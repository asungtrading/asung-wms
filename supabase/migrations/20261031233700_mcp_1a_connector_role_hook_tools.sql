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
-- mcp-1a — IMS Claude 커넥터 DB 바탕 + 읽기 도구 ① ~ ⑤ (2026-10-31 UTC · 판정 917 ~ 923 · 지시서 ~/asung/prompts/mcp-1a.md · 이견 1 ~ 16 답 반영)
--   A 역할 ims_connector(nologin noinherit · authenticator 멤버 · statement_timeout 8s · 표 · 뷰 · 시퀀스 권한 0) + PUBLIC `=X` 가 박힌 옛 함수 9 의 PUBLIC 회수(이견 2 — 7 트리거 함수 + 2 호출 전용 · 실측: 트리거는 EXECUTE 없이 돈다 · anon · authenticated · service_role 의 X 는 그대로)
--     ⚠️ 기본 권한(pg_default_acl postgres · public · f)에 PUBLIC 이 없다(실측) — alter default privileges 는 넣지 않는다(이견 1)
--   B 설정 한 줄 표 mcp_config(singleton · claude_client_id · 행 하나 심음) · RLS + supabase_auth_admin select 정책 · 창구 mcp_config_get(admin) · mcp_config_set(admin · null = 끄기 · REST WHERE = where singleton)
--   C 훅 ims_access_token_hook(event) — client_id 클레임 없음 → 입력 그대로(어떤 예외에도) · 있고 mcp_config 와 같음 → claims.role = 'ims_connector' · 다르거나 null → {"error":{"http_code":403,…}}(Supabase 문서 SSO 예의 꼴) · 표 하나 읽기 외 아무것도 안 한다
--     ⚠️ authentication_method 는 보지 않는다('oauth' = 소셜 로그인 값 · 이견 3) · role 을 임의 역할로 바꿀 수 있는지는 짐작 — mcp-4 실연결에서 확인(917)
--   D 열쇠 claude — ims_perm_catalog 재발행(20261028201500:43 ~ 70 바이트 복사 + claude 한 줄) · 문 mcp_gate(p_screen): client_id = mcp_config(이견 5) · 활성 직원 · perms ? 'claude' | 'claude:read'(이견 6 · admin · supervisor 도 켜야 한다 · 921) · p_screen 이면 ims_can_view
--   E 도구 ① mcp_order ② mcp_stock ③ mcp_customer ④ mcp_po ⑤ mcp_backorders — definer · stable · 첫 줄 mcp_gate · jsonb 한 행 · 허용 목록으로 골라 담는다(923 · 919) · EXECUTE 는 ims_connector 에만
--     도우미 mcp_warehouse_id · mcp_customer_pick(내부 · EXECUTE 아무에게도 안 준다 · definer 셸이 postgres 로 부른다)
--   무접촉: ims_can_view · ims_can_write · so_detail · stk_availability · so_customer_balance_many · so_customer_overdue · po_detail · so_backorder_list · 화면 · 대시보드(OAuth Server · Hook 토글은 mcp-4) · 첫 문장 = guard-test-only.sql 바이트 복사
--   컷오버 날 지우기: mcp_config 는 거래 표에 FK 가 없다 — 지우기 대상 아님
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261031233700_mcp_1a_connector_role_hook_tools.sql && supabase migration repair --status applied 20261031233700 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): MIG=supabase/migrations/20261031233700_mcp_1a_connector_role_hook_tools.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/mcp_1a_check.sql

-- ═══ A) 역할 ims_connector ═══
create role ims_connector nologin noinherit;
comment on role ims_connector is 'mcp-1a 판정 917: Claude 커넥터 토큰의 역할 — 훅이 OAuth 토큰(client_id = mcp_config.claude_client_id)의 role 을 이것으로 찍고 PostgREST 가 set role 한다 · 권한 = mcp_* 도구 창구 EXECUTE 만(표 · 뷰 · 시퀀스 · 그 밖의 함수 · Storage 0)';
grant ims_connector to authenticator;
alter role ims_connector set statement_timeout = '8s';
grant usage on schema public to ims_connector;
-- PUBLIC `=X` 9(이견 2): 트리거 함수 7 + ims_html_forbidden(product_update 안에서만) + wms_pallet_frozen_check(wms_pallet_freeze · item_freeze 안에서만) — 명시 X(anon · authenticated · service_role)는 그대로
revoke execute on function public.set_updated_at() from public;
revoke execute on function public.wms_pallet_dims() from public;
revoke execute on function public.wms_reports_planned_empty_once() from public;
revoke execute on function public.wms_reports_resolved_how_stamp() from public;
revoke execute on function public.so_line_combo_parent_check() from public;
revoke execute on function public.ims_html_forbidden(text) from public;
revoke execute on function public.wms_pallet_frozen_check(uuid, text) from public;
revoke execute on function public.wms_pallet_freeze() from public;
revoke execute on function public.wms_pallet_item_freeze() from public;

