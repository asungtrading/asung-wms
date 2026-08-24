-- wms_hold_pack 로컬 기능 테스트 (2026-08-07 · Hold RPC — 픽 Hold 테스트의 팩 판)
--
-- 실행 (로컬 supabase — 프로덕션 금지):
--   supabase db reset
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/wms_hold_pack_test.sql
--
-- 전체가 한 트랜잭션 + 마지막 ROLLBACK — 로컬 DB 에 무흔적.
-- 전부 통과하면 마지막 NOTICE 가 "ALL 9 TESTS PASSED".
-- (ⓗⓘ 2026-08-24 추가 — wms_task_holds 이력: 성공 Hold 1행 · 멱등/예외 무기록.
--  마이그레이션 20260824192416)

begin;

do $test$
declare
  o1 bigint; o2 bigint;
  p1 bigint; p2 bigint; p3 bigint; p4 bigint;
  k1 bigint; k2 bigint; k3 bigint; k4 bigint;
  la bigint; lb bigint; lc bigint; le bigint;   -- order lines
  pla bigint; plb bigint; plc bigint; ple bigint;  -- pack lines
  res jsonb;
  n int; t text;
  ts0 timestamptz;
  errmsg text;
begin
  -- ── 셋업: 직원 · 로그인 흉내 ─────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);
  insert into wms_staff (name, email, role, warehouse_access, active)
  values ('RPC Tester', 'rpc-test@asung.ca', 'worker', 'both', true),
         ('Renamed Worker', 'rpc-drift@asung.ca', 'worker', 'both', true);

  -- ── 셋업: 라인 3개가 상태 3갈래(verified/in_progress/pending) 커버 ────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-HOLDPK-1', 'SO-TEST-HOLDPK-1', 'packing') returning id into o1;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o1, 'SO-TEST-HOLDPK-1-1', 'Picker Kim', 'completed') returning id into p1;
  insert into wms_pack_tasks (order_id, pick_task_id, batch_label, assigned_to, status, started_at, work_started)
  values (o1, p1, 'SO-TEST-HOLDPK-1-1', 'RPC Tester', 'in_progress', now() - interval '10 min', true)
  returning id, started_at into k1, ts0;

  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-A','SKU-A',1,10,10) returning id into la;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-B','SKU-B',1,6,6) returning id into lb;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-C','SKU-C',1,8,8) returning id into lc;

  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,la,10) returning id into pla;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,lb,6)  returning id into plb;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,lc,8)  returning id into plc;

  -- ── ⓐ 정상 Hold ──────────────────────────────────────────────────────
  res := wms_hold_pack(
    k1,
    jsonb_build_array(
      jsonb_build_object('id',pla,'verified_base',10,'status','verified',   'verification_method','scanned_base'),
      jsonb_build_object('id',plb,'verified_base',2, 'status','in_progress','verification_method','manual'),
      jsonb_build_object('id',plc,'verified_base',0, 'status','pending',    'verification_method',null)));

  if res->>'held' <> 'true' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL a1: %', res; end if;
  if (res->>'lines_updated')::int <> 3 then raise exception 'FAIL a2: %', res; end if;
  select status||'/'||coalesce(assigned_to,'-')||'/'||held_by into t from wms_pack_tasks where id=k1;
  if t <> 'pending/-/RPC Tester' then raise exception 'FAIL a3: task=%', t; end if;
  -- 진행 흔적 보존 + verified_at 은 Hold 가 찍지 않는다 (완료 전용 — 현행 동일)
  select started_at::text||'/'||work_started::text into t from wms_pack_tasks where id=k1;
  if t <> ts0::text||'/true' then raise exception 'FAIL a4: progress marks changed (%)', t; end if;
  select count(*) into n from wms_pack_task_lines where pack_task_id=k1 and verified_at is not null;
  if n <> 0 then raise exception 'FAIL a5: verified_at set on hold (%)', n; end if;
  select status||'/'||verified_base::text into t from wms_pack_task_lines where id=plb;
  if t <> 'in_progress/2' then raise exception 'FAIL a6: %', t; end if;
  select verification_method into t from wms_pack_task_lines where id=plc;
  if t is not null then raise exception 'FAIL a7: null vmethod not preserved (%)', t; end if;
  raise notice 'PASS a — 정상 Hold (플립·held_by·라인 3갈래·verified_at 무접촉)';

  -- ── ⓑ 재호출 멱등 (이미 pending) ─────────────────────────────────────
  res := wms_hold_pack(
    k1,
    jsonb_build_array(jsonb_build_object('id',plb,'verified_base',99,'status','verified','verification_method','manual')));
  if res->>'held' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL b1: %', res; end if;
  select verified_base::text into t from wms_pack_task_lines where id=plb;
  if t <> '2' then raise exception 'FAIL b2: line written on CAS fail (%)', t; end if;
  raise notice 'PASS b — 재호출 멱등 (무기록)';

  -- ── ⓒ CAS 불일치 (남의 태스크): 무변 ────────────────────────────────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-HOLDPK-2','SO-TEST-HOLDPK-2','packing') returning id into o2;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B2','Picker Kim','completed') returning id into p2;
  insert into wms_pack_tasks (order_id, pick_task_id, batch_label, assigned_to, status)
  values (o2,p2,'B2','Somebody Else','in_progress') returning id into k2;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o2,'SKU-E','SKU-E',1,5,5) returning id into le;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k2,le,5) returning id into ple;

  res := wms_hold_pack(
    k2,
    jsonb_build_array(jsonb_build_object('id',ple,'verified_base',5,'status','verified','verification_method','manual')));
  if res->>'held' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL c1: %', res; end if;
  select status||'/'||assigned_to into t from wms_pack_tasks where id=k2;
  if t <> 'in_progress/Somebody Else' then raise exception 'FAIL c2: %', t; end if;
  select count(*) into n from wms_pack_task_lines where id=ple and verified_base > 0;
  if n <> 0 then raise exception 'FAIL c3: line written on CAS fail'; end if;
  raise notice 'PASS c — CAS 불일치 (무변)';

  -- ── ⓓ 이름 드리프트 ──────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"rpc-drift@asung.ca"}', false);
  -- pick_task_id 는 유니크(uq_packtasks_pick — 픽 배치당 팩 태스크 1개)라 픽 태스크도 새로
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B3','Picker Kim','completed') returning id into p3;
  insert into wms_pack_tasks (order_id, pick_task_id, batch_label, assigned_to, status)
  values (o2,p3,'B3','Old Name','in_progress') returning id into k3;
  res := wms_hold_pack(k3, '[]'::jsonb);
  if res->>'held' <> 'false' or res->>'worker' <> 'Renamed Worker' then raise exception 'FAIL d1: %', res; end if;
  select status into t from wms_pack_tasks where id=k3;
  if t <> 'in_progress' then raise exception 'FAIL d2: %', t; end if;
  raise notice 'PASS d — 이름 드리프트 (worker 로 원인 식별)';
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);

  -- ── ⓔ 라인 수 불일치: 예외 + 플립 포함 전체 롤백 ─────────────────────
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B4','Picker Kim','completed') returning id into p4;
  insert into wms_pack_tasks (order_id, pick_task_id, batch_label, assigned_to, status)
  values (o2,p4,'B4','RPC Tester','in_progress') returning id into k4;
  begin
    res := wms_hold_pack(
      k4,
      jsonb_build_array(jsonb_build_object('id',999999999,'verified_base',1,'status','verified','verification_method','manual')));
    raise exception 'FAIL e1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('removed by a rollback' in errmsg) = 0 or position('Ask a manager' in errmsg) = 0 then
      raise exception 'FAIL e2: %', errmsg;
    end if;
  end;
  select status||'/'||coalesce(held_by,'-') into t from wms_pack_tasks where id=k4;
  if t <> 'in_progress/-' then raise exception 'FAIL e3: flip not rolled back (%)', t; end if;
  raise notice 'PASS e — 라인 수 불일치 (전체 롤백 · 원인 메시지)';

  -- ── ⓕ 타 태스크 라인 오염 차단: 남의 라인 id → 스코프 밖 = 롤백 ──────
  begin
    res := wms_hold_pack(
      k4,
      jsonb_build_array(jsonb_build_object('id',pla,'verified_base',1,'status','verified','verification_method','manual')));
    raise exception 'FAIL f1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('removed by a rollback' in errmsg) = 0 then raise exception 'FAIL f2: %', errmsg; end if;
  end;
  select verified_base::text into t from wms_pack_task_lines where id=pla;
  if t <> '10' then raise exception 'FAIL f3: foreign line written (%)', t; end if;
  select status into t from wms_pack_tasks where id=k4;
  if t <> 'in_progress' then raise exception 'FAIL f4: flip survived (%)', t; end if;
  raise notice 'PASS f — 타 태스크 라인 오염 차단 (스코프 밖 = 전체 롤백)';

  -- ── ⓖ 미등록 이메일 ─────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"nobody@asung.ca"}', false);
  begin
    res := wms_hold_pack(k4, '[]'::jsonb);
    raise exception 'FAIL g1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('No staff record' in errmsg) = 0 then raise exception 'FAIL g2: %', errmsg; end if;
  end;
  raise notice 'PASS g — 미등록 로그인 차단';

  -- ── ⓗ Hold 이력 (2026-08-24 · 마이그레이션 20260824192416) ────────────
  -- ⓐ 의 성공 Hold 가 남긴 행 검증 — kind/task_id/worker/열림/manual
  select count(*) into n from wms_task_holds
   where task_kind='pack' and task_id=k1 and worker='RPC Tester'
     and held_at is not null and resumed_at is null and resumed_by is null and source='manual';
  if n <> 1 then raise exception 'FAIL h1: pack hold history rows=%', n; end if;
  raise notice 'PASS h — Hold 이력 · pack (1행 · 열림 · manual)';

  -- ── ⓘ 멱등·예외·CAS 불일치는 이력을 만들지 않는다 ─────────────────────
  -- 성공 Hold 는 ⓐ 하나뿐 — ⓑ 멱등 · ⓒⓓ CAS/드리프트 · ⓔⓕ 예외 롤백 · ⓖ 미등록 전부 무기록.
  select count(*) into n from wms_task_holds;
  if n <> 1 then raise exception 'FAIL i1: total history rows=% (expected 1)', n; end if;
  raise notice 'PASS i — 멱등·예외·CAS 불일치 무기록 (총 1행)';

  raise notice '════ ALL 9 TESTS PASSED ════';
end
$test$;

rollback;
