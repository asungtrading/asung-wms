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
-- 20261019152102_doc_1b1_data.sql — doc-1b1 (2026-10-19 · 회사 PC · Fable · 문서 템플릿 ② 데이터 창구 — final_invoice · internal_receipt · credit_note · sales_order)
--   판정 521 ~ 525 · doc-0 Q2 원천 · doc-1a 계약 doc_field_catalog(31c39cd · 20261019144030:371 ~ 432) · doc-1b1 §0 이견(회신)
--   ① 꼴 도우미 넷 doc_fmt_money · doc_fmt_qty · doc_fmt_pct · doc_fmt_date(돈 1,234.56 · 수량 정수면 소수 없이 · % 0 이면 "" · 날짜 꼴은 inv_config doc_date_format)
--   ② 회사 키 둘 더함 doc_date_format(여섯 꼴 중 하나 · 첫 값 DDMONYYYY = 16OCT2026) · doc_public_base_url(로고 공개 주소의 앞부분 · db_role 로 시드 · 창구가 logo_url 을 완성한다)
--      → ims_doc_config_keys · ims_doc_config_problem · doc_config 재발행(doc-1a 원본 바이트 + 더한 줄만)
--   ③ 창구 doc_data(p_kind, p_ref) → {kind, docs: [문서 하나 = 목록과 똑같은 열쇠]} · 문 = doc_staff_or_service(활성 직원 · service_role) · definer · 속 셋(invoice · credit · so) + 공통 머리 하나
--      final_invoice · internal_receipt {invoice_id} = so_invoice 표 셋(굳은 값) + 지금 값(바코드 · 줄 메모 · 연락처 · 택배 · 송장 · 결제) · 판정 314 so_invoice_unit_display
--      credit_note {credit_id} = so_credit 표 둘 + 원 인보이스의 굳은 주소(없으면 손님 기본 주소) · 환불 = refund 배분 · remaining = so_credit_remaining
--      sales_order {so_id} = so_proforma(한 오더) + so_line 표지(no_price · free) · 선결제 = proforma deposits
--      ship_ready = 거부 한 줄(doc-1b2 · 마무리 미리 보기에 돈을 얹는 차수)
--   ⚠️ 원천 창구(so_invoice_detail · so_credit_detail · so_proforma · so_invoice_issue)는 재발행하지 않는다 · 새 읽기 창구만
--   무접촉: 화면 · git · 운영 DB · 번호 시퀀스 · 첫 문장 = guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/doc-1b1-verify.sql

-- ═══ ① 꼴 도우미 — 판은 로직이 없다(Mustache) · 꼴은 창구가 만든다 ═══
create function public.doc_fmt_money(p numeric) returns text
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$ select case when p is null then '' else trim(to_char(round(p, 2), 'FM999,999,999,990.00')) end; $$;
create function public.doc_fmt_qty(p numeric) returns text
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$ select case when p is null then '' when p = trunc(p) then trunc(p)::bigint::text else rtrim(rtrim(p::text, '0'), '.') end; $$;
create function public.doc_fmt_pct(p numeric) returns text
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$ select case when p is null or p = 0 then '' else public.doc_fmt_qty(p) || '%' end; $$;
create function public.doc_fmt_date(p date, p_fmt text) returns text
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$ select case when p is null then '' else to_char(p, coalesce(nullif(p_fmt, ''), 'DDMONYYYY')) end; $$;
comment on function public.doc_fmt_money(numeric) is 'doc-1b1 ② — 돈 글자: 소수 둘 · 천 단위 쉼표 · 음수 -1,234.56 · null 은 ""(가격 없음 줄)';
comment on function public.doc_fmt_qty(numeric) is 'doc-1b1 ② — 수량 글자: 정수면 소수 없이(2) · 소수가 있으면 있는 만큼(2.5) · null 은 ""';
comment on function public.doc_fmt_pct(numeric) is 'doc-1b1 ② — % 글자: 0 · null 이면 "" · 아니면 20% 꼴';
comment on function public.doc_fmt_date(date, text) is 'doc-1b1 ② — 날짜 글자: inv_config doc_date_format(여섯 꼴 · 첫 값 DDMONYYYY = 16OCT2026) · null 은 ""';
revoke all on function public.doc_fmt_money(numeric), public.doc_fmt_qty(numeric), public.doc_fmt_pct(numeric), public.doc_fmt_date(date, text) from public, anon;
grant execute on function public.doc_fmt_money(numeric), public.doc_fmt_qty(numeric), public.doc_fmt_pct(numeric), public.doc_fmt_date(date, text) to authenticated, service_role;

-- ═══ ② 회사 키 둘 — ims_doc_config_keys 재발행(원본 20261019144030:129 바이트 + 둘) · ims_doc_config_problem 재발행(원본 :139 바이트 + 갈래 둘) · 시드 ═══
create or replace function public.ims_doc_config_keys() returns text[]
  language sql immutable
  set search_path = public, pg_temp
as $$
  select array['doc_company_name', 'doc_hst', 'doc_website', 'doc_terms', 'doc_branches', 'doc_logo_path', 'doc_date_format', 'doc_public_base_url'];   -- doc-1b1: 날짜 꼴 · 공개 주소 앞부분
$$;
comment on function public.ims_doc_config_keys() is 'doc-1a 판정 524 · 525 — inv_config 의 회사 글 키(모든 문서의 머리 · 꼬리가 읽는다 · doc_config) · inv_config_guard 의 문서 갈래(값 검사 누가 쓰든 · 화면 쓰기는 master · 삭제 · 이름 바꾸기 거부)가 읽는다 · 메일 키(ims_mail_config_keys)와 같은 꼴 · [doc-1b1] 여섯 → 여덟(doc_date_format · doc_public_base_url)';

