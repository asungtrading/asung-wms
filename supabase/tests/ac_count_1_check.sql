-- supabase/tests/ac_count_1_check.sql — ac-count-1 검증: ims_action_counts = 화면 원문 넷 + fc_pickup_attention_list 행 수 (2026-11-06 · 지시서 ~/asung/prompts/ac-count-1.md)
-- [운영 메인 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞) → begin(lock_timeout 2s · statement_timeout 10s) → (-v mig 면 \i + G0) → 검증 → rollback → 실제 행 무변
--   Claude Code(시험): MIG=supabase/migrations/20261107023342_ac_count_1_action_counts.sql; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/ac_count_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 두 갈래의 차이는 G0(시험만) · 기대 OK 수 EXPECT_OK
--   읽기만 · 쓰기 하나(A8 · ref_payment_term.net_days 를 잠시 바꿔 「즉시 결제조건 없음」 → rollback) · 가짜 행 없음 · 신원은 실제 직원 셋(이름은 찍지 않는다 · 판정만)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 17
\else
\set EXPECT_OK 16
\endif
\pset pager off
select (select count(*) from public.ref_payment_term) as y_pt, (select count(*) from public.ref_payment_term where net_days = 0) as y_pt0, (select count(*) from public.ims_staff) as y_staff,
       (select count(*) from public.so_invoice) as y_inv, (select count(*) from public.customer) as y_cu,
       (select auth_user_id::text from public.ims_staff where id = '00000000-0000-4000-a000-000000000001') as u_mgr,
       (select auth_user_id::text from public.ims_staff where role = 'manager' and is_active and perms ? 'sales:read' and not perms ? 'sales' order by id limit 1) as u_read,
       (select auth_user_id::text from public.ims_staff where role = 'worker' and is_active and not perms ? 'sales' and not perms ? 'sales:read' and not perms ? 'ims' order by id limit 1) as u_none,
       (select id::text from public.ref_warehouse where name = 'Asung Trading Inc.') as wh_t,
       (select id::text from public.ref_warehouse where name = 'Asung - Edmonton') as wh_e \gset
