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
-- qbo-sync-2e-3-2-1 — 환불(so_payment kind refund)의 크레딧 노트 몫을 QuickBooks 로(DB): 일감 kind 넷 · 몸 넷 · 상태 맞추기 · 트리거(INSERT 새로 · status 가지) · 1056 컷 · 990 표시 · ⓖ-1 이월 가드 · 백필 · 재발행 열 (판정 1056 ~ 1058 · 이견 3 (가) · 6 (나) · 8 · 9 · ⓖ-1 ~ ⓖ-8 · 2026-11-08 · 지시서 ~/asung/prompts/qbo-sync-2e-3-2-1.md · §0 이견 1 ~ 19 Caleb 답)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied <이 파일 번호> · ⚠️ db push 쓰지 않는다 · 2e-3-1(20261107044131) 뒤
-- ⭐ 범위(이견 9 답): 크레딧 노트 몫만 — 받아 둔 돈 몫(refund_from_account > 0)이 있는 환불은 통째로 failed(ⓖ-2 · 반쪽만 보내지 않는다) · 컷(1056 · paid_on < 2026-10-30) 전 환불은 일감 0(ⓖ-5) · 컷 전 날짜로 새로 적은 환불은 failed 「Dated before the cut-over …」(ⓖ-4 · 사람이 Retry 또는 Skip) · 통화 ≠ 기본 통화는 failed(이견 5)
-- 무엇:
--   ⓪ 재발행 원본 가드 — 재발행 열(claim · done · preview · doc · list · retry · link_set · job_on_payment_status · opening_alloc_sync · opening_credit_body)과 무변이어야 하는 결제 넷 · credit_alloc_sync · credit_apply_body · opening_apply_body · job_on_payment_alloc 의 DB prosrc md5 가 다르면 멈춘다
--   ① 표(⚠️ 파일 끝 — 잠금 구간을 짧게): qbo_job kind(+ refund · refund_void · refund_apply · refund_apply_void) · ims_kind(+ refund · ims_id = so_payment.id · 넷 모두 그 환불 하나 · ⓖ-6) · pair / qbo_txn ims_kind(+ refund ↔ Purchase · refund_apply ↔ Payment · 이견 8: 한 환불에 장이 둘이라 ims_kind 둘) · qbo_type(+ Purchase) · 새 트리거 so_payment_refund_qbo(AFTER INSERT · DEFERRABLE INITIALLY DEFERRED · kind refund · 이견 6 (나) · 7)
--   ② 도우미(식 한 곳): qbo_refund_from_account(환불) = amount − Σ활성 so_credit_alloc(refund_payment_id)(so_payment_list · so_customer_balance 의 식 그대로) · qbo_opening_refunded_block(붙임)(ⓖ-1 (다): Σ so_payment_remaining(이월 · 활성 · 같은 통화) − Σ 환불 account 몫 < 0 이면 글) · qbo_refund_block(환불)(이견 5 통화 · ⓖ-2 account 몫 — sync 는 failed 글로 · 몸은 예외로) · qbo_refund_label · qbo_refund_purchase_head(Purchase 머리 · 줄 detail: 정산 계좌 = account_code 짝 · A/R = customer.ar_account_code 짝 · 세금 = Out of Scope (Purchase) 규칙의 qbo_link 짝(ⓖ-8 · 번호 안 박음) · DocNumber = reference 21 자) · qbo_refund_credit_lines(크레딧마다 CreditMemo 거래 · 기다림 · 매장 ≠ 손님 울타리(이견 12) · 1013 꼴 void 기다림(이견 11))
--   ③ 몸 넷(grant 0 · claim · preview 가 부른다): qbo_refund_body = Purchase(sandbox 2-a · PaymentType Cash · AccountRef 정산 계좌 · EntityRef 환불 손님 · GlobalTaxCalculation NotApplicable · 줄 하나 A/R + CustomerRef + Out of Scope · Amount = 크레딧 몫 합 · PrivateNote 「IMS refund <uuid>」) · qbo_refund_apply_body = 0 원 Payment(Expense 줄 = Purchase · A/R 몫 합 + CreditMemo 줄마다 · sandbox-2 걸음 25 · PrivateNote 「IMS refund applied <uuid>」) · qbo_refund_apply_void_body(결제 void 꼴 · sparse) · qbo_refund_void_body(ⓖ-7 · 이견 9: Full update 꼴 전부 · 줄 Amount 0 · PrivateNote 「Voided - 」 머리 · SyncToken 은 EF 가 다시 읽어 끼운다 · 줄도 읽은 것으로)
--   ④ qbo_refund_sync(환불 · 사람) — 상태표: Purchase 보낸 적 없음 · 활성 → (컷 전 ∧ 11-08 전 created = 일감 0 · ⓖ-5) · refund queued(차단 글이 있으면 failed · ⓖ-2 · ⓖ-4) + refund_apply blocked_by 그것 / void → 열린 것 skipped · sending · unknown 이면 refund_void 를 그 뒤에 · 컷 전이면 refund_void **failed** 「entered in QuickBooks by hand before the cut-over — void it there too」(ⓖ-5 알림 · 이견 4) / Purchase 서 있음 · Payment 아직 → apply queued · void → refund_void queued(apply 가 나가는 중이면 apply_void → refund_void 차례) / 둘 다 서 있음 · void → refund_apply_void queued → refund_void blocked_by(ⓖ-7 순서) / QBO 쪽 void 됨 → 열린 것 skipped · 트리거 둘 = qbo_job_on_refund_insert(새) · qbo_job_on_payment_status 재발행(refund 가지) · 오류는 삼킨다
--   ⑤ qbo_refund_backfill()(적용 때 한 번 · 활성 환불 · 일감 · 거래 없음 → sync · 컷은 sync 가 가른다) · qbo_refund_requeue(사람)(세금 짝이 서면 failed refund → queued · qbo_link_set tax_rule 가지 · 1039 꼴)
--   ⑥ 재발행(DB 바이트 + 가지): claim(kinds 18 · 몸 넷) · preview · doc(refund) · list(kinds 18 · ims_name · txn join kind 로) · retry(규칙 넷) · done(refund → qbo_txn Purchase · TotalAmt = 크레딧 몫 합 대조 · refund_apply → qbo_txn refund_apply Payment 0 대조 · void 둘 → voided_at · 끝에 sync) · link_set(tax_rule 가지) · on_payment_status(refund 가지) · opening_alloc_sync(ⓖ-1 가드 → failed) · opening_credit_body(ⓖ-1 가드 → 예외)
--   ⑦ grant · comment · 착지 · 백필 NOTICE
-- 안 하는 것: EF(2e-3-2-1b — SEND_KINDS 18 · Purchase 쓰기 · assertWriteAllowed 몸 검사 · refund_void 읽고 고쳐 쓰기 · 가드 TxnDate 범위 · unknown 풀기 · cron 62 kinds 열둘) · 화면(1c) · 받아 둔 돈 몫(ⓖ-2 따로 차수) · ⓖ-1 (가) 환불을 결제에 매기(따로 차수) · USD 손님 셋의 ar_account_code _61_(deferred)
-- 거래 표 FK: 0(ims_id 다형) · 검증: supabase/tests/qbo_sync_2e3_2_1_check.sql(-v mig 시험 · 적용 뒤 -v mig 없이)

-- ═══ ⓪ 재발행 원본 가드 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_claim')                   is distinct from 'd5d2451f30d554de904a671acbbca63a' then v_bad := v_bad || ' qbo_job_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_done')                    is distinct from '5ccbf6d01f9070a3b29544e5d90d2d7a' then v_bad := v_bad || ' qbo_job_done'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_preview')                 is distinct from '23a3c17cd0abc73c30581d7d2f19b567' then v_bad := v_bad || ' qbo_job_preview'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_doc')                     is distinct from 'e37fd6610563f5bfe0505d6082b2164c' then v_bad := v_bad || ' qbo_job_doc'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_list')                    is distinct from '60192de3829d5ce653b9d6c5fa705de2' then v_bad := v_bad || ' qbo_job_list'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_retry')                   is distinct from '07b2fcaf4005179a50a4157f1614446a' then v_bad := v_bad || ' qbo_job_retry'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_link_set')                    is distinct from '8b4372cb1df4834567b687f2c1264689' then v_bad := v_bad || ' qbo_link_set'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_on_payment_status')       is distinct from '05517da102d5e288d304d8e94fb658f0' then v_bad := v_bad || ' qbo_job_on_payment_status'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_opening_alloc_sync')          is distinct from '53c07803d1b6165a8bb6f35555347f43' then v_bad := v_bad || ' qbo_opening_alloc_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_opening_credit_body')         is distinct from '7e88a31136420cbfc3ff16e433de0684' then v_bad := v_bad || ' qbo_opening_credit_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_body')                is distinct from 'e1aea51849844cc5898351daaa3ef533' then v_bad := v_bad || ' qbo_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_void_body')           is distinct from '4ddb45cd728222d7b676d1e0bd169a54' then v_bad := v_bad || ' qbo_payment_void_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync')                is distinct from '9efb5d9f6007048692d13cd00623c4b8' then v_bad := v_bad || ' qbo_payment_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_fingerprint')         is distinct from 'd6da0342942ef68345b9432e0e84da23' then v_bad := v_bad || ' qbo_payment_fingerprint'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_alloc_sync')           is distinct from '44419d3b499a33299e010e33671b26fa' then v_bad := v_bad || ' qbo_credit_alloc_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_apply_body')           is distinct from '50dcad57a35f9c83412ae437fd873726' then v_bad := v_bad || ' qbo_credit_apply_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_opening_apply_body')          is distinct from '71b0e76ec76d4c2524cd31c3452ce074' then v_bad := v_bad || ' qbo_opening_apply_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_on_payment_alloc')        is distinct from '5466ba493ed2874918e17fa84e4abfdb' then v_bad := v_bad || ' qbo_job_on_payment_alloc'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('qbo_job_done', 'qbo_job_claim', 'qbo_link_set', 'qbo_job_on_payment_status', 'qbo_opening_alloc_sync', 'qbo_opening_credit_body')) <> 6 then v_bad := v_bad || ' overloads'; end if;
  if to_regprocedure('public.qbo_account_ref(text, text)') is null or to_regprocedure('public.so_credit_store(uuid)') is null or to_regprocedure('public.qbo_refund_from_account(uuid)') is not null then v_bad := v_bad || ' prerequisites(2e-1b · cr-store-1a) or already-applied'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_payment'::regclass and not tgisinternal) <> 2 then v_bad := v_bad || ' so_payment triggers (expected 2: so_payment_qbo_status · so_payment_touch)'; end if;
  if exists (select 1 from pg_constraint where conname = 'qbo_job_kind_ck' and pg_get_constraintdef(oid) like '%refund%') then v_bad := v_bad || ' already-applied'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══ ② 도우미 — 식 한 곳(환불 account 몫 · ⓖ-1 가드 · 차단 글 · 이름표 · Purchase 머리 · 크레딧 줄) ═══
create function public.qbo_refund_from_account(p_refund_id uuid) returns numeric
  language sql stable security definer set search_path = public, pg_temp
as $$
  select p.amount - coalesce((select sum(a.amount) from public.so_credit_alloc a where a.refund_payment_id = p.id and a.voided_at is null), 0)
    from public.so_payment p where p.id = p_refund_id and p.kind = 'refund';
$$;
comment on function public.qbo_refund_from_account(uuid) is 'qbo-sync-2e-3-2-1 이견 6(속 · grant 0): 환불의 「받아 둔 돈 몫」 = amount − Σ활성 so_credit_alloc(refund_payment_id = 환불) — so_payment_list.refund_from_account(20260925195701) · so_customer_balance.refund_from_received 과 같은 식 · ⓖ-1 가드 · ⓖ-2 차단 · 몸 · sync 가 모두 이 하나를 읽는다 · 환불이 아니면 null';

create function public.qbo_opening_refunded_block(p_alloc_id uuid) returns text
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_a public.so_payment_alloc%rowtype; v_p public.so_payment%rowtype; v_left numeric; v_ref numeric;
begin
  select * into v_a from public.so_payment_alloc a where a.id = p_alloc_id;
  if v_a.id is null then return null; end if;
  select * into v_p from public.so_payment p where p.id = v_a.payment_id;
  if v_p.id is null or v_p.kind <> 'payment' or v_p.method <> 'opening' then return null; end if;
  select coalesce(sum(public.so_payment_remaining(o.id)), 0) into v_left from public.so_payment o where o.customer_id = v_p.customer_id and o.currency_id = v_p.currency_id and o.kind = 'payment' and o.method = 'opening' and o.status = 'active';
  select coalesce(sum(public.qbo_refund_from_account(r.id)), 0) into v_ref from public.so_payment r where r.customer_id = v_p.customer_id and r.currency_id = v_p.currency_id and r.kind = 'refund' and r.status = 'active';
  if v_left - v_ref >= 0 then return null; end if;                                                                                      -- 남은 합(이 붙임을 이미 뺀 값) − 환불 account 몫 < 0 = 환불된 이월 돈을 썼다(ⓖ-2 (가) 「이월 돈 먼저」 와 같은 셈)
  return format('Opening credit %s uses carried-over money that was refunded already (%s %s of carried-over money is left after applications, but %s of it was refunded) — detach it in the IMS and attach other money — nothing was sent',
                coalesce(public.qbo_job_doc('opening_alloc', p_alloc_id::text)->>'doc_number', left(p_alloc_id::text, 8)), v_p.currency_code, v_left, v_ref);
end;
$$;
comment on function public.qbo_opening_refunded_block(uuid) is 'qbo-sync-2e-3-2-1 ⓖ-1 (다) · 이견 6(속 · grant 0): 이월 받아 둔 돈 붙임 하나가 환불된 돈을 쓰는지 — 그 손님 · 그 통화의 Σ so_payment_remaining(이월 · 활성)(이 붙임을 이미 뺀 값) − Σ 활성 환불의 account 몫(qbo_refund_from_account) < 0 이면 글(failed 글 · 예외 글) · 아니면 null · qbo_opening_alloc_sync(일감을 failed 로) · qbo_opening_credit_body(예외) 가 읽는다 · 11-08 실측 7 손님 모두 0.00 = 새 실패 0';

create function public.qbo_refund_label(p public.so_payment) returns text
  language sql immutable
as $$ select coalesce(nullif(btrim(coalesce(p.reference, '')), ''), 'Refund ' || p.paid_on::text || ' ' || p.amount::text) $$;
comment on function public.qbo_refund_label(public.so_payment) is 'qbo-sync-2e-3-2-1(속 · grant 0): 환불의 이름표 = reference · 없으면 「Refund <결제일> <금액>」(결제 몸의 v_label 꼴) — 글 · doc · unknown 열쇠가 같은 이름을 쓴다';

create function public.qbo_refund_block(p_refund_id uuid) returns text
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_p public.so_payment%rowtype; v_from numeric; v_base text := coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD');
begin
  select * into v_p from public.so_payment p where p.id = p_refund_id;
  if v_p.id is null or v_p.kind <> 'refund' then return null; end if;
  if nullif(btrim(coalesce(v_p.currency_code, '')), '') is null then return format('Refund %s has no currency code — nothing was sent', public.qbo_refund_label(v_p)); end if;
  if v_p.currency_code <> v_base then return format('Refund %s is in %s — refunds in a foreign currency are not sent to QuickBooks yet — nothing was sent', public.qbo_refund_label(v_p), v_p.currency_code); end if;   -- 이견 5: 환율 · A/R USD 는 sandbox 안 한 것
  v_from := public.qbo_refund_from_account(v_p.id);
  if v_from > 0 then
    return format('Refund %s pays %s %s from money on account — refunds from money on account are not sent to QuickBooks yet, so this refund waits as a whole (its credit-note part %s is not sent alone) — nothing was sent', public.qbo_refund_label(v_p), v_p.currency_code, v_from, v_p.amount - v_from);   -- ⓖ-2: 반쪽만 보내지 않는다
  end if;
  return null;
end;
$$;
comment on function public.qbo_refund_block(uuid) is 'qbo-sync-2e-3-2-1 ⓖ-2 · 이견 3 · 5(속 · grant 0): 환불을 QuickBooks 로 못 보내는 까닭 글 — 통화 없음 · 통화 ≠ 기본 통화(inv_config base_currency) · 받아 둔 돈 몫 > 0(qbo_refund_from_account) · 아니면 null · qbo_refund_sync 는 이 글로 일감을 처음부터 failed 로 · 몸 둘은 예외로 — 컷 조건(ⓖ-3 · 4 · 5)은 여기 없다(sync 만 · Retry 가 몸을 다시 돌려도 「Send」 가 되도록)';

create function public.qbo_refund_purchase_head(p_refund_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_p public.so_payment%rowtype; v_c public.customer%rowtype; v_label text; v_cust_ref text; v_dep text; v_ar_code text; v_ar text; v_rule public.ref_tax_rule%rowtype; v_tax_ref text; v_doc text;
        v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}';
