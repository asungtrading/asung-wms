-- SO 모듈 마이그레이션 ④ — 거래 표 넷 신설: so · so_line · so_charge · so_reserve + 시퀀스 so_number_seq · so_next_number() (2026-09-23 · 파일 시각 UTC)
--
-- 목표: 마이그레이션 1개 · 표 4 · 시퀀스 1 · 함수 1(채번) · ⭐ 행 0 · ⭐⭐ 쓰기 정책 0 — 이번 차수 뒤 authenticated 는 네 표를 읽을 수만 있다.
-- 만들지 않는다(so-mig-4 §1 · Caleb 2026-09-23): 전이 트리거(6-g′) · 쓰기 RPC 전부(so_confirm · so_release · so_cancel · 출고 창구 · 분할 · 병합) · so_family_members/_lines ·
--   가용 재고 함수(5-f) · §8 표(so_invoice …) · ims_perm_catalog 변경(sales 묶음). 근거: 쓰기 길이 없으면 6-g′ 가 막으려는 사고(po.html setStatus 가 status 를 직접 바꾼 길 · po-module 2489행)가
--   생길 수 없다 · 허용 짝의 내려가는 쪽(WMS 롤백 · 인보이스 취소 invoiced→shipped 8-h)은 RPC 와 함께 정해야 시험할 수 있다 · PO 도 표를 먼저 세우고 쓰기를 뒤에 얹었다.
-- 선행: 20260916144201(po · po_line · po_number_seq 선례) · 20260917230000(ims_can_write · ims_staff) · 20260918133858(ims_touch · updated_by 규약) · 20260922201223(customer 셋 · 가장 최근 규약) ·
--       ref_warehouse · ref_currency · ref_payment_term · ref_account · product(전부 id uuid · 원문 매칭 열쇠 name/code/sku unique — 2026-09-23 grep 확인).
--       ⚠️ ims_touch() · ims_can_write(text) · set_updated_at() · po_next_number() 는 다시 만들지 않는다(마지막 정의 확인 · 이름·시그니처만 씀).
-- 정본: docs/design/so-module.md 5-d(so) · 5-e(so_line · so_charge) · 5-f(so_reserve) · 6-a(상태 아홉) · 6-b(channel · intake) · 8-b(merged_into_id) · 8-c(금액 칸 없음) · 9-b(이름) · 9-c·9-d(FK+원문 · 낱말) · §10(이번 차수 판정 · 뒤집은 것 표 — 만든 뒤 신설).
--       이 파일과 정본이 어긋나면 정본이 이긴다. 지시서 ~/asung/prompts/so-mig-4-so-tables.md · 검토 이견 1~8 · ⬜1~⬜9 는 Caleb 판정(2026-09-23)대로.
--
-- ═══ 설계 판단 — 5-d·5-e 본문만 보면 틀린 표가 나온다 · 뒷절이 뒤집은 것을 반영했다 ═══
--   status      아홉 draft · confirmed · at_wms · picking · packed · shipped · invoiced · fulfilled · cancelled (6-a · ⚠️ 6-a 제목의 「열」은 세면 아홉 — §10 정정 후보 · released→at_wms · closed 없음)
--   closed_reason  expired · superseded · voided · merged — ⚠️ fulfilled 없음 · cancelled 에만 선다(6-a · 6-i · 8-b · 8-j)
--   channel     warehouse · pos · counter(6-b · 5-d 본문의 「둘」이 아니다 · counter ≠ WMS direct) · intake  manual · shopify · csv · pos(6-b · 이름 source 아님 — inv_ledger.source 관례 충돌 회피)
--   FK+원문     location_id/_name → ref_warehouse(9-c ⬜3 · customer.default_location 과 짝) · currency_id/_code → ref_currency(9-d · PO 머리와 짝) · payment_term_id/_name · ar_account_id/_code · sale_account_id/_code(5-d)
--   원문만       tax_rule · price_tier — ref_tax_rule · ref_price_tier 가 없다 · 생기면 FK 칸을 옆에(9-c ⬜2 · 손님과 같은 이유)
--   주소 낱말    bill_to_*/ship_to_* 의 state_province · postal_code(9-d · 5-d 본문 state·postcode 를 뒤집었다) · 주소록을 FK 로 가리키지 않는다 — 칸칸이 복사(5-d)
--   금액 칸      ⚠️ 두지 않는다 — 인보이스가 발행 시점 금액을 굳히고 오더 금액은 뷰·함수로(8-c · 8-j · 다음 차수)
--   시각·사람    created_by · confirmed_at/by · at_wms_at/by(⭐ released_* 아님 — so_reserve.released_at 과 두 뜻 · ⬜1) · shipped_at/by(counter 의 누른 사람 · 6-b) · invoiced_at · closed_at(끝 상태 둘의 시각) · cancelled_by(⬜2)
--   짝 CHECK     split 짝 · cancelled⇔closed_reason · merged⇒closed_reason · 자기 참조 금지 · 끝 상태⇔closed_at(⬜5 · 같은 행 안의 값 짝 — 앞뒤 행 비교(전이)는 트리거 차수)
--   on delete    ⭐ so_line.so_id · so_charge.so_id → so CASCADE(거래 표 규약 「문서 → 소유 줄」 · po-module 1414행 · po_line 선례 · 검토 이견 1) · so_reserve.so_line_id → so_line NO ACTION(이력 · 예약이 붙은 줄은
--               확정된 적이 있다 ⇒ 지우지 않고 cancelled) · 그 밖 FK 전부 no action. ⚠️ 지시서 §2 공통의 「cascade 금지」는 마스터·관계 표 규약이었다.
--   so_reserve.open_line_id  plain unique(deferrable 아님 · 검토 이견 4) — RPC 는 풀고(released_at) → 거는(insert) 두 문장이라 즉시 검사로 된다 · 거꾸로 짜면 23505 로 잡힌다 ·
--               customer_*_default_uq(③ · 한 upsert 문장 안 교대)와 다르게 둔 이유 · deferrable 은 on_conflict 기준이 못 된다(9-i ⑪) · ⚠️ 부분 유니크 인덱스 금지(asung-wms 규칙 29)
--   NOT NULL    customer_id · currency_id · status · channel · intake · order_date(so) · so_id · line_no · product_id · sku · pack_factor · qty_ordered · qty_shipped · unit_price · price_override(so_line) ·
--               so_id · line_no · name · amount(so_charge) · so_line_id · qty_allocated · kind · allocated_at(so_reserve) — 나머지는 draft 가 비어 있을 수 있다(⬜4) · location_id nullable(PO ship_to_warehouse_id 와 같다)
--   정밀도       list_price · unit_price numeric(18,7)(po_line.unit_price · product_supplier 와 한 관례 · 검토 이견 5) · pct 는 plain numeric · 단가 0 을 막지 않는다(샘플 · PO 와 같다)
--   so_charge.account  기본 _99_(Freight Sales) 은 표 기본값이 아니다 — FK 는 ref_account.id(uuid · 테스트·운영이 다르다)라 마이그레이션이 박을 수 없다 · 화면·RPC 가 code='_99_' 를 찾아 넣는다(검토 이견 6)
--   메모 칸      5-d 의 comments(오더 메모) · shipping_notes(창고·배송 지시) 둘 — 거래 표 규약의 note 를 comments 가 대신한다(칸을 셋 두지 않는다 · po_line 이 note 하나로 간 것과 같은 판단)
--   컷오버      네 표 모두 「거래 ⇒ 지운다」(PO 와 같다 · po-module §11-⓪)
--
-- ═══ 권한 — ⭐⭐ 읽기만 (⬜7) ═══
--   RLS enable · 정책은 <표>_select 하나씩(for select to authenticated using (true)) · anon 에는 아무것도 주지 않는다 ·
--   ⚠️ Supabase 기본 권한이 authenticated 에 ALL 을 이미 주므로 revoke all 뒤 grant select 두 문장(검토 이견 3 · customer.sql 이 revoke delete,truncate 만 한 것과 다르다) ·
--   시퀀스·so_next_number() grant 는 PO 모양(usage,select · execute to authenticated) — 지금은 insert 권한이 없어 무의미하지만 RPC 차수가 invoker 로 가면 필요하고 해가 없다.
--
-- ⚠️ begin/commit 없음 — 적용은 psql -v ON_ERROR_STOP=1 -1 -f(한 트랜잭션) + supabase migration repair --status applied <이 파일 시각> (po-module §13-f · 이력 표가 안 쌓인다) — 실행은 Caleb · [테스트 · Asung-IMS].
-- ⚠️ 검증에서 시퀀스를 소비하지 않는다 — 시험 행은 so_number 를 직접 넣는다(SO-99999t 등 · CHECK 통과) · 기본값은 pg_get_expr 로 읽는다(시퀀스는 롤백되지 않는다).

