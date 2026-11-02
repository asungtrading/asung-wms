-- supabase/ops/restock-fee-account.sql — 리스탁킹 피 계정을 IMS 에 넣는다 (cr-ref-fee-1 · 2026-11-02)
-- [테스트 · Asung-IMS — Go live 뒤 IMS 메인 · 판정 617] ⚠️ db_role = test 가 아니면 ⓪ 에서 멈춘다.
--
-- 왜: 리스탁킹 피 계정은 없었다(so-module §19 판정 7 · 설정 so_credit_restock_fee_account_code 빈 값 · 매니저가 줄마다 고른다).
--     북키퍼가 QBO 에 수입 계정 + 같은 이름 Item 을 만들면 IMS 에 그 계정을 넣고 기본으로 삼는다(판정 7 「회계사가 정하면 값만」).
-- IMS 계정 code 의 꼴 = `_<QBO Account Id>_` (qbo_match_auto 'account' = auto_code · `^_([0-9]+)_$` 의 숫자 = qbo_entity.qbo_id · _98_ ↔ 98 실측).
--     AcctNum(QBO 「번호」)이 아니다 — Id 는 QBO 가 계정을 만들 때 주고 pull 한 뒤 qbo_entity 에서 읽는다.
--
-- 순서(사람):
--   1. QBO — 북키퍼: 수입 계정(Income) + 같은 이름의 Item(Service · Income account = 그 계정).
--   2. IMS — Settings → QuickBooks → pull Accounts · Items (qbo_entity 에 들어온다).
--   3. Id 찾기(아래 「찾기」 문장) → 이 파일 dry-run → 보고 → -v apply=1.
--   4. 이 파일이 하는 것: ref_account 한 줄(source manual · REVENUE) · 설정 키 · qbo_link account(auto_code 와 같은 꼴 · 이 파일이 직접 넣는다 — qbo_match_auto 는 로그인 직원만 부른다).
--   5. 뒤에 손으로: 첫 크레딧(수수료 줄)을 발행 → 송신 일감이 한 번 failed(「no QuickBooks item — link account item acct:<code>」 · 판정 961)
--      → Settings → QuickBooks matching → 「Freight, discount & account lines」 에 acct:<code> 행이 보인다(크레딧 줄이 생겨야 보인다 · qbo_ims_rows 'charge')
--      → Item 짝 → 그 일감 Retry. (qbo_link_set 은 qbo_ims_rows 에 있는 행만 받으므로 크레딧 전에는 못 짝는다.)
--
-- 찾기(Id · 이름 · Item 유무):
--   psql "$(cat ~/.asung-testdb-url)" -X -c "select qbo_id, name, active from qbo_entity where qbo_type = 'Account' and name ilike '%restock%' order by 1;"
--   psql "$(cat ~/.asung-testdb-url)" -X -c "select qbo_id, name, active from qbo_entity where qbo_type = 'Item' and name ilike '%restock%' order by 1;"
--
-- 실행(Caleb · 레포 뿌리에서 · 변수 둘은 필수 · 셋째는 선택):
--   dry-run(기본 · 끝에 rollback · 검산까지 돈다):
--     psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -v acct_id=<QBO Account Id> -v acct_name='<QBO 계정 이름>' -f supabase/ops/restock-fee-account.sql
--   적용(commit):
--     psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -v acct_id=<QBO Account Id> -v acct_name='<QBO 계정 이름>' -v apply=1 -f supabase/ops/restock-fee-account.sql
--   선택: -v acct_type=OTHERINCOME (기본 INCOME · ref_account.account_type 표기 · QBO AccountType 과 맞춘다)
-- 되돌리기(적용 뒤):
--   update inv_config set value = '' where key = 'so_credit_restock_fee_account_code';
--   delete from qbo_link where ims_kind = 'account' and ims_id = (select id::text from ref_account where code = '_<Id>_');
--   update ref_account set is_active = false where code = '_<Id>_';   -- 크레딧 줄이 이미 그 계정을 썼으면 지우지 않는다(account_id 참조)
-- 검산은 `| OK |` 꼴 — 하나라도 FAIL 이면 raise → 전부 되돌아간다(-1).

\set ON_ERROR_STOP on
\if :{?acct_id}
\else
  \echo 'need -v acct_id=<QBO Account Id>'
  \quit
\endif
\if :{?acct_name}
\else
  \echo 'need -v acct_name=<QBO account name>'
  \quit
\endif
\if :{?acct_type}
\else
  \set acct_type INCOME
\endif
\if :{?apply}
\else
  \set apply 0
