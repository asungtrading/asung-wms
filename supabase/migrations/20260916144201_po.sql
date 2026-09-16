-- ─────────────────────────────────────────────────────────────
-- ⑤ PO 본체 ①차 — po · po_line · po_discount · po_receipt_line (테스트 DB Asung-IMS · 2026-09-16)
--
-- 정본: docs/design/po-module.md §11(설계 판단 · 2026-09-15) · §5(표 관례) · §3-g(product_supplier) · §10-h(ims_staff)
-- 지시서: ~/asung/prompts/po-tables-1.md · 검토 이견 1~17 (2026-09-16 · 3 은 「파일 하나」로 뒤집힘 · 7·14 는 문구 정정)
--
-- ⭐ 이번 차수의 범위 — 발주 머리 · 라인 · 할인 줄 · 입고 줄. ❌ 인보이스 · 비용 · 결제 표는 다음 차수(§11-f·g·h).
--    ❌ 사건 표 · 트리거 · 아웃박스도 만들지 않는다(§11-j · Caleb 합의 2026-09-16) — 원장을 IMS 로 옮길 때 잇는다.
--       근거: 받을 곳이 없는데 보내는 쪽만 만들면 그 모양이 맞는지 확인할 방법이 없다. 입고 줄에 원장이 필요로 하는 것이 다 있다.
--    ❌ 분할 함수 · 잠금 트리거도 다음 차수(아래 「확정 = 잠금」).
--
-- ⭐⭐ 컷오버 축(§11-⓪ 설계 함의 ①) — 이 넷은 전부 **거래**다 ⇒ 컷오버 때 지운다. 마스터(supplier · product · ref_* · ims_staff)는 남는다.
--    ⚠️ 예외 하나(§11-d · 2-c): PO 확정이 갱신하는 product_supplier.cost·last_supplied(Latest)는 마스터에 있으나 거래에서 나오는 값 —
--       컷오버 때 거래는 지우지만 Latest 는 남긴다. 그 갱신은 이 파일의 칸이 아니라 확정 동작(다음 차수)이다.
--
-- ⭐ 파일 하나에 넷을 담는다(Caleb 2026-09-16) — 마이그레이션은 적용되면 고치지 않고 나중 변경은 새 파일이다. 나눠서 얻는 것이 없고,
--    넷은 FK 로 묶여 함께 있어야 뜻이 있다. 나누면 중간에 실패했을 때 모듈이 반만 선다.
--
-- ⭐ 거래 표는 §5 「마스터 표」 규약의 대상이 아니다 — 물려받는 것과 빼는 것을 밝힌다(검토 이견 2):
--    물려받음  id uuid PK · note · created_at/updated_at + set_updated_at 트리거 · RLS auth_all + revoke anon · <표>_*_ck 이름 · FK 인덱스 <표>_<칸>_idx
--    뺌        cin7_id(Cin7 발주는 적재하지 않는다 · §11-⓪ 함의 ②) · source(cin7/manual 축이 없다) · is_active(상태 status 가 대신) · name(문서에 이름이 없다)
--    FK        문서 → 소유 줄(po_line · po_discount)은 on delete cascade — §5 「CASCADE 는 문서→소유 라인에만」이 정확히 이 부류.
--              그 밖은 전부 no action. 입고 줄 → 라인도 no action — 입고가 있는 줄은 지울 수 없다(입고는 사건이다 · 상쇄 규칙은 사건 차수에).
--    권한      DELETE 는 막지 않는다(초안은 지울 수 있어야 한다 · 확정 뒤는 취소로 물러난다) · TRUNCATE 는 막는다.
--
-- ⚠️⚠️ 확정 = 잠금(§11-b)이지만 **지금 확정 문서는 보호받지 않는다.** 화면이 편집을 감추는 것은 막는 것이 아니다(anon key 공개 · 2026-09-15 is_purchasable 에서 확인).
--    ⬜ 분할 함수를 만드는 차수에 잠금 트리거와 그 예외 경로(시스템 분할만 통과)를 함께 넣는다 — 트리거만 먼저 넣으면 분할 함수가 못 움직인다.
--
-- ⚠️ 참조 칸 이름은 마이그레이션 파일로 확인했다 — ref_bin(id · warehouse_id · 20260911165946) · ims_staff(id · 20260915141105) ·
--    ref_currency/ref_payment_term/ref_warehouse(id · 20260911*) · product(id · 20260913230500) · supplier_discount(id · 20260912212150).
--    지시서 4-ⓑ 의 \d 실물 결과는 이 파일을 쓸 때 붙어 오지 않았다 — 적용 전 \d 로 한 번 대조할 것.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ 채번 — 시퀀스 + 함수 · 기본값으로 건다 (검토 이견 4) ═══
-- ⭐ PO-02000 부터(Caleb 2026-09-16) — 지금 Cin7 은 PO-01302 근처. 겹치지 않게 벌려 두었다(연습 기간 거래는 컷오버 때 지우므로 충돌은 문제가 아니다).
-- ⭐ 시퀀스인 이유 — 동시 생성에서 겹치지 않는다(트랜잭션 밖에서 원자적) · PostgREST insert 만으로 번호가 붙어 화면에 채번 코드가 없다.
--    max()+1 은 잠금이 필요하고 두 사람이 동시에 만들면 겹친다.
-- ⚠️ 대가 — 롤백된 번호는 비어 남는다(시퀀스는 되돌아가지 않는다). 「PO-12345 는 우리 번호일 뿐이다」(Caleb · §11-c)라 빈 번호를 허용한다.
-- ⚠️ 마이그레이션에 시퀀스 선례가 없다(2026-09-16 grep) — 첫 사례. 함수 이름은 inv_*·wms_* 관례대로 모듈 접두어 po_.
-- ⭐ 갈라진 문서(§11-c)는 번호 뒤에 소문자 접미사가 붙는다 — PO-02000 → PO-02000a(받은 쪽) + PO-02000b(남은 쪽). 원본 번호는 남지 않는다.
--    접미사를 붙이는 것은 분할 함수(다음 차수)의 일이고 이 시퀀스는 모체 번호만 낸다.
create sequence if not exists public.po_number_seq start with 2000 increment by 1;

