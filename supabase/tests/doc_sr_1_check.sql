-- doc-sr-1 검증 — supabase/migrations/20261029220000_doc_sr_1_proforma_credits.sql (판정 874 · ship_ready credits[] · totals.credits · asung-doc §1 · §2 · so-module §86 · deferred 380)
--   시험 적용 + 검증(Claude Code · rollback): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029220000_doc_sr_1_proforma_credits.sql -f supabase/tests/doc_sr_1_check.sql 2>&1 | tee /tmp/doc_sr_1.out
--   확인 실행(Caleb · 적용 뒤 · -v mig 없음): 같은 명령에서 -v mig 만 뺀다 · 갈래는 DB 의 doc_data_invoice_fmt prosrc md5 로 가른다(옛 판 8bfd2523 = doc-cr-1 · 새 판 = doc-sr-1)
--   OK 줄 꼴: 'OK <태그>'(앞 빈칸 없음) → grep -cE '^ ?OK ' · MISMATCH 줄 꼴: 'MISMATCH (<태그>): <자세히>'
--   EXPECT: 시험(-v mig) OK 17 · MISMATCH 0 · 마른 OK 3 · 확인 OK 13 — 파일 끝 「기대 OK」 주석
--   ⚠️ 재료: 실물은 읽기만(SO-25251 packed · 운임 30.14 는 화면 실물과 같은 입력 · 60073 · 60019 · 크레딧 노트 하나 · confirmed 오더 하나 · packed 오더 둘인 손님 하나) · 가짜(rollback)는 직원 1(sales) + 크레딧 1(CR-99980 · 묶음 둘 손님 · ④ 관측용)
--   ⚠️ 테스트 DB 는 mail_enabled on · cron 이 돈다 — 반드시 rollback · doc_mail_* · mail_claim 은 부르지 않는다 · 시퀀스는 당기지 않는다(크레딧 번호 명시) · so_finalize 는 p_commit false(so_invoice_preview 안) — 쓰지 않는다 · so 행 for update 는 트랜잭션 안 몇 초
--   잠금 규칙 ④: 무거운 기준값은 begin 앞 · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다
\set ON_ERROR_STOP on
\pset pager off
-- ── 머리(잠금 없음) — 함수 판 · ACL · 재료 열쇠 · 실물 스냅샷 ──
select (select value from public.inv_config where key = 'db_role') as db_role;
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_data_invoice_fmt' and pronamespace = 'public'::regnamespace), '(none)') as fmt_md5_head \gset
select coalesce((select md5(prosrc) from pg_proc where proname = 'doc_field_catalog' and pronamespace = 'public'::regnamespace), '(none)') as cat_md5_head \gset
select (:'fmt_md5_head' = '8bfd2523b9484ed1815d965040e6b3ec')::int as is_old \gset
select ((:{?mig}) or :is_old = 0)::int as expect_pass \gset
select :'fmt_md5_head' as fmt_md5_head, :'cat_md5_head' as cat_md5_head, :is_old as is_old, :expect_pass as expect_pass;
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') as fmt_acl_head \gset
select coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') as cat_acl_head \gset
select md5(coalesce(string_agg(t.id::text || ':' || t.credit_number || ':' || t.status || ':' || t.total, '|' order by t.id), '')) || ' ' || count(*) as snap_cr from public.so_credit t \gset
select md5(coalesce(string_agg(t.kind || ':' || t.template_id::text, '|' order by t.kind), '')) || ' ' || count(*) as snap_ta from public.doc_template_active t \gset
select md5(coalesce(string_agg(t.id::text || ':' || t.path || ':' || t.sha256, '|' order by t.id), '')) || ' ' || count(*) as snap_df from public.doc_file t \gset
select (select count(*) from public.so_invoice) as n_inv_head, (select count(*) from public.ims_staff) as n_staff_head, (select count(*) from public.so where status = 'packed') as n_packed_head \gset
select coalesce(value, 'DDMONYYYY') as dfmt from public.inv_config where key = 'doc_date_format' \gset
select id::text as wh from public.ref_warehouse where name = 'Asung Trading Inc.' and is_active \gset
select coalesce((select id::text from public.so where so_number = 'SO-25251' and status = 'packed'), '') as so_sr \gset
select coalesce((select id::text from public.so_invoice where invoice_number = '60073'), '') as inv_m \gset
select coalesce((select id::text from public.so_invoice where invoice_number = '60019'), '') as inv_o \gset
select id::text as cr_s from public.so_credit order by created_at desc limit 1 \gset
select id::text as so_s from public.so where status = 'confirmed' order by created_at desc limit 1 \gset
-- 묶음 둘: packed 오더가 둘 이상인 손님 하나(같은 통화) — 없으면 '' (T3 「안 봤다」)
select coalesce((select bill_to_customer_id::text from public.so where status = 'packed' and id <> nullif(:'so_sr', '')::uuid group by bill_to_customer_id, currency_id having count(*) >= 2 order by count(*) desc, min(so_number) limit 1), '') as cust_g \gset
select coalesce((select id::text from public.so where status = 'packed' and bill_to_customer_id = nullif(:'cust_g', '')::uuid order by so_number limit 1), '') as so_a \gset
select coalesce((select id::text from public.so where status = 'packed' and bill_to_customer_id = nullif(:'cust_g', '')::uuid order by so_number offset 1 limit 1), '') as so_b \gset
select coalesce((select currency_id::text from public.so where id = nullif(:'so_a', '')::uuid), '') as cur_g \gset
select (:'so_sr' <> '')::int as has_sr, (:'inv_m' <> '')::int as has_m, (:'inv_o' <> '')::int as has_o, (:'so_a' <> '' and :'so_b' <> '')::int as has_g \gset
select :has_sr as has_so_25251, :has_m as has_60073, :has_o as has_60019, :has_g as has_two_group, left(:'so_a', 8) as so_a, left(:'so_b', 8) as so_b,
       (select so_number from public.so where id = nullif(:'so_a', '')::uuid) as so_a_number, (select so_number from public.so where id = nullif(:'so_b', '')::uuid) as so_b_number,
       (select count(*) from public.so_credit c where c.customer_id = nullif(:'cust_g', '')::uuid and c.status = 'issued' and public.so_credit_remaining(c.id) > 0) as cust_g_live_credits, :'dfmt' as date_format;
