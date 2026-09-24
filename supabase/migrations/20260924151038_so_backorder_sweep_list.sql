-- SO 쓰기 ③c — 백오더 만료 스윕(cron) · 읽기 함수 so_backorder_list (2026-09-24 UTC)
-- 지시서 ~/asung/prompts/so-write-3-ship.md 판정 6·7·11 · ⬜9 · ⬜11 · 판정 회신(90일 · 토론토 새벽 · 뒤처리 끝난 오더도 닫힌다 · 출발 줄 없는 도착은 세지 않는다 · 알림 전 표시)
-- 바탕: 20260924145105(so_backorder_close · so_backorder_record · so_backorder_reopen) · 20260924141140(released_reason 'closed') · 20260924015859(so_available_many) · 20260824202539(wms_auto_hold — cron 함수 모양 · revoke 셋) · 20260916190000:103(inv_config seed 선례)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/so-write-3c-verify.sql · cron 등록은 supabase/ops/cron.sql(Caleb)
--
-- ⭐ 무엇을 하나
--    ① inv_config so_backorder_expire_days = '90'(일 · 달은 길이가 달라 일로 · 5-g 「기간은 설정」 · on conflict do nothing)
--    ② so_backorder_sweep() — cron 이 postgres 로 부른다(wms_auto_hold 모양: security invoker · public·anon·authenticated 전부 revoke · 반환 jsonb)
--       대상: status confirmed ∧ order_date + days < ims_today() ∧ 열린 예약이 전부 backorder 이거나 0개 — preorder·hold·allocated 예약이 하나라도 있으면 대상 아님(판정 9 · 보통 확정 오더는 닫히지 않는다)
--       한 오더: 남은 열린 backorder 줄 → 장부 expired(ended_by null = 시스템) → 예약 released_reason 'closed' → 오더 cancelled · closed_reason(열린 줄이 있었으면 expired · 0 이었으면 superseded) · closed_at · closed_note
--       이미 끝난 줄(장부 있음 · 예약 닫힘)은 그대로 · 기간을 늘려도 이미 닫힌 오더는 무접촉(cancelled 는 대상 밖) · 두 번 돌려도 같다 · 상한 c_cap 200(오래된 order_date 먼저 · 남은 수를 반환)
--    ③ so_backorder_list(p_filters jsonb) — 읽기 창구 하나(invoker · stable · authenticated) · jsonb 하나(PostgREST 1,000행 상한 · limit ≤ 1000)
--       줄 = 열린 백오더 예약(open) ∪ 장부 활성 줄(ended) · 분류 여덟(손님 · 공급처(기본 · 없으면 null · 필터 'none') · 브랜드 · SKU · 기간(원래 주문일 · 끝난 날) · 브랜치 · 이메일 · 입고됨)
--       입고됨(판정 6·7) = 백오더가 생긴 뒤(그 줄 backorder 예약의 allocated_at) 그 창고(so.location_name = inv_ledger.warehouse)에 po_in(+) 또는 다른 창고에서 온 transfer_in(같은 doc_number·sku 의 transfer_out 창고가 IN_TRANSIT 아니고 도착 창고와 다르다) ·
--                    조정(adjust_*) · 반품(credit_in) · 조립(assemble_in) 제외 · 출발 줄 없는 도착 제외(어디서 왔는지 모른다 · §3-① no_out_leg 2 docs) · 지금 가용이 다시 0 이어도 분류는 그대로(가용은 옆에)
--       알림: backorder_notified_at 은 지금 아무도 안 채운다(GAS 가 Cin7 에서 보낸다) — 줄마다 notified_state 'sent' | 'unknown_pre_ims' · 머리에 notify_tracking 문장(화면이 「안 보냄」으로 거짓 표시하지 않게 · 이견 8)
--       가용: 창고마다 so_available_many 한 번씩(줄마다 부르지 않는다 · §14-e) — available_here · available_other{창고: EA}
-- ⭐ 판정(이 파일이 정한 것 · 정본 §15 로 말만)
--    closed_reason — 스윕이 닫을 때 열린 백오더 줄이 하나라도 있었으면 expired(수요가 기간으로 소멸) · 0 이었으면 superseded(수요는 새 오더로 옮겨 갔고 문서만 정리) — 대화 Claude 안 채택 · 근거: closed_reason 은 「무엇이 수요를 끝냈나」를 말한다(5-g 셋)
--    상한 200 — wms_auto_hold 의 20 은 2분마다 도는 잡의 몫 · 이 잡은 하루 한 번이고 첫 회차(전환 뒤)에 석 달치가 한꺼번에 걸릴 수 있다 · 오더 하나가 싸서(줄 몇 개) 200 도 1초 안(짐작) · 남으면 반환 remaining 에 보이고 다음 날 이어 닫는다
--    설정이 없거나 숫자가 아니면 스윕은 예외로 멈춘다(짐작 값으로 닫지 않는다 · cron 로그에 남는다)
-- ⚠️ 다시 만들지 않은 것 — so_backorder_record · so_backorder_reopen · so_available_many · ims_today · so_status_guard(confirmed→cancelled 짝 있음)
-- ⚠️ 시퀀스 무접촉 · seed 는 inv_config 한 줄

