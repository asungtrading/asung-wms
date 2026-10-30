-- supabase/tests/unconf_1_check.sql — unconf-1 Unconfirm 을 Manager 에게 · 자기 창고 오더만 (2026-10-29 · 판정 883)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5) → begin → 옛 prosrc 담기 → (-v mig 면 \i) → 가짜 재료 UNC-(실제 두 창고 · 직원 다섯 · 손님 · 확정 SO 열 + 형제 둘)
--   → U(문 · 창고 · 순서) · C(재발행 diff · 시험 갈래만) · D(nowhere 정적) · E(속성 · md5 · 무접촉) → rollback → Z1 실제 행 무변 · Z2 md5 복귀(시험 갈래만)
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261029235800_unconf_1_manager_own_warehouse.sql -f supabase/tests/unconf_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 22 · 확인(적용 뒤) 19 — C0 ~ C2(옛 = 새 대조)는 시험 갈래만 · Z1 · Z2 는 t_res 밖 한 줄씩
--   쓰기 0 — 가짜 재료는 rollback · 번호 시퀀스를 당기는 창구는 부르지 않는다(so_number 는 글자 그대로 SO-79920 ~ SO-79927)
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback 을 찍는다)
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 22
\else
\set EXPECT_OK 19
\endif
\pset pager off
select (select count(*) from public.so) as n_so0, (select count(*) from public.so_line) as n_line0, (select count(*) from public.so_reserve) as n_res0, (select count(*) from public.customer) as n_cust0,
       (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.ref_warehouse) as n_wh0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') as unc_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_confirm') as conf_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') as posr_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_service_confirm') as svc_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_cancel') as canc_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_can_warehouse') as canwh_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_require_role') as role_md5_0 \gset
\echo '── 기준: so' :n_so0 '· so_line' :n_line0 '· so_reserve' :n_res0 '· ims_staff' :n_staff0 '· so_unconfirm md5' :unc_md5_0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
create temp table t_pre as select proname, prosrc, md5(prosrc) as md5, array_length(string_to_array(prosrc, E'\n'), 1) as n_lines from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm';
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.chkb(p_name text, p_ok boolean, p_note text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, coalesce(p_ok, false), p_note, 'true');
$$;
-- 창구 호출: 성공이면 쓰기가 남고(바깥 트랜잭션 · rollback 됨) 결과 글자 · 오류면 ERR 글자(서브트랜잭션이 되돌린다)
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
create function pg_temp.unc(p_so uuid) returns text language sql as $$
  select pg_temp.run(format('select public.so_unconfirm(%L::uuid)::text', p_so));
$$;
-- 오더 한 줄 요약: status/location_name/merged 형제 수/unconfirmed_by 가 있나
create function pg_temp.st(p_so uuid) returns text language sql as $$
  select s.status || '/' || s.location_name || '/' || (select count(*) from public.so x where x.merged_into_id = s.id and x.closed_reason = 'merged')::text || '/' || (s.unconfirmed_by is not null)::text
  from public.so s where s.id = p_so;
$$;
-- ar_2b_check 꼴: 깊이 0 의 update · delete 에 WHERE 가 없는 수(주석 제거 · 괄호 속은 지움 · 글자 리터럴은 세지 않는다)
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

