-- supabase/tests/chip_1_check.sql — chip-1 so_chip_ids() · so_chips_many() 검증 (2026-10-26 · 판정 465 · 479 ~ 481 · deferred 235)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음: 행 수 · 시퀀스) → begin → (-v mig 면 \i) → 가짜 오더 여덟(replica · rollback) → 함수 꼴 · 권한 · 가짜 직원 호출 · 묶음 넷 = 독립 식 · 칩 = 조합마다 · 걸린 시간 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261026201550_chip_1_so_chips.sql -f supabase/tests/chip_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험 = 확인 = 아래 EXPECT_OK · 적용 전 마른 실행(-v mig 없음)은 OK 9(S0 · P7 · P8 · B6 · C12 ~ C16 — 빈 집합끼리 같다) · 나머지 MISMATCH(아직 창구 없음 — 정상)
--   쓰기 0 — 창구 둘은 stable · 가짜 오더 · 직원은 rollback · so · so_line · so_reserve · so_backorder_close · ims_staff 행 수 · so_number_seq 전후 대조(so_number 는 직접 준다 — 시퀀스를 안 당긴다)
\set ON_ERROR_STOP on
\set EXPECT_OK 44
\pset pager off
select (select count(*) from public.so) as n_so, (select count(*) from public.so_line) as n_sl, (select count(*) from public.so_reserve) as n_rs,
       (select count(*) from public.so_backorder_close) as n_bc, (select count(*) from public.ims_staff) as n_staff,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_chip_ids', 'so_chips_many')) as n_fn0 \gset
select last_value as seq_last, is_called::text as seq_called from public.so_number_seq \gset
select c.id::text as cust from public.customer c where c.is_active order by c.name limit 1 \gset
select p.id::text as prod, p.sku as psku from public.product p where p.is_active and p.sellable and p.parent_product_id is null order by p.sku limit 1 \gset
select r.id::text as cur from public.ref_currency r order by r.code limit 1 \gset
\echo '── 기준: so' :n_so '· so_line' :n_sl '· so_reserve' :n_rs '· so_backorder_close' :n_bc '· ims_staff' :n_staff '· chip fns' :n_fn0 '· seq' :seq_last :seq_called
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.j(p text) returns jsonb language plpgsql as $$
begin
  if p is null or left(p, 1) not in ('[', '{') then return null; end if;
  return p::jsonb;
end $$;

-- ── 가짜 오더 여덟(replica — 문지기 · 큐 트리거를 비껴 · 번호 직접 · rollback) ──
--   F1 allocated 2 줄 · F2 backorder 1 + allocated 1 · F3 preorder 1 + hold 1(칩 둘) · F4 confirmed · 예약 닫힘 · close 있음(ended)
--   F5 confirmed · 예약 없음 · close 없음(서비스 꼴 — ended 아님) · F6 at_wms + 열린 backorder(status 무관) · F7 backorder 닫힘 + allocated(백오더 아님) · F8 cancelled · close 있음(ended 아님)
set local session_replication_role = replica;
create temp table t_f (k text, so_id uuid default gen_random_uuid(), status text, so_number text);
insert into t_f (k, status, so_number) values
  ('F1', 'confirmed', 'SO-99901'), ('F2', 'confirmed', 'SO-99902'), ('F3', 'confirmed', 'SO-99903'), ('F4', 'confirmed', 'SO-99904'),
  ('F5', 'confirmed', 'SO-99905'), ('F6', 'at_wms',    'SO-99906'), ('F7', 'confirmed', 'SO-99907'), ('F8', 'cancelled', 'SO-99908');
insert into public.so (id, so_number, customer_id, channel, intake, currency_id, status, confirmed_at, closed_at, closed_reason, at_wms_at)
  select so_id, so_number, :'cust'::uuid, 'warehouse', 'manual', :'cur'::uuid, status, now() - interval '2 day',
         case when status = 'cancelled' then now() - interval '1 day' end, case when status = 'cancelled' then 'expired' end,
         case when status = 'at_wms' then now() - interval '1 day' end
  from t_f;
create temp table t_l (k text, ln int, line_id uuid default gen_random_uuid());
insert into t_l (k, ln) values ('F1', 1), ('F1', 2), ('F2', 1), ('F2', 2), ('F3', 1), ('F3', 2), ('F4', 1), ('F5', 1), ('F6', 1), ('F6', 2), ('F7', 1), ('F7', 2), ('F8', 1);
insert into public.so_line (id, so_id, line_no, product_id, sku, pack_factor, qty_ordered, unit_price)
  select l.line_id, f.so_id, l.ln, :'prod'::uuid, :'psku', 1, 5, 1.00 from t_l l join t_f f on f.k = l.k;
