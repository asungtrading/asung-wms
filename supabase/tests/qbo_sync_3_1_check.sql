-- supabase/tests/qbo_sync_3_1_check.sql — qbo-sync-3-1 검증 (2026-11-08 밤 · 판정 1087 · 1088 · 1091 · deferred 499 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → S 구조 · D 데이터(11 · 3 · 어긋남 0 · updated_by 보존) · B 트리거(거부 · 함께 바꾸면 통과 · deferred 다시 읽기) · R 창구 넷(통화별 기본 · block · 함께 바꾸면 통과) · A 조정 해석(45 · 직접 고른 계정 · 기본 없음) · K 572 거부 · W WHERE 정적 → rollback → Z
--   Claude Code(시험 · 레포 루트): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261108150000_qbo_sync_3_1_account_currency.sql -f supabase/tests/qbo_sync_3_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — D1 · D2 의 「고친 수」 기대가 11 · 3 → 0 · 0 으로 바뀌는 것 말고는 같다
--   ⚠️ 공개 레포 — 상호를 찍지 않는다(id · 수만) · 가짜 행 이름은 「ZZ qbo-sync-3-1 …」 · 시퀀스는 안 나간다(uuid 표만 · 조정은 insert 안 함 · draft 한 건의 계정 칸만 트랜잭션 안에서 바꿔 본다)
--   ⚠️ 트리거는 deferred — 여기서는 try(…, fire) 가 set constraints all immediate 로 발화시킨다 · RPC 시험은 먼저 deferred 로 돌려 놓고 부른다(PostgREST 와 같은 조건)
\set ON_ERROR_STOP on
\pset pager off
select (select value from public.inv_config where key = 'db_role') as db_role;
select (select id from public.ref_currency where code = 'CAD')::text as cad, (select id from public.ref_currency where code = 'USD')::text as usd,
       (select id from public.ref_account where code = '_62_')::text as a62, (select id from public.ref_account where code = '_109_')::text as a109,
       (select id from public.ref_account where code = '_61_')::text as a61, (select id from public.ref_account where code = '_212_')::text as a212,
       (select id from public.ref_account where code = '_1150040010_')::text as adisc \gset
\if :{?mig}
\set want_fix_s 11
\set want_fix_c 3
\else
\set want_fix_s 0
\set want_fix_c 0
\endif

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns text language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
  return case when p_got is not distinct from p_want then 'OK   ' else 'FAIL ' end || p_label || case when p_got is not distinct from p_want then '' else format(' — got %s · want %s', coalesce(p_got, '(null)'), coalesce(p_want, '(null)')) end;
end $$;
-- try: 서브트랜잭션에서 돌리고 결과(또는 오류)를 글로 — p_fire 면 끝에 deferred 트리거를 발화시킨다 · 늘 deferred 로 시작(PostgREST 조건)
create function pg_temp.try(p_sql text, p_fire boolean default true) returns text language plpgsql as $$
declare v text;
begin
  set constraints all deferred;
  execute p_sql into v;
  if p_fire then set constraints all immediate; set constraints all deferred; end if;
  return coalesce(v, '(null)');
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- run: INTO 없이(문장 여럿) — 통과면 (ok)
create function pg_temp.run(p_sql text, p_fire boolean default true) returns text language plpgsql as $$
begin
  set constraints all deferred;
  execute p_sql;
  if p_fire then set constraints all immediate; set constraints all deferred; end if;
  return '(ok)';
exception when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.as_user(p_uid text, p_role text default 'authenticated') returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', p_role)::text, true);
$$;
-- safeupdate 규칙 정적 스캐너(qbo_1c_check 의 것 그대로)
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
-- 가짜 공급처 · 손님 넣기(상호 없음 · 트랜잭션 안 · rollback)
create function pg_temp.mk_supplier(p_name text, p_cur uuid, p_acct uuid) returns text language plpgsql as $$
declare v uuid;
begin
  insert into public.supplier (name, source, is_active, payment_term_name, account_payable_id, account_payable_code, currency_id)
  values (p_name, 'manual', true, 'Due on receipt', p_acct, (select code from public.ref_account where id = p_acct), p_cur) returning id into v;
  return v::text;
end $$;
create function pg_temp.mk_customer(p_name text, p_cur uuid, p_acct uuid) returns text language plpgsql as $$
declare v uuid;
begin
  insert into public.customer (name, source, is_active, currency_id, currency_code, ar_account_id, ar_account_code)
  values (p_name, 'manual', true, p_cur, (select code from public.ref_currency where id = p_cur), p_acct, (select code from public.ref_account where id = p_acct)) returning id into v;
  return v::text;
end $$;

begin;
-- ── 기준(begin 안 · \i 앞) ──
select (select count(*) from public.supplier s where s.currency_id = :'cad'::uuid and s.account_payable_code = '_109_') as pre_cad109,
       (select count(*) from public.customer c where c.currency_id = :'usd'::uuid and c.ar_account_code = '_61_') as pre_usd61,
       (select count(*) from public.supplier where updated_by is not null) as pre_s_by, (select count(*) from public.customer where updated_by is not null) as pre_c_by,
       (select count(*) from public.supplier) as pre_s_n, (select count(*) from public.customer) as pre_c_n, (select count(*) from public.inv_adjust) as pre_adj_n,
       (select count(*) from public.inv_adjust where status = 'confirmed') as pre_adj_conf, (select count(*) from public.ims_staff) as pre_staff \gset
\echo '── 기준: CAD·_109_' :pre_cad109 '· USD·_61_' :pre_usd61 '· supplier' :pre_s_n '(updated_by' :pre_s_by ') · customer' :pre_c_n '(updated_by' :pre_c_by ') · inv_adjust' :pre_adj_n '(confirmed' :pre_adj_conf ') · staff' :pre_staff
\if :{?mig}
\echo '── 시험 적용:' :mig
\i :mig
\endif

-- ── S 구조 ──
select pg_temp.chk('S1 ref_account.currency_code 채움 셋(_109_ USD · _203_ KRW · _212_ USD) · 나머지 null',
  (select string_agg(code || '=' || currency_code, ' ' order by code) from public.ref_account where currency_code is not null), '_109_=USD _203_=KRW _212_=USD');
select pg_temp.chk('S2 inv_config 키 다섯',
  (select string_agg(key || '=' || value, ' ' order by key) from public.inv_config where key in ('inv_adjust_default_account_code', 'supplier_default_account_payable_code_cad', 'supplier_default_account_payable_code_usd', 'customer_default_ar_account_code_cad', 'customer_default_ar_account_code_usd')),
  'customer_default_ar_account_code_cad=_61_ customer_default_ar_account_code_usd=_212_ inv_adjust_default_account_code=_1150040010_ supplier_default_account_payable_code_cad=_62_ supplier_default_account_payable_code_usd=_109_');
select pg_temp.chk('S3 옛 키 둘 값 무변(폴백)', (select string_agg(key || '=' || value, ' ' order by key) from public.inv_config where key in ('supplier_default_account_payable_code', 'customer_default_ar_account_code')), 'customer_default_ar_account_code=_61_ supplier_default_account_payable_code=_109_');
select pg_temp.chk('S4 트리거 둘 deferrable initially deferred · AFTER · 행마다',
  (select string_agg(t.tgname || ':' || t.tgdeferrable::text || t.tginitdeferred::text, ' ' order by t.tgname) from pg_trigger t where t.tgname in ('supplier_account_currency_ck', 'customer_account_currency_ck')), 'customer_account_currency_ck:truetrue supplier_account_currency_ck:truetrue');
select pg_temp.chk('S5 ims_account_currency: _62_ CAD · _109_ USD · _212_ USD · _61_ CAD · 모르는 id null',
  public.ims_account_currency(:'a62'::uuid) || ' ' || public.ims_account_currency(:'a109'::uuid) || ' ' || public.ims_account_currency(:'a212'::uuid) || ' ' || public.ims_account_currency(:'a61'::uuid) || ' ' || coalesce(public.ims_account_currency(gen_random_uuid()), 'null'), 'CAD USD USD CAD null');
select pg_temp.chk('S6 거부 글 꼴(빠져나오는 길 같은 줄)', public.ims_account_currency_msg('Supplier', 'X', 'payable', '_109_', 'USD', 'CAD'),
  'Supplier X: payable account _109_ is in USD but the supplier currency is CAD — change the currency and the account together in one save, or pick a CAD payable account — nothing was saved');

-- ── D 데이터 ──
select pg_temp.chk('D1 CAD 공급처 중 A/P _109_ = 0 · 고친 수 = ' || :'want_fix_s',
  (select count(*) from public.supplier s where s.currency_id = :'cad'::uuid and s.account_payable_code = '_109_')::text || ' ' || (:pre_cad109 - (select count(*) from public.supplier s where s.currency_id = :'cad'::uuid and s.account_payable_code = '_109_'))::text, '0 ' || :'want_fix_s');
select pg_temp.chk('D2 USD 손님 중 A/R _61_ = 0 · 고친 수 = ' || :'want_fix_c',
  (select count(*) from public.customer c where c.currency_id = :'usd'::uuid and c.ar_account_code = '_61_')::text || ' ' || (:pre_usd61 - (select count(*) from public.customer c where c.currency_id = :'usd'::uuid and c.ar_account_code = '_61_'))::text, '0 ' || :'want_fix_c');
select pg_temp.chk('D3 고친 뒤 어긋남 0(공급처 · 손님) · id ↔ code 짝 어긋남 0',
  (select count(*) from public.supplier s join public.ref_currency r on r.id = s.currency_id where s.account_payable_id is not null and public.ims_account_currency(s.account_payable_id) <> r.code)::text || ' '
  || (select count(*) from public.customer c where c.ar_account_id is not null and public.ims_account_currency(c.ar_account_id) <> coalesce((select r.code from public.ref_currency r where r.id = c.currency_id), c.currency_code))::text || ' '
  || (select count(*) from public.supplier s join public.ref_account a on a.id = s.account_payable_id where a.code <> s.account_payable_code)::text || ' '
  || (select count(*) from public.customer c join public.ref_account a on a.id = c.ar_account_id where a.code <> c.ar_account_code)::text, '0 0 0 0');
select pg_temp.chk('D4 updated_by 보존(touch 끔) · 행 수 무변',
  (select count(*) from public.supplier where updated_by is not null)::text || ' ' || (select count(*) from public.customer where updated_by is not null)::text || ' ' || (select count(*) from public.supplier)::text || ' ' || (select count(*) from public.customer)::text,
  :'pre_s_by' || ' ' || :'pre_c_by' || ' ' || :'pre_s_n' || ' ' || :'pre_c_n');
select pg_temp.chk('D5 CAD 공급처의 A/P 는 전부 _62_ · USD 공급처는 전부 _109_',
  (select string_agg(r.code || ':' || s.account_payable_code, ' ' order by r.code, s.account_payable_code) from (select distinct s.currency_id, s.account_payable_code from public.supplier s) s join public.ref_currency r on r.id = s.currency_id), 'CAD:_62_ USD:_109_');

-- ── B 트리거(표 직접 — 적재 REST 와 같은 길) ──
select pg_temp.try(format('select pg_temp.mk_supplier(%L, %L, %L)', 'ZZ qbo-sync-3-1 bad supplier', :'cad', :'a109')) as b1 \gset
select pg_temp.chk('B1 insert CAD 공급처 + A/P _109_ → 거부(P0001 · 글에 USD/CAD · 빠져나오는 길)', (:'b1' ~ '^ERR P0001: Supplier ZZ qbo-sync-3-1 bad supplier: payable account _109_ is in USD but the supplier currency is CAD — change the currency and the account together in one save, or pick a CAD payable account — nothing was saved$')::text, 'true');
select pg_temp.try(format('select pg_temp.mk_supplier(%L, %L, %L)', 'ZZ qbo-sync-3-1 supplier', :'cad', :'a62')) as fs \gset
select pg_temp.chk('B2 insert CAD + _62_ → 통과', (:'fs' !~ '^ERR')::text, 'true');
select pg_temp.chk('B3 update 통화만 USD → 거부', (pg_temp.try(format('update public.supplier set currency_id = %L where id = %L returning id::text', :'usd', :'fs')) ~ '^ERR P0001: Supplier ZZ qbo-sync-3-1 supplier: payable account _62_ is in CAD but the supplier currency is USD — change the currency and the account together in one save, or pick a USD payable account — nothing was saved$')::text, 'true');
select pg_temp.chk('B4 update 통화 + 계정 한 UPDATE → 통과 · 행 USD/_109_', pg_temp.try(format('update public.supplier set currency_id = %L, account_payable_id = %L, account_payable_code = ''_109_'' where id = %L returning account_payable_code', :'usd', :'a109', :'fs')), '_109_');
select pg_temp.run(format('update public.supplier set currency_id = %L where id = %L; update public.supplier set account_payable_id = %L, account_payable_code = ''_62_'' where id = %L', :'cad', :'fs', :'a62', :'fs')) as b5 \gset
select pg_temp.chk('B5 deferred 다시 읽기: 통화 UPDATE → 계정 UPDATE 따로(한 트랜잭션) → 발화 때 통과 · 행 CAD/_62_',
  :'b5' || ' ' || (select r.code || '/' || s.account_payable_code from public.supplier s join public.ref_currency r on r.id = s.currency_id where s.id = :'fs'::uuid), '(ok) CAD/_62_');   -- 상태는 다른 문장에서(같은 문장의 서브쿼리는 문장 시작 스냅샷)
select pg_temp.chk('B6 통화 null 이면 통과(비교할 것 없음) · 되돌리면 통과', pg_temp.try(format('update public.supplier set currency_id = null where id = %L returning 1::text', :'fs')) || ' ' || pg_temp.try(format('update public.supplier set currency_id = %L where id = %L returning 1::text', :'cad', :'fs')), '1 1');
select pg_temp.try(format('select pg_temp.mk_customer(%L, %L, %L)', 'ZZ qbo-sync-3-1 bad customer', :'usd', :'a61')) as c1 \gset
select pg_temp.chk('C1 insert USD 손님 + A/R _61_ → 거부', (:'c1' ~ '^ERR P0001: Customer ZZ qbo-sync-3-1 bad customer: receivable account _61_ is in CAD but the customer currency is USD — change the currency and the account together in one save, or pick a USD receivable account — nothing was saved$')::text, 'true');
select pg_temp.try(format('select pg_temp.mk_customer(%L, %L, %L)', 'ZZ qbo-sync-3-1 customer', :'usd', :'a212')) as fc \gset
select pg_temp.chk('C2 insert USD + _212_ → 통과', (:'fc' !~ '^ERR')::text, 'true');
select pg_temp.chk('C3 update 통화만 CAD(currency_id · currency_code 함께) → 거부', (pg_temp.try(format('update public.customer set currency_id = %L, currency_code = ''CAD'' where id = %L returning id::text', :'cad', :'fc')) ~ '^ERR P0001: Customer ZZ qbo-sync-3-1 customer: receivable account _212_ is in USD but the customer currency is CAD — change the currency and the account together in one save, or pick a CAD receivable account — nothing was saved$')::text, 'true');
select pg_temp.chk('C4 update 통화 + A/R 한 UPDATE → 통과 · 행 CAD/_61_', pg_temp.try(format('update public.customer set currency_id = %L, currency_code = ''CAD'', ar_account_id = %L, ar_account_code = ''_61_'' where id = %L returning currency_code || ''/'' || ar_account_code', :'cad', :'a61', :'fc')), 'CAD/_61_');
select pg_temp.chk('C5 A/R null 이면 통과 · 되돌리기(USD/_212_) 통과', pg_temp.try(format('update public.customer set ar_account_id = null, ar_account_code = null where id = %L returning 1::text', :'fc')) || ' ' || pg_temp.try(format('update public.customer set currency_id = %L, currency_code = ''USD'', ar_account_id = %L, ar_account_code = ''_212_'' where id = %L returning 1::text', :'usd', :'a212', :'fc')), '1 1');

-- ── R 창구 넷(가짜 master 직원 · 이름표만 · rollback) ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'zz-qbo-sync-3-1@test.invalid', 'ZZ qbo-sync-3-1 master', 'manager', '["ims", "master", "purchasing", "sales"]', '{}') returning auth_user_id::text as st_uid \gset
select pg_temp.as_user(:'st_uid');
set constraints all deferred;
select public.supplier_create(jsonb_build_object('name', 'ZZ qbo-sync-3-1 create cad', 'currency_id', :'cad'), true, '{}') as r1 \gset
select pg_temp.chk('R1 supplier_create CAD(계정 안 줌) → committed · 기본 account_payable → _62_', (:'r1'::jsonb->>'committed') || ' ' || (select account_payable_code from public.supplier where id = (:'r1'::jsonb->>'supplier_id')::uuid) || ' ' || ((:'r1'::jsonb->'defaults_used') ? 'account_payable')::text, 'true _62_ true');
select public.supplier_create(jsonb_build_object('name', 'ZZ qbo-sync-3-1 create usd', 'currency_id', :'usd'), true, '{}') as r2 \gset
select pg_temp.chk('R2 supplier_create USD → _109_', (:'r2'::jsonb->>'committed') || ' ' || (select account_payable_code from public.supplier where id = (:'r2'::jsonb->>'supplier_id')::uuid), 'true _109_');
select public.supplier_create(jsonb_build_object('name', 'ZZ qbo-sync-3-1 create none'), true, '{}') as r2b \gset
select pg_temp.chk('R2b supplier_create 통화도 안 줌 → 기본 통화 USD · _109_', (:'r2b'::jsonb->>'committed') || ' ' || (select r.code || '/' || s.account_payable_code from public.supplier s join public.ref_currency r on r.id = s.currency_id where s.id = (:'r2b'::jsonb->>'supplier_id')::uuid), 'true USD/_109_');
select public.supplier_create(jsonb_build_object('name', 'ZZ qbo-sync-3-1 create bad', 'currency_id', :'cad', 'account_payable_id', :'a109'), true, '{}') as r3 \gset
select pg_temp.chk('R3 supplier_create CAD + _109_ → block currency_account_mismatch(warn 아님) · 글', (:'r3'::jsonb->>'committed') || ' ' || (:'r3'::jsonb->'blocks'->0->>'code') || ' ' || jsonb_array_length(:'r3'::jsonb->'warnings')::text || ' ' || ((:'r3'::jsonb->'blocks'->0->>'message') = 'Supplier ZZ qbo-sync-3-1 create bad: payable account _109_ is in USD but the supplier currency is CAD — change the currency and the account together in one save, or pick a CAD payable account — nothing was saved')::text, 'false currency_account_mismatch 0 true');
select pg_temp.run(format('update public.supplier set currency_id = %L, account_payable_id = %L, account_payable_code = ''_62_'' where id = %L', :'cad', :'a62', :'fs')) as st_s \gset
\echo '   (가짜 공급처를 CAD/_62_ 로 맞춤:' :st_s ')'
select public.supplier_update(jsonb_build_array(jsonb_build_object('supplier_id', :'fs', 'op', 'set', 'field', 'currency_id', 'value', :'usd', 'old', :'cad')), true, '{}') as r4 \gset
select pg_temp.chk('R4 supplier_update 통화만 USD → block currency_account_mismatch · 글자 추론 warn 없음', (:'r4'::jsonb->>'committed') || ' ' || (select string_agg(b->>'code', ',') from jsonb_array_elements(:'r4'::jsonb->'blocks') b) || ' ' || (select count(*) from jsonb_array_elements(:'r4'::jsonb->'warnings') w where w->>'code' = 'currency_account_mismatch')::text, 'false currency_account_mismatch 0');
select pg_temp.try(format('select public.supplier_update(jsonb_build_array(jsonb_build_object(''supplier_id'', %L, ''op'', ''set'', ''field'', ''currency_id'', ''value'', %L, ''old'', %L), jsonb_build_object(''supplier_id'', %L, ''op'', ''set'', ''field'', ''account_payable_id'', ''value'', %L, ''old'', %L)), true, ''{}'')::text', :'fs', :'usd', :'cad', :'fs', :'a109', :'a62')) as r5 \gset
select pg_temp.chk('R5 supplier_update 통화 + 계정 한 호출 → committed · 발화 때 통과 · 행 USD/_109_', (:'r5' !~ '^ERR')::text || ' ' || (:'r5'::jsonb->>'committed') || ' ' || (select r.code || '/' || s.account_payable_code from public.supplier s join public.ref_currency r on r.id = s.currency_id where s.id = :'fs'::uuid), 'true true USD/_109_');
select public.customer_create(jsonb_build_object('name', 'ZZ qbo-sync-3-1 cust usd', 'currency_id', :'usd'), true, '{tier_currency_mismatch,shipping_address_missing,billing_address_missing}') as r6 \gset
select pg_temp.chk('R6 customer_create USD → 기본 A/R _212_', (:'r6'::jsonb->>'committed') || ' ' || (select ar_account_code from public.customer where id = (:'r6'::jsonb->>'customer_id')::uuid), 'true _212_');
select public.customer_create(jsonb_build_object('name', 'ZZ qbo-sync-3-1 cust cad'), true, '{shipping_address_missing,billing_address_missing}') as r7 \gset
select pg_temp.chk('R7 customer_create 통화 안 줌(기본 CAD) → _61_', (:'r7'::jsonb->>'committed') || ' ' || (select currency_code || '/' || ar_account_code from public.customer where id = (:'r7'::jsonb->>'customer_id')::uuid), 'true CAD/_61_');
select public.customer_create(jsonb_build_object('name', 'ZZ qbo-sync-3-1 cust bad', 'currency_id', :'usd', 'ar_account_id', :'a61'), true, '{}') as r8 \gset
select pg_temp.chk('R8 customer_create USD + _61_ → block currency_account_mismatch', (:'r8'::jsonb->>'committed') || ' ' || (select string_agg(b->>'code', ',') from jsonb_array_elements(:'r8'::jsonb->'blocks') b), 'false currency_account_mismatch');
select pg_temp.run(format('update public.customer set currency_id = %L, currency_code = ''USD'', ar_account_id = %L, ar_account_code = ''_212_'' where id = %L', :'usd', :'a212', :'fc')) as st_c \gset
\echo '   (가짜 손님을 USD/_212_ 로 맞춤:' :st_c ')'
select public.customer_update(jsonb_build_array(jsonb_build_object('customer_id', :'fc', 'op', 'set', 'field', 'currency_id', 'value', :'cad', 'old', :'usd')), true, '{}') as r9 \gset
select pg_temp.chk('R9 customer_update 통화만 CAD → block currency_account_mismatch', (:'r9'::jsonb->>'committed') || ' ' || (select string_agg(b->>'code', ',') from jsonb_array_elements(:'r9'::jsonb->'blocks') b), 'false currency_account_mismatch');
select pg_temp.try(format('select public.customer_update(jsonb_build_array(jsonb_build_object(''customer_id'', %L, ''op'', ''set'', ''field'', ''currency_id'', ''value'', %L, ''old'', %L), jsonb_build_object(''customer_id'', %L, ''op'', ''set'', ''field'', ''ar_account_id'', ''value'', %L, ''old'', %L)), true, ''{}'')::text', :'fc', :'cad', :'usd', :'fc', :'a61', :'a212')) as r10 \gset
select pg_temp.chk('R10 customer_update 통화 + A/R 한 호출 → committed · 발화 때 통과 · 행 CAD/_61_', (:'r10' !~ '^ERR')::text || ' ' || (:'r10'::jsonb->>'committed') || ' ' || (select currency_code || '/' || ar_account_code from public.customer where id = :'fc'::uuid), 'true true CAD/_61_');

