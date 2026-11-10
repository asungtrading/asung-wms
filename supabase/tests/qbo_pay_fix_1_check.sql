-- supabase/tests/qbo_pay_fix_1_check.sql — qbo-pay-fix-1 검증 (2026-11-09 밤 토론토 · deferred 540 · §0 이견 1 ~ 7 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i) → 가짜 재료(DO 하나) → S1 결함 ① + 실제 흐름(되돌림 → 다시 바꿈 → void → 다시 보냄) · S2 결함 ②(닫힌 void 뒤에 남은 일감) · S3 결제 지움 → void 만 · S4 안 나간 일감 skip · G 구조 · W1 REST WHERE · C 운영 1 건 → 집계 → rollback → 실패면 raise
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261110023000_qbo_pay_fix_1_payment_sync_orphan_resend.sql -f supabase/tests/qbo_pay_fix_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다)
--   마른 실행(적용 전 · -v mig 없이 = 옛 함수): 결함이 FAIL 로 잡히고 exit 3 — 기대 OK 11 · FAIL 11(S1c · S1d · S1e · S1f · S2b · S2c · S2d · G1 · G4 · C1 · C2) · 실측 2026-11-10 UTC · begin → rollback 4.4 초(시험 적용 6.4 초)
--   ⚠️ 가짜 재료만(직원 f1f1f1f1-… · 손님 c3f10000-… · 제품 ZZPF1-001 · 인보이스 9971001 ~ 6 · 결제 넷) — 실제 행은 읽기만 · 시험 갈래에서 마이그레이션이 운영 일감 하나를 푸는 것은 마이그레이션의 몫(rollback) · ⚠️ claim 은 늘 일감 id 로만(id 없이 부르면 운영의 queued 일감을 잡는다) · QBO 호출 0 · 상호를 찍지 않는다
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 22
\else
\set EXPECT_OK 22
\endif
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%');
create temp table t_ids (k text primary key, v text);
insert into t_ids values ('realm', (select realm_id from public.qbo_connection where singleton)), ('tor', (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.')), ('today', public.ims_today()::text);
select (select value from public.inv_config where key = 'db_role') as db_role, (select count(*) from t_pre) as n_fn, (select md5 from t_pre where proname = 'qbo_payment_sync') as pre_sync_md5,
       (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0, (select count(*) from public.so) as n_so0, (select count(*) from public.so_invoice) as n_inv0,
       (select count(*) from public.so_payment) as n_pay0, (select count(*) from public.so_payment_alloc) as n_alloc0, (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_txn) as n_txn0, (select count(*) from public.qbo_link) as n_link0,
       (select j.state from public.qbo_job j where j.id = 'a5bd4e28-caf3-4012-afa6-c7b337c8bc44') as pre_stuck_state \gset
\echo '── 기준: db_role' :db_role '· 함수' :n_fn '· qbo_payment_sync' :pre_sync_md5 '· job' :n_job0 '· txn' :n_txn0 '· 운영 일감 a5bd4e28' :pre_stuck_state
-- 도우미는 begin 앞(임시 객체 · 실제 행 0) — 이 DB 는 문장마다 왕복 ≈ 0.3 초라 트랜잭션 안 문장 수를 줄인다(잠금 10 초 안)
create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns void language sql as $$ insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want); $$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.bk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"f1f1f1f1-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
-- 결제 하나의 일감 꼴: kind:state[>부모 kind:state] 를 글자 순으로(같은 트랜잭션이라 created_at 순서에 기대지 않는다) · p_open 이면 열린 것만
create function pg_temp.st(p_pay text, p_open boolean default false) returns text language sql as $$
  select coalesce(string_agg(x.s, ',' order by x.s collate "C"), '(none)') from (
    select j.kind || ':' || j.state || coalesce('>' || (select b.kind || ':' || b.state from public.qbo_job b where b.id = j.blocked_by), '') as s
      from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id = p_pay and (not p_open or j.state not in ('sent', 'skipped'))) x
$$;
create function pg_temp.inv(p_n int) returns text language sql as $$ select '13f10000-0000-4000-8000-00000000000' || p_n::text $$;
create function pg_temp.pay_add(p_amount numeric, p_inv int, p_alloc numeric, p_ref text) returns text language sql as $$
  select pg_temp.bk(format($q$ select (public.so_payment_add(%L::jsonb))->>'payment_id' $q$, jsonb_build_object('customer_id', 'c3f10000-0000-4000-8000-00000000000a', 'amount', p_amount, 'method', 'cheque', 'reference', p_ref, 'currency_code', 'CAD', 'warehouse_id', pg_temp.id('tor'),
    'allocations', jsonb_build_array(jsonb_build_object('invoice_id', pg_temp.inv(p_inv), 'amount', p_alloc)))::text))
$$;
create function pg_temp.attach(p_pay text, p_inv int, p_amount numeric) returns text language sql as $$
  select pg_temp.bk(format($q$ select (public.so_payment_attach(%L, %L::jsonb))->>'payment_id' $q$, p_pay, jsonb_build_array(jsonb_build_object('invoice_id', pg_temp.inv(p_inv), 'amount', p_amount))::text))
$$;
create function pg_temp.detach(p_pay text, p_inv int) returns text language sql as $$
  select pg_temp.bk(format($q$ select (public.so_payment_detach(%L, 'pay-fix-1 test'))->>'payment_id' $q$, (select a.id from public.so_payment_alloc a where a.payment_id = p_pay::uuid and a.invoice_id = pg_temp.inv(p_inv)::uuid and a.voided_at is null limit 1)))
$$;
-- 보내기 흉내: 그 결제의 열린 일감 하나(kind)를 **id 로** claim → sending 이면 done · 돌려주는 글 = claimed · done state · done 이 푼 수(못 잡으면 그 까닭)
create function pg_temp.send(p_kind text, p_pay text, p_qbo_id text, p_token text, p_total numeric default null, p_unapplied numeric default null) returns text language plpgsql as $$
declare v_id uuid; v_c text; v_d text; v_state text;
begin
  select j.id into v_id from public.qbo_job j where j.kind = p_kind and j.ims_kind = 'payment' and j.ims_id = p_pay and j.state in ('queued', 'blocked');
  if v_id is null then return 'no open ' || p_kind || ' job'; end if;
  v_c := pg_temp.svc(format($q$ select public.qbo_job_claim(50, array['payment', 'payment_void'], array[%L]::uuid[])::text $q$, v_id));
  select j.state into v_state from public.qbo_job j where j.id = v_id;
  if v_state <> 'sending' then return 'not claimed: job is ' || v_state; end if;
  if p_kind = 'payment' then v_d := pg_temp.svc(format('select public.qbo_job_done(%L, %L, %L, %L, %L, null, null, %s, null, %s)::text', v_id, p_qbo_id, 'ZZPF1', p_token, 'tid-' || p_qbo_id, p_total, p_unapplied));
  else v_d := pg_temp.svc(format('select public.qbo_job_done(%L, %L, %L, %L, %L, null, null)::text', v_id, p_qbo_id, 'ZZPF1', p_token, 'tid-v-' || p_qbo_id)); end if;
  if v_d like 'ERR %' then return v_d; end if;
  return 'claimed ' || (v_c::jsonb->>'claimed') || ' · ' || (v_d::jsonb->>'state') || ' · unblocked ' || coalesce(v_d::jsonb->>'unblocked', '-');
end $$;
create function pg_temp.txn(p_pay text) returns text language sql as $$
  select coalesce((select t.qbo_id || ' voided ' || (t.voided_at is not null)::text || ' fp_same ' || (t.fingerprint is not distinct from public.qbo_payment_fingerprint(p_pay::uuid))::text from public.qbo_txn t where t.ims_kind = 'payment' and t.ims_id = p_pay), '(no txn)')
$$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
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
end $$;
create temp sequence s_so start 99950;
create function pg_temp.mk_inv(p_id uuid, p_num text, p_kind text, p_bill uuid, p_bill_name text, p_on date, p_cust uuid[]) returns void language plpgsql as $$
declare i int; v_oid uuid; v_so uuid; v_sl uuid; v_num text; v_n int := coalesce(array_length(p_cust, 1), 0); v_prod uuid := 'd3f10000-0000-4000-8000-000000000001';
begin
  insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, store_customer_id, legacy_sale_id, legacy_invoice_id, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due)
  values (p_id, p_num, p_kind, 'issued', p_bill, p_bill_name, '1 Any St', 'Toronto', 'ON', 'M1M 1M1', 'CA', p_on, case when p_kind = 'sale' then 'f1f1f1f1-0000-4000-8000-00000000000a'::uuid end, coalesce(p_cust[1], p_bill), case when p_kind = 'opening' then 'test-sale-' || p_num end, case when p_kind = 'opening' then 'test-inv-' || p_num end, (select id from public.ref_currency where code = 'CAD'), 'CAD', 10 * greatest(v_n, 1), 10 * greatest(v_n, 1), 0, 10 * greatest(v_n, 1), 10 * greatest(v_n, 1));
  for i in 1 .. v_n loop
    v_so := gen_random_uuid(); v_sl := gen_random_uuid(); v_oid := gen_random_uuid(); v_num := 'SO-' || nextval('s_so')::text;
    insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_country)
    values (v_so, v_num, p_cust[i], p_bill, 'pos', 'manual', (select id from public.ref_currency where code = 'CAD'), 'CAD', p_on, 'PO-' || v_num, now(), 'Ship', '5 St', 'Toronto', 'CA');
    insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, unit_price) values (v_sl, v_so, 1, v_prod, 'ZZPF1-001', 'ZZPF1 Widget', 1, 1, 1, 10);
    insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, taxable_amount, tax_amount, total)
    values (v_oid, p_id, v_so, v_num, p_cust[i], 'Ship', '5 St', 'Toronto', 'CA', (select id from public.ref_tax_rule where name = 'HST ON (Sale)'), 'HST ON (Sale)', 0, 'ship_to', 10, 10, 0, 10);
    insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_code) values (p_id, v_oid, i, 'product', v_sl, 'ZZPF1-001', 'ZZPF1 Widget', 1, 10, 10, 0, '_98_');
  end loop;
