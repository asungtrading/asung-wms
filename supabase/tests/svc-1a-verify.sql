-- svc-1a-verify.sql — 서비스 목록 ref_service + 비용 줄 수량 · 단가 · 서비스(판정 590 · 593 · 596 · 597):
--   ② 결함 판(S0 · 시험 전용) · ① 동일성(옛 호출 열 경우를 \i 앞 · 뒤 · I1 ~ I2 · 시험 전용) · ③ 새 길(N1 ~ N7) · ④ CHECK 직접(C1) · 무접촉(G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021164646_svc_1a_service_list_charge_qty.sql -f supabase/tests/svc-1a-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · I1 · I2 넷은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 13 − 4 + 1 = **10** · MISMATCH 0
--   가짜 재료는 전부 SVC1A · SO 는 so_create(sales)로 · 번호 시퀀스 so_number_seq 는 머리에서 읽고 rollback 뒤 greatest(실제 최대, 머리)
--   ⚠️ 동일성의 각 경우는 pg_temp.trial 이 서브트랜잭션 안에서 돌리고 결과(반환 · 그 오더의 비용 줄 · so_tax_preview · so_detail 합계)를 예외 메시지로 꺼낸 뒤 되감는다

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021164646' \gset
select :n_applied as schema_migrations_rows_for_20261021164646;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select :so_seq_last as so_number_seq_head, :'so_seq_called' as so_called_head, (select max(substring(so_number from '[0-9]+')::bigint) from public.so) as so_max_head;

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
-- uuid · 시각을 지우고 새 칸 다섯을 뺀다(옛 호출 비교용)
create function pg_temp.norm(p text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(coalesce(p, ''), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g'), '"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+"', '"T"', 'g') $$;
create function pg_temp.strip_new(p jsonb) returns jsonb language sql immutable as $$
  select case when p ? 'charge' then jsonb_set(p, '{charge}', (p->'charge') - 'qty' - 'unit_price' - 'service_id' - 'price_set_by' - 'price_set_at') else p end $$;
create function pg_temp.charges_of(p_so uuid) returns text language sql security definer as $$
  select coalesce(string_agg(c.line_no || '|' || c.name || '|' || coalesce(c.description, '-') || '|' || trim_scale(c.amount) || '|' || coalesce(c.tax_rule, '-') || '|' || coalesce(c.account_code, '-') || '|' || coalesce(trim_scale(c.discount_pct)::text, '-') || '|' || coalesce(trim_scale(c.discount_amount)::text, '-'), E'\n' order by c.line_no), '(none)') from public.so_charge c where c.so_id = p_so $$;
create function pg_temp.totals_of(p_so uuid) returns text language sql security definer as $$
  select (public.so_tax_preview(p_so, null, null, 'ordered', null)->'totals')::text || ' ## ' || coalesce((public.so_detail(p_so)->'totals')::text, '-') $$;
-- 한 경우: 서브트랜잭션에서 p_sql 을 돌리고 결과를 꺼낸 뒤 되감는다(쓰기 0)
create function pg_temp.trial(p_claims text, p_sql text, p_so uuid) returns jsonb language plpgsql as $$
declare v_ret text;
begin
  begin
    perform set_config('request.jwt.claims', p_claims, true);
    begin
      execute p_sql into v_ret;
    exception when others then
      v_ret := 'ERR ' || sqlstate || ': ' || sqlerrm;
    end;
    raise exception using errcode = 'P7777', message = jsonb_build_object('ret', v_ret, 'rows', pg_temp.charges_of(p_so), 'totals', pg_temp.totals_of(p_so))::text;
  exception when sqlstate 'P7777' then
    return sqlerrm::jsonb;
  end;
end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'ref_service=' || (to_regclass('public.ref_service') is not null)::text
      || ' qty_col=' || exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so_charge' and column_name = 'qty')::text
      || ' set_args=' || (select max(pronargs) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_charge_set')::text $$;
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'charges=' || (select count(*) || '/' || md5(string_agg(c.id::text || c.amount || c.name || coalesce(c.account_code, '-'), ',' order by c.id)) from public.so_charge c join public.so s on s.id = c.so_id join public.customer cu on cu.id = s.customer_id where cu.name <> 'SVC1A Customer')
      || ' so=' || (select count(*) from public.so s join public.customer cu on cu.id = s.customer_id where cu.name <> 'SVC1A Customer')
      || ' fns=' || (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_charge_remove', 'so_charge_gate', 'so_finalize', 'so_tax_preview', 'so_detail', 'so_invoice_issue', 'shop_order_freight')) $$;

\echo '── M0) 가짜 직원 넷(S sales · SM sales + master · M master · W 없음) · 손님 · 오더 둘(draft D · packed P) · 기존 비용 줄 F0 · 세율 · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1a-s@test.invalid', 'SVC1A S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid, id::text as s_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1a-sm@test.invalid', 'SVC1A SM', 'manager', '["ims","sales","master"]', '{}') returning auth_user_id::text as sm_uid, id::text as sm_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1a-m@test.invalid', 'SVC1A M', 'manager', '["ims","master"]', '{}') returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1a-w@test.invalid', 'SVC1A W', 'worker', '[]', '{}') returning auth_user_id::text as w_uid \gset
\set s  '{"sub":"' :s_uid  '","role":"authenticated"}'
\set sm '{"sub":"' :sm_uid '","role":"authenticated"}'
\set m  '{"sub":"' :m_uid  '","role":"authenticated"}'
\set w  '{"sub":"' :w_uid  '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh from public.ref_warehouse where is_active order by name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name, rate_pct as r13_rate from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as acct153 from public.ref_account where code = '_153_' \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id) values ('SVC1A Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid) returning id::text as cust \gset
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''svc-1a test D'')::text', :'cust', :'wh')) as d0 \gset
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''svc-1a test P'')::text', :'cust', :'wh')) as p0 \gset
reset role;
select coalesce(pg_temp.j(:'d0')->>'id', '00000000-0000-0000-0000-000000000000') as so_d, coalesce(pg_temp.j(:'p0')->>'id', '00000000-0000-0000-0000-000000000000') as so_p \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id in (:'so_d'::uuid, :'so_p'::uuid);
update public.so set status = 'packed' where id = :'so_p'::uuid;
insert into public.so_charge (so_id, line_no, name, amount, tax_rule, account_code) values (:'so_d'::uuid, 1, 'Freight', 20, :'r13_name', '_99_') returning id::text as f0 \gset
set local session_replication_role = origin;
select pg_temp.real_rows() as real_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff ×4 · customer · draft %s · packed order · charge F0 20 · tax %s %s%% · account _153_ · snapshots taken', pg_temp.j(:'d0')->>'so_number', :'r13_name', trim_scale(:'r13_rate'::numeric)),
  :'d0' not like 'ERR%' and :'p0' not like 'ERR%' and :'f0' <> '' and :'acct153' <> '' and :'real_before' <> '', format('d0 %s | p0 %s', left(:'d0', 120), left(:'p0', 120)));

