-- wms_hold_pick 로컬 기능 테스트 (2026-08-07 · Hold RPC — 완료 테스트 원형 + wave)
--
-- 실행 (로컬 supabase — 프로덕션 금지):
--   supabase db reset
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/wms_hold_pick_test.sql
--
-- 전체가 한 트랜잭션 + 마지막 ROLLBACK — 로컬 DB 에 무흔적.
-- 전부 통과하면 마지막 NOTICE 가 "ALL 11 TESTS PASSED".

begin;

do $test$
declare
  o1 bigint; o2 bigint; o3 bigint;
  t1 bigint; t2 bigint; t3 bigint; t4 bigint; t5 bigint; t6 bigint; t7 bigint;
  w1 bigint; w2 bigint;
  la bigint; lb bigint; lc bigint; le bigint; lf bigint;   -- order lines
  pa bigint; pb bigint; pc bigint; pe bigint; pf bigint;   -- pick lines
  p4 bigint; p5a bigint;
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

  -- ── 셋업: 단일 모드 — 라인 3개가 상태 3갈래(picked/in_progress/pending) 커버 ──
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-HOLD-1', 'SO-TEST-HOLD-1', 'picking') returning id into o1;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, started_at, work_started)
  values (o1, 'SO-TEST-HOLD-1-1', 'RPC Tester', 'in_progress', now() - interval '10 min', true)
  returning id, started_at into t1, ts0;

  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-A','SKU-A',1,10,10) returning id into la;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-B','SKU-B',1,6,6) returning id into lb;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-C','SKU-C',1,8,8) returning id into lc;

  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t1,la,10) returning id into pa;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t1,lb,6)  returning id into pb;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t1,lc,8)  returning id into pc;

  -- ── ⓐ 단일 정상 Hold ─────────────────────────────────────────────────
  res := wms_hold_pick(
    jsonb_build_array(
      jsonb_build_object('id',pa,'picked_base',10,'status','picked',     'verification_method','scanned_base'),
      jsonb_build_object('id',pb,'picked_base',2, 'status','in_progress','verification_method','manual'),
      jsonb_build_object('id',pc,'picked_base',0, 'status','pending',    'verification_method',null)),
    t1, null);

  if res->>'held' <> 'true' or res->>'mode' <> 'single' then raise exception 'FAIL a1: %', res; end if;
  if (res->>'lines_updated')::int <> 3 then raise exception 'FAIL a2: %', res; end if;
  select status||'/'||coalesce(assigned_to,'-')||'/'||held_by into t from wms_pick_tasks where id=t1;
  if t <> 'pending/-/RPC Tester' then raise exception 'FAIL a3: task=%', t; end if;
  -- 진행 흔적 보존: started_at·work_started 는 Hold 가 건드리지 않는다 (현행 동일)
  select started_at::text||'/'||work_started::text into t from wms_pick_tasks where id=t1;
  if t <> ts0::text||'/true' then raise exception 'FAIL a4: progress marks changed (%)', t; end if;
  select status||'/'||picked_base::text into t from wms_pick_task_lines where id=pb;
  if t <> 'in_progress/2' then raise exception 'FAIL a5: %', t; end if;
  select verification_method into t from wms_pick_task_lines where id=pc;
  if t is not null then raise exception 'FAIL a6: null vmethod not preserved (%)', t; end if;
  raise notice 'PASS a — 단일 정상 Hold (플립·held_by·라인 3갈래·진행 흔적 보존)';

  -- ── ⓑ 재호출 멱등 (이미 pending — 내 Hold 응답 유실 재탭) ────────────
  res := wms_hold_pick(
    jsonb_build_array(jsonb_build_object('id',pb,'picked_base',99,'status','picked','verification_method','manual')),
    t1, null);
  if res->>'held' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL b1: %', res; end if;
  select picked_base::text into t from wms_pick_task_lines where id=pb;
  if t <> '2' then raise exception 'FAIL b2: line written on CAS fail (%)', t; end if;
  select held_by into t from wms_pick_tasks where id=t1;
  if t <> 'RPC Tester' then raise exception 'FAIL b3: held_by changed'; end if;
  raise notice 'PASS b — 재호출 멱등 (무기록)';

  -- ── ⓒ CAS 불일치 (남의 태스크): 무변 ────────────────────────────────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-HOLD-2','SO-TEST-HOLD-2','picking') returning id into o2;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B2','Somebody Else','in_progress') returning id into t2;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o2,'SKU-E','SKU-E',1,5,5) returning id into le;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t2,le,5) returning id into pe;

  res := wms_hold_pick(
    jsonb_build_array(jsonb_build_object('id',pe,'picked_base',5,'status','picked','verification_method','manual')),
    t2, null);
  if res->>'held' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL c1: %', res; end if;
  select status||'/'||assigned_to into t from wms_pick_tasks where id=t2;
  if t <> 'in_progress/Somebody Else' then raise exception 'FAIL c2: %', t; end if;
  select count(*) into n from wms_pick_task_lines where id=pe and picked_base > 0;
  if n <> 0 then raise exception 'FAIL c3: line written on CAS fail'; end if;
  raise notice 'PASS c — CAS 불일치 (무변)';

  -- ── ⓓ 이름 드리프트 ──────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"rpc-drift@asung.ca"}', false);
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B3','Old Name','in_progress') returning id into t3;
  res := wms_hold_pick('[]'::jsonb, t3, null);
  if res->>'held' <> 'false' or res->>'worker' <> 'Renamed Worker' then raise exception 'FAIL d1: %', res; end if;
  select status into t from wms_pick_tasks where id=t3;
  if t <> 'in_progress' then raise exception 'FAIL d2: %', t; end if;
  raise notice 'PASS d — 이름 드리프트 (worker 로 원인 식별)';
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);

  -- ── ⓔ 라인 수 불일치: 예외 + 플립 포함 전체 롤백 ─────────────────────
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B4','RPC Tester','in_progress') returning id into t4;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t4,le,3) returning id into p4;
  begin
    res := wms_hold_pick(
      jsonb_build_array(
        jsonb_build_object('id',p4,'picked_base',3,'status','picked','verification_method','manual'),
        jsonb_build_object('id',999999999,'picked_base',1,'status','picked','verification_method','manual')),
      t4, null);
    raise exception 'FAIL e1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('removed by a rollback' in errmsg) = 0 or position('Ask a manager' in errmsg) = 0 then
      raise exception 'FAIL e2: %', errmsg;
    end if;
  end;
  select status||'/'||coalesce(held_by,'-') into t from wms_pick_tasks where id=t4;
  if t <> 'in_progress/-' then raise exception 'FAIL e3: flip not rolled back (%)', t; end if;
  select count(*) into n from wms_pick_task_lines where id=p4 and picked_base > 0;
  if n <> 0 then raise exception 'FAIL e4: line survived rollback'; end if;
  raise notice 'PASS e — 라인 수 불일치 (전체 롤백 · 원인 메시지)';

  -- ── ⓕ 타 배치 라인 오염 차단: 남의 라인 id 를 실어도 스코프 밖 = 롤백 ──
  begin
    res := wms_hold_pick(
      jsonb_build_array(jsonb_build_object('id',pe,'picked_base',4,'status','picked','verification_method','manual')),
      t4, null);
    raise exception 'FAIL f1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('removed by a rollback' in errmsg) = 0 then raise exception 'FAIL f2: %', errmsg; end if;
  end;
  select count(*) into n from wms_pick_task_lines where id=pe and picked_base > 0;
  if n <> 0 then raise exception 'FAIL f3: foreign line written'; end if;
  select status into t from wms_pick_tasks where id=t4;
  if t <> 'in_progress' then raise exception 'FAIL f4: flip survived (%)', t; end if;
  raise notice 'PASS f — 타 배치 라인 오염 차단 (스코프 밖 = 전체 롤백)';

  -- ── ⓖ wave 정상 Hold: 멤버 2 · 서로 다른 오더 ────────────────────────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-HOLD-3','SO-TEST-HOLD-3','picking') returning id into o3;
  insert into wms_waves (label, warehouse, status, assigned_to)
  values ('W-HOLD-1','toronto','in_progress','RPC Tester') returning id into w1;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o2,'SO-TEST-HOLD-2-1','RPC Tester','in_progress',w1,1) returning id into t5;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o3,'SO-TEST-HOLD-3-1','RPC Tester','in_progress',w1,2) returning id into t6;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o3,'SKU-F','SKU-F',1,9,9) returning id into lf;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t5,le,5) returning id into p5a;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t6,lf,9) returning id into pf;

  res := wms_hold_pick(
    jsonb_build_array(
      jsonb_build_object('id',p5a,'picked_base',5,'status','picked',     'verification_method','scanned_base'),
      jsonb_build_object('id',pf, 'picked_base',4,'status','in_progress','verification_method','scanned_base')),
    null, w1);

  if res->>'held' <> 'true' or res->>'mode' <> 'wave' or (res->>'members_held')::int <> 2 then
    raise exception 'FAIL g1: %', res;
  end if;
  select status||'/'||coalesce(assigned_to,'-')||'/'||held_by into t from wms_waves where id=w1;
  if t <> 'pending/-/RPC Tester' then raise exception 'FAIL g2: wave=%', t; end if;
  select count(*) into n from wms_pick_tasks
   where wave_id=w1 and status='pending' and assigned_to is null and held_by='RPC Tester';
  if n <> 2 then raise exception 'FAIL g3: members=%', n; end if;
  select picked_base::text||'/'||status into t from wms_pick_task_lines where id=pf;
  if t <> '4/in_progress' then raise exception 'FAIL g4: %', t; end if;
  raise notice 'PASS g — wave 정상 Hold (wave·멤버 원자 플립 + held_by)';

  -- ── ⓗ wave 재호출 멱등 ───────────────────────────────────────────────
  res := wms_hold_pick(
    jsonb_build_array(jsonb_build_object('id',pf,'picked_base',9,'status','picked','verification_method','manual')),
    null, w1);
  if res->>'held' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL h1: %', res; end if;
  select picked_base::text into t from wms_pick_task_lines where id=pf;
  if t <> '4' then raise exception 'FAIL h2: line written on CAS fail (%)', t; end if;
  raise notice 'PASS h — wave 재호출 멱등 (무기록)';

  -- ── ⓘ wave 멤버 어긋남: 한 멤버가 남의 것 → 예외 + wave 플립 롤백 ────
  insert into wms_waves (label, warehouse, status, assigned_to)
  values ('W-HOLD-2','toronto','in_progress','RPC Tester') returning id into w2;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o2,'B5','RPC Tester','in_progress',w2,1);
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o3,'B6','Somebody Else','in_progress',w2,2);
  begin
    res := wms_hold_pick('[]'::jsonb, null, w2);
    raise exception 'FAIL i1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('member batches matched' in errmsg) = 0 then raise exception 'FAIL i2: %', errmsg; end if;
  end;
  select status||'/'||assigned_to into t from wms_waves where id=w2;
  if t <> 'in_progress/RPC Tester' then raise exception 'FAIL i3: wave flip not rolled back (%)', t; end if;
  select count(*) into n from wms_pick_tasks where wave_id=w2 and status='pending';
  if n <> 0 then raise exception 'FAIL i4: member flipped despite rollback'; end if;
  raise notice 'PASS i — wave 멤버 어긋남 (전체 롤백)';

  -- ── ⓙ 미등록 이메일 ─────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"nobody@asung.ca"}', false);
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B7','RPC Tester','in_progress') returning id into t7;
  begin
    res := wms_hold_pick('[]'::jsonb, t7, null);
    raise exception 'FAIL j1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('No staff record' in errmsg) = 0 then raise exception 'FAIL j2: %', errmsg; end if;
  end;
  raise notice 'PASS j — 미등록 로그인 차단';
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);

  -- ── ⓚ 모드 배타: 둘 다/둘 다 아님 → 예외 ────────────────────────────
  begin
    res := wms_hold_pick('[]'::jsonb, t7, w1);
    raise exception 'FAIL k1: no exception (both)';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('exactly one' in errmsg) = 0 then raise exception 'FAIL k2: %', errmsg; end if;
  end;
  begin
    res := wms_hold_pick('[]'::jsonb);
    raise exception 'FAIL k3: no exception (neither)';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('exactly one' in errmsg) = 0 then raise exception 'FAIL k4: %', errmsg; end if;
  end;
  raise notice 'PASS k — 모드 배타 검증';

  raise notice '════ ALL 11 TESTS PASSED ════';
end
$test$;

rollback;
