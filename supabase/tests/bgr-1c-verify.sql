-- bgr-1c-verify.sql — B급 칸 ③ POS 의 B급 줄(판정 633 · 634 ② · 635 · 642 · 644 · 646 · 647):
--   S0 결함 판 · G0 손대지 않은 함수 무변 · T 옛 = 새(재발행 다섯 — B급이 끼지 않은 입력 · 가짜 POS 오더) · G1 모양 ·
--   C1 B급 고르기(후보 둘 → choose · 지정 → 5.00 · 덮어쓰기 · 할인 0 · 누른 직원) · C2 B급끼리 합치기 · 정상 줄과 안 합침(값이 같아도) ·
--   C3 값 없음 거부(644) · POS 밖 거부(warehouse · counter) · 직접 쓰기 · 값 바꾸기 · 창고 바꾸기 거부 · C4 오더 할인 문턱엔 들어가고 할인은 정상 줄만 · 다시 매기기 kept ·
--   C5 so_lines_available(B급 줄 = 그 칸 − 다른 열린 B급 줄 할당) · C8 확정 뒤 칸 값 변경 → 줄 값 그대로 · C6 확정 · Finish → 원장(B 에서 3 · B −1 · 정상 줄은 N) · 원장 가드 ·
--   C7 옮기기 · 합치기 길(나누기 · 붙여 넣기 · 다시 열기 · 정상으로 되돌리기) · L 1a · 1b 착지 유지 · Z1 실제 행 무접촉
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261023141448_bgr_1c_pos_bgrade_lines.sql -f supabase/tests/bgr-1c-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T 셋은 없고 P0c 한 줄
--   기대(2026-10-23 시험 통과 실행 · 찍힌 OK 줄을 셈): 시험 갈래 OK 15(M0 S0 G0 T G1 C1 C2 C3 C4 C5 C8 C6 C7 L Z1) · MISMATCH 0 · begin ~ rollback 약 4 초 / 확인 갈래 OK 13(M0 P0c G1 C1 ~ C8 L Z1) · MISMATCH 0
--   ⭐ 잠금 규칙(2026-10-23): 트랜잭션 첫 줄 lock_timeout 3s · 가짜 재료만 · 끝에 begin ~ rollback 초 · alter · lock · truncate · drop 줄 없음(\i 시험 갈래 밖)
--   가짜 재료 = 직원 하나(sales · stock_adjust) · 손님(Wholesale · 할인 7 %) · 토론토 칸 넷(BGRC-N · B · B2 · B3) · 제품 둘(BGRC-P Wholesale 10.00 · BGRC-Q) · B급 값 둘 · 오더 문턱 딜(20 이상 50 %) — 되감긴다
--   시퀀스 = so_number_seq · so_invoice_number_seq — 끝에서 greatest(실제 최대, 시작 값)

\echo '── db_role · schema_migrations · 시퀀스 시작 값'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261023141448' \gset
select :n_applied as schema_migrations_rows_for_20261023141448;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset

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
   and p.proname in ('so_line_update', 'so_pos_confirm', 'so_pos_complete', 'so_pos_finish', 'so_allocate_all', 'so_pick_plan', 'inv_post_sale', 'so_ship', 'so_reprice', 'so_split', 'so_merge',
                     'so_line_requote', 'so_tax_preview', 'so_line_remove', 'bgrade_price_set', 'bgrade_stock', 'inv_available_base', 'ref_bin_bgrade_set') $$;
create function pg_temp.real_rows(p_t0 timestamptz) returns text language plpgsql security definer as $$
begin
  return 'so=' || (select count(*) || '/' || md5(coalesce(string_agg(s.id::text || s.status || s.location_id::text || s.channel, ',' order by s.id), '')) from public.so s where s.created_at < p_t0)
      || ' lines=' || (select count(*) || '/' || md5(coalesce(string_agg(l.id::text || l.qty_ordered || coalesce(l.unit_price::text, '-') || coalesce(l.bgrade_bin_id::text, '-'), ',' order by l.id), '')) from public.so_line l where l.created_at < p_t0)
      || ' inv=' || (select count(*) || '/' || md5(coalesce(string_agg(i.id::text || i.status, ',' order by i.id), '')) from public.so_invoice i where i.created_at < p_t0)
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where created_at < p_t0)
      || ' reserve=' || (select count(*) || '/' || md5(coalesce(string_agg(r.id::text || coalesce(r.released_at::text, ''), ',' order by r.id), '')) from public.so_reserve r where r.created_at < p_t0)
      || ' bprice=' || (select count(*) || '/' || md5(coalesce(string_agg(b.id::text || b.price, ',' order by b.id), '')) from public.bgrade_price b where b.created_at < p_t0);
