-- ─────────────────────────────────────────────────────────────
-- 공급처 할인 → 재고 원가 ④-b — 「To pay」 읽기 창구 · 비용 청구서 할인 → landed(판정 393) · 할인 고치기 창구 · CBSA 할인 사건(pending) (Asung-IMS · po-disc-4b · 2026-10-09)
--   정본(뒤에 적는다): so-module §53 판정 391 · 393 · 395 · 399(2026-10-08 · Caleb) · po-module §11-f 「비용」 · §11-h 「조기 결제 할인 — 결제에서」
--   판정 391  「To pay」 = po_pay_candidates(공급처 · 통화 · 결제일) — 확정 인보이스 + 확정 비용 청구서의 미지급(세금 포함) · 인보이스 할인 조건과 결제일 기준 할인(식 한 곳 po_early_discount_calc) · 비용 청구서는 조건 칸이 없어 null
--   판정 393  비용 청구서 할인도 landed 를 낮춘다 — po_payment_create 의 비용 청구서 원소 discount(+ discount_basis) · 식 한 곳 po_charge_discount_parts · 배분 줄(po_charge_alloc) 금액 비율 · 배분 줄마다 사건(target charge_alloc · 환율 = 청구서) · ⬜1 그 배분 줄의 landed 가 아직 레이어에 안 얹혔으면 사건은 pending(레이어가 있어도 · 부르는 쪽에서 가른다 — 창구 무재발행) → landed 가 얹히는 순간(입고 확정 ⓕ) 뒤 ⓖ 가 얹는다
--   판정 395  세금 포함 기준 할인은 세금 몫을 충당 칸에 기록만 · tax_amount 0 이면 기준이 결과를 안 바꾼다(CBSA)
--   할인 고치기  po_payment_alloc_discount_set(충당 · 새 할인 · 미리 보기 · basis) — 낸 돈 고정 · 충당 amount 가 할인 차이만큼(⬜3) · 미지급 초과 거부(po_payment_target_check) · 옛 사건 전부 되돌림 + 새 사건 · 0 이면 되돌림만(⬜4 잠금은 저절로 풀린다 — 잠금은 discount_amount > 0 인 충당을 본다)
--   CBSA(⬜2)  10039192310530 의 landed 는 지금 얹을 수 없다(PO-02001a 입고 0 · PO-02002a 레이어 35.39 에 1,949.88 은 뜻이 없다 · 입고 확정이 ⓕ 보다 19분 앞섰다) → 할인 사건 둘(−39.00 · −11.95)을 pending 으로만 만든다(⬜1 규칙 그대로 · landed 백필 ⑯ 때 함께)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 — po_payment_alloc_cost_events(20261009013612:64~148 + 비용 갈래 · p_basis · 되돌린 사건은 「이미 있음」에서 제외) · po_payment_create(20261009013612 ①:232~395 + 비용 원소 할인 · basis · 사건) · 경고 charge_discount_not_costed_yet 제거
--   원칙 1: IMS 는 Cin7 없이 돈다 — 할인 · 원가의 재료는 IMS 결제 · IMS 비용 청구서 · IMS 환율
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

-- ═══ ① 「To pay」 읽기 창구 — 확정 인보이스(unpaid > 0) + 확정 비용 청구서(unpaid > 0) · 할인은 결제일(p_on · 없으면 오늘) 기준 · 정렬 할인 기한 → 만기 → 번호 · setof(화면이 rows 로 그대로 · ⬜5) ═══
create function public.po_pay_candidates(p_supplier_id uuid default null, p_currency_id uuid default null, p_on date default null)
  returns table (kind text, id uuid, number text, supplier_id uuid, supplier_name text, currency_id uuid, currency_code text,
                 doc_date date, due_date date, unpaid numeric, po_numbers text,
                 terms_source text, early_discount_pct numeric, early_discount_amount numeric, early_discount_basis text, early_discount_until date,
                 discount_available numeric, discount_valid boolean, days_left int, discount_expired boolean, valid_on date)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_on date := coalesce(p_on, public.ims_today());
