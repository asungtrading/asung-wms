-- ─────────────────────────────────────────────────────────────
-- ⑤ PO 본체 ②차 — 인보이스 · 비용 · 결제 (테스트 DB Asung-IMS · 2026-09-16)
--   po_invoice · po_invoice_line · po_invoice_discount · po_charge · po_charge_alloc · po_payment · po_payment_alloc
--
-- 정본: docs/design/po-module.md §11-f(비용) · §11-g(인보이스) · §11-h(결제) · §11-e(할인) · §3-b D·②③⑤(할인·인보이스 실물) · §7
-- 앞 차수: 20260916144201_po.sql (po · po_line · po_discount · po_receipt_line · 2026-09-16 적용·검증 ✅ · 커밋 8a27edd)
-- 지시서: ~/asung/prompts/po-tables-2.md · 검토 이견 ⬜1~⬜6 · 7~15 (2026-09-16 · 11 은 「closed = 입고 종료」로 · 12 는 is_payable 채택)
--
-- ⭐ ①차의 판단을 그대로 잇는다 — 거래 표 규약 · 파일 하나 · 잠금 트리거 없음 · 컷오버 때 지운다.
--    물려받음  id uuid PK · note · created_at/updated_at + set_updated_at 트리거 · RLS auth_all + revoke anon · <표>_*_ck 이름 · FK 인덱스 <표>_<칸>_idx
--    뺌        cin7_id · source · is_active · name (거래 표 · ①차 이견 2)
--    FK        문서 → 소유 줄은 on delete cascade(po_invoice→line·discount · po_charge→alloc · po_payment→alloc) · 밖을 가리키는 FK 는 전부 no action
--    권한      DELETE 는 막지 않는다(초안은 지운다 · 확정 뒤는 취소로) · TRUNCATE 는 막는다
--    ⚠️⚠️ 확정 문서는 지금 DB 가 보호하지 않는다(①차와 같다) — 화면이 감추는 것은 막는 것이 아니다. ⬜ 잠금 트리거는 분할 함수 차수에 예외 경로와 함께.
--    ⚠️⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라 · 부분 유니크 인덱스 금지(PostgREST on_conflict).
--
-- ⭐⭐ 컷오버 축(§11-⓪) — 이 일곱은 전부 **거래**다 ⇒ 컷오버 때 지운다. 마스터(supplier · product · ref_* · ims_staff)는 남는다.
--
-- ⭐ 이번 차수의 판단 요약
--   인보이스는 줄 수준으로 잇는다(Caleb 2026-09-16) — po_invoice_line.po_line_id. 인보이스가 PO 여럿에 걸치는 것은 줄이 알아서 갈린다.
--     ⇒ 머리에 「걸린 PO 들」 칸을 두지 않는다 — 조인(po_invoice_line → po_line → po)으로 충분 · 칸을 두면 줄이 바뀔 때 어긋난다(①차 received_qty 와 같은 이유).
--   ⭐ 할인은 두 층이다(이견 3) — po_discount(①차) = 발주를 만들 때 「이렇게 될 것이다」로 제안받은 **예상** · po_invoice_discount(이번) = 공급처가 인보이스에 적어 보낸 **확정**.
--     원가 배분의 정본은 인보이스 할인(§11-g ① · §3-b ③ 「할인 줄은 어느 인보이스에 속하는지 알아야 한다」). §11-e 「문서 위에 선다」는 그대로 — 「어느 문서」가 둘.
--   비용(po_charge)은 줄 없는 문서 → po_charge_alloc(이 발주에 얼마) → 라인은 계산(§11-e 규칙 · 금액 비례 · 잔돈은 금액이 가장 큰 줄 · 동점은 SKU 순).
--     ⭐⭐ 배분 금액은 넣을 때 계산해 **박아 두고, 나중에 발주 금액이 바뀌어도 다시 계산하지 않는다**(Caleb 2026-09-16). 고치려면 사람이 고친다. 아래 po_charge_alloc 주석.
--     비용 문서는 제품을 참조하지 않는다 — Type=Service 53 은 ③ product 에 없고(범위 Type=Stock) 넣을 이유도 없다. kind CHECK + description 으로 간다.
--   ⭐ closed 의 뜻은 **입고 종료**다(Caleb 2026-09-16). 비용은 그 뒤에 붙는다 — po_charge_alloc 은 po.status 와 무관하게 붙는다(제약 없음).
--     근거: 「비용까지 붙어야 닫는다」로 하면 비용이 안 오는 발주(국내 발주 — 관세도 통관도 없다)는 영원히 안 닫히고, 비용은 나중에 또 붙을 수 있어 「이제 다 붙었다」를 시스템이 알 수 없다.
--     ⇒ §11-b 「입고가 끝나도 바로 안 닫는다」는 이 뜻으로 고친다(정본 갱신 · 별건). 검증 데이터 PO-02001a(closed)는 그대로.
--   결제(po_payment)는 인보이스 여럿을 가리킨다(Caleb 2026-09-16 · 저장은 인보이스별 · 실무의 「PO 단위로 묶어 낸다」는 화면이 돕는다).
--     ⭐ po_payment_alloc 은 **po_invoice 또는 po_charge 정확히 하나**를 가리킨다(CHECK · Caleb 확정 2026-09-16). 비용 청구서(CBSA 관세 · BBE 통관)도 돈을 낸다 —
--        [실측] Cin7 Purchases 목록에서 그 문서들의 Payment status 가 Paid 로 찍힌다. 인보이스만 가리키면 그 송금을 적을 데가 없고 미지급 목록에서 비용 청구서가 영원히
--        안 낸 것으로 남는다. §11-g 「비용 문서와 인보이스는 같은 모양(밖에서 오는 청구서)」이 결제에서도 성립한다.
--        📌 경위: 「결제는 인보이스 여럿을 가리킨다」로 정할 때 비용 문서를 빼놓고 생각한 것은 설계 대화의 누락이었고, 검토(Claude Code)가 잡아 확정했다.
--   조기결제 할인은 결제 한 건 안에서 보인다 — po_payment.discount_taken 칸(계산으로만 내면 「덜 낸 것」과 「할인 받은 것」이 구별되지 않는다 · 부분 결제 실물 Avlon 50% COD & 50% Net30 · §7).
--   KRW 환차손익은 이번에 계산하지 않는다 — po_payment 에 currency_id·exchange_rate·amount 를 두어 나중에 소급할 수 있게만(§7 · 회계 담당자 영역 · QBO 때).
--
-- ⭐ 결제 계정 — Caleb 실측(2026-09-16) · po_payment.account_id 주석에도 남긴다
--   Cin7 의 결제는 은행과 직접 연결되어 있지 않다. IMS 도 은행 연동이 필요 없다.
--   지금 흐름: QBO 가 계정과목을 만든다 → Cin7 으로 내려온다 → 결제할 때 그중 하나를 지정만 한다 → 실제 fund 매칭은 QBO 가 한다.
--   ⇒ §11-h 「IMS 는 사실만 · 분개는 QBO」와 정확히 맞는다. FK 는 ref_account(id) · nullable · 화면이 목록을 보여 주고 사람이 고른다.
--   ⚠️ ref_account.for_payments 를 결제 계좌 필터로 쓰지 마라 — 실무와 안 맞는다. 23개 중 7개가 카드이고 나머지는 is_active=false 인 Cin7 기본 계정(Gift Card · Petty Cash · Cash Float 은 안 쓴다).
--      정작 실제 은행 계좌(_104_ TD CAD CHEQUING · _105_ BMO CAD CHEQUING · _106_ BMO USD CHEQUING)는 for_payments 에 안 걸려 있다.
--   ⬜ 후보를 좁히는 규칙은 실제로 쓰는 계정이 드러나면 그때(화면 차수 이후). 📌 Cin7 Omni 시절에는 e-transfer/카드/현금/수표 구분만 했고 전부 QBO 에서 처리했다.
--
-- ❌ 이번에 만들지 않는 것 — 사건 표·트리거(원장 이식 때 · ①차와 같다) · 잠금 트리거 · 인보이스 파일 칸(Supabase Storage 미결 · §10-k) · 크레딧 노트 표(§11-g Cin7 탭 · 실물이 나오면).
-- ⚠️ 참조 칸 이름은 마이그레이션 파일로 확인했다 — po_line(id · 20260916144201) · supplier · ref_currency · ref_payment_term · ref_account · ims_staff · product · supplier_discount(모두 id uuid PK).
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ po_invoice — 인보이스 머리 (인보이스 한 장 = 한 행 · §11-g) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_invoice (
  id                 uuid primary key default gen_random_uuid(),
  supplier_id        uuid not null references public.supplier         (id) on delete no action,
  invoice_number     text not null,                                                              -- 공급처가 준 번호(INV 2142773 · 0094204-IN) · 우리가 채번하지 않는다
  invoice_date       date not null,
  due_date           date,                                                                       -- 기한 · 사람이 넣는다(ref_payment_term 값 34행이 비어 있다 · §10-k) · 채워지면 화면이 제안
  payment_term_id    uuid references public.ref_payment_term (id) on delete no action,            -- FK + 원문 병행(§3-b 관례) — 그날의 조건
  payment_term_name  text,
  currency_id        uuid not null references public.ref_currency     (id) on delete no action,
  exchange_rate      numeric,                                                                    -- 환율은 문서에 박는다(§7) · CAD 면 1
  total_amount       numeric not null,                                                           -- ⭐ 인보이스에 찍힌 총액 — 정본. 줄 합×할인 체인은 계산값 · 둘이 다르면 화면이 보여 준다(대조값 · 두 곳에 적는 것이 아니다)
  status             text not null default 'draft',                                              -- draft → confirmed(§11-g 셋을 일으킨다) · cancelled 옆으로
  created_by         uuid references public.ims_staff (id) on delete no action,
  confirmed_by       uuid references public.ims_staff (id) on delete no action,
  confirmed_at       timestamptz,
  cancelled_at       timestamptz,
  note               text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),

  constraint po_invoice_status_ck check (status in ('draft', 'confirmed', 'cancelled')),
  constraint po_invoice_supplier_id_invoice_number_key unique (supplier_id, invoice_number)
);

