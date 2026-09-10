-- 같은 사람 · 다중 기기 차단 — ① 픽·팩 검증 격자 (2026-09-10 · 규칙 28 소절)
--
-- 실행 (⚠️ 로컬 supabase 만 — 프로덕션·테스트 DB 금지 · 전체가 한 트랜잭션 + 마지막 ROLLBACK = DB 무변):
--   (a) 마이그레이션이 아직 로컬에 없을 때 — 트랜잭션 안에서 적용 → 격자 → ROLLBACK:
--       psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" \
--         -v mig=supabase/migrations/20260910230704_session_guard_pick_pack.sql -f scripts/testdb/session_guard_check.sql
--   (b) supabase db reset 뒤(이미 적용됨):
--       psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v mig=/dev/null -f scripts/testdb/session_guard_check.sql
-- 전부 통과하면 마지막 NOTICE 가 "SESSION GUARD: ALL CHECKS PASSED".
--
-- ⚠️ security invoker + auth.email() 이라 psql 에서 set_config('request.jwt.claims', …) 로 신원을 흘린다.
--    RLS 는 postgres 역할이라 안 걸린다 — RLS 회귀는 이 파일이 보지 않는다(정책 무변).
-- ⚠️ PostgREST 의 오버로드 모호성은 psql 로 재현할 수 없다 — pg_proc 정의 1개(케이스 0)가 대리 증거다.

\set ON_ERROR_STOP on
begin;
\i :mig

-- payload 조립 헬퍼 — pg_temp 라 ROLLBACK 과 함께 사라진다 (프론트가 보내는 모양 그대로)
create function pg_temp.pick_lines(p_task bigint) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id,
           'picked_base', case when assigned_base=10 then 10 else 3 end,
           'status', case when assigned_base=10 then 'picked' else 'short' end,
           'verification_method', case when assigned_base=10 then 'scanned_base' else 'manual' end) order by id), '[]')
    from wms_pick_task_lines where pick_task_id=p_task $$;
create function pg_temp.pick_disc(p_task bigint) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('order_id', order_id, 'pick_task_id', id, 'sku','GB','ordered_base',5,'actual_base',3))
    from wms_pick_tasks where id=p_task $$;
create function pg_temp.hold_lines(p_task bigint) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'picked_base', picked_base,
           'status', case when picked_base>0 then 'in_progress' else 'pending' end,
           'verification_method', verification_method) order by id), '[]')
    from wms_pick_task_lines where pick_task_id=p_task $$;
create function pg_temp.wave_lines(p_wave bigint) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'picked_base', 4, 'status','picked','verification_method','scanned_base') order by l.id), '[]')
    from wms_pick_task_lines l join wms_pick_tasks t on t.id=l.pick_task_id where t.wave_id=p_wave $$;
create function pg_temp.pack_lines(p_pack bigint) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'verified_base', 10, 'status','verified','verification_method','scanned_base') order by id), '[]')
    from wms_pack_task_lines where pack_task_id=p_pack $$;
create function pg_temp.pack_hold_lines(p_pack bigint) returns jsonb language sql as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', id, 'verified_base', 4, 'status','in_progress','verification_method','scanned_base') order by id), '[]')
    from wms_pack_task_lines where pack_task_id=p_pack $$;

do $chk$
declare
  v_tester text := 'Guard Tester';
  n int; t text; res jsonb;
  o bigint; l1 bigint; l2 bigint;
  T1 bigint; T2 bigint; T3 bigint; T4 bigint; T5 bigint; T6 bigint; T7 bigint; T8 bigint; T9 bigint;
  W1 bigint; WM1 bigint; WM2 bigint;
  P1 bigint; P2 bigint; P3 bigint; P4 bigint; P5 bigint; P6 bigint; P7 bigint; P8 bigint;
  pl1 bigint; pl2 bigint;
  disc_before int; picked_before numeric;
  -- 픽 배치 fixture: 라인 2개(GA assigned 10 · GB assigned 5) · 초기 picked 3/0 → 완료 payload 10/3(GB short)