create function public.po_next_number() returns text
  language sql volatile
  set search_path = public, pg_temp
as $$
  select 'PO-' || lpad(nextval('public.po_number_seq')::text, 5, '0');
$$;
comment on function public.po_next_number() is '발주번호 채번 — PO- + 다섯 자리(시퀀스 po_number_seq · 2000 부터). 갈라진 문서의 접미사 a·b·c 는 여기서 안 붙인다(분할 함수 · 다음 차수). 정본 po-module §11-c · 2026-09-16';

-- 기본값(default)은 insert 하는 역할로 실행된다 — authenticated 가 시퀀스를 쓸 수 있어야 한다
revoke all on sequence public.po_number_seq from public, anon;
grant usage, select on sequence public.po_number_seq to authenticated;
revoke all on function public.po_next_number() from public, anon;
grant execute on function public.po_next_number() to authenticated;

-- ═══ po — 발주 머리 ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po (
  id                    uuid primary key default gen_random_uuid(),
  po_number             text not null unique default public.po_next_number(),   -- ⭐ PO-02000 · 갈라지면 PO-02000a (접미사 포함 · 접두어로 찾는다)
  status                text not null default 'draft',                          -- draft → confirmed → closed · cancelled 옆으로 (§11-b)
  supplier_id           uuid not null references public.supplier         (id) on delete no action,
  currency_id           uuid not null references public.ref_currency     (id) on delete no action,   -- 공급처 기본통화를 화면이 넣는다
  exchange_rate         numeric,                                                 -- ⭐ 환율은 마스터가 아니라 문서에 박는다(§7) · CAD 면 1 · nullable(작성 중)
  payment_term_id       uuid references public.ref_payment_term (id) on delete no action,            -- FK + 원문 병행(§3-b 관례) — 그날의 조건을 남긴다
  payment_term_name     text,
  ship_to_warehouse_id  uuid references public.ref_warehouse     (id) on delete no action,            -- 배송지(창고)
  order_date            date not null default current_date,
  split_from_id         uuid references public.po                (id) on delete no action,            -- ⭐ 바로 앞 문서(§11-c · Caleb 2026-09-16) · c → b → a 사슬
  created_by            uuid references public.ims_staff         (id) on delete no action,            -- 화면이 me.id 를 넣는다(⬜ auth.uid() → ims_staff.id 기본값 함수는 이번 범위 밖)
  confirmed_by          uuid references public.ims_staff         (id) on delete no action,
  confirmed_at          timestamptz,
  closed_at             timestamptz,
  cancelled_at          timestamptz,
  note                  text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint po_status_ck    check (status in ('draft', 'confirmed', 'closed', 'cancelled')),
  constraint po_number_ck    check (po_number ~ '^PO-[0-9]{5,}[a-z]*$')
);

