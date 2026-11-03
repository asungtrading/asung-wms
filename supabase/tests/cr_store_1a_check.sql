-- supabase/tests/cr_store_1a_check.sql — cr-store-1a 검증: 매장 열쇠 둘(1030) · 문(1010 · 1022′ · 이견 3) · 계획(1026′ · 이견 5) · 발행 매장(1031 · 1032 · 이견 1 · 4) · Attach 후보(1033 의 한 곳) · 환불 갈래 무변(1025′) · so_invoice_issue 무변
-- [메인 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback → 시퀀스 되돌림(이견 8 답) → 실제 행 무변 · ⚠️ begin ~ rollback 10 초 안
--   Claude Code(시험): MIG=supabase/migrations/20261103090000_cr_store_1a_credit_store.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/cr_store_1a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만) · L2(시험만) · 기대 OK 수는 아래 EXPECT_OK
--   쓰기: 가짜 직원 1(manager · sales) · 실물 손님(Regina 본사 · BRTB · MSG · DT · Rex Warehouse 본사 · Alicer) 아래 가짜 오더 6 · 인보이스 6(번호 99901xx · 시퀀스 무접촉) · 크레딧 4(CR-9993x 명시) · 환불 결제 2 · so_credit_issue commit 1(번호 시퀀스 1 소모 → 끝에서 되돌림) · 전부 rollback
--   ⚠️ 잠그는 실물 행: customer Regina Beauty Inc. · Alicer Express Inc.(so_credit_issue 136 행 for update — 미리 보기도 잠근다) · 그 밖은 가짜 행만 · 숫자는 적지 않고 파일 안에서 센다(이견 6)
--   REST 두 겹: ① L1 nowhere 스캐너(새 2 · 재발행 4 의 update · delete 깊이 0 WHERE) ② 적용 뒤 so-credits 상세의 Attach 후보 한 번(Caleb)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 28
\else
\set EXPECT_OK 27
\endif
\pset pager off
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5, p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.proname like 'so\_credit%' or p.proname like 'so\_invoice%' or p.proname like 'so\_payment%' or p.proname like 'so\_customer\_balance%');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.so) as n_so0,
       (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.so_credit) as n_cr0, (select count(*) from public.so_credit_alloc) as n_alloc0, (select count(*) from public.so_payment) as n_pay0,
       (select id::text from public.ref_currency where code = 'CAD') as cad_id,
       (select id::text from public.ref_tax_rule where name = 'HST ON (Sale)') as hst_id,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh_id,
       (select id::text from public.ref_account where code = '_6_') as a6, (select id::text from public.ref_account where code = '_99_') as a99,
       (select id::text from public.customer where name = 'Regina Beauty Inc.') as regina,
       (select id::text from public.customer where name = 'Regina Beauty Inc.-BRTB') as brtb,
       (select id::text from public.customer where name = 'Regina Beauty Inc.-MSG') as msg,
       (select id::text from public.customer where name = 'Regina Beauty Inc.-DT') as dt,
       (select id::text from public.customer where name = 'Rex Beauty Inc.-Warehouse') as rex,
       (select id::text from public.customer where name = 'Alicer Express Inc.') as alicer,
       (select last_value from public.so_credit_number_seq) as cr_seq_last, (select is_called::text from public.so_credit_number_seq) as cr_seq_called,
       (select coalesce(max(credit_number), '') from public.so_credit) as cr_max0 \gset
\echo '── 기준: 함수' :n_fn '· staff' :n_staff0 '· customer' :n_cust0 '· so' :n_so0 '· invoice' :n_inv0 '· credit' :n_cr0 '· alloc' :n_alloc0 '· payment' :n_pay0 '· CR seq' :cr_seq_last :cr_seq_called '· max' :cr_max0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
select (to_regproc('public.so_invoice_store') is not null)::text as landed \gset
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin
    execute p_sql into v;
  exception when others then
    v := 'ERR ' || sqlstate || ': ' || sqlerrm;
  end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
