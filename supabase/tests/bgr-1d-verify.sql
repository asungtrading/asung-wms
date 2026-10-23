-- bgr-1d-verify.sql — B급 칸 ④ 인쇄 Final sale · 반품 경고 · 반품 칸 · surcharge 없음(판정 640 · 648 · 649 · 650):
--   S0 결함 판 · G0 손대지 않은 함수 무변 · T 옛 = 새(B급이 끼지 않은 입력 — catalog · 크레딧 미리 보기 · 정상 POS 인보이스 doc_data) ·
--   D1 surcharge(B급 줄 비움 · 정상 줄 0.50 · clear → 다시 · patch IM638 · 합계 surcharge = 정상 줄 몫) · D2 doc_data final_sale · catalog · D3 prepare(final_sale · 칸 기본) ·
--   D4 · D5 발행(경고 final_sale · B 로 · 정상 줄을 빈 B2 로 · 죽은 값 지움 · 잔고 · 값) + 거부(다른 창고 · 꺼진 B급 칸) + 칸이 꺼졌을 때 bgrade_bin_gone ·
--   D6 크레딧 취소(반대 사건 · 가드 통과) · D7 가격 조정 경고 · D8 1a · 1b · 1c 착지 · Z1
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261023143239_bgr_1d_final_sale_returns.sql -f supabase/tests/bgr-1d-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T 셋은 없고 P0c 한 줄
--   기대(2026-10-23 시험 통과 실행 · 찍힌 OK 줄을 셈): 시험 갈래 OK 13(M0 S0 G0 T D1 ~ D8 Z1) · MISMATCH 0 · begin ~ rollback 약 4 초 / 확인 갈래 OK 11(M0 P0c D1 ~ D8 Z1) · MISMATCH 0
--   ⭐ 잠금 규칙: 첫 줄 lock_timeout 3s · 가짜 재료만 · 끝에 begin ~ rollback 초 · alter · lock · truncate · drop 없음
--   ⚠️ 번호: POS Finish 가 인보이스 번호 · 발행이 크레딧 번호를 당긴다(실물 발행을 거쳐야 원장 · 가드를 본다) — 트랜잭션을 몇 초로 두고 끝에서 셋(오더 · 인보이스 · 크레딧)을 greatest(실제 최대, 시작 값)
--   가짜 재료 = 직원 하나 · 손님 · 토론토 칸 넷(BGRD-N · B · B2 · BX 꺼진 B급) + 에드먼턴 B급 칸 하나 · 제품 P(Wholesale 10.00 · tariff 0.50 그룹) · 원장(N 18 · B 2) · B급 값(B 5.00 · B2 4.00 죽은 값)

\echo '── db_role · schema_migrations · 시퀀스 시작 값'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261023143239' \gset
select :n_applied as schema_migrations_rows_for_20261023143239;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset

begin;
set local lock_timeout = '3s';
select clock_timestamp() as tb, now() as t0 \gset

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
create function pg_temp.try_undo(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin
    if p_claims is not null then perform set_config('request.jwt.claims', p_claims, true); end if;
    execute p_sql into v;
    raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
  exception when sqlstate 'P7777' then return 'PASS: ' || sqlerrm;
  end;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('inv_post_credit', 'so_credit_cancel', 'doc_data', 'doc_data_credit', 'doc_data_so', 'doc_data_ship_ready', 'so_line_add', 'so_line_update', 'so_tax_preview', 'so_invoice_issue',
                     'so_line_surcharge_defaults', 'so_surcharge_group_save', 'bgrade_price_set', 'bgrade_stock', 'ims_last_bin', 'so_pick_plan', 'inv_post_sale') $$;
create function pg_temp.real_rows(p_t0 timestamptz) returns text language plpgsql security definer as $$
begin
  return 'so=' || (select count(*) || '/' || md5(coalesce(string_agg(s.id::text || s.status, ',' order by s.id), '')) from public.so s where s.created_at < p_t0)
      || ' inv=' || (select count(*) || '/' || md5(coalesce(string_agg(i.id::text || i.status, ',' order by i.id), '')) from public.so_invoice i where i.created_at < p_t0)
      || ' cr=' || (select count(*) || '/' || md5(coalesce(string_agg(c.id::text || c.status, ',' order by c.id), '')) from public.so_credit c where c.created_at < p_t0)
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where created_at < p_t0)
      || ' bprice=' || (select count(*) || '/' || md5(coalesce(string_agg(b.id::text || b.price, ',' order by b.id), '')) from public.bgrade_price b where b.created_at < p_t0)
      || ' bins=' || (select count(*) || '/' || md5(coalesce(string_agg(b.id::text || b.is_bgrade || b.is_active, ',' order by b.id), '')) from public.ref_bin b where b.created_at < p_t0);