-- ═══ B) mcp_config — 한 줄 표 ═══
create table public.mcp_config (
  singleton        boolean primary key default true check (singleton),
  claude_client_id text,
  updated_at       timestamptz not null default now(),
  updated_by       uuid references public.ims_staff(id)
);
comment on table public.mcp_config is 'mcp-1a 판정 922: Claude 커넥터 설정 한 줄 — claude_client_id = 대시보드에 손으로 등록한 Claude OAuth client 의 id(null = 아직 등록 전 = 커넥터 토큰 전부 거부) · 훅(supabase_auth_admin)이 읽고 admin 이 mcp_config_set 으로 쓴다 · 거래 표 FK 없음(컷오버 지우기 대상 아님)';
create trigger mcp_config_touch before update on public.mcp_config for each row execute function public.ims_touch();
insert into public.mcp_config (singleton, claude_client_id) values (true, null);
alter table public.mcp_config enable row level security;
create policy mcp_config_select_auth_admin on public.mcp_config for select to supabase_auth_admin using (true);
revoke all on table public.mcp_config from public, anon, authenticated, service_role, ims_connector;
grant usage on schema public to supabase_auth_admin;
grant select on table public.mcp_config to supabase_auth_admin;

create or replace function public.mcp_config_get() returns jsonb
  language sql stable security definer set search_path = public, pg_temp
as $$
  select case when public.ims_is_admin() then
    (select jsonb_build_object('client_id', c.claude_client_id, 'updated_at', c.updated_at, 'updated_by_name', (select s.name from public.ims_staff s where s.id = c.updated_by))
       from public.mcp_config c where c.singleton)
  else null end;
$$;
comment on function public.mcp_config_get() is 'mcp-1a: Claude 커넥터 설정 읽기(admin 만 · 아니면 null) — Settings 화면용';

create or replace function public.mcp_config_set(p_client_id text) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
begin
  perform public.ims_require_admin('the Claude connector client');
  update public.mcp_config set claude_client_id = nullif(btrim(p_client_id), '') where singleton;   -- REST safeupdate: WHERE 필수(행 하나 표는 where singleton)
  return public.mcp_config_get();
end;
$$;
comment on function public.mcp_config_set(text) is 'mcp-1a 판정 922: Claude OAuth client id 를 적는다(admin · null · 빈 글 = 끄기 = 커넥터 토큰 전부 거부) · ims_touch 가 updated_at · updated_by';

-- ═══ C) 훅 ims_access_token_hook ═══
create or replace function public.ims_access_token_hook(event jsonb) returns jsonb
  language plpgsql stable security invoker set search_path = public, pg_temp
as $$
declare
  v_claims jsonb;
  v_cid    text;
  v_cfg    text;
begin
  -- 갈래 1: client_id 클레임이 없으면(직원 화면 로그인 · 갱신 · 소셜 로그인 포함) 어떤 경우에도 입력 그대로
  begin
    v_claims := event->'claims';
    if v_claims is null or jsonb_typeof(v_claims) <> 'object' then return event; end if;
    v_cid := v_claims->>'client_id';
    if v_cid is null then return event; end if;
  exception when others then
    return event;
  end;
  -- 갈래 2: OAuth client 토큰 — 등록된 Claude client 만 ims_connector 로 · 그 밖은 거부(예외도 거부 · fail-closed)
  begin
    select c.claude_client_id into v_cfg from public.mcp_config c where c.singleton;
    if v_cfg is not null and v_cfg = v_cid then
      return jsonb_set(event, '{claims,role}', to_jsonb('ims_connector'::text), true);
    end if;
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'This OAuth client is not registered for the IMS Claude connector'));
  exception when others then
    return jsonb_build_object('error', jsonb_build_object('http_code', 403, 'message', 'IMS could not verify the OAuth client — token refused'));
  end;
end;
$$;
comment on function public.ims_access_token_hook(jsonb) is 'mcp-1a 판정 917 · 922: Supabase Custom Access Token Hook — claims.client_id 없음 → 입력 그대로 · = mcp_config.claude_client_id → claims.role = ims_connector · 다름 · null → {"error":{"http_code":403}} · ⚠️ 켜는 것은 대시보드(mcp-4) · 터지면 모든 로그인이 막히므로 갈래 1 은 예외에도 입력 그대로';
revoke execute on function public.ims_access_token_hook(jsonb) from public, anon, authenticated, service_role, ims_connector;
grant execute on function public.ims_access_token_hook(jsonb) to supabase_auth_admin;

