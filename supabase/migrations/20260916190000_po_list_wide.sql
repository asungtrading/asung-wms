-- ─────────────────────────────────────────────────────────────
-- ⑤ PO 넓은 목록 — po 머리 칸 추가 · po_list 확장(국면 다섯) · po_detail 보강(캐럿) · po_create 손질 (테스트 DB Asung-IMS · 2026-09-16)
--
-- 정본: docs/design/po-module.md §13-f(다음 차수로 넘긴 것 — 이 파일이 그 첫 묶음) · §11-b(확정의 뜻) · §11-f·g(비용·인보이스가 발주 여럿에 걸친다) · §3-b B·C(주소·연락처 실측)
-- 앞 정의: po_list 20260916164539 · po_detail 20260916175003 · po_create 20260916181719 — 셋 다 create or replace 로 이어짓는다(①차 규칙 · 앞 파일은 고치지 않는다)
-- 지시서: ~/asung/prompts/po-list-wide.md · 검토 이견 1~24(2026-09-16 · 14 만 뒤집힘 — 「cancelled 는 판정을 바꾸지 않는다」 · 나머지 전부 받음)
-- ⚠️ 파일명 — 만든 시각은 18:03 인데 앞 파일이 181719 라 그 뒤에 서도록 190000 으로 붙였다(마이그레이션은 이름순으로 적용된다).
--
-- ⭐ 이번 차수가 하는 것 셋(+1)
--   ① po 표에 칸 15개 — required_by · tax_rule · tax_inclusive · inventory_account(id+code) · ⭐ 그날의 연락처 3 · 주소 6
--   ② po_list 에 칸 14개를 뒤에 붙인다 — 국면 다섯(none/partial/done) · 청구·크레딧·비용 건수 · 미지급·기납 합 · 문서 번호 검색칸 · required_by
--   ③ po_detail 에 캐럿용 배분 — charges[].allocs · invoices[].po_shares · credits[].po_shares · header 에 새 칸과 편집용 id
--   ④ po_create 가 공급처에서 따라오는 새 칸을 채운다(연락처 · 주소 · tax_rule · inventory account) — 없으면 null + warnings
--   ⭐ 헬퍼 뷰 둘 — po_invoice_money(인보이스·크레딧 한 장의 돈) · po_charge_money(비용 한 장의 돈). ⚠️⚠️ **미지급 식의 정본이 여기로 옮겨 왔다.**
--      po_list 와 po_detail 이 같은 뷰를 읽는다. 식이 두 곳에 있으면 정본이 둘이 된다(검토 이견 18 · Caleb 「지금이 옮길 때다」).
--
-- ⭐ 파일 하나인 이유 — 뷰·RPC 가 새 칸을 읽고 po_create 가 새 칸을 쓴다. 나누면 중간 상태에서 po_create 가 없는 칸에 쓴다(③차와 같은 판단).
-- ⚠️ create or replace view 는 기존 칸의 이름·순서·타입을 못 바꾼다(PG 규칙) ⇒ po_list 의 새 칸은 **전부 뒤에** 붙였다. 기존 22칸은 앞 정의 그대로.
-- ⚠️ create or replace function 은 서명이 같아야 한다 — po_detail(uuid) · po_create(uuid, uuid, date, text) 그대로.
--
-- ⭐⭐ 그날 값을 박는다 — 연락처·주소 (Caleb 2026-09-16)
--   근거: 결제조건을 payment_term_id + payment_term_name 둘로 둔 것과 같은 이유(§3-b 관례). 공급처 연락처가 나중에 바뀌어도 **그 발주는 그 사람에게 보낸 것**이다.
--         나중에 IMS 가 발주서를 메일로 보내면 「누구에게 보냈나」가 그대로 쓰인다(보내기는 나중 · 답장 받기는 지금 필요 없다).
--   ⭐ 원문만 박고 FK 는 두지 않는다(검토 이견 4) — payment_term 과 다르게 가는 이유: supplier_contact 는 「261건 그대로 옮기고 나중에 걸러서 **지운다**」(§3-b C · DELETE 열림).
--      FK no action 이면 발주가 가리킨 행을 못 지워 정리가 막히고, set null 은 거래 표 규약(밖 FK 전부 no action · §5)의 새 예외다. 원문이 있으면 FK 가 주는 것(어디서 왔나)이 거의 없다.
--   ⭐ 주소는 여섯 칸 그대로(한 줄로 합치지 않는다) — 나중에 문서(PDF·메일)에 다시 찍으려면 되돌릴 수 있어야 한다. ref_warehouse 도 여섯 칸.
--   ⭐ 이메일을 담는다 — 발주서 메일이 쓰는 유일한 칸. mobile·fax·website 는 안 담는다(Cin7 머리 실물도 Contact·Phone 둘).
--   ❌ blind_receipt 없음(Caleb) · ❌ 다른 배송지(드롭십) 칸 없음(검토 이견 7) — 주소 칸은 쉬운 부분이고, 어려운 부분은 po_receipt_line.bin_id NOT NULL 이라
--      우리 창고에 안 들어오는 물건은 **입고 줄을 세울 수 없다**는 점(원장 사건도 나가면 안 된다). 주소만 두면 「받을 수 없는 발주」가 생긴다. Cin7 에 실물이 있는지 실측이 먼저(⬜).
--
-- ⭐ tax_rule — 머리가 기본값 · 줄이 덮는다 · 줄 null = 머리를 따른다 (검토 이견 2 · [실측 2026-09-16] po_line.tax_rule 47개 전부 null · po_lines_paste 는 줄 tax_rule 을 안 쓴다 · product.purchase_tax_rule 0행)
--   머리는 po_create 가 supplier.tax_rule 을 그날 값으로 복사한다([실측] 활성 226/226 채움 · Zero-rated (Purchase) 149 최다).
--   ⚠️ 세금 **계산**은 이번 범위 밖 — ref_tax_rule 이 없어 세율을 모른다(§7-a 미결). tax_inclusive 도 기록만 · totals 에 반영하지 않는다.
--
-- ⭐ inventory_account — 공급처도 제품도 아니고 회사 기본값 하나 (검토 이견 3 · [실측 2026-09-16] product.inventory_account_code 는 1곳뿐이고 그것도 _58_ · supplier 에는 account_payable 만)
--   ⇒ inv_config 'po_inventory_account_code' = '_59_'(Inventory Asset · §8 실재 확인)를 심고 po_create 가 ref_account.code 로 푼다. FK + 원문 코드(product 계정 넷의 id+code 관례).
--   함수 안에 '_59_' 를 박지 않는 이유 — §7 이 inv-cost 의 계정 하드코딩을 이미 부채로 적었다. inv_config 는 base_currency · baseline_snapshot_key 둘뿐 — 셋째를 심는 것이 선례에 맞다(Caleb).
--
-- ⭐⭐ 국면 다섯 — 판정 규칙 (Caleb 2026-09-16 · 계산 규칙은 한곳 §13 ⇒ 뷰가 문자열로 내고 금액·수량도 함께 준다 · 검토 이견 11)
--   값     'none'(아직 · 회색) · 'partial'(일부 · 주황) · 'done'(다 됐다 · 초록) — 넓은 목록에서만 그린다(화면)
--   주문   ⭐ **상태가 아니라 사실로 판정한다**(Caleb · 이견 14 정정) — 라인 0 이면 none · 라인이 있는데 확정 전이면 partial · 확정됐으면 done.
--          「확정 전」은 status='draft' 또는 (status='cancelled' 이고 confirmed_at is null). ⚠️ cancelled 는 판정을 **바꾸지 않는다** — 취소는 진행도가 아니라 종료다.
--          라인 13개짜리 PO-02005 가 취소됐는데 주문이 회색이면 「아무것도 안 한 발주」로 보인다. 실제로는 만들었다가 접은 것이다. 취소는 상태 칩이 따로 보여 준다.
--          ⚠️ 확정을 눌렀는데 라인이 없는 문서도 가능하다(Confirm 은 PostgREST update · 검사 없음) — 그 경우 none 이 맞다(라인이 없다는 사실).
--   청구   ⭐ **금액이 아니라 수량으로 판정한다**(검토 이견 12 · Caleb 「맞다」) — 인보이스 단가는 발주 단가와 자주 다르고(§11-d) 할인은 문서 단위라 발주 몫으로 못 내린다.
--          금액으로 재면 다 청구됐는데 영원히 「일부」가 된다. 이 발주 라인을 가리키는 goods 줄 qty_ea 합(invoiced_qty) vs ordered_qty — 0 이면 none · 미만 partial · 이상 done.
--          취소 안 된 인보이스는 draft 도 센다(존재하는 문서다). 크레딧은 빼지 않는다(진행도가 아니라 「이런 일이 있었다」 — 태그 · credit_count).
--          invoiced_total(할인 전 · 이 발주 몫 줄 합)·invoice_count 는 표시용.
--   입고   received_qty(입고 줄 합) vs ordered_qty — 0 이면 none · 미만 partial · 이상 done(초과 포함 · §13 설계대로).
--   비용   취소 안 된 비용 배분이 하나라도 있으면 done · 없으면 none — partial 없음. ⚠️ 국내 발주는 비용이 없어 늘 회색 — **구별하지 않는다**(Caleb).
--   결제   ⭐⭐ **문서 기준**(검토 이견 13) — 이 발주에 걸린 인보이스·비용 **문서**의 미지급 합. 인보이스 하나가 발주 둘에 걸치면 그 미지급은 두 발주 행에 **둘 다** 보인다
--          (po_detail invoices[].unpaid 와 같은 기준 · 배분 없는 것을 비례로 나누면 새 계산 규칙이 생긴다).
--          ⚠️⚠️ 그래서 목록의 unpaid_total·paid_total 을 **세로로 더하면 안 된다 — 두 번 센다.** 화면에도 같은 주석을 단다(말만 · Caleb 「안 적으면 두 번 센다」).
--          판정: 걸린 문서(인보이스+비용 · 취소 제외)가 없으면 none · unpaid_total > 0 이면 (paid_total > 0 ? partial : none) · unpaid_total ≤ 0 이면 done.
--          ⭐ 음수 미지급(받을 돈 · 크레딧)은 done + 음수 금액 그대로 — 화면은 이미 「credit due」를 그린다(po.html 4ae86d6).
--   ⚠️ 취소된 인보이스·크레딧·비용은 국면·건수·미지급에서 **뺀다.** 앞 po_detail 정의는 status 를 안 봤다(검증 데이터에 cancelled 문서가 없어 값은 무변) —
--      이번에 헬퍼 뷰의 credit_total 도 취소된 크레딧을 뺀다(취소한 크레딧이 미지급을 줄이면 틀린다). 문서 목록(invoices[]·credits[]·charges[])에는 취소된 것도 status 와 함께 그대로 보인다.
--
-- ⭐ 검색 — doc_numbers text 한 칸(검토 이견 16) — 이 발주에 걸린 인보이스·크레딧·비용 번호를 공백으로 모은 것(취소 포함 · 찾는 데는 상태가 상관없다).
--   화면의 .or(po_number.ilike, supplier_name.ilike) 에 doc_numbers.ilike 한 항만 더하면 된다. 배열 칸은 PostgREST 에서 cs(정확 일치)만 되고 ilike 가 안 듣는다. 인덱스는 안 듣는다(앞 뷰와 같은 짐작).
-- ⭐ 빠른 필터 — 아직 안 온 것 = status=confirmed & receipt_phase<>'done'(+ required_by 정렬 · 이견 1) · 미지급 있는 것 = unpaid_total > 0. 뷰 칸으로 충분하다.
-- ⚠️ 무게 — 짐작. 지금 행이 여덟이라 못 잰다. CTE 마다 FK 인덱스가 있는 group by 라 수천 건까지 체감 없을 것으로 본다. 상관 서브쿼리 대신 문서별 집계 뒤 조인.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po — 머리 칸 15개 ═══
alter table public.po
  add column if not exists required_by             date,                                                                 -- ⭐ 납기 희망일(Caleb 「required by 는 필요해」) · Cin7 목록에도 열이 있다
  add column if not exists tax_rule                text,                                                                 -- 문서 기본 세금규칙 원문 · 줄(po_line.tax_rule)이 null 이면 이것을 따른다
  add column if not exists tax_inclusive           boolean not null default false,                                       -- Cin7 Tax inclusive 체크 · 기록만(계산 없음)
  add column if not exists inventory_account_id    uuid references public.ref_account (id) on delete no action,          -- FK + 원문 코드 병행(product 계정 넷 관례)
  add column if not exists inventory_account_code  text,
  add column if not exists supplier_contact_name   text,                                                                 -- ⭐ 그날의 연락처 — 원문만 · FK 없음(머리 주석)
  add column if not exists supplier_contact_phone  text,
  add column if not exists supplier_contact_email  text,
  add column if not exists supplier_address_line1  text,                                                                 -- ⭐ 그날의 주소 — 여섯 칸 그대로(ref_warehouse 와 같은 낱말)
  add column if not exists supplier_address_line2  text,
  add column if not exists supplier_city           text,
  add column if not exists supplier_state_province text,
  add column if not exists supplier_postal_code    text,
  add column if not exists supplier_country        text;

