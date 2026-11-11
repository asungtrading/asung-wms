-- 20261111013522_qbo_dname_1_customer_display_name.sql — qbo-dname-1 · QuickBooks 에 손님을 만들 때 Display name 을 먼저 쓴다 (판정 1153 + 보충 · Caleb 2026-11-10 · 지시서 ~/asung/prompts/qbo-dname-1.md)
-- [Asung-IMS · 운영 메인] 적용은 Caleb: psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일> → migration repair · ⚠️ db push 금지 · 이 파일에 begin · commit 없음
-- 무엇(함수 셋 재발행 · 시그니처 · 권한 · 설정 그대로 · create or replace · 표 · 행 무변):
--   A qbo_customer_body(원본 = 20261102003000 · DB prosrc md5 eab0f5fa82077b0457330671ad05c750 → 새 몸 md5 a4a1d9d5422c43d8af2508fdd116c331)
--       ① DisplayName = left(btrim(coalesce(nullif(btrim(display_name), ''), name)), 100) — 거울(Customer · Vendor) 충돌 검사도 그 이름으로(1153 ①)
--       ② CompanyName = left(btrim(name), 100) 그대로(보충 2) · 돌려주는 display_name 열쇠 = 실제로 보낼 이름(claim · preview · unknown 조회가 읽는다 — 무변)
--       ③ 충돌 글 둘(1153 ② · 보충 4): Display name 빈 손님 = 「같은 손님이면 짝 · 다른 사람이면 Display name → Retry」 / 찬 손님 = 「Display name 도 이미 있다 — 고치고 Retry」
--       ④ 콜론 · 제어 문자(탭 · 줄바꿈)가 든 이름은 거부(보충 6 · 자동으로 바꾸지 않는다) · 100 자 자름 경고는 보낸 이름의 출처에 맞춰
--   B qbo_job_fail(원본 = 20261102003000 · md5 fdd230fa5b4de73c7345b32836ef8439 → 8f8bd3c49eff82a18ecff38affc3e922) — kind customer 의 6240(Duplicate Name · EF 가 넘긴 Intuit 글)에 할 일을 앞에 붙인다(보충 3 · Vendor 는 그대로)
--   C qbo_match_auto(원본 = 20261101230000 · md5 616dae936f4aaa9caa61a64e85d72845 → ceab383236e39f4685cb427d77cd9064) — 손님 열쇠 = 몸이 보낼 이름(Display name 우선 · 보충 1) · 다른 kind 무변
-- 무접촉: qbo_job_claim · qbo_job_open_or_add · qbo_job_preview · qbo_job_retry · qbo_job_unknown_list · qbo_ims_rows(짝 화면의 IMS 이름은 name 그대로) · qbo_vendor_body · EF · cron · 화면 · 실제 행
--   이미 QuickBooks 에 이어진 손님은 건드리지 않는다(1153 ④ — 몸은 만들 때만 불린다 · Display name 을 나중에 바꿔도 QBO 이름 그대로)
-- 검증: supabase/tests/qbo_dname_1_check.sql

-- ═══ A) 손님 몸 ═══
create or replace function public.qbo_customer_body(p_customer_id uuid) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := public.qbo_realm_of(); v_c public.customer%rowtype; v_a public.customer_address%rowtype; v_name text; v_dup text; v_email text; v_term text; v_tax text; v_parent text; v_country text;
        v_warn text[] := '{}'; v_cur text; v_body jsonb;
        v_dn text; v_company text;   -- qbo-dname-1 판정 1153: Display name(비면 null) · CompanyName(= name 그대로)
