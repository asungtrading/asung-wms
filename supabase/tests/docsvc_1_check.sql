-- docsvc-1 검증 — supabase/migrations/20261114125023_docsvc_1_service_lines_apart.sql (서비스 줄을 문서에서 운임과 따로 · 판정 1221 ~ 1228 · 지시서 ~/asung/prompts/docsvc-1.md 「지을 것」 5 · crtax_1_check.sql 과 같은 장치)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261114125023_docsvc_1_service_lines_apart.sql -f supabase/tests/docsvc_1_check.sql
--   확인(적용 뒤 · 사람): 같은 명령에서 -v mig=… 만 뺀다 — 「옛 = 새」 전후 대조는 건너뛴다(옛 출력이 없다) · 나머지(새 열쇠 값 · 불변식 · 가상 건)는 그대로 돈다
--   ⚠️ 실제 행 무변: 끝은 rollback · 쓰기는 가상 서비스 줄 하나(packed 오더의 so_charge · line_no 99)뿐 — rollback 으로 사라진다 · 번호 시퀀스 무접촉(미리 보기만 · 발행 없음)
--   ⚠️ 잠금: 함수 여섯의 create or replace(표 잠금 없음) + 가상 so_charge 한 줄의 행 잠금 · lock_timeout 3 s · 시작 전 활성 세션 확인(토요일 · Caleb 2026-11-14 답 13)
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- ── 머리(읽기) — 직원 신원 · 견줄 실물 ──
select
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff,
  (select i.id::text from public.so_invoice i where i.invoice_number = '60513') as inv_mix,                                                                                     -- SO-21445 · 제품 6 + FINAL-SALE 1
  (select i.id::text from public.so_invoice i where i.invoice_number = '60471') as inv_svc,                                                                                     -- 서비스 오더 · 서비스 줄 5 · 제품 0
  (select i.id::text from public.so_invoice i where i.kind <> 'opening' and i.status = 'issued'
      and exists (select 1 from public.so_invoice_line l join public.so_charge c on c.id = l.so_charge_id where l.invoice_id = i.id and l.kind = 'charge' and c.service_id is null and btrim(coalesce(c.description, '')) <> '')
      and not exists (select 1 from public.so_invoice_line l join public.so_charge c on c.id = l.so_charge_id where l.invoice_id = i.id and c.service_id is not null)
    order by i.invoice_number desc limit 1) as inv_prod,                                                                                                                         -- 제품 + 설명 있는 운임 · 서비스 0
  (select i.id::text from public.so_invoice i where i.kind = 'opening' and i.status = 'issued' order by i.invoice_number desc limit 1) as inv_open,
  (select s.id::text from public.so s where s.status = 'packed' order by s.updated_at desc limit 1) as so_sr,
  (select rc.id::text from public.ref_carrier rc where rc.is_active and rc.kind = 'pickup' order by rc.name limit 1) as car,
  (select rs.id::text from public.ref_service rs where not rs.final_sale and rs.is_active and exists (select 1 from public.so_charge c where c.service_id = rs.id) order by rs.name limit 1) as svc,
  (select count(*) from jsonb_array_elements_text(public.doc_field_catalog('final_invoice')->'allowed') a where a = 'services_title')::int as applied_head,
  (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) || '/' || (select last_value::text from public.so_credit_number_seq) as seq_head,
  (select count(*)::text from public.so_charge) as chg_head,
  (select md5(string_agg(p.proname || md5(p.prosrc), ',' order by p.proname)) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('so_detail', 'doc_data', 'doc_data_so', 'doc_data_credit', 'doc_data_common', 'doc_qty_totals', 'so_tax_preview', 'so_invoice_issue', 'so_finalize', 'qbo_invoice_body', 'qbo_credit_body', 'mcp_order', 'mcp_sales', 'doc_template_check')) as untouched_head,
  (select md5(string_agg(p.proname || coalesce(p.proacl::text, '') || p.prosecdef::text || p.provolatile::text, ',' order by p.proname)) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('doc_data_invoice', 'doc_data_invoice_fmt', 'so_invoice_preview', 'doc_field_catalog', 'so_invoice_detail', 'so_credit_prepare')) as acl_head,
  (select md5(string_agg(t.id::text || md5(t.body), ',' order by t.id)) from public.doc_template t) as tpl_head \gset
select 'head: applied ' || :applied_head || ' · seq(so/inv/cr) ' || :'seq_head' || ' · so_charge ' || :'chg_head' || ' · staff ' || left(:'staff', 8) || ' · mix ' || left(:'inv_mix', 8) || ' · svc ' || left(:'inv_svc', 8)
       || ' · prod ' || left(:'inv_prod', 8) || ' · opening ' || left(:'inv_open', 8) || ' · packed so ' || left(:'so_sr', 8) || ' · pickup ' || left(:'car', 8) || ' · service ' || left(:'svc', 8)
       || ' · active sessions ' || (select count(*) from pg_stat_activity a where a.datname = current_database() and a.backend_type = 'client backend' and a.pid <> pg_backend_pid() and a.state <> 'idle');