comment on table  public.po_invoice is '⑤ 인보이스 머리 — ⭐ 인보이스 한 장 = 한 행 · PO 는 줄(po_invoice_line.po_line_id)로 가리킨다(줄 수준 · Caleb 2026-09-16). 한 인보이스가 PO-02001a 와 b 둘에 걸쳐도 줄이 갈리고 총액은 한 번만 있다(§11-g). 「걸린 PO 들」 칸은 두지 않는다 — 조인으로 충분. 확정이 일으키는 셋(§11-g): ① 할인(po_invoice_discount)이 원가로 내려간다 ② 인보이스 수량 vs 받은 수량(po_receipt_line 합) 차이가 드러난다 ③ 미지급이 생긴다(due_date · 결제조건이 처음 일하는 자리). ⭐ 거래 — 컷오버 때 지운다. 정본 po-module §11-g';
comment on column public.po_invoice.invoice_number is '공급처가 준 번호 · unique (supplier_id, invoice_number) — 공급처가 다르면 같은 번호가 있을 수 있어 전역은 틀리고, 안 걸면 같은 인보이스를 두 번 넣는 것이 조용히 지나간다(§11-g 「두 번 세지 않는다」). 한 공급처가 연도별로 번호를 다시 쓰는 경우는 미확인(짐작) — 그때 note 로';
comment on column public.po_invoice.due_date is '지급 기한 · 사람이 넣는다. 계산(invoice_date + ref_payment_term.net_days)은 ref_payment_term 34행이 채워진 뒤 화면이 제안(§10-k). 조기결제 기한(discount_days)도 그때. 미지급 목록의 정렬 축';
comment on column public.po_invoice.total_amount is '⭐ 인보이스에 찍힌 총액(인보이스 통화) — 정본(§3-b 「인보이스 금액이 정본이라 장부는 맞는다」). 줄 합(payable 무관 · 전 줄)에 할인 체인을 곱한 계산값과 다르면 입력 오류 또는 반올림 — 화면이 보여 준다. 두 곳에 적는 것이 아니라 대조값이다. CHECK 없음 — 크레딧성 음수 인보이스가 올 수 있다(짐작 · 실물 미확인)';
comment on column public.po_invoice.status is 'draft 작성 중 → confirmed 확정(§11-g 의 셋이 일어난다 · 잠금 — ⚠️ DB 가 보호하지는 않는다) · cancelled 는 옆으로. ⚠️ 「결제됨」은 상태가 아니라 진행도 — po_payment_alloc 합으로 계산한다(①차 「입고 진행」과 같은 판단)';
comment on column public.po_invoice.payment_term_id is 'FK + 원문(payment_term_name) — PO 또는 공급처의 값을 화면이 복사 제안 · 그날의 조건을 남긴다. 조기결제 할인율의 정본은 ref_payment_term(§3-b D) — 여기 다시 적지 않는다';
comment on column public.po_invoice.exchange_rate is '환율은 문서에 박는다(§7) · 인보이스 통화 → CAD · CAD 면 1. KRW 송금 환차손익은 po_payment 쪽 환율과 대조해 나중에(§7 · 이번엔 계산 안 함)';

