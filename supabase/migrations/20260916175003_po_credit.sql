-- ─────────────────────────────────────────────────────────────
-- ⑤ PO 표 ③차 — 크레딧 노트 (po_invoice 에 종류를 더한다 · RPC po_detail 갱신) (테스트 DB Asung-IMS · 2026-09-16)
--
-- 정본: docs/design/po-module.md §11-g(인보이스) · §11-h(결제) · §13(표·검증 · 거래 표 규약 §5)
-- 표: 20260916153313_po_invoice_charge_payment.sql(②차 · 이번에 po_invoice 를 고친다 — 다른 표는 무변)
-- 뷰·RPC: 20260916163806_po_read.sql → 20260916164539_po_read_factor.sql(지금 도는 정의) → 이 파일이 po_detail 만 create or replace · po_list 는 무변
-- 지시서: ~/asung/prompts/po-tables-3-credit.md · 검토 이견 1~11(2026-09-16 · 전부 받음 · 3 은 ④안 · 할인 줄은 자동 복사 없음)
--
-- ⭐⭐ 왜 — 실무가 이미 그렇게 돈다 [Caleb 실측 2026-09-16]
--   PO 100 · 인보이스 100 · 실제 입고 90 인 일이 있다 — 공급처마다 다르지만 특정 공급처는 거의 매번. 이때 supplier credit note 를 만들어 두고 있다.
--   Cin7 Purchases 「With a credit note」 필터에 걸리는 건이 꽤 많다(Camille Rose · By Natures · Recho Ayumaah · Ebin New York · J.Strickland · Exod · Avlon · Taliah Waajid · BIP …).
--   [Cin7 실물 · Recho Ayumaah / PO-00832] Credit note # 23537005816 · 2026-06-10 · RCO00162 54 × 6 = 324.00 · 「Credit note for」 23537005760.
--   Payments: 23537005760 = 7,822.66 · 23537005817 = 86.88 · 23537005816 = 324.00 → paid 7,585.54 ⇒ 크레딧이 갚을 돈을 **줄인다**.
--   📌 Credit note 옆에 Unstock 탭이 따로 있다 — 크레딧과 재고 빼기는 갈려 있다. 우리 경우(90개만 받음)는 뺄 재고가 없다. ⬜ 「받고 나서 반품」은 사건 차수(§11-j).
--   ⚠️ 정본에 크레딧 설계가 없었다(§11-g 「Credit note · Unstock 탭」 한 줄) — 이번에 처음 선다(정본 갱신 · 별건).
--
-- ⭐ Caleb 이 정한 것(2026-09-16)
--   2-a 새 표를 만들지 않는다 — po_invoice 에 종류 칸 doc_kind('invoice' · 'credit'). 근거: Cin7 실물에서 크레딧은 인보이스와 같은 모양(번호·날짜·환율·줄) ·
--       줄 구조가 같고 결제 충당도 같은 자리 · 별도 표면 po_payment_alloc 의 대상이 셋이 된다 · 크레딧은 본질적으로 부호가 반대인 인보이스다.
--   2-b ⭐⭐ 금액은 **양수**로 담는다 — 크레딧 노트 실물에 324.00 으로 찍혀 있다. DB 에 −324.00 이 있으면 대조할 때마다 뒤집어 생각해야 한다(§13 「찍힌 값이 정본」과 같은 방향).
--       ⇒ 부호는 **RPC 계산에서만** 준다(§13 「계산 규칙의 정본은 RPC」). ⚠️ 「왜 크레딧이 양수지」는 결함이 아니라 설계다.
--   2-c 「어느 인보이스에 대한 것인가」는 비워 둘 수 있다 — credit_for_invoice_id nullable · self-FK. 인보이스와 무관한 조정 크레딧이 실제로 있다(Caleb 실측).
--       ⇒ 미지급이 갈린다: 붙은 크레딧은 그 인보이스의 미지급을 줄인다 · 안 붙은 크레딧은 「쓸 수 있는 크레딧」으로 남아 결제할 때 가져다 쓴다(alloc).
--   2-d 크레딧 줄은 발주 라인을 가리킨다 — po_invoice_line 을 **그대로** 쓴다(칸 변경 없음). 「시켰다 · 청구됐다 · 받았다 · 크레딧 받았다」가 한 줄로 이어진다.
--       is_payable 의 뜻을 넓힌다 — 「결제 계산에 드는 줄」(인보이스: 낼 돈 · 크레딧: 뺄 돈). 돌려받은 물건 = goods + po_line_id · 조정 = other + description.
--   2-e 결제 부호 — ④안(검토 이견 3 · Caleb 확정): **붙은 크레딧은 인보이스에서 빼고 끝 · 안 붙은 크레딧은 결제 때 po_payment_alloc 이 크레딧을 가리켜 「썼다」(양수 · CHECK > 0 유지).**
--       결제 검산: Σalloc(인보이스) + Σalloc(비용) = amount + discount_taken + Σalloc(크레딧). 표 변경 없음(alloc 은 이미 po_invoice 행을 가리킬 수 있다).
--       ⚠️ 붙어 있으면서 alloc 으로도 쓰이면 두 번 깎인다 — 다른 행이라 CHECK 로 못 걸고 RPC 가 warnings 로 잡는다. 만들기 화면이 막는다.
--   ⭐ 할인 줄은 크레딧에 **자동으로 복사하지 않는다**(Caleb 2026-09-16) — 크레딧 노트는 공급처가 보내오는 문서다. 거기 적힌 대로 넣는다.
--       Cin7 화면의 크레딧 줄에도 DISCOUNT 0% 칸이 있었다(RCO00162 54 × 6 = 324.00). 공급처 문서에 할인이 적혀 있으면 사람이 po_invoice_discount 에 넣는다.
--
-- ⭐ 제약 — 같은 행 안에서 걸 수 있는 것만 CHECK · 다른 행을 봐야 하는 것은 RPC warnings(트리거 없음 규약 · ①차)
--   CHECK  doc_kind in ('invoice','credit') · credit_for 는 크레딧만 갖고 자기 자신은 못 가리킨다
--   RPC    credit_for 가 크레딧을 가리킨다 · 다른 공급처를 가리킨다 · 붙어 있는데 alloc 으로도 썼다 → credits[].warnings
--   유니크 (supplier_id, invoice_number) → **(supplier_id, doc_kind, invoice_number)** — 공급처가 크레딧 메모를 인보이스와 다른 번호 체계로 내면 같은 숫자가 겹칠 수 있다(짐작 · 실물은 다른 번호).
--       막았을 때의 대가(그 크레딧을 IMS 에 못 넣는다)가 열었을 때의 대가(같은 번호의 인보이스·크레딧이 둘이면 종류로 가른다)보다 크다. 같은 종류 안의 중복은 여전히 막힌다. 부분 인덱스 아님.
--
-- 이 파일이 하는 것 — ① po_invoice 칸 둘 + 제약 + 유니크 교체 + 인덱스 ② 주석 갱신(⚠️ ②차 total_amount 주석의 「크레딧성 음수 인보이스가 올 수 있다(짐작)」를 고친다 — 크레딧은 별 문서 · 양수)
--   ③ po_detail create or replace(인보이스만 세고 credits[] 절 신설 · unpaid 에 credit_total 반영 · payments target_kind 에 'credit') · po_list 는 무변(발주 금액만 · 인보이스도 안 센다).
-- 한 파일인 이유 — RPC 가 새 칸을 읽는다. 따로 가면 중간 상태에서 RPC 가 깨진다. 기존 1행(AMP-778812)은 default 로 invoice 가 된다(update 불필요).
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po_invoice — 종류 · 크레딧 대상 ═══
alter table public.po_invoice
  add column if not exists doc_kind              text not null default 'invoice',                                    -- ⭐ invoice · credit(2-a) · 기존 행은 default 로 invoice
  add column if not exists credit_for_invoice_id uuid references public.po_invoice (id) on delete no action;          -- ⭐ 어느 인보이스에 대한 크레딧인가(Cin7 「Credit note for」) · nullable(조정 크레딧) · self-FK

