-- supabase/migrations/20261110023000_qbo_pay_fix_1_payment_sync_orphan_resend.sql — qbo-pay-fix-1: 손님 결제 맞추기(qbo_payment_sync) — void 를 거둘 때 그 뒤 「다시 보내기」 일감이 skipped 부모에 영구 blocked 로 남는 결함(deferred 540) (2026-11-09 밤 토론토 · 지시서 ~/asung/prompts/qbo-pay-fix-1.md · §0 이견 1 ~ 7 답)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261110023000 --yes · supabase db push 금지
-- 무엇: ① 재발행 하나 qbo_payment_sync(원본 = DB prosrc md5 9efb5d9f6007048692d13cd00623c4b8 · pg_get_functiondef · 2026-11-10 UTC · 고친 곳 둘 = 4-5a qbo_bill_payment_sync 의 두 곳을 손님 꼴로 · 시그니처 · ACL · definer · search_path 그대로)
--         ①-a QBO 에 서 있고 지문이 같아져 안 나간 void 를 거둘 때, 그 뒤에 섰던 열린 payment 일감(queued · blocked · failed)도 skipped
--         ①-b 지문이 달라 void 가 설 때(또는 이미 서 있을 때) blocked payment 일감도 그 void 뒤로(옛: queued · failed 만 → 거둔 void 뒤에 남은 일감은 새 void 가 나가도 영영 안 풀렸다)
--       ② 운영에 걸린 일감 하나를 푼다 — 조건(id + 아직 blocked + 부모 payment_void skipped + qbo_txn.voided_at 있음 + 지금 지문 not null)이 하나라도 어긋나면 0 행 · 풀린 행 수는 NOTICE · 풀리면 cron 62 가 지금 붙임대로 새 Payment 를 보낸다
-- 넣지 않은 것(이견 3): 사람이 void 를 Skip 할 때 뒤 일감이 남는 꼴(qbo_job_skip · qbo_job_on_invoice_cancel 류 · 모든 kind) — 새 deferred · 다른 맞추기 함수 셋(credit_alloc · opening_alloc · refund)은 void 를 거두는 갈래가 없어 무변
-- 잠금: 함수 재발행(카탈로그) + qbo_job 한 행 update — 표 잠금 없음 · 새 표 · 칸 · CHECK · 트리거 · 시퀀스 0 · EF · 화면 · cron 무변
-- ⚠️ 공개 레포 — 손님 상호 없음 · UI 글자는 영어
-- 검증 supabase/tests/qbo_pay_fix_1_check.sql(운영 메인 begin → rollback · 가짜 재료만) · 적용은 Caleb

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

-- ═══════════════ ⓪ 재발행 원본 가드 — DB prosrc md5 · 같은 이름 하나 ═══════════════
do $$
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync') <> 1 then
    raise exception 'qbo-pay-fix-1: expected exactly one public.qbo_payment_sync — nothing was changed';
  end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_payment_sync') is distinct from '9efb5d9f6007048692d13cd00623c4b8' then
    raise exception 'qbo-pay-fix-1: public.qbo_payment_sync is not the body this migration was written against (already applied, or changed since) — nothing was changed';
  end if;
end $$;