-- ═══ po_invoice_line — 인보이스 줄 (po_line 을 가리킨다 · 없는 줄도 담는다) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_invoice_line (
  id                       uuid primary key default gen_random_uuid(),
  po_invoice_id            uuid not null references public.po_invoice (id) on delete cascade,      -- ⭐ 문서 → 소유 줄 · CASCADE
  line_no                  integer not null,
  line_kind                text not null default 'goods',                                          -- goods 물건(po_line 필수) · charge 운임 등 비용 줄 · other 우리가 안 시킨 것
  po_line_id               uuid references public.po_line (id) on delete no action,                -- ⭐ nullable — 인보이스는 밖에서 오는 사실이다. PO 에 없는 줄도 실물(운임 · 안 시킨 것)
  description              text,                                                                   -- po_line 이 없으면 필수(CHECK) · 있으면 자유
  qty_ea                   numeric not null,                                                       -- 낱개(po_line 과 대조) · 부호 CHECK 없음(정정 줄이 음수로 올 수 있다 · inv_doc_cost 선례) · charge 줄은 1
  entered_unit_product_id  uuid references public.product (id) on delete no action,                -- 인보이스에 찍힌 단위(CASE 등 = 세트 SKU) · null 이면 EA
  entered_qty              numeric,
  entered_pack_factor      numeric,                                                                -- 그날의 환산 계수(po_line 과 같다 · §4-d)
  unit_price               numeric(18,7) not null default 0,                                       -- ⭐ 낱개 단가(인보이스 통화) · 실제 단가 — 할인은 여기 녹이지 않는다(문서 위 po_invoice_discount) · 0 허용(샘플)
  is_payable               boolean not null default true,                                          -- ⭐ 실무: 「인보이스에 있는 shipping cost 빼고 pay함」(§3-b Comments) — 빼고 내는 줄은 false
  note                     text,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  constraint po_invoice_line_kind_ck          check (line_kind in ('goods', 'charge', 'other')),
  constraint po_invoice_line_target_ck        check ((line_kind = 'goods' and po_line_id is not null)
                                                     or (line_kind <> 'goods' and description is not null)),
  constraint po_invoice_line_line_no_ck       check (line_no >= 1),
  constraint po_invoice_line_unit_price_ck    check (unit_price >= 0),
  constraint po_invoice_line_entered_unit_ck  check (entered_unit_product_id is null
                                                     or (entered_qty is not null and entered_pack_factor is not null)),
  constraint po_invoice_line_po_invoice_id_line_no_key unique (po_invoice_id, line_no)
);

