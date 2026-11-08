-- doc-qty-1 검증 — supabase/migrations/20261108140000_doc_qty_1_totals.sql (문서 수량 합계 열쇠 totals.line_count · qty_total · qty_total_ea · orders[].셋 · asung-doc §1 · §2 · 지시서 ~/asung/prompts/doc-qty-1.md)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB): cd ~/asung/asung-wms && set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261108140000_doc_qty_1_totals.sql -f supabase/tests/doc_qty_1_check.sql 2>&1 | tee /tmp/doc_qty_1.out
--   확인(적용 뒤 · Caleb): 같은 명령에서 -v mig=… 만 뺀다 — T(옛 = 새) 갈래는 건너뛰고 N · V · T4 · L · Z 만
--   ⚠️ 실제 행 무변: 가짜 행 insert 0 · 직원 신원은 실제 active · sales 직원 id 를 request.jwt.claims 로만(이견 10) · 읽기 창구(doc_data · so_invoice_preview)만 부른다 · 끝은 rollback
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- ── 표본(읽기) — 60244 = SO-20996 의 인보이스(세트 줄 둘 · 콤보 줄 · 오더 셋) · 60293 = 오더 둘 · 콤보 · 세트 없는 한 오더 인보이스 · packed 오더 하나(ship_ready) · 콤보 든 열린 오더(sales_order) ──
select id::text as inv_set from public.so_invoice where invoice_number = '60244' \gset
select id::text as inv_two from public.so_invoice where invoice_number = '60293' \gset
select i.id::text as inv_plain, i.invoice_number as inv_plain_no from public.so_invoice i
 where i.kind <> 'opening' and i.status = 'issued' and (select count(*) from public.so_invoice_order o where o.invoice_id = i.id) = 1
   and not exists (select 1 from public.so_invoice_line l where l.invoice_id = i.id and (l.pack_factor > 1 or l.combo_components is not null))
 order by i.issued_on desc, i.invoice_number desc limit 1 \gset
-- 열린 오더에 세트 줄(pack_factor > 1)은 없다(SO-20996 은 fulfilled · so_proforma 가 거부) — sales_order 의 EA 는 doc_qty_totals 항등(V3)과 착지 검사로
select id::text as so_plain, so_number as so_plain_no from public.so s where s.status = 'confirmed' and not exists (select 1 from public.so_line sl where sl.so_id = s.id and (sl.combo_line_id is not null or sl.pack_factor > 1)) order by s.updated_at desc limit 1 \gset
-- packed 오더는 전부 Shopify 라 미리 보기에 carrier 가 필요(so_finalize) — Pickup 꼴(추적 번호 없음) · 읽기만
select name as carrier_pick from public.ref_carrier where is_active and kind <> 'carrier' order by name limit 1 \gset
select id::text as so_combo from public.so where so_number = 'SO-21142' \gset
select id::text as so_packed, so_number as so_packed_no from public.so where status = 'packed' order by updated_at desc limit 1 \gset
select auth_user_id::text as staff from public.ims_staff where is_active and perms ? 'sales' and auth_user_id is not null order by created_at limit 1 \gset
select left(:'inv_set', 8) as inv_set_, left(:'inv_two', 8) as inv_two_, :'inv_plain_no' as inv_plain_no, :'so_plain_no' as so_plain_no, left(:'so_combo', 8) as so_combo_, :'so_packed_no' as so_packed_no, left(:'staff', 8) as staff_;
-- ── 머리(적용 전 실물) ──
select coalesce((select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') as fmt_md5_head,
       coalesce((select md5(prosrc) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') as cat_md5_head,
       coalesce((select md5(prosrc) from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), '(none)') as so_md5_head,
       coalesce((select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), '(none)') as inv_md5_head,
       coalesce((select md5(prosrc) from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure), '(none)') as pv_md5_head,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_qty_totals')::int as has_qty_head \gset
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') as fmt_acl_head,
       coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') as cat_acl_head,
       coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), '(none)') as so_acl_head,
       coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), '(none)') as inv_acl_head,
       coalesce((select proacl::text from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure), '(none)') as pv_acl_head \gset
-- 무접촉 함수 · 실물 스냅샷
select md5(string_agg(proname || ':' || md5(prosrc), '|' order by proname)) as snap_fn from pg_proc
 where pronamespace = 'public'::regnamespace and proname in ('doc_data', 'doc_data_credit', 'doc_data_ship_ready', 'so_invoice_issue', 'so_tax_preview', 'so_proforma', 'so_finalize', 'doc_fmt_qty', 'doc_price_cells', 'doc_template_check') \gset
select (select count(*) from public.so_invoice) || '|' || (select count(*) from public.so_invoice_line) || '|' || (select count(*) from public.so) || '|' || (select count(*) from public.so_line) || '|' || (select coalesce(max(updated_at)::text, '') from public.so) || '|' || (select coalesce(max(updated_at)::text, '') from public.so_invoice)
       || '|' || (select count(*) from public.mail_outbox) || '|' || (select count(*) from public.doc_file) || '|' || (select md5(string_agg(kind || version || md5(body), '|' order by kind, version)) from public.doc_template) || '|' || (select md5(string_agg(kind || template_id::text, '|' order by kind)) from public.doc_template_active) as snap_rows \gset
select (:has_qty_head = 0)::int as is_old \gset
\if :{?mig}
select 1 as expect_pass \gset
\else
select (:has_qty_head = 1)::int as expect_pass \gset
\endif

