-- supabase/tests/tf_combo_1a_check.sql — tf-combo-1a(판정 952 · 953 ① · 956) 트랜스퍼 콤보 줄 · 문서 쪽 검증 (2026-11-02)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · tf_pallet_1_check 와 같은 꼴) — 기준(begin 앞) → begin → (-v mig 면 \i) → 꼴 · 기능 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261102100000_tf_combo_1a_lines.sql -f supabase/tests/tf_combo_1a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — M1(md5 바뀜)은 확인 갈래에 없다 ⇒ 확인 OK 수 = 시험 OK 수 − 1
--   쓰기 0 — 가짜 재료(TFC-T1 ~ T3 · 직원 하나)는 rollback · 상품은 실물 UNF18260(= UNF18054 ~ 57 × 6)을 읽기만 · 줄은 가짜 트랜스퍼에만 · transfer_number 는 직접 준다(시퀀스 안 당김) · identity(wms_pick_tasks)는 당긴다(틈만)
--   ⚠️ 테스트 DB = 운영 — 잠그는 것은 가짜 행뿐 · statement_timeout 120s · lock_timeout 3s
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 44
\else
\set EXPECT_OK 43
\endif
-- ── 기준(begin 앞 · 잠금 없음) ──
select (select count(*) from public.inv_transfer) as n_tf, (select count(*) from public.inv_transfer_line) as n_tfl, (select count(*) from public.ims_staff) as n_staff,
       (select count(*) from public.wms_pick_tasks) as n_pt, (select count(*) from public.shop_stock_queue) as n_ssq,
       (select count(*) from public.inv_transfer where transfer_number like 'TFC-%') as n_fake0,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('inv_transfer_line_set', 'inv_transfer_line_remove', 'inv_transfer_lines_paste', 'inv_transfer_shortage', 'inv_transfer_list', 'inv_available_base', 'stk_reserved', 'wms_pick_lines')) as fn_md5_0,
       (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || p.provolatile::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('inv_transfer_line_set', 'inv_transfer_line_remove', 'inv_transfer_lines_paste', 'inv_transfer_shortage', 'inv_transfer_list', 'inv_available_base', 'stk_reserved', 'wms_pick_lines')) as fn_acl_0,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('so_combo_children_insert', 'so_combo_children_sync', 'so_line_combo_parent_check', 'so_lines_available', 'so_line_add', 'so_line_remove', 'so_pick_plan', 'so_ship', 'so_finalize', 'wms_so_handoff', 'tf_depart', 'wms_finalize', 'stk_availability', 'pur_stock')) as so_md5_0
\gset
select id::text as wh1, name as wh1name from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as wh2 from public.ref_warehouse where name = 'Asung - Edmonton' \gset
select p.id::text as pc from public.product p where p.sku = 'UNF18260' \gset
select p.id::text as p54 from public.product p where p.sku = 'UNF18054' \gset
select p.id::text as p55 from public.product p where p.sku = 'UNF18055' \gset
select p.id::text as p56 from public.product p where p.sku = 'UNF18056' \gset
select p.id::text as p57 from public.product p where p.sku = 'UNF18057' \gset
-- 가용 식 기준(잠금 없음 · 다섯 키 · inv_available_base 다른 갈래 bal · alloc 전후 동일의 재료)
select md5(string_agg(m.stock_pid::text || ':' || trim_scale(m.qty_ea) || ':' || trim_scale(m.sales_alloc_ea) || ':' || trim_scale(m.bgrade_ea), ' ' order by m.stock_pid)) as iab_bal0,
       string_agg(m.stock_pid::text || ':' || trim_scale(m.transfer_alloc_ea), ' ' order by m.stock_pid) as iab_tal0
  from public.inv_available_base(:'wh1'::uuid, array[:'pc', :'p54', :'p55', :'p56', :'p57']::uuid[]) m \gset
\echo '── 기준: transfer' :n_tf '· lines' :n_tfl '· staff' :n_staff '· pick tasks' :n_pt '· shop queue' :n_ssq '· fake' :n_fake0
\echo '── fn md5(전):' :fn_md5_0
\echo '── 가용 bal md5(전):' :iab_bal0 '· talloc(전):' :iab_tal0