create index if not exists po_inventory_account_id_idx on public.po (inventory_account_id);   -- FK 인덱스(§5)
create index if not exists po_required_by_idx          on public.po (required_by);            -- 「아직 안 온 것」 정렬 축

comment on column public.po.required_by             is '⭐ 납기 희망일(Cin7 Required by · Caleb 2026-09-16 「필요해」). nullable — 작성 중에는 비어 있다. 「아직 안 온 것」 빠른 필터의 정렬·지연 축(po_list 도 낸다 · 화면 열로 그릴지는 화면이 정한다)';
comment on column public.po.tax_rule                is '문서 기본 세금규칙 원문 — po_create 가 supplier.tax_rule 을 그날 값으로 복사한다([실측 2026-09-16] 활성 226/226 채움). ⭐ 줄(po_line.tax_rule)이 null 이면 이것을 따르고, 줄에 값이 있으면 줄이 덮는다([실측] po_line.tax_rule 47개 전부 null · po_lines_paste 는 줄 tax_rule 을 안 쓴다). ⚠️ 세금 계산은 없다 — ref_tax_rule 미결(§7-a)이라 세율을 모른다. Cin7 은 필수(*)지만 여기는 nullable(막히면 등록이 안 된다 · §3-c 와 같은 판단)';
comment on column public.po.tax_inclusive           is 'Cin7 Tax inclusive 체크 · default false · 기록만. totals 에 반영하지 않는다(세율이 없다) — ref_tax_rule 이 서면 그때';
comment on column public.po.inventory_account_id    is '재고 자산 계정 → ref_account(id) · nullable. ⭐ 원천은 공급처도 제품도 아니고 회사 기본값 하나 — inv_config po_inventory_account_code(_59_ Inventory Asset)를 po_create 가 ref_account.code 로 푼다([실측 2026-09-16] product.inventory_account_code 는 1곳뿐이고 _58_ · supplier 에는 account_payable 만). 없으면 null + warnings inventory_account_unset';
comment on column public.po.inventory_account_code  is '재고 자산 계정 원문 코드(ref_account.code · 예 _59_) — FK 와 병행(product 계정 넷의 id+code 관례). FK 가 못 붙어도 여기는 남는다';
comment on column public.po.supplier_contact_name   is '⭐ 그날의 연락처 이름 — supplier_contact 에서 po_create 가 복사(규칙: 활성 중 is_default 가 정확히 하나면 그것 · 아니면 활성이 정확히 하나면 그것 · 그 외 null + warnings contact_unset/contact_ambiguous · [실측 2026-09-16] 활성 226 중 기본 하나 159 · 기본 없이 하나 20 · 0건 44 ⇒ 179 곳을 덮는다). ⭐ 원문만 · FK 없음 — supplier_contact 는 나중에 걸러 지우는 표(§3-b C)라 FK 가 정리를 막는다. 나중에 발주서를 메일로 보낼 때 「누구에게 보냈나」가 이 칸이다. ⚠️ 회사 이름·메모가 든 행(「Acquired by …」 류)을 규칙으로 골라내지 않는다 — 정리의 일이다';
comment on column public.po.supplier_contact_phone  is '그날의 연락처 전화(supplier_contact.phone 원문 · mobile 은 안 담는다)';
comment on column public.po.supplier_contact_email  is '⭐ 그날의 연락처 이메일(supplier_contact.email 원문) — 발주서 메일 보내기(⬜ 나중)가 쓰는 유일한 칸. 답장 받기는 지금 필요 없다(Caleb 2026-09-16)';
comment on column public.po.supplier_address_line1  is '⭐ 그날의 공급처 주소(Cin7 Vendor address) — supplier_address 에서 po_create 가 복사(규칙 §3-b B: 활성 1건이면 그것 · 여럿이면 Billing 이 정확히 하나면 그것 · 그 외 null + warnings address_unset/address_ambiguous). ⚠️ [실측 2026-09-16] 활성 226 중 주소 0건이 143 ⇒ 경고가 대다수에서 뜬다 — 화면이 오류처럼 그리면 안 된다. 여섯 칸 그대로(한 줄로 합치지 않는다 — 문서에 다시 찍으려면 되돌릴 수 있어야 한다) · 원문만 · FK 없음';
comment on column public.po.supplier_address_line2  is '그날의 주소 둘째 줄(supplier_address.line2 · 실측 9/87 만 채움)';
comment on column public.po.supplier_city           is '그날의 주소 도시';
comment on column public.po.supplier_state_province is '그날의 주소 주/도';
comment on column public.po.supplier_postal_code    is '그날의 주소 우편번호';
comment on column public.po.supplier_country        is '그날의 주소 나라';

