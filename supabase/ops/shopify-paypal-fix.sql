-- supabase/ops/shopify-paypal-fix.sql — 이미 적힌 Shopify PayPal 결제를 수단 paypal · 계좌 _124_ PayPal 로 바로잡는다 (qbo-sync-2e-1a · 판정 986 · 2026-11-02)
-- [테스트 · Asung-IMS — Go live 뒤 IMS 메인 · 판정 617] ⚠️ db_role = test 가 아니면 ⓪ 에서 멈춘다 · 마이그레이션 20261103020000(2e-1a · CHECK 에 paypal · _124_ 기본값)이 먼저 적용돼 있어야 한다.
--
-- 왜: 받기가 gateway paypal 거래도 method shopify · 계좌 _104_ TD CAD CHEQUING 으로 적었다(2e-0 Q5 · 실물 3 건 185.28 — AO-17314 64.35 · AO-17327 84.23 · AO-17339 36.70 · 모두 2026-11-02).
--     북키퍼: PayPal 돈은 PayPal 계정(QBO _124_ · 수단 7 PayPal)으로(판정 986). 2e-1a 부터 받기가 바로 paypal 로 적으므로 이 파일은 그 전 행만 고친다.
--     shop_cash(AO-17309 5.00)는 _104_ · shopify 그대로(Caleb 2026-11-02).
-- 무엇: so_payment 행의 method shopify → paypal · account_id · account_code → _124_ · note 끝에 흔적 한 줄 · 붙임(so_payment_alloc) · 금액 · 날짜 · 손님 무접촉
--   대상 = shop_order_transaction.gateway = 'paypal' 인 거래의 so_payment 중 method shopify · status active · 아직 QuickBooks 일감 · 거래 짝이 없는 것(있으면 멈춤 — 보낸 뒤에는 void + 다시 보내기 길로)
--
-- 실행(Caleb · 레포 뿌리에서):
--   dry-run(기본 · 끝에 rollback · 검산까지 돈다):  psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/ops/shopify-paypal-fix.sql
--   적용(commit):                                   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -v apply=1 -f supabase/ops/shopify-paypal-fix.sql
--   선택: -v expect=3  (대상 수가 이 수와 다르면 멈춘다 · 기본 3 · 다시 돌릴 때는 0)
-- 되돌리기(적용 뒤): note 의 흔적 글로 행을 찾아 method = 'shopify' · account_id · account_code = _104_ 로(붙임은 안 건드렸으니 그대로)
-- 검산은 `| OK |` 꼴 — 하나라도 FAIL 이면 raise → 전부 되돌아간다(-1).

\set ON_ERROR_STOP on
\if :{?apply}
\else
  \set apply 0
\endif
\if :{?expect}
\else
  \set expect 3
\endif
set lock_timeout = '3s';
select set_config('ops.apply', :'apply', true) as apply, set_config('ops.expect', :'expect', true) as expect;

-- ⓪ 이 DB · 2e-1a 적용됨 · 계좌 _124_
do $$
declare v_role text; v_124 public.ref_account%rowtype; v_ck text;
begin
  select value into v_role from public.inv_config where key = 'db_role';
  if coalesce(v_role, '') <> 'test' then raise exception '⓪ this DB is % — the IMS main DB is Asung-IMS (db_role = test) — nothing was saved', coalesce(v_role, '(no db_role)'); end if;
  select pg_get_constraintdef(oid) into v_ck from pg_constraint where conname = 'so_payment_method_ck';
  if v_ck !~ '''paypal''' then raise exception '⓪ so_payment_method_ck has no paypal — apply migration 20261103020000 (qbo-sync-2e-1a) first — nothing was saved'; end if;
  select * into v_124 from public.ref_account a where a.code = '_124_';
  if v_124.id is null or not (v_124.is_active and v_124.account_type = 'BANK') then raise exception '⓪ account _124_ (PayPal) missing or not an active BANK account — nothing was saved'; end if;
  raise notice '⓪ OK · db_role test · paypal in CHECK · _124_ % active', v_124.name;
end $$;

-- ① 대상 — 거래 표의 gateway paypal → 그 결제 · 아직 shopify 인 것
create temp table t_fix as
select p.id, p.reference, p.paid_on, p.amount, p.method, p.account_code, t.gateway, t.transaction_gid,
       (select count(*) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null) as allocs,
       (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null) as alloc_sum
  from public.shop_order_transaction t
  join public.so_payment p on p.id = t.so_payment_id
 where lower(coalesce(t.gateway, '')) = 'paypal' and p.method = 'shopify' and p.status = 'active';
