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

-- ═══ crn-2 — 크레딧 가격 조정 줄(지난 세일 차액) (2026-10-21 · 판정 603 · 611 · 612 · 613 · 614 · crn-0 · crn-1 뒤 · 정본 so-module §8-g · §19 · §22-c · §49 판정 325) ═══
--   계기: Caleb 「손님이 9.99에 물건을 사갔다고 가정할께 … 지나간 세일금액의 차만큼 돌려달라고 … 이것을 크레딧 노트로 만들려면」
--   ① 표: so_credit_line.kind 에 price_adjustment · 칸 셋 qty_adjusted · unit_price_before(낸 단가 — 인보이스 줄이면 오더 할인 뒤 · 613) · unit_price_after(새 단가) · 짝 CHECK so_credit_line_adjust_ck(셋 다 또는 다 null · qty > 0 · 0 ≤ after < before · amount = round((before − after) × qty, 2)) ·
--      qty_returned 는 null(so_credit_line_qty_ck 그대로 — 반품 수량을 세는 세 식은 손대지 않아도 「반품 가능 수량을 깎지 않는다」가 지켜진다 · 603) · so_credit_reason_ck 에 price_adjustment(612)
--   ② 층(tiers) — 도우미 so_credit_line_state(so_invoice_line_id): 인보이스 줄 하나의 판 수량을 「낸 단가 층」(gross × (1 − 오더 할인%) · 손으로 정한 줄은 할인 없음 · 613)에서 시작해 발행된 크레딧(취소 제외 · 발행일 · 시각 · 번호 순)을 되돌린다 —
--      반품은 낮은 층부터 뗀다(611 「조정된 몫부터」 · 조정이 여럿이면 더 낮은 새 단가 = 더 많이 조정된 몫부터 · §2-1) · 조정은 새 단가보다 비싼 가장 낮은 층에서 떼어 새 단가 층으로 옮긴다 ·
--      반환 = qty_sold · gross_unit_price · order_discount_pct · paid_unit_price · qty_returned · qty_returnable · qty_adjustable(낸 단가 층의 수량) · qty_adjusted_open(조정 층의 합) · tiers[{qty, unit_price, paid}] · adjustments[] ·
--      속 도우미 둘 so_credit_tiers_take(tiers, qty, 새 단가 | null) → {tiers, parts[]} · so_credit_tiers_add(tiers, qty, 단가) — 발행 · 준비 · 문서가 같은 식을 쓴다(§22-f ⬜ 「복사된 qty_credited 식」도 이 도우미로 닫힘)
--   ③ so_credit_issue — 가격 조정 줄은 둘째 바퀴(같은 크레딧의 반품이 먼저 낮은 층을 가져간다 · §2-2): 인보이스 줄 {so_invoice_line_id, qty, new_unit_price} — 새 단가 > 0(0 은 거부 · §2-3) · 그 층 안에서만(넘치면 나눠 보내라고 말한다) · 금액 = (층 단가 − 새 단가) × 수량 · 세율 = 그 줄 · 계정 = 그 인보이스 줄(614) ·
--      참조 크레딧 {sku, qty, paid_unit_price, new_unit_price} · 계정 _98_ · 반품 줄의 금액은 층에서(조정된 몫은 새 단가 · 낸 단가 몫은 인보이스 단가 — 오더 할인 거울은 그 몫만 기준으로 · 611 · 613 · 설명에 「(7 × 7.99 + 3 × 9.99)」) ·
--      조정 줄에는 오더 할인 거울 · surcharge 자동 · 운임 할인 거울 · 리스탁킹 피 기준 · 원장(inv_post_credit 은 product + 칸만) 모두 없다 · 경고 reason_not_price_adjustment · reason_price_adjustment_with_returns(막지 않음 · §2-4)
--   ④ so_credit_prepare — 줄마다 adjust{paid_unit_price · qty_adjustable · qty_adjusted_open · tiers · adjustments …} · vocab 에 price_adjustment
--   ⑤ doc_data_credit — 가격 조정 줄은 제품 표에(수량 = qty_adjusted · 단가 칸 = 개당 차액 · 설명 「Price adjustment 9.49 → 7.99 — …」) · charges 에서 뺀다
--   ⑥ so_credit_cancel — 가격 조정 줄이 든 크레딧은 그 뒤 같은 인보이스 줄에 발행된 크레딧이 있으면 취소 거부(뒤 것이 이 층으로 값이 매겨졌다 · 611) · 취소되면 층은 저절로 되살아난다(상태는 발행된 크레딧만 되돌린다)
--   ⚠️ 재발행 넷의 몸 = DB 원문 바이트 + 더한 · 바꾼 줄만(착지 md5) · 가격 조정이 없는 크레딧의 미리 보기 · 발행 · 상세 · 문서 · 원장은 그대로(동일성 시험 T13) · 운영에는 닿지 않는다(가드).

create temp table crn2_before as
select (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
         and p.proname in ('inv_post_credit', 'so_credit_detail', 'so_credit_attach', 'so_credit_detach', 'so_credit_alloc_add', 'so_credit_remaining', 'so_customer_balance', 'inv_layer_post_credit', 'so_detail', 'doc_data', 'so_tax_amount', 'so_line_manual', 'so_invoice_issue')) as others,
       (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_credit_issue', 'so_credit_prepare', 'doc_data_credit', 'so_credit_cancel')) as acls,
       (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.so_credit_line'::regclass and contype = 'c' and conname <> 'so_credit_line_kind_ck') as other_line_checks,
       (select count(*) from public.so_credit_line) as n_lines,
       (select count(*) || '/' || md5(coalesce(string_agg(l.id::text || l.kind || l.amount, ',' order by l.id), '')) from public.so_credit_line l) as lines_md5;

-- ═══ ① 표 ═══
alter table public.so_credit_line add column qty_adjusted numeric, add column unit_price_before numeric, add column unit_price_after numeric;
alter table public.so_credit_line drop constraint so_credit_line_kind_ck;
alter table public.so_credit_line add constraint so_credit_line_kind_ck check (kind = any (array['product', 'freight', 'tax', 'other', 'restocking_fee', 'surcharge', 'order_discount', 'freight_discount', 'price_adjustment']));
alter table public.so_credit_line add constraint so_credit_line_adjust_ck
  check ((kind = 'price_adjustment') = (qty_adjusted is not null) and (kind = 'price_adjustment') = (unit_price_before is not null) and (kind = 'price_adjustment') = (unit_price_after is not null)
         and (kind <> 'price_adjustment' or (qty_adjusted > 0 and unit_price_after >= 0 and unit_price_after < unit_price_before and amount = round((unit_price_before - unit_price_after) * qty_adjusted, 2))));
alter table public.so_credit drop constraint so_credit_reason_ck;
alter table public.so_credit add constraint so_credit_reason_ck check (reason = any (array['customer_return', 'damaged', 'billing_error', 'other', 'price_adjustment']));
comment on column public.so_credit_line.qty_adjusted      is 'crn-2 판정 603 — 가격 조정 줄(kind price_adjustment)의 조정 수량 · 반품 수량(qty_returned)은 null — 반품 가능 수량을 깎지 않는다';
comment on column public.so_credit_line.unit_price_before is 'crn-2 판정 603 · 613 — 낸 단가(인보이스 줄이면 오더 할인 뒤 · 앞선 조정이 있으면 그 층의 단가 · 참조 크레딧은 손으로) · amount = round((before − after) × qty_adjusted, 2)';
comment on column public.so_credit_line.unit_price_after  is 'crn-2 판정 603 · 611 — 새 단가(> 0 · before 보다 작다) · 뒤 반품은 이 몫부터 이 단가로(so_credit_line_state 의 층)';
comment on constraint so_credit_line_adjust_ck on public.so_credit_line is 'crn-2 판정 603: 가격 조정 줄은 qty_adjusted · unit_price_before · unit_price_after 셋 다 · 그 밖은 다 null · 0 ≤ after < before · amount = round((before − after) × qty, 2)';

-- ═══ ② 층 도우미 — so_credit_tiers_take · so_credit_tiers_add(속 · 실행권 없음) · so_credit_line_state(읽기 · authenticated) ═══
create function public.so_credit_tiers_take(p_tiers jsonb, p_qty numeric, p_above numeric) returns jsonb
language plpgsql immutable
set search_path = public, pg_temp
as $$
-- 층 배열 [{qty, unit_price, paid}] 에서 p_qty 만큼 뗀다 — 낮은 단가부터(p_above 가 있으면 그보다 비싼 층만) · 반환 {tiers(뗀 뒤), parts[{qty, unit_price, paid}](뗀 순서)} · 모자라면 있는 만큼만(부르는 쪽이 한도를 본다)
declare v_need numeric := p_qty; v_out jsonb := '[]'::jsonb; v_parts jsonb := '[]'::jsonb; t jsonb; v_q numeric; v_take numeric;
begin
  for t in select x from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb)) x order by (x->>'unit_price')::numeric, (x->>'paid')::boolean desc loop
    v_q := (t->>'qty')::numeric;
    if v_need > 0 and v_q > 0 and (p_above is null or (t->>'unit_price')::numeric > p_above) then
      v_take := least(v_q, v_need);  v_need := v_need - v_take;
      v_parts := v_parts || jsonb_build_object('qty', v_take, 'unit_price', (t->>'unit_price')::numeric, 'paid', (t->>'paid')::boolean);
      v_q := v_q - v_take;
    end if;
    if v_q > 0 then v_out := v_out || (t || jsonb_build_object('qty', v_q)); end if;
  end loop;
  return jsonb_build_object('tiers', v_out, 'parts', v_parts, 'short', v_need);
