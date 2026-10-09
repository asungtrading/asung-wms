-- ─────────────────────────────────────────────────────────────
-- 공급처 할인 → 재고 원가 ④-a2 — 결제 할인 → 원가 사건(판정 391 · 395) · 결제 창구가 원소 discount 를 연다(제안 · 경고 셋) · 되돌림(충당 떼기 · 결제 지우기) · 문지기 문장 · P&G 백필 (Asung-IMS · po-disc-4a2 · 2026-10-09)
--   정본(뒤에 적는다): so-module §53 판정 389 · 390 · 391 · 395 · 398 · 399(2026-10-08 · Caleb) · po-module §11-h 「조기 결제 할인 — 결제에서」
--   판정 391  결제 저장 순간 원가를 낮춘다 — po_payment_create 가 인보이스 충당마다 사건(inv_cost_adjust · PO 줄마다)을 만들고 inv_layer_post_cost_adjust 를 부른다 · 레이어 없으면 pending(입고 확정 ⓖ) · 399 거부면 결제 전체가 저장되지 않는다
--   판정 395  세금 포함 총액에 받은 할인은 상품 몫만 — 식 한 곳 po_invoice_discount_parts(원가 몫 · 세금 몫 · 그 밖의 몫 · 끝수는 원가 몫) · 세금 몫 · 그 밖의 몫은 충당 칸(discount_tax_part · discount_other_part)에 기록만(⬜1)
--   이견 ⓐ  po_payment_create · po_payment_alloc_delete · po_doc_delete 를 security definer 로(문은 첫 줄 그대로) — invoker 창구는 회수된 속 함수를 못 부른다(asung-workflow §4 「invoker 셸은 회수된 속을 못 부른다」) · 세 창구의 RLS 정책은 전부 purchasing 이라 판정은 같다
--   이견 ⓑ  옛 모양(원소에 discount 열쇠가 하나도 없다 = 지금 화면)은 p_discount_taken 이 사람의 선언 · 제안은 경고 discount_available 로만 · 새 모양(열쇠 있음 · null = 제안) 은 원소마다 — 안 그러면 조건 있는 인보이스를 지금 화면으로 전액 내는 길이 검산에 막힌다
--   이견 ⓒ  비용 청구서 원소의 discount 는 거부(④-b) · 옛 모양의 비용 청구서 할인은 충당에만 + 경고 charge_discount_not_costed_yet
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음(set local 없음 · 백필은 alter table disable trigger 로) · 재발행 — po_payment_create(20261009011457:685~821 바이트 복사 + 할인 블록 · 사건) · po_payment_alloc_delete(20260918013000:514~543 + 되돌림) · po_doc_delete(20260918000000:682~850 + 되돌림) · 문지기 둘(20261009011457:160~196 문장만)
--   원칙 1: IMS 는 Cin7 없이 돈다 — 사건의 재료는 IMS 결제 · IMS 인보이스 · IMS 환율
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

-- ═══ ② 식 한 곳 — 할인 → 원가 몫 · 세금 몫 · 그 밖의 몫(판정 395) · 충당 칸 둘(기록만 · ⬜1) ═══
alter table public.po_payment_alloc
  add column discount_tax_part   numeric not null default 0,                             -- 할인 중 세금 몫(with_tax 기준일 때만 > 0 · 기록 · 회계사 확인 · 재고 무관)
  add column discount_other_part numeric not null default 0,                             -- 할인 중 그 밖의 몫(payable 인 other · charge 줄 · 기록 · 재고 무관)
  add constraint po_payment_alloc_discount_parts_ck check (discount_tax_part >= 0 and discount_other_part >= 0 and discount_tax_part + discount_other_part <= discount_amount);
comment on column public.po_payment_alloc.discount_tax_part   is 'po-disc-4a2 ⭐ 이 충당 할인 중 세금 몫(판정 395 · with_tax 기준일 때 할인 × 세금 ÷ 기준 · pre_tax 면 0) — 기록만(원가 사건 없음 · 회계사 확인) · 창구가 적는다 · 원가 몫 = discount_amount − 세금 몫 − 그 밖의 몫 = Σ사건 amount_doc 의 반대 부호';
comment on column public.po_payment_alloc.discount_other_part is 'po-disc-4a2 ⭐ 이 충당 할인 중 그 밖의 몫(payable 인 other · charge 줄의 비율) — 기록만 · 재고 무관';

