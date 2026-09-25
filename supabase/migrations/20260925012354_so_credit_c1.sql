-- ═══ SO 크레딧 ⓒ1 — 크레딧 노트 표 셋 · 번호 CR-01000~ · 리스탁킹 피 설정 · 원장 창구 credit_in(두 층) · 재생성 일치(inv_layer_apply 재발행) · 발행·취소·읽기 창구 (2026-09-24 · 지시서 ~/asung/prompts/so-credit-1.md · 판정 회신 Caleb 2026-09-24 집) ═══
-- 자리: §8 의 마지막 차수 ⓒ(ⓐ ✅ ⓑ ✅). ⓑ1 20260924234250 · ⓑ2 20260925001733 · ③a 20260924141140(inv_post_sale · inv_layer_post_sale 선례) 위에 선다. ⭐ 새 일하는 방식의 첫 실물(시험 적용 장치).
-- 판정(Caleb 2026-09-24 · 말 그대로 요약)
--   판정 1 두 갈래 — 줄마다 「정상 칸으로 돌아온다(credit_in)」 / 「안 돌아온다(돈만 · 사유)」 · B급 칸은 나중(줄에 「돌아가는 칸」을 적어 두면 B급이 서도 표·사건 무접촉 · 사유 b_grade 는 그날 재고 조정으로 넣을 목록)
--   판정 2 반품 접수 문서 없음 — 검수가 끝난 뒤 크레딧 노트 하나에 · 판정 3 발행은 manager 이상 · 초안 없음
--   판정 4·5 기본 100%(원 인보이스 줄의 단가·할인·세율 · 줄마다 반올림) · 원 인보이스 발행일 + 60일이 지났으면 알림만(자동으로 안 붙인다) · 매니저가 넣으면 Restocking fee 줄 20% 미리 채움 · % 바꿀 수 있다 · 60·20 은 설정(잠금)
--   판정 6 전환 전 Cin7 판매의 반품도 IMS 크레딧으로 — 원본 = Cin7 번호 원문(종이 cin7_invoice_number · 되짚기 열쇠 cin7_order_number · 0-4) · 줄은 SKU·수량·그때 단가를 손으로 · 원가는 원장의 Cin7 sale_out 소비 기록에서
--   판정 7 리스탁킹 피 계정은 비워 둔다(설정 so_credit_restock_fee_account_code 빈 값) · 수수료 줄을 넣을 때 매니저가 계정을 고른다(없으면 거부) · 계정 코드 키는 잠금 밖
-- 이견(✅) 0-2 원장 CHECK 넓힐 것 없음(credit_in · creditnote · ims · return_restore · reversal 전부 있다) · 0-3 두 축의 되짚기 열쇠 = 오더 번호(SO-…) → inv_layer_consume(doc_type sale · reason sale) · 함수 하나 · 0-5 갈래 ① 복원 → ② 남은 레이어 가중평균 → ③ 최근 원가(17-e) → ④ unknown ·
--   0-6 inv_layer_apply 재발행(IMS 문에서 credit_in 을 창구로 · hint) · 0-8 수수료 줄에도 그 세율(음수) · 0-10 취소 = 활성 alloc 없음 ∧ 돌아온 레이어 소진 0 → 반대 credit_in + reversal 소진 · 0-11 크레딧 줄은 so_invoice_line 을 가리키고 rate_pct 를 굳힌다 · ⬜4 리스탁 칸 '' 불허 · 기본 ims_last_bin · 창고 = 반품을 받은 창고
-- ⓒ2 몫(여기 없음): so_customer_balance 진 빚 · so_invoice_issue ② 크레딧 · so_invoice_cancel auto 크레딧 풀기 · so_payment_refund 한도 · so_detail · so_credit_attach/detach — so_credit_alloc 표는 여기서 세운다(취소 가드가 본다)
-- 검증 ~/asung/prompts/so-credit-1a-verify.sql(새 틀 · -v mig=이 파일 로 시험 적용) · 시퀀스 셋(오더 · 인보이스 · 크레딧) 머리에서 읽고 끝에서 되돌림

-- ═══ ① 설정 셋 — 리스탁킹 피(판정 5·7) · 60·20 은 잠금 목록에(supervisor 이상 · 양의 정수) · 계정 코드는 잠금 밖(빈 값 = 없음 → 수수료 줄에 계정을 요구) ═══
insert into public.inv_config (key, value, note) values
  ('so_credit_restock_fee_days', '60', 'SO 크레딧 · 원 인보이스 발행일 + 이 일수가 지나면 리스탁킹 피 알림(자동으로 붙이지 않는다 · 판정 5 · so-module §19)'),
  ('so_credit_restock_fee_pct',  '20', 'SO 크레딧 · Restocking fee 줄을 넣을 때 미리 채우는 %(바꿀 수 있다 · 판정 5)'),
  ('so_credit_restock_fee_account_code', '', 'SO 크레딧 · Restocking fee 줄의 기본 계정 code(ref_account) · 빈 값 = 없음 → 매니저가 줄마다 고른다(판정 7 · 회계사가 정하면 값만 넣는다 · _94_ Surcharge · _47_ Miscellaneous Income 후보)')
on conflict (key) do nothing;

create or replace function public.ims_config_locked_keys() returns text[]
  language sql immutable
  set search_path = public, pg_temp
as $$
  select array['so_backorder_expire_days', 'so_credit_restock_fee_days', 'so_credit_restock_fee_pct'];       -- ⭐ 다음에 잠글 키는 여기 한 줄 — 계정 코드 키(so_credit_restock_fee_account_code)는 잠금 밖(양의 정수 트리거와 맞지 않는다 · 판정 7)
$$;
comment on function public.ims_config_locked_keys() is '⭐ inv_config 에서 supervisor 이상만 바꿀 수 있는 키 목록(판정 14 · 2026-09-24 · ⓒ1 셋) — so_backorder_expire_days · so_credit_restock_fee_days · so_credit_restock_fee_pct · 트리거 inv_config_guard 가 읽는다(양의 정수) · 키를 더하면 여기 한 곳 · 계정 코드 키는 잠금 밖';

-- ═══ ② 번호 CR-01000~(8-a · 접두어 CR- · 재사용 금지) ═══
create sequence if not exists public.so_credit_number_seq start with 1000 increment by 1;
create function public.so_credit_next_number() returns text
  language sql volatile
  set search_path = public, pg_temp
as $$ select 'CR-' || lpad(nextval('public.so_credit_number_seq')::text, 5, '0'); $$;
comment on function public.so_credit_next_number() is '크레딧 번호 채번(8-a · Caleb 2026-09-22) — CR-01000 부터(Cin7 CR-00628 · 여유 372) · 취소한 번호는 재사용하지 않는다 · ⚠️ 시퀀스는 롤백되지 않는다 — 검증은 rollback 밖 setval(1000, false) · so_credit 이 비어 있을 때만';
revoke all on sequence public.so_credit_number_seq from public, anon, authenticated;
revoke all on function public.so_credit_next_number() from public, anon, authenticated;

-- ═══ ③ 표 셋 ═══
-- 3-a so_credit — 머리(8-g · 판정 6 원본 둘 · 반품을 받은 창고 · Cin7 크레딧의 세금 규칙)
create table if not exists public.so_credit (
  id                    uuid primary key default gen_random_uuid(),
  credit_number         text not null unique default public.so_credit_next_number(),
  status                text not null default 'issued',
  customer_id           uuid not null references public.customer (id) on delete no action,          -- 청구처(돈을 돌려받을 손님)
  currency_id           uuid not null references public.ref_currency (id) on delete no action,
  currency_code         text,
  invoice_id            uuid references public.so_invoice (id) on delete no action,                  -- IMS 원본 인보이스(살아 있어야 한다)
  cin7_invoice_number   text,                                                                        -- 판정 6 · 종이의 번호 원문(49xxx)
  cin7_order_number     text,                                                                        -- 판정 6 · 되짚기 열쇠(SO-xxxxx · 원장 sale_out doc_number · 0-4) · 비면 갈래 ②③
  cin7_invoice_date     date,                                                                        -- 판정 6 · 수수료 알림의 기준일(손으로)
  origin_invoice_on     date,                                                                        -- 원 인보이스 발행일(IMS 복사 · Cin7 손) · 수수료 알림 기준(판정 5)
  reason                text not null,
  note                  text,
  warehouse_id          uuid not null references public.ref_warehouse (id) on delete no action,      -- 반품을 받은 창고(⬜4 · 기본 원 판매 창고)
  warehouse_name        text,
  tax_rule_id           uuid references public.ref_tax_rule (id) on delete no action,                -- Cin7 크레딧만(IMS 는 줄이 인보이스 오더 세율을 굳힌다)
  tax_rule              text,
  rate_pct              numeric(7,4),
  issued_on             date not null,
  issued_by             uuid references public.ims_staff (id) on delete no action,
  lines_amount          numeric not null default 0,                                                  -- product · freight · tax · other 줄 합(≥ 0)
  fee_amount            numeric not null default 0,                                                  -- restocking_fee 줄 합(≤ 0)
  tax_amount            numeric not null default 0,
  total                 numeric not null default 0,                                                  -- = lines + fee + tax · 손님 앞으로 넘어가는 금액(진 빚 · 8-e)
  cancelled_at          timestamptz,
  cancelled_by          uuid references public.ims_staff (id) on delete no action,
  cancel_note           text,
  created_by            uuid references public.ims_staff (id) on delete no action,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  updated_by            uuid references public.ims_staff (id) on delete no action,
  constraint so_credit_number_ck       check (credit_number ~ '^CR-[0-9]{5,}$'),
  constraint so_credit_status_ck       check (status in ('issued','cancelled')),
  constraint so_credit_reason_ck       check (reason in ('customer_return','damaged','billing_error','other')),
  constraint so_credit_origin_ck       check ((invoice_id is null) <> (cin7_invoice_number is null)),
  constraint so_credit_lines_ck        check (lines_amount >= 0),
  constraint so_credit_fee_ck          check (fee_amount <= 0),
  constraint so_credit_total_ck        check (total = lines_amount + fee_amount + tax_amount),
  constraint so_credit_cancel_ck       check ((status = 'cancelled') = (cancelled_at is not null)),
  constraint so_credit_cancel_by_ck    check ((cancelled_at is null) = (cancelled_by is null)),
  constraint so_credit_cancel_note_ck  check ((cancelled_at is null) = (cancel_note is null))
);
create index if not exists so_credit_customer_idx     on public.so_credit (customer_id);
create index if not exists so_credit_invoice_idx      on public.so_credit (invoice_id);
create index if not exists so_credit_currency_idx     on public.so_credit (currency_id);
create index if not exists so_credit_warehouse_idx    on public.so_credit (warehouse_id);
create index if not exists so_credit_tax_rule_idx     on public.so_credit (tax_rule_id);
create index if not exists so_credit_issued_on_idx    on public.so_credit (issued_on);
create index if not exists so_credit_issued_by_idx    on public.so_credit (issued_by);
create index if not exists so_credit_cancelled_by_idx on public.so_credit (cancelled_by);
create index if not exists so_credit_created_by_idx   on public.so_credit (created_by);
create index if not exists so_credit_updated_by_idx   on public.so_credit (updated_by);
comment on table  public.so_credit is 'SO 크레딧 노트 머리(§8 8-g · ⓒ1 · 2026-09-24) · ⭐ 거래 — 컷오버 때 지운다 · 손님에게 나가는 서류(발행 순간 total 이 손님 앞으로 = 잔액의 「진 빚」 8-e) · 번호 CR-01000~(재사용 금지) · 상태 issued|cancelled(초안 없음 · 판정 3) · 원본 = IMS invoice_id 또는 Cin7 번호 원문(판정 6 · 짝 CHECK) · warehouse = 반품을 받은 창고(⬜4) · 쓰기는 창구만(so_credit_issue · so_credit_cancel · 표는 select 만)';
comment on column public.so_credit.cin7_order_number is '판정 6 · 되짚기 열쇠 — 원장 Cin7 sale_out 의 doc_number(SO-xxxxx)이자 inv_layer_consume.doc_number · 이 값으로 그 판매의 소비 기록을 되돌린다(갈래 ①) · 비면 갈래 ②③ + 경고 origin_sale_untraced · 인보이스 번호(49xxx)로는 못 되짚는다(0-4 실측)';
comment on column public.so_credit.origin_invoice_on is '원 인보이스 발행일 — IMS 는 so_invoice.issued_on 복사 · Cin7 은 cin7_invoice_date · 리스탁킹 피 알림의 기준(판정 5 · IMS 는 손님이 받은 날을 모른다) · null 이면 알림 없음 + 경고 fee_window_unknown';
comment on column public.so_credit.total is '= lines_amount(≥ 0) + fee_amount(≤ 0) + tax_amount · CHECK so_credit_total_ck · 발행 순간 손님 앞으로 넘어가는 금액(진 빚 · ⓒ2 so_customer_balance.owed_credit = Σissued total − Σ활성 so_credit_alloc)';