-- inv_config 셋째 키 — 재고 자산 계정 기본값 (base_currency 와 같은 방식 · 재실행 안전 · FK 없음)
insert into public.inv_config (key, value, note) values
  ('po_inventory_account_code', '_59_', '⑤ 발주 머리 inventory_account 기본값 · ref_account.code 를 가리킨다(FK 없음 — key-value 표) · _59_ Inventory Asset(§8 실재 확인) · po_create 가 푼다 · 함수에 박지 않는 이유는 §7(inv-cost 하드코딩 부채) · 2026-09-16')
on conflict (key) do nothing;

-- ═══ ② 헬퍼 뷰 — 문서 한 장의 돈 (⭐⭐ 미지급 식의 정본 · po_list 와 po_detail 이 같이 읽는다) ═══
-- po_invoice_money — 인보이스·크레딧(doc_kind 둘 다) 한 행마다 한 행. 식은 앞 po_detail(175003)의 inv·cred CTE 를 그대로 옮긴 것 — 값이 바뀌면 안 된다(검증 ②).
--   goods_sum · other_sum       줄마다 round(qty×단가,2) 합 · goods(할인 체인 대상) / 그 밖(charge·other · 체인 안 곱한다 · Caleb 2026-09-16)
--   goods_payable · other_payable  is_payable 줄만(인보이스: 낼 돈 · 크레딧: 뺄 돈)
--   factor                      po_invoice_discount 체인(po_mul · 없으면 1)
--   computed_total · diff       계산값과 찍힌 total_amount 의 대조
--   payable_net                 round(goods_payable×factor,2) + other_payable — 인보이스는 갚을 돈 · 크레딧은 뺄 돈(credit_net)
--   alloc_total                 po_payment_alloc 합 — 인보이스는 paid · 크레딧은 used(「썼다」 · ③차 ④안)
--   credit_total                (인보이스만) 이 인보이스를 가리키는 **취소 안 된** 크레딧의 payable_net 합 · 크레딧 행은 0
--   unpaid                      (인보이스만) payable_net − alloc_total − credit_total · 음수면 받을 돈 · 크레딧 행은 null
--   remaining                   (안 붙은 크레딧만) payable_net − alloc_total · 붙은 크레딧·인보이스는 null
create or replace view public.po_invoice_money
  with (security_invoker = true) as
with l as (
  select po_invoice_id,
         count(*)::int                                                                                       as line_count,
         coalesce(sum(round(qty_ea * unit_price, 2)) filter (where line_kind = 'goods'), 0)                  as goods_sum,
         coalesce(sum(round(qty_ea * unit_price, 2)) filter (where line_kind <> 'goods'), 0)                 as other_sum,
         coalesce(sum(round(qty_ea * unit_price, 2)) filter (where line_kind = 'goods' and is_payable), 0)   as goods_payable,
         coalesce(sum(round(qty_ea * unit_price, 2)) filter (where line_kind <> 'goods' and is_payable), 0)  as other_payable
  from public.po_invoice_line
  group by po_invoice_id
),
d as (
  select po_invoice_id, public.po_mul(1 - percent / 100) as factor
  from public.po_invoice_discount
  group by po_invoice_id
),
a as (
  select po_invoice_id, coalesce(sum(amount), 0) as alloc_total
  from public.po_payment_alloc
  where po_invoice_id is not null
  group by po_invoice_id
),
base as (
  select i.id, i.doc_kind, i.status, i.credit_for_invoice_id, i.total_amount,
         coalesce(l.line_count, 0)     as line_count,
         coalesce(l.goods_sum, 0)      as goods_sum,
         coalesce(l.other_sum, 0)      as other_sum,
         coalesce(l.goods_payable, 0)  as goods_payable,
         coalesce(l.other_payable, 0)  as other_payable,
         coalesce(d.factor, 1)         as factor,
         coalesce(a.alloc_total, 0)    as alloc_total
  from public.po_invoice i
  left join l on l.po_invoice_id = i.id
  left join d on d.po_invoice_id = i.id
  left join a on a.po_invoice_id = i.id
),
calc as (
  select b.*,
         round(b.goods_sum * b.factor, 2) + b.other_sum          as computed_total,
         round(b.goods_payable * b.factor, 2) + b.other_payable  as payable_net
  from base b
),
cr as (                                        -- 인보이스에 붙은 크레딧의 뺄 돈 합 (취소 제외)
  select credit_for_invoice_id as invoice_id, coalesce(sum(payable_net), 0) as credit_total
  from calc
  where doc_kind = 'credit' and status <> 'cancelled' and credit_for_invoice_id is not null
  group by credit_for_invoice_id
)
select
  c.id, c.doc_kind, c.status, c.credit_for_invoice_id, c.total_amount,
  c.line_count, c.goods_sum, c.other_sum, c.goods_payable, c.other_payable,
  c.factor,                                                              -- ⚠️ 원래 factor(40자리까지) · 표시는 읽는 쪽이 round(…,6)
  c.computed_total,
  c.total_amount - c.computed_total                                      as diff,
  c.payable_net,
  c.alloc_total,
  case when c.doc_kind = 'invoice' then coalesce(cr.credit_total, 0) else 0 end                          as credit_total,
  case when c.doc_kind = 'invoice' then c.payable_net - c.alloc_total - coalesce(cr.credit_total, 0) end  as unpaid,
  case when c.doc_kind = 'credit' and c.credit_for_invoice_id is null then c.payable_net - c.alloc_total end as remaining
from calc c
left join cr on cr.invoice_id = c.id;

comment on view public.po_invoice_money is '⑤ 인보이스·크레딧 한 장의 돈 — ⭐⭐ 미지급 식의 정본(2026-09-16 · po_detail 에서 옮겨 옴 · po_list 와 po_detail 이 같이 읽는다 · 두 곳에 식이 있으면 정본이 둘). 줄 금액 round(qty×단가,2) · 할인 체인은 goods 줄에만(po_mul) · payable_net = is_payable 줄 합(체인 적용) · 인보이스 unpaid = payable_net − 충당(alloc_total) − 붙은 크레딧(credit_total · 취소 제외) · 음수면 받을 돈 · 크레딧 remaining = 안 붙은 것만 payable_net − 쓴 합. factor 는 원래 값 — 표시는 읽는 쪽이 6자리로. security_invoker. 정본 po-module §13 · §11-g';

revoke all on public.po_invoice_money from anon;
grant select on public.po_invoice_money to authenticated;

-- po_charge_money — 비용 한 장의 돈 (문서 기준 · 배분은 po_charge_alloc 에 박힌 값 · 재계산 없음 §11-f)
create or replace view public.po_charge_money
  with (security_invoker = true) as
select c.id, c.status, c.total_amount,
       coalesce(p.paid, 0)                          as paid,
       c.total_amount - coalesce(p.paid, 0)         as unpaid,           -- 문서 전체 기준(앞 po_detail charges[].unpaid 와 같다)
       coalesce(al.alloc_sum, 0)                    as alloc_sum,        -- 발주들에 박은 배분 합
       c.total_amount - coalesce(al.alloc_sum, 0)   as unallocated       -- 아직 어느 발주에도 안 간 몫 · 0 이 정상 · ⬜ 비용 목록 화면(만들기 차수)이 쓴다