begin
  perform public.ims_require_write('purchasing', 'read');                    -- 문(purchasing) — 결제 화면의 축
  return query
  with inv as (
    select 'invoice'::text as kind, l.id, l.invoice_number as number, l.supplier_id, l.supplier_name, l.currency_id, l.currency_code,
           l.invoice_date as doc_date, l.due_date, l.unpaid, l.po_numbers,
           case when l.early_discount_pct is not null or l.early_discount_amount is not null then 'invoice' end as terms_source,
           l.early_discount_pct, l.early_discount_amount, l.early_discount_basis, l.early_discount_until,
           c.discount, c.is_valid, c.days_left
      from public.po_invoice_list l
      join public.po_invoice_money m on m.id = l.id
      cross join lateral public.po_early_discount_calc(l.early_discount_pct, l.early_discount_amount, l.early_discount_basis, l.early_discount_until, m.payable_taxable, m.payable_net, v_on) c
     where l.status = 'confirmed' and l.doc_kind = 'invoice' and l.unpaid > 0
       and (p_supplier_id is null or l.supplier_id = p_supplier_id) and (p_currency_id is null or l.currency_id = p_currency_id)
  ), chg as (
    select 'charge'::text as kind, l.id, l.charge_number as number, l.supplier_id, l.supplier_name, l.currency_id, l.currency_code,
           l.charge_date as doc_date, l.due_date, l.unpaid, l.po_numbers,
           null::text as terms_source, null::numeric, null::numeric, null::text, null::date,
           null::numeric as discount, null::boolean as is_valid, null::int as days_left                                     -- 비용 청구서는 조건 칸이 없다 — 사람이 Pay 때 넣는다
      from public.po_charge_list l
     where l.status = 'confirmed' and l.unpaid > 0
       and (p_supplier_id is null or l.supplier_id = p_supplier_id) and (p_currency_id is null or l.currency_id = p_currency_id)
  ), u as (select * from inv union all select * from chg)
  select u.kind, u.id, u.number, u.supplier_id, u.supplier_name, u.currency_id, u.currency_code, u.doc_date, u.due_date, u.unpaid, u.po_numbers,
         u.terms_source, u.early_discount_pct, u.early_discount_amount, u.early_discount_basis, u.early_discount_until,
         case when u.terms_source is not null and u.is_valid then u.discount when u.terms_source is not null then 0 end as discount_available,   -- 기한 지나면 0 · 조건 없으면 null
         case when u.terms_source is not null then u.is_valid end as discount_valid,
         u.days_left,
         (u.terms_source is not null and not u.is_valid) as discount_expired,
         v_on as valid_on
    from u
   order by (case when u.terms_source is not null and u.is_valid then 0 else 1 end), u.early_discount_until nulls last, u.due_date nulls last, u.number;
end;
$$;
revoke all on function public.po_pay_candidates(uuid, uuid, date) from public, anon;
grant execute on function public.po_pay_candidates(uuid, uuid, date) to authenticated;
comment on function public.po_pay_candidates(uuid, uuid, date) is 'po-disc-4b ⭐ 「To pay」(판정 391 · 2026-10-09) — 확정 인보이스(doc_kind invoice · unpaid > 0) + 확정 비용 청구서(unpaid > 0) · 공급처 · 통화로 거른다 · unpaid 는 세금 포함(po_invoice_money.unpaid · po_charge_money.unpaid) · 인보이스 할인 = 결제일 p_on(없으면 오늘) 기준 po_early_discount_calc(기한 지나면 discount_available 0 · discount_expired true · 조건 없으면 null) · 비용 청구서는 조건 칸 없음(null · Pay 때 사람이) · 정렬 유효 할인 먼저 → 기한 → 만기 → 번호 · invoker(RLS select) · 문 purchasing · 화면 ⑥ 이 rows 로 그대로 쓴다';

