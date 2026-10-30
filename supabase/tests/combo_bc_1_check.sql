-- supabase/tests/combo_bc_1_check.sql — combo-bc-1 창고 읽기 창구가 구성품 줄에 「그 콤보의 바코드」 를 싣는다 (2026-10-30 · 판정 887)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5 · CHECK 정의) → begin → 옛 prosrc 담기 → (-v mig 면 \i) → 가짜 재료 CBC-*
--   → T1 구성품 둘 콤보(바코드 둘 · 하나 꺼짐) · 보통 줄 · T2 콤보 바코드 0 · T3 트랜스퍼 갈래 · T4 SO-25264 실물 읽기만 · T4b 팩 갈래 · T5 verification_method scanned_combo
--   → T6 권한 · C(옛 창구와 대조 — combo_barcodes 를 뺀 나머지 바이트 같음 · 시험 갈래만) · D(nowhere 정적) · E(속성 · md5 · CHECK · comment · 무접촉) · P(\timing) → rollback → Z1 실제 행 무변 · Z2 md5 · CHECK 복귀(시험 갈래만)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261030160000_combo_bc_1_pick_lines_combo_barcodes.sql -f supabase/tests/combo_bc_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 21 · 확인(적용 뒤) 20 — C1(옛 = 새 대조)은 시험 갈래만 · Z1 · Z2 는 t_res 밖 한 줄씩
--   실제 값(2026-10-30 · 테스트 DB): 5 회차(1 착지 확인 "char" 캐스트 · 2 도우미 cb 의 jsonb 리터럴 · 3 so_number_ck 접미는 글자만 · 4 OK 21/21 · begin~rollback 7.53 s · 5 P 를 한 번씩으로 줄인 판)
--   적용 전 마른 실행(-v mig 없음)은 옛 창구라 T · E 가 MISMATCH(정상)
--   쓰기 0 — 가짜 재료는 rollback · 번호 시퀀스를 당기는 창구(so_create)는 부르지 않는다(so_number 글자 그대로 SO-00000cbcz · 트랜스퍼 CBC-T1) · SO-25264 는 읽기만
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback 을 찍는다) · CHECK 넓히기는 두 표에 ACCESS EXCLUSIVE 잠깐(lock_timeout 3s)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 21
\else
\set EXPECT_OK 20
\endif
\pset pager off
select (select count(*) from public.product) as n_prod0, (select count(*) from public.product_barcode) as n_bc0, (select count(*) from public.product_bom) as n_bom0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_line) as n_line0, (select count(*) from public.inv_transfer) as n_tf0,
       (select count(*) from public.wms_pick_tasks) as n_pt0, (select count(*) from public.wms_pick_task_lines) as n_ptl0, (select count(*) from public.wms_pack_tasks) as n_pk0, (select count(*) from public.wms_pack_task_lines) as n_pkl0,
       (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_lines') as pl_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_line_save') as save_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_complete_pick') as cpk_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_complete_pack') as cpa_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_hold_pick') as hold_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_rollback') as rb_md5_0,
       (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.wms_pick_task_lines'::regclass and conname = 'wms_pick_task_lines_verification_method_check') as pick_ck_0,
       (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.wms_pack_task_lines'::regclass and conname = 'wms_pack_task_lines_verification_method_check') as pack_ck_0,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1, (select name from public.ref_warehouse where name = 'Asung Trading Inc.') as wh1name,
       (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as wh2,
       (select id::text from public.ref_currency where code = 'CAD') as cad,
       (select t.id from public.wms_pick_tasks t join public.so s on s.id = t.order_id where s.so_number = 'SO-25264' order by t.id limit 1) as real_task,
       (select t.id from public.wms_pick_tasks t join public.wms_pick_task_lines l on l.pick_task_id = t.id where t.order_id is not null and t.id <> 1237
          and not exists (select 1 from public.so_line x where x.id = l.order_line_id and x.combo_line_id is not null) group by t.id having count(*) >= 5 order by t.id desc limit 1) as plain_task \gset
\echo '── 기준: product' :n_prod0 '· barcode' :n_bc0 '· so_line' :n_line0 '· pick_lines' :n_ptl0 '· pack_lines' :n_pkl0 '· wms_pick_lines md5' :pl_md5_0 '· SO-25264 과제' :real_task '· 콤보 없는 과제' :plain_task
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
create temp table t_pre as select proname, prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_lines');
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
grant insert on t_res to authenticated; grant usage on sequence t_res_n_seq to authenticated;
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 줄 목록 → 「sku=combo_barcodes」 를 line_no 순으로 한 줄에
create function pg_temp.cb(p jsonb) returns text language sql as $$
  select coalesce(string_agg(e->>'sku' || '=' || coalesce((e->'combo_barcodes')::text, 'MISSING'), ' ' order by e->>'sku'), '(empty)') from jsonb_array_elements(p) e
$$;
create function pg_temp.one_batch(p_doc uuid) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('line_ids', jsonb_agg(l.line_id order by l.line_no))) from public.wms_order_doc_line l where l.doc_id = p_doc and l.qty_target > 0
$$;

-- ── M 재료(replica · 트리거 · FK 검사 없이 · 전부 rollback): 직원 둘 · 손님 · 제품 여섯 · BOM · 바코드 · 오더 · 트랜스퍼 ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'cbc1-wh@test.invalid', 'CBC1 warehouse', 'manager', '["ims","wms","picking","packing","wms_manage"]', '{}') returning auth_user_id::text as u_wh \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'cbc1-no@test.invalid', 'CBC1 no warehouse', 'worker', '["ims"]', array[:'wh2'::uuid]) returning auth_user_id::text as u_no \gset
insert into public.customer (name, source, currency_id) values ('CBC1 Customer', 'manual', :'cad'::uuid) returning id::text as cust \gset
insert into public.product (sku, name, source) values ('CBC1-COMBO', 'CBC1 combo (sealed box)', 'manual') returning id::text as p_combo \gset
insert into public.product (sku, name, source) values ('CBC1-COMBO0', 'CBC1 combo without barcode', 'manual') returning id::text as p_combo0 \gset
insert into public.product (sku, name, source) values ('CBC1-A', 'CBC1 component A', 'manual') returning id::text as p_a \gset
insert into public.product (sku, name, source) values ('CBC1-B', 'CBC1 component B', 'manual') returning id::text as p_b \gset
insert into public.product (sku, name, source) values ('CBC1-C', 'CBC1 component C', 'manual') returning id::text as p_c \gset
insert into public.product (sku, name, source) values ('CBC1-N', 'CBC1 plain line', 'manual') returning id::text as p_n \gset
insert into public.product_bom (parent_product_id, component_product_id, quantity, source) values (:'p_combo'::uuid, :'p_a'::uuid, 2, 'manual'), (:'p_combo'::uuid, :'p_b'::uuid, 3, 'manual'), (:'p_combo0'::uuid, :'p_c'::uuid, 1, 'manual');
insert into public.product_barcode (product_id, barcode, is_primary, is_active, source) values
  (:'p_combo'::uuid, 'CBC18870002', false, true,  'manual'),     -- 켜짐 · primary 아님(정렬: primary 먼저 → 0001 이 앞)
  (:'p_combo'::uuid, 'CBC18870001', true,  true,  'manual'),     -- 켜짐 · primary
  (:'p_combo'::uuid, 'CBC18870009', false, false, 'manual'),     -- 꺼짐 → 빠진다
  (:'p_a'::uuid, 'CBC1887000A', true, true, 'manual'), (:'p_b'::uuid, 'CBC1887000B', true, true, 'manual'), (:'p_c'::uuid, 'CBC1887000C', true, true, 'manual'), (:'p_n'::uuid, 'CBC1887000N', true, true, 'manual');
insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at)
  values ('SO-00000cbcz', :'cust'::uuid, 'warehouse', 'manual', 'at_wms', :'cad'::uuid, :'wh1'::uuid, :'wh1name', now()) returning id::text as so1 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (:'so1'::uuid, 1, :'p_combo'::uuid, 'CBC1-COMBO', 1, 1) returning id::text as l_combo \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, combo_line_id, combo_qty) values (:'so1'::uuid, 2, :'p_a'::uuid, 'CBC1-A', 1, 2, :'l_combo'::uuid, 2) returning id::text as l_a \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, combo_line_id, combo_qty) values (:'so1'::uuid, 3, :'p_b'::uuid, 'CBC1-B', 1, 3, :'l_combo'::uuid, 3) returning id::text as l_b \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (:'so1'::uuid, 4, :'p_n'::uuid, 'CBC1-N', 1, 5) returning id::text as l_n \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (:'so1'::uuid, 5, :'p_combo0'::uuid, 'CBC1-COMBO0', 1, 1) returning id::text as l_combo0 \gset
insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, combo_line_id, combo_qty) values (:'so1'::uuid, 6, :'p_c'::uuid, 'CBC1-C', 1, 1, :'l_combo0'::uuid, 1) returning id::text as l_c \gset
insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, confirmed_at) values ('CBC-T1', 'at_wms', :'wh1'::uuid, :'wh2'::uuid, now()) returning id::text as tf1 \gset
insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (:'tf1'::uuid, 1, :'p_n'::uuid, 'CBC1-N', 4, 1);
set local session_replication_role = origin;

