-- supabase/migrations/20261107044600_mail_inc_1c_fill_recipients.sql
-- mail-inc-1c — 문서 메일 받는 이 여럿: 메일을 만들 때 to_more 를 채운다 (2026-11-07 · 판정 1000 · 1018 ~ 1029 · 529 · so-module §99-c 3 · 지시서 mail-inc-1c §0 이견 1 ~ 10 의 답)
-- [테스트 · Asung-IMS = IMS 메인] 적용: psql -1 -f <이 파일> + supabase migration repair --status applied 20261107044600 (db push 금지) · 시험 · 확인 = supabase/tests/mail_inc_1c_check.sql
--
-- 무엇(이견 1 · 2): mail_outbox 에 문서 메일 줄을 넣는 곳은 doc_mail_enqueue 하나 · 부르는 곳 둘(직원 Send doc_mail_send · 자동 최종 인보이스 doc_mail_auto_invoice) — 셋을 재발행한다
--   ① doc_mail_enqueue — 옛 9 인자 drop → 11 인자(+ p_to_more text[] · p_recipients jsonb) · to_more 칸에 싣고 payload 에 recipients(이견 5 · 1027 skipped 보임) · revoke 그대로(postgres · service_role 만)
--   ② doc_mail_send — 시그니처 그대로 · inv_config 'doc_mail_multi' = 'on' 일 때만 새 길(이견 6):
--        받는 이 = doc_mail_recipients(p_kind, p_ref)(1018 · 1021 · 1024 · 1027) · p_to 는 쉼표 · 세미콜론 목록(이견 3 · 직원이 칸에서 지우거나 더한 그대로 · 1022 「그 한 통만」) — lower(btrim) → ims_mail_address_ok → 겹침은 처음 것만 → 상한 10
--        미리 보기(commit false) to = 전체 목록 ", "(EF render 의 to 와 같은 꼴) + to_first · to_more · recipients{source, how, how_498, skipped, stores, list}(이견 4) · 옛 칸(to_default · to_how) 유지
--        보내기(commit true) = 첫 주소 to_address · 나머지 to_more(CHECK ims_mail_to_more_ok) · 키가 없거나 'on' 아니면 옛 길 그대로(498 하나 · 미리 보기도 옛 꼴 · 쉼표는 거부)
--   ③ doc_mail_auto_invoice — 같은 키 · 같은 함수 · 받는 이 셈을 exception 블록 안으로(메일 때문에 발행이 서지 않는다 · 529) · 건너뜀 no_email · reissue · error 그대로(doc_mail_skip)
--   ④ 키 doc_mail_multi 는 이 파일이 넣지 않는다(= 꺼진 채 적용) — ims_mail_config_keys 밖 · 화면 없음 · psql 로만(보고서의 켜기 · 끄기 명령) · 1d 때 지운다
-- 무변(1025 · 1026): doc_mail_recipient(498 · QBO BillEmail) · doc_mail_recipients · doc_mail_customer · 백오더 둘 · mail_claim · mail_mark · mail_outbox 칸 · CHECK
-- ⚠️ 1b EF(asung-wms 34fe1f9 · 배포 완료) 뒤에만 켠다 — 그 전에 켜면 둘째 주소부터 조용히 빠진다(deferred 460)
-- ⚠️ redirect(1029 · 1b 이견 ②)는 창구가 거르지 않는다 — 보내는 순간의 설정이라 EF 가 failed 로 둔다(이견 7)

