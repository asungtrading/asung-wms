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

-- ═══ hcr-1 — 이력(hist_)을 보고 채우는 참조 크레딧: DB (2026-10-26 · 판정 774 · 778 · 779 · 781 · 782 · 기술 넷) ═══
--   서버는 hist_ 를 읽기만 한다(654 — 원장 · 원가 · 잔액은 잇지 않는다) · 크레딧은 참조 크레딧 그대로(602 · 609 · 610)
--   ① 색인 hist_so_line_doc_number_idx — 정규화 lower(trim(doc_number)) · invoice 줄만(기술 1 · 머리 invoice_number 로 조인하면 47143 에 47441 의 줄이 섞인다)
--   ② so_credit.store_customer_id(779 매장 · 돈은 customer_id = 청구처) · so_credit.warnings(기술 3 · 발행 때 경고를 기록에) · so_credit_ref_number_idx
--   ③ 한 곳 — hist_line_kind(줄 분류) · hist_credit_lines(778 단가 · Cin7 반품 · IMS 참조 크레딧 · 남은 수량) · hist_credit_tax(781) — 창구 hist_credit_source 와 so_credit_issue 가 같은 함수를 부른다(식이 둘이면 경고가 엇갈린다)
--   ④ 읽기 창구 hist_credit_source(p_number) → jsonb — sales 보기 · ⚠️ definer + 첫 줄 문(invoker 는 hist RLS 정책 함수가 leakproof 가 아니라 식 색인을 못 타 8 초 — 시험 실측 · so_credit_detail 꼴)
--   ⑤ so_credit_issue 재발행 — ref 갈래에 매장 · 778 단가 비교 · 초과 경고 · 781 제안 · 기록 · DB 바이트(md5 cffc1999…) 위에 더한 줄 + 바꾼 토큰 하나(ship_to 손님 → 매장)
--   ⑥ so_credit_detail(store_name 키) · doc_data_credit(참조 크레딧 배송지 블록 = 매장) 재발행 · so_credit_list 에 store_customer_id · store_name(create or replace · ACL 그대로)
--   컷오버 지우기(reload-procedure §P): so_credit 은 truncate 쪽(새 칸 · 색인은 표에 붙어 남는다 · cutover-delete.sql 은 표 이름만 대조) · hist_so_line 은 남김 쪽(새 색인도 남는다) — 손댈 줄 없음

-- ═══ ① 색인 ═══
create index hist_so_line_doc_number_idx on public.hist_so_line (lower(trim(doc_number)), hist_so_id);   -- 부분 색인(where doc_type) 이 아니다: planner 는 부분 색인의 식 통계를 안 쓴다(추정 1,378 행 → seq scan · hcr-1 실측) · credit 줄 902 개가 섞여도 번호 꼴(CR-…)이 달라 무해
analyze public.hist_so_line;   -- 식 색인의 통계(없으면 번호 하나를 0.5 % = 1,377 행으로 추정해 seq scan 을 고른다 · hcr-1 실측 57 ms → 색인 길)
comment on index public.hist_so_line_doc_number_idx is 'hcr-1 기술 1: 옛 인보이스 번호(줄의 doc_number · invoice 줄) 정규화 lower(trim()) 찾기 — hist_credit_lines · so_credit_issue(ref) 가 쓴다';

-- ═══ ② so_credit 칸 둘 · 색인 ═══
--   표 grant 는 그대로(authenticated=r 표 단위 · 칸 grant 없음 → 새 칸은 표 권한을 따른다 · cost-1 꼴이 아니다)
alter table public.so_credit add column store_customer_id uuid references public.customer (id) on delete no action;
alter table public.so_credit add column warnings jsonb not null default '[]'::jsonb;
alter table public.so_credit add constraint so_credit_warnings_ck check (jsonb_typeof(warnings) = 'array');
create index so_credit_store_idx on public.so_credit (store_customer_id);
create index so_credit_ref_number_idx on public.so_credit (lower(trim(ref_invoice_number))) where ref_invoice_number is not null;
comment on column public.so_credit.store_customer_id is 'hcr-1 판정 779: 매장(종이 · 목록의 이름) — customer_id 는 돈을 돌려받을 청구처(= 매장의 coalesce(default_bill_to_customer_id, id)) · 참조 크레딧은 보낸 store_customer_id(없으면 customer_id) · 인보이스 크레딧은 첫 오더의 손님 · so_credit_issue 가 채운다';
comment on column public.so_credit.warnings is 'hcr-1 기술 3: 발행 때 so_credit_issue 가 낸 경고(원장 경고까지) — 참조 크레딧의 manual_unit_price · qty_over_sold:<sku>:<asked>/<remaining> · not_on_invoice:<sku> · tax_rule_differs:<지금 규칙> · reference_not_in_history · reference_seen:… 와 인보이스 크레딧의 final_sale · inactive_bin … · 막지 않는 것만(거부는 기록이 없다)';

-- ═══ ③ 한 곳 — 줄 분류 · 778 단가 · 남은 수량 · 781 세금 ═══
create function public.hist_line_kind(p_sku text) returns text
  language sql immutable set search_path = public, pg_temp as $$
  select case
    when p_sku is null then 'product'
    when p_sku = '_4_' or lower(p_sku) = 'shipping' or lower(p_sku) like 'shipping - %' then 'freight'          -- 판정 782: 운임 줄(_4_ · Shipping - Standard · Shipping - Free Shipping …) — 보이되 기본 해제
    when p_sku in ('Discount', 'Order total discount') then 'discount'                                           -- 판정 778: 오더 전체 할인 — 제품 줄 단가에 나눠 넣는다(안 보인다)
    when lower(p_sku) like 'customer credit%' or upper(p_sku) like 'CREDIT-%' then 'hidden'                       -- 판정 782: Customer Credit Write-off · CREDIT-01 — 안 보인다
    else 'product' end $$;                                                                                         -- 제품(product_id 가 비어도 — FINAL-SALE · AMZ00201 같은 「못 푼 제품 줄」 은 표시로)
comment on function public.hist_line_kind(text) is 'hcr-1 한 곳: hist_so_line.sku 원문 → product | freight | discount | hidden (판정 778 · 782) — hist_credit_lines 만 부른다 · 실측(테스트 DB 2026-10-26): _4_ 9,201 · Shipping - Standard 2,588 · Shipping - Aonebeauty TOR 300 · Shipping - Free Shipping 15 · Discount 24 · Order total discount 14 · Customer Credit Write-off 9';