-- 창고로: 과제 하나씩(창구 wms_batch_create · 가짜 창고 직원 claims)
select set_config('request.jwt.claims', json_build_object('sub', :'u_wh', 'role', 'authenticated')::text, true) \gset
select pg_temp.run(format('select (public.wms_batch_create(%L::uuid, %L::jsonb)->>''status'')', :'so1', pg_temp.one_batch(:'so1'::uuid))) as so_split,
       pg_temp.run(format('select (public.wms_batch_create(%L::uuid, %L::jsonb)->>''status'')', :'tf1', pg_temp.one_batch(:'tf1'::uuid))) as tf_split \gset
select pg_temp.chk('M1 wms_batch_create: SO-00000cbcz → picking · CBC-T1 → picking', :'so_split' || '/' || :'tf_split', 'picking/picking');
select t.id as task_so from public.wms_pick_tasks t where t.order_id = :'so1'::uuid \gset
select t.id as task_tf from public.wms_pick_tasks t where t.transfer_id = :'tf1'::uuid \gset
select pg_temp.chk('M2 pick lines: SO 4(콤보 줄 둘은 빠진다 · 판정 244) · 트랜스퍼 1',
  (select count(*) from public.wms_pick_task_lines where pick_task_id = :task_so)::text || '/' || (select count(*) from public.wms_pick_task_lines where pick_task_id = :task_tf)::text, '4/1');

-- ── T1 구성품 둘 콤보(바코드 셋 · 하나 꺼짐) · 보통 줄 · T2 콤보 바코드 0 ──
select public.wms_pick_lines(array[:task_so]::bigint[]) as j_so \gset
select pg_temp.chk('T1 구성품 줄 = 콤보의 켜진 바코드 둘(primary 먼저 · 그다음 barcode 순) · 보통 줄 [] · T2 바코드 없는 콤보의 구성품 []',
  pg_temp.cb(:'j_so'::jsonb), 'CBC1-A=["CBC18870001", "CBC18870002"] CBC1-B=["CBC18870001", "CBC18870002"] CBC1-C=[] CBC1-N=[]');
select pg_temp.chk('T1b 모든 줄에 combo_barcodes 가 있고 jsonb 배열이다 · 줄 수 4',
  (select string_agg(jsonb_typeof(e->'combo_barcodes'), ',') || '/' || count(*)::text from jsonb_array_elements(:'j_so'::jsonb) e), 'array,array,array,array/4');