-- 입력(화면 꼴): Ship & invoice 창이 보내는 orders[] 그대로 — so_id · charges(새 운임 줄 30.14 · Caleb 실물 관측과 같은 값) · carrier_id "" · carrier "" · tracking_number ""(so.html finBlockInput · finSend)
select jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so_sr', 'charges', jsonb_build_array(jsonb_build_object('name', 'Freight', 'amount', 30.14)), 'carrier_id', '', 'carrier', '', 'tracking_number', '')))::text as r_sr \gset
select jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so_a')))::text as r_a \gset
select jsonb_build_object('orders', jsonb_build_array(jsonb_build_object('so_id', :'so_a', 'invoice_group', 'g1'), jsonb_build_object('so_id', :'so_b', 'invoice_group', 'g2')))::text as r_g \gset
select jsonb_build_object('invoice_id', :'inv_m')::text as r_m, jsonb_build_object('invoice_id', :'inv_o')::text as r_o, jsonb_build_object('credit_id', :'cr_s')::text as r_cr, jsonb_build_object('so_id', :'so_s')::text as r_so \gset

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
  perform set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000d5201","role":"authenticated"}', true);
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
create function pg_temp.plan(p_orders jsonb, p_i int) returns jsonb language sql as $$ select pg_temp.j(pg_temp.asu(format('select (public.so_invoice_preview(%L::jsonb)->''docs''->%s->''plan'')::text', p_orders, p_i))) $$;
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
-- 시각만 뗀다(doc.printed_at · ship_ready 는 invoice.calc_at 도 분 단위) — 옛 = 새 비교 · 새 열쇠는 떼지 않는다(T4 는 네 kind 가 글자 그대로 같아야 한다)
create function pg_temp.strip_t(p jsonb) returns jsonb language sql as $$ select jsonb_set(p, '{doc}', coalesce(p->'doc', '{}'::jsonb) - 'printed_at') $$;
create function pg_temp.strip_docs(p jsonb) returns jsonb language sql as $$ select (select coalesce(jsonb_agg(pg_temp.strip_t(d) order by ord), '[]'::jsonb) from jsonb_array_elements(p->'docs') with ordinality t(d, ord)) $$;
-- 새 열쇠 셋(credits · totals.credits)과 시각을 뗀다 — ship_ready 옛 = 새(옛 열쇠 전부 그대로)
create function pg_temp.strip_sr(p jsonb) returns jsonb language sql as $$
  select (select coalesce(jsonb_agg(jsonb_set(jsonb_set(d - 'credits', '{doc}', coalesce(d->'doc', '{}'::jsonb) - 'printed_at'), '{totals}', coalesce(d->'totals', '{}'::jsonb) - 'credits') order by ord), '[]'::jsonb) from jsonb_array_elements(p->'docs') with ordinality t(d, ord)) $$;
-- 불변식 한 장(ship_ready): total − Σpayments − Σcredits = balance_due · Σpayments = paid · Σcredits = plan.credit · balance_due = due_amount(0 이면 "0.00" 와 "") · credits 줄 수 = auto_credit 걸음 수 · totals.credits = nz(합) · 줄마다 number · date · amount = 걸음 · reference = so_credit → so_invoice
create function pg_temp.sr_bad(p_doc jsonb, p_plan jsonb) returns text language plpgsql as $$
declare v_t numeric; v_p numeric; v_c numeric; v_b numeric; v_paid numeric; v_n int; v_bad text := ''; s jsonb; c jsonb; i int := 0; v_ref text;
begin
  if p_doc is null then return 'no-doc'; end if;
  if p_plan is null then return 'no-plan'; end if;
  v_t := pg_temp.num(p_doc->'totals'->>'total');  v_b := pg_temp.num(p_doc->'totals'->>'balance_due');  v_paid := pg_temp.num(p_doc->'totals'->>'paid');
  select coalesce(sum(pg_temp.num(x->>'amount')), 0) into v_p from jsonb_array_elements(p_doc->'payments') x;
  select coalesce(sum(pg_temp.num(x->>'amount')), 0) into v_c from jsonb_array_elements(coalesce(p_doc->'credits', '[]'::jsonb)) x;
  select count(*) into v_n from jsonb_array_elements(p_plan->'steps') x where x->>'step' = 'auto_credit';
  if not (p_doc ? 'credits') then v_bad := v_bad || ' no-credits-key'; end if;
  if round(v_t - v_p - v_c, 2) <> v_b then v_bad := v_bad || ' sum'; end if;
  if v_p <> v_paid then v_bad := v_bad || ' paid'; end if;
  if v_c <> round((p_plan->>'credit')::numeric, 2) then v_bad := v_bad || ' plan-credit'; end if;
  if v_b <> round((p_plan->>'left')::numeric, 2) then v_bad := v_bad || ' plan-left'; end if;
  if (p_doc->'totals'->>'balance_due') <> public.doc_fmt_money((p_plan->>'left')::numeric) then v_bad := v_bad || ' balance_due-text'; end if;
  if (p_doc->'totals'->>'due_amount') <> public.doc_fmt_money_nz((p_plan->>'left')::numeric) then v_bad := v_bad || ' due_amount-text'; end if;
  if (p_doc->'totals'->>'credits') <> public.doc_fmt_money_nz(v_c) then v_bad := v_bad || ' credits-text'; end if;
  if (p_doc->'totals'->>'credit_applied') <> public.doc_fmt_money_nz(v_c) then v_bad := v_bad || ' credit_applied-old'; end if;
  if jsonb_array_length(coalesce(p_doc->'credits', '[]'::jsonb)) <> v_n then v_bad := v_bad || ' rows'; end if;
  for s in select x from jsonb_array_elements(p_plan->'steps') x where x->>'step' = 'auto_credit' loop
    c := p_doc->'credits'->i;  i := i + 1;
    select coalesce((select oi.invoice_number from public.so_invoice oi where oi.id = cr.invoice_id), cr.ref_invoice_number, '') into v_ref from public.so_credit cr where cr.id = (s->>'credit_id')::uuid;
    if c is null or (c->>'no') <> i::text or (c->>'number') <> (s->>'credit_number') or (c->>'date') <> public.doc_fmt_date((s->>'issued_on')::date, (select coalesce(value, 'DDMONYYYY') from public.inv_config where key = 'doc_date_format')) or (c->>'amount') <> public.doc_fmt_money((s->>'amount')::numeric) or (c->>'reference') <> coalesce(v_ref, '') then
      v_bad := v_bad || format(' row%s(%s vs step %s ref %s)', i, c::text, s::text, v_ref);
    end if;
  end loop;
  return case when v_bad = '' then '' else format('%s [t %s p %s c %s b %s plan %s]', v_bad, v_t, v_p, v_c, v_b, (p_plan - 'steps')::text) end;