begin;
set local lock_timeout = '3s';
select set_config('d.staff', :'staff', true);
select clock_timestamp() as t_begin \gset
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
-- 실제 직원(sales) 신원으로 읽기 창구를 부른다 — insert 0 · 예외는 'ERR <sqlstate>: <문장>' 글자로
create function pg_temp.asu(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('d.staff')), true);
  execute 'set local role authenticated';
  execute p_sql into v_out;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v_out;
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.paths(p jsonb, p_pre text default '') returns setof text language plpgsql as $$
declare k text; e jsonb;
begin
  if jsonb_typeof(p) = 'object' then
    for k in select x from jsonb_object_keys(p) x loop
      if jsonb_typeof(p->k) = 'object' then return query select * from pg_temp.paths(p->k, p_pre || k || '.');
      elsif jsonb_typeof(p->k) = 'array' then return next p_pre || k; return query select * from pg_temp.paths(p->k, p_pre || k || '.');
      else return next p_pre || k; end if;
    end loop;
  elsif jsonb_typeof(p) = 'array' then
    for e in select x from jsonb_array_elements(p) x loop return query select * from pg_temp.paths(e, p_pre); end loop;
  end if;
  return;
end $$;
create function pg_temp.pset(p jsonb) returns text[] language sql as $$ select coalesce(array_agg(distinct x order by x), '{}') from pg_temp.paths(p) x $$;
create function pg_temp.cset(p jsonb) returns text[] language sql as $$ select coalesce(array_agg(distinct x order by x), '{}') from (select jsonb_array_elements_text(p->'allowed') union all select jsonb_array_elements_text(p->'sections')) t(x) $$;
create function pg_temp.minus(a text[], b text[]) returns text[] language sql as $$ select coalesce(array_agg(x order by x), '{}') from unnest(a) x where not (x = any (b)) $$;
-- 새 열쇠(totals 셋 · orders[] 셋) · 시각(printed_at · calc_at)만 떼고 비교
create function pg_temp.strip(p jsonb) returns jsonb language sql as $$
  select case when q ? 'orders' then jsonb_set(q, '{orders}', (select coalesce(jsonb_agg(o - 'line_count' - 'qty_total' - 'qty_total_ea' order by ord), '[]'::jsonb) from jsonb_array_elements(q->'orders') with ordinality t(o, ord))) else q end
  from (select jsonb_set(jsonb_set(jsonb_set(p, '{doc}', coalesce(p->'doc', '{}'::jsonb) - 'printed_at'), '{invoice}', coalesce(p->'invoice', '{}'::jsonb) - 'calc_at'), '{totals}', coalesce(p->'totals', '{}'::jsonb) - 'line_count' - 'qty_total' - 'qty_total_ea') as q) s $$;
create function pg_temp.strip_docs(p jsonb) returns jsonb language sql as $$ select (select coalesce(jsonb_agg(pg_temp.strip(d) order by ord), '[]'::jsonb) from jsonb_array_elements(p->'docs') with ordinality t(d, ord)) $$;
-- 미리 보기 원본(so_invoice_preview)에서 줄의 pack_factor 만 떼고 비교(옛 발행 = 새 발행 한 겹 · 돈 · 세금 · 줄 무변)
create function pg_temp.strip_pv(p jsonb) returns jsonb language sql as $$
  select jsonb_set(p, '{docs}', (select coalesce(jsonb_agg(jsonb_set(d, '{orders}', (select coalesce(jsonb_agg(jsonb_set(o, '{lines}', (select coalesce(jsonb_agg(l - 'pack_factor' order by lo), '[]'::jsonb) from jsonb_array_elements(o->'lines') with ordinality t3(l, lo))) order by oo), '[]'::jsonb) from jsonb_array_elements(d->'orders') with ordinality t2(o, oo))) - 'calc_at' order by do_), '[]'::jsonb) from jsonb_array_elements(p->'docs') with ordinality t1(d, do_))) $$;
-- 문서 줄 수량 칸(글자)의 합 · 줄 수
create function pg_temp.sum_q(p_lines jsonb) returns numeric language sql as $$ select coalesce(sum((l->>'qty')::numeric), 0) from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) l $$;
create function pg_temp.all_lines(p_doc jsonb) returns jsonb language sql as $$ select coalesce((select jsonb_agg(l) from jsonb_array_elements(p_doc->'orders') o cross join lateral jsonb_array_elements(o->'lines') l), '[]'::jsonb) $$;