-- ═══ ① 설정 ═══
insert into public.inv_config (key, value, note) values
  ('so_backorder_expire_days', '90',
   'Backorder orders expire this many days after order_date (so_backorder_sweep · daily cron). Days, not months. Was 3 months by hand in Cin7 (so-module 1-h · 5-g). Raising it does not reopen orders already expired — the rule at closing time stands. Caleb 2026-09-24.')
on conflict (key) do nothing;

-- ═══ ② so_backorder_sweep — 만료(cron · postgres) ═══
create function public.so_backorder_sweep() returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  c_cap    constant int := 200;                      -- 회차 상한(오래된 order_date 먼저 · 남은 수는 remaining)
  v_cfg    text;
  v_days   int;
  v_today  date := public.ims_today();
  v_cut    date;
  s        record;
  r        record;
  v_open   int;
  v_reason text;
  v_orders int := 0;
  v_lines  int := 0;
  v_remaining int := 0;
  v_n      int;
  v_out    jsonb := '[]'::jsonb;
begin
  select k.value into v_cfg from public.inv_config k where k.key = 'so_backorder_expire_days';
  if v_cfg is null or v_cfg !~ '^[0-9]{1,4}$' or v_cfg::int <= 0 then
    raise exception 'inv_config.so_backorder_expire_days is missing or not a positive whole number (%) — the backorder sweep did not run', coalesce(v_cfg, 'null');
  end if;
  v_days := v_cfg::int;
  v_cut  := v_today - v_days;                        -- order_date < v_cut  ⇔  order_date + days < today

  for s in
    select x.id, x.so_number, x.order_date
    from public.so x
    where x.status = 'confirmed'
      and x.order_date < v_cut
      and not exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                      where l.so_id = x.id and rr.released_at is null and rr.kind <> 'backorder')   -- preorder · hold · allocated 가 하나라도 있으면 대상 아님
    order by x.order_date, x.so_number
    limit c_cap
  loop
    perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(s.so_number, '[a-z]+$', '')));
    v_open := 0;
    for r in
      select rr.id as reserve_id, rr.so_line_id, rr.qty_allocated
      from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
      where l.so_id = s.id and rr.released_at is null and rr.kind = 'backorder'
      order by l.line_no
    loop
      perform pg_advisory_xact_lock(hashtext('so_reserve:' || r.so_line_id::text));
      perform public.so_backorder_record(r.so_line_id, 'expired', r.qty_allocated, 0, 0, null, null, null,
                                         format('Expired after %s days (order_date %s · today %s)', v_days, s.order_date, v_today));
      update public.so_reserve set released_at = now(), released_by = null, released_reason = 'closed' where id = r.reserve_id and released_at is null;
      v_open := v_open + 1;
    end loop;
    v_reason := case when v_open > 0 then 'expired' else 'superseded' end;
    update public.so set status = 'cancelled', closed_reason = v_reason, closed_at = now(), cancelled_by = null,
           closed_note = case when v_open > 0 then format('Expired after %s days — %s backorder line(s) still open (order_date %s)', v_days, v_open, s.order_date)
                              else format('All lines already taken over or ended — closed by the backorder sweep after %s days (order_date %s)', v_days, s.order_date) end
    where id = s.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception 'Backorder order % was not closed — it may have been changed by someone else just now — the sweep stopped', s.so_number;
    end if;
    v_orders := v_orders + 1;  v_lines := v_lines + v_open;
    v_out := v_out || jsonb_build_object('so_number', s.so_number, 'order_date', s.order_date, 'closed_reason', v_reason, 'lines_expired', v_open);
  end loop;

  select count(*) into v_remaining
  from public.so x
  where x.status = 'confirmed' and x.order_date < v_cut
    and not exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                    where l.so_id = x.id and rr.released_at is null and rr.kind <> 'backorder');

  return jsonb_build_object('today', v_today, 'expire_days', v_days, 'cutoff_order_date_before', v_cut, 'cap', c_cap,
                            'orders_closed', v_orders, 'lines_expired', v_lines, 'remaining', v_remaining, 'orders', v_out);
