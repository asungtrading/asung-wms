-- wms_pause_receipt 로컬 기능 테스트 (2026-08-25 · 리시빙 Hold·partial 기록 — 마이그레이션 20260825203457)
--
-- 실행 (로컬 supabase — 프로덕션 금지):
--   supabase db reset
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/wms_pause_receipt_test.sql
--
-- 전체가 한 트랜잭션 + 마지막 ROLLBACK — 로컬 DB 에 무흔적.
-- 전부 통과하면 마지막 NOTICE 가 "ALL 7 TESTS PASSED".

begin;

do $test$
declare
  r1 bigint; r2 bigint;
  res jsonb;
  n int; t text;
  errmsg text;
begin
  -- ── 셋업 ────────────────────────────────────────────────────────────
  perform set_config('request.jwt.claims', '{"email":"rpc-test@asung.ca"}', false);
  insert into wms_staff (name, email, role, warehouse_access, active)
  values ('RPC Tester', 'rpc-test@asung.ca', 'worker', 'both', true);
  insert into wms_receipts (po_number, cin7_purchase_id, warehouse, status, received_by, source_type)
  values ('PO-TEST-PZ-1', 'cin7-pz-1', 'toronto', 'in_progress', 'RPC Tester', 'po') returning id into r1;
  insert into wms_receipts (po_number, cin7_purchase_id, warehouse, status, received_by, source_type)
  values ('TR-TEST-PZ-2', 'cin7-pz-2', 'toronto', 'in_progress', 'RPC Tester', 'transfer') returning id into r2;

  -- ── ⓐ held: 플립 + 이력(source=manual · worker 서버 유도) ─────────────
  res := wms_pause_receipt(r1, 'held');
  if res->>'paused' <> 'true' then raise exception 'FAIL a1: %', res; end if;
  select status into t from wms_receipts where id=r1;
  if t <> 'held' then raise exception 'FAIL a2: status=%', t; end if;
  select count(*) into n from wms_task_holds
   where task_kind='receipt' and task_id=r1 and worker='RPC Tester' and source='manual' and resumed_at is null;
  if n <> 1 then raise exception 'FAIL a3: history rows=%', n; end if;
  raise notice 'PASS a — held (플립+이력 manual · 서버 유도)';

  -- ── ⓑ 이중 pause 차단: held 상태에서 재 pause = CAS 0행 무기록 ────────
  res := wms_pause_receipt(r1, 'partial');
  if res->>'paused' <> 'false' then raise exception 'FAIL b1: %', res; end if;
  select count(*) into n from wms_task_holds where task_kind='receipt' and task_id=r1;
  if n <> 1 then raise exception 'FAIL b2: duplicate history (%)', n; end if;
  raise notice 'PASS b — 이중 pause 차단 (CAS 0행 · 무기록)';

  -- ── ⓒ resume — 기존 RPC 재사용 (서버 시계 · resumed_by 서버 유도) ─────
  update wms_receipts set status='in_progress' where id=r1;   -- 프론트 재개 흉내 (openReceipt :785)
  n := wms_resume_hold('receipt', r1);
  if n <> 1 then raise exception 'FAIL c1: resume closed % rows', n; end if;
  select count(*) into n from wms_task_holds
   where task_kind='receipt' and task_id=r1 and resumed_at is not null and resumed_at >= held_at and resumed_by='RPC Tester';
  if n <> 1 then raise exception 'FAIL c2: resumed_at/by wrong'; end if;
  raise notice 'PASS c — resume (wms_resume_hold 재사용 · 서버 시계)';

  -- ── ⓓ partial: 트랜스퍼 receipt 에서 (같은 테이블 — 자동 포함 확인) ───
  res := wms_pause_receipt(r2, 'partial');
  if res->>'paused' <> 'true' or res->>'reason' <> 'partial' then raise exception 'FAIL d1: %', res; end if;
  select status into t from wms_receipts where id=r2;
  if t <> 'partial' then raise exception 'FAIL d2: status=%', t; end if;
  select source into t from wms_task_holds where task_kind='receipt' and task_id=r2 and resumed_at is null;
  if t <> 'partial' then raise exception 'FAIL d3: source=%', t; end if;
  raise notice 'PASS d — partial (source=partial · transfer receipt 동일 동작)';

  -- ── ⓔ 완료가 열린 이력을 닫는 흐름 (A Hold → B 완료 엣지의 서버 반쪽) ──
  -- 프론트 finishReceipt 는 completed patch 후 wms_resume_hold 를 부른다 — 그 결과를 흉내
  update wms_receipts set status='completed', completed_at=now() where id=r2;
  n := wms_resume_hold('receipt', r2);
  if n <> 1 then raise exception 'FAIL e1: complete-close closed % rows', n; end if;
  raise notice 'PASS e — 완료 시 닫기 (hold 종점 = 완료 시각)';

  -- ── ⓕ hold_leak — receipt 판 4갈래 ────────────────────────────────────
  -- 정상(held + 열린 행) = 0
  insert into wms_receipts (po_number, cin7_purchase_id, warehouse, status, received_by, source_type)
  values ('PO-TEST-PZ-3', 'cin7-pz-3', 'toronto', 'in_progress', 'RPC Tester', 'po') returning id into r1;
  res := wms_pause_receipt(r1, 'held');
  select fail_count into n from wms_health_check() where check_key='hold_leak';
  if n <> 0 then raise exception 'FAIL f1: normal held flagged (%)', n; end if;
  -- 유실(in_progress 인데 열린 행) = 1
  update wms_receipts set status='in_progress' where id=r1;   -- 재개했는데 닫기 유실 흉내
  select fail_count into n from wms_health_check() where check_key='hold_leak';
  if n <> 1 then raise exception 'FAIL f2: lost close not flagged (%)', n; end if;
  -- 삭제된 receipt = 0 (admin delete 경로 — rollback/void 관례)
  delete from wms_receipt_lines where receipt_id=r1;
  delete from wms_receipts where id=r1;
  select fail_count into n from wms_health_check() where check_key='hold_leak';
  if n <> 0 then raise exception 'FAIL f3: deleted receipt flagged (%)', n; end if;
  -- 이중 open = 1 (receipt 부재여도 rn>1 은 잡음)
  insert into wms_task_holds (task_kind, task_id, worker, source) values ('receipt', 999777, 'A', 'manual');
  insert into wms_task_holds (task_kind, task_id, worker, source) values ('receipt', 999777, 'A', 'manual');
  select fail_count into n from wms_health_check() where check_key='hold_leak';
  if n <> 1 then raise exception 'FAIL f4: double-open not flagged (%)', n; end if;
  raise notice 'PASS f — hold_leak receipt 판 (정상 0 · 유실 1 · 삭제 0 · 이중 1)';

  -- ── ⓖ 가드: 잘못된 reason · 미등록 로그인 ────────────────────────────
  begin
    res := wms_pause_receipt(r2, 'paused');
    raise exception 'FAIL g1: no exception (bad reason)';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('held or partial' in errmsg) = 0 then raise exception 'FAIL g2: %', errmsg; end if;
  end;
  perform set_config('request.jwt.claims', '{"email":"nobody@asung.ca"}', false);
  begin
    res := wms_pause_receipt(r2, 'held');
    raise exception 'FAIL g3: no exception (no staff)';
  exception when others then
    errmsg := sqlerrm;
    if errmsg like 'FAIL%' then raise; end if;
    if position('No staff record' in errmsg) = 0 then raise exception 'FAIL g4: %', errmsg; end if;
  end;
  raise notice 'PASS g — reason·로그인 가드';

  raise notice '════ ALL 7 TESTS PASSED ════';
end
$test$;

rollback;