end $$;

-- ── 가짜 재료(replica · 트리거 없이) — 직원 1 ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values ('00000000-0000-4000-8000-0000000d5201', 'docsr1-sa@example.invalid', 'docsr1 sales', 'worker', '["sales"]', true) returning id::text as st \gset
set local session_replication_role = origin;

\if :{?mig}
-- ── O 시험에서만: 적용 전 옛 판 — 옛 출력을 받아 둔다 ──
select public.doc_field_catalog('final_invoice')::text as o_cat_fi, public.doc_field_catalog('ship_ready')::text as o_cat_sr, public.doc_field_catalog('internal_receipt')::text as o_cat_ir,
       public.doc_field_catalog('credit_note')::text as o_cat_cr, public.doc_field_catalog('sales_order')::text as o_cat_so \gset
select pg_temp.dd('ship_ready', :'r_sr'::jsonb)::text as o_sr, pg_temp.dd('ship_ready', :'r_a'::jsonb)::text as o_a,
       pg_temp.dd('final_invoice', :'r_m'::jsonb)::text as o_fm, pg_temp.dd('internal_receipt', :'r_m'::jsonb)::text as o_im, pg_temp.dd('final_invoice', :'r_o'::jsonb)::text as o_fo,
       pg_temp.dd('credit_note', :'r_cr'::jsonb)::text as o_cr, pg_temp.dd('sales_order', :'r_so'::jsonb)::text as o_so \gset
select pg_temp.chk('O1 시험에서만: 적용 전 = doc-cr-1 판(fmt 8bfd2523 · cat f8f5ab5b) · 옛 출력 일곱이 JSON · 옛 ship_ready 출력에 credits · totals.credits 없음 · 옛 ship_ready 카탈로그에 credits · totals.credits 없음 · SO-25251 옛 totals.credit_applied = balance_forward 부호 반대(이중 표시 실물) · deposit_applied = paid = Σpayments[](같은 돈)',
  :is_old = 1 and :'cat_md5_head' = 'f8f5ab5b78fb4d441e81a42a6f837bf7'
  and left(:'o_sr', 1) = '{' and left(:'o_a', 1) = '{' and left(:'o_fm', 1) = '{' and left(:'o_im', 1) = '{' and left(:'o_fo', 1) = '{' and left(:'o_cr', 1) = '{' and left(:'o_so', 1) = '{'
  and not ((pg_temp.j(:'o_sr')->'docs'->0) ? 'credits') and not ((pg_temp.j(:'o_sr')->'docs'->0->'totals') ? 'credits')
  and not ('credits' = any (pg_temp.cset(pg_temp.j(:'o_cat_sr')))) and not ('totals.credits' = any (pg_temp.cset(pg_temp.j(:'o_cat_sr'))))
  and (:has_sr = 0 or (pg_temp.num(pg_temp.j(:'o_sr')->'docs'->0->'totals'->>'credit_applied') = -pg_temp.num(pg_temp.j(:'o_sr')->'docs'->0->'totals'->>'balance_forward')
                      and pg_temp.num(pg_temp.j(:'o_sr')->'docs'->0->'totals'->>'deposit_applied') + pg_temp.num(pg_temp.j(:'o_sr')->'docs'->0->'totals'->>'paid') - pg_temp.num(pg_temp.j(:'o_sr')->'docs'->0->'totals'->>'deposit_applied') = (select coalesce(sum(pg_temp.num(x->>'amount')), 0) from jsonb_array_elements(pg_temp.j(:'o_sr')->'docs'->0->'payments') x))),
  format('%s | %s | sr %s | a %s | fm %s | sr totals %s', :'fmt_md5_head', :'cat_md5_head', left(:'o_sr', 60), left(:'o_a', 60), left(:'o_fm', 60), (pg_temp.j(:'o_sr')->'docs'->0->'totals')::text));
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('G1 시험에서만: 적용 뒤 둘 다 새 몸 · 함수 하나씩 · fmt 에 auto_credit · catalog 에 ship_ready 가드 없음',
  (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) <> '8bfd2523b9484ed1815d965040e6b3ec'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) <> 'f8f5ab5b78fb4d441e81a42a6f837bf7'
  and (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_field_catalog') and pronamespace = 'public'::regnamespace) = 2
  and (select prosrc from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) ~ 'auto_credit'
  and (select prosrc from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) !~ 'if p_kind <> ''ship_ready'' then',
  format('fmt %s cat %s', (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure)));
\else
select pg_temp.chk('G0 확인 실행: doc_data_invoice_fmt 가 있다 · 판 = ' || case when :is_old = 1 then '옛(doc-cr-1 · 적용 전 — 아래 갈래는 돌지 않는다)' else '새(doc-sr-1 · 통과 갈래)' end,
  :'fmt_md5_head' <> '(none)', :'fmt_md5_head');
\endif

\if :expect_pass
-- ── 새 출력 ──
select public.doc_field_catalog('final_invoice')::text as n_cat_fi, public.doc_field_catalog('ship_ready')::text as n_cat_sr, public.doc_field_catalog('internal_receipt')::text as n_cat_ir,
       public.doc_field_catalog('credit_note')::text as n_cat_cr, public.doc_field_catalog('sales_order')::text as n_cat_so \gset
select pg_temp.dd('ship_ready', :'r_sr'::jsonb)::text as n_sr, pg_temp.dd('ship_ready', :'r_a'::jsonb)::text as n_a,
       pg_temp.dd('final_invoice', :'r_m'::jsonb)::text as n_fm, pg_temp.dd('internal_receipt', :'r_m'::jsonb)::text as n_im, pg_temp.dd('final_invoice', :'r_o'::jsonb)::text as n_fo,
       pg_temp.dd('credit_note', :'r_cr'::jsonb)::text as n_cr, pg_temp.dd('sales_order', :'r_so'::jsonb)::text as n_so \gset