\echo '── 기준: payment_term' :y_pt '(net 0:' :y_pt0 ') · staff' :y_staff '· invoice' :y_inv '· customer' :y_cu '· 신원 셋 있음:' :u_mgr :u_read :u_none
-- ── begin 앞(잠금 없음): 임시 표 · 임시 함수 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create temp table t_ids (k text primary key, v text);   -- psql 변수는 $$ 안(do)에서 안 풀린다 → 임시 표로 넘긴다(fc_pickup_4_check 와 같은 길)
insert into t_ids values ('u_mgr', :'u_mgr'), ('u_read', :'u_read'), ('u_none', :'u_none'), ('wh_t', :'wh_t'), ('wh_e', :'wh_e');
create function pg_temp.v(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
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
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
-- 화면 원문 넷 + 픽업 행 수 — manager-list.html ml v1.4 :84 ~ :88 · :99 ~ :102 그대로(in (…) 꼴 · 이름 거르기) · 비교의 「want」
create function pg_temp.screen(p_wh uuid default null) returns text language plpgsql as $$
declare v_name text; v_s text;
begin
  select w.name into v_name from public.ref_warehouse w where w.id = p_wh;
  select (public.so_stock_short_list(('{"unchecked_only":true}'::jsonb) || case when p_wh is null then '{}'::jsonb else jsonb_build_object('warehouse_id', p_wh) end)->>'unchecked_count')
      || '|' || (select count(*) from public.so_invoice_list where is_open = true and (p_wh is null or warehouse_id = p_wh)
                   and payment_term_name in (select name from public.ref_payment_term where net_days = 0 union all select '__none__' where not exists (select 1 from public.ref_payment_term where net_days = 0)))::text
      || '|' || (public.so_pos_open_list(p_wh)->>'stale_count')
      || '|' || (select count(*) from public.customer_review_list where (p_wh is null or default_location_name = v_name))::text
      || '|' || jsonb_array_length(public.fc_pickup_attention_list(p_wh)->'rows')::text
    into v_s;
  return v_s;
end $$;
create function pg_temp.five(p jsonb) returns text language sql as $$
  select coalesce(p->>'short', 'null') || '|' || coalesce(p->>'unpaid', 'null') || '|' || coalesce(p->>'pos', 'null') || '|' || coalesce(p->>'new_customers', 'null') || '|' || coalesce(p->>'pickups', 'null');
$$;
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

begin;
set local lock_timeout = '2s';
set local statement_timeout = '10s';
select clock_timestamp() as t_begin0000 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
select pg_temp.chk('G0 landing — ims_action_counts 1 · definer · stable · acl authenticated only',
  (select count(*)::text || ' ' || bool_and(prosecdef)::text || ' ' || string_agg(provolatile::text, '') || ' ' || coalesce(string_agg(proacl::text, ''), '-') from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_action_counts'),
  '1 true s {postgres=X/postgres,authenticated=X/postgres}');
\endif

do $$
declare p jsonb; p_t jsonb; p_e jsonb; v_s1 text; v_s2 text; v_s3 text; t0 timestamptz; v_ms numeric;
begin
  -- A: 신원 = 시험용 manager 행 00000000-…-0001(sales · master · 창고 전부) — 화면을 보는 사람
  perform pg_temp.as_user(pg_temp.v('u_mgr'));
  p := public.ims_action_counts(null);
  perform pg_temp.chk('A1 keys — 아홉(warehouse_id · warehouse 는 이견 5)', (select string_agg(k, ',' order by k) from jsonb_object_keys(p) k), 'at,new_customers,pickups,pos,short,total,unpaid,warehouse,warehouse_id');
  perform pg_temp.chk('A2 All branches — short|unpaid|pos|new_customers|pickups = 화면 원문 넷 + 픽업 행 수', pg_temp.five(p), pg_temp.screen(null));
  p_t := public.ims_action_counts(pg_temp.v('wh_t')::uuid);
  perform pg_temp.chk('A3 Toronto — 다섯 = 화면 원문(warehouse_id · location_id · default_location_name 이름)', pg_temp.five(p_t), pg_temp.screen(pg_temp.v('wh_t')::uuid));
  p_e := public.ims_action_counts(pg_temp.v('wh_e')::uuid);
  perform pg_temp.chk('A4 Edmonton — 다섯 = 화면 원문', pg_temp.five(p_e), pg_temp.screen(pg_temp.v('wh_e')::uuid));
  perform pg_temp.chk('A5 total = 다섯 합(All · T · E) · 값은 int',
    (select string_agg(((x->>'total')::int = coalesce((x->>'short')::int, 0) + coalesce((x->>'unpaid')::int, 0) + coalesce((x->>'pos')::int, 0) + coalesce((x->>'new_customers')::int, 0) + coalesce((x->>'pickups')::int, 0))::text
                       || '/' || jsonb_typeof(x->'total') || '/' || jsonb_typeof(x->'short') || '/' || jsonb_typeof(x->'unpaid'), ' ') from unnest(array[p, p_t, p_e]) x),
    'true/number/number/number true/number/number/number true/number/number/number');
  perform pg_temp.chk('A6 warehouse_id · warehouse 되울림 — All null/null · T id/이름 · E id/이름',
    coalesce(p->>'warehouse_id', 'null') || '/' || coalesce(p->>'warehouse', 'null') || ' | ' || (p_t->>'warehouse_id') || '/' || (p_t->>'warehouse') || ' | ' || (p_e->>'warehouse_id') || '/' || (p_e->>'warehouse'),
    'null/null | ' || pg_temp.v('wh_t') || '/Asung Trading Inc. | ' || pg_temp.v('wh_e') || '/Asung - Edmonton');
  perform pg_temp.chk('A7 at = now()(이 트랜잭션) · timestamptz 글', ((p->>'at')::timestamptz = now())::text, 'true');
  -- A8 즉시 결제조건이 하나도 없으면 unpaid 0(화면 __none__ 과 같다) — ref_payment_term 을 잠시 바꾼다(rollback)
  reset role;
  update public.ref_payment_term set net_days = 999 where net_days = 0;
  perform pg_temp.as_user(pg_temp.v('u_mgr'));
  perform pg_temp.chk('A8 IMMEDIATE 빈 집합 → unpaid 0 · 다른 넷 그대로 · 화면 원문도 0',
    pg_temp.five(public.ims_action_counts(null)) || ' | ' || pg_temp.screen(null),
    (p->>'short') || '|0|' || (p->>'pos') || '|' || (p->>'new_customers') || '|' || (p->>'pickups') || ' | ' || (p->>'short') || '|0|' || (p->>'pos') || '|' || (p->>'new_customers') || '|' || (p->>'pickups'));
  reset role;
  update public.ref_payment_term set net_days = 0 where net_days = 999;
  -- B: 문
  perform pg_temp.as_user(pg_temp.v('u_read'));
  perform pg_temp.chk('B1 sales:read 만 가진 manager → 통과(ims_can_view 는 :read 도) · 다섯 = 같은 화면 원문(창고 문 없는 넷은 같다 · pickups 는 ims_can_warehouse)', pg_temp.five(public.ims_action_counts(null)), pg_temp.screen(null));
  perform pg_temp.as_user(pg_temp.v('u_none'));
  v_s1 := pg_temp.try('select public.ims_action_counts(null)::text');
  perform pg_temp.chk('B2 sales 없는 worker → 첫 줄 문 거부(nothing was read)', v_s1, 'ERR P0001: You cannot see the Action Centre — ask an admin to add the ''sales'' permission — nothing was read');
  v_s2 := pg_temp.try('set local role anon; select public.ims_action_counts(null)::text');
  reset role;
  perform pg_temp.chk('B3 anon → 42501(역할 · execute 없음)', left(v_s2, 9), 'ERR 42501');
  -- B4 authenticated 역할로(grant 실증 · 속 invoker so_pos_open_list 가 definer 안에서 같은 값)
  perform pg_temp.as_user(pg_temp.v('u_mgr'));
  v_s3 := pg_temp.try('set local role authenticated; select pg_temp.five(public.ims_action_counts(null))');
  reset role;
  perform pg_temp.chk('B4 set role authenticated + manager claims → 같은 다섯(grant · RLS 아래 표 select true)', v_s3, pg_temp.five(p));
  perform pg_temp.as_user(pg_temp.v('u_mgr'));
  v_s1 := pg_temp.try('select public.ims_action_counts(''11111111-1111-4111-8111-111111111111'')::text');
  perform pg_temp.chk('B5 모르는 창고 → Warehouse not found', v_s1, 'ERR P0001: Warehouse not found');
  -- C: 시간
  perform public.ims_action_counts(null);
  t0 := clock_timestamp(); perform public.ims_action_counts(null); v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000, 1);
  perform pg_temp.chk('C1 한 번 호출 서버 시간 < 300 ms(2 분에 한 번 · 화면마다) — 실측 ms 는 detail', (v_ms < 300)::text || ' ' || v_ms::text, 'true ' || v_ms::text);
  -- L: 정적
  perform pg_temp.chk('L1 nowhere — WHERE 없는 update · delete 0(stable · 쓰기 없음)', (select pg_temp.nowhere(p.prosrc)::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ims_action_counts'), '0');
  perform pg_temp.chk('L2 다섯 원천을 그대로 부른다(so_stock_short_list · so_invoice_list · so_pos_open_list · customer_review_list · fc_pickup_attention_list 각 1 회 이상 · any(array( 꼴)',
    (select (prosrc ~ 'public\.so_stock_short_list\(')::text || (prosrc ~ 'public\.so_invoice_list')::text || (prosrc ~ 'public\.so_pos_open_list\(')::text || (prosrc ~ 'public\.customer_review_list')::text || (prosrc ~ 'public\.fc_pickup_attention_list\(')::text || (prosrc ~ 'any \(array\(select')::text
       from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_action_counts'), 'truetruetruetruetruetrue');
end $$;

-- ── 결과 ──
select clock_timestamp() - :'t_begin0000'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select pg_temp.as_user(:'u_mgr') as as_mgr \gset
select public.ims_action_counts(null) as info_real_all, public.ims_action_counts(:'wh_t'::uuid) - 'at' as info_real_toronto, public.ims_action_counts(:'wh_e'::uuid) - 'at' as info_real_edmonton \gx
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.ref_payment_term) = :y_pt and (select count(*) from public.ref_payment_term where net_days = 0) = :y_pt0 and (select count(*) from public.ims_staff) = :y_staff and (select count(*) from public.so_invoice) = :y_inv and (select count(*) from public.customer) = :y_cu then 'Z1 OK real rows unchanged (payment_term net 0 back)' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_action_counts') = 0 then 'Z2 OK ims_action_counts gone after rollback' else 'Z2 MISMATCH ims_action_counts still there' end as z2;
\endif