-- ═══ 0) 가드 — 원본이 짐작과 같은가 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_enqueue') <> 1
     or not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_enqueue' and md5(prosrc) = '4cc7822b22313a429f77b6c8cc09a67d'
                      and pg_get_function_identity_arguments(oid) = 'p_kind text, p_ref jsonb, p_to text, p_subject text, p_body text, p_customer_id uuid, p_staff uuid, p_doc_file_id uuid, p_auto boolean') then v_bad := v_bad || ' enqueue-origin'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') <> 1
     or not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send' and md5(prosrc) = '29cef8a7fab52de07e3e510297ad2d98') then v_bad := v_bad || ' send-origin'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice') <> 1
     or not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice' and md5(prosrc) = '1f86dfe94b9453b172f4b2edc00d8f58') then v_bad := v_bad || ' auto-origin'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox' and column_name = 'to_more') then v_bad := v_bad || ' to_more-missing'; end if;
  if not exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_recipients') then v_bad := v_bad || ' recipients-missing(1a)'; end if;
  if exists (select 1 from public.inv_config where key = 'doc_mail_multi') then v_bad := v_bad || ' key-already-present'; end if;
  if v_bad <> '' then raise exception 'mail-inc-1c guard:%', v_bad; end if;
end $$;

-- ═══ 1) doc_mail_enqueue — 옛 9 인자 drop → 11 인자(이견 2 · create or replace 는 시그니처가 바뀌면 두 벌이 된다) ═══
-- 원본 20261019184432_doc_3a_mail_db.sql(md5 4cc7822b) 바이트 + 바뀐 줄: 머리(인자 둘) · insert 칸 to_more · payload || recipients · 반환 to_more
drop function public.doc_mail_enqueue(text, jsonb, text, text, text, uuid, uuid, uuid, boolean);
create function public.doc_mail_enqueue(p_kind text, p_ref jsonb, p_to text, p_subject text, p_body text, p_customer_id uuid, p_staff uuid, p_doc_file_id uuid, p_auto boolean, p_to_more text[], p_recipients jsonb) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_f public.doc_file%rowtype; v_att jsonb := '[]'::jsonb; v_o public.mail_outbox%rowtype;
        v_from text := (select c.value from public.inv_config c where c.key = 'mail_doc_from');
        v_name text := (select c.value from public.inv_config c where c.key = 'mail_doc_from_name');
        v_reply text := nullif((select c.value from public.inv_config c where c.key = 'mail_doc_reply_to'), '');