-- ═══════════════ ① qbo_payment_sync 재발행 — 고친 곳 둘([qbo-pay-fix-1 ①] · [qbo-pay-fix-1 ②]) ═══════════════
CREATE OR REPLACE FUNCTION public.qbo_payment_sync(p_payment_id uuid, p_by uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_realm text := (select c.realm_id from public.qbo_connection c where c.singleton); v_p public.so_payment%rowtype; v_fp text; v_t public.qbo_txn%rowtype; v_pj public.qbo_job%rowtype; v_vj public.qbo_job%rowtype; v_act text := 'none'; v_vid uuid;
begin
  if v_realm is null then return jsonb_build_object('action', 'no_connection'); end if;
  select * into v_p from public.so_payment p where p.id = p_payment_id;
  if v_p.id is null or v_p.kind <> 'payment' or v_p.method = 'opening' then return jsonb_build_object('action', 'not_applicable'); end if;   -- 환불은 2e-3 · 이월 받아 둔 돈은 보내지 않는다(341 · A-8)
  v_fp := public.qbo_payment_fingerprint(v_p.id);
  select * into v_t  from public.qbo_txn t where t.realm_id = v_realm and t.ims_kind = 'payment' and t.ims_id = v_p.id::text;
  select * into v_pj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment'      and j.ims_kind = 'payment' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  select * into v_vj from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment_void' and j.ims_kind = 'payment' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc, j.id desc limit 1;
  if v_t.id is null then                                                                                                               -- 보낸 적 없다
    if v_pj.id is null then
      if v_fp is not null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff) values (v_realm, 'payment', 'payment', v_p.id::text, 'queued', p_by)
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'queued';
      end if;
    elsif v_pj.state in ('queued', 'blocked', 'failed') then
      if v_fp is null then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment voided or fully detached before sending'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'skipped';
      elsif v_pj.state = 'failed' and v_fp is distinct from v_pj.fingerprint then
        update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: the payment changed after it failed'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'requeued';
      end if;                                                                                                                          -- queued · blocked 는 그대로(claim 이 그때의 상태로 몸을 다시 만든다)
    elsif v_pj.state in ('sending', 'unknown') then                                                                                   -- 닿았는지 모른다 → void 를 그 일감 뒤에(2b1 cancel 꼴) · 다시 보내기는 done 의 reconcile 이 쌓는다
      if v_fp is distinct from v_pj.fingerprint and v_vj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'payment_void', 'payment', v_p.id::text, 'blocked', v_pj.id, p_by, 'changed while sending — void after the send settles')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'void_after_send';
      end if;
    end if;
  elsif v_t.voided_at is null then                                                                                                     -- QBO 에 서 있다
    if v_fp is not distinct from v_t.fingerprint then                                                                                 -- IMS = QBO 그대로(떼었다가 똑같이 다시 붙인 경우) → 아직 안 나간 void 는 거둔다 · 나가는 중이면 다시 보내기를 그 뒤에
      if v_vj.id is not null and v_vj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment restored to what QuickBooks has — void not needed'), 2000), updated_by = p_by where j.id = v_vj.id;
        if v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then                                              -- [qbo-pay-fix-1 ①] 그 void 뒤에 섰던 다시 보내기도 거둔다(skipped 부모는 claim ② 가 못 푼다 · 4-5a 꼴 · deferred 540)
          update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment restored to what QuickBooks has — nothing to send again'), 2000), updated_by = p_by where j.id = v_pj.id;
        end if;
        return jsonb_build_object('action', 'void_cancelled', 'fingerprint', v_fp);
      elsif v_vj.id is not null and v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'payment', 'payment', v_p.id::text, 'blocked', v_vj.id, p_by, 'sent again after the void that is under way')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        return jsonb_build_object('action', 'resend_after_void', 'fingerprint', v_fp);
      end if;
      return jsonb_build_object('action', 'same', 'fingerprint', v_fp);
    end if;
    if v_vj.id is null then
      insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note)
      values (v_realm, 'payment_void', 'payment', v_p.id::text, 'queued', p_by, case when v_fp is null then 'payment voided or fully detached — void in QuickBooks' else 'payment changed — void, then send again' end)
      on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing returning id into v_vid;
      if v_vid is null then select j.id into v_vid from public.qbo_job j where j.realm_id = v_realm and j.kind = 'payment_void' and j.ims_kind = 'payment' and j.ims_id = v_p.id::text and j.state not in ('sent', 'skipped') order by j.created_at desc limit 1; end if;
    else v_vid := v_vj.id; end if;
    if v_fp is not null then
      if v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, blocked_by, by_staff, note) values (v_realm, 'payment', 'payment', v_p.id::text, 'blocked', v_vid, p_by, 'sent again after the void')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
      elsif v_pj.state in ('queued', 'failed', 'blocked') and v_pj.blocked_by is distinct from v_vid then                        -- [qbo-pay-fix-1 ②] blocked 도 이 void 뒤로 옮긴다(claim 이 void 뒤에 몸을 다시 만든다 · 4-5a 꼴 · deferred 540)
        update public.qbo_job j set state = 'blocked', blocked_by = v_vid, claimed_at = null, next_at = now(), request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'waits for the void of the earlier QuickBooks payment'), 2000), updated_by = p_by where j.id = v_pj.id;
      end if;
      v_act := 'void_and_resend';
    else
      if v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
        update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment voided or fully detached — only the void goes'), 2000), updated_by = p_by where j.id = v_pj.id;
      end if;
      v_act := 'void';
    end if;
  else                                                                                                                                 -- QBO 쪽은 void 됐다
    if v_fp is not null then
      if v_pj.id is null then
        insert into public.qbo_job (realm_id, kind, ims_kind, ims_id, state, by_staff, note) values (v_realm, 'payment', 'payment', v_p.id::text, 'queued', p_by, 'sent again after the void')
        on conflict (realm_id, kind, ims_kind, ims_id) where state not in ('sent', 'skipped') do nothing;
        v_act := 'resend';
      elsif v_pj.state = 'failed' and v_fp is distinct from v_pj.fingerprint then
        update public.qbo_job j set state = 'queued', next_at = now(), claimed_at = null, request_id = gen_random_uuid(), note = left(concat_ws(' · ', j.note, 'sent again: the payment changed after it failed'), 2000), updated_by = p_by where j.id = v_pj.id;
        v_act := 'requeued';
      end if;
    elsif v_pj.id is not null and v_pj.state in ('queued', 'blocked', 'failed') then
      update public.qbo_job j set state = 'skipped', claimed_at = null, blocked_by = null, note = left(concat_ws(' · ', j.note, 'payment voided or fully detached before sending'), 2000), updated_by = p_by where j.id = v_pj.id;
      v_act := 'skipped';
    end if;
  end if;
  return jsonb_build_object('action', v_act, 'fingerprint', v_fp);
