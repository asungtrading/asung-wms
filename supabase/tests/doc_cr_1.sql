-- doc-cr-1 검증 — supabase/migrations/20261029012649_doc_cr_1.sql (판정 864 · credits[] · totals.credits · totals.balance_due · asung-doc §1 · §2 · so-module §66 판정 528)
--   시험 적용 + 검증(Claude Code · rollback): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029012649_doc_cr_1.sql -f supabase/tests/doc_cr_1.sql 2>&1 | tee /tmp/doc_cr_1.out
--   확인 실행(Caleb · 적용 뒤 · -v mig 없음): 같은 명령에서 -v mig 만 뺀다 · 갈래는 DB 의 doc_data_invoice_fmt prosrc md5 로 가른다(옛 판 1ee6ba91 = srs-1 · 새 판 = doc-cr-1)
--   EXPECT: 시험(-v mig) OK 17(O1 G1 N0 T1 T2 T3 T4 D1 D2 D3 D4 D5 D6 D7 L1 Z1 Z2 · MISMATCH 0 · begin ~ rollback 4.3 ~ 6.4 초 · 3 회차 통과) · 마른(적용 전 · -v mig 없음) OK 3(G0 Z1 Z2) · 확인(적용 뒤 · -v mig 없음) OK 13(G0 N0 T4 D1 D2 D3 D4 D5 D6 D7 L1 Z1 Z2 — 계산값 · 적용 전엔 못 돈다 · Caleb 확인 실행이 첫 통과)
--   ⚠️ 재료: 실물은 읽기만(60073 · 60019 · 60011 · 크레딧 없는 최신 인보이스 · 크레딧 노트 하나 · confirmed 오더 하나) · 가짜(rollback)는 직원 1(sales) + 크레딧 셋(so_invoice 표는 쓰지 않는다 — ar-3 주의)
--     CR-99990 cancelled 인데 살아 있는 붙임 0.10(60073) · CR-99991 issued 인데 void 된 붙임 0.20(60073) — 둘 다 목록에서 빠지고 60073 의 남은 돈을 안 바꾼다
--     CR-99992 issued · Cin7 시절(ref_invoice_number 49999 · invoice_id null) · 살아 있는 붙임 0.01(60019) — reference 가 ref_invoice_number 로 · 60019 의 남은 돈이 0.01 줄어든다(기대값은 식으로)
--   ⚠️ 테스트 DB 는 mail_enabled on · cron 이 돈다 — 반드시 rollback · doc_mail_* · mail_claim 은 부르지 않는다 · 시퀀스는 당기지 않는다(크레딧 번호 명시)
--   잠금 규칙 ④: doc_data 는 인보이스 한 장 읽기(가볍다) · 마이그레이션은 create or replace function 셋(표 잠금 없음) · begin ~ rollback 시간을 끝에 찍는다
\set ON_ERROR_STOP on
\pset pager off
-- ── 머리(잠금 없음) — 함수 판 · ACL · 재료 열쇠 · 실물 스냅샷 ──
select (select value from public.inv_config where key = 'db_role') as db_role;
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace), '(none)') as fmt_md5_head \gset
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_field_catalog' and pronamespace = 'public'::regnamespace), '(none)') as cat_md5_head \gset
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_invoice' and pronamespace = 'public'::regnamespace), '(none)') as ld_md5_head \gset
select (:'fmt_md5_head' = '1ee6ba91dd1d4428f6659ff215fab183')::int as is_old \gset
select ((:{?mig}) or :is_old = 0)::int as expect_pass \gset
select :'fmt_md5_head' as fmt_md5_head, :'cat_md5_head' as cat_md5_head, :'ld_md5_head' as ld_md5_head, :is_old as is_old, :expect_pass as expect_pass;
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') as fmt_acl_head \gset
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') as cat_acl_head \gset
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), '(none)') as ld_acl_head \gset
select md5(coalesce(string_agg(t.id::text || ':' || t.credit_number || ':' || t.status || ':' || t.total, '|' order by t.id), '')) || ' ' || count(*) as snap_cr from public.so_credit t \gset
select md5(coalesce(string_agg(t.id::text || ':' || coalesce(t.invoice_id::text, '') || ':' || t.amount || ':' || coalesce(t.voided_at::text, ''), '|' order by t.id), '')) || ' ' || count(*) as snap_ca from public.so_credit_alloc t \gset
select md5(coalesce(string_agg(t.kind || ':' || t.template_id::text, '|' order by t.kind), '')) || ' ' || count(*) as snap_ta from public.doc_template_active t \gset
select md5(coalesce(string_agg(t.id::text || ':' || t.path || ':' || t.sha256, '|' order by t.id), '')) || ' ' || count(*) as snap_df from public.doc_file t \gset
select (select count(*) from public.so_invoice) as n_inv_head, (select count(*) from public.ims_staff) as n_staff_head \gset
select coalesce(value, 'DDMONYYYY') as dfmt from public.inv_config where key = 'doc_date_format' \gset
select id::text as wh from public.ref_warehouse where name = 'Asung Trading Inc.' and is_active \gset
select coalesce((select id::text from public.so_invoice where invoice_number = '60073'), '') as inv_m \gset
select coalesce((select id::text from public.so_invoice where invoice_number = '60019'), '') as inv_o \gset
select coalesce((select id::text from public.so_invoice where invoice_number = '60011'), '') as inv_self \gset
select id::text as inv_n from public.so_invoice i where i.status = 'issued' and i.kind <> 'opening' and not exists (select 1 from public.so_credit_alloc a where a.invoice_id = i.id) order by i.issued_on desc, i.created_at desc limit 1 \gset
select id::text as cr_s from public.so_credit order by created_at desc limit 1 \gset
select id::text as so_s from public.so where status = 'confirmed' order by created_at desc limit 1 \gset
select (:'inv_m' <> '')::int as has_m, (:'inv_o' <> '')::int as has_o, (:'inv_self' <> '')::int as has_self \gset
select bill_to_customer_id::text as cust_m, currency_id::text as cur_m from public.so_invoice where id = :'inv_m'::uuid \gset
select bill_to_customer_id::text as cust_o, currency_id::text as cur_o from public.so_invoice where id = :'inv_o'::uuid \gset
select :has_m as has_60073, :has_o as has_60019, :has_self as has_60011, left(:'inv_n', 8) as inv_no_credit, (select invoice_number from public.so_invoice where id = :'inv_n'::uuid) as inv_no_credit_number, left(:'cr_s', 8) as cr_sample, left(:'so_s', 8) as so_sample, :'dfmt' as date_format;