-- ═══ ② 식 한 곳 — 비용 청구서 할인 → 원가 몫 · 세금 몫(판정 393 · 395) · 기준 pre_tax(total_amount) | with_tax(total_amount + tax_amount) · tax 0 이면 기준 무관 ═══
create function public.po_charge_discount_parts(p_charge_id uuid, p_discount numeric, p_basis text default null)
  returns table (basis text, base_amount numeric, pre_tax numeric, tax_amount numeric, cost_part numeric, tax_part numeric)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with c as (
    select coalesce(p_basis, 'pre_tax') as basis, ch.total_amount as pre_tax, coalesce(ch.tax_amount, 0) as tax_amount,
           case when coalesce(p_basis, 'pre_tax') = 'with_tax' then ch.total_amount + coalesce(ch.tax_amount, 0) else ch.total_amount end as base_amount
    from public.po_charge ch where ch.id = p_charge_id
  ), p as (
    select c.*, case when c.base_amount > 0 and c.basis = 'with_tax' then round(coalesce(p_discount, 0) * c.tax_amount / c.base_amount, 2) else 0 end as tax_part from c
  )
  select p.basis, p.base_amount, p.pre_tax, p.tax_amount, coalesce(p_discount, 0) - p.tax_part as cost_part, p.tax_part from p   -- 끝수는 원가 몫에 · 합 = 할인
$$;
revoke all on function public.po_charge_discount_parts(uuid, numeric, text) from public, anon;
grant execute on function public.po_charge_discount_parts(uuid, numeric, text) to authenticated;
comment on function public.po_charge_discount_parts(uuid, numeric, text) is 'po-disc-4b ⭐ 비용 청구서 할인을 둘로 가르는 식 한 곳(판정 393 · 395) — 기준 pre_tax(total_amount · 세금 전) | with_tax(total_amount + tax_amount) · 세금 몫 = with_tax 일 때 할인 × tax_amount ÷ 기준(round 2) · 원가 몫 = 할인 − 세금 몫(끝수) · tax_amount 0 이면 기준이 결과를 안 바꾼다(CBSA) · po_payment_create(미리 보기 · 저장) · po_payment_alloc_cost_events · po_payment_alloc_discount_set 이 부른다';


-- ═══ ②-b po_payment_alloc_cost_events 재발행 — 마지막 정의 20261009013612:64~148(DB md5 76c991df · 검증 G0) 바이트 복사 + 인자 p_basis(시그니처 바뀜 · 옛 것 drop) · declare 1 · 비용 갈래 블록(옛 skipped 4줄 대체) · 「이미 있음」 되돌린 사건 제외 ═══
drop function if exists public.po_payment_alloc_cost_events(uuid, boolean);
create function public.po_payment_alloc_cost_events(p_alloc_id uuid, p_post boolean default true, p_basis text default null) returns jsonb   -- po-disc-4b: p_basis = 비용 청구서 할인의 기준(pre_tax | with_tax · 인보이스는 조건 칸의 basis · 무시)
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'po_payment_alloc_cost_events@2026-10-09.2';   -- po-disc-4b: 비용 청구서 갈래(판정 393) · 되돌린 사건은 「이미 있음」에서 제외(할인 고치기)
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
  v_chg       public.po_charge%rowtype;  v_cp record;  v_ca record;  v_base text;  v_fx numeric;  v_cn int;  v_asum numeric;  v_landed boolean;  v_held int := 0;   -- po-disc-4b 비용 갈래
