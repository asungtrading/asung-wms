-- so-tot-1-verify.sql — so_totals_many = so_detail.totals 같음 증명(모든 오더 · 두 신원) · 비용 · 가장자리 (Asung-IMS · 2026-10-07)
--   기대: 시험 갈래 OK 16 · 확인 갈래(G0 셋 없음) OK 13 · MISMATCH 0(시험 적용 3회차 통과 · 2026-10-07) · 읽기 창구라 재료 없음(가짜 직원 한 행만 · rollback) · 시퀀스 무접촉
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261007161321_so_tot_1_totals_many.sql -f supabase/tests/so-tot-1-verify.sql 2>&1 | tee /tmp/so-tot-1.out; echo "rc=${PIPESTATUS[0]}"
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select last_value as cr_seq_last, is_called as cr_seq_called from public.so_credit_number_seq \gset
\echo '== seq head so' :so_seq_last :so_seq_called 'inv' :inv_seq_last :inv_seq_called 'cr' :cr_seq_last :cr_seq_called
select count(*) as n_so from public.so \gset
select coalesce(string_agg(s.status || '=' || s.n, ' · ' order by s.status), '-') as so_by_status from (select status, count(*) n from public.so group by status) s \gset
\echo '== orders on this DB:' :n_so '·' :so_by_status

begin;
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create temp table t_pre as
  select p.proname as n, p.prosrc as src from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname in ('so_detail', 'so_tax_preview', 'so_lines_total');
\if :{?mig}
select pg_temp.chk('G0a so_detail last def = 20261006204146:956~', (select md5(src) from t_pre where n = 'so_detail'), '50677b573390a9fab65f0185ee17661e');
select pg_temp.chk('G0b so_tax_preview last def = 20261006000805:884~', (select md5(src) from t_pre where n = 'so_tax_preview'), '497207d8659cfa115a560f04fd1f4e85');
select pg_temp.chk('G0c so_lines_total last def = 20261006201443:152~', (select md5(src) from t_pre where n = 'so_lines_total'), 'ab900f0a75b4b05e0e7afd7ecd4868e6');
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
-- 정규형: 오더마다 「so_id|basis|여덟 수(trim_scale · null = ∅)」 한 줄 · 둘을 글자로 맞댄다(수는 numeric 으로 맞춘 뒤 글자)
create function pg_temp.canon_detail() returns text language plpgsql stable as $$
declare v_out text := ''; v_r record; v_t jsonb;
begin
  for v_r in select s.id from public.so s order by s.id loop
    v_t := public.so_detail(v_r.id)->'totals';
    v_out := v_out || v_r.id::text || '|' || (v_t->>'basis') || '|' || coalesce(trim_scale((v_t->>'lines_total')::numeric)::text, '∅') || '|' || coalesce(trim_scale((v_t->>'order_discount_amount')::numeric)::text, '∅')
             || '|' || coalesce(trim_scale((v_t->>'charges_total')::numeric)::text, '∅') || '|' || coalesce(trim_scale((v_t->>'surcharge_amount')::numeric)::text, '∅') || '|' || coalesce(trim_scale((v_t->>'tax')::numeric)::text, '∅')
             || '|' || coalesce(trim_scale((v_t->>'order_total')::numeric)::text, '∅') || '|' || coalesce(trim_scale((v_t->>'order_total_with_tax')::numeric)::text, '∅') || E'\n';
  end loop;
  return v_out;
end $$;
create function pg_temp.canon_many() returns text language plpgsql stable as $$
declare v_out text := ''; v_ids uuid[]; v_r record; v_i int := 1;
begin
  select array_agg(s.id order by s.id) into v_ids from public.so s;
  while v_i <= coalesce(cardinality(v_ids), 0) loop                                                                 -- 200 개씩(상한)
    for v_r in select * from public.so_totals_many(v_ids[v_i : v_i + 199]) order by so_id loop
      v_out := v_out || v_r.so_id::text || '|' || v_r.basis || '|' || coalesce(trim_scale(v_r.lines_total)::text, '∅') || '|' || coalesce(trim_scale(v_r.order_discount_amount)::text, '∅')
               || '|' || coalesce(trim_scale(v_r.charges_total)::text, '∅') || '|' || coalesce(trim_scale(v_r.surcharge_amount)::text, '∅') || '|' || coalesce(trim_scale(v_r.tax)::text, '∅')
               || '|' || coalesce(trim_scale(v_r.order_total)::text, '∅') || '|' || coalesce(trim_scale(v_r.order_total_with_tax)::text, '∅') || E'\n';
    end loop;
    v_i := v_i + 200;
  end loop;
  return v_out;
