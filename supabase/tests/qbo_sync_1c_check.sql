-- supabase/tests/qbo_sync_1c_check.sql — qbo-sync-1c 검증: qbo_match_auto 묶음(p_after · p_limit) · 임시 표 analyze · qbo_ims_rows rows 20000 · 옛 서명 없음 (2026-11-01 · 판정 934 · 1c 이견 1 ~ 5 「다섯 다 동의」)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 3s) → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): export MIG=supabase/migrations/20261101230000_qbo_sync_1c_match_chunks.sql; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig="$MIG" -f supabase/tests/qbo_sync_1c_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 같다(24)
--   데이터: 운영 회사의 실제 qbo_entity · qbo_link 를 그대로 쓴다(1b pull 뒤) — supplier 의 짝을 rollback 안에서 지우고 묶음 100 으로 세 번 돌려 한 번(20000)과 합이 같은지 본다 · product 는 sku 가 비어 전부 absent(1c EF 뒤 Item 을 다시 받으면 바뀐다 — 수는 동적으로 센다)
--   쓰기: 가짜 직원 둘 · supplier 짝 지우기 · 자동 짝 — 전부 rollback · 실제 행 0 변경
--   REST 두 겹: ① L1 nowhere 스캐너(새 qbo_match_auto) ② 적용 · 배포 뒤 Caleb 의 QBOP.match('product') 묶음 돌기
\set ON_ERROR_STOP on
\set EXPECT_OK 24
\pset pager off
\set mgr '{"role":"authenticated","sub":"a1a1a1a1-0000-4000-8000-000000000002"}'
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.qbo_link) as n_link0, (select count(*) from public.qbo_entity) as n_ent0,
       (select realm_id from public.qbo_connection where singleton) as realm,
       (select count(*) from public.supplier s where s.is_active) as n_sup,
       (select count(*) from public.supplier s where s.is_active and not exists (select 1 from public.qbo_link l where l.ims_kind = 'supplier' and l.ims_id = s.id::text)) as n_sup_unl,
       (select count(*) from public.product p where p.is_active and not exists (select 1 from public.qbo_link l where l.ims_kind = 'product' and l.ims_id = p.id::text)) as n_prod_unl,
       (select count(*) from public.customer c where c.is_active and not exists (select 1 from public.qbo_link l where l.ims_kind = 'customer' and l.ims_id = c.id::text)) as n_cust_unl,
       (select count(*) from public.qbo_entity e where e.qbo_type = 'Item' and e.sku is not null) as n_item_sku,
       (select count(*) from public.qbo_entity e where e.qbo_type = 'Item' and e.gone_at is null) as n_item \gset