-- ── A 조정 해석 ──
select pg_temp.chk('A1 모든 조정(' || :'pre_adj_n' || ' · confirmed ' || :'pre_adj_conf' || ') → 기본 _1150040010_ · is_default · id 짝',
  (select count(*) from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) x where x.account_code = '_1150040010_' and x.is_default and x.account_id = :'adisc'::uuid)::text || ' ' || (select count(*) from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) x where a.status = 'confirmed')::text, :'pre_adj_n' || ' ' || :'pre_adj_conf');
select (select id::text from public.inv_adjust where status = 'draft' order by created_at limit 1) as adj1 \gset
update public.inv_adjust set account_id = :'a62'::uuid, account_code = '_62_' where id = :'adj1'::uuid;
select pg_temp.chk('A2 계정을 고른 조정 → 그 값 · is_default false', (select x.account_code || ' ' || x.is_default::text || ' ' || (x.account_id = :'a62'::uuid)::text from public.inv_adjust_account(:'adj1'::uuid) x), '_62_ false true');
select pg_temp.chk('A3 모르는 조정 → 오류', (pg_temp.try(format('select account_code from public.inv_adjust_account(%L)', gen_random_uuid()::text)) ~ '^ERR P0001: Adjustment [0-9a-f-]{36} does not exist \(or you cannot read it\) — nothing was read$')::text, 'true');
update public.inv_config set value = '' where key = 'inv_adjust_default_account_code';
select pg_temp.chk('A4 기본 키 비면 → 오류(값 있는 조정은 그대로)', (pg_temp.try(format('select account_code from public.inv_adjust_account(%L)', (select id::text from public.inv_adjust where status = 'confirmed' limit 1))) ~ '^ERR P0001: The default adjustment account is not set up \(inv_config inv_adjust_default_account_code\) — a migration sets it — nothing was read$')::text || ' ' || (select x.account_code from public.inv_adjust_account(:'adj1'::uuid) x), 'true _62_');
update public.inv_config set value = '_1150040010_' where key = 'inv_adjust_default_account_code';