select pg_temp.plan((:'r_sr'::jsonb)->'orders', 0)::text as p_sr, pg_temp.plan((:'r_a'::jsonb)->'orders', 0)::text as p_a \gset
select pg_temp.chk('N0 새 출력 일곱이 다 JSON(가짜 직원 sales 로 doc_data) · 계획 둘(so_invoice_preview · 같은 입력)도 JSON',
  left(:'n_sr', 1) = '{' and left(:'n_a', 1) = '{' and left(:'n_fm', 1) = '{' and left(:'n_im', 1) = '{' and left(:'n_fo', 1) = '{' and left(:'n_cr', 1) = '{' and left(:'n_so', 1) = '{' and left(:'p_sr', 1) = '{' and left(:'p_a', 1) = '{',
  format('sr %s | a %s | fm %s | im %s | fo %s | cr %s | so %s | p_sr %s | p_a %s', left(:'n_sr', 80), left(:'n_a', 80), left(:'n_fm', 80), left(:'n_im', 80), left(:'n_fo', 80), left(:'n_cr', 80), left(:'n_so', 80), left(:'p_sr', 80), left(:'p_a', 80)));

-- ── T1 SO-25251 ship_ready(화면 입력 · 운임 30.14): credits[] 1 줄 이상 · Σcredits = 계획 credit · 불변식 · 줄 값 = 걸음 + so_credit → so_invoice ──
select pg_temp.chk('T1 SO-25251 ship_ready(화면 꼴 입력 · 운임 30.14): credits[] 1 줄 이상 · Σcredits = plan.credit = 옛 credit_applied(시험) · total − Σpayments[] − Σcredits = balance_due · balance_due = due_amount = plan.left · Σpayments = paid · 줄마다 number · date · amount = auto_credit 걸음 · reference = 원 인보이스 번호(so_credit.invoice_id → invoice_number · 없으면 ref_invoice_number · 없으면 "") · totals.credits = nz(합) · 장 하나(groups 1)',
  :has_sr = 1 and jsonb_array_length(pg_temp.j(:'n_sr')->'docs') = 1 and jsonb_array_length(pg_temp.j(:'n_sr')->'groups') = 1
  and jsonb_array_length(pg_temp.j(:'n_sr')->'docs'->0->'credits') >= 1
  and pg_temp.sr_bad(pg_temp.j(:'n_sr')->'docs'->0, pg_temp.j(:'p_sr')) = ''
  and (pg_temp.j(:'n_sr')->'docs'->0->'totals'->>'credits') <> '',
  format('has %s | bad [%s] | credits %s | totals %s | payments %s | plan %s', :has_sr, pg_temp.sr_bad(pg_temp.j(:'n_sr')->'docs'->0, pg_temp.j(:'p_sr')), (pg_temp.j(:'n_sr')->'docs'->0->'credits')::text, (pg_temp.j(:'n_sr')->'docs'->0->'totals')::text, (pg_temp.j(:'n_sr')->'docs'->0->'payments')::text, :'p_sr'));
select 'T1-실물: credits = ' || (pg_temp.j(:'n_sr')->'docs'->0->'credits')::text;
select 'T1-실물: totals  = ' || (pg_temp.j(:'n_sr')->'docs'->0->'totals')::text;
select 'T1-실물: payments = ' || (pg_temp.j(:'n_sr')->'docs'->0->'payments')::text;
\if :{?mig}
select pg_temp.chk('T1b 시험에서만: SO-25251 Σcredits(새) = 옛 credit_applied(적용 전 출력에서 셈) · 옛 열쇠 전부 글자 그대로(credits · totals.credits · 시각만 떼고 옛 = 새)',
  :has_sr = 1 and (select coalesce(sum(pg_temp.num(x->>'amount')), 0) from jsonb_array_elements(pg_temp.j(:'n_sr')->'docs'->0->'credits') x) = pg_temp.num(pg_temp.j(:'o_sr')->'docs'->0->'totals'->>'credit_applied')
  and pg_temp.strip_sr(pg_temp.j(:'n_sr')) = pg_temp.strip_sr(pg_temp.j(:'o_sr')) and pg_temp.strip_sr(pg_temp.j(:'n_a')) = pg_temp.strip_sr(pg_temp.j(:'o_a'))
  and (pg_temp.j(:'n_sr')->'groups') = (pg_temp.j(:'o_sr')->'groups'),
  format('old credit_applied %s | new Σ %s | old totals %s', pg_temp.j(:'o_sr')->'docs'->0->'totals'->>'credit_applied', (select coalesce(sum(pg_temp.num(x->>'amount')), 0) from jsonb_array_elements(pg_temp.j(:'n_sr')->'docs'->0->'credits') x), (pg_temp.j(:'o_sr')->'docs'->0->'totals')::text));
\endif

-- ── T2 크레딧 없는 오더(묶음 둘 손님의 첫 오더 · 가짜 크레딧을 넣기 전) ──
select pg_temp.chk('T2 크레딧 없는 오더(' || coalesce((select so_number from public.so where id = nullif(:'so_a', '')::uuid), '(없음)') || ' · 손님에게 남은 크레딧 0): credits = [] · totals.credits "" · 계획 credit 0 · 불변식 그대로',
  :has_g = 1 and (pg_temp.j(:'n_a')->'docs'->0->'credits') = '[]'::jsonb and (pg_temp.j(:'n_a')->'docs'->0->'totals'->>'credits') = ''
  and (pg_temp.j(:'p_a')->>'credit')::numeric = 0 and pg_temp.sr_bad(pg_temp.j(:'n_a')->'docs'->0, pg_temp.j(:'p_a')) = '',
  format('has_g %s | bad [%s] | totals %s | plan %s', :has_g, pg_temp.sr_bad(pg_temp.j(:'n_a')->'docs'->0, pg_temp.j(:'p_a')), (pg_temp.j(:'n_a')->'docs'->0->'totals')::text, :'p_a'));

-- ── T3 묶음 둘(같은 손님 · invoice_group g1 · g2) + 가짜 크레딧 CR-99980 5.00(이 손님 · replica) — 장마다 불변식 · ④ 관측(같은 크레딧이 두 장에 다 계획되는가) ──
set local session_replication_role = replica;
insert into public.so_credit (credit_number, status, customer_id, currency_id, currency_code, ref_invoice_number, reason, warehouse_id, issued_on, issued_by, lines_amount, total, created_by)
  select 'CR-99980', 'issued', :'cust_g'::uuid, :'cur_g'::uuid, 'CAD', '49980', 'other', :'wh'::uuid, public.ims_today(), :'st'::uuid, 5.00, 5.00, :'st'::uuid where :has_g = 1;