-- ═══ D) 열쇠 claude — ims_perm_catalog 재발행(20261028201500:43 ~ 70 바이트 복사 + claude 한 줄 — freight_booking(마지막 · 쉼표 없음) 앞에) ═══
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
      "transfer":              {"room": "ims", "label": "Transfers — warehouse to warehouse (person by person · off until switched on)"},
      "doc_template":          {"room": "ims", "min_role": "supervisor", "label": "Document templates — publish a layout version (admin always · supervisor only when switched on · off until switched on)"},
      "cost":                  {"room": "ims", "label": "Inventory cost — stock value, layer values, unit costs (admin and supervisor always · person by person · read and write both show it · off until switched on)"},
      "claude":                {"room": "ims", "label": "Claude connector — ask Claude about orders, stock, customers, POs and backorders (person by person · admins and supervisors must be switched on too · read only · off until switched on)"},
      "freight_booking":       {"room": "ims", "rooms": ["wms", "ims"], "label": "Freight booking — book, cancel and re-book Freightcom shipments (admin and supervisor always · person by person · warehouse and office each switched on · quotes stay with sales / fulfillment · off until switched on)"}
    }
  }'::jsonb;
$$;
do $$ begin
  execute format('comment on function public.ims_perm_catalog() is %L',
    obj_description(to_regprocedure('public.ims_perm_catalog()'), 'pg_proc')
    || ' · ⭐ [2026-10-31 mcp-1a] screens.claude(Claude 커넥터 · 판정 921 — ⚠️ admin · supervisor 도 켜야 한다 · mcp_gate 가 perms ? claude | claude:read 를 글자 그대로 본다 · ims_can_view(claude) 는 쓰지 않는다)');
end $$;

create or replace function public.mcp_gate(p_screen text) returns uuid
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_claims jsonb := nullif(current_setting('request.jwt.claims', true), '')::jsonb;
  v_cid    text  := null;
  v_cfg    text;
  v_id     uuid;
  v_perms  jsonb;
begin
  v_cid := v_claims->>'client_id';
  if v_cid is null then
    raise exception 'This tool can only be used through the Claude connector (no OAuth client in the token) — nothing was read';
  end if;
  select c.claude_client_id into v_cfg from public.mcp_config c where c.singleton;
  if v_cfg is null or v_cfg <> v_cid then
    raise exception 'This OAuth client is not the registered Claude connector — nothing was read';
  end if;
  select s.id, s.perms into v_id, v_perms from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_id is null then
    raise exception 'No active staff record for this login — nothing was read';
  end if;
  if not (v_perms ? 'claude' or v_perms ? 'claude:read') then
    raise exception 'Your account does not have the ''claude'' permission — ask an admin to switch it on in Staff — nothing was read';
  end if;
  if p_screen is not null and not public.ims_can_view(p_screen) then
    raise exception 'You need the ''%'' permission to use this tool — nothing was read', p_screen;
  end if;
  return v_id;
end;
$$;
comment on function public.mcp_gate(text) is 'mcp-1a 판정 921: 커넥터 도구의 문 — 부를 때마다 본다(끄면 다음 질문부터 거절) · claims.client_id = mcp_config(이견 5) · 활성 직원 · perms ? claude | claude:read 글자 그대로(admin · supervisor 도 켜야 한다) · p_screen 이면 ims_can_view(p_screen) 도 · 돌려주는 것 = ims_staff.id';

-- ═══ E) 도우미 둘(내부) ═══
create or replace function public.mcp_warehouse_id(p_name text) returns uuid
  language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce(
    (select w.id from public.ref_warehouse w where w.is_active and (lower(w.name) = lower(btrim(p_name)) or lower(coalesce(w.city, '')) = lower(btrim(p_name))) limit 1),
    (select case when count(*) = 1 then (array_agg(w.id))[1] end from public.ref_warehouse w where w.is_active and (w.name ilike '%' || btrim(p_name) || '%' or w.city ilike '%' || btrim(p_name) || '%')));
$$;
comment on function public.mcp_warehouse_id(text) is 'mcp-1a 이견 8: 창고 이름 · city(정확 → 포함 유일) → id · 못 풀면 null(ref_warehouse 에 code 칸 없음 · 이름은 짐작하지 않는다)';