\endif

set lock_timeout = '3s';
select set_config('ops.acct_id', :'acct_id', true) as acct_id, set_config('ops.acct_name', :'acct_name', true) as acct_name, set_config('ops.acct_type', :'acct_type', true) as acct_type, set_config('ops.apply', :'apply', true) as apply;

-- ⓪ 이 DB · 입력 꼴 · QBO 쪽 실물
do $$
declare v_role text; v_id text := current_setting('ops.acct_id', true); v_name text := current_setting('ops.acct_name', true); v_ent public.qbo_entity%rowtype; v_items int;
begin
  select value into v_role from public.inv_config where key = 'db_role';
  if coalesce(v_role, '') <> 'test' then raise exception '⓪ this DB is % — the IMS main DB is Asung-IMS (db_role = test) — nothing was saved', coalesce(v_role, '(no db_role)'); end if;
  if v_id !~ '^[0-9]+$' then raise exception '⓪ acct_id must be the QBO Account Id (digits only · got %) — not the AcctNum', v_id; end if;
  if nullif(btrim(v_name), '') is null then raise exception '⓪ acct_name is empty'; end if;
  select * into v_ent from public.qbo_entity e where e.realm_id = public.qbo_realm_of() and e.qbo_type = 'Account' and e.qbo_id = v_id;
  if v_ent.qbo_id is null then raise exception '⓪ QuickBooks Account % is not in the pulled list — Settings → QuickBooks → pull Accounts first', v_id; end if;
  if v_ent.gone_at is not null then raise exception '⓪ QuickBooks Account % (%) is gone since %', v_id, v_ent.name, v_ent.gone_at::date; end if;
  if not v_ent.active then raise exception '⓪ QuickBooks Account % (%) is inactive', v_id, v_ent.name; end if;
  if lower(btrim(v_ent.name)) <> lower(btrim(v_name)) then raise exception '⓪ acct_name "%" ≠ QuickBooks Account % name "%" — pass the QBO name as is', v_name, v_id, v_ent.name; end if;
  select count(*) into v_items from public.qbo_entity e where e.realm_id = public.qbo_realm_of() and e.qbo_type = 'Item' and e.gone_at is null and e.active and lower(btrim(e.name)) = lower(btrim(v_name));
  raise notice '⓪ OK · db_role test · Account % "%" active · same-name Items pulled: % (0 = make the Item in QBO and pull Items before the first credit is sent)', v_id, v_ent.name, v_items;
end $$;

-- ① ref_account — code _<Id>_ · 이미 있으면 같은 이름일 때만 지나간다(활성으로 켠다)
do $$
declare v_id text := current_setting('ops.acct_id', true); v_name text := current_setting('ops.acct_name', true); v_type text := current_setting('ops.acct_type', true); v_code text; v_a public.ref_account%rowtype;
begin
  v_code := '_' || v_id || '_';
  select * into v_a from public.ref_account a where a.code = v_code;
  if v_a.id is null then
    insert into public.ref_account (code, name, account_class, account_type, source, is_active, for_payments, note)
    values (v_code, btrim(v_name), 'REVENUE', v_type, 'manual', true, false, 'Restocking fee account (cr-ref-fee-1 · so-module §19 판정 7 · QBO Account Id ' || v_id || ')');
    raise notice '① ref_account inserted · % %', v_code, btrim(v_name);
  elsif lower(btrim(v_a.name)) <> lower(btrim(v_name)) then
    raise exception '① ref_account % already exists with another name "%" — nothing was saved', v_code, v_a.name;
  else
    update public.ref_account a set is_active = true where a.id = v_a.id and not a.is_active;
    raise notice '① ref_account % already there (%) · active', v_code, v_a.name;
  end if;
end $$;

-- ② 설정 키 — 기본 계정 code (앱의 ims_config_set 은 이 키를 거부한다 · psql 만)
update public.inv_config c
   set value = '_' || current_setting('ops.acct_id', true) || '_', updated_at = now()
 where c.key = 'so_credit_restock_fee_account_code';

-- ③ qbo_link account — auto_code 와 같은 꼴(ims_id = ref_account.id · Account · matched_by auto_code · by_staff null = psql)
insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match)
select public.qbo_realm_of(), 'account', a.id::text, 'Account', current_setting('ops.acct_id', true), 'auto_code', e.name
  from public.ref_account a
  join public.qbo_entity e on e.realm_id = public.qbo_realm_of() and e.qbo_type = 'Account' and e.qbo_id = current_setting('ops.acct_id', true)
 where a.code = '_' || current_setting('ops.acct_id', true) || '_'