comment on table  public.po_invoice_line is '⑤ 인보이스 줄 — ⭐ po_line 을 가리킨다(줄 수준 · Caleb 2026-09-16). 근거: ① 수량 차이(우리 200 vs 인보이스 300)는 줄이 없으면 안 보인다 ② 할인이 물건에 금액 비례로 내려가려면 어느 물건인지 알아야 한다 ③ 실무가 줄 단위다(Cin7 Invoice 탭 · Copy). ⭐ 갈라진 문서 덕에 a 는 주문=입고가 맞아 Copy 할 때 뺄 것이 없다(①차 검증 실증). ⚠️ po_line 에 없는 줄도 담는다(nullable · line_kind) — 막으면 그런 인보이스를 IMS 에 못 넣고 「PO 에 없는 줄」이라는 차이가 사라진다. ⬜ charge 줄이 원가로 내려가는 길(po_charge 와 같은 배분 규칙)은 사건 차수에. ⭐ 거래 — 컷오버 때 지운다';
comment on column public.po_invoice_line.line_kind is 'goods = 물건(po_line_id 필수 · 매입 원가) · charge = 운임 등 인보이스 안에 끼어 온 비용(po_line 없음 · description 필수 · 대개 is_payable=false) · other = 우리가 안 시킨 것(description 필수 · 차이로 드러난다). CHECK po_invoice_line_target_ck';
comment on column public.po_invoice_line.po_line_id is '⭐ 어느 발주 라인의 청구인가 → po_line(id) · on delete no action(인보이스가 걸린 라인은 지울 수 없다). nullable — 밖에서 오는 사실을 그대로 담는다. 한 인보이스의 줄들이 PO-02001a 와 b 의 라인을 각각 가리킬 수 있다 — 그래서 머리에 PO 칸이 없다';
comment on column public.po_invoice_line.qty_ea is '낱개 수량(po_line.qty_ea · po_receipt_line 합과 대조 — §11-g ② 차이) · numeric · 부호·정수 CHECK 없음. ⚠️ 인보이스는 CASE 로 오는 일이 많다([실물 Ampro] CASE 345 @ 20.34 = EA 2,070 @ 3.39 · §3-b ⑤) — 찍힌 대로 entered_* 에 넣고 여기는 낱개로';
comment on column public.po_invoice_line.entered_unit_product_id is '인보이스에 찍힌 단위 = 그 낱개를 parent_product_id 로 가진 세트 SKU(product.id) · null 이면 EA. entered_qty × entered_pack_factor = qty_ea 를 화면이 검산한다(po_line 과 같은 칸 넷 · 이견 8)';
comment on column public.po_invoice_line.unit_price is '낱개 단가(인보이스 통화 · numeric(18,7)) — ⭐ 실제 단가 · 할인은 여기 녹이지 않고 문서 위 po_invoice_discount 로(§3-b ④). po_line.unit_price 와 다르면 차이(마스터도 고쳐야 하나 — §11-d) · 0 허용(샘플 §3-b ④)';
comment on column public.po_invoice_line.is_payable is '⭐ 결제 대상인가 — 실무가 「인보이스에 있는 shipping cost 빼고 pay함」(§3-b Comments · Caleb 2026-09-16 채택). 결제 충당은 인보이스 단위라 이 칸이 없으면 빼고 낸 인보이스가 영원히 미지급으로 남거나 사람이 「다 낸 것으로 친다」를 눌러야 한다. 미지급 = payable 줄 합(할인 적용 후) − po_payment_alloc 합';

-- ═══ po_invoice_discount — 인보이스 위 할인 줄 (확정 · 원가 배분의 정본) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_invoice_discount (
  id                    uuid primary key default gen_random_uuid(),
  po_invoice_id         uuid not null references public.po_invoice (id) on delete cascade,        -- ⭐ 문서 → 소유 줄 · CASCADE
  seq                   integer not null,                                                          -- ⚠️⚠️ 곱해지는 차례(po_discount · supplier_discount 와 같은 뜻)
  name                  text not null,
  percent               numeric not null,
  supplier_discount_id  uuid references public.supplier_discount (id) on delete no action,          -- 제안의 원천 · 스페셜은 null
  note                  text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint po_invoice_discount_percent_ck    check (percent >= 0 and percent <= 100),
  constraint po_invoice_discount_seq_ck        check (seq >= 1),
  constraint po_invoice_discount_po_invoice_id_seq_key unique (po_invoice_id, seq)
);

