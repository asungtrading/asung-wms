-- 20261103174500_mail_inc_1a_recipients.sql — mail-inc-1a: 문서 메일 받는 이 여럿 · DB 바탕(채우기는 아직 안 함) (2026-11-03 · 판정 1000 · 1018 ~ 1029)
-- [운영 · Asung-IMS] 적용은 Caleb · psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f + supabase migration repair --status applied 20261103174500 · db push 금지
--
-- 왜: 문서 메일(final_invoice · credit_note · sales_order · ship_ready · 자동 최종 인보이스)이 손님 연락처 하나(498)에게만 간다. 판정 1000(가): include in email 이 켜진 연락처 모두에게 ·
--     1018(가): 청구처의 켜진 연락처 ∪ 그 문서 매장(자식 손님)의 켜진 연락처(본사 5 아래 매장 26 이 실제로 바뀌는 곳) · 1019 모두 To · 1020 켜진 것만 · 1021 합집합이 비면 청구처 498 만 ·
--     1024 매장 둘 이상 = 합집합 · 1026(나) 새 함수(옛 함수 · QBO 셋 · 백오더 둘 무변) · 1027 lower(btrim) → ims_mail_address_ok → 처음 것만 · 상한 10 · skipped 로 남긴다 · 1028(가) to_more text[] · 1029 redirect 한 통.
-- ⚠️ 차수 순서(보고서 §3): 1a(이 파일) 적용 → 1b EF 배포 → 1c(채우기) 적용 → 1d 화면. 이 차수에서는 아무도 to_more 를 채우지 않는다 — doc_mail_send · doc_mail_enqueue · doc_mail_auto_invoice · doc_mail_list 무접촉(1c 몫).
-- 이견 답(2026-11-03 · mail-inc-1a §0 · 1 ~ 15 모두 받음):
--   3 CHECK 안에서는 서브쿼리 · unnest 를 못 쓴다 → immutable 도우미 ims_mail_to_more_ok(p_to, p_more) 하나 · 원소끼리 겹침도 막는다
--   5 셀프 청구(매장 = 청구처)면 매장 집합에서 청구처를 뺀다 · role 은 bill_to 하나
--   7 skipped = {email, name, customer_id, role, reason ∈ blank | bad_shape | duplicate | cap}
--   8 fallback_498 일 때 how_498(default | other) 를 함께 · name = 그 주소의 첫 활성 연락처
--   9 청구처 켜짐 0 · 매장 켜짐 있음 → how flags · 매장 주소만(청구처 498 은 안 들어간다 · 1020 · 1018 가)
--   10 mail_claim 의 to_more 는 JSON 배열로 간다(기존 행 '{}' → []) — 1b EF 는 없음 · [] 둘 다 「없음」 으로
--   13 이월(opening) 인보이스는 doc_data_invoice 가 raise 로 거부(ar-2 785) · doc_mail_send 는 doc_data 를 받는 이보다 먼저 부른다 → 새 함수는 만나지 않는다(받아도 store_customer_id 로 매장을 잡을 뿐 · 해 없음)
-- 무엇: ① ims_mail_to_more_ok ② mail_outbox.to_more text[] not null default '{}' + CHECK ③ doc_mail_recipients(p_kind, p_ref) ④ mail_claim 재발행(DB 바이트 + 'to_more' 한 줄) ⑤ 가드 · 착지
-- 무접촉: doc_mail_recipient · doc_mail_customer · doc_mail_send · doc_mail_enqueue · doc_mail_auto_invoice · doc_mail_list · qbo_invoice_body · qbo_credit_body · qbo_customer_body · mail_backorder_pick · mail_backorder_send ·
--         mail_outbox 의 옛 CHECK(to_address · original_to 쉼표 거부) · 화면 · EF(1b)
-- 검증: supabase/tests/mail_inc_1a_check.sql (begin → \i → 검증 → rollback · 메일 창구는 부르지 않는다)