create or replace function public.ims_doc_config_problem(p_key text, p_value text, p_delete boolean default false) returns text
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_j jsonb;
  v_e jsonb;
  v_codes text[] := '{}';
begin
  if p_delete then return 'cannot be removed — change its value instead'; end if;
  if p_value is null then return 'cannot be empty (null)'; end if;
  case p_key
  when 'doc_company_name' then
    if btrim(p_value) = '' or length(p_value) > 120 then return 'must be the company name (1 to 120 characters)'; end if;
  when 'doc_hst' then
    if length(p_value) > 40 then return 'must be at most 40 characters'; end if;
  when 'doc_website' then
    if length(p_value) > 100 or p_value ~ '[[:space:]<>"'']' then return 'must be a web address like asung.ca (at most 100 characters · no spaces or quotes)'; end if;
  when 'doc_terms' then
    if length(p_value) > 10000 then return 'must be at most 10000 characters'; end if;
    if p_value ~* '<script[[:space:]>/]' or p_value ~* '<[^>]*[[:space:]]on[a-z]+[[:space:]]*=' then return 'must not contain script or on…= attributes'; end if;
  when 'doc_branches' then
    begin
      v_j := p_value::jsonb;
    exception when others then
      return 'must be JSON like [{"code":"TOR","label":"Toronto","line1":"…","line2":"…","phone":"…","email":"…"}, {"code":"EDM", …}]';
    end;
    if jsonb_typeof(v_j) <> 'array' or jsonb_array_length(v_j) <> 2 then return 'must be a JSON list of exactly two branches (TOR and EDM — ruling 524: both are printed on every document)'; end if;
    for v_e in select x from jsonb_array_elements(v_j) x loop
      if jsonb_typeof(v_e) <> 'object' or coalesce((select array_agg(k order by k) from jsonb_object_keys(v_e) k), '{}') <> array['code', 'email', 'label', 'line1', 'line2', 'phone']
         or exists (select 1 from jsonb_each(v_e) t where jsonb_typeof(t.value) <> 'string') then
        return 'each branch needs exactly code, label, line1, line2, phone, email — all text (empty allowed)';
      end if;
      if v_e->>'code' not in ('TOR', 'EDM') then return format('branch code must be TOR or EDM (got %s)', v_e->>'code'); end if;
      if exists (select 1 from jsonb_each_text(v_e) t where length(t.value) > 200) then return format('branch %s: a value is longer than 200 characters', v_e->>'code'); end if;
      v_codes := array_append(v_codes, v_e->>'code');
    end loop;
    if (select array_agg(c order by c) from unnest(v_codes) c) <> array['EDM', 'TOR'] then return 'must have one TOR branch and one EDM branch'; end if;
  when 'doc_logo_path' then
    if p_value <> '' then
      if p_value !~ '^[A-Za-z0-9][A-Za-z0-9._/-]{0,199}$' or p_value ~ '\.\.' then return format('must be empty or a file path inside the doc-brand bucket (got %s)', p_value); end if;
      if not exists (select 1 from storage.objects o where o.bucket_id = 'doc-brand' and o.name = p_value) then return format('%s is not in the doc-brand bucket — upload the logo first', p_value); end if;
    end if;
  when 'doc_date_format' then                                                                                              -- doc-1b1: 여섯 꼴 중 하나(to_char 패턴 · Settings 가 고른다)
    if p_value not in ('DDMONYYYY', 'DD Mon YYYY', 'YYYY-MM-DD', 'MM/DD/YYYY', 'DD/MM/YYYY', 'Mon DD, YYYY') then
      return format('must be one of DDMONYYYY, DD Mon YYYY, YYYY-MM-DD, MM/DD/YYYY, DD/MM/YYYY, Mon DD, YYYY (got %s)', p_value);
    end if;
  when 'doc_public_base_url' then                                                                                          -- doc-1b1: https:// + 호스트 · 끝 / 없음 · 로고 공개 주소의 앞부분
    if p_value !~ '^https://[a-z0-9][a-z0-9.-]{2,120}$' then return format('must be https://<host> with no path or trailing slash (got %s)', p_value); end if;
  else
    return 'is not a document setting';
  end case;
  return null;
end;
$$;
comment on function public.ims_doc_config_problem(text, text, boolean) is 'doc-1a — 회사 글 키의 값 검사(inv_config_guard 가 부른다 · 누가 쓰든): null = 통과 · 아니면 거부 문장. doc_branches = 지점 둘(TOR · EDM 고정 · 칸 여섯 전부 글자 · 빈 칸 허용 · 창고 id 와 엮지 않는다 — 판정 524 「두 지점을 늘 함께」) · doc_logo_path = 빈 값 또는 doc-brand 버킷에 실재하는 경로 · doc_terms 는 글(script · on…= 만 막는다 · 판은 따로 거부) · 지우기 거부 · [doc-1b1] doc_date_format 여섯 꼴 · doc_public_base_url https://<host>';