begin
  select * into v_c from public.customer c where c.id = p_customer_id;
  if v_c.id is null then raise exception 'No IMS customer % — nothing was sent', p_customer_id; end if;
  if not v_c.is_active then raise exception 'IMS customer % is inactive — not sent to QuickBooks', v_c.name; end if;
  v_dn := nullif(btrim(coalesce(v_c.display_name, '')), '');                                              -- qbo-dname-1 판정 1153 ①: Display name 이 있으면 그 이름 · 공백뿐이면 없는 것
  v_name := left(btrim(coalesce(v_dn, v_c.name)), 100);
  v_company := nullif(left(btrim(v_c.name), 100), '');                                                    -- 보충 2: CompanyName 은 name 그대로(QuickBooks 에서 겹치면 안 되는 것은 DisplayName 뿐)
  if v_name = '' then raise exception 'IMS customer % has an empty name — nothing was sent', p_customer_id; end if;
  if v_name ~ '[[:cntrl:]:]' then                                                                          -- 보충 6: 콜론 · 탭 · 줄바꿈(제어 문자)은 QuickBooks 이름에 못 쓴다 — 자동으로 바꾸지 않고 거부
    if v_dn is not null then raise exception 'The Display name "%" has a character QuickBooks does not accept in a name (a colon, a tab or a line break) — change the Display name of IMS customer "%" in Customers, then Retry — nothing was sent', v_name, btrim(v_c.name);
    else raise exception 'The name of IMS customer "%" has a character QuickBooks does not accept in a name (a colon, a tab or a line break) — give this customer a Display name without it in Customers, then Retry — nothing was sent', v_name; end if;
  end if;
  if v_dn is not null and length(v_dn) > 100 then v_warn := array_append(v_warn, ('Display name cut to 100 characters: ' || v_name));
  elsif v_dn is null and length(btrim(v_c.name)) > 100 then v_warn := array_append(v_warn, ('name cut to 100 characters: ' || v_name)); end if;
  if v_dn is not null and length(btrim(v_c.name)) > 100 then v_warn := array_append(v_warn, ('company name cut to 100 characters: ' || v_company)); end if;
  select e.qbo_type || ' #' || e.qbo_id || ' ' || e.name into v_dup from public.qbo_entity e
    where e.realm_id = v_realm and e.qbo_type in ('Customer', 'Vendor') and e.gone_at is null and lower(btrim(e.name)) = lower(v_name) order by e.active desc, e.qbo_type, e.qbo_id limit 1;
  if v_dup is not null then                                                                                -- 판정 1153 ② · 보충 4: 할 일을 적는다 — Display name 이 이미 찬 손님이 또 겹치면 글이 다르다
    if v_dn is null then raise exception 'QuickBooks already has a customer or supplier named "%" (%) — if it is the same customer, link them under Settings → QuickBooks matching; if it is a different person, give IMS customer "%" a Display name in Customers, then Retry — nothing was sent', v_name, v_dup, btrim(v_c.name);
    else raise exception 'The Display name "%" is also taken in QuickBooks (%) — change the Display name of IMS customer "%" in Customers, then Retry — nothing was sent', v_name, v_dup, btrim(v_c.name); end if;
  end if;
  select * into v_a from public.customer_address a where a.customer_id = p_customer_id and a.is_active and a.type = 'Billing' and a.is_default_for_type order by a.created_at, a.id limit 1;
  if v_a.id is null then v_warn := array_append(v_warn, 'no default billing address — BillAddr not sent'); end if;
  v_country := public.qbo_country_name(v_a.country);
  if v_country is not null and v_country not in ('Canada', 'USA') then v_warn := array_append(v_warn, ('country "' || v_country || '" sent as is (946 maps only CA and US)')); end if;
  v_email := public.doc_mail_recipient(p_customer_id)->>'to';
  if v_email is null then v_warn := array_append(v_warn, 'no email on file — PrimaryEmailAddr not sent'); end if;
  if v_c.payment_term_id is not null then
    select l.qbo_id into v_term from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'payment_term' and l.ims_id = v_c.payment_term_id::text;
    if v_term is null then v_warn := array_append(v_warn, ('payment term "' || coalesce(v_c.payment_term_name, '?') || '" has no QuickBooks match — SalesTermRef not sent')); end if;
  end if;
  if nullif(btrim(coalesce(v_c.tax_rule, '')), '') is not null then
    select l.qbo_id into v_tax from public.ref_tax_rule t join public.qbo_link l on l.realm_id = v_realm and l.ims_kind = 'tax_rule' and l.ims_id = t.id::text where t.name = v_c.tax_rule order by t.is_active desc limit 1;
    if v_tax is null then v_warn := array_append(v_warn, ('tax rule "' || v_c.tax_rule || '" has no QuickBooks match — DefaultTaxCodeRef not sent')); end if;
  end if;
  if v_c.parent_id is not null then
    select l.qbo_id into v_parent from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = v_c.parent_id::text;
  end if;
  v_cur := coalesce(nullif(btrim(coalesce(v_c.currency_code, '')), ''), (select c.value from public.inv_config c where c.key = 'customer_default_currency_code'), 'CAD');
  v_body := jsonb_strip_nulls(jsonb_build_object(
    'DisplayName', v_name, 'CompanyName', v_company, 'Taxable', true,
    'CurrencyRef', jsonb_build_object('value', v_cur),
    'BillAddr', case when v_a.id is not null then jsonb_build_object('Line1', nullif(btrim(coalesce(v_a.line1, '')), ''), 'Line2', nullif(btrim(coalesce(v_a.line2, '')), ''), 'City', nullif(btrim(coalesce(v_a.city, '')), ''),
                                                                    'CountrySubDivisionCode', nullif(btrim(coalesce(v_a.state_province, '')), ''), 'PostalCode', nullif(btrim(coalesce(v_a.postal_code, '')), ''), 'Country', v_country) end,
    'PrimaryEmailAddr', case when v_email is not null then jsonb_build_object('Address', v_email) end,
    'SalesTermRef', case when v_term is not null then jsonb_build_object('value', v_term) end,
    'DefaultTaxCodeRef', case when v_tax is not null then jsonb_build_object('value', v_tax) end,
    'ParentRef', case when v_parent is not null then jsonb_build_object('value', v_parent) end,
    'Job', case when v_parent is not null then true end,
    'BillWithParent', case when v_parent is not null then (v_c.default_bill_to_customer_id = v_c.parent_id) end));
  return jsonb_build_object('kind', 'customer', 'ims_kind', 'customer', 'ims_id', p_customer_id::text, 'display_name', v_name, 'body', v_body, 'warnings', to_jsonb(v_warn),
                            'parent_customer_id', case when v_c.parent_id is not null and v_parent is null then v_c.parent_id::text end);
