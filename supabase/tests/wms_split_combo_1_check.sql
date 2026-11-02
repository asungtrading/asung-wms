-- supabase/tests/wms_split_combo_1_check.sql — wms-split-combo-1(판정 972 · 973) 한 콤보 줄의 구성품은 한 조각에 — wms_batch_create 거부 검증 (2026-11-02)
-- [메인 IMS · Asung-IMS] 시험 적용 장치 틀(combo_bc_1_check 와 같은 꼴) — 기준(begin 앞 · 잠금 없음) → begin → 가짜 재료 WSC-* (replica)
--   → (-v mig 면: R 옛 창구로 같은 입력을 돌려 서명을 담고 savepoint 로 되감은 뒤 \i) → S 판매(갈림 거부 · 셋 갈림 · 두 콤보 · 저장 0 · 같이 통과 · 큰 콤보 한 조각)
--   → N 콤보 없는 오더 · T 트랜스퍼 · C 옛 = 새(통과 갈래 서명) · E 꼴(본문 = 원본 + 더한 줄 · 속성 · comment · 무접촉 md5) → rollback → Z 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261102180122_wms_split_combo_1.sql -f supabase/tests/wms_split_combo_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 20 · 확인(적용 뒤) 16 — R1(옛 창구가 갈린 조각을 받았다 = 결함 재현) · C1 ~ C3(옛 = 새)는 시험 갈래만 · Z 는 t_res 밖 한 줄
--   쓰기 0 — 가짜 재료는 rollback · so_number 글자 그대로 SO-00000wscx · wscy(접미는 글자만) · 트랜스퍼 WSC-T1 · ⚠️ identity(wms_pick_tasks · wms_pick_task_lines · wms_pick_line_bins)는 당긴다(틈만)
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback) · 실제 오더 행은 잠그지 않는다(가짜 문서만 for update) · lock_timeout 3s
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 20
\else
\set EXPECT_OK 16
\endif
\pset pager off
select (select count(*) from public.so) as n_so0, (select count(*) from public.so_line) as n_line0, (select count(*) from public.inv_transfer) as n_tf0, (select count(*) from public.inv_transfer_line) as n_tfl0,
       (select count(*) from public.wms_pick_tasks) as n_pt0, (select count(*) from public.wms_pick_task_lines) as n_ptl0, (select count(*) from public.wms_pick_line_bins) as n_plb0,
       (select count(*) from public.product) as n_prod0, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('wms_wave_create', 'wms_pick_task_build', 'so_pick_plan', 'wms_pick_lines', 'wms_doc_status')) as un_md5_0,
       (select coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner)
          from pg_proc p where p.oid = 'public.wms_batch_create(uuid, jsonb)'::regprocedure) as attr_0,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1, (select name from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1name,
       (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as wh2,
       (select id::text from public.ref_currency where code = 'CAD') as cad \gset
\echo '── 기준: so' :n_so0 '· so_line' :n_line0 '· transfer' :n_tf0 '· pick_tasks' :n_pt0 '· pick_lines' :n_ptl0 '· bins' :n_plb0
\echo '── 속성(전):' :attr_0
begin;
set local lock_timeout = '3s';
set local statement_timeout = '30s';
select clock_timestamp() as t_begin \gset
create temp table t_pre as select proname, prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_batch_create';

-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
-- 창구 한 번 → 성공이면 'OK <status>' · 실패면 'ERR <sqlerrm>'
create function pg_temp.bc(p_doc uuid, p_batches jsonb) returns text language plpgsql as $$
declare v jsonb;
begin
  v := public.wms_batch_create(p_doc, p_batches);
  return 'OK ' || (v->>'status');
exception when others then return 'ERR ' || sqlerrm;
end $$;
-- line_no 목록들 → p_batches([[1,2],[3]] → [{line_ids:[…]},{…}])
create function pg_temp.bt(p_doc uuid, p jsonb) returns jsonb language sql as $$
  select jsonb_agg(jsonb_build_object('line_ids', (select jsonb_agg(l.line_id order by l.line_no) from jsonb_array_elements_text(g.e) x(no) join public.wms_order_doc_line l on l.doc_id = p_doc and l.line_no = x.no::int)) order by g.o)
  from jsonb_array_elements(p) with ordinality g(e, o)
$$;
-- 만든 것의 서명(id 없이): 문서 상태 · 과제마다 라벨:sku 목록 · 계획 칸 행 수(가짜 제품은 칸 · 장부가 없어 계획 칸 '' → 행 0 · 옛 창구도 같다 — C1 ~ C3)
create function pg_temp.sig(p_doc uuid) returns text language sql as $$
  select (select d.status from public.wms_order_doc d where d.doc_id = p_doc) || ' | ' ||
         coalesce((select string_agg(t.batch_label || ':' || (select string_agg(l.sku || '×' || trim_scale(tl.assigned_base)::text, ',' order by l.line_no)
                                                            from public.wms_pick_task_lines tl join public.wms_order_doc_line l on l.line_id = coalesce(tl.order_line_id, tl.transfer_line_id) where tl.pick_task_id = t.id)
                                                   || ':bins ' || (select count(*) from public.wms_pick_line_bins b join public.wms_pick_task_lines tl on tl.id = b.pick_task_line_id where tl.pick_task_id = t.id),
                                     ' ; ' order by t.batch_label)
                   from public.wms_pick_tasks t where coalesce(t.order_id, t.transfer_id) = p_doc), '(no tasks)')
$$;

-- ── 재료(replica · 전부 rollback): 직원 · 손님 · 제품(콤보 셋 · 구성품 여섯 · 보통 하나) · 판매 둘 · 트랜스퍼 하나 ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'wsc1-mgr@test.invalid', 'WSC1 manager', 'manager', '["ims","wms","picking","packing","wms_manage"]', '{}') returning auth_user_id::text as u_mgr \gset
insert into public.customer (name, source, currency_id) values ('WSC1 Customer', 'manual', :'cad'::uuid) returning id::text as cust \gset
insert into public.product (sku, name, source) values ('WSC-COMBO', 'WSC combo 1', 'manual') returning id::text as pc1 \gset
insert into public.product (sku, name, source) values ('WSC-COMBO2', 'WSC combo 2', 'manual') returning id::text as pc2 \gset
insert into public.product (sku, name, source) values ('WSC-BIG', 'WSC big combo', 'manual') returning id::text as pcb \gset
insert into public.product (sku, name, source) values ('WSC-A', 'WSC A', 'manual') returning id::text as pa \gset
insert into public.product (sku, name, source) values ('WSC-B', 'WSC B', 'manual') returning id::text as pb \gset
insert into public.product (sku, name, source) values ('WSC-C', 'WSC C', 'manual') returning id::text as pcc \gset
insert into public.product (sku, name, source) values ('WSC-D', 'WSC D', 'manual') returning id::text as pd \gset
insert into public.product (sku, name, source) values ('WSC-E', 'WSC E', 'manual') returning id::text as pe \gset
insert into public.product (sku, name, source) values ('WSC-N', 'WSC plain', 'manual') returning id::text as pn \gset
-- SO-00000wscx: 1 콤보 WSC-COMBO(2 · 3 · 4 구성품) · 5 보통 · 6 콤보 WSC-COMBO2(7 · 8 구성품)
insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at)
  values ('SO-00000wscx', :'cust'::uuid, 'warehouse', 'manual', 'at_wms', :'cad'::uuid, :'wh1'::uuid, :'wh1name', now()) returning id::text as so1 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (:'so1'::uuid, 1, :'pc1'::uuid, 'WSC-COMBO', 1, 1) returning id::text as k1 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, combo_line_id, combo_qty) values (:'so1'::uuid, 2, :'pa'::uuid, 'WSC-A', 1, 2, :'k1'::uuid, 2), (:'so1'::uuid, 3, :'pb'::uuid, 'WSC-B', 1, 3, :'k1'::uuid, 3), (:'so1'::uuid, 4, :'pcc'::uuid, 'WSC-C', 1, 1, :'k1'::uuid, 1);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (:'so1'::uuid, 5, :'pn'::uuid, 'WSC-N', 1, 5);
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (:'so1'::uuid, 6, :'pc2'::uuid, 'WSC-COMBO2', 1, 2) returning id::text as k2 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, combo_line_id, combo_qty) values (:'so1'::uuid, 7, :'pd'::uuid, 'WSC-D', 1, 2, :'k2'::uuid, 1), (:'so1'::uuid, 8, :'pe'::uuid, 'WSC-E', 1, 4, :'k2'::uuid, 2);
-- SO-00000wscy: 콤보 없음(보통 셋)
insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at)
  values ('SO-00000wscy', :'cust'::uuid, 'warehouse', 'manual', 'at_wms', :'cad'::uuid, :'wh1'::uuid, :'wh1name', now()) returning id::text as so2 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (:'so2'::uuid, 1, :'pn'::uuid, 'WSC-N', 1, 3), (:'so2'::uuid, 2, :'pa'::uuid, 'WSC-A', 1, 1), (:'so2'::uuid, 3, :'pb'::uuid, 'WSC-B', 1, 2);