-- 3-b so_credit_line — 줄(무엇을 깎나 · kind 다섯 · 돌아가는 칸 · 안 돌아온 사유 · 세율 굳힘)
create table if not exists public.so_credit_line (
  id                    uuid primary key default gen_random_uuid(),
  credit_id             uuid not null references public.so_credit (id) on delete cascade,
  line_no               int not null,
  kind                  text not null,                                                               -- product · freight · tax · other · restocking_fee
  so_invoice_line_id    uuid references public.so_invoice_line (id) on delete no action,             -- IMS product·freight 줄(종이의 줄 · 0-11) · Cin7 null
  so_line_id            uuid references public.so_line (id) on delete no action,                     -- 원장 되짚기의 다리(so.so_number) · 인보이스 줄에서 복사
  product_id            uuid references public.product (id) on delete no action,
  sku                   text,
  description           text,
  qty_returned          numeric,                                                                     -- product 만 · > 0 · 판매 단위
  restock_bin_id        uuid references public.ref_bin (id) on delete no action,                     -- 판정 1 「돌아가는 칸」 · null = 안 돌아옴 · B급 칸이 서면 칸 목록에 표시만
  restock_bin           text,
  not_restocked_reason  text,                                                                        -- damaged · b_grade · not_returned · other(note 필수)
  not_restocked_note    text,
  unit_price            numeric,
  amount                numeric not null default 0,                                                  -- product·freight·tax·other ≥ 0 · restocking_fee ≤ 0
  rate_pct              numeric(7,4),
  tax_amount            numeric not null default 0,
  account_id            uuid references public.ref_account (id) on delete no action,
  account_code          text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  updated_by            uuid references public.ims_staff (id) on delete no action,
  constraint so_credit_line_no_ck         check (line_no >= 1),
  constraint so_credit_line_uq            unique (credit_id, line_no),
  constraint so_credit_line_kind_ck       check (kind in ('product','freight','tax','other','restocking_fee')),
  constraint so_credit_line_qty_ck        check ((kind = 'product') = (qty_returned is not null)),
  constraint so_credit_line_qty_pos_ck    check (qty_returned is null or qty_returned > 0),
  constraint so_credit_line_restock_ck    check (case when kind = 'product' then (restock_bin_id is null) = (not_restocked_reason is not null) else restock_bin_id is null and not_restocked_reason is null end),
  constraint so_credit_line_bin_pair_ck   check ((restock_bin_id is null) = (restock_bin is null)),
  constraint so_credit_line_reason_ck     check (not_restocked_reason is null or not_restocked_reason in ('damaged','b_grade','not_returned','other')),
  constraint so_credit_line_reason_note_ck check (not_restocked_reason is distinct from 'other' or not_restocked_note is not null),
  constraint so_credit_line_amount_ck     check (case when kind = 'restocking_fee' then amount <= 0 else amount >= 0 end)
);
create index if not exists so_credit_line_credit_idx       on public.so_credit_line (credit_id);
create index if not exists so_credit_line_invoice_line_idx on public.so_credit_line (so_invoice_line_id);
create index if not exists so_credit_line_so_line_idx      on public.so_credit_line (so_line_id);
create index if not exists so_credit_line_product_idx      on public.so_credit_line (product_id);
create index if not exists so_credit_line_bin_idx          on public.so_credit_line (restock_bin_id);
create index if not exists so_credit_line_account_idx      on public.so_credit_line (account_id);
create index if not exists so_credit_line_updated_by_idx   on public.so_credit_line (updated_by);
comment on table public.so_credit_line is 'SO 크레딧 줄(8-g · 판정 1 · ⓒ1) · kind product(qty_returned · restock_bin_id 있으면 원장 credit_in · 없으면 not_restocked_reason) · freight · tax(세액만 돌려줌) · other · restocking_fee(≤ 0 · 판정 4·5) · IMS 줄은 so_invoice_line 을 가리키고 단가·세율(rate_pct · 그 인보이스 오더)·계정을 굳힌다(0-11) · Cin7 줄은 sku·수량·단가 손으로(판정 6) · 갈리는 것은 「재고가 움직이냐」(8-g) · 쓰기는 창구만';
comment on column public.so_credit_line.restock_bin_id is '판정 1 「돌아가는 칸」 — null = 안 돌아옴(not_restocked_reason 필수) · 있으면 원장 credit_in(그 칸 · ⬜4 기본 ims_last_bin · 그 창고 ref_bin 에 있어야 · 빈 문자열 불허) · B급 칸이 서면 칸 목록에 표시만 더하고 줄은 그 칸을 고른다(표·사건 무접촉) · 그동안 b_grade 사유는 B급 칸이 선 날 재고 조정으로 넣을 목록';

-- 3-c so_credit_alloc — 크레딧을 어디에 썼나(인보이스 또는 환불 결제 · 0-9 · ⓑ alloc 과 같은 모양 · 떼기 = void) · 쓰는 창구는 ⓒ2(여기서는 표와 취소 가드만)
create table if not exists public.so_credit_alloc (
  id                uuid primary key default gen_random_uuid(),
  credit_id         uuid not null references public.so_credit (id) on delete cascade,
  invoice_id        uuid references public.so_invoice (id) on delete no action,
  refund_payment_id uuid references public.so_payment (id) on delete no action,                     -- kind refund 인 결제(크레딧을 현금으로 · 8-g)
  amount            numeric not null,
  source            text not null default 'manual',                                                  -- manual · auto(발행 때 크레딧부터 · ⓒ2)
  voided_at         timestamptz,
  voided_by         uuid references public.ims_staff (id) on delete no action,
  void_note         text,
  created_by        uuid references public.ims_staff (id) on delete no action,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.ims_staff (id) on delete no action,
  active_target     uuid generated always as (case when voided_at is null then coalesce(invoice_id, refund_payment_id) end) stored,
  constraint so_credit_alloc_amount_ck    check (amount > 0),
  constraint so_credit_alloc_target_ck    check ((invoice_id is null) <> (refund_payment_id is null)),
  constraint so_credit_alloc_source_ck    check (source in ('manual','auto')),
  constraint so_credit_alloc_void_by_ck   check ((voided_at is null) = (voided_by is null)),
  constraint so_credit_alloc_void_note_ck check ((voided_at is null) = (void_note is null)),
  constraint so_credit_alloc_active_uq    unique (credit_id, active_target)
);
create index if not exists so_credit_alloc_credit_idx     on public.so_credit_alloc (credit_id);
create index if not exists so_credit_alloc_invoice_idx    on public.so_credit_alloc (invoice_id);
create index if not exists so_credit_alloc_refund_idx     on public.so_credit_alloc (refund_payment_id);
create index if not exists so_credit_alloc_voided_by_idx  on public.so_credit_alloc (voided_by);
create index if not exists so_credit_alloc_created_by_idx on public.so_credit_alloc (created_by);
create index if not exists so_credit_alloc_updated_by_idx on public.so_credit_alloc (updated_by);
comment on table public.so_credit_alloc is 'SO 크레딧 소진(8-e credit_applied · 8-g 소진 · ⓒ1 표 · 창구는 ⓒ2) — 대상 = 인보이스 또는 환불 결제 정확히 하나(0-9 · 크레딧 환불은 received 를 건드리지 않는다) · 떼기 = void(흔적) · 활성 짝 하나(생성 칸 active_target + unique) · source manual|auto(발행 때 크레딧부터 · 취소 때 auto 는 함께 void · 판정 7 과 같은 규칙) · 잔액 식(ⓒ2): owed_credit = Σissued so_credit.total − Σ활성 alloc';

create trigger so_credit_touch       before update on public.so_credit       for each row execute function public.ims_touch();
create trigger so_credit_line_touch  before update on public.so_credit_line  for each row execute function public.ims_touch();
create trigger so_credit_alloc_touch before update on public.so_credit_alloc for each row execute function public.ims_touch();
alter table public.so_credit       enable row level security;
alter table public.so_credit_line  enable row level security;
alter table public.so_credit_alloc enable row level security;
create policy so_credit_select       on public.so_credit       for select to authenticated using (true);
create policy so_credit_line_select  on public.so_credit_line  for select to authenticated using (true);
create policy so_credit_alloc_select on public.so_credit_alloc for select to authenticated using (true);
revoke all on public.so_credit       from public, anon, authenticated;
revoke all on public.so_credit_line  from public, anon, authenticated;
revoke all on public.so_credit_alloc from public, anon, authenticated;
grant select on public.so_credit       to authenticated;
grant select on public.so_credit_line  to authenticated;
grant select on public.so_credit_alloc to authenticated;

