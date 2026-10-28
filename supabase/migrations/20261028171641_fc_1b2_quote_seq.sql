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
-- fc-1b2 — 견적 「최신」 열쇠 fc_quote.seq (2026-10-28 · fc-1b 확인 실행 B17 MISMATCH 의 원인 · 지시서 Caleb 회신)
--   원인(원문): fc_shipment_for_so 「select * into v_q … order by q.requested_at desc, q.id desc limit 1」 · fc_quote.requested_at 기본값 now() · id 기본값 gen_random_uuid()
--        → 한 트랜잭션 안의 견적 셋(fc_1a_check 10d · 12f · fc_1b_check B16)은 requested_at 이 전부 같고 동점은 난수 id 로 갈린다 — 시험 갈래에서 우연히 pending 이 뽑혔고 확인 갈래에서 done 이 뽑혔다(got=done/5)
--        같은 꼴 둘 더: fc_quote_select 의 「마지막 done 견적」(requested_at desc, id desc) · fc_quote_save 의 pending 줄 찾기(requested_at desc) — 운영에서도 같은 초(ms) 안에 두 견적이 서면 갈린다
--   고침: fc_quote.seq bigint identity(넣은 순서 · 트랜잭션과 무관하게 증가) + 색인 (shipment_id, seq desc) · 셋 다 order by q.seq desc · requested_at 은 그대로(표시용)
--   재발행 셋 = 바이트 복사 + 정렬 한 줄씩(fc_shipment_for_so · fc_quote_save 20261028170402 · fc_quote_select 20261028162209) · 시그니처 · 권한 · comment 그대로(create or replace)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261028171641_fc_1b2_quote_seq.sql && supabase migration repair --status applied 20261028171641 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261028171641_fc_1b2_quote_seq.sql -f supabase/tests/fc_1b2_check.sql  (안에서 fc_1b_check 의 99 — 그 안의 fc_1a 76 포함 — 를 함께 돌린다)

-- ═══ 1) 칸 · 색인 ═══
alter table public.fc_quote add column seq bigint generated always as identity;
comment on column public.fc_quote.seq is 'fc-1b2: 넣은 순서(identity) — 「최신 견적」 · 「마지막 done 견적」 · pending 줄 찾기의 정렬 열쇠(requested_at 은 한 트랜잭션 안에서 같다 · id 는 난수)';
create index fc_quote_shipment_seq_idx on public.fc_quote (shipment_id, seq desc);
revoke all on sequence public.fc_quote_seq_seq from public, anon, authenticated, service_role;      -- 쓰기는 definer 창구(fc_quote_pending · fc_quote_save)만 · REST 직접 insert 는 닫혀 있다(fc-1a)

