-- ═══ SO 결제 ⓑ1 — 결제 표 · 붙이기 · 선결제 대상 · 계좌 기본값 · 손님 잔액 · 남은 금액 · 제안 · 창구 다섯 (2026-09-24 · 지시서 ~/asung/prompts/so-payment-1.md · 판정 회신 Caleb 2026-09-24 집) ═══
-- 자리: 인보이스 · 결제 · 크레딧(§8)의 둘째 차수 ⓑ(ⓐ 인보이스 ✅ → ⓑ 결제·잔액 → ⓒ 크레딧). ⓐ1(20260924200029)의 so_invoice 위에 선다.
-- 정본 §8 8-d(kind · 다대다 · 오래된 것부터 제안하되 사람이 바꾼다) · 8-e(잔액 식 하나 · 출처 둘 · 별도 잔액 표 없음) · 8-f(오버페이 = 잔액) · 판정 1~7 · 이견 0-1~0-11 ✅.
--
-- 판정(Caleb 2026-09-24 · 말 그대로 요약)
--   판정 2  결제 방법 여덟(cheque · credit_card · debit_card · e_transfer · wire · cash · direct_deposit · shopify) · (방법, 브랜치, 통화) → 계좌 기본값 · 사람이 바꿀 수 있다 · 기본값 없는 칸(송금·직접 입금 CAD · USD 없음 칸)은 계좌를 요구(0-9 · 거부 아님)
--   판정 4  결제에 대상 오더를 적어 두면 그 오더가 마무리될 때 인보이스에 자동으로 붙는다(붙이는 것은 ⓑ2 · 여기는 표만) · 판정 6  넣기·붙이기·대상 = sales · 떼기·취소·환불 = manager
--   판정 7  취소 때 alloc 중 source manual 이 하나라도 있으면 거부 · auto_deposit·auto_balance 는 취소와 함께 void(ⓑ2 · source 칸은 여기서)
-- 이견(✅)
--   0-2  「sales 이상」은 역할이 아니다 — ims_require_write('sales') · manager 는 so_require_role('manager')(ims_role_rank 에 sales 없음)
--   0-5  인보이스 남은 금액 = total − Σ활성 alloc 하나(so_invoice_remaining) · amount_due 는 종이에 찍힌 값일 뿐(ⓑ2 가 deposit_applied 로 CHECK 교체)
--   0-6  환불은 집계라(8-e) 붙이기 한도 = min(인보이스 남은 금액, 결제 남은 금액, 그 통화의 받아 둔 돈) 셋 · 결제 취소도 잔액이 음수가 되면 거부
--   0-7  예약된 선결제 = 대상 오더 중 「끝 상태 아님 ∧ 살아 있는 인보이스 없음」이 하나라도 남은 결제의 남은 금액 — available 에서 뺀다(ⓑ2 자동 잔액 붙이기가 쓰는 값) · 대상이 전부 발행·취소되면 저절로 일반 잔액
-- 표(9-b 이름) so_payment · so_payment_alloc(떼기 = void · 활성 유니크는 생성 칸 active_invoice_id · 규칙 29) · so_payment_order(대상 · 금액 없음) · so_payment_account_default(판정 2 씨앗 22 · 마스터 쓰기)
-- 읽기  so_customer_balance(통화별 · 식의 정본) · so_invoice_remaining · so_payment_default_account · so_payment_propose(읽기만)
-- 속    so_payment_resolve_account · so_payment_alloc_add(한도 셋 · source 인자 — ⓑ2 의 자동 붙이기도 이 함수로)
-- 창구  so_payment_add(sales) · so_payment_attach(sales) · so_payment_detach(manager) · so_payment_void(manager) · so_payment_refund(manager)
-- ⓑ2 몫(여기 없음): so_invoice_issue 재발행(자동 붙이기 · deposit_applied · balance_forward · fulfilled) · so_invoice_cancel 재발행(풀기·가드) · so_status_guard 짝 · so_detail · 견적서(so_proforma)
-- 검증 ~/asung/prompts/so-payment-1a-verify.sql · 시퀀스 둘(so_number_seq · so_invoice_number_seq)은 rollback 밖 setval

-- ═══ ① so_payment — 결제·환불 머리(8-d · kind 로 가르고 금액은 늘 양수) ═══
create table if not exists public.so_payment (
  id              uuid primary key default gen_random_uuid(),
  kind            text not null,                                                              -- payment · refund(8-d · 부호가 아니라 kind)
  amount          numeric not null,                                                           -- ⚠️ 늘 양수
  paid_on         date not null default public.ims_today(),
  method          text not null,                                                              -- 판정 2 여덟
  reference       text,                                                                       -- 수표 번호 · e-Transfer 참조 · Shopify 거래번호
  customer_id     uuid not null references public.customer     (id) on delete no action,     -- 낸 손님 = 청구처(so_invoice.bill_to_customer_id 와 맞춘다)
  currency_id     uuid not null references public.ref_currency (id) on delete no action,
  currency_code   text,
  account_id      uuid not null references public.ref_account  (id) on delete no action,     -- 지정만(분개는 QBO · PO 와 같다) · 활성 BANK 또는 _5_
  account_code    text,                                                                       -- 그날 값
  warehouse_id    uuid not null references public.ref_warehouse (id) on delete no action,    -- 브랜치 = 창고(어디서 받았나 · TOR/EDM 글자 대신 FK · ref_warehouse 에 code 없음)
  warehouse_name  text,
  note            text,
  status          text not null default 'active',
  voided_at       timestamptz,
  voided_by       uuid references public.ims_staff (id) on delete no action,
  void_note       text,
  created_by      uuid references public.ims_staff (id) on delete no action,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  updated_by      uuid references public.ims_staff (id) on delete no action,
  constraint so_payment_kind_ck      check (kind in ('payment','refund')),
  constraint so_payment_amount_ck    check (amount > 0),
  constraint so_payment_method_ck    check (method in ('cheque','credit_card','debit_card','e_transfer','wire','cash','direct_deposit','shopify')),
  constraint so_payment_status_ck    check (status in ('active','voided')),
  constraint so_payment_void_ck      check ((status = 'voided') = (voided_at is not null)),
  constraint so_payment_void_by_ck   check ((voided_at is null) = (voided_by is null)),
  constraint so_payment_void_note_ck check ((voided_at is null) = (void_note is null))
);
create index if not exists so_payment_customer_idx   on public.so_payment (customer_id);
create index if not exists so_payment_currency_idx   on public.so_payment (currency_id);
create index if not exists so_payment_account_idx    on public.so_payment (account_id);
create index if not exists so_payment_warehouse_idx  on public.so_payment (warehouse_id);
create index if not exists so_payment_paid_on_idx    on public.so_payment (paid_on);
create index if not exists so_payment_voided_by_idx  on public.so_payment (voided_by);
create index if not exists so_payment_created_by_idx on public.so_payment (created_by);
create index if not exists so_payment_updated_by_idx on public.so_payment (updated_by);
comment on table  public.so_payment is 'SO 결제·환불(§8 8-d · ⓑ1 · 2026-09-24) · ⭐ 거래 — 컷오버 때 지운다 · kind payment|refund 로 가르고 amount 는 늘 양수(부호로 담으면 where amount > 0 이 환불을 조용히 지운다) · 결제와 인보이스는 다대다(so_payment_alloc) · 선수금 = 붙지 않은 결제(별도 문서 없음 · 8-e) · 대상 오더는 so_payment_order · 상태 active|voided(취소 = void · 삭제 없음) · 번호 없음(참조번호는 손님 것) · 쓰기는 창구만(so_payment_add · attach · detach · void · refund · 표는 select 만)';
comment on column public.so_payment.kind          is 'payment · refund(8-d Caleb 「리펀드 금액이 양수로 기록 … 헷갈리는 포인트」 → 부호가 아니라 kind) · 환불은 어느 결제에도 매이지 않는다 — 잔액 식(8-e)이 집계이기 때문 · 환불 한도 = 그 통화의 받아 둔 돈(so_payment_refund)';
comment on column public.so_payment.amount        is '⚠️ 늘 양수(CHECK) · 소수 둘째 자리까지(창구가 거부) · payment 는 amount − Σ활성 alloc 이 「결제의 남은 금액」';
comment on column public.so_payment.paid_on       is '받은 날(토론토 ims_today 기본 · 미래 거부) · 제안·자동 붙이기의 순서 열쇠(오래된 것부터)';
comment on column public.so_payment.method        is '판정 2 여덟 — cheque · credit_card · debit_card · e_transfer · wire · cash · direct_deposit · shopify(AONE 온라인 결제 · 유입 차수가 넣는다) · CHECK so_payment_method_ck';
comment on column public.so_payment.customer_id   is '낸 손님 = 청구처 — 붙이는 인보이스의 bill_to_customer_id 와 같아야 한다(so_payment_alloc_add 가 거부) · 대상 오더는 coalesce(so.bill_to_customer_id, so.customer_id) 가 이 손님';
comment on column public.so_payment.account_id    is '받은(환불은 내보낸) 계좌 · 지정만 한다(분개는 QBO · po_payment.account_id 와 같은 태도) · 기본값은 so_payment_account_default(방법 · 창고 · 통화) · 사람이 바꿀 수 있다 · 후보 = is_active and (account_type = BANK or code = _5_)(§3 ① 실측 · for_payments 는 BANK 전부 false 라 못 쓴다)';
comment on column public.so_payment.warehouse_id  is '브랜치(어디서 받았나) = ref_warehouse FK(code 칸이 없어 TOR·EDM 글자 대신) · 기본값 = 첫 대상 오더의 so.location_id → customer.default_location_id → 없으면 창구가 요구';
comment on column public.so_payment.status        is 'active · voided(취소 = void · manager · 활성 alloc 이 있으면 먼저 떼라 · payment 취소 뒤 받아 둔 돈이 음수면 거부(환불이 이미 나갔다 · 0-6)) · CHECK 짝 셋(voided_at · voided_by · void_note)';

