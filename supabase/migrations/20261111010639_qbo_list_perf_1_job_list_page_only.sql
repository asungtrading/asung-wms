-- 20261111010639_qbo_list_perf_1_job_list_page_only.sql — qbo-list-perf-1 · QuickBooks 보내기 목록 All · Sent 보기 시간 초과 고치기 (deferred 561 · Caleb 2026-11-10 「만들자」 · 지시서 ~/asung/prompts/qbo-list-perf-1.md)
-- [Asung-IMS · 운영 메인] 적용은 Caleb: psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일> → migration repair · ⚠️ db push 금지 · 이 파일에 begin · commit 없음
-- 무엇: qbo_job_list 재발행 하나(시그니처 · 반환 꼴 · 정렬 · 거르기 뜻 그대로 · 원본 = DB prosrc md5 e123778349c5491e728857dc59c17c72 = 20261111003341 의 정의) → 새 몸 md5 8342809117f91827f0bcc8c2ba57f2d8
--   느린 까닭(실측 11-10 밤 · 일감 942): 문서 요약 qbo_job_doc 한 번 ≈ 1.3 ms 인데 ① 옆 서브쿼리 (select qbo_job_doc(…) as doc) 가 펴져 d.doc 을 읽는 칸마다 다시 불렸다(참조 1 번 1.25 s → 4 번 4.07 s → offset 0 을 두면 4 번도 1.24 s)
--     ② 그것을 거른 행 전부에(sent 785) + 기다리는 부모 요약도 전부에(blocked_by 가 남은 행 333) ⇒ All 10.4 s · Sent 12.1 s — 화면(authenticated) 한도 8 s 를 넘는다
--   고친 것: A 거르기 · 세기 · 정렬은 qbo_job 만으로(CTE f) · B 찾기(p_q)가 없으면 한 쪽(limit ≤ 200)을 먼저 고르고 그 행에만 요약 · 찾기가 있으면 거른 행 전부에 요약(찾기가 ims_name 을 본다 — 뜻 그대로)하되 행마다 한 번(offset 0)
--            C 기다리는 부모 요약 · QuickBooks 거래 짝(qbo_txn) · 직원 이름은 늘 한 쪽의 행에만 · counts 줄은 글자 그대로
--   같음의 근거: 부모 잇기(PK) · qbo_txn 잇기(유니크 qbo_txn_ims_key realm_id · ims_kind · ims_id)는 행 수를 바꾸지 않는다 → total = 거른 일감 수 · 정렬 열쇠(상태 순위 · queued/blocked 의 created_at · created_at desc)는 요약을 안 쓴다
-- 무접촉: qbo_job_doc(md5 9d6a689d2b3814991deabe6310597931) · 그 밖의 qbo_ 함수 · 표 · 색인 · 트리거 · EF · cron · 화면 · 실제 행
-- 검증: supabase/tests/qbo_list_perf_1_check.sql

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
  -- qbo-list-perf-1(deferred 561): 느린 까닭 = 문서 요약 qbo_job_doc 이 「한 행에 한 번」 이 아니라 d.doc 을 읽는 칸마다(행마다 열 번 남짓) 다시 불렸다(옆 서브쿼리가 펴져서) + 거른 행 전부에 불렸다
  --   ⇒ 요약은 offset 0 서브쿼리로 한 번만 · 찾기(p_q)가 없으면 화면에 나갈 한 쪽의 행에만 · 기다리는 부모 요약 · QuickBooks 거래 짝 · 직원 이름은 늘 한 쪽의 행에만 · 반환 꼴 · 정렬 · 거르기 뜻은 그대로
  return (with f as materialized (   -- 거르기 · 정렬 열쇠는 qbo_job 만으로(문서 요약을 안 쓴다)
      select j.id, j.realm_id, j.kind, j.ims_kind, j.ims_id, j.state, j.attempts, j.next_at, j.claimed_at, j.blocked_by, j.qbo_id, j.qbo_name, j.sent_at, j.last_error, j.last_intuit_tid, j.warning, j.note, j.by_staff, j.created_at, j.updated_at, j.hidden_at, j.hidden_by,
             case j.state when 'unknown' then 0 when 'failed' then 1 when 'sending' then 2 when 'queued' then 3 when 'blocked' then 4 else 5 end as rk, case when j.state in ('queued', 'blocked') then j.created_at end as k_old
      from public.qbo_job j
      where j.realm_id = v_realm and case when p_state = 'hidden' then j.state = 'skipped' and j.hidden_at is not null   -- qbo-hide-1 판정 1152: hidden = 숨긴 Skip 만 · 그 밖의 모든 보기는 숨기지 않은 것만
                                          else j.hidden_at is null and (p_state is null or (p_state = 'open' and j.state not in ('sent', 'skipped')) or j.state = p_state) end
        and (p_kinds is null or j.kind = any (p_kinds))
        and (p_from is null or (j.created_at at time zone 'America/Toronto')::date >= p_from) and (p_to is null or (j.created_at at time zone 'America/Toronto')::date <= p_to)
      ),
    pg0 as materialized (select f.id from f where v_q is null order by f.rk, f.k_old asc nulls last, f.created_at desc limit v_lim offset v_off),   -- 찾기 없음: 한 쪽을 먼저 고른다
    e as materialized (   -- 문서 요약이 필요한 행만: 찾기가 있으면 거른 행 전부(찾기가 ims_name 을 본다) · 없으면 그 한 쪽
      select n.*, d.doc,
             case n.ims_kind when 'invoice' then coalesce(d.doc->>'doc_number', '') || ' · ' || coalesce(d.doc->>'name', '') || ' · ' || coalesce(d.doc->>'currency', '') || ' ' || coalesce(d.doc->>'total', '')
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
                             when 'supplier' then coalesce(d.doc->>'name', n.ims_id)   -- 4-3a Vendor
                             when 'product' then coalesce(d.doc->>'doc_number', '') || ' ' || coalesce(d.doc->>'name', '')
                             else coalesce(d.doc->>'name', n.ims_id) end as ims_name
      from (select f.* from f where v_q is not null or f.id in (select pg0.id from pg0) offset 0) n
      cross join lateral (select public.qbo_job_doc(n.ims_kind, n.ims_id) as doc offset 0) d),   -- offset 0: 요약을 행마다 한 번만
    hit as (select e.* from e where v_q is null or e.ims_name ilike '%' || v_q || '%' or coalesce(e.qbo_id, '') ilike '%' || v_q || '%' or coalesce(e.qbo_name, '') ilike '%' || v_q || '%'),
    pg as materialized (select h.* from hit h order by h.rk, h.k_old asc nulls last, h.created_at desc limit v_lim offset case when v_q is null then 0 else v_off end)   -- 찾기 없음이면 e 가 이미 그 한 쪽
    select jsonb_build_object('state', p_state, 'kinds', to_jsonb(p_kinds), 'from', p_from, 'to', p_to, 'q', v_q, 'total', case when v_q is null then (select count(*) from f) else (select count(*) from hit) end, 'limit', v_lim, 'offset', v_off,
      'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) || jsonb_build_object('hidden', coalesce(sum(x.h), 0)) from (select j.state, count(*) filter (where j.hidden_at is null) as n, count(*) filter (where j.hidden_at is not null) as h from public.qbo_job j where j.realm_id = v_realm group by j.state) x),   -- qbo-hide-1: 상태 수는 숨기지 않은 것만 · hidden = 숨긴 수(늘 있다)
      'rows', coalesce((select jsonb_agg((to_jsonb(b) - 'rk' - 'k_old') order by b.rk, b.k_old, b.created_at desc) from (
                select g.id, g.kind, g.ims_kind, g.ims_id, g.state, g.attempts, g.next_at, g.claimed_at, g.blocked_by, g.qbo_id, g.qbo_name, g.sent_at, g.last_error, g.last_intuit_tid, g.warning, g.note, g.by_staff, g.created_at, g.updated_at,
                       (g.created_at at time zone 'America/Toronto')::date as job_date,
                       g.doc->>'doc_number' as doc_number, g.doc->>'name' as name, g.doc->>'currency' as currency, (g.doc->>'total')::numeric as total, (g.doc->>'doc_date')::date as doc_date, g.doc->>'doc_status' as doc_status,
                       g.ims_name,
                       (select s.name from public.ims_staff s where s.id = g.by_staff) as by_name,
                       g.hidden_at, (select s.name from public.ims_staff s where s.id = g.hidden_by) as hidden_by_name,   -- qbo-hide-1 판정 1152: 누가 언제 숨겼나
                       p.kind as blocked_kind, p.state as blocked_state, coalesce(pd.doc->>'doc_number', pd.doc->>'name', p.ims_id) as blocked_name,
                       t.qbo_id as txn_qbo_id, t.total_amt as txn_total_amt, t.total_tax as txn_total_tax, t.mismatch as txn_mismatch, t.voided_at as txn_voided_at,
                       g.rk, g.k_old
                  from pg g
                  left join public.qbo_job p on p.id = g.blocked_by
                  left join lateral (select public.qbo_job_doc(p.ims_kind, p.ims_id) as doc offset 0) pd on p.id is not null
                  left join public.qbo_txn t on t.realm_id = g.realm_id and t.ims_id = g.ims_id and g.ims_kind in ('invoice', 'credit', 'payment', 'credit_alloc', 'opening_alloc', 'refund', 'cost_sheet', 'po_invoice', 'po_credit', 'po_charge', 'po_payment', 'po_discount')   -- 4-7a + po_discount   -- 2e-3-2-1 + refund · 3-2b + cost_sheet(JournalEntry)
                                           and t.ims_kind = case g.kind when 'opening_credit' then 'opening_credit' when 'opening_credit_void' then 'opening_credit' when 'opening_apply' then 'opening_alloc' when 'opening_apply_void' then 'opening_alloc'
                                                                        when 'refund_apply' then 'refund_apply' when 'refund_apply_void' then 'refund_apply' else g.ims_kind end   -- 2e-3-1 이견 3: 한 붙임에 txn 둘 — kind 로 갈라 잇는다 · 2e-3-2-1 이견 8: 환불도(refund · refund_void ↔ txn refund(Purchase) · refund_apply · _void ↔ txn refund_apply(Payment))
                ) b), '[]'::jsonb)));