begin;
select clock_timestamp() as t_begin \gset
set local lock_timeout = '3s';
set local statement_timeout = '120s';
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.errp(p_sql text, p_prefix text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return 'NOERR';
exception when others then
  return case when p_prefix <> 'NOERR' and sqlerrm like p_prefix || '%' then 'starts: ' || p_prefix else 'got: ' || sqlerrm end;
end $$;
create function pg_temp.chkerr(p_name text, p_sql text, p_prefix text) returns void language sql as $$
  select pg_temp.chk(p_name, pg_temp.errp(p_sql, p_prefix), case when p_prefix = 'NOERR' then 'NOERR' else 'starts: ' || p_prefix end)
$$;
create function pg_temp.as_user(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true)
$$;
-- 줄 요약: line_no:sku:qty:combo_qty:pf(:C = 구성품 줄이 달린 콤보 줄)
create function pg_temp.lines(p_tf uuid) returns text language plpgsql as $$   -- plpgsql: 새 칸(combo_qty)을 읽는 도우미는 \i 전에 본문 검사가 서지 않게
begin
  return (select coalesce(string_agg(l.line_no || ':' || l.sku || ':' || trim_scale(l.qty) || ':' || coalesce(trim_scale(l.combo_qty)::text, '-') || ':' || trim_scale(l.pack_factor)
                             || case when exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l.id) then ':C' else '' end
                             || case when l.combo_line_id is not null then '>' || (select c.line_no from public.inv_transfer_line c where c.id = l.combo_line_id) else '' end, ',' order by l.line_no), '(none)')
  from public.inv_transfer_line l where l.transfer_id = p_tf);
end $$;
create function pg_temp.line(p_tf uuid, p_no int) returns uuid language sql as $$ select l.id from public.inv_transfer_line l where l.transfer_id = p_tf and l.line_no = p_no $$;

-- ── 재료: 직원(admin) · 초안 트랜스퍼 셋(토론토 → 에드먼턴 · 번호 직접) ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'tfc-a@test.invalid', 'TFC Admin', 'admin', '[]', '{}') returning auth_user_id::text as ua, id::text as sa \gset
insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, created_by) values ('TFC-T1', 'draft', :'wh1'::uuid, :'wh2'::uuid, :'sa'::uuid) returning id::text as t1 \gset
insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, created_by) values ('TFC-T2', 'draft', :'wh1'::uuid, :'wh2'::uuid, :'sa'::uuid) returning id::text as t2 \gset
insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, created_by) values ('TFC-T3', 'draft', :'wh1'::uuid, :'wh2'::uuid, :'sa'::uuid) returning id::text as t3 \gset
set local session_replication_role = origin;

\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select pg_temp.as_user(:'ua');

-- ── F 꼴 ──
select pg_temp.chk('F1 inv_transfer_line: combo_line_id uuid · combo_qty numeric',
  (select string_agg(c.column_name || ':' || c.data_type, ' ' order by c.column_name) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'inv_transfer_line' and c.column_name in ('combo_line_id', 'combo_qty')),
  'combo_line_id:uuid combo_qty:numeric');
select pg_temp.chk('F2 constraints: fk cascade · self · pair · qty · unique nulls not distinct (transfer, product, combo_line) · deferred parent trigger',
  (select string_agg(c.conname || '=' || pg_get_constraintdef(c.oid), ' ' order by c.conname) from pg_constraint c where c.conrelid = 'public.inv_transfer_line'::regclass and (c.conname like 'inv_transfer_line_combo%' or c.conname = 'inv_transfer_line_product_uq')),
  'inv_transfer_line_combo_line_id_fkey=FOREIGN KEY (combo_line_id) REFERENCES inv_transfer_line(id) ON DELETE CASCADE inv_transfer_line_combo_pair_ck=CHECK (((combo_line_id IS NULL) = (combo_qty IS NULL))) inv_transfer_line_combo_parent_ck=TRIGGER DEFERRABLE INITIALLY DEFERRED inv_transfer_line_combo_qty_ck=CHECK (((combo_qty IS NULL) OR (combo_qty > (0)::numeric))) inv_transfer_line_combo_self_ck=CHECK ((combo_line_id IS DISTINCT FROM id)) inv_transfer_line_product_uq=UNIQUE NULLS NOT DISTINCT (transfer_id, product_id, combo_line_id)');