-- ═══ ② so_payment_alloc — 이 결제가 어느 인보이스에 얼마씩(8-d payment_invoice · 다대다 · 떼기 = void · 흔적) ═══
create table if not exists public.so_payment_alloc (
  id                uuid primary key default gen_random_uuid(),
  payment_id        uuid not null references public.so_payment (id) on delete cascade,        -- 문서 → 소유 줄
  invoice_id        uuid not null references public.so_invoice (id) on delete no action,
  amount            numeric not null,
  source            text not null default 'manual',                                           -- manual · auto_deposit · auto_balance(판정 7 · ⓑ2 가 쓴다)
  voided_at         timestamptz,
  voided_by         uuid references public.ims_staff (id) on delete no action,
  void_note         text,
  created_by        uuid references public.ims_staff (id) on delete no action,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.ims_staff (id) on delete no action,
  active_invoice_id uuid generated always as (case when voided_at is null then invoice_id end) stored,   -- ⭐ 활성 짝 하나(규칙 29 · so_invoice_order.active_so_id 와 같은 장치)
  constraint so_payment_alloc_amount_ck    check (amount > 0),
  constraint so_payment_alloc_source_ck    check (source in ('manual','auto_deposit','auto_balance')),
  constraint so_payment_alloc_void_by_ck   check ((voided_at is null) = (voided_by is null)),
  constraint so_payment_alloc_void_note_ck check ((voided_at is null) = (void_note is null)),
  constraint so_payment_alloc_active_uq    unique (payment_id, active_invoice_id)
);
create index if not exists so_payment_alloc_payment_idx    on public.so_payment_alloc (payment_id);
create index if not exists so_payment_alloc_invoice_idx    on public.so_payment_alloc (invoice_id);
create index if not exists so_payment_alloc_voided_by_idx  on public.so_payment_alloc (voided_by);
create index if not exists so_payment_alloc_created_by_idx on public.so_payment_alloc (created_by);
create index if not exists so_payment_alloc_updated_by_idx on public.so_payment_alloc (updated_by);
comment on table  public.so_payment_alloc is 'SO 결제 → 인보이스 붙임(8-d payment_invoice · ⓑ1) · ⭐ 거래 · 결제 하나가 인보이스 여럿 · 인보이스 하나에 결제 여럿(50% COD & 50% N30) · 떼기 = void(행은 남는다 · 「원인을 모르면 상쇄하지 않는다 · 흔적을 남긴다」) · 활성 짝은 하나(생성 칸 active_invoice_id + unique · 부분 유니크 없음) · source 는 취소가 자동 붙은 것을 함께 푸는 열쇠(판정 7) · 쓰기는 so_payment_alloc_add(속) · 창구만';
comment on column public.so_payment_alloc.source is 'manual(사람이 붙였다 · 넣기·붙이기 창구) · auto_deposit(발행 때 대상 오더의 선결제 · ⓑ2) · auto_balance(발행 때 손님 잔액 · ⓑ2) · 인보이스 취소는 manual 이 하나라도 있으면 거부 · auto 둘은 함께 void(판정 7)';
comment on column public.so_payment_alloc.active_invoice_id is '생성 칸 — voided_at 이 비었을 때만 invoice_id · unique (payment_id, active_invoice_id) 로 「한 결제는 한 인보이스에 활성 줄 하나」(void 뒤 다시 붙이면 새 행 · 규칙 29 부분 유니크 금지)';

-- ═══ ③ so_payment_order — 선결제 대상 오더(판정 4 · 금액 없음 · 「이 돈은 이 오더를 위한 것」 표시만) ═══
create table if not exists public.so_payment_order (
  id          uuid primary key default gen_random_uuid(),
  payment_id  uuid not null references public.so_payment (id) on delete cascade,
  so_id       uuid not null references public.so (id) on delete no action,
  created_by  uuid references public.ims_staff (id) on delete no action,
  created_at  timestamptz not null default now(),
  constraint so_payment_order_uq unique (payment_id, so_id)
);
create index if not exists so_payment_order_so_idx         on public.so_payment_order (so_id);
create index if not exists so_payment_order_created_by_idx on public.so_payment_order (created_by);
comment on table public.so_payment_order is 'SO 선결제 대상 오더(판정 4 · ⓑ1) · ⭐ 거래 · 한 결제 → 오더 여럿 · 한 오더 ← 결제 여럿 · ⚠️ 금액 없음 — 인보이스가 서기 전에 배분 장부를 하나 더 두지 않는다 · 뜻: 그 오더가 마무리(so_finalize → so_invoice_issue · ⓑ2)될 때 이 결제의 남은 금액이 그 인보이스에 auto_deposit 으로 붙는다 · 대상 오더 중 하나라도 「끝 상태 아님 ∧ 살아 있는 인보이스 없음」이면 그 결제의 남은 금액은 예약(reserved_deposit · 0-7)이라 일반 잔액(available)에서 빠진다 · 대상이 전부 발행·취소되면 저절로 일반 잔액 · 표시는 지우지 않는다(so_payment_void 가 돈만 접는다)';

