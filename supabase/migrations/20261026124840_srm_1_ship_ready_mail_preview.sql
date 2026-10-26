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
-- ═══ srm-1 — Ship Ready 메일: doc_file_id 검사를 「보내기(commit true)」 로만 · 보낼 때 그 PDF 가 이 오더의 것인지 본다 (2026-10-26 · 판정 744 · 745) ═══
--   결함(2026-10-26 Caleb 화면 · so.html Ship & invoice → Email Ship Ready): doc-3a 의 doc_mail_send 가 commit 값과 상관없이 ship_ready 에 doc_file_id 를 요구해
--     화면의 미리 보기(ims-doc.js:186 · p_commit false · 번호 없이)가 늘 거절 → Send 단추가 꺼진 채 「A Ship Ready mail needs the PDF made first」 — Ship Ready 메일이 매번 막혔다
--     (테스트 DB 실측: mail_outbox kind doc_ship_ready 0 · doc_file kind ship_ready 0 — doc-3a 이후 한 통도 안 나갔다)
--   ① doc_mail_send 재발행 — 원본 20261019184432_doc_3a_mail_db.sql 746 ~ 782 행 바이트 그대로(DB prosrc md5 d5c17ce5c763bf7da620404a26cad3d2) + 바뀐 줄 셋:
--      · 746 머리 create → create or replace(시그니처 그대로 · comment · grant 보존)
--      · 761 검사에 p_commit and — 미리 보기(commit false)는 번호 없이 통과 · 보내기는 여전히 doc_data(so_finalize 미리 보기)보다 먼저 거절(싼 문부터) · 거절 문장 그대로(화면 · 정본에 같은 글) — 판정 744
--      · 761 뒤 한 검사 더 — 보낼 때 넘겨받은 PDF 가 이 오더의 것인가(doc_file.ref->'orders' = p_ref->'orders' · EF _shared/doc.ts 가 ref 를 {창의 ref, group, so_ids} 로 남긴다) — 판정 745
--        새 거절 문장 'That Ship Ready PDF is for a different order — make the PDF for this order and send again — nothing was saved' · 없는 파일 · 다른 kind 는 doc_mail_enqueue 의 문장 그대로
--      · 780 comment 끝에 srm-1 한 토막
--   화면(ims-doc.js · so.html)은 그대로 — 미리 보기가 읽는 칸(from · from_name · reply_to · redirect_to · to · subject · body)은 바뀌지 않는다 · 기각 B(창을 열 때 PDF 를 먼저 만든다 — Cancel 해도 doc_file 이 남는다)
--   새 표 · 칸 · 시퀀스 0 · 무접촉: doc_mail_enqueue · doc_mail_attach · doc_mail_auto_invoice · 메일 기계(mail_claim · mail_mark) · 검증 supabase/tests/srm_1_check.sql

do $$
declare v_md5 text;
begin
  select md5(prosrc) into v_md5 from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace;
  if v_md5 is null then raise exception using errcode = 'IM511', message = 'STOP - doc_mail_send (doc-3a) is missing - nothing was changed'; end if;
  if v_md5 = '98f93aaa243f111befdad7eeb9a0eb1e' then raise exception using errcode = 'IM511', message = 'STOP - srm-1 is already applied (doc_mail_send body is the srm-1 body) - nothing was changed'; end if;
  if v_md5 <> 'd5c17ce5c763bf7da620404a26cad3d2' then
    raise exception using errcode = 'IM511', message = format('STOP - doc_mail_send body md5 %s is not the doc-3a body (%s) this file re-issues - nothing was changed', left(v_md5, 8), left('d5c17ce5c763bf7da620404a26cad3d2', 8));
  end if;
end $$;