-- WSC-T1(트랜스퍼): 1 콤보 WSC-COMBO(2 · 3 구성품) · 4 보통
insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, confirmed_at) values ('WSC-T1', 'at_wms', :'wh1'::uuid, :'wh2'::uuid, now()) returning id::text as tf1 \gset
insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (:'tf1'::uuid, 1, :'pc1'::uuid, 'WSC-COMBO', 1, 1) returning id::text as tk1 \gset
insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor, combo_line_id, combo_qty) values (:'tf1'::uuid, 2, :'pa'::uuid, 'WSC-A', 2, 1, :'tk1'::uuid, 2), (:'tf1'::uuid, 3, :'pb'::uuid, 'WSC-B', 3, 1, :'tk1'::uuid, 3);
insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (:'tf1'::uuid, 4, :'pn'::uuid, 'WSC-N', 4, 1);
set local session_replication_role = origin;
select set_config('request.jwt.claims', json_build_object('sub', :'u_mgr', 'role', 'authenticated')::text, true) \gset

-- ── R 옛 창구(시험 갈래만): 같은 입력 · 서명을 psql 변수에 담고 되감는다(임시 표는 savepoint 되감기에 같이 사라진다) ──
\if :{?mig}
savepoint s_old;
select pg_temp.bc(:'so1'::uuid, pg_temp.bt(:'so1'::uuid, '[["2","3","5"],["4","7","8"]]')) as o_r1 \gset
rollback to savepoint s_old;
select pg_temp.bc(:'so1'::uuid, pg_temp.bt(:'so1'::uuid, '[["2","3","4"],["5","7","8"]]')) as r_so1 \gset
select :'r_so1' || ' | ' || pg_temp.sig(:'so1'::uuid) as o_so1 \gset
select pg_temp.bc(:'so2'::uuid, pg_temp.bt(:'so2'::uuid, '[["1","2"],["3"]]')) as r_so2 \gset
select :'r_so2' || ' | ' || pg_temp.sig(:'so2'::uuid) as o_so2 \gset
select pg_temp.bc(:'tf1'::uuid, pg_temp.bt(:'tf1'::uuid, '[["2","3"],["4"]]')) as r_tf1 \gset
select :'r_tf1' || ' | ' || pg_temp.sig(:'tf1'::uuid) as o_tf1 \gset
rollback to savepoint s_old;
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
select pg_temp.chk('R1 old wms_batch_create ACCEPTS a split combo (defect reproduced): SO-00000wscx [[2,3,5],[4,7,8]] → OK picking', :'o_r1', 'OK picking');
\endif
select set_config('request.jwt.claims', json_build_object('sub', :'u_mgr', 'role', 'authenticated')::text, true) \gset