-- ═══ ⓪ 시퀀스 · 채번 — PO 모양(20260916144201 44~58행) ═══
create sequence if not exists public.so_number_seq start with 25000 increment by 1;

create function public.so_next_number() returns text
  language sql volatile
  set search_path = public, pg_temp
as $$
  select 'SO-' || lpad(nextval('public.so_number_seq')::text, 5, '0');
$$;
comment on function public.so_next_number() is '오더번호 채번 — SO- + 다섯 자리(시퀀스 so_number_seq · 25000 부터 · §2-b · Cin7 최신 SO-16714 기준 여유 8,286 · 8-a). 갈라진 문서의 접미사 a·b·c 는 여기서 안 붙인다(분할 함수 차수 · 5-d 「원래 번호는 남는다」 — PO 실물과 다르다 · 원본은 번호를 지키고 갈라져 나온 것만 접미사). 롤백된 번호는 빈다(허용 · PO 와 같은 판단). ⚠️ 시퀀스는 롤백되지 않는다 — 검증 insert 는 번호를 직접 넣는다 (2026-09-23)';

revoke all on sequence public.so_number_seq from public, anon;
grant usage, select on sequence public.so_number_seq to authenticated;
revoke all on function public.so_next_number() from public, anon;
grant execute on function public.so_next_number() to authenticated;

