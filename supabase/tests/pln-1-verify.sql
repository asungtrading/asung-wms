-- pln-1-verify.sql — PO 「Paste lines」 가격 칸 · po_lines_paste 재발행(판정 624):
--   T1 동일성(가격 없이 붙이기 = 옛 함수와 같은 단가 · price_source · 시험 갈래) · T2 2.50 → pasted · product_supplier 무변 · T3 0 받음 · 음수 · abc 는 그 줄만 bad_price(미리 보기 · commit) ·
--   T4 문서 할인 10% 위에 붙인 2.50 → po_detail net_total = round(2.50 × (1 − 10/100), 2)(SQL 식) · T5 미리 보기 쓰기 0 · Z1 다른 PO 함수 md5 무변
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261022190351_pln_1_po_paste_price.sql -f supabase/tests/pln-1-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · T1 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 9 − 3 + 1 = **7** · MISMATCH 0
--   가짜 재료만(PLN1 — 공급처 A · 제품 F(고정 3 · 최근 2.8) · L(최근 1.5) · Z(연결 있고 단가 없음) · I(연결 꺼짐) · N(연결 없음) · 직원 W purchasing · draft PO 둘 · 되감긴다) · po_number_seq 머리 → rollback 뒤 greatest

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261022190351' \gset
select :n_applied as schema_migrations_rows_for_20261022190351;
select last_value as po_seq_last, is_called as po_seq_called from public.po_number_seq \gset
select :po_seq_last as po_seq_head;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 붙이기 결과 자취 — 줄마다 input_sku|verdict|unit_price|price_source · summary 의 수
create function pg_temp.tr(p jsonb) returns text language sql as $$
  select coalesce((select string_agg((r->>'input_sku') || '|' || (r->>'verdict') || '|' || coalesce(trim_scale((r->>'unit_price')::numeric)::text, '-') || '|' || coalesce(r->>'price_source', '-'), ' ; ' order by (r->>'n')::int) from jsonb_array_elements(p->'lines') r), '-')
      || ' · summary ok=' || (p->'summary'->>'ok') || ' no_link=' || (p->'summary'->>'no_link') || ' bad_qty=' || (p->'summary'->>'bad_qty') || ' bad_price=' || coalesce(p->'summary'->>'bad_price', '∅') || ' inserted=' || (p->'summary'->>'inserted') $$;
create function pg_temp.fns() returns text language sql security definer as $$
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('po_create', 'po_line_update', 'po_line_delete', 'po_doc_cancel', 'po_doc_delete', 'po_detail', 'po_discount_save', 'po_discount_delete', 'po_discount_factor', 'po_invoice_create', 'ims_require_write') $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'md5=' || (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste')
      || ' n=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste')
      || ' definer=' || (select p.prosecdef::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste')
      || ' acl=' || (select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') $$;

\echo '── M0) 가짜 재료 — 직원 W · 공급처 A · 제품 다섯 · 연결 넷 · draft PO 둘'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'pln1-w@test.invalid', 'PLN1 W', 'manager', '["ims","purchasing"]', '{}') returning auth_user_id::text as w_uid \gset
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh from public.ref_warehouse where is_active order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.supplier (name, source, is_active, payment_term_name, account_payable_code, currency_id) values ('PLN1 Supplier A', 'manual', true, 'Due on receipt', '_62_', :'cad'::uuid) returning id::text as sup \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PLN1-F', 'PLN1 fixed 3 latest 2.8', 'manual', true, true) returning id::text as pf \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PLN1-L', 'PLN1 latest 1.5', 'manual', true, true) returning id::text as pl \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PLN1-Z', 'PLN1 link no price', 'manual', true, true) returning id::text as pz \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PLN1-I', 'PLN1 link inactive', 'manual', true, true) returning id::text as pi \gset
insert into public.product (sku, name, source, is_active, sellable) values ('PLN1-N', 'PLN1 no link', 'manual', true, true) returning id::text as pn \gset
insert into public.product_supplier (product_id, supplier_id, is_active, is_default, source, fixed_cost, cost, supplier_sku) values
  (:'pf'::uuid, :'sup'::uuid, true, true, 'manual', 3, 2.8, 'SUP-F'), (:'pl'::uuid, :'sup'::uuid, true, true, 'manual', null, 1.5, 'SUP-L'),
  (:'pz'::uuid, :'sup'::uuid, true, true, 'manual', null, null, 'SUP-Z'), (:'pi'::uuid, :'sup'::uuid, false, false, 'manual', 9, 9, 'SUP-I');