from public.po_charge c
left join (select po_charge_id, sum(amount) as paid      from public.po_payment_alloc where po_charge_id is not null group by po_charge_id) p  on p.po_charge_id  = c.id
left join (select po_charge_id, sum(amount) as alloc_sum from public.po_charge_alloc  group by po_charge_id)                                   al on al.po_charge_id = c.id;

comment on view public.po_charge_money is '⑤ 비용 청구서 한 장의 돈 — paid = 충당 합 · unpaid = total_amount − paid(문서 전체 기준) · alloc_sum = 발주들에 박은 배분 합 · unallocated = 총액 − 배분 합(0 이 정상 · 안 붙은 청구서는 ⬜ 비용 목록 화면에서). po_list 와 po_detail 이 같이 읽는다. security_invoker. 정본 po-module §11-f · §13 · 2026-09-16';

revoke all on public.po_charge_money from anon;
grant select on public.po_charge_money to authenticated;

-- ═══ ③ po_list — 기존 22칸 그대로 + 뒤에 14칸 ═══
-- 앞 정의(164539)의 CTE l·r·d·c·sp 와 select 22칸은 그대로. 새 CTE: il(문서↔발주 · 줄 수준) · inv · cred · chg · nums.
create or replace view public.po_list
  with (security_invoker = true) as
with l as (                                   -- 라인 합
  select po_id,
         count(*)::int                                      as line_count,
         coalesce(sum(qty_ea), 0)                           as ordered_qty,
         coalesce(sum(round(qty_ea * unit_price, 2)), 0)    as subtotal
  from public.po_line
  group by po_id
),
r as (                                        -- 입고 합
  select pl.po_id, coalesce(sum(rl.qty_ea), 0) as received_qty
  from public.po_receipt_line rl
  join public.po_line pl on pl.id = rl.po_line_id
  group by pl.po_id
),
d as (                                        -- 할인 체인
  select po_id, public.po_mul(1 - percent / 100) as factor
  from public.po_discount
  group by po_id
),
c as (                                        -- 붙은 비용 (박힌 배분 금액의 합 · 앞 정의 그대로 · 상태 무관)
  select po_id, coalesce(sum(amount), 0) as charge_total
  from public.po_charge_alloc
  group by po_id
),
sp as (                                       -- 갈라져 나간 문서 수
  select split_from_id as po_id, count(*)::int as split_to_count
  from public.po
  where split_from_id is not null
  group by split_from_id
),
il as (                                       -- ⭐ 문서 ↔ 발주 (줄 수준 · §11-g 머리에 PO 칸 없음) · 문서마다 발주마다 한 행 · goods 줄만 센다
  select x.po_invoice_id, pl.po_id,
         coalesce(sum(x.qty_ea)                          filter (where x.line_kind = 'goods'), 0) as goods_qty,
         coalesce(sum(round(x.qty_ea * x.unit_price, 2)) filter (where x.line_kind = 'goods'), 0) as goods_amount
  from public.po_invoice_line x
  join public.po_line pl on pl.id = x.po_line_id
  group by x.po_invoice_id, pl.po_id
),
inv as (                                      -- 이 발주에 걸린 인보이스(취소 제외) · 돈은 문서 기준(⚠️ 세로로 더하지 마라)
  select x.po_id,
         count(*)::int                        as invoice_count,
         coalesce(sum(x.goods_qty), 0)        as invoiced_qty,
         coalesce(sum(x.goods_amount), 0)     as invoiced_total,       -- 할인 전 · 이 발주 몫 줄 합
         coalesce(sum(m.alloc_total), 0)      as paid,
         coalesce(sum(m.unpaid), 0)           as unpaid
  from il x
  join public.po_invoice i on i.id = x.po_invoice_id
  join public.po_invoice_money m on m.id = i.id
  where i.doc_kind = 'invoice' and i.status <> 'cancelled'
  group by x.po_id
),
cred as (                                     -- 이 발주에 걸린 크레딧(취소 제외) — 줄이 이 발주를 가리키거나 · 이 발주의 인보이스에 붙은 것(po_detail cred 와 같은 집합)
  select po_id, count(*)::int as credit_count
  from (
    select x.po_id, x.po_invoice_id as credit_id
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    where k.doc_kind = 'credit' and k.status <> 'cancelled'
    union
    select x.po_id, k.id
    from public.po_invoice k
    join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.doc_kind = 'credit' and k.status <> 'cancelled'
  ) u
  group by po_id
),
chg as (                                      -- 이 발주에 배분된 비용(취소 제외) · 돈은 문서 기준
  select a.po_id,
         count(*)::int                 as charge_count,
         coalesce(sum(m.paid), 0)      as paid,
         coalesce(sum(m.unpaid), 0)    as unpaid
  from public.po_charge_alloc a
  join public.po_charge c on c.id = a.po_charge_id
  join public.po_charge_money m on m.id = c.id
  where c.status <> 'cancelled'
  group by a.po_id
),
nums as (                                     -- 검색용 문서 번호 모음(인보이스·크레딧·비용 · 취소 포함 — 찾는 데는 상태가 상관없다)
  select po_id, string_agg(distinct num, ' ' order by num) as doc_numbers
  from (
    select x.po_id, k.invoice_number as num
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    union
    select x.po_id, k.invoice_number
    from public.po_invoice k join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.doc_kind = 'credit'
    union
    select a.po_id, c.charge_number
    from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id
  ) u
  group by po_id
)
select
  -- ── 기존 22칸 · 이름·순서·타입 그대로 (create or replace 규칙) ──
  p.id,
  p.po_number,
  p.status,
  p.order_date,
  p.supplier_id,
  s.name                                                       as supplier_name,
  cur.code                                                     as currency_code,
  coalesce(l.line_count, 0)                                    as line_count,
  coalesce(l.ordered_qty, 0)                                   as ordered_qty,
  coalesce(r.received_qty, 0)                                  as received_qty,
  coalesce(l.subtotal, 0)                                      as subtotal,
  round(coalesce(d.factor, 1), 6)                              as discount_factor,
  round(coalesce(l.subtotal, 0) * coalesce(d.factor, 1), 2)    as net_total,
  coalesce(c.charge_total, 0)                                  as charge_total,
  sf.po_number                                                 as split_from_number,
  coalesce(sp.split_to_count, 0)                               as split_to_count,
  p.confirmed_at,
  p.closed_at,
  p.cancelled_at,
  p.note,
  p.created_at,
  p.updated_at,
  -- ── 새 14칸 (2026-09-16 · 뒤에만 붙인다) ──
  p.required_by,                                                                                       -- 이견 1 · 「아직 안 온 것」 정렬 축 · 화면 열로 그릴지는 화면이
  coalesce(inv.invoice_count, 0)                               as invoice_count,                       -- 취소 제외
  coalesce(inv.invoiced_qty, 0)                                as invoiced_qty,                        -- goods 줄 qty_ea 합(이 발주 라인을 가리키는 것) · 청구 국면의 축
  coalesce(inv.invoiced_total, 0)                              as invoiced_total,                      -- 할인 전 · 표시용
  coalesce(cred.credit_count, 0)                               as credit_count,                        -- ⭐ 국면이 아니다 — 발주번호 옆 태그(split 과 같은 자리)
  coalesce(chg.charge_count, 0)                                as charge_count,                        -- 취소 제외
  coalesce(inv.paid, 0) + coalesce(chg.paid, 0)                as paid_total,                          -- ⚠️⚠️ 문서 기준 · 세로로 더하지 마라(두 발주에 걸친 문서는 둘 다에 있다)
  coalesce(inv.unpaid, 0) + coalesce(chg.unpaid, 0)            as unpaid_total,                        -- ⚠️⚠️ 같다 · 음수면 받을 돈(credit due)
  nums.doc_numbers,                                                                                    -- 검색용 · .ilike 한 항
  case when coalesce(l.line_count, 0) = 0                                                   then 'none'
       when p.status = 'draft' or (p.status = 'cancelled' and p.confirmed_at is null)       then 'partial'
       else 'done' end                                         as order_phase,                         -- ⭐ 사실로 판정 · cancelled 는 바꾸지 않는다(Caleb)
  case when coalesce(inv.invoiced_qty, 0) = 0                                               then 'none'
       when inv.invoiced_qty < coalesce(l.ordered_qty, 0)                                   then 'partial'
       else 'done' end                                         as invoice_phase,                       -- ⭐ 수량으로(이견 12)
  case when coalesce(r.received_qty, 0) = 0                                                 then 'none'
       when r.received_qty < coalesce(l.ordered_qty, 0)                                     then 'partial'
       else 'done' end                                         as receipt_phase,                       -- 초과 입고도 done
  case when coalesce(chg.charge_count, 0) = 0                                               then 'none'
       else 'done' end                                         as charge_phase,                        -- partial 없음 · 국내 발주는 늘 none(구별하지 않는다)
  case when coalesce(inv.invoice_count, 0) + coalesce(chg.charge_count, 0) = 0              then 'none'
       when coalesce(inv.unpaid, 0) + coalesce(chg.unpaid, 0) > 0
            then case when coalesce(inv.paid, 0) + coalesce(chg.paid, 0) > 0 then 'partial' else 'none' end
       else 'done' end                                         as payment_phase                        -- ⭐ 문서 기준(이견 13) · 음수(받을 돈)는 done