begin
  if v_from is null or not public.ims_mail_address_ok(v_from) then raise exception 'mail_doc_from (the document sender address) is not set — Settings → Backorder emails'; end if;
  if p_doc_file_id is not null then
    select * into v_f from public.doc_file f where f.id = p_doc_file_id;
    if v_f.id is null then raise exception 'Stored PDF not found — nothing was saved'; end if;
    if v_f.kind <> p_kind then raise exception 'That PDF is a % document, not % — nothing was saved', v_f.kind, p_kind; end if;
    v_att := jsonb_build_array(jsonb_build_object('doc_file_id', v_f.id, 'path', v_f.path, 'filename', regexp_replace(v_f.path, '^.*/', ''), 'bytes', v_f.bytes, 'sha256', v_f.sha256));
  end if;
  insert into public.mail_outbox (kind, category, status, from_address, from_name, reply_to, to_address, to_more, subject, body_text, payload, customer_id, attachments, dedupe_key, created_by)
  values ('doc_' || p_kind, 'transactional', case when p_doc_file_id is null then 'waiting_pdf' else 'queued' end, v_from, nullif(v_name, ''), v_reply, p_to, coalesce(p_to_more, '{}'), p_subject, p_body,
          jsonb_build_object('doc_kind', p_kind, 'ref', p_ref, 'customer_id', p_customer_id, 'auto', p_auto, 'requested_by', p_staff, 'doc_file_id', p_doc_file_id)
            || case when p_recipients is null then '{}'::jsonb else jsonb_build_object('recipients', p_recipients) end,                       -- mail-inc-1c 이견 5: skipped · how 가 보이는 자리(1027 · 1d doc_mail_list 가 읽는다)
          p_customer_id, v_att, 'doc:' || p_kind || ':' || md5(p_ref::text) || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'), p_staff)
  returning * into v_o;
  return jsonb_build_object('outbox_id', v_o.id, 'status', v_o.status, 'to', v_o.to_address, 'to_more', to_jsonb(v_o.to_more), 'subject', v_o.subject, 'attachments', v_o.attachments, 'created_at', v_o.created_at);
end;
$$;
revoke all on function public.doc_mail_enqueue(text, jsonb, text, text, text, uuid, uuid, uuid, boolean, text[], jsonb) from public, anon, authenticated;
comment on function public.doc_mail_enqueue(text, jsonb, text, text, text, uuid, uuid, uuid, boolean, text[], jsonb) is 'doc-3a 속 — mail_outbox 에 문서 메일 한 줄(⑤ doc_mail_send · ⑥ doc_mail_auto_invoice 가 부른다 · 직접 못 부름): 받는 이 · 제목 · 본문 · 보내는 주소 mail_doc_* · 첨부(있으면 queued · 없으면 waiting_pdf). mail-inc-1c(판정 1028 · 1027): p_to_more = 둘째 주소부터(to_more 칸 · CHECK ims_mail_to_more_ok · null 은 {}) · p_recipients = payload.recipients {source, how, how_498, skipped, stores, list}(null 이면 안 싣는다 · 옛 길). 반환 {outbox_id, status, to, to_more, subject, attachments, created_at}';

-- ═══ 2) doc_mail_send 재발행 — 원본 20261102013000_mail_live_1.sql(md5 29cef8a7) 바이트 + mail-inc-1c 줄(v_multi 갈래 · 미리 보기 칸 · enqueue 인자 둘) ═══
CREATE OR REPLACE FUNCTION public.doc_mail_send(p_kind text, p_ref jsonb, p_to text DEFAULT NULL::text, p_subject text DEFAULT NULL::text, p_body text DEFAULT NULL::text, p_commit boolean DEFAULT false, p_doc_file_id uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff uuid;  v_cust uuid;  v_rcpt jsonb;  v_to text;  v_doc jsonb;  v_subject text;  v_body text;
  v_redirect text := nullif((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), '');
  v_multi boolean := coalesce((select c.value from public.inv_config c where c.key = 'doc_mail_multi'), '') = 'on';   -- mail-inc-1c 이견 6: 키가 없거나 on 이 아니면 옛 길(498 하나)
  v_rec jsonb;  v_all text[] := '{}';  v_more text[] := '{}';  v_a text;  v_src text;
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
  if v_multi then                                                                                   -- mail-inc-1c(1018 · 1021 · 1022 · 1027): 받는 이 여럿
    v_rec := public.doc_mail_recipients(p_kind, p_ref);
    if nullif(btrim(coalesce(p_to, '')), '') is not null then                                       -- 직원이 칸에 쓴 그대로(이견 3) — 쉼표 · 세미콜론 목록 · lower(btrim) · 겹침은 처음 것만 · 상한 10
      foreach v_a in array regexp_split_to_array(p_to, '[,;]') loop
        v_a := lower(btrim(v_a));
        if v_a = '' then continue; end if;
        if not public.ims_mail_address_ok(v_a) then raise exception 'Not one email address: % — nothing was saved', v_a; end if;
        if v_a <> all (v_all) then v_all := v_all || v_a; end if;
      end loop;
      if cardinality(v_all) > 10 then raise exception 'At most 10 recipients in one email (you typed %) — nothing was saved', cardinality(v_all); end if;
      v_src := case when v_all = array(select x->>'email' from jsonb_array_elements(v_rec->'list') x) then v_rec->>'how' else 'typed' end;
    else
      v_all := array(select x->>'email' from jsonb_array_elements(v_rec->'list') x);
      v_src := v_rec->>'how';
    end if;
    if cardinality(v_all) = 0 then raise exception 'This customer has no email address — add a contact with an email, or type one — nothing was saved'; end if;
    v_to := v_all[1];  v_more := v_all[2:];
    v_rec := jsonb_build_object('source', v_src, 'how', v_rec->>'how', 'how_498', v_rec->'how_498', 'skipped', v_rec->'skipped', 'stores', v_rec->'stores', 'list', v_rec->'list');
  else
    v_to := lower(btrim(coalesce(nullif(p_to, ''), v_rcpt->>'to')));
    if v_to is null then raise exception 'This customer has no email address — add a contact with an email, or type one — nothing was saved'; end if;
    if not public.ims_mail_address_ok(v_to) then raise exception 'Not one email address: % — nothing was saved', v_to; end if;
  end if;
  v_subject := btrim(public.doc_mail_fill(coalesce(p_subject, (select d.value from public.doc_setting d where d.kind = p_kind and d.key = 'mail_subject')), v_doc));
  v_body := public.doc_mail_fill(coalesce(p_body, (select d.value from public.doc_setting d where d.kind = p_kind and d.key = 'mail_body')), v_doc);
  if v_subject = '' then raise exception 'The mail subject is empty — set it in Settings → Documents or type one — nothing was saved'; end if;
  if v_subject ~ '[\r\n]' or length(v_subject) > 300 then raise exception 'The subject must be one line of at most 300 characters — nothing was saved'; end if;
  if length(coalesce(v_body, '')) > 20000 then raise exception 'The mail body must be at most 20000 characters — nothing was saved'; end if;
  if not p_commit then                                                                            -- mail-live-1 판정 947: redirect_to 는 EF addressFor 와 같은 뜻 — 돌려 보낼 주소가 있으면 시험이든 운영([REDIRECT →])이든 그 주소로 간다 · 없으면 null(손님에게)
    return jsonb_build_object('committed', false, 'kind', p_kind, 'customer_id', v_cust, 'to', case when v_multi then array_to_string(v_all, ', ') else v_to end, 'to_default', v_rcpt->>'to', 'to_how', v_rcpt->>'how', 'subject', v_subject, 'body', v_body,
                              'from', (select c.value from public.inv_config c where c.key = 'mail_doc_from'), 'from_name', (select c.value from public.inv_config c where c.key = 'mail_doc_from_name'), 'reply_to', (select c.value from public.inv_config c where c.key = 'mail_doc_reply_to'),
                              'redirect_to', v_redirect, 'would_status', case when p_doc_file_id is null then 'waiting_pdf' else 'queued' end, 'doc_file_id', p_doc_file_id)
           || case when v_multi then jsonb_build_object('to_first', v_to, 'to_more', to_jsonb(v_more), 'recipients', v_rec) else '{}'::jsonb end;   -- mail-inc-1c 이견 4: to = 전체 ", "(EF render 와 같은 꼴) · 1d 체크박스 재료 = recipients
  end if;
  return jsonb_build_object('committed', true) || public.doc_mail_enqueue(p_kind, p_ref, v_to, v_subject, v_body, v_cust, v_staff, p_doc_file_id, false, v_more, v_rec);
end;
$function$;
comment on function public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid) is 'doc-3a — 직원이 누르는 문서 메일(final_invoice · credit_note · sales_order · ship_ready · internal_receipt 는 안 보낸다): 문 sales 쓰기(+ doc_data 의 문) · 제목 · 본문 = doc_setting 글(p_subject · p_body 로 바꿀 수 있다)의 {{a.b}} 를 doc_data 의 값으로 채움 · p_commit false = 미리 보기(redirect_to 도) · true = mail_outbox 한 줄 — PDF 없으면 waiting_pdf(3b 일꾼이 doc EF 로 만들어 붙이고 queued 로) · ship_ready 는 직원이 doc EF 로 만든 PDF 의 doc_file_id 가 있어야(service 길은 ship_ready 를 못 만든다) → queued · 보내는 주소 = mail_doc_*(판정 530). mail-inc-1c(판정 1018 ~ 1029): inv_config doc_mail_multi = on 이면 받는 이 = doc_mail_recipients(청구처 ∪ 매장의 켜진 연락처 · 비면 498) · p_to 는 쉼표 · 세미콜론 목록(칸에 쓴 그대로 · 겹침 제거 · 상한 10) · 미리 보기 to = 전체 ", " + to_first · to_more · recipients · 보내기 = 첫 주소 to_address + 나머지 to_more · 키가 없거나 on 아니면 옛 길(498 하나 · p_to 한 주소 · 옛 반환 꼴)';

