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
-- ═══ ldfix-1a2 — IMS 에서 부모를 「뗀」 결정도 표식으로 남긴다 (2026-10-24 · 판정 678 · 판정 256 · 253 의 「비우면 null」 이 바뀜) ═══
--   ① customer_parent_guard 재발행(원본 20261006131814_master_cs_par_1.sql) — parent_id 가 비면 parent_source 가 'cin7' 일 때만 null(Cin7 이 뗐다 · 적재 2단계 비우기 PATCH {parent_id:null} 은 옛 'cin7' 을 싣고 와 여기서 비워진다)
--      'ims' 는 남긴다 = 「IMS 가 부모 없음으로 정했다」(창구 customer_update 가 명시) · 규칙 1(깊이 하나) · 규칙 4(옛 부모를 가리키던 청구처 null) 그대로 · 트리거 정의 BEFORE INSERT OR UPDATE OF parent_id 그대로
--   ② customer_update 재발행 — 원본 20261019184432_doc_3a_mail_db.sql 41 ~ 482 행 바이트 그대로 · 바뀐 줄 1(parent_id 갈래: 비울 때도 parent_source = 'ims') · 옛 본문 md5 9643fd449c9c06ddf4616f5c968349b8 → 새 9d44ac6c2bb803c57a092876047a9852 · 서명 같음 · ACL · comment 유지(착지가 확인)
--   ③ 채우기 1 행 — Asung Employee - Sungeun Lee(cin7_id 2ca116b6-145b-455b-a3c1-7e0a30fc04fb) · 2026-10-20 IMS 창구에서 뗐으나 옛 256 으로 parent_source 가 null 이 된 행 → 'ims' · 바뀐 행이 1 이 아니면 멈춤(0 = 이미 바뀜 · 2 = cin7_id 겹침)
--      ⚠️ customer_touch(ims_touch)가 돌아 updated_at = 적용 시각 · updated_by = null 이 된다(DDL 로 트리거를 끄지 않는다 — 테스트 DB 잠금) · 672 목록에서 이 행이 빠지지만 1단계 칸은 직원이 안 바꿨다
--   ④ comment 셋(칼럼 parent_source · 함수 customer_parent_guard · 트리거) 새 뜻 · customer_update comment 끝에 포인터 · CHECK customer_parent_source_ck 무변(null · cin7 · ims)
--   ⚠️ 적재 코드 ImsLoadCustomer.gs 는 판정 무변 — 2단계는 parent_source='ims' 면 parent_id 와 무관하게 건너뛴다(ldfix-1a 481 행) · 문구 · 수만 ldfix-1a2 가 손본다 · 새 표 · 시퀀스 0 · 화면 무변(asung-ims 에 parent_source 읽는 곳 0)

-- ═══ 1) customer_parent_guard — 판정 678 ═══
create or replace function public.customer_parent_guard()
  returns trigger
  language plpgsql
  security definer
  set search_path = public, pg_temp
as $$
declare
  v_parent public.customer%rowtype;
begin
  -- 규칙 1 — 깊이 하나(새 부모가 자식이면 · 내게 자식이 있으면 거부) · 부모가 없는 id 는 FK 가 뒤에서 막는다
  if new.parent_id is not null then
    select * into v_parent from public.customer c where c.id = new.parent_id;
    if found and v_parent.parent_id is not null then
      raise exception '% already has a parent — a customer tree is one level deep — nothing was saved', v_parent.name;
    end if;
    if exists (select 1 from public.customer k where k.parent_id = new.id and k.id <> new.id) then
      raise exception '% has children of its own — a customer tree is one level deep — nothing was saved', new.name;
    end if;
  end if;
  -- 규칙 4 — 부모를 비우거나 바꿀 때 청구처가 그 옛 부모면 자기 자신(null)으로
  if tg_op = 'UPDATE' and old.parent_id is not null and new.parent_id is distinct from old.parent_id and new.default_bill_to_customer_id = old.parent_id then
    new.default_bill_to_customer_id := null;
  end if;
  -- 판정 678(ldfix-1a2 · 2026-10-24 · 256 바뀜) — 부모가 없는데 parent_source 가 'cin7' 이면 모순이라 비운다(Cin7 이 뗐다 · 적재 비우기 PATCH 가 지나는 길)
  --   'ims' 는 남긴다 — IMS 창구가 「부모 없음」 으로 정한 표식(customer_update 가 명시) · 적재 2단계는 이 행을 건너뛴다
  if new.parent_id is null and new.parent_source = 'cin7' then
    new.parent_source := null;
  end if;
  return new;
end;
$$;
comment on function public.customer_parent_guard() is 'customer BEFORE INSERT OR UPDATE OF parent_id 트리거(cs-par-1 · 2026-10-06 · ldfix-1a2 · 2026-10-24) — 규칙 1 깊이 하나(새 부모가 자식 · 내게 자식 → 거부 · 창구 parent_has_parent 의 밑단) · 규칙 4 부모를 비우거나 바꿀 때 default_bill_to_customer_id 가 옛 부모면 null(창구는 bill_to_reset_with_parent 로 먼저 알린다 · 적재 2단계 비우기 PATCH 도 지난다) · 판정 678 parent_id 가 비면 parent_source 가 cin7 일 때만 null(Cin7 이 뗐다) · ims 는 남긴다(IMS 가 부모 없음으로 정했다 · 창구가 명시 · 적재 2단계가 건너뛴다) · inactive · 권한은 보지 않는다(창구 일) · 적재 1단계 upsert 는 parent_id 를 안 보내 바로 지나간다';
comment on trigger customer_parent_guard on public.customer is 'cs-par-1 규칙 1 · 4 · 판정 253 · 678(ldfix-1a2) — 함수 주석 참조';
comment on column public.customer.parent_source is '⭐ 판정 253(cs-par-1 · 2026-10-06) · 678(ldfix-1a2 · 2026-10-24) — 이 부모 관계를 누가 정했나: ims(창구 customer_update · customer_create 가 세움 · 바꿈 · ⭐ 뗌 — parent_id 가 없고 ims 면 「IMS 가 부모 없음으로 정했다」) · cin7(적재 2단계 · 채우기 13행) · null(부모 없음 · 아무도 안 정함 — Cin7 이 뗐거나 처음부터 없음 · 트리거가 parent_id 가 비면 cin7 만 null 로 비운다) · 적재 2단계는 ims 인 행은 parent_id 와 무관하게 건너뛴다(ldfix-1a · 1a2)';

