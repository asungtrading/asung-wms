-- srs-1 검증 — supabase/migrations/20261027023008_srs_1_ship_ready_mail_so_numbers.sql (판정 787 invoice.so_numbers · 판정 788 orders.ship_to_repeat · asung-doc §2 · §4 · so-module §66)
--   시험 적용 + 검증(Claude Code · rollback): cd ~/asung/asung-wms && set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027023008_srs_1_ship_ready_mail_so_numbers.sql -f supabase/tests/srs_1_check.sql 2>&1 | tee /tmp/srs_1.out
--   확인 실행(Caleb · 적용 뒤 · -v mig 없음): 같은 명령에서 -v mig 만 뺀다 · 갈래는 DB 의 doc_data_invoice_fmt prosrc md5 로 가른다(옛 판 a0c3f58d = bgr-1d · 새 판 = srs-1)
--   기대 OK 수(통과한 실행에서 받아 적음) — 파일 끝 「기대 OK」 주석
--   ⚠️ 재료 전부 가짜(rollback) — 직원 1(sales) · 손님 1 · 연락처 1 · 제품 1 · packed 오더 3(SO-79921 · 79922 배송지 다름 · 79923 = 79921 과 같은 배송지 · srm-1 의 79911 · 79912 와 다르게) · 표본(인보이스 · 크레딧 · confirmed 오더 · 있으면 묶음 인보이스 60073)은 실물을 읽기만
--   ⚠️ 테스트 DB 는 mail_enabled on · cron 이 돈다 — 반드시 rollback 으로 끝난다 · doc_mail_pdf_claim · mail_claim 은 부르지 않는다 · 시퀀스는 당기지 않는다(so 직접 insert) · 메일은 미리 보기(commit false)만 — 큐에 줄을 넣지 않는다
--   ⚠️ ar-3(docs/probes/ImsLoadOpening.gs)가 같은 테스트 DB 를 쓴다 — so_invoice* · so_payment* · so_opening_load 는 읽기만 · 쓰지 않는다
--   「카탈로그 ↔ doc_data 열쇠 대조」 — 지시서가 가리킨 supabase/tests/doc_1b* 는 레포에 없다(doc-1b1 ④ 는 v_cat · v_doc 를 선언만) → 여기서 세운다:
--     출력 열쇠(pg_temp.paths · 목록은 색인 없이 경로로) 와 카탈로그(allowed ∪ sections) 를 양쪽 차집합으로 — 옛 = 새(새 열쇠 하나만 다르다) · 새 판의 차집합은 적어 둔 집합과 같다
\set ON_ERROR_STOP on
\pset pager off
-- ── 머리(잠금 없음) — 시퀀스 · 함수 판 · 재료 열쇠 · 실물 스냅샷 ──
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select :so_seq_last as so_seq_before, :'so_seq_called' as so_called_before, :inv_seq_last as inv_seq_before, :'inv_seq_called' as inv_called_before;
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace), '(none)') as fmt_md5_head \gset
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_field_catalog' and pronamespace = 'public'::regnamespace), '(none)') as cat_md5_head \gset
select (:'fmt_md5_head' = 'a0c3f58dbd760a01615ee7996556e7fb')::int as is_old \gset
select ((:{?mig}) or :is_old = 0)::int as expect_pass \gset
select :'fmt_md5_head' as fmt_md5_head, :'cat_md5_head' as cat_md5_head, :is_old as is_old, :expect_pass as expect_pass;
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') as fmt_acl_head \gset
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') as cat_acl_head \gset
select value as subj_head from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject' \gset
select (:'subj_head' = 'PROFORMA INVOICE - Asung Trading Inc.')::int as subj_is_seed \gset
select :'subj_head' as subj_head, :subj_is_seed as subj_is_seed;
select md5(string_agg(kind || '|' || key || '|' || value || '|' || coalesce(updated_by::text, ''), '|' order by kind, key)) || ' ' || count(*) as snap_ds from public.doc_setting where not (kind = 'ship_ready' and key = 'mail_subject') \gset
select md5(coalesce(string_agg((to_jsonb(t) - 'attachments')::text, '|' order by t.id), '')) || ' ' || count(*) as snap_ob from public.mail_outbox t \gset
select md5(coalesce(string_agg(t.id::text || ':' || t.path || ':' || t.sha256, '|' order by t.id), '')) || ' ' || count(*) as snap_df from public.doc_file t \gset
select count(*) as n_sr_head from public.mail_outbox where kind = 'doc_ship_ready' \gset
select id::text as wh from public.ref_warehouse where name = 'Asung Trading Inc.' and is_active \gset
select id::text as cur from public.ref_currency where code = 'CAD' limit 1 \gset
select id::text as taxr from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active limit 1 \gset
select id::text as acc98 from public.ref_account where code = '_98_' \gset
select id::text as term30 from public.ref_payment_term where name = 'Net 30' limit 1 \gset
select id::text as inv_s from public.so_invoice where status = 'issued' order by issued_on desc, created_at desc limit 1 \gset
select id::text as cr_s from public.so_credit order by created_at desc limit 1 \gset
select id::text as so_s from public.so where status = 'confirmed' order by created_at desc limit 1 \gset
select coalesce((select id::text from public.so_invoice where invoice_number = '60073'), '') as inv_m \gset
select (:'inv_m' <> '')::int as has_m \gset
select left(:'inv_s', 8) as inv_sample, left(:'cr_s', 8) as cr_sample, left(:'so_s', 8) as so_sample, :has_m as has_merged_60073;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\pset format unaligned
\pset tuples_only on
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
-- 가짜 직원(sales 쓰기) 신원으로 창구를 부른다 — postgres 세션 그대로 부르지 않는다 · 예외는 'ERR <sqlstate>: <문장>' 글자로
create function pg_temp.asu(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-00000057a201","role":"authenticated"}', true);
  execute 'set local role authenticated';
  execute p_sql into v_out;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);   -- 비운다 — 남겨 두면 마이그레이션의 update 가 ims_touch 에서 가짜 직원을 updated_by 로 적는다(1 회차 D4 · 실제 적용은 psql = null)
  return v_out;
