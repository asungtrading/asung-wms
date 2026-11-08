-- supabase/tests/qbo_sync_3_2a_check.sql — qbo-sync-3-2a 검증 (2026-11-08 밤 · 판정 1082 ~ 1085 · 1087 · 1090 · 1092 ~ 1103 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → S 구조 · E 기대값(126,715.43 · 264 SO · 1094 · 1096 · 1099 · 1103 · 살린 트럭 · opening_fix · 상계) · B 장 만들기(12 장 · 열쇠 · 균형 · 10-31 양방향) · D 차액(1 센트 · adj 꼬리 · 차례 P) · H 보류 결정 · M 월 검산 · K 572 · W WHERE 정적 · G grant → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261108170000_qbo_sync_3_2a_cost_sheet_db.sql -f supabase/tests/qbo_sync_3_2a_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — B1 의 「만든 수」 는 이미 cron 이 만든 장을 빼고 센다(existing + built = 12)
--   ⚠️ 공개 레포 — 상호를 찍지 않는다(문서 번호 · 금액 · 수만) · 시퀀스는 안 나간다(새 표 PK uuid · inv_layer 계열에 행을 넣지 않는다 · 문턱 시험은 키 값을 트랜잭션 안에서 100 으로 · 이견 10) · 가짜 직원 한 명(ims_staff · uuid · rollback)
\set ON_ERROR_STOP on
\pset pager off
select (select value from public.inv_config where key = 'db_role') as db_role;
select (select realm_id from public.qbo_connection where singleton) as realm \gset

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is not distinct from p_want then '' else format(' — got %s · want %s', coalesce(p_got, '(null)'), coalesce(p_want, '(null)')) end;
end $$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
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
set local statement_timeout = '600s';
-- ── 기준(begin 안 · \i 앞) ──
select (select count(*) from public.ims_staff) as pre_staff, (select count(*) from public.inv_layer) as pre_layer, (select count(*) from public.inv_layer_consume) as pre_cons, (select count(*) from public.inv_layer_cost_add) as pre_add,
       (select coalesce(min(id), 0) from public.inv_layer_consume) as pre_epoch, (select count(*) from public.inv_config) as pre_cfg \gset
\echo '── 기준: staff' :pre_staff '· inv_layer' :pre_layer '· consume' :pre_cons '(min id' :pre_epoch ') · cost_add' :pre_add '· inv_config' :pre_cfg '· realm' :realm
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif
select (select count(*) from public.qbo_cost_sheet where kind = 'day' and sheet_date <= '2026-11-06') as pre_sheets \gset

-- ── S 구조 ──
select pg_temp.chk('S1 표 셋 · RLS 켜짐 · 표 grant 0',
  (select string_agg(c.relname || ':' || c.relrowsecurity::text || ':' || coalesce(c.relacl::text, '{}'), ' ' order by c.relname) from pg_class c where c.relnamespace = 'public'::regnamespace and c.relname in ('qbo_cost_sheet', 'qbo_cost_sent', 'qbo_cost_hold')),
  'qbo_cost_hold:true:{postgres=arwdDxtm/postgres} qbo_cost_sent:true:{postgres=arwdDxtm/postgres} qbo_cost_sheet:true:{postgres=arwdDxtm/postgres}');
select pg_temp.chk('S2 inv_config 키 셋', (select string_agg(key || '=' || value, ' ' order by key) from public.inv_config where key in ('qbo_send_cost_enabled', 'qbo_cost_adjust_hold_over', 'qbo_cost_since')), 'qbo_cost_adjust_hold_over=1000 qbo_cost_since=2026-10-31 qbo_send_cost_enabled=off');
select pg_temp.chk('S3 상수: 창고 코드 · 제외 넷 · 비용 계정 · IN_TRANSIT 레이어의 장 창고(TRF-00003 → TOR)',
  public.qbo_cost_wh_code('Asung Trading Inc.') || ' ' || public.qbo_cost_wh_code('Asung - Edmonton') || ' ' || coalesce(public.qbo_cost_wh_code('IN_TRANSIT'), 'null') || ' ' || array_to_string(public.qbo_cost_excluded_docs(), ',') || ' ' || public.qbo_cost_charge_account('duty') || public.qbo_cost_charge_account('brokerage') || public.qbo_cost_charge_account('freight') || coalesce(public.qbo_cost_charge_account('x'), 'null') || ' ' || public.qbo_cost_layer_wh('IN_TRANSIT', 'TRF-00003') || ' ' || public.qbo_cost_layer_wh('Asung - Edmonton', 'x'),
  'TOR EDM null TR-06396,TR-06397,TR-06398,TR-06399 _134__135__136_null TOR EDM');
select pg_temp.chk('S4 PK 전부 uuid · 시퀀스 새로 생긴 것 0', (select string_agg(c.table_name || '.' || c.column_name || ':' || c.data_type, ' ' order by c.table_name) from information_schema.columns c join information_schema.table_constraints tc on tc.table_schema = c.table_schema and tc.table_name = c.table_name and tc.constraint_type = 'PRIMARY KEY' join information_schema.key_column_usage k on k.constraint_name = tc.constraint_name and k.column_name = c.column_name where c.table_schema = 'public' and c.table_name in ('qbo_cost_sheet', 'qbo_cost_sent') and c.column_name = 'id') || ' ' || (select count(*) from pg_sequences where sequencename like 'qbo_cost%')::text, 'qbo_cost_sent.id:uuid qbo_cost_sheet.id:uuid 0');

-- ── E 기대값 (≤ 11-06 · 운영 데이터 · 3-2-0 S1 · S2 · S9 실측과 맞댄다) ──
create temp table t_exp as select * from public.qbo_cost_expected(date '2026-11-06', null, :'realm');
select pg_temp.chk('E1 판매 원가(SO · #58/#59 · send) = 264 SO · 126,715.43(원금 합) · 센트 합과 ±0.20 안',
  (select count(distinct e.doc_key)::text || ' ' || round(sum(e.raw_amount), 2)::text || ' ' || (abs(sum(e.cents) - 12671543) <= 20)::text from t_exp e where e.key_kind = 'SO' and e.acct_a = '_58_' and e.acct_b = '_59_' and e.status = 'send'), '264 126715.43 true');
select pg_temp.chk('E2 상태 넷뿐 · block 0(지금 데이터는 22 칸 안)', ((select string_agg(x.status || ':' || x.n, ' ' order by x.status) from (select e.status, count(*) as n from t_exp e group by e.status) x) ~ '^(excluded:[0-9]+ )?(hold:[0-9]+ )?send:[0-9]+$' and not exists (select 1 from t_exp e where e.status = 'block'))::text, 'true');
select pg_temp.chk('E3 살린 트럭 도착 넷 = excluded · 15,158.90(짝 (_1150040007_,_59_) 에서 차 #59 = 음수) · 출발(10-26) 은 날짜 바닥에 걸러 없음 · send 에 TR- 0',
  (select count(distinct e.doc_key)::text || ' ' || round(sum(e.raw_amount), 2)::text from t_exp e where e.doc_key = any (public.qbo_cost_excluded_docs()) and e.status = 'excluded' and e.acct_a = '_1150040007_' and e.acct_b = '_59_') || ' ' || (select count(*) from t_exp e where e.doc_key like 'TR-%' and e.status = 'send')::text, '4 -15158.90 0');
select pg_temp.chk('E4 opening_fix 가족 = excluded(cost_late · cost_moved · 얹기 13,035.48) · send 에 TR-03975/6 · adj: 없음 · Cin7 SO(SO-18513) 없음 · 트랜스퍼 복사 carried 안 셈(CHG · TRF 얹기 줄 0)',
  (select round(sum(e.raw_amount), 2)::text from t_exp e where e.status = 'excluded' and e.reason like 'opening_fix%' and e.key_kind = 'opening_fix') || ' ' || (select count(*) from t_exp e where e.status = 'send' and (e.doc_key in ('TR-03975', 'TR-03976', 'SO-18513') or e.doc_key like 'adj:%'))::text || ' ' || (select count(*) from t_exp e where e.key_kind = 'CHG' and e.status = 'send')::text, '13035.48 0 0');
select pg_temp.chk('E5 1094 sale_shortfall SO-21090(EDM) = 차 #59 / 대 #1150040010 6.33 → 짝(_1150040010_,_59_) 센트 −633 · 판매 줄은 그대로(_58_/_59_)',
  (select string_agg(e.wh_code || ' ' || e.acct_a || '/' || e.acct_b || ' ' || e.cents::text, ' · ' order by e.acct_a) from t_exp e where e.doc_key = 'SO-21090' and e.status = 'send'), 'EDM _1150040010_/_59_ -633 · EDM _58_/_59_ ' || (select e.cents::text from t_exp e where e.doc_key = 'SO-21090' and e.acct_a = '_58_'));
select pg_temp.chk('E6 1096 입고 RCV-00117 · 00121 = hold · 차 #59 / 대 GINR · 12,989.53(짝 (_1150040012_,_59_) 에서 음수)', (select count(*)::text || ' ' || round(sum(e.raw_amount), 2)::text || ' ' || min(e.acct_a || '/' || e.acct_b) from t_exp e where e.key_kind = 'RCV' and e.status = 'hold'), '2 -12989.53 _1150040012_/_59_');
select pg_temp.chk('E7 상계(이견 7): 취소된 크레딧 CR-01015 · 01025 = restock + reversal → 줄 없음 · CR-01026 = (_58_,_59_) −40014 · CR 18 중 send 16',
  (select count(*) from t_exp e where e.doc_key in ('CR-01015', 'CR-01025'))::text || ' ' || (select e.cents::text from t_exp e where e.doc_key = 'CR-01026') || ' ' || (select count(distinct e.doc_key) from t_exp e where e.key_kind = 'CR' and e.status = 'send')::text, '0 -40014 16');
select pg_temp.chk('E8 1103 Entity: #58 짝 SO 264 모두 인보이스 손님 있음 · CR 16 모두 크레딧 손님 있음 · #59 모음 쪽(1150040010 짝)엔 없음',
  (select count(*) filter (where e.entity_customer_id is not null)::text || '/' || count(*)::text from t_exp e where e.key_kind = 'SO' and e.acct_a = '_58_' and e.status = 'send') || ' ' || (select count(*) filter (where e.entity_customer_id is not null)::text || '/' || count(*)::text from t_exp e where e.key_kind = 'CR' and e.status = 'send') || ' ' || (select count(*) from t_exp e where e.acct_a = '_1150040010_' and e.entity_customer_id is not null)::text, '264/264 16/16 0');
select pg_temp.chk('E9 1085 트랜스퍼 출발 TRF-00003 · 00005 = TOR · (_1150040007_,_59_) + 11,150.38 · 9,482.65 · 도착 0(아직 운송 중)',
  (select string_agg(e.doc_key || ' ' || e.wh_code || ' ' || e.acct_a || '/' || e.acct_b || ' ' || round(e.raw_amount, 2)::text, ' · ' order by e.doc_key) from t_exp e where e.key_kind = 'TRF' and e.status = 'send'), 'TRF-00003 TOR _1150040007_/_59_ 11150.38 · TRF-00005 TOR _1150040007_/_59_ 9482.65');
select pg_temp.chk('E10 10-31 조정 양방향(이견 11): TOR adjust_out 240.93 · 레이어 118.11 · EDM 80.15 · 47.37 — 짝(_1150040010_,_59_) 원금 합 TOR 122.82 · EDM 32.79(원금 32.786902 · 두 자리 표시 47.37 − 80.15 = 32.78 은 표시 반올림 차)',
  (select string_agg(x.wh || ' ' || round(x.s, 2)::text, ' ' order by x.wh) from (select e.wh_code as wh, sum(e.raw_amount) as s from t_exp e where e.key_kind = 'ADJ' and e.first_on = '2026-10-31' and e.last_on = '2026-10-31' group by e.wh_code) x), 'EDM 32.79 TOR 122.82');
select pg_temp.chk('E11 날짜 바닥: p_since 11-02 로 좁히면 10-31 조정 없음 · 1900 까지로 넓혀도 ims 출처 밖(Cin7 10-30 SO 78)은 안 들어옴',
  (select count(*) from public.qbo_cost_expected(date '2026-11-06', date '2026-11-02', :'realm') e where e.first_on < '2026-11-02')::text || ' ' || (select count(*) from public.qbo_cost_expected(date '2026-10-30', date '1900-01-01', :'realm') e where e.key_kind = 'SO' and e.status = 'send')::text, '0 0');
select pg_temp.chk('E12 모르는 칸 예외 꼴: lost 흉내 — 장 만들기가 문서 번호 · 칸을 글에 싣는다(가짜 행 없이 reason 글만 검사)',
  (pg_temp.try($q$select reason from public.qbo_cost_expected(date '2026-11-06') where status = 'block' limit 1$q$) = '(null)')::text, 'true');

-- ── B 장 만들기(장 행만 · 12 장 · 열쇠 · 균형) ──
select public.qbo_cost_sheet_build_due(:'realm') as b \gset
select pg_temp.chk('B1 build_due: 막힘 0 · 11-06 까지 장 12(기존 + 이번) · 11-01 · 11-07 · 11-08 없음',
  jsonb_array_length(:'b'::jsonb->'errors')::text || ' ' || (select count(*) from public.qbo_cost_sheet s where s.kind = 'day' and s.sheet_date <= '2026-11-06')::text || ' ' || (select count(*) from public.qbo_cost_sheet s where s.sheet_date in ('2026-11-01', '2026-11-07', '2026-11-08'))::text, '0 12 0');
select pg_temp.chk('B2 장 날 · 창고 = 10-31 둘 + 11-02 ~ 06 × 둘 · state pending · DocNumber 꼴 · epoch = min(consume id)',
  (select string_agg(to_char(s.sheet_date, 'MMDD') || s.wh, ',' order by s.sheet_date, s.wh) from public.qbo_cost_sheet s where s.kind = 'day' and s.sheet_date <= '2026-11-06') || ' ' || (select string_agg(distinct s.state, ',') from public.qbo_cost_sheet s) || ' ' || (select bool_and(s.doc_number = 'COGS-' || to_char(s.sheet_date, 'YYYYMMDD') || '-' || s.wh and s.epoch = :pre_epoch)::text from public.qbo_cost_sheet s),
  '1031EDM,1031TOR,1102EDM,1102TOR,1103EDM,1103TOR,1104EDM,1104TOR,1105EDM,1105TOR,1106EDM,1106TOR pending true');
select pg_temp.chk('B3 한 장 최대 열쇠 = TOR 11-06(3-2-0 S9: 56 = SO 46 + ADJ 4 + CR 4 + RCV 1 + TRF 1 · RCV-00121 은 보류 · CR-01025 는 restock + 취소 상계 0 → 보낼 열쇠 54 · 보류 열쇠 2 = RCV-00117 · 00121 누적) · 11-02 TOR SO 49',
  (select s.wh || ' ' || s.sheet_date::text || ' ' || s.built_keys::text || ' hold ' || s.built_hold_keys::text from public.qbo_cost_sheet s order by s.built_keys desc limit 1) || ' · ' || (select count(distinct c.doc_key)::text from public.qbo_cost_sheet_calc(date '2026-11-02', 'TOR', :'realm') c where c.key_kind = 'SO' and c.status = 'send'),
  'TOR 2026-11-06 54 hold 2 · 49');
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'zz-qbo-sync-3-2a@test.invalid', 'ZZ qbo-sync-3-2a bookkeeper', 'manager', '["ims", "qbo"]', '{}') returning auth_user_id::text as st_uid \gset
select pg_temp.as_user(:'st_uid');
create temp table t_prev as
  select s.sheet_date, s.wh, public.qbo_cost_preview(s.sheet_date, s.wh) as p from public.qbo_cost_sheet s where s.kind = 'day' and s.sheet_date <= '2026-11-06';
