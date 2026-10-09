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

-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- shop-1a — Shopify 연동 ① 바탕 · DB (2026-10-09 · 판정 362 · 403 · shop-0 회신 이견 1 ~ 9 · 정본 docs/design/shopify-integration.md §1)
--   ① shop_store(스토어 설정 한 줄 · 티어 짝 · 열쇠 접두) ② shop_location(Shopify 위치 ↔ IMS 창고 짝 · GID 가 열쇠) ③ shop_call_log(EF 호출 기록 · 쓰기는 service_role)
--   ④ 권한 키 shopify(ims_perm_catalog 재발행 · 새 줄 하나) ⑤ 창구 shop_store_save(admin · 두 번 부르기 · op 넷) ⑥ 뷰 shop_store_list ⑦ 시작값 test 스토어 한 행(위치 짝은 shop-1b ping 뒤 화면에서)
--   ⭐ 두 표는 authenticated select 만(직접 쓰기 닫힘 · prod-2 모양) · 뷰도 select 만(미룬 159 되풀이 금지) · 열쇠 값은 표에 없다(EF 가 secret_prefix + _CLIENT_ID / _CLIENT_SECRET 환경 변수에서)
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) shop_store ═══
create table public.shop_store (
  id               uuid primary key default gen_random_uuid(),
  code             text not null,                                           -- 짧은 이름(test · asung · aone) · 화면 · EF 가 이것으로 부른다
  shop_domain      text not null,                                           -- *.myshopify.com
  label            text not null,
  kind             text not null,                                           -- asung(도매 · asung.ca 모양) · aone(매장 픽업 · aonebeauty.com 모양) — 브랜치 규칙 칸은 ④ 오더 받기 때
  sale_tier_id     uuid not null references public.ref_price_tier (id) on delete no action,   -- Shopify Price · purpose sale 만(창구가 막는다)
  compare_tier_id  uuid references public.ref_price_tier (id) on delete no action,            -- Shopify Compare-at · sale 또는 compare · Price 와 같아도 된다 · null = 보내지 않음(판정 403 고침)
  secret_prefix    text not null default 'SHOPIFY_IMS',                     -- EF 환경 변수 접두(<prefix>_CLIENT_ID · <prefix>_CLIENT_SECRET) · 다른 organization 의 스토어는 다른 접두
  is_active        boolean not null default true,
  note             text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  updated_by       uuid references public.ims_staff (id) on delete no action,
  constraint shop_store_code_uk     unique (code),
  constraint shop_store_domain_uk   unique (shop_domain),
  constraint shop_store_code_ck     check (code ~ '^[a-z0-9_]{1,20}$'),
  constraint shop_store_domain_ck   check (shop_domain ~ '^[a-z0-9][a-z0-9-]*\.myshopify\.com$'),
  constraint shop_store_kind_ck     check (kind in ('asung', 'aone')),
  constraint shop_store_prefix_ck   check (secret_prefix ~ '^[A-Z][A-Z0-9_]*$')
);
create index shop_store_sale_tier_id_idx    on public.shop_store (sale_tier_id);
create index shop_store_compare_tier_id_idx on public.shop_store (compare_tier_id);
create index shop_store_updated_by_idx      on public.shop_store (updated_by);
create trigger shop_store_touch before update on public.shop_store for each row execute function public.ims_touch();
alter table public.shop_store enable row level security;
create policy shop_store_select on public.shop_store for select to authenticated using (true);
revoke all on public.shop_store from anon, authenticated;                                                    -- 기본 권한(references · trigger 포함)을 전부 거두고 select 만(1회차 T1c)
grant select on public.shop_store to authenticated;
comment on table public.shop_store is
  'shop-1a 판정 362 · 403: Shopify 스토어 = IMS 안의 설정 한 줄 — code(화면 · EF 열쇠) · shop_domain · kind asung | aone · Price 티어 sale_tier_id(sale 만) · Compare-at 티어 compare_tier_id(sale 또는 compare · Price 와 같아도 됨 · null = 안 보냄 · reference 금지 — 판정 403 고침: 세일가는 Wholesale All In One 앱이 정한다) · secret_prefix(EF 환경 변수 <prefix>_CLIENT_ID · _CLIENT_SECRET · 열쇠 값은 표에 없다) · 쓰기는 shop_store_save(admin) 만 · 브랜치 규칙 칸은 ④ 오더 받기 때 더한다';