end;
$$;
revoke all on function public.so_credit_tiers_take(jsonb, numeric, numeric) from public, anon, authenticated;
create function public.so_credit_tiers_add(p_tiers jsonb, p_qty numeric, p_unit_price numeric) returns jsonb
language sql immutable
set search_path = public, pg_temp
as $$
  -- 조정 층 더하기 — 같은 단가의 조정 층이 있으면 합치고 없으면 새 층(paid false)
  select case when exists (select 1 from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb)) x where not (x->>'paid')::boolean and (x->>'unit_price')::numeric = p_unit_price)
              then (select jsonb_agg(case when not (x->>'paid')::boolean and (x->>'unit_price')::numeric = p_unit_price then x || jsonb_build_object('qty', (x->>'qty')::numeric + p_qty) else x end) from jsonb_array_elements(coalesce(p_tiers, '[]'::jsonb)) x)
              else coalesce(p_tiers, '[]'::jsonb) || jsonb_build_object('qty', p_qty, 'unit_price', p_unit_price, 'paid', false) end
$$;
revoke all on function public.so_credit_tiers_add(jsonb, numeric, numeric) from public, anon, authenticated;
create function public.so_credit_line_state(p_invoice_line_id uuid) returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp
as $$
-- crn-2 판정 603 · 611 · 613: 인보이스 제품 줄 하나의 「층」 — 낸 단가 층(qty_sold @ paid_unit_price · paid true)에서 시작해 발행된 크레딧(취소 제외 · 발행일 · 시각 · 줄 순)을 되돌린다 ·
--   반품(product)은 낮은 층부터 뗀다 · 조정(price_adjustment)은 새 단가보다 비싼 가장 낮은 층에서 떼어 새 단가 층으로 · 발행(so_credit_issue) · 준비(so_credit_prepare) · 상세가 함께 쓴다 · 콤보 줄은 조정이 없어 층 하나
declare
  v_il public.so_invoice_line%rowtype;  v_io public.so_invoice_order%rowtype;  v_sl public.so_line%rowtype;
  v_pct numeric := 0;  v_paid numeric;  v_tiers jsonb;  v_ret numeric := 0;  v_adj jsonb := '[]'::jsonb;  v_x jsonb;  r record;
begin
  select * into v_il from public.so_invoice_line l where l.id = p_invoice_line_id and l.kind = 'product';
  if v_il.id is null then return null; end if;
  select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
  select * into v_sl from public.so_line s where s.id = v_il.so_line_id;
  if coalesce(v_io.order_discount_pct, 0) > 0 and v_sl.id is not null and not public.so_line_manual(v_sl) then v_pct := v_io.order_discount_pct; end if;   -- od-1 판정 542 · 544 · crn-2 판정 613
  v_paid := round(coalesce(v_il.unit_price, 0) * (1 - v_pct / 100), 2);
  v_tiers := jsonb_build_array(jsonb_build_object('qty', v_il.qty, 'unit_price', v_paid, 'paid', true));
  for r in select l.kind, l.qty_returned, l.qty_adjusted, l.unit_price_before, l.unit_price_after, c.credit_number, c.issued_on
             from public.so_credit_line l join public.so_credit c on c.id = l.credit_id
            where l.so_invoice_line_id = p_invoice_line_id and c.status = 'issued' and l.kind in ('product', 'price_adjustment')
            order by c.issued_on, c.created_at, c.credit_number, l.line_no loop                                     -- 번호(CR-00000 · 오름차순)가 같은 트랜잭션의 동률을 가른다
    if r.kind = 'product' then
      v_x := public.so_credit_tiers_take(v_tiers, r.qty_returned, null);  v_tiers := v_x->'tiers';  v_ret := v_ret + r.qty_returned;
    else
      v_x := public.so_credit_tiers_take(v_tiers, r.qty_adjusted, r.unit_price_after);  v_tiers := public.so_credit_tiers_add(v_x->'tiers', r.qty_adjusted, r.unit_price_after);
      v_adj := v_adj || jsonb_build_object('credit_number', r.credit_number, 'issued_on', r.issued_on, 'qty', r.qty_adjusted, 'unit_price_before', r.unit_price_before, 'unit_price_after', r.unit_price_after);
    end if;
  end loop;
  return jsonb_build_object('so_invoice_line_id', v_il.id, 'qty_sold', v_il.qty, 'gross_unit_price', v_il.unit_price, 'order_discount_pct', v_pct, 'paid_unit_price', v_paid,
                            'qty_returned', v_ret, 'qty_returnable', v_il.qty - v_ret,
                            'qty_adjustable', coalesce((select sum((t->>'qty')::numeric) from jsonb_array_elements(v_tiers) t where (t->>'paid')::boolean), 0),
                            'qty_adjusted_open', coalesce((select sum((t->>'qty')::numeric) from jsonb_array_elements(v_tiers) t where not (t->>'paid')::boolean), 0),
                            'tiers', (select coalesce(jsonb_agg(t order by (t->>'unit_price')::numeric desc, (t->>'paid')::boolean desc), '[]'::jsonb) from jsonb_array_elements(v_tiers) t where (t->>'qty')::numeric > 0),
                            'adjustments', v_adj);
end;
$$;
revoke all on function public.so_credit_line_state(uuid) from public, anon;
grant execute on function public.so_credit_line_state(uuid) to authenticated, service_role;
comment on function public.so_credit_line_state(uuid) is 'crn-2(판정 603 · 611 · 613 · 2026-10-21) — 인보이스 제품 줄의 층: 낸 단가(오더 할인 뒤) · 반품 · 조정 · 조정 가능 · 열린 조정 몫 · tiers[{qty, unit_price, paid}] · adjustments[] — 발행 · 준비 · 화면이 같은 식을 쓴다 · 반품은 낮은 층부터 · 조정은 새 단가보다 비싼 가장 낮은 층에서';

