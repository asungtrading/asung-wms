-- lat-1-verify.sql — 입고 완료가 공급처 Latest(product_supplier.cost) · last_supplied 를 고친다(판정 626 · 627):
--   T1 동일성(옛 확정 = 새 확정 — 원장 · 레이어 · 반환(새 열쇠 빼고) · 옛 함수는 product_supplier 를 안 건드린다 · 시험 갈래) · T2 갈래마다 한 줄(2.50 → cost · 연결 없음 · 꺼진 연결 · 0 원 · 통화 다름 · 더 새 공급일) · fixed_cost 무변 · po_price_history 에 할인 뒤 값
--   T3 먼저 반영(post_now)이 고치고 확정은 unchanged · T4 문(receiving 없는 직원 거부 · 도우미 직접 호출 42501) · Z1 셸 · 원장 창구 md5 무변
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261022191756_lat_1_receipt_updates_latest.sql -f supabase/tests/lat-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T1 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 8 − 3 + 1 = **6** · MISMATCH 0
--   가짜 재료만(LAT1 — 공급처 A(CAD) · 제품 P1 ~ P7 · 연결 · PO A · B(직접 insert · PO-99901 · 99902 · 시퀀스 무접촉) · 확정 인보이스(할인 10%) · draft 입고 + 작업 줄 · 직원 W(receiving · purchasing) · N(sales)) · 전부 되감긴다

