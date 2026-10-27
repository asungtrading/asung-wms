-- supabase/tests/ar_2b_check.sql — ar-2b so_opening_load REST(safeupdate) 21000 고침 검증 (2026-10-27 UTC · 판정 789)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · 잠금 규칙) — 기준(begin 앞 · 잠금 없음 · 고치기 전 prosrc 담기) → begin(lock_timeout 3s) → (-v mig 면 \i) → 가짜 재료 → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027024747_ar_2b_rest_safeupdate.sql -f supabase/tests/ar_2b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 S1 하나(고치기 전 prosrc 의 WHERE 없는 update 수: 시험 4 · 확인 0) · 기대 OK 수는 같다
--   ⚠️ psql 직결은 safeupdate 를 못 싣는다(load · PGOPTIONS · set 셋 다 막힘 · 2026-10-26 실측) ⇒ 여기의 「재현 · 통과」 는 정적 셈(깊이 0 WHERE 스캐너 · safeupdate 의 규칙 = UPDATE · DELETE 의 최상위 WHERE 없음 → 21000)
--      실제 REST 통과는 테스트 프로젝트 REST 를 curl 로(회신 명령) — 이 파일이 대신하지 않는다
--   쓰기: 가짜 직원 1 · 가짜 손님 1 · 이월 인보이스 1 · 이월 결제 1 — 전부 rollback · 번호 시퀀스는 당기지 않는다(옛 번호 명시)
\set ON_ERROR_STOP on
\set EXPECT_OK 18
\pset pager off
-- 기준(begin 앞 · 잠금 없음) — 고치기 전 prosrc 를 담아 둔다(시험 갈래 = 옛 판 · 확인 갈래 = 이미 고친 판)
create temp table t_pre as
  select proname, prosrc, md5(prosrc) as md5 from pg_proc where pronamespace = 'public'::regnamespace
   and proname in ('so_invoice_remaining', 'doc_mail_auto_invoice', 'drive_archive_on_issue', 'so_invoice_cancel', 'so_payment_void', 'doc_data_invoice', 'so_opening_load',
                   'hist_line_kind', 'hist_credit_lines', 'hist_credit_tax', 'hist_credit_source', 'so_credit_issue', 'so_credit_detail', 'doc_data_credit');
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
select (select count(*) from public.so_invoice) as n_inv, (select count(*) from public.so_payment) as n_pay, (select count(*) from public.so_payment_alloc) as n_alloc,
       (select count(*) from public.customer) as n_cust, (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.so_credit) as n_cred,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load') as n_fn0,
       (select md5 from t_pre where proname = 'so_opening_load') as pre_md5, (select count(*) from t_pre) as n_pre \gset
\echo '── 기준: so_invoice' :n_inv '· so_payment' :n_pay '· alloc' :n_alloc '· customer' :n_cust '· staff' :n_staff '· credit' :n_cred '· inv seq' :inv_seq_last :inv_seq_called '· cr seq' :cr_seq_last :cr_seq_called '· so_opening_load in pg_proc' :n_fn0 '· pre md5' :pre_md5 '· t_pre rows' :n_pre
\if :{?mig}
\set pre_want 4
\else
\set pre_want 0
\endif
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.chkb(p_name text, p_ok boolean, p_note text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, coalesce(p_ok, false), coalesce(p_ok::text, 'null'), p_note);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- safeupdate 의 규칙을 정적으로 센다: 함수 본문의 문장마다(; 로 가른다 · -- 주석 제거) 머리 동사가 update · delete(plpgsql 의 then · else · loop · begin 뒤 포함) 또는 with 뒤 최상위 update · delete 이고
--   괄호 묶음을 모두 걷어낸 뒤(깊이 0 만 남긴다) where 가 없으면 하나 — 서브쿼리 안의 where 는 세지 않는다(그것이 safeupdate 가 보는 jointree quals 와 같다)
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- service_role 로 창구 부르기(REST 와 같은 역할 · 끝나면 되돌린다)
create function pg_temp.load(p jsonb, p_dry boolean) returns jsonb language plpgsql as $$
declare v jsonb; v_claims text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute 'set local role service_role';
  v := public.so_opening_load(p, p_dry);
  execute 'reset role';
  perform set_config('request.jwt.claims', v_claims, true);
  return v;
