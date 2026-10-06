-- ─────────────────────────────────────────────────────────────
-- 손님 부모 · 자식 관계와 청구처를 IMS 에서 세우고 없앤다 — DB 차수 (Asung-IMS · cs-par-1 · 2026-10-06)
--   정본(뒤에 적는다): so-module — 판정 251 ~ 255 · cs-par-1 이견 1 ~ 13(전부 채택) · 5-a(600 ~ 625행 칸 설명) · 9-i 판정 ⑫(1955 ~ 1975행 적재 두 단계) · §17 판정 2(3123행 청구처) · 42-e 미룬 96
--   원칙(Caleb 2026-10-06): 부모 · 자식 관계와 청구처는 IMS 에서 세우고 없앤다 — 적재(ImsLoadCustomer)는 불러오는 데이터일 뿐이다
--   판정 251  청구처 규칙은 customer.default_bill_to_customer_id 한 칸(null = 자기 자신) · is_bill_parent 는 규칙에 쓰지 않는다 · 지금 is_bill_parent 이고 부모가 있는데 청구처가 빈 손님은 청구처를 부모로 한 번 채운다(6절 · 실측 12)
--   판정 252  parent_id · default_bill_to_customer_id 를 바꾸는 것은 master(돈 칸과 같은 문) — customer_update 는 v_struct(parent_id) 로 문만 같이 걸고 reviewed · open_so_keep_old 는 걸지 않는다(이견 5) · customer_create 도 parent_id 는 master 만
--   판정 253  customer.parent_source text(null · cin7 · ims) — 창구가 세우거나 바꾸면 ims · 비우면 null · 채우기는 지금 부모 있는 13행 cin7 · 적재 2단계가 ims 를 덮지 않게 하는 것은 GAS 차수(이 파일은 GAS 를 건드리지 않는다)
--   판정 254  is_bill_parent 를 customer_update · customer_create 에서 뺀다 — 적재가 매 upsert 마다 Cin7 값으로 덮으므로(ImsLoadCustomer.gs 323행) IMS 에서 고칠 수 있다는 것은 거짓 약속이었다 · 받은 값을 비춰 둘 뿐
--   판정 255  자기 자신은 null 하나로 표기한다 — parent_id · default_bill_to_customer_id · default_ship_to_customer_id 모두 <> id CHECK(청구는 부모 · 배송은 자기(null) 조합은 그대로 된다)
--   규칙 1  깊이는 하나 — 자식은 부모가 될 수 없고 자식이 있는 손님은 다른 손님의 자식이 될 수 없다 → 창구(parent_has_parent · 이미 있었다) + 트리거 customer_parent_guard(적재 · 손 SQL 어느 길로 써도 막힌다)
--   규칙 2  자기 자신을 부모 · 청구처 · 배송지로 둘 수 없다 → CHECK 셋 + 창구(parent_self · bill_to_self · ship_to_self)
--   규칙 3  꺼진 손님은 부모 · 청구처 · 배송지로 새로 고를 수 없다 → 창구만(parent_unknown · bill_to_unknown · ship_to_unknown · 이미 있었다) — 트리거는 보지 않는다(업무 규칙)
--   규칙 4  부모를 비우거나 바꿀 때 청구처가 그 옛 부모면 null 로 돌린다 → 트리거가 모든 길에서 수행(적재 2단계 「비우기」 PATCH 도 지난다 · 이견 3) · 창구는 ack 알림 bill_to_reset_with_parent · 같은 호출이 옛 부모를 청구처로 다시 보내면 막기 bill_to_is_old_parent(이견 7)
--   규칙 5  청구처를 바꿔도 이미 만든 오더는 그대로 — so_copy_customer(20260924200029:147 · 203)가 coalesce(default_bill_to_customer_id, id) 를 so.bill_to_customer_id 에 굳히고 so_create · so_header_update 만 부른다 · 이 파일은 so 를 건드리지 않는다
--   재발행 둘 — customer_update(마지막 정의 20261005164835:46 ~ 471) · customer_create(20261005161145:71 ~ 357) · 원본과 diff 는 보고에(바뀐 줄마다 이유) · 시그니처 그대로(create or replace · grant · comment 다시)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
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

-- ═══ 1) 판정 253 — parent_source 칸 ═══
alter table public.customer add column if not exists parent_source text;
alter table public.customer add constraint customer_parent_source_ck check (parent_source is null or parent_source in ('cin7', 'ims'));
comment on column public.customer.parent_source is '⭐ 판정 253(cs-par-1 · 2026-10-06) — 이 부모 관계를 누가 세웠나: ims(창구 customer_update · customer_create) · cin7(적재 2단계 · 채우기 13행) · null(부모 없음 — 트리거가 parent_id 가 비면 함께 비운다 · 적재가 세웠는데 아직 표기 전) · 적재 2단계는 cin7 인 것만 잇고 비우도록 고친다(GAS 차수 · 그 전까지 적재는 이 칸을 모른다)';