-- chk 는 트랜잭션 밖에서 만든다 — rollback 뒤의 Z2 도 부른다(트랜잭션 안의 pg_temp 함수는 rollback 으로 사라진다 · pos_pay_1 선례)
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\pset format unaligned
\pset tuples_only on
-- 가짜 직원(sales) 신원으로 창구를 부른다 · 예외는 'ERR <sqlstate>: <문장>' 글자로
create function pg_temp.asu(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000dc701","role":"authenticated"}', true);
  execute 'set local role authenticated';
  execute p_sql into v_out;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v_out;
exception when others then
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.dd(p_kind text, p_ref jsonb) returns jsonb language sql as $$ select pg_temp.j(pg_temp.asu(format('select public.doc_data(%L, %L)::text', p_kind, p_ref))) $$;
create function pg_temp.num(p text) returns numeric language sql as $$ select case when coalesce(p, '') = '' then 0 else replace(p, ',', '')::numeric end $$;
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
-- 새 열쇠 셋 + 시각을 뗀다(옛 = 새 비교)
create function pg_temp.strip(p jsonb) returns jsonb language sql as $$
  select jsonb_set(jsonb_set(p - 'credits', '{doc}', coalesce(p->'doc', '{}'::jsonb) - 'printed_at'), '{totals}', coalesce(p->'totals', '{}'::jsonb) - 'credits' - 'balance_due') $$;
create function pg_temp.strip_docs(p jsonb) returns jsonb language sql as $$ select (select coalesce(jsonb_agg(pg_temp.strip(d) order by ord), '[]'::jsonb) from jsonb_array_elements(p->'docs') with ordinality t(d, ord)) $$;
-- 불변식 한 장: total − Σpayments − Σcredits = balance_due(글자 → 숫자) · balance_due = so_invoice_remaining · Σcredits = 뷰 credited · Σpayments = 뷰 paid · credits 는 살아 있는 붙임 줄 수
create function pg_temp.inv_bad(p_inv uuid) returns text language plpgsql as $$
declare d jsonb; v_t numeric; v_p numeric; v_c numeric; v_b numeric; v_rem numeric; v_paid numeric; v_cred numeric; v_n int; v_bad text := '';
begin
  d := pg_temp.dd('final_invoice', jsonb_build_object('invoice_id', p_inv))->'docs'->0;
  if d is null then return 'no-json(' || (select invoice_number from public.so_invoice where id = p_inv) || ')'; end if;
  v_t := pg_temp.num(d->'totals'->>'total');  v_b := pg_temp.num(d->'totals'->>'balance_due');
  select coalesce(sum(pg_temp.num(x->>'amount')), 0) into v_p from jsonb_array_elements(d->'payments') x;
  select coalesce(sum(pg_temp.num(x->>'amount')), 0) into v_c from jsonb_array_elements(d->'credits') x;
  select l.remaining, l.paid, l.credited into v_rem, v_paid, v_cred from public.so_invoice_list l where l.id = p_inv;
  select count(*) into v_n from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id where a.invoice_id = p_inv and a.voided_at is null and c.status = 'issued';
  if round(v_t - v_p - v_c, 2) <> v_b then v_bad := v_bad || ' sum'; end if;
  if v_b <> round(v_rem, 2) then v_bad := v_bad || ' remaining'; end if;
  if v_c <> round(v_cred, 2) then v_bad := v_bad || ' credited'; end if;
  if v_p <> round(v_paid, 2) then v_bad := v_bad || ' paid'; end if;
  if jsonb_array_length(d->'credits') <> v_n then v_bad := v_bad || ' rows'; end if;
  if (d->'totals'->>'balance_due') !~ '^-?[0-9,]+\.[0-9][0-9]$' then v_bad := v_bad || ' balance_due-text'; end if;
  if (d->'totals'->>'credits') <> public.doc_fmt_money_nz(v_c) then v_bad := v_bad || ' credits-text'; end if;
  return case when v_bad = '' then '' else format('%s:%s [t %s p %s c %s b %s rem %s]', (select invoice_number from public.so_invoice where id = p_inv), v_bad, v_t, v_p, v_c, v_b, v_rem) end;
end $$;

-- ── 가짜 재료(replica · 트리거 없이) — 직원 1 · 크레딧 셋 ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values ('00000000-0000-4000-8000-0000000dc701', 'doccr1-sa@example.invalid', 'doccr1 sales', 'worker', '["sales"]', true) returning id::text as st \gset
insert into public.so_credit (credit_number, status, customer_id, currency_id, currency_code, invoice_id, reason, warehouse_id, issued_on, issued_by, lines_amount, total, cancelled_at, cancelled_by, cancel_note, created_by)
  values ('CR-99990', 'cancelled', :'cust_m'::uuid, :'cur_m'::uuid, 'CAD', :'inv_m'::uuid, 'other', :'wh'::uuid, public.ims_today(), :'st'::uuid, 0.10, 0.10, now(), :'st'::uuid, 'doccr1 fake cancelled', :'st'::uuid) returning id::text as c0 \gset
insert into public.so_credit (credit_number, status, customer_id, currency_id, currency_code, invoice_id, reason, warehouse_id, issued_on, issued_by, lines_amount, total, created_by)
  values ('CR-99991', 'issued', :'cust_m'::uuid, :'cur_m'::uuid, 'CAD', :'inv_m'::uuid, 'other', :'wh'::uuid, public.ims_today(), :'st'::uuid, 0.20, 0.20, :'st'::uuid) returning id::text as c1 \gset
insert into public.so_credit (credit_number, status, customer_id, currency_id, currency_code, ref_invoice_number, reason, warehouse_id, issued_on, issued_by, lines_amount, total, created_by)
  values ('CR-99992', 'issued', :'cust_o'::uuid, :'cur_o'::uuid, 'CAD', '49999', 'other', :'wh'::uuid, public.ims_today(), :'st'::uuid, 0.01, 0.01, :'st'::uuid) returning id::text as c2 \gset
insert into public.so_credit_alloc (credit_id, invoice_id, amount, source, created_by) values (:'c0'::uuid, :'inv_m'::uuid, 0.10, 'manual', :'st'::uuid);
insert into public.so_credit_alloc (credit_id, invoice_id, amount, source, voided_at, voided_by, void_note, created_by) values (:'c1'::uuid, :'inv_m'::uuid, 0.20, 'manual', now(), :'st'::uuid, 'doccr1 fake void', :'st'::uuid);
insert into public.so_credit_alloc (credit_id, invoice_id, amount, source, created_by) values (:'c2'::uuid, :'inv_o'::uuid, 0.01, 'manual', :'st'::uuid);
set local session_replication_role = origin;
select public.so_invoice_remaining(:'inv_m'::uuid)::text as rem_m, public.so_invoice_remaining(:'inv_o'::uuid)::text as rem_o, public.so_invoice_remaining(:'inv_n'::uuid)::text as rem_n \gset
select public.doc_fmt_money(:'rem_m'::numeric) as rem_m_txt, public.doc_fmt_money(:'rem_o'::numeric) as rem_o_txt, public.doc_fmt_money(:'rem_n'::numeric) as rem_n_txt \gset
select jsonb_build_object('invoice_id', :'inv_m')::text as r_m, jsonb_build_object('invoice_id', :'inv_o')::text as r_o, jsonb_build_object('invoice_id', :'inv_self')::text as r_self, jsonb_build_object('invoice_id', :'inv_n')::text as r_n,
       jsonb_build_object('credit_id', :'cr_s')::text as r_cr, jsonb_build_object('so_id', :'so_s')::text as r_so \gset

\if :{?mig}
-- ── O 시험에서만: 적용 전 옛 판 — 옛 출력을 받아 둔다 ──
select public.doc_field_catalog('final_invoice')::text as o_cat_fi, public.doc_field_catalog('ship_ready')::text as o_cat_sr, public.doc_field_catalog('internal_receipt')::text as o_cat_ir,
       public.doc_field_catalog('credit_note')::text as o_cat_cr, public.doc_field_catalog('sales_order')::text as o_cat_so \gset
select pg_temp.dd('final_invoice', :'r_m'::jsonb)::text as o_fm, pg_temp.dd('internal_receipt', :'r_m'::jsonb)::text as o_im, pg_temp.dd('final_invoice', :'r_o'::jsonb)::text as o_fo, pg_temp.dd('final_invoice', :'r_self'::jsonb)::text as o_fs,
       pg_temp.dd('final_invoice', :'r_n'::jsonb)::text as o_fn, pg_temp.dd('credit_note', :'r_cr'::jsonb)::text as o_cr, pg_temp.dd('sales_order', :'r_so'::jsonb)::text as o_so \gset
select pg_temp.chk('O1 시험에서만: 적용 전 = srs-1 판(fmt 1ee6ba91 · cat 126e2096 · loader d47d2a5a) · 옛 출력 일곱이 JSON · 옛 출력에 credits · totals.balance_due 없음 · 옛 카탈로그 셋에 totals.balance_due 없음 · 60073 옛 totals.credit_applied "" · due_amount ""(종이에 크레딧 · Due 줄이 없던 실물)',
  :is_old = 1 and :'cat_md5_head' = '126e20963f966471979f31282f8691a6' and :'ld_md5_head' = 'd47d2a5ad8c28449676451176b76b9e8'
  and left(:'o_fm', 1) = '{' and left(:'o_im', 1) = '{' and left(:'o_fo', 1) = '{' and left(:'o_fs', 1) = '{' and left(:'o_fn', 1) = '{' and left(:'o_cr', 1) = '{' and left(:'o_so', 1) = '{'
  and not ((pg_temp.j(:'o_fm')->'docs'->0) ? 'credits') and not ((pg_temp.j(:'o_fm')->'docs'->0->'totals') ? 'balance_due') and not ((pg_temp.j(:'o_im')->'docs'->0) ? 'credits')
  and not ((pg_temp.j(:'o_cat_fi')->'allowed') ? 'totals.balance_due') and not ((pg_temp.j(:'o_cat_sr')->'allowed') ? 'totals.balance_due') and not ((pg_temp.j(:'o_cat_ir')->'allowed') ? 'totals.balance_due')
  and (pg_temp.j(:'o_fm')->'docs'->0->'totals'->>'credit_applied') = '' and (pg_temp.j(:'o_fm')->'docs'->0->'totals'->>'due_amount') = '' and (pg_temp.j(:'o_fm')->'docs'->0->'totals'->>'paid') = '28.26',
  format('%s | %s | %s | fm %s | im %s | fo %s | cr %s | so %s', :'fmt_md5_head', :'cat_md5_head', :'ld_md5_head', left(:'o_fm', 60), left(:'o_im', 60), left(:'o_fo', 60), left(:'o_cr', 60), left(:'o_so', 60)));
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('G1 시험에서만: 적용 뒤 셋 다 새 몸 · 함수 하나씩 · loader 에 credits · fmt 에 balance_due · catalog 에 totals.balance_due',
  (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> '1ee6ba91dd1d4428f6659ff215fab183'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) <> '126e20963f966471979f31282f8691a6'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) <> 'd47d2a5ad8c28449676451176b76b9e8'
  and (select count(*) from pg_proc where proname in ('doc_data_invoice', 'doc_data_invoice_fmt', 'doc_field_catalog') and pronamespace = 'public'::regnamespace) = 3
  and (select prosrc from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) ~ '''credits'''
  and (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) ~ 'balance_due'
  and (select prosrc from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) ~ 'totals\.balance_due',
  format('ld %s fmt %s cat %s', (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure)));