set local session_replication_role = origin;
select (select string_agg(ps.supplier_sku || ':' || coalesce(trim_scale(ps.fixed_cost)::text, '-') || '/' || coalesce(trim_scale(ps.cost)::text, '-'), ',' order by ps.supplier_sku) from public.product_supplier ps where ps.supplier_id = :'sup'::uuid) as ps_before \gset
select pg_temp.as_user(:'w', format('select public.po_create(%L::uuid, %L::uuid, null, ''pln-1 A'')::text', :'sup', :'wh')) as mk_a \gset
select pg_temp.as_user(:'w', format('select public.po_create(%L::uuid, %L::uuid, null, ''pln-1 B'')::text', :'sup', :'wh')) as mk_b \gset
select pg_temp.j(:'mk_a')->>'id' as po_a, pg_temp.j(:'mk_a')->>'po_number' as po_a_no, pg_temp.j(:'mk_b')->>'id' as po_b \gset
select pg_temp.fns() as fns_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff W · supplier A · products F L Z I N · links (%s) · draft PO %s + B · snapshots', :'ps_before', :'po_a_no'),
  :'w_uid' <> '' and :'sup' <> '' and :'po_a' <> '' and :'po_b' <> '' and :'ps_before' = 'SUP-F:3/2.8,SUP-I:9/9,SUP-L:-/1.5,SUP-Z:-/-', format('%s | %s | %s', left(:'mk_a', 150), left(:'mk_b', 100), :'ps_before'));

\set lines_noprice '[{"sku":"PLN1-F","qty":"2"},{"sku":"PLN1-L","qty":"1"},{"sku":"PLN1-Z","qty":"3"},{"sku":"PLN1-I","qty":"1"},{"sku":"PLN1-N","qty":"4"},{"sku":"NOPE-SKU","qty":"1"},{"sku":"PLN1-F","qty":"0"}]'

