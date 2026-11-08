-- supabase/tests/qbo_sync_2e3_2_1_check.sql — qbo-sync-2e-3-2-1 검증: 표 · 트리거(INSERT deferred · status 가지 · 결제 길 무변) · 도우미(account 몫 · ⓖ-1 가드 · 차단 글) · 몸 넷(Purchase 꼴 · 0 원 Payment 줄 여럿 · void 둘) · sync 상태표(①~⑥ · ⓖ-2 · ⓖ-4 · ⓖ-5) · claim · done(두 장 · 대조 · void 차례 · reconcile) · 세금 짝 없음 → failed → qbo_link_set 되살림(ⓖ-8) · ⓖ-1 가드(가짜 + 실물 7 손님 0) · retry 넷 · list · doc · preview · 백필(실물 2) · 같은 입력 → 같은 출력(옛 몸 셋) · 권한 · nowhere (2026-11-08)
-- [테스트 · Asung-IMS = IMS 메인] 시험 적용 장치 틀 — 기준(begin 앞) → begin(lock_timeout 3s) → 도우미(DO 하나) → 가짜 바탕(DO 하나 · 잠금 밖) → (-v mig 면 \i + G0 · 표 CHECK 는 파일 끝이라 잠금은 거기부터) → 검증 DO 블록 여덟(왕복 최소 · 1055) → rollback · ⚠️ 트리거는 DEFERRED — `set constraints all immediate` 로 당겨 쏜다(그 뒤 환불 + 붙임을 한 덩이로 넣을 때는 다시 deferred)
--   Claude Code(시험): MIG=supabase/migrations/20261108075221_qbo_sync_2e3_2_1_refund_jobs.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_sync_2e3_2_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 차이는 G0 · B1(시험 = 파일 안 백필 · 확인 = 이미 적용된 수) · 기대 OK 수는 EXPECT_OK(시험 · 확인)
--   쓰기: 가짜 직원 1(qbo · sales · manager) · 손님 4(A 짝 · B 짝 없음 · H 짝 · S 매장 짝 · 상위 H) · 크레딧 8 · 환불 11 · 이월 결제 2 · 인보이스 2 · 붙임 2 · 전부 rollback · QBO 호출 0 · 시퀀스 무접촉(크레딧 · 인보이스 번호는 직접 · CR-9997x · 9972xxx)
--   실물: B1 백필이 컷 뒤 환불 2 건(CR-01011 · CR-01012 몫)에 refund queued + refund_apply blocked 를 만들고(새 행) 컷 전 8 건은 일감 0 · 실물 행은 읽기만 → rollback
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 35
\set MIGFLAG true
\else
\set EXPECT_OK 35
\set MIGFLAG false
\endif
\pset pager off
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%' or p.proname like 'shop\_%');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0,
       (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.so_credit) as n_cr0, (select count(*) from public.so_credit_alloc) as n_calloc0, (select count(*) from public.so_payment_alloc) as n_palloc0, (select count(*) from public.so_payment) as n_pay0,
       (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0, (select count(*) from public.qbo_link) as n_link0, (select count(*) from public.qbo_entity) as n_ent0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as tor_id, (select id::text from public.ref_currency where code = 'CAD') as cad_id, (select id::text from public.ref_currency where code = 'USD') as usd_id,
       (select id::text from public.ref_account where code = '_1150040028_') as acct_et, (select id::text from public.ref_account where code = '_1150040009_') as acct_cc,
       (select r.id::text from public.ref_tax_rule r where r.direction = 'purchase' and r.name ilike 'Out of Scope%' order by r.is_active desc, r.name limit 1) as rule_oosp,
       (select l.qbo_id from public.qbo_link l join public.ref_tax_rule r on r.id::text = l.ims_id where l.ims_kind = 'tax_rule' and r.direction = 'purchase' and r.name ilike 'Out of Scope%' order by r.is_active desc, r.name limit 1) as tax_oosp,
       (select l.qbo_id from public.qbo_link l join public.ref_account a on a.id::text = l.ims_id where l.ims_kind = 'account' and a.code = '_1150040028_') as acct_et_qbo,
       (select l.qbo_id from public.qbo_link l join public.ref_account a on a.id::text = l.ims_id where l.ims_kind = 'account' and a.code = '_61_') as ar_qbo,
       (select count(*) from public.so_payment p where p.kind = 'refund' and p.status = 'active' and p.paid_on >= date '2026-10-30'
          and not exists (select 1 from public.qbo_job j where j.ims_kind = 'refund' and j.ims_id = p.id::text) and not exists (select 1 from public.qbo_txn t where t.ims_kind in ('refund', 'refund_apply') and t.ims_id = p.id::text)) as n_scope,
       (select count(*) from public.so_payment p where p.kind = 'refund' and p.status = 'active' and p.paid_on < date '2026-10-30') as n_precut,
       (select count(*) from public.qbo_job j where j.kind in ('payment', 'payment_void')) as n_payjob0, (select count(*) from public.qbo_job j where j.kind in ('credit_apply', 'credit_apply_void')) as n_cajob0,
       (select count(*) from public.qbo_job where ims_kind = 'opening_alloc') as n_oajob0, (select count(*) from public.qbo_job where ims_kind = 'refund') as n_rjob0,
       public.ims_today()::text as today \gset
-- 실물 셋(읽기만): 컷 뒤 환불 하나(가장 오래된) · 「같은 입력 → 같은 출력」 의 옛 몸 셋(결제 · 크레딧 붙임 · 이월 붙임 — sent 된 실물 하나씩 · md5)
select p.id::text as real_ref, p.paid_on::text as real_ref_on, trim_scale(p.amount)::text as real_ref_amt, (select l.qbo_id from public.qbo_link l where l.ims_kind = 'customer' and l.ims_id = p.customer_id::text) as real_cust_ref,
       (select c.credit_number from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id where a.refund_payment_id = p.id and a.voided_at is null order by c.credit_number limit 1) as real_cr,
       (select t.qbo_id from public.so_credit_alloc a join public.qbo_txn t on t.ims_kind = 'credit' and t.ims_id = a.credit_id::text where a.refund_payment_id = p.id and a.voided_at is null order by t.doc_number limit 1) as real_cr_qbo
  from public.so_payment p where p.kind = 'refund' and p.status = 'active' and p.paid_on >= date '2026-10-30' order by p.paid_on, p.created_at, p.id limit 1 \gset
select coalesce((select md5(public.qbo_payment_body(j.ims_id::uuid)::text) from public.qbo_job j where j.kind = 'payment' and j.state = 'sent' order by j.sent_at desc limit 1), 'none') as m_pay,
       coalesce((select md5(public.qbo_credit_apply_body(j.ims_id::uuid)::text) from public.qbo_job j where j.kind = 'credit_apply' and j.state = 'sent' order by j.sent_at desc limit 1), 'none') as m_ca,
       coalesce((select md5(public.qbo_opening_credit_body(j.ims_id::uuid)::text) from public.qbo_job j where j.kind = 'opening_credit' and j.state = 'sent' order by j.sent_at desc limit 1), 'none') as m_oc,
       (select j.ims_id from public.qbo_job j where j.kind = 'payment' and j.state = 'sent' order by j.sent_at desc limit 1) as id_pay,
       (select j.ims_id from public.qbo_job j where j.kind = 'credit_apply' and j.state = 'sent' order by j.sent_at desc limit 1) as id_ca,
       (select j.ims_id from public.qbo_job j where j.kind = 'opening_credit' and j.state = 'sent' order by j.sent_at desc limit 1) as id_oc \gset
\echo '── 기준: 함수' :n_fn '· job' :n_job0 '· refund jobs' :n_rjob0 '· opening_alloc jobs' :n_oajob0 '· txn' :n_txn0 '· 백필 범위' :n_scope '· 컷 전' :n_precut '· 실물 환불' :real_ref :real_ref_on :real_ref_amt :real_cr '(CM' :real_cr_qbo ') · tax Out of Scope (Purchase)' :tax_oosp '· E-Transfer' :acct_et_qbo '· A/R' :ar_qbo '· realm' :realm
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
-- ── 도우미(DO 하나 · 왕복 1) ──
do $do$
begin
  create temp table t_res (n serial, name text, ok boolean, got text, want text);
  create temp table t_kv (k text primary key, v text);
  execute $f$ create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$ insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want); $$ $f$;
  execute $f$ create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_kv(k, v) values (p_k, p_v) on conflict (k) do update set v = excluded.v; $$ $f$;
  execute $f$ create function pg_temp.get(p_k text) returns text language sql stable as $$ select v from t_kv where k = p_k $$ $f$;
  execute $f$ create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
    declare v text; v_old text := current_setting('request.jwt.claims', true);
    begin
      perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
      execute format('set local role %I', p_role);
      begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
      execute 'reset role';
      perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
      return coalesce(v, '(null)');
    end $$ $f$;
  execute $f$ create function pg_temp.bk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"e3f20000-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$ $f$;
  execute $f$ create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$ $f$;
  execute $f$ create function pg_temp.try(p_sql text) returns text language plpgsql as $$
    declare v text;
    begin
      begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
      return coalesce(v, '(null)');
    end $$ $f$;
  execute $f$ create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
    declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
    begin
      v := regexp_replace(p_src, '--[^\n]*', '', 'g');
      foreach v_chunk in array string_to_array(v, ';') loop
        v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
        if v_verb is null then continue; end if;
        v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
        loop v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g'); exit when v_chunk = v_prev; end loop;
        if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
        if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
      end loop;
      return v_n;
    end $$ $f$;
  execute $f$ create function pg_temp.job(p_kind text, p_ims text) returns uuid language sql as $$ select j.id from public.qbo_job j where j.kind = p_kind and j.ims_id = p_ims and j.state not in ('sent', 'skipped') order by j.created_at desc limit 1 $$ $f$;
  execute $f$ create function pg_temp.anyjob(p_kind text, p_ims text) returns uuid language sql as $$ select j.id from public.qbo_job j where j.kind = p_kind and j.ims_id = p_ims order by j.created_at desc limit 1 $$ $f$;
  execute $f$ create function pg_temp.jobs(p_ims text) returns text language sql as $$ select coalesce(string_agg(j.kind || ':' || j.state, ',' order by j.created_at, coalesce(array_position(array['refund', 'refund_apply', 'refund_apply_void', 'refund_void', 'opening_credit', 'opening_apply', 'opening_apply_void', 'opening_credit_void', 'credit', 'credit_void', 'customer'], j.kind), 99), j.kind), '(none)') from public.qbo_job j where j.ims_id = p_ims $$ $f$;
  execute $f$ create function pg_temp.err(p_ims text, p_kind text) returns text language sql as $$ select j.last_error from public.qbo_job j where j.kind = p_kind and j.ims_id = p_ims order by j.created_at desc limit 1 $$ $f$;
  execute $f$ create function pg_temp.claim(p_kinds text, p_job uuid) returns jsonb language sql as $$ select pg_temp.svc(format($q$ select public.qbo_job_claim(50, array[%s], array[%L]::uuid[])::text $q$, p_kinds, p_job))::jsonb $$ $f$;
  execute $f$ create function pg_temp.done(p_job uuid, p_id text, p_name text, p_amt numeric, p_tax numeric, p_unapplied numeric) returns jsonb language sql as $$
    select pg_temp.svc(format('select public.qbo_job_done(%L, %L, %L, ''0'', ''tid'', null, null, %s, %s, %s)::text', p_job, p_id, p_name, coalesce(p_amt::text, 'null'), coalesce(p_tax::text, 'null'), coalesce(p_unapplied::text, 'null')))::jsonb $$ $f$;
  execute $f$ create function pg_temp.void(p_pay text) returns text language sql as $$ select pg_temp.bk(format($q$ select (public.so_payment_void(%L, 'test void'))->>'status' $q$, p_pay)) $$ $f$;
  execute $f$ create function pg_temp.mk_cr(p_id uuid, p_num text, p_cust uuid, p_store uuid, p_amt numeric) returns void language sql as $$
    insert into public.so_credit (id, credit_number, status, customer_id, store_customer_id, currency_id, currency_code, invoice_id, ref_invoice_number, reason, warehouse_id, warehouse_name, issued_on, issued_by, lines_amount, fee_amount, tax_amount, total, order_discount_amount, freight_discount_amount, surcharge_amount)
    values (p_id, p_num, 'issued', p_cust, p_store, pg_temp.get('cad_id')::uuid, 'CAD', null, 'TEST-' || p_num, 'customer_return', pg_temp.get('tor_id')::uuid, 'Asung Trading Inc.', pg_temp.get('today')::date, 'e3f20000-0000-4000-8000-00000000000a', p_amt, 0, 0, p_amt, 0, 0, 0) $$ $f$;
  execute $f$ create function pg_temp.mk_ref(p_id uuid, p_cust uuid, p_amt numeric, p_on date, p_ref text, p_cur text, p_created timestamptz) returns void language sql as $$
    insert into public.so_payment (id, kind, amount, paid_on, method, reference, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, status, created_by, created_at)
    values (p_id, 'refund', p_amt, p_on, 'e_transfer', p_ref, p_cust, case p_cur when 'USD' then pg_temp.get('usd_id')::uuid else pg_temp.get('cad_id')::uuid end, p_cur, pg_temp.get('acct_et')::uuid, '_1150040028_', pg_temp.get('tor_id')::uuid, 'Asung Trading Inc.', 'active', 'e3f20000-0000-4000-8000-00000000000a', coalesce(p_created, now())) $$ $f$;
  execute $f$ create function pg_temp.mk_al(p_cr uuid, p_ref uuid, p_amt numeric) returns void language sql as $$
    insert into public.so_credit_alloc (credit_id, invoice_id, refund_payment_id, amount, source, created_by) values (p_cr, null, p_ref, p_amt, 'manual', 'e3f20000-0000-4000-8000-00000000000a') $$ $f$;
  execute $f$ create function pg_temp.mk_inv(p_id uuid, p_num text, p_bill uuid, p_name text) returns void language sql as $$
    insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, store_customer_id, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due)
    values (p_id, p_num, 'sale', 'issued', p_bill, p_name, '1 Any St', 'Toronto', 'ON', 'M1M 1M1', 'CA', pg_temp.get('today')::date, 'e3f20000-0000-4000-8000-00000000000a', p_bill, pg_temp.get('cad_id')::uuid, 'CAD', 10, 10, 0, 10, 10) $$ $f$;