end $$;
-- so_detail 에서 새 열쇠 둘을 걷는다(옛 = 새)
create function pg_temp.strip_d(p jsonb) returns jsonb language sql immutable as $$
  select case when jsonb_typeof(p->'lines') <> 'array' then p else jsonb_set(p, '{lines}', coalesce((select jsonb_agg(e - 'bgrade_bin' - 'is_bgrade_line' order by o) from jsonb_array_elements(p->'lines') with ordinality t(e, o)), '[]'::jsonb)) end $$;
-- 줄 넣기 결과의 뜻만(id · 시각 빼고)
create function pg_temp.norm_add(p jsonb) returns text language sql immutable as $$
  select concat_ws('|', p->>'action', p->'line'->>'sku', p->'line'->>'line_no', p->'line'->>'qty_ordered', p->'line'->>'unit_price', p->'line'->>'discount_pct', p->'line'->>'price_override', p->>'total') $$;
create function pg_temp.sla(p_so uuid) returns text language sql as $$
  select string_agg(concat_ws(':', a.line_no, a.sku, a.qty_ordered, trim_scale(a.available_ea), trim_scale(a.available_units)), ' ' order by a.line_no) from public.so_lines_available(p_so) a $$;
create function pg_temp.lines(p_so uuid) returns text language sql as $$
  select coalesce(string_agg(format('L%s %s %s@%s%s', l.line_no, l.sku, trim_scale(l.qty_ordered), l.unit_price, case when l.bgrade_bin_id is not null then '[' || (select rb.name from public.ref_bin rb where rb.id = l.bgrade_bin_id) || ']' else '' end), ' ' order by l.line_no), '-') from public.so_line l where l.so_id = p_so $$;
create function pg_temp.led(p_bin text, p_line uuid, p_ref text, p_wh text) returns text language sql as $$
  select left(pg_temp.try_undo(null, format('insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source, raw) values (public.ims_today() - 1, 2, ''BGRC-P'', %L, %L, -1, ''sale_out'', ''sale'', ''BGRC-L'', %L, ''ims'', %L::jsonb) returning 1',
                    p_wh, p_bin, p_ref, jsonb_build_object('kind', 'sale_out', 'so_line_id', p_line))), 9) $$;