set local session_replication_role = origin;
select case when :has_g = 1 then pg_temp.dd('ship_ready', :'r_g'::jsonb)::text else '' end as n_g \gset
select case when :has_g = 1 then pg_temp.plan((:'r_g'::jsonb)->'orders', 0)::text else '' end as p_g0, case when :has_g = 1 then pg_temp.plan((:'r_g'::jsonb)->'orders', 1)::text else '' end as p_g1 \gset
\if :has_g
select pg_temp.chk('T3 묶음 둘(' || (select so_number from public.so where id = :'so_a'::uuid) || ' g1 · ' || (select so_number from public.so where id = :'so_b'::uuid) || ' g2 · 가짜 CR-99980 5.00 · ref_invoice_number 49980): docs 2 · groups 2 · 장마다 불변식 · 장마다 credits[] 1 줄 = CR-99980 · reference "49980"(Cin7 시절 꼴) · 각 장 Σcredits = 그 장의 계획',
  jsonb_array_length(pg_temp.j(:'n_g')->'docs') = 2 and jsonb_array_length(pg_temp.j(:'n_g')->'groups') = 2
  and pg_temp.sr_bad(pg_temp.j(:'n_g')->'docs'->0, pg_temp.j(:'p_g0')) = '' and pg_temp.sr_bad(pg_temp.j(:'n_g')->'docs'->1, pg_temp.j(:'p_g1')) = ''
  and (pg_temp.j(:'n_g')->'docs'->0->'credits'->0->>'number') = 'CR-99980' and (pg_temp.j(:'n_g')->'docs'->0->'credits'->0->>'reference') = '49980'
  and (pg_temp.j(:'n_g')->'docs'->1->'credits'->0->>'number') = 'CR-99980',
  format('bad0 [%s] bad1 [%s] | doc0 credits %s totals %s | doc1 credits %s totals %s', pg_temp.sr_bad(pg_temp.j(:'n_g')->'docs'->0, pg_temp.j(:'p_g0')), pg_temp.sr_bad(pg_temp.j(:'n_g')->'docs'->1, pg_temp.j(:'p_g1')),
         (pg_temp.j(:'n_g')->'docs'->0->'credits')::text, (pg_temp.j(:'n_g')->'docs'->0->'totals')::text, (pg_temp.j(:'n_g')->'docs'->1->'credits')::text, (pg_temp.j(:'n_g')->'docs'->1->'totals')::text));
select 'T3-관측(④): 장 둘의 크레딧 계획 합 = ' || ((select coalesce(sum(pg_temp.num(x->>'amount')), 0) from jsonb_array_elements(pg_temp.j(:'n_g')->'docs'->0->'credits') x) + (select coalesce(sum(pg_temp.num(x->>'amount')), 0) from jsonb_array_elements(pg_temp.j(:'n_g')->'docs'->1->'credits') x))::text
       || ' · 크레딧 남은 돈 = ' || public.so_credit_remaining((select id from public.so_credit where credit_number = 'CR-99980'))::text || ' · 장 1 total ' || (pg_temp.j(:'n_g')->'docs'->0->'totals'->>'total') || ' · 장 2 total ' || (pg_temp.j(:'n_g')->'docs'->1->'totals'->>'total')
       || ' → 합이 남은 돈보다 크면 미리 보기가 같은 크레딧을 두 장에 다 계획한 것(발행은 장마다 붙여 가며 줄어든다 · so_invoice_preview 20261020010711:909 · 이 차수 무접촉)';
\else
select 'T3 안 봤다 — packed 오더가 둘 이상인 손님이 테스트 DB 에 없다';
\endif

-- ── T4 네 kind 출력이 적용 전과 같다(같은 ref · 시각 printed_at 만 떼고 md5) ──
\if :{?mig}
select pg_temp.chk('T4 시험에서만: final_invoice(60073 · 60019) · internal_receipt(60073) · credit_note · sales_order 출력이 적용 전과 같다(같은 ref · doc.printed_at 만 떼고 md5 같음 · 글자 그대로) · 카탈로그 final_invoice · internal_receipt · credit_note · sales_order 바이트 같음',
  md5(pg_temp.strip_docs(pg_temp.j(:'n_fm'))::text) = md5(pg_temp.strip_docs(pg_temp.j(:'o_fm'))::text) and md5(pg_temp.strip_docs(pg_temp.j(:'n_im'))::text) = md5(pg_temp.strip_docs(pg_temp.j(:'o_im'))::text)
  and md5(pg_temp.strip_docs(pg_temp.j(:'n_fo'))::text) = md5(pg_temp.strip_docs(pg_temp.j(:'o_fo'))::text)
  and md5(pg_temp.strip_docs(pg_temp.j(:'n_cr'))::text) = md5(pg_temp.strip_docs(pg_temp.j(:'o_cr'))::text) and md5(pg_temp.strip_docs(pg_temp.j(:'n_so'))::text) = md5(pg_temp.strip_docs(pg_temp.j(:'o_so'))::text)
  and :'n_cat_fi' = :'o_cat_fi' and :'n_cat_ir' = :'o_cat_ir' and :'n_cat_cr' = :'o_cat_cr' and :'n_cat_so' = :'o_cat_so',
  format('fm %s=%s | im %s=%s | fo %s=%s | cr %s=%s | so %s=%s | raw md5 equal fm %s cr %s so %s', left(md5(pg_temp.strip_docs(pg_temp.j(:'o_fm'))::text), 8), left(md5(pg_temp.strip_docs(pg_temp.j(:'n_fm'))::text), 8), left(md5(pg_temp.strip_docs(pg_temp.j(:'o_im'))::text), 8), left(md5(pg_temp.strip_docs(pg_temp.j(:'n_im'))::text), 8),
         left(md5(pg_temp.strip_docs(pg_temp.j(:'o_fo'))::text), 8), left(md5(pg_temp.strip_docs(pg_temp.j(:'n_fo'))::text), 8), left(md5(pg_temp.strip_docs(pg_temp.j(:'o_cr'))::text), 8), left(md5(pg_temp.strip_docs(pg_temp.j(:'n_cr'))::text), 8), left(md5(pg_temp.strip_docs(pg_temp.j(:'o_so'))::text), 8), left(md5(pg_temp.strip_docs(pg_temp.j(:'n_so'))::text), 8),
         md5(:'n_fm') = md5(:'o_fm'), md5(:'n_cr') = md5(:'o_cr'), md5(:'n_so') = md5(:'o_so')));
