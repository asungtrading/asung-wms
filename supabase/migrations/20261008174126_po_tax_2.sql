do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;
-- 20261008174126_po_tax_2.sql — po-tax-2 (2026-10-08 · 회사 PC) · PO 매입 세금 ② 비용 청구서 세금 칸 · 트랜스퍼 운임 · 비용 결제 갈래
--   Caleb 결정(2026-10-08 · 판정 번호는 다음 문서 차수): ① 매입 세금은 상품 원가에 넣지 않는다 — landed 는 세금 전 · 낼 돈 = 세금 전 + 세금
--   ② 비용 청구서(po_charge)는 「세금 전」과 「세금」 두 칸 · 세금은 청구서에 찍힌 값 그대로(수입 GST 는 비율로 못 만든다) · 세율 규칙이 있는 청구처는 제안값(so_tax_amount(total_amount, rate_pct))을 보이고 사람이 맞춘다 · 배분 · landed 는 세금 전만
--   po-tax-0 · 1 에서 받은 것: total_amount 는 칸 그대로 뜻만 「세금 전」(comment) · tax_amount not null default 0 · tax_rule_id + 원문 짝(제안 재료 · 저장된 tax_amount 가 정본) · 짝 트리거 po_tax_rule_pair 를 이 표에도 ·
--      규칙 출처 = 청구처 supplier.tax_rule(못 풀면 null + 경고 · 막지 않는다) · 트랜스퍼 운임도 같은 표 · 세금은 문서 통화 · 계정은 안 쓴다 · 확정 뒤 잠금은 total_amount 와 같은 선(없음) · CHECK(부호) 없음
--   ⭐ 제안값의 모양(지시서 §1-4 · 내 판단 ㉡): 보내지 않으면 0 을 저장하고 제안값은 반환만(tax_suggested) + 경고 tax_amount_not_given — 세금은 「찍힌 값」이지 계산값이 아니다 · 저장 0 은 결제에서 「미지급 초과」로 드러난다(크게 실패) ·
--      ㉠(보내지 않으면 제안값 저장)은 청구처 마스터 규칙이 틀린 경비처(USD · HST PE 2016 · 21 곳)에서 15% 가 조용히 들어가 결제 뒤에야 보인다(조용히 실패) — 기각
--   이 차수 밖: 할인 → 원가 · 화면(대화 Claude · po · invoices · charges · transfers · suppliers · payments)
--   대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/po-tax-2-verify.sql
--
--   ① po_charge 칸 셋(tax_amount · tax_rule_id · tax_rule) · FK 인덱스 · 주석(total_amount 뜻 고침) · 짝 트리거 · backfill(청구처 규칙 이름 → id · 제안 재료만 · tax_amount 는 0 그대로) · 짝 CHECK
--   ② po_charge_money 재발행(unpaid 세금 포함 · 뒤에 여섯 tax_amount · total_with_tax · tax_rule_id · tax_rule · rate_pct · tax_suggested) · po_charge_list(뒤에 넷)
--   ③ 창구 — po_charge_create(인자 둘 더함 → drop + create + 권한 · 규칙 풀기 · 세금 받기 · 제안값 · 경고 둘) · po_charge_confirm · po_charge_detail · tf_charge_create(인자 둘 · drop + create) · tf_charge_update(열쇠 셋) · tf_charge_confirm ·
--      po_payment_target_check · po_payment_detail(비용 doc_total = total_with_tax) · 목록 밖 둘: po_detail(charges[] 에 tax_amount · total_with_tax — 화면이 total_amount 와 unpaid 를 나란히 그린다) · inv_transfer_detail(charges[] 같은 둘)
--      ⚠️ PO 비용 머리 고치기 창구는 없다 — charges.html 이 PostgREST 로 po_charge 를 직접 쓴다(tax_amount 도 같은 길 · tax_rule 은 트리거가 푼다)
--   ④ 실물 확인 do 블록

-- ═══ ① 칸 · 인덱스 · 주석 · 트리거 · backfill · CHECK ═══
alter table public.po_charge
  add column if not exists tax_amount  numeric not null default 0,                                              -- ⭐ 청구서에 찍힌 세금(청구 통화) · 저장값이 정본 · 원가에 안 간다
  add column if not exists tax_rule_id uuid references public.ref_tax_rule (id) on delete no action,            -- 제안 재료(청구처 규칙) · 원문 짝
  add column if not exists tax_rule    text;
create index if not exists po_charge_tax_rule_idx on public.po_charge (tax_rule_id);
comment on column public.po_charge.total_amount is '⭐ [po-tax-2 2026-10-08 · 뜻 고침] 청구서 총액의 **세금 전** 금액(청구 통화) · CHECK 없음 — 정정이 음수로 올 수 있다(inv_doc_cost.amount 주석 선례) · 배분(po_charge_alloc 합 = 이 값 · 세금 전끼리 대조 · 제약으로 막지 않는다 — 입력 중간 상태가 있다) · landed(inv_layer_post_charge 가 배분 줄 × 환율) · unallocated 는 이 값 기준 · 세금은 tax_amount · 낼 돈은 po_charge_money.total_with_tax · unpaid';
comment on column public.po_charge.tax_amount   is 'po-tax-2 ⭐ 청구서에 찍힌 세금(청구 통화 · 환산 없음) · 저장값이 정본(규칙으로 계산하지 않는다 — 수입 GST 는 「물건 값 + 관세」의 5% 라 청구서 금액에서 비율로 못 만든다) · 제안값 = so_tax_amount(total_amount, 청구처 규칙 rate_pct) · 창구가 보내지 않으면 0(경고 tax_amount_not_given) · ⚠️ 원가(landed)에 안 들어간다(결정 ①) · 낼 돈 = total_amount + tax_amount(po_charge_money) · CHECK(부호) 없음(total_amount 와 같은 결) · 확정 뒤 잠금 없음(total_amount 와 같은 선) · 기존 6행 0';
comment on column public.po_charge.tax_rule_id  is 'po-tax-2 — 제안 재료 FK → ref_tax_rule(purchase · 활성) · 원문 tax_rule 과 짝 CHECK po_charge_tax_rule_pair_ck · 트리거 po_charge_tax_rule_pair(po_tax_rule_pair) · 만들 때 청구처 supplier.tax_rule 이름 → id(못 풀면 null + 경고 tax_rule_unknown:<원문>) · 저장된 tax_amount 가 정본이고 이 규칙은 tax_suggested 만 만든다';
comment on column public.po_charge.tax_rule     is 'po-tax-2 — 제안 규칙 이름(원문 · FK 와 짝) · PostgREST 로 이름을 쓰면 트리거가 id 를 푼다';
create trigger po_charge_tax_rule_pair before insert or update of tax_rule_id, tax_rule on public.po_charge for each row execute function public.po_tax_rule_pair();
update public.po_charge c set tax_rule_id = r.id                                                                 -- backfill · 제안 재료(활성 purchase 이름만) · tax_amount 는 0 그대로(기존 6행 · Test1 90 은 뜻을 모른다 — 안 고친다)
from public.supplier s join public.ref_tax_rule r on r.name = s.tax_rule and r.direction = 'purchase' and r.is_active
where s.id = c.supplier_id and c.tax_rule_id is null;
alter table public.po_charge add constraint po_charge_tax_rule_pair_ck check ((tax_rule_id is null) = (tax_rule is null));
comment on constraint po_charge_tax_rule_pair_ck on public.po_charge is 'po-tax-2 — FK 와 원문은 함께 있거나 함께 없다 · 트리거 po_charge_tax_rule_pair 가 채운다';

-- ═══ ② po_charge_money 재발행 — 마지막 정의 20260916190000:187 · unpaid = 세금 전 + 세금 − 충당 · unallocated 는 세금 전끼리 그대로 · 뒤에 여섯 ═══
create or replace view public.po_charge_money
  with (security_invoker = true) as
select c.id, c.status, c.total_amount,
       coalesce(p.paid, 0)                                   as paid,
       c.total_amount + c.tax_amount - coalesce(p.paid, 0)   as unpaid,           -- po-tax-2 · 낼 돈 = 세금 전 + 세금 − 충당(문서 전체 기준)
       coalesce(al.alloc_sum, 0)                             as alloc_sum,        -- 발주들에 박은 배분 합(세금 전)
       c.total_amount - coalesce(al.alloc_sum, 0)            as unallocated,      -- 세금 전끼리 · 0 이 정상
       -- ── po-tax-2 · 뒤에 더한 여섯 ──
       c.tax_amount,                                                              -- 찍힌 세금(정본)
       c.total_amount + c.tax_amount                         as total_with_tax,   -- 낼 돈(문서 통화)
       c.tax_rule_id, c.tax_rule, r.rate_pct,                                     -- 제안 재료
       public.so_tax_amount(c.total_amount, r.rate_pct)      as tax_suggested     -- 제안값(규칙 없으면 null) · 저장값과 다를 수 있다(수입 GST)
