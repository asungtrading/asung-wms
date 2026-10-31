-- supabase/tests/cbal_1_check.sql — cbal-1 손님 잔액 여러 명 읽기 창구(so_customer_balance_many) 검증 (2026-10-31 · 판정 912)
-- [테스트 · Asung-IMS] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞: 단일 창구 md5 · 새 함수 유무 · 표 수) → begin → (-v mig 면 \i) → 가짜 직원 둘 → 검사 → rollback → Z1
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261031214531_cbal_1_customer_balance_many.sql -f supabase/tests/cbal_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 37 · 확인(-v mig 없이) 36(M1 은 시험 갈래만) · MISMATCH 0 · Z1 OK 한 줄 · 「Time:」 두 줄(T1 100 id · T2 null 모드 — 8 초 안)
--   쓰기는 가짜 직원 둘(replica · cbal1-*)뿐 · 창구는 읽기만(S1 이 WHERE 없는 update · delete 0 을 정적으로 센다)
--   잠금 규칙: 기준값은 begin 앞 · lock_timeout 3s · begin ~ rollback 시간을 끝에 찍는다
\set ON_ERROR_STOP on
\pset pager off
select coalesce((select value from public.inv_config where key = 'db_role'), '(missing)') as db_role \gset
select (:'db_role' = 'test') as is_test \gset
\echo '── db_role' :db_role
\if :is_test
\else
\echo 'STOP — inv_config.db_role is not test — nothing was run'
\quit
\endif
-- ── 기준(begin 앞) ──
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5, p.proacl::text as acl, p.prosecdef, p.provolatile, p.proconfig::text as cfg
  from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_customer_balance', 'so_customer_balance_many');
select (select count(*) from t_pre where proname = 'so_customer_balance_many') as fn_n0 \gset
select (select count(*) from public.customer) as w_cust, (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.so_payment) as w_pay,
       (select count(*) from public.so_invoice) as w_inv, (select count(*) from public.so_credit) as w_cred \gset
\echo '── 기준: customer' :w_cust '· staff' :w_staff '· so_payment' :w_pay '· so_invoice' :w_inv '· so_credit' :w_cred '· many 있음' :fn_n0
begin;
set local lock_timeout = '3s';
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
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 행을 글자 한 줄로(customer_id · 통화 순) — 단일 창구를 id 마다 lateral · many 를 한 번 · 둘이 글자까지 같아야 한다(순서는 정렬로 고정 · 집합 비교)
create function pg_temp.rows_single(p_ids uuid[]) returns text language sql stable as $$
  select coalesce(string_agg(k.id || '|' || b.currency_code || '|' || b.currency_id || '|' || b.received || '|' || b.reserved_deposit || '|' || b.owed_credit || '|' || b.available || '|' || b.open_invoices || '|' || b.open_invoices_due, ' ; ' order by k.id, b.currency_code), '(0 rows)')
    from (select distinct x as id from unnest(p_ids) x where x is not null) k cross join lateral public.so_customer_balance(k.id) b;
$$;
create function pg_temp.rows_many(p_ids uuid[]) returns text language sql stable as $$
  select coalesce(string_agg(m.customer_id || '|' || m.currency_code || '|' || m.currency_id || '|' || m.received || '|' || m.reserved_deposit || '|' || m.owed_credit || '|' || m.available || '|' || m.open_invoices || '|' || m.open_invoices_due, ' ; ' order by m.customer_id, m.currency_code), '(0 rows)')
    from public.so_customer_balance_many(p_ids) m;
$$;
-- 가짜 직원으로 부른다(authenticated 역할 · 가짜 uid) · p_fn = 'many' | 'single'
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
create function pg_temp.call_as(p_uid text, p_fn text, p_ids uuid[], p_role text default 'authenticated') returns text language plpgsql as $$
declare v text;
begin
  perform pg_temp.as_user(p_uid, p_role);
  execute format('set local role %I', p_role);
  if p_fn = 'many' then v := pg_temp.rows_many(p_ids); else v := pg_temp.rows_single(p_ids); end if;
  reset role;
  return v;