-- ═══ ④ 원장 창구 — 두 층(③a 선례) · 실시간(so_credit_issue → inv_post_credit → inv_layer_post_credit)과 재생성(inv_layer_apply → inv_layer_apply_credit_ims → inv_layer_post_credit)이 같은 함수를 부른다(17-f) ═══
-- 4-a inv_layer_post_credit — 레이어 층 · 갈래 ① 원 판매의 소비 기록 복원(return_restore · Cin7 축 inv_layer_apply_credit 과 같은 식 · 열쇠 = 오더 번호 · 0-3) → ② 남은 레이어 가중평균(layer_avg) → ③ 최근 원가 네 단계(17-e · layer_recent · layer_recent_other_wh · price_history) → ④ unknown
--   p_hint(재생성): 실시간이 raw.cost.remainder 에 남긴 {qty, unit_cost, cost_source, step, source} — ①은 소비 기록에서 다시 나오고(단가 같음 · 레이어 id 는 다르다) 나머지는 hint 값으로 같은 레이어를 세운다(17-f (가))
create function public.inv_layer_post_credit(
  p_doc_number   text,        -- 크레딧 번호(CR-…)
  p_line_ref     text,        -- 첫 줄 id
  p_sku          text,        -- 낱개 SKU
  p_warehouse    text,        -- 반품을 받은 창고 이름
  p_qty          numeric,     -- EA
  p_occurred_on  date,
  p_origin_sale  text,        -- 원 판매 오더 번호(SO-…) · null 이면 갈래 ① 없음
  p_hint         jsonb default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_credit@2026-09-25.1';
  v_hint       jsonb := case when p_hint is not null and jsonb_typeof(p_hint) = 'object' then p_hint else null end;
  v_need       numeric := p_qty;
  v_take       numeric;
  v_traced_qty numeric := 0;
  v_traced_amt numeric := 0;
  v_traced_n   int := 0;
  v_layers     jsonb := '[]'::jsonb;
  v_unit       numeric;
  v_src        text;
  v_step       int;
  v_source     jsonb;
  v_rem        numeric;
  v_remval     numeric;
  v_layer_id   bigint;
  v_id         bigint;
  c            record;
  x            record;
begin
  if p_qty is null or p_qty <= 0 then
    return jsonb_build_object('sku', p_sku, 'warehouse', p_warehouse, 'qty', p_qty, 'traced_qty', 0, 'traced_layers', 0, 'remainder', null, 'layers', '[]'::jsonb, 'amount', 0, 'builder', c_version);
  end if;
  if exists (select 1 from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = p_doc_number and y.sku = p_sku and y.warehouse = p_warehouse) then
    raise exception 'Credit layers for % / % on % already exist — this credit was already costed — nothing was saved', p_sku, p_warehouse, p_doc_number;
  end if;

  -- 갈래 ① — 원 판매(오더 번호)가 소진한 레이어를 같은 단가로 되돌린다(소비된 순서 · 앞선 크레딧이 되돌린 몫은 뺀다 · inv_layer_apply_credit 갈래 ① 과 같은 식)
  if p_origin_sale is not null then
    for c in
      select s.layer_id, s.unit_cost,
             s.qty - coalesce((select sum(x2.qty) from public.inv_layer x2
                                 where x2.origin_type = 'creditnote' and x2.cost_source = 'return_restore' and x2.parent_layer_id = s.layer_id
                                   and x2.doc_number in (select distinct e.doc_number from public.inv_ledger e
                                                           where e.event_type = 'credit_in' and e.raw -> 'header' ->> 'order_number' = p_origin_sale)), 0) as avail
        from (select cs.layer_id, cs.unit_cost, sum(cs.qty) as qty, min(l.received_on) as received_on
                from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
               where cs.doc_type = 'sale' and cs.doc_number = p_origin_sale and cs.reason = 'sale' and l.sku = p_sku
               group by cs.layer_id, cs.unit_cost) s
       order by s.received_on, s.layer_id
    loop
      exit when v_need <= 0;
      if c.avail <= 0 then continue; end if;
      v_take := least(c.avail, v_need);
      insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
      values (p_sku, p_warehouse, 'creditnote', p_doc_number, p_line_ref, c.layer_id, p_occurred_on, true, v_take, c.unit_cost, 'return_restore')
      returning id into v_id;
      v_layers := v_layers || jsonb_build_object('layer_id', v_id, 'qty', v_take, 'unit_cost', c.unit_cost, 'cost_source', 'return_restore', 'parent_layer_id', c.layer_id);
      v_traced_qty := v_traced_qty + v_take;  v_traced_amt := v_traced_amt + round(v_take * c.unit_cost, 6);  v_traced_n := v_traced_n + 1;
      v_need := v_need - v_take;
    end loop;
  end if;

  -- 나머지 — hint(재생성) 또는 ② → ③ → ④
  if v_need > 0 then
    if v_hint is not null then
      if nullif(v_hint->>'qty', '')::numeric is distinct from v_need then
        raise exception 'Credit remainder hint (%) does not match the untraced quantity (%) for % / % on % — the ledger raw is wrong, not this function — nothing was saved',
          v_hint->>'qty', v_need, p_sku, p_warehouse, p_doc_number;
      end if;
      v_unit := nullif(v_hint->>'unit_cost', '')::numeric;  v_src := coalesce(v_hint->>'cost_source', 'unknown');
      v_step := nullif(v_hint->>'step', '')::int;  v_source := v_hint->'source';
      if v_unit is null or v_unit < 0 or v_src not in ('layer_avg','layer_recent','layer_recent_other_wh','price_history','unknown') then
        raise exception 'Credit remainder hint for % / % on % has no usable unit_cost/cost_source (%) — the ledger raw is wrong, not this function — nothing was saved', p_sku, p_warehouse, p_doc_number, v_hint::text;
      end if;
    else
      -- ② 남은 레이어 가중평균(그 SKU×창고 · 지금 남은 것)
      select coalesce(sum(t.rem), 0), coalesce(sum(t.rem * t.unit_cost), 0) into v_rem, v_remval
        from (select y.unit_cost, y.qty - coalesce((select sum(k.qty) from public.inv_layer_consume k where k.layer_id = y.id), 0) as rem
                from public.inv_layer y where y.sku = p_sku and y.warehouse = p_warehouse) t
       where t.rem > 0;
      if v_rem > 0 then
        v_unit := round(v_remval / v_rem, 6);  v_src := 'layer_avg';  v_step := 2;  v_source := jsonb_build_object('remaining_qty', v_rem, 'remaining_value', v_remval);
      else
        -- ③ 최근 원가(17-e · inv_layer_post_sale 과 같은 네 단계 · sale_shortfall 제외 · landed 포함)
        select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse,
               (y.unit_cost * y.qty + coalesce((select sum(a.amount) from public.inv_layer_cost_add a where a.layer_id = y.id), 0)) / y.qty as unit
          into x
          from public.inv_layer y where y.sku = p_sku and y.warehouse = p_warehouse and y.origin_type <> 'sale_shortfall'
         order by y.received_on desc, y.id desc limit 1;
        if found then
          v_unit := x.unit;  v_src := 'layer_recent';  v_step := 3;
          v_source := jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
        else
          select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse,
                 (y.unit_cost * y.qty + coalesce((select sum(a.amount) from public.inv_layer_cost_add a where a.layer_id = y.id), 0)) / y.qty as unit
            into x
            from public.inv_layer y where y.sku = p_sku and y.warehouse <> p_warehouse and y.origin_type <> 'sale_shortfall'
           order by y.received_on desc, y.id desc limit 1;
          if found then
            v_unit := x.unit;  v_src := 'layer_recent_other_wh';  v_step := 4;
            v_source := jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
          else
            select h.net_unit_cad, h.invoice_number, h.invoice_date, h.supplier_name into x
              from public.po_price_history h where h.sku = p_sku and h.net_unit_cad is not null
             order by h.invoice_date desc, h.invoice_number desc limit 1;
            if found then
              v_unit := x.net_unit_cad;  v_src := 'price_history';  v_step := 5;
              v_source := jsonb_build_object('invoice_number', x.invoice_number, 'invoice_date', x.invoice_date, 'supplier_name', x.supplier_name);
            else
              v_unit := 0;  v_src := 'unknown';  v_step := 6;  v_source := null;      -- ④ 모른다 — 0 · 표시가 남는다
            end if;
          end if;
        end if;
      end if;
    end if;
    insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
    values (p_sku, p_warehouse, 'creditnote', p_doc_number, p_line_ref, null, p_occurred_on, v_src = 'layer_avg', v_need, v_unit, v_src)
    returning id into v_layer_id;
    v_layers := v_layers || jsonb_build_object('layer_id', v_layer_id, 'qty', v_need, 'unit_cost', v_unit, 'cost_source', v_src, 'step', v_step);
  end if;

  return jsonb_build_object(
    'sku', p_sku, 'warehouse', p_warehouse, 'qty', p_qty, 'origin_sale', p_origin_sale,
    'traced_qty', v_traced_qty, 'traced_layers', v_traced_n, 'traced_amount', v_traced_amt,
    'remainder', case when v_need > 0 then jsonb_build_object('qty', v_need, 'unit_cost', v_unit, 'cost_source', v_src, 'step', v_step, 'source', v_source, 'layer_id', v_layer_id, 'amount', round(v_need * v_unit, 6), 'reproduced', v_hint is not null) end,
    'layers', v_layers, 'amount', v_traced_amt + coalesce(round(v_need * v_unit, 6), 0), 'builder', c_version);
end;
$$;
comment on function public.inv_layer_post_credit(text, text, text, text, numeric, date, text, jsonb) is
  '⭐⭐ 반품 재고의 레이어 층(8-g credit_in · ledger-design 1324 IMS 축 · ⓒ1) — security definer · authenticated 없음 · ⭐ 실시간(inv_post_credit)·재생성(inv_layer_apply_credit_ims) 둘이 이것만 부른다(17-f). 갈래 ① p_origin_sale(오더 번호 · 두 축 같은 열쇠 · 0-3)의 소비 기록(inv_layer_consume doc_type sale · reason sale · 같은 sku)을 소비된 순서로 같은 단가로 되돌린다(return_restore · parent_layer_id · 앞선 크레딧이 되돌린 몫 제외 · inv_layer_apply_credit 갈래 ① 과 같은 식) → ② 남은 레이어 가중평균(layer_avg · step 2) → ③ 최근 원가 네 단계(17-e · layer_recent 3 · layer_recent_other_wh 4 · price_history 5 · 0-5 ✅) → ④ unknown 0(step 6). p_hint = raw.cost.remainder(재생성 재현 · 17-f (가)) · 반환 traced_qty · remainder · layers · amount · 멱등 「already costed」';
revoke all on function public.inv_layer_post_credit(text, text, text, text, numeric, date, text, jsonb) from public, anon, authenticated;

-- 4-b inv_post_credit — 원장 행 층(so_credit_issue 만 부른다 · invoker · 첫 줄 ims_require_write(sales, posted)) · restock 줄마다 낱개 SKU·EA · 키 (sku) 로 접어 레이어 먼저 → 결과(raw.cost)를 실어 credit_in 행 insert(줄 = 칸 하나)
create function public.inv_post_credit(p_credit_id uuid, p_occurred_on date) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_credit@2026-09-25.1';
  v_cr       public.so_credit%rowtype;
  v_existing int;
  v_alloc    jsonb;
  v_costs    jsonb := '{}'::jsonb;
  v_rows     int := 0;
  v_qty      numeric := 0;
  v_warn     text[] := '{}';
  k          record;
  b          record;
begin
  perform public.ims_require_write('sales', 'posted');        -- ⭐ 첫 줄 — 호출자(auth.uid())의 sales 쓰기

  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found — nothing was posted to the ledger'; end if;
  if v_cr.status <> 'issued' then raise exception 'Credit note % is % — the ledger takes issued credit notes only — nothing was posted to the ledger', v_cr.credit_number, v_cr.status; end if;
  if v_cr.warehouse_name is null then raise exception 'Credit note % has no warehouse — nothing was posted to the ledger', v_cr.credit_number; end if;

  select count(*) into v_existing from public.inv_ledger l where l.doc_type = 'creditnote' and l.doc_number = v_cr.credit_number and l.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;
  if p_occurred_on > public.ims_today() then v_warn := array_append(v_warn, 'credited_on_in_future'); end if;

  -- restock 줄 모으기 — 판매 단위 → EA(pack_factor) · 낱개 SKU(세트는 parent) · 원 판매 오더 번호(IMS so_line → so · Cin7 cin7_order_number)
  with a as (
    select cl.id as line_id, cl.line_no, cl.product_id, cl.sku as credited_sku, cl.qty_returned, cl.unit_price, cl.restock_bin as bin,
           coalesce(pp.sku, pr.sku) as base_sku, coalesce(pr.pack_factor, 1) as pack_factor, cl.qty_returned * coalesce(pr.pack_factor, 1) as qty_ea,
           coalesce(s.so_number, v_cr.cin7_order_number) as origin_sale
      from public.so_credit_line cl
      join public.product pr on pr.id = cl.product_id
      left join public.product pp on pp.id = pr.parent_product_id
      left join public.so_line sl on sl.id = cl.so_line_id
      left join public.so s on s.id = sl.so_id
     where cl.credit_id = p_credit_id and cl.kind = 'product' and cl.restock_bin_id is not null
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then
    return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', false, 'existing_rows', 0, 'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["nothing_restocked"]'::jsonb);
  end if;

  -- ⭐ 레이어 먼저 — 낱개 SKU 키마다 한 번(창고 하나 · 줄 여럿은 접는다 · line_ref = 첫 줄 · 원 판매는 첫 줄의 것 — 재생성 키 (doc, sku, wh) 와 같다)
  for k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no))[1] as line_ref, (array_agg(t.origin_sale order by t.line_no))[1] as origin_sale,
           count(distinct t.origin_sale) as n_origin
      from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, origin_sale text)
     group by t.base_sku order by t.base_sku
  loop
    if k.n_origin > 1 then v_warn := array_append(v_warn, 'mixed_origin_sales:' || k.base_sku); end if;
    if k.origin_sale is null then v_warn := array_append(v_warn, 'origin_sale_unknown:' || k.base_sku); end if;
    v_costs := v_costs || jsonb_build_object(k.base_sku, public.inv_layer_post_credit(v_cr.credit_number, k.line_ref, k.base_sku, v_cr.warehouse_name, k.qty_ea, p_occurred_on, k.origin_sale, null));
    if (v_costs -> k.base_sku ->> 'traced_qty')::numeric < k.qty_ea then v_warn := array_append(v_warn, 'origin_sale_untraced:' || k.base_sku || ':' || ((v_costs -> k.base_sku -> 'remainder' ->> 'cost_source'))); end if;
  end loop;

  -- 원장 행 — 줄(= 칸 하나) · raw.header 는 Cin7 credit_in 과 같은 모양(order_number · credit_note_number · credit_note_date — 두 축을 같은 식으로 되짚는다) · raw.cost.remainder 가 재생성 hint
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, credited_sku text, qty_returned numeric, unit_price numeric, bin text,
                                                   base_sku text, pack_factor numeric, qty_ea numeric, origin_sale text)
     order by line_no
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 1, b.base_sku, v_cr.warehouse_name, b.bin, b.qty_ea, 'credit_in', 'creditnote', v_cr.credit_number, v_cr.id::text, b.line_id::text, null, 'ims',
      jsonb_build_object(
        'kind', 'credit_in', 'poster', c_version,
        'header', jsonb_build_object('order_number', b.origin_sale, 'credit_note_number', v_cr.credit_number, 'credit_note_date', p_occurred_on, 'invoice_id', v_cr.invoice_id, 'cin7_invoice_number', v_cr.cin7_invoice_number),
        'credit_id', v_cr.id, 'credit_line_id', b.line_id, 'line_no', b.line_no,
        'product_id', b.product_id, 'sku', b.credited_sku, 'base_sku', b.base_sku, 'pack_factor', b.pack_factor,
        'qty', b.qty_returned, 'qty_ea', b.qty_ea, 'unit_price', b.unit_price,
        'warehouse_id', v_cr.warehouse_id, 'warehouse', v_cr.warehouse_name, 'bin', b.bin,
        'customer_id', v_cr.customer_id, 'credited_on', p_occurred_on, 'issued_by', v_cr.issued_by,
        'cost', v_costs -> b.base_sku));
    v_rows := v_rows + 1;  v_qty := v_qty + b.qty_ea;
  end loop;

  return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', false, 'existing_rows', 0,
                            'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Credit note % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_cr.credit_number, sqlerrm;
