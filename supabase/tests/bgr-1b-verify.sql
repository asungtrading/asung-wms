-- bgr-1b-verify.sql — B급 칸 ② B급 값 · 옮기기 · 되돌리기 · 다른 길 막기(판정 630 · 631 · 632 · 637 · 638 · 639 · 642 · 644 · 645):
--   S0 결함 판 · G0 손대지 않은 함수 무변 · T 옛 = 새(재발행 둘 — B급이 끼지 않은 입력 · 가짜 재료) · G1 모양 ·
--   B1 move_in(문 · 원장 bin_move 둘 · 레이어 무변 · 가용) · B2 같은 값 더하기(stock_move 없는 manager) · 642 거부 · B3 값 바꾸기(p_reprice) · B4 % · 값 검사 ·
--   B5 move_out · 죽은 값 덮기 · B→B 거부 · B6 기존 칸 옮기기 막기(inv_move_now · 칸 비우기 · 확정 때 원장 가드) · B7 조정(값 그대로 / 0 에서 들어오면 값 없음 · 레이어) ·
--   B8 칸 칸 이른 거부 일곱 · 원장 가드 사건별 · B9 표 직접 쓰기 거부 · 1a 가드 · S5 1a 착지(허락 목록 여덟) · F5 원장 창구 · 칸 FK 전수 · Z1 실제 행 무접촉
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261023135121_bgr_1b_bgrade_price_moves.sql -f supabase/tests/bgr-1b-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T 셋은 없고 P0c 한 줄
--   기대(2026-10-23 시험 통과 실행 · 찍힌 OK 줄을 셈): 시험 갈래 OK 17(M0 S0 G0 T G1 B1 ~ B9 S5 F5 Z1) · MISMATCH 0 · begin ~ rollback 약 5 초 / 확인 갈래 OK 15(M0 P0c G1 B1 ~ B9 S5 F5 Z1) · MISMATCH 0
--   ⭐ 잠금 규칙(2026-10-23): 트랜잭션 첫 줄 lock_timeout 3s · 무거운 측정 없음(가짜 재료만) · 끝에 begin ~ rollback 초를 찍는다 · 이 파일에 alter · lock · truncate · drop 줄 없음(\i 시험 갈래 밖)
--   가짜 재료 = 직원 다섯 · 토론토 칸 다섯(BGRB-N · N2 · B · B2 · B3) · 제품 둘(BGRB-P Wholesale 10.00 · BGRB-Q Wholesale 없음) · 원장(N 에 P 18 · Q 5) — 되감긴다 · 옮기기 · 조정 번호 시퀀스는 끝에서 greatest(실제 최대, 시작 값)