-- ═══ ④ so_payment_account_default — (방법, 창고, 통화) → 계좌 기본값(판정 2 · 마스터 쓰기 · 씨앗 22) ═══
create table if not exists public.so_payment_account_default (
  id            uuid primary key default gen_random_uuid(),
  method        text not null,
  warehouse_id  uuid not null references public.ref_warehouse (id) on delete no action,
  currency_code text not null,
  account_id    uuid not null references public.ref_account (id) on delete no action,
  account_code  text not null,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  constraint so_payment_account_default_method_ck   check (method in ('cheque','credit_card','debit_card','e_transfer','wire','cash','direct_deposit','shopify')),
  constraint so_payment_account_default_currency_ck check (currency_code ~ '^[A-Z]{3}$'),
  constraint so_payment_account_default_uq          unique (method, warehouse_id, currency_code)
);
create index if not exists so_payment_account_default_warehouse_idx  on public.so_payment_account_default (warehouse_id);
create index if not exists so_payment_account_default_account_idx    on public.so_payment_account_default (account_id);
create index if not exists so_payment_account_default_updated_by_idx on public.so_payment_account_default (updated_by);
comment on table public.so_payment_account_default is 'SO 결제 계좌 기본값(판정 2 · ⓑ1) — 열쇠 (method, warehouse_id, currency_code) · 없는 조합 = 기본값 없음(송금·직접 입금 CAD · 데빗·e-Transfer·Shopify USD) → 넣을 때 계좌를 요구(0-9 · 거부 아님) · 관계 표(마스터 쓰기 master · DELETE 열림 · admin 이 고친다 · 마이그레이션 아님) · 씨앗 22 = 창고 둘(Asung Trading Inc. · Asung - Edmonton) × 11 · 회계사 확인 거리 _1150040029_ Clearing - Shopify 는 씨앗 없이 고를 수만 · 「모든 창고」 행 대신 창고마다 행(부분 유니크 회피)';

do $$
declare
  v_tor  uuid;
  v_edm  uuid;
  v_acct public.ref_account%rowtype;
  seed   record;
begin
  select w.id into v_tor from public.ref_warehouse w where w.name = 'Asung Trading Inc.';
  select w.id into v_edm from public.ref_warehouse w where w.name = 'Asung - Edmonton';
  if v_tor is null or v_edm is null then
    raise exception 'so_payment_account_default seed: warehouse "Asung Trading Inc." / "Asung - Edmonton" not found in ref_warehouse — nothing was saved';
  end if;
  for seed in
    select * from (values
      ('cheque',         'TOR', 'CAD', '_5_'),          ('cheque',         'EDM', 'CAD', '_5_'),
      ('cheque',         'TOR', 'USD', '_106_'),        ('cheque',         'EDM', 'USD', '_106_'),
      ('credit_card',    'TOR', 'CAD', '_1150040027_'), ('credit_card',    'EDM', 'CAD', '_1150040030_'),
      ('credit_card',    'TOR', 'USD', '_106_'),        ('credit_card',    'EDM', 'USD', '_106_'),
      ('debit_card',     'TOR', 'CAD', '_1150040027_'), ('debit_card',     'EDM', 'CAD', '_1150040030_'),
      ('e_transfer',     'TOR', 'CAD', '_1150040028_'), ('e_transfer',     'EDM', 'CAD', '_1150040028_'),
      ('cash',           'TOR', 'CAD', '_137_'),        ('cash',           'EDM', 'CAD', '_1150040031_'),
      ('cash',           'TOR', 'USD', '_106_'),        ('cash',           'EDM', 'USD', '_106_'),
      ('wire',           'TOR', 'USD', '_106_'),        ('wire',           'EDM', 'USD', '_106_'),
      ('direct_deposit', 'TOR', 'USD', '_106_'),        ('direct_deposit', 'EDM', 'USD', '_106_'),
      ('shopify',        'TOR', 'CAD', '_104_'),        ('shopify',        'EDM', 'CAD', '_104_')
    ) as v(method, branch, currency_code, account_code)
  loop
    select * into v_acct from public.ref_account a where a.code = seed.account_code;
    if v_acct.id is null then
      raise exception 'so_payment_account_default seed: account % not found in ref_account — nothing was saved', seed.account_code;
    end if;
    if not (v_acct.is_active and (v_acct.account_type = 'BANK' or v_acct.code = '_5_')) then
      raise exception 'so_payment_account_default seed: account % (%) is not an active BANK account (type % · active %) — nothing was saved', v_acct.code, v_acct.name, v_acct.account_type, v_acct.is_active;
    end if;
    insert into public.so_payment_account_default (method, warehouse_id, currency_code, account_id, account_code)
    values (seed.method, case seed.branch when 'TOR' then v_tor else v_edm end, seed.currency_code, v_acct.id, v_acct.code)
    on conflict (method, warehouse_id, currency_code) do nothing;
  end loop;
end $$;

-- ═══ ⑤ 트리거 · RLS · 권한 — 거래 표 셋은 select 만(so_invoice 와 같다) · 기본값 표는 마스터 쓰기(ref_region_alias 와 같다) ═══
create trigger so_payment_touch                 before update on public.so_payment                 for each row execute function public.ims_touch();
create trigger so_payment_alloc_touch           before update on public.so_payment_alloc           for each row execute function public.ims_touch();
create trigger so_payment_account_default_touch before update on public.so_payment_account_default for each row execute function public.ims_touch();

alter table public.so_payment                 enable row level security;
alter table public.so_payment_alloc           enable row level security;
alter table public.so_payment_order           enable row level security;
alter table public.so_payment_account_default enable row level security;
create policy so_payment_select       on public.so_payment       for select to authenticated using (true);
create policy so_payment_alloc_select on public.so_payment_alloc for select to authenticated using (true);
create policy so_payment_order_select on public.so_payment_order for select to authenticated using (true);
revoke all on public.so_payment       from public, anon, authenticated;
revoke all on public.so_payment_alloc from public, anon, authenticated;
revoke all on public.so_payment_order from public, anon, authenticated;
grant select on public.so_payment       to authenticated;
grant select on public.so_payment_alloc to authenticated;
grant select on public.so_payment_order to authenticated;
create policy so_payment_account_default_select on public.so_payment_account_default for select to authenticated using (true);
create policy so_payment_account_default_insert on public.so_payment_account_default for insert to authenticated with check ((select public.ims_can_write('master')));
create policy so_payment_account_default_update on public.so_payment_account_default for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy so_payment_account_default_delete on public.so_payment_account_default for delete to authenticated using ((select public.ims_can_write('master')));
revoke all on public.so_payment_account_default from anon;
revoke truncate on public.so_payment_account_default from authenticated;