insert into public.inv_config (key, value, note) values
  ('doc_date_format', 'DDMONYYYY', 'doc-1b1 — 문서의 날짜 꼴(to_char 패턴 · DDMONYYYY = 16OCT2026 · DD Mon YYYY · YYYY-MM-DD · MM/DD/YYYY · DD/MM/YYYY · Mon DD, YYYY) · 바꾸기 master'),
  ('doc_public_base_url', case when (select c.value from public.inv_config c where c.key = 'db_role') = 'test' then 'https://fazgmyvzzhqybtvtktyg.supabase.co' else 'https://gftpcnkxbdjzzfvzwcfl.supabase.co' end,
                          'doc-1b1 — 로고 공개 주소의 앞부분(doc_data 가 company.logo_url = 이 값 + /storage/v1/object/public/doc-brand/ + doc_logo_path 로 완성한다) · 시드는 db_role 로(test = Asung-IMS · 아니면 asung-WMS) · 바꾸기 master')
  on conflict (key) do nothing;

-- doc_config 재발행 — 원본 20261019144030:716 바이트 + 더한 줄(date_format · public_base_url)
create or replace function public.doc_config() returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.doc_staff_or_service();
  return jsonb_build_object(
    'company',  jsonb_build_object('name', (select c.value from public.inv_config c where c.key = 'doc_company_name'), 'hst', (select c.value from public.inv_config c where c.key = 'doc_hst'),
                                    'website', (select c.value from public.inv_config c where c.key = 'doc_website'), 'terms', (select c.value from public.inv_config c where c.key = 'doc_terms'),
                                    'logo_path', (select c.value from public.inv_config c where c.key = 'doc_logo_path')),
    'branches', (select coalesce(c.value::jsonb, '[]'::jsonb) from public.inv_config c where c.key = 'doc_branches'),
    'settings', (select coalesce(jsonb_object_agg(x.kind, x.kv), '{}'::jsonb) from (select d.kind, jsonb_object_agg(d.key, d.value) kv from public.doc_setting d group by d.kind) x),
    'active',   (select coalesce(jsonb_object_agg(a.kind, jsonb_build_object('template_id', a.template_id, 'version', t.version, 'set_at', a.set_at)), '{}'::jsonb)
                 from public.doc_template_active a join public.doc_template t on t.id = a.template_id),
    'can_publish', public.ims_can_doc_template(), 'can_edit_text', public.ims_can_write('master'),
    'unit_display', (select c.value from public.inv_config c where c.key = 'so_invoice_unit_display'),
    'date_format', (select c.value from public.inv_config c where c.key = 'doc_date_format'),                              -- doc-1b1
    'public_base_url', (select c.value from public.inv_config c where c.key = 'doc_public_base_url'));                      -- doc-1b1
end;
$$;
comment on function public.doc_config() is 'doc-1a 읽기 — 화면 · doc-1b 데이터 창구 · doc-2 EF 가 같은 것을 읽는다: company(name · hst · website · terms · logo_path) · branches(판정 524 둘) · settings{kind: {key: value}} · active{kind: {template_id, version, set_at}} · can_publish(판정 522) · can_edit_text(판정 525) · unit_display(판정 314) · [doc-1b1] date_format · public_base_url(로고 공개 주소 = public_base_url + /storage/v1/object/public/doc-brand/ + logo_path — doc_data 가 완성한다) · 활성 직원 · service_role';

-- ═══ ③ 창구 — 공통 머리 · 속 셋 · doc_data ═══
-- 공통: company · branches(line1 빈 지점은 뺀다 — 판정 524 「둘 다」 는 값이 있을 때) · doc · show · bill_to(머리 여섯 + 연락처 둘은 부르는 쪽이 준다)
create function public.doc_data_common(p_kind text, p_cfg jsonb, p_bill_to jsonb) returns jsonb
  language sql stable
  set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'company', jsonb_build_object('name', coalesce(p_cfg->'company'->>'name', ''), 'hst', coalesce(p_cfg->'company'->>'hst', ''), 'website', coalesce(p_cfg->'company'->>'website', ''),
                                  'terms', coalesce(p_cfg->'company'->>'terms', ''),
                                  'logo_url', case when coalesce(p_cfg->'company'->>'logo_path', '') = '' then '' else (p_cfg->>'public_base_url') || '/storage/v1/object/public/doc-brand/' || (p_cfg->'company'->>'logo_path') end),
    'branches', (select coalesce(jsonb_agg(jsonb_build_object('code', b->>'code', 'label', coalesce(b->>'label', ''), 'line1', b->>'line1', 'line2', coalesce(b->>'line2', ''), 'phone', coalesce(b->>'phone', ''), 'email', coalesce(b->>'email', '')) order by ord), '[]'::jsonb)
                 from jsonb_array_elements(coalesce(p_cfg->'branches', '[]'::jsonb)) with ordinality t(b, ord) where coalesce(b->>'line1', '') <> ''),
    'doc', jsonb_build_object('kind', p_kind,
                              'title', coalesce(nullif(p_cfg->'settings'->p_kind->>'title', ''), case p_kind when 'final_invoice' then 'FINAL INVOICE' when 'internal_receipt' then 'INTERNAL USE ONLY INVOICE' when 'credit_note' then 'CREDIT NOTE' when 'sales_order' then 'SALES ORDER' else 'PROFORMA' end),
                              'printed_at', public.doc_fmt_date(public.ims_today(), p_cfg->>'date_format') || ' ' || to_char(now() at time zone 'America/Toronto', 'HH24:MI')),
    'show', jsonb_build_object('upc', coalesce(p_cfg->'settings'->p_kind->>'show_upc', 'true') = 'true', 'comment', coalesce(p_cfg->'settings'->p_kind->>'show_comment', 'true') = 'true',
                               'charge_code', coalesce(p_cfg->'settings'->p_kind->>'show_charge_code', 'false') = 'true'),
    'bill_to', jsonb_build_object('name', coalesce(p_bill_to->>'name', ''), 'line1', coalesce(p_bill_to->>'line1', ''), 'line2', coalesce(p_bill_to->>'line2', ''), 'city', coalesce(p_bill_to->>'city', ''),
                                  'state_province', coalesce(p_bill_to->>'state_province', ''), 'postal_code', coalesce(p_bill_to->>'postal_code', ''), 'country', coalesce(p_bill_to->>'country', ''),
                                  'email', coalesce(p_bill_to->>'email', ''), 'phone', coalesce(p_bill_to->>'phone', '')));