\echo '── 동일성 재료 — 옛 호출 열 경우(화면 so.html Add a charge 꼴 · packed 비용 · Shopify 운임 · 할인 · 고치기 · 지우기 · 거부 셋)'
create temp table t_ident (phase text, c text, ret text, rows_ text, totals text);
grant all on t_ident to authenticated;
create function pg_temp.ident(p_phase text) returns int language plpgsql as $$
declare v jsonb; v_n int := 0; c jsonb;
begin
  for c in select x from jsonb_array_elements(current_setting('svc1a.cases')::jsonb) as x loop
    v := pg_temp.trial(c->>'claims', c->>'sql', (c->>'so')::uuid);
    insert into t_ident values (p_phase, c->>'c',
      case when left(v->>'ret', 1) = '{' then pg_temp.norm(pg_temp.strip_new((v->>'ret')::jsonb)::text) else pg_temp.norm(v->>'ret') end, v->>'rows', v->>'totals');
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;
select set_config('svc1a.cases', jsonb_build_array(
  jsonb_build_object('c', '1 add Freight 25 (screen shape · account null)', 'claims', :'s', 'so', :'so_d', 'sql', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Freight'', p_amount => 25, p_charge_id => null, p_description => null, p_discount_pct => null, p_discount_amount => null, p_account_id => null)::text', :'so_d')),
  jsonb_build_object('c', '2 add with 10% discount', 'claims', :'s', 'so', :'so_d', 'sql', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Freight'', p_amount => 30, p_discount_pct => 10)::text', :'so_d')),
  jsonb_build_object('c', '3 add with 5.00 discount and account _153_', 'claims', :'s', 'so', :'so_d', 'sql', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Handling'', p_amount => 12.5, p_description => ''by hand'', p_discount_amount => 5, p_account_id => %L::uuid)::text', :'so_d', :'acct153')),
  jsonb_build_object('c', '4 edit F0 (name · amount · description)', 'claims', :'s', 'so', :'so_d', 'sql', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Freight-edited'', p_amount => 22.75, p_charge_id => %L::uuid, p_description => ''edited'')::text', :'so_d', :'f0')),
  jsonb_build_object('c', '5 tax rule on the charge · refused', 'claims', :'s', 'so', :'so_d', 'sql', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Freight'', p_amount => 25, p_tax_rule => ''GST (Sale)'')::text', :'so_d')),
  jsonb_build_object('c', '6 negative amount · refused', 'claims', :'s', 'so', :'so_d', 'sql', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Freight'', p_amount => -1)::text', :'so_d')),
  jsonb_build_object('c', '7 packed order as sales only · refused', 'claims', :'s', 'so', :'so_p', 'sql', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Packing fee'', p_amount => 8)::text', :'so_p')),
  jsonb_build_object('c', '8 packed order as sales + master · added', 'claims', :'sm', 'so', :'so_p', 'sql', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Packing fee'', p_amount => 8)::text', :'so_p')),
  jsonb_build_object('c', '9 Shopify freight (positional 9 args · free shipping)', 'claims', :'s', 'so', :'so_d', 'sql', format('select public.shop_order_freight(%L::uuid, ''retail'', ''#SVC1A'', %L::jsonb)::text', :'so_d', '{"title":"Standard","originalPriceSet":{"shopMoney":{"amount":"15.00"}},"discountedPriceSet":{"shopMoney":{"amount":"0.00"}}}')),
  jsonb_build_object('c', 'A remove F0', 'claims', :'s', 'so', :'so_d', 'sql', format('select public.so_charge_remove(%L::uuid)::text', :'f0'))
)::text, true) as cases_set;

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — ref_service 없음 · so_charge 에 qty 칸 없음 · so_charge_set 인자 9'
select pg_temp.chk('S0 before the trial: no ref_service · no so_charge.qty · so_charge_set takes 9 args · not in schema_migrations', :'gate_before' = 'ref_service=false qty_col=false set_args=9' and :n_applied = 0, format('gate %s | n_applied %s', :'gate_before', :n_applied));
\echo '── I0) 동일성 — 옛 판으로 열 경우(되감김)'
select pg_temp.ident('old') as old_cases \gset
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: other charge functions (remove · gate · finalize · tax_preview · detail · invoice_issue · shop_order_freight) unchanged · real rows unchanged', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));
\echo '── I1 ~ I2) 동일성 — 새 판으로 같은 열 경우 · 비교'
select pg_temp.ident('new') as new_cases \gset
select count(*) as n_cases, count(*) filter (where o.ret = n.ret) as same_ret, count(*) filter (where o.rows_ = n.rows_) as same_rows, count(*) filter (where o.totals = n.totals) as same_totals,
       coalesce(string_agg(o.c || ': ' || left(o.ret, 160) || ' ≠ ' || left(n.ret, 160), ' | ') filter (where o.ret <> n.ret or o.rows_ <> n.rows_ or o.totals <> n.totals), '-') as diffs
  from t_ident o join t_ident n on n.c = o.c and n.phase = 'new' where o.phase = 'old' \gset
