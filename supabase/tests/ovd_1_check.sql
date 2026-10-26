-- ovd-1 검증 — 20261026192704_ovd_1_customer_overdue.sql (판정 768 ~ 771 · 연체 인보이스 알림: 읽기 창구 + 웹 오더 경고)
--   시험 적용 + 검증(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261026192704_ovd_1_customer_overdue.sql -f ~/asung/prompts/ovd-1-verify.sql 2>&1 | tee /tmp/ovd-1.out
--   확인 실행(Caleb · 이미 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다 · 기대 OK 는 아래 줄
--   ⭐ 기대 OK 수: 시험 적용 OK = 20 · MISMATCH 0 · exit 0(3회차 실측 · 1회차 psql 변수가 $$ 안에서 안 풀림 · 2회차 가짜 인보이스 currency_code 비움 — 재료만 고쳤다) · 확인 실행(적용 뒤 · -v mig 없음) = 19(G0 은 시험에서만)
--   ⚠️ 재료 전부 가짜(rollback) — 가짜 손님 넷(Ovd1 Parent = 청구처 · Ovd1 Child(parent_id · default_bill_to = Parent) · Ovd1 Solo · Ovd1 Empty) · 가짜 인보이스 8 장(번호 999770xx · 오더 없음 — 뷰는 left join) · 결제 2(직접 insert · 붙임 1)
--      ⚠️ 시퀀스 무접촉 — so_number_seq · so_invoice_number_seq 를 당기는 창구(so_create · so_invoice_issue · shop_order_process)는 부르지 않는다(asung-workflow §5) · 속 함수 shop_order_overdue_warning 을 직접 · 실제 손님 · 인보이스 · 결제 무접촉(가짜 손님에만 붙는다)
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261026192704' \gset
select :n_applied as schema_migrations_rows_for_20261026192704;
select last_value as seq_last, is_called as seq_called from public.so_number_seq \gset
select last_value as iseq_last, is_called as iseq_called from public.so_invoice_number_seq \gset
select md5(prosrc) as md5_process_before from pg_proc where proname = 'shop_order_process' \gset
select (to_regprocedure('public.so_customer_overdue(uuid)') is not null)::int as fn_before \gset
select count(*) as n_inv_before from public.so_invoice \gset
select count(*) as n_pay_before from public.so_payment \gset
select count(*) as n_cust_before from public.customer \gset
select md5(string_agg(i.id::text || i.status || coalesce(i.due_on::text, '') || public.so_invoice_remaining(i.id)::text, ',' order by i.id)) as inv_md5_before from public.so_invoice i \gset
select id::text as cur from public.ref_currency where code = 'CAD' limit 1 \gset
select id::text as usd from public.ref_currency where code = 'USD' limit 1 \gset
select id::text as wh from public.ref_warehouse where is_active order by name limit 1 \gset
select id::text as acct from public.ref_account where is_active order by code limit 1 \gset
select id::text as staff from public.ims_staff where is_active order by created_at limit 1 \gset
select public.ims_today()::text as today \gset

begin;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
\if :{?mig}
select pg_temp.chk('G0 시험에서만: 적용 전(schema_migrations 0 행 · 창구 없음) · process prosrc 가 바뀌었다 · ovd-1 토막 · 창구 둘이 생겼다',
  :n_applied = 0 and :fn_before = 0
  and (select md5(prosrc) <> :'md5_process_before' and prosrc ~ 'ovd-1 판정 769' and prosrc ~ 'shop_order_overdue_warning\(c\.id\)' from pg_proc where proname = 'shop_order_process')
  and to_regprocedure('public.so_customer_overdue(uuid)') is not null and to_regprocedure('public.shop_order_overdue_warning(uuid)') is not null,
  format('applied %s fn_before %s', :n_applied, :fn_before));
\endif

-- ── 도우미 ──
create function pg_temp.mk_cust(p_name text, p_parent uuid, p_bill uuid, p_cur uuid, p_wh uuid) returns uuid
  language sql as $$ insert into public.customer (name, currency_id, default_location_id, parent_id, parent_source, default_bill_to_customer_id) values (p_name, p_cur, p_wh, p_parent, case when p_parent is null then null else 'ims' end, p_bill) returning id $$;
-- 인보이스 직접 insert(오더 없음 · 시퀀스 무접촉 · currency_code 글자 칸도 발행 창구처럼 채운다 — 뷰 · 창구가 그 칸으로 묶는다) · due_on 은 오늘 기준 일수(null = 기한 없음) · 취소는 status cancelled + cancelled_at · by · note
create function pg_temp.mk_inv(p_number text, p_cust uuid, p_cur uuid, p_total numeric, p_due_days int, p_cancel boolean, p_staff uuid) returns uuid
  language sql as $$
  insert into public.so_invoice (invoice_number, status, bill_to_customer_id, issued_on, due_on, payment_term_name, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due,
                                 cancelled_at, cancelled_by, cancel_note)
  values (p_number, case when p_cancel then 'cancelled' else 'issued' end, p_cust, public.ims_today() - 60, case when p_due_days is null then null else public.ims_today() - p_due_days end, 'ovd-1 fake', p_cur, (select rc.code from public.ref_currency rc where rc.id = p_cur),
          p_total, p_total, 0, p_total, p_total,
          case when p_cancel then now() end, case when p_cancel then p_staff end, case when p_cancel then 'ovd-1 fake cancel' end)
  returning id $$;
create function pg_temp.mk_pay(p_cust uuid, p_amount numeric, p_ref text, p_cur uuid, p_acct uuid, p_wh uuid) returns uuid
  language sql as $$ insert into public.so_payment (kind, amount, method, reference, customer_id, currency_id, account_id, warehouse_id, note) values ('payment', p_amount, 'cash', p_ref, p_cust, p_cur, p_acct, p_wh, 'ovd-1 fake') returning id $$;
create function pg_temp.ovd(p_cust uuid) returns jsonb language sql as $$ select public.so_customer_overdue(p_cust) $$;
create function pg_temp.bc(p_j jsonb) returns text
  language sql as $$ select coalesce(string_agg(e->>'currency_code' || ':' || (e->>'count') || ':' || round((e->>'amount')::numeric, 2) || ':' || (e->>'oldest_days'), ' ' order by e->>'currency_code'), '') from jsonb_array_elements(p_j->'by_currency') e $$;
create function pg_temp.inv_nums(p_j jsonb) returns text
  language sql as $$ select coalesce(string_agg(e->>'invoice_number' || '@' || (e->>'days_overdue'), ' ' order by o), '') from jsonb_array_elements(p_j->'invoices') with ordinality as t(e, o) $$;
create function pg_temp.av(p_j jsonb) returns text
  language sql as $$ select coalesce(string_agg(e->>'currency_code' || ':' || round((e->>'available')::numeric, 2), ' ' order by e->>'currency_code'), '') from jsonb_array_elements(p_j->'available') e $$;

-- ── 가짜 손님 넷 · 인보이스 8 · 결제 2 ──
select pg_temp.mk_cust('Ovd1 Parent', null, null, :'cur'::uuid, :'wh'::uuid)::text as p \gset
select pg_temp.mk_cust('Ovd1 Child', :'p'::uuid, :'p'::uuid, :'cur'::uuid, :'wh'::uuid)::text as k \gset
select pg_temp.mk_cust('Ovd1 Solo', null, null, :'cur'::uuid, :'wh'::uuid)::text as s \gset
select pg_temp.mk_cust('Ovd1 Empty', null, null, :'cur'::uuid, :'wh'::uuid)::text as n \gset
\set i1_total 100.00
\set i2_total 50.00
\set i4_total 10.00
\set i8_total 7.77
\set pay_free 15.00
select pg_temp.mk_inv('99977001', :'p'::uuid, :'cur'::uuid, :i1_total, 10, false, :'staff'::uuid)::text as i1 \gset
select pg_temp.mk_inv('99977002', :'p'::uuid, :'cur'::uuid, :i2_total, 21, false, :'staff'::uuid)::text as i2 \gset
select pg_temp.mk_inv('99977003', :'p'::uuid, :'cur'::uuid, 20.00, 30, false, :'staff'::uuid)::text as i3 \gset
select pg_temp.mk_inv('99977004', :'p'::uuid, :'usd'::uuid, :i4_total, 5, false, :'staff'::uuid)::text as i4 \gset
select pg_temp.mk_inv('99977005', :'p'::uuid, :'cur'::uuid, 70.00, null, false, :'staff'::uuid)::text as i5 \gset
select pg_temp.mk_inv('99977006', :'p'::uuid, :'cur'::uuid, 80.00, -1, false, :'staff'::uuid)::text as i6 \gset
select pg_temp.mk_inv('99977007', :'p'::uuid, :'cur'::uuid, 90.00, 40, true, :'staff'::uuid)::text as i7 \gset
select pg_temp.mk_inv('99977008', :'s'::uuid, :'cur'::uuid, :i8_total, 3, false, :'staff'::uuid)::text as i8 \gset
select pg_temp.mk_pay(:'p'::uuid, 20.00, 'ovd-1 paid i3', :'cur'::uuid, :'acct'::uuid, :'wh'::uuid)::text as pay3 \gset
insert into public.so_payment_alloc (payment_id, invoice_id, amount, source) values (:'pay3'::uuid, :'i3'::uuid, 20.00, 'manual');
select pg_temp.mk_pay(:'p'::uuid, :pay_free, 'ovd-1 free money', :'cur'::uuid, :'acct'::uuid, :'wh'::uuid)::text as payf \gset
-- 기대값은 입력에서: 부모의 연체 = i1(10일 · CAD) · i2(21일 · CAD) · i4(5일 · USD) — i3 다 냄 · i5 기한 없음 · i6 기한 전 · i7 취소 · i8 은 Solo 의 것
select (:i1_total + :i2_total)::numeric as exp_cad \gset
select pg_temp.ovd(:'k'::uuid) as k_j \gset
select pg_temp.ovd(:'p'::uuid) as p_j \gset
select pg_temp.ovd(:'s'::uuid) as s_j \gset
select pg_temp.ovd(:'n'::uuid) as n_j \gset
select pg_temp.chk('V0 재료: 뷰에서 부모 청구처의 열린 행 5(i1 i2 i4 i5 i6) · 연체 3 · 기한 없음 1 · i3 remaining 0 · i7 취소',
  (select count(*) from public.so_invoice_list l where l.bill_to_customer_id = :'p'::uuid and l.is_open) = 5
  and (select count(*) from public.so_invoice_list l where l.bill_to_customer_id = :'p'::uuid and l.is_open and l.days_overdue > 0) = 3
  and (select count(*) from public.so_invoice_list l where l.bill_to_customer_id = :'p'::uuid and l.is_open and l.due_unknown) = 1
  and (select l.remaining from public.so_invoice_list l where l.id = :'i3'::uuid) = 0
  and (select l.status from public.so_invoice_list l where l.id = :'i7'::uuid) = 'cancelled',
  (select string_agg(l.invoice_number || ' ' || l.status || ' open=' || l.is_open::text || ' od=' || l.days_overdue || ' rem=' || l.remaining, ' | ' order by l.invoice_number) from public.so_invoice_list l where l.bill_to_customer_id = :'p'::uuid));
select pg_temp.chk('C1 자식 손님 → 청구처 = 부모 · bill_to_differs true · bill_to_name · as_of 오늘 · count 3 · oldest 21',
  (:'k_j'::jsonb->>'customer_id') = :'k' and (:'k_j'::jsonb->>'bill_to_customer_id') = :'p' and (:'k_j'::jsonb->>'bill_to_differs')::boolean and (:'k_j'::jsonb->>'bill_to_name') = 'Ovd1 Parent'
  and (:'k_j'::jsonb->>'as_of') = :'today' and (:'k_j'::jsonb->>'count')::int = 3 and (:'k_j'::jsonb->>'oldest_days')::int = 21,
  :'k_j');
select pg_temp.chk('C2 자식: by_currency = CAD 2 장 ' || :exp_cad || ' 21일 · USD 1 장 10.00 5일(통화 코드 순) · invoices 일수 내림 i2@21 i1@10 i4@5 · available CAD ' || :pay_free || '(i3 결제는 다 붙어 0 · 빈 돈만)',
  pg_temp.bc(:'k_j'::jsonb) = format('CAD:2:%s:21 USD:1:%s:5', round(:exp_cad::numeric, 2), round(:i4_total::numeric, 2))
  and pg_temp.inv_nums(:'k_j'::jsonb) = '99977002@21 99977001@10 99977004@5'
  and pg_temp.av(:'k_j'::jsonb) = format('CAD:%s', round(:pay_free::numeric, 2)),
  pg_temp.bc(:'k_j'::jsonb) || ' / ' || pg_temp.inv_nums(:'k_j'::jsonb) || ' / ' || pg_temp.av(:'k_j'::jsonb));
select pg_temp.chk('C2b 자식: invoices 원소 열쇠 7(invoice_id invoice_number issued_on due_on days_overdue remaining currency_code) · i2 remaining ' || :i2_total || ' · due_on = 오늘 − 21',
  (select string_agg(k, ',' order by k) from jsonb_object_keys(:'k_j'::jsonb->'invoices'->0) k) = 'currency_code,days_overdue,due_on,invoice_id,invoice_number,issued_on,remaining'
  and (:'k_j'::jsonb->'invoices'->0->>'invoice_id') = :'i2' and round((:'k_j'::jsonb->'invoices'->0->>'remaining')::numeric, 2) = round(:i2_total::numeric, 2)
  and (:'k_j'::jsonb->'invoices'->0->>'due_on')::date = (:'today'::date - 21),
  (:'k_j'::jsonb->'invoices')::text);
select pg_temp.chk('C3 부모 자신 → 같은 수 · bill_to_differs false · bill_to = 자기',
  (:'p_j'::jsonb->>'count')::int = 3 and not (:'p_j'::jsonb->>'bill_to_differs')::boolean and (:'p_j'::jsonb->>'bill_to_customer_id') = :'p'
  and pg_temp.bc(:'p_j'::jsonb) = pg_temp.bc(:'k_j'::jsonb) and pg_temp.inv_nums(:'p_j'::jsonb) = pg_temp.inv_nums(:'k_j'::jsonb) and pg_temp.av(:'p_j'::jsonb) = pg_temp.av(:'k_j'::jsonb),
  :'p_j');
select pg_temp.chk('C4 홀로 손님 → 자기 인보이스 1 장(' || :i8_total || ' · 3일) · available [] · 부모 것은 섞이지 않는다',
  (:'s_j'::jsonb->>'count')::int = 1 and (:'s_j'::jsonb->>'oldest_days')::int = 3 and pg_temp.bc(:'s_j'::jsonb) = format('CAD:1:%s:3', round(:i8_total::numeric, 2))
  and pg_temp.inv_nums(:'s_j'::jsonb) = '99977008@3' and (:'s_j'::jsonb->'available') = '[]'::jsonb and not (:'s_j'::jsonb->>'bill_to_differs')::boolean,
  :'s_j');
select pg_temp.chk('C5 빈 손님 → count 0 · oldest 0 · 배열 셋 [] · 열쇠 10',
  (:'n_j'::jsonb->>'count')::int = 0 and (:'n_j'::jsonb->>'oldest_days')::int = 0 and (:'n_j'::jsonb->'by_currency') = '[]'::jsonb and (:'n_j'::jsonb->'invoices') = '[]'::jsonb and (:'n_j'::jsonb->'available') = '[]'::jsonb
  and (select count(*) from jsonb_object_keys(:'n_j'::jsonb)) = 10,
  :'n_j');
select pg_temp.chk('C6 없는 손님 → null', public.so_customer_overdue('00000000-0000-0000-0000-000000000000'::uuid) is null, public.so_customer_overdue('00000000-0000-0000-0000-000000000000'::uuid)::text);
select pg_temp.chk('C7 정본 대조: so_invoice_ar_summary(부모) CAD overdue_count 2 · overdue_total ' || :exp_cad || ' · no_due_count 1 — 창구와 같은 수',
  (select (c->>'overdue_count')::int = 2 and round((c->>'overdue_total')::numeric, 2) = round(:exp_cad::numeric, 2) and (c->>'no_due_count')::int = 1
     from jsonb_array_elements(public.so_invoice_ar_summary(:'p'::uuid)->'currencies') c where c->>'currency_code' = 'CAD'),
  public.so_invoice_ar_summary(:'p'::uuid)::text);
-- 웹 오더 경고 원소(속 함수 직접 — process 는 시퀀스를 당긴다)
select public.shop_order_overdue_warning(:'k'::uuid) as w_k \gset
select public.shop_order_overdue_warning(:'s'::uuid) as w_s \gset
select public.shop_order_overdue_warning(:'n'::uuid) as w_n \gset
select pg_temp.chk('W1 자식 → 원소 1 · code customer_overdue · at · count 3 · oldest 21 · bill_to_* · as_of · by_currency 같음',
  jsonb_array_length(:'w_k'::jsonb) = 1 and (:'w_k'::jsonb->0->>'code') = 'customer_overdue' and (:'w_k'::jsonb->0->>'at') is not null
  and (:'w_k'::jsonb->0->>'count')::int = 3 and (:'w_k'::jsonb->0->>'oldest_days')::int = 21 and (:'w_k'::jsonb->0->>'bill_to_name') = 'Ovd1 Parent' and (:'w_k'::jsonb->0->>'bill_to_customer_id') = :'p'
  and (:'w_k'::jsonb->0->>'as_of') = :'today' and (:'w_k'::jsonb->0->'by_currency') = (:'k_j'::jsonb->'by_currency'),
  :'w_k');
select pg_temp.chk('W2 자식 글: 「3 overdue invoices at the time the order came in — CAD 150.00 · USD 10.00 — oldest 21 days — billed to Ovd1 Parent」',
  (:'w_k'::jsonb->0->>'message') = format('3 overdue invoices at the time the order came in — CAD %s · USD %s — oldest 21 days — billed to Ovd1 Parent', to_char(:exp_cad::numeric, 'FM999,999,990.00'), to_char(:i4_total::numeric, 'FM999,999,990.00')),
  :'w_k'::jsonb->0->>'message');
select pg_temp.chk('W3 홀로 손님 글: 단수 · billed to 없음 「1 overdue invoice at the time the order came in — CAD 7.77 — oldest 3 days」',
  jsonb_array_length(:'w_s'::jsonb) = 1 and (:'w_s'::jsonb->0->>'message') = format('1 overdue invoice at the time the order came in — CAD %s — oldest 3 days', to_char(:i8_total::numeric, 'FM999,999,990.00')),
  :'w_s'::jsonb->0->>'message');
select pg_temp.chk('W4 빈 손님 · 없는 손님 → [] (process 의 v_warn || [] 는 그대로)',
  :'w_n'::jsonb = '[]'::jsonb and public.shop_order_overdue_warning('00000000-0000-0000-0000-000000000000'::uuid) = '[]'::jsonb and ('[{"code":"x"}]'::jsonb || :'w_n'::jsonb) = '[{"code":"x"}]'::jsonb,
  :'w_n');
select pg_temp.chk('W5 경고 원소는 shop_order_warning_ack 가 읽는 꼴(code · at 있음 · acked_at · settled_at 없음) → open_warning_count 에 센다',
  (:'w_k'::jsonb->0 ? 'code') and (:'w_k'::jsonb->0 ? 'at') and not (:'w_k'::jsonb->0 ? 'acked_at') and not (:'w_k'::jsonb->0 ? 'settled_at'),
  :'w_k');
-- 직원 역할로(invoker · 정책은 authenticated 전부) — 읽기만
set local role authenticated;
select pg_temp.chk('A1 authenticated 로 so_customer_overdue 호출 → 같은 count 3', (public.so_customer_overdue(:'k'::uuid)->>'count')::int = 3, public.so_customer_overdue(:'k'::uuid)::text);
reset role;
select pg_temp.chk('A2 acl: so_customer_overdue authenticated 실행 ○ · anon ✕ · invoker · stable / shop_order_overdue_warning authenticated ✕ anon ✕ public ✕',
  has_function_privilege('authenticated', 'public.so_customer_overdue(uuid)', 'execute') and not has_function_privilege('anon', 'public.so_customer_overdue(uuid)', 'execute')
  and (select not prosecdef and provolatile = 's' from pg_proc where proname = 'so_customer_overdue')
  and not has_function_privilege('authenticated', 'public.shop_order_overdue_warning(uuid)', 'execute') and not has_function_privilege('anon', 'public.shop_order_overdue_warning(uuid)', 'execute') and not has_function_privilege('public', 'public.shop_order_overdue_warning(uuid)', 'execute'),
  'acl');
select pg_temp.chk('P1 shop_order_process 본문: 한 문장 「v_warn := v_warn || public.shop_order_overdue_warning(c.id);」 가 so_create 뒤 · 한 번 · 앞 차수 표식(frt-1a · pay-3a 판정 470 · ful-1b 판정 454) 그대로 · definer · authenticated 실행 ✕',
  (select prosrc like '%v_so_id := (v_so->>''id'')::uuid;%v_warn := v_warn || public.shop_order_overdue_warning(c.id);%so_line_add(%' and (select count(*) from regexp_matches(prosrc, 'shop_order_overdue_warning', 'g')) = 1
          and prosrc like '%frt-1a%' and prosrc like '%pay-3a 판정 470%' and prosrc like '%ful-1b 판정 454%' and prosecdef from pg_proc where proname = 'shop_order_process')
  and not has_function_privilege('authenticated', 'public.shop_order_process(uuid)', 'execute'),
  (select left(prosrc, 200) from pg_proc where proname = 'shop_order_process'));
select pg_temp.chk('P2 inv_config 에 overdue 설정 칸 없음(판정 770)', not exists (select 1 from public.inv_config where key like '%overdue%'), (select string_agg(key, ',') from public.inv_config where key like '%overdue%'));
select pg_temp.chk('Z1 무접촉: 실제 인보이스 md5 · 수 그대로(가짜 8 장 제외) · 실제 결제 수(가짜 2 제외) · 손님 수(가짜 4 제외) · 시퀀스 둘 안 당김',
  (select md5(string_agg(i.id::text || i.status || coalesce(i.due_on::text, '') || public.so_invoice_remaining(i.id)::text, ',' order by i.id)) from public.so_invoice i where i.invoice_number not like '999770%') = :'inv_md5_before'
  and (select count(*) from public.so_invoice) = :n_inv_before + 8 and (select count(*) from public.so_payment) = :n_pay_before + 2 and (select count(*) from public.customer) = :n_cust_before + 4
  and (select last_value = :seq_last and is_called = :'seq_called'::boolean from public.so_number_seq) and (select last_value = :iseq_last and is_called = :'iseq_called'::boolean from public.so_invoice_number_seq),
  format('inv %s pay %s cust %s', (select count(*) from public.so_invoice), (select count(*) from public.so_payment), (select count(*) from public.customer)));
rollback;
select last_value as seq_after, is_called as seq_called_after from public.so_number_seq;
select last_value as iseq_after, is_called as iseq_called_after from public.so_invoice_number_seq;
select count(*) as fake_customers_left from public.customer where name like 'Ovd1 %';