-- ═══ so_credit_issue 재발행 — 원본 20261021194405_crn_1_reference_credit.sql:113 바이트 + 더한 · 바꾼 줄만 · crn-2 ═══
CREATE OR REPLACE FUNCTION public.so_credit_issue(p jsonb, p_commit boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other','price_adjustment'];   -- crn-2 판정 612
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
  v_ref       boolean := false;                                                                        -- crn-1 판정 602 · 609: 참조 크레딧(인보이스 없음 · 옛 이름 cin7)
  v_ref_inv   text;  v_ref_ord text;  v_ref_date date;
  v_tax_src   text;  v_sa public.customer_address%rowtype;  v_tr jsonb;  v_seen text;                  -- crn-1 판정 610: 세금 기본 = 손님 기본 배송지의 규칙 · 경고 reference_seen
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
  v_od_amt    numeric := 0;  v_od record;  v_od_il public.so_invoice_line%rowtype;                                      -- dsc-3b 판정 325 — 오더 할인 몫(인보이스-오더마다 음수 줄 하나)
  v_sc        public.so_invoice_line%rowtype;  v_sc_amt numeric := 0;  v_sc_line numeric;  v_sc_tax numeric;  v_sc_already numeric;   -- surcharge-2b(묶음 7)
  v_fd        public.so_invoice_line%rowtype;  v_fd_amt numeric := 0;  v_fd_line numeric := 0;  v_fd_tax numeric;  v_fd_already numeric;  v_fd_inv numeric;   -- fr-3 판정 355: 운임 할인 되돌림(인보이스 charge_discount 줄 · 같은 비율 · 끝수는 마지막에)
  v_rates     numeric[] := '{}';  v_first_rate numeric;
  v_fee_lines int := 0;  v_restock_n int := 0;
  v_fee_sugg  jsonb;
  v_warn      text[] := '{}';
  v_ledger    jsonb;
  v_est       numeric;  v_est_qty numeric;
  v_ask       numeric;
  x           jsonb;
  e           jsonb;
  -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄의 반품 — 콤보 크레딧 줄(금액 · qty = 콤보 수 · 칸 · 사유 없음 · combo_components) + 구성품 크레딧 줄(금액 0 · qty = n × combo_qty · 제 칸 또는 사유 · combo_credit_line_id) · 구성품 하나만의 상품 줄은 거부
  v_combo     jsonb;  cj jsonb;  v_cov jsonb;  v_def_bin text;  v_def_nr text;  v_def_note text;  v_cpr public.product%rowtype;  v_cq numeric;  v_idmap jsonb := '{}'::jsonb;  v_parent_ln int;
  -- crn-2(판정 603 · 611 · 613 · 614): 인보이스 줄마다 가격 층(tiers · so_credit_line_state) — 이 호출 안의 반품 · 조정이 차례로 깎는다 · v_odb = 줄 번호 → 오더 할인 거울의 기준 금액(조정된 몫은 뺀다)
  v_tiers     jsonb := '{}'::jsonb;  v_take jsonb;  v_tier jsonb;  v_odb jsonb := '{}'::jsonb;  v_od_base numeric;  v_before numeric;  v_after numeric;  v_adj_n int := 0;  v_ret_n int := 0;
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

  -- 원본 — IMS 인보이스 또는 참조 번호(옛 인보이스 종이 번호 · 판정 602 · 609 — 옛 열쇠 cin7 은 거부)
  if nullif(p->>'invoice_id', '') is not null then
    select * into v_inv from public.so_invoice i where i.id = (p->>'invoice_id')::uuid for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_inv.status <> 'issued' then raise exception 'Invoice % is % — credit the live invoice, not a cancelled one — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
    v_cust := v_inv.bill_to_customer_id;  v_origin_on := v_inv.issued_on;
    select * into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
    select o.* into v_first_io from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.location_id into v_wh from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id order by o.so_number limit 1;
  elsif p ? 'cin7' then
    raise exception 'The cin7 key is gone — send ref {invoice_number, order_number, invoice_date} for a credit without an IMS invoice — nothing was saved';   -- crn-1 판정 609
  elsif p->'ref' is not null and jsonb_typeof(p->'ref') = 'object' then
    v_ref := true;
    v_ref_inv := nullif(trim(p->'ref'->>'invoice_number'), '');  v_ref_ord := nullif(trim(p->'ref'->>'order_number'), '');  v_ref_date := nullif(p->'ref'->>'invoice_date', '')::date;
    if v_ref_inv is null then raise exception 'A reference credit needs ref.invoice_number (the number on the paper invoice) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A reference credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_ref_date;
    if not exists (select 1 from public.customer c where c.id = v_cust) then raise exception 'Customer not found — nothing was saved'; end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is not null then                                                  -- 보낸 규칙 그대로(활성 판매 규칙 검사 그대로)
      select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
      if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
      v_tax_src := 'given';
    else                                                                                                  -- crn-1 판정 610: 손님 기본 배송지의 주 → so_tax_rule_for(IMS 인보이스와 같은 식) · 없으면 거부(직원이 고른다)
      select * into v_sa from public.customer_address a where a.customer_id = v_cust and a.type = 'Shipping' and a.is_active and a.is_default_for_type limit 1;
      if v_sa.id is null then raise exception 'Pick a tax rule — the customer has no default ship-to address to suggest one from — nothing was saved'; end if;
      v_tr := public.so_tax_rule_for(v_sa.country, v_sa.state_province, v_on, 'sale');
      if nullif(v_tr->>'rule_id', '') is null then raise exception 'Pick a tax rule — no sale tax rule is linked to the customer''s default ship-to (% / %) — nothing was saved', coalesce(v_sa.country, '?'), coalesce(v_sa.state_province, '?'); end if;
      select * into v_rule from public.ref_tax_rule r where r.id = (v_tr->>'rule_id')::uuid;
      v_tax_src := 'ship_to';
    end if;
    select c.default_location_id into v_wh from public.customer c where c.id = v_cust;
  else
    raise exception 'Give invoice_id (an IMS invoice) or ref {invoice_number, order_number, invoice_date} (a credit without an IMS invoice) — nothing was saved';
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
    if v_kind = 'surcharge' then raise exception 'Surcharge lines are added automatically from the returned product lines — do not send them — nothing was saved'; end if;   -- surcharge-2b(D-3 · 자동만)
    if v_kind = 'freight_discount' then raise exception 'Freight discount lines are added automatically from the returned freight line — do not send them — nothing was saved'; end if;   -- fr-3 판정 355(자동만)
    if v_kind is null or v_kind not in ('product','freight','tax','other','restocking_fee','price_adjustment') then raise exception 'Line kind must be one of product, freight, tax, other, restocking_fee, price_adjustment — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    if v_kind = 'price_adjustment' then v_adj_n := v_adj_n + 1; continue; end if;                       -- crn-2: 가격 조정은 둘째 바퀴(반품이 먼저 낮은 층을 가져간다 · §2-2)
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;  v_fd := null;  v_fd_line := 0;                                                           -- fr-3
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
    v_take := null;  v_od_base := null;                                                                                                                                                -- crn-2
    v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;

    if v_kind = 'product' then
      v_qty := nullif(x->>'qty_returned', '')::numeric;
      if v_qty is null or v_qty <= 0 then raise exception 'A product line needs qty_returned > 0 — nothing was saved'; end if;
      if v_ref then
        v_sku := nullif(trim(x->>'sku'), '');
        if v_sku is null then raise exception 'A reference credit product line needs sku — nothing was saved'; end if;
        select * into v_pr from public.product pr where pr.sku = v_sku;
        if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
        v_unit := nullif(x->>'unit_price', '')::numeric;
        if v_unit is null or v_unit < 0 then raise exception 'A reference credit product line needs unit_price (the price on the paper invoice) — nothing was saved'; end if;
        v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_pr.name);
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then
          if exists (select 1 from public.so_line cl2 join public.so_invoice_order io2 on io2.so_id = cl2.so_id                                  -- asm-2b2(판정 245): 구성품은 인보이스 줄이 없다 — 하나만 돌려받는 길은 「other」 금액 줄
                      where io2.invoice_id = v_inv.id and cl2.combo_line_id is not null and (cl2.id = nullif(x->>'so_line_id', '')::uuid or cl2.sku = nullif(trim(x->>'sku'), ''))) then
            raise exception 'Line % is a component of a combo on invoice % — a combo is credited whole (credit the combo line); for one component use an other line (amount only, no stock) — nothing was saved', coalesce(nullif(trim(x->>'sku'), ''), x->>'so_line_id'), v_inv.invoice_number;
          end if;
          raise exception 'An IMS product line needs so_invoice_line_id (the invoice line being returned) — nothing was saved';
        end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
        if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_already := (public.so_credit_line_state(v_il.id)->>'qty_returned')::numeric;                   -- crn-2: 「이미 반품」 식은 so_credit_line_state 한 곳(§22-f ⬜ 복사 식 닫힘 · 값은 같다)
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        -- crn-2 판정 611: 반품은 조정된 몫(낮은 층)부터 — 이 줄의 층을 가져와(이 호출의 앞선 줄이 깎은 것 포함) 낮은 값부터 v_qty 만큼 뗀다
        if not (v_tiers ? v_il.id::text) then v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_line_state(v_il.id)->'tiers'); end if;
        v_take := public.so_credit_tiers_take(v_tiers->(v_il.id::text), v_qty, null);
        v_tiers := v_tiers || jsonb_build_object(v_il.id::text, v_take->'tiers');
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_take is null then
        v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_od_base := v_amount;
      else                                                                                                      -- crn-2 판정 611: 낸 단가 층은 인보이스 단가(오더 할인 거울이 따로 뺀다) · 조정 층은 새 단가 그대로(거울 기준에서 뺀다)
        select coalesce(sum(case when (pt->>'paid')::boolean then round((pt->>'qty')::numeric * coalesce(v_unit, 0), 2) else round((pt->>'qty')::numeric * (pt->>'unit_price')::numeric, 2) end), 0),
               coalesce(sum(case when (pt->>'paid')::boolean then round((pt->>'qty')::numeric * coalesce(v_unit, 0), 2) else 0 end), 0)
          into v_amount, v_od_base from jsonb_array_elements(v_take->'parts') pt;
        if exists (select 1 from jsonb_array_elements(v_take->'parts') pt where not (pt->>'paid')::boolean) then
          v_unit := round(v_amount / v_qty, 6);
          v_desc := v_desc || ' (' || (select string_agg(trim_scale((pt->>'qty')::numeric) || ' × ' || trim_scale(case when (pt->>'paid')::boolean then coalesce(v_il.unit_price, 0) else (pt->>'unit_price')::numeric end), ' + ' order by ord) from jsonb_array_elements(v_take->'parts') with ordinality t(pt, ord)) || ')';
        end if;
      end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
      v_product_amt := v_product_amt + v_amount;  v_rates := array_append(v_rates, v_rate);
      -- 돌아오나(판정 1) — not_restocked_reason 이 있으면 안 돌아옴 · 아니면 칸(지정 → ims_last_bin → 거부 · '' 불허 · ⬜4)
      v_combo := case when v_ref then null else nullif(v_il.combo_components, 'null'::jsonb) end;
      v_nr := nullif(trim(x->>'not_restocked_reason'), '');
      if v_combo is not null then                                                                                 -- asm-2b2: 콤보 줄 자체는 칸 · 사유가 없다 — 줄에 적은 칸 · 사유는 구성품 전부의 기본값(components[] 가 덮는다)
        v_def_nr := v_nr;  v_def_note := nullif(trim(x->>'not_restocked_note'), '');  v_def_bin := nullif(trim(x->>'restock_bin'), '');  v_nr := null;
        if v_def_nr is not null and v_def_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        if v_def_nr = 'other' and v_def_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        if exists (select 1 from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where not exists (select 1 from jsonb_array_elements(v_combo) cy where cy->>'sku' = nullif(trim(cx->>'sku'), ''))) then
          raise exception 'components[] of combo % names a sku that is not part of that combo on invoice % — nothing was saved', v_sku, v_inv.invoice_number;
        end if;
      elsif v_nr is not null then
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
           and cs.doc_number = case when v_ref then null else (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id)) end;   -- crn-1 판정 602: 참조 크레딧은 되짚지 않는다(예상 null · 실제 원가는 inv_layer_post_credit ② 가중평균부터)
      end if;
    elsif v_kind = 'freight' then
      if v_ref then
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
      if not v_ref then                                                                                             -- fr-3 판정 355: 그 운임 줄에 할인 줄(charge_discount · 같은 so_charge_id)이 있으면 같은 비율로 되돌린다
        select * into v_fd from public.so_invoice_line d where d.invoice_id = v_inv.id and d.kind = 'charge_discount' and d.so_charge_id = v_il.so_charge_id;
        if v_fd.id is not null then
          v_fd_inv := -v_fd.amount;                                                                                    -- 인보이스 할인(양수)
          select coalesce(-sum(cl.amount), 0) into v_fd_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_fd.id and c.status = 'issued';   -- 이미 돌려준 할인(양수)
          v_fd_line := case when v_already + v_amount = v_il.amount then v_fd_inv - v_fd_already                             -- 끝수 규칙: 정가를 다 돌려주는 마지막 줄은 남은 할인 전부(합 = 인보이스 할인 · 정확히)
                            else least(round(v_amount * v_fd_inv / v_il.amount, 2), v_fd_inv - v_fd_already) end;                 -- 그 밖은 round(x × 비율, 2) · 남은 할인을 넘지 않는다
          if (v_already - v_fd_already) + (v_amount - v_fd_line) > v_il.amount - v_fd_inv or v_fd_line > v_amount then         -- 순액 한도: 돌려준 순액 합 ≤ 손님이 낸 순액 · 남은 할인이 이번 운임보다 크면(앞 크레딧이 할인 없이 정가를 가져간 옛 모양) 음수 순액이 되므로 거부(정가 한도 검사는 위에 그대로)
            raise exception 'Invoice % charge % : the customer paid % net (% less % discount) — % net already credited and % asked now — only % left — nothing was saved',
              v_inv.invoice_number, v_il.line_no, v_il.amount - v_fd_inv, v_il.amount, v_fd_inv, v_already - v_fd_already, v_amount - v_fd_line, (v_il.amount - v_fd_inv) - (v_already - v_fd_already);
          end if;
        end if;
      end if;
    elsif v_kind = 'tax' then
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null or v_amount < 0 then raise exception 'A tax line needs amount ≥ 0 (the tax being returned) — nothing was saved'; end if;
      v_rate := null;  v_tax := 0;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Tax');
      if v_acct.id is null then
        select * into v_acct from public.ref_account a where a.id = (case when v_ref then v_rule.account_id else (select r.account_id from public.ref_tax_rule r where r.id = v_first_io.tax_rule_id) end);
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_ref then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);  v_parent_ln := v_ln;
    if v_kind = 'product' then v_odb := v_odb || jsonb_build_object(v_ln::text, v_od_base); v_ret_n := v_ret_n + 1; end if;                                      -- crn-2: 거울 기준(조정된 몫 제외)
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', v_kind, 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku, 'description', v_desc,
                                             'qty_returned', v_qty, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                             'unit_price', v_unit, 'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code,
                                             'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_qty * coalesce(v_pr.pack_factor, 1), 6) end,
                                             'combo_components', case when v_kind = 'product' then v_combo end);                                           -- asm-2b2: 콤보 크레딧 줄에 includes(인보이스 줄 사본)
    if v_kind = 'freight' and not v_ref and v_fd.id is not null and v_fd_line > 0 then                                   -- fr-3 판정 355 · 352 · 354 · 358: 운임 줄 바로 뒤 할인 되돌림 줄 · 음수 · 세금 따로(줄마다) · 계정 = 인보이스 할인 줄 것
      v_fd_tax := public.so_tax_amount(-v_fd_line, v_io.rate_pct);
      v_ln := v_ln + 1;  v_fd_amt := v_fd_amt - v_fd_line;  v_tax_amt := v_tax_amt + coalesce(v_fd_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'freight_discount', 'so_invoice_line_id', v_fd.id, 'description', v_fd.description,
                                               'amount', -v_fd_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_fd_tax, 0), 'account_id', v_fd.account_id, 'account_code', v_fd.account_code);
    end if;
    if v_kind = 'product' and not v_ref then                                                                  -- surcharge-2b(묶음 7): 그 상품의 인보이스 surcharge 줄이 있으면 크레딧 surcharge 줄을 자동으로 · 개당은 인보이스 줄의 것(문서는 문서에서) · 세금은 그 줄 세율로 따로 · 계정 복사 · 물건값(v_lines_amt) · 리스탁킹 피 바탕(v_product_amt) 밖
      select * into v_sc from public.so_invoice_line il where il.invoice_id = v_inv.id and il.kind = 'surcharge' and il.so_line_id = v_il.so_line_id;
      if v_sc.id is not null then
        v_sc_line := public.so_line_surcharge_total(v_sc.unit_price, v_qty);
        select coalesce(sum(cl.amount), 0) into v_sc_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_sc.id and c.status = 'issued';
        if v_sc_already + v_sc_line > v_sc.amount then raise exception 'Invoice % surcharge of line % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_sc_already, v_sc.amount, v_sc.amount - v_sc_already; end if;
        v_sc_tax := public.so_tax_amount(v_sc_line, v_io.rate_pct);
        v_ln := v_ln + 1;  v_sc_amt := v_sc_amt + v_sc_line;  v_tax_amt := v_tax_amt + coalesce(v_sc_tax, 0);
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'surcharge', 'so_invoice_line_id', v_sc.id, 'so_line_id', v_sc.so_line_id, 'product_id', v_product_id, 'sku', v_sc.sku, 'description', v_sc.description,
                                                 'qty_returned', v_qty, 'unit_price', v_sc.unit_price, 'amount', v_sc_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_sc_tax, 0), 'account_id', v_sc.account_id, 'account_code', v_sc.account_code);
      end if;
    end if;
    if v_kind = 'product' and v_combo is not null then                                                             -- asm-2b2(묶음 7 · 판정 245): 구성품 크레딧 줄 — 콤보 n 개 ⇒ 구성품마다 n × combo_qty 가 재고로(제 칸 · 또는 안 돌아온 사유) · 금액 0 · 원장(credit_in)은 이 줄들만 · 원가 갈래 ① 은 구성품 SKU 의 소비 기록으로
      for cj in select c2.v from jsonb_array_elements(v_combo) with ordinality c2(v, ord) order by c2.ord loop
        select * into v_cpr from public.product pr where pr.id = nullif(cj->>'product_id', '')::uuid;
        if v_cpr.id is null then select * into v_cpr from public.product pr where pr.sku = cj->>'sku'; end if;
        if v_cpr.id is null then raise exception 'Component % of combo % is not a product any more — nothing was saved', cj->>'sku', v_sku; end if;
        select cx into v_cov from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where nullif(trim(cx->>'sku'), '') = cj->>'sku' limit 1;
        v_cq := v_qty * (cj->>'qty_per_combo')::numeric;
        v_bin := null;  v_bin_id := null;  v_bin_name := null;  v_est := null;  v_nr_note := null;
        v_nr := coalesce(nullif(trim(v_cov->>'not_restocked_reason'), ''), v_def_nr);
        if v_nr is not null then
          if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
          v_nr_note := coalesce(nullif(trim(v_cov->>'not_restocked_note'), ''), v_def_note);
          if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        else
          v_bin_name := coalesce(nullif(trim(v_cov->>'restock_bin'), ''), v_def_bin);
          if v_bin_name is null then
            v_bin_name := public.ims_last_bin(array[coalesce(v_cpr.parent_product_id, v_cpr.id)], v_w.id) -> coalesce(v_cpr.parent_product_id, v_cpr.id)::text ->> 'bin';
            if v_bin_name is null then raise exception 'No bin known for % (component of combo %) in % — pick a restock bin for it in components[] (or mark it not restocked) — nothing was saved', v_cpr.sku, v_sku, v_w.name; end if;
          end if;
          select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
          if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
          if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
          v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
          select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0) into v_est
            from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
           where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_cpr.parent_product_id), v_cpr.sku)
             and cs.doc_number = (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id));
        end if;
        v_ln := v_ln + 1;
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'product', 'so_invoice_line_id', null, 'so_line_id', nullif(cj->>'so_line_id', '')::uuid, 'product_id', v_cpr.id, 'sku', v_cpr.sku, 'description', coalesce(cj->>'description', v_cpr.name),
                                                 'qty_returned', v_cq, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                                 'unit_price', 0, 'amount', 0, 'rate_pct', v_rate, 'tax_amount', 0, 'account_id', v_acct.id, 'account_code', v_acct.code,
                                                 'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_cq * coalesce(v_cpr.pack_factor, 1), 6) end,
                                                 'combo_parent_line_no', v_parent_ln, 'combo_qty', (cj->>'qty_per_combo')::numeric, 'combo_sku', v_sku);
      end loop;
    end if;
  end loop;

  -- ═══ crn-2 판정 603 · 611 · 613 · 614: 가격 조정 줄(둘째 바퀴) — 인보이스 줄: 층(낸 단가 = 오더 할인 뒤 · 앞선 조정이 있으면 그 단가)에서 새 단가보다 비싼 가장 낮은 층 하나 · 수량은 그 층 안에서만(넘치면 나눠 보내라) ·
  --     참조 크레딧: 낸 단가 · 새 단가 · 수량을 손으로 · 금액 = (낸 − 새) × 수량 · 세율 = 그 줄(또는 규칙) · 계정 = 그 인보이스 줄(614 · 참조는 _98_) · 재고 0 · 거울 · surcharge · 운임 할인 · 피 기준에 안 들어간다 ═══
  for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'price_adjustment' loop
    v_il := null;  v_io := null;  v_pr := null;  v_acct := null;  v_tier := null;  v_il_id := null;  v_so_line_id := null;  v_product_id := null;  v_sku := null;  v_desc := null;
    v_qty := nullif(x->>'qty', '')::numeric;  v_after := nullif(x->>'new_unit_price', '')::numeric;  v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_qty is null or v_qty <= 0 then raise exception 'A price adjustment line needs qty > 0 — nothing was saved'; end if;
    if v_after is null or v_after <= 0 then raise exception 'A price adjustment line needs new_unit_price above 0 — to write the goods off entirely use a product line marked not returned, or an other line — nothing was saved'; end if;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;
    if v_ref then
      v_sku := nullif(trim(x->>'sku'), '');
      if v_sku is null then raise exception 'A reference credit price adjustment line needs sku — nothing was saved'; end if;
      select * into v_pr from public.product pr where pr.sku = v_sku;
      if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
      v_before := nullif(x->>'paid_unit_price', '')::numeric;
      if v_before is null or v_before < 0 then raise exception 'A reference credit price adjustment line needs paid_unit_price (the price on the paper invoice) — nothing was saved'; end if;
      if v_after >= v_before then raise exception 'New unit price % is not below the paid unit price % — nothing was saved', trim_scale(v_after), trim_scale(v_before); end if;
      v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := v_pr.name;
      if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
    else
      v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
      if v_il_id is null then raise exception 'A price adjustment line needs so_invoice_line_id (the invoice line being adjusted) — nothing was saved'; end if;
      select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
      if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
      if v_il.combo_components is not null then raise exception 'Invoice % line % (%) is a combo — a price adjustment on a combo is not supported; use an other line — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku; end if;
      select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
      if not (v_tiers ? v_il.id::text) then v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_line_state(v_il.id)->'tiers'); end if;
      if not exists (select 1 from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0) then
        raise exception 'Invoice % line % (%): nothing left to adjust — all % were returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale(v_il.qty);
      end if;
      select t into v_tier from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0 and (t->>'unit_price')::numeric > v_after order by (t->>'unit_price')::numeric limit 1;
      if v_tier is null then
        raise exception 'Invoice % line % (%): new unit price % is not below the current unit price % — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale(v_after),
          trim_scale((select min((t->>'unit_price')::numeric) from jsonb_array_elements(v_tiers->(v_il.id::text)) t where (t->>'qty')::numeric > 0));
      end if;
      v_before := (v_tier->>'unit_price')::numeric;
      if v_qty > (v_tier->>'qty')::numeric then
        raise exception 'Invoice % line % (%): only % can be adjusted at % — split the adjustment (% at %%s%, the rest at the next price level) — nothing was saved',
          v_inv.invoice_number, v_il.line_no, v_il.sku, trim_scale((v_tier->>'qty')::numeric), trim_scale(v_before), trim_scale((v_tier->>'qty')::numeric), trim_scale(v_before);
      end if;
      v_take := public.so_credit_tiers_take(v_tiers->(v_il.id::text), v_qty, v_after);
      v_tiers := v_tiers || jsonb_build_object(v_il.id::text, public.so_credit_tiers_add(v_take->'tiers', v_qty, v_after));
      v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := v_il.description;
      select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
      if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;   -- 판정 614: 그 판매 줄의 매출 계정
    end if;
    v_amount := round((v_before - v_after) * v_qty, 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'price_adjustment', 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku,
                                             'description', format('Price adjustment %s → %s', trim_scale(v_before), trim_scale(v_after)) || coalesce(' — ' || v_desc, ''),
                                             'qty_adjusted', v_qty, 'unit_price_before', v_before, 'unit_price_after', v_after, 'unit_price', v_before - v_after,
                                             'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
  end loop;
  if v_adj_n > 0 and v_ret_n = 0 and v_reason <> 'price_adjustment' then v_warn := array_append(v_warn, 'reason_not_price_adjustment'); end if;          -- crn-2 §2-4: 경고만
  if v_reason = 'price_adjustment' and v_ret_n > 0 then v_warn := array_append(v_warn, 'reason_price_adjustment_with_returns'); end if;

  -- crn-1 판정 602 · crn-0 §2-5: 참조 크레딧 경고 — 늘 manual_unit_price(인보이스 없이 넣은 단가 · 화면이 크게) · 같은 손님 · 같은 참조 번호(대소문자 · 앞뒤 공백 무시) · 같은 SKU 의 앞선 발행 크레딧이 있으면 reference_seen:<CR 번호들>(막지 않는다)
  if v_ref then
    v_warn := array_append(v_warn, 'manual_unit_price');
    select string_agg(distinct c2.credit_number, ', ') into v_seen
      from public.so_credit c2 join public.so_credit_line l2 on l2.credit_id = c2.id
     where c2.customer_id = v_cust and c2.status = 'issued' and lower(trim(c2.ref_invoice_number)) = lower(v_ref_inv)
       and l2.kind = 'product' and l2.sku in (select le->>'sku' from jsonb_array_elements(v_lines) le where le->>'kind' = 'product');
    if v_seen is not null then v_warn := array_append(v_warn, 'reference_seen:' || v_seen); end if;
  end if;

  -- dsc-3b 판정 325 · 316: 인보이스 거울 — 인보이스-오더마다 오더 할인 % 가 있으면 그 오더의 제품 환불액에 음수 줄 하나(세금 따로 · 계정 = 그 인보이스의 order_discount 줄) · surcharge 는 기준 밖(인보이스와 같다) · Cin7 크레딧은 해당 없음
  if not v_ref then
    for v_od in
      select io.id as io_id, io.so_number, io.order_discount_pct as pct, io.rate_pct, sum(coalesce((v_odb->>(le->>'line_no'))::numeric, (le->>'amount')::numeric)) as amt   -- crn-2 판정 611 · 613: 조정된 몫은 거울 기준에서 뺀다(그 몫은 새 단가 그대로)
      from jsonb_array_elements(v_lines) le join public.so_invoice_line il on il.id = nullif(le->>'so_invoice_line_id', '')::uuid join public.so_invoice_order io on io.id = il.invoice_order_id join public.so_line sl on sl.id = il.so_line_id   -- od-1
      where le->>'kind' = 'product' and coalesce(io.order_discount_pct, 0) > 0 and not public.so_line_manual(sl)   -- od-1 판정 542 · 544: 손으로 정한 줄은 오더 할인을 받지 않았으니 되돌릴 몫도 없다
      group by io.id, io.so_number, io.order_discount_pct, io.rate_pct order by io.so_number
    loop
      v_amount := -round(v_od.amt * v_od.pct / 100, 2);  v_tax := public.so_tax_amount(v_amount, v_od.rate_pct);
      select * into v_od_il from public.so_invoice_line il where il.invoice_order_id = v_od.io_id and il.kind = 'order_discount' limit 1;
      v_ln := v_ln + 1;  v_od_amt := v_od_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'order_discount', 'so_invoice_line_id', v_od_il.id, 'description', format('Order discount %s%% (%s)', v_od.pct, v_od.so_number),
                                               'amount', v_amount, 'rate_pct', v_od.rate_pct, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_od_il.account_id, 'account_code', v_od_il.account_code);
    end loop;
  end if;

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수 · dsc-3b 판정 325: 기준 = 제품 환불액 − 오더 할인 몫(손님이 실제 낸 값)
  v_first_rate := case when v_ref then v_rule.rate_pct else v_rates[1] end;
  if v_fee_lines > 0 then
    if v_fee_lines > 1 then raise exception 'Only one restocking_fee line per credit note — nothing was saved'; end if;
    if (select count(distinct r) from unnest(v_rates) r) > 1 then v_warn := array_append(v_warn, 'fee_rate_mixed'); end if;
    for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'restocking_fee' loop
      v_acct := null;  v_acct_id := nullif(x->>'account_id', '')::uuid;
      if v_acct_id is not null then select * into v_acct from public.ref_account a where a.id = v_acct_id;
      elsif v_fee_acct_code is not null then select * into v_acct from public.ref_account a where a.code = v_fee_acct_code; end if;
      if v_acct.id is null then raise exception 'A restocking fee line needs account_id — no default account is set (inv_config so_credit_restock_fee_account_code) — nothing was saved'; end if;
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null then v_amount := -round((v_product_amt + v_od_amt) * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;   -- dsc-3b 판정 325: v_od_amt 는 음수
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
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round((v_product_amt + v_od_amt) * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);   -- dsc-3b 판정 325
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'freight_discount_amount', v_fd_amt, 'fee_amount', v_fee_amt, 'surcharge_amount', v_sc_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, ref_invoice_number, ref_order_number, ref_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, order_discount_amount, freight_discount_amount, fee_amount, surcharge_amount, tax_amount, total, created_by, updated_by)   -- fr-3
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_ref_inv, v_ref_ord, v_ref_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_od_amt, v_fd_amt, v_fee_amt, v_sc_amt, v_tax_amt, v_lines_amt + v_od_amt + v_fd_amt + v_fee_amt + v_sc_amt + v_tax_amt, v_staff, v_staff)   -- fr-3
  returning * into v_cr;
  for e in select t from jsonb_array_elements(v_lines) t loop
    insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, description, qty_returned, restock_bin_id, restock_bin, not_restocked_reason, not_restocked_note,
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by, combo_credit_line_id, combo_qty, combo_components,
                                       qty_adjusted, unit_price_before, unit_price_after)                                                                                                -- crn-2
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff,
            (v_idmap->>(e->>'combo_parent_line_no'))::uuid, nullif(e->>'combo_qty', '')::numeric, nullif(e->'combo_components', 'null'::jsonb),                   -- asm-2b2: 구성품 줄은 앞서 넣은 콤보 줄(line_no → id)에 매단다 · 콤보 줄은 includes 를 든다
            nullif(e->>'qty_adjusted', '')::numeric, nullif(e->>'unit_price_before', '')::numeric, nullif(e->>'unit_price_after', '')::numeric)                                              -- crn-2
    returning id into v_il_id;
    v_idmap := v_idmap || jsonb_build_object((e->>'line_no'), v_il_id);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'freight_discount_amount', v_cr.freight_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ so_credit_prepare 재발행 — 원본 20261007181109_fr_3_freight_discount_credit.sql:426 바이트 + 더한 · 바꾼 줄만 · crn-2 ═══