on conflict (realm_id, ims_kind, ims_id) do nothing;

-- ④ 검산 — 셋 + 미리 보기 하나(참조 크레딧 · 수수료 줄에 account_id 없이 → 설정 기본이 붙는가 · 쓰기 0)
do $$
declare v_id text := current_setting('ops.acct_id', true); v_code text; v_a public.ref_account%rowtype; v_cfg text; v_l public.qbo_link%rowtype; v_fail int := 0;
        v_auth uuid; v_cust uuid; v_sku text; v_r jsonb; v_fee jsonb; v_ok boolean;
begin
  v_code := '_' || v_id || '_';
  select * into v_a from public.ref_account a where a.code = v_code;
  v_ok := v_a.id is not null and v_a.is_active and v_a.account_class = 'REVENUE';
  raise notice '| % | ref_account | %', case when v_ok then 'OK' else 'FAIL' end, coalesce(v_code || ' ' || v_a.name || ' · ' || v_a.account_class || '/' || coalesce(v_a.account_type, '-') || ' · ' || v_a.source, 'missing');
  if not v_ok then v_fail := v_fail + 1; end if;
  select value into v_cfg from public.inv_config where key = 'so_credit_restock_fee_account_code';
  v_ok := v_cfg = v_code;
  raise notice '| % | inv_config so_credit_restock_fee_account_code | %', case when v_ok then 'OK' else 'FAIL' end, coalesce(v_cfg, '(null)');
  if not v_ok then v_fail := v_fail + 1; end if;
  select * into v_l from public.qbo_link l where l.realm_id = public.qbo_realm_of() and l.ims_kind = 'account' and l.ims_id = v_a.id::text;
  v_ok := v_l.qbo_id = v_id and v_l.qbo_type = 'Account';
  raise notice '| % | qbo_link account | %', case when v_ok then 'OK' else 'FAIL' end, coalesce('qbo_id ' || v_l.qbo_id || ' · ' || v_l.matched_by || ' · ' || coalesce(v_l.qbo_name_at_match, '-'), 'missing');
  if not coalesce(v_ok, false) then v_fail := v_fail + 1; end if;
  -- 미리 보기: 활성 admin 직원 · 활성 손님 · 활성 SKU 하나 · HST ON (Sale) · 수수료 줄에 계정 지정 없음 ⇒ 설정 기본
  select s.auth_user_id into v_auth from public.ims_staff s where s.is_active and s.role = 'admin' and s.auth_user_id is not null order by s.created_at limit 1;
  select c.id into v_cust from public.customer c where c.is_active order by c.created_at limit 1;
  select p.sku into v_sku from public.product p where p.is_active and p.sku ~ '^[A-Z]{3}[0-9]' order by p.sku limit 1;
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_auth, 'role', 'authenticated')::text, true);
  v_r := public.so_credit_issue(jsonb_build_object('customer_id', v_cust, 'ref', jsonb_build_object('invoice_number', 'RESTOCK-FEE-CHECK', 'invoice_date', public.ims_today() - 100),
                                                   'tax_rule', 'HST ON (Sale)', 'reason', 'customer_return',
                                                   'lines', jsonb_build_array(jsonb_build_object('kind', 'product', 'sku', v_sku, 'qty_returned', 2, 'unit_price', 10, 'not_restocked_reason', 'damaged'),
                                                                              jsonb_build_object('kind', 'restocking_fee'))), false);
  perform set_config('request.jwt.claims', '', true);
  select x into v_fee from jsonb_array_elements(v_r->'lines') x where x->>'kind' = 'restocking_fee';
  v_ok := coalesce(v_fee->>'account_code' = v_code and (v_fee->>'amount')::numeric = -4.00 and (v_r->>'committed') = 'false', false);
  raise notice '| % | preview ref credit · fee line takes the default account | %', case when v_ok then 'OK' else 'FAIL' end,
        coalesce('amount ' || (v_fee->>'amount') || ' · account ' || (v_fee->>'account_code') || ' · total ' || (v_r->'totals'->>'total') || ' · committed ' || (v_r->>'committed'), 'no fee line');
  if not v_ok then v_fail := v_fail + 1; end if;
  if v_fail > 0 then raise exception '④ % check(s) FAIL — nothing was saved', v_fail; end if;
  if current_setting('ops.apply', true) = '1' then raise notice '④ all OK · apply=1 → commit'; else raise notice '④ all OK · dry-run → rollback (add -v apply=1 to commit)'; end if;
end $$;

\if :apply
\else
  rollback;
\endif
