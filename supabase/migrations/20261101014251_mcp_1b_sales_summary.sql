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
-- mcp-1b — IMS Claude 커넥터 ⑥ 판매 집계 창구 mcp_sales + 이름 고르기 도우미 mcp_name_pick · 셀 도우미 mcp_sales_cell + hist_line_kind 재정의(SET 없이 · 본문 바이트 그대로 · 인라인) (2026-11-01 UTC · 판정 918 ~ 920 · 923 · 925 ~ 930 · 지시서 ~/asung/prompts/mcp-1b.md · 이견 1 ~ 15 전부 반영)
--   무엇: Claude 커넥터 도구 ⑥ sales_summary 의 창구 — 기간 × 묶음(brand · customer · month · sku · supplier) · 거르기(brand · customer · sku · supplier 이름) · 판매 · 크레딧 · 순매출 · 수량 · (원가 열쇠가 있으면) COGS · GP · 「합계는 IMS 가 낸다」(918 · deferred 360)
--   출처: 이력(hist_so_line · kind product · invoice → 판매(인보이스 날짜) · credit → 크레딧(크레딧 발행일 · 926)) ∪ IMS(so_invoice_line kind product · kind sale · issued · opening 제외 − so_credit_line product · price_adjustment · issued) — 제품 줄만(925) · 세전 · CAD 만(이견 11)
--   원가(928 · 이견 2 · 3): inv_layer_consume sale_out(reason sale) − inv_layer creditnote 레이어(qty × unit_cost · 날짜 = received_on) · 열쇠 = 이력 오더 번호 × SKU · IMS so_line.id(콤보 구성품은 combo_line_id 로 부모) · 크레딧 번호 × SKU · 못 맞는 원가는 오더(손님 · 인보이스 날짜)로 올리고 totals.cogs_unmatched 로 밝힘
--   GP(928 · 이견 10): gp_from = greatest(from, 2026-08-21) · net_costed = 원가 행이 붙은 판매 − 그 구간 크레딧 · gp = net_costed − cogs · gp_pct = gp / net_costed · uncosted_sales 밝힘 · 구간이 없으면 null(지어내지 않는다) · 원가 열쇠(ims_can_view_cost)가 없으면 열쇠 자체가 없다(919)
--   손님(929 · 이견 4): coalesce(parent_id, id) 한 줄 + accounts(본사 자신 포함 · 둘 이상일 때) · 지점 이름으로 거르면 그 계정만 · 공급처(930 · 이견 5): product_supplier is_default and is_active · 여럿이면 이름순 첫째 · 없으면 (no supplier) · 브랜드 없으면 (no brand)(927)
--   표 밖(925 · 926 · 이견 7 ~ 9): other{freight, services, order_discount, adjustments, invoice_total_pretax, other_credits, excluded_non_cad} — brand · sku · supplier 거르기가 없을 때만(오더 단위) · 늘 sales + freight + services + order_discount + adjustments = invoice_total_pretax
--   ⭐ 이견 1: hist_line_kind 의 `set search_path` 가 인라인을 막아 283k 행마다 호출(1 년 sku 5.9 s) → SET 없이 같은 본문(객체 참조 0) · WHERE 가 아니라 select 에서만 계산(플래너 0.5 % 추정 → 중첩 루프 함정) · 새 색인 없음(seq scan 이 본질)
--   실측(테스트 DB 2026-11-01 · ims_connector · 1 년 2025-11-01 ~ 2026-10-31 · limit 50): brand 3.2 s · month 3.3 s · customer 3.4 s · sku 3.9 s · supplier 3.3 s(8 초 예산 · statement_timeout 8s) — 첫 판 40 s(CTE 결과에 거른 뒤 조인 → 플래너 0.5 % 추정 · 중첩 루프 · 디스크 정렬) → 줄 전부 한 집합 · 거르기 뒤 해시 집계 한 번 · 열쇠 짝은 해시 조인(EXISTS 서브플랜 금지) · work_mem 32MB(함수 SET · 기본 3.5MB 면 해시 집계가 디스크로)
--   권한: 도구 mcp_sales 는 ims_connector 만 EXECUTE · 도우미(mcp_name_pick · mcp_sales_cell)는 아무에게도(definer 셸이 postgres 로 부른다) · 첫 줄 mcp_gate('sales')
--   무접촉: mcp-1a 의 역할 · 훅 · 도구 ① ~ ⑤ · mcp_config · mcp-2 기록 · 화면 · 대시보드 · 첫 문장 = guard-test-only.sql 바이트 복사 · 컷오버 날 지우는 순서: 표 없음
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261101014251_mcp_1b_sales_summary.sql && supabase migration repair --status applied 20261101014251 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261101014251_mcp_1b_sales_summary.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_1b_check.sql