\echo '── M0) 가짜 직원 · 손님 · 칸 넷 · 제품 둘 · 원장 · B급 값 둘 · 문턱 딜'
select id::text as tor, name as torname from public.ref_warehouse where id = '045e4ca6-b7a9-446e-9e6a-a5a0db56d456' and is_active \gset
select id::text as edm from public.ref_warehouse where is_active and name ilike '%edmonton%' \gset
select pg_temp.real_rows(:'t0'::timestamptz) as real_before, pg_temp.fns() as fns_before \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgrc-w@test.invalid', 'BGRC W', 'manager', '["ims","sales","stock_adjust"]', '{}') returning auth_user_id::text as w_uid, id::text as w_id \gset
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
select id::text as r13, name as r13_name from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRC-N', :'tor'::uuid, 'manual', true) returning id::text as bin_n \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRC-B', :'tor'::uuid, 'manual', true) returning id::text as bin_b \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRC-B2', :'tor'::uuid, 'manual', true) returning id::text as bin_b2 \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRC-B3', :'tor'::uuid, 'manual', true) returning id::text as bin_b3 \gset
update public.ref_bin set is_bgrade = true where id in (:'bin_b'::uuid, :'bin_b2'::uuid, :'bin_b3'::uuid);
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name)
  values ('BGRC C1', 'manual', 'Wholesale', :'tor'::uuid, 7, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as c1 \gset
insert into public.product (sku, name, source, is_active, sellable) values ('BGRC-P', 'BGRC Product', 'manual', true, true) returning id::text as pid_p \gset
insert into public.product (sku, name, source, is_active, sellable) values ('BGRC-Q', 'BGRC Other', 'manual', true, true) returning id::text as pid_q \gset
insert into public.product_price (product_id, tier_id, price, source) values (:'pid_p'::uuid, '161cdb6d-9c34-476a-87bd-93a9b372f315'::uuid, 10.00, 'manual'), (:'pid_q'::uuid, '161cdb6d-9c34-476a-87bd-93a9b372f315'::uuid, 4.00, 'manual');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today() - 30, 1, 'BGRC-P', :'torname', 'BGRC-N', 18, 'po_in', 'purchase', 'PO-BGRC', 'bgrc-p-n', 'manual'),
  (public.ims_today() - 30, 1, 'BGRC-P', :'torname', 'BGRC-B', 2, 'po_in', 'purchase', 'PO-BGRC', 'bgrc-p-b', 'manual'),
  (public.ims_today() - 30, 1, 'BGRC-P', :'torname', 'BGRC-B2', 1, 'po_in', 'purchase', 'PO-BGRC', 'bgrc-p-b2', 'manual'),
  (public.ims_today() - 30, 1, 'BGRC-Q', :'torname', 'BGRC-B3', 1, 'adjust_new', 'adjustment', 'ADJ-BGRC', 'bgrc-q-b3', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('BGRC-P', :'torname', 'purchase', 'PO-BGRC', 'bgrc-p', public.ims_today() - 30, true, 21, 2.5, 'po_line'),
  ('BGRC-Q', :'torname', 'purchase', 'PO-BGRC', 'bgrc-q', public.ims_today() - 30, true, 1, 1.2, 'po_line');
insert into public.bgrade_price (bin_id, product_id, price, set_by) values (:'bin_b'::uuid, :'pid_p'::uuid, 5.00, :'w_id'::uuid), (:'bin_b2'::uuid, :'pid_p'::uuid, 3.00, :'w_id'::uuid);
insert into public.so_deal (name, is_active, source, is_order_level, kind, coupon_required) values ('BGRC order tier', true, 'manual', true, 'pct', false) returning id::text as deal \gset
insert into public.so_deal_tier (deal_id, tier_no, min_amount, pct) values (:'deal'::uuid, 1, 20, 50);
set local session_replication_role = origin;
create function pg_temp.mk_pos(p_claims text, p_cust uuid, p_wh uuid, p_ch text, p_note text, p_rule uuid, p_rule_name text) returns text language plpgsql as $$
declare v uuid;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v := (public.so_create(p_cust, p_ch, case when p_ch = 'pos' then 'pos' else 'manual' end, p_wh, p_note)->>'id')::uuid;
  execute 'set local session_replication_role = replica';
  update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v;
  execute 'set local session_replication_role = origin';
  return v::text;
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
select pg_temp.mk_pos(:'w', :'c1'::uuid, :'tor'::uuid, 'pos', 'bgr-1c T', :'r13'::uuid, :'r13_name') as so_t \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id''', :'so_t', :'pid_p')) as lt \gset
select pg_temp.chk(format('M0 staff W(sales · adjust) · customer Wholesale −7%% · bins BGRC-N/B/B2/B3 in %s · P: N 18 · B 2 @5.00 · B2 1 @3.00 · Q: B3 1 (no price) · deal ≥ 20 → 50%% · POS order T with %s', :'torname', pg_temp.lines(:'so_t'::uuid)),
  :'w_uid' <> '' and :'deal' <> '' and :'so_t' ~ '^[0-9a-f-]{36}$' and :'lt' ~ '^[0-9a-f-]{36}$' and :'real_before' <> '' and :'fns_before' <> '', format('so_t %s · lt %s', :'so_t', :'lt'));

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) · 옛 출력 담기'
select (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_bgrade_set') as s0_win,
       (select count(*) from pg_trigger where tgname = 'so_line_bgrade_guard') as s0_trg \gset
select pg_temp.as_user(:'w', format('select public.so_detail(%L::uuid)::text', :'so_t')) as d0 \gset
select pg_temp.sla(:'so_t'::uuid) as a0 \gset
select pg_temp.try_undo(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', :'so_t', :'pid_q')) as add0 \gset
select pg_temp.try_undo(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', :'so_t', :'pid_p')) as add0b \gset
select pg_temp.as_user(:'w', format('select public.so_lines_paste(%L::uuid, %L::jsonb, false)::text', :'so_t', '[{"sku":"BGRC-P","qty":1},{"sku":"BGRC-Q","qty":1,"price":3.5}]')) as p0 \gset
select pg_temp.led('BGRC-N', :'lt'::uuid, 't1', :'torname') as g0a, pg_temp.led('BGRC-B', null, 't2', :'torname') as g0b \gset
select pg_temp.chk(format('S0 before the trial: no B-grade line window · no line guard · a sale_out row in a B-grade bin passes the 1b guard (%s) · old outputs captured', :'g0b'),
  :s0_win = 0 and :s0_trg = 0 and :n_applied = 0 and :'d0' like '{%' and :'a0' <> '' and :'add0' like 'PASS: {%' and :'add0b' like 'PASS: {%' and :'p0' like '{%' and :'g0a' = 'PASS: 1' and :'g0b' = 'PASS: 1',
  format('%s | %s | %s | %s | %s | %s', left(:'d0', 100), :'a0', left(:'add0', 200), left(:'p0', 200), :'g0a', :'g0b'));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: POS confirm · finish · ship · pick plan · posting · reprice · split · merge · 1a · 1b functions not re-issued are unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', :'fns_before', pg_temp.fns()));
\echo '── T) 옛 = 새 — B급이 끼지 않은 입력'
select pg_temp.as_user(:'w', format('select public.so_detail(%L::uuid)::text', :'so_t')) as d1 \gset
select pg_temp.sla(:'so_t'::uuid) as a1 \gset
select pg_temp.try_undo(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', :'so_t', :'pid_q')) as add1 \gset
select pg_temp.try_undo(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', :'so_t', :'pid_p')) as add1b \gset
select pg_temp.as_user(:'w', format('select public.so_lines_paste(%L::uuid, %L::jsonb, false)::text', :'so_t', '[{"sku":"BGRC-P","qty":1},{"sku":"BGRC-Q","qty":1,"price":3.5}]')) as p1 \gset
select pg_temp.led('BGRC-N', :'lt'::uuid, 't1', :'torname') as g1a \gset
select pg_temp.chk(format('T old = new without a B-grade line: so_detail (new keys stripped) · so_lines_available (%s) · so_line_add new line and merge (%s · %s) · paste preview · normal-bin sale_out passes the guard', :'a1', pg_temp.norm_add(pg_temp.j(substr(:'add1', 7))), pg_temp.norm_add(pg_temp.j(substr(:'add1b', 7)))),
  pg_temp.strip_d(pg_temp.j(:'d0')) = pg_temp.strip_d(pg_temp.j(:'d1')) and :'a0' = :'a1'
  and pg_temp.norm_add(pg_temp.j(substr(:'add0', 7))) = pg_temp.norm_add(pg_temp.j(substr(:'add1', 7))) and pg_temp.norm_add(pg_temp.j(substr(:'add0b', 7))) = pg_temp.norm_add(pg_temp.j(substr(:'add1b', 7)))
  and pg_temp.j(:'p0') = pg_temp.j(:'p1') and :'g1a' = 'PASS: 1',
  format('%s || %s | %s || %s | %s || %s | %s', :'a0', :'a1', left(:'add0', 250), left(:'add1', 250), left(:'p0', 300), left(:'p1', 300), :'g1a'));
\else
select pg_temp.chk('P0c confirm run: migration 20261023141448 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_bgrade_set') as landed \gset
\if :landed
\echo '── G1) 모양'
select pg_temp.chk('G1 windows authenticated only · guards postgres only · so_lines_available ends with bgrade_bin_id · bgrade_bin · line guard + header guard + ledger guard on',
  has_function_privilege('authenticated', 'public.so_line_bgrade_set(uuid, uuid)', 'execute') and not has_function_privilege('anon', 'public.so_line_bgrade_set(uuid, uuid)', 'execute')
  and not has_function_privilege('service_role', 'public.so_line_bgrade_clear(uuid)', 'execute') and not has_function_privilege('authenticated', 'public.so_line_bgrade_guard()', 'execute')
  and (select pg_get_function_result(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_available') like '%available_units numeric, bgrade_bin_id uuid, bgrade_bin text)'
  and (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O' and tgname in ('so_line_bgrade_guard', 'so_bgrade_header_guard', 'inv_ledger_bgrade_guard')) = 3,
  'see G1');

\echo '── C1) POS 줄 → B급: 칸 생략(후보 둘 → choose) · B 지정 → 5.00'
select pg_temp.mk_pos(:'w', :'c1'::uuid, :'tor'::uuid, 'pos', 'bgr-1c C', :'r13'::uuid, :'r13_name') as so1 \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id''', :'so1', :'pid_p')) as l1 \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set(%L::uuid)::text', :'l1')) as c1a \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set(%L::uuid, %L::uuid)::text', :'l1', :'bin_b')) as c1b \gset
select pg_temp.as_user(:'w', format('select public.so_detail(%L::uuid)::text', :'so1')) as c1d \gset
select pg_temp.as_user(:'w', format('select public.so_tax_preview(%L::uuid, public.ims_today(), null, ''ordered'')->''totals''->>''lines_amount''', :'so1')) as c1t \gset
select (select string_agg(format('%s@%s(%s)', e->>'bin', e->>'price', e->>'qty'), ',') from jsonb_array_elements(pg_temp.j(:'c1a')->'candidates') e) as c1a_t \gset
select pg_temp.chk(format('C1 no bin given → choose %s (nothing saved) · bin B → %s · detail B-grade %s / %s · lines amount %s', :'c1a_t', pg_temp.lines(:'so1'::uuid),
         pg_temp.j(:'c1d')->'lines'->0->>'is_bgrade_line', pg_temp.j(:'c1d')->'lines'->0->>'bgrade_bin', :'c1t'),
  pg_temp.j(:'c1a')->>'action' = 'choose' and :'c1a_t' = 'BGRC-B2@3.00(1),BGRC-B@5.00(2)'
  and pg_temp.j(:'c1b')->>'action' = 'set' and (pg_temp.j(:'c1b')->'line'->>'unit_price')::numeric = 5 and (pg_temp.j(:'c1b')->'line'->>'price_override')::boolean
  and pg_temp.j(:'c1b')->'line'->>'discount_pct' is null and pg_temp.j(:'c1b')->'line'->>'price_set_by' = :'w_id' and pg_temp.j(:'c1b')->'warnings' = '[]'::jsonb
  and pg_temp.j(:'c1d')->'lines'->0->>'is_bgrade_line' = 'true' and pg_temp.j(:'c1d')->'lines'->0->>'bgrade_bin' = 'BGRC-B' and (pg_temp.j(:'c1d')->'lines'->0->>'manual')::boolean
  and :'c1t'::numeric = 5,
  format('%s | %s | %s', left(:'c1a', 500), left(:'c1b', 600), :'c1t'));