exception when others then
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 열쇠 경로 — 목록은 색인 없이(orders.lines.sku) · 목록 이름 자체도 하나(섹션) · 값 하나는 경로
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
create function pg_temp.strip(p jsonb) returns jsonb language sql as $$
  select case when q ? 'orders' then jsonb_set(q, '{orders}', (select coalesce(jsonb_agg(o - 'ship_to_repeat' order by ord), '[]'::jsonb) from jsonb_array_elements(q->'orders') with ordinality t(o, ord))) else q end
  from (select jsonb_set(jsonb_set(p, '{doc}', coalesce(p->'doc', '{}'::jsonb) - 'printed_at'), '{invoice}', coalesce(p->'invoice', '{}'::jsonb) - 'calc_at' - 'so_numbers') as q) s $$;
create function pg_temp.rep(p jsonb) returns text language sql as $$ select coalesce((select string_agg(coalesce(o->>'ship_to_repeat', '?'), ',' order by ord) from jsonb_array_elements(p->'orders') with ordinality t(o, ord)), '') $$;
create function pg_temp.strip_docs(p jsonb) returns jsonb language sql as $$ select (select coalesce(jsonb_agg(pg_temp.strip(d) order by ord), '[]'::jsonb) from jsonb_array_elements(p->'docs') with ordinality t(d, ord)) $$;

-- ── 가짜 재료(replica · 트리거 없이) ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values ('00000000-0000-4000-8000-00000057a201', 'srs1-sa@example.invalid', 'srs1 sales', 'worker', '["sales"]', true);
insert into public.customer (name, currency_id, currency_code, default_location_id) values ('srs1 Cust', :'cur'::uuid, 'CAD', :'wh'::uuid) returning id::text as k1 \gset
insert into public.customer_contact (customer_id, name, email, is_default, is_active) values (:'k1'::uuid, 'Srs One', 'srs.one@example.invalid', true, true);
insert into public.product (name, sku, source, uom_name) values ('Srs1 P1', 'SRS1-P1', 'manual', 'EA') returning id::text as p1 \gset
create function pg_temp.mk_so(p_no text) returns uuid language plpgsql as $$
declare v_id uuid;
begin
  insert into public.so (so_number, customer_id, bill_to_customer_id, channel, intake, status, currency_id, currency_code, location_id, location_name, order_date, ref, payment_term_id, payment_term_name,
                         tax_rule_id, tax_rule, tax_rule_manual, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country,
                         ship_to_company, ship_to_line1, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country, sale_account_id, sale_account_code, confirmed_at)
  values (p_no, current_setting('d.k1')::uuid, current_setting('d.k1')::uuid, 'warehouse', 'manual', 'packed', current_setting('d.cur')::uuid, 'CAD', current_setting('d.wh')::uuid, 'Asung Trading Inc.', public.ims_today(), 'PO-' || p_no, current_setting('d.term')::uuid, 'Net 30',
          current_setting('d.taxr')::uuid, 'HST ON (Sale)', false, 'srs1 Cust', '1 Bill St', 'Toronto', 'ON', 'M1M 1M1', 'Canada',
          'Ship ' || p_no, '9 Ship Rd', 'Markham', 'ON', 'L3R 0A1', 'Canada', current_setting('d.acc98')::uuid, '_98_', now())
  returning id into v_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped, list_price, discount_pct, discount_source, unit_price)
  values (v_id, 1, current_setting('d.p1')::uuid, 'SRS1-P1', 'Srs1 P1', 'EA', 1, 2, 0, 10, 0, 'customer', 10);
  return v_id;
end $$;
select set_config('d.k1', :'k1', true), set_config('d.cur', :'cur', true), set_config('d.wh', :'wh', true), set_config('d.term', :'term30', true), set_config('d.taxr', :'taxr', true), set_config('d.acc98', :'acc98', true), set_config('d.p1', :'p1', true);
select pg_temp.mk_so('SO-79921')::text as so1, pg_temp.mk_so('SO-79922')::text as so2, pg_temp.mk_so('SO-79923')::text as so3 \gset
update public.so set ship_to_company = ' ship so-79921 ' where id = :'so3'::uuid;   -- 판정 788: 79923 의 배송지 = 79921 과 같다(대소문자 · 앞뒤 공백만 다르게 — lower(btrim) 비교)
select id::text as l1 from public.so_line where so_id = :'so1'::uuid \gset
select id::text as l2 from public.so_line where so_id = :'so2'::uuid \gset
select id::text as l3 from public.so_line where so_id = :'so3'::uuid \gset
-- 창(Ship & invoice)이 보내는 ref — 오더 하나 · 오더 둘을 한 번에(같은 손님 · 같은 규칙 = 한 묶음 = 한 장)
select jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so1', 'picks', jsonb_build_array(jsonb_build_object('line_id', :'l1', 'bin', 'SRS1-BIN', 'qty', 2)))))::text as ref1 \gset
select jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so1', 'picks', jsonb_build_array(jsonb_build_object('line_id', :'l1', 'bin', 'SRS1-BIN', 'qty', 2))),
                                                      jsonb_build_object('so_id', :'so2', 'picks', jsonb_build_array(jsonb_build_object('line_id', :'l2', 'bin', 'SRS1-BIN', 'qty', 2)))))::text as ref12 \gset
select jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so1', 'picks', jsonb_build_array(jsonb_build_object('line_id', :'l1', 'bin', 'SRS1-BIN', 'qty', 2))),
                                                      jsonb_build_object('so_id', :'so3', 'picks', jsonb_build_array(jsonb_build_object('line_id', :'l3', 'bin', 'SRS1-BIN', 'qty', 2)))))::text as ref13 \gset