-- ═══ ⑥ 읽기 넷(invoker · stable · authenticated) ═══
-- 6-a so_invoice_remaining — 인보이스 남은 금액 = total − Σ활성 alloc(활성 결제만) · 이 식은 여기 하나(0-5 · amount_due 는 종이에 찍힌 값) · 취소된 인보이스는 0
create function public.so_invoice_remaining(p_invoice_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when i.status = 'cancelled' then 0
              else i.total - coalesce((select sum(a.amount) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                                        where a.invoice_id = i.id and a.voided_at is null and p.status = 'active'), 0) end
  from public.so_invoice i where i.id = p_invoice_id;
$$;
comment on function public.so_invoice_remaining(uuid) is '⭐ 인보이스 남은 금액 — total − Σ활성 alloc(활성 결제만) · ⓑ1 · 0-5 「식은 한 곳」(amount_due − Σ 가 아니다 — 발행 때 자동으로 붙은 것이 amount_due 에도 alloc 에도 있어 두 번 빼게 된다) · 취소된 인보이스는 0 · 없는 id 는 null';
revoke all on function public.so_invoice_remaining(uuid) from public, anon;
grant execute on function public.so_invoice_remaining(uuid) to authenticated;

-- 6-b so_customer_balance — ⭐⭐ 손님 잔액 식의 정본(8-e · 통화별 한 행) · 화면·창구·발행이 이 함수만 부른다
--   received         = Σ활성 payment 의 남은 금액(amount − Σ활성 alloc) − Σ활성 refund          ← 8-e 「받아 둔 돈」
--   reserved_deposit = 그중 예약된 선결제(0-7 · 대상 오더 하나라도 열려 있고 살아 있는 인보이스 없음)의 남은 금액 Σ
--   owed_credit      = 0(ⓒ 전 · so_credit_alloc 이 서면 ⓒ 가 재발행해 Σcredit − Σcredit_applied 를 넣는다 — 없는 표를 참조하는 코드는 쓰지 않는다)
--   available        = greatest(received + owed_credit − reserved_deposit, 0)                     ← ⓑ2 자동 잔액 붙이기가 쓰는 값
--   open_invoices · open_invoices_due = 미수 인보이스 수 · Σ남은 금액(issued · 남은 금액 > 0)
create function public.so_customer_balance(p_customer_id uuid)
  returns table (currency_id uuid, currency_code text, received numeric, reserved_deposit numeric, owed_credit numeric, available numeric, open_invoices int, open_invoices_due numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with cur as (
    select p.currency_id from public.so_payment p where p.customer_id = p_customer_id
    union
    select i.currency_id from public.so_invoice i where i.bill_to_customer_id = p_customer_id
  ),
  pay as (
    select p.id, p.currency_id, p.kind, p.amount,
           p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null), 0) as remaining,
           exists (select 1 from public.so_payment_order o join public.so s on s.id = o.so_id
                    where o.payment_id = p.id and s.status not in ('fulfilled', 'cancelled')
                      and not exists (select 1 from public.so_invoice_order io where io.active_so_id = s.id)) as reserved
      from public.so_payment p
     where p.customer_id = p_customer_id and p.status = 'active'
  ),
  inv as (
    select i.currency_id, count(*) as n, sum(public.so_invoice_remaining(i.id)) as due
      from public.so_invoice i
     where i.bill_to_customer_id = p_customer_id and i.status = 'issued' and public.so_invoice_remaining(i.id) > 0
     group by i.currency_id
  ),
  agg as (
    select c.currency_id,
           coalesce(sum(case when y.kind = 'payment' then y.remaining end), 0) - coalesce(sum(case when y.kind = 'refund' then y.amount end), 0) as received,
           coalesce(sum(case when y.kind = 'payment' and y.reserved then y.remaining end), 0) as reserved_deposit
      from cur c left join pay y on y.currency_id = c.currency_id
     group by c.currency_id
  )
  select a.currency_id, rc.code, a.received, a.reserved_deposit, 0::numeric as owed_credit,
         greatest(a.received + 0 - a.reserved_deposit, 0) as available,
         coalesce(v.n, 0)::int as open_invoices, coalesce(v.due, 0) as open_invoices_due
    from agg a
    join public.ref_currency rc on rc.id = a.currency_id
    left join inv v on v.currency_id = a.currency_id
   order by rc.code;
$$;
comment on function public.so_customer_balance(uuid) is '⭐⭐ 손님 잔액 식의 정본(8-e · ⓑ1) — 통화별 한 행(환율 없음 · 판정 ⬜10) · received = Σ활성 payment 남은 금액 − Σ활성 refund(받아 둔 돈) · reserved_deposit = 예약된 선결제(0-7) · owed_credit = 0(ⓒ 가 재발행) · available = greatest(received + owed_credit − reserved_deposit, 0)(ⓑ2 자동 잔액 붙이기의 한도) · open_invoices/_due = 미수 인보이스 · ⚠️ 화면·다른 함수가 이 식을 다시 짜지 않는다 · 별도 잔액 표 없음 · 결제도 인보이스도 없는 손님은 0행';
revoke all on function public.so_customer_balance(uuid) from public, anon;
grant execute on function public.so_customer_balance(uuid) to authenticated;

-- 6-c so_payment_default_account — (방법, 창고, 통화) → 계좌 id · 없으면 null(화면이 미리 채운다)
create function public.so_payment_default_account(p_method text, p_warehouse_id uuid, p_currency_id uuid) returns uuid
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select d.account_id
    from public.so_payment_account_default d
    join public.ref_currency c on c.code = d.currency_code
   where d.method = p_method and d.warehouse_id = p_warehouse_id and c.id = p_currency_id;
$$;
comment on function public.so_payment_default_account(text, uuid, uuid) is '결제 계좌 기본값 조회(판정 2 · ⓑ1) — so_payment_account_default (method, warehouse_id, currency_code) · 없으면 null(= 기본값 없음 · 창구는 계좌를 요구) · 화면이 미리 채우는 용도';
revoke all on function public.so_payment_default_account(text, uuid, uuid) from public, anon;
grant execute on function public.so_payment_default_account(text, uuid, uuid) to authenticated;