-- ═══ A) hist_line_kind — SET 없이 다시(본문은 20261027010153 hcr-1 54 ~ 61 행 바이트 그대로 · 이견 1) ═══
create or replace function public.hist_line_kind(p_sku text) returns text
  language sql immutable as $$
  select case
    when p_sku is null then 'product'
    when p_sku = '_4_' or lower(p_sku) = 'shipping' or lower(p_sku) like 'shipping - %' then 'freight'          -- 판정 782: 운임 줄(_4_ · Shipping - Standard · Shipping - Free Shipping …) — 보이되 기본 해제
    when p_sku in ('Discount', 'Order total discount') then 'discount'                                           -- 판정 778: 오더 전체 할인 — 제품 줄 단가에 나눠 넣는다(안 보인다)
    when lower(p_sku) like 'customer credit%' or upper(p_sku) like 'CREDIT-%' then 'hidden'                       -- 판정 782: Customer Credit Write-off · CREDIT-01 — 안 보인다
    else 'product' end $$;                                                                                         -- 제품(product_id 가 비어도 — FINAL-SALE · AMZ00201 같은 「못 푼 제품 줄」 은 표시로)
comment on function public.hist_line_kind(text) is 'hcr-1 한 곳: hist_so_line.sku 원문 → product | freight | discount | hidden (판정 778 · 782) — hist_credit_lines · mcp_sales 가 부른다 · ⭐ [2026-11-01 mcp-1b 이견 1] set search_path 를 뺐다(객체 참조 0 · SET 이 있으면 SQL 함수가 인라인되지 않아 283k 행마다 호출 = 1 년 집계 5.9 s → 인라인 2.4 s) · 본문 무변 · 실측(테스트 DB 2026-10-26): _4_ 9,201 · Shipping - Standard 2,588 · Shipping - Aonebeauty TOR 300 · Shipping - Free Shipping 15 · Discount 24 · Order total discount 14 · Customer Credit Write-off 9';

-- ═══ B) 도우미 ① mcp_name_pick — 브랜드 · 공급처 이름 → id(정확 → 포함 유일 → 후보 ≤ 5) · mcp_customer_pick 꼴(이견 5) ═══
create or replace function public.mcp_name_pick(p_kind text, p_q text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_q text := btrim(coalesce(p_q, '')); v_n int; v_id uuid; v_name text; v_c jsonb;
begin
  if v_q = '' then return jsonb_build_object('matches', 0, 'id', null, 'name', null, 'candidates', '[]'::jsonb); end if;
  if p_kind = 'brand' then
    with m as (select b.id, b.name, b.is_active, lower(b.name) = lower(v_q) as exact from public.ref_brand b where b.name ilike '%' || v_q || '%')
    select count(*), coalesce((select id from m where exact order by is_active desc, name limit 1), (select case when count(*) = 1 then (array_agg(id))[1] end from m)),
           (select coalesce(jsonb_agg(x.name order by x.exact desc, x.is_active desc, x.name), '[]'::jsonb) from (select * from m order by exact desc, is_active desc, name limit 5) x)
      into v_n, v_id, v_c from m;
    select b.name into v_name from public.ref_brand b where b.id = v_id;
  elsif p_kind = 'supplier' then
    with m as (select s.id, s.name, s.is_active, lower(s.name) = lower(v_q) as exact from public.supplier s where s.name ilike '%' || v_q || '%')
    select count(*), coalesce((select id from m where exact order by is_active desc, name limit 1), (select case when count(*) = 1 then (array_agg(id))[1] end from m)),
           (select coalesce(jsonb_agg(x.name order by x.exact desc, x.is_active desc, x.name), '[]'::jsonb) from (select * from m order by exact desc, is_active desc, name limit 5) x)
      into v_n, v_id, v_c from m;
    select s.name into v_name from public.supplier s where s.id = v_id;
  else
    raise exception 'mcp_name_pick: unknown kind %', p_kind;
  end if;
  return jsonb_build_object('matches', v_n, 'id', v_id, 'name', v_name, 'candidates', v_c);
end;
$$;
comment on function public.mcp_name_pick(text, text) is 'mcp-1b 이견 5: 브랜드(ref_brand) · 공급처(supplier) 이름 검색 → {matches, id · name(정확 일치 또는 유일 포함이면 · 아니면 null), candidates ≤ 5(이름만)} — 내부 · EXECUTE 아무에게도';

-- ═══ C) 도우미 ② mcp_sales_cell — 한 칸(행 · 계정 · 합계)의 jsonb · 원가 열쇠는 p_cost 일 때만(919) · GP 구간이 없으면 null(928) ═══
create or replace function public.mcp_sales_cell(p_sales numeric, p_credits numeric, p_qty numeric, p_qty_credited numeric, p_cogs numeric, p_sales_costed numeric, p_credits_costed numeric, p_uncosted numeric, p_cost boolean, p_window boolean) returns jsonb
  language sql immutable