create function public.po_invoice_discount_parts(p_invoice_id uuid, p_discount numeric, p_basis text default null)
  returns table (basis text, base_amount numeric, goods_net numeric, tax_amount numeric, other_amount numeric, cost_part numeric, tax_part numeric, other_part numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with m as (
    select coalesce(p_basis, i.early_discount_basis, 'pre_tax') as basis,
           round(m.goods_payable * m.factor, 2) as goods_net, coalesce(m.payable_tax, 0) as tax_amount, m.other_payable as other_amount,
           m.payable_taxable, m.payable_net
    from public.po_invoice i join public.po_invoice_money m on m.id = i.id where i.id = p_invoice_id
  ), b as (
    select m.*, case m.basis when 'with_tax' then m.payable_net else m.payable_taxable end as base_amount from m
  ), p as (
    select b.*,
           case when b.base_amount > 0 and b.basis = 'with_tax' then round(coalesce(p_discount, 0) * b.tax_amount / b.base_amount, 2) else 0 end   as tax_part,
           case when b.base_amount > 0 then round(coalesce(p_discount, 0) * b.other_amount / b.base_amount, 2) else 0 end                        as other_part
    from b
  )
  select p.basis, p.base_amount, p.goods_net, p.tax_amount, p.other_amount,
         coalesce(p_discount, 0) - p.tax_part - p.other_part as cost_part,                 -- 끝수는 원가 몫에 — 셋의 합 = 할인(검산)
         p.tax_part, p.other_part
  from p
$$;
revoke all on function public.po_invoice_discount_parts(uuid, numeric, text) from public, anon;
grant execute on function public.po_invoice_discount_parts(uuid, numeric, text) to authenticated;
comment on function public.po_invoice_discount_parts(uuid, numeric, text) is 'po-disc-4a2 ⭐ 할인을 셋으로 가르는 식 한 곳(판정 395) — 기준 = basis(pre_tax → payable_taxable · with_tax → payable_net · 없으면 인보이스 조건 · 그것도 없으면 pre_tax) · 세금 몫 = with_tax 일 때 할인 × payable_tax ÷ 기준(round 2 · pre_tax 면 0) · 그 밖의 몫 = 할인 × other_payable ÷ 기준 · 원가 몫 = 할인 − 둘(끝수는 여기) · po_payment_create(미리 보기 · 저장) · po_payment_alloc_cost_events 가 부른다';

-- ═══ ②-b 속 함수 — 충당 하나의 할인 → 원가 사건(PO 줄마다 · 줄 금액 qty × 단가 × 인보이스 체인 비율 · 끝수 마지막 · 무상 줄 몫 없음 · 환율 = po_invoice_line_cost) · p_post 면 곧바로 얹는다(레이어 없으면 pending · 399 거부는 그대로 올라간다) ═══
create function public.po_payment_alloc_cost_events(p_alloc_id uuid, p_post boolean default true) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'po_payment_alloc_cost_events@2026-10-09.1';
  v_al        public.po_payment_alloc%rowtype;
  v_pay       public.po_payment%rowtype;
  v_inv       public.po_invoice%rowtype;
  v_cur       text;
  v_p         record;
  v_l         record;
  v_staff     uuid;
  v_src       text;
  v_wsum      numeric;
  v_n         int;
  v_i         int := 0;
  v_given     numeric := 0;
  v_share     numeric;
  v_id        uuid;
  v_j         jsonb;
  v_events    jsonb := '[]'::jsonb;
  v_free      int := 0;
  v_nofx      text;
begin
  select * into v_al from public.po_payment_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — no cost was changed', p_alloc_id; end if;
  if v_al.po_invoice_id is null then
    return jsonb_build_object('alloc_id', p_alloc_id, 'skipped', 'charge_allocation', 'events', '[]'::jsonb, 'builder', c_version);   -- 비용 청구서 할인은 ④-b
  end if;
  if coalesce(v_al.discount_amount, 0) <= 0 then
    return jsonb_build_object('alloc_id', p_alloc_id, 'skipped', 'no_discount', 'events', '[]'::jsonb, 'builder', c_version);
  end if;
  if exists (select 1 from public.inv_cost_adjust j where j.source_type = 'po_payment_alloc' and j.source_id = p_alloc_id) then
    raise exception 'Allocation line % already has cost events — they are reversed when the allocation is removed, not re-made — no cost was changed', p_alloc_id;
  end if;
  select * into v_pay from public.po_payment where id = v_al.po_payment_id;
  select * into v_inv from public.po_invoice where id = v_al.po_invoice_id;
  select c.code into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  v_src := coalesce(nullif(v_pay.reference, ''), 'PAY ' || v_pay.paid_on::text || ' ' || v_inv.invoice_number);

  select * into v_p from public.po_invoice_discount_parts(v_inv.id, v_al.discount_amount, null);
  update public.po_payment_alloc set discount_tax_part = v_p.tax_part, discount_other_part = v_p.other_part where id = p_alloc_id;   -- 기록(문지기는 amount · discount_amount 만 본다)

  -- PO 줄마다 가중 = Σ(qty × 단가 × 인보이스 체인) · goods · payable · 단가 > 0(판정 398 무상 줄은 몫 없음) · 환율은 줄의 출처(인보이스 → 같은 통화 PO → 없음 = 거부) · 같은 조회를 두 번(집계 · 루프) — 임시 표 없이
  select count(*), coalesce(sum(g.w), 0), string_agg(g.sku, ', ') filter (where g.nofx) into v_n, v_wsum, v_nofx
    from (select il.po_line_id, min(pr.sku) as sku, sum(il.qty_ea * il.unit_price * c.factor) as w, bool_or(c.net_unit_cad is null) as nofx
            from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id join public.product pr on pr.id = pl.product_id
            cross join lateral public.po_invoice_line_cost(il.id) c
           where il.po_invoice_id = v_inv.id and il.line_kind = 'goods' and il.is_payable and il.unit_price > 0 and il.po_line_id is not null
           group by il.po_line_id) g;
  select count(*) into v_free from public.po_invoice_line il where il.po_invoice_id = v_inv.id and il.line_kind = 'goods' and il.po_line_id is not null and not (il.is_payable and il.unit_price > 0);
  if v_nofx is not null then
    raise exception 'Invoice % is in % but has no exchange rate for its lines (%) — the discount cannot be put on stock cost without it; enter the rate on the invoice (or the PO) first — nothing was saved', v_inv.invoice_number, coalesce(v_cur, '?'), v_nofx;
  end if;
  if v_n = 0 or v_wsum <= 0 or v_p.cost_part <= 0 then
    return jsonb_build_object('alloc_id', p_alloc_id, 'invoice_number', v_inv.invoice_number, 'discount', v_al.discount_amount, 'basis', v_p.basis,
                              'cost_part', v_p.cost_part, 'tax_part', v_p.tax_part, 'other_part', v_p.other_part, 'skipped', 'no_cost_part', 'events', '[]'::jsonb, 'free_lines', v_free, 'builder', c_version);
  end if;

  for v_l in
    select il.po_line_id, min(pl.line_no) as line_no, min(pr.sku) as sku, sum(il.qty_ea * il.unit_price * c.factor) as w, max(c.exchange_rate) as fx, max(c.exchange_rate_source) as fx_src
      from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id join public.product pr on pr.id = pl.product_id
      cross join lateral public.po_invoice_line_cost(il.id) c
     where il.po_invoice_id = v_inv.id and il.line_kind = 'goods' and il.is_payable and il.unit_price > 0 and il.po_line_id is not null
     group by il.po_line_id
     order by min(pl.line_no), il.po_line_id
  loop
    v_i := v_i + 1;
    if v_i = v_n then v_share := v_p.cost_part - v_given; else v_share := round(v_p.cost_part * v_l.w / v_wsum, 2); end if;   -- 끝수는 마지막 줄 · 합 = 원가 몫
    v_given := v_given + v_share;
    if v_share = 0 then continue; end if;
    insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, amount_doc, currency_id, exchange_rate, source_type, source_id, source_number, note, created_by, updated_by)
    values ('settlement_discount', 'po_line', v_l.po_line_id, -v_share * coalesce(v_l.fx, 1), -v_share, v_inv.currency_id, v_l.fx, 'po_payment_alloc', p_alloc_id, v_src,
            format('early-payment discount %s on invoice %s (%s · basis %s · fx %s)', v_al.discount_amount, v_inv.invoice_number, v_src, v_p.basis, coalesce(v_l.fx_src, 'base')), v_staff, v_staff)
    returning id into v_id;
    v_j := null;
    if p_post then v_j := public.inv_layer_post_cost_adjust(v_id); end if;                                                   -- 판정 391 · 레이어 없으면 no_layers(pending) · 판정 399 거부는 예외로 올라간다 = 결제 전체 안 저장
    v_events := v_events || jsonb_build_object('id', v_id, 'po_line_id', v_l.po_line_id, 'po_line_no', v_l.line_no, 'sku', v_l.sku, 'weight', v_l.w,
                                               'amount_doc', -v_share, 'exchange_rate', v_l.fx, 'amount_cad', -v_share * coalesce(v_l.fx, 1),
                                               'status', coalesce(v_j ->> 'status', 'pending'), 'layers', coalesce((v_j ->> 'layers')::int, 0), 'posted_cad', coalesce((v_j ->> 'posted_cad')::numeric, 0));
  end loop;
  return jsonb_build_object('alloc_id', p_alloc_id, 'invoice_number', v_inv.invoice_number, 'currency', v_cur, 'discount', v_al.discount_amount, 'basis', v_p.basis, 'base_amount', v_p.base_amount,
                            'cost_part', v_p.cost_part, 'tax_part', v_p.tax_part, 'other_part', v_p.other_part, 'events', v_events, 'event_count', jsonb_array_length(v_events),
                            'free_lines', v_free, 'posted', p_post, 'builder', c_version);