\echo '── db_role · schema_migrations · 시퀀스 시작 값'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261023135121' \gset
select :n_applied as schema_migrations_rows_for_20261023135121;
select last_value as mv_seq_last, is_called as mv_seq_called from public.inv_move_number_seq \gset
select last_value as adj_seq_last, is_called as adj_seq_called from public.inv_adjust_number_seq \gset

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
create function pg_temp.as_role(p_role text, p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  if p_claims is not null then perform set_config('request.jwt.claims', p_claims, true); end if;
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then
  reset role;
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 해 보고 되감기(부분 트랜잭션) — 통과하면 'PASS: 결과' · 거부면 'ERR 상태: 글'
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
-- 옮기기 결과에서 번호 · id 를 걷는다(옛 = 새 비교용)
create function pg_temp.norm_mv(p jsonb) returns jsonb language sql immutable as $$
  select case when p is null then null else (p - 'move_id' - 'move_number') || jsonb_build_object('ledger', coalesce(p->'ledger', '{}'::jsonb) - 'move_id' - 'move_number') end $$;
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('inv_move_now', 'inv_move_line_set', 'inv_move_confirm', 'inv_move_create', 'inv_move_eval', 'inv_post_move', 'inv_post_adjust', 'inv_adjust_line_set', 'inv_adjust_confirm',
                     'inv_adjust_require', 'ims_can_adjust', 'inv_adjust_ledger', 'ref_bin_bgrade_set', 'ref_bin_bgrade_guard', 'inv_post_credit', 'inv_post_receipt', 'inv_post_sale', 'inv_post_transfer_arrive') $$;
create function pg_temp.real_rows(p_t0 timestamptz) returns text language plpgsql security definer as $$
begin
  return 'ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where created_at < p_t0)
      || ' layer=' || (select count(*) || '/' || coalesce(sum(id), 0) || '/' || coalesce(sum(qty), 0) from public.inv_layer where created_at < p_t0)
      || ' move=' || (select count(*) || '/' || md5(coalesce(string_agg(m.id::text || m.status, ',' order by m.id), '')) from public.inv_move m where m.created_at < p_t0)
      || ' adj=' || (select count(*) || '/' || md5(coalesce(string_agg(a.id::text || a.status, ',' order by a.id), '')) from public.inv_adjust a where a.created_at < p_t0)
      || ' bins=' || (select count(*) || '/' || md5(coalesce(string_agg(b.id::text || b.name || b.is_active || b.is_bgrade || coalesce(b.updated_at::text, ''), ',' order by b.id), '')) from public.ref_bin b where b.created_at < p_t0);
end $$;
-- 가짜 칸들의 지금 — 칸/SKU 잔고 @값(값 있음 여부)
create function pg_temp.bg_state(p_claims text, p_wh uuid) returns text language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  v := public.bgrade_stock(p_wh);
  return coalesce((select string_agg(format('%s/%s %s@%s%s', r->>'bin', r->>'sku', r->>'qty', coalesce(r->>'price', '-'), case when (r->>'pct') is not null then '(' || (r->>'pct') || '% of ' || trim_scale((r->>'basis_price')::numeric) || ')' else '' end), ' ' order by r->>'bin', r->>'sku')
                     from jsonb_array_elements(v->'rows') r where r->>'bin' like 'BGRB-%'), '-');
end $$;

\echo '── M0) 가짜 직원 다섯 · 칸 다섯 · 제품 둘 · 원장(N 에 P 18 · Q 5) · 스냅샷'
select id::text as tor, name as torname from public.ref_warehouse where id = '045e4ca6-b7a9-446e-9e6a-a5a0db56d456' and is_active \gset
select pg_temp.real_rows(:'t0'::timestamptz) as real_before, pg_temp.fns() as fns_before \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgrb-s@test.invalid', 'BGRB S', 'supervisor', '["ims","stock_adjust"]', '{}') returning auth_user_id::text as s_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgrb-k@test.invalid', 'BGRB K', 'supervisor', '["ims"]', '{}') returning auth_user_id::text as k_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgrb-w@test.invalid', 'BGRB W', 'worker', '["ims","stock_move","stock_adjust"]', '{}') returning auth_user_id::text as w_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgrb-m@test.invalid', 'BGRB M', 'manager', '["ims","stock_adjust"]', '{}') returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'bgrb-x@test.invalid', 'BGRB X', 'manager', '["ims","master"]', '{}') returning auth_user_id::text as x_uid \gset
\set s '{"sub":"' :s_uid '","role":"authenticated"}'
\set k '{"sub":"' :k_uid '","role":"authenticated"}'
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
\set m '{"sub":"' :m_uid '","role":"authenticated"}'
\set x '{"sub":"' :x_uid '","role":"authenticated"}'
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRB-N', :'tor'::uuid, 'manual', true) returning id::text as bin_n \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRB-N2', :'tor'::uuid, 'manual', true) returning id::text as bin_n2 \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRB-B', :'tor'::uuid, 'manual', true) returning id::text as bin_b \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRB-B2', :'tor'::uuid, 'manual', true) returning id::text as bin_b2 \gset
insert into public.ref_bin (name, warehouse_id, source, is_active) values ('BGRB-B3', :'tor'::uuid, 'manual', true) returning id::text as bin_b3 \gset
update public.ref_bin set is_bgrade = true where id in (:'bin_b'::uuid, :'bin_b2'::uuid);
set local session_replication_role = replica;
insert into public.product (sku, name, source, is_active, sellable) values ('BGRB-P', 'BGRB Product', 'manual', true, true) returning id::text as pid_p \gset
insert into public.product (sku, name, source, is_active, sellable) values ('BGRB-Q', 'BGRB No wholesale', 'manual', true, true) returning id::text as pid_q \gset
insert into public.product_price (product_id, tier_id, price, source) values (:'pid_p'::uuid, '161cdb6d-9c34-476a-87bd-93a9b372f315'::uuid, 10.00, 'manual');
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values
  (public.ims_today() - 30, 1, 'BGRB-P', :'torname', 'BGRB-N', 18, 'po_in', 'purchase', 'PO-BGRB', 'bgrb-p', 'manual'),
  (public.ims_today() - 30, 1, 'BGRB-Q', :'torname', 'BGRB-N', 5, 'po_in', 'purchase', 'PO-BGRB', 'bgrb-q', 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('BGRB-P', :'torname', 'purchase', 'PO-BGRB', 'bgrb-p', public.ims_today() - 30, true, 18, 2.5, 'po_line'),
  ('BGRB-Q', :'torname', 'purchase', 'PO-BGRB', 'bgrb-q', public.ims_today() - 30, true, 5, 1.2, 'po_line');
set local session_replication_role = origin;
select pg_temp.chk(format('M0 staff S(supervisor+adjust) K(supervisor, no adjust) W(worker, move+adjust) M(manager adjust, no stock_move) X(master) · bins BGRB-N/N2/B/B2/B3 in %s (B · B2 B-grade) · products P(Wholesale 10.00) Q · ledger N: P 18 Q 5', :'torname'),
  :'s_uid' <> '' and :'x_uid' <> '' and :'bin_b3' <> '' and :'pid_q' <> '' and :'real_before' <> '' and :'fns_before' <> '', 'see M0');

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) · 옛 출력 담기(가짜 재료 · 작게)'
select (select count(*) from pg_class where relname = 'bgrade_price' and relnamespace = 'public'::regnamespace) as s0_tbl,
       (select count(*) from pg_trigger where tgname = 'inv_ledger_bgrade_guard') as s0_trg \gset