create or replace function public.mcp_customer_pick(p_q text) returns jsonb
  language sql stable security definer set search_path = public, pg_temp
as $$
  with m as (
    select c.id, c.name, c.display_name, c.is_active, c.price_tier, (lower(c.name) = lower(btrim(p_q)) or lower(coalesce(c.display_name, '')) = lower(btrim(p_q))) as exact
      from public.customer c
     where c.name ilike '%' || btrim(p_q) || '%' or c.display_name ilike '%' || btrim(p_q) || '%'
  )
  select jsonb_build_object(
    'matches', (select count(*) from m),
    'id', coalesce((select id from m where exact order by is_active desc, name limit 1), (select case when count(*) = 1 then (array_agg(id))[1] end from m)),
    'candidates', (select coalesce(jsonb_agg(jsonb_build_object('name', x.name, 'display_name', x.display_name, 'is_active', x.is_active, 'price_tier', x.price_tier) order by x.exact desc, x.is_active desc, x.name), '[]'::jsonb)
                     from (select * from m order by exact desc, is_active desc, name limit 5) x));
$$;
comment on function public.mcp_customer_pick(text) is 'mcp-1a 이견 9: 손님 이름 검색 → {matches, id(정확 일치 또는 유일 포함이면 · 아니면 null), candidates ≤ 5(이름 · 표시 이름 · 활성 · 티어 — 연락처 없음 923)}';

-- ═══ E ①) mcp_order ═══
create or replace function public.mcp_order(p_so_number text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_no text := upper(btrim(coalesce(p_so_number, '')));
  v_id uuid;
  d    jsonb;
  s    jsonb;
  t    jsonb;
  i    jsonb;
begin
  perform public.mcp_gate('sales');
  if v_no ~ '^[0-9]+[A-Z]*$' then v_no := 'SO-' || v_no; end if;
  select x.id into v_id from public.so x where upper(x.so_number) = v_no;
  if v_id is null then return jsonb_build_object('found', false, 'so_number', v_no); end if;
  d := public.so_detail(v_id);  s := d->'so';  t := d->'totals';  i := d->'invoice';
  return jsonb_build_object(
    'found', true,
    'so_number', s->>'so_number', 'status', s->>'status', 'channel', s->>'channel', 'intake', s->>'intake', 'warehouse', s->>'location_name',
    'order_date', s->'order_date', 'required_by', s->'required_by', 'confirmed_at', s->'confirmed_at', 'shipped_at', s->'shipped_at', 'invoiced_at', s->'invoiced_at',
    'closed_at', s->'closed_at', 'cancelled_at', s->'cancelled_at', 'closed_reason', s->'closed_reason',
    'customer_name', d->>'customer_name', 'currency', s->>'currency_code', 'price_tier', s->>'price_tier', 'payment_term', s->>'payment_term_name',
    'carrier', s->>'carrier', 'tracking_number', s->>'tracking_number',
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'line_no', l->'line_no', 'sku', l->>'sku', 'name', l->>'product_name', 'unit', l->>'unit', 'pack_factor', l->'pack_factor',
                'qty_ordered', l->'qty_ordered', 'qty_shipped', l->'qty_shipped', 'qty_credited', l->'qty_credited', 'qty_removed', l->'qty_removed',
                'list_price', l->'list_price', 'unit_price', l->'unit_price', 'discount_pct', l->'discount_pct', 'line_total', l->'total',
                'is_combo', l->'is_combo', 'combo_sku', l->'combo_sku') order by (l->>'line_no')::int), '[]'::jsonb)
              from jsonb_array_elements(coalesce(d->'lines', '[]'::jsonb)) l),
    'charges', (select coalesce(jsonb_agg(jsonb_build_object('name', c->>'name', 'qty', c->'qty', 'amount', c->'amount', 'discount', c->'discount', 'net', c->'net') order by (c->>'line_no')::int), '[]'::jsonb)
                  from jsonb_array_elements(coalesce(d->'charges', '[]'::jsonb)) c),
    'totals', jsonb_build_object('basis', t->>'basis', 'lines_total', t->'lines_total', 'order_discount_pct', t->'order_discount_pct', 'order_discount_amount', t->'order_discount_amount',
                                 'charges_total', t->'charges_net_total', 'surcharge', t->'surcharge_amount', 'order_total', t->'order_total', 'tax', t->'tax', 'order_total_with_tax', t->'order_total_with_tax'),
    'invoice', case when i is null or jsonb_typeof(i) = 'null' then null else
                 jsonb_build_object('invoice_number', i->>'invoice_number', 'status', i->>'status', 'issued_on', i->'issued_on', 'due_on', i->'due_on',
                                    'total', i->'total', 'paid', i->'paid', 'remaining', i->'remaining', 'credited_total', i->'credited_total') end,
    'warnings', d->'warnings');