-- ═══ 2) 규칙 2 · 판정 255 — 자기 자신은 null 하나로 표기한다(CHECK 셋 · 실측 자기 참조 0 · 0 · 0) ═══
alter table public.customer add constraint customer_parent_not_self_ck  check (parent_id is null or parent_id <> id);
alter table public.customer add constraint customer_bill_to_not_self_ck check (default_bill_to_customer_id is null or default_bill_to_customer_id <> id);
alter table public.customer add constraint customer_ship_to_not_self_ck check (default_ship_to_customer_id is null or default_ship_to_customer_id <> id);
comment on constraint customer_parent_not_self_ck  on public.customer is '규칙 2(cs-par-1) — 자기 자신을 부모로 둘 수 없다 · 창구는 parent_self 로 먼저 막는다';
comment on constraint customer_bill_to_not_self_ck on public.customer is '규칙 2 · 판정 255(cs-par-1) — 자기 자신이 청구처면 null 로 표기한다 · 창구는 bill_to_self 로 먼저 막는다';
comment on constraint customer_ship_to_not_self_ck on public.customer is '규칙 2 · 판정 255(cs-par-1) — 자기 자신이 배송지면 null 로 표기한다 · 창구는 ship_to_self 로 먼저 막는다 · 청구는 부모 · 배송은 자기(null) 조합은 그대로 된다';

-- ═══ 3) 규칙 1 · 4 — 트리거 customer_parent_guard(parent_id 를 쓰는 모든 길: 창구 · 적재 PATCH · 손 SQL) ═══
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
  -- 판정 253 — 부모가 없으면 parent_source 도 없다(어느 길로 비워도)
  if new.parent_id is null then
    new.parent_source := null;
  end if;
  return new;
end;
$$;
revoke all on function public.customer_parent_guard() from public, anon;
comment on function public.customer_parent_guard() is 'customer BEFORE INSERT OR UPDATE OF parent_id 트리거(cs-par-1 · 2026-10-06) — 규칙 1 깊이 하나(새 부모가 자식 · 내게 자식 → 거부 · 창구 parent_has_parent 의 밑단) · 규칙 4 부모를 비우거나 바꿀 때 default_bill_to_customer_id 가 옛 부모면 null(창구는 bill_to_reset_with_parent 로 먼저 알린다 · 적재 2단계 비우기 PATCH 도 지난다) · 판정 253 parent_id 가 비면 parent_source 도 null · inactive · 권한은 보지 않는다(창구 일) · 적재 1단계 upsert 는 parent_id 를 안 보내 바로 지나간다 · 2단계 같은 값 PATCH 는 통과(실측 깊이 2+ 0)';
drop trigger if exists customer_parent_guard on public.customer;
create trigger customer_parent_guard before insert or update of parent_id on public.customer for each row execute function public.customer_parent_guard();
comment on trigger customer_parent_guard on public.customer is 'cs-par-1 규칙 1 · 4 · 판정 253 — 함수 주석 참조';