-- 6-d so_payment_propose — 붙이기 제안(8-d 「오래된 것부터 제안하되 사람이 바꾼다」) · 읽기만 · 아무것도 안 쓴다
create function public.so_payment_propose(p_customer_id uuid, p_amount numeric, p_currency_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_left numeric := p_amount;
  v_rows jsonb := '[]'::jsonb;
  v_take numeric;
  v_rem  numeric;
  inv    record;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if p_currency_id is null then raise exception 'Currency is required'; end if;
  for inv in
    select i.id, i.invoice_number, i.issued_on, i.due_on, i.total
      from public.so_invoice i
     where i.bill_to_customer_id = p_customer_id and i.currency_id = p_currency_id and i.status = 'issued'
     order by i.due_on nulls last, i.issued_on, i.invoice_number
  loop
    v_rem := public.so_invoice_remaining(inv.id);
    if v_rem <= 0 then continue; end if;
    v_take := case when v_left > 0 then least(v_rem, v_left) else 0 end;
    v_rows := v_rows || jsonb_build_object('invoice_id', inv.id, 'invoice_number', inv.invoice_number, 'issued_on', inv.issued_on, 'due_on', inv.due_on, 'total', inv.total, 'remaining', v_rem, 'suggested', v_take);
    v_left := v_left - v_take;
  end loop;
  return jsonb_build_object('customer_id', p_customer_id, 'currency_id', p_currency_id, 'amount', p_amount, 'proposed', v_rows, 'allocated', p_amount - v_left, 'leftover', v_left);
end;
$$;
comment on function public.so_payment_propose(uuid, numeric, uuid) is '붙이기 제안(8-d · ⓑ1) — 그 손님(청구처)·그 통화의 미수 인보이스를 기한(due_on · null 은 뒤) → 발행일 → 번호 순으로 채워 나간 제안 [{invoice_id, invoice_number, issued_on, due_on, total, remaining, suggested}](미수 전부 · 금액이 닿지 않는 것은 suggested 0) · allocated · leftover(= 붙지 않고 잔액으로 남을 돈) · ⚠️ 읽기만 — 사람이 바꿔 so_payment_add/attach 에 넘긴다 · 자동으로 다 붙이지 않는다(8-d Caleb)';
revoke all on function public.so_payment_propose(uuid, numeric, uuid) from public, anon;
grant execute on function public.so_payment_propose(uuid, numeric, uuid) to authenticated;

-- ═══ ⑦ 속 함수 둘(invoker · authenticated 없음 · 창구가 부른다) ═══
-- 7-a so_payment_resolve_account — 계좌 정하기: 지정 → 없으면 기본값 → 없으면 거부 · 후보 조건(활성 BANK 또는 _5_) 아니면 거부
create function public.so_payment_resolve_account(p_method text, p_warehouse_id uuid, p_currency_id uuid, p_account_id uuid) returns public.ref_account
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_id   uuid;
  v_acct public.ref_account%rowtype;
begin
  v_id := coalesce(p_account_id, public.so_payment_default_account(p_method, p_warehouse_id, p_currency_id));
  if v_id is null then
    raise exception 'No default account for % at % in % — pick an account — nothing was saved',
      p_method, (select w.name from public.ref_warehouse w where w.id = p_warehouse_id), (select c.code from public.ref_currency c where c.id = p_currency_id);
  end if;
  select * into v_acct from public.ref_account a where a.id = v_id;
  if v_acct.id is null then raise exception 'Account not found — nothing was saved'; end if;
  if not (v_acct.is_active and (v_acct.account_type = 'BANK' or v_acct.code = '_5_')) then
    raise exception 'Account % (%) cannot receive payments — only active BANK accounts or _5_ Undeposited Funds — nothing was saved', v_acct.code, v_acct.name;
  end if;
  return v_acct;
end;
$$;
comment on function public.so_payment_resolve_account(text, uuid, uuid, uuid) is 'SO 결제 속 함수(ⓑ1) — 계좌 정하기: p_account_id 지정 → 없으면 so_payment_default_account → 없으면 거부(「No default account … pick an account」 · 0-9) · 후보 조건 is_active and (account_type = BANK or code = _5_)(§3 ① 실측 · for_payments 못 씀) 아니면 거부 · 환불은 기본값 없이 지정만(so_payment_refund)';
revoke all on function public.so_payment_resolve_account(text, uuid, uuid, uuid) from public, anon, authenticated;

-- 7-b so_payment_alloc_add — 붙이기 한 줄(한도 셋 · 0-6) · source 인자(manual 은 창구 · auto_* 는 ⓑ2 발행이) · 잠금은 결제 → 인보이스 순
create function public.so_payment_alloc_add(p_payment_id uuid, p_invoice_id uuid, p_amount numeric, p_source text, p_staff uuid) returns public.so_payment_alloc
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_p       public.so_payment%rowtype;
  v_i       public.so_invoice%rowtype;
  v_inv_rem numeric;
  v_pay_rem numeric;
  v_recv    numeric;
  v_row     public.so_payment_alloc%rowtype;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'Allocation amount must be positive — nothing was saved'; end if;
  if p_amount <> round(p_amount, 2) then raise exception 'Amounts have at most two decimals (got %) — nothing was saved', p_amount; end if;
  if p_source not in ('manual', 'auto_deposit', 'auto_balance') then raise exception 'Unknown allocation source % — nothing was saved', p_source; end if;
  select * into v_p from public.so_payment p where p.id = p_payment_id for update;
  if not found then raise exception 'Payment not found — nothing was saved'; end if;
  if v_p.status <> 'active' then raise exception 'Payment is voided — nothing was saved'; end if;
  if v_p.kind <> 'payment' then raise exception 'A refund cannot be applied to an invoice — nothing was saved'; end if;
  select * into v_i from public.so_invoice i where i.id = p_invoice_id for update;
  if not found then raise exception 'Invoice not found — nothing was saved'; end if;
  if v_i.status <> 'issued' then raise exception 'Invoice % is % — nothing was saved', v_i.invoice_number, v_i.status; end if;
  if v_i.bill_to_customer_id <> v_p.customer_id then raise exception 'Invoice % bills a different customer than this payment — nothing was saved', v_i.invoice_number; end if;
  if v_i.currency_id <> v_p.currency_id then
    raise exception 'Invoice % is in % but the payment is in % — same currency only (no exchange) — nothing was saved', v_i.invoice_number, v_i.currency_code, v_p.currency_code;
  end if;
  if exists (select 1 from public.so_payment_alloc a where a.payment_id = v_p.id and a.active_invoice_id = v_i.id) then
    raise exception 'This payment is already applied to invoice % — detach that first — nothing was saved', v_i.invoice_number;
  end if;
  v_inv_rem := public.so_invoice_remaining(v_i.id);
  if p_amount > v_inv_rem then raise exception 'Invoice % has only % left to pay (asked %) — nothing was saved', v_i.invoice_number, v_inv_rem, p_amount; end if;
  v_pay_rem := v_p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null), 0);
  if p_amount > v_pay_rem then raise exception 'Payment has only % left to apply (asked %) — nothing was saved', v_pay_rem, p_amount; end if;
  select b.received into v_recv from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id;
  if p_amount > coalesce(v_recv, 0) then
    raise exception 'Customer has only % % on account after refunds (asked %) — nothing was saved', coalesce(v_recv, 0), v_p.currency_code, p_amount;
  end if;
  insert into public.so_payment_alloc (payment_id, invoice_id, amount, source, created_by, updated_by)
  values (v_p.id, v_i.id, p_amount, p_source, p_staff, p_staff)
  returning * into v_row;
  return v_row;