from public.po_charge c
left join (select po_charge_id, sum(amount) as paid      from public.po_payment_alloc where po_charge_id is not null group by po_charge_id) p  on p.po_charge_id  = c.id
left join (select po_charge_id, sum(amount) as alloc_sum from public.po_charge_alloc  group by po_charge_id)                                   al on al.po_charge_id = c.id
left join public.ref_tax_rule r on r.id = c.tax_rule_id;
comment on view public.po_charge_money is '⑤ 비용 청구서 한 장의 돈 — paid = 충당 합 · ⭐ [po-tax-2 2026-10-08] unpaid = total_amount(세금 전) + tax_amount − paid(낼 돈은 세금 포함) · alloc_sum = 발주 · 트랜스퍼에 박은 배분 합(세금 전) · unallocated = total_amount − alloc_sum(세금 전끼리 · 0 이 정상) · 뒤에 여섯 tax_amount · total_with_tax · tax_rule_id · tax_rule · rate_pct · tax_suggested(= so_tax_amount(total_amount, rate_pct) · 규칙 없으면 null · 저장값이 정본). po_list · po_detail · po_charge_list · 창구들이 같이 읽는다. security_invoker. 정본 po-module §11-f · §13';


-- ═══ ③-1 po_charge_list 재발행 — 마지막 정의 20260917150000:113(create view · or replace 로) · 뒤에 넷 ═══
create or replace view public.po_charge_list
  with (security_invoker = true) as
with pos as (
  select a.po_charge_id,
         count(*)::int                                                  as po_count,
         string_agg(x.po_number, ' ' order by x.po_number)              as po_numbers
  from public.po_charge_alloc a
  join public.po x on x.id = a.po_id
  group by a.po_charge_id
)
select
  c.id, c.charge_number, c.charge_date, c.due_date, c.kind, c.description, c.status,
  c.supplier_id, s.name as supplier_name,
  c.currency_id, cur.code as currency_code, c.exchange_rate,
  c.total_amount,
  m.paid, m.unpaid, m.alloc_sum, m.unallocated,                          -- po_charge_money 그대로(식 없음)
  coalesce(pos.po_count, 0) as po_count,
  pos.po_numbers,                                                        -- 발주 번호로 청구서를 찾는다(.ilike)
  c.confirmed_at, c.cancelled_at, c.note, c.created_at, c.updated_at,
  -- ── po-tax-2 · 뒤에 더한 넷 ──
  m.tax_amount, m.total_with_tax, c.tax_rule_id, c.tax_rule
from public.po_charge c
join public.po_charge_money m on m.id = c.id
join public.supplier s on s.id = c.supplier_id
join public.ref_currency cur on cur.id = c.currency_id
left join pos on pos.po_charge_id = c.id;
comment on view public.po_charge_list is '⑤ 비용 청구서 목록 — PostgREST 로 표처럼(§10-j 3-a). 돈은 po_charge_money 그대로 · po_numbers(발주 번호 검색). ⭐ [po-tax-2 2026-10-08] 뒤에 넷 tax_amount · total_with_tax · tax_rule_id · tax_rule — total_amount 는 세금 전 · unpaid 는 세금 포함. security_invoker. 정본 po-module §11-f';

-- ═══ ③-2 po_charge_detail 재발행 — 마지막 정의 20260929021949 · header 세금 셋 · money 넷 · 경고 tax_amount_zero_with_rate ═══
create or replace function public.po_charge_detail(p_charge_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with c as (
  select * from public.po_charge where id = p_charge_id
),
m as (
  select * from public.po_charge_money where id = p_charge_id
),
al as (
  select a.id as alloc_id, a.po_id, x.po_number, x.status as po_status, a.amount, a.note,
         a.transfer_id, t.transfer_number, t.status as transfer_status,                                                                        -- tr-4: 트랜스퍼 배분 줄(발주 줄은 null · 반환에는 트랜스퍼 줄에만 키를 더한다)
         coalesce((select sum(round(l.qty_ea * l.unit_price, 2)) from public.po_line l where l.po_id = a.po_id), 0) as base_amount,       -- 비례의 기준(할인 전)
         coalesce((select sum(a2.amount) from public.po_charge_alloc a2 join public.po_charge c2 on c2.id = a2.po_charge_id
                    where a2.po_id = a.po_id and a2.po_charge_id <> p_charge_id and c2.status <> 'cancelled'), 0) as other_charges       -- 그 발주에 이미 붙은 다른 비용
  from public.po_charge_alloc a
  left join public.po x on x.id = a.po_id                                                                                                    -- tr-4: left — 트랜스퍼 배분 줄은 발주가 없다
  left join public.inv_transfer t on t.id = a.transfer_id
  where a.po_charge_id = p_charge_id
),
pay as (
  select pa.id as alloc_id, pa.amount as alloc_amount, pm.id as payment_id, pm.paid_on, pm.reference, pm.amount as payment_amount, pm.discount_taken,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  where pa.po_charge_id = p_charge_id
)
select case when not exists (select 1 from c) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', c.id, 'charge_number', c.charge_number, 'charge_date', c.charge_date, 'due_date', c.due_date, 'kind', c.kind, 'description', c.description, 'status', c.status,
      'supplier_id', c.supplier_id, 'supplier_name', s.name,
      'currency_id', c.currency_id, 'currency_code', cur.code, 'exchange_rate', c.exchange_rate,
      'total_amount', c.total_amount,
      'tax_amount', c.tax_amount, 'tax_rule_id', c.tax_rule_id, 'tax_rule', c.tax_rule,                    -- po-tax-2 · 세금 전 · 찍힌 세금 · 제안 규칙(PostgREST 로 고친다)
      'created_by_name', cb.name, 'confirmed_by_name', fb.name, 'cancelled_by_name', xb.name,
      'confirmed_at', c.confirmed_at, 'cancelled_at', c.cancelled_at, 'note', c.note, 'created_at', c.created_at, 'updated_at', c.updated_at)
    from c
    join public.supplier s on s.id = c.supplier_id
    join public.ref_currency cur on cur.id = c.currency_id
    left join public.ims_staff cb on cb.id = c.created_by
    left join public.ims_staff fb on fb.id = c.confirmed_by
    left join public.ims_staff xb on xb.id = c.cancelled_by
  ),
  'money', (
    select jsonb_build_object('total_amount', m.total_amount, 'paid', m.paid, 'unpaid', m.unpaid, 'alloc_sum', m.alloc_sum, 'unallocated', m.unallocated,
                              'tax_amount', m.tax_amount, 'total_with_tax', m.total_with_tax, 'rate_pct', m.rate_pct, 'tax_suggested', m.tax_suggested) from m   -- po-tax-2
  ),
  'allocs', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'po_id', po_id, 'po_number', po_number, 'po_status', po_status, 'amount', amount, 'note', note,
                                        'base_amount', base_amount, 'other_charges', other_charges)
                     || case when transfer_id is not null then jsonb_build_object('transfer_id', transfer_id, 'transfer_number', transfer_number, 'transfer_status', transfer_status) else '{}'::jsonb end
                     order by po_number, transfer_number)
    from al), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'payment_id', payment_id, 'paid_on', paid_on, 'reference', reference, 'alloc_amount', alloc_amount,
                                        'payment_amount', payment_amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
                                        'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when m.unallocated <> 0 then 'unallocated' end,
        case when not exists (select 1 from al) then 'no_allocs' end,
        case when c.total_amount = 0 then 'total_amount_zero' end,
        case when exists (select 1 from al where al.po_status = 'cancelled') then 'alloc_on_cancelled_po' end,
        case when m.rate_pct > 0 and c.tax_amount = 0 then 'tax_amount_zero_with_rate' end                   -- po-tax-2 · 세율 규칙이 있는데 세금 0 — 잊었을 가능성(막지 않는다)
      ], null)) as w
      from c cross join m) t
  )
) end;
$$;