end $$;
create function pg_temp.lines(p_so uuid) returns text language sql as $$
  select coalesce(string_agg(format('L%s %s@%s sc=%s%s', l.line_no, trim_scale(l.qty_ordered), trim_scale(l.unit_price), coalesce(trim_scale(l.surcharge_amount)::text, '-'), case when l.bgrade_bin_id is not null then '[B]' else '' end), ' ' order by l.line_no), '-') from public.so_line l where l.so_id = p_so $$;
create function pg_temp.bal(p_wh text) returns text language sql as $$
  select string_agg(format('%s=%s', v.bin, trim_scale(v.qty)), ' ' order by v.bin) from public.inv_balance v where v.warehouse = p_wh and v.sku = 'BGRD-P' $$;
create function pg_temp.bgs(p_claims text, p_wh uuid) returns text language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v := public.bgrade_stock(p_wh);
  return coalesce((select string_agg(format('%s %s@%s', r->>'bin', r->>'qty', coalesce(r->>'price', '-')), ' ' order by r->>'bin') from jsonb_array_elements(v->'rows') r where r->>'bin' like 'BGRD-%'), '-');
end $$;

\echo '── M0) 가짜 재료 · POS 오더 T(정상 줄만) → 확정 → Finish → 인보이스 T'
select id::text as tor, name as torname from public.ref_warehouse where id = '045e4ca6-b7a9-446e-9e6a-a5a0db56d456' and is_active \gset
select id::text as edm from public.ref_warehouse where is_active and name ilike '%edmonton%' \gset
select pg_temp.real_rows(:'t0'::timestamptz) as real_before, pg_temp.fns() as fns_before \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgrd-w@test.invalid', 'BGRD W', 'manager', '["ims","sales","stock_adjust"]', '{}') returning auth_user_id::text as w_uid, id::text as w_id \gset
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRD-N', :'tor'::uuid, 'manual', true) returning id::text as bin_n \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRD-B', :'tor'::uuid, 'manual', true) returning id::text as bin_b \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRD-B2', :'tor'::uuid, 'manual', true) returning id::text as bin_b2 \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRD-BX', :'tor'::uuid, 'manual', true) returning id::text as bin_bx \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRD-EB', :'edm'::uuid, 'manual', true) returning id::text as bin_eb \gset
update public.ref_bin set is_bgrade = true where id in (:'bin_b'::uuid, :'bin_b2'::uuid, :'bin_bx'::uuid, :'bin_eb'::uuid);
update public.ref_bin set is_active = false where id = :'bin_bx'::uuid;
set local session_replication_role = replica;
insert into public.so_surcharge_group (name, surcharge_amount, is_active, source) values ('BGRD tariff', 0.50, true, 'manual') returning id::text as grp \gset
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name)
  values ('BGRD C1', 'manual', 'Wholesale', :'tor'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c1 \gset
insert into public.product (sku, name, source, is_active, sellable, surcharge_group_id) values ('BGRD-P', 'BGRD Product', 'manual', true, true, :'grp'::uuid) returning id::text as pid_p \gset
insert into public.product_price (product_id, tier_id, price, source) values (:'pid_p'::uuid, '161cdb6d-9c34-476a-87bd-93a9b372f315'::uuid, 10.00, 'manual');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today() - 30, 1, 'BGRD-P', :'torname', 'BGRD-N', 18, 'po_in', 'purchase', 'PO-BGRD', 'bgrd-n', 'manual'),
  (public.ims_today() - 30, 1, 'BGRD-P', :'torname', 'BGRD-B', 2, 'po_in', 'purchase', 'PO-BGRD', 'bgrd-b', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('BGRD-P', :'torname', 'purchase', 'PO-BGRD', 'bgrd-p', public.ims_today() - 30, true, 20, 2.5, 'po_line');
insert into public.bgrade_price (bin_id, product_id, price, set_by) values (:'bin_b'::uuid, :'pid_p'::uuid, 5.00, :'w_id'::uuid), (:'bin_b2'::uuid, :'pid_p'::uuid, 4.00, :'w_id'::uuid);
set local session_replication_role = origin;
create function pg_temp.mk_pos(p_claims text, p_cust uuid, p_wh uuid, p_note text, p_rule uuid, p_rule_name text) returns text language plpgsql as $$
declare v uuid;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v := (public.so_create(p_cust, 'pos', 'pos', p_wh, p_note)->>'id')::uuid;
  execute 'set local session_replication_role = replica';
  update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v;
  execute 'set local session_replication_role = origin';
  return v::text;
end $$;
select pg_temp.mk_pos(:'w', :'c1'::uuid, :'tor'::uuid, 'bgr-1d T', :'r13'::uuid, :'r13_name') as so_t \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id''', :'so_t', :'pid_p')) as lt \gset
select pg_temp.as_user(:'w', format('select public.so_pos_confirm(%L::uuid)->>''status''', :'so_t')) as t_conf \gset
select pg_temp.as_user(:'w', format('select public.so_pos_finish(%L::uuid, true)->>''invoice_id''', :'so_t')) as inv_t \gset
select (select id::text from public.so_invoice_line where invoice_id = :'inv_t'::uuid and kind = 'product') as il_t \gset
\set p_t '{"invoice_id":"' :inv_t '","reason":"customer_return","warehouse_id":"' :tor '","lines":[{"kind":"product","so_invoice_line_id":"' :il_t '","qty_returned":1}]}'
select pg_temp.chk(format('M0 staff · customer · bins BGRD-N/B/B2/BX(off)/EB(Edmonton) · P Wholesale 10.00 + tariff 0.50 · N 18 · B 2 @5.00 · B2 dead 4.00 · POS order T %s → invoice', pg_temp.lines(:'so_t'::uuid)),
  :'t_conf' = 'confirmed' and :'inv_t' ~ '^[0-9a-f-]{36}$' and :'il_t' ~ '^[0-9a-f-]{36}$' and :'real_before' <> '', format('%s | %s', :'t_conf', :'inv_t'));

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) · 옛 출력 담기'
select (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_credit_issue' and prosrc ~ 'final_sale') as s0_fs \gset
select pg_temp.as_user(:'w', 'select public.doc_field_catalog(''final_invoice'')::text') as o_cat, pg_temp.as_user(:'w', 'select public.doc_field_catalog(''ship_ready'')::text') as o_cat2,
       pg_temp.as_user(:'w', format('select public.so_credit_prepare(%L::uuid)::text', :'inv_t')) as o_prep,
       pg_temp.as_user(:'w', format('select public.so_credit_issue(%L::jsonb, false)::text', :'p_t')) as o_iss,
       pg_temp.as_user(:'w', format('select public.doc_data(''final_invoice'', %L::jsonb)::text', jsonb_build_object('invoice_id', :'inv_t'))) as o_doc \gset
select pg_temp.chk('S0 before the trial: no final_sale anywhere · old outputs captured (catalog ×2 · credit prepare · credit preview · invoice doc data)',
  :s0_fs = 0 and :n_applied = 0 and :'o_cat' like '{%' and :'o_prep' like '{%' and :'o_iss' like '{%' and :'o_doc' like '{%' and not exists (select 1 from jsonb_array_elements(pg_temp.j(:'o_doc')->'docs'->0->'orders'->0->'lines') l where l ? 'final_sale'),
  format('fs %s applied %s cat %s prep %s iss %s doc %s nofs %s | %s', :s0_fs, :n_applied, :'o_cat' like '{%%', :'o_prep' like '{%%', :'o_iss' like '{%%', :'o_doc' like '{%%', true, left(:'o_iss', 300)));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: credit posting · cancel · other doc data · line add · update · tax preview · surcharge · 1a · 1b functions not re-issued are unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', :'fns_before', pg_temp.fns()));
\echo '── T) 옛 = 새 — B급이 끼지 않은 입력(새 열쇠만 더해졌다)'
select pg_temp.as_user(:'w', 'select public.doc_field_catalog(''final_invoice'')::text') as n_cat, pg_temp.as_user(:'w', 'select public.doc_field_catalog(''ship_ready'')::text') as n_cat2,
       pg_temp.as_user(:'w', format('select public.so_credit_prepare(%L::uuid)::text', :'inv_t')) as n_prep,
       pg_temp.as_user(:'w', format('select public.so_credit_issue(%L::jsonb, false)::text', :'p_t')) as n_iss,
       pg_temp.as_user(:'w', format('select public.doc_data(''final_invoice'', %L::jsonb)::text', jsonb_build_object('invoice_id', :'inv_t'))) as n_doc \gset
select pg_temp.chk('T old = new without a B-grade line: catalog final_invoice = old + orders.lines.final_sale · ship_ready same · prepare = old + final_sale false + restock_bgrade_bin_gone false per product line · credit preview same · invoice doc data = old + final_sale false (printed_at stripped)',
  (select jsonb_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat')->'allowed') x) = (select jsonb_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat')->'allowed') union all select 'orders.lines.final_sale') t(x))
  and pg_temp.j(:'n_cat2') = pg_temp.j(:'o_cat2')
  and jsonb_set(pg_temp.j(:'n_prep'), '{lines}', (select jsonb_agg(case when e ? 'final_sale' then e - 'final_sale' - 'restock_bgrade_bin_gone' else e end order by o) from jsonb_array_elements(pg_temp.j(:'n_prep')->'lines') with ordinality t(e, o))) = pg_temp.j(:'o_prep')
  and (select bool_and(e->>'final_sale' = 'false' and e->>'restock_bgrade_bin_gone' = 'false') from jsonb_array_elements(pg_temp.j(:'n_prep')->'lines') e where e->>'kind' = 'product')
  and pg_temp.j(:'n_iss') = pg_temp.j(:'o_iss')
  and (pg_temp.j(:'n_doc')->'docs'->0 #- '{doc,printed_at}') = (select jsonb_set(pg_temp.j(:'o_doc')->'docs'->0 #- '{doc,printed_at}', '{orders}', (select jsonb_agg(jsonb_set(o, '{lines}', (select jsonb_agg(l || '{"final_sale": false}'::jsonb order by lo) from jsonb_array_elements(o->'lines') with ordinality u(l, lo))) order by oo) from jsonb_array_elements(pg_temp.j(:'o_doc')->'docs'->0->'orders') with ordinality v(o, oo))))
  and (pg_temp.j(:'n_doc') - 'docs') = (pg_temp.j(:'o_doc') - 'docs'),
  format('%s || %s || %s', left(:'n_prep', 300), left(:'n_iss', 200), left(:'n_doc', 300)));