begin
  -- ── 케이스 0: 오버로드 1개 · 시그니처 끝 p_session_id text · ACL ─────────────────────
  for t in select unnest(array['wms_complete_pick','wms_hold_pick','wms_complete_pack','wms_hold_pack']) loop
    select count(*) into n from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace where ns.nspname='public' and p.proname=t;
    if n <> 1 then raise exception 'FAIL 0-overload %: defs=% (옛 시그니처가 남았다 — PostgREST 모호성)', t, n; end if;
    perform 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
     where ns.nspname='public' and p.proname=t and pg_get_function_identity_arguments(p.oid) like '%p_session_id text';
    if not found then raise exception 'FAIL 0-sig %: 마지막 파라미터가 p_session_id text 가 아니다', t; end if;
    perform 1 from pg_proc p join pg_namespace ns on ns.oid=p.pronamespace
     where ns.nspname='public' and p.proname=t
       and has_function_privilege('authenticated', p.oid, 'execute')
       and not has_function_privilege('anon', p.oid, 'execute');
    if not found then raise exception 'FAIL 0-acl %: authenticated 실행 불가 또는 anon 실행 가능', t; end if;
  end loop;
  raise notice 'PASS 0: 4 RPC — 정의 1개 · p_session_id text 끝 · ACL(authenticated t / anon f)';

  -- ── 셋업: 직원 · 로그인 흉내 ─────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"guard-test@asung.ca"}', false);
  insert into wms_staff (name, email, role, warehouse_access, active)
  values (v_tester, 'guard-test@asung.ca', 'worker', 'both', true),
         ('Other Worker', 'guard-other@asung.ca', 'worker', 'both', true);

  -- 픽 배치 9개 (T1~T9) — 각 오더 1 · 라인 2
  for i in 1..9 loop
    insert into wms_orders (cin7_sale_id, order_number, status, warehouse)
    values ('GUARD-T'||i, 'SO-GUARD-T'||i, 'picking', 'toronto') returning id into o;
    insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, session_id)
    values (o, 'SO-GUARD-T'||i||'-1',
            case when i in (5,9) then 'Other Worker' else v_tester end,
            'in_progress',
            case when i in (1,4,6,8) then null else 'S1' end)
    returning id into T1;   -- 임시 담기
    insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base) values (o,'GA','GA',1,10,10) returning id into l1;
    insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base) values (o,'GB','GB',1,5,5)  returning id into l2;
    insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base, picked_base, status, verification_method)
    values (T1,l1,10,3,'in_progress','scanned_base'), (T1,l2,5,0,'pending',null);
    case i when 1 then T1:=T1; when 2 then T2:=T1; when 3 then T3:=T1; when 4 then T4:=T1; when 5 then T5:=T1;
           when 6 then T6:=T1; when 7 then T7:=T1; when 8 then T8:=T1; when 9 then T9:=T1; end case;
  end loop;
  select id into T1 from wms_pick_tasks where batch_label='SO-GUARD-T1-1';

  select count(*) into disc_before from wms_discrepancies;
  select coalesce(sum(picked_base),0) into picked_before from wms_pick_task_lines
   where pick_task_id in (T1,T2,T3,T4,T5);

  -- ── 케이스 1: 픽 완료 ─────────────────────────────────────────────────────────
  -- T1: p_session_id 생략(옛 HTML · DB 만 먼저 나간 배포 창) → 종전 동작
  res := wms_complete_pick(pg_temp.pick_lines(T1), T1, null, pg_temp.pick_disc(T1), '[]', '[]');
  if res->>'completed' <> 'true' then raise exception 'FAIL 1-T1 생략: %', res; end if;
  select string_agg(picked_base::text||'/'||status, ',' order by id) into t from wms_pick_task_lines where pick_task_id=T1;
  if t <> '10/picked,3/short' then raise exception 'FAIL 1-T1 lines: %', t; end if;
  select count(*) into n from wms_discrepancies where pick_task_id=T1 and reason='short_pick';
  if n <> 1 then raise exception 'FAIL 1-T1 short_pick=%', n; end if;
  -- T2: 행 S1 · p S1 → 성공
  res := wms_complete_pick(pg_temp.pick_lines(T2), T2, null, pg_temp.pick_disc(T2), '[]', '[]', 'S1');
  if res->>'completed' <> 'true' then raise exception 'FAIL 1-T2 일치: %', res; end if;
  -- T3: 행 S1 · p S2 (다른 기기) → 0행 · reason other_device · 라인·discrepancy·status 무변
  res := wms_complete_pick(pg_temp.pick_lines(T3), T3, null, pg_temp.pick_disc(T3), '[]', '[]', 'S2');
  if res->>'completed' <> 'false' or res->>'reason' <> 'other_device' or res->>'worker' <> v_tester then
    raise exception 'FAIL 1-T3 불일치: %', res; end if;
  select string_agg(picked_base::text||'/'||status, ',' order by id) into t from wms_pick_task_lines where pick_task_id=T3;
  if t <> '3/in_progress,0/pending' then raise exception 'FAIL 1-T3 라인이 변했다: %', t; end if;
  select count(*) into n from wms_discrepancies where pick_task_id=T3; if n <> 0 then raise exception 'FAIL 1-T3 disc=%', n; end if;
  select status into t from wms_pick_tasks where id=T3; if t <> 'in_progress' then raise exception 'FAIL 1-T3 status=%', t; end if;
  -- T4: 행 null(배포 전 클레임) · p S2 → 레거시 통과
  res := wms_complete_pick(pg_temp.pick_lines(T4), T4, null, pg_temp.pick_disc(T4), '[]', '[]', 'S2');
  if res->>'completed' <> 'true' then raise exception 'FAIL 1-T4 레거시: %', res; end if;
  -- T5: assigned_to 남 · p S1 → 0행 · reason null (종전 분기)
  res := wms_complete_pick(pg_temp.pick_lines(T5), T5, null, pg_temp.pick_disc(T5), '[]', '[]', 'S1');
  if res->>'completed' <> 'false' or not (res ? 'reason') or res->>'reason' is not null then
    raise exception 'FAIL 1-T5 남의 배치: %', res; end if;
  -- 집계: 성공 3건(T1·T2·T4) → discrepancy +3 · picked_base 합 +30 (각 3+0 → 10+3 = +10)
  select count(*) - disc_before into n from wms_discrepancies;
  if n <> 3 then raise exception 'FAIL 1-agg disc delta=%', n; end if;
  select coalesce(sum(picked_base),0) - picked_before into picked_before from wms_pick_task_lines where pick_task_id in (T1,T2,T3,T4,T5);
  if picked_before <> 30 then raise exception 'FAIL 1-agg picked delta=%', picked_before; end if;
  raise notice 'PASS 1: 픽 완료 — 생략 회귀 · 일치 · 불일치(other_device·무변) · 레거시 null · 남(reason null) · 집계 +3/+30';

  -- ── 케이스 2: 픽 Hold ────────────────────────────────────────────────────────
  res := wms_hold_pick(pg_temp.hold_lines(T6), T6, null);                 -- 생략
  if res->>'held' <> 'true' then raise exception 'FAIL 2-T6 생략: %', res; end if;
  res := wms_hold_pick(pg_temp.hold_lines(T7), T7, null, 'S2');           -- 불일치
  if res->>'held' <> 'false' or res->>'reason' <> 'other_device' then raise exception 'FAIL 2-T7 불일치: %', res; end if;
  res := wms_hold_pick(pg_temp.hold_lines(T8), T8, null, 'S2');           -- 레거시 null
  if res->>'held' <> 'true' then raise exception 'FAIL 2-T8 레거시: %', res; end if;
  res := wms_hold_pick(pg_temp.hold_lines(T9), T9, null, 'S1');           -- 남
  if res->>'held' <> 'false' or res->>'reason' is not null then raise exception 'FAIL 2-T9 남: %', res; end if;
  select string_agg(status||':'||coalesce(held_by,'-'), ',' order by id) into t from wms_pick_tasks where id in (T6,T7,T8,T9);
  if t <> format('pending:%s,in_progress:-,pending:%s,in_progress:-', v_tester, v_tester) then raise exception 'FAIL 2 states: %', t; end if;
  select count(*) into n from wms_task_holds where task_kind='pick' and task_id in (T6,T8); if n <> 2 then raise exception 'FAIL 2 holds(T6,T8)=%', n; end if;
  select count(*) into n from wms_task_holds where task_kind='pick' and task_id in (T7,T9); if n <> 0 then raise exception 'FAIL 2 holds(T7,T9)=%', n; end if;
  select string_agg(picked_base::text, ',' order by id) into t from wms_pick_task_lines where pick_task_id=T7;
  if t <> '3,0' then raise exception 'FAIL 2-T7 라인이 변했다: %', t; end if;
  raise notice 'PASS 2: 픽 Hold — 생략·불일치(other_device·무변)·레거시·남';

  -- ── 케이스 3: wave — CAS 는 wave 행 · 멤버는 세션 조건 없음 ─────────────────────
  insert into wms_waves (label, warehouse, status, assigned_to, session_id) values ('WAVE-GUARD-1','toronto','in_progress',v_tester,'S1') returning id into W1;
  for i in 1..2 loop
    insert into wms_orders (cin7_sale_id, order_number, status, warehouse) values ('GUARD-W'||i, 'SO-GUARD-W'||i, 'picking', 'toronto') returning id into o;
    insert into wms_pick_tasks (order_id, batch_label, assigned_to, status, wave_id, tote_no, session_id)
    values (o, 'SO-GUARD-W'||i||'-1', v_tester, 'in_progress', W1, i, null) returning id into WM1;   -- 멤버 session_id null(레거시 wave 모양)
    insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base) values (o,'GW','GW',1,4,4) returning id into l1;
    insert into wms_pick_task_lines (pick_task_id, order_line_id, assigned_base, picked_base, status) values (WM1,l1,4,4,'picked');
    if i=2 then WM2:=WM1; end if;
  end loop;
  select id into WM1 from wms_pick_tasks where batch_label='SO-GUARD-W1-1';
  res := wms_complete_pick(pg_temp.wave_lines(W1), null, W1, '[]', '[]', '[]', 'S2');
  if res->>'completed' <> 'false' or res->>'reason' <> 'other_device' then raise exception 'FAIL 3-W1 불일치: %', res; end if;
  select count(*) into n from wms_pick_tasks where wave_id=W1 and status='in_progress'; if n <> 2 then raise exception 'FAIL 3-W1 멤버가 변했다: %', n; end if;
  res := wms_complete_pick(pg_temp.wave_lines(W1), null, W1, '[]', '[]', '[]', 'S1');
  if res->>'completed' <> 'true' or (res->>'members_completed')::int <> 2 then raise exception 'FAIL 3-W1 일치: %', res; end if;
  raise notice 'PASS 3: wave — 불일치 0행(멤버 무변) · 일치 members_completed 2 (멤버 session_id null 이어도 통과)';

  -- ── 케이스 4·5: 팩 완료 · Hold ───────────────────────────────────────────────
  for i in 1..8 loop
    insert into wms_orders (cin7_sale_id, order_number, status, warehouse) values ('GUARD-P'||i, 'SO-GUARD-P'||i, 'packing', 'toronto') returning id into o;
    insert into wms_pick_tasks (order_id, batch_label, assigned_to, status) values (o, 'SO-GUARD-P'||i||'-1', 'Picker Kim', 'completed') returning id into l1;
    insert into wms_pack_tasks (order_id, pick_task_id, batch_label, assigned_to, status, session_id)
    values (o, l1, 'SO-GUARD-P'||i||'-1', case when i=5 then 'Other Worker' else v_tester end, 'in_progress',
            case when i in (1,4,6,8) then null else 'S1' end) returning id into P1;
    insert into wms_order_lines (order_id, order_sku, base_sku, factor, ordered_qty, required_base) values (o,'GP','GP',1,10,10) returning id into l2;
    insert into wms_pack_task_lines (pack_task_id, order_line_id, expected_base, verified_base, status, verification_method) values (P1,l2,10,4,'in_progress','scanned_base');
    case i when 1 then P1:=P1; when 2 then P2:=P1; when 3 then P3:=P1; when 4 then P4:=P1; when 5 then P5:=P1; when 6 then P6:=P1; when 7 then P7:=P1; when 8 then P8:=P1; end case;
  end loop;
  select id into P1 from wms_pack_tasks where batch_label='SO-GUARD-P1-1';

  res := wms_complete_pack(P1, pg_temp.pack_lines(P1), '[]', '[]', '[]', '[]');            -- 생략
  if res->>'completed' <> 'true' then raise exception 'FAIL 4-P1 생략: %', res; end if;
  res := wms_complete_pack(P2, pg_temp.pack_lines(P2), '[]', '[]', '[]', '[]', 'S1');      -- 일치
  if res->>'completed' <> 'true' then raise exception 'FAIL 4-P2 일치: %', res; end if;
  res := wms_complete_pack(P3, pg_temp.pack_lines(P3), '[]', '[]', '[]', '[]', 'S2');      -- 불일치
  if res->>'completed' <> 'false' or res->>'reason' <> 'other_device' then raise exception 'FAIL 4-P3 불일치: %', res; end if;
  select verified_base::text||'/'||status into t from wms_pack_task_lines where pack_task_id=P3;
  if t <> '4/in_progress' then raise exception 'FAIL 4-P3 라인이 변했다: %', t; end if;
  select status into t from wms_pack_tasks where id=P3; if t <> 'in_progress' then raise exception 'FAIL 4-P3 status=%', t; end if;
  res := wms_complete_pack(P4, pg_temp.pack_lines(P4), '[]', '[]', '[]', '[]', 'S2');      -- 레거시 null
  if res->>'completed' <> 'true' then raise exception 'FAIL 4-P4 레거시: %', res; end if;
  res := wms_complete_pack(P5, pg_temp.pack_lines(P5), '[]', '[]', '[]', '[]', 'S1');      -- 남
  if res->>'completed' <> 'false' or res->>'reason' is not null then raise exception 'FAIL 4-P5 남: %', res; end if;
  raise notice 'PASS 4: 팩 완료 — 생략·일치·불일치(other_device·verified 4 무변)·레거시·남';

  res := wms_hold_pack(P6, pg_temp.pack_hold_lines(P6));             if res->>'held' <> 'true'  then raise exception 'FAIL 5-P6 생략: %', res; end if;
  res := wms_hold_pack(P7, pg_temp.pack_hold_lines(P7), 'S2');       if res->>'held' <> 'false' or res->>'reason' <> 'other_device' then raise exception 'FAIL 5-P7 불일치: %', res; end if;
  res := wms_hold_pack(P8, pg_temp.pack_hold_lines(P8), 'S2');       if res->>'held' <> 'true'  then raise exception 'FAIL 5-P8 레거시: %', res; end if;
  select string_agg(status, ',' order by id) into t from wms_pack_tasks where id in (P6,P7,P8);
  if t <> 'pending,in_progress,pending' then raise exception 'FAIL 5 states: %', t; end if;
  raise notice 'PASS 5: 팩 Hold — 생략·불일치(other_device)·레거시';

  -- ── 케이스 6: 「새 화면이 이긴다」 — T3 를 새 화면 S2 가 클레임(claimSession 과 같은 UPDATE) 후 완료 ──
  update wms_pick_tasks set session_id='S2' where id=T3 and assigned_to=v_tester and status='in_progress';
  get diagnostics n = row_count; if n <> 1 then raise exception 'FAIL 6 claim rows=%', n; end if;
  res := wms_complete_pick(pg_temp.pick_lines(T3), T3, null, pg_temp.pick_disc(T3), '[]', '[]', 'S2');
  if res->>'completed' <> 'true' then raise exception 'FAIL 6 새 화면 완료: %', res; end if;
  -- 옛 화면 S1 이 그 뒤 Hold 를 눌러도 (이미 completed) 0행 · reason null (other_device 는 in_progress 일 때만)
  res := wms_hold_pick(pg_temp.hold_lines(T3), T3, null, 'S1');
  if res->>'held' <> 'false' or res->>'reason' is not null then raise exception 'FAIL 6 옛 화면 Hold: %', res; end if;
  raise notice 'PASS 6: 새 화면 클레임 → 완료 성공 · 옛 화면은 0행';

  raise notice 'SESSION GUARD: ALL CHECKS PASSED';
end
$chk$;

rollback;