create function pg_temp.mgw(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"b2c50000-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.pg(p_sql text) returns text language sql as $$ select pg_temp.as_conn('postgres', null, p_sql) $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.cname(p uuid) returns text language sql as $$ select c.name from public.customer c where c.id = p $$;
-- safeupdate 규칙을 정적으로 센다(qbo_sync_2c1_check 의 것 그대로)
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

-- ── 가짜 직원(manager · sales) ──
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('b2c50000-0000-4000-8000-00000000000a', 'b2c50000-0000-4000-8000-000000000001', 'cr-store-1a-mgr@asung.invalid', 'CR Store 1a Manager', 'manager', '["sales"]');

-- ── K) 실물 — 열쇠 둘(1030) · 오더 손님 두 칸 같음(이견 2) · 어긋난 활성 붙임 0(C-1) · CR-01008 → 60026 같은 매장 · 60059 · 60060 매장 이름 ──
\if :landed
select pg_temp.chk('K1 열쇠 — issued 인보이스 전부 so_invoice_store 있음(null 0) · 크레딧 전부 so_credit_store 있음(null 0) · 이월은 전부 store_customer_id 그대로 · sale 은 전부 오더 손님',
  (select 'inv null ' || count(*) filter (where public.so_invoice_store(i.id) is null) || '/' || count(*)
       || ' · opening=store ' || (count(*) filter (where i.kind = 'opening' and public.so_invoice_store(i.id) = i.store_customer_id) = count(*) filter (where i.kind = 'opening'))::text
       || ' · sale=order ' || (count(*) filter (where i.kind = 'sale' and public.so_invoice_store(i.id) = (select o.customer_id from public.so_invoice_order o where o.invoice_id = i.id and o.cancelled_at is null limit 1)) = count(*) filter (where i.kind = 'sale'))::text
     from public.so_invoice i where i.status = 'issued')
  || ' | credit null ' || (select count(*) filter (where public.so_credit_store(c.id) is null) || '/' || count(*) from public.so_credit c),
  'inv null 0/' || (select count(*) from public.so_invoice where status = 'issued') || ' · opening=store true · sale=order true | credit null 0/' || :n_cr0);
select pg_temp.chk('K2 so_invoice_order.customer_id = so.customer_id 전 행(이견 2) · 어긋난 활성 붙임 0(C-1) · CR-01008 → 60026 같은 매장(Alicer) · 60059 → Regina-BRTB · 60060 → Rex-BRTQ',
  (select count(*) filter (where o.customer_id is distinct from s.customer_id)::text || '/' || count(*) from public.so_invoice_order o join public.so s on s.id = o.so_id)
  || ' | cross ' || (select count(*) from public.so_credit_alloc a join public.so_invoice i on i.id = a.invoice_id where a.voided_at is null and public.so_invoice_store(i.id) is distinct from public.so_credit_store(a.credit_id))
  || ' | ' || (select (public.so_credit_store(a.credit_id) = public.so_invoice_store(a.invoice_id))::text || ' ' || pg_temp.cname(public.so_credit_store(a.credit_id)) from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id where c.credit_number = 'CR-01008' and a.voided_at is null and a.invoice_id is not null)
  || ' | ' || pg_temp.cname(public.so_invoice_store((select id from public.so_invoice where invoice_number = '60059'))) || ' | ' || pg_temp.cname(public.so_invoice_store((select id from public.so_invoice where invoice_number = '60060'))),
  '0/' || (select count(*) from public.so_invoice_order) || ' | cross 0 | true Alicer Express Inc. | Regina Beauty Inc.-BRTB | Rex Beauty Inc.-BRTQ');
\else
select pg_temp.chk('K1 열쇠 함수 — 적용 안 됨(so_invoice_store 없음)', 'missing', 'landed');
select pg_temp.chk('K2 열쇠 함수 — 적용 안 됨(so_invoice_store 없음)', 'missing', 'landed');
\endif

-- ── 가짜 오더 6(실물 손님 · 청구처) · 인보이스 6 · 크레딧 4 · 환불 2 ──
--   S1 BRTB · S2 MSG · S3 BRTB + S4 MSG(한 인보이스 = 매장 둘) · S5 Rex 본사 자신 · S6 DT(크레딧 없는 매장 · 구조 증명 (가))
insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_country) values
  ('e2c50000-0000-4000-8000-000000000001', 'SO-99941', :'brtb'::uuid, :'regina'::uuid, 'pos', 'manual', :'cad_id'::uuid, 'CAD', public.ims_today() - 1, 'CRS-1', now() - interval '1 day', 'BRTB', '1 St', 'Toronto', 'CA'),
  ('e2c50000-0000-4000-8000-000000000002', 'SO-99942', :'msg'::uuid,  :'regina'::uuid, 'pos', 'manual', :'cad_id'::uuid, 'CAD', public.ims_today() - 1, 'CRS-2', now() - interval '1 day', 'MSG', '2 St', 'Toronto', 'CA'),
  ('e2c50000-0000-4000-8000-000000000003', 'SO-99943', :'brtb'::uuid, :'regina'::uuid, 'pos', 'manual', :'cad_id'::uuid, 'CAD', public.ims_today() - 1, 'CRS-3', now() - interval '1 day', 'BRTB', '3 St', 'Toronto', 'CA'),
  ('e2c50000-0000-4000-8000-000000000004', 'SO-99944', :'msg'::uuid,  :'regina'::uuid, 'pos', 'manual', :'cad_id'::uuid, 'CAD', public.ims_today() - 1, 'CRS-4', now() - interval '1 day', 'MSG', '4 St', 'Toronto', 'CA'),
  ('e2c50000-0000-4000-8000-000000000005', 'SO-99945', :'rex'::uuid,  :'rex'::uuid,    'pos', 'manual', :'cad_id'::uuid, 'CAD', public.ims_today() - 1, 'CRS-5', now() - interval '1 day', 'Rex', '5 St', 'Toronto', 'CA'),
  ('e2c50000-0000-4000-8000-000000000006', 'SO-99946', :'dt'::uuid,   :'regina'::uuid, 'pos', 'manual', :'cad_id'::uuid, 'CAD', public.ims_today() - 1, 'CRS-6', now() - interval '1 day', 'DT', '6 St', 'Toronto', 'CA');