-- ── S 판매 ──
select pg_temp.chk('S1 split combo rejected: [[2,3,5],[4,7,8]] → WSC-COMBO in splits 1 and 2',
  pg_temp.bc(:'so1'::uuid, pg_temp.bt(:'so1'::uuid, '[["2","3","5"],["4","7","8"]]')),
  'ERR WSC-COMBO on SO-00000wscx must stay in one split — its items are in splits 1 and 2 — nothing was saved');
select pg_temp.chk('S2 three splits + two combos: [[2],[3,7],[4,8,5]] → both named, line order, 「1, 2 and 3」',
  pg_temp.bc(:'so1'::uuid, pg_temp.bt(:'so1'::uuid, '[["2"],["3","7"],["4","8","5"]]')),
  'ERR WSC-COMBO on SO-00000wscx must stay in one split — its items are in splits 1, 2 and 3; WSC-COMBO2 on SO-00000wscx must stay in one split — its items are in splits 2 and 3 — nothing was saved');
select pg_temp.chk('S3 only the second combo split: [[2,3,4,7],[5,8]] → WSC-COMBO2 only',
  pg_temp.bc(:'so1'::uuid, pg_temp.bt(:'so1'::uuid, '[["2","3","4","7"],["5","8"]]')),
  'ERR WSC-COMBO2 on SO-00000wscx must stay in one split — its items are in splits 1 and 2 — nothing was saved');