end;
$$;
comment on function public.so_payment_alloc_add(uuid, uuid, numeric, text, uuid) is '⭐ SO 붙이기 한 줄(속 함수 · ⓑ1 · 0-6) — 결제 활성·kind payment · 인보이스 issued · 같은 청구처 · 같은 통화 · 활성 짝 없음 · 한도 셋 = 인보이스 남은 금액 · 결제 남은 금액 · 그 통화의 받아 둔 돈(received · 환불이 집계라 이것이 바닥) 아니면 거부 · source manual(창구) | auto_deposit | auto_balance(ⓑ2 발행 · auto_balance 는 부르는 쪽이 available 이하로 정한다) · 권한은 부르는 창구가 봤다';
revoke all on function public.so_payment_alloc_add(uuid, uuid, numeric, text, uuid) from public, anon, authenticated;

-- ═══ ⑧ 창구 다섯(definer · 첫 줄 ims_require_write(sales) · manager 는 둘째 줄 so_require_role(manager) · 손님 행 잠금으로 잔액 검사를 직렬화) ═══
-- 8-a so_payment_add — 넣기(sales) · 붙이기·대상 오더를 함께 받을 수 있다
--   p: {customer_id, amount, paid_on?, method, reference?, currency_id? | currency_code?, account_id?, warehouse_id?, note?, allocations?: [{invoice_id, amount}], target_so_ids?: [uuid]}
create function public.so_payment_add(p jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_c        public.customer%rowtype;
  v_cur      public.ref_currency%rowtype;
  v_w        public.ref_warehouse%rowtype;
  v_acct     public.ref_account%rowtype;
  v_p        public.so_payment%rowtype;
  v_a        public.so_payment_alloc%rowtype;
  v_s        public.so%rowtype;
  v_amount   numeric;
  v_on       date;
  v_method   text;
  v_wh       uuid;
  v_targets  uuid[];
  v_target_rows jsonb := '[]'::jsonb;
  v_allocs   jsonb := '[]'::jsonb;
  v_alloc_sum numeric := 0;
  v_first_loc uuid;
  v_bad      text;
  t_id       uuid;
  x          jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄(판정 6 · sales 열쇠)
  v_staff := public.so_current_staff();

  if nullif(p->>'customer_id', '') is null then raise exception 'customer_id is required — nothing was saved'; end if;
  select * into v_c from public.customer c where c.id = (p->>'customer_id')::uuid for update;   -- 손님 행 잠금(잔액 검사 직렬화)
  if not found then raise exception 'Customer not found — nothing was saved'; end if;

  v_amount := (p->>'amount')::numeric;
  if v_amount is null or v_amount <= 0 then raise exception 'Amount must be positive — nothing was saved'; end if;
  if v_amount <> round(v_amount, 2) then raise exception 'Amounts have at most two decimals (got %) — nothing was saved', v_amount; end if;
  v_on := coalesce((p->>'paid_on')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Payment date % is in the future — nothing was saved', v_on; end if;
  v_method := nullif(trim(p->>'method'), '');
  if v_method is null or v_method not in ('cheque','credit_card','debit_card','e_transfer','wire','cash','direct_deposit','shopify') then
    raise exception 'Unknown payment method % — use one of cheque, credit_card, debit_card, e_transfer, wire, cash, direct_deposit, shopify — nothing was saved', coalesce(v_method, '(none)');
  end if;

  -- 통화: 지정(id 또는 code) → 손님 통화 → 없으면 거부
  select * into v_cur from public.ref_currency c
   where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), v_c.currency_id);
  if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;

  -- 선결제 대상 오더(판정 4): 같은 손님(청구처 또는 오더 손님) · 끝 상태 아님 · 살아 있는 인보이스 없음
  select array_agg(distinct t.v::uuid) into v_targets from jsonb_array_elements_text(coalesce(nullif(p->'target_so_ids', 'null'::jsonb), '[]'::jsonb)) as t(v);
  if v_targets is not null then
    foreach t_id in array v_targets loop
      select * into v_s from public.so s where s.id = t_id;
      if not found then raise exception 'Target order not found — nothing was saved'; end if;
      if coalesce(v_s.bill_to_customer_id, v_s.customer_id) <> v_c.id then raise exception 'Order % belongs to a different customer — nothing was saved', v_s.so_number; end if;
      if v_s.status in ('fulfilled', 'cancelled') then raise exception 'Order % is % — a deposit can only target an open order — nothing was saved', v_s.so_number, v_s.status; end if;
      select i.invoice_number into v_bad from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.active_so_id = v_s.id;
      if v_bad is not null then raise exception 'Order % is already on invoice % — apply the payment to the invoice instead — nothing was saved', v_s.so_number, v_bad; end if;
    end loop;
    select s.location_id into v_first_loc from public.so s where s.id = any(v_targets) order by s.so_number limit 1;
  end if;

  -- 브랜치(창고): 지정 → 첫 대상 오더의 창고 → 손님 기본 창고 → 거부
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_first_loc, v_c.default_location_id);
  if v_wh is null then raise exception 'Branch (warehouse_id) is required — the customer has no default warehouse — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;

  -- 계좌: 지정 → 기본값 → 거부 · 후보 조건
  v_acct := public.so_payment_resolve_account(v_method, v_w.id, v_cur.id, nullif(p->>'account_id', '')::uuid);

  -- 붙이기 합 ≤ 결제 금액
  select coalesce(sum((t->>'amount')::numeric), 0) into v_alloc_sum from jsonb_array_elements(coalesce(nullif(p->'allocations', 'null'::jsonb), '[]'::jsonb)) t;
  if v_alloc_sum > v_amount then raise exception 'Allocations % exceed the payment amount % — nothing was saved', v_alloc_sum, v_amount; end if;

  insert into public.so_payment (kind, amount, paid_on, method, reference, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, note, created_by, updated_by)
  values ('payment', v_amount, v_on, v_method, nullif(trim(p->>'reference'), ''), v_c.id, v_cur.id, v_cur.code, v_acct.id, v_acct.code, v_w.id, v_w.name, nullif(trim(p->>'note'), ''), v_staff, v_staff)
  returning * into v_p;

  if v_targets is not null then
    foreach t_id in array v_targets loop
      insert into public.so_payment_order (payment_id, so_id, created_by) values (v_p.id, t_id, v_staff);
      select v_target_rows || jsonb_build_object('so_id', s.id, 'so_number', s.so_number, 'status', s.status) into v_target_rows from public.so s where s.id = t_id;
    end loop;
  end if;

  for x in select t from jsonb_array_elements(coalesce(nullif(p->'allocations', 'null'::jsonb), '[]'::jsonb)) t loop
    v_a := public.so_payment_alloc_add(v_p.id, nullif(x->>'invoice_id', '')::uuid, (x->>'amount')::numeric, 'manual', v_staff);
    v_allocs := v_allocs || jsonb_build_object('alloc_id', v_a.id, 'invoice_id', v_a.invoice_id,
                                               'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_a.invoice_id),
                                               'amount', v_a.amount, 'invoice_remaining', public.so_invoice_remaining(v_a.invoice_id));
  end loop;

  return jsonb_build_object('payment_id', v_p.id, 'kind', v_p.kind, 'amount', v_p.amount, 'paid_on', v_p.paid_on, 'method', v_p.method, 'reference', v_p.reference,
                            'customer_id', v_p.customer_id, 'currency_code', v_p.currency_code, 'account_id', v_p.account_id, 'account_code', v_p.account_code, 'account_name', v_acct.name,
                            'warehouse_id', v_p.warehouse_id, 'warehouse_name', v_p.warehouse_name, 'status', v_p.status,
                            'allocations', v_allocs, 'allocated', v_alloc_sum, 'remaining', v_p.amount - v_alloc_sum, 'targets', v_target_rows,
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_c.id) b where b.currency_id = v_cur.id));
end;
$$;
comment on function public.so_payment_add(jsonb) is '⭐⭐ 결제 넣기(8-d · 판정 2·4·6 · ⓑ1) — definer · 첫 줄 ims_require_write(sales) · p {customer_id, amount, paid_on?(오늘 · 미래 거부), method(여덟), reference?, currency_id?|currency_code?(기본 손님 통화), account_id?(기본 so_payment_account_default · 없으면 거부 · 활성 BANK/_5_ 만), warehouse_id?(기본 첫 대상 오더 창고 → 손님 기본 창고 → 거부), note?, allocations? [{invoice_id, amount}](so_payment_alloc_add · 한도 셋 · Σ ≤ amount), target_so_ids?(같은 손님 · 열린 오더 · 살아 있는 인보이스 없음)} · kind 는 payment 고정(환불은 so_payment_refund) · 반환 결제 · allocations · remaining · targets · balance(그 통화 행)';
revoke all on function public.so_payment_add(jsonb) from public, anon;
grant execute on function public.so_payment_add(jsonb) to authenticated;

