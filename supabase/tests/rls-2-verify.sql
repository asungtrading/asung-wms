-- rls-2-verify.sql — inv_config 쓰기 닫기(판정 568 · 572 ~ 574): 결함 재현(S0) · 직접 쓰기 거부(S1) · 창구 ims_config_set 허용 길(S2) · 열쇠/거부 키(S3) · changed_elsewhere(S4) · 값 검사는 guard 문장 그대로(S5) · service_role · postgres 길 그대로(S6) · 끝 rollback 뒤 설정 값 원래대로(Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261020210026_rls_2_config_write_gate.sql -f supabase/tests/rls-2-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 는 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더
--   가짜 재료는 직원 셋(rls2-*@test.invalid)뿐 · 설정 값은 트랜잭션 안에서만 바뀌고 rollback 으로 돌아온다(Z1 이 begin 전 md5 와 비교)

\echo '── db_role · schema_migrations · 설정 41 행 md5(begin 전)'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261020210026' \gset
select :n_applied as schema_migrations_rows_for_20261020210026;
select count(*) as n_cfg0, md5(string_agg(c.key || '|' || c.value || '|' || coalesce(c.updated_at::text, '') || '|' || coalesce(c.updated_by::text, ''), ',' order by c.key)) as md5_cfg0 from public.inv_config c \gset

begin;
set local statement_timeout = '120s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');   -- 0 행 returning 은 null — \gset 이 변수를 비워 다음 식이 깨진다
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.v(p_key text) returns text language sql security definer as $$ select c.value from public.inv_config c where c.key = p_key $$;
create function pg_temp.set(p_key text, p_value text, p_old text) returns text language plpgsql as $$
begin
  return public.ims_config_set(p_key, p_value, p_old)::text;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'auth_all=' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'inv_config' and policyname = 'auth_all')
      || ' select_pol=' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'inv_config' and cmd = 'SELECT' and roles::text ~ 'authenticated')
      || ' other_pol=' || (select count(*) from pg_policies where schemaname = 'public' and tablename = 'inv_config' and cmd <> 'SELECT')
      || ' auth_write_grants=' || (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'inv_config' and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE'))
      || ' auth_select=' || (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'inv_config' and grantee = 'authenticated' and privilege_type = 'SELECT')
      || ' service_role_write=' || (select count(*) from information_schema.role_table_grants where table_schema = 'public' and table_name = 'inv_config' and grantee = 'service_role' and privilege_type in ('INSERT', 'UPDATE', 'DELETE'))
      || ' set_fn=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ims_config_set' and p.prosecdef and coalesce(p.proacl::text, '') ~ 'authenticated' and coalesce(p.proacl::text, '') !~ 'service_role')
      || ' guard_trg=' || (select count(*) from pg_trigger t where t.tgrelid = 'public.inv_config'::regclass and t.tgname = 'inv_config_guard' and not t.tgisinternal) $$;

\echo '── M0) 직원 셋(admin · master manager · ims 만 worker) · 지금 값 몇 개 · guard 몸 md5'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls2-admin@test.invalid', 'RLS2 admin', 'admin', '["ims"]', '{}') returning auth_user_id::text as g_adm \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls2-master@test.invalid', 'RLS2 master', 'manager', '["ims","master"]', '{}') returning auth_user_id::text as g_mas \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rls2-worker@test.invalid', 'RLS2 worker', 'worker', '["ims"]', '{}') returning auth_user_id::text as g_wrk \gset
\set c_adm '{"sub":"' :g_adm '","role":"authenticated"}'
\set c_mas '{"sub":"' :g_mas '","role":"authenticated"}'
\set c_wrk '{"sub":"' :g_wrk '","role":"authenticated"}'
select pg_temp.v('base_currency') as v_base, pg_temp.v('so_surcharge_account_code') as v_sur, pg_temp.v('mail_backorder_min_fill_pct') as v_pct, pg_temp.v('doc_website') as v_web, pg_temp.v('mail_enabled') as v_mail, pg_temp.v('so_backorder_expire_days') as v_exp, pg_temp.v('so_invoice_unit_display') as v_unit, pg_temp.v('db_role') as v_role \gset
select md5(p.prosrc) as guard_md5_before from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_config_guard' \gset
select pg_temp.chk(format('M0 staff ×3 · %s config rows · base %s · surcharge %s · min_fill %s · website %s · mail %s · expire %s · unit %s · db_role %s', :n_cfg0, :'v_base', :'v_sur', :'v_pct', :'v_web', :'v_mail', :'v_exp', :'v_unit', :'v_role'),
  :'g_adm' <> '' and :'g_mas' <> '' and :'g_wrk' <> '' and :n_cfg0 >= 41 and :'v_base' <> '' and :'v_pct' ~ '^[0-9]+$' and :'v_exp' ~ '^[0-9]+$' and :'guard_md5_before' <> '', 'see M0');

