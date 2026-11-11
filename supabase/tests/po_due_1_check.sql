-- po-due-1 확인 — po_invoice_detail 머리의 due_date_manual (deferred 555 · 판정 1144)
--   쓰는 법(시험 적용 · 끝은 늘 rollback):
--     psql "$(cat ~/.asung-testdb-url)" -X -v mig=supabase/migrations/20261111041118_po_due_1_invoice_detail_due_date_manual.sql -f supabase/tests/po_due_1_check.sql
--   적용 뒤 확인(mig 없이): 옛 판이 없으니 P4 · P5 는 「옛 = 새 − 키」 가 아니라 「새에 키가 있다」 만 본다(old_missing 로 표시)
--   가짜 인보이스는 표에 직접(발행 창구 금지 · 교훈 142) · session_replication_role = replica(트리거 · FK 끔 — due_date_manual 을 손으로 놓는다)
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 15
begin;
set local statement_timeout = '120s';
set local lock_timeout = '5s';

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create temp table t_snap (phase text, who text, k text, v jsonb, primary key (phase, who, k));
create temp table t_doc (k text primary key, id uuid);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is distinct from p_want then ' — got ' || coalesce(p_got, '(null)') || ' · want ' || coalesce(p_want, '(null)') else '' end;
end $$;
-- 그 사람(역할 + JWT sub)으로 상세를 읽는다 — 오류는 글로(권한 거부도 값이다)
create function pg_temp.detail_as(p_role text, p_uid uuid, p_id uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', case when p_uid is null then '' else json_build_object('sub', p_uid, 'role', p_role)::text end, true);
  if p_role <> 'postgres' then execute format('set local role %I', p_role); end if;
  begin
    select public.po_invoice_detail(p_id) into v;
  exception when others then v := jsonb_build_object('ERR', sqlstate);
  end;
  reset role;
  perform set_config('request.jwt.claims', '', true);
  return v;
end $$;
create function pg_temp.snap(p_phase text) returns int language sql as $$
  with w(who, role, uid) as (
    values ('postgres', 'postgres', null::uuid),
           ('purchasing', 'authenticated', (select auth_user_id from public.ims_staff where is_active and perms ? 'purchasing' and auth_user_id is not null order by created_at limit 1)),
           ('no_ims', 'authenticated', (select auth_user_id from public.ims_staff where is_active and not perms ? 'ims' and not perms ? 'purchasing' and auth_user_id is not null order by created_at limit 1)),
           ('anon', 'anon', null::uuid)),
  ins as (insert into t_snap select p_phase, w.who, d.k, pg_temp.detail_as(w.role, w.uid, d.id) from w cross join t_doc d returning 1)
  select count(*)::int from ins;
$$;

-- ── 가짜 넷(draft false · draft true · 크레딧 · 취소) — 실물 2223170 을 본떠 표에 직접 ──
set local session_replication_role = replica;
insert into public.po_invoice
select (jsonb_populate_record(i, f.patch || jsonb_build_object('id', gen_random_uuid(), 'confirmed_at', null, 'confirmed_by', null))).*
from public.po_invoice i,
     lateral (values (jsonb_build_object('invoice_number', 'ZZ-PODUE-F', 'status', 'draft', 'due_date_manual', false)),
             (jsonb_build_object('invoice_number', 'ZZ-PODUE-T', 'status', 'draft', 'due_date_manual', true)),
             (jsonb_build_object('invoice_number', 'ZZ-PODUE-C', 'status', 'draft', 'doc_kind', 'credit', 'credit_for_invoice_id', i.id, 'due_date', null,
                                 'early_discount_pct', null, 'early_discount_amount', null, 'early_discount_basis', null, 'early_discount_until', null)),
             (jsonb_build_object('invoice_number', 'ZZ-PODUE-X', 'status', 'cancelled', 'cancelled_at', now(), 'due_date_manual', true))) f(patch)
where i.invoice_number = '2223170';
set local session_replication_role = origin;
insert into t_doc select case invoice_number when 'ZZ-PODUE-F' then 'fake_false' when 'ZZ-PODUE-T' then 'fake_true' when 'ZZ-PODUE-C' then 'fake_credit' when 'ZZ-PODUE-X' then 'fake_cancelled'
                         else 'real_' || invoice_number end, id
from public.po_invoice;                                                                            -- 실물 전부(12 장) + 가짜 넷

select pg_temp.snap('old') as old_snaps, (select md5(prosrc) from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure) as md5_before \gset
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif
select pg_temp.snap('new') as new_snaps, (select md5(prosrc) from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure) as md5_after \gset
\echo '── 문서' :old_snaps '→' :new_snaps '· md5' :md5_before '→' :md5_after

select pg_temp.chk(x.label, x.got, x.want) from (values
  ('P1a 실물 2223170: header.due_date_manual = 칸 값',
     (select v #>> '{header,due_date_manual}' from t_snap where phase = 'new' and who = 'postgres' and k = 'real_2223170'),
     (select due_date_manual::text from public.po_invoice where invoice_number = '2223170')),
  ('P1b 실물 전부: header.due_date_manual = 칸 값(어긋난 장 0) · 키가 jsonb boolean',
     (select count(*) filter (where (s.v #> '{header,due_date_manual}') is distinct from to_jsonb(i.due_date_manual))::text || ' / ' || count(*) filter (where i.due_date_manual)::text || ' true'
        from t_snap s join t_doc d on d.k = s.k join public.po_invoice i on i.id = d.id where s.phase = 'new' and s.who = 'postgres' and s.k like 'real_%'),
     '0 / ' || (select count(*) filter (where due_date_manual)::text from public.po_invoice where invoice_number not like 'ZZ-PODUE-%') || ' true'),
  ('P2a 가짜 draft · due_date_manual false → false', (select v #>> '{header,due_date_manual}' from t_snap where phase = 'new' and who = 'postgres' and k = 'fake_false'), 'false'),
  ('P2b 가짜 draft · due_date_manual true → true',   (select v #>> '{header,due_date_manual}' from t_snap where phase = 'new' and who = 'postgres' and k = 'fake_true'), 'true'),
  ('P3  크레딧: 키가 있다 · 값 = 칸 값(false) · doc_kind credit',
     (select (v -> 'header' ? 'due_date_manual')::text || ' ' || (v #>> '{header,due_date_manual}') || ' ' || (v #>> '{header,doc_kind}') from t_snap where phase = 'new' and who = 'postgres' and k = 'fake_credit'), 'true false credit'),
  ('P3b 취소된 장: 키가 있다 · 값 = 칸 값(true)',
     (select (v #>> '{header,due_date_manual}') || ' ' || (v #>> '{header,status}') from t_snap where phase = 'new' and who = 'postgres' and k = 'fake_cancelled'), 'true cancelled'),
  ('P4a 옛 판 = 새 판 − header.due_date_manual (postgres · 실물 전부 + 가짜 넷 · 다른 장 0)',
     (select count(*) filter (where o.v is distinct from (n.v #- '{header,due_date_manual}'))::text || ' of ' || count(*)::text
        from t_snap n join t_snap o on o.phase = 'old' and o.who = n.who and o.k = n.k where n.phase = 'new' and n.who = 'postgres'),
     '0 of ' || (select count(*)::text from t_doc)),
  ('P4b 옛 판에는 키가 없었다(전 장) · 새 판 머리 키 수 = 옛 + 1',
     (select count(*) filter (where o.v -> 'header' ? 'due_date_manual')::text || ' / '
             || count(*) filter (where (select count(*) from jsonb_object_keys(n.v -> 'header')) <> (select count(*) from jsonb_object_keys(o.v -> 'header')) + 1)::text
        from t_snap n join t_snap o on o.phase = 'old' and o.who = n.who and o.k = n.k where n.phase = 'new' and n.who = 'postgres'), '0 / 0'),
  ('P4c 머리 밖(money · lines · shares · credits · warnings …) 최상위 키 목록 같음',
     (select count(*) filter (where (select array_agg(x order by x) from jsonb_object_keys(n.v) x) is distinct from (select array_agg(x order by x) from jsonb_object_keys(o.v) x))::text
        from t_snap n join t_snap o on o.phase = 'old' and o.who = n.who and o.k = n.k where n.phase = 'new' and n.who = 'postgres'), '0'),
  ('P5a 권한 purchasing(authenticated): 옛 = 새 − 키 · 오류 0 · 키 있음',
     (select count(*) filter (where o.v is distinct from (n.v #- '{header,due_date_manual}'))::text || ' / ' || count(*) filter (where n.v ? 'ERR')::text || ' / ' || count(*) filter (where n.v -> 'header' ? 'due_date_manual')::text
        from t_snap n join t_snap o on o.phase = 'old' and o.who = n.who and o.k = n.k where n.phase = 'new' and n.who = 'purchasing'),
     '0 / 0 / ' || (select count(*)::text from t_doc)),
  ('P5b 권한 ims 없는 직원(authenticated): 옛과 같은 문(옛 = 새 − 키 · 오류 꼴도 같음)',
     (select count(*) filter (where o.v is distinct from (n.v #- '{header,due_date_manual}'))::text || ' of ' || count(*)::text
        from t_snap n join t_snap o on o.phase = 'old' and o.who = n.who and o.k = n.k where n.phase = 'new' and n.who = 'no_ims'),
     '0 of ' || (select count(*)::text from t_doc)),
  ('P5c anon: 옛과 같다 — 실행권 없음(42501) 전 장',
     (select count(*) filter (where n.v = o.v and n.v = '{"ERR": "42501"}')::text || ' of ' || count(*)::text
        from t_snap n join t_snap o on o.phase = 'old' and o.who = n.who and o.k = n.k where n.phase = 'new' and n.who = 'anon'),
     (select count(*)::text || ' of ' || count(*)::text from t_doc)),
  ('P5d ACL · invoker · stable · search_path · 인자 그대로 · 오버로드 1',
     (select proacl::text || ' ' || prosecdef::text || ' ' || provolatile::text || ' ' || proconfig::text || ' ' || pg_get_function_identity_arguments(oid) || ' ' ||
             (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_invoice_detail')
        from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure),
     '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} false s {"search_path=public, pg_temp"} p_invoice_id uuid 1'),
  ('R1  재발행 함수: update · delete 낱말 0(주석 뺀 본문 · 읽기만 — WHERE 없는 update · delete 0)',
     (select (select count(*) from regexp_matches(regexp_replace(prosrc, '--[^\n]*', '', 'g'), '\m(update|delete|insert|truncate)\M', 'gi'))::text from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure), '0'),
  ('Z1  본문 = 옛 본문 + 한 줄(prosrc 에서 due_date_manual 줄을 빼면 md5 b350…48e2)',
     (select md5(regexp_replace(prosrc, '\n[^\n]*''due_date_manual'', i\.due_date_manual,[^\n]*', '')) from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure),
     'b35031559b188bd70f12434ba4ad48e2')
) x(label, got, want);

select count(*) filter (where ok) as ok, count(*) as total, :EXPECT_OK as expect, case when count(*) filter (where ok) = :EXPECT_OK and count(*) = :EXPECT_OK then 'ALL OK' else 'NOT OK' end as verdict from t_res;
select who, count(*) as docs, count(*) filter (where v ? 'ERR') as errs, count(*) filter (where v -> 'header' ? 'due_date_manual') as has_key from t_snap where phase = 'new' group by who order by who;
rollback;
select (select count(*) from public.po_invoice where invoice_number like 'ZZ-PODUE-%') as fakes_left, (select md5(prosrc) from pg_proc where oid = 'public.po_invoice_detail(uuid)'::regprocedure) as md5_after_rollback;