do $$
declare v_n int; v_exp int := current_setting('ops.expect', true)::int; r record; v_jobs int;
begin
  select count(*) into v_n from t_fix;
  for r in select * from t_fix order by reference loop
    raise notice '① target: % · % · % % · method % · account % · gateway % · allocs % (%)', r.reference, r.paid_on, r.amount, 'CAD', r.method, r.account_code, r.gateway, r.allocs, r.alloc_sum;
  end loop;
  if v_n <> v_exp then raise exception '① expected % target payment(s), found % — pass -v expect=<n> if that is right — nothing was saved', v_exp, v_n; end if;
  select count(*) into v_jobs from public.qbo_job j where j.ims_id in (select id::text from t_fix);
  if v_jobs > 0 then raise exception '① % target payment(s) already have a QuickBooks job — fix those by void + resend, not here — nothing was saved', v_jobs; end if;
  select count(*) into v_jobs from public.qbo_txn x where x.ims_id in (select id::text from t_fix);
  if v_jobs > 0 then raise exception '① % target payment(s) are already in QuickBooks (qbo_txn) — nothing was saved', v_jobs; end if;
  raise notice '① % payment(s) to fix · no QuickBooks job or txn yet', v_n;
end $$;

-- ② 고치기 — method · 계좌 · note 흔적 · 그 밖 무접촉(so_payment_touch 가 updated_at 만)
update public.so_payment p
   set method = 'paypal', account_id = a.id, account_code = a.code,
       note = concat_ws(' · ', p.note, 'account set to PayPal _124_ · method paypal (qbo-sync-2e-1a 판정 986 · was shopify _104_)')
  from public.ref_account a
 where a.code = '_124_' and p.id in (select id from t_fix);

-- ③ 검산 넷
do $$
declare v_fail int := 0; v_ok boolean; v_n int; v_s text; v_exp int := current_setting('ops.expect', true)::int;
begin
  select count(*) into v_n from public.so_payment p where p.id in (select id from t_fix) and p.method = 'paypal' and p.account_code = '_124_' and p.account_id = (select id from public.ref_account where code = '_124_');
  v_ok := v_n = v_exp;
  raise notice '| % | targets now paypal · _124_ | % of %', case when v_ok then 'OK' else 'FAIL' end, v_n, v_exp;
  if not v_ok then v_fail := v_fail + 1; end if;
  select count(*) into v_n from public.shop_order_transaction t join public.so_payment p on p.id = t.so_payment_id where lower(coalesce(t.gateway, '')) = 'paypal' and p.method = 'shopify' and p.status = 'active';
  v_ok := v_n = 0;
  raise notice '| % | paypal-gateway payments still on shopify | %', case when v_ok then 'OK' else 'FAIL' end, v_n;
  if not v_ok then v_fail := v_fail + 1; end if;
  select string_agg(p.method || ' ' || p.account_code, ',') into v_s from public.shop_order_transaction t join public.so_payment p on p.id = t.so_payment_id where lower(coalesce(t.gateway, '')) = 'shop_cash';
  v_ok := coalesce(v_s, 'none') in ('shopify _104_', 'none');
  raise notice '| % | shop_cash untouched (shopify _104_) | %', case when v_ok then 'OK' else 'FAIL' end, coalesce(v_s, 'none');
  if not v_ok then v_fail := v_fail + 1; end if;
  select count(*) into v_n from t_fix f where f.allocs <> (select count(*) from public.so_payment_alloc a where a.payment_id = f.id and a.voided_at is null)
                                        or f.alloc_sum <> (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a where a.payment_id = f.id and a.voided_at is null)
                                        or f.amount <> (select p.amount from public.so_payment p where p.id = f.id) or f.paid_on <> (select p.paid_on from public.so_payment p where p.id = f.id);
  v_ok := v_n = 0;
  raise notice '| % | allocations · amount · date untouched | % changed', case when v_ok then 'OK' else 'FAIL' end, v_n;
  if not v_ok then v_fail := v_fail + 1; end if;
  if v_fail > 0 then raise exception '③ % check(s) FAIL — nothing was saved', v_fail; end if;
  if current_setting('ops.apply', true) = '1' then raise notice '③ all OK · apply=1 → commit'; else raise notice '③ all OK · dry-run → rollback (add -v apply=1 to commit)'; end if;
end $$;

\if :apply
\else
  rollback;
\endif