-- ═══ 2) shop_location — Shopify 위치 ↔ IMS 창고 짝 (열쇠는 GID · 이름은 표시 칸) ═══
create table public.shop_location (
  id                    uuid primary key default gen_random_uuid(),
  store_id              uuid not null references public.shop_store (id) on delete no action,
  shopify_location_gid  text not null,                                       -- gid://shopify/Location/<숫자> · 이름이 바뀌어도 이것으로 잇는다(shop-0 이견 6)
  shopify_name          text,                                                -- ping 이 채우는 표시 칸
  warehouse_id          uuid not null references public.ref_warehouse (id) on delete no action,   -- 원장은 ref_warehouse.name 글자로 잇는다(shop-0 이견 3)
  is_active             boolean not null default true,
  checked_at            timestamptz,                                         -- ping 이 이 짝을 Shopify 에서 마지막으로 본 시각
  note                  text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  updated_by            uuid references public.ims_staff (id) on delete no action,
  constraint shop_location_store_gid_uk  unique (store_id, shopify_location_gid),
  constraint shop_location_store_wh_uk   unique (store_id, warehouse_id),
  constraint shop_location_gid_ck        check (shopify_location_gid ~ '^gid://shopify/Location/[0-9]+$')
);
create index shop_location_warehouse_id_idx on public.shop_location (warehouse_id);
create index shop_location_updated_by_idx   on public.shop_location (updated_by);
create trigger shop_location_touch before update on public.shop_location for each row execute function public.ims_touch();
alter table public.shop_location enable row level security;
create policy shop_location_select on public.shop_location for select to authenticated using (true);
revoke all on public.shop_location from anon, authenticated;                                                    -- 기본 권한(references · trigger 포함)을 전부 거두고 select 만(1회차 T1c)
grant select on public.shop_location to authenticated;
comment on table public.shop_location is
  'shop-1a: 스토어의 Shopify 위치(GID) ↔ IMS 창고(ref_warehouse.id) 짝 — ③ 재고 올리기 · ⑤ 발송이 이 짝만 읽는다 · 한 스토어에서 GID 하나 = 창고 하나(유니크 둘) · 끄기는 is_active false(다시 같은 창고를 다른 GID 에 붙이면 그 행이 되살아난다) · shopify_name · checked_at 은 ping(shop-1b · service_role)이 채운다 · 쓰기는 shop_store_save(admin) 만';

-- ═══ 3) shop_call_log — EF 호출 기록 (쓰기는 service_role · 90 일 지우기는 EF 몫 · shop-1b) ═══
create table public.shop_call_log (
  id                  bigint generated always as identity primary key,
  called_at           timestamptz not null default now(),
  store_id            uuid references public.shop_store (id) on delete no action,
  action              text not null,                                         -- ping · (②③④⑤ 의 action 이름)
  ok                  boolean not null,
  http_status         int,
  query_cost          int,                                                   -- extensions.cost.actualQueryCost
  throttle_available  int,                                                   -- extensions.cost.throttleStatus.currentlyAvailable
  error               text,                                                  -- 앞 400 자
  by_staff            uuid references public.ims_staff (id) on delete no action,   -- 직원 길이면 그 사람 · cron 이면 null
  ms                  int,
  constraint shop_call_log_error_ck check (error is null or length(error) <= 400)
);
create index shop_call_log_store_called_idx on public.shop_call_log (store_id, called_at desc);
create index shop_call_log_by_staff_idx     on public.shop_call_log (by_staff);
alter table public.shop_call_log enable row level security;
create policy shop_call_log_select on public.shop_call_log for select to authenticated using (true);
revoke all on public.shop_call_log from anon, authenticated;                                                    -- 기본 권한(references · trigger 포함)을 전부 거두고 select 만(1회차 T1c)
grant select on public.shop_call_log to authenticated;
comment on table public.shop_call_log is
  'shop-1a: Shopify EF 의 호출 한 번 = 한 줄(ping 부터) — ok · http_status · query_cost · throttle_available · error(앞 400 자) · by_staff(직원 길) 또는 null(cron) · ms · 쓰기는 EF(service_role)만 · 90 일 지난 줄은 EF 가 호출 끝에 지운다(shop-1b) · Action Centre 로 올릴 바탕';