\if :{?mig}
\echo '── S0) 결함 재현(시험 전용) — ims 만 가진 worker 가 base_currency · so_surcharge_account_code 를 직접 update 하면 들어간다(guard 가 안 보는 키) · auth_all · 쓰기 grant 있음'
select pg_temp.gate_state() as gate_before \gset
set local role authenticated;
select set_config('request.jwt.claims', :'c_wrk', true) as claims;
select pg_temp.run('update public.inv_config set value = ''XXX'' where key = ''base_currency'' returning value') as s0_base \gset
select pg_temp.run('update public.inv_config set value = ''_0_'' where key = ''so_surcharge_account_code'' returning value') as s0_sur \gset
reset role;
update public.inv_config set value = :'v_base' where key = 'base_currency';
update public.inv_config set value = :'v_sur' where key = 'so_surcharge_account_code';
select pg_temp.chk('S0 before the trial: an ims-only worker changed base_currency and so_surcharge_account_code directly (the defect — the guard does not look at these keys) · auth_all present · write grants present · no ims_config_set · not in schema_migrations',
  :'s0_base' = 'XXX' and :'s0_sur' = '_0_' and :'gate_before' like 'auth_all=1 %' and :'gate_before' !~ 'auth_write_grants=0 ' and :'gate_before' ~ 'set_fn=0 ' and :n_applied = 0 and pg_temp.v('base_currency') = :'v_base',
  format('base %s | sur %s | gate %s | n_applied %s', left(:'s0_base', 80), left(:'s0_sur', 80), :'gate_before', :n_applied));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: inv_config_guard body byte-identical (ruling 573) · guard trigger still on the table',
  (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_config_guard') = :'guard_md5_before' and pg_temp.gate_state() ~ 'guard_trg=1', pg_temp.gate_state());
\else
select pg_temp.chk('P0c confirm run: migration 20261020210026 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() like 'auth_all=0 select_pol=1 %' and to_regprocedure('public.ims_config_set(text, text, text)') is not null) as landed \gset
\if :landed
\echo '── G1) 실물 — 정책 select 하나 · 쓰기 정책 0 · authenticated 쓰기 grant 0 · select 1 · service_role 쓰기 3 · 창구 definer · authenticated 만 실행 · guard 트리거 그대로'
select pg_temp.gate_state() as gate \gset
select pg_temp.chk('G1 gate: auth_all 0 · select policy 1 · other 0 · authenticated write grants 0 · select 1 · service_role insert/update/delete 3 · ims_config_set definer (authenticated only) · guard trigger 1',
  :'gate' = 'auth_all=0 select_pol=1 other_pol=0 auth_write_grants=0 auth_select=1 service_role_write=3 set_fn=1 guard_trg=1', :'gate');

\echo '── S1) 직접 쓰기 거부 — worker · master 둘 다: update · insert · delete → 42501 permission denied for table inv_config · select 는 된다'
set local role authenticated;
select set_config('request.jwt.claims', :'c_wrk', true) as claims;
select pg_temp.run('update public.inv_config set value = ''XXX'' where key = ''base_currency'' returning value') as s1_upd \gset
select pg_temp.run('insert into public.inv_config (key, value) values (''rls2_new_key'', ''x'') returning key') as s1_ins \gset
select pg_temp.run('delete from public.inv_config where key = ''so_surcharge_account_code'' returning key') as s1_del \gset
select pg_temp.run('select count(*)::text from public.inv_config') as s1_sel \gset
select set_config('request.jwt.claims', :'c_mas', true) as claims;
select pg_temp.run('update public.inv_config set value = ''55'' where key = ''mail_backorder_min_fill_pct'' returning value') as s1_upd2 \gset
reset role;
select pg_temp.chk('S1 direct writes refused: worker update · insert · delete and master update → 42501 "permission denied for table inv_config" · select still works · nothing changed',
  :'s1_upd' like 'ERR 42501%' and :'s1_upd' like '%permission denied for table inv_config%' and :'s1_ins' like 'ERR 42501%' and :'s1_del' like 'ERR 42501%' and :'s1_upd2' like 'ERR 42501%' and :'s1_upd2' like '%permission denied for table inv_config%'
  and :'s1_sel' ~ '^[0-9]+$' and pg_temp.v('base_currency') = :'v_base' and pg_temp.v('mail_backorder_min_fill_pct') = :'v_pct' and (select count(*) from public.inv_config where key = 'rls2_new_key') = 0,
  format('upd %s | ins %s | del %s | sel %s | upd2 %s', left(:'s1_upd', 90), left(:'s1_ins', 90), left(:'s1_del', 90), :'s1_sel', left(:'s1_upd2', 90)));

\echo '── S2) 창구 허용 길 — master: min_fill_pct +1(old = 지금 값 · changed · updated_by_name) · doc_website 같은 값(changed false) · so_invoice_unit_display net · admin: mail_enabled 끄고 다시 켬 · so_backorder_expire_days +1(supervisor 이상) · p_old null 은 검사 안 함'
set local role authenticated;
select set_config('request.jwt.claims', :'c_mas', true) as claims;
select pg_temp.set('mail_backorder_min_fill_pct', (:'v_pct'::int + 1)::text, :'v_pct') as s2_pct \gset
select pg_temp.set('doc_website', :'v_web', :'v_web') as s2_web \gset
select pg_temp.set('so_invoice_unit_display', 'net', :'v_unit') as s2_unit \gset
select set_config('request.jwt.claims', :'c_adm', true) as claims;
select pg_temp.set('mail_enabled', case when :'v_mail' = 'on' then 'off' else 'on' end, :'v_mail') as s2_m1 \gset
select pg_temp.set('mail_enabled', :'v_mail', null) as s2_m2 \gset
select pg_temp.set('so_backorder_expire_days', (:'v_exp'::int + 1)::text, :'v_exp') as s2_exp \gset
reset role;
select pg_temp.chk('S2 gate paths: master min_fill_pct +1 (changed · updated_by_name RLS2 master · edit_level master) · same doc_website → changed false · unit_display net · admin mail_enabled toggled and restored (admin · p_old null skips the check) · expire_days +1 (supervisor level) · values landed · updated_by filled',
  pg_temp.j(:'s2_pct')->>'changed' = 'true' and pg_temp.j(:'s2_pct')->>'value' = (:'v_pct'::int + 1)::text and pg_temp.j(:'s2_pct')->>'old_value' = :'v_pct' and pg_temp.j(:'s2_pct')->>'updated_by_name' = 'RLS2 master' and pg_temp.j(:'s2_pct')->>'edit_level' = 'master'
  and pg_temp.j(:'s2_web')->>'changed' = 'false' and pg_temp.j(:'s2_web')->>'value' = :'v_web'
  and pg_temp.j(:'s2_unit')->>'changed' = 'true' and pg_temp.v('so_invoice_unit_display') = 'net'
  and pg_temp.j(:'s2_m1')->>'changed' = 'true' and pg_temp.j(:'s2_m1')->>'edit_level' = 'admin' and pg_temp.j(:'s2_m2')->>'changed' = 'true' and pg_temp.v('mail_enabled') = :'v_mail' and pg_temp.j(:'s2_m2')->>'updated_by_name' = 'RLS2 admin'
  and pg_temp.j(:'s2_exp')->>'changed' = 'true' and pg_temp.j(:'s2_exp')->>'edit_level' = 'supervisor' and pg_temp.v('so_backorder_expire_days') = (:'v_exp'::int + 1)::text
  and (select s.name from public.inv_config c join public.ims_staff s on s.id = c.updated_by where c.key = 'mail_backorder_min_fill_pct') = 'RLS2 master'
  and (select c.updated_at > now() - interval '1 minute' from public.inv_config c where c.key = 'mail_backorder_min_fill_pct'),
  format('pct %s | web %s | unit %s | m1 %s | m2 %s | exp %s', left(:'s2_pct', 200), left(:'s2_web', 120), left(:'s2_unit', 120), left(:'s2_m1', 120), left(:'s2_m2', 120), left(:'s2_exp', 160)));

\echo '── S3) 열쇠 · 거부 키 — worker → master 키 거부 · master → admin 키 거부 · master(manager) → 잠긴 키 거부 · admin → db_role · base_currency · doc_public_base_url · customer_default_currency_code 거부(a migration or psql) · 없는 키 · 빈 값 · 직원 아닌 로그인'
set local role authenticated;
select set_config('request.jwt.claims', :'c_wrk', true) as claims;
select pg_temp.set('mail_backorder_min_fill_pct', '60', null) as s3_w1 \gset
select pg_temp.set('doc_website', 'x.test', null) as s3_w2 \gset
select set_config('request.jwt.claims', :'c_mas', true) as claims;
select pg_temp.set('mail_enabled', 'off', null) as s3_m1 \gset
select pg_temp.set('so_backorder_expire_days', '5', null) as s3_m2 \gset
select set_config('request.jwt.claims', :'c_adm', true) as claims;
select pg_temp.set('db_role', 'production', null) as s3_a1 \gset
select pg_temp.set('base_currency', 'USD', null) as s3_a2 \gset
select pg_temp.set('doc_public_base_url', 'https://x.test', null) as s3_a3 \gset
select pg_temp.set('customer_default_currency_code', 'USD', null) as s3_a4 \gset
select pg_temp.set('rls2_no_such_key', 'x', null) as s3_a5 \gset
select pg_temp.set('doc_website', null, null) as s3_a6 \gset
select set_config('request.jwt.claims', '{"sub":"00000000-0000-0000-0000-000000000000","role":"authenticated"}', true) as claims;
select pg_temp.set('doc_website', 'x.test', null) as s3_n1 \gset
reset role;
select pg_temp.chk('S3 refusals: worker (master key · doc key) · master (admin key · locked key) · admin on the 20 refused keys (db_role · base_currency · doc_public_base_url · customer_default_currency_code → "a migration or psql changes this") · unknown key · null value · not staff — nothing changed',
  :'s3_w1' like '%needs the master permission%' and :'s3_w2' like '%needs the master permission%'
  and :'s3_m1' like '%needs an admin%' and :'s3_m2' like '%needs a supervisor or above (you are manager)%'
  and :'s3_a1' like '%db_role is not changed from the app — a migration or psql changes this%' and :'s3_a2' like '%a migration or psql changes this%' and :'s3_a3' like '%a migration or psql changes this%' and :'s3_a4' like '%a migration or psql changes this%'
  and :'s3_a5' like '%is not a setting%' and :'s3_a6' like '%cannot be empty (null)%' and :'s3_n1' like '%not registered as active staff%'
  and pg_temp.v('db_role') = :'v_role' and pg_temp.v('base_currency') = :'v_base' and pg_temp.v('mail_enabled') = :'v_mail' and pg_temp.v('doc_website') = :'v_web' and pg_temp.v('so_backorder_expire_days') = (:'v_exp'::int + 1)::text,
  format('w1 %s | w2 %s | m1 %s | m2 %s | a1 %s | a2 %s | a3 %s | a4 %s | a5 %s | a6 %s | n1 %s', left(:'s3_w1', 100), left(:'s3_w2', 100), left(:'s3_m1', 100), left(:'s3_m2', 120), left(:'s3_a1', 140), left(:'s3_a2', 100), left(:'s3_a3', 100), left(:'s3_a4', 100), left(:'s3_a5', 100), left(:'s3_a6', 100), left(:'s3_n1', 100)));

\echo '── S4) changed_elsewhere(판정 574) — master 가 옛 값(지금 값 −1)으로 min_fill_pct 를 보내면 거부 · 문장에 지금 값 · 누가(RLS2 master) · 언제 · 값 그대로'
set local role authenticated;
select set_config('request.jwt.claims', :'c_mas', true) as claims;
select pg_temp.set('mail_backorder_min_fill_pct', '70', :'v_pct') as s4_old \gset
reset role;
select pg_temp.chk('S4 changed_elsewhere: p_old = the value before S2 → refused · message names the key · RLS2 master · time · current value · nothing changed',
  :'s4_old' like 'ERR P0001: changed_elsewhere: mail_backorder_min_fill_pct was changed by RLS2 master at 20__-__-__ __:__ to "' || (:'v_pct'::int + 1)::text || '"%' and pg_temp.v('mail_backorder_min_fill_pct') = (:'v_pct'::int + 1)::text,
  left(:'s4_old', 220));

\echo '── S5) 값 검사는 guard 가(한 곳) — 틀린 모양은 guard 의 문장 그대로: doc_branches JSON 아님 · unit_display 어휘 밖 · expire_days 숫자 아님 · min_fill_pct 모양 · 시험 DB 메일 규칙(mail_enabled on 인 채 mail_redirect_to 비우기) · 값 그대로'
set local role authenticated;
select set_config('request.jwt.claims', :'c_adm', true) as claims;
select pg_temp.set('doc_branches', 'nope', null) as s5_br \gset
select pg_temp.set('so_invoice_unit_display', 'xyz', null) as s5_unit \gset
select pg_temp.set('so_backorder_expire_days', 'abc', null) as s5_exp \gset
select pg_temp.set('mail_backorder_min_fill_pct', 'abc', null) as s5_pct \gset
select pg_temp.set('mail_redirect_to', '', null) as s5_red \gset
reset role;
select pg_temp.chk('S5 shape checks come from the guard, unchanged: doc_branches "must be JSON like" · unit_display "must be one of both, discounted, net" · expire_days "positive whole number of days" · min_fill_pct refused · test-DB mail rule (redirect cannot be emptied while mail_enabled is on) · values untouched',
  :'s5_br' like 'ERR P0001: inv_config.doc_branches must be JSON like%' and :'s5_unit' like 'ERR P0001: inv_config.so_invoice_unit_display must be one of both, discounted, net%'
  and :'s5_exp' like 'ERR P0001: inv_config.so_backorder_expire_days must be a positive whole number of days%' and :'s5_pct' like 'ERR P0001: inv_config.mail_backorder_min_fill_pct %'
  and ((:'v_role' = 'test' and :'v_mail' = 'on' and :'s5_red' like '%cannot be emptied while mail_enabled is on in the test database%') or (:'v_role' <> 'test' or :'v_mail' <> 'on'))
  and pg_temp.v('so_invoice_unit_display') = 'net' and pg_temp.v('mail_redirect_to') is distinct from '' and pg_temp.v('doc_branches') like '[%',
  format('br %s | unit %s | exp %s | pct %s | red %s', left(:'s5_br', 110), left(:'s5_unit', 120), left(:'s5_exp', 120), left(:'s5_pct', 140), left(:'s5_red', 160)));

\echo '── S6) 다른 쓰는 길 그대로 — service_role(EF)의 select · update 됨 · postgres(마이그레이션)의 update 됨 · 창구는 service_role 에게 없다'
set local role service_role;
select pg_temp.run('update public.inv_config set value = value where key = ''so_direct_order_tier_code'' returning key') as s6_sr_upd \gset
select pg_temp.run('select value from public.inv_config where key = ''db_role''') as s6_sr_sel \gset
select pg_temp.run('select public.ims_config_set(''doc_website'', ''x.test'', null)::text') as s6_sr_fn \gset
reset role;
select pg_temp.run('update public.inv_config set value = value where key = ''base_currency'' returning key') as s6_pg_upd \gset
select pg_temp.chk('S6 other writers untouched: service_role update 1 row · select ok · service_role has no execute on ims_config_set (42501) · postgres update 1 row',
  :'s6_sr_upd' = 'so_direct_order_tier_code' and :'s6_sr_sel' = :'v_role' and :'s6_sr_fn' like 'ERR 42501%' and :'s6_pg_upd' = 'base_currency',
  format('sr upd %s | sr sel %s | sr fn %s | pg upd %s', :'s6_sr_upd', :'s6_sr_sel', left(:'s6_sr_fn', 100), :'s6_pg_upd'));

\else
select pg_temp.chk('G1 ~ S6 skipped: rls-2 not landed (auth_all still on inv_config · no ims_config_set)', false, 'not landed — nothing to exercise');   -- 미적용 DB 의 마른 실행이 ERROR 가 아니라 MISMATCH 로 끝나게
\endif

rollback;
\echo '── Z1) rollback 뒤 — 설정 41 행 md5 begin 전과 같음 · 가짜 직원 0'
select count(*) as n_cfg1, md5(string_agg(c.key || '|' || c.value || '|' || coalesce(c.updated_at::text, '') || '|' || coalesce(c.updated_by::text, ''), ',' order by c.key)) as md5_cfg1 from public.inv_config c \gset
select case when :n_cfg1 = :n_cfg0 and :'md5_cfg1' = :'md5_cfg0' then 'OK ' else 'MISMATCH (' end || format('Z1 %s config rows back to their pre-test values after rollback (md5 equal)', :n_cfg1) || case when :n_cfg1 = :n_cfg0 and :'md5_cfg1' = :'md5_cfg0' then '' else format('): %s rows · md5 %s vs %s', :n_cfg1, :'md5_cfg1', :'md5_cfg0') end;
select (select count(*) from public.ims_staff where email like 'rls2-%') as fake_traces_left;