from public.po p
join public.supplier     s   on s.id   = p.supplier_id
join public.ref_currency cur on cur.id = p.currency_id
left join l    on l.po_id    = p.id
left join r    on r.po_id    = p.id
left join d    on d.po_id    = p.id
left join c    on c.po_id    = p.id
left join public.po sf on sf.id = p.split_from_id
left join sp   on sp.po_id   = p.id
left join inv  on inv.po_id  = p.id
left join cred on cred.po_id = p.id
left join chg  on chg.po_id  = p.id
left join nums on nums.po_id = p.id;

comment on view public.po_list is '⑤ 발주 목록 — PostgREST 로 표처럼 읽는다(.range()+count:exact · .ilike · .order · §10-j 3-a). security_invoker. 기존 22칸(subtotal · discount_factor 6자리 · net_total · charge_total · received_qty …)은 164539 그대로. ⭐ [2026-09-16 넓은 목록] 뒤에 14칸 — required_by · invoice_count · invoiced_qty · invoiced_total(할인 전) · credit_count(태그 · 국면 아님) · charge_count · paid_total · unpaid_total · doc_numbers(검색 · .ilike) · 국면 다섯 order/invoice/receipt/charge/payment_phase(none/partial/done). 판정: 주문은 사실로(라인 0 none · 확정 전 partial · 확정 done · cancelled 는 안 바꾼다) · 청구는 수량(invoiced_qty vs ordered_qty) · 입고는 수량(초과 done) · 비용은 있으면 done · 결제는 문서 기준 미지급(≤0 done · 음수는 받을 돈). ⚠️⚠️ paid_total·unpaid_total 은 문서 기준 — 발주 둘에 걸친 문서는 둘 다에 보인다 · **세로로 더하면 두 번 센다.** 취소된 문서는 국면·건수·돈에서 뺀다(doc_numbers 는 포함). 돈의 정본은 po_invoice_money · po_charge_money. 검색 인덱스는 안 듣는다(짐작). 정본 po-module §13 · §13-f · 2026-09-16';

revoke all on public.po_list from anon;
grant select on public.po_list to authenticated;