-- 8-b so_payment_attach — 붙이기(sales · 제안 그대로든 바꿔서든 사람이 정한 것)
create function public.so_payment_attach(p_payment_id uuid, p_allocs jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_p      public.so_payment%rowtype;
  v_a      public.so_payment_alloc%rowtype;
  v_allocs jsonb := '[]'::jsonb;
  v_sum    numeric := 0;
  x        jsonb;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if not found then raise exception 'Payment not found — nothing was saved'; end if;
  perform 1 from public.customer c where c.id = v_p.customer_id for update;   -- 손님 행 잠금
  if jsonb_typeof(p_allocs) is distinct from 'array' or jsonb_array_length(p_allocs) = 0 then raise exception 'Nothing to apply — pass [{invoice_id, amount}] — nothing was saved'; end if;
  for x in select t from jsonb_array_elements(p_allocs) t loop
    v_a := public.so_payment_alloc_add(v_p.id, nullif(x->>'invoice_id', '')::uuid, (x->>'amount')::numeric, 'manual', v_staff);
    v_sum := v_sum + v_a.amount;
    v_allocs := v_allocs || jsonb_build_object('alloc_id', v_a.id, 'invoice_id', v_a.invoice_id,
                                               'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_a.invoice_id),
                                               'amount', v_a.amount, 'invoice_remaining', public.so_invoice_remaining(v_a.invoice_id));
  end loop;
  return jsonb_build_object('payment_id', v_p.id, 'applied', v_sum, 'allocations', v_allocs,
                            'payment_remaining', v_p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null), 0),
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id));
end;
$$;
comment on function public.so_payment_attach(uuid, jsonb) is '⭐ 붙이기(8-d · 판정 6 · ⓑ1) — definer · 첫 줄 ims_require_write(sales) · [{invoice_id, amount}] 를 so_payment_alloc_add(manual · 한도 셋) 로 · 하나라도 막히면 전체 거부 · 반환 applied · allocations · payment_remaining · balance';
revoke all on function public.so_payment_attach(uuid, jsonb) from public, anon;
grant execute on function public.so_payment_attach(uuid, jsonb) to authenticated;

-- 8-c so_payment_detach — 떼기(manager · void · 흔적)
create function public.so_payment_detach(p_alloc_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_a     public.so_payment_alloc%rowtype;
  v_p     public.so_payment%rowtype;
  v_note  text;
  v_n     int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 6)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'Detaching needs a reason (p_note) — nothing was saved'; end if;
  select * into v_a from public.so_payment_alloc a where a.id = p_alloc_id for update;
  if not found then raise exception 'Allocation not found — nothing was saved'; end if;
  if v_a.voided_at is not null then raise exception 'This allocation was already detached — nothing was saved'; end if;
  select * into v_p from public.so_payment p where p.id = v_a.payment_id;
  perform 1 from public.customer c where c.id = v_p.customer_id for update;   -- 손님 행 잠금
  update public.so_payment_alloc set voided_at = now(), voided_by = v_staff, void_note = v_note, updated_by = v_staff where id = v_a.id and voided_at is null;
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Allocation was not detached — it may have been changed by someone else just now — nothing was saved'; end if;
  return jsonb_build_object('alloc_id', v_a.id, 'payment_id', v_a.payment_id, 'invoice_id', v_a.invoice_id, 'amount', v_a.amount, 'source', v_a.source, 'note', v_note,
                            'invoice_remaining', public.so_invoice_remaining(v_a.invoice_id),
                            'payment_remaining', v_p.amount - coalesce((select sum(a.amount) from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null), 0),
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id));
end;
$$;
comment on function public.so_payment_detach(uuid, text) is '⭐ 떼기(판정 6 manager · ⓑ1) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · 사유 필수 · 행은 지우지 않고 void(voided_at/by/note · active_invoice_id 가 비어 다시 붙일 수 있다) · 돈은 결제의 남은 금액 → 받아 둔 돈으로 돌아간다(반환 balance 로 보인다)';
revoke all on function public.so_payment_detach(uuid, text) from public, anon;
grant execute on function public.so_payment_detach(uuid, text) to authenticated;

-- 8-d so_payment_void — 결제·환불 취소(manager · 붙은 것이 있으면 먼저 떼라 · 취소 뒤 잔액이 음수면 거부)
create function public.so_payment_void(p_payment_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_p     public.so_payment%rowtype;
  v_note  text;
  v_n     int;
  v_rem   numeric;
  v_recv  numeric;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 6)
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'Voiding needs a reason (p_note) — nothing was saved'; end if;
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if not found then raise exception 'Payment not found — nothing was saved'; end if;
  perform 1 from public.customer c where c.id = v_p.customer_id for update;   -- 손님 행 잠금
  select * into v_p from public.so_payment p where p.id = p_payment_id for update;
  if v_p.status <> 'active' then raise exception 'Payment is already voided — nothing was saved'; end if;
  select count(*) into v_n from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null;
  if v_n > 0 then raise exception 'Payment has % allocation(s) applied to invoices — detach them first — nothing was saved', v_n; end if;
  if v_p.kind = 'payment' then
    v_rem := v_p.amount;   -- 활성 alloc 0 이므로 남은 금액 = amount
    select b.received into v_recv from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id;
    if coalesce(v_recv, 0) - v_rem < 0 then
      raise exception 'Voiding this payment would put the customer''s % balance below zero (% on account, refunds already paid out) — nothing was saved', v_p.currency_code, coalesce(v_recv, 0);
    end if;
  end if;
  update public.so_payment set status = 'voided', voided_at = now(), voided_by = v_staff, void_note = v_note, updated_by = v_staff where id = v_p.id and status = 'active';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Payment was not voided — it may have been changed by someone else just now — nothing was saved'; end if;
  return jsonb_build_object('payment_id', v_p.id, 'kind', v_p.kind, 'amount', v_p.amount, 'status', 'voided', 'note', v_note,
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_p.customer_id) b where b.currency_id = v_p.currency_id));
end;
$$;
comment on function public.so_payment_void(uuid, text) is '⭐ 결제·환불 취소(판정 6 manager · ⓑ1 · 0-6) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · 사유 필수 · 활성 alloc 이 있으면 「먼저 떼라」 거부 · payment 는 취소 뒤 그 통화의 받아 둔 돈이 음수가 되면 거부(환불이 이미 나갔다) · refund 취소는 잔액이 늘 뿐이라 늘 된다 · 대상 오더 표시(so_payment_order)는 그대로(돈이 아니다 · 취소된 결제는 잔액 함수가 세지 않는다) · 삭제 없음';
revoke all on function public.so_payment_void(uuid, text) from public, anon;
grant execute on function public.so_payment_void(uuid, text) to authenticated;