select pg_temp.chk('T1c 구성품 줄의 r.barcodes 는 그대로 낱개 하나(콤보 바코드가 섞이지 않는다) · combo_sku 그대로',
  (select e->'barcodes'->0->>'barcode' || '/' || jsonb_array_length(e->'barcodes')::text || '/' || (e->>'combo_sku') from jsonb_array_elements(:'j_so'::jsonb) e where e->>'sku' = 'CBC1-A'), 'CBC1887000A/1/CBC1-COMBO');

-- ── T3 트랜스퍼 갈래 ──
select pg_temp.chk('T3 트랜스퍼 갈래 줄 combo_barcodes = []', pg_temp.cb(public.wms_pick_lines(array[:task_tf]::bigint[])), 'CBC1-N=[]');
select pg_temp.chk('T3b 두 과제 한 번에(배열) — 줄 5 · 트랜스퍼 줄도 배열',
  (select count(*)::text || '/' || count(*) filter (where jsonb_typeof(e->'combo_barcodes') = 'array')::text from jsonb_array_elements(public.wms_pick_lines(array[:task_so, :task_tf]::bigint[])) e), '5/5');

-- ── T4 SO-25264 실물 — 읽기만(그 오더의 pick_task_id) ──
select pg_temp.chk('T4 SO-25264(실물 · 읽기만): 구성품 넷 줄마다 ["810162182595"] · 콤보 줄 UNF18259 없음',
  pg_temp.cb(public.wms_pick_lines(array[:real_task]::bigint[])), 'UNF18046=["810162182595"] UNF18047=["810162182595"] UNF18048=["810162182595"] UNF18049=["810162182595"]');

\echo '── 화면이 쓸 꼴(SO-25264 · UNF18046 줄 · 압축 jsonb 한 줄):'
select e::text from jsonb_array_elements(public.wms_pick_lines(array[:real_task]::bigint[])) e where e->>'sku' = 'UNF18046';

-- ── T4b 팩 갈래(가짜 팩 과제 · replica) ──
set local session_replication_role = replica;
insert into public.wms_pack_tasks (order_id, pick_task_id, batch_label, status) values (:'so1'::uuid, :task_so, 'SO-00000cbcz-1', 'pending') returning id as pack_so \gset
insert into public.wms_pack_task_lines (pack_task_id, order_line_id, expected_base) select :pack_so, l.order_line_id, l.assigned_base from public.wms_pick_task_lines l where l.pick_task_id = :task_so;
set local session_replication_role = origin;
select public.wms_pick_lines(null, :pack_so) as j_pk \gset
select pg_temp.chk('T4b 팩 갈래(p_pack_task_id): 구성품 줄에도 콤보 바코드 · pack_line_id 있음',
  pg_temp.cb(:'j_pk'::jsonb) || ' / ' || (select count(*) filter (where (e->'pack_line_id') is not null)::text from jsonb_array_elements(:'j_pk'::jsonb) e),
  'CBC1-A=["CBC18870001", "CBC18870002"] CBC1-B=["CBC18870001", "CBC18870002"] CBC1-C=[] CBC1-N=[] / 4');

-- ── T5 verification_method: scanned_combo 저장(창구) · 옛 값 셋 그대로 · 엉뚱한 값은 CHECK 이름으로 거부 ──
set local session_replication_role = replica;
update public.wms_pick_tasks set status = 'in_progress', assigned_to = (select id from public.ims_staff where auth_user_id = :'u_wh'::uuid), session_id = 'cbc1-sess', work_started = true, started_at = now() where id = :task_so;
set local session_replication_role = origin;
select l.id as line_a from public.wms_pick_task_lines l where l.pick_task_id = :task_so and l.order_line_id = :'l_a'::uuid \gset
set local role authenticated;
select pg_temp.run(format('select (public.wms_pick_line_save(%s, 0, null, null, ''scanned_combo'', ''cbc1-sess''))->>''saved''', :line_a)) as s_combo \gset
reset role;
select pg_temp.chk('T5a 창구 wms_pick_line_save: scanned_combo 저장 = saved true · 줄에 scanned_combo',
  :'s_combo' || '/' || (select coalesce(verification_method, '(null)') from public.wms_pick_task_lines where id = :line_a), 'true/scanned_combo');