\else
select pg_temp.chk('G0 확인 실행: doc_data_invoice_fmt 가 있다 · 판 = ' || case when :is_old = 1 then '옛(srs-1 · 적용 전 — 아래 갈래는 돌지 않는다)' else '새(doc-cr-1 · 통과 갈래)' end,
  :'fmt_md5_head' <> '(none)', :'fmt_md5_head');
\endif

\if :expect_pass
-- ── 새 출력 ──
select public.doc_field_catalog('final_invoice')::text as n_cat_fi, public.doc_field_catalog('ship_ready')::text as n_cat_sr, public.doc_field_catalog('internal_receipt')::text as n_cat_ir,
       public.doc_field_catalog('credit_note')::text as n_cat_cr, public.doc_field_catalog('sales_order')::text as n_cat_so \gset
select pg_temp.dd('final_invoice', :'r_m'::jsonb)::text as n_fm, pg_temp.dd('internal_receipt', :'r_m'::jsonb)::text as n_im, pg_temp.dd('final_invoice', :'r_o'::jsonb)::text as n_fo, pg_temp.dd('final_invoice', :'r_self'::jsonb)::text as n_fs,
       pg_temp.dd('final_invoice', :'r_n'::jsonb)::text as n_fn, pg_temp.dd('credit_note', :'r_cr'::jsonb)::text as n_cr, pg_temp.dd('sales_order', :'r_so'::jsonb)::text as n_so \gset