\echo '── C2) B급끼리 합치기 · 정상 줄과 안 합침(값이 같게 넣어도)'
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)::text', :'so1', :'pid_p')) as c2a \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set(%L::uuid, %L::uuid)::text', pg_temp.j(:'c2a')->'line'->>'id', :'bin_b')) as c2b \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 2)::text', :'so1', :'pid_p')) as c2c \gset
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1, 5.00, null, null, null, false)::text', :'so1', :'pid_p')) as c2d \gset
select pg_temp.lines(:'so1'::uuid) as c2_lines \gset
select pg_temp.chk(format('C2 scan P → new line (%s) · B-grade on it → merged into the B line · scan P ×2 → normal line · P at 5.00 → %s (not merged into the B line) · %s', pg_temp.j(:'c2a')->>'action', pg_temp.j(:'c2d')->>'action', :'c2_lines'),
  pg_temp.j(:'c2a')->>'action' <> 'merged' and pg_temp.j(:'c2a')->>'action' <> 'ask' and pg_temp.j(:'c2b')->>'action' = 'merged' and pg_temp.j(:'c2b')->>'removed_line_id' = pg_temp.j(:'c2a')->'line'->>'id'
  and pg_temp.j(:'c2c')->>'action' <> 'merged' and pg_temp.j(:'c2c')->>'action' <> 'ask' and pg_temp.j(:'c2d')->>'action' = 'ask'
  and not exists (select 1 from jsonb_array_elements(pg_temp.j(:'c2d')->'existing') e where (e->>'unit_price')::numeric = 5)
  and :'c2_lines' ~ '^L1 BGRC-P 2@5\.0+\[BGRC-B\] L2 BGRC-P 2@9\.30*$',
  format('%s | %s | %s | %s', left(:'c2a', 300), left(:'c2b', 300), left(:'c2c', 300), left(:'c2d', 600)));

