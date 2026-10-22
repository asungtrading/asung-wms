-- grt-1a-verify.sql — anon 권한 거두기(판정 617 · 618):
--   적용 전 anon 70(표 25 · 뷰 2 · 시퀀스 43) · 기본 권한 r/S 에 anon → 적용 뒤 anon 0 · 다른 역할 바이트 무변 · 기본 권한 r/S 에 anon 0 · f 무변 · 새 객체 0 ·
--   set role anon → 42501(전에는 0 행) · 로그인한 직원(authenticated + claims)의 wms_waves insert · update · select 그대로 · pur_settings · so_credit_prepare 그대로 · 무접촉(G0 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261022150638_grt_1a_revoke_anon.sql -f supabase/tests/grt-1a-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · A0 · G0 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 수 − 2 · MISMATCH 0
--   가짜 재료 = 직원 W 하나(GRT1A · manager · wms · sales · purchasing · packing · wms_manage) · wms_waves 행 하나(되감긴다) · 시퀀스 wms_waves_id_seq 머리 → rollback 뒤 greatest

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261022150638' \gset
select :n_applied as schema_migrations_rows_for_20261022150638;
select last_value as wv_seq_last, is_called as wv_seq_called from public.wms_waves_id_seq \gset
select :wv_seq_last as wms_waves_seq_head;

begin;
set local statement_timeout = '600s';
select now() as t0 \gset

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 역할을 바꿔 한 문장 — set local role 은 예외로 되감긴 서브트랜잭션과 함께 돌아온다 · 끝에 reset
create function pg_temp.as_role(p_role text, p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute format('set local role %I', p_role);
  if p_claims is not null then perform set_config('request.jwt.claims', p_claims, true); end if;
  execute p_sql into v;
  reset role;
  return coalesce(v, '(null)');
exception when others then
  reset role;
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 권한 자취 — public 의 r · v · m · p · S 전부의 (relname · relkind · relacl) md5 · anon 이 든 수 · 기본 권한 r · S · f 원문
create function pg_temp.acl_state() returns text language sql security definer as $$
  select 'rels=' || (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'S'))
      || ' anon=' || (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'S') and c.relacl::text like '%anon=%')
      || ' others_md5=' || (select md5(string_agg(c.relname::text || c.relkind::text || coalesce((select string_agg(a::text, ',' order by a::text) from unnest(c.relacl) a where a::text not like 'anon=%'), '-'), '|' order by c.relname, c.relkind))
                             from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'S'))
      || ' def=' || (select string_agg(d.defaclobjtype::text || ':' || d.defaclacl::text, ' ' order by d.defaclobjtype) from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace) $$;
create function pg_temp.real_rows(p_t0 timestamptz) returns text language sql security definer as $$
  select 'so=' || (select count(*) from public.so s where s.created_at < p_t0) || ' inv=' || (select count(*) from public.so_invoice i where i.created_at < p_t0)
      || ' waves=' || (select count(*) from public.wms_waves w where w.created_at < p_t0) || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where created_at < p_t0)
      || ' staff=' || (select count(*) from public.ims_staff where email not like 'grt1a-%') $$;

\echo '── M0) 가짜 직원 W · 스냅샷 · 적용 전 anon 전권 27 의 relacl 원문 · 기본 권한 원문'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'grt1a-w@test.invalid', 'GRT1A W', 'manager', '["ims","wms","sales","purchasing","packing","picking","wms_manage"]', '{}') returning auth_user_id::text as w_uid, id::text as w_id \gset
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as wh from public.ref_warehouse where is_active order by name limit 1 \gset
select id::text as inv0, invoice_number as inv0_no from public.so_invoice where status = 'issued' and cancelled_at is null order by issued_on, invoice_number limit 1 \gset
select pg_temp.acl_state() as acl_before, pg_temp.real_rows(:'t0'::timestamptz) as real_before \gset
select c.relkind::text as k, c.relname, c.relacl::text as acl from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm') and c.relacl::text like '%anon=%' order by 1, 2;
select count(*) as anon_seqs, string_agg(c.relname, ', ' order by c.relname) as names from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind = 'S' and c.relacl::text like '%anon=%';
select substring(:'acl_before' from 'def=.*') as default_acl_before;
select pg_temp.chk(format('M0 staff W · warehouse %s · invoice %s · acl snapshot (%s)', left(:'wh', 8), :'inv0_no', substring(:'acl_before' from '^rels=[0-9]+ anon=[0-9]+')), :'w_uid' <> '' and :'wh' <> '' and :'inv0' <> '' and :'acl_before' <> '', 'see M0');