select public.doc_data_invoice_fmt('ship_ready', jsonb_build_object('date_format', :'dfmt', 'unit_display', 'both'), '{"header":{},"orders":[],"charges":[],"payments":[],"totals":{"total":10,"amount_due":4.5,"credit_applied":2}}'::jsonb)::text as n_sr \gset
select pg_temp.chk('N0 새 출력 일곱이 다 JSON(가짜 직원 sales 로 doc_data) · ship_ready 그리기 직접(postgres · 중립)도 JSON',
  left(:'n_fm', 1) = '{' and left(:'n_im', 1) = '{' and left(:'n_fo', 1) = '{' and left(:'n_fs', 1) = '{' and left(:'n_fn', 1) = '{' and left(:'n_cr', 1) = '{' and left(:'n_so', 1) = '{' and left(:'n_sr', 1) = '{',
  format('fm %s | im %s | fo %s | fs %s | fn %s | cr %s | so %s | sr %s', left(:'n_fm', 80), left(:'n_im', 80), left(:'n_fo', 80), left(:'n_fs', 80), left(:'n_fn', 80), left(:'n_cr', 80), left(:'n_so', 80), left(:'n_sr', 80)));

\if :{?mig}
-- ── T 옛 = 새 (시험에서만) ──
select pg_temp.chk('T1 카탈로그: final_invoice · internal_receipt 의 allowed = 옛 + 일곱(credits.no·number·date·reference·amount · totals.credits · totals.balance_due) · sections = 옛 + credits · required 그대로 · ship_ready 는 allowed = 옛 + totals.balance_due 만 · sections · required 그대로 · credit_note · sales_order 바이트 무변',
  (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_fi')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_fi')->'allowed') union all select unnest(array['credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due'])) t(x))
  and (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_ir')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_ir')->'allowed') union all select unnest(array['credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due'])) t(x))
  and (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_sr')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_sr')->'allowed') union all select 'totals.balance_due') t(x))
  and (pg_temp.j(:'n_cat_fi')->'sections') = (pg_temp.j(:'o_cat_fi')->'sections') || '["credits"]'::jsonb and (pg_temp.j(:'n_cat_ir')->'sections') = (pg_temp.j(:'o_cat_ir')->'sections') || '["credits"]'::jsonb and (pg_temp.j(:'n_cat_sr')->'sections') = (pg_temp.j(:'o_cat_sr')->'sections')
  and (pg_temp.j(:'n_cat_fi')->'required') = (pg_temp.j(:'o_cat_fi')->'required') and (pg_temp.j(:'n_cat_ir')->'required') = (pg_temp.j(:'o_cat_ir')->'required') and (pg_temp.j(:'n_cat_sr')->'required') = (pg_temp.j(:'o_cat_sr')->'required')
  and :'n_cat_cr' = :'o_cat_cr' and :'n_cat_so' = :'o_cat_so',
  format('fi new %s old %s | ir new %s old %s | sr new %s old %s | fi sections %s', jsonb_array_length(pg_temp.j(:'n_cat_fi')->'allowed'), jsonb_array_length(pg_temp.j(:'o_cat_fi')->'allowed'), jsonb_array_length(pg_temp.j(:'n_cat_ir')->'allowed'), jsonb_array_length(pg_temp.j(:'o_cat_ir')->'allowed'), jsonb_array_length(pg_temp.j(:'n_cat_sr')->'allowed'), jsonb_array_length(pg_temp.j(:'o_cat_sr')->'allowed'), (pg_temp.j(:'n_cat_fi')->'sections')::text));