-- ── 도우미(begin 앞 · 잠금 구간 밖) ──
create temp table t_res (seq serial, tag text, ok boolean, detail text);
create temp table t_old (k text primary key, v text);
create temp table t_new (k text primary key, v text);
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 700)) $$;
-- 한 문장 → 글자 · 예외는 'ERR <sqlstate>: <문장>'
create function pg_temp.q(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  execute p_sql into v_out;
  return v_out;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.num(p text) returns numeric language sql as $$ select nullif(replace(p, ',', ''), '')::numeric $$;
-- 새 문서에서 docsvc-1 이 얹은 열쇠를 뺀다 → 옛 문서와 같아야 한다
create function pg_temp.strip(d jsonb) returns jsonb language sql as $$
  select case when d is null or jsonb_typeof(d) <> 'object' then d else
    jsonb_set(jsonb_set(d - array['services', 'freight_lines', 'services_title', 'has_services', 'has_freight_lines', 'has_product_lines', 'services_separate', 'services_as_main'],
                        '{totals}', (d->'totals') - array['services_before_tax', 'services_tax', 'services_total', 'freight_before_tax', 'freight_tax', 'freight_total', 'services_line_count', 'services_qty_total']),
              '{orders}', (select coalesce(jsonb_agg(o - 'has_lines' order by ord), '[]'::jsonb) from jsonb_array_elements(d->'orders') with ordinality t(o, ord))) end $$;
-- 견줄 출력 한 벌(옛 · 새가 같은 문장을 돈다) — p_t 는 't_old' · 't_new'
create function pg_temp.snap(p_t text, p_sr text, p_car text) returns void language plpgsql as $$
declare v_ref text := jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', p_sr, 'carrier_id', p_car, 'charges', jsonb_build_array(jsonb_build_object('name', 'Freight', 'amount', 25.00)))))::text;   -- 마무리 화면이 새 운임 25.00 을 더한 꼴(so.html finCollect) — packed 오더는 운임이 아직 없다
begin
  execute format($f$insert into %I (k, v)
    select 'fi:' || i.id, pg_temp.q(format('select (public.doc_data(''final_invoice'', jsonb_build_object(''invoice_id'', %%L))->''docs''->0)::text', i.id)) from public.so_invoice i
    union all select 'ir:' || i.id, pg_temp.q(format('select (public.doc_data(''internal_receipt'', jsonb_build_object(''invoice_id'', %%L))->''docs''->0)::text', i.id)) from public.so_invoice i
                where i.kind = 'opening' and i.id = (select max(o.id::text)::uuid from public.so_invoice o where o.kind = 'opening')
                   or i.kind <> 'opening' and (exists (select 1 from public.so_invoice_line l join public.so_charge c on c.id = l.so_charge_id where l.invoice_id = i.id and c.service_id is not null)
                                               or i.id in (select x.id from public.so_invoice x where x.kind <> 'opening' order by x.invoice_number desc limit 40))
    union all select 'cn:' || c.id, pg_temp.q(format('select public.doc_data(''credit_note'', jsonb_build_object(''credit_id'', %%L))::text', c.id)) from public.so_credit c
    union all select 'so:' || s.id, pg_temp.q(format('select public.doc_data(''sales_order'', jsonb_build_object(''so_id'', %%L))::text', s.id)) from (select s0.id from public.so s0 where s0.status in ('confirmed', 'packed', 'picking') order by s0.updated_at desc limit 40) s
    union all select 'cat:' || k, public.doc_field_catalog(k)::text from unnest(array['final_invoice', 'internal_receipt', 'ship_ready', 'credit_note', 'sales_order']) k
    union all select 'det:' || i.id, pg_temp.q(format('select public.so_invoice_detail(%%L)::text', i.id)) from public.so_invoice i where i.kind <> 'opening' or i.id in (select o.id from public.so_invoice o where o.kind = 'opening' order by o.invoice_number desc limit 20)
    union all select 'prep:' || i.id, pg_temp.q(format('select public.so_credit_prepare(%%L)::text', i.id)) from public.so_invoice i where i.kind <> 'opening' or i.id in (select o.id from public.so_invoice o where o.kind = 'opening' order by o.invoice_number desc limit 20)
    union all select 'sr', pg_temp.q(format('select public.doc_data(''ship_ready'', %%L::jsonb)::text', %L))
    union all select 'pv', pg_temp.q(format('select public.so_invoice_preview(%%L::jsonb->''orders'')::text', %L))$f$, p_t, v_ref, v_ref);
end $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
select set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', :'staff'), true) is not null as claims_set \gset
\if :{?mig}
  select pg_temp.snap('t_old', :'so_sr', :'car');
  \i :mig
\endif
select pg_temp.snap('t_new', :'so_sr', :'car');

create function pg_temp.run() returns void language plpgsql as $run$
declare
  c_mix  constant text := current_setting('docsvc.inv_mix');   c_svc constant text := current_setting('docsvc.inv_svc');  c_prod constant text := current_setting('docsvc.inv_prod');
  c_open constant text := current_setting('docsvc.inv_open');  c_sr  constant text := current_setting('docsvc.so_sr');    c_car  constant text := current_setting('docsvc.car');
  c_svcid constant text := current_setting('docsvc.svc');
  v_has_old boolean := exists (select 1 from t_old);
  d jsonb;  r text;  v_n bigint;  v_m bigint;  v_k bigint;  v_ref jsonb;  v_cid uuid;  v_cat jsonb;  v_cfg jsonb := public.doc_config();
  c_new_keys constant text[] := array['services_title', 'has_services', 'services_separate', 'services_as_main', 'has_product_lines', 'has_freight_lines', 'orders.has_lines', 'services.final_sale',
    'totals.services_before_tax', 'totals.services_tax', 'totals.services_total', 'totals.freight_before_tax', 'totals.freight_tax', 'totals.freight_total', 'totals.services_line_count', 'totals.services_qty_total',
    'services.no', 'services.so_number', 'services.code', 'services.description', 'services.comment', 'services.qty', 'services.unit_price', 'services.discount_pct', 'services.amount', 'services.tax_amount',
    'freight_lines.no', 'freight_lines.so_number', 'freight_lines.code', 'freight_lines.description', 'freight_lines.comment', 'freight_lines.qty', 'freight_lines.unit_price', 'freight_lines.discount_pct', 'freight_lines.amount', 'freight_lines.tax_amount'];
begin
  -- ═══ A 전수 — 발행 · 취소 인보이스 전부(이월 제외)의 final_invoice 자료 ═══
  select count(*), count(*) filter (where n.v like 'ERR%') into v_n, v_m from t_new n join public.so_invoice i on i.id::text = substr(n.k, 4) where n.k like 'fi:%' and i.kind <> 'opening';
  perform pg_temp.res('A1 전수 — 이월 아닌 인보이스 전부의 final_invoice 자료가 예외 없이 나온다', v_n > 400 and v_m = 0, format('docs %s · errors %s', v_n, v_m));
  if v_has_old then
    select count(*) filter (where pg_temp.strip(pg_temp.j(n.v)) is distinct from pg_temp.j(o.v)), count(*) filter (where pg_temp.j(n.v)->'charges' is distinct from pg_temp.j(o.v)->'charges' or (pg_temp.j(n.v)->'charges')::text <> (pg_temp.j(o.v)->'charges')::text),
           count(*) filter (where (select jsonb_agg(pg_temp.j(n.v)->'totals'->k order by k) from unnest(array['charges_before_tax', 'charges_tax', 'charges_total', 'charges_discount', 'before_tax', 'tax', 'total', 'line_count', 'qty_total', 'qty_total_ea', 'balance_due']) k)
                                   is distinct from (select jsonb_agg(pg_temp.j(o.v)->'totals'->k order by k) from unnest(array['charges_before_tax', 'charges_tax', 'charges_total', 'charges_discount', 'before_tax', 'tax', 'total', 'line_count', 'qty_total', 'qty_total_ea', 'balance_due']) k))
      into v_n, v_m, v_k from t_new n join t_old o on o.k = n.k where n.k like 'fi:%';
    perform pg_temp.res('A2 전후 전수 — 새 열쇠를 뺀 새 문서 = 옛 문서(final_invoice 전부 · 이월의 예외 글도)', v_n = 0 and (select count(*) from t_old o where o.k like 'fi:%') = (select count(*) from t_new n where n.k like 'fi:%'), format('differ %s of %s', v_n, (select count(*) from t_new n where n.k like 'fi:%')));
    perform pg_temp.res('A3 전후 전수 — charges[] 글자 그대로(jsonb 글 비교)', v_m = 0, format('differ %s', v_m));
    perform pg_temp.res('A4 전후 전수 — totals 의 charges_* 넷 · before_tax · tax · total · 수량 합계 셋 · balance_due 그대로', v_k = 0, format('differ %s', v_k));
  end if;
  select count(*) into v_n from t_new n cross join lateral (select pg_temp.j(n.v) as d) x
   where n.k like 'fi:%' and n.v not like 'ERR%'
     and not (pg_temp.num(x.d->'totals'->>'services_before_tax') + pg_temp.num(x.d->'totals'->>'freight_before_tax') = pg_temp.num(x.d->'totals'->>'charges_before_tax')
          and pg_temp.num(x.d->'totals'->>'services_tax') + pg_temp.num(x.d->'totals'->>'freight_tax') = pg_temp.num(x.d->'totals'->>'charges_tax')
          and pg_temp.num(x.d->'totals'->>'services_total') + pg_temp.num(x.d->'totals'->>'freight_total') = pg_temp.num(x.d->'totals'->>'charges_total')
          and jsonb_array_length(x.d->'services') + jsonb_array_length(x.d->'freight_lines') = jsonb_array_length(x.d->'charges')
          and pg_temp.num(x.d->'totals'->>'services_before_tax') = coalesce((select sum(pg_temp.num(s->>'amount')) from jsonb_array_elements(x.d->'services') s), 0)
          and pg_temp.num(x.d->'totals'->>'freight_before_tax') = coalesce((select sum(pg_temp.num(s->>'amount')) from jsonb_array_elements(x.d->'freight_lines') s), 0));
  perform pg_temp.res('A5 전수 불변식 — services + freight = charges(세전 · 세금 · 합 · 줄 수) · 소계 = 자기 줄 금액의 합', v_n = 0, format('broken %s', v_n));
  select count(*) into v_n from t_new n cross join lateral (select pg_temp.j(n.v) as d) x
   where n.k like 'fi:%' and n.v not like 'ERR%'
     and not (jsonb_typeof(x.d->'has_services') = 'boolean' and jsonb_typeof(x.d->'has_freight_lines') = 'boolean' and jsonb_typeof(x.d->'has_product_lines') = 'boolean' and jsonb_typeof(x.d->'services_separate') = 'boolean' and jsonb_typeof(x.d->'services_as_main') = 'boolean'
          and (x.d->>'has_services')::boolean = (jsonb_array_length(x.d->'services') > 0) and (x.d->>'has_freight_lines')::boolean = (jsonb_array_length(x.d->'freight_lines') > 0)
          and (x.d->>'has_product_lines')::boolean = (x.d->'totals'->>'line_count' <> '0')
          and (x.d->>'services_separate')::boolean = ((x.d->>'has_services')::boolean and (x.d->>'has_product_lines')::boolean)
          and (x.d->>'services_as_main')::boolean  = ((x.d->>'has_services')::boolean and not (x.d->>'has_product_lines')::boolean)
          and ((x.d->>'services_title') <> '') = (x.d->>'has_services')::boolean
          and not exists (select 1 from jsonb_array_elements(x.d->'orders') o where jsonb_typeof(o->'has_lines') <> 'boolean' or (o->>'has_lines')::boolean <> (o->>'line_count' <> '0') or (o->>'has_lines')::boolean <> (jsonb_array_length(o->'lines') > 0))
          and not exists (select 1 from jsonb_array_elements(x.d->'services') with ordinality s(s, ord) where s.s->>'no' <> s.ord::text or jsonb_typeof(s.s->'final_sale') <> 'boolean')
          and not exists (select 1 from jsonb_array_elements(x.d->'freight_lines') with ordinality s(s, ord) where s.s->>'no' <> s.ord::text or s.s ? 'final_sale'));
  perform pg_temp.res('A6 전수 표지 — 불리언은 진짜 JSON 불리언 · has_* = 배열 · 줄 수와 맞음 · separate / as_main 은 섞임 / 순수 · 제목은 서비스가 있을 때만 · orders[].has_lines · 번호 각자 1 부터', v_n = 0, format('broken %s', v_n));
  select coalesce(sum(jsonb_array_length(pg_temp.j(n.v)->'services')), 0), count(*) filter (where jsonb_array_length(pg_temp.j(n.v)->'services') > 0) into v_n, v_m from t_new n where n.k like 'fi:%' and n.v not like 'ERR%';
  select count(*), count(distinct l.invoice_id) into v_k, r from public.so_invoice_line l join public.so_charge c on c.id = l.so_charge_id where l.kind <> 'product' and c.service_id is not null;
  perform pg_temp.res('A7 전수 가름 — services[] 줄 수 · 서비스 있는 문서 수 = DB(so_invoice_line → so_charge.service_id)', v_n = v_k and v_m = r::bigint and v_k >= 12, format('docs say %s lines in %s docs · DB %s lines in %s invoices', v_n, v_m, v_k, r));
  -- 1227: 새 배열에는 「 — 메모」 로 끝나는 설명 + 같은 메모가 없다 · 비워진 줄 수 = DB 가 세는 「이름 — 설명」 줄 수 · charges[] 의 메모는 그대로
  select count(*) filter (where s.s->>'comment' <> '' and right(s.s->>'description', char_length(' — ' || (s.s->>'comment'))) = ' — ' || (s.s->>'comment')) into v_n
    from t_new n cross join lateral jsonb_array_elements((pg_temp.j(n.v)->'services') || (pg_temp.j(n.v)->'freight_lines')) s(s) where n.k like 'fi:%' and n.v not like 'ERR%';
  select count(*) filter (where s.s->>'comment' <> '' and right(s.s->>'description', char_length(' — ' || (s.s->>'comment'))) = ' — ' || (s.s->>'comment')),
         count(*) filter (where s.s->>'comment' <> '')
    into v_m, v_k from t_new n cross join lateral jsonb_array_elements(pg_temp.j(n.v)->'charges') s(s) where n.k like 'fi:%' and n.v not like 'ERR%';
  perform pg_temp.res('A8 전수 1227 — services[] · freight_lines[] 에 두 번 찍힐 메모 0 · charges[] 는 그대로 두 번(옛 판 무변) · 운임 줄도 함께(DB: 운임 108 + 서비스 2 이상)',
    v_n = 0 and v_m >= 110
    and v_m = (select count(*) from public.so_invoice_line l join public.so_charge c on c.id = l.so_charge_id where l.kind = 'charge' and btrim(coalesce(c.description, '')) <> '' and right(l.description, char_length(' — ' || c.description)) = ' — ' || c.description)
    and (select count(*) from t_new n cross join lateral jsonb_array_elements((pg_temp.j(n.v)->'services') || (pg_temp.j(n.v)->'freight_lines')) s(s) where n.k like 'fi:%' and n.v not like 'ERR%' and s.s->>'comment' <> '') = v_k - v_m,
    format('new arrays doubled %s · charges[] doubled %s of %s with a memo', v_n, v_m, v_k));

  -- ═══ B SO-21445(섞임 · 인보이스 60513) ═══
  d := pg_temp.j((select n.v from t_new n where n.k = 'fi:' || c_mix));
  perform pg_temp.res('B1 SO-21445 final_invoice — 「Final sale items」 · 섞임(separate) · 서비스 1 줄(수량 2 · 1.00 · 2.00 · final_sale true · 메모 한 번) · 운임 0',
    d->>'services_title' = 'Final sale items' and d->'services_separate' = 'true'::jsonb and d->'services_as_main' = 'false'::jsonb and d->'has_services' = 'true'::jsonb and d->'has_product_lines' = 'true'::jsonb and d->'has_freight_lines' = 'false'::jsonb
    and jsonb_array_length(d->'services') = 1 and jsonb_array_length(d->'freight_lines') = 0
    and d->'services'->0->>'no' = '1' and d->'services'->0->>'qty' = '2' and d->'services'->0->>'unit_price' = '1.00' and d->'services'->0->>'amount' = '2.00' and d->'services'->0->'final_sale' = 'true'::jsonb
    and d->'services'->0->>'description' = 'FINAL SALE ITEM - No Return or Exchange — Wig- Wild' and d->'services'->0->>'comment' = '' and d->'charges'->0->>'comment' = 'Wig- Wild' and d->'services'->0->>'so_number' = 'SO-21445',
    left((d->'services')::text || ' ' || (d->>'services_title'), 400));
  perform pg_temp.res('B2 SO-21445 합계 — 서비스 2.00 · 0.26 · 2.26 · 운임 0.00 · charges 2.00 · 2.26 그대로 · 제품 6 줄 · 41(서비스는 따로 1 줄 · 2) · 총액 286.94',
    d->'totals'->>'services_before_tax' = '2.00' and d->'totals'->>'services_tax' = '0.26' and d->'totals'->>'services_total' = '2.26' and d->'totals'->>'freight_before_tax' = '0.00' and d->'totals'->>'freight_total' = '0.00'
    and d->'totals'->>'charges_before_tax' = '2.00' and d->'totals'->>'charges_total' = '2.26' and d->'totals'->>'line_count' = '6' and d->'totals'->>'qty_total' = '41'
    and d->'totals'->>'services_line_count' = '1' and d->'totals'->>'services_qty_total' = '2' and d->'totals'->>'total' = '286.94' and d->'orders'->0->'has_lines' = 'true'::jsonb,
    left((d->'totals')::text, 600));
  d := pg_temp.j((select n.v from t_new n where n.k = 'ir:' || c_mix));
  perform pg_temp.res('B3 SO-21445 internal_receipt — 같은 새 열쇠(같은 길)', d->>'services_title' = 'Final sale items' and d->'services_separate' = 'true'::jsonb and d->'totals'->>'services_total' = '2.26' and d->'services'->0->'final_sale' = 'true'::jsonb, left((d->'services')::text, 300));

  -- ═══ C 순수 서비스 문서(서비스 오더 · 인보이스 60471) ═══
  d := pg_temp.j((select n.v from t_new n where n.k = 'fi:' || c_svc));
  select count(*), coalesce(sum(l.qty), 0) into v_n, r from public.so_invoice_line l where l.invoice_id = c_svc::uuid and l.kind = 'charge';
  perform pg_temp.res('C1 순수 서비스 final_invoice — 「Services」 · as_main(제목 없이 본표 자리) · separate false · 제품 줄 0 · orders[].has_lines false · 서비스 줄 수 · 수량 = DB',
    d->>'services_title' = 'Services' and d->'services_as_main' = 'true'::jsonb and d->'services_separate' = 'false'::jsonb and d->'has_product_lines' = 'false'::jsonb and d->'has_services' = 'true'::jsonb
    and d->'orders'->0->'has_lines' = 'false'::jsonb and d->'totals'->>'line_count' = '0' and jsonb_array_length(d->'services') = v_n and v_n >= 5 and d->'totals'->>'services_line_count' = v_n::text
    and pg_temp.num(d->'totals'->>'services_qty_total') = r::numeric and d->'totals'->>'services_before_tax' = d->'totals'->>'charges_before_tax' and d->'totals'->>'services_total' = d->'totals'->>'charges_total'
    and not exists (select 1 from jsonb_array_elements(d->'services') s where s->'final_sale' <> 'false'::jsonb or s->>'qty' = '' or s->>'unit_price' = ''),
    left(format('title %s · lines %s · qty %s · totals %s', d->>'services_title', v_n, r, (d->'totals')::text), 600));
  d := pg_temp.j((select n.v from t_new n where n.k = 'ir:' || c_svc));
  perform pg_temp.res('C2 순수 서비스 internal_receipt — as_main · 서비스 줄 수 같음', d->'services_as_main' = 'true'::jsonb and jsonb_array_length(d->'services') = v_n, left((d->'services')::text, 200));

  -- ═══ D 제품 + 운임만(서비스 0 · 설명 있는 운임) ═══
  d := pg_temp.j((select n.v from t_new n where n.k = 'fi:' || c_prod));
  perform pg_temp.res('D1 제품만 있는 인보이스 — 서비스 표지 전부 false · 제목 "" · services [] · freight_lines = charges 와 같은 줄 수 · 서비스 합계 0.00 · 0 줄',
    d->'has_services' = 'false'::jsonb and d->'services_separate' = 'false'::jsonb and d->'services_as_main' = 'false'::jsonb and d->>'services_title' = '' and d->'services' = '[]'::jsonb and d->'has_product_lines' = 'true'::jsonb
    and d->'has_freight_lines' = 'true'::jsonb and jsonb_array_length(d->'freight_lines') = jsonb_array_length(d->'charges') and d->'totals'->>'services_before_tax' = '0.00' and d->'totals'->>'services_total' = '0.00'
    and d->'totals'->>'services_line_count' = '0' and d->'totals'->>'services_qty_total' = '0' and d->'totals'->>'freight_before_tax' = d->'totals'->>'charges_before_tax' and d->'totals'->>'freight_total' = d->'totals'->>'charges_total',
    left((d->'freight_lines')::text, 400));
  perform pg_temp.res('D2 그 운임 줄 — freight_lines 의 메모는 비고(설명에 이미) charges 의 메모는 그대로 · 나머지 칸은 charges 와 같음',
    exists (select 1 from jsonb_array_elements(d->'charges') with ordinality c(c, ord) join jsonb_array_elements(d->'freight_lines') with ordinality f(f, ord) on f.ord = c.ord where c.c->>'comment' <> '' and f.f->>'comment' = '')
    and not exists (select 1 from jsonb_array_elements(d->'charges') with ordinality c(c, ord) join jsonb_array_elements(d->'freight_lines') with ordinality f(f, ord) on f.ord = c.ord where (c.c - 'comment') <> (f.f - 'comment')),
    left((d->'charges')::text, 300));

  -- ═══ E 이월 인보이스 — 같은 예외 그대로 ═══
  r := (select n.v from t_new n where n.k = 'fi:' || c_open);
  perform pg_temp.res('E1 이월 인보이스 — doc_data 가 같은 예외(carried forward … cannot be printed)를 그대로 던진다', r like 'ERR %was carried forward from the previous system%' and (not v_has_old or r = (select o.v from t_old o where o.k = 'fi:' || c_open)), left(r, 200));

  -- ═══ F 무변 — internal_receipt · credit_note · sales_order · 카탈로그 ═══
  if v_has_old then
    select count(*), count(*) filter (where pg_temp.strip(pg_temp.j(n.v)) is distinct from pg_temp.j(o.v) or (n.v like 'ERR%' and n.v <> o.v)) into v_n, v_m from t_new n join t_old o on o.k = n.k where n.k like 'ir:%';
    perform pg_temp.res('F1 전후 — internal_receipt(서비스 인보이스 전부 + 최근 40 + 이월 하나): 새 열쇠를 뺀 새 문서 = 옛 문서', v_n >= 40 and v_m = 0, format('differ %s of %s', v_m, v_n));
    select count(*), count(*) filter (where n.v is distinct from o.v) into v_n, v_m from t_new n join t_old o on o.k = n.k where n.k like 'cn:%';
    perform pg_temp.res('F2 전후 — credit_note 자료 글자 그대로(크레딧 전부)', v_n >= 30 and v_m = 0, format('differ %s of %s', v_m, v_n));
    select count(*), count(*) filter (where n.v is distinct from o.v) into v_n, v_m from t_new n join t_old o on o.k = n.k where n.k like 'so:%';
    perform pg_temp.res('F3 전후 — sales_order 자료 글자 그대로(열린 오더 40)', v_n >= 30 and v_m = 0, format('differ %s of %s', v_m, v_n));
    perform pg_temp.res('F4 전후 — credit_note · sales_order 카탈로그 출력 바이트 동일',
      (select n.v = o.v from t_new n join t_old o on o.k = n.k where n.k = 'cat:credit_note') and (select n.v = o.v from t_new n join t_old o on o.k = n.k where n.k = 'cat:sales_order'), 'cat');
    select count(*) into v_n from unnest(array['final_invoice', 'internal_receipt', 'ship_ready']) kk
     where (select array_agg(a order by a) from (select jsonb_array_elements_text(pg_temp.j((select n.v from t_new n where n.k = 'cat:' || kk))->'allowed') a except select jsonb_array_elements_text(pg_temp.j((select o.v from t_old o where o.k = 'cat:' || kk))->'allowed')) x)
           is distinct from (select array_agg(a order by a) from unnest(c_new_keys) a)
        or exists (select jsonb_array_elements_text(pg_temp.j((select o.v from t_old o where o.k = 'cat:' || kk))->'allowed') except select jsonb_array_elements_text(pg_temp.j((select n.v from t_new n where n.k = 'cat:' || kk))->'allowed'))
        or pg_temp.j((select n.v from t_new n where n.k = 'cat:' || kk))->'required' <> pg_temp.j((select o.v from t_old o where o.k = 'cat:' || kk))->'required'
        or pg_temp.j((select n.v from t_new n where n.k = 'cat:' || kk))->'sections' <> (pg_temp.j((select o.v from t_old o where o.k = 'cat:' || kk))->'sections') || '["services", "freight_lines"]'::jsonb;
    perform pg_temp.res('F5 전후 — 인보이스 꼴 셋 카탈로그: 더한 열쇠는 정확히 36 · 뺀 것 0 · required 그대로 · 구획 + services · freight_lines', v_n = 0 and cardinality(c_new_keys) = 36, format('kinds off %s', v_n));
  end if;
  select count(*) into v_n from unnest(array['final_invoice', 'internal_receipt', 'ship_ready']) k where not ((public.doc_field_catalog(k)->'allowed') ?& c_new_keys and (public.doc_field_catalog(k)->'sections') ?& array['services', 'freight_lines']);
  select count(*) into v_m from unnest(array['credit_note', 'sales_order']) k cross join unnest(c_new_keys) a where (public.doc_field_catalog(k)->'allowed') ? a or (public.doc_field_catalog(k)->'sections') ?| array['services', 'freight_lines'];
  perform pg_temp.res('F6 카탈로그 — 새 열쇠 36 · 구획 둘이 인보이스 꼴 셋에 있고 credit_note · sales_order 에는 없다', v_n = 0 and v_m = 0, format('missing kinds %s · leaked %s', v_n, v_m));
  -- 문서가 내는 열쇠 ↔ 카탈로그: 새 열쇠가 전부 실제 문서에 있다(SO-21445)
  d := pg_temp.j((select n.v from t_new n where n.k = 'fi:' || c_mix));
  select count(*) into v_n from unnest(c_new_keys) a where case split_part(a, '.', 1) when 'totals' then not (d->'totals' ? split_part(a, '.', 2)) when 'orders' then not (d->'orders'->0 ? split_part(a, '.', 2))
                                                           when 'services' then not (d->'services'->0 ? split_part(a, '.', 2)) when 'freight_lines' then false else not (d ? a) end;
  perform pg_temp.res('F7 카탈로그 ↔ 출력 — 새 열쇠가 SO-21445 문서에 전부 있다(freight_lines.* 는 D 의 문서에서)', v_n = 0
    and not exists (select 1 from unnest(c_new_keys) a where split_part(a, '.', 1) = 'freight_lines' and not (pg_temp.j((select n.v from t_new n where n.k = 'fi:' || c_prod))->'freight_lines'->0 ? split_part(a, '.', 2))), format('missing %s', v_n));
  -- 판 검사: 새 열쇠를 쓴 판은 인보이스 꼴에서 지나가고 credit_note 에서는 거부 · 지금 쓰는 판 셋은 그대로 지나간다
  r := '<html><body>{{invoice.number}}{{invoice.total_qty}}{{invoice.calc_at}}{{#orders}}{{#has_lines}}{{#lines}}{{no}}{{/lines}}{{/has_lines}}{{/orders}}{{#has_product_lines}}x{{/has_product_lines}}'
       || '{{#has_services}}{{#services_separate}}<h2>{{services_title}}</h2>{{/services_separate}}{{#services_as_main}}m{{/services_as_main}}{{#services}}{{no}}{{so_number}}{{code}}{{description}}{{#comment}}{{comment}}{{/comment}}{{qty}}{{unit_price}}{{discount_pct}}{{amount}}{{tax_amount}}{{#final_sale}}F{{/final_sale}}{{/services}}'
       || '{{totals.services_line_count}}{{totals.services_qty_total}}{{totals.services_before_tax}}{{totals.services_tax}}{{totals.services_total}}{{/has_services}}'
       || '{{#has_freight_lines}}{{#freight_lines}}{{no}}{{description}}{{amount}}{{/freight_lines}}{{totals.freight_before_tax}}{{totals.freight_tax}}{{totals.freight_total}}{{/has_freight_lines}}{{^has_freight_lines}}none{{/has_freight_lines}}'
       || '{{totals.tax}}{{totals.total}}{{totals.due_amount}}</body></html>';
  perform pg_temp.res('F8 판 검사 — 새 열쇠를 전부 쓴 판: final_invoice · internal_receipt 통과 · ship_ready 통과(번호 자리만 빼고) · credit_note 는 unknown_field 로 거부',
    (public.doc_template_check('final_invoice', replace(r, '{{invoice.calc_at}}', ''), 'template')->>'ok')::boolean and (public.doc_template_check('internal_receipt', replace(r, '{{invoice.calc_at}}', ''), 'template')->>'ok')::boolean
    and (public.doc_template_check('ship_ready', replace(r, '{{invoice.number}}', ''), 'template')->>'ok')::boolean
    and (public.doc_template_check('credit_note', r, 'template')->'problems')::text like '%unknown_field%services_title%',
    left((public.doc_template_check('final_invoice', replace(r, '{{invoice.calc_at}}', ''), 'template')->'problems')::text || (public.doc_template_check('ship_ready', replace(r, '{{invoice.number}}', ''), 'template')->'problems')::text, 500));
  select count(*), count(*) filter (where (public.doc_template_check(t.kind, t.body, 'template')->>'ok')::boolean) into v_n, v_m from public.doc_template_active a join public.doc_template t on t.id = a.template_id;
  perform pg_temp.res('F9 지금 쓰는 판 다섯 — 판 검사 그대로 통과(옛 판이 다시 Check 돼도 지나간다)', v_n = 5 and v_m = 5, format('ok %s of %s', v_m, v_n));

  -- ═══ G 화면 창구 — so_invoice_detail · so_credit_prepare ═══
  if v_has_old then
    select count(*), count(*) filter (where n.v like 'ERR%' or (pg_temp.j(n.v) #- '{invoice,services_amount}'
              || jsonb_build_object('orders', (select coalesce(jsonb_agg(o - 'services_amount' order by ord), '[]'::jsonb) from jsonb_array_elements(pg_temp.j(n.v)->'orders') with ordinality t(o, ord)),
                                    'lines', (select coalesce(jsonb_agg(l - 'is_service' - 'final_sale' order by ord), '[]'::jsonb) from jsonb_array_elements(pg_temp.j(n.v)->'lines') with ordinality t(l, ord)))) is distinct from pg_temp.j(o.v))
      into v_n, v_m from t_new n join t_old o on o.k = n.k where n.k like 'det:%';
    perform pg_temp.res('G1 전후 — so_invoice_detail: 더한 칸(invoice · orders[] 의 services_amount · lines[] 의 is_service · final_sale)을 빼면 옛 출력(인보이스 전부 + 이월 20)', v_n > 400 and v_m = 0, format('differ %s of %s', v_m, v_n));
    select count(*), count(*) filter (where n.v like 'ERR%' and n.v <> o.v or n.v not like 'ERR%' and jsonb_set(pg_temp.j(n.v), '{lines}', (select coalesce(jsonb_agg(l - 'is_service' order by ord), '[]'::jsonb) from jsonb_array_elements(pg_temp.j(n.v)->'lines') with ordinality t(l, ord))) is distinct from pg_temp.j(o.v))
      into v_n, v_m from t_new n join t_old o on o.k = n.k where n.k like 'prep:%';
    perform pg_temp.res('G2 전후 — so_credit_prepare: lines[] 의 is_service 를 빼면 옛 출력(인보이스 전부 + 이월 20)', v_n > 400 and v_m = 0, format('differ %s of %s', v_m, v_n));
  end if;
  d := pg_temp.j((select n.v from t_new n where n.k = 'det:' || c_mix));
  perform pg_temp.res('G3 so_invoice_detail SO-21445 — invoice.services_amount 2.00 · orders[0].services_amount 2.00 · 서비스 줄 is_service true · final_sale true · 제품 줄 is_service false',
    (d->'invoice'->>'services_amount')::numeric = 2.00 and (d->'orders'->0->>'services_amount')::numeric = 2.00 and (d->'invoice'->>'charges_amount')::numeric = 2.00
    and (select count(*) from jsonb_array_elements(d->'lines') l where l->'is_service' = 'true'::jsonb and l->'final_sale' = 'true'::jsonb and l->>'kind' = 'charge') = 1
    and (select count(*) from jsonb_array_elements(d->'lines') l where l->>'kind' = 'product' and l->'is_service' = 'false'::jsonb and jsonb_typeof(l->'final_sale') = 'boolean') = 6,
    left((d->'invoice'->>'services_amount') || ' ' || (d->'orders'->0->>'services_amount'), 100));
  select coalesce(sum((select count(*) from jsonb_array_elements(pg_temp.j(n.v)->'lines') l where l->'is_service' = 'true'::jsonb)), 0),
         coalesce(sum((pg_temp.j(n.v)->'invoice'->>'services_amount')::numeric), 0),
         coalesce(sum((select count(*) from jsonb_array_elements(pg_temp.j(n.v)->'lines') l where l->'final_sale' = 'true'::jsonb and l->>'kind' = 'product')), 0)
    into v_n, r, v_m from t_new n where n.k like 'det:%' and n.v not like 'ERR%';
  perform pg_temp.res('G4 so_invoice_detail 전수 — is_service 줄 수 · services_amount 합 = DB · B급으로 판 제품 줄은 final_sale true(DB 줄 수와 같음) · 운임만 있는 인보이스는 0',
    v_n = (select count(*) from public.so_invoice_line l join public.so_charge c on c.id = l.so_charge_id where c.service_id is not null)
    and r::numeric = (select coalesce(sum(l.amount), 0) from public.so_invoice_line l join public.so_charge c on c.id = l.so_charge_id where l.kind = 'charge' and c.service_id is not null)
    and v_m = (select count(*) from public.so_invoice_line l join public.so_line sl on sl.id = l.so_line_id where l.kind = 'product' and sl.bgrade_bin_id is not null)
    and (pg_temp.j((select n.v from t_new n where n.k = 'det:' || c_prod))->'invoice'->>'services_amount')::numeric = 0,
    format('is_service lines %s · services_amount sum %s · b-grade lines %s', v_n, r, v_m));
  d := pg_temp.j((select n.v from t_new n where n.k = 'prep:' || c_mix));
  perform pg_temp.res('G5 so_credit_prepare — SO-21445 의 서비스 줄 is_service true(final_sale true 그대로) · 제품 줄 false · 운임 인보이스의 운임 줄 false · 서비스 오더의 줄 전부 true',
    (select count(*) from jsonb_array_elements(d->'lines') l where l->>'kind' = 'charge' and l->'is_service' = 'true'::jsonb and l->'final_sale' = 'true'::jsonb) = 1
    and (select count(*) from jsonb_array_elements(d->'lines') l where l->>'kind' = 'product' and l->'is_service' = 'false'::jsonb) = 6
    and (select count(*) filter (where l->'is_service' = 'false'::jsonb) > 0 and count(*) filter (where l->'is_service' <> 'false'::jsonb) = 0 from jsonb_array_elements(pg_temp.j((select n.v from t_new n where n.k = 'prep:' || c_prod))->'lines') l where l->>'kind' = 'charge')
    and (select count(*) >= 5 and count(*) filter (where l->'is_service' <> 'true'::jsonb) = 0 from jsonb_array_elements(pg_temp.j((select n.v from t_new n where n.k = 'prep:' || c_svc))->'lines') l),
    left((d->'lines'->-1)::text, 300));

  -- ═══ S ship_ready — 실물 전후 + rollback 안 가상 서비스 건 ═══
  v_ref := jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', c_sr, 'carrier_id', c_car, 'charges', jsonb_build_array(jsonb_build_object('name', 'Freight', 'amount', 25.00)))));   -- snap 과 같은 꼴
  r := (select n.v from t_new n where n.k = 'sr');
  d := pg_temp.j(r)->'docs'->0;
  perform pg_temp.res('S1 ship_ready 실물(packed 오더) — 자료가 나오고 서비스 표지 false · freight_lines = charges 줄 수 · 합계 불변식',
    r not like 'ERR%' and d->'has_services' = 'false'::jsonb and d->>'services_title' = '' and jsonb_array_length(d->'freight_lines') = jsonb_array_length(d->'charges') and d->'has_product_lines' = 'true'::jsonb
    and d->'totals'->>'freight_total' = d->'totals'->>'charges_total' and d->'totals'->>'services_total' = '0.00' and d->'orders'->0->'has_lines' = 'true'::jsonb, left(r, 300));
  if v_has_old then
    perform pg_temp.res('S2 전후 — ship_ready: 새 열쇠를 뺀 새 문서 = 옛 문서 · groups 그대로',
      (select coalesce(jsonb_agg(pg_temp.strip(x) order by ord), '[]'::jsonb) from jsonb_array_elements(pg_temp.j(r)->'docs') with ordinality t(x, ord)) = pg_temp.j((select o.v from t_old o where o.k = 'sr'))->'docs'
      and pg_temp.j(r)->'groups' = pg_temp.j((select o.v from t_old o where o.k = 'sr'))->'groups', left(r, 200));
    perform pg_temp.res('S3 전후 — so_invoice_preview: 운임 줄의 is_service · final_sale 둘을 빼면 옛 출력 · 운임 줄은 표지 false · qty · unit_price 그대로 null',
      (select n.v from t_new n where n.k = 'pv') not like 'ERR%'
      and jsonb_set(pg_temp.j((select n.v from t_new n where n.k = 'pv')), '{docs}', (select jsonb_agg(jsonb_set(x, '{charges}', (select coalesce(jsonb_agg(c - 'is_service' - 'final_sale' order by co), '[]'::jsonb) from jsonb_array_elements(x->'charges') with ordinality cc(c, co))) order by ord)
                                                                                         from jsonb_array_elements(pg_temp.j((select n.v from t_new n where n.k = 'pv'))->'docs') with ordinality t(x, ord)))
          = pg_temp.j((select o.v from t_old o where o.k = 'pv'))
      and (select count(*) > 0 and count(*) filter (where c->'is_service' <> 'false'::jsonb or c->'final_sale' <> 'false'::jsonb or c->'qty' <> 'null'::jsonb or c->'unit_price' <> 'null'::jsonb) = 0
           from jsonb_array_elements(pg_temp.j((select n.v from t_new n where n.k = 'pv'))->'docs'->0->'charges') c), left((pg_temp.j((select n.v from t_new n where n.k = 'pv'))->'docs'->0->'charges')::text, 300));
  end if;
  -- 가상: 그 packed 오더에 서비스 줄 하나(수량 3 × 2.50 = 7.50 · 메모 있음) — 일반 서비스가 창고 오더에 붙는 것은 DB 가 막지 않는다(docsvc-0 §1)
  insert into public.so_charge (so_id, line_no, name, description, amount, qty, unit_price, service_id, account_id, account_code)
    select c_sr::uuid, 99, rs.name, 'docsvc test memo', 7.50, 3, 2.50, rs.id, (select c.account_id from public.so_charge c where c.service_id = rs.id limit 1), (select c.account_code from public.so_charge c where c.service_id = rs.id limit 1)
    from public.ref_service rs where rs.id = c_svcid::uuid returning id into v_cid;
  r := pg_temp.q(format('select public.doc_data(''ship_ready'', %L::jsonb)::text', v_ref));
  d := pg_temp.j(r)->'docs'->0;
  perform pg_temp.res('S4 가상 ship_ready(제품 + 서비스 줄) — 「Services」 · separate · 서비스 줄에 수량 3 · 단가 2.50 · 7.50 · 메모 한 번 · final_sale false · 운임 줄은 그대로',
    r not like 'ERR%' and d->>'services_title' = 'Services' and d->'services_separate' = 'true'::jsonb and d->'services_as_main' = 'false'::jsonb and jsonb_array_length(d->'services') = 1
    and d->'services'->0->>'qty' = '3' and d->'services'->0->>'unit_price' = '2.50' and d->'services'->0->>'amount' = '7.50' and d->'services'->0->>'comment' = '' and d->'services'->0->'final_sale' = 'false'::jsonb
    and d->'services'->0->>'description' like '% — docsvc test memo' and d->'totals'->>'services_before_tax' = '7.50' and d->'totals'->>'services_line_count' = '1' and d->'totals'->>'services_qty_total' = '3'
    and jsonb_array_length(d->'freight_lines') = jsonb_array_length(d->'charges') - 1
    and pg_temp.num(d->'totals'->>'services_total') + pg_temp.num(d->'totals'->>'freight_total') = pg_temp.num(d->'totals'->>'charges_total'), left(coalesce((d->'services')::text, r), 400));
  perform pg_temp.res('S5 가상 ship_ready — charges[] 의 그 서비스 줄에도 수량 · 단가가 찍힌다(이견 7 · 허용된 변화) · 메모는 charges[] 에 그대로',
    exists (select 1 from jsonb_array_elements(d->'charges') c where c->>'qty' = '3' and c->>'unit_price' = '2.50' and c->>'comment' = 'docsvc test memo')
    and (select count(*) from jsonb_array_elements(d->'charges') c where c->>'qty' <> '') = 1 + (select count(*) from jsonb_array_elements(d->'freight_lines') c where c->>'qty' <> ''), left((d->'charges')::text, 400));
  -- 마무리 화면이 그 줄의 금액을 고치면(9.00 ≠ 3 × 2.50) 수량 · 단가는 비운다 — so_invoice_issue :159 와 같은 식
  r := pg_temp.q(format('select public.doc_data(''ship_ready'', %L::jsonb)::text', jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', c_sr, 'carrier_id', c_car,
         'charges', jsonb_build_array(jsonb_build_object('charge_id', v_cid, 'name', (select c.name from public.so_charge c where c.id = v_cid), 'amount', 9.00, 'description', 'docsvc test memo'), jsonb_build_object('name', 'Freight', 'amount', 25.00)))))));
  d := pg_temp.j(r)->'docs'->0;
  perform pg_temp.res('S6 가상 ship_ready — 금액을 고친 서비스 줄(9.00 ≠ 수량 × 단가)은 수량 · 단가 빈칸 · 여전히 services[] · 줄 수 1 · 수량 0',
    r not like 'ERR%' and jsonb_array_length(d->'services') = 1 and d->'services'->0->>'amount' = '9.00' and d->'services'->0->>'qty' = '' and d->'services'->0->>'unit_price' = ''
    and d->'totals'->>'services_line_count' = '1' and d->'totals'->>'services_qty_total' = '0', left(coalesce((d->'services')::text, r), 300));
  delete from public.so_charge c where c.id = v_cid;

  -- ═══ M fmt 가상 재료 — 제목 셋 · 할인 줄 · surcharge · 오더 할인 · 번호 · 1227 갈래 · 오더 여럿 ═══
  d := public.doc_data_invoice_fmt('final_invoice', v_cfg, jsonb_build_object('header', jsonb_build_object('number', 'T-1', 'bill_to', '{}'::jsonb),
    'orders', jsonb_build_array(jsonb_build_object('so_number', 'SO-A', 'ship_to', '{}'::jsonb, 'lines', jsonb_build_array(jsonb_build_object('sku', 'X', 'qty', 4, 'amount', 40, 'tax_amount', 5.2, 'unit_price', 10))),
                                jsonb_build_object('so_number', 'SO-B', 'ship_to', '{}'::jsonb, 'lines', '[]'::jsonb)),
    'charges', jsonb_build_array(
      jsonb_build_object('so_number', 'SO-A', 'kind', 'surcharge',       'description', 'Tariff surcharge', 'comment', '', 'qty', 4, 'unit_price', 1, 'amount', 4, 'tax_amount', 0.52),
      jsonb_build_object('so_number', 'SO-A', 'kind', 'order_discount',  'description', 'Order discount 5%', 'comment', '', 'amount', -2, 'tax_amount', -0.26),
      jsonb_build_object('so_number', 'SO-A', 'kind', 'charge',          'description', 'Freight — LTL', 'comment', 'LTL', 'amount', 30, 'tax_amount', 3.9, 'is_service', false, 'final_sale', false),
      jsonb_build_object('so_number', 'SO-A', 'kind', 'charge_discount', 'description', 'Freight discount 50%', 'comment', '', 'discount_pct', 50, 'amount', -15, 'tax_amount', -1.95, 'is_service', false, 'final_sale', false),
      jsonb_build_object('so_number', 'SO-A', 'kind', 'charge',          'description', 'FINAL SALE ITEM — Wig', 'comment', 'Wig', 'qty', 2, 'unit_price', 1, 'amount', 2, 'tax_amount', 0.26, 'is_service', true, 'final_sale', true),
      jsonb_build_object('so_number', 'SO-B', 'kind', 'charge',          'description', 'Prep per unit', 'comment', 'rush job', 'qty', 2.5, 'unit_price', 4, 'amount', 10, 'tax_amount', 1.3, 'is_service', true, 'final_sale', false),
      jsonb_build_object('so_number', 'SO-B', 'kind', 'charge_discount', 'description', 'Prep per unit discount 10%', 'comment', '', 'discount_pct', 10, 'amount', -1, 'tax_amount', -0.13, 'is_service', true, 'final_sale', false),
      jsonb_build_object('so_number', 'SO-B', 'kind', 'charge',          'description', 'Pallet fee', 'comment', '', 'amount', 5, 'tax_amount', 0.65)),
    'payments', '[]'::jsonb, 'totals', jsonb_build_object('taxable', 73, 'tax', 9.49, 'total', 82.49, 'amount_due', 82.49)));
  perform pg_temp.res('M1 가상 섞임 — 제목 「Services & final sale」 · services 3(떨이 · 서비스 · 그 할인 줄 — 부모를 따라감) · freight_lines 5(surcharge · 오더 할인 · 운임 · 운임 할인 · 표지 없는 줄) · 번호 각자 1 부터 · charges 8 은 1 ~ 8',
    d->>'services_title' = 'Services & final sale' and d->'services_separate' = 'true'::jsonb and jsonb_array_length(d->'services') = 3 and jsonb_array_length(d->'freight_lines') = 5 and jsonb_array_length(d->'charges') = 8
    and (select string_agg(s->>'no', ',' order by ord) from jsonb_array_elements(d->'services') with ordinality t(s, ord)) = '1,2,3'
    and (select string_agg(s->>'no', ',' order by ord) from jsonb_array_elements(d->'freight_lines') with ordinality t(s, ord)) = '1,2,3,4,5'
    and (select string_agg(s->>'no', ',' order by ord) from jsonb_array_elements(d->'charges') with ordinality t(s, ord)) = '1,2,3,4,5,6,7,8'
    and (select string_agg(s->>'description', '|' order by ord) from jsonb_array_elements(d->'services') with ordinality t(s, ord)) = 'FINAL SALE ITEM — Wig|Prep per unit|Prep per unit discount 10%'
    and (select string_agg(s->>'description', '|' order by ord) from jsonb_array_elements(d->'freight_lines') with ordinality t(s, ord)) = 'Tariff surcharge|Order discount 5%|Freight — LTL|Freight discount 50%|Pallet fee'
    and d->'services'->0->'final_sale' = 'true'::jsonb and d->'services'->1->'final_sale' = 'false'::jsonb, left((d->'services')::text || (d->>'services_title'), 500));
  perform pg_temp.res('M2 가상 합계 — 서비스 11.00 · 1.43 · 12.43(할인 줄 포함) · 운임 22.00 · 2.86 · 24.86 · charges 33.00 · 4.29 · 37.29 · 서비스 줄 수 2(할인 줄 안 셈) · 수량 4.5 · 제품 1 줄 · 4',
    d->'totals'->>'services_before_tax' = '11.00' and d->'totals'->>'services_tax' = '1.43' and d->'totals'->>'services_total' = '12.43' and d->'totals'->>'freight_before_tax' = '22.00' and d->'totals'->>'freight_tax' = '2.86' and d->'totals'->>'freight_total' = '24.86'
    and d->'totals'->>'charges_before_tax' = '33.00' and d->'totals'->>'charges_tax' = '4.29' and d->'totals'->>'charges_total' = '37.29' and d->'totals'->>'charges_discount' = '-16.00'
    and d->'totals'->>'services_line_count' = '2' and d->'totals'->>'services_qty_total' = '4.5' and d->'totals'->>'line_count' = '1' and d->'totals'->>'qty_total' = '4', left((d->'totals')::text, 600));
  perform pg_temp.res('M3 가상 1227 — 「… — 메모」 로 끝나면 메모를 비운다(떨이 · 운임) · 설명에 없는 메모(rush job)는 그대로 · charges[] 는 셋 다 그대로',
    d->'services'->0->>'comment' = '' and d->'services'->1->>'comment' = 'rush job' and d->'freight_lines'->2->>'comment' = ''
    and d->'charges'->2->>'comment' = 'LTL' and d->'charges'->4->>'comment' = 'Wig' and d->'charges'->5->>'comment' = 'rush job', left((d->'freight_lines'->2)::text, 300));
  perform pg_temp.res('M4 가상 오더 여럿 — 제품 줄 있는 오더 has_lines true · 없는 오더 false(빈 제품 표를 안 그리게) · 문서는 has_product_lines true',
    d->'orders'->0->'has_lines' = 'true'::jsonb and d->'orders'->1->'has_lines' = 'false'::jsonb and d->'has_product_lines' = 'true'::jsonb and d->'orders'->1->>'line_count' = '0', left((d->'orders'->1)::text, 200));
  d := public.doc_data_invoice_fmt('internal_receipt', v_cfg, jsonb_build_object('header', jsonb_build_object('number', 'T-2', 'bill_to', '{}'::jsonb), 'orders', jsonb_build_array(jsonb_build_object('so_number', 'SO-C', 'ship_to', '{}'::jsonb, 'lines', '[]'::jsonb)),
    'charges', jsonb_build_array(jsonb_build_object('so_number', 'SO-C', 'kind', 'charge', 'description', 'FINAL SALE ITEM', 'comment', '', 'qty', 1, 'unit_price', 3, 'amount', 3, 'tax_amount', 0.39, 'is_service', true, 'final_sale', true)),
    'payments', '[]'::jsonb, 'totals', jsonb_build_object('taxable', 3, 'tax', 0.39, 'total', 3.39, 'amount_due', 0)));
  perform pg_temp.res('M5 가상 떨이만 있는 POS 영수증 — 「Final sale items」 · as_main · 운임 [] · has_freight_lines false',
    d->>'services_title' = 'Final sale items' and d->'services_as_main' = 'true'::jsonb and d->'services_separate' = 'false'::jsonb and d->'freight_lines' = '[]'::jsonb and d->'has_freight_lines' = 'false'::jsonb and d->'has_product_lines' = 'false'::jsonb, left(d::text, 200));
  d := public.doc_data_invoice_fmt('final_invoice', v_cfg, '{"header":{"bill_to":{}},"orders":[],"charges":[],"payments":[],"totals":{}}'::jsonb);
  perform pg_temp.res('M6 가상 빈 문서 — 새 열쇠가 전부 있고 비어 있다([] · "" · false · 0.00 · 0)',
    d->'services' = '[]'::jsonb and d->'freight_lines' = '[]'::jsonb and d->>'services_title' = '' and d->'has_services' = 'false'::jsonb and d->'has_freight_lines' = 'false'::jsonb and d->'has_product_lines' = 'false'::jsonb
    and d->'services_separate' = 'false'::jsonb and d->'services_as_main' = 'false'::jsonb and d->'totals'->>'services_total' = '0.00' and d->'totals'->>'freight_total' = '0.00' and d->'totals'->>'services_line_count' = '0' and d->'totals'->>'services_qty_total' = '0' and d->'orders' = '[]'::jsonb,
    left(d::text, 200));

  -- ═══ Z 무접촉 · 끝 상태 ═══
  perform pg_temp.res('Z1 무접촉 함수 14 — so_detail · doc_data · doc_data_so · doc_data_credit · doc_data_common · doc_qty_totals · so_tax_preview · so_invoice_issue · so_finalize · qbo_invoice_body · qbo_credit_body · mcp_order · mcp_sales · doc_template_check 의 prosrc 그대로',
    (select md5(string_agg(p.proname || md5(p.prosrc), ',' order by p.proname)) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('so_detail', 'doc_data', 'doc_data_so', 'doc_data_credit', 'doc_data_common', 'doc_qty_totals', 'so_tax_preview', 'so_invoice_issue', 'so_finalize', 'qbo_invoice_body', 'qbo_credit_body', 'mcp_order', 'mcp_sales', 'doc_template_check')) = current_setting('docsvc.untouched_head'), 'md5');
  perform pg_temp.res('Z2 재발행 여섯 — acl · definer/invoker · volatility 그대로 · 시그니처마다 하나(겹친 정의 없음)',
    (select md5(string_agg(p.proname || coalesce(p.proacl::text, '') || p.prosecdef::text || p.provolatile::text, ',' order by p.proname)) from pg_proc p where p.pronamespace = 'public'::regnamespace
       and p.proname in ('doc_data_invoice', 'doc_data_invoice_fmt', 'so_invoice_preview', 'doc_field_catalog', 'so_invoice_detail', 'so_credit_prepare')) = current_setting('docsvc.acl_head')
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('doc_data_invoice', 'doc_data_invoice_fmt', 'so_invoice_preview', 'doc_field_catalog', 'so_invoice_detail', 'so_credit_prepare')) = 6, 'acl');
  perform pg_temp.res('Z3 실제 행 — 판(doc_template) 무변 · so_charge 줄 수 그대로(가상 줄 지움) · 번호 시퀀스 그대로 · 신원 postgres',
    (select md5(string_agg(t.id::text || md5(t.body), ',' order by t.id)) from public.doc_template t) = current_setting('docsvc.tpl_head')
    and (select count(*)::text from public.so_charge) = current_setting('docsvc.chg_head')
    and (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) || '/' || (select last_value::text from public.so_credit_number_seq) = current_setting('docsvc.seq_head')
    and current_user = 'postgres', format('so_charge %s · user %s', (select count(*) from public.so_charge), current_user));