end;
$function$;

comment on function public.qbo_payment_sync(uuid, uuid) is 'qbo-sync-2e-1b 판정 978 · 988 · A-10(속 · grant 0): 결제 하나의 QBO 일감을 IMS 상태(지문)에 맞춘다 — 보낸 적 없음: fp 있으면 payment queued · 열린 queued · blocked 그대로 · failed 는 fp 바뀌면 되살림 · fp 없으면 skipped · sending · unknown 이면 payment_void 를 그 일감 뒤에(2b1 꼴) / QBO 에 서 있음: fp 같으면 아무것도(안 나간 void 일감이 있으면 거둔다 · 나가는 중이면 다시 보내기를 그 뒤에) · 다르면 payment_void queued + fp 있으면 payment blocked_by void(없으면 void 만 · 열린 payment 는 skipped) / QBO 쪽 void 됨: fp 있으면 payment queued · 환불 · 이월 받아 둔 돈 · 연결 없음은 not_applicable · 돌려주는 것 = { action · fingerprint } · 부르는 곳 = 트리거 둘 · done 의 reconcile · 백필 · requeue · [qbo-pay-fix-1 · deferred 540] 서 있는데 fp 가 같아져 void 를 거둘 때 그 뒤에 섰던 열린 payment 일감(queued · blocked · failed)도 skipped · fp 가 달라 새 void 가 서면 blocked payment 일감도 그 void 뒤로 옮긴다(4-5a qbo_bill_payment_sync 와 같은 두 곳)';

-- ═══════════════ ② 운영에 걸린 일감 하나 풀기(조건이 어긋나면 0 행) ═══════════════
do $$
declare v_n int;
begin
  update public.qbo_job j
     set state = 'queued', blocked_by = null, claimed_at = null, next_at = now(), request_id = gen_random_uuid(),
         note = left(concat_ws(' · ', j.note, 'released by qbo-pay-fix-1: the void it waited for was withdrawn and a later void already went — sent again with the payment as it is now'), 2000)
   where j.id = 'a5bd4e28-caf3-4012-afa6-c7b337c8bc44'
     and j.kind = 'payment' and j.ims_kind = 'payment' and j.ims_id = '15e70a27-36da-4240-bb9b-047f6b8a70e3'
     and j.state = 'blocked'
     and exists (select 1 from public.qbo_job p where p.id = j.blocked_by and p.kind = 'payment_void' and p.ims_kind = 'payment' and p.ims_id = j.ims_id and p.state = 'skipped')
     and exists (select 1 from public.qbo_txn t where t.realm_id = j.realm_id and t.ims_kind = 'payment' and t.ims_id = j.ims_id and t.voided_at is not null)
     and public.qbo_payment_fingerprint('15e70a27-36da-4240-bb9b-047f6b8a70e3'::uuid) is not null;
  get diagnostics v_n = row_count;
  raise notice 'qbo-pay-fix-1: released % stuck payment job(s) (expected 1 — 0 means its state changed before this ran, look at the job)', v_n;
end $$;

-- ═══════════════ ③ 끝 확인 — 새 몸 md5 · 같은 이름 하나 · ACL 그대로 ═══════════════
do $$
declare v text;
begin
  select md5(p.prosrc) || ' ' || coalesce(p.proacl::text, '-') || ' ' || p.prosecdef::text || ' ' || (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'qbo_payment_sync')::text into v
    from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'qbo_payment_sync';
  if v is distinct from '12492822dfb7755effd4ac027eee0e99 {postgres=X/postgres} true 1' then
    raise exception 'qbo-pay-fix-1: after-check failed (%) — nothing was saved', v;
  end if;
end $$;