end;
$$;
comment on function public.mcp_order(text) is 'mcp-1a 도구 ①(918 · 923): SO 번호(SO-xxxxx · 숫자만도) → 번호 · 상태 · 날짜 · 손님 이름 · 채널 · 줄(판매가 · 할인 · 수량) · 합계 · 세금 · 인보이스 · 운송사 · 추적번호 — 주소 · 전화 · 메모 없음 · 문 sales · 없으면 {found:false}';

-- ═══ E ②) mcp_stock ═══
create or replace function public.mcp_stock(p_q text, p_warehouse text default null, p_limit int default 20) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_q   text := nullif(btrim(coalesce(p_q, '')), '');
  v_w   text := nullif(btrim(coalesce(p_warehouse, '')), '');
  v_lim int  := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_wh  uuid;
begin
  perform public.mcp_gate(null);                                                     -- 재고 조회는 열쇠 없음(판정 258 · stk_availability 의 활성 직원 문이 그대로 돈다)
  if v_q is null then raise exception 'Give a SKU, barcode, product name or brand to search — nothing was read'; end if;
  if v_w is not null then
    v_wh := public.mcp_warehouse_id(v_w);
    if v_wh is null then
      return jsonb_build_object('warehouse_not_found', v_w,
                                'warehouses', (select jsonb_agg(jsonb_build_object('name', w.name, 'city', w.city) order by w.name) from public.ref_warehouse w where w.is_active));
    end if;
  end if;
  return (select jsonb_build_object(
            'query', v_q, 'warehouse', (select w.name from public.ref_warehouse w where w.id = v_wh), 'total', coalesce(max(r.total), 0), 'returned', count(*),
            'rows', coalesce(jsonb_agg(jsonb_build_object(
              'sku', r.sku, 'name', r.name, 'brand', r.brand_name, 'category', r.category_name, 'is_active', r.is_active,
              'on_hand', r.on_hand, 'sales_allocated', r.sales_allocated, 'transfer_reserved', r.transfer_reserved, 'available', r.available,
              'on_order', r.on_order, 'in_transit', r.in_transit, 'last_event_on', r.last_event_on,
              'matched_set_sku', r.matched_set_sku, 'matched_set_pack_factor', r.matched_set_pack_factor, 'sale_pct', r.sale_pct,
              'by_warehouse', (select jsonb_agg(jsonb_build_object('warehouse', w->>'warehouse', 'on_hand', w->'on_hand', 'sales_allocated', w->'sales_allocated', 'transfer_reserved', w->'transfer_reserved',
                                                                   'available', w->'available', 'on_order', w->'on_order', 'in_transit', w->'in_transit'))
                                 from jsonb_array_elements(coalesce(r.by_warehouse, '[]'::jsonb)) w)) order by r.sku), '[]'::jsonb))
          from public.stk_availability(v_wh, v_q, null, null, false, v_lim, 0, false, null) r);
end;
$$;
comment on function public.mcp_stock(text, text, int) is 'mcp-1a 도구 ②(918): SKU · 바코드 · 이름 · 브랜드 검색 → stk_availability(창고 null = 두 창고 합 + by_warehouse) · 창고는 이름 · city 로(못 풀면 창고 목록) · p_limit 1 ~ 50 · 원가 칸 없음(919)';