\echo '── 기준: qbo_* 함수' :n_fn '· staff' :n_staff0 '· qbo_link' :n_link0 '· qbo_entity' :n_ent0 '· realm' :realm '· 활성 supplier' :n_sup '(짝 없음' :n_sup_unl ') · 짝 없는 product' :n_prod_unl '· customer' :n_cust_unl '· Item sku 있음' :n_item_sku
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
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
create function pg_temp.adm(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"a1a1a1a1-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
-- 묶음 한 번 → 'considered/linked/absent/ambiguous/skipped/limit/next_after 있음?/remaining/done'
create function pg_temp.m(p_kind text, p_after text, p_limit text) returns text language plpgsql as $$
declare t text; j jsonb;
begin
  t := pg_temp.adm(format('select public.qbo_match_auto(%L, %s, %s)::text', p_kind, coalesce(quote_literal(p_after), 'null'), coalesce(p_limit, 'null')));
  if t like 'ERR%' then return t; end if;
  j := t::jsonb;
  return (j->>'considered') || '/' || (j->>'linked') || '/' || (j->>'absent') || '/' || (j->>'ambiguous') || '/' || (j->>'skipped') || '/' || (j->>'limit') || '/' || (j->>'remaining') || '/' || (j->>'done');
end $$;
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
insert into public.ims_staff (id, auth_user_id, email, name, role) values
  ('a1a1a1a1-0000-4000-8000-00000000000a', 'a1a1a1a1-0000-4000-8000-000000000001', 'qbo-sync-1c-admin@asung.invalid', 'QBO Sync Test Admin', 'admin'),
  ('a1a1a1a1-0000-4000-8000-00000000000b', 'a1a1a1a1-0000-4000-8000-000000000002', 'qbo-sync-1c-manager@asung.invalid', 'QBO Sync Test Manager', 'manager');

-- ── A) 착지 ──
select pg_temp.chk('A1 qbo_match_auto 는 (text, text, int) 하나 · authenticated · 옛 (text) 없음', (select string_agg(pg_get_function_identity_arguments(p.oid) || '=' || coalesce(p.proacl::text, '-'), ' | ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_match_auto'),
  'p_kind text, p_after text, p_limit integer={postgres=X/postgres,authenticated=X/postgres}');
select pg_temp.chk('A2 qbo_ims_rows rows 20000 · grant 0 · 몸(union all 9)은 그대로', (select p.prorows::int::text || ' ' || coalesce(p.proacl::text, '-') || ' ' || (p.prosrc like '%where p_kind = ''service''%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_ims_rows'), '20000 {postgres=X/postgres} true');
select pg_temp.chk('A3 다른 qbo_* 함수 md5 전부 begin 앞과 같다(qbo_match_auto 만 바뀜 · qbo_ims_rows 는 몸 같고 rows 만)', (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5 where t.proname <> 'qbo_match_auto') || '/' || (select count(*)::text from t_pre where proname <> 'qbo_match_auto'), (:n_fn - 1)::text || '/' || (:n_fn - 1)::text);
select pg_temp.chk('A4 함수 comment 에 「묶음」 · 「next_after」', (select (obj_description(p.oid, 'pg_proc') like '%묶음%next_after%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_match_auto'), 'true');
select pg_temp.chk('A5 표 · 정책 · 색인 무접촉(qbo_link 색인 4 · qbo_link_qbo_idx 그대로)', (select string_agg(indexname, ' ' order by indexname) from pg_indexes where schemaname = 'public' and tablename = 'qbo_link'), 'qbo_link_ims_key qbo_link_pkey qbo_link_qbo_idx qbo_link_qbo_one_idx');

-- ── B) 문 ──
select pg_temp.chk('B1 manager → P0001 · service_role → 42501 · 옛 서명(text 하나)은 기본값으로 풀려 같은 함수', left(pg_temp.as_conn('authenticated', :'mgr'::jsonb, 'select public.qbo_match_auto(''supplier'')::text'), 30) || ' | ' || left(pg_temp.as_conn('service_role', '{"role":"service_role"}', 'select public.qbo_match_auto(''supplier'', null, 10)::text'), 9),
  'ERR P0001: Only an admin can m | ERR 42501');
select pg_temp.chk('B2 거부 그대로 — charge · 모르는 kind', left(pg_temp.m('charge', null, null), 39) || ' | ' || left(pg_temp.m('bogus', null, null), 30), 'ERR P0001: No automatic rule for charge | ERR P0001: kind must be one of');

-- ── C) 묶음 — supplier 짝을 지우고 100 씩 세 번 = 한 번(20000) ──
delete from public.qbo_link where ims_kind = 'supplier';
savepoint sp_once;
select pg_temp.adm('select public.qbo_match_auto(''supplier'', null, 20000)::text') as once \gset
select (:'once'::jsonb->>'considered') || '/' || (:'once'::jsonb->>'linked') || '/' || (:'once'::jsonb->>'absent') as once_sum \gset
rollback to savepoint sp_once;                                                                          -- 한 번 돌린 짝을 되돌린다(t_res 도 같이 되돌아가므로 C1 · C2 는 이 뒤에 적는다)
select pg_temp.chk('C1 한 번(20000) — limit 20000 · done true · remaining 0 · next_after = 마지막 활성 supplier id', (:'once'::jsonb->>'limit') || ' ' || (:'once'::jsonb->>'done') || ' ' || (:'once'::jsonb->>'remaining') || ' ' || ((:'once'::jsonb->>'next_after') = (select max(s.id::text) from public.supplier s where s.is_active))::text, '20000 true 0 true');
select pg_temp.chk('C2 한 번의 considered/linked/absent = 활성 supplier 전부 / 기대 195 / 33(1b 실측과 같다)', :'once_sum', :n_sup || '/195/33');
select pg_temp.adm('select public.qbo_match_auto(''supplier'', null, 100)::text') as c1 \gset
select pg_temp.chk('C3 묶음 1(100) — considered 100 · done false · remaining = 활성 - 100 · next_after = 100 번째 ims_id', (:'c1'::jsonb->>'considered') || ' ' || (:'c1'::jsonb->>'done') || ' ' || (:'c1'::jsonb->>'remaining') || ' ' || ((:'c1'::jsonb->>'next_after') = (select s.id::text from public.supplier s where s.is_active order by s.id::text offset 99 limit 1))::text,
  '100 false ' || (:n_sup - 100)::text || ' true');
select pg_temp.adm(format('select public.qbo_match_auto(''supplier'', %L, 100)::text', :'c1'::jsonb->>'next_after')) as c2 \gset
select pg_temp.chk('C4 묶음 2(after) — considered 100 · next_after 커짐 · remaining = 활성 - 200', (:'c2'::jsonb->>'considered') || ' ' || ((:'c2'::jsonb->>'next_after') > (:'c1'::jsonb->>'next_after'))::text || ' ' || (:'c2'::jsonb->>'remaining') || ' ' || (:'c2'::jsonb->>'after' = :'c1'::jsonb->>'next_after')::text, '100 true ' || (:n_sup - 200)::text || ' true');
select pg_temp.adm(format('select public.qbo_match_auto(''supplier'', %L, 100)::text', :'c2'::jsonb->>'next_after')) as c3 \gset
select pg_temp.chk('C5 묶음 3 — 나머지 · done true · remaining 0', (:'c3'::jsonb->>'considered') || ' ' || (:'c3'::jsonb->>'done') || ' ' || (:'c3'::jsonb->>'remaining'), (:n_sup - 200)::text || ' true 0');
select pg_temp.chk('C6 세 묶음의 합 = 한 번(considered · linked · absent · ambiguous) — after 뒤는 다시 세지 않는다', ((:'c1'::jsonb->>'considered')::int + (:'c2'::jsonb->>'considered')::int + (:'c3'::jsonb->>'considered')::int)::text || '/' || ((:'c1'::jsonb->>'linked')::int + (:'c2'::jsonb->>'linked')::int + (:'c3'::jsonb->>'linked')::int)::text || '/' || ((:'c1'::jsonb->>'absent')::int + (:'c2'::jsonb->>'absent')::int + (:'c3'::jsonb->>'absent')::int)::text || '/' || ((:'c1'::jsonb->>'ambiguous')::int + (:'c2'::jsonb->>'ambiguous')::int + (:'c3'::jsonb->>'ambiguous')::int)::text, :'once_sum' || '/0');
select pg_temp.chk('C7 짝 표의 supplier 줄 = linked 합 · 전부 auto_name · by_staff 가짜 admin', (select count(*)::text || ' ' || count(*) filter (where matched_by = 'auto_name')::text || ' ' || count(*) filter (where by_staff = 'a1a1a1a1-0000-4000-8000-00000000000a')::text from public.qbo_link where ims_kind = 'supplier'), repeat((:'once'::jsonb->>'linked') || ' ', 2) || (:'once'::jsonb->>'linked'));
select pg_temp.adm(format('select public.qbo_match_auto(''supplier'', %L, 100)::text', :'c3'::jsonb->>'next_after')) as c4 \gset
select pg_temp.chk('C8 done 뒤 한 번 더(after = 마지막) — considered 0 · linked 0 · next_after = after 그대로 · done true', (:'c4'::jsonb->>'considered') || ' ' || (:'c4'::jsonb->>'linked') || ' ' || (:'c4'::jsonb->>'next_after' = :'c3'::jsonb->>'next_after')::text || ' ' || (:'c4'::jsonb->>'done'), '0 0 true true');
select pg_temp.chk('C9 after 없이 다시(짝 있음은 안 센다) — considered = absent 33 · linked 0 · done true', pg_temp.m('supplier', null, null), (:'once'::jsonb->>'absent') || '/0/' || (:'once'::jsonb->>'absent') || '/0/0/5000/0/true');
select pg_temp.chk('C10 p_limit 깎기 — 99999 → 20000 · 0 → 1 · null → 5000', (pg_temp.adm('select public.qbo_match_auto(''supplier'', null, 99999)::text')::jsonb->>'limit') || ' ' || (pg_temp.adm('select public.qbo_match_auto(''supplier'', null, 0)::text')::jsonb->>'limit') || ' ' || (pg_temp.adm('select public.qbo_match_auto(''supplier'', null, null)::text')::jsonb->>'limit'), '20000 1 5000');
select pg_temp.chk('C11 limit 1 — considered 1 · remaining = absent - 1 · done false', pg_temp.m('supplier', null, '1'), '1/0/1/0/0/1/' || ((:'once'::jsonb->>'absent')::int - 1)::text || '/false');

-- ── D) 큰 종류 — product 한 번(20000) · 기본 5000 묶음 · customer 남은 것 ──
select clock_timestamp() as t_d0 \gset
select pg_temp.adm('select public.qbo_match_auto(''product'', null, 20000)::text') as d1 \gset
select pg_temp.chk('D1 product 한 번(20000) — considered = 짝 없는 활성 product · done true · (sku 비면 전부 absent)', (:'d1'::jsonb->>'considered') || ' ' || (:'d1'::jsonb->>'done') || ' ' || (((:'d1'::jsonb->>'linked')::int + (:'d1'::jsonb->>'absent')::int + (:'d1'::jsonb->>'ambiguous')::int) = (:'d1'::jsonb->>'considered')::int)::text, :n_prod_unl || ' true true');
select pg_temp.chk('D1b product 한 번 — 10 초 안(실측 시간은 아래 줄)', (clock_timestamp() - :'t_d0'::timestamptz < interval '10 seconds')::text, 'true');
select clock_timestamp() - :'t_d0'::timestamptz as product_once_elapsed;
select pg_temp.chk('D2 임시 표 넷 analyze 흔적 — reltuples = 실제 행(t_ims = 짝 없는 product · t_ent = Item · t_cand · t_pick) · pg_stats 있음', (select string_agg(c.relname || ':' || c.reltuples::int::text, ' ' order by c.relname) from pg_class c where c.relnamespace = pg_my_temp_schema() and c.relname in ('t_ims', 't_ent', 't_cand', 't_pick')) || ' ' || (select count(distinct tablename)::text from pg_stats where tablename in ('t_ims', 't_ent', 't_pick')),
  't_cand:' || ((:'d1'::jsonb->>'linked')::int + (:'d1'::jsonb->>'ambiguous')::int)::text || ' t_ent:' || :n_item || ' t_ims:' || :n_prod_unl || ' t_pick:' || :n_prod_unl || ' 3');
