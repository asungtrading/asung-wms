-- supabase/tests/lec_1_check.sql — lec-1 so_customer_is_company 도매 등급 = 법인 검증 (2026-10-27 · 판정 번호는 문서 차수가 · 짐작 793)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음: 활성 손님 전수 「지금 규칙(함수) vs 새 규칙(식)」 · 행 수 · 함수 md5)
--   → begin → (-v mig 면 \i) → 함수 꼴 · 권한 · 가짜 손님 LEC- 열여섯(등급 code 1·2·4·7) · 실제 손님 하나(읽기) · 전수 비교 · 걸린 시간 → rollback → 실제 행 무변 · 함수 md5 복귀
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027140700_lec_1_company_by_tier.sql -f supabase/tests/lec_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 38 · 확인(적용 뒤 · -v mig 없음) 36 — A3 · A5 는 「옛 함수 vs 새 규칙」 비교라 시험 갈래에서만 돈다(§50-c)
--   적용 전 마른 실행(-v mig 없음)은 C1 C2 C3 C9 C10 C11 C12 C16 F6 A1 A2 열하나가 MISMATCH(아직 옛 규칙 — 정상)
--   쓰기 0 — 가짜 손님 · 연락처는 rollback · customer · customer_contact 행 수 전후 대조 · 번호를 당기는 창구는 부르지 않는다
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 38
\else
\set EXPECT_OK 36
\endif
\pset pager off
-- 기준(begin 앞 · 잠금 없음 · 무거운 것은 여기): 활성 손님 전수 — 지금 규칙(DB 함수) · 새 규칙(식 — 함수와 독립) · 바뀌는 수
create temp table t_base as
  with k as (
    select c.id, c.name, c.price_tier, c.is_legal_entity,
           public.so_customer_is_company(c.id) as cur,
           (select cc.name from public.customer_contact cc
             where cc.customer_id = c.id and cc.is_default and cc.is_active and nullif(trim(cc.name), '') is not null
             order by cc.created_at limit 1) as kname,
           exists (select 1 from public.ref_price_tier t where t.code in (1, 2, 4, 7) and lower(trim(t.name)) = lower(trim(c.price_tier))) as tier_co
    from public.customer c where c.is_active)
  select id, name, price_tier, is_legal_entity, cur, tier_co,
         case when is_legal_entity or tier_co then true
              when price_tier = 'AONE' then false
              when kname is not null and lower(trim(name)) <> lower(trim(kname))
                   and position(lower(trim(kname)) in lower(trim(name))) = 0 and position(lower(trim(name)) in lower(trim(kname))) = 0 then true
              else false end as new_exp
  from k;
select count(*) as n_active, count(*) filter (where cur is distinct from new_exp) as n_changed,
       count(*) filter (where cur is distinct from new_exp and price_tier = 'Wholesale' and not is_legal_entity and not cur and new_exp) as n_changed_wh,
       count(*) filter (where tier_co and not is_legal_entity) as n_tier_only,
       count(*) filter (where tier_co and not is_legal_entity and cur) as n_already_3
from t_base \gset
select (select count(*) from public.customer) as n_cust, (select count(*) from public.customer_contact) as n_contact,
       (select count(*) from public.customer where name like 'LEC-%') as n_lec0,
       (select count(*) from public.ref_price_tier) as n_tier,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_customer_is_company') as fn_md5_0,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_customer_is_company') as n_fn0,
       has_function_privilege('service_role', 'public.so_customer_is_company(uuid)', 'execute')::text as sr0 \gset
\echo '── 기준: active' :n_active '· changed(cur≠new)' :n_changed '(Wholesale·legal f·f→t' :n_changed_wh ') · tier-only' :n_tier_only '(already by ③' :n_already_3 ') · customer' :n_cust '· contact' :n_contact '· LEC- rows' :n_lec0 '· fn md5' :fn_md5_0
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
-- 가짜 손님 하나 만들고 판정을 글자로 돌려준다(LEC- 접두 · source manual · rollback 됨)
create function pg_temp.mk(p_name text, p_tier text, p_legal boolean, p_contact text default null) returns text language plpgsql as $$
declare v_id uuid;
begin
  insert into public.customer (name, price_tier, is_legal_entity, source, is_active) values (p_name, p_tier, p_legal, 'manual', true) returning id into v_id;
  if p_contact is not null then
    insert into public.customer_contact (customer_id, name, is_default, is_active, source) values (v_id, p_contact, true, true, 'manual');
  end if;
  return public.so_customer_is_company(v_id)::text;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;