select pg_temp.as_user(:'w', format('select public.inv_move_bin_contents(%L::uuid, %L::uuid)::text', :'tor', :'bin_n')) as o1 \gset
select pg_temp.as_user(:'m', format('select public.inv_move_now(%L::uuid, %L::jsonb, ''bgr-1b T'')::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_n2', 'qty', 1)))) as o2 \gset
select pg_temp.try_undo(:'w', format('select public.inv_move_now(%L::uuid, %L::jsonb, ''bgr-1b T'')::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_n2', 'qty', 1)))) as o3 \gset
select pg_temp.chk(format('S0 before the trial: no bgrade_price · no ledger guard · old outputs captured (bin contents · no-stock_move refusal · a regular move)'),
  :s0_tbl = 0 and :s0_trg = 0 and :n_applied = 0 and :'o1' like '{%' and :'o2' like 'ERR P0001: You cannot change stock_move data%' and :'o3' like 'PASS: {%',
  format('%s | %s | %s', left(:'o1', 200), :'o2', left(:'o3', 200)));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: move · adjust · posting · 1a functions not re-issued are unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', :'fns_before', pg_temp.fns()));
\echo '── T) 옛 = 새 — B급이 끼지 않은 입력'
select pg_temp.as_user(:'w', format('select public.inv_move_bin_contents(%L::uuid, %L::uuid)::text', :'tor', :'bin_n')) as n1 \gset
select pg_temp.as_user(:'m', format('select public.inv_move_now(%L::uuid, %L::jsonb, ''bgr-1b T'')::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_n2', 'qty', 1)))) as n2 \gset
select pg_temp.try_undo(:'w', format('select public.inv_move_now(%L::uuid, %L::jsonb, ''bgr-1b T'')::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_n2', 'qty', 1)))) as n3 \gset
select pg_temp.chk('T old = new without a B-grade bin: bin contents (byte equal) · manager without stock_move still refused by Stock moves (same text) · a regular move (same result but move id · number)',
  :'o1' = :'n1' and :'o2' = :'n2' and pg_temp.norm_mv(pg_temp.j(substr(:'o3', 7))) = pg_temp.norm_mv(pg_temp.j(substr(:'n3', 7))),
  format('%s || %s | %s || %s | %s || %s', left(:'o1', 150), left(:'n1', 150), :'o2', :'n2', left(:'o3', 300), left(:'n3', 300)));
\else
select pg_temp.chk('P0c confirm run: migration 20261023135121 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select exists (select 1 from pg_class where relname = 'bgrade_price' and relnamespace = 'public'::regnamespace) as landed \gset
\if :landed
\echo '── G1) 모양'
select pg_temp.chk('G1 bgrade_price: RLS · select authenticated only · unique (bin, product) · windows authenticated only · core · triggers postgres only · ledger guard + 7 bin-column refusals enabled',
  (select relrowsecurity from pg_class where oid = 'public.bgrade_price'::regclass)
  and (select relacl::text from pg_class where oid = 'public.bgrade_price'::regclass) = '{postgres=arwdDxtm/postgres,authenticated=r/postgres}'
  and exists (select 1 from pg_constraint where conrelid = 'public.bgrade_price'::regclass and conname = 'bgrade_price_bin_product_key')
  and not has_function_privilege('anon', 'public.bgrade_move_in(uuid, jsonb, text)', 'execute') and has_function_privilege('authenticated', 'public.bgrade_move_out(uuid, jsonb, text)', 'execute')
  and not has_function_privilege('authenticated', 'public.bgrade_price_put(public.ref_bin, public.product, numeric, numeric, boolean, uuid)', 'execute')
  and (select count(*) from pg_trigger where not tgisinternal and tgenabled = 'O' and tgfoid in ('public.ims_bin_bgrade_refuse()'::regprocedure, 'public.inv_ledger_bgrade_guard()'::regprocedure)) = 8,
  'see G1');

\echo '── B1) move_in P 3 N → B 값 5.00 — 문 · 원장 · 레이어 · 가용 · B급 목록'
select (select count(*) || '/' || sum(qty) || '/' || sum(qty * unit_cost) from public.inv_layer where sku = 'BGRB-P' and warehouse = :'torname') as layer0 \gset
\set l_p3 '[{"product_id":"' :pid_p '","from_bin_id":"' :bin_n '","to_bin_id":"' :bin_b '","qty":3,"price":5}]'
select pg_temp.as_user(:'w', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', :'l_p3')) as b1w \gset
select pg_temp.as_user(:'k', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', :'l_p3')) as b1k \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', :'l_p3')) as b1 \gset
select (select string_agg(format('%s:%s:%s:%s', e.bin, trim_scale(e.qty_delta), e.event_type, e.raw->>'kind'), ' ' order by e.qty_delta) from public.inv_ledger e where e.doc_number = pg_temp.j(:'b1')->>'move_number') as b1_led,
       (select count(*) || '/' || sum(qty) || '/' || sum(qty * unit_cost) from public.inv_layer where sku = 'BGRB-P' and warehouse = :'torname') as layer1,
       (select format('%s/%s/%s/%s', trim_scale(qty_ea), trim_scale(sales_alloc_ea), trim_scale(transfer_alloc_ea), trim_scale(bgrade_ea)) from public.inv_available_base(:'tor'::uuid, array[:'pid_p'::uuid])) as b1_iab \gset
select pg_temp.bg_state(:'s', :'tor'::uuid) as b1_bg \gset
select pg_temp.chk(format('B1 worker (even with the key) · supervisor without the key refused · supervisor S moved: ledger %s · layers %s = %s · available %s · B-grade list %s', :'b1_led', :'layer0', :'layer1', :'b1_iab', :'b1_bg'),
  :'b1w' like 'ERR P0001: You cannot adjust stock%' and :'b1k' like 'ERR P0001: You cannot adjust stock%'
  and pg_temp.j(:'b1')->>'status' = 'confirmed' and pg_temp.j(:'b1')->>'kind' = 'bgrade_in' and (pg_temp.j(:'b1')->'prices'->0->>'price')::numeric = 5
  and :'b1_led' = 'BGRB-N:-3:transfer_out:bin_move BGRB-B:3:transfer_in:bin_move' and :'layer0' = :'layer1' and :'b1_iab' = '15/0/0/3' and :'b1_bg' = 'BGRB-B/BGRB-P 3@5.00',
  format('%s | %s | %s', :'b1w', :'b1k', left(:'b1', 600)));

\echo '── B2) 같은 값 더하기(값 없이 · stock_move 없는 manager) · 642 다른 값 거부(값 · %)'
select pg_temp.as_user(:'m', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b', 'qty', 2))))  as b2a \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b', 'qty', 1, 'price', 4)))) as b2b \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b', 'qty', 1, 'pct', 30)))) as b2c \gset
select pg_temp.bg_state(:'s', :'tor'::uuid) as b2_bg \gset
select pg_temp.chk(format('B2 manager M (adjust key, no stock_move) adds 2 at the live price · 4.00 and 30%% (= 7.00) refused (one price per SKU in a bin) · %s', :'b2_bg'),
  pg_temp.j(:'b2a')->>'status' = 'confirmed' and (pg_temp.j(:'b2a')->'prices'->0->>'price')::numeric = 5 and not (pg_temp.j(:'b2a')->'prices'->0->>'changed')::boolean
  and :'b2b' like 'ERR P0001: Bin BGRB-B already holds BGRB-P at 5.00 — one price per SKU in a B-grade bin%' and :'b2c' like 'ERR P0001: Bin BGRB-B already holds BGRB-P at 5.00%'
  and :'b2_bg' = 'BGRB-B/BGRB-P 5@5.00',
  format('%s | %s | %s', left(:'b2a', 400), :'b2b', :'b2c'));