\else
select pg_temp.chk('P0c confirm run: migration 20261023143239 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_credit_issue' and prosrc ~ 'final_sale') as landed \gset
\if :landed
\echo '── D1) surcharge — B급 줄 비움 · 정상 줄 0.50 · clear → 다시 · 다시 B급 · patch IM638 · 합계'
select pg_temp.mk_pos(:'w', :'c1'::uuid, :'tor'::uuid, 'bgr-1d D', :'r13'::uuid, :'r13_name') as so1 \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id''', :'so1', :'pid_p')) as lb \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set(%L::uuid, %L::uuid)->>''action''', :'lb', :'bin_b')) as d1a \gset
select pg_temp.lines(:'so1'::uuid) as d1a_l \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_clear(%L::uuid)->>''action''', :'lb')) as d1b \gset
select pg_temp.lines(:'so1'::uuid) as d1b_l \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set(%L::uuid, %L::uuid)->>''action''', :'lb', :'bin_b')) as d1c \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id''', :'so1', :'pid_p')) as ln \gset
select pg_temp.as_user(:'w', format('select public.so_line_update(%L::uuid, ''{"surcharge_amount": 0.5, "surcharge_label": "BGRD tariff"}''::jsonb)::text', :'lb')) as d1d \gset
select pg_temp.as_user(:'w', format('select public.so_tax_preview(%L::uuid, public.ims_today(), null, ''ordered'')->''totals''', :'so1')) as d1t \gset
select pg_temp.lines(:'so1'::uuid) as d1_l \gset
select pg_temp.chk(format('D1 set → %s · clear → %s · set again + normal line → %s · surcharge patch on the B line refused · preview totals %s', :'d1a_l', :'d1b_l', :'d1_l', left(:'d1t', 300)),
  :'d1a' = 'set' and :'d1a_l' = 'L1 1@5 sc=-[B]' and :'d1b' = 'cleared' and :'d1b_l' = 'L1 1@10 sc=0.5' and :'d1c' = 'set' and :'d1_l' = 'L1 1@5 sc=-[B] L2 1@10 sc=0.5'
  and :'d1d' like 'ERR IM638: Line 1 is a B-grade line%' and :'d1t' ~ '"surcharge[a-z_]*": 0\.50',
  format('%s | %s | %s | %s', :'d1a', :'d1b', :'d1c', :'d1d'));