-- 창구 부르기 글(실제 직원) — 옛 · 새 같은 글
select format('select public.doc_data(''final_invoice'', %L)::text', jsonb_build_object('invoice_id', :'inv_set')) as q_fi_set,
       format('select public.doc_data(''internal_receipt'', %L)::text', jsonb_build_object('invoice_id', :'inv_set')) as q_ir_set,
       format('select public.doc_data(''final_invoice'', %L)::text', jsonb_build_object('invoice_id', :'inv_two')) as q_fi_two,
       format('select public.doc_data(''final_invoice'', %L)::text', jsonb_build_object('invoice_id', :'inv_plain')) as q_fi_plain,
       format('select public.doc_data(''sales_order'', %L)::text', jsonb_build_object('so_id', :'so_plain')) as q_so_plain,
       format('select public.doc_data(''sales_order'', %L)::text', jsonb_build_object('so_id', :'so_combo')) as q_so_combo,
       format('select public.doc_data(''ship_ready'', %L)::text', jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so_packed', 'carrier', :'carrier_pick')))) as q_sr,
       format('select public.so_invoice_preview(%L, null)::text', jsonb_build_array(jsonb_build_object('so_id', :'so_packed', 'carrier', :'carrier_pick'))) as q_pv \gset

\if :{?mig}
-- ── O 시험에서만: 적용 전 옛 출력 ──
select public.doc_field_catalog('final_invoice')::text as o_cat_fi, public.doc_field_catalog('ship_ready')::text as o_cat_sr, public.doc_field_catalog('internal_receipt')::text as o_cat_ir,
       public.doc_field_catalog('credit_note')::text as o_cat_cr, public.doc_field_catalog('sales_order')::text as o_cat_so \gset
select pg_temp.asu(:'q_fi_set') as o_fi_set, pg_temp.asu(:'q_ir_set') as o_ir_set, pg_temp.asu(:'q_fi_two') as o_fi_two, pg_temp.asu(:'q_fi_plain') as o_fi_plain,
       pg_temp.asu(:'q_so_plain') as o_so_plain, pg_temp.asu(:'q_so_combo') as o_so_combo, pg_temp.asu(:'q_sr') as o_sr, pg_temp.asu(:'q_pv') as o_pv \gset
select pg_temp.chk('O1 시험에서만: 적용 전 = 옛 판(doc_qty_totals 없음 · 카탈로그에 totals.qty_total 없음) · 옛 출력 여덟이 다 JSON',
  :is_old = 1 and not ((pg_temp.j(:'o_cat_fi')->'allowed') ? 'totals.qty_total') and not ((pg_temp.j(:'o_cat_so')->'allowed') ? 'totals.qty_total')
  and not ((pg_temp.j(:'o_fi_set')->'docs'->0->'totals') ? 'qty_total')
  and left(:'o_fi_set', 1) = '{' and left(:'o_ir_set', 1) = '{' and left(:'o_fi_two', 1) = '{' and left(:'o_fi_plain', 1) = '{' and left(:'o_so_plain', 1) = '{' and left(:'o_so_combo', 1) = '{' and left(:'o_sr', 1) = '{' and left(:'o_pv', 1) = '{',
  format('fi_set %s | ir %s | two %s | plain %s | so_plain %s | so_combo %s | sr %s | pv %s', left(:'o_fi_set', 50), left(:'o_ir_set', 50), left(:'o_fi_two', 50), left(:'o_fi_plain', 50), left(:'o_so_plain', 50), left(:'o_so_combo', 50), left(:'o_sr', 80), left(:'o_pv', 80)));
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('G1 시험에서만: 적용 뒤 다섯 몸이 새 판 · doc_qty_totals 생김 · 여섯 함수 하나씩',
  (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> :'fmt_md5_head'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) <> :'cat_md5_head'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) <> :'so_md5_head'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) <> :'inv_md5_head'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure) <> :'pv_md5_head'
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('doc_qty_totals', 'doc_data_invoice', 'so_invoice_preview', 'doc_data_invoice_fmt', 'doc_data_so', 'doc_field_catalog')) = 6,
  'heads');
\else
select pg_temp.chk('G0 확인 실행: doc_qty_totals 가 ' || case when :is_old = 1 then '없다(적용 전 — 아래 갈래는 돌지 않는다)' else '있다(적용 뒤 · 통과 갈래)' end, :has_qty_head = 1, 'has_qty=' || :has_qty_head);
\endif

\if :expect_pass
-- ── 새 출력 ──
select public.doc_field_catalog('final_invoice')::text as n_cat_fi, public.doc_field_catalog('ship_ready')::text as n_cat_sr, public.doc_field_catalog('internal_receipt')::text as n_cat_ir,
       public.doc_field_catalog('credit_note')::text as n_cat_cr, public.doc_field_catalog('sales_order')::text as n_cat_so \gset
select pg_temp.asu(:'q_fi_set') as n_fi_set, pg_temp.asu(:'q_ir_set') as n_ir_set, pg_temp.asu(:'q_fi_two') as n_fi_two, pg_temp.asu(:'q_fi_plain') as n_fi_plain,
       pg_temp.asu(:'q_so_plain') as n_so_plain, pg_temp.asu(:'q_so_combo') as n_so_combo, pg_temp.asu(:'q_sr') as n_sr, pg_temp.asu(:'q_pv') as n_pv \gset
select pg_temp.chk('N0 새 출력 여덟이 다 JSON(실제 직원 sales 로 doc_data · ship_ready 는 so_finalize 미리 보기 · packed 오더 ' || :'so_packed_no' || ' · so_id + carrier → WMS 인계 picks)',
  left(:'n_fi_set', 1) = '{' and left(:'n_ir_set', 1) = '{' and left(:'n_fi_two', 1) = '{' and left(:'n_fi_plain', 1) = '{' and left(:'n_so_plain', 1) = '{' and left(:'n_so_combo', 1) = '{' and left(:'n_sr', 1) = '{' and left(:'n_pv', 1) = '{',
  format('fi_set %s | ir %s | two %s | plain %s | so_plain %s | so_combo %s | sr %s | pv %s', left(:'n_fi_set', 50), left(:'n_ir_set', 50), left(:'n_fi_two', 50), left(:'n_fi_plain', 50), left(:'n_so_plain', 50), left(:'n_so_combo', 50), left(:'n_sr', 120), left(:'n_pv', 120)));