end;
$$;
comment on function public.inv_post_credit(uuid, date) is
  '⭐⭐ 반품의 원장 창구(원칙 2 · 8-g credit_in = so_out 의 반대 · ⓒ1) — issued 크레딧의 restock 줄(restock_bin_id 있음)을 줄 = 칸 하나 credit_in 행으로(낱개 SKU · EA · seq_hint 1 유입 · doc creditnote/CR 번호 · line_ref 크레딧 줄 id · source ims) · ⭐ 낱개 SKU 키마다 inv_layer_post_credit 을 먼저 불러 갈래 ①~④ 레이어를 만들고 결과를 raw.cost 에 싣는다(remainder 가 재생성 hint) · raw.header 는 Cin7 credit_in 과 같은 모양(order_number = 원 판매 오더 번호) · 멱등(already_posted) · 경고 origin_sale_unknown · origin_sale_untraced · mixed_origin_sales · 첫 줄 ims_require_write(sales, posted) · invoker · authenticated 는 execute 없음 — so_credit_issue 만 부른다';
revoke all on function public.inv_post_credit(uuid, date) from public, anon, authenticated;

-- 4-c inv_layer_apply_credit_ims — 재생성 보조(IMS 축) · inv_layer_apply_credit(Cin7 축)과 같은 반환 모양 · 키 (doc, sku, wh) 순액 · 첫 행의 raw.header.order_number · raw.cost.remainder 를 hint 로 같은 창구
create function public.inv_layer_apply_credit_ims(p_ledger_id bigint, p_until date,
                                                  out o_layers int, out o_traced int, out o_avg int,
                                                  out o_unknown int, out o_net_zero int, out o_processed int)
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  r       public.inv_ledger%rowtype;
  f       public.inv_ledger%rowtype;
  v_net   numeric;
  v_res   jsonb;
