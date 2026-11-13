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
-- so-shipto-1 — Finalized(packed) 오더의 배송지 바꾸기 · DB 창구 so_ship_to_change (2026-11-12 · 판정 1200 ~ 1210 · 조사 so-shipto-0)
--   계기: asung.ca 손님(아마존 셀러)은 어느 창고로 보낼지가 마지막에 정해진다 — Ship & invoice 전에 배송지를 바꿀 길이 없었다(so_header_update 는 draft 만)
--   판정: 1206 자리 = Ship & invoice 창 · 상태 = packed 만(draft 길 · confirmed · at_wms · picking 무변) · 1200 다른 주 허락 + 세금을 새 배송지로 · 1205 주 · 나라가 바뀌는 변경은 aone 오더만 거부
--         1201 살아 있는 예약(booked · pending)이면 거부 · 주소가 바뀌면 그 SO 가 든 live 발송을 통째로 cancelled(fc_book_prepare 가 견적 때 굳힌 옛 목적지를 그대로 보내므로) · 1203 문 = sales
--         1204 · 1207 주소록에서 고르거나 새로 적는다 · 새로 적은 것은 주소록에 추가만(기본 승격 없음) · 1209 하나만 바꾸기 허락(shipment_siblings_cut) · 유닛을 나눠 가졌으면 거부 · 1210 세금 규칙이 바뀌면 tax_changed
--   만드는 것: ① 속 함수 so_tax_refresh_at(so_tax_refresh 의 몸 + p_status) · so_tax_refresh 는 그 껍데기(서명 · 권한 · 동작 그대로 — 원본 = DB prosrc md5 가드)
--             ② 기록 표 so_ship_to_log(닫힘 — RLS on · 정책 0 · 권한 0 · 창구로만 쓴다 · 읽기 창구 없음) ③ 창구 so_ship_to_change
--   무접촉: so_header_update · so_copy_customer · fc_book_* · fc_shipment_prepare · shop_* · WMS · doc_data · Shopify 오더 주소 · doc_file
--   ⚠️ 컷오버 날 지우는 순서: so_ship_to_log 는 so 를 FK 로 문다(so_id · restrict) → 거래 지우기에서 **so 보다 먼저** so_ship_to_log 를 지운다(ims_staff FK changed_by 는 직원을 지우지 않으므로 무관) · 시퀀스 0
--   검증 supabase/tests/so_shipto_1_check.sql

-- ⓪ 원본 가드 — so_tax_refresh 가 조사 때 읽은 몸(20260924175014)이 아니면 아무것도 바꾸지 않는다(이미 껍데기면 지나간다)
do $$
declare v_md5 text;  v_src text;
begin
  select md5(p.prosrc), p.prosrc into v_md5, v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_tax_refresh';
  if v_md5 is distinct from '9853a21ea38bf74cd2719ed593268ed5' and coalesce(v_src, '') !~ 'so_tax_refresh_at' then
    raise exception 'so-shipto-1: so_tax_refresh is not the body this migration was written against (md5 %) — nothing was changed', coalesce(v_md5, '<missing>');
  end if;
end $$;

-- ═══ 1) 속 함수 so_tax_refresh_at — so_tax_refresh 의 몸 그대로 + p_status(draft · packed) ═══
--   원본과 다른 줄: 서명의 p_status · 상태 목록 검사 한 줄 · 상태 거부(draft 문장은 원본 그대로 · packed 문장 더함) · update 의 status = p_status
create or replace function public.so_tax_refresh_at(p_so_id uuid, p_staff uuid, p_prev_country text, p_prev_state text, p_clear_manual boolean, p_status text)
returns jsonb language plpgsql set search_path = public, pg_temp as $$
declare
  v_so       public.so%rowtype;
  g_new      record;
  g_old      record;
  v_pick     jsonb;
  v_new_id   uuid;
  v_new_name text;
  v_warn     jsonb;
  v_reset    boolean := false;
  v_n        int;