set local session_replication_role = origin;
-- 창구 부르기 글(가짜 직원) — 옛 · 새 같은 글
select format('select public.doc_data(''ship_ready'', %L)::text', :'ref1'::jsonb) as q_sr1,
       format('select public.doc_data(''ship_ready'', %L)::text', :'ref12'::jsonb) as q_sr12,
       format('select public.doc_data(''ship_ready'', %L)::text', :'ref13'::jsonb) as q_sr13,
       case when :has_m = 1 then format('select public.doc_data(''final_invoice'', %L)::text', jsonb_build_object('invoice_id', :'inv_m')) else 'select ''{}''::text' end as q_fm,
       format('select public.doc_data(''final_invoice'', %L)::text', jsonb_build_object('invoice_id', :'inv_s')) as q_fi,
       format('select public.doc_data(''internal_receipt'', %L)::text', jsonb_build_object('invoice_id', :'inv_s')) as q_ir,
       format('select public.doc_data(''credit_note'', %L)::text', jsonb_build_object('credit_id', :'cr_s')) as q_cr,
       format('select public.doc_data(''sales_order'', %L)::text', jsonb_build_object('so_id', :'so_s')) as q_so,
       format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, false)::text', :'ref1'::jsonb) as q_m1,
       format('select public.doc_mail_send(''ship_ready'', %L, null, null, null, false)::text', :'ref12'::jsonb) as q_m12,
       format('select public.doc_mail_send(''sales_order'', %L, null, null, null, false)::text', jsonb_build_object('so_id', :'so_s')) as q_mso,
       format('select public.doc_mail_send(''final_invoice'', %L, null, null, null, false)::text', jsonb_build_object('invoice_id', :'inv_s')) as q_mfi \gset

\if :{?mig}
-- ── O 시험에서만: 적용 전 옛 판 — 옛 출력을 받아 둔다 ──
select public.doc_field_catalog('final_invoice')::text as o_cat_fi, public.doc_field_catalog('ship_ready')::text as o_cat_sr, public.doc_field_catalog('internal_receipt')::text as o_cat_ir,
       public.doc_field_catalog('credit_note')::text as o_cat_cr, public.doc_field_catalog('sales_order')::text as o_cat_so \gset
select pg_temp.asu(:'q_sr1') as o_sr1, pg_temp.asu(:'q_sr12') as o_sr12, pg_temp.asu(:'q_sr13') as o_sr13, pg_temp.asu(:'q_fi') as o_fi, pg_temp.asu(:'q_ir') as o_ir, pg_temp.asu(:'q_cr') as o_cr, pg_temp.asu(:'q_so') as o_so, pg_temp.asu(:'q_fm') as o_fm \gset
select pg_temp.asu(:'q_m1') as o_m1, pg_temp.asu(:'q_mso') as o_mso, pg_temp.asu(:'q_mfi') as o_mfi \gset
select pg_temp.chk('O1 시험에서만: 적용 전 = bgr-1d 판(fmt md5 a0c3f58d) · 카탈로그 셋에 invoice.so_numbers 없음 · 새 제목 글은 옛 카탈로그에서 unknown_field · ship_ready 미리 보기 제목 = 설정 글 그대로(자리표 없음) · 옛 출력 여섯 + 미리 보기 셋 받음',
  :is_old = 1 and :'cat_md5_head' = '7a9edf38a1903ddc3398a9df700882e8'
  and not ((pg_temp.j(:'o_cat_fi')->'allowed') ? 'invoice.so_numbers') and not ((pg_temp.j(:'o_cat_sr')->'allowed') ? 'invoice.so_numbers') and not ((pg_temp.j(:'o_cat_ir')->'allowed') ? 'invoice.so_numbers')
  and (public.doc_template_check('ship_ready', 'PROFORMA INVOICE {{invoice.so_numbers}} - Asung Trading Inc.', 'text')->'problems'->0->>'code') = 'unknown_field'
  and (pg_temp.j(:'o_m1')->>'subject') = btrim(:'subj_head')
  and not ((pg_temp.j(:'o_sr13')->'docs'->0->'orders'->0) ? 'ship_to_repeat')
  and left(:'o_sr1', 1) = '{' and left(:'o_sr12', 1) = '{' and left(:'o_sr13', 1) = '{' and left(:'o_fm', 1) = '{' and left(:'o_fi', 1) = '{' and left(:'o_ir', 1) = '{' and left(:'o_cr', 1) = '{' and left(:'o_so', 1) = '{' and left(:'o_mso', 1) = '{' and left(:'o_mfi', 1) = '{',
  format('%s | %s | sr1 %s | sr12 %s | fi %s | ir %s | cr %s | so %s | m1 %s | mso %s | mfi %s', :'fmt_md5_head', :'cat_md5_head', left(:'o_sr1', 60), left(:'o_sr12', 60), left(:'o_fi', 60), left(:'o_ir', 60), left(:'o_cr', 60), left(:'o_so', 60), left(:'o_m1', 80), left(:'o_mso', 60), left(:'o_mfi', 60)));