begin
  select * into v_p from public.so_payment p where p.id = p_refund_id;
  if v_p.id is null then raise exception 'No IMS refund % — nothing was sent', p_refund_id; end if;
  v_label := public.qbo_refund_label(v_p);
  if v_p.kind <> 'refund' then raise exception 'Payment % is not a refund — it goes to QuickBooks as a Payment, not as an expense — nothing was sent', v_label; end if;
  if nullif(btrim(coalesce(v_p.currency_code, '')), '') is null then raise exception 'Refund % has no currency code — nothing was sent', v_label; end if;
  -- EntityRef · 줄 CustomerRef = 환불 손님(돈의 주인 · so_payment.customer_id) 짝 · 없으면 needs(손님 일감은 claim 이 쌓는다)
  select * into v_c from public.customer c where c.id = v_p.customer_id;
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_p.customer_id::text;
  if v_cust_ref is null then v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_p.customer_id::text, 'name', v_c.name); end if;
  -- AccountRef = 환불에 적힌 정산 계좌 그대로(qbo_account_ref 가 거부 글 · 결제 Deposit To 와 같은 길) · 줄 AccountRef = 손님의 A/R 계정(customer.ar_account_code · 비면 customer_default_ar_account_code) 짝 — 이견 5
  v_dep := public.qbo_account_ref(v_p.account_code, 'account of refund ' || v_label);
  v_ar_code := coalesce(nullif(btrim(coalesce(v_c.ar_account_code, '')), ''), (select c.value from public.inv_config c where c.key = 'customer_default_ar_account_code'));
  v_ar := public.qbo_account_ref(v_ar_code, 'receivables account of customer ' || v_c.name);
  -- ⓖ-8: 세금 = Out of Scope (Purchase) 규칙의 짝(TaxCodeRef) · 번호를 박지 않는다 · 짝 없으면 failed(짝이 서면 qbo_link_set → qbo_refund_requeue 가 되살린다)
  select * into v_rule from public.ref_tax_rule r where r.direction = 'purchase' and r.name ilike 'Out of Scope%' order by r.is_active desc, r.name limit 1;
  if v_rule.id is null then raise exception 'IMS has no "Out of Scope" purchase tax rule — add it under Settings → Reference Book first — nothing was sent'; end if;
  select l.qbo_id into v_tax_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_rule.id::text;
  if v_tax_ref is null then raise exception 'Tax rule "%" has no QuickBooks tax code — link it under Settings → QuickBooks matching — nothing was sent', v_rule.name; end if;
  v_doc := nullif(btrim(coalesce(v_p.reference, '')), '');
  if v_doc is not null and length(v_doc) > 21 then v_warn := array_append(v_warn, format('reference "%s" cut to 21 characters for QuickBooks', v_doc)); v_doc := left(v_doc, 21); end if;
  return jsonb_build_object('label', v_label, 'customer_id', v_p.customer_id, 'customer_name', v_c.name, 'cust_ref', v_cust_ref, 'needs', v_needs, 'warnings', to_jsonb(v_warn), 'doc_number', v_doc,
    'head', jsonb_strip_nulls(jsonb_build_object('PaymentType', 'Cash', 'AccountRef', jsonb_build_object('value', v_dep),
              'EntityRef', case when v_cust_ref is not null then jsonb_build_object('value', v_cust_ref, 'type', 'Customer') end,
              'TxnDate', v_p.paid_on, 'CurrencyRef', jsonb_build_object('value', v_p.currency_code), 'GlobalTaxCalculation', 'NotApplicable', 'DocNumber', v_doc)),
    'detail', jsonb_strip_nulls(jsonb_build_object('AccountRef', jsonb_build_object('value', v_ar), 'CustomerRef', case when v_cust_ref is not null then jsonb_build_object('value', v_cust_ref) end, 'TaxCodeRef', jsonb_build_object('value', v_tax_ref))));
end;
$$;
comment on function public.qbo_refund_purchase_head(uuid) is 'qbo-sync-2e-3-2-1 이견 5 · 10 · ⓖ-8(속 · grant 0): 환불 Purchase 의 머리와 줄 detail — PaymentType Cash · AccountRef = 환불 account_code 짝 · EntityRef = 환불 손님 짝(없으면 needs) · TxnDate = paid_on · CurrencyRef · GlobalTaxCalculation NotApplicable · DocNumber = reference 21 자 / detail = A/R(customer.ar_account_code 짝) + CustomerRef + TaxCodeRef(Out of Scope (Purchase) 규칙 짝 · 번호 안 박음) · 만들기 몸과 void 몸이 함께 읽는다(sandbox 2-a)';