-- ═══ 4) 권한 키 shopify — ims_perm_catalog 재발행(마지막 정의 20260928201753_transfer_1a.sql:471 · prosrc md5 40dac6284fe9bdc73879971ed16ac3c9 · 21 줄 · 더한 줄 하나 · 나머지 바이트 그대로 · 맨 앞에 넣어 다른 줄의 쉼표를 안 건드린다 · jsonb 라 순서 무관) ═══
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "shopify":    {"room": "ims", "min_role": "manager", "label": "Shopify stores, product push, stock sync (manager and above · shop-1a)"},
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products, prices, product tags, deals"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"},
      "sales":      {"room": "ims", "label": "Sales orders, customer addresses and contacts"},
      "picking":     {"room": "wms", "label": "Picking — pick tasks, waves, holds"},
      "packing":     {"room": "wms", "label": "Packing — pack tasks, pallets, boxes"},
      "fulfillment": {"room": "wms", "label": "Fulfillment — finalize, shipping, manager review"},
      "wms_manage":  {"room": "wms", "min_role": "manager", "label": "Warehouse management — batches, waves, rollbacks (manager and above)"},
      "wms_receiving":         {"room": "wms", "label": "Warehouse receiving — count, put away, hold, off-PO"},
      "wms_receiving_confirm": {"room": "wms", "min_role": "manager", "label": "Warehouse receiving — confirm a receipt (manager and above · off until switched on)"},
      "stock_adjust":          {"room": "ims", "min_role": "manager", "label": "Stock adjustments — draft and confirm (manager and above · off until switched on)"},
      "stock_move":            {"room": "wms", "label": "Bin moves — move stock between bins in one warehouse (person by person · off until switched on)"},
      "transfer":              {"room": "ims", "label": "Transfers — warehouse to warehouse (person by person · off until switched on)"}
    }
  }'::jsonb;
$$;
comment on function public.ims_perm_catalog() is
  '권한 카탈로그 — modes · screens(room · min_role · label) · ⭐ [2026-10-09 shop-1a] screens.shopify(ims 방 · manager 이상 · Shopify 스토어 설정 · 상품 보내기 · 재고 올리기 — 창구 shop_store_save 는 admin 문 · EF shopify 의 직원 길은 ims_can_write(shopify)) · 그 앞 이력은 20260928201753 의 comment';

