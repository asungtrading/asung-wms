-- supabase/tests/qbo_sync_4_7b_check.sql — qbo-sync-4-7b(DB 몫) 검증 (2026-11-09 토론토 밤 · 판정 1150 「가」 · §0 이견 1 · 4 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i) → 가짜 재료(DO 하나) → S1 할인 결제 claim = needs 길(VC 일감이 need_jobs 로 · 미리 보기 needs) · S2 할인 둘인 결제 · S3 할인 VC Skip → 결제가 풀려 몸이 raise(failed + 출구) → Retry 둘 · S4 Bill 이 안 간 결제(VC 는 needs 에 없음) · S5 qbo_job_open_or_add 가지 · S6 회귀 · W REST WHERE · G 착지 · Z 실제 행 무변 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261110040718_qbo_sync_4_7b_discount_credit_needs.sql -f supabase/tests/qbo_sync_4_7b_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(두 갈래 같다 · 갈래 전용 검사 없음) · FAIL 이 하나라도 있으면 exit 3
--   마른 실행(적용 전 · -v mig 없음 = 옛 함수): 결함이 FAIL 로 잡히고 exit 3 — 기대 OK 12 · FAIL 11(S1b · S1c · S1d · S2a · S2b · S3a · S3b · S5a · S5b · S5c · G1) · 실측 2026-11-10 UTC · begin → rollback 7.5 초(시험 적용 9.3 초)
--   ⚠️ 가짜 재료만(직원 zz-qbo-sync-4-7b@ · 공급처 ZZ-QBO47B · 계좌 ZZ47B-BANK-CAD · PO-79473 · 인보이스 ZZ47B-INV-1 ~ 7 · 거울 zz7b*) — 실제 행은 읽기만 · claim 은 늘 일감 id 로만 · 번호 시퀀스 무접촉 · 공개 레포 — 상호를 찍지 않는다
--   잠금: 함수 재발행(카탈로그) + 가짜 행 — QBO · PO 표의 행 잠금은 이 트랜잭션의 새 행뿐
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 23
select (select value from public.inv_config where key = 'db_role') as db_role;

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create temp table t_ids (k text primary key, v text);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label;
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
$$;
create function pg_temp.svc(p_sql text) returns jsonb language plpgsql as $$
declare v jsonb; v_claims text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', '{"role":"service_role"}', true);
  execute p_sql into v;
  perform set_config('request.jwt.claims', coalesce(v_claims, ''), true);
  return v;
end $$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.job(p_kind text, p_ims_kind text, p_ims_id text) returns public.qbo_job language sql as $$
  select j.* from public.qbo_job j where j.kind = p_kind and j.ims_kind = p_ims_kind and j.ims_id = p_ims_id order by j.created_at desc, j.id desc limit 1
$$;
create function pg_temp.openjob(p_kind text, p_ims_kind text, p_ims_id text) returns public.qbo_job language sql as $$
  select j.* from public.qbo_job j where j.kind = p_kind and j.ims_kind = p_ims_kind and j.ims_id = p_ims_id and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1
$$;
create function pg_temp.claim1(p_job uuid, p_kind text) returns jsonb language sql as $$
  select pg_temp.svc(format('select public.qbo_job_claim(1, array[%L], array[%L]::uuid[])', p_kind, p_job))
$$;
create function pg_temp.mkpay(p_key text, p_cur text, p_amount numeric, p_acct text, p_ref text, p_targets jsonb, p_rate numeric default null, p_disc numeric default 0) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v := public.po_payment_create(null, public.ims_today(), p_amount, pg_temp.id(p_cur)::uuid, p_disc, pg_temp.id(p_acct)::uuid, p_ref, null, p_targets, true, p_rate);
  perform pg_temp.as_user(null);
  perform pg_temp.put(p_key, v->>'payment_id');
  perform pg_temp.put(p_key || '_a', (select a.id::text from public.po_payment_alloc a where a.po_payment_id = (v->>'payment_id')::uuid order by a.created_at, a.id limit 1));
  return v;
end $$;
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