select (select count(*) from t_ident where phase = 'old' and ret like 'ERR%') as n_err, (select string_agg(c || '=' || left(ret, 220), ' | ' order by c) from t_ident where phase = 'old' and ret like 'ERR%') as errs \gset
select pg_temp.chk(format('I1 old calls: %s of %s cases give the same return (new null columns stripped · uuid/time masked) · same charge rows · same so_tax_preview and so_detail totals', :same_ret, :n_cases),
  :n_cases = 10 and :same_ret = 10 and :same_rows = 10 and :same_totals = 10, :'diffs');
select pg_temp.chk('I2 the three refusals are the old sentences (tax rule · negative · packed without master) and the seven others succeed', :n_err = 3 and :'errs' like '%5 tax rule%follow the order tax rule%' and :'errs' like '%6 negative%cannot be negative%' and :'errs' like '%7 packed%master permission%', :'errs');
\else
select pg_temp.chk('P0c confirm run: migration 20261021164646 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() = 'ref_service=true qty_col=true set_args=12') as landed \gset
\if :landed
\echo '── G1) 실물 — ref_service 정책 셋(select true · insert/update master) · anon 0 · authenticated delete 0 · 계정 기본 _153_ · so_charge 새 칸 다섯 · CHECK 여섯'
select pg_temp.chk('G1 ref_service: RLS on · 3 policies · anon none · authenticated no delete · account default = _153_ · so_charge 5 new columns · 6 new checks',
  (select relrowsecurity from pg_class where oid = 'public.ref_service'::regclass) and (select count(*) from pg_policies where tablename = 'ref_service') = 3
  and not has_table_privilege('anon', 'public.ref_service', 'select') and not has_table_privilege('authenticated', 'public.ref_service', 'delete')
  and (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'ref_service' and column_name = 'account_id') = format('%L::uuid', :'acct153')
  and (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_charge' and column_name in ('qty', 'unit_price', 'service_id', 'price_set_by', 'price_set_at')) = 5
  and (select count(*) from pg_constraint where conrelid = 'public.so_charge'::regclass and conname ~ '^so_charge_(qty_pair|qty_pos|unit_price|qty_amount|service_qty|price_set_pair)_ck$') = 6, pg_temp.gate_state());

\echo '── N1) 서비스 목록 — M(master)이 「SVC1A Prep service」 0.45 를 만든다(계정 비우면 _153_) · S(sales)는 못 만든다 · S 는 읽는다 · M 이 단가를 바꾼다 · 이름 바꾸기는 막힌다 · 지우기는 안 된다'
set local role authenticated;
select pg_temp.as_user(:'m', 'insert into public.ref_service (name, unit_price) values (''SVC1A Prep service'', 0.45) returning id::text') as svc \gset
select pg_temp.as_user(:'m', 'insert into public.ref_service (name, unit_price, is_active) values (''SVC1A Old service'', 1.00, false) returning id::text') as svc_off \gset
select pg_temp.as_user(:'s', 'insert into public.ref_service (name, unit_price) values (''SVC1A Sales try'', 1) returning id::text') as n1_sales_ins \gset
select pg_temp.as_user(:'s', 'select count(*)::text from public.ref_service where name like ''SVC1A%''') as n1_sales_sel \gset
select pg_temp.as_user(:'m', format('update public.ref_service set unit_price = 0.50 where id = %L::uuid returning unit_price::text', :'svc')) as n1_price \gset
select pg_temp.as_user(:'m', format('update public.ref_service set unit_price = 0.45 where id = %L::uuid returning unit_price::text', :'svc')) as n1_price_back \gset
select pg_temp.as_user(:'m', format('update public.ref_service set name = ''SVC1A Renamed'' where id = %L::uuid returning name', :'svc')) as n1_rename \gset
select pg_temp.as_user(:'m', format('delete from public.ref_service where id = %L::uuid returning id::text', :'svc')) as n1_delete \gset
select pg_temp.as_user(:'m', 'insert into public.ref_service (name, unit_price) values ('' padded '', 1) returning id::text') as n1_pad \gset
select pg_temp.as_user(:'m', 'insert into public.ref_service (name, unit_price) values (''svc1a prep SERVICE'', 1) returning id::text') as n1_dup \gset
reset role;
select pg_temp.chk('N1 service list: master creates (account defaults to _153_) · sales cannot insert (RLS 42501) · sales reads 2 · master changes the price · rename refused (IM538) · delete refused (42501) · padded name refused (ref_service_name_ck) · case-insensitive duplicate refused (23505)',
  :'svc' ~ '^[0-9a-f-]{36}$' and (select account_id::text from public.ref_service where id = :'svc'::uuid) = :'acct153'
  and :'n1_sales_ins' like 'ERR 42501%' and :'n1_sales_sel' = '2' and :'n1_price' = '0.50' and :'n1_price_back' = '0.45'
  and :'n1_rename' like 'ERR IM538%' and :'n1_delete' like 'ERR 42501%' and :'n1_pad' like 'ERR 23514%' and :'n1_pad' like '%ref_service_name_ck%' and :'n1_dup' like 'ERR 23505%',
  format('svc %s | sales_ins %s | sel %s | price %s/%s | rename %s | delete %s | pad %s | dup %s', :'svc', left(:'n1_sales_ins', 80), :'n1_sales_sel', :'n1_price', :'n1_price_back', left(:'n1_rename', 80), left(:'n1_delete', 80), left(:'n1_pad', 100), left(:'n1_dup', 80)));

\echo '── N2) 서비스 줄 — S 가 draft D 에 service + qty 1200 → 단가 0.45 · 금액 540.00 · 이름 · 계정 _153_ · price_set_by null · 세금 = round(540 × 13 %, 2) = 70.20'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 1200, p_service_id => %L::uuid)::text', :'so_d', :'svc')) as n2 \gset
reset role;
select coalesce(pg_temp.j(:'n2')->'charge'->>'id', '00000000-0000-0000-0000-000000000000') as ch1 \gset
select (select jsonb_agg(c) from jsonb_array_elements(public.so_tax_preview(:'so_d'::uuid, null, null, 'ordered', null)->'charges') c where (c->>'name') = 'SVC1A Prep service') as n2_tax \gset
select pg_temp.chk('N2 service line: qty 1200 · unit_price 0.45 · amount 540.00 · name "SVC1A Prep service" · account _153_ · service_id set · price_set_by null · tax rule = order · so_tax_preview tax 70.20',
  :'n2' not like 'ERR%' and (select c.qty || '|' || trim_scale(c.unit_price) || '|' || c.amount || '|' || c.name || '|' || c.account_code || '|' || (c.service_id = :'svc'::uuid) || '|' || coalesce(c.price_set_by::text, 'null') || '|' || c.tax_rule from public.so_charge c where c.id = :'ch1'::uuid)
      = format('1200|0.45|540.00|SVC1A Prep service|_153_|true|null|%s', :'r13_name')
  and (pg_temp.j(:'n2_tax')->0->>'tax')::numeric = round(540 * :'r13_rate'::numeric / 100, 2),
  format('n2 %s | tax %s', left(:'n2', 300), :'n2_tax'));

\echo '── N3) 손 단가 — 같은 줄을 0.38 로 → 금액 456.00 · price_set_by = S · 다시 목록 단가 0.45 로 → price_set_by null · 서비스 없이 수량 × 단가(3 × 9.99 = 29.97) → price_set_by = S · 계정 _99_'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_charge_id => %L::uuid, p_qty => 1200, p_unit_price => 0.38, p_service_id => %L::uuid)::text', :'so_d', :'ch1', :'svc')) as n3a \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_charge_id => %L::uuid, p_qty => 1200, p_service_id => %L::uuid)::text', :'so_d', :'ch1', :'svc')) as n3b \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Labelling'', p_amount => null, p_qty => 3, p_unit_price => 9.99)::text', :'so_d')) as n3c \gset
reset role;
select pg_temp.chk('N3 hand price: 0.38 → amount 456.00 · price_set_by S (+ at) · back to list price → price_set_by null · no-service 3 × 9.99 → 29.97 · price_set_by S · account _99_',
  :'n3a' not like 'ERR%' and (pg_temp.j(:'n3a')->'charge'->>'amount')::numeric = 456.00 and pg_temp.j(:'n3a')->'charge'->>'price_set_by' = :'s_id' and pg_temp.j(:'n3a')->'charge'->>'price_set_at' is not null
  and :'n3b' not like 'ERR%' and (pg_temp.j(:'n3b')->'charge'->>'amount')::numeric = 540.00 and pg_temp.j(:'n3b')->'charge'->>'price_set_by' is null and pg_temp.j(:'n3b')->'charge'->>'price_set_at' is null
  and :'n3c' not like 'ERR%' and (pg_temp.j(:'n3c')->'charge'->>'amount')::numeric = 29.97 and pg_temp.j(:'n3c')->'charge'->>'price_set_by' = :'s_id' and pg_temp.j(:'n3c')->'charge'->>'account_code' = '_99_',
  format('a %s | b %s | c %s', left(:'n3a', 200), left(:'n3b', 200), left(:'n3c', 200)));