comment on table  public.po is '⑤ 발주 머리(Purchase 하나 · Simple/Advanced 를 가르지 않는다 §11-a). ⭐ 거래 — 컷오버 때 지운다(§11-⓪). 부분입고는 문서가 갈라진다(§11-c · split_from_id). ⚠️ 확정=잠금이지만 지금은 DB 가 보호하지 않는다 — 분할 함수 차수에 트리거와 예외 경로를 함께(⬜). 정본 po-module §11 · 2026-09-16 신설';
comment on column public.po.po_number is '⭐ PO-02000 부터(Caleb 2026-09-16 · Cin7 은 PO-01302 근처라 벌려 둠) · 기본값 po_next_number(). 갈라지면 소문자 접미사 — 받은 쪽 a · 남은 쪽 b · 또 갈라지면 c·d(§11-c). ⚠️ 원본 번호는 남지 않는다(껍데기 없음). 공급처 인보이스에는 모체 번호로 적혀 오므로 찾기는 접두어(po_number like ''PO-02000%'')로 — 유니크 인덱스가 앞부분 검색을 받는다. 「맨 처음을 가리키는 칸」은 두지 않는다(접두어로 충분 · Caleb 2026-09-16)';
comment on column public.po.status is '작성 중 draft → 확정 confirmed(문서 잠금 · 결재가 아니다 · 승인자 칸·대기열 없음 §11-b) → 종료 closed · 취소 cancelled 는 옆으로. ⚠️ 「입고 진행」은 상태가 아니라 진행도 — 저장하지 않고 po_receipt_line 합으로 계산한다. ⚠️ 입고가 끝나도 바로 안 닫는다 — 비용이 나중에 붙는다(§11-f). ⭐ 자동 분할(§11-c)은 시스템 동작이라 잠금의 예외 — 확정 문서의 번호에 접미사가 붙고 수량이 갈리는 것은 결함이 아니다';
comment on column public.po.split_from_id is '⭐ 갈라져 나온 바로 앞 문서(Caleb 2026-09-16 · 「PO-12345 가 모체고 바로 직전 알파벳에서 갈라진 것이니 바로 앞을 가리킨다」). c → b → a 사슬로 갈라진 순서가 그대로 보인다. 맨 처음 칸은 없다 — 한 번에 모으는 것은 번호 접두어로. 모체(첫 문서)는 null';
comment on column public.po.currency_id is 'NOT NULL · 공급처(supplier.currency_id)의 값을 화면이 기본으로 넣는다. ⚠️ 통화를 기호로만 구별하지 마라 — CAD·USD 둘 다 $(§7)';
comment on column public.po.exchange_rate is '⭐ 환율은 마스터가 아니라 문서에 박는다(§7 · 「그 거래를 한 날의 환율」). CAD 면 1. 작성 중에는 비어 있을 수 있다. ⬜ KRW 송금 환차손익은 결제(§11-h) 차수에';
comment on column public.po.payment_term_id is 'FK + 원문(payment_term_name) 병행 — §3-b 관례. 이 문서를 만든 날의 조건이 남는다(마스터가 바뀌어도). 결제조건이 실제로 일하는 자리는 인보이스 확정(§11-g · 다음 차수)';
comment on column public.po.ship_to_warehouse_id is '배송지 창고 → ref_warehouse(id). 입고 줄의 빈(ref_bin)은 자기 warehouse_id 를 갖는다 — 둘이 어긋나면 카운터로 본다(제약으로 막지 않는다 · 다른 창고에서 받는 실물이 있을 수 있다 · 짐작)';
comment on column public.po.created_by is '만든 사람 → ims_staff(id)(§10-h 「PO created_by 가 이 행을 가리킨다」). auth_user_id 가 아니라 id 다. 화면이 me.id 를 넣는다. nullable — ⬜ 기본값 함수(auth.uid() → ims_staff.id)는 다음에';
comment on column public.po.confirmed_by is '확정을 누른 사람 → ims_staff(id). 만드는 사람과 누르는 사람이 같다(Caleb 실측) — 결재가 아니라 잠금의 기록이다';
comment on column public.po.note is '우리가 적는 메모(§11 「메모」). 공급처에 보내는 문구와 내부 메모를 가르는 것은 화면 차수에';