begin
  select * into v_al from public.po_payment_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — no cost was changed', p_alloc_id; end if;
  if v_al.po_charge_id is not null then                                                                   -- ═══ po-disc-4b(판정 393 · 395) · 비용 청구서 할인 → 배분 줄(po_charge_alloc)마다 사건(target charge_alloc) · ⬜1 landed 가 아직 레이어에 없는 배분 줄은 pending 으로(레이어가 있어도) ═══
    if coalesce(v_al.discount_amount, 0) <= 0 then
      return jsonb_build_object('alloc_id', p_alloc_id, 'skipped', 'no_discount', 'events', '[]'::jsonb, 'builder', c_version);
    end if;
    if exists (select 1 from public.inv_cost_adjust j where j.source_type = 'po_payment_alloc' and j.source_id = p_alloc_id and not exists (select 1 from public.inv_cost_adjust r where r.reverses_id = j.id)) then
      raise exception 'Allocation line % already has cost events — they are reversed when the allocation is removed or its discount changed, not re-made — no cost was changed', p_alloc_id;
    end if;
    select * into v_pay from public.po_payment where id = v_al.po_payment_id;
    select * into v_chg from public.po_charge where id = v_al.po_charge_id;
    select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
    select k.value into v_base from public.inv_config k where k.key = 'base_currency';
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    v_src := coalesce(nullif(v_pay.reference, ''), 'PAY ' || v_pay.paid_on::text || ' ' || v_chg.charge_number);
    select * into v_cp from public.po_charge_discount_parts(v_chg.id, v_al.discount_amount, p_basis);
    update public.po_payment_alloc set discount_tax_part = v_cp.tax_part, discount_other_part = 0 where id = p_alloc_id;
    select count(*), coalesce(sum(a.amount), 0) into v_cn, v_asum from public.po_charge_alloc a where a.po_charge_id = v_chg.id;
    if v_cn = 0 or v_asum <= 0 or v_cp.cost_part <= 0 then
      return jsonb_build_object('alloc_id', p_alloc_id, 'charge_number', v_chg.charge_number, 'discount', v_al.discount_amount, 'basis', v_cp.basis, 'cost_part', v_cp.cost_part, 'tax_part', v_cp.tax_part, 'other_part', 0, 'skipped', 'no_cost_part', 'events', '[]'::jsonb, 'builder', c_version);
    end if;
    v_fx := case when v_cur is distinct from v_base then v_chg.exchange_rate end;                             -- 환율 = 청구서(CAD per 통화) · 기준통화면 null
    if v_cur is distinct from v_base and (v_fx is null or v_fx <= 0) then
      raise exception 'Charge % is in % but has no exchange rate — the discount cannot be put on stock cost without it; enter the rate on the charge first — nothing was saved', v_chg.charge_number, coalesce(v_cur, '?');
    end if;
    for v_ca in
      select a.id, a.amount, a.posted_on, coalesce(p.po_number, tr.transfer_number) as target
        from public.po_charge_alloc a left join public.po p on p.id = a.po_id left join public.inv_transfer tr on tr.id = a.transfer_id
       where a.po_charge_id = v_chg.id
       order by coalesce(p.po_number, tr.transfer_number), a.id
    loop
      v_i := v_i + 1;
      if v_i = v_cn then v_share := v_cp.cost_part - v_given; else v_share := round(v_cp.cost_part * v_ca.amount / v_asum, 2); end if;   -- 배분 줄 금액 비율 · 끝수 마지막
      v_given := v_given + v_share;
      if v_share = 0 then continue; end if;
      v_landed := v_ca.posted_on is not null or exists (select 1 from public.inv_layer_cost_add x where x.kind = 'landed' and x.doc_number = v_chg.charge_number and x.line_ref = v_ca.id::text);   -- ⬜1: 그 배분 줄의 landed 가 레이어에 있나
      insert into public.inv_cost_adjust (kind, target_type, po_charge_alloc_id, amount_cad, amount_doc, currency_id, exchange_rate, source_type, source_id, source_number, note, created_by, updated_by)
      values ('settlement_discount', 'charge_alloc', v_ca.id, -v_share * coalesce(v_fx, 1), -v_share, v_chg.currency_id, v_fx, 'po_payment_alloc', p_alloc_id, v_src,
              format('discount %s on charge %s (%s · basis %s · allocation %s%s)', v_al.discount_amount, v_chg.charge_number, v_src, v_cp.basis, v_ca.target, case when v_landed then '' else ' · held: landed not on cost yet' end), v_staff, v_staff)
      returning id into v_id;
      v_j := null;
      if not v_landed then v_held := v_held + 1;
      elsif p_post then v_j := public.inv_layer_post_cost_adjust(v_id); end if;                              -- 판정 391 · 399 거부는 예외로 올라간다 = 결제 전체 안 저장
      v_events := v_events || jsonb_build_object('id', v_id, 'alloc_id', v_ca.id, 'target', v_ca.target, 'alloc_amount', v_ca.amount, 'landed_posted', v_landed,
                                                 'amount_doc', -v_share, 'exchange_rate', v_fx, 'amount_cad', -v_share * coalesce(v_fx, 1),
                                                 'status', coalesce(v_j ->> 'status', 'pending'), 'layers', coalesce((v_j ->> 'layers')::int, 0), 'posted_cad', coalesce((v_j ->> 'posted_cad')::numeric, 0));
    end loop;
    return jsonb_build_object('alloc_id', p_alloc_id, 'charge_number', v_chg.charge_number, 'currency', v_cur, 'discount', v_al.discount_amount, 'basis', v_cp.basis, 'base_amount', v_cp.base_amount,
                              'cost_part', v_cp.cost_part, 'tax_part', v_cp.tax_part, 'other_part', 0, 'events', v_events, 'event_count', jsonb_array_length(v_events),
                              'held_landed_not_posted', v_held, 'posted', p_post, 'builder', c_version);
  end if;
  if coalesce(v_al.discount_amount, 0) <= 0 then
    return jsonb_build_object('alloc_id', p_alloc_id, 'skipped', 'no_discount', 'events', '[]'::jsonb, 'builder', c_version);
  end if;
  if exists (select 1 from public.inv_cost_adjust j where j.source_type = 'po_payment_alloc' and j.source_id = p_alloc_id and not exists (select 1 from public.inv_cost_adjust r where r.reverses_id = j.id)) then   -- po-disc-4b: 되돌린 사건은 「이미 있음」이 아니다(할인 고치기가 되돌리고 다시 만든다)
    raise exception 'Allocation line % already has cost events — they are reversed when the allocation is removed or its discount changed, not re-made — no cost was changed', p_alloc_id;
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
revoke all on function public.po_payment_alloc_cost_events(uuid, boolean, text) from public, anon, authenticated;
comment on function public.po_payment_alloc_cost_events(uuid, boolean, text) is 'po-disc-4a2 · 4b ⭐ 충당 하나의 할인 → 원가 사건 — 인보이스(판정 391 · 395 · 398 · PO 줄마다 · po_invoice_discount_parts · 환율 po_invoice_line_cost) · 비용 청구서(판정 393 · 배분 줄마다 target charge_alloc · po_charge_discount_parts(p_basis) · 환율 청구서 · ⬜1 그 배분 줄의 landed 가 레이어에 없으면 pending — held_landed_not_posted) · 되돌린 사건은 「이미 있음」이 아니다 · p_post 면 inv_layer_post_cost_adjust(no_layers = pending · 399 거부는 예외) · 충당 칸 discount_tax_part · discount_other_part 를 적는다';

