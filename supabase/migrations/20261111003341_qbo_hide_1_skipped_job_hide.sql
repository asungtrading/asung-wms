-- 20261111003341_qbo_hide_1_skipped_job_hide.sql — qbo-hide-1 · Skip 한 QuickBooks 일감을 골라 숨기기 (판정 1152 + 보충 · Caleb 2026-11-10 · 지시서 ~/asung/prompts/qbo-hide-1.md)
-- [Asung-IMS · 운영 메인] 적용은 Caleb: psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일> → migration repair · ⚠️ db push 금지 · 이 파일에 begin · commit 없음
-- 무엇:
--   A 표 qbo_job 칸 둘 hidden_at · hidden_by(ims_staff) + CHECK qbo_job_hidden_only_skipped_ck(숨김은 skipped 만 · 두 칸은 함께)
--   B 트리거 qbo_job_touch_hidden(BEFORE UPDATE · 이름 순으로 qbo_job_touch 뒤 · WHEN 이 거짓이면 함수를 부르지 않는다 — cron 61 · 62 의 update 는 식 비교뿐)
--       ① skipped 를 벗어나는 update(old skipped → new 그 밖 · 어떤 길로든 — state 를 쓰는 update 66 문장 · 함수 22 개를 한 곳에서)면 숨김 두 칸을 비운다(판정 ⑤)
--       ② 숨김 칸만 바뀐 update 면 updated_at · updated_by 를 old 로 되돌린다(보충 이견 1 (가) — Skip 한 사람 · 시각은 updated_* 에만 있다)
--       · skipped 아닌 줄에 hidden_at 을 직접 넣는 것은 트리거가 고치지 않고 CHECK 가 거부한다(보충 이견 2)
--   C 창구 qbo_job_hide(p_jobs uuid[], p_hide boolean) — 열쇠 qbo(쓰기 · qbo_key_gate(true) · qbo_job_skip 과 같은 문) · 전부 아니면 아무것도(빈 배열 · 중복 · 없는 id · 다른 realm · 숨기는데 skipped 아님 · blocked 일감이 기다리는 것(보충 이견 3)) · 멱등(already) · 반환 {changed, already, hidden}
--   D qbo_job_list 재발행(시그니처 그대로 · 원본 = DB prosrc md5 a853b47b76e899e44ebbb270779e2a26 = 20261110034500 의 정의 · 바뀐 줄 넷: 상태 값 hidden · 행 칸 hidden_at · hidden_by_name · where · counts) → 새 몸 md5 e123778349c5491e728857dc59c17c72
--       p_state 'hidden' = state skipped ∧ hidden_at 있음 · 그 밖의 모든 보기(null · open · skipped · …)는 hidden_at is null 만 · counts = 상태마다 숨기지 않은 수 + hidden(숨긴 수 · 늘 있다 · 0 포함)
-- 무접촉: qbo_job_retry · qbo_job_skip · qbo_job_claim · 그 밖의 qbo_ 함수 · EF · cron · 화면 · 실제 행(숨긴 일감 0 으로 시작)
-- 검증: supabase/tests/qbo_hide_1_check.sql

-- ═══ A) 칸 둘 + CHECK ═══
alter table public.qbo_job add column hidden_at timestamptz, add column hidden_by uuid references public.ims_staff(id);
alter table public.qbo_job add constraint qbo_job_hidden_only_skipped_ck check ((hidden_at is null or state = 'skipped') and ((hidden_at is null) = (hidden_by is null)));
comment on column public.qbo_job.hidden_at is 'qbo-hide-1 판정 1152: 이 Skip 한 일감을 목록에서 접어 둔 시각(null = 보임) · skipped 일 때만 · qbo_job_hide 로만 쓴다 · skipped 를 벗어나면 트리거 qbo_job_touch_hidden 이 비운다';
comment on column public.qbo_job.hidden_by is 'qbo-hide-1 판정 1152: 숨긴 직원 · hidden_at 과 함께 있거나 함께 없다';

-- ═══ B) 트리거 — skipped 를 벗어나면 숨김 풀기 · 숨김 칸만 바뀌면 updated_* 지키기 ═══
create function public.qbo_job_touch_hidden() returns trigger
  language plpgsql set search_path = public, pg_temp