-- ═══ 5) 창구 shop_store_save — admin · 두 번 부르기(p_commit false = 검사 · true + p_ack = 저장 · 저장 직전 재검사는 같은 호출 안의 한 번) · op 넷 ═══
--   선례 price_tier_rule_save(20261002012641:663~734 · definer · 첫 줄 ims_require_admin) + product_update 의 경고 ack 모양(unacked)
create function public.shop_store_save(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_code     text;
  v_key      text;
  v_gid      text;
  v_seen     text[] := '{}';
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_s        public.shop_store%rowtype;
  v_l        public.shop_location%rowtype;
  v_sale     public.ref_price_tier%rowtype;
  v_cmp      public.ref_price_tier%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_old      jsonb;
  v_cur      jsonb;
  v_prefix   text;
  v_cnt      bigint;
  c_ops      constant text[] := array['store_set', 'store_off', 'location_set', 'location_off'];
begin
  perform public.ims_require_admin('Shopify stores');                                             -- ⭐ 유일한 문 — 첫 줄(shop-0 이견 5)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 200 then raise exception 'Too many changes in one call (% — the limit is 200) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    if not (coalesce(v_c->>'op', '') = any(c_ops)) then
      raise exception 'Unknown op "%" — store_set, store_off, location_set or location_off — nothing was saved', coalesce(v_c->>'op', '(none)');
    end if;
  end loop;

  -- ② 줄마다 막기 · 알리기 — 전부 모은다
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_s := null; v_l := null; v_sale := null; v_cmp := null; v_wh := null;
    v_code := lower(trim(coalesce(v_c->>(case when v_op like 'store_%' then 'code' else 'store_code' end), '')));
    v_key := case when v_code = '' then '(blank)' else v_code end;
    v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'code', v_code, 'applied', false);
    if v_code !~ '^[a-z0-9_]{1,20}$' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':code_invalid', 'code', 'code_invalid', 'message', format('Store code "%s" must be 1-20 lowercase letters, digits or _ — nothing was saved', v_code));
      continue;
    end if;
    select * into v_s from public.shop_store s where s.code = v_code;

    if v_op = 'store_set' then
      if (v_code || '|store') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s appears twice in this call — nothing was saved', v_code));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|store');
      -- old: 새 스토어는 null · 있는 스토어는 화면이 본 여섯 칸
      if v_s.id is not null then
        if coalesce(jsonb_typeof(v_c->'old'), 'none') <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Store %s exists — the old values the screen saw are missing — nothing was saved', v_code));
          continue;
        end if;
        v_old := v_c->'old';
        v_cur := jsonb_build_object('shop_domain', v_s.shop_domain, 'label', v_s.label, 'kind', v_s.kind,
                                    'sale_tier', (select t.name from public.ref_price_tier t where t.id = v_s.sale_tier_id),
                                    'compare_tier', (select t.name from public.ref_price_tier t where t.id = v_s.compare_tier_id),
                                    'secret_prefix', v_s.secret_prefix);
        if (v_cur->>'shop_domain') is distinct from nullif(v_old->>'shop_domain', '') or (v_cur->>'label') is distinct from nullif(v_old->>'label', '') or (v_cur->>'kind') is distinct from nullif(v_old->>'kind', '')
           or (v_cur->>'sale_tier') is distinct from nullif(v_old->>'sale_tier', '') or (v_cur->>'compare_tier') is distinct from nullif(v_old->>'compare_tier', '') or (v_cur->>'secret_prefix') is distinct from nullif(v_old->>'secret_prefix', '') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed store %s — check again — nothing was saved', v_code));
          continue;
        end if;
      elsif coalesce(jsonb_typeof(v_c->'old'), 'null') <> 'null' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — to create it send old as null — nothing was saved', v_code));
        continue;
      end if;
      -- 칸 검사
      if coalesce(v_c->>'shop_domain', '') !~ '^[a-z0-9][a-z0-9-]*\.myshopify\.com$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':domain_invalid', 'code', 'domain_invalid', 'message', format('Store %s: the domain must look like name.myshopify.com (lowercase) — nothing was saved', v_code));
      elsif exists (select 1 from public.shop_store x where x.shop_domain = v_c->>'shop_domain' and x.code <> v_code) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':domain_taken', 'code', 'domain_taken', 'message', format('Store %s: %s is already used by another store — nothing was saved', v_code, v_c->>'shop_domain'));
      end if;
      if nullif(trim(coalesce(v_c->>'label', '')), '') is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':label_missing', 'code', 'label_missing', 'message', format('Store %s needs a label — nothing was saved', v_code));
      end if;
      if coalesce(v_c->>'kind', '') not in ('asung', 'aone') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':kind_invalid', 'code', 'kind_invalid', 'message', format('Store %s: kind must be asung or aone — nothing was saved', v_code));
      end if;
      v_prefix := coalesce(nullif(trim(coalesce(v_c->>'secret_prefix', '')), ''), 'SHOPIFY_IMS');
      if v_prefix !~ '^[A-Z][A-Z0-9_]*$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':prefix_invalid', 'code', 'prefix_invalid', 'message', format('Store %s: the secret prefix must be CAPITALS, digits or _ (e.g. SHOPIFY_IMS) — nothing was saved', v_code));
      end if;
      -- 티어 — 이름으로 받는다 · Price 는 sale 만 · Compare-at 은 sale 또는 compare(같아도 됨 · 비워도 됨) · reference 는 어디에도 안 된다(판정 403 고침)
      select * into v_sale from public.ref_price_tier t where t.name = trim(coalesce(v_c->>'sale_tier', '')) and t.is_active;
      if v_sale.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sale_tier_unknown', 'code', 'sale_tier_unknown', 'message', format('Store %s: there is no active price tier named "%s" for Price — nothing was saved', v_code, coalesce(v_c->>'sale_tier', '')));
      elsif v_sale.purpose <> 'sale' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sale_tier_not_sale', 'code', 'sale_tier_not_sale', 'message', format('Store %s: Price must be a sale tier — %s is a %s tier — nothing was saved', v_code, v_sale.name, v_sale.purpose));
      end if;
      if nullif(trim(coalesce(v_c->>'compare_tier', '')), '') is not null then
        select * into v_cmp from public.ref_price_tier t where t.name = trim(v_c->>'compare_tier') and t.is_active;
        if v_cmp.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':compare_tier_unknown', 'code', 'compare_tier_unknown', 'message', format('Store %s: there is no active price tier named "%s" for Compare-at — nothing was saved', v_code, v_c->>'compare_tier'));
        elsif v_cmp.purpose not in ('sale', 'compare') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':compare_tier_reference', 'code', 'compare_tier_reference', 'message', format('Store %s: Compare-at cannot be a %s tier (%s) — use a sale or compare tier, or leave it empty — nothing was saved', v_code, v_cmp.purpose, v_cmp.name));
        end if;
      end if;
      -- 알리기: 같은 kind 의 다른 활성 스토어(시험 + 실제가 같은 kind 일 수 있다 — 막지 않는다) · 꺼진 스토어를 다시 켬
      select count(*) into v_cnt from public.shop_store x where x.kind = coalesce(v_c->>'kind', '') and x.is_active and x.code <> v_code;
      if v_cnt > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':kind_active_dup', 'code', 'kind_active_dup', 'count', v_cnt, 'message', format('Store %s: %s other active store(s) already have kind %s — fine for a test store next to the real one, check it is what you mean', v_code, v_cnt, v_c->>'kind'));
      end if;
      if v_s.id is not null and not v_s.is_active then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':store_reactivated', 'code', 'store_reactivated', 'message', format('Store %s is off — saving turns it back on', v_code));
      end if;

    elsif v_op = 'store_off' then
      if v_s.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — nothing was saved', v_code));
        continue;
      end if;
      if (v_code || '|store') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s appears twice in this call — nothing was saved', v_code));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|store');
      if not v_s.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_off', 'code', 'already_off', 'message', format('Store %s is already off — nothing was saved', v_code));
        continue;
      end if;
      if not (v_c ? 'old') or (v_c->>'old') is distinct from v_s.shop_domain then                  -- old = 화면이 본 shop_domain(스토어 확인용)
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Store %s: the domain the screen saw does not match — check again — nothing was saved', v_code));
        continue;
      end if;
      select count(*) into v_cnt from public.shop_location l where l.store_id = v_s.id and l.is_active;
      if v_cnt > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':locations_stay', 'code', 'locations_stay', 'count', v_cnt, 'message', format('Store %s has %s active location pair(s) — they stay as they are (the store is only switched off)', v_code, v_cnt));
      end if;

    else                                                                                            -- location_set · location_off
      if v_s.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':store_unknown', 'code', 'store_unknown', 'message', format('Store %s does not exist — nothing was saved', v_code));
        continue;
      end if;
      v_gid := trim(coalesce(v_c->>'shopify_location_gid', ''));
      v_key := v_code || ':' || (case when v_gid = '' then '(blank)' else v_gid end);
      if v_gid !~ '^gid://shopify/Location/[0-9]+$' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':gid_invalid', 'code', 'gid_invalid', 'message', format('Store %s: the Shopify location id must look like gid://shopify/Location/123 — nothing was saved', v_code));
        continue;
      end if;
      if (v_code || '|gid|' || v_gid) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Store %s: location %s appears twice in this call — nothing was saved', v_code, v_gid));
        continue;
      end if;
      v_seen := v_seen || (v_code || '|gid|' || v_gid);
      select * into v_l from public.shop_location l where l.store_id = v_s.id and l.shopify_location_gid = v_gid;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Store %s location %s: the old warehouse the screen saw is missing (null for a new pair) — nothing was saved', v_code, v_gid));
        continue;
      end if;
      if (case when v_l.id is not null and v_l.is_active then v_l.warehouse_id::text end) is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed the warehouse of location %s on store %s — check again — nothing was saved', v_gid, v_code));
        continue;
      end if;
      if v_op = 'location_set' then
        if coalesce(v_c->>'warehouse_id', '') ~ '^[0-9a-fA-F-]{36}$' then
          select * into v_wh from public.ref_warehouse w where w.id = (v_c->>'warehouse_id')::uuid and w.is_active;
        end if;
        if v_wh.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_unknown', 'code', 'warehouse_unknown', 'message', format('Store %s location %s: the warehouse is missing or inactive — nothing was saved', v_code, v_gid));
          continue;
        end if;
        if (v_code || '|wh|' || v_wh.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_duplicate_in_call', 'code', 'warehouse_duplicate_in_call', 'message', format('Store %s: warehouse %s is given to two locations in this call — nothing was saved', v_code, v_wh.name));
          continue;
        end if;
        v_seen := v_seen || (v_code || '|wh|' || v_wh.id::text);
        if exists (select 1 from public.shop_location x where x.store_id = v_s.id and x.warehouse_id = v_wh.id and x.is_active and x.shopify_location_gid <> v_gid) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_already_mapped', 'code', 'warehouse_already_mapped', 'message', format('Store %s: warehouse %s is already paired with another Shopify location — switch that pair off first — nothing was saved', v_code, v_wh.name));
          continue;
        end if;
      else
        if v_l.id is null or not v_l.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':location_unknown', 'code', 'location_unknown', 'message', format('Store %s has no active pair for location %s — nothing was saved', v_code, v_gid));
          continue;
        end if;
      end if;
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 줄 순서대로 · 한 트랜잭션
  v_i := 0;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_code := lower(trim(coalesce(v_c->>(case when v_op like 'store_%' then 'code' else 'store_code' end), '')));
    select * into v_s from public.shop_store s where s.code = v_code;
    if v_op = 'store_set' then
      select t.id into v_sale from public.ref_price_tier t where t.name = trim(v_c->>'sale_tier') and t.is_active;
      v_cmp := null;
      if nullif(trim(coalesce(v_c->>'compare_tier', '')), '') is not null then
        select t.id into v_cmp from public.ref_price_tier t where t.name = trim(v_c->>'compare_tier') and t.is_active;
      end if;
      v_prefix := coalesce(nullif(trim(coalesce(v_c->>'secret_prefix', '')), ''), 'SHOPIFY_IMS');
      if v_s.id is null then
        insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, compare_tier_id, secret_prefix, is_active, updated_by)
        values (v_code, v_c->>'shop_domain', trim(v_c->>'label'), v_c->>'kind', v_sale.id, v_cmp.id, v_prefix, true, v_staff);
      else
        update public.shop_store set shop_domain = v_c->>'shop_domain', label = trim(v_c->>'label'), kind = v_c->>'kind', sale_tier_id = v_sale.id, compare_tier_id = v_cmp.id, secret_prefix = v_prefix, is_active = true
         where id = v_s.id;
      end if;
    elsif v_op = 'store_off' then
      update public.shop_store set is_active = false where id = v_s.id;
    elsif v_op = 'location_set' then
      v_gid := trim(v_c->>'shopify_location_gid');
      select * into v_l from public.shop_location l where l.store_id = v_s.id and l.shopify_location_gid = v_gid;
      if v_l.id is not null then
        update public.shop_location set warehouse_id = (v_c->>'warehouse_id')::uuid, is_active = true where id = v_l.id;
      elsif exists (select 1 from public.shop_location x where x.store_id = v_s.id and x.warehouse_id = (v_c->>'warehouse_id')::uuid and not x.is_active) then
        update public.shop_location set shopify_location_gid = v_gid, shopify_name = null, checked_at = null, is_active = true     -- 꺼진 같은 창고 짝을 되살려 새 GID 로(유니크 둘을 지킨다)
         where store_id = v_s.id and warehouse_id = (v_c->>'warehouse_id')::uuid and not is_active;
      else
        insert into public.shop_location (store_id, shopify_location_gid, warehouse_id, is_active, updated_by) values (v_s.id, v_gid, (v_c->>'warehouse_id')::uuid, true, v_staff);
      end if;
    elsif v_op = 'location_off' then
      update public.shop_location set is_active = false where store_id = v_s.id and shopify_location_gid = trim(v_c->>'shopify_location_gid');
    end if;
    v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
  end loop;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.shop_store_save(jsonb, boolean, text[]) from public, anon;