as $$
  select jsonb_build_object('sales', round(coalesce(p_sales, 0), 2), 'credits', round(coalesce(p_credits, 0), 2), 'net', round(coalesce(p_sales, 0) - coalesce(p_credits, 0), 2),
                            'qty', trim_scale(coalesce(p_qty, 0)), 'qty_credited', trim_scale(coalesce(p_qty_credited, 0)))
      || case when not p_cost then '{}'::jsonb
              when not p_window then jsonb_build_object('cogs', null, 'gp', null, 'gp_pct', null, 'net_costed', null, 'uncosted_sales', null)
              else jsonb_build_object('cogs', round(coalesce(p_cogs, 0), 2),
                                      'gp', round(coalesce(p_sales_costed, 0) - coalesce(p_credits_costed, 0) - coalesce(p_cogs, 0), 2),
                                      'gp_pct', case when coalesce(p_sales_costed, 0) - coalesce(p_credits_costed, 0) <> 0
                                                     then round((coalesce(p_sales_costed, 0) - coalesce(p_credits_costed, 0) - coalesce(p_cogs, 0)) / (coalesce(p_sales_costed, 0) - coalesce(p_credits_costed, 0)) * 100, 1) end,
                                      'net_costed', round(coalesce(p_sales_costed, 0) - coalesce(p_credits_costed, 0), 2),
                                      'uncosted_sales', round(coalesce(p_uncosted, 0), 2)) end
$$;
comment on function public.mcp_sales_cell(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, boolean, boolean) is 'mcp-1b: 판매 집계 한 칸 — sales · credits · net · qty · qty_credited + (p_cost 면) cogs · gp · gp_pct · net_costed · uncosted_sales(p_window 가 아니면 전부 null · 928) — 내부 · EXECUTE 아무에게도';

-- ═══ D) 도구 ⑥ mcp_sales ═══
create or replace function public.mcp_sales(p_from text, p_to text, p_group text, p_brand text default null, p_customer text default null, p_sku text default null, p_supplier text default null, p_limit int default 50) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp set work_mem = '32MB'   -- 32MB: 해시 집계 · 해시 조인이 디스크로 안 넘치게(기본 3.5MB · 머리 주석의 실측)
as $$
declare
  c_cost_from constant date := '2026-08-21';                                           -- 판정 928: 원가 기록 시작(inv_layer_consume sale_out 첫 날 · 시험이 실물로 단언)
  v_from date; v_to date; v_gp_from date;
  v_group text := lower(btrim(coalesce(p_group, '')));
  v_limit int := coalesce(p_limit, 50);
  v_cost boolean;
  v_brand text; v_sup text; v_sku text; v_cust uuid; v_cust_group uuid; v_cust_acct uuid;
  v_filters jsonb := '{}'::jsonb;
  v_other_ok boolean;
  pk jsonb; v_q text; v_n int; v_cr record;
  v_res jsonb;
