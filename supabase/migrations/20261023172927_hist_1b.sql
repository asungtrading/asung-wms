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

-- ═══ hist-1b — hist_so_load 가 REST 로 부르면 서는 결함 고침 (2026-10-23 · 실사고 13:22 · hist_so_load 400 · 21000 "DELETE requires a WHERE clause") ═══
--   까닭: REST 연결의 역할 authenticator 가 session_preload_libraries=supautils, safeupdate 를 싣는다(테스트 DB rolconfig 원문) · 창구 안 임시 표 비우기 `delete from hist_so_ld;`(hist_1 166 행)가 WHERE 가 없어 걸렸다
--        psql 직결 시험(hist-1)은 그 장치를 거치지 않아 통과했다 · 이 셸에서는 load · PGOPTIONS 가 막혀 재현을 못 했다 — 재현은 실사고 로그로 선 것으로 본다(대화 Claude 판단)
--   고침: 그 한 줄을 `truncate hist_so_ld;` 로 — 임시 표는 세션 전용이라 잠금이 남에게 안 미치고 TRUNCATE 는 safeupdate 검사(DELETE · UPDATE) 밖 · 다른 줄은 바이트 그대로 · create or replace(서명 같음 · grant · comment 유지 — 착지가 확인)
--   ⚠️ inv_layer_apply 의 WHERE 없는 delete 둘(inv_layer_consume · inv_layer_cost_add · psql 전용 · REST 로 부르면 같은 21000)은 이 차수 밖 — 따로 판정
CREATE OR REPLACE FUNCTION public.hist_so_load(p_orders jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- hist-1: Apps Script 가 쪽(≤ 500 오더)으로 부른다 · p_orders = [{order_number!, era?, source!, cin7_customer_id?, customer_name?, order_date?, invoice_date?, invoice_number?, location?, currency?,
--   lines!: [{doc_type?(invoice | credit · 'Invoice' · 'Credit note' 도 받는다), doc_number?, doc_date?, sku!, product_name?, brand?, quantity!, sale?, discount?, tax?, total?}]}]
--   ① 풀기 customer.cin7_id · product.sku 정확 → upper ② 거르기 — 줄의 doc_date(없으면 오더 invoice_date)가 ims_today() 뒤면 그 줄을 빼고 셈 · 줄이 하나도 안 남으면 오더도 안 넣음(659) · order_number 가 IMS so.so_number 와 같으면 안 넣음
--   ③ 머리 upsert on (era, order_number) · 줄은 지우고 다시 넣는다(멱등) ④ 합 · line_count · has_return · unit_price 는 여기서 셈 · ⚠️ 원장 · 원가 · so(번호 겹침 읽기 하나) · 크레딧 어느 표도 쓰지 않는다
declare
  v_today date := public.ims_today();
  o jsonb;  v_on text;  v_era text;  v_src text;  v_cid uuid;  v_cust uuid;  v_id uuid;  v_isnew boolean;
  v_inv_date date;  v_inv_no text;  v_n int;
  c_in int := 0;  c_ins int := 0;  c_upd int := 0;  c_fut int := 0;  c_ims int := 0;  l_in int := 0;  l_w int := 0;  l_fut int := 0;  c_unres int := 0;  p_unres int := 0;
begin
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' then raise exception 'p_orders must be a JSON array of orders — nothing was saved'; end if;
  if jsonb_array_length(p_orders) > 500 then raise exception 'Too many orders in one call (% — the limit is 500) — send pages of 500 — nothing was saved', jsonb_array_length(p_orders); end if;
  if to_regclass('pg_temp.hist_so_ld') is null then                                                                        -- 쪽마다 한 번(NOTICE 없이) · 트랜잭션 끝에 사라진다
    create temp table hist_so_ld (seq int, doc_type text, doc_number text, doc_date date, sku text, product_id uuid, product_name text, brand text, quantity numeric, sale numeric, discount numeric, tax numeric, total numeric, fut boolean) on commit drop;
  end if;
  for o in select x from jsonb_array_elements(p_orders) as x loop
    c_in := c_in + 1;
    v_on := nullif(trim(coalesce(o->>'order_number', '')), '');
    if v_on is null then raise exception 'Order % has no order_number — nothing was saved', c_in; end if;
    v_era := coalesce(nullif(trim(o->>'era'), ''), 'core');
    if v_era <> 'core' then raise exception 'Order %: era % is not known (core) — nothing was saved', v_on, v_era; end if;
    v_src := nullif(trim(coalesce(o->>'source', '')), '');
    if v_src is null or v_src not in ('bq_confirmed', 'bq_current') then raise exception 'Order %: source must be bq_confirmed or bq_current — nothing was saved', v_on; end if;
    if jsonb_typeof(o->'lines') <> 'array' or jsonb_array_length(o->'lines') = 0 then raise exception 'Order % has no lines — nothing was saved', v_on; end if;
    l_in := l_in + jsonb_array_length(o->'lines');
    if exists (select 1 from public.so s where s.so_number = v_on) then c_ims := c_ims + 1; continue; end if;    -- IMS 번호와 겹침(실측 0 · 안전장치)
    v_inv_date := nullif(o->>'invoice_date', '')::date;
    -- 줄 펴기 · 풀기 · 미래 거르기
    truncate hist_so_ld;                                                                     -- hist-1b: WHERE 없는 delete 는 REST(authenticator 가 safeupdate 를 싣는다)에서 21000 — 임시 표는 truncate(세션 전용 · safeupdate 검사 밖)
    insert into hist_so_ld (seq, doc_type, doc_number, doc_date, sku, product_id, product_name, brand, quantity, sale, discount, tax, total, fut)
    select t.o,
           case lower(trim(coalesce(l->>'doc_type', 'invoice'))) when 'credit' then 'credit' when 'credit note' then 'credit' else 'invoice' end,
           nullif(trim(l->>'doc_number'), ''), coalesce(nullif(l->>'doc_date', '')::date, v_inv_date),
           trim(l->>'sku'),
           coalesce((select p.id from public.product p where p.sku = trim(l->>'sku')), (select p.id from public.product p where upper(p.sku) = upper(trim(l->>'sku')) order by p.sku limit 1)),
           nullif(trim(l->>'product_name'), ''), nullif(trim(l->>'brand'), ''),
           nullif(l->>'quantity', '')::numeric, nullif(l->>'sale', '')::numeric, nullif(l->>'discount', '')::numeric, nullif(l->>'tax', '')::numeric, nullif(l->>'total', '')::numeric,
           coalesce(nullif(l->>'doc_date', '')::date, v_inv_date) > v_today
      from jsonb_array_elements(o->'lines') with ordinality as t(l, o);
    if exists (select 1 from hist_so_ld where sku is null or sku = '' or quantity is null) then raise exception 'Order %: every line needs sku and quantity — nothing was saved', v_on; end if;
    select count(*) filter (where fut) into v_n from hist_so_ld;
    l_fut := l_fut + v_n;
    delete from hist_so_ld where fut;
    if not exists (select 1 from hist_so_ld) then c_fut := c_fut + 1; continue; end if;   -- 판정 659: 미래 날짜뿐이면 오더도 안 넣는다
    v_cid := nullif(o->>'cin7_customer_id', '')::uuid;
    v_cust := (select c.id from public.customer c where c.cin7_id = v_cid);
    if v_cust is null then c_unres := c_unres + 1; end if;
    select count(*) into v_n from hist_so_ld where product_id is null;  p_unres := p_unres + v_n;
    if v_inv_date is null then select min(doc_date) into v_inv_date from hist_so_ld where doc_type = 'invoice'; end if;
    v_inv_no := coalesce(nullif(trim(o->>'invoice_number'), ''), (select doc_number from hist_so_ld where doc_type = 'invoice' and doc_number is not null order by seq limit 1));
    -- 머리 upsert
    select h.id into v_id from public.hist_so h where h.era = v_era and h.order_number = v_on;
    v_isnew := v_id is null;
    if v_isnew then
      insert into public.hist_so (era, order_number, cin7_customer_id, customer_id, customer_name, order_date, invoice_date, invoice_number, location, currency, source)
      values (v_era, v_on, v_cid, v_cust, nullif(trim(o->>'customer_name'), ''), nullif(o->>'order_date', '')::date, v_inv_date, v_inv_no, nullif(trim(o->>'location'), ''), nullif(trim(o->>'currency'), ''), v_src)
      returning id into v_id;
      c_ins := c_ins + 1;
    else
      update public.hist_so set cin7_customer_id = v_cid, customer_id = v_cust, customer_name = nullif(trim(o->>'customer_name'), ''), order_date = nullif(o->>'order_date', '')::date, invoice_date = v_inv_date, invoice_number = v_inv_no,
             location = nullif(trim(o->>'location'), ''), currency = nullif(trim(o->>'currency'), ''), source = v_src, loaded_at = now() where id = v_id;
      c_upd := c_upd + 1;
    end if;
    delete from public.hist_so_line where hist_so_id = v_id;
    insert into public.hist_so_line (hist_so_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, brand, quantity, unit_price, sale, discount, tax, total, is_return)
    select v_id, seq, doc_type, doc_number, doc_date, sku, product_id, product_name, brand, quantity, case when quantity <> 0 and sale is not null then round(sale / quantity, 6) end, sale, discount, tax, total, doc_type = 'credit'
      from hist_so_ld order by seq;
    get diagnostics v_n = row_count;  l_w := l_w + v_n;
    update public.hist_so h set sale_total = s.sa, tax_total = s.tx, total = s.tt, line_count = s.n, has_return = s.r
      from (select sum(sale) sa, sum(tax) tx, sum(total) tt, count(*) n, bool_or(is_return) r from public.hist_so_line where hist_so_id = v_id) s where h.id = v_id;
  end loop;
  return jsonb_build_object('orders_in', c_in, 'orders_inserted', c_ins, 'orders_updated', c_upd, 'orders_skipped_future', c_fut, 'orders_skipped_ims_number', c_ims,
                            'lines_in', l_in, 'lines_written', l_w, 'lines_skipped_future', l_fut, 'customer_unresolved', c_unres, 'product_unresolved', p_unres);
end $function$;

-- ═══ 착지 — 몸 md5 · delete 없음 · truncate 있음 · ACL · comment 그대로 ═══
do $$
declare v_acl text;  v_cmt text;  v_src text;
begin
  select md5(p.prosrc), p.proacl::text, obj_description(p.oid, 'pg_proc'), p.prosrc into strict v_src, v_acl, v_cmt, v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'hist_so_load';
  if md5(v_src) <> '61ec800f2fa25698ce478cb05dc56d85' then raise exception 'hist-1b landing check failed: body'; end if;
  if v_src ~ '\n\s*delete from hist_so_ld\s*;' or v_src !~ '\n\s*truncate hist_so_ld\s*;' then raise exception 'hist-1b landing check failed: delete still there / truncate missing'; end if;
  if v_acl <> '{postgres=X/postgres,service_role=X/postgres}' then raise exception 'hist-1b landing check failed: acl %', v_acl; end if;
  if v_cmt is null or v_cmt not like 'hist-1 판정 659 · 660%' then raise exception 'hist-1b landing check failed: comment'; end if;
end $$;