-- ═══ ① so — 오더 머리 (5-d · 6-a · 6-b · 8-b · 9-c · 9-d) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.so (
  id                       uuid primary key default gen_random_uuid(),
  so_number                text not null unique default public.so_next_number(),
  customer_id              uuid not null references public.customer         (id) on delete no action,
  channel                  text not null,
  intake                   text not null,
  status                   text not null default 'draft',
  closed_reason            text,
  -- 창고 · 날짜 · 참조(5-d) — FK + 원문
  location_id              uuid references public.ref_warehouse (id) on delete no action,
  location_name            text,
  order_date               date not null default current_date,
  required_by              date,
  ref                      text,
  comments                 text,
  -- 손님에서 복사해 굳는 것(5-d) — 마스터가 있는 다섯은 FK + 원문 · currency 도 FK + 원문(9-d)
  currency_id              uuid not null references public.ref_currency     (id) on delete no action,
  currency_code            text,
  payment_term_id          uuid references public.ref_payment_term (id) on delete no action,
  payment_term_name        text,
  discount_pct             numeric,
  tax_rule                 text,
  price_tier               text,
  ar_account_id            uuid references public.ref_account      (id) on delete no action,
  ar_account_code          text,
  sale_account_id          uuid references public.ref_account      (id) on delete no action,
  sale_account_code        text,
  -- 청구처 7 · 배송지 9 — 칸칸이 복사(5-d) · 낱말은 9-d
  bill_to_name             text,
  bill_to_line1            text,
  bill_to_line2            text,
  bill_to_city             text,
  bill_to_state_province   text,
  bill_to_postal_code      text,
  bill_to_country          text,
  ship_to_company          text,
  ship_to_contact          text,
  ship_to_phone            text,
  ship_to_line1            text,
  ship_to_line2            text,
  ship_to_city             text,
  ship_to_state_province   text,
  ship_to_postal_code      text,
  ship_to_country          text,
  -- 배송 · 메모(5-d)
  carrier                  text,
  tracking_number          text,
  shipping_notes           text,
  -- 형제 · 병합(5-d · 8-b) — 자기 참조 · 바로 앞 문서 · 뿌리 칸 없음
  split_from_id            uuid references public.so (id) on delete no action,
  split_reason             text,
  merged_into_id           uuid references public.so (id) on delete no action,
  -- 시각 · 사람(⬜1 · ⬜2 · 6-b · 6-g)
  created_by               uuid references public.ims_staff (id) on delete no action,
  confirmed_at             timestamptz,
  confirmed_by             uuid references public.ims_staff (id) on delete no action,
  at_wms_at                timestamptz,
  at_wms_by                uuid references public.ims_staff (id) on delete no action,
  shipped_at               timestamptz,
  shipped_by               uuid references public.ims_staff (id) on delete no action,
  invoiced_at              timestamptz,
  closed_at                timestamptz,
  cancelled_by             uuid references public.ims_staff (id) on delete no action,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  updated_by               uuid references public.ims_staff (id) on delete no action,

  constraint so_number_ck         check (so_number ~ '^SO-[0-9]{5,}[a-z]*$'),
  constraint so_status_ck         check (status in ('draft','confirmed','at_wms','picking','packed','shipped','invoiced','fulfilled','cancelled')),
  constraint so_closed_reason_ck  check (closed_reason is null or closed_reason in ('expired','superseded','voided','merged')),
  constraint so_channel_ck        check (channel in ('warehouse','pos','counter')),
  constraint so_intake_ck         check (intake in ('manual','shopify','csv','pos')),
  constraint so_split_reason_ck   check (split_reason is null or split_reason in ('stock_short','warehouse')),
  constraint so_discount_pct_ck   check (discount_pct is null or (discount_pct >= 0 and discount_pct <= 100)),
  constraint so_split_pair_ck     check ((split_from_id is null) = (split_reason is null)),
  constraint so_cancel_reason_ck  check ((status = 'cancelled') = (closed_reason is not null)),
  constraint so_merge_reason_ck   check (merged_into_id is null or closed_reason = 'merged'),
  constraint so_self_ref_ck       check (split_from_id is distinct from id and merged_into_id is distinct from id),
  constraint so_closed_at_ck      check ((status in ('fulfilled','cancelled')) = (closed_at is not null))
);
create index if not exists so_customer_idx      on public.so (customer_id);
create index if not exists so_location_idx      on public.so (location_id);
create index if not exists so_currency_idx      on public.so (currency_id);
create index if not exists so_payment_term_idx  on public.so (payment_term_id);
create index if not exists so_ar_account_idx    on public.so (ar_account_id);
create index if not exists so_sale_account_idx  on public.so (sale_account_id);
create index if not exists so_split_from_idx    on public.so (split_from_id);
create index if not exists so_merged_into_idx   on public.so (merged_into_id);
create index if not exists so_created_by_idx    on public.so (created_by);
create index if not exists so_confirmed_by_idx  on public.so (confirmed_by);
create index if not exists so_at_wms_by_idx     on public.so (at_wms_by);
create index if not exists so_shipped_by_idx    on public.so (shipped_by);
create index if not exists so_cancelled_by_idx  on public.so (cancelled_by);
create index if not exists so_updated_by_idx    on public.so (updated_by);