create function public.qbo_refund_credit_lines(p_refund_id uuid, p_cust_ref text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_p public.so_payment%rowtype; r record; w record; v_tc public.qbo_txn%rowtype; v_j public.qbo_job%rowtype; v_store_ref text; v_store_parent text;
        v_cov numeric := 0; v_nums text[] := '{}'; v_checks jsonb := '[]'::jsonb; v_lines jsonb := '[]'::jsonb; v_wait uuid; v_wait_doc text; v_wait_reason text; v_warn text[] := '{}';
begin
  select * into v_p from public.so_payment p where p.id = p_refund_id;
  for r in select a.amount, c.id as credit_id, c.credit_number, public.so_credit_store(c.id) as store_id
             from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id where a.refund_payment_id = p_refund_id and a.voided_at is null order by c.credit_number, a.created_at, a.id loop
    -- 이견 12: CreditMemo 는 매장(935) 에 서 있다 — 환불 손님(돈의 주인)과 다르면 QBO 가 둘을 잇지 못한다 · 빠져나오는 길 = 매장이 QBO 하위 손님(qbo_entity.parent_id)이면 경고만(2e-3-1 꼴)
    if p_cust_ref is not null and r.store_id is distinct from v_p.customer_id then
      select l.qbo_id into v_store_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = r.store_id::text;
      select e.parent_id into v_store_parent from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Customer' and e.qbo_id = v_store_ref;
      if v_store_parent is null or v_store_parent <> p_cust_ref then
        raise exception 'Refund % belongs to customer % but credit note % was issued to store % — in QuickBooks the credit memo is on the store: make the store a sub-customer (bill with parent) of that customer, refresh the customer list under Settings → QuickBooks matching, then retry — nothing was sent',
          public.qbo_refund_label(v_p), (select c.name from public.customer c where c.id = v_p.customer_id), r.credit_number, (select c.name from public.customer c where c.id = r.store_id);
      end if;
      v_warn := array_append(v_warn, format('credit note %s is on store %s, a QuickBooks sub-customer of %s', r.credit_number, (select c.name from public.customer c where c.id = r.store_id), (select c.name from public.customer c where c.id = v_p.customer_id)));
    end if;
    -- 기다림 사슬: 크레딧 노트가 QBO 에 선 뒤(qbo_txn credit) · 일감 없음 · skipped 는 failed 글 · 첫 미발송 하나에 wait(claim ② 가 sent 때 풀면 다음 바퀴에 다시 본다)
    select * into v_tc from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'credit' and t.ims_id = r.credit_id::text and t.voided_at is null;
    if v_tc.id is null then
      select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'credit' and j.ims_kind = 'credit' and j.ims_id = r.credit_id::text order by j.created_at desc, j.id desc limit 1;
      if v_j.id is null then raise exception 'Credit note % has no QuickBooks job — send it first — nothing was sent', r.credit_number; end if;
      if v_j.state = 'skipped' then raise exception 'Credit note % was skipped — skip this refund too, or retry the credit note first — nothing was sent', r.credit_number; end if;
      if v_j.state = 'sent' then raise exception 'Credit note % job is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', r.credit_number; end if;
      if v_wait is null then v_wait := v_j.id; v_wait_doc := r.credit_number; v_wait_reason := format('waiting for credit note %s to reach QuickBooks first', r.credit_number); end if;
    else
      v_checks := v_checks || jsonb_build_object('txn_type', 'CreditMemo', 'credit_number', r.credit_number, 'qbo_creditmemo_id', v_tc.qbo_id, 'amount', r.amount);
      v_lines := v_lines || jsonb_build_object('Amount', r.amount, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_tc.qbo_id, 'TxnType', 'CreditMemo')));
      if v_wait is null then                                                                                                           -- 이견 11(1013 꼴): 같은 크레딧 노트의 열린 void 일감(credit_apply_void · 다른 환불의 refund_apply_void) 뒤에 — 1b 가드(RemainingCredit ≥ 몫)가 void 뒤에 통과하도록
        for w in select j.id, j.kind, j.state from public.qbo_job j
                  where j.realm_id = v_realm and j.state not in ('sent', 'skipped')
                    and ((j.kind = 'credit_apply_void' and exists (select 1 from public.so_credit_alloc a2 where a2.id::text = j.ims_id and a2.credit_id = r.credit_id))
                      or (j.kind = 'refund_apply_void' and j.ims_id <> p_refund_id::text and exists (select 1 from public.so_credit_alloc a3 where a3.refund_payment_id::text = j.ims_id and a3.credit_id = r.credit_id)))
                  order by j.created_at, j.id limit 1 loop
          v_wait := w.id; v_wait_doc := r.credit_number;
          v_wait_reason := format('waiting for the void of %s on credit note %s to reach QuickBooks first (that job is %s%s)', case w.kind when 'credit_apply_void' then 'a credit application' else 'another refund' end, r.credit_number, w.state,
                                  case when w.state = 'failed' then ' — retry or skip it first' when w.state = 'unknown' then ' — check QuickBooks and retry it with a note' else '' end);
        end loop;
      end if;
    end if;
    v_cov := v_cov + r.amount; v_nums := array_append(v_nums, r.credit_number);
  end loop;
  return jsonb_build_object('covered', v_cov, 'count', coalesce(array_length(v_nums, 1), 0), 'numbers', array_to_string(v_nums, ', '), 'checks', v_checks, 'pay_lines', v_lines,
                            'wait_job', v_wait, 'wait_doc', v_wait_doc, 'wait_reason', v_wait_reason, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.qbo_refund_credit_lines(uuid, text) is 'qbo-sync-2e-3-2-1 이견 11 · 12(속 · grant 0): 환불이 갚은 크레딧 노트(활성 so_credit_alloc.refund_payment_id)마다 — 매장 ≠ 환불 손님 울타리(QBO 하위 손님이면 경고) · 크레딧 노트가 QBO 에 선 뒤(없으면 wait_job = credit 일감 · 일감 없음 · skipped · sent-무거래 는 예외) · 같은 크레딧 노트의 열린 void 일감 뒤(1013 꼴) · 돌려주는 것 = { covered(몫 합) · count · numbers · checks[{txn_type CreditMemo …}] · pay_lines(0 원 Payment 의 CreditMemo 줄) · wait_job · wait_doc · wait_reason · warnings } · 몸 둘이 함께 읽는다';

-- ═══ ③ 몸 넷 ═══
create function public.qbo_refund_body(p_refund_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_p public.so_payment%rowtype; v_block text; v_h jsonb; v_cl jsonb; v_line jsonb; v_cov numeric;
begin
  select * into v_p from public.so_payment p where p.id = p_refund_id;
  if v_p.id is null then raise exception 'No IMS refund % — nothing was sent', p_refund_id; end if;
  if v_p.kind <> 'refund' then raise exception 'Payment % is not a refund — it goes to QuickBooks as a Payment, not as an expense — nothing was sent', public.qbo_refund_label(v_p); end if;
  if v_p.status <> 'active' then raise exception 'Refund % is voided — nothing to send (a void job takes care of QuickBooks) — nothing was sent', public.qbo_refund_label(v_p); end if;
  v_block := public.qbo_refund_block(v_p.id);                                                                                         -- ⓖ-2 · 이견 5(컷은 보지 않는다 — 이견 3)
  if v_block is not null then raise exception '%', v_block; end if;
  v_h := public.qbo_refund_purchase_head(v_p.id);
  v_cl := public.qbo_refund_credit_lines(v_p.id, v_h->>'cust_ref');
  if (v_cl->>'count')::int = 0 then raise exception 'Refund % has no credit note applied — nothing was sent', v_h->>'label'; end if;
  v_cov := (v_cl->>'covered')::numeric;
  -- sandbox 2-a · 2-c: 줄 하나 = A/R 몫 합(크레딧 노트 몫) · AccountBasedExpenseLineDetail{ AccountRef A/R · CustomerRef · TaxCodeRef Out of Scope } — 이월 몫(Customer Credits 줄) · 컷 뒤 결제 몫은 따로 차수(ⓖ-2)
  v_line := jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', 1, 'Amount', v_cov,
              'Description', 'Refund of credit note' || case when (v_cl->>'count')::int > 1 then 's ' else ' ' end || (v_cl->>'numbers'), 'AccountBasedExpenseLineDetail', v_h->'detail');
  return jsonb_build_object('kind', 'refund', 'ims_kind', 'refund', 'ims_id', v_p.id::text, 'name', v_h->>'label', 'doc_number', v_h->>'doc_number', 'customer_id', v_p.customer_id,
    'body', (v_h->'head') || jsonb_build_object('PrivateNote', 'IMS refund ' || v_p.id::text, 'Line', jsonb_build_array(v_line)),
    'needs', v_h->'needs', 'wait_job', v_cl->'wait_job', 'wait_invoice', v_cl->'wait_doc', 'wait_reason', v_cl->'wait_reason', 'warnings', (v_h->'warnings') || (v_cl->'warnings'), 'line_count', 1,
    'totals', jsonb_build_object('amount', v_p.amount, 'credit_covered', v_cov, 'from_account', v_p.amount - v_cov, 'credit_numbers', v_cl->>'numbers'),
    'fingerprint', null, 'check_lines', v_cl->'checks',
    'lookup', jsonb_build_object('customer_ref', v_h->>'cust_ref', 'txn_date', v_p.paid_on, 'total_amt', v_cov, 'private_note', 'IMS refund ' || v_p.id::text));
end;
$$;
comment on function public.qbo_refund_body(uuid) is 'qbo-sync-2e-3-2-1 판정 1056 ~ 1058 · 이견 3 (가) · ⓖ-2 · ⓖ-6 · ⓖ-8(속 · grant 0 · claim · preview 가 부른다): 환불 → QBO Purchase(Expense) 만들기 몸 — sandbox 2-a 꼴 · PaymentType Cash · AccountRef 정산 계좌 · EntityRef 환불 손님 · TxnDate paid_on · GlobalTaxCalculation NotApplicable · DocNumber reference · PrivateNote 「IMS refund <uuid>」 · 줄 하나 = 크레딧 노트 몫 합(A/R + CustomerRef + Out of Scope (Purchase) 짝) · voided · 통화 ≠ 기본 · 받아 둔 돈 몫 > 0 · 매장 ≠ 손님 · 짝 없음은 예외(failed) · 크레딧 노트가 QBO 에 선 뒤(wait_job) · 돌려주는 것 = { body · needs · wait_job · wait_invoice(크레딧 번호) · wait_reason · warnings · totals · check_lines(CreditMemo) · lookup(unknown 열쇠 = PrivateNote · EntityRef · TxnDate · TotalAmt) · fingerprint null }';

create function public.qbo_refund_apply_body(p_refund_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_p public.so_payment%rowtype; v_block text; v_h jsonb; v_cl jsonb; v_tp public.qbo_txn%rowtype; v_j public.qbo_job%rowtype; v_wait uuid; v_wait_doc text; v_wait_reason text;
        v_lines jsonb := '[]'::jsonb; v_checks jsonb := '[]'::jsonb; v_cov numeric;
begin
  select * into v_p from public.so_payment p where p.id = p_refund_id;
  if v_p.id is null then raise exception 'No IMS refund % — nothing was sent', p_refund_id; end if;
  if v_p.kind <> 'refund' then raise exception 'Payment % is not a refund — it goes to QuickBooks as a Payment, not as an expense — nothing was sent', public.qbo_refund_label(v_p); end if;
  if v_p.status <> 'active' then raise exception 'Refund % is voided — nothing to send (a void job takes care of QuickBooks) — nothing was sent', public.qbo_refund_label(v_p); end if;
  v_block := public.qbo_refund_block(v_p.id);
  if v_block is not null then raise exception '%', v_block; end if;
  v_h := public.qbo_refund_purchase_head(v_p.id);                                                                                     -- 손님 짝(needs) · 이름표 — 계정 · 세금 짝도 같은 울타리
  -- 기다림: 자기 Purchase(refund 일감) 먼저 → 크레딧 노트마다(qbo_refund_credit_lines) · 첫 미발송 하나에 wait
  select * into v_tp from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'refund' and t.ims_id = v_p.id::text and t.voided_at is null;
  if v_tp.id is null then
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'refund' and j.ims_kind = 'refund' and j.ims_id = v_p.id::text order by j.created_at desc, j.id desc limit 1;
    if v_j.id is null then raise exception 'Refund % has no QuickBooks job for its expense — check qbo_job by hand — nothing was sent', v_h->>'label'; end if;
    if v_j.state = 'skipped' then raise exception 'The expense of refund % was skipped — skip this one too, or retry that job first — nothing was sent', v_h->>'label'; end if;
    if v_j.state = 'sent' then raise exception 'The expense job of refund % is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', v_h->>'label'; end if;
    v_wait := v_j.id; v_wait_doc := v_h->>'label'; v_wait_reason := format('waiting for the expense of refund %s to reach QuickBooks first', v_h->>'label');
  end if;
  v_cl := public.qbo_refund_credit_lines(v_p.id, v_h->>'cust_ref');
  if (v_cl->>'count')::int = 0 then raise exception 'Refund % has no credit note applied — nothing was sent', v_h->>'label'; end if;
  v_cov := (v_cl->>'covered')::numeric;
  if v_wait is null and nullif(v_cl->>'wait_job', '') is not null then v_wait := (v_cl->>'wait_job')::uuid; v_wait_doc := v_cl->>'wait_doc'; v_wait_reason := v_cl->>'wait_reason'; end if;
  if v_wait is null then                                                                                                               -- sandbox 2-a · sandbox-2 걸음 25: Expense 줄 하나(A/R 몫 합 · TxnType "Expense") + CreditMemo 줄마다
    v_lines := jsonb_build_array(jsonb_build_object('Amount', v_cov, 'LinkedTxn', jsonb_build_array(jsonb_build_object('TxnId', v_tp.qbo_id, 'TxnType', 'Expense')))) || (v_cl->'pay_lines');
    v_checks := jsonb_build_array(jsonb_build_object('txn_type', 'Expense', 'refund', v_h->>'label', 'qbo_purchase_id', v_tp.qbo_id, 'amount', v_cov)) || (v_cl->'checks');
  end if;
  return jsonb_build_object('kind', 'refund_apply', 'ims_kind', 'refund', 'ims_id', v_p.id::text, 'name', v_h->>'label', 'doc_number', v_h->>'label', 'customer_id', v_p.customer_id,
    'body', jsonb_strip_nulls(jsonb_build_object('CustomerRef', case when v_h->>'cust_ref' is null then null else jsonb_build_object('value', v_h->>'cust_ref') end,
              'TxnDate', v_p.paid_on, 'TotalAmt', 0, 'CurrencyRef', jsonb_build_object('value', v_p.currency_code), 'PrivateNote', 'IMS refund applied ' || v_p.id::text, 'Line', v_lines)),   -- PaymentMethodRef · DepositToAccountRef · PaymentRefNum 없음(C-5″ · 2-a)
    'needs', v_h->'needs', 'wait_job', v_wait, 'wait_invoice', v_wait_doc, 'wait_reason', v_wait_reason, 'warnings', (v_h->'warnings') || (v_cl->'warnings'), 'line_count', jsonb_array_length(v_lines),
    'totals', jsonb_build_object('amount', 0, 'applied', v_cov, 'unapplied', 0, 'credit_numbers', v_cl->>'numbers'),
    'fingerprint', null, 'check_lines', v_checks,
    'lookup', jsonb_build_object('customer_ref', v_h->>'cust_ref', 'txn_date', v_p.paid_on, 'total_amt', 0, 'private_note', 'IMS refund applied ' || v_p.id::text));
end;
$$;
comment on function public.qbo_refund_apply_body(uuid) is 'qbo-sync-2e-3-2-1 ⓖ-6 · 이견 11(속 · grant 0 · claim · preview 가 부른다): 환불 하나 → QBO 0 원 Payment 한 장(Purchase 와 CreditMemo 들을 잇는다) — CustomerRef = 환불 손님 짝 · TxnDate paid_on · TotalAmt 0 · PrivateNote 「IMS refund applied <uuid>」 · Line = Expense(qbo_txn refund 의 Purchase · A/R 몫 합 · TxnType "Expense") + CreditMemo 줄마다 그 몫(sandbox-2 걸음 25) · 기다림 = 자기 Purchase(refund 일감) → 크레딧 노트마다 → 같은 크레딧의 열린 void · 돌려주는 것 = { body · needs · wait_job · wait_invoice · wait_reason · warnings · totals · check_lines[{txn_type Expense|CreditMemo …}] · lookup · fingerprint null }';

create function public.qbo_refund_apply_void_body(p_refund_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_p public.so_payment%rowtype; v_t public.qbo_txn%rowtype; v_label text;
begin
  select * into v_p from public.so_payment p where p.id = p_refund_id;
  if v_p.id is null or v_p.kind <> 'refund' then raise exception 'No IMS refund % — nothing was sent', p_refund_id; end if;
  v_label := public.qbo_refund_label(v_p);
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'refund_apply' and t.ims_id = p_refund_id::text;
  if v_t.id is null then raise exception 'The zero payment of refund % was never sent to QuickBooks — nothing to void', v_label; end if;
  if v_t.voided_at is not null then raise exception 'The zero payment of refund % (QuickBooks payment #%) is already voided — nothing was sent', v_label, v_t.qbo_id; end if;
  return jsonb_build_object('kind', 'refund_apply_void', 'ims_kind', 'refund', 'ims_id', p_refund_id::text, 'name', v_label, 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id,
    'body', jsonb_strip_nulls(jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token, 'sparse', true)), 'needs', '[]'::jsonb,
    'warnings', case when v_t.sync_token is null then '["no SyncToken on file — the sender reads the payment first"]'::jsonb else '[]'::jsonb end,
    'lookup', jsonb_build_object('qbo_id', v_t.qbo_id, 'private_note', 'IMS refund applied ' || p_refund_id::text));
end;
$$;
comment on function public.qbo_refund_apply_void_body(uuid) is 'qbo-sync-2e-3-2-1 ⓖ-7(속 · grant 0): 환불의 0 원 Payment void 몸 — qbo_txn refund_apply 의 Id · SyncToken · sparse true(EF 는 payment?operation=update&include=void · 2e-2 credit_apply_void 와 같은 길) · 보낸 적 없음 · 이미 void 면 예외(failed) · 순서 = Purchase void(refund_void) 보다 먼저(sync 가 blocked_by 로 세운다)';

create function public.qbo_refund_void_body(p_refund_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_p public.so_payment%rowtype; v_t public.qbo_txn%rowtype; v_ta public.qbo_txn%rowtype; v_h jsonb; v_label text; v_warn jsonb;
begin
  select * into v_p from public.so_payment p where p.id = p_refund_id;
  if v_p.id is null or v_p.kind <> 'refund' then raise exception 'No IMS refund % — nothing was sent', p_refund_id; end if;
  v_label := public.qbo_refund_label(v_p);
  select * into v_t from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'refund' and t.ims_id = p_refund_id::text;
  if v_t.id is null then raise exception 'Refund % was never sent to QuickBooks — nothing to void', v_label; end if;
  if v_t.voided_at is not null then raise exception 'Refund % (QuickBooks expense #%) is already voided — nothing was sent', v_label, v_t.qbo_id; end if;
  v_h := public.qbo_refund_purchase_head(v_p.id);
  if v_h->>'cust_ref' is null then raise exception 'Refund % has no QuickBooks customer match — the expense cannot be rewritten — nothing was sent', v_label; end if;
  v_warn := v_h->'warnings';
  if v_t.sync_token is null then v_warn := v_warn || '"no SyncToken on file — the sender reads the expense first"'::jsonb; end if;
  select * into v_ta from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'refund_apply' and t.ims_id = p_refund_id::text and t.voided_at is null;
  if v_ta.id is not null then v_warn := v_warn || to_jsonb(format('the zero payment #%s that links this expense is still standing on file — it is voided first (ⓖ-7)', v_ta.qbo_id)); end if;
  -- ⓖ-7 · 이견 9: Full update 꼴 전부(Id · SyncToken · 머리 · 줄 Amount 0 · PrivateNote 「Voided - 」 머리) — EF 가 GET purchase/<id> 로 SyncToken 과 Line(줄 Id · LineNum 은 QBO 가 매긴 것 · Amount 0)을 읽은 것으로 바꾼다 · 나머지는 이 몸 그대로
  return jsonb_build_object('kind', 'refund_void', 'ims_kind', 'refund', 'ims_id', p_refund_id::text, 'name', v_label, 'doc_number', v_t.doc_number, 'qbo_id', v_t.qbo_id, 'sync_token', v_t.sync_token,
    'body', jsonb_strip_nulls((v_h->'head') || jsonb_build_object('Id', v_t.qbo_id, 'SyncToken', v_t.sync_token, 'PrivateNote', 'Voided - IMS refund ' || p_refund_id::text,
              'Line', jsonb_build_array(jsonb_build_object('DetailType', 'AccountBasedExpenseLineDetail', 'LineNum', 1, 'Amount', 0, 'Description', 'Voided', 'AccountBasedExpenseLineDetail', v_h->'detail')))),
    'needs', '[]'::jsonb, 'warnings', v_warn,
    'lookup', jsonb_build_object('qbo_id', v_t.qbo_id, 'private_note', 'IMS refund ' || p_refund_id::text));
end;
$$;
comment on function public.qbo_refund_void_body(uuid) is 'qbo-sync-2e-3-2-1 ⓖ-7 · 이견 4 · 9(속 · grant 0): 환불 Purchase 되돌리기 몸 = Full update void 꼴(sandbox 2-d · Delete 없음 · operation 없음) — Id · SyncToken(qbo_txn 의 것 · 낡았을 수 있다 → 경고) · 머리(qbo_refund_purchase_head) · 줄 하나 Amount 0 · PrivateNote 「Voided - IMS refund <uuid>」(금액 0 만으로는 Voided 가 아니다 · P2 a) · EF 가 GET 으로 SyncToken · Line 을 읽은 것으로 바꾼다 · 보낸 적 없음 · 이미 void 면 예외 · 순서 = 0 원 Payment void 뒤(sync 가 blocked_by 로)';

-- ═══ ④ 상태 맞추기(트리거 둘 · done 의 reconcile · 백필 · requeue 가 부른다) ═══
create function public.qbo_refund_sync(p_refund_id uuid, p_by uuid) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_p public.so_payment%rowtype; v_active boolean; v_err text;
        v_tp public.qbo_txn%rowtype; v_ta public.qbo_txn%rowtype; v_rj public.qbo_job%rowtype; v_rvj public.qbo_job%rowtype; v_aj public.qbo_job%rowtype; v_avj public.qbo_job%rowtype; v_id uuid; v_act text := 'none';
        v_cut constant date := date '2026-10-30';   -- 1056 · ⓖ-3: 컷오버 날 = 결제일(paid_on) 기준 고정 · qbo_send_since(11-02) 와 다르다 · created_at 으로 거르지 않는다(컷 전 8 건의 created_at 은 11-04 ~ 05)
        v_new constant date := date '2026-11-08';   -- ⓖ-4 · 이견 2: 이 차수가 선 날(토론토) — 그 뒤 적은(created_at) 환불만 컷 전 날짜를 사람이 본다(failed 「Dated before the cut-over …」) · 8 건은 그 전 created 라 일감 0(ⓖ-5)
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  select * into v_p from public.so_payment p where p.id = p_refund_id;
  if v_p.id is null or v_p.kind <> 'refund' then return jsonb_build_object('action', 'not_applicable'); end if;                     -- 결제는 qbo_payment_sync 의 몫(무변)
  v_active := v_p.status = 'active';
  select * into v_tp from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'refund'       and t.ims_id = v_p.id::text;
  select * into v_ta from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'refund_apply' and t.ims_id = v_p.id::text;
  select * into v_rj  from public.qbo_job j where j.realm_id = v_realm and j.kind = 'refund'            and j.ims_kind = 'refund' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_rvj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'refund_void'       and j.ims_kind = 'refund' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_aj  from public.qbo_job j where j.realm_id = v_realm and j.kind = 'refund_apply'      and j.ims_kind = 'refund' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_avj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'refund_apply_void' and j.ims_kind = 'refund' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_tp.id is null then                                                                                                               -- Purchase 를 보낸 적 없다
    if v_active then
      if v_p.paid_on < v_cut and (v_p.created_at at time zone 'America/Toronto')::date < v_new then return jsonb_build_object('action', 'before_cut'); end if;   -- ⓖ-5(990): 컷 전 환불은 북키퍼가 QBO 에 손으로 넣었다 — 일감 0
      if v_rj.id is null then
        v_err := coalesce(public.qbo_refund_block(v_p.id), case when v_p.paid_on < v_cut then 'Dated before the cut-over (2026-10-30) — check QuickBooks, then Retry or Skip' end);   -- ⓖ-2 · 이견 5 · ⓖ-4: 처음부터 failed(cron 이 안 집는다 · 화면 Failed 에 바로) · Retry 가 Send
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, 'refund', 'refund', v_p.id::text, case when v_err is null then 'queued' else 'failed' end, v_err, p_by)
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
        if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'refund' and j.ims_kind = 'refund' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
        v_rj.id := v_id; v_act := case when v_err is null then 'queued' else 'failed' end;
        if v_aj.id is not null and v_aj.state = 'blocked' then update public.qbo_job j set blocked_by = v_rj.id where j.id = v_aj.id; end if;   -- apply 가 옛(끝난) 일감 뒤에 서 있었다면 새 일감 뒤로
      end if;
      if v_aj.id is null then                                                                                                           -- ⓖ-6: 0 원 Payment 는 만들 때부터 Purchase 일감 뒤(claim ② 가 sent 때 푼다)
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'refund_apply', 'refund', v_p.id::text, 'blocked', v_rj.id, p_by, 'waits for the expense of this refund to reach QuickBooks first')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        if v_act = 'none' then v_act := 'queued'; end if;
      end if;
    else
      if v_rj.id is not null and v_rj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'refund voided before sending'), 2000), updated_by = p_by where j.id = v_rj.id;
        v_act := 'skipped';
      end if;
      if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'refund voided before sending'), 2000), updated_by = p_by where j.id = v_aj.id;
        v_act := 'skipped';
      end if;
      if v_rj.id is not null and v_rj.state in ('sending', 'unknown') and v_rvj.id is null then                                       -- 닿았는지 모른다 → void 를 그 일감 뒤에(결제 꼴)
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'refund_void', 'refund', v_p.id::text, 'blocked', v_rj.id, p_by, 'voided while sending — void after the send settles')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'void_after_send';
      elsif v_p.paid_on < v_cut and v_rvj.id is null then                                                                               -- ⓖ-5 · 이견 4: 컷 전 환불(QBO 에 손으로 들어간 것)의 void — 알림 = refund_void 일감을 failed 로(화면 Failed · Retry 는 「not standing」 으로 거부 · 사람이 QBO 에서 void 한 뒤 Skip)
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, 'refund_void', 'refund', v_p.id::text, 'failed', 'This refund was entered in QuickBooks by hand before the cut-over (2026-10-30) — void it there too (if it is there), then skip this job', p_by)
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'hand_void_alert';
      end if;
    end if;
  elsif v_tp.voided_at is null then                                                                                                     -- Purchase 가 QBO 에 서 있다
    if v_ta.id is null then                                                                                                             -- 0 원 Payment 는 아직
      if v_active then
        if v_aj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'refund_apply', 'refund', v_p.id::text, 'queued', p_by)
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          v_act := 'queued';
        end if;
      else
        if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
          update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'refund voided — only the void goes'), 2000), updated_by = p_by where j.id = v_aj.id;
        end if;
        if v_aj.id is not null and v_aj.state in ('sending', 'unknown') then                                                          -- 0 원 Payment 가 나가는 중 → 그 뒤에 apply_void → 그 뒤에 refund_void(ⓖ-7 순서)
          if v_avj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'refund_apply_void', 'refund', v_p.id::text, 'blocked', v_aj.id, p_by, 'voided while sending — void after the send settles')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
            if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'refund_apply_void' and j.ims_kind = 'refund' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
            v_avj.id := v_id;
          end if;
          if v_rvj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'refund_void', 'refund', v_p.id::text, 'blocked', v_avj.id, p_by, 'void the expense after the zero payment is voided')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          end if;
          v_act := 'void_after_send';
        else
          if v_rvj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'refund_void', 'refund', v_p.id::text, 'queued', p_by, 'refund voided — void the expense in QuickBooks')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          end if;
          v_act := 'void';
        end if;
      end if;
    elsif v_ta.voided_at is null then                                                                                                   -- 둘 다 서 있다
      if v_active then
        v_act := 'same';                                                                                                                -- 환불 행은 바뀌지 않는다 — 지문 · 다시 보내기 없음(1011 꼴)
      else                                                                                                                              -- ⓖ-7: 0 원 Payment void 먼저 → Purchase void(blocked_by)
        if v_avj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'refund_apply_void', 'refund', v_p.id::text, 'queued', p_by, 'refund voided — void the zero payment in QuickBooks')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
          if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'refund_apply_void' and j.ims_kind = 'refund' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
          v_avj.id := v_id;
        end if;
        if v_rvj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'refund_void', 'refund', v_p.id::text, 'blocked', v_avj.id, p_by, 'void the expense after the zero payment is voided')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        end if;
        v_act := 'void';
      end if;
    else                                                                                                                                -- 0 원 Payment 는 QBO 쪽 void 됨 · Purchase 는 서 있다
      if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_aj.id;
        v_act := 'skipped';
      end if;
      if not v_active then
        if v_rvj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'refund_void', 'refund', v_p.id::text, 'queued', p_by, 'refund voided — void the expense in QuickBooks')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        end if;
        v_act := 'void';
      end if;
    end if;
  else                                                                                                                                  -- Purchase 가 QBO 쪽 void 됨(환불은 되살지 않는다 · 새 환불 = 새 행 = 새 두 장)
    if v_rj.id is not null and v_rj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_rj.id;
      v_act := 'skipped';
    end if;
    if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_aj.id;
      v_act := 'skipped';
    end if;
  end if;
  return jsonb_build_object('action', v_act);
end;
$$;
comment on function public.qbo_refund_sync(uuid, uuid) is 'qbo-sync-2e-3-2-1 이견 3 · 4 · 6 (나) · ⓖ-2 ~ ⓖ-7(속 · grant 0): 환불 하나의 QBO 일감(두 장)을 IMS 상태에 맞춘다 — 결제 · 연결 없음이면 조용히 / Purchase 보낸 적 없음: 활성 → 컷 전 ∧ 11-08 전 created 면 일감 0(ⓖ-5) · refund queued(qbo_refund_block 글 또는 컷 전 날짜면 처음부터 failed · ⓖ-2 · ⓖ-4) + refund_apply blocked_by 그것 · void → 열린 것 skipped · sending · unknown 이면 refund_void 를 그 뒤에 · 컷 전이면 refund_void failed 「entered in QuickBooks by hand …」(ⓖ-5 알림) / Purchase 서 있음 · Payment 아직: 활성 → apply queued · void → refund_void queued(apply 가 나가는 중이면 apply_void → refund_void 차례) / 둘 다 서 있음: 활성 → same · void → refund_apply_void queued + refund_void blocked_by / Payment 만 QBO 쪽 void: 열린 apply skipped · void 면 refund_void / Purchase QBO 쪽 void: 열린 것 skipped · 돌려주는 것 = { action } · 부르는 곳 = 트리거 둘(so_payment_refund_qbo · so_payment_qbo_status) · done 의 reconcile · 백필 · requeue';