end $do$;
select pg_temp.put('mig', :'MIGFLAG'), pg_temp.put('realm', :'realm'), pg_temp.put('tor_id', :'tor_id'), pg_temp.put('cad_id', :'cad_id'), pg_temp.put('usd_id', :'usd_id'), pg_temp.put('acct_et', :'acct_et'), pg_temp.put('acct_cc', :'acct_cc'), pg_temp.put('today', :'today'),
       pg_temp.put('rule_oosp', :'rule_oosp'), pg_temp.put('tax_oosp', :'tax_oosp'), pg_temp.put('acct_et_qbo', :'acct_et_qbo'), pg_temp.put('ar_qbo', :'ar_qbo'), pg_temp.put('n_scope', :'n_scope'), pg_temp.put('n_precut', :'n_precut'), pg_temp.put('n_payjob0', :'n_payjob0'), pg_temp.put('n_cajob0', :'n_cajob0'), pg_temp.put('n_oajob0', :'n_oajob0'), pg_temp.put('n_rjob0', :'n_rjob0'),
       pg_temp.put('real_ref', :'real_ref'), pg_temp.put('real_ref_on', :'real_ref_on'), pg_temp.put('real_ref_amt', :'real_ref_amt'), pg_temp.put('real_cust_ref', :'real_cust_ref'), pg_temp.put('real_cr', :'real_cr'), pg_temp.put('real_cr_qbo', :'real_cr_qbo'),
       pg_temp.put('m_pay', :'m_pay'), pg_temp.put('m_ca', :'m_ca'), pg_temp.put('m_oc', :'m_oc'), pg_temp.put('id_pay', :'id_pay'), pg_temp.put('id_ca', :'id_ca'), pg_temp.put('id_oc', :'id_oc');   -- ⚠️ psql 변수는 $$ 안에서 안 바뀐다 — t_kv 로 넘긴다
-- ── 가짜 바탕(DO 하나 · 잠금 밖): 직원 · 손님 넷 · 짝 · 거울 · 크레딧 8 · 환불 11 · 이월 결제 2 · 인보이스 2 · 트리거는 끝에 당겨 쏜다 ──
do $do$
declare v_realm text := pg_temp.get('realm');
  cA constant uuid := 'c3f20000-0000-4000-8000-00000000000a'; cB constant uuid := 'c3f20000-0000-4000-8000-00000000000b'; cH constant uuid := 'c3f20000-0000-4000-8000-000000000010'; cS constant uuid := 'c3f20000-0000-4000-8000-000000000011';
begin
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values ('e3f20000-0000-4000-8000-00000000000a', 'e3f20000-0000-4000-8000-000000000001', 'qbo-sync-2e32-bk@asung.invalid', 'QBO 2e32 Bookkeeper', 'manager', '["qbo", "sales"]');
  insert into public.customer (id, name, is_active, source, currency_code) values (cA, 'QBO2E32 Store A', true, 'manual', 'CAD'), (cB, 'QBO2E32 Store B', true, 'manual', 'CAD'), (cH, 'QBO2E32 Head H', true, 'manual', 'CAD');
  insert into public.customer (id, name, is_active, source, currency_code, parent_id, parent_source, default_bill_to_customer_id) values (cS, 'QBO2E32 Store S', true, 'manual', 'CAD', cH, 'ims', cH);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values
    (v_realm, 'customer', cA::text, 'Customer', 'C-2E32-A', 'manual', 'QBO2E32 Store A'), (v_realm, 'customer', cH::text, 'Customer', 'C-2E32-H', 'manual', 'QBO2E32 Head H'), (v_realm, 'customer', cS::text, 'Customer', 'C-2E32-S', 'manual', 'QBO2E32 Store S');
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, parent_id, active, fetched_at) values (v_realm, 'Customer', 'C-2E32-H', 'QBO2E32 Head H', null, true, now()), (v_realm, 'Customer', 'C-2E32-S', 'QBO2E32 Store S', null, true, now());
  -- 크레딧 8: CA1 30 · CA2 20 · CA4 5 · CA5 10 · CA6 5 · CB 5(B) · CS 8(손님 H · 매장 S) = QBO 에 선 것 / CA3 10 · CA7 7 = 일감만(queued)
  perform pg_temp.mk_cr('33f20000-0000-4000-8000-000000000001', 'CR-99971', cA, cA, 30); perform pg_temp.mk_cr('33f20000-0000-4000-8000-000000000002', 'CR-99972', cA, cA, 20); perform pg_temp.mk_cr('33f20000-0000-4000-8000-000000000003', 'CR-99973', cA, cA, 10);
  perform pg_temp.mk_cr('33f20000-0000-4000-8000-000000000004', 'CR-99974', cA, cA, 5);  perform pg_temp.mk_cr('33f20000-0000-4000-8000-000000000005', 'CR-99975', cA, cA, 10); perform pg_temp.mk_cr('33f20000-0000-4000-8000-000000000006', 'CR-99976', cA, cA, 5);
  perform pg_temp.mk_cr('33f20000-0000-4000-8000-000000000007', 'CR-99977', cA, cA, 7);  perform pg_temp.mk_cr('33f20000-0000-4000-8000-00000000000b', 'CR-99978', cB, cB, 5);  perform pg_temp.mk_cr('33f20000-0000-4000-8000-000000000012', 'CR-99979', cH, cS, 8);
  -- 이월 결제 둘(ⓖ-1): OPA A 50 · OPB B 10 · 인보이스 둘(sale · 오늘 · 매장 없음 — 가드가 먼저 선다)
  insert into public.so_payment (id, kind, amount, paid_on, method, reference, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, status, note) values
    ('43f20000-0000-4000-8000-0000000000a0', 'payment', 50, '2026-10-31', 'opening', 'OPEN-2E32-A', cA, pg_temp.get('cad_id')::uuid, 'CAD', pg_temp.get('acct_cc')::uuid, '_1150040009_', pg_temp.get('tor_id')::uuid, 'Asung Trading Inc.', 'active', 'test opening'),
    ('43f20000-0000-4000-8000-0000000000b0', 'payment', 10, '2026-10-31', 'opening', 'OPEN-2E32-B', cB, pg_temp.get('cad_id')::uuid, 'CAD', pg_temp.get('acct_cc')::uuid, '_1150040009_', pg_temp.get('tor_id')::uuid, 'Asung Trading Inc.', 'active', 'test opening');
  perform pg_temp.mk_inv('13f20000-0000-4000-8000-000000000001', '9972001', cA, 'QBO2E32 Store A'); perform pg_temp.mk_inv('13f20000-0000-4000-8000-000000000002', '9972002', cB, 'QBO2E32 Store B');