end $run$;
select set_config('docsvc.inv_mix', :'inv_mix', true), set_config('docsvc.inv_svc', :'inv_svc', true), set_config('docsvc.inv_prod', :'inv_prod', true), set_config('docsvc.inv_open', :'inv_open', true),
       set_config('docsvc.so_sr', :'so_sr', true), set_config('docsvc.car', :'car', true), set_config('docsvc.svc', :'svc', true), set_config('docsvc.untouched_head', :'untouched_head', true),
       set_config('docsvc.acl_head', :'acl_head', true), set_config('docsvc.tpl_head', :'tpl_head', true), set_config('docsvc.chg_head', :'chg_head', true), set_config('docsvc.seq_head', :'seq_head', true) \gset cfg_
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · seq(so/inv/cr) ' || :'seq_head' || ' → '
       || (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) || '/' || (select last_value::text from public.so_credit_number_seq)
       || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
\pset tuples_only off
\pset format aligned
rollback;
-- 기대: 시험(-v mig) OK 45 · FAIL 0 · seq 앞 = 뒤 · begin ~ 끝 ≈ 3 분(2026-11-14 실측 — 인보이스 전부의 문서 자료를 옛 · 새 두 번 뽑는다) · 확인(적용 뒤 · -v mig 없이) OK 34(전후 대조 11 은 건너뜀)