end $$;
-- INV1 A sale(일감 queued · 결제가 기다림) · INV2 A sale(보내진 셈 · txn) · INV3 K 매장 · 청구처 P sale(txn · 980) · INV4 A opening(이월 · 짝 없음) · INV5 A sale since 전(10-31)

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset
-- ── 가짜 재료: 직원 1 · 손님 1(짝 있음) · 제품 1 · 인보이스 여섯(1 은 안 나감 · 2 ~ 6 은 보내진 셈) ──
do $$
declare i int; v_realm text := pg_temp.id('realm');
begin
  if v_realm is null or pg_temp.id('tor') is null then raise exception 'fixture: realm or warehouse is missing'; end if;
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values ('f1f1f1f1-0000-4000-8000-00000000000a', 'f1f1f1f1-0000-4000-8000-000000000001', 'qbo-pay-fix-1@asung.invalid', 'ZZPF1 Bookkeeper', 'manager', '["qbo", "sales"]');
  insert into public.customer (id, name, is_active, source, currency_code) values ('c3f10000-0000-4000-8000-00000000000a', 'ZZPF1 Store A', true, 'manual', 'CAD');
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values (v_realm, 'customer', 'c3f10000-0000-4000-8000-00000000000a', 'Customer', 'C-ZZPF1-A', 'manual', 'ZZPF1 Store A');
  insert into public.product (id, name, sku, is_active, source, sellable, revenue_account_code) values ('d3f10000-0000-4000-8000-000000000001', 'ZZPF1 Widget', 'ZZPF1-001', true, 'manual', true, '_98_');
  for i in 1 .. 6 loop
    perform pg_temp.mk_inv(pg_temp.inv(i)::uuid, '997100' || i::text, 'sale', 'c3f10000-0000-4000-8000-00000000000a', 'ZZPF1 Store A', pg_temp.id('today')::date, array['c3f10000-0000-4000-8000-00000000000a'::uuid]);
  end loop;