\echo '── B3) 값 바꾸기 — p_reprice 없으면 거부 · 있으면 relabel 경고 · 같은 값 무해 · 문'
select pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 3.00)::text', :'bin_b', :'pid_p')) as b3a \gset
select pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 4.00, null, true)::text', :'bin_b', :'pid_p')) as b3b \gset
select pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 4.00)::text', :'bin_b', :'pid_p')) as b3c \gset
select pg_temp.as_user(:'w', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 4.00, null, true)::text', :'bin_b', :'pid_p')) as b3w \gset
select pg_temp.bg_state(:'s', :'tor'::uuid) as b3_bg \gset
select pg_temp.chk(format('B3 3.00 without reprice refused · reprice 5.00 → 4.00 (relabel warning) · 4.00 again no-op · worker refused · %s', :'b3_bg'),
  :'b3a' like 'ERR P0001: Bin BGRB-B already holds BGRB-P at 5.00%'
  and (pg_temp.j(:'b3b')->>'changed')::boolean and (pg_temp.j(:'b3b')->>'relabel')::boolean and (pg_temp.j(:'b3b')->>'previous_price')::numeric = 5 and pg_temp.j(:'b3b')->'warnings' = '["relabel"]'::jsonb
  and not (pg_temp.j(:'b3c')->>'changed')::boolean and :'b3w' like 'ERR P0001: You cannot adjust stock%' and :'b3_bg' = 'BGRB-B/BGRB-P 5@4.00',
  format('%s | %s | %s | %s', :'b3a', :'b3b', :'b3c', :'b3w'));

\echo '── B4) % — B2 에 P 30%% → 7.00 · Q % 거부(Wholesale 없음) · Q 값 2.50 · 검사들'
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b2', 'qty', 1, 'pct', 30)))) as b4a \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_q', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b2', 'qty', 1, 'pct', 30)))) as b4b \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('sku', 'BGRB-Q', 'from_bin', 'BGRB-N', 'to_bin', 'BGRB-B2', 'qty', 1, 'price', 2.50)))) as b4c \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_q', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b2', 'qty', 1), jsonb_build_object('product_id', :'pid_q', 'from_bin_id', :'bin_n2', 'to_bin_id', :'bin_b2', 'qty', 1)))) as b4d \gset
select concat_ws(' | ',
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 5, 30)::text', :'bin_b2', :'pid_p')),
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid)::text', :'bin_b2', :'pid_p')),
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, null, 0)::text', :'bin_b2', :'pid_p')),
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, null, 100)::text', :'bin_b2', :'pid_p')),
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, null, -5)::text', :'bin_b2', :'pid_p')),
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 0)::text', :'bin_b2', :'pid_p')),
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 1.234)::text', :'bin_b2', :'pid_p')),
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 3)::text', :'bin_b', :'pid_q')),
  pg_temp.as_user(:'s', format('select public.bgrade_price_set(%L::uuid, %L::uuid, 3)::text', :'bin_n', :'pid_p'))) as b4v \gset