\echo '── N4) 거부 — qty 0 · −1 · unit_price −0.1 · qty 만 · unit_price 만 · 금액이 다름 · 꺼진 서비스 · 없는 서비스 · 세금 칸(593) · 옛 꼴로 수량 줄 고치기'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''x'', p_amount => null, p_qty => 0, p_unit_price => 1)::text', :'so_d')) as r_q0 \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''x'', p_amount => null, p_qty => -1, p_unit_price => 1)::text', :'so_d')) as r_qn \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''x'', p_amount => null, p_qty => 1, p_unit_price => -0.1)::text', :'so_d')) as r_pn \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''x'', p_amount => null, p_qty => 5)::text', :'so_d')) as r_qonly \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''x'', p_amount => null, p_unit_price => 5)::text', :'so_d')) as r_ponly \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''x'', p_amount => 10, p_qty => 2, p_unit_price => 4)::text', :'so_d')) as r_amt \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 1, p_service_id => %L::uuid)::text', :'so_d', :'svc_off')) as r_off \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 1, p_service_id => gen_random_uuid())::text', :'so_d')) as r_none \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 1, p_service_id => %L::uuid, p_tax_rule => ''GST (Sale)'')::text', :'so_d', :'svc')) as r_tax \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => ''Prep'', p_amount => 500, p_charge_id => %L::uuid)::text', :'so_d', :'ch1')) as r_oldedit \gset
select pg_temp.as_user(:'w', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 1, p_service_id => %L::uuid)::text', :'so_d', :'svc')) as r_w \gset
reset role;
select pg_temp.chk('N4 refusals: qty 0 · qty −1 · price −0.1 · qty only · price only · amount ≠ qty × price · switched-off service · unknown service · tax rule (593 sentence) · old-shape edit of a qty line · no sales key — nothing written',
  :'r_q0' like '%Quantity must be more than 0%' and :'r_qn' like '%Quantity must be more than 0%' and :'r_pn' like '%unit price cannot be negative%'
  and :'r_qonly' like '%needs both qty and unit_price%' and :'r_ponly' like '%needs both qty and unit_price%' and :'r_amt' like '%does not match 2 × 4%'
  and :'r_off' like '%is switched off%' and :'r_none' like '%Service not found%' and :'r_tax' like '%follow the order tax rule%' and :'r_oldedit' like '%quantity × unit price line%' and :'r_w' like '%cannot change sales data%'
  and (select count(*) from public.so_charge where so_id = :'so_d'::uuid) = 3,
  format('q0 %s | qn %s | pn %s | qonly %s | ponly %s | amt %s | off %s | none %s | tax %s | oldedit %s | w %s', left(:'r_q0', 70), left(:'r_qn', 70), left(:'r_pn', 70), left(:'r_qonly', 70), left(:'r_ponly', 70), left(:'r_amt', 90), left(:'r_off', 70), left(:'r_none', 60), left(:'r_tax', 70), left(:'r_oldedit', 90), left(:'r_w', 70)));