-- ── O2 시드가 아닌 값은 안 덮는다 — savepoint 안에서 다른 글로 바꿔 놓고 마이그레이션 → 그대로 · 되돌린 뒤 진짜 적용 ──
savepoint srs1_custom;
update public.doc_setting set value = 'srs1 custom {{bill_to.name}} subject' where kind = 'ship_ready' and key = 'mail_subject';
\echo '── 시험 적용 1(savepoint · 직원이 고친 값 · rollback to savepoint):' :mig
\i :mig
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('O2 시험에서만: 직원이 고친 제목은 안 덮는다 — 마이그레이션이 돌았는데(fmt 몸에 so_numbers) 값은 그대로',
  (select value from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject') = 'srs1 custom {{bill_to.name}} subject'
  and (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) ~ 'so_numbers',
  (select value from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject'));
rollback to savepoint srs1_custom;
select pg_temp.chk('O3 시험에서만: savepoint 되돌린 뒤 옛 판 · 값 머리 그대로',
  (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) = 'a0c3f58dbd760a01615ee7996556e7fb'
  and (select value from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject') = :'subj_head', 'sp');
\echo '── 시험 적용 2(rollback 됨):' :mig
\i :mig
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('G1 시험에서만: 적용 뒤 fmt · catalog 몸이 새 판 · 함수 하나씩 · fmt 에 so_numbers · catalog 에 invoice.so_numbers',
  (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> 'a0c3f58dbd760a01615ee7996556e7fb'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) <> '7a9edf38a1903ddc3398a9df700882e8'
  and (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_field_catalog') and pronamespace = 'public'::regnamespace) = 2
  and (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) ~ 'so_numbers'
  and (select prosrc from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) ~ 'invoice\.so_numbers',
  format('fmt %s cat %s', (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure)));
\else
select pg_temp.chk('G0 확인 실행: doc_data_invoice_fmt 가 있다 · 판 = ' || case when :is_old = 1 then '옛(bgr-1d · 적용 전 — 아래 갈래는 돌지 않는다)' else '새(srs-1 · 통과 갈래)' end,
  :'fmt_md5_head' <> '(none)', :'fmt_md5_head');
\endif

\if :expect_pass
-- ── 새 출력 ──
select public.doc_field_catalog('final_invoice')::text as n_cat_fi, public.doc_field_catalog('ship_ready')::text as n_cat_sr, public.doc_field_catalog('internal_receipt')::text as n_cat_ir,
       public.doc_field_catalog('credit_note')::text as n_cat_cr, public.doc_field_catalog('sales_order')::text as n_cat_so \gset
select pg_temp.asu(:'q_sr1') as n_sr1, pg_temp.asu(:'q_sr12') as n_sr12, pg_temp.asu(:'q_sr13') as n_sr13, pg_temp.asu(:'q_fi') as n_fi, pg_temp.asu(:'q_ir') as n_ir, pg_temp.asu(:'q_cr') as n_cr, pg_temp.asu(:'q_so') as n_so, pg_temp.asu(:'q_fm') as n_fm \gset
select value as subj_now from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject' \gset
select pg_temp.chk('N0 새 출력 여섯이 다 JSON(가짜 직원 sales 로 doc_data · ship_ready 는 so_finalize 미리 보기)',
  left(:'n_sr1', 1) = '{' and left(:'n_sr12', 1) = '{' and left(:'n_sr13', 1) = '{' and left(:'n_fm', 1) = '{' and left(:'n_fi', 1) = '{' and left(:'n_ir', 1) = '{' and left(:'n_cr', 1) = '{' and left(:'n_so', 1) = '{',
  format('sr1 %s | sr12 %s | fi %s | ir %s | cr %s | so %s', left(:'n_sr1', 100), left(:'n_sr12', 100), left(:'n_fi', 100), left(:'n_ir', 100), left(:'n_cr', 100), left(:'n_so', 100)));

\if :{?mig}
-- ── T 옛 = 새 (시험에서만) ──
select pg_temp.chk('T1 카탈로그: final_invoice · ship_ready · internal_receipt 의 allowed = 옛 + invoice.so_numbers + orders.ship_to_repeat(딱 둘) · sections · required 그대로 · credit_note · sales_order 는 바이트 무변',
  (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_fi')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_fi')->'allowed') union all select 'invoice.so_numbers' union all select 'orders.ship_to_repeat') t(x))
  and (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_sr')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_sr')->'allowed') union all select 'invoice.so_numbers' union all select 'orders.ship_to_repeat') t(x))
  and (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_ir')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_ir')->'allowed') union all select 'invoice.so_numbers' union all select 'orders.ship_to_repeat') t(x))
  and (pg_temp.j(:'n_cat_fi') - 'allowed') = (pg_temp.j(:'o_cat_fi') - 'allowed') and (pg_temp.j(:'n_cat_sr') - 'allowed') = (pg_temp.j(:'o_cat_sr') - 'allowed') and (pg_temp.j(:'n_cat_ir') - 'allowed') = (pg_temp.j(:'o_cat_ir') - 'allowed')
  and :'n_cat_cr' = :'o_cat_cr' and :'n_cat_so' = :'o_cat_so',
  format('fi new %s old %s | sr new %s', jsonb_array_length(pg_temp.j(:'n_cat_fi')->'allowed'), jsonb_array_length(pg_temp.j(:'o_cat_fi')->'allowed'), jsonb_array_length(pg_temp.j(:'n_cat_sr')->'allowed')));
select pg_temp.chk('T2 doc_data 옛 = 새(새 열쇠 invoice.so_numbers · orders[].ship_to_repeat · 시각 calc_at · printed_at 만 떼고): ship_ready 한 오더 · 두 오더 × 2(docs · groups) · final_invoice · internal_receipt · 묶음 인보이스(있으면) · credit_note · sales_order 바이트 무변',
  pg_temp.strip_docs(pg_temp.j(:'n_sr1')) = pg_temp.strip_docs(pg_temp.j(:'o_sr1')) and (pg_temp.j(:'n_sr1')->'groups') = (pg_temp.j(:'o_sr1')->'groups')
  and pg_temp.strip_docs(pg_temp.j(:'n_sr12')) = pg_temp.strip_docs(pg_temp.j(:'o_sr12')) and (pg_temp.j(:'n_sr12')->'groups') = (pg_temp.j(:'o_sr12')->'groups')
  and pg_temp.strip_docs(pg_temp.j(:'n_sr13')) = pg_temp.strip_docs(pg_temp.j(:'o_sr13')) and (pg_temp.j(:'n_sr13')->'groups') = (pg_temp.j(:'o_sr13')->'groups')
  and (:has_m = 0 or pg_temp.strip_docs(pg_temp.j(:'n_fm')) = pg_temp.strip_docs(pg_temp.j(:'o_fm')))
  and pg_temp.strip_docs(pg_temp.j(:'n_fi')) = pg_temp.strip_docs(pg_temp.j(:'o_fi')) and pg_temp.strip_docs(pg_temp.j(:'n_ir')) = pg_temp.strip_docs(pg_temp.j(:'o_ir'))
  and pg_temp.strip_docs(pg_temp.j(:'n_cr')) = pg_temp.strip_docs(pg_temp.j(:'o_cr')) and pg_temp.strip_docs(pg_temp.j(:'n_so')) = pg_temp.strip_docs(pg_temp.j(:'o_so'))
  and not ((pg_temp.j(:'o_sr12')->'docs'->0->'invoice') ? 'so_numbers') and not ((pg_temp.j(:'o_fi')->'docs'->0->'invoice') ? 'so_numbers')
  and not ((pg_temp.j(:'n_cr')->'docs'->0) ? 'invoice') and not ((pg_temp.j(:'n_so')->'docs'->0) ? 'invoice'),
  format('sr12 old=%s new=%s | fi old=%s new=%s', left(:'o_sr12', 80), left(:'n_sr12', 80), left(:'o_fi', 80), left(:'n_fi', 80)));