-- ═══ ④ po_detail(p_po_id) — 헬퍼 뷰를 읽고 · 캐럿용 배분을 더하고 · header 에 새 칸과 편집용 id ═══
-- 바뀐 곳(175003 대비): inv·cred 가 po_invoice_money 를 읽는다(식 이동 · 값 무변) · chg 가 po_charge_money 를 읽는다 · header 에 20칸 추가 ·
--   invoices[].po_shares · credits[].po_shares · charges[].allocs 신설 · 그 밖 키·순서·계산은 그대로.
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
shares as (                                   -- ⭐ 캐럿용 — 문서 하나가 어느 발주에 몇 줄·몇 개·얼마(할인 전 줄 합)씩 걸렸나 (§11-g 인보이스 하나가 발주 둘에)
  select il.po_invoice_id, pl.po_id, x.po_number, x.status as po_status,
         count(*)::int                                                           as line_count,
         coalesce(sum(il.qty_ea) filter (where il.line_kind = 'goods'), 0)       as qty_ea,
         coalesce(sum(round(il.qty_ea * il.unit_price, 2)), 0)                   as amount
  from public.po_invoice_line il
  join public.po_line pl on pl.id = il.po_line_id
  join public.po x on x.id = pl.po_id
  where il.po_invoice_id in (select po_invoice_id from inv_ids)
     or il.po_invoice_id in (select k.id from public.po_invoice k where k.doc_kind = 'credit' and k.credit_for_invoice_id in (select po_invoice_id from inv_ids))
  group by il.po_invoice_id, pl.po_id, x.po_number, x.status
),
cred as (                                     -- ⭐ 크레딧 — 이 발주의 라인을 가리키거나 · 이 발주의 인보이스를 가리키는(조정 크레딧 · 라인 없음) 것 · 돈은 po_invoice_money
  select c.*,
         s.name   as supplier_name,
         cur.code as currency_code,
         f.invoice_number as credit_for_number,
         f.supplier_id    as credit_for_supplier_id,
         f.doc_kind       as credit_for_doc_kind,
         m.line_count, m.goods_sum, m.other_sum, m.factor, m.computed_total, m.diff,
         m.payable_net    as credit_net,
         m.alloc_total    as used,
         m.remaining,
         (select count(*) from public.po_invoice_line x join public.po_line pl on pl.id = x.po_line_id
           where x.po_invoice_id = c.id and pl.po_id = p_po_id)::int                       as lines_for_this_po
  from public.po_invoice c
  join public.po_invoice_money m on m.id = c.id
  join public.supplier s on s.id = c.supplier_id
  join public.ref_currency cur on cur.id = c.currency_id
  left join public.po_invoice f on f.id = c.credit_for_invoice_id
  where c.doc_kind = 'credit'
    and (c.id in (select po_invoice_id from inv_ids)
         or c.credit_for_invoice_id in (select po_invoice_id from inv_ids))
),
inv as (                                      -- 인보이스만 · 돈은 po_invoice_money(⭐ 식의 정본이 거기로 갔다)
  select i.*,
         s.name   as supplier_name,
         cur.code as currency_code,
         m.line_count, m.goods_sum, m.other_sum, m.factor, m.computed_total, m.diff, m.payable_net,
         m.alloc_total as paid,
         m.credit_total,
         m.unpaid,
         (select count(*) from public.po_invoice_line x join public.po_line pl on pl.id = x.po_line_id
           where x.po_invoice_id = i.id and pl.po_id = p_po_id)::int                       as lines_for_this_po
  from public.po_invoice i
  join public.po_invoice_money m on m.id = i.id
  join public.supplier s on s.id = i.supplier_id
  join public.ref_currency cur on cur.id = i.currency_id
  where i.doc_kind = 'invoice'
    and i.id in (select po_invoice_id from inv_ids)
),
chg as (                                      -- 이 발주에 배분된 비용 · 돈은 po_charge_money
  select c.*, a.amount as alloc_amount, s.name as supplier_name, cur.code as currency_code,
         m.paid, m.unpaid, m.alloc_sum, m.unallocated
  from public.po_charge_alloc a
  join public.po_charge c on c.id = a.po_charge_id
  join public.po_charge_money m on m.id = c.id
  join public.supplier s on s.id = c.supplier_id
  join public.ref_currency cur on cur.id = c.currency_id
  where a.po_id = p_po_id
),
pay as (                                      -- 이 발주의 인보이스에 걸린 결제 + 이 발주에 배분된 비용 문서에 걸린 결제 + 쓴 크레딧
  select pm.*, pa.amount as alloc_amount,
         case when pa.po_charge_id is not null then 'charge'
              when i.doc_kind = 'credit'        then 'credit'
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
      'required_by', p.required_by,                                                                  -- ⭐ 새
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'currency_id', p.currency_id, 'currency_code', cur.code, 'exchange_rate', p.exchange_rate,   -- currency_id 새(편집용)
      'payment_term_id', p.payment_term_id,                                                          -- 새(편집용)
      'payment_term_name', coalesce(p.payment_term_name, pt.name),
      'ship_to_warehouse_id', p.ship_to_warehouse_id,                                                -- 새(편집용)
      'ship_to_warehouse', w.name,
      'tax_rule', p.tax_rule, 'tax_inclusive', p.tax_inclusive,                                      -- ⭐ 새 · 줄 tax_rule null = 이것을 따른다
      'inventory_account_id', p.inventory_account_id, 'inventory_account_code', p.inventory_account_code,
      'inventory_account_name', ia.name,                                                             -- ⭐ 새
      'supplier_contact_name', p.supplier_contact_name, 'supplier_contact_phone', p.supplier_contact_phone,
      'supplier_contact_email', p.supplier_contact_email,                                            -- ⭐ 새 · 그날의 연락처
      'supplier_address_line1', p.supplier_address_line1, 'supplier_address_line2', p.supplier_address_line2,
      'supplier_city', p.supplier_city, 'supplier_state_province', p.supplier_state_province,
      'supplier_postal_code', p.supplier_postal_code, 'supplier_country', p.supplier_country,       -- ⭐ 새 · 그날의 주소
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
    left join public.ref_account ia on ia.id = p.inventory_account_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = p.created_by
    left join public.ims_staff fb on fb.id = p.confirmed_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'product_id', product_id, 'sku', sku, 'product_name', product_name,
      'supplier_sku', supplier_sku, 'qty_ea', qty_ea, 'received_qty', received_qty,
      'remaining_qty', qty_ea - received_qty,
      'entered_unit_sku', entered_unit_sku, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'tax_rule', tax_rule, 'note', note) order by line_no)   -- tax_rule null = 머리를 따른다
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'seq', seq, 'name', name, 'percent', percent,
                                        'supplier_discount_id', supplier_discount_id, 'note', note) order by seq)
    from disc), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'subtotal', subtotal,
      'discount_factor', round(factor, 6),
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
      'discount_factor', round(factor, 6),
      'total_amount', total_amount,
      'computed_total', computed_total,
      'diff', diff,
      'payable_net', payable_net,
      'paid', paid,
      'credit_total', credit_total,
      'unpaid', unpaid,                                                                    -- 음수면 받을 돈(credit due)
      -- ⭐ 캐럿 — 이 인보이스가 걸린 발주 전부(이 발주 포함) · amount 는 할인 전 줄 합(할인은 문서 단위라 발주 몫으로 안 내린다)
      'po_shares', coalesce((select jsonb_agg(jsonb_build_object('po_id', sh.po_id, 'po_number', sh.po_number, 'po_status', sh.po_status,
                                                                 'line_count', sh.line_count, 'qty_ea', sh.qty_ea, 'amount', sh.amount) order by sh.po_number)
                             from shares sh where sh.po_invoice_id = inv.id), '[]'::jsonb))
      order by invoice_date, invoice_number)
    from inv), '[]'::jsonb),
  'credits', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'credit_number', invoice_number, 'credit_date', invoice_date, 'status', status,
      'credit_for_invoice_id', credit_for_invoice_id, 'credit_for_number', credit_for_number,
      'supplier_name', supplier_name, 'currency_code', currency_code,
      'line_count', line_count, 'lines_for_this_po', lines_for_this_po,
      'discount_factor', round(factor, 6),
      'total_amount', total_amount,
      'computed_total', computed_total,
      'diff', diff,
      'credit_net', credit_net,
      'used', used,
      'remaining', remaining,                                                              -- 안 붙은 크레딧만 · 붙은 것은 null
      'warnings', (select coalesce(jsonb_agg(w), '[]'::jsonb) from unnest(array_remove(array[
                    case when credit_for_invoice_id is not null and used > 0 then 'attached_and_used' end,
                    case when credit_for_doc_kind = 'credit' then 'credit_for_is_credit' end,
                    case when credit_for_supplier_id is not null and credit_for_supplier_id <> supplier_id then 'credit_for_other_supplier' end
                  ], null)) as w),
      -- ⭐ 캐럿 — 크레딧 줄이 걸린 발주 전부(조정 크레딧은 줄이 없어 빈 배열)
      'po_shares', coalesce((select jsonb_agg(jsonb_build_object('po_id', sh.po_id, 'po_number', sh.po_number, 'po_status', sh.po_status,
                                                                 'line_count', sh.line_count, 'qty_ea', sh.qty_ea, 'amount', sh.amount) order by sh.po_number)
                             from shares sh where sh.po_invoice_id = cred.id), '[]'::jsonb))
      order by invoice_date, invoice_number)
    from cred), '[]'::jsonb),
  'charges', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'charge_number', charge_number, 'kind', kind, 'description', description, 'charge_date', charge_date,
      'status', status, 'supplier_name', supplier_name, 'currency_code', currency_code,
      'total_amount', total_amount,
      'alloc_amount', alloc_amount,                                                        -- 이 발주에 박힌 배분
      'paid', paid,
      'unpaid', unpaid,                                                                    -- 문서 전체 기준
      'unallocated', unallocated,                                                          -- 총액 − 배분 합 · 0 이 정상
      -- ⭐ 캐럿 — 그 청구서의 배분 전부(이 발주 포함) · [실물] CBSA 2,547.37 = PO-02001a 597.49 + PO-02002 1,949.88
      'allocs', coalesce((select jsonb_agg(jsonb_build_object('po_id', a.po_id, 'po_number', x.po_number, 'po_status', x.status, 'amount', a.amount) order by x.po_number)
                          from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = chg.id), '[]'::jsonb))
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
comment on function public.po_detail(uuid) is '⑤ 발주 상세 — jsonb 하나(header · lines · discounts · totals · receipts · invoices · credits · charges · payments). ⭐ 계산 규칙의 정본 — 다만 [2026-09-16 넓은 목록] 인보이스·크레딧·비용 한 장의 돈(payable_net · paid · credit_total · unpaid · remaining)은 po_invoice_money · po_charge_money 뷰로 옮겼다(po_list 와 한 식). 발주 쪽(할인 체인 po_mul · 라인 round(qty×단가,2) · 입고 줄 합 · 초과면 remaining 음수)은 여기. ⭐ 캐럿 — invoices[].po_shares · credits[].po_shares(문서가 걸린 발주 전부 · amount 는 할인 전 줄 합) · charges[].allocs(배분 전부). header 에 새 칸(required_by · tax_rule · tax_inclusive · inventory_account · 그날의 연락처 3 · 주소 6)과 편집용 id(currency_id · payment_term_id · ship_to_warehouse_id). 없는 id → null. security invoker. 정본 po-module §13 · §11-e·f·g · 2026-09-16';

revoke all on function public.po_detail(uuid) from public, anon;
grant execute on function public.po_detail(uuid) to authenticated;

