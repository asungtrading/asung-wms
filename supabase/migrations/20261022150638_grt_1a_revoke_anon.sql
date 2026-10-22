do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;

-- ═══ grt-1a — anon 권한 거두기(public 의 표 · 뷰 · 물질화 뷰 · 시퀀스) (2026-10-22 · 판정 617 · 618 · grt-0) ═══
--   근거(618): 컷오버 = Asung-IMS 승격 · 공개 레포에 anon 키가 있다 · 로그인 안 한 사람의 권한은 운영 전에 0.
--   grt-0 실측: anon 이 relacl 에 든 객체 70 = 표 25(wms_* 20 · inv_adjust · inv_move · inv_transfer(+line) · po_receipt_post · so_line_merge_source) · 뷰 2(wms_order_doc · _line) · 시퀀스 43 — anon · public 대상 RLS 정책 0 · anon 실행권은 definer 0 · invoker 6(표 안 읽음) · 화면 · EF · GAS 가 anon 키로 표를 치는 곳 0.
--   하는 일: ① revoke all … from anon(표 · 뷰 · 물질화 뷰 = ALL TABLES · 시퀀스) ② 기본 권한(postgres · public)에서 anon 의 표 · 시퀀스 몫(Dxtm · w)을 거둔다 · 함수 기본 권한(f · anon=X)은 범위 밖(그대로).
--   지키는 것: anon 말고는 한 비트도 안 바뀐다(authenticated · service_role · postgres 의 relacl 바이트 그대로 · 착지 ②) · 새 객체 0(판정 615 · 착지 ⑤).
create temp table grt1a_before as
  select c.oid, c.relname, c.relkind::text as relkind,
         (select coalesce(string_agg(a::text, ',' order by a::text), '') from unnest(c.relacl) a where a::text not like 'anon=%') as acl_wo_anon
  from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'S');
create temp table grt1a_before_def as
  select d.defaclobjtype::text as t, d.defaclacl::text as acl from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace;

revoke all on all tables in schema public from anon;                                 -- 표 · 뷰 · 물질화 뷰 · 파티션 표 전부(PG: ALL TABLES 는 뷰 · 물질화 뷰를 포함한다)
revoke all on all sequences in schema public from anon;
alter default privileges for role postgres in schema public revoke all on tables from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;

-- ═══ 착지 — ① anon 0 ② 다른 역할 바이트 무변 ③ 기본 권한 r · S 에 anon 0 ④ 함수 기본 권한 무변 ⑤ 새 객체 0 ═══
do $$
declare v_bad text := '';  v_n int;  v_f_before text;  v_f_after text;
begin
  select count(*) into v_n from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'S') and c.relacl::text like '%anon=%';
  if v_n <> 0 then v_bad := v_bad || format(' anon_still_on_%s', v_n); end if;
  select count(*) into v_n from grt1a_before b join pg_class c on c.oid = b.oid
   where b.acl_wo_anon is distinct from (select coalesce(string_agg(a::text, ',' order by a::text), '') from unnest(c.relacl) a where a::text not like 'anon=%');
  if v_n <> 0 then v_bad := v_bad || format(' other_roles_changed_%s', v_n); end if;
  select count(*) into v_n from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype in ('r', 'S') and d.defaclacl::text like '%anon=%';
  if v_n <> 0 then v_bad := v_bad || format(' default_anon_%s', v_n); end if;
  select acl into v_f_before from grt1a_before_def where t = 'f';
  select d.defaclacl::text into v_f_after from pg_default_acl d where d.defaclrole = 'postgres'::regrole and d.defaclnamespace = 'public'::regnamespace and d.defaclobjtype = 'f';
  if v_f_before is distinct from v_f_after then v_bad := v_bad || ' function_default_changed'; end if;
  select count(*) into v_n from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'S') and c.oid not in (select oid from grt1a_before);
  if v_n <> 0 then v_bad := v_bad || format(' new_objects_%s', v_n); end if;
  if (select count(*) from grt1a_before) <> (select count(*) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relkind in ('r', 'v', 'm', 'p', 'S')) then v_bad := v_bad || ' object_count_changed'; end if;
  if v_bad <> '' then raise exception 'grt-1a landing check failed:%', v_bad; end if;
end $$;
drop table grt1a_before;
drop table grt1a_before_def;