-- ═══ 2) 재발행 셋 ═══
create or replace function public.fc_shipment_for_so(p_so_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_f     public.fc_shipment%rowtype;
  v_q     public.fc_quote%rowtype;
  v_so    public.so%rowtype;
  v_units jsonb;
  v_rates jsonb;
  v_sel   public.fc_quote_rate%rowtype;
  v_sos   jsonb;
  v_now   jsonb;
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if not found then raise exception 'Order % not found', p_so_id; end if;
  select f.* into v_f from public.fc_shipment_so l join public.fc_shipment f on f.id = l.shipment_id where l.so_id = p_so_id and l.live;
  v_now := public.fc_units_snapshot(array[p_so_id]);
  if v_f.id is null then
    return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number, 'shipment', null,
                              'units_now', v_now, 'units_without_dims', (select count(*) from jsonb_array_elements(v_now) e where e->>'length_in' is null or e->>'width_in' is null or e->>'height_in' is null or e->>'weight_lb' is null),
                              'markup_pct', (select c.value::numeric from public.inv_config c where c.key = 'fc_markup_pct'));
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('so_id', s.id, 'so_number', s.so_number, 'status', s.status, 'is_charge_so', s.id = v_f.charge_so_id) order by s.created_at, s.so_number), '[]'::jsonb)
    into v_sos from public.fc_shipment_so l join public.so s on s.id = l.so_id where l.shipment_id = v_f.id and l.live;
  select * into v_q from public.fc_quote q where q.shipment_id = v_f.id order by q.seq desc limit 1;                                 -- fc-1b2: 「최신」 = seq(한 트랜잭션 안 now() 동점 · id 난수 → 갈렸다)
  if v_q.id is not null and v_q.status = 'done' then
    select coalesce(jsonb_agg(jsonb_build_object('rate_id', r.id, 'service_id', r.service_id, 'carrier_name', r.carrier_name, 'service_name', r.service_name, 'carrier_id', r.carrier_id,
                                                 'base_cents', r.base_cents, 'surcharge_cents', r.surcharge_cents, 'tax_cents', r.tax_cents, 'total_cents', r.total_cents, 'pretax_cents', r.pretax_cents,
                                                 'customer_charge_cents', r.customer_charge_cents, 'transit_days', r.transit_days, 'valid_until', r.valid_until,
                                                 'avoided', r.avoided, 'preselected', r.preselected, 'selectable', (not r.avoided and r.carrier_id is not null), 'totals_mismatch', r.totals_mismatch,
                                                 'selected', r.id = v_f.selected_rate_id)
                              order by r.avoided, (r.carrier_id is null), r.pretax_cents, r.service_id), '[]'::jsonb)
      into v_rates from public.fc_quote_rate r where r.quote_id = v_q.id;
  end if;
  if v_f.selected_rate_id is not null then select * into v_sel from public.fc_quote_rate r where r.id = v_f.selected_rate_id; end if;
  select public.fc_units_snapshot(array(select l.so_id from public.fc_shipment_so l where l.shipment_id = v_f.id and l.live)) into v_units;
  return jsonb_build_object('so_id', p_so_id, 'so_number', v_so.so_number,
    'shipment', jsonb_build_object('id', v_f.id, 'status', v_f.status, 'packaging_type', v_f.packaging_type, 'origin_warehouse_id', v_f.origin_warehouse_id,
                                   'charge_so_id', v_f.charge_so_id, 'customer_id', v_f.customer_id, 'address_id', v_f.address_id,
                                   'freight_locked', v_f.freight_locked, 'freight_locked_reason', v_f.freight_locked_reason,
                                   'address_review', v_f.address_review, 'address_review_closed_at', v_f.address_review_closed_at, 'address_review_action', v_f.address_review_action,   -- fc-1b 845
                                   'origin', v_f.origin, 'destination', v_f.destination, 'options', v_f.options, 'units', v_f.units, 'request', v_f.request, 'payload_hash', v_f.payload_hash,
                                   'created_in', v_f.created_in, 'created_by', v_f.created_by, 'created_at', v_f.created_at, 'updated_at', v_f.updated_at),
    'orders', v_sos,
    'quote', case when v_q.id is null then null else jsonb_build_object('id', v_q.id, 'status', v_q.status, 'request_id', v_q.request_id, 'error', v_q.error, 'requested_at', v_q.requested_at, 'done_at', v_q.done_at, 'rates', coalesce(v_rates, '[]'::jsonb)) end,
    'selected', case when v_sel.id is null then null else jsonb_build_object('rate_id', v_sel.id, 'carrier_id', v_sel.carrier_id, 'carrier_name', v_sel.carrier_name, 'service_id', v_sel.service_id, 'service_name', v_sel.service_name,
                                                                        'customer_charge_cents', v_sel.customer_charge_cents, 'pretax_cents', v_sel.pretax_cents) end,
    'charge_amount', case when v_sel.id is null or v_f.freight_locked then null else round(v_sel.customer_charge_cents / 100.0, 2) end,
    'units_now', v_units, 'units_changed', (v_units <> v_f.units),
    'units_without_dims', (select count(*) from jsonb_array_elements(v_units) e where e->>'length_in' is null or e->>'width_in' is null or e->>'height_in' is null or e->>'weight_lb' is null),
    'markup_pct', (select c.value::numeric from public.inv_config c where c.key = 'fc_markup_pct'));
end;
$$;