-- 8-e so_payment_refund — 환불(manager · kind refund · 그 통화의 받아 둔 돈을 넘지 못한다 · 계좌 지정 필수)
--   p: {customer_id, amount, paid_on?, method, reference?, currency_id? | currency_code?, account_id(필수), warehouse_id?, note?}
create function public.so_payment_refund(p jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_c      public.customer%rowtype;
  v_cur    public.ref_currency%rowtype;
  v_w      public.ref_warehouse%rowtype;
  v_acct   public.ref_account%rowtype;
  v_p      public.so_payment%rowtype;
  v_amount numeric;
  v_on     date;
  v_method text;
  v_wh     uuid;
  v_recv   numeric;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄(판정 6)
  v_staff := public.so_current_staff();

  if nullif(p->>'customer_id', '') is null then raise exception 'customer_id is required — nothing was saved'; end if;
  select * into v_c from public.customer c where c.id = (p->>'customer_id')::uuid for update;   -- 손님 행 잠금
  if not found then raise exception 'Customer not found — nothing was saved'; end if;
  v_amount := (p->>'amount')::numeric;
  if v_amount is null or v_amount <= 0 then raise exception 'Amount must be positive — nothing was saved'; end if;
  if v_amount <> round(v_amount, 2) then raise exception 'Amounts have at most two decimals (got %) — nothing was saved', v_amount; end if;
  v_on := coalesce((p->>'paid_on')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Refund date % is in the future — nothing was saved', v_on; end if;
  v_method := nullif(trim(p->>'method'), '');
  if v_method is null or v_method not in ('cheque','credit_card','debit_card','e_transfer','wire','cash','direct_deposit','shopify') then
    raise exception 'Unknown payment method % — use one of cheque, credit_card, debit_card, e_transfer, wire, cash, direct_deposit, shopify — nothing was saved', coalesce(v_method, '(none)');
  end if;
  select * into v_cur from public.ref_currency c
   where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), v_c.currency_id);
  if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_c.default_location_id);
  if v_wh is null then raise exception 'Branch (warehouse_id) is required — the customer has no default warehouse — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;
  if nullif(p->>'account_id', '') is null then raise exception 'A refund needs an account (account_id) — there is no default for money going out — nothing was saved'; end if;
  v_acct := public.so_payment_resolve_account(v_method, v_w.id, v_cur.id, (p->>'account_id')::uuid);

  select b.received into v_recv from public.so_customer_balance(v_c.id) b where b.currency_id = v_cur.id;
  if v_amount > coalesce(v_recv, 0) then
    raise exception 'Customer has only % % on account — a refund cannot exceed it (asked %) — nothing was saved', coalesce(v_recv, 0), v_cur.code, v_amount;
  end if;

  insert into public.so_payment (kind, amount, paid_on, method, reference, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, note, created_by, updated_by)
  values ('refund', v_amount, v_on, v_method, nullif(trim(p->>'reference'), ''), v_c.id, v_cur.id, v_cur.code, v_acct.id, v_acct.code, v_w.id, v_w.name, nullif(trim(p->>'note'), ''), v_staff, v_staff)
  returning * into v_p;

  return jsonb_build_object('payment_id', v_p.id, 'kind', v_p.kind, 'amount', v_p.amount, 'paid_on', v_p.paid_on, 'method', v_p.method, 'reference', v_p.reference,
                            'customer_id', v_p.customer_id, 'currency_code', v_p.currency_code, 'account_id', v_p.account_id, 'account_code', v_p.account_code, 'account_name', v_acct.name,
                            'warehouse_id', v_p.warehouse_id, 'warehouse_name', v_p.warehouse_name, 'status', v_p.status,
                            'balance', (select to_jsonb(b) from public.so_customer_balance(v_c.id) b where b.currency_id = v_cur.id));
end;
$$;
comment on function public.so_payment_refund(jsonb) is '⭐ 환불(8-e·8-g 「환불은 잔액을 넘지 못한다」 · 판정 6 manager · ⓑ1) — definer · 첫 줄 ims_require_write(sales) · 둘째 줄 so_require_role(manager) · p {customer_id, amount, paid_on?, method, reference?, currency_id?|currency_code?, account_id(⚠️ 필수 · 나가는 돈에 기본값 없음 · 후보 조건은 같다), warehouse_id?(기본 손님 창고), note?} · 한도 = 그 통화의 받아 둔 돈(received · 예약된 선결제 포함 — 취소된 오더의 선금 돌려주기가 이 경우) · kind refund 한 줄 · 어느 결제에도 매이지 않는다(8-e 집계) · ⓒ 크레딧 환불(진 빚)은 ⓒ 가 한도에 owed_credit 을 더한다';
revoke all on function public.so_payment_refund(jsonb) from public, anon;
grant execute on function public.so_payment_refund(jsonb) to authenticated;

-- ═══ 검증(~/asung/prompts/so-payment-1a-verify.sql · psql -v ON_ERROR_STOP=1 -f · 전부 rollback · 시퀀스 둘은 rollback 밖 setval) ═══
--   구조 표 넷·함수 열하나(definer 다섯 · 읽기 넷 · 속 둘) · 씨앗 22 · 넣기 여덟 방법 × 기본 계좌(TOR·EDM·USD · 송금 CAD 거부 · 지정 계좌 · _61_ 거부 · 미래·소수 셋째·모르는 방법 거부) ·
--   붙이기 한 결제 → 인보이스 셋 · 한 인보이스 ← 결제 둘 · 오버페이 189 → 188.77 잔액 0.23 · 제안(순서 · 읽기만) · 한도 셋(결제 남은 금액 · 인보이스 남은 금액 · 받아 둔 돈) · 같은 짝 두 번 거부 ·
--   떼기 manager(void · 다시 붙임) · 취소(붙어 있으면 거부 → 떼고 → 취소 · 음수 잔액 거부 · 두 번 거부) · 환불(한도 · 계좌 필수) · 선결제 대상(같은 손님·열린 오더·살아 있는 인보이스 · 예약 → 오더 닫히면 풀림 · 창고 기본값 순서) ·
--   통화(USD 결제 → CAD 인보이스 거부 · 통화별 행) · 권한(worker 무열쇠 거부 · supervisor 통과 · worker+sales 는 manager 셋 거부) · CHECK 하나씩 constraint_name · 흔적 0 · 25000 f · 60000 f