exception when others then reset role; return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- safeupdate 의 규칙을 정적으로 센다(ar_2b_check 와 같은 스캐너): 깊이 0 WHERE 없는 update · delete
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

-- ── 가짜(replica · cbal1-): 직원 둘 — sales 열쇠 · 열쇠 없음 ──
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'cbal1-sales@test.invalid', 'CBAL1 Sales', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as u_sales \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'cbal1-nokey@test.invalid', 'CBAL1 NoKey', 'worker', '["ims"]', '{}') returning auth_user_id::text as u_nokey \gset
set local session_replication_role = origin;

-- ── 표본 다섯(📌 cbal-1): Clore Inc. · KimC Trading LLC · PiiQ Design House · 본사로 청구되는 매장 하나 · 잔액 없는 손님 하나 ──
select coalesce((select c.id::text from public.customer c where c.name = 'Clore Inc.' order by c.is_active desc limit 1), '') as clore \gset
select coalesce((select c.id::text from public.customer c where c.name = 'KimC Trading LLC' order by c.is_active desc limit 1), '') as kimc \gset
select coalesce((select c.id::text from public.customer c where c.name = 'PiiQ Design House' order by c.is_active desc limit 1), '') as piiq \gset
select coalesce((select c.id::text from public.customer c
                  where c.default_bill_to_customer_id is not null and c.default_bill_to_customer_id <> c.id and c.is_active
                  order by (exists (select 1 from public.so_invoice i where i.bill_to_customer_id = c.default_bill_to_customer_id and i.status = 'issued')) desc, c.name limit 1), '') as store \gset
select coalesce((select c.id::text from public.customer c
                  where c.is_active and not exists (select 1 from public.so_payment p where p.customer_id = c.id) and not exists (select 1 from public.so_credit r where r.customer_id = c.id)
                    and not exists (select 1 from public.so_invoice i where i.bill_to_customer_id = c.id) order by c.name limit 1), '') as zero \gset
select (nullif(:'clore', '') is not null and nullif(:'kimc', '') is not null and nullif(:'piiq', '') is not null and nullif(:'store', '') is not null and nullif(:'zero', '') is not null) as have5 \gset
\echo '── 표본: clore' :clore '· kimc' :kimc '· piiq' :piiq '· store' :store '· zero' :zero
select pg_temp.chk('M0 so_customer_balance 마지막 정의 = 20260925205011:511 ~ 557 (DB prosrc md5 · begin 앞)', (select md5 from t_pre where proname = 'so_customer_balance'), '801f4408593833f8cdc42691486a4a76');
select pg_temp.chk('S0 표본 다섯이 모두 있다(이름 셋 · 본사로 청구되는 매장 · 거래 없는 손님)', :'have5'::text, 't');

-- ── A) 표본: many = 손님마다 단일(글자까지 · 정렬 고정) ──
select pg_temp.chk('A1 Clore Inc. — many = single (이월 107 장 · CAD)', pg_temp.rows_many(array[:'clore'::uuid]), pg_temp.rows_single(array[:'clore'::uuid]));
select pg_temp.chk('A1b Clore Inc. 행이 있다(0 rows 가 아니다)', (pg_temp.rows_many(array[:'clore'::uuid]) <> '(0 rows)')::text, 'true');
select pg_temp.chk('A2 KimC Trading LLC — many = single (USD)', pg_temp.rows_many(array[:'kimc'::uuid]), pg_temp.rows_single(array[:'kimc'::uuid]));
select pg_temp.chk('A2b KimC 에 USD 행이 있다', (select (count(*) > 0)::text from public.so_customer_balance_many(array[:'kimc'::uuid]) m where m.currency_code = 'USD'), 'true');
select pg_temp.chk('A3 PiiQ Design House — many = single (받아 둔 돈)', pg_temp.rows_many(array[:'piiq'::uuid]), pg_temp.rows_single(array[:'piiq'::uuid]));
select pg_temp.chk('A3b PiiQ received > 0', (select (coalesce(sum(m.received), 0) > 0)::text from public.so_customer_balance_many(array[:'piiq'::uuid]) m), 'true');
select pg_temp.chk('A4 본사로 청구되는 매장 — many = single (매장 자신의 행 · 되돌림 없음 · 단일과 같다)', pg_temp.rows_many(array[:'store'::uuid]), pg_temp.rows_single(array[:'store'::uuid]));
select pg_temp.chk('A5 거래 없는 손님 — many 0 행 = single 0 행', pg_temp.rows_many(array[:'zero'::uuid]), pg_temp.rows_single(array[:'zero'::uuid]));
select pg_temp.chk('A5b 거래 없는 손님은 (0 rows)', pg_temp.rows_many(array[:'zero'::uuid]), '(0 rows)');
select pg_temp.chk('A6 다섯을 한 번에 — many = 단일 다섯 합(집합 · 글자)', pg_temp.rows_many(array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid, :'store'::uuid, :'zero'::uuid]),
  pg_temp.rows_single(array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid, :'store'::uuid, :'zero'::uuid]));