comment on table  public.so is 'SO 모듈 오더 머리(5-d) · ⭐ 거래 — 컷오버 때 지운다(PO 와 같다 · §11-⓪) · 한 오더는 한 창고(5-d · 나눠 보내면 오더를 가른다) · 상태 아홉(6-a) · 길 셋 channel(6-b) · 유입 넷 intake(6-b) · 금액 칸 없음(8-c 인보이스가 굳힌다) · 형제 split_from_id(바로 앞) · 병합 merged_into_id(8-b) · ⚠️ 이번 차수는 읽기만 — 쓰기 정책 0 · 전이 트리거·RPC 는 다음 차수(6-g′) · 정본 docs/design/so-module.md 5-d · §6 · §10 · 2026-09-23 신설';
comment on column public.so.so_number              is '⭐ SO-25000 부터(§2-b · 8-a) · 기본값 so_next_number() · unique · CHECK so_number_ck ^SO-[0-9]{5,}[a-z]*$ · 갈라져 나온 것만 소문자 접미사 a·b·c(5-d 「원래 번호는 남는다」 · 최대 24번 · 붙이는 자리는 분할 함수) · 손님 서류에 나간 번호가 바뀌지 않는다';
comment on column public.so.customer_id            is 'FK → customer(id) · NOT NULL · on delete no action · 인덱스 so_customer_idx · 손님을 고르면 아래 「복사해 굳는 것」이 채워진다(§1-b · 5-d)';
comment on column public.so.channel                is '⭐ 오더가 가는 길 — CHECK so_channel_ck warehouse · pos · counter(6-b · 5-d 본문의 「둘」을 뒤집었다 6-i) · 상태 전이의 모양을 정한다(warehouse 는 at_wms→picking→packed 를 지나고 pos·counter 는 confirmed→shipped) · ⚠️ counter ≠ WMS 의 fulfillment_type direct(6-b) · Shopify 는 channel 이 아니라 intake';
comment on column public.so.intake                 is '⭐ 오더가 들어온 경로 — CHECK so_intake_ck manual · shopify · csv · pos(6-b) · 전이와 무관 · 통계·연동의 축 · ⚠️ 이름은 source 가 아니다 — inv_ledger.source · ref_*.source(어느 시스템이 만들었나)와 뜻이 달라 intake 로(6-b · 검토 이견 ③′)';
comment on column public.so.status                 is '⭐ CHECK so_status_ck 아홉 — draft · confirmed · at_wms · picking · packed · shipped · invoiced · fulfilled · cancelled(6-a · ⚠️ 6-a 제목의 「열」은 세면 아홉) · 기본 draft · 끝 상태는 fulfilled·cancelled 둘(closed 없음) · at_wms 가 소유권의 선(6-e) · shipped 가 원장에서 빠지는 유일한 자리(6-d · 7-b) · ⚠️ 전이(허용 짝)는 이번에 안 건다 — 6-g′ 트리거·RPC 차수 · Cin7 Order Progress(AdditionalAttribute1 · 사람이 손으로 옮기는 표식)를 대체한다(6-a)';
comment on column public.so.closed_reason          is 'CHECK so_closed_reason_ck expired · superseded · voided · merged(6-a · 8-b) · ⚠️ fulfilled 는 없다(끝 상태 fulfilled 가 따로 있다 · 6-i) · cancelled 에만 선다 — so_cancel_reason_ck (status=cancelled) ⇔ (closed_reason not null) · expired 는 매일 도는 작업(5-g) · superseded 는 출하 확정이 닫는다(5-g) · merged 는 병합 원본(8-b) · voided 그 밖은 ④(6-a ⬜)';
comment on column public.so.location_id            is '창고 → ref_warehouse(id) · nullable(PO ship_to_warehouse_id 와 같다 · 확정 때 RPC 가 요구) · 인덱스 so_location_idx · 손님 default_location_id 로 채우되 사람이 바꾼다(5-d) · 확정 뒤 바꾸는 것은 §2-h 별도 동작 · 릴리스 전에만(6-e) · ⭐ 한 오더는 한 창고 — 라인·예약에 창고 칸이 없다(5-d · 5-f) · FK+원문(9-c ⬜3 · customer.default_location 과 짝)';
comment on column public.so.location_name          is '창고 원문(ref_warehouse.name 을 그날 값으로 복사) · FK 가 못 붙어도 남는다';
comment on column public.so.order_date             is 'NOT NULL default current_date · ⭐ 백오더 만료는 이 날짜로 잰다(5-d · required_by 가 아니다) · 갈라진 문서는 머리를 통째로 복사하므로 모체의 것(5-d)';
comment on column public.so.required_by            is '손님 요청 납기 · 날짜는 둘뿐(order_date · required_by) — Invoice date · Due date 는 인보이스의 것이라 여기 없다(5-d · §8)';
comment on column public.so.ref                    is '손님 쪽 참조(실물 AS-6674 · POS-TOR-001555 · 5-d) · 병합 때 원본에 그대로 남고 새 오더의 ref 칸 하나에 다섯을 담지 않는다(8-b)';
comment on column public.so.comments               is '오더 메모(5-d) · ⚠️ shipping_notes 와 다른 칸 · 거래 표 규약의 note 를 이 칸이 대신한다(칸을 셋 두지 않는다)';
comment on column public.so.currency_id            is 'FK → ref_currency(id) · NOT NULL(PO 머리와 짝 · 20260916144201) · 인덱스 so_currency_idx · 손님 customer.currency_id 를 복사(5-d) · ⭐ FK+원문(9-d · 5-d 「원문 하나」를 뒤집었다 · PO·SO 가 ref_currency 를 공용)';
comment on column public.so.currency_code          is '통화 원문(예 CAD) · 그날의 값 · FK 가 못 붙어도 남는다';
comment on column public.so.payment_term_id        is 'FK → ref_payment_term(id) · nullable · 인덱스 so_payment_term_idx · 손님에서 복사해 굳는다(5-d 「참조가 아니라 복사」 — 손님 조건이 반년 뒤 바뀌어도 작년 오더는 그때 조건) · ref_payment_term 은 PO 와 공용(§4)';
comment on column public.so.payment_term_name      is '결제조건 원문 · 그날의 값(5-d) · 인보이스 due date 계산의 근거는 ④ 차수';
comment on column public.so.discount_pct           is '손님 할인 하나(§1-k · 5-d 복사) · CHECK 0~100(⬜6) · 줄에서 바꿀 수 있다(5-e so_line.discount_pct) · PO 의 체인 할인과 다르다(§4)';
comment on column public.so.tax_rule               is '세금 규칙 원문(배송지 기준 · 손님에 저장 · §1-m) · ⚠️ 원문만 — ref_tax_rule 은 미결 · 생기면 FK 칸을 옆에(9-c ⬜2) · 인보이스(§8) 전에 서야 한다';
comment on column public.so.price_tier             is '가격 티어 원문(§1-j · 5-e list_price 의 근거) · ⚠️ 원문만 — ref_price_tier 는 어디에도 없다(9-c ⬜2) · 오더 가격 계산 전에 서야 한다';
comment on column public.so.ar_account_id          is 'FK → ref_account(id) · nullable · 인덱스 so_ar_account_idx · 손님 ar_account_id 를 복사(5-d) · 원문은 code(자연키 · po-module)';
comment on column public.so.ar_account_code        is 'AR 계정 원문 Code(예 _61_) · 그날의 값';
comment on column public.so.sale_account_id        is 'FK → ref_account(id) · nullable · 인덱스 so_sale_account_idx · 손님 sale_account_id 를 복사(5-d) · 제품 매출 계정(예 _98_ · 운임은 so_charge.account · _99_)';
comment on column public.so.sale_account_code      is '매출 계정 원문 Code · 그날의 값';
comment on column public.so.bill_to_name           is '청구처 — ⭐ 칸칸이 복사(5-d · Caleb 2026-09-21 · 뭉치면 주별 매출·세금 검산에서 state 를 못 센다) · 주소록(customer_address)을 FK 로 가리키지 않는다(손님이 이사해도 지난 오더의 청구처는 그날 것) · 채우는 길 셋(자기 주소록 · default_bill_to_customer_id 의 주소록 · 손으로 · 5-d 드롭십) · 손으로 넣은 것은 주소록에 되돌려 담지 않는다';
comment on column public.so.bill_to_state_province is '청구처 주/도 · ⭐ 낱말은 state_province(9-d · 5-d 본문 bill_to_state 를 뒤집었다 — ref_warehouse · supplier_address · customer_address · po 머리와 한 낱말)';
comment on column public.so.bill_to_postal_code    is '청구처 우편번호 · ⭐ 낱말은 postal_code(9-d · 5-d 본문 bill_to_postcode 를 뒤집었다)';
comment on column public.so.ship_to_company        is '배송지 회사 — 칸칸이 복사 · 채우는 길 셋(5-d) · 청구처와 다를 수 있다(드롭십 · §1-s)';
comment on column public.so.ship_to_contact        is '배송지 받는 사람';
comment on column public.so.ship_to_phone          is '⭐ Cin7 에 없는 칸(5-d) — 드롭십이면 택배사가 연락할 상대가 우리 손님이 아니라 받는 사람이다 · 지금은 Shipping notes 에 적고 있을 것(짐작 · 실물 미확인)';
comment on column public.so.ship_to_state_province is '배송지 주/도 · 낱말은 state_province(9-d) · §1-i 창고 라우팅의 근거(BC·AB·MB → 에드먼튼) — ⚠️⚠️ 자동 라우팅 금지 · 제안까지만';
comment on column public.so.ship_to_postal_code    is '배송지 우편번호 · 낱말은 postal_code(9-d)';
comment on column public.so.carrier                is '택배사 · 손님 default_carrier 가 기본값(5-d) · 지금은 Freightcom 에서 손으로(§1-p)';
comment on column public.so.tracking_number        is '추적번호 · 지금은 Freightcom 에서 받아 손으로 넣는다(§1-p) · ⬜ Freightcom API 를 붙이면 자동으로 채워지는 자리(5-d)';
comment on column public.so.shipping_notes         is '창고·배송 지시 · comments(오더 메모)와 다른 칸(5-d) · Shopify 유입의 Order Note 등이 여기로 온다 — 연동 때 어느 칸으로 보낼지 가른다';
comment on column public.so.split_from_id          is '⭐ 갈라져 나온 바로 앞 문서 → so(id) · 자기 참조 · nullable · on delete no action · 인덱스 so_split_from_idx · PO 와 같다(po-module 2538행 · 뿌리를 가리키는 칸은 두지 않는다 — 한 번에 모으는 것은 so_number like ''SO-25001%'') · 사슬은 재귀 함수 so_family_members 가 모은다(분할 함수 차수) · so_split_pair_ck (split_from_id is null) = (split_reason is null) · so_self_ref_ck 자기 자신 금지';
comment on column public.so.split_reason           is '⭐ PO 에 없는 칸(5-d) — 갈라지는 계기가 둘: CHECK so_split_reason_ck stock_short(재고 부족 · Authorize 때·출하 확정 때 §1-f·§2-f) · warehouse(창고 분리 · 한 오더는 한 창고) · split_from_id 와 짝(so_split_pair_ck)';
comment on column public.so.merged_into_id         is '⭐ 병합으로 합쳐진 새 오더 → so(id) · 자기 참조 · nullable · on delete no action · 인덱스 so_merged_into_idx(8-b · 5-d 에 없던 칸 · 8-j) · 원본은 번호를 지킨 채 status=cancelled · closed_reason=merged 로 닫힌다 — so_merge_reason_ck (merged_into_id not null ⇒ closed_reason=merged) · 릴리스 전에만(8-b) · void 와 다른 점: 흔적이 남는다 · ⚠️ so_family_members 는 이 축을 재귀에 섞지 않고 반환에 merged_into 칸 하나(8-j ⬜②)';
comment on column public.so.created_by             is '만든 사람 → ims_staff(id) · nullable · 인덱스 so_created_by_idx(PO 와 같다 · 20260916144201) · RPC 가 auth.uid() → ims_staff.id 로 채운다(화면이 주지 않는다 · anon key 공개)';
comment on column public.so.confirmed_at           is '확정(Cin7 의 Authorize) 시각 · 6-a confirmed · 이때 할당이 갈린다(6-d) · 갈라진 문서는 확정 흔적을 물려받는다(5-d)';
comment on column public.so.confirmed_by           is '확정을 누른 사람 → ims_staff(id) · 인덱스 so_confirmed_by_idx';
comment on column public.so.at_wms_at              is '⭐ Release to WMS 를 누른 시각 — 소유권이 창고로 넘어가는 선(6-e · 6-a at_wms) · ⚠️ 이름은 released_at 이 아니다 — so_reserve.released_at(할당을 풀었다)과 두 뜻이 된다(6-a 가 status 이름을 released→at_wms 로 바꾼 바로 그 이유 · ⬜1)';
comment on column public.so.at_wms_by              is 'Release to WMS 를 누른 사람 → ims_staff(id) · manager 이상(6-h) · 인덱스 so_at_wms_by_idx';
comment on column public.so.shipped_at             is '⭐ 나간 시각 — 원장에서 빠지는 유일한 자리(6-d · 7-b so_out 한 오더에 한 번) · 순서 고정 shipped → invoiced(6-g) · packed 에 오래 머문 오더를 찾을 때 시각이 필요하다(6-g)';
comment on column public.so.shipped_by             is '「나갔다」를 누른 사람 → ims_staff(id) · 인덱스 so_shipped_by_idx · ⭐ counter 길은 이것이 유일한 사람 흔적(6-b ① — 다른 길은 픽커·패커가 WMS 에 남는다) · warehouse 길은 WMS 출하 사건이 옮기므로 null 일 수 있다';
comment on column public.so.invoiced_at            is '송장이 나간 시각(6-a invoiced) · 인보이스 묶음(so_invoice · 8-c)이 발행되면 담긴 오더 전부가 함께 넘어간다 · shipped_at 뒤(6-g 순서 고정)';
comment on column public.so.closed_at              is '끝 상태(fulfilled · cancelled)에 선 시각(⬜2) — so_closed_at_ck (status in fulfilled,cancelled) ⇔ (closed_at not null) · so_family_members 반환 모양이 이 칸을 쓴다(5-d · PO 와 같다) · ⚠️ WMS 롤백으로 끝 상태에서 내려올 때 closed_at 을 함께 비우는 것은 RPC 차수의 일(전이 트리거·허용 짝 하향 · 6-g′ · 8-h)';
comment on column public.so.cancelled_by           is '취소한 사람 → ims_staff(id) · 인덱스 so_cancelled_by_idx · 시각은 closed_at(cancelled 도 끝 상태) · 이유는 closed_reason · 자동 닫힘(expired 매일 작업 · superseded 출하 확정)은 null = system';
comment on column public.so.updated_by             is '마지막으로 고친 사람 → ims_staff(id) · so_touch(ims_touch) 가 auth.uid() 로 채운다 · null = system · 인덱스 so_updated_by_idx';