begin
  o_layers := 0; o_traced := 0; o_avg := 0; o_unknown := 0; o_net_zero := 0; o_processed := 0;
  select * into r from public.inv_ledger where id = p_ledger_id;
  if not found or r.event_type <> 'credit_in' or r.source <> 'ims' then return; end if;
  if exists (select 1 from inv_layer_apply_done d where d.kind = 'credit' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then return; end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('credit', r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  select sum(qty_delta) into v_net from public.inv_ledger
   where event_type = 'credit_in' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse and (p_until is null or occurred_on <= p_until);
  if v_net is null or v_net <= 0 then o_net_zero := 1; return; end if;          -- 취소(reversal)로 상쇄된 키 — 레이어 없음(17-f ②)

  select * into f from public.inv_ledger
   where event_type = 'credit_in' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse and qty_delta > 0 and (p_until is null or occurred_on <= p_until)
   order by occurred_on, id limit 1;
  v_res := public.inv_layer_post_credit(r.doc_number, f.line_ref, r.sku, r.warehouse, v_net, f.occurred_on, f.raw -> 'header' ->> 'order_number', f.raw -> 'cost' -> 'remainder');
  o_layers := coalesce((v_res ->> 'traced_layers')::int, 0) + case when v_res -> 'remainder' is not null and jsonb_typeof(v_res -> 'remainder') = 'object' then 1 else 0 end;
  o_traced := case when coalesce((v_res ->> 'traced_qty')::numeric, 0) > 0 then 1 else 0 end;
  o_avg := case when v_res -> 'remainder' is not null and jsonb_typeof(v_res -> 'remainder') = 'object' then 1 else 0 end;
  o_unknown := case when v_res -> 'remainder' ->> 'cost_source' = 'unknown' then 1 else 0 end;
end;
$$;
comment on function public.inv_layer_apply_credit_ims(bigint, date) is
  '재생성 보조 · IMS 축 credit_in(ⓒ1 · 17-f) — inv_layer_apply 가 source ims 인 credit_in 을 여기로 보낸다(Cin7 축은 inv_layer_apply_credit 그대로) · 키 (doc, sku, wh) 순액(≤ 0 이면 net_zero · 취소 상쇄) · 첫 행의 raw.header.order_number(원 판매)·raw.cost.remainder(hint)로 inv_layer_post_credit 을 불러 실시간과 같은 레이어를 세운다 · 반환 모양은 inv_layer_apply_credit 과 같다(o_layers · o_traced · o_avg · o_unknown · o_net_zero · o_processed)';
revoke all on function public.inv_layer_apply_credit_ims(bigint, date) from public, anon, authenticated;

-- ═══ ⑤ inv_layer_apply 재발행 — 마지막 정의 20260921161933(바이트 그대로) · 바뀐 줄 둘: IMS 문 목록에서 credit_in 제외 · credit_in 갈래를 source 로 가름(ims → inv_layer_apply_credit_ims) ═══
create or replace function inv_layer_apply(p_until date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_t0          timestamptz := clock_timestamp();
  v_baseline    int;
  r             record;
  v_c int; v_u int; v_rows int; v_short int; v_proc int; v_rev int; v_layers int; v_orphan int; v_nz int; v_unk int; v_unkq numeric;
  v_partial int; v_traced int; v_avg int;
  v_po          int := 0;
  v_sale        int := 0;
  v_sale_keys   int := 0;
  v_sale_rev    int := 0;
  v_tr          int := 0;
  v_tr_layers   int := 0;
  v_tr_orphan   int := 0;
  v_tr_nz       int := 0;
  v_tr_unk      int := 0;
  v_tr_unkq     numeric := 0;
  v_tr_unpaired int := 0;
  v_adj         int := 0;
  v_adj_layers  int := 0;
  v_adj_rows    int := 0;
  v_adj_unk     int := 0;
  v_adj_new_nz  int := 0;
  v_asm         int := 0;
  v_asm_layers  int := 0;
  v_asm_rows    int := 0;
  v_asm_partial int := 0;
  v_asm_nz      int := 0;
  v_asm_unpaired int := 0;
  v_cr          int := 0;
  v_cr_layers   int := 0;
  v_cr_traced   int := 0;
  v_cr_avg      int := 0;
  v_cr_unk      int := 0;
  v_cr_nz       int := 0;
  v_layers_po   int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
  -- landed (2026-09-10)
  v_landed_rows int := 0;
  v_landed_amt  numeric := 0;
  v_landed_orph int := 0;
  v_neg         record;
  -- transfer_freight (2026-09-10)
  v_doc         record;
  v_grp         record;
  v_fr_n        int;
  v_fr_basis    numeric;
  v_fr_rows     int := 0;
  v_fr_amt      numeric := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
  -- IMS (2026-09-20) — 창구 둘(inv_layer_post_receipt · inv_layer_post_charge)의 반환을 합친다. ⚠️ 원문 변수와 겹치지 않는 v_ims_ 접두어
  v_ims_src     text;
  v_ims_task    text;
  v_ims_docno   text;
  v_ims_j       jsonb;
  v_ims_chg     record;
  v_ims_rcv         int := 0;   v_ims_rcv_layers int := 0;   v_ims_rcv_exist int := 0;   v_ims_rcv_cost numeric := 0;   v_ims_rcv_skipped int := 0;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_ims_chg_unvisited int := 0;   v_ims_chg_unvisited_amt numeric := 0;
  v_ims_skip    jsonb := '[]'::jsonb;
  -- IMS 초과분 (2026-09-20 · over 닫기) — 형제 창구 inv_layer_post_receipt_over 의 반환을 합친다
  v_ims_over    text;
  v_ims_over_n  int := 0;   v_ims_over_layers int := 0;   v_ims_over_skipped int := 0;
  -- IMS 문 · 보조 넷 (2026-09-20) — 창구가 아직 없는 IMS 사건을 사건 종류별로 센다(0 이 아니면 그 창구를 만들 때다). sale_out 은 없다(문 불필요).
  v_ims_gate    jsonb := '{"transfer_in": 0, "transfer_out": 0, "manual_reversal": 0, "adjust_existing": 0, "adjust_new": 0, "assemble_in": 0, "assemble_out": 0, "credit_in": 0}'::jsonb;
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  -- ⭐ IMS 권한 문 (2026-09-20) — 창구 둘은 ims_require_write(receiving · purchasing) 로 auth.uid() 의 권한을 본다.
  --   권한이 없으면 창구가 전부 예외를 던지고 아래 IMS 블록이 그것을 「건너뛰었다」로 세어 버린다 — 재생성이 조용히 반쪽(IMS 만 빠진 레이어 표)이 된다.
  --   그래서 지우기 전에 먼저 막는다. psql 에서는 request.jwt.claims 에 admin 의 sub 를 심고 돌린다(20260918133858 검증 주석 선례).
  if not (ims_can_write('receiving') and ims_can_write('purchasing')) then
    raise exception 'inv_layer_apply: the IMS cost windows (inv_layer_post_receipt · inv_layer_post_charge) need write permission on receiving and purchasing for this login (auth.uid() = %) — from psql, set request.jwt.claims to an admin''s sub first — nothing was rebuilt',
      coalesce(auth.uid()::text, '(null)');
  end if;
  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, po_in 먼저, id · source 필터 없음 · ⭐ 2026-09-21: 같은 날 유입끼리는 po_in 을 맨 앞에 — seq_hint 는 유입·유출만 가른다. 근거는 이 파일 머리 주석)
  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, case event_type when 'po_in' then 0 else 1 end, id
  loop
    -- ⭐⭐ IMS 문 · 보조 넷 (2026-09-20 · po_in 문의 형제 · Caleb 「문만 낸다 — 창구는 만들지 않는다」) — 창구가 아직 없는 IMS 사건은 보조 함수에 보내지 않고 사건 종류별로 센다.
    -- 왜 안 보내나: 보조 넷(transfer_in · adjust · assemble · credit)은 원가를 inv_cost / 레이어 평균에서 찾는다. IMS 사건은 거기 없어 unit_cost 0 · 'unknown' 레이어가 선다 — po_in 에서 실측된 사고(rcv_unknown 0→2)와 같다.
    -- 왜 창구를 지금 안 만드나: 트랜스퍼 모듈도 IMS 재고조정도 아직 없다 — 쓰지 않을 창구는 맞는지 검증할 표본이 없다. 그 사건을 내는 날 창구를 만들고 여기서 부른다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
    -- 왜 세나: 조용히 지나가면 「IMS 트랜스퍼가 재고에 안 잡힌다」를 아무도 모른다. ims.skipped_by_event 가 0 이 아니면 창구를 만들 때가 됐다는 신호다.
    -- ⚠️ sale_out 은 세지도 막지도 않는다 — 소진은 출처를 안 보는 한 원장 FIFO 가 맞다(inv_layer_fifo_take). po_in 은 아래 분기가 창구로 처리한다.
    -- ⭐ 두 leg 다 막는다(⬜4) — transfer_out · manual_reversal · assemble_out 도 IMS 면 여기서 센다. out 은 대응 in 이 처리하므로 in 만 막아도 레이어는 안 서지만, 아래 *_unpaired 신호가 IMS 것으로 오염된다(그 집계에서도 ims 를 뺀다).
    -- 원문 루프 select(id, event_type)는 바꾸지 않는다 — po_in·sale_out 이 아닌 행만 PK 조회 한 번(po_in 은 아래 분기가 이미 조회한다).
    if r.event_type not in ('po_in', 'sale_out', 'credit_in') then   -- ⓒ1 2026-09-25: credit_in 은 아래 갈래가 source 로 가른다(IMS → 창구 inv_layer_apply_credit_ims · 문에서 세지 않는다 · skipped_by_event.credit_in 은 늘 0)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        v_ims_gate := jsonb_set(v_ims_gate, array[r.event_type], to_jsonb(coalesce((v_ims_gate ->> r.event_type)::int, 0) + 1));
        continue;
      end if;
    end if;
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers_po := v_layers_po + v_c; v_unknown := v_unknown + v_u;
      -- ⭐⭐ IMS 입고 (2026-09-20) — 보조 inv_layer_apply_po_in 은 source='ims' 면 문에서 돌아섰다(0·0). 이 줄의 레이어는 창구 inv_layer_post_receipt 가 만든다.
      -- 왜 여기(루프 안 · 날짜순)이고 끝이 아닌가: 입고 레이어는 **수량** 레이어다 — 뒤에 오는 sale_out·transfer_out 이 FIFO 로 이것을 소진한다.
      --   끝에서 만들면 루프 안의 소진이 이 레이어를 못 보고 short 로 떨어지거나 다른 레이어를 먹어, 실시간 기표(확정 때 창구가 만든 상태)와 재생성 결과가 갈라진다.
      --   비용(cost_add)은 수량이 아니라 금액만 얹으므로 끝(landed·운송비와 같은 층)에 둔다 — 아래 「IMS 비용」 블록.
      -- 왜 창구에 넘기나: 원가 규칙(환율 곱하기 · 기준까지만 · bin 접기)이 창구 안에 있다. 여기 다시 적으면 같은 규칙이 두 곳에 살고 한쪽만 고치면 조용히 갈라진다.
      -- 왜 원장에서 훑나: 이 함수의 일은 「원장에서 레이어를 다시 만드는 것」이다 — 원장에 없으면 레이어도 없다. p_until 도 그대로 걸린다(as-of).
      -- 왜 입고 단위(doc_task_id = po_receipt.id)로 한 번인가: 입고 하나가 원장에 bin 별 여러 줄을 남긴다. 창구는 입고 단위로 일하고 4키 멱등이라 두 번 불러도 안전하지만,
      --   세는 값이 겹치지 않게 done 표(kind 'ims_rcv')로 한 번만 부른다. 같은 입고의 원장 줄은 occurred_on 이 같아(received_on) p_until 경계에 걸쳐 갈라지지 않는다.
      -- 왜 건너뛰고 세나(멈추지 않나 · Caleb 판정 2026-09-20): 이 함수는 검산 도구다. 입고 한 건의 빈칸(환율)으로 검산 자체가 안 되면 도구가 못 쓰게 된다.
      --   건너뛰어도 틀린 값이 들어가지 않는다 — 0 원가 레이어를 만드는 것과 전혀 다르다. 환율을 채우고 다시 돌리면 그 자리에 제대로 선다. 선례: freight_no_basis(기준 0 이면 버리고 금액을 센다).
      --   ⚠️ 몇 건을 왜 건너뛰었는지 반환(ims.receipts_skipped · ims.skip_reasons)에 반드시 남긴다 — 조용히 지나가면 같은 사고의 재판이다.
      select source, doc_task_id, doc_number into v_ims_src, v_ims_task, v_ims_docno from inv_ledger where id = r.id;   -- 루프 select 는 바꾸지 않는다(원문 무변) — PK 조회 한 번
      if v_ims_src = 'ims' and v_ims_task is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_rcv' and d.doc_number = v_ims_task and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_rcv', v_ims_task, '', '');   -- 입고 단위 키 — sku·warehouse 는 not null 이라 빈 문자열
        begin
          v_ims_j := inv_layer_post_receipt(v_ims_task::uuid);
          v_ims_rcv        := v_ims_rcv + 1;
          v_ims_rcv_layers := v_ims_rcv_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
          v_ims_rcv_exist  := v_ims_rcv_exist  + coalesce((v_ims_j->>'layers_existing')::int, 0);   -- 지운 뒤라 0 이어야 한다(생기면 신호 — 다른 축이 같은 4키를 먼저 만들었다)
          v_ims_rcv_cost   := v_ims_rcv_cost   + coalesce((v_ims_j->>'cost_total_cad')::numeric, 0);
        exception when others then
          -- ⚠️ 서브트랜잭션 — 창구가 던진 것(환율 없음 · 확정 아님 · po_line 없음 · base_currency 없음)만 여기로 온다. 그 호출이 넣은 레이어는 서브트랜잭션이 되돌린다 — 이 입고의 레이어는 하나도 서지 않는다.
          v_ims_rcv_skipped := v_ims_rcv_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'receipt', 'number', v_ims_docno, 'id', v_ims_task, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS 초과분 (2026-09-20 · over 닫기) — line_ref 가 ':over' 인 po_in 행은 형제 창구 inv_layer_post_receipt_over(diff_id) 가 만든다(free → 0 · billed/credited → 기준 레이어의 unit_cost).
      --   왜 여기(루프 안): 수량 레이어라 뒤의 FIFO 소진이 봐야 한다(위 입고와 같은 이유). 기준 레이어가 먼저 서야 하는데, 초과분 행은 같은 날(received_on)·더 큰 id 라 (occurred_on, seq_hint, id) 순서에서 항상 뒤다.
      --   왜 diff 단위 한 번: 한 차이가 빈 별 여러 행을 남긴다 — done 표 kind 'ims_over'. 거부(기준 레이어 없음 등)는 건너뛰고 ims.over_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_over from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:over';
      if v_ims_over is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_over' and d.doc_number = v_ims_over and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_over', v_ims_over, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_over(v_ims_over::uuid);
          v_ims_over_n      := v_ims_over_n + 1;
          v_ims_over_layers := v_ims_over_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_over_skipped := v_ims_over_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'over', 'number', v_ims_docno, 'id', v_ims_over, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
    elsif r.event_type = 'sale_out' then
      select * into v_rows, v_short, v_proc, v_rev from inv_layer_apply_sale_out(r.id, p_until);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_sale_keys := v_sale_keys + v_proc; v_sale_rev := v_sale_rev + v_rev;
    elsif r.event_type = 'transfer_in' then
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan; v_tr_nz := v_tr_nz + v_nz;
      v_tr_unk := v_tr_unk + v_unk; v_tr_unkq := v_tr_unkq + v_unkq;
    elsif r.event_type in ('adjust_existing', 'adjust_new') then
      select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
      v_adj := v_adj + 1; v_adj_layers := v_adj_layers + v_layers; v_adj_rows := v_adj_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_adj_unk := v_adj_unk + v_unk; v_adj_new_nz := v_adj_new_nz + v_nz;
    elsif r.event_type = 'assemble_in' then
      select * into v_layers, v_rows, v_short, v_partial, v_nz, v_proc from inv_layer_apply_assemble(r.id, p_until);
      v_asm := v_asm + 1; v_asm_layers := v_asm_layers + v_layers; v_asm_rows := v_asm_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_asm_partial := v_asm_partial + v_partial; v_asm_nz := v_asm_nz + v_nz;
    elsif r.event_type = 'assemble_out' then
      v_asm := v_asm + 1;   -- 부품 out 은 대응 in 이 처리한다(A-2 ④) — 여기서는 세기만
    elsif r.event_type = 'credit_in' then
      -- ⓒ1 2026-09-25: IMS 축(source ims)은 창구(inv_layer_post_credit)로 · Cin7 축은 종전 inv_layer_apply_credit — 두 축이 같은 반환 모양(17-f · 실시간과 재생성이 같은 함수)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit_ims(r.id, p_until);
      else
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit(r.id, p_until);
      end if;
      v_cr := v_cr + 1; v_cr_layers := v_cr_layers + v_layers; v_cr_traced := v_cr_traced + v_traced;
      v_cr_avg := v_cr_avg + v_avg; v_cr_unk := v_cr_unk + v_unk; v_cr_nz := v_cr_nz + v_nz;
    else
      v_tr := v_tr + 1;   -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다
    end if;
  end loop;

  -- ⭐ 순액 > 0 인데 같은 날짜의 대응 in 이 처리하지 않은 out 키 — (doc, sku, wh, day) · 0 이어야 한다(생기면 신호)
  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse, occurred_on
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 IMS out leg 는 위 문이 세었다(ims.skipped_by_event) — 여기 섞이면 「생기면 신호」가 IMS 것으로 오염된다
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse, occurred_on
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku
                          and d.warehouse = o.warehouse and d.day = o.occurred_on);

  -- 순액 > 0 인데 대응 in 이 처리하지 않은 부품 out 키 — 0 이어야 한다(생기면 신호). 순액 ≤ 0(상쇄 소멸) 키는 제외.
  select count(*) into v_asm_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type = 'assemble_out'
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 같은 이유
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'asm_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — 레이어가 전부 만들어진 뒤 집합 연산 한 번 ═══
  -- 가드: 키(4키 + occurred_on) 합이 음수면 예외 — inv_layer_cost_add 에는 amount CHECK 가 없어 이것이 유일한 방어다
  select c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on, sum(c.amount) as amt into v_neg
    from inv_cost c
    where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)
    group by c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on
    having sum(c.amount) < 0
    order by 1, 2, 5 limit 1;
  if found then
    raise exception 'inv_cost landed sum(amount) is negative for % / % / % / % @ %: % — refusing to add cost (revaluation offset? inspect inv_cost)',
      v_neg.doc_number, v_neg.line_ref, v_neg.sku, v_neg.warehouse, v_neg.occurred_on, v_neg.amt;
  end if;

  insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
  select x.id, 'landed',
         sum(c.amount),          -- ⭐ bin 이 여럿이면 합산 (실측 0건 · 방어)
         c.occurred_on,          -- ⚠️ 날짜별로 별개 행 (통관·freight·관세)
         c.doc_number, c.line_ref,
         null                    -- PO landed 는 인보이스 번호가 오지 않는다 (헤더)
    from inv_cost c
    join inv_layer x
      on  x.origin_type = 'purchase'
      and x.doc_number  = c.doc_number
      and x.line_ref    = c.line_ref
      and x.sku         = c.sku
      and x.warehouse   = c.warehouse
    where c.cost_kind = 'landed'
      and (p_until is null or c.occurred_on <= p_until)
    group by x.id, c.occurred_on, c.doc_number, c.line_ref;
  get diagnostics v_landed_rows = row_count;
  select coalesce(sum(amount), 0) into v_landed_amt from inv_layer_cost_add where kind = 'landed';

  -- orphan — 대응 purchase 레이어가 없는 landed 키 (조인에서 조용히 빠지므로 따로 센다)
  select count(*) into v_landed_orph
    from (select distinct c.doc_number, c.line_ref, c.sku, c.warehouse
            from inv_cost c
            where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)) k
    where not exists (select 1 from inv_layer x
                        where x.origin_type = 'purchase' and x.doc_number = k.doc_number and x.line_ref = k.line_ref
                          and x.sku = k.sku and x.warehouse = k.warehouse);

  -- ═══ 트랜스퍼 운송비 → inv_layer_cost_add (kind='transfer_freight' · 2026-09-10 · 헤더 B) — landed 와 같은 자리 ═══
  -- B-4 가드: 저널 행 금액이 음수면 예외 — inv_doc_cost 에도 inv_layer_cost_add 에도 amount CHECK 가 없어 이것이 유일한 방어다
  select d.doc_number, d.ref_number, d.occurred_on, d.amount into v_neg
    from inv_doc_cost d
    where d.doc_type = 'transfer' and d.kind = 'transfer_freight'
      and (p_until is null or d.occurred_on <= p_until)
      and d.amount < 0
    order by d.doc_number, d.occurred_on, d.ref_number limit 1;
  if found then
    raise exception 'inv_doc_cost transfer_freight amount is negative for % / invoice % @ %: % — refusing to distribute (correction? inspect inv_doc_cost)',
      v_neg.doc_number, coalesce(v_neg.ref_number, '(null)'), v_neg.occurred_on, v_neg.amount;
  end if;

  -- 문서 단위 루프 — 배분 기준(도착 레이어 원가 합)은 문서에 딸린 레이어로 정해지므로 문서마다 한 번 계산한다
  for v_doc in
    select doc_number, sum(amount) as amount     -- amount: no_basis 로 떨어질 때 합산할 문서 금액 (p_until 범위)
      from inv_doc_cost
      where doc_type = 'transfer' and kind = 'transfer_freight'
        and (p_until is null or occurred_on <= p_until)
      group by doc_number
      order by doc_number
  loop
    -- B-1 대상 = 도착 창고 레이어만 (IN_TRANSIT 제외) · B-2 기준 = unit_cost × qty (remaining 아님)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_fr_n, v_fr_basis
      from inv_layer x
      where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT';
    if v_fr_n = 0 then
      v_fr_orphan := v_fr_orphan + 1;          -- 대응 레이어 없음 (0 이 아니면 신호)
      continue;
    end if;
    if v_fr_basis <= 0 then
      v_fr_nobasis := v_fr_nobasis + 1;        -- 원가 미상(unknown · unit_cost 0) 레이어만 있는 문서 — 0 으로 나누지 않는다
      v_fr_nobasis_amt := v_fr_nobasis_amt + v_doc.amount;   -- ⚠️ 버린 운송비 금액 — Cin7 대조에서 설명된 차이의 크기 (헤더)
      continue;
    end if;

    -- 날짜별 한 묶음 — cost_add 유니크 키에 ref_number 가 없으므로 같은 날 인보이스가 둘이면 합산 1행 (헤더 B-3)
    for v_grp in
      select occurred_on, sum(amount) as amount, count(*) as n,
             string_agg(distinct ref_number, ',' order by ref_number) as ref_number
        from inv_doc_cost
        where doc_type = 'transfer' and kind = 'transfer_freight' and doc_number = v_doc.doc_number
          and (p_until is null or occurred_on <= p_until)
        group by occurred_on
        order by occurred_on
    loop
      if v_grp.n > 1 then v_fr_multi := v_fr_multi + 1; end if;
      -- B-2 배분: share = round(문서금액 × 레이어원가 / 합, 6) · 마지막 레이어(id 순) = 문서금액 − 앞선 share 합 (remainder on last)
      insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      select t.id, 'transfer_freight',
             case when t.rn = t.cnt
                  then v_grp.amount - coalesce(sum(t.share) over (order by t.rn rows between unbounded preceding and 1 preceding), 0)
                  else t.share end,
             v_grp.occurred_on, v_doc.doc_number, t.line_ref, v_grp.ref_number
        from (select x.id, x.line_ref,
                     round(v_grp.amount * (x.unit_cost * x.qty) / v_fr_basis, 6) as share,
                     row_number() over (order by x.id) as rn,
                     count(*) over () as cnt
                from inv_layer x
                where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT') t;
      get diagnostics v_rows = row_count;
      v_fr_rows := v_fr_rows + v_rows;
    end loop;
    v_fr_docs := v_fr_docs + 1;
  end loop;
  select coalesce(sum(amount), 0) into v_fr_amt from inv_layer_cost_add where kind = 'transfer_freight';


  -- ═══ IMS 비용 → inv_layer_cost_add (kind='landed' · 2026-09-20) — landed·운송비와 같은 층 · 창구 inv_layer_post_charge 에 넘긴다 ═══
  -- 왜 여기(끝)인가: 비용은 수량이 아니라 금액만 얹는다 — FIFO 소진에 영향이 없어 Cin7 landed·운송비와 같은 자리다(입고 레이어는 루프 안 — 위).
  -- 왜 레이어에서 훑나(Caleb 판정 2026-09-20): 비용은 원장에 사건을 남기지 않아(금액만 얹는다) 원장으로 훑을 수 없다. 레이어가 없으면 얹을 곳도 없으니 부를 이유가 없다.
  --   길: inv_layer(cost_source='po_line').line_ref = po_line.id::text → po_line.po_id = po_charge_alloc.po_id → po_charge_alloc.po_charge_id = po_charge.id (confirmed).
  --   비용 문서 단위로 한 번(한 비용이 여러 발주에 배분된다 — exists 로 접는다) · 순서 고정.
  -- 왜 창구에 넘기나: 배분 규칙(환율 · unit_cost×qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등)이 창구 안에 있다 — 두 곳에 살게 하지 않는다.
  -- p_until: 창구는 occurred_on = po_charge.charge_date 로 얹는다 — 그래서 charge_date <= p_until 로 고른다(as-of 재생성).
  -- 방문하지 않은 확정 비용(배분된 발주 어디에도 IMS 레이어가 없는 것 — 예: 환율이 없어 입고를 건너뛴 발주)은 따로 센다(charges_unvisited · 금액 CAD)
  --   — 「버린 금액」의 그림이 빠지지 않게. Cin7 대조에서 이 금액만큼은 설명된 차이다(정본 D 의 freight_no_basis_amount 와 같은 구실).
  for v_ims_chg in
    select c.id, c.charge_number, c.charge_date
      from po_charge c
      where c.status = 'confirmed' and c.confirmed_at is not null
        and (p_until is null or c.charge_date <= p_until)
        and exists (select 1
                      from po_charge_alloc a
                      join po_line  pl on pl.po_id = a.po_id
                      join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                      where a.po_charge_id = c.id)
      order by c.charge_date, c.charge_number, c.id       -- ⚠️ 순서 고정 · charge_number 는 (supplier_id, charge_number) 유니크라 id 까지 건다
  loop
    begin
      v_ims_j := inv_layer_post_charge(v_ims_chg.id);
      v_ims_chg_n            := v_ims_chg_n + 1;
      v_ims_chg_rows         := v_ims_chg_rows         + coalesce((v_ims_j->>'layers_touched')::int, 0);
      v_ims_chg_amt          := v_ims_chg_amt          + coalesce((v_ims_j->>'amount_posted_cad')::numeric, 0);
      v_ims_chg_nobasis_amt  := v_ims_chg_nobasis_amt  + coalesce((v_ims_j->>'no_basis_amount_cad')::numeric, 0);    -- 기준 0 이라 버린 금액(정본 D)
      v_ims_chg_nolayers_amt := v_ims_chg_nolayers_amt + coalesce((v_ims_j->>'no_layers_amount_cad')::numeric, 0);   -- 배분 줄 중 레이어 없는 발주로 간 금액
      v_ims_chg_already      := v_ims_chg_already      + coalesce((v_ims_j->>'already_posted_allocs')::int, 0);      -- cost_add 를 지운 뒤라 0 이어야 한다(생기면 신호)
    exception when others then
      v_ims_chg_skipped := v_ims_chg_skipped + 1;
      v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'charge', 'number', v_ims_chg.charge_number, 'id', v_ims_chg.id, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  -- 방문하지 않은 확정 비용 — 위 exists 가 거른 것. 금액은 창구와 같은 규칙으로 CAD(기준통화면 ×1 · 아니면 × exchange_rate). ⚠️ 환율 null 인 외화 비용은 합에서 빠진다(확정 게이트 ⑥ 뒤엔 없다 · 건수에는 든다).
  select count(*), coalesce(sum(c.total_amount * case when cu.code is not distinct from k.value then 1 else c.exchange_rate end), 0)
    into v_ims_chg_unvisited, v_ims_chg_unvisited_amt
    from po_charge c
    join ref_currency cu on cu.id = c.currency_id
    left join inv_config k on k.key = 'base_currency'
    where c.status = 'confirmed' and c.confirmed_at is not null
      and (p_until is null or c.charge_date <= p_until)
      and not exists (select 1
                        from po_charge_alloc a
                        join po_line  pl on pl.po_id = a.po_id
                        join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                        where a.po_charge_id = c.id);

  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                                     'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
              and (p_until is null or occurred_on <= p_until)
            group by event_type) s;

  return jsonb_build_object(
    'until',                     p_until,
    'processed_po_in',           v_po,
    'processed_sale_out',        v_sale,
    'sale_keys_processed',       v_sale_keys,
    'sale_keys_fully_reversed',  v_sale_rev,
    'processed_transfer',        v_tr,
    'transfer_layers_created',   v_tr_layers,
    'transfer_orphan_in',        v_tr_orphan,
    'transfer_keys_net_zero',    v_tr_nz,
    'transfer_unknown_layers',   v_tr_unk,
    'transfer_unknown_qty',      v_tr_unkq,
    'transfer_out_unpaired',     v_tr_unpaired,
    'processed_adjust',          v_adj,
    'adjust_layers_created',     v_adj_layers,
    'adjust_consume_rows',       v_adj_rows,
    'adjust_unknown_layers',     v_adj_unk,
    'adjust_new_net_zero',       v_adj_new_nz,
    'processed_assembly',        v_asm,
    'assembly_layers_created',   v_asm_layers,
    'assembly_consume_rows',     v_asm_rows,
    'assembly_partial_cost',     v_asm_partial,
    'assembly_net_zero',         v_asm_nz,
    'assembly_out_unpaired',     v_asm_unpaired,
    'processed_credit',          v_cr,
    'credit_layers_created',     v_cr_layers,
    'credit_traced',             v_cr_traced,
    'credit_avg',                v_cr_avg,
    'credit_unknown_layers',     v_cr_unk,
    'credit_net_zero',           v_cr_nz,
    'landed_rows',               v_landed_rows,
    'landed_amount',             v_landed_amt,
    'landed_orphan',             v_landed_orph,
    'freight_rows',              v_fr_rows,
    'freight_amount',            v_fr_amt,
    'freight_docs',              v_fr_docs,
    'freight_no_basis',          v_fr_nobasis,
    'freight_no_basis_amount',   v_fr_nobasis_amt,
    'freight_orphan',            v_fr_orphan,
    'freight_multi_ref',         v_fr_multi,
    -- ⭐ IMS (2026-09-20) — 한 칸에 중첩한다. ⚠️ jsonb_build_object 는 인자 100개 한도(키 50) — 기존 45키에 평면으로 더하면 넘는다. 기존 45칸은 이름·뜻 무변.
    'ims', jsonb_build_object(
      'receipts_posted',           v_ims_rcv,               -- 창구가 레이어를 만든 입고 수
      'layers_created',            v_ims_rcv_layers,        -- 그 레이어 행 수(라인 단위 · bin 접힘)
      'layers_existing',           v_ims_rcv_exist,         -- 0 이어야 한다
      'layers_cost_cad',           v_ims_rcv_cost,          -- Σ qty × unit_cost(CAD)
      'receipts_skipped',          v_ims_rcv_skipped,       -- ⚠️ 창구가 거부해 건너뛴 입고 수 — skip_reasons 에 문장
      'charges_posted',            v_ims_chg_n,
      'charge_rows',               v_ims_chg_rows,          -- cost_add 행 수
      'charge_amount_cad',         v_ims_chg_amt,
      'charge_no_basis_amount_cad',  v_ims_chg_nobasis_amt,   -- 버린 금액(정본 D)
      'charge_no_layers_amount_cad', v_ims_chg_nolayers_amt,  -- 버린 금액(레이어 없는 발주)
      'charge_already_posted',     v_ims_chg_already,       -- 0 이어야 한다
      'charges_skipped',           v_ims_chg_skipped,       -- ⚠️ 창구가 거부해 건너뛴 비용 수
      'charges_unvisited',         v_ims_chg_unvisited,     -- 배분된 발주 어디에도 IMS 레이어가 없어 부르지 않은 확정 비용 수
      'charges_unvisited_amount_cad', v_ims_chg_unvisited_amt,  -- 그 금액 — 설명된 차이
      'over_posted',               v_ims_over_n,            -- ⭐ 2026-09-20 초과분(over 닫기) — 창구가 레이어를 만든 차이 수
      'over_layers',               v_ims_over_layers,
      'over_skipped',              v_ims_over_skipped,      -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'over'
      'skipped_by_event',          v_ims_gate,              -- ⭐ 2026-09-20 창구가 아직 없어 보조 함수에 보내지 않은 IMS 사건 수(종류별 · 여덟 키 항상) — 0 이 아니면 그 사건의 창구를 만들 때다
      'skip_reasons',              v_ims_skip),             -- [{kind receipt|charge · number · id · sqlstate · error}] — 이유 문장 그대로
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

comment on function inv_layer_apply(date) is '⭐ 원가 레이어 전량 재생성(검산 도구 · 사람이 부를 때만 돈다 · cron 없음) — baseline 외 inv_layer · inv_layer_consume · inv_layer_cost_add 를 지우고 원장(inv_ledger · ⚠️ source 필터 없음 — cin7·manual·ims 전부)을 날짜순으로 다시 태운다. Cin7 줄은 inv_cost 로(보조 여섯), ⭐ IMS 줄(source ims)은 창구로 — 입고는 루프 안에서 inv_layer_post_receipt(입고 단위) · 초과분(:over)은 inv_layer_post_receipt_over(차이 단위) · 비용은 끝에서 inv_layer_post_charge · ⭐ [ⓒ1 2026-09-25] 반품(credit_in · source ims)은 inv_layer_apply_credit_ims → inv_layer_post_credit(실시간과 같은 함수 · raw.cost.remainder hint) · Cin7 축 credit_in 은 inv_layer_apply_credit 그대로. [2026-09-20 보조 넷 문] 창구가 아직 없는 IMS 사건(transfer_in/out · manual_reversal · adjust_existing/new · assemble_in/out)은 보조 함수에 보내지 않고 ims.skipped_by_event 에 종류별로 센다(credit_in 키는 남되 늘 0) — 0 이 아니면 그 창구를 만들 때다 · sale_out 은 그대로 소진(한 원장 FIFO). 창구가 거부한 것은 멈추지 않고 건너뛰어 센다 — ims.receipts_skipped · over_skipped · charges_skipped · skip_reasons[]. 권한: 시작에서 receiving·purchasing 쓰기 권한을 본다(psql 은 request.jwt.claims). 반환 45칸 무변 + ims{} 중첩. 원본 20260910141553 → 20260920142635 → 20260920171930 → 20260920181910 → 20260921161933 → 20260925012354';

-- ═══ ⑥ 창구 셋 — so_credit_issue(manager · 미리 보기) · so_credit_cancel(manager · 원장 되돌림) · so_credit_detail(읽기) ═══
-- 6-a so_credit_issue — p {invoice_id | cin7 {invoice_number, order_number?, invoice_date?} + customer_id + tax_rule, reason, note?, warehouse_id?, issued_on?,
--                        lines [{kind product|freight|tax|other|restocking_fee, so_invoice_line_id?(IMS), sku?(Cin7), qty_returned?, unit_price?(Cin7), restock_bin?(칸 이름 · 없으면 ims_last_bin), not_restocked_reason?(+note) — 있으면 안 돌아옴,
--                                amount?(freight·tax·other · fee 는 음수), pct?(fee), description?, account_id?}]}
create function public.so_credit_issue(p jsonb, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other'];
  c_nr        constant text[] := array['damaged','b_grade','not_returned','other'];
  v_staff     uuid;
  v_on        date;
  v_reason    text;
  v_inv       public.so_invoice%rowtype;
  v_c         public.customer%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_w         public.ref_warehouse%rowtype;
  v_rule      public.ref_tax_rule%rowtype;
  v_cr        public.so_credit%rowtype;
  v_il        public.so_invoice_line%rowtype;
  v_io        public.so_invoice_order%rowtype;
  v_pr        public.product%rowtype;
  v_bin       public.ref_bin%rowtype;
  v_acct      public.ref_account%rowtype;
  v_cin7      boolean := false;
  v_cin7_inv  text;  v_cin7_ord text;  v_cin7_date date;
  v_cust      uuid;
  v_origin_on date;
  v_wh        uuid;
  v_first_io  public.so_invoice_order%rowtype;
  v_fee_days  int;  v_fee_pct numeric;  v_fee_acct_code text;
  v_lines     jsonb := '[]'::jsonb;
  v_ln        int := 0;
  v_kind      text;
  v_qty       numeric;  v_already numeric;  v_unit numeric;  v_amount numeric;  v_rate numeric;  v_tax numeric;
  v_bin_name  text;  v_bin_id uuid;  v_nr text;  v_nr_note text;  v_desc text;  v_acct_id uuid;  v_acct_code text;
  v_product_id uuid;  v_so_line_id uuid;  v_sku text;  v_il_id uuid;
  v_lines_amt numeric := 0;  v_fee_amt numeric := 0;  v_tax_amt numeric := 0;  v_product_amt numeric := 0;
  v_rates     numeric[] := '{}';  v_first_rate numeric;
  v_fee_lines int := 0;  v_restock_n int := 0;
  v_fee_sugg  jsonb;
  v_warn      text[] := '{}';
  v_ledger    jsonb;
  v_est       numeric;  v_est_qty numeric;
  v_ask       numeric;
  x           jsonb;
  e           jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 발행은 manager 이상(판정 3)
  v_staff := public.so_current_staff();
  v_on := coalesce(nullif(p->>'issued_on', '')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Credit date % is in the future — nothing was saved', v_on; end if;
  v_reason := nullif(trim(p->>'reason'), '');
  if v_reason is null or v_reason <> all (c_reasons) then raise exception 'reason must be one of customer_return, damaged, billing_error, other — nothing was saved'; end if;
  if v_reason = 'other' and nullif(trim(p->>'note'), '') is null then raise exception 'reason other needs a note — nothing was saved'; end if;
  if p->'lines' is null or jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  -- 설정(판정 5·7)
  select nullif(k.value, '')::int into v_fee_days from public.inv_config k where k.key = 'so_credit_restock_fee_days';
  select nullif(k.value, '')::numeric into v_fee_pct from public.inv_config k where k.key = 'so_credit_restock_fee_pct';
  select nullif(k.value, '') into v_fee_acct_code from public.inv_config k where k.key = 'so_credit_restock_fee_account_code';

  -- 원본 — IMS 인보이스 또는 Cin7 번호 원문(판정 6 · 0-4)
  if nullif(p->>'invoice_id', '') is not null then
    select * into v_inv from public.so_invoice i where i.id = (p->>'invoice_id')::uuid for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_inv.status <> 'issued' then raise exception 'Invoice % is % — credit the live invoice, not a cancelled one — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
    v_cust := v_inv.bill_to_customer_id;  v_origin_on := v_inv.issued_on;
    select * into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
    select o.* into v_first_io from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.location_id into v_wh from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id order by o.so_number limit 1;
  elsif p->'cin7' is not null and jsonb_typeof(p->'cin7') = 'object' then
    v_cin7 := true;
    v_cin7_inv := nullif(trim(p->'cin7'->>'invoice_number'), '');  v_cin7_ord := nullif(trim(p->'cin7'->>'order_number'), '');  v_cin7_date := nullif(p->'cin7'->>'invoice_date', '')::date;
    if v_cin7_inv is null then raise exception 'A Cin7 credit needs cin7.invoice_number (the paper number) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A Cin7 credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_cin7_date;
    if v_cin7_ord is null then v_warn := array_append(v_warn, 'origin_sale_unknown'); end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is null then raise exception 'A Cin7 credit needs tax_rule (an active sale tax rule name) — nothing was saved'; end if;
    select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
    if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
    select c.default_location_id into v_wh from public.customer c where c.id = v_cust;
  else
    raise exception 'Give invoice_id (an IMS invoice) or cin7 {invoice_number, order_number, invoice_date} — nothing was saved';
  end if;
  select * into v_c from public.customer c where c.id = v_cust for update;         -- 청구처 손님 행 잠금(잔액 직렬화 · ⓑ 와 같은 자물쇠)
  if not found then raise exception 'Customer not found — nothing was saved'; end if;

  -- 창고(반품을 받은 창고 · ⬜4) — 지정 → 원 판매 창고 → 손님 기본 창고 → 거부
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_wh);
  if v_wh is null then raise exception 'warehouse_id is required — where were the goods returned to? — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;

  -- 줄 — 첫 바퀴: product · freight · tax · other(수수료는 둘째 바퀴 · 제품 합이 먼저 필요하다)
  for x in select t from jsonb_array_elements(p->'lines') t loop
    v_kind := nullif(trim(x->>'kind'), '');
    if v_kind is null or v_kind not in ('product','freight','tax','other','restocking_fee') then raise exception 'Line kind must be one of product, freight, tax, other, restocking_fee — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
    v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;

    if v_kind = 'product' then
      v_qty := nullif(x->>'qty_returned', '')::numeric;
      if v_qty is null or v_qty <= 0 then raise exception 'A product line needs qty_returned > 0 — nothing was saved'; end if;
      if v_cin7 then
        v_sku := nullif(trim(x->>'sku'), '');
        if v_sku is null then raise exception 'A Cin7 product line needs sku — nothing was saved'; end if;
        select * into v_pr from public.product pr where pr.sku = v_sku;
        if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
        v_unit := nullif(x->>'unit_price', '')::numeric;
        if v_unit is null or v_unit < 0 then raise exception 'A Cin7 product line needs unit_price (the price on that invoice) — nothing was saved'; end if;
        v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_pr.name);
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS product line needs so_invoice_line_id (the invoice line being returned) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
        if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        select coalesce(sum(cl.qty_returned), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id
         where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
      v_product_amt := v_product_amt + v_amount;  v_rates := array_append(v_rates, v_rate);
      -- 돌아오나(판정 1) — not_restocked_reason 이 있으면 안 돌아옴 · 아니면 칸(지정 → ims_last_bin → 거부 · '' 불허 · ⬜4)
      v_nr := nullif(trim(x->>'not_restocked_reason'), '');
      if v_nr is not null then
        if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        v_nr_note := nullif(trim(x->>'not_restocked_note'), '');
        if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
      else
        v_bin_name := nullif(trim(x->>'restock_bin'), '');
        if v_bin_name is null then
          v_bin_name := public.ims_last_bin(array[coalesce(v_pr.parent_product_id, v_pr.id)], v_w.id) -> coalesce(v_pr.parent_product_id, v_pr.id)::text ->> 'bin';
          if v_bin_name is null then raise exception 'No bin known for % in % — pick a restock bin (or mark the line not restocked) — nothing was saved', v_sku, v_w.name; end if;
        end if;
        select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
        if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
        if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
        v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
        -- 원가 복원 예상(미리 보기 · 원 판매의 소비 기록 평균 × EA · 없으면 null)
        select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0), sum(cs.qty) into v_est, v_est_qty
          from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
         where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_pr.parent_product_id), v_pr.sku)
           and cs.doc_number = case when v_cin7 then v_cin7_ord else (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id)) end;
      end if;
    elsif v_kind = 'freight' then
      if v_cin7 then
        v_amount := nullif(x->>'amount', '')::numeric;  v_rate := v_rule.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Freight');
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_99_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS freight line needs so_invoice_line_id (the charge line) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'charge';
        if v_il.id is null then raise exception 'Invoice line % is not a charge line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_amount := coalesce(nullif(x->>'amount', '')::numeric, v_il.amount);  v_rate := v_io.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select coalesce(sum(cl.amount), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        if v_already + v_amount > v_il.amount then raise exception 'Invoice % charge % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_already, v_il.amount, v_il.amount - v_already; end if;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_amount is null or v_amount < 0 then raise exception 'A freight line needs amount ≥ 0 — nothing was saved'; end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
    elsif v_kind = 'tax' then
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null or v_amount < 0 then raise exception 'A tax line needs amount ≥ 0 (the tax being returned) — nothing was saved'; end if;
      v_rate := null;  v_tax := 0;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Tax');
      if v_acct.id is null then
        select * into v_acct from public.ref_account a where a.id = (case when v_cin7 then v_rule.account_id else (select r.account_id from public.ref_tax_rule r where r.id = v_first_io.tax_rule_id) end);
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_cin7 then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', v_kind, 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku, 'description', v_desc,
                                             'qty_returned', v_qty, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                             'unit_price', v_unit, 'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code,
                                             'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_qty * coalesce(v_pr.pack_factor, 1), 6) end);
  end loop;

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수
  v_first_rate := case when v_cin7 then v_rule.rate_pct else v_rates[1] end;
  if v_fee_lines > 0 then
    if v_fee_lines > 1 then raise exception 'Only one restocking_fee line per credit note — nothing was saved'; end if;
    if (select count(distinct r) from unnest(v_rates) r) > 1 then v_warn := array_append(v_warn, 'fee_rate_mixed'); end if;
    for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'restocking_fee' loop
      v_acct := null;  v_acct_id := nullif(x->>'account_id', '')::uuid;
      if v_acct_id is not null then select * into v_acct from public.ref_account a where a.id = v_acct_id;
      elsif v_fee_acct_code is not null then select * into v_acct from public.ref_account a where a.code = v_fee_acct_code; end if;
      if v_acct.id is null then raise exception 'A restocking fee line needs account_id — no default account is set (inv_config so_credit_restock_fee_account_code) — nothing was saved'; end if;
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null then v_amount := -round(v_product_amt * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;
      if v_amount > 0 then raise exception 'A restocking fee reduces the credit — amount must be ≤ 0 (got %) — nothing was saved', v_amount; end if;
      v_tax := public.so_tax_amount(v_amount, v_first_rate);
      v_ln := v_ln + 1;  v_fee_amt := v_fee_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'restocking_fee', 'description', coalesce(nullif(trim(x->>'description'), ''), format('Restocking fee %s%%', coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct))),
                                               'amount', v_amount, 'rate_pct', v_first_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
    end loop;
  end if;
  -- 알림(판정 5) — 원 인보이스 발행일 + N일이 지났고 수수료 줄이 없으면 「대상」만 알린다(자동으로 붙이지 않는다)
  if v_origin_on is null then v_warn := array_append(v_warn, 'fee_window_unknown');
  elsif v_fee_days is not null and v_on - v_origin_on > v_fee_days and v_fee_lines = 0 and v_product_amt > 0 then
    v_warn := array_append(v_warn, 'restock_fee_window:' || (v_on - v_origin_on)::text);
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round(v_product_amt * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'fee_amount', v_fee_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_fee_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, cin7_invoice_number, cin7_order_number, cin7_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, fee_amount, tax_amount, total, created_by, updated_by)
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_cin7_inv, v_cin7_ord, v_cin7_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_fee_amt, v_tax_amt, v_lines_amt + v_fee_amt + v_tax_amt, v_staff, v_staff)
  returning * into v_cr;
  for e in select t from jsonb_array_elements(v_lines) t loop
    insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, description, qty_returned, restock_bin_id, restock_bin, not_restocked_reason, not_restocked_note,
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by)
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'fee_amount', v_cr.fee_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.so_credit_issue(jsonb, boolean) is
  '⭐⭐ 크레딧 노트 발행(8-g · 판정 1~7 · ⓒ1) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · p_commit false = 미리 보기(아무것도 안 씀 · 제안 칸 · 원가 복원 예상 · 수수료 알림). 원본 = invoice_id(IMS · issued 만) 또는 cin7 {invoice_number(종이) · order_number(되짚기 열쇠 · 비면 경고) · invoice_date} + customer_id + tax_rule(활성 sale 규칙 이름). 줄: product(IMS so_invoice_line_id → 단가·세율(그 인보이스 오더)·계정 굳힘 · Σ반품 ≤ 판매 · Cin7 sku·unit_price 손으로 · not_restocked_reason 있으면 안 돌아옴 · 아니면 칸 = restock_bin → ims_last_bin → 거부(빈 문자열 불허)) · freight(IMS 운임 줄 · ≤ 그 줄) · tax(세액만 · 세금 계정) · other(계정 필수) · restocking_fee(하나 · 기본 −Σ제품×pct · 계정 지정→설정→거부 · 세율 첫 제품 줄 · 세금도 음수). 알림 restock_fee_window:N + fee_suggested(자동으로 안 붙인다 · 판정 5). 발행 = 머리·줄 insert → restock 줄이 있으면 inv_post_credit(원장 credit_in · 레이어). 반환 lines · totals · fee_suggested · ledger · warnings';