-- ═══ po_line — 발주 라인 ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_line (
  id                       uuid primary key default gen_random_uuid(),
  po_id                    uuid not null references public.po      (id) on delete cascade,     -- ⭐ 문서 → 소유 줄 · §5 의 CASCADE 예외 부류
  line_no                  integer not null,                                                    -- 문서 안 차례 · 원장 line_ref 가 된다(§11-j)
  product_id               uuid not null references public.product (id) on delete no action,   -- ⭐ 낱개(EA)를 가리킨다 — 세트·콤보가 아니다(§11-d)
  supplier_sku             text,                                                                -- product_supplier.supplier_sku 를 그날 값으로 복사(공급처가 부르는 코드)
  qty_ea                   numeric not null,                                                    -- ⭐ 저장은 낱개(EA) · 원장·원가와 한 축(§11-d)
  entered_unit_product_id  uuid references public.product (id) on delete no action,             -- 사람이 고른 입력 단위 = 그 낱개를 부모로 가진 세트 SKU · null 이면 EA 로 넣었다
  entered_qty              numeric,                                                             -- 사람이 넣은 수(그 단위로)
  entered_pack_factor      numeric,                                                             -- ⭐ 그날의 환산 계수(product.pack_factor 의 그 순간 값 · §4-d) — 나중에 바뀌어도 그날의 환산은 그대로
  unit_price               numeric(18,7) not null default 0,                                    -- 낱개 단가 · 이번 발주만 · 마스터(product_supplier.fixed_cost)는 그대로(§11-d)
  tax_rule                 text,                                                                -- 원문 · product.purchase_tax_rule 을 화면이 복사 제안 · ⬜ ref_tax_rule 미결(§7-a)
  note                     text,                                                                -- §11-d 「코멘트」 — 공통 note 를 쓴다(칸을 둘 두지 않는다)
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),

  constraint po_line_qty_ea_ck        check (qty_ea > 0),
  constraint po_line_unit_price_ck    check (unit_price >= 0),                                 -- ⚠️ 0 을 막지 마라 — 샘플은 수량이 있고 단가가 0 (§3-b ④ · §11-d)
  constraint po_line_line_no_ck       check (line_no >= 1),
  constraint po_line_entered_unit_ck  check (entered_unit_product_id is null
                                             or (entered_qty is not null and entered_pack_factor is not null)),   -- 단위를 골랐으면 수와 계수도 남긴다
  constraint po_line_po_id_line_no_key unique (po_id, line_no)
);