select pg_temp.chk('A7 다섯 — 여덟 칸 합(received · reserved · owed · available · open_invoices · due)이 같다',
  (select coalesce(sum(m.received), 0) || '/' || coalesce(sum(m.reserved_deposit), 0) || '/' || coalesce(sum(m.owed_credit), 0) || '/' || coalesce(sum(m.available), 0) || '/' || coalesce(sum(m.open_invoices), 0) || '/' || coalesce(sum(m.open_invoices_due), 0)
     from public.so_customer_balance_many(array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid, :'store'::uuid, :'zero'::uuid]) m),
  (select coalesce(sum(b.received), 0) || '/' || coalesce(sum(b.reserved_deposit), 0) || '/' || coalesce(sum(b.owed_credit), 0) || '/' || coalesce(sum(b.available), 0) || '/' || coalesce(sum(b.open_invoices), 0) || '/' || coalesce(sum(b.open_invoices_due), 0)
     from unnest(array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid, :'store'::uuid, :'zero'::uuid]) k(id) cross join lateral public.so_customer_balance(k.id) b));

-- ── N) null 모드 = 전 손님을 단일로 돌려 「칸 중 하나라도 0 이 아닌」 행의 집합과 같다(표본이 아니라 전부 — 손님 수는 기준 줄) ──
create temp table t_full as
  select c.id as customer_id, b.* from public.customer c cross join lateral public.so_customer_balance(c.id) b
   where b.received <> 0 or b.reserved_deposit <> 0 or b.owed_credit <> 0 or b.open_invoices <> 0 or b.open_invoices_due <> 0;
create temp table t_null as select * from public.so_customer_balance_many(null);
select pg_temp.chk('N1 null 모드 행 집합 = 전 손님 단일 · 0 아닌 행(글자 · 정렬 고정)',
  (select coalesce(string_agg(m.customer_id || '|' || m.currency_code || '|' || m.received || '|' || m.reserved_deposit || '|' || m.owed_credit || '|' || m.available || '|' || m.open_invoices || '|' || m.open_invoices_due, ' ; ' order by m.customer_id, m.currency_code), '(0 rows)') from t_null m),
  (select coalesce(string_agg(f.customer_id || '|' || f.currency_code || '|' || f.received || '|' || f.reserved_deposit || '|' || f.owed_credit || '|' || f.available || '|' || f.open_invoices || '|' || f.open_invoices_due, ' ; ' order by f.customer_id, f.currency_code), '(0 rows)') from t_full f));
select pg_temp.chk('N2 null 모드 행마다 칸 중 하나는 0 이 아니다(전부 0 인 행 0)', (select count(*)::text from t_null m where m.received = 0 and m.reserved_deposit = 0 and m.owed_credit = 0 and m.open_invoices = 0 and m.open_invoices_due = 0), '0');
select pg_temp.chk('N3 null 모드 손님 집합 = 전 손님 단일의 손님 집합(수가 같고 차집합 0)',
  (select count(distinct customer_id)::text || '/' || (select count(*) from (select customer_id from t_null except select customer_id from t_full) x) || '/' || (select count(*) from (select customer_id from t_full except select customer_id from t_null) y) from t_null),
  (select count(distinct customer_id)::text from t_full) || '/0/0');