end;
$$;
do $$
begin
  execute format('comment on function public.qbo_customer_body(uuid) is %L', coalesce(obj_description('public.qbo_customer_body(uuid)'::regprocedure, 'pg_proc'), '') || ' · [qbo-dname-1 판정 1153: DisplayName = Display name 이 있으면 그 이름 · 없으면 name(100 자) · CompanyName 은 name 그대로 · 충돌 글에 할 일(같은 손님이면 짝 · 다른 사람이면 Display name → Retry · Display name 도 겹치면 고치고 Retry) · 콜론 · 제어 문자 이름 거부]');
end $$;

-- ═══ B) 보내기 거부 — 손님 6240 안내 ═══
create or replace function public.qbo_job_fail(p_job uuid, p_error text, p_intuit_tid text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_j public.qbo_job%rowtype; v_err text; v_cn text; v_dn text;   -- qbo-dname-1
begin
  if not public.doc_is_service() then raise exception 'qbo_job_fail is for the send worker only — nothing was saved'; end if;
  select * into v_j from public.qbo_job j where j.id = p_job for update;
  if v_j.id is null then raise exception 'Job % not found — nothing was saved', p_job; end if;
  if v_j.state not in ('sending', 'unknown') then raise exception 'Only a job being sent, or one whose result is unknown, can fail (this one is %) — nothing was saved', v_j.state; end if;
  v_err := left(coalesce(nullif(btrim(coalesce(p_error, '')), ''), 'send failed'), 2000);
  -- qbo-dname-1 판정 1153 ② · 보충 3: QuickBooks 가 손님 만들기를 6240(Duplicate Name — 거울에 없는 Employee 등)으로 거부하면 할 일을 앞에 붙인다 · Vendor 는 범위 밖(그대로)
  if v_j.kind = 'customer' and (v_err ~ '\mcode 6240\M' or v_err ~* 'duplicate name exists') then
    select btrim(c.name), nullif(btrim(coalesce(c.display_name, '')), '') into v_cn, v_dn from public.customer c where c.id::text = v_j.ims_id;
    if v_cn is not null then
      v_err := left(case when v_dn is null
          then format('QuickBooks already has a customer, supplier or employee named "%s" — if it is the same customer, link them under Settings → QuickBooks matching; if it is a different person, give IMS customer "%s" a Display name in Customers, then Retry — nothing was sent', left(v_cn, 100), v_cn)
          else format('The Display name "%s" is also taken in QuickBooks — change the Display name of IMS customer "%s" in Customers, then Retry — nothing was sent', left(v_dn, 100), v_cn) end
        || ' · QuickBooks answered: ' || v_err, 2000);
    end if;
  end if;
  update public.qbo_job j set state = 'failed', claimed_at = null, last_error = v_err, last_intuit_tid = coalesce(p_intuit_tid, j.last_intuit_tid) where j.id = v_j.id;
  return jsonb_build_object('job_id', v_j.id, 'state', 'failed', 'attempts', v_j.attempts);
end;
$$;
do $$
begin
  execute format('comment on function public.qbo_job_fail(uuid, text, text) is %L', coalesce(obj_description('public.qbo_job_fail(uuid, text, text)'::regprocedure, 'pg_proc'), '') || ' · [qbo-dname-1 판정 1153: kind customer 의 6240(Duplicate Name)이면 last_error 앞에 할 일을 붙인다(Display name → Retry) · 뒤에 「QuickBooks answered: 」 + Intuit 글 · Vendor 는 그대로]');
end $$;

-- ═══ C) 자동 짝 — 손님 열쇠 ═══
create or replace function public.qbo_match_auto(p_kind text, p_after text default null, p_limit int default 5000) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp set client_min_messages = warning   -- drop table if exists 의 NOTICE 를 끈다
as $$
declare v_staff uuid := public.qbo_sync_gate(); v_realm text := public.qbo_realm_of(); v_type text := public.qbo_type_of(p_kind); v_by text; v_st public.qbo_pull_state%rowtype;
        v_lim int := least(greatest(coalesce(p_limit, 5000), 1), 20000); v_linked int; v_next text; v_remaining int; v_res jsonb;