comment on table  public.po_line is '⑤ 발주 라인 — 제품 · 수량(낱개) · 단가 · 세금규칙 · 사람이 넣은 단위와 그날의 환산 계수(§11-d). ⭐ 거래 — 컷오버 때 지운다. ❌ received_qty 칸 없음 — 입고는 po_receipt_line 을 더해서 낸다(한 라인이 여러 빈으로 나뉜다 · 두 곳에 적히면 어긋난다 · Caleb 2026-09-16). ❌ 라인 할인 칸 없음 — 할인은 문서 위 po_discount(§11-e). 정본 po-module §11-d';
comment on column public.po_line.line_no is '문서 안 차례(1부터) · unique (po_id, line_no). 원장 사건의 line_ref 로 쓰인다(§11-j — 유니크 키 일곱 중 하나 · 이것 하나가 열쇠는 아니다)';
comment on column public.po_line.product_id is '⭐ 낱개(EA) 제품 — ④ product_supplier 가 낱개에만 붙는다(§3-g). 세트는 부모를 pack_factor 로 환산해 넣고 · 사 오는 콤보(립오일 3)는 「공급처 줄이 있으면 후보」(§3-g) · 후보에 없는 제품은 §11-k 제품 생성 규칙';
comment on column public.po_line.qty_ea is '⭐ 낱개 수량 · numeric(소수 수량 실물이 있다 — inv_ledger 관례 · 정수 CHECK 없음) · > 0. 사람이 케이스로 넣었으면 entered_qty × entered_pack_factor 가 이 값이다 — 그 검산을 화면이 보여 준다';
comment on column public.po_line.entered_unit_product_id is '사람이 고른 입력 단위 — 그 낱개를 parent_product_id 로 가진 세트 SKU(product.id). null = EA 로 넣었다. ⭐ 인보이스와 대조할 때 「이 줄은 케이스로 넣은 것」이 보인다(§11-d · [실물 Ampro] CASE 345 @ 20.34 = EA 2,070 @ 3.39)';
comment on column public.po_line.entered_pack_factor is '⭐ 그날의 환산 계수 — product.pack_factor(정본 BOM Quantity · §3-d)의 그 순간 값을 복사한다. pack_factor 가 나중에 바뀌어도 이 줄의 환산은 그대로여야 한다(§4-d 「그 순간에만 존재한 것」 · 검토 Claude 제안 · 2026-09-16 채택). ⚠️ 환산값은 product 에 있다 — product_supplier 에 없다';
comment on column public.po_line.unit_price is '낱개 단가 · numeric(18,7)(product_supplier 와 같은 정밀도) · 이번 발주에만 적용 — 마스터 Fixed(product_supplier.fixed_cost)는 그대로(§11-d 두 자리). 화면 제안 순서 Fixed → Latest → 0(경고). ⚠️ 0 허용(샘플). ⭐ 마스터와 다르면 화면이 표시해 준다';
comment on column public.po_line.tax_rule is '세금 규칙 원문(product.purchase_tax_rule 을 복사 제안). ⬜ ref_tax_rule 은 미결(§7-a) — 표가 서면 FK+원문 병행으로';

-- ═══ po_discount — 문서 위 할인 줄 (체인 · 차례로 곱한다) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_discount (
  id                    uuid primary key default gen_random_uuid(),
  po_id                 uuid not null references public.po (id) on delete cascade,             -- ⭐ 문서 → 소유 줄 · CASCADE
  seq                   integer not null,                                                       -- ⚠️⚠️ 곱해지는 차례(supplier_discount.seq 와 같은 뜻)
  name                  text not null,                                                          -- 자유 문자열(Trade / Damage / Full Line …) · 마스터로 만들지 않는다(supplier_discount 와 같은 판단)
  percent               numeric not null,                                                       -- 0~100 · 금액에 작용하는 숫자라 numeric
  supplier_discount_id  uuid references public.supplier_discount (id) on delete no action,      -- 어디서 제안됐나 · 문서에서 고쳐도 원천이 남는다 · 스페셜 할인(마스터에 없음)은 null
  note                  text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),

  constraint po_discount_percent_ck    check (percent >= 0 and percent <= 100),
  constraint po_discount_seq_ck        check (seq >= 1),
  constraint po_discount_po_id_seq_key unique (po_id, seq)
);

comment on table  public.po_discount is '⑤ 문서 위 할인 줄(§11-e) — 공급처를 고르면 supplier_discount 가 제안되어 들어오고 · 문서에서 고칠 수 있고 · 줄을 더할 수 있다(마스터는 제안이지 잠금이 아니다). ⚠️⚠️ 차례로 곱한다 — 더하지 않는다([실물 Ampro] 17%→1%→3% 를 21% 로 더하면 146 달러 어긋남 · §3-b D). 원가 배분(금액 비례 · 잔돈은 금액이 가장 큰 줄 · 동점은 SKU 순)은 계산 규칙이라 칸이 없다. ⚠️ 조기결제 할인은 여기 안 섞는다(ref_payment_term 이 정본 · 결제 차수). ⭐ 거래 — 컷오버 때 지운다. 정본 po-module §11-e';
comment on column public.po_discount.seq is '⚠️⚠️ 곱해지는 차례 · unique (po_id, seq). 체인 할인은 순서가 겹치면 어느 것을 먼저 곱할지 알 수 없다. 10·20·30 처럼 띄어 매기면 사이에 끼울 수 있다(supplier_discount.seq 와 같은 관례)';
comment on column public.po_discount.percent is '비율(0~100 · CHECK) · numeric — 부동소수점을 쓰지 않는다. 문서의 값이 이 발주의 정본 · 실제 금액의 정본은 인보이스(다음 차수)';
comment on column public.po_discount.supplier_discount_id is '제안의 원천 → supplier_discount(id) · nullable. 문서에서 percent 를 고쳐도 어느 마스터 줄에서 왔는지 남는다. 마스터에 없는 스페셜 할인은 null. on delete no action — 마스터 줄을 지우려면 이 줄이 먼저 사라져야 한다';