\if :{?mig}
-- ── T 옛 = 새(시험에서만) ──
select pg_temp.chk('T1 카탈로그: 인보이스 꼴 세 kind allowed = 옛 + totals 셋 + orders 셋(딱 여섯) · sales_order = 옛 + totals 셋(딱 셋) · sections · required 그대로 · credit_note 바이트 무변',
  (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_fi')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_fi')->'allowed') union all select unnest(array['totals.line_count', 'totals.qty_total', 'totals.qty_total_ea', 'orders.line_count', 'orders.qty_total', 'orders.qty_total_ea'])) t(x))
  and (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_sr')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_sr')->'allowed') union all select unnest(array['totals.line_count', 'totals.qty_total', 'totals.qty_total_ea', 'orders.line_count', 'orders.qty_total', 'orders.qty_total_ea'])) t(x))
  and (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_ir')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_ir')->'allowed') union all select unnest(array['totals.line_count', 'totals.qty_total', 'totals.qty_total_ea', 'orders.line_count', 'orders.qty_total', 'orders.qty_total_ea'])) t(x))
  and (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_so')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_so')->'allowed') union all select unnest(array['totals.line_count', 'totals.qty_total', 'totals.qty_total_ea'])) t(x))
  and (pg_temp.j(:'n_cat_fi') - 'allowed') = (pg_temp.j(:'o_cat_fi') - 'allowed') and (pg_temp.j(:'n_cat_sr') - 'allowed') = (pg_temp.j(:'o_cat_sr') - 'allowed') and (pg_temp.j(:'n_cat_ir') - 'allowed') = (pg_temp.j(:'o_cat_ir') - 'allowed') and (pg_temp.j(:'n_cat_so') - 'allowed') = (pg_temp.j(:'o_cat_so') - 'allowed')
  and :'n_cat_cr' = :'o_cat_cr',
  format('fi new %s old %s | so new %s old %s', jsonb_array_length(pg_temp.j(:'n_cat_fi')->'allowed'), jsonb_array_length(pg_temp.j(:'o_cat_fi')->'allowed'), jsonb_array_length(pg_temp.j(:'n_cat_so')->'allowed'), jsonb_array_length(pg_temp.j(:'o_cat_so')->'allowed')));
select pg_temp.chk('T2 doc_data 옛 = 새(새 열쇠 totals 셋 · orders[] 셋 · 시각만 떼고): final_invoice 60244(오더 셋 · 세트 · 콤보) · internal_receipt 60244 · final_invoice 60293(오더 둘) · 세트 없는 인보이스 · sales_order 세트 없는 열린 오더 · SO-21142(콤보) · ship_ready packed 오더(docs · groups)',
  pg_temp.strip_docs(pg_temp.j(:'n_fi_set')) = pg_temp.strip_docs(pg_temp.j(:'o_fi_set')) and pg_temp.strip_docs(pg_temp.j(:'n_ir_set')) = pg_temp.strip_docs(pg_temp.j(:'o_ir_set'))
  and pg_temp.strip_docs(pg_temp.j(:'n_fi_two')) = pg_temp.strip_docs(pg_temp.j(:'o_fi_two')) and pg_temp.strip_docs(pg_temp.j(:'n_fi_plain')) = pg_temp.strip_docs(pg_temp.j(:'o_fi_plain'))
  and pg_temp.strip_docs(pg_temp.j(:'n_so_plain')) = pg_temp.strip_docs(pg_temp.j(:'o_so_plain')) and pg_temp.strip_docs(pg_temp.j(:'n_so_combo')) = pg_temp.strip_docs(pg_temp.j(:'o_so_combo'))
  and pg_temp.strip_docs(pg_temp.j(:'n_sr')) = pg_temp.strip_docs(pg_temp.j(:'o_sr')) and (pg_temp.j(:'n_sr')->'groups') = (pg_temp.j(:'o_sr')->'groups')
  and (pg_temp.j(:'o_fi_set')->'docs'->0->'orders'->0->'lines') = (pg_temp.j(:'n_fi_set')->'docs'->0->'orders'->0->'lines') and (pg_temp.j(:'o_so_plain')->'docs'->0->'lines') = (pg_temp.j(:'n_so_plain')->'docs'->0->'lines'),
  format('fi_set old=%s new=%s | so_set old=%s new=%s', left(:'o_fi_set', 80), left(:'n_fi_set', 80), left(:'o_so_plain', 80), left(:'n_so_plain', 80)));