\echo '── C3) 값 없음(644) · 칸에 그 SKU 없음 · POS 밖 · 직접 쓰기 · 값 · 창고 바꾸기 거부 · 수량은 된다'
select pg_temp.as_user(:'w', format('select public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id''', :'so1', :'pid_q')) as lq \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set(%L::uuid)::text', :'lq')) as c3a \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set(%L::uuid, %L::uuid)::text', :'lq', :'bin_b')) as c3b \gset
select pg_temp.as_user(:'w', format('select public.so_line_remove(%L::uuid)->>''removed_line_no''', :'lq')) as c3r \gset
select pg_temp.mk_pos(:'w', :'c1'::uuid, :'tor'::uuid, 'warehouse', 'bgr-1c C3 wh', :'r13'::uuid, :'r13_name') as so_wh \gset
select pg_temp.mk_pos(:'w', :'c1'::uuid, :'tor'::uuid, 'counter', 'bgr-1c C3 ctr', :'r13'::uuid, :'r13_name') as so_ct \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set((public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id'')::uuid, %L::uuid)::text', :'so_wh', :'pid_p', :'bin_b')) as c3c \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set((public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id'')::uuid, %L::uuid)::text', :'so_ct', :'pid_p', :'bin_b')) as c3d \gset
select (select id::text from public.so_line where so_id = :'so1'::uuid and bgrade_bin_id is null and sku = 'BGRC-P' order by line_no limit 1) as l3,
       (select id::text from public.so_line where so_id = :'so1'::uuid and bgrade_bin_id is not null) as lb \gset