-- ═══ 3) doc_mail_auto_invoice 재발행 — 원본 20261027014202_ar_2_opening_carry_forward.sql(md5 1f86dfe9) 바이트 + mail-inc-1c 줄(v_multi 갈래 · 받는 이 셈을 exception 블록 안으로 · enqueue 인자 둘) ═══
CREATE OR REPLACE FUNCTION public.doc_mail_auto_invoice()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v_on boolean; v_rcpt jsonb; v_doc jsonb; v_ref jsonb := jsonb_build_object('invoice_id', new.id); v_subject text; v_body text; v_staff uuid;
        v_multi boolean := coalesce((select c.value from public.inv_config c where c.key = 'doc_mail_multi'), '') = 'on';   -- mail-inc-1c 이견 6: 키가 없거나 on 이 아니면 옛 길(498 하나)
        v_rec jsonb; v_all text[] := '{}';
begin
  if new.kind = 'opening' then return null; end if;                                                                                      -- ar-2 판정 785: 이월 인보이스(이전 시스템)는 메일 없음
  select c.final_invoice_mail into v_on from public.customer c where c.id = new.bill_to_customer_id;
  if not coalesce(v_on, false) then return null; end if;
  if (select i.status from public.so_invoice i where i.id = new.id) is distinct from 'issued' then return null; end if;             -- 같은 트랜잭션에서 취소됐으면 아무것도
  if exists (select 1 from public.so_invoice_order o1 join public.so_invoice_order o2 on o2.so_id = o1.so_id and o2.invoice_id <> o1.invoice_id where o1.invoice_id = new.id) then
    insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'reissue', 'an earlier invoice exists for the same order — not mailed automatically');
    return null;
  end if;
  begin
    if v_multi then                                                                                                                      -- mail-inc-1c(1018 · 1021 · 1023): 받는 이 여럿 — 셈도 이 블록 안(메일 때문에 발행이 서지 않는다 · 529)
      v_rec := public.doc_mail_recipients('final_invoice', v_ref);
      v_all := array(select x->>'email' from jsonb_array_elements(v_rec->'list') x);
      v_rec := jsonb_build_object('source', v_rec->>'how', 'how', v_rec->>'how', 'how_498', v_rec->'how_498', 'skipped', v_rec->'skipped', 'stores', v_rec->'stores', 'list', v_rec->'list');
    else
      v_rcpt := public.doc_mail_recipient(new.bill_to_customer_id);
      if v_rcpt->>'to' is not null then v_all := array[v_rcpt->>'to']; end if;
    end if;
    if cardinality(v_all) = 0 then
      insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'no_email', 'the customer has no contact with an email address');
      return null;
    end if;
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    v_doc := public.doc_data('final_invoice', v_ref)->'docs'->0;
    v_subject := btrim(public.doc_mail_fill((select d.value from public.doc_setting d where d.kind = 'final_invoice' and d.key = 'mail_subject'), v_doc));
    v_body := public.doc_mail_fill((select d.value from public.doc_setting d where d.kind = 'final_invoice' and d.key = 'mail_body'), v_doc);
    if v_subject = '' then raise exception 'mail_subject of final_invoice is empty (Settings → Documents)'; end if;
    perform public.doc_mail_enqueue('final_invoice', v_ref, v_all[1], v_subject, v_body, new.bill_to_customer_id, v_staff, null, true, v_all[2:], v_rec);
  exception when others then                                                                                                             -- 발행을 막지 않는다 — 남기고 지나간다
    insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'error', left(sqlerrm, 500));
  end;
  return null;