begin
  if v_type is null then raise exception 'kind must be one of account, tax_rule, payment_term, payment_method, customer, supplier, product, charge, service (got %)', p_kind; end if;
  if p_kind in ('charge', 'service') then raise exception 'No automatic rule for % — link it by hand with qbo_link_set', p_kind; end if;
  select * into v_st from public.qbo_pull_state s where s.realm_id = v_realm and s.qbo_type = v_type;
  if v_st.finished_at is null then raise exception 'The QuickBooks % list has not been pulled completely — run the pull first', v_type; end if;
  v_by := case p_kind when 'account' then 'auto_code' when 'payment_method' then 'auto_map' when 'product' then 'auto_sku' else 'auto_name' end;
  drop table if exists t_ims, t_ent, t_cand, t_pick;
  create temp table t_ims on commit drop as                                                            -- 이 묶음 = 활성 · 짝 없음 · ims_id > p_after · ims_id 순 · v_lim 개
    select r.ims_id, r.ims_name, lower(btrim(left(r.ims_name, 100))) as nm,
      case p_kind when 'account' then (regexp_match(r.ims_code, '^_([0-9]+)_$'))[1]
                  when 'tax_rule' then lower(btrim(regexp_replace(r.ims_name, '\s*\((Sale|Purchase)\)\s*$', '')))
                  when 'payment_term' then regexp_replace(lower(r.ims_name), '\s', '', 'g')
                  when 'payment_method' then lower(r.ims_code)
                  when 'product' then lower(btrim(r.ims_code))
                  when 'customer' then lower(btrim(coalesce((select left(btrim(c.display_name), 100) from public.customer c where c.id = r.ims_id::uuid and nullif(btrim(coalesce(c.display_name, '')), '') is not null), r.ims_name)))   -- qbo-dname-1 판정 1153 보충 1: 손님 열쇠 = 몸이 보낼 이름(Display name 우선 · 없으면 name)
                  else lower(btrim(r.ims_name)) end as k
    from public.qbo_ims_rows(p_kind) r
    where r.ims_active and (p_after is null or r.ims_id > p_after)
      and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = r.ims_id)
    order by r.ims_id limit v_lim;
  analyze t_ims;
  create temp table t_ent on commit drop as
    select e.qbo_id, e.name, e.active, lower(btrim(e.name)) as nm,
      case p_kind when 'account' then e.qbo_id when 'payment_term' then regexp_replace(lower(e.name), '\s', '', 'g') when 'product' then lower(btrim(e.sku)) else lower(btrim(e.name)) end as k
    from public.qbo_entity e where e.realm_id = v_realm and e.qbo_type = v_type and e.gone_at is null;
  analyze t_ent;
  create temp table t_cand on commit drop as
    select i.ims_id, e.qbo_id, e.name as qbo_name, e.active, (p_kind = 'product' and e.nm = i.nm) as name_hit from t_ims i join t_ent e on e.k = i.k where i.k is not null;
  analyze t_cand;
  create temp table t_pick on commit drop as
    select x.*, case when x.n_act = 1 then x.id_act when x.n_act > 1 and x.n_name = 1 then x.id_name end as qbo_id,
                case when x.n_act = 1 then x.nm_act when x.n_act > 1 and x.n_name = 1 then x.nm_name end as qbo_name,
                case when x.n_act = 1 then v_by when x.n_act > 1 and x.n_name = 1 then v_by || '_name' end as by,
                case when x.n_act = 1 or (x.n_act > 1 and x.n_name = 1) then 'linked' when x.k is null then 'skipped' when x.n_all > 0 then 'ambiguous' else 'absent' end as state
    from (select i.ims_id, i.ims_name, i.k, count(c.qbo_id) as n_all, count(c.qbo_id) filter (where c.active) as n_act, count(c.qbo_id) filter (where c.active and c.name_hit) as n_name,
                 (array_agg(c.qbo_id) filter (where c.active))[1] as id_act, (array_agg(c.qbo_name) filter (where c.active))[1] as nm_act,
                 (array_agg(c.qbo_id) filter (where c.active and c.name_hit))[1] as id_name, (array_agg(c.qbo_name) filter (where c.active and c.name_hit))[1] as nm_name,
                 string_agg(c.qbo_id || ' ' || c.qbo_name || case when c.active then '' else ' (inactive)' end, ' | ' order by c.active desc, c.qbo_id) as candidates
          from t_ims i left join t_cand c on c.ims_id = i.ims_id group by i.ims_id, i.ims_name, i.k) x;
  analyze t_pick;
  insert into public.qbo_link (realm_id, ims_kind, ims_id, qbo_type, qbo_id, matched_by, qbo_name_at_match, by_staff)
  select v_realm, p_kind, p.ims_id, v_type, p.qbo_id, p.by, p.qbo_name, v_staff from t_pick p where p.state = 'linked'
  on conflict (realm_id, qbo_type, qbo_id) where ims_kind <> 'tax_rule' do nothing;                      -- QBO 쪽이 이미 다른 IMS 행의 것이면 못 넣는다 → ambiguous
  get diagnostics v_linked = row_count;
  update t_pick p set state = 'ambiguous', candidates = coalesce(p.candidates, '') || ' (QuickBooks id already linked)'
    where p.state = 'linked' and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = p.ims_id);
  select coalesce(max(p.ims_id), p_after) into v_next from t_pick p;                                     -- 묶음이 비면 p_after 그대로
  select count(*) into v_remaining from public.qbo_ims_rows(p_kind) r                                   -- 이 묶음 뒤에 남은 활성 · 짝 없음(absent · ambiguous 는 남지 않는다 — 다음 묶음은 next_after 뒤만)
    where r.ims_active and (v_next is null or r.ims_id > v_next)
      and not exists (select 1 from public.qbo_link l where l.realm_id = v_realm and l.ims_kind = p_kind and l.ims_id = r.ims_id);
  select jsonb_build_object('kind', p_kind, 'qbo_type', v_type, 'realm_id', v_realm, 'considered', count(*), 'linked', v_linked,
           'absent', count(*) filter (where p.state = 'absent'), 'ambiguous', count(*) filter (where p.state = 'ambiguous'), 'skipped', count(*) filter (where p.state = 'skipped'),
           'limit', v_lim, 'after', p_after, 'next_after', v_next, 'remaining', v_remaining, 'done', v_remaining = 0,
           'examples', jsonb_build_object(
             'ambiguous', (select coalesce(jsonb_agg(jsonb_build_object('ims_id', a.ims_id, 'ims_name', a.ims_name, 'candidates', a.candidates) order by a.ims_name), '[]'::jsonb) from (select * from t_pick where state = 'ambiguous' order by ims_name limit 20) a),
             'absent',    (select coalesce(jsonb_agg(b.ims_name order by b.ims_name), '[]'::jsonb) from (select ims_name from t_pick where state = 'absent' order by ims_name limit 20) b),
             'skipped',   (select coalesce(jsonb_agg(s.ims_name order by s.ims_name), '[]'::jsonb) from t_pick s where s.state = 'skipped')))
  into v_res from t_pick p;
  return v_res;