-- ── F 함수 꼴: 하나 · 시그니처 (uuid) · sql · stable · invoker · search_path · comment lec-1 ──
select count(*)::text as n_fn, coalesce(max(p.provolatile::text), '-') as vol, coalesce(max(p.prosecdef::text), '-') as def,
       coalesce(max(array_to_string(p.proconfig, ',')), '-') as cfg, coalesce(max(l.lanname), '-') as lang,
       coalesce(max(pg_get_function_identity_arguments(p.oid)), '-') as args,
       coalesce(max(left(obj_description(p.oid, 'pg_proc'), 5)), '-') as cmt
from pg_proc p join pg_language l on l.oid = p.prolang
where p.pronamespace = 'public'::regnamespace and p.proname = 'so_customer_is_company' \gset
select pg_temp.chk('F1 one so_customer_is_company', :'n_fn', '1');
select pg_temp.chk('F2 signature (p_customer_id uuid) unchanged', :'args', 'p_customer_id uuid');
select pg_temp.chk('F3 language sql', :'lang', 'sql');
select pg_temp.chk('F4 stable', :'vol', 's');
select pg_temp.chk('F5 security invoker', :'def', 'false');
select pg_temp.chk('F6 comment starts lec-1', :'cmt', 'lec-1');
select pg_temp.chk('F7 search_path', :'cfg', 'search_path=public, pg_temp');

-- ── P 권한: authenticated 만 · anon · public · service_role 없음 ──
select pg_temp.chk('P1 authenticated can execute', pg_temp.run('select has_function_privilege(''authenticated'', ''public.so_customer_is_company(uuid)'', ''execute'')::text'), 'true');
select pg_temp.chk('P2 anon cannot',               pg_temp.run('select has_function_privilege(''anon'', ''public.so_customer_is_company(uuid)'', ''execute'')::text'), 'false');
select pg_temp.chk('P3 service_role execute unchanged from before (원본 revoke 는 public · anon 만)', pg_temp.run('select has_function_privilege(''service_role'', ''public.so_customer_is_company(uuid)'', ''execute'')::text'), :'sr0');
select pg_temp.chk('P4 public (any role) no default grant', pg_temp.run('select (p.proacl is not null and not exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0))::text from pg_proc p where p.pronamespace = ''public''::regnamespace and p.proname = ''so_customer_is_company'''), 'true');
select pg_temp.chk('P5 so_copy_customer still the only caller', pg_temp.run('select string_agg(p.oid::regprocedure::text, '','' order by 1) from pg_proc p where p.pronamespace = ''public''::regnamespace and p.prosrc like ''%so_customer_is_company%'' and p.proname <> ''so_customer_is_company'''), 'so_copy_customer(uuid,uuid)');

-- ── C 가짜 손님 LEC- (규칙 ① 등급 · ② AONE · ③ 연락처 · ④ 그 밖) ──
select pg_temp.chk('C1 Wholesale · legal f · no contact → company',            pg_temp.mk('LEC-C1 Wholesale Person', 'Wholesale', false), 'true');
select pg_temp.chk('C2 USWholesale USD · legal f · no contact → company',      pg_temp.mk('LEC-C2 US Person', 'USWholesale USD', false), 'true');
select pg_temp.chk('C3 Regular CAD · legal f · no contact → company',          pg_temp.mk('LEC-C3 Regular Person', 'Regular CAD', false), 'true');
select pg_temp.chk('C4 AONE · legal f · contact same name → person',           pg_temp.mk('LEC-C4 Aone Same', 'AONE', false, 'LEC-C4 Aone Same'), 'false');
select pg_temp.chk('C5 AONE · legal f · no contact → person',                  pg_temp.mk('LEC-C5 Aone None', 'AONE', false), 'false');
select pg_temp.chk('C6 AONE · legal t → company (① first)',                    pg_temp.mk('LEC-C6 Aone Legal', 'AONE', true), 'true');
select pg_temp.chk('C7 tier null · legal f · contact differs → company (③ as before)', pg_temp.mk('LEC-C7 Null Tier Corp', null, false, 'Someone Else'), 'true');
select pg_temp.chk('C8 tier null · legal f · no contact → person (④ as before)',       pg_temp.mk('LEC-C8 Null Tier Person', null, false), 'false');
select pg_temp.chk('C9 "wholesale " lower + trailing space → company (text match)',    pg_temp.mk('LEC-C9 Lower Wholesale', 'wholesale ', false), 'true');
select pg_temp.chk('C10 " REGULAR CAD" upper + leading space → company (text match)',  pg_temp.mk('LEC-C10 Upper Regular', ' REGULAR CAD', false), 'true');
select pg_temp.chk('C11 Franchise (code 2 · Caleb 2026-10-27) · legal f · no contact → company', pg_temp.mk('LEC-C11 Franchise Person', 'Franchise', false), 'true');
select pg_temp.chk('C12 Wholesale · contact contained in name (Hamilton) → company (① before ③④)', pg_temp.mk('LEC-C12 Adrian Hamilton', 'Wholesale', false, 'Hamilton'), 'true');
select pg_temp.chk('C13 AONE · legal f · contact differs → person (② before ③ · as before)', pg_temp.mk('LEC-C13 Aone Corp', 'AONE', false, 'Someone Else'), 'false');
select pg_temp.chk('C14 Wholesale · legal t → company',                        pg_temp.mk('LEC-C14 Wholesale Legal', 'Wholesale', true), 'true');
select pg_temp.chk('C15 unknown tier text "Wholesale USD" (no such name) · no contact → person', pg_temp.mk('LEC-C15 Wrong Name', 'Wholesale USD', false), 'false');
select pg_temp.chk('C16 " franchise" lower + leading space → company (text match)', pg_temp.mk('LEC-C16 Lower Franchise', ' franchise', false), 'true');
select pg_temp.chk('C17 LEC- fake rows inside txn = 16', (select count(*)::text from public.customer where name like 'LEC-%'), '16');