--   IA 9990101 Regina ← S1(BRTB) · IB 9990102 Regina ← S2(MSG) · IC 9990103 Regina ← S3 + S4(매장 둘) · ID 9990104 Rex ← S5(본사 자신) · IE 9990105 이월 Regina · 매장 BRTB(오더 0) · IF 9990106 sale Regina · 오더 0 · 매장 없음
create function pg_temp.mk_inv(p_id uuid, p_num text, p_kind text, p_bill uuid, p_store uuid, p_sos uuid[]) returns void language plpgsql as $$
declare v_so uuid;
begin
  insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_country, issued_on, issued_by, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due, legacy_sale_id, legacy_invoice_id, store_customer_id)
  values (p_id, p_num, p_kind, 'issued', p_bill, pg_temp.cname(p_bill), '1 Any St', 'Toronto', 'CA', public.ims_today() - 1, 'b2c50000-0000-4000-8000-00000000000a', (select id from public.ref_currency where code = 'CAD'), 'CAD', 10, 10, 0, 10, 10,
          case when p_kind = 'opening' then 'CRS-LS' end, case when p_kind = 'opening' then 'CRS-LI-' || p_num end, case when p_kind = 'opening' then p_store end);
  foreach v_so in array p_sos loop
    insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, taxable_amount, tax_amount, total)
    select p_id, s.id, s.so_number, s.customer_id, s.ship_to_company, s.ship_to_line1, s.ship_to_city, s.ship_to_country, (select id from public.ref_tax_rule where name = 'HST ON (Sale)'), 'HST ON (Sale)', 13, 'ship_to', 10, 10, 0, 10 from public.so s where s.id = v_so;
  end loop;
end $$;
select pg_temp.mk_inv('12c50000-0000-4000-8000-000000000001', '9990101', 'sale', :'regina'::uuid, null, array['e2c50000-0000-4000-8000-000000000001'::uuid]);
select pg_temp.mk_inv('12c50000-0000-4000-8000-000000000002', '9990102', 'sale', :'regina'::uuid, null, array['e2c50000-0000-4000-8000-000000000002'::uuid]);
select pg_temp.mk_inv('12c50000-0000-4000-8000-000000000003', '9990103', 'sale', :'regina'::uuid, null, array['e2c50000-0000-4000-8000-000000000003'::uuid, 'e2c50000-0000-4000-8000-000000000004'::uuid]);
select pg_temp.mk_inv('12c50000-0000-4000-8000-000000000004', '9990104', 'sale', :'rex'::uuid, null, array['e2c50000-0000-4000-8000-000000000005'::uuid]);
select pg_temp.mk_inv('12c50000-0000-4000-8000-000000000005', '9990105', 'opening', :'regina'::uuid, :'brtb'::uuid, '{}'::uuid[]);
select pg_temp.mk_inv('12c50000-0000-4000-8000-000000000006', '9990106', 'sale', :'regina'::uuid, null, '{}'::uuid[]);
--   크레딧 — C1 CR-99931 Regina · 매장 BRTB · 5 · C2 CR-99932 Rex · 매장 Rex 자신 · 3 · C3 CR-99933 Regina · 매장 MSG · 4 · C4 CR-99934 Regina · 매장 null(열쇠 = 청구처 자신) · 2
create function pg_temp.mk_cr(p_id uuid, p_num text, p_cust uuid, p_store uuid, p_inv uuid, p_amt numeric) returns void language plpgsql as $$
begin
  insert into public.so_credit (id, credit_number, status, customer_id, store_customer_id, currency_id, currency_code, invoice_id, reason, warehouse_id, warehouse_name, issued_on, issued_by, lines_amount, fee_amount, tax_amount, total)
  values (p_id, p_num, 'issued', p_cust, p_store, (select id from public.ref_currency where code = 'CAD'), 'CAD', p_inv, 'billing_error', (select id from public.ref_warehouse where name = 'Asung Trading Inc.'), 'Asung Trading Inc.', public.ims_today() - 1, 'b2c50000-0000-4000-8000-00000000000a', p_amt, 0, 0, p_amt);
  insert into public.so_credit_line (credit_id, line_no, kind, description, amount, tax_amount, account_id, account_code) values (p_id, 1, 'other', 'Goodwill', p_amt, 0, (select id from public.ref_account where code = '_6_'), '_6_');