-- ── K 판정 572 — 새 키는 앱에서 못 바꾼다 ──
select pg_temp.chk('K1 ims_config_set(새 키) → not changed from the app', (pg_temp.try($q$select public.ims_config_set('inv_adjust_default_account_code', '_58_', '_1150040010_')::text$q$) ~ 'not changed from the app')::text || ' ' || (pg_temp.try($q$select public.ims_config_set('supplier_default_account_payable_code_cad', '_109_', '_62_')::text$q$) ~ 'not changed from the app')::text, 'true true');

-- ── W WHERE 정적(REST 두 겹 ①) ──
select pg_temp.chk('W1 이 차수의 함수 일곱 — 깊이 0 WHERE 없는 update · delete 0',
  (select string_agg(p.proname || ' ' || pg_temp.nowhere(p.prosrc)::text, ' · ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('supplier_create', 'supplier_update', 'customer_create', 'customer_update', 'supplier_account_currency_check', 'customer_account_currency_check', 'inv_adjust_account')),
  'customer_account_currency_check 0 · customer_create 0 · customer_update 0 · inv_adjust_account 0 · supplier_account_currency_check 0 · supplier_create 0 · supplier_update 0');
select pg_temp.chk('W2 창구 넷 definer · search_path 그대로 · 트리거 몸 둘 invoker',
  (select string_agg(p.proname || ':' || p.prosecdef::text || ':' || coalesce(array_to_string(p.proconfig, ','), '-'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('supplier_create', 'supplier_update', 'customer_create', 'customer_update', 'supplier_account_currency_check', 'customer_account_currency_check')),
  'customer_account_currency_check:false:search_path=public, pg_temp customer_create:true:search_path=public, pg_temp customer_update:true:search_path=public, pg_temp supplier_account_currency_check:false:search_path=public, pg_temp supplier_create:true:search_path=public, pg_temp supplier_update:true:search_path=public, pg_temp');
select pg_temp.chk('W3 권한: 창구 넷 acl 그대로 · 새 셋 authenticated · service_role · 트리거 몸 둘 비공개',
  (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '(default)'), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('supplier_create', 'customer_update', 'ims_account_currency', 'inv_adjust_account', 'supplier_account_currency_check')),
  'customer_update:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} ims_account_currency:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} inv_adjust_account:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres} supplier_account_currency_check:{postgres=X/postgres} supplier_create:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}');

-- ── Z(rollback 앞 — t_res 도 트랜잭션 안) ──
\echo '── 결과(상호 없음 · 가짜 행은 rollback) ──'
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, 41 as expect_total from t_res;
select 'FAIL ' || label || format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) as fail_line from t_res where not ok order by n;
rollback;
select (select count(*) from public.supplier s where s.currency_id = :'cad'::uuid and s.account_payable_code = '_109_') = :pre_cad109 and (select count(*) from public.ims_staff) = :pre_staff and (select count(*) from public.supplier) = :pre_s_n and (select count(*) from public.customer) = :pre_c_n as rolled_back_clean;