-- ═══ ② so_line — 제품 줄 (5-e) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.so_line (
  id                 uuid primary key default gen_random_uuid(),
  so_id              uuid not null references public.so      (id) on delete cascade,     -- ⭐ 문서 → 소유 줄 · 거래 표 규약 예외(po_line 선례 · 검토 이견 1)
  line_no            integer not null,
  product_id         uuid not null references public.product (id) on delete no action,
  -- 마스터에서 복사해 굳는다(5-e)
  sku                text not null,
  product_name       text,
  unit               text,
  pack_factor        numeric not null,
  -- 수량(판매 단위) · 가격 넷 · 부가 셋(5-e)
  qty_ordered        numeric not null,
  qty_shipped        numeric not null default 0,
  list_price         numeric(18,7),
  discount_pct       numeric,
  unit_price         numeric(18,7) not null default 0,
  price_override     boolean not null default false,
  surcharge_pct      numeric,
  surcharge_amount   numeric,
  surcharge_label    text,
  tax_rule           text,
  comments           text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  updated_by         uuid references public.ims_staff (id) on delete no action,

  constraint so_line_line_no_ck        check (line_no >= 1),
  constraint so_line_pack_factor_ck    check (pack_factor > 0),
  constraint so_line_qty_ordered_ck    check (qty_ordered > 0),
  constraint so_line_qty_shipped_ck    check (qty_shipped >= 0),
  constraint so_line_list_price_ck     check (list_price is null or list_price >= 0),
  constraint so_line_unit_price_ck     check (unit_price >= 0),
  constraint so_line_discount_pct_ck   check (discount_pct is null or (discount_pct >= 0 and discount_pct <= 100)),
  constraint so_line_surcharge_ck      check (surcharge_pct is null or surcharge_amount is null),
  constraint so_line_so_id_line_no_key unique (so_id, line_no)
);
create index if not exists so_line_so_idx         on public.so_line (so_id);
create index if not exists so_line_product_idx    on public.so_line (product_id);
create index if not exists so_line_updated_by_idx on public.so_line (updated_by);