-- ═══ 0) 가드 — 원본이 보고서 B · C 의 바이트인가 · 아직 안 만들어졌나 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_claim')         <> 'a1264c93917ed04cd3aaf15c74e89914' then v_bad := v_bad || ' mail_claim'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_recipient') <> '40411541bc7be327e67fd9c0e4839287' then v_bad := v_bad || ' doc_mail_recipient'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_customer')  <> '56f212dcbf7be8657f38a32aebad6a7a' then v_bad := v_bad || ' doc_mail_customer'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send')      <> '29cef8a7fab52de07e3e510297ad2d98' then v_bad := v_bad || ' doc_mail_send'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_mail_address_ok') <> 'a5029cc64fd8600c3289cc9bcd02c220' then v_bad := v_bad || ' ims_mail_address_ok'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox' and column_name = 'to_more') then v_bad := v_bad || ' to_more-exists'; end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname in ('doc_mail_recipients', 'ims_mail_to_more_ok')) then v_bad := v_bad || ' new-fn-exists'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM100', message = format('STOP - mail-inc-1a guard failed (originals differ from report B · C):%s', v_bad); end if;
end $$;

-- ═══ 1) ims_mail_to_more_ok — to_more 의 CHECK 도우미(이견 3) ═══
-- 길이 ≤ 9(첫 주소 to_address 와 합쳐 상한 10 · 1027) · 원소마다 ims_mail_address_ok · 원소끼리 겹치지 않음 · to_address 와 겹치지 않음(비교는 lower(btrim))
create function public.ims_mail_to_more_ok(p_to text, p_more text[]) returns boolean
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$
  select p_more is not null
     and coalesce(cardinality(p_more), 0) <= 9
     and not exists (select 1 from unnest(p_more) m where not public.ims_mail_address_ok(m))
     and (select count(distinct lower(btrim(m))) from unnest(p_more) m) = coalesce(cardinality(p_more), 0)
     and not exists (select 1 from unnest(p_more) m where lower(btrim(m)) = lower(btrim(p_to)));
$$;
revoke all on function public.ims_mail_to_more_ok(text, text[]) from public, anon;
grant execute on function public.ims_mail_to_more_ok(text, text[]) to authenticated, service_role;
comment on function public.ims_mail_to_more_ok(text, text[]) is 'mail-inc-1a 이견 3 — mail_outbox.to_more 의 CHECK 도우미: 길이 ≤ 9(to_address 와 합쳐 상한 10 · 판정 1027) · 원소마다 ims_mail_address_ok(쉼표 · 공백 · 빈 · null 거부) · 원소끼리 겹치지 않음 · to_address 와 겹치지 않음(lower(btrim) 로 비교) · immutable';

-- ═══ 2) mail_outbox.to_more — 받는 이 둘째부터(판정 1028 가) · 기존 행 '{}' · 옛 CHECK 무변 ═══
alter table public.mail_outbox add column to_more text[] not null default '{}';
alter table public.mail_outbox add constraint mail_outbox_to_more_ck check (public.ims_mail_to_more_ok(to_address, to_more));
comment on column public.mail_outbox.to_more is 'mail-inc-1a 판정 1028(가) — 받는 이 둘째부터(첫 주소는 to_address 그대로 · 1019 모두 To). CHECK ims_mail_to_more_ok(길이 ≤ 9 · 원소마다 주소 하나 꼴 · 서로 · to_address 와 겹치지 않음). ⚠️ 1c(doc_mail_enqueue · doc_mail_send) 전까지 아무도 채우지 않는다 — 1b EF 가 먼저 배포돼야 한다(옛 EF 는 to_address 에게만 보낸다). redirect 면 한 통 · original_to = 첫 주소 · 나머지는 여기 그대로(1029)';