$$;
revoke all on function public.doc_data_common(text, jsonb, jsonb) from public, anon, authenticated;

-- 손님의 기본 연락처(지금 값 · 판정 498 과 같은 고르기: 기본 → 이메일 있는 활성 첫) · 결제 방식 이름
create function public.doc_contact(p_customer_id uuid) returns jsonb
  language sql stable
  set search_path = public, pg_temp
as $$
  select coalesce((select jsonb_build_object('email', coalesce(c.email, ''), 'phone', coalesce(nullif(c.phone, ''), c.mobile_phone, ''))
                   from public.customer_contact c where c.customer_id = p_customer_id and c.is_active
                   order by c.is_default desc, (c.email is not null and c.email <> '') desc, c.created_at, c.id limit 1), '{"email": "", "phone": ""}'::jsonb);
$$;
create function public.doc_method_label(p text) returns text
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$
  select case p when 'cheque' then 'Cheque' when 'credit_card' then 'Credit card' when 'debit_card' then 'Debit card' when 'e_transfer' then 'e-Transfer' when 'wire' then 'Wire transfer'
                when 'cash' then 'Cash' when 'direct_deposit' then 'Direct deposit' when 'shopify' then 'Shopify' else coalesce(p, '') end;
$$;
-- 판정 314 단가 칸 — both: unit_price + net_unit_price · discounted: unit_price 만 · net: unit_price 자리에 실제 단가 · net = unit × (1 − 오더 할인 %/100) 그릴 때 반올림
create function public.doc_unit_prices(p_unit numeric, p_od_pct numeric, p_display text) returns jsonb
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$
  select case when p_unit is null then '{"unit_price": "", "net_unit_price": ""}'::jsonb
              when p_display = 'net' then jsonb_build_object('unit_price', public.doc_fmt_money(p_unit * (1 - coalesce(p_od_pct, 0) / 100)), 'net_unit_price', '')
              when p_display = 'discounted' then jsonb_build_object('unit_price', public.doc_fmt_money(p_unit), 'net_unit_price', '')
              else jsonb_build_object('unit_price', public.doc_fmt_money(p_unit), 'net_unit_price', public.doc_fmt_money(p_unit * (1 - coalesce(p_od_pct, 0) / 100))) end;
$$;
create function public.doc_upc(p_product_id uuid) returns text
  language sql stable
  set search_path = public, pg_temp
as $$ select coalesce((select b.barcode from public.product_barcode b where b.product_id = p_product_id and b.is_active order by b.is_primary desc, b.barcode limit 1), ''); $$;
revoke all on function public.doc_contact(uuid), public.doc_method_label(text), public.doc_unit_prices(numeric, numeric, text), public.doc_upc(uuid) from public, anon, authenticated;

