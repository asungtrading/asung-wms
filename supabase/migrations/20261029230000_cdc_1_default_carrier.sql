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
-- cdc-1 — 손님 기본 운송사를 고치는 창구 customer_default_carrier_set + customer_export 재발행(운송사 칸 = id 의 표 이름) (2026-10-29 · 판정 876 · 동료 피드백 4 「default carrier 칸을 선택하거나 넣을 수가 없어」 · 조사 fb-1029-0)
--   무엇이 났나: customers.html cs v7 의 Default carrier 칸은 보기만 — customer_update(20261028162209:696)는 글자 default_carrier 만 받고(:710 · :817 · :1050) default_carrier_id 는 ful-1a 일회성 이관(20261013170000:100) 뒤 아무 창구도 쓰지 않았다(글자 ↔ id 트리거 없음 · customer update 정책 with check (false) 20261005154716:47)
--   판정 876(Caleb 「그래도 가자」 · 2026-10-29): ① 고를 수 있는 종류 = ref_carrier.kind 셋 다 ② 문 = sales 쓰기(customer_carrier_avoid_set 과 같은 문) ③ 고르면 글자 default_carrier 도 표 이름으로 ④ 비우면(p_carrier_id null) id · 글자 둘 다 null
--     (글자를 남기면 so_copy_customer 가 옛 글자를 새 오더에 다시 싣고(20261013170000:218) 표에 없으면 Ship & invoice 가 막힌다) ⑤ customer_export 의 운송사 칸 = id 의 표 이름(id 가 없으면 지금처럼 글자)
--   판정 451(적재 때 표에 없는 글자는 id 만 비우고 글자 남김)은 적재 규칙으로 그대로 — 이 창구는 직원이 고른 값이라 451 밖 · 손님 적재(ImsLoadCustomer.gs:356)는 글자만 보낸다 — ③ 의 글자를 Cin7 값으로 한 번 덮을 수 있다(새 오더는 id 를 먼저 보므로 영향 없음 · 알고 간다)
--   화면(asung-ims customers.html cs v7b · 대화 Claude): sb.rpc("customer_default_carrier_set", { p_customer_id, p_carrier_id: ref_carrier.id 또는 null, p_old: 지금 customer.default_carrier_id 또는 null }) · error.message 를 그대로 보인다 · 성공이면 다시 읽는다(반환값은 안 쓴다)
--   새 표 없음 · 데이터 무접촉(새 함수 하나 · customer_export 재발행 · comment 셋) · 손님 행은 창구가 불릴 때만 바뀐다
--   ⚠️ 적용은 Caleb: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261029230000_cdc_1_default_carrier.sql && supabase migration repair --status applied 20261029230000 — db push 금지
--   시험: supabase/tests/cdc_1_check.sql(-v mig · begin → rollback · T1~T8) · 둘째 겹 = 적용 뒤 Caleb 이 customers.html cs v7b 의 Default carrier → Change 로 한 번 고르고 한 번 비운다(REST)

-- ═══ 0) 마지막 정의 확인 — customer_export prosrc md5 가 exp-1(20261026162607:298 · 유일한 정의)의 것일 때만 · 새 창구는 아직 없어야 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'customer_export') is distinct from '7ec349f11a80b7fe5d1bbf5d03386182' then v_bad := v_bad || ' customer_export(md5)'; end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'customer_default_carrier_set') then v_bad := v_bad || ' customer_default_carrier_set(already there)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM876', message = format('STOP - not the expected state:%s - re-read before re-issuing - nothing was changed', v_bad); end if;
end $$;