-- ═══ ③-3 po_charge_create 재발행 — 마지막 정의 20260924001820:807 · 인자 둘(p_tax_amount · p_tax_rule) → drop + create + 권한 · 제안 규칙 · 세금 받기(㉡ 안 주면 0) · 반환 여섯 ═══
drop function if exists public.po_charge_create(uuid, text, date, text, numeric, uuid, date, text, text, uuid[], boolean);
create function public.po_charge_create(
  p_supplier_id   uuid,                        -- 경비처(CBSA · BBE · Showtime …) — 발주처가 아니다
  p_charge_number text,                        -- 청구서 번호 · unique (supplier_id, charge_number)
  p_charge_date   date,                        -- 안 주면 오늘
  p_kind          text,                        -- freight | duty | brokerage | other
  p_total_amount  numeric,                     -- ⭐ 필수 · 우리가 넣는 숫자(계산값이 없다) · 정정은 음수 가능
  p_currency_id   uuid    default null,        -- ⭐ 필수(null 이면 거부 · 폴백 없음 · 이견 5 뒤집음) — 청구서는 자기 통화로 오고 비용처는 건마다 통화가 다를 수 있어 마스터 값이 그 청구서의 통화라는 보장이 없다 · 틀려도 결제 단계까지 조용히 간다. default null 은 인자 순서(뒤에 default 가 있다) 때문이지 선택이라는 뜻이 아니다
  p_due_date      date    default null,
  p_description   text    default null,
  p_note          text    default null,
  p_po_ids        uuid[]  default '{}',        -- 처음 담을 발주(빈 배열 허용) · ⑥ 규칙으로 배분 제안
  p_commit        boolean default false,       -- false = 미리 보기(넣지 않는다)
  p_tax_amount    numeric default null,        -- po-tax-2 ⭐ 청구서에 찍힌 세금(청구 통화) · 안 주면 0 저장 + 경고 tax_amount_not_given(제안값은 반환 tax_suggested 에만 · 결정 ②)
  p_tax_rule      text    default null         -- po-tax-2 · 제안 규칙 이름(활성 purchase) · 안 주면 청구처 supplier.tax_rule(못 풀면 null + 경고 tax_rule_unknown:<원문> · 막지 않는다)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_sup       public.supplier%rowtype;
  v_num       text;
  v_cur       uuid;
  v_cur_code  text;
  v_exists    int;
  v_missing   int;
  v_chg_id    uuid;
  v_allocs    jsonb := '[]'::jsonb;
  v_sum       numeric := 0;
  v_base_sum  numeric := 0;
  v_n         int := 0;
  v_warn      text[] := '{}';
  r           record;
  v_tax_id    uuid;  v_tax_name text;  v_rate numeric;  v_tax_sug numeric;  v_tax numeric;              -- po-tax-2
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_sup from public.supplier where id = p_supplier_id;
  if not found then raise exception 'Supplier % not found — nothing was saved', p_supplier_id; end if;
  -- po-tax-2 · 제안 규칙 — 준 이름 > 청구처 규칙 · 활성 purchase 만 · 준 이름이 틀리면 거부 · 청구처 규칙이 안 풀리면 경고만
  if p_tax_rule is not null then
    select r2.id, r2.name, r2.rate_pct into v_tax_id, v_tax_name, v_rate from public.ref_tax_rule r2 where r2.name = p_tax_rule and r2.direction = 'purchase' and r2.is_active;
    if v_tax_id is null then raise exception 'Tax rule "%" is not an active purchase tax rule — pick one from Settings › Tax rules — nothing was saved', p_tax_rule; end if;
  elsif v_sup.tax_rule is not null then
    select r2.id, r2.name, r2.rate_pct into v_tax_id, v_tax_name, v_rate from public.ref_tax_rule r2 where r2.name = v_sup.tax_rule and r2.direction = 'purchase' and r2.is_active;
    if v_tax_id is null then v_warn := array_append(v_warn, 'tax_rule_unknown:' || v_sup.tax_rule); end if;
  end if;

  v_num := nullif(regexp_replace(coalesce(p_charge_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if v_num is null then raise exception 'Charge number is required — it is the supplier''s document number — nothing was saved'; end if;
  if p_kind is null or p_kind not in ('freight', 'duty', 'brokerage', 'other') then
    raise exception 'p_kind must be freight, duty, brokerage or other — nothing was saved';
  end if;
  if p_total_amount is null then raise exception 'Total amount is required — nothing was saved'; end if;

  -- 통화 — 사람이 고른다 · 폴백 없음(Caleb 2026-09-17 · 이견 5 뒤집음): 비용처는 건마다 통화가 다를 수 있어 공급처 마스터 값이 이 청구서의 통화라는 보장이 없고, 틀리면 결제 단계까지 조용히 간다
  if p_currency_id is null then raise exception 'Currency is required — nothing was saved'; end if;
  v_cur := p_currency_id;
  select c.code into v_cur_code from public.ref_currency c where c.id = v_cur;
  if v_cur_code is null then raise exception 'Currency % not found — nothing was saved', v_cur; end if;

  -- 번호 중복 — 미리 보기는 경고 · commit 은 읽을 문장으로 거부
  select count(*) into v_exists from public.po_charge where supplier_id = p_supplier_id and charge_number = v_num;
  if v_exists > 0 then
    if p_commit then raise exception 'Charge % already exists for % — nothing was saved', v_num, v_sup.name; end if;
    v_warn := array_append(v_warn, 'charge_number_exists');
  end if;
  if p_total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;
  -- po-tax-2 · 세금 — 찍힌 값을 받는다 · 제안값은 반환만 · 안 주면 0 + 경고 · 세율 규칙이 있는데 0 이면 경고(막지 않는다)
  v_tax_sug := public.so_tax_amount(p_total_amount, v_rate);
  v_tax := coalesce(p_tax_amount, 0);
  if p_tax_amount is null and coalesce(v_tax_sug, 0) <> 0 then v_warn := array_append(v_warn, 'tax_amount_not_given'); end if;
  if coalesce(v_rate, 0) > 0 and v_tax = 0 then v_warn := array_append(v_warn, 'tax_amount_zero_with_rate'); end if;

  -- 발주 존재 검사 — 제안 함수는 없는 id 를 조용히 빠뜨리므로 여기서 먼저
  select count(*) into v_missing from unnest(coalesce(p_po_ids, '{}'::uuid[])) u where not exists (select 1 from public.po x where x.id = u);
  if v_missing > 0 then raise exception '% of the given PO id(s) do not exist — nothing was saved', v_missing; end if;

  -- commit: 머리 한 행(만든 사람 서버 유도)
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
    insert into public.po_charge (supplier_id, charge_number, charge_date, due_date, kind, description, currency_id, total_amount, status, created_by, note, tax_amount, tax_rule_id, tax_rule)
    values (p_supplier_id, v_num, coalesce(p_charge_date, public.ims_today()), p_due_date, p_kind, p_description, v_cur, p_total_amount, 'draft', v_staff, p_note, v_tax, v_tax_id, v_tax_name)   -- po-tax-2
    returning id into v_chg_id;
  end if;

  -- 배분 제안(⑥ 규칙 한 곳) — 미리 보기는 계산만 · commit 은 박는다
  for r in select * from public.po_charge_alloc_propose(p_total_amount, p_po_ids) loop
    v_n := v_n + 1; v_sum := v_sum + r.amount; v_base_sum := v_base_sum + r.base_amount;
    if r.po_status = 'cancelled' and not ('alloc_on_cancelled_po' = any(v_warn)) then v_warn := array_append(v_warn, 'alloc_on_cancelled_po'); end if;
    if p_commit then
      insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (v_chg_id, r.po_id, r.amount);
    end if;
    v_allocs := v_allocs || jsonb_build_object('po_id', r.po_id, 'po_number', r.po_number, 'po_status', r.po_status, 'base_amount', r.base_amount, 'amount', r.amount, 'inserted', p_commit);
  end loop;
  if v_n > 0 and v_base_sum = 0 then v_warn := array_append(v_warn, 'no_base_amount'); end if;   -- 라인 금액이 전부 0 → 균등으로 나눴다

  return jsonb_build_object(
    'committed', p_commit, 'charge_id', v_chg_id, 'charge_number', v_num, 'charge_date', coalesce(p_charge_date, public.ims_today()), 'kind', p_kind,
    'supplier_id', p_supplier_id, 'supplier_name', v_sup.name, 'currency_id', v_cur, 'currency_code', v_cur_code,
    'total_amount', p_total_amount, 'alloc_sum', v_sum, 'unallocated', p_total_amount - v_sum,
    'tax_rule_id', v_tax_id, 'tax_rule', v_tax_name, 'rate_pct', v_rate, 'tax_suggested', v_tax_sug,          -- po-tax-2 · 제안(반환만)
    'tax_amount', v_tax, 'total_with_tax', p_total_amount + v_tax,                                            -- po-tax-2 · 저장되는(된) 값
    'allocs', v_allocs, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Charge % already exists for % — nothing was saved', v_num, coalesce(v_sup.name, 'this supplier');
end;
$$;
comment on function public.po_charge_create(uuid, text, date, text, numeric, uuid, date, text, text, uuid[], boolean, numeric, text) is '⑤ 비용 청구서 만들기(미리 보기 = 같은 모양 · p_commit) — 청구처 · 번호 · 날짜 · 종류 · ⭐ total_amount = 세금 전(po-tax-2) · 통화(필수 · 폴백 없음) · 배분 제안(po_charge_alloc_propose · 세금 전 비례) · ⭐ [po-tax-2 2026-10-08] p_tax_amount = 청구서에 찍힌 세금(안 주면 0 저장 + 경고 tax_amount_not_given · 제안값은 반환 tax_suggested) · p_tax_rule = 제안 규칙 이름(안 주면 청구처 supplier.tax_rule → id · 못 풀면 null + 경고 tax_rule_unknown:<원문>) · 경고 tax_amount_zero_with_rate(세율 규칙인데 0) · 반환 tax_rule_id · tax_rule · rate_pct · tax_suggested · tax_amount · total_with_tax. 정본 po-module §11-f';
revoke all on function public.po_charge_create(uuid, text, date, text, numeric, uuid, date, text, text, uuid[], boolean, numeric, text) from public, anon;
grant execute on function public.po_charge_create(uuid, text, date, text, numeric, uuid, date, text, text, uuid[], boolean, numeric, text) to authenticated;

-- ═══ ③-4 po_charge_confirm 재발행 — 마지막 정의 20260919200414 · 경고 tax_amount_zero_with_rate · money 둘 · 원가 호출 무변(세금 전) ═══
create or replace function public.po_charge_confirm(p_charge_id uuid, p_confirm boolean default true) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_doc   text;                                                 -- ②-b: 0행 문장용(returning 이 v_chg 를 null 로 덮는다)
  v_staff uuid;
  v_chg   public.po_charge%rowtype;
  v_m     record;
  v_n     int;
  v_txt   text;
  v_warn  text[] := '{}';
  v_cost  jsonb;                                                -- 원가 창구의 반환(원가 이식 2차 · 2026-09-19)
  v_cur   text;                                                 -- ⑥ 환율 게이트 — 청구 통화 코드
  v_base_cur text;                                              -- ⑥ 기준통화 코드(inv_config.base_currency) · ⚠️ 원문에 같은 이름 없음 확인(2026-09-19 v_base 실사고)
  v_rate  numeric;                                              -- po-tax-2 · 제안 규칙 세율(경고용)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  v_doc := 'Charge ' || v_chg.charge_number;
  select * into v_m from public.po_charge_money where id = p_charge_id;

  if p_confirm then
    if v_chg.status = 'confirmed' then raise exception 'Charge % is already confirmed — nothing was saved', v_chg.charge_number; end if;
    if v_chg.status = 'cancelled' then raise exception 'Charge % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_chg.charge_number; end if;
    select count(*) into v_n from public.po_charge_alloc where po_charge_id = p_charge_id;
    if v_n = 0 then raise exception 'Charge % has no allocation lines — nothing to put on cost — nothing was saved', v_chg.charge_number; end if;
    -- ⭐⭐ 거부(경고 아님) — 양쪽 다 우리가 넣는 숫자라 안 맞으면 덜 입력한 것(⑤)
    if v_m.unallocated <> 0 then
      raise exception 'Charge % is not fully allocated — total % · allocated % · unallocated % — fix the allocations (or press Spread) first — nothing was saved',
        v_chg.charge_number, v_m.total_amount, v_m.alloc_sum, v_m.unallocated;
    end if;
    if v_chg.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;
    select r.rate_pct into v_rate from public.ref_tax_rule r where r.id = v_chg.tax_rule_id;                 -- po-tax-2
    if coalesce(v_rate, 0) > 0 and v_chg.tax_amount = 0 then v_warn := array_append(v_warn, 'tax_amount_zero_with_rate'); end if;   -- po-tax-2 · 막지 않는다(세금은 낼 돈만 · 원가 무관)
    if exists (select 1 from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = p_charge_id and x.status = 'cancelled') then
      v_warn := array_append(v_warn, 'alloc_on_cancelled_po');
    end if;
    -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 비용인데 환율이 없거나 0 이면 확정 거부(입고와 같은 이유 · 원가가 조용히 틀리는 것보다 낫다 · 원가 이식 2차 2026-09-19)
    --   ⚠️ po_charge.exchange_rate 는 CAD per USD 다 — amount × exchange_rate = CAD. 곱한다 · 나누지 않는다(계산은 inv_layer_post_charge 에서).
    select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
    select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
    if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which charges need an exchange rate — nothing was saved'; end if;
    if v_cur is distinct from v_base_cur and (v_chg.exchange_rate is null or v_chg.exchange_rate <= 0) then
      raise exception 'Charge % is in % but has no % per % exchange rate — the cost cannot be put on stock without it. Enter the rate on the charge ("Exchange rate") and confirm again — nothing was saved',
        v_chg.charge_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
    end if;
    update public.po_charge set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    -- ⭐ 원가 — 같은 트랜잭션으로 레이어에 얹는다(원장 이식 2차의 ⓔ 와 같은 판단 · 원칙 2 「안에 있는 것끼리는 창구를 부른다」 · 하나가 실패하면 확정도 실패)
    v_cost := public.inv_layer_post_charge(p_charge_id);
    if coalesce((v_cost->>'no_layers_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_not_on_stock_no_receipt_yet'); end if;   -- 입고가 없는 발주 — 나중에 백필(inv_layer_post_charge 재호출)
    if coalesce((v_cost->>'no_basis_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_dropped_no_basis'); end if;                 -- 정본 D — 기준 0 은 버린다
  else
    if v_chg.status <> 'confirmed' then raise exception 'Charge % is % — only a confirmed document can be reopened — nothing was saved', v_chg.charge_number, v_chg.status; end if;
    -- ⭐ po_invoice_confirm Reopen · po_doc_cancel 과 같은 선 — 결제 참조번호·금액을 이름으로
    if v_m.paid > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_charge_id = p_charge_id;
      raise exception 'Charge % has payments applied (%) — cannot reopen while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
    end if;
    -- ⭐ [원가 이식 2차] landed 가 이미 레이어에 얹혔으면 되돌리지 않는다 — 원가는 append-only. 되돌려 배분을 고치고 다시 확정해도 멱등이 건너뛰어 옛 금액이 남는다.
    select count(*) into v_n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number;
    if v_n > 0 then
      raise exception 'Charge % has already been added to stock cost (% layer row(s)) — it cannot be reopened; to correct it, enter an offsetting charge — nothing was saved', v_chg.charge_number, v_n;
    end if;
    update public.po_charge set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
  end if;

  return jsonb_build_object(
    'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status, 'confirmed_at', v_chg.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'paid', v_m.paid, 'unpaid', v_m.unpaid, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated,
                                'tax_amount', v_m.tax_amount, 'total_with_tax', v_m.total_with_tax),         -- po-tax-2
    'cost', v_cost,                                                                              -- ⭐ 원가 결과(layers_touched · amount_posted_cad · no_layers · no_basis · allocs[]) · 되돌리기면 null
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ③-5 tf_charge_create 재발행 — 마지막 정의 20260929021949:238 · 인자 둘 → drop + create + 권한(definer) · 같은 규칙 ═══
drop function if exists public.tf_charge_create(uuid, uuid, text, date, text, numeric, uuid, numeric, date, text, text, boolean);
create function public.tf_charge_create(
  p_transfer_id   uuid,                        -- 운임을 얹을 트랜스퍼(배분 줄 하나 = 총액 · 더 얹으려면 tf_charge_alloc_add)
  p_supplier_id   uuid,                        -- 경비처(운송사 …) — 발주처가 아니다
  p_charge_number text,                        -- 청구서 번호 · unique (supplier_id, charge_number)
  p_charge_date   date,                        -- 안 주면 오늘
  p_kind          text,                        -- freight | duty | brokerage | other
  p_total_amount  numeric,                     -- ⭐ 필수 · 우리가 넣는 숫자 · 정정은 음수 가능
  p_currency_id   uuid    default null,        -- ⭐ 필수(폴백 없음 · 발주 비용과 같은 판단)
  p_exchange_rate numeric default null,        -- 기준통화 per 청구 통화(CAD per USD) — 기준통화가 아니면 확정 때 필요
  p_due_date      date    default null,
  p_description   text    default null,
  p_note          text    default null,
  p_commit        boolean default false,       -- false = 미리 보기(넣지 않는다)
  p_tax_amount    numeric default null,        -- po-tax-2 ⭐ 청구서에 찍힌 세금 · 안 주면 0 저장 + 경고 tax_amount_not_given(제안값은 tax_suggested 에만)
  p_tax_rule      text    default null         -- po-tax-2 · 제안 규칙 이름(활성 purchase) · 안 주면 청구처 규칙(못 풀면 null + 경고)
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_x public.inv_transfer%rowtype; v_sup public.supplier%rowtype; v_num text; v_cur_code text; v_exists int; v_chg_id uuid; v_alloc_id uuid; v_warn text[] := '{}';
        v_tax_id uuid; v_tax_name text; v_rate numeric; v_tax_sug numeric; v_tax numeric;                   -- po-tax-2
begin
  perform public.ims_require_write('transfer', 'saved');                                                   -- ⭐ 첫 줄 문
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id;
  if not found then raise exception 'Transfer % not found — nothing was saved', p_transfer_id; end if;
  if v_x.status in ('draft', 'cancelled') then raise exception 'Transfer % is % — a freight charge goes on a confirmed transfer — nothing was saved', v_x.transfer_number, v_x.status; end if;
  if not (public.ims_can_warehouse(v_x.from_warehouse_id) or public.ims_can_warehouse(v_x.to_warehouse_id)) then
    raise exception 'Transfer % is between warehouses you are not set up for — nothing was saved', v_x.transfer_number;
  end if;
  select * into v_sup from public.supplier where id = p_supplier_id;
  if not found then raise exception 'Supplier % not found — nothing was saved', p_supplier_id; end if;
  v_num := nullif(regexp_replace(coalesce(p_charge_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if v_num is null then raise exception 'Charge number is required — it is the supplier''s document number — nothing was saved'; end if;
  if p_kind is null or p_kind not in ('freight', 'duty', 'brokerage', 'other') then raise exception 'p_kind must be freight, duty, brokerage or other — nothing was saved'; end if;
  if p_total_amount is null then raise exception 'Total amount is required — nothing was saved'; end if;
  if p_currency_id is null then raise exception 'Currency is required — nothing was saved'; end if;
  select c.code into v_cur_code from public.ref_currency c where c.id = p_currency_id;
  if v_cur_code is null then raise exception 'Currency % not found — nothing was saved', p_currency_id; end if;
  if p_exchange_rate is not null and p_exchange_rate <= 0 then raise exception 'Exchange rate must be a positive number — nothing was saved'; end if;
  select count(*) into v_exists from public.po_charge where supplier_id = p_supplier_id and charge_number = v_num;
  if v_exists > 0 then
    if p_commit then raise exception 'Charge % already exists for % — nothing was saved', v_num, v_sup.name; end if;
    v_warn := array_append(v_warn, 'charge_number_exists');
  end if;
  if p_total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;
  if v_x.status not in ('received') then v_warn := array_append(v_warn, 'transfer_not_arrived_yet'); end if;              -- 넣어 둘 수는 있다(묶음 일곱 4) · 원가는 도착 뒤
  -- po-tax-2 · 제안 규칙(준 이름 > 청구처 규칙 · 활성 purchase 만) · 세금은 찍힌 값 · 안 주면 0 + 경고 · 원가(도착 순간 landed)는 total_amount 만
  if p_tax_rule is not null then
    select r2.id, r2.name, r2.rate_pct into v_tax_id, v_tax_name, v_rate from public.ref_tax_rule r2 where r2.name = p_tax_rule and r2.direction = 'purchase' and r2.is_active;
    if v_tax_id is null then raise exception 'Tax rule "%" is not an active purchase tax rule — pick one from Settings › Tax rules — nothing was saved', p_tax_rule; end if;
  elsif v_sup.tax_rule is not null then
    select r2.id, r2.name, r2.rate_pct into v_tax_id, v_tax_name, v_rate from public.ref_tax_rule r2 where r2.name = v_sup.tax_rule and r2.direction = 'purchase' and r2.is_active;
    if v_tax_id is null then v_warn := array_append(v_warn, 'tax_rule_unknown:' || v_sup.tax_rule); end if;
  end if;
  v_tax_sug := public.so_tax_amount(p_total_amount, v_rate);
  v_tax := coalesce(p_tax_amount, 0);
  if p_tax_amount is null and coalesce(v_tax_sug, 0) <> 0 then v_warn := array_append(v_warn, 'tax_amount_not_given'); end if;
  if coalesce(v_rate, 0) > 0 and v_tax = 0 then v_warn := array_append(v_warn, 'tax_amount_zero_with_rate'); end if;
  if p_commit then
    insert into public.po_charge (supplier_id, charge_number, charge_date, due_date, kind, description, currency_id, exchange_rate, total_amount, status, created_by, note, tax_amount, tax_rule_id, tax_rule)
    values (p_supplier_id, v_num, coalesce(p_charge_date, public.ims_today()), p_due_date, p_kind, p_description, p_currency_id, p_exchange_rate, p_total_amount, 'draft', v_staff, p_note, v_tax, v_tax_id, v_tax_name)   -- po-tax-2
    returning id into v_chg_id;
    insert into public.po_charge_alloc (po_charge_id, transfer_id, amount) values (v_chg_id, v_x.id, p_total_amount) returning id into v_alloc_id;
  end if;
  return jsonb_build_object('committed', p_commit, 'charge_id', v_chg_id, 'charge_number', v_num, 'charge_date', coalesce(p_charge_date, public.ims_today()), 'kind', p_kind,
                            'supplier_id', p_supplier_id, 'supplier_name', v_sup.name, 'currency_id', p_currency_id, 'currency_code', v_cur_code, 'exchange_rate', p_exchange_rate,
                            'total_amount', p_total_amount, 'alloc_sum', p_total_amount, 'unallocated', 0,
                            'tax_rule_id', v_tax_id, 'tax_rule', v_tax_name, 'rate_pct', v_rate, 'tax_suggested', v_tax_sug, 'tax_amount', v_tax, 'total_with_tax', p_total_amount + v_tax,   -- po-tax-2
                            'allocs', jsonb_build_array(jsonb_build_object('alloc_id', v_alloc_id, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'transfer_status', v_x.status, 'amount', p_total_amount, 'inserted', p_commit)),
                            'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Charge % already exists for % — nothing was saved', v_num, coalesce(v_sup.name, 'this supplier');
end;
$$;
comment on function public.tf_charge_create(uuid, uuid, text, date, text, numeric, uuid, numeric, date, text, text, boolean, numeric, text) is 'tr-4 — 트랜스퍼 운임 문서 만들기(transfer 열쇠 · 창고 · 배분 줄 하나 = total_amount) · ⭐ [po-tax-2 2026-10-08] p_tax_amount(찍힌 세금 · 안 주면 0 + 경고 tax_amount_not_given) · p_tax_rule(제안 규칙 · 안 주면 청구처 규칙) · 반환 tax_rule_id · tax_rule · rate_pct · tax_suggested · tax_amount · total_with_tax · 도착 순간 얹히는 원가(inv_layer_post_charge)는 total_amount(세금 전)만 · 정본 po-module §11-f · so-module §27';
revoke all on function public.tf_charge_create(uuid, uuid, text, date, text, numeric, uuid, numeric, date, text, text, boolean, numeric, text) from public, anon;
grant execute on function public.tf_charge_create(uuid, uuid, text, date, text, numeric, uuid, numeric, date, text, text, boolean, numeric, text) to authenticated;

-- ═══ ③-6 tf_charge_update 재발행 — 마지막 정의 20260929021949:302 · 열쇠 셋(tax_amount · tax_rule · tax_rule_id) · 반환 다섯 ═══
create or replace function public.tf_charge_update(p_charge_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_chg public.po_charge%rowtype; v_k text; v_n int; v_cur text; v_m record;
begin
  v_chg := public.tf_charge_access(p_charge_id, 'saved');                                                  -- ⭐ 첫 줄 문(열쇠 · 발주 배분 없음 · 창고)
  select * into v_chg from public.po_charge c where c.id = p_charge_id for update;
  if v_chg.status <> 'draft' then raise exception 'Charge % is % — the head can be edited only while draft — nothing was saved', v_chg.charge_number, v_chg.status; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then raise exception 'p_patch must be a JSON object of the fields to change — nothing was saved'; end if;
  for v_k in select jsonb_object_keys(p_patch) loop
    if v_k not in ('supplier_id', 'charge_number', 'charge_date', 'due_date', 'kind', 'total_amount', 'currency_id', 'exchange_rate', 'description', 'note', 'tax_amount', 'tax_rule', 'tax_rule_id') then   -- po-tax-2 · 열쇠 셋
      raise exception 'Field % cannot be changed here — nothing was saved', v_k;
    end if;
  end loop;
  if p_patch ? 'kind' and (p_patch ->> 'kind') not in ('freight', 'duty', 'brokerage', 'other') then raise exception 'kind must be freight, duty, brokerage or other — nothing was saved'; end if;
  if p_patch ? 'total_amount' and (p_patch ->> 'total_amount') is null then raise exception 'Total amount cannot be left empty — nothing was saved'; end if;
  if p_patch ? 'tax_amount' and (p_patch ->> 'tax_amount') is null then raise exception 'Tax amount cannot be left empty — enter 0 when the bill has no tax — nothing was saved'; end if;   -- po-tax-2
  if p_patch ? 'charge_date' and (p_patch ->> 'charge_date') is null then raise exception 'Charge date cannot be left empty — nothing was saved'; end if;
  if p_patch ? 'charge_number' and nullif(regexp_replace(coalesce(p_patch ->> 'charge_number', ''), '^[\s ]+|[\s ]+$', '', 'g'), '') is null then raise exception 'Charge number cannot be left empty — nothing was saved'; end if;
  if p_patch ? 'currency_id' then
    select c.code into v_cur from public.ref_currency c where c.id = (p_patch ->> 'currency_id')::uuid;
    if v_cur is null then raise exception 'Currency % not found — nothing was saved', p_patch ->> 'currency_id'; end if;
  end if;
  if p_patch ? 'supplier_id' and not exists (select 1 from public.supplier s where s.id = (p_patch ->> 'supplier_id')::uuid) then raise exception 'Supplier % not found — nothing was saved', p_patch ->> 'supplier_id'; end if;
  if p_patch ? 'exchange_rate' and (p_patch ->> 'exchange_rate') is not null and (p_patch ->> 'exchange_rate')::numeric <= 0 then raise exception 'Exchange rate must be a positive number — nothing was saved'; end if;
  update public.po_charge set
    supplier_id   = case when p_patch ? 'supplier_id'   then (p_patch ->> 'supplier_id')::uuid else supplier_id end,
    charge_number = case when p_patch ? 'charge_number' then regexp_replace(p_patch ->> 'charge_number', '^[\s ]+|[\s ]+$', '', 'g') else charge_number end,
    charge_date   = case when p_patch ? 'charge_date'   then (p_patch ->> 'charge_date')::date else charge_date end,
    due_date      = case when p_patch ? 'due_date'      then (p_patch ->> 'due_date')::date else due_date end,
    kind          = case when p_patch ? 'kind'          then p_patch ->> 'kind' else kind end,
    total_amount  = case when p_patch ? 'total_amount'  then (p_patch ->> 'total_amount')::numeric else total_amount end,
    currency_id   = case when p_patch ? 'currency_id'   then (p_patch ->> 'currency_id')::uuid else currency_id end,
    exchange_rate = case when p_patch ? 'exchange_rate' then (p_patch ->> 'exchange_rate')::numeric else exchange_rate end,
    description   = case when p_patch ? 'description'   then p_patch ->> 'description' else description end,
    note          = case when p_patch ? 'note'          then p_patch ->> 'note' else note end,
    tax_amount    = case when p_patch ? 'tax_amount'    then (p_patch ->> 'tax_amount')::numeric else tax_amount end,                 -- po-tax-2 · 찍힌 세금
    tax_rule      = case when p_patch ? 'tax_rule'      then nullif(p_patch ->> 'tax_rule', '') else tax_rule end,                    -- po-tax-2 · 이름(트리거가 id · 활성 purchase 아니면 거부) · "" = 없음
    tax_rule_id   = case when p_patch ? 'tax_rule_id'   then nullif(p_patch ->> 'tax_rule_id', '')::uuid else tax_rule_id end        -- po-tax-2 · id(둘 다 오면 id)
  where id = p_charge_id and status = 'draft' returning * into v_chg;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Charge % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_charge_id; end if;
  select * into v_m from public.po_charge_money where id = p_charge_id;
  return jsonb_build_object('charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status, 'charge_date', v_chg.charge_date, 'kind', v_chg.kind, 'total_amount', v_chg.total_amount,
                            'currency_id', v_chg.currency_id, 'exchange_rate', v_chg.exchange_rate, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated, 'changed', (select jsonb_agg(k) from jsonb_object_keys(p_patch) k),
                            'tax_amount', v_chg.tax_amount, 'tax_rule', v_chg.tax_rule, 'tax_rule_id', v_chg.tax_rule_id, 'total_with_tax', v_m.total_with_tax, 'tax_suggested', v_m.tax_suggested);   -- po-tax-2
exception
  when unique_violation then
    raise exception 'Charge % already exists for this supplier — nothing was saved', coalesce(p_patch ->> 'charge_number', v_chg.charge_number);
end;
$$;

-- ═══ ③-7 tf_charge_confirm 재발행 — 마지막 정의 20260929021949 · 경고 · money 둘 ═══
create or replace function public.tf_charge_confirm(p_charge_id uuid, p_confirm boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_chg public.po_charge%rowtype; v_staff uuid; v_m record; v_n int; v_txt text; v_warn text[] := '{}'; v_cost jsonb; v_cur text; v_base_cur text;
        v_rate numeric;                                                                                      -- po-tax-2
begin
  v_chg := public.tf_charge_access(p_charge_id, 'saved');                                                  -- ⭐ 첫 줄 문
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_chg from public.po_charge c where c.id = p_charge_id for update;
  select * into v_m from public.po_charge_money where id = p_charge_id;
  if p_confirm then
    if v_chg.status = 'confirmed' then raise exception 'Charge % is already confirmed — nothing was saved', v_chg.charge_number; end if;
    if v_chg.status = 'cancelled' then raise exception 'Charge % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_chg.charge_number; end if;
    select count(*) into v_n from public.po_charge_alloc where po_charge_id = p_charge_id;
    if v_n = 0 then raise exception 'Charge % has no allocation lines — nothing to put on cost — nothing was saved', v_chg.charge_number; end if;
    if v_m.unallocated <> 0 then                                                                           -- 거부(경고 아님) — 발주 비용과 같은 판단 ⑤
      raise exception 'Charge % is not fully allocated — total % · allocated % · unallocated % — fix the allocation line(s) first — nothing was saved', v_chg.charge_number, v_m.total_amount, v_m.alloc_sum, v_m.unallocated;
    end if;
    if v_chg.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;
    select r.rate_pct into v_rate from public.ref_tax_rule r where r.id = v_chg.tax_rule_id;                 -- po-tax-2
    if coalesce(v_rate, 0) > 0 and v_chg.tax_amount = 0 then v_warn := array_append(v_warn, 'tax_amount_zero_with_rate'); end if;   -- po-tax-2 · 막지 않는다
    if exists (select 1 from public.po_charge_alloc a join public.inv_transfer x on x.id = a.transfer_id where a.po_charge_id = p_charge_id and x.status = 'cancelled') then v_warn := array_append(v_warn, 'alloc_on_cancelled_transfer'); end if;
    -- 환율 게이트 — 기준통화가 아닌데 환율이 없거나 0 이면 확정 거부(발주 비용 ⑥ 과 같은 이유 · amount × exchange_rate = CAD · 곱한다)
    select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
    select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
    if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which charges need an exchange rate — nothing was saved'; end if;
    if v_cur is distinct from v_base_cur and (v_chg.exchange_rate is null or v_chg.exchange_rate <= 0) then
      raise exception 'Charge % is in % but has no % per % exchange rate — the cost cannot be put on stock without it. Enter the rate on the charge and confirm again — nothing was saved', v_chg.charge_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
    end if;
    update public.po_charge set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_charge_id and status = 'draft' returning * into v_chg;
    if not found then raise exception 'Charge % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_charge_id; end if;
    v_cost := public.inv_layer_post_charge(p_charge_id);                                                   -- ⭐ 원가 — 같은 트랜잭션(하나가 실패하면 확정도 실패) · 문은 창구 안(transfer 열쇠 · 발주 배분 없음)
    if coalesce((v_cost ->> 'no_layers_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_not_on_stock_not_arrived_yet'); end if;   -- 도착 전(묶음 일곱 4) — 도착 뒤 inv_layer_post_charge 재호출(백필) 또는 재생성
    if coalesce((v_cost ->> 'no_basis_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_dropped_no_basis'); end if;
  else
    if v_chg.status <> 'confirmed' then raise exception 'Charge % is % — only a confirmed document can be reopened — nothing was saved', v_chg.charge_number, v_chg.status; end if;
    if v_m.paid > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id where pa.po_charge_id = p_charge_id;
      raise exception 'Charge % has payments applied (%) — cannot reopen while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
    end if;
    select count(*) into v_n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number;   -- append-only — 레이어에 얹힌 것은 되돌리지 않는다(발주 비용과 같다)
    if v_n > 0 then raise exception 'Charge % has already been added to stock cost (% layer row(s)) — it cannot be reopened; to correct it, enter an offsetting charge — nothing was saved', v_chg.charge_number, v_n; end if;
    update public.po_charge set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_charge_id and status = 'confirmed' returning * into v_chg;
    if not found then raise exception 'Charge % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_charge_id; end if;
  end if;
  return jsonb_build_object('id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status, 'confirmed_at', v_chg.confirmed_at,
                            'money', jsonb_build_object('total_amount', v_m.total_amount, 'paid', v_m.paid, 'unpaid', v_m.unpaid, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated,
                                                        'tax_amount', v_m.tax_amount, 'total_with_tax', v_m.total_with_tax),         -- po-tax-2
                            'cost', v_cost, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ③-8 po_payment_target_check 재발행 — 마지막 정의 20260917190000:62 · 비용 doc_total = 뷰 total_with_tax(세금 포함 · 안 고치면 세금만큼 「미지급 초과」 거부) ═══
create or replace function public.po_payment_target_check(
  p_kind            text,                  -- 'invoice' | 'charge'
  p_target_id       uuid,
  p_amount          numeric,               -- null 이면 초과 검사를 건너뛴다(미지급 전액 제안용)
  p_currency_id     uuid,                  -- 결제 통화 · 대상 문서와 같아야 한다
  p_exclude_alloc_id uuid default null     -- 고치는 중인 줄 — 그 금액은 미지급에 되돌려 놓고 본다
) returns table (
  target_number text, target_status text, supplier_id uuid, supplier_name text,
  currency_id uuid, currency_code text, doc_total numeric, doc_paid numeric, doc_unpaid numeric
)
language plpgsql
stable
security invoker
set search_path = public, pg_temp
as $$
declare
  v_label   text;
  v_kind    text;
  v_excl    numeric := 0;
  v_pay_cur text;
begin
  if p_kind not in ('invoice', 'charge') then
    raise exception 'p_targets[].kind must be invoice or charge — nothing was saved';
  end if;
  if p_exclude_alloc_id is not null then
    select coalesce(a.amount, 0) into v_excl from public.po_payment_alloc a where a.id = p_exclude_alloc_id;
    v_excl := coalesce(v_excl, 0);
  end if;
  select c.code into v_pay_cur from public.ref_currency c where c.id = p_currency_id;

  if p_kind = 'invoice' then
    select i.invoice_number, i.status, i.supplier_id, s.name, i.currency_id, cur.code, m.payable_net, m.alloc_total, m.unpaid, i.doc_kind
      into target_number, target_status, supplier_id, supplier_name, currency_id, currency_code, doc_total, doc_paid, doc_unpaid, v_kind
    from public.po_invoice i
    join public.po_invoice_money m on m.id = i.id
    join public.supplier s on s.id = i.supplier_id
    join public.ref_currency cur on cur.id = i.currency_id
    where i.id = p_target_id;
    if not found then raise exception 'Invoice % not found — nothing was saved', p_target_id; end if;
    if v_kind = 'credit' then
      -- §11-h 「안 붙은 크레딧만 이 길 · 붙은 크레딧은 두 번 깎인다」 — 부호가 반대라 이 검산에 못 섞는다 · 다음 차수(이견 4)
      raise exception '% is a credit note — using a credit note in a payment is a later step; only invoices and charges can be paid here — nothing was saved', target_number;
    end if;
    v_label := 'Invoice';
  else
    select c.charge_number, c.status, c.supplier_id, s.name, c.currency_id, cur.code, m.total_with_tax, m.paid, m.unpaid   -- po-tax-2 · 비용의 낼 돈 = 세금 포함(뷰)
      into target_number, target_status, supplier_id, supplier_name, currency_id, currency_code, doc_total, doc_paid, doc_unpaid
    from public.po_charge c
    join public.po_charge_money m on m.id = c.id
    join public.supplier s on s.id = c.supplier_id
    join public.ref_currency cur on cur.id = c.currency_id
    where c.id = p_target_id;
    if not found then raise exception 'Charge % not found — nothing was saved', p_target_id; end if;
    v_label := 'Charge';
  end if;

  -- ④ 확정된 문서에만 — 초안에도 미지급이 계산되므로 여기서 막는다
  if target_status <> 'confirmed' then
    raise exception '% % is % — only a confirmed document can be paid (confirm it first) — nothing was saved', v_label, target_number, target_status;
  end if;
  -- ② 한 결제 = 한 통화 — 문서 번호와 통화를 이름으로
  if currency_id <> p_currency_id then
    raise exception '% % is % but the payment is % — one payment, one currency; pay it with a separate % payment — nothing was saved',
      v_label, target_number, currency_code, coalesce(v_pay_cur, p_currency_id::text), currency_code;
  end if;
  -- ⑤ 미지급 초과 — 고치는 중인 줄의 금액은 되돌려 놓고 본다
  if p_amount is not null and p_amount > doc_unpaid + v_excl then
    raise exception '% %: allocating % but only % is unpaid — nothing was saved', v_label, target_number, p_amount, doc_unpaid + v_excl;
  end if;
  return next;
end;
$$;

-- ═══ ③-9 po_payment_detail 재발행 — 마지막 정의 20260917190000:170 · 비용 doc_total = total_with_tax ═══
create or replace function public.po_payment_detail(p_payment_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with p as (
  select * from public.po_payment where id = p_payment_id
),
al as (
  select pa.id as alloc_id, pa.amount, pa.note,
         case when pa.po_charge_id is not null then 'charge' else 'invoice' end                  as target_kind,
         coalesce(pa.po_invoice_id, pa.po_charge_id)                                             as target_id,
         coalesce(i.invoice_number, c.charge_number)                                             as target_number,
         coalesce(i.status, c.status)                                                            as target_status,
         coalesce(i.supplier_id, c.supplier_id)                                                  as supplier_id,
         s.name                                                                                  as supplier_name,
         coalesce(i.currency_id, c.currency_id)                                                  as doc_currency_id,
         cur.code                                                                                as currency_code,
         case when pa.po_charge_id is not null then cm.total_with_tax else im.payable_net end    as doc_total,        -- 인보이스 payable_net · 비용 total_with_tax(po-tax-2 · 세금 포함)
         case when pa.po_charge_id is not null then cm.paid         else im.alloc_total end      as doc_paid_total,   -- 그 문서에 붙은 모든 결제의 충당 합
         case when pa.po_charge_id is not null then cm.unpaid       else im.unpaid end           as doc_unpaid
  from public.po_payment_alloc pa
  left join public.po_invoice i on i.id = pa.po_invoice_id
  left join public.po_invoice_money im on im.id = pa.po_invoice_id
  left join public.po_charge c on c.id = pa.po_charge_id
  left join public.po_charge_money cm on cm.id = pa.po_charge_id
  left join public.supplier s on s.id = coalesce(i.supplier_id, c.supplier_id)
  left join public.ref_currency cur on cur.id = coalesce(i.currency_id, c.currency_id)
  where pa.po_payment_id = p_payment_id
),
m as (
  select p.amount, p.discount_taken, coalesce((select sum(amount) from al), 0) as alloc_sum,
         p.amount + p.discount_taken - coalesce((select sum(amount) from al), 0) as gap
  from p
)
select case when not exists (select 1 from p) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', p.id, 'paid_on', p.paid_on, 'amount', p.amount, 'discount_taken', p.discount_taken,
      'currency_id', p.currency_id, 'currency_code', cur.code, 'exchange_rate', p.exchange_rate,
      'account_id', p.account_id, 'account_code', acc.code, 'account_name', acc.name,
      'reference', p.reference, 'paid_by', p.paid_by, 'paid_by_name', st.name, 'note', p.note, 'created_at', p.created_at, 'updated_at', p.updated_at)
    from p
    join public.ref_currency cur on cur.id = p.currency_id
    left join public.ref_account acc on acc.id = p.account_id
    left join public.ims_staff st on st.id = p.paid_by
  ),
  'money', (select jsonb_build_object('amount', m.amount, 'discount_taken', m.discount_taken, 'alloc_sum', m.alloc_sum, 'gap', m.gap) from m),
  'allocs', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'target_kind', target_kind, 'target_id', target_id, 'target_number', target_number, 'target_status', target_status,
                                        'supplier_id', supplier_id, 'supplier_name', supplier_name, 'currency_code', currency_code, 'amount', amount, 'note', note,
                                        'doc_total', doc_total, 'doc_paid_total', doc_paid_total, 'doc_unpaid', doc_unpaid)
                     order by target_kind, target_number)
    from al), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when m.gap <> 0 then 'gap_not_zero' end,
        case when not exists (select 1 from al) then 'no_allocs' end,
        case when exists (select 1 from al where al.doc_currency_id <> p.currency_id) then 'mixed_currency' end,
        case when exists (select 1 from al where al.target_status <> 'confirmed') then 'alloc_on_unconfirmed_doc' end,
        case when (select count(distinct supplier_id) from al) > 1 then 'mixed_supplier' end
      ], null)) as w
      from p cross join m) t
  )
) end;
$$;

-- ═══ ③-10 po_detail 재발행(목록 밖 · 이유: po.html 상세가 charges[].total_amount 와 unpaid 를 나란히 그린다 — 세금 전 · 세금 포함을 가르려면 열쇠 둘) — 마지막 정의 20261008170700 · chg CTE · charges[] tax_amount · total_with_tax ═══
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
         coalesce((select sum(amount) from public.po_charge_alloc where po_id = p_po_id), 0) as charge_total,
         (select case when bool_or(g.rate_pct is null) then null else sum(g.tax_amount) end
            from public.po_tax_group g where g.doc_kind = 'po' and g.doc_id = p_po_id)   as tax_amount,        -- po-tax-1 · 예상 세금(규칙 모르는 묶음이 있으면 null)
         (select bool_or(g.tax_rule_id is null) from public.po_tax_group g where g.doc_kind = 'po' and g.doc_id = p_po_id) as tax_rule_missing
),
txg as (                                      -- po-tax-1 · 규칙 묶음마다(화면이 「HST ON 13% 1,202.44 · Zero-rated 0.00」로 그린다)
  select * from public.po_tax_group g where g.doc_kind = 'po' and g.doc_id = p_po_id
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
         m.line_count, m.goods_sum, m.other_sum, m.factor, m.computed_total, m.diff, m.tax_amount,
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
         m.line_count, m.goods_sum, m.other_sum, m.factor, m.computed_total, m.diff, m.payable_net, m.tax_amount,
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
         m.paid, m.unpaid, m.alloc_sum, m.unallocated, m.total_with_tax                                   -- po-tax-2 · tax_amount 는 c.* 에 이미 있다(1회차 42702 ambiguous)
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
      'tax_rule_id', p.tax_rule_id, 'rate_pct', tr.rate_pct,                                        -- po-tax-1 · FK · 머리 세율
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
    left join public.ref_tax_rule tr on tr.id = p.tax_rule_id
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
      'unit_price', unit_price, 'amount', amount, 'tax_rule', tax_rule, 'tax_rule_id', tax_rule_id, 'note', note) order by line_no)   -- tax_rule null = 머리를 따른다 · po-tax-1 tax_rule_id
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
      'received_qty', received_qty,
      -- ── po-tax-1 · 예상 세금(문서 통화 · 원가 아님) ──
      'taxable_amount', round(subtotal * factor, 2),
      'tax_amount', tax_amount,
      'total_with_tax', round(subtotal * factor, 2) + tax_amount,
      'tax_groups', coalesce((select jsonb_agg(jsonb_build_object('tax_rule_id', g.tax_rule_id, 'tax_rule', g.tax_rule, 'rate_pct', g.rate_pct, 'line_count', g.line_count,
                                                                  'taxable_amount', g.taxable_amount, 'discount_amount', g.discount_amount, 'tax_amount', g.tax_amount)
                                               order by g.tax_rule nulls last) from txg g), '[]'::jsonb))
    from tot
  ),
  'warnings', (                                 -- po-tax-1 · 규칙 없는 줄 · 세금 포함 단가 표시
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select tax_rule_missing from tot) then 'tax_rule_missing' end,
        case when (select tax_inclusive from p) then 'tax_inclusive_not_supported' end
      ], null)) as w) t
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
      'tax_amount', tax_amount,                                                            -- po-tax-1
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
      'tax_amount', tax_amount,                                                            -- po-tax-1
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
      'tax_amount', tax_amount, 'total_with_tax', total_with_tax,                            -- po-tax-2 · 세금 전 · 찍힌 세금 · 낼 돈
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