create function public.hist_credit_lines(p_number text)
returns table (hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text,
               quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric,
               qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric)
  language sql stable security definer set search_path = public, pg_temp as $$
  -- ⚠️ definer: 직원 역할(RLS · 정책 함수 ims_can_view 가 leakproof 가 아니라 식 색인을 못 타고 seq scan 276k 행 × 정책 호출 = 8 초 · hcr-1 실측) — 실행권은 postgres 만 · 문은 부르는 창구(hist_credit_source · hist_credit_tax 의 ims_can_view · so_credit_issue 의 ims_require_write)
  -- ⚠️ 번호 비교는 p_number 식으로 직접(CTE 로 감싸면 planner 가 값을 못 보고 0.5 % 추정(1,377 행) → hist_so_line seq scan · 50 ms · hcr-1 실측) — 식 색인 통계로 ≈ 20 행 추정
  with ords as (select distinct hl.hist_so_id from public.hist_so_line hl where hl.doc_type = 'invoice' and lower(trim(hl.doc_number)) = lower(trim(p_number))),
  -- 오더의 줄 전부를 (hist_so_id, seq) 색인으로 한 번만 읽는다 — doc_type 으로 거르는 seq scan 은 RLS 정책 함수(ims_can_view)를 276k 행마다 불러 직원 역할에서 8 초(hcr-1 시험 실측)
  all_ln as (select hl.* from ords o cross join lateral (select h2.* from public.hist_so_line h2 where h2.hist_so_id = o.hist_so_id offset 0) hl),   -- offset 0 = 서브쿼리를 못 펴게 → 중첩 루프 + (hist_so_id, seq) 색인(추정이 틀려도 seq scan 으로 안 간다 · hcr-1 실측)
  ln as (select a.*, public.hist_line_kind(a.sku) as kind from all_ln a where a.doc_type = 'invoice'),
  -- 판정 778: 오더 단위 — P = Σ제품 줄 sale · D = Σ할인 줄 sale(≤ 0) · 제품 줄마다 sale × (P + D) / P 를 센트로 · 끝수는 가장 큰 제품 줄에(Σ = P + D 를 센트까지)
  agg as (select l.hist_so_id, coalesce(sum(l.sale) filter (where l.kind = 'product'), 0) as p, coalesce(sum(l.sale) filter (where l.kind = 'discount'), 0) as d from ln l group by l.hist_so_id),
  adj as (select l.*, a.p, a.d,
                 case when l.kind = 'product' and a.p <> 0 and a.d <> 0 then round(l.sale * (a.p + a.d) / a.p, 2) else l.sale end as sale_adj0,
                 row_number() over (partition by l.hist_so_id order by (l.kind = 'product') desc, l.sale desc, l.seq) as rn
          from ln l join agg a on a.hist_so_id = l.hist_so_id),
  fix as (select x.hist_so_id, case when x.p <> 0 and x.d <> 0 then (x.p + x.d) - sum(x.sale_adj0) filter (where x.kind = 'product') else 0 end as rem from adj x group by x.hist_so_id, x.p, x.d),
  adj2 as (select x.*, case when x.kind = 'product' and x.rn = 1 then x.sale_adj0 + coalesce(f.rem, 0) else x.sale_adj0 end as sale_adj from adj x join fix f on f.hist_so_id = x.hist_so_id),
  -- Cin7 반품(doc_type credit · 수량 음수) — 오더 안 제품(product_id · 못 풀면 upper(sku))마다
  cin7 as (select a.hist_so_id, coalesce(a.product_id::text, upper(a.sku)) as key, -sum(a.quantity) as q
           from all_ln a where a.doc_type = 'credit' group by 1, 2),
  -- IMS 참조 크레딧(기술 2) — 손님과 상관없이 같은 정규화 번호 + 제품 · 취소된 것은 빼고 · 반품 줄(qty_returned)만(가격 조정 줄은 수량을 안 깎는다 · 603)
  ims as (select coalesce(cl.product_id::text, upper(cl.sku)) as key, sum(cl.qty_returned) as q
          from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id
          where c.status = 'issued' and c.ref_invoice_number is not null and lower(trim(c.ref_invoice_number)) = lower(trim(p_number)) and cl.kind = 'product' and cl.qty_returned is not null group by 1)
  select x.hist_so_id, h.order_number, x.doc_number, x.seq, x.kind, x.sku, x.product_id, pr.sku, coalesce(pr.name, x.product_name),
         x.quantity, x.unit_price,
         case when x.quantity <> 0 then round(x.sale_adj / x.quantity, 6) else x.unit_price end,
         x.sale, x.sale_adj, x.tax,
         case when x.kind = 'product' then coalesce(c7.q, 0) end,
         case when x.kind = 'product' then coalesce(im.q, 0) end,
         case when x.kind = 'product' then x.quantity - coalesce(c7.q, 0) - coalesce(im.q, 0) end
  from adj2 x
  join public.hist_so h on h.id = x.hist_so_id
  left join public.product pr on pr.id = x.product_id
  left join cin7 c7 on c7.hist_so_id = x.hist_so_id and c7.key = coalesce(x.product_id::text, upper(x.sku))
  left join ims im on im.key = coalesce(x.product_id::text, upper(x.sku))
  where lower(trim(x.doc_number)) = lower(trim(p_number))
  order by h.order_number, x.seq
$$;
comment on function public.hist_credit_lines(text) is 'hcr-1 한 곳(판정 774 · 778 · 기술 1 · 2): 옛 인보이스 번호(줄의 doc_number · lower(trim)) → 그 인보이스의 줄 — kind(hist_line_kind) · product_sku(제품의 sku · 서버는 대소문자 정확히 찾는다) · unit_price_adj(778: 오더 전체 할인을 제품 줄에 비례 배분 · 센트 · 끝수는 가장 큰 줄 · unit = round(sale_adj / qty, 6)) · qty_cin7_returned(오더의 credit 줄) · qty_ims_credited(발행된 IMS 참조 크레딧 · 손님 무관) · qty_remaining — hist_credit_source · hist_credit_tax · so_credit_issue(ref) 가 부른다 · 오더가 인보이스 둘이면 P · D 는 오더 단위 · 줄은 그 번호 것만';