CREATE OR REPLACE FUNCTION public.so_credit_prepare(p_invoice_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with inv as (
    select i.*, cu.name as customer_name, public.ims_today() as today,
           (select s.location_id from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = i.id order by o.so_number limit 1) as wh_id   -- 발행 창구 :996 과 같은 줄(원판매 첫 오더의 창고)
    from public.so_invoice i left join public.customer cu on cu.id = i.bill_to_customer_id
    where i.id = p_invoice_id
  ),
  cfg as (
    select (select nullif(k.value, '')::int     from public.inv_config k where k.key = 'so_credit_restock_fee_days')         as fee_days,
           (select nullif(k.value, '')::numeric from public.inv_config k where k.key = 'so_credit_restock_fee_pct')          as fee_pct,
           (select nullif(k.value, '')          from public.inv_config k where k.key = 'so_credit_restock_fee_account_code') as fee_account_code
  )
  select jsonb_build_object(
    'invoice', jsonb_build_object('id', inv.id, 'invoice_number', inv.invoice_number, 'status', inv.status, 'creditable', (inv.status = 'issued'), 'issued_on', inv.issued_on,
                                  'days_since_invoice', inv.today - inv.issued_on, 'customer_id', inv.bill_to_customer_id, 'customer_name', inv.customer_name, 'bill_to_name', inv.bill_to_name,
                                  'currency_id', inv.currency_id, 'currency_code', inv.currency_code, 'total', inv.total, 'remaining', public.so_invoice_remaining(inv.id)),
    'warehouse', (select jsonb_build_object('warehouse_id', w.id, 'warehouse_name', w.name, 'is_active', w.is_active) from public.ref_warehouse w where w.id = inv.wh_id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'so_invoice_line_id', l.id, 'line_no', l.line_no, 'kind', l.kind, 'sku', l.sku, 'description', l.description, 'unit', l.unit, 'pack_factor', l.pack_factor,
                'qty_sold', l.qty,
                -- ⚠️ 복사 식(0-5): so_credit_issue 20260925012354:1055~1056 의 「이미 반품」과 글자까지 같아야 창구가 거부하지 않는다 · ⬜ so_credit_line_returned(so_invoice_line_id) 류 함수로 떼고 발행 창구와 함께 부른다(다음 차수)
                'qty_credited', case when l.kind = 'product' then (public.so_credit_line_state(l.id)->>'qty_returned')::numeric end,                                                            -- crn-2: 식은 so_credit_line_state 한 곳(§22-f ⬜ 닫힘)
                'qty_returnable', case when l.kind = 'product' then (public.so_credit_line_state(l.id)->>'qty_returnable')::numeric end,
                -- crn-2 판정 603 · 611 · 613: 가격 조정 재료 — 낸 단가(오더 할인 뒤) · 층(tiers) · 조정할 수 있는 수량(낸 단가 층) · 열린 조정 몫 · 앞선 조정 목록(콤보 줄은 null)
                'adjust', case when l.kind = 'product' and l.combo_components is null then public.so_credit_line_state(l.id) - 'so_invoice_line_id' - 'tiers_raw' end,
                'amount', l.amount,
                -- charge 줄의 「이미 반품」은 금액(발행 창구 :1099~1103 의 v_already 와 같은 뜻)
                'amount_credited', case when l.kind in ('charge', 'surcharge') then (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,   -- surcharge-2b: surcharge 줄은 보이기만(자동 · 손으로 못 보낸다)
                'discount_line_id', fd.fd_id, 'discount_amount', fd.fd_amount, 'net_amount', case when l.kind = 'charge' then l.amount - coalesce(fd.fd_amount, 0) end,                     -- fr-3 판정 355: 운임 줄의 할인(인보이스 charge_discount 줄 · 양수) · 순액
                'discount_credited', fd.fd_credited, 'net_credited', case when l.kind = 'charge' then fd.gross_credited - coalesce(fd.fd_credited, 0) end,                   -- 이미 돌려준 할인(양수) · 이미 돌려준 순액
                'net_remaining', case when l.kind = 'charge' then (l.amount - coalesce(fd.fd_amount, 0)) - (fd.gross_credited - coalesce(fd.fd_credited, 0)) end,              -- 남은 순액 한도(so_credit_issue 의 순액 검사와 같은 식)
                'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'rate_pct', io.rate_pct, 'tax_rule', io.tax_rule, 'tax_amount', l.tax_amount, 'account_code', l.account_code,
                'product_id', sl.product_id, 'stock_product_id', coalesce(pr.parent_product_id, pr.id), 'stock_sku', coalesce(pp.sku, pr.sku),
                -- 되돌려 놓을 칸 기본값 — 발행 창구 :1077 과 같은 길(ims_last_bin(낱개 제품, 창고) · ④a1 뒤로 보관용 아님 먼저 · 없으면 null → 사람이 고르거나 안 돌아옴으로)
                'restock_bin_default', case when l.kind = 'product' and l.combo_components is null and inv.wh_id is not null and pr.id is not null
                                            then public.ims_last_bin(array[coalesce(pr.parent_product_id, pr.id)], inv.wh_id) -> coalesce(pr.parent_product_id, pr.id)::text end,
                -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄 = 반품 단위(qty 는 콤보 수) · 구성품마다 돌아가는 칸 기본(ims_last_bin · 낱개 제품 · 그 창고) — 보통 줄은 null
                'combo_components', (select jsonb_agg(cj || jsonb_build_object('restock_bin_default', case when inv.wh_id is not null and cpr.id is not null then public.ims_last_bin(array[coalesce(cpr.parent_product_id, cpr.id)], inv.wh_id) -> coalesce(cpr.parent_product_id, cpr.id)::text end) order by cj->>'sku')
                                       from jsonb_array_elements(l.combo_components) cj left join public.product cpr on cpr.id = nullif(cj->>'product_id', '')::uuid))
              order by l.line_no), '[]'::jsonb)
              from public.so_invoice_line l
              join public.so_invoice_order io on io.id = l.invoice_order_id
              left join public.so_line sl on sl.id = l.so_line_id
              left join public.product pr on pr.id = sl.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              left join lateral (select d.id as fd_id, -d.amount as fd_amount,                                                                                       -- fr-3: 운임 줄의 할인 줄(없으면 null)
                                        (select coalesce(-sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = d.id and c.status = 'issued') as fd_credited,
                                        (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') as gross_credited
                                   from public.so_invoice_line d where l.kind = 'charge' and d.invoice_id = l.invoice_id and d.kind = 'charge_discount' and d.so_charge_id = l.so_charge_id) fd on true
              where l.invoice_id = inv.id and l.kind in ('product', 'charge', 'surcharge')),
    'restock_fee', jsonb_build_object('days', cfg.fee_days, 'pct', cfg.fee_pct, 'account_code', cfg.fee_account_code,
                                      'days_since_invoice', inv.today - inv.issued_on,
                                      'applies', (cfg.fee_days is not null and inv.today - inv.issued_on > cfg.fee_days),
                                      'note', 'notice only — the preview so_credit_issue(p, false) proposes the amount (fee_suggested); the account must be picked when account_code is null'),
    'already_credited', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason, 'total', c.total, 'remaining', public.so_credit_remaining(c.id)) order by c.credit_number), '[]'::jsonb)
                         from public.so_credit c where c.invoice_id = inv.id),
    'vocab', jsonb_build_object('reasons', '["customer_return","damaged","billing_error","other","price_adjustment"]'::jsonb,                                                      -- crn-2 판정 612
                                'not_restocked_reasons', '["damaged","b_grade","not_returned","other"]'::jsonb,
                                'line_kinds', '["product","freight","tax","other","restocking_fee","price_adjustment"]'::jsonb)                                                   -- crn-2 판정 603
  )
  from inv, cfg;