select pg_temp.chk('T2 doc_data 옛 = 새(새 열쇠 credits · totals.credits · totals.balance_due · printed_at 만 떼고 — 옛 열쇠 전부 글자 그대로): 60073 final_invoice · internal_receipt · 60019 · 60011 · 크레딧 없는 인보이스 · credit_note · sales_order(바이트) · 옛 totals 열쇠 18 = 새 totals − 둘',
  pg_temp.strip_docs(pg_temp.j(:'n_fm')) = pg_temp.strip_docs(pg_temp.j(:'o_fm')) and pg_temp.strip_docs(pg_temp.j(:'n_im')) = pg_temp.strip_docs(pg_temp.j(:'o_im'))
  and pg_temp.strip_docs(pg_temp.j(:'n_fo')) = pg_temp.strip_docs(pg_temp.j(:'o_fo')) and pg_temp.strip_docs(pg_temp.j(:'n_fs')) = pg_temp.strip_docs(pg_temp.j(:'o_fs')) and pg_temp.strip_docs(pg_temp.j(:'n_fn')) = pg_temp.strip_docs(pg_temp.j(:'o_fn'))
  and pg_temp.strip_docs(pg_temp.j(:'n_cr')) = pg_temp.strip_docs(pg_temp.j(:'o_cr')) and pg_temp.strip_docs(pg_temp.j(:'n_so')) = pg_temp.strip_docs(pg_temp.j(:'o_so'))
  and md5(:'n_cr') = md5(:'o_cr') and md5(:'n_so') = md5(:'o_so')
  and ((pg_temp.j(:'n_fm')->'docs'->0->'totals') - 'credits' - 'balance_due') = (pg_temp.j(:'o_fm')->'docs'->0->'totals') and (select count(*) from jsonb_object_keys(pg_temp.j(:'o_fm')->'docs'->0->'totals')) = 18
  and (select count(*) from jsonb_object_keys(pg_temp.j(:'n_fm')->'docs'->0->'totals')) = 20,
  format('fm old=%s new=%s | fo old=%s new=%s', left(:'o_fm', 80), left(:'n_fm', 80), left(:'o_fo', 80), left(:'n_fo', 80)));
select pg_temp.chk('T3 열쇠 대조 옛 = 새: 출력 − 카탈로그 · 카탈로그 − 출력 이 final_invoice(60073) · internal_receipt · credit_note · sales_order 모두 옛과 같다(새 열쇠는 양쪽에 같이)',
  pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fm')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_fm')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_fi')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_fi')), pg_temp.pset(pg_temp.j(:'n_fm')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_fi')), pg_temp.pset(pg_temp.j(:'o_fm')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_im')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_im')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_ir')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_ir')), pg_temp.pset(pg_temp.j(:'n_im')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_ir')), pg_temp.pset(pg_temp.j(:'o_im')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_cr'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_cr')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_cr')))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_so')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_so'))),
  format('fi out−cat old %s new %s | cat−out old %s new %s | ir out−cat new %s', pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_fm')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_fi'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fm')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))),
         pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_fi')), pg_temp.pset(pg_temp.j(:'o_fm')->'docs'->0)), pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_fi')), pg_temp.pset(pg_temp.j(:'n_fm')->'docs'->0)), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_im')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir')))));
\endif

-- ── T4 열쇠 대조(새 판 · 시험 · 확인 둘 다): 새 열쇠가 카탈로그와 출력 양쪽에 · 출력 − 카탈로그 = final_invoice {} · internal_receipt {orders.lines.final_sale}(bgr-1d 부터) · ship_ready 는 balance_due 만 · credit_note · sales_order 엔 없다 ──
select pg_temp.chk('T4 열쇠 대조(새 판): credits.* 다섯 · totals.credits · totals.balance_due 가 final_invoice · internal_receipt 의 카탈로그 · 출력 양쪽에 · ship_ready 는 totals.balance_due 만(credits 없음 · 카탈로그 · 중립 출력) · credit_note · sales_order 엔 셋 다 없다 · 출력 − 카탈로그 = fi {} · ir {orders.lines.final_sale} · cr {} · so {}',
  pg_temp.cset(pg_temp.j(:'n_cat_fi')) @> array['credits', 'credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due']
  and pg_temp.pset(pg_temp.j(:'n_fm')->'docs'->0) @> array['credits', 'credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due']
  and pg_temp.cset(pg_temp.j(:'n_cat_ir')) @> array['credits', 'credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due']
  and pg_temp.pset(pg_temp.j(:'n_im')->'docs'->0) @> array['credits', 'credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due']
  and 'totals.balance_due' = any (pg_temp.cset(pg_temp.j(:'n_cat_sr'))) and not ('totals.credits' = any (pg_temp.cset(pg_temp.j(:'n_cat_sr')))) and not ('credits' = any (pg_temp.cset(pg_temp.j(:'n_cat_sr'))))
  and (pg_temp.j(:'n_sr')->'totals'->>'balance_due') = '4.50' and not (pg_temp.j(:'n_sr') ? 'credits') and not ((pg_temp.j(:'n_sr')->'totals') ? 'credits') and (pg_temp.j(:'n_sr')->'totals'->>'credit_applied') = '2.00'
  and not ('totals.balance_due' = any (pg_temp.cset(pg_temp.j(:'n_cat_cr')))) and not ('totals.balance_due' = any (pg_temp.cset(pg_temp.j(:'n_cat_so')))) and not ('credits' = any (pg_temp.cset(pg_temp.j(:'n_cat_cr')))) and not ('credits' = any (pg_temp.cset(pg_temp.j(:'n_cat_so'))))
  and not ('totals.balance_due' = any (pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0))) and not ('totals.balance_due' = any (pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0))) and not ('credits' = any (pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0))) and not ('credits' = any (pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0)))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fm')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))) = '{}'::text[]
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_im')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))) = array['orders.lines.final_sale']
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_cr'))) = '{}'::text[]
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so'))) = '{}'::text[],
  format('fi out−cat %s | ir %s | cr %s | so %s | fi cat−out %s | sr totals %s', pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_fm')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_fi'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_im')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_ir'))),
         pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_cr'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_so'))), pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_fi')), pg_temp.pset(pg_temp.j(:'n_fm')->'docs'->0)), (pg_temp.j(:'n_sr')->'totals')::text));