end $$;
set constraints all immediate;
do $$
declare i int; v_realm text := pg_temp.id('realm');
begin
  for i in 2 .. 6 loop
    update public.qbo_job set state = 'sent', qbo_id = 'INV-ZZPF1-' || i::text, qbo_name = '997100' || i::text, sent_at = now() where ims_id = pg_temp.inv(i) and kind = 'invoice';
    insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, sent_at) values (v_realm, 'invoice', pg_temp.inv(i), 'Invoice', 'INV-ZZPF1-' || i::text, '997100' || i::text, '0', 10, 0, now());
  end loop;
  perform pg_temp.chk('F0 가짜 재료: 인보이스 일감 여섯 — 1 queued · 2 ~ 6 sent', (select string_agg(j.state, ',' order by j.ims_id) from public.qbo_job j where j.kind = 'invoice' and j.ims_id like '13f10000-0000-4000-8000-%'), 'queued,sent,sent,sent,sent,sent');
end $$;

-- ── S1 결함 ① + 운영에서 실제로 난 흐름: 보냄 → 붙임 더함(void + 다시 보내기) → 그 붙임 뗌(지문 = QBO) → 다시 더함 → void 나감 → 다시 보내기 나감 ──
do $$
declare p text;
begin
  p := pg_temp.pay_add(20, 2, 10, 'ZZPF1-P1'); perform pg_temp.put('p1', p);
  perform pg_temp.chk('S1a 새 결제(20 · 10 → 인보이스 2): payment 일감 queued → id 로 claim · done → sent · qbo_txn 지문 = 지금 지문', pg_temp.st(p) || ' | ' || pg_temp.send('payment', p, 'PAY-ZZPF1-1', '0', 20, 10) || ' | ' || pg_temp.st(p) || ' | ' || pg_temp.txn(p),
    'payment:queued | claimed 1 · sent · unblocked 0 | payment:sent | PAY-ZZPF1-1 voided false fp_same true');
  perform pg_temp.attach(p, 3, 5);
  perform pg_temp.chk('S1b 붙임 더함(5 → 인보이스 3 · 지문 ≠ QBO): void queued + 다시 보내기 blocked(그 void 뒤)', pg_temp.st(p), 'payment:blocked>payment_void:queued,payment:sent,payment_void:queued');
  perform pg_temp.detach(p, 3);
  perform pg_temp.chk('S1c ⭐ 결함 ① — 그 붙임 뗌(지문 = QBO 그대로): 안 나간 void skipped + 그 뒤 다시 보내기도 skipped · 열린 일감 0(옛 함수: payment:blocked>payment_void:skipped 가 남는다)', pg_temp.st(p) || ' | ' || pg_temp.st(p, true) || ' | ' || pg_temp.txn(p),
    'payment:sent,payment:skipped,payment_void:skipped | (none) | PAY-ZZPF1-1 voided false fp_same true');
  perform pg_temp.chk('S1d ⭐ 거둔 다시 보내기 일감의 note 「nothing to send again」', (select coalesce(bool_or(j.note like '%restored to what QuickBooks has — nothing to send again%'), false)::text from public.qbo_job j where j.ims_id = p and j.kind = 'payment' and j.state = 'skipped'), 'true');
  perform pg_temp.attach(p, 3, 5);
  perform pg_temp.chk('S1e ⭐ 다시 더함(지문 ≠ QBO): 새 void queued + 다시 보내기가 그 새 void 뒤(옛 함수: 거둔 void 뒤에 그대로)', pg_temp.st(p, true), 'payment:blocked>payment_void:queued,payment_void:queued');
  perform pg_temp.chk('S1f ⭐ 새 void 나감(done 이 뒤 일감을 푼다) → 다시 보내기 나감 → 열린 일감 0 · QBO 새 Payment · 지문 = 지금 지문(옛 함수: QBO 쪽은 void 인데 다시 보내기는 blocked)',
    pg_temp.send('payment_void', p, 'PAY-ZZPF1-1', '1') || ' | ' || pg_temp.send('payment', p, 'PAY-ZZPF1-1B', '0', 20, 5) || ' | ' || pg_temp.st(p, true) || ' | ' || pg_temp.txn(p),
    'claimed 1 · sent · unblocked 1 | claimed 1 · sent · unblocked 0 | (none) | PAY-ZZPF1-1B voided false fp_same true');