$function$;

-- ═══ doc_data_credit 재발행 — 원본 20261021194405_crn_1_reference_credit.sql:597 바이트 + 더한 · 바꾼 줄만 · crn-2 ═══
CREATE OR REPLACE FUNCTION public.doc_data_credit(p_credit_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cr   public.so_credit%rowtype;
  v_inv  public.so_invoice%rowtype;
  v_fmt  text := p_cfg->>'date_format';
  v_bill jsonb;  v_ship jsonb;  v_lines jsonb;  v_charges jsonb;  v_refunds jsonb;
  v_lines_amt numeric;  v_lines_tax numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_applied numeric;  v_ref text;
begin
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if v_cr.id is null then raise exception 'Credit note not found'; end if;
  if v_cr.invoice_id is not null then
    select * into v_inv from public.so_invoice i where i.id = v_cr.invoice_id;
    v_bill := jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country);
    select jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country)
      into v_ship
    from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;                                                   -- 여러 오더면 첫 오더(so_number 순)의 배송지
    select string_agg(s.ref, ', ' order by o.so_number) into v_ref from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id and s.ref is not null and s.ref <> '';
  else
    select jsonb_build_object('name', c.name, 'line1', a.line1, 'line2', a.line2, 'city', a.city, 'state_province', a.state_province, 'postal_code', a.postal_code, 'country', a.country) into v_bill
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Billing' and a.is_default_for_type where c.id = v_cr.customer_id;
    select jsonb_build_object('company', c.name, 'contact', '', 'phone', '', 'line1', a.line1, 'line2', a.line2, 'city', a.city, 'state_province', a.state_province, 'postal_code', a.postal_code, 'country', a.country) into v_ship
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Shipping' and a.is_default_for_type where c.id = v_cr.customer_id;
  end if;
  -- 제품 줄(콤보 구성품 줄은 뺀다 — 손님 문서 · amount 0) · 그 밖(freight · tax · other · surcharge · order_discount · freight_discount)은 charges · restocking_fee 는 totals
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(x.product_id), 'sku', coalesce(x.sku, ''), 'description', coalesce(x.description, ''), 'comment', '', 'unit', coalesce(x.unit, ''),
                                               'qty', public.doc_fmt_qty(coalesce(x.qty_returned, x.qty_adjusted)), 'list_price', '', 'discount_pct', '', 'unit_price', public.doc_fmt_money(x.unit_price), 'net_unit_price', '',   -- crn-2: 가격 조정 줄은 조정 수량 · 개당 차액
                                               'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount), 'is_free', false, 'no_price', false) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0)
    into v_lines, v_lines_amt, v_lines_tax
  from (select l.*, coalesce(sl.unit, p.uom_name) as unit, row_number() over (order by l.line_no) as no
        from public.so_credit_line l left join public.so_line sl on sl.id = l.so_line_id left join public.product p on p.id = l.product_id
        where l.credit_id = v_cr.id and l.kind in ('product', 'price_adjustment') and l.combo_credit_line_id is null) x;                                          -- crn-2 판정 603: 가격 조정 줄은 제품 표에(설명 「Price adjustment 9.49 → 7.99 — …」)
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'so_number', '', 'code', coalesce(x.account_code, ''), 'description', coalesce(x.description, ''), 'comment', '', 'qty', public.doc_fmt_qty(x.qty_returned),
                                               'unit_price', public.doc_fmt_money(x.unit_price), 'discount_pct', '', 'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount)) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0)
    into v_charges, v_chg_amt, v_chg_tax
  from (select l.*, row_number() over (order by l.line_no) as no from public.so_credit_line l where l.credit_id = v_cr.id and l.kind not in ('product', 'restocking_fee', 'price_adjustment')) x;   -- crn-2
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.reference, ''), 'date', public.doc_fmt_date(x.paid_on, v_fmt), 'method', public.doc_method_label(x.method), 'amount', public.doc_fmt_money(x.amount)) order by x.no), '[]'::jsonb)
    into v_refunds
  from (select a.amount, p.reference, p.paid_on, p.method, row_number() over (order by p.paid_on, p.created_at, a.created_at) as no
        from public.so_credit_alloc a join public.so_payment p on p.id = a.refund_payment_id
        where a.credit_id = v_cr.id and a.refund_payment_id is not null and a.voided_at is null and p.status = 'active') x;
  select coalesce(sum(a.amount), 0) into v_applied from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id is not null and a.voided_at is null;
  return jsonb_build_object(
    'credit', jsonb_build_object('number', v_cr.credit_number, 'date', public.doc_fmt_date(v_cr.issued_on, v_fmt), 'invoice_number', coalesce(v_inv.invoice_number, v_cr.ref_invoice_number, ''),   -- crn-1 판정 609: 참조 번호(옛 이름은 판정 609 앞의 것)
                                 'reference', coalesce(v_ref, ''), 'reason', coalesce(v_cr.reason, ''), 'currency', coalesce(v_cr.currency_code, ''), 'memo', coalesce(v_cr.note, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_ship->>'company', ''), 'contact', coalesce(v_ship->>'contact', ''), 'phone', coalesce(v_ship->>'phone', ''), 'line1', coalesce(v_ship->>'line1', ''), 'line2', coalesce(v_ship->>'line2', ''),
                                  'city', coalesce(v_ship->>'city', ''), 'state_province', coalesce(v_ship->>'state_province', ''), 'postal_code', coalesce(v_ship->>'postal_code', ''), 'country', coalesce(v_ship->>'country', '')),
    'lines', v_lines, 'charges', v_charges, 'refunds', v_refunds,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'restocking_fee', public.doc_fmt_money(v_cr.fee_amount), 'before_tax', public.doc_fmt_money(v_cr.total - v_cr.tax_amount), 'tax', public.doc_fmt_money(v_cr.tax_amount), 'total', public.doc_fmt_money(v_cr.total),
                                 'applied', public.doc_fmt_money(v_applied), 'remaining', public.doc_fmt_money(public.so_credit_remaining(v_cr.id))))
    || public.doc_data_common('credit_note', p_cfg, coalesce(v_bill, '{}'::jsonb) || public.doc_contact(v_cr.customer_id));