begin
  if p_status is null or p_status not in ('draft', 'packed') then raise exception 'so_tax_refresh_at: status % is not draft or packed — nothing was saved', coalesce(p_status, '(null)'); end if;
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found — nothing was saved';
  end if;
  if v_so.status <> p_status then
    if p_status = 'draft' then raise exception 'This order is not a draft (status %) — its tax rule is fixed — nothing was saved', v_so.status; end if;
    raise exception 'Order % is % — its tax rule follows the ship-to only while the order is Finalized — nothing was saved', v_so.so_number, v_so.status;
  end if;

  -- 사람이 정한 규칙(판정 7): 배송지의 나라·주가 같으면 그대로(거리·도시·우편번호만 바뀐 것) · 바뀌었으면 배송지 규칙으로 되돌리고 경고
  if v_so.tax_rule_manual and not p_clear_manual then
    select * into g_new from public.ims_region_from_address(v_so.ship_to_country, v_so.ship_to_state_province);
    select * into g_old from public.ims_region_from_address(p_prev_country, p_prev_state);
    if g_new.country_code is not distinct from g_old.country_code and g_new.region_code is not distinct from g_old.region_code then
      return jsonb_build_object('so_id', p_so_id, 'rule_id', v_so.tax_rule_id, 'rule', v_so.tax_rule, 'manual', true, 'changed', false, 'previous', v_so.tax_rule,
                                'reset_by_ship_to', false, 'warnings', '[]'::jsonb);
    end if;
    v_reset := true;
  end if;

  v_pick     := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, public.ims_today(), 'sale');
  v_new_id   := (v_pick->>'rule_id')::uuid;
  v_new_name := v_pick->>'rule';
  v_warn     := coalesce(v_pick->'warnings', '[]'::jsonb);
  if v_reset then
    v_warn := v_warn || '["tax_rule_reset_by_ship_to"]'::jsonb;
  end if;

  if v_new_id is distinct from v_so.tax_rule_id or v_new_name is distinct from v_so.tax_rule or v_so.tax_rule_manual then
    update public.so set tax_rule_id = v_new_id, tax_rule = v_new_name, tax_rule_manual = false, updated_by = coalesce(p_staff, updated_by)
    where id = p_so_id and status = p_status;
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
    end if;
  end if;
  -- 줄·운임은 오더 규칙을 기록만(판정 8·9) — 다른 값이 남지 않게 전부 맞춘다
  update public.so_line   set tax_rule = v_new_name, updated_by = coalesce(p_staff, updated_by) where so_id = p_so_id and tax_rule is distinct from v_new_name;
  update public.so_charge set tax_rule = v_new_name, updated_by = coalesce(p_staff, updated_by) where so_id = p_so_id and tax_rule is distinct from v_new_name;

  return jsonb_build_object('so_id', p_so_id, 'rule_id', v_new_id, 'rule', v_new_name, 'rate_pct', v_pick->'rate_pct', 'manual', false,
                            'changed', v_new_id is distinct from v_so.tax_rule_id, 'previous', v_so.tax_rule, 'reset_by_ship_to', v_reset,
                            'region', v_pick->'region', 'warnings', v_warn);
end;
$$;
revoke all on function public.so_tax_refresh_at(uuid, uuid, text, text, boolean, text) from public, anon, authenticated;
grant execute on function public.so_tax_refresh_at(uuid, uuid, text, text, boolean, text) to service_role;
comment on function public.so_tax_refresh_at(uuid, uuid, text, text, boolean, text) is 'so-shipto-1: so_tax_refresh 의 몸(세금 ② · 판정 7 · 8 · 9) + p_status — draft(so_tax_refresh 껍데기 · so_header_update 길) · packed(so_ship_to_change 길 · 판정 1200) · 그 상태가 아니면 거부 · 속 함수(화면이 부르지 않는다 · authenticated 실행 불가)';

-- so_tax_refresh — 서명 · 기본값 · 권한 그대로(create or replace) · 몸은 속 함수를 draft 로 부르는 한 줄
create or replace function public.so_tax_refresh(p_so_id uuid, p_staff uuid, p_prev_country text default null, p_prev_state text default null, p_clear_manual boolean default false)
returns jsonb language plpgsql set search_path = public, pg_temp as $$
begin
  return public.so_tax_refresh_at(p_so_id, p_staff, p_prev_country, p_prev_state, p_clear_manual, 'draft');   -- so-shipto-1: 몸은 so_tax_refresh_at 으로 옮겼다 · draft 문 그대로
end;
$$;

