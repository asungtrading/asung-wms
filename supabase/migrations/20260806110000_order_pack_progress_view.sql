-- wms_order_pack_progress — 분할 오더 팩 완료 판정 뷰 (2026-08-06, 규칙 9 fulfillment 게이트)
--
-- 현장 사고: 분할 오더 일부만 팩이 끝난 상태에서 fulfillment 가 진행돼 분할이 누락된다.
-- 화면 표시는 아무도 안 읽는다(SO-14129 와 같은 실패 양식) → 전부 팩 완료 전에는 보드에서 숨긴다.
-- 규칙: 전부 아니면 전무 — 5분할 중 1개만 미완이어도 5개 전부 숨고, 마지막이 끝나는 순간 함께 나타난다.
--
-- ⚠️ 분모 = 픽 배치 수 (2026-08-06 실측 SO-14188: pick 2 · pack 1 · done 1 —
--    팩 태스크 수로 세면 1/1=완료로 오판한다. 이게 기존 누락의 메커니즘이었다).
-- ⚠️ wms_orders.status(ready_to_close)를 쓰지 않는 이유: 전이 발동 의존 — 응답 유실로 전이가
--    안 되는 경로가 실재한다. 사실 계산은 자동 복구된다(롤백이 pack_tasks 를 지우면 카운트가
--    줄어 스스로 숨고, 전이가 늦어도 팩이 끝나면 나타난다).
-- ⚠️ 판정은 이 뷰 한 곳뿐이어야 한다 — 소비 지점: fulfillment 보드 필터 · 스캔 안내 토스트 ·
--    Finalize 직전 재확인 · admin Status 표시. 나중에 예외(매니저 강제 출고 등)가 생기면
--    아래 all_packed 식 한 줄만 고친다. 예외 컬럼은 미리 만들지 않는다(사용자 결정 2026-08-06).
--
-- security_invoker: 뷰 조회에 베이스 테이블 RLS(auth_all — 로그인 필수)가 그대로 적용된다.
-- pick_batches = 0 인 오더는 뷰에 행이 없다(pick_tasks inner 기준) — 소비자는 "행 없음 = 미자격"
-- 으로 다뤄야 한다(fail-closed).

create or replace view public.wms_order_pack_progress
  with (security_invoker = true) as
select
  pt.order_id,
  count(pt.id)::int as pick_batches,
  (count(distinct pk.pick_task_id) filter (where pk.status = 'completed'))::int as packs_done,
  count(pt.id) > 0
    and count(pt.id) = count(distinct pk.pick_task_id) filter (where pk.status = 'completed')
    as all_packed
from public.wms_pick_tasks pt
left join public.wms_pack_tasks pk on pk.pick_task_id = pt.id
group by pt.order_id;

-- ⚠️ GRANT 가 빠지면 PostgREST 조회가 permission denied 로 떨어져 fulfillment 보드가 전부 빈다.
--    (프론트는 이 실패를 명시적 오류 상태로 표시하지만, 그래도 일은 멈춘다.)
grant select on public.wms_order_pack_progress to authenticated, anon;

comment on view public.wms_order_pack_progress is
  'per-order pack progress: denominator = pick batches (NOT pack tasks - SO-14188). all_packed gates the fulfillment board (rule 9)';