-- ═══ ③-11 inv_transfer_detail 재발행(목록 밖 · 이유: transfers.html 이 charges[].total_amount 를 그린다 — 같은 둘) — 마지막 정의 20260929025719 ═══
create or replace function public.inv_transfer_detail(p_transfer_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select case when not public.ims_can_view('transfer') then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(x) || jsonb_build_object('from_warehouse', fw.name, 'to_warehouse', tw.name, 'created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', p.name, 'qty', l.qty, 'qty_sent', l.qty_sent, 'short_sent', case when l.qty_sent is not null and l.qty_sent < l.qty then l.qty - l.qty_sent end, 'qty_received', l.qty_received, 'qty_lost', l.qty_lost, 'qty_returned', l.qty_returned, 'qty_extra', l.qty_extra, 'pack_factor', l.pack_factor,
                                                              'qty_ea', l.qty * l.pack_factor, 'stock_product_id', coalesce(p.parent_product_id, p.id),
                                                              -- tr-4b(판정 79 · 화면 ⑥ 재료): 이 줄의 자식 레이어(line_ref = 줄 id 또는 줄 id:…)로 따라온 얹힌 원가(kind carried) — 운송 중 · 도착 창고 · 되돌린(출발 창고)
                                                              'carried', (select jsonb_build_object('in_transit', coalesce(sum(ca.amount) filter (where y.warehouse = 'IN_TRANSIT'), 0), 'arrived', coalesce(sum(ca.amount) filter (where y.warehouse = tw.name), 0),
                                                                                                    'returned', coalesce(sum(ca.amount) filter (where y.warehouse = fw.name), 0), 'total', coalesce(sum(ca.amount), 0))
                                                                            from public.inv_layer y join public.inv_layer_cost_add ca on ca.layer_id = y.id and ca.kind = 'carried'
                                                                           where y.origin_type = 'transfer' and y.doc_number = x.transfer_number and (y.line_ref = l.id::text or y.line_ref like l.id::text || ':%'))) order by l.line_no), '[]'::jsonb)
                  from public.inv_transfer_line l join public.product p on p.id = l.product_id where l.transfer_id = x.id),
      'shortage', case when x.status = 'draft' then public.inv_transfer_shortage(x.id) else '[]'::jsonb end,
      -- tr-4(판정 67 · 묶음 일곱 · 화면 ⑥ 재료): 이 트랜스퍼에 배분된 비용 문서 — 문서별 금액(자기 통화) · CAD(기준통화면 ×1 · 아니면 × exchange_rate · 취소 제외) · 레이어에 얹힌 금액(cost_add landed · 배분 줄 단위)
      'freight', (select jsonb_build_object(
                    'total_cad', coalesce(sum(case when c.status <> 'cancelled' then a.amount * case when cu.code is not distinct from k.value then 1 else coalesce(c.exchange_rate, 0) end end), 0),
                    'posted_cad', coalesce(sum(pc.posted), 0),
                    'charges', coalesce(jsonb_agg(jsonb_build_object('charge_id', c.id, 'charge_number', c.charge_number, 'supplier_id', c.supplier_id, 'supplier_name', s.name, 'kind', c.kind, 'status', c.status, 'charge_date', c.charge_date, 'due_date', c.due_date,
                                                                'currency_code', cu.code, 'exchange_rate', c.exchange_rate, 'total_amount', c.total_amount, 'tax_amount', c.tax_amount, 'total_with_tax', c.total_amount + c.tax_amount /* po-tax-2 · 세금 전 · 찍힌 세금 · 낼 돈 */, 'alloc_id', a.id, 'amount', a.amount, 'posted_cad', coalesce(pc.posted, 0), 'layers', coalesce(pc.n, 0), 'description', c.description) order by c.charge_date, c.charge_number), '[]'::jsonb))
                  from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id join public.supplier s on s.id = c.supplier_id join public.ref_currency cu on cu.id = c.currency_id
                  left join public.inv_config k on k.key = 'base_currency'
                  left join lateral (select sum(ca.amount) as posted, count(*) as n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text) pc on true
                  where a.transfer_id = x.id))
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by left join public.ims_staff fb on fb.id = x.confirmed_by
     where x.id = p_transfer_id) end;