-- ═══ 3) doc_mail_recipients — 받는 이 목록(판정 1026 나 · 1018 · 1020 · 1021 · 1024 · 1027) ═══
-- 청구처 = doc_mail_customer(kind, ref)(보고서 B · F 와 같은 길) · 매장 = 그 문서 오더들의 손님(인보이스 coalesce(so_invoice.store_customer_id, 오더 손님) · 크레딧 coalesce(store_customer_id, customer_id) · sales_order so.customer_id · ship_ready orders[] 모두)
-- 순서 = 청구처(기본 먼저 · created_at · id) → 매장(같은 순서 · 매장은 문서 안 순서) · 셀프 청구면 매장 집합에서 청구처를 뺀다(이견 5) · 쓸 수 있는 켜진 주소가 하나도 없으면 doc_mail_recipient(청구처)(498 한 곳 · 1021)
-- 반환 {list:[{email, name, customer_id, role bill_to|store}], skipped:[{email, name, customer_id, role, reason blank|bad_shape|duplicate|cap}], how flags|fallback_498|none, how_498 default|other|null, customer_id(청구처), stores:[uuid]}
create function public.doc_mail_recipients(p_kind text, p_ref jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_bill    uuid := public.doc_mail_customer(p_kind, p_ref);
  v_stores  uuid[] := '{}';
  v_list    jsonb := '[]';
  v_skipped jsonb := '[]';
  v_seen    text[] := '{}';
  v_norm    text;
  v_reason  text;
  v_498     jsonb;
  v_name    text;
  r         record;
begin
  if v_bill is null then
    return jsonb_build_object('list', '[]'::jsonb, 'skipped', '[]'::jsonb, 'how', 'none', 'how_498', null::text, 'customer_id', null::uuid, 'stores', '[]'::jsonb);
  end if;
  v_stores := case p_kind
    when 'final_invoice' then (select case when i.store_customer_id is not null then array[i.store_customer_id]
                                           else array(select o.customer_id from public.so_invoice_order o where o.invoice_id = i.id and o.cancelled_at is null and o.customer_id is not null order by o.so_number, o.id) end
                               from public.so_invoice i where i.id = nullif(p_ref->>'invoice_id', '')::uuid)
    when 'credit_note'   then (select array[coalesce(c.store_customer_id, c.customer_id)] from public.so_credit c where c.id = nullif(p_ref->>'credit_id', '')::uuid)
    when 'sales_order'   then (select array[s.customer_id] from public.so s where s.id = nullif(p_ref->>'so_id', '')::uuid)
    when 'ship_ready'    then array(select s.customer_id from jsonb_array_elements(coalesce(p_ref->'orders', '[]'::jsonb)) with ordinality o(v, n)
                                    join public.so s on s.id = nullif(o.v->>'so_id', '')::uuid order by o.n)
    else '{}'::uuid[] end;
  v_stores := coalesce(array(select u.s from unnest(v_stores) with ordinality u(s, n) where u.s is not null and u.s <> v_bill group by u.s order by min(u.n)), '{}');   -- 이견 5 · 1024(처음 나온 순서)

  for r in
    select x.role, cc.customer_id, cc.name, cc.email
    from (select v_bill as cid, 'bill_to'::text as role, 0::bigint as ord
          union all select u.s, 'store', u.n from unnest(v_stores) with ordinality u(s, n)) x
    join public.customer_contact cc on cc.customer_id = x.cid and cc.is_active and cc.include_in_email
    order by x.ord, cc.is_default desc, cc.created_at, cc.id
  loop
    v_norm := lower(btrim(r.email));
    v_reason := case when nullif(v_norm, '') is null then 'blank'
                     when not public.ims_mail_address_ok(v_norm) then 'bad_shape'
                     when v_norm = any (v_seen) then 'duplicate'
                     when jsonb_array_length(v_list) >= 10 then 'cap' end;                                                          -- 1027 상한 10(to_address 1 + to_more 9)
    if v_reason is null then
      v_list := v_list || jsonb_build_object('email', v_norm, 'name', r.name, 'customer_id', r.customer_id, 'role', r.role);
      v_seen := v_seen || v_norm;
    else
      v_skipped := v_skipped || jsonb_build_object('email', btrim(r.email), 'name', r.name, 'customer_id', r.customer_id, 'role', r.role, 'reason', v_reason);   -- 조용히 버리지 않는다(1027)
    end if;
  end loop;

  if jsonb_array_length(v_list) = 0 then                                                                                              -- 1021(가): 쓸 수 있는 켜진 주소가 없으면 청구처 498 만
    v_498 := public.doc_mail_recipient(v_bill);
    if v_498->>'to' is null then
      return jsonb_build_object('list', '[]'::jsonb, 'skipped', v_skipped, 'how', 'none', 'how_498', null::text, 'customer_id', v_bill, 'stores', to_jsonb(v_stores));
    end if;
    select cc.name into v_name from public.customer_contact cc where cc.customer_id = v_bill and cc.is_active and lower(btrim(cc.email)) = v_498->>'to' order by cc.is_default desc, cc.created_at, cc.id limit 1;
    return jsonb_build_object('list', jsonb_build_array(jsonb_build_object('email', v_498->>'to', 'name', v_name, 'customer_id', v_bill, 'role', 'bill_to')),
                              'skipped', v_skipped, 'how', 'fallback_498', 'how_498', v_498->>'how', 'customer_id', v_bill, 'stores', to_jsonb(v_stores));
  end if;
  return jsonb_build_object('list', v_list, 'skipped', v_skipped, 'how', 'flags', 'how_498', null::text, 'customer_id', v_bill, 'stores', to_jsonb(v_stores));
end $$;
revoke all on function public.doc_mail_recipients(text, jsonb) from public, anon, authenticated;
comment on function public.doc_mail_recipients(text, jsonb) is 'mail-inc-1a 판정 1026(나) — 문서 메일 받는 이 목록(final_invoice · credit_note · sales_order · ship_ready · 1c 부터 doc_mail_send · doc_mail_auto_invoice 가 부른다). 청구처 = doc_mail_customer(kind, ref) · 매장 = 문서 오더들의 손님(1018 · 1024 합집합 · 셀프 청구면 청구처만) · include_in_email 켜진 활성 연락처만(1020) · lower(btrim) → ims_mail_address_ok → 처음 것만 · 상한 10 · 빠진 것은 skipped(blank | bad_shape | duplicate | cap · 1027) · 쓸 수 있는 켜진 주소가 없으면 doc_mail_recipient(청구처) 하나(how fallback_498 · how_498 = 그 함수의 how) · 그것도 없으면 how none. 반환 {list, skipped, how, how_498, customer_id, stores}. 옛 doc_mail_recipient(QBO 셋 · 백오더 둘) 무변';

-- ═══ 4) mail_claim 재발행 — DB 바이트(md5 a1264c93 · 20261102013000 mail_live_1) 그대로 + 'to_more' 한 줄(보고서 C 47 줄 · 1b EF 의 재료) ═══
CREATE OR REPLACE FUNCTION public.mail_claim(p_limit integer DEFAULT 10)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_limit   int := least(greatest(coalesce(p_limit, 10), 1), 50);
  v_enabled boolean := coalesce((select c.value from public.inv_config c where c.key = 'mail_enabled'), 'off') = 'on';
  v_stale   int;
  v_mails   jsonb;