-- ═══ 4) customer_update 재발행 — 마지막 정의 20261005164835:46 ~ 471 · 바뀐 줄 9 + 뺀 줄 1 + 더한 줄 13(보고의 diff) ═══
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
  v_money    text[] := array['price_tier', 'discount_pct', 'payment_term_id', 'currency_id', 'ar_account_id', 'sale_account_id', 'default_bill_to_customer_id', 'invoice_split_by_store', 'is_active'];   -- 판정 241(cs-3): 켜기 · 끄기도 master 만 · 판정 254(cs-par-1): is_bill_parent 는 뺐다(받은 값을 비춰 둘 뿐 · 적재가 매번 덮는다)
  v_general  text[] := array['name', 'display_name', 'note', 'tax_rule', 'default_location_id', 'default_carrier', 'tax_number', 'tags', 'is_legal_entity', 'default_ship_to_customer_id'];   -- 판정 252(cs-par-1): parent_id 는 v_struct 로
  v_struct   text[] := array['parent_id'];   -- cs-par-1 판정 252(이견 5) — 문은 master(돈 칸과 같은 문) · 저장은 reviewed · open_so_keep_old 경고 없이(오더에 복사되는 조건이 아니다)
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
      if v_field is null or not (v_field = any(v_general) or v_field = any(v_money) or v_field = any(v_struct)) then
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
        when 'invoice_split_by_store' then v_cust.invoice_split_by_store::text end;
      if (case when v_field = 'discount_pct' then (v_cur::numeric is distinct from nullif(v_c->>'old', '')::numeric)
               when v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean)
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
      elsif v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store') then
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
  'master-cs-2b · 판정 237 · 238 · 240 — 손님 고치기 창구 하나(product_update 모양): p_changes = 바꿀 것 목록(한 호출에 손님 여럿 · 최대 1,000 줄 · 줄 = {customer_id, op, …}) · op 아홉 = set(field · value · old) · address_add/set/off/default · contact_add/set/off/default · 문 = sales 또는 master 쓰기 · 돈 칸 여덟 + is_active(판정 241)(price_tier · discount_pct · payment_term_id · currency_id · ar_account_id · sale_account_id · default_bill_to_customer_id · invoice_split_by_store)의 set 은 master 만(money_field_not_allowed) · ⭐ cs-par-1(2026-10-06 · 판정 251 ~ 255 · 원본 20261005164835): parent_id 도 master 만(판정 252 · 같은 code · reviewed · open_so_keep_old 는 없다) · 부모 저장은 parent_source = ims(비우면 null · 판정 253) · 부모 깊이 하나 · 자기 자신 금지(parent_self · parent_has_parent 양방향 — 트리거 customer_parent_guard 가 모든 길에서 다시 막는다) · 꺼진 손님은 부모 · 청구처 · 배송지로 못 고른다(parent_unknown · bill_to_unknown · ship_to_unknown) · 규칙 4: 부모를 비우거나 바꿀 때 청구처가 옛 부모면 알림 bill_to_reset_with_parent(ack · 트리거가 null 로 돌린다) · 같은 호출이 옛 부모를 청구처로 보내면 막기 bill_to_is_old_parent · 자기 자신을 청구처 · 배송지로 보내면 막기 bill_to_self · ship_to_self(null 하나로 표기 · 판정 255) · is_bill_parent 는 더 고치지 못한다(판정 254 · field_unknown · 받은 값을 비춰 둘 뿐 · 청구처 규칙은 default_bill_to_customer_id 한 칸 · 판정 251) · 줄마다 old 대조(changed_elsewhere · old_missing · field_duplicate_in_call) · 두 번 부르기(p_commit · p_ack · unacked) · 바꾸는 칸의 새 값만 검사(옛 꺼진 참조는 막지 않는다) · 이름 바꾸기 · 켜기는 같은 접은 이름 알리기 · 끄기는 열린 SO · 미수 · 잔액 · 자식 알리기 · 돈 칸 · 주소를 바꾸면 열린 SO 수 알리기(옛 값 그대로) · 기본 옮기기는 한 문장(deferrable) · master 의 돈 칸 저장은 reviewed_by/at(처음만 · reviewed_now). 2026-10-06';