grant execute on function public.shop_store_save(jsonb, boolean, text[]) to authenticated;
comment on function public.shop_store_save(jsonb, boolean, text[]) is
  '⭐ Shopify 스토어 설정 창구(shop-1a · 판정 362 · 403 · shop-0 이견 5) — definer · 첫 줄 ims_require_admin · p_changes = 바꿀 것 목록(최대 200) · op 넷: store_set {code, shop_domain, label, kind, sale_tier, compare_tier, secret_prefix?, old}(새 스토어는 old null · 있는 스토어는 old = 화면이 본 여섯 칸 {shop_domain, label, kind, sale_tier, compare_tier, secret_prefix} · 티어는 이름 · compare_tier 비움 = 안 보냄 · 꺼진 스토어는 다시 켠다) · store_off {code, old = shop_domain} · location_set {store_code, shopify_location_gid, warehouse_id, old = 지금 warehouse_id | null} · location_off {store_code, shopify_location_gid, old = warehouse_id}. 막기 code_invalid · domain_invalid · domain_taken · label_missing · kind_invalid · prefix_invalid · sale_tier_unknown · sale_tier_not_sale · compare_tier_unknown · compare_tier_reference · store_unknown · already_off · old_missing · changed_elsewhere · field_duplicate_in_call · gid_invalid · warehouse_unknown · warehouse_duplicate_in_call · warehouse_already_mapped · location_unknown. 알리기(ack) kind_active_dup{count} · store_reactivated · locations_stay{count}. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 막기 하나면 아무것도 안 바뀐다 · Compare-at = Price 같은 티어는 막기도 경고도 아님(판정 403 고침)';