\echo '── N5) 할인 · 합계 — 서비스 줄에 10 % 할인(옛 할인 칸 그대로) · so_tax_preview charges_amount = Σ 비용 줄 · so_detail 합계와 같다'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_charge_id => %L::uuid, p_qty => 1200, p_service_id => %L::uuid, p_discount_pct => 10)::text', :'so_d', :'ch1', :'svc')) as n5 \gset
reset role;
select pg_temp.chk('N5 service line with a 10% discount: discount 54.00 · net 486.00 · so_tax_preview charges_amount = Σ amounts (20 + 540 + 29.97)',
  :'n5' not like 'ERR%' and (pg_temp.j(:'n5')->'charge'->>'discount')::numeric = 54.00 and (pg_temp.j(:'n5')->'charge'->>'net')::numeric = 486.00
  and (public.so_tax_preview(:'so_d'::uuid, null, null, 'ordered', null)->'totals'->>'charges_amount')::numeric = (select sum(amount) from public.so_charge where so_id = :'so_d'::uuid),
  format('n5 %s | totals %s', left(:'n5', 200), public.so_tax_preview(:'so_d'::uuid, null, null, 'ordered', null)->'totals'));

\echo '── C1) CHECK 직접 — 한 번에 하나만 어기는 행(제약 이름까지)'
create function pg_temp.ins(p_sql text) returns text language plpgsql as $$
declare v_c text;
begin
  execute p_sql;
  return 'inserted';