comment on table  public.po_invoice_discount is '⑤ 인보이스 위 할인 줄 — ⭐ 확정 층. 할인은 공급처가 인보이스에 적어 보내는 것이다([실물 Ampro INV 0094204-IN] Trade 17% → Damage 1% → Full Line 3% · §3-b D). ①차 po_discount 는 발주를 만들 때 제안받은 예상 — 인보이스를 만들 때 복사 제안되고 여기서 고친다. ⭐ 원가 배분의 정본은 이 표다(§11-g ① · §3-b ③ 「할인 줄은 어느 인보이스에 속하는지 알아야 한다」 — Cin7 이 PO 단위로 배분해 아직 인보이스 안 된 498.33 의 원가까지 내린 실물). ⚠️⚠️ 차례로 곱한다(더하면 146 달러 어긋남). 배분(goods 줄에 금액 비례 · 잔돈은 금액이 가장 큰 줄 · 동점은 SKU 순 · charge/other 줄에는 안 내린다)은 계산 규칙 — 칸 없음. ⚠️ 조기결제 할인은 여기 아니다(ref_payment_term · po_payment.discount_taken). ⭐ 거래 — 컷오버 때 지운다';
comment on column public.po_invoice_discount.seq is '⚠️⚠️ 곱해지는 차례 · unique (po_invoice_id, seq) · 10·20·30 처럼 띄어 매기면 사이에 끼울 수 있다(supplier_discount.seq 관례)';
comment on column public.po_invoice_discount.supplier_discount_id is '제안의 원천 → supplier_discount(id) · nullable(스페셜 할인 · 마스터에 없는 이름). 마스터와 percent 가 다르면 「마스터가 낡았나 이번만 달랐나」를 사람이 판단한다(§3-b D 「마스터는 제안이지 잠금이 아니다」)';

-- ═══ po_charge — 비용 문서 (운임 · 관세 · 통관 — Service invoice · 줄 없는 문서 · §11-f) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_charge (
  id             uuid primary key default gen_random_uuid(),
  supplier_id    uuid not null references public.supplier     (id) on delete no action,            -- 경비처(CBSA · BBE · Showtime …) · is_purchasable=false 여도 supplier 에 남는다(§3-b 열린 물음 「원가에 얹히는 비용을 주는 곳은 남는다」)
  charge_number  text not null,                                                                    -- 청구서 번호(Service Invoice · [실물] B6913286 = inv_doc_cost.ref_number 의 그것)
  charge_date    date not null,                                                                    -- 청구서 날짜(원장 occurred_on 이 된다 · inv_doc_cost 관례)
  due_date       date,
  kind           text not null,                                                                    -- freight 운임 · duty 관세 · brokerage 통관중개 · other
  description    text,
  currency_id    uuid not null references public.ref_currency (id) on delete no action,
  exchange_rate  numeric,
  total_amount   numeric not null,                                                                 -- 청구서 총액 · CHECK 없음(정정이 음수로 올 수 있다 · inv_doc_cost 선례)
  status         text not null default 'draft',
  created_by     uuid references public.ims_staff (id) on delete no action,
  confirmed_by   uuid references public.ims_staff (id) on delete no action,
  confirmed_at   timestamptz,
  cancelled_at   timestamptz,
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint po_charge_kind_ck   check (kind in ('freight', 'duty', 'brokerage', 'other')),
  constraint po_charge_status_ck check (status in ('draft', 'confirmed', 'cancelled')),
  constraint po_charge_supplier_id_charge_number_key unique (supplier_id, charge_number)
);

comment on table  public.po_charge is '⑤ 비용 문서(§11-f) — 운송·관세·통관 청구서가 자기 문서로 서서 PO 여럿을 가리킨다(po_charge_alloc). ⭐ 별도 문서인 결정적 근거: 컨테이너 하나에 여러 공급처 물건이 섞여 청구서 한 장이 PO 여러 건에 걸친다(Caleb 실측) — PO 안에 넣으면 쪼개야 하고 원본과 일대일이 안 맞는다. [실물] Ampro 발주 옆에 CBSA(관세)·BBE(통관중개)가 각자 문서 · Type=Service. ⭐ 줄 없는 문서 — 라인 배분은 계산(§11-e 규칙). 제품을 참조하지 않는다(Type=Service 53 은 ③ product 에 없다 · kind + description 으로 · §7 의 「담을 자리」는 필요 없어진 것으로 닫을 후보). 원가는 고치는 것이 아니라 더한다 — 원장의 inv_layer_cost_add 가 받을 자리(§12-c · kind 가 그 갈래). ⭐ 거래 — 컷오버 때 지운다';
comment on column public.po_charge.kind is 'freight 운임 · duty 관세(CBSA) · brokerage 통관중개(BBE) · other. CHECK 있음 — 우리 값이라 늘릴 때는 마이그레이션(규칙 41 절차). 원장 이식 때 inv_layer_cost_add.kind(landed …)로 가는 갈래';
comment on column public.po_charge.charge_number is '청구서 번호 · unique (supplier_id, charge_number) — po_invoice 와 같은 판단(공급처가 다르면 같은 번호가 있을 수 있다 · 두 번 넣기 방지)';
comment on column public.po_charge.total_amount is '청구서 총액(청구 통화) · CHECK 없음 — 정정이 음수로 올 수 있다(inv_doc_cost.amount 주석 선례). po_charge_alloc 합과 대조(같아야 한다 · 화면이 보여 준다)';
comment on column public.po_charge.status is 'draft → confirmed(배분이 원가로 내려가는 시점 · 사건 차수) · cancelled. 「결제됨」은 진행도(po_payment_alloc 합)';