-- 최종 인보이스 · Internal — so_invoice 표 셋의 굳은 값 + 지금 값(바코드 · 줄 메모 · 연락처 · 택배 · 송장 · 결제)
create function public.doc_data_invoice(p_kind text, p_invoice_id uuid, p_cfg jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_inv  public.so_invoice%rowtype;
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_orders jsonb;  v_charges jsonb;  v_payments jsonb;
  v_lines_amt numeric;  v_lines_tax numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_chd numeric;  v_paid numeric;  v_qty numeric;
begin
  select * into v_inv from public.so_invoice i where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'Invoice not found'; end if;
  -- 오더마다(§8-c · so_number 순) · 제품 줄은 인보이스 안에서 1, 2, 3 … 이어서
  with pl as (
    select l.*, o.so_number as o_so_number, o.order_discount_pct as o_od_pct, sl.comments as sl_comments, sl.free_reason as sl_free, sl.product_id as sl_product_id,
           row_number() over (order by o.so_number, l.line_no) as no
    from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id left join public.so_line sl on sl.id = l.so_line_id
    where l.invoice_id = v_inv.id and l.kind = 'product')
  select coalesce(jsonb_agg(jsonb_build_object(
           'so_number', o.so_number, 'reference', coalesce(s.ref, ''), 'carrier', coalesce(s.carrier, ''), 'tracking', coalesce(s.tracking_number, ''), 'tax_rule', coalesce(o.tax_rule, ''),
           'ship_to', jsonb_build_object('company', coalesce(o.ship_to_company, ''), 'contact', coalesce(o.ship_to_contact, ''), 'phone', coalesce(o.ship_to_phone, ''), 'line1', coalesce(o.ship_to_line1, ''), 'line2', coalesce(o.ship_to_line2, ''),
                                         'city', coalesce(o.ship_to_city, ''), 'state_province', coalesce(o.ship_to_state_province, ''), 'postal_code', coalesce(o.ship_to_postal_code, ''), 'country', coalesce(o.ship_to_country, '')),
           'lines', (select coalesce(jsonb_agg((jsonb_build_object('no', pl.no::text, 'upc', public.doc_upc(pl.sl_product_id), 'sku', coalesce(pl.sku, ''), 'description', coalesce(pl.description, ''), 'comment', coalesce(pl.sl_comments, ''),
                                                                    'unit', coalesce(pl.unit, ''), 'qty', public.doc_fmt_qty(pl.qty), 'list_price', public.doc_fmt_money(pl.list_price), 'discount_pct', public.doc_fmt_pct(pl.discount_pct),
                                                                    'amount', public.doc_fmt_money(pl.amount), 'tax_amount', public.doc_fmt_money(pl.tax_amount), 'is_free', pl.sl_free is not null, 'no_price', pl.unit_price is null)
                                                || public.doc_unit_prices(pl.unit_price, pl.o_od_pct, v_disp)) order by pl.no), '[]'::jsonb)
                     from pl where pl.invoice_order_id = o.id)) order by o.so_number), '[]'::jsonb),
         coalesce(sum(o.lines_amount), 0)
    into v_orders, v_lines_amt
  from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id;
  -- 운임 · 운임 할인 · 오더 할인 · 부가 요금 줄 → charges(오더 번호 · 계정 코드 · 그 줄의 오더) · 합은 줄에서
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'so_number', x.so_number, 'code', coalesce(x.account_code, ''), 'description', coalesce(x.description, ''), 'comment', coalesce(x.comment, ''),
                                               'qty', public.doc_fmt_qty(x.qty), 'unit_price', public.doc_fmt_money(x.unit_price), 'discount_pct', public.doc_fmt_pct(x.discount_pct),
                                               'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount)) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0), coalesce(sum(x.amount) filter (where x.kind = 'charge_discount'), 0)
    into v_charges, v_chg_amt, v_chg_tax, v_chd
  from (select l.kind, l.account_code, l.description, l.qty, l.unit_price, l.discount_pct, l.amount, l.tax_amount, o.so_number,
               case when l.kind = 'charge' then c.description end as comment,
               row_number() over (order by o.so_number, l.line_no) as no
        from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id left join public.so_charge c on c.id = l.so_charge_id
        where l.invoice_id = v_inv.id and l.kind <> 'product') x;
  select coalesce(sum(l.tax_amount), 0), coalesce(sum(l.qty), 0) into v_lines_tax, v_qty from public.so_invoice_line l where l.invoice_id = v_inv.id and l.kind = 'product';
  -- 결제 — 붙어 있는 활성 결제만(떼어진 것 · 취소된 것 거름) · 금액은 붙인 몫
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.reference, ''), 'date', public.doc_fmt_date(x.paid_on, v_fmt), 'method', public.doc_method_label(x.method), 'amount', public.doc_fmt_money(x.amount)) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0)
    into v_payments, v_paid
  from (select a.amount, p.reference, p.paid_on, p.method, row_number() over (order by p.paid_on, p.created_at, a.created_at) as no
        from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
        where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment') x;
  return jsonb_build_object(
    'invoice', jsonb_build_object('number', v_inv.invoice_number, 'date', public.doc_fmt_date(v_inv.issued_on, v_fmt), 'due_date', public.doc_fmt_date(v_inv.due_on, v_fmt), 'terms', coalesce(v_inv.payment_term_name, ''),
                                  'currency', coalesce(v_inv.currency_code, ''), 'memo', coalesce(v_inv.note, ''), 'total_qty', public.doc_fmt_qty(v_qty)),
    'orders', v_orders, 'charges', v_charges, 'payments', v_payments,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money(v_inv.order_discount_amount), 'surcharge', public.doc_fmt_money(v_inv.surcharge_amount), 'charges_discount', public.doc_fmt_money(v_chd),
                                 'before_tax', public.doc_fmt_money(v_inv.taxable_amount), 'tax', public.doc_fmt_money(v_inv.tax_amount), 'total', public.doc_fmt_money(v_inv.total),
                                 'deposit_applied', public.doc_fmt_money(v_inv.deposit_applied), 'credit_applied', public.doc_fmt_money(v_inv.credit_applied), 'balance_forward', public.doc_fmt_money(v_inv.balance_forward),
                                 'paid', public.doc_fmt_money(v_paid), 'due_label', case when v_inv.amount_due > 0 then 'Due' when v_inv.amount_due < 0 then 'Credit' else 'Paid' end, 'due_amount', public.doc_fmt_money(v_inv.amount_due)))
    || public.doc_data_common(p_kind, p_cfg, jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province,
                                                                'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country) || public.doc_contact(v_inv.bill_to_customer_id));
end;
$$;
revoke all on function public.doc_data_invoice(text, uuid, jsonb) from public, anon, authenticated;

-- 크레딧 노트 — so_credit 표 둘 · 주소는 원 인보이스의 굳은 값(없으면 — Cin7 원본 — 손님의 기본 주소 · 지금 값) · 환불은 refund 배분 · remaining = so_credit_remaining
create function public.doc_data_credit(p_credit_id uuid, p_cfg jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_cr   public.so_credit%rowtype;
  v_inv  public.so_invoice%rowtype;
  v_fmt  text := p_cfg->>'date_format';
  v_bill jsonb;  v_ship jsonb;  v_lines jsonb;  v_charges jsonb;  v_refunds jsonb;
  v_lines_amt numeric;  v_lines_tax numeric;  v_chg_amt numeric;  v_chg_tax numeric;  v_applied numeric;  v_ref text;
begin
  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if v_cr.id is null then raise exception 'Credit note not found'; end if;
  if v_cr.invoice_id is not null then
    select * into v_inv from public.so_invoice i where i.id = v_cr.invoice_id;
    v_bill := jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country);
    select jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country)
      into v_ship
    from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;                                                   -- 여러 오더면 첫 오더(so_number 순)의 배송지
    select string_agg(s.ref, ', ' order by o.so_number) into v_ref from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id and s.ref is not null and s.ref <> '';
  else
    select jsonb_build_object('name', c.name, 'line1', a.line1, 'line2', a.line2, 'city', a.city, 'state_province', a.state_province, 'postal_code', a.postal_code, 'country', a.country) into v_bill
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Billing' and a.is_default_for_type where c.id = v_cr.customer_id;
    select jsonb_build_object('company', c.name, 'contact', '', 'phone', '', 'line1', a.line1, 'line2', a.line2, 'city', a.city, 'state_province', a.state_province, 'postal_code', a.postal_code, 'country', a.country) into v_ship
    from public.customer c left join public.customer_address a on a.customer_id = c.id and a.is_active and a.type = 'Shipping' and a.is_default_for_type where c.id = v_cr.customer_id;
  end if;
  -- 제품 줄(콤보 구성품 줄은 뺀다 — 손님 문서 · amount 0) · 그 밖(freight · tax · other · surcharge · order_discount · freight_discount)은 charges · restocking_fee 는 totals
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(x.product_id), 'sku', coalesce(x.sku, ''), 'description', coalesce(x.description, ''), 'comment', '', 'unit', coalesce(x.unit, ''),
                                               'qty', public.doc_fmt_qty(x.qty_returned), 'list_price', '', 'discount_pct', '', 'unit_price', public.doc_fmt_money(x.unit_price), 'net_unit_price', '',
                                               'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount), 'is_free', false, 'no_price', false) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0)
    into v_lines, v_lines_amt, v_lines_tax
  from (select l.*, coalesce(sl.unit, p.uom_name) as unit, row_number() over (order by l.line_no) as no
        from public.so_credit_line l left join public.so_line sl on sl.id = l.so_line_id left join public.product p on p.id = l.product_id
        where l.credit_id = v_cr.id and l.kind = 'product' and l.combo_credit_line_id is null) x;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'so_number', '', 'code', coalesce(x.account_code, ''), 'description', coalesce(x.description, ''), 'comment', '', 'qty', public.doc_fmt_qty(x.qty_returned),
                                               'unit_price', public.doc_fmt_money(x.unit_price), 'discount_pct', '', 'amount', public.doc_fmt_money(x.amount), 'tax_amount', public.doc_fmt_money(x.tax_amount)) order by x.no), '[]'::jsonb),
         coalesce(sum(x.amount), 0), coalesce(sum(x.tax_amount), 0)
    into v_charges, v_chg_amt, v_chg_tax
  from (select l.*, row_number() over (order by l.line_no) as no from public.so_credit_line l where l.credit_id = v_cr.id and l.kind not in ('product', 'restocking_fee')) x;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.reference, ''), 'date', public.doc_fmt_date(x.paid_on, v_fmt), 'method', public.doc_method_label(x.method), 'amount', public.doc_fmt_money(x.amount)) order by x.no), '[]'::jsonb)
    into v_refunds
  from (select a.amount, p.reference, p.paid_on, p.method, row_number() over (order by p.paid_on, p.created_at, a.created_at) as no
        from public.so_credit_alloc a join public.so_payment p on p.id = a.refund_payment_id
        where a.credit_id = v_cr.id and a.refund_payment_id is not null and a.voided_at is null and p.status = 'active') x;
  select coalesce(sum(a.amount), 0) into v_applied from public.so_credit_alloc a where a.credit_id = v_cr.id and a.invoice_id is not null and a.voided_at is null;
  return jsonb_build_object(
    'credit', jsonb_build_object('number', v_cr.credit_number, 'date', public.doc_fmt_date(v_cr.issued_on, v_fmt), 'invoice_number', coalesce(v_inv.invoice_number, v_cr.cin7_invoice_number, ''),
                                 'reference', coalesce(v_ref, ''), 'reason', coalesce(v_cr.reason, ''), 'currency', coalesce(v_cr.currency_code, ''), 'memo', coalesce(v_cr.note, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_ship->>'company', ''), 'contact', coalesce(v_ship->>'contact', ''), 'phone', coalesce(v_ship->>'phone', ''), 'line1', coalesce(v_ship->>'line1', ''), 'line2', coalesce(v_ship->>'line2', ''),
                                  'city', coalesce(v_ship->>'city', ''), 'state_province', coalesce(v_ship->>'state_province', ''), 'postal_code', coalesce(v_ship->>'postal_code', ''), 'country', coalesce(v_ship->>'country', '')),
    'lines', v_lines, 'charges', v_charges, 'refunds', v_refunds,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money(v_lines_amt), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money(v_lines_amt + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'restocking_fee', public.doc_fmt_money(v_cr.fee_amount), 'before_tax', public.doc_fmt_money(v_cr.total - v_cr.tax_amount), 'tax', public.doc_fmt_money(v_cr.tax_amount), 'total', public.doc_fmt_money(v_cr.total),
                                 'applied', public.doc_fmt_money(v_applied), 'remaining', public.doc_fmt_money(public.so_credit_remaining(v_cr.id))))
    || public.doc_data_common('credit_note', p_cfg, coalesce(v_bill, '{}'::jsonb) || public.doc_contact(v_cr.customer_id));