end $$;
select pg_temp.mk_cr('32c50000-0000-4000-8000-000000000001', 'CR-99931', :'regina'::uuid, :'brtb'::uuid, '12c50000-0000-4000-8000-000000000001', 5);
select pg_temp.mk_cr('32c50000-0000-4000-8000-000000000002', 'CR-99932', :'rex'::uuid,    :'rex'::uuid,  '12c50000-0000-4000-8000-000000000004', 3);
select pg_temp.mk_cr('32c50000-0000-4000-8000-000000000003', 'CR-99933', :'regina'::uuid, :'msg'::uuid,  '12c50000-0000-4000-8000-000000000002', 4);
select pg_temp.mk_cr('32c50000-0000-4000-8000-000000000004', 'CR-99934', :'regina'::uuid, null,          '12c50000-0000-4000-8000-000000000001', 2);
--   환불 결제 둘(1025′ 환불 갈래) — R1 Rex · R2 Regina
insert into public.so_payment (id, kind, amount, paid_on, method, customer_id, currency_id, currency_code, account_id, account_code, warehouse_id, warehouse_name, created_by) values
  ('42c50000-0000-4000-8000-000000000001', 'refund', 1, public.ims_today(), 'cash', :'rex'::uuid,    :'cad_id'::uuid, 'CAD', :'a99'::uuid, '_99_', :'wh_id'::uuid, 'Asung Trading Inc.', 'b2c50000-0000-4000-8000-00000000000a'),
  ('42c50000-0000-4000-8000-000000000002', 'refund', 1, public.ims_today(), 'cash', :'regina'::uuid, :'cad_id'::uuid, 'CAD', :'a99'::uuid, '_99_', :'wh_id'::uuid, 'Asung Trading Inc.', 'b2c50000-0000-4000-8000-00000000000a');

-- ── F) 가짜 행의 열쇠 ──
select pg_temp.chk('F1 가짜 인보이스 열쇠 — IA BRTB · IB MSG · IC null(매장 둘) · ID Rex 자신 · IE BRTB(이월) · IF null(오더 0) · 크레딧 C1 BRTB · C2 Rex · C3 MSG · C4 Regina(매장 null → 청구처)',
  pg_temp.pg('select coalesce(pg_temp.cname(public.so_invoice_store(''12c50000-0000-4000-8000-000000000001'')), ''null'') || '' | '' || coalesce(pg_temp.cname(public.so_invoice_store(''12c50000-0000-4000-8000-000000000002'')), ''null'') || '' | '' || coalesce(pg_temp.cname(public.so_invoice_store(''12c50000-0000-4000-8000-000000000003'')), ''null'') || '' | '' || coalesce(pg_temp.cname(public.so_invoice_store(''12c50000-0000-4000-8000-000000000004'')), ''null'') || '' | '' || coalesce(pg_temp.cname(public.so_invoice_store(''12c50000-0000-4000-8000-000000000005'')), ''null'') || '' | '' || coalesce(pg_temp.cname(public.so_invoice_store(''12c50000-0000-4000-8000-000000000006'')), ''null'')')
  || ' || ' || pg_temp.pg('select pg_temp.cname(public.so_credit_store(''32c50000-0000-4000-8000-000000000001'')) || '' | '' || pg_temp.cname(public.so_credit_store(''32c50000-0000-4000-8000-000000000002'')) || '' | '' || pg_temp.cname(public.so_credit_store(''32c50000-0000-4000-8000-000000000003'')) || '' | '' || pg_temp.cname(public.so_credit_store(''32c50000-0000-4000-8000-000000000004''))'),
  'Regina Beauty Inc.-BRTB | Regina Beauty Inc.-MSG | null | Rex Beauty Inc.-Warehouse | Regina Beauty Inc.-BRTB | null || Regina Beauty Inc.-BRTB | Rex Beauty Inc.-Warehouse | Regina Beauty Inc.-MSG | Regina Beauty Inc.');

-- ── T) 문 so_credit_alloc_add(postgres · 속 함수) ──
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000001'', ''12c50000-0000-4000-8000-000000000001'', 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'')).amount::text') as t1 \gset
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000001'', ''12c50000-0000-4000-8000-000000000002'', 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'')).amount::text') as t2 \gset
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000001'', ''12c50000-0000-4000-8000-000000000003'', 1, ''auto'', ''b2c50000-0000-4000-8000-00000000000a'')).amount::text') as t3 \gset
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000001'', ''12c50000-0000-4000-8000-000000000006'', 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'')).amount::text') as t4 \gset
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000002'', ''12c50000-0000-4000-8000-000000000004'', 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'')).amount::text') as t5 \gset
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000001'', ''12c50000-0000-4000-8000-000000000005'', 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'')).amount::text') as t6 \gset
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000004'', ''12c50000-0000-4000-8000-000000000001'', 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'')).amount::text') as t7 \gset
select pg_temp.chk('T1 C1(BRTB) → IA(BRTB) 붙음 1 · T6 C1 → IE(이월 BRTB · store_customer_id) 붙음 1 · T5 C2(Rex 본사 자신) → ID(본사 이름 오더) 붙음 1', :'t1' || ' | ' || :'t6' || ' | ' || :'t5', '1 | 1 | 1');
select pg_temp.chk('T2 C1(BRTB) → IB(MSG) 거부 — 매장 글(1010)', :'t2', 'ERR P0001: Credit note CR-99931 belongs to store Regina Beauty Inc.-BRTB — invoice 9990102 is for store Regina Beauty Inc.-MSG — a credit note applies only to invoices of the store it was issued to — nothing was saved');
select pg_temp.chk('T3 C1 → IC(매장 둘 · auto 도) 거부 — 1022′ 글 · T4 C1 → IF(오더 0 · 매장 없음) 거부 — 이견 3 글', :'t3' || ' | ' || :'t4',
  'ERR P0001: Invoice 9990103 covers 2 stores — a credit note applies to one store''s invoice only — split the invoice (cancel and reissue per store) — nothing was saved | ERR P0001: Invoice 9990106 has no store on record — nothing was saved');