end $do$;
select clock_timestamp() as t_fixtures \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
select clock_timestamp() as t_mig \gset
-- ── 가짜 환불 11(DO 하나 · ⚠️ 마이그레이션 뒤 — DEFERRED 트리거 사건은 insert 때 쌓이므로 새 트리거 so_payment_refund_qbo 가 선 뒤에 넣어야 쏜다) ──
do $do$
declare cA constant uuid := 'c3f20000-0000-4000-8000-00000000000a'; cB constant uuid := 'c3f20000-0000-4000-8000-00000000000b'; cH constant uuid := 'c3f20000-0000-4000-8000-000000000010';
begin
  -- 환불 11(직접 insert · 창구 없음 · 시퀀스 무접촉): R1 A 30(CA1) · R2 A 25(CA2 20 + CA4 5) · R3 A 12(CA3 10 → account 2 · ⓖ-2) · R4 A 10 컷 전 · 11-05 created(ⓖ-5) · R5 A 10 컷 전 · 오늘 created(CA5 10 · ⓖ-4) · R6 A 7(CA7 · 크레딧 일감 queued) · R7 B 5(CB · 손님 짝 없음) · R8 H 8(CS · 매장 S) · R9 A 3 USD · R10 A 50 account 만(ⓖ-2 · ⓖ-1) · R11 A 5(CA6 · sending 중 void)
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000001', cA, 30, '2026-11-05', 'REF-2E32-1', 'CAD', null); perform pg_temp.mk_al('33f20000-0000-4000-8000-000000000001', '43f20000-0000-4000-8000-000000000001', 30);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000002', cA, 25, '2026-11-05', 'REF-2E32-2-WITH-A-VERY-LONG-REFERENCE', 'CAD', null); perform pg_temp.mk_al('33f20000-0000-4000-8000-000000000002', '43f20000-0000-4000-8000-000000000002', 20); perform pg_temp.mk_al('33f20000-0000-4000-8000-000000000004', '43f20000-0000-4000-8000-000000000002', 5);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000003', cA, 12, '2026-11-05', 'REF-2E32-3', 'CAD', null); perform pg_temp.mk_al('33f20000-0000-4000-8000-000000000003', '43f20000-0000-4000-8000-000000000003', 10);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000004', cA, 10, '2026-10-20', 'REF-2E32-4', 'CAD', '2026-11-05 12:00-05');
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000005', cA, 10, '2026-10-20', 'REF-2E32-5', 'CAD', null); perform pg_temp.mk_al('33f20000-0000-4000-8000-000000000005', '43f20000-0000-4000-8000-000000000005', 10);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000006', cA, 7, '2026-11-05', 'REF-2E32-6', 'CAD', null); perform pg_temp.mk_al('33f20000-0000-4000-8000-000000000007', '43f20000-0000-4000-8000-000000000006', 7);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000007', cB, 5, '2026-11-05', 'REF-2E32-7', 'CAD', null); perform pg_temp.mk_al('33f20000-0000-4000-8000-00000000000b', '43f20000-0000-4000-8000-000000000007', 5);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000008', cH, 8, '2026-11-05', 'REF-2E32-8', 'CAD', null); perform pg_temp.mk_al('33f20000-0000-4000-8000-000000000012', '43f20000-0000-4000-8000-000000000008', 8);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000009', cA, 3, '2026-11-05', 'REF-2E32-9', 'USD', null);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000010', cA, 50, '2026-11-05', 'REF-2E32-10', 'CAD', null);
  perform pg_temp.mk_ref('43f20000-0000-4000-8000-000000000011', cA, 5, '2026-11-05', 'REF-2E32-11', 'CAD', null); perform pg_temp.mk_al('33f20000-0000-4000-8000-000000000006', '43f20000-0000-4000-8000-000000000011', 5);