select pg_temp.chk('T3 열쇠 대조 옛 = 새: 출력 − 카탈로그 · 카탈로그 − 출력 이 네 kind(final_invoice · internal_receipt · ship_ready · sales_order) 모두 옛과 같다(새 열쇠는 양쪽에 같이)',
  pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fi_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_fi_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_fi')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_fi')), pg_temp.pset(pg_temp.j(:'n_fi_set')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_fi')), pg_temp.pset(pg_temp.j(:'o_fi_set')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_ir_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_ir_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_ir')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_ir')), pg_temp.pset(pg_temp.j(:'n_ir_set')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_ir')), pg_temp.pset(pg_temp.j(:'o_ir_set')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_sr')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_sr')), pg_temp.pset(pg_temp.j(:'o_sr')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so_plain')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_so_plain')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_so')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_so')), pg_temp.pset(pg_temp.j(:'n_so_plain')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_so')), pg_temp.pset(pg_temp.j(:'o_so_plain')->'docs'->0)),
  format('fi out−cat old %s new %s | sr out−cat old %s new %s | so out−cat new %s',
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_fi_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_fi'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fi_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))),
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_sr'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))),
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so_plain')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so')))));
select pg_temp.chk('I1 옛 발행 = 새 발행 한 겹(시험에서만): so_invoice_preview 원본(packed 오더 ' || :'so_packed_no' || ')이 줄의 pack_factor 만 빼면 옛과 같다(돈 · 세금 · 줄 · plan 무변) · 새 줄에 pack_factor 숫자 · so_invoice_issue 는 so_invoice_preview 를 안 부른다(호출 0) · issue · so_tax_preview · so_proforma · so_finalize 몸 무변',
  pg_temp.strip_pv(pg_temp.j(:'n_pv')) = pg_temp.strip_pv(pg_temp.j(:'o_pv'))
  and (pg_temp.j(:'n_pv')->'docs'->0->'totals') = (pg_temp.j(:'o_pv')->'docs'->0->'totals')
  and jsonb_typeof(pg_temp.j(:'n_pv')->'docs'->0->'orders'->0->'lines'->0->'pack_factor') = 'number' and not ((pg_temp.j(:'o_pv')->'docs'->0->'orders'->0->'lines'->0) ? 'pack_factor')
  and (select count(*) from regexp_matches((select prosrc from pg_proc where oid = 'public.so_invoice_issue(uuid[], uuid, date)'::regprocedure), 'public\.so_invoice_preview\(', 'g')) = 0
  and (select md5(string_agg(proname || ':' || md5(prosrc), '|' order by proname)) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('doc_data', 'doc_data_credit', 'doc_data_ship_ready', 'so_invoice_issue', 'so_tax_preview', 'so_proforma', 'so_finalize', 'doc_fmt_qty', 'doc_price_cells', 'doc_template_check')) = :'snap_fn',
  format('pv old=%s new=%s', left(:'o_pv', 120), left(:'n_pv', 120)));
\endif

-- ── T4 열쇠 대조(새 판 · 시험 · 확인 둘 다) ──
select pg_temp.chk('T4 열쇠 대조(새 판): totals 셋이 네 kind 카탈로그 · 출력 양쪽에 · orders 셋이 인보이스 꼴 세 kind 양쪽에 · credit_note 카탈로그에 없다 · sales_order 출력에 orders 없음 · 출력 − 카탈로그 = 종전 집합(ship_ready · internal_receipt {orders.lines.final_sale} · 나머지 {})',
  (select bool_and(k = any (pg_temp.cset(pg_temp.j(:'n_cat_fi'))) and k = any (pg_temp.pset(pg_temp.j(:'n_fi_set')->'docs'->0))
                   and k = any (pg_temp.cset(pg_temp.j(:'n_cat_ir'))) and k = any (pg_temp.pset(pg_temp.j(:'n_ir_set')->'docs'->0))
                   and k = any (pg_temp.cset(pg_temp.j(:'n_cat_sr'))) and k = any (pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0))
                   and not (k = any (pg_temp.cset(pg_temp.j(:'n_cat_cr'))))) from unnest(array['totals.line_count', 'totals.qty_total', 'totals.qty_total_ea', 'orders.line_count', 'orders.qty_total', 'orders.qty_total_ea']) k)
  and (select bool_and(k = any (pg_temp.cset(pg_temp.j(:'n_cat_so'))) and k = any (pg_temp.pset(pg_temp.j(:'n_so_plain')->'docs'->0))) from unnest(array['totals.line_count', 'totals.qty_total', 'totals.qty_total_ea']) k)
  and not ((pg_temp.j(:'n_so_plain')->'docs'->0) ? 'orders')
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fi_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))) = '{}'
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_ir_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))) = '{orders.lines.final_sale}'
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))) = '{orders.lines.final_sale}'
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so_plain')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so'))) = '{}',
  format('fi out−cat %s | ir %s | sr %s | so %s', pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fi_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_ir_set')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))),
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so_plain')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so')))));

