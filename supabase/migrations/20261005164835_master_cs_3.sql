-- ─────────────────────────────────────────────────────────────
-- 공급처 만들기 · 고치기 창구 + 공급처 표 넷 닫기 + 손님 끄기 · 켜기는 master 만(판정 241) (Asung-IMS · master-cs-3 · 2026-10-05)
--   정본(뒤에 적는다): so-module §41 — 판정 236 ~ 241 · master-cs 묶음 1 ~ 9 · cs-1 보고 §5(공급처 돈 칸) · 조사 master-cs-0 이견 1(공급처 적재 코드가 레포에 없다)
--   판정 241  손님 끄기 · 켜기는 master 만 — customer_update 재발행(마지막 정의 20261005163039 바이트 그대로 · is_active 를 돈 칸 목록으로 옮긴 줄 둘 + comment 한 줄)
--   ① supplier_create(p_supplier, p_commit, p_ack) · ② supplier_update(p_changes, p_commit, p_ack) — 손님 창구 모양 그대로(두 번 부르기 · op · old 대조 · 한 호출에 주소 · 연락처 · 할인 · 「기본 하나」 deferrable)
--      문 = purchasing 또는 master 쓰기 · 돈 칸(master 만) = currency_id · payment_term_id · account_payable_id · tax_rule · 할인 op(discount_add/set/off) · 끄기 · 켜기(is_active)도 master(판정 241 과 같은 결)
--      이름(판정 238): 접은 이름(공백 하나 · 대소문자 무시)이 같은 공급처(꺼진 것 포함)가 있으면 막기 name_exists · 끝의 「(Supplier)」 를 뗀 이름이 같으면 알리기 name_similar
--      purchasing 이 만들 때 돈 칸은 inv_config supplier_default_*(결제조건 · 매입채무 계정 · 통화 · 세금 규칙 · seed = 활성 공급처 최빈값) · master 는 직접
--   ③ 공급처 표 넷 닫기 — cs-1 모양(쓰기 정책 drop + revoke insert · update · delete · select 그대로) · 공급처 행을 for update 로 잠그는 invoker 창구 없음(전수 grep 0) ⇒ 「잠금만」 없이 완전히
--      ⚠️ po_discount_save/po_discount_delete(20260918003000 · security invoker · p_target 'supplier' 갈래 · 문 master)가 supplier_discount 를 쓴다 — 화면(po.html · invoices.html)은 'po' · 'invoice' 로만 부른다(grep) ⇒ 그 갈래는 닫힌 뒤 42501 로 죽는다(쓰는 곳 0 · 공급처 할인은 supplier_update 로) · 재발행은 뒤 차수
--      ⚠️ 적재(ImsLoadSupplier.gs 셋 · 레포에 없다)는 ImsRefLoad.gs ims_fetch_ 와 같은 service_role 키로 쓴다고 짐작(po-module §3-c 「셋 다 ims_fetch_ 를 쓴다」) ⇒ rolbypassrls · 표 권한 그대로라 산다 · 검증 L 이 service_role upsert(name · cin7_id)를 증명 · Caleb 실측 거리(적용 뒤 적재 한 번)
--   막기(code)  op_unknown(raise) · supplier_unknown · field_unknown · old_missing · changed_elsewhere · field_duplicate_in_call · money_field_not_allowed · default_missing · name_missing · name_exists · value_invalid
--               payment_term_invalid · account_invalid · currency_invalid · discount_invalid · discount_unknown · discount_inactive · address_unknown · address_empty · address_inactive · contact_unknown · contact_empty · contact_inactive
--   알리기(code) name_similar · inactive_open_po · inactive_open_invoice · inactive_products · inactive_formulas · open_po_keep_old · contact_default_off · currency_account_mismatch
--   반환 create { committed, supplier_id, name, defaults_used, address_ids, contact_ids, blocks, warnings, unacked } · update { committed, changes[{i, supplier_id, op, field, applied, id?}], blocks, warnings, unacked }
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 = customer_update 하나(위) · 끝의 do 블록이 닫힘 실물을 세어 어긋나면 전부 되돌린다
-- ─────────────────────────────────────────────────────────────
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