end $do$;
set constraints all immediate;   -- 가짜 바탕의 DEFERRED 트리거(크레딧 발행 · 인보이스 발행 · 환불 INSERT · 크레딧 붙임)를 지금 쏜다
-- ── A) 착지 · 트리거 가지(환불 11 의 일감) · 백필(실물) · 옛 몸 같은 출력 · ⓖ-1 실물 ──
do $$
declare v_scope int := pg_temp.get('n_scope')::int; v_realm text := pg_temp.get('realm'); r1 text := '43f20000-0000-4000-8000-000000000001';
begin
  update public.qbo_job set state = 'sent', qbo_id = 'CM-2E32-' || right(ims_id, 2), qbo_name = 'CR-9997' || right(ims_id, 1), sent_at = now() where kind = 'credit' and ims_id in ('33f20000-0000-4000-8000-000000000001', '33f20000-0000-4000-8000-000000000002', '33f20000-0000-4000-8000-000000000004', '33f20000-0000-4000-8000-000000000005', '33f20000-0000-4000-8000-000000000006', '33f20000-0000-4000-8000-00000000000b', '33f20000-0000-4000-8000-000000000012');
  insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at)
    select v_realm, 'credit', c.id::text, 'CreditMemo', 'CM-2E32-' || right(c.id::text, 2), c.credit_number, '0', c.total, 0, now() from public.so_credit c where c.id in ('33f20000-0000-4000-8000-000000000001', '33f20000-0000-4000-8000-000000000002', '33f20000-0000-4000-8000-000000000004', '33f20000-0000-4000-8000-000000000005', '33f20000-0000-4000-8000-000000000006', '33f20000-0000-4000-8000-00000000000b', '33f20000-0000-4000-8000-000000000012');
  perform pg_temp.chk('A1 CHECK — qbo_job kind 18 · ims_kind refund · pair 넷 · qbo_txn kind 둘(refund · refund_apply) · type Purchase · pair refund → Purchase · ELSE Payment',
    (select string_agg((pg_get_constraintdef(oid) ~* 'refund_void' and pg_get_constraintdef(oid) ~* 'refund_apply_void')::text, ',' order by conname) from pg_constraint where conname in ('qbo_job_kind_ck', 'qbo_job_pair_ck'))
    || ' | ' || (select (pg_get_constraintdef(oid) ~ '''refund''')::text from pg_constraint where conname = 'qbo_job_ims_kind_ck')
    || ' | ' || (select (pg_get_constraintdef(oid) ~ '''refund''' and pg_get_constraintdef(oid) ~ 'refund_apply')::text from pg_constraint where conname = 'qbo_txn_kind_ck')
    || ' | ' || (select (pg_get_constraintdef(oid) ~ 'Purchase')::text from pg_constraint where conname = 'qbo_txn_type_ck')
    || ' | ' || (select (pg_get_constraintdef(oid) ~ 'WHEN ''refund''::text THEN ''Purchase''' and pg_get_constraintdef(oid) ~ 'ELSE ''Payment''')::text from pg_constraint where conname = 'qbo_txn_pair_ck'),
    'true,true | true | true | true | true');
  perform pg_temp.chk('A2 트리거 — so_payment 셋(refund_qbo deferred · qbo_status · touch) · status 함수에 refund 가지 · so_credit_alloc_qbo 그대로 · so_payment_alloc 둘 그대로',
    (select string_agg(t.tgname || ':' || case when t.tgdeferrable and t.tginitdeferred then 'deferred' else 'immediate' end, ',' order by t.tgname) from pg_trigger t where t.tgrelid = 'public.so_payment'::regclass and not t.tgisinternal)
    || ' | ' || (select (prosrc like '%qbo_refund_sync(new.id%' and prosrc like '%qbo_payment_sync(new.id%')::text from pg_proc where proname = 'qbo_job_on_payment_status' and pronamespace = 'public'::regnamespace)
    || ' | ' || (select count(*)::text from pg_trigger where tgname = 'so_credit_alloc_qbo' and tgdeferrable and tginitdeferred) || ' ' || (select count(*)::text from pg_trigger t where t.tgrelid = 'public.so_payment_alloc'::regclass and not t.tgisinternal),
    'so_payment_qbo_status:immediate,so_payment_refund_qbo:deferred,so_payment_touch:immediate | true | 1 2');
  perform pg_temp.chk('A3 nowhere — 새 함수 열넷 · 재발행 열의 깊이 0 WHERE 없는 update · delete = 0',
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_refund_from_account', 'qbo_opening_refunded_block', 'qbo_refund_label', 'qbo_refund_block', 'qbo_refund_purchase_head', 'qbo_refund_credit_lines', 'qbo_refund_body', 'qbo_refund_apply_body', 'qbo_refund_apply_void_body', 'qbo_refund_void_body', 'qbo_refund_sync', 'qbo_job_on_refund_insert', 'qbo_refund_backfill', 'qbo_refund_requeue',
                                                                                                                                             'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc', 'qbo_link_set', 'qbo_job_on_payment_status', 'qbo_opening_alloc_sync', 'qbo_opening_credit_body')),
    'qbo_job_claim=0 qbo_job_doc=0 qbo_job_done=0 qbo_job_list=0 qbo_job_on_payment_status=0 qbo_job_on_refund_insert=0 qbo_job_preview=0 qbo_job_retry=0 qbo_link_set=0 qbo_opening_alloc_sync=0 qbo_opening_credit_body=0 qbo_opening_refunded_block=0 qbo_refund_apply_body=0 qbo_refund_apply_void_body=0 qbo_refund_backfill=0 qbo_refund_block=0 qbo_refund_body=0 qbo_refund_credit_lines=0 qbo_refund_from_account=0 qbo_refund_label=0 qbo_refund_purchase_head=0 qbo_refund_requeue=0 qbo_refund_sync=0 qbo_refund_void_body=0');
  perform pg_temp.chk('A4 ACL — 새 함수 열넷 grant 0 · 재발행은 그대로(claim · done service_role · list · preview · retry · link_set authenticated · 그 밖 grant 0)',
    (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_refund_from_account', 'qbo_opening_refunded_block', 'qbo_refund_label', 'qbo_refund_block', 'qbo_refund_purchase_head', 'qbo_refund_credit_lines', 'qbo_refund_body', 'qbo_refund_apply_body', 'qbo_refund_apply_void_body', 'qbo_refund_void_body', 'qbo_refund_sync', 'qbo_job_on_refund_insert', 'qbo_refund_backfill', 'qbo_refund_requeue',
                                                                                                                                              'qbo_job_claim', 'qbo_job_done', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc', 'qbo_link_set', 'qbo_job_on_payment_status', 'qbo_opening_alloc_sync', 'qbo_opening_credit_body')),
    'qbo_job_claim={postgres=X/postgres,service_role=X/postgres} qbo_job_doc={postgres=X/postgres} qbo_job_done={postgres=X/postgres,service_role=X/postgres} qbo_job_list={postgres=X/postgres,authenticated=X/postgres} qbo_job_on_payment_status={postgres=X/postgres} qbo_job_on_refund_insert={postgres=X/postgres} qbo_job_preview={postgres=X/postgres,authenticated=X/postgres} qbo_job_retry={postgres=X/postgres,authenticated=X/postgres} qbo_link_set={postgres=X/postgres,authenticated=X/postgres} qbo_opening_alloc_sync={postgres=X/postgres} qbo_opening_credit_body={postgres=X/postgres} qbo_opening_refunded_block={postgres=X/postgres} qbo_refund_apply_body={postgres=X/postgres} qbo_refund_apply_void_body={postgres=X/postgres} qbo_refund_backfill={postgres=X/postgres} qbo_refund_block={postgres=X/postgres} qbo_refund_body={postgres=X/postgres} qbo_refund_credit_lines={postgres=X/postgres} qbo_refund_from_account={postgres=X/postgres} qbo_refund_label={postgres=X/postgres} qbo_refund_purchase_head={postgres=X/postgres} qbo_refund_requeue={postgres=X/postgres} qbo_refund_sync={postgres=X/postgres} qbo_refund_void_body={postgres=X/postgres}');
  perform pg_temp.chk('A5 무변 — 결제 넷(2e-1b) · credit_alloc_sync(2e-2-1) · credit_apply_body · opening_apply_body · job_on_payment_alloc(2e-3-1) md5', (select string_agg(left(md5(p.prosrc), 8), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_payment_body', 'qbo_payment_fingerprint', 'qbo_payment_sync', 'qbo_payment_void_body', 'qbo_credit_alloc_sync', 'qbo_credit_apply_body', 'qbo_opening_apply_body', 'qbo_job_on_payment_alloc')), '44419d3b 50dcad57 5466ba49 71b0e76e e1aea518 d6da0342 9efb5d9f 4ddb45cd');
  perform pg_temp.chk('A6 같은 입력 → 같은 출력 — 옛 몸 셋(결제 · 크레딧 붙임 · 이월 붙임 · sent 실물 하나씩)의 출력 md5 가 begin 앞과 같다(실물 없으면 none=none)',
    (pg_temp.get('m_pay') = coalesce((select md5(public.qbo_payment_body(pg_temp.get('id_pay')::uuid)::text) where pg_temp.get('id_pay') is not null), 'none'))::text || ' ' || (pg_temp.get('m_ca') = coalesce((select md5(public.qbo_credit_apply_body(pg_temp.get('id_ca')::uuid)::text) where pg_temp.get('id_ca') is not null), 'none'))::text || ' ' || (pg_temp.get('m_oc') = coalesce((select md5(public.qbo_opening_credit_body(pg_temp.get('id_oc')::uuid)::text) where pg_temp.get('id_oc') is not null), 'none'))::text,
    'true true true');
  perform pg_temp.chk('A7 ⓖ-1 실물 — 이월 돈 + 환불이 있는 손님(7)의 Σremaining − Σ환불 account 몫 < 0 인 손님 0 · 그 손님들의 열린 opening_alloc 일감 0 · 실물 opening_alloc 일감 수 무변',
    (select count(*)::text from (select p.customer_id, p.currency_id from public.so_payment p where p.kind = 'payment' and p.method = 'opening' and p.status = 'active' and p.id::text not like '43f2%' group by 1, 2) o
      where exists (select 1 from public.so_payment f where f.kind = 'refund' and f.status = 'active' and f.customer_id = o.customer_id and f.id::text not like '43f2%')
        and (select coalesce(sum(public.so_payment_remaining(x.id)), 0) from public.so_payment x where x.customer_id = o.customer_id and x.currency_id = o.currency_id and x.kind = 'payment' and x.method = 'opening' and x.status = 'active')
          - (select coalesce(sum(public.qbo_refund_from_account(f.id)), 0) from public.so_payment f where f.customer_id = o.customer_id and f.currency_id = o.currency_id and f.kind = 'refund' and f.status = 'active') < 0)
    || ' ' || (select count(*)::text from (select p.customer_id from public.so_payment p where p.kind = 'payment' and p.method = 'opening' and p.status = 'active' and p.id::text not like '43f2%' group by 1) o
                where exists (select 1 from public.so_payment f where f.kind = 'refund' and f.status = 'active' and f.customer_id = o.customer_id and f.id::text not like '43f2%'))
    || ' | ' || (select count(*)::text from public.qbo_job j join public.so_payment_alloc a on a.id::text = j.ims_id join public.so_payment p on p.id = a.payment_id where j.ims_kind = 'opening_alloc' and j.state not in ('sent', 'skipped') and p.id::text not like '43f2%'
                  and exists (select 1 from public.so_payment f where f.kind = 'refund' and f.status = 'active' and f.customer_id = p.customer_id))
    || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'opening_alloc' and j.ims_id not in (select a.id::text from public.so_payment_alloc a where a.payment_id::text like '43f2%')),
    '0 7 | 0 | ' || pg_temp.get('n_oajob0'));
  if pg_temp.get('mig') = 'true' then
    perform pg_temp.chk('B1 백필(실물 · 파일 안) — refund queued = 범위(2) · refund_apply blocked = 범위 · 자기 refund 뒤 · 컷 전 8 건 일감 0 · 가짜 0 · 실물 환불 ' || pg_temp.get('real_ref') || ' 의 일감 둘',
      (select count(*) filter (where j.kind = 'refund' and j.state = 'queued')::text || ' ' || count(*) filter (where j.kind = 'refund_apply' and j.state = 'blocked')::text || ' ' || count(*) filter (where j.kind = 'refund_apply' and exists (select 1 from public.qbo_job c where c.id = j.blocked_by and c.kind = 'refund' and c.ims_id = j.ims_id))::text
         from public.qbo_job j where j.ims_kind = 'refund' and j.ims_id not like '43f2%')
      || ' | ' || (select count(*)::text from public.qbo_job j join public.so_payment p on p.id::text = j.ims_id where j.ims_kind = 'refund' and p.paid_on < date '2026-10-30' and p.id::text not like '43f2%') || ' ' || pg_temp.get('n_precut')
      || ' | ' || pg_temp.jobs(pg_temp.get('real_ref')),
      v_scope::text || ' ' || v_scope::text || ' ' || v_scope::text || ' | 0 ' || pg_temp.get('n_precut') || ' | refund:queued,refund_apply:blocked');
  else
    perform pg_temp.chk('B1 (적용 뒤) 실물 환불 ' || pg_temp.get('real_ref') || ' 의 refund 일감 둘(refund · refund_apply) · 컷 전 8 건 일감 0', (select count(*)::text from public.qbo_job j where j.ims_kind = 'refund' and j.ims_id = pg_temp.get('real_ref') and j.kind in ('refund', 'refund_apply')) || ' | ' || (select count(*)::text from public.qbo_job j join public.so_payment p on p.id::text = j.ims_id where j.ims_kind = 'refund' and p.paid_on < date '2026-10-30' and p.id::text not like '43f2%'), '2 | 0');
  end if;
  perform pg_temp.chk('B2 기존 결제 · 크레딧 붙임 일감 수 무변(백필은 새 kind 만)', (select count(*) filter (where j.kind in ('payment', 'payment_void'))::text || ' ' || count(*) filter (where j.kind in ('credit_apply', 'credit_apply_void'))::text from public.qbo_job j where j.ims_id not like '%-0000-4000-8000-%'), pg_temp.get('n_payjob0') || ' ' || pg_temp.get('n_cajob0'));
  -- C) 트리거 가지(INSERT deferred · 당겨 쏨) — 환불 11 의 일감 · 글
  perform pg_temp.chk('C1 트리거 — R1 · R2 · R6 · R7 · R8 · R11 refund:queued + refund_apply:blocked(자기 refund 뒤) / R3(account 몫 2) · R9(USD) · R10(account 50) refund:failed + apply blocked / R4(컷 전 · 11-05 created) 일감 0 / R5(컷 전 · 오늘 created) failed / 크레딧 붙임(refund) 에는 credit_apply 일감 0',
    (select string_agg(right(x, 2) || '=' || pg_temp.jobs(x), ' ' order by x) from unnest(array['43f20000-0000-4000-8000-000000000001', '43f20000-0000-4000-8000-000000000002', '43f20000-0000-4000-8000-000000000003', '43f20000-0000-4000-8000-000000000004', '43f20000-0000-4000-8000-000000000005', '43f20000-0000-4000-8000-000000000006', '43f20000-0000-4000-8000-000000000007', '43f20000-0000-4000-8000-000000000008', '43f20000-0000-4000-8000-000000000009', '43f20000-0000-4000-8000-000000000010', '43f20000-0000-4000-8000-000000000011']) x)
    || ' | ' || (select count(*)::text from public.qbo_job j where j.kind = 'refund_apply' and j.ims_id like '43f2%' and j.state = 'blocked' and exists (select 1 from public.qbo_job c where c.id = j.blocked_by and c.kind = 'refund' and c.ims_id = j.ims_id))
    || ' | ' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'credit_alloc' and j.ims_id in (select a.id::text from public.so_credit_alloc a where a.refund_payment_id is not null and a.refund_payment_id::text like '43f2%')),
    '01=refund:queued,refund_apply:blocked 02=refund:queued,refund_apply:blocked 03=refund:failed,refund_apply:blocked 04=(none) 05=refund:failed,refund_apply:blocked 06=refund:queued,refund_apply:blocked 07=refund:queued,refund_apply:blocked 08=refund:queued,refund_apply:blocked 09=refund:failed,refund_apply:blocked 10=refund:failed,refund_apply:blocked 11=refund:queued,refund_apply:blocked | 10 | 0');
  perform pg_temp.chk('C2 failed 글 — R3 ⓖ-2(account 2 · 크레딧 몫 10) · R5 ⓖ-4 · R9 통화 · R10 ⓖ-2 · 도우미 qbo_refund_from_account(R1 0 · R3 2 · R10 50 · 결제 null)',
    pg_temp.err('43f20000-0000-4000-8000-000000000003', 'refund') || ' | ' || pg_temp.err('43f20000-0000-4000-8000-000000000005', 'refund') || ' | ' || pg_temp.err('43f20000-0000-4000-8000-000000000009', 'refund') || ' | ' || pg_temp.err('43f20000-0000-4000-8000-000000000010', 'refund')
    || ' | ' || trim_scale(public.qbo_refund_from_account('43f20000-0000-4000-8000-000000000001'))::text || ' ' || trim_scale(public.qbo_refund_from_account('43f20000-0000-4000-8000-000000000003'))::text || ' ' || trim_scale(public.qbo_refund_from_account('43f20000-0000-4000-8000-000000000010'))::text || ' ' || coalesce(public.qbo_refund_from_account('43f20000-0000-4000-8000-0000000000a0')::text, 'null'),
    'Refund REF-2E32-3 pays CAD 2 from money on account — refunds from money on account are not sent to QuickBooks yet, so this refund waits as a whole (its credit-note part 10 is not sent alone) — nothing was sent | Dated before the cut-over (2026-10-30) — check QuickBooks, then Retry or Skip | Refund REF-2E32-9 is in USD — refunds in a foreign currency are not sent to QuickBooks yet — nothing was sent | Refund REF-2E32-10 pays CAD 50 from money on account — refunds from money on account are not sent to QuickBooks yet, so this refund waits as a whole (its credit-note part 0 is not sent alone) — nothing was sent | 0 2 50 null');
end $$;

-- ── D) 몸 넷 · 세금 짝 없음 → failed → link_set 되살림 · needs · wait · 매장 ≠ 손님 ──
do $$
declare r1 text := '43f20000-0000-4000-8000-000000000001'; r2 text := '43f20000-0000-4000-8000-000000000002'; r3 text := '43f20000-0000-4000-8000-000000000003'; r5 text := '43f20000-0000-4000-8000-000000000005'; r6 text := '43f20000-0000-4000-8000-000000000006'; r7 text := '43f20000-0000-4000-8000-000000000007'; r8 text := '43f20000-0000-4000-8000-000000000008';
        b jsonb; b2 jsonb; v jsonb; v_t text; v_realm text := pg_temp.get('realm'); v_ar text := pg_temp.get('ar_qbo'); v_et text := pg_temp.get('acct_et_qbo'); v_tax text := pg_temp.get('tax_oosp');
