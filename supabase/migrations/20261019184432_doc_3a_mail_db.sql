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
-- 20261019184432_doc_3a_mail_db.sql — doc-3a (2026-10-19 · 회사 PC · Fable · 문서 메일의 DB 쪽: PDF 첨부 자리 · 손님 자동 칸 · 인보이스 메모 · 보내는 주소 · 수동 보내기 · 자동 줄 세우기 · 읽기)
--   판정 526(인보이스 Notes = so_invoice.note · 쓰는 창구) · 529(손님마다 켜는 칸 · 기본 꺼짐 · 적재가 덮지 않는다) · 530(보내는 주소 info@ · 설정 키) · 메일 기계 §65(판정 493 ~ 518 · mail_outbox · 판정 498 받는 이 · 514 결과 모름)
--   ① customer.final_invoice_mail(기본 false) · customer_update 재발행(원본 20261016152757:92 바이트 + backorder_mail 과 같은 자리 다섯 · 판정 517 의 결) · 적재(ImsLoadCustomer.gs)는 고정 칸 목록이라 보내지 않는다
--   ② so_invoice_note_set · so_credit_note_set(sales 쓰기 · issued 만 · 2000 자) — doc_data 가 읽는 칸(so_invoice.note · so_credit.note)
--   ③ inv_config 키 셋 mail_doc_from · mail_doc_from_name · mail_doc_reply_to — ims_mail_config_keys · ims_mail_config_problem 재발행(원본 20261016123721:152 · :162 + 더한 줄) · inv_config_guard 의 메일 갈래가 그대로 지킨다(master · 삭제 · 이름 바꾸기 거부) · mail_settings 는 키 목록을 돌아 저절로 열 줄 · 백오더 키 무접촉
--   ④ mail_outbox.attachments jsonb(PDF 자체는 안 넣는다 — doc_file_id · filename · bytes · sha256 · path) · kind 넷 더함(doc_final_invoice · doc_credit_note · doc_sales_order · doc_ship_ready) · 상태 waiting_pdf(「PDF 기다림」 — mail_claim 은 queued 만 집으니 3b 전에는 안 보낸다)
--   ⑤ doc_mail_send(kind · ref · to · subject · body · commit · doc_file_id) — 미리 보기(498 받는 이 · 제목 · 본문을 doc_setting 글 + doc_data 로 채움 · 시험 DB 면 돌려 보낼 주소) · 실행 = mail_outbox 한 줄(waiting_pdf · ship_ready 는 직원이 만든 PDF 를 받아 queued)
--   ⑥ 자동(판정 529) — so_invoice AFTER INSERT 지연 제약 트리거(발행 트랜잭션 끝에 · so_invoice_issue 무접촉) · 청구처 칸이 켜져 있으면 ⑤ 와 같은 줄 · 받는 주소 없음 · 재발행(같은 오더의 앞 인보이스) · 오류는 doc_mail_skip 에 남기고 발행은 막지 않는다
--   ⑦ doc_mail_list(kind, ref) — 문서마다 보낸 메일 · 건너뛴 것 · doc_mail_cancel(waiting_pdf · queued 인 문서 메일만 · sales)
--   무접촉: so_invoice_issue · mail_claim · mail_mark · drain · EF · 화면 · 운영 DB · 첫 문장 = guard-test-only.sql 바이트 복사 · 검증 ~/asung/prompts/doc-3a-verify.sql + mail-* 검증 일곱 다시