select pg_temp.try_undo(null, format('update public.so_line set bgrade_bin_id = %L::uuid where id = %L::uuid returning 1', :'bin_b', :'l3')) as c3e,
       pg_temp.try_undo(null, format('update public.so_line set unit_price = 1 where id = %L::uuid returning 1', :'lb')) as c3f,
       pg_temp.as_user(:'w', format('select public.so_line_update(%L::uuid, ''{"unit_price": 4}''::jsonb)::text', :'lb')) as c3g,
       pg_temp.try_undo(null, format('update public.so set location_id = %L::uuid where id = %L::uuid returning 1', :'edm', :'so1')) as c3h,
       pg_temp.try_undo(null, format('insert into public.so_line (so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, bgrade_bin_id) values (%L::uuid, 99, %L::uuid, ''BGRC-P'', ''x'', 1, 1, %L::uuid) returning 1', :'so1', :'pid_p', :'bin_b')) as c3i \gset
select pg_temp.as_user(:'w', format('select public.so_line_update(%L::uuid, ''{"qty_ordered": 3}''::jsonb)->''line''->>''qty_ordered''', :'lb')) as c3j \gset
select pg_temp.chk(format('C3 Q (B-grade stock, no price) refused · B has no Q · warehouse and counter orders refused · direct set · price · store change · insert refused (IM638) · qty change passes (%s) · %s', :'c3j', pg_temp.lines(:'so1'::uuid)),
  :'c3a' like 'ERR P0001: No B-grade price for BGRC-Q in bin BGRC-B3 — ask a manager to set it%' and :'c3b' like 'ERR P0001: No B-grade stock of BGRC-Q in bin BGRC-B — %' and :'c3r' ~ '^[0-9]+$'
  and :'c3c' like 'ERR P0001: B-grade is sold at the POS only — order % is a warehouse order%' and :'c3d' like 'ERR P0001: B-grade is sold at the POS only — order % is a counter order%'
  and :'c3e' like 'ERR IM638: Line % B-grade is set or cleared only with the B-grade button%' and :'c3f' like 'ERR IM638: Line 1 is a B-grade line — its price comes from the B-grade bin%'
  and :'c3g' like 'ERR IM638: Line 1 is a B-grade line%' and :'c3h' like 'ERR IM638: Order % has B-grade lines — clear them before changing the store%'
  and :'c3i' like 'ERR IM638: B-grade lines are made only with the B-grade button%' and :'c3j'::numeric = 3,
  format('%s | %s | %s | %s | %s | %s | %s | %s | %s | %s', :'c3a', :'c3b', :'c3c', :'c3d', :'c3e', :'c3f', :'c3g', :'c3h', :'c3i', :'c3j'));

\echo '── C4) 오더 할인 — 문턱엔 B급 줄 금액이 들어가고 할인 바탕은 정상 줄만 · 다시 매기기 kept'
select pg_temp.as_user(:'w', format('select public.so_tax_preview(%L::uuid, public.ims_today(), null, ''ordered'')::text', :'so1')) as c4p \gset
select pg_temp.as_user(:'w', format('select public.so_reprice(%L::uuid)::text', :'so1')) as c4r \gset
select (select string_agg(format('%s:%s', r->>'line_no', coalesce(r->>'reason', 'requoted')), ',' order by (r->>'line_no')::int) from jsonb_array_elements(coalesce(pg_temp.j(:'c4r')->'lines', pg_temp.j(:'c4r')->'rows')) r) as c4r_t \gset
select pg_temp.chk(format('C4 lines %s · manual (B-grade) %s · discount basis %s · order discount %s%% = %s · reprice %s', pg_temp.j(:'c4p')->'totals'->>'lines_amount', pg_temp.j(:'c4p')->'totals'->>'manual_lines_amount',
         pg_temp.j(:'c4p')->'totals'->>'discount_basis_amount', pg_temp.j(:'c4p')->'order_discount'->>'pct', pg_temp.j(:'c4p')->'totals'->>'order_discount_amount', :'c4r_t'),
  (pg_temp.j(:'c4p')->'totals'->>'lines_amount')::numeric = 33.6 and (pg_temp.j(:'c4p')->'totals'->>'manual_lines_amount')::numeric = 15
  and (pg_temp.j(:'c4p')->'totals'->>'discount_basis_amount')::numeric = 18.6 and (pg_temp.j(:'c4p')->'order_discount'->>'pct')::numeric = 50
  and (pg_temp.j(:'c4p')->'totals'->>'order_discount_amount')::numeric = -9.3 and :'c4r_t' like '1:price_override%',
  format('%s | %s', left(:'c4p', 900), left(:'c4r', 600)));