revoke all on function public.so_credit_issue(jsonb, boolean) from public, anon;
grant execute on function public.so_credit_issue(jsonb, boolean) to authenticated;

-- 6-b so_credit_cancel — manager · 활성 alloc 없음 ∧ 돌아온 레이어 소진 0 → 반대 credit_in(line_ref :reversal) + reversal 소진(17-f ② 첫 실물) · 팔렸으면 거부(재고 조정으로 안내) · 번호 남음(0-10)
create function public.so_credit_cancel(p_credit_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_cr      public.so_credit%rowtype;
  v_note    text;
  v_n       int;
  v_alloc   int;
  v_sold    text;
  v_rows    int := 0;
  v_layers  int := 0;
  v_qty     numeric := 0;
  v_today   date := public.ims_today();
  g         record;
  y         record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'A cancel needs a reason (p_note) — nothing was saved'; end if;
  select * into v_cr from public.so_credit c where c.id = p_credit_id for update;
  if not found then raise exception 'Credit note not found — nothing was saved'; end if;
  if v_cr.status <> 'issued' then raise exception 'Credit note % is already % — nothing was saved', v_cr.credit_number, v_cr.status; end if;
  perform 1 from public.customer c where c.id = v_cr.customer_id for update;
  select count(*) into v_alloc from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null;
  if v_alloc > 0 then raise exception 'Credit note % has been applied (% allocation(s)) — detach it first — nothing was saved', v_cr.credit_number, v_alloc; end if;

  -- 원장: 돌아온 레이어(origin creditnote · doc = CR)가 하나라도 소진됐으면 거부
  select string_agg(l.sku || ' @' || l.warehouse, ', ') into v_sold
    from public.inv_layer l where l.origin_type = 'creditnote' and l.doc_number = v_cr.credit_number
     and exists (select 1 from public.inv_layer_consume k where k.layer_id = l.id);
  if v_sold is not null then
    raise exception 'Credit note % — the returned stock was already sold on (%) — it cannot be cancelled; use a stock adjustment and a new credit note instead — nothing was saved', v_cr.credit_number, v_sold;
  end if;

  -- 반대 사건 — 행마다 qty_delta 음수 · line_ref :reversal(유니크 키 · 재생성은 키 순액 ≤ 0 → net_zero) · 레이어는 reason reversal 로 전량 소진(실시간도 남은 것 0)
  for g in select * from public.inv_ledger l where l.doc_type = 'creditnote' and l.doc_number = v_cr.credit_number and l.source = 'ims' and l.event_type = 'credit_in' and l.qty_delta > 0 order by l.id loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_today, 2, g.sku, g.warehouse, g.bin, -g.qty_delta, 'credit_in', 'creditnote', g.doc_number, g.doc_task_id, g.line_ref || ':reversal', null, 'ims',
            jsonb_build_object('kind', 'credit_in_reversal', 'poster', 'so_credit_cancel@2026-09-25.1', 'header', g.raw -> 'header', 'reversal_of', g.id, 'credit_id', v_cr.id, 'cancel_note', v_note, 'cancelled_by', v_staff, 'cancelled_on', v_today));
    v_rows := v_rows + 1;  v_qty := v_qty + g.qty_delta;
  end loop;
  for y in select * from public.inv_layer l where l.origin_type = 'creditnote' and l.doc_number = v_cr.credit_number order by l.id loop
    insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason)
    values (y.id, 'creditnote', v_cr.credit_number, y.line_ref || ':reversal', 'credit_in', v_today, y.qty, y.unit_cost, round(y.qty * y.unit_cost, 6), 'reversal');
    v_layers := v_layers + 1;
  end loop;

  update public.so_credit set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_note = v_note, updated_by = v_staff where id = v_cr.id and status = 'issued';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Credit note % was not cancelled — it may have been changed by someone else just now — nothing was saved', v_cr.credit_number; end if;
  return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', 'cancelled', 'note', v_note, 'cancelled_by', v_staff,
                            'ledger_rows_reversed', v_rows, 'qty_ea_reversed', v_qty, 'layers_reversed', v_layers);