create function public.qbo_job_on_refund_insert() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_by uuid := coalesce(new.created_by, new.updated_by);
begin
  begin
    perform public.qbo_refund_sync(new.id, v_by);
  exception when others then                                                                                                           -- 환불 만들기를 막지 않는다 — failed 일감으로 흔적
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff)
      select c.realm_id, 'refund', 'refund', new.id::text, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by from public.qbo_connection c where c.singleton
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
comment on function public.qbo_job_on_refund_insert() is 'qbo-sync-2e-3-2-1 이견 6 (나) · 7: so_payment AFTER INSERT(kind refund · DEFERRABLE INITIALLY DEFERRED — so_payment_refund 가 같은 커밋 안에서 붙이는 크레딧 몫(so_credit_alloc.refund_payment_id)이 다 선 뒤) → qbo_refund_sync · 오류는 삼킨다(failed 일감으로 흔적) · 트리거 so_payment_refund_qbo(파일 끝)';

-- ═══ ⑤ 백필 · 세금 짝 되살리기 ═══
create function public.qbo_refund_backfill() returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare r record; v_r jsonb; v_q int := 0; v_f int := 0; v_b int := 0;
begin
  if not exists (select 1 from public.qbo_connection c where c.singleton) then return jsonb_build_object('queued', 0, 'failed', 0, 'before_cut', 0); end if;
  for r in select p.id, coalesce(p.created_by, p.updated_by) as by_staff from public.so_payment p
            where p.kind = 'refund' and p.status = 'active'
              and not exists (select 1 from public.qbo_job j where j.ims_kind = 'refund' and j.ims_id = p.id::text)
              and not exists (select 1 from public.qbo_txn t where t.ims_kind in ('refund', 'refund_apply') and t.ims_id = p.id::text)
            order by p.paid_on, p.created_at, p.id loop
    v_r := public.qbo_refund_sync(r.id, r.by_staff);                                                                                  -- 컷(ⓖ-3 · 4 · 5) · 차단(ⓖ-2)은 sync 가 가른다 — 식 두 곳 금지
    if v_r->>'action' = 'queued' then v_q := v_q + 1; elsif v_r->>'action' = 'failed' then v_f := v_f + 1; elsif v_r->>'action' = 'before_cut' then v_b := v_b + 1; end if;
  end loop;
  return jsonb_build_object('queued', v_q, 'failed', v_f, 'before_cut', v_b);
end;
$$;
comment on function public.qbo_refund_backfill() is 'qbo-sync-2e-3-2-1 ⓖ-3 · ⓖ-5(속 · grant 0): 적용 때 한 번 — 활성 환불 중 일감(어느 상태든) · 거래 짝 없는 것마다 qbo_refund_sync(컷 · 차단은 sync 가 가른다) · 돌려주는 것 = { queued(refund queued + refund_apply blocked 짝) · failed · before_cut } · 11-08 실측 = queued 2(CR-01011 · CR-01012 몫) · before_cut 8 · 연결 없으면 0';

create function public.qbo_refund_requeue(p_by uuid) returns int
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_r record; v_n int := 0;
begin
  for v_r in select j.id from public.qbo_job j join public.so_payment p on p.id::text = j.ims_id join public.qbo_connection c on c.singleton and c.realm_id = j.realm_id
              where j.kind = 'refund' and j.ims_kind = 'refund' and j.state = 'failed' and j.last_error like 'Tax rule "%" has no QuickBooks tax code%' and p.kind = 'refund' and p.status = 'active'
                and not exists (select 1 from public.qbo_txn t where t.realm_id = j.realm_id and t.ims_kind = 'refund' and t.ims_id = j.ims_id and t.voided_at is null)
              order by j.created_at, j.id loop
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: the purchase tax rule is now matched in QuickBooks'), 2000), updated_by = p_by
     where j.id = v_r.id;
    v_n := v_n + 1;
  end loop;
  return v_n;
end;
$$;
comment on function public.qbo_refund_requeue(uuid) is 'qbo-sync-2e-3-2-1 이견 13 · ⓖ-8(속 · grant 0 · qbo_link_set 이 tax_rule Out of Scope (Purchase) 짝을 세울 때 부른다 · 1039 꼴): 세금 짝이 없어 failed 된 refund 일감(글 「Tax rule … has no QuickBooks tax code」 · 환불 active · Purchase 안 섬)을 queued 로 · 다른 까닭의 failed(ⓖ-2 · ⓖ-4)는 건드리지 않는다 · 돌려주는 것 = 되살린 수';

-- ═══ ⑥ 재발행 — opening_credit_body · opening_alloc_sync(ⓖ-1 가드) · on_payment_status(refund 가지) · link_set(tax_rule 가지) · claim · preview · doc · list · retry · done(DB 바이트 + 가지 · 같은 서명 · create or replace 라 ACL 그대로) ═══
create or replace function public.qbo_opening_credit_body (p_alloc_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_a public.so_payment_alloc%rowtype; v_p public.so_payment%rowtype; v_i public.so_invoice%rowtype; v_cust public.customer%rowtype; v_is uuid; v_cust_ref text; v_store_ref text; v_store_parent text;
        v_item text; v_rule public.ref_tax_rule%rowtype; v_tax_ref text; v_detail jsonb; v_rate_ref text; v_needs jsonb := '[]'::jsonb; v_warn text[] := '{}'; v_doc text; v_label text; v_date date; v_desc text;
        v_ti public.qbo_txn%rowtype; v_j public.qbo_job%rowtype; v_wait uuid; v_wait_doc text; v_wait_reason text; v_line jsonb; v_tax_line jsonb;
begin
  select * into v_a from public.so_payment_alloc a where a.id = p_alloc_id;
  if v_a.id is null then raise exception 'No IMS payment application % — nothing was sent', p_alloc_id; end if;
  select * into v_p from public.so_payment p where p.id = v_a.payment_id;
  if v_p.kind <> 'payment' or v_p.method <> 'opening' then raise exception 'Payment % is not money carried over from the previous system — it goes to QuickBooks as a Payment, not as an opening credit — nothing was sent', coalesce(v_p.reference, left(v_p.id::text, 8)); end if;
  select * into v_i from public.so_invoice i where i.id = v_a.invoice_id;
  v_doc := public.qbo_opening_doc_number(v_a.id); v_label := v_doc || ' → ' || v_i.invoice_number;
  if v_a.voided_at is not null then raise exception 'Opening credit % was detached — nothing to send (a void job takes care of QuickBooks) — nothing was sent', v_label; end if;
  if v_p.status <> 'active' then raise exception 'The carried-over money behind opening credit % is voided — nothing was sent', v_label; end if;
  if public.qbo_opening_refunded_block(p_alloc_id) is not null then raise exception '%', public.qbo_opening_refunded_block(p_alloc_id); end if;   -- 2e-3-2-1 ⓖ-1 (다): 환불된 이월 돈을 쓰는 붙임은 보내지 않는다(sync 가 처음부터 failed · Retry 도 여기서 다시 failed)
  if nullif(btrim(coalesce(v_p.currency_code, '')), '') is null then raise exception 'Opening credit % has no currency code — nothing was sent', v_label; end if;
  if length(v_doc) > 21 then v_warn := array_append(v_warn, format('document number %s is longer than 21 characters — sent as %s', v_doc, left(v_doc, 21))); v_doc := left(v_doc, 21); end if;
  -- 이견 4: CustomerRef = 돈의 주인(so_payment.customer_id · 786 손님 브랜치) · 짝 없으면 needs · 인보이스 매장(so_invoice_store)과 다르면 failed — 빠져나오는 길 = QBO 에서 매장이 그 손님의 하위 손님(qbo_entity.parent_id · 482 꼴)이면 경고만 · 아니면 글대로 묶고 Retry
  select * into v_cust from public.customer c where c.id = v_p.customer_id;
  v_is := public.so_invoice_store(v_i.id);
  if v_is is null then raise exception 'Invoice % has no store on record — nothing was sent', v_i.invoice_number; end if;
  select l.qbo_id into v_cust_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_p.customer_id::text;
  if v_cust_ref is null then
    v_needs := v_needs || jsonb_build_object('kind', 'customer', 'ims_id', v_p.customer_id::text, 'name', v_cust.name);
  elsif v_is <> v_p.customer_id then
    select l.qbo_id into v_store_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_is::text;
    select e.parent_id into v_store_parent from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'Customer' and e.qbo_id = v_store_ref;
    if v_store_parent is null or v_store_parent <> v_cust_ref then
      raise exception 'Opening credit % belongs to customer % but invoice % is for store % — the opening credit belongs to another customer than the invoice store: detach it, or in QuickBooks make the store a sub-customer (bill with parent) of that customer, refresh the customer list under Settings → QuickBooks matching, then retry — nothing was sent',
        v_label, v_cust.name, v_i.invoice_number, (select c.name from public.customer c where c.id = v_is);
    end if;
    v_warn := array_append(v_warn, format('invoice %s is for store %s, a QuickBooks sub-customer of %s — the credit memo is written on the parent customer', v_i.invoice_number, (select c.name from public.customer c where c.id = v_is), v_cust.name));
  end if;
  -- 이견 7: Item = qbo_link charge 「acct:<결제 계정>」(951 · 961 과 같은 열쇠 · Settings → QuickBooks matching) · 없으면 failed · 짝이 서면 qbo_link_set → qbo_opening_credit_requeue 가 되살린다
  if nullif(btrim(coalesce(v_p.account_code, '')), '') is null then raise exception 'The carried-over money behind opening credit % has no account — nothing was sent', v_label; end if;
  select l.qbo_id into v_item from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'charge' and l.ims_id = 'acct:' || v_p.account_code;
  if v_item is null then raise exception 'Opening credits on account % have no QuickBooks item — link account item "acct:%" to the Customer Credit item under Settings → QuickBooks matching; this opening credit then goes by itself — nothing was sent', v_p.account_code, v_p.account_code; end if;
  -- 이견 6: 세금 = Out of Scope(Sale) 규칙의 짝(TaxCodeRef) + TaxLine 0(2c 꼴 · TaxRateRef 는 거울 detail)
  select * into v_rule from public.ref_tax_rule r where r.direction = 'sale' and r.name ilike 'Out of Scope%' order by r.is_active desc, r.name limit 1;
  if v_rule.id is null then raise exception 'IMS has no "Out of Scope" sale tax rule — add it under Settings → Reference Book first — nothing was sent'; end if;
  select l.qbo_id into v_tax_ref from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = v_rule.id::text;
  if v_tax_ref is null then raise exception 'Tax rule "%" has no QuickBooks tax code — link it under Settings → QuickBooks matching — nothing was sent', v_rule.name; end if;
  select e.detail into v_detail from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = 'TaxCode' and e.qbo_id = v_tax_ref;
  v_rate_ref := nullif(btrim(coalesce(v_detail->'TaxRateDetail'->0->'TaxRateRef'->>'value', '')), '');
  if v_rate_ref is null then raise exception 'QuickBooks tax code #% ("%") has no tax rate on file — Settings → QuickBooks matching → Refresh list (tax codes), then retry — nothing was sent', v_tax_ref, v_rule.name; end if;
  -- 이견 8: 인보이스 뒤에 선다(인보이스가 skipped · 취소되면 CreditMemo 만 서서 손님 잔액을 줄인다) · 이월 · since 전 · 일감 없음 · skipped 는 failed 글
  select * into v_ti from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'invoice' and t.ims_id = v_i.id::text and t.voided_at is null;
  if v_ti.id is null then
    if v_i.kind = 'opening' then raise exception 'Invoice % was carried over from the previous system and has no QuickBooks match yet — match it under Settings → QuickBooks → Opening invoices; this opening credit then goes by itself — nothing was sent', v_i.invoice_number; end if;
    if not public.qbo_send_since_ok(v_i.issued_on) then raise exception 'Invoice % was issued before the QuickBooks start date and has no QuickBooks match — match it under Settings → QuickBooks → Opening invoices — nothing was sent', v_i.invoice_number; end if;
    select * into v_j from public.qbo_job j where j.realm_id = v_realm and j.kind = 'invoice' and j.ims_kind = 'invoice' and j.ims_id = v_i.id::text order by j.created_at desc, j.id desc limit 1;
    if v_j.id is null then raise exception 'Invoice % has no QuickBooks job — send the invoice first — nothing was sent', v_i.invoice_number; end if;
    if v_j.state = 'skipped' then raise exception 'Invoice % was skipped — skip this opening credit too, or retry the invoice first — nothing was sent', v_i.invoice_number; end if;
    if v_j.state = 'sent' then raise exception 'Invoice % job is sent but no QuickBooks transaction is on file — check qbo_txn by hand — nothing was sent', v_i.invoice_number; end if;
    v_wait := v_j.id; v_wait_doc := v_i.invoice_number; v_wait_reason := format('waiting for invoice %s to reach QuickBooks first', v_i.invoice_number);
  end if;
  v_date := (v_a.created_at at time zone 'America/Toronto')::date;                                                                     -- 1017 꼴: 붙인 날(토론토)
  v_desc := 'Credit on account applied to invoice ' || v_i.invoice_number;
  v_line := jsonb_build_object('DetailType', 'SalesItemLineDetail', 'LineNum', 1, 'Amount', v_a.amount, 'Description', v_desc,
              'SalesItemLineDetail', jsonb_build_object('ItemRef', jsonb_build_object('value', v_item), 'Qty', 1, 'UnitPrice', trim_scale(v_a.amount), 'TaxCodeRef', jsonb_build_object('value', v_tax_ref)));
  v_tax_line := jsonb_build_object('DetailType', 'TaxLineDetail', 'Amount', 0, 'TaxLineDetail', jsonb_build_object('TaxRateRef', jsonb_build_object('value', v_rate_ref), 'PercentBased', true, 'TaxPercent', 0, 'NetAmountTaxable', v_a.amount));
  return jsonb_build_object('kind', 'opening_credit', 'ims_kind', 'opening_alloc', 'ims_id', v_a.id::text, 'name', v_label, 'doc_number', v_doc, 'customer_id', v_p.customer_id,
    'body', jsonb_strip_nulls(jsonb_build_object(
      'DocNumber', v_doc, 'TxnDate', to_char(v_date, 'YYYY-MM-DD'),
      'CustomerRef', case when v_cust_ref is not null then jsonb_build_object('value', v_cust_ref) end,
      'CurrencyRef', jsonb_build_object('value', v_p.currency_code),
      'PrivateNote', 'IMS opening credit used ' || v_a.id::text, 'CustomerMemo', jsonb_build_object('value', v_desc),
      'GlobalTaxCalculation', 'TaxExcluded', 'Line', jsonb_build_array(v_line),
      'TxnTaxDetail', jsonb_build_object('TotalTax', 0, 'TaxLine', jsonb_build_array(v_tax_line)))),
    'needs', v_needs, 'wait_job', v_wait, 'wait_invoice', v_wait_doc, 'wait_reason', v_wait_reason, 'warnings', to_jsonb(v_warn), 'line_count', 1,
    'totals', jsonb_build_object('taxable', v_a.amount, 'tax', 0, 'total', v_a.amount, 'invoice_number', v_i.invoice_number, 'doc_number', v_doc), 'fingerprint', null);
end;
$$;
create or replace function public.qbo_opening_alloc_sync (p_alloc_id uuid, p_by uuid) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_a public.so_payment_alloc%rowtype; v_p public.so_payment%rowtype; v_active boolean;
        v_tc public.qbo_txn%rowtype; v_ta public.qbo_txn%rowtype; v_cj public.qbo_job%rowtype; v_cvj public.qbo_job%rowtype; v_aj public.qbo_job%rowtype; v_avj public.qbo_job%rowtype; v_id uuid; v_act text := 'none';
        v_gap_err text := public.qbo_opening_refunded_block(p_alloc_id);   -- 2e-3-2-1 ⓖ-1 (다): 환불된 이월 돈을 쓰는 붙임이면 글(opening_credit 을 처음부터 failed 로) · 아니면 null
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  select * into v_a from public.so_payment_alloc a where a.id = p_alloc_id;
  if v_a.id is null then return jsonb_build_object('action', 'not_applicable'); end if;
  select * into v_p from public.so_payment p where p.id = v_a.payment_id;
  if v_p.id is null or v_p.kind <> 'payment' or v_p.method <> 'opening' then return jsonb_build_object('action', 'not_applicable'); end if;      -- 이월 아닌 결제는 qbo_payment_sync 의 몫(무변)
  if not public.qbo_send_since_ok((v_a.created_at at time zone 'America/Toronto')::date) then return jsonb_build_object('action', 'before_since'); end if;   -- QBO 시대 전 사건은 조용히
  v_active := v_a.voided_at is null;
  select * into v_tc from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'opening_credit' and t.ims_id = v_a.id::text;
  select * into v_ta from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'opening_alloc'  and t.ims_id = v_a.id::text;
  select * into v_cj  from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_credit'      and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_cvj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_credit_void' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_aj  from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_apply'       and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_avj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_apply_void'  and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_tc.id is null then                                                                                                               -- CreditMemo 를 보낸 적 없다
    if v_active then
      if v_cj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff) values (v_realm, 'opening_credit', 'opening_alloc', v_a.id::text, case when v_gap_err is null then 'queued' else 'failed' end, v_gap_err, p_by)   -- 2e-3-2-1 ⓖ-1: 가드 글이 있으면 failed
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
        if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_credit' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
        v_cj.id := v_id; v_act := case when v_gap_err is null then 'queued' else 'failed' end;   -- 2e-3-2-1 ⓖ-1
        if v_aj.id is not null and v_aj.state = 'blocked' then update public.qbo_job j set blocked_by = v_cj.id where j.id = v_aj.id; end if;   -- apply 가 옛(끝난) 일감 뒤에 서 있었다면 새 일감 뒤로
      end if;
      if v_aj.id is null then                                                                                                           -- 이견 2: 0 원 Payment 는 만들 때부터 CreditMemo 일감 뒤(claim ② 가 sent 때 푼다)
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_apply', 'opening_alloc', v_a.id::text, 'blocked', v_cj.id, p_by, 'waits for the credit memo of this opening credit to reach QuickBooks first')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        if v_act = 'none' then v_act := 'queued'; end if;
      end if;
    else
      if v_cj.id is not null and v_cj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'opening credit detached before sending'), 2000), updated_by = p_by where j.id = v_cj.id;
        v_act := 'skipped';
      end if;
      if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'opening credit detached before sending'), 2000), updated_by = p_by where j.id = v_aj.id;
        v_act := 'skipped';
      end if;
      if v_cj.id is not null and v_cj.state in ('sending', 'unknown') and v_cvj.id is null then                                       -- 닿았는지 모른다 → void 를 그 일감 뒤에(결제 꼴)
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'blocked', v_cj.id, p_by, 'detached while sending — void after the send settles')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'void_after_send';
      end if;
    end if;
  elsif v_tc.voided_at is null then                                                                                                     -- CreditMemo 가 QBO 에 서 있다
    if v_ta.id is null then                                                                                                             -- 0 원 Payment 는 아직
      if v_active then
        if v_aj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'opening_apply', 'opening_alloc', v_a.id::text, 'queued', p_by)
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          v_act := 'queued';
        end if;
      else
        if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
          update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'opening credit detached — only the void goes'), 2000), updated_by = p_by where j.id = v_aj.id;
        end if;
        if v_aj.id is not null and v_aj.state in ('sending', 'unknown') then                                                          -- 0 원 Payment 가 나가는 중 → 그 뒤에 apply_void → 그 뒤에 credit_void
          if v_avj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_apply_void', 'opening_alloc', v_a.id::text, 'blocked', v_aj.id, p_by, 'detached while sending — void after the send settles')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
            if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_apply_void' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
            v_avj.id := v_id;
          end if;
          if v_cvj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'blocked', v_avj.id, p_by, 'void the credit memo after the zero payment is voided')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          end if;
          v_act := 'void_after_send';
        else
          if v_cvj.id is null then
            insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'queued', p_by, 'opening credit detached — void the credit memo in QuickBooks')
            on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
          end if;
          v_act := 'void';
        end if;
      end if;
    elsif v_ta.voided_at is null then                                                                                                   -- 둘 다 서 있다
      if v_active then
        v_act := 'same';                                                                                                                -- 1011 꼴: 붙임 행은 바뀌지 않는다 — 지문 · 다시 보내기 없음
      else                                                                                                                              -- 이견 12: 0 원 Payment void 먼저 → CreditMemo void(blocked_by)
        if v_avj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'opening_apply_void', 'opening_alloc', v_a.id::text, 'queued', p_by, 'opening credit detached — void the zero payment in QuickBooks')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_id;
          if v_id is null then select j.id into v_id from public.qbo_job j where j.realm_id = v_realm and j.kind = 'opening_apply_void' and j.ims_kind = 'opening_alloc' and j.ims_id = v_a.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1; end if;
          v_avj.id := v_id;
        end if;
        if v_cvj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'blocked', v_avj.id, p_by, 'void the credit memo after the zero payment is voided')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        end if;
        v_act := 'void';
      end if;
    else                                                                                                                                -- 0 원 Payment 는 QBO 쪽 void 됨 · CreditMemo 는 서 있다
      if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_aj.id;
        v_act := 'skipped';
      end if;
      if not v_active then
        if v_cvj.id is null then
          insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'opening_credit_void', 'opening_alloc', v_a.id::text, 'queued', p_by, 'opening credit detached — void the credit memo in QuickBooks')
          on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        end if;
        v_act := 'void';
      end if;
    end if;
  else                                                                                                                                  -- CreditMemo 가 QBO 쪽 void 됨(붙임은 되살지 않는다 · 다시 붙이면 새 행 = 새 두 장)
    if v_cj.id is not null and v_cj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_cj.id;
      v_act := 'skipped';
    end if;
    if v_aj.id is not null and v_aj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'already voided in QuickBooks'), 2000), updated_by = p_by where j.id = v_aj.id;
      v_act := 'skipped';
    end if;
  end if;
  return jsonb_build_object('action', v_act);