select 'T4-raw md5(시각 안 뗀 것 · 분이 넘어가면 다를 수 있다): fm ' || (md5(:'n_fm') = md5(:'o_fm'))::text || ' im ' || (md5(:'n_im') = md5(:'o_im'))::text || ' fo ' || (md5(:'n_fo') = md5(:'o_fo'))::text || ' cr ' || (md5(:'n_cr') = md5(:'o_cr'))::text || ' so ' || (md5(:'n_so') = md5(:'o_so'))::text;
\endif

-- ── T5 카탈로그 ↔ 출력 열쇠 대조 — ship_ready(srs_1_check T3 · T4 꼴) ──
\if :{?mig}
select pg_temp.chk('T5a 시험에서만 열쇠 대조 옛 = 새(ship_ready SO-25251 · 묶음 둘 손님 오더): 출력 − 카탈로그 · 카탈로그 − 출력 이 옛과 같다(새 열쇠는 양쪽에 같이) · ship_ready 카탈로그 allowed = 옛 + 여섯(credits.no·number·date·reference·amount · totals.credits) · sections = 옛 + credits · required 그대로',
  pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_sr')))
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0)) = pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_sr')), pg_temp.pset(pg_temp.j(:'o_sr')->'docs'->0))
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_a')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))) = pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_a')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_sr')))
  and (select array_agg(x order by x) from jsonb_array_elements_text(pg_temp.j(:'n_cat_sr')->'allowed') x) = (select array_agg(x order by x) from (select jsonb_array_elements_text(pg_temp.j(:'o_cat_sr')->'allowed') union all select unnest(array['credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits'])) t(x))
  and (pg_temp.j(:'n_cat_sr')->'sections') = (pg_temp.j(:'o_cat_sr')->'sections') || '["credits"]'::jsonb and (pg_temp.j(:'n_cat_sr')->'required') = (pg_temp.j(:'o_cat_sr')->'required'),
  format('sr out−cat old %s new %s | cat−out old %s new %s | allowed old %s new %s', pg_temp.minus(pg_temp.pset(pg_temp.j(:'o_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'o_cat_sr'))), pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))),
         pg_temp.minus(pg_temp.cset(pg_temp.j(:'o_cat_sr')), pg_temp.pset(pg_temp.j(:'o_sr')->'docs'->0)), pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0)), jsonb_array_length(pg_temp.j(:'o_cat_sr')->'allowed'), jsonb_array_length(pg_temp.j(:'n_cat_sr')->'allowed')));
\endif
select pg_temp.chk('T5 열쇠 대조(새 판): credits · credits.no·number·date·reference·amount · totals.credits · totals.balance_due 가 ship_ready 의 카탈로그 · 출력(SO-25251) 양쪽에 · ship_ready 카탈로그 = final_invoice 카탈로그 − {invoice.number · orders.lines.final_sale} + {invoice.calc_at} · 출력 − 카탈로그 = {orders.lines.final_sale}(bgr-1d 부터 · deferred 344) · credit_note · sales_order 카탈로그 · 출력엔 credits 없음',
  pg_temp.cset(pg_temp.j(:'n_cat_sr')) @> array['credits', 'credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due']
  and pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0) @> array['credits', 'credits.no', 'credits.number', 'credits.date', 'credits.reference', 'credits.amount', 'totals.credits', 'totals.balance_due']
  and pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))) = array['orders.lines.final_sale']
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.cset(pg_temp.j(:'n_cat_fi'))) = array['invoice.calc_at']
  and pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_fi')), pg_temp.cset(pg_temp.j(:'n_cat_sr'))) = array['invoice.number', 'orders.lines.final_sale']
  and not ('credits' = any (pg_temp.cset(pg_temp.j(:'n_cat_cr')))) and not ('credits' = any (pg_temp.cset(pg_temp.j(:'n_cat_so')))) and not ('credits' = any (pg_temp.pset(pg_temp.j(:'n_cr')->'docs'->0))) and not ('credits' = any (pg_temp.pset(pg_temp.j(:'n_so')->'docs'->0))),
  format('sr out−cat %s | cat−out %s | sr−fi %s | fi−sr %s', pg_temp.minus(pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0), pg_temp.cset(pg_temp.j(:'n_cat_sr'))), pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.pset(pg_temp.j(:'n_sr')->'docs'->0)),
         pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_sr')), pg_temp.cset(pg_temp.j(:'n_cat_fi'))), pg_temp.minus(pg_temp.cset(pg_temp.j(:'n_cat_fi')), pg_temp.cset(pg_temp.j(:'n_cat_sr')))));