-- 카탈로그 ↔ 출력 열쇠 대조 — 옛 차집합 = 새 차집합(양쪽) · 새 열쇠는 양쪽에 함께 들어온다
select pg_temp.chk('T3 열쇠 대조 옛 = 새: 출력 − 카탈로그 · 카탈로그 − 출력 이 세 kind(ship_ready 두 오더 · final_invoice · internal_receipt) 모두 옛과 같다(새 열쇠는 양쪽에 같이) · credit_note · sales_order 도 같다',
  pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_sr12')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_sr')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_sr')), pg_temp.pset(pg_temp.j(:'o_sr12')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fi')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_fi')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_fi')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_fi')), pg_temp.pset(pg_temp.j(:'n_fi')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_fi')), pg_temp.pset(pg_temp.j(:'o_fi')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_ir')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_ir')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_ir')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_ir')), pg_temp.pset(pg_temp.j(:'n_ir')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_ir')), pg_temp.pset(pg_temp.j(:'o_ir')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_cr'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_cr')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_cr')))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_so')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_so'))),
  format('sr out−cat old %s new %s | cat−out old %s new %s | fi out−cat new %s | cat−out new %s',
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_sr12')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_sr'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))),
         pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_sr')), pg_temp.pset(pg_temp.j(:'o_sr12')->'docs'->0)), pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0)),
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fi')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))), pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_fi')), pg_temp.pset(pg_temp.j(:'n_fi')->'docs'->0))));
\endif

-- ── T4 열쇠 대조(새 판 · 시험 · 확인 둘 다): 새 열쇠가 카탈로그와 출력 양쪽에 · 출력 − 카탈로그 는 적어 둔 집합(bgr-1d 가 final_invoice 카탈로그에만 넣은 orders.lines.final_sale 을 ship_ready · internal_receipt 출력도 낸다 — 이 차수 전부터) ──
select pg_temp.chk('T4 열쇠 대조(새 판): invoice.so_numbers · orders.ship_to_repeat 가 세 kind 의 카탈로그 · 출력 양쪽에 · credit_note · sales_order 출력엔 없다 · 출력 − 카탈로그 = ship_ready {orders.lines.final_sale} · internal_receipt {orders.lines.final_sale} · final_invoice {} · credit_note {} · sales_order {}',
  'invoice.so_numbers' = any (pg_temp.cset(pg_temp.j(:'n_cat_sr'))) and 'invoice.so_numbers' = any (pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0))
  and 'orders.ship_to_repeat' = any (pg_temp.cset(pg_temp.j(:'n_cat_sr'))) and 'orders.ship_to_repeat' = any (pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0))
  and 'orders.ship_to_repeat' = any (pg_temp.cset(pg_temp.j(:'n_cat_fi'))) and 'orders.ship_to_repeat' = any (pg_temp.pset(pg_temp.j(:'n_fi')->'docs'->0))
  and 'orders.ship_to_repeat' = any (pg_temp.cset(pg_temp.j(:'n_cat_ir'))) and 'orders.ship_to_repeat' = any (pg_temp.pset(pg_temp.j(:'n_ir')->'docs'->0))
  and not ('orders.ship_to_repeat' = any (pg_temp.cset(pg_temp.j(:'n_cat_cr')))) and not ('orders.ship_to_repeat' = any (pg_temp.cset(pg_temp.j(:'n_cat_so'))))
  and 'invoice.so_numbers' = any (pg_temp.cset(pg_temp.j(:'n_cat_fi'))) and 'invoice.so_numbers' = any (pg_temp.pset(pg_temp.j(:'n_fi')->'docs'->0))
  and 'invoice.so_numbers' = any (pg_temp.cset(pg_temp.j(:'n_cat_ir'))) and 'invoice.so_numbers' = any (pg_temp.pset(pg_temp.j(:'n_ir')->'docs'->0))
  and not ('invoice.so_numbers' = any (pg_temp.cset(pg_temp.j(:'n_cat_cr')))) and not ('invoice.so_numbers' = any (pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0)))
  and not ('invoice.so_numbers' = any (pg_temp.cset(pg_temp.j(:'n_cat_so')))) and not ('invoice.so_numbers' = any (pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0)))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))) = array['orders.lines.final_sale']
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_ir')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))) = array['orders.lines.final_sale']
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fi')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))) = '{}'::text[]
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_cr'))) = '{}'::text[]
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so'))) = '{}'::text[],
  format('sr out−cat %s | ir %s | fi %s | cr %s | so %s | sr cat−out %s',
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_ir')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))),
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fi')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_cr'))),
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so'))), pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.pset(pg_temp.j(:'n_sr12')->'docs'->0))));

-- ── D 값 ──
select pg_temp.chk('D1 ship_ready: 오더 둘 → 한 장 · invoice.so_numbers = "SO-79921, SO-79922"(오더 순서 = so_number 순) · 오더 하나 → "SO-79921" · groups[0].so_ids 에 둘 · invoice.number 는 여전히 없다 · calc_at 있다',
  jsonb_array_length(pg_temp.j(:'n_sr12')->'docs') = 1 and (pg_temp.j(:'n_sr12')->'docs'->0->'invoice'->>'so_numbers') = 'SO-79921, SO-79922'
  and jsonb_array_length(pg_temp.j(:'n_sr1')->'docs') = 1 and (pg_temp.j(:'n_sr1')->'docs'->0->'invoice'->>'so_numbers') = 'SO-79921'
  and jsonb_array_length(pg_temp.j(:'n_sr12')->'groups'->0->'so_ids') = 2
  and not ((pg_temp.j(:'n_sr12')->'docs'->0->'invoice') ? 'number') and (pg_temp.j(:'n_sr12')->'docs'->0->'invoice') ? 'calc_at',
  format('sr12 invoice %s | sr1 invoice %s', (pg_temp.j(:'n_sr12')->'docs'->0->'invoice')::text, (pg_temp.j(:'n_sr1')->'docs'->0->'invoice')::text));