end;
$$;
revoke all on function public.po_payment_alloc_cost_events(uuid, boolean) from public, anon, authenticated;   -- 속 함수 — po_payment_create(definer) · 백필이 부른다
comment on function public.po_payment_alloc_cost_events(uuid, boolean) is 'po-disc-4a2 ⭐ 충당 하나의 할인 → 원가 사건(판정 391 · 395 · 398 · 2026-10-09) — 인보이스 충당만(비용 청구서 skipped · ④-b) · 할인 0 skipped · 이미 사건이 있으면 거부(되돌림은 떼기 · 지우기에서) · 몫 = po_invoice_discount_parts.cost_part · PO 줄마다 가중 Σ(qty × 단가 × 인보이스 체인) · 끝수 마지막 줄 · 무상 줄 몫 없음 · 환율 = po_invoice_line_cost(없으면 거부) · amount_doc = −몫 · amount_cad = −몫 × 환율 · source_type po_payment_alloc · source_id 충당 · source_number 결제 reference(없으면 PAY <날> <인보이스>) · p_post 면 inv_layer_post_cost_adjust(no_layers = pending · 399 거부는 예외) · 충당 칸 discount_tax_part · discount_other_part 를 적는다';

-- ═══ ③ 속 함수 — 충당의 사건을 되돌린다(떼기 · 지우기 전에 · 같은 트랜잭션 · posted 는 곧바로 반대 부호 · pending 은 둘 다 pending) ═══
create function public.po_payment_alloc_cost_reverse(p_alloc_id uuid, p_note text default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare x record; v_r jsonb; v_list jsonb := '[]'::jsonb; v_n int := 0;
begin
  for x in select j.id, j.source_number, j.status from public.inv_cost_adjust j
            where j.source_type = 'po_payment_alloc' and j.source_id = p_alloc_id
              and not exists (select 1 from public.inv_cost_adjust r where r.reverses_id = j.id)
            order by j.created_at, j.id loop
    v_r := public.inv_cost_adjust_reverse(x.id, p_note);
    v_n := v_n + 1;
    v_list := v_list || jsonb_build_object('reverses_id', x.id, 'reversal_id', v_r ->> 'reversal_id', 'was', x.status, 'status', v_r ->> 'status', 'amount_cad', v_r -> 'amount_cad');
  end loop;
  return jsonb_build_object('alloc_id', p_alloc_id, 'reversed', v_n, 'events', v_list);
end;
$$;
revoke all on function public.po_payment_alloc_cost_reverse(uuid, text) from public, anon, authenticated;
comment on function public.po_payment_alloc_cost_reverse(uuid, text) is 'po-disc-4a2 ⭐ 충당 하나의 원가 사건(되돌림 아닌 것 · 아직 안 되돌린 것)을 inv_cost_adjust_reverse 로 되돌린다 — po_payment_alloc_delete · po_doc_delete(payment) 가 지우기 전에 부른다(같은 트랜잭션 · 돈과 원가가 같이 움직인다) · 사건은 남는다(source_id 는 FK 없음)';

-- ═══ ④ 문지기 문장(📌 5) — uuid 없이 결제일 · 금액 · 통화(· reference) · 「delete this payment and enter it again」 · ⬜ ④-b · ⑥ 에서 「Adjust discount」 단추가 생기면 이 두 문장을 고친다(표식 ADJUST-DISCOUNT-BUTTON) ═══
create or replace function public.po_payment_guard() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_cur text;
begin
  if coalesce(current_setting('po.payment_door', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    raise exception 'A payment is created through the payment window (Pay · po_payment_create), not by inserting a row — nothing was saved';
  end if;
  if new.amount is distinct from old.amount or new.discount_taken is distinct from old.discount_taken then
    select c.code into v_cur from public.ref_currency c where c.id = old.currency_id;
    -- ADJUST-DISCOUNT-BUTTON: 단추가 생기면 「delete this payment and enter it again」 → 「use Adjust discount」
    raise exception 'Paid (% → %) and Discount taken (% → %) on the payment of % % dated % are not edited here — to correct them, delete this payment and enter it again — nothing was saved',
      old.amount, new.amount, old.discount_taken, new.discount_taken, old.amount, coalesce(v_cur, ''), old.paid_on::text || case when old.reference is not null then ' (' || old.reference || ')' else '' end;
  end if;
  return new;
end;
$$;
create or replace function public.po_payment_alloc_guard() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if coalesce(current_setting('po.payment_door', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    raise exception 'A document is put on a payment through the payment window (Pay · Add a document), not by inserting a row — nothing was saved';
  end if;
  if new.amount is distinct from old.amount or new.discount_amount is distinct from old.discount_amount then
    -- ADJUST-DISCOUNT-BUTTON: 단추가 생기면 「delete this payment and enter it again」 → 「use Adjust discount」
    raise exception 'The amount (% → %) and discount (% → %) on this line are not edited here — change the amount in the On this payment column; to change the discount, delete this payment and enter it again — nothing was saved',
      old.amount, new.amount, old.discount_amount, new.discount_amount;
  end if;
  return new;
end;
$$;


-- ═══ ① po_payment_create 재발행 — 마지막 정의 20261009011457:685~821(DB md5 d54d37bc · 검증 G0) 바이트 복사 + definer · declare 5줄 · 모양 가르기 · 원소 할인 블록 · Σ 규칙(4a1 옛 모양 블록 대체) · 충당 insert returning + 사건 · 반환 키 2 ═══
create or replace function public.po_payment_create(
  p_supplier_id    uuid,                        -- 화면의 축(후보 문서·통화가 여기서 따라온다) · ⭐ 선택(이견 1·ⓑ) — 대상 문서의 공급처와 다르면 경고 mixed_supplier · 표에 칸이 없다(결제는 공급처를 안 담는다)
  p_paid_on        date,                        -- 안 주면 오늘
  p_amount         numeric,                     -- 실제로 낸 돈(결제 통화) · > 0(CHECK)
  p_currency_id    uuid,                        -- ⭐ 필수 · 결제 통화 = 대상 문서 전부의 통화(②)
  p_discount_taken numeric default 0,           -- ⑥ 사람이 선언 · ≥ 0(CHECK)
  p_account_id     uuid    default null,        -- 지정만(③) · 통화 검사 없음 · 안 고르면 경고
  p_reference      text    default null,
  p_note           text    default null,
  p_targets        jsonb   default null,        -- [ {kind, id, amount, note}, … ] · amount 없으면 미지급 전액 제안
  p_commit         boolean default false
) returns jsonb
language plpgsql
volatile
security definer                                              -- po-disc-4a2(이견 ⓐ): 속 함수 po_payment_alloc_cost_events 를 부른다 — invoker 창구는 회수된 속을 못 부른다 · 문은 첫 줄 ims_require_write('purchasing')
set search_path = public, pg_temp
as $$
declare
  v_staff      uuid;
  v_sup_id     uuid;
  v_sup_name   text;
  v_cur_code   text;
  v_acc_code   text;  v_acc_name text;
  v_pay_id     uuid;
  v_allocs     jsonb := '[]'::jsonb;
  v_sum        numeric := 0;
  v_gap        numeric;
  v_disc       numeric;
  v_warn       text[] := '{}';
  v_sups       uuid[] := '{}';
  v_seen       text[] := '{}';
  v_key        text;
  v_kind       text;  v_tid uuid;  v_amt numeric;  v_note text;
  t            record;
  r            jsonb;
  v_prev       text;                                           -- po-disc-4a1: 문지기 플래그 전 값
  v_eds        record;                                         -- po-disc-4a2: 이 문서의 조기 결제 할인(결제일 기준 · po_invoice_early_discount)
  v_dsc        numeric;  v_dsum numeric := 0;  v_dsrc text;    -- po-disc-4a2: 원소의 할인 · Σ · 출처(suggested | given | legacy)
  v_legacy     boolean;                                        -- po-disc-4a2(이견 ⓑ): 원소에 discount 열쇠가 하나도 없다 = 옛 모양(지금 화면) — p_discount_taken 이 사람의 선언
  v_pb         text;  v_pc numeric;  v_pt numeric;  v_po numeric;   -- po-disc-4a2: 할인의 세 몫(po_invoice_discount_parts)
  v_aid        uuid;  v_cost jsonb;  v_costs jsonb := '[]'::jsonb;  -- po-disc-4a2: 저장 순간의 원가 사건
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  if p_amount is null then raise exception 'Amount is required — nothing was saved'; end if;
  if p_amount <= 0 then raise exception 'Amount must be above 0 (got %) — nothing was saved', p_amount; end if;
  if p_currency_id is null then raise exception 'Currency is required — nothing was saved'; end if;
  select c.code into v_cur_code from public.ref_currency c where c.id = p_currency_id;
  if v_cur_code is null then raise exception 'Currency % not found — nothing was saved', p_currency_id; end if;
  v_disc := coalesce(p_discount_taken, 0);
  if v_disc < 0 then raise exception 'Discount taken cannot be negative (got %) — nothing was saved', v_disc; end if;
  v_sup_id := p_supplier_id;
  if v_sup_id is not null then
    select s.name into v_sup_name from public.supplier s where s.id = v_sup_id;
    if v_sup_name is null then raise exception 'Supplier % not found — nothing was saved', v_sup_id; end if;
  end if;
  if p_account_id is not null then
    select a.code, a.name into v_acc_code, v_acc_name from public.ref_account a where a.id = p_account_id;
    if v_acc_code is null then raise exception 'Account % not found — nothing was saved', p_account_id; end if;
  else
    v_warn := array_append(v_warn, 'account_missing');
  end if;
  if p_targets is not null and jsonb_typeof(p_targets) <> 'array' then
    raise exception 'p_targets must be a JSON array [{kind, id, amount, note}] — nothing was saved';
  end if;

  -- ── po-disc-4a2(이견 ⓑ) · 모양 가르기 — 옛 모양: 원소에 discount 열쇠 없음 → p_discount_taken 이 선언(대상 하나에만) · 새 모양: 원소마다 discount(null = 조건으로 제안) ──
  v_legacy := not exists (select 1 from jsonb_array_elements(coalesce(p_targets, '[]'::jsonb)) e where e ? 'discount');
  if v_legacy and v_disc > 0 and jsonb_array_length(coalesce(p_targets, '[]'::jsonb)) > 1 then
    raise exception 'Say which document the discount of % belongs to — a payment that settles % documents cannot carry one discount for all of them; give the discount per document, or pay the discounted document on its own payment — nothing was saved', v_disc, jsonb_array_length(coalesce(p_targets, '[]'::jsonb));
  end if;

  -- ── 대상 문서 검사(한 곳 · po_payment_target_check) — 미리 보기도 같은 판정 ──
  for r in select * from jsonb_array_elements(coalesce(p_targets, '[]'::jsonb)) loop
    v_kind := r->>'kind';
    v_tid  := nullif(r->>'id', '')::uuid;
    v_amt  := nullif(r->>'amount', '')::numeric;
    v_note := r->>'note';
    if v_tid is null then raise exception 'p_targets[] needs an id on every element — nothing was saved'; end if;
    v_key := coalesce(v_kind, '?') || ':' || v_tid::text;
    if v_key = any(v_seen) then raise exception 'Document % appears twice in p_targets — nothing was saved', v_tid; end if;
    v_seen := array_append(v_seen, v_key);
    if v_amt is not null and v_amt <= 0 then
      raise exception 'p_targets[] amount must be above 0 or omitted (got % for %) — nothing was saved', v_amt, v_tid;
    end if;
    select * into t from public.po_payment_target_check(v_kind, v_tid, v_amt, p_currency_id, null);
    if v_amt is null then v_amt := t.doc_unpaid; end if;                          -- 미지급 전액 제안
    if v_amt <= 0 then
      raise exception '% % has nothing unpaid (%) — nothing to allocate — nothing was saved', case v_kind when 'invoice' then 'Invoice' else 'Charge' end, t.target_number, t.doc_unpaid;
    end if;
    -- ── po-disc-4a2 · 이 문서의 할인(판정 391) — 비용 청구서는 ④-b(원소 discount 거부 · 옛 모양은 충당에만 + 경고) · 인보이스는 제안 · 경고 셋 · 세 몫 ──
    v_dsc := nullif(r->>'discount', '')::numeric;  v_dsrc := null;  v_pb := null;  v_pc := null;  v_pt := null;  v_po := null;
    if v_dsc is not null and v_dsc < 0 then raise exception 'p_targets[] discount cannot be negative (got % for %) — nothing was saved', v_dsc, t.target_number; end if;
    if v_kind = 'charge' then
      if v_dsc is not null then
        raise exception 'Charge %: a discount on a charge bill is not put on stock cost yet — that arrives with the next step; leave the discount off this line for now — nothing was saved', t.target_number;
      end if;
      v_dsc := case when v_legacy and v_disc > 0 then v_disc else 0 end;
      if v_dsc > 0 then v_dsrc := 'legacy'; v_warn := array_append(v_warn, 'charge_discount_not_costed_yet:' || t.target_number); end if;
    else
      select * into v_eds from public.po_invoice_early_discount(v_tid, coalesce(p_paid_on, public.ims_today()));
      if v_legacy then
        v_dsc := case when v_disc > 0 then v_disc else 0 end;
        if v_dsc > 0 then v_dsrc := 'legacy'; end if;
        if v_dsc = 0 and v_eds.has_terms and v_eds.is_valid and v_eds.discount > 0 then v_warn := array_append(v_warn, 'discount_available:' || t.target_number || ':' || v_eds.discount::text); end if;
      elsif v_dsc is null then
        if v_eds.has_terms and v_eds.is_valid then v_dsc := v_eds.discount; v_dsrc := 'suggested'; v_warn := array_append(v_warn, 'discount_suggested:' || t.target_number);
        elsif v_eds.has_terms then v_dsc := 0; v_warn := array_append(v_warn, 'discount_expired:' || t.target_number);
        else v_dsc := 0; end if;
      else
        v_dsrc := 'given';
      end if;
      if v_dsc > 0 and v_dsrc <> 'suggested' then
        if v_eds.has_terms and not v_eds.is_valid then v_warn := array_append(v_warn, 'discount_after_deadline:' || t.target_number); end if;
        if not v_eds.has_terms then v_warn := array_append(v_warn, 'discount_without_terms:' || t.target_number); end if;
      end if;
      if v_dsc > v_amt then raise exception 'Invoice %: discount % is larger than the amount allocated to it (%) — nothing was saved', t.target_number, v_dsc, v_amt; end if;
      if v_dsc > 0 then select basis, cost_part, tax_part, other_part into v_pb, v_pc, v_pt, v_po from public.po_invoice_discount_parts(v_tid, v_dsc, null); end if;
    end if;
    v_dsum := v_dsum + v_dsc;
    v_sum := v_sum + v_amt;
    if not (t.supplier_id = any(v_sups)) then v_sups := array_append(v_sups, t.supplier_id); end if;
    v_allocs := v_allocs || jsonb_build_object('kind', v_kind, 'id', v_tid, 'number', t.target_number, 'supplier_name', t.supplier_name, 'currency_code', t.currency_code,
                                               'doc_total', t.doc_total, 'doc_paid_before', t.doc_paid, 'doc_unpaid_before', t.doc_unpaid, 'amount', v_amt, 'note', v_note, 'inserted', p_commit,
                                               'discount', v_dsc, 'discount_source', v_dsrc, 'discount_basis', v_pb, 'cost_part', v_pc, 'tax_part', v_pt, 'other_part', v_po);   -- po-disc-4a2 · 이 문서의 할인과 세 몫(판정 395)
  end loop;

  -- ── po-disc-4a2 · 검산의 할인 = Σ원소 할인 · 새 모양인데 p_discount_taken 도 왔으면 둘이 같아야 한다(어느 쪽이 맞는지 모른다 · 조용히 고르지 않는다) ──
  if not v_legacy and v_disc > 0 and round(v_disc - v_dsum, 2) <> 0 then
    raise exception 'Say the discount once — per document (p_targets[].discount, total %) or as p_discount_taken (%), not both with different totals — nothing was saved', v_dsum, v_disc;
  end if;
  v_disc := v_dsum;

  -- 공급처 — 강제하지 않는다(이견 1 · ⓑ) · 둘 이상이거나 p_supplier_id 와 다르면 경고
  if cardinality(v_sups) > 1 or (v_sup_id is not null and cardinality(v_sups) = 1 and v_sups[1] <> v_sup_id) then
    v_warn := array_append(v_warn, 'mixed_supplier');
  end if;
  if v_sup_id is null and cardinality(v_sups) = 1 then
    v_sup_id := v_sups[1];
    select s.name into v_sup_name from public.supplier s where s.id = v_sup_id;
  end if;

  -- ⑤ 검산 — Σ충당 = amount + discount_taken · 거부(양쪽 다 우리가 넣는 숫자)
  v_gap := round(p_amount + v_disc - v_sum, 2);
  if v_gap <> 0 then
    raise exception 'Allocations % do not match amount % + discount % = % (gap %) — fix the amounts or the discount first — nothing was saved',
      v_sum, p_amount, v_disc, p_amount + v_disc, v_gap;
  end if;

  -- ── commit: 머리 한 행 + 충당 줄 ──
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
    v_prev := current_setting('po.payment_door', true);  perform set_config('po.payment_door', '1', true);   -- po-disc-4a1: 이 창구의 쓰기만 문지기를 지난다
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference, discount_taken, paid_by, note)
    values (coalesce(p_paid_on, public.ims_today()), p_amount, p_currency_id, p_account_id, p_reference, v_disc, v_staff, p_note)
    returning id into v_pay_id;
    for r in select * from jsonb_array_elements(v_allocs) loop
      insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note, discount_amount)   -- po-disc-4a1 · 충당 할인(정본 · Σ 트리거가 discount_taken 을 맞춘다)
      values (v_pay_id,
              case when r->>'kind' = 'invoice' then (r->>'id')::uuid end,
              case when r->>'kind' = 'charge'  then (r->>'id')::uuid end,
              (r->>'amount')::numeric, r->>'note', coalesce((r->>'discount')::numeric, 0))   -- po-disc-4a2 · 원소의 할인
      returning id into v_aid;
      if r->>'kind' = 'invoice' and coalesce((r->>'discount')::numeric, 0) > 0 then                        -- po-disc-4a2(판정 391) · 저장 순간 원가 사건 — 레이어 없으면 pending · 399 거부는 예외 = 결제 전체 안 저장
        v_cost := public.po_payment_alloc_cost_events(v_aid, true);
        v_costs := v_costs || v_cost;
      end if;
    end loop;
    perform set_config('po.payment_door', coalesce(v_prev, ''), true);                                       -- po-disc-4a1
  end if;

  return jsonb_build_object(
    'committed', p_commit, 'payment_id', v_pay_id, 'paid_on', coalesce(p_paid_on, public.ims_today()),
    'amount', p_amount, 'discount_taken', v_disc, 'currency_id', p_currency_id, 'currency_code', v_cur_code,
    'supplier_id', v_sup_id, 'supplier_name', v_sup_name,
    'account_code', v_acc_code, 'account_name', v_acc_name,
    'alloc_sum', v_sum, 'gap', v_gap, 'allocs', v_allocs, 'cost_events', v_costs, 'legacy_shape', v_legacy, 'warnings', to_jsonb(v_warn));   -- po-disc-4a2 · cost_events[] = 충당마다 사건(저장 때만) · legacy_shape
end;
$$;

-- ═══ ③-a po_payment_alloc_delete 재발행 — 마지막 정의 20260918013000:514~543(DB md5 f80a194d · 검증 G0) 바이트 복사 + definer · declare 1 · 되돌림 1 · 반환 키 2(gap 식) ═══
create or replace function public.po_payment_alloc_delete(p_alloc_id uuid) returns jsonb
language plpgsql
volatile
security definer                                              -- po-disc-4a2(이견 ⓐ): 속 함수 po_payment_alloc_cost_reverse 를 부른다 · 문은 첫 줄
set search_path = public, pg_temp
as $$
declare
  v_n    int;                                                   -- ②-b: row_count
  v_al   public.po_payment_alloc%rowtype;
  v_pay  public.po_payment%rowtype;
  v_num  text;
  v_sum  numeric;
  v_rv   jsonb;                                                 -- po-disc-4a2: 되돌린 원가 사건
begin
  perform public.ims_require_write('purchasing', 'deleted');     -- ②-b

  select * into v_al from public.po_payment_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — nothing was deleted', p_alloc_id; end if;
  select * into v_pay from public.po_payment where id = v_al.po_payment_id;
  select coalesce(i.invoice_number, c.charge_number) into v_num
  from public.po_payment_alloc a left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id
  where a.id = p_alloc_id;
  v_rv := public.po_payment_alloc_cost_reverse(p_alloc_id, 'allocation removed from payment ' || coalesce(v_pay.reference, v_pay.paid_on::text));   -- po-disc-4a2(판정 391): 지우기 전에 사건을 되돌린다(같은 트랜잭션 · posted → 반대 부호 곧바로 · pending → 둘 다 pending)
  delete from public.po_payment_alloc where id = p_alloc_id;
  get diagnostics v_n = row_count;                              -- ②-b
  if v_n = 0 then raise exception 'Allocation line % on payment % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_alloc_id, coalesce(v_pay.reference, v_pay.id::text); end if;
  select coalesce(sum(amount), 0) into v_sum from public.po_payment_alloc where po_payment_id = v_pay.id;
  return jsonb_build_object('deleted', true, 'alloc_id', v_al.id, 'payment_id', v_pay.id,
                            'kind', case when v_al.po_charge_id is not null then 'charge' else 'invoice' end, 'target_number', v_num,
                            'amount_removed', v_al.amount, 'discount_removed', v_al.discount_amount, 'cost_reversed', v_rv,   -- po-disc-4a2
                            'alloc_sum', v_sum, 'gap', round(v_pay.amount + (select coalesce(sum(x.discount_amount), 0) from public.po_payment_alloc x where x.po_payment_id = v_pay.id) - v_sum, 2));   -- po-disc-4a2 · gap 은 지운 뒤의 Σ할인으로(머리 discount_taken 은 트리거가 뒤에 맞춘다)
end;
$$;

-- ═══ ③-b po_doc_delete 재발행 — 마지막 정의 20260918000000:682~850(DB md5 8864a994 · 검증 G0) 바이트 복사 + definer · declare 1 · 결제 갈래 되돌림 루프 3 · 반환 키 1 ═══
create or replace function public.po_doc_delete(
  p_target text,                          -- 'po' | 'invoice' | 'charge' | 'payment'
  p_id     uuid
) returns jsonb
language plpgsql
volatile
security definer                                              -- po-disc-4a2(이견 ⓐ): payment 갈래가 속 함수 po_payment_alloc_cost_reverse 를 부른다 · 문은 첫 줄 · 네 갈래의 RLS 정책은 전부 purchasing
set search_path = public, pg_temp
as $$
declare
  v_po        public.po%rowtype;
  v_inv       public.po_invoice%rowtype;
  v_chg       public.po_charge%rowtype;
  v_pay       public.po_payment%rowtype;
  v_label     text;
  v_n         int;
  v_txt       text;
  v_lines     int;
  v_discs     int;
  v_del       int;                                              -- ②-b: row_count
  v_rv        jsonb := '[]'::jsonb;  x record;                  -- po-disc-4a2: 결제 갈래 — 충당마다 되돌린 원가 사건
begin
  perform public.ims_require_write('purchasing', 'deleted');   -- ②-b

  if p_target not in ('po', 'invoice', 'charge', 'payment') then
    raise exception 'p_target must be po, invoice, charge or payment — nothing was deleted';
  end if;

  -- ══════════ 발주 (100000 그대로) ══════════
  if p_target = 'po' then
    select * into v_po from public.po where id = p_id;
    if not found then raise exception 'PO % not found — nothing was deleted', p_id; end if;

    if v_po.confirmed_at is not null then
      raise exception 'PO % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
        v_po.po_number, to_char(v_po.confirmed_at, 'YYYY-MM-DD');
    end if;

    select count(*) into v_n
    from public.po_receipt_line rl join public.po_line pl on pl.id = rl.po_line_id where pl.po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % receipt line(s) — a received order cannot be deleted; receipts are events — nothing was deleted', v_po.po_number, v_n;
    end if;

    select count(distinct i.id), string_agg(distinct i.invoice_number, ', ' order by i.invoice_number) into v_n, v_txt
    from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id join public.po_invoice i on i.id = il.po_invoice_id
    where pl.po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % is referenced by % invoice/credit document(s) (%) — remove those lines or delete those documents first — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(c.charge_number, ', ' order by c.charge_number) into v_n, v_txt
    from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id where a.po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % charge allocation(s) (%) — remove the allocation first — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(c.po_number, ', ' order by c.po_number) into v_n, v_txt
    from public.po c where c.split_from_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % split document(s) (%) pointing at it — the chain would break — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(k.invoice_number, ', ' order by k.invoice_number) into v_n, v_txt
    from public.po_invoice k where k.credit_po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % numbered % credit note(s) (%) — their number rests on this PO — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*) into v_lines from public.po_line     where po_id = p_id;
    select count(*) into v_discs from public.po_discount where po_id = p_id;
    delete from public.po where id = p_id;
    get diagnostics v_del = row_count;                          -- ②-b
    if v_del = 0 then
      raise exception 'PO % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_po.po_number;
    end if;

    return jsonb_build_object(
      'deleted', true, 'target', 'po', 'id', v_po.id, 'po_number', v_po.po_number, 'status_before', v_po.status,
      'lines_deleted', v_lines, 'discounts_deleted', v_discs);
  end if;

  -- ══════════ 비용 문서 (150000 그대로) ══════════
  if p_target = 'charge' then
    select * into v_chg from public.po_charge where id = p_id;
    if not found then raise exception 'Charge % not found — nothing was deleted', p_id; end if;

    if v_chg.confirmed_at is not null then
      raise exception 'Charge % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
        v_chg.charge_number, to_char(v_chg.confirmed_at, 'YYYY-MM-DD');
    end if;

    select count(*), string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_n, v_txt
    from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id where pa.po_charge_id = p_id;
    if v_n > 0 then
      raise exception 'Charge % has payments applied (%) — remove the payment allocation first — nothing was deleted', v_chg.charge_number, v_txt;
    end if;

    select count(*) into v_lines from public.po_charge_alloc where po_charge_id = p_id;
    delete from public.po_charge where id = p_id;
    get diagnostics v_del = row_count;                          -- ②-b
    if v_del = 0 then
      raise exception 'Charge % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_chg.charge_number;
    end if;

    return jsonb_build_object(
      'deleted', true, 'target', 'charge', 'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status_before', v_chg.status,
      'allocs_deleted', v_lines);
  end if;

  -- ══════════ 결제 (새 가지) — 상태가 없다 · 언제든 지운다(⑦ · 표 주석 「잘못 넣었으면 지운다」) · 충당 줄은 CASCADE · 그 문서들의 미지급이 되살아난다 ══════════
  if p_target = 'payment' then
    select * into v_pay from public.po_payment where id = p_id;
    if not found then raise exception 'Payment % not found — nothing was deleted', p_id; end if;

    select count(*), string_agg(coalesce(i.invoice_number, c.charge_number), ', ' order by coalesce(i.invoice_number, c.charge_number)) into v_lines, v_txt
    from public.po_payment_alloc a
    left join public.po_invoice i on i.id = a.po_invoice_id
    left join public.po_charge  c on c.id = a.po_charge_id
    where a.po_payment_id = p_id;
    for x in select a.id from public.po_payment_alloc a where a.po_payment_id = p_id order by a.created_at, a.id loop   -- po-disc-4a2(판정 391): 지우기 전에 충당마다 사건을 되돌린다(CASCADE 가 충당을 지우기 전 · 같은 트랜잭션)
      v_rv := v_rv || public.po_payment_alloc_cost_reverse(x.id, 'payment deleted (' || coalesce(v_pay.reference, v_pay.paid_on::text) || ')');
    end loop;
    delete from public.po_payment where id = p_id;
    get diagnostics v_del = row_count;                          -- ②-b
    if v_del = 0 then
      raise exception 'Payment % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', coalesce(v_pay.reference, p_id::text);
    end if;

    return jsonb_build_object(
      'deleted', true, 'target', 'payment', 'id', v_pay.id, 'reference', v_pay.reference, 'paid_on', v_pay.paid_on, 'amount', v_pay.amount,
      'allocs_deleted', v_lines, 'docs', v_txt,                                   -- docs = 미지급이 되살아난 문서 번호(없으면 null)
      'cost_reversed', v_rv);                                                      -- po-disc-4a2 · 충당마다 되돌린 사건
  end if;

  -- ══════════ 인보이스 · 크레딧 (100000 그대로) ══════════
  select * into v_inv from public.po_invoice where id = p_id;
  if not found then raise exception 'Invoice % not found — nothing was deleted', p_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;

  if v_inv.doc_kind = 'credit' then
    raise exception 'Credit note % cannot be deleted — cancel it instead; its number must never be reused by another credit note — nothing was deleted', v_inv.invoice_number;
  end if;

  if v_inv.confirmed_at is not null then
    raise exception '% % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
      v_label, v_inv.invoice_number, to_char(v_inv.confirmed_at, 'YYYY-MM-DD');
  end if;

  select count(*), string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_n, v_txt
  from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id where pa.po_invoice_id = p_id;
  if v_n > 0 then
    raise exception '% % has payments applied (%) — remove the payment allocation first — nothing was deleted', v_label, v_inv.invoice_number, v_txt;
  end if;

  select count(*), string_agg(c.invoice_number, ', ' order by c.invoice_number) into v_n, v_txt
  from public.po_invoice c where c.credit_for_invoice_id = p_id;
  if v_n > 0 then
    raise exception 'Invoice % has % credit note(s) pointing at it (%) — cancel and detach those first — nothing was deleted', v_inv.invoice_number, v_n, v_txt;
  end if;

  select count(*) into v_lines from public.po_invoice_line     where po_invoice_id = p_id;
  select count(*) into v_discs from public.po_invoice_discount where po_invoice_id = p_id;
  delete from public.po_invoice where id = p_id;
  get diagnostics v_del = row_count;                            -- ②-b
  if v_del = 0 then
    raise exception '% % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_label, v_inv.invoice_number;
  end if;

  return jsonb_build_object(
    'deleted', true, 'target', 'invoice', 'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status_before', v_inv.status,
    'lines_deleted', v_lines, 'discounts_deleted', v_discs);
end;
$$;

-- ═══ ⑤ P&G 백필(📌 4) — 실제 행을 바꾸는 유일한 자리: 인보이스 1030266656 조건(2.1% · pre_tax · 2026-10-21) · due_date 2026-11-07(Net30) · 충당 할인 952.08 의 사건 13(pending · 입고 0 · 판정 391 실물 재료) ═══
--   ⬜5 잠금 트리거(po_invoice_early_lock)는 이 인보이스의 충당이 이미 952.08 을 쓰고 있어 조건 수정을 막는다 → 그 트리거만 한 문장 동안 끈다(replica 는 FK · touch 까지 끈다) · 사건은 p_post false(창구를 안 부른다 — 레이어 0 · claims 없는 적용 세션)
alter table public.po_invoice disable trigger po_invoice_early_lock;
update public.po_invoice
   set early_discount_pct = 2.1, early_discount_amount = null, early_discount_basis = 'pre_tax', early_discount_until = date '2026-10-21', due_date = date '2026-11-07'
 where invoice_number = '1030266656' and doc_kind = 'invoice' and status = 'confirmed' and early_discount_basis is null;
alter table public.po_invoice enable trigger po_invoice_early_lock;
do $$
declare v_al uuid; v_j jsonb;
begin
  if (select count(*) from public.po_invoice where invoice_number = '1030266656' and early_discount_pct = 2.1 and early_discount_basis = 'pre_tax' and early_discount_until = date '2026-10-21' and due_date = date '2026-11-07') <> 1 then
    raise exception using errcode = 'IM396', message = 'STOP - po-disc-4a2 backfill: invoice 1030266656 terms were not written (not found, not confirmed, or terms already present) - nothing was changed';
  end if;
  select a.id into v_al from public.po_payment_alloc a join public.po_invoice i on i.id = a.po_invoice_id where i.invoice_number = '1030266656' and a.discount_amount = 952.08;
  if v_al is null then raise exception using errcode = 'IM396', message = 'STOP - po-disc-4a2 backfill: the P&G allocation with discount 952.08 was not found - nothing was changed'; end if;
  if exists (select 1 from public.inv_cost_adjust j where j.source_id = v_al) then raise exception using errcode = 'IM396', message = 'STOP - po-disc-4a2 backfill: cost events for the P&G allocation already exist - nothing was changed'; end if;
  v_j := public.po_payment_alloc_cost_events(v_al, false);
  raise notice 'po-disc-4a2 backfill P&G 1030266656: events % · cost_part % · tax_part % · other_part %', v_j ->> 'event_count', v_j ->> 'cost_part', v_j ->> 'tax_part', v_j ->> 'other_part';
end $$;

-- ═══ ⑧ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text; v_n int; v_sum numeric;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_payment_alloc' and column_name in ('discount_tax_part', 'discount_other_part')) <> 2 then v_bad := v_bad || ' alloc-columns'; end if;
  foreach v_t in array array['public.po_invoice_discount_parts(uuid, numeric, text)'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  foreach v_t in array array['public.po_payment_alloc_cost_events(uuid, boolean)', 'public.po_payment_alloc_cost_reverse(uuid, text)'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_create', 'po_payment_alloc_delete', 'po_doc_delete') and p.prosecdef and p.prosrc like '%po-disc-4a2%') <> 3 then v_bad := v_bad || ' reissued-three(definer+marker)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_guard', 'po_payment_alloc_guard') and p.prosrc like '%delete this payment and enter it again%' and p.prosrc not like '%Adjust discount),%') <> 2 then v_bad := v_bad || ' guards(sentence)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_alloc_set', 'po_payment_target_check', 'po_invoice_early_discount', 'po_early_discount_calc', 'inv_layer_post_cost_adjust', 'inv_cost_adjust_reverse', 'po_receipt_confirm_by', 'po_invoice_line_cost') and p.prosrc like '%po-disc-4a2%') <> 0 then v_bad := v_bad || ' untouched-functions-touched'; end if;
  if md5(pg_get_viewdef('public.po_invoice_money'::regclass)) <> '08f428cbc4a0534df0eaa08ade03aa38' then v_bad := v_bad || ' po_invoice_money-changed'; end if;
  select count(*), coalesce(sum(j.amount_cad), 0) into v_n, v_sum
    from public.inv_cost_adjust j join public.po_payment_alloc a on a.id = j.source_id join public.po_invoice i on i.id = a.po_invoice_id
   where j.source_type = 'po_payment_alloc' and i.invoice_number = '1030266656';
  if v_n <> 13 or v_sum <> -952.08 then v_bad := v_bad || format(' pg-backfill(events %s · sum %s)', v_n, v_sum); end if;
  if exists (select 1 from public.inv_cost_adjust j join public.po_payment_alloc a on a.id = j.source_id join public.po_invoice i on i.id = a.po_invoice_id where i.invoice_number = '1030266656' and (j.status <> 'pending' or j.kind <> 'settlement_discount' or j.target_type <> 'po_line')) then v_bad := v_bad || ' pg-backfill(status)'; end if;
  if exists (select 1 from public.inv_layer y join public.po_line pl on pl.id::text = y.line_ref join public.po_invoice_line il on il.po_line_id = pl.id join public.po_invoice i on i.id = il.po_invoice_id where i.invoice_number = '1030266656') then v_bad := v_bad || ' pg-backfill(layers-exist)'; end if;
  if (select count(*) from public.po_payment p join public.po_payment_alloc a on a.po_payment_id = p.id join public.po_invoice i on i.id = a.po_invoice_id where i.invoice_number = '1030266656' and p.amount = 50278.68 and p.discount_taken = 952.08 and a.amount = 51230.76 and a.discount_amount = 952.08 and a.discount_tax_part = 0 and a.discount_other_part = 0) <> 1 then v_bad := v_bad || ' pg-backfill(payment-changed)'; end if;
  if (select count(*) from public.inv_cost_adjust j where j.source_type = 'po_payment_alloc') <> 13 then v_bad := v_bad || ' other-events-made'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM397', message = format('STOP - po-disc-4a2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
