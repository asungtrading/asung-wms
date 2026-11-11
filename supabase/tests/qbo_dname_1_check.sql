-- supabase/tests/qbo_dname_1_check.sql — qbo-dname-1 검증 (2026-11-10 토론토 · 판정 1153 + 보충 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] 기준(begin 앞) → begin(lock_timeout 3s) → 가짜 재료(DO 하나 · 표에 직접 — 창구로 문서를 발행하지 않는다) → 옛 몸 출력 담기(실제 손님 · 읽기만) → (-v mig 면 \i) → 시나리오(DO 하나) → 구조 · 정적 검사 → 집계 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111013522_qbo_dname_1_customer_display_name.sql -f supabase/tests/qbo_dname_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(갈래마다 같다)
--   마른 실행(적용 전 · -v mig 없이): 옛 몸 · 옛 글이라 여러 줄이 FAIL 로 잡히고 exit 3(죽지 않는다 — 모든 호출이 try 로 싸여 있다)
--   ⚠️ 가짜 재료만: 직원 f1d0a000-…-0a · 손님 「ZZDN …」(id f1d0a000-… 몸 시험 · f1d0a0ff-… 자동 짝 시험) · 거울 qbo_id 「zzdn-…」 · 일감(kind customer · vendor · ims_id = 가짜 uuid) — 실제 행은 읽기만
--   ⚠️ QuickBooks 호출 0 — 몸 함수 · 일감 상태 · 자동 짝(가짜 넷만 걸리게 p_after · p_limit 로 좁힘)만 본다 · qbo_job_claim 은 부르지 않는다(실제 일감을 잡는다)
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 29
\else
\set EXPECT_OK 29
\endif
\set NEW_BODY_MD5 a4a1d9d5422c43d8af2508fdd116c331
\set NEW_FAIL_MD5 8f8bd3c49eff82a18ecff38affc3e922
\set NEW_MATCH_MD5 ceab383236e39f4685cb427d77cd9064
create temp table t_pre as select p.proname, md5(p.prosrc) as md5 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%';
create temp table t_ids (k text primary key, v text);
insert into t_ids values ('realm', (select realm_id from public.qbo_connection where singleton)), ('new_body_md5', :'NEW_BODY_MD5'), ('new_fail_md5', :'NEW_FAIL_MD5'), ('new_match_md5', :'NEW_MATCH_MD5');
select (select count(*) from t_pre) as n_fn, (select count(*) from public.ims_staff) as n_staff0, (select count(*) from public.qbo_job) as n_job0, (select count(*) from public.customer) as n_cust0,
       (select count(*) from public.qbo_entity) as n_ent0, (select count(*) from public.qbo_link) as n_link0,
       (select string_agg(md5, ',' order by proname) from t_pre where proname in ('qbo_customer_body', 'qbo_job_fail', 'qbo_match_auto')) as pre_three \gset
\echo '── 기준: qbo_ 함수' :n_fn '· 손님' :n_cust0 '· 거울' :n_ent0 '· 짝' :n_link0 '· 일감' :n_job0 '· 셋의 md5(body,fail,match)' :pre_three
create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns void language sql as $$ insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want); $$;
create function pg_temp.id(p_k text) returns text language sql as $$ select v from t_ids where k = p_k $$;
create function pg_temp.put(p_k text, p_v text) returns void language sql as $$ insert into t_ids values (p_k, p_v) on conflict (k) do update set v = excluded.v $$;
create function pg_temp.as_conn(p_role text, p_claims jsonb, p_sql text) returns text language plpgsql as $$
declare v text; v_old text := current_setting('request.jwt.claims', true);
begin
  perform set_config('request.jwt.claims', coalesce(p_claims::text, ''), true);
  execute format('set local role %I', p_role);
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', coalesce(v_old, ''), true);
  return coalesce(v, '(null)');