select pg_temp.chk('B4 미리 보기 12 장 모두 balanced · error 없음 · #59 순액 한 줄 · 줄 수 = 열쇠 줄 + 1',
  (select count(*) filter (where (p->>'balanced')::boolean)::text || '/' || count(*)::text || ' ' || count(*) filter (where p->>'error' is not null)::text || ' ' || bool_and((select count(*) from jsonb_array_elements(p->'je_lines') l where l->>'account_code' = '_59_') = 1)::text || ' ' || bool_and((p->>'je_line_count')::int = (select count(*) from jsonb_array_elements(p->'je_lines') l where l->>'account_code' <> '_59_') + 1)::text from t_prev), '12/12 0 true true');
select pg_temp.chk('B5 TOR 11-06 미리 보기: 차 = 대 · 줄 반올림의 합(1097) · Entity 가 SO #58 줄마다 QBO 번호 또는 null(7 명 미짝)',
  (select (p->>'debit_cents' = p->>'credit_cents')::text || ' ' || (p->>'je_line_count') || ' ' || (select count(*) filter (where l->>'entity_qbo_id' is not null)::text || '/' || count(*)::text from jsonb_array_elements(p->'je_lines') l where l->>'account_code' = '_58_' and l->>'key_kind' = 'SO') from t_prev where sheet_date = '2026-11-06' and wh = 'TOR'),
  (select 'true ' || (p->>'je_line_count') || ' ' || (select count(*) filter (where l->>'entity_qbo_id' is not null)::text || '/' || count(*)::text from jsonb_array_elements(p->'je_lines') l where l->>'account_code' = '_58_' and l->>'key_kind' = 'SO') from t_prev where sheet_date = '2026-11-06' and wh = 'TOR'));
