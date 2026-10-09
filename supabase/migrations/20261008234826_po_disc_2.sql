-- ─────────────────────────────────────────────────────────────
-- 공급처 할인 → 재고 원가 ② — 입고 기준 단가 = 확정 인보이스의 실제 단가 · 원가 재료 핀(po_receipt_cost) · 식 한 곳(po_invoice_discount_factor · po_invoice_line_cost) · 입고된 인보이스 취소 막기 (Asung-IMS · po-disc-2 · 2026-10-08)
--   정본(뒤에 적는다): so-module §53 판정 390 · 392 · 394 · 396 · 398(2026-10-08 · Caleb) · po-module §11-e 끝 「(나) 인보이스 실제 단가」 · §11-i 「입고 원가의 재료」 · §13-j
--   판정 392  입고 원가 = 확정 인보이스 단가 × 인보이스 체인 × 인보이스 환율(처음부터) · 입고 뒤 바뀌는 길은 공통 조정 장치(po-disc-3 · 5)
--   판정 394  입고 순간 값으로 못 박는다 — 이 차수의 핀 po_receipt_cost(receipt · PO 줄마다 한 행 · append-only) · 재생성은 핀을 읽는다
--   판정 396  입고가 있는 공급처 인보이스는 취소를 막는다(po_doc_cancel · 다시 열기와 같은 검사) — 크레딧으로 바로잡는다
--   판정 398  돈을 내지 않은 줄(is_payable false · unit_price 0)로 온 물건의 원가는 0 · 같은 PO 줄에 섞이면 낸 돈 ÷ 받은 개수(평균) · po_price_history 의 거름은 그대로(가격 이력은 낸 단가만)
--   ⬜1 핀 자리 = 새 표 po_receipt_cost — po_receipt_line 은 빈마다 한 행이고 레이어는 (입고 · PO 줄 · 창고)마다 하나라 빈 행에 적으면 같은 값이 행마다 복제된다
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 셋 — inv_layer_post_receipt(마지막 정의 20261008193337:54~161 위에 · 바뀐 줄은 보고의 diff) · po_doc_cancel(20260918000000:468~679 바이트 복사 + declare 1 · 검사 블록 1) · po_price_history(20260920163231:32~109 · 출력 바이트 그대로 · 식만 함수로)
--   원칙 1: IMS 는 Cin7 없이 돈다 — 원가의 재료는 IMS 인보이스 · IMS 입고 · IMS 환율
-- ─────────────────────────────────────────────────────────────
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

-- ═══ ① po_receipt_cost — 이 입고가 이 PO 줄의 레이어를 처음 세운 순간의 원가 재료(판정 394 · 398 · append-only) ═══
create table public.po_receipt_cost (
  id                   uuid primary key default gen_random_uuid(),
  receipt_id           uuid not null references public.po_receipt (id) on delete no action,
  po_line_id           uuid not null references public.po_line (id) on delete no action,
  source               text not null,                                                   -- invoice | po
  invoice_id           uuid references public.po_invoice (id) on delete no action,      -- source invoice 일 때 not null(짝 CHECK)
  invoice_line_ids     uuid[],                                                          -- 그 인보이스에서 이 PO 줄을 가리킨 goods 줄들(무상 줄 포함 · 음수 줄 제외)
  qty_basis            numeric,                                                         -- 인보이스 줄 qty_ea 합(평균의 분모 · source po 면 null)
  amount_basis         numeric,                                                         -- 낸 돈 합(문서 통화 · 체인 뒤 · 무상 줄 0 · source po 면 null)
  unit_price_net       numeric not null,                                                -- 문서 통화 · 반올림 없음 = amount_basis ÷ qty_basis (po 면 po_line.unit_price × PO 계수)
  discount_factor      numeric not null,                                                -- 인보이스 체인(invoice) | PO 체인(po · po_receipt.discount_factor 와 같다)
  currency_id          uuid references public.ref_currency (id) on delete no action,
  exchange_rate        numeric,                                                         -- CAD per 통화 · 기준통화면 null
  exchange_rate_source text,                                                            -- invoice | po | null(기준통화)
  unit_cost_cad        numeric not null,                                                -- 레이어 단가 그대로(반올림 없음)
  pinned_at            timestamptz not null default now(),
  builder              text,
  constraint po_receipt_cost_source_ck       check (source in ('invoice', 'po')),
  constraint po_receipt_cost_invoice_pair_ck check ((source = 'invoice') = (invoice_id is not null)),
  constraint po_receipt_cost_fx_source_ck    check (exchange_rate_source is null or exchange_rate_source in ('invoice', 'po')),
  constraint po_receipt_cost_fx_pair_ck      check ((exchange_rate is null) = (exchange_rate_source is null)),
  constraint po_receipt_cost_uq              unique (receipt_id, po_line_id)
);
create index po_receipt_cost_po_line_idx on public.po_receipt_cost (po_line_id);
create index po_receipt_cost_invoice_idx on public.po_receipt_cost (invoice_id);
alter table public.po_receipt_cost enable row level security;
create policy po_receipt_cost_select on public.po_receipt_cost for select to authenticated using (true);
create policy po_receipt_cost_insert on public.po_receipt_cost for insert to authenticated with check ((select public.ims_can_write('receiving')));
revoke all on public.po_receipt_cost from public, anon;
revoke update, delete, truncate, references, trigger on public.po_receipt_cost from authenticated;   -- 기본 권한이 전부 준다(pg_default_acl) — 넣기 · 읽기만 남긴다 · append-only(고치지 않는다 · 지우지 않는다)
grant select, insert on public.po_receipt_cost to authenticated;
comment on table public.po_receipt_cost is 'po-disc-2 ⭐ 입고 원가 재료 핀(판정 394 · 398 · 2026-10-08) — 한 행 = 이 입고(receipt_id)가 이 PO 줄(po_line_id)의 레이어를 처음 세운 순간의 재료 · source invoice(확정 인보이스 줄 · unit_price_net = 낸 돈 ÷ 받은 개수 · 무상 줄은 개수만) | po(인보이스 줄 없음 · po_line.unit_price × PO 체인) · exchange_rate(CAD per 통화 · 기준통화면 null) · unit_cost_cad = 레이어 단가 그대로 · 창구 inv_layer_post_receipt 가 레이어를 만들 때만 적고 다음부터는 이 값을 쓴다(재생성이 같은 값 · 그 뒤 인보이스 · PO 환율 · 할인이 바뀌어도 그대로 — 바뀐 몫은 공통 조정 장치 po-disc-3 · 5) · append-only(update · delete 정책 없음 · 권한도 없음) · 쓰기는 창구만(insert 정책 receiving — 재생성 로그인도 receiving 을 가진다)';