end;
$$;
revoke all on function public.doc_data_credit(uuid, jsonb) from public, anon, authenticated;

-- SO — so_proforma(한 오더 · 주문 수량 · 그날 세율 · 선결제)의 숫자 + so_line 표지(가격 없음 · 무상 · 메모) · 열린 오더만(so_proforma 가 거부한다)
create function public.doc_data_so(p_so_id uuid, p_cfg jsonb) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_so   public.so%rowtype;
  v_pf   jsonb;  v_o jsonb;  v_t jsonb;
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_lines jsonb;  v_charges jsonb := '[]'::jsonb;  v_prepay jsonb;
  v_lines_tax numeric;  v_n int := 0;  v_x jsonb;  v_sc_code text := (select c.value from public.inv_config c where c.key = 'so_surcharge_account_code');
  v_chg_amt numeric;  v_chg_tax numeric;
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if v_so.id is null then raise exception 'Order not found'; end if;
  v_pf := public.so_proforma(array[p_so_id]);
  v_o := v_pf->'orders'->0;  v_t := v_pf->'totals';
  select coalesce(jsonb_agg((jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(sl.product_id), 'sku', coalesce(x.l->>'sku', ''), 'description', coalesce(x.l->>'product_name', ''), 'comment', coalesce(sl.comments, ''),
                                                'unit', coalesce(x.l->>'unit', ''), 'qty', public.doc_fmt_qty((x.l->>'qty')::numeric), 'list_price', public.doc_fmt_money((x.l->>'list_price')::numeric), 'discount_pct', public.doc_fmt_pct((x.l->>'discount_pct')::numeric),
                                                'amount', public.doc_fmt_money((x.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((x.l->>'tax')::numeric), 'is_free', sl.free_reason is not null, 'no_price', sl.unit_price is null)
                             || public.doc_unit_prices(sl.unit_price, v_so.order_discount_pct, v_disp)) order by x.no), '[]'::jsonb),
         coalesce(sum((x.l->>'tax')::numeric), 0)
    into v_lines, v_lines_tax
  from (select l, row_number() over (order by (l->>'line_no')::int) as no from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l) x
  left join public.so_line sl on sl.id = (x.l->>'line_id')::uuid;
  -- charges = 운임(정가) · 운임 할인(음수) · 오더 할인(음수) · 줄 부가 요금 — so_tax_preview 가 센 값 그대로 · 순서 운임 → 할인 → 오더 할인 → 부가 요금
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charges', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_x->>'account_code', ''), 'description', coalesce(v_x->>'name', ''), 'comment', coalesce(v_x->>'description', ''),
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charge_discounts', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce((select c.value from public.inv_config c where c.key = 'so_freight_discount_account_code'), ''), 'description', coalesce(v_x->>'name', ''), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  if coalesce((v_o->'order_discount'->>'amount')::numeric, 0) <> 0 then
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_so.sale_account_code, ''), 'description', format('Order discount %s%%', public.doc_fmt_qty((v_o->'order_discount'->>'pct')::numeric)), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', '', 'amount', public.doc_fmt_money((v_o->'order_discount'->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_o->'order_discount'->>'tax')::numeric));
  end if;
  for v_x in select l from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l where coalesce((l->>'surcharge_total')::numeric, 0) > 0 order by (l->>'line_no')::int loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_sc_code, ''), 'description', coalesce(nullif(v_x->>'surcharge_label', ''), 'Surcharge') || ' (' || (v_x->>'sku') || ')', 'comment', '',
                                                 'qty', public.doc_fmt_qty((v_x->>'qty')::numeric), 'unit_price', public.doc_fmt_money((v_x->>'surcharge_unit')::numeric), 'discount_pct', '',
                                                 'amount', public.doc_fmt_money((v_x->>'surcharge_total')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'surcharge_tax')::numeric));
  end loop;
  v_chg_amt := coalesce((v_t->>'charges_amount')::numeric, 0) - coalesce((v_t->>'charges_discount_amount')::numeric, 0) + coalesce((v_t->>'order_discount_amount')::numeric, 0) + coalesce((v_t->>'surcharge_amount')::numeric, 0);
  v_chg_tax := case when v_t->>'tax' is null then null else (v_t->>'tax')::numeric - v_lines_tax end;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.d->>'reference', ''), 'date', public.doc_fmt_date((x.d->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(x.d->>'method'), 'amount', public.doc_fmt_money((x.d->>'remaining')::numeric)) order by x.no), '[]'::jsonb)
    into v_prepay
  from (select d, row_number() over () as no from jsonb_array_elements(coalesce(v_pf->'deposits', '[]'::jsonb)) d) x;
  return jsonb_build_object(
    'so', jsonb_build_object('number', v_so.so_number, 'date', public.doc_fmt_date(v_so.order_date, v_fmt), 'status', v_so.status, 'required_by', public.doc_fmt_date(v_so.required_by, v_fmt), 'terms', coalesce(v_so.payment_term_name, ''),
                             'reference', coalesce(v_so.ref, ''), 'currency', coalesce(v_so.currency_code, ''), 'memo', coalesce(v_so.comments, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_so.ship_to_company, ''), 'contact', coalesce(v_so.ship_to_contact, ''), 'phone', coalesce(v_so.ship_to_phone, ''), 'line1', coalesce(v_so.ship_to_line1, ''), 'line2', coalesce(v_so.ship_to_line2, ''),
                                  'city', coalesce(v_so.ship_to_city, ''), 'state_province', coalesce(v_so.ship_to_state_province, ''), 'postal_code', coalesce(v_so.ship_to_postal_code, ''), 'country', coalesce(v_so.ship_to_country, '')),
    'lines', v_lines, 'charges', v_charges, 'prepayments', v_prepay,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money((v_t->>'lines_amount')::numeric), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money((v_t->>'lines_amount')::numeric + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount_amount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge_amount')::numeric), 'charges_discount', public.doc_fmt_money(-(v_t->>'charges_discount_amount')::numeric),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable_amount')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'prepaid', public.doc_fmt_money((v_t->>'received')::numeric), 'due_amount', public.doc_fmt_money((v_t->>'balance_due')::numeric)))
    || public.doc_data_common('sales_order', p_cfg, jsonb_build_object('name', v_so.bill_to_name, 'line1', v_so.bill_to_line1, 'line2', v_so.bill_to_line2, 'city', v_so.bill_to_city, 'state_province', v_so.bill_to_state_province,
                                                                        'postal_code', v_so.bill_to_postal_code, 'country', v_so.bill_to_country) || public.doc_contact(coalesce(v_so.bill_to_customer_id, v_so.customer_id)));