begin
  perform public.mcp_gate('sales');
  -- 인자 검사(이견 13) — 영어 한 문장
  if coalesce(p_from, '') !~ '^\d{4}-\d{2}-\d{2}$' or coalesce(p_to, '') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'Give from and to as dates in YYYY-MM-DD form — nothing was read'; end if;
  begin v_from := p_from::date; v_to := p_to::date; exception when others then raise exception 'from or to is not a real calendar date (% · %) — nothing was read', p_from, p_to; end;
  if v_from > v_to then raise exception 'from (%) is after to (%) — nothing was read', v_from, v_to; end if;
  if v_to > v_from + interval '3 years' then raise exception 'The period is longer than 3 years — ask for a shorter range — nothing was read'; end if;
  if v_group not in ('brand', 'customer', 'month', 'sku', 'supplier') then raise exception 'group must be one of brand, customer, month, sku, supplier — nothing was read'; end if;
  if v_limit < 1 or v_limit > 200 then raise exception 'limit must be between 1 and 200 — nothing was read'; end if;
  v_cost := public.ims_can_view_cost();
  v_gp_from := greatest(v_from, c_cost_from); if v_gp_from > v_to then v_gp_from := null; end if;
  -- 거르기(이름 → 하나 · 못 풀면 후보)
  if nullif(btrim(coalesce(p_brand, '')), '') is not null then
    pk := public.mcp_name_pick('brand', p_brand);
    if pk->>'id' is null then return jsonb_build_object('resolved', false, 'field', 'brand', 'query', btrim(p_brand), 'matches', pk->'matches', 'candidates', pk->'candidates'); end if;
    v_brand := pk->>'name'; v_filters := v_filters || jsonb_build_object('brand', v_brand);
  end if;
  if nullif(btrim(coalesce(p_supplier, '')), '') is not null then
    pk := public.mcp_name_pick('supplier', p_supplier);
    if pk->>'id' is null then return jsonb_build_object('resolved', false, 'field', 'supplier', 'query', btrim(p_supplier), 'matches', pk->'matches', 'candidates', pk->'candidates'); end if;
    v_sup := pk->>'name'; v_filters := v_filters || jsonb_build_object('supplier', v_sup);
  end if;
  if nullif(btrim(coalesce(p_customer, '')), '') is not null then
    pk := public.mcp_customer_pick(p_customer);
    v_cust := (pk->>'id')::uuid;
    if v_cust is null then return jsonb_build_object('resolved', false, 'field', 'customer', 'query', btrim(p_customer), 'matches', pk->'matches', 'candidates', pk->'candidates'); end if;
    select c.name, c.parent_id, (select p.name from public.customer p where p.id = c.parent_id) as parent_name into v_cr from public.customer c where c.id = v_cust;
    if v_cr.parent_id is null then v_cust_group := v_cust; v_filters := v_filters || jsonb_build_object('customer', v_cr.name, 'customer_scope', 'this customer and its accounts');
    else v_cust_acct := v_cust; v_filters := v_filters || jsonb_build_object('customer', v_cr.name, 'customer_scope', 'this account only', 'parent_name', v_cr.parent_name); end if;
  end if;
  if nullif(btrim(coalesce(p_sku, '')), '') is not null then
    v_q := upper(btrim(p_sku));
    select p.sku into v_sku from public.product p where upper(p.sku) = v_q;
    if v_sku is null then
      select count(*), min(p.sku) into v_n, v_sku from public.product p where p.sku ilike '%' || v_q || '%';
      if v_n <> 1 then
        return jsonb_build_object('resolved', false, 'field', 'sku', 'query', v_q, 'matches', v_n,
                                  'candidates', (select coalesce(jsonb_agg(jsonb_build_object('sku', x.sku, 'name', x.name) order by x.sku), '[]'::jsonb) from (select p.sku, p.name from public.product p where p.sku ilike '%' || v_q || '%' order by p.sku limit 5) x));
      end if;
    end if;
    v_sku := upper(v_sku); v_filters := v_filters || jsonb_build_object('sku', v_sku);
  end if;
  v_other_ok := v_brand is null and v_sup is null and v_sku is null;

  with
  -- 기본 공급처(930 · 이견 5): is_default · is_active · 여럿이면 이름순 첫째
  ps as (select x.product_id, min(s.name) as supplier
           from public.product_supplier x join public.supplier s on s.id = x.supplier_id
          where x.is_default and x.is_active group by x.product_id),
  -- IMS 오더 → 인보이스 날짜(못 맞춘 원가의 날짜 자리)
  soi as (select o.so_id, max(i.issued_on) as d from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where i.kind = 'sale' and i.status = 'issued' group by o.so_id),
  -- ① 줄 전부 한 번에 — src: sale · credit(제품 줄 · (ldoc, sku) = 원가와 맞출 열쇠 · 이견 3) · freight · services · order_discount · adjustments · other_credit · non_cad(이견 7 ~ 9 · 11)
  --    ⚠️ 이력 kind 는 WHERE 가 아니라 select 에서(이견 1 · 플래너 0.5 % 추정 → 중첩 루프 함정) · hist_line_kind(lower · like 넷)를 줄마다 부르면 1.3 s(283k 행) → 특수 꼴일 수 있는 줄에만(정규식 하나 · ci · 상위 집합) · 뜻은 hist_line_kind 가 정한다
  ln as (select case when x.kind = 'product' and x.doc_type = 'invoice' then 'sale' when x.kind = 'product' then 'credit' when x.doc_type = 'credit' then 'other_credit'
                     when x.kind = 'freight' then 'freight' when x.kind = 'services' then 'services' when x.kind = 'discount' then 'order_discount' else 'adjustments' end as src,
                case when x.kind <> 'product' then null when x.doc_type = 'invoice' then x.order_number else 'c:' || lower(btrim(x.doc_number)) end as ldoc,
                x.d, x.customer_id, x.brand, x.usku as sku, x.product_id, x.amount, x.qty, (x.doc_type = 'invoice') as inv
           from (select h.order_number, hl.doc_number, hl.doc_type, upper(hl.sku) as usku, hl.product_id, nullif(hl.brand, '') as brand, h.customer_id,
                        case when hl.doc_type = 'invoice' then h.invoice_date else hl.doc_date end as d, case when hl.doc_type = 'invoice' then hl.sale else -hl.sale end as amount, abs(hl.quantity) as qty,
                        case when hl.sku ~* '^(_[0-9]+_$|shipping|discount$|order total discount$|customer credit|credit-)'
                             then (case when hl.sku ~ '^_[0-9]+_$' and hl.sku <> '_4_' then 'services' else public.hist_line_kind(hl.sku) end) else 'product' end as kind
                   from public.hist_so h join public.hist_so_line hl on hl.hist_so_id = h.id
                  where (hl.doc_type = 'invoice' and h.invoice_date between v_from and v_to) or (hl.doc_type = 'credit' and hl.doc_date between v_from and v_to)
                 offset 0) x
         union all
         -- IMS 인보이스 줄 — kind sale · issued · opening 제외 · 콤보 구성 줄 제외 · CAD 아니면 non_cad(이견 11)
         select case when coalesce(i.currency_code, 'CAD') <> 'CAD' then 'non_cad' when l.kind = 'product' then 'sale'
                     when l.kind in ('charge', 'charge_discount') and sc.service_id is null then 'freight' when l.kind in ('charge', 'charge_discount', 'surcharge') then 'services' else 'order_discount' end,
                case when l.kind = 'product' and coalesce(i.currency_code, 'CAD') = 'CAD' then 'i:' || l.so_line_id::text end, i.issued_on, coalesce(o.customer_id, s.customer_id), p.brand_name, upper(l.sku), sl.product_id,
                l.amount, l.qty, coalesce(i.currency_code, 'CAD') = 'CAD'
           from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id join public.so s on s.id = o.so_id join public.so_invoice_line l on l.invoice_order_id = o.id
           left join public.so_line sl on sl.id = l.so_line_id left join public.product p on p.id = sl.product_id left join public.so_charge sc on sc.id = l.so_charge_id
          where i.kind = 'sale' and i.status = 'issued' and i.issued_on between v_from and v_to and sl.combo_line_id is null
         union all
         -- IMS 크레딧 줄 — issued · 콤보 자식 제외 · tax 줄 제외(세전) · product · price_adjustment 가 제품 크레딧
         select case when coalesce(c.currency_code, 'CAD') <> 'CAD' then 'non_cad' when l.kind in ('product', 'price_adjustment') then 'credit' else 'other_credit' end,
                case when l.kind in ('product', 'price_adjustment') and coalesce(c.currency_code, 'CAD') = 'CAD' then 'c:' || lower(c.credit_number) end, c.issued_on, c.customer_id, p.brand_name, upper(l.sku), l.product_id,
                l.amount, coalesce(l.qty_returned, 0), false
           from public.so_credit c join public.so_credit_line l on l.credit_id = c.id left join public.product p on p.id = l.product_id
          where c.status = 'issued' and c.issued_on between v_from and v_to and l.combo_credit_line_id is null and l.kind <> 'tax'),
  -- ② 원가(928 · 이견 2 · 3): sale_out(reason sale) 을 열쇠로 — IMS line_ref = so_line.id(콤보 구성품은 부모 줄 · 자리도 부모 제품) · 이력 = 오더 번호 × SKU · 자리 = 오더 머리(손님 · 인보이스 날짜) + 소비한 SKU 의 제품
  cg as (select c.doc_number, upper(l.sku) as sku, sum(c.amount) as amt, min(c.occurred_on) as occ,
                case when c.line_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then c.line_ref::uuid end as line_uuid
           from public.inv_layer_consume c join public.inv_layer l on l.id = c.layer_id
          where c.event_type = 'sale_out' and c.reason = 'sale' and v_gp_from is not null
          group by 1, 2, 5),
  -- 판매 줄 열쇠(기간 안) — 원가에 판매 줄이 있는가(matched) · hashed subplan
  sk as (select distinct h.order_number as ldoc, upper(hl.sku) as lsku
           from public.hist_so h cross join lateral (select hl.sku from public.hist_so_line hl where hl.hist_so_id = h.id and hl.doc_type = 'invoice' offset 0) hl   -- offset 0: (hist_so_id, seq) 색인으로 오더의 줄만(hcr-1 선례)
          where v_gp_from is not null and h.invoice_date between v_gp_from and v_to
         union
         select 'i:' || l.so_line_id::text, upper(l.sku) from public.so_invoice i join public.so_invoice_order o on o.invoice_id = i.id join public.so_invoice_line l on l.invoice_order_id = o.id
          where v_gp_from is not null and i.kind = 'sale' and i.status = 'issued' and i.issued_on between v_gp_from and v_to and l.kind = 'product'),
  cx as (select 'cogs' as src, lk.ldoc, (s.ldoc is not null) as matched,
                coalesce(fh.invoice_date, soi.d, g.occ) as d, coalesce(fh.customer_id, fs.customer_id) as customer_id,
                coalesce(pi.brand_name, ph.brand_name) as brand, lk.lsku as sku, coalesce(pi.id, ph.id) as product_id, g.amt as amount
           from cg g
           left join public.so_line sl on sl.id = g.line_uuid
           left join public.so_line slp on slp.id = coalesce(sl.combo_line_id, sl.id)
           cross join lateral (select case when slp.id is not null then 'i:' || slp.id::text else g.doc_number end as ldoc, coalesce(upper(slp.sku), g.sku) as lsku) lk
           left join sk s on s.ldoc = lk.ldoc and s.lsku = lk.lsku
           left join public.product pi on pi.id = slp.product_id
           left join public.product ph on sl.id is null and upper(ph.sku) = g.sku
           left join public.hist_so fh on fh.era = 'core' and fh.order_number = g.doc_number
           left join public.so fs on fs.so_number = g.doc_number
           left join soi on soi.so_id = fs.id),
  -- ③ 재입고 복원(creditnote 레이어 · 이견 2) — 열쇠 = 크레딧 번호 × SKU · 날짜 = received_on · 자리 = 크레딧 머리의 손님 + 제품
  rs as (select l.doc_number, upper(l.sku) as sku, l.received_on, sum(l.qty * l.unit_cost) as amt
           from public.inv_layer l where l.origin_type = 'creditnote' and v_gp_from is not null and l.received_on between v_gp_from and v_to group by 1, 2, 3),
  rx as (select 'restock' as src, 'c:' || lower(btrim(r.doc_number)) as ldoc, r.received_on as d, coalesce(fh.customer_id, fc.customer_id) as customer_id, p.brand_name as brand, r.sku, p.id as product_id, r.amt as amount
           from rs r
           left join lateral (select h.customer_id from public.hist_so_line hl join public.hist_so h on h.id = hl.hist_so_id
                               where hl.doc_type = 'credit' and lower(btrim(hl.doc_number)) = lower(btrim(r.doc_number)) limit 1) fh on true
           left join public.so_credit fc on fc.credit_number = r.doc_number
           left join public.product p on upper(p.sku) = r.sku),
  ck as (select distinct x.ldoc, x.sku from cx x),   -- 원가가 붙은 열쇠(판매 줄의 costed · 해시 조인 · ⚠️ EXISTS 서브플랜은 플래너가 hashed 를 안 고르면 283k × 56k — 실측으로 겪음)
  -- ④ 하나로 + 손님 묶음(929) + 공급처 + 거르기(브랜드 · 손님 · SKU · 공급처) — 한 번 · 표 밖 줄은 gkey null · okind = 그 종류 · costed = 그 판매 줄에 원가가 붙었나(hashed subplan · 열쇠 단위 집계 없음)
  f as (select u.src, u.d, u.amount, u.qty, u.inv, u.customer_id, u.matched,
               (u.src = 'sale' and ck.ldoc is not null) as costed,
               case when u.src not in ('sale', 'credit', 'cogs', 'restock') then null
                    when v_group = 'brand' then coalesce(u.brand, '(no brand)') when v_group = 'customer' then coalesce(coalesce(c.parent_id, c.id)::text, '(no customer)') when v_group = 'month' then to_char(u.d, 'YYYY-MM')
                    when v_group = 'sku' then u.sku else coalesce(ps.supplier, '(no supplier)') end as gkey,
               case when u.src in ('sale', 'credit', 'cogs', 'restock') then null else u.src end as okind
          from (select x.src, x.ldoc, x.d, x.customer_id, x.brand, x.sku, x.product_id, x.amount, x.qty, x.inv, true as matched from ln x where v_other_ok or x.src in ('sale', 'credit')
                union all select x.src, x.ldoc, x.d, x.customer_id, x.brand, x.sku, x.product_id, x.amount, null::numeric, false, x.matched from cx x where x.d between v_gp_from and v_to
                union all select x.src, x.ldoc, x.d, x.customer_id, x.brand, x.sku, x.product_id, x.amount, null::numeric, false, true from rx x) u
          left join public.customer c on c.id = u.customer_id left join ps on ps.product_id = u.product_id
          left join ck on u.src = 'sale' and ck.ldoc = u.ldoc and ck.sku = u.sku
         where (v_brand is null or lower(coalesce(u.brand, '')) = lower(v_brand))
           and (v_cust_group is null or coalesce(c.parent_id, c.id) = v_cust_group) and (v_cust_acct is null or u.customer_id = v_cust_acct)
           and (v_sku is null or u.sku = v_sku)
           and (v_sup is null or lower(coalesce(ps.supplier, '')) = lower(v_sup))),
  -- ⑤ 계정 단위(929) → 묶음 단위 롤업 — 해시 집계 한 번(묶음 × 계정 × 종류 ≈ 수만)
  ga as (select f.gkey, f.customer_id, f.okind,
                coalesce(sum(f.amount) filter (where f.src = 'sale'), 0) as sales, coalesce(sum(f.amount) filter (where f.src = 'credit'), 0) as credits,
                coalesce(sum(f.qty) filter (where f.src = 'sale'), 0) as qty, coalesce(sum(f.qty) filter (where f.src = 'credit'), 0) as qty_credited,
                coalesce(sum(f.amount) filter (where f.src = 'cogs'), 0) - coalesce(sum(f.amount) filter (where f.src = 'restock'), 0) as cogs,
                coalesce(sum(f.amount) filter (where f.src = 'cogs' and not f.matched), 0) as cogs_unmatched,
                coalesce(sum(f.amount) filter (where f.src = 'sale' and f.costed and f.d >= v_gp_from), 0) as sales_costed,
                coalesce(sum(f.amount) filter (where f.src = 'credit' and f.d >= v_gp_from), 0) as credits_costed,
                coalesce(sum(f.amount) filter (where f.src = 'sale' and not f.costed and f.d >= v_gp_from), 0) as uncosted,
                coalesce(sum(f.amount) filter (where f.okind is not null), 0) as other_amt, count(*) filter (where f.okind is not null) as other_n, coalesce(sum(f.amount) filter (where f.inv), 0) as inv_amt
           from f group by f.gkey, f.customer_id, f.okind),
  g as (select a.gkey, sum(a.sales) as sales, sum(a.credits) as credits, sum(a.qty) as qty, sum(a.qty_credited) as qty_credited, sum(a.cogs) as cogs, sum(a.cogs_unmatched) as cogs_unmatched,
               sum(a.sales_costed) as sales_costed, sum(a.credits_costed) as credits_costed, sum(a.uncosted) as uncosted
          from ga a where a.gkey is not null group by a.gkey),
  gr as (select g.*, row_number() over (order by (case when v_group = 'month' then g.gkey end), (case when v_group <> 'month' then g.sales - g.credits end) desc nulls last, g.gkey) as rn from g),
  rows_j as (select coalesce(jsonb_agg(
               jsonb_build_object('key', case when v_group = 'customer' then coalesce((select c.name from public.customer c where c.id::text = gr.gkey), gr.gkey) else gr.gkey end)
               || case when v_group = 'sku' then jsonb_build_object('name', (select p.name from public.product p where upper(p.sku) = gr.gkey limit 1)) else '{}'::jsonb end
               || public.mcp_sales_cell(gr.sales, gr.credits, gr.qty, gr.qty_credited, gr.cogs, gr.sales_costed, gr.credits_costed, gr.uncosted, v_cost, v_gp_from is not null)
               || case when v_group = 'customer' and (select count(*) from ga where ga.gkey = gr.gkey) > 1
                       then jsonb_build_object('accounts', (select jsonb_agg(jsonb_build_object('name', (select c.name from public.customer c where c.id = a.customer_id))
                                                                             || public.mcp_sales_cell(a.sales, a.credits, a.qty, a.qty_credited, a.cogs, a.sales_costed, a.credits_costed, a.uncosted, v_cost, v_gp_from is not null)
                                                                             order by a.sales - a.credits desc)
                                                             from ga a where a.gkey = gr.gkey))
                       else '{}'::jsonb end
               order by gr.rn), '[]'::jsonb) as j from gr where gr.rn <= v_limit),
  trunc as (select count(*) as n, coalesce(sum(gr.sales - gr.credits), 0) as net from gr where gr.rn > v_limit),
  -- ⑥ 표 밖(925 · 926 · 이견 7 ~ 9 · 11) — 오더 단위 · brand · sku · supplier 거르기 없을 때만(f 가 이미 손님 거르기를 했다) · invoice_total_pretax = inv 줄 전부(제품 포함)
  oth as (select coalesce(sum(a.other_amt) filter (where a.okind = 'freight'), 0) as freight, coalesce(sum(a.other_amt) filter (where a.okind = 'services'), 0) as services,
                 coalesce(sum(a.other_amt) filter (where a.okind = 'order_discount'), 0) as order_discount, coalesce(sum(a.other_amt) filter (where a.okind = 'adjustments'), 0) as adjustments,
                 coalesce(sum(a.inv_amt), 0) as invoice_total_pretax, coalesce(sum(a.other_amt) filter (where a.okind = 'other_credit'), 0) as other_credits,
                 coalesce(sum(a.other_n) filter (where a.okind = 'non_cad'), 0) as non_cad_n, coalesce(sum(a.other_amt) filter (where a.okind = 'non_cad'), 0) as non_cad_amt
            from ga a),
  srcn as (select (select min(h.invoice_date) from public.hist_so h) as h0, (select max(h.invoice_date) from public.hist_so h) as h1,
                  (select min(i.issued_on) from public.so_invoice i where i.kind = 'sale' and i.status = 'issued') as i0)
  select jsonb_build_object(
           'period', jsonb_build_object('from', v_from, 'to', v_to), 'group', v_group, 'filters', v_filters,
           'rows', (select j from rows_j),
           'totals', (select public.mcp_sales_cell(sum(g.sales), sum(g.credits), sum(g.qty), sum(g.qty_credited), sum(g.cogs), sum(g.sales_costed), sum(g.credits_costed), sum(g.uncosted), v_cost, v_gp_from is not null)
                             || case when v_cost then jsonb_build_object('cogs_unmatched', case when v_gp_from is not null then round(coalesce(sum(g.cogs_unmatched), 0), 2) end) else '{}'::jsonb end from gr g),
           'source_note', (select 'Cin7 history: invoice dates ' || coalesce(s.h0::text, '(none)') || ' to ' || coalesce(s.h1::text, '(none)') || ' · IMS invoices from ' || coalesce(s.i0::text, '(none yet)')
                                  || ' · costs recorded from ' || c_cost_from::text || ' · amounts CAD before tax · product lines only (freight, services, order discounts and adjustments are under "other") · sales by invoice date, credits by credit date · totals are computed by IMS'
                             from srcn s))
         || case when (select t.n from trunc t) > 0 then jsonb_build_object('rows_truncated', (select jsonb_build_object('rows', t.n, 'net', round(t.net, 2)) from trunc t)) else '{}'::jsonb end
         || case when v_other_ok then jsonb_build_object('other', (select jsonb_build_object('freight', round(o.freight, 2), 'services', round(o.services, 2), 'order_discount', round(o.order_discount, 2), 'adjustments', round(o.adjustments, 2),
                                                                                      'invoice_total_pretax', round(o.invoice_total_pretax, 2), 'other_credits', round(o.other_credits, 2),
                                                                                      'excluded_non_cad', jsonb_build_object('count', o.non_cad_n, 'amount', round(o.non_cad_amt, 2))) from oth o))
                 else jsonb_build_object('other_note', 'Freight, services, order discounts and adjustments are order-level and are shown only when not filtering by brand, SKU or supplier') end
         || case when v_cost then jsonb_build_object('gp_from', v_gp_from) else '{}'::jsonb end
    into v_res;
  return v_res;
