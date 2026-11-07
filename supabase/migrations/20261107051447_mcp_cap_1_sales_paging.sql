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
-- mcp-cap-1 — 커넥터 판매 집계 mcp_sales 에 쪽 넘기기(p_offset) + limit 상한 500 · 시그니처가 바뀌어 drop → create (2026-11-07 UTC · 지시서 ~/asung/prompts/mcp-cap-1.md · 이견 1 ~ 9 답 반영 · 조사 mcp-cap-0)
--   무엇: p_offset int default 0(음수 거부 · 끝을 넘으면 빈 쪽) · p_limit 1 ~ 500(기본 50 그대로) · 응답에 page{offset, limit, shown, total_rows, next_offset} · rows_truncated{rows, net} = 이 쪽에 안 보인 줄 전부(앞 + 뒤 · offset 0 이면 지금까지와 같은 뜻 · 보이는 줄 net 합 + rows_truncated.net = totals.net 이 모든 쪽에서 — 925) · totals · other · gp_from · source_note 는 쪽과 상관없이 전체(무변)
--   이견 1: 정렬 열쇠는 이미 유일(gr 의 마지막 열쇠 gkey · g 가 gkey 로 묶는다) — 덧붙이지 않았다 · 이견 2: rows_before 없음 · 「next_offset 이 null 이 아니면 이어 불러라」 · 이견 3: limit 500 이 늘리는 줄마다 비용 둘을 질의 안에서 — customer 이름 c.id = gkey::uuid(text 비교는 pk 색인을 못 탔다) · 계정 수는 g 에서 count(*) · accounts 는 ga 를 쪽의 gkey 로 한 번 묶어 조인(줄마다 ga 두 번 훑기 없음)
--   무변: 919 · 923 원가 칸 · 묶는 기준 다섯(930) · 집계 · 거르기 · other · hist_line_kind · mcp_name_pick · mcp_sales_cell · mcp_gate · 권한(ims_connector EXECUTE 만 · PUBLIC 0) · work_mem 32MB · search_path
--   ⚠️ drop → create → grant: 옛 시그니처(…, int) 판이 남으면 PostgREST 이름 호출이 ambiguous(300) — 착지 검사가 한 벌인지 센다 · 새 판은 p_offset 기본 0 이라 옛 EF(p_offset 없이 호출)도 받는다 ⇒ DB 먼저 · EF 나중
--   적용(Caleb · IMS 메인 fazgmyvzzhqybtvtktyg): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '2s'" -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=<이 파일> psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_cap_1_check.sql

-- ═══ 0) 바탕 확인 — 지금 mcp_sales 가 mcp-1b 판(20261101014251 · 본문 md5 fa78acc11d3b9d00c8b0b618ad1bd664) 한 벌인지 · 아니면 멈춘다(diff 의 바탕이 다르다) ═══
do $$
declare v_n int; v_md5 text;
begin
  select count(*), min(md5(p.prosrc)) into v_n, v_md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales';
  if v_n <> 1 or v_md5 <> 'fa78acc11d3b9d00c8b0b618ad1bd664' then
    raise exception 'mcp-cap-1: mcp_sales is not the single mcp-1b version (count %, md5 %) — stop, nothing was changed', v_n, coalesce(v_md5, '(none)');
  end if;
end $$;

