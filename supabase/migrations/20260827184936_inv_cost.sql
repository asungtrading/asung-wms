-- 원가(landed cost) — inv_cost (2026-08-27)
--
-- ⚠️ 이 테이블은 **원장이 아니다.** 조사·설계 정본은
--    docs/sessions/2026-08-27-landed-cost-investigation.md 다. 다시 조사하지 말 것.
--
-- 무엇인가: Cin7 이 계산한 COGS 를 우리 원장 행 단위(bin·CardID)로 나눠 담는다.
--   Cin7 은 InventoryMovements 에 「제품 × 날짜 × COGS」만 준다(수량도 SKU 도 bin 도 없다).
--   SR 로 수량을 얻고 PutAway 로 bin·CardID 를 얻어 원장 line_ref 와 잇는다.
--
-- ⚠️⚠️ **원장(inv_ledger)과 달리 append-only 가 아니다 — upsert 로 덮어쓴다.**
--   근거: 원장은 「우리가 만든 사건」이라 상쇄로만 고치지만, 이 테이블은 Cin7 의 계산 결과를
--   베낀 것이고 언제든 다시 가져올 수 있다. 다시 만들 수 있는 것에 append-only 의 부담을
--   질 이유가 없다. [실측] Cin7 은 재평가로 값을 바꾼다(+A, −A, +B 세 행) — append 로 담으면
--   TR-04175(2026-08-25 라인 소멸)와 같은 이중 계상 문제가 그대로 재현된다.
--   ⇒ 경계: 우리가 만든 사건 = 상쇄 / Cin7 을 베낀 것 = 덮어쓰기(inv_snapshot·inv_compare 와 동형).
--   📌 하드 플립 시점의 값이 원가의 기초가 된다(inv_snapshot 이 수량에 한 역할과 같다).
--      그 이후에는 우리가 계산해 쌓는다 — 그때는 append 가 맞다.
--
-- ⚠️ amount 는 **순액**이다. 같은 (제품·날짜)에 IM 행이 여럿일 수 있고(재평가 상쇄),
--   합산해야 최종값이 나온다. [실측 PO-00005] +2173.366080 / −2173.366080 / +2173.366402.
-- ⚠️ ref(service 인보이스 번호)는 키에 넣지 않는다 — 비용이 **날짜별로 합쳐져** 오기 때문이다.
--   [실측 PO-00005] MJ 사용자 6줄(ref 2종) 합 4,291.30 = IM 11/03 합. raw 에만 남긴다.
-- ⚠️ 배분 기준은 **금액 비례**다(수량·무게 아님). 분모 = Invoice.Lines 총합(AdditionalCharges 전).
-- ⚠️ 환율은 **Invoice[].CurrencyRate** 다 — 헤더 CurrencyRate 가 아니다(회차별로 갈린다).
-- ⚠️ Simple Purchase 경로는 **미검증**이다. 실물이 거의 없어 표본을 못 구했다(2026-08-27).
--   수량 수집처럼 Type 으로 분기하되(Advanced=PutAway / Simple=StockReceived) Simple 은
--   생기면 그때 확인한다.
--
-- 조회: select * from inv_cost where doc_number='PO-00853' order by occurred_on, sku;

create table inv_cost (
  id             bigint generated always as identity primary key,

  -- 원장 연결 축 (inv_ledger 유니크 키와 같은 구성 · line_ref = PutAway 의 CardID)
  doc_type       text        not null,
  doc_number     text        not null,
  line_ref       text        not null,
  sku            text        not null,
  warehouse      text        not null,
  bin            text        not null default '',   -- ⚠️ 부분 유니크 인덱스 금지 → 키 컬럼 전부 not null

  occurred_on    date        not null,   -- Cin7 이 준 날짜 그대로(입고일 또는 비용 발생일).
                                         -- ⚠️ 비용은 입고보다 앞설 수 있다(인보이스 날짜로 소급).
  cost_kind      text        not null,   -- 'goods' | 'landed'
                                         -- ⚠️ 합치지 말 것 — 합치면 되돌릴 수 없다.

  qty            numeric     not null,   -- PutAway 라인 수량
  amount         numeric     not null,   -- 배분된 CAD 순액
  unit_cost      numeric     not null,   -- amount / qty (0 나눗셈은 EF 가 막는다)

  -- 배분 전 원본 (goods 만) — ⚠️ 환산 결과만 담으면 검증도 재계산도 불가능하다
  currency_orig  text,
  amount_orig    numeric,
  fx_rate        numeric,

  collector      text        not null,
  refreshed_at   timestamptz not null default now(),
  raw            jsonb                   -- IM 원본 행 · MJ 줄(ref 포함) · 배분 근거
);

create unique index inv_cost_uq on inv_cost
  (doc_type, doc_number, line_ref, warehouse, bin, sku, cost_kind, occurred_on);
create index inv_cost_doc_idx  on inv_cost (doc_type, doc_number);
create index inv_cost_sku_idx  on inv_cost (sku, occurred_on);

alter table inv_cost add constraint inv_cost_kind_ck
  check (cost_kind in ('goods', 'landed'));

-- RLS — inv_conflicts·inv_missing_lines 와 동일. 쓰기 주체는 EF(service_role · RLS 우회).
-- ⚠️ DELETE/TRUNCATE 는 회수하지 않는다 — 이 테이블은 재수집으로 다시 만들 수 있다
--    (inv_missing_lines·inv_snapshot_runs 와 다른 점: 그쪽은 재생성 불가능한 증거다).
alter table inv_cost enable row level security;
create policy auth_all on inv_cost for all to authenticated using (true) with check (true);
revoke all on inv_cost from anon;