\echo '── db_role · schema_migrations'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261022191756' \gset
select :n_applied as schema_migrations_rows_for_20261022191756;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_role(p_role text, p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then
  reset role;
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('po_receipt_confirm', 'po_receipt_post_now', 'inv_post_receipt', 'inv_layer_post_receipt', 'po_receipt_keep_open', 'inv_layer_post_charge', 'po_receipt_over_bins', 'wms_recv_state') $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'cb=' || (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_confirm_by')
      || ' pn=' || (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_post_now_by')
      || ' helper=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_latest_apply') $$;
-- 공급처 연결 자취 — sku:cost/fixed/last_supplied/active
create function pg_temp.ps_trace(p_sup uuid) returns text language sql security definer as $$
  select string_agg(pr.sku || ':' || coalesce(trim_scale(ps.cost)::text, '-') || '/' || coalesce(trim_scale(ps.fixed_cost)::text, '-') || '/' || coalesce(ps.last_supplied::text, '-') || '/' || ps.is_active::text, ' ' order by pr.sku)
  from public.product_supplier ps join public.product pr on pr.id = ps.product_id where ps.supplier_id = p_sup $$;
-- 원장 · 레이어 자취(이 입고 번호)
create function pg_temp.led_trace(p_rcv text) returns text language sql security definer as $$
  select 'ledger=' || (select count(*) || '/' || coalesce(trim_scale(sum(qty_delta))::text, '0') || '/' || coalesce(string_agg(sku || '=' || trim_scale(qty_delta), ',' order by sku, line_ref), '-') from public.inv_ledger where source = 'ims' and doc_number = p_rcv)
      || ' layers=' || (select count(*) || '/' || coalesce(trim_scale(sum(qty))::text, '0') || '/' || coalesce(trim_scale(round(sum(qty * unit_cost), 4))::text, '0') from public.inv_layer where doc_number = p_rcv) $$;
-- 반환 정규화 — 새 열쇠(latest_*) · 경고의 latest_ 항목 · 시각 · uuid 를 뺀다 · ledger 열쇠는 뺀다(레이어 id 가 실행마다 다르다 — 원장 · 레이어 동일성은 led_trace 가 따로 받친다)
create function pg_temp.canon(p jsonb) returns text language sql as $$
  select regexp_replace(regexp_replace(regexp_replace(((p - 'latest_updated' - 'latest_skipped' - 'confirmed_at' - 'ledger')
           || jsonb_build_object('warnings', (select coalesce(jsonb_agg(w order by w), '[]'::jsonb) from jsonb_array_elements_text(p->'warnings') w where w not like 'latest_%')))::text,
           '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g'), '"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+"', '"T"', 'g'), '"id": [0-9]+', '"id": 0', 'g') $$;
-- 옛 판 동일성: 서브트랜잭션 안에서 입고 A 를 확정하고 반환 · 원장 · 연결 자취를 꺼낸 뒤 되감는다(쓰기 0)
create function pg_temp.scn(p_staff uuid, p_rcv uuid, p_rcv_no text, p_sup uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  begin
    v := public.po_receipt_confirm_by(p_staff, p_rcv);
    raise exception using errcode = 'P7777', message = jsonb_build_object('ret', pg_temp.canon(v), 'warn', v->'warnings', 'led', pg_temp.led_trace(p_rcv_no), 'ps', pg_temp.ps_trace(p_sup), 'has_latest', v ? 'latest_updated')::text;
  exception when sqlstate 'P7777' then return sqlerrm::jsonb;
  when others then return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
  end;
end $$;

\echo '── M0) 가짜 재료'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'lat1-w@test.invalid', 'LAT1 W', 'manager', '["ims","receiving","purchasing"]', '{}') returning auth_user_id::text as w_uid, id::text as w_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'lat1-n@test.invalid', 'LAT1 N', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as n_uid \gset
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
\set n '{"sub":"' :n_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as usd from public.ref_currency where code = 'USD' \gset
select w.id::text as wh, w.name as whname from public.ref_warehouse w where w.is_active order by w.name limit 1 \gset
select b.id::text as bin, b.name as binname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select (public.ims_today() - 3)::text as rcv_on \gset
set local session_replication_role = replica;
insert into public.supplier (name, source, is_active, payment_term_name, account_payable_code, currency_id) values ('LAT1 Supplier A', 'manual', true, 'Due on receipt', '_62_', :'cad'::uuid) returning id::text as sup \gset
insert into public.product (sku, name, source, is_active, sellable) values ('LAT1-P1', 'LAT1 link 1.00 fixed 9', 'manual', true, true) returning id::text as p1 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('LAT1-P2', 'LAT1 no link', 'manual', true, true) returning id::text as p2 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('LAT1-P3', 'LAT1 link inactive', 'manual', true, true) returning id::text as p3 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('LAT1-P4', 'LAT1 free line', 'manual', true, true) returning id::text as p4 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('LAT1-P5', 'LAT1 newer supply exists', 'manual', true, true) returning id::text as p5 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('LAT1-P6', 'LAT1 link in USD', 'manual', true, true) returning id::text as p6 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('LAT1-P7', 'LAT1 post-now', 'manual', true, true) returning id::text as p7 \gset
insert into public.product_supplier (product_id, supplier_id, is_active, is_default, source, fixed_cost, cost, last_supplied, currency_id, supplier_sku) values
  (:'p1'::uuid, :'sup'::uuid, true,  true,  'manual', 9, 1.00, public.ims_today() - 30, :'cad'::uuid, 'S-P1'),
  (:'p3'::uuid, :'sup'::uuid, false, false, 'manual', null, 1.00, public.ims_today() - 30, :'cad'::uuid, 'S-P3'),
  (:'p4'::uuid, :'sup'::uuid, true,  true,  'manual', null, 1.00, public.ims_today() - 30, :'cad'::uuid, 'S-P4'),
  (:'p5'::uuid, :'sup'::uuid, true,  true,  'manual', null, 1.00, public.ims_today() - 1,  :'cad'::uuid, 'S-P5'),
  (:'p6'::uuid, :'sup'::uuid, true,  true,  'manual', null, 1.00, public.ims_today() - 30, :'usd'::uuid, 'S-P6'),
  (:'p7'::uuid, :'sup'::uuid, true,  true,  'manual', null, 1.00, public.ims_today() - 30, :'cad'::uuid, 'S-P7');
-- PO A(확정 · CAD) · 줄 여섯 · 확정 인보이스(할인 10%) · draft 입고 + 작업 줄(칸 있음 · 수량 = 인보이스)
insert into public.po (po_number, supplier_id, currency_id, status, ship_to_warehouse_id, order_date, confirmed_at, created_by) values ('PO-99901', :'sup'::uuid, :'cad'::uuid, 'confirmed', :'wh'::uuid, public.ims_today() - 10, now(), :'w_id'::uuid) returning id::text as po_a \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values
  (:'po_a'::uuid, 1, :'p1'::uuid, 10, 1.00), (:'po_a'::uuid, 2, :'p2'::uuid, 5, 0), (:'po_a'::uuid, 3, :'p3'::uuid, 4, 1.00),
  (:'po_a'::uuid, 4, :'p4'::uuid, 3, 0), (:'po_a'::uuid, 5, :'p5'::uuid, 2, 1.00), (:'po_a'::uuid, 6, :'p6'::uuid, 1, 1.00);
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, total_amount, status, confirmed_at, confirmed_by, doc_kind, created_by) values (:'sup'::uuid, 'LAT1-INV-A', public.ims_today() - 5, :'cad'::uuid, 0, 'confirmed', now(), :'w_id'::uuid, 'invoice', :'w_id'::uuid) returning id::text as inv_a \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable)
  select :'inv_a'::uuid, pl.line_no, 'goods', pl.id, pl.qty_ea, case pl.line_no when 1 then 2.50 when 2 then 2.00 when 3 then 2.00 when 4 then 0 when 5 then 3.00 when 6 then 4.00 end, true from public.po_line pl where pl.po_id = :'po_a'::uuid;
