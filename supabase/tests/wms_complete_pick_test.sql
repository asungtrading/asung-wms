-- wms_complete_pick 로컬 기능 테스트 (2026-08-06 · 픽 완료 RPC — 팩 테스트 원형 + wave)
--
-- 실행 (로컬 supabase — 프로덕션 금지):
--   supabase db reset
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/wms_complete_pick_test.sql
--
-- 전체가 한 트랜잭션 + 마지막 ROLLBACK — 로컬 DB 에 무흔적.
-- 전부 통과하면 마지막 NOTICE 가 "ALL 12 TESTS PASSED".

begin;

do $test$
declare
  o1 bigint; o2 bigint; o3 bigint; ox bigint;
  t1 bigint; t2 bigint; t3 bigint; t4 bigint; t5 bigint; t6 bigint; t7 bigint;
  w1 bigint; w2 bigint; w3 bigint;
  la bigint; lb bigint; lc bigint; ld bigint; le bigint; lf bigint;   -- order lines
  pa bigint; pb bigint; pc bigint; pd bigint; pe bigint; pf bigint;   -- pick lines
  p4 bigint; p5a bigint; p7 bigint;
  res jsonb;
  n int; t text;
  errmsg text;
begin
  -- ── 셋업: 직원 · 로그인 흉내 ─────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);
  insert into wms_staff (name, email, role, warehouse_access, active)
  values ('RPC Tester', 'rpc-test@asung.ca', 'worker', 'both', true),
         ('Renamed Worker', 'rpc-drift@asung.ca', 'worker', 'both', true);

  -- ── 셋업: 단일 모드 시나리오 — 라인 4개가 전 갈래 커버 ──────────────
  -- A=미선언 부족(short_pick) · B=정상 · C=선언·여전히 부족(refresh) · D=선언·채움(delete)
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-PICK-1', 'SO-TEST-PICK-1', 'picking') returning id into o1;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o1, 'SO-TEST-PICK-1-1', 'RPC Tester', 'in_progress') returning id into t1;

  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-A','SKU-A',1,10,10) returning id into la;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-B','SKU-B',1,6,6) returning id into lb;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-C','SKU-C',1,8,8) returning id into lc;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-D','SKU-D',1,4,4) returning id into ld;

  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t1,la,10) returning id into pa;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t1,lb,6)  returning id into pb;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t1,lc,8)  returning id into pc;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t1,ld,4)  returning id into pd;

  -- 선행 선언: C·D = stock_short (규칙 41)
  insert into wms_discrepancies (order_id, order_number, sku, ordered_base, actual_base, reason, source, declared_by, cin7_corrected)
  values (o1,'SO-TEST-PICK-1','SKU-C',8,2,'stock_short','picking','RPC Tester',false),
         (o1,'SO-TEST-PICK-1','SKU-D',4,1,'stock_short','picking','RPC Tester',false);

  -- ── ⓐ 단일 정상 완료 (부족 포함) ────────────────────────────────────
  res := wms_complete_pick(
    jsonb_build_array(
      jsonb_build_object('id',pa,'picked_base',7, 'status','short', 'verification_method','scanned_base'),
      jsonb_build_object('id',pb,'picked_base',6, 'status','picked','verification_method','scanned_variant'),
      jsonb_build_object('id',pc,'picked_base',3, 'status','short', 'verification_method',null),
      jsonb_build_object('id',pd,'picked_base',4, 'status','picked','verification_method','manual')),
    t1, null,
    jsonb_build_array(jsonb_build_object('order_id',o1,'pick_task_id',t1,'sku','SKU-A','ordered_base',10,'actual_base',7)),
    jsonb_build_array(jsonb_build_object('order_id',o1,'sku','SKU-C','ordered_base',8,'actual_base',3)),
    jsonb_build_array(jsonb_build_object('order_id',o1,'sku','SKU-D')));

  if res->>'completed' <> 'true' or res->>'mode' <> 'single' then raise exception 'FAIL a1: %', res; end if;
  if (res->>'lines_updated')::int <> 4 or (res->>'disc_inserted')::int <> 1
     or (res->>'short_refreshed')::int <> 1 or (res->>'short_deleted')::int <> 1 then
    raise exception 'FAIL a2: counts=%', res;
  end if;
  select status||'/'||completed_by into t from wms_pick_tasks where id=t1;
  if t <> 'completed/RPC Tester' then raise exception 'FAIL a3: task=%', t; end if;
  select status into t from wms_pick_task_lines where id=pa;
  if t <> 'short' then raise exception 'FAIL a4: %', t; end if;
  select status||'/'||picked_base::text into t from wms_pick_task_lines where id=pb;
  if t <> 'picked/6' then raise exception 'FAIL a5: %', t; end if;
  select coalesce(responsible,'-')||'/'||order_number into t from wms_discrepancies
   where pick_task_id=t1 and reason='short_pick' and sku='SKU-A';
  if t <> '-/SO-TEST-PICK-1' then raise exception 'FAIL a6: short_pick=% (responsible 미설정·order_number 서버 유도)', t; end if;
  select actual_base::text into t from wms_discrepancies
   where order_id=o1 and sku='SKU-C' and reason='stock_short';
  if t <> '3' then raise exception 'FAIL a7: refresh=%', t; end if;
  select count(*) into n from wms_discrepancies where order_id=o1 and sku='SKU-D' and reason='stock_short';
  if n <> 0 then raise exception 'FAIL a8: stale declaration not deleted'; end if;
  raise notice 'PASS a — 단일 정상 완료 (short_pick·refresh·stale delete)';

  -- ── ⓑ 단일 재호출 멱등 ───────────────────────────────────────────────
  res := wms_complete_pick(
    jsonb_build_array(jsonb_build_object('id',pa,'picked_base',7,'status','short','verification_method','scanned_base')),
    t1, null,
    jsonb_build_array(jsonb_build_object('order_id',o1,'pick_task_id',t1,'sku','SKU-A','ordered_base',10,'actual_base',7)));
  if res->>'completed' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL b1: %', res; end if;
  select count(*) into n from wms_discrepancies where pick_task_id=t1 and reason='short_pick';
  if n <> 1 then raise exception 'FAIL b2: short_pick duplicated (%)', n; end if;
  raise notice 'PASS b — 단일 재호출 멱등';

  -- ── ⓒ CAS 불일치 (남의 태스크): 무변 ────────────────────────────────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-PICK-2','SO-TEST-PICK-2','picking') returning id into o2;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B2','Somebody Else','in_progress') returning id into t2;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o2,'SKU-E','SKU-E',1,5,5) returning id into le;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t2,le,5) returning id into pe;

  res := wms_complete_pick(
    jsonb_build_array(jsonb_build_object('id',pe,'picked_base',5,'status','picked','verification_method','manual')),
    t2, null);
  if res->>'completed' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL c1: %', res; end if;
  select count(*) into n from wms_pick_task_lines where id=pe and picked_base > 0;
  if n <> 0 then raise exception 'FAIL c2: line written on CAS fail'; end if;
  raise notice 'PASS c — CAS 불일치 (무변)';

  -- ── ⓓ 이름 드리프트 ──────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"rpc-drift@asung.ca"}', false);
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B3','Old Name','in_progress') returning id into t3;
  res := wms_complete_pick('[]'::jsonb, t3, null);
  if res->>'completed' <> 'false' or res->>'worker' <> 'Renamed Worker' then raise exception 'FAIL d1: %', res; end if;
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
    res := wms_complete_pick(
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
  select status into t from wms_pick_tasks where id=t4;
  if t <> 'in_progress' then raise exception 'FAIL e3: flip not rolled back (%)', t; end if;
  raise notice 'PASS e — 라인 수 불일치 (전체 롤백 · 원인 메시지)';

  -- ── ⓕ wave 정상 완료: 멤버 2 · 서로 다른 오더 · 귀속 확인 ────────────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-PICK-3','SO-TEST-PICK-3','picking') returning id into o3;
  insert into wms_waves (label, warehouse, status, assigned_to)
  values ('W-TEST-1','toronto','in_progress','RPC Tester') returning id into w1;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o2,'SO-TEST-PICK-2-1','RPC Tester','in_progress',w1,1) returning id into t5;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o3,'SO-TEST-PICK-3-1','RPC Tester','in_progress',w1,2) returning id into t6;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o3,'SKU-F','SKU-F',1,9,9) returning id into lf;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t5,le,5) returning id into p5a;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t6,lf,9) returning id into pf;

  res := wms_complete_pick(
    jsonb_build_array(
      jsonb_build_object('id',p5a,'picked_base',5,'status','picked','verification_method','scanned_base'),
      jsonb_build_object('id',pf, 'picked_base',6,'status','short', 'verification_method','scanned_base')),
    null, w1,
    -- short 는 멤버 2(t6)의 오더(o3) 소속 — wave 라인별 귀속 (규칙 18)
    jsonb_build_array(jsonb_build_object('order_id',o3,'pick_task_id',t6,'sku','SKU-F','ordered_base',9,'actual_base',6)));

  if res->>'completed' <> 'true' or res->>'mode' <> 'wave' or (res->>'members_completed')::int <> 2 then
    raise exception 'FAIL f1: %', res;
  end if;
  select status into t from wms_waves where id=w1;
  if t <> 'completed' then raise exception 'FAIL f2: wave=%', t; end if;
  select count(*) into n from wms_pick_tasks where wave_id=w1 and status='completed' and completed_by='RPC Tester';
  if n <> 2 then raise exception 'FAIL f3: members=%', n; end if;
  select order_id::text||'/'||order_number into t from wms_discrepancies
   where pick_task_id=t6 and reason='short_pick';
  if t <> o3::text||'/SO-TEST-PICK-3' then raise exception 'FAIL f4: 귀속=%', t; end if;
  raise notice 'PASS f — wave 정상 완료 (멤버·wave 원자 · short 오더별 귀속)';

  -- ── ⓖ wave 재호출 멱등 ───────────────────────────────────────────────
  res := wms_complete_pick(
    jsonb_build_array(jsonb_build_object('id',pf,'picked_base',6,'status','short','verification_method','scanned_base')),
    null, w1,
    jsonb_build_array(jsonb_build_object('order_id',o3,'pick_task_id',t6,'sku','SKU-F','ordered_base',9,'actual_base',6)));
  if res->>'completed' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL g1: %', res; end if;
  select count(*) into n from wms_discrepancies where pick_task_id=t6 and reason='short_pick';
  if n <> 1 then raise exception 'FAIL g2: duplicated (%)', n; end if;
  raise notice 'PASS g — wave 재호출 멱등';

  -- ── ⓗ wave 멤버 어긋남: 한 멤버가 남의 것 → 예외 + wave 플립 롤백 ────
  insert into wms_waves (label, warehouse, status, assigned_to)
  values ('W-TEST-2','toronto','in_progress','RPC Tester') returning id into w2;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o2,'B5','RPC Tester','in_progress',w2,1);
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o3,'B6','Somebody Else','in_progress',w2,2);
  begin
    res := wms_complete_pick('[]'::jsonb, null, w2);
    raise exception 'FAIL h1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('member batches matched' in errmsg) = 0 then raise exception 'FAIL h2: %', errmsg; end if;
  end;
  select status into t from wms_waves where id=w2;
  if t <> 'in_progress' then raise exception 'FAIL h3: wave flip not rolled back (%)', t; end if;
  select count(*) into n from wms_pick_tasks where wave_id=w2 and status='completed';
  if n <> 0 then raise exception 'FAIL h4: member flipped despite rollback'; end if;
  raise notice 'PASS h — wave 멤버 어긋남 (전체 롤백)';

  -- ── ⓘ 귀속 가드: 범위 밖 order_id → 예외 + 전체 롤백 ─────────────────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-PICK-X','SO-TEST-PICK-X','picking') returning id into ox;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B7','RPC Tester','in_progress') returning id into t7;
  insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base)
  values (t7,le,2) returning id into p7;
  begin
    res := wms_complete_pick(
      jsonb_build_array(jsonb_build_object('id',p7,'picked_base',1,'status','short','verification_method','manual')),
      t7, null,
      jsonb_build_array(jsonb_build_object('order_id',ox,'pick_task_id',t7,'sku','SKU-E','ordered_base',2,'actual_base',1)));
    raise exception 'FAIL i1: no exception on out-of-scope order';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('outside this pick scope' in errmsg) = 0 then raise exception 'FAIL i2: %', errmsg; end if;
  end;
  select status into t from wms_pick_tasks where id=t7;
  if t <> 'in_progress' then raise exception 'FAIL i3: flip survived guard failure (%)', t; end if;
  select count(*) into n from wms_discrepancies where order_id=ox;
  if n <> 0 then raise exception 'FAIL i4: mis-attributed disc written'; end if;
  raise notice 'PASS i — 귀속 가드 (범위 밖 오더 차단 · 전체 롤백)';

  -- ── ⓙ 미등록 이메일 ─────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"nobody@asung.ca"}', false);
  begin
    res := wms_complete_pick('[]'::jsonb, t7, null);
    raise exception 'FAIL j1: no exception';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('No staff record' in errmsg) = 0 then raise exception 'FAIL j2: %', errmsg; end if;
  end;
  raise notice 'PASS j — 미등록 로그인 차단';
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);

  -- ── ⓚ 과거 2단 쓰기 잔재: wave completed + 멤버 미완 → 재호출 무변 ────
  -- (RPC 는 이 상태를 만들 수 없다 — 과거 부분 실패 잔재의 동작을 문서화.
  --  배포 전 프로덕션 감사 SQL 로 실재 여부를 확인한다.)
  insert into wms_waves (label, warehouse, status, assigned_to)
  values ('W-TEST-3','toronto','completed','RPC Tester') returning id into w3;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no)
  values (o2,'B8','RPC Tester','in_progress',w3,1);
  res := wms_complete_pick('[]'::jsonb, null, w3);
  if res->>'completed' <> 'false' then raise exception 'FAIL k1: %', res; end if;
  select count(*) into n from wms_pick_tasks where wave_id=w3 and status='completed';
  if n <> 0 then raise exception 'FAIL k2: residue member flipped'; end if;
  raise notice 'PASS k — 잔재 상태(완료 wave·미완 멤버): completed=false·무변 (감사 SQL 로 별도 확인)';

  -- ── ⓛ 모드 배타: 둘 다/둘 다 아님 → 예외 ────────────────────────────
  begin
    res := wms_complete_pick('[]'::jsonb, t7, w1);
    raise exception 'FAIL l1: no exception (both)';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('exactly one' in errmsg) = 0 then raise exception 'FAIL l2: %', errmsg; end if;
  end;
  begin
    res := wms_complete_pick('[]'::jsonb);
    raise exception 'FAIL l3: no exception (neither)';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('exactly one' in errmsg) = 0 then raise exception 'FAIL l4: %', errmsg; end if;
  end;
  raise notice 'PASS l — 모드 배타 검증';

  raise notice '════ ALL 12 TESTS PASSED ════';
end
$test$;

rollback;