-- ═══ po_charge_alloc — 비용 배분 줄 (이 발주에 얼마 · ⭐ 박아 둔다) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_charge_alloc (
  id            uuid primary key default gen_random_uuid(),
  po_charge_id  uuid not null references public.po_charge (id) on delete cascade,                 -- ⭐ 문서 → 소유 줄 · CASCADE
  po_id         uuid not null references public.po        (id) on delete no action,               -- ⭐ 발주 문서(갈라진 뒤의 것 · PO-02001a)까지만 — 라인은 계산
  amount        numeric not null,                                                                  -- ⭐ 박아 둔 배분 금액(청구 통화) · CHECK 없음(정정 음수)
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint po_charge_alloc_po_charge_id_po_id_key unique (po_charge_id, po_id)
);

comment on table  public.po_charge_alloc is '⑤ 비용 배분 줄 — 청구서 → 발주 문서(§11-f 배분 ①). ⭐⭐ 배분 금액은 넣을 때 계산해(기본 금액 비례 · 사람이 고칠 수 있다) **박아 두고, 나중에 발주 금액이 바뀌어도 다시 계산하지 않는다**(Caleb 2026-09-16). 근거: 비용은 대개 물건을 다 받은 뒤에 붙어 그때는 이미 확정 상태고, 한번 원가 층에 더해진 금액이 저절로 바뀌면 원가가 흔들린다. 고치려면 사람이 고친다. ⚠️ 「발주 금액이 바뀌었는데 배분이 안 따라온다」는 버그가 아니라 설계다(①차 「원장 합 ≠ 입고 줄 합」과 같은 종류의 주석). ⭐ po.status 와 무관하게 붙는다 — closed 는 입고 종료의 뜻이고 비용은 그 뒤에 붙는다(제약 없음 · Caleb 2026-09-16). 발주 → 라인 배분은 계산(§11-e 규칙 · 칸 없음). ⭐ 거래 — 컷오버 때 지운다';
comment on column public.po_charge_alloc.po_id is '→ po(id) · on delete no action. 갈라진 뒤의 문서를 가리킨다(PO-02001a · b 각각). ⭐ closed 문서에도 붙는다 — 국내 발주처럼 비용이 안 오는 발주가 있고 비용은 나중에 또 붙을 수 있어 「다 붙었다」를 시스템이 알 수 없다(§11-b 갱신 · 별건)';
comment on column public.po_charge_alloc.amount is '⭐ 박아 둔 금액(청구 통화) — 다시 계산하지 않는다(표 주석). 합이 po_charge.total_amount 와 같아야 한다(대조 · 제약으로 막지 않는다 — 입력 중간 상태가 있다). CHECK 없음 — 정정 음수';

-- ═══ po_payment — 결제 (사실만 · 분개는 QBO · §11-h) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_payment (
  id              uuid primary key default gen_random_uuid(),
  paid_on         date not null default current_date,
  amount          numeric not null,                                                                -- 실제로 낸 돈(결제 통화)
  currency_id     uuid not null references public.ref_currency (id) on delete no action,           -- 결제 통화(인보이스 통화와 다를 수 있다 · KRW 송금 §7)
  exchange_rate   numeric,                                                                         -- 결제 통화 → CAD · 환차손익 소급용(이번엔 계산 안 함)
  account_id      uuid references public.ref_account (id) on delete no action,                    -- ⭐ nullable · 지정만 한다(아래 주석 · Caleb 실측)
  reference       text,                                                                            -- 송금 참조 · 체크 번호 · 카드 승인 등 자유 문자열
  discount_taken  numeric not null default 0,                                                      -- ⭐ 조기결제로 덜 낸 금액(결제 통화) · 사람이 선언한다
  paid_by         uuid references public.ims_staff (id) on delete no action,
  note            text,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),

  constraint po_payment_amount_ck         check (amount > 0),
  constraint po_payment_discount_taken_ck check (discount_taken >= 0)
);