-- ═══ ③ po_payment_create 재발행 — 마지막 정의 20261009013612 ①(DB md5 0e991ab1 · 검증 G0) 바이트 복사 + declare 1 · 비용 청구서 원소 블록(거부 · 경고 charge_discount_not_costed_yet 제거 → discount · discount_basis · 세 몫) · 사건 호출 조건 · basis 인자 ═══
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
  v_cb         text;                                           -- po-disc-4b: 비용 청구서 원소의 discount_basis(pre_tax | with_tax · 없으면 pre_tax)
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
    if v_kind = 'charge' then                                                                                -- po-disc-4b(판정 393): 비용 청구서 할인 — 원소 discount(+ discount_basis) · 옛 모양은 p_discount_taken · 조건 칸이 없어 제안 없음 · 사건은 저장 때(landed 없으면 보류)
      v_cb := nullif(r->>'discount_basis', '');
      if v_cb is not null and v_cb not in ('pre_tax', 'with_tax') then raise exception 'p_targets[] discount_basis must be pre_tax or with_tax (got % for %) — nothing was saved', v_cb, t.target_number; end if;
      if v_legacy then
        v_dsc := case when v_disc > 0 then v_disc else 0 end;
        if v_dsc > 0 then v_dsrc := 'legacy'; end if;
      elsif v_dsc is null then
        v_dsc := 0;
      else
        v_dsrc := 'given';
      end if;
      if v_dsc > v_amt then raise exception 'Charge %: discount % is larger than the amount allocated to it (%) — nothing was saved', t.target_number, v_dsc, v_amt; end if;
      if v_dsc > 0 then select basis, cost_part, tax_part, 0 into v_pb, v_pc, v_pt, v_po from public.po_charge_discount_parts(v_tid, v_dsc, v_cb); end if;
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
      if coalesce((r->>'discount')::numeric, 0) > 0 then                                                   -- po-disc-4a2(판정 391) · po-disc-4b(393 비용도) · 저장 순간 원가 사건 — 레이어 없으면 pending · 399 거부는 예외 = 결제 전체 안 저장
        v_cost := public.po_payment_alloc_cost_events(v_aid, true, r->>'discount_basis');                   -- po-disc-4b · 비용은 원소의 basis(인보이스는 무시)
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