-- ── D 값 ──
select pg_temp.chk('D1 실물 60073(판정 864): credits 한 줄 = {no 1 · number CR-01010 · date = 크레딧 발행일(doc_date_format) · reference "60070"(60070 에 낸 크레딧을 손으로 붙임) · amount "0.80"} · totals.credits "0.80" · totals.balance_due "0.00"(늘 찍는다) · 옛 due_amount "" · paid "28.26" · 가짜 CR-99990(cancelled) · CR-99991(void) 는 빠진다 · internal_receipt 도 같은 credits · totals',
  :has_m = 1 and jsonb_array_length(pg_temp.j(:'n_fm')->'docs'->0->'credits') = 1
  and (pg_temp.j(:'n_fm')->'docs'->0->'credits'->0) = jsonb_build_object('no', '1', 'number', 'CR-01010', 'date', public.doc_fmt_date((select c.issued_on from public.so_credit c where c.credit_number = 'CR-01010'), :'dfmt'), 'reference', '60070', 'amount', '0.80')
  and (pg_temp.j(:'n_fm')->'docs'->0->'totals'->>'credits') = '0.80' and (pg_temp.j(:'n_fm')->'docs'->0->'totals'->>'balance_due') = '0.00' and :'rem_m' = '0.00'
  and (pg_temp.j(:'n_fm')->'docs'->0->'totals'->>'due_amount') = '' and (pg_temp.j(:'n_fm')->'docs'->0->'totals'->>'due_label') = '' and (pg_temp.j(:'n_fm')->'docs'->0->'totals'->>'paid') = '28.26' and (pg_temp.j(:'n_fm')->'docs'->0->'totals'->>'total') = '29.06'
  and :'n_fm' !~ 'CR-9999' and :'n_im' !~ 'CR-9999'
  and (pg_temp.j(:'n_im')->'docs'->0->'credits') = (pg_temp.j(:'n_fm')->'docs'->0->'credits') and (pg_temp.j(:'n_im')->'docs'->0->'totals') = (pg_temp.j(:'n_fm')->'docs'->0->'totals'),
  format('credits %s | totals %s', (pg_temp.j(:'n_fm')->'docs'->0->'credits')::text, (pg_temp.j(:'n_fm')->'docs'->0->'totals')::text));
select coalesce(string_agg(b, ' ; '), '') as d2_bad from (select pg_temp.inv_bad(i.id) as b from public.so_invoice i where i.status = 'issued' and i.kind <> 'opening' and (i.id = :'inv_n'::uuid or exists (select 1 from public.so_credit_alloc a where a.invoice_id = i.id))) t where b <> '' \gset
select count(*) as d2_n from public.so_invoice i where i.status = 'issued' and i.kind <> 'opening' and (i.id = :'inv_n'::uuid or exists (select 1 from public.so_credit_alloc a where a.invoice_id = i.id)) \gset
select pg_temp.chk('D2 불변식(숫자로) — 크레딧 붙임이 있는 모든 issued 인보이스(실물 8 + 가짜 붙임) + 크레딧 없는 인보이스 하나 = ' || :d2_n || ' 장: total − Σpayments − Σcredits = balance_due · balance_due = so_invoice_remaining · Σcredits = 뷰 Credited · Σpayments = 뷰 Paid · credits 줄 수 = 살아 있는 붙임 수 · balance_due 는 늘 돈 글자 · totals.credits = nz(합)',
  :d2_n >= 9 and coalesce(:'d2_bad', '') = '', coalesce(:'d2_bad', '(none)'));
select pg_temp.chk('D3 실물 60019(남은 돈 있음 · CR-01005 4.37 auto · 60018 에 낸 크레딧) + 가짜 CR-99992(Cin7 시절 · ref_invoice_number 49999 · 0.01): credits 둘(발행일 순 · 둘째 reference "49999") · totals.credits "4.38" · balance_due = 옛 due_amount 글자 = doc_fmt_money(so_invoice_remaining) · due_label "Due" · 옛 credit_applied "4.37" · balance_forward "-4.37" 그대로(이견 5 — v8 이 뺀다)',
  :has_o = 1 and jsonb_array_length(pg_temp.j(:'n_fo')->'docs'->0->'credits') = 2
  and (pg_temp.j(:'n_fo')->'docs'->0->'credits'->0->>'number') = 'CR-01005' and (pg_temp.j(:'n_fo')->'docs'->0->'credits'->0->>'reference') = '60018' and (pg_temp.j(:'n_fo')->'docs'->0->'credits'->0->>'amount') = '4.37'
  and (pg_temp.j(:'n_fo')->'docs'->0->'credits'->1) = jsonb_build_object('no', '2', 'number', 'CR-99992', 'date', public.doc_fmt_date(public.ims_today(), :'dfmt'), 'reference', '49999', 'amount', '0.01')
  and (pg_temp.j(:'n_fo')->'docs'->0->'totals'->>'credits') = '4.38'
  and (pg_temp.j(:'n_fo')->'docs'->0->'totals'->>'balance_due') = :'rem_o_txt' and (pg_temp.j(:'n_fo')->'docs'->0->'totals'->>'balance_due') = (pg_temp.j(:'n_fo')->'docs'->0->'totals'->>'due_amount') and :'rem_o'::numeric > 0
  and (pg_temp.j(:'n_fo')->'docs'->0->'totals'->>'due_label') = 'Due' and (pg_temp.j(:'n_fo')->'docs'->0->'totals'->>'credit_applied') = '4.37' and (pg_temp.j(:'n_fo')->'docs'->0->'totals'->>'balance_forward') = '-4.37',
  format('credits %s | totals %s | rem %s', (pg_temp.j(:'n_fo')->'docs'->0->'credits')::text, (pg_temp.j(:'n_fo')->'docs'->0->'totals')::text, :'rem_o'));
select pg_temp.chk('D4 크레딧 없는 인보이스(' || (select invoice_number from public.so_invoice where id = :'inv_n'::uuid) || '): credits [] · totals.credits "" · balance_due = doc_fmt_money(so_invoice_remaining)(0 이면 "0.00" · 아니면 due_amount 와 같은 글자)',
  (pg_temp.j(:'n_fn')->'docs'->0->'credits') = '[]'::jsonb and (pg_temp.j(:'n_fn')->'docs'->0->'totals'->>'credits') = ''
  and (pg_temp.j(:'n_fn')->'docs'->0->'totals'->>'balance_due') = :'rem_n_txt'
  and (pg_temp.j(:'n_fn')->'docs'->0->'totals'->>'balance_due') = case when :'rem_n'::numeric = 0 then '0.00' else (pg_temp.j(:'n_fn')->'docs'->0->'totals'->>'due_amount') end,
  format('rem %s | totals %s', :'rem_n', (pg_temp.j(:'n_fn')->'docs'->0->'totals')::text));