end $$;

-- ── S2 결함 ② — 다시 보내기가 「닫힌 void」 뒤에 남아 있을 때(사람이 void 를 Skip 한 꼴을 가짜 일감에 직접 흉내) 결제가 또 바뀌면 새 void 뒤로 옮긴다 ──
do $$
declare p text; v_v1 uuid;
begin
  p := pg_temp.pay_add(20, 4, 10, 'ZZPF1-P2'); perform pg_temp.put('p2', p);
  perform pg_temp.send('payment', p, 'PAY-ZZPF1-2', '0', 20, 10);
  perform pg_temp.attach(p, 5, 5);
  select j.id into v_v1 from public.qbo_job j where j.ims_id = p and j.kind = 'payment_void' and j.state = 'queued';
  update public.qbo_job j set state = 'skipped', note = 'pay-fix-1 test: skipped by a person' where j.id = v_v1 and j.ims_id = p;
  perform pg_temp.chk('S2a 준비: 보냄 → 붙임 더함 → 가짜 void 를 skipped 로(뒤 일감은 남는다 · 새 deferred 의 꼴)', pg_temp.st(p), 'payment:blocked>payment_void:skipped,payment:sent,payment_void:skipped');
  perform pg_temp.attach(p, 3, 2);
  perform pg_temp.chk('S2b ⭐ 결함 ② — 결제가 또 바뀜(2 → 인보이스 3): 새 void queued · blocked 다시 보내기가 그 새 void 뒤로 옮겨짐 · note 「waits for the void」(옛 함수: 닫힌 void 뒤에 그대로)',
    pg_temp.st(p, true) || ' | ' || (select coalesce(bool_or(j.note like '%waits for the void of the earlier QuickBooks payment%'), false)::text from public.qbo_job j where j.ims_id = p and j.kind = 'payment' and j.state = 'blocked'), 'payment:blocked>payment_void:queued,payment_void:queued | true');
  perform pg_temp.chk('S2c ⭐ 새 void 나감 → 다시 보내기 풀려 나감 → 열린 일감 0 · 지문 = 지금 지문',
    pg_temp.send('payment_void', p, 'PAY-ZZPF1-2', '1') || ' | ' || pg_temp.send('payment', p, 'PAY-ZZPF1-2B', '0', 20, 3) || ' | ' || pg_temp.st(p, true) || ' | ' || pg_temp.txn(p),
    'claimed 1 · sent · unblocked 1 | claimed 1 · sent · unblocked 0 | (none) | PAY-ZZPF1-2B voided false fp_same true');
  perform pg_temp.attach(p, 6, 1);
  perform pg_temp.chk('S2d 회귀 — 보통의 바꿈(열린 일감 없음 → 1 → 인보이스 6: void queued + 다시 보내기 blocked) → 그 붙임 뗌(지문 = QBO): 둘 다 거둬 열린 일감 0 · QBO Payment 그대로',
    pg_temp.st(p, true) || ' | ' || (pg_temp.detach(p, 6) = p)::text || ' | ' || pg_temp.st(p, true) || ' | ' || pg_temp.txn(p), 'payment:blocked>payment_void:queued,payment_void:queued | true | (none) | PAY-ZZPF1-2B voided false fp_same true');