select pg_temp.chk('T5b 옛 값 셋 그대로 저장(픽 줄 · 팩 줄)',
  pg_temp.run(format('update public.wms_pick_task_lines set verification_method = ''scanned_variant'' where id = %s returning verification_method', :line_a)) || '/' ||
  pg_temp.run(format('update public.wms_pick_task_lines set verification_method = ''scanned_base'' where id = %s returning verification_method', :line_a)) || '/' ||
  pg_temp.run(format('update public.wms_pick_task_lines set verification_method = ''manual'' where id = %s returning verification_method', :line_a)) || '/' ||
  pg_temp.run(format('update public.wms_pack_task_lines set verification_method = ''scanned_combo'' where pack_task_id = %s and order_line_id = %L returning verification_method', :pack_so, :'l_a')) || '/' ||
  pg_temp.run(format('update public.wms_pack_task_lines set verification_method = ''manual'' where pack_task_id = %s and order_line_id = %L returning verification_method', :pack_so, :'l_a')),
  'scanned_variant/scanned_base/manual/scanned_combo/manual');
select pg_temp.chk('T5c 엉뚱한 값 scanned_box 는 CHECK 이름으로 거부(픽 · 팩)',
  pg_temp.run(format('update public.wms_pick_task_lines set verification_method = ''scanned_box'' where id = %s returning verification_method', :line_a)) || ' | ' ||
  pg_temp.run(format('update public.wms_pack_task_lines set verification_method = ''scanned_box'' where pack_task_id = %s and order_line_id = %L returning verification_method', :pack_so, :'l_a')),
  'ERR 23514: new row for relation "wms_pick_task_lines" violates check constraint "wms_pick_task_lines_verification_method_check" | ERR 23514: new row for relation "wms_pack_task_lines" violates check constraint "wms_pack_task_lines_verification_method_check"');

-- ── T6 권한(가짜 직원 · set role authenticated + claims) ──
set local role authenticated;
select pg_temp.run(format('select jsonb_array_length(public.wms_pick_lines(array[%s]::bigint[]))::text', :task_so)) as r_wh \gset
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'u_no', 'role', 'authenticated')::text, true) \gset
set local role authenticated;
select pg_temp.run(format('select jsonb_array_length(public.wms_pick_lines(array[%s]::bigint[]))::text', :task_so)) as r_no \gset
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true) \gset
set local role anon;
select pg_temp.run(format('select jsonb_array_length(public.wms_pick_lines(array[%s]::bigint[]))::text', :task_so)) as r_anon \gset
reset role;
select set_config('request.jwt.claims', json_build_object('sub', :'u_wh', 'role', 'authenticated')::text, true) \gset
select pg_temp.chk('T6 권한: 창고 직원 4 줄 · 창고 권한 없는 직원(worker · ims 만 · 다른 창고)도 4 줄 — 읽기 창구는 창고 검사 없음(comment 그대로 · 쓰기 창구가 지킨다) · anon 은 execute 거부',
  :'r_wh' || '/' || :'r_no' || '/' || :'r_anon', '4/4/ERR 42501: permission denied for function wms_pick_lines');