select pg_temp.chk('B5b 7 SO 의 인보이스 손님이 qbo_link 에 없다(이견 3 · 3-2b needs) — 264 중 7', (select count(*) from t_exp e where e.key_kind = 'SO' and e.acct_a = '_58_' and e.status = 'send' and not exists (select 1 from public.qbo_link l where l.realm_id = :'realm' and l.ims_kind = 'customer' and l.ims_id = e.entity_customer_id::text))::text, '7');
select pg_temp.chk('B6 10-31 TOR 미리 보기: ADJ 열쇠 줄(_1150040010_) = 그날 ADJ 열쇠 수(문서마다 들어옴 · 나감이 한 짝으로 상계돼 한 줄) · #59 한 줄 · balanced · baseline none',
  (select (p->>'balanced')::text || ' ' || ((select count(*) from jsonb_array_elements(p->'je_lines') l where l->>'account_code' = '_1150040010_') = (select count(*) from jsonb_array_elements(p->'keys') k where k->>'key_kind' = 'ADJ'))::text || ' ' || (p->>'baseline') from t_prev where sheet_date = '2026-10-31' and wh = 'TOR'), 'true true none');
select pg_temp.chk('B7 차례 P(이견 9): 11-03 TOR 는 앞 장 11-02 가 pending → baseline pending:2026-11-02 · 11-02 열쇠는 11-03 장에 없음(기대(≤03) − 기대(≤02))',
  (select (p->>'baseline') || ' ' || (select count(*) from jsonb_array_elements(p->'keys') k where (k->>'first_sent_on') is not null)::text || ' ' || (select count(*) from jsonb_array_elements(p->'keys') k where k->>'doc_key' in (select c.doc_key from public.qbo_cost_sheet_calc(date '2026-11-02', 'TOR', :'realm') c where c.status = 'send' and c.key_kind = 'SO'))::text from t_prev where sheet_date = '2026-11-03' and wh = 'TOR'), 'pending:2026-11-02 0 0');