-- ═══ A) drop → create(새 시그니처 … p_limit int, p_offset int) — 본문은 mcp-1b 원본에서 의도한 줄만(diff 는 보고에) ═══
drop function public.mcp_sales(text, text, text, text, text, text, text, int);
create function public.mcp_sales(p_from text, p_to text, p_group text, p_brand text default null, p_customer text default null, p_sku text default null, p_supplier text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp set work_mem = '32MB'   -- 32MB: 해시 집계 · 해시 조인이 디스크로 안 넘치게(기본 3.5MB · 머리 주석의 실측)
as $$
declare
  c_cost_from constant date := '2026-08-21';                                           -- 판정 928: 원가 기록 시작(inv_layer_consume sale_out 첫 날 · 시험이 실물로 단언)
  v_from date; v_to date; v_gp_from date;
  v_group text := lower(btrim(coalesce(p_group, '')));
  v_limit int := coalesce(p_limit, 50);
  v_offset int := coalesce(p_offset, 0);                                               -- mcp-cap-1: 쪽 넘기기(rn 이 v_offset 보다 큰 줄부터 v_limit 개)
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
  if v_limit < 1 or v_limit > 500 then raise exception 'limit must be between 1 and 500 — nothing was read'; end if;
  if v_offset < 0 then raise exception 'offset must be 0 or more — nothing was read'; end if;
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
               sum(a.sales_costed) as sales_costed, sum(a.credits_costed) as credits_costed, sum(a.uncosted) as uncosted, count(*) as n_acct   -- n_acct: 묶음의 계정 수(ga 는 gkey × customer_id · 표 안 줄은 okind null · mcp-cap-1 이견 3)
          from ga a where a.gkey is not null group by a.gkey),
  gr as (select g.*, row_number() over (order by (case when v_group = 'month' then g.gkey end), (case when v_group <> 'month' then g.sales - g.credits end) desc nulls last, g.gkey) as rn from g),
  -- 이 쪽(mcp-cap-1 · 이견 2 · 3): rn 이 v_offset 보다 큰 줄부터 v_limit 개 · customer 이름은 uuid 로(gkey::text 비교는 pk 색인을 못 탄다) · 계정 묶음은 ga 를 쪽의 gkey 로 한 번 묶어 조인(줄마다 ga 를 훑지 않는다)
  pg as (select gr.*, case when v_group = 'customer' and gr.gkey ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then gr.gkey::uuid end as gid
           from gr where gr.rn > v_offset and gr.rn <= v_offset + v_limit),
  acc as (select a.gkey, jsonb_agg(jsonb_build_object('name', c.name)
                                   || public.mcp_sales_cell(a.sales, a.credits, a.qty, a.qty_credited, a.cogs, a.sales_costed, a.credits_costed, a.uncosted, v_cost, v_gp_from is not null)
                                   order by a.sales - a.credits desc) as j
            from ga a join pg on pg.gkey = a.gkey left join public.customer c on c.id = a.customer_id
           where v_group = 'customer' and pg.n_acct > 1 group by a.gkey),
  rows_j as (select coalesce(jsonb_agg(
               jsonb_build_object('key', case when v_group = 'customer' then coalesce(cn.name, pg.gkey) else pg.gkey end)
               || case when v_group = 'sku' then jsonb_build_object('name', (select p.name from public.product p where upper(p.sku) = pg.gkey limit 1)) else '{}'::jsonb end
               || public.mcp_sales_cell(pg.sales, pg.credits, pg.qty, pg.qty_credited, pg.cogs, pg.sales_costed, pg.credits_costed, pg.uncosted, v_cost, v_gp_from is not null)
               || case when acc.j is not null then jsonb_build_object('accounts', acc.j) else '{}'::jsonb end
               order by pg.rn), '[]'::jsonb) as j, count(*) as shown
               from pg left join public.customer cn on cn.id = pg.gid left join acc on acc.gkey = pg.gkey),
  -- 쪽 정보 · 안 보인 줄(앞 + 뒤 · 925 항등식: 보이는 줄 net 합 + rows_truncated.net = totals.net 이 모든 쪽에서 선다 · offset 0 이면 지금까지와 같은 뜻)
  pagei as (select r.shown, t.n as total, case when v_offset + r.shown < t.n then v_offset + r.shown end as next_offset from rows_j r, (select count(*) as n from gr) t),
  trunc as (select count(*) as n, coalesce(sum(gr.sales - gr.credits), 0) as net from gr where gr.rn <= v_offset or gr.rn > v_offset + v_limit),
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
           'page', (select jsonb_build_object('offset', v_offset, 'limit', v_limit, 'shown', p.shown, 'total_rows', p.total, 'next_offset', p.next_offset) from pagei p),
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
comment on function public.mcp_sales(text, text, text, text, text, text, text, int, int) is 'mcp-1b 도구 ⑥(918 ~ 920 · 923 · 925 ~ 930) + mcp-cap-1 쪽 넘기기(2026-11-07): 기간(text YYYY-MM-DD · ≤ 3 년) × 묶음(brand · customer · month · sku · supplier) · 거르기(이름 → 유일 · 못 풀면 {resolved:false, candidates}) · p_limit 1 ~ 500(기본 50) · p_offset ≥ 0(기본 0 · 끝을 넘으면 빈 쪽) · rows{key, sales, credits, net, qty, qty_credited[, cogs, gp, gp_pct, net_costed, uncosted_sales][, name][, accounts]} 순매출 큰 순(month 는 날짜순 · 같으면 key 순 · 쪽 사이에 흔들리지 않는다) · page{offset, limit, shown, total_rows, next_offset(남은 줄이 없으면 null)} · totals(+ cogs_unmatched) · other · gp_from · source_note 는 쪽과 상관없이 전체 · rows_truncated{rows, net} = 이 쪽에 안 보인 줄 전부(앞 + 뒤 · 보이는 줄 net 합 + rows_truncated.net = totals.net) · next_offset 이 null 이 아니면 그 값을 p_offset 으로 이어 부른다 — 원가 열쇠(ims_can_view_cost)가 없으면 cogs · gp · gp_pct · net_costed · uncosted_sales · cogs_unmatched · gp_from 열쇠 자체가 없다 · 연락처 · 메모 없음 · 문 sales';