-- 예약: (k, ln, kind, 열림)
insert into public.so_reserve (so_line_id, qty_allocated, kind, released_at, released_reason)
  select l.line_id, 5, x.kind, case when x.open then null else now() - interval '1 day' end, case when x.open then null else 'closed' end
  from (values ('F1', 1, 'allocated', true), ('F1', 2, 'allocated', true),
               ('F2', 1, 'backorder', true), ('F2', 2, 'allocated', true),
               ('F3', 1, 'preorder',  true), ('F3', 2, 'hold',      true),
               ('F4', 1, 'backorder', false),
               ('F6', 1, 'backorder', true), ('F6', 2, 'allocated', true),
               ('F7', 1, 'backorder', false), ('F7', 2, 'allocated', true),
               ('F8', 1, 'backorder', false)) x(k, ln, kind, open)
  join t_l l on l.k = x.k and l.ln = x.ln;
insert into public.so_backorder_close (so_line_id, end_kind, qty_open)
  select l.line_id, 'expired', 5 from t_l l where (l.k, l.ln) in (('F4', 1), ('F8', 1));
set local session_replication_role = origin;
select count(*)::text as n_fake from public.so where so_number like 'SO-9990%' \gset
select pg_temp.chk('S0 eight fake orders in', :'n_fake', '8');

-- ── F 함수 꼴 ──
select count(*)::text as n_fn, coalesce(string_agg(p.proname || ':' || p.provolatile::text || ':' || p.prosecdef::text || ':' || coalesce(array_to_string(p.proconfig, ','), '-'), ' ' order by p.proname), '-') as shape,
       coalesce(string_agg(left(obj_description(p.oid, 'pg_proc'), 6), ' ' order by p.proname), '-') as cmts
from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_chip_ids', 'so_chips_many') \gset
select pg_temp.chk('F1 two functions', :'n_fn', '2');
select pg_temp.chk('F2 stable · invoker · search_path', :'shape', 'so_chip_ids:s:false:search_path=public, pg_temp so_chips_many:s:false:search_path=public, pg_temp');
select pg_temp.chk('F3 comments start chip-1', :'cmts', 'chip-1 chip-1');
select pg_temp.chk('F4 so_chip_ids returns jsonb', pg_temp.run('select prorettype::regtype::text from pg_proc where pronamespace = ''public''::regnamespace and proname = ''so_chip_ids'''), 'jsonb');
select pg_temp.chk('F5 so_chips_many columns', pg_temp.run('select string_agg(u.n, '','' order by u.o) from pg_proc p, unnest(p.proargnames, p.proargmodes) with ordinality u(n, m, o) where p.pronamespace = ''public''::regnamespace and p.proname = ''so_chips_many'' and u.m = ''t'''), 'so_id,n_allocated,n_backorder,n_preorder,n_hold,ended');