select pg_temp.chk('F3 partial index on combo_line_id', (select count(*) from pg_indexes where tablename = 'inv_transfer_line' and indexname = 'inv_transfer_line_combo_line_id_idx' and indexdef like '%WHERE (combo_line_id IS NOT NULL)')::text, '1');
select pg_temp.chk('F4 helpers: authenticated · anon cannot call tf_combo_children_insert · _sync',
  (select string_agg(p.proname || ':' || has_function_privilege('authenticated', p.oid, 'execute')::text || has_function_privilege('anon', p.oid, 'execute')::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'tf_combo_children%'),
  'tf_combo_children_insert:falsefalse tf_combo_children_sync:falsefalse');
select pg_temp.chk('F5 eight reissued functions: acl · definer · volatility unchanged',
  (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || p.provolatile::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('inv_transfer_line_set', 'inv_transfer_line_remove', 'inv_transfer_lines_paste', 'inv_transfer_shortage', 'inv_transfer_list', 'inv_available_base', 'stk_reserved', 'wms_pick_lines')), :'fn_acl_0');
select pg_temp.chk('F6 SO · 창고 쪽 무접촉(14 functions md5)',
  (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('so_combo_children_insert', 'so_combo_children_sync', 'so_line_combo_parent_check', 'so_lines_available', 'so_line_add', 'so_line_remove', 'so_pick_plan', 'so_ship', 'so_finalize', 'wms_so_handoff', 'tf_depart', 'wms_finalize', 'stk_availability', 'pur_stock')), :'so_md5_0');
\if :{?mig}
select pg_temp.chk('M1 eight functions changed vs baseline md5 (시험 갈래만)',
  ((select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('inv_transfer_line_set', 'inv_transfer_line_remove', 'inv_transfer_lines_paste', 'inv_transfer_shortage', 'inv_transfer_list', 'inv_available_base', 'stk_reserved', 'wms_pick_lines')) <> :'fn_md5_0')::text, 'true');
\endif
select pg_temp.chk('A0 inv_available_base five keys: bal · alloc · bgrade identical before/after (talloc too — nothing of ours confirmed yet)',
  (select md5(string_agg(m.stock_pid::text || ':' || trim_scale(m.qty_ea) || ':' || trim_scale(m.sales_alloc_ea) || ':' || trim_scale(m.bgrade_ea), ' ' order by m.stock_pid)) || '|' || string_agg(m.stock_pid::text || ':' || trim_scale(m.transfer_alloc_ea), ' ' order by m.stock_pid)
     from public.inv_available_base(:'wh1'::uuid, array[:'pc', :'p54', :'p55', :'p56', :'p57']::uuid[]) m), :'iab_bal0' || '|' || :'iab_tal0');
-- 예약 기준(이 트랜잭션 · 우리 줄 전 · admin)
select coalesce((select m.transfer_alloc_ea from public.inv_available_base(:'wh1'::uuid, array[:'p54']::uuid[]) m), 0) as tal54_0,
       coalesce((select m.transfer_alloc_ea from public.inv_available_base(:'wh1'::uuid, array[:'p57']::uuid[]) m), 0) as tal57_0,
       coalesce((select m.transfer_alloc_ea from public.inv_available_base(:'wh1'::uuid, array[:'pc']::uuid[]) m), 0) as talc_0,
       (public.stk_reserved(:'p54'::uuid, :'wh1'::uuid) ->> 'trf_total')::numeric as trf54_0 \gset

-- ── L 줄 넣기 · 고치기 · 지우기(판정 952 · 956 · 이견 6) ──
select public.inv_transfer_line_set(:'t1'::uuid, '{"sku": "UNF18260", "qty": "2"}') as s1 \gset
select pg_temp.chk('L1 combo line: is_combo · 4 components · children qty 12 = 2 × 6 · combo_qty 6 · pf 1 · hang under line 1',
  (:'s1'::jsonb ->> 'is_combo') || '|' || (:'s1'::jsonb ->> 'components') || '|' || (:'s1'::jsonb ->> 'line_no') || '|' || pg_temp.lines(:'t1'::uuid),
  'true|4|1|1:UNF18260:2:-:1:C,2:UNF18054:12:6:1>1,3:UNF18055:12:6:1>1,4:UNF18056:12:6:1>1,5:UNF18057:12:6:1>1');
select public.inv_transfer_line_set(:'t1'::uuid, jsonb_build_object('line_id', pg_temp.line(:'t1'::uuid, 1), 'sku', 'UNF18260', 'qty', '1')) as s2 \gset
select pg_temp.chk('L2 combo qty 2 → 1: components follow (6 each) · updated_by set on children',
  pg_temp.lines(:'t1'::uuid) || '|' || (select count(*) from public.inv_transfer_line l where l.transfer_id = :'t1'::uuid and l.combo_line_id is not null and l.updated_by = :'sa'::uuid),
  '1:UNF18260:1:-:1:C,2:UNF18054:6:6:1>1,3:UNF18055:6:6:1>1,4:UNF18056:6:6:1>1,5:UNF18057:6:6:1>1|4');
select pg_temp.chkerr('L3 editing a component line directly: refused',
  format('select public.inv_transfer_line_set(%L, jsonb_build_object(''line_id'', %L, ''sku'', ''UNF18054'', ''qty'', ''9''))::text', :'t1', pg_temp.line(:'t1'::uuid, 2)),
  'Line 2 (UNF18054) is a component of combo UNF18260 (line 1) — change the combo line instead');
select pg_temp.chkerr('L4 removing a component line: refused',
  format('select public.inv_transfer_line_remove(%L, %L)::text', :'t1', pg_temp.line(:'t1'::uuid, 2)),
  'Line 2 (UNF18054) is a component of combo UNF18260 (line 1) — remove the combo line instead');
select public.inv_transfer_line_set(:'t1'::uuid, '{"sku": "UNF18054", "qty": "12"}') as s3 \gset
select pg_temp.chk('L5 (판정 956) same SKU as an ordinary line next to its component line: allowed · not a combo · line 6',
  (:'s3'::jsonb ->> 'is_combo') || '|' || (:'s3'::jsonb ->> 'line_no') || '|' || (select count(*) from public.inv_transfer_line l where l.transfer_id = :'t1'::uuid and l.sku = 'UNF18054'), 'false|6|2');
select pg_temp.chkerr('L6 a second combo line for the same SKU: refused (unique (t, pid, null))',
  format('select public.inv_transfer_line_set(%L, ''{"sku": "UNF18260", "qty": "1"}'')::text', :'t1'), 'Transfer TFC-T1 already has a line for UNF18260 — change that line instead');
select pg_temp.chkerr('L6a a second ordinary line for UNF18054: refused as before',
  format('select public.inv_transfer_line_set(%L, ''{"sku": "UNF18054", "qty": "1"}'')::text', :'t1'), 'Transfer TFC-T1 already has a line for UNF18054 — change that line instead');
select pg_temp.chkerr('L7 (이견 6) changing the combo line to another product: refused',
  format('select public.inv_transfer_line_set(%L, jsonb_build_object(''line_id'', %L, ''sku'', ''UNF18056'', ''qty'', ''1''))::text', :'t1', pg_temp.line(:'t1'::uuid, 1)),
  'Line 1 (UNF18260) — a combo line cannot be changed to another product, and a line cannot be changed into a combo — remove the line and add it again');
select pg_temp.chkerr('L7a changing an ordinary line into the combo product: refused too',
  format('select public.inv_transfer_line_set(%L, jsonb_build_object(''line_id'', %L, ''sku'', ''UNF18260'', ''qty'', ''1''))::text', :'t1', pg_temp.line(:'t1'::uuid, 6)),
  'Line 6 (UNF18054) — a combo line cannot be changed to another product, and a line cannot be changed into a combo — remove the line and add it again');
select pg_temp.chk('L7b ordinary → ordinary product change still works (UNF18054 → UNF18057 · beside its component line)',
  (select (j ->> 'sku') || '|' || (j ->> 'is_combo') from public.inv_transfer_line_set(:'t1'::uuid, jsonb_build_object('line_id', pg_temp.line(:'t1'::uuid, 6), 'sku', 'UNF18057', 'qty', '12')) j), 'UNF18057|false');
-- 부모 검사(deferred 제약 트리거 — 문장 끝에 보게 immediate 로 토글)
set constraints all immediate;
select pg_temp.chkerr('T1 component hanging under a combo line of another transfer: refused',
  format('insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor, combo_line_id, combo_qty) values (%L, 99, %L, ''UNF18055'', 6, 1, %L, 6) returning id::text', :'t2', :'p55', pg_temp.line(:'t1'::uuid, 1)),
  'Line 99 (UNF18055) hangs under combo line 1 of another transfer');
select pg_temp.chkerr('T2 component hanging under a component line (combo in combo): refused',
  format('insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor, combo_line_id, combo_qty) values (%L, 99, %L, ''UNF18055'', 6, 1, %L, 6) returning id::text', :'t1', :'p55', pg_temp.line(:'t1'::uuid, 2)),
  'Line 99 (UNF18055) hangs under line 2, which is itself a component — a combo cannot contain a combo');
select pg_temp.chkerr('T3 pair check: combo_qty without combo_line_id refused',
  format('insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor, combo_qty) values (%L, 99, %L, ''UNF18055'', 6, 1, 6) returning id::text', :'t2', :'p55'),
  'new row for relation "inv_transfer_line" violates check constraint "inv_transfer_line_combo_pair_ck"');
set constraints all deferred;

-- ── P 붙여 넣기(이견 5 (가)) — 빈 초안 T2 에서 미리 보기(T1 에는 콤보 줄이 이미 있어 exists 가 맞다) ──
select public.inv_transfer_lines_paste(:'t2'::uuid, '[{"sku": "UNF18260", "qty": "100"}, {"sku": "UNF18055", "qty": "5"}, {"sku": "UNF18260", "qty": "1"}, {"sku": "UNF18054", "qty": "3"}]', false) as pv \gset
-- 기대: 콤보 줄 short_by(콤보 단위) = least(100, max_c ⌈(붙인 보통 ok 줄 EA + 100 × 6 − 가용_c) ÷ 6⌉) · available_units = min_c ⌊가용_c ÷ 6⌋ · T2 기존 줄 0 · 붙인 보통 = UNF18055 5 · UNF18054 3
with c as (select coalesce(cp.parent_product_id, cp.id) as pid, cp.sku from public.product_bom b join public.product cp on cp.id = b.component_product_id where b.parent_product_id = :'pc'::uuid and b.is_active),
     av as (select m.stock_pid, coalesce(m.available_ea, 0) as a from public.so_available_many((select array_agg(pid) from c), :'wh1'::uuid) m),
     add as (select :'p54'::uuid as pid, 3::numeric as ea union all select :'p55'::uuid, 5)
select least(100, max(ceil(greatest(coalesce(ad.ea, 0) + 600 - av.a, 0) / 6)))::text as exp_short,
       min(floor(greatest(av.a, 0) / 6))::text as exp_units,
       string_agg(c.sku || ':' || trim_scale(greatest(coalesce(ad.ea, 0) + 600 - av.a, 0)), ',' order by c.sku) as exp_short_ea,
       -- summary.short 기대 = 콤보 줄(모자라면 1) + 보통 ok 줄 둘(같은 재고 키를 콤보가 먼저 끌어 쓰므로 함께 모자랄 수 있다)
       ((case when least(100, max(ceil(greatest(coalesce(ad.ea, 0) + 600 - av.a, 0) / 6))) > 0 then 1 else 0 end) + count(*) filter (where ad.ea is not null and coalesce(ad.ea, 0) + 600 - av.a > 0))::text as exp_n_short
  from c join av on av.stock_pid = c.pid left join add ad on ad.pid = c.pid \gset
select pg_temp.chk('P1 preview verdicts on T2: combo ok · ok · duplicate(combo again) · ok',
  (select string_agg(l ->> 'verdict', ',' order by (l ->> 'n')::int) from jsonb_array_elements(:'pv'::jsonb -> 'lines') l), 'ok,ok,duplicate,ok');
select pg_temp.chk('P2 combo row: is_combo · 4 components with need_ea 600 · per-component short_ea · available_ea null · short_by in combos · available_units (expected from so_available_many)',
  (select (l ->> 'is_combo') || '|' || jsonb_array_length(l -> 'components') || '|' || (select string_agg((k ->> 'sku') || ':' || (k ->> 'need_ea') || ':' || (k ->> 'short_ea'), ',' order by k ->> 'sku') from jsonb_array_elements(l -> 'components') k)
          || '|' || coalesce(l ->> 'available_ea', 'null') || '|' || (l ->> 'short_by') || '|' || (l ->> 'available_units') from jsonb_array_elements(:'pv'::jsonb -> 'lines') l where (l ->> 'n')::int = 1),
  'true|4|' || regexp_replace(:'exp_short_ea', '([A-Z0-9]+):', '\1:600:', 'g') || '|null|' || :'exp_short' || '|' || :'exp_units');
select pg_temp.chk('P3 combo row message says short_by_N_combos · summary.short counts it · ordinary rows is_combo false · components null',
  (select ((l ->> 'message') like '%short_by_' || :'exp_short' || '_combos — components short%')::text from jsonb_array_elements(:'pv'::jsonb -> 'lines') l where (l ->> 'n')::int = 1)
  || '|' || (:'pv'::jsonb -> 'summary' ->> 'short') || '|' || (select string_agg((l ->> 'is_combo') || ':' || coalesce(l ->> 'components', 'null'), ',' order by (l ->> 'n')::int) from jsonb_array_elements(:'pv'::jsonb -> 'lines') l where (l ->> 'n')::int in (2, 4)),
  'true|' || :'exp_n_short' || '|false:null,false:null');
select pg_temp.chk('P4 nothing inserted by the preview', pg_temp.lines(:'t2'::uuid), '(none)');
select public.inv_transfer_lines_paste(:'t2'::uuid, '[{"sku": "UNF18260", "qty": "3"}, {"sku": "UNF18056", "qty": "2"}]', true) as pc2 \gset
select pg_temp.chk('P5 paste commit on T2: combo inserted with 4 components (qty 18) + ordinary UNF18056 2 · inserted 2',
  (:'pc2'::jsonb -> 'summary' ->> 'inserted') || '|' || pg_temp.lines(:'t2'::uuid),
  '2|1:UNF18260:3:-:1:C,2:UNF18054:18:6:1>1,3:UNF18055:18:6:1>1,4:UNF18056:18:6:1>1,5:UNF18057:18:6:1>1,6:UNF18056:2:-:1');
select pg_temp.chk('P6 paste again on T2: combo → exists(line 1) · its component SKU as ordinary → ok (956)',
  (select string_agg((l ->> 'verdict') || ':' || coalesce(l ->> 'line_no', '-'), ',' order by (l ->> 'n')::int) from jsonb_array_elements(public.inv_transfer_lines_paste(:'t2'::uuid, '[{"sku": "UNF18260", "qty": "1"}, {"sku": "UNF18054", "qty": "1"}]', false) -> 'lines') l), 'exists:-,ok:7');

-- ── S 가용 · 확정(판정 953 ①) ──
select pg_temp.chk('S1 shortage counts component lines, not the combo line (need = combo 6 + ordinary UNF18057 12 → 18 · shows only short keys)',
  (select coalesce(string_agg((e ->> 'sku') || ':' || (e ->> 'need_ea'), ',' order by e ->> 'sku'), '(none)') from jsonb_array_elements(public.inv_transfer_shortage(:'t1'::uuid)) e where e ->> 'sku' = 'UNF18260'), '(none)');
select public.inv_transfer_line_set(:'t1'::uuid, jsonb_build_object('line_id', pg_temp.line(:'t1'::uuid, 1), 'sku', 'UNF18260', 'qty', '1000'));
select pg_temp.chk('S2 combo 1000 → components 6000 each · shortage lists the four components (need 6000 · 6012 for UNF18057) and not UNF18260',
  (select string_agg((e ->> 'sku') || ':' || (e ->> 'need_ea'), ',' order by e ->> 'sku') from jsonb_array_elements(public.inv_transfer_shortage(:'t1'::uuid)) e), 'UNF18054:6000,UNF18055:6000,UNF18056:6000,UNF18057:6012');
select pg_temp.chkerr('S3 confirm refused on component shortage', format('select public.inv_transfer_confirm(%L)::text', :'t1'), 'Transfer TFC-T1 cannot be confirmed — not enough available at the from warehouse: UNF18054 needs 6000');
select public.inv_transfer_line_set(:'t1'::uuid, jsonb_build_object('line_id', pg_temp.line(:'t1'::uuid, 1), 'sku', 'UNF18260', 'qty', '1'));
select pg_temp.chk('S4 confirm ok with combo 1 (components 6 each)', (select j ->> 'status' from public.inv_transfer_confirm(:'t1'::uuid) j), 'confirmed');
select pg_temp.chk('A1 (판정 566) after confirm: inv_available_base talloc UNF18054 +6 · UNF18057 +18 · combo pid +0 · stk_reserved trf_total UNF18054 = talloc',
  (select trim_scale(m.transfer_alloc_ea - :tal54_0) from public.inv_available_base(:'wh1'::uuid, array[:'p54']::uuid[]) m) || '|' ||
  (select trim_scale(m.transfer_alloc_ea - :tal57_0) from public.inv_available_base(:'wh1'::uuid, array[:'p57']::uuid[]) m) || '|' ||
  trim_scale(coalesce((select m.transfer_alloc_ea from public.inv_available_base(:'wh1'::uuid, array[:'pc']::uuid[]) m), 0) - :talc_0) || '|' ||
  trim_scale((public.stk_reserved(:'p54'::uuid, :'wh1'::uuid) ->> 'trf_total')::numeric - :trf54_0) || '|' ||
  (select ((public.stk_reserved(:'p54'::uuid, :'wh1'::uuid) ->> 'trf_total')::numeric = m.transfer_alloc_ea)::text from public.inv_available_base(:'wh1'::uuid, array[:'p54']::uuid[]) m),
  '6|18|0|6|true');
select pg_temp.chk('A2 stk_reserved trf list for UNF18054 has the component line (TFC-T1 · 6) and no combo line',
  (select string_agg((t ->> 'transfer_number') || ':' || (t ->> 'line_sku') || ':' || (t ->> 'qty_ea'), ',') from jsonb_array_elements(public.stk_reserved(:'p54'::uuid, :'wh1'::uuid) -> 'trf') t where t ->> 'transfer_number' = 'TFC-T1'), 'TFC-T1:UNF18054:6');
select pg_temp.chk('A3 inv_available_base keys: bal · alloc · bgrade of the five keys unchanged (only talloc moved)',
  (select md5(string_agg(m.stock_pid::text || ':' || trim_scale(m.qty_ea) || ':' || trim_scale(m.sales_alloc_ea) || ':' || trim_scale(m.bgrade_ea), ' ' order by m.stock_pid)) from public.inv_available_base(:'wh1'::uuid, array[:'pc', :'p54', :'p55', :'p56', :'p57']::uuid[]) m), :'iab_bal0');

-- ── V 뷰 · 픽 줄 · 목록 ──
select pg_temp.chk('V1 wms_order_doc_line(T1): no combo line · components carry combo_line_id · combo_qty 6 · combo_sku · ordinary line nulls · 5 rows',
  (select string_agg(x.line_no || ':' || x.sku || ':' || coalesce(trim_scale(x.combo_qty)::text, '-') || ':' || coalesce(x.combo_sku, '-') || ':' || coalesce((x.combo_line_id = pg_temp.line(:'t1'::uuid, 1))::text, '-'), ',' order by x.line_no) from public.wms_order_doc_line x where x.doc_id = :'t1'::uuid),
  '2:UNF18054:6:UNF18260:true,3:UNF18055:6:UNF18260:true,4:UNF18056:6:UNF18260:true,5:UNF18057:6:UNF18260:true,6:UNF18057:-:-:-');
set local session_replication_role = replica;
insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (:'t3'::uuid, 1, :'pc'::uuid, 'UNF18260', 1, 1);   -- 구성품 없는 콤보 상품 줄(TRF-00003 #316 꼴 · 기존 행)
insert into public.wms_pick_tasks (transfer_id, batch_label, status, assigned_to) values (:'t1'::uuid, 'A', 'pending', :'sa'::uuid) returning id::text as pt \gset
insert into public.wms_pick_task_lines (pick_task_id, transfer_line_id, assigned_base, picked_base, status) values (:'pt'::bigint, pg_temp.line(:'t1'::uuid, 2), 6, 0, 'pending'), (:'pt'::bigint, pg_temp.line(:'t1'::uuid, 6), 12, 0, 'pending');
set local session_replication_role = origin;
select pg_temp.chk('V2 (이견 7) a combo-product line without components is an ordinary line: in the view · shortage counts UNF18260 itself',
  (select string_agg(x.sku || ':' || coalesce(x.combo_sku, '-'), ',') from public.wms_order_doc_line x where x.doc_id = :'t3'::uuid) || '|' || (select string_agg((e ->> 'sku') || ':' || (e ->> 'need_ea'), ',') from jsonb_array_elements(public.inv_transfer_shortage(:'t3'::uuid)) e), 'UNF18260:-|UNF18260:1');
select coalesce((select jsonb_agg(b.barcode order by b.is_primary desc, b.barcode) from public.product_barcode b where b.product_id = :'pc'::uuid and b.is_active), '[]'::jsonb)::text as bc_c \gset
select pg_temp.chk('V3 wms_pick_lines(transfer task): component row has combo_sku · combo_barcodes = UNF18260 barcodes · ordinary row []',
  (select string_agg((l ->> 'sku') || ':' || coalesce(l ->> 'combo_sku', '-') || ':' || (l -> 'combo_barcodes')::text, ',' order by (l ->> 'order_line_id')) from jsonb_array_elements(public.wms_pick_lines(array[:'pt'::bigint])) l),
  (select string_agg(s, ',' order by o) from (values (pg_temp.line(:'t1'::uuid, 2)::text, 'UNF18054:UNF18260:' || :'bc_c'), (pg_temp.line(:'t1'::uuid, 6)::text, 'UNF18057:-:[]')) v(o, s)));
select pg_temp.chk('V4 inv_transfer_list(TFC-T1): line_count 5 (4 components + 1 ordinary) · qty_ea 36',
  (select (t ->> 'line_count') || '|' || (t ->> 'qty_ea') from jsonb_array_elements(public.inv_transfer_list('{"q": "TFC-T1"}')) t where t ->> 'transfer_number' = 'TFC-T1'), '5|36');
select pg_temp.chk('V5 combo barcodes are real (UNF18260 has at least one active barcode)', (jsonb_array_length(:'bc_c'::jsonb) >= 1)::text, 'true');

-- ── D 지우기 ──
set local session_replication_role = replica;
delete from public.wms_pick_task_lines where pick_task_id = :'pt'::bigint;   -- 가짜 픽 줄(V3 재료 · RESTRICT FK)
delete from public.wms_pick_tasks where id = :'pt'::bigint;
set local session_replication_role = origin;
select public.inv_transfer_unconfirm(:'t1'::uuid);
select pg_temp.chk('D1 removing the combo line removes its 4 components · ordinary line stays',
  (select j ->> 'removed_components' from public.inv_transfer_line_remove(:'t1'::uuid, pg_temp.line(:'t1'::uuid, 1)) j) || '|' || pg_temp.lines(:'t1'::uuid), '4|6:UNF18057:12:-:1');
select pg_temp.chk('D2 list after removal: line_count 1 · qty_ea 12 · view 1 row',
  (select (t ->> 'line_count') || '|' || (t ->> 'qty_ea') from jsonb_array_elements(public.inv_transfer_list('{"q": "TFC-T1"}')) t where t ->> 'transfer_number' = 'TFC-T1') || '|' || (select count(*) from public.wms_order_doc_line x where x.doc_id = :'t1'::uuid), '1|12|1');
select pg_temp.chkerr('D3 removing the ordinary line still works', format('select public.inv_transfer_line_remove(%L, %L)::text', :'t1', pg_temp.line(:'t1'::uuid, 6)), 'NOERR');
select pg_temp.chk('D4 cascade: deleting a combo line row directly takes its components (T2)',
  (select pg_temp.run(format('delete from public.inv_transfer_line where id = %L returning id::text', pg_temp.line(:'t2'::uuid, 1))) is not null)::text || '|' || pg_temp.lines(:'t2'::uuid), 'true|6:UNF18056:2:-:1');
-- 큐(정보 · 검사 아님): shop_stock_queue 에 콤보 pid 가 들었는가
select count(*) filter (where q.product_id = :'pc'::uuid) as q_combo, count(*) as q_all from public.shop_stock_queue q where q.queued_at >= now() and q.product_id in (:'pc'::uuid, :'p54'::uuid, :'p55'::uuid, :'p56'::uuid, :'p57'::uuid) \gset
\echo '── shop_stock_queue(이 트랜잭션 · 다섯 pid): 콤보 pid' :q_combo '· 전체' :q_all '(함수 수정 0 · 해롭지 않다 · rollback)'

-- ── 화면이 쓸 창구 꼴(보고용 출력) ──
\echo '── 창구 꼴: inv_transfer_line_set(combo) →' :s1
select (:'pv'::jsonb -> 'lines' -> 0)::text as pv0 \gset
\echo '── 창구 꼴: inv_transfer_lines_paste preview combo row →' :pv0
select (:'pv'::jsonb -> 'summary')::text as pvs \gset
\echo '── 창구 꼴: inv_transfer_lines_paste preview summary →' :pvs
select (select x from public.wms_order_doc_line x where x.doc_id = :'t2'::uuid and x.line_no = 6)::text as vrow \gset
\echo '── 창구 꼴: wms_order_doc_line ordinary row →' :vrow

select pg_temp.chk('X1 fake rows present (rolled back below): 3 TFC transfers · 1 staff', (select count(*) from public.inv_transfer where transfer_number like 'TFC-T%') || '/' || (select count(*) from public.ims_staff where email like 'tfc-%'), '3/1');
\echo '── 결과(OK · MISMATCH) ──'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' | want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
\echo '── OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
select (clock_timestamp() - :'t_begin'::timestamptz)::text as in_tx \gset
\echo '── begin ~ rollback:' :in_tx
rollback;
-- ── 뒤: 실제 행 무변 ──
select (select count(*) from public.inv_transfer) = :n_tf and (select count(*) from public.inv_transfer_line) = :n_tfl and (select count(*) from public.ims_staff) = :n_staff
   and (select count(*) from public.wms_pick_tasks) = :n_pt and (select count(*) from public.shop_stock_queue) = :n_ssq
   and (select count(*) from public.inv_transfer where transfer_number like 'TFC-%') = :n_fake0 as rows_unchanged_after_rollback \gset
\echo '── rollback 뒤 실제 행 무변:' :rows_unchanged_after_rollback
select case when :n_bad = 0 and :n_ok = :EXPECT_OK and :'rows_unchanged_after_rollback' = 't' then 'PASS' else 'FAIL' end as verdict;