select pg_temp.chk('S4 after rejects nothing saved: status at_wms · tasks 0', pg_temp.sig(:'so1'::uuid), 'at_wms | (no tasks)');
select pg_temp.chk('S5 old checks still first: line in two batches [[2,3,4],[4,5,7,8]] → old message (not combo)',
  pg_temp.bc(:'so1'::uuid, pg_temp.bt(:'so1'::uuid, '[["2","3","4"],["4","5","7","8"]]')),
  'ERR Order SO-00000wscx — lines in more than one batch (4) — nothing was saved');
savepoint s_new;
select pg_temp.bc(:'so1'::uuid, pg_temp.bt(:'so1'::uuid, '[["2","3","4","5","7","8"]]')) as s6 \gset
rollback to savepoint s_new;
select pg_temp.chk('S6 whole order in one big split (판정 973 — the RPC has no size limit): [[2,3,4,5,7,8]] → OK picking', :'s6', 'OK picking');
select pg_temp.bc(:'so1'::uuid, pg_temp.bt(:'so1'::uuid, '[["2","3","4"],["5","7","8"]]')) as n_so1 \gset
select pg_temp.chk('S7 together passes: [[2,3,4],[5,7,8]] → picking · each combo in one task',
  :'n_so1' || ' | ' || pg_temp.sig(:'so1'::uuid),
  'OK picking | picking | SO-00000wscx-1:WSC-A×2,WSC-B×3,WSC-C×1:bins 0 ; SO-00000wscx-2:WSC-N×5,WSC-D×2,WSC-E×4:bins 0');
\if :{?mig}
select pg_temp.chk('C1 SO with combos (together): new = old (status · labels · lines · plan bins)', :'n_so1' || ' | ' || pg_temp.sig(:'so1'::uuid), :'o_so1');
\endif

-- ── N 콤보 없는 오더 ──
select pg_temp.bc(:'so2'::uuid, pg_temp.bt(:'so2'::uuid, '[["1","2"],["3"]]')) as n_so2 \gset
select pg_temp.chk('N1 no-combo order split in two → picking', :'n_so2' || ' | ' || pg_temp.sig(:'so2'::uuid),
  'OK picking | picking | SO-00000wscy-1:WSC-N×3,WSC-A×1:bins 0 ; SO-00000wscy-2:WSC-B×2:bins 0');