select pg_temp.chk('B8 닫히지 않은 날 · since 앞 · 이미 있는 장', (pg_temp.try(format('select public.qbo_cost_sheet_build(%L, ''TOR'', %L)::text', public.ims_today(), :'realm')) ~ 'is not closed yet')::text || ' ' || (pg_temp.try(format('select public.qbo_cost_sheet_build(%L, ''TOR'', %L)::text', date '2026-10-30', :'realm')) ~ 'before the sync start')::text || ' ' || (public.qbo_cost_sheet_build(date '2026-11-02', 'TOR', :'realm')->>'existing'), 'true true true');

-- ── D 차액(1092): 10-31 · 11-02 TOR 를 보낸 것으로 두고 보낸 몫에 1 센트 다르게 → 11-03 장에 그 열쇠 차액 한 줄 + 꼬리 ──
reset role;
select set_config('request.jwt.claims', '', true);
do $$
declare v_realm text := (select realm_id from public.qbo_connection where singleton); r record; v_s uuid; v_first boolean := true;
begin
  for r in select s.* from public.qbo_cost_sheet s where s.realm_id = v_realm and s.wh = 'TOR' and s.sheet_date in ('2026-10-31', '2026-11-02') order by s.sheet_date loop
    insert into public.qbo_cost_sent (sheet_id, realm_id, wh, key_kind, doc_key, acct_a, acct_b, cents)
    select r.id, v_realm, 'TOR', c.key_kind, c.doc_key, c.acct_a, c.acct_b, c.diff_cents from public.qbo_cost_sheet_calc(r.sheet_date, 'TOR', v_realm) c where c.status = 'send' and c.diff_cents <> 0;
    update public.qbo_cost_sheet set state = 'sent', sent_at = now(), qbo_id = 'ZZ-test-' || r.sheet_date::text where id = r.id;
  end loop;
  -- 11-02 TOR 의 SO 열쇠 하나를 1 센트 적게 보낸 것으로
  update public.qbo_cost_sent t set cents = t.cents - 1 where t.id = (select t2.id from public.qbo_cost_sent t2 join public.qbo_cost_sheet s on s.id = t2.sheet_id where s.sheet_date = '2026-11-02' and t2.wh = 'TOR' and t2.key_kind = 'SO' and t2.acct_a = '_58_' order by t2.doc_key limit 1);