comment on table  public.so_line is 'SO 모듈 제품 줄(5-e) · ⭐ 거래 — 컷오버 때 지운다 · 자연키 (so_id, line_no)(PO 와 같다) · ⚠️ (so_id, product_id) 유니크 없음 — 단가가 다른 두 줄이 있다(5-e · 합치는 일은 화면·import) · 수량은 판매 단위 + pack_factor(낱개는 qty × pack_factor · PO 는 낱개 저장 · §4) · ⚠️ barcode 없음(스캔은 그 시점 최신 값 · 5-e) · 원장 so_out 의 line_ref 가 이 id 다(7-b) · 정본 docs/design/so-module.md 5-e · 2026-09-23 신설';
comment on column public.so_line.so_id            is 'FK → so(id) · NOT NULL · ⭐ on delete cascade — 문서 → 소유 줄(거래 표 규약 예외 · po-module 1414행 · po_line 선례 · 검토 이견 1) · 인덱스 so_line_so_idx · ⚠️ 확정된 오더는 지우지 않고 cancelled 로(PO 2490행) — cascade 는 draft 삭제에서만 일한다';
comment on column public.so_line.line_no          is '문서 안 차례(1부터 · CHECK) · unique (so_id, line_no) · CSV 에 적힌 순서를 지킨다(§1-a) · 새 줄이 붙으면 겹치므로 형제 합계는 product_id 로 접는다(5-d so_family_lines)';
comment on column public.so_line.product_id       is 'FK → product(id) · NOT NULL · 잇는 것(마스터 · 형제 합계 · 원장) · 인덱스 so_line_product_idx(5-e 「FK + 굳힌 sku 둘 다」)';
comment on column public.so_line.sku              is '⭐ 굳힌 값 — 그때 서류에 찍힌 SKU(5-e · product_id 는 잇는 것) · NOT NULL · 재적재·마스터 변경이 덮지 않는다';
comment on column public.so_line.product_name     is '굳힌 값 — 제품 이름이 바뀌면 지난 송장의 품명이 함께 바뀌는 것을 막는다(5-e)';
comment on column public.so_line.unit             is '굳힌 값 — 판매 단위 이름(5-e)';
comment on column public.so_line.pack_factor      is '⭐ 굳힌 값 · NOT NULL · CHECK > 0 — 12개들이를 24개들이로 바꾸면 과거 「3 박스」가 36 인지 72 인지 알 수 없게 된다(5-e) · 정본은 BOM Quantity(asung-po) · 그 순간의 값 · WMS required_base = qty × factor 가 이 값에 기댄다';
comment on column public.so_line.qty_ordered      is '주문 수량(판매 단위) · NOT NULL · CHECK > 0 · 낱개는 qty × pack_factor 로 낸다(5-e) · qty_ordered − qty_shipped 가 백오더 수량(§2-f)';
comment on column public.so_line.qty_shipped      is '출하 확정이 채운다(5-e · §2-f 출하 실적에서 백오더가 나온다) · NOT NULL default 0 · CHECK >= 0 · ⚠️ 상한 없음 — Over-pick 은 장부 무변이지만 「더 나갈 수 있는지」는 안 봤다(⬜6 · 짐작 없이 열어 둔다)';
comment on column public.so_line.list_price       is '티어 가격(그날의 값 · §1-k 길의 첫 단계) · numeric(18,7)(po_line.unit_price 와 한 관례) · CHECK >= 0';
comment on column public.so_line.discount_pct     is '손님 할인 %(오더 머리에서 복사 · 줄에서 바꿀 수 있다 · 5-e) · CHECK 0~100';
comment on column public.so_line.unit_price       is '실제 단가 · numeric(18,7) · NOT NULL default 0 · CHECK >= 0 — ⚠️ 0 을 막지 않는다(샘플은 수량이 있고 단가가 0 · 5-e · PO 와 같다)';
comment on column public.so_line.price_override   is '⭐ true 면 unit_price 는 계산 결과가 아니다(사람이 덮어썼다 · 5-e · USD 손님 둘 §1-j) · 가격 넷을 다 남기는 이유: unit_price 하나면 「왜 이 값인가」를 풀 수 없다';
comment on column public.so_line.surcharge_pct    is '⭐ 부가(보복 관세 등 · Caleb 2026-09-21 · 5-e) — 한시적이라 가격을 올리지 않는다 · surcharge_amount 와 둘 중 하나만(CHECK so_line_surcharge_ck) · 둘 다 비면 없는 것 · ⚠️ so_charge 와 다른 자리 — 특정 제품에 붙는다(운임은 오더에 한 번)';
comment on column public.so_line.surcharge_amount is '부가 금액 · surcharge_pct 와 둘 중 하나만(CHECK) · 우리 마진이 아니라 정부에 내는 돈 — 매출 분석에서 가른다(5-e)';
comment on column public.so_line.surcharge_label  is '부가 이름(예 US Tariff) — 몇 년 뒤 「이게 무엇이었나」를 알 수 있어야 한다(5-e)';
comment on column public.so_line.tax_rule         is '줄 세금 규칙 원문(5-e) · ⚠️ 원문만 — ref_tax_rule 미결(9-c ⬜2)';
comment on column public.so_line.comments         is '줄 메모(5-e)';
comment on column public.so_line.updated_by       is '마지막으로 고친 사람 → ims_staff(id) · so_line_touch(ims_touch) · 인덱스 so_line_updated_by_idx';