as $function$
begin
  if old.state = 'skipped' and new.state <> 'skipped' and old.hidden_at is not null then
    new.hidden_at := null; new.hidden_by := null;                       -- 판정 1152 ⑤: skipped 를 벗어나면(어떤 길로든) 숨김이 풀린다
  elsif (to_jsonb(new) - array['hidden_at', 'hidden_by', 'updated_at', 'updated_by']) = (to_jsonb(old) - array['hidden_at', 'hidden_by', 'updated_at', 'updated_by']) then
    new.updated_at := old.updated_at; new.updated_by := old.updated_by;   -- 보충 이견 1 (가): 숨김 칸만 바뀐 update 는 「누가 언제 Skip 했나」(updated_*)를 덮지 않는다 — qbo_job_touch 가 방금 쓴 값을 되돌린다
  end if;
  return new;
end;
$function$;
comment on function public.qbo_job_touch_hidden() is 'qbo-hide-1 판정 1152 ⑤ · 보충 이견 1 · 2: qbo_job BEFORE UPDATE(qbo_job_touch 뒤) — ① old skipped → new 그 밖이면 hidden_at · hidden_by 를 비운다 ② 숨김 칸만 바뀐 update 면 updated_at · updated_by 를 old 로 되돌린다(Skip 한 사람 · 시각 지킴) · 그 밖은 손대지 않는다(직접 넣기는 CHECK 가 거부)';
revoke all on function public.qbo_job_touch_hidden() from public, anon, authenticated, service_role;
create trigger qbo_job_touch_hidden before update on public.qbo_job for each row
  when ((old.hidden_at is distinct from new.hidden_at) or (old.hidden_at is not null and new.state <> 'skipped'))
  execute function public.qbo_job_touch_hidden();

-- ═══ C) 창구 qbo_job_hide ═══
create function public.qbo_job_hide(p_jobs uuid[], p_hide boolean) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $function$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_n int := coalesce(cardinality(p_jobs), 0); v_distinct int; v_found int; v_not_skipped int; v_waited int; v_changed int;
begin
  if p_hide is null then raise exception 'Say whether to hide (true) or show again (false) — nothing was changed'; end if;
  if v_n = 0 then raise exception 'Pick at least one job — nothing was changed'; end if;
  if v_n > 500 then raise exception 'Too many jobs at once (% — at most 500) — nothing was changed', v_n; end if;
  if array_position(p_jobs, null) is not null then raise exception 'The list of jobs has an empty entry — nothing was changed'; end if;
  select count(distinct x.id) into v_distinct from unnest(p_jobs) as x(id);
  if v_distinct <> v_n then raise exception '% of the % picked jobs are listed more than once — nothing was changed', v_n - v_distinct, v_n; end if;
  perform 1 from public.qbo_job j where j.id = any (p_jobs) and j.realm_id = v_realm order by j.id for update;
  select count(*), count(*) filter (where j.state <> 'skipped') into v_found, v_not_skipped from public.qbo_job j where j.id = any (p_jobs) and j.realm_id = v_realm;
  if v_found <> v_n then raise exception '% of the % picked jobs were not found in this QuickBooks company — nothing was changed', v_n - v_found, v_n; end if;
  if p_hide then
    if v_not_skipped > 0 then raise exception 'Only skipped jobs can be hidden — % of the % picked jobs are not skipped — nothing was changed', v_not_skipped, v_n; end if;
    select count(distinct c.blocked_by) into v_waited from public.qbo_job c where c.blocked_by = any (p_jobs) and c.state = 'blocked';
    if v_waited > 0 then raise exception '% of the % picked jobs still have other jobs waiting on them (blocked) — settle those first — nothing was changed', v_waited, v_n; end if;
    update public.qbo_job j set hidden_at = now(), hidden_by = v_staff where j.id = any (p_jobs) and j.realm_id = v_realm and j.state = 'skipped' and j.hidden_at is null;
  else
    update public.qbo_job j set hidden_at = null, hidden_by = null where j.id = any (p_jobs) and j.realm_id = v_realm and j.hidden_at is not null;
  end if;
  get diagnostics v_changed = row_count;
  return jsonb_build_object('changed', v_changed, 'already', v_n - v_changed, 'hidden', p_hide);