create or replace function public.fc_quote_save(p_shipment_id uuid, p_request_id text, p_response jsonb, p_error text default null, p_request jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_f      public.fc_shipment%rowtype;
  v_staff  uuid;
  v_role   text := coalesce(current_setting('request.jwt.claims', true)::jsonb->>'role', '');
  v_qid    uuid;
  v_pct    numeric;
  v_defc   uuid;
  v_use_def boolean;
  v_n      int := 0;
  v_pre_id uuid;
  v_r      record;
  v_base   bigint;  v_sur bigint;  v_tax bigint;  v_total bigint;  v_pre bigint;
  v_cid    uuid;
  v_vu     date;
  v_pend   uuid;                                                                      -- fc-1b: 이 request_id 의 pending 줄(fc_quote_pending 이 넣음)
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  if v_role <> 'service_role' then perform public.fc_gate(v_f.origin_warehouse_id, 'saved'); end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_f.status in ('booked', 'cancelled') then raise exception 'Shipment is % — no new quotes — nothing was saved', v_f.status; end if;
  if p_request_id is not null then select q.id into v_pend from public.fc_quote q where q.shipment_id = p_shipment_id and q.request_id = p_request_id and q.status = 'pending' order by q.seq desc limit 1; end if;   -- fc-1b2: seq
  if p_error is not null then
    if v_pend is not null then
      update public.fc_quote q set status = 'error', error = left(p_error, 1000), done_at = now(), request = coalesce(p_request, q.request), by_staff = coalesce(v_staff, q.by_staff) where q.id = v_pend returning q.id into v_qid;
    else
      insert into public.fc_quote (shipment_id, request_id, status, request, error, done_at, by_staff) values (p_shipment_id, p_request_id, 'error', coalesce(p_request, v_f.request), left(p_error, 1000), now(), v_staff) returning id into v_qid;
    end if;
    return jsonb_build_object('quote_id', v_qid, 'status', 'error', 'rates', 0);
  end if;
  if p_response is null or jsonb_typeof(coalesce(p_response->'rates', 'null'::jsonb)) <> 'array' then raise exception 'The quote response has no rates[] — nothing was saved'; end if;
  v_pct := coalesce((select c.value::numeric from public.inv_config c where c.key = 'fc_markup_pct'), 0);
  select c.default_carrier_id into v_defc from public.customer c where c.id = v_f.customer_id;
  if v_pend is not null then
    update public.fc_quote q set status = 'done', response = p_response, done_at = now(), request = coalesce(p_request, q.request), by_staff = coalesce(v_staff, q.by_staff) where q.id = v_pend returning q.id into v_qid;
  else
    insert into public.fc_quote (shipment_id, request_id, status, request, response, done_at, by_staff) values (p_shipment_id, p_request_id, 'done', coalesce(p_request, v_f.request), p_response, now(), v_staff) returning id into v_qid;   -- fc-1b: request = EF 가 실제 보낸 몸(freight_class · services 포함) · 없으면 발송의 payload
  end if;
  for v_r in select t.rate, t.ord from jsonb_array_elements(p_response->'rates') with ordinality as t(rate, ord) loop
    if nullif(btrim(v_r.rate->>'service_id'), '') is null then continue; end if;
    v_base  := public.fc_money_cents(v_r.rate->'base');
    v_sur   := coalesce((select sum(public.fc_money_cents(s->'amount')) from jsonb_array_elements(coalesce(nullif(v_r.rate->'surcharges', 'null'::jsonb), '[]'::jsonb)) s), 0);
    v_tax   := coalesce((select sum(public.fc_money_cents(s->'amount')) from jsonb_array_elements(coalesce(nullif(v_r.rate->'taxes', 'null'::jsonb), '[]'::jsonb)) s), 0);
    v_total := public.fc_money_cents(v_r.rate->'total');
    v_pre   := coalesce(v_base, 0) + v_sur;
    select c.id into v_cid from public.ref_carrier c where c.freightcom_carrier is not null and lower(btrim(c.freightcom_carrier)) = lower(btrim(coalesce(v_r.rate->>'carrier_name', ''))) limit 1;
    v_vu := case when jsonb_typeof(v_r.rate->'valid_until') = 'object' and (v_r.rate->'valid_until'->>'year') ~ '^[0-9]+$'
                 then make_date((v_r.rate->'valid_until'->>'year')::int, (v_r.rate->'valid_until'->>'month')::int, (v_r.rate->'valid_until'->>'day')::int) end;
    insert into public.fc_quote_rate (quote_id, service_id, carrier_name, service_name, carrier_id, base_cents, surcharge_cents, tax_cents, total_cents, pretax_cents, markup_pct, customer_charge_cents, transit_days, valid_until, avoided, totals_mismatch, raw)
    values (v_qid, btrim(v_r.rate->>'service_id'), nullif(btrim(v_r.rate->>'carrier_name'), ''), nullif(btrim(v_r.rate->>'service_name'), ''), v_cid, v_base, v_sur, v_tax, v_total, v_pre, v_pct,
            round(v_pre * (1 + v_pct / 100))::bigint,                                                                     -- 836: 세전 × (1 + 마크업) · 센트 반올림
            case when (v_r.rate->>'transit_time_days') ~ '^[0-9]+$' then (v_r.rate->>'transit_time_days')::int end, v_vu,
            v_cid is not null and exists (select 1 from public.customer_carrier_avoid a where a.customer_id = v_f.customer_id and a.carrier_id = v_cid),   -- 843
            v_total is not null and v_total <> v_pre + v_tax, v_r.rate);
    v_n := v_n + 1;
  end loop;
  -- 843 미리 고르기 — 피할 것 · 짝 없는 것 제외 · 손님 기본 운송사에 줄이 있으면 그 가운데 최저 · 없으면 전체 최저
  v_use_def := v_defc is not null and exists (select 1 from public.fc_quote_rate q where q.quote_id = v_qid and not q.avoided and q.carrier_id = v_defc);
  select q.id into v_pre_id from public.fc_quote_rate q where q.quote_id = v_qid and not q.avoided and q.carrier_id is not null and (not v_use_def or q.carrier_id = v_defc)
   order by q.pretax_cents, q.service_id limit 1;
  if v_pre_id is not null then update public.fc_quote_rate set preselected = true where id = v_pre_id; end if;
  update public.fc_shipment f set status = 'quoted', selected_rate_id = null, updated_by = coalesce(v_staff, f.updated_by) where f.id = p_shipment_id;
  return jsonb_build_object('quote_id', v_qid, 'status', 'done', 'rates', v_n, 'preselected_rate_id', v_pre_id, 'freight_locked', v_f.freight_locked, 'markup_pct', v_pct);
end;
$$;

create or replace function public.fc_quote_select(p_shipment_id uuid, p_rate_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_f   public.fc_shipment%rowtype;
  v_r   public.fc_quote_rate%rowtype;
  v_qid uuid;
  v_staff uuid;
begin
  select * into v_f from public.fc_shipment f where f.id = p_shipment_id for update;
  if not found then raise exception 'Shipment % not found — nothing was saved', p_shipment_id; end if;
  perform public.fc_gate(v_f.origin_warehouse_id, 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_f.status not in ('quoted', 'selected') then raise exception 'Shipment is % — get a quote first — nothing was saved', v_f.status; end if;
  select q.id into v_qid from public.fc_quote q where q.shipment_id = p_shipment_id and q.status = 'done' order by q.seq desc limit 1;   -- fc-1b2: 마지막 done 견적 = seq
  select * into v_r from public.fc_quote_rate r where r.id = p_rate_id and r.quote_id = v_qid;
  if not found then raise exception 'That rate is not on the latest quote of this shipment — quote again — nothing was saved'; end if;
  if v_r.avoided then raise exception 'This customer avoids % — pick another rate — nothing was saved', v_r.carrier_name; end if;
  if v_r.carrier_id is null then raise exception 'Carrier "%" is not on the IMS carrier list — add it in Settings (Freightcom name) before choosing it — nothing was saved', v_r.carrier_name; end if;
  update public.fc_shipment f set status = 'selected', selected_rate_id = v_r.id, updated_by = v_staff where f.id = p_shipment_id;
  return jsonb_build_object('shipment_id', p_shipment_id, 'selected_rate_id', v_r.id, 'carrier_id', v_r.carrier_id, 'service_id', v_r.service_id,
                            'customer_charge_cents', v_r.customer_charge_cents, 'charge_amount', case when v_f.freight_locked then null else round(v_r.customer_charge_cents / 100.0, 2) end,
                            'freight_locked', v_f.freight_locked, 'charge_so_id', v_f.charge_so_id);
end;
$$;

-- ═══ 3) 착지 검사 ═══
do $$
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'fc_quote' and column_name = 'seq' and is_identity = 'YES') <> 1 then raise exception 'fc-1b2 landing check failed: fc_quote.seq identity'; end if;
  if to_regclass('public.fc_quote_shipment_seq_idx') is null then raise exception 'fc-1b2 landing check failed: index'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_shipment_for_so') <> 'da58d09aa302303fc95b85ee66899068' then raise exception 'fc-1b2 landing check failed: fc_shipment_for_so md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_save') <> '40c9fa6e7e2b425bfb13e9eb96de903a' then raise exception 'fc-1b2 landing check failed: fc_quote_save md5'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'fc_quote_select') <> 'ca317868f2ecb6d2647439e9e370469e' then raise exception 'fc-1b2 landing check failed: fc_quote_select md5'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_shipment_for_so', 'fc_quote_save', 'fc_quote_select')) <> 3 then raise exception 'fc-1b2 landing check failed: function count'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('fc_shipment_for_so', 'fc_quote_save', 'fc_quote_select') and prosrc like '%requested_at desc%') <> 0 then raise exception 'fc-1b2 landing check failed: requested_at ordering still present'; end if;
  if not has_function_privilege('authenticated', 'public.fc_quote_select(uuid, uuid)', 'execute') or has_function_privilege('service_role', 'public.fc_quote_select(uuid, uuid)', 'execute')
     or not has_function_privilege('service_role', 'public.fc_quote_save(uuid, text, jsonb, text, jsonb)', 'execute') or not has_function_privilege('authenticated', 'public.fc_shipment_for_so(uuid)', 'execute') then
    raise exception 'fc-1b2 landing check failed: function acl changed';
  end if;
  raise notice 'fc-1b2 landing OK — fc_quote.seq · index · reissued 3 (order by seq)';
end $$;