\if :{?mig}
\echo '── S0 · A0) 결함 판(시험 전용) — anon 70 · 기본 권한에 anon · set role anon 으로 wms_pack_tasks 가 「0 행」(거부가 아니라)'
select pg_temp.as_role('anon', null, 'select count(*)::text from public.wms_pack_tasks') as a0_tbl \gset
select pg_temp.as_role('anon', null, 'select count(*)::text from public.wms_order_doc') as a0_view \gset
select pg_temp.chk(format('S0 before the trial: anon on 70 relations (25 tables · 2 views · 43 sequences) · default r/S carry anon · anon reads wms_pack_tasks → %s rows (RLS/empty · not 42501) · wms_order_doc (security_invoker view) → already 42501 on its base table so (%s) · not in schema_migrations', :'a0_tbl', left(:'a0_view', 60)),
  :'acl_before' like 'rels=244 anon=70 %' and :'acl_before' like '%r:{postgres=arwdDxtm/postgres,anon=Dxtm/postgres,%' and :'acl_before' like '%S:{postgres=rwU/postgres,anon=w/postgres,%'
  and :'a0_tbl' = '0' and :'a0_view' like 'ERR 42501:%' and :n_applied = 0,
  format('%s | %s | %s', left(:'acl_before', 400), left(:'a0_tbl', 80), left(:'a0_view', 80)));
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: real rows unchanged · object count 244 unchanged', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before' and pg_temp.acl_state() like 'rels=244 %', format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));
\else
select pg_temp.chk('P0c confirm run: migration 20261022150638 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.acl_state() like 'rels=% anon=0 %') as landed \gset
\if :landed
\echo '── G1) 착지 ①②③④⑤ — anon 0 · 다른 역할 바이트 무변 · 기본 권한 r/S anon 0 · f 무변 · 새 객체 0'
select pg_temp.acl_state() as acl_after \gset
select pg_temp.chk('G1 anon 0 on all public relations · other roles'' acl bytes identical to the snapshot · default r/S without anon · default f unchanged (anon=X kept) · 244 objects',
  :'acl_after' like 'rels=244 anon=0 %'
  and substring(:'acl_after' from 'others_md5=[0-9a-f]+') = substring(:'acl_before' from 'others_md5=[0-9a-f]+')
  and :'acl_after' like '%r:{postgres=arwdDxtm/postgres,authenticated=Dxtm/postgres,service_role=Dxtm/postgres}%'
  and :'acl_after' like '%S:{postgres=rwU/postgres,authenticated=w/postgres,service_role=w/postgres}%'
  and substring(:'acl_after' from 'f:\{[^}]*\}') = substring(:'acl_before' from 'f:\{[^}]*\}') and :'acl_after' like '%f:{%anon=X/postgres%',
  format('before %s | after %s', :'acl_before', :'acl_after'));

\echo '── T1) set role anon → 42501 (표 · 뷰 · 시퀀스)'
select pg_temp.as_role('anon', null, 'select count(*)::text from public.wms_pack_tasks') as t1a \gset
select pg_temp.as_role('anon', null, 'select count(*)::text from public.wms_order_doc') as t1b \gset
select pg_temp.as_role('anon', null, 'select nextval(''public.wms_waves_id_seq'')::text') as t1c \gset
select pg_temp.as_role('anon', null, 'select count(*)::text from public.so_line_merge_source') as t1d \gset
select pg_temp.as_role('anon', null, 'select count(*)::text from public.inv_adjust') as t1e \gset
select pg_temp.chk('T1 anon: wms_pack_tasks · wms_order_doc (view) · nextval(wms_waves_id_seq) · so_line_merge_source · inv_adjust → all 42501 permission denied',
  :'t1a' like 'ERR 42501:%' and :'t1b' like 'ERR 42501:%' and :'t1c' like 'ERR 42501:%' and :'t1d' like 'ERR 42501:%' and :'t1e' like 'ERR 42501:%',
  format('%s | %s | %s | %s | %s', left(:'t1a', 90), left(:'t1b', 90), left(:'t1c', 90), left(:'t1d', 90), left(:'t1e', 90)));

\echo '── T2) 로그인한 직원 — wms_waves insert · update · select (화면 wms-picker · wms-admin 이 직접 쓰는 꼴) 그대로'
select pg_temp.as_role('authenticated', :'w', format('insert into public.wms_waves (label, warehouse_id, status, created_by) values (''GRT1A wave'', %L::uuid, ''pending'', %L::uuid) returning id::text', :'wh', :'w_id')) as t2_ins \gset
select pg_temp.as_role('authenticated', :'w', format('update public.wms_waves set status = ''in_progress'', started_at = now(), assigned_to = %L::uuid where id = %L::bigint returning status', :'w_id', :'t2_ins')) as t2_upd \gset
select pg_temp.as_role('authenticated', :'w', format('select label || ''|'' || status from public.wms_waves where id = %L::bigint', :'t2_ins')) as t2_sel \gset
select pg_temp.as_role('authenticated', :'w', format('delete from public.wms_waves where id = %L::bigint returning id::text', :'t2_ins')) as t2_del \gset
select pg_temp.chk(format('T2 authenticated W: insert wms_waves → id %s · update → in_progress · select → GRT1A wave|in_progress · delete → same id', :'t2_ins'),
  :'t2_ins' ~ '^[0-9]+$' and :'t2_upd' = 'in_progress' and :'t2_sel' = 'GRT1A wave|in_progress' and :'t2_del' = :'t2_ins',
  format('%s | %s | %s | %s', left(:'t2_ins', 100), left(:'t2_upd', 100), left(:'t2_sel', 100), left(:'t2_del', 100)));

\echo '── T3) 창구 둘 — pur_settings() · so_credit_prepare(실제 인보이스 · 읽기만) 그대로'
select pg_temp.as_role('authenticated', :'w', 'select public.pur_settings()::text') as t3a \gset
select pg_temp.as_role('authenticated', :'w', format('select public.so_credit_prepare(%L::uuid)::text', :'inv0')) as t3b \gset
select pg_temp.chk(format('T3 pur_settings → boundary_date %s · weights · so_credit_prepare(%s) → invoice keys · lines %s', pg_temp.j(:'t3a')->>'boundary_date', :'inv0_no', jsonb_array_length(coalesce(pg_temp.j(:'t3b')->'lines', '[]'::jsonb))),
  pg_temp.j(:'t3a') ? 'boundary_date' and pg_temp.j(:'t3a') ? 'weights' and pg_temp.j(:'t3b') ? 'lines' and :'t3b' not like 'ERR%',
  format('%s | %s', left(:'t3a', 200), left(:'t3b', 300)));
\else
select pg_temp.chk('G1 ~ T3 skipped: grt-1a not landed', false, pg_temp.acl_state());
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real so · invoices · waves · ledger · staff untouched', pg_temp.real_rows(:'t0'::timestamptz) = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows(:'t0'::timestamptz)));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 되돌리기'
select (select count(*) from public.ims_staff where email like 'grt1a-%') + (select count(*) from public.wms_waves where label = 'GRT1A wave') as leftovers;
select setval('public.wms_waves_id_seq', greatest(coalesce((select max(id) from public.wms_waves), 0), :wv_seq_last), :'wv_seq_called'::boolean) as wms_waves_id_seq_reset_to;
select last_value || '|' || is_called as wv_seq_after from public.wms_waves_id_seq;