end;
$function$;

-- ═══ so_credit_cancel 재발행 — 원본 20260930144905_cogs_2_cost_split.sql:1763 바이트 + 더한 · 바꾼 줄만 · crn-2 ═══
CREATE OR REPLACE FUNCTION public.so_credit_cancel(p_credit_id uuid, p_note text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_val     numeric;  v_unit numeric;                              -- cogs-2(판정 106): 되돌리는 소진 = 그 레이어의 남은 가치 전부(inv_layer_value · 얹힌 몫 포함)
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
  -- crn-2 판정 611: 가격 조정 줄이 든 크레딧은 그 뒤 같은 인보이스 줄에 발행된 크레딧(반품 · 조정)이 있으면 취소 거부 — 뒤 것이 이 조정의 층(새 단가)으로 값이 매겨졌다 · 뒤 것부터 취소
  select string_agg(distinct c2.credit_number, ', ') into v_sold
    from public.so_credit_line l1 join public.so_credit_line l2 on l2.so_invoice_line_id = l1.so_invoice_line_id and l2.credit_id <> l1.credit_id and l2.kind in ('product', 'price_adjustment')
    join public.so_credit c2 on c2.id = l2.credit_id
   where l1.credit_id = v_cr.id and l1.kind = 'price_adjustment' and c2.status = 'issued' and (c2.issued_on, c2.created_at, c2.credit_number) > (v_cr.issued_on, v_cr.created_at, v_cr.credit_number);   -- 같은 순서(so_credit_line_state) · 번호는 한 트랜잭션 안의 동률을 가른다
  if v_sold is not null then raise exception 'Credit note % has price adjustments that later credit notes (%) were priced on — cancel those first — nothing was saved', v_cr.credit_number, v_sold; end if;
  v_sold := null;

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
    select v.remaining_value, coalesce(v.unit_cost, 0) into v_val, v_unit from public.inv_layer_value(y.id) v;   -- cogs-2(판정 106): 소진 0 인 레이어라 남은 가치 = 처음 원가 + 얹힌 것 전부
    insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason)
    values (y.id, 'creditnote', v_cr.credit_number, y.line_ref || ':reversal', 'credit_in', v_today, y.qty, v_unit, v_val, 'reversal');
    v_layers := v_layers + 1;
  end loop;

  update public.so_credit set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_note = v_note, updated_by = v_staff where id = v_cr.id and status = 'issued';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Credit note % was not cancelled — it may have been changed by someone else just now — nothing was saved', v_cr.credit_number; end if;
  return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', 'cancelled', 'note', v_note, 'cancelled_by', v_staff,
                            'ledger_rows_reversed', v_rows, 'qty_ea_reversed', v_qty, 'layers_reversed', v_layers);