end;
$function$;
comment on function public.qbo_job_hide(uuid[], boolean) is 'qbo-hide-1 판정 1152(열쇠 qbo 쓰기): Skip 한 일감을 골라 숨기기(p_hide true) · 다시 보이기(false) — 지금 realm 의 일감만 · 전부 아니면 아무것도(빈 배열 · 중복 · 없는 id · 다른 realm · 숨기는데 skipped 아님 · blocked 일감이 기다리는 일감) · 이미 그 상태면 세기만(already) · 반환 {changed, already, hidden} · updated_at · updated_by 는 그대로(트리거 qbo_job_touch_hidden)';
revoke all on function public.qbo_job_hide(uuid[], boolean) from public, anon, authenticated, service_role;
grant execute on function public.qbo_job_hide(uuid[], boolean) to authenticated;

-- ═══ D) qbo_job_list 재발행 — 시그니처 그대로 · 바뀐 줄 넷(-- qbo-hide-1 표시) ═══
CREATE OR REPLACE FUNCTION public.qbo_job_list(p_state text DEFAULT NULL::text, p_kinds text[] DEFAULT NULL::text[], p_from date DEFAULT NULL::date, p_to date DEFAULT NULL::date, p_q text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_lim int := least(greatest(coalesce(p_limit, 50), 1), 200); v_off int := greatest(coalesce(p_offset, 0), 0); v_q text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if p_state is not null and p_state not in ('queued', 'blocked', 'sending', 'sent', 'failed', 'unknown', 'skipped', 'open', 'hidden') then raise exception 'state must be one of queued, blocked, sending, sent, failed, unknown, skipped, open, hidden (got %)', p_state; end if;   -- qbo-hide-1 + hidden
  if p_kinds is not null and (not (p_kinds <@ array['customer', 'item', 'invoice', 'invoice_void', 'credit', 'credit_void', 'payment', 'payment_void', 'credit_apply', 'credit_apply_void', 'opening_credit', 'opening_credit_void', 'opening_apply', 'opening_apply_void', 'refund', 'refund_void', 'refund_apply', 'refund_apply_void', 'cost_day', 'vendor', 'bill', 'vendor_credit', 'bill_delete_manual', 'bill_payment', 'bill_payment_void']) or coalesce(array_length(p_kinds, 1), 0) = 0) then raise exception 'kinds must be among customer, item, invoice, invoice_void, credit, credit_void, payment, payment_void, credit_apply, credit_apply_void, opening_credit, opening_credit_void, opening_apply, opening_apply_void, refund, refund_void, refund_apply, refund_apply_void, cost_day, vendor, bill, vendor_credit, bill_delete_manual, bill_payment, bill_payment_void (got %)', p_kinds; end if;   -- 4-5a kinds 25   -- 2e-3-2-1 kinds 18 · 3-2b cost_day 19
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
                             when 'po_payment' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-5a 공급처 결제 = 「reference · 공급처 · 통화 금액」
                             when 'cost_sheet' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '')   -- 3-2b 하루 원가 장 = 「COGS-… · Cost day <날> <창고>」
                             when 'po_invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-3a 공급처 인보이스 Bill
                             when 'po_credit' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-3a 공급처 크레딧 VendorCredit
                             when 'po_discount' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-7a 조기 결제 할인 VendorCredit
                             when 'po_charge' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')   -- 4-3a 비용 문서 Bill
                             when 'supplier' then coalesce(d.doc->>'name', j.ims_id)   -- 4-3a Vendor
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', j.ims_id) end as ims_name,
             (select s.name from public.ims_staff s where s.id = j.by_staff) as by_name,
             j.hidden_at, (select s.name from public.ims_staff s where s.id = j.hidden_by) as hidden_by_name,   -- qbo-hide-1 판정 1152: 누가 언제 숨겼나
             p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
             t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at
      from public.qbo_job j
      cross join lateral (select public.qbo_job_doc(j.ims_kind, j.ims_id) as doc) d
      left join public.qbo_job p on p.id = j.blocked_by
      left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc) pd on p.id is not null
      left join public.qbo_txn t on t.realm_id = j.realm_id and t.ims_id = j.ims_id and j.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet', 'po_invoice', 'po_credit', 'po_charge', 'po_payment', 'po_discount')   -- 4-7a + po_discount   -- 2e-3-2-1 + refund · 3-2b + cost_sheet(JournalEntry)
                               and t.ims_kind = case j.kind when 'opening_credit' then 'opening_credit' when 'opening_credit_void' then 'opening_credit' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                            when 'refund_apply' then 'refund_apply' when 'refund_apply_void' then 'refund_apply' else j.ims_kind end   -- 2e-3-1 이견 3: 한 붙임에 txn 둘 — kind 로 갈라 잇는다 · 2e-3-2-1 이견 8: 환불도(refund · refund_void ↔ txn refund(Purchase) · refund_apply · _void ↔ txn refund_apply(Payment))
      where j.realm_id = v_realm and case when p_state = 'hidden' then j.state = 'skipped' and j.hidden_at is not null   -- qbo-hide-1 판정 1152: hidden = 숨긴 Skip 만 · 그 밖의 모든 보기는 숨기지 않은 것만
                                          else j.hidden_at is null and (p_state is null or (p_state = 'open' and j.state not in ('sent', 'skipped')) or j.state = p_state) end
        and (p_kinds is null or j.kind = any (p_kinds))
        and (p_from is null or (j.created_at at time zone 'America/Toronto')::date >= p_from) and (p_to is null or (j.created_at at time zone 'America/Toronto')::date <= p_to)),
    hit as (select b.* from base b where v_q is null or b.ims_name ilike '%' || v_q || '%' or coalesce(b.qbo_id, '') ilike '%' || v_q || '%' or coalesce(b.qbo_name, '') ilike '%' || v_q || '%')
    select jsonb_build_object('state', p_state, 'kinds', to_jsonb(p_kinds), 'from', p_from, 'to', p_to, 'q', v_q, 'total', (select count(*) from hit), 'limit', v_lim, 'offset', v_off,
      'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) || jsonb_build_object('hidden', coalesce(sum(x.h), 0)) from (select j.state, count(*) filter (where j.hidden_at is null) as n, count(*) filter (where j.hidden_at is not null) as h from public.qbo_job j where j.realm_id = v_realm group by j.state) x),   -- qbo-hide-1: 상태 수는 숨기지 않은 것만 · hidden = 숨긴 수(늘 있다)
      'rows', coalesce((select jsonb_agg((to_jsonb(b) - 'rk' - 'k_old') order by b.rk, b.k_old, b.created_at desc) from (
                select h.*, case h.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end as rk, case when h.state in ('queued', 'blocked') then h.created_at end as k_old
                  from hit h order by 
                    case h.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end,
                    case when h.state in ('queued', 'blocked') then h.created_at end asc nulls last, h.created_at desc
                  limit v_lim offset v_off) b), '[]'::jsonb)));