-- ═══ ⑤ po_create — 공급처에서 따라오는 새 칸을 채운다 (서명 그대로 · 181719 의 본문 + 연락처·주소·tax_rule·inventory account) ═══
-- POST /rest/v1/rpc/po_create  {"p_supplier_id": "<uuid>", "p_warehouse_id": null, "p_order_date": null, "p_note": null}
-- 새 warnings: contact_unset(활성 연락처 0) · contact_ambiguous(둘 이상인데 기본이 정확히 하나가 아니다) · address_unset(활성 주소 0 · ⚠️ 143/226 에서 뜬다) ·
--             address_ambiguous(둘 이상인데 Billing 이 정확히 하나가 아니다) · tax_rule_unset(공급처 tax_rule 비어 있음 · 실측 0곳) · inventory_account_unset(inv_config 키 없음 · 코드가 ref_account 에 없음)
-- ⚠️ 연락처 규칙은 사람·메모를 가르지 않는다(「Acquired by House of Cheatham」이 연락처와 Billing 주소로 들어가 있다 — 실측) — 그것은 정리의 일.
create or replace function public.po_create(
  p_supplier_id  uuid,
  p_warehouse_id uuid default null,
  p_order_date   date default null,
  p_note         text default null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_sup       public.supplier%rowtype;
  v_cur       uuid;
  v_wh        uuid;
  v_wh_n      int;
  v_ct        public.supplier_contact%rowtype;   -- 그날의 연락처
  v_ct_n      int;
  v_ct_def_n  int;
  v_ad        public.supplier_address%rowtype;   -- 그날의 주소
  v_ad_n      int;
  v_ad_bil_n  int;
  v_acct_code text;
  v_acct_id   uuid;
  v_po_id     uuid;
  v_po_number text;
  v_disc      int := 0;
  v_warn      text[] := '{}';
begin
  -- 만든 사람 — 서버 유도(§10-h 열쇠 auth_user_id) · 행이 없으면 아무것도 안 쓴다
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;

  select * into v_sup from public.supplier where id = p_supplier_id;
  if not found then
    raise exception 'Supplier % not found — nothing was saved', p_supplier_id;
  end if;
  -- ⚠️ 비활성·미판정 공급처는 막지 않는다 — 판정은 화면의 정돈 규칙(§10-j 3-b) 한곳에. 여기서는 알리기만
  if not v_sup.is_active then v_warn := array_append(v_warn, 'supplier_inactive'); end if;
  if v_sup.is_purchasable is distinct from true then v_warn := array_append(v_warn, 'supplier_not_purchasable'); end if;

  -- 통화 — 공급처 기본통화 · 없으면 inv_config.base_currency · 그것도 없으면 예외(po.currency_id 는 not null)
  v_cur := v_sup.currency_id;
  if v_cur is null then
    select c.id into v_cur
    from public.ref_currency c
    join public.inv_config k on k.key = 'base_currency' and k.value = c.code;
    if v_cur is null then
      raise exception 'Supplier has no currency and inv_config.base_currency does not point at a ref_currency row — nothing was saved';
    end if;
    v_warn := array_append(v_warn, 'currency_defaulted');
  end if;

  -- 창고 — 준 것 · 아니면 기본 창고가 정확히 하나일 때만(짐작으로 고르지 않는다)
  v_wh := p_warehouse_id;
  if v_wh is null then
    select count(*), (array_agg(w.id))[1] into v_wh_n, v_wh
    from public.ref_warehouse w where w.is_default and w.is_active;
    if coalesce(v_wh_n, 0) <> 1 then
      v_wh := null;
      v_warn := array_append(v_warn, 'warehouse_unset');
    end if;
  end if;

  -- ⭐ 그날의 연락처 — 활성 중 is_default 가 정확히 하나면 그것 · 아니면 활성이 정확히 하나면 그것 · 그 외 null + 경고
  --    [실측 2026-09-16] 활성 226 중 기본 정확히 하나 159 · 기본 없이 하나 20 · 0건 44 ⇒ 179 곳을 덮는다
  select count(*), count(*) filter (where c.is_default) into v_ct_n, v_ct_def_n
  from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active;
  if v_ct_def_n = 1 then
    select * into v_ct from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active and c.is_default;
  elsif v_ct_n = 1 then
    select * into v_ct from public.supplier_contact c where c.supplier_id = p_supplier_id and c.is_active;
  elsif v_ct_n = 0 then
    v_warn := array_append(v_warn, 'contact_unset');
  else
    v_warn := array_append(v_warn, 'contact_ambiguous');
  end if;

  -- ⭐ 그날의 주소 — 활성 1건이면 그것 · 여럿이면 Billing 이 정확히 하나면 그것 · 그 외 null + 경고 (§3-b B 규칙 · DefaultForType 은 안 담았다)
  --    ⚠️ [실측] 활성 226 중 주소 0건 143 ⇒ address_unset 이 대다수에서 뜬다 — 화면이 오류처럼 그리면 안 된다(말만)
  select count(*), count(*) filter (where a.type = 'Billing') into v_ad_n, v_ad_bil_n
  from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active;
  if v_ad_n = 1 then
    select * into v_ad from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active;
  elsif v_ad_n > 1 and v_ad_bil_n = 1 then
    select * into v_ad from public.supplier_address a where a.supplier_id = p_supplier_id and a.is_active and a.type = 'Billing';
  elsif v_ad_n = 0 then
    v_warn := array_append(v_warn, 'address_unset');
  else
    v_warn := array_append(v_warn, 'address_ambiguous');
  end if;

  -- 세금규칙 — 공급처 원문 그대로(실측 226/226 채움 · 비어 있으면 알리기만)
  if v_sup.tax_rule is null then v_warn := array_append(v_warn, 'tax_rule_unset'); end if;

  -- ⭐ 재고 자산 계정 — inv_config po_inventory_account_code → ref_account.code (없으면 null + 경고 · 활성 여부는 안 본다 — 기본값이 비활성이면 그것이 보여야 한다)
  select k.value into v_acct_code from public.inv_config k where k.key = 'po_inventory_account_code';
  if v_acct_code is not null then
    select r.id into v_acct_id from public.ref_account r where r.code = v_acct_code;
  end if;
  if v_acct_id is null then
    v_acct_code := null;                                  -- 코드가 표에 없으면 원문도 박지 않는다(짐작 값을 남기지 않는다)
    v_warn := array_append(v_warn, 'inventory_account_unset');
  end if;

  -- ① po 한 행 — po_number 는 기본값 po_next_number() · 결제조건은 FK + 원문 · 연락처·주소는 원문만(그날 값)
  insert into public.po (status, supplier_id, currency_id, payment_term_id, payment_term_name, ship_to_warehouse_id, order_date, created_by, note,
                         tax_rule, inventory_account_id, inventory_account_code,
                         supplier_contact_name, supplier_contact_phone, supplier_contact_email,
                         supplier_address_line1, supplier_address_line2, supplier_city, supplier_state_province, supplier_postal_code, supplier_country)
  values ('draft', p_supplier_id, v_cur, v_sup.payment_term_id, v_sup.payment_term_name, v_wh, coalesce(p_order_date, current_date), v_staff, p_note,
          v_sup.tax_rule, v_acct_id, v_acct_code,
          v_ct.name, v_ct.phone, v_ct.email,
          v_ad.line1, v_ad.line2, v_ad.city, v_ad.state_province, v_ad.postal_code, v_ad.country)
  returning id, po_number into v_po_id, v_po_number;

  -- ② supplier_discount → po_discount 복사(예상 층 · §11-e · 활성만 · seq 그대로 · 원천 id 를 남긴다) — 지금 0행 · 채우면 듣는다
  insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id)
  select v_po_id, d.seq, d.name, d.percent, d.id
  from public.supplier_discount d
  where d.supplier_id = p_supplier_id and d.is_active
  order by d.seq;
  get diagnostics v_disc = row_count;

  return jsonb_build_object(
    'id', v_po_id, 'po_number', v_po_number, 'status', 'draft',
    'currency_id', v_cur, 'ship_to_warehouse_id', v_wh, 'payment_term_name', v_sup.payment_term_name,
    'tax_rule', v_sup.tax_rule, 'inventory_account_code', v_acct_code,
    'supplier_contact_name', v_ct.name, 'supplier_contact_email', v_ct.email,
    'supplier_address_line1', v_ad.line1,
    'discounts_copied', v_disc,
    'warnings', to_jsonb(v_warn));
end;
$$;

comment on function public.po_create(uuid, uuid, date, text) is '⑤ 발주 초안 만들기 — po 한 행(draft · po_number 기본값) + supplier_discount → po_discount 복사. 공급처에서 따라오는 것: 통화(없으면 inv_config.base_currency) · 결제조건(FK+원문) · ⭐ [2026-09-16] tax_rule 원문 · 그날의 연락처(is_default 하나 → 활성 하나 → null) · 그날의 주소(1건 → Billing 하나 → null · 여섯 칸 원문) · inventory account(inv_config po_inventory_account_code → ref_account · FK+코드). 창고는 기본 창고가 정확히 하나일 때만. created_by 는 auth.uid() → ims_staff.id 서버 유도. 없으면 null 로 두고 warnings 로 알린다(contact_unset/ambiguous · address_unset/ambiguous · tax_rule_unset · inventory_account_unset) — 막지 않는다. 실패는 예외(nothing was saved). 정본 po-module §11-b·e · §13-f · 2026-09-16';