alter table public.po_invoice
  add constraint po_invoice_doc_kind_ck   check (doc_kind in ('invoice', 'credit')),
  add constraint po_invoice_credit_for_ck check (credit_for_invoice_id is null
                                                 or (doc_kind = 'credit' and credit_for_invoice_id <> id));           -- 인보이스는 이 칸을 못 쓴다 · 자기 자신 금지 (같은 행 안 · CHECK 가능)

-- 유니크 교체 — 종류를 넣는다(위 머리 · 부분 인덱스 아님) · 선례 wms_receipts_cin7_purchase_id_key 교체(drop if exists → add)
alter table public.po_invoice drop constraint if exists po_invoice_supplier_id_invoice_number_key;
alter table public.po_invoice add constraint po_invoice_supplier_id_doc_kind_invoice_number_key unique (supplier_id, doc_kind, invoice_number);

create index if not exists po_invoice_credit_for_invoice_id_idx on public.po_invoice (credit_for_invoice_id);   -- FK 인덱스(§5) · 「이 인보이스에 붙은 크레딧」 조회의 축
create index if not exists po_invoice_doc_kind_idx              on public.po_invoice (doc_kind);

-- ═══ ② 주석 갱신 ═══
comment on table  public.po_invoice is '⑤ 인보이스 머리 — ⭐ 인보이스 한 장 = 한 행 · PO 는 줄(po_invoice_line.po_line_id)로 가리킨다(줄 수준 · Caleb 2026-09-16). ⭐ [2026-09-16 ③차] 크레딧 노트도 이 표다 — doc_kind=credit · 같은 모양(번호·날짜·환율·줄) · 금액은 **양수** · 부호는 RPC 계산에서 · credit_for_invoice_id 로 어느 인보이스에 대한 것인지(nullable · 조정 크레딧). 확정이 일으키는 셋(§11-g): ① 할인(po_invoice_discount)이 원가로 내려간다 ② 인보이스 수량 vs 받은 수량(po_receipt_line 합) 차이가 드러난다 ③ 미지급이 생긴다(크레딧은 줄인다). ⭐ 거래 — 컷오버 때 지운다. 정본 po-module §11-g · §13';
comment on column public.po_invoice.doc_kind is '⭐ invoice(공급처 청구서) · credit(공급처 크레딧 노트 · 2026-09-16 ③차). 새 표를 만들지 않은 이유 — Cin7 실물에서 크레딧은 인보이스와 같은 모양이고 줄·결제 충당 자리가 같다 · 별도 표면 po_payment_alloc 의 대상이 셋이 된다(Caleb). ⚠️ 크레딧 금액도 **양수**로 담는다 — 찍힌 값(324.00)이 정본이라 −324.00 이 들어 있으면 대조할 때마다 뒤집어야 한다. 부호는 po_detail RPC 가 계산에서 준다(§13 「계산 규칙의 정본은 RPC」). 기본값 invoice — 기존 행이 그대로 invoice 가 됐다';
comment on column public.po_invoice.credit_for_invoice_id is '⭐ 크레딧이 어느 인보이스에 대한 것인가(Cin7 「Credit note for」 · [실물] 23537005816 → 23537005760) · self-FK · on delete no action. nullable — 인보이스와 무관한 조정 크레딧이 실제로 있다(Caleb 실측). 붙은 크레딧 → 그 인보이스의 미지급을 줄인다(RPC invoices[].credit_total) · 안 붙은 크레딧 → 쓸 수 있는 크레딧으로 남아 결제 때 po_payment_alloc 이 이 행을 가리켜 「썼다」(remaining 으로 본다). CHECK: 크레딧만 갖는다 · 자기 자신 금지. ⚠️ 「크레딧을 가리킨다 · 다른 공급처를 가리킨다 · 붙어 있는데 alloc 으로도 썼다」는 다른 행의 일이라 CHECK 로 못 걸고(트리거 없음 규약) RPC credits[].warnings 가 잡는다 — 만들기 화면이 막는다';
comment on column public.po_invoice.invoice_number is '공급처가 준 번호(인보이스: INV 2142773 · 0094204-IN · 크레딧: 23537005816) · unique (supplier_id, doc_kind, invoice_number) — [2026-09-16 ③차] 종류를 넣었다: 공급처가 크레딧 메모를 인보이스와 다른 번호 체계로 내면 같은 숫자가 겹칠 수 있다(짐작 · 실물은 다른 번호). 막았을 때의 대가(못 넣는다)가 크다. 같은 종류 안의 중복(같은 인보이스 두 번)은 여전히 막힌다(§11-g 「두 번 세지 않는다」). 한 공급처가 연도별로 번호를 다시 쓰는 경우는 미확인(짐작) — 그때 note 로';
comment on column public.po_invoice.total_amount is '⭐ 문서에 찍힌 총액(문서 통화 · **크레딧도 양수**) — 정본(§3-b 「인보이스 금액이 정본이라 장부는 맞는다」). 줄 합(goods 는 할인 체인 적용)의 계산값과 다르면 입력 오류 또는 반올림 — RPC diff 로 화면이 보여 준다. 두 곳에 적는 것이 아니라 대조값이다. ⚠️ [정정 2026-09-16 ③차] ②차 주석의 「크레딧성 음수 인보이스가 올 수 있다(짐작)」는 틀렸다 — 크레딧은 doc_kind=credit 의 별 문서이고 양수다. CHECK 는 여전히 없다(정정 문서가 올 가능성 · 짐작)';
comment on column public.po_invoice.due_date is '지급 기한 · 사람이 넣는다. 계산(invoice_date + ref_payment_term.net_days)은 ref_payment_term 34행이 채워진 뒤 화면이 제안(§10-k). 조기결제 기한(discount_days)도 그때. 미지급 목록의 정렬 축. ⚠️ 크레딧(doc_kind=credit)은 기한이 없다 — null 로 둔다';
comment on column public.po_invoice_line.is_payable is '⭐ 결제 계산에 드는 줄인가 — [2026-09-16 ③차 뜻 넓힘] 인보이스에서는 「낼 돈에 드는 줄」(실무 「인보이스에 있는 shipping cost 빼고 pay함」 §3-b Comments — 운임 줄은 false) · 크레딧에서는 「뺄 돈에 드는 줄」(예: 크레딧 노트의 운임 환급 줄을 안 받는 것으로 치면 false). 결제 충당은 문서 단위라 이 칸이 없으면 빼고 낸 인보이스가 영원히 미지급으로 남거나 사람이 「다 낸 것으로 친다」를 눌러야 한다. 인보이스 미지급 = payable 줄 합(할인 적용 후) − po_payment_alloc 합 − 붙은 크레딧의 credit_net';
comment on column public.po_invoice_line.po_line_id is '⭐ 어느 발주 라인의 청구(또는 크레딧)인가 → po_line(id) · on delete no action. nullable — 밖에서 오는 사실을 그대로 담는다(운임 · 안 시킨 것 · 조정 크레딧). [2026-09-16 ③차] 크레딧 줄도 같은 구조 — 돌려받은 물건은 goods + po_line_id 로 그 라인에 붙는다(Caleb 「시켰다 · 청구됐다 · 받았다 · 크레딧 받았다가 한 줄로」). 한 문서의 줄들이 PO-02001a 와 b 의 라인을 각각 가리킬 수 있다 — 그래서 머리에 PO 칸이 없다';
comment on table  public.po_payment_alloc is '⑤ 결제 충당 줄 — 이 결제가 어느 청구서에 얼마를 갚았나. ⭐ po_invoice **또는** po_charge 정확히 하나를 가리킨다(CHECK po_payment_alloc_target_ck). 비용 청구서(CBSA 관세 · BBE 통관)도 돈을 낸다([실측 Caleb 2026-09-16] Cin7 Purchases 에서 Paid). ⭐ [2026-09-16 ③차] po_invoice 가 크레딧(doc_kind=credit)이면 뜻이 뒤집힌다 — 갚은 게 아니라 **「이 결제에서 이 크레딧을 썼다」**(amount 는 여전히 양수 · CHECK 유지 · 부호는 RPC 가 대상 종류로 준다 · ④안). 안 붙은 크레딧(credit_for null)만 이 길로 쓴다 · 붙은 크레딧은 인보이스에서 직접 빼므로 여기 오면 두 번 깎인다(RPC warnings attached_and_used). 결제 검산: Σ인보이스 + Σ비용 = amount + discount_taken + Σ크레딧. 인보이스 미지급 = payable 줄 합 − 여기 합 − 붙은 크레딧 · 비용 미지급 = total_amount − 여기 합. ⭐ 거래 — 컷오버 때 지운다';
comment on column public.po_payment_alloc.amount is '이 대상에 충당한 금액(결제 통화) · > 0. 대상이 인보이스·비용이면 갚은 돈, 대상이 크레딧이면 **쓴 크레딧**(2026-09-16 ③차 · 부호는 RPC 가 준다). 한 결제의 검산: Σ인보이스 + Σ비용 = po_payment.amount + discount_taken + Σ크레딧(화면). 인보이스가 두 결제로 갚아질 수 있고(부분 결제) 한 결제가 문서 여럿을 갚을 수 있다';