\if :{?mig}
select pg_temp.chk('C2 no-combo order: new = old', :'n_so2' || ' | ' || pg_temp.sig(:'so2'::uuid), :'o_so2');
\endif

-- ── T 트랜스퍼 ──
select pg_temp.chk('T1 transfer split combo rejected: [[2,4],[3]]',
  pg_temp.bc(:'tf1'::uuid, pg_temp.bt(:'tf1'::uuid, '[["2","4"],["3"]]')),
  'ERR WSC-COMBO on WSC-T1 must stay in one split — its items are in splits 1 and 2 — nothing was saved');
select pg_temp.chk('T2 after reject nothing saved', pg_temp.sig(:'tf1'::uuid), 'at_wms | (no tasks)');
select pg_temp.bc(:'tf1'::uuid, pg_temp.bt(:'tf1'::uuid, '[["2","3"],["4"]]')) as n_tf1 \gset
select pg_temp.chk('T3 transfer together passes: [[2,3],[4]] → picking', :'n_tf1' || ' | ' || pg_temp.sig(:'tf1'::uuid),
  'OK picking | picking | WSC-T1-1:WSC-A×2,WSC-B×3:bins 0 ; WSC-T1-2:WSC-N×4:bins 0');
\if :{?mig}
select pg_temp.chk('C3 transfer: new = old', :'n_tf1' || ' | ' || pg_temp.sig(:'tf1'::uuid), :'o_tf1');
\endif

-- ── E 꼴 ──
select pg_temp.chk('E1 body = original 84efda39 + only lines tagged wms-split-combo-1',
  (select md5(regexp_replace(prosrc, '[^\n]*wms-split-combo-1[^\n]*\n', '', 'g')) from pg_proc where oid = 'public.wms_batch_create(uuid, jsonb)'::regprocedure), '84efda39742fb62c104c6b4db62aa855');
select pg_temp.chk('E2 added lines = 13', (select count(*)::text from regexp_matches((select prosrc from pg_proc where oid = 'public.wms_batch_create(uuid, jsonb)'::regprocedure), 'wms-split-combo-1', 'g')), '13');
select pg_temp.chk('E3 attributes unchanged (acl · definer · volatile · search_path · owner)',
  (select coalesce(p.proacl::text, '-') || '/' || p.prosecdef || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') || '/' || pg_get_userbyid(p.proowner) from pg_proc p where p.oid = 'public.wms_batch_create(uuid, jsonb)'::regprocedure), :'attr_0');
select pg_temp.chk('E4 comment carries 판정 972', (select (obj_description('public.wms_batch_create(uuid, jsonb)'::regprocedure, 'pg_proc') like '%wms-split-combo-1(판정 972)%')::text), 'true');
select pg_temp.chk('E5 untouched md5 (wave · task_build · pick_plan · pick_lines · doc_status)',
  (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('wms_wave_create', 'wms_pick_task_build', 'so_pick_plan', 'wms_pick_lines', 'wms_doc_status')), :'un_md5_0');

select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' | want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
select (select count(*) from public.so) = :n_so0 and (select count(*) from public.so_line) = :n_line0 and (select count(*) from public.inv_transfer) = :n_tf0 and (select count(*) from public.inv_transfer_line) = :n_tfl0
   and (select count(*) from public.wms_pick_tasks) = :n_pt0 and (select count(*) from public.wms_pick_task_lines) = :n_ptl0 and (select count(*) from public.wms_pick_line_bins) = :n_plb0
   and (select count(*) from public.product) = :n_prod0 and (select count(*) from public.ims_staff) = :n_staff0 and (select count(*) from public.customer) = :n_cust0 as rows_unchanged_after_rollback \gset
\echo '── Z 실제 행 무변:' :rows_unchanged_after_rollback
select case when :n_bad = 0 and :n_ok = :EXPECT_OK and :'rows_unchanged_after_rollback' = 't' then 'PASS' else 'FAIL' end as verdict;