-- ── P 권한 · 가짜 직원(열쇠 0) 호출 · 걸린 시간 ──
select pg_temp.chk('P1 authenticated can execute both', pg_temp.run('select (has_function_privilege(''authenticated'', ''public.so_chip_ids()'', ''execute'') and has_function_privilege(''authenticated'', ''public.so_chips_many(uuid[])'', ''execute''))::text'), 'true');
select pg_temp.chk('P2 anon cannot', pg_temp.run('select (has_function_privilege(''anon'', ''public.so_chip_ids()'', ''execute'') or has_function_privilege(''anon'', ''public.so_chips_many(uuid[])'', ''execute''))::text'), 'false');
select pg_temp.chk('P3 service_role cannot', pg_temp.run('select (has_function_privilege(''service_role'', ''public.so_chip_ids()'', ''execute'') or has_function_privilege(''service_role'', ''public.so_chips_many(uuid[])'', ''execute''))::text'), 'false');
select pg_temp.chk('P4 no PUBLIC grant', pg_temp.run('select (count(*) = 2)::text from pg_proc p where p.pronamespace = ''public''::regnamespace and p.proname in (''so_chip_ids'', ''so_chips_many'') and p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0)'), 'true');
insert into public.ims_staff (auth_user_id, email, name, role, perms, is_active) values (gen_random_uuid(), 'chip1-min@test.invalid', 'chip1 no keys', 'worker', '[]', true);
select auth_user_id::text as u_min from public.ims_staff where email = 'chip1-min@test.invalid' \gset
select string_agg(id::text, ',') as page_ids from (select id from public.so order by created_at desc limit 100) x \gset
select set_config('request.jwt.claims', json_build_object('sub', :'u_min', 'role', 'authenticated')::text, true);
set local role authenticated;
select clock_timestamp() as t0 \gset
select pg_temp.run('select set_config(''app.ids'', public.so_chip_ids()::text, true)') as r_ids \gset
select clock_timestamp() as t1 \gset
select pg_temp.run(format('select set_config(''app.chips'', coalesce((select jsonb_agg(to_jsonb(c)) from public.so_chips_many(array[%s]::uuid[]) c), ''[]'')::text, true)', (select string_agg(quote_literal(x), ',') from unnest(string_to_array(:'page_ids', ',')) x))) as r_page \gset
select clock_timestamp() as t2 \gset
reset role;
select pg_temp.chk('P5 fake staff: so_chip_ids ok', case when :'r_ids' like 'ERR%' then :'r_ids' else 'OK' end, 'OK');
select pg_temp.chk('P6 fake staff: so_chips_many(100 ids) ok', case when :'r_page' like 'ERR%' then :'r_page' else 'OK' end, 'OK');
select round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000)::int as ms_ids, round(extract(epoch from (:'t2'::timestamptz - :'t1'::timestamptz)) * 1000)::int as ms_page \gset
select pg_temp.chk(format('P7 so_chip_ids < 8000 ms (measured %s ms) · so_chips_many 100 ids (measured %s ms)', :ms_ids, :ms_page), (:ms_ids < 8000 and :ms_page < 8000)::text, 'true');
select pg_temp.chk('P8 fake staff count', (select count(*)::text from public.ims_staff where email = 'chip1-min@test.invalid'), '1');
create temp table t_ids as select k, (pg_temp.j(current_setting('app.ids', true)) -> k) as arr from (values ('backorder'), ('preorder'), ('hold'), ('ended')) v(k);
create temp table t_page as select (c->>'so_id')::uuid as so_id, (c->>'n_allocated')::int n_allocated, (c->>'n_backorder')::int n_backorder, (c->>'n_preorder')::int n_preorder, (c->>'n_hold')::int n_hold, (c->>'ended')::boolean ended
  from jsonb_array_elements(coalesce(pg_temp.j(current_setting('app.chips', true)), '[]'::jsonb)) c;
select pg_temp.chk('P9 so_chips_many(100 page ids) = 100 rows', (select count(*)::text from t_page), '100');

-- ── B 묶음 넷 = 독립 식(가짜 포함 · 실제 행 포함) ──
create temp table t_exp as
  select 'backorder' as k, l.so_id from public.so_reserve r join public.so_line l on l.id = r.so_line_id where r.released_at is null and r.kind = 'backorder' group by l.so_id
  union all select 'preorder', l.so_id from public.so_reserve r join public.so_line l on l.id = r.so_line_id where r.released_at is null and r.kind = 'preorder' group by l.so_id
  union all select 'hold', l.so_id from public.so_reserve r join public.so_line l on l.id = r.so_line_id where r.released_at is null and r.kind = 'hold' group by l.so_id
  union all select 'ended', s.id from public.so s where s.status = 'confirmed'
       and not exists (select 1 from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id and r.released_at is null)
       and exists (select 1 from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id where l.so_id = s.id);