\if :{?mig}
\echo '── S0 · D-pre) 결함 판 — 옛 몸 · 가격 없이 미리 보기(옛 결과 담기) · 옛 함수는 price 열쇠를 모른다'
select pg_temp.as_user(:'w', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_a', :'lines_noprice')) as pre_noprice \gset
select pg_temp.as_user(:'w', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_a', '[{"sku":"PLN1-F","qty":"2","price":"2.50"}]')) as pre_price \gset
select pg_temp.chk(format('S0 before the trial: body = 20260918000000 (698d9a56…) · no bad_price key · old preview ignores price (F → 3 fixed) → %s', pg_temp.tr(pg_temp.j(:'pre_price'))),
  :'gate_before' like 'md5=698d9a56db8f590d386a02d495ac0e16 n=1 definer=false acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' and :n_applied = 0
  and pg_temp.tr(pg_temp.j(:'pre_price')) like 'PLN1-F|ok|3|fixed · summary % bad_price=∅ inserted=0', format('%s | %s', :'gate_before', left(:'pre_price', 300)));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: other PO functions md5 unchanged', pg_temp.fns() = :'fns_before', format('before %s | after %s', left(:'fns_before', 300), left(pg_temp.fns(), 300)));
\echo '── T1) 동일성 — 가격 없이 붙이기: 옛 결과와 같은 verdict · unit_price · price_source(새 열쇠 input_price · bad_price 만 다름)'
select pg_temp.as_user(:'w', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_a', :'lines_noprice')) as post_noprice \gset
select pg_temp.chk(format('T1 no price: old = new line by line (%s)', pg_temp.tr(pg_temp.j(:'post_noprice'))),
  replace(pg_temp.tr(pg_temp.j(:'pre_noprice')), 'bad_price=∅', 'bad_price=0') = pg_temp.tr(pg_temp.j(:'post_noprice'))
  and (select jsonb_agg(r - 'input_price' order by (r->>'n')::int) from jsonb_array_elements(pg_temp.j(:'post_noprice')->'lines') r) = (select jsonb_agg(r order by (r->>'n')::int) from jsonb_array_elements(pg_temp.j(:'pre_noprice')->'lines') r)
  and pg_temp.tr(pg_temp.j(:'post_noprice')) = 'PLN1-F|ok|3|fixed ; PLN1-L|ok|1.5|latest ; PLN1-Z|ok|0|none ; PLN1-I|no_link|0|none ; PLN1-N|no_link|0|none ; NOPE-SKU|not_found|-|- ; PLN1-F|duplicate|-|- · summary ok=3 no_link=2 bad_qty=0 bad_price=0 inserted=0',
  format('old %s | new %s', pg_temp.tr(pg_temp.j(:'pre_noprice')), pg_temp.tr(pg_temp.j(:'post_noprice'))));
\else
select pg_temp.chk('P0c confirm run: migration 20261022190351 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() like 'md5=00ad0eadccab6d03bd4ebbe78fe79f76 n=1 %') as landed \gset
\if :landed
\echo '── G1) 실물'
select pg_temp.chk('G1 po_lines_paste body = pln-1 (00ad0ead…) · one overload · security invoker · volatile · ACL unchanged (postgres · authenticated · service_role X · anon none)',
  pg_temp.gate_state() = 'md5=00ad0eadccab6d03bd4ebbe78fe79f76 n=1 definer=false acl={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}'
  and (select p.provolatile = 'v' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') and not has_function_privilege('anon', 'public.po_lines_paste(uuid, jsonb, boolean)', 'execute'), pg_temp.gate_state());

\echo '── T2) 가격 2.50 → pasted · product_supplier 무변(commit)'
\set lines_t2 '[{"sku":"PLN1-F","qty":"2","price":"2.50"},{"sku":"PLN1-L","qty":"1"},{"sku":"PLN1-N","qty":"4","price":" 7 "},{"sku":"PLN1-I","qty":"1","price":"0.75"}]'
select pg_temp.as_user(:'w', format('select public.po_lines_paste(%L::uuid, %L::jsonb, true)::text', :'po_a', :'lines_t2')) as t2 \gset
select (select string_agg(ps.supplier_sku || ':' || coalesce(trim_scale(ps.fixed_cost)::text, '-') || '/' || coalesce(trim_scale(ps.cost)::text, '-'), ',' order by ps.supplier_sku) from public.product_supplier ps where ps.supplier_id = :'sup'::uuid) as ps_after \gset
select pg_temp.chk(format('T2 commit: F 2.50 → pasted · L (no price) → 1.5 latest · N (no link · price " 7 ") → 7 pasted no_link "pasted price used" · I (link inactive · 0.75) → 0.75 pasted · 4 inserted · po_line rows carry those prices · product_supplier unchanged → %s', pg_temp.tr(pg_temp.j(:'t2'))),
  pg_temp.tr(pg_temp.j(:'t2')) = 'PLN1-F|ok|2.5|pasted ; PLN1-L|ok|1.5|latest ; PLN1-N|no_link|7|pasted ; PLN1-I|no_link|0.75|pasted · summary ok=2 no_link=2 bad_qty=0 bad_price=0 inserted=4'
  and (select r->>'message' from jsonb_array_elements(pg_temp.j(:'t2')->'lines') r where r->>'input_sku' = 'PLN1-N') = 'no_product_supplier_link_for_this_supplier — pasted price used'
  and (select r->>'message' from jsonb_array_elements(pg_temp.j(:'t2')->'lines') r where r->>'input_sku' = 'PLN1-I') = 'link_inactive — pasted price used'
  and (select string_agg(p.sku || '=' || trim_scale(l.unit_price), ',' order by l.line_no) from public.po_line l join public.product p on p.id = l.product_id where l.po_id = :'po_a'::uuid) = 'PLN1-F=2.5,PLN1-L=1.5,PLN1-N=7,PLN1-I=0.75'
  and :'ps_after' = :'ps_before',
  format('%s | lines %s | ps %s', left(:'t2', 700), (select string_agg(p.sku || '=' || trim_scale(l.unit_price), ',' order by l.line_no) from public.po_line l join public.product p on p.id = l.product_id where l.po_id = :'po_a'::uuid), :'ps_after'));

\echo '── T3) 0 은 받는다 · 음수 · abc 는 그 줄만 bad_price · 나머지 그대로(미리 보기 → commit)'
\set lines_t3 '[{"sku":"PLN1-Z","qty":"3","price":"0"},{"sku":"PLN1-F","qty":"1","price":"-1"},{"sku":"PLN1-L","qty":"2","price":"abc"},{"sku":"PLN1-N","qty":"1","price":""}]'
select count(*) as n_lines_b0 from public.po_line where po_id = :'po_b'::uuid \gset
select pg_temp.as_user(:'w', format('select public.po_lines_paste(%L::uuid, %L::jsonb, false)::text', :'po_b', :'lines_t3')) as t3p \gset
select count(*) as n_lines_b1 from public.po_line where po_id = :'po_b'::uuid \gset
select pg_temp.as_user(:'w', format('select public.po_lines_paste(%L::uuid, %L::jsonb, true)::text', :'po_b', :'lines_t3')) as t3c \gset
select count(*) as n_lines_b2 from public.po_line where po_id = :'po_b'::uuid \gset
select pg_temp.chk(format('T3 preview = commit verdicts: Z price 0 → 0 pasted · F -1 → bad_price · L abc → bad_price · N "" → no_link 0 none · bad_price 2 · inserted 0 → 2 · po_line %s → %s → %s · T5 preview wrote nothing', :n_lines_b0, :n_lines_b1, :n_lines_b2),
  pg_temp.tr(pg_temp.j(:'t3p')) = 'PLN1-Z|ok|0|pasted ; PLN1-F|bad_price|-|- ; PLN1-L|bad_price|-|- ; PLN1-N|no_link|0|none · summary ok=1 no_link=1 bad_qty=0 bad_price=2 inserted=0'
  and pg_temp.tr(pg_temp.j(:'t3c')) = 'PLN1-Z|ok|0|pasted ; PLN1-F|bad_price|-|- ; PLN1-L|bad_price|-|- ; PLN1-N|no_link|0|none · summary ok=1 no_link=1 bad_qty=0 bad_price=2 inserted=2'
  and (select string_agg(r->>'message', ' / ' order by (r->>'n')::int) from jsonb_array_elements(pg_temp.j(:'t3c')->'lines') r where r->>'verdict' = 'bad_price') = 'price_must_be_zero_or_a_positive_number / price_must_be_zero_or_a_positive_number'
  and :n_lines_b0 = 0 and :n_lines_b1 = 0 and :n_lines_b2 = 2,
  format('preview %s | commit %s', left(:'t3p', 500), left(:'t3c', 500)));

\echo '── T4) 문서 할인 10% 위에 붙인 2.50 — po_detail 의 지불 = round(2.50 × (1 − 10/100), 2)'
select pg_temp.as_user(:'w', format('select public.po_create(%L::uuid, %L::uuid, null, ''pln-1 C'')->>''id''', :'sup', :'wh')) as po_c \gset
select pg_temp.as_user(:'w', format('select public.po_lines_paste(%L::uuid, %L::jsonb, true)::text', :'po_c', '[{"sku":"PLN1-F","qty":"1","price":"2.50"}]')) as t4p \gset
select pg_temp.as_user(:'w', format('select public.po_discount_save(''po'', %L::uuid, %L::jsonb)::text', :'po_c', '{"name": "PLN1 10%", "percent": 10}')) as t4d \gset
select pg_temp.as_user(:'w', format('select public.po_detail(%L::uuid)::text', :'po_c')) as t4 \gset
select round(2.50 * (1 - 10 / 100.0), 2) as expect_net, (select trim_scale(public.po_discount_factor(:'po_c'::uuid))) as factor_fn \gset
select pg_temp.chk(format('T4 PO C: pasted 2.50 × 1 + document discount 10%% → po_detail totals.subtotal 2.5 · discount_factor 0.9 · net_total %s (= round(2.50 × 0.9, 2) in SQL) · line unit_price stays 2.50 (discount is on the document)', :expect_net),
  (pg_temp.j(:'t4')->'totals'->>'subtotal')::numeric = 2.5 and (pg_temp.j(:'t4')->'totals'->>'discount_factor')::numeric = 0.9 and (pg_temp.j(:'t4')->'totals'->>'net_total')::numeric = :expect_net
  and (select (r->>'unit_price')::numeric from jsonb_array_elements(pg_temp.j(:'t4')->'lines') r limit 1) = 2.5 and :'factor_fn' = '0.9' and pg_temp.tr(pg_temp.j(:'t4p')) like 'PLN1-F|ok|2.5|pasted%',
  format('paste %s | disc %s | totals %s', left(:'t4p', 160), left(:'t4d', 160), left((pg_temp.j(:'t4')->'totals')::text, 400)));
\else
select pg_temp.chk('G1 ~ T4 skipped: pln-1 not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 무접촉 — 다른 PO 함수 md5 · po_lines_paste 하나뿐'
select pg_temp.chk('Z1 other PO functions md5 unchanged · po_lines_paste one overload', pg_temp.fns() = :'fns_before' and pg_temp.gate_state() like '% n=1 %', format('before %s | after %s', left(:'fns_before', 300), left(pg_temp.fns(), 300)));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 되돌리기'
select (select count(*) from public.supplier where name like 'PLN1 %') + (select count(*) from public.product where sku like 'PLN1-%') + (select count(*) from public.ims_staff where email like 'pln1-%') as leftovers;
select setval('public.po_number_seq', greatest(coalesce((select max(substring(po_number from '[0-9]+')::bigint) from public.po), 0), :po_seq_last), :'po_seq_called'::boolean) as po_number_seq_reset_to;
select last_value || '|' || is_called as po_seq_after from public.po_number_seq;