-- ═══ ① 손님 칸 · customer_update 재발행 ═══
alter table public.customer add column final_invoice_mail boolean not null default false;
comment on column public.customer.final_invoice_mail is 'doc-3a 판정 529 — 「최종 인보이스 자동 메일」(기본 꺼짐 · 몇십 명 · 컷오버 전에 Customers 화면에서 손으로 켠다) · 켜져 있으면 발행 순간(so_invoice AFTER INSERT · 지연) 문서 메일 한 줄이 선다 · 바꾸기 = customer_update(값이 바뀔 때만 manager 이상 · 판정 517 의 결) · 손님 적재(ImsLoadCustomer)는 고정 칸 목록이라 보내지 않는다';
create or replace function public.customer_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_master   boolean;
  v_mgr_ok   boolean;                                                              -- mail-4a 판정 517: manager 이상인가
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_reviewed uuid[] := '{}';
  v_money    text[] := array['price_tier', 'discount_pct', 'payment_term_id', 'currency_id', 'ar_account_id', 'sale_account_id', 'default_bill_to_customer_id', 'invoice_split_by_store', 'is_active'];   -- 판정 241(cs-3): 켜기 · 끄기도 master 만 · 판정 254(cs-par-1): is_bill_parent 는 뺐다(받은 값을 비춰 둘 뿐 · 적재가 매번 덮는다)
  v_general  text[] := array['name', 'display_name', 'note', 'tax_rule', 'default_location_id', 'default_carrier', 'tax_number', 'tags', 'is_legal_entity', 'default_ship_to_customer_id'];   -- 판정 252(cs-par-1): parent_id 는 v_struct 로
  v_struct   text[] := array['parent_id'];   -- cs-par-1 판정 252(이견 5) — 문은 master(돈 칸과 같은 문) · 저장은 reviewed · open_so_keep_old 경고 없이(오더에 복사되는 조건이 아니다)
  v_mgr      text[] := array['backorder_mail', 'final_invoice_mail'];   -- mail-4a 판정 507 · 517: 백오더 알림 받기 — 값이 바뀔 때만 manager 이상(sales 는 보기만 · 판정 237 의 일반 칸 = sales 의 예외) · doc-3a 판정 529: 최종 인보이스 자동 메일도 같은 결
  v_afields  text[] := array['type', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country', 'label'];
  v_cfields  text[] := array['name', 'phone', 'mobile_phone', 'fax', 'email', 'website', 'job_title', 'include_in_email', 'marketing_consent'];
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_field    text;
  v_cid      uuid;
  v_key      text;
  v_cust     public.customer%rowtype;
  v_cur      text;
  v_new      text;
  v_num      numeric;
  v_seen     text[] := '{}';
  v_touched  uuid[] := '{}';
  v_money_ok uuid[] := '{}';
  v_addr_ch  uuid[] := '{}';
  v_tier     public.ref_price_tier%rowtype;
  v_term     public.ref_payment_term%rowtype;
  v_curr     public.ref_currency%rowtype;
  v_acct     public.ref_account%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_other    public.customer%rowtype;
  v_a        public.customer_address%rowtype;
  v_ct       public.customer_contact%rowtype;
  v_vals     jsonb;
  v_olds     jsonb;
  v_f        text;
  v_folded   text;
  v_n_act    int;
  v_n_off    int;
  v_matches  jsonb;
  v_open_so  int;
  v_open_inv int;
  v_inv_due  numeric;
  v_bal      numeric;
  v_kids     int;
  v_consent  text;
  v_keys     text[];
  v_unacked  text[];
  v_rid      uuid;
  v_newdef   text[] := '{}';   -- 이 호출이 새 기본을 세우는 자리 — <customer_id>:<type>(주소) · <customer_id>(연락처) — 그 자리의 옛 기본을 끄는 op 는 알리지 않는다
begin
  -- ⭐ 문(판정 237) — sales 또는 master 쓰기 · 문장은 ims_require_write 모양(2a 와 같다)
  if not (public.ims_can_write('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  v_mgr_ok := coalesce(public.ims_role_rank((select s.role from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active)), 0) >= public.ims_role_rank('manager');   -- mail-4a 판정 517
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then raise exception 'p_changes must be a JSON array of changes — nothing was saved'; end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 1000 then raise exception 'Too many changes in one call (% — the limit is 1,000) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_op := v_c->>'op';
    if v_op is null or v_op not in ('set', 'address_add', 'address_set', 'address_off', 'address_default', 'contact_add', 'contact_set', 'contact_off', 'contact_default') then
      raise exception 'Unknown op % — one of set · address_add · address_set · address_off · address_default · contact_add · contact_set · contact_off · contact_default — nothing was saved', coalesce(v_op, '(blank)');
    end if;
    if v_op = 'address_add' and coalesce((v_c->'values'->>'is_default_for_type')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '') || ':' || btrim(coalesce(v_c->'values'->>'type', ''))); end if;
    if v_op = 'address_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '') || ':' || coalesce((select a.type from public.customer_address a where a.id = nullif(v_c->>'address_id', '')::uuid), '')); end if;
    if v_op = 'contact_add' and coalesce((v_c->'values'->>'is_default')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '')); end if;
    if v_op = 'contact_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '')); end if;
  end loop;

  -- ② 검사 — 줄마다(현재 값은 지금 읽는다 · 저장은 ③에서 같은 순서로)
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_field := nullif(btrim(v_c->>'field'), '');
    v_cid := nullif(v_c->>'customer_id', '')::uuid;
    v_key := coalesce(v_cid::text, '(blank)');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'customer_id', v_cid, 'op', v_op, 'field', v_field, 'applied', false);
    select * into v_cust from public.customer c where c.id = v_cid;
    if v_cid is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':customer_unknown', 'customer_id', v_cid, 'code', 'customer_unknown', 'message', format('Change %s: the customer does not exist — nothing was saved', v_i));
      continue;
    end if;
    v_touched := array_append(v_touched, v_cid);

    -- ── set ──
    if v_op = 'set' then
      if v_field is null or not (v_field = any(v_general) or v_field = any(v_money) or v_field = any(v_struct) or v_field = any(v_mgr)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(blank)'), 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: field %s cannot be changed here — nothing was saved', v_cust.name, coalesce(v_field, '(blank)')));
        continue;
      end if;
      if (v_key || ':' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s %s is changed twice in this call — keep one — nothing was saved', v_cust.name, v_field));
        continue;
      end if;
      v_seen := array_append(v_seen, v_key || ':' || v_field);
      if (v_field = any(v_money) or v_field = any(v_struct)) and not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_field, 'customer_id', v_cid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change %s of %s — nothing was saved', v_field, v_cust.name));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s %s: the old value the screen saw is missing — nothing was saved', v_cust.name, v_field));
        continue;
      end if;
      v_cur := case v_field
        when 'name' then v_cust.name when 'display_name' then v_cust.display_name when 'note' then v_cust.note when 'tax_rule' then v_cust.tax_rule
        when 'default_location_id' then v_cust.default_location_id::text when 'default_carrier' then v_cust.default_carrier when 'tax_number' then v_cust.tax_number when 'tags' then v_cust.tags
        when 'is_legal_entity' then v_cust.is_legal_entity::text when 'parent_id' then v_cust.parent_id::text when 'default_ship_to_customer_id' then v_cust.default_ship_to_customer_id::text when 'is_active' then v_cust.is_active::text
        when 'price_tier' then v_cust.price_tier when 'discount_pct' then v_cust.discount_pct::text when 'payment_term_id' then v_cust.payment_term_id::text when 'currency_id' then v_cust.currency_id::text
        when 'ar_account_id' then v_cust.ar_account_id::text when 'sale_account_id' then v_cust.sale_account_id::text when 'default_bill_to_customer_id' then v_cust.default_bill_to_customer_id::text
        when 'invoice_split_by_store' then v_cust.invoice_split_by_store::text when 'backorder_mail' then v_cust.backorder_mail::text when 'final_invoice_mail' then v_cust.final_invoice_mail::text end;   -- doc-3a
      if (case when v_field = 'discount_pct' then (v_cur::numeric is distinct from nullif(v_c->>'old', '')::numeric)
               when v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store', 'backorder_mail', 'final_invoice_mail') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean)   -- doc-3a
               else (v_cur is distinct from nullif(v_c->>'old', '')) end) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of %s (now "%s") — check again — nothing was saved', v_field, v_cust.name, coalesce(v_cur, '')));
        continue;
      end if;
      v_new := nullif(btrim(v_c->>'value'), '');
      -- 값 검사(바꾸는 칸만 · 옛 값은 보지 않는다)
      if v_field = 'name' then
        if v_new is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'customer_id', v_cid, 'code', 'name_missing', 'message', format('%s cannot have an empty name — nothing was saved', v_cust.name));
        else
          v_folded := lower(regexp_replace(v_new, '\s+', ' ', 'g'));
          select count(*) filter (where c.is_active), count(*) filter (where not c.is_active),
                 coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'is_active', c.is_active) order by c.is_active desc, c.created_at) filter (where c.rn <= 5), '[]'::jsonb)
            into v_n_act, v_n_off, v_matches
            from (select c0.*, row_number() over (order by c0.is_active desc, c0.created_at) as rn from public.customer c0 where c0.id <> v_cid and lower(regexp_replace(btrim(c0.name), '\s+', ' ', 'g')) = v_folded) c;
          if v_n_act > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':name_exists', 'customer_id', v_cid, 'code', 'name_exists', 'matches', v_matches, 'message', format('%s active customer(s) already have the name "%s" — is this really the same name? Confirm to rename anyway', v_n_act, v_new));
          elsif v_n_off > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':name_matches_inactive', 'customer_id', v_cid, 'code', 'name_matches_inactive', 'matches', v_matches, 'message', format('%s inactive customer(s) have the name "%s" — confirm to rename anyway', v_n_off, v_new));
          end if;
        end if;
      elsif v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store', 'backorder_mail', 'final_invoice_mail') then   -- doc-3a
        if v_new is null or v_new not in ('true', 'false') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_field, 'customer_id', v_cid, 'code', 'value_invalid', 'message', format('%s %s must be true or false — nothing was saved', v_cust.name, v_field));
        elsif v_field = 'is_active' and v_new = 'false' then
          -- 끄기 — 알리기 넷(판정 B-4) · so_create 가 새 오더를 막는 것은 기존 동작
          select count(*) into v_open_so from public.so s where s.customer_id = v_cid and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed');
          select count(*), coalesce(sum(public.so_invoice_remaining(i.id)), 0) into v_open_inv, v_inv_due from public.so_invoice i where i.bill_to_customer_id = v_cid and i.status = 'issued' and public.so_invoice_remaining(i.id) > 0;
          select coalesce(sum(b.available), 0) + coalesce(sum(b.owed_credit), 0) into v_bal from public.so_customer_balance(v_cid) b;
          select count(*) into v_kids from public.customer k where k.is_active and k.id <> v_cid and (k.parent_id = v_cid or k.default_ship_to_customer_id = v_cid or k.default_bill_to_customer_id = v_cid);
          if v_open_so > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_so', 'customer_id', v_cid, 'code', 'inactive_open_so', 'count', v_open_so, 'message', format('%s has %s open order(s) — they keep running; new orders will be refused once the customer is inactive. Confirm to deactivate', v_cust.name, v_open_so)); end if;
          if v_open_inv > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_invoice', 'customer_id', v_cid, 'code', 'inactive_open_invoice', 'count', v_open_inv, 'amount', v_inv_due, 'message', format('%s has %s unpaid invoice(s) (%s due) — confirm to deactivate', v_cust.name, v_open_inv, v_inv_due)); end if;
          if v_bal <> 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_balance', 'customer_id', v_cid, 'code', 'inactive_balance', 'amount', v_bal, 'message', format('%s has a balance (available + credit = %s) — confirm to deactivate', v_cust.name, v_bal)); end if;
          if v_kids > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_children', 'customer_id', v_cid, 'code', 'inactive_children', 'count', v_kids, 'message', format('%s active customer(s) point at %s as parent, ship-to or bill-to — confirm to deactivate', v_kids, v_cust.name)); end if;
        elsif v_field = 'is_active' and v_new = 'true' then
          v_folded := lower(regexp_replace(btrim(v_cust.name), '\s+', ' ', 'g'));
          select count(*), coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.created_at), '[]'::jsonb) into v_n_act, v_matches
            from public.customer c where c.id <> v_cid and c.is_active and lower(regexp_replace(btrim(c.name), '\s+', ' ', 'g')) = v_folded;
          if v_n_act > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':name_exists', 'customer_id', v_cid, 'code', 'name_exists', 'matches', v_matches, 'message', format('%s active customer(s) already have the name "%s" — confirm to reactivate anyway', v_n_act, v_cust.name)); end if;
        end if;
      elsif v_field = 'discount_pct' then
        if v_new is null or v_new !~ '^[0-9]+(\.[0-9]+)?$' or v_new::numeric > 100 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid', 'customer_id', v_cid, 'code', 'discount_invalid', 'message', format('%s: discount_pct must be a number from 0 to 100 (got %s) — nothing was saved', v_cust.name, coalesce(v_new, '(blank)')));
        end if;
      elsif v_field = 'price_tier' then
        select * into v_tier from public.ref_price_tier t where t.name = v_new and t.is_active and t.purpose = 'sale';
        if v_new is null or not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_invalid', 'customer_id', v_cid, 'code', 'tier_invalid', 'message', format('%s: price tier %s does not exist, is inactive or is not a sale tier — nothing was saved', v_cust.name, coalesce(v_new, '(blank)')));
        elsif v_cust.currency_id is not null and v_tier.currency_id <> v_cust.currency_id then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':tier_currency_mismatch', 'customer_id', v_cid, 'code', 'tier_currency_mismatch', 'message', format('Price tier %s is not in the currency of %s (%s) — order prices will not match', v_tier.name, v_cust.name, v_cust.currency_code));
        end if;
      elsif v_field = 'payment_term_id' then
        select * into v_term from public.ref_payment_term t where t.id = v_new::uuid and t.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':payment_term_invalid', 'customer_id', v_cid, 'code', 'payment_term_invalid', 'message', format('%s: the payment term does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field = 'currency_id' then
        select * into v_curr from public.ref_currency r where r.id = v_new::uuid and r.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_invalid', 'customer_id', v_cid, 'code', 'currency_invalid', 'message', format('%s: the currency does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field in ('ar_account_id', 'sale_account_id') then
        select * into v_acct from public.ref_account a where a.id = v_new::uuid and a.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || replace(v_field, '_id', '_invalid'), 'customer_id', v_cid, 'code', replace(v_field, '_id', '_invalid'), 'message', format('%s: the account does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field = 'default_location_id' then
        if v_new is not null and not exists (select 1 from public.ref_warehouse w where w.id = v_new::uuid and w.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_unknown', 'customer_id', v_cid, 'code', 'warehouse_unknown', 'message', format('%s: the default warehouse does not exist or is inactive — nothing was saved', v_cust.name));
        end if;
      elsif v_field = 'parent_id' then
        if v_new is not null then
          select * into v_other from public.customer c where c.id = v_new::uuid and c.is_active;
          if v_new::uuid = v_cid then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_self', 'customer_id', v_cid, 'code', 'parent_self', 'message', format('%s cannot be its own parent — nothing was saved', v_cust.name));
          elsif not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'customer_id', v_cid, 'code', 'parent_unknown', 'message', format('%s: the parent customer does not exist or is inactive — nothing was saved', v_cust.name));
          elsif v_other.parent_id is not null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_has_parent', 'customer_id', v_cid, 'code', 'parent_has_parent', 'message', format('%s already has a parent — a customer tree is one level deep — nothing was saved', v_other.name));
          elsif exists (select 1 from public.customer k where k.parent_id = v_cid) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_has_parent', 'customer_id', v_cid, 'code', 'parent_has_parent', 'message', format('%s has children of its own — a customer tree is one level deep — nothing was saved', v_cust.name)); end if;
        end if;
        -- cs-par-1 규칙 4(이견 3 · 7) — 부모를 비우거나 바꿀 때: 같은 호출이 그 옛 부모를 청구처로 다시 보내면 막는다 · 청구처가 옛 부모인데 이 호출이 청구처를 안 바꾸면 트리거(customer_parent_guard)가 null 로 돌린다고 알린다(ack)
        if v_cust.parent_id is not null and v_new is distinct from v_cust.parent_id::text then
          if exists (select 1 from jsonb_array_elements(p_changes) z where z->>'op' = 'set' and nullif(btrim(z->>'field'), '') = 'default_bill_to_customer_id' and nullif(z->>'customer_id', '')::uuid = v_cid and nullif(btrim(z->>'value'), '') = v_cust.parent_id::text) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':bill_to_is_old_parent', 'customer_id', v_cid, 'code', 'bill_to_is_old_parent', 'message', format('%s: the bill-to customer in this call is the parent being removed — pick another bill-to or leave it blank — nothing was saved', v_cust.name));
          elsif v_cust.default_bill_to_customer_id = v_cust.parent_id and not exists (select 1 from jsonb_array_elements(p_changes) z where z->>'op' = 'set' and nullif(btrim(z->>'field'), '') = 'default_bill_to_customer_id' and nullif(z->>'customer_id', '')::uuid = v_cid) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':bill_to_reset_with_parent', 'customer_id', v_cid, 'code', 'bill_to_reset_with_parent', 'message', format('%s is billed to its parent — removing or changing the parent resets the bill-to to the customer itself. Confirm', v_cust.name));
          end if;
        end if;
      elsif v_field in ('default_ship_to_customer_id', 'default_bill_to_customer_id') then
        -- cs-par-1 규칙 2(이견 6 · 판정 255) — 자기 자신은 null 하나로 표기한다 · 보내면 막는다(CHECK customer_bill_to_not_self_ck · customer_ship_to_not_self_ck 가 모든 길에서 같은 것을 막는다)
        if v_new is not null and v_new::uuid = v_cid then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || case when v_field = 'default_ship_to_customer_id' then 'ship_to_self' else 'bill_to_self' end, 'customer_id', v_cid, 'code', case when v_field = 'default_ship_to_customer_id' then 'ship_to_self' else 'bill_to_self' end, 'message', format('%s cannot be its own %s customer — leave it blank (blank means the customer itself) — nothing was saved', v_cust.name, case when v_field = 'default_ship_to_customer_id' then 'ship-to' else 'bill-to' end));
        end if;
        if v_new is not null and not exists (select 1 from public.customer c where c.id = v_new::uuid and c.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || case when v_field = 'default_ship_to_customer_id' then 'ship_to_unknown' else 'bill_to_unknown' end, 'customer_id', v_cid, 'code', case when v_field = 'default_ship_to_customer_id' then 'ship_to_unknown' else 'bill_to_unknown' end, 'message', format('%s: that customer does not exist or is inactive — nothing was saved', v_cust.name));
        end if;
      end if;
      if v_field in ('backorder_mail', 'final_invoice_mail') and not v_mgr_ok and v_new is distinct from v_cur then   -- doc-3a 판정 529: 같은 결   -- mail-4a 판정 517: 값이 바뀔 때만(같은 값이 실려 와도 막지 않는다)
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':manager_needed:' || v_field, 'customer_id', v_cid, 'code', 'manager_needed', 'message', format('Only a manager or above can turn backorder alerts %s for %s — nothing was saved', case when v_new = 'true' then 'on' else 'off' end, v_cust.name));
      end if;
      if v_field = any(v_money) then v_money_ok := array_append(v_money_ok, v_cid); end if;

    -- ── 주소 op ──
    elsif v_op like 'address_%' then
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      v_olds := coalesce(v_c->'olds', '{}'::jsonb);
      if v_op = 'address_add' then
        v_f := nullif(btrim(v_vals->>'type'), '');
        if v_f is null or v_f not in ('Billing', 'Business', 'Shipping') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_type_invalid:' || v_i, 'customer_id', v_cid, 'code', 'address_type_invalid', 'message', format('%s: address type must be Billing, Business or Shipping (got %s) — nothing was saved', v_cust.name, coalesce(v_f, '(blank)')));
        end if;
        if nullif(btrim(coalesce(v_vals->>'line1', '') || coalesce(v_vals->>'city', '') || coalesce(v_vals->>'postal_code', '')), '') is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_empty:' || v_i, 'customer_id', v_cid, 'code', 'address_empty', 'message', format('%s: the new address has no street, city or postal code — nothing was saved', v_cust.name));
        end if;
      else
        select * into v_a from public.customer_address a where a.id = nullif(v_c->>'address_id', '')::uuid and a.customer_id = v_cid;
        if not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_unknown:' || v_i, 'customer_id', v_cid, 'code', 'address_unknown', 'message', format('%s: that address is not on this customer — nothing was saved', v_cust.name));
          continue;
        end if;
        if (v_key || ':address:' || v_a.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:address:' || v_a.id::text, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same address is changed twice in this call — nothing was saved', v_cust.name));
          continue;
        end if;
        v_seen := array_append(v_seen, v_key || ':address:' || v_a.id::text);
        if v_op = 'address_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_afields)) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:address.' || v_f, 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: address field %s cannot be changed here — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            if not (v_olds ? v_f) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:address.' || v_f, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s: address %s — the old value the screen saw is missing — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            v_cur := case v_f when 'type' then v_a.type when 'line1' then v_a.line1 when 'line2' then v_a.line2 when 'city' then v_a.city when 'state_province' then v_a.state_province when 'postal_code' then v_a.postal_code when 'country' then v_a.country else v_a.label end;
            if v_cur is distinct from nullif(v_olds->>v_f, '') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:address.' || v_f, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the address %s of %s (now "%s") — check again — nothing was saved', v_f, v_cust.name, coalesce(v_cur, '')));
            end if;
            if v_f = 'type' and nullif(btrim(v_vals->>'type'), '') not in ('Billing', 'Business', 'Shipping') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_type_invalid:' || v_i, 'customer_id', v_cid, 'code', 'address_type_invalid', 'message', format('%s: address type must be Billing, Business or Shipping — nothing was saved', v_cust.name));
            end if;
          end loop;
        elsif v_op = 'address_off' then
          if not v_a.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'customer_id', v_cid, 'code', 'address_inactive', 'message', format('%s: that address is already off — nothing was saved', v_cust.name));
          elsif v_a.is_default_for_type and not ((v_key || ':' || v_a.type) = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':address_default_off:' || v_a.type, 'customer_id', v_cid, 'code', 'address_default_off', 'message', format('%s: this is the default %s address — switching it off leaves no default %s address (orders will warn). Confirm', v_cust.name, v_a.type, v_a.type)); end if;
        elsif v_op = 'address_default' then
          if not v_a.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'customer_id', v_cid, 'code', 'address_inactive', 'message', format('%s: an inactive address cannot be the default — switch it on first — nothing was saved', v_cust.name)); end if;
        end if;
      end if;
      v_addr_ch := array_append(v_addr_ch, v_cid);

    -- ── 연락처 op ──
    else
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      v_olds := coalesce(v_c->'olds', '{}'::jsonb);
      if v_op = 'contact_add' then
        if nullif(btrim(coalesce(v_vals->>'name', '') || coalesce(v_vals->>'phone', '') || coalesce(v_vals->>'mobile_phone', '') || coalesce(v_vals->>'email', '')), '') is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_empty:' || v_i, 'customer_id', v_cid, 'code', 'contact_empty', 'message', format('%s: the new contact has no name, phone or email — nothing was saved', v_cust.name));
        end if;
        v_consent := nullif(btrim(v_vals->>'marketing_consent'), '');
        if v_consent is not null and v_consent not in ('0', '1', '2', '3') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':consent_invalid:' || v_i, 'customer_id', v_cid, 'code', 'consent_invalid', 'message', format('%s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — got %s — nothing was saved', v_cust.name, v_consent));
        end if;
      else
        select * into v_ct from public.customer_contact k where k.id = nullif(v_c->>'contact_id', '')::uuid and k.customer_id = v_cid;
        if not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_unknown:' || v_i, 'customer_id', v_cid, 'code', 'contact_unknown', 'message', format('%s: that contact is not on this customer — nothing was saved', v_cust.name));
          continue;
        end if;
        if (v_key || ':contact:' || v_ct.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:contact:' || v_ct.id::text, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same contact is changed twice in this call — nothing was saved', v_cust.name));
          continue;
        end if;
        v_seen := array_append(v_seen, v_key || ':contact:' || v_ct.id::text);
        if v_op = 'contact_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_cfields)) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:contact.' || v_f, 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: contact field %s cannot be changed here — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            if not (v_olds ? v_f) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:contact.' || v_f, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s: contact %s — the old value the screen saw is missing — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            v_cur := case v_f when 'name' then v_ct.name when 'phone' then v_ct.phone when 'mobile_phone' then v_ct.mobile_phone when 'fax' then v_ct.fax when 'email' then v_ct.email when 'website' then v_ct.website when 'job_title' then v_ct.job_title
                              when 'include_in_email' then v_ct.include_in_email::text else case v_ct.marketing_consent when true then '2' when false then '3' else null end end;
            if (case when v_f = 'include_in_email' then (v_cur::boolean is distinct from nullif(v_olds->>v_f, '')::boolean)
                     when v_f = 'marketing_consent' then (v_cur is distinct from (case nullif(v_olds->>v_f, '') when '2' then '2' when '3' then '3' else null end))
                     else (v_cur is distinct from nullif(v_olds->>v_f, '')) end) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:contact.' || v_f, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the contact %s of %s (now "%s") — check again — nothing was saved', v_f, v_cust.name, coalesce(v_cur, '')));
            end if;
            if v_f = 'marketing_consent' and nullif(btrim(v_vals->>v_f), '') is not null and nullif(btrim(v_vals->>v_f), '') not in ('0', '1', '2', '3') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':consent_invalid:' || v_i, 'customer_id', v_cid, 'code', 'consent_invalid', 'message', format('%s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — nothing was saved', v_cust.name));
            end if;
          end loop;
        elsif v_op = 'contact_off' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'customer_id', v_cid, 'code', 'contact_inactive', 'message', format('%s: that contact is already off — nothing was saved', v_cust.name));
          elsif v_ct.is_default and not (v_key = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':contact_default_off', 'customer_id', v_cid, 'code', 'contact_default_off', 'message', format('%s: this is the default contact — switching it off leaves no default contact. Confirm', v_cust.name)); end if;
        elsif v_op = 'contact_default' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'customer_id', v_cid, 'code', 'contact_inactive', 'message', format('%s: an inactive contact cannot be the default — switch it on first — nothing was saved', v_cust.name)); end if;
        end if;
      end if;
    end if;
  end loop;

  -- 열린 오더 알리기 — 돈 칸 · 주소를 바꾸는 손님마다(열린 SO 는 복사해 굳힌 값 그대로 · master-cs-0 §C)
  for v_cid in select distinct u from unnest(v_money_ok || v_addr_ch) as u loop
    select count(*), max(c.name) into v_open_so, v_cur from public.so s join public.customer c on c.id = s.customer_id where s.customer_id = v_cid and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed');
    if v_open_so > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_cid::text || ':open_so_keep_old', 'customer_id', v_cid, 'code', 'open_so_keep_old', 'count', v_open_so, 'message', format('%s has %s open order(s) — they keep the old terms and addresses; only new orders get the change. Confirm', v_cur, v_open_so));
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns, 'reviewed_now', '[]'::jsonb,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 줄 순서대로 · 손님 행 잠금 · 한 트랜잭션 · 23505 는 문장으로
  begin
    perform 1 from public.customer c where c.id = any(v_touched) for update;
    v_i := 0;
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_cid := (v_c->>'customer_id')::uuid;
      v_new := nullif(btrim(v_c->>'value'), '');
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      if v_op = 'set' then
        case v_field
          when 'name' then update public.customer set name = v_new, updated_by = v_staff where id = v_cid;
          when 'display_name' then update public.customer set display_name = v_new, updated_by = v_staff where id = v_cid;
          when 'note' then update public.customer set note = v_new, updated_by = v_staff where id = v_cid;
          when 'tax_rule' then update public.customer set tax_rule = v_new, updated_by = v_staff where id = v_cid;
          when 'default_location_id' then update public.customer set default_location_id = v_new::uuid, default_location_name = (select w.name from public.ref_warehouse w where w.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'default_carrier' then update public.customer set default_carrier = v_new, updated_by = v_staff where id = v_cid;
          when 'tax_number' then update public.customer set tax_number = v_new, updated_by = v_staff where id = v_cid;
          when 'tags' then update public.customer set tags = v_new, updated_by = v_staff where id = v_cid;
          when 'is_legal_entity' then update public.customer set is_legal_entity = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'parent_id' then update public.customer set parent_id = v_new::uuid, parent_source = case when v_new is null then null else 'ims' end, updated_by = v_staff where id = v_cid;   -- 판정 253(cs-par-1): 창구가 세우거나 바꾸면 ims · 비우면 null
          when 'default_ship_to_customer_id' then update public.customer set default_ship_to_customer_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'is_active' then update public.customer set is_active = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'price_tier' then update public.customer set price_tier = v_new, updated_by = v_staff where id = v_cid;
          when 'discount_pct' then update public.customer set discount_pct = v_new::numeric, updated_by = v_staff where id = v_cid;
          when 'payment_term_id' then update public.customer set payment_term_id = v_new::uuid, payment_term_name = (select t.name from public.ref_payment_term t where t.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'currency_id' then update public.customer set currency_id = v_new::uuid, currency_code = (select r.code from public.ref_currency r where r.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'ar_account_id' then update public.customer set ar_account_id = v_new::uuid, ar_account_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'sale_account_id' then update public.customer set sale_account_id = v_new::uuid, sale_account_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'default_bill_to_customer_id' then update public.customer set default_bill_to_customer_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'invoice_split_by_store' then update public.customer set invoice_split_by_store = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'backorder_mail' then update public.customer set backorder_mail = v_new::boolean, updated_by = v_staff where id = v_cid;   -- mail-4a 판정 507 · 517(누가 · 언제 = updated_by · updated_at — 다른 칸과 같다)
          when 'final_invoice_mail' then update public.customer set final_invoice_mail = v_new::boolean, updated_by = v_staff where id = v_cid;   -- doc-3a 판정 529(같은 결)
        end case;
        -- 판정 240 — 돈 칸을 master 가 바꾸면 확인 · 처음 확인만 남긴다
        if v_field = any(v_money) then
          update public.customer set reviewed_by = v_staff, reviewed_at = now() where id = v_cid and reviewed_at is null returning id into v_rid;
          if v_rid is not null then v_reviewed := array_append(v_reviewed, v_rid); v_rid := null; end if;
        end if;
      elsif v_op = 'address_add' then
        v_f := btrim(v_vals->>'type');
        if coalesce((v_vals->>'is_default_for_type')::boolean, false) then
          update public.customer_address set is_default_for_type = false, updated_by = v_staff where customer_id = v_cid and type = v_f and is_default_for_type;
        end if;
        insert into public.customer_address (customer_id, source, updated_by, type, is_default_for_type, label, line1, line2, city, state_province, postal_code, country)
        values (v_cid, 'manual', v_staff, v_f, coalesce((v_vals->>'is_default_for_type')::boolean, false), nullif(btrim(v_vals->>'label'), ''), nullif(btrim(v_vals->>'line1'), ''), nullif(btrim(v_vals->>'line2'), ''),
                nullif(btrim(v_vals->>'city'), ''), nullif(btrim(v_vals->>'state_province'), ''), nullif(btrim(v_vals->>'postal_code'), ''), nullif(btrim(v_vals->>'country'), ''))
        returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'address_set' then
        update public.customer_address a set
          type = case when v_vals ? 'type' then btrim(v_vals->>'type') else a.type end,
          line1 = case when v_vals ? 'line1' then nullif(btrim(v_vals->>'line1'), '') else a.line1 end,
          line2 = case when v_vals ? 'line2' then nullif(btrim(v_vals->>'line2'), '') else a.line2 end,
          city = case when v_vals ? 'city' then nullif(btrim(v_vals->>'city'), '') else a.city end,
          state_province = case when v_vals ? 'state_province' then nullif(btrim(v_vals->>'state_province'), '') else a.state_province end,
          postal_code = case when v_vals ? 'postal_code' then nullif(btrim(v_vals->>'postal_code'), '') else a.postal_code end,
          country = case when v_vals ? 'country' then nullif(btrim(v_vals->>'country'), '') else a.country end,
          label = case when v_vals ? 'label' then nullif(btrim(v_vals->>'label'), '') else a.label end,
          updated_by = v_staff
        where a.id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_off' then
        update public.customer_address set is_active = false, is_default_for_type = false, updated_by = v_staff where id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_default' then
        select * into v_a from public.customer_address a where a.id = (v_c->>'address_id')::uuid;
        update public.customer_address a set is_default_for_type = (a.id = v_a.id), updated_by = v_staff where a.customer_id = v_cid and a.type = v_a.type and a.is_active and (a.is_default_for_type or a.id = v_a.id);
      elsif v_op = 'contact_add' then
        v_consent := nullif(btrim(v_vals->>'marketing_consent'), '');
        if coalesce((v_vals->>'is_default')::boolean, false) then
          update public.customer_contact set is_default = false, updated_by = v_staff where customer_id = v_cid and is_default;
        end if;
        insert into public.customer_contact (customer_id, source, updated_by, name, phone, mobile_phone, fax, email, website, job_title, include_in_email, marketing_consent, is_default)
        values (v_cid, 'manual', v_staff, nullif(btrim(v_vals->>'name'), ''), nullif(btrim(v_vals->>'phone'), ''), nullif(btrim(v_vals->>'mobile_phone'), ''), nullif(btrim(v_vals->>'fax'), ''), nullif(btrim(v_vals->>'email'), ''),
                nullif(btrim(v_vals->>'website'), ''), nullif(btrim(v_vals->>'job_title'), ''), coalesce((v_vals->>'include_in_email')::boolean, false),
                case v_consent when '2' then true when '3' then false else null end, coalesce((v_vals->>'is_default')::boolean, false))
        returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'contact_set' then
        update public.customer_contact k set
          name = case when v_vals ? 'name' then nullif(btrim(v_vals->>'name'), '') else k.name end,
          phone = case when v_vals ? 'phone' then nullif(btrim(v_vals->>'phone'), '') else k.phone end,
          mobile_phone = case when v_vals ? 'mobile_phone' then nullif(btrim(v_vals->>'mobile_phone'), '') else k.mobile_phone end,
          fax = case when v_vals ? 'fax' then nullif(btrim(v_vals->>'fax'), '') else k.fax end,
          email = case when v_vals ? 'email' then nullif(btrim(v_vals->>'email'), '') else k.email end,
          website = case when v_vals ? 'website' then nullif(btrim(v_vals->>'website'), '') else k.website end,
          job_title = case when v_vals ? 'job_title' then nullif(btrim(v_vals->>'job_title'), '') else k.job_title end,
          include_in_email = case when v_vals ? 'include_in_email' then coalesce((v_vals->>'include_in_email')::boolean, false) else k.include_in_email end,
          marketing_consent = case when v_vals ? 'marketing_consent' then (case nullif(btrim(v_vals->>'marketing_consent'), '') when '2' then true when '3' then false else null end) else k.marketing_consent end,
          updated_by = v_staff
        where k.id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_off' then
        update public.customer_contact set is_active = false, is_default = false, updated_by = v_staff where id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_default' then
        update public.customer_contact k set is_default = (k.id = (v_c->>'contact_id')::uuid), updated_by = v_staff where k.customer_id = v_cid and k.is_active and (k.is_default or k.id = (v_c->>'contact_id')::uuid);
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'Two defaults would remain for one customer (%) — set one default per address type and one default contact — nothing was saved', coalesce(sqlerrm, '');
  end;

  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'reviewed_now', to_jsonb(v_reviewed));
end;
$$;


-- ═══ ② 메모 창구 — doc_data 가 읽는 칸(판정 526) ═══
create function public.so_invoice_note_set(p_invoice_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_i public.so_invoice%rowtype; v_staff uuid;
begin
  perform public.ims_require_write('sales', 'saved');                                         -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  select * into v_i from public.so_invoice i where i.id = p_invoice_id for update;
  if v_i.id is null then raise exception 'Invoice not found — nothing was saved'; end if;
  if v_i.status <> 'issued' then raise exception 'Invoice % is % — the note of a cancelled invoice cannot be changed — nothing was saved', v_i.invoice_number, v_i.status; end if;
  if length(coalesce(p_note, '')) > 2000 then raise exception 'The invoice note must be at most 2000 characters — nothing was saved'; end if;
  update public.so_invoice set note = nullif(btrim(p_note), ''), updated_by = v_staff where id = v_i.id returning * into v_i;
  return jsonb_build_object('invoice_id', v_i.id, 'invoice_number', v_i.invoice_number, 'note', coalesce(v_i.note, ''), 'updated_at', v_i.updated_at, 'updated_by', v_i.updated_by);
end;
$$;
comment on function public.so_invoice_note_set(uuid, text) is 'doc-3a 판정 526 — 인보이스 메모(so_invoice.note · 종이의 Notes · doc_data invoice.memo)를 쓴다 · sales 쓰기 · issued 만 · 2000 자 · 빈 글은 null · 누가 · 언제 = updated_by · updated_at(so_invoice_touch)';
revoke all on function public.so_invoice_note_set(uuid, text) from public, anon;
grant execute on function public.so_invoice_note_set(uuid, text) to authenticated;

create function public.so_credit_note_set(p_credit_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.so_credit%rowtype; v_staff uuid;
begin
  perform public.ims_require_write('sales', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  select * into v_c from public.so_credit c where c.id = p_credit_id for update;
  if v_c.id is null then raise exception 'Credit note not found — nothing was saved'; end if;
  if v_c.status <> 'issued' then raise exception 'Credit note % is % — the memo of a cancelled credit note cannot be changed — nothing was saved', v_c.credit_number, v_c.status; end if;
  if length(coalesce(p_note, '')) > 2000 then raise exception 'The credit note memo must be at most 2000 characters — nothing was saved'; end if;
  update public.so_credit set note = nullif(btrim(p_note), ''), updated_by = v_staff where id = v_c.id returning * into v_c;
  return jsonb_build_object('credit_id', v_c.id, 'credit_number', v_c.credit_number, 'note', coalesce(v_c.note, ''), 'updated_at', v_c.updated_at, 'updated_by', v_c.updated_by);
end;
$$;
comment on function public.so_credit_note_set(uuid, text) is 'doc-3a — 크레딧 노트 메모(so_credit.note · doc_data credit.memo)를 쓴다 · sales 쓰기 · issued 만 · 2000 자(발행 때 넣은 메모를 뒤에 고치는 길 — 인보이스 메모와 같은 결)';
revoke all on function public.so_credit_note_set(uuid, text) from public, anon;
grant execute on function public.so_credit_note_set(uuid, text) to authenticated;

-- ═══ ③ 보내는 주소 키 셋(판정 530) — 메일 키 목록 · 검사 재발행 · 시드 ═══
create or replace function public.ims_mail_config_keys() returns text[]
  language sql immutable
  set search_path = public, pg_temp
as $$
  select array['mail_enabled', 'mail_redirect_to', 'mail_backorder_from', 'mail_backorder_reply_to', 'mail_backorder_from_name', 'mail_backorder_schedule', 'mail_backorder_min_fill_pct', 'mail_doc_from', 'mail_doc_from_name', 'mail_doc_reply_to'];   -- doc-3a 판정 530: 문서 메일 보내는 주소 셋
$$;

create or replace function public.ims_mail_config_problem(p_key text, p_value text, p_delete boolean default false) returns text
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_test boolean := coalesce((select c.value = 'test' from public.inv_config c where c.key = 'db_role'), false);
  v_j    jsonb;
  v_wh   text;
  v_e    jsonb;
begin
  -- 시험 DB 엮인 규칙(이견 11) — 켜진 동안 돌려 보낼 주소를 지우지 못한다
  if p_delete then
    if p_key = 'mail_redirect_to' and v_test and (select c.value from public.inv_config c where c.key = 'mail_enabled') = 'on' then
      return 'cannot be removed while mail_enabled is on in the test database — turn mail_enabled off first';
    end if;
    return null;
  end if;
  if p_value is null then
    return 'cannot be empty (null)';
  end if;
  case p_key
  when 'mail_enabled' then
    if p_value not in ('on', 'off') then
      return format('must be on or off (got %s)', p_value);
    end if;
    if p_value = 'on' and v_test and coalesce((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), '') = '' then
      return 'cannot be on in the test database while mail_redirect_to is empty — set mail_redirect_to (an @asung.ca address) first';
    end if;
  when 'mail_redirect_to' then
    if p_value <> '' and not public.ims_mail_address_ok(p_value) then
      return format('must be empty or one email address (got %s)', p_value);
    end if;
    if v_test and p_value = '' and (select c.value from public.inv_config c where c.key = 'mail_enabled') = 'on' then
      return 'cannot be emptied while mail_enabled is on in the test database — turn mail_enabled off first';
    end if;
    if v_test and p_value <> '' and lower(p_value) !~ '@asung\.ca$' then
      return format('must be an @asung.ca address in the test database (got %s)', p_value);
    end if;
  when 'mail_backorder_from' then
    if not public.ims_mail_address_ok(p_value) then
      return format('must be one email address (got %s)', p_value);
    end if;
  when 'mail_backorder_reply_to' then
    if p_value <> '' and not public.ims_mail_address_ok(p_value) then
      return format('must be empty or one email address (got %s)', p_value);
    end if;
  when 'mail_backorder_from_name' then
    if btrim(p_value) = '' then
      return 'must not be empty';
    end if;
  when 'mail_backorder_min_fill_pct' then
    if p_value !~ '^[0-9]{1,3}$' or p_value::int not between 1 and 100 then
      return format('must be a whole number from 1 to 100 (got %s)', p_value);
    end if;
  when 'mail_backorder_schedule' then
    begin
      v_j := p_value::jsonb;
    exception when others then
      return 'must be JSON like {"<warehouse id>": {"tz": "America/Toronto", "days": [1, 4], "hour": 9}}';
    end;
    if jsonb_typeof(v_j) <> 'object' or v_j = '{}'::jsonb then
      return 'must be a JSON object keyed by warehouse id (a warehouse left out gets no mail)';
    end if;
    for v_wh, v_e in select x.key, x.value from jsonb_each(v_j) x loop
      if v_wh !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
         or not exists (select 1 from public.ref_warehouse w where w.id = v_wh::uuid and w.is_active) then
        return format('key %s is not an active warehouse id', v_wh);
      end if;
      if jsonb_typeof(v_e) <> 'object' or not (v_e ? 'tz' and v_e ? 'days' and v_e ? 'hour')
         or exists (select 1 from jsonb_object_keys(v_e) k where k not in ('tz', 'days', 'hour')) then
        return format('warehouse %s needs exactly tz, days, hour', v_wh);
      end if;
      if jsonb_typeof(v_e->'tz') <> 'string' or not exists (select 1 from pg_timezone_names z where z.name = v_e->>'tz') then
        return format('warehouse %s: tz %s is not a known time zone name', v_wh, v_e->'tz');
      end if;
      if jsonb_typeof(v_e->'days') <> 'array' or jsonb_array_length(v_e->'days') = 0
         or exists (select 1 from jsonb_array_elements(v_e->'days') d where jsonb_typeof(d) <> 'number' or d::text !~ '^[1-7]$')
         or (select count(distinct d::text) from jsonb_array_elements(v_e->'days') d) <> jsonb_array_length(v_e->'days') then
        return format('warehouse %s: days must be a non-empty list of different whole numbers 1 (Mon) to 7 (Sun) (got %s)', v_wh, v_e->'days');
      end if;
      if jsonb_typeof(v_e->'hour') <> 'number' or (v_e->'hour')::text !~ '^([0-9]|1[0-9]|2[0-3])$' then
        return format('warehouse %s: hour must be a whole number 0 to 23 (got %s)', v_wh, v_e->'hour');
      end if;
    end loop;
  when 'mail_doc_from' then                                                                 -- doc-3a 판정 530: 문서 메일 보내는 주소(ims@ 의 Send mail as 에 등록된 것 · 등록 전이면 Gmail 이 거부한다)
    if not public.ims_mail_address_ok(p_value) then
      return format('must be one email address (got %s)', p_value);
    end if;
  when 'mail_doc_reply_to' then
    if p_value <> '' and not public.ims_mail_address_ok(p_value) then
      return format('must be empty or one email address (got %s)', p_value);
    end if;
  when 'mail_doc_from_name' then
    if btrim(p_value) = '' then
      return 'must not be empty';
    end if;
  else
    return 'is not a mail setting';
  end case;
  return null;
end;
$$;

insert into public.inv_config (key, value, note) values
  ('mail_doc_from',      'info@asung.ca', 'doc-3a 판정 530 — 문서 메일(최종 인보이스 · 크레딧 · SO · Ship Ready)의 보내는 주소 · ims@ 메일함에 Send mail as 로 등록돼 있어야 Gmail 이 받는다(등록 전이면 notifications@asung.ca 로 바꿔 시작) · 바꾸기 master'),
  ('mail_doc_from_name', 'Asung Trading', 'doc-3a 판정 530 — 문서 메일의 보내는 이름 · 바꾸기 master'),
  ('mail_doc_reply_to',  'info@asung.ca', 'doc-3a 판정 530 — 문서 메일의 답장 주소(빈 값이면 넣지 않는다) · 바꾸기 master')
  on conflict (key) do nothing;

-- ═══ ④ mail_outbox — 첨부 자리 · 문서 메일 kind 넷 · 상태 waiting_pdf ═══
alter table public.mail_outbox add column attachments jsonb not null default '[]'::jsonb;
alter table public.mail_outbox add constraint mail_outbox_attachments_ck check (jsonb_typeof(attachments) = 'array');
comment on column public.mail_outbox.attachments is 'doc-3a — 첨부 목록 [{doc_file_id, path, filename, bytes, sha256}] · PDF 바이트는 넣지 않는다(비공개 버킷 documents 의 doc_file) · 보내는 EF(3b)가 바이트를 받아 multipart/mixed 로 붙인다 · 백오더 메일은 []';
alter table public.mail_outbox drop constraint mail_outbox_kind_ck;
alter table public.mail_outbox add constraint mail_outbox_kind_ck check (kind in ('backorder_ready', 'doc_final_invoice', 'doc_credit_note', 'doc_sales_order', 'doc_ship_ready'));
alter table public.mail_outbox drop constraint mail_outbox_kind_category_ck;
alter table public.mail_outbox add constraint mail_outbox_kind_category_ck check (kind not in ('backorder_ready', 'doc_final_invoice', 'doc_credit_note', 'doc_sales_order', 'doc_ship_ready') or category = 'transactional');
alter table public.mail_outbox drop constraint mail_outbox_status_ck;
alter table public.mail_outbox add constraint mail_outbox_status_ck check (status in ('waiting_pdf', 'queued', 'sending', 'sent', 'failed', 'unknown', 'cancelled'));
comment on constraint mail_outbox_status_ck on public.mail_outbox is 'doc-3a: waiting_pdf = 문서 메일이 PDF 를 기다린다(3b 일꾼이 doc EF 로 만들어 붙이고 queued 로) · mail_claim 은 queued 만 집는다 · 그 밖은 mail-1a 그대로';
create index mail_outbox_waiting_idx on public.mail_outbox (created_at) where status = 'waiting_pdf';
create index mail_outbox_doc_ref_gin on public.mail_outbox using gin ((payload->'ref') jsonb_path_ops) where kind like 'doc\_%';

create table public.doc_mail_skip (
  id          bigint generated always as identity primary key,
  kind        text not null,
  ref         jsonb not null,
  customer_id uuid references public.customer(id),
  reason      text not null,
  detail      text,
  created_at  timestamptz not null default now(),
  constraint doc_mail_skip_kind_ck check (kind in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready')),
  constraint doc_mail_skip_reason_ck check (reason in ('no_email', 'reissue', 'error'))
);
comment on table public.doc_mail_skip is 'doc-3a 판정 529 — 자동 문서 메일이 서지 못한 자리(받는 주소 없음 no_email · 같은 오더의 앞 인보이스가 있다 reissue · 그 밖 오류 error) · 발행은 막지 않는다 · doc_mail_list 가 함께 보인다';
create index doc_mail_skip_ref_gin on public.doc_mail_skip using gin (ref jsonb_path_ops);
alter table public.doc_mail_skip enable row level security;
revoke all on public.doc_mail_skip from anon, authenticated;

-- ═══ ⑤ 수동 보내기 · 도우미 ═══
-- 받는 이(판정 498 그대로 · mail_backorder_pick 과 같은 고르기): 기본 연락처의 바른 주소 → 없으면 바른 주소를 가진 다른 활성 연락처 첫(created_at · id) → 없으면 null
create function public.doc_mail_recipient(p_customer_id uuid) returns jsonb
  language sql stable
  set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'to', coalesce((select lower(btrim(cc.email)) from public.customer_contact cc where cc.customer_id = p_customer_id and cc.is_active and cc.is_default and public.ims_mail_address_ok(lower(btrim(cc.email))) limit 1),
                   (select lower(btrim(cc.email)) from public.customer_contact cc where cc.customer_id = p_customer_id and cc.is_active and cc.is_default is not true and public.ims_mail_address_ok(lower(btrim(cc.email))) order by cc.created_at, cc.id limit 1)),
    'how', case when exists (select 1 from public.customer_contact cc where cc.customer_id = p_customer_id and cc.is_active and cc.is_default and public.ims_mail_address_ok(lower(btrim(cc.email)))) then 'default'
                when exists (select 1 from public.customer_contact cc where cc.customer_id = p_customer_id and cc.is_active and cc.is_default is not true and public.ims_mail_address_ok(lower(btrim(cc.email)))) then 'other'
                else 'none' end);
$$;
revoke all on function public.doc_mail_recipient(uuid) from public, anon, authenticated;

-- 글 채우기 — {{a.b}} 스칼라만(제목 · 본문의 자리표 · 값은 doc_data 의 문서) · 섹션 꼬리표({{#x}} · {{/x}} · {{^x}})는 그대로 둔다(3b 의 mustache 가 그린다 · 미리 보기용)
create function public.doc_mail_fill(p_text text, p_doc jsonb) returns text
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
declare v_out text := coalesce(p_text, ''); v_m text[]; v_val text;
begin
  for v_m in select regexp_matches(coalesce(p_text, ''), '\{\{\s*([a-z_][a-z0-9_]*(?:\.[a-z_][a-z0-9_]*)*)\s*\}\}', 'g') loop
    v_val := coalesce(p_doc #>> string_to_array(v_m[1], '.'), '');
    v_out := regexp_replace(v_out, '\{\{\s*' || replace(v_m[1], '.', '\.') || '\s*\}\}', replace(v_val, '\', '\\'), 'g');   -- 바꿔 넣는 글의 \ 만 피한다(& 는 PostgreSQL 에서 글자 그대로)
  end loop;
  return v_out;
end;
$$;
revoke all on function public.doc_mail_fill(text, jsonb) from public, anon;
grant execute on function public.doc_mail_fill(text, jsonb) to authenticated, service_role;

-- 문서의 청구처(받는 이의 손님) — kind 마다 원천이 다르다
create function public.doc_mail_customer(p_kind text, p_ref jsonb) returns uuid
  language sql stable
  set search_path = public, pg_temp
as $$
  select case p_kind
    when 'final_invoice' then (select i.bill_to_customer_id from public.so_invoice i where i.id = nullif(p_ref->>'invoice_id', '')::uuid)
    when 'credit_note'   then (select c.customer_id from public.so_credit c where c.id = nullif(p_ref->>'credit_id', '')::uuid)
    when 'sales_order'   then (select coalesce(s.bill_to_customer_id, s.customer_id) from public.so s where s.id = nullif(p_ref->>'so_id', '')::uuid)
    when 'ship_ready'    then (select coalesce(s.bill_to_customer_id, s.customer_id) from public.so s where s.id = nullif(p_ref->'orders'->0->>'so_id', '')::uuid)
  end;
$$;
revoke all on function public.doc_mail_customer(text, jsonb) from public, anon, authenticated;

-- 한 줄 세우기(속 · ⑤ 실행 · ⑥ 자동이 같이 쓴다) — 받는 이 · 제목 · 본문 · 보내는 주소 · 첨부(있으면 queued · 없으면 waiting_pdf)
create function public.doc_mail_enqueue(p_kind text, p_ref jsonb, p_to text, p_subject text, p_body text, p_customer_id uuid, p_staff uuid, p_doc_file_id uuid, p_auto boolean) returns jsonb
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
  insert into public.mail_outbox (kind, category, status, from_address, from_name, reply_to, to_address, subject, body_text, payload, customer_id, attachments, dedupe_key, created_by)
  values ('doc_' || p_kind, 'transactional', case when p_doc_file_id is null then 'waiting_pdf' else 'queued' end, v_from, nullif(v_name, ''), v_reply, p_to, p_subject, p_body,
          jsonb_build_object('doc_kind', p_kind, 'ref', p_ref, 'customer_id', p_customer_id, 'auto', p_auto, 'requested_by', p_staff, 'doc_file_id', p_doc_file_id),
          p_customer_id, v_att, 'doc:' || p_kind || ':' || md5(p_ref::text) || ':' || to_char(clock_timestamp(), 'YYYYMMDDHH24MISSUS'), p_staff)
  returning * into v_o;
  return jsonb_build_object('outbox_id', v_o.id, 'status', v_o.status, 'to', v_o.to_address, 'subject', v_o.subject, 'attachments', v_o.attachments, 'created_at', v_o.created_at);
end;
$$;
revoke all on function public.doc_mail_enqueue(text, jsonb, text, text, text, uuid, uuid, uuid, boolean) from public, anon, authenticated;

create function public.doc_mail_send(p_kind text, p_ref jsonb, p_to text default null, p_subject text default null, p_body text default null, p_commit boolean default false, p_doc_file_id uuid default null) returns jsonb
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
  if p_kind = 'ship_ready' and p_doc_file_id is null then raise exception 'A Ship Ready mail needs the PDF made first (doc_file_id) — nothing was saved'; end if;   -- doc_data(so_finalize 미리 보기)보다 먼저 — 싼 문부터
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
comment on function public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid) is 'doc-3a — 직원이 누르는 문서 메일(final_invoice · credit_note · sales_order · ship_ready · internal_receipt 는 안 보낸다): 문 sales 쓰기(+ doc_data 의 문) · 받는 이 = 판정 498 고르기(p_to 로 바꿀 수 있다 · 한 통에 한 주소) · 제목 · 본문 = doc_setting 글(p_subject · p_body 로 바꿀 수 있다)의 {{a.b}} 를 doc_data 의 값으로 채움 · p_commit false = 미리 보기(시험 DB 면 redirect_to 도) · true = mail_outbox 한 줄 — PDF 없으면 waiting_pdf(3b 일꾼이 doc EF 로 만들어 붙이고 queued 로) · ship_ready 는 직원이 doc EF 로 만든 PDF 의 doc_file_id 가 있어야(service 길은 ship_ready 를 못 만든다) → queued · 보내는 주소 = mail_doc_*(판정 530)';
revoke all on function public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid) from public, anon;
grant execute on function public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid) to authenticated;

-- ═══ ⑥ 자동(판정 529) — so_invoice AFTER INSERT · 지연 제약 트리거(발행 트랜잭션 끝에 — 그때는 담긴 오더 · 줄 · 합계가 다 있다) · so_invoice_issue 무접촉 ═══
create function public.doc_mail_auto_invoice() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_on boolean; v_rcpt jsonb; v_doc jsonb; v_ref jsonb := jsonb_build_object('invoice_id', new.id); v_subject text; v_body text; v_staff uuid;
begin
  select c.final_invoice_mail into v_on from public.customer c where c.id = new.bill_to_customer_id;
  if not coalesce(v_on, false) then return null; end if;
  if (select i.status from public.so_invoice i where i.id = new.id) is distinct from 'issued' then return null; end if;             -- 같은 트랜잭션에서 취소됐으면 아무것도
  if exists (select 1 from public.so_invoice_order o1 join public.so_invoice_order o2 on o2.so_id = o1.so_id and o2.invoice_id <> o1.invoice_id where o1.invoice_id = new.id) then
    insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'reissue', 'an earlier invoice exists for the same order — not mailed automatically');
    return null;
  end if;
  v_rcpt := public.doc_mail_recipient(new.bill_to_customer_id);
  if v_rcpt->>'to' is null then
    insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'no_email', 'the customer has no contact with an email address');
    return null;
  end if;
  begin
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    v_doc := public.doc_data('final_invoice', v_ref)->'docs'->0;
    v_subject := btrim(public.doc_mail_fill((select d.value from public.doc_setting d where d.kind = 'final_invoice' and d.key = 'mail_subject'), v_doc));
    v_body := public.doc_mail_fill((select d.value from public.doc_setting d where d.kind = 'final_invoice' and d.key = 'mail_body'), v_doc);
    if v_subject = '' then raise exception 'mail_subject of final_invoice is empty (Settings → Documents)'; end if;
    perform public.doc_mail_enqueue('final_invoice', v_ref, v_rcpt->>'to', v_subject, v_body, new.bill_to_customer_id, v_staff, null, true);
  exception when others then                                                                                                             -- 발행을 막지 않는다 — 남기고 지나간다
    insert into public.doc_mail_skip (kind, ref, customer_id, reason, detail) values ('final_invoice', v_ref, new.bill_to_customer_id, 'error', left(sqlerrm, 500));
  end;
  return null;
end;
$$;
comment on function public.doc_mail_auto_invoice() is 'doc-3a 판정 529 — 인보이스가 issued 로 생기고 청구처의 final_invoice_mail 이 켜져 있으면 문서 메일 한 줄(waiting_pdf · 3b 가 PDF 를 붙여 보낸다) · 지연 제약 트리거라 발행 트랜잭션 끝에 돈다(so_invoice_issue 무접촉) · 건너뜀: 같은 오더의 앞 인보이스가 있다(재발행 · reissue) · 받는 주소 없음(no_email) · 그 밖 오류(error) → doc_mail_skip · 발행은 막지 않는다 · POS · Shopify 주문도 칸대로';
revoke all on function public.doc_mail_auto_invoice() from public, anon;
create constraint trigger so_invoice_doc_mail_auto after insert on public.so_invoice deferrable initially deferred for each row execute function public.doc_mail_auto_invoice();

-- ═══ ⑦ 읽기 · 취소 ═══
create function public.doc_mail_list(p_kind text, p_ref jsonb) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.doc_staff_or_service();
  if p_kind not in ('final_invoice', 'credit_note', 'sales_order', 'ship_ready') then raise exception 'Unknown document mail kind %', coalesce(p_kind, '(null)'); end if;
  if p_ref is null or jsonb_typeof(p_ref) <> 'object' then raise exception 'p_ref must be a JSON object'; end if;
  return jsonb_build_object(
    'mails', coalesce((select jsonb_agg(jsonb_build_object('outbox_id', o.id, 'status', o.status, 'to', o.to_address, 'original_to', o.original_to, 'subject', o.subject, 'auto', (o.payload->>'auto')::boolean,
                                                           'attachments', o.attachments, 'created_at', o.created_at, 'created_by', o.created_by, 'created_by_name', s.name, 'sent_at', o.sent_at, 'attempts', o.attempts, 'last_error', o.last_error) order by o.created_at desc)
                       from public.mail_outbox o left join public.ims_staff s on s.id = o.created_by
                       where o.kind = 'doc_' || p_kind and o.payload->'ref' @> p_ref), '[]'::jsonb),
    'skipped', coalesce((select jsonb_agg(jsonb_build_object('id', k.id, 'reason', k.reason, 'detail', k.detail, 'created_at', k.created_at) order by k.created_at desc)
                         from public.doc_mail_skip k where k.kind = p_kind and k.ref @> p_ref), '[]'::jsonb));
end;
$$;
comment on function public.doc_mail_list(text, jsonb) is 'doc-3a 읽기 — 그 문서(kind · ref 포함)의 메일 목록(상태 · 받는 이 · 제목 · 자동인가 · 첨부 · 누가 · 언제 · 결과)과 건너뛴 것(doc_mail_skip) · 활성 직원 · service_role';
revoke all on function public.doc_mail_list(text, jsonb) from public, anon;
grant execute on function public.doc_mail_list(text, jsonb) to authenticated, service_role;

create function public.doc_mail_cancel(p_outbox_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_o public.mail_outbox%rowtype; v_staff uuid;
begin
  perform public.ims_require_write('sales', 'cancelled');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'A note is required — nothing was saved'; end if;
  select * into v_o from public.mail_outbox o where o.id = p_outbox_id for update;
  if v_o.id is null then raise exception 'Mail not found — nothing was saved'; end if;
  if v_o.kind not like 'doc\_%' then raise exception 'Only a document mail can be cancelled here (backorder mails: Backorders → Emails) — nothing was saved'; end if;
  if v_o.status not in ('waiting_pdf', 'queued') then raise exception 'Only a mail still waiting (waiting_pdf or queued) can be cancelled (this one is %) — nothing was saved', v_o.status; end if;
  update public.mail_outbox set status = 'cancelled' where id = v_o.id;
  insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts, staff_id, note) values (v_o.id, 'cancel', v_o.status, 'cancelled', v_o.attempts, v_staff, btrim(p_note));
  return jsonb_build_object('outbox_id', v_o.id, 'status', 'cancelled', 'from_status', v_o.status);
end;
$$;
comment on function public.doc_mail_cancel(uuid, text) is 'doc-3a — 아직 안 나간 문서 메일(waiting_pdf · queued)을 취소(sales 쓰기 · 메모 필수 · mail_outbox_event cancel) · 백오더 메일은 mail_outbox_cancel(manager)';
revoke all on function public.doc_mail_cancel(uuid, text) from public, anon;
grant execute on function public.doc_mail_cancel(uuid, text) to authenticated;

-- ═══ ⑧ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'customer' and column_name = 'final_invoice_mail' and is_nullable = 'NO' and column_default = 'false') then v_bad := v_bad || ' customer-col'; end if;
  if (select prosrc from pg_proc where oid = 'public.customer_update(jsonb, boolean, text[])'::regprocedure) !~ 'final_invoice_mail = v_new::boolean' then v_bad := v_bad || ' customer_update'; end if;
  if cardinality(public.ims_mail_config_keys()) <> 10 or (select count(*) from public.inv_config where key = any (public.ims_mail_config_keys())) <> 10 then v_bad := v_bad || ' mail-keys'; end if;
  if (select count(*) from public.inv_config where key = any (public.ims_mail_config_keys()) and public.ims_mail_config_problem(key, value) is not null) <> 0 then v_bad := v_bad || ' mail-key-values'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'mail_outbox' and column_name = 'attachments') then v_bad := v_bad || ' attachments'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_status_ck') !~ 'waiting_pdf' or (select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_outbox_kind_ck') !~ 'doc_final_invoice' then v_bad := v_bad || ' outbox-ck'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_invoice'::regclass and tgname = 'so_invoice_doc_mail_auto' and tgdeferrable and tginitdeferred) <> 1 then v_bad := v_bad || ' trigger'; end if;
  if public.doc_mail_fill('No {{invoice.number}} for {{bill_to.name}} {{#x}}y{{/x}} {{nope.key}}', '{"invoice": {"number": "60009"}, "bill_to": {"name": "A & B"}}') <> 'No 60009 for A & B {{#x}}y{{/x}} ' then v_bad := v_bad || ' fill'; end if;
  if has_function_privilege('anon', 'public.doc_mail_send(text, jsonb, text, text, text, boolean, uuid)', 'execute') or has_function_privilege('authenticated', 'public.doc_mail_enqueue(text, jsonb, text, text, text, uuid, uuid, uuid, boolean)', 'execute')
     or has_function_privilege('authenticated', 'public.doc_mail_recipient(uuid)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and table_name = 'doc_mail_skip' and grantee in ('anon', 'authenticated')) then v_bad := v_bad || ' skip-grants'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - doc-3a did not land as designed:%s - nothing was changed', v_bad); end if;
end $$;