-- ── C 옛 창구와 대조(시험 갈래만): 옛 prosrc 를 pg_temp 함수로 되살려 같은 과제를 읽고 · 새 줄에서 combo_barcodes 만 빼면 바이트 같음 ──
\if :{?mig}
select format('create function pg_temp.old_pick_lines(p_task_ids bigint[] default null, p_pack_task_id bigint default null) returns jsonb language plpgsql stable set search_path = public, pg_temp as %L', prosrc) as mk_old from t_pre where proname = 'wms_pick_lines' \gset
:mk_old ;
select pg_temp.chk('C1 옛 창구 = 새 창구 − combo_barcodes (가짜 SO · 트랜스퍼 · 팩 갈래 · SO-25264 · 콤보 없는 실제 과제 — 기존 칸 · 값 바이트 그대로)',
  ((select jsonb_agg(e - 'combo_barcodes') from jsonb_array_elements(public.wms_pick_lines(array[:task_so, :task_tf]::bigint[])) e) = pg_temp.old_pick_lines(array[:task_so, :task_tf]::bigint[]))::text || '/' ||
  ((select jsonb_agg(e - 'combo_barcodes') from jsonb_array_elements(public.wms_pick_lines(null, :pack_so)) e) = pg_temp.old_pick_lines(null, :pack_so))::text || '/' ||
  ((select jsonb_agg(e - 'combo_barcodes') from jsonb_array_elements(public.wms_pick_lines(array[:real_task]::bigint[])) e) = pg_temp.old_pick_lines(array[:real_task]::bigint[]))::text || '/' ||
  ((select jsonb_agg(e - 'combo_barcodes') from jsonb_array_elements(public.wms_pick_lines(array[:plain_task]::bigint[])) e) = pg_temp.old_pick_lines(array[:plain_task]::bigint[]))::text || '/' ||
  (select count(*) filter (where e ? 'combo_barcodes')::text || '=' || count(*)::text from jsonb_array_elements(public.wms_pick_lines(array[:plain_task]::bigint[])) e),
  'true/true/true/true/5=5');
\endif