select pg_temp.chk('N4 null 모드에 표본 셋(Clore · KimC · PiiQ)이 들어 있고 거래 없는 손님은 없다',
  (select (count(*) filter (where customer_id = :'clore'::uuid) > 0)::text || (count(*) filter (where customer_id = :'kimc'::uuid) > 0)::text || (count(*) filter (where customer_id = :'piiq'::uuid) > 0)::text || (count(*) filter (where customer_id = :'zero'::uuid) = 0)::text from t_null), 'truetruetruetrue');
select count(*) as n_null_rows, count(distinct customer_id) as n_null_cust from t_null \gset
\echo '── null 모드: 행' :n_null_rows '· 손님' :n_null_cust

-- ── E) 가장자리: 빈 배열 · 없는 id · 같은 id 두 번 · null 원소 · 501 거부 · 500 통과 ──
select pg_temp.chk('E1 빈 배열 = 0 행(null 모드가 아니다)', pg_temp.rows_many(array[]::uuid[]), '(0 rows)');
select pg_temp.chk('E2 없는 id = 0 행', pg_temp.rows_many(array['00000000-0000-0000-0000-000000000001'::uuid]), '(0 rows)');
select pg_temp.chk('E3 같은 id 두 번 = 한 번(Clore 두 번 = Clore 한 번)', pg_temp.rows_many(array[:'clore'::uuid, :'clore'::uuid]), pg_temp.rows_many(array[:'clore'::uuid]));
select pg_temp.chk('E4 null 원소는 건너뛴다([null, Clore] = Clore)', pg_temp.rows_many(array[null::uuid, :'clore'::uuid]), pg_temp.rows_many(array[:'clore'::uuid]));
select pg_temp.chk('E5 501 개 거부 — nothing was read', pg_temp.try('select count(*)::text from public.so_customer_balance_many((select array_agg(gen_random_uuid()) from generate_series(1, 501)))'),
  'ERR P0001: Too many customers in one call (501 — the limit is 500) — nothing was read');
select pg_temp.chk('E6 500 개(없는 id)는 거부가 아니라 0 행', pg_temp.try('select count(*)::text from public.so_customer_balance_many((select array_agg(gen_random_uuid()) from generate_series(1, 500)))'), '0');
select pg_temp.chk('E7 같은 id 501 번도 거부(상한은 배열 길이)', left(pg_temp.try(format('select count(*)::text from public.so_customer_balance_many((select array_agg(%L::uuid) from generate_series(1, 501)))', :'clore')), 41), 'ERR P0001: Too many customers in one call');

-- ── U) 가짜 직원 신원 — 문은 단일 창구와 같다(sales 열쇠 · 열쇠 없음 모두 같은 행 · anon 은 execute 거부) ──
select pg_temp.chk('U1 sales 열쇠 직원: many = single(같은 신원 · 다섯 표본)', pg_temp.call_as(:'u_sales', 'many', array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid, :'store'::uuid, :'zero'::uuid]),
  pg_temp.call_as(:'u_sales', 'single', array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid, :'store'::uuid, :'zero'::uuid]));
select pg_temp.chk('U2 열쇠 없는 직원: many = single(같은 신원 — 단일이 열쇠를 안 보니 여기도 같다)', pg_temp.call_as(:'u_nokey', 'many', array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid, :'store'::uuid, :'zero'::uuid]),
  pg_temp.call_as(:'u_nokey', 'single', array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid, :'store'::uuid, :'zero'::uuid]));