-- ═══ 2) customer_update 재발행 — 바뀐 줄 1(parent_id 갈래) ═══
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
          when 'parent_id' then update public.customer set parent_id = v_new::uuid, parent_source = 'ims', updated_by = v_staff where id = v_cid;   -- 판정 253 · 678(ldfix-1a2 · 2026-10-24): 창구가 세우거나 바꾸거나 떼면 모두 ims — 뗀 것도 「IMS 가 부모 없음으로 정했다」 는 표식(적재 2단계가 건너뛴다) · 옛 줄은 비울 때 null(256 옛 뜻)
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

do $$ declare v_c text; begin
  select obj_description('public.customer_update(jsonb, boolean, text[])'::regprocedure) into v_c;
  execute format('comment on function public.customer_update(jsonb, boolean, text[]) is %L', coalesce(v_c, '') || ' · [2026-10-24 · ldfix-1a2 · 판정 678] parent_id 를 비우는 set 도 parent_source = ims 를 남긴다(뗀 결정의 표식 · 적재 2단계가 건너뛴다)');
end $$;

-- ═══ 3) 채우기 1 행 — Sungeun Lee(cin7_id 로 집는다 · 이름은 단언) ═══
do $$
declare v_name text;  v_n int;
begin
  select c.name into v_name from public.customer c where c.cin7_id = '2ca116b6-145b-455b-a3c1-7e0a30fc04fb';
  if v_name is distinct from 'Asung Employee - Sungeun Lee' then
    raise exception 'ldfix-1a2 backfill: cin7_id 2ca116b6-145b-455b-a3c1-7e0a30fc04fb is "%" — expected "Asung Employee - Sungeun Lee" — nothing was changed', coalesce(v_name, '<missing>');
  end if;
  update public.customer set parent_source = 'ims' where cin7_id = '2ca116b6-145b-455b-a3c1-7e0a30fc04fb' and parent_id is null and parent_source is null;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'ldfix-1a2 backfill: expected exactly 1 row (parent_id null · parent_source null), got % — nothing was changed', v_n;
  end if;
  raise notice 'ldfix-1a2 backfill: parent_source = ims on 1 row (Asung Employee - Sungeun Lee · detached in IMS 2026-10-20 · ruling 678)';
end $$;

-- ═══ 착지 — 트리거 몸 · 창구 md5 · 채우기 · CHECK · 트리거 정의 ═══
do $$
declare v_src text;  v_md5 text;  v_def text;  v_ck text;  v_row record;
begin
  select prosrc into v_src from pg_proc where proname = 'customer_parent_guard' and pronamespace = 'public'::regnamespace;
  if v_src !~ $q$new\.parent_id is null and new\.parent_source = 'cin7'$q$ or v_src ~ '어느 길로 비워도' then raise exception 'ldfix-1a2 landing: customer_parent_guard body is not the new one'; end if;
  select md5(prosrc) into v_md5 from pg_proc where proname = 'customer_update' and pronamespace = 'public'::regnamespace;
  if v_md5 <> '9d44ac6c2bb803c57a092876047a9852' then raise exception 'ldfix-1a2 landing: customer_update body md5 % <> expected 9d44ac6c2bb803c57a092876047a9852', v_md5; end if;
  if v_md5 = '9643fd449c9c06ddf4616f5c968349b8' then raise exception 'ldfix-1a2 landing: customer_update still the old body'; end if;
  select parent_id, parent_source into v_row from public.customer where cin7_id = '2ca116b6-145b-455b-a3c1-7e0a30fc04fb';
  if v_row.parent_id is not null or v_row.parent_source is distinct from 'ims' then raise exception 'ldfix-1a2 landing: backfill row not (null, ims)'; end if;
  select pg_get_constraintdef(oid) into v_ck from pg_constraint where conname = 'customer_parent_source_ck';
  if v_ck <> $q$CHECK (((parent_source IS NULL) OR (parent_source = ANY (ARRAY['cin7'::text, 'ims'::text]))))$q$ then raise exception 'ldfix-1a2 landing: CHECK changed: %', v_ck; end if;
  select pg_get_triggerdef(oid) into v_def from pg_trigger where tgname = 'customer_parent_guard' and tgrelid = 'public.customer'::regclass;
  if v_def <> 'CREATE TRIGGER customer_parent_guard BEFORE INSERT OR UPDATE OF parent_id ON public.customer FOR EACH ROW EXECUTE FUNCTION customer_parent_guard()' then raise exception 'ldfix-1a2 landing: trigger def changed: %', v_def; end if;
  raise notice 'ldfix-1a2 landed: guard new · customer_update md5 9d44ac6c · backfill (null, ims) · CHECK and trigger unchanged';
end $$;