select pg_temp.chk('D2 그리기 직접(postgres · 중립 jsonb): 빈 번호("" · 공백 · 없음)는 건너뛰고 orders 순서 그대로 "SO-1, SO-2" · 오더 없음 → "" · final_invoice 꼴도 같다',
  (public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
     '{"header":{"issued_on":"2026-10-26"},"orders":[{"so_number":"SO-1","lines":[]},{"so_number":"","lines":[]},{"so_number":"   ","lines":[]},{"lines":[]},{"so_number":"SO-2","lines":[]}],"charges":[],"payments":[],"totals":{}}'::jsonb)->'invoice'->>'so_numbers') = 'SO-1, SO-2'
  and (public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{},"orders":[],"charges":[],"payments":[],"totals":{}}'::jsonb)->'invoice'->>'so_numbers') = ''
  and (public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
     '{"header":{"number":"60001","issued_on":"2026-10-26"},"orders":[{"so_number":"SO-9","lines":[]},{"so_number":"SO-8","lines":[]}],"charges":[],"payments":[],"totals":{}}'::jsonb)->'invoice'->>'so_numbers') = 'SO-9, SO-8',
  (public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
     '{"header":{"issued_on":"2026-10-26"},"orders":[{"so_number":"SO-1","lines":[]},{"so_number":"","lines":[]},{"lines":[]},{"so_number":"SO-2","lines":[]}],"charges":[],"payments":[],"totals":{}}'::jsonb)->'invoice')::text);
select pg_temp.chk('D3 실물 인보이스 표본: final_invoice · internal_receipt 의 invoice.so_numbers = 그 인보이스의 오더 so_number 를 so_number 순으로 이은 글 · invoice.number 그대로',
  (pg_temp.j(:'n_fi')->'docs'->0->'invoice'->>'so_numbers') = (select string_agg(o.so_number, ', ' order by o.so_number) from public.so_invoice_order o where o.invoice_id = :'inv_s'::uuid)
  and (pg_temp.j(:'n_ir')->'docs'->0->'invoice'->>'so_numbers') = (select string_agg(o.so_number, ', ' order by o.so_number) from public.so_invoice_order o where o.invoice_id = :'inv_s'::uuid)
  and (pg_temp.j(:'n_fi')->'docs'->0->'invoice'->>'number') = (select i.invoice_number from public.so_invoice i where i.id = :'inv_s'::uuid),
  format('fi invoice %s', (pg_temp.j(:'n_fi')->'docs'->0->'invoice')::text));
select pg_temp.chk('D5 판정 788 ship_ready: 같은 배송지 두 오더(79921 · 79923 — 대소문자 · 공백만 다름) → ship_to_repeat [false, true] · 다른 배송지(79921 · 79922) → [false, false] · 오더 하나 → [false] · 오더 순서 그대로',
  pg_temp.rep(pg_temp.j(:'n_sr13')->'docs'->0) = 'false,true' and pg_temp.rep(pg_temp.j(:'n_sr12')->'docs'->0) = 'false,false' and pg_temp.rep(pg_temp.j(:'n_sr1')->'docs'->0) = 'false'
  and (pg_temp.j(:'n_sr13')->'docs'->0->'orders'->0->>'so_number') = 'SO-79921' and (pg_temp.j(:'n_sr13')->'docs'->0->'orders'->1->>'so_number') = 'SO-79923'
  and (pg_temp.j(:'n_sr13')->'docs'->0->'orders'->1->'ship_to'->>'company') = ' ship so-79921 ' and (pg_temp.j(:'n_sr13')->'docs'->0->'invoice'->>'so_numbers') = 'SO-79921, SO-79923',
  format('sr13 %s | sr12 %s | sr13 ship_to[1] %s', pg_temp.rep(pg_temp.j(:'n_sr13')->'docs'->0), pg_temp.rep(pg_temp.j(:'n_sr12')->'docs'->0), (pg_temp.j(:'n_sr13')->'docs'->0->'orders'->1->'ship_to')::text));