-- ═══ ③ po_detail — 인보이스만 세고 credits[] 절을 낸다 (지금 도는 정의 20260916164539 를 그대로 가져와 필요한 곳만 바꿨다) ═══
-- 바뀐 곳: inv_ids 주석 · cred CTE 신설(inv 앞) · inv 에 doc_kind='invoice' 필터 + credit_total · pay 의 target_kind 에 credit + 대상 집합에 크레딧 · invoices[] 에 credit_total · unpaid 식 · credits[] 절 신설
create or replace function public.po_detail(p_po_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with p as (
  select * from public.po where id = p_po_id
),
lines as (
  select pl.*,
         pr.sku,
         pr.name                                   as product_name,
         up.sku                                    as entered_unit_sku,
         coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = pl.id), 0) as received_qty,
         round(pl.qty_ea * pl.unit_price, 2)       as amount
  from public.po_line pl
  join public.product pr on pr.id = pl.product_id
  left join public.product up on up.id = pl.entered_unit_product_id
  where pl.po_id = p_po_id
),
disc as (
  select * from public.po_discount where po_id = p_po_id
),
tot as (
  select coalesce((select sum(amount) from lines), 0)                        as subtotal,
         coalesce((select public.po_mul(1 - percent / 100) from disc), 1)     as factor,
         coalesce((select sum(qty_ea) from lines), 0)                         as ordered_qty,
         coalesce((select sum(received_qty) from lines), 0)                   as received_qty,
         coalesce((select sum(amount) from public.po_charge_alloc where po_id = p_po_id), 0) as charge_total
),
rcpt as (
  select rl.*, pl.line_no, pr.sku, b.name as bin_name, w.name as warehouse_name, st.name as received_by_name
  from public.po_receipt_line rl
  join public.po_line pl on pl.id = rl.po_line_id
  join public.product pr on pr.id = pl.product_id
  join public.ref_bin b on b.id = rl.bin_id
  join public.ref_warehouse w on w.id = b.warehouse_id
  left join public.ims_staff st on st.id = rl.received_by
  where pl.po_id = p_po_id
),
inv_ids as (                                  -- 이 발주의 라인을 가리키는 문서(인보이스·크레딧 둘 다 · 줄 수준 · 머리에 PO 칸 없음)
  select distinct il.po_invoice_id
  from public.po_invoice_line il
  join public.po_line pl on pl.id = il.po_line_id
  where pl.po_id = p_po_id
),
cred as (                                     -- ⭐ 크레딧(doc_kind='credit') — 이 발주의 라인을 가리키거나 · 이 발주의 인보이스를 가리키는(조정 크레딧 · 라인 없음) 것
  select c.*,
         s.name   as supplier_name,
         cur.code as currency_code,
         f.invoice_number as credit_for_number,
         f.supplier_id    as credit_for_supplier_id,
         f.doc_kind       as credit_for_doc_kind,
         (select count(*) from public.po_invoice_line x where x.po_invoice_id = c.id)::int as line_count,
         (select count(*) from public.po_invoice_line x join public.po_line pl on pl.id = x.po_line_id
           where x.po_invoice_id = c.id and pl.po_id = p_po_id)::int                       as lines_for_this_po,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = c.id and x.line_kind = 'goods')                          as goods_sum,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = c.id and x.line_kind <> 'goods')                         as other_sum,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = c.id and x.line_kind = 'goods' and x.is_payable)         as goods_payable,   -- is_payable = 뺄 돈 계산에 드는 줄
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = c.id and x.line_kind <> 'goods' and x.is_payable)        as other_payable,
         coalesce((select public.po_mul(1 - percent / 100) from public.po_invoice_discount dd
           where dd.po_invoice_id = c.id), 1)                                                as factor,           -- 크레딧 자기 할인 줄(사람이 넣었을 때만 · 자동 복사 없음)
         (select coalesce(sum(amount), 0) from public.po_payment_alloc a where a.po_invoice_id = c.id) as used  -- ⭐ alloc 이 크레딧을 가리키면 「이 결제에서 썼다」(양수)
  from public.po_invoice c
  join public.supplier s on s.id = c.supplier_id
  join public.ref_currency cur on cur.id = c.currency_id
  left join public.po_invoice f on f.id = c.credit_for_invoice_id
  where c.doc_kind = 'credit'
    and (c.id in (select po_invoice_id from inv_ids)
         or c.credit_for_invoice_id in (select po_invoice_id from inv_ids))
),
inv as (
  select i.*,
         s.name   as supplier_name,
         cur.code as currency_code,
         (select count(*) from public.po_invoice_line x where x.po_invoice_id = i.id)::int as line_count,
         (select count(*) from public.po_invoice_line x join public.po_line pl on pl.id = x.po_line_id
           where x.po_invoice_id = i.id and pl.po_id = p_po_id)::int                       as lines_for_this_po,
         -- ⭐ 할인 체인은 goods 줄에만(Caleb 2026-09-16 · other 는 공급처가 할인했는지 모른다 · 차이로 드러나면 그때 정한다)
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = i.id and x.line_kind = 'goods')                          as goods_sum,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = i.id and x.line_kind <> 'goods')                         as other_sum,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = i.id and x.line_kind = 'goods' and x.is_payable)         as goods_payable,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = i.id and x.line_kind <> 'goods' and x.is_payable)        as other_payable,
         coalesce((select public.po_mul(1 - percent / 100) from public.po_invoice_discount dd
           where dd.po_invoice_id = i.id), 1)                                                as factor,
         (select coalesce(sum(amount), 0) from public.po_payment_alloc a where a.po_invoice_id = i.id) as paid,
         -- ⭐ 이 인보이스를 가리키는(붙은) 크레딧의 뺄 돈 합 — 갚을 돈을 줄인다(Cin7 「Credit note for」 · ③ 경로)
         (select coalesce(sum(round(cn.goods_payable * cn.factor, 2) + cn.other_payable), 0)
            from cred cn where cn.credit_for_invoice_id = i.id)                               as credit_total
  from public.po_invoice i
  join public.supplier s on s.id = i.supplier_id
  join public.ref_currency cur on cur.id = i.currency_id
  where i.doc_kind = 'invoice'                                                                -- ⭐ 크레딧은 여기 안 센다(credits 절)
    and i.id in (select po_invoice_id from inv_ids)
),
chg as (
  select c.*, a.amount as alloc_amount, s.name as supplier_name, cur.code as currency_code,
         (select coalesce(sum(amount), 0) from public.po_payment_alloc pa where pa.po_charge_id = c.id) as paid
  from public.po_charge_alloc a
  join public.po_charge c on c.id = a.po_charge_id
  join public.supplier s on s.id = c.supplier_id
  join public.ref_currency cur on cur.id = c.currency_id
  where a.po_id = p_po_id
),
pay as (                                      -- 이 발주의 인보이스에 걸린 결제 + 이 발주에 배분된 비용 문서에 걸린 결제
  select pm.*, pa.amount as alloc_amount,
         case when pa.po_charge_id is not null then 'charge'
              when i.doc_kind = 'credit'        then 'credit'          -- ⭐ 크레딧을 「썼다」(양수 · 갚은 게 아니라 뺀 것)
              else 'invoice' end                                       as target_kind,
         coalesce(i.invoice_number, c.charge_number)                             as target_number,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  left join public.po_invoice i on i.id = pa.po_invoice_id
  left join public.po_charge  c on c.id = pa.po_charge_id
  where pa.po_invoice_id in (select po_invoice_id from inv_ids)
     or pa.po_invoice_id in (select id from cred)
     or pa.po_charge_id  in (select id from chg)
)
select case when not exists (select 1 from p) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', p.id, 'po_number', p.po_number, 'status', p.status, 'order_date', p.order_date,
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'currency_code', cur.code, 'exchange_rate', p.exchange_rate,
      'payment_term_name', coalesce(p.payment_term_name, pt.name),      -- 문서에 박힌 원문 우선 · 없으면 마스터 이름
      'ship_to_warehouse', w.name,
      'split_from_number', sf.po_number,
      'split_to', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'po_number', x.po_number, 'status', x.status) order by x.po_number)
                             from public.po x where x.split_from_id = p.id), '[]'::jsonb),
      'created_by_name', cb.name, 'confirmed_by_name', fb.name,
      'confirmed_at', p.confirmed_at, 'closed_at', p.closed_at, 'cancelled_at', p.cancelled_at,
      'note', p.note, 'created_at', p.created_at, 'updated_at', p.updated_at)
    from p
    join public.supplier s on s.id = p.supplier_id
    join public.ref_currency cur on cur.id = p.currency_id
    left join public.ref_payment_term pt on pt.id = p.payment_term_id
    left join public.ref_warehouse w on w.id = p.ship_to_warehouse_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = p.created_by
    left join public.ims_staff fb on fb.id = p.confirmed_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'product_id', product_id, 'sku', sku, 'product_name', product_name,
      'supplier_sku', supplier_sku, 'qty_ea', qty_ea, 'received_qty', received_qty,
      'remaining_qty', qty_ea - received_qty,                          -- ⚠️ 초과면 음수 · 그대로(설계대로)
      'entered_unit_sku', entered_unit_sku, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'tax_rule', tax_rule, 'note', note) order by line_no)
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'seq', seq, 'name', name, 'percent', percent,
                                        'supplier_discount_id', supplier_discount_id, 'note', note) order by seq)
    from disc), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'subtotal', subtotal,
      'discount_factor', round(factor, 6),                              -- ⭐ 표시용 6자리 · 아래 금액은 원래 factor 로 계산한 뒤 2자리
      'discount_amount', round(subtotal - subtotal * factor, 2),
      'net_total', round(subtotal * factor, 2),
      'charge_total', charge_total,
      'ordered_qty', ordered_qty,
      'received_qty', received_qty)
    from tot
  ),
  'receipts', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'po_line_id', po_line_id, 'line_no', line_no, 'sku', sku,
      'received_on', received_on, 'received_by_name', received_by_name,
      'bin_name', bin_name, 'warehouse_name', warehouse_name, 'qty_ea', qty_ea, 'note', note)
      order by received_on, line_no, bin_name)
    from rcpt), '[]'::jsonb),
  'invoices', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'invoice_number', invoice_number, 'invoice_date', invoice_date, 'due_date', due_date, 'status', status,
      'supplier_name', supplier_name, 'currency_code', currency_code,
      'line_count', line_count, 'lines_for_this_po', lines_for_this_po,
      'discount_factor', round(factor, 6),                                                -- 표시용 · 계산은 원래 factor
      'total_amount', total_amount,                                                       -- 찍힌 값 · 정본
      'computed_total', round(goods_sum * factor, 2) + other_sum,                          -- 계산값 (goods 만 체인)
      'diff', total_amount - (round(goods_sum * factor, 2) + other_sum),                   -- ⭐ 대조 · 0 이 아니면 입력 오류·반올림·other 할인
      'payable_net', round(goods_payable * factor, 2) + other_payable,                     -- 갚을 돈 (is_payable 줄만)
      'paid', paid,
      'credit_total', credit_total,                                                        -- ⭐ 붙은 크레딧의 뺄 돈 합
      'unpaid', (round(goods_payable * factor, 2) + other_payable) - paid - credit_total)  -- ⭐ 미지급 = 갚을 돈 − 충당 − 붙은 크레딧 · 음수면 받을 돈(credit due)
      order by invoice_date, invoice_number)
    from inv), '[]'::jsonb),
  'credits', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'credit_number', invoice_number, 'credit_date', invoice_date, 'status', status,
      'credit_for_invoice_id', credit_for_invoice_id, 'credit_for_number', credit_for_number,
      'supplier_name', supplier_name, 'currency_code', currency_code,
      'line_count', line_count, 'lines_for_this_po', lines_for_this_po,
      'discount_factor', round(factor, 6),
      'total_amount', total_amount,                                                        -- 찍힌 값(양수 · 정본)
      'computed_total', round(goods_sum * factor, 2) + other_sum,
      'diff', total_amount - (round(goods_sum * factor, 2) + other_sum),
      'credit_net', round(goods_payable * factor, 2) + other_payable,                      -- ⭐ 뺄 돈(양수 · is_payable 줄만)
      'used', used,                                                                        -- alloc 으로 쓴 합(안 붙은 크레딧의 길)
      'remaining', case when credit_for_invoice_id is null
                        then (round(goods_payable * factor, 2) + other_payable) - used     -- 안 붙은 크레딧: 아직 쓸 수 있는 금액
                        else null end,                                                     -- 붙은 크레딧: 그 인보이스의 unpaid 에 이미 반영 — remaining 없음
      'warnings', (select coalesce(jsonb_agg(w), '[]'::jsonb) from unnest(array_remove(array[
                    case when credit_for_invoice_id is not null and used > 0 then 'attached_and_used' end,        -- 붙어 있는데 alloc 으로도 썼다 → 두 번 깎인다
                    case when credit_for_doc_kind = 'credit' then 'credit_for_is_credit' end,                       -- 크레딧이 크레딧을 가리킨다
                    case when credit_for_supplier_id is not null and credit_for_supplier_id <> supplier_id then 'credit_for_other_supplier' end
                  ], null)) as w))
      order by invoice_date, invoice_number)
    from cred), '[]'::jsonb),
  'charges', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'charge_number', charge_number, 'kind', kind, 'description', description, 'charge_date', charge_date,
      'status', status, 'supplier_name', supplier_name, 'currency_code', currency_code,
      'total_amount', total_amount,
      'alloc_amount', alloc_amount,                                                        -- 이 발주에 박힌 배분 (재계산 없음)
      'paid', paid,
      'unpaid', total_amount - paid)                                                       -- 비용 문서 전체 기준
      order by charge_date, charge_number)
    from chg), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'paid_on', paid_on, 'reference', reference,
      'target_kind', target_kind, 'target_number', target_number, 'alloc_amount', alloc_amount,
      'amount', amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
      'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb)
) end;
$$;
comment on function public.po_detail(uuid) is '⑤ 발주 상세 — jsonb 하나(header · lines · discounts · totals · receipts · invoices · credits · charges · payments). ⭐ 계산 규칙의 정본: 할인 체인은 po_mul 로 곱한다(표시용 factor 는 6자리) · 라인 금액은 round(qty×단가,2) · 인보이스 체인은 goods 줄에만 · computed_total 과 찍힌 total_amount 의 diff 가 대조 · 인보이스 미지급 = is_payable 줄 합(체인 적용) − 충당 합 − 붙은 크레딧(credit_total) · 음수면 받을 돈 · 크레딧은 양수로 담고 부호는 여기서(2026-09-16 · 붙은 크레딧은 인보이스에서 빼고, 안 붙은 크레딧은 alloc 으로 「썼다」) · 비용 배분은 박힌 값 읽기만 · 입고는 줄 합. 없는 id → null. security invoker. 정본 po-module §13 · §11-e·f·g · 2026-09-16';