end;
$function$;
comment on function public.doc_mail_auto_invoice() is 'doc-3a 판정 529 — 인보이스가 issued 로 생기고 청구처의 final_invoice_mail 이 켜져 있으면 문서 메일 한 줄(waiting_pdf · 3b 가 PDF 를 붙여 보낸다) · 지연 제약 트리거라 발행 트랜잭션 끝에 돈다(so_invoice_issue 무접촉) · 건너뜀: 같은 오더의 앞 인보이스가 있다(재발행 · reissue) · 받는 주소 없음(no_email) · 그 밖 오류(error) → doc_mail_skip · 발행은 막지 않는다 · POS · Shopify 주문도 칸대로. mail-inc-1c(판정 1018 · 1021 · 1023): inv_config doc_mail_multi = on 이면 받는 이 = doc_mail_recipients(청구처 ∪ 매장 · 비면 498 · 그것도 없으면 no_email) · 첫 주소 to_address + 나머지 to_more · payload.recipients · 셈은 exception 블록 안 · 키가 없거나 on 아니면 옛 길(498 하나)';

-- ═══ 4) 착지 — 한 벌씩 · acl · 꼴 · 트리거 · 키 없음(꺼진 채) ═══
do $$
declare v_bad text := ''; v_acl text; v_src text;
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_enqueue') <> 1 then v_bad := v_bad || ' enqueue-count'; end if;
  if (select pg_get_function_identity_arguments(oid) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_enqueue' limit 1)
     <> 'p_kind text, p_ref jsonb, p_to text, p_subject text, p_body text, p_customer_id uuid, p_staff uuid, p_doc_file_id uuid, p_auto boolean, p_to_more text[], p_recipients jsonb' then v_bad := v_bad || ' enqueue-args'; end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_enqueue' limit 1;
  if v_acl is distinct from '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' enqueue-acl(' || coalesce(v_acl, 'null') || ')'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') <> 1 then v_bad := v_bad || ' send-count'; end if;
  if has_function_privilege('anon', 'public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)', 'execute') then v_bad := v_bad || ' send-acl'; end if;
  if (select provolatile::text || prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send') <> 'vtrue' then v_bad := v_bad || ' send-shape'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice') <> 1 then v_bad := v_bad || ' auto-count'; end if;
  if (select provolatile::text || prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice') <> 'vtrue' then v_bad := v_bad || ' auto-shape'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_invoice'::regclass and tgname = 'so_invoice_doc_mail_auto' and tgdeferrable and tginitdeferred and tgfoid = 'public.doc_mail_auto_invoice()'::regprocedure) <> 1 then v_bad := v_bad || ' trigger'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send';
  if (select count(*) from regexp_matches(v_src, 'doc_mail_multi', 'g')) <> 1 or (select count(*) from regexp_matches(v_src, 'doc_mail_recipients\(', 'g')) <> 1 or (select count(*) from regexp_matches(v_src, 'doc_mail_enqueue\(', 'g')) <> 1 then v_bad := v_bad || ' send-src'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_auto_invoice';
  if (select count(*) from regexp_matches(v_src, 'doc_mail_multi', 'g')) <> 1 or (select count(*) from regexp_matches(v_src, 'doc_mail_recipients\(', 'g')) <> 1 or (select count(*) from regexp_matches(v_src, 'doc_mail_enqueue\(', 'g')) <> 1 then v_bad := v_bad || ' auto-src'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_enqueue';
  if (select count(*) from regexp_matches(v_src, 'to_more', 'g')) <> 4 or (select count(*) from regexp_matches(v_src, '''recipients''', 'g')) <> 1 then v_bad := v_bad || ' enqueue-src'; end if;
  if exists (select 1 from public.inv_config where key = 'doc_mail_multi') then v_bad := v_bad || ' key-present'; end if;
  if v_bad <> '' then raise exception 'mail-inc-1c landing:%', v_bad; end if;
  raise notice 'mail-inc-1c landed — doc_mail_enqueue 11 args (one) · doc_mail_send · doc_mail_auto_invoice reissued · doc_mail_multi absent (off until psql turns it on)';
end $$;