end;
$function$;

-- ═══ 착지 — 칸 셋 · CHECK 셋 · 도우미 셋 ACL · 재발행 넷 md5 · 옛 행 무변 · 다른 창구 무변 ═══
do $$
declare
  v_bad text := '';
  v_n   int;
  b     record;
  v_exp jsonb := '{"so_credit_issue": "4175a0e0c3e8abd7b4bf0f7cff106803", "so_credit_prepare": "3fcd62ab735eeb311ba2d9e67a5acbff", "doc_data_credit": "494b84313f58d7b29b39aafbe986e894", "so_credit_cancel": "253fe38e15880598a96eba9796ff1397"}'::jsonb;
  k     text;
begin
  select * into b from crn2_before;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'so_credit_line' and column_name in ('qty_adjusted', 'unit_price_before', 'unit_price_after');
  if v_n <> 3 then v_bad := v_bad || format(' cols_%s_of_3', v_n); end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_credit_line'::regclass and conname = 'so_credit_line_kind_ck') !~ 'price_adjustment' then v_bad := v_bad || ' kind_ck'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_credit_line'::regclass and conname = 'so_credit_line_adjust_ck') !~ 'round' then v_bad := v_bad || ' adjust_ck'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so_credit'::regclass and conname = 'so_credit_reason_ck') !~ 'price_adjustment' then v_bad := v_bad || ' reason_ck'; end if;
  if (select string_agg(conname || ':' || pg_get_constraintdef(oid), ' ' order by conname) from pg_constraint where conrelid = 'public.so_credit_line'::regclass and contype = 'c' and conname not in ('so_credit_line_kind_ck', 'so_credit_line_adjust_ck')) is distinct from b.other_line_checks then v_bad := v_bad || ' other_line_checks'; end if;
  if (select count(*) || '/' || md5(coalesce(string_agg(l.id::text || l.kind || l.amount, ',' order by l.id), '')) from public.so_credit_line l) is distinct from b.lines_md5 or exists (select 1 from public.so_credit_line where qty_adjusted is not null) then v_bad := v_bad || ' old_rows'; end if;
  for k in select jsonb_object_keys(v_exp) loop
    select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k;
    if v_n <> 1 then v_bad := v_bad || format(' %s_overloads_%s', k, v_n); end if;
    if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = k) is distinct from (v_exp->>k) then v_bad := v_bad || ' ' || k || '_body'; end if;
  end loop;
  if (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_credit_issue', 'so_credit_prepare', 'doc_data_credit', 'so_credit_cancel')) is distinct from b.acls then v_bad := v_bad || ' reissued_acls'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('inv_post_credit', 'so_credit_detail', 'so_credit_attach', 'so_credit_detach', 'so_credit_alloc_add', 'so_credit_remaining', 'so_customer_balance', 'inv_layer_post_credit', 'so_detail', 'doc_data', 'so_tax_amount', 'so_line_manual', 'so_invoice_issue')) is distinct from b.others then v_bad := v_bad || ' others_changed'; end if;
  if to_regprocedure('public.so_credit_line_state(uuid)') is null or to_regprocedure('public.so_credit_tiers_take(jsonb, numeric, numeric)') is null or to_regprocedure('public.so_credit_tiers_add(jsonb, numeric, numeric)') is null then v_bad := v_bad || ' helpers'; end if;
  if not has_function_privilege('authenticated', 'public.so_credit_line_state(uuid)', 'execute') or has_function_privilege('anon', 'public.so_credit_line_state(uuid)', 'execute')
     or has_function_privilege('authenticated', 'public.so_credit_tiers_take(jsonb, numeric, numeric)', 'execute') or has_function_privilege('anon', 'public.so_credit_tiers_take(jsonb, numeric, numeric)', 'execute')
     or has_function_privilege('authenticated', 'public.so_credit_tiers_add(jsonb, numeric, numeric)', 'execute') or has_function_privilege('anon', 'public.so_credit_tiers_add(jsonb, numeric, numeric)', 'execute') then v_bad := v_bad || ' helper_acl'; end if;
  if (select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_issue') !~ 'price_adjustment' then v_bad := v_bad || ' issue_text'; end if;
  if v_bad <> '' then raise exception 'crn-2 landing check failed:%', v_bad; end if;
end $$;
drop table crn2_before;
