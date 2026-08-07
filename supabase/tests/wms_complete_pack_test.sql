-- wms_complete_pack 로컬 기능 테스트 (2026-08-06 · 8단계)
--
-- 실행 (로컬 supabase — 프로덕션 금지):
--   supabase db reset
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/wms_complete_pack_test.sql
--
-- 전체가 한 트랜잭션이고 마지막에 ROLLBACK — 로컬 DB 에 아무것도 남기지 않는다.
-- 전부 통과하면 마지막 NOTICE 가 "ALL 8 TESTS PASSED".
-- auth.email() 은 request.jwt.claims 를 읽으므로 set_config 로 흉내낸다.

begin;

do $test$
declare
  o1 bigint; o2 bigint;
  p1 bigint; p2 bigint; p3 bigint; p4 bigint; p6 bigint;
  k1 bigint; k2 bigint; k3 bigint; k4 bigint; k6 bigint;
  la bigint; lb bigint; lc bigint; ld bigint; le bigint; lf bigint;  -- order lines
  pla bigint; plb bigint; plc bigint; pld bigint; ple bigint; plf bigint;  -- pack lines
  pl2 bigint; pl4 bigint; pl6 bigint;
  res jsonb;
  n int; t text;
  errmsg text;
begin
  -- ── 셋업: 직원 · 로그인 흉내 ─────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);
  insert into wms_staff (name, email, role, warehouse_access, active)
  values ('RPC Tester', 'rpc-test@asung.ca', 'worker', 'both', true),
         ('Renamed Worker', 'rpc-drift@asung.ca', 'worker', 'both', true);

  -- ── 셋업: 오더 1 (본 시나리오) — 라인 6개가 전 갈래를 커버 ──────────
  -- A=팩에서 회복(short_pick 해소) · B=미선언 부족(short_after_pack) · C=초과(over_pick)
  -- D=중복스캔(pack_scan_mistake) · E=선언·여전히 부족(refresh) · F=선언·채움(resolve)
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-RPC-1', 'SO-TEST-RPC-1', 'packing') returning id into o1;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o1, 'SO-TEST-RPC-1-1', 'Picker Kim', 'completed') returning id into p1;
  insert into wms_pack_tasks (order_id, pick_task_id, batch_label, assigned_to, status)
  values (o1, p1, 'SO-TEST-RPC-1-1', 'RPC Tester', 'in_progress') returning id into k1;

  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-A','SKU-A',1,10,10) returning id into la;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-B','SKU-B',1,12,12) returning id into lb;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-C','SKU-C',1,5,5) returning id into lc;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-D','SKU-D',1,6,6) returning id into ld;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-E','SKU-E',1,10,10) returning id into le;
  insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base)
  values (o1,'SKU-F','SKU-F',1,4,4) returning id into lf;

  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,la,7)  returning id into pla;   -- 픽커가 7만 가져옴 → 팩에서 10 채움(회복)
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,lb,12) returning id into plb;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,lc,5)  returning id into plc;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,ld,6)  returning id into pld;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,le,10) returning id into ple;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k1,lf,4)  returning id into plf;

  -- 선행 discrepancy: A=short_pick(픽 부족) · E,F=stock_short 선언
  insert into wms_discrepancies (order_id, order_number, sku, ordered_base, actual_base, reason, cin7_corrected)
  values (o1,'SO-TEST-RPC-1','SKU-A',10,7,'short_pick',false);
  insert into wms_discrepancies (order_id, order_number, sku, ordered_base, actual_base, reason, source, declared_by, cin7_corrected)
  values (o1,'SO-TEST-RPC-1','SKU-E',10,3,'stock_short','picking','Picker Kim',false),
         (o1,'SO-TEST-RPC-1','SKU-F',4,2,'stock_short','picking','Picker Kim',false);

  -- ── ⓐ 정상 완료: 전 갈래 한 번에 ────────────────────────────────────
  res := wms_complete_pack(
    k1,
    jsonb_build_array(
      jsonb_build_object('id',pla,'verified_base',10,'status','verified','verification_method','scanned_base'),
      jsonb_build_object('id',plb,'verified_base',8, 'status','mismatch','verification_method','scanned_base'),
      jsonb_build_object('id',plc,'verified_base',5, 'status','verified','verification_method','scanned_variant'),
      jsonb_build_object('id',pld,'verified_base',6, 'status','verified','verification_method','manual'),
      jsonb_build_object('id',ple,'verified_base',4, 'status','mismatch','verification_method',null),
      jsonb_build_object('id',plf,'verified_base',4, 'status','verified','verification_method','scanned_base')),
    jsonb_build_array(
      jsonb_build_object('sku','SKU-B','reason','short_after_pack','ordered_base',12,'actual_base',8),
      jsonb_build_object('sku','SKU-C','reason','over_pick','ordered_base',5,'actual_base',7),
      jsonb_build_object('sku','SKU-D','reason','pack_scan_mistake','ordered_base',6,'actual_base',6)),
    jsonb_build_array(jsonb_build_object('sku','SKU-E','ordered_base',10,'actual_base',4)),
    '["SKU-F"]'::jsonb,
    '["SKU-A"]'::jsonb);

  if res->>'completed' <> 'true' then raise exception 'FAIL a1: completed=%', res; end if;
  if res->>'worker' <> 'RPC Tester' then raise exception 'FAIL a2: worker=%', res->>'worker'; end if;
  if (res->>'lines_updated')::int <> 6 or (res->>'disc_inserted')::int <> 3
     or (res->>'short_refreshed')::int <> 1 or (res->>'short_resolved')::int <> 1
     or (res->>'recovered_resolved')::int <> 1 then
    raise exception 'FAIL a3: counts=%', res;
  end if;
  select status||'/'||completed_by into t from wms_pack_tasks where id=k1;
  if t <> 'completed/RPC Tester' then raise exception 'FAIL a4: task=%', t; end if;
  select count(*) into n from wms_pack_task_lines
   where pack_task_id=k1 and verified_at is not null;
  if n <> 6 then raise exception 'FAIL a5: verified_at on % of 6', n; end if;
  select verification_method into t from wms_pack_task_lines where id=ple;
  if t is not null then raise exception 'FAIL a6: null vmethod not preserved (%)', t; end if;
  select responsible||'/'||coalesce(source,'-') into t from wms_discrepancies
   where pack_task_id=k1 and reason='short_after_pack';
  if t <> 'Picker Kim/-' then raise exception 'FAIL a7: short_after_pack=%', t; end if;
  select coalesce(responsible,'-')||'/'||source||'/'||declared_by||'/'||resolved_by into t
    from wms_discrepancies where pack_task_id=k1 and reason='pack_scan_mistake';
  if t <> '-/packing/RPC Tester/RPC Tester' then raise exception 'FAIL a8: scan_mistake=%', t; end if;
  select actual_base::text into t from wms_discrepancies
   where order_id=o1 and sku='SKU-E' and reason='stock_short';
  if t <> '4' then raise exception 'FAIL a9: refresh actual=%', t; end if;
  select resolved_by into t from wms_discrepancies
   where order_id=o1 and sku='SKU-F' and reason='stock_short';
  if t <> 'RPC Tester' then raise exception 'FAIL a10: F not resolved'; end if;
  select reason||'/'||resolved_by into t from wms_discrepancies where order_id=o1 and sku='SKU-A';
  if t <> 'resolved_pack_recovery/RPC Tester' then raise exception 'FAIL a11: recovery=%', t; end if;
  if res->>'ready' <> 'true' then raise exception 'FAIL a12: ready=%', res->>'ready'; end if;
  select status into t from wms_orders where id=o1;
  if t <> 'ready_to_close' then raise exception 'FAIL a13: order=%', t; end if;
  raise notice 'PASS a — 정상 완료 (전 갈래 · ready)';

  -- ── ⓑ 재호출 멱등: 같은 페이로드 재실행 → completed=false · 중복 0 ──
  res := wms_complete_pack(k1,
    jsonb_build_array(jsonb_build_object('id',pla,'verified_base',10,'status','verified','verification_method','scanned_base')),
    jsonb_build_array(jsonb_build_object('sku','SKU-B','reason','short_after_pack','ordered_base',12,'actual_base',8)));
  if res->>'completed' <> 'false' then raise exception 'FAIL b1: %', res; end if;
  select count(*) into n from wms_discrepancies where pack_task_id=k1;
  if n <> 3 then raise exception 'FAIL b2: disc duplicated (%)', n; end if;
  raise notice 'PASS b — 재호출 멱등 (completed=false · discrepancy 중복 없음)';

  -- ── ⓒ CAS 불일치 (남의 태스크): 아무것도 안 씀 ──────────────────────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-RPC-2','SO-TEST-RPC-2','packing') returning id into o2;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B2','Picker Kim','completed') returning id into p2;
  insert into wms_pack_tasks (order_id, pick_task_id, assigned_to, status)
  values (o2, p2, 'Somebody Else', 'in_progress') returning id into k2;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k2, la, 5) returning id into pl2;

  res := wms_complete_pack(k2,
    jsonb_build_array(jsonb_build_object('id',pl2,'verified_base',5,'status','verified','verification_method','manual')),
    jsonb_build_array(jsonb_build_object('sku','SKU-A','reason','over_pick','ordered_base',5,'actual_base',6)));
  if res->>'completed' <> 'false' or res->>'worker' <> 'RPC Tester' then raise exception 'FAIL c1: %', res; end if;
  select count(*) into n from wms_pack_task_lines where id=pl2 and verified_at is not null;
  if n <> 0 then raise exception 'FAIL c2: line written on CAS fail'; end if;
  select count(*) into n from wms_discrepancies where pack_task_id=k2;
  if n <> 0 then raise exception 'FAIL c3: disc written on CAS fail'; end if;
  raise notice 'PASS c — CAS 불일치 (라인·discrepancy 무변)';

  -- ── ⓓ 이름 드리프트: 세션은 살아 있는데 wms_staff.name 이 바뀐 경우 ──
  -- assigned_to='Old Name'(클레임 당시 이름) vs 서버 유도 worker='Renamed Worker'.
  -- completed=false + worker 반환 → 프론트가 me.name 과 대조해 원인 안내.
  perform set_config('request.jwt.claims', '{"email":"rpc-drift@asung.ca"}', false);
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B3','Picker Kim','completed') returning id into p3;
  insert into wms_pack_tasks (order_id, pick_task_id, assigned_to, status)
  values (o2, p3, 'Old Name', 'in_progress') returning id into k3;
  res := wms_complete_pack(k3, '[]'::jsonb);
  if res->>'completed' <> 'false' or res->>'worker' <> 'Renamed Worker' then
    raise exception 'FAIL d1: %', res;
  end if;
  select status into t from wms_pack_tasks where id=k3;
  if t <> 'in_progress' then raise exception 'FAIL d2: task=%', t; end if;
  raise notice 'PASS d — 이름 드리프트 (completed=false + worker 로 원인 식별 가능)';
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);

  -- ── ⓔ 라인 수 불일치: 예외 + 전체 롤백 (플립 포함) ──────────────────
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B4','Picker Kim','completed') returning id into p4;
  insert into wms_pack_tasks (order_id, pick_task_id, assigned_to, status)
  values (o2, p4, 'RPC Tester', 'in_progress') returning id into k4;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k4, lb, 3) returning id into pl4;

  begin
    res := wms_complete_pack(k4,
      jsonb_build_array(
        jsonb_build_object('id',pl4,'verified_base',3,'status','verified','verification_method','manual'),
        jsonb_build_object('id',999999999,'verified_base',1,'status','verified','verification_method','manual')),
      jsonb_build_array(jsonb_build_object('sku','SKU-B','reason','over_pick','ordered_base',3,'actual_base',4)));
    raise exception 'FAIL e1: no exception on line mismatch';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('removed by a rollback' in errmsg) = 0 or position('Ask a manager' in errmsg) = 0 then
      raise exception 'FAIL e2: message lacks cause guidance: %', errmsg;
    end if;
  end;
  select status into t from wms_pack_tasks where id=k4;
  if t <> 'in_progress' then raise exception 'FAIL e3: flip not rolled back (%)', t; end if;
  select count(*) into n from wms_pack_task_lines where id=pl4 and verified_at is not null;
  if n <> 0 then raise exception 'FAIL e4: line survived rollback'; end if;
  select count(*) into n from wms_discrepancies where pack_task_id=k4;
  if n <> 0 then raise exception 'FAIL e5: disc survived rollback'; end if;
  raise notice 'PASS e — 라인 수 불일치 (예외 메시지에 원인 · 플립까지 전체 롤백)';

  -- ── ⓕ 불량 reason: 플립 전 검증에서 예외 ─────────────────────────────
  begin
    res := wms_complete_pack(k4,
      jsonb_build_array(jsonb_build_object('id',pl4,'verified_base',3,'status','verified','verification_method','manual')),
      jsonb_build_array(jsonb_build_object('sku','SKU-B','reason','stock_short','ordered_base',3,'actual_base',1)));
    raise exception 'FAIL f1: no exception on bad reason';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('not allowed' in errmsg) = 0 then raise exception 'FAIL f2: %', errmsg; end if;
  end;
  select status into t from wms_pack_tasks where id=k4;
  if t <> 'in_progress' then raise exception 'FAIL f3'; end if;
  raise notice 'PASS f — 불량 reason 차단 (무변)';

  -- ── ⓖ 미등록 이메일: 예외 ───────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"nobody@asung.ca"}', false);
  begin
    res := wms_complete_pack(k4, '[]'::jsonb);
    raise exception 'FAIL g1: no exception on unknown staff';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('No staff record' in errmsg) = 0 then raise exception 'FAIL g2: %', errmsg; end if;
  end;
  raise notice 'PASS g — 미등록 로그인 차단';
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);

  -- ── ⓗ ready 서브블록 비치명: 오더 UPDATE 가 죽어도 완료는 커밋 ───────
  insert into wms_orders (cin7_sale_id, order_number, status)
  values ('TEST-RPC-3','SO-TEST-RPC-3','packing') returning id into o2;
  insert into wms_pick_tasks (order_id, batch_label, assigned_to, status)
  values (o2,'B6','Picker Kim','completed') returning id into p6;
  insert into wms_pack_tasks (order_id, pick_task_id, assigned_to, status)
  values (o2, p6, 'RPC Tester', 'in_progress') returning id into k6;
  insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base)
  values (k6, lc, 2) returning id into pl6;

  -- 전체가 ROLLBACK 되는 트랜잭션 안이라 이 임시 함수·트리거는 DB 에 남지 않는다
  create function public.__rpc_test_boom() returns trigger language plpgsql as
    $f$ begin raise exception 'simulated order update failure'; end $f$;
  create trigger t_boom before update on wms_orders
    for each row execute function public.__rpc_test_boom();

  res := wms_complete_pack(k6,
    jsonb_build_array(jsonb_build_object('id',pl6,'verified_base',2,'status','verified','verification_method','manual')));
  drop trigger t_boom on wms_orders;
  drop function public.__rpc_test_boom();

  if res->>'completed' <> 'true' then raise exception 'FAIL h1: %', res; end if;
  if res->>'ready' <> 'false' or res->>'ready_error' is null then raise exception 'FAIL h2: %', res; end if;
  select status into t from wms_pack_tasks where id=k6;
  if t <> 'completed' then raise exception 'FAIL h3: %', t; end if;
  select status into t from wms_orders where id=o2;
  if t <> 'packing' then raise exception 'FAIL h4: order changed (%)', t; end if;
  raise notice 'PASS h — ready 실패 비치명 (완료 유지 · ready_error 보고)';

  raise notice '════ ALL 8 TESTS PASSED ════';
end
$test$;

rollback;
