-- 비재고 SKU 게이트 (2026-08-24) — inv_sku_types 캐시 + inv_ledger CHECK 확장 2건
--
-- 배경 [실사고 FINAL-SALE]: ⑥ 첫 shadow 대조의 unknown 1건 — Cin7 `Type=Non-inventory` 품목
-- (파손품을 adjustment 로 이미 뺀 뒤 판매할 때 쓰는 껍데기 SKU · Cin7 은 재고를 안 움직인다)의
-- 판매를 수집이 재고 사건으로 잡아 -34 를 쌓았다. 기존 `IsServiceOnly` 필터의 틈 —
-- IsService(서비스: 팔되 실물 없음)와 Type=Non-inventory(재고 추적 안 함)는 **다른 축**이다
-- (cin7-api 스킬 15번 · FINAL-SALE 은 IsService=false).
--
-- 처방 (2026-08-24 사용자 확정):
--  · 상수로 박지 않는다 — [실측] 비재고 2개(FINAL-SALE·AS91437-BLK) + SERVICE 3개
--    (OrderTotalDiscount·AMZ00101·AMZ00102)로 지금은 작지만, 상품이 늘면 코드 배포가 필요해지고
--    새 비재고 SKU 는 대조에서 unknown 이 날 때까지 모른다(오늘이 그 사례).
--  · 캐시 갱신 = 별도 EF `inv-sku-types`(pg_cron 일 1회) — inv-collect 안에 두면 6잡이 각자
--    갱신을 시도하고 소스별 회차가 서로의 캐시 상태에 의존한다. 별도 EF 는 실패가 격리된다.
--  · 게이트(inv-collect makeSink)는 fail-open — 캐시가 비어도 수집은 통과 + warnings.
--    원장은 shadow 이고 대조가 안전망이다(잘못 들어와도 unknown 으로 잡힌다 — FINAL-SALE 이 그 경로).
--
-- 이 파일: ① inv_sku_types(차단 대상 = 비-Stock 타입만 — 현재 5행. "재고 품목인가"는 목록 부재 =
-- Stock 으로 답한다. 전 SKU 저장은 필요해지면 확장) ② source CHECK + 'manual'(상쇄 행의 출처 —
-- Cin7 문서가 아니라 사람의 판단) ③ event_type CHECK + 'manual_reversal'(append-only 의 정정 수단
-- — 물리 삭제 금지. 설계 4부 3번 "정석 = 역분개"의 첫 실사용).
-- ⚠️ 배포 순서: 이 SQL(db push — Caleb) → EF 2개 배포 → 캐시 1회 수동 실행 → dry 확인 →
-- **그다음에** 상쇄 행 INSERT(먼저 넣으면 다음 수집에서 -34 가 또 들어온다).

-- ─────────────────────────────────────────────────────────
-- 1) inv_sku_types — 재고를 움직이지 않는 SKU 캐시 (비-Stock 타입만)
--
-- ⚠️⚠️ 저장 범위 계약: 이 테이블에는 **Type ≠ 'Stock' 인 SKU 만** 넣는다 (EF inv-sku-types 가
--   그렇게만 쓴다 · [실측 2026-08-24] 49행 = Non-inventory + Service). 소비자(inv-collect 게이트
--   로드 · inv-sku-types 의 diff 조회)가 이 계약을 근거로 **무페이지 단일 조회**를 쓴다 —
--   ⚠️ 여기에 Stock 품목(1.4만+)을 넣으면 PostgREST 1,000행 캡에서 조용히 잘리고, 잘린 뒤의
--   비재고 SKU 가 게이트를 통과한다(규칙 20 캡 함정 계열). 전 SKU 저장으로 바꾸려면 소비자
--   조회를 range 페이지네이션으로 먼저 바꿀 것. 게이트 로드에 800행 근접 경보가 있다.
-- ─────────────────────────────────────────────────────────
create table inv_sku_types (
  sku          text primary key,
  product_type text not null,          -- Cin7 product Type 원문 그대로 (외부 원문 — CHECK 없음)
  is_service   boolean,                -- 개념 구분 기록용 (IsService ≠ Non-inventory)
  refreshed_at timestamptz not null default now()
);
alter table inv_sku_types enable row level security;
create policy auth_all on inv_sku_types for all to authenticated using (true) with check (true);
revoke all on inv_sku_types from anon;

-- ─────────────────────────────────────────────────────────
-- 2) inv_ledger.source: + 'manual' (사람의 판단으로 넣는 행 — 상쇄 등)
-- 3) inv_ledger.event_type: + 'manual_reversal'
-- ─────────────────────────────────────────────────────────
alter table inv_ledger drop constraint inv_ledger_source_check;
alter table inv_ledger add constraint inv_ledger_source_check
  check (source in ('cin7', 'wms', 'manual'));

alter table inv_ledger drop constraint inv_ledger_event_type_check;
alter table inv_ledger add constraint inv_ledger_event_type_check
  check (event_type in (
    'sale_out',         -- 판매 출고 (−)
    'credit_in',        -- 반품 입고 (+)
    'po_in',            -- 발주 입고 (+)
    'transfer_out',     -- 창고이동 출발 (−)
    'transfer_in',      -- 창고이동 도착 (+)
    'adjust_existing',  -- 조정 · 기존 재고 (목표수량 − 당시수량)
    'adjust_new',       -- 조정 · 신규 재고 (+)
    'assemble_in',      -- 조립 완제품 (+)
    'assemble_out',     -- 조립 구성품 (−)
    'manual_reversal'   -- 사람의 상쇄 행 (append-only 정정 — source='manual' 과 짝)
  ));