comment on table  public.po_payment is '⑤ 결제 — IMS 가 든다(§11-h · Caleb「결제는 IMS 에서 하는 게 맞다」). ⭐ IMS 가 드는 것은 「무엇을 언제 얼마 냈다」는 사실 — 어느 계정으로 어떻게 분개되는지는 QBO 의 일(§3-b 구별선). 인보이스·비용 문서 여럿을 가리킨다(po_payment_alloc) — 실무는 PO(입고된 쉽먼트) 단위로 묶어 내지만(Caleb 실측) 저장은 청구서별 충당 금액이다: 갚을 돈을 만든 것은 인보이스고 · PO 를 가리키면 어느 인보이스가 결제됐는지 모르고 · 인보이스 하나가 PO 둘에 걸친다. 묶기는 화면이 돕는다. 상태 없음 — 결제는 사실이라 잘못 넣었으면 지운다(DELETE 열림 · 상쇄 규칙은 QBO 이음새 때). ⭐ 거래 — 컷오버 때 지운다';
comment on column public.po_payment.account_id is '⭐ 결제 계정 → ref_account(id) · nullable · 지정만 한다. [Caleb 실측 2026-09-16] Cin7 의 결제는 은행과 직접 연결되어 있지 않다 — IMS 도 은행 연동이 필요 없다. 흐름: QBO 가 계정과목을 만든다 → Cin7 으로 내려온다 → 결제할 때 그중 하나를 지정만 한다 → 실제 fund 매칭은 QBO 가 한다(§11-h 「IMS 는 사실만 · 분개는 QBO」와 정확히 맞는다). ⚠️ ref_account.for_payments 를 결제 계좌 필터로 쓰지 마라 — 23개 중 7개가 카드 · 나머지는 is_active=false 인 Cin7 기본 계정(Gift Card · Petty Cash · Cash Float 은 안 쓴다) · 정작 실제 은행 계좌 _104_ TD CAD CHEQUING · _105_ BMO CAD CHEQUING · _106_ BMO USD CHEQUING 은 for_payments 에 안 걸려 있다. 화면이 목록을 보여 주고 사람이 고른다. ⬜ 후보를 좁히는 규칙은 실제로 쓰는 계정이 드러나면 그때. 📌 Cin7 Omni 시절엔 e-transfer/카드/현금/수표 구분만 했고 전부 QBO 에서 처리했다';
comment on column public.po_payment.amount is '실제로 낸 돈(결제 통화) · > 0. 충당 합(po_payment_alloc.amount 합) = amount + discount_taken 이어야 한다 — 표를 가로지르는 검산이라 CHECK 로 못 걸고 화면이 보여 준다';
comment on column public.po_payment.discount_taken is '⭐ 조기결제로 덜 낸 금액(결제 통화) — 인보이스 합 10,000 에 9,800 을 보냈으면 200. 결제 한 건 안에서 그 차이가 보인다(인보이스마다 따로 적으면 안 보인다 · Caleb 2026-09-16). ⚠️ 칸으로 두는 이유 — 계산(충당 합 − 낸 돈)만으로는 「덜 낸 것(부분 결제 · 실물 Avlon 50% COD & 50% Net30 §7)」과 「할인 받은 것」이 구별되지 않는다. 사람이 「이 200 은 할인이다」를 선언해야 인보이스가 닫힌다. ⚠️ HST 매입세액 처리는 회계사 확인 미결(§11-h · [실물 E.T Browne] 덜 낸 226.81 인데 Cin7 은 256.30 을 깎았다) — 금액만 기록해 두면 나중에 얹는다';
comment on column public.po_payment.currency_id is '결제 통화 · 인보이스 통화와 다를 수 있다(인보이스 USD · 결제 KRW · §7). exchange_rate 와 함께 두어 KRW 환차손익을 나중에 소급할 수 있게 — 이번엔 계산하지 않는다(회계 담당자 영역 · QBO 때)';

-- ═══ po_payment_alloc — 결제 충당 줄 (인보이스 또는 비용 문서 하나에 얼마) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_payment_alloc (
  id             uuid primary key default gen_random_uuid(),
  po_payment_id  uuid not null references public.po_payment (id) on delete cascade,                -- ⭐ 문서 → 소유 줄 · CASCADE
  po_invoice_id  uuid references public.po_invoice (id) on delete no action,                       -- 둘 중 하나(CHECK)
  po_charge_id   uuid references public.po_charge  (id) on delete no action,                       -- 비용 청구서도 돈을 낸다(Cin7 에서 Paid 로 찍힌다 · 머리 주석)
  amount         numeric not null,                                                                 -- 충당 금액(결제 통화)
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),

  constraint po_payment_alloc_amount_ck  check (amount > 0),
  constraint po_payment_alloc_target_ck  check ((po_invoice_id is null) <> (po_charge_id is null)),   -- 정확히 하나
  constraint po_payment_alloc_po_payment_id_po_invoice_id_key unique (po_payment_id, po_invoice_id),  -- null 은 서로 다르게 취급된다(charge 줄들은 여기 안 걸린다) · 부분 인덱스 아님
  constraint po_payment_alloc_po_payment_id_po_charge_id_key  unique (po_payment_id, po_charge_id)
);

comment on table  public.po_payment_alloc is '⑤ 결제 충당 줄 — 이 결제가 어느 청구서에 얼마를 갚았나. ⭐ po_invoice **또는** po_charge 정확히 하나를 가리킨다(CHECK po_payment_alloc_target_ck). ⭐ 비용 청구서(CBSA 관세 · BBE 통관)도 돈을 낸다 — [실측 Caleb 2026-09-16] Cin7 Purchases 목록에서 그 문서들의 Payment status 가 Paid 로 찍힌다. 인보이스만 가리키면 그 송금을 적을 데가 없고 미지급 목록에서 비용 청구서가 영원히 안 낸 것으로 남는다(§11-g 「비용 문서와 인보이스는 같은 모양」). 📌 처음 「결제는 인보이스 여럿을 가리킨다」로 정할 때 비용 문서를 빼놓은 것은 설계 대화의 누락 — 검토에서 잡아 확정. 인보이스 미지급 = payable 줄 합(할인 적용 후) − 여기 합 · 비용 미지급 = total_amount − 여기 합. ⭐ 거래 — 컷오버 때 지운다';
comment on column public.po_payment_alloc.amount is '이 청구서에 충당한 금액(결제 통화) · > 0. 한 결제의 충당 합 = po_payment.amount + discount_taken(화면 검산). 인보이스가 두 결제로 갚아질 수 있고(부분 결제) 한 결제가 인보이스 여럿을 갚을 수 있다';