end;
$$;
do $$
begin
  execute format('comment on function public.qbo_match_auto(text, text, int) is %L', coalesce(obj_description('public.qbo_match_auto(text, text, int)'::regprocedure, 'pg_proc'), '') || ' · [qbo-dname-1 판정 1153: 손님 열쇠 = Display name 이 있으면 그 이름(100 자) · 없으면 name — 몸이 QuickBooks 에 보낼 이름과 같다]');
end $$;

-- ═══ 착지 검사 ═══
do $$
declare v text;
begin
  select string_agg(p.proname || '=' || md5(p.prosrc) || ' ' || p.proacl::text || ' ' || p.provolatile::text || ' ' || p.prosecdef::text || ' ' || (select count(*) from pg_proc q where q.pronamespace = 'public'::regnamespace and q.proname = p.proname)::text, ' | ' order by p.proname)
    into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('qbo_customer_body', 'qbo_job_fail', 'qbo_match_auto');
  if v is distinct from 'qbo_customer_body=a4a1d9d5422c43d8af2508fdd116c331 {postgres=X/postgres} s true 1 | qbo_job_fail=8f8bd3c49eff82a18ecff38affc3e922 {postgres=X/postgres,service_role=X/postgres} v true 1 | qbo_match_auto=ceab383236e39f4685cb427d77cd9064 {postgres=X/postgres,authenticated=X/postgres} v true 1' then
    raise exception 'qbo-dname-1 landing check failed (%) — nothing was saved', v;
  end if;
end $$;