-- ═══ E ③) mcp_customer ═══
create or replace function public.mcp_customer(p_q text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_q  text := nullif(btrim(coalesce(p_q, '')), '');
  pk   jsonb;
  v_id uuid;
  o    jsonb;
begin
  perform public.mcp_gate('sales');
  if v_q is null then raise exception 'Give a customer name to search — nothing was read'; end if;
  pk := public.mcp_customer_pick(v_q);
  v_id := (pk->>'id')::uuid;
  if v_id is null then
    return jsonb_build_object('found', false, 'query', v_q, 'matches', pk->'matches', 'candidates', pk->'candidates');
  end if;
  o := public.so_customer_overdue(v_id);
  return jsonb_build_object(
    'found', true, 'matches', pk->'matches',
    'customer', (select jsonb_build_object('name', c.name, 'display_name', c.display_name, 'is_active', c.is_active, 'price_tier', c.price_tier, 'payment_term', c.payment_term_name,
                                           'currency', c.currency_code, 'default_warehouse', c.default_location_name,
                                           'bill_to_name', (select b.name from public.customer b where b.id = c.default_bill_to_customer_id),
                                           'parent_name', (select p.name from public.customer p where p.id = c.parent_id))
                   from public.customer c where c.id = v_id),
    'balance', (select coalesce(jsonb_agg(jsonb_build_object('currency', b.currency_code, 'received', b.received, 'reserved_deposit', b.reserved_deposit, 'owed_credit', b.owed_credit,
                                                             'available', b.available, 'open_invoices', b.open_invoices, 'open_invoices_due', b.open_invoices_due) order by b.currency_code), '[]'::jsonb)
                  from public.so_customer_balance_many(array[v_id]) b),
    'overdue', jsonb_build_object('as_of', o->'as_of', 'count', o->'count', 'oldest_days', o->'oldest_days', 'by_currency', o->'by_currency',
                                  'bill_to_name', o->>'bill_to_name', 'bill_to_differs', o->'bill_to_differs',
                                  'invoices', (select coalesce(jsonb_agg(jsonb_build_object('invoice_number', x->>'invoice_number', 'issued_on', x->'issued_on', 'due_on', x->'due_on',
                                                                                            'days_overdue', x->'days_overdue', 'remaining', x->'remaining', 'currency', x->>'currency_code')), '[]'::jsonb)
                                                 from jsonb_array_elements(coalesce(o->'invoices', '[]'::jsonb)) x)),
    'recent_orders', (with r as (select x.id, x.so_number, x.order_date, x.status, x.location_name from public.so x where x.customer_id = v_id order by x.order_date desc, x.so_number desc limit 10)
                      select coalesce(jsonb_agg(jsonb_build_object('so_number', r.so_number, 'order_date', r.order_date, 'status', r.status, 'warehouse', r.location_name,
                                                                   'order_total', t.order_total, 'order_total_with_tax', t.order_total_with_tax) order by r.order_date desc, r.so_number desc), '[]'::jsonb)
                        from r left join public.so_totals_many((select array_agg(z.id) from r z)) t on t.so_id = r.id));
end;
$$;
comment on function public.mcp_customer(text) is 'mcp-1a 도구 ③(918 · 923): 손님 이름 검색 → 정확 · 유일이면 요약(티어 · 조건 · 잔액 so_customer_balance_many · 연체 so_customer_overdue · 최근 SO 10 + so_totals_many) · 아니면 후보 ≤ 5 — 주소 · 전화 · 이메일 · 메모 없음 · 문 sales';

-- ═══ E ④) mcp_po ═══
create or replace function public.mcp_po(p_po_number text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_no text := upper(btrim(coalesce(p_po_number, '')));
  v_id uuid;
  d    jsonb;
  h    jsonb;
begin
  perform public.mcp_gate('purchasing');
  if v_no ~ '^[0-9]+[A-Z]*$' then v_no := 'PO-' || v_no; end if;
  select x.id into v_id from public.po x where upper(x.po_number) = v_no;
  if v_id is null then return jsonb_build_object('found', false, 'po_number', v_no); end if;
  d := public.po_detail(v_id);  h := d->'header';
  return jsonb_build_object(
    'found', true,
    'po_number', h->>'po_number', 'status', h->>'status', 'supplier_name', h->>'supplier_name', 'order_date', h->'order_date', 'required_by', h->'required_by',
    'ship_to_warehouse', h->>'ship_to_warehouse', 'currency', h->>'currency_code', 'payment_term', h->>'payment_term_name',
    'confirmed_at', h->'confirmed_at', 'closed_at', h->'closed_at', 'cancelled_at', h->'cancelled_at', 'split_from_number', h->'split_from_number',
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'line_no', l->'line_no', 'sku', l->>'sku', 'name', l->>'product_name', 'supplier_sku', l->>'supplier_sku',
                'qty_ordered', l->'qty_ea', 'qty_received', l->'received_qty', 'qty_remaining', l->'remaining_qty',
                'entered_unit_sku', l->'entered_unit_sku', 'entered_qty', l->'entered_qty') order by (l->>'line_no')::int), '[]'::jsonb)
              from jsonb_array_elements(coalesce(d->'lines', '[]'::jsonb)) l),
    'totals', jsonb_build_object('ordered_qty', d->'totals'->'ordered_qty', 'received_qty', d->'totals'->'received_qty'),
    'receipts', (select coalesce(jsonb_agg(jsonb_build_object('receipt_number', r.receipt_number, 'received_on', r.received_on, 'status', r.status, 'warehouse', w.name,
                                                              'qty_ea', (select coalesce(sum(rl.qty_ea), 0) from public.po_receipt_line rl where rl.receipt_id = r.id)) order by r.received_on, r.receipt_number), '[]'::jsonb)
                   from public.po_receipt r left join public.ref_warehouse w on w.id = r.warehouse_id where r.po_id = v_id));