create temp table t_got as select i.k, (x.v)::uuid as so_id from t_ids i, lateral jsonb_array_elements_text(coalesce(i.arr, '[]'::jsonb)) x(v);
select pg_temp.chk('B1 four keys present', (select string_agg(k, ',' order by k) from t_ids where arr is not null), 'backorder,ended,hold,preorder');
select pg_temp.chk('B2 backorder set = independent', (select count(*)::text from ((select so_id from t_got where k = 'backorder' except select so_id from t_exp where k = 'backorder') union all (select so_id from t_exp where k = 'backorder' except select so_id from t_got where k = 'backorder')) x), '0');
select pg_temp.chk('B3 preorder set = independent',  (select count(*)::text from ((select so_id from t_got where k = 'preorder'  except select so_id from t_exp where k = 'preorder')  union all (select so_id from t_exp where k = 'preorder'  except select so_id from t_got where k = 'preorder'))  x), '0');
select pg_temp.chk('B4 hold set = independent',      (select count(*)::text from ((select so_id from t_got where k = 'hold'      except select so_id from t_exp where k = 'hold')      union all (select so_id from t_exp where k = 'hold'      except select so_id from t_got where k = 'hold'))      x), '0');
select pg_temp.chk('B5 ended set = independent',     (select count(*)::text from ((select so_id from t_got where k = 'ended'     except select so_id from t_exp where k = 'ended')     union all (select so_id from t_exp where k = 'ended'     except select so_id from t_got where k = 'ended'))     x), '0');
select pg_temp.chk('B6 no duplicates inside a bucket', (select (count(*) - count(distinct (k, so_id)))::text from t_got), '0');
select pg_temp.chk('B7 backorder ∋ F2 F6 · ∌ F1 F3 F4 F5 F7 F8', (select string_agg(f.k, ',' order by f.k) from t_f f where f.so_id in (select so_id from t_got where k = 'backorder')), 'F2,F6');
select pg_temp.chk('B8 preorder ∋ F3 only (of fakes)', (select string_agg(f.k, ',' order by f.k) from t_f f where f.so_id in (select so_id from t_got where k = 'preorder')), 'F3');
select pg_temp.chk('B9 hold ∋ F3 only (of fakes)',     (select string_agg(f.k, ',' order by f.k) from t_f f where f.so_id in (select so_id from t_got where k = 'hold')), 'F3');
select pg_temp.chk('B10 ended ∋ F4 only (of fakes — F5 no close · F8 cancelled)', (select string_agg(f.k, ',' order by f.k) from t_f f where f.so_id in (select so_id from t_got where k = 'ended')), 'F4');
select pg_temp.chk('B11 SO-25088 (ruling 480 example) in ended when still confirmed with close rows',
  (select (s.id in (select so_id from t_got where k = 'ended'))::text from public.so s where s.so_number = 'SO-25088'),
  (select (s.status = 'confirmed' and not exists (select 1 from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id and r.released_at is null)
          and exists (select 1 from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id where l.so_id = s.id))::text from public.so s where s.so_number = 'SO-25088'));
-- Confirmed(다 잡힘) = status confirmed − 넷의 합집합 : 가짜 중 F1(allocated 2) · F5(예약 없음 · close 없음) · F7(백오더는 닫혔고 allocated 만 열림)
select pg_temp.chk('B12 Confirmed(all allocated) of fakes = F1 F5 F7 (F7: backorder released · allocated open)', (select string_agg(f.k, ',' order by f.k) from t_f f where f.status = 'confirmed' and f.so_id not in (select so_id from t_got)), 'F1,F5,F7');

-- ── C 칩: 조합마다 (so_chips_many 를 가짜 여덟 + 모르는 id + 겹친 id 로) ──
select (to_regprocedure('public.so_chips_many(uuid[])') is not null) as landed \gset
\if :landed
create temp table t_c as select c.* from public.so_chips_many((select array_agg(so_id) || array[gen_random_uuid()] || (select array_agg(so_id) from t_f where k = 'F1') from t_f)) c;
\else
create temp table t_c (so_id uuid, n_allocated int, n_backorder int, n_preorder int, n_hold int, ended boolean);
\endif
select pg_temp.chk('C0 eight rows (unknown id none · duplicate once)', (select count(*)::text from t_c), '8');
select pg_temp.chk('C1 F1 allocated 2 → 2,0,0,0,f', (select n_allocated || ',' || n_backorder || ',' || n_preorder || ',' || n_hold || ',' || ended::text from t_c c join t_f f on f.so_id = c.so_id where f.k = 'F1'), '2,0,0,0,false');
select pg_temp.chk('C2 F2 backorder+allocated → 1,1,0,0,f', (select n_allocated || ',' || n_backorder || ',' || n_preorder || ',' || n_hold || ',' || ended::text from t_c c join t_f f on f.so_id = c.so_id where f.k = 'F2'), '1,1,0,0,false');
select pg_temp.chk('C3 F3 preorder+hold → 0,0,1,1,f', (select n_allocated || ',' || n_backorder || ',' || n_preorder || ',' || n_hold || ',' || ended::text from t_c c join t_f f on f.so_id = c.so_id where f.k = 'F3'), '0,0,1,1,false');
select pg_temp.chk('C4 F4 ended → 0,0,0,0,t', (select n_allocated || ',' || n_backorder || ',' || n_preorder || ',' || n_hold || ',' || ended::text from t_c c join t_f f on f.so_id = c.so_id where f.k = 'F4'), '0,0,0,0,true');
select pg_temp.chk('C5 F5 no reserve no close → 0,0,0,0,f', (select n_allocated || ',' || n_backorder || ',' || n_preorder || ',' || n_hold || ',' || ended::text from t_c c join t_f f on f.so_id = c.so_id where f.k = 'F5'), '0,0,0,0,false');
select pg_temp.chk('C6 F6 at_wms + backorder → 1,1,0,0,f', (select n_allocated || ',' || n_backorder || ',' || n_preorder || ',' || n_hold || ',' || ended::text from t_c c join t_f f on f.so_id = c.so_id where f.k = 'F6'), '1,1,0,0,false');
select pg_temp.chk('C7 F7 released backorder + allocated → 1,0,0,0,f', (select n_allocated || ',' || n_backorder || ',' || n_preorder || ',' || n_hold || ',' || ended::text from t_c c join t_f f on f.so_id = c.so_id where f.k = 'F7'), '1,0,0,0,false');
select pg_temp.chk('C8 F8 cancelled + close → 0,0,0,0,f', (select n_allocated || ',' || n_backorder || ',' || n_preorder || ',' || n_hold || ',' || ended::text from t_c c join t_f f on f.so_id = c.so_id where f.k = 'F8'), '0,0,0,0,false');
select pg_temp.chk('C9 201 ids refused', (pg_temp.run('select count(*)::text from public.so_chips_many((select array_agg(gen_random_uuid()) from generate_series(1, 201)))') like 'ERR P0001: so_chips_many takes at most 200 order ids%')::text, 'true');
select pg_temp.chk('C10 empty · null ids → 0 rows', pg_temp.run('select (select count(*) from public.so_chips_many(array[]::uuid[])) || '','' || (select count(*) from public.so_chips_many(array[null]::uuid[]))'), '0,0');
-- 칩 ↔ 묶음 일치(모든 오더 · 200 씩)
\if :landed
create temp table t_all as
  select c.* from (select array_agg(id) as ids from (select id, (row_number() over (order by id) - 1) / 200 as b from public.so) x group by b) g, lateral public.so_chips_many(g.ids) c;