-- ── V 값 ──
select (pg_temp.j(:'n_fi_set')->'docs'->0) as d_fi_set \gset
select pg_temp.chk('V1 final_invoice 60244(SO-20996 · 세트 줄 둘 · 콤보 줄 · 오더 셋): totals.qty_total = Σ 문서 줄 수량 칸 = invoice.total_qty · line_count = 줄 수 · qty_total_ea = Σ qty × so_invoice_line.pack_factor(표에서 바로) · ≠ qty_total · SO-20996 오더 블록 = 3 · 3 · 37 · 다른 오더 블록(세트 없음)은 ea "" · 장 line_count = Σ 오더 line_count',
  (pg_temp.j(:'d_fi_set')->'totals'->>'qty_total') = public.doc_fmt_qty(pg_temp.sum_q(pg_temp.all_lines(pg_temp.j(:'d_fi_set'))))
  and (pg_temp.j(:'d_fi_set')->'totals'->>'qty_total') = (pg_temp.j(:'d_fi_set')->'invoice'->>'total_qty')
  and (pg_temp.j(:'d_fi_set')->'totals'->>'line_count') = jsonb_array_length(pg_temp.all_lines(pg_temp.j(:'d_fi_set')))::text
  and (pg_temp.j(:'d_fi_set')->'totals'->>'qty_total_ea') = public.doc_fmt_qty((select sum(l.qty * l.pack_factor) from public.so_invoice_line l where l.invoice_id = :'inv_set'::uuid and l.kind = 'product'))
  and (pg_temp.j(:'d_fi_set')->'totals'->>'qty_total_ea') <> (pg_temp.j(:'d_fi_set')->'totals'->>'qty_total')
  and (select o->>'line_count' || '·' || (o->>'qty_total') || '·' || (o->>'qty_total_ea') from jsonb_array_elements(pg_temp.j(:'d_fi_set')->'orders') o where o->>'so_number' = 'SO-20996') = '3·3·37'
  and (select bool_and((o->>'qty_total_ea') = '' and (o->>'qty_total') = public.doc_fmt_qty(pg_temp.sum_q(o->'lines')) and (o->>'line_count') = jsonb_array_length(o->'lines')::text) from jsonb_array_elements(pg_temp.j(:'d_fi_set')->'orders') o where o->>'so_number' <> 'SO-20996')
  and (pg_temp.j(:'d_fi_set')->'totals'->>'line_count')::int = (select sum((o->>'line_count')::int) from jsonb_array_elements(pg_temp.j(:'d_fi_set')->'orders') o)
  and jsonb_array_length(pg_temp.j(:'d_fi_set')->'orders') = 3,
  format('totals %s | orders %s', (pg_temp.j(:'d_fi_set')->'totals') - 'lines_before_tax' - 'lines_tax' - 'lines_total' - 'charges_before_tax' - 'charges_tax' - 'charges_total' - 'order_discount' - 'surcharge' - 'charges_discount' - 'before_tax' - 'tax' - 'total' - 'deposit_applied' - 'credit_applied' - 'balance_forward' - 'paid' - 'due_label' - 'due_amount' - 'balance_due' - 'credits',
         (select string_agg((o->>'so_number') || '=' || (o->>'line_count') || '·' || (o->>'qty_total') || '·' || coalesce(nullif(o->>'qty_total_ea', ''), '""'), ' ' order by o->>'so_number') from jsonb_array_elements(pg_temp.j(:'d_fi_set')->'orders') o)));
select pg_temp.chk('V2 internal_receipt 60244 = final_invoice 60244 의 셋과 같다(장 · 오더마다) · final_invoice 60293(오더 둘 · 콤보): 장 = Σ 오더 · ea = "" · 세트 없는 인보이스 ' || :'inv_plain_no' || ': ea = "" · qty_total = invoice.total_qty · 오더 하나 블록 = 장',
  (pg_temp.j(:'n_ir_set')->'docs'->0->'totals'->'line_count') = (pg_temp.j(:'d_fi_set')->'totals'->'line_count') and (pg_temp.j(:'n_ir_set')->'docs'->0->'totals'->'qty_total') = (pg_temp.j(:'d_fi_set')->'totals'->'qty_total') and (pg_temp.j(:'n_ir_set')->'docs'->0->'totals'->'qty_total_ea') = (pg_temp.j(:'d_fi_set')->'totals'->'qty_total_ea')
  and (select jsonb_agg(jsonb_build_object('n', o->>'so_number', 'c', o->>'line_count', 'q', o->>'qty_total', 'e', o->>'qty_total_ea') order by o->>'so_number') from jsonb_array_elements(pg_temp.j(:'n_ir_set')->'docs'->0->'orders') o)
    = (select jsonb_agg(jsonb_build_object('n', o->>'so_number', 'c', o->>'line_count', 'q', o->>'qty_total', 'e', o->>'qty_total_ea') order by o->>'so_number') from jsonb_array_elements(pg_temp.j(:'d_fi_set')->'orders') o)
  and jsonb_array_length(pg_temp.j(:'n_fi_two')->'docs'->0->'orders') = 2
  and (pg_temp.j(:'n_fi_two')->'docs'->0->'totals'->>'qty_total')::numeric = (select sum((o->>'qty_total')::numeric) from jsonb_array_elements(pg_temp.j(:'n_fi_two')->'docs'->0->'orders') o)
  and (pg_temp.j(:'n_fi_two')->'docs'->0->'totals'->>'qty_total_ea') = '' and (pg_temp.j(:'n_fi_two')->'docs'->0->'totals'->>'qty_total') = (pg_temp.j(:'n_fi_two')->'docs'->0->'invoice'->>'total_qty')
  and (pg_temp.j(:'n_fi_plain')->'docs'->0->'totals'->>'qty_total_ea') = '' and (pg_temp.j(:'n_fi_plain')->'docs'->0->'totals'->>'qty_total') = (pg_temp.j(:'n_fi_plain')->'docs'->0->'invoice'->>'total_qty')
  and (pg_temp.j(:'n_fi_plain')->'docs'->0->'totals'->>'qty_total') = public.doc_fmt_qty(pg_temp.sum_q(pg_temp.j(:'n_fi_plain')->'docs'->0->'orders'->0->'lines'))
  and (pg_temp.j(:'n_fi_plain')->'docs'->0->'orders'->0->'qty_total') = (pg_temp.j(:'n_fi_plain')->'docs'->0->'totals'->'qty_total') and (pg_temp.j(:'n_fi_plain')->'docs'->0->'orders'->0->'line_count') = (pg_temp.j(:'n_fi_plain')->'docs'->0->'totals'->'line_count'),
  format('ir %s | two %s | plain %s', pg_temp.j(:'n_ir_set')->'docs'->0->'totals'->>'qty_total_ea', pg_temp.j(:'n_fi_two')->'docs'->0->'totals'->>'qty_total', pg_temp.j(:'n_fi_plain')->'docs'->0->'totals'->>'qty_total'));