end $$;

-- ── S) 정적: safeupdate 조건의 재현(고치기 전 판) · 통과(지금 판) ──
select pg_temp.chk('S0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text, '1011110');
select pg_temp.chk('S1 재현: 고치기 전 so_opening_load(= begin 앞 prosrc · md5 ' || :'pre_md5' || ') 의 WHERE 없는 update · delete 수 — 시험 갈래 4(ar2_inv.reason · ar2_inv.action · ar2_cr.reason · ar2_crg.action) · 확인 갈래 0',
  (select pg_temp.nowhere(prosrc)::text from t_pre where proname = 'so_opening_load'), :'pre_want');
select pg_temp.chk('S2 재현: 고치기 전 ar-2 · hcr-1 함수 14 전체의 WHERE 없는 update · delete 합 — so_opening_load 몫뿐', (select sum(pg_temp.nowhere(prosrc))::text from t_pre), :'pre_want');
select pg_temp.chk('S3 통과: 지금 판 so_opening_load 의 WHERE 없는 update · delete 0', (select pg_temp.nowhere(prosrc)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load'), '0');
select pg_temp.chk('S4 통과: 지금 판 14 함수 전부 0 (함수마다 「이름 0」)',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in (select proname from t_pre)),
  (select string_agg(proname || ' 0', ' · ' order by proname) from t_pre));
select pg_temp.chk('S5 so_opening_load prosrc = ar-2b 파일 본문(md5) · 함수 하나', (select md5(prosrc) || ' ' || count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load' group by prosrc), 'c721e260f8254dbe5239f6ba0f946ec5 1');
select pg_temp.chkb('S6 WHERE 넷이 본문에 있다 · 옛 꼴 넷은 없다', (select prosrc like '%end where i.reason is null;%' and prosrc like '%else ''update'' end where i.action is null;%' and prosrc like '%end where r.reason is null;%' and prosrc like '%''branch_unresolved'' end where g.action is null;%'
  and prosrc not like '%else ''update'' end;%' and prosrc not like '%''branch_unresolved'' end;%' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load'), 'four new · old gone');
select pg_temp.chkb('S7 ACL · definer · comment 그대로: service_role 만 · definer · comment 머리 「ar-2 판정 775 · 783 ~ 786」',
  (select p.prosecdef from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_opening_load') and has_function_privilege('service_role', 'public.so_opening_load(jsonb, boolean)', 'execute')
  and not has_function_privilege('authenticated', 'public.so_opening_load(jsonb, boolean)', 'execute') and not has_function_privilege('anon', 'public.so_opening_load(jsonb, boolean)', 'execute')
  and coalesce(obj_description('public.so_opening_load(jsonb, boolean)'::regprocedure, 'pg_proc'), '') like 'ar-2 판정 775 · 783 ~ 786%', 'service_role only · definer · comment kept');
select pg_temp.chk('S8 다른 13 함수는 무접촉(prosrc md5 begin 앞 = 지금)', (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 where t.proname <> 'so_opening_load'), '13');

-- ── F) 기능: service_role 로 같은 입력 → 판단 칸(reason · action)이 모든 행에 여전히 찍힌다 ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'ar2b-s@test.invalid', 'AR2B S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid \gset
\set s '{"sub":"' :s_uid '","role":"authenticated"}'
select set_config('request.jwt.claims', :'s', true) as staff_claims_set \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as tor, name as tor_name from public.ref_warehouse where is_active and name not ilike '%edmonton%' order by name limit 1 \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
select public.ims_today() as today \gset
set local session_replication_role = replica;
insert into public.customer (name, source, cin7_id, currency_id, currency_code, default_location_id, default_location_name, payment_term_id, payment_term_name)
  values ('AR2B HQ', 'manual', gen_random_uuid(), :'cad'::uuid, 'CAD', :'tor'::uuid, :'tor_name', :'pt30'::uuid, :'pt30_name') returning id::text as hq, cin7_id::text as hq_c7 \gset
set local session_replication_role = origin;
set constraints all immediate;
select pg_temp.chkb('F0 가짜 재료: 직원 · 손님 HQ(cin7_id · CAD · 브랜치 · 결제조건 ' || :'pt30_name' || ')', :'s_uid' <> '' and :'hq' <> '' and :'pt30' <> '' and :'tor' <> '', 'see F0');
-- 입력: 인보이스 둘(79921 좋음 · X1 번호 틀림) · 받아 둔 돈 둘(20.00 좋음 · 0 금액 틀림) — 거부 줄의 reason 과 좋은 줄의 action 이 함께 찍혀야 넷의 WHERE 가 「모든 행」임이 선다
\set inp_good_total 110.00
select jsonb_build_object('as_of', :'today', 'complete', false,
  'invoices', jsonb_build_array(
    jsonb_build_object('legacy_sale_id', 'ar2b-sale-1', 'legacy_invoice_id', 'ar2b-task-1', 'invoice_number', '79921', 'cin7_customer_id', :'hq_c7', 'issued_on', (:'today'::date - 10)::text, 'payment_term_name', :'pt30_name', 'currency', 'CAD', 'total_before_tax', 100.00, 'tax', 10.00, 'total', :inp_good_total, 'prior_settled', 10.00),
    jsonb_build_object('legacy_sale_id', 'ar2b-sale-2', 'legacy_invoice_id', 'ar2b-task-2', 'invoice_number', 'X1', 'cin7_customer_id', :'hq_c7', 'issued_on', :'today', 'currency', 'CAD', 'total_before_tax', 10, 'tax', 0, 'total', 10)),
  'credits', jsonb_build_array(
    jsonb_build_object('cin7_customer_id', :'hq_c7', 'currency', 'CAD', 'amount', 20.00, 'source', 'credit', 'reference', 'ar2b credit'),
    jsonb_build_object('cin7_customer_id', :'hq_c7', 'currency', 'CAD', 'amount', 0, 'source', 'overpay', 'reference', 'ar2b zero')))::text as inp \gset
select pg_temp.load(:'inp'::jsonb, true)::text as dry1 \gset
select pg_temp.chk('F1 Dry(service_role): invoices in 2 · inserted 1 · rejected 1 · reject reason number_invalid(seq 2) · credits rows_in 2 · groups 1 · inserted 1 · rejected 1 · reason amount_invalid(seq 2)',
  format('%s %s %s %s %s %s %s %s %s %s', :'dry1'::jsonb#>>'{invoices,in}', :'dry1'::jsonb#>>'{invoices,inserted}', :'dry1'::jsonb#>>'{invoices,rejected}', :'dry1'::jsonb#>>'{invoices,rejects,0,reason}', :'dry1'::jsonb#>>'{invoices,rejects,0,seq}',
         :'dry1'::jsonb#>>'{credits,rows_in}', :'dry1'::jsonb#>>'{credits,groups}', :'dry1'::jsonb#>>'{credits,inserted}', :'dry1'::jsonb#>>'{credits,rejected}', :'dry1'::jsonb#>>'{credits,rejects,0,reason}'), '2 1 1 number_invalid 2 2 1 1 1 amount_invalid');
select pg_temp.chk('F2 Dry 는 쓰기 0 (opening 인보이스 · opening 결제 행 수 = begin 앞)', (select count(*) from public.so_invoice where kind = 'opening' and legacy_invoice_id like 'ar2b-%')::text || ' ' || (select count(*) from public.so_payment where method = 'opening' and customer_id = :'hq'::uuid)::text, '0 0');
select pg_temp.load(:'inp'::jsonb, false)::text as ap1 \gset
select pg_temp.chk('F3 Apply: 같은 판단(inserted 1/1) · so_invoice opening 79921 · total 110.00 · prior_settled 10.00 · remaining 100.00 · so_payment opening 20.00 · account _1150040009_',
  format('%s %s %s %s', :'ap1'::jsonb#>>'{invoices,inserted}', :'ap1'::jsonb#>>'{credits,inserted}',
    (select format('%s %s %s %s', i.invoice_number, i.total, i.prior_settled, public.so_invoice_remaining(i.id)) from public.so_invoice i where i.kind = 'opening' and i.legacy_invoice_id = 'ar2b-task-1'),
    (select format('%s %s', p.amount, p.account_code) from public.so_payment p where p.method = 'opening' and p.customer_id = :'hq'::uuid)), '1 1 79921 110.00 10.00 100.00 20.00 _1150040009_');
select pg_temp.load(:'inp'::jsonb, false)::text as ap2 \gset
select pg_temp.chk('F4 다시 Apply(같은 입력): invoices same 1 · credits same 1 · 행 수 그대로 1 · 1', format('%s %s %s %s', :'ap2'::jsonb#>>'{invoices,same}', :'ap2'::jsonb#>>'{credits,same}',
  (select count(*) from public.so_invoice where kind = 'opening' and legacy_invoice_id like 'ar2b-%'), (select count(*) from public.so_payment where method = 'opening' and customer_id = :'hq'::uuid)), '1 1 1 1');
select pg_temp.load(jsonb_set(jsonb_set(jsonb_set(:'inp'::jsonb, '{invoices,0,total}', '120.00'::jsonb), '{invoices,0,total_before_tax}', '110.00'::jsonb), '{credits,0,amount}', '25.00'::jsonb), false)::text as ap3 \gset
select pg_temp.chk('F5 바뀐 입력(합계 120.00 · 돈 25.00) Apply: invoices updated 1 · credits updated 1 · 실물 120.00 · 25.00 (action update 길 — WHERE 뒤의 거부 사슬 그대로)', format('%s %s %s %s', :'ap3'::jsonb#>>'{invoices,updated}', :'ap3'::jsonb#>>'{credits,updated}',
  (select i.total from public.so_invoice i where i.kind = 'opening' and i.legacy_invoice_id = 'ar2b-task-1'), (select p.amount from public.so_payment p where p.method = 'opening' and p.customer_id = :'hq'::uuid)), '1 1 120.00 25.00');
select pg_temp.chk('F6 빈 입력 {} (service_role · GAS 의 curl 재현과 같은 입력): in 0 · rows_in 0 · 쓰기 0', (pg_temp.load('{}'::jsonb, false)#>>'{invoices,in}') || ' ' || (pg_temp.load('{}'::jsonb, false)#>>'{credits,rows_in}'), '0 0');
do $$
declare v text;
begin
  execute 'set local role authenticated';
  begin
    perform public.so_opening_load('{}'::jsonb, true);
    v := 'no error';
  exception when others then v := 'ERR ' || sqlstate;
  end;
  execute 'reset role';
  perform set_config('app.out', v, true);
end $$;
select pg_temp.chk('F7 authenticated(직원)는 여전히 못 부른다 → ERR 42501', current_setting('app.out', true), 'ERR 42501');

-- ── C) hcr-1 so_credit_issue: 같은 정적 셈 0 (발행 실물 p_commit true 는 supabase/tests/hcr_1_check.sql I9 · I10 — 29) ──
select pg_temp.chk('C1 so_credit_issue · hist_credit_source · so_credit_detail · doc_data_credit 의 WHERE 없는 update · delete 0 · 실행권(authenticated t · service_role t · anon f) 그대로 — service_role 도 부를 수 있다(REST 로 발행 실물 시험이 가능하다는 뜻 · 쓰기라 Caleb 결정)',
  (select pg_temp.nowhere(prosrc)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_credit_issue') || ' ' || has_function_privilege('authenticated', 'public.so_credit_issue(jsonb, boolean)', 'execute')::text || ' ' || has_function_privilege('service_role', 'public.so_credit_issue(jsonb, boolean)', 'execute')::text || ' ' || has_function_privilege('anon', 'public.so_credit_issue(jsonb, boolean)', 'execute')::text,
  '0 true true false');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.so_invoice) = :n_inv as so_invoice_same, (select count(*) from public.so_payment) = :n_pay as so_payment_same, (select count(*) from public.so_payment_alloc) = :n_alloc as alloc_same,
       (select count(*) from public.customer) = :n_cust as customer_same, (select count(*) from public.ims_staff) = :n_staff as staff_same, (select count(*) from public.so_credit) = :n_cred as credit_same,
       (select last_value = :inv_seq_last and is_called = :'inv_seq_called'::boolean from public.so_invoice_number_seq) as inv_seq_same,
       (select last_value = :cr_seq_last and is_called = :'cr_seq_called'::boolean from public.so_credit_number_seq) as cr_seq_same,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load') = :n_fn0 as fn_count_same_as_before,
       (select md5(prosrc) = :'pre_md5' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_opening_load') as so_opening_load_prosrc_same_as_before;