-- ── T6 REST 첫 겹(정적): 다시 낸 두 함수의 몸에 update · delete 문이 있는가 ──
select (select count(*) from pg_proc where oid in ('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'public.doc_field_catalog(text)'::regprocedure) and prosrc ~* '(^|[\s;])(update|delete)\s') as n_ud \gset
select pg_temp.chk('T6 REST 첫 겹(정적): 다시 낸 doc_data_invoice_fmt · doc_field_catalog 몸에 update · delete 문 0 → WHERE 깊이 검사 해당 없음(둘 다 읽기만 · STABLE · IMMUTABLE)', :n_ud = 0, format('update/delete 가 있는 함수 %s', :n_ud));

-- ── D 그리기 직접 · 판 검사 ──
select pg_temp.chk('D1 그리기 직접(postgres · 중립 jsonb · ship_ready = plan): auto_credit 둘 → no 1·2 · 번호 · 날짜 꼴 · 금액 · reference(가짜 credit_id → "") · 합 "4.50" · balance_due = due_amount "4.50" · 옛 열쇠(credit_applied "4.50" · balance_forward "-4.50" · deposit_applied "1.00" · paid "1.00") 그대로 · 걸음 없으면 [] · "" · plan 열쇠 없어도 [] · ""',
  (select jsonb_array_length(d->'credits') = 2 and (d->'credits'->0) = '{"no":"1","date":"28OCT2026","amount":"3.00","number":"CR-00001","reference":""}'::jsonb and (d->'credits'->1->>'no') = '2' and (d->'totals'->>'credits') = '4.50' and (d->'totals'->>'balance_due') = '4.50' and (d->'totals'->>'due_amount') = '4.50'
          and (d->'totals'->>'credit_applied') = '4.50' and (d->'totals'->>'balance_forward') = '-4.50' and (d->'totals'->>'deposit_applied') = '1.00' and (d->'totals'->>'paid') = '1.00'
     from public.doc_data_invoice_fmt('ship_ready', jsonb_build_object('date_format', 'DDMONYYYY', 'unit_display', 'both'),
           '{"header":{},"orders":[],"charges":[],"payments":[{"reference":"x","paid_on":"2026-10-29","method":"cash","amount":1}],"totals":{"total":10,"amount_due":4.5,"deposit_applied":1,"credit_applied":4.5,"balance_forward":-4.5,"paid":1},"plan":{"deposit":1,"credit":4.5,"balance":0,"left":4.5,"steps":[{"step":"auto_deposit","payment_id":"00000000-0000-4000-8000-000000000001","amount":1,"paid_on":"2026-10-29"},{"step":"auto_credit","credit_id":"00000000-0000-4000-8000-000000000002","credit_number":"CR-00001","amount":3,"issued_on":"2026-10-28"},{"step":"auto_credit","credit_id":"00000000-0000-4000-8000-000000000003","credit_number":"CR-00002","amount":1.5,"issued_on":"2026-10-29"}]}}'::jsonb) d)
  and (select (d->'credits') = '[]'::jsonb and (d->'totals'->>'credits') = '' from public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{},"orders":[],"charges":[],"payments":[],"totals":{"total":10,"amount_due":10},"plan":{"steps":[]}}'::jsonb) d)
  and (select (d->'credits') = '[]'::jsonb and (d->'totals'->>'credits') = '' from public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{},"orders":[],"charges":[],"payments":[],"totals":{"total":10,"amount_due":10}}'::jsonb) d),
  (public.doc_data_invoice_fmt('ship_ready', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{},"orders":[],"charges":[],"payments":[],"totals":{"total":10,"amount_due":4.5},"plan":{"steps":[{"step":"auto_credit","credit_id":"00000000-0000-4000-8000-000000000002","credit_number":"CR-00001","amount":3,"issued_on":"2026-10-28"}]}}'::jsonb) - 'company' - 'branches' - 'bill_to' - 'doc' - 'show')::text);
select pg_temp.chk('D2 그리기 직접(final_invoice · internal_receipt): 적재의 credits[] 만 본다 — plan 에 auto_credit 이 있어도 안 싣는다(doc-cr-1 그대로)',
  (select jsonb_array_length(d->'credits') = 2 and d::text !~ 'CR-77777' and (d->'totals'->>'credits') = '2.00' from public.doc_data_invoice_fmt('final_invoice', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb,
     '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"credits":[{"credit_number":"CR-00001","issued_on":"2026-10-28","reference":"60070","amount":0.8},{"credit_number":"CR-00002","issued_on":"2026-10-27","reference":null,"amount":1.2}],"totals":{"total":2,"remaining":0},"plan":{"steps":[{"step":"auto_credit","credit_id":"00000000-0000-4000-8000-000000000002","credit_number":"CR-77777","amount":3,"issued_on":"2026-10-28"}]}}'::jsonb) d)
  and (select (d->'credits') = '[]'::jsonb and (d->'totals'->>'credits') = '' and (d->'totals'->>'balance_due') = '1.00' from public.doc_data_invoice_fmt('internal_receipt', '{"date_format":"DDMONYYYY","unit_display":"both"}'::jsonb, '{"header":{"number":"1"},"orders":[],"charges":[],"payments":[],"totals":{"total":1,"remaining":1},"plan":{"steps":[{"step":"auto_credit","credit_number":"CR-77777","amount":3}]}}'::jsonb) d),
  'fmt');
select body as v_active_sr from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'ship_ready') \gset
select body as v_active_fi from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'final_invoice') \gset
select pg_temp.chk('D3 doc_template_check: v9 꼴 판(Credits 표 · {{#reference}} · totals.credits · balance_due)이 ship_ready 에서 통과 · 쓰는 ship_ready 판 v' || (select version from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'ship_ready')) || '(옛 열쇠만)은 여전히 통과(required 무접촉) · 쓰는 final_invoice v' || (select version from public.doc_template t where t.id = (select template_id from public.doc_template_active where kind = 'final_invoice')) || ' 판 본문을 ship_ready kind 로 검사하면 invoice.number 가 unknown_field(= ship_ready 판은 따로 써야 한다 · calc_at)',
  (public.doc_template_check('ship_ready', '<div>{{#orders}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.calc_at}} {{totals.tax}} {{totals.total}} <tr data-due="{{totals.due_amount}}"></tr> {{#credits}}{{no}} {{number}} {{date}} {{#reference}}(Invoice {{reference}}){{/reference}} {{amount}}{{/credits}}{{#totals.credits}}{{totals.credits}}{{/totals.credits}}{{totals.balance_due}}</div>', 'template')->>'ok')::boolean
  and (public.doc_template_check('ship_ready', :'v_active_sr', 'template')->>'ok')::boolean
  and exists (select 1 from jsonb_array_elements(public.doc_template_check('ship_ready', :'v_active_fi', 'template')->'problems') p where p->>'code' = 'unknown_field' and p->>'tag' = '{{invoice.number}}'),
  format('v9 꼴 %s | active sr %s | fi-as-sr %s', left(public.doc_template_check('ship_ready', '<div>{{#orders}}{{#lines}}{{sku}}{{/lines}}{{/orders}}{{invoice.calc_at}} {{totals.tax}} {{totals.total}} <tr data-due="{{totals.due_amount}}"></tr> {{#credits}}{{no}} {{number}} {{date}} {{#reference}}(Invoice {{reference}}){{/reference}} {{amount}}{{/credits}}{{#totals.credits}}{{totals.credits}}{{/totals.credits}}{{totals.balance_due}}</div>', 'template')::text, 200),
         left(public.doc_template_check('ship_ready', :'v_active_sr', 'template')::text, 120), left(public.doc_template_check('ship_ready', :'v_active_fi', 'template')::text, 300)));
select pg_temp.chk('L1 함수 모양(새 판): fmt STABLE · catalog IMMUTABLE · ACL 둘 머리와 같다 · authenticated 는 fmt 못 부르고 catalog 는 부른다 · anon 둘 다 못 부른다 · comment 둘에 874 · 864 · 787 · 함수 하나씩',
  (select provolatile from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure) = 's'
  and (select provolatile from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure) = 'i'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), '(none)') = :'fmt_acl_head'
  and coalesce((select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure), '(none)') = :'cat_acl_head'
  and not has_function_privilege('authenticated', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') and has_function_privilege('authenticated', 'public.doc_field_catalog(text)', 'execute')
  and not has_function_privilege('anon', 'public.doc_data_invoice_fmt(text, jsonb, jsonb)', 'execute') and not has_function_privilege('anon', 'public.doc_field_catalog(text)', 'execute')
  and obj_description('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'pg_proc') ~ '874' and obj_description('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'pg_proc') ~ '864' and obj_description('public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure, 'pg_proc') ~ '787'
  and obj_description('public.doc_field_catalog(text)'::regprocedure, 'pg_proc') ~ '874' and obj_description('public.doc_field_catalog(text)'::regprocedure, 'pg_proc') ~ '864' and obj_description('public.doc_field_catalog(text)'::regprocedure, 'pg_proc') ~ '787'
  and (select count(*) from pg_proc where proname in ('doc_data_invoice_fmt', 'doc_field_catalog') and pronamespace = 'public'::regnamespace) = 2,
  format('fmt acl %s | cat acl %s', (select proacl::text from pg_proc where oid = 'public.doc_data_invoice_fmt(text, jsonb, jsonb)'::regprocedure), (select proacl::text from pg_proc where oid = 'public.doc_field_catalog(text)'::regprocedure)));
\endif

-- ── Z 무접촉 ──
select pg_temp.chk('Z1 무접촉: doc_data_invoice(5fcac178 · doc-cr-1) · so_invoice_preview(6a36efcb) · so_invoice_apply_plan(6eb27944) · so_invoice_issue(7a031482) · so_invoice_remaining(505f62c6) · doc_data(400358fa) · doc_data_ship_ready(446fa345) · doc_data_credit · doc_data_so · doc_template_check · doc_mail_send · doc_mail_fill 몸 그대로 · 쓰는 판(doc_template_active) · doc_file 스냅샷 그대로 · so_invoice 행 수 · packed 오더 수 그대로',
  (select md5(prosrc) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) = '5fcac178ab84816f339e1b8c6b9a82dd'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure) = '6a36efcbd4de5f06cb4d818ab12233ab'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_apply_plan(uuid, uuid, uuid[], numeric)'::regprocedure) = '6eb279442ae55f380d2fe2c685a82290'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_issue(uuid[], uuid, date)'::regprocedure) = '7a03148223048349d2b9d461969ca3f6'
  and (select md5(prosrc) from pg_proc where oid = 'public.so_invoice_remaining(uuid)'::regprocedure) = '505f62c60461e326e5f1cac598f08cb7'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data(text, jsonb)'::regprocedure) = '400358fa6e488d514039cdc9705e6d39'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_ship_ready(jsonb, jsonb)'::regprocedure) = '446fa345c99b64ba39ed0d67bdceeaac'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_credit(uuid, jsonb)'::regprocedure) = '017c7f9b5111995d418a6d5888d27bda'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) = '904414a209c081eb2900bfe5daa935c3'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_template_check(text, text, text)'::regprocedure) = '26b1075a117087a42a061531c785f821'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)'::regprocedure) = '98f93aaa243f111befdad7eeb9a0eb1e'
  and (select md5(prosrc) from pg_proc where oid = 'public.doc_mail_fill(text, jsonb)'::regprocedure) = '42c3f7b742c66dd7698a17e15387197d'
  and (select md5(coalesce(string_agg(t.kind || ':' || t.template_id::text, '|' order by t.kind), '')) || ' ' || count(*) from public.doc_template_active t) = :'snap_ta'
  and (select md5(coalesce(string_agg(t.id::text || ':' || t.path || ':' || t.sha256, '|' order by t.id), '')) || ' ' || count(*) from public.doc_file t) = :'snap_df'
  and (select count(*) from public.so_invoice) = :n_inv_head and (select count(*) from public.so where status = 'packed') = :n_packed_head,
  format('ld %s pv %s plan %s', (select left(md5(prosrc), 8) from pg_proc where oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure), (select left(md5(prosrc), 8) from pg_proc where oid = 'public.so_invoice_apply_plan(uuid, uuid, uuid[], numeric)'::regprocedure)));