create function public.hist_credit_tax(p_number text, p_store_customer_id uuid, p_on date default null) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp as $$
-- 판정 781: 옛 세율 = 활성 판매 규칙 세율 후보 중 「줄마다 round(sale × c/100, 2) 와 tax 의 차이 합」 이 가장 작은 것(동률이면 Σtax/Σsale 에 가까운 것) ·
--   허용 폭 = 줄마다 1 센트(반올림 흔적 — 12.9 · 13.1 % 는 센트 반올림에서 온다 · 실측: 최적 후보에서 263,216 제품 줄 중 263,081(99.95 %)이 1 센트 안 · 257,136 은 정확 · 넘는 135 줄 = 세율이 섞인 53 오더 → tax_fit mixed)
--   지금 규칙 = 매장 기본 배송지(Shipping · is_default_for_type) → so_tax_rule_for(…, p_on, 'sale') · 같은 세율이면 그 규칙 · 다르면 같은 세율의 활성 판매 규칙(하나 → 제안 · 여럿 · 없음 → 직원이 고른다)
declare
  v_on     date := coalesce(p_on, public.ims_today());
  v_sale   numeric;  v_tax numeric;  v_n int;
  v_best   record;
  v_sa     public.customer_address%rowtype;
  v_cur    jsonb;  v_cur_rate numeric;
  v_cands  jsonb := '[]'::jsonb;  v_sugg jsonb;  v_fit text;  v_differs boolean;  v_rates jsonb;
  v_j      jsonb;                                                   -- 세금 낼 제품 줄(sale ≠ 0) — hist_credit_lines 는 한 번만 부른다(직원 역할의 RLS 비용)
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- definer 첫 줄 문(so_credit_detail · rls-3b 꼴)
  select coalesce(jsonb_agg(jsonb_build_object('sale', l.sale, 'tax', coalesce(l.tax, 0))), '[]'::jsonb), coalesce(sum(l.sale), 0), coalesce(sum(l.tax), 0), count(*)
    into v_j, v_sale, v_tax, v_n
    from public.hist_credit_lines(p_number) l where l.kind = 'product' and l.sale <> 0;
  if v_n > 0 then
    select c.rate, sum(abs((e->>'tax')::numeric - round((e->>'sale')::numeric * c.rate / 100, 2))) as err, max(abs((e->>'tax')::numeric - round((e->>'sale')::numeric * c.rate / 100, 2))) as maxerr
      into v_best
      from (select distinct r.rate_pct as rate from public.ref_tax_rule r where r.direction = 'sale' and r.is_active) c
      cross join jsonb_array_elements(v_j) e
     group by c.rate
     order by 2, abs(c.rate - 100 * v_tax / v_sale), c.rate
     limit 1;
    v_fit := case when v_best.maxerr = 0 then 'exact' when v_best.maxerr <= 0.01 then 'rounded' else 'mixed' end;
    select coalesce(jsonb_agg(jsonb_build_object('rate_pct', z.r, 'lines', z.n) order by z.r), '[]'::jsonb) into v_rates
      from (select round(100 * (e->>'tax')::numeric / (e->>'sale')::numeric, 1) as r, count(*) as n from jsonb_array_elements(v_j) e group by 1) z;
  end if;
  if p_store_customer_id is not null then
    select * into v_sa from public.customer_address a where a.customer_id = p_store_customer_id and a.type = 'Shipping' and a.is_active and a.is_default_for_type limit 1;
    if v_sa.id is not null then
      v_cur := public.so_tax_rule_for(v_sa.country, v_sa.state_province, v_on, 'sale');
      v_cur := jsonb_build_object('rule_id', v_cur->'rule_id', 'rule', v_cur->'rule', 'rate_pct', v_cur->'rate_pct', 'source', 'ship_to', 'ship_to', coalesce(v_sa.country, '?') || ' / ' || coalesce(v_sa.state_province, '?'), 'warnings', coalesce(v_cur->'warnings', '[]'::jsonb));
      v_cur_rate := nullif(v_cur->>'rate_pct', '')::numeric;
    end if;
  end if;
  if v_best.rate is null then                                       -- 세금 낼 줄이 없다(무상 · 금액 0) — 옛 세율을 모른다 → 지금 규칙을 제안
    if v_cur_rate is not null then v_sugg := jsonb_build_object('rule_id', v_cur->'rule_id', 'rule', v_cur->'rule', 'rate_pct', v_cur->'rate_pct'); v_cands := jsonb_build_array(v_sugg); end if;
    v_differs := null;
  elsif v_cur_rate is not null and v_cur_rate = v_best.rate then     -- 같다 → 지금 규칙
    v_sugg := jsonb_build_object('rule_id', v_cur->'rule_id', 'rule', v_cur->'rule', 'rate_pct', v_cur->'rate_pct');  v_cands := jsonb_build_array(v_sugg);  v_differs := false;
  else                                                              -- 다르다(또는 지금 규칙 없음) → 옛 세율과 같은 활성 판매 규칙
    select coalesce(jsonb_agg(jsonb_build_object('rule_id', r.id, 'rule', r.name, 'rate_pct', r.rate_pct) order by r.name), '[]'::jsonb) into v_cands
      from public.ref_tax_rule r where r.direction = 'sale' and r.is_active and r.rate_pct = v_best.rate;
    if jsonb_array_length(v_cands) = 1 then v_sugg := v_cands->0; end if;
    v_differs := case when v_cur_rate is null then null else true end;
  end if;
  return jsonb_build_object(
    'old_rate_pct', v_best.rate, 'old_rate_eff', case when v_sale <> 0 then round(100 * v_tax / v_sale, 2) end, 'tax_fit', v_fit, 'taxable_lines', v_n, 'line_rates', coalesce(v_rates, '[]'::jsonb),
    'current_rule', v_cur, 'suggested', v_sugg, 'candidates', v_cands, 'differs', v_differs, 'pick_needed', (v_sugg is null), 'on', v_on);
end $$;
comment on function public.hist_credit_tax(text, uuid, date) is 'hcr-1 한 곳(판정 781): 옛 인보이스의 세율(줄마다 1 센트 허용 · 후보 = 활성 판매 규칙 세율) · 매장 지금 규칙(기본 배송지 → so_tax_rule_for) · 제안(같으면 지금 규칙 · 다르면 같은 세율의 규칙 하나) · candidates(여럿이면 직원이 고른다) · differs · tax_fit exact|rounded|mixed · line_rates — hist_credit_source · so_credit_issue(ref · tax_rule 을 안 줬을 때) 가 부른다';