end $$;
select (select t.doc_key from public.qbo_cost_sent t join public.qbo_cost_sheet s on s.id = t.sheet_id where s.sheet_date = '2026-11-02' and t.wh = 'TOR' and t.key_kind = 'SO' and t.acct_a = '_58_' order by t.doc_key limit 1) as tweak_key \gset
select pg_temp.chk('D1 11-03 TOR 셈: baseline sent · 그 열쇠 차액 +1 센트 · label 「<SO> (adj. of 2026-11-02)」 · 다른 11-02 열쇠 0',
  (select min(c.baseline) || ' ' || coalesce(max(c.diff_cents::text) filter (where c.doc_key = :'tweak_key'), '-') || ' ' || coalesce(max(c.label) filter (where c.doc_key = :'tweak_key'), '-') || ' ' || count(*) filter (where c.first_sent_on = '2026-11-02' and c.doc_key <> :'tweak_key')::text from public.qbo_cost_sheet_calc(date '2026-11-03', 'TOR', :'realm') c where c.status = 'send'),
  'sent 1 ' || :'tweak_key' || ' (adj. of 2026-11-02) 0');
select pg_temp.chk('D2 보낸 열쇠의 first_sent_on · sent_cents 가 셈에 실린다(11-02 열쇠 = 기대 − 1)', (select (c.expected_cents - c.sent_cents)::text || ' ' || c.first_sent_on::text from public.qbo_cost_sheet_calc(date '2026-11-03', 'TOR', :'realm') c where c.doc_key = :'tweak_key' and c.acct_a = '_58_'), '1 2026-11-02');
select pg_temp.chk('D3 늦게 적은 과거 사건 꼴: 보낸 장(11-02)의 열쇠가 기대에서 사라지면(보낸 몫만 남음) 다음 장에 음수 차액 → 차대 뒤집힘(Credit #58)',
  (with x as (select c.diff_cents, c.label from public.qbo_cost_sheet_calc(date '2026-11-03', 'TOR', :'realm') c where c.doc_key = :'tweak_key' and c.acct_a = '_58_')
   select (diff_cents > 0)::text from x), 'true');