select pg_temp.chk('D6 판정 788 그리기 직접(중립 jsonb): [A, A(대소문자 · 공백 변형), B, A, contact 만 다른 A] → [false, true, false, true, true] · 두 오더 ship_to 둘 다 빈칸 → [false, true] · line2 만 다르면 false',
  pg_temp.rep(public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
     '{"header":{"number":"1"},"orders":[{"so_number":"SO-1","ship_to":{"company":"Acme","contact":"Ann","line1":"1 Main St","line2":"","city":"Toronto","state_province":"ON","postal_code":"M1M 1M1","country":"Canada"},"lines":[]},
                                           {"so_number":"SO-2","ship_to":{"company":" ACME ","contact":"Ann","line1":"1 main st","line2":"","city":"toronto","state_province":"on","postal_code":"m1m 1m1 ","country":"CANADA"},"lines":[]},
                                           {"so_number":"SO-3","ship_to":{"company":"Acme","contact":"Ann","line1":"2 Other St","line2":"","city":"Toronto","state_province":"ON","postal_code":"M1M 1M1","country":"Canada"},"lines":[]},
                                           {"so_number":"SO-4","ship_to":{"company":"Acme","contact":"Ann","line1":"1 Main St","line2":"","city":"Toronto","state_province":"ON","postal_code":"M1M 1M1","country":"Canada"},"lines":[]},
                                           {"so_number":"SO-5","ship_to":{"company":"Acme","contact":"Bob","phone":"416","line1":"1 Main St","line2":"","city":"Toronto","state_province":"ON","postal_code":"M1M 1M1","country":"Canada"},"lines":[]}],"charges":[],"payments":[],"totals":{}}'::jsonb)) = 'false,true,false,true,true'
  and pg_temp.rep(public.doc_data_invoice_fmt('internal_receipt', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[{"so_number":"SO-1","lines":[]},{"so_number":"SO-2","lines":[]}],"charges":[],"payments":[],"totals":{}}'::jsonb)) = 'false,true'
  and pg_temp.rep(public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{},"orders":[{"so_number":"SO-1","ship_to":{"company":"Acme","line1":"1 Main St","line2":"Unit 1"},"lines":[]},{"so_number":"SO-2","ship_to":{"company":"Acme","line1":"1 Main St","line2":"Unit 2"},"lines":[]}],"charges":[],"payments":[],"totals":{}}'::jsonb)) = 'false,false',
  pg_temp.rep(public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[{"so_number":"SO-1","ship_to":{"company":"Acme"},"lines":[]},{"so_number":"SO-2","ship_to":{"company":" ACME "},"lines":[]}],"charges":[],"payments":[],"totals":{}}'::jsonb)));
select pg_temp.chk('D7 판정 788 실물 묶음 인보이스 60073(SO-25201 · SO-25202 · 같은 Ship To · 있으면): final_invoice 의 orders ship_to_repeat = [false, true] · so_numbers = "SO-25201, SO-25202" — 없으면 건너뜀(has_m 0)',
  :has_m = 0 or (pg_temp.rep(pg_temp.j(:'n_fm')->'docs'->0) = 'false,true' and (pg_temp.j(:'n_fm')->'docs'->0->'invoice'->>'so_numbers') = 'SO-25201, SO-25202'
                 and (pg_temp.j(:'n_fm')->'docs'->0->'orders'->0->'ship_to') = (pg_temp.j(:'n_fm')->'docs'->0->'orders'->1->'ship_to')),
  format('has_m %s | rep %s | so_numbers %s | ship_to[0] %s | ship_to[1] %s', :has_m, pg_temp.rep(pg_temp.j(:'n_fm')->'docs'->0), pg_temp.j(:'n_fm')->'docs'->0->'invoice'->>'so_numbers', (pg_temp.j(:'n_fm')->'docs'->0->'orders'->0->'ship_to')::text, (pg_temp.j(:'n_fm')->'docs'->0->'orders'->1->'ship_to')::text));
select pg_temp.chk('D4 ship_ready 기본 메일 제목: 머리 값이 시드 원문이면 → "PROFORMA INVOICE {{invoice.so_numbers}} - Asung Trading Inc." · 아니면 머리 값 그대로(직원이 고친 것) · 지금 값은 doc_template_check(text) 통과(fields = [invoice.so_numbers] 또는 자리표 없음) · updated_by null · 다른 doc_setting 29 행 무변 — 머리 ' || :'subj_head' || ' → 지금 ' || :'subj_now',
  :'subj_now' = case when :subj_is_seed = 1 then 'PROFORMA INVOICE {{invoice.so_numbers}} - Asung Trading Inc.' else :'subj_head' end
  and (:'subj_now' = '' or (public.doc_template_check('ship_ready', :'subj_now', 'text')->>'ok')::boolean or (public.doc_template_check('ship_ready', :'subj_now', 'text')->'problems'->0->>'code') = 'no_placeholders')
  and (:subj_is_seed = 0 or (public.doc_template_check('ship_ready', :'subj_now', 'text')->'fields') = '["invoice.so_numbers"]'::jsonb)
  and (:subj_is_seed = 0 or (select updated_by is null from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject'))
  and (select md5(string_agg(kind || '|' || key || '|' || value || '|' || coalesce(updated_by::text, ''), '|' order by kind, key)) || ' ' || count(*) from public.doc_setting where not (kind = 'ship_ready' and key = 'mail_subject')) = :'snap_ds',
  format('now %s | check %s', :'subj_now', public.doc_template_check('ship_ready', :'subj_now', 'text')::text));

-- ── S 메일 미리 보기 — 화면이 부르는 순서(ims-doc.js:186 doc_mail_send commit false · p_subject 없음 → 칸에 넣음 → 보내기는 칸의 글을 p_subject 로) ──
select pg_temp.asu(:'q_m1') as n_m1, pg_temp.asu(:'q_m12') as n_m12, pg_temp.asu(:'q_mso') as n_mso, pg_temp.asu(:'q_mfi') as n_mfi \gset
select pg_temp.asu(format('select public.doc_mail_send(''ship_ready'', %L, null, %L, null, false)::text', :'ref1'::jsonb, 'PROFORMA INVOICE SO-79921 - Asung Trading Inc.')) as n_m1t \gset
select pg_temp.chk('S1 미리 보기 ship_ready 오더 하나: 제목 = 설정 글을 그 문서로 채운 것 — 시드였다면 "PROFORMA INVOICE SO-79921 - Asung Trading Inc." · committed false · 받는 이 = 기본 연락처 · 칸 일곱 그대로',
  (pg_temp.j(:'n_m1')->>'committed') = 'false' and (pg_temp.j(:'n_m1')->>'to') = 'srs.one@example.invalid'
  and (pg_temp.j(:'n_m1')->>'subject') = btrim(public.doc_mail_fill(:'subj_now', pg_temp.j(:'n_sr1')->'docs'->0))
  and (:subj_is_seed = 0 or (pg_temp.j(:'n_m1')->>'subject') = 'PROFORMA INVOICE SO-79921 - Asung Trading Inc.')
  and pg_temp.j(:'n_m1') ?& array['from', 'from_name', 'reply_to', 'redirect_to', 'to', 'subject', 'body'],
  left(:'n_m1', 300));
select pg_temp.chk('S2 미리 보기 ship_ready 오더 둘(한 장): 제목에 둘 다 — 시드였다면 "PROFORMA INVOICE SO-79921, SO-79922 - Asung Trading Inc." · 본문은 설정 글 그대로 채움',
  (pg_temp.j(:'n_m12')->>'committed') = 'false'
  and (pg_temp.j(:'n_m12')->>'subject') = btrim(public.doc_mail_fill(:'subj_now', pg_temp.j(:'n_sr12')->'docs'->0))
  and (:subj_is_seed = 0 or (pg_temp.j(:'n_m12')->>'subject') = 'PROFORMA INVOICE SO-79921, SO-79922 - Asung Trading Inc.')
  and (pg_temp.j(:'n_m12')->>'body') = public.doc_mail_fill((select value from public.doc_setting where kind = 'ship_ready' and key = 'mail_body'), pg_temp.j(:'n_sr12')->'docs'->0),
  left(:'n_m12', 300));
select pg_temp.chk('S3 직원이 칸의 글을 그대로 보낼 때(p_subject = 이미 채워진 글): 다시 채워도 같은 글(자리표 없음 → 그대로)',
  (pg_temp.j(:'n_m1t')->>'subject') = 'PROFORMA INVOICE SO-79921 - Asung Trading Inc.', left(:'n_m1t', 200));
\if :{?mig}
select pg_temp.chk('S4 시험에서만: 다른 kind 미리 보기 옛 = 새 — sales_order · final_invoice(제목 FINAL INVOICE {{invoice.number}} 그대로 · 반환 바이트)',
  md5(:'n_mso') = md5(:'o_mso') and md5(:'n_mfi') = md5(:'o_mfi') and (pg_temp.j(:'n_mfi')->>'subject') like 'FINAL INVOICE %',
  format('mso old %s new %s | mfi old %s new %s', left(:'o_mso', 80), left(:'n_mso', 80), left(:'o_mfi', 80), left(:'n_mfi', 80)));
\else
select pg_temp.chk('S4 확인: 다른 kind 미리 보기 통과 — sales_order · final_invoice(제목 FINAL INVOICE …)',
  (pg_temp.j(:'n_mso')->>'committed') = 'false' and (pg_temp.j(:'n_mfi')->>'committed') = 'false' and (pg_temp.j(:'n_mfi')->>'subject') like 'FINAL INVOICE %',
  format('mso %s | mfi %s', left(:'n_mso', 80), left(:'n_mfi', 80)));
\endif

-- ── L 함수 모양 ──
select pg_temp.chk('L1 함수 모양(새 판): fmt STABLE · catalog IMMUTABLE · ACL 머리와 같다(둘) · authenticated 는 fmt 못 부르고 catalog 는 부른다 · anon 둘 다 못 부른다 · comment 둘에 787 · 함수 하나씩',
  (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) = 's'
  and (select provolatile from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) = 'i'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') = :'fmt_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') = :'cat_acl_head'
  and not has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') and has_function_privilege('authenticated', 'public.doc_field_catalog(text)', 'execute')
  and not has_function_privilege('anon', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') and not has_function_privilege('anon', 'public.doc_field_catalog(text)', 'execute')
  and obj_description('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'pg_proc') ~ '787' and obj_description('public.doc_field_catalog(text)'::regprocedure, 'pg_proc') ~ '787'
  and (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_field_catalog') and pronamespace = 'public'::regnamespace) = 2,
  format('fmt acl %s | cat acl %s', (select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), (select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure)));
\endif

-- ── Z 실물 무접촉 ──
select pg_temp.chk('Z1 실물 무접촉: mail_outbox · doc_file md5 머리와 같다 · doc_ship_ready 줄 수 그대로(미리 보기는 큐에 안 넣는다) · 다른 doc_setting 행 무변 · 무접촉 함수 몸 그대로(doc_mail_send · doc_mail_fill · doc_setting_set · doc_template_check · doc_data · doc_data_ship_ready · doc_data_invoice)',
  (select md5(coalesce(string_agg((to_jsonb(t) - 'attachments')::text, '|' order by t.id), '')) || ' ' || count(*) from public.mail_outbox t) = :'snap_ob'
  and (select md5(coalesce(string_agg(t.id::text || ':' || t.path || ':' || t.sha256, '|' order by t.id), '')) || ' ' || count(*) from public.doc_file t) = :'snap_df'
  and (select count(*) from public.mail_outbox where kind = 'doc_ship_ready') = :n_sr_head
  and (select md5(string_agg(kind || '|' || key || '|' || value || '|' || coalesce(updated_by::text, ''), '|' order by kind, key)) || ' ' || count(*) from public.doc_setting where not (kind = 'ship_ready' and key = 'mail_subject')) = :'snap_ds'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)'::regprocedure) = '98f93aaa243f111befdad7eeb9a0eb1e'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_mail_fill(text, jsonb)'::regprocedure) = '42c3f7b742c66dd7698a17e15387197d'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_setting_set(text, text, text)'::regprocedure) = '29b48aab06a92d18d7e466062dec9e86'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_template_check(text, text, text)'::regprocedure) = '26b1075a117087a42a061531c785f821'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data(text, jsonb)'::regprocedure) = '400358fa6e488d514039cdc9705e6d39'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_ship_ready(jsonb, jsonb)'::regprocedure) = '446fa345c99b64ba39ed0d67bdceeaac'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) = 'd47d2a5ad8c28449676451176b76b9e8',
  'snap');
select 'begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text as elapsed;
\pset tuples_only off
\pset format aligned
rollback;
-- ── 번호 되돌리기 = greatest(실제 최대, 머리) · 전후 원문(이 시험은 시퀀스를 당기지 않는다 — 안전망) ──
select setval('public.so_number_seq', greatest(coalesce((select max(substring(s.so_number from '^SO-([0-9]+)')::bigint) from public.so s), 0), :so_seq_last), :'so_seq_called'::boolean) as so_seq_set;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(i.invoice_number::bigint) from public.so_invoice i where i.invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as inv_seq_set;
select last_value as so_seq_after, is_called as so_called_after from public.so_number_seq;
select last_value as inv_seq_after, is_called as inv_called_after from public.so_invoice_number_seq;
select 'rolled back — srs1 fake rows left: staff ' || (select count(*) from public.ims_staff where email like 'srs1-%') || ' · cust ' || (select count(*) from public.customer where name = 'srs1 Cust') || ' · so ' || (select count(*) from public.so where so_number in ('SO-79921', 'SO-79922', 'SO-79923')) || ' · product ' || (select count(*) from public.product where sku = 'SRS1-P1') || ' · outbox doc_ship_ready ' || (select count(*) from public.mail_outbox where kind = 'doc_ship_ready') || ' · ship_ready mail_subject = ' || (select value from public.doc_setting where kind = 'ship_ready' and key = 'mail_subject') as leftover;
-- 기대 OK: 시험(-v mig) 22(3 회차 실측 · MISMATCH 0 · begin ~ rollback 4.2 초 — 마이그레이션을 savepoint 안 1 번 + 진짜 1 번 읽는다) · 마른(적용 전 · 옛 판 · -v mig 없음) 2(실측 · G0 Z1) · 확인(적용 뒤 · -v mig 없음) 16(계산 = G0 N0 T4 D1 D2 D3 D5 D6 D7 D4 S1 S2 S3 S4 L1 Z1 · 적용 전엔 못 돈다 — Caleb 확인 실행이 첫 통과)
-- 회차 기록: 1 회차 — 마이그레이션 실물 확인의 표본 판이 {{#ship_to}} 를 섹션으로 써 template-check 에 걸림(ship_to 는 섹션이 아니다 · {{ship_to.company}} 꼴로 고침) · 2 회차 — D4 updated_by: asu 가 request.jwt.claims 를 트랜잭션에 남겨 ims_touch 가 가짜 직원을 적음(호출 뒤 비우게 고침) · 3 회차 통과