select pg_temp.chk('D5 실물 60011(자기 인보이스에 낸 CR-01003 1133.75 를 자기에게 붙임 · manual): reference "" (판이 {{#reference}} 로 숨긴다) · number CR-01003 · balance_due "0.00"',
  :has_self = 1 and jsonb_array_length(pg_temp.j(:'n_fs')->'docs'->0->'credits') = 1 and (pg_temp.j(:'n_fs')->'docs'->0->'credits'->0->>'number') = 'CR-01003' and (pg_temp.j(:'n_fs')->'docs'->0->'credits'->0->>'reference') = ''
  and (pg_temp.j(:'n_fs')->'docs'->0->'credits'->0->>'amount') = '1,133.75' and (pg_temp.j(:'n_fs')->'docs'->0->'totals'->>'balance_due') = '0.00',
  format('credits %s', (pg_temp.j(:'n_fs')->'docs'->0->'credits')::text));
select pg_temp.chk('D6 그리기 직접(postgres · 중립 jsonb): 크레딧 둘 → no 1·2 · 날짜 꼴 · reference null → "" · 합 "2.00" · remaining 0 → balance_due "0.00" · due_amount "" · credits 열쇠 없으면 [] · "" · totals 비면 balance_due ""(null) · remaining 189.92 → "189.92" · 1234.5 → "1,234.50"',
  (select (d->'credits'->0) = '{"no":"1","date":"28OCT2026","amount":"0.80","number":"CR-00001","reference":"60070"}'::jsonb and (d->'credits'->1->>'no') = '2' and (d->'credits'->1->>'reference') = '' and (d->'totals'->>'credits') = '2.00' and (d->'totals'->>'balance_due') = '0.00' and (d->'totals'->>'due_amount') = ''
     from public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"credits":[{"credit_number":"CR-00001","issued_on":"2026-10-28","reference":"60070","amount":0.8},{"credit_number":"CR-00002","issued_on":"2026-10-27","reference":null,"amount":1.2}],"totals":{"total":2,"remaining":0}}'::jsonb) d)
  and (select (d->'credits') = '[]'::jsonb and (d->'totals'->>'credits') = '' and (d->'totals'->>'balance_due') = '' from public.doc_data_invoice_fmt('internal_receipt', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"totals":{}}'::jsonb) d)
  and (public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"totals":{"remaining":189.92}}'::jsonb)->'totals'->>'balance_due') = '189.92'
  and (public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"totals":{"remaining":1234.5}}'::jsonb)->'totals'->>'balance_due') = '1,234.50',
  (public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"credits":[{"credit_number":"CR-00001","issued_on":"2026-10-28","reference":"60070","amount":0.8},{"credit_number":"CR-00002","issued_on":"2026-10-27","reference":null,"amount":1.2}],"totals":{"total":2,"remaining":0}}'::jsonb) - 'company' - 'branches' - 'bill_to' - 'doc' - 'show')::text);
select body as v_active_fi from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'final_invoice') \gset
select body as v_active_ir from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'internal_receipt') \gset
select pg_temp.chk('D7 doc_template_check: v8 꼴 판(credits 표 · {{#reference}} · totals.credits · balance_due) 이 final_invoice · internal_receipt 에서 통과 · 쓰는 판(final_invoice v' || (select version from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'final_invoice')) || ' · internal_receipt v' || (select version from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'internal_receipt')) || ')은 여전히 통과(required 무접촉) · ship_ready 는 totals.balance_due 통과 · {{#credits}} 는 unknown_field',
  (public.doc_template_check('final_invoice', '<div>{{#orders}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.number}} {{totals.tax}} {{totals.total}} {{totals.due_amount}} {{#credits}}{{no}} {{number}} {{date}} {{#reference}}(Invoice {{reference}}){{/reference}} {{amount}}{{/credits}}{{#totals.credits}}{{totals.credits}}{{/totals.credits}}{{totals.balance_due}}</div>', 'template')->>'ok')::boolean
  and (public.doc_template_check('internal_receipt', '<div>{{invoice.number}} {{invoice.total_qty}} {{totals.total}} {{totals.due_amount}} {{#credits}}{{number}} {{date}} {{reference}} {{amount}}{{/credits}}{{totals.credits}}{{totals.balance_due}}</div>', 'template')->>'ok')::boolean
  and (public.doc_template_check('final_invoice', :'v_active_fi', 'template')->>'ok')::boolean and (public.doc_template_check('internal_receipt', :'v_active_ir', 'template')->>'ok')::boolean
  and (public.doc_template_check('ship_ready', '<div>{{#orders}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.calc_at}} {{totals.tax}} {{totals.total}} {{totals.due_amount}} {{totals.balance_due}}</div>', 'template')->>'ok')::boolean
  and exists (select 1 from jsonb_array_elements(public.doc_template_check('ship_ready', '<div>{{#orders}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.calc_at}} {{totals.tax}} {{totals.total}} {{totals.due_amount}} {{#credits}}{{number}}{{/credits}}</div>', 'template')->'problems') p where p->>'code' = 'unknown_field'),
  format('fi %s | ir %s | active fi %s | sr %s', left(public.doc_template_check('final_invoice', '<div>{{#orders}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.number}} {{totals.tax}} {{totals.total}} {{totals.due_amount}} {{#credits}}{{no}} {{number}} {{date}} {{#reference}}(Invoice {{reference}}){{/reference}} {{amount}}{{/credits}}{{#totals.credits}}{{totals.credits}}{{/totals.credits}}{{totals.balance_due}}</div>', 'template')::text, 200),
         left(public.doc_template_check('internal_receipt', '<div>{{invoice.number}} {{invoice.total_qty}} {{totals.total}} {{totals.due_amount}} {{#credits}}{{number}} {{date}} {{reference}} {{amount}}{{/credits}}{{totals.credits}}{{totals.balance_due}}</div>', 'template')::text, 200),
         left(public.doc_template_check('final_invoice', :'v_active_fi', 'template')::text, 120), left(public.doc_template_check('ship_ready', '<div>{{totals.balance_due}}</div>', 'template')::text, 200)));