end;
$$;
comment on function public.so_backorder_sweep() is
  '⭐ 백오더 만료 스윕(③c · 5-g · 판정 9·11 · cron 매일 · postgres 만) — inv_config so_backorder_expire_days(90) · 대상 = confirmed ∧ order_date + days < ims_today() ∧ 열린 예약이 전부 backorder 이거나 0개(preorder·hold·allocated 있으면 제외) · 남은 열린 백오더 줄은 장부 expired(시스템) + 예약 closed · 오더 cancelled(열린 줄 있었으면 expired · 0 이면 superseded) · 상한 200(오래된 것 먼저 · remaining 반환) · 설정이 없으면 예외로 멈춘다 · 두 번 돌려도 같다. ⚠️ authenticated 는 부르지 못한다(cron 소유자만 · wms_auto_hold 모양)';
-- cron(postgres 소유자)만 부른다 — 화면·직원이 남의 백오더를 닫는 경로 차단(wms_auto_hold 20260824202539:185~187 과 같은 모양)
revoke all on function public.so_backorder_sweep() from public;
revoke all on function public.so_backorder_sweep() from anon;
revoke all on function public.so_backorder_sweep() from authenticated;

-- ═══ ③ so_backorder_list — 읽기 창구(invoker · stable · authenticated) ═══
--   p_filters 열쇠: customer_id · supplier_id(uuid 또는 'none') · brand_id · sku(앞글자 일치 · 대소문자 무관) · product_id · location_id · state open|ended|all(기본 all) · end_kind ·
--                  order_from · order_to(원래 주문일) · ended_from · ended_to(끝난 날) · arrived true|false · notified true|false · limit(기본 200 · 최대 1000) · offset
create function public.so_backorder_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','state','end_kind','order_from','order_to','ended_from','ended_to','arrived','notified','limit','offset'];
  v_bad    text;
  v_state  text := coalesce(nullif(f->>'state', ''), 'all');
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_rows   jsonb;
  v_total  int;
  v_open   int;
  v_ended  int;
  v_avail  jsonb := '{}'::jsonb;                   -- "warehouse_id:stock_pid" → available_ea (창고마다 so_available_many 한 번)
  v_pids   uuid[];
  w        record;
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if v_state not in ('open', 'ended', 'all') then raise exception 'state must be open, ended or all'; end if;

  -- 낱개 제품 묶음(가용 계산용) — stable 함수라 임시 표를 쓰지 않는다(INSERT 금지) · 같은 합집합을 아래 bo 가 다시 읽는다
  select array_agg(distinct x.stock_pid) into v_pids
  from (
    select coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.product p on p.id = l.product_id
    where r.kind = 'backorder' and r.released_at is null
    union
    select coalesce(p.parent_product_id, p.id)
    from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.product p on p.id = l.product_id
    where c.reopened_at is null
  ) x;

  -- 가용 — 활성 창고마다 so_available_many 한 번(줄마다 부르지 않는다) · 이 목록의 낱개 제품 전부
  for w in select wh.id, wh.name from public.ref_warehouse wh where wh.is_active order by wh.name loop
    select coalesce(v_avail || jsonb_object_agg(w.id::text || ':' || m.stock_pid::text, m.available_ea), v_avail) into v_avail
    from public.so_available_many(v_pids, w.id) m;
  end loop;

  with bo as (
    select l.id as line_id, s.id as so_id, s.so_number, s.order_date, s.location_id, s.location_name, s.customer_id,
           l.product_id, coalesce(p.parent_product_id, p.id) as stock_pid, coalesce(pp.sku, p.sku) as base_sku, l.sku, l.product_name, l.pack_factor, l.qty_ordered,
           'open'::text as state, r.qty_allocated as qty_open, r.allocated_at as backorder_since,
           null::text as end_kind, null::numeric as qty_taken, null::numeric as qty_unwanted, null::uuid as taken_by_so_id, null::timestamptz as ended_at, l.backorder_notified_at as notified_at
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    left join public.product pp on pp.id = p.parent_product_id
    where r.kind = 'backorder' and r.released_at is null
    union all
    select l.id, s.id, s.so_number, s.order_date, s.location_id, s.location_name, s.customer_id,
           l.product_id, coalesce(p.parent_product_id, p.id), coalesce(pp.sku, p.sku), l.sku, l.product_name, l.pack_factor, l.qty_ordered,
           'ended', c.qty_open,
           (select max(r2.allocated_at) from public.so_reserve r2 where r2.so_line_id = l.id and r2.kind = 'backorder'),
           c.end_kind, c.qty_taken, c.qty_unwanted, c.taken_by_so_id, c.ended_at, l.backorder_notified_at
    from public.so_backorder_close c
    join public.so_line l on l.id = c.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    left join public.product pp on pp.id = p.parent_product_id
    where c.reopened_at is null
  ),
  base as (
    select t.*,
           cu.name as customer_name,
           p.brand_id, p.brand_name,
           ps.supplier_id, su.name as supplier_name,
           ts.so_number as taken_by_so_number,
           -- 입고됨(판정 6·7): 백오더가 생긴 뒤 그 창고에 po_in 또는 다른 창고에서 온 transfer_in(출발 줄이 있고 출발 창고 ≠ 도착 창고 · IN_TRANSIT 제외) · 조정·반품·조립 제외
           exists (
             select 1 from public.inv_ledger g
             where g.sku = t.base_sku and g.warehouse = t.location_name and g.qty_delta > 0
               and g.occurred_on >= (t.backorder_since at time zone 'America/Toronto')::date
               and (g.event_type = 'po_in'
                    or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
                        and exists (select 1 from public.inv_ledger o
                                    where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                                      and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
           ) as arrived,
           (v_avail->>(t.location_id::text || ':' || t.stock_pid::text))::numeric as available_here,
           (select jsonb_object_agg(wh.name, (v_avail->>(wh.id::text || ':' || t.stock_pid::text))::numeric)
              from public.ref_warehouse wh where wh.is_active and wh.id is distinct from t.location_id) as available_other
    from bo t
    join public.customer cu on cu.id = t.customer_id
    join public.product p on p.id = t.product_id
    left join public.product_supplier ps on ps.product_id = t.product_id and ps.is_default and ps.is_active
    left join public.supplier su on su.id = ps.supplier_id
    left join public.so ts on ts.id = t.taken_by_so_id
  ),
  filtered as (
    select * from base b
    where (f->>'customer_id' is null or b.customer_id = (f->>'customer_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_id is null) or (f->>'supplier_id' <> 'none' and b.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or b.sku ilike (f->>'sku') || '%' or b.base_sku ilike (f->>'sku') || '%')
      and (f->>'product_id'  is null or b.product_id = (f->>'product_id')::uuid)
      and (f->>'location_id' is null or b.location_id = (f->>'location_id')::uuid)
      and (v_state = 'all' or b.state = v_state)
      and (f->>'end_kind'    is null or b.end_kind = f->>'end_kind')
      and (f->>'order_from'  is null or b.order_date >= (f->>'order_from')::date)
      and (f->>'order_to'    is null or b.order_date <= (f->>'order_to')::date)
      and (f->>'ended_from'  is null or (b.ended_at at time zone 'America/Toronto')::date >= (f->>'ended_from')::date)
      and (f->>'ended_to'    is null or (b.ended_at at time zone 'America/Toronto')::date <= (f->>'ended_to')::date)
      and (f->>'arrived'     is null or b.arrived = (f->>'arrived')::boolean)
      and (f->>'notified'    is null or (b.notified_at is not null) = (f->>'notified')::boolean)
  )
  select count(*), count(*) filter (where state = 'open'), count(*) filter (where state = 'ended'),
         coalesce((select jsonb_agg(jsonb_build_object(
             'so_id', x.so_id, 'so_number', x.so_number, 'order_date', x.order_date, 'line_id', x.line_id,
             'customer_id', x.customer_id, 'customer_name', x.customer_name,
             'product_id', x.product_id, 'sku', x.sku, 'base_sku', x.base_sku, 'product_name', x.product_name, 'pack_factor', x.pack_factor,
             'brand_id', x.brand_id, 'brand_name', x.brand_name, 'supplier_id', x.supplier_id, 'supplier_name', x.supplier_name,
             'location_id', x.location_id, 'location_name', x.location_name,
             'qty_ordered', x.qty_ordered, 'qty_open', x.qty_open, 'backorder_since', x.backorder_since,
             'state', x.state, 'end_kind', x.end_kind, 'qty_taken', x.qty_taken, 'qty_unwanted', x.qty_unwanted,
             'taken_by_so_id', x.taken_by_so_id, 'taken_by_so_number', x.taken_by_so_number, 'ended_at', x.ended_at,
             'notified_at', x.notified_at, 'notified_state', case when x.notified_at is not null then 'sent' else 'unknown_pre_ims' end,
             'arrived', x.arrived, 'available_here', x.available_here, 'available_other', x.available_other)
           order by x.customer_name, x.customer_id, x.base_sku, x.order_date, x.so_number, x.line_id)
           from (select * from filtered order by customer_name, customer_id, base_sku, order_date, so_number, line_id limit v_limit offset v_offset) x), '[]'::jsonb)
    into v_total, v_open, v_ended, v_rows
  from filtered;

  return jsonb_build_object(
    'total', v_total, 'open', v_open, 'ended', v_ended, 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'notify_tracking', 'pre_ims — backorder_notified_at is not written yet (GAS sends arrival mail from Cin7); notified_state unknown_pre_ims is not "not sent"',
    'arrived_rule', 'po_in or transfer_in from another warehouse (same doc transfer_out at a different, non-IN_TRANSIT warehouse) at the order warehouse since the backorder was made; adjustments, credits, assemblies and arrivals without a departure leg do not count',
    'rows', v_rows);
end;
$$;
comment on function public.so_backorder_list(jsonb) is
  '⭐ 백오더 읽기 창구 하나(③c · 판정 5·6·7 · ⬜11) — 줄 = 열린 backorder 예약(open) ∪ 장부 활성 줄(ended · so_backorder_close.reopened_at null) · 분류 여덟(손님 · 기본 공급처 없음=null/필터 none · 브랜드 · SKU · 주문일·끝난 날 · 브랜치 · 알림 · 입고됨) · 가용 here/other(창고마다 so_available_many 한 번) · 손님별 흐름은 손님·제품·order_date 순 · jsonb 하나(limit ≤ 1000 · offset). 알림 칸은 pre_ims(notified_state unknown_pre_ims 는 「안 보냄」이 아니다). invoker · stable(임시 표 없음 — stable 은 INSERT 를 못 한다 · 합집합을 두 번 읽는다)';
revoke all on function public.so_backorder_list(jsonb) from public, anon;
grant execute on function public.so_backorder_list(jsonb) to authenticated;

-- ═══ cron — supabase/ops/cron.sql 에 기록(마이그레이션 아님 · 등록은 Caleb) : 'so-backorder-sweep' · '17 9 * * *'(09:17 UTC = 토론토 05:17 EDT · 04:17 EST) · select so_backorder_sweep() ═══
-- ═══ 검증(Caleb · ~/asung/prompts/so-write-3c-verify.sql) — 만료(89일 무접촉 · 91일 닫힘 · 뒤처리 끝난 오더 superseded · preorder·hold 무접촉 · 이미 끝난 줄 그대로 · 두 번째 회차 0) · 만료 뒤 다시 열기 거부 · 읽기(필터 · 입고됨 여섯) · authenticated 가 sweep 을 못 부른다 ═══