select pg_temp.bg_state(:'s', :'tor'::uuid) as b4_bg \gset
select pg_temp.chk(format('B4 30%% off Wholesale 10.00 → 7.00 · Q by %% refused (no Wholesale) · Q at 2.50 by name · two lines same SKU and bin refused · both / neither / 0 / 100 / −5 %% / price 0 / 1.234 / no stock / regular bin refused · %s', :'b4_bg'),
  (pg_temp.j(:'b4a')->'prices'->0->>'price')::numeric = 7 and (pg_temp.j(:'b4a')->'prices'->0->>'basis_price')::numeric = 10 and (pg_temp.j(:'b4a')->'prices'->0->>'pct')::numeric = 30
  and :'b4b' like 'ERR P0001: No Wholesale price for BGRB-Q — enter a B-grade price instead%' and pg_temp.j(:'b4c')->>'status' = 'confirmed'
  and :'b4d' like 'ERR P0001: BGRB-Q is on two lines into bin BGRB-B2%'
  and :'b4v' ~ '^ERR P0001: Enter either a B-grade price or a percent off Wholesale, not both.* \| ERR P0001: Enter either.* \| ERR P0001: Percent off must be more than 0 and less than 100 \(got 0\).* \| ERR P0001: Percent off.*\(got 100\).* \| ERR P0001: Percent off.*\(got -5\).* \| ERR P0001: A B-grade price must be more than 0.* \| ERR P0001: A B-grade price is in cents.* \| ERR P0001: No B-grade stock of BGRB-Q in bin BGRB-B.* \| ERR P0001: Bin BGRB-N is not a B-grade bin.*$'
  and :'b4_bg' = 'BGRB-B/BGRB-P 5@4.00 BGRB-B2/BGRB-P 1@7.00(30% of 10) BGRB-B2/BGRB-Q 1@2.50',
  format('%s | %s | %s | %s | %s', left(:'b4a', 300), :'b4b', left(:'b4c', 120), :'b4d', :'b4v'));

\echo '── B5) move_out B → N 5 · 죽은 값 덮기 · B→B 거부(양쪽) · 정상 칸에서 move_out 거부'
select pg_temp.as_user(:'s', format('select public.bgrade_move_out(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_b', 'to_bin_id', :'bin_n', 'qty', 5)))) as b5a \gset
select pg_temp.bg_state(:'s', :'tor'::uuid) as b5a_bg \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_out(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_b2', 'to_bin_id', :'bin_b', 'qty', 1)))) as b5b \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_out(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_n2', 'qty', 1)))) as b5c \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_b2', 'to_bin_id', :'bin_b', 'qty', 1, 'price', 6)))) as b5d \gset
select pg_temp.as_user(:'s', format('select public.bgrade_move_in(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b', 'qty', 1, 'price', 6)))) as b5e \gset
select pg_temp.bg_state(:'s', :'tor'::uuid) as b5_bg \gset
select (select format('%s/%s/%s/%s', trim_scale(qty_ea), trim_scale(sales_alloc_ea), trim_scale(transfer_alloc_ea), trim_scale(bgrade_ea)) from public.inv_available_base(:'tor'::uuid, array[:'pid_p'::uuid])) as b5_iab \gset
select pg_temp.chk(format('B5 move back 5 (B empties: %s) · B2→B refused both ways · regular→regular via Move back refused · Move to B-grade at 6.00 over the dead 4.00 · %s · available %s', :'b5a_bg', :'b5_bg', :'b5_iab'),
  pg_temp.j(:'b5a')->>'kind' = 'bgrade_out' and pg_temp.j(:'b5a')->>'status' = 'confirmed' and :'b5a_bg' = 'BGRB-B2/BGRB-P 1@7.00(30% of 10) BGRB-B2/BGRB-Q 1@2.50'
  and :'b5b' like 'ERR P0001: To bin BGRB-B is a B-grade bin — B-grade to B-grade moves are not allowed%' and :'b5c' like 'ERR P0001: From bin BGRB-N is not a B-grade bin%'
  and :'b5d' like 'ERR P0001: From bin BGRB-B2 is a B-grade bin — B-grade to B-grade moves are not allowed%'
  and (pg_temp.j(:'b5e')->'prices'->0->>'changed')::boolean and not (pg_temp.j(:'b5e')->'prices'->0->>'relabel')::boolean
  and :'b5_bg' = 'BGRB-B/BGRB-P 1@6.00 BGRB-B2/BGRB-P 1@7.00(30% of 10) BGRB-B2/BGRB-Q 1@2.50' and :'b5_iab' = '16/0/0/2',
  format('%s | %s | %s | %s | %s', left(:'b5a', 200), :'b5b', :'b5c', :'b5d', left(:'b5e', 300)));