end;
$$;
comment on function public.mcp_po(text) is 'mcp-1a 도구 ④(918 · 919): PO 번호 → 번호 · 상태 · 공급처 이름 · 날짜 · 줄(sku · 주문 · 받은 · 남은 수량) · 입고 목록(번호 · 날짜 · 상태) — 단가 · 금액 · 운임 · landed · 인보이스 · 결제 · 공급처 연락처 · 주소 · 메모 없음 · 문 purchasing';

-- ═══ E ⑤) mcp_backorders ═══
create or replace function public.mcp_backorders(p_filters jsonb default '{}'::jsonb, p_limit int default 50) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  f      jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys constant text[] := array['customer', 'brand', 'warehouse', 'sku', 'state', 'kind', 'owed', 'arrived'];
  v_bad  text;
  g      jsonb := jsonb_build_object('limit', least(greatest(coalesce(p_limit, 50), 1), 100)::text);
  pk     jsonb;
  v_wh   uuid;
  v_br   uuid;
  r      jsonb;
begin
  perform public.mcp_gate('sales');
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object — nothing was read'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter % — allowed: customer, brand, warehouse, sku, state, kind, owed, arrived — nothing was read', v_bad; end if;
  if f ? 'customer' then
    pk := public.mcp_customer_pick(f->>'customer');
    if pk->>'id' is null then return jsonb_build_object('resolved', false, 'field', 'customer', 'matches', pk->'matches', 'candidates', pk->'candidates'); end if;
    g := g || jsonb_build_object('customer_id', pk->>'id');
  end if;
  if f ? 'brand' then
    select case when count(*) = 1 then (array_agg(b.id))[1] end into v_br from public.ref_brand b where b.name ilike '%' || btrim(f->>'brand') || '%' or lower(b.name) = lower(btrim(f->>'brand'));
    if v_br is null then select b.id into v_br from public.ref_brand b where lower(b.name) = lower(btrim(f->>'brand')) limit 1; end if;
    if v_br is null then
      return jsonb_build_object('resolved', false, 'field', 'brand',
                                'candidates', (select coalesce(jsonb_agg(b.name order by b.name), '[]'::jsonb) from (select b.name from public.ref_brand b where b.name ilike '%' || btrim(f->>'brand') || '%' order by b.name limit 10) b));
    end if;
    g := g || jsonb_build_object('brand_id', v_br::text);
  end if;
  if f ? 'warehouse' then
    v_wh := public.mcp_warehouse_id(f->>'warehouse');
    if v_wh is null then
      return jsonb_build_object('resolved', false, 'field', 'warehouse',
                                'warehouses', (select jsonb_agg(jsonb_build_object('name', w.name, 'city', w.city) order by w.name) from public.ref_warehouse w where w.is_active));
    end if;
    g := g || jsonb_build_object('location_id', v_wh::text);
  end if;
  g := g || (f - 'customer' - 'brand' - 'warehouse');                                 -- sku · state · kind · owed · arrived 는 그대로 넘긴다(so_backorder_list 가 값을 검사)
  r := public.so_backorder_list(g);
  return jsonb_build_object(
    'total', r->'total', 'open', r->'open', 'ended', r->'ended', 'open_owed', r->'open_owed', 'open_backorder', r->'open_backorder', 'open_preorder', r->'open_preorder',
    'limit', r->'limit', 'filters', f, 'arrived_rule', r->'arrived_rule',
    'rows', (select coalesce(jsonb_agg(jsonb_build_object(
               'so_number', x->>'so_number', 'order_date', x->'order_date', 'customer_name', x->>'customer_name', 'warehouse', x->>'location_name',
               'sku', x->>'sku', 'base_sku', x->>'base_sku', 'name', x->>'product_name', 'pack_factor', x->'pack_factor', 'brand', x->>'brand_name', 'supplier', x->>'supplier_name',
               'qty_ordered', x->'qty_ordered', 'qty_open', x->'qty_open', 'backorder_since', x->'backorder_since', 'days_waiting', x->'days_waiting',
               'state', x->>'state', 'kind', x->>'kind', 'end_kind', x->'end_kind', 'qty_taken', x->'qty_taken', 'qty_unwanted', x->'qty_unwanted',
               'taken_by_so_number', x->'taken_by_so_number', 'ended_at', x->'ended_at', 'owed', x->'owed', 'arrived', x->'arrived',
               'available_here', x->'available_here', 'available_other', x->'available_other', 'is_combo', x->'is_combo',
               'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c->>'sku', 'name', c->>'product_name', 'combo_qty', c->'combo_qty')), '[]'::jsonb)
                                from jsonb_array_elements(case when jsonb_typeof(x->'components') = 'array' then x->'components' else '[]'::jsonb end) c))), '[]'::jsonb)
             from jsonb_array_elements(coalesce(r->'rows', '[]'::jsonb)) x));