select pg_temp.chk('V3 sales_order ' || :'so_plain_no' || '(세트 · 콤보 없음) · SO-21142(콤보 · 구성품 줄 있음): totals 셋 = doc_qty_totals(so_proforma 의 원천 줄)(같은 출처 · 항등) · line_count = 찍힌 줄 수(콤보 = 세트 하나) · 구성품 SKU 는 찍힌 줄에 없다 · qty_total = Σ 수량 칸 · ea = "" · 줄 열쇠 무변(pack_factor 안 실림) · 열린 오더에 세트 줄 없음(실측)',
  (pg_temp.j(:'n_so_plain')->'docs'->0->'totals'->'line_count') = (public.doc_qty_totals(public.so_proforma(array[:'so_plain'::uuid])->'orders'->0->'lines')->'line_count')
  and (pg_temp.j(:'n_so_plain')->'docs'->0->'totals'->'qty_total') = (public.doc_qty_totals(public.so_proforma(array[:'so_plain'::uuid])->'orders'->0->'lines')->'qty_total')
  and (pg_temp.j(:'n_so_plain')->'docs'->0->'totals'->'qty_total_ea') = (public.doc_qty_totals(public.so_proforma(array[:'so_plain'::uuid])->'orders'->0->'lines')->'qty_total_ea')
  and (pg_temp.j(:'n_so_combo')->'docs'->0->'totals'->'qty_total') = (public.doc_qty_totals(public.so_proforma(array[:'so_combo'::uuid])->'orders'->0->'lines')->'qty_total')
  and (pg_temp.j(:'n_so_plain')->'docs'->0->'totals'->>'qty_total') = public.doc_fmt_qty(pg_temp.sum_q(pg_temp.j(:'n_so_plain')->'docs'->0->'lines'))
  and (pg_temp.j(:'n_so_plain')->'docs'->0->'totals'->>'line_count') = jsonb_array_length(pg_temp.j(:'n_so_plain')->'docs'->0->'lines')::text and (pg_temp.j(:'n_so_plain')->'docs'->0->'totals'->>'line_count')::int > 0
  and (pg_temp.j(:'n_so_combo')->'docs'->0->'totals'->>'line_count') = jsonb_array_length(pg_temp.j(:'n_so_combo')->'docs'->0->'lines')::text
  and (pg_temp.j(:'n_so_combo')->'docs'->0->'totals'->>'line_count')::int = (select count(*) from public.so_line sl where sl.so_id = :'so_combo'::uuid and sl.combo_line_id is null)
  and (select count(*) from public.so_line sl where sl.so_id = :'so_combo'::uuid and sl.combo_line_id is not null) > 0
  and not exists (select 1 from public.so_line sl where sl.so_id = :'so_combo'::uuid and sl.combo_line_id is not null and sl.sku in (select l->>'sku' from jsonb_array_elements(pg_temp.j(:'n_so_combo')->'docs'->0->'lines') l))
  and (pg_temp.j(:'n_so_combo')->'docs'->0->'totals'->>'qty_total') = public.doc_fmt_qty(pg_temp.sum_q(pg_temp.j(:'n_so_combo')->'docs'->0->'lines'))
  and (pg_temp.j(:'n_so_combo')->'docs'->0->'totals'->>'qty_total_ea') = '' and (pg_temp.j(:'n_so_plain')->'docs'->0->'totals'->>'qty_total_ea') = ''
  and not exists (select 1 from public.so s join public.so_line sl on sl.so_id = s.id where sl.pack_factor > 1 and s.status not in ('fulfilled', 'cancelled'))
  and not ((pg_temp.j(:'n_so_plain')->'docs'->0->'lines'->0) ? 'pack_factor') and not ((pg_temp.j(:'n_fi_set')->'docs'->0->'orders'->0->'lines'->0) ? 'pack_factor'),
  format('so_plain %s | so_combo %s', (pg_temp.j(:'n_so_plain')->'docs'->0->'totals') - 'lines_before_tax' - 'lines_tax' - 'lines_total' - 'charges_before_tax' - 'charges_tax' - 'charges_total' - 'order_discount' - 'surcharge' - 'charges_discount' - 'before_tax' - 'tax' - 'total' - 'prepaid' - 'due_amount',
         (pg_temp.j(:'n_so_combo')->'docs'->0->'totals') - 'lines_before_tax' - 'lines_tax' - 'lines_total' - 'charges_before_tax' - 'charges_tax' - 'charges_total' - 'order_discount' - 'surcharge' - 'charges_discount' - 'before_tax' - 'tax' - 'total' - 'prepaid' - 'due_amount'));