select pg_temp.chk('U3 sales 직원의 many = 소유자 실행과 같은 행(RLS 가 authenticated 전부라 값이 같다)', pg_temp.call_as(:'u_sales', 'many', array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid]), pg_temp.rows_many(array[:'clore'::uuid, :'kimc'::uuid, :'piiq'::uuid]));
select pg_temp.chk('U4 anon 은 execute 거부(단일과 같은 grant)', left(pg_temp.call_as('', 'many', array[:'clore'::uuid], 'anon'), 9), 'ERR 42501');
select pg_temp.chk('U5 anon 은 단일도 execute 거부', left(pg_temp.call_as('', 'single', array[:'clore'::uuid], 'anon'), 9), 'ERR 42501');

-- ── P) 함수 꼴 · 권한 = 단일 창구와 같은 문 ──
select pg_temp.chk('P1 many: stable · invoker · search_path 가 단일과 같다',
  (select p.prosecdef::text || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_customer_balance_many'),
  (select p.prosecdef::text || '/' || p.provolatile::text || '/' || coalesce(p.proconfig::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_customer_balance'));
select pg_temp.chk('P2 many: execute = authenticated 만(public · anon 없음) — 단일과 같다',
  has_function_privilege('authenticated', 'public.so_customer_balance_many(uuid[])', 'execute')::text || has_function_privilege('anon', 'public.so_customer_balance_many(uuid[])', 'execute')::text || has_function_privilege('public', 'public.so_customer_balance_many(uuid[])', 'execute')::text,
  has_function_privilege('authenticated', 'public.so_customer_balance(uuid)', 'execute')::text || has_function_privilege('anon', 'public.so_customer_balance(uuid)', 'execute')::text || has_function_privilege('public', 'public.so_customer_balance(uuid)', 'execute')::text);
select pg_temp.chk('P3 many 반환 칸 = customer_id + 단일의 여덟 칸(이름 · 순서)',
  pg_get_function_result('public.so_customer_balance_many(uuid[])'::regprocedure),
  replace(pg_get_function_result('public.so_customer_balance(uuid)'::regprocedure), 'TABLE(', 'TABLE(customer_id uuid, '));
select pg_temp.chk('P4 comment 에 판정 912', (select (coalesce(obj_description(p.oid, 'pg_proc'), '') like '%912%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_customer_balance_many'), 'true');

-- ── S) 정적: WHERE 없는 update · delete(safeupdate 규칙) 0 · 단일 창구 무접촉 ──
select pg_temp.chk('S1 스캐너 자기 시험', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('select 1 from t;')::text, '1010');
select pg_temp.chk('S2 many 의 WHERE 없는 update · delete 0(읽기만)', (select pg_temp.nowhere(p.prosrc)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_customer_balance_many'), '0');
select pg_temp.chk('S3 so_customer_balance 무접촉(prosrc md5 · acl · 꼴)', (select (md5(p.prosrc) = t.md5 and p.proacl::text is not distinct from t.acl and p.prosecdef = t.prosecdef)::text from pg_proc p join t_pre t on t.proname = p.proname where p.pronamespace = 'public'::regnamespace and p.proname = 'so_customer_balance'), 'true');
\if :{?mig}
select pg_temp.chk('M1 (시험 갈래) many 는 begin 앞에 없었다', :'fn_n0', '0');
\endif

-- ── T) 시간(REST statement_timeout 8 초 안) — 100 id · null 모드 ──
select array_agg(id) as ids100 from (select distinct customer_id as id from t_full order by 1 limit 100) x \gset
\timing on
select count(*) as t1_rows_100_ids from public.so_customer_balance_many(:'ids100'::uuid[]);
select count(*) as t2_rows_null_mode from public.so_customer_balance_many(null);
\timing off

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 300) || ' want=' || left(coalesce(want, '(null)'), 300) end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, count(*) as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.customer) = :w_cust and (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.so_payment) = :w_pay
            and (select count(*) from public.so_invoice) = :w_inv and (select count(*) from public.so_credit) = :w_cred
            and (select count(*) from public.ims_staff where email like 'cbal1-%') = 0
            and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_customer_balance_many') = :fn_n0
       then 'Z1 OK real rows unchanged (customer · staff · so_payment · so_invoice · so_credit · no cbal1 staff) · many presence = begin 앞' else 'Z1 FAIL' end as z1;