$$;

-- ═══ ④ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'po_charge' and column_name in ('tax_amount', 'tax_rule_id', 'tax_rule');
  if v_n <> 3 then v_bad := v_bad || format(' columns(%s)', v_n); end if;
  if (select count(*) from pg_constraint where conname = 'po_charge_tax_rule_pair_ck') <> 1 then v_bad := v_bad || ' check'; end if;
  if (select count(*) from pg_trigger where tgname = 'po_charge_tax_rule_pair' and not tgisinternal) <> 1 then v_bad := v_bad || ' trigger'; end if;
  select count(*) into v_n from public.po_charge where tax_rule_id is null and tax_rule is not null;
  if v_n <> 0 then v_bad := v_bad || format(' pair(%s)', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('po_charge_create', 'po_charge_confirm', 'po_charge_detail', 'tf_charge_create', 'tf_charge_update', 'tf_charge_confirm', 'po_payment_target_check', 'po_payment_detail', 'po_detail', 'inv_transfer_detail') and p.prosrc like '%po-tax-2%';
  if v_n <> 10 then v_bad := v_bad || format(' bodies(%s)', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('po_charge_create', 'po_charge_confirm', 'po_charge_detail', 'tf_charge_create', 'tf_charge_update', 'tf_charge_confirm', 'po_payment_target_check', 'po_payment_detail', 'po_detail', 'inv_transfer_detail');
  if v_n <> 10 then v_bad := v_bad || format(' duplicate-signatures(%s)', v_n); end if;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'po_charge_money';
  if v_n <> 13 then v_bad := v_bad || format(' po_charge_money_columns(%s)', v_n); end if;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'po_charge_list';
  if v_n <> 28 then v_bad := v_bad || format(' po_charge_list_columns(%s)', v_n); end if;
  if v_bad <> '' then raise exception 'po-tax-2 self-check failed:% — nothing was applied', v_bad; end if;
end $$;