-- ═══ 2) 기록 표 so_ship_to_log — 처음부터 닫는다 ═══
create table public.so_ship_to_log (
  id                  uuid primary key default gen_random_uuid(),
  change_id           uuid not null,                                   -- 한 호출 = 한 묶음(함께 바꾼 오더들이 같은 값)
  so_id               uuid not null references public.so(id),
  before              jsonb not null,                                  -- 옛 배송지 아홉 칸
  after               jsonb not null,                                  -- 새 배송지 아홉 칸
  tax_before          jsonb not null,                                  -- {rule_id, rule, rate_pct, manual} — 금액이 아니다(금액은 발행일 기준으로 발행 때 굳는다)
  tax_after           jsonb not null,
  shipments_cancelled uuid[] not null default '{}',                    -- 이 오더가 들어 있던 live 발송(cancel_reason ship_to_changed)
  siblings_cut        text[] not null default '{}',                    -- 배열 밖인데 같은 발송에 묶여 함께 끊긴 SO 번호
  address_saved_id    uuid,                                            -- 주소록에 더한 행(FK 없음 — 기록일 뿐)
  changed_by          uuid references public.ims_staff(id),
  changed_at          timestamptz not null default now()
);
create index so_ship_to_log_so_idx on public.so_ship_to_log (so_id);
create index so_ship_to_log_changed_by_idx on public.so_ship_to_log (changed_by);
alter table public.so_ship_to_log enable row level security;
revoke all on table public.so_ship_to_log from public, anon, authenticated, service_role;
comment on table public.so_ship_to_log is 'so-shipto-1 판정 1206: Finalized 오더의 배송지를 바꾼 기록(누가 · 언제 · 옛 → 새 · 세금 규칙 전후 · 끊은 발송 · 함께 끊긴 형제) — 닫힌 표(RLS on · 정책 0 · 권한 0) · 쓰기는 so_ship_to_change 만 · 읽기 창구 없음 · ⚠️ 컷오버 날 지우는 순서: so 보다 먼저 이 표를 지운다(so_id FK)';

-- ═══ 3) 창구 so_ship_to_change ═══
--   p_orders  = [{"so_id": …, "old": {아홉 칸 — 화면이 본 값}}] — 오더마다 자기 옛 값(동시 편집 대조) · 「함께」 는 주소 여섯 칸이 같은 오더만(fc_norm · fc_country — fc_shipment_prepare ③ 과 같은 기준)
--   p_address = 아홉 칸(ship_to_*) 또는 {"address_id": …, ship_to_company, ship_to_contact, ship_to_phone} — address_id 는 주소 여섯 칸만 서버가 채운다(주소록에 회사 · 연락처 · 전화가 없다)
--   막는 순서 [G1] 문 → [G2] 잠금(so id 순) · packed · 같은 배송 손님 · 창고 · 주소 → [G3] 옛 값 → 새 주소 꼴 [G7] → [G4] 예약(fc_shipment id 순으로 잠근 뒤) → [G4b] 나눠 가진 유닛 → [G5] aone 주 변경 → [G6] 같은 값 changed false → [G8] 세금 규칙 없음
create or replace function public.so_ship_to_change(p_orders jsonb, p_address jsonb, p_save_to_book boolean default false, p_conditions jsonb default null)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c_keys  constant text[] := array['ship_to_company', 'ship_to_contact', 'ship_to_phone', 'ship_to_line1', 'ship_to_line2', 'ship_to_city', 'ship_to_state_province', 'ship_to_postal_code', 'ship_to_country'];
  c_six   constant text[] := array['ship_to_line1', 'ship_to_line2', 'ship_to_city', 'ship_to_state_province', 'ship_to_postal_code', 'ship_to_country'];
  v_staff uuid;
  v_e     jsonb;
  v_olds  jsonb := '{}'::jsonb;        -- so_id → 화면이 본 옛 값
  v_befo  jsonb := '{}'::jsonb;        -- so_id → 지금 값(아홉 칸)
  v_ids   uuid[];
  v_id    uuid;
  v_k     text;
  v_so    public.so%rowtype;
  v_first public.so%rowtype;
  v_cid   uuid;                         -- 배송 손님 = default_ship_to_customer_id → 없으면 오더 손님(so_copy_customer · fc_shipment_prepare ⑥ 과 같은 규칙)
  v_cid1  uuid;
  v_cur   jsonb;
  v_new   jsonb;
  v_aid   uuid;
  v_addr  public.customer_address%rowtype;
  v_bad   text;
  v_bad2  text;
  v_same  boolean := true;
  v_ships uuid[];
  v_my    uuid[];
  v_sibs  text[];
  v_rev   boolean;
  g_old   record;
  g_new   record;
  v_pick  jsonb;
  v_moved boolean;
  v_tax   jsonb;
  v_tb    jsonb;
  v_ta    jsonb;
  v_tmsg  text[] := '{}';
  v_reset text[] := '{}';
  v_out   jsonb := '[]'::jsonb;
  v_warn  jsonb := '[]'::jsonb;
  v_chg   uuid := gen_random_uuid();
  v_saved uuid;
  v_n     int;