select pg_temp.chk('D4 EDM 은 무영향(TOR 보낸 몫은 창고 열쇠) · EDM 11-03 baseline 그대로 pending:2026-11-02', (select min(c.baseline) from public.qbo_cost_sheet_calc(date '2026-11-03', 'EDM', :'realm') c), 'pending:2026-11-02');

-- ── H 보류 결정(1099 · 이견 6 · 10: 문턱을 트랜잭션 안에서 100 으로 · 가짜 조정 없음) ──
update public.inv_config set value = '100' where key = 'qbo_cost_adjust_hold_over';
-- 문턱 넘는 ADJ = 사건 Σ|금액|(레이어 들어옴 + adjust_out 나감 · 10-31 ~ 11-06) > 100 이면서 짝 순액이 0 이 아닌 것(순액 0 은 줄이 없다 · ADJ-00018 꼴)
select string_agg(x.k, ',' order by x.k) as over100 from (
  select d.k, sum(d.a) as tot from (select l.doc_number as k, l.qty * l.unit_cost as a from public.inv_layer l where l.origin_type like 'adjust_%' and l.received_on between '2026-10-31' and '2026-11-06'
                                     union all select c.doc_number, c.amount from public.inv_layer_consume c where c.reason = 'adjust_out' and c.occurred_on between '2026-10-31' and '2026-11-06') d group by d.k) x
  where x.tot > 100 and exists (select 1 from t_exp e where e.doc_key = x.k and e.key_kind = 'ADJ') \gset
\echo '   (문턱 100 을 넘고 줄이 있는 ADJ:' :over100 ')'
select pg_temp.chk('H1 문턱 100 → 넘는 ADJ 전부 보류(ADJ-00011 359.05 · 00098 234.22 · 00035 178.26 · …) · 까닭 글',
  (select string_agg(distinct e.doc_key, ',' order by e.doc_key) from public.qbo_cost_expected(date '2026-11-06', null, :'realm') e where e.status = 'hold' and e.key_kind = 'ADJ') || ' ' || (select (min(e.reason) ~ '^adjustment ADJ-00011 totals 359\.05 over the 100 threshold — decide send / never first \(1099\)$')::text from public.qbo_cost_expected(date '2026-11-06', null, :'realm') e where e.doc_key = 'ADJ-00011' and e.status = 'hold'), :'over100' || ' true');
select pg_temp.as_user(:'st_uid');
select pg_temp.chk('H2a 결정 창구 거부: RCV · note 없음 · 모르는 ADJ',
  (pg_temp.try($q$select public.qbo_cost_hold_decide('RCV', 'RCV-00117', 'send', 'x')::text$q$) ~ 'Only an inventory adjustment')::text || ' ' || (pg_temp.try($q$select public.qbo_cost_hold_decide('ADJ', 'ADJ-00035', 'send')::text$q$) ~ 'note is required')::text || ' ' || (pg_temp.try($q$select public.qbo_cost_hold_decide('ADJ', 'ADJ-99999', 'send', 'x')::text$q$) ~ 'does not exist')::text, 'true true true');
select public.qbo_cost_hold_decide('ADJ', 'ADJ-00035', 'send', 'ZZ test: real count')->>'decision' as h_send \gset
select public.qbo_cost_hold_decide('ADJ', 'ADJ-00098', 'never', 'ZZ test: write-off')->>'decision' as h_never \gset
select pg_temp.chk('H2b send → 그 ADJ 상태 send · never → excluded(결정은 다음 문장에서 보인다 — 같은 문장은 시작 스냅샷)',
  :'h_send' || ':' || (select string_agg(distinct e.status, ',') from public.qbo_cost_expected(date '2026-11-06', null, :'realm') e where e.doc_key = 'ADJ-00035') || ' ' || :'h_never' || ':' || (select string_agg(distinct e.status, ',') from public.qbo_cost_expected(date '2026-11-06', null, :'realm') e where e.doc_key = 'ADJ-00098'), 'send:send never:excluded');