-- ═══ ② 식 한 곳 — 인보이스 할인 계수 · 인보이스 줄 원가 ═══
create function public.po_invoice_discount_factor(p_invoice_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce((select public.po_mul(1 - d.percent / 100) from public.po_invoice_discount d where d.po_invoice_id = p_invoice_id), 1);
$$;
revoke all on function public.po_invoice_discount_factor(uuid) from public, anon;
grant execute on function public.po_invoice_discount_factor(uuid) to authenticated;
comment on function public.po_invoice_discount_factor(uuid) is 'po-disc-2 ⭐ 인보이스 할인 체인 계수 한 곳 — po_invoice_discount 줄의 (1 − percent/100) 을 곱한다(po_mul · 더하지 않는다 · §11-e) · 줄 없으면 1 · po_invoice_money.factor 와 같은 식(검증 S12 가 전 인보이스에서 대조 · 그 뷰를 이 함수로 바꾸는 것은 미룬 141) · po_discount_factor 와 같은 모양 · po_invoice_line_cost · inv_layer_post_receipt 가 부른다';

create function public.po_invoice_line_cost(p_invoice_line_id uuid)
  returns table (factor numeric, net_unit numeric, exchange_rate numeric, exchange_rate_source text, net_unit_cad numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select f.factor,
         il.unit_price * f.factor                                                       as net_unit,
         fx.rate                                                                        as exchange_rate,
         fx.src                                                                         as exchange_rate_source,
         case when fx.is_base then il.unit_price * f.factor
              when fx.rate is not null then il.unit_price * f.factor * fx.rate end      as net_unit_cad
  from public.po_invoice_line il
  join public.po_invoice i on i.id = il.po_invoice_id
  left join public.po_line pl on pl.id = il.po_line_id
  left join public.po x on x.id = pl.po_id
  cross join lateral (select public.po_invoice_discount_factor(i.id) as factor) f
  cross join lateral (
    select (cur.code is not distinct from b.code) as is_base,
           case when cur.code is not distinct from b.code then null
                when i.exchange_rate is not null and i.exchange_rate > 0 then i.exchange_rate
                when x.currency_id = i.currency_id and x.exchange_rate is not null and x.exchange_rate > 0 then x.exchange_rate end as rate,
           case when cur.code is not distinct from b.code then null
                when i.exchange_rate is not null and i.exchange_rate > 0 then 'invoice'
                when x.currency_id = i.currency_id and x.exchange_rate is not null and x.exchange_rate > 0 then 'po' end as src
    from public.ref_currency cur
    left join (select k.value as code from public.inv_config k where k.key = 'base_currency') b on true
    where cur.id = i.currency_id) fx
  where il.id = p_invoice_line_id;
$$;
revoke all on function public.po_invoice_line_cost(uuid) from public, anon;
grant execute on function public.po_invoice_line_cost(uuid) to authenticated;
comment on function public.po_invoice_line_cost(uuid) is 'po-disc-2 ⭐ 인보이스 줄 하나의 원가 재료 한 곳(반올림 없음) — factor(인보이스 체인) · net_unit = unit_price × factor(문서 통화) · exchange_rate(CAD per 통화 · 기준통화면 null · 인보이스 환율 > 0 → invoice · 인보이스 통화 = PO 통화이고 PO 환율 > 0 → po · 아니면 null = 남의 환율은 쓰지 않는다) · net_unit_cad(환율 없으면 null · 0 아님) · 뷰 po_price_history 가 줄마다 부른다(표시는 round 6) · SQL stable(인라인)';

-- ═══ ③ po_price_history 재발행 — 마지막 정의 20260920163231:32~109 · 출력(칸 순서 · 이름 · round 6 · 거름 넷) 바이트 그대로 · 계수 · 환율 · CAD 는 po_invoice_line_cost 한 곳 · security_invoker · 권한 · comment 유지 ═══
create or replace view public.po_price_history
  with (security_invoker = true) as
with base as (
  select k.value as code from public.inv_config k where k.key = 'base_currency'
),
disc as (                                                                           -- 사람이 읽는 할인 문장 · seq 순(곱해지는 차례) · 계수는 po_invoice_line_cost 가 정본(여기서 다시 곱하지 않는다)
  select d.po_invoice_id,
         string_agg(d.name || ' ' || case when d.percent = trunc(d.percent) then trunc(d.percent)::text else rtrim(d.percent::text, '0') end || '%', ' · ' order by d.seq) as discount_label,   -- 17 → 「17%」 · 17.5 → 「17.5%」(to_char FM 은 정수 끝에 '.' 을 남길 수 있어 안 쓴다)
         count(*)::int as discount_count
  from public.po_invoice_discount d
  group by d.po_invoice_id
),
cr as (                                                                             -- 이 인보이스에 걸린 크레딧(취소 제외) — 표시만 · 값은 이번 판에 안 섞는다
  select c.credit_for_invoice_id as invoice_id,
         count(*)::int as credit_count,
         string_agg(c.invoice_number, ' · ' order by c.invoice_date, c.invoice_number) as credit_numbers
  from public.po_invoice c
  where c.doc_kind = 'credit' and c.status <> 'cancelled' and c.credit_for_invoice_id is not null
  group by c.credit_for_invoice_id
)
select
  pr.id                                   as product_id,
  pr.sku,
  pr.name                                 as product_name,
  i.supplier_id,
  s.name                                  as supplier_name,
  i.id                                    as invoice_id,
  i.invoice_number,                                                                 -- 공급처가 준 번호(우리 채번 아님) — supplier_ref_number 는 크레딧 전용 칸이라 여기 없다
  i.invoice_date,
  x.id                                    as po_id,
  x.po_number,
  il.id                                   as invoice_line_id,
  il.qty_ea                               as qty,
  il.unit_price                           as gross_unit,                            -- 인보이스에 적힌 값(할인 전 · 인보이스 통화)
  c.factor,                                                                         -- 할인 계수(원래 자릿수 · 1 이면 할인 없음) · 정본 po_invoice_line_cost(po-disc-2 · = po_invoice_money.factor)
  round(c.net_unit, 6)                    as net_unit,                              -- ⭐ 실제 매입 단가(할인 반영 · 인보이스 통화)
  dc.discount_label,                                                                -- 「Trade 17% · Damage 1%」 · 없으면 null
  coalesce(dc.discount_count, 0)          as discount_count,
  cur.code                                as currency_code,                         -- 인보이스 통화 = 이 줄의 기준
  (cur.code is not distinct from b.code)  as is_base_currency,                      -- 기준통화면 화면이 CAD 를 따로 그리지 않는다
  c.exchange_rate,                                                                  -- CAD per 통화 · 곱한다(원가 레이어와 같은 방향) · po-disc-2: 식 한 곳
  c.exchange_rate_source,                                                           -- invoice · po · null(환율 없음)
  round(c.net_unit_cad, 6)                as net_unit_cad,                          -- ⚠️ 환율 없으면 null — 0 으로 채우지 않는다
  (cr.credit_count is not null)           as has_credit,                            -- 취소되지 않은 크레딧이 걸려 있다 — 「정정이 붙어 있다」 표시만
  coalesce(cr.credit_count, 0)            as credit_count,
  cr.credit_numbers,
  i.confirmed_at
from public.po_invoice_line il
join public.po_invoice       i   on i.id  = il.po_invoice_id
join public.po_line          pl  on pl.id = il.po_line_id
join public.po               x   on x.id  = pl.po_id
join public.product          pr  on pr.id = pl.product_id
join public.supplier         s   on s.id  = i.supplier_id
join public.ref_currency     cur on cur.id = i.currency_id
cross join lateral public.po_invoice_line_cost(il.id) c
left join base b   on true
left join disc dc  on dc.po_invoice_id = i.id
left join cr       on cr.invoice_id = i.id
where i.doc_kind = 'invoice'
  and i.status   = 'confirmed'
  and il.line_kind = 'goods'                                                        -- 할인은 goods 에만 · charge/other 는 가격이 아니다
  and il.is_payable                                                                 -- ⓐ 우리 쓸 것 · ⓑ 공짜 — 둘 다 가격이 아니다(판정 398: 원가는 0 · 평균이 되지만 가격 이력은 낸 단가만)
  and il.unit_price > 0                                                             -- 0 은 가격으로 읽힌다(샘플)
  and il.qty_ea > 0;                                                                -- 음수는 정정 줄
comment on view public.po_price_history is '⭐ 매입 가격 이력(2026-09-20) — 한 줄 = 확정 인보이스(doc_kind invoice · confirmed)의 goods·payable 줄 하나 = 「이 SKU 를 이 공급처에서 이날 실제로 얼마에 샀나」. 출처는 인보이스(공급처가 준 실제 값 · 발주는 우리가 적은 값 · 입고는 수량의 사실). net_unit = round(unit_price × factor, 6) · factor 는 po_invoice_money(할인 체인 정본 · 차례로 곱한다) · discount_label 은 「Trade 17% · Damage 1%」(seq 순). 통화는 인보이스 통화가 기준 · 기준통화면 is_base_currency=true · 환율 null · net_unit_cad = net_unit. 외화 환율은 인보이스 → 같은 통화의 발주 → null(exchange_rate_source) · ⚠️ 환율 없으면 net_unit_cad 는 null(0 아님). 거름: goods 아님 · is_payable=false(우리 쓸 것·공짜) · unit_price 0 · qty_ea ≤ 0 — 빠진 줄은 po_price_history_skipped 에 이유와 함께. 크레딧은 이번 판에 안 섞는다 — has_credit·credit_numbers 로 표시만. ⚠️ 1센트: Σ round(net_unit×qty,2) ≠ 문서 총액이 정상(끊는 횟수 차이 · AMP-778812 2,010.53 vs 2,010.54) — 원가에 쓰게 되면 레이어 배분 방식으로 맞춘다. 세트 환산 없음(세트로 주문하지 않는다). SKU 하나는 PostgREST 필터(?sku=eq.…&order=invoice_date.desc) · 전체 조회는 1,000행 상한 주의. security_invoker. 정본 po-module §11-e·§11-g';
revoke all on public.po_price_history from anon;
grant select on public.po_price_history to authenticated;

-- ═══ ④ inv_layer_post_receipt 재발행 — 마지막 정의 20261008193337:54~161(DB md5 54d8ad6d · 검증 G0) 위에 · 단가 순서 핀 → 확정 인보이스(판정 392 · 398) → PO 기준(po-disc-1 그대로) · 핀은 이 호출이 레이어를 만들 때만 ═══
create or replace function public.inv_layer_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt@2026-10-08.3';   -- po-disc-2: 핀 → 확정 인보이스 실제 단가(낸 돈 ÷ 받은 개수 · 인보이스 체인 · 인보이스 환율) → PO 기준
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_cur      text;
  v_base     text;
  v_factor   numeric;                 -- PO 통화 → CAD 계수(PO 기준 폴백에만) · 기준통화면 1 · 아니면 po.exchange_rate · 없으면 null(PO 기준을 쓰는 줄에서만 거부)
  v_disc     numeric;                 -- po-disc-1 · PO 할인 체인 계수(1 = 할인 없음) — 입고에 적힌 값 · 없으면 지금 체인(po_discount_factor)을 읽어 적는다
  v_disc_src text;                    -- po-disc-1 · receipt_stored | po_discount_now
  v_created  int := 0;
  v_existing int := 0;
  v_qty      numeric := 0;
  v_cost     numeric := 0;
  v_rows     int := 0;
  v_price    numeric;
  v_unit     numeric;
  v_layer_id bigint;
  v_lines    jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
  x          record;
  -- po-disc-2
  v_pin      public.po_receipt_cost%rowtype;
  v_inv      record;                  -- 확정 인보이스(이 PO 줄 · confirmed_at 가장 늦은 것) — id · invoice_number · currency_id · exchange_rate
  v_basis    text;                    -- pinned | invoice | po
  v_qty_b    numeric;                 -- 인보이스 줄 qty 합(양수 줄)
  v_amt_b    numeric;                 -- 낸 돈 합(체인 뒤 · 문서 통화)
  v_ifactor  numeric;                 -- 이 줄에 쓴 할인 체인(인보이스 · 또는 PO)
  v_net      numeric;                 -- 문서 통화 단가(반올림 없음)
  v_fx       numeric;                 -- 이 줄에 쓴 환율(기준통화면 null)
  v_fx_src   text;                    -- invoice | po | null
  v_fx_cur   uuid;                    -- 이 줄의 통화(인보이스 또는 PO)
  v_icur     text;
  v_ids      uuid[];
  v_n_inv    int;
  v_inv_no   text;
  v_fx_seen  jsonb := '[]'::jsonb;    -- 반환 fx_rates — 실제로 쓴 (출처 · 환율) 묶음
begin

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — no cost layers were created', p_receipt_id; end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — cost layers are built for confirmed receipts only — no cost layers were created', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — no cost layers were created', v_r.receipt_number; end if;

  -- 통화 · 환율 — PO 환율은 PO 기준 폴백에만 쓴다(인보이스 기준 줄은 인보이스 환율) · 없으면 그 줄에서 거부
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base from public.inv_config k where k.key = 'base_currency';
  if v_base is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — no cost layers were created'; end if;
  if v_cur is distinct from v_base then
    -- ⚠️⚠️⚠️ po.exchange_rate 는 CAD per USD 다 — unit_price(USD) × exchange_rate = CAD. 곱한다. 나누면 원가가 반으로 줄어드는데 에러가 안 난다.
    v_factor := case when v_po.exchange_rate is not null and v_po.exchange_rate > 0 then v_po.exchange_rate end;
  else
    v_factor := 1;                                                                                          -- 기준통화(CAD) — 환율을 곱하지 않는다(정본 1239행 「이미 CAD」)
    if v_po.exchange_rate is not null and v_po.exchange_rate <> 1 then v_warn := array_append(v_warn, 'exchange_rate_ignored_base_currency'); end if;
  end if;

  -- po-disc-1 · PO 할인 계수 — ⭐ 입고 확정 순간의 체인(그 뒤 PO 할인이 바뀐 몫은 (나) 인보이스 차액 차수) · 처음 세울 때 po_receipt 에 적어 재생성이 같은 값을 쓴다
  if v_r.discount_factor is not null then
    v_disc := v_r.discount_factor; v_disc_src := 'receipt_stored';
  else
    v_disc := public.po_discount_factor(v_po.id); v_disc_src := 'po_discount_now';
    update public.po_receipt set discount_factor = v_disc where id = p_receipt_id and discount_factor is null;
  end if;

  -- 원장 행을 라인 단위로 접는다(bin 을 버린다 · 이견 2 · 3) — 이 RCV 의 ims po_in 행만
  for x in
    select l.line_ref, l.sku, l.warehouse, sum(l.qty_delta) as qty, min(l.occurred_on) as received_on, count(*)::int as ledger_rows
    from public.inv_ledger l
    where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in'
      and l.doc_number = v_r.receipt_number and l.qty_delta > 0
      and l.line_ref not like '%:over' and l.line_ref not like '%:offpo'                                -- ⑤-6c1 off-PO 행은 형제 창구 inv_layer_post_receipt_off_po 가 만든다(라인이 없어 po_line 조회가 안 된다)                                                              -- ⭐ 2026-09-20 초과분 행(over 닫기 · line_ref = po_line_id||':over')은 형제 창구 inv_layer_post_receipt_over 가 만든다 — 여기서 접으면 po_line 을 못 찾아 터지거나(접미어) free 를 발주 단가로 매긴다
    group by l.line_ref, l.sku, l.warehouse
    order by l.line_ref
  loop
    v_rows := v_rows + x.ledger_rows;
    -- 멱등 — 같은 4키의 레이어가 있으면 건너뛴다(inv_layer_apply_po_in 과 같은 규칙) · ⚠️ po-disc-2: 있는 레이어에는 핀을 쓰지 않는다(레이어와 다른 값을 적을 수 있다 — 기존 레이어는 전환 재생성이 처음 부르며 핀다)
    if exists (select 1 from public.inv_layer y
                where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = x.line_ref
                  and y.sku = x.sku and y.warehouse = x.warehouse) then
      v_existing := v_existing + 1;
      continue;
    end if;
    -- 단가 — line_ref 가 po_line_id 다(원장 이식 2차 · Caleb 실측 확정)
    select pl.unit_price into v_price from public.po_line pl where pl.id::text = x.line_ref;
    if v_price is null then
      raise exception 'Ledger row % / % on % points at a PO line (%) that does not exist — the ledger is wrong, not this function — no cost layers were created', x.sku, x.warehouse, v_r.receipt_number, x.line_ref;
    end if;

    -- ═══ po-disc-2 · 단가 순서: ① 핀 → ② 확정 인보이스(판정 392 · 398) → ③ PO 기준(po-disc-1) ═══
    v_pin := null; v_inv := null; v_basis := null; v_qty_b := null; v_amt_b := null; v_ifactor := null; v_net := null; v_fx := null; v_fx_src := null; v_fx_cur := null; v_ids := null; v_icur := null; v_inv_no := null;
    select * into v_pin from public.po_receipt_cost k where k.receipt_id = p_receipt_id and k.po_line_id = x.line_ref::uuid;
    if found then
      v_basis := 'pinned'; v_unit := v_pin.unit_cost_cad; v_net := v_pin.unit_price_net; v_fx := v_pin.exchange_rate; v_fx_src := v_pin.exchange_rate_source; v_ifactor := v_pin.discount_factor; v_fx_cur := v_pin.currency_id;
      v_qty_b := v_pin.qty_basis; v_amt_b := v_pin.amount_basis;
      select i.invoice_number into v_inv_no from public.po_invoice i where i.id = v_pin.invoice_id;
    else
      -- ② 확정 인보이스 — 이 PO 줄을 가리키는 goods 줄이 있는 confirmed invoice · 둘 이상이면 confirmed_at 이 가장 늦은 것 + 경고
      select count(distinct i.id) into v_n_inv
        from public.po_invoice i join public.po_invoice_line il on il.po_invoice_id = i.id
       where i.doc_kind = 'invoice' and i.status = 'confirmed' and il.line_kind = 'goods' and il.po_line_id = x.line_ref::uuid;
      if v_n_inv > 1 then v_warn := array_append(v_warn, 'multiple_confirmed_invoices:' || x.line_ref); end if;
      select i.id, i.invoice_number, i.currency_id, i.exchange_rate into v_inv
        from public.po_invoice i
       where i.doc_kind = 'invoice' and i.status = 'confirmed'
         and exists (select 1 from public.po_invoice_line il where il.po_invoice_id = i.id and il.line_kind = 'goods' and il.po_line_id = x.line_ref::uuid)
       order by i.confirmed_at desc nulls last, i.invoice_number desc
       limit 1;
      if v_inv.id is not null then
        v_inv_no := v_inv.invoice_number;
        if exists (select 1 from public.po_invoice_line il where il.po_invoice_id = v_inv.id and il.line_kind = 'goods' and il.po_line_id = x.line_ref::uuid and il.qty_ea < 0) then
          v_warn := array_append(v_warn, 'negative_invoice_line_excluded:' || x.line_ref);                              -- ⬜2: 정정 줄은 평균에서 뺀다(실물 0)
        end if;
        v_ifactor := public.po_invoice_discount_factor(v_inv.id);
        select coalesce(sum(il.qty_ea), 0),
               coalesce(sum(il.unit_price * il.qty_ea) filter (where il.is_payable and il.unit_price > 0), 0) * v_ifactor,
               array_agg(il.id order by il.line_no)
          into v_qty_b, v_amt_b, v_ids
          from public.po_invoice_line il
         where il.po_invoice_id = v_inv.id and il.line_kind = 'goods' and il.po_line_id = x.line_ref::uuid and il.qty_ea > 0;
        if v_qty_b > 0 then
          v_basis := 'invoice';
          v_net := v_amt_b / v_qty_b;                                                                              -- 판정 398: 낸 돈 ÷ 받은 개수(무상 줄은 개수만) · 반올림 없음
          v_fx_cur := v_inv.currency_id;
          select c.code into v_icur from public.ref_currency c where c.id = v_inv.currency_id;
          if v_icur is not distinct from v_base then
            v_fx := null; v_fx_src := null; v_unit := v_net;
          elsif v_inv.exchange_rate is not null and v_inv.exchange_rate > 0 then
            v_fx := v_inv.exchange_rate; v_fx_src := 'invoice'; v_unit := v_net * v_fx;
          elsif v_inv.currency_id = v_po.currency_id and v_po.exchange_rate is not null and v_po.exchange_rate > 0 then
            v_fx := v_po.exchange_rate; v_fx_src := 'po'; v_unit := v_net * v_fx;
          else
            raise exception 'Invoice % (PO %) is in % but has no % per % exchange rate, and the order''s rate is not for % — stock cost cannot be worked out. Enter the rate in the invoice header ("Exchange rate") and run again — no cost layers were created',
              v_inv.invoice_number, v_po.po_number, coalesce(v_icur, '?'), v_base, coalesce(v_icur, '?'), coalesce(v_icur, '?');
          end if;
        end if;
      end if;
      if v_basis is null then
        -- ③ PO 기준(인보이스 줄 없음) — po-disc-1 그대로 · 경고
        v_basis := 'po'; v_warn := array_append(v_warn, 'no_invoice_line:' || x.line_ref);
        if v_factor is null then
          raise exception 'PO % is in % but has no % per % exchange rate, and line % has no confirmed invoice line to take the rate from — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and run again — no cost layers were created',
            v_po.po_number, coalesce(v_cur, '?'), v_base, coalesce(v_cur, '?'), x.sku;
        end if;
        v_ifactor := v_disc; v_net := v_price * v_disc; v_fx_cur := v_po.currency_id;
        if v_cur is distinct from v_base then v_fx := v_factor; v_fx_src := 'po'; else v_fx := null; v_fx_src := null; end if;
        -- ⚠️⚠️⚠️ CAD per USD × USD 단가 = CAD 단가. 곱한다. (기준통화면 v_factor = 1) · po-disc-1: × PO 할인 계수(체인 · 더하지 않는다) · 반올림 없음(옛 레이어와 같은 자릿수)
        v_unit := v_price * v_disc * v_factor;
      end if;
    end if;

    insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
    values (x.sku, x.warehouse, 'purchase', v_r.receipt_number, x.line_ref, null, x.received_on, true, x.qty, v_unit, 'po_line')
    returning id into v_layer_id;
    v_created := v_created + 1;
    v_qty  := v_qty  + x.qty;
    v_cost := v_cost + x.qty * v_unit;
    -- po-disc-2 · 핀 — 이 호출이 레이어를 만들 때만 · 판정 394(입고 순간 값으로 못 박는다)
    if v_basis <> 'pinned' then
      insert into public.po_receipt_cost (receipt_id, po_line_id, source, invoice_id, invoice_line_ids, qty_basis, amount_basis, unit_price_net, discount_factor, currency_id, exchange_rate, exchange_rate_source, unit_cost_cad, builder)
      values (p_receipt_id, x.line_ref::uuid, v_basis, case when v_basis = 'invoice' then v_inv.id end, v_ids, v_qty_b, v_amt_b, v_net, v_ifactor, v_fx_cur, v_fx, v_fx_src, v_unit, c_version);
    end if;
    if v_fx_src is not null and not (v_fx_seen @> jsonb_build_array(jsonb_build_object('source', v_fx_src, 'rate', v_fx))) then
      v_fx_seen := v_fx_seen || jsonb_build_object('source', v_fx_src, 'rate', v_fx);
    end if;
    v_lines := v_lines || jsonb_build_object('layer_id', v_layer_id, 'po_line_id', x.line_ref, 'sku', x.sku, 'warehouse', x.warehouse,
                                             'qty', x.qty, 'ledger_rows', x.ledger_rows, 'unit_price', v_price, 'unit_price_net', v_net, 'unit_cost_cad', v_unit, 'received_on', x.received_on,
                                             'cost_basis', v_basis, 'invoice_number', v_inv_no, 'discount_factor', v_ifactor, 'exchange_rate', v_fx, 'exchange_rate_source', v_fx_src,
                                             'qty_basis', v_qty_b, 'amount_basis', v_amt_b);   -- po-disc-2
  end loop;
  if v_rows = 0 then v_warn := array_append(v_warn, 'no_ledger_rows_for_receipt'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'currency', v_cur, 'base_currency', v_base,
    'fx_rates', v_fx_seen,                                                                   -- po-disc-2: 실제로 쓴 (출처 · 환율) 묶음 — 줄마다 lines[].exchange_rate · exchange_rate_source
    'fx_direction', case when jsonb_array_length(v_fx_seen) = 0 then v_base || ' — base currency or nothing created, no conversion (× 1)'
                         else v_base || ' per document currency — unit_price_net × rate · rate per line (see lines[].exchange_rate_source)' end,   -- ⚠️ 거짓이면 안 된다 — 쓴 환율은 줄마다 적는다
    'discount_factor', v_disc, 'discount_factor_source', v_disc_src,                      -- po-disc-1(PO 체인 · PO 기준 줄에만 쓴다)
    'ledger_rows', v_rows, 'layers_created', v_created, 'layers_existing', v_existing,
    'qty', v_qty, 'cost_total_cad', v_cost, 'cost_source', 'po_line', 'builder', c_version,
    'lines', v_lines, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.inv_layer_post_receipt(uuid) is '⭐ 원가의 창구(원가 이식 1차 · 2026-09-19) — 확정 입고 하나의 IMS 원장 행(po_in · source ims)을 라인 단위로 접어 inv_layer 를 만든다(키 = 원장 키 · bin 접기 · cost_source po_line · 멱등 4키). ⭐ po-disc-2(2026-10-08 · 판정 392 · 394 · 398) 단가 순서: ① 핀 po_receipt_cost(있으면 그대로 · 재생성이 같은 값) → ② 확정 인보이스 줄(이 PO 줄 · 둘 이상이면 confirmed_at 늦은 것 + 경고 multiple_confirmed_invoices) — 낸 돈(is_payable ∧ unit_price > 0 인 줄 × 인보이스 체인) ÷ 받은 개수(qty > 0 인 줄 전부 · 무상 줄은 개수만 · 음수 줄 제외 + 경고) × 환율(기준통화 null · 인보이스 환율 → 같은 통화의 PO 환율 → 아니면 거부 · 남의 환율은 쓰지 않는다) → ③ 인보이스 줄 없음 = PO 기준(po-disc-1 · unit_price × PO 체인(po_receipt.discount_factor) × PO 환율 · 경고 no_invoice_line) · 반올림 없음 · 핀은 이 호출이 레이어를 만들 때만 적는다(있는 레이어에는 안 적는다). 세금은 안 들어간다. 재생성 inv_layer_apply 가 같은 창구를 부른다(식 하나). off-PO · 초과분은 형제 창구. 반환 fx_rates · lines[].cost_basis(pinned|invoice|po) · invoice_number · unit_price_net · exchange_rate · exchange_rate_source · qty_basis · amount_basis. security invoker · append-only';

-- ═══ ⑤ po_doc_cancel 재발행 — 마지막 정의 20260918000000:468~679(DB md5 a49d6ec6 · 검증 G0) 바이트 복사 · declare 한 줄 · 인보이스 갈래에 검사 블록 하나(판정 396) ═══
create or replace function public.po_doc_cancel(
  p_target text,                          -- 'po' | 'invoice' | 'charge' | 'payment'(거부)
  p_id     uuid,
  p_cancel boolean default true
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff        uuid;
  v_po           public.po%rowtype;
  v_inv          public.po_invoice%rowtype;
  v_for          public.po_invoice%rowtype;
   v_rp           record;                                 -- po-disc-2 판정 396: 입고가 있는 PO(이 인보이스의 goods 줄이 가리키는)
  v_chg          public.po_charge%rowtype;
  v_label        text;
  v_m            record;
  v_m2           record;
  v_recv_n       int;
  v_recv_qty     numeric;
  v_n            int;
  v_txt          text;
  v_inv_txt      text;
  v_chg_txt      text;
  v_cred_txt     text;
  v_split_txt    text;
  v_new_status   text;
  v_unpaid_before numeric;
  v_unpaid_after  numeric;
  v_warn         text[] := '{}';
  v_doc          text;                                          -- ②-b: 0행 문장용 문서 이름(rowtype 이 null 로 덮이기 전에 든다)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  if p_target not in ('po', 'invoice', 'charge', 'payment') then
    raise exception 'p_target must be po, invoice, charge or payment — nothing was saved';
  end if;
  -- ⭐ 결제는 상태가 없다(⑦) — 취소가 아니라 삭제
  if p_target = 'payment' then
    raise exception 'A payment has no cancelled state — delete it instead (po_doc_delete with p_target payment) — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;

  -- ══════════ 발주 (100000 그대로) ══════════
  if p_target = 'po' then
    select * into v_po from public.po where id = p_id;
    if not found then raise exception 'PO % not found — nothing was saved', p_id; end if;
    v_doc := 'PO ' || v_po.po_number;

    if p_cancel then
      if v_po.status = 'cancelled' then
        raise exception 'PO % is already cancelled — nothing was saved', v_po.po_number;
      end if;
      if v_po.status = 'closed' then
        raise exception 'PO % is closed (receiving finished) — a closed order cannot be cancelled — nothing was saved', v_po.po_number;
      end if;
      select count(*), coalesce(sum(rl.qty_ea), 0) into v_recv_n, v_recv_qty
      from public.po_receipt_line rl join public.po_line pl on pl.id = rl.po_line_id
      where pl.po_id = p_id;
      if v_recv_n > 0 then
        raise exception 'PO % has % receipt line(s) (% EA received) — a received order cannot be cancelled; receipts are events — nothing was saved',
          v_po.po_number, v_recv_n, v_recv_qty;
      end if;

      select string_agg(distinct i.invoice_number, ', ' order by i.invoice_number) into v_inv_txt
      from public.po_invoice_line il
      join public.po_line pl on pl.id = il.po_line_id
      join public.po_invoice i on i.id = il.po_invoice_id
      where pl.po_id = p_id and i.status <> 'cancelled';
      if v_inv_txt is not null then v_warn := array_append(v_warn, 'has_invoices'); end if;

      select string_agg(distinct c.charge_number, ', ' order by c.charge_number) into v_chg_txt
      from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id
      where a.po_id = p_id and c.status <> 'cancelled';
      if v_chg_txt is not null then v_warn := array_append(v_warn, 'has_charges'); end if;

      select string_agg(k.invoice_number, ', ' order by k.invoice_number) into v_cred_txt
      from public.po_invoice k where k.credit_po_id = p_id and k.status <> 'cancelled';
      if v_cred_txt is not null then v_warn := array_append(v_warn, 'has_numbered_credits'); end if;

      select string_agg(c.po_number, ', ' order by c.po_number) into v_split_txt
      from public.po c where c.split_from_id = p_id;
      if v_split_txt is not null then v_warn := array_append(v_warn, 'has_split_children'); end if;

      update public.po set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
      where id = p_id returning * into v_po;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    else
      if v_po.status <> 'cancelled' then
        raise exception 'PO % is % — only a cancelled order can be restored — nothing was saved', v_po.po_number, v_po.status;
      end if;
      v_new_status := case when v_po.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_po;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    end if;

    return jsonb_build_object(
      'target', 'po', 'id', v_po.id, 'po_number', v_po.po_number, 'status', v_po.status,
      'cancelled_at', v_po.cancelled_at, 'confirmed_at', v_po.confirmed_at, 'restored', not p_cancel,
      'attached', jsonb_build_object('invoices', v_inv_txt, 'charges', v_chg_txt, 'numbered_credits', v_cred_txt, 'split_children', v_split_txt),
      'warnings', to_jsonb(v_warn));
  end if;

  -- ══════════ 비용 문서 (150000 그대로) ══════════
  if p_target = 'charge' then
    select * into v_chg from public.po_charge where id = p_id;
    if not found then raise exception 'Charge % not found — nothing was saved', p_id; end if;
    v_doc := 'Charge ' || v_chg.charge_number;
    select * into v_m from public.po_charge_money where id = p_id;

    if p_cancel then
      if v_chg.status = 'cancelled' then
        raise exception 'Charge % is already cancelled — nothing was saved', v_chg.charge_number;
      end if;
      if v_m.paid > 0 then
        select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
        from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
        where pa.po_charge_id = p_id;
        raise exception 'Charge % has payments applied (%) — cannot cancel while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
      end if;
      select count(*), string_agg(x.po_number, ', ' order by x.po_number) into v_n, v_chg_txt
      from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = p_id;
      if v_n > 0 then v_warn := array_append(v_warn, 'has_allocs'); end if;
      if v_chg.status = 'draft' then v_warn := array_append(v_warn, 'cancelled_from_draft'); end if;

      update public.po_charge set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
      where id = p_id returning * into v_chg;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    else
      if v_chg.status <> 'cancelled' then
        raise exception 'Charge % is % — only a cancelled document can be restored — nothing was saved', v_chg.charge_number, v_chg.status;
      end if;
      v_new_status := case when v_chg.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po_charge set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_chg;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    end if;

    return jsonb_build_object(
      'target', 'charge', 'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status,
      'cancelled_at', v_chg.cancelled_at, 'confirmed_at', v_chg.confirmed_at, 'restored', not p_cancel,
      'attached', jsonb_build_object('pos', v_chg_txt),
      'warnings', to_jsonb(v_warn));
  end if;

  -- ══════════ 인보이스 · 크레딧 (100000 그대로) ══════════
  select * into v_inv from public.po_invoice where id = p_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_doc := v_label || ' ' || v_inv.invoice_number;
  select * into v_m from public.po_invoice_money where id = p_id;

  if p_cancel then
    if v_inv.status = 'cancelled' then
      raise exception '% % is already cancelled — nothing was saved', v_label, v_inv.invoice_number;
    end if;
    if v_m.alloc_total > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_invoice_id = p_id;
      raise exception '% % has payments applied (%) — cannot cancel while paid/used; remove the payment allocation first — nothing was saved',
        v_label, v_inv.invoice_number, v_txt;
    end if;
    select count(*), string_agg(c.invoice_number, ', ' order by c.invoice_number) into v_n, v_txt
    from public.po_invoice c where c.credit_for_invoice_id = p_id and c.status <> 'cancelled';
    if v_n > 0 then
      raise exception 'Invoice % has % credit note(s) attached (%) — cancel or detach those first — nothing was saved',
        v_inv.invoice_number, v_n, v_txt;
    end if;
    if v_inv.doc_kind = 'credit' and v_inv.credit_for_invoice_id is not null then
      select * into v_m2 from public.po_invoice_money where id = v_inv.credit_for_invoice_id;
      v_unpaid_before := v_m2.unpaid;
      if v_m2.alloc_total > 0 then v_warn := array_append(v_warn, 'credit_for_invoice_has_payments'); end if;
    end if;
    if v_inv.status = 'draft' then v_warn := array_append(v_warn, 'cancelled_from_draft'); end if;
    -- ═══ po-disc-2 · 판정 396 — 입고가 있는 인보이스는 취소를 막는다(다시 열기 po_invoice_confirm 과 같은 검사 · 이 인보이스의 goods 줄이 가리키는 PO 마다 · 크레딧으로 바로잡는다) ═══
    if v_inv.doc_kind = 'invoice' then
      for v_rp in
        select distinct p.id, p.po_number
        from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id join public.po p on p.id = pl.po_id
        where il.po_invoice_id = p_id and il.line_kind = 'goods'
        order by p.po_number
      loop
        if exists (select 1 from public.po_receipt r where r.po_id = v_rp.id) then
          raise exception 'The warehouse has received against PO % — a received invoice cannot be cancelled; correct it with a credit note — nothing was saved', v_rp.po_number;
        end if;
      end loop;
    end if;

    update public.po_invoice set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
    where id = p_id returning * into v_inv;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;     -- ②-b

    if v_inv.doc_kind = 'credit' and v_inv.credit_for_invoice_id is not null then
      select unpaid into v_unpaid_after from public.po_invoice_money where id = v_inv.credit_for_invoice_id;
    end if;
  else
    if v_inv.status <> 'cancelled' then
      raise exception '% % is % — only a cancelled document can be restored — nothing was saved', v_label, v_inv.invoice_number, v_inv.status;
    end if;
    v_new_status := case when v_inv.confirmed_at is not null then 'confirmed' else 'draft' end;
    if v_inv.credit_for_invoice_id is not null then
      select * into v_for from public.po_invoice where id = v_inv.credit_for_invoice_id;
      if v_for.status = 'cancelled' then v_warn := array_append(v_warn, 'credit_for_cancelled'); end if;
    end if;
    update public.po_invoice set status = v_new_status, cancelled_at = null, cancelled_by = null
    where id = p_id returning * into v_inv;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;     -- ②-b
  end if;

  return jsonb_build_object(
    'target', 'invoice', 'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status,
    'cancelled_at', v_inv.cancelled_at, 'confirmed_at', v_inv.confirmed_at, 'restored', not p_cancel,
    'credit_for', case when v_inv.credit_for_invoice_id is not null then
        jsonb_build_object('invoice_id', v_inv.credit_for_invoice_id,
                           'invoice_number', (select f.invoice_number from public.po_invoice f where f.id = v_inv.credit_for_invoice_id),
                           'unpaid_before', v_unpaid_before, 'unpaid_after', v_unpaid_after) end,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑥ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text;
begin
  if to_regclass('public.po_receipt_cost') is null then v_bad := v_bad || ' table'; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.po_receipt_cost'::regclass) then v_bad := v_bad || ' rls'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'po_receipt_cost') <> 2 then v_bad := v_bad || ' policies'; end if;
  if has_table_privilege('authenticated', 'public.po_receipt_cost', 'update') or has_table_privilege('authenticated', 'public.po_receipt_cost', 'delete') or has_table_privilege('authenticated', 'public.po_receipt_cost', 'truncate')
     or not has_table_privilege('authenticated', 'public.po_receipt_cost', 'insert') or not has_table_privilege('authenticated', 'public.po_receipt_cost', 'select') then v_bad := v_bad || ' authenticated-privileges'; end if;
  if has_table_privilege('anon', 'public.po_receipt_cost', 'select') or has_table_privilege('anon', 'public.po_receipt_cost', 'insert') then v_bad := v_bad || ' anon-privileges'; end if;
  foreach v_t in array array['public.po_invoice_discount_factor(uuid)', 'public.po_invoice_line_cost(uuid)'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'inv_layer_post_receipt' and p.prosrc like '%inv_layer_post_receipt@2026-10-08.3%' and p.prosrc like '%po_receipt_cost%') <> 1 then v_bad := v_bad || ' inv_layer_post_receipt'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'po_doc_cancel' and p.prosrc like '%a received invoice cannot be cancelled%') <> 1 then v_bad := v_bad || ' po_doc_cancel'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('inv_layer_post_receipt_over', 'inv_layer_post_receipt_off_po', 'po_receipt_diff_settle_off_invoice', 'inv_layer_apply', 'po_receipt_confirm_by', 'po_invoice_confirm') and p.prosrc like '%po-disc-2%') <> 0 then v_bad := v_bad || ' untouched-functions-touched'; end if;
  if (select pg_get_viewdef('public.po_price_history'::regclass) like '%po_invoice_line_cost%') is not true then v_bad := v_bad || ' po_price_history(view)'; end if;
  if (select reloptions::text from pg_class where oid = 'public.po_price_history'::regclass) not like '%security_invoker=true%' then v_bad := v_bad || ' po_price_history(invoker)'; end if;
  if has_table_privilege('anon', 'public.po_price_history', 'select') or not has_table_privilege('authenticated', 'public.po_price_history', 'select') then v_bad := v_bad || ' po_price_history(grants)'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_price_history') <> 26 then v_bad := v_bad || ' po_price_history(columns)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM392', message = format('STOP - po-disc-2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