exception when check_violation then
  get stacked diagnostics v_c = constraint_name;
  return 'CHECK ' || v_c;
end $$;
select pg_temp.ins(format('insert into public.so_charge (so_id, line_no, name, amount, qty, unit_price) values (%L::uuid, 91, ''c1'', 10.00, 2, 4)', :'so_d')) as c_amt,
       pg_temp.ins(format('insert into public.so_charge (so_id, line_no, name, amount, qty) values (%L::uuid, 92, ''c2'', 8, 2)', :'so_d')) as c_pair,
       pg_temp.ins(format('insert into public.so_charge (so_id, line_no, name, amount, qty, unit_price) values (%L::uuid, 93, ''c3'', 0, 0, 1)', :'so_d')) as c_pos,
       pg_temp.ins(format('insert into public.so_charge (so_id, line_no, name, amount, service_id) values (%L::uuid, 94, ''c4'', 5, %L::uuid)', :'so_d', :'svc')) as c_svc,
       pg_temp.ins(format('insert into public.so_charge (so_id, line_no, name, amount, qty, unit_price, price_set_by) values (%L::uuid, 95, ''c5'', 8, 2, 4, %L::uuid)', :'so_d', :'s_id')) as c_ps,
       pg_temp.ins(format('insert into public.so_charge (so_id, line_no, name, amount, qty, unit_price) values (%L::uuid, 96, ''c6'', 8.00, 2, 4)', :'so_d')) as c_ok \gset