select pg_temp.chk('D3 product 기본(5000) 에서 짝 없는 것만 다시 — considered = min(5000, 남은 수) · remaining · done 맞물림', (select (j->>'considered') || ' ' || (j->>'remaining') || ' ' || (j->>'done') from (select pg_temp.adm('select public.qbo_match_auto(''product'')::text')::jsonb j) x),
  least(5000, :n_prod_unl - (:'d1'::jsonb->>'linked')::int)::text || ' ' || greatest(:n_prod_unl - (:'d1'::jsonb->>'linked')::int - 5000, 0)::text || ' ' || (:n_prod_unl - (:'d1'::jsonb->>'linked')::int <= 5000)::text);
select pg_temp.chk('D4 customer — 남은 것만(1b 가 9,764 를 이미 지었다) · done true', (select (j->>'considered') || ' ' || (j->>'done') from (select pg_temp.adm('select public.qbo_match_auto(''customer'', null, 20000)::text')::jsonb j) x), :n_cust_unl || ' true');

-- ── L) REST 두 겹 ① — 새 함수의 update · delete 는 깊이 0 WHERE ──
select pg_temp.chk('L1 nowhere 스캐너 = 0(qbo_match_auto · qbo_ims_rows)', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_match_auto', 'qbo_ims_rows') and pg_temp.nowhere(p.prosrc) <> 0), null);

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 as staff_same, (select count(*) from public.ims_staff where email like 'qbo-sync-1c-%') = 0 as fake_staff_gone,
       (select count(*) from public.qbo_link) = :n_link0 as links_same, (select count(*) from public.qbo_entity) = :n_ent0 as entities_same;
\if :{?mig}
select (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_match_auto' and pg_get_function_identity_arguments(p.oid) = 'p_kind text') = 1 as old_signature_back_as_expected;
\else
select (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_match_auto' and pg_get_function_identity_arguments(p.oid) = 'p_kind text, p_after text, p_limit integer') = 1 as new_signature_present;
\endif