-- ═══ FK 인덱스 — Postgres 는 자동 생성하지 않는다 (§5 · <표>_<칸>_idx) ═══
create index if not exists po_invoice_supplier_id_idx       on public.po_invoice (supplier_id);
create index if not exists po_invoice_payment_term_id_idx   on public.po_invoice (payment_term_id);
create index if not exists po_invoice_currency_id_idx       on public.po_invoice (currency_id);
create index if not exists po_invoice_created_by_idx        on public.po_invoice (created_by);
create index if not exists po_invoice_confirmed_by_idx      on public.po_invoice (confirmed_by);
create index if not exists po_invoice_status_idx            on public.po_invoice (status);
create index if not exists po_invoice_due_date_idx          on public.po_invoice (due_date);          -- 미지급 목록 정렬
create index if not exists po_invoice_line_po_invoice_id_idx           on public.po_invoice_line (po_invoice_id);
create index if not exists po_invoice_line_po_line_id_idx              on public.po_invoice_line (po_line_id);   -- ⭐ 인보이스 → PO 조인의 축
create index if not exists po_invoice_line_entered_unit_product_id_idx on public.po_invoice_line (entered_unit_product_id);
create index if not exists po_invoice_discount_po_invoice_id_idx        on public.po_invoice_discount (po_invoice_id);
create index if not exists po_invoice_discount_supplier_discount_id_idx on public.po_invoice_discount (supplier_discount_id);
create index if not exists po_charge_supplier_id_idx   on public.po_charge (supplier_id);
create index if not exists po_charge_currency_id_idx   on public.po_charge (currency_id);
create index if not exists po_charge_created_by_idx    on public.po_charge (created_by);
create index if not exists po_charge_confirmed_by_idx  on public.po_charge (confirmed_by);
create index if not exists po_charge_status_idx        on public.po_charge (status);
create index if not exists po_charge_alloc_po_charge_id_idx on public.po_charge_alloc (po_charge_id);
create index if not exists po_charge_alloc_po_id_idx        on public.po_charge_alloc (po_id);
create index if not exists po_payment_currency_id_idx on public.po_payment (currency_id);
create index if not exists po_payment_account_id_idx  on public.po_payment (account_id);
create index if not exists po_payment_paid_by_idx     on public.po_payment (paid_by);
create index if not exists po_payment_paid_on_idx     on public.po_payment (paid_on);
create index if not exists po_payment_alloc_po_payment_id_idx on public.po_payment_alloc (po_payment_id);
create index if not exists po_payment_alloc_po_invoice_id_idx on public.po_payment_alloc (po_invoice_id);
create index if not exists po_payment_alloc_po_charge_id_idx  on public.po_payment_alloc (po_charge_id);

-- ═══ 트리거 — ⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라 ═══
create trigger po_invoice_set_updated_at          before update on public.po_invoice          for each row execute function public.set_updated_at();
create trigger po_invoice_line_set_updated_at     before update on public.po_invoice_line     for each row execute function public.set_updated_at();
create trigger po_invoice_discount_set_updated_at before update on public.po_invoice_discount for each row execute function public.set_updated_at();
create trigger po_charge_set_updated_at           before update on public.po_charge           for each row execute function public.set_updated_at();
create trigger po_charge_alloc_set_updated_at     before update on public.po_charge_alloc     for each row execute function public.set_updated_at();
create trigger po_payment_set_updated_at          before update on public.po_payment          for each row execute function public.set_updated_at();
create trigger po_payment_alloc_set_updated_at    before update on public.po_payment_alloc    for each row execute function public.set_updated_at();

-- ═══ RLS · 권한 — ①차와 같은 auth_all (§10-j 3-i) · ⚠️ 확정 문서 보호 없음(머리 주석) ═══
alter table public.po_invoice          enable row level security;
alter table public.po_invoice_line     enable row level security;
alter table public.po_invoice_discount enable row level security;
alter table public.po_charge           enable row level security;
alter table public.po_charge_alloc     enable row level security;
alter table public.po_payment          enable row level security;
alter table public.po_payment_alloc    enable row level security;

create policy auth_all on public.po_invoice          for all to authenticated using (true) with check (true);
create policy auth_all on public.po_invoice_line     for all to authenticated using (true) with check (true);
create policy auth_all on public.po_invoice_discount for all to authenticated using (true) with check (true);
create policy auth_all on public.po_charge           for all to authenticated using (true) with check (true);
create policy auth_all on public.po_charge_alloc     for all to authenticated using (true) with check (true);
create policy auth_all on public.po_payment          for all to authenticated using (true) with check (true);
create policy auth_all on public.po_payment_alloc    for all to authenticated using (true) with check (true);

revoke all on public.po_invoice          from anon;
revoke all on public.po_invoice_line     from anon;
revoke all on public.po_invoice_discount from anon;
revoke all on public.po_charge           from anon;
revoke all on public.po_charge_alloc     from anon;
revoke all on public.po_payment          from anon;
revoke all on public.po_payment_alloc    from anon;

-- DELETE 는 막지 않는다(초안은 지운다 · 확정 뒤는 취소로 · 결제는 사실이라 잘못 넣었으면 지운다) · TRUNCATE 는 막는다
revoke truncate on public.po_invoice          from authenticated;
revoke truncate on public.po_invoice_line     from authenticated;
revoke truncate on public.po_invoice_discount from authenticated;
revoke truncate on public.po_charge           from authenticated;
revoke truncate on public.po_charge_alloc     from authenticated;
revoke truncate on public.po_payment          from authenticated;
revoke truncate on public.po_payment_alloc    from authenticated;