insert into public.po_invoice_discount (po_invoice_id, seq, name, percent) values (:'inv_a'::uuid, 1, 'LAT1 10', 10);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-LAT1A', :'po_a'::uuid, :'wh'::uuid, :'rcv_on'::date, 'draft', :'w_id'::uuid) returning id::text as rcv_a \gset
insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at, putaway_by, putaway_at)
  select :'rcv_a'::uuid, pl.id, pl.qty_ea, :'bin'::uuid, true, 'manual', :'w_id'::uuid, now(), :'w_id'::uuid, now() from public.po_line pl where pl.po_id = :'po_a'::uuid;
-- PO B — P7 한 줄 · 먼저 반영 → 확정
insert into public.po (po_number, supplier_id, currency_id, status, ship_to_warehouse_id, order_date, confirmed_at, created_by) values ('PO-99902', :'sup'::uuid, :'cad'::uuid, 'confirmed', :'wh'::uuid, public.ims_today() - 10, now(), :'w_id'::uuid) returning id::text as po_b \gset
insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (:'po_b'::uuid, 1, :'p7'::uuid, 5, 1.00) returning id::text as pl_b \gset
insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, total_amount, status, confirmed_at, confirmed_by, doc_kind, created_by) values (:'sup'::uuid, 'LAT1-INV-B', public.ims_today() - 5, :'cad'::uuid, 0, 'confirmed', now(), :'w_id'::uuid, 'invoice', :'w_id'::uuid) returning id::text as inv_b \gset
insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (:'inv_b'::uuid, 1, 'goods', :'pl_b'::uuid, 5, 1.80, true);
insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values ('RCV-LAT1B', :'po_b'::uuid, :'wh'::uuid, :'rcv_on'::date, 'draft', :'w_id'::uuid) returning id::text as rcv_b \gset
insert into public.po_receipt_work (receipt_id, po_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at, putaway_by, putaway_at) values (:'rcv_b'::uuid, :'pl_b'::uuid, 5, :'bin'::uuid, true, 'manual', :'w_id'::uuid, now(), :'w_id'::uuid, now()) returning id::text as work_b \gset
set local session_replication_role = origin;
select pg_temp.ps_trace(:'sup'::uuid) as ps0, pg_temp.fns() as fns_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff W · N · supplier A · P1 ~ P7 · links (%s) · PO-99901 (6 lines · invoice 10%%) · PO-99902 (P7) · draft receipts dated %s', :'ps0', :'rcv_on'),
  :'w_id' <> '' and :'rcv_a' <> '' and :'rcv_b' <> '' and :'work_b' <> ''
  and :'ps0' = format('LAT1-P1:1/9/%s/true LAT1-P3:1/-/%s/false LAT1-P4:1/-/%s/true LAT1-P5:1/-/%s/true LAT1-P6:1/-/%s/true LAT1-P7:1/-/%s/true', public.ims_today() - 30, public.ims_today() - 30, public.ims_today() - 30, public.ims_today() - 1, public.ims_today() - 30, public.ims_today() - 30),
  :'ps0');

\if :{?mig}
\echo '── S0 · D-pre) 결함 판 — 옛 몸 둘 · 도우미 없음 · 옛 확정(되감김)의 반환 · 원장 · 연결 자취'
select pg_temp.scn(:'w_id'::uuid, :'rcv_a'::uuid, 'RCV-LAT1A', :'sup'::uuid)::text as pre \gset
select pg_temp.chk(format('S0 before the trial: confirm_by = rcv-3 (d2734ecd…) · post_now_by = rcv-1b (30ab6c2a…) · no helper · old confirm ran (%s) · old function leaves product_supplier unchanged · no latest_updated key', left(pg_temp.j(:'pre')->>'led', 60)),
  :'gate_before' = 'cb=d2734ecd59053597f3c91cf4c6b52b4f pn=30ab6c2aeb3a91903479d986eb028719 helper=0' and :n_applied = 0
  and not (pg_temp.j(:'pre') ? 'err') and pg_temp.j(:'pre')->>'ps' = :'ps0' and not (pg_temp.j(:'pre')->>'has_latest')::boolean and (pg_temp.j(:'pre')->>'led') like 'ledger=6/%',
  format('%s | %s', :'gate_before', left(:'pre', 600)));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: shells · ledger · layer · keep_open · over_bins md5 unchanged · product_supplier untouched by the trial itself', pg_temp.fns() = :'fns_before' and pg_temp.ps_trace(:'sup'::uuid) = :'ps0', format('before %s | after %s', left(:'fns_before', 300), left(pg_temp.fns(), 300)));