-- ═══ 1) 판정 241 — customer_update 재발행(마지막 정의 20261005163039:49~474 바이트 그대로 · 바뀐 줄: v_money · v_general · comment) ═══
create or replace function public.customer_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_master   boolean;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_reviewed uuid[] := '{}';
  v_money    text[] := array['price_tier', 'discount_pct', 'payment_term_id', 'currency_id', 'ar_account_id', 'sale_account_id', 'default_bill_to_customer_id', 'is_bill_parent', 'invoice_split_by_store', 'is_active'];   -- 판정 241(cs-3): 켜기 · 끄기도 master 만
  v_general  text[] := array['name', 'display_name', 'note', 'tax_rule', 'default_location_id', 'default_carrier', 'tax_number', 'tags', 'is_legal_entity', 'parent_id', 'default_ship_to_customer_id'];
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
      if v_field is null or not (v_field = any(v_general) or v_field = any(v_money)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(blank)'), 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: field %s cannot be changed here — nothing was saved', v_cust.name, coalesce(v_field, '(blank)')));
        continue;
      end if;
      if (v_key || ':' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s %s is changed twice in this call — keep one — nothing was saved', v_cust.name, v_field));
        continue;
      end if;
      v_seen := array_append(v_seen, v_key || ':' || v_field);
      if v_field = any(v_money) and not v_master then
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
        when 'is_bill_parent' then v_cust.is_bill_parent::text when 'invoice_split_by_store' then v_cust.invoice_split_by_store::text end;
      if (case when v_field = 'discount_pct' then (v_cur::numeric is distinct from nullif(v_c->>'old', '')::numeric)
               when v_field in ('is_legal_entity', 'is_active', 'is_bill_parent', 'invoice_split_by_store') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean)
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
      elsif v_field in ('is_legal_entity', 'is_active', 'is_bill_parent', 'invoice_split_by_store') then
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
      elsif v_field in ('default_ship_to_customer_id', 'default_bill_to_customer_id') then
        if v_new is not null and not exists (select 1 from public.customer c where c.id = v_new::uuid and c.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || case when v_field = 'default_ship_to_customer_id' then 'ship_to_unknown' else 'bill_to_unknown' end, 'customer_id', v_cid, 'code', case when v_field = 'default_ship_to_customer_id' then 'ship_to_unknown' else 'bill_to_unknown' end, 'message', format('%s: that customer does not exist or is inactive — nothing was saved', v_cust.name));
        end if;
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
          when 'parent_id' then update public.customer set parent_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'default_ship_to_customer_id' then update public.customer set default_ship_to_customer_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'is_active' then update public.customer set is_active = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'price_tier' then update public.customer set price_tier = v_new, updated_by = v_staff where id = v_cid;
          when 'discount_pct' then update public.customer set discount_pct = v_new::numeric, updated_by = v_staff where id = v_cid;
          when 'payment_term_id' then update public.customer set payment_term_id = v_new::uuid, payment_term_name = (select t.name from public.ref_payment_term t where t.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'currency_id' then update public.customer set currency_id = v_new::uuid, currency_code = (select r.code from public.ref_currency r where r.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'ar_account_id' then update public.customer set ar_account_id = v_new::uuid, ar_account_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'sale_account_id' then update public.customer set sale_account_id = v_new::uuid, sale_account_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'default_bill_to_customer_id' then update public.customer set default_bill_to_customer_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'is_bill_parent' then update public.customer set is_bill_parent = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'invoice_split_by_store' then update public.customer set invoice_split_by_store = v_new::boolean, updated_by = v_staff where id = v_cid;
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
revoke all on function public.customer_update(jsonb, boolean, text[]) from public, anon;
grant execute on function public.customer_update(jsonb, boolean, text[]) to authenticated;
comment on function public.customer_update(jsonb, boolean, text[]) is
  'master-cs-2b · 판정 237 · 238 · 240 — 손님 고치기 창구 하나(product_update 모양): p_changes = 바꿀 것 목록(한 호출에 손님 여럿 · 최대 1,000 줄 · 줄 = {customer_id, op, …}) · op 아홉 = set(field · value · old) · address_add/set/off/default · contact_add/set/off/default · 문 = sales 또는 master 쓰기 · 돈 칸 아홉 + is_active(판정 241 · cs-3 재발행 · 켜기 · 끄기도 master)(price_tier · discount_pct · payment_term_id · currency_id · ar_account_id · sale_account_id · default_bill_to_customer_id · is_bill_parent · invoice_split_by_store)의 set 은 master 만(money_field_not_allowed) · 줄마다 old 대조(changed_elsewhere · old_missing · field_duplicate_in_call) · 두 번 부르기(p_commit · p_ack · unacked) · 바꾸는 칸의 새 값만 검사(옛 꺼진 참조는 막지 않는다) · 이름 바꾸기 · 켜기는 같은 접은 이름 알리기 · 끄기는 열린 SO · 미수 · 잔액 · 자식 알리기 · 돈 칸 · 주소를 바꾸면 열린 SO 수 알리기(옛 값 그대로) · 기본 옮기기는 한 문장(deferrable) · master 의 돈 칸 저장은 reviewed_by/at(처음만 · reviewed_now). 2026-10-05';

-- ═══ 2) 공급처 돈 칸 기본값 — inv_config 키 넷(잠금 밖 · 있으면 두기 · seed = 활성 공급처 226 최빈값) ═══
insert into public.inv_config (key, value, note) values
  ('supplier_default_payment_term',        'Due on receipt',        'master-cs-3 — purchasing 이 만든 새 공급처의 결제조건(ref_payment_term.name · 활성) · 활성 공급처 92/226 · master 가 바꾼다'),
  ('supplier_default_account_payable_code','_109_',                 'master-cs-3 — 새 공급처의 매입채무 계정(ref_account.code) · 활성 공급처 183/226 이 _109_ Accounts Payable (A/P) - USD · ⚠️ CAD 공급처는 _62_ — 통화를 CAD 로 바꾸면 계정도 master 가 함께(창구가 currency_account_mismatch 로 알린다)'),
  ('supplier_default_currency_code',       'USD',                   'master-cs-3 — 새 공급처의 통화(ref_currency.code) · 활성 공급처 USD 159 · CAD 67'),
  ('supplier_default_tax_rule',            'Zero-rated (Purchase)', 'master-cs-3 — 새 공급처의 세금 규칙 원문(po 머리로 복사된다) · 활성 공급처 149/226')
on conflict (key) do nothing;

-- ═══ 3) 만들기 창구 ═══
--   p_supplier = { name*, note, is_purchasable(true|false|null), is_discontinued, discontinued_on,
--                  [master 만] currency_id · payment_term_id · account_payable_id · tax_rule · discounts:[{name, percent}],
--                  addresses:[{type, line1, line2, city, state_province, postal_code, country}], contacts:[{name, phone, mobile_phone, fax, email, website, is_default}] }
create or replace function public.supplier_create(p_supplier jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_master   boolean;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_defaults text[] := '{}';
  v_name     text;
  v_folded   text;
  v_money    text[] := array['currency_id', 'payment_term_id', 'account_payable_id', 'tax_rule', 'discounts'];
  v_given    text[];
  v_term     public.ref_payment_term%rowtype;
  v_cur      public.ref_currency%rowtype;
  v_acct     public.ref_account%rowtype;
  v_tax      text;
  v_cfg      text;
  v_a        jsonb;
  v_c        jsonb;
  v_d        jsonb;
  v_i        int;
  v_n_cdef   int := 0;
  v_pct      numeric;
  v_sid      uuid;
  v_rid      uuid;
  v_addr_ids jsonb := '[]'::jsonb;
  v_cont_ids jsonb := '[]'::jsonb;
  v_keys     text[];
  v_unacked  text[];
  v_sim      jsonb;
begin
  if not (public.ims_can_write('purchasing') or public.ims_can_write('master')) then
    raise exception 'You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if p_supplier is null or jsonb_typeof(p_supplier) <> 'object' then raise exception 'p_supplier must be a JSON object — nothing was saved'; end if;
  if p_supplier ? 'addresses' and jsonb_typeof(p_supplier->'addresses') <> 'array' then raise exception 'addresses must be a JSON array — nothing was saved'; end if;
  if p_supplier ? 'contacts'  and jsonb_typeof(p_supplier->'contacts')  <> 'array' then raise exception 'contacts must be a JSON array — nothing was saved'; end if;
  if p_supplier ? 'discounts' and jsonb_typeof(p_supplier->'discounts') <> 'array' then raise exception 'discounts must be a JSON array — nothing was saved'; end if;

  -- 이름(판정 238 · 공급처는 막는다 · 꺼진 것 포함 · 「(Supplier)」 를 뗀 이름이 같으면 알리기)
  v_name := nullif(btrim(p_supplier->>'name'), '');
  if v_name is null then
    v_blocks := v_blocks || jsonb_build_object('key', 'name_missing', 'code', 'name_missing', 'message', 'The supplier has no name — nothing was saved');
  else
    v_folded := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
    if exists (select 1 from public.supplier s where lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = v_folded) then
      v_blocks := v_blocks || jsonb_build_object('key', 'name_exists', 'code', 'name_exists', 'message', format('A supplier named "%s" already exists (%s) — the name is the key (Cin7 refers to suppliers by name) — reactivate or rename that one instead — nothing was saved', v_name,
        (select string_agg(s.name || case when s.is_active then '' else ' · inactive' end, '; ') from public.supplier s where lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = v_folded)));
    else
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'is_active', s.is_active) order by s.name), '[]'::jsonb) into v_sim from public.supplier s
       where regexp_replace(lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')), '\s*\(supplier\)$', '') = regexp_replace(v_folded, '\s*\(supplier\)$', '');
      if jsonb_array_length(v_sim) > 0 then
        v_warns := v_warns || jsonb_build_object('key', 'name_similar', 'code', 'name_similar', 'matches', v_sim, 'message', format('%s supplier(s) have almost the same name (%s) — is this the same company? Confirm to create anyway', jsonb_array_length(v_sim), (select string_agg(m->>'name', '; ') from jsonb_array_elements(v_sim) m)));
      end if;
    end if;
  end if;

  -- 돈 칸(master 만 · 아니면 기본값)
  select coalesce(array_agg(k order by k), '{}') into v_given from unnest(v_money) as k where p_supplier ? k and p_supplier->k <> 'null'::jsonb;
  if cardinality(v_given) > 0 and not v_master then
    v_blocks := v_blocks || jsonb_build_object('key', 'money_field_not_allowed', 'code', 'money_field_not_allowed', 'message', format('Only a master user can set %s on a new supplier — leave them out and the defaults apply — nothing was saved', array_to_string(v_given, ', ')));
  end if;
  if 'payment_term_id' = any(v_given) and v_master then
    select * into v_term from public.ref_payment_term t where t.id = (p_supplier->>'payment_term_id')::uuid and t.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'payment_term_invalid', 'code', 'payment_term_invalid', 'message', 'The payment term does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'supplier_default_payment_term';
    select * into v_term from public.ref_payment_term t where t.name = v_cfg and t.is_active;
    if v_cfg is null or not found then v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:payment_term', 'code', 'default_missing', 'message', format('The default payment term is not set up (inv_config supplier_default_payment_term = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'payment_term'); end if;
  end if;
  if 'account_payable_id' = any(v_given) and v_master then
    select * into v_acct from public.ref_account a where a.id = (p_supplier->>'account_payable_id')::uuid and a.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'account_invalid', 'code', 'account_invalid', 'message', 'The payable account does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'supplier_default_account_payable_code';
    select * into v_acct from public.ref_account a where a.code = v_cfg and a.is_active;
    if v_cfg is null or not found then v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:account_payable', 'code', 'default_missing', 'message', format('The default payable account is not set up (inv_config supplier_default_account_payable_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'account_payable'); end if;
  end if;
  if 'currency_id' = any(v_given) and v_master then
    select * into v_cur from public.ref_currency c where c.id = (p_supplier->>'currency_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'currency_invalid', 'code', 'currency_invalid', 'message', 'The currency does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'supplier_default_currency_code';
    select * into v_cur from public.ref_currency c where c.code = v_cfg and c.is_active;
    if v_cfg is null or not found then v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:currency', 'code', 'default_missing', 'message', format('The default currency is not set up (inv_config supplier_default_currency_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'currency'); end if;
  end if;
  if 'tax_rule' = any(v_given) and v_master then
    v_tax := nullif(btrim(p_supplier->>'tax_rule'), '');
  else
    select nullif(k.value, '') into v_tax from public.inv_config k where k.key = 'supplier_default_tax_rule';
    if v_tax is not null then v_defaults := array_append(v_defaults, 'tax_rule'); end if;           -- 세금 규칙은 원문 칸 · 비어도 막지 않는다(po_create 가 tax_rule_unset 알림)
  end if;
  if v_cur.id is not null and v_acct.id is not null and ((v_cur.code = 'USD') <> (v_acct.name ilike '%USD%')) then
    v_warns := v_warns || jsonb_build_object('key', 'currency_account_mismatch', 'code', 'currency_account_mismatch', 'message', format('Currency %s with payable account %s %s — check the account matches the currency. Confirm to create anyway', v_cur.code, v_acct.code, v_acct.name));
  end if;
  -- 할인(master 만 · 체인 순서 = 배열 순서)
  v_i := 0;
  for v_d in select x from jsonb_array_elements(coalesce(p_supplier->'discounts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_pct := case when (v_d->>'percent') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (v_d->>'percent')::numeric end;
    if nullif(btrim(v_d->>'name'), '') is null or v_pct is null or v_pct > 100 then
      v_blocks := v_blocks || jsonb_build_object('key', 'discount_invalid:' || v_i, 'code', 'discount_invalid', 'message', format('Discount %s needs a name and a percent from 0 to 100 — nothing was saved', v_i));
    end if;
  end loop;
  -- 일반 칸 값
  if nullif(btrim(p_supplier->>'is_purchasable'), '') is not null and btrim(p_supplier->>'is_purchasable') not in ('true', 'false') then
    v_blocks := v_blocks || jsonb_build_object('key', 'value_invalid:is_purchasable', 'code', 'value_invalid', 'message', 'is_purchasable must be true, false or null (not decided) — nothing was saved');
  end if;
  -- 주소 · 연락처
  v_i := 0;
  for v_a in select x from jsonb_array_elements(coalesce(p_supplier->'addresses', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    if nullif(btrim(coalesce(v_a->>'line1', '') || coalesce(v_a->>'city', '') || coalesce(v_a->>'postal_code', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'address_empty:' || v_i, 'code', 'address_empty', 'message', format('Address %s has no street, city or postal code — nothing was saved', v_i));
    end if;
  end loop;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_supplier->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    if nullif(btrim(coalesce(v_c->>'name', '') || coalesce(v_c->>'phone', '') || coalesce(v_c->>'mobile_phone', '') || coalesce(v_c->>'email', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'contact_empty:' || v_i, 'code', 'contact_empty', 'message', format('Contact %s has no name, phone or email — nothing was saved', v_i));
    end if;
    if coalesce((v_c->>'is_default')::boolean, false) then v_n_cdef := v_n_cdef + 1; end if;
  end loop;
  if v_n_cdef > 1 then v_blocks := v_blocks || jsonb_build_object('key', 'contact_default_many', 'code', 'contact_default_many', 'message', 'More than one contact is marked default — only one per supplier — nothing was saved'); end if;

  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'supplier_id', null, 'name', v_name, 'defaults_used', to_jsonb(v_defaults), 'address_ids', '[]'::jsonb, 'contact_ids', '[]'::jsonb,
                              'blocks', v_blocks, 'warnings', v_warns, 'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  begin
    insert into public.supplier (name, note, source, is_active, created_by, updated_by, payment_term_id, payment_term_name, account_payable_id, account_payable_code, currency_id, tax_rule, is_purchasable, is_discontinued, discontinued_on)
    values (v_name, nullif(btrim(p_supplier->>'note'), ''), 'manual', true, v_staff, v_staff, v_term.id, v_term.name, v_acct.id, v_acct.code, v_cur.id, v_tax,
            nullif(btrim(p_supplier->>'is_purchasable'), '')::boolean, coalesce((p_supplier->>'is_discontinued')::boolean, false),
            case when coalesce((p_supplier->>'is_discontinued')::boolean, false) then coalesce(nullif(p_supplier->>'discontinued_on', '')::date, public.ims_today()) end)
    returning id into v_sid;
  exception when unique_violation then
    raise exception 'Someone just created a supplier named "%" — check again — nothing was saved', v_name;
  end;
  v_i := 0;
  for v_d in select x from jsonb_array_elements(coalesce(p_supplier->'discounts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    insert into public.supplier_discount (supplier_id, name, percent, seq, source, updated_by) values (v_sid, btrim(v_d->>'name'), (v_d->>'percent')::numeric, v_i, 'manual', v_staff);
  end loop;
  for v_a in select x from jsonb_array_elements(coalesce(p_supplier->'addresses', '[]'::jsonb)) as x loop
    insert into public.supplier_address (supplier_id, source, updated_by, type, line1, line2, city, state_province, postal_code, country)
    values (v_sid, 'manual', v_staff, nullif(btrim(v_a->>'type'), ''), nullif(btrim(v_a->>'line1'), ''), nullif(btrim(v_a->>'line2'), ''), nullif(btrim(v_a->>'city'), ''), nullif(btrim(v_a->>'state_province'), ''), nullif(btrim(v_a->>'postal_code'), ''), nullif(btrim(v_a->>'country'), ''))
    returning id into v_rid;
    v_addr_ids := v_addr_ids || to_jsonb(v_rid);
  end loop;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_supplier->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    insert into public.supplier_contact (supplier_id, source, updated_by, name, phone, mobile_phone, fax, email, website, is_default)
    values (v_sid, 'manual', v_staff, nullif(btrim(v_c->>'name'), ''), nullif(btrim(v_c->>'phone'), ''), nullif(btrim(v_c->>'mobile_phone'), ''), nullif(btrim(v_c->>'fax'), ''), nullif(btrim(v_c->>'email'), ''), nullif(btrim(v_c->>'website'), ''),
            case when v_n_cdef = 1 then coalesce((v_c->>'is_default')::boolean, false) else v_i = 1 end)
    returning id into v_rid;
    v_cont_ids := v_cont_ids || to_jsonb(v_rid);
  end loop;
  return jsonb_build_object('committed', true, 'supplier_id', v_sid, 'name', v_name, 'defaults_used', to_jsonb(v_defaults), 'address_ids', v_addr_ids, 'contact_ids', v_cont_ids, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.supplier_create(jsonb, boolean, text[]) from public, anon;
grant execute on function public.supplier_create(jsonb, boolean, text[]) to authenticated;
comment on function public.supplier_create(jsonb, boolean, text[]) is
  'master-cs-3 · 판정 237 · 238 — 공급처 만들기 한 벌(공급처 + 할인들 + 주소들 + 연락처들 · 한 트랜잭션) · 문 = purchasing 또는 master 쓰기 · 두 번 부르기(p_commit · p_ack · unacked) · 돈 칸(currency_id · payment_term_id · account_payable_id · tax_rule · discounts)은 master 만 — purchasing 이 보내면 막기 money_field_not_allowed · 안 보내면 inv_config supplier_default_* 기본값 · 같은 접은 이름(꺼진 것 포함)은 막기 name_exists(이름이 열쇠) · 「(Supplier)」 뗀 이름이 같으면 알리기 name_similar · 연락처 기본 하나(표시 없으면 첫 줄) · source manual · created_by. 2026-10-05';

-- ═══ 4) 고치기 창구 ═══
--   op  set{supplier_id, field, value, old} — 일반(purchasing · master): name · note · is_purchasable(true|false|null) · is_discontinued · discontinued_on / master 만: currency_id · payment_term_id · account_payable_id · tax_rule · is_active(판정 241)
--       discount_add{supplier_id, values{name, percent}} · discount_set{supplier_id, discount_id, values{name, percent}, olds{…}} · discount_off{supplier_id, discount_id} — master 만
--       address_add{supplier_id, values{type, line1 …}} · address_set{supplier_id, address_id, values, olds} · address_off{supplier_id, address_id} · contact_add/set/off/default — purchasing · master
create or replace function public.supplier_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_master  boolean;
  v_blocks  jsonb := '[]'::jsonb;
  v_warns   jsonb := '[]'::jsonb;
  v_changes jsonb := '[]'::jsonb;
  v_money   text[] := array['currency_id', 'payment_term_id', 'account_payable_id', 'tax_rule', 'is_active'];
  v_general text[] := array['name', 'note', 'is_purchasable', 'is_discontinued', 'discontinued_on'];
  v_afields text[] := array['type', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country'];
  v_cfields text[] := array['name', 'phone', 'mobile_phone', 'fax', 'email', 'website'];
  v_mops    text[] := array['discount_add', 'discount_set', 'discount_off'];
  v_n       int;
  v_i       int := 0;
  v_c       jsonb;
  v_op      text;
  v_field   text;
  v_sid     uuid;
  v_key     text;
  v_sup     public.supplier%rowtype;
  v_cur     text;
  v_new     text;
  v_seen    text[] := '{}';
  v_touched uuid[] := '{}';
  v_money_s uuid[] := '{}';
  v_a       public.supplier_address%rowtype;
  v_ct      public.supplier_contact%rowtype;
  v_dsc     public.supplier_discount%rowtype;
  v_vals    jsonb;
  v_olds    jsonb;
  v_f       text;
  v_folded  text;
  v_open_po int;
  v_open_inv int;
  v_prods   int;
  v_forms   int;
  v_pct     numeric;
  v_keys    text[];
  v_unacked text[];
  v_rid     uuid;
  v_newdef  text[] := '{}';
begin
  if not (public.ims_can_write('purchasing') or public.ims_can_write('master')) then
    raise exception 'You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then raise exception 'p_changes must be a JSON array of changes — nothing was saved'; end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 1000 then raise exception 'Too many changes in one call (% — the limit is 1,000) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_op := v_c->>'op';
    if v_op is null or v_op not in ('set', 'discount_add', 'discount_set', 'discount_off', 'address_add', 'address_set', 'address_off', 'contact_add', 'contact_set', 'contact_off', 'contact_default') then
      raise exception 'Unknown op % — one of set · discount_add · discount_set · discount_off · address_add · address_set · address_off · contact_add · contact_set · contact_off · contact_default — nothing was saved', coalesce(v_op, '(blank)');
    end if;
    if v_op = 'contact_add' and coalesce((v_c->'values'->>'is_default')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'supplier_id', '')); end if;
    if v_op = 'contact_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'supplier_id', '')); end if;
  end loop;

  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_sid := nullif(v_c->>'supplier_id', '')::uuid; v_key := coalesce(v_sid::text, '(blank)');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'supplier_id', v_sid, 'op', v_op, 'field', v_field, 'applied', false);
    select * into v_sup from public.supplier s where s.id = v_sid;
    if v_sid is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':supplier_unknown', 'supplier_id', v_sid, 'code', 'supplier_unknown', 'message', format('Change %s: the supplier does not exist — nothing was saved', v_i)); continue;
    end if;
    v_touched := array_append(v_touched, v_sid);
    v_vals := coalesce(v_c->'values', '{}'::jsonb); v_olds := coalesce(v_c->'olds', '{}'::jsonb);

    if v_op = 'set' then
      if v_field is null or not (v_field = any(v_general) or v_field = any(v_money)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(blank)'), 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: field %s cannot be changed here — nothing was saved', v_sup.name, coalesce(v_field, '(blank)'))); continue;
      end if;
      if (v_key || ':' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s %s is changed twice in this call — keep one — nothing was saved', v_sup.name, v_field)); continue;
      end if;
      v_seen := array_append(v_seen, v_key || ':' || v_field);
      if v_field = any(v_money) and not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_field, 'supplier_id', v_sid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change %s of %s — nothing was saved', v_field, v_sup.name)); continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s %s: the old value the screen saw is missing — nothing was saved', v_sup.name, v_field)); continue;
      end if;
      v_cur := case v_field when 'name' then v_sup.name when 'note' then v_sup.note when 'is_purchasable' then v_sup.is_purchasable::text when 'is_discontinued' then v_sup.is_discontinued::text when 'discontinued_on' then v_sup.discontinued_on::text
                            when 'currency_id' then v_sup.currency_id::text when 'payment_term_id' then v_sup.payment_term_id::text when 'account_payable_id' then v_sup.account_payable_id::text when 'tax_rule' then v_sup.tax_rule when 'is_active' then v_sup.is_active::text end;
      if (case when v_field in ('is_purchasable', 'is_discontinued', 'is_active') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean) else (v_cur is distinct from nullif(v_c->>'old', '')) end) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of %s (now "%s") — check again — nothing was saved', v_field, v_sup.name, coalesce(v_cur, ''))); continue;
      end if;
      v_new := nullif(btrim(v_c->>'value'), '');
      if v_field = 'name' then
        if v_new is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'supplier_id', v_sid, 'code', 'name_missing', 'message', format('%s cannot have an empty name — nothing was saved', v_sup.name));
        else
          v_folded := lower(regexp_replace(v_new, '\s+', ' ', 'g'));
          if exists (select 1 from public.supplier s where s.id <> v_sid and lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = v_folded) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_exists', 'supplier_id', v_sid, 'code', 'name_exists', 'message', format('A supplier named "%s" already exists — the name is the key — nothing was saved', v_new));
          end if;
          v_warns := v_warns || jsonb_build_object('key', v_key || ':rename_sync_cin7', 'supplier_id', v_sid, 'code', 'rename_sync_cin7', 'message', format('Renaming %s to "%s": Cin7 refers to suppliers by name — rename it in Cin7 too (Cin7 first while both systems run). Confirm', v_sup.name, v_new));
        end if;
      elsif v_field in ('is_discontinued', 'is_active') then
        if v_new is null or v_new not in ('true', 'false') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_field, 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s %s must be true or false — nothing was saved', v_sup.name, v_field));
        elsif v_field = 'is_active' and v_new = 'false' then
          select count(*) into v_open_po from public.po p where p.supplier_id = v_sid and p.status in ('draft', 'confirmed');
          select count(*) into v_open_inv from public.po_invoice i where i.supplier_id = v_sid and i.status in ('draft', 'confirmed') and i.total_amount > coalesce((select sum(l.amount) from public.po_payment_alloc l where l.po_invoice_id = i.id), 0);
          select count(*) into v_prods from public.product_supplier ps where ps.supplier_id = v_sid and ps.is_active;
          select count(*) into v_forms from public.price_formula f where f.supplier_id = v_sid;
          if v_open_po > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_po', 'supplier_id', v_sid, 'code', 'inactive_open_po', 'count', v_open_po, 'message', format('%s has %s open purchase order(s) — they keep running. Confirm to deactivate', v_sup.name, v_open_po)); end if;
          if v_open_inv > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_invoice', 'supplier_id', v_sid, 'code', 'inactive_open_invoice', 'count', v_open_inv, 'message', format('%s has %s supplier invoice(s) not fully paid — confirm to deactivate', v_sup.name, v_open_inv)); end if;
          if v_prods > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_products', 'supplier_id', v_sid, 'code', 'inactive_products', 'count', v_prods, 'message', format('%s is linked to %s product(s) (supplier lines stay) — confirm to deactivate', v_sup.name, v_prods)); end if;
          if v_forms > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_formulas', 'supplier_id', v_sid, 'code', 'inactive_formulas', 'count', v_forms, 'message', format('%s has %s price formula(s) — confirm to deactivate', v_sup.name, v_forms)); end if;
        end if;
      elsif v_field = 'is_purchasable' then
        if v_new is not null and v_new not in ('true', 'false') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_purchasable', 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s: is_purchasable must be true, false or empty (not decided) — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'discontinued_on' then
        if v_new is not null and v_new !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:discontinued_on', 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s: discontinued_on must be a date (YYYY-MM-DD) or empty — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'payment_term_id' then
        if v_new is null or not exists (select 1 from public.ref_payment_term t where t.id = v_new::uuid and t.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':payment_term_invalid', 'supplier_id', v_sid, 'code', 'payment_term_invalid', 'message', format('%s: the payment term does not exist or is inactive — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'account_payable_id' then
        if v_new is null or not exists (select 1 from public.ref_account a where a.id = v_new::uuid and a.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':account_invalid', 'supplier_id', v_sid, 'code', 'account_invalid', 'message', format('%s: the payable account does not exist or is inactive — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'currency_id' then
        if v_new is null or not exists (select 1 from public.ref_currency r where r.id = v_new::uuid and r.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_invalid', 'supplier_id', v_sid, 'code', 'currency_invalid', 'message', format('%s: the currency does not exist or is inactive — nothing was saved', v_sup.name));
        elsif ((select r.code from public.ref_currency r where r.id = v_new::uuid) = 'USD') <> (coalesce((select a.name from public.ref_account a where a.id = v_sup.account_payable_id), '') ilike '%USD%') then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':currency_account_mismatch', 'supplier_id', v_sid, 'code', 'currency_account_mismatch', 'message', format('%s: the payable account %s may not match the new currency — check it. Confirm', v_sup.name, coalesce(v_sup.account_payable_code, '?')));
        end if;
      end if;
      if v_field = any(v_money) and v_field <> 'is_active' then v_money_s := array_append(v_money_s, v_sid); end if;

    elsif v_op = any(v_mops) then
      if not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_op, 'supplier_id', v_sid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change the discounts of %s — nothing was saved', v_sup.name)); continue;
      end if;
      if v_op = 'discount_add' then
        v_pct := case when (v_vals->>'percent') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (v_vals->>'percent')::numeric end;
        if nullif(btrim(v_vals->>'name'), '') is null or v_pct is null or v_pct > 100 then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid:' || v_i, 'supplier_id', v_sid, 'code', 'discount_invalid', 'message', format('%s: a discount needs a name and a percent from 0 to 100 — nothing was saved', v_sup.name)); end if;
      else
        select * into v_dsc from public.supplier_discount d where d.id = nullif(v_c->>'discount_id', '')::uuid and d.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'discount_unknown', 'message', format('%s: that discount line is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':discount:' || v_dsc.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:discount:' || v_dsc.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same discount line is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':discount:' || v_dsc.id::text);
        if v_op = 'discount_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if v_f not in ('name', 'percent') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:discount.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: discount field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:discount.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: discount %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            if (case when v_f = 'percent' then (v_dsc.percent is distinct from nullif(v_olds->>v_f, '')::numeric) else (v_dsc.name is distinct from nullif(v_olds->>v_f, '')) end) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:discount.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the discount %s of %s — check again — nothing was saved', v_f, v_sup.name));
            end if;
          end loop;
          if v_vals ? 'percent' and not ((v_vals->>'percent') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' and (v_vals->>'percent')::numeric <= 100) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid:' || v_i, 'supplier_id', v_sid, 'code', 'discount_invalid', 'message', format('%s: percent must be 0 to 100 — nothing was saved', v_sup.name)); end if;
        elsif v_op = 'discount_off' and not v_dsc.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'discount_inactive', 'message', format('%s: that discount line is already off — nothing was saved', v_sup.name));
        end if;
      end if;
      v_money_s := array_append(v_money_s, v_sid);

    elsif v_op like 'address_%' then
      if v_op = 'address_add' then
        if nullif(btrim(coalesce(v_vals->>'line1', '') || coalesce(v_vals->>'city', '') || coalesce(v_vals->>'postal_code', '')), '') is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_empty:' || v_i, 'supplier_id', v_sid, 'code', 'address_empty', 'message', format('%s: the new address has no street, city or postal code — nothing was saved', v_sup.name)); end if;
      else
        select * into v_a from public.supplier_address a where a.id = nullif(v_c->>'address_id', '')::uuid and a.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'address_unknown', 'message', format('%s: that address is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':address:' || v_a.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:address:' || v_a.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same address is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':address:' || v_a.id::text);
        if v_op = 'address_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_afields)) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:address.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: address field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:address.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: address %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            v_cur := case v_f when 'type' then v_a.type when 'line1' then v_a.line1 when 'line2' then v_a.line2 when 'city' then v_a.city when 'state_province' then v_a.state_province when 'postal_code' then v_a.postal_code else v_a.country end;
            if v_cur is distinct from nullif(v_olds->>v_f, '') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:address.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the address %s of %s (now "%s") — check again — nothing was saved', v_f, v_sup.name, coalesce(v_cur, ''))); end if;
          end loop;
        elsif v_op = 'address_off' and not v_a.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'address_inactive', 'message', format('%s: that address is already off — nothing was saved', v_sup.name));
        end if;
      end if;

    else
      if v_op = 'contact_add' then
        if nullif(btrim(coalesce(v_vals->>'name', '') || coalesce(v_vals->>'phone', '') || coalesce(v_vals->>'mobile_phone', '') || coalesce(v_vals->>'email', '')), '') is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_empty:' || v_i, 'supplier_id', v_sid, 'code', 'contact_empty', 'message', format('%s: the new contact has no name, phone or email — nothing was saved', v_sup.name)); end if;
      else
        select * into v_ct from public.supplier_contact k where k.id = nullif(v_c->>'contact_id', '')::uuid and k.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'contact_unknown', 'message', format('%s: that contact is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':contact:' || v_ct.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:contact:' || v_ct.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same contact is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':contact:' || v_ct.id::text);
        if v_op = 'contact_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_cfields)) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:contact.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: contact field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:contact.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: contact %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            v_cur := case v_f when 'name' then v_ct.name when 'phone' then v_ct.phone when 'mobile_phone' then v_ct.mobile_phone when 'fax' then v_ct.fax when 'email' then v_ct.email else v_ct.website end;
            if v_cur is distinct from nullif(v_olds->>v_f, '') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:contact.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the contact %s of %s (now "%s") — check again — nothing was saved', v_f, v_sup.name, coalesce(v_cur, ''))); end if;
          end loop;
        elsif v_op = 'contact_off' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'contact_inactive', 'message', format('%s: that contact is already off — nothing was saved', v_sup.name));
          elsif v_ct.is_default and not (v_key = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':contact_default_off', 'supplier_id', v_sid, 'code', 'contact_default_off', 'message', format('%s: this is the default contact — switching it off leaves no default (po_create will warn contact_unset). Confirm', v_sup.name)); end if;
        elsif v_op = 'contact_default' and not v_ct.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'contact_inactive', 'message', format('%s: an inactive contact cannot be the default — switch it on first — nothing was saved', v_sup.name));
        end if;
      end if;
    end if;
  end loop;

  for v_sid in select distinct u from unnest(v_money_s) as u loop
    select count(*), max(s.name) into v_open_po, v_cur from public.po p join public.supplier s on s.id = p.supplier_id where p.supplier_id = v_sid and p.status in ('draft', 'confirmed');
    if v_open_po > 0 then v_warns := v_warns || jsonb_build_object('key', v_sid::text || ':open_po_keep_old', 'supplier_id', v_sid, 'code', 'open_po_keep_old', 'count', v_open_po, 'message', format('%s has %s open purchase order(s) — they keep the old terms; only new orders get the change. Confirm', v_cur, v_open_po)); end if;
  end loop;

  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  begin
    perform 1 from public.supplier s where s.id = any(v_touched) for update;
    v_i := 0;
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_sid := (v_c->>'supplier_id')::uuid; v_new := nullif(btrim(v_c->>'value'), ''); v_vals := coalesce(v_c->'values', '{}'::jsonb);
      if v_op = 'set' then
        case v_field
          when 'name' then update public.supplier set name = v_new, updated_by = v_staff where id = v_sid;
          when 'note' then update public.supplier set note = v_new, updated_by = v_staff where id = v_sid;
          when 'is_purchasable' then update public.supplier set is_purchasable = v_new::boolean, updated_by = v_staff where id = v_sid;
          when 'is_discontinued' then update public.supplier set is_discontinued = v_new::boolean, discontinued_on = case when v_new::boolean then coalesce(discontinued_on, public.ims_today()) else null end, updated_by = v_staff where id = v_sid;
          when 'discontinued_on' then update public.supplier set discontinued_on = v_new::date, updated_by = v_staff where id = v_sid;
          when 'currency_id' then update public.supplier set currency_id = v_new::uuid, updated_by = v_staff where id = v_sid;
          when 'payment_term_id' then update public.supplier set payment_term_id = v_new::uuid, payment_term_name = (select t.name from public.ref_payment_term t where t.id = v_new::uuid), updated_by = v_staff where id = v_sid;
          when 'account_payable_id' then update public.supplier set account_payable_id = v_new::uuid, account_payable_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_sid;
          when 'tax_rule' then update public.supplier set tax_rule = v_new, updated_by = v_staff where id = v_sid;
          when 'is_active' then update public.supplier set is_active = v_new::boolean, updated_by = v_staff where id = v_sid;
        end case;
      elsif v_op = 'discount_add' then
        insert into public.supplier_discount (supplier_id, name, percent, seq, source, updated_by)
        values (v_sid, btrim(v_vals->>'name'), (v_vals->>'percent')::numeric, (select coalesce(max(d.seq), 0) + 1 from public.supplier_discount d where d.supplier_id = v_sid), 'manual', v_staff) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'discount_set' then
        update public.supplier_discount d set name = case when v_vals ? 'name' then btrim(v_vals->>'name') else d.name end, percent = case when v_vals ? 'percent' then (v_vals->>'percent')::numeric else d.percent end, updated_by = v_staff where d.id = (v_c->>'discount_id')::uuid;
      elsif v_op = 'discount_off' then
        update public.supplier_discount set is_active = false, updated_by = v_staff where id = (v_c->>'discount_id')::uuid;
      elsif v_op = 'address_add' then
        insert into public.supplier_address (supplier_id, source, updated_by, type, line1, line2, city, state_province, postal_code, country)
        values (v_sid, 'manual', v_staff, nullif(btrim(v_vals->>'type'), ''), nullif(btrim(v_vals->>'line1'), ''), nullif(btrim(v_vals->>'line2'), ''), nullif(btrim(v_vals->>'city'), ''), nullif(btrim(v_vals->>'state_province'), ''), nullif(btrim(v_vals->>'postal_code'), ''), nullif(btrim(v_vals->>'country'), '')) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'address_set' then
        update public.supplier_address a set
          type = case when v_vals ? 'type' then nullif(btrim(v_vals->>'type'), '') else a.type end, line1 = case when v_vals ? 'line1' then nullif(btrim(v_vals->>'line1'), '') else a.line1 end, line2 = case when v_vals ? 'line2' then nullif(btrim(v_vals->>'line2'), '') else a.line2 end,
          city = case when v_vals ? 'city' then nullif(btrim(v_vals->>'city'), '') else a.city end, state_province = case when v_vals ? 'state_province' then nullif(btrim(v_vals->>'state_province'), '') else a.state_province end,
          postal_code = case when v_vals ? 'postal_code' then nullif(btrim(v_vals->>'postal_code'), '') else a.postal_code end, country = case when v_vals ? 'country' then nullif(btrim(v_vals->>'country'), '') else a.country end, updated_by = v_staff
        where a.id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_off' then
        update public.supplier_address set is_active = false, updated_by = v_staff where id = (v_c->>'address_id')::uuid;
      elsif v_op = 'contact_add' then
        if coalesce((v_vals->>'is_default')::boolean, false) then update public.supplier_contact set is_default = false, updated_by = v_staff where supplier_id = v_sid and is_default; end if;
        insert into public.supplier_contact (supplier_id, source, updated_by, name, phone, mobile_phone, fax, email, website, is_default)
        values (v_sid, 'manual', v_staff, nullif(btrim(v_vals->>'name'), ''), nullif(btrim(v_vals->>'phone'), ''), nullif(btrim(v_vals->>'mobile_phone'), ''), nullif(btrim(v_vals->>'fax'), ''), nullif(btrim(v_vals->>'email'), ''), nullif(btrim(v_vals->>'website'), ''), coalesce((v_vals->>'is_default')::boolean, false)) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'contact_set' then
        update public.supplier_contact k set
          name = case when v_vals ? 'name' then nullif(btrim(v_vals->>'name'), '') else k.name end, phone = case when v_vals ? 'phone' then nullif(btrim(v_vals->>'phone'), '') else k.phone end, mobile_phone = case when v_vals ? 'mobile_phone' then nullif(btrim(v_vals->>'mobile_phone'), '') else k.mobile_phone end,
          fax = case when v_vals ? 'fax' then nullif(btrim(v_vals->>'fax'), '') else k.fax end, email = case when v_vals ? 'email' then nullif(btrim(v_vals->>'email'), '') else k.email end, website = case when v_vals ? 'website' then nullif(btrim(v_vals->>'website'), '') else k.website end, updated_by = v_staff
        where k.id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_off' then
        update public.supplier_contact set is_active = false, is_default = false, updated_by = v_staff where id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_default' then
        update public.supplier_contact k set is_default = (k.id = (v_c->>'contact_id')::uuid), updated_by = v_staff where k.supplier_id = v_sid and k.is_active and (k.is_default or k.id = (v_c->>'contact_id')::uuid);
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'A name or default would collide (%) — check the supplier name and keep one default contact — nothing was saved', coalesce(sqlerrm, '');
  end;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.supplier_update(jsonb, boolean, text[]) from public, anon;
grant execute on function public.supplier_update(jsonb, boolean, text[]) to authenticated;
comment on function public.supplier_update(jsonb, boolean, text[]) is
  'master-cs-3 · 판정 237 · 238 · 241 — 공급처 고치기 창구 하나(customer_update 모양): p_changes 줄 = {supplier_id, op, …} · op 열하나 = set(field · value · old) · discount_add/set/off(master) · address_add/set/off · contact_add/set/off/default · 문 = purchasing 또는 master 쓰기 · 돈 칸(currency_id · payment_term_id · account_payable_id · tax_rule · 할인 op · is_active)은 master 만(money_field_not_allowed) · 줄마다 old 대조(changed_elsewhere · old_missing · field_duplicate_in_call) · 바꾸는 칸의 새 값만 검사 · 이름 바꾸기는 접은 이름 충돌이면 막기(name_exists) + Cin7 에도 바꾸라는 알림(rename_sync_cin7) · 끄기는 열린 PO · 미지급 인보이스 · 상품 연결 · 가격식 알리기 · 돈 칸 · 할인을 바꾸면 열린 PO 수 알리기(옛 값 그대로) · suppliers.html 의 is_purchasable 토글은 set is_purchasable 한 줄. 2026-10-05';

-- ═══ 5) 공급처 표 넷 닫기 — cs-1 모양(정책 drop + revoke insert · update · delete · select 그대로 · 잠그는 invoker 창구 없음 ⇒ 완전히) ═══
drop policy if exists supplier_insert on public.supplier;
drop policy if exists supplier_update on public.supplier;
drop policy if exists supplier_delete on public.supplier;
revoke insert, update, delete on public.supplier from authenticated;
drop policy if exists supplier_address_insert on public.supplier_address;
drop policy if exists supplier_address_update on public.supplier_address;
drop policy if exists supplier_address_delete on public.supplier_address;
revoke insert, update, delete on public.supplier_address from authenticated;
drop policy if exists supplier_contact_insert on public.supplier_contact;
drop policy if exists supplier_contact_update on public.supplier_contact;
drop policy if exists supplier_contact_delete on public.supplier_contact;
revoke insert, update, delete on public.supplier_contact from authenticated;
drop policy if exists supplier_discount_insert on public.supplier_discount;
drop policy if exists supplier_discount_update on public.supplier_discount;
drop policy if exists supplier_discount_delete on public.supplier_discount;
revoke insert, update, delete on public.supplier_discount from authenticated;

-- ═══ 6) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_t text; v_bad text := '';
begin
  foreach v_t in array array['supplier', 'supplier_address', 'supplier_contact', 'supplier_discount'] loop
    if (select count(*) from pg_policies where schemaname = 'public' and tablename = v_t) <> 1
       or not exists (select 1 from pg_policies where schemaname = 'public' and tablename = v_t and cmd = 'SELECT')
       or has_table_privilege('authenticated', format('public.%I', v_t), 'insert') or has_table_privilege('authenticated', format('public.%I', v_t), 'update') or has_table_privilege('authenticated', format('public.%I', v_t), 'delete')
       or has_any_column_privilege('authenticated', format('public.%I', v_t), 'update') or not has_table_privilege('authenticated', format('public.%I', v_t), 'select')
       or not (has_table_privilege('service_role', format('public.%I', v_t), 'insert') and has_table_privilege('service_role', format('public.%I', v_t), 'update')) then
      v_bad := v_bad || ' ' || v_t;
    end if;
  end loop;
  if (select count(*) from public.inv_config where key like 'supplier\_default\_%') <> 4 then v_bad := v_bad || ' inv_config(defaults)'; end if;
  if to_regprocedure('public.supplier_create(jsonb, boolean, text[])') is null or to_regprocedure('public.supplier_update(jsonb, boolean, text[])') is null or to_regprocedure('public.customer_update(jsonb, boolean, text[])') is null then v_bad := v_bad || ' functions'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM241', message = format('STOP - the supplier door is not closed as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