-- ── 재료(가짜 UNC- · replica · rollback) — 창고는 실제 둘(Edmonton · 토론토) ──
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh_e, name as wh_e_name from public.ref_warehouse where is_active and name ilike '%edmonton%' order by name limit 1 \gset
select id::text as wh_t, name as wh_t_name from public.ref_warehouse where is_active and name not ilike '%edmonton%' order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'unc-mgr-edm@test.invalid', 'UNC Manager Edmonton', 'manager', '["ims","sales"]', array[:'wh_e'::uuid]) returning auth_user_id::text as u_mgr_e \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'unc-mgr-all@test.invalid', 'UNC Manager Office', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as u_mgr_all \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'unc-sup-edm@test.invalid', 'UNC Supervisor Edmonton', 'supervisor', '["ims","sales"]', array[:'wh_e'::uuid]) returning auth_user_id::text as u_sup_e \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'unc-wrk-edm@test.invalid', 'UNC Worker Edmonton', 'worker', '["ims","sales"]', array[:'wh_e'::uuid]) returning auth_user_id::text as u_wrk_e \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'unc-mgr-ro@test.invalid', 'UNC Manager sales:read', 'manager', '["ims","sales:read"]', array[:'wh_e'::uuid]) returning auth_user_id::text as u_mgr_ro \gset
insert into public.customer (name, source, currency_id, price_tier) values ('UNC Alpha Corp', 'manual', :'cad'::uuid, 'Wholesale') returning id::text as c_a \gset
select set_config('unc.cad', :'cad', true), set_config('unc.c_a', :'c_a', true), set_config('unc.wh_e', :'wh_e', true), set_config('unc.wh_t', :'wh_t', true), set_config('unc.wh_e_name', :'wh_e_name', true), set_config('unc.wh_t_name', :'wh_t_name', true) \gset
-- 확정 SO 하나(줄 하나 · 예약 없음) — 형제는 split_from_id + stock_short · created_at = 부모 confirmed_at · 손대지 않음(updated_at = created_at · 줄도)
create function pg_temp.mk_so(p_number text, p_wh text, p_status text, p_split_from uuid) returns uuid language plpgsql as $$
declare v_so uuid; v_conf timestamptz := now() - interval '1 hour'; v_created timestamptz; v_wh uuid; v_wh_name text;
begin
  if p_wh = 'E' then v_wh := current_setting('unc.wh_e')::uuid; v_wh_name := current_setting('unc.wh_e_name'); else v_wh := current_setting('unc.wh_t')::uuid; v_wh_name := current_setting('unc.wh_t_name'); end if;
  v_created := case when p_split_from is null then now() - interval '1 day' else v_conf end;
  insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at, created_at, updated_at, split_from_id, split_reason)
  values (p_number, current_setting('unc.c_a')::uuid, 'warehouse', 'manual', p_status, current_setting('unc.cad')::uuid, v_wh, v_wh_name, v_conf, v_created, v_created, p_split_from, case when p_split_from is null then null else 'stock_short' end)
  returning id into v_so;
  insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered, created_at, updated_at) select v_so, 1, p.id, p.sku, 1, 2, v_created, v_created from public.product p where p.is_active order by p.sku limit 1;
  return v_so;
end $$;
select pg_temp.mk_so('SO-79920', 'E', 'confirmed', null)::text as e1 \gset
select pg_temp.mk_so('SO-79921', 'T', 'confirmed', null)::text as t1 \gset
select pg_temp.mk_so('SO-79922', 'E', 'confirmed', null)::text as e2 \gset
select pg_temp.mk_so('SO-79923', 'T', 'confirmed', null)::text as t2 \gset
select pg_temp.mk_so('SO-79924', 'T', 'confirmed', null)::text as t3 \gset
select pg_temp.mk_so('SO-79925', 'E', 'confirmed', null)::text as e3 \gset
select pg_temp.mk_so('SO-79926', 'E', 'confirmed', null)::text as p1 \gset
select pg_temp.mk_so('SO-79926a', 'T', 'confirmed', :'p1'::uuid)::text as p1a \gset
select pg_temp.mk_so('SO-79927', 'E', 'confirmed', null)::text as p2 \gset
select pg_temp.mk_so('SO-79927a', 'E', 'confirmed', :'p2'::uuid)::text as p2a \gset
select pg_temp.mk_so('SO-79928', 'T', 'shipped', null)::text as t4 \gset
set local session_replication_role = origin;
select pg_temp.chkb('F0 fake material: real warehouses Edmonton + Toronto · staff 5 (manager Edmonton · manager no Location · supervisor Edmonton · worker · manager sales:read) · customer · confirmed SO 10 + shipped 1 · siblings a of 79926 (Toronto) and 79927 (Edmonton) born at confirmation · untouched',
  :'wh_e' <> '' and :'wh_t' <> '' and :'wh_e' <> :'wh_t' and :'u_mgr_e' <> '' and :'u_mgr_all' <> '' and :'u_sup_e' <> '' and :'u_wrk_e' <> '' and :'u_mgr_ro' <> ''
  and (select count(*) from public.so where so_number like 'SO-7992%') = 11
  and (select bool_and(c.created_at = p.confirmed_at and c.updated_at = c.created_at and c.location_id is not null) from public.so c join public.so p on p.id = c.split_from_id where c.so_number in ('SO-79926a', 'SO-79927a'))
  and (select count(*) from public.so where so_number in ('SO-79926a', 'SO-79927a')) = 2, 'see F0');