-- ═══ ④ 읽기 창구 — definer + 첫 줄 문 ims_can_view('sales') ═══
create function public.hist_credit_source(p_number text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp as $$
-- 판정 774: 옛 인보이스 번호 → 머리(오더 · 매장 · 청구처 · 통화) · 제품 줄(778 단가 · 남은 수량) · 운임 줄(782 · 기본 해제) · 세금(781) — 못 찾음 · 둘 이상 · 못 푼 손님 · 못 푼 제품은 거부가 아니라 표시
declare
  v_num    text := lower(trim(coalesce(p_number, '')));
  v_orders jsonb := '[]'::jsonb;
  v_h      public.hist_so%rowtype;
  v_c      public.customer%rowtype;
  v_b      public.customer%rowtype;
  v_cur    public.ref_currency%rowtype;
  v_o      jsonb;  v_lines jsonb;  v_freight jsonb;  v_tax jsonb;  v_warn text[];
  v_ids    uuid[];  v_id uuid;
  v_cur_src text;  v_all jsonb;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;
  if v_num = '' then raise exception 'Give the number on the old invoice'; end if;
  select coalesce(jsonb_agg(to_jsonb(l) order by l.order_number, l.seq), '[]'::jsonb) into v_all from public.hist_credit_lines(p_number) l;   -- 한 번만 부른다(직원 역할의 RLS 비용 · 아래는 전부 v_all 에서)
  select coalesce(array_agg(distinct (e->>'hist_so_id')::uuid), '{}') into v_ids from jsonb_array_elements(v_all) e;
  foreach v_id in array v_ids loop
    v_warn := '{}';  v_c := null;  v_b := null;  v_cur := null;  v_cur_src := null;
    select * into v_h from public.hist_so h where h.id = v_id;
    if v_h.customer_id is not null then select * into v_c from public.customer c where c.id = v_h.customer_id; end if;
    if v_c.id is null then v_warn := array_append(v_warn, 'customer_unresolved');
    else select * into v_b from public.customer c where c.id = coalesce(v_c.default_bill_to_customer_id, v_c.id); end if;
    if nullif(trim(v_h.currency), '') is not null then select * into v_cur from public.ref_currency r where upper(r.code) = upper(trim(v_h.currency)); v_cur_src := 'history'; end if;
    if v_cur.id is null and v_c.currency_id is not null then select * into v_cur from public.ref_currency r where r.id = v_c.currency_id; v_cur_src := 'customer'; end if;
    if v_cur.id is null then v_warn := array_append(v_warn, 'currency_unknown'); end if;
    if exists (select 1 from public.hist_so_line hl where hl.hist_so_id = v_id and hl.doc_type = 'invoice' and lower(trim(hl.doc_number)) <> v_num) then
      v_warn := array_append(v_warn, 'order_has_other_invoice:' || (select string_agg(distinct hl.doc_number, ', ') from public.hist_so_line hl where hl.hist_so_id = v_id and hl.doc_type = 'invoice' and lower(trim(hl.doc_number)) <> v_num));
    end if;
    select coalesce(jsonb_agg(jsonb_build_object(
             'seq', l.seq, 'sku', l.sku, 'product_id', l.product_id, 'product_sku', l.product_sku, 'product_name', l.product_name, 'resolved', l.product_id is not null,
             'qty_sold', l.quantity, 'unit_price_hist', l.unit_price, 'unit_price', l.unit_price_adj, 'amount_hist', l.sale, 'amount', l.sale_adj, 'tax', l.tax,
             'rate_pct_line', case when l.sale <> 0 then round(100 * coalesce(l.tax, 0) / l.sale, 2) end,
             'qty_cin7_returned', l.qty_cin7_returned, 'qty_ims_credited', l.qty_ims_credited, 'qty_remaining', l.qty_remaining) order by l.seq), '[]'::jsonb)
      into v_lines from jsonb_to_recordset(v_all) as l(hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text, quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric, qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric) where l.hist_so_id = v_id and l.kind = 'product';
    select coalesce(jsonb_agg(jsonb_build_object('seq', l.seq, 'sku', l.sku, 'description', coalesce(l.product_name, l.sku), 'amount', l.sale, 'tax', l.tax, 'checked', false) order by l.seq), '[]'::jsonb)
      into v_freight from jsonb_to_recordset(v_all) as l(hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text, quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric, qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric) where l.hist_so_id = v_id and l.kind = 'freight';
    if exists (select 1 from jsonb_array_elements(v_lines) e where not (e->>'resolved')::boolean) then v_warn := array_append(v_warn, 'product_unresolved:' || (select count(*) from jsonb_array_elements(v_lines) e where not (e->>'resolved')::boolean)); end if;
    if exists (select 1 from jsonb_array_elements(v_lines) e where (e->>'qty_remaining')::numeric < 0) then v_warn := array_append(v_warn, 'over_returned'); end if;
    v_tax := public.hist_credit_tax(p_number, v_c.id, public.ims_today());
    if v_tax->>'tax_fit' = 'mixed' then v_warn := array_append(v_warn, 'tax_mixed'); end if;
    if coalesce((v_tax->>'differs')::boolean, false) then v_warn := array_append(v_warn, 'tax_rule_differs'); end if;
    if (v_tax->>'pick_needed')::boolean then v_warn := array_append(v_warn, 'tax_pick_needed'); end if;
    v_o := jsonb_build_object(
      'hist_so_id', v_h.id, 'order_number', v_h.order_number, 'invoice_number', (select min(l.doc_number) from jsonb_to_recordset(v_all) as l(hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text, quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric, qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric) where l.hist_so_id = v_id), 'head_invoice_number', v_h.invoice_number,
      'invoice_date', v_h.invoice_date, 'order_date', v_h.order_date, 'source', v_h.source, 'location', v_h.location,
      'customer', jsonb_build_object('hist_customer_name', v_h.customer_name, 'resolved', v_c.id is not null,
                                     'store_customer_id', v_c.id, 'store_name', v_c.name, 'bill_to_customer_id', v_b.id, 'bill_to_name', v_b.name, 'bill_to_is_store', (v_b.id = v_c.id),
                                     'currency_id', v_cur.id, 'currency_code', v_cur.code, 'currency_source', v_cur_src, 'default_location_id', v_c.default_location_id),
      'totals', jsonb_build_object('sale_total', v_h.sale_total, 'tax_total', v_h.tax_total, 'line_count', v_h.line_count,
                                   'product_amount', (select coalesce(sum(l.sale), 0) from jsonb_to_recordset(v_all) as l(hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text, quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric, qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric) where l.hist_so_id = v_id and l.kind = 'product'),
                                   'discount_amount', (select coalesce(sum(l.sale), 0) from jsonb_to_recordset(v_all) as l(hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text, quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric, qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric) where l.hist_so_id = v_id and l.kind = 'discount'),
                                   'discount_lines', (select count(*) from jsonb_to_recordset(v_all) as l(hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text, quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric, qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric) where l.hist_so_id = v_id and l.kind = 'discount'),
                                   'hidden_lines', (select count(*) from jsonb_to_recordset(v_all) as l(hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text, quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric, qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric) where l.hist_so_id = v_id and l.kind = 'hidden'),
                                   'hidden_amount', (select coalesce(sum(l.sale), 0) from jsonb_to_recordset(v_all) as l(hist_so_id uuid, order_number text, doc_number text, seq int, kind text, sku text, product_id uuid, product_sku text, product_name text, quantity numeric, unit_price numeric, unit_price_adj numeric, sale numeric, sale_adj numeric, tax numeric, qty_cin7_returned numeric, qty_ims_credited numeric, qty_remaining numeric) where l.hist_so_id = v_id and l.kind = 'hidden')),
      'lines', v_lines, 'freight', v_freight, 'tax', v_tax, 'warnings', to_jsonb(v_warn));
    v_orders := v_orders || v_o;
  end loop;
  return jsonb_build_object(
    'number', p_number, 'number_norm', v_num, 'found', jsonb_array_length(v_orders) > 0, 'multiple_orders', jsonb_array_length(v_orders) > 1, 'orders', v_orders,
    'already_credited', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason, 'total', c.total,
                                                                      'customer_id', c.customer_id, 'customer_name', (select cu.name from public.customer cu where cu.id = c.customer_id),
                                                                      'store_customer_id', c.store_customer_id, 'store_name', (select cu.name from public.customer cu where cu.id = c.store_customer_id),
                                                                      'lines', (select coalesce(jsonb_agg(jsonb_build_object('sku', l.sku, 'qty_returned', l.qty_returned, 'kind', l.kind) order by l.line_no), '[]'::jsonb) from public.so_credit_line l where l.credit_id = c.id and l.kind in ('product', 'freight', 'price_adjustment')))
                                                   order by c.credit_number), '[]'::jsonb)
                         from public.so_credit c where c.ref_invoice_number is not null and lower(trim(c.ref_invoice_number)) = v_num),
    'as_of', public.ims_today());