-- ═══ ③ so_charge — 추가 비용 · 서비스 줄 (5-e) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.so_charge (
  id            uuid primary key default gen_random_uuid(),
  so_id         uuid not null references public.so (id) on delete cascade,     -- ⭐ 문서 → 소유 줄(검토 이견 1)
  line_no       integer not null,
  name          text not null,
  description   text,
  amount        numeric not null,
  tax_rule      text,
  account_id    uuid references public.ref_account (id) on delete no action,
  account_code  text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,

  constraint so_charge_line_no_ck        check (line_no >= 1),
  constraint so_charge_so_id_line_no_key unique (so_id, line_no)
);
create index if not exists so_charge_so_idx         on public.so_charge (so_id);
create index if not exists so_charge_account_idx    on public.so_charge (account_id);
create index if not exists so_charge_updated_by_idx on public.so_charge (updated_by);

comment on table  public.so_charge is 'SO 모듈 추가 비용·서비스 줄(5-e · 실물 Freight · 5 BOXES / PUROLATOR · 110.50 · _99_) · ⭐ 거래 — 컷오버 때 지운다 · 표를 나눈 이유: 재고가 없고 매출 계정이 _99_ 로 따로고 화면 합계도 갈라 보여 준다(§1-p) · ⚠️ PO 와 방향이 반대 — po_charge 는 원가에 얹고(landed) so_charge 는 매출로(§4) · 모양도 다르다 — po_charge 는 경비처가 있는 문서 + 배분표 · so_charge 는 오더에 붙는 줄 · 배분표 없음(운임은 한 오더에 한 번) · 자연키 (so_id, line_no)(⬜9) · 정본 docs/design/so-module.md 5-e · 2026-09-23 신설';
comment on column public.so_charge.so_id        is 'FK → so(id) · NOT NULL · ⭐ on delete cascade — 문서 → 소유 줄(검토 이견 1) · 인덱스 so_charge_so_idx';
comment on column public.so_charge.line_no      is '문서 안 차례(1부터 · CHECK) · unique (so_id, line_no) — so_line 과 같은 자연키(⬜9 · 두 표의 line_no 축은 따로다)';
comment on column public.so_charge.name         is '비용 이름(예 Freight) · NOT NULL';
comment on column public.so_charge.description  is '설명(예 5 BOXES / PUROLATOR · §1-p 실물)';
comment on column public.so_charge.amount       is '금액 · NOT NULL · ⚠️ 부호 CHECK 없음 — Cin7 에서 additional cost 에 마이너스를 넣는 우회(po-module §7-b-D)가 판매에도 있었는지 안 봤다 · 막지 않는다 · 운임 견적은 나중에 들어오므로 오더 만들 때 값이 없을 수 있다(§2-h · 줄 자체를 나중에 붙인다)';
comment on column public.so_charge.tax_rule     is '세금 규칙 원문(실물 GST (Sale)) · ⚠️ 원문만 — ref_tax_rule 미결(9-c ⬜2)';
comment on column public.so_charge.account_id   is 'FK → ref_account(id) · nullable · 인덱스 so_charge_account_idx · FK + 원문(code)(5-e · 5-a 계정과 같은 모양) · ⚠️ 기본 _99_(Freight Sales Account)은 표 기본값이 아니다 — id 는 테스트·운영이 달라 마이그레이션이 박을 수 없다 · 화면·RPC 가 code=''_99_'' 를 찾아 넣는다(검토 이견 6) · 취급 수수료·특별 포장비가 생기면 계정이 다르다(5-e)';
comment on column public.so_charge.account_code is '계정 원문 Code(예 _99_) · 그날의 값 · 크레딧 노트가 같은 계정으로 되돌아가야 QuickBooks 에서 맞는다(8-g)';
comment on column public.so_charge.updated_by   is '마지막으로 고친 사람 → ims_staff(id) · so_charge_touch(ims_touch) · 인덱스 so_charge_updated_by_idx';

-- ═══ ④ so_reserve — 예약: 할당 · 프리오더 · 보류 · 백오더 (5-f · 6-d) ═══
-- 컷오버: 거래 ⇒ 지운다.
create table if not exists public.so_reserve (
  id             uuid primary key default gen_random_uuid(),
  so_line_id     uuid not null references public.so_line (id) on delete no action,     -- ⭐ 이력 — cascade 아님(검토 이견 1)
  qty_allocated  numeric not null,
  kind           text not null,
  allocated_at   timestamptz not null default now(),
  allocated_by   uuid references public.ims_staff (id) on delete no action,
  released_at    timestamptz,
  released_by    uuid references public.ims_staff (id) on delete no action,
  open_line_id   uuid generated always as (case when released_at is null then so_line_id end) stored,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.ims_staff (id) on delete no action,

  constraint so_reserve_qty_ck       check (qty_allocated > 0),
  constraint so_reserve_kind_ck      check (kind in ('allocated','preorder','hold','backorder')),
  constraint so_reserve_open_line_uq unique (open_line_id)
);
create index if not exists so_reserve_so_line_idx      on public.so_reserve (so_line_id);
create index if not exists so_reserve_allocated_by_idx on public.so_reserve (allocated_by);
create index if not exists so_reserve_released_by_idx  on public.so_reserve (released_by);
create index if not exists so_reserve_updated_by_idx   on public.so_reserve (updated_by);