begin
  perform public.ims_require_write('sales');                                                                                             -- [G1] 1203
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  -- ① 꼴
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' or jsonb_array_length(p_orders) = 0 then raise exception 'Choose at least one order — nothing was saved'; end if;
  if jsonb_array_length(p_orders) > 50 then raise exception 'Too many orders in one change (% — the limit is 50) — nothing was saved', jsonb_array_length(p_orders); end if;
  if p_address is null or jsonb_typeof(p_address) <> 'object' then raise exception 'p_address must be a JSON object — nothing was saved'; end if;
  if p_conditions is not null and jsonb_typeof(p_conditions) not in ('object', 'null') then raise exception 'p_conditions must be a JSON object — nothing was saved'; end if;
  for v_e in select x from jsonb_array_elements(p_orders) x loop
    if jsonb_typeof(v_e) <> 'object' or nullif(btrim(v_e->>'so_id'), '') is null or jsonb_typeof(v_e->'old') is distinct from 'object' then
      raise exception 'Each order needs so_id and old (the ship-to the screen saw) — nothing was saved';
    end if;
    v_id := (v_e->>'so_id')::uuid;
    if v_olds ? v_id::text then raise exception 'Order % is listed twice — nothing was saved', v_id; end if;
    v_olds := v_olds || jsonb_build_object(v_id::text, v_e->'old');
  end loop;
  select array_agg(k::uuid order by k::uuid) into v_ids from jsonb_object_keys(v_olds) k;
  -- ② 잠금(id 순) · 상태 · 같은 배송 손님 · 창고 · 주소 여섯 칸 · ③ 옛 값
  perform 1 from public.so s where s.id = any (v_ids) order by s.id for update;
  foreach v_id in array v_ids loop
    select * into v_so from public.so s where s.id = v_id;
    if not found then raise exception 'Order % not found — nothing was saved', v_id; end if;
    if v_so.status <> 'packed' then raise exception '%', case v_so.status when 'draft' then format('Order %s is a draft — change the ship-to on the order itself — nothing was saved', v_so.so_number) when 'shipped' then format('Order %s has already shipped — the ship-to can no longer be changed — nothing was saved', v_so.so_number) when 'fulfilled' then format('Order %s has already been shipped and invoiced — the ship-to can no longer be changed — nothing was saved', v_so.so_number) when 'cancelled' then format('Order %s is cancelled — the ship-to can no longer be changed — nothing was saved', v_so.so_number) else format('Order %s is %s — the ship-to can be changed here only once the warehouse has finalized the order — nothing was saved', v_so.so_number, v_so.status) end; end if;   -- [G2] 1206
    select coalesce(c.default_ship_to_customer_id, c.id) into v_cid from public.customer c where c.id = v_so.customer_id;
    if v_first.id is null then
      v_first := v_so;  v_cid1 := v_cid;
    else
      if v_cid is distinct from v_cid1 then raise exception 'Order % ships to a different customer than % — change them separately — nothing was saved', v_so.so_number, v_first.so_number; end if;   -- [G2c]
      if v_so.location_id is distinct from v_first.location_id then raise exception 'Order % ships from a different warehouse than % — change them separately — nothing was saved', v_so.so_number, v_first.so_number; end if;   -- [G2w]
      if (public.fc_norm(v_so.ship_to_line1), public.fc_norm(v_so.ship_to_line2), public.fc_norm(v_so.ship_to_city), public.fc_norm(v_so.ship_to_state_province), public.fc_norm(v_so.ship_to_postal_code), public.fc_country(v_so.ship_to_country)) is distinct from (public.fc_norm(v_first.ship_to_line1), public.fc_norm(v_first.ship_to_line2), public.fc_norm(v_first.ship_to_city), public.fc_norm(v_first.ship_to_state_province), public.fc_norm(v_first.ship_to_postal_code), public.fc_country(v_first.ship_to_country)) then raise exception 'Order % has a different ship-to address than % — change them separately — nothing was saved', v_so.so_number, v_first.so_number; end if;   -- [G2a]
    end if;
    select jsonb_object_agg(k, to_jsonb(v_so)->k) into v_cur from unnest(c_keys) k;
    if exists (select 1 from unnest(c_keys) k where nullif(btrim(v_cur->>k), '') is distinct from nullif(btrim(v_olds->(v_id::text)->>k), '')) then raise exception 'Someone changed the ship-to address on order % just now — reload the order and try again — nothing was saved', v_so.so_number; end if;   -- [G3]
    v_befo := v_befo || jsonb_build_object(v_id::text, v_cur);
  end loop;
  -- ④ 새 값 — 회사 · 연락처 · 전화는 늘 p_address 에 · 주소 여섯 칸은 address_id(배송 손님의 활성 Shipping · Business) 또는 p_address
  foreach v_k in array c_keys[1:3] loop
    if not p_address ? v_k then raise exception 'p_address must carry ship_to_company, ship_to_contact and ship_to_phone (blank is allowed) — nothing was saved'; end if;
  end loop;
  v_aid := nullif(btrim(p_address->>'address_id'), '')::uuid;
  if v_aid is not null then
    if p_address ?| c_six then raise exception 'Send either address_id or the address fields, not both — nothing was saved'; end if;
    select * into v_addr from public.customer_address a where a.id = v_aid and a.customer_id = v_cid1 and a.is_active and a.type in ('Shipping', 'Business');
    if not found then raise exception 'That address is not an active shipping address of this customer — nothing was saved'; end if;
    v_new := jsonb_build_object('ship_to_company', p_address->>'ship_to_company', 'ship_to_contact', p_address->>'ship_to_contact', 'ship_to_phone', p_address->>'ship_to_phone',
                                'ship_to_line1', v_addr.line1, 'ship_to_line2', v_addr.line2, 'ship_to_city', v_addr.city, 'ship_to_state_province', v_addr.state_province, 'ship_to_postal_code', v_addr.postal_code, 'ship_to_country', v_addr.country);
  else
    v_new := p_address;
  end if;
  select jsonb_object_agg(k, nullif(btrim(v_new->>k), '')) into v_new from unnest(c_keys) k;                                           -- 저장 꼴 = btrim · 빈 글 → null(so_header_update 와 같다)
  if (v_new->>'ship_to_line1') is null or (v_new->>'ship_to_city') is null or (v_new->>'ship_to_state_province') is null or (v_new->>'ship_to_postal_code') is null then raise exception 'The new ship-to needs a street, city, province and postal code — nothing was saved'; end if;   -- [G7]
  select string_agg(k, ', ') into v_bad from unnest(c_keys) k where length(v_new->>k) > 200;
  if v_bad is not null then raise exception 'These ship-to fields are longer than 200 characters: % — nothing was saved', v_bad; end if;
  perform public.fc_country(v_new->>'ship_to_country');                                                                                -- 두 글자 나라 코드가 아니면 여기서 멈춘다(견적이 어차피 거부한다)
  select not exists (select 1 from jsonb_each(v_befo) b, unnest(c_keys) k where nullif(btrim(b.value->>k), '') is distinct from (v_new->>k)) into v_same;
  -- ⑤ 예약(1201) — 이 SO 들이 든 live 발송을 id 순으로 잠근 뒤에 본다(fc_book_prepare 가 발송을 잠근 채 pending 을 만든다)
  select coalesce(array_agg(distinct l.shipment_id order by l.shipment_id), '{}') into v_ships from public.fc_shipment_so l where l.so_id = any (v_ids) and l.live;
  perform 1 from public.fc_shipment f where f.id = any (v_ships) order by f.id for update;
  select string_agg(x.t, ', ' order by x.t) into v_bad from (
    select distinct s.so_number || case when f.status = 'booked' or exists (select 1 from public.fc_booking b where b.shipment_id = f.id and b.status = 'booked') then ' (booked)' else ' (booking in progress)' end as t
      from public.fc_shipment f join public.fc_shipment_so l on l.shipment_id = f.id and l.live join public.so s on s.id = l.so_id
     where f.id = any (v_ships) and l.so_id = any (v_ids)
       and (f.status = 'booked' or exists (select 1 from public.fc_booking b where b.shipment_id = f.id and b.status in ('booked', 'pending')))) x;
  if v_bad is not null then raise exception 'Cancel the Freightcom booking first — % — nothing was saved', v_bad; end if;                -- [G4] 1201
  -- ⑥ 나눠 가진 유닛(1209) — 배열의 SO 유닛에 배열 밖 SO 물건이 들었거나 그 반대면 갈라 견적할 수 없다(fc_shipment_prepare ④)
  select string_agg(distinct s.so_number, ', ') into v_bad from public.wms_pallet_items i join public.so s on s.id = i.order_id
   where i.order_id is not null and not (i.order_id = any (v_ids))
     and i.pallet_id in (select u.id from public.wms_pallets u where (u.order_id = any (v_ids) and u.parent_id is null)
                            or u.parent_id in (select u2.id from public.wms_pallets u2 where u2.order_id = any (v_ids) and u2.parent_id is null));
  select string_agg(distinct s.so_number, ', ') into v_bad2 from public.wms_pallet_items i join public.wms_pallets u on u.id = i.pallet_id left join public.wms_pallets p on p.id = u.parent_id
    join public.so s on s.id = coalesce(p.order_id, u.order_id)
   where i.order_id = any (v_ids) and not (coalesce(p.order_id, u.order_id) = any (v_ids));
  if coalesce(v_bad, v_bad2) is not null then raise exception 'The boxes or pallets of these orders also hold goods of % — include those orders in the change — nothing was saved', concat_ws(', ', v_bad, v_bad2); end if;   -- [G4b] 1209
  -- ⑦ aone(1205) — 주 · 나라가 바뀌는(또는 새 주를 못 읽는) 변경은 Shopify 에서 결제 · 승인된 웹 오더(aone 스토어 · 갈린 형제 포함)에 거부
  select * into g_new from public.ims_region_from_address(v_new->>'ship_to_country', v_new->>'ship_to_state_province');
  foreach v_id in array v_ids loop
    select * into g_old from public.ims_region_from_address(v_befo->(v_id::text)->>'ship_to_country', v_befo->(v_id::text)->>'ship_to_state_province');
    if g_new.country_code is distinct from g_old.country_code or g_new.region_code is distinct from g_old.region_code or g_new.region_code is null then
      select string_agg(distinct c.order_name, ', ') into v_bad from public.so_chain_shop_orders(v_id) c where c.store_kind = 'aone';
      if v_bad is not null then raise exception 'Order % was paid in Shopify (%) — its ship-to cannot move to another province or country — nothing was saved', (select s.so_number from public.so s where s.id = v_id), v_bad; end if;   -- [G5] 1205
    end if;
  end loop;
  -- ⑧ 같은 값 — 쓰지 않는다
  if v_same then return jsonb_build_object('changed', false, 'orders', (select jsonb_agg(jsonb_build_object('so_id', s.id, 'so_number', s.so_number) order by s.so_number) from public.so s where s.id = any (v_ids)), 'ship_to', v_new, 'warnings', '[]'::jsonb); end if;   -- [G6]
  -- ⑨ 세금 규칙을 못 고르는 주소 거부 — 사람이 정한 규칙이고 주가 그대로인 오더는 그 규칙이 남으므로 지나간다(판정 7)
  v_pick := public.so_tax_rule_for(v_new->>'ship_to_country', v_new->>'ship_to_state_province', public.ims_today(), 'sale');
  foreach v_id in array v_ids loop
    select * into v_so from public.so s where s.id = v_id;
    select * into g_old from public.ims_region_from_address(v_so.ship_to_country, v_so.ship_to_state_province);
    v_moved := g_new.country_code is distinct from g_old.country_code or g_new.region_code is distinct from g_old.region_code;
    if (v_pick->>'rule_id') is null and not (v_so.tax_rule_manual and not v_moved) then raise exception 'No tax rule for the new ship-to (% · %) — check the province and country — nothing was saved', coalesce(v_new->>'ship_to_state_province', '(blank)'), coalesce(v_new->>'ship_to_country', '(blank)'); end if;   -- [G8]
  end loop;

  -- ═ 쓰기 ═
  -- ⓐ 아홉 칸
  update public.so s set ship_to_company = v_new->>'ship_to_company', ship_to_contact = v_new->>'ship_to_contact', ship_to_phone = v_new->>'ship_to_phone',
                         ship_to_line1 = v_new->>'ship_to_line1', ship_to_line2 = v_new->>'ship_to_line2', ship_to_city = v_new->>'ship_to_city',
                         ship_to_state_province = v_new->>'ship_to_state_province', ship_to_postal_code = v_new->>'ship_to_postal_code', ship_to_country = v_new->>'ship_to_country'
   where s.id = any (v_ids) and s.status = 'packed';
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_ids) then raise exception 'The orders were not saved — one of them may have been changed by someone else just now — nothing was saved'; end if;
  -- ⓑ 끊기 전에 읽어 둔다: 배열 밖 형제 · 안 닫힌 「주소 기억 필요」
  select coalesce(array_agg(distinct s.so_number order by s.so_number), '{}') into v_sibs
    from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = any (v_ships) and l.live and not (l.so_id = any (v_ids));
  select exists (select 1 from public.fc_shipment f where f.id = any (v_ships) and f.address_review is not null and f.address_review_closed_at is null) into v_rev;
  -- ⓒ 주소록(1204 · 1207) — 새로 적은 주소만 · 추가만(기본 무변) · 같은 주소(fc_norm line1 + postal · 견적이 주소를 찾는 기준)가 이미 있으면 넣지 않는다
  if coalesce(p_save_to_book, false) and v_aid is null then
    select count(*) into v_n from public.customer_address a where a.customer_id = v_cid1 and a.is_active and a.type in ('Shipping', 'Business')
       and public.fc_norm(a.line1) = public.fc_norm(v_new->>'ship_to_line1') and public.fc_norm(a.postal_code) = public.fc_norm(v_new->>'ship_to_postal_code');
    if v_n > 0 then
      v_warn := v_warn || jsonb_build_object('code', 'address_exists', 'message', 'This address is already in the customer''s address book — it was not added again.');
    else
      insert into public.customer_address (customer_id, source, updated_by, type, is_default_for_type, line1, line2, city, state_province, postal_code, country, residential, tailgate_required, threshold_delivery)
      values (v_cid1, 'manual', v_staff, 'Shipping', false, v_new->>'ship_to_line1', v_new->>'ship_to_line2', v_new->>'ship_to_city', v_new->>'ship_to_state_province', v_new->>'ship_to_postal_code', v_new->>'ship_to_country',
              nullif(btrim(p_conditions->>'residential'), '')::boolean, coalesce(nullif(btrim(p_conditions->>'tailgate_required'), '')::boolean, false), coalesce(nullif(btrim(p_conditions->>'threshold_delivery'), '')::boolean, false))
      returning id into v_saved;
    end if;
  end if;
  -- ⓓ 오더마다: 세금(속 함수 · packed) · 기록
  foreach v_id in array v_ids loop
    select * into v_so from public.so s where s.id = v_id;
    v_tb := jsonb_build_object('rule_id', v_so.tax_rule_id, 'rule', v_so.tax_rule, 'rate_pct', (select r.rate_pct from public.ref_tax_rule r where r.id = v_so.tax_rule_id), 'manual', v_so.tax_rule_manual);
    v_tax := public.so_tax_refresh_at(v_id, v_staff, v_befo->(v_id::text)->>'ship_to_country', v_befo->(v_id::text)->>'ship_to_state_province', false, 'packed');
    select jsonb_build_object('rule_id', s.tax_rule_id, 'rule', s.tax_rule, 'rate_pct', (select r.rate_pct from public.ref_tax_rule r where r.id = s.tax_rule_id), 'manual', s.tax_rule_manual) into v_ta from public.so s where s.id = v_id;
    select coalesce(array_agg(l.shipment_id order by l.shipment_id), '{}') into v_my from public.fc_shipment_so l where l.so_id = v_id and l.live;
    if (v_ta->>'rule_id') is distinct from (v_tb->>'rule_id') then
      v_tmsg := array_append(v_tmsg, format('%s: %s → %s', v_so.so_number, coalesce((v_tb->>'rule') || ' ' || trim_scale((v_tb->>'rate_pct')::numeric)::text || '%', 'no rule'), coalesce((v_ta->>'rule') || ' ' || trim_scale((v_ta->>'rate_pct')::numeric)::text || '%', 'no rule')));
    end if;
    if coalesce((v_tax->>'reset_by_ship_to')::boolean, false) then v_reset := array_append(v_reset, v_so.so_number); end if;
    insert into public.so_ship_to_log (change_id, so_id, before, after, tax_before, tax_after, shipments_cancelled, siblings_cut, address_saved_id, changed_by)
    values (v_chg, v_id, v_befo->(v_id::text), v_new, v_tb, v_ta, v_my, v_sibs, v_saved, v_staff);
    v_out := v_out || jsonb_build_object('so_id', v_id, 'so_number', v_so.so_number, 'tax_before', v_tb, 'tax_after', v_ta, 'tax_changed', (v_ta->>'rule_id') is distinct from (v_tb->>'rule_id'), 'shipments_cancelled', to_jsonb(v_my));
  end loop;
  -- ⓔ 발송 끊기(1201) — live 전부(draft · quoted · selected — booked 는 위에서 거부) · 트리거 fc_shipment_live_sync 가 live 를 끈다 → 다시 견적
  update public.fc_shipment f set status = 'cancelled', cancelled_at = now(), cancel_reason = 'ship_to_changed', updated_by = v_staff where f.id = any (v_ships) and f.status <> 'cancelled';
  -- ⓕ 경고
  if cardinality(v_tmsg) > 0 then
    v_warn := v_warn || jsonb_build_object('code', 'tax_changed', 'message', format('The tax rule changed with the new ship-to (%s) — the order totals follow the new rule. If a Ship Ready was already sent, send it again.', array_to_string(v_tmsg, ' · ')));   -- 1210
  end if;
  if cardinality(v_reset) > 0 then
    v_warn := v_warn || jsonb_build_object('code', 'tax_rule_reset_by_ship_to', 'message', format('The tax rule set by hand on %s was reset because the ship-to province changed.', array_to_string(v_reset, ', ')));
  end if;
  if cardinality(v_sibs) > 0 then
    v_warn := v_warn || jsonb_build_object('code', 'shipment_siblings_cut', 'so_numbers', to_jsonb(v_sibs), 'message', format('The freight quote was shared with %s — it was dropped for them too. Quote them again from their own Ship & invoice window.', array_to_string(v_sibs, ', ')));   -- 1209
  end if;
  if v_rev then
    v_warn := v_warn || jsonb_build_object('code', 'address_review_dropped', 'message', 'A pending "remember this address" request on the old freight quote was dropped with it.');
  end if;
  return jsonb_build_object('changed', true, 'change_id', v_chg, 'orders', v_out, 'ship_to', v_new, 'shipments_cancelled', to_jsonb(v_ships), 'siblings_cut', to_jsonb(v_sibs),
                            'address_saved', case when v_saved is null then null else jsonb_build_object('address_id', v_saved, 'customer_id', v_cid1) end, 'warnings', v_warn);