end $$;
revoke all on function public.hist_line_kind(text) from public, anon, authenticated, service_role;   -- 기본 권한(f · anon · authenticated · service_role 전부 X · 615)을 비우고 authenticated 만
revoke all on function public.hist_credit_lines(text) from public, anon, authenticated, service_role;   -- 기본 권한(f · anon · authenticated · service_role 전부 X · 615)을 비우고 authenticated 만
revoke all on function public.hist_credit_tax(text, uuid, date) from public, anon, service_role;   -- 기본 권한(f · anon · authenticated · service_role 전부 X · 615)을 비우고 authenticated 만
revoke all on function public.hist_credit_source(text) from public, anon, service_role;   -- 기본 권한(f · anon · authenticated · service_role 전부 X · 615)을 비우고 authenticated 만
-- hist_line_kind · hist_credit_lines 는 postgres 만(definer 창구 둘과 so_credit_issue 가 속에서 부른다 · 직원 역할 직접 호출 없음)
grant execute on function public.hist_credit_tax(text, uuid, date) to authenticated;
grant execute on function public.hist_credit_source(text) to authenticated;
comment on function public.hist_credit_source(text) is 'hcr-1 판정 774 · 778 · 779 · 781 · 782: 참조 크레딧 화면(hcr-2)이 옛 인보이스 번호로 미리 채울 재료 — {number, number_norm, found, multiple_orders, orders[{hist_so_id, order_number, invoice_number, head_invoice_number, invoice_date, order_date, source, location, customer{hist_customer_name, resolved, store_customer_id, store_name, bill_to_customer_id, bill_to_name, bill_to_is_store, currency_id, currency_code, currency_source history|customer, default_location_id}, totals{…}, lines[{seq, sku, product_id, product_sku, product_name, resolved, qty_sold, unit_price_hist, unit_price(778), amount_hist, amount, tax, rate_pct_line, qty_cin7_returned, qty_ims_credited, qty_remaining}], freight[{seq, sku, description, amount, tax, checked:false}], tax(hist_credit_tax), warnings[customer_unresolved · currency_unknown · order_has_other_invoice:… · product_unresolved:n · over_returned · tax_mixed · tax_rule_differs · tax_pick_needed]}], already_credited[…], as_of} · sales 보기(ims_can_view 첫 줄 문) · definer · stable · 발행은 so_credit_issue(ref + store_customer_id · 줄은 product_sku · unit_price 그대로)';