select pg_temp.chk('H3 hold_list: 보류 열쇠에 RCV 둘(결정 안 받음) + 문턱 ADJ(결정 받음) = 넘는 수 − 결정 둘 · decisions 2', (select (select count(*) from jsonb_array_elements(h->'holds') x where x->>'key_kind' = 'RCV' and not (x->>'takes_decision')::boolean)::text || ' ' || (select count(distinct x->>'doc_key') from jsonb_array_elements(h->'holds') x where x->>'key_kind' = 'ADJ' and (x->>'takes_decision')::boolean)::text || ' ' || jsonb_array_length(h->'decisions')::text from public.qbo_cost_hold_list() h), '2 ' || (array_length(string_to_array(:'over100', ','), 1) - 2)::text || ' 2');
select coalesce(public.qbo_cost_hold_decide('ADJ', 'ADJ-00098', null)->>'removed', '-') as h_rm \gset
select pg_temp.chk('H3b 결정 지움(null) → removed 1 · 다시 hold', :'h_rm' || ':' || (select string_agg(distinct e.status, ',') from public.qbo_cost_expected(date '2026-11-06', null, :'realm') e where e.doc_key = 'ADJ-00098'), '1:hold');
select pg_temp.chk('H4 이미 일부 보낸 조정은 never 불가(10-31 TOR 는 sent · ADJ-00011 은 10-31 TOR 장에 있다)', (pg_temp.try($q$select public.qbo_cost_hold_decide('ADJ', 'ADJ-00011', 'never', 'x')::text$q$) ~ 'already went to QuickBooks in part')::text, 'true');
reset role;
select set_config('request.jwt.claims', '', true);
update public.inv_config set value = '1000' where key = 'qbo_cost_adjust_hold_over';
delete from public.qbo_cost_hold where note like 'ZZ test%';

-- ── M 월 검산(1086 · 이견 12) ──
select pg_temp.as_user(:'st_uid');
select public.qbo_cost_month(date '2026-11-01', 'TOR') as m_tor, public.qbo_cost_month(date '2026-11-01', null) as m_all, public.qbo_cost_month(date '2026-10-01', 'EDM') as m_oct \gset
select pg_temp.chk('M1 11 월 TOR: residual 0.00 · sent = 10-31 + 11-02 TOR 재고 쪽(보낸 몫) · in_flight 0 · hold 12,989.53 · excluded = 살린 트럭 TOR 몫 0(도착은 EDM) + opening_fix TOR 몫 · blocks 0',
  (:'m_tor'::jsonb->'inventory'->>'residual') || ' ' || (:'m_tor'::jsonb->'inventory'->>'in_flight') || ' ' || (:'m_tor'::jsonb->'inventory'->>'hold') || ' ' || (:'m_tor'::jsonb->'counts'->>'blocks') || ' ' || ((:'m_tor'::jsonb->'inventory'->>'sent')::numeric <> 0)::text, '0.00 0.00 12989.53 0 true');
select pg_temp.chk('M2 11 월 둘 다: residual 0.00 · so_count 264 · ims_cogs = sale − restock + reversal 꼴(126,715.43 − 1,705.94 + 429.19 + 상계 → 125,438.68) · cogs 반올림 |≤ 0.20|',
  (:'m_all'::jsonb->'inventory'->>'residual') || ' ' || (:'m_all'::jsonb->'cogs'->>'so_count') || ' ' || (:'m_all'::jsonb->'cogs'->>'ims_cogs') || ' ' || (abs((:'m_all'::jsonb->'cogs'->>'rounding')::numeric) <= 0.20)::text, '0.00 264 125438.68 true');
select pg_temp.chk('M3 10 월 EDM(10-31 하루 · since 바닥): residual 0.00 · ims_delta = 조정 양방향 −32.79(들어옴 − 나감 · 원금 32.786902) · sheets pending 1', (:'m_oct'::jsonb->'inventory'->>'residual') || ' ' || (:'m_oct'::jsonb->'inventory'->>'ims_delta') || ' ' || (:'m_oct'::jsonb->'counts'->'sheets'->>'pending'), '0.00 -32.79 1');
select pg_temp.chk('M4 장 목록: 12 행 · counts sent 2 · pending 10 · since · 스위치 off', (select (l->>'since') || ' ' || (l->>'send_enabled') || ' ' || jsonb_array_length(l->'rows')::text || ' ' || (l->'counts'->>'sent') || ' ' || (l->'counts'->>'pending') from public.qbo_cost_sheet_list(null, null, null, null) l), '2026-10-31 off 12 2 10');
reset role;
select set_config('request.jwt.claims', '', true);