\echo '── C5) so_lines_available — 다른 POS 오더의 열린 B급 줄 할당(1)을 뺀다 · 정상 줄은 B급을 뺀 가용'
select pg_temp.mk_pos(:'w', :'c1'::uuid, :'tor'::uuid, 'pos', 'bgr-1c C5 other', :'r13'::uuid, :'r13_name') as so4 \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_set((public.so_line_add(%L::uuid, %L::uuid, 1)->''line''->>''id'')::uuid, %L::uuid)->>''action''', :'so4', :'pid_p', :'bin_b')) as c5a \gset
select pg_temp.as_user(:'w', format('select public.so_pos_confirm(%L::uuid)->>''status''', :'so4')) as c5b \gset
select pg_temp.sla(:'so1'::uuid) as c5s, (select string_agg(coalesce(a.bgrade_bin, '-'), ',' order by a.line_no) from public.so_lines_available(:'so1'::uuid) a) as c5bin \gset
select pg_temp.chk(format('C5 other POS order holds 1 B-grade from B (%s · %s) · available %s (bins %s) — B line: 2 − 1 = 1 against 3 ordered (not blocked) · normal line: 18', :'c5a', :'c5b', :'c5s', :'c5bin'),
  :'c5a' = 'set' and :'c5b' = 'confirmed' and :'c5s' = '1:BGRC-P:3:1:1 2:BGRC-P:2:18:18' and :'c5bin' = 'BGRC-B,-', :'c5s');

\echo '── C8) 확정된 오더 뒤 칸 값 바꾸기(646 reprice 5.00 → 4.00) → 확정 · 초안 줄 값 그대로'
select pg_temp.as_user(:'w', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 4.00, null, true)->>''relabel''', :'bin_b', :'pid_p')) as c8a \gset
select pg_temp.chk(format('C8 bin price repriced (relabel %s) · confirmed order line %s · draft order line %s', :'c8a', pg_temp.lines(:'so4'::uuid), pg_temp.lines(:'so1'::uuid)),
  :'c8a' = 'true' and pg_temp.lines(:'so4'::uuid) ~ '^L1 BGRC-P 1@5\.0+\[BGRC-B\]$' and pg_temp.lines(:'so1'::uuid) ~ '^L1 BGRC-P 3@5\.0+\[BGRC-B\] ', :'c8a');

\echo '── C6) 확정 · Finish → 할당 · 원장 · 원장 가드'
select pg_temp.as_user(:'w', format('select public.so_pos_confirm(%L::uuid)->>''status''', :'so1')) as c6a \gset
select (select format('%s/%s/%s/%s', trim_scale(qty_ea), trim_scale(sales_alloc_ea), trim_scale(transfer_alloc_ea), trim_scale(bgrade_ea)) from public.inv_available_base(:'tor'::uuid, array[:'pid_p'::uuid])) as c6iab \gset
select pg_temp.as_user(:'w', format('select public.so_pos_finish(%L::uuid, false)::text', :'so1')) as c6p \gset
select pg_temp.as_user(:'w', format('select public.so_pos_finish(%L::uuid, true)::text', :'so1')) as c6b \gset
select (select string_agg(format('%s:%s', e.bin, trim_scale(e.qty_delta)), ' ' order by e.bin) from public.inv_ledger e where e.doc_type = 'sale' and e.doc_number = (select so_number from public.so where id = :'so1'::uuid)) as c6led,
       (select string_agg(format('%s=%s', v.bin, trim_scale(v.qty)), ' ' order by v.bin) from public.inv_balance v where v.warehouse = :'torname' and v.sku = 'BGRC-P') as c6bal \gset
select pg_temp.led('BGRC-B', :'l3'::uuid, 'g1', :'torname') as c6g1, pg_temp.led('BGRC-N', :'lb'::uuid, 'g2', :'torname') as c6g2, pg_temp.led('', :'lb'::uuid, 'g3', :'torname') as c6g3,
       pg_temp.led('BGRC-B', :'lb'::uuid, 'g4', :'torname') as c6g4, pg_temp.led('BGRC-B', null, 'g5', :'torname') as c6g5 \gset
select pg_temp.chk(format('C6 confirmed · available %s (sales alloc = normal line 2 only) · preview short %s · finished %s · ledger %s · balance %s · guard: normal line from B %s · B line from N %s · from no bin %s · B line from B %s · no line %s',
         :'c6iab', pg_temp.j(:'c6p')->>'short_ea_total', pg_temp.j(:'c6b')->>'status', :'c6led', :'c6bal', :'c6g1', :'c6g2', :'c6g3', :'c6g4', :'c6g5'),
  :'c6a' = 'confirmed' and :'c6iab' = '18/2/0/3' and pg_temp.j(:'c6b')->>'status' = 'fulfilled' and :'c6led' = 'BGRC-B:-3 BGRC-N:-2' and :'c6bal' = 'BGRC-B=-1 BGRC-B2=1 BGRC-N=16'
  and :'c6g1' = 'ERR IM637' and :'c6g2' = 'ERR IM637' and :'c6g3' = 'ERR IM637' and :'c6g4' = 'PASS: 1' and :'c6g5' = 'ERR IM637',
  format('%s | %s | %s', left(:'c6p', 400), left(:'c6b', 400), :'c6iab'));