-- ── U) 문 · 창고 · 순서 ──
select pg_temp.as_user(:'u_mgr_e');
select pg_temp.unc(:'e1'::uuid) as u1 \gset
select pg_temp.chkb('U1 manager · Location = Edmonton · Edmonton order → unconfirmed (returns status draft · merged [] · order now draft · unconfirmed_by set)',
  :'u1' like '%"status": "draft"%' and :'u1' like '%"merged": []%' and pg_temp.st(:'e1'::uuid) = 'draft/' || :'wh_e_name' || '/0/true', left(:'u1', 120) || ' | ' || pg_temp.st(:'e1'::uuid));
select pg_temp.chk('U2 same manager · Toronto order → warehouse refusal text (English · as the screen shows it)', pg_temp.unc(:'t1'::uuid),
  'ERR P0001: Order SO-79921 is in ' || :'wh_t_name' || ' — you can unconfirm only orders of your locations (ask a supervisor) — nothing was saved');
select pg_temp.chk('U2b … and nothing changed: Toronto order still confirmed · no unconfirmed_by · updated_at = before', pg_temp.st(:'t1'::uuid) || '/' || (select (updated_at = created_at)::text from public.so where id = :'t1'::uuid), 'confirmed/' || :'wh_t_name' || '/0/false/true');
select pg_temp.as_user(:'u_mgr_all');
select pg_temp.chkb('U3 manager · Location empty → Edmonton order and Toronto order both unconfirmed (empty = all · the accepted trade-off)',
  pg_temp.unc(:'e2'::uuid) like '%"status": "draft"%' and pg_temp.unc(:'t2'::uuid) like '%"status": "draft"%' and pg_temp.st(:'e2'::uuid) like 'draft/%' and pg_temp.st(:'t2'::uuid) like 'draft/%', pg_temp.st(:'e2'::uuid) || ' | ' || pg_temp.st(:'t2'::uuid));
select pg_temp.as_user(:'u_sup_e');
select pg_temp.chkb('U4 supervisor · Location = Edmonton (checked) → Toronto order unconfirmed (supervisor · admin never bounded by Location)',
  pg_temp.unc(:'t3'::uuid) like '%"status": "draft"%' and pg_temp.st(:'t3'::uuid) like 'draft/%', pg_temp.st(:'t3'::uuid));