end $$;

-- ═══ C1 같음 — postgres 신원 · 모든 오더(상태 · 채널 · 취소 포함) · 여덟 열 numeric 대조 · 오더 수 = 비교 수 ═══
-- ⚠️ 둘을 한 문장에서 받는다(같은 스냅샷) — 1회차는 두 문장으로 받아 그 사이 다른 세션이 고친 오더 하나가 양쪽에 다르게 보였다(테스트 DB 를 Caleb 이 같이 쓰는 중 · 짐작)
select pg_temp.canon_detail() as cd, pg_temp.canon_many() as cm \gset
select array_length(string_to_array(rtrim(:'cd', E'\n'), E'\n'), 1) as n_cd, array_length(string_to_array(rtrim(:'cm', E'\n'), E'\n'), 1) as n_cm \gset
select count(*) as n_diff from (select unnest(string_to_array(:'cd', E'\n')) except select unnest(string_to_array(:'cm', E'\n'))) d \gset
select count(*) as n_diff2 from (select unnest(string_to_array(:'cm', E'\n')) except select unnest(string_to_array(:'cd', E'\n'))) d \gset
select pg_temp.chk('C1 postgres: so_detail.totals = so_totals_many on every order · compared = orders · differing rows 0 (both directions)', :'n_cd' || '/' || :'n_cm' || '/' || :'n_diff' || '/' || :'n_diff2' || '/' || (:'cd' = :'cm')::text, :'n_so' || '/' || :'n_so' || '/0/0/true');
select 'C1 sample (first 3 canon rows): ' || replace(substr(:'cm', 1, 400), E'\n', ' ‖ ');
select pg_temp.chk('C1b null pairs present where no tax rule (drafts) · shipped basis present where shipped/fulfilled', (select count(*) from public.so_totals_many((select array_agg(id) from public.so)) m where m.tax is null)::text || '/' || (select count(*) from public.so_totals_many((select array_agg(id) from public.so)) m where m.basis = 'shipped'), (select count(*) from public.so s where (public.so_detail(s.id)->'totals'->>'tax') is null)::text || '/' || (select count(*) from public.so s where s.status in ('shipped', 'fulfilled')));

-- ═══ C2 같음 — 가짜 직원(sales 읽기) 신원 · so_detail 도 invoker 라 RLS 가 숨기는 행이 있다면 둘 다 같이 사라져야 한다(지금 so_select 는 using(true)) ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'sotot1-sales@test.invalid', 'SOTOT1 Sales', 'worker', '["sales"]'::jsonb) returning auth_user_id::text as s_uid \gset
\set s_claims '{"sub":"' :s_uid '","role":"authenticated"}'
set local role authenticated;
select set_config('request.jwt.claims', :'s_claims', true);
select md5(pg_temp.canon_detail()) as md_cd_s, md5(pg_temp.canon_many()) as md_cm_s, array_length(string_to_array(rtrim(pg_temp.canon_many(), E'\n'), E'\n'), 1) as n_s \gset
reset role;
select pg_temp.chk('C2 fake sales staff (authenticated): both canon texts equal each other and equal the postgres text · row count = orders', (:'md_cd_s' = :'md_cm_s')::text || '/' || (:'md_cm_s' = md5(:'cm'))::text || '/' || :'n_s', 'true/true/' || :'n_so');