begin
  b := public.qbo_refund_body(r1::uuid);
  perform pg_temp.chk('D1 R1 refund 몸(sandbox 2-a) — PaymentType Cash · AccountRef E-Transfer 짝 · EntityRef C-2E32-A Customer · TxnDate 2026-11-05 · CAD · NotApplicable · DocNumber REF-2E32-1 · PrivateNote · 줄 하나(Amount 30 · A/R 짝 · CustomerRef · TaxCodeRef Out of Scope (Purchase) 짝 · Description) · needs 0 · wait null · check_lines CreditMemo CM · lookup · totals · fingerprint null',
    (b->'body'->>'PaymentType') || ' ' || (b->'body'->'AccountRef'->>'value') || ' ' || (b->'body'->'EntityRef'->>'value') || ' ' || (b->'body'->'EntityRef'->>'type') || ' ' || (b->'body'->>'TxnDate') || ' ' || (b->'body'->'CurrencyRef'->>'value') || ' ' || (b->'body'->>'GlobalTaxCalculation') || ' ' || (b->'body'->>'DocNumber') || ' ' || (b->'body'->>'PrivateNote' = 'IMS refund ' || r1)::text
    || ' | ' || jsonb_array_length(b->'body'->'Line')::text || ' ' || (b->'body'->'Line'->0->>'Amount') || ' ' || (b->'body'->'Line'->0->>'DetailType') || ' ' || (b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value') || ' ' || (b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'CustomerRef'->>'value') || ' ' || (b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'TaxCodeRef'->>'value') || ' ' || (b->'body'->'Line'->0->>'Description')
    || ' | ' || jsonb_array_length(b->'needs')::text || ' ' || coalesce(b->>'wait_job', 'null') || ' ' || (b->'check_lines'->0->>'txn_type') || ' ' || (b->'check_lines'->0->>'credit_number') || ' ' || (b->'check_lines'->0->>'qbo_creditmemo_id') || ' ' || (b->'lookup'->>'total_amt') || ' ' || (b->'lookup'->>'customer_ref') || ' ' || (b->'totals'->>'credit_covered') || ' ' || (b->'totals'->>'from_account') || ' ' || (b->'fingerprint')::text || ' ' || (b->>'name') || ' ' || (b->>'doc_number'),
    'Cash ' || v_et || ' C-2E32-A Customer 2026-11-05 CAD NotApplicable REF-2E32-1 true | 1 30 AccountBasedExpenseLineDetail ' || v_ar || ' C-2E32-A ' || v_tax || ' Refund of credit note CR-99971 | 0 null CreditMemo CR-99971 CM-2E32-01 30 C-2E32-A 30 0 null REF-2E32-1 REF-2E32-1');
  b := public.qbo_refund_body(r2::uuid);
  perform pg_temp.chk('D2 R2 refund 몸(크레딧 둘) — 줄 하나 Amount 25 · Description 「credit notes CR-99972, CR-99974」 · check_lines 둘 · DocNumber 21 자로 잘림 + 경고 · totals credit_numbers',
    (b->'body'->'Line'->0->>'Amount') || ' ' || (b->'body'->'Line'->0->>'Description') || ' | ' || jsonb_array_length(b->'check_lines')::text || ' ' || (b->'check_lines'->1->>'credit_number') || ' | ' || (b->'body'->>'DocNumber') || ' ' || (b->'warnings'->>0) || ' | ' || (b->'totals'->>'credit_numbers'),
    '25 Refund of credit notes CR-99972, CR-99974 | 2 CR-99974 | REF-2E32-2-WITH-A-VER reference "REF-2E32-2-WITH-A-VERY-LONG-REFERENCE" cut to 21 characters for QuickBooks | CR-99972, CR-99974');
  b := public.qbo_refund_apply_body(r1::uuid); b2 := public.qbo_refund_body(r6::uuid);
  perform pg_temp.chk('D3 wait — R1 apply 몸(Purchase 아직) wait_job = R1 refund 일감 · 글 · Line 0 / R6 refund 몸(CR-99977 일감 queued · 거래 없음) wait_job = 그 credit 일감 · 글 / void 몸 둘(R1) 은 「never sent」',
    (b->>'wait_job' = pg_temp.job('refund', r1)::text)::text || ' ' || (b->>'wait_reason') || ' ' || (b->>'line_count') || ' | ' || (b2->>'wait_job' = pg_temp.job('credit', '33f20000-0000-4000-8000-000000000007')::text)::text || ' ' || (b2->>'wait_reason') || ' ' || (b2->>'wait_invoice')
    || ' | ' || pg_temp.try(format('select public.qbo_refund_apply_void_body(%L)::text', r1)) || ' | ' || pg_temp.try(format('select public.qbo_refund_void_body(%L)::text', r1)),
    'true waiting for the expense of refund REF-2E32-1 to reach QuickBooks first 0 | true waiting for credit note CR-99977 to reach QuickBooks first CR-99977 | ERR P0001: The zero payment of refund REF-2E32-1 was never sent to QuickBooks — nothing to void | ERR P0001: Refund REF-2E32-1 was never sent to QuickBooks — nothing to void');
  b := public.qbo_refund_body(r7::uuid);
  perform pg_temp.chk('D4 needs · 거부 글 — R7(손님 B 짝 없음) needs 1 customer · EntityRef 없음 · 줄 CustomerRef 없음 / R3 몸 = ⓖ-2 글 · R5 몸은 컷을 안 본다(wait null · Amount 10) / R8 매장 S ≠ 손님 H → 거부 글',
    jsonb_array_length(b->'needs')::text || ' ' || (b->'needs'->0->>'kind') || ' ' || (b->'needs'->0->>'ims_id') || ' ' || (b->'body' ? 'EntityRef')::text || ' ' || (b->'body'->'Line'->0->'AccountBasedExpenseLineDetail' ? 'CustomerRef')::text
    || ' | ' || pg_temp.try(format('select public.qbo_refund_body(%L)::text', r3)) || ' | ' || (select coalesce(x->>'wait_job', 'null') || ' ' || (x->'body'->'Line'->0->>'Amount') from public.qbo_refund_body(r5::uuid) x)
    || ' | ' || pg_temp.try(format('select public.qbo_refund_body(%L)::text', r8)),
    '1 customer c3f20000-0000-4000-8000-00000000000b false false | ERR P0001: Refund REF-2E32-3 pays CAD 2 from money on account — refunds from money on account are not sent to QuickBooks yet, so this refund waits as a whole (its credit-note part 10 is not sent alone) — nothing was sent | null 10 | ERR P0001: Refund REF-2E32-8 belongs to customer QBO2E32 Head H but credit note CR-99979 was issued to store QBO2E32 Store S — in QuickBooks the credit memo is on the store: make the store a sub-customer (bill with parent) of that customer, refresh the customer list under Settings → QuickBooks matching, then retry — nothing was sent');
  update public.qbo_entity e set parent_id = 'C-2E32-H' where e.realm_id = v_realm and e.qbo_type = 'Customer' and e.qbo_id = 'C-2E32-S';   -- 빠져나오는 길: QBO 에서 S 를 H 의 하위 손님으로
  b := public.qbo_refund_body(r8::uuid); b2 := public.qbo_refund_apply_body(r8::uuid);
  perform pg_temp.chk('D5 하위 손님 길 — S 의 parent_id = C-2E32-H 가 되면 R8 refund 몸은 EntityRef C-2E32-H + 경고 · apply 몸도 같은 경고(wait 는 자기 Purchase)',
    (b->'body'->'EntityRef'->>'value') || ' ' || (b->'warnings'->>0) || ' | ' || (b2->'body'->'CustomerRef'->>'value') || ' ' || (b2->'warnings'->>0) || ' ' || (b2->>'wait_reason'),
    'C-2E32-H credit note CR-99979 is on store QBO2E32 Store S, a QuickBooks sub-customer of QBO2E32 Head H | C-2E32-H credit note CR-99979 is on store QBO2E32 Store S, a QuickBooks sub-customer of QBO2E32 Head H waiting for the expense of refund REF-2E32-8 to reach QuickBooks first');
  -- ⓖ-8: 세금 짝을 떼면 몸 거부 → claim 은 failed → qbo_link_set(tax_rule) 이 되살린다(requeued 1 · R5 는 ⓖ-4 failed 라 안 건드린다)
  delete from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = pg_temp.get('rule_oosp');
  v_t := pg_temp.try(format('select public.qbo_refund_body(%L)::text', r1));
  v := pg_temp.claim($k$'refund', 'refund_void', 'refund_apply', 'refund_apply_void'$k$, pg_temp.job('refund', r1));
  perform pg_temp.chk('D6 세금 짝 없음 — 몸 거부 글 · claim 은 failed(body_failed 1 · 같은 글)',
    v_t || ' | ' || (v->>'claimed') || ' ' || (v->>'body_failed') || ' ' || (select j.state || ' ' || (j.last_error = replace(v_t, 'ERR P0001: ', ''))::text from public.qbo_job j where j.id = pg_temp.job('refund', r1)),
    'ERR P0001: Tax rule "Out of Scope (Purchase)" has no QuickBooks tax code — link it under Settings → QuickBooks matching — nothing was sent | 1 1 failed true');
  v_t := pg_temp.bk(format($q$ select public.qbo_link_set('tax_rule', %L, %L)::text $q$, pg_temp.get('rule_oosp'), v_tax));
  perform pg_temp.chk('D7 qbo_link_set(tax_rule Out of Scope (Purchase) → 짝) — requeued 1 · R1 refund queued + note · R5(ⓖ-4 failed) · R3(ⓖ-2 failed) 그대로',
    (v_t::jsonb->>'ims_kind') || ' ' || (v_t::jsonb->>'qbo_id') || ' ' || (v_t::jsonb->>'requeued') || ' | ' || (select j.state || ' ' || (j.note like '%sent again: the purchase tax rule is now matched%')::text from public.qbo_job j where j.id = pg_temp.job('refund', r1)) || ' | ' || pg_temp.jobs(r5) || ' ' || pg_temp.jobs(r3),
    'tax_rule ' || v_tax || ' 1 | queued true | refund:failed,refund_apply:blocked refund:failed,refund_apply:blocked');
end $$;

-- ── E) claim · done(두 장 · 줄 여럿 · 대조) · void 차례(ⓖ-7) · sending 중 void · 안 보낸 void · ⓖ-5 알림 · retry 넷 ──
do $$
declare r1 text := '43f20000-0000-4000-8000-000000000001'; r2 text := '43f20000-0000-4000-8000-000000000002'; r3 text := '43f20000-0000-4000-8000-000000000003'; r4 text := '43f20000-0000-4000-8000-000000000004'; r5 text := '43f20000-0000-4000-8000-000000000005'; r6 text := '43f20000-0000-4000-8000-000000000006'; r7 text := '43f20000-0000-4000-8000-000000000007'; r8 text := '43f20000-0000-4000-8000-000000000008'; r11 text := '43f20000-0000-4000-8000-000000000011';
        v jsonb; v2 jsonb; d jsonb; b jsonb; v_t text; v_t2 text; v_t3 text; v_jr uuid; v_ar text := pg_temp.get('ar_qbo'); v_tax text := pg_temp.get('tax_oosp');