select pg_temp.chk('T7 C4(매장 null → 열쇠 = 청구처 Regina) → IA(BRTB) 거부 — coalesce 갈래', :'t7', 'ERR P0001: Credit note CR-99934 belongs to store Regina Beauty Inc. — invoice 9990101 is for store Regina Beauty Inc.-BRTB — a credit note applies only to invoices of the store it was issued to — nothing was saved');
select pg_temp.chk('T8 옛 문 그대로 — 청구처 다른 인보이스(C2 Rex → IA Regina)는 옛 글로 먼저 거부(매장 문은 그 뒤)',
  pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000002'', ''12c50000-0000-4000-8000-000000000001'', 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'')).amount::text'),
  'ERR P0001: Invoice 9990101 bills a different customer than credit note CR-99932 — nothing was saved');
--   환불 갈래(1025′) — 글자 무변 + 동작 그대로(같은 손님 환불 OK · 다른 손님 거부)
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000002'', null, 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'', ''42c50000-0000-4000-8000-000000000001'')).amount::text') as r1 \gset
select pg_temp.pg('select (public.so_credit_alloc_add(''32c50000-0000-4000-8000-000000000002'', null, 1, ''manual'', ''b2c50000-0000-4000-8000-00000000000a'', ''42c50000-0000-4000-8000-000000000002'')).amount::text') as r2 \gset
select pg_temp.chk('T9 환불 갈래 무접촉(1025′) — else ~ end if 글자가 begin 앞과 같다 · 같은 손님 환불 붙음 1 · 다른 손님 환불 옛 글로 거부',
  (select (split_part(split_part(p.prosrc, E'\n  else\n', 2), E'\n  insert into public.so_credit_alloc', 1) = split_part(split_part(t.prosrc, E'\n  else\n', 2), E'\n  insert into public.so_credit_alloc', 1))::text
     from pg_proc p join t_pre t on t.proname = p.proname where p.pronamespace = 'public'::regnamespace and p.proname = 'so_credit_alloc_add')
  || ' | ' || :'r1' || ' | ' || :'r2',
  'true | 1 | ERR P0001: Refund and credit note CR-99932 differ in customer or currency — nothing was saved');

