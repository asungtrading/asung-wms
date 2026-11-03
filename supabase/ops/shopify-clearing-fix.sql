-- supabase/ops/shopify-clearing-fix.sql — 이미 적힌 Shopify 결제의 계좌를 _104_ TD CAD CHEQUING → _1150040029_ Clearing - Shopify 로 (qbo-sync-2e-1a2 · 판정 993 · 2026-11-02)
-- [테스트 · Asung-IMS — Go live 뒤 IMS 메인 · 판정 617] ⚠️ db_role = test 가 아니면 ⓪ 에서 멈춘다 · 마이그레이션 20261103040000(2e-1a2 · 기본값 _1150040029_)이 먼저 적용돼 있어야 한다.
--
-- 왜: Cin7 은 Shopify(aone 카드) 결제를 Clearing - Shopify #1150040029 로 보냈고(47 장 대조 · 14 장) 북키퍼가 수수료 뗀 묶음 입금을 거기서 맞춘다(판정 993 (가)).
--     IMS 기본값은 _104_ 였다(§18-a 판정 2 · 회계사 확인 거리) → 2e-1a2 가 기본값을 바꾸고, 이 파일이 그 전에 적힌 행을 바꾼다.
-- 무엇: so_payment 행의 account_id · account_code → _1150040029_ · note 끝에 흔적 한 줄 · method(shopify) · 붙임 · 금액 · 날짜 · 손님 무접촉
--   대상 = method shopify · status active · account_code _104_ (paypal 로 바꾼 3 건은 method 가 paypal 이라 대상 아님 · shop_cash AO-17309 는 method shopify 라 대상 — Caleb 11-02) · QuickBooks 일감 · 거래 짝이 있으면 멈춤
--
-- 실행(Caleb · 레포 뿌리에서):
--   dry-run(기본 · 끝에 rollback · 검산까지 돈다):  psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/ops/shopify-clearing-fix.sql
--   적용(commit):                                   psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -v apply=1 -f supabase/ops/shopify-clearing-fix.sql
--   선택: -v expect=34  (대상 수가 이 수와 다르면 멈춘다 · 기본 34 · 다시 돌릴 때는 0)
-- 되돌리기(적용 뒤): note 의 흔적 글로 행을 찾아 account_id · account_code = _104_ 로
-- 검산은 `| OK |` 꼴 — 하나라도 FAIL 이면 raise → 전부 되돌아간다(-1).

\set ON_ERROR_STOP on
\if :{?apply}
\else
  \set apply 0
\endif
\if :{?expect}
\else
  \set expect 34
\endif
set lock_timeout = '3s';
select set_config('ops.apply', :'apply', true) as apply, set_config('ops.expect', :'expect', true) as expect;

-- ⓪ 이 DB · 2e-1a2 적용됨(기본값) · 계좌 _1150040029_
do $$
declare v_role text; v_a public.ref_account%rowtype; v_def int;
begin
  select value into v_role from public.inv_config where key = 'db_role';
  if coalesce(v_role, '') <> 'test' then raise exception '⓪ this DB is % — the IMS main DB is Asung-IMS (db_role = test) — nothing was saved', coalesce(v_role, '(no db_role)'); end if;
  select * into v_a from public.ref_account a where a.code = '_1150040029_';
  if v_a.id is null or not (v_a.is_active and v_a.account_type = 'BANK') then raise exception '⓪ account _1150040029_ (Clearing - Shopify) missing or not an active BANK account — nothing was saved'; end if;
  select count(*) into v_def from public.so_payment_account_default d where d.method = 'shopify' and d.currency_code = 'CAD' and d.account_code = '_1150040029_';
  if v_def <> 2 then raise exception '⓪ shopify CAD default is not _1150040029_ on both warehouses (% rows) — apply migration 20261103040000 (qbo-sync-2e-1a2) first — nothing was saved', v_def; end if;
  raise notice '⓪ OK · db_role test · default shopify CAD → _1150040029_ · % active', v_a.name;
end $$;

-- ① 대상
create temp table t_fix as
select p.id, p.reference, p.paid_on, p.amount, p.method, p.account_code,
       (select count(*) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null) as allocs,
       (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a where a.payment_id = p.id and a.voided_at is null) as alloc_sum
  from public.so_payment p
 where p.method = 'shopify' and p.status = 'active' and p.account_code = '_104_';