begin
  -- 멈춘 sending — EF 가 도중에 죽었다 · 요청이 Gmail 에 갔는지 모른다 → unknown(판정 514 · 자동 재전송 금지) · 꺼져 있어도 한다(이견 2)
  with s as (
    update public.mail_outbox o
       set status = 'unknown',
           last_error = left(coalesce(o.last_error || ' · ', '') || format('stale: still sending %s after claim (attempt %s) — the request may or may not have reached Gmail', date_trunc('second', now() - o.claimed_at), o.attempts), 2000)
     where o.status = 'sending' and o.claimed_at < now() - interval '10 minutes'
    returning o.id, o.attempts
  )
  insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts, note)
  select s.id, 'stale', 'sending', 'unknown', s.attempts, 'sending for over 10 minutes' from s;
  get diagnostics v_stale = row_count;

  if not v_enabled then
    return jsonb_build_object('enabled', false, 'redirect_to', nullif((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), ''),
                              'db_role', (select c.value from public.inv_config c where c.key = 'db_role'), 'mail_live', coalesce((select c.value = 'on' from public.inv_config c where c.key = 'mail_live'), false), 'recovered_unknown', v_stale, 'mails', '[]'::jsonb);
  end if;

  with c as (
    select o.id from public.mail_outbox o
    where o.status = 'queued' and coalesce(o.next_attempt_at, '-infinity') <= now()
    order by o.next_attempt_at nulls first, o.created_at, o.id
    limit v_limit
    for update skip locked
  ),
  u as (
    update public.mail_outbox o set status = 'sending', claimed_at = now(), attempts = o.attempts + 1
    from c where o.id = c.id
    returning o.*
  ),
  e as (
    insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts)
    select u.id, 'claim', 'queued', 'sending', u.attempts from u
  )
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'kind', u.kind, 'category', u.category, 'from_address', u.from_address, 'from_name', u.from_name, 'reply_to', u.reply_to,
                                               'to_address', u.to_address, 'subject', u.subject, 'payload', u.payload, 'attempt', u.attempts, 'claimed_at', u.claimed_at,
                                               'to_more', u.to_more,
                                               'customer_id', u.customer_id, 'location_id', u.location_id, 'run_id', u.run_id) order by u.next_attempt_at nulls first, u.created_at, u.id), '[]'::jsonb)
    into v_mails from u;

  return jsonb_build_object('enabled', true, 'redirect_to', nullif((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), ''),
                            'db_role', (select c.value from public.inv_config c where c.key = 'db_role'), 'mail_live', coalesce((select c.value = 'on' from public.inv_config c where c.key = 'mail_live'), false), 'recovered_unknown', v_stale, 'mails', v_mails);
