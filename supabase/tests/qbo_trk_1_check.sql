-- supabase/tests/qbo_trk_1_check.sql — qbo-trk-1 검증: 인보이스 몸의 TrackingNum 31 자 · CustomerMemo 둘째 줄 Tracking (2026-11-06 · Caleb 판정 A · 지시서 ~/asung/prompts/qbo-trk-1.md)
-- [운영 메인 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 2s · statement_timeout 10s) → 가짜 행 → 옛 몸 담기 → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261107021000_qbo_trk_1_tracking_memo.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/qbo_trk_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만) · 기대 OK 수 EXPECT_OK
--   쓰기(전부 rollback): 가짜 직원 1 · 매장 1(짝) · 제품 1(짝) · SO 14 · 인보이스 10(번호 998000N 명시 · 시퀀스 무접촉) — 실제 HST ON (Sale) 짝 · TaxCode 거울 detail 은 있는 그대로 읽는다(기준에서 확인)
--   ⚠️ 발행 트리거는 DEFERRED — 커밋하지 않으므로 일감은 쌓이지 않는다 · QBO 호출 0
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 15
\else
\set EXPECT_OK 14
\endif
\pset pager off
select (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.product) as n_prod0,
       (select count(*) from public.so) as n_so0, (select count(*) from public.so_invoice) as n_inv0, (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.qbo_link) as n_link0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select id::text from public.ref_currency where code = 'CAD') as cad_id,
       (select id::text from public.ref_tax_rule where name = 'HST ON (Sale)') as hst_id,
       (select l.qbo_id from public.ref_tax_rule t join public.qbo_link l on l.ims_kind = 'tax_rule' and l.ims_id = t.id::text where t.name = 'HST ON (Sale)') as hst_qbo,
       (select coalesce(e.detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', '-') from public.ref_tax_rule t join public.qbo_link l on l.ims_kind = 'tax_rule' and l.ims_id = t.id::text join public.qbo_entity e on e.qbo_type = 'TaxCode' and e.qbo_id = l.qbo_id where t.name = 'HST ON (Sale)') as hst_rate,
       (select id::text from public.ref_account where code = '_98_') as a98,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_invoice_body') as fn_md5_0 \gset
\echo '── 기준: staff' :n_staff0 '· customer' :n_cust0 '· so' :n_so0 '· invoice' :n_inv0 '· job' :n_job0 '· realm' :realm '· HST ON →' :hst_qbo '· rate' :hst_rate '· qbo_invoice_body md5' :fn_md5_0
begin;
set local lock_timeout = '2s';
set local statement_timeout = '10s';
select clock_timestamp() as t_begin \gset
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.body(p_id uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  begin v := public.qbo_invoice_body(p_id);
  exception when others then v := jsonb_build_object('error', 'ERR ' || sqlstate || ': ' || sqlerrm); end;
  return v;
end $$;
-- safeupdate 규칙 정적 스캐너(qbo_1c_check 의 것 그대로)
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
-- 가짜 직원 · 매장(짝) · 제품(짝)
insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values
  ('b7c10000-0000-4000-8000-00000000000a', 'b7c10000-0000-4000-8000-000000000001', 'qbo-trk-1-bk@asung.invalid', 'QBO trk1 Bookkeeper', 'manager', '["qbo"]');
insert into public.customer (id, name, is_active, source, currency_code, tax_rule) values ('c7c10000-0000-4000-8000-00000000000a', 'QBOTRK Store', true, 'manual', 'CAD', 'HST ON (Sale)');
insert into public.customer_contact (customer_id, name, email, is_default, is_active, source) values ('c7c10000-0000-4000-8000-00000000000a', 'AP', 'ap-trk@asung.invalid', true, true, 'manual');
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values (:'realm', 'customer', 'c7c10000-0000-4000-8000-00000000000a', 'Customer', 'C-TRK-A', 'manual', 'QBOTRK Store');
insert into public.product (id, name, sku, is_active, source, sellable, revenue_account_code) values ('d7c10000-0000-4000-8000-000000000001', 'QBOTRK Widget', 'QBOTRK-001', true, 'manual', true, '_98_');
insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active) values (:'realm', 'Item', 'I-TRK-1', 'QBOTRK Widget', 'QBOTRK-001', true);
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match) values (:'realm', 'product', 'd7c10000-0000-4000-8000-000000000001', 'Item', 'I-TRK-1', 'manual', 'QBOTRK Widget');
-- 인보이스 하나 = 오더 p_trk 개(원소마다 so.tracking_number · null = 없음) · 오더마다 제품 줄 하나 · so_number 는 SO-T<n><i>(so_number 순 = 넣은 순)
create temp sequence s_so start 99801;
create function pg_temp.mk_inv(p_id uuid, p_num text, p_trk text[]) returns void language plpgsql as $$
declare i int; v_oid uuid; v_so uuid; v_sl uuid; v_num text; v_n int := array_length(p_trk, 1);
begin
  insert into public.so_invoice (id, invoice_number, kind, status, bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country, issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code, lines_amount, taxable_amount, tax_amount, total, amount_due)
  values (p_id, p_num, 'sale', 'issued', 'c7c10000-0000-4000-8000-00000000000a', 'QBOTRK Store', '1 Any St', 'Toronto', 'ON', 'M1M 1M1', 'CA', '2026-11-05', 'b7c10000-0000-4000-8000-00000000000a', null, null, '2026-12-05', (select id from public.ref_currency where code = 'CAD'), 'CAD', 2 * v_n, 2 * v_n, 0.26 * v_n, 2.26 * v_n, 2.26 * v_n);
  for i in 1 .. v_n loop
    v_so := gen_random_uuid(); v_sl := gen_random_uuid(); v_oid := gen_random_uuid(); v_num := 'SO-' || nextval('s_so')::text;
    insert into public.so (id, so_number, customer_id, bill_to_customer_id, channel, intake, currency_id, currency_code, order_date, ref, tracking_number, shipped_at, ship_to_company, ship_to_line1, ship_to_city, ship_to_country)
    values (v_so, v_num, 'c7c10000-0000-4000-8000-00000000000a', 'c7c10000-0000-4000-8000-00000000000a', 'pos', 'manual', (select id from public.ref_currency where code = 'CAD'), 'CAD', '2026-11-05', 'PO-' || v_num, p_trk[i], '2026-11-05 16:00+00', 'Ship', '5 St', 'Toronto', 'CA');
    insert into public.so_line (id, so_id, line_no, product_id, sku, product_name, pack_factor, qty_ordered, qty_shipped, unit_price)
    values (v_sl, v_so, 1, 'd7c10000-0000-4000-8000-000000000001', 'QBOTRK-001', 'QBOTRK Widget', 1, 1, 1, 2);
    insert into public.so_invoice_order (id, invoice_id, so_id, so_number, customer_id, ship_to_company, ship_to_line1, ship_to_city, ship_to_country, tax_rule_id, tax_rule, rate_pct, tax_source, lines_amount, taxable_amount, tax_amount, total)
    values (v_oid, p_id, v_so, v_num, 'c7c10000-0000-4000-8000-00000000000a', 'Ship', '5 St', 'Toronto', 'CA', (select id from public.ref_tax_rule where name = 'HST ON (Sale)'), 'HST ON (Sale)', 13, 'ship_to', 2, 2, 0.26, 2.26);
    insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_code)
    values (p_id, v_oid, i, 'product', v_sl, 'QBOTRK-001', 'QBOTRK Widget', 1, 2, 2, 0.26, '_98_');
  end loop;