-- ═══ po_receipt_line — 입고 줄 (어느 라인을 · 언제 · 누가 · 어느 빈에 · 몇 개) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.po_receipt_line (
  id           uuid primary key default gen_random_uuid(),
  po_line_id   uuid not null references public.po_line   (id) on delete no action,   -- ⚠️ cascade 아님 — 입고가 있는 줄(과 그 문서)은 지울 수 없다
  received_on  date not null default current_date,                                    -- ⭐ 물건이 들어온 날 = 원장 occurred_on(우리가 처리한 시각이 아니다 · inv_ledger 주석)
  received_by  uuid references public.ims_staff (id) on delete no action,             -- 받은 사람 → ims_staff(id)
  bin_id       uuid not null references public.ref_bin   (id) on delete no action,   -- ⭐ 빈 = ref_bin(id) · 창고는 ref_bin.warehouse_id 로 따라온다(따로 두면 어긋난다)
  qty_ea       numeric not null,                                                      -- 낱개 · 이 빈에 넣은 수 · 실제로 받은 수(초과분 포함 · 아래)
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint po_receipt_line_qty_ea_ck check (qty_ea > 0)
);

comment on table  public.po_receipt_line is '⑤ 입고 줄 — 어느 라인을 · 언제 · 누가 · 어느 빈에 · 몇 개(§11-i · Caleb 2026-09-16). ⭐ 따로 서는 이유 — 한 라인이 여러 빈으로 나뉜다(1,200개를 A 빈 800 · B 빈 400 · 「가능하면 한 SKU 는 한 빈에」지만 부득이한 경우가 있다 · Caleb 실측). ⭐ 입고 줄 하나 = 원장 사건 하나 — §11-j 의 사건이 이 줄에서 그대로 나온다(날짜·SKU·창고/빈·수량·문서 번호·line_no 가 다 있다 · 사건 표·트리거는 원장 이식 때 · 2026-09-16 합의). ⭐ 거래 — 컷오버 때 지운다. ⚠️⚠️ 초과분(§11-i): 실제로 받은 수는 여기 그대로 적히지만 사건은 PO 확정 수량까지만 나간다 ⇒ 원장 합 ≠ 입고 줄 합. 이것은 설계대로다 — 대조하다 버그로 오해하지 마라. 차이 = 입고 줄 합 − po_line.qty_ea 로 계산한다(차이 큐 표는 재고조정 모듈 때). 정본 po-module §11-i·j';
comment on column public.po_receipt_line.po_line_id is 'FK → po_line(id) · on delete no action — 입고는 사건이라 라인과 함께 사라지면 안 된다. 잘못 받은 것을 되돌리는 규칙(취소 줄로 상쇄인가 · 삭제인가)은 사건 차수에 정한다 — 지금은 DELETE 가 열려 있다(관계 표 관례)';
comment on column public.po_receipt_line.received_on is '⭐ 물건이 들어온 날 — 원장 occurred_on 이 된다. 우리가 처리한 시각(created_at)이 아니다. date — 원장이 date 다';
comment on column public.po_receipt_line.received_by is '받은 사람 → ims_staff(id). 풋어웨이까지 한 사람(§11-i 「빈이 정해진 뒤 입고가 확정된다」)';
comment on column public.po_receipt_line.bin_id is '⭐ 빈 → ref_bin(id) NOT NULL — 풋어웨이가 끝나야 입고 줄이 선다(§11-i). 창고는 ref_bin.warehouse_id 로 따라온다 · po.ship_to_warehouse_id 와 다르면 카운터로 본다. ⚠️ 원장 이식 때: inv_ledger.warehouse·bin 은 text(Cin7 원문 이름)라 ref_warehouse.name·ref_bin.name 으로 풀어야 한다(§12-a 「손봐야 하는 것」에 추가할 것 · 2026-09-16 발견). WMS 의 wms_sku_bins(sticky bin)는 다른 프로젝트의 캐시 — 표 관계 없음 · 「추천 빈」은 화면 규칙';
comment on column public.po_receipt_line.qty_ea is '이 빈에 넣은 낱개 수 · > 0 · numeric. ⚠️ 실제로 받은 수를 적는다 — PO 수량으로 자르지 않는다(자르면 초과가 안 보인다). 사건으로 나갈 때 PO 확정 수량까지만(§11-i) ⇒ 원장 합 ≠ 입고 줄 합은 설계대로';

