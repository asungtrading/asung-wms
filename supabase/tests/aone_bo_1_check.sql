-- supabase/tests/aone_bo_1_check.sql — aone-bo-1 검증 (2026-11-01 밤 · 판정 948 · 949 · 덧붙임 3)
-- [테스트 · Asung-IMS] 시험 적용 장치 — begin → (-v mig 면 \i) → A ~ G 갈래 → rollback → 실물 무변(Z1) · 10 초 안(Z2)
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261102020000_aone_bo_1.sql -f supabase/tests/aone_bo_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 · 기대 MISMATCH 0
--   재료: 가짜 직원 셋(abo1-*@test.invalid) · E 는 savepoint 안에서 가짜 입고 한 줄(inv_ledger · BCO10197 토론토 1000) 로 몫을 만들고 mail_enabled 를 on 으로 맞춘다 · 전부 rollback
\set ON_ERROR_STOP on
\pset pager off
select (select count(*) from public.customer where backorder_mail) as n_bo_on0, (select count(*) from public.mail_outbox) as n_mail0, (select count(*) from public.mail_backorder_line) as n_mbl0,
       (select count(*) from public.inv_ledger) as n_ledger0, (select count(*) from public.customer) as n_cust0, (select count(*) from public.mail_run) as n_run0,
       (select count(*) from supabase_migrations.schema_migrations where version = '20261102020000') as n_mig0,
       (select md5(string_agg(c.key || '|' || c.value, ',' order by c.key)) from public.inv_config c) as md5_cfg0 \gset
\echo '── 기준: bo_on' :n_bo_on0 '· mail_outbox' :n_mail0 '· mail_backorder_line' :n_mbl0 '· inv_ledger' :n_ledger0 '· customer' :n_cust0 '· mail_run' :n_run0 '· schema_migrations =' :n_mig0
begin;
set local lock_timeout = '3s';
set local statement_timeout = '120s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'abo1-mgr@test.invalid', 'ABO1 manager', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as g_mgr \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'abo1-wrk@test.invalid', 'ABO1 worker', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as g_wrk \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'abo1-mas@test.invalid', 'ABO1 master', 'manager', '["ims","sales","master"]', '{}') returning auth_user_id::text as g_mas \gset
\set c_mgr '{"sub":"' :g_mgr '","role":"authenticated"}'
\set c_wrk '{"sub":"' :g_wrk '","role":"authenticated"}'
\set c_mas '{"sub":"' :g_mas '","role":"authenticated"}'
select w.id::text as tor from public.ref_warehouse w where w.name = 'Asung Trading Inc.' \gset