end $$;
-- bk = 쓰기 열쇠(qbo) 가짜 직원 · svc = service_role(send 일꾼) · try = postgres 로(몸 함수는 grant 0)
create function pg_temp.bk(p_sql text) returns text language sql as $$ select pg_temp.as_conn('authenticated', '{"role":"authenticated","sub":"f1d0a000-0000-4000-8000-000000000001"}'::jsonb, p_sql) $$;
create function pg_temp.svc(p_sql text) returns text language sql as $$ select pg_temp.as_conn('service_role', '{"role":"service_role"}'::jsonb, p_sql) $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  begin execute p_sql into v; exception when others then v := 'ERR ' || sqlstate || ': ' || sqlerrm; end;
  return coalesce(v, '(null)');
end $$;
-- 몸: 'names' = DisplayName|CompanyName|돌려준 display_name 열쇠 · 'warn' = 경고 글 · 거부면 'ERR …' 그대로
create function pg_temp.b(p_k text, p_what text default 'names') returns text language plpgsql as $$
declare v text := pg_temp.try(format('select public.qbo_customer_body(%L)::text', pg_temp.id(p_k))); v_j jsonb;
begin
  if v like 'ERR %' then return v; end if;
  v_j := v::jsonb;
  return case p_what when 'names' then coalesce(v_j->'body'->>'DisplayName', '(null)') || '|' || coalesce(v_j->'body'->>'CompanyName', '(null)') || '|' || coalesce(v_j->>'display_name', '(null)')
                     when 'warn' then coalesce((select string_agg(x, ' · ') from jsonb_array_elements_text(v_j->'warnings') x where x like '%cut to 100%'), '(none)') else '?' end;
end $$;
-- 일감 거부(service_role) 뒤 last_error
create function pg_temp.fail(p_job_k text, p_error text) returns text language plpgsql as $$
declare v text := pg_temp.svc(format('select public.qbo_job_fail(%L, %L, null)::text', pg_temp.id(p_job_k), p_error));
begin
  if v like 'ERR %' then return v; end if;
  return (select j.state || ' ' || j.last_error from public.qbo_job j where j.id = pg_temp.id(p_job_k)::uuid);
end $$;
create function pg_temp.j(p_v text, p_key text) returns text language sql as $$ select case when p_v like 'ERR %' or p_v = '(null)' then p_v else coalesce(p_v::jsonb->>p_key, '(null)') end $$;
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g'); exit when v_chunk = v_prev; end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;

begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
-- ── 가짜 재료: 직원 W(qbo) · 손님 c1 ~ c10(몸) · m1 ~ m4(자동 짝) · 거울 여섯 · 일감 여섯
do $$
declare v_realm text := pg_temp.id('realm'); v_id uuid; r record;
begin
  insert into public.ims_staff (id, auth_user_id, email, name, role, perms) values ('f1d0a000-0000-4000-8000-00000000000a', 'f1d0a000-0000-4000-8000-000000000001', 'qbo-dname-1-w@asung.invalid', 'ZZDN Writer', 'manager', '["qbo"]');
  for r in select * from (values
      ('c1',  'f1d0a000-0000-4000-8000-000000000011', 'ZZDN Plain One',   null),
      ('c2',  'f1d0a000-0000-4000-8000-000000000012', 'ZZDN Legal Two',   'ZZDN Trade Two'),
      ('c3',  'f1d0a000-0000-4000-8000-000000000013', 'ZZDN Same Three',  null),
      ('c5',  'f1d0a000-0000-4000-8000-000000000015', 'ZZDN Legal Five',  '  ZZDN Taken Five '),
      ('c6',  'f1d0a000-0000-4000-8000-000000000016', 'ZZDN Blank Six',   '   '),
      ('c7',  'f1d0a000-0000-4000-8000-000000000017', 'ZZDN Long Seven',  'ZZDN ' || repeat('x', 115)),
      ('c8',  'f1d0a000-0000-4000-8000-000000000018', 'ZZDN Colon: Eight', null),
      ('c9',  'f1d0a000-0000-4000-8000-000000000019', 'ZZDN Nine',        E'ZZDN Tab\tNine'),
      ('c10', 'f1d0a000-0000-4000-8000-00000000001a', 'ZZDN ' || repeat('y', 115), null),
      ('m1',  'f1d0a0ff-0000-4000-8000-000000000001', 'ZZDN Match One',   null),
      ('m2',  'f1d0a0ff-0000-4000-8000-000000000002', 'ZZDN Match Two',   'ZZDN Match Two (north)'),
      ('m3',  'f1d0a0ff-0000-4000-8000-000000000003', 'ZZDN Legal Three', 'ZZDN Trade Three'),
      ('m4',  'f1d0a0ff-0000-4000-8000-000000000004', 'ZZDN Match Four',  '  ')) x(k, id, name, dn) loop
    insert into public.customer (id, name, display_name, source, is_active) values (r.id::uuid, r.name, r.dn, 'manual', true);
    perform pg_temp.put(r.k, r.id);
  end loop;
  insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, active) values
    (v_realm, 'Customer', 'zzdn-3',  'ZZDN Same Three', true),
    (v_realm, 'Vendor',   'zzdn-5',  'zzdn taken five', true),
    (v_realm, 'Customer', 'zzdn-m1', 'ZZDN Match One', true),
    (v_realm, 'Customer', 'zzdn-m2', 'ZZDN Match Two', true),
    (v_realm, 'Customer', 'zzdn-m3', 'ZZDN Trade Three', true),
    (v_realm, 'Customer', 'zzdn-m4', 'ZZDN Match Four', true);
  -- 일감: jc3 = c3 의 failed 손님 일감(D3 · D4) · jf1 ~ jf6 = sending(qbo_job_fail 시험 · jf4 는 vendor)
  insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, 'customer', 'customer', pg_temp.id('c3'), 'failed', 'zz dname test: old failure', 'f1d0a000-0000-4000-8000-00000000000a') returning id into v_id;
  perform pg_temp.put('jc3', v_id::text), pg_temp.put('jc3_req', (select j.request_id::text from public.qbo_job j where j.id = v_id));
  for r in select * from (values ('jf1', 'customer', 'customer', 'c1'), ('jf2', 'customer', 'customer', 'c2'), ('jf3', 'customer', 'customer', 'c6'), ('jf4', 'vendor', 'supplier', null), ('jf5', 'customer', 'customer', 'c7'), ('jf6', 'customer', 'customer', 'c5')) x(k, kind, ims_kind, ck) loop
    insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, claimed_at, attempts, by_staff) values (v_realm, r.kind, r.ims_kind, coalesce(pg_temp.id(r.ck), gen_random_uuid()::text), 'sending', now(), 1, 'f1d0a000-0000-4000-8000-00000000000a') returning id into v_id;
    perform pg_temp.put(r.k, v_id::text);
  end loop;
end $$;
-- 옛 몸 출력(시험 갈래 = 옛 판 · 확인 갈래 = 새 판) — Display name 이 빈 실제 활성 손님 전부 · 읽기만
create temp table t_old as select c.id, pg_temp.try(format('select public.qbo_customer_body(%L)::text', c.id)) as r from public.customer c where c.is_active and nullif(btrim(coalesce(c.display_name, '')), '') is null and c.name not like 'ZZDN %';
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

-- ── 시나리오(DO 하나 · 순서대로)
do $$
declare v text; v2 text; v_e text := 'HTTP 400 ValidationFault code 6240: Duplicate Name Exists Error — The name supplied already exists. : null';
  v_a text := ' — if it is the same customer, link them under Settings → QuickBooks matching; if it is a different person, give IMS customer "%s" a Display name in Customers, then Retry — nothing was sent';