end;
$$;
revoke all on function public.doc_data_so(uuid, jsonb) from public, anon, authenticated;

create function public.doc_data(p_kind text, p_ref jsonb) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_cfg jsonb;
  v_id  uuid;
  v_doc jsonb;
begin
  perform public.doc_staff_or_service();                                                           -- ⭐ 문 — 첫 줄(활성 직원 · service_role)
  if p_kind = 'ship_ready' then raise exception 'Ship Ready data comes in the next version (doc-1b2)'; end if;
  if p_kind not in ('final_invoice', 'internal_receipt', 'credit_note', 'sales_order') then raise exception 'Unknown document kind % — final_invoice, internal_receipt, credit_note or sales_order', coalesce(p_kind, '(null)'); end if;
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then raise exception 'p_ref must be a JSON object like {"invoice_id": "…"}'; end if;
  v_cfg := public.doc_config();
  if p_kind in ('final_invoice', 'internal_receipt') then
    if nullif(p_ref->>'invoice_id', '') is null then raise exception 'p_ref needs invoice_id'; end if;
    v_doc := public.doc_data_invoice(p_kind, (p_ref->>'invoice_id')::uuid, v_cfg);
  elsif p_kind = 'credit_note' then
    if nullif(p_ref->>'credit_id', '') is null then raise exception 'p_ref needs credit_id'; end if;
    v_doc := public.doc_data_credit((p_ref->>'credit_id')::uuid, v_cfg);
  else
    if nullif(p_ref->>'so_id', '') is null then raise exception 'p_ref needs so_id'; end if;
    v_doc := public.doc_data_so((p_ref->>'so_id')::uuid, v_cfg);
  end if;
  return jsonb_build_object('kind', p_kind, 'docs', jsonb_build_array(v_doc));