-- ── 기준(begin 앞 · 잠금 없음) ──
select (select count(*) from public.po_invoice) as pre_inv, (select count(*) from public.po_payment) as pre_pay, (select count(*) from public.po_payment_alloc) as pre_alloc, (select count(*) from public.qbo_job) as pre_jobs, (select count(*) from public.qbo_txn) as pre_txn,
       (select count(*) from public.supplier) as pre_sup, (select count(*) from public.ims_staff) as pre_staff, (select count(*) from public.inv_cost_adjust) as pre_adj,
       (select md5(coalesce(string_agg(md5(to_jsonb(i)::text), ',' order by i.id), '')) from public.po_invoice i) as pre_inv_md5,
       (select md5(coalesce(string_agg(md5(to_jsonb(p)::text), ',' order by p.id), '')) from public.po_payment p) as pre_pay_md5,
       (select md5(coalesce(string_agg(md5(to_jsonb(a)::text), ',' order by a.id), '')) from public.po_payment_alloc a) as pre_alloc_md5,
       (select md5(coalesce(string_agg(md5(to_jsonb(j)::text), ',' order by j.id), '')) from public.qbo_job j) as pre_job_md5,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_skip', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_done', 'qbo_discount_credit_body', 'qbo_discount_credit_sync', 'qbo_bill_payment_sync', 'qbo_bill_payment_void_body', 'qbo_bill_payment_fingerprint', 'qbo_vendor_credit_body', 'qbo_bill_body', 'po_payment_create')) as pre_md5_same,
       (select string_agg(proname || ':' || coalesce(proacl::text, '') || ':' || prosecdef::text || ':' || provolatile::text || ':' || pg_get_function_identity_arguments(oid), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_payment_body', 'qbo_job_open_or_add', 'qbo_job_claim')) as pre_three_shape,
       (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_payment_body', 'qbo_job_open_or_add', 'qbo_job_claim')) as pre_three_md5,
       clock_timestamp() as t_begin \gset
\echo '── 기준: invoices' :pre_inv '· payments' :pre_pay '· allocs' :pre_alloc '· jobs' :pre_jobs '· txn' :pre_txn
\echo '── 기준 세 함수 md5:' :pre_three_md5

begin;
set local statement_timeout = '120s';
set local lock_timeout = '3s';
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

-- ── 가짜 재료(DO 하나) — 직원 · 공급처 B(CAD) · 계좌(+ 거울 · 짝) · Vendor 거울 · PO + 줄 · 인보이스 일곱(20.00 = 8 × 2.5 · confirmed · Zero-rated) · Bill 일감 sent + qbo_txn Bill(6 번만 Bill 일감 queued · 짝 없음) ──
do $$
declare v_cad uuid := (select id from public.ref_currency where code = 'CAD'); v_ap_cad public.ref_account%rowtype; v_term uuid := (select id from public.ref_payment_term where name = 'Net 30' and net_days = 30);
        v_zero uuid := (select id from public.ref_tax_rule where name = 'Zero-rated (Purchase)'); v_prod uuid := (select id from public.product where sku = 'AAL10850'); v_realm text := (select realm_id from public.qbo_connection where singleton);
        v_sb uuid := gen_random_uuid(); v_acb uuid := gen_random_uuid(); v_po uuid := gen_random_uuid(); v_l uuid := gen_random_uuid(); v_st uuid := gen_random_uuid(); v_staff uuid; v_k int; v_id uuid; v_bj uuid;
begin
  select * into v_ap_cad from public.ref_account where code = '_62_';
  if v_cad is null or v_term is null or v_zero is null or v_prod is null or v_realm is null or v_ap_cad.id is null then raise exception 'fixture: a reference row is missing (currency CAD · term Net 30 · tax rule Zero-rated (Purchase) · product AAL10850 · realm · A/P _62_)'; end if;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_st, 'zz-qbo-sync-4-7b@test.invalid', 'ZZ qbo-sync-4-7b bookkeeper', 'manager', '["ims", "qbo", "purchasing"]', '{}') returning id into v_staff;
  insert into public.supplier (id, name, source, is_active, payment_term_id, payment_term_name, account_payable_id, account_payable_code, currency_id) values (v_sb, 'ZZ-QBO47B Supplier B', 'manual', true, v_term, 'Net 30', v_ap_cad.id, v_ap_cad.code, v_cad);
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active) values (v_realm, 'Vendor', 'zz7bvb', 'ZZ-QBO47B Vendor B', true);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (v_realm, 'supplier', v_sb::text, 'Vendor', 'zz7bvb', 'manual');
  insert into public.ref_account (id, code, name, account_class, account_type, source, currency_code) values (v_acb, 'ZZ47B-BANK-CAD', 'ZZ47B Bank CAD', 'ASSET', 'BANK', 'manual', null);
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active, detail) values (v_realm, 'Account', 'zz7bacb', 'ZZ47B Bank CAD', true, '{"AccountType": "Bank", "CurrencyRef": {"value": "CAD"}}'::jsonb);
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by) values (v_realm, 'account', v_acb::text, 'Account', 'zz7bacb', 'manual');
  insert into public.po (id, po_number, status, supplier_id, currency_id) values (v_po, 'PO-79473', 'confirmed', v_sb, v_cad);
  insert into public.po_line (id, po_id, line_no, product_id, qty_ea, unit_price) values (v_l, v_po, 1, v_prod, 400, 2.5);
  for v_k in 1..7 loop
    v_id := gen_random_uuid();
    insert into public.po_invoice (id, supplier_id, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name, currency_id, exchange_rate, total_amount, status, doc_kind, tax_rule_id, confirmed_by, confirmed_at, created_at)
    values (v_id, v_sb, 'ZZ47B-INV-' || v_k, public.ims_today(), public.ims_today() + 30, v_term, 'Net 30', v_cad, null, 20, 'confirmed', 'invoice', v_zero, v_staff, now(), now());
    insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price) values (v_id, 1, 'goods', v_l, 8, 2.5);
    if v_k = 6 then
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'bill', 'po_invoice', v_id::text, 'queued', v_staff) on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      select j.id into v_bj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'bill' and j.ims_kind = 'po_invoice' and j.ims_id = v_id::text and j.state not in ('sent', 'skipped');
      perform pg_temp.put('bill6', v_bj::text);
    else
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, sent_at, qbo_id, qbo_name, fingerprint, by_staff) values (v_realm, 'bill', 'po_invoice', v_id::text, 'sent', now(), 'zz7bb' || v_k, 'ZZ47B-INV-' || v_k, '2000|X', v_staff);
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, fingerprint, source) values (v_realm, 'po_invoice', v_id::text, 'Bill', 'zz7bb' || v_k, 'ZZ47B-INV-' || v_k, '0', 20, 0, '2000|X', 'sent');
    end if;
    perform pg_temp.put('i' || v_k, v_id::text);
  end loop;
  perform pg_temp.put('staff', v_staff::text); perform pg_temp.put('st_uid', v_st::text); perform pg_temp.put('sb', v_sb::text); perform pg_temp.put('acb', v_acb::text); perform pg_temp.put('cad', v_cad::text); perform pg_temp.put('realm', v_realm);