-- ═══ ⑤ so_credit_issue 재발행 — 원본 DB 바이트(md5 cffc1999ca41558d0a8e2fede1b911e0) + 더한 줄(「hcr-1」) + 바꾼 토큰 하나(ship_to 갈래 a.customer_id = v_cust → coalesce(v_store, v_cust) · 779) · 서명 · 권한 · comment 그대로 ═══
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
  v_bgb       uuid;                                                                   -- bgr-1d: 반품하는 인보이스 줄의 B급 칸(정상 줄 · 참조 크레딧은 null)
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
  -- hcr-1(판정 774 · 778 · 779 · 781): 참조 크레딧이 이력(hist_)을 읽기만 한다 — 매장 칸(v_store) · 778 반영 단가 · 남은 수량 경고 · 781 세금 제안 · 경고를 기록(so_credit.warnings)에 남긴다
  v_store     uuid;  v_hl jsonb := '{}'::jsonb;  v_hist_found boolean := false;  v_hist_manual boolean := false;  v_hist_tax jsonb;  v_hu numeric;  v_hrem numeric;  v_hask numeric;  v_wt text;
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
  if exists (select 1 from jsonb_array_elements(p->'lines') bx                                                          -- bgr-1e 판정 651: 「안 돌아옴 · b_grade」 는 새로 못 쓴다(줄 · 콤보 구성품 · 미리 보기도)
              where nullif(trim(bx->>'not_restocked_reason'), '') = 'b_grade'
                 or exists (select 1 from jsonb_array_elements(case when jsonb_typeof(bx->'components') = 'array' then bx->'components' else '[]'::jsonb end) bc
                             where nullif(trim(bc->>'not_restocked_reason'), '') = 'b_grade')) then
    raise exception 'B-grade goods go back into a B-grade bin now — pick a B-grade bin as the restock bin, or use damaged if it is thrown out — nothing was saved';
  end if;

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
    select s.customer_id into v_store from public.so s where s.id = v_first_io.so_id;                                                                   -- hcr-1 판정 779: 인보이스 크레딧의 매장 = 첫 오더(so_number 순)의 손님
  elsif p ? 'cin7' then
    raise exception 'The cin7 key is gone — send ref {invoice_number, order_number, invoice_date} for a credit without an IMS invoice — nothing was saved';   -- crn-1 판정 609
  elsif p->'ref' is not null and jsonb_typeof(p->'ref') = 'object' then
    v_ref := true;
    v_ref_inv := nullif(trim(p->'ref'->>'invoice_number'), '');  v_ref_ord := nullif(trim(p->'ref'->>'order_number'), '');  v_ref_date := nullif(p->'ref'->>'invoice_date', '')::date;
    if v_ref_inv is null then raise exception 'A reference credit needs ref.invoice_number (the number on the paper invoice) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A reference credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_ref_date;
    if not exists (select 1 from public.customer c where c.id = v_cust) then raise exception 'Customer not found — nothing was saved'; end if;
    v_store := nullif(p->>'store_customer_id', '')::uuid;                                                                                       -- hcr-1 판정 779: 매장(종이 · 목록의 이름) · 돈(customer_id)은 매장의 청구처 coalesce(default_bill_to_customer_id, id) 여야 한다
    if v_store is not null then
      if not exists (select 1 from public.customer c where c.id = v_store) then raise exception 'Store customer not found — nothing was saved'; end if;
      if v_cust <> (select coalesce(c.default_bill_to_customer_id, c.id) from public.customer c where c.id = v_store) then
        raise exception 'customer_id must be the bill-to of store % — the money goes to the bill-to, the paper and the list show the store — nothing was saved', (select c.name from public.customer c where c.id = v_store);
      end if;
    else
      v_store := v_cust;
    end if;
    v_hist_found := exists (select 1 from public.hist_so_line hl where hl.doc_type = 'invoice' and lower(trim(hl.doc_number)) = lower(v_ref_inv));          -- hcr-1 판정 774: 옛 인보이스가 이력에 있으면 읽는다(없으면 옛 동작 그대로)
    if v_hist_found then                                                                                                                            -- 한 곳(hist_credit_lines)의 778 단가 · 남은 수량 — 창구 hist_credit_source 와 같은 식
      select coalesce(jsonb_object_agg(k.key, jsonb_build_object('unit', k.unit, 'rem', k.rem)), '{}'::jsonb) into v_hl
        from (select coalesce(h.product_id::text, upper(h.sku)) as key, min(h.unit_price_adj) as unit, sum(h.qty_remaining) as rem from public.hist_credit_lines(v_ref_inv) h where h.kind = 'product' group by 1) k;
    end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is not null then                                                  -- 보낸 규칙 그대로(활성 판매 규칙 검사 그대로)
      select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
      if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
      v_tax_src := 'given';
    elsif v_hist_found then                                                                               -- hcr-1 판정 781: 이력의 세율 = 매장 지금 규칙이면 그 규칙 · 다르면 같은 세율의 규칙(하나면 제안 · 여럿 · 없음이면 거부 글로 고르라) · 「다르다」 는 경고
      v_hist_tax := public.hist_credit_tax(v_ref_inv, v_store, v_on);
      if nullif(v_hist_tax->'suggested'->>'rule_id', '') is null then
        raise exception 'Pick a tax rule — invoice % was taxed at % percent and % active sale rule(s) have that rate (%) — nothing was saved', v_ref_inv, trim_scale(coalesce((v_hist_tax->>'old_rate_pct')::numeric, 0)),
          jsonb_array_length(coalesce(v_hist_tax->'candidates', '[]'::jsonb)), coalesce((select string_agg(cx->>'rule', ', ') from jsonb_array_elements(coalesce(v_hist_tax->'candidates', '[]'::jsonb)) cx), '-');
      end if;
      select * into v_rule from public.ref_tax_rule r where r.id = (v_hist_tax->'suggested'->>'rule_id')::uuid;
      v_tax_src := 'history';
      if coalesce((v_hist_tax->>'differs')::boolean, false) then v_warn := array_append(v_warn, 'tax_rule_differs:' || coalesce(v_hist_tax->'current_rule'->>'rule', '-')); end if;
    else                                                                                                  -- crn-1 판정 610: 손님 기본 배송지의 주 → so_tax_rule_for(IMS 인보이스와 같은 식) · 없으면 거부(직원이 고른다)
      select * into v_sa from public.customer_address a where a.customer_id = coalesce(v_store, v_cust) and a.type = 'Shipping' and a.is_active and a.is_default_for_type limit 1;
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
    v_bgb := null;                                                                                                                                                         -- bgr-1d
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
        if v_hist_found then                                                                                                  -- hcr-1 판정 774 · 778 · 기술 3: 이력 줄(778 반영 단가 · 남은 수량)과 견준다 — 막지 않는다 · 경고만
          v_hu := (v_hl->(v_pr.id::text)->>'unit')::numeric;  v_hrem := (v_hl->(v_pr.id::text)->>'rem')::numeric;
          if v_hu is null then
            v_hist_manual := true;  v_wt := 'not_on_invoice:' || v_pr.sku;  if not (v_wt = any (v_warn)) then v_warn := array_append(v_warn, v_wt); end if;
          else
            if abs(v_unit - v_hu) >= 0.005 then v_hist_manual := true; end if;                                                                           -- 한 푼(0.005) 이상 다르면 「손으로 넣은 단가」
            select coalesce(sum(nullif(t->>'qty_returned', '')::numeric), 0) into v_hask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(trim(t->>'sku'), '') = v_sku;
            if v_hask > v_hrem then v_wt := format('qty_over_sold:%s:%s/%s', v_pr.sku, trim_scale(v_hask), trim_scale(v_hrem));  if not (v_wt = any (v_warn)) then v_warn := array_append(v_warn, v_wt); end if; end if;
          end if;
        end if;
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
        select sl.bgrade_bin_id into v_bgb from public.so_line sl where sl.id = v_il.so_line_id;                                  -- bgr-1d 판정 640
        if v_bgb is not null then v_warn := array_append(v_warn, 'final_sale:' || v_sku); end if;                                -- bgr-1d: 경고만(노 리턴 · 발행은 막지 않는다)
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
        if v_bin_name is null and v_bgb is not null then                                                                         -- bgr-1d 판정 649: B급 줄의 반품 = 팔려 나간 그 B급 칸
          select rb.name into v_bin_name from public.ref_bin rb where rb.id = v_bgb and rb.is_bgrade and rb.is_active and rb.warehouse_id = v_w.id;
          if v_bin_name is null then v_warn := array_append(v_warn, 'bgrade_bin_gone:' || v_sku); end if;                     -- 꺼졌거나 · 비활성 · 다른 창고 → 정상 기본(ims_last_bin)
        end if;
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
      if exists (select 1 from public.so_line sl where sl.id = v_il.so_line_id and sl.bgrade_bin_id is not null) then v_warn := array_append(v_warn, 'final_sale:' || v_il.sku); end if;   -- bgr-1d: 가격 조정도 같은 경고
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
    if not v_hist_found or v_hist_manual then                                                                                 -- hcr-1 기술 3: 이력이 있으면 단가가 이력(778 반영)과 다를 때 · 인보이스에 없는 제품일 때만
    v_warn := array_append(v_warn, 'manual_unit_price');
    end if;
    if not v_hist_found then v_warn := array_append(v_warn, 'reference_not_in_history'); end if;                                              -- hcr-1: 이력에 없는 번호 — 수량 · 단가를 견주지 못했다
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

  update public.so_credit c set store_customer_id = v_store, warnings = to_jsonb(v_warn) where c.id = v_cr.id;                               -- hcr-1 판정 779 · 기술 3: 매장 · 경고를 기록에(원장 경고까지 합친 뒤 · 상태는 안 건드린다)
  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_ref then jsonb_build_object('ref_invoice_number', v_ref_inv, 'ref_order_number', v_ref_ord, 'ref_invoice_date', v_ref_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct, 'tax_rule_source', v_tax_src)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'freight_discount_amount', v_cr.freight_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ ⑥-a so_credit_detail 재발행 — 원본 DB 바이트(md5 e63b83a64525db62c8b7dabd3130b4ae) + 더한 줄 하나(store_name) · credit.store_customer_id · credit.warnings 는 to_jsonb 로 저절로 ═══