-- ── A 착지 ──
select pg_temp.chk('A1 so_store_of exists · immutable · acl authenticated + service_role', (select provolatile::text || '/' || proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_store_of'), 'i/{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}');
select pg_temp.chk('A2 basis_ck has manual · ops_aone_bo_off exists · rls on · no grants', ((select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_backorder_line_basis_ck' and conrelid = 'public.mail_backorder_line'::regclass) ~ 'manual')::text || '/' || (to_regclass('public.ops_aone_bo_off') is not null)::text || '/' || (select relrowsecurity::text from pg_class where oid = 'public.ops_aone_bo_off'::regclass) || '/' || (select count(*) from information_schema.role_table_grants where table_name = 'ops_aone_bo_off' and grantee in ('anon', 'authenticated', 'service_role'))::text, 'true/true/true/0');
select pg_temp.chk('A3 ten functions re-issued (md5 ≠ old)', (select count(*) from (values ('so_backorder_list', 'cbc0ee1c181ab540b569558a40cd16af'), ('so_backorder_arrivals', '25dee596844dba2a7cf62e38faa8fb69'), ('so_backorder_ready', '2ea4fe401068594ea2f9da06447b30cf'), ('so_backorder_overview', 'ce3f84b03c40bf460240dd8043c527f2'), ('so_backorder_demand', 'eec87cef20c7b626c7ea7088a04d2b4d'), ('mail_backorder_pick', '5b32987f6a6531a831987030185ed763'), ('mail_backorder_tick', 'ed117405eed18ee101e2a05a9ec46624'), ('mail_run_chat_due', 'fb2d46bc080f0f598bb246b6c8fe50c6'), ('shop_order_prepare', 'b6e06d4604f6535cd0b0c935c68dbf55'), ('customer_create', '76f4ca450c6d087a9bd19b794f39a085')) v(n, m) join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = v.n where md5(p.prosrc) <> v.m)::text, '10');
select pg_temp.chk('A4 mail_backorder_send: definer · acl authenticated + service_role(default) · not anon/public', (select prosecdef::text || '/' || proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_backorder_send'), 'true/{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}');
select pg_temp.chk('A5 acl kept: five windows + customer_create authenticated + service_role · pick · tick postgres only · prepare postgres + service_role', (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_backorder_list', 'so_backorder_arrivals', 'so_backorder_ready', 'so_backorder_overview', 'so_backorder_demand', 'customer_create') and proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}')::text || '/' || (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('mail_backorder_pick', 'mail_backorder_tick') and proacl::text = '{postgres=X/postgres}')::text || '/' || (select proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_prepare'), '6/2/{postgres=X/postgres,service_role=X/postgres}');

-- ── B so_store_of ──
select pg_temp.chk('B1 so_store_of: AO- aone · AS- asung · other prefix manual · non-shopify manual · nulls manual · split child inherits (20/20 same ref)',
  public.so_store_of('shopify', 'AO-17337') || '/' || public.so_store_of('shopify', 'AS-7384') || '/' || public.so_store_of('shopify', 'XX-1') || '/' || public.so_store_of('manual', 'AO-1') || '/' || public.so_store_of(null, null) || '/' || (select count(*) filter (where c.ref = p.ref)::text || ' of ' || count(*)::text from public.so c join public.so p on p.id = c.split_from_id), 'aone/asung/manual/manual/manual/' || (select count(*)::text || ' of ' || count(*)::text from public.so c join public.so p on p.id = c.split_from_id));

-- ── C 다섯 창구(REST 두 겹 · authenticated 가짜 manager) ──
set local role authenticated;
select set_config('request.jwt.claims', :'c_mgr', true) as claims;
select pg_temp.try($q$select public.so_backorder_list('{"state":"open","limit":1000}')::text$q$) as l_all \gset
select pg_temp.try($q$select public.so_backorder_list('{"state":"open","store":"aone","limit":1000}')::text$q$) as l_ao \gset
select pg_temp.try($q$select public.so_backorder_list('{"state":"open","store":"x"}')::text$q$) as l_bad \gset
select pg_temp.try(format($q$select public.so_backorder_ready('{"store":"aone","location_id":"%s","limit":100}')::text$q$, :'tor')) as r_ao \gset
select pg_temp.try(format($q$select public.so_backorder_arrivals('{"store":"aone","location_id":"%s","received_from":"%s","include_no_waiting":true,"limit":3}')::text$q$, :'tor', public.ims_today() - 7)) as a_ao \gset
select pg_temp.try(format($q$select public.so_backorder_arrivals('{"location_id":"%s","received_from":"%s","include_no_waiting":true,"limit":3}')::text$q$, :'tor', public.ims_today() - 7)) as a_all \gset
select pg_temp.try($q$select public.so_backorder_overview('{"store":"aone","limit":5}')::text$q$) as o_ao \gset
select pg_temp.try($q$select public.so_backorder_demand('{"store":"aone","limit":1000}')::text$q$) as d_ao \gset
select pg_temp.try($q$select public.so_backorder_demand('{"store":"nope"}')::text$q$) as d_bad \gset
reset role;
select pg_temp.chk('C1 list: aone total = independent count · aone rows all aone · aone total ≤ all · all rows carry store (asung | aone | manual)',
  (pg_temp.j(:'l_ao')->>'total') || '/'
  || (select count(*) from jsonb_array_elements(pg_temp.j(:'l_ao')->'rows') r where r->>'store' <> 'aone')::text || '/' || ((pg_temp.j(:'l_ao')->>'total')::int <= (pg_temp.j(:'l_all')->>'total')::int)::text
  || '/' || (select count(*) from jsonb_array_elements(pg_temp.j(:'l_all')->'rows') r where r->>'store' not in ('asung', 'aone', 'manual'))::text,  (select count(*)::text from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id join public.so s on s.id = cp.so_id where r.kind in ('backorder', 'preorder') and r.released_at is null and public.so_store_of(s.intake, s.ref) = 'aone' and exists (select 1 from (select distinct coalesce(cp2.combo_line_id, cp2.id) lid from public.so_reserve r2 join public.so_line cp2 on cp2.id = r2.so_line_id where r2.kind in ('backorder','preorder') and r2.released_at is null) z where z.lid = coalesce(cp.combo_line_id, cp.id)) and cp.combo_line_id is null) || '/0/true/0');
select pg_temp.chk('C2 list: store x → refused', :'l_bad', 'ERR P0001: store must be asung, aone or manual (got x)');
select pg_temp.chk('C3 ready: store filter runs · rows all aone · prosrc carries store key', (pg_temp.j(:'r_ao') ? 'rows')::text || '/' || (select count(*) from jsonb_array_elements(pg_temp.j(:'r_ao')->'rows') r where r->>'store' <> 'aone')::text || '/' || ((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_backorder_ready') ~ $q$'store', r.store$q$)::text, 'true/0/true');
select pg_temp.chk('C4 arrivals: store filter runs · rows carry stores (array)', (pg_temp.j(:'a_ao') ? 'rows')::text || '/' || (select count(*) from jsonb_array_elements(pg_temp.j(:'a_all')->'rows') r where jsonb_typeof(r->'stores') <> 'array')::text || '/' || (select count(*) from jsonb_array_elements(pg_temp.j(:'a_ao')->'rows') r cross join jsonb_array_elements_text(r->'stores') s where s <> 'aone')::text, 'true/0/0');
select pg_temp.chk('C5 overview + demand: store filter runs (overview hands f to demand) · demand rows and lines all aone · bad value refused', (pg_temp.j(:'o_ao') ? 'rows')::text || '/' || (pg_temp.j(:'d_ao') ? 'rows')::text || '/' || (select count(*) from jsonb_array_elements(pg_temp.j(:'d_ao')->'rows') r where r->>'store' <> 'aone')::text || '/' || (select count(*) from jsonb_array_elements(pg_temp.j(:'d_ao')->'rows') r cross join jsonb_array_elements(r->'lines') l where l->>'store' <> 'aone')::text || '/' || :'d_bad', 'true/true/0/0/ERR P0001: store must be asung, aone or manual (got nope)');

-- ── D pick: aone 제외 · aone_lines ──
select public.mail_backorder_pick(:'tor'::uuid, now())::text as pk \gset
select pg_temp.chk('D1 pick: aone_lines key (int ≥ 0) · no aone line in mails or skipped', (jsonb_typeof(pg_temp.j(:'pk')->'aone_lines') = 'number')::text || '/' || (select count(*) from jsonb_array_elements(pg_temp.j(:'pk')->'mails' || (pg_temp.j(:'pk')->'skipped')) m cross join jsonb_array_elements(m->'lines') l join public.so s on s.id = (l->>'so_id')::uuid where public.so_store_of(s.intake, s.ref) = 'aone')::text, 'true/0');

-- ── E send(가짜 입고로 몫 · savepoint) ──
savepoint e;
with bo as (                                                                                      -- 열린 백오더 예약이 있는 aone 줄(토론토 · 콤보 아님) — fill 없이(fill 은 한 번에 2 초)
  select l.id as line_id, s.customer_id, l.sku, s.so_number from public.so_line l join public.so s on s.id = l.so_id
  where s.location_id = :'tor'::uuid and s.status = 'confirmed' and l.combo_line_id is null and public.so_store_of(s.intake, s.ref) = 'aone'
    and exists (select 1 from public.so_reserve r where r.so_line_id = l.id and r.kind = 'backorder' and r.released_at is null)
    and not exists (select 1 from public.so_line cp where cp.combo_line_id = l.id))
select (select line_id::text from bo where sku = 'BCO10197' order by so_number limit 1) as e_line, (select customer_id::text from bo where sku = 'BCO10197' order by so_number limit 1) as e_cust, 'BCO10197' as e_sku,
       (select line_id::text from bo where sku <> 'BCO10197' order by so_number limit 1) as e_line2 \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
values (public.ims_today(), 1, :'e_sku', 'Asung Trading Inc.', '', 1000, 'adjust_existing', 'adjustment', 'AONE-BO-1-TRIAL', 'trial', 'manual');
update public.inv_config set value = 'on' where key = 'mail_enabled';
set local role authenticated;
select set_config('request.jwt.claims', :'c_wrk', true) as claims;
select pg_temp.try(format($q$select public.mail_backorder_send(array['%s']::uuid[], false)::text$q$, :'e_line')) as e_wrk \gset
select set_config('request.jwt.claims', :'c_mgr', true) as claims;
select pg_temp.try($q$select public.mail_backorder_send('{}'::uuid[], false)::text$q$) as e_empty \gset
select pg_temp.try(format($q$select public.mail_backorder_send(array['%s','%s','00000000-0000-4000-8000-000000000000']::uuid[], false)::text$q$, :'e_line', :'e_line2')) as e_prev \gset
select pg_temp.try(format($q$select public.mail_backorder_send(array['%s']::uuid[], true)::text$q$, :'e_line')) as e_commit \gset
reset role;
select (select count(*) from public.mail_outbox o where o.kind = 'backorder_ready' and o.status = 'queued' and o.run_id is null and o.dedupe_key like 'bo:manual:%' and o.customer_id = :'e_cust'::uuid and o.payload->>'manual' = 'true' and o.created_by = (select id from public.ims_staff where email = 'abo1-mgr@test.invalid'))::text as e_outbox,
       (select b.basis || '/' || b.can_fill_units::text from public.mail_backorder_line b where b.so_line_id = :'e_line'::uuid and b.released_at is null) as e_mbl,
       (select n.notified_state || '/' || n.basis from public.so_backorder_notice_state(array[:'e_line'::uuid]) n) as e_state,
       public.mail_backorder_line_notified(:'e_line'::uuid)::text as e_notified \gset
update public.inv_config set value = 'off' where key = 'mail_enabled';
set local role authenticated;
select set_config('request.jwt.claims', :'c_mgr', true) as claims;
select pg_temp.try(format($q$select public.mail_backorder_send(array['%s']::uuid[], true)::text$q$, :'e_line2')) as e_off \gset
reset role;
rollback to savepoint e;
select pg_temp.chk('E0 trial stock gives the aone line its share (preview can_fill > 0 · other aone line without stock → nothing_to_fill)', ((pg_temp.j(:'e_prev')->'mails'->0->'lines'->0->>'can_fill_units')::numeric > 0)::text, 'true');
select pg_temp.chk('E1 worker (sales) → needs a manager', (:'e_wrk' like '%needs a manager or above (you are worker)%')::text, 'true');
select pg_temp.chk('E2 empty → pick at least one', :'e_empty', 'ERR P0001: Pick at least one backorder line — nothing was sent');
select pg_temp.chk('E3 preview: committed false · 1 mail (customer · to · backorder_mail key · 1 line basis manual store aone) · skipped_lines: nothing_to_fill + not_open_backorder',
  (pg_temp.j(:'e_prev')->>'committed') || '/' || jsonb_array_length(pg_temp.j(:'e_prev')->'mails')::text || '/' || (pg_temp.j(:'e_prev')->'mails'->0->>'customer_id' = :'e_cust')::text || '/' || (pg_temp.j(:'e_prev')->'mails'->0 ? 'backorder_mail')::text || '/' || (pg_temp.j(:'e_prev')->'mails'->0->'lines'->0->>'basis') || '/' || (pg_temp.j(:'e_prev')->'mails'->0->'lines'->0->>'store')
  || '/' || (select string_agg(l->>'reason', ',' order by l->>'reason') from jsonb_array_elements(pg_temp.j(:'e_prev')->'skipped_lines') l), 'false/1/true/true/manual/aone/not_open_backorder,nothing_to_fill');
select pg_temp.chk('E4 commit: committed true · mails 1 · lines 1 · outbox row (queued · run_id null · bo:manual · payload manual · created_by) · mail_backorder_line manual (can_fill = preview) · notice_state queued/manual · mail_backorder_line_notified true (alert fill · send again exclude it by this)',
  (pg_temp.j(:'e_commit')->>'committed') || '/' || (pg_temp.j(:'e_commit')->>'mails') || '/' || (pg_temp.j(:'e_commit')->>'lines') || '/' || :'e_outbox' || '/' || :'e_mbl' || '/' || :'e_state' || '/' || :'e_notified', 'true/1/1/1/manual/' || (pg_temp.j(:'e_prev')->'mails'->0->'lines'->0->>'can_fill_units') || '/queued/manual/true');
select pg_temp.chk('E5 already_notified branch exists in mail_backorder_send (reason mapping · covered by E4 notified = true)', ((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_backorder_send') ~ $q$'already_notified'$q$)::text, 'true');
select pg_temp.chk('E6 mail_enabled off → commit refused', (:'e_off' like '%Emails are off (mail_enabled)%')::text, 'true');
select pg_temp.chk('E7 savepoint rolled back: trial ledger · outbox · line markers gone', (select count(*) from public.inv_ledger where doc_number = 'AONE-BO-1-TRIAL')::text || '/' || (select count(*) from public.mail_outbox where dedupe_key like 'bo:manual:%')::text || '/' || (select count(*) from public.mail_backorder_line where basis = 'manual')::text, '0/0/0');

-- ── F customer_create backorder_mail(949 ①) — 주소 없음 경고 둘은 p_ack 로(shop_order_prepare 의 두 번 부르기와 같은 뜻) ──
savepoint f;
set local role authenticated;
select set_config('request.jwt.claims', :'c_mas', true) as claims;
select pg_temp.try($q$select public.customer_create('{"name":"ABO1 trial aone customer","backorder_mail":false}', true, '{shipping_address_missing,billing_address_missing}')::text$q$) as f_off \gset
select pg_temp.try($q$select public.customer_create('{"name":"ABO1 trial plain customer"}', true, '{shipping_address_missing,billing_address_missing}')::text$q$) as f_def \gset
reset role;
select coalesce((select backorder_mail::text from public.customer where name = 'ABO1 trial aone customer'), '(none)') as f_off_v, coalesce((select backorder_mail::text from public.customer where name = 'ABO1 trial plain customer'), '(none)') as f_def_v \gset
select left(:'f_off', 600) as f_off_head, left(:'f_def', 300) as f_def_head;
rollback to savepoint f;
select pg_temp.chk('F1 customer_create: backorder_mail false honoured · absent → true', (pg_temp.j(:'f_off')->>'committed') || '/' || :'f_off_v' || '/' || (pg_temp.j(:'f_def')->>'committed') || '/' || :'f_def_v', 'true/false/true/true');
select pg_temp.chk('F2 shop_order_prepare sends backorder_mail = (store kind <> aone)', ((select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_prepare') ~ $q$'backorder_mail', \(v_s\.kind <> 'aone'\)$q$)::text, 'true');

-- ── G chat_due aone_lines ──
savepoint g;
insert into public.mail_run (kind, location_id, run_on, started_at, mails, lines, params) values ('backorder_ready', :'tor'::uuid, date '2099-01-01', now(), 0, 0, '{"aone_lines": 3}') returning id::text as g_run \gset
select pg_temp.try($q$select public.mail_run_chat_due()::text$q$) as g_due \gset
rollback to savepoint g;
select pg_temp.chk('G1 mail_run_chat_due carries aone_lines from params', (select r->>'aone_lines' from jsonb_array_elements(pg_temp.j(:'g_due')) r where r->>'run_id' = :'g_run'), '3');

\echo '── 결과'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when not ok then 'got=' || coalesce(got, '(null)') || ' · want=' || coalesce(want, '(null)') end as diff from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch from t_res;
select extract(epoch from clock_timestamp() - :'t_begin0'::timestamptz)::numeric(6,2) as seconds_in_txn \gset
rollback;
\echo '── Z1 rollback 뒤 실물 그대로 · Z2 초'
select (select count(*) from public.customer where backorder_mail) = :n_bo_on0 as z1_bo_on, (select count(*) from public.mail_outbox) = :n_mail0 as z1_mail, (select count(*) from public.mail_backorder_line) = :n_mbl0 as z1_mbl,
       (select count(*) from public.inv_ledger) = :n_ledger0 as z1_ledger, (select count(*) from public.customer) = :n_cust0 as z1_cust, (select count(*) from public.mail_run) = :n_run0 as z1_run,
       (select count(*) from supabase_migrations.schema_migrations where version = '20261102020000') = :n_mig0 as z1_mig,
       (select md5(string_agg(c.key || '|' || c.value, ',' order by c.key)) from public.inv_config c) = :'md5_cfg0' as z1_cfg,
       (select count(*) from public.ims_staff where email like 'abo1-%') = 0 as z1_staff, :seconds_in_txn as z2_seconds;