end $$;
set constraints all immediate;

-- ── S1 할인 하나인 결제(2223170 꼴) — 결제 claim 이 VC 일감을 need_jobs 로 돌려준다(1150) · 미리 보기 needs · blocked 를 다시 골라도 need_jobs · VC sent → 결제 claimed(줄 둘) ──
do $$
declare v_r jsonb; v_c jsonb; v_b jsonb; v_n jsonb; v_vj public.qbo_job; v_pj public.qbo_job; v_a text; v_pv jsonb; v_jobs0 bigint;
begin
  v_r := pg_temp.mkpay('p1', 'cad', 19.6, 'acb', 'ZZ47B-P1', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i1'), 'amount', 20, 'discount', 0.4)), null, 0.4);
  v_a := pg_temp.id('p1_a');
  v_vj := pg_temp.openjob('vendor_credit', 'po_discount', v_a); v_pj := pg_temp.openjob('bill_payment', 'po_payment', pg_temp.id('p1'));
  perform pg_temp.chk('S1a 할인 결제 저장(인보이스 1 · 20 · 할인 0.4 · 낸 돈 19.6): 할인 VC 일감 queued · 결제 일감 queued', coalesce(v_vj.state, '(none)') || ' ' || coalesce(v_pj.state, '(none)'), 'queued queued');
  select count(*) into v_jobs0 from public.qbo_job;
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1')); v_n := v_c->'need_jobs'->0;
  perform pg_temp.chk('S1b 결제 claim(id): blocked_for_needs 1 · blocked_for_invoice 0 · need_jobs 하나 = 그 VC 일감(vendor_credit · po_discount · existing · for_job = 결제 · queued) · 결제 blocked_by = VC 일감 · requested blocked · 새 일감 0',
    coalesce(v_c->>'blocked_for_needs', '?') || ' ' || coalesce(v_c->>'blocked_for_invoice', '?') || ' ' || jsonb_array_length(coalesce(v_c->'need_jobs', '[]'))::text || ' ' || coalesce(v_n->>'kind', '?') || ' ' || coalesce(v_n->>'ims_kind', '?') || ' ' || ((v_n->>'job_id') = v_vj.id::text)::text
      || ' ' || coalesce(v_n->>'existing', '?') || ' ' || ((v_n->>'for_job') = v_pj.id::text)::text || ' ' || coalesce(v_n->>'state', '?') || ' ' || v_pj.state || ' ' || (v_pj.blocked_by is not distinct from v_vj.id)::text || ' ' || coalesce(v_c->'requested'->0->>'result', '?')
      || ' ' || ((select count(*) from public.qbo_job) - v_jobs0)::text,
    '1 0 1 vendor_credit po_discount true true true queued blocked true blocked 0');
  perform pg_temp.chk('S1c 결제 일감 글: 「…discount credit of invoice ZZ47B-INV-1 is created in QuickBooks first, in the same send…」 + 「waiting for 1 QuickBooks record(s)…」',
    (coalesce(v_pj.warning, '') like '%early-payment discount credit of invoice ZZ47B-INV-1 is created in QuickBooks first, in the same send%')::text || ' ' || (coalesce(v_pj.warning, '') like '%waiting for 1 QuickBooks record(s) to be created first%')::text, 'true true');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_pv := public.qbo_job_preview(v_pj.id);
  perform pg_temp.as_user(null);
  perform pg_temp.chk('S1d 미리 보기: needs 하나(vendor_credit · job_id = VC 일감 · job_state queued · 이름 「Discount credit D<yymmdd>-ZZ47B-INV-1 · 0.4 CAD」) · wait 없음 · sendable false · error 없음',
    jsonb_array_length(coalesce(v_pv->'needs', '[]'))::text || ' ' || coalesce(v_pv->'needs'->0->>'kind', '?') || ' ' || ((v_pv->'needs'->0->>'job_id') = v_vj.id::text)::text || ' ' || coalesce(v_pv->'needs'->0->>'job_state', '?')
      || ' ' || ((v_pv->'needs'->0->>'name') = 'Discount credit D' || to_char(public.ims_today(), 'YYMMDD') || '-ZZ47B-INV-1 · 0.4 CAD')::text || ' ' || (coalesce(v_pv->'wait', 'null'::jsonb) = 'null'::jsonb)::text || ' ' || coalesce(v_pv->>'sendable', '?') || ' ' || coalesce(v_pv->>'error', 'none'),
    '1 vendor_credit true queued true true false none');
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_n := v_c->'need_jobs'->0;
  perform pg_temp.chk('S1e 이미 blocked 인 결제를 다시 고름: claimed 0 · need_jobs 하나 = 같은 VC 일감(겹치지 않음) · requested not_queued',
    coalesce(v_c->>'claimed', '?') || ' ' || jsonb_array_length(coalesce(v_c->'need_jobs', '[]'))::text || ' ' || ((v_n->>'job_id') = v_vj.id::text)::text || ' ' || coalesce(v_n->>'ims_kind', '?') || ' ' || coalesce(v_c->'requested'->0->>'result', '?'), '0 1 true po_discount not_queued');
  v_c := pg_temp.claim1(v_vj.id, 'vendor_credit');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz7bvc1', 'D-ZZ47B-INV-1', '0', null, null, null, 0.40, 0, null)$q$, v_vj.id));
  perform pg_temp.put('s1_after_done', (pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'))).state);
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_b := v_c->'jobs'->0; v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p1'));
  perform pg_temp.chk('S1f VC sent(done 이 결제를 queued 로 푼다) → 같은 결제 claim: claimed 1 · need_jobs 0 · TotalAmt 19.6 · 줄 둘 = Bill zz7bb1 20 + VendorCredit zz7bvc1 0.4 · 경고 없음',
    coalesce(v_r->>'state', '?') || ' ' || pg_temp.id('s1_after_done') || ' ' || coalesce(v_c->>'claimed', '?') || ' ' || jsonb_array_length(coalesce(v_c->'need_jobs', '[]'))::text || ' ' || coalesce(v_b->'body'->>'TotalAmt', '?') || ' ' || jsonb_array_length(coalesce(v_b->'body'->'Line', '[]'))::text
      || ' ' || coalesce(v_b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnType', '?') || ' ' || coalesce(v_b->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId', '?') || ' ' || coalesce(v_b->'body'->'Line'->0->>'Amount', '?')
      || ' ' || coalesce(v_b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnType', '?') || ' ' || coalesce(v_b->'body'->'Line'->1->'LinkedTxn'->0->>'TxnId', '?') || ' ' || coalesce(v_b->'body'->'Line'->1->>'Amount', '?') || ' ' || coalesce(v_pj.warning, 'none'),
    'sent queued 1 0 19.6 2 Bill zz7bb1 20 VendorCredit zz7bvc1 0.4 none');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S1 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S2 할인 인보이스 둘인 결제 — need_jobs 둘(한 번에) · 하나만 가면 풀렸다가 남은 하나로 다시 blocked · 둘 다 가면 claimed(줄 넷) ──
do $$
declare v_r jsonb; v_c jsonb; v_b jsonb; v_pj public.qbo_job; v_a3 text; v_a4 text; v_j3 public.qbo_job; v_j4 public.qbo_job; v_first public.qbo_job; v_second public.qbo_job;
begin
  v_r := pg_temp.mkpay('p2', 'cad', 39.2, 'acb', 'ZZ47B-P2', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i3'), 'amount', 20, 'discount', 0.4), jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i4'), 'amount', 20, 'discount', 0.4)), null, 0.8);
  select a.id::text into v_a3 from public.po_payment_alloc a where a.po_payment_id = pg_temp.id('p2')::uuid and a.po_invoice_id = pg_temp.id('i3')::uuid;
  select a.id::text into v_a4 from public.po_payment_alloc a where a.po_payment_id = pg_temp.id('p2')::uuid and a.po_invoice_id = pg_temp.id('i4')::uuid;
  v_j3 := pg_temp.openjob('vendor_credit', 'po_discount', v_a3); v_j4 := pg_temp.openjob('vendor_credit', 'po_discount', v_a4); v_pj := pg_temp.openjob('bill_payment', 'po_payment', pg_temp.id('p2'));
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p2'));
  perform pg_temp.chk('S2a 할인 둘 결제 claim: need_jobs 둘 = 두 VC 일감(한 번에) · 결제 blocked · blocked_by 는 둘 중 하나 · 글 「waiting for 2…」',
    jsonb_array_length(coalesce(v_c->'need_jobs', '[]'))::text || ' ' || (select count(distinct x->>'job_id') from jsonb_array_elements(coalesce(v_c->'need_jobs', '[]')) x where (x->>'job_id') in (v_j3.id::text, v_j4.id::text) and x->>'ims_kind' = 'po_discount')::text
      || ' ' || v_pj.state || ' ' || (v_pj.blocked_by in (v_j3.id, v_j4.id))::text || ' ' || (coalesce(v_pj.warning, '') like '%waiting for 2 QuickBooks record(s)%')::text, '2 2 blocked true true');
  if v_pj.blocked_by = v_j3.id then v_first := v_j3; v_second := v_j4; else v_first := v_j4; v_second := v_j3; end if;
  v_c := pg_temp.claim1(v_first.id, 'vendor_credit');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz7bvc2', 'D-ZZ47B-A', '0', null, null, null, 0.40, 0, null)$q$, v_first.id));
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p2'));
  perform pg_temp.chk('S2b 기다리던 VC 하나만 sent → 결제가 풀렸다가 남은 VC 로 다시 blocked: blocked_for_needs 1 · need_jobs 하나 = 남은 VC · blocked_by = 남은 VC · 쓰기 0(jobs 0)',
    coalesce(v_c->>'blocked_for_needs', '?') || ' ' || jsonb_array_length(coalesce(v_c->'need_jobs', '[]'))::text || ' ' || ((v_c->'need_jobs'->0->>'job_id') = v_second.id::text)::text || ' ' || v_pj.state || ' ' || (v_pj.blocked_by is not distinct from v_second.id)::text || ' ' || jsonb_array_length(coalesce(v_c->'jobs', '[]'))::text,
    '1 1 true blocked true 0');
  v_c := pg_temp.claim1(v_second.id, 'vendor_credit');
  v_r := pg_temp.svc(format($q$select public.qbo_job_done(%L::uuid, 'zz7bvc3', 'D-ZZ47B-B', '0', null, null, null, 0.40, 0, null)$q$, v_second.id));
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_b := v_c->'jobs'->0;
  perform pg_temp.chk('S2c 둘 다 sent → 결제 claimed: TotalAmt 39.2 · 줄 넷(Bill 20 · VendorCredit 0.4 둘씩) · check_lines 넷',
    coalesce(v_c->>'claimed', '?') || ' ' || coalesce(v_b->'body'->>'TotalAmt', '?') || ' ' || jsonb_array_length(coalesce(v_b->'body'->'Line', '[]'))::text
      || ' ' || (select count(*) filter (where x->'LinkedTxn'->0->>'TxnType' = 'Bill' and (x->>'Amount')::numeric = 20)::text || ' ' || count(*) filter (where x->'LinkedTxn'->0->>'TxnType' = 'VendorCredit' and (x->>'Amount')::numeric = 0.4 and x->'LinkedTxn'->0->>'TxnId' in ('zz7bvc2', 'zz7bvc3'))::text from jsonb_array_elements(coalesce(v_b->'body'->'Line', '[]')) x)
      || ' ' || jsonb_array_length(coalesce(v_b->'check_lines', '[]'))::text, '1 39.2 4 2 2 4');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S2 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S3 사람이 할인 VC 일감을 Skip — 옛: 결제가 skipped 부모에 영구 blocked · 새: 다음 claim 의 ② 가 풀고 몸이 raise → failed + 출구 글 → VC Retry · 결제 Retry → 다시 needs 길 ──
do $$
declare v_r jsonb; v_c jsonb; v_t text; v_pj public.qbo_job; v_vj public.qbo_job; v_a text;
begin
  v_r := pg_temp.mkpay('p3', 'cad', 19.6, 'acb', 'ZZ47B-P3', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i5'), 'amount', 20, 'discount', 0.4)), null, 0.4);
  v_a := pg_temp.id('p3_a'); v_vj := pg_temp.openjob('vendor_credit', 'po_discount', v_a); v_pj := pg_temp.openjob('bill_payment', 'po_payment', pg_temp.id('p3'));
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_r := public.qbo_job_skip(v_vj.id, 'ZZ47B skip the discount credit');
  perform pg_temp.as_user(null);
  v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p3'));
  perform pg_temp.put('s3_before', v_pj.state || ' ' || coalesce(v_r->>'blocked_children', '?'));
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p3'));
  perform pg_temp.chk('S3a 할인 VC Skip(결제는 blocked · blocked_children 1) → 결제 claim: ② 가 풀고 몸이 raise → failed · body_failed 1 · requested failed · 글 「…was skipped — retry that job first, or enter this payment in QuickBooks by hand and press Skip on this job…」',
    pg_temp.id('s3_before') || ' ' || v_pj.state || ' ' || coalesce(v_c->>'body_failed', '?') || ' ' || coalesce(v_c->'requested'->0->>'result', '?') || ' ' || (coalesce(v_pj.last_error, '') like '%early-payment discount of invoice ZZ47B-INV-5 was skipped — retry that job first, or enter this payment in QuickBooks by hand and press Skip on this job%')::text,
    'blocked 1 failed 1 failed true');
  perform pg_temp.as_user(pg_temp.id('st_uid'));
  v_t := pg_temp.try(format($q$select (public.qbo_job_retry(%L::uuid, 'ZZ47B send the discount credit after all'))->>'state'$q$, v_vj.id)) || ' ' || pg_temp.try(format($q$select (public.qbo_job_retry(%L::uuid, 'ZZ47B retry the payment'))->>'state'$q$, v_pj.id));
  perform pg_temp.as_user(null);
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p3'));
  perform pg_temp.chk('S3b 출구: VC 일감 Retry(queued) · 결제 Retry(queued) → 결제 claim: 다시 needs 길(need_jobs 하나 = 그 VC 일감 · blocked) · 열린 할인 VC 일감 하나',
    v_t || ' ' || jsonb_array_length(coalesce(v_c->'need_jobs', '[]'))::text || ' ' || ((v_c->'need_jobs'->0->>'job_id') = v_vj.id::text)::text || ' ' || v_pj.state || ' ' || (select count(*) from public.qbo_job j where j.kind = 'vendor_credit' and j.ims_kind = 'po_discount' and j.ims_id = v_a and j.state not in ('sent', 'skipped'))::text,
    'queued queued 1 true blocked 1');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S3 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S4 Bill 이 아직 안 간 인보이스의 할인 결제 — Bill 만 wait_job · VC 는 needs 에 없다(Bill 은 대신 보내지 않는다 960) ──
do $$
declare v_r jsonb; v_c jsonb; v_t text; v_j jsonb; v_pj public.qbo_job;
begin
  v_r := pg_temp.mkpay('p4', 'cad', 19.6, 'acb', 'ZZ47B-P4', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i6'), 'amount', 20, 'discount', 0.4)), null, 0.4);
  v_pj := pg_temp.openjob('bill_payment', 'po_payment', pg_temp.id('p4'));
  v_t := pg_temp.try(format('select public.qbo_bill_payment_body(%L::uuid)::text', pg_temp.id('p4')));
  if v_t like 'ERR %' then perform pg_temp.chk('S4a Bill 안 간 할인 결제 몸', v_t, 'a body');
  else v_j := v_t::jsonb;
    perform pg_temp.chk('S4a Bill 안 간 할인 결제 몸: needs 0 · wait_job = Bill 일감 · 글 「waiting for bill ZZ47B-INV-6…」 · 할인 VC 일감은 서 있다(queued)',
      jsonb_array_length(coalesce(v_j->'needs', '[]'))::text || ' ' || ((v_j->>'wait_job') = pg_temp.id('bill6'))::text || ' ' || (coalesce(v_j->>'wait_reason', '') like 'waiting for bill ZZ47B-INV-6 to reach QuickBooks first%')::text || ' ' || coalesce((pg_temp.openjob('vendor_credit', 'po_discount', pg_temp.id('p4_a'))).state, '(none)'), '0 true true queued');
  end if;
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p4'));
  perform pg_temp.chk('S4b 그 결제 claim: blocked_for_invoice 1 · blocked_for_needs 0 · need_jobs 0 · blocked_by = Bill 일감',
    coalesce(v_c->>'blocked_for_invoice', '?') || ' ' || coalesce(v_c->>'blocked_for_needs', '?') || ' ' || jsonb_array_length(coalesce(v_c->'need_jobs', '[]'))::text || ' ' || (v_pj.blocked_by::text is not distinct from pg_temp.id('bill6'))::text, '1 0 0 true');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S4 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S5 qbo_job_open_or_add 의 vendor_credit 가지 — 찾아 돌려주기만 · 만들지 않음 · 열린 일감 없으면 raise · 일반 크레딧(po_credit)은 안 돌려줌 · 그 밖 kind 거부 그대로 ──
do $$
declare v_t text; v_n0 bigint; v_cr uuid := gen_random_uuid(); v_vj public.qbo_job;
begin
  select count(*) into v_n0 from public.qbo_job;
  v_vj := pg_temp.openjob('vendor_credit', 'po_discount', pg_temp.id('p4_a'));
  v_t := pg_temp.try(format($q$select (x->>'id') || ' ' || (x->>'existing') || ' ' || (x->>'ims_kind') || ' ' || (x->>'state') from public.qbo_job_open_or_add('vendor_credit', %L, %L::uuid) x$q$, pg_temp.id('p4_a'), pg_temp.id('staff')));
  perform pg_temp.chk('S5a open_or_add(vendor_credit, 붙임 id): 열린 할인 VC 일감을 돌려준다(existing true · po_discount · queued) · 새 일감 0', v_t || ' ' || ((select count(*) from public.qbo_job) - v_n0)::text, v_vj.id::text || ' true po_discount queued 0');
  v_t := pg_temp.try(format($q$select public.qbo_job_open_or_add('vendor_credit', %L, %L::uuid)::text$q$, pg_temp.id('p1_a'), pg_temp.id('staff')));
  perform pg_temp.chk('S5b 열린 일감이 없는 붙임(VC 가 이미 sent): raise 「…has no open QuickBooks job — press Retry on the supplier payment job…」 · 새 일감 0', (v_t like 'ERR %early-payment discount vendor credit has no open QuickBooks job — press Retry on the supplier payment job%')::text || ' ' || ((select count(*) from public.qbo_job) - v_n0)::text, 'true 0');
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (pg_temp.id('realm'), 'vendor_credit', 'po_credit', v_cr::text, 'queued', pg_temp.id('staff')::uuid);
  v_t := pg_temp.try(format($q$select public.qbo_job_open_or_add('vendor_credit', %L, %L::uuid)::text$q$, v_cr, pg_temp.id('staff')));
  perform pg_temp.chk('S5c 일반 공급처 크레딧(po_credit) 일감은 돌려주지 않는다(raise) · bill · invoice kind 거부 그대로',
    (v_t like 'ERR %has no open QuickBooks job%')::text || ' ' || (pg_temp.try(format($q$select public.qbo_job_open_or_add('bill', %L, %L::uuid)::text$q$, pg_temp.id('i1'), pg_temp.id('staff'))) like 'ERR %kind must be customer, item or vendor%')::text
      || ' ' || (pg_temp.try(format($q$select public.qbo_job_open_or_add('invoice', %L, %L::uuid)::text$q$, pg_temp.id('i1'), pg_temp.id('staff'))) like 'ERR %kind must be customer, item or vendor%')::text, 'true true true');
  update public.qbo_job j set state = 'skipped', note = 'ZZ47B fixture' where j.id = (select x.id from public.qbo_job x where x.kind = 'vendor_credit' and x.ims_kind = 'po_credit' and x.ims_id = v_cr::text);
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S5 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;

-- ── S6 회귀 — 할인 없는 결제 · Bill 일감 Skip 은 결제를 풀지 않는다(② 새 가지는 할인 VC 만) · 손 안 댄 함수 md5 ──
do $$
declare v_r jsonb; v_c jsonb; v_t text; v_j jsonb; v_pj public.qbo_job;
begin
  v_r := pg_temp.mkpay('p5', 'cad', 10, 'acb', 'ZZ47B-P5', jsonb_build_array(jsonb_build_object('kind', 'invoice', 'id', pg_temp.id('i7'), 'amount', 10)), null, 0);
  v_pj := pg_temp.openjob('bill_payment', 'po_payment', pg_temp.id('p5'));
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_j := v_c->'jobs'->0;
  perform pg_temp.chk('S6a 할인 없는 결제 claim(4-5a 꼴): claimed 1 · need_jobs 0 · TotalAmt 10 · 줄 하나 Bill zz7bb7 10 · check_lines 하나(qbo_bill_id 그대로) · 경고 없음 · po_discount 일감 0',
    coalesce(v_c->>'claimed', '?') || ' ' || jsonb_array_length(coalesce(v_c->'need_jobs', '[]'))::text || ' ' || coalesce(v_j->'body'->>'TotalAmt', '?') || ' ' || jsonb_array_length(coalesce(v_j->'body'->'Line', '[]'))::text || ' ' || coalesce(v_j->'body'->'Line'->0->'LinkedTxn'->0->>'TxnType', '?') || ' ' || coalesce(v_j->'body'->'Line'->0->'LinkedTxn'->0->>'TxnId', '?')
      || ' ' || coalesce(v_j->'check_lines'->0->>'qbo_bill_id', '?') || ' ' || jsonb_array_length(coalesce(v_j->'warnings', '[]'))::text || ' ' || (select count(*) from public.qbo_job j where j.ims_kind = 'po_discount' and j.ims_id = pg_temp.id('p5_a'))::text, '1 0 10 1 Bill zz7bb7 zz7bb7 0 0');
  update public.qbo_job j set state = 'skipped', note = 'ZZ47B fixture — bill skipped' where j.id = pg_temp.id('bill6')::uuid;
  v_pj := pg_temp.openjob('bill_payment', 'po_payment', pg_temp.id('p4'));
  v_c := pg_temp.claim1(v_pj.id, 'bill_payment'); v_pj := pg_temp.job('bill_payment', 'po_payment', pg_temp.id('p4'));
  perform pg_temp.chk('S6b Bill 일감이 skipped 인 결제(S4)는 풀리지 않는다 — ② 의 새 가지는 할인 VC 부모만: claimed 0 · blocked 그대로', coalesce(v_c->>'claimed', '?') || ' ' || v_pj.state || ' ' || (v_pj.blocked_by::text is not distinct from pg_temp.id('bill6'))::text, '0 blocked true');
exception when others then perform pg_temp.as_user(null); perform pg_temp.chk('S6 (멈춤)', sqlstate || ': ' || sqlerrm, 'no error');
end $$;
select pg_temp.chk('S6c 손 안 댄 함수 열둘 md5 = begin 앞(skip · preview · retry · done · 할인 VC 몸 · sync · 결제 sync · void 몸 · 지문 · 크레딧 몸 · Bill 몸 · 결제 창구)',
  ((select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_skip', 'qbo_job_preview', 'qbo_job_retry', 'qbo_job_done', 'qbo_discount_credit_body', 'qbo_discount_credit_sync', 'qbo_bill_payment_sync', 'qbo_bill_payment_void_body', 'qbo_bill_payment_fingerprint', 'qbo_vendor_credit_body', 'qbo_bill_body', 'po_payment_create')) = :'pre_md5_same')::text, 'true');

-- ── W REST 두 겹 ① — 재발행 셋의 update · delete 깊이 0 WHERE(claim 은 service_role 이 REST 로 부른다) ──
select pg_temp.chk('W1 재발행 셋: WHERE 없는 update · delete 0',
  (select coalesce(string_agg(p.proname || ':' || pg_temp.nowhere(p.prosrc)::text, ' ' order by p.proname) filter (where pg_temp.nowhere(p.prosrc) > 0), 'none') || ' ' || count(*)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_bill_payment_body', 'qbo_job_open_or_add', 'qbo_job_claim')), 'none 3');

-- ── G 착지 ──
select pg_temp.chk('G1 재발행 셋의 prosrc md5 = 마이그레이션이 박은 값',
  (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_payment_body', 'qbo_job_open_or_add', 'qbo_job_claim')),
  'qbo_bill_payment_body:a109cb3b12572f1b8e530a885e949639 qbo_job_claim:9ab3a4d8fc92fa8fcc00cff9ccf77dcb qbo_job_open_or_add:29a2a12c43412e15a61a4d120463e661');
select pg_temp.chk('G2 같은 이름 하나씩 · 실행권 · definer · volatile · 시그니처 = begin 앞 그대로',
  (select count(*)::text from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_payment_body', 'qbo_job_open_or_add', 'qbo_job_claim')) || ' '
    || ((select string_agg(proname || ':' || coalesce(proacl::text, '') || ':' || prosecdef::text || ':' || provolatile::text || ':' || pg_get_function_identity_arguments(oid), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_payment_body', 'qbo_job_open_or_add', 'qbo_job_claim')) = :'pre_three_shape')::text, '3 true');

-- ── Z 실제 행 무변(트랜잭션 안 · begin 앞에 있던 행만) ──
select pg_temp.chk('Z1 실제 행 무변: 인보이스 · 결제 · 붙임 · 일감 — begin 앞 지문 그대로 · 실제 qbo_txn 수 그대로',
  ((select md5(coalesce(string_agg(md5(to_jsonb(i)::text), ',' order by i.id), '')) from public.po_invoice i where i.invoice_number not like 'ZZ47B-%') = :'pre_inv_md5')::text
    || ' ' || ((select md5(coalesce(string_agg(md5(to_jsonb(p)::text), ',' order by p.id), '')) from public.po_payment p where coalesce(p.reference, '') not like 'ZZ47B-%') = :'pre_pay_md5')::text
    || ' ' || ((select md5(coalesce(string_agg(md5(to_jsonb(a)::text), ',' order by a.id), '')) from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id where coalesce(p.reference, '') not like 'ZZ47B-%') = :'pre_alloc_md5')::text
    || ' ' || ((select md5(coalesce(string_agg(md5(to_jsonb(j)::text), ',' order by j.id), '')) from public.qbo_job j where j.created_at < :'t_begin'::timestamptz) = :'pre_job_md5')::text
    || ' ' || ((select count(*) from public.qbo_txn t where t.qbo_id not like 'zz7b%') = :pre_txn)::text, 'true true true true true');

-- ── 결과(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select case when ok then 'OK   ' else 'FAIL ' end || label || case when ok then '' else format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) end as line from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, :EXPECT_OK as expect_ok from t_res;
select (count(*) filter (where not ok) > 0 or count(*) filter (where ok) <> :EXPECT_OK) as has_fail from t_res \gset
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
select (select count(*) from public.po_invoice) = :pre_inv and (select count(*) from public.po_payment) = :pre_pay and (select count(*) from public.po_payment_alloc) = :pre_alloc and (select count(*) from public.qbo_job) = :pre_jobs and (select count(*) from public.qbo_txn) = :pre_txn
   and (select count(*) from public.supplier) = :pre_sup and (select count(*) from public.ims_staff) = :pre_staff and (select count(*) from public.inv_cost_adjust) = :pre_adj
   and (select string_agg(proname || ':' || md5(prosrc), ' ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_bill_payment_body', 'qbo_job_open_or_add', 'qbo_job_claim')) = :'pre_three_md5' as rolled_back_clean;
\if :has_fail
do $$ begin raise exception 'qbo_sync_4_7b_check: FAIL (or OK count <> EXPECT_OK) — see the lines above'; end $$;
\endif