-- ═══ ① doc_mail_send 재발행 — 판정 744 · 745 ═══
create or replace function public.doc_mail_send(p_kind text, p_ref jsonb, p_to text default null, p_subject text default null, p_body text default null, p_commit boolean default false, p_doc_file_id uuid default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_cust uuid;  v_rcpt jsonb;  v_to text;  v_doc jsonb;  v_subject text;  v_body text;
  v_test boolean := coalesce((select c.value = 'test' from public.inv_config c where c.key = 'db_role'), false);
  v_redirect text := nullif((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), '');
begin
  perform public.ims_require_write('sales', 'sent');                                              -- ⭐ 첫 줄(문서를 보는 문은 doc_data 가 또 묻는다)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready') then raise exception 'Only final_invoice, credit_note, sales_order or ship_ready can be mailed (internal_receipt is not sent to customers) — nothing was saved'; end if;
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then raise exception 'p_ref must be a JSON object — nothing was saved'; end if;
  v_cust := public.doc_mail_customer(p_kind, p_ref);
  if v_cust is null then raise exception 'Document not found — nothing was saved'; end if;
  if p_commit and p_kind = 'ship_ready' and p_doc_file_id is null then raise exception 'A Ship Ready mail needs the PDF made first (doc_file_id) — nothing was saved'; end if;   -- 판정 744(srm-1): 보낼 때(commit true)만 — 미리 보기는 번호 없이 통과 · doc_data(so_finalize 미리 보기)보다 먼저 — 싼 문부터
  if p_commit and p_kind = 'ship_ready' and exists (select 1 from public.doc_file f where f.id = p_doc_file_id and f.kind = 'ship_ready' and f.ref->'orders' is distinct from p_ref->'orders') then
    raise exception 'That Ship Ready PDF is for a different order — make the PDF for this order and send again — nothing was saved';   -- 판정 745(srm-1): 넘겨받은 PDF 가 이 오더의 것인가 — EF 는 doc_file.ref 를 {창의 ref(orders …), group, so_ids} 로 남기므로 orders 끼리 비교(없는 파일 · 다른 kind 는 doc_mail_enqueue 가 거절)
  end if;
  v_doc := public.doc_data(p_kind, p_ref)->'docs'->0;                                             -- 문 · 값 — 자리표 채우기 재료(ship_ready 는 so_finalize 미리 보기 · sales)
  v_rcpt := public.doc_mail_recipient(v_cust);
  v_to := lower(btrim(coalesce(nullif(p_to, ''), v_rcpt->>'to')));
  if v_to is null then raise exception 'This customer has no email address — add a contact with an email, or type one — nothing was saved'; end if;
  if not public.ims_mail_address_ok(v_to) then raise exception 'Not one email address: % — nothing was saved', v_to; end if;
  v_subject := btrim(public.doc_mail_fill(coalesce(p_subject, (select d.value from public.doc_setting d where d.kind = p_kind and d.key = 'mail_subject')), v_doc));
  v_body := public.doc_mail_fill(coalesce(p_body, (select d.value from public.doc_setting d where d.kind = p_kind and d.key = 'mail_body')), v_doc);
  if v_subject = '' then raise exception 'The mail subject is empty — set it in Settings → Documents or type one — nothing was saved'; end if;
  if v_subject ~ '[\r\n]' or length(v_subject) > 300 then raise exception 'The subject must be one line of at most 300 characters — nothing was saved'; end if;
  if length(coalesce(v_body, '')) > 20000 then raise exception 'The mail body must be at most 20000 characters — nothing was saved'; end if;
  if not p_commit then
    return jsonb_build_object('committed', false, 'kind', p_kind, 'customer_id', v_cust, 'to', v_to, 'to_default', v_rcpt->>'to', 'to_how', v_rcpt->>'how', 'subject', v_subject, 'body', v_body,
                              'from', (select c.value from public.inv_config c where c.key = 'mail_doc_from'), 'from_name', (select c.value from public.inv_config c where c.key = 'mail_doc_from_name'), 'reply_to', (select c.value from public.inv_config c where c.key = 'mail_doc_reply_to'),
                              'redirect_to', case when v_test then v_redirect end, 'would_status', case when p_doc_file_id is null then 'waiting_pdf' else 'queued' end, 'doc_file_id', p_doc_file_id);
  end if;
  return jsonb_build_object('committed', true) || public.doc_mail_enqueue(p_kind, p_ref, v_to, v_subject, v_body, v_cust, v_staff, p_doc_file_id, false);
end;
$$;
comment on function public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid) is 'doc-3a — 직원이 누르는 문서 메일(final_invoice · credit_note · sales_order · ship_ready · internal_receipt 는 안 보낸다): 문 sales 쓰기(+ doc_data 의 문) · 받는 이 = 판정 498 고르기(p_to 로 바꿀 수 있다 · 한 통에 한 주소) · 제목 · 본문 = doc_setting 글(p_subject · p_body 로 바꿀 수 있다)의 {{a.b}} 를 doc_data 의 값으로 채움 · p_commit false = 미리 보기(시험 DB 면 redirect_to 도) · true = mail_outbox 한 줄 — PDF 없으면 waiting_pdf(3b 일꾼이 doc EF 로 만들어 붙이고 queued 로) · ship_ready 는 직원이 doc EF 로 만든 PDF 의 doc_file_id 가 있어야(service 길은 ship_ready 를 못 만든다) → queued · 보내는 주소 = mail_doc_*(판정 530) · ⭐ srm-1(판정 744 · 745): 미리 보기(commit false)는 doc_file_id 없이 통과 · 보내기(commit true)만 번호 필수 + 그 PDF 의 ref.orders 가 p_ref.orders 와 같아야 한다';
revoke all on function public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid) from public, anon;
grant execute on function public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid) to authenticated;

-- ═══ 착지 ═══
do $$
declare v_md5 text;  v_oid oid;
begin
  select oid, md5(prosrc) into v_oid, v_md5 from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace;
  if v_md5 <> '98f93aaa243f111befdad7eeb9a0eb1e' then raise exception 'srm-1 landing: doc_mail_send md5 % <> 98f93aaa243f111befdad7eeb9a0eb1e', v_md5; end if;
  if (select count(*) from pg_proc where proname = 'doc_mail_send' and pronamespace = 'public'::regnamespace) <> 1 then raise exception 'srm-1 landing: doc_mail_send is not exactly one function'; end if;
  if not (select prosecdef from pg_proc where oid = v_oid) then raise exception 'srm-1 landing: doc_mail_send is not definer'; end if;
  if not has_function_privilege('authenticated', v_oid, 'execute') then raise exception 'srm-1 landing: authenticated lost execute'; end if;
  if has_function_privilege('anon', v_oid, 'execute') then raise exception 'srm-1 landing: anon can execute'; end if;
  if (select prosrc from pg_proc where oid = v_oid) !~ 'p_commit and p_kind = ''ship_ready'' and p_doc_file_id is null' then raise exception 'srm-1 landing: the commit-only check line is missing'; end if;
  if (select prosrc from pg_proc where oid = v_oid) !~ 'is for a different order' then raise exception 'srm-1 landing: the same-order check is missing'; end if;
  if (select obj_description(v_oid, 'pg_proc')) !~ '745' then raise exception 'srm-1 landing: comment lost the srm-1 note'; end if;
  raise notice 'srm-1 landed: doc_mail_send md5 98f93aaa243f111befdad7eeb9a0eb1e · definer · authenticated execute · anon none · preview passes without doc_file_id · send checks same-order PDF (744 · 745)';
end $$;