end;
$function$

;
comment on function public.mail_claim(int) is 'mail-2a — 보내는 EF(mail-2b)가 부른다(service_role 만). ① 10 분 넘게 sending 인 메일은 unknown(판정 514 — 요청이 갔는지 모른다 · 자동 재전송 안 함 · 꺼져 있어도) ② mail_enabled on 이면 queued 이고 next_attempt_at ≤ now() 인 메일을 오래된 것부터 p_limit(1 ~ 50)통 for update skip locked 로 sending · claimed_at · attempts + 1 ③ 반환 {enabled, redirect_to(비면 null), db_role, mail_live(boolean · mail-live-1 판정 947), recovered_unknown, mails[{id, kind, category, from_address, from_name, reply_to, to_address, to_more(text[] → JSON 배열 · 비면 [] · mail-inc-1a 판정 1028 · 1b EF 가 To 에 잇는다), subject, payload, attempt, claimed_at, customer_id, location_id, run_id}]} — 돌려 보내기 · 켜짐 판단은 EF 가 보내기 직전에';

-- ═══ 5) 착지 확인 ═══
do $$
declare v_bad text := ''; v_acl text; v_src text;
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox' and column_name = 'to_more' and data_type = 'ARRAY' and is_nullable = 'NO' and column_default = '''{}''::text[]') then v_bad := v_bad || ' to_more-column'; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.mail_outbox'::regclass and conname = 'mail_outbox_to_more_ck' and contype = 'c') then v_bad := v_bad || ' to_more-check'; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.mail_outbox'::regclass and conname = 'mail_outbox_to_ck') or not exists (select 1 from pg_constraint where conrelid = 'public.mail_outbox'::regclass and conname = 'mail_outbox_original_to_ck') then v_bad := v_bad || ' old-checks'; end if;
  if not public.ims_mail_to_more_ok('a@x.ca', '{}') or not public.ims_mail_to_more_ok('a@x.ca', array['b@x.ca', 'c@x.ca']) then v_bad := v_bad || ' helper-accept'; end if;
  if public.ims_mail_to_more_ok('a@x.ca', array['A@x.ca']) or public.ims_mail_to_more_ok('a@x.ca', array['b@x.ca, c@x.ca']) or public.ims_mail_to_more_ok('a@x.ca', array['b@x.ca', 'B@x.ca']) or public.ims_mail_to_more_ok('a@x.ca', null) then v_bad := v_bad || ' helper-reject'; end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_mail_to_more_ok';
  if v_acl is distinct from (select proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_mail_address_ok') then v_bad := v_bad || ' helper acl ' || coalesce(v_acl, 'null'); end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_recipients';
  if v_acl is distinct from (select proacl::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_recipient') then v_bad := v_bad || ' recipients acl ' || coalesce(v_acl, 'null'); end if;
  if (select provolatile::text || prosecdef::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_recipients') <> 'sfalse' then v_bad := v_bad || ' recipients-volatility'; end if;
  select prosrc into v_src from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_claim';
  if md5(v_src) = 'a1264c93917ed04cd3aaf15c74e89914' then v_bad := v_bad || ' mail_claim-not-reissued'; end if;
  if (select count(*) from regexp_matches(v_src, '''to_more'', u\.to_more', 'g')) <> 1 then v_bad := v_bad || ' mail_claim-to_more-line'; end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_claim';
  if v_acl <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' mail_claim acl ' || coalesce(v_acl, 'null'); end if;
  -- 무변 셋
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_recipient') <> '40411541bc7be327e67fd9c0e4839287' then v_bad := v_bad || ' doc_mail_recipient-changed'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_customer')  <> '56f212dcbf7be8657f38a32aebad6a7a' then v_bad := v_bad || ' doc_mail_customer-changed'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'doc_mail_send')      <> '29cef8a7fab52de07e3e510297ad2d98' then v_bad := v_bad || ' doc_mail_send-changed'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM100', message = format('STOP - mail-inc-1a landing check failed:%s', v_bad); end if;
end $$;