revoke all on function public.po_create(uuid, uuid, date, text) from public, anon;
grant execute on function public.po_create(uuid, uuid, date, text) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 화면(asung-ims/po.html · 대화 Claude 가 고친다)이 새로 받는 것 — 이 파일의 산출물이 화면의 입력이다
-- ─────────────────────────────────────────────────────────────
-- po_list (기존 22칸 뒤에)
--   required_by · invoice_count · invoiced_qty · invoiced_total · credit_count · charge_count · paid_total · unpaid_total · doc_numbers ·
--   order_phase · invoice_phase · receipt_phase · charge_phase · payment_phase   (각 'none' | 'partial' | 'done')
--   검색:  .or(`po_number.ilike.%q%,supplier_name.ilike.%q%,doc_numbers.ilike.%q%`)
--   필터:  공급처 .eq('supplier_id') → 날짜 .gte/.lte('order_date') → 상태 → 빠른 필터 아직 안 온 것 .eq('status','confirmed').neq('receipt_phase','done') · 미지급 .gt('unpaid_total', 0)
--   태그:  credit_count > 0 → 발주번호 옆 「credit」 태그(split 과 같은 자리 · 국면 아이콘이 아니다)
--   ⚠️⚠️ paid_total · unpaid_total 은 문서 기준 — 목록을 세로로 더해 합계를 내지 마라(두 발주에 걸친 문서가 두 번 센다). 화면 주석에 같은 문장을 둘 것.
--   ⚠️ 국면 다섯은 넓은 목록에서만 그린다 · unpaid_total < 0 은 「credit due」
-- po_detail
--   header      + required_by · currency_id · payment_term_id · ship_to_warehouse_id · tax_rule · tax_inclusive · inventory_account_id/_code/_name ·
--                 supplier_contact_name/_phone/_email · supplier_address_line1/_line2 · supplier_city · supplier_state_province · supplier_postal_code · supplier_country
--   invoices[]  + po_shares[] {po_id, po_number, po_status, line_count, qty_ea, amount}   (캐럿 · amount 는 할인 전 줄 합 · 이 발주 포함)
--   credits[]   + po_shares[] 같은 모양(조정 크레딧은 [])
--   charges[]   + allocs[] {po_id, po_number, po_status, amount} · unallocated             (캐럿)
--   lines[].tax_rule 이 null 이면 header.tax_rule 을 따른다(표시 규칙)
--   그 밖 키·값은 무변(unpaid · credit_total · remaining · warnings · payments …)
-- po_create
--   반환 + tax_rule · inventory_account_code · supplier_contact_name · supplier_contact_email · supplier_address_line1
--   warnings 새 값 contact_unset · contact_ambiguous · address_unset(대다수) · address_ambiguous · tax_rule_unset · inventory_account_unset — 오류가 아니다 · 알림으로
-- 머리 편집(PostgREST update · 기존 길): required_by · tax_rule · tax_inclusive · inventory_account_id/_code · 연락처 3 · 주소 6 도 같은 길로 고친다
-- 새 뷰 po_invoice_money · po_charge_money — 화면이 직접 읽을 필요는 없다(⬜ 비용·인보이스 목록 화면이 쓸 것)

-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 테스트 DB · 예상값은 검토 Claude 계산 — §13-b 실물과 SQL 스냅숏(2026-09-16)에서)
-- ─────────────────────────────────────────────────────────────
-- ⓪ 적용 뒤 표·설정
--   \d po                                                       → 새 칸 15개 · 인덱스 po_inventory_account_id_idx · po_required_by_idx
--   select key, value from inv_config order by 1;              → base_currency · baseline_snapshot_key · po_inventory_account_code = _59_
--   select po_number, required_by, tax_rule, supplier_contact_name from po order by 1;   → 기존 행은 전부 null(backfill 안 함 · 검토 이견 10)
-- ① 헬퍼 뷰 — 앞 po_detail 값과 같아야 한다(식 이동 · 값 무변)
--   select i.invoice_number, m.doc_kind, m.payable_net, m.alloc_total, m.credit_total, m.unpaid, m.remaining from po_invoice_money m join po_invoice i on i.id = m.id order by 1;
--   예상  AMP-778812 invoice payable_net 2010.54 · alloc_total 2010.54 · credit_total 30.90 · unpaid −30.90 · remaining null
--         CN-AMP-778812-1 credit payable_net 30.90 · alloc_total 0 · credit_total 0 · unpaid null · remaining null(붙은 크레딧)
--   select c.charge_number, m.total_amount, m.paid, m.unpaid, m.alloc_sum, m.unallocated from po_charge_money m join po_charge c on c.id = m.id;
--   예상  10039192310530 · 2547.37 · 2547.37 · 0 · 2547.37 · 0.00
-- ② po_list 국면 — 기존 칸 무변 확인 먼저
--   select po_number, net_total, charge_total from po_list order by 1;   → PO-02001a 2010.54 597.49 · PO-02001b 253.91 0 · PO-02002 7985.00 1949.88 (그대로)
--   select po_number, status, order_phase, invoice_phase, receipt_phase, charge_phase, payment_phase, invoice_count, invoiced_qty, credit_count, charge_count, paid_total, unpaid_total, doc_numbers
--     from po_list order by 1;
--   예상  PO-02001a  closed     done  done     done  done  done   1  (=ordered_qty)  1  1  4557.91  −30.90  '10039192310530 AMP-778812 CN-AMP-778812-1'
--                    (청구: AMP-778812 goods 3줄이 a 의 라인 전부 · 2,446.80 = a 소계 ⇒ 수량도 같다고 본다 · 다르면 partial — 그때 실물 확인)
--                    (결제: 인보이스 unpaid −30.90 + CBSA 0 = −30.90 ≤ 0 ⇒ done · 음수 = 받을 돈 · paid 2010.54 + 2547.37)
--         PO-02001b  confirmed  done  none     none  none  none   0  0  0  0  0  0  null
--         PO-02002   (confirmed 면 done · draft 면 partial)  none  none  done  done   0  0  0  1  2547.37  0  '10039192310530'
--                    ⭐ 청구 none 인데 결제 done — 문서 기준(CBSA 를 다 냈다)이라 맞는 결과다. 결함이 아니다.
--         PO-02005   cancelled · 라인 13 → order_phase 는 confirmed_at 이 있으면 done · 없으면 partial (⭐ none 이 아니다 · Caleb) · 나머지 none
--         PO-02003·02004·02006·02007  라인 있으면 partial(draft)/done(confirmed) · 없으면 none · 나머지 none · unpaid 0
--   ⚠️ paid_total 을 세로로 더하면 2547.37 이 a 와 02002 에 두 번 나온다 — 설계대로(문서 기준). 합계를 내는 자리가 아니다.
-- ③ 검색 — select po_number from po_list where doc_numbers ilike '%778812%';   → PO-02001a (인보이스·크레딧 둘이 걸림 · 행은 하나)
--                select po_number from po_list where doc_numbers ilike '%10039192310530%' order by 1;   → PO-02001a · PO-02002
-- ④ po_detail 값 무변 + 캐럿
--   select po_detail((select id from po where po_number='PO-02001a')) -> 'totals';                       → 앞과 같다(2010.54 · 436.26 · 0.821700)
--   select jsonb_pretty(po_detail((select id from po where po_number='PO-02001a')) -> 'invoices');
--   예상  unpaid −30.90 · credit_total 30.90 · paid 2010.54 (무변) · po_shares [{PO-02001a · closed · line_count 3 · qty_ea (=a ordered) · amount 2446.80}]
--   select jsonb_pretty(po_detail((select id from po where po_number='PO-02001a')) -> 'charges');
--   예상  alloc_amount 597.49 · unpaid 0 · unallocated 0.00 · allocs [{PO-02001a closed 597.49}, {PO-02002 … 1949.88}]   ⭐ 캐럿에 보일 것
--   select jsonb_pretty(po_detail((select id from po where po_number='PO-02002')) -> 'charges' -> 0 -> 'allocs');   → 같은 둘(다른 발주에서 봐도 전부)
--   select po_detail((select id from po where po_number='PO-02001a')) -> 'credits' -> 0 -> 'po_shares';   → [{PO-02001a · 1줄 · 10 · 30.90}]
--   select jsonb_pretty(po_detail((select id from po where po_number='PO-02001a')) -> 'header');   → required_by null · tax_rule null · ship_to_warehouse_id 있음 · inventory_account_name null
-- ⑤ po_create — 화면(로그인)에서 House of Cheatham 으로 하나 만든 뒤
--   select po_number, tax_rule, inventory_account_code, supplier_contact_name, supplier_address_line1, supplier_country from po order by created_at desc limit 1;
--   예상  tax_rule = HoC 의 supplier.tax_rule · inventory_account_code _59_ · 연락처: HoC 활성 연락처가 기본 하나면 그 이름(「Acquired by House of Cheatham」이 기본이면 그것이 박힌다 — 규칙대로 · 정리 대상)
--         주소: HoC 활성 주소가 1건이면 그것 · Billing 둘(§3-b)이면 null + warnings 'address_ambiguous'
--   warnings 에 inventory_account_unset 이 없어야 한다(_59_ 가 ref_account 에 있으면)
-- ⑥ 취소 문서 제외 — 크레딧 CN-AMP-778812-1 을 cancelled 로 바꿔 보면 po_list PO-02001a credit_count 0 · unpaid_total 0 · po_detail invoices[0].credit_total 0 · unpaid 0 —
--   credits[] 에는 status cancelled 로 그대로 보인다. 확인 뒤 되돌린다.