-- ── P) 계획 so_invoice_apply_plan(1026′ · 1022′ · 이견 5) — C1 남은 3(5 − 1 − 1) · C3 4 · C4 2(Regina 자신) ──
select pg_temp.pg('select public.so_invoice_apply_plan(''' || :'regina' || ''', ''' || :'cad_id' || ''', array[''e2c50000-0000-4000-8000-000000000001''::uuid], 100)::text') as p1 \gset
select pg_temp.pg('select public.so_invoice_apply_plan(''' || :'regina' || ''', ''' || :'cad_id' || ''', array[''e2c50000-0000-4000-8000-000000000002''::uuid], 100)::text') as p2 \gset
select pg_temp.pg('select public.so_invoice_apply_plan(''' || :'regina' || ''', ''' || :'cad_id' || ''', array[''e2c50000-0000-4000-8000-000000000003''::uuid, ''e2c50000-0000-4000-8000-000000000004''::uuid], 100)::text') as p3 \gset
select pg_temp.pg('select public.so_invoice_apply_plan(''' || :'regina' || ''', ''' || :'cad_id' || ''', array[''e2c50000-0000-4000-8000-000000000006''::uuid], 100)::text') as p4 \gset
select pg_temp.pg('select public.so_invoice_apply_plan(''' || :'rex' || ''', ''' || :'cad_id' || ''', array[''e2c50000-0000-4000-8000-000000000005''::uuid], 100)::text') as p5 \gset
create function pg_temp.plan(p text) returns text language sql as $$
  select case when pg_temp.j(p) is null then p else
    'credit ' || (pg_temp.j(p)->>'credit') || ' steps ' || coalesce((select string_agg((s->>'credit_number') || '=' || (s->>'amount'), ',' order by s->>'credit_number') from jsonb_array_elements(pg_temp.j(p)->'steps') s where s->>'step' = 'auto_credit'), '-')
    || ' skipped ' || coalesce(pg_temp.j(p)->>'credit_skipped', 'null') || ' keys ' || (select count(*) from jsonb_object_keys(pg_temp.j(p))) end $$;
select pg_temp.chk('P1 계획 [S1 BRTB] — C1 남은 3 만(C3 MSG · C4 Regina 자신 안 고름) · skipped null · 키 6(옛 5 + credit_skipped)', pg_temp.plan(:'p1'), 'credit 3 steps CR-99931=3 skipped null keys 6');
select pg_temp.chk('P2 계획 [S2 MSG] — C3 4 만', pg_temp.plan(:'p2'), 'credit 4 steps CR-99933=4 skipped null keys 6');
select pg_temp.chk('P3 계획 [S3 + S4 매장 둘] — 크레딧 0 · auto_credit 걸음 0 · credit_skipped multi_store(1022′)', pg_temp.plan(:'p3'), 'credit 0 steps - skipped multi_store keys 6');
select pg_temp.chk('P4 계획 [S6 DT · 그 매장 크레딧 없음] — 크레딧 0 · 걸음 0 · skipped null(구조 증명 (가): 다른 매장 크레딧만 있는 손님의 발행은 크레딧을 안 건드린다)', pg_temp.plan(:'p4'), 'credit 0 steps - skipped null keys 6');
select pg_temp.chk('P5 계획 [S5 Rex 본사 자신] — C2 남은 1(3 − 1 − 1)', pg_temp.plan(:'p5'), 'credit 1 steps CR-99932=1 skipped null keys 6');
select pg_temp.chk('P6 구조 증명 (나) — so_invoice_issue md5 무변(svc_1c 7a031482…) · alloc_add 호출 1 · 그 호출은 apply_plan 호출 뒤(계획 걸음에서만) · 부르는 곳 셋(issue · preview · service_invoice)',
  (select md5(p.prosrc) || ' | ' || (length(p.prosrc) - length(replace(p.prosrc, 'so_credit_alloc_add(', ''))) / length('so_credit_alloc_add(') || ' | ' || (position('so_credit_alloc_add(' in p.prosrc) > position('so_invoice_apply_plan(' in p.prosrc))::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_issue')
  || ' | ' || (select string_agg(p.proname, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc like '%so_invoice_apply_plan(%' and p.proname <> 'so_invoice_apply_plan'),
  '7a03148223048349d2b9d461969ca3f6 | 1 | true | so_invoice_issue so_invoice_preview so_service_invoice');

-- ── D) Attach 후보 so_credit_detail(1033 의 한 곳) — C1(BRTB): IA(남은 9) · IE(남은 9) 만 · IB(MSG) · IC(둘) · IF(없음) 빠짐 · 다른 키 그대로 ──
select pg_temp.mgw('select public.so_credit_detail(''32c50000-0000-4000-8000-000000000001'')::text') as d1 \gset
select pg_temp.chk('D1 C1 상세 open_invoices = 9990101 · 9990105 만(매장 BRTB) · remaining(C1) 3 · applied 2 · 키 수 14 그대로',
  (select coalesce(string_agg(o->>'invoice_number', ',' order by o->>'invoice_number'), '-') from jsonb_array_elements(coalesce(pg_temp.j(:'d1')->'open_invoices', '[]'::jsonb)) o where (o->>'invoice_number') like '99901%')
  || ' | ' || coalesce(pg_temp.j(:'d1')->>'remaining', :'d1') || ' | ' || coalesce(pg_temp.j(:'d1')->>'applied', '-') || ' | ' || coalesce((select count(*) from jsonb_object_keys(pg_temp.j(:'d1')))::text, '-'),
  '9990101,9990105 | 3 | 2 | 14');
select pg_temp.mgw('select public.so_credit_detail(''32c50000-0000-4000-8000-000000000004'')::text') as d4 \gset
select pg_temp.chk('D2 C4(매장 null → Regina 자신) 상세 open_invoices — 가짜 중 0(Regina 이름 오더 없음 · IF 는 매장 없음)',
  (select coalesce(string_agg(o->>'invoice_number', ',' order by o->>'invoice_number'), '-') from jsonb_array_elements(coalesce(pg_temp.j(:'d4')->'open_invoices', '[]'::jsonb)) o where (o->>'invoice_number') like '99901%'), '-');

-- ── I) 발행 so_credit_issue(manager) — 인보이스 갈래 매장(1031 · 이견 1) · 참조 갈래(1032 · 이견 4) ──
create function pg_temp.pinv(p_inv text) returns text language sql as $$
  select format('select public.so_credit_issue(%L::jsonb, false)::text', jsonb_build_object('invoice_id', p_inv, 'reason', 'billing_error', 'warehouse_id', (select id from public.ref_warehouse where name = 'Asung Trading Inc.'),
    'lines', jsonb_build_array(jsonb_build_object('kind', 'other', 'amount', 1, 'description', 'Goodwill', 'account_id', (select id from public.ref_account where code = '_6_'))))) $$;
create function pg_temp.pref(p_cust text, p_store text, p_commit boolean) returns text language sql as $$
  select format('select public.so_credit_issue(%L::jsonb, %s)::text', jsonb_strip_nulls(jsonb_build_object('ref', jsonb_build_object('invoice_number', 'CRS-REF-OLD-1', 'order_number', 'SO-OLD', 'invoice_date', '2026-10-01'),
    'customer_id', p_cust, 'store_customer_id', p_store, 'currency_code', 'CAD', 'tax_rule', 'HST ON (Sale)', 'reason', 'billing_error', 'warehouse_id', (select id from public.ref_warehouse where name = 'Asung Trading Inc.'),
    'lines', jsonb_build_array(jsonb_build_object('kind', 'other', 'amount', 1, 'description', 'Goodwill', 'account_id', (select id from public.ref_account where code = '_6_'))))), p_commit::text) $$;
-- 손님 행 잠금 창(Regina · Alicer · so_credit_issue 136 행 for update) = 여기부터 rollback 까지
select clock_timestamp() as t_lock \gset
select pg_temp.mgw(pg_temp.pinv('12c50000-0000-4000-8000-000000000005')) as i1 \gset
select pg_temp.mgw(pg_temp.pinv('12c50000-0000-4000-8000-000000000003')) as i2 \gset
select pg_temp.mgw(pg_temp.pinv('12c50000-0000-4000-8000-000000000001')) as i3 \gset
select pg_temp.chk('I1 이월 IE(매장 BRTB · 오더 0) 크레딧 미리 보기 — store_customer_id = BRTB(1031 · 옛 코드는 null) · 경고에 store_ambiguous 없음',
  coalesce(pg_temp.cname((pg_temp.j(:'i1')->>'store_customer_id')::uuid), left(:'i1', 80)) || ' | ' || coalesce((pg_temp.j(:'i1')->'warnings' ? 'store_ambiguous')::text, '-'), 'Regina Beauty Inc.-BRTB | false');
select pg_temp.chk('I2 매장 둘 IC 크레딧 미리 보기 — 매장 = 첫 오더(SO-99943 · BRTB) · 경고 store_ambiguous(이견 1) · I3 sale IA — 오더 손님 BRTB · 경고 없음',
  coalesce(pg_temp.cname((pg_temp.j(:'i2')->>'store_customer_id')::uuid), left(:'i2', 80)) || ' | ' || coalesce((pg_temp.j(:'i2')->'warnings' ? 'store_ambiguous')::text, '-')
  || ' || ' || coalesce(pg_temp.cname((pg_temp.j(:'i3')->>'store_customer_id')::uuid), left(:'i3', 80)) || ' | ' || coalesce((pg_temp.j(:'i3')->'warnings' ? 'store_ambiguous')::text, '-'),
  'Regina Beauty Inc.-BRTB | true || Regina Beauty Inc.-BRTB | false');
--   발행 commit 1(시퀀스 1 소모 · 끝에서 되돌림) — IE 이월 크레딧의 표 행 store_customer_id
select pg_temp.mgw(replace(pg_temp.pinv('12c50000-0000-4000-8000-000000000005'), ', false)', ', true)')) as i4 \gset
select pg_temp.chk('I4 이월 IE 크레딧 발행(commit) — committed · 반환 store BRTB · 표 행 store_customer_id BRTB · invoice_id IE · 번호 = 시퀀스 다음',
  coalesce(pg_temp.j(:'i4')->>'committed', left(:'i4', 80)) || ' | ' || coalesce(pg_temp.cname((pg_temp.j(:'i4')->>'store_customer_id')::uuid), '-')
  || ' | ' || coalesce((select pg_temp.cname(c.store_customer_id) || ' ' || (c.invoice_id = '12c50000-0000-4000-8000-000000000005')::text || ' ' || c.credit_number from public.so_credit c where c.id = (pg_temp.j(:'i4')->>'credit_id')::uuid), '-'),
  'true | Regina Beauty Inc.-BRTB | Regina Beauty Inc.-BRTB true CR-' || lpad((:cr_seq_last + 1)::text, 5, '0'));
--   참조 갈래
select pg_temp.mgw(pg_temp.pref(:'regina', null, false)) as rf1 \gset
select pg_temp.mgw(pg_temp.pref(:'regina', :'regina', false)) as rf2 \gset
select pg_temp.mgw(pg_temp.pref(:'regina', :'brtb', false)) as rf3 \gset
select pg_temp.mgw(pg_temp.pref(:'brtb', null, false)) as rf4 \gset
select pg_temp.mgw(pg_temp.pref(:'alicer', null, false)) as rf5 \gset
select pg_temp.mgw(pg_temp.pref(:'regina', :'rex', false)) as rf6 \gset
select pg_temp.chk('R1 참조 크레딧 — 청구처 Regina(매장 셋) · 매장 비움 → 거부(1032 글)', :'rf1', 'ERR P0001: Customer Regina Beauty Inc. has stores — pick the store this credit belongs to (or the head office itself) — nothing was saved');
select pg_temp.chk('R2 참조 — 본사 자신(Regina) 고름 → 받음 · store Regina · R3 매장 BRTB 고름 → 받음 · store BRTB',
  coalesce(pg_temp.cname((pg_temp.j(:'rf2')->>'store_customer_id')::uuid), left(:'rf2', 80)) || ' | ' || coalesce(pg_temp.cname((pg_temp.j(:'rf3')->>'store_customer_id')::uuid), left(:'rf3', 80)), 'Regina Beauty Inc. | Regina Beauty Inc.-BRTB');
select pg_temp.chk('R4 참조 — customer_id 가 매장(BRTB) → 거부(이견 4 글)', :'rf4', 'ERR P0001: Customer Regina Beauty Inc.-BRTB bills to Regina Beauty Inc. — send customer_id = the bill-to and store_customer_id = this store — nothing was saved');
select pg_temp.chk('R5 참조 — 매장 없는 손님(Alicer) · 매장 비움 → 지금처럼 청구처 자신 · R6 남의 매장(Rex)을 고르면 옛 글로 거부',
  coalesce(pg_temp.cname((pg_temp.j(:'rf5')->>'store_customer_id')::uuid), left(:'rf5', 80)) || ' | ' || split_part(:'rf6', ' — ', 1), 'Alicer Express Inc. | ERR P0001: customer_id must be the bill-to of store Rex Beauty Inc.-Warehouse');

-- ── L) REST 두 겹 ① — 새 · 재발행 함수의 update · delete 는 전부 깊이 0 WHERE · 다른 함수 md5 무변 · 권한 ──
select pg_temp.chk('L1 nowhere 스캐너 = 0(새 2 + 재발행 4)', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('so_credit_store', 'so_invoice_store', 'so_credit_alloc_add', 'so_invoice_apply_plan', 'so_credit_issue', 'so_credit_detail')),
  'so_credit_alloc_add=0 so_credit_detail=0 so_credit_issue=0 so_credit_store=0 so_invoice_apply_plan=0 so_invoice_store=0');
\if :{?mig}
select pg_temp.chk('L2 기존 함수 md5 — 재발행 4(alloc_add · apply_plan · credit_issue · credit_detail) 빼고 so_credit* · so_invoice* · so_payment* · so_customer_balance* 전부 begin 앞과 같다',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5)
  || ' ' || (select string_agg(t.proname, ' ' order by t.proname) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5),
  (:n_fn - 4)::text || ' so_credit_alloc_add so_credit_detail so_credit_issue so_invoice_apply_plan');
\endif
select pg_temp.chk('L3 권한 · 성질 — 새 둘 stable · invoker · authenticated + service_role · 재발행 넷 옛 ACL 그대로(alloc_add 는 postgres + service_role 만)',
  (select string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text || ':' || coalesce(p.proacl::text, '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
    and p.proname in ('so_credit_store', 'so_invoice_store', 'so_credit_alloc_add', 'so_invoice_apply_plan', 'so_credit_issue', 'so_credit_detail')),
  'so_credit_alloc_add:v:false:{postgres=X/postgres,service_role=X/postgres} so_credit_detail:s:true:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} so_credit_issue:v:true:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} '
  || 'so_credit_store:s:false:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} so_invoice_apply_plan:s:false:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} so_invoice_store:s:false:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}');
select pg_temp.chk('L4 scanner 자기 시험', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text, '101');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback, clock_timestamp() - :'t_lock'::timestamptz as customer_lock_window;
rollback;
\echo '── 번호 시퀀스(이견 8 답) — 그사이 실물 크레딧이 안 생겼을 때만 setval · 생겼으면 빈칸 수만 보고'
select case when (select coalesce(max(credit_number), '') from public.so_credit) = :'cr_max0'
            then 'setval → ' || setval('public.so_credit_number_seq', :cr_seq_last, :'cr_seq_called'::boolean)::text || ' (' || :'cr_seq_called' || ')'
            else 'SKIP setval — real credit notes appeared meanwhile (max now ' || (select max(credit_number) from public.so_credit) || ') · number gap = '
                 || ((select last_value from public.so_credit_number_seq) - :cr_seq_last - (select count(*) from public.so_credit where credit_number > :'cr_max0'))::text end as seq_restore;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.ims_staff where email like 'cr-store-1a-%') = 0 as fake_staff_gone,
       (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.so) = :n_so0 as so_same, (select count(*) from public.so_invoice) = :n_inv0 as invoice_same,
       (select count(*) from public.so_credit) = :n_cr0 as credit_same, (select count(*) from public.so_credit_alloc) = :n_alloc0 as alloc_same, (select count(*) from public.so_payment) = :n_pay0 as payment_same,
       (select last_value from public.so_credit_number_seq) = :cr_seq_last as seq_same,
       (select count(*) from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5) = :n_fn as fn_same;
\if :{?mig}
select (select count(*) from pg_proc where proname in ('so_credit_store', 'so_invoice_store')) = 0 as new_fn_gone_as_expected;
\else
select (select count(*) from pg_proc where proname in ('so_credit_store', 'so_invoice_store')) = 2 as new_fn_present;
\endif