\endif

select (pg_temp.gate_state() = 'cb=0437dd9fa83c9320f032f5db5ab3b889 pn=a246129b612853f2411594e7acc76d35 helper=1') as landed \gset
\if :landed
\echo '── G1) 실물'
select pg_temp.chk('G1 confirm_by · post_now_by bodies = lat-1 · helper exists (no execute for public · anon · authenticated · service_role) · re-issued ACL unchanged (postgres · service_role) · definer',
  pg_temp.gate_state() = 'cb=0437dd9fa83c9320f032f5db5ab3b889 pn=a246129b612853f2411594e7acc76d35 helper=1'
  and not has_function_privilege('authenticated', 'public.po_receipt_latest_apply(uuid, uuid, uuid)', 'execute') and not has_function_privilege('anon', 'public.po_receipt_latest_apply(uuid, uuid, uuid)', 'execute') and not has_function_privilege('service_role', 'public.po_receipt_latest_apply(uuid, uuid, uuid)', 'execute')
  and (select string_agg(p.proname || ':' || p.proacl::text || ':' || p.prosecdef::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm_by', 'po_receipt_post_now_by'))
      = 'po_receipt_confirm_by:{postgres=X/postgres,service_role=X/postgres}:true po_receipt_post_now_by:{postgres=X/postgres,service_role=X/postgres}:true',
  pg_temp.gate_state());

\echo '── T1 · T2) 입고 A 확정(새 판) — 동일성(원장 · 레이어 · 반환) · Latest 갈래 여섯'
select public.po_receipt_confirm_by(:'w_id'::uuid, :'rcv_a'::uuid)::text as post \gset
select pg_temp.ps_trace(:'sup'::uuid) as ps1, pg_temp.led_trace('RCV-LAT1A') as led1 \gset
\if :{?mig}
select pg_temp.chk(format('T1 identity: new confirm = old confirm — ledger · layers trace (%s) · return minus new keys · ledger key (ids differ per run) · warnings minus latest_*', :'led1'),
  pg_temp.j(:'pre')->>'led' = :'led1' and pg_temp.j(:'pre')->>'ret' = pg_temp.canon(pg_temp.j(:'post')),
  format('old led %s | new led %s | differing keys: %s', pg_temp.j(:'pre')->>'led', :'led1',
         (select string_agg(k || ': ' || left(coalesce(a.v::text, '∅'), 300) || ' ≠ ' || left(coalesce(b.v::text, '∅'), 300), ' || ')
            from (select key as k, value as v from jsonb_each((pg_temp.j(:'pre')->>'ret')::jsonb)) a full join (select key as k, value as v from jsonb_each(pg_temp.canon(pg_temp.j(:'post'))::jsonb)) b using (k)
           where a.v is distinct from b.v)));
\endif
select pg_temp.chk(format('T2 after confirm A (received %s): P1 1→2.50 (gross · not 2.25 net) · last_supplied → %s · fixed 9 kept · P3 (inactive link) 1→2.00 · P2 no link → warning · P4 free → skipped · P5 newer supply → skipped (kept %s) · P6 USD link vs CAD invoice → skipped · po_price_history P1 net = %s → %s', :'rcv_on', :'rcv_on', public.ims_today() - 1, round(2.50 * 0.9, 6), :'ps1'),
  :'ps1' = format('LAT1-P1:2.5/9/%s/true LAT1-P3:2/-/%s/false LAT1-P4:1/-/%s/true LAT1-P5:1/-/%s/true LAT1-P6:1/-/%s/true LAT1-P7:1/-/%s/true', :'rcv_on', :'rcv_on', public.ims_today() - 30, public.ims_today() - 1, public.ims_today() - 30, public.ims_today() - 30)
  and (select string_agg((u->>'sku') || ':' || trim_scale((u->>'old_cost')::numeric) || '→' || trim_scale((u->>'new_cost')::numeric) || ':' || (u->>'new_last_supplied') || ':' || (u->>'link_active'), ' ' order by u->>'sku') from jsonb_array_elements(pg_temp.j(:'post')->'latest_updated') u)
      = format('LAT1-P1:1→2.5:%s:true LAT1-P3:1→2:%s:false', :'rcv_on', :'rcv_on')
  and (select string_agg((s->>'sku') || ':' || (s->>'reason'), ' ' order by s->>'sku') from jsonb_array_elements(pg_temp.j(:'post')->'latest_skipped') s) = 'LAT1-P2:no_link LAT1-P4:free LAT1-P5:newer_supply_exists LAT1-P6:currency_mismatch'
  and (pg_temp.j(:'post')->'warnings') ? 'latest_no_link:LAT1-P2' and (pg_temp.j(:'post')->'warnings') ? 'latest_currency_mismatch:LAT1-P6' and (pg_temp.j(:'post')->'warnings') ? 'latest_older_skipped:LAT1-P5'
  and (select round(h.net_unit, 6) from public.po_price_history h where h.sku = 'LAT1-P1') = round(2.50 * 0.9, 6) and (select h.gross_unit from public.po_price_history h where h.sku = 'LAT1-P1') = 2.50,
  format('ps %s | updated %s | skipped %s | warnings %s', :'ps1', left((pg_temp.j(:'post')->'latest_updated')::text, 400), left((pg_temp.j(:'post')->'latest_skipped')::text, 300), (pg_temp.j(:'post')->'warnings')::text));

\echo '── T3 · T4) 입고 B — 문(N 거부) · 먼저 반영(post_now · W)이 P7 을 1→1.80 · 그 뒤 확정(po_receipt_confirm 셸 · W)은 unchanged · 도우미 직접 호출 42501'
select pg_temp.as_user(:'n', format('select public.po_receipt_post_now(%L::uuid, %L::jsonb, true)::text', :'rcv_b', jsonb_build_array(:'work_b'))) as t3n \gset
select pg_temp.as_user(:'w', format('select public.po_receipt_post_now(%L::uuid, %L::jsonb, true)::text', :'rcv_b', jsonb_build_array(:'work_b'))) as t3p \gset
select pg_temp.ps_trace(:'sup'::uuid) as ps2 \gset
select pg_temp.as_user(:'n', format('select public.po_receipt_confirm(%L::uuid)::text', :'rcv_b')) as t3cn \gset
select pg_temp.as_user(:'w', format('select public.po_receipt_confirm(%L::uuid)::text', :'rcv_b')) as t3c \gset
select pg_temp.ps_trace(:'sup'::uuid) as ps3 \gset
select pg_temp.as_role('authenticated', :'w', format('select public.po_receipt_latest_apply(%L::uuid, null, %L::uuid)::text', :'rcv_b', :'w_id')) as t4h \gset
select pg_temp.chk(format('T3 post-now by W: P7 1→1.80 · last_supplied %s · then confirm by W: latest_updated [] · skipped P7 unchanged · cost still 1.80 → %s', :'rcv_on', left(:'ps3', 200)),
  :'t3n' like 'ERR P0001:%receiving%' and :'t3cn' like 'ERR P0001:%receiving%'
  and (pg_temp.j(:'t3p')->>'committed')::boolean and (select string_agg((u->>'sku') || ':' || trim_scale((u->>'old_cost')::numeric) || '→' || trim_scale((u->>'new_cost')::numeric), ' ') from jsonb_array_elements(pg_temp.j(:'t3p')->'latest_updated') u) = 'LAT1-P7:1→1.8'
  and :'ps2' like format('%%LAT1-P7:1.8/-/%s/true', :'rcv_on')
  and pg_temp.j(:'t3c')->>'status' = 'confirmed' and jsonb_array_length(pg_temp.j(:'t3c')->'latest_updated') = 0
  and (select string_agg((s->>'sku') || ':' || (s->>'reason'), ' ') from jsonb_array_elements(pg_temp.j(:'t3c')->'latest_skipped') s) = 'LAT1-P7:unchanged'
  and :'ps3' = :'ps2' and :'t4h' like 'ERR 42501:%',
  format('N %s | post %s | N confirm %s | confirm %s | helper %s', left(:'t3n', 120), left(:'t3p', 400), left(:'t3cn', 120), left(:'t3c', 400), left(:'t4h', 120)));
\else
select pg_temp.chk('G1 ~ T4 skipped: lat-1 not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 무접촉'
select pg_temp.chk('Z1 shells · ledger · layer · keep_open · over_bins · wms_recv_state md5 unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', left(:'fns_before', 300), left(pg_temp.fns(), 300)));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0'
select (select count(*) from public.supplier where name like 'LAT1 %') + (select count(*) from public.product where sku like 'LAT1-%') + (select count(*) from public.ims_staff where email like 'lat1-%') + (select count(*) from public.po where po_number in ('PO-99901', 'PO-99902')) + (select count(*) from public.inv_ledger where doc_number like 'RCV-LAT1%') as leftovers;