end $$;

-- ── S3 결제 지움(떼고 void) → void 만 · S4 안 나간 일감은 skip ──
do $$
declare p text; q text;
begin
  p := pg_temp.pay_add(10, 6, 5, 'ZZPF1-P3'); perform pg_temp.put('p3', p);
  perform pg_temp.send('payment', p, 'PAY-ZZPF1-3', '0', 10, 5);
  perform pg_temp.detach(p, 6);
  perform pg_temp.chk('S3a 보낸 결제의 붙임을 모두 뗌(지문 null): void 만 queued · 다시 보내기 없음', pg_temp.st(p), 'payment:sent,payment_void:queued');
  perform pg_temp.bk(format($q$ select (public.so_payment_void(%L, 'pay-fix-1 test void'))->>'payment_id' $q$, p));
  perform pg_temp.chk('S3b 결제 취소: 일감 그대로(void 하나) · 결제 voided · void 나감 → 열린 일감 0 · QBO 쪽 void', pg_temp.st(p) || ' | ' || (select s.status from public.so_payment s where s.id = p::uuid) || ' | ' || pg_temp.send('payment_void', p, 'PAY-ZZPF1-3', '1') || ' | ' || pg_temp.st(p, true) || ' | ' || pg_temp.txn(p),
    'payment:sent,payment_void:queued | voided | claimed 1 · sent · unblocked 0 | (none) | PAY-ZZPF1-3 voided true fp_same false');
  q := pg_temp.pay_add(3, 1, 3, 'ZZPF1-P4'); perform pg_temp.put('p4', q);
  perform pg_temp.chk('S4a 안 나간 인보이스(1)에 붙인 결제: 일감 queued → claim 은 인보이스 뒤로 세운다(blocked)', pg_temp.st(q) || ' | ' || pg_temp.send('payment', q, 'PAY-ZZPF1-4', '0', 3, 0) || ' | ' || pg_temp.st(q), 'payment:queued | not claimed: job is blocked | payment:blocked>invoice:queued');
  perform pg_temp.detach(q, 1);
  perform pg_temp.chk('S4b 보내기 전에 붙임을 뗌: 안 나간 일감 skipped(「before sending」) · void 일감 없음 · txn 없음', pg_temp.st(q) || ' | ' || (select coalesce(bool_or(j.note like '%before sending%'), false)::text from public.qbo_job j where j.ims_id = q and j.kind = 'payment') || ' | ' || pg_temp.txn(q), 'payment:skipped | true | (no txn)');