end;
$$;
comment on function public.mcp_sales(text, text, text, text, text, text, text, int) is 'mcp-1b 도구 ⑥(918 ~ 920 · 923 · 925 ~ 930): 기간(text YYYY-MM-DD · ≤ 3 년) × 묶음(brand · customer · month · sku · supplier) · 거르기(이름 → 유일 · 못 풀면 {resolved:false, candidates}) · rows{key, sales, credits, net, qty, qty_credited[, cogs, gp, gp_pct, net_costed, uncosted_sales][, name][, accounts]} 순매출 큰 순(month 는 날짜순) · totals(+ cogs_unmatched) · rows_truncated · other(오더 단위 · brand · sku · supplier 거르기 없을 때만) · gp_from · source_note — 원가 열쇠(ims_can_view_cost)가 없으면 cogs · gp · gp_pct · net_costed · uncosted_sales · cogs_unmatched · gp_from 열쇠 자체가 없다 · 연락처 · 메모 없음 · 문 sales';

-- ═══ 권한 — 도구 ⑥ 는 ims_connector 만 · 도우미는 아무에게도 · hist_line_kind 는 전처럼(authenticated 그대로 · PUBLIC 없음) ═══
revoke all on function public.mcp_sales(text, text, text, text, text, text, text, int), public.mcp_name_pick(text, text),
                       public.mcp_sales_cell(numeric, numeric, numeric, numeric, numeric, numeric, numeric, numeric, boolean, boolean)
  from public, anon, authenticated, service_role, ims_connector;