-- ═══ 5) customer_create 재발행 — 마지막 정의 20261005161145:71 ~ 357 · 바뀐 줄 4 + 더한 줄 1(보고의 diff) ═══
create or replace function public.customer_create(p_customer jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_master    boolean;
  v_blocks    jsonb := '[]'::jsonb;
  v_warns     jsonb := '[]'::jsonb;
  v_defaults  text[] := '{}';
  v_name      text;
  v_folded    text;
  v_matches   jsonb;
  v_n_active  int;
  v_n_off     int;
  v_money     text[] := array['price_tier', 'discount_pct', 'payment_term_id', 'currency_id', 'ar_account_id', 'sale_account_id', 'default_bill_to_customer_id', 'invoice_split_by_store'];   -- 판정 254(cs-par-1): is_bill_parent 는 받지 않는다(보내도 무시 · 늘 false)
  v_given     text[];
  v_k         text;
  v_tier      public.ref_price_tier%rowtype;
  v_term      public.ref_payment_term%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_ar        public.ref_account%rowtype;
  v_sale      public.ref_account%rowtype;
  v_wh        public.ref_warehouse%rowtype;
  v_parent    public.customer%rowtype;
  v_other     public.customer%rowtype;
  v_disc      numeric;
  v_cfg       text;
  v_a         jsonb;
  v_c         jsonb;
  v_i         int;
  v_type      text;
  v_def_types text[] := '{}';
  v_has_ship  boolean := false;
  v_has_bill  boolean := false;
  v_n_cdef    int := 0;
  v_consent   boolean;
  v_consent_t text;
  v_cid       uuid;
  v_aid       uuid;
  v_addr_ids  jsonb := '[]'::jsonb;
  v_cont_ids  jsonb := '[]'::jsonb;
  v_keys      text[];
  v_unacked   text[];
  v_first_def_by_type jsonb := '{}'::jsonb;
begin
  -- ⭐ 문(판정 237) — sales 또는 master 쓰기 · 문장은 ims_require_write 와 같은 모양(sales 를 이름한다)
  if not (public.ims_can_write('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- ① 모양
  if p_customer is null or jsonb_typeof(p_customer) <> 'object' then
    raise exception 'p_customer must be a JSON object — nothing was saved';
  end if;
  if p_customer ? 'addresses' and jsonb_typeof(p_customer->'addresses') <> 'array' then raise exception 'addresses must be a JSON array — nothing was saved'; end if;
  if p_customer ? 'contacts'  and jsonb_typeof(p_customer->'contacts')  <> 'array' then raise exception 'contacts must be a JSON array — nothing was saved'; end if;

  -- ② 이름 · 같은 이름(판정 238)
  v_name := nullif(btrim(p_customer->>'name'), '');
  if v_name is null then
    v_blocks := v_blocks || jsonb_build_object('key', 'name_missing', 'code', 'name_missing', 'message', 'The customer has no name — nothing was saved');
  else
    v_folded := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
    select count(*) filter (where c.is_active), count(*) filter (where not c.is_active),
           coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'is_active', c.is_active, 'city', (select a.city from public.customer_address a where a.customer_id = c.id and a.is_active order by (a.type = 'Shipping') desc, a.is_default_for_type desc, a.created_at limit 1))
                              order by c.is_active desc, c.created_at) filter (where c.rn <= 5), '[]'::jsonb)
      into v_n_active, v_n_off, v_matches
      from (select c0.*, row_number() over (order by c0.is_active desc, c0.created_at) as rn from public.customer c0 where lower(regexp_replace(btrim(c0.name), '\s+', ' ', 'g')) = v_folded) c;
    if v_n_active > 0 then
      v_warns := v_warns || jsonb_build_object('key', 'name_exists', 'code', 'name_exists', 'matches', v_matches,
        'message', format('%s active customer(s) already have this name (%s) — is this really a new customer? Confirm to create it anyway', v_n_active, (select string_agg(coalesce(m->>'name', '') || coalesce(' · ' || (m->>'city'), ''), '; ') from jsonb_array_elements(v_matches) m where (m->>'is_active')::boolean)));
    elsif v_n_off > 0 then
      v_warns := v_warns || jsonb_build_object('key', 'name_matches_inactive', 'code', 'name_matches_inactive', 'matches', v_matches,
        'message', format('%s inactive customer(s) have this name — reactivating one may be better than a new row. Confirm to create a new customer', v_n_off));
    end if;
  end if;

  -- ③ 돈 칸(판정 237 · 239) — 요청에 든 돈 칸 목록
  select coalesce(array_agg(k order by k), '{}') into v_given from unnest(v_money) as k where p_customer ? k and p_customer->k <> 'null'::jsonb;
  if cardinality(v_given) > 0 and not v_master then
    v_blocks := v_blocks || jsonb_build_object('key', 'money_field_not_allowed', 'code', 'money_field_not_allowed',
      'message', format('Only a master user can set %s on a new customer — leave them out and the defaults apply (a master user reviews them later) — nothing was saved', array_to_string(v_given, ', ')));
  end if;

  -- 티어
  if 'price_tier' = any(v_given) and v_master then
    select * into v_tier from public.ref_price_tier t where t.name = btrim(p_customer->>'price_tier') and t.is_active and t.purpose = 'sale';
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'tier_invalid', 'code', 'tier_invalid', 'message', format('Price tier %s does not exist, is inactive or is not a sale tier — nothing was saved', p_customer->>'price_tier')); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_price_tier';
    select * into v_tier from public.ref_price_tier t where t.name = v_cfg and t.is_active and t.purpose = 'sale';
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:price_tier', 'code', 'default_missing', 'message', format('The default price tier is not set up (inv_config customer_default_price_tier = %s) — ask a master user to fix the default or to create this customer — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'price_tier'); end if;
  end if;
  -- 할인
  if 'discount_pct' = any(v_given) and v_master then
    v_disc := case when (p_customer->>'discount_pct') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (p_customer->>'discount_pct')::numeric end;
    if v_disc is null or v_disc > 100 then v_blocks := v_blocks || jsonb_build_object('key', 'discount_invalid', 'code', 'discount_invalid', 'message', format('discount_pct must be a number from 0 to 100 (got %s) — nothing was saved', p_customer->>'discount_pct')); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_discount_pct';
    v_disc := case when v_cfg ~ '^[0-9]+(\.[0-9]+)?$' and v_cfg::numeric <= 100 then v_cfg::numeric end;
    if v_disc is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:discount_pct', 'code', 'default_missing', 'message', format('The default discount is not set up (inv_config customer_default_discount_pct = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'discount_pct'); end if;
  end if;
  -- 결제조건
  if 'payment_term_id' = any(v_given) and v_master then
    select * into v_term from public.ref_payment_term t where t.id = (p_customer->>'payment_term_id')::uuid and t.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'payment_term_invalid', 'code', 'payment_term_invalid', 'message', 'The payment term does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_payment_term';
    select * into v_term from public.ref_payment_term t where t.name = v_cfg and t.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:payment_term', 'code', 'default_missing', 'message', format('The default payment term is not set up (inv_config customer_default_payment_term = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'payment_term'); end if;
  end if;
  -- 통화
  if 'currency_id' = any(v_given) and v_master then
    select * into v_cur from public.ref_currency c where c.id = (p_customer->>'currency_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'currency_invalid', 'code', 'currency_invalid', 'message', 'The currency does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_currency_code';
    select * into v_cur from public.ref_currency c where c.code = v_cfg and c.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:currency', 'code', 'default_missing', 'message', format('The default currency is not set up (inv_config customer_default_currency_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'currency'); end if;
  end if;
  -- 계정 둘
  if 'ar_account_id' = any(v_given) and v_master then
    select * into v_ar from public.ref_account a where a.id = (p_customer->>'ar_account_id')::uuid and a.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'ar_account_invalid', 'code', 'ar_account_invalid', 'message', 'The receivable account does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_ar_account_code';
    select * into v_ar from public.ref_account a where a.code = v_cfg and a.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:ar_account', 'code', 'default_missing', 'message', format('The default receivable account is not set up (inv_config customer_default_ar_account_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'ar_account'); end if;
  end if;
  if 'sale_account_id' = any(v_given) and v_master then
    select * into v_sale from public.ref_account a where a.id = (p_customer->>'sale_account_id')::uuid and a.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'sale_account_invalid', 'code', 'sale_account_invalid', 'message', 'The sales account does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_sale_account_code';
    select * into v_sale from public.ref_account a where a.code = v_cfg and a.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:sale_account', 'code', 'default_missing', 'message', format('The default sales account is not set up (inv_config customer_default_sale_account_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'sale_account'); end if;
  end if;
  if v_tier.id is not null and v_cur.id is not null and v_tier.currency_id <> v_cur.id then
    v_warns := v_warns || jsonb_build_object('key', 'tier_currency_mismatch', 'code', 'tier_currency_mismatch', 'message', format('Price tier %s is not in the customer currency %s — order prices will not match the currency', v_tier.name, v_cur.code));
  end if;
  -- 청구 구조(master 만 · 값 검사)
  if 'default_bill_to_customer_id' = any(v_given) and v_master then
    select * into v_other from public.customer c where c.id = (p_customer->>'default_bill_to_customer_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'bill_to_unknown', 'code', 'bill_to_unknown', 'message', 'The bill-to customer does not exist or is inactive — nothing was saved'); end if;
  end if;

  -- ④ 일반 칸(누구나) — 창고 · 부모 · 배송 손님
  if nullif(p_customer->>'default_location_id', '') is not null then
    select * into v_wh from public.ref_warehouse w where w.id = (p_customer->>'default_location_id')::uuid and w.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'warehouse_unknown', 'code', 'warehouse_unknown', 'message', 'The default warehouse does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_location_name';
    select * into v_wh from public.ref_warehouse w where w.name = v_cfg and w.is_active;       -- 비었거나 없으면 창고 없이 만든다(돈 칸이 아니다 · 오더가 창고를 고른다)
    if v_wh.id is not null then v_defaults := array_append(v_defaults, 'default_location'); end if;
  end if;
  if nullif(p_customer->>'parent_id', '') is not null then
    if not v_master then v_blocks := v_blocks || jsonb_build_object('key', 'money_field_not_allowed:parent_id', 'code', 'money_field_not_allowed', 'message', 'Only a master user can set parent_id on a new customer — leave it out and link the store afterwards — nothing was saved'); end if;   -- 판정 252(cs-par-1)
    select * into v_parent from public.customer c where c.id = (p_customer->>'parent_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'parent_unknown', 'code', 'parent_unknown', 'message', 'The parent customer does not exist or is inactive — nothing was saved');
    elsif v_parent.parent_id is not null then v_blocks := v_blocks || jsonb_build_object('key', 'parent_has_parent', 'code', 'parent_has_parent', 'message', format('%s already has a parent — a customer tree is one level deep — nothing was saved', v_parent.name)); end if;
  end if;
  if nullif(p_customer->>'default_ship_to_customer_id', '') is not null then
    select * into v_other from public.customer c where c.id = (p_customer->>'default_ship_to_customer_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'ship_to_unknown', 'code', 'ship_to_unknown', 'message', 'The ship-to customer does not exist or is inactive — nothing was saved'); end if;
  end if;

  -- ⑤ 주소 — type 어휘 · 빈 줄 · type 별 기본 하나(표시 없으면 그 type 의 첫 줄)
  v_i := 0;
  for v_a in select x from jsonb_array_elements(coalesce(p_customer->'addresses', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_type := nullif(btrim(v_a->>'type'), '');
    if v_type is null or v_type not in ('Billing', 'Business', 'Shipping') then
      v_blocks := v_blocks || jsonb_build_object('key', 'address_type_invalid:' || v_i, 'code', 'address_type_invalid', 'message', format('Address %s: type must be Billing, Business or Shipping (got %s) — nothing was saved', v_i, coalesce(v_type, '(blank)')));
      continue;
    end if;
    if nullif(btrim(coalesce(v_a->>'line1', '') || coalesce(v_a->>'city', '') || coalesce(v_a->>'postal_code', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'address_empty:' || v_i, 'code', 'address_empty', 'message', format('Address %s (%s) has no street, city or postal code — nothing was saved', v_i, v_type));
    end if;
    if v_type = 'Shipping' then v_has_ship := true; end if;
    if v_type = 'Billing' then v_has_bill := true; end if;
    if coalesce((v_a->>'is_default_for_type')::boolean, false) then
      if v_type = any(v_def_types) then
        v_blocks := v_blocks || jsonb_build_object('key', 'address_default_many:' || v_type, 'code', 'address_default_many', 'message', format('More than one %s address is marked default — only one per type — nothing was saved', v_type));
      else v_def_types := v_def_types || v_type; end if;
    end if;
    if not (v_first_def_by_type ? v_type) then v_first_def_by_type := v_first_def_by_type || jsonb_build_object(v_type, v_i); end if;
  end loop;
  if not v_has_ship then
    v_warns := v_warns || jsonb_build_object('key', 'shipping_address_missing', 'code', 'shipping_address_missing', 'message', 'No shipping address — every order for this customer will ask for one (ship_to_empty). Confirm to create the customer without it');
  end if;
  if not v_has_bill then
    v_warns := v_warns || jsonb_build_object('key', 'billing_address_missing', 'code', 'billing_address_missing', 'message', 'No billing address — every order for this customer will warn bill_to_empty until one is added. Confirm to create the customer without it');
  end if;

  -- ⑥ 연락처 — 빈 줄 · 동의 숫자 · 기본 하나(표시 없으면 첫 줄)
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_customer->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    if nullif(btrim(coalesce(v_c->>'name', '') || coalesce(v_c->>'phone', '') || coalesce(v_c->>'mobile_phone', '') || coalesce(v_c->>'email', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'contact_empty:' || v_i, 'code', 'contact_empty', 'message', format('Contact %s has no name, phone or email — nothing was saved', v_i));
    end if;
    v_consent_t := nullif(btrim(v_c->>'marketing_consent'), '');
    if v_consent_t is not null and v_consent_t not in ('0', '1', '2', '3') then
      v_blocks := v_blocks || jsonb_build_object('key', 'consent_invalid:' || v_i, 'code', 'consent_invalid', 'message', format('Contact %s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — got %s — nothing was saved', v_i, v_consent_t));
    end if;
    if coalesce((v_c->>'is_default')::boolean, false) then v_n_cdef := v_n_cdef + 1; end if;
  end loop;
  if v_n_cdef > 1 then
    v_blocks := v_blocks || jsonb_build_object('key', 'contact_default_many', 'code', 'contact_default_many', 'message', 'More than one contact is marked default — only one per customer — nothing was saved');
  end if;

  -- ⑦ 판정 — 막기 있음 → 저장 안 함 · 검사만 → 반환 · 확인 안 받은 경고 → 저장 안 함(판정 176 모양)
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'customer_id', null, 'name', v_name, 'review_required', not v_master, 'defaults_used', to_jsonb(v_defaults),
                              'address_ids', '[]'::jsonb, 'contact_ids', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ⑧ 저장 — 손님 → 주소 → 연락처 · 한 트랜잭션 · source manual · cin7_id null · created_by · master 면 reviewed 즉시(판정 240)
  insert into public.customer (name, display_name, note, source, is_active, created_by, updated_by,
                               currency_id, currency_code, payment_term_id, payment_term_name, discount_pct, price_tier, tax_rule,
                               default_location_id, default_location_name, ar_account_id, ar_account_code, sale_account_id, sale_account_code,
                               parent_id, parent_source, is_legal_entity, default_ship_to_customer_id, default_bill_to_customer_id, default_carrier, tax_number, tags, invoice_split_by_store,
                               reviewed_by, reviewed_at)
  values (v_name, nullif(btrim(p_customer->>'display_name'), ''), nullif(btrim(p_customer->>'note'), ''), 'manual', true, v_staff, v_staff,
          v_cur.id, v_cur.code, v_term.id, v_term.name, v_disc, v_tier.name, nullif(btrim(p_customer->>'tax_rule'), ''),
          v_wh.id, v_wh.name, v_ar.id, v_ar.code, v_sale.id, v_sale.code,
          nullif(p_customer->>'parent_id', '')::uuid,
          case when nullif(p_customer->>'parent_id', '') is not null then 'ims' end,   -- 판정 253 · 254(cs-par-1): parent_source(부모를 주면 ims) · is_bill_parent 는 기본값 false 로 둔다
          coalesce((p_customer->>'is_legal_entity')::boolean, false),
          nullif(p_customer->>'default_ship_to_customer_id', '')::uuid,
          case when v_master then nullif(p_customer->>'default_bill_to_customer_id', '')::uuid end,
          nullif(btrim(p_customer->>'default_carrier'), ''), nullif(btrim(p_customer->>'tax_number'), ''), nullif(btrim(p_customer->>'tags'), ''),
          case when v_master then coalesce((p_customer->>'invoice_split_by_store')::boolean, false) else false end,
          case when v_master then v_staff end, case when v_master then now() end)
  returning id into v_cid;
  v_i := 0;
  for v_a in select x from jsonb_array_elements(coalesce(p_customer->'addresses', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_type := btrim(v_a->>'type');
    insert into public.customer_address (customer_id, source, updated_by, type, is_default_for_type, label, line1, line2, city, state_province, postal_code, country)
    values (v_cid, 'manual', v_staff, v_type,
            case when v_type = any(v_def_types) then coalesce((v_a->>'is_default_for_type')::boolean, false) else (v_first_def_by_type->>v_type)::int = v_i end,
            nullif(btrim(v_a->>'label'), ''), nullif(btrim(v_a->>'line1'), ''), nullif(btrim(v_a->>'line2'), ''), nullif(btrim(v_a->>'city'), ''),
            nullif(btrim(v_a->>'state_province'), ''), nullif(btrim(v_a->>'postal_code'), ''), nullif(btrim(v_a->>'country'), ''))
    returning id into v_aid;
    v_addr_ids := v_addr_ids || to_jsonb(v_aid);
  end loop;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_customer->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_consent_t := nullif(btrim(v_c->>'marketing_consent'), '');
    v_consent := case v_consent_t when '2' then true when '3' then false else null end;      -- asung-so ⚠️ 2 Opt in · 3 Opt out · 0 · 1 · 없음 = Unknown
    insert into public.customer_contact (customer_id, source, updated_by, name, phone, mobile_phone, fax, email, website, job_title, include_in_email, marketing_consent, is_default)
    values (v_cid, 'manual', v_staff, nullif(btrim(v_c->>'name'), ''), nullif(btrim(v_c->>'phone'), ''), nullif(btrim(v_c->>'mobile_phone'), ''), nullif(btrim(v_c->>'fax'), ''),
            nullif(btrim(v_c->>'email'), ''), nullif(btrim(v_c->>'website'), ''), nullif(btrim(v_c->>'job_title'), ''), coalesce((v_c->>'include_in_email')::boolean, false), v_consent,
            case when v_n_cdef = 1 then coalesce((v_c->>'is_default')::boolean, false) else v_i = 1 end)
    returning id into v_aid;
    v_cont_ids := v_cont_ids || to_jsonb(v_aid);
  end loop;

  return jsonb_build_object('committed', true, 'customer_id', v_cid, 'name', v_name, 'review_required', not v_master, 'defaults_used', to_jsonb(v_defaults),
                            'address_ids', v_addr_ids, 'contact_ids', v_cont_ids, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.customer_create(jsonb, boolean, text[]) from public, anon;
grant execute on function public.customer_create(jsonb, boolean, text[]) to authenticated;
comment on function public.customer_create(jsonb, boolean, text[]) is
  'master-cs-2a · 판정 237 ~ 240 — 손님 만들기 한 벌(손님 + 주소들 + 연락처들 · 한 트랜잭션) · 문 = sales 또는 master 쓰기 · 두 번 부르기(p_commit false 검사 · true 저장 · 확인 안 받은 경고 열쇠가 있으면 unacked) · 돈 칸(price_tier · discount_pct · payment_term_id · currency_id · ar_account_id · sale_account_id · default_bill_to_customer_id · invoice_split_by_store)은 master 만 — sales 가 보내면 막기 money_field_not_allowed · 안 보내면 inv_config customer_default_* 기본값(비었거나 없거나 꺼졌으면 default_missing) · ⭐ cs-par-1(2026-10-06 · 판정 252 ~ 254 · 원본 20261005161145): parent_id 도 master 만(money_field_not_allowed · 부모는 활성 · 자식이 아닌 손님 — parent_unknown · parent_has_parent · 트리거 customer_parent_guard 가 다시 막는다) · 부모를 주면 parent_source = ims(판정 253) · is_bill_parent 는 받지 않는다(판정 254 · 늘 false) · 같은 접은 이름의 활성 손님 → 알리기 name_exists(ack 로 만든다 · 판정 238) · 기본 하나(주소 type 별 · 연락처)는 표시 없으면 첫 줄 · master 가 만들면 reviewed_by/at 즉시 · sales 면 null(Action Centre). 2026-10-06';

-- ═══ 6) 채우기 — 판정 251(청구처 = 부모 · 실측 12) · 판정 253(부모 있는 행 parent_source = cin7 · 실측 13) · parent_id 는 SET 에 없어 트리거는 안 돈다 · updated_by 는 ims_touch 가 null(system) ═══
do $$
declare
  v_bill int;
  v_src  int;
begin
  update public.customer set default_bill_to_customer_id = parent_id
   where is_bill_parent and parent_id is not null and default_bill_to_customer_id is null;
  get diagnostics v_bill = row_count;
  update public.customer set parent_source = 'cin7'
   where parent_id is not null and parent_source is null;
  get diagnostics v_src = row_count;
  raise notice 'cs-par-1 fill — ruling 251 bill-to set to parent: % row(s) · ruling 253 parent_source = cin7: % row(s)', v_bill, v_src;
end $$;

-- ═══ 7) 칸 주석 — 뜻이 바뀐 셋(원문 그대로 + 덧붙임) ═══
comment on column public.customer.parent_id                   is 'Cin7 CustomerParentID → customer(id) · 자기 참조 · nullable · on delete no action · 인덱스 customer_parent_idx · ⭐ 연결 축만 — 상속 없음(§2-m 정정 · 자식 설정은 각자) · ⚠️ 적재는 부모를 먼저 넣어야 이어진다(적재 차수의 일) · ⭐ cs-par-1(2026-10-06): IMS 에서 세우고 없앤다(창구 customer_update · master 만 · 판정 252) · 깊이 하나 · 자기 자신 금지(트리거 customer_parent_guard · CHECK customer_parent_not_self_ck) · 누가 세웠나는 parent_source(판정 253) · 비우거나 바꾸면 옛 부모를 가리키던 default_bill_to_customer_id 는 null(규칙 4)';
comment on column public.customer.is_bill_parent              is 'Cin7 IsBillParent 그대로 받아만 둔다 · IMS 규칙은 걸지 않는다(그 일은 default_bill_to_customer_id 가 한다 · 5-a) · ⭐ 판정 251 · 254(cs-par-1 · 2026-10-06): 청구처 규칙은 default_bill_to_customer_id 한 칸뿐 — 이 칸은 규칙에 쓰지 않고 창구(customer_update · customer_create)도 더 받지 않는다(적재가 매 upsert 마다 덮는다) · 판정 251 채우기의 재료로 한 번 쓰였다(true + 부모 있음 + 청구처 빈 손님 → 청구처 = 부모)';
comment on column public.customer.default_bill_to_customer_id is '⭐ Cin7 에 없는 우리 칸 · 청구처 주소록의 주인 → customer(id) · 비어 있으면 자기 자신 · 주소를 복제하지 않고 주소록의 주인을 가리킨다(부모 주소가 바뀌면 자식 수만큼 고치는 일을 피한다 · 5-a) · ⚠️ 재적재가 덮지 않는다 · 인덱스 customer_default_bill_to_customer_idx · ⭐ cs-par-1(2026-10-06): 청구처 규칙은 이 한 칸(판정 251) · master 만 바꾼다(판정 252) · 아무 활성 손님(자기 자신은 null · CHECK customer_bill_to_not_self_ck · 판정 255) · 부모를 비우거나 바꿀 때 옛 부모를 가리키면 트리거가 null 로(규칙 4) · 오더는 만든 날 값(so.bill_to_customer_id · 규칙 5)';

-- ═══ 8) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'customer' and column_name = 'parent_source') then v_bad := v_bad || ' parent_source'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.customer'::regclass and contype = 'c' and conname in ('customer_parent_source_ck', 'customer_parent_not_self_ck', 'customer_bill_to_not_self_ck', 'customer_ship_to_not_self_ck')) <> 4 then v_bad := v_bad || ' checks'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.customer'::regclass and tgname = 'customer_parent_guard' and not tgisinternal) then v_bad := v_bad || ' trigger'; end if;
  if to_regprocedure('public.customer_update(jsonb, boolean, text[])') is null or to_regprocedure('public.customer_create(jsonb, boolean, text[])') is null or to_regprocedure('public.customer_parent_guard()') is null then v_bad := v_bad || ' functions'; end if;
  if (select prosrc from pg_proc where oid = to_regprocedure('public.customer_update(jsonb, boolean, text[])')) like '%''is_bill_parent''%' then v_bad := v_bad || ' customer_update(is_bill_parent)'; end if;   -- 따옴표 열쇠(목록 · case · 저장 줄) 어디에도 없어야 한다 · 주석의 낱말은 세지 않는다
  if (select prosrc from pg_proc where oid = to_regprocedure('public.customer_update(jsonb, boolean, text[])')) not like '%v_struct%' then v_bad := v_bad || ' customer_update(v_struct)'; end if;
  if (select prosrc from pg_proc where oid = to_regprocedure('public.customer_create(jsonb, boolean, text[])')) like '%''is_bill_parent''%' or (select prosrc from pg_proc where oid = to_regprocedure('public.customer_create(jsonb, boolean, text[])')) like '%, is_bill_parent,%' then v_bad := v_bad || ' customer_create(is_bill_parent)'; end if;   -- 주석의 낱말은 세지 않는다(따옴표 열쇠 · 칸 목록만)
  if (select count(*) from public.customer where is_bill_parent and parent_id is not null and default_bill_to_customer_id is null) <> 0 then v_bad := v_bad || ' fill(251)'; end if;
  if (select count(*) from public.customer where parent_id is not null and parent_source is null) <> 0 or (select count(*) from public.customer where parent_id is null and parent_source is not null) <> 0 then v_bad := v_bad || ' fill(253)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM253', message = format('STOP - cs-par-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