-- ═══ 권한 — 옛 판과 같게: ims_connector 만 EXECUTE · PUBLIC · anon · authenticated · service_role 없음 ═══
revoke all on function public.mcp_sales(text, text, text, text, text, text, text, int, int) from public, anon, authenticated, service_role, ims_connector;
grant execute on function public.mcp_sales(text, text, text, text, text, text, text, int, int) to ims_connector;

-- ═══ 착지 검사 — 한 벌 · 새 시그니처 · acl 글자 그대로(= PUBLIC 없음) · SET 그대로 ═══
--   ⚠️ 1b 의 「public 함수 전체 PUBLIC EXECUTE 0」 은 이제 안 선다 — 11-07 실측 inv_transfer_line_combo_parent_check(트리거 함수 · 이 차수 밖)에 PUBLIC EXECUTE 가 있다 ⇒ 여기서는 mcp_sales 만 본다
do $$
declare v text; v_n int;
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales') <> 1 then raise exception 'mcp-cap-1 landing: mcp_sales count <> 1'; end if;
  select pg_get_function_identity_arguments(p.oid) into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales';
  if v <> 'p_from text, p_to text, p_group text, p_brand text, p_customer text, p_sku text, p_supplier text, p_limit integer, p_offset integer' then raise exception 'mcp-cap-1 landing: signature %', v; end if;
  select p.proacl::text || ' ' || p.prosecdef::text || p.provolatile::text || coalesce(p.proconfig::text, '-') into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales';
  if v <> '{postgres=X/postgres,ims_connector=X/postgres} trues{"search_path=public, pg_temp",work_mem=32MB}' then raise exception 'mcp-cap-1 landing: acl/config %', v; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'mcp_sales' and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE');
  if v_n <> 0 then raise exception 'mcp-cap-1 landing: PUBLIC EXECUTE on mcp_sales'; end if;
  raise notice 'mcp-cap-1 landing OK — mcp_sales 한 벌 · (…, p_limit integer, p_offset integer) · acl ims_connector 만 · PUBLIC 없음 · SET 그대로';
end $$;