select pg_temp.chk('V4 ship_ready(packed ' || :'so_packed_no' || ' · 직원 로그인 꼴 · so_finalize 미리 보기): docs[0] totals.qty_total = Σ 수량 칸 = invoice.total_qty · line_count = 줄 수 · orders[0] 셋 = 장(오더 하나) · ea 는 pack_factor 로 셈(미리 보기 원본 줄의 pack_factor 와 대조)',
  (pg_temp.j(:'n_sr')->'docs'->0->'totals'->>'qty_total') = public.doc_fmt_qty(pg_temp.sum_q(pg_temp.all_lines(pg_temp.j(:'n_sr')->'docs'->0)))
  and (pg_temp.j(:'n_sr')->'docs'->0->'totals'->>'qty_total') = (pg_temp.j(:'n_sr')->'docs'->0->'invoice'->>'total_qty')
  and (pg_temp.j(:'n_sr')->'docs'->0->'totals'->>'line_count') = jsonb_array_length(pg_temp.all_lines(pg_temp.j(:'n_sr')->'docs'->0))::text
  and (pg_temp.j(:'n_sr')->'docs'->0->'orders'->0->'qty_total') = (pg_temp.j(:'n_sr')->'docs'->0->'totals'->'qty_total') and (pg_temp.j(:'n_sr')->'docs'->0->'orders'->0->'qty_total_ea') = (pg_temp.j(:'n_sr')->'docs'->0->'totals'->'qty_total_ea')
  and (pg_temp.j(:'n_sr')->'docs'->0->'totals'->>'qty_total_ea') = (public.doc_qty_totals(pg_temp.j(:'n_pv')->'docs'->0->'orders'->0->'lines')->>'qty_total_ea')
  and (pg_temp.j(:'n_sr')->'docs'->0->'totals'->>'qty_total_ea') = case when (select sum((l->>'qty')::numeric * coalesce((l->>'pack_factor')::numeric, 1)) from jsonb_array_elements(pg_temp.j(:'n_pv')->'docs'->0->'orders'->0->'lines') l) = (select sum((l->>'qty')::numeric) from jsonb_array_elements(pg_temp.j(:'n_pv')->'docs'->0->'orders'->0->'lines') l) then '' else public.doc_fmt_qty((select sum((l->>'qty')::numeric * coalesce((l->>'pack_factor')::numeric, 1)) from jsonb_array_elements(pg_temp.j(:'n_pv')->'docs'->0->'orders'->0->'lines') l)) end,
  format('sr totals %s', (pg_temp.j(:'n_sr')->'docs'->0->'totals') - 'lines_before_tax' - 'lines_tax' - 'lines_total' - 'charges_before_tax' - 'charges_tax' - 'charges_total' - 'order_discount' - 'surcharge' - 'charges_discount' - 'before_tax' - 'tax' - 'total' - 'deposit_applied' - 'credit_applied' - 'balance_forward' - 'paid' - 'due_label' - 'due_amount' - 'balance_due' - 'credits'));

-- ── L 함수 모양 ──
select pg_temp.chk('L1 함수 모양: ACL 다섯이 머리와 같다 · doc_qty_totals = postgres · service_role 만(authenticated · anon 못 부른다) · immutable · invoker · fmt · so STABLE · catalog IMMUTABLE · preview VOLATILE · comment 다섯에 doc-qty-1 · 여섯 함수 하나씩',
  coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') = :'fmt_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') = :'cat_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), '(none)') = :'so_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), '(none)') = :'inv_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure), '(none)') = :'pv_acl_head'
  and not has_function_privilege('authenticated', 'public.doc_qty_totals(jsonb)', 'execute') and not has_function_privilege('anon', 'public.doc_qty_totals(jsonb)', 'execute') and has_function_privilege('service_role', 'public.doc_qty_totals(jsonb)', 'execute')
  and (select provolatile::text || prosecdef::text from pg_proc where oid = 'public.doc_qty_totals(jsonb)'::regprocedure) = 'ifalse'
  and (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) = 's' and (select provolatile from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) = 's'
  and (select provolatile from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) = 'i' and (select provolatile from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure) = 'v' and (select provolatile from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) = 's'
  and (select bool_and(coalesce(obj_description(oid, 'pg_proc'), '') ~ 'doc-qty-1') from pg_proc where pronamespace = 'public'::regnamespace and proname in ('doc_qty_totals', 'so_invoice_preview', 'doc_data_invoice_fmt', 'doc_data_so', 'doc_field_catalog'))
  and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('doc_qty_totals', 'doc_data_invoice', 'so_invoice_preview', 'doc_data_invoice_fmt', 'doc_data_so', 'doc_field_catalog')) = 6,
  format('qty acl %s', (select proacl::text from pg_proc where oid = 'public.doc_qty_totals(jsonb)'::regprocedure)));
\endif

-- ── Z 실물 무접촉 ──
select pg_temp.chk('Z1 실물 무접촉: so_invoice · so_invoice_line · so · so_line 수 · 마지막 갱신 · mail_outbox · doc_file 수 · doc_template · doc_template_active 머리와 같다 · request.jwt.claims 비었음',
  (select count(*) from public.so_invoice) || '|' || (select count(*) from public.so_invoice_line) || '|' || (select count(*) from public.so) || '|' || (select count(*) from public.so_line) || '|' || (select coalesce(max(updated_at)::text, '') from public.so) || '|' || (select coalesce(max(updated_at)::text, '') from public.so_invoice)
  || '|' || (select count(*) from public.mail_outbox) || '|' || (select count(*) from public.doc_file) || '|' || (select md5(string_agg(kind || version || md5(body), '|' order by kind, version)) from public.doc_template) || '|' || (select md5(string_agg(kind || template_id::text, '|' order by kind)) from public.doc_template_active) = :'snap_rows'
  and coalesce(current_setting('request.jwt.claims', true), '') = '',
  'snap');
select 'begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text as elapsed;
\pset tuples_only off
\pset format aligned
rollback;
-- 기대 OK: 시험(-v mig) 13(O1 G1 N0 T1 T2 T3 I1 T4 V1 V2 V3 V4 L1 + Z1 = 14 줄) · 마른(적용 전 · -v mig 없음) 2(G0 Z1) · 확인(적용 뒤 · -v mig 없음) 9(G0 N0 T4 V1 V2 V3 V4 L1 Z1)