CREATE OR REPLACE FUNCTION public.so_credit_detail(p_credit_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_cr public.so_credit%rowtype;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3b(판정 582): 첫 줄 문 = Credit Notes 의 열쇠(sales 보기) · definer 라 표 정책을 지나므로 여기서 거른다
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found'; end if;
  return jsonb_build_object(
    'credit', to_jsonb(v_cr),
    'customer_name', (select c.name from public.customer c where c.id = v_cr.customer_id),
    'store_name', (select c.name from public.customer c where c.id = v_cr.store_customer_id),                                           -- hcr-1 판정 779: 매장 이름(credit.store_customer_id 와 credit.warnings 는 to_jsonb 로 저절로)
    'invoice_number', (select i.invoice_number from public.so_invoice i where i.id = v_cr.invoice_id),
    'lines', (select coalesce(jsonb_agg(to_jsonb(l) order by l.line_no), '[]'::jsonb) from public.so_credit_line l where l.credit_id = v_cr.id),
    'allocations', (select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at), '[]'::jsonb) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'applied', (select coalesce(sum(a.amount), 0) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null),
    'remaining', public.so_credit_remaining(v_cr.id),                                                                                   -- so-credit-read-1 C1: 식의 한 곳(옛 식은 C0 정의 그대로였다)
    -- so-credit-read-1 R2(2026-09-25) — 더한 키 넷(옛 키 아홉은 그대로 · 부르는 곳 0 이지만 규칙대로 더하기만)
    'credit_row', (select to_jsonb(v) from public.so_credit_list v where v.id = v_cr.id),
    'allocations_all', (select coalesce(jsonb_agg(jsonb_build_object('alloc_id', a.id, 'invoice_id', a.invoice_id, 'invoice_number', i.invoice_number, 'invoice_status', i.status,
                                                                     'refund_payment_id', a.refund_payment_id, 'refund_paid_on', p.paid_on, 'refund_method', p.method, 'refund_reference', p.reference, 'refund_status', p.status,
                                                                     'amount', a.amount, 'source', a.source, 'voided_at', a.voided_at, 'void_note', a.void_note, 'created_at', a.created_at) order by a.created_at), '[]'::jsonb)
                        from public.so_credit_alloc a left join public.so_invoice i on i.id = a.invoice_id left join public.so_payment p on p.id = a.refund_payment_id
                        where a.credit_id = v_cr.id),
    'open_invoices', (select coalesce(jsonb_agg(jsonb_build_object('invoice_id', l.id, 'invoice_number', l.invoice_number, 'issued_on', l.issued_on, 'due_on', l.due_on, 'due_unknown', l.due_unknown,
                                                                   'total', l.total, 'remaining', l.remaining, 'days_overdue', l.days_overdue, 'so_numbers', l.so_numbers,
                                                                   'attached_from_this_credit', coalesce((select sum(a.amount) from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id = l.id and a.voided_at is null), 0)) order by l.issued_on, l.invoice_number), '[]'::jsonb)
                      from public.so_invoice_list l
                      where l.is_open and l.bill_to_customer_id = v_cr.customer_id and l.currency_id = v_cr.currency_id),
    'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_cr.customer_id) b where b.currency_id = v_cr.currency_id),
    'ledger', (select coalesce(jsonb_agg(jsonb_build_object('id', g.id, 'occurred_on', g.occurred_on, 'sku', g.sku, 'warehouse', g.warehouse, 'bin', g.bin, 'qty_delta', g.qty_delta, 'line_ref', g.line_ref, 'cost', g.raw -> 'cost') order by g.id), '[]'::jsonb)
                 from public.inv_ledger g where g.doc_type = 'creditnote' and g.doc_number = v_cr.credit_number and g.source = 'ims'),
    'layers', (select coalesce(jsonb_agg(jsonb_build_object('id', y.id, 'sku', y.sku, 'warehouse', y.warehouse, 'qty', y.qty, 'unit_cost', case when (select public.ims_can_view_cost()) then y.unit_cost end /* rls-3b(판정 580): 원가 값만 열쇠로 */, 'cost_source', y.cost_source, 'parent_layer_id', y.parent_layer_id,
                                                            'consumed', (select coalesce(sum(k.qty), 0) from public.inv_layer_consume k where k.layer_id = y.id)) order by y.id), '[]'::jsonb)
               from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = v_cr.credit_number));
end;

$function$;

-- ═══ ⑥-b doc_data_credit 재발행 — 원본 DB 바이트(md5 494b84313f58d7b29b39aafbe986e894) + 바꾼 토큰 하나(참조 크레딧 배송지 블록 c.id = coalesce(store_customer_id, customer_id) · 779 종이의 매장) · 청구 블록 그대로 ═══
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
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Shipping' and a.is_default_for_type where c.id = coalesce(v_cr.store_customer_id, v_cr.customer_id);   -- hcr-1 판정 779: 참조 크레딧의 배송지 블록(종이의 매장) = 매장 칸 · 청구 블록은 청구처 그대로
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