end;
$$;
comment on function public.doc_data(text, jsonb) is 'doc-1b1 — 문서 데이터 창구: 판(Mustache)이 먹을 값을 doc_field_catalog(kind) 와 똑같은 열쇠로 · {kind, docs: [문서 하나]}(ship_ready 는 묶음 여럿이라 배열 · doc-1b2) · p_ref = {invoice_id} | {credit_id} | {so_id} · 값은 전부 글자 꼴(돈 1,234.56 · 수량 · % · 날짜 doc_date_format)과 JSON 불리언(is_free · no_price · show.*) · 빈 값은 "" · 문 = doc_staff_or_service · 없는 id 는 거부 · ship_ready 거부(doc-1b2) · 원천: final_invoice · internal_receipt = so_invoice 표 셋(굳은 값) + 지금 값(바코드 · 줄 메모 · 연락처 · 택배 · 송장 · 붙은 결제) · credit_note = so_credit 표 둘 + 원 인보이스 주소(없으면 손님 기본 주소) · sales_order = so_proforma(열린 오더만) + so_line 표지';
revoke all on function public.doc_data(text, jsonb) from public, anon;
grant execute on function public.doc_data(text, jsonb) to authenticated, service_role;

-- ═══ ④ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_k text; v_cat jsonb; v_doc jsonb;
begin
  if cardinality(public.ims_doc_config_keys()) <> 8 then v_bad := v_bad || ' keys'; end if;
  if (select count(*) from public.inv_config where key = any (public.ims_doc_config_keys())) <> 8 then v_bad := v_bad || ' config-seed'; end if;
  if (select count(*) from public.inv_config where key = any (public.ims_doc_config_keys()) and public.ims_doc_config_problem(key, value) is not null) <> 0 then v_bad := v_bad || ' config-values'; end if;
  if (select prosrc from pg_proc where oid = 'public.doc_config()'::regprocedure) !~ 'public_base_url' then v_bad := v_bad || ' doc_config-body'; end if;
  if public.doc_fmt_money(-1234.5) <> '-1,234.50' or public.doc_fmt_qty(2.50) <> '2.5' or public.doc_fmt_qty(3) <> '3' or public.doc_fmt_pct(0) <> '' or public.doc_fmt_pct(20) <> '20%' or public.doc_fmt_date('2026-10-16', 'DDMONYYYY') <> '16OCT2026' then v_bad := v_bad || ' fmt'; end if;
  if has_function_privilege('anon', 'public.doc_data(text, jsonb)', 'execute') or has_function_privilege('authenticated', 'public.doc_data_invoice(text, uuid, jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.doc_data_common(text, jsonb, jsonb)', 'execute') or not has_function_privilege('service_role', 'public.doc_data(text, jsonb)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM511', message = format('STOP - doc-1b1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