-- ═══ FK 인덱스 — Postgres 는 자동 생성하지 않는다 (§5 · <표>_<칸>_idx) ═══
create index if not exists po_supplier_id_idx           on public.po (supplier_id);
create index if not exists po_currency_id_idx           on public.po (currency_id);
create index if not exists po_payment_term_id_idx       on public.po (payment_term_id);
create index if not exists po_ship_to_warehouse_id_idx  on public.po (ship_to_warehouse_id);
create index if not exists po_split_from_id_idx         on public.po (split_from_id);
create index if not exists po_created_by_idx            on public.po (created_by);
create index if not exists po_confirmed_by_idx          on public.po (confirmed_by);
create index if not exists po_status_idx                on public.po (status);                 -- 「확정됐고 아직 다 안 받은 PO」(§11-i 유입 조건) 조회용
create index if not exists po_line_po_id_idx                    on public.po_line (po_id);
create index if not exists po_line_product_id_idx               on public.po_line (product_id);
create index if not exists po_line_entered_unit_product_id_idx  on public.po_line (entered_unit_product_id);
create index if not exists po_discount_po_id_idx                on public.po_discount (po_id);
create index if not exists po_discount_supplier_discount_id_idx on public.po_discount (supplier_discount_id);
create index if not exists po_receipt_line_po_line_id_idx   on public.po_receipt_line (po_line_id);
create index if not exists po_receipt_line_bin_id_idx       on public.po_receipt_line (bin_id);
create index if not exists po_receipt_line_received_by_idx  on public.po_receipt_line (received_by);
create index if not exists po_receipt_line_received_on_idx  on public.po_receipt_line (received_on);   -- 원장 이식 때 날짜별로 사건을 뽑는다

-- ═══ 트리거 — ⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라 ═══
create trigger po_set_updated_at              before update on public.po              for each row execute function public.set_updated_at();
create trigger po_line_set_updated_at         before update on public.po_line         for each row execute function public.set_updated_at();
create trigger po_discount_set_updated_at     before update on public.po_discount     for each row execute function public.set_updated_at();
create trigger po_receipt_line_set_updated_at before update on public.po_receipt_line for each row execute function public.set_updated_at();

-- ═══ RLS · 권한 — 마스터 17표와 같은 auth_all (§10-j 3-i 「막을 것이 늘면 표 하나가 아니라 규칙으로」) ═══
-- ⚠️ 확정 문서 보호 · 매니저/admin 구분은 여기 없다 — 위 머리 주석 「확정 = 잠금」 참조(⬜ 분할 함수 차수).
alter table public.po              enable row level security;
alter table public.po_line         enable row level security;
alter table public.po_discount     enable row level security;
alter table public.po_receipt_line enable row level security;

create policy auth_all on public.po              for all to authenticated using (true) with check (true);
create policy auth_all on public.po_line         for all to authenticated using (true) with check (true);
create policy auth_all on public.po_discount     for all to authenticated using (true) with check (true);
create policy auth_all on public.po_receipt_line for all to authenticated using (true) with check (true);

revoke all on public.po              from anon;
revoke all on public.po_line         from anon;
revoke all on public.po_discount     from anon;
revoke all on public.po_receipt_line from anon;

-- DELETE 는 막지 않는다(초안은 지운다 · 확정 뒤는 취소로 — 그 구분은 DB 가 아니라 화면·RPC · ⬜ 잠금 차수에 트리거) · TRUNCATE 는 막는다
revoke truncate on public.po              from authenticated;
revoke truncate on public.po_line         from authenticated;
revoke truncate on public.po_discount     from authenticated;
revoke truncate on public.po_receipt_line from authenticated;