-- ═══ ⑥-c so_credit_list — 끝에 store_customer_id · store_name(create or replace · 앞 칸 이름 · 순서 · 꼴 그대로 · ACL · security_invoker 그대로) · search_text 에 매장 이름 ═══
create or replace view public.so_credit_list with (security_invoker = true) as
 WITH al AS (
         SELECT a.credit_id,
            sum(a.amount) FILTER (WHERE a.invoice_id IS NOT NULL) AS applied_to_invoices,
            sum(a.amount) FILTER (WHERE a.refund_payment_id IS NOT NULL) AS refunded,
            string_agg(i_1.invoice_number, ', '::text ORDER BY i_1.invoice_number) FILTER (WHERE a.invoice_id IS NOT NULL) AS invoice_numbers_applied
           FROM so_credit_alloc a
             LEFT JOIN so_invoice i_1 ON i_1.id = a.invoice_id
          WHERE a.voided_at IS NULL
          GROUP BY a.credit_id
        )
 SELECT c.id,
    c.credit_number,
    c.status,
    c.issued_on,
    c.customer_id,
    cu.name AS customer_name,
    c.currency_id,
    c.currency_code,
    c.reason,
    c.note,
    c.warehouse_id,
    c.warehouse_name,
    c.invoice_id,
    i.invoice_number,
    c.ref_invoice_number,
    c.ref_order_number,
    c.origin_invoice_on,
    c.lines_amount,
    c.fee_amount,
    c.tax_amount,
    c.total,
    COALESCE(al.applied_to_invoices, 0::numeric) AS applied_to_invoices,
    COALESCE(al.refunded, 0::numeric) AS refunded,
    r.remaining,
    al.invoice_numbers_applied,
    c.cancelled_at,
    c.cancel_note,
    c.created_at,
    ( SELECT s.name
           FROM ims_staff s
          WHERE s.id = c.issued_by) AS issued_by_name,
    (((((((((((((c.credit_number || ' '::text) || COALESCE(cu.name, ''::text)) || ' '::text) || COALESCE(i.invoice_number, ''::text)) || ' '::text) || COALESCE(c.ref_invoice_number, ''::text)) || ' '::text) || COALESCE(al.invoice_numbers_applied, ''::text)) || ' '::text) || c.reason) || ' '::text) || COALESCE(c.note, ''::text)) || ' '::text) || COALESCE(st.name, ''::text) AS search_text,   -- hcr-1: 매장 이름도 찾힌다
    c.surcharge_amount,
    c.store_customer_id,                                                                                                                                   -- hcr-1 판정 779
    st.name AS store_name
   FROM so_credit c
     LEFT JOIN customer cu ON cu.id = c.customer_id
     LEFT JOIN customer st ON st.id = c.store_customer_id
     LEFT JOIN so_invoice i ON i.id = c.invoice_id
     LEFT JOIN al ON al.credit_id = c.id
     CROSS JOIN LATERAL ( SELECT so_credit_remaining(c.id) AS remaining) r;
comment on view public.so_credit_list is '⭐ 크레딧 노트 목록(so-credit-read-1 R1 · surcharge-2b 열 하나 끝에 · hcr-1 열 둘 끝에) — 한 장 한 행 · security_invoker · applied_to_invoices · refunded · remaining = so_credit_remaining(id) · applied + refunded + remaining = total(issued) · ⭐ surcharge_amount(자동 surcharge 줄 합 · lines_amount 밖 · total 에는 들어 있다) · invoice_number(원판매) · search_text(매장 이름 포함) · crn-1 판정 609: cin7_invoice_number · cin7_order_number → ref_invoice_number · ref_order_number(참조 크레딧 · 인보이스 없음) · hcr-1 판정 779: store_customer_id · store_name(종이 · 목록의 매장 · customer_id 는 청구처)';

-- ═══ 착지 — 색인 · 칸 · 함수 넷 · 재발행 셋 md5 · ACL · 뷰 칸 ═══
do $$
declare v text;
begin
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_credit_issue', 'so_credit_detail', 'doc_data_credit'))
     <> 'doc_data_credit=017c7f9b5111995d418a6d5888d27bda so_credit_detail=66041c902b54876b062c242f1c9218b6 so_credit_issue=1530f29bf9e67108d58438b375a023f3' then raise exception 'hcr-1 landing check failed: reissued bodies'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('hist_line_kind', 'hist_credit_lines', 'hist_credit_tax', 'hist_credit_source')) <> 4 then raise exception 'hcr-1 landing check failed: functions'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('hist_credit_tax', 'hist_credit_source') and p.proacl::text <> '{postgres=X/postgres,authenticated=X/postgres}') then raise exception 'hcr-1 landing check failed: function acl (tax/source)'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('hist_line_kind', 'hist_credit_lines') and p.proacl::text <> '{postgres=X/postgres}') then raise exception 'hcr-1 landing check failed: function acl (kind/lines)'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('hist_credit_lines', 'hist_credit_tax', 'hist_credit_source') and (not p.prosecdef or p.provolatile <> 's')) then raise exception 'hcr-1 landing check failed: definer/stable'; end if;
  if (select relacl::text from pg_class where oid = 'public.so_credit'::regclass) <> '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}' then raise exception 'hcr-1 landing check failed: so_credit acl changed'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit' and column_name in ('store_customer_id', 'warnings')) <> 2 then raise exception 'hcr-1 landing check failed: columns'; end if;
  if (select count(*) from pg_indexes where schemaname = 'public' and indexname in ('hist_so_line_doc_number_idx', 'so_credit_store_idx', 'so_credit_ref_number_idx')) <> 3 then raise exception 'hcr-1 landing check failed: indexes'; end if;
  if (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit_list') not like '%,surcharge_amount,store_customer_id,store_name' then raise exception 'hcr-1 landing check failed: view columns'; end if;
  if (select relacl::text from pg_class where oid = 'public.so_credit_list'::regclass) <> '{postgres=arwdDxtm/postgres,service_role=arwdDxtm/postgres,authenticated=r/postgres}' then raise exception 'hcr-1 landing check failed: view acl'; end if;
  if not exists (select 1 from pg_class c where c.oid = 'public.so_credit_list'::regclass and c.reloptions::text like '%security_invoker=true%') then raise exception 'hcr-1 landing check failed: view security_invoker'; end if;
end $$;