-- ── K 판정 572 · 열쇠 문 ──
select pg_temp.as_user(:'st_uid');
select pg_temp.chk('K1 ims_config_set(새 키 셋) → not changed from the app', (pg_temp.try($q$select public.ims_config_set('qbo_send_cost_enabled', 'on', 'off')::text$q$) ~ 'not changed from the app')::text || ' ' || (pg_temp.try($q$select public.ims_config_set('qbo_cost_adjust_hold_over', '5', '1000')::text$q$) ~ 'not changed from the app')::text || ' ' || (pg_temp.try($q$select public.ims_config_set('qbo_cost_since', '2026-01-01', '2026-10-31')::text$q$) ~ 'not changed from the app')::text, 'true true true');
reset role;
select set_config('request.jwt.claims', '', true);
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'zz-qbo-sync-3-2a-nokey@test.invalid', 'ZZ qbo-sync-3-2a no key', 'worker', '["ims"]', '{}') returning auth_user_id::text as nk_uid \gset
select pg_temp.as_user(:'nk_uid');
select pg_temp.chk('K2 열쇠 없는 직원: 미리 보기 · 목록 · 결정 · 월 · build_now 모두 거부(qbo 열쇠)', (pg_temp.try($q$select public.qbo_cost_preview(date '2026-11-02', 'TOR')::text$q$) ~ 'does not have the ''qbo''')::text || (pg_temp.try($q$select public.qbo_cost_sheet_list()::text$q$) ~ 'does not have the ''qbo''')::text || (pg_temp.try($q$select public.qbo_cost_hold_decide('ADJ', 'ADJ-00011', 'send', 'x')::text$q$) ~ 'does not have the ''qbo''')::text || (pg_temp.try($q$select public.qbo_cost_month(date '2026-11-01')::text$q$) ~ 'does not have the ''qbo''')::text || (pg_temp.try($q$select public.qbo_cost_build_now()::text$q$) ~ 'does not have the ''qbo''')::text, 'truetruetruetruetrue');
reset role;
select set_config('request.jwt.claims', '', true);

-- ── W WHERE 정적(REST 두 겹 ①) · G grant ──
select pg_temp.chk('W1 새 함수 15 — 깊이 0 WHERE 없는 update · delete 0',
  (select string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc)::text, ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'qbo_cost_%'),
  'qbo_cost_build_now 0 · qbo_cost_charge_account 0 · qbo_cost_excluded_docs 0 · qbo_cost_expected 0 · qbo_cost_hold_decide 0 · qbo_cost_hold_list 0 · qbo_cost_layer_wh 0 · qbo_cost_month 0 · qbo_cost_preview 0 · qbo_cost_sheet_build 0 · qbo_cost_sheet_build_due 0 · qbo_cost_sheet_calc 0 · qbo_cost_sheet_list 0 · qbo_cost_wh_code 0 · qbo_cost_wh_name 0');
select pg_temp.chk('G1 grant: 열쇠 창구 여섯 authenticated+service · 속 넷 service 만 · build_due grant 0 · 상수 넷 열림',
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '(default)'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_cost_preview', 'qbo_cost_expected', 'qbo_cost_sheet_build_due', 'qbo_cost_wh_code')),
  'qbo_cost_expected:{postgres=X/postgres,service_role=X/postgres} qbo_cost_preview:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} qbo_cost_sheet_build_due:{postgres=X/postgres} qbo_cost_wh_code:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}');
select pg_temp.chk('G2 원가 표 · 원장 무접촉: inv_layer · consume · cost_add 행 수 · min id 그대로', (select count(*) from public.inv_layer)::text || ' ' || (select count(*) from public.inv_layer_consume)::text || ' ' || (select count(*) from public.inv_layer_cost_add)::text || ' ' || (select min(id) from public.inv_layer_consume)::text, :'pre_layer' || ' ' || :'pre_cons' || ' ' || :'pre_add' || ' ' || :'pre_epoch');

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, 44 as expect_total from t_res;
select 'FAIL ' || label || format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) as fail_line from t_res where not ok order by n;
rollback;
select (select count(*) from public.ims_staff) = :pre_staff and (select count(*) from public.inv_config) = :pre_cfg and not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'qbo_cost_sheet' and :{?mig}) as rolled_back_clean;