end;
$function$;
do $$
begin
  execute format('comment on function public.qbo_job_list(text, text[], date, date, text, int, int) is %L', coalesce(obj_description('public.qbo_job_list(text, text[], date, date, text, int, int)'::regprocedure, 'pg_proc'), '') || ' · [qbo-hide-1 판정 1152: p_state hidden = 숨긴 Skip(state skipped ∧ hidden_at) · 그 밖의 모든 보기는 숨기지 않은 것만 · counts 는 숨기지 않은 수 + hidden · 행에 hidden_at · hidden_by_name]');
end $$;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select (select md5(p.prosrc) || ' ' || p.proacl::text from pg_proc p where p.oid = 'public.qbo_job_list(text, text[], date, date, text, int, int)'::regprocedure)
      || ' | ' || (select p.proacl::text || ' ' || p.prosecdef::text from pg_proc p where p.oid = 'public.qbo_job_hide(uuid[], boolean)'::regprocedure)
      || ' | ' || (select string_agg(t.tgname, ',' order by t.tgname) from pg_trigger t where t.tgrelid = 'public.qbo_job'::regclass and not t.tgisinternal and t.tgtype & 2 = 2)
      || ' | ' || (select count(*) from public.qbo_job j where j.hidden_at is not null or j.hidden_by is not null)::text into v;
  if v is distinct from 'e123778349c5491e728857dc59c17c72 {postgres=X/postgres,authenticated=X/postgres} | {postgres=X/postgres,authenticated=X/postgres} true | qbo_job_touch,qbo_job_touch_hidden | 0' then
    raise exception 'qbo-hide-1 landing check failed (%) — nothing was saved', v;
  end if;
end $$;