-- ═══ 6) 뷰 shop_store_list — security_invoker · 스토어 + 티어 이름 + 위치 짝 jsonb + 마지막 ping ═══
create view public.shop_store_list
  with (security_invoker = true) as
  select s.id, s.code, s.shop_domain, s.label, s.kind, s.is_active, s.secret_prefix, s.note, s.updated_at, s.updated_by,
         s.sale_tier_id,    ts.name as sale_tier_name,
         s.compare_tier_id, tc.name as compare_tier_name,
         coalesce((select jsonb_agg(jsonb_build_object('id', l.id, 'shopify_location_gid', l.shopify_location_gid, 'shopify_name', l.shopify_name,
                                                        'warehouse_id', l.warehouse_id, 'warehouse_name', w.name, 'is_active', l.is_active, 'checked_at', l.checked_at)
                                     order by l.is_active desc, w.name)
                     from public.shop_location l join public.ref_warehouse w on w.id = l.warehouse_id
                    where l.store_id = s.id), '[]'::jsonb) as locations,
         (select count(*) from public.shop_location l where l.store_id = s.id and l.is_active) as locations_active,
         p.ok as last_ping_ok, p.called_at as last_ping_at, p.error as last_ping_error
    from public.shop_store s
    join public.ref_price_tier ts on ts.id = s.sale_tier_id
    left join public.ref_price_tier tc on tc.id = s.compare_tier_id
    left join lateral (select g.ok, g.called_at, g.error from public.shop_call_log g where g.store_id = s.id and g.action = 'ping' order by g.called_at desc, g.id desc limit 1) p on true;