\else
create temp table t_all (so_id uuid, n_allocated int, n_backorder int, n_preorder int, n_hold int, ended boolean);
\endif
select pg_temp.chk('C11 so_chips_many over every order = so count', (select count(*)::text from t_all), (select count(*)::text from public.so));
select pg_temp.chk('C12 chips n_backorder>0 set = ids.backorder', (select count(*)::text from ((select so_id from t_all where n_backorder > 0 except select so_id from t_got where k = 'backorder') union all (select so_id from t_got where k = 'backorder' except select so_id from t_all where n_backorder > 0)) x), '0');
select pg_temp.chk('C13 chips n_preorder>0 set = ids.preorder',   (select count(*)::text from ((select so_id from t_all where n_preorder > 0  except select so_id from t_got where k = 'preorder')  union all (select so_id from t_got where k = 'preorder'  except select so_id from t_all where n_preorder > 0))  x), '0');
select pg_temp.chk('C14 chips n_hold>0 set = ids.hold',           (select count(*)::text from ((select so_id from t_all where n_hold > 0      except select so_id from t_got where k = 'hold')      union all (select so_id from t_got where k = 'hold'      except select so_id from t_all where n_hold > 0))      x), '0');
select pg_temp.chk('C15 chips ended set = ids.ended',             (select count(*)::text from ((select so_id from t_all where ended           except select so_id from t_got where k = 'ended')     union all (select so_id from t_got where k = 'ended'     except select so_id from t_all where ended))           x), '0');
select pg_temp.chk('C16 ended rows have no open reservation', (select count(*)::text from t_all where ended and (n_allocated + n_backorder + n_preorder + n_hold) > 0), '0');

-- ── 실측(보고용 · 가짜 여덟 포함) ──
\echo '── 묶음 크기(가짜 8 포함): backorder · preorder · hold · ended · 칩 둘 이상인 오더'
select (select count(*) from t_got where k = 'backorder') as backorder, (select count(*) from t_got where k = 'preorder') as preorder,
       (select count(*) from t_got where k = 'hold') as hold, (select count(*) from t_got where k = 'ended') as ended,
       (select count(*) from t_all where (n_backorder > 0)::int + (n_preorder > 0)::int + (n_hold > 0)::int + ended::int >= 2) as multi_chip;
\echo '── so_chips_many 반환 예(가짜 F2 · F3 · F4)'
select f.k, c.* from t_c c join t_f f on f.so_id = c.so_id where f.k in ('F2', 'F3', 'F4') order by f.k;

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.so) = :n_so as so_same, (select count(*) from public.so_line) = :n_sl as so_line_same,
       (select count(*) from public.so_reserve) = :n_rs as so_reserve_same, (select count(*) from public.so_backorder_close) = :n_bc as close_same,
       (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_chip_ids', 'so_chips_many')) = :n_fn0 as fn_count_same_as_before,
       (select last_value = :seq_last and is_called::text = :'seq_called' from public.so_number_seq) as seq_same;