-- ═══ ④ 할인 고치기 창구 — 낸 돈 고정 · 충당 amount 가 할인 차이만큼(⬜3) · 미지급 초과 거부 · 옛 사건 전부 되돌림 + 새 사건 · 미리 보기 ═══
create function public.po_payment_alloc_discount_set(p_alloc_id uuid, p_discount numeric, p_commit boolean default false, p_discount_basis text default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_al      public.po_payment_alloc%rowtype;
  v_pay     public.po_payment%rowtype;
  v_kind    text;  v_tid uuid;  v_num text;
  v_eds     record;
  t         record;
  v_new_amt numeric;
  v_warn    text[] := '{}';
  v_basis   text;
  v_pb text; v_pc numeric; v_pt numeric; v_po numeric;
  v_rv      jsonb := '{}'::jsonb;
  v_ev      jsonb := '{}'::jsonb;
  v_prev    text;
  v_cur_ev  jsonb;
  v_n       int;
begin
  perform public.ims_require_write('purchasing', 'saved');
  if p_discount is null or p_discount < 0 then raise exception 'p_discount must be 0 or above (got %) — nothing was saved', p_discount; end if;
  if p_discount_basis is not null and p_discount_basis not in ('pre_tax', 'with_tax') then raise exception 'p_discount_basis must be pre_tax or with_tax (got %) — nothing was saved', p_discount_basis; end if;
  select * into v_al from public.po_payment_alloc where id = p_alloc_id for update;
  if not found then raise exception 'Allocation line % not found — nothing was saved', p_alloc_id; end if;
  select * into v_pay from public.po_payment where id = v_al.po_payment_id;
  v_kind := case when v_al.po_charge_id is not null then 'charge' else 'invoice' end;
  v_tid  := coalesce(v_al.po_invoice_id, v_al.po_charge_id);
  -- ⬜3 낸 돈은 은행 사실 — 충당 amount 가 할인 차이만큼 움직인다 · Σ충당 = amount + Σ할인 그대로
  v_new_amt := v_al.amount + (p_discount - v_al.discount_amount);
  if v_new_amt <= 0 then raise exception 'Lowering the discount to % would take this line''s amount to % — a line must settle more than 0; remove the line instead — nothing was saved', p_discount, v_new_amt; end if;
  select * into t from public.po_payment_target_check(v_kind, v_tid, v_new_amt, v_pay.currency_id, v_al.id);   -- 미지급 초과면 여기서 거부(고치는 줄의 금액은 되돌려 놓고 본다)
  v_num := t.target_number;
  if p_discount > v_new_amt then raise exception '% %: discount % is larger than the amount allocated to it (%) — nothing was saved', case v_kind when 'invoice' then 'Invoice' else 'Charge' end, v_num, p_discount, v_new_amt; end if;
  if v_kind = 'invoice' then
    select * into v_eds from public.po_invoice_early_discount(v_tid, v_pay.paid_on);
    if p_discount > 0 and v_eds.has_terms and not v_eds.is_valid then v_warn := array_append(v_warn, 'discount_after_deadline:' || v_num); end if;
    if p_discount > 0 and not v_eds.has_terms then v_warn := array_append(v_warn, 'discount_without_terms:' || v_num); end if;
    if p_discount > 0 then select basis, cost_part, tax_part, other_part into v_pb, v_pc, v_pt, v_po from public.po_invoice_discount_parts(v_tid, p_discount, null); end if;
  else
    v_basis := coalesce(p_discount_basis, 'pre_tax');
    if p_discount > 0 then select basis, cost_part, tax_part, 0 into v_pb, v_pc, v_pt, v_po from public.po_charge_discount_parts(v_tid, p_discount, v_basis); end if;
  end if;
  select count(*), coalesce(jsonb_agg(jsonb_build_object('id', j.id, 'status', j.status, 'amount_cad', j.amount_cad, 'amount_doc', j.amount_doc) order by j.created_at, j.id), '[]'::jsonb) into v_n, v_cur_ev
    from public.inv_cost_adjust j where j.source_type = 'po_payment_alloc' and j.source_id = p_alloc_id and not exists (select 1 from public.inv_cost_adjust r where r.reverses_id = j.id);
  if p_commit then
    v_prev := current_setting('po.payment_door', true);  perform set_config('po.payment_door', '1', true);
    v_rv := public.po_payment_alloc_cost_reverse(p_alloc_id, format('discount changed %s → %s on payment %s', v_al.discount_amount, p_discount, coalesce(v_pay.reference, v_pay.paid_on::text)));
    update public.po_payment_alloc set amount = v_new_amt, discount_amount = p_discount, discount_tax_part = 0, discount_other_part = 0 where id = p_alloc_id;   -- Σ 트리거가 discount_taken 을 맞춘다 · 잠금(⬜4)은 discount_amount > 0 을 보므로 0 이면 저절로 풀린다
    perform set_config('po.payment_door', coalesce(v_prev, ''), true);
    if p_discount > 0 then v_ev := public.po_payment_alloc_cost_events(p_alloc_id, true, v_basis); end if;   -- 판정 399 거부는 예외 = 전체 안 저장
  end if;
  return jsonb_build_object('committed', p_commit, 'alloc_id', p_alloc_id, 'payment_id', v_pay.id, 'kind', v_kind, 'target_number', v_num,
                            'before', jsonb_build_object('amount', v_al.amount, 'discount', v_al.discount_amount, 'events', v_cur_ev, 'event_count', v_n),
                            'after',  jsonb_build_object('amount', v_new_amt, 'discount', p_discount, 'basis', coalesce(v_pb, v_basis), 'cost_part', v_pc, 'tax_part', v_pt, 'other_part', v_po),
                            'delta', p_discount - v_al.discount_amount, 'payment_amount', v_pay.amount,
                            'reversed', v_rv, 'cost_events', v_ev, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.po_payment_alloc_discount_set(uuid, numeric, boolean, text) from public, anon;
grant execute on function public.po_payment_alloc_discount_set(uuid, numeric, boolean, text) to authenticated;
comment on function public.po_payment_alloc_discount_set(uuid, numeric, boolean, text) is 'po-disc-4b ⭐ 충당 하나의 할인 고치기(판정 391 · 2026-10-09) — 낸 돈(po_payment.amount)은 고정 · 충당 amount 가 할인 차이만큼 움직인다(Σ충당 = amount + Σ할인) · 미지급 초과는 po_payment_target_check 가 거부 · 저장: 옛 사건 전부 되돌림(po_payment_alloc_cost_reverse) → 충당 갱신(플래그) → 새 할인 > 0 이면 사건 다시(po_payment_alloc_cost_events · 비용은 p_discount_basis) · 0 이면 되돌림만(조건 잠금은 저절로 풀린다) · 미리 보기(p_commit false) 는 before/after · 지금 사건 · 경고(discount_after_deadline · discount_without_terms) · 문 purchasing · 화면 ⑥ 「Adjust discount」 단추의 창구(문지기 문장 표식 ADJUST-DISCOUNT-BUTTON 은 그때 고친다)';

-- ═══ ⑤ CBSA 할인 사건(⬜2) — landed 는 지금 안 얹는다 · 할인 사건 둘을 pending 으로만(원가 몫 50.95 · 기준 pre_tax = with_tax(tax 0) · 배분 1,949.88 : 597.49 → −39.00 · −11.95) ═══
do $$
declare v_al uuid; v_j jsonb;
begin
  select a.id into v_al from public.po_payment_alloc a join public.po_charge c on c.id = a.po_charge_id join public.po_payment p on p.id = a.po_payment_id
   where c.charge_number = '10039192310530' and p.reference = 'EFT-20260916-02' and a.discount_amount = 50.95;
  if v_al is null then raise exception using errcode = 'IM398', message = 'STOP - po-disc-4b: the CBSA allocation (EFT-20260916-02 · 10039192310530 · discount 50.95) was not found - nothing was changed'; end if;
  if exists (select 1 from public.inv_cost_adjust j where j.source_id = v_al) then raise exception using errcode = 'IM398', message = 'STOP - po-disc-4b: cost events for the CBSA allocation already exist - nothing was changed'; end if;
  v_j := public.po_payment_alloc_cost_events(v_al, false, 'pre_tax');
  raise notice 'po-disc-4b CBSA 10039192310530: events % · cost_part % · tax_part % · held %', v_j ->> 'event_count', v_j ->> 'cost_part', v_j ->> 'tax_part', v_j ->> 'held_landed_not_posted';
end $$;

-- ═══ ⑧ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text; v_n int; v_sum numeric;
begin
  foreach v_t in array array['public.po_pay_candidates(uuid, uuid, date)', 'public.po_charge_discount_parts(uuid, numeric, text)', 'public.po_payment_alloc_discount_set(uuid, numeric, boolean, text)'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  v_t := 'public.po_payment_alloc_cost_events(uuid, boolean, text)';
  if to_regprocedure(v_t) is null then v_bad := v_bad || ' cost_events(missing)'; end if;
  if to_regprocedure('public.po_payment_alloc_cost_events(uuid, boolean)') is not null then v_bad := v_bad || ' cost_events(old-signature-left)'; end if;
  if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') then v_bad := v_bad || ' cost_events(grants)'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_payment_create', 'po_payment_alloc_cost_events') and p.prosecdef and p.prosrc like '%po-disc-4b%') <> 2 then v_bad := v_bad || ' reissued-two'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%charge_discount_not_costed_yet%') <> 0 then v_bad := v_bad || ' old-warning-left'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_payment_alloc_cost_reverse', 'po_payment_alloc_delete', 'po_doc_delete', 'po_payment_alloc_set', 'po_payment_guard', 'po_payment_alloc_guard', 'inv_layer_post_cost_adjust', 'inv_layer_post_charge', 'po_charge_confirm', 'po_receipt_confirm_by', 'po_invoice_discount_parts') and p.prosrc like '%po-disc-4b%') <> 0 then v_bad := v_bad || ' untouched-functions-touched'; end if;
  select count(*), coalesce(sum(j.amount_cad), 0) into v_n, v_sum from public.inv_cost_adjust j join public.po_payment_alloc a on a.id = j.source_id join public.po_charge c on c.id = a.po_charge_id where c.charge_number = '10039192310530';
  if v_n <> 2 or v_sum <> -50.95 then v_bad := v_bad || format(' cbsa(events %s · sum %s)', v_n, v_sum); end if;
  if exists (select 1 from public.inv_cost_adjust j join public.po_payment_alloc a on a.id = j.source_id join public.po_charge c on c.id = a.po_charge_id where c.charge_number = '10039192310530' and (j.status <> 'pending' or j.target_type <> 'charge_alloc')) then v_bad := v_bad || ' cbsa(status)'; end if;
  if (select count(*) from public.inv_layer_cost_add x where x.doc_number = '10039192310530') <> 0 then v_bad := v_bad || ' cbsa(landed-posted)'; end if;
  if (select count(*) from public.po_payment p join public.po_payment_alloc a on a.po_payment_id = p.id where p.reference = 'EFT-20260916-02' and p.amount = 2496.42 and p.discount_taken = 50.95 and a.amount = 2547.37 and a.discount_amount = 50.95 and a.discount_tax_part = 0) <> 1 then v_bad := v_bad || ' cbsa(payment-changed)'; end if;
  if (select count(*) from public.inv_cost_adjust j where j.source_type = 'po_payment_alloc' and j.target_type = 'charge_alloc') <> 2 then v_bad := v_bad || ' other-charge-events-made'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM399', message = format('STOP - po-disc-4b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