-- ═══ 1) 창구 customer_default_carrier_set — 꼴 · 보안은 customer_carrier_avoid_set(20261028162209:674) 그대로 · 문 = sales 쓰기 ═══
create function public.customer_default_carrier_set(p_customer_id uuid, p_carrier_id uuid, p_old uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_c public.customer%rowtype;  v_car public.ref_carrier%rowtype;
begin
  perform public.ims_require_write('sales');
  select * into v_c from public.customer c where c.id = p_customer_id for update;
  if not found then raise exception 'Customer % not found — nothing was saved', p_customer_id; end if;
  if v_c.default_carrier_id is distinct from p_old then                                                                                     -- 화면이 본 값(p_old)과 지금 값이 다르면 거부 — 동시 편집
    raise exception 'Someone changed this customer''s default carrier just now (it is now %) — reload the customer and try again — nothing was saved', coalesce(v_c.default_carrier, 'none');
  end if;
  if p_carrier_id is not null then                                                                                                           -- 876 ①: kind 셋 다(carrier · pickup · delivery) · 켜진 행만
    select * into v_car from public.ref_carrier rc where rc.id = p_carrier_id;
    if not found then raise exception 'Carrier % is not on the carrier list — pick one from the list — nothing was saved', p_carrier_id; end if;
    if not v_car.is_active then raise exception 'Carrier % is switched off — pick an active carrier — nothing was saved', v_car.name; end if;
  end if;
  if v_c.default_carrier_id is not distinct from p_carrier_id and v_c.default_carrier is not distinct from v_car.name then               -- 같은 값(id 같고 글자도 이미 표 이름 · null 이면 둘 다 null) — 쓰지 않는다(touch 도 안 돈다)
    return jsonb_build_object('customer_id', p_customer_id, 'changed', false, 'default_carrier_id', v_c.default_carrier_id, 'default_carrier', v_c.default_carrier);
  end if;
  update public.customer c set default_carrier_id = v_car.id, default_carrier = v_car.name where c.id = p_customer_id;                   -- 876 ③ · ④: 고르면 id + 표 이름 · 비우면(v_car 비어 있음) 둘 다 null · updated_at · updated_by 는 customer_touch(ims_touch)
  return jsonb_build_object('customer_id', p_customer_id, 'changed', true, 'default_carrier_id', v_car.id, 'default_carrier', v_car.name);
end;
$$;
revoke all on function public.customer_default_carrier_set(uuid, uuid, uuid) from public, anon, service_role;
grant execute on function public.customer_default_carrier_set(uuid, uuid, uuid) to authenticated;
comment on function public.customer_default_carrier_set(uuid, uuid, uuid) is 'cdc-1 판정 876: 손님 기본 운송사 고치기(sales · ref_carrier kind 셋 다 · 켜진 행만) — 고르면 default_carrier_id + 글자 default_carrier = 표 이름 · null 이면 둘 다 null(so_copy_customer 가 옛 글자를 싣지 않게) · p_old = 화면이 본 default_carrier_id(다르면 거부) · 같은 값이면 changed false · 반환 {customer_id, changed, default_carrier_id, default_carrier}';

-- ═══ 2) 칸 comment — 옛 글 그대로 + 876 한 줄 ═══
comment on column public.customer.default_carrier_id is 'ful-1a 판정 436 · 451: 손님 기본 운송사(ref_carrier) — so_copy_customer 가 새 오더의 carrier_id 로 복사 · 옛 글자(default_carrier)와 이름이 정확히 같을 때만 이었고 나머지는 null(억지로 맞추면 Pickup 손님에게 발송 메일이 간다) · 적재(ImsLoadCustomer)는 글자만 쓰므로 이 칸을 덮지 않는다 · cdc-1 판정 876: 직원이 고치는 창구는 customer_default_carrier_set(sales · kind 셋 다 · 고르면 글자도 표 이름 · 비우면 둘 다 null)';
comment on column public.customer.default_carrier is 'Cin7 Carrier 원문 — ⭐ [ful-1a 판정 451] 기본값의 주인은 default_carrier_id · 이 글자는 원래 글자로 남긴다(표에 없는 글자를 직원이 보고 고른다) · cdc-1 판정 876: customer_default_carrier_set 이 고르면 표 이름으로 · 비우면 null(451 은 적재 규칙으로 그대로 · 적재는 여전히 이 글자만 쓴다)';