begin
  -- D 몸
  perform pg_temp.chk('D1 Display name 빈 손님 → DisplayName = name · CompanyName = name(옛 판과 같음)', pg_temp.b('c1'), 'ZZDN Plain One|ZZDN Plain One|ZZDN Plain One');
  perform pg_temp.chk('D2 Display name 채운 손님 → DisplayName = Display name · CompanyName = name 그대로(보충 2) · 돌려준 이름 = 보낸 이름', pg_temp.b('c2'), 'ZZDN Trade Two|ZZDN Legal Two|ZZDN Trade Two');
  v := 'ERR P0001: QuickBooks already has a customer or supplier named "ZZDN Same Three" (Customer #zzdn-3 ZZDN Same Three)' || format(v_a, 'ZZDN Same Three');
  perform pg_temp.chk('D3 거울에 같은 name · Display name 비었음 → 거부 · 새 글(같은 손님이면 짝 · 다른 사람이면 Display name → Retry)', pg_temp.b('c3'), v);
  perform pg_temp.chk('D3b 그 손님의 failed 일감 미리 보기(열쇠 직원) → error 에 같은 글 · 몸 없음', pg_temp.j(pg_temp.bk(format('select public.qbo_job_preview(%L)::text', pg_temp.id('jc3'))), 'error') , substr(v, 12));
  -- D4 Display name 을 넣고 Retry
  update public.customer c set display_name = 'ZZDN Same Three (north)' where c.id = pg_temp.id('c3')::uuid;
  v := pg_temp.bk(format('select public.qbo_job_retry(%L, %L)::text', pg_temp.id('jc3'), 'zz dname test: display name given'));
  perform pg_temp.chk('D4a Display name 을 넣고 Retry → 일감 queued · request_id 새로', pg_temp.j(v, 'state') || ' ' || (select (j.state = 'queued' and j.request_id::text <> pg_temp.id('jc3_req'))::text from public.qbo_job j where j.id = pg_temp.id('jc3')::uuid), 'queued true');
  v := pg_temp.bk(format('select public.qbo_job_preview(%L)::text', pg_temp.id('jc3')));
  perform pg_temp.chk('D4b Retry 뒤 몸은 새로 만들어진다 — DisplayName = 새 이름 · 충돌 없음 · 미리 보기 name = 새 이름 · error 없음', pg_temp.b('c3') || ' | ' || pg_temp.j(v, 'name') || ' ' || pg_temp.j(v, 'error'),
    'ZZDN Same Three (north)|ZZDN Same Three|ZZDN Same Three (north) | ZZDN Same Three (north) (null)');
  perform pg_temp.chk('D5 Display name 도 거울(Vendor · 대소문자 다름)에 있음 → 거부 · 「Display name 도 이미 있다」 글', pg_temp.b('c5'),
    'ERR P0001: The Display name "ZZDN Taken Five" is also taken in QuickBooks (Vendor #zzdn-5 zzdn taken five) — change the Display name of IMS customer "ZZDN Legal Five" in Customers, then Retry — nothing was sent');
  perform pg_temp.chk('D6 Display name 이 공백만 → name 을 쓴다', pg_temp.b('c6'), 'ZZDN Blank Six|ZZDN Blank Six|ZZDN Blank Six');
  perform pg_temp.chk('D7 100 자 넘는 Display name → 100 자로 잘림 · CompanyName = name · 경고 「Display name cut」', pg_temp.b('c7') || ' | ' || pg_temp.b('c7', 'warn'),
    left('ZZDN ' || repeat('x', 115), 100) || '|ZZDN Long Seven|' || left('ZZDN ' || repeat('x', 115), 100) || ' | Display name cut to 100 characters: ' || left('ZZDN ' || repeat('x', 115), 100));
  perform pg_temp.chk('D7b 100 자 넘는 name · Display name 없음 → 옛 판 그대로(둘 다 100 자 · 경고 「name cut」)', pg_temp.b('c10') || ' | ' || pg_temp.b('c10', 'warn'),
    left('ZZDN ' || repeat('y', 115), 100) || '|' || left('ZZDN ' || repeat('y', 115), 100) || '|' || left('ZZDN ' || repeat('y', 115), 100) || ' | name cut to 100 characters: ' || left('ZZDN ' || repeat('y', 115), 100));
  -- C 콜론 · 제어 문자(보충 6)
  perform pg_temp.chk('C1 name 에 콜론 · Display name 없음 → 거부(Display name 을 넣고 Retry)', pg_temp.b('c8'),
    'ERR P0001: The name of IMS customer "ZZDN Colon: Eight" has a character QuickBooks does not accept in a name (a colon, a tab or a line break) — give this customer a Display name without it in Customers, then Retry — nothing was sent');
  v := pg_temp.b('c9');
  update public.customer c set display_name = E'ZZDN Line\nNine' where c.id = pg_temp.id('c9')::uuid;
  perform pg_temp.chk('C2 Display name 에 탭 · 줄바꿈 → 둘 다 거부(Display name 을 고치고 Retry)', (v = E'ERR P0001: The Display name "ZZDN Tab\tNine" has a character QuickBooks does not accept in a name (a colon, a tab or a line break) — change the Display name of IMS customer "ZZDN Nine" in Customers, then Retry — nothing was sent')::text || ' ' ||
    (pg_temp.b('c9') like E'ERR P0001: The Display name "ZZDN Line\nNine" has a character QuickBooks does not accept in a name (a colon, a tab or a line break) — change the Display name of IMS customer "ZZDN Nine" in Customers, then Retry — nothing was sent')::text, 'true true');
  update public.customer c set display_name = 'ZZDN Fine Nine' where c.id = pg_temp.id('c9')::uuid;
  perform pg_temp.chk('C3 Display name 을 고치면 지나간다', pg_temp.b('c9'), 'ZZDN Fine Nine|ZZDN Nine|ZZDN Fine Nine');
  update public.customer c set display_name = 'ZZDN Eight' where c.id = pg_temp.id('c8')::uuid;
  perform pg_temp.chk('C4 콜론 든 name 에 Display name 을 넣으면 지나간다 — DisplayName = Display name · CompanyName 은 name 그대로', pg_temp.b('c8'), 'ZZDN Eight|ZZDN Colon: Eight|ZZDN Eight');
  -- F qbo_job_fail(보충 3)
  perform pg_temp.chk('F1 손님 일감 6240 · Display name 없음 → 할 일이 앞 · 뒤에 Intuit 글', pg_temp.fail('jf1', v_e),
    'failed QuickBooks already has a customer, supplier or employee named "ZZDN Plain One"' || format(v_a, 'ZZDN Plain One') || ' · QuickBooks answered: ' || v_e);
  perform pg_temp.chk('F2 손님 일감 6240 · Display name 있음 → 「Display name 도 이미 있다 — 고치고 Retry」', pg_temp.fail('jf2', v_e),
    'failed The Display name "ZZDN Trade Two" is also taken in QuickBooks — change the Display name of IMS customer "ZZDN Legal Two" in Customers, then Retry — nothing was sent · QuickBooks answered: ' || v_e);
  perform pg_temp.chk('F3 손님 일감의 다른 오류(2020) → 글 그대로', pg_temp.fail('jf3', 'HTTP 400 ValidationFault code 2020: Required param missing — CurrencyRef'), 'failed HTTP 400 ValidationFault code 2020: Required param missing — CurrencyRef');
  perform pg_temp.chk('F4 Vendor 일감 6240 → 글 그대로(범위 밖)', pg_temp.fail('jf4', v_e), 'failed ' || v_e);
  perform pg_temp.chk('F5 빈 글 → send failed(옛 판 그대로)', pg_temp.fail('jf5', '   '), 'failed send failed');
  v := pg_temp.fail('jf6', v_e || ' ' || repeat('z', 2500));
  perform pg_temp.chk('F6 긴 글(2,500 자 넘음) + 6240 → 2,000 자 · 할 일이 앞에 남는다', length(substr(v, 8))::text || ' ' || (v like 'failed The Display name "ZZDN Taken Five" is also taken in QuickBooks — change the Display name of IMS customer "ZZDN Legal Five" in Customers, then Retry — nothing was sent · QuickBooks answered: HTTP 400 %')::text, '2000 true');
  -- M 자동 짝(보충 1) — 가짜 넷만: p_after = f1d0a0ff-…-000 · p_limit 4
  v := pg_temp.bk($q$ select public.qbo_match_auto('customer', 'f1d0a0ff-0000-4000-8000-000000000000', 4)::text $q$);
  perform pg_temp.chk('M1 자동 짝 묶음(가짜 넷): considered 4 · linked 3 · absent 1 · ambiguous 0', pg_temp.j(v, 'considered') || ' ' || pg_temp.j(v, 'linked') || ' ' || pg_temp.j(v, 'absent') || ' ' || pg_temp.j(v, 'ambiguous'), '4 3 1 0');
  perform pg_temp.chk('M2 짝: m1(Display name 없음) → 같은 name · m3 → Display name 과 같은 QBO 손님 · m4(공백뿐) → name · m2 는 없음', (select coalesce(string_agg(t.k || '→' || l.qbo_id || ':' || l.matched_by, ',' order by t.k), '(none)') from t_ids t join public.qbo_link l on l.realm_id = pg_temp.id('realm') and l.ims_kind = 'customer' and l.ims_id = t.v where t.k like 'm_'),
    'm1→zzdn-m1:auto_name,m3→zzdn-m3:auto_name,m4→zzdn-m4:auto_name');
  perform pg_temp.chk('M3 「다른 사람」 이라 Display name 을 준 m2 는 같은 name 의 QBO 손님(zzdn-m2)에 이어지지 않는다 — absent 보기에 그 이름', case when v like 'ERR %' then v else (v::jsonb->'examples'->'absent')::text end || ' ' || (select count(*) from public.qbo_link l where l.qbo_id = 'zzdn-m2')::text, '["ZZDN Match Two"] 0');
  v := pg_temp.bk($q$ select public.qbo_match_auto('supplier', 'ffffffff-ffff-ffff-ffff-ffffffffffff', 1)::text $q$);
  perform pg_temp.chk('M4 다른 kind(supplier · 빈 묶음)는 그대로 돈다 — considered 0', pg_temp.j(v, 'considered') || ' ' || pg_temp.j(v, 'linked'), '0 0');