end;
$function$;
do $$
begin
  execute format('comment on function public.qbo_job_list(text, text[], date, date, text, int, int) is %L', coalesce(obj_description('public.qbo_job_list(text, text[], date, date, text, int, int)'::regprocedure, 'pg_proc'), '') || ' · [qbo-list-perf-1 deferred 561: 문서 요약은 찾기가 없으면 한 쪽의 행에만 · 찾기가 있으면 거른 행 전부에 — 행마다 한 번 · 부모 요약 · 거래 짝 · 직원 이름은 한 쪽의 행에만 · 반환 꼴 · 정렬 · 거르기 무변]');
end $$;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select md5(p.prosrc) || ' ' || p.proacl::text || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || p.proconfig::text || ' ' || (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = 'qbo_job_list')::text
         || ' | ' || (select md5(d.prosrc) from pg_proc d where d.oid = 'public.qbo_job_doc(text, text)'::regprocedure)
    into v from pg_proc p where p.oid = 'public.qbo_job_list(text, text[], date, date, text, int, int)'::regprocedure;
  if v is distinct from '8342809117f91827f0bcc8c2ba57f2d8 {postgres=X/postgres,authenticated=X/postgres} s true {"search_path=public, pg_temp"} 1 | 9d6a689d2b3814991deabe6310597931' then
    raise exception 'qbo-list-perf-1 landing check failed (%) — nothing was saved', v;
  end if;
end $$;