select pg_temp.chk('L1 함수 모양(새 판): loader STABLE · fmt STABLE · catalog IMMUTABLE · ACL 셋 머리와 같다 · authenticated 는 loader · fmt 못 부르고 catalog 는 부른다 · anon 셋 다 못 부른다 · comment 둘에 864 와 787 · 함수 하나씩',
  (select provolatile from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) = 's'
  and (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) = 's'
  and (select provolatile from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) = 'i'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), '(none)') = :'ld_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') = :'fmt_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') = :'cat_acl_head'
  and not has_function_privilege('authenticated', 'public.doc_data_invoice(text, uuid, jsonb)', 'execute') and not has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') and has_function_privilege('authenticated', 'public.doc_field_catalog(text)', 'execute')
  and not has_function_privilege('anon', 'public.doc_data_invoice(text, uuid, jsonb)', 'execute') and not has_function_privilege('anon', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') and not has_function_privilege('anon', 'public.doc_field_catalog(text)', 'execute')
  and obj_description('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'pg_proc') ~ '864' and obj_description('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'pg_proc') ~ '787'
  and obj_description('public.doc_field_catalog(text)'::regprocedure, 'pg_proc') ~ '864' and obj_description('public.doc_field_catalog(text)'::regprocedure, 'pg_proc') ~ '787'
  and (select count(*) from pg_proc where proname in ('doc_data_invoice', 'doc_data_invoice_fmt', 'doc_field_catalog') and pronamespace = 'public'::regnamespace) = 3,
  format('ld acl %s | fmt acl %s | cat acl %s', (select proacl::text from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), (select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), (select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure)));
\endif

-- ── Z 무접촉 ──
select pg_temp.chk('Z1 무접촉: so_invoice_remaining(ar-2 505f62c6) · so_invoice_issue(7a031482) · so_invoice_detail(accd8dee) · doc_data(400358fa) · doc_data_credit · doc_data_so · doc_data_ship_ready · doc_template_check · doc_mail_send · doc_mail_fill 몸 그대로 · 쓰는 판(doc_template_active) · doc_file 스냅샷 그대로 · so_invoice 행 수 그대로',
  (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_remaining(uuid)'::regprocedure) = '505f62c60461e326e5f1cac598f08cb7'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_issue(uuid[], uuid, date)'::regprocedure) = '7a03148223048349d2b9d461969ca3f6'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_detail(uuid)'::regprocedure) = 'accd8deedc3eb1a8bb6bcb2ef549418a'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data(text, jsonb)'::regprocedure) = '400358fa6e488d514039cdc9705e6d39'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure) = '017c7f9b5111995d418a6d5888d27bda'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) = '904414a209c081eb2900bfe5daa935c3'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_ship_ready(jsonb, jsonb)'::regprocedure) = '446fa345c99b64ba39ed0d67bdceeaac'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_template_check(text, text, text)'::regprocedure) = '26b1075a117087a42a061531c785f821'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)'::regprocedure) = '98f93aaa243f111befdad7eeb9a0eb1e'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_mail_fill(text, jsonb)'::regprocedure) = '42c3f7b742c66dd7698a17e15387197d'
  and (select md5(coalesce(string_agg(t.kind || ':' || t.template_id::text, '|' order by t.kind), '')) || ' ' || count(*) from public.doc_template_active t) = :'snap_ta'
  and (select md5(coalesce(string_agg(t.id::text || ':' || t.path || ':' || t.sha256, '|' order by t.id), '')) || ' ' || count(*) from public.doc_file t) = :'snap_df'
  and (select count(*) from public.so_invoice) = :n_inv_head,
  'snap');
select 'begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text as elapsed;
\pset tuples_only off
\pset format aligned
rollback;
-- ── rollback 뒤 — 가짜 흔적 0 · 실물 스냅샷 머리 그대로(시퀀스는 당기지 않았다 — 크레딧 번호 명시) ──
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('Z2 rollback 뒤: 가짜 직원 0 · 가짜 크레딧 0 · so_credit · so_credit_alloc 스냅샷 머리와 같다 · 직원 수 그대로',
  (select count(*) from public.ims_staff where email like 'doccr1-%') = 0 and (select count(*) from public.so_credit where credit_number like 'CR-9999%') = 0
  and (select md5(coalesce(string_agg(t.id::text || ':' || t.credit_number || ':' || t.status || ':' || t.total, '|' order by t.id), '')) || ' ' || count(*) from public.so_credit t) = :'snap_cr'
  and (select md5(coalesce(string_agg(t.id::text || ':' || coalesce(t.invoice_id::text, '') || ':' || t.amount || ':' || coalesce(t.voided_at::text, ''), '|' order by t.id), '')) || ' ' || count(*) from public.so_credit_alloc t) = :'snap_ca'
  and (select count(*) from public.ims_staff) = :n_staff_head,
  format('staff %s cr %s', (select count(*) from public.ims_staff where email like 'doccr1-%'), (select count(*) from public.so_credit where credit_number like 'CR-9999%')));
\pset tuples_only off
\pset format aligned
-- 기대 OK: 시험(-v mig) 17(3 회차 실측 · MISMATCH 0 · 1 회차 D2 \gset null → 변수 미설정 · 2 회차 chk 가 트랜잭션 안이라 Z2 에서 사라짐 — 둘 다 검증 파일 쪽) · 마른(적용 전) 3(실측 · G0 Z1 Z2) · 확인(적용 뒤) 13(계산 = G0 N0 T4 D1 ~ D7 L1 Z1 Z2)