-- ── R 실제 손님(읽기만): 합의된 오차 손님 1001132194 ONTARIO INC — 지금 Wholesale · legal f · 이미 ③ 으로 회사 → 무변 ──
select pg_temp.chk('R1 1001132194 ONTARIO INC → company (unchanged)',
  pg_temp.run('select public.so_customer_is_company(id)::text from public.customer where name = ''1001132194 ONTARIO INC'' and is_active'), 'true');
select pg_temp.chk('R2 1001132194 ONTARIO INC was company under old rule too (baseline)',
  (select cur::text from t_base where name = '1001132194 ONTARIO INC'), 'true');

-- ── A 활성 손님 전수: 함수 = 새 규칙 식 · 바뀐 수 = 기준 · 바뀐 손님은 전부 Wholesale · legal f ──
select clock_timestamp() as t0 \gset
create temp table t_now as select b.id, public.so_customer_is_company(b.id) as now from t_base b;
select clock_timestamp() as t1 \gset
select pg_temp.chk('A1 all active: function = new-rule expression (diff 0)', (select count(*)::text from t_base b join t_now n using (id) where n.now is distinct from b.new_exp), '0');
select pg_temp.chk('A2 all active: changed vs old rule = baseline n_changed', (select count(*)::text from t_base b join t_now n using (id) where n.now is distinct from b.cur), :'n_changed');
\if :{?mig}
-- 시험 갈래에서만(§50-c): 「DB 의 옛 함수 vs 새 규칙」 은 적용 전에만 성립한다 — 적용 뒤 확인 갈래에서는 n_changed 0 · tier-only 전부 회사
select pg_temp.chk('A3 baseline n_changed = 56 (2026-10-27 실측 · 재적재 뒤면 바뀔 수 있다)', :'n_changed', '56');
\endif
select pg_temp.chk('A4 every changed customer is Wholesale · legal f · f→t', :'n_changed_wh', :'n_changed');
\if :{?mig}
select pg_temp.chk('A5 tier-only 829 · already company by ③ 773 (2026-10-27 실측)', :'n_tier_only' || '/' || :'n_already_3', '829/773');
\endif
select pg_temp.chk('A6 no AONE customer changes', (select count(*)::text from t_base b join t_now n using (id) where n.now is distinct from b.cur and b.price_tier = 'AONE'), '0');

-- ── T 걸린 시간 ──
select round(extract(epoch from (:'t1'::timestamptz - :'t0'::timestamptz)) * 1000)::int as call_ms \gset
select pg_temp.chk(format('T1 full-scan call < 8000 ms (measured %s ms)', :call_ms), (:call_ms < 8000)::text, 'true');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.customer) = :n_cust as customer_same,
       (select count(*) from public.customer_contact) = :n_contact as contact_same,
       (select count(*) from public.customer where name like 'LEC-%') = :n_lec0 as lec_rows_same,
       (select count(*) from public.ref_price_tier) = :n_tier as tier_same,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_customer_is_company') = :'fn_md5_0' as fn_md5_same_as_before,
       (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_customer_is_company') = :n_fn0 as fn_count_same;