end;
$$;
comment on function public.mcp_backorders(jsonb, int) is 'mcp-1a 도구 ⑤(918 · 923 · 이견 9): so_backorder_list 를 이름 열쇠(customer · brand · warehouse · sku · state · kind · owed · arrived)로 — 이름을 유일하게 풀어 uuid 로 넘기고 못 풀면 {resolved:false, candidates} · p_limit 1 ~ 100 · 메모 · 연락처 없음 · 문 sales';

-- ═══ 권한 — 도구 ①~⑤ 는 ims_connector 만 · 도우미는 아무에게도 · 설정 창구는 authenticated(admin 은 함수 안에서) ═══
revoke all on function public.mcp_gate(text), public.mcp_warehouse_id(text), public.mcp_customer_pick(text),
                       public.mcp_order(text), public.mcp_stock(text, text, int), public.mcp_customer(text), public.mcp_po(text), public.mcp_backorders(jsonb, int),
                       public.mcp_config_get(), public.mcp_config_set(text)
  from public, anon, authenticated, service_role, ims_connector;
grant execute on function public.mcp_order(text), public.mcp_stock(text, text, int), public.mcp_customer(text), public.mcp_po(text), public.mcp_backorders(jsonb, int) to ims_connector;
grant execute on function public.mcp_config_get(), public.mcp_config_set(text) to authenticated;

-- ═══ 착지 검사 ═══
do $$
declare v text; v_n int;
begin
  if not exists (select 1 from pg_roles where rolname = 'ims_connector' and not rolcanlogin and not rolinherit) then raise exception 'mcp-1a landing: role ims_connector'; end if;
  if not exists (select 1 from pg_auth_members m join pg_roles r on r.oid = m.roleid join pg_roles u on u.oid = m.member where r.rolname = 'ims_connector' and u.rolname = 'authenticator') then raise exception 'mcp-1a landing: authenticator membership'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE');
  if v_n <> 0 then raise exception 'mcp-1a landing: PUBLIC EXECUTE still on % public functions', v_n; end if;
  select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_order', 'mcp_stock', 'mcp_customer', 'mcp_po', 'mcp_backorders');
  if v <> 'mcp_backorders={postgres=X/postgres,ims_connector=X/postgres} mcp_customer={postgres=X/postgres,ims_connector=X/postgres} mcp_order={postgres=X/postgres,ims_connector=X/postgres} mcp_po={postgres=X/postgres,ims_connector=X/postgres} mcp_stock={postgres=X/postgres,ims_connector=X/postgres}' then raise exception 'mcp-1a landing: tool acl %', v; end if;
  select p.proacl::text into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'ims_access_token_hook';
  if v <> '{postgres=X/postgres,supabase_auth_admin=X/postgres}' then raise exception 'mcp-1a landing: hook acl %', v; end if;
  select string_agg(p.proname || '=' || p.proacl::text, ' ' order by p.proname) into v from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('mcp_gate', 'mcp_warehouse_id', 'mcp_customer_pick');
  if v <> 'mcp_customer_pick={postgres=X/postgres} mcp_gate={postgres=X/postgres} mcp_warehouse_id={postgres=X/postgres}' then raise exception 'mcp-1a landing: helper acl %', v; end if;
  select c.relacl::text || ' rls=' || c.relrowsecurity::text into v from pg_class c where c.oid = 'public.mcp_config'::regclass;
  if v <> '{postgres=arwdDxtm/postgres,supabase_auth_admin=r/postgres} rls=true' then raise exception 'mcp-1a landing: mcp_config acl %', v; end if;
  if (select count(*) from public.mcp_config) <> 1 then raise exception 'mcp-1a landing: mcp_config row'; end if;
  if not (public.ims_perm_catalog()->'screens' ? 'claude') then raise exception 'mcp-1a landing: catalog claude'; end if;
  raise notice 'mcp-1a landing OK — role · membership · PUBLIC EXECUTE 0 · tool acl · hook acl · helper acl · mcp_config acl+rls · row 1 · catalog claude';
end $$;