-- ── D nowhere 정적: 재발행 함수의 WHERE 없는 update · delete 0(읽기 창구 · 옛 판도 0) ──
select pg_temp.chk('D1 nowhere: wms_pick_lines 지금 판 0 · begin 앞 판 0',
  (select pg_temp.nowhere(prosrc)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_lines') || '/' || (select pg_temp.nowhere(prosrc)::text from t_pre where proname = 'wms_pick_lines'), '0/0');

-- ── E 속성 · 권한 · CHECK · comment · 무접촉 ──
select pg_temp.chk('E1 wms_pick_lines: invoker · stable · search_path · acl postgres + authenticated + service_role · 하나 · 본문에 cbc 셋',
  (select prosecdef::text || '/' || provolatile::text || '/' || array_to_string(proconfig, ';') || '/' || coalesce(proacl::text, '-') || '/' ||
          (prosrc ~ '\), cbc as \(' and prosrc ~ $r$jsonb_build_object\('combo_barcodes', coalesce\(cbc\.arr, '\[\]'::jsonb\)\)$r$ and prosrc ~ 'left join cbc  on cbc\.combo_line_id = pl\.combo_line_id')::text
     from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_lines')
  || '/' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_lines'),
  'false/s/search_path=public, pg_temp/{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}/true/1');
select pg_temp.chk('E2 CHECK 둘(public): scanned_combo 포함 · 이름 그대로 · wms_legacy 둘은 옛 정의 그대로',
  (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.wms_pick_task_lines'::regclass and conname = 'wms_pick_task_lines_verification_method_check') || ' | ' ||
  (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.wms_pack_task_lines'::regclass and conname = 'wms_pack_task_lines_verification_method_check') || ' | ' ||
  (select count(*)::text from pg_constraint where connamespace = 'wms_legacy'::regnamespace and conname like '%verification_method_check' and pg_get_constraintdef(oid) !~ 'scanned_combo'),
  $c$CHECK ((verification_method = ANY (ARRAY['scanned_variant'::text, 'scanned_base'::text, 'manual'::text, 'scanned_combo'::text]))) | CHECK ((verification_method = ANY (ARRAY['scanned_variant'::text, 'scanned_base'::text, 'manual'::text, 'scanned_combo'::text]))) | 2$c$);
select pg_temp.chk('E3 함수 본문에 verification_method 값 목록 없음: scanned_variant 를 품은 public 함수 0 · 읽는 함수 8 그대로',
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ 'scanned_variant') || '/' ||
  (select string_agg(proname, ',' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and prosrc ~ 'verification_method'),
  '0/wms_complete_pack,wms_complete_pick,wms_hold_pack,wms_hold_pick,wms_pick_line_save,wms_pick_lines,wms_rollback,wms_rollback_batch');
select pg_temp.chk('E4 comment: 옛 글 그대로 앞에 + 판정 887 · combo_barcodes · scanned_combo',
  (select (c like '⑤-4b 읽기 창구 — 픽 줄(과제 여럿 · 웨이브 멤버 전부)%사진 칸 없음(판정 33). ⊕ combo_barcodes(combo-bc-1 판정 887%scanned_combo).')::text from (select obj_description('public.wms_pick_lines(bigint[], bigint)'::regprocedure, 'pg_proc') c) x), 'true');
select pg_temp.chk('E5 untouched (md5 begin 앞 = 지금): wms_pick_line_save · wms_complete_pick · wms_complete_pack · wms_hold_pick · wms_rollback',
  (select string_agg((md5(prosrc) = case proname when 'wms_pick_line_save' then :'save_md5_0' when 'wms_complete_pick' then :'cpk_md5_0' when 'wms_complete_pack' then :'cpa_md5_0'
                                              when 'wms_hold_pick' then :'hold_md5_0' else :'rb_md5_0' end)::text, '/' order by proname)
     from pg_proc where pronamespace = 'public'::regnamespace and proname in ('wms_pick_line_save', 'wms_complete_pick', 'wms_complete_pack', 'wms_hold_pick', 'wms_rollback')),
  'true/true/true/true/true');
select pg_temp.chk('E6 DB 사실(보고용): 콤보 바코드 = 자기 구성품 바코드인 쌍 0 · 바코드 가진 콤보 부모 수',
  (select count(*)::text from public.product_bom m join public.product_barcode pb on pb.product_id = m.parent_product_id and pb.is_active
     join public.product_barcode cb on cb.product_id = m.component_product_id and cb.is_active and cb.barcode = pb.barcode where m.is_active and pb.barcode not like 'CBC1%') || '/' ||
  (select count(distinct b.product_id)::text from public.product_barcode b where b.is_active and b.barcode not like 'CBC1%' and exists (select 1 from public.product_bom m where m.parent_product_id = b.product_id and m.is_active)),
  '0/35');

-- ── P 성능(\timing · 콤보 없는 실제 과제 · SO-25264 과제 · 한 번씩 — 잠금 시간을 아낀다 · 적용 전 기준은 보고에) ──
\echo '── P 성능: 콤보 없는 과제' :plain_task '· SO-25264 과제' :real_task
\timing on
select length(public.wms_pick_lines(array[:plain_task]::bigint[])::text) as plain_len;
select length(public.wms_pick_lines(array[:real_task]::bigint[])::text) as so25264_len;
\timing off

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
select case when (select count(*) from public.product) = :n_prod0 and (select count(*) from public.product_barcode) = :n_bc0 and (select count(*) from public.product_bom) = :n_bom0
            and (select count(*) from public.so) = :n_so0 and (select count(*) from public.so_line) = :n_line0 and (select count(*) from public.inv_transfer) = :n_tf0
            and (select count(*) from public.wms_pick_tasks) = :n_pt0 and (select count(*) from public.wms_pick_task_lines) = :n_ptl0
            and (select count(*) from public.wms_pack_tasks) = :n_pk0 and (select count(*) from public.wms_pack_task_lines) = :n_pkl0
            and (select count(*) from public.ims_staff) = :n_staff0 and (select count(*) from public.customer) = :n_cust0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'wms_pick_lines') = :'pl_md5_0'
             and (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.wms_pick_task_lines'::regclass and conname = 'wms_pick_task_lines_verification_method_check') = :'pick_ck_0'
             and (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.wms_pack_task_lines'::regclass and conname = 'wms_pack_task_lines_verification_method_check') = :'pack_ck_0'
             and (select obj_description('public.wms_pick_lines(bigint[], bigint)'::regprocedure, 'pg_proc')) not like '%판정 887%'
       then 'Z2 OK function + two CHECKs + comment back to before' else 'Z2 MISMATCH not restored' end as z2;
\endif