begin
  -- E1 R1 Purchase: claim → done(TotalAmt 30 · tax 0) → txn refund Purchase · apply 가 queued 로 풀린다 · reconcile none
  v := pg_temp.claim($k$'refund', 'refund_apply'$k$, pg_temp.job('refund', r1));
  d := pg_temp.done(pg_temp.job('refund', r1), 'PUR-2E32-1', 'REF-2E32-1', 30, 0, null);
  perform pg_temp.chk('E1 R1 refund claim · done(TotalAmt 30 · tax 0) — claimed 1 · jobs[0] kind · doc_number · body PaymentType · lookup · sent · mismatch null · unblocked 1 · reconcile none · txn refund Purchase PUR-2E32-1 REF-2E32-1 30 0 sent · apply queued',
    (v->>'claimed') || ' ' || (v->'jobs'->0->>'kind') || ' ' || (v->'jobs'->0->>'doc_number') || ' ' || (v->'jobs'->0->'body'->>'PaymentType') || ' ' || (v->'jobs'->0->'lookup'->>'private_note' = 'IMS refund ' || r1)::text || ' | ' || (d->>'state') || ' ' || coalesce(d->>'mismatch', 'null') || ' ' || (d->>'unblocked') || ' ' || (d->'reconcile'->>'action')
    || ' | ' || (select t.ims_kind || ' ' || t.qbo_type || ' ' || t.qbo_id || ' ' || t.doc_number || ' ' || trim_scale(t.total_amt)::text || ' ' || trim_scale(t.total_tax)::text || ' ' || t.source from public.qbo_txn t where t.ims_kind = 'refund' and t.ims_id = r1) || ' | ' || pg_temp.jobs(r1),
    '1 refund REF-2E32-1 Cash true | sent null 1 none | refund Purchase PUR-2E32-1 REF-2E32-1 30 0 sent | refund:sent,refund_apply:queued');
  -- E2 R1 0 원 Payment: 몸(Line 둘 · check_lines 둘) → claim → done(0 · 0) → txn refund_apply · reconcile same
  b := public.qbo_refund_apply_body(r1::uuid);
  v := pg_temp.claim($k$'refund', 'refund_apply'$k$, pg_temp.job('refund_apply', r1));
  d := pg_temp.done(pg_temp.job('refund_apply', r1), 'PAY-2E32-1', 'REF-2E32-1', 0, null, 0);
  perform pg_temp.chk('E2 R1 apply 몸 · claim · done — wait null · Line 둘(Expense PUR-2E32-1 30 · CreditMemo CM-2E32-01 30) · check_lines(Expense · CreditMemo) · TotalAmt 0 · 계좌 · 수단 없음 · PrivateNote · claimed 1 · sent · reconcile same · txn refund_apply Payment PAY-2E32-1 0',
    coalesce(b->>'wait_job', 'null') || ' ' || jsonb_array_length(b->'body'->'Line')::text || ' ' || (b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId') || ' ' || (b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnType') || ' ' || (b->'body'->'Line'->0->>'Amount') || ' ' || (b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnId') || ' ' || (b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnType') || ' ' || (b->'body'->'Line'->1->>'Amount')
    || ' | ' || (b->'check_lines'->0->>'txn_type') || ' ' || (b->'check_lines'->0->>'qbo_purchase_id') || ' ' || (b->'check_lines'->1->>'txn_type') || ' ' || (b->'check_lines'->1->>'qbo_creditmemo_id') || ' | ' || (b->'body'->>'TotalAmt') || ' ' || (b->'body' ?| array['PaymentMethodRef', 'DepositToAccountRef', 'PaymentRefNum'])::text || ' ' || (b->'body'->>'PrivateNote' = 'IMS refund applied ' || r1)::text
    || ' | ' || (v->>'claimed') || ' ' || (d->>'state') || ' ' || (d->'reconcile'->>'action') || ' ' || (select t.ims_kind || ' ' || t.qbo_type || ' ' || t.qbo_id || ' ' || trim_scale(t.total_amt)::text from public.qbo_txn t where t.ims_kind = 'refund_apply' and t.ims_id = r1),
    'null 2 PUR-2E32-1 Expense 30 CM-2E32-01 CreditMemo 30 | Expense PUR-2E32-1 CreditMemo CM-2E32-01 | 0 false true | 1 sent same refund_apply Payment PAY-2E32-1 0');
  -- E3 R2(크레딧 둘): Purchase done 에 TotalAmt 26(IMS 25) → sent + mismatch · apply 몸 Line 셋(Expense 25 + CM 20 + CM 5 · sandbox-2 걸음 25)
  v := pg_temp.claim($k$'refund'$k$, pg_temp.job('refund', r2));
  d := pg_temp.done(pg_temp.job('refund', r2), 'PUR-2E32-2', 'REF-2E32-2-WITH-A-VER', 26, 0, null);
  b := public.qbo_refund_apply_body(r2::uuid);
  perform pg_temp.chk('E3 R2 refund done(TotalAmt 26 ≠ 25) — sent · mismatch 글 · warning = 몸 경고(21 자) · txn.mismatch / R2 apply 몸 Line 셋(Expense 25 · CM-2E32-02 20 · CM-2E32-04 5) · check_lines 셋 · totals applied 25 · credit_numbers',
    (d->>'state') || ' | ' || (d->>'mismatch') || ' | ' || (select (j.warning like '%cut to 21 characters for QuickBooks · ' || t.mismatch)::text from public.qbo_job j join public.qbo_txn t on t.ims_kind = 'refund' and t.ims_id = j.ims_id where j.ims_id = r2 and j.kind = 'refund')
    || ' | ' || jsonb_array_length(b->'body'->'Line')::text || ' ' || (b->'body'->'Line'->0->>'Amount') || ' ' || (b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnId') || ' ' || (b->'body'->'Line'->1->>'Amount') || ' ' || (b->'body'->'Line'->2->'LinkedTxn'->0->>'TxnId') || ' ' || (b->'body'->'Line'->2->>'Amount') || ' ' || jsonb_array_length(b->'check_lines')::text || ' ' || (b->'totals'->>'applied') || ' ' || (b->'totals'->>'credit_numbers'),
    'sent | QuickBooks total 26 differs from IMS 25 (credit-note part of refund REF-2E32-2-WITH-A-VERY-LONG-REFERENCE) — check it in QuickBooks (942) | true | 3 25 CM-2E32-02 20 CM-2E32-04 5 3 25 CR-99972, CR-99974');
  -- E4 둘 다 sent 뒤 void(R1) → apply_void queued → refund_void blocked_by(ⓖ-7) · void 몸 둘 · claim · done 차례 · reconcile
  v_t := pg_temp.void(r1);
  b := public.qbo_refund_apply_void_body(r1::uuid);
  perform pg_temp.chk('E4 R1 void(둘 다 sent) — voided · 크레딧 몫 풀림 · refund_apply_void queued(note) · refund_void blocked_by 그것(note) · apply_void 몸(Id PAY-2E32-1 · SyncToken 0 · sparse · lookup)',
    v_t || ' ' || (select (a.voided_at is not null)::text from public.so_credit_alloc a where a.refund_payment_id = r1::uuid) || ' | ' || pg_temp.jobs(r1) || ' | ' || (select (j.note like '%refund voided — void the zero payment%')::text from public.qbo_job j where j.id = pg_temp.job('refund_apply_void', r1)) || ' ' || (select (j.blocked_by = pg_temp.job('refund_apply_void', r1))::text || ' ' || j.note from public.qbo_job j where j.id = pg_temp.job('refund_void', r1))
    || ' | ' || (b->'body'->>'Id') || ' ' || (b->'body'->>'SyncToken') || ' ' || (b->'body'->>'sparse') || ' ' || (b->'lookup'->>'private_note' = 'IMS refund applied ' || r1)::text,
    'voided true | refund:sent,refund_apply:sent,refund_apply_void:queued,refund_void:blocked | true true void the expense after the zero payment is voided | PAY-2E32-1 0 true true');
  b := public.qbo_refund_void_body(r1::uuid);
  perform pg_temp.chk('E5 R1 refund_void 몸(Full update 꼴 전부 · 이견 9) — Id PUR-2E32-1 · SyncToken 0 · PaymentType · AccountRef · EntityRef · TxnDate · CurrencyRef · NotApplicable · DocNumber · PrivateNote 「Voided - IMS refund <id>」 · 줄 하나 Amount 0 · detail(A/R · CustomerRef · TaxCodeRef) · 경고 「zero payment … still standing」 · lookup · sync_token',
    (b->'body'->>'Id') || ' ' || (b->'body'->>'SyncToken') || ' ' || (b->'body'->>'PaymentType') || ' ' || (b->'body' ? 'AccountRef')::text || ' ' || (b->'body'->'EntityRef'->>'value') || ' ' || (b->'body'->>'TxnDate') || ' ' || (b->'body'->'CurrencyRef'->>'value') || ' ' || (b->'body'->>'GlobalTaxCalculation') || ' ' || (b->'body'->>'DocNumber') || ' ' || (b->'body'->>'PrivateNote' = 'Voided - IMS refund ' || r1)::text
    || ' | ' || jsonb_array_length(b->'body'->'Line')::text || ' ' || (b->'body'->'Line'->0->>'Amount') || ' ' || (b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'AccountRef'->>'value') || ' ' || (b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'CustomerRef'->>'value') || ' ' || (b->'body'->'Line'->0->'AccountBasedExpenseLineDetail'->'TaxCodeRef'->>'value')
    || ' | ' || (b->'warnings'->>0) || ' | ' || (b->'lookup'->>'qbo_id') || ' ' || (b->'lookup'->>'private_note' = 'IMS refund ' || r1)::text || ' ' || (b->>'sync_token') || ' ' || (b->>'kind'),
    'PUR-2E32-1 0 Cash true C-2E32-A 2026-11-05 CAD NotApplicable REF-2E32-1 true | 1 0 ' || v_ar || ' C-2E32-A ' || v_tax || ' | the zero payment #PAY-2E32-1 that links this expense is still standing on file — it is voided first (ⓖ-7) | PUR-2E32-1 true 0 refund_void');
  v := pg_temp.claim($k$'refund_apply_void', 'refund_void'$k$, pg_temp.job('refund_apply_void', r1));
  d := pg_temp.done(pg_temp.job('refund_apply_void', r1), 'PAY-2E32-1', 'REF-2E32-1', null, null, null);
  perform pg_temp.chk('E6 apply_void claim 1 · done — sent · txn refund_apply voided · unblocked 1(refund_void → queued) · reconcile void · refund_void 몸에 이제 경고 없음(SyncToken 있음)',
    (v->>'claimed') || ' ' || (d->>'state') || ' ' || (d->>'unblocked') || ' ' || (d->'reconcile'->>'action') || ' | ' || (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'refund_apply' and t.ims_id = r1) || ' ' || pg_temp.jobs(r1) || ' | ' || jsonb_array_length(public.qbo_refund_void_body(r1::uuid)->'warnings')::text,
    '1 sent 1 void | true refund:sent,refund_apply:sent,refund_apply_void:sent,refund_void:queued | 0');
  v := pg_temp.claim($k$'refund_apply_void', 'refund_void'$k$, pg_temp.job('refund_void', r1));
  d := pg_temp.done(pg_temp.job('refund_void', r1), 'PUR-2E32-1', 'REF-2E32-1', null, null, null);
  perform pg_temp.chk('E7 refund_void claim 1 · done — sent · txn refund voided · reconcile skipped-none(열린 일감 없음) · 일감 넷 모두 sent · R1 몸 둘은 이제 「voided」 거부',
    (v->>'claimed') || ' ' || (d->>'state') || ' ' || (d->'reconcile'->>'action') || ' | ' || (select (t.voided_at is not null)::text from public.qbo_txn t where t.ims_kind = 'refund' and t.ims_id = r1) || ' ' || pg_temp.jobs(r1) || ' | ' || pg_temp.try(format('select public.qbo_refund_body(%L)::text', r1)),
    '1 sent none | true refund:sent,refund_apply:sent,refund_apply_void:sent,refund_void:sent | ERR P0001: Refund REF-2E32-1 is voided — nothing to send (a void job takes care of QuickBooks) — nothing was sent');
  -- E8 안 보낸 void(R8 · queued) → 둘 다 skipped · sending 중 void(R11) → refund_void blocked_by · apply skipped → done 뒤 refund_void queued · R2(Purchase sent · Payment 아직) void → apply skipped · refund_void queued
  v_t := pg_temp.void(r8);
  v := pg_temp.claim($k$'refund'$k$, pg_temp.job('refund', r11));
  v_jr := pg_temp.anyjob('refund', r11);
  perform pg_temp.void(r11);
  d := pg_temp.done(v_jr, 'PUR-2E32-11', 'REF-2E32-11', 5, 0, null);
  perform pg_temp.void(r2);
  perform pg_temp.chk('E8 · E9 · E10 — R8 void 전 → refund · apply skipped(「voided before sending」) / R11 sending 중 void → refund_void blocked_by 그 일감 · apply skipped → done 뒤 refund sent · void queued · reconcile void / R2(Purchase sent) void → apply skipped(「only the void goes」) · refund_void queued(note)',
    pg_temp.jobs(r8) || ' ' || (select count(*)::text from public.qbo_job j where j.ims_id = r8 and j.note like '%refund voided before sending%')
    || ' | ' || (v->>'claimed') || ' ' || (select (j.blocked_by = v_jr)::text || ' ' || j.note from public.qbo_job j where j.ims_id = r11 and j.kind = 'refund_void') || ' | ' || (d->>'state') || ' ' || (d->>'unblocked') || ' ' || (d->'reconcile'->>'action') || ' ' || pg_temp.jobs(r11)
    || ' | ' || pg_temp.jobs(r2) || ' ' || (select (j.note like '%only the void goes%')::text from public.qbo_job j where j.ims_id = r2 and j.kind = 'refund_apply') || ' ' || (select (j.note like '%void the expense in QuickBooks%')::text from public.qbo_job j where j.id = pg_temp.job('refund_void', r2)),
    'refund:skipped,refund_apply:skipped 2 | 1 true voided while sending — void after the send settles | sent 1 void refund:sent,refund_apply:skipped,refund_void:queued | refund:sent,refund_apply:skipped,refund_void:queued true true');
  -- E11 ⓖ-5: 컷 전 환불 R4(일감 0) void → refund_void failed(알림 글) · retry 는 「not standing」 으로 거부 · skip 은 된다
  v_t := pg_temp.void(r4);
  v_t2 := pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.job('refund_void', r4)));
  v_t3 := pg_temp.jobs(r4) || ' | ' || pg_temp.err(r4, 'refund_void');
  perform pg_temp.chk('E11 ⓖ-5 — R4(컷 전 · 일감 0) void → refund_void:failed + 알림 글 · retry 거부(not standing — nothing to void) · skip 가능',
    v_t || ' ' || v_t3 || ' | ' || v_t2 || ' | ' || pg_temp.bk(format('select (public.qbo_job_skip(%L, ''voided in QuickBooks by hand''))->>''state''', pg_temp.job('refund_void', r4))),
    'voided refund_void:failed | This refund was entered in QuickBooks by hand before the cut-over (2026-10-30) — void it there too (if it is there), then skip this job | ERR P0001: Refund REF-2E32-4 (expense) is not standing in QuickBooks — nothing to void — nothing was saved | skipped');
  -- E12 retry 넷 — R5(ⓖ-4 failed) retry OK → queued → claim 1(몸이 컷을 안 본다 = Send) / R3(ⓖ-2 failed) retry OK → claim 은 다시 failed 같은 글 / R8 refund(skipped · void 됨) 거부 / R2 refund_void(queued) 상태 거부 / R6 refund(blocked 로 만든 뒤) 상태 거부
  v_t := pg_temp.bk(format('select (public.qbo_job_retry(%L, ''checked QuickBooks — not there''))->>''state''', pg_temp.job('refund', r5)));
  v := pg_temp.claim($k$'refund'$k$, pg_temp.job('refund', r5));
  v_t2 := pg_temp.bk(format('select (public.qbo_job_retry(%L, null))->>''state''', pg_temp.job('refund', r3)));
  v2 := pg_temp.claim($k$'refund'$k$, pg_temp.job('refund', r3));
  perform pg_temp.chk('E12 retry — R5 queued → claim 1 · body_failed 0 · Line Amount 10 / R3 retry queued → claim body_failed 1 · ⓖ-2 글 그대로 / R8 skipped 거부 / R2 refund_void queued 상태 거부 / R6 blocked 상태 거부',
    v_t || ' ' || (v->>'claimed') || ' ' || (v->>'body_failed') || ' ' || (v->'jobs'->0->'body'->'Line'->0->>'Amount')
    || ' | ' || v_t2 || ' ' || (v2->>'body_failed') || ' ' || (select j.state || ' ' || (j.last_error like 'Refund REF-2E32-3 pays CAD 2 from money on account%')::text from public.qbo_job j where j.id = pg_temp.job('refund', r3))
    || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.anyjob('refund', r8))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.job('refund_void', r2))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', pg_temp.job('refund_apply', r6))),
    'queued 1 0 10 | queued 1 failed true | ERR P0001: Refund REF-2E32-8 is voided — nothing to send (a void job takes care of QuickBooks) — nothing was saved | ERR P0001: Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is queued) — nothing was saved | ERR P0001: Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is blocked) — nothing was saved');
  update public.qbo_job set state = 'failed', last_error = 'test: refused' where id = pg_temp.job('refund_void', r2);
  update public.qbo_job set state = 'failed', last_error = 'test: refused' where id = pg_temp.job('refund_apply', r6);
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error) values (pg_temp.get('realm'), 'refund_apply_void', 'refund', r11, 'failed', 'test') returning id into v_jr;
  perform pg_temp.chk('E13 retry 규칙(failed 로 만들고) — R2 refund_void(Purchase 서 있음 · void 됨) OK queued · R6 refund_apply(Purchase 아직 · 활성) OK queued(몸이 기다린다) · R11 refund_apply_void(Payment 안 섬) 거부',
    pg_temp.bk(format('select (public.qbo_job_retry(%L, ''ok''))->>''state''', pg_temp.job('refund_void', r2))) || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''ok''))->>''state''', pg_temp.job('refund_apply', r6)))
    || ' | ' || pg_temp.bk(format('select (public.qbo_job_retry(%L, ''why''))->>''state''', v_jr)),
    'queued | queued | ERR P0001: Refund REF-2E32-11 (zero payment) is not standing in QuickBooks — nothing to void — nothing was saved');