end $$;
-- G2 실제 손님(Display name 빈 활성 손님 전부 · 읽기만) — 옛 출력 ↔ 새 출력
create temp table t_new as select o.id, o.r as r_old, pg_temp.try(format('select public.qbo_customer_body(%L)::text', o.id)) as r_new from t_old o;
select
  pg_temp.chk('G2a 실제 손님: 옛 판에서 몸이 만들어지던 손님은 새 판에서도 바이트 그대로(다른 것 0) · 거부 수 같음', (select count(*) filter (where r_old not like 'ERR %' and r_new is distinct from r_old)::text || ' ' || (count(*) filter (where r_old like 'ERR %') = count(*) filter (where r_new like 'ERR %'))::text from t_new), '0 true'),
  pg_temp.chk('G2b 실제 손님: 이름 충돌 거부는 모두 새 글(할 일) — 옛 글 0 · 새 글이 아닌 충돌 거부 0', (select count(*) filter (where r_new like '%link the IMS customer to it under Settings%')::text || ' ' || count(*) filter (where r_new like 'ERR %QuickBooks already has a customer or supplier named%' and r_new not like '%— if it is the same customer, link them under Settings → QuickBooks matching; if it is a different person, give IMS customer "%" a Display name in Customers, then Retry — nothing was sent')::text from t_new), '0 0'),
  -- 구조 · 정적
  pg_temp.chk('S1 셋의 md5 · ACL · volatile · definer · 설정 · 같은 이름 하나', (select string_agg(p.proname || '=' || md5(p.prosrc) || ' ' || p.proacl::text || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || p.proconfig::text || ' ' || (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = p.proname)::text, ' | ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_customer_body', 'qbo_job_fail', 'qbo_match_auto')),
    'qbo_customer_body=' || pg_temp.id('new_body_md5') || ' {postgres=X/postgres} s true {"search_path=public, pg_temp"} 1 | qbo_job_fail=' || pg_temp.id('new_fail_md5') || ' {postgres=X/postgres,service_role=X/postgres} v true {"search_path=public, pg_temp"} 1 | qbo_match_auto=' || pg_temp.id('new_match_md5') || ' {postgres=X/postgres,authenticated=X/postgres} v true {"search_path=public, pg_temp",client_min_messages=warning} 1'),
  pg_temp.chk('R1 REST 겹 ① — 재발행 셋의 깊이 0 WHERE 없는 update · delete = 0', (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc)::text, ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_customer_body', 'qbo_job_fail', 'qbo_match_auto')), 'qbo_customer_body=0,qbo_job_fail=0,qbo_match_auto=0');
\if :{?mig}
select pg_temp.chk('G1(시험 갈래) begin 앞과 md5 가 다른 qbo_ 함수 = 셋뿐(옛 eab0f5fa… · fdd230fa… · 616dae93…) · 새 qbo_ 함수 없음',
  (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5) || ' ' || :'pre_three' || ' ' ||
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%' and p.proname not in (select proname from t_pre)),
  'qbo_customer_body,qbo_job_fail,qbo_match_auto eab0f5fa82077b0457330671ad05c750,fdd230fa5b4de73c7345b32836ef8439,616dae936f4aaa9caa61a64e85d72845 (none)');
\else
select pg_temp.chk('G1(확인 갈래) begin 앞과 md5 가 다른 qbo_ 함수 없음 · 새 함수 없음(이미 적용)',
  (select coalesce(string_agg(t.proname, ',' order by t.proname), '(none)') from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) <> t.md5) || ' ' ||
  (select coalesce(string_agg(p.proname, ',' order by p.proname), '(none)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%' and p.proname not in (select proname from t_pre)), '(none) (none)');
\endif

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(가짜 행은 rollback) ──'
select n, case when ok then 'OK  ' else 'FAIL' end as r, label, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' · want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, (count(*) filter (where not ok) > 0 or count(*) filter (where ok) <> :EXPECT_OK) as bad from t_res \gset
\echo 'OK' :ok '· FAIL' :fail '· total' :total '· expect_ok' :EXPECT_OK
select (select count(*) from t_new) as real_customers_compared, (select count(*) filter (where r_new not like 'ERR %') from t_new) as real_bodies_built, (select count(*) filter (where r_new like 'ERR %') from t_new) as real_refused,
       round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — t 여야 한다'
select (select count(*) from public.ims_staff) = :n_staff0 and (select count(*) from public.qbo_job) = :n_job0 and (select count(*) from public.customer) = :n_cust0 and (select count(*) from public.qbo_entity) = :n_ent0 and (select count(*) from public.qbo_link) = :n_link0
   and (select string_agg(md5(p.prosrc), ',' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_customer_body', 'qbo_job_fail', 'qbo_match_auto')) = :'pre_three'
   and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo\_%') = :n_fn as rolled_back_clean;
\if :bad
do $$ begin raise exception 'qbo_dname_1_check: FAIL or OK count differs from EXPECT_OK — see the result table above'; end $$;
\endif