comment on table  public.so_reserve is 'SO 모듈 예약(5-f · 이름이 so_reserve 인 이유: kind 넷 중 셋은 할당이 아니라 「잡지 않기로 한 기록」) · ⭐ 거래 — 컷오버 때 지운다 · ⭐ 할당은 원장 밖(§2-d · 원장에는 shipped 때 so_out 만) · 창고 단위(한 오더는 한 창고 · 창고 칸·bin 칸 없음 · 칸은 픽 단계에서) · ⭐ 지우지 않고 released_at 을 찍는다(5-f · 보류가 잦다 · §2-d 「이력 안 남김」을 뒤집었다) · 가용(창고,제품) = 창고 잔고 − Σ qty_allocated where kind=allocated and released_at is null(5-f · 함수 하나 · RPC 차수) · 정본 docs/design/so-module.md 5-f · 6-d · 2026-09-23 신설';
comment on column public.so_reserve.so_line_id    is 'FK → so_line(id) · NOT NULL · ⭐ on delete no action — 이력이다 · 예약이 붙은 줄은 확정된 적이 있으므로 지우지 않고 cancelled 로(검토 이견 1 · po_receipt_line→po_line 과 같은 결) · 인덱스 so_reserve_so_line_idx';
comment on column public.so_reserve.qty_allocated is '잡은(또는 잡지 않기로 한) 수량 · 판매 단위 · NOT NULL · CHECK > 0';
comment on column public.so_reserve.kind          is 'CHECK so_reserve_kind_ck 넷 — allocated(재고가 있고 잡았다 · 시스템) · backorder(재고가 없다 · 시스템 · 스플릿이 표시) · preorder(물건이 아직 안 들어왔다 · 사람이 고른다) · hold(재고는 있지만 안 잡는다 · 사람 · 할당 해제 동작이 표시)(6-d · 5-f) · ⚠️ pos·counter 는 allocated 만(6-d 실물을 손에 쥔 길 · 재고를 보지 않는다) · preorder·hold·backorder 는 가용에서 빼지 않는다(5-f)';
comment on column public.so_reserve.allocated_at  is '이 줄이 선 시각 · NOT NULL default now()';
comment on column public.so_reserve.allocated_by  is '잡은 사람 → ims_staff(id) · 시스템이 정한 것(allocated·backorder)은 null = system · 인덱스 so_reserve_allocated_by_idx';
comment on column public.so_reserve.released_at   is '⭐ 푼 시각 — 지우지 않고 남긴다(5-f · 「왜 이 오더가 오래 걸렸나」에 답한다) · 풀린 줄은 open_line_id 가 null 이 되어 유니크에서 빠진다 · 상태가 바뀌면(할당 → 보류) 앞 줄을 풀고 새 줄을 만든다 · ⚠️ 이름 released 는 「할당을 풀었다」 — so.at_wms_at(Release to WMS)과 다른 뜻(⬜1)';
comment on column public.so_reserve.released_by   is '푼 사람 → ims_staff(id) · 자동 해제(취소 · 창고 변경 RPC)는 null = system · 인덱스 so_reserve_released_by_idx';
comment on column public.so_reserve.open_line_id  is '⭐ 생성 칸 — released_at 이 null 이면 so_line_id · 아니면 null · 전체 유니크 so_reserve_open_line_uq 가 「한 라인에 안 풀린 줄은 하나 — 어느 kind 든」을 막는다(5-f · Caleb 2026-09-21 · WHERE 없는 전체 유니크라 부분 유니크 금지(규칙 29)에 걸리지 않는다) · ⭐ plain unique — deferrable 아님(검토 이견 4): RPC 는 풀고(released_at) → 거는(insert) 두 문장이라 즉시 검사로 된다 · 거꾸로 짜면 23505 로 잡힌다(그것이 맞다) · customer_*_default_uq(③ · 한 upsert 문장 안 교대)와 다르게 둔 이유 · deferrable 은 on_conflict 기준이 못 된다(9-i ⑪) · 잠금 pg_advisory_xact_lock(hashtext(''so_reserve:''||so_line_id))은 RPC 의 일(5-f) — 유니크는 마지막 방어';
comment on column public.so_reserve.updated_by    is '마지막으로 고친 사람 → ims_staff(id) · so_reserve_touch(ims_touch) · 인덱스 so_reserve_updated_by_idx';

-- ═══ 트리거 — <표>_touch → 공용 ims_touch() (20260918133858 · ⚠️ 다시 만들지 않는다) ═══
create trigger so_touch         before update on public.so         for each row execute function public.ims_touch();
create trigger so_line_touch    before update on public.so_line    for each row execute function public.ims_touch();
create trigger so_charge_touch  before update on public.so_charge  for each row execute function public.ims_touch();
create trigger so_reserve_touch before update on public.so_reserve for each row execute function public.ims_touch();

-- ═══ RLS · 권한 — ⭐⭐ 읽기만(⬜7) · 쓰기 정책 0 · 쓰기 RPC 차수에서 sales 묶음·전이 트리거와 함께 연다 ═══
alter table public.so         enable row level security;
alter table public.so_line    enable row level security;
alter table public.so_charge  enable row level security;
alter table public.so_reserve enable row level security;

create policy so_select         on public.so         for select to authenticated using (true);
create policy so_line_select    on public.so_line    for select to authenticated using (true);
create policy so_charge_select  on public.so_charge  for select to authenticated using (true);
create policy so_reserve_select on public.so_reserve for select to authenticated using (true);

revoke all on public.so         from public, anon, authenticated;
revoke all on public.so_line    from public, anon, authenticated;
revoke all on public.so_charge  from public, anon, authenticated;
revoke all on public.so_reserve from public, anon, authenticated;
grant select on public.so         to authenticated;
grant select on public.so_line    to authenticated;
grant select on public.so_charge  to authenticated;
grant select on public.so_reserve to authenticated;

-- 검증(회신에 따로 · psql heredoc 두 덩어리 · 시퀀스 소비 금지): 표 4 · 행 0 · 정책 4(<표>_select) · 트리거 _touch 4 · 제약 p 4 · u 4(so_number · so_line·so_charge 의 (so_id,line_no) · so_reserve_open_line_uq) · c 23 ·
--   f 24 · 인덱스 24(so 14 · so_line 3 · so_charge 3 · so_reserve 4) · 권한 anon 0 · authenticated SELECT 만 · 시퀀스 start 25000 · last_value null · so_number 기본값 so_next_number() ·
--   실동작: 23514(status · channel · intake · closed_reason · split 짝 · surcharge) · 23505(open_line_id) · 23503(FK) · 42501(authenticated insert) · select 통과 · rollback.