\echo '── C7) 옮기기 · 합치기 길 — 나누기(통째 · 일부) · 붙여 넣기 · 다시 열기 · 정상으로 되돌리기'
select (select id::text from public.so_line where so_id = :'so4'::uuid) as l4 \gset
select pg_temp.try_undo(null, format('select (public.so_split(%L::uuid, ''manual'', %L::jsonb, ''draft'', %L::uuid)).so_number', :'so4', jsonb_build_array(jsonb_build_object('line_id', :'l4', 'qty', 1)), :'w_id')) as c7a \gset
set local session_replication_role = replica;
update public.so_line set qty_ordered = 2 where id = :'l4'::uuid;
set local session_replication_role = origin;
select pg_temp.try_undo(null, format('select (public.so_split(%L::uuid, ''manual'', %L::jsonb, ''draft'', %L::uuid)).so_number', :'so4', jsonb_build_array(jsonb_build_object('line_id', :'l4', 'qty', 1)), :'w_id')) as c7b \gset
select pg_temp.as_user(:'w', format('select public.so_pos_reopen(%L::uuid)->>''status''', :'so4')) as c7c \gset
select pg_temp.as_user(:'w', format('select public.so_lines_paste(%L::uuid, %L::jsonb, false)->''lines''->0->>''verdict''', :'so4', '[{"sku":"BGRC-P","qty":1,"price":5}]')) as c7d \gset
select pg_temp.as_user(:'w', format('select public.so_line_bgrade_clear(%L::uuid)::text', :'l4')) as c7e \gset
select pg_temp.chk(format('C7 split whole / part refused (IM638) · reopen keeps the B line (%s) · paste at the same 5.00 → %s (not merged) · clear → %s', :'c7c', :'c7d', pg_temp.lines(:'so4'::uuid)),
  :'c7a' like 'ERR IM638: Line 1 is a B-grade line — it stays on its POS order%' and :'c7b' like 'ERR IM638: A B-grade line (BGRC-P) is not split or copied%'
  and :'c7c' = 'draft' and :'c7d' = 'ok' and pg_temp.j(:'c7e')->>'action' = 'cleared' and pg_temp.lines(:'so4'::uuid) ~ '^L1 BGRC-P 2@9\.30*$',
  format('%s | %s | %s | %s | %s', :'c7a', :'c7b', :'c7c', :'c7d', left(:'c7e', 300)));

\echo '── L) 1a · 1b 착지 유지 — 허락 목록 여덟 · 원장 창구 열둘 · 칸 FK'
create temp table bgr_src on commit drop as
  select p.proname, regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as s from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
select (select string_agg(proname, ',' order by proname) from bgr_src where (s ~ '\mims_inv_balance\M' or s ~ '\minv_balance\M') and s !~ 'bgrade') as l_blind,
       (select string_agg(proname, ',' order by proname) from bgr_src where s ~* 'insert\s+into\s+(public\.)?inv_ledger') as l_writers,
       (select count(*) from pg_constraint c where c.contype = 'f' and c.confrelid = 'public.ref_bin'::regclass) as l_fk \gset
select pg_temp.chk(format('L 1a allowlist of eight · 1b ledger writers twelve · bin FK columns %s (no new)', :l_fk),
  :'l_blind' = 'inv_adjust_ledger,inv_stock_master,inv_stock_master_sku,product_bom_set,product_update,stk_bins,stk_bins_many,wms_health_check'
  and :'l_writers' = 'inv_post_adjust,inv_post_credit,inv_post_move,inv_post_receipt,inv_post_receipt_off_po,inv_post_receipt_over,inv_post_sale,inv_post_transfer_arrive,inv_post_transfer_depart,so_credit_cancel,tf_over_decide,tf_settle'
  and :l_fk = 12, format('%s || %s || %s', :'l_blind', :'l_writers', :l_fk));
\else
select pg_temp.chk('G1 ~ L skipped: bgr-1c not landed', false, 'so_line_bgrade_set missing');
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real orders · lines · invoices · ledger · reservations · B-grade prices that existed at the snapshot untouched', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before',
  format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));
select round(extract(epoch from clock_timestamp() - :'tb'::timestamptz)::numeric, 2) as tx_seconds_begin_to_rollback;
rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 되돌리기(greatest(실제 최대, 시작 값))'
select (select count(*) from public.product where sku like 'BGRC-%') + (select count(*) from public.ims_staff where email like 'bgrc-%') + (select count(*) from public.ref_bin where name like 'BGRC-%')
     + (select count(*) from public.inv_ledger where sku like 'BGRC-%') + (select count(*) from public.customer where name like 'BGRC %') + (select count(*) from public.so_deal where name like 'BGRC %') as leftovers;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