do $$
declare v_n int; v_exp int := current_setting('ops.expect', true)::int; r record; v_jobs int; v_sum numeric; v_voided int;
begin
  select count(*), coalesce(sum(amount), 0) into v_n, v_sum from t_fix;
  for r in select * from t_fix order by paid_on, reference loop
    raise notice '① target: % · % · % CAD · % · account % · allocs % (%)', r.reference, r.paid_on, r.amount, r.method, r.account_code, r.allocs, r.alloc_sum;
  end loop;
  select count(*) into v_voided from public.so_payment p where p.method = 'shopify' and p.status = 'voided';
  if v_n <> v_exp then raise exception '① expected % target payment(s), found % — pass -v expect=<n> if that is right — nothing was saved', v_exp, v_n; end if;
  select count(*) into v_jobs from public.qbo_job j where j.ims_id in (select id::text from t_fix);
  if v_jobs > 0 then raise exception '① % target payment(s) already have a QuickBooks job — fix those by void + resend, not here — nothing was saved', v_jobs; end if;
  select count(*) into v_jobs from public.qbo_txn x where x.ims_id in (select id::text from t_fix);
  if v_jobs > 0 then raise exception '① % target payment(s) are already in QuickBooks (qbo_txn) — nothing was saved', v_jobs; end if;
  raise notice '① % payment(s) · % CAD to move · voided shopify payments left alone: % · no QuickBooks job or txn yet', v_n, v_sum, v_voided;
end $$;

-- ② 고치기 — 계좌 · note 흔적 · 그 밖 무접촉(so_payment_touch 가 updated_at 만)
update public.so_payment p
   set account_id = a.id, account_code = a.code,
       note = concat_ws(' · ', p.note, 'deposit account set to Clearing - Shopify _1150040029_ (qbo-sync-2e-1a2 판정 993 · was _104_)')
  from public.ref_account a
 where a.code = '_1150040029_' and p.id in (select id from t_fix);

-- ③ 검산 넷
do $$
declare v_fail int := 0; v_ok boolean; v_n int; v_s text; v_exp int := current_setting('ops.expect', true)::int;
begin
  select count(*) into v_n from public.so_payment p where p.id in (select id from t_fix) and p.method = 'shopify' and p.account_code = '_1150040029_' and p.account_id = (select id from public.ref_account where code = '_1150040029_');
  v_ok := v_n = v_exp;
  raise notice '| % | targets now shopify · _1150040029_ | % of %', case when v_ok then 'OK' else 'FAIL' end, v_n, v_exp;
  if not v_ok then v_fail := v_fail + 1; end if;
  select count(*) into v_n from public.so_payment p where p.method = 'shopify' and p.status = 'active' and p.account_code = '_104_';
  v_ok := v_n = 0;
  raise notice '| % | active shopify payments still on _104_ | %', case when v_ok then 'OK' else 'FAIL' end, v_n;
  if not v_ok then v_fail := v_fail + 1; end if;
  select coalesce(string_agg(distinct p.method || ' ' || p.account_code, ','), 'none') into v_s from public.so_payment p where p.method = 'paypal';
  v_ok := v_s in ('paypal _124_', 'none');
  raise notice '| % | paypal payments untouched (_124_) | %', case when v_ok then 'OK' else 'FAIL' end, v_s;
  if not v_ok then v_fail := v_fail + 1; end if;
  select count(*) into v_n from t_fix f where f.allocs <> (select count(*) from public.so_payment_alloc a where a.payment_id = f.id and a.voided_at is null)
                                        or f.alloc_sum <> (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a where a.payment_id = f.id and a.voided_at is null)
                                        or f.amount <> (select p.amount from public.so_payment p where p.id = f.id) or f.paid_on <> (select p.paid_on from public.so_payment p where p.id = f.id)
                                        or f.method <> (select p.method from public.so_payment p where p.id = f.id);
  v_ok := v_n = 0;
  raise notice '| % | allocations · amount · date · method untouched | % changed', case when v_ok then 'OK' else 'FAIL' end, v_n;
  if not v_ok then v_fail := v_fail + 1; end if;
  if v_fail > 0 then raise exception '③ % check(s) FAIL — nothing was saved', v_fail; end if;
  if current_setting('ops.apply', true) = '1' then raise notice '③ all OK · apply=1 → commit'; else raise notice '③ all OK · dry-run → rollback (add -v apply=1 to commit)'; end if;
end $$;

\if :apply
\else
  rollback;
\endif