\echo '── B6) 기존 칸 옮기기 막기 — inv_move_now(N→B · B→N) · 칸 비우기(B) · 정상 옮기기 통과 · 칸을 B급으로 바꾼 뒤 확정 = 원장 가드'
select pg_temp.as_user(:'w', format('select public.inv_move_now(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b', 'qty', 1)))) as b6a \gset
select pg_temp.as_user(:'w', format('select public.inv_move_now(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('sku', 'BGRB-P', 'from_bin', 'BGRB-B', 'to_bin', 'BGRB-N', 'qty', 1)))) as b6b \gset
select pg_temp.as_user(:'w', format('select public.inv_move_bin_contents(%L::uuid, %L::uuid)::text', :'tor', :'bin_b')) as b6c \gset
select pg_temp.as_user(:'w', format('select public.inv_move_now(%L::uuid, %L::jsonb)::text', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_n2', 'qty', 1)))) as b6d \gset
select pg_temp.as_user(:'w', format('select public.inv_move_create(%L::uuid, ''bgr-1b B6'')->>''id''', :'tor')) as mv6 \gset
select pg_temp.as_user(:'w', format('select public.inv_move_line_set(%L::uuid, %L::jsonb)->>''line_id''', :'mv6', jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_n', 'to_bin_id', :'bin_b3', 'qty', 1))) as mv6l \gset
update public.ref_bin set is_bgrade = true where id = :'bin_b3'::uuid;
select pg_temp.as_user(:'w', format('select public.inv_move_confirm(%L::uuid)::text', :'mv6')) as b6e \gset
select pg_temp.chk('B6 Stock moves into and out of a B-grade bin refused (by id and by name) · bin contents of a B-grade bin refused · regular move passes · a draft made before the bin turned B-grade is stopped at confirm by the ledger guard',
  :'b6a' like 'ERR IM637: Stock move: bin BGRB-B is a B-grade bin — use Move to B-grade / Move back for B-grade bins%' and :'b6b' like 'ERR IM637: Stock move: bin BGRB-B is a B-grade bin%'
  and :'b6c' like 'ERR P0001: Bin BGRB-B is a B-grade bin — take stock out of it with Move back%' and pg_temp.j(:'b6d')->>'status' = 'confirmed'
  and :'mv6l' ~ '^[0-9a-f-]{36}$' and :'b6e' like 'ERR IM637: Bin BGRB-B3 in % is a B-grade bin — stock goes in or out of it only with Move to B-grade / Move back, a stock adjustment or a POS sale (transfer_in BGRB-P 1)%',
  format('%s | %s | %s | %s | %s | %s', :'b6a', :'b6b', :'b6c', left(:'b6d', 120), :'mv6l', :'b6e'));

\echo '── B7) 조정 — B 에 P +2(값 살아 있음 → 그대로) · B2 를 비운 뒤 P +2(0 에서 → 값 없음) · 레이어'
select pg_temp.as_user(:'s', format('select public.bgrade_move_out(%L::uuid, %L::jsonb)->>''status''', :'tor', jsonb_build_array(jsonb_build_object('product_id', :'pid_p', 'from_bin_id', :'bin_b2', 'to_bin_id', :'bin_n', 'qty', 1)))) as b7o \gset
select pg_temp.as_user(:'s', format('select public.inv_adjust_create(%L::uuid, ''bgr-1b B7'', null)->>''id''', :'tor')) as adj7 \gset
select pg_temp.as_user(:'s', format('select public.inv_adjust_line_set(%L::uuid, %L::jsonb)->>''line_id''', :'adj7', jsonb_build_object('product_id', :'pid_p', 'bin_id', :'bin_b', 'mode', 'delta', 'qty', 2, 'reason', 'found'))) as adj7a \gset
select pg_temp.as_user(:'s', format('select public.inv_adjust_line_set(%L::uuid, %L::jsonb)->>''line_id''', :'adj7', jsonb_build_object('product_id', :'pid_p', 'bin_id', :'bin_b2', 'mode', 'delta', 'qty', 2, 'reason', 'found'))) as adj7b \gset
select pg_temp.as_user(:'s', format('select public.inv_adjust_confirm(%L::uuid)::text', :'adj7')) as b7c \gset
select pg_temp.bg_state(:'s', :'tor'::uuid) as b7_bg \gset
select pg_temp.as_user(:'s', format('select (public.bgrade_stock(%L::uuid)->>''no_price_count'')', :'tor')) as b7_np \gset
select (select string_agg(format('%s:%s@%s', origin_type, trim_scale(qty), trim_scale(unit_cost)), ' ' order by id) from public.inv_layer where sku = 'BGRB-P' and warehouse = :'torname') as b7_layers \gset
select pg_temp.chk(format('B7 adjust +2 into B (live 6.00 kept) and +2 into B2 after it emptied (old 7.00 dropped → no price): %s · no-price rows %s · layers %s', :'b7_bg', :'b7_np', :'b7_layers'),
  :'b7o' = 'confirmed' and :'adj7b' ~ '^[0-9a-f-]{36}$' and pg_temp.j(:'b7c')->>'status' = 'confirmed'
  and :'b7_bg' = 'BGRB-B/BGRB-P 3@6.00 BGRB-B2/BGRB-P 2@- BGRB-B2/BGRB-Q 1@2.50' and :'b7_np'::int >= 1
  and (select count(*) from public.bgrade_price bp where bp.bin_id = :'bin_b2'::uuid and bp.product_id = :'pid_p'::uuid) = 0,
  format('%s | %s | %s | %s', :'b7o', :'adj7a', :'adj7b', left(:'b7c', 600)));

\echo '── B8) 칸 칸 이른 거부 일곱(B → IM637 · 정상 칸 → 트리거 통과 뒤 다른 제약) · 원장 가드 사건별'
select string_agg(format('%s.%s B=%s N=%s', t.tbl, t.col,
         left(pg_temp.try_undo(null, format('insert into public.%I (%I) values (%L::uuid) returning 1', t.tbl, t.col, :'bin_b')), 9),
         left(pg_temp.try_undo(null, format('insert into public.%I (%I) values (%L::uuid) returning 1', t.tbl, t.col, :'bin_n')), 9)), ' ; ' order by t.tbl, t.col) as b8a
  from (values ('po_receipt_line', 'bin_id'), ('po_receipt_work', 'bin_id'), ('po_receipt_diff', 'bin_id'), ('so_credit_line', 'restock_bin_id'),
               ('inv_transfer_settle', 'bin_id'), ('inv_move_line', 'from_bin_id'), ('inv_move_line', 'to_bin_id')) t(tbl, col) \gset
\echo :b8a
create function pg_temp.led(p_bin text, p_delta numeric, p_event text, p_kind text, p_source text, p_ref text, p_wh text) returns text language sql as $$
  select left(pg_temp.try_undo(null, format('insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source, raw) values (public.ims_today() - 1, 1, ''BGRB-P'', %L, %L, %s, %L, ''transfer'', ''BGRB-L8'', %L, %L, %L::jsonb) returning 1',
                    p_wh, p_bin, p_delta, p_event, p_ref, p_source, jsonb_build_object('kind', p_kind))), 9) $$;
select concat_ws(' ', 'po_in=' || pg_temp.led('BGRB-B', 1, 'po_in', 'po_in', 'ims', 'l1', :'torname'), 'transfer_in=' || pg_temp.led('BGRB-B', 1, 'transfer_in', 'transfer', 'ims', 'l2', :'torname'),
         'transfer_out=' || pg_temp.led('BGRB-B', -1, 'transfer_out', 'transfer', 'ims', 'l3', :'torname'), 'credit_in=' || pg_temp.led('BGRB-B', 1, 'credit_in', 'credit_in', 'ims', 'l4', :'torname'),
         'bin_move=' || pg_temp.led('BGRB-B', 1, 'transfer_in', 'bin_move', 'ims', 'l5', :'torname'), 'sale_out=' || pg_temp.led('BGRB-B', -1, 'sale_out', 'sale_out', 'ims', 'l6', :'torname'),
         'adjust=' || pg_temp.led('BGRB-B', 1, 'adjust_new', 'adjust', 'ims', 'l7', :'torname'), 'cin7_po_in=' || pg_temp.led('BGRB-B', 1, 'po_in', null, 'cin7', 'l8', :'torname'),
         'regular_po_in=' || pg_temp.led('BGRB-N', 1, 'po_in', 'po_in', 'ims', 'l9', :'torname')) as b8b \gset
select pg_temp.chk(format('B8 bin columns: B-grade → IM637 · regular bin passes the trigger (then the row''s own constraints) · ledger guard: %s', :'b8b'),
  :'b8a' = 'inv_move_line.from_bin_id B=ERR IM637 N=ERR 23502 ; inv_move_line.to_bin_id B=ERR IM637 N=ERR 23502 ; inv_transfer_settle.bin_id B=ERR IM637 N=ERR 23502 ; po_receipt_diff.bin_id B=ERR IM637 N=ERR 23502 ; po_receipt_line.bin_id B=ERR IM637 N=ERR 23502 ; po_receipt_work.bin_id B=ERR IM637 N=ERR 23502 ; so_credit_line.restock_bin_id B=ERR IM637 N=ERR 23502'
  and :'b8b' = 'po_in=ERR IM637 transfer_in=ERR IM637 transfer_out=ERR IM637 credit_in=ERR IM637 bin_move=ERR IM637 sale_out=PASS: 1 adjust=PASS: 1 cin7_po_in=PASS: 1 regular_po_in=PASS: 1',
  format('%s || %s', :'b8a', :'b8b'));

\echo '── B9) bgrade_price 직접 쓰기 거부 · 읽기 · 1a 가드 무사'
select pg_temp.as_role('authenticated', :'s', format('insert into public.bgrade_price (bin_id, product_id, price) values (%L::uuid, %L::uuid, 1) returning 1', :'bin_b', :'pid_q')) as b9a,
       pg_temp.as_role('authenticated', :'s', 'with u as (update public.bgrade_price set price = 1 returning 1) select count(*)::text from u') as b9b,
       pg_temp.as_role('authenticated', :'s', 'with u as (delete from public.bgrade_price returning 1) select count(*)::text from u') as b9c,
       pg_temp.as_role('authenticated', :'s', 'select count(*)::text from public.bgrade_price where bin_id in (select id from public.ref_bin where name like ''BGRB-%'')') as b9d,
       pg_temp.as_role('service_role', null, 'select count(*)::text from public.bgrade_price') as b9e,
       pg_temp.as_role('anon', null, 'select count(*)::text from public.bgrade_price') as b9f,
       pg_temp.as_role('authenticated', :'x', format('with u as (update public.ref_bin set is_bgrade = false where id = %L::uuid returning 1) select count(*)::text from u', :'bin_b')) as b9g \gset
select pg_temp.chk(format('B9 authenticated insert · update · delete refused (42501) · read %s rows · service_role · anon cannot read · 1a guard still refuses a direct is_bgrade change (IM636)', :'b9d'),
  :'b9a' like 'ERR 42501:%' and :'b9b' like 'ERR 42501:%' and :'b9c' like 'ERR 42501:%' and :'b9d' = '2' and :'b9e' like 'ERR 42501:%' and :'b9f' like 'ERR 42501:%' and :'b9g' like 'ERR IM636:%',
  format('%s | %s | %s | %s | %s | %s | %s', :'b9a', :'b9b', :'b9c', :'b9d', :'b9e', :'b9f', :'b9g'));

\echo '── S5) 1a 착지 — ims_inv_balance · inv_balance 를 읽고 bgrade 를 안 보는 함수 = 허락 목록(inv_move_bin_contents 가 빠져 여덟)'
create temp table bgr_src on commit drop as
  select p.proname, regexp_replace(p.prosrc, '--[^\n]*', '', 'g') as s from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f';
select (select string_agg(proname, ',' order by proname) from bgr_src where (s ~ '\mims_inv_balance\M' or s ~ '\minv_balance\M') and s !~ 'bgrade') as s5_blind \gset
select pg_temp.chk(format('S5 readers that do not look at bgrade = allowlist of eight (%s)', :'s5_blind'),
  :'s5_blind' = 'inv_adjust_ledger,inv_stock_master,inv_stock_master_sku,product_bom_set,product_update,stk_bins,stk_bins_many,wms_health_check', :'s5_blind');

\echo '── F5) 원장 창구 · 칸 FK 전수 — 새 길이 생기면 멈춘다'
select (select string_agg(proname, ',' order by proname) from bgr_src where s ~* 'insert\s+into\s+(public\.)?inv_ledger') as f5_writers,
       (select string_agg(c.conrelid::regclass::text || '.' || a.attname || '=' ||
                 case when exists (select 1 from pg_trigger t where t.tgrelid = c.conrelid and t.tgfoid = 'public.ims_bin_bgrade_refuse()'::regprocedure and not t.tgisinternal and t.tgenabled = 'O'
                                     and encode(t.tgargs, 'escape') like a.attname || '\\000%') then 'refuse'
                      when c.conrelid::regclass::text || '.' || a.attname in ('inv_adjust_line.bin_id') then 'allow:adjust'
                      when c.conrelid::regclass::text || '.' || a.attname in ('so_line.bgrade_bin_id') then 'allow:bgrade_line'
                      when c.conrelid::regclass::text || '.' || a.attname in ('product_bin_overflow.bin_id') then 'allow:display'
                      when c.conrelid::regclass::text || '.' || a.attname in ('wms_pick_line_bins.bin_id') then 'allow:1a_write_refuses'
                      else 'UNLISTED' end, ',' order by 1) from pg_constraint c join pg_attribute a on a.attrelid = c.conrelid and a.attnum = any(c.conkey)
         where c.contype = 'f' and c.confrelid = 'public.ref_bin'::regclass and c.conrelid <> 'public.bgrade_price'::regclass) as f5_fk \gset
\echo :f5_writers
\echo :f5_fk
select pg_temp.chk('F5 ledger writers = the twelve known (all behind the ledger guard) · every bin FK column is refused or on the allowlist · ledger guard on',
  :'f5_writers' = 'inv_post_adjust,inv_post_credit,inv_post_move,inv_post_receipt,inv_post_receipt_off_po,inv_post_receipt_over,inv_post_sale,inv_post_transfer_arrive,inv_post_transfer_depart,so_credit_cancel,tf_over_decide,tf_settle'
  and :'f5_fk' not like '%UNLISTED%' and (select count(*) from regexp_split_to_table(:'f5_fk', ',') x where x like '%=refuse') = 7
  and exists (select 1 from pg_trigger where tgrelid = 'public.inv_ledger'::regclass and tgname = 'inv_ledger_bgrade_guard' and tgenabled = 'O'),
  format('%s || %s', :'f5_writers', :'f5_fk'));
\else
select pg_temp.chk('G1 ~ F5 skipped: bgr-1b not landed', false, 'bgrade_price missing');
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real ledger · layers · moves · adjustments · bins that existed at the snapshot untouched', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before',
  format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));
select round(extract(epoch from clock_timestamp() - :'tb'::timestamptz)::numeric, 2) as tx_seconds_begin_to_rollback;
rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 되돌리기(greatest(실제 최대, 시작 값))'
select (select count(*) from public.product where sku like 'BGRB-%') + (select count(*) from public.ims_staff where email like 'bgrb-%') + (select count(*) from public.ref_bin where name like 'BGRB-%') + (select count(*) from public.inv_ledger where sku like 'BGRB-%') as leftovers;
select setval('public.inv_move_number_seq', greatest(coalesce((select max(substring(move_number from '[0-9]+')::bigint) from public.inv_move), 0), :mv_seq_last), :'mv_seq_called'::boolean) as inv_move_number_seq_reset_to;
select setval('public.inv_adjust_number_seq', greatest(coalesce((select max(substring(adjust_number from '[0-9]+')::bigint) from public.inv_adjust), 0), :adj_seq_last), :'adj_seq_called'::boolean) as inv_adjust_number_seq_reset_to;