end $$;
-- 송장 꼴(실물 모양 · 18 자 UPS) — 11 개 = 218 자 · 60 개 = 1,198 자(메모 1,000 자 넘김)
select (select string_agg('1ZV56D2620' || lpad((100000 + g)::text, 8, '0'), ', ') from generate_series(1, 11) g) as trk11,
       (select string_agg('1ZV56D2620' || lpad((200000 + g)::text, 8, '0'), ', ') from generate_series(1, 60) g) as trk60 \gset
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000001', '9980001', array['1ZV56D262044047464']);                                         -- T1 송장 하나 18 자 · 오더 하나(바이트 동일)
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000002', '9980002', array['1ZV56D262044047464, 1ZV56D262049372479']);                     -- T2 둘 38 자
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000003', '9980003', array[:'trk11']);                                                       -- T3 열한 개 218 자
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000004', '9980004', array[null::text]);                                                     -- T4 송장 없음
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000005', '9980005', array['A-1001, A-1002', 'B-2001']);                                     -- T5 오더 둘 · 둘 다 송장
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000006', '9980006', array[null, 'B-2001']);                                                 -- T6 오더 둘 · 둘째만 송장
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000007', '9980007', array['A-1001', '']);                                                   -- T7 오더 둘 · 첫째에 하나(바이트 동일)
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000008', '9980008', array['ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789']);                         -- T8 하나 36 자(자름)
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000009', '9980009', array[:'trk60']);                                                       -- T9 60 개 1,198 자(메모 한도 · 47 개 남아 996 자 = 45 + 1 + 10 + 47×18 + 46×2 + 2)
select pg_temp.mk_inv('17c10000-0000-4000-8000-000000000010', '9980010', array[E' X1,X2\nX3  X4 ']);                                             -- T10 쉼표 · 줄바꿈 · 공백 섞임
-- 옛 몸(재발행 전) — 시험 갈래에서만 뜻이 있다(확인 갈래는 같은 함수)
select pg_temp.body('17c10000-0000-4000-8000-000000000001')::text as old1, pg_temp.body('17c10000-0000-4000-8000-000000000007')::text as old7, pg_temp.body('17c10000-0000-4000-8000-000000000002')::text as old2 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
select pg_temp.chk('G1 재발행 — qbo_invoice_body 본문이 바뀌었다(md5)', (select (md5(p.prosrc) <> :'fn_md5_0')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_invoice_body'), 'true');
\endif
create temp table t_b as select n, pg_temp.body(('17c10000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid) as r from generate_series(1, 10) n;
create function pg_temp.g(p_n int) returns jsonb language sql as $$ select r->'body' from t_b where n = p_n $$;
create function pg_temp.w(p_n int) returns text language sql as $$ select coalesce((select string_agg(x, ' | ') from jsonb_array_elements_text((select r->'warnings' from t_b where n = p_n)) x where x not like 'no payment term%'), '-') $$;   -- 가짜 인보이스는 결제조건 없음(2b1 경고 · 이 시험의 관심 밖)
-- 기준 점검 — 열 장 모두 몸이 나왔다(error 없음 · needs 0)
select pg_temp.chk('T0 열 장 모두 몸 — error 0 · needs 0 · DocNumber 9980001 ~ 10',
  (select count(*) filter (where r ? 'error')::text || ' ' || sum(jsonb_array_length(r->'needs'))::text || ' ' || string_agg(r->'body'->>'DocNumber', ',' order by n) from t_b), '0 0 9980001,9980002,9980003,9980004,9980005,9980006,9980007,9980008,9980009,9980010');
select pg_temp.chk('T1 송장 하나 18 자 · 오더 하나 — TrackingNum 그대로 · 메모 줄 없음 · 경고 없음 · 몸 바이트 동일(재발행 전후)',
  (pg_temp.g(1)->>'TrackingNum') || ' | ' || (pg_temp.g(1)->'CustomerMemo'->>'value') || ' | ' || pg_temp.w(1) || ' | ' || ((select r::text from t_b where n = 1) = :'old1')::text,
  '1ZV56D262044047464 | Customer Reference: PO-SO-99801, QBOTRK Store | - | true');
select pg_temp.chk('T2 둘 38 자 — TrackingNum 첫 번호 · 메모 둘째 줄 Tracking 둘 · PrivateNote 무변 · 경고 없음 · 그 밖 칸은 재발행 전과 같다',
  (pg_temp.g(2)->>'TrackingNum') || ' | ' || replace(pg_temp.g(2)->'CustomerMemo'->>'value', E'\n', '⏎') || ' | ' || (pg_temp.g(2)->>'PrivateNote') || ' | ' || pg_temp.w(2)
  || ' | ' || ((pg_temp.g(2) - 'TrackingNum'::text - 'CustomerMemo'::text) = ((:'old2'::jsonb->'body') - 'TrackingNum'::text - 'CustomerMemo'::text))::text,
  '1ZV56D262044047464 | Customer Reference: PO-SO-99802, QBOTRK Store⏎Tracking: 1ZV56D262044047464, 1ZV56D262049372479 | Customer Reference: PO-SO-99802 | - | true');
select pg_temp.chk('T3 열한 개 218 자 — TrackingNum 첫 번호 18 자 · 메모에 11 개 전부(한도 안 · 경고 없음)',
  (pg_temp.g(3)->>'TrackingNum') || ' ' || length(pg_temp.g(3)->>'TrackingNum')::text || ' | ' || (split_part(pg_temp.g(3)->'CustomerMemo'->>'value', E'\n', 2) = 'Tracking: ' || :'trk11')::text || ' ' || length(pg_temp.g(3)->'CustomerMemo'->>'value')::text || ' | ' || pg_temp.w(3),
  '1ZV56D262000100001 18 | true ' || (length('Customer Reference: PO-SO-99803, QBOTRK Store') + 1 + length('Tracking: ' || :'trk11'))::text || ' | -');
select pg_temp.chk('T4 송장 없음 — TrackingNum 칸 없음 · 메모 줄 없음', (pg_temp.g(4) ? 'TrackingNum')::text || ' | ' || (pg_temp.g(4)->'CustomerMemo'->>'value'), 'false | Customer Reference: PO-SO-99804, QBOTRK Store');
select pg_temp.chk('T5 오더 둘 · 둘 다 송장 — TrackingNum 첫 오더 첫 번호 · 메모 「SO-1 a, b / SO-2 c」 · refs 는 오더 둘',
  (pg_temp.g(5)->>'TrackingNum') || ' | ' || replace(pg_temp.g(5)->'CustomerMemo'->>'value', E'\n', '⏎'),
  'A-1001 | Customer Reference: PO-SO-99805, PO-SO-99806, QBOTRK Store⏎Tracking: SO-99805 A-1001, A-1002 / SO-99806 B-2001');
select pg_temp.chk('T6 오더 둘 · 둘째만 송장 — TrackingNum 없음 · 메모 「SO-2 c」(송장 있는 오더만)',
  (pg_temp.g(6) ? 'TrackingNum')::text || ' | ' || replace(pg_temp.g(6)->'CustomerMemo'->>'value', E'\n', '⏎'), 'false | Customer Reference: PO-SO-99807, PO-SO-99808, QBOTRK Store⏎Tracking: SO-99808 B-2001');
select pg_temp.chk('T7 오더 둘 · 첫째에 하나 — TrackingNum 그대로 · 메모 줄 없음 · 몸 바이트 동일(재발행 전후)',
  (pg_temp.g(7)->>'TrackingNum') || ' | ' || (pg_temp.g(7)->'CustomerMemo'->>'value') || ' | ' || ((select r::text from t_b where n = 7) = :'old7')::text, 'A-1001 | Customer Reference: PO-SO-99809, PO-SO-99810, QBOTRK Store | true');
select pg_temp.chk('T8 하나 36 자 — TrackingNum 31 자로 자름 · 메모에 전체 · 경고 「cut to 31」',
  (pg_temp.g(8)->>'TrackingNum') || ' ' || length(pg_temp.g(8)->>'TrackingNum')::text || ' | ' || split_part(pg_temp.g(8)->'CustomerMemo'->>'value', E'\n', 2) || ' | ' || pg_temp.w(8),
  'ABCDEFGHIJKLMNOPQRSTUVWXYZ01234 31 | Tracking: ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 | tracking number "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" cut to 31 characters for QuickBooks — the full number is in the memo');
select pg_temp.chk('T9 60 개 1,198 자 — 메모 ≤ 1,000 · 쉼표 경계에서 잘라 ' || quote_literal(' …') || ' · 잘린 자리 뒤 번호는 통째(조각 길이 전부 18) · 경고 「cut to fit 1,000」 · TrackingNum 첫 번호',
  (select (length(m) <= 1000)::text || ' ' || length(m)::text || ' ' || (m like '% …')::text || ' ' || (select bool_and(length(x) = 18) from regexp_split_to_table(regexp_replace(split_part(m, E'\n', 2), '^Tracking: | …$', '', 'g'), ', ') x)::text
          || ' ' || (select count(*) from regexp_split_to_table(regexp_replace(split_part(m, E'\n', 2), '^Tracking: | …$', '', 'g'), ', ')) || ' | ' || (pg_temp.g(9)->>'TrackingNum') || ' | ' || pg_temp.w(9)
   from (select pg_temp.g(9)->'CustomerMemo'->>'value' m) x),
  'true 996 true true 47 | 1ZV56D262000200001 | tracking list in the memo cut to fit 1,000 characters');
select pg_temp.chk('T10 쉼표 · 줄바꿈 · 공백 섞임 — 조각 넷 · TrackingNum X1 · 메모 「X1, X2, X3, X4」',
  (pg_temp.g(10)->>'TrackingNum') || ' | ' || split_part(pg_temp.g(10)->'CustomerMemo'->>'value', E'\n', 2), 'X1 | Tracking: X1, X2, X3, X4');
select pg_temp.chk('T11 실물 꼴 — 운영 failed 6 장의 몸(TrackingNum ≤ 31 · 메모 둘째 줄 Tracking · 1,000 자 안) — 있으면 전부 true · 없으면 0',
  (select coalesce(count(*)::text || ' ' || bool_and(length(b->>'TrackingNum') <= 31 and (b->'CustomerMemo'->>'value') like E'%\nTracking: %' and length(b->'CustomerMemo'->>'value') <= 1000)::text, '0')
   from public.qbo_job j, lateral (select pg_temp.body(j.ims_id::uuid)->'body' b) x where j.kind = 'invoice' and j.state = 'failed' and j.last_error like '%Max:31%'),
  (select coalesce(nullif(count(*), 0)::text || ' true', '0') from public.qbo_job j where j.kind = 'invoice' and j.state = 'failed' and j.last_error like '%Max:31%'));
select pg_temp.chk('L1 nowhere — 재발행 함수의 WHERE 없는 update · delete 0(stable · 쓰기 없음)', (select pg_temp.nowhere(p.prosrc)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_invoice_body'), '0');
select pg_temp.chk('L2 grant — qbo_invoice_body 는 창구 아님(execute 0 · 2b1 그대로)', (select coalesce(p.proacl::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_invoice_body'), '{postgres=X/postgres}');
\echo '── 결과'
select n, case when ok then 'OK ' else 'FAIL' end as r, name, case when ok then '' else 'got:  ' || coalesce(got, '(null)') || E'\nwant: ' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_fail, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.customer) = :n_cust0 as customer_same, (select count(*) from public.product) = :n_prod0 as product_same,
       (select count(*) from public.so) = :n_so0 as so_same, (select count(*) from public.so_invoice) = :n_inv0 as invoice_same, (select count(*) from public.qbo_job) = :n_job0 as job_same, (select count(*) from public.qbo_link) = :n_link0 as link_same,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_invoice_body') = :'fn_md5_0' as fn_same;