end;
$$;
revoke all on function public.so_ship_to_change(jsonb, jsonb, boolean, jsonb) from public, anon, service_role;
grant execute on function public.so_ship_to_change(jsonb, jsonb, boolean, jsonb) to authenticated;
comment on function public.so_ship_to_change(jsonb, jsonb, boolean, jsonb) is 'so-shipto-1 판정 1200 ~ 1210: Finalized(packed) 오더의 배송지 바꾸기(sales 쓰기) — p_orders [{so_id, old{아홉 칸}}] · p_address 아홉 칸 또는 {address_id + 회사 · 연락처 · 전화} · 거부: packed 아님 · 옛 값 어긋남 · 살아 있는 예약(Cancel the Freightcom booking first) · 유닛을 나눠 가진 배열 밖 오더 · aone 의 주 · 나라 변경 · 빈 주소 · 세금 규칙 없음 · 같은 값이면 changed false · 쓰기: so 아홉 칸 → 세금(so_tax_refresh_at packed · 판정 7) → live 발송 cancelled(ship_to_changed) → 주소록 추가만(p_save_to_book · 기본 무변) → so_ship_to_log · 경고 tax_changed · tax_rule_reset_by_ship_to · shipment_siblings_cut · address_review_dropped · address_exists · Shopify 오더 주소 무접촉';