grant execute on function public.mcp_sales(text, text, text, text, text, text, text, int) to ims_connector;
revoke execute on function public.hist_line_kind(text) from public;

-- ═══ 착지 검사 ═══
do $$
declare v text; v_n int;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE');
  if v_n <> 0 then raise exception 'mcp-1b landing: PUBLIC EXECUTE still on % public functions', v_n; end if;
  select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_sales', 'mcp_name_pick', 'mcp_sales_cell');
  if v <> 'mcp_name_pick={postgres=X/postgres} mcp_sales={postgres=X/postgres,ims_connector=X/postgres} mcp_sales_cell={postgres=X/postgres}' then raise exception 'mcp-1b landing: acl %', v; end if;
  select p.proconfig::text into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'hist_line_kind';
  if v is not null then raise exception 'mcp-1b landing: hist_line_kind still has SET %', v; end if;
  if md5((select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'hist_line_kind')) <> 'c098f08cc8a0d588d1cb87836d257c2d' then raise exception 'mcp-1b landing: hist_line_kind body changed'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') <> 1 then raise exception 'mcp-1b landing: mcp_sales count'; end if;
  raise notice 'mcp-1b landing OK — PUBLIC EXECUTE 0 · mcp_sales acl(ims_connector) · 도우미 acl(postgres 만) · hist_line_kind SET 없음 · 본문 md5 그대로';
end $$;