select pg_temp.as_user(:'u_wrk_e');
select pg_temp.chk('U5 worker (sales write · Edmonton) → role refusal as before · now says manager', pg_temp.unc(:'e3'::uuid), 'ERR P0001: This needs a manager or above (you are worker) — nothing was saved');
select pg_temp.as_user(:'u_mgr_ro');
select pg_temp.chk('U6 manager with sales:read only → sales refusal first line (unchanged)', pg_temp.unc(:'e3'::uuid), 'ERR P0001: You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved');
select pg_temp.chk('U6b … Edmonton order SO-79925 untouched by U5 · U6', pg_temp.st(:'e3'::uuid), 'confirmed/' || :'wh_e_name' || '/0/false');
select pg_temp.as_user(:'u_mgr_e');
select pg_temp.unc(:'p1'::uuid) as u7 \gset
select pg_temp.chkb('U7 (이견 1) manager Edmonton · Edmonton order whose confirmation sibling sits in Toronto (parent moved after confirming · SO-25166 shape) → allowed · sibling merged back (only the original order''s warehouse is judged)',
  :'u7' like '%"status": "draft"%' and :'u7' like '%"merged": ["SO-79926a"]%' and pg_temp.st(:'p1'::uuid) = 'draft/' || :'wh_e_name' || '/1/true'
  and (select status || '/' || closed_reason || '/' || (merged_into_id = :'p1'::uuid)::text from public.so where id = :'p1a'::uuid) = 'cancelled/merged/true'
  and (select count(*) from public.so_line where so_id = :'p1'::uuid) = 2, left(:'u7', 160) || ' | ' || pg_temp.st(:'p1'::uuid));
select pg_temp.unc(:'p2'::uuid) as u8 \gset
select pg_temp.chkb('U8 manager Edmonton · Edmonton order with an Edmonton sibling → allowed · sibling merged back · lines moved (merge path byte-identical to before)',
  :'u8' like '%"merged": ["SO-79927a"]%' and pg_temp.st(:'p2'::uuid) = 'draft/' || :'wh_e_name' || '/1/true' and (select count(*) from public.so_line where so_id = :'p2'::uuid) = 2, left(:'u8', 160));
select pg_temp.chk('U9 order: manager Edmonton · Toronto order that is shipped → the warehouse refusal comes before the status refusal', pg_temp.unc(:'t4'::uuid),
  'ERR P0001: Order SO-79928 is in ' || :'wh_t_name' || ' — you can unconfirm only orders of your locations (ask a supervisor) — nothing was saved');
select pg_temp.as_user(:'u_sup_e');
select pg_temp.chk('U9b order: supervisor · same shipped Toronto order → passes the warehouse gate · status refusal as before', pg_temp.unc(:'t4'::uuid),
  'ERR P0001: Order SO-79928 is shipped — only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) — nothing was saved');
select pg_temp.as_user(:'u_mgr_e');
select pg_temp.chk('U10 unknown order id → Order not found (unchanged · before the warehouse gate)', pg_temp.unc('00000000-0000-0000-0000-000000000001'::uuid), 'ERR P0001: Order not found — nothing was saved');
select pg_temp.chk('U11 manager Edmonton · already unconfirmed Edmonton order (draft) → status refusal as before (gate passed)', pg_temp.unc(:'e1'::uuid),
  'ERR P0001: Order SO-79920 is draft — only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) — nothing was saved');

-- ── C) 재발행 diff — 옛(begin 앞 prosrc) = 새 대조 · 시험 갈래만 · 줄이 셋 늘어나므로 줄 번호가 아니라 줄 글자(다중집합)로 비교 ──
\if :{?mig}
create temp table t_diff as
  with o as (select l, count(*) as c from t_pre t, regexp_split_to_table(t.prosrc, E'\n') as l group by l),
       w as (select l, count(*) as c from pg_proc p, regexp_split_to_table(p.prosrc, E'\n') as l where p.pronamespace = 'public'::regnamespace and p.proname = 'so_unconfirm' group by l)
  select 'removed' as side, o.l, o.c - coalesce(w.c, 0) as c from o left join w on w.l = o.l where o.c > coalesce(w.c, 0)
  union all
  select 'added', w.l, w.c - coalesce(o.c, 0) from w left join o on o.l = w.l where w.c > coalesce(o.c, 0);