end;
$$;
create or replace function public.qbo_job_on_payment_status () returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_by uuid := coalesce(new.voided_by, new.updated_by);
begin
  if new.status is not distinct from old.status then return null; end if;
  begin
    if new.kind = 'refund' then perform public.qbo_refund_sync(new.id, v_by); else perform public.qbo_payment_sync(new.id, v_by); end if;   -- 2e-3-2-1 이견 7: 환불 void 는 refund 가지
  exception when others then
    begin
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, last_error, by_staff)
      select c.realm_id, case when new.kind = 'refund' then 'refund' else 'payment' end, case when new.kind = 'refund' then 'refund' else 'payment' end, new.id::text, 'failed', left('could not queue: ' || sqlerrm, 2000), v_by from public.qbo_connection c where c.singleton   -- 2e-3-2-1: 실패 흔적은 가지에 맞춰
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
    exception when others then null;
    end;
  end;
  return null;
end;
$$;
create or replace function public.qbo_link_set (p_kind text, p_ims_id text, p_qbo_id text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_ims record; v_ent public.qbo_entity%rowtype; v_other record; v_l public.qbo_link%rowtype; v_rq int := 0;
begin
  if v_type is null then raise exception 'kind must be one of account, tax_rule, payment_term, payment_method, customer, supplier, product, charge, service (got %)', p_kind; end if;
  select * into v_ims from public.qbo_ims_rows(p_kind) r where r.ims_id = p_ims_id;
  if v_ims.ims_id is null then raise exception 'No IMS % with id % — nothing was saved', p_kind, p_ims_id; end if;
  select * into v_ent from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = v_type and e.qbo_id = p_qbo_id;
  if v_ent.qbo_id is null then raise exception 'QuickBooks % % is not in the pulled list — pull the list first, or check the id', v_type, p_qbo_id; end if;
  if v_ent.gone_at is not null then raise exception 'QuickBooks % % (%) is no longer in QuickBooks (gone since %) — nothing was saved', v_type, p_qbo_id, v_ent.name, v_ent.gone_at::date; end if;
  if p_kind <> 'tax_rule' then
    select l.ims_kind, l.ims_id into v_other from public.qbo_link l where l.realm_id = v_realm and l.qbo_type = v_type and l.qbo_id = p_qbo_id and l.ims_kind <> 'tax_rule' and not (l.ims_kind = p_kind and l.ims_id = p_ims_id);
    if found then raise exception 'QuickBooks % % (%) is already linked to IMS % % — clear that link first', v_type, p_qbo_id, v_ent.name, v_other.ims_kind, coalesce((select r.ims_name from public.qbo_ims_rows(v_other.ims_kind) r where r.ims_id = v_other.ims_id), v_other.ims_id); end if;
  end if;
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
  values (v_realm, p_kind, p_ims_id, v_type, p_qbo_id, 'manual', v_ent.name, v_staff)
  on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, matched_by = 'manual', qbo_name_at_match = excluded.qbo_name_at_match, by_staff = excluded.by_staff, matched_at = now(), updated_at = now(), updated_by = excluded.by_staff
  returning * into v_l;
  if p_kind = 'payment_method' then v_rq := public.qbo_payment_method_requeue(p_ims_id, v_staff); end if;
  if p_kind = 'charge' and p_ims_id like 'acct:%' then v_rq := v_rq + public.qbo_opening_credit_requeue(substr(p_ims_id, 6), v_staff); end if;   -- 2e-3-1 이견 7(1039 꼴): 계정 Item 짝이 서면 그 계정의 이월 돈 failed opening_credit 을 queued 로   -- 2e-1d-1 판정 1039: 수단 짝이 서면 그 수단의 failed 결제 일감을 queued 로(남은 이월 장 > 0 은 건너뛴다)
  if p_kind = 'tax_rule' and exists (select 1 from public.ref_tax_rule r where r.id::text = p_ims_id and r.direction = 'purchase' and r.name ilike 'Out of Scope%') then v_rq := v_rq + public.qbo_refund_requeue(v_staff); end if;   -- 2e-3-2-1 이견 13 · ⓖ-8(1039 꼴): Out of Scope (Purchase) 짝이 서면 세금 짝 없음으로 failed 된 refund → queued
  return to_jsonb(v_l) || jsonb_build_object('ims_name', v_ims.ims_name, 'ims_code', v_ims.ims_code, 'qbo_name', v_ent.name, 'qbo_active', v_ent.active, 'requeued', v_rq);
end;
$$;
create or replace function public.qbo_job_claim (p_limit int default 15, p_kinds text[] default array['customer', 'item'], p_job_ids uuid[] default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_stale int; v_unblocked int; v_ids uuid[]; v_j public.qbo_job%rowtype; v_open public.qbo_job%rowtype; v_b jsonb; v_rows jsonb := '[]'::jsonb; v_failed int := 0; v_blocked int := 0; v_waiting int := 0; v_last uuid; v_cust uuid; v_nj jsonb; e jsonb;
  v_kinds text[] := coalesce(p_kinds, array['customer', 'item']);
  v_pick uuid[] := (select array_agg(distinct x) from unnest(p_job_ids) x where x is not null);                                       -- 2d1: 고른 id(중복 · null 제거) · null 이면 옛 길(가장 오래된 것부터 p_limit)
  v_needs jsonb := '[]'::jsonb; v_req jsonb := '[]'::jsonb; v_r record;
begin
  if not public.doc_is_service() then raise exception 'qbo_job_claim is for the send worker only — nothing was read'; end if;
  if not (v_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void']) or coalesce(array_length(v_kinds, 1), 0) = 0 then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void (got %)', v_kinds; end if;   -- 2e-3-2-1 kinds 18
  if p_job_ids is not null and coalesce(array_length(v_pick, 1), 0) = 0 then raise exception 'job_ids must name at least one job — nothing was read'; end if;
  if coalesce(array_length(v_pick, 1), 0) > 200 then raise exception 'job_ids may name at most 200 jobs in one call (got %) — nothing was read', array_length(v_pick, 1); end if;
  -- ① 멈춘 sending(EF 가 도중에 죽었다 · QBO 에 닿았는지 모른다) → unknown(mail_claim 꼴 · 자동 재전송 금지 · 다음 send 가 이름 · DocNumber 로 조회해 푼다)
  update public.qbo_job j set state = 'unknown', claimed_at = null,
         last_error = left(coalesce(j.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — QuickBooks may or may not have it', date_trunc('second', now() - j.claimed_at), j.attempts), 2000)
   where j.realm_id = v_realm and j.state = 'sending' and j.claimed_at < now() - interval '10 minutes';
  get diagnostics v_stale = row_count;
  -- ② 부모가 보내졌으면 자식을 연다(손님 → 자식 손님 · need → 인보이스 · 인보이스 → void · 인보이스 → 크레딧)
  update public.qbo_job j set state = 'queued', next_at = now() from public.qbo_job p where j.realm_id = v_realm and j.state = 'blocked' and p.id = j.blocked_by and p.state = 'sent';
  get diagnostics v_unblocked = row_count;
  -- ③ 잡기 — queued → sending(for update skip locked · 10 분 임대) · EF 가 아는 kind 만 · [2d1] p_job_ids 가 있으면 그 id 만(한도는 id 수)
  with pick as (
    select j.id from public.qbo_job j where j.realm_id = v_realm and j.state = 'queued' and j.next_at <= now() and j.kind = any (v_kinds) and (v_pick is null or j.id = any (v_pick))
     order by j.created_at, j.id limit case when v_pick is null then greatest(1, least(coalesce(p_limit, 15), 50)) else array_length(v_pick, 1) end for update skip locked),
  upd as (update public.qbo_job j set state = 'sending', claimed_at = now(), attempts = j.attempts + 1 from pick where j.id = pick.id returning j.id)
  select coalesce(array_agg(u.id), '{}') into v_ids from upd u;
  -- ④ 몸은 다음 문장에서 일감마다(같은 문장 안의 읽기는 update 전 행을 본다) · 몸이 안 만들어지면 그 일감만 failed · needs 가 있으면 need 일감을 쌓고 이 일감은 blocked(이견 11) · [2d1] need 일감을 need_jobs 로 돌려준다 · blocked_by 는 손님 need 우선
  for v_j in select * from public.qbo_job j where j.id = any (v_ids) order by j.created_at, j.id loop
    begin
      v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                           when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                           when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void   -- 2c1 credit · credit_void
      if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
      if v_b->>'parent_customer_id' is not null then raise exception 'parent customer is not in QuickBooks yet — send the parent first (job was not blocked: parent link removed?)'; end if;
      if jsonb_array_length(coalesce(v_b->'needs', '[]'::jsonb)) > 0 then
        v_last := null; v_cust := null;
        for e in select x from jsonb_array_elements(v_b->'needs') x loop
          v_nj := public.qbo_job_open_or_add(e->>'kind', e->>'ims_id', v_j.by_staff);                                                 -- 몸이 거부하면(941 · 활성 Sku 사람 짝 …) 예외 → 이 일감 failed + 그 까닭
          v_last := (v_nj->>'id')::uuid;
          if e->>'kind' = 'customer' then v_cust := v_last; end if;
          v_needs := v_needs || jsonb_build_object('job_id', v_nj->>'id', 'kind', v_nj->>'kind', 'ims_kind', v_nj->>'ims_kind', 'ims_id', v_nj->>'ims_id', 'state', v_nj->>'state', 'name', e->>'name', 'existing', coalesce((v_nj->>'existing')::boolean, false), 'for_job', v_j.id, 'parent_job', v_nj->'parent_job'->>'id');
          if v_nj->'parent_job'->>'id' is not null then
            v_needs := v_needs || jsonb_build_object('job_id', v_nj->'parent_job'->>'id', 'kind', 'customer', 'ims_kind', 'customer', 'ims_id', v_nj->'parent_job'->>'ims_id', 'state', v_nj->'parent_job'->>'state', 'name', null, 'existing', coalesce((v_nj->'parent_job'->>'existing')::boolean, false), 'for_job', v_nj->>'id', 'parent_job', null);
          end if;
        end loop;
        update public.qbo_job j set state = 'blocked', blocked_by = coalesce(v_cust, v_last), claimed_at = null,
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[format('waiting for %s QuickBooks record(s) to be created first', jsonb_array_length(v_b->'needs'))], ' · '), '')
         where j.id = v_j.id;
        v_blocked := v_blocked + 1;
        continue;
      end if;
      if nullif(v_b->>'wait_job', '') is not null then                                                                                 -- 2c1 판정 960: 크레딧은 자기 IMS 인보이스가 QBO 에 들어간 뒤 — 그 인보이스 일감 뒤에 선다(② 가 sent 때 푼다)
        update public.qbo_job j set state = 'blocked', blocked_by = (v_b->>'wait_job')::uuid, claimed_at = null,
               warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')) || array[coalesce(v_b->>'wait_reason', format('waiting for invoice %s to reach QuickBooks first', coalesce(v_b->>'wait_invoice', '?')))], ' · '), '')
         where j.id = v_j.id;
        v_waiting := v_waiting + 1;
        continue;
      end if;
      update public.qbo_job j set warning = nullif(array_to_string(array(select jsonb_array_elements_text(v_b->'warnings')), ' · '), ''), fingerprint = v_b->>'fingerprint' where j.id = v_j.id;   -- 2e-1b: 보낼 때의 IMS 상태(지문)를 일감에 · done 이 qbo_txn 으로 옮긴다
      v_rows := v_rows || jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'attempt', v_j.attempts, 'request_id', v_j.request_id,
                                             'name', coalesce(v_b->>'display_name', v_b->>'name'), 'name_alt', v_b->>'name_alt', 'sku', v_b->>'sku', 'doc_number', v_b->>'doc_number', 'qbo_id', v_b->>'qbo_id',
                                             'body', v_b->'body', 'warnings', v_b->'warnings', 'totals', v_b->'totals',
                                             'fingerprint', v_b->>'fingerprint', 'check_lines', v_b->'check_lines', 'lookup', v_b->'lookup');   -- 2e-1b: 결제 = (가) Balance 가드 줄 · unknown 열쇠
    exception when others then
      update public.qbo_job j set state = 'failed', claimed_at = null, last_error = left(sqlerrm, 2000) where j.id = v_j.id;
      v_failed := v_failed + 1;
    end;
  end loop;
  -- ⑤ [2d1] 고른 id 마다 결과 — 잡힌 것은 ④ 뒤의 상태로(sending = claimed · blocked = 까닭 · failed = 글) · 못 잡은 것은 왜
  if v_pick is not null then
    for v_r in select x.id, j.state, j.kind, j.warning, j.last_error, j.next_at, j.realm_id from unnest(v_pick) x(id) left join public.qbo_job j on j.id = x.id loop
      if v_r.state = 'blocked' and v_r.realm_id = v_realm and not (v_r.id = any (v_ids)) then                                       -- 이미 blocked 인 일감을 다시 골랐다 → 기다리는 열린 일감(부모 blocked_by + 몸의 needs)을 need_jobs 로(EF 가 다음 바퀴에 같이 잡는다 · 거래 종류는 EF 가 안 잡는다 = 960)
        select * into v_j from public.qbo_job j where j.id = v_r.id;
        select * into v_open from public.qbo_job j where j.id = v_j.blocked_by and j.state not in ('sent', 'skipped');
        if v_open.id is not null then v_needs := v_needs || jsonb_build_object('job_id', v_open.id, 'kind', v_open.kind, 'ims_kind', v_open.ims_kind, 'ims_id', v_open.ims_id, 'state', v_open.state, 'name', null, 'existing', true, 'for_job', v_j.id, 'parent_job', null); end if;
        begin
          v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                               when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                               when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
          for e in select x from jsonb_array_elements(coalesce(v_b->'needs', '[]'::jsonb)) x
                   union all select jsonb_build_object('kind', 'customer', 'ims_id', v_b->>'parent_customer_id', 'name', null) where v_b->>'parent_customer_id' is not null loop
            select * into v_open from public.qbo_job j where j.realm_id = v_realm and j.kind = e->>'kind' and j.ims_id = e->>'ims_id' and j.state not in ('sent', 'skipped') and j.id is distinct from v_j.blocked_by order by j.created_at limit 1;
            if v_open.id is not null then v_needs := v_needs || jsonb_build_object('job_id', v_open.id, 'kind', v_open.kind, 'ims_kind', v_open.ims_kind, 'ims_id', v_open.ims_id, 'state', v_open.state, 'name', e->>'name', 'existing', true, 'for_job', v_j.id, 'parent_job', null); end if;
            v_open := null;
          end loop;
        exception when others then null;                                                                                           -- 몸이 거부해도 requested 의 까닭(warning)은 그대로 · needs 만 모른다
        end;
      end if;
      v_req := v_req || jsonb_build_object('job_id', v_r.id, 'kind', v_r.kind, 'state', v_r.state,
        'result', case when v_r.state is null or v_r.realm_id is distinct from v_realm then 'not_found'
                       when v_r.id = any (v_ids) then case v_r.state when 'sending' then 'claimed' when 'blocked' then 'blocked' when 'failed' then 'failed' else v_r.state end
                       when v_r.state <> 'queued' then 'not_queued'
                       when not (v_r.kind = any (v_kinds)) then 'wrong_kind'
                       when v_r.next_at > now() then 'not_due' else 'locked' end,
        'reason', case when v_r.state is null or v_r.realm_id is distinct from v_realm then 'no such job'
                       when v_r.id = any (v_ids) then case v_r.state when 'blocked' then v_r.warning when 'failed' then v_r.last_error end
                       when v_r.state <> 'queued' then format('the job is %s — not sent', v_r.state) || case v_r.state when 'blocked' then ' (' || coalesce(v_r.warning, 'waiting for another job') || ')' when 'failed' then ' — retry it first' when 'unknown' then ' — retry it with a note after checking QuickBooks' when 'skipped' then ' — retry it first' when 'sending' then ' (another send is working on it)' else '' end
                       when not (v_r.kind = any (v_kinds)) then format('kind %s is not sent by this worker', v_r.kind)
                       when v_r.next_at > now() then format('the job is scheduled for %s', v_r.next_at) else 'another send holds the job — try again in a moment' end);
    end loop;
  end if;
  return jsonb_build_object('realm_id', v_realm, 'kinds', to_jsonb(v_kinds), 'picked', case when v_pick is null then null else to_jsonb(v_pick) end, 'recovered_unknown', v_stale, 'unblocked', v_unblocked, 'claimed', coalesce(array_length(v_ids, 1), 0), 'body_failed', v_failed, 'blocked_for_needs', v_blocked, 'blocked_for_invoice', v_waiting,
                            'need_jobs', v_needs, 'requested', v_req, 'jobs', v_rows);
end;
$$;
create or replace function public.qbo_job_preview (p_job uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_j public.qbo_job%rowtype; v_b jsonb; v_err text; v_needs jsonb := '[]'::jsonb; e jsonb; v_open public.qbo_job%rowtype; v_wait public.qbo_job%rowtype; v_parent public.qbo_job%rowtype; v_blocked jsonb; v_wait_j jsonb;
begin
  select * into v_j from public.qbo_job j where j.id = p_job and j.realm_id = v_realm;
  if v_j.id is null then raise exception 'Job % not found — nothing to preview', p_job; end if;
  begin
    v_b := case v_j.kind when 'customer' then public.qbo_customer_body(v_j.ims_id::uuid) when 'item' then public.qbo_item_body(v_j.ims_id)
                         when 'invoice' then public.qbo_invoice_body(v_j.ims_id::uuid) when 'invoice_void' then public.qbo_void_body(v_j.ims_id::uuid)
                         when 'credit' then public.qbo_credit_body(v_j.ims_id::uuid) when 'credit_void' then public.qbo_credit_void_body(v_j.ims_id::uuid)
                           when 'payment' then public.qbo_payment_body(v_j.ims_id::uuid) when 'payment_void' then public.qbo_payment_void_body(v_j.ims_id::uuid)
                           when 'credit_apply' then public.qbo_credit_apply_body(v_j.ims_id::uuid) when 'credit_apply_void' then public.qbo_credit_apply_void_body(v_j.ims_id::uuid)
                           when 'refund' then public.qbo_refund_body(v_j.ims_id::uuid) when 'refund_void' then public.qbo_refund_void_body(v_j.ims_id::uuid) when 'refund_apply' then public.qbo_refund_apply_body(v_j.ims_id::uuid) when 'refund_apply_void' then public.qbo_refund_apply_void_body(v_j.ims_id::uuid)   -- 2e-3-2-1 refund · refund_void · refund_apply · refund_apply_void
                           when 'opening_credit' then public.qbo_opening_credit_body(v_j.ims_id::uuid) when 'opening_credit_void' then public.qbo_opening_credit_void_body(v_j.ims_id::uuid)
                           when 'opening_apply' then public.qbo_opening_apply_body(v_j.ims_id::uuid) when 'opening_apply_void' then public.qbo_opening_apply_void_body(v_j.ims_id::uuid) end;   -- 2e-3-1 opening_credit · opening_credit_void · opening_apply · opening_apply_void   -- 2e-2-1 credit_apply · credit_apply_void   -- 2e-1b payment · payment_void
    if v_b is null then raise exception 'kind % has no body', v_j.kind; end if;
  exception when others then
    v_err := left(sqlerrm, 2000); v_b := null;
  end;
  -- needs(손님 · Item 을 먼저 만들어야 한다) — 열린 일감이 있으면 그 id · state · 없으면 null(send 가 만든다) · 손님 몸의 부모(parent_customer_id)도 need 로
  if v_b is not null then
    for e in select x from jsonb_array_elements(coalesce(v_b->'needs', '[]'::jsonb)) x
             union all select jsonb_build_object('kind', 'customer', 'ims_id', v_b->>'parent_customer_id', 'name', (select c.name from public.customer c where c.id::text = v_b->>'parent_customer_id')) where v_b->>'parent_customer_id' is not null loop
      select * into v_open from public.qbo_job j where j.realm_id = v_realm and j.kind = e->>'kind' and j.ims_id = e->>'ims_id' and j.state not in ('sent', 'skipped') order by j.created_at limit 1;
      v_needs := v_needs || jsonb_build_object('kind', e->>'kind', 'ims_id', e->>'ims_id', 'name', e->>'name', 'job_id', v_open.id, 'job_state', v_open.state, 'job_error', v_open.last_error);
      v_open := null;
    end loop;
    if nullif(v_b->>'wait_job', '') is not null then
      select * into v_wait from public.qbo_job j where j.id = (v_b->>'wait_job')::uuid;
      v_wait_j := jsonb_build_object('job_id', v_wait.id, 'kind', v_wait.kind, 'state', v_wait.state, 'invoice', v_b->>'wait_invoice', 'reason', coalesce(v_b->>'wait_reason', format('waiting for invoice %s to reach QuickBooks first — send it too', coalesce(v_b->>'wait_invoice', '?'))));
    end if;
  end if;
  if v_j.blocked_by is not null then
    select * into v_parent from public.qbo_job j where j.id = v_j.blocked_by;
    v_blocked := jsonb_build_object('job_id', v_parent.id, 'kind', v_parent.kind, 'state', v_parent.state, 'doc', public.qbo_job_doc(v_parent.ims_kind, v_parent.ims_id), 'last_error', v_parent.last_error);
  end if;
  return jsonb_build_object(
    'job', jsonb_build_object('id', v_j.id, 'kind', v_j.kind, 'ims_kind', v_j.ims_kind, 'ims_id', v_j.ims_id, 'state', v_j.state, 'attempts', v_j.attempts, 'qbo_id', v_j.qbo_id, 'qbo_name', v_j.qbo_name, 'last_error', v_j.last_error, 'warning', v_j.warning, 'note', v_j.note, 'created_at', v_j.created_at, 'sent_at', v_j.sent_at, 'by_name', (select s.name from public.ims_staff s where s.id = v_j.by_staff)),
    'doc', public.qbo_job_doc(v_j.ims_kind, v_j.ims_id),
    'name', coalesce(v_b->>'display_name', v_b->>'name'), 'doc_number', v_b->>'doc_number', 'body', v_b->'body', 'totals', v_b->'totals', 'warnings', coalesce(v_b->'warnings', '[]'::jsonb), 'line_count', (v_b->>'line_count')::int,
    'needs', v_needs, 'wait', v_wait_j, 'blocked_by', v_blocked, 'error', v_err, 'check_lines', v_b->'check_lines', 'fingerprint', v_b->>'fingerprint',   -- 2e-1b
    'sendable', (v_err is null and jsonb_array_length(v_needs) = 0 and v_wait_j is null and v_j.state = 'queued'),
    'preview_only', true);
end;
$$;
create or replace function public.qbo_job_doc (p_ims_kind text, p_ims_id text) returns jsonb
  language sql stable security definer set search_path = public, pg_temp
as $$
  select case p_ims_kind
    when 'invoice' then (select jsonb_build_object('doc_number', i.invoice_number, 'name', i.bill_to_name, 'customer_id', i.bill_to_customer_id, 'currency', i.currency_code, 'total', i.total, 'doc_date', i.issued_on, 'doc_status', i.status)
                           from public.so_invoice i where i.id::text = p_ims_id)
    when 'credit' then (select jsonb_build_object('doc_number', c.credit_number, 'name', (select cu.name from public.customer cu where cu.id = c.customer_id), 'customer_id', c.customer_id, 'currency', c.currency_code, 'total', c.total, 'doc_date', c.issued_on, 'doc_status', c.status)
                          from public.so_credit c where c.id::text = p_ims_id)
    when 'customer' then (select jsonb_build_object('doc_number', null, 'name', c.name, 'customer_id', c.id, 'currency', c.currency_code, 'total', null, 'doc_date', null, 'doc_status', case when c.is_active then 'active' else 'inactive' end)
                            from public.customer c where c.id::text = p_ims_id)
    when 'product' then (select jsonb_build_object('doc_number', p.sku, 'name', p.name, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', case when p.is_active then 'active' else 'inactive' end)
                           from public.product p where p.id::text = p_ims_id)
    when 'payment' then (select jsonb_build_object('doc_number', p.reference, 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', p.amount, 'doc_date', p.paid_on, 'doc_status', p.status)
                           from public.so_payment p where p.id::text = p_ims_id)   -- 2e-1b: 결제 = reference · 청구처 · 통화 · 금액 · 받은 날 · active | voided
    when 'credit_alloc' then (select jsonb_build_object('doc_number', c.credit_number || ' → ' || coalesce(i.invoice_number, 'refund'), 'name', (select cu.name from public.customer cu where cu.id = public.so_invoice_store(i.id)), 'customer_id', public.so_invoice_store(i.id), 'currency', c.currency_code, 'total', a.amount, 'doc_date', (a.created_at at time zone 'America/Toronto')::date, 'doc_status', case when a.voided_at is null then 'active' else 'voided' end)
                                from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id left join public.so_invoice i on i.id = a.invoice_id where a.id::text = p_ims_id)   -- 2e-2-1: 크레딧 붙임 = 「CR → 인보이스」 · 매장(1014) · 통화 · 붙임 금액 · 붙인 날(토론토) · active | voided
    when 'opening_alloc' then (select jsonb_build_object('doc_number', public.qbo_opening_doc_number(a.id) || ' → ' || i.invoice_number, 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', a.amount, 'doc_date', (a.created_at at time zone 'America/Toronto')::date, 'doc_status', case when a.voided_at is null then 'active' else 'voided' end)
                                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id join public.so_invoice i on i.id = a.invoice_id where a.id::text = p_ims_id)   -- 2e-3-1: 이월 돈 붙임 = 「OC-<인보이스>-<n> → 인보이스」 · 돈의 주인(이견 4) · 통화 · 붙임 금액 · 붙인 날(토론토) · active | voided
    when 'refund' then (select jsonb_build_object('doc_number', public.qbo_refund_label(p), 'name', (select cu.name from public.customer cu where cu.id = p.customer_id), 'customer_id', p.customer_id, 'currency', p.currency_code, 'total', p.amount, 'doc_date', p.paid_on, 'doc_status', p.status)
                          from public.so_payment p where p.id::text = p_ims_id and p.kind = 'refund')   -- 2e-3-2-1: 환불 = reference(없으면 「Refund <날> <금액>」) · 손님 · 통화 · 금액 · 결제일 · active | voided
    else jsonb_build_object('doc_number', p_ims_id, 'name', p_ims_id, 'customer_id', null, 'currency', null, 'total', null, 'doc_date', null, 'doc_status', null) end;
$$;
create or replace function public.qbo_job_list (p_state text default null, p_kinds text[] default null, p_from date default null, p_to date default null, p_q text default null, p_limit int default 50, p_offset int default 0) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open (got %)', p_state; end if;
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void (got %)', p_kinds; end if;   -- 2e-3-2-1 kinds 18
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'from % is after to % — nothing was read', p_from, p_to; end if;
  return (with base as (
      select j.id, j.kind, j.ims_kind, j.ims_id, j.state, j.attempts, j.next_at, j.claimed_at, j.blocked_by, j.qbo_id, j.qbo_name, j.sent_at, j.last_error, j.last_intuit_tid, j.warning, j.note, j.by_staff, j.created_at, j.updated_at,
             (j.created_at at time zone 'America/Toronto')::date as job_date,
             d.doc->>'doc_number' as doc_number, d.doc->>'name' as name, d.doc->>'currency' as currency, (d.doc->>'total')::numeric as total, (d.doc->>'doc_date')::date as doc_date, d.doc->>'doc_status' as doc_status,
             case j.ims_kind when 'invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'credit' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
                             when 'payment' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-1b
                             when 'credit_alloc' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-2-1
                             when 'opening_alloc' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-3-1
                             when 'refund' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 2e-3-2-1
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', j.ims_id) end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j
      cross join lateral (select public.qbo_job_doc(j.ims_kind, j.ims_id) as doc) d
      left join public.qbo_job p on p.id = j.blocked_by
      left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc) pd on p.id is not null
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund')   -- 2e-3-2-1 + refund
                               and t.ims_kind = case j.kind when 'opening_credit' then 'opening_credit' when 'opening_credit_void' then 'opening_credit' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                            when 'refund_apply' then 'refund_apply' when 'refund_apply_void' then 'refund_apply' else j.ims_kind end   -- 2e-3-1 이견 3: 한 붙임에 txn 둘 — kind 로 갈라 잇는다 · 2e-3-2-1 이견 8: 환불도(refund · refund_void ↔ txn refund(Purchase) · refund_apply · _void ↔ txn refund_apply(Payment))
      where j.realm_id = v_realm and (p_state is null or (p_state = 'open' and j.state not in ('sent', 'skipped')) or j.state = p_state)
        and (p_kinds is null or j.kind = any (p_kinds))
        and (p_from is null or (j.created_at at time zone 'America/Toronto')::date >= p_from) and (p_to is null or (j.created_at at time zone 'America/Toronto')::date <= p_to)),
    hit as (select b.* from base b where v_q is null or b.ims_name ilike '%' || v_q || '%' or coalesce(b.qbo_id, '') ilike '%' || v_q || '%' or coalesce(b.qbo_name, '') ilike '%' || v_q || '%')
    select jsonb_build_object('state', p_state, 'kinds', to_jsonb(p_kinds), 'from', p_from, 'to', p_to, 'q', v_q, 'total', (select count(*) from hit), 'limit', v_lim, 'offset', v_off,
      'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) from (select j.state, count(*) as n from public.qbo_job j where j.realm_id = v_realm group by j.state) x),
      'rows', coalesce((select jsonb_agg((to_jsonb(b) - 'rk' - 'k_old') order by b.rk, b.k_old, b.created_at desc) from (
                select h.*, case h.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end as rk, case when h.state in ('queued', 'blocked') then h.created_at end as k_old
                  from hit h order by 
                    case h.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end,
                    case when h.state in ('queued', 'blocked') then h.created_at end asc nulls last, h.created_at desc
                  limit v_lim offset v_off) b), '[]'::jsonb)));
end;
$$;
create or replace function public.qbo_job_retry (p_job uuid, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_j public.qbo_job%rowtype; v_doc jsonb; v_open uuid;
begin
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('failed', 'unknown', 'skipped') then raise exception 'Only a failed or skipped job, or one whose result is unknown, can be sent again (this one is %) — nothing was saved', v_j.state; end if;
  if v_j.state = 'unknown' and nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say what you checked in QuickBooks (a note is required when the result was unknown) — nothing was saved'; end if;
  if v_j.kind = 'payment' and public.qbo_payment_fingerprint(v_j.ims_id::uuid) is null then                                             -- 2e-1b A-4: 결제 retry = 활성 · 붙임 ≥ 1 일 때만
    raise exception 'Payment % is voided or has no invoice applied — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce((select p.reference from public.so_payment p where p.id = v_j.ims_id::uuid), v_j.ims_id);
  end if;
  if v_j.kind = 'payment_void' and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'payment' and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-1b A-4: void retry = QBO 에 서 있을 때만
    raise exception 'Payment % is not standing in QuickBooks — nothing to void — nothing was saved', coalesce((select p.reference from public.so_payment p where p.id = v_j.ims_id::uuid), v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply' and not exists (select 1 from public.so_credit_alloc a where a.id::text = v_j.ims_id and a.voided_at is null and a.invoice_id is not null) then   -- 2e-2-1 이견 9: 붙임 retry = 활성 · 인보이스 대상 · QBO 에 안 섰을 때만
    raise exception 'Credit application % was detached (or pays a refund) — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply' and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Credit application % is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply_void' and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-2-1 이견 9: void retry = QBO 에 서 있을 때만
    raise exception 'Credit application % is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind = 'credit_apply_void' and exists (select 1 from public.so_credit_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then
    raise exception 'Credit application % is still applied in IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('opening_credit', 'opening_apply') and not exists (select 1 from public.so_payment_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then   -- 2e-3-1 이견 13: 붙임 retry = 활성 ∧ 그 장이 QBO 에 안 섰을 때만
    raise exception 'Opening credit % was detached — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('opening_credit', 'opening_apply') and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'opening_credit' then 'opening_credit' else 'opening_alloc' end and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Opening credit % (%) is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'opening_credit' then 'credit memo' else 'zero payment' end;
  end if;
  if v_j.kind in ('opening_credit_void', 'opening_apply_void') and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'opening_credit_void' then 'opening_credit' else 'opening_alloc' end and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-3-1 이견 13: void retry = 그 장이 QBO 에 서 있을 때만
    raise exception 'Opening credit % (%) is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'opening_credit_void' then 'credit memo' else 'zero payment' end;
  end if;
  if v_j.kind in ('opening_credit_void', 'opening_apply_void') and exists (select 1 from public.so_payment_alloc a where a.id::text = v_j.ims_id and a.voided_at is null) then
    raise exception 'Opening credit % is still applied in IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('refund', 'refund_apply') and not exists (select 1 from public.so_payment p where p.id::text = v_j.ims_id and p.kind = 'refund' and p.status = 'active') then   -- 2e-3-2-1 이견 14: 환불 retry = 활성 ∧ 그 장이 QBO 에 안 섰을 때만(컷은 보지 않는다 — ⓖ-4 의 「Retry」 = Send)
    raise exception 'Refund % is voided — nothing to send (a void job takes care of QuickBooks) — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.kind in ('refund', 'refund_apply') and exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'refund' then 'refund' else 'refund_apply' end and t.ims_id = v_j.ims_id and t.voided_at is null) then
    raise exception 'Refund % (%) is already standing in QuickBooks — nothing to send — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'refund' then 'expense' else 'zero payment' end;
  end if;
  if v_j.kind in ('refund_void', 'refund_apply_void') and not exists (select 1 from public.qbo_txn t where t.realm_id = v_j.realm_id and t.ims_kind = case v_j.kind when 'refund_void' then 'refund' else 'refund_apply' end and t.ims_id = v_j.ims_id and t.voided_at is null) then   -- 2e-3-2-1 이견 14: void retry = 그 장이 QBO 에 서 있을 때만(ⓖ-5 알림 일감은 여기서 거부 → Skip)
    raise exception 'Refund % (%) is not standing in QuickBooks — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id), case v_j.kind when 'refund_void' then 'expense' else 'zero payment' end;
  end if;
  if v_j.kind in ('refund_void', 'refund_apply_void') and exists (select 1 from public.so_payment p where p.id::text = v_j.ims_id and p.kind = 'refund' and p.status = 'active') then
    raise exception 'Refund % is still active in the IMS — nothing to void — nothing was saved', coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
  end if;
  if v_j.state = 'skipped' then                                                                                                        -- 2d1 이견 ④: 되돌리기 — note 필수 · 문서 상태 · 같은 열쇠의 열린 일감 없음
    if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say why this skipped job should be sent after all (a note is required) — nothing was saved'; end if;
    v_doc := public.qbo_job_doc(v_j.ims_kind, v_j.ims_id);
    if v_j.kind in ('invoice', 'credit') and coalesce(v_doc->>'doc_status', '') <> 'issued' then
      raise exception '% % is % — a skipped job can only be sent again while the document is issued — nothing was saved', case v_j.kind when 'invoice' then 'Invoice' else 'Credit note' end, coalesce(v_doc->>'doc_number', v_j.ims_id), coalesce(v_doc->>'doc_status', 'missing');
    end if;
    if v_j.kind in ('invoice_void', 'credit_void') and coalesce(v_doc->>'doc_status', '') <> 'cancelled' then
      raise exception '% % is % — a skipped void can only be sent again while the document is cancelled — nothing was saved', case v_j.kind when 'invoice_void' then 'Invoice' else 'Credit note' end, coalesce(v_doc->>'doc_number', v_j.ims_id), coalesce(v_doc->>'doc_status', 'missing');
    end if;
    select j.id into v_open from public.qbo_job j where j.realm_id = v_j.realm_id and j.kind = v_j.kind and j.ims_kind = v_j.ims_kind and j.ims_id = v_j.ims_id and j.state not in ('sent', 'skipped') and j.id <> v_j.id limit 1;
    if v_open is not null then raise exception 'Another open job (%) already exists for this % — send or skip that one instead — nothing was saved', v_open, v_j.kind; end if;
    update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, blocked_by = null, request_id = gen_random_uuid(), note = btrim(p_note), updated_by = v_staff where j.id = v_j.id;
    return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', 'skipped');
  end if;
  update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = coalesce(nullif(btrim(p_note), ''), j.note), updated_by = v_staff where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'queued', 'attempts', v_j.attempts, 'was', v_j.state);
end;
$$;
create or replace function public.qbo_job_done (p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text default null, p_intuit_tid text default null, p_note text default null, p_sku text default null, p_total_amt numeric default null, p_total_tax numeric default null, p_unapplied_amt numeric default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype; v_type text; v_link_err text; v_unblocked int := 0; v_i public.so_invoice%rowtype; v_c public.so_credit%rowtype; v_mismatch text; v_n int; v_p public.so_payment%rowtype; v_applied numeric; v_sync jsonb;   -- 2e-1b v_p · v_applied · v_sync
        v_alabel text;   -- 2e-2-1
        v_oa public.so_payment_alloc%rowtype;   -- 2e-3-1
begin
  if not public.doc_is_service() then raise exception 'qbo_job_done is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('sending', 'unknown') then raise exception 'Only a job being sent, or one whose result is unknown, can be finished (this one is %) — nothing was saved', v_j.state; end if;
  if nullif(btrim(coalesce(p_qbo_id, '')), '') is null or nullif(btrim(coalesce(p_qbo_name, '')), '') is null then raise exception 'qbo_id and qbo_name are required — nothing was saved'; end if;
  update public.qbo_job j set state = 'sent', sent_at = now(), claimed_at = null, qbo_id = btrim(p_qbo_id), qbo_name = btrim(p_qbo_name), sync_token = p_sync_token, last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid),
         last_error = case when p_note is not null then left(coalesce(j.last_error || ' · ', '') || p_note, 2000) else j.last_error end, attempts = j.attempts + case when p_note is not null then 1 else 0 end
   where j.id = v_j.id;
  if v_j.kind in ('customer', 'item') then
    v_type := case v_j.ims_kind when 'customer' then 'Customer' else 'Item' end;
    insert into public.qbo_entity (realm_id, qbo_type, qbo_id, name, sku, active, sync_token, fetched_at, gone_at)
    values (v_j.realm_id, v_type, btrim(p_qbo_id), btrim(p_qbo_name), nullif(btrim(coalesce(p_sku, '')), ''), true, p_sync_token, now(), null)
    on conflict (realm_id, qbo_type, qbo_id) do update set name = excluded.name, sku = coalesce(excluded.sku, public.qbo_entity.sku), active = true, sync_token = excluded.sync_token, fetched_at = now(), gone_at = null;
    begin
      insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
      values (v_j.realm_id, v_j.ims_kind, v_j.ims_id, v_type, btrim(p_qbo_id), 'created', btrim(p_qbo_name), v_j.by_staff)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_type = excluded.qbo_type, qbo_id = excluded.qbo_id, matched_by = 'created', qbo_name_at_match = excluded.qbo_name_at_match, matched_at = now(), updated_at = now(), updated_by = excluded.by_staff;
    exception when unique_violation then                                                              -- QBO 쪽 부분 유일(이미 다른 IMS 행의 짝) — QBO 레코드는 생겼다 · 사람이 짝을 바로잡는다
      v_link_err := format('QuickBooks %s #%s was created but is already linked to another IMS row — fix the link by hand under Settings → QuickBooks matching', v_type, btrim(p_qbo_id));
    end;
  elsif v_j.kind = 'invoice' then                                                                      -- 2b1: 거래 짝 + 942 합계 대조(상태는 sent · 다르면 mismatch · 자동 void 없음)
    select * into v_i from public.so_invoice i where i.id = v_j.ims_id::uuid;
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check invoice ' || coalesce(v_i.invoice_number, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_i.total or p_total_tax <> v_i.tax_amount then format('QuickBooks total %s / tax %s differs from IMS %s / %s — check invoice %s in QuickBooks (942)', p_total_amt, p_total_tax, v_i.total, v_i.tax_amount, v_i.invoice_number) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at)
      values (v_j.realm_id, 'invoice', v_j.ims_id, 'Invoice', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, updated_at = now();
    exception when unique_violation then                                                              -- (realm, Invoice, qbo_id) 가 이미 다른 IMS 인보이스의 짝
      v_link_err := format('QuickBooks Invoice #%s is already recorded for another IMS invoice — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'invoice_void' then                                                                 -- 2b1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'invoice' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent invoice on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'credit' then                                                                       -- 2c1: 거래 짝(CreditMemo) + 942 대조(so_credit.total · tax_amount · 상태는 sent · 자동 void 없음)
    select * into v_c from public.so_credit c where c.id = v_j.ims_id::uuid;
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check credit note ' || coalesce(v_c.credit_number, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_c.total or p_total_tax <> v_c.tax_amount then format('QuickBooks total %s / tax %s differs from IMS %s / %s — check credit note %s in QuickBooks (942)', p_total_amt, p_total_tax, v_c.total, v_c.tax_amount, v_c.credit_number) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at)
      values (v_j.realm_id, 'credit', v_j.ims_id, 'CreditMemo', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null)
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, updated_at = now();
    exception when unique_violation then                                                              -- (realm, CreditMemo, qbo_id) 가 이미 다른 IMS 크레딧의 짝
      v_link_err := format('QuickBooks CreditMemo #%s is already recorded for another IMS credit note — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'credit_void' then                                                                  -- 2c1 판정 963: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'credit' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent credit note on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'payment' then                                                                      -- 2e-1b: 거래 짝(Payment) + 지문(claim 이 일감에 적은 것) + 942 꼴 대조(TotalAmt = amount · UnappliedAmt = amount − Σ붙임 · 상태는 sent · 자동 void 없음)
    select * into v_p from public.so_payment p where p.id = v_j.ims_id::uuid;
    select coalesce(sum(a.amount), 0) into v_applied from public.so_payment_alloc a where a.payment_id = v_p.id and a.voided_at is null;
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check payment ' || coalesce(v_p.reference, v_j.ims_id) || ' in QuickBooks'
                       when p_total_amt <> v_p.amount then format('QuickBooks total %s differs from IMS %s — check payment %s in QuickBooks (942)', p_total_amt, v_p.amount, coalesce(v_p.reference, v_j.ims_id))
                       when p_unapplied_amt is not null and p_unapplied_amt <> v_p.amount - v_applied then format('QuickBooks unapplied %s differs from IMS %s — check payment %s in QuickBooks (942)', p_unapplied_amt, v_p.amount - v_applied, coalesce(v_p.reference, v_j.ims_id)) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'payment', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, v_j.fingerprint, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = excluded.fingerprint, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 결제의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS payment — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'payment_void' then                                                                 -- 2e-1b 978: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'payment' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent payment on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'credit_apply' then                                                                  -- 2e-2-1 판정 1009 · 1011: 거래 짝(credit_alloc ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent · 자동 void 없음)
    v_alabel := coalesce(public.qbo_job_doc('credit_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check credit application ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check credit application %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check credit application %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'credit_alloc', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'credit_apply_void' then                                                             -- 2e-2-1 1011: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'credit_alloc' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent credit application on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'opening_credit' then                                                                -- 2e-3-1 이견 14: 거래 짝(opening_credit ↔ 「쓰기」 CreditMemo) + 대조(TotalAmt = 붙임 금액 ∧ TotalTax 0 · 상태는 sent · 자동 void 없음)
    select * into v_oa from public.so_payment_alloc a where a.id = v_j.ims_id::uuid;
    v_alabel := coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null or p_total_tax is null then 'QuickBooks did not return TotalAmt / TotalTax — check opening credit ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> v_oa.amount or p_total_tax <> 0 then format('QuickBooks total %s / tax %s differs from IMS %s / 0 — check opening credit %s in QuickBooks (942)', p_total_amt, p_total_tax, v_oa.amount, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'opening_credit', v_j.ims_id, 'CreditMemo', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, CreditMemo, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks CreditMemo #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'opening_credit_void' then                                                           -- 2e-3-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'opening_credit' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent opening credit memo on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'opening_apply' then                                                                 -- 2e-3-1 이견 14: 거래 짝(opening_alloc ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent)
    v_alabel := coalesce(public.qbo_job_doc('opening_alloc', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check opening credit application ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check opening credit application %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check opening credit application %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'opening_alloc', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'opening_apply_void' then                                                            -- 2e-3-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'opening_alloc' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent opening credit application on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'refund' then                                                                       -- 2e-3-2-1 이견 15: 거래 짝(refund ↔ Purchase) + 대조(TotalAmt = 크레딧 몫 합 · TotalTax 0 · 상태는 sent · 자동 void 없음)
    select * into v_p from public.so_payment p where p.id = v_j.ims_id::uuid;
    select coalesce(sum(a.amount), 0) into v_applied from public.so_credit_alloc a where a.refund_payment_id = v_p.id and a.voided_at is null;
    v_alabel := public.qbo_refund_label(v_p);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check refund ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> v_applied then format('QuickBooks total %s differs from IMS %s (credit-note part of refund %s) — check it in QuickBooks (942)', p_total_amt, v_applied, v_alabel)
                       when p_total_tax is not null and p_total_tax <> 0 then format('QuickBooks tax %s is not 0 — check refund %s in QuickBooks (942)', p_total_tax, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'refund', v_j.ims_id, 'Purchase', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, p_total_tax, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = excluded.total_tax,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Purchase, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Purchase #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'refund_void' then                                                                  -- 2e-3-2-1 ⓖ-7: 거래 짝에 void 흔적(EF 는 TotalAmt 0 ∧ 「Voided - 」 로 done)
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'refund' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent refund expense on file to mark — check qbo_txn by hand'; end if;
  elsif v_j.kind = 'refund_apply' then                                                                 -- 2e-3-2-1 이견 15: 거래 짝(refund_apply ↔ 0 원 Payment · 지문 없음) + 대조(TotalAmt 0 · UnappliedAmt 0 · 상태는 sent)
    v_alabel := coalesce(public.qbo_job_doc('refund', v_j.ims_id)->>'doc_number', v_j.ims_id);
    v_mismatch := case when p_total_amt is null then 'QuickBooks did not return TotalAmt — check the zero payment of refund ' || v_alabel || ' in QuickBooks'
                       when p_total_amt <> 0 then format('QuickBooks total %s is not 0 — check the zero payment of refund %s in QuickBooks (942)', p_total_amt, v_alabel)
                       when p_unapplied_amt is not null and p_unapplied_amt <> 0 then format('QuickBooks unapplied %s is not 0 — check the zero payment of refund %s in QuickBooks (942)', p_unapplied_amt, v_alabel) end;
    begin
      insert into public.qbo_txn (realm_id, ims_kind, ims_id, qbo_type, qbo_id, doc_number, sync_token, total_amt, total_tax, mismatch, job_id, sent_at, voided_at, fingerprint, source)
      values (v_j.realm_id, 'refund_apply', v_j.ims_id, 'Payment', btrim(p_qbo_id), btrim(p_qbo_name), p_sync_token, p_total_amt, null, v_mismatch, v_j.id, now(), null, null, 'sent')
      on conflict (realm_id, ims_kind, ims_id) do update set qbo_id = excluded.qbo_id, doc_number = excluded.doc_number, sync_token = excluded.sync_token, total_amt = excluded.total_amt, total_tax = null,
        mismatch = excluded.mismatch, job_id = excluded.job_id, sent_at = now(), voided_at = null, fingerprint = null, source = 'sent', updated_at = now();
    exception when unique_violation then                                                              -- (realm, Payment, qbo_id) 가 이미 다른 IMS 행의 짝
      v_link_err := format('QuickBooks Payment #%s is already recorded for another IMS record — check both in QuickBooks and fix by hand', btrim(p_qbo_id));
    end;
    if v_link_err is null and v_mismatch is not null then
      update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, v_mismatch), 2000) where j.id = v_j.id;
    end if;
  elsif v_j.kind = 'refund_apply_void' then                                                            -- 2e-3-2-1: 거래 짝에 void 흔적
    update public.qbo_txn t set voided_at = now(), sync_token = coalesce(p_sync_token, t.sync_token), updated_at = now() where t.realm_id = v_j.realm_id and t.ims_kind = 'refund_apply' and t.ims_id = v_j.ims_id;
    get diagnostics v_n = row_count;
    if v_n <> 1 then v_link_err := 'voided in QuickBooks but IMS has no sent refund zero payment on file to mark — check qbo_txn by hand'; end if;
  end if;
  if v_link_err is not null then
    update public.qbo_job j set state = 'failed', sent_at = null, last_error = left(coalesce(j.last_error || ' · ', '') || v_link_err, 2000) where j.id = v_j.id;
  else
    update public.qbo_job j set state = 'queued', next_at = now() where j.state = 'blocked' and j.blocked_by = v_j.id;
    get diagnostics v_unblocked = row_count;
  end if;
  if v_j.kind in ('payment', 'payment_void') and v_link_err is null then                              -- 2e-1b A-10: 보낸 뒤 reconcile — 보내는 동안 붙임이 바뀌었으면 void · 다시 보내기 일감을 지금 쌓는다(in-flight 중에는 열린 payment 일감 자리가 하나라 못 쌓는다)
    begin v_sync := public.qbo_payment_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  if v_j.kind in ('credit_apply', 'credit_apply_void') and v_link_err is null then                     -- 2e-2-1 이견 8: 보낸 뒤 상태 맞추기 — 보내는 동안 떼였으면 void 일감을 쌓는다
    begin v_sync := public.qbo_credit_alloc_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  if v_j.kind in ('opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void') and v_link_err is null then   -- 2e-3-1 이견 14: 보낸 뒤 상태 맞추기 — 보내는 동안 떼였으면 void 일감을 쌓는다 · CreditMemo 가 서면 apply 는 ② 가 푼다
    begin v_sync := public.qbo_opening_alloc_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  if v_j.kind in ('refund', 'refund_void', 'refund_apply', 'refund_apply_void') and v_link_err is null then   -- 2e-3-2-1 이견 15: 보낸 뒤 상태 맞추기 — 보내는 동안 void 됐으면 void 일감을 쌓는다 · Purchase 가 서면 apply 는 ② 가 푼다
    begin v_sync := public.qbo_refund_sync(v_j.ims_id::uuid, v_j.by_staff);
    exception when others then update public.qbo_job j set warning = left(concat_ws(' · ', j.warning, 'reconcile after send failed: ' || sqlerrm), 2000) where j.id = v_j.id; end;
  end if;
  return jsonb_build_object('job_id', v_j.id, 'kind', v_j.kind, 'state', case when v_link_err is null then 'sent' else 'failed' end, 'reconcile', v_sync, 'qbo_id', btrim(p_qbo_id), 'qbo_name', btrim(p_qbo_name), 'linked', v_link_err is null, 'link_error', v_link_err, 'unblocked', v_unblocked, 'mismatch', v_mismatch);
end;
$$;

-- ═══ ① 표 · 트리거(⚠️ 일부러 끝에 — ACCESS EXCLUSIVE 잠금은 여기부터 끝까지만 · 함수는 표 CHECK 와 무관하게 먼저 선다) ═══
alter table public.qbo_job                                                                                                           -- 한 문장(왕복 0.3 s × 6 → 1 · 잠금 규칙 ④)
  drop constraint qbo_job_kind_ck,
  add  constraint qbo_job_kind_ck check (kind in ('customer', 'item', 'invoice', 'credit', 'invoice_void', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void')),
  drop constraint qbo_job_ims_kind_ck,
  add  constraint qbo_job_ims_kind_ck check (ims_kind in ('customer', 'product', 'charge', 'invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund')),
  drop constraint qbo_job_pair_ck,
  add  constraint qbo_job_pair_ck check (ims_kind = case kind when 'customer' then 'customer' when 'invoice' then 'invoice' when 'invoice_void' then 'invoice' when 'credit' then 'credit' when 'credit_void' then 'credit'
                                                                                        when 'payment' then 'payment' when 'payment_void' then 'payment' when 'credit_apply' then 'credit_alloc' when 'credit_apply_void' then 'credit_alloc'
                                                                                        when 'opening_credit' then 'opening_alloc' when 'opening_credit_void' then 'opening_alloc' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                                                        when 'refund' then 'refund' when 'refund_void' then 'refund' when 'refund_apply' then 'refund' when 'refund_apply_void' then 'refund' else ims_kind end
                                                                and (kind <> 'item' or ims_kind in ('product', 'charge')));
alter table public.qbo_txn                                                                                                           -- 한 문장
  drop constraint qbo_txn_kind_ck,
  add  constraint qbo_txn_kind_ck check (ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_credit', 'opening_alloc', 'refund', 'refund_apply')),
  drop constraint qbo_txn_type_ck,
  add  constraint qbo_txn_type_ck check (qbo_type in ('Invoice', 'CreditMemo', 'Payment', 'Purchase')),
  drop constraint qbo_txn_pair_ck,
  add  constraint qbo_txn_pair_ck check (qbo_type = case ims_kind when 'invoice' then 'Invoice' when 'credit' then 'CreditMemo' when 'opening_credit' then 'CreditMemo' when 'refund' then 'Purchase' else 'Payment' end);
create constraint trigger so_payment_refund_qbo after insert on public.so_payment deferrable initially deferred for each row when (new.kind = 'refund') execute function public.qbo_job_on_refund_insert();

-- ═══ ⑦ grant — 새 함수 전부 grant 0(claim · preview · done · 트리거 · 백필 · link_set 이 부른다) · 재발행 열은 create or replace 라 ACL 그대로 ═══
revoke all on function public.qbo_refund_from_account(uuid), public.qbo_opening_refunded_block(uuid), public.qbo_refund_label(public.so_payment), public.qbo_refund_block(uuid), public.qbo_refund_purchase_head(uuid), public.qbo_refund_credit_lines(uuid, text),
  public.qbo_refund_body(uuid), public.qbo_refund_apply_body(uuid), public.qbo_refund_apply_void_body(uuid), public.qbo_refund_void_body(uuid), public.qbo_refund_sync(uuid, uuid), public.qbo_job_on_refund_insert(), public.qbo_refund_backfill(), public.qbo_refund_requeue(uuid)
  from public, anon, authenticated, service_role;
do $$
begin
  execute format('comment on table public.qbo_job is %L', coalesce(obj_description('public.qbo_job'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-3-2-1: kind refund · refund_void(Purchase) · refund_apply · refund_apply_void(0 원 Payment)(ims_kind refund · ims_id so_payment.id · 넷 모두 그 환불 하나 · 트리거 so_payment_refund_qbo(INSERT · deferred) + so_payment_qbo_status 의 refund 가지 · 지문 없음) — 크레딧 노트 몫만(ⓖ-2) · 컷(10-30) 전 환불은 일감 0(ⓖ-5) · 컷 전 날짜로 새로 적으면 failed(ⓖ-4)');
  execute format('comment on table public.qbo_txn is %L', coalesce(obj_description('public.qbo_txn'::regclass, 'pg_class'), '') || ' · ⭐ qbo-sync-2e-3-2-1: ims_kind refund ↔ QBO Purchase(Expense · doc_number = reference) · refund_apply ↔ QBO Payment(0 원) · 한 환불(ims_id)에 둘 · fingerprint null · source sent');
  execute format('comment on function public.qbo_job_on_payment_status() is %L', coalesce(obj_description('public.qbo_job_on_payment_status()'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 이견 7] kind refund 면 qbo_refund_sync · 아니면 qbo_payment_sync 그대로 · 실패 흔적은 가지에 맞춰 refund | payment');
  execute format('comment on function public.qbo_link_set(text, text, text) is %L', coalesce(obj_description('public.qbo_link_set(text, text, text)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 이견 13] tax_rule Out of Scope (Purchase) 짝이 서면 qbo_refund_requeue(세금 짝 없음으로 failed 된 refund → queued · requeued 에 더한다)');
  execute format('comment on function public.qbo_opening_alloc_sync(uuid, uuid) is %L', coalesce(obj_description('public.qbo_opening_alloc_sync(uuid, uuid)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 ⓖ-1 (다)] 새 opening_credit 일감은 qbo_opening_refunded_block 글이 있으면 처음부터 failed(action failed) · apply 는 그 뒤 blocked');
  execute format('comment on function public.qbo_opening_credit_body(uuid) is %L', coalesce(obj_description('public.qbo_opening_credit_body(uuid)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 ⓖ-1 (다)] 환불된 이월 돈을 쓰는 붙임은 예외(qbo_opening_refunded_block 글)');
  execute format('comment on function public.qbo_job_claim(int, text[], uuid[]) is %L', coalesce(obj_description('public.qbo_job_claim(int, text[], uuid[])'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 kinds 18 · 몸 refund · refund_void · refund_apply · refund_apply_void]');
  execute format('comment on function public.qbo_job_preview(uuid) is %L', coalesce(obj_description('public.qbo_job_preview(uuid)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 몸 넷]');
  execute format('comment on function public.qbo_job_doc(text, text) is %L', coalesce(obj_description('public.qbo_job_doc(text, text)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 refund = reference(없으면 「Refund <날> <금액>」) · 손님 · 통화 · 금액 · 결제일 · active | voided]');
  execute format('comment on function public.qbo_job_list(text, text[], date, date, text, int, int) is %L', coalesce(obj_description('public.qbo_job_list(text, text[], date, date, text, int, int)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 kinds 18 · ims_name refund · txn 짝은 kind 로(refund·_void ↔ txn refund · refund_apply·_void ↔ txn refund_apply)]');
  execute format('comment on function public.qbo_job_retry(uuid, text) is %L', coalesce(obj_description('public.qbo_job_retry(uuid, text)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 이견 14: refund · refund_apply 는 환불 활성 ∧ 그 장이 QBO 에 안 섰을 때만(컷은 안 본다 = ⓖ-4 의 Send) · void 둘은 그 장이 서 있고 환불이 void 됐을 때만]');
  execute format('comment on function public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric, numeric) is %L', coalesce(obj_description('public.qbo_job_done(uuid, text, text, text, text, text, text, numeric, numeric, numeric)'::regprocedure, 'pg_proc'), '') || ' · [2e-3-2-1 이견 15: refund → qbo_txn refund Purchase(TotalAmt = 크레딧 몫 합 ∧ TotalTax 0 대조) · refund_apply → qbo_txn refund_apply Payment(TotalAmt 0 · UnappliedAmt 0 대조) · void 둘 → voided_at · 끝에 qbo_refund_sync]');
end $$;

-- ═══ ⑧ 착지 · 백필 ═══
do $$
declare v text; v_r jsonb; v_bad text := '';
begin
  select string_agg(p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')=' || coalesce(p.proacl::text, '-'), ' ' order by p.proname, p.oid) into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_refund_from_account', 'qbo_opening_refunded_block', 'qbo_refund_label', 'qbo_refund_block', 'qbo_refund_purchase_head', 'qbo_refund_credit_lines', 'qbo_refund_body', 'qbo_refund_apply_body', 'qbo_refund_apply_void_body', 'qbo_refund_void_body', 'qbo_refund_sync', 'qbo_job_on_refund_insert', 'qbo_refund_backfill', 'qbo_refund_requeue',
                                                                                        'qbo_job_done', 'qbo_job_claim', 'qbo_job_retry', 'qbo_job_list', 'qbo_job_preview', 'qbo_job_doc', 'qbo_link_set', 'qbo_job_on_payment_status', 'qbo_opening_alloc_sync', 'qbo_opening_credit_body');
  if v <> 'qbo_job_claim(p_limit integer, p_kinds text[], p_job_ids uuid[])={postgres=X/postgres,service_role=X/postgres} qbo_job_doc(p_ims_kind text, p_ims_id text)={postgres=X/postgres} qbo_job_done(p_job uuid, p_qbo_id text, p_qbo_name text, p_sync_token text, p_intuit_tid text, p_note text, p_sku text, p_total_amt numeric, p_total_tax numeric, p_unapplied_amt numeric)={postgres=X/postgres,service_role=X/postgres} qbo_job_list(p_state text, p_kinds text[], p_from date, p_to date, p_q text, p_limit integer, p_offset integer)={postgres=X/postgres,authenticated=X/postgres} qbo_job_on_payment_status()={postgres=X/postgres} qbo_job_on_refund_insert()={postgres=X/postgres} qbo_job_preview(p_job uuid)={postgres=X/postgres,authenticated=X/postgres} qbo_job_retry(p_job uuid, p_note text)={postgres=X/postgres,authenticated=X/postgres} qbo_link_set(p_kind text, p_ims_id text, p_qbo_id text)={postgres=X/postgres,authenticated=X/postgres} qbo_opening_alloc_sync(p_alloc_id uuid, p_by uuid)={postgres=X/postgres} qbo_opening_credit_body(p_alloc_id uuid)={postgres=X/postgres} qbo_opening_refunded_block(p_alloc_id uuid)={postgres=X/postgres} qbo_refund_apply_body(p_refund_id uuid)={postgres=X/postgres} qbo_refund_apply_void_body(p_refund_id uuid)={postgres=X/postgres} qbo_refund_backfill()={postgres=X/postgres} qbo_refund_block(p_refund_id uuid)={postgres=X/postgres} qbo_refund_body(p_refund_id uuid)={postgres=X/postgres} qbo_refund_credit_lines(p_refund_id uuid, p_cust_ref text)={postgres=X/postgres} qbo_refund_from_account(p_refund_id uuid)={postgres=X/postgres} qbo_refund_label(p so_payment)={postgres=X/postgres} qbo_refund_purchase_head(p_refund_id uuid)={postgres=X/postgres} qbo_refund_requeue(p_by uuid)={postgres=X/postgres} qbo_refund_sync(p_refund_id uuid, p_by uuid)={postgres=X/postgres} qbo_refund_void_body(p_refund_id uuid)={postgres=X/postgres}' then
    raise exception '⑧ ACL unexpected: %', v;
  end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_body')                is distinct from 'e1aea51849844cc5898351daaa3ef533' then v_bad := v_bad || ' qbo_payment_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_void_body')           is distinct from '4ddb45cd728222d7b676d1e0bd169a54' then v_bad := v_bad || ' qbo_payment_void_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync')                is distinct from '9efb5d9f6007048692d13cd00623c4b8' then v_bad := v_bad || ' qbo_payment_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_fingerprint')         is distinct from 'd6da0342942ef68345b9432e0e84da23' then v_bad := v_bad || ' qbo_payment_fingerprint'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_alloc_sync')           is distinct from '44419d3b499a33299e010e33671b26fa' then v_bad := v_bad || ' qbo_credit_alloc_sync'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_credit_apply_body')           is distinct from '50dcad57a35f9c83412ae437fd873726' then v_bad := v_bad || ' qbo_credit_apply_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_opening_apply_body')          is distinct from '71b0e76ec76d4c2524cd31c3452ce074' then v_bad := v_bad || ' qbo_opening_apply_body'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_job_on_payment_alloc')        is distinct from '5466ba493ed2874918e17fa84e4abfdb' then v_bad := v_bad || ' qbo_job_on_payment_alloc'; end if;
  if v_bad <> '' then raise exception '⑧ functions changed by this migration (must not):%', v_bad; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_payment'::regclass and not tgisinternal) <> 3 or (select count(*) from pg_trigger where tgname = 'so_payment_refund_qbo' and tgrelid = 'public.so_payment'::regclass and tgdeferrable and tginitdeferred) <> 1 then raise exception '⑧ so_payment triggers unexpected (must be 3: so_payment_refund_qbo deferred + so_payment_qbo_status + so_payment_touch)'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_credit_alloc'::regclass and not tgisinternal) <> 2 then raise exception '⑧ so_credit_alloc triggers changed (must stay 2)'; end if;
  v_r := public.qbo_refund_backfill();
  raise notice '⑧ refund backfill: % refund(s) queued (= refund queued + refund_apply blocked each) · % failed (blocked by a reason — see the Failed list) · % before the cut-over 2026-10-30 (no job · 990)', v_r->>'queued', v_r->>'failed', v_r->>'before_cut';
end $$;
-- 끝 — 적용 뒤: supabase/tests/qbo_sync_2e3_2_1_check.sql(-v mig 없이) → 2e-3-2-1b(EF · SEND_KINDS 18) 배포 → 첫 실물 손 Send 2 건(CR-01011 · CR-01012 몫 · 두 환불 × 두 장) → QBO 손님 10505 Open Balance 전후 · CreditMemo 172491 · 172490 RemainingCredit 0 → 그 뒤 cron 62 kinds 열둘(supabase/ops/cron.sql) · ⚠️ EF 전에 cron 을 늘리면 kindsOf 400 → 결제도 멈춘다(1034)