select 'begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text as elapsed;
\pset tuples_only off
\pset format aligned
rollback;
-- ── rollback 뒤 — 가짜 흔적 0 · 실물 스냅샷 머리 그대로(시퀀스는 당기지 않았다 — 크레딧 번호 명시) ──
\pset format unaligned
\pset tuples_only on
select pg_temp.chk('Z2 rollback 뒤: 가짜 직원 0 · 가짜 크레딧 0 · so_credit 스냅샷 머리와 같다 · 직원 수 그대로',
  (select count(*) from public.ims_staff where email like 'docsr1-%') = 0 and (select count(*) from public.so_credit where credit_number = 'CR-99980') = 0
  and (select md5(coalesce(string_agg(t.id::text || ':' || t.credit_number || ':' || t.status || ':' || t.total, '|' order by t.id), '')) || ' ' || count(*) from public.so_credit t) = :'snap_cr'
  and (select count(*) from public.ims_staff) = :n_staff_head,
  format('staff %s cr %s', (select count(*) from public.ims_staff where email like 'docsr1-%'), (select count(*) from public.so_credit where credit_number = 'CR-99980')));
\pset tuples_only off
\pset format aligned
-- 기대 OK: 시험(-v mig) 17(O1 G1 N0 T1 T1b T2 T3 T4 T5a T5 T6 D1 D2 D3 L1 Z1 Z2 · MISMATCH 0 · begin ~ rollback 1.7 ~ 2.0 초 · 3 회차 통과 — 1 회차 sr_bad 안의 psql 변수 :'dfmt'(함수 몸 $$ 안) 문법 오류 · 2 회차 D3 problems 열쇠 field → tag · 둘 다 검증 파일 쪽) · 마른(적용 전 · -v mig 없음) 3(G0 Z1 Z2 · 실측) · 확인(적용 뒤 · -v mig 없음) 13(계산 = G0 N0 T1 T2 T3 T5 T6 D1 D2 D3 L1 Z1 Z2 — Caleb 확인 실행이 첫 통과)