select pg_temp.as_user(:'w', format('select public.so_pos_confirm(%L::uuid)->>''status''', :'so1')) as d1e \gset
select pg_temp.as_user(:'w', format('select public.so_pos_finish(%L::uuid, true)->>''invoice_id''', :'so1')) as inv1 \gset
select (select id::text from public.so_invoice_line il where il.invoice_id = :'inv1'::uuid and il.kind = 'product' and il.so_line_id = :'lb'::uuid) as il_b,
       (select id::text from public.so_invoice_line il where il.invoice_id = :'inv1'::uuid and il.kind = 'product' and il.so_line_id = :'ln'::uuid) as il_n,
       (select string_agg(il.kind || ':' || trim_scale(il.amount), ' ' order by il.line_no) from public.so_invoice_line il where il.invoice_id = :'inv1'::uuid) as inv1_lines \gset

\echo '── D2) doc_data final_invoice — B급 줄 final_sale 참 · 정상 줄 거짓 · catalog'
select pg_temp.as_user(:'w', format('select public.doc_data(''final_invoice'', %L::jsonb)::text', jsonb_build_object('invoice_id', :'inv1'))) as d2 \gset
select coalesce((select string_agg(format('%s:%s:%s', l->>'sku', l->>'unit_price', jsonb_typeof(l->'final_sale') || '=' || (l->>'final_sale')), ' ' order by l->>'no') from jsonb_array_elements(pg_temp.j(:'d2')->'docs'->0->'orders'->0->'lines') l), '-') as d2_t \gset
select pg_temp.chk(format('D2 invoice lines %s · lines on paper %s · catalog: final_invoice has orders.lines.final_sale · credit_note · sales_order · ship_ready · internal_receipt do not', :'inv1_lines', :'d2_t'),
  :'d1e' = 'confirmed' and :'d2_t' ~ '^BGRD-P:[^ ]+:boolean=true BGRD-P:[^ ]+:boolean=false$'
  and (public.doc_field_catalog('final_invoice')->'allowed') ? 'orders.lines.final_sale'
  and not ((public.doc_field_catalog('credit_note')->'allowed') ? 'lines.final_sale') and not ((public.doc_field_catalog('sales_order')->'allowed') ? 'lines.final_sale')
  and not ((public.doc_field_catalog('ship_ready')->'allowed') ? 'orders.lines.final_sale') and not ((public.doc_field_catalog('internal_receipt')->'allowed') ? 'orders.lines.final_sale'),
  left(:'d2', 800));