end $$;

-- ── F) claim 가지(needs · wait) · ⓖ-1 가드(가짜) · list · doc · preview · kinds ──
do $$
declare r1 text := '43f20000-0000-4000-8000-000000000001'; r6 text := '43f20000-0000-4000-8000-000000000006'; r7 text := '43f20000-0000-4000-8000-000000000007'; v jsonb; v2 jsonb; ls jsonb; pv jsonb; v_t text; v_al text; v_bl text;
        cA constant uuid := 'c3f20000-0000-4000-8000-00000000000a'; cB constant uuid := 'c3f20000-0000-4000-8000-00000000000b';
begin
  v := pg_temp.claim($k$'refund'$k$, pg_temp.job('refund', r7));
  v2 := pg_temp.claim($k$'refund'$k$, pg_temp.job('refund', r6));
  perform pg_temp.chk('F1 claim 가지 — R7(손님 B 짝 없음) blocked_for_needs 1 · need_jobs customer B(새 일감) · R6 refund claim → blocked_for_invoice 1(CR-99977 일감 뒤 · warning)',
    (v->>'blocked_for_needs') || ' ' || (v->'need_jobs'->0->>'kind') || ' ' || (v->'need_jobs'->0->>'ims_id') || ' ' || (select j.state from public.qbo_job j where j.id = pg_temp.job('refund', r7)) || ' ' || (select (j.blocked_by = pg_temp.job('customer', cB::text))::text from public.qbo_job j where j.id = pg_temp.job('refund', r7))
    || ' | ' || (v2->>'blocked_for_invoice') || ' ' || (select j.state || ' ' || (j.blocked_by = pg_temp.job('credit', '33f20000-0000-4000-8000-000000000007'))::text || ' ' || j.warning from public.qbo_job j where j.id = pg_temp.job('refund', r6)),
    '1 customer ' || cB::text || ' blocked true | 1 blocked true waiting for credit note CR-99977 to reach QuickBooks first');
  -- ⓖ-1 (다): 손님 A(이월 50 · 환불 account 몫 = R3 2 + R4 10(void 됨 → 0) + R10 50 = 52 · USD R9 제외) 의 이월 붙임 20 → 남은 30 − 52 < 0 → opening_credit failed · apply blocked · 몸도 같은 글 / 손님 B(환불 0) 의 이월 붙임 4 → queued(무변)
  set constraints all deferred;
  insert into public.so_payment_alloc (payment_id, invoice_id, amount, source, created_by) values ('43f20000-0000-4000-8000-0000000000a0', '13f20000-0000-4000-8000-000000000001', 20, 'auto_balance', 'e3f20000-0000-4000-8000-00000000000a') returning id::text into v_al;
  insert into public.so_payment_alloc (payment_id, invoice_id, amount, source, created_by) values ('43f20000-0000-4000-8000-0000000000b0', '13f20000-0000-4000-8000-000000000002', 4, 'auto_balance', 'e3f20000-0000-4000-8000-00000000000a') returning id::text into v_bl;
  set constraints all immediate;
  perform pg_temp.chk('F2 ⓖ-1 가드 — A 의 이월 붙임: opening_credit:failed + opening_apply:blocked · 글(30 left · 52 refunded) · 몸 거부 같은 글 · 도우미 / B 의 이월 붙임: queued + blocked(무변) · 도우미 null · 결제 길(qbo_payment_sync) 무변',
    pg_temp.jobs(v_al) || ' | ' || pg_temp.err(v_al, 'opening_credit') || ' | ' || (pg_temp.try(format('select public.qbo_opening_credit_body(%L)::text', v_al)) = 'ERR P0001: ' || public.qbo_opening_refunded_block(v_al::uuid))::text
    || ' | ' || pg_temp.jobs(v_bl) || ' ' || coalesce(public.qbo_opening_refunded_block(v_bl::uuid), 'null') || ' | ' || (public.qbo_payment_sync('43f20000-0000-4000-8000-0000000000a0', null)->>'action'),
    'opening_credit:failed,opening_apply:blocked | Opening credit OC-9972001-1 → 9972001 uses carried-over money that was refunded already (CAD 30 of carried-over money is left after applications, but 52 of it was refunded) — detach it in the IMS and attach other money — nothing was sent | true | opening_credit:queued,opening_apply:blocked null | not_applicable');
  ls := pg_temp.bk($q$ select public.qbo_job_list(null, array['refund', 'refund_void', 'refund_apply', 'refund_apply_void'], null, null, 'REF-2E32', 50, 0)::text $q$)::jsonb;
  perform pg_temp.chk('F3 list(kinds 넷 · q REF-2E32) — 가짜 줄 수 = DB 일감 수 · R1 refund_void 줄 txn = PUR-2E32-1(voided) · refund_apply_void 줄 txn = PAY-2E32-1(voided)(kind 로 갈라 잇기) · doc(REF-2E32-1 · 손님 A · CAD 30 · 2026-11-05 · voided) · ims_name',
    (select count(*)::text from jsonb_array_elements(ls->'rows') r) || '=' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'refund' and j.ims_id like '43f2%')
    || ' | ' || (select (r->>'txn_qbo_id') || ' ' || (r->>'txn_voided_at' is not null)::text from jsonb_array_elements(ls->'rows') r where r->>'ims_id' = r1 and r->>'kind' = 'refund_void') || ' | ' || (select (r->>'txn_qbo_id') || ' ' || (r->>'txn_voided_at' is not null)::text from jsonb_array_elements(ls->'rows') r where r->>'ims_id' = r1 and r->>'kind' = 'refund_apply_void')
    || ' | ' || (select (r->>'doc_number') || ' ' || (r->>'name') || ' ' || (r->>'currency') || ' ' || (r->>'total') || ' ' || (r->>'doc_date') || ' ' || (r->>'doc_status') || ' | ' || (r->>'ims_name') from jsonb_array_elements(ls->'rows') r where r->>'ims_id' = r1 and r->>'kind' = 'refund'),
    (select count(*)::text from public.qbo_job j where j.ims_kind = 'refund' and j.ims_id like '43f2%') || '=' || (select count(*)::text from public.qbo_job j where j.ims_kind = 'refund' and j.ims_id like '43f2%')
    || ' | PUR-2E32-1 true | PAY-2E32-1 true | REF-2E32-1 QBO2E32 Store A CAD 30 2026-11-05 voided | REF-2E32-1 · QBO2E32 Store A · CAD 30');
  pv := pg_temp.bk(format('select public.qbo_job_preview(%L)::text', pg_temp.job('refund', r7)))::jsonb;
  perform pg_temp.chk('F4 doc · preview · kinds — qbo_job_doc(refund R1 · 환불 없는 id null · reference 없으면 「Refund <날> <금액>」) · preview(R7 · blocked_by customer · needs 1 · sendable false · doc) · list kinds 18 글 · claim 기본 kinds 그대로',
    (public.qbo_job_doc('refund', r1)->>'doc_number') || ' ' || (public.qbo_job_doc('refund', r1)->>'doc_status') || ' | ' || coalesce(public.qbo_job_doc('refund', gen_random_uuid()::text)::text, 'null') || ' | ' || (select public.qbo_refund_label(p) from public.so_payment p where p.id = '43f20000-0000-4000-8000-000000000010') || ' ' || (select public.qbo_refund_label((p.id, p.kind, p.amount, p.paid_on, p.method, null, p.customer_id, p.currency_id, p.currency_code, p.account_id, p.account_code, p.warehouse_id, p.warehouse_name, p.note, p.status, p.voided_at, p.voided_by, p.void_note, p.created_by, p.created_at, p.updated_at, p.updated_by)::public.so_payment) from public.so_payment p where p.id = '43f20000-0000-4000-8000-000000000010')
    || ' | ' || (pv->'blocked_by'->>'kind') || ' ' || jsonb_array_length(pv->'needs')::text || ' ' || (pv->>'sendable') || ' ' || (pv->'doc'->>'doc_number') || ' | ' || pg_temp.bk($q$ select (public.qbo_job_list(null, array['bogus']))->>'kinds' $q$) || ' | ' || pg_temp.svc($q$ select (public.qbo_job_claim(5))->>'kinds' $q$),
    'REF-2E32-1 voided | null | REF-2E32-10 Refund 2026-11-05 50 | customer 1 false REF-2E32-7 | ERR P0001: kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void (got {bogus}) | ["customer", "item"]');
  perform pg_temp.chk('F5 qbo_link_set 의 다른 가지 그대로(payment_method · charge acct:) · claim 몸 CASE 에 refund 넷 · preview 도', (select (prosrc like '%qbo_payment_method_requeue(p_ims_id, v_staff)%' and prosrc like '%qbo_opening_credit_requeue(substr(p_ims_id, 6), v_staff)%' and prosrc like '%qbo_refund_requeue(v_staff)%')::text from pg_proc where proname = 'qbo_link_set' and pronamespace = 'public'::regnamespace)
    || ' ' || (select (prosrc like '%when ''refund_apply_void'' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)%')::text from pg_proc where proname = 'qbo_job_claim' and pronamespace = 'public'::regnamespace) || ' ' || (select (prosrc like '%when ''refund_void'' then public.qbo_refund_void_body(v_j.ims_id::uuid)%')::text from pg_proc where proname = 'qbo_job_preview' and pronamespace = 'public'::regnamespace), 'true true true');
  perform pg_temp.chk('F6 바뀐 함수 = 재발행 열 + 새 함수(t_pre 에 없음) · 그 밖 무변', (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5), case when pg_temp.get('mig') = 'true' then 'qbo_job_claim,qbo_job_doc,qbo_job_done,qbo_job_list,qbo_job_on_payment_status,qbo_job_preview,qbo_job_retry,qbo_link_set,qbo_opening_alloc_sync,qbo_opening_credit_body' else '(none)' end);
end $$;

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback, :'t_fixtures'::timestamptz - :'t_begin'::timestamptz as fixtures, :'t_mig'::timestamptz - :'t_fixtures'::timestamptz as mig_file, clock_timestamp() - :'t_mig'::timestamptz as mig_end_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.so_invoice) = :n_inv0 as invoice_same, (select count(*) from public.so_credit) = :n_cr0 as credit_same,
       (select count(*) from public.so_credit_alloc) = :n_calloc0 as calloc_same, (select count(*) from public.so_payment_alloc) = :n_palloc0 as palloc_same, (select count(*) from public.so_payment) = :n_pay0 as payment_same,
       (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_txn) = :n_txn0 as txn_same, (select count(*) from public.qbo_link) = :n_link0 as link_same, (select count(*) from public.qbo_entity) = :n_ent0 as entity_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