select pg_temp.chk('C1 checks by name: amount ≠ round(qty × price) → so_charge_qty_amount_ck · qty without price → so_charge_qty_pair_ck · qty 0 → so_charge_qty_pos_ck · service without qty → so_charge_service_qty_ck · price_set_by without at → so_charge_price_set_pair_ck · a correct row inserts',
  :'c_amt' = 'CHECK so_charge_qty_amount_ck' and :'c_pair' = 'CHECK so_charge_qty_pair_ck' and :'c_pos' = 'CHECK so_charge_qty_pos_ck' and :'c_svc' = 'CHECK so_charge_service_qty_ck' and :'c_ps' = 'CHECK so_charge_price_set_pair_ck' and :'c_ok' = 'inserted',
  format('%s | %s | %s | %s | %s | %s', :'c_amt', :'c_pair', :'c_pos', :'c_svc', :'c_ps', :'c_ok'));

\echo '── N6) 화면 재료 — 반환 원문'
select 'so_charge_set service add: ' || :'n2' as shape union all select 'so_charge_set hand price: ' || :'n3a' union all select 'refusal old-shape edit: ' || :'r_oldedit';
\else
select pg_temp.chk('G1 ~ C1 skipped: svc-1a not landed', false, 'not landed — nothing to exercise');
\endif

\echo '── Z1) 실제 행 무접촉(SVC1A 손님 오더 제외)'
select pg_temp.chk('Z1 real rows untouched (other orders'' charges · orders · charge functions)', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · so_number_seq 되돌리기'
select (select count(*) from public.customer where name = 'SVC1A Customer') + (select count(*) from public.ims_staff where email like 'svc1a-%') as fake_traces_left, to_regclass('public.ref_service') is null as ref_service_gone_or_never_landed;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select last_value as so_seq_last_after, is_called as so_seq_called_after from public.so_number_seq;