\echo '── D3) so_credit_prepare — final_sale · 칸 기본(B급 줄 = B · 정상 줄 = ims_last_bin)'
select pg_temp.as_user(:'w', format('select public.so_credit_prepare(%L::uuid)::text', :'inv1')) as d3 \gset
select (select string_agg(format('%s fs=%s bin=%s bg=%s gone=%s', e->>'line_no', e->>'final_sale', e->'restock_bin_default'->>'bin', coalesce(e->'restock_bin_default'->>'is_bgrade', '-'), e->>'restock_bgrade_bin_gone'), ' | ' order by (e->>'line_no')::int)
          from jsonb_array_elements(pg_temp.j(:'d3')->'lines') e where e->>'kind' = 'product') as d3_t \gset
select pg_temp.chk(format('D3 %s', :'d3_t'), :'d3_t' = '1 fs=true bin=BGRD-B bg=true gone=false | 2 fs=false bin=BGRD-N bg=- gone=false', :'d3_t');

\echo '── D4 · D5) 발행 — B급 줄 1(칸 비움 → B) · 정상 줄 1 → B2(빈 · 죽은 값) · 거부 · 칸이 꺼졌을 때'
create function pg_temp.gone_b(p_claims text, p_bin uuid, p_p jsonb) returns text language plpgsql as $$
declare v jsonb;
begin
  begin
    update public.ref_bin set is_active = false where id = p_bin;
    perform set_config('request.jwt.claims', p_claims, true);
    v := public.so_credit_issue(p_p, false);
    raise exception using errcode = 'P7777', message = v::text;
  exception when sqlstate 'P7777' then return sqlerrm;
  end;
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
select pg_temp.gone_b(:'w', :'bin_b', jsonb_build_object('invoice_id', :'inv1', 'reason', 'customer_return', 'warehouse_id', :'tor', 'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'il_b', 'qty_returned', 1)))) as d5e \gset
select pg_temp.as_user(:'w', format('select public.so_credit_issue(%L::jsonb, true)::text', jsonb_build_object('invoice_id', :'inv1', 'reason', 'customer_return', 'warehouse_id', :'tor',
         'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'il_b', 'qty_returned', 1), jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'il_n', 'qty_returned', 1, 'restock_bin', 'BGRD-B2'))))) as d4 \gset
select (select string_agg(format('%s:%s:%s', e.bin, trim_scale(e.qty_delta), e.event_type), ' ' order by e.bin) from public.inv_ledger e where e.doc_type = 'creditnote' and e.doc_number = pg_temp.j(:'d4')->>'credit_number') as d4_led,
       pg_temp.bal(:'torname') as d4_bal, pg_temp.bgs(:'w', :'tor'::uuid) as d4_bg \gset
select pg_temp.chk(format('D4 · D5 issued %s · warnings %s · ledger %s · balance %s · B-grade list %s (B keeps 5.00 · B2 came in empty → dead 4.00 dropped → no price)', pg_temp.j(:'d4')->>'credit_number', pg_temp.j(:'d4')->'warnings', :'d4_led', :'d4_bal', :'d4_bg'),
  pg_temp.j(:'d4')->>'status' = 'issued' and pg_temp.j(:'d4')->'warnings' ? 'final_sale:BGRD-P' and :'d4_led' = 'BGRD-B:1:credit_in BGRD-B2:1:credit_in'
  and :'d4_bal' = 'BGRD-B=2 BGRD-B2=1 BGRD-N=16' and :'d4_bg' = 'BGRD-B 2@5.00 BGRD-B2 1@-',
  left(:'d4', 900));
select pg_temp.try_undo(:'w', format('select public.so_credit_issue(%L::jsonb, true)->>''status''', jsonb_build_object('invoice_id', :'inv_t', 'reason', 'customer_return', 'warehouse_id', :'tor',
         'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'il_t', 'qty_returned', 0.5, 'restock_bin', 'BGRD-EB'))))) as d5a,
       pg_temp.try_undo(:'w', format('select public.so_credit_issue(%L::jsonb, true)->>''status''', jsonb_build_object('invoice_id', :'inv_t', 'reason', 'customer_return', 'warehouse_id', :'tor',
         'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'so_invoice_line_id', :'il_t', 'qty_returned', 0.5, 'restock_bin', 'BGRD-BX'))))) as d5b,
       pg_temp.try_undo(null, format('update public.so_credit_line set restock_bin_id = %L::uuid where credit_id = %L::uuid and restock_bin_id = %L::uuid returning 1', :'bin_bx', pg_temp.j(:'d4')->>'credit_id', :'bin_b2')) as d5c \gset
select pg_temp.chk(format('D5 Edmonton B-grade bin refused · switched-off B-grade bin refused (insert and direct update · IM637) · B line whose bin turned off → warning %s and bin %s',
         pg_temp.j(:'d5e')->'warnings', pg_temp.j(:'d5e')->'lines'->0->>'restock_bin'),
  :'d5a' like 'ERR P0001: Bin BGRD-EB is not in warehouse %' and :'d5b' like 'ERR IM637: Credit restock: B-grade bin BGRD-BX is switched off or belongs to another store%'
  and :'d5c' like 'ERR IM637: Credit restock: B-grade bin BGRD-BX%' and pg_temp.j(:'d5e')->'warnings' ? 'bgrade_bin_gone:BGRD-P'
  and pg_temp.j(:'d5e')->'lines'->0->>'restock_bin' = 'BGRD-N',
  format('%s | %s | %s | %s', :'d5a', :'d5b', :'d5c', left(:'d5e', 500)));

\echo '── D6) 크레딧 취소 — 반대 사건이 B · B2 에서 · 가드 통과'
select pg_temp.as_user(:'w', format('select public.so_credit_cancel(%L::uuid, ''bgr-1d D6'')::text', pg_temp.j(:'d4')->>'credit_id')) as d6 \gset
select (select string_agg(format('%s:%s:%s', e.bin, trim_scale(e.qty_delta), e.raw->>'kind'), ' ' order by e.bin) from public.inv_ledger e where e.doc_type = 'creditnote' and e.doc_number = pg_temp.j(:'d4')->>'credit_number' and e.qty_delta < 0) as d6_led,
       pg_temp.bal(:'torname') as d6_bal \gset
select pg_temp.chk(format('D6 cancelled · reversal rows %s · balance %s', :'d6_led', :'d6_bal'),
  :'d6' like '{%' and :'d6_led' = 'BGRD-B:-1:credit_in_reversal BGRD-B2:-1:credit_in_reversal' and :'d6_bal' = 'BGRD-B=1 BGRD-B2=0 BGRD-N=16', left(:'d6', 400));

\echo '── D7) 가격 조정 줄이 B급 줄을 고르면 같은 경고(미리 보기 · 번호 없음)'
select pg_temp.as_user(:'w', format('select public.so_credit_issue(%L::jsonb, false)->''warnings''', jsonb_build_object('invoice_id', :'inv1', 'reason', 'price_adjustment', 'warehouse_id', :'tor',
         'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'il_b', 'qty', 1, 'new_unit_price', 4))))) as d7a,
       pg_temp.as_user(:'w', format('select public.so_credit_issue(%L::jsonb, false)->''warnings''', jsonb_build_object('invoice_id', :'inv1', 'reason', 'price_adjustment', 'warehouse_id', :'tor',
         'lines', jsonb_build_array(jsonb_build_object('kind', 'price_adjustment', 'so_invoice_line_id', :'il_n', 'qty', 1, 'new_unit_price', 9))))) as d7b \gset
select pg_temp.chk(format('D7 price adjustment on the B line warns %s · on the normal line %s', :'d7a', :'d7b'),
  pg_temp.j(:'d7a') ? 'final_sale:BGRD-P' and not (pg_temp.j(:'d7b') ? 'final_sale:BGRD-P'), format('%s | %s', :'d7a', :'d7b'));

\echo '── D8) 1a · 1b · 1c 착지 유지'
create temp table bgr_src on commit drop as
  select p.proname, regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as s from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
select (select string_agg(proname, ',' order by proname) from bgr_src where (s ~ '\mims_inv_balance\M' or s ~ '\minv_balance\M') and s !~ 'bgrade') as l_blind,
       (select string_agg(proname, ',' order by proname) from bgr_src where s ~* 'insert\s+into\s+(public\.)?inv_ledger') as l_writers,
       (select count(*) from pg_constraint c where c.contype = 'f' and c.confrelid = 'public.ref_bin'::regclass) as l_fk,
       (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O' and tgname in ('so_credit_line_bgrade_refuse', 'inv_ledger_bgrade_guard', 'so_line_bgrade_guard', 'so_bgrade_header_guard')) as l_trg \gset
select pg_temp.chk(format('D8 1a allowlist of eight · ledger writers twelve · bin FK %s · B-grade triggers %s', :l_fk, :l_trg),
  :'l_blind' = 'inv_adjust_ledger,inv_stock_master,inv_stock_master_sku,product_bom_set,product_update,stk_bins,stk_bins_many,wms_health_check'
  and :'l_writers' = 'inv_post_adjust,inv_post_credit,inv_post_move,inv_post_receipt,inv_post_receipt_off_po,inv_post_receipt_over,inv_post_sale,inv_post_transfer_arrive,inv_post_transfer_depart,so_credit_cancel,tf_over_decide,tf_settle'
  and :l_fk = 12 and :l_trg = 4, format('%s || %s', :'l_blind', :'l_writers'));
\else
select pg_temp.chk('D1 ~ D8 skipped: bgr-1d not landed', false, 'so_credit_issue has no final_sale');
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real orders · invoices · credits · ledger · B-grade prices · bins that existed at the snapshot untouched', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before',
  format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));
select round(extract(epoch from clock_timestamp() - :'tb'::timestamptz)::numeric, 2) as tx_seconds_begin_to_rollback;
rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 셋 되돌리기(greatest(실제 최대, 시작 값))'
select (select count(*) from public.product where sku like 'BGRD-%') + (select count(*) from public.ims_staff where email like 'bgrd-%') + (select count(*) from public.ref_bin where name like 'BGRD-%')
     + (select count(*) from public.inv_ledger where sku like 'BGRD-%') + (select count(*) from public.customer where name like 'BGRD %') + (select count(*) from public.so_surcharge_group where name like 'BGRD %') as leftovers;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select setval('public.so_credit_number_seq', greatest(coalesce((select max(substring(credit_number from '[0-9]+')::bigint) from public.so_credit), 0), :cr_seq_last), :'cr_seq_called'::boolean) as so_credit_number_seq_reset_to;