select pg_temp.chk('C0 begin 앞 prosrc = 마지막 정의(dsc_3b:470 · md5 · 100 줄)', (select md5 || '/' || n_lines from t_pre), 'b9b48b92b7445a84abcdb5aa1b254b28/100');
select pg_temp.chk('C1 new = old + 3 lines · removed 1 · added 4', (select array_length(string_to_array(prosrc, E'\n'), 1)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') || '/' ||
  (select coalesce(sum(c) filter (where side = 'removed'), 0)::text || '/' || coalesce(sum(c) filter (where side = 'added'), 0)::text from t_diff), '103/1/4');
select pg_temp.chk('C2 removed = the supervisor gate line · added = the manager gate line + the three warehouse-check lines · nothing else',
  (select string_agg(side || '=' || regexp_replace(btrim(l), '\s+--.*$', ''), ' || ' order by side desc, btrim(l) collate "C") from t_diff),
  'removed=perform public.so_require_role(''supervisor'', ''saved'');' ||
  ' || added=end if;' ||
  ' || added=if not public.ims_can_warehouse(v_so.location_id) then' ||
  ' || added=perform public.so_require_role(''manager'', ''saved'');' ||
  ' || added=raise exception ''Order % is in % — you can unconfirm only orders of your locations (ask a supervisor) — nothing was saved'', v_so.so_number, coalesce(v_so.location_name, ''(no location)'');');
\endif

-- ── D) REST 첫 겹 — 정적: 깊이 0 의 update · delete 에 WHERE ──
select pg_temp.chk('D0 scanner self-test: no-where update 1 · where 0 · subquery-where-only 1 · with-update no-where 1 · delete no-where 1 · then-update 1 · string update 0',
  pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
  || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text, '1011110');
select pg_temp.chk('D1 new last definition: WHERE-less update · delete = 0 for so_unconfirm', (select 'so_unconfirm ' || pg_temp.nowhere(prosrc)::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm'), 'so_unconfirm 0');

-- ── E) 속성 · md5 · 무접촉 ──
select pg_temp.chk('E1 so_unconfirm: definer · volatile · search_path · authenticated yes · anon no · exactly one · comment has 883 · the warehouse line calls ims_can_warehouse(v_so.location_id) once · the role line says manager',
  (select prosecdef::text || '/' || provolatile::text || '/' || array_to_string(proconfig, ';') || '/' || (prosrc like '%so_require_role(''manager'', ''saved'')%')::text || '/' || (length(prosrc) - length(replace(prosrc, 'ims_can_warehouse(v_so.location_id)', ''))) / length('ims_can_warehouse(v_so.location_id)')
   from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') || '/' ||
  has_function_privilege('authenticated', 'public.so_unconfirm(uuid)', 'execute')::text || '/' || has_function_privilege('anon', 'public.so_unconfirm(uuid)', 'execute')::text || '/' ||
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') || '/' || (coalesce(obj_description('public.so_unconfirm(uuid)'::regprocedure, 'pg_proc'), '') like '%판정 883%')::text,
  'true/v/search_path=public, pg_temp/true/1/true/false/1/true');
select pg_temp.chk('E2 untouched (md5 begin 앞 = 지금): so_confirm · so_pos_reopen · so_service_confirm · so_cancel · ims_can_warehouse · so_require_role',
  (select md5(prosrc) = :'conf_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_confirm')::text || '/' || (select md5(prosrc) = :'posr_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen')::text || '/' ||
  (select md5(prosrc) = :'svc_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_service_confirm')::text || '/' || (select md5(prosrc) = :'canc_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_cancel')::text || '/' ||
  (select md5(prosrc) = :'canwh_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_can_warehouse')::text || '/' || (select md5(prosrc) = :'role_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_require_role')::text, 'true/true/true/true/true/true');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
select case when (select count(*) from public.so) = :n_so0 and (select count(*) from public.so_line) = :n_line0 and (select count(*) from public.so_reserve) = :n_res0 and (select count(*) from public.customer) = :n_cust0
            and (select count(*) from public.ims_staff) = :n_staff0 and (select count(*) from public.ref_warehouse) = :n_wh0
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
\if :{?mig}
select case when (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') = :'unc_md5_0'
       then 'Z2 OK so_unconfirm back to before (md5)' else 'Z2 MISMATCH so_unconfirm not restored' end as z2;
\endif