-- ═══ T 비용 — 최근 오더(created_at desc · 최대 100) id 로 so_totals_many 한 번 · so_detail × n · so_tax_preview × n (clock_timestamp · 뜨거운 두 번째 판 사용) ═══
-- ⚠️ 반환값을 쓴다(sum(length(…::text))) — 안 쓰는 서브쿼리 출력은 stable 함수라도 계획기가 지워 「so_detail × 61 = 29 ms」 로 보였다(2회차)
select array_agg(id) as ids100, count(*) as n100 from (select id from public.so order by created_at desc limit 100) q \gset
select sum(length(m::text)) from public.so_totals_many(:'ids100'::uuid[]) m;
select clock_timestamp() as t0 \gset
select sum(length(m::text)) from public.so_totals_many(:'ids100'::uuid[]) m;
select clock_timestamp() as t1 \gset
select sum(length(public.so_detail(x)::text)) from unnest(:'ids100'::uuid[]) x;
select clock_timestamp() as t2 \gset
select sum(length(public.so_tax_preview(s.id, null, null, case when s.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end)::text)) from public.so s where s.id = any(:'ids100'::uuid[]);
select clock_timestamp() as t3 \gset
select 'T cost (n=' || :'n100' || ' orders · ms · warm): so_totals_many once=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000) || ' · so_detail x n=' || round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000) || ' · so_tax_preview x n=' || round(extract(epoch from (:'t3'::timestamptz - :'t2'::timestamptz)) * 1000) || ' · per order (many)=' || round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000 / :'n100', 2) || ' ms';
select pg_temp.chk('T so_totals_many on the recent set returns every order', (select count(*)::text from public.so_totals_many(:'ids100'::uuid[])), :'n100');

-- ═══ E 가장자리 — 상한 · 빈 배열 · null · 중복 · 없는 id · 섞임 ═══
do $$ begin perform count(*) from public.so_totals_many((select array_agg(gen_random_uuid()) from generate_series(1, 201))); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlerrm, true); end $$;
select pg_temp.chk('E1 201 ids → refused with the cap message', current_setting('app.out', true), 'so_totals_many takes at most 200 order ids at a time (got 201) — nothing was read');
select pg_temp.chk('E2 200 unknown ids → allowed · 0 rows', (select count(*)::text from public.so_totals_many((select array_agg(gen_random_uuid()) from generate_series(1, 200)))), '0');
select pg_temp.chk('E3 empty array · null → 0 rows', (select count(*) from public.so_totals_many('{}'::uuid[]))::text || '/' || (select count(*) from public.so_totals_many(null)), '0/0');
select s.id::text as one from public.so s order by s.created_at desc limit 1 \gset
select pg_temp.chk('E4 duplicate id ×3 + null → one row · 201 copies of one id → allowed (distinct = 1)', (select count(*) from public.so_totals_many(array[:'one'::uuid, :'one'::uuid, :'one'::uuid, null]))::text || '/' || (select count(*) from public.so_totals_many((select array_agg(:'one'::uuid) from generate_series(1, 201)))), '1/1');
select pg_temp.chk('E5 mixed existing + unknown → only the existing row', (select count(*)::text || '/' || bool_and(so_id = :'one'::uuid)::text from public.so_totals_many(array[:'one'::uuid, gen_random_uuid()])), '1/true');

-- ═══ G 권한 · 모양 · 무접촉 ═══
select pg_temp.chk('G1 so_totals_many: authenticated execute · anon no · public no · invoker · stable · one definition', has_function_privilege('authenticated', 'public.so_totals_many(uuid[])', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_totals_many(uuid[])', 'execute')::text || '/' || has_function_privilege('public', 'public.so_totals_many(uuid[])', 'execute')::text || '/' || (select (not p.prosecdef)::text || '/' || p.provolatile::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_totals_many') || '/' || (select count(*) from pg_proc where proname = 'so_totals_many'), 'true/false/false/true/s/1');
select pg_temp.chk('G2 return columns (identity · result)', pg_get_function_identity_arguments('public.so_totals_many(uuid[])'::regprocedure) || ' → ' || pg_get_function_result('public.so_totals_many(uuid[])'::regprocedure), 'p_so_ids uuid[] → TABLE(so_id uuid, basis text, lines_total numeric, order_discount_amount numeric, charges_total numeric, surcharge_amount numeric, tax numeric, order_total numeric, order_total_with_tax numeric)');
select pg_temp.chk('G3 so_detail · so_tax_preview · so_lines_total untouched (md5 same as before)', (select count(*)::text from t_pre t join pg_proc p on p.proname = t.n join pg_namespace n on n.oid = p.pronamespace and n.nspname = 'public' where md5(p.prosrc) = md5(t.src)), '3');
set local role anon;
do $$ begin perform count(*) from public.so_totals_many('{}'::uuid[]); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
reset role;
select pg_temp.chk('G4 anon → 42501', current_setting('app.out', true), '42501');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
select 'seq tail so ' || last_value || ' ' || is_called from public.so_number_seq;
select 'seq tail inv ' || last_value || ' ' || is_called from public.so_invoice_number_seq;
select 'seq tail cr ' || last_value || ' ' || is_called from public.so_credit_number_seq;