end;
$$;
comment on function public.so_credit_cancel(uuid, text) is
  '⭐ 크레딧 노트 취소(8-g · 0-10 · ⓒ1) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · issued 만 · 사유 필수 · 활성 so_credit_alloc 이 있으면 거부(먼저 떼라 · ⓒ2) · 돌아온 레이어가 소진됐으면 거부(「already sold on — 재고 조정 + 새 크레딧」) · 아니면 원장 반대 사건(credit_in · qty_delta 음수 · line_ref :reversal · 오늘 · seq_hint 2) + 레이어 reason reversal 전량 소진(17-f ② 첫 실물) → 재생성은 키 순액 0 → net_zero(레이어 없음) · 실시간은 남은 것 0 — 합이 같다 · 번호는 남는다';
revoke all on function public.so_credit_cancel(uuid, text) from public, anon;
grant execute on function public.so_credit_cancel(uuid, text) to authenticated;

-- 6-c so_credit_detail — 읽기 한 창구(invoker · stable · 로그인)
create function public.so_credit_detail(p_credit_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_cr public.so_credit%rowtype;
begin
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found'; end if;
  return jsonb_build_object(
    'credit', to_jsonb(v_cr),
    'customer_name', (select c.name from public.customer c where c.id = v_cr.customer_id),
    'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_cr.invoice_id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb) from public.so_credit_line l where l.credit_id = v_cr.id),
    'allocations', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]'::jsonb) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'applied', (select coalesce(sum(a.amount), 0) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'remaining', case when v_cr.status = 'cancelled' then 0 else v_cr.total - (select coalesce(sum(a.amount), 0) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null) end,
    'ledger', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'occurred_on', g.occurred_on, 'sku', g.sku, 'warehouse', g.warehouse, 'bin', g.bin, 'qty_delta', g.qty_delta, 'line_ref', g.line_ref, 'cost', g.raw -> 'cost') order by g.id), '[]'::jsonb)
                 from public.inv_ledger g where g.doc_type = 'creditnote' and g.doc_number = v_cr.credit_number and g.source = 'ims'),
    'layers', (select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'sku', y.sku, 'warehouse', y.warehouse, 'qty', y.qty, 'unit_cost', y.unit_cost, 'cost_source', y.cost_source, 'parent_layer_id', y.parent_layer_id,
                                                            'consumed', (select coalesce(sum(k.qty), 0) from public.inv_layer_consume k where k.layer_id = y.id)) order by y.id), '[]'::jsonb)
               from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = v_cr.credit_number));
end;
$$;
comment on function public.so_credit_detail(uuid) is '크레딧 노트 읽기 한 창구(ⓒ1) — invoker · stable(RLS select · 로그인) · credit · lines · 활성 allocations · applied · remaining(진 빚 남은 몫) · ledger(credit_in 행 · raw.cost) · layers(원가 레이어 · 소진량)';
revoke all on function public.so_credit_detail(uuid) from public, anon;
grant execute on function public.so_credit_detail(uuid) to authenticated;

-- ═══ 검증(~/asung/prompts/so-credit-1a-verify.sql · 새 틀 · psql -v mig=<이 파일> · 전부 rollback · 시퀀스 셋 setval) — 요지는 지시서 §4 ═══