revoke all on public.shop_store_list from anon, authenticated;
grant select on public.shop_store_list to authenticated;
comment on view public.shop_store_list is
  'shop-1a: Settings → Shopify Stores 화면의 목록 — 스토어 + 티어 이름(sale_tier_name · compare_tier_name) + locations jsonb[{id, shopify_location_gid, shopify_name, warehouse_id, warehouse_name, is_active, checked_at}] + locations_active + 마지막 ping(last_ping_ok · last_ping_at · last_ping_error · shop_call_log action ping) · security_invoker · select 만(미룬 159 모양을 되풀이하지 않는다)';

-- ═══ 7) 시작값 — test 스토어 한 행(판정 403: Price Wholesale · Compare-at wholesalespecia CAD · asung.ca 를 흉내 낸다) · 위치 짝은 shop-1b ping 뒤 화면에서 ═══
do $$
declare v_sale uuid; v_cmp uuid;
begin
  select id into v_sale from public.ref_price_tier where name = 'Wholesale' and is_active and purpose = 'sale';
  select id into v_cmp  from public.ref_price_tier where name = 'wholesalespecia CAD' and is_active and purpose in ('sale', 'compare');
  if v_sale is null or v_cmp is null then
    raise exception 'shop-1a seed: price tier Wholesale (%) or wholesalespecia CAD (%) not found — nothing was changed', v_sale, v_cmp;
  end if;
  insert into public.shop_store (code, shop_domain, label, kind, sale_tier_id, compare_tier_id, secret_prefix, note)
  values ('test', 'asung-ims-test.myshopify.com', 'Asung IMS test store', 'asung', v_sale, v_cmp, 'SHOPIFY_IMS',
          'shop-1a 시작값 · Dev store · organization Asung Trading · 앱 Asung IMS v1scopes · 열쇠는 테스트 프로젝트 secrets SHOPIFY_IMS_CLIENT_ID / _CLIENT_SECRET');
end $$;