-- ═══ 3) customer_export 재발행 — 20261026162607:298~346 바이트 복사 + 운송사 칸 한 줄(coalesce) · 조인 한 줄 · create or replace · comment 끝에 876 ═══
create or replace function public.customer_export(p_q text default null, p_only_active boolean default true, p_only_new boolean default false, p_columns text[] default null)
returns jsonb language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_q text := nullif(btrim(p_q), ''); v_cols jsonb; v_keys text[]; v_total bigint; v_rows jsonb;
begin
  select jsonb_agg(jsonb_build_object('key', k.key, 'label', k.label, 'text', k.is_text) order by k.o), array_agg(k.key order by k.o)
    into v_cols, v_keys from public.export_pick('customer', p_columns) k;
  with base as (
    select c.* from public.customer c
    where (not coalesce(p_only_active, false) or c.is_active)
      and (not coalesce(p_only_new, false) or (c.source = 'manual' and c.reviewed_at is null))
      and (v_q is null or c.name ilike '%' || v_q || '%' or c.display_name ilike '%' || v_q || '%')
  ),
  pick as materialized (select * from base order by name, id limit 20000),
  ad as materialized (                                   -- 손님마다 한 줄(기본 Billing · 기본 Shipping) — 같은 CTE 를 두 번 잇면 줄마다 다시 훑어 8 초를 넘었다(exp-1 시험 3 회차)
    select a.customer_id,
           max(a.line1) filter (where a.type = 'Billing') b_line1, max(a.line2) filter (where a.type = 'Billing') b_line2, max(a.city) filter (where a.type = 'Billing') b_city,
           max(a.state_province) filter (where a.type = 'Billing') b_prov, max(a.postal_code) filter (where a.type = 'Billing') b_postal, max(a.country) filter (where a.type = 'Billing') b_country,
           max(a.line1) filter (where a.type = 'Shipping') s_line1, max(a.line2) filter (where a.type = 'Shipping') s_line2, max(a.city) filter (where a.type = 'Shipping') s_city,
           max(a.state_province) filter (where a.type = 'Shipping') s_prov, max(a.postal_code) filter (where a.type = 'Shipping') s_postal, max(a.country) filter (where a.type = 'Shipping') s_country
    from public.customer_address a
    where a.is_active and a.is_default_for_type and a.type in ('Billing', 'Shipping') and a.customer_id in (select id from pick) group by 1),
  ct as materialized (select t.customer_id, t.name, t.phone, t.mobile_phone, t.email, t.marketing_consent from public.customer_contact t
         where t.is_active and t.is_default and t.customer_id in (select id from pick)),
  full_ as materialized (                -- 한 번만 만든다 — 그냥 두면 고른 칸마다 jsonb 를 다시 만들어 손님 전 칸이 16 초였다(exp-1 시험 3 회차)
    select c.name, c.id, jsonb_build_object(
      'name', c.name, 'display_name', c.display_name, 'is_active', c.is_active, 'price_tier', c.price_tier, 'payment_term', c.payment_term_name,
      'currency', c.currency_code, 'discount_pct', c.discount_pct, 'tax_rule', c.tax_rule, 'default_warehouse', c.default_location_name,
      'parent', par.name, 'invoices_to', bto.name, 'carrier', coalesce(rc.name, c.default_carrier), 'tax_number', c.tax_number, 'tags', c.tags,
      'invoice_split_by_store', c.invoice_split_by_store, 'backorder_mail', c.backorder_mail, 'invoice_mail', c.final_invoice_mail,
      'source', case c.source when 'manual' then 'IMS' when 'cin7' then 'Before IMS' else c.source end,
      'created_at', to_char(c.created_at at time zone 'America/Toronto', 'YYYY-MM-DD'), 'reviewed_at', to_char(c.reviewed_at at time zone 'America/Toronto', 'YYYY-MM-DD'))
      || jsonb_build_object(
      'billing_line1', a.b_line1, 'billing_line2', a.b_line2, 'billing_city', a.b_city, 'billing_province', a.b_prov, 'billing_postal', a.b_postal, 'billing_country', a.b_country,
      'shipping_line1', a.s_line1, 'shipping_line2', a.s_line2, 'shipping_city', a.s_city, 'shipping_province', a.s_prov, 'shipping_postal', a.s_postal, 'shipping_country', a.s_country,
      'contact_name', t.name, 'contact_phone', t.phone, 'contact_mobile', t.mobile_phone, 'contact_email', t.email,
      'contact_marketing', case t.marketing_consent when true then 'Opt in' when false then 'Opt out' else case when t.customer_id is null then null else 'Unknown' end end) as j
    from pick c
    left join public.customer par on par.id = c.parent_id
    left join public.customer bto on bto.id = c.default_bill_to_customer_id
    left join public.ref_carrier rc on rc.id = c.default_carrier_id                        -- cdc-1 판정 876 ⑤: 운송사 칸 = id 의 표 이름(없으면 글자)
    left join ad a on a.customer_id = c.id
    left join ct t on t.customer_id = c.id
  )
  select (select count(*) from base),
         coalesce(jsonb_agg((select jsonb_agg(f.j -> u.k order by u.o) from unnest(v_keys) with ordinality u(k, o)) order by f.name, f.id), '[]'::jsonb)
    into v_total, v_rows from full_ f;
  return jsonb_build_object('kind', 'customer', 'total', v_total, 'row_count', jsonb_array_length(v_rows), 'truncated', v_total > 20000,
                            'columns', v_cols, 'rows', v_rows);
end $$;
comment on function public.customer_export(text, boolean, boolean, text[]) is 'exp-1 판정 699 · 700 · 761 · 762 · 763 — 손님 내보내기: customers.html 의 거르기(검색 = 이름 · 표시 이름 · Active only · New — not reviewed) + p_columns → {kind, total, row_count, truncated, columns, rows} · 순서 name · 주소 = 기본 Billing · 기본 Shipping · 연락처 = 기본 · 주소 · 연락처 칸은 sales 쓰기 ∨ master 쓰기만(761) · cdc-1 판정 876 ⑤: 운송사 칸 = default_carrier_id 의 표 이름(없으면 글자 default_carrier)';