-- 함수 EXECUTE 는 PUBLIC 기본 부여 — create or replace 는 ACL 을 유지하지만 명시가 관례
revoke all on function public.po_detail(uuid) from public, anon;
grant execute on function public.po_detail(uuid) to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 화면(asung-ims/po.html · 대화 Claude 가 고친다)이 새로 받는 것
-- ─────────────────────────────────────────────────────────────
--   invoices[]  기존 키 + credit_total · unpaid 의 뜻이 바뀜(= payable_net − paid − credit_total · 음수면 받을 돈 → 「credit due」)
--   credits[]   id · credit_number · credit_date · status · credit_for_invoice_id · credit_for_number · supplier_name · currency_code ·
--               line_count · lines_for_this_po · discount_factor · total_amount · computed_total · diff · credit_net · used · remaining(안 붙은 것만 · 붙은 것은 null) · warnings[](빈 배열이면 정상)
--   payments[]  target_kind 에 'credit' 추가(뜻: 썼다) — 그 밖은 그대로
--   header · lines · discounts · totals · receipts · charges 는 무변 · po_list 무변
--
-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 지시서 §4 ⓓ · 예상값은 검토 Claude 계산 — 할인 줄은 자동 복사하지 않으므로 「안 함」 쪽)
-- ─────────────────────────────────────────────────────────────
-- ⓪ 적용 뒤 기존 행
--   select invoice_number, doc_kind, credit_for_invoice_id from po_invoice;                  → AMP-778812 · invoice · null
--   select conname from pg_constraint where conrelid = 'public.po_invoice'::regclass order by 1;  → …_doc_kind_ck · …_credit_for_ck · …_supplier_id_doc_kind_invoice_number_key (옛 …_supplier_id_invoice_number_key 없음)
-- ① 크레딧 하나 — AMP-778812 에 대한 것 · AMP00415 10개 돌려받음 · 할인 줄 없음 · 찍힌 총액 30.90
--   insert into po_invoice (supplier_id, doc_kind, invoice_number, invoice_date, currency_id, total_amount, status, credit_for_invoice_id, confirmed_at)
--   select i.supplier_id, 'credit', 'CN-AMP-778812-1', current_date, i.currency_id, 30.90, 'confirmed', i.id, now()
--   from po_invoice i where i.invoice_number = 'AMP-778812' returning id;
--   insert into po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price)
--   select c.id, 1, 'goods', pl.id, 10, 3.09
--   from po_invoice c, po_line pl join po p on p.id = pl.po_id join product pr on pr.id = pl.product_id
--   where c.invoice_number = 'CN-AMP-778812-1' and p.po_number = 'PO-02001a' and pr.sku = 'AMP00415';
-- ② 상세 a
--   select jsonb_pretty(po_detail((select id from po where po_number = 'PO-02001a')) -> 'invoices');
--   예상  1행 AMP-778812 · payable_net 2010.54 · paid 2010.54 · credit_total 30.90 · unpaid −30.90   ⭐ 음수 = 받을 돈(이미 다 낸 인보이스에 크레딧이 붙었다 · 맞은 결과)
--   select jsonb_pretty(po_detail((select id from po where po_number = 'PO-02001a')) -> 'credits');
--   예상  1행 CN-AMP-778812-1 · credit_for_number AMP-778812 · lines_for_this_po 1 · line_count 1 · discount_factor 1.000000 · total_amount 30.90 · computed_total 30.90 · diff 0.00 ·
--         credit_net 30.90 · used 0 · remaining null(붙은 크레딧) · warnings []
--   select jsonb_array_length(po_detail((select id from po where po_number = 'PO-02001a')) -> 'payments');   → 2 (변화 없음)
--   (할인 줄을 크레딧에 손으로 넣었다면 credit_net 25.39 · unpaid −25.39 — 이번 검증은 안 넣는 쪽)
-- ③ 뷰 무변
--   select po_number, net_total from po_list order by po_number;   → 2010.54 · 253.91 · 7985.00 (그대로)
-- ④ 유니크 — 같은 공급처 · 같은 번호 · 다른 종류는 들어간다 · 같은 종류는 막힌다
--   insert into po_invoice (supplier_id, doc_kind, invoice_number, invoice_date, currency_id, total_amount) select supplier_id, 'credit', 'AMP-778812', current_date, currency_id, 0 from po_invoice where invoice_number='AMP-778812' and doc_kind='invoice';   → 성공(종류가 다르다) · 확인 뒤 지운다
--   같은 문장을 doc_kind 'invoice' 로 → unique 위반
-- ⑤ CHECK — 인보이스에 credit_for 를 넣으면 po_invoice_credit_for_ck 위반 · 크레딧이 자기 id 를 가리키면 위반
-- ⑥ warnings — 붙은 크레딧을 alloc 으로도 쓰면 credits[0].warnings = ["attached_and_used"] (넣어 보고 지운다)