end $$;

-- ── G 구조 · W1 REST WHERE · C 운영 1 건 ──
select pg_temp.chk('G1 qbo_payment_sync 몸 md5 = 새 몸 · 같은 이름 하나 · 시그니처 · ACL · definer · search_path 그대로',
  (select md5(p.prosrc) || ' ' || (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'qbo_payment_sync')::text || ' ' || pg_get_function_identity_arguments(p.oid) || ' ' || coalesce(p.proacl::text, '-') || ' ' || p.prosecdef::text || ' ' || p.proconfig::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_payment_sync'),
  '12492822dfb7755effd4ac027eee0e99 1 p_payment_id uuid, p_by uuid {postgres=X/postgres} true {"search_path=public, pg_temp"}'),
  pg_temp.chk('G2 공급처 결제 맞추기(qbo_bill_payment_sync) 무변 md5', (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_bill_payment_sync'), '416ded93ca8bfbb99045896dbdf4f7b1'),
  pg_temp.chk('G4 고친 두 곳이 몸에 있다(① 거둘 때 뒤 일감 · ② blocked 도 옮김) · 옛 줄 「in (queued, failed) then」 없음',
  (select (p.prosrc like '%nothing to send again%')::text || ' ' || (p.prosrc like '%in (''queued'', ''failed'', ''blocked'') and v_pj.blocked_by is distinct from v_vid then%')::text || ' ' || (p.prosrc not like '%in (''queued'', ''failed'') then%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_payment_sync'), 'true true true'),
  pg_temp.chk('W1 REST 겹 ① — 재발행 함수의 깊이 0 WHERE 없는 update · delete = 0', (select pg_temp.nowhere(p.prosrc)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_payment_sync'), '0'),
  pg_temp.chk('C1 운영: 닫힌(skipped) payment_void 뒤에 blocked 로 남은 실제 payment 일감 = 0(가짜 제외)',
  (select count(*)::text from public.qbo_job j join public.qbo_job p on p.id = j.blocked_by where j.kind = 'payment' and j.state = 'blocked' and p.kind = 'payment_void' and p.state = 'skipped' and j.ims_id not in (select v from t_ids)), '0');
\if :{?mig}
select pg_temp.chk('G3(시험 갈래) begin 앞과 md5 가 다른 qbo_ · so_ 함수 = qbo_payment_sync 하나 · 옛 몸 md5 · 함수 수 무변',
  (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5) || ' ' || :'pre_sync_md5' || ' ' || ((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%')) = :n_fn)::text,
  'qbo_payment_sync 9efb5d9f6007048692d13cd00623c4b8 true');
\else
select pg_temp.chk('G3(확인 갈래) begin 앞과 md5 가 다른 qbo_ · so_ 함수 없음 · 함수 수 무변',
  (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5) || ' ' || ((select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'qbo\_%' or p.proname like 'so\_%')) = :n_fn)::text, '(none) true');
\endif
\if :{?mig}
select pg_temp.chk('C2(시험 갈래) 운영 일감 a5bd4e28: begin 앞 blocked → queued · blocked_by null · note 「released by qbo-pay-fix-1」 · 그 결제의 다른 일감 무변(sent 2 · skipped 1)',
  :'pre_stuck_state' || ' → ' || (select j.state || ' ' || (j.blocked_by is null)::text || ' ' || (j.note like '%released by qbo-pay-fix-1%')::text from public.qbo_job j where j.id = 'a5bd4e28-caf3-4012-afa6-c7b337c8bc44')
  || ' | ' || (select string_agg(x.s, ',' order by x.s collate "C") from (select j.kind || ':' || j.state as s from public.qbo_job j where j.ims_kind = 'payment' and j.ims_id = '15e70a27-36da-4240-bb9b-047f6b8a70e3' and j.id <> 'a5bd4e28-caf3-4012-afa6-c7b337c8bc44') x),
  'blocked → queued true true | payment:sent,payment_void:sent,payment_void:skipped');
\else
select pg_temp.chk('C2(확인 갈래) 운영 일감 a5bd4e28 은 더는 blocked 가 아니다(queued · sending · sent 가운데 하나) · note 「released by qbo-pay-fix-1」',
  (select (j.state in ('queued', 'sending', 'sent'))::text || ' ' || coalesce(j.note like '%released by qbo-pay-fix-1%', false)::text from public.qbo_job j where j.id = 'a5bd4e28-caf3-4012-afa6-c7b337c8bc44'), 'true true');
\endif

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select n, case when ok then 'OK  ' else 'FAIL' end as r, label, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' · want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, (count(*) filter (where not ok) > 0 or count(*) filter (where ok) <> :EXPECT_OK) as bad from t_res \gset
\echo 'OK' :ok '· FAIL' :fail '· total' :total '· expect_ok' :EXPECT_OK
select round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 and (select count(*) from public.customer) = :n_cust0 and (select count(*) from public.product) = :n_prod0 and (select count(*) from public.so) = :n_so0 and (select count(*) from public.so_invoice) = :n_inv0
   and (select count(*) from public.so_payment) = :n_pay0 and (select count(*) from public.so_payment_alloc) = :n_alloc0 and (select count(*) from public.qbo_job) = :n_job0 and (select count(*) from public.qbo_txn) = :n_txn0 and (select count(*) from public.qbo_link) = :n_link0
   and (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_payment_sync') = :'pre_sync_md5'
   and (select j.state from public.qbo_job j where j.id = 'a5bd4e28-caf3-4012-afa6-c7b337c8bc44') is not distinct from :'pre_stuck_state' as rolled_back_clean;
\if :bad
do $$ begin raise exception 'qbo_pay_fix_1_check: FAIL or OK count differs from EXPECT_OK — see the result table above'; end $$;
\endif
