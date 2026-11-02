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
-- aone-bo-1 — aonebeauty.com(aone) 웹 오더의 백오더: 자동 알림에서 빼고 사람이 고른다 · aone 손님은 backorder_mail off · Backorders 다섯 창구에 store 거르기 (2026-11-01 밤 · 판정 948 · 949 · 덧붙임 3 · 지시서 mail-live-1 덧붙임 · EF mail(_shared/mail.ts chatText · mail_test.ts) 같은 커밋 · 앞 차수 mail-live-1 20261102013000)
--   가르는 열쇠 하나: so_store_of(intake, ref) → 'asung' | 'aone' | 'manual'(웹 아님) — so v5z2(판정 916)의 규칙(intake shopify + ref 앞글자 AS- · AO- · 나뉜 오더는 ref 를 이어받는다 · 20/20 실측)을 함수로.
--   ① so_store_of(immutable) ② mail_backorder_line.basis 에 manual ③ ops_aone_bo_off(949 ② 되돌리기 재료 · postgres 만)
--   ④ 다섯 창구 재발행 — c_keys 에 store · 값 검사 · 거르기 한 줄 · 행에 store(list · ready · demand 줄/행) · stores(arrivals · 기다리는 줄의 스토어 배열) · overview 는 분모(ordered)에 거르기 + demand 로 같은 f 가 넘어간다
--        so_backorder_list(마지막 정의 20261016133451 · md5 cbc0ee1c181ab540b569558a40cd16af) · so_backorder_arrivals(20261015015435 · 25dee596844dba2a7cf62e38faa8fb69) · so_backorder_ready(20261015024520 · 2ea4fe401068594ea2f9da06447b30cf)
--        so_backorder_overview(20261015024520 · ce3f84b03c40bf460240dd8043c527f2) · so_backorder_demand(20261014234811 · eec87cef20c7b626c7ea7088a04d2b4d)
--   ⑤ mail_backorder_pick 재발행(md5 5b32987f6a6531a831987030185ed763) — fl0(스토어) → fl 은 aone 제외 · aone_lines 수 ⑥ mail_backorder_tick(ed117405eed18ee101e2a05a9ec46624) — params · runs 에 aone_lines ⑦ mail_run_chat_due(fb2d46bc080f0f598bb246b6c8fe50c6) — aone_lines(EF Chat 한 줄 · 948 ⑥)
--   ⑧ mail_backorder_send(p_line_ids, p_commit) 새 창구(948 ③ · ④) ⑨ shop_order_prepare(b6e06d4604f6535cd0b0c935c68dbf55) — aone 이면 payload backorder_mail false ⑩ customer_create(76f4ca450c6d087a9bd19b794f39a085) — backorder_mail 칸(없으면 true) ⑪ 착지 확인
--   재발행은 DB 의 마지막 정의(pg_get_functiondef)에 자리만 바꿔 넣었다(조립 스크립트가 교체마다 등장 수를 단정) · 권한(acl)은 create or replace 가 지킨다(착지에서 본다)
--   ⚠️ 적용은 Caleb: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261102020000_aone_bo_1.sql && supabase migration repair --status applied 20261102020000 · 그 뒤 supabase/ops/aone-bo-1-off.sql(949 ②) · EF mail 재배포(mail-live-1 과 한 번) · db push 금지
--   시험: supabase/tests/aone_bo_1_check.sql(begin → \i → A ~ G 갈래 → rollback)


-- ═══ 1) so_store_of — 스토어 판정(so v5z2 규칙 · 한 곳) ═══
create or replace function public.so_store_of(p_intake text, p_ref text)
returns text
language sql
immutable
set search_path = public, pg_temp
as $$
  select case when p_intake = 'shopify' and p_ref ~ '^AO-' then 'aone'
              when p_intake = 'shopify' and p_ref ~ '^AS-' then 'asung'
              else 'manual' end;
$$;
revoke all on function public.so_store_of(text, text) from public, anon;
grant execute on function public.so_store_of(text, text) to authenticated, service_role;
comment on function public.so_store_of(text, text) is 'aone-bo-1 판정 948 · 덧붙임 3 — 오더의 스토어: intake shopify + ref 앞글자 AO- = aone(aonebeauty.com) · AS- = asung(asung.ca) · 그 밖 = manual(웹 아님 · 직원 오더 · 모르는 접두어). so v5z2(판정 916)의 화면 규칙과 같다 · 나뉜 오더는 ref 를 이어받으므로 그 행만 본다 · Backorders 다섯 창구 · mail_backorder_pick · mail_backorder_send 가 쓴다';

-- ═══ 2) mail_backorder_line.basis — manual(직원이 보냄) ═══
alter table public.mail_backorder_line drop constraint mail_backorder_line_basis_ck;
alter table public.mail_backorder_line add constraint mail_backorder_line_basis_ck check (basis in ('receipt', 'full', 'manual'));

-- ═══ 3) ops_aone_bo_off — 949 ② 한 번 끄기의 되돌리기 재료(ops/aone-bo-1-off.sql 이 쓴다 · postgres 만) ═══
create table if not exists public.ops_aone_bo_off (
  customer_id uuid primary key references public.customer(id),
  was_on      boolean not null,
  off_at      timestamptz not null default now(),
  note        text
);
alter table public.ops_aone_bo_off enable row level security;
revoke all on table public.ops_aone_bo_off from public, anon, authenticated, service_role;
comment on table public.ops_aone_bo_off is 'aone-bo-1 판정 949 ② — aone 만 거래한 기존 손님의 backorder_mail 을 한 번 껐다는 기록(ops/aone-bo-1-off.sql · 멱등). 되돌리기: update customer c set backorder_mail = true from ops_aone_bo_off o where o.customer_id = c.id and o.was_on; 그 뒤 이 표를 비운다 · 화면 · 창구 없음(postgres 만)';

-- ═══ 4) so_backorder_list — c_keys store · 거르기 · 행 store ═══
CREATE OR REPLACE FUNCTION public.so_backorder_list(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','state','end_kind','order_from','order_to','ended_from','ended_to','arrived','notified','owed','limit','offset','kind','store'];   -- bo-pre-1 판정 351: 거르기 kind
  v_bad    text;
  v_state  text := coalesce(nullif(f->>'state', ''), 'all');
  v_kind   text := nullif(f->>'kind', '');                                                                           -- bo-pre-1 판정 351: backorder | preorder · 없으면 둘 다
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_rows   jsonb;
  v_total  int;
  v_open   int;
  v_ended  int;
  v_open_owed int;                                 -- 열린 무상 백오더(우리가 줄 것) 수
  v_open_bo int;  v_open_pre int;                  -- bo-pre-1 판정 351: 열린 것 가운데 백오더 · 프리오더 수(화면이 거르기 옆에 보인다)
  v_avail  jsonb := '{}'::jsonb;                   -- "warehouse_id:stock_pid" → available_ea (창고마다 so_available_many 한 번)
  v_pids   uuid[];
  w        record;
begin
  if not public.ims_can_view('sales') then raise exception 'Backorders needs the sales permission — nothing was read'; end if;   -- mail-1c(mail-1b 이견 1): definer 로 바꾸며 첫 줄(Backorders 화면 = sales · ims-auth.js:81)
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if f->>'store' is not null and f->>'store' not in ('asung', 'aone', 'manual') then raise exception 'store must be asung, aone or manual (got %)', f->>'store'; end if;   -- aone-bo-1 판정 948 · 덧붙임 3: 스토어 거르기(so_store_of)
  if v_state not in ('open', 'ended', 'all') then raise exception 'state must be open, ended or all'; end if;
  if v_kind is not null and v_kind not in ('backorder', 'preorder') then raise exception 'kind must be backorder or preorder'; end if;   -- bo-pre-1 판정 351

  -- 낱개 제품 묶음(가용 계산용) — stable 함수라 임시 표를 쓰지 않는다(INSERT 금지) · 같은 합집합을 아래 bo 가 다시 읽는다
  select array_agg(distinct x.stock_pid) into v_pids
  from (
    select coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.product p on p.id = l.product_id
    where r.kind in ('backorder', 'preorder') and r.released_at is null                                                 -- bo-pre-1 판정 351: 프리오더 줄도 같은 목록
    union
    select coalesce(p.parent_product_id, p.id)
    from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.product p on p.id = l.product_id
    where c.reopened_at is null
    union                                                                                                       -- asm-2b2: 장부가 콤보 줄에 설 때 그 구성품의 재고 키(열린 콤보 백오더의 예약은 구성품 줄에 있어 첫 갈래가 이미 담는다)
    select coalesce(p.parent_product_id, p.id)
    from public.so_backorder_close c join public.so_line cp on cp.combo_line_id = c.so_line_id join public.product p on p.id = cp.product_id
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
           'open'::text as state, q.qty_open, q.since as backorder_since,
           null::text as end_kind, null::numeric as qty_taken, null::numeric as qty_unwanted, null::uuid as taken_by_so_id, null::timestamptz as ended_at,
           q.kind,                                                                                                                  -- bo-pre-1 판정 351: 행마다 kind(backorder | preorder)
           l.free_reason, public.so_store_of(s.intake, s.ref) as store                                                                                          -- 판정 15·16: 무상 줄 = owed(우리가 줄 것)
    from (select distinct coalesce(cp.combo_line_id, cp.id) as line_id                                           -- asm-2b2(묶음 4): 수요 줄 — 예약은 구성품 줄에 있지만 목록은 콤보 줄 하나로(수량 = 콤보 수 · 구성품은 아래 components)
            from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id where r.kind in ('backorder', 'preorder') and r.released_at is null) d   -- bo-pre-1 판정 351
    join public.so_line l on l.id = d.line_id
    cross join lateral (select min(floor(r.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, min(r.allocated_at) as since, min(r.kind) as kind   -- bo-pre-1: 기준 시각 = 그 예약이 생긴 때(같은 식) · 한 수요 줄의 예약은 한 kind
                        from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id
                        where (cp.id = l.id or cp.combo_line_id = l.id) and r.kind in ('backorder', 'preorder') and r.released_at is null) q   -- bo-pre-1 판정 351
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    left join public.product pp on pp.id = p.parent_product_id
    union all
    select l.id, s.id, s.so_number, s.order_date, s.location_id, s.location_name, s.customer_id,
           l.product_id, coalesce(p.parent_product_id, p.id), coalesce(pp.sku, p.sku), l.sku, l.product_name, l.pack_factor, l.qty_ordered,
           'ended', c.qty_open,
           (select max(r2.allocated_at) from public.so_reserve r2 join public.so_line cp on cp.id = r2.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and r2.kind = 'backorder'),   -- asm-2b2: 콤보 줄의 예약은 구성품에
           c.end_kind, c.qty_taken, c.qty_unwanted, c.taken_by_so_id, c.ended_at,
           'backorder'::text,                                                                                                       -- bo-pre-1: 끝난 목록은 백오더만(프리오더는 기록 표가 없다 · 판정 9)
           l.free_reason, public.so_store_of(s.intake, s.ref) as store
    from public.so_backorder_close c
    join public.so_line l on l.id = c.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    left join public.product pp on pp.id = p.parent_product_id
    where c.reopened_at is null
  ),
  ns as (select * from public.so_backorder_notice_state((select array_agg(distinct b0.line_id) from bo b0))),   -- mail-1c: 알림 상태 · 때는 mail_backorder_line 에서(옛 so_line.backorder_notified_at 은 쓰지 않는다)
  base as (
    select t.*,
           ns.notified_at, ns.notified_state,                                                                         -- mail-1c: 509 계보 · 프리오더 null
           cu.name as customer_name,
           p.brand_id, p.brand_name,
           ps.supplier_id, su.name as supplier_name,
           ts.so_number as taken_by_so_number,
           (t.free_reason is not null) as owed,                                                                  -- 무상 줄 백오더 = 우리가 줄 것(판정 16 · 이어받기·만료 대상 아님)
           (public.ims_today() - t.order_date) as days_waiting,                                                  -- 기다린 날수(원래 주문일 기준 · 오래된 것을 매니저가 정리)
           cb.is_combo, cb.components,                                                                              -- asm-2b2: 콤보 줄 표시 · 구성품(sku · 이름 · combo_qty · base_sku)
           -- 입고됨(판정 6·7): 백오더가 생긴 뒤 그 창고에 po_in 또는 다른 창고에서 온 transfer_in(출발 줄이 있고 출발 창고 ≠ 도착 창고 · IN_TRANSIT 제외) · 조정·반품·조립 제외
           -- asm-2b2(⬜ 알림): 콤보는 「어느 구성품이든 자격 있는 입고가 있었다 ∧ 지금 통째 콤보가 1 개 이상 가용」 — 입고 사건이 있어야 하고(판정 6 · 반품 · 조정으로 생긴 가용은 세지 않는다) 반쪽 콤보로는 알리지 않는다(묶음 4)
           case when cb.is_combo then cb.arrived_any and coalesce(cb.avail_here, 0) >= 1 else exists (
             select 1 from public.inv_ledger g
             where g.sku = t.base_sku and g.warehouse = t.location_name and g.qty_delta > 0
               and g.occurred_on >= (t.backorder_since at time zone 'America/Toronto')::date
               and (g.event_type = 'po_in'
                    or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
                        and exists (select 1 from public.inv_ledger o
                                    where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                                      and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
           ) end as arrived,
           case when cb.is_combo then cb.avail_here else (v_avail->>(t.location_id::text || ':' || t.stock_pid::text))::numeric end as available_here,   -- asm-2b2: 콤보 가용 = min(구성품 가용 ÷ (combo_qty × pack_factor))
           case when cb.is_combo then cb.avail_other else (select jsonb_object_agg(wh.name, (v_avail->>(wh.id::text || ':' || t.stock_pid::text))::numeric)
              from public.ref_warehouse wh where wh.is_active and wh.id is distinct from t.location_id) end as available_other
    from bo t
    cross join lateral (                                                                                            -- asm-2b2: 콤보 줄의 구성품 · 콤보 단위 가용(이 창고 · 다른 창고) · 구성품 입고 사건
      select exists (select 1 from public.so_line cp where cp.combo_line_id = t.line_id) as is_combo,
             (select jsonb_agg(jsonb_build_object('sku', cp.sku, 'product_name', cp.product_name, 'combo_qty', cp.combo_qty, 'base_sku', coalesce(cpp.sku, cp2.sku)) order by cp.line_no)
                from public.so_line cp join public.product cp2 on cp2.id = cp.product_id left join public.product cpp on cpp.id = cp2.parent_product_id where cp.combo_line_id = t.line_id) as components,
             (select min(floor(coalesce((v_avail->>(t.location_id::text || ':' || coalesce(cp2.parent_product_id, cp2.id)::text))::numeric, 0) / (cp.combo_qty * cp.pack_factor)))
                from public.so_line cp join public.product cp2 on cp2.id = cp.product_id where cp.combo_line_id = t.line_id) as avail_here,
             (select jsonb_object_agg(wh.name, (select min(floor(coalesce((v_avail->>(wh.id::text || ':' || coalesce(cp2.parent_product_id, cp2.id)::text))::numeric, 0) / (cp.combo_qty * cp.pack_factor)))
                                                  from public.so_line cp join public.product cp2 on cp2.id = cp.product_id where cp.combo_line_id = t.line_id))
                from public.ref_warehouse wh where wh.is_active and wh.id is distinct from t.location_id) as avail_other,
             exists (select 1 from public.so_line cp join public.product cp2 on cp2.id = cp.product_id left join public.product cpp on cpp.id = cp2.parent_product_id
                       join public.inv_ledger g on g.sku = coalesce(cpp.sku, cp2.sku) and g.warehouse = t.location_name and g.qty_delta > 0
                                                 and g.occurred_on >= (t.backorder_since at time zone 'America/Toronto')::date
                                                 and (g.event_type = 'po_in'
                                                      or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
                                                          and exists (select 1 from public.inv_ledger o where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                                                                        and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
                      where cp.combo_line_id = t.line_id) as arrived_any
    ) cb
    join public.customer cu on cu.id = t.customer_id
    join public.product p on p.id = t.product_id
    left join public.product_supplier ps on ps.product_id = t.product_id and ps.is_default and ps.is_active
    left join public.supplier su on su.id = ps.supplier_id
    left join public.so ts on ts.id = t.taken_by_so_id
    left join ns on ns.line_id = t.line_id
  ),
  filtered as (
    select * from base b
    where (f->>'customer_id' is null or b.customer_id = (f->>'customer_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_id is null) or (f->>'supplier_id' <> 'none' and b.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or b.sku ilike (f->>'sku') || '%' or b.base_sku ilike (f->>'sku') || '%'
           or exists (select 1 from jsonb_array_elements(coalesce(b.components, '[]'::jsonb)) cj where cj->>'sku' ilike (f->>'sku') || '%' or cj->>'base_sku' ilike (f->>'sku') || '%'))   -- asm-2b2: 구성품 SKU 로도 콤보 백오더를 찾는다
      and (f->>'product_id'  is null or b.product_id = (f->>'product_id')::uuid)
      and (f->>'location_id' is null or b.location_id = (f->>'location_id')::uuid)
      and (f->>'store'       is null or b.store = f->>'store')                                                                        -- aone-bo-1: 스토어
      and (v_state = 'all' or b.state = v_state)
      and (f->>'end_kind'    is null or b.end_kind = f->>'end_kind')
      and (f->>'order_from'  is null or b.order_date >= (f->>'order_from')::date)
      and (f->>'order_to'    is null or b.order_date <= (f->>'order_to')::date)
      and (f->>'ended_from'  is null or (b.ended_at at time zone 'America/Toronto')::date >= (f->>'ended_from')::date)
      and (f->>'ended_to'    is null or (b.ended_at at time zone 'America/Toronto')::date <= (f->>'ended_to')::date)
      and (f->>'arrived'     is null or b.arrived = (f->>'arrived')::boolean)
      and (f->>'notified'    is null or (b.notified_at is not null) = (f->>'notified')::boolean)
      and (f->>'owed'        is null or b.owed = (f->>'owed')::boolean)
      and (v_kind is null or b.kind = v_kind)                                                                                 -- bo-pre-1 판정 351
  )
  select count(*), count(*) filter (where state = 'open'), count(*) filter (where state = 'ended'),
         count(*) filter (where state = 'open' and owed) as open_owed_n,
         count(*) filter (where state = 'open' and kind = 'backorder'), count(*) filter (where state = 'open' and kind = 'preorder'),   -- bo-pre-1 판정 351
         coalesce((select jsonb_agg(jsonb_build_object(
             'so_id', x.so_id, 'so_number', x.so_number, 'order_date', x.order_date, 'line_id', x.line_id,
             'customer_id', x.customer_id, 'customer_name', x.customer_name,
             'product_id', x.product_id, 'sku', x.sku, 'base_sku', x.base_sku, 'product_name', x.product_name, 'pack_factor', x.pack_factor,
             'brand_id', x.brand_id, 'brand_name', x.brand_name, 'supplier_id', x.supplier_id, 'supplier_name', x.supplier_name,
             'location_id', x.location_id, 'location_name', x.location_name, 'store', x.store,                                                   -- aone-bo-1: asung | aone | manual
             'qty_ordered', x.qty_ordered, 'qty_open', x.qty_open, 'backorder_since', x.backorder_since,
             'state', x.state, 'kind', x.kind, 'end_kind', x.end_kind, 'qty_taken', x.qty_taken, 'qty_unwanted', x.qty_unwanted,                   -- bo-pre-1 판정 351: kind
             'taken_by_so_id', x.taken_by_so_id, 'taken_by_so_number', x.taken_by_so_number, 'ended_at', x.ended_at,
             'notified_at', x.notified_at, 'notified_state', x.notified_state,
             'free_reason', x.free_reason, 'owed', x.owed, 'days_waiting', x.days_waiting,
             'arrived', x.arrived, 'available_here', x.available_here, 'available_other', x.available_other,
             'is_combo', x.is_combo, 'components', x.components)                                                   -- asm-2b2: 콤보 줄 하나로 선다(qty = 콤보 수) · 구성품은 여기에
           order by x.customer_name, x.customer_id, x.base_sku, x.order_date, x.so_number, x.line_id)
           from (select * from filtered order by customer_name, customer_id, base_sku, order_date, so_number, line_id limit v_limit offset v_offset) x), '[]'::jsonb)
    into v_total, v_open, v_ended, v_open_owed, v_open_bo, v_open_pre, v_rows
  from filtered;

  return jsonb_build_object(
    'total', v_total, 'open', v_open, 'ended', v_ended, 'open_owed', v_open_owed, 'open_backorder', v_open_bo, 'open_preorder', v_open_pre, 'limit', v_limit, 'offset', v_offset, 'filters', f,   -- bo-pre-1 판정 351
    'notify_tracking', 'ims — notified_state from IMS backorder mail (mail_backorder_line · split lines inherit their ancestor): queued · sent · unknown (request sent, no answer) · cancelled · failed (released, goes again next run) · not_sent · unknown_pre_ims (backorder made before the first IMS mail run of that warehouse — may have had a GAS mail); notified_at = sent time, or queued time while queued or unknown; pre-order rows are not notification-tracked: both null (ruling 499); filter notified = notified_at is not null',
    'arrived_rule', 'po_in or transfer_in from another warehouse (same doc transfer_out at a different, non-IN_TRANSIT warehouse) at the order warehouse since the backorder was made; adjustments, credits, assemblies and arrivals without a departure leg do not count; a combo row is arrived when any component had such an arrival and at least one whole combo is available at the order warehouse; pre-order rows (kind preorder, ruling 351) use the same rule counted from the pre-order reservation, are never expired or taken over (ruling 9), and only open pre-orders are listed (no ended record)',
    'rows', v_rows);
end;
$function$;

-- ═══ 5) so_backorder_arrivals — 기다리는 줄의 스토어 · 행 stores ═══
CREATE OR REPLACE FUNCTION public.so_backorder_arrivals(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['location_id','supplier_id','brand_id','sku','product_id','received_from','received_to','include_no_waiting','limit','offset','store'];
  v_bad    text;
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_from   date := coalesce((f->>'received_from')::date, case when f->>'received_to' is null then public.ims_today() - 30 end);
  v_to     date := (f->>'received_to')::date;
  v_all    boolean := coalesce((f->>'include_no_waiting')::boolean, false);
  v_wh     text;
  v_t0     timestamptz := clock_timestamp();
  v_out    jsonb;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3c(판정 583): 첫 줄 문 = Backorders 의 열쇠(sales 보기) · definer 라 product_supplier 정책을 지나므로 여기서 거른다 · 이 함수는 product_supplier 에서 supplier_id 만 읽는다(단가 · 공식 안 냄)
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if f->>'store' is not null and f->>'store' not in ('asung', 'aone', 'manual') then raise exception 'store must be asung, aone or manual (got %)', f->>'store'; end if;   -- aone-bo-1 판정 948 · 덧붙임 3: 스토어 거르기(so_store_of)
  if f->>'location_id' is not null then
    select w.name into v_wh from public.ref_warehouse w where w.id = (f->>'location_id')::uuid;
    if v_wh is null then raise exception 'Warehouse not found'; end if;
  end if;

  with ev as (                                                                                      -- 기간 안 입고 사건 → 재고 제품 · 창고 · 공급처
    select e.ledger_id, e.occurred_on, e.kind, e.doc_number, e.qty_delta,
           p.id as stock_pid, p.sku as psku, p.name as product_name, p.brand_id, p.brand_name,
           w.id as location_id, w.name as location_name,
           case when e.raw->>'po_id' is not null then (select po.supplier_id from public.po po where po.id = (e.raw->>'po_id')::uuid) end as po_supplier_id
    from public.inv_receipt_events(null, v_wh, v_from, v_to) e
    join public.product p on p.sku = e.sku and p.parent_product_id is null
    join public.ref_warehouse w on w.name = e.warehouse
  ),
  ev2 as (
    select ev.*, coalesce(ev.po_supplier_id, ps.supplier_id) as supplier_id,
           case when ev.po_supplier_id is not null then 'po' when ps.supplier_id is not null then 'product_default' end as supplier_basis
    from ev left join public.product_supplier ps on ps.product_id = ev.stock_pid and ps.is_default and ps.is_active
  ),
  grp as (
    select stock_pid, psku, product_name, brand_id, brand_name, location_id, location_name,
           sum(qty_delta) as received_base, count(*) as receipts_n, max(occurred_on) as last_received_on,
           (array_agg(supplier_id order by occurred_on desc, ledger_id desc))[1] as supplier_id,
           (array_agg(supplier_basis order by occurred_on desc, ledger_id desc))[1] as supplier_basis,
           array_agg(distinct supplier_id) filter (where supplier_id is not null) as supplier_ids,
           jsonb_agg(jsonb_build_object('occurred_on', occurred_on, 'kind', kind, 'doc_number', doc_number, 'qty_base', qty_delta, 'supplier_id', supplier_id, 'supplier_basis', supplier_basis) order by occurred_on desc, ledger_id desc) as receipts_all
    from ev2
    group by stock_pid, psku, product_name, brand_id, brand_name, location_id, location_name
  ),
  wait as (                                                                                        -- 열린 백오더 · 프리오더 수요 줄 → 기다리는 재고 제품(보통 줄 = 제 제품 · 콤보 줄 = 구성품마다)
    select y.stock_pid, s.location_id, s.customer_id, y.so_id, y.qty_base, public.so_store_of(s.intake, s.ref) as store,   -- aone-bo-1: 스토어
           (y.first_at at time zone 'America/Toronto')::date as first_on, s.order_date, s.so_number, y.line_no                                -- bo-2b: can_fill 순서(so_backorder_waiting 과 같다 — 오래 기다린 줄부터 · order_date · so_number · line_no)
    from (
      select l.id, l.so_id, l.line_no, coalesce(p.parent_product_id, p.id) as stock_pid, q.qty_open * l.pack_factor as qty_base, q.first_at
      from public.so_line l join public.product p on p.id = l.product_id
      cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, min(res.allocated_at) as first_at
                          from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                          where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind in ('backorder', 'preorder') and res.released_at is null) q
      where l.combo_line_id is null and q.qty_open is not null
      union all
      select l.id, l.so_id, l.line_no, coalesce(pp.parent_product_id, pp.id), q.qty_open * cp.combo_qty * cp.pack_factor, q.first_at
      from public.so_line l join public.so_line cp on cp.combo_line_id = l.id join public.product pp on pp.id = cp.product_id
      cross join lateral (select min(floor(res.qty_allocated / coalesce(c2.combo_qty, 1))) as qty_open, min(res.allocated_at) as first_at
                          from public.so_reserve res join public.so_line c2 on c2.id = res.so_line_id
                          where (c2.id = l.id or c2.combo_line_id = l.id) and res.kind in ('backorder', 'preorder') and res.released_at is null) q
      where l.combo_line_id is null and q.qty_open is not null
    ) y join public.so s on s.id = y.so_id
    where (f->>'store' is null or public.so_store_of(s.intake, s.ref) = f->>'store')                                                  -- aone-bo-1: 기다리는 줄을 스토어로 거른다(same/other · can_fill 도 그 스토어 몫만)
  ),
  base as (
    select g.*,
           (select count(distinct w.customer_id) from wait w where w.stock_pid = g.stock_pid and w.location_id = g.location_id) as same_customers,
           (select count(*) from wait w where w.stock_pid = g.stock_pid and w.location_id = g.location_id) as same_lines,
           (select array_agg(distinct w.store order by w.store) from wait w where w.stock_pid = g.stock_pid and w.location_id = g.location_id) as same_stores,   -- aone-bo-1
           (select coalesce(sum(w.qty_base), 0) from wait w where w.stock_pid = g.stock_pid and w.location_id = g.location_id) as same_qty_base,
           (select count(distinct w.customer_id) from wait w where w.stock_pid = g.stock_pid and w.location_id is distinct from g.location_id) as other_customers,
           (select count(*) from wait w where w.stock_pid = g.stock_pid and w.location_id is distinct from g.location_id) as other_lines,
           (select coalesce(sum(w.qty_base), 0) from wait w where w.stock_pid = g.stock_pid and w.location_id is distinct from g.location_id) as other_qty_base
    from grp g
  ),
  filtered as (
    select * from base b
    where (v_all or b.same_lines + b.other_lines > 0)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_ids is null) or (f->>'supplier_id' <> 'none' and (f->>'supplier_id')::uuid = any(coalesce(b.supplier_ids, '{}'::uuid[]))))
      and (f->>'brand_id'   is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'        is null or b.psku ilike (f->>'sku') || '%')
      and (f->>'product_id' is null or b.stock_pid = (f->>'product_id')::uuid)
  ),
  page as (
    select * from filtered order by same_qty_base desc, last_received_on desc, psku limit v_limit offset v_offset
  ),
  avail as (                                                                                       -- bo-2b: 가용은 창고마다 한 번(쪽의 재고 제품을 배열로) — 행마다 부르면 200 행에 16.8 초(실측)
    select lw.location_id, b.stock_pid, coalesce(b.qty_ea, 0) - coalesce(b.sales_alloc_ea, 0) - coalesce(b.transfer_alloc_ea, 0) as avail
    from (select pg.location_id, array_agg(distinct pg.stock_pid) as pids from page pg group by pg.location_id) lw
    cross join lateral public.inv_available_base(lw.location_id, lw.pids) b
  ),
  cf as (                                                                                          -- bo-2b: can_fill_now_base 를 집합으로(기다리는 같은 창고 줄이 있는 행만 · 규칙 = so_backorder_waiting · 오래 기다린 줄부터 가용을 나눈다)
    select z.stock_pid, z.location_id, sum(least(z.qty_base, greatest(z.avail - z.before_base, 0))) as can_fill_base
    from (select w.stock_pid, w.location_id, w.qty_base, coalesce(a.avail, 0) as avail,                                                     -- bo-2b: 잔고 행이 없는 제품은 inv_available_base 가 행을 안 낸다 → 가용 0
                 coalesce(sum(w.qty_base) over (partition by w.stock_pid, w.location_id order by w.first_on asc, w.order_date, w.so_number, w.line_no rows between unbounded preceding and 1 preceding), 0) as before_base
          from wait w left join avail a on a.stock_pid = w.stock_pid and a.location_id = w.location_id) z
    group by z.stock_pid, z.location_id
  )
  select jsonb_build_object(
    'total', (select count(*) from filtered), 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'period_from', v_from, 'period_to', v_to, 'include_no_waiting', v_all,
    'supplier_rule', 'per receipt: raw.po_id → po.supplier_id (basis po, IMS receipts) else the product''s default supplier (basis product_default, Cin7-era receipts) — ruling 482 · row supplier = the latest receipt''s · the supplier filter matches any receipt in the period',
    'waiting_rule', 'open backorder and pre-order demand lines waiting for this stock product (a combo line waits through its components) · same = order warehouse is the receipt warehouse · other = another warehouse (ruling 488: shown too, needs a transfer or a warehouse change before it can proceed) · rows with no waiting line are left out unless include_no_waiting',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'product_id', p.stock_pid, 'sku', p.psku, 'product_name', p.product_name, 'brand_id', p.brand_id, 'brand_name', p.brand_name,
        'supplier_id', p.supplier_id, 'supplier_name', (select s.name from public.supplier s where s.id = p.supplier_id), 'supplier_basis', p.supplier_basis,
        'location_id', p.location_id, 'location_name', p.location_name,
        'received_base', p.received_base, 'receipts_n', p.receipts_n, 'last_received_on', p.last_received_on,
        'receipts', (select coalesce(jsonb_agg(r), '[]'::jsonb) from (select r from jsonb_array_elements(p.receipts_all) r limit 20) z), 'receipts_truncated', p.receipts_n > 20,
        'available_now_base', coalesce((select a.avail from avail a where a.stock_pid = p.stock_pid and a.location_id = p.location_id), 0),                        -- bo-2b
        'waiting_same_location', jsonb_build_object('customers', p.same_customers, 'lines', p.same_lines, 'qty_base', p.same_qty_base),
        'stores', to_jsonb(coalesce(p.same_stores, '{}'::text[])),                                                                                   -- aone-bo-1: 이 창고에서 기다리는 줄의 스토어(asung · aone · manual)
        'waiting_other_locations', jsonb_build_object('customers', p.other_customers, 'lines', p.other_lines, 'qty_base', p.other_qty_base),
        'can_fill_now_base', case when p.same_lines > 0 then coalesce((select c.can_fill_base from cf c where c.stock_pid = p.stock_pid and c.location_id = p.location_id), 0) else 0 end)   -- bo-2b
      order by p.same_qty_base desc, p.last_received_on desc, p.psku) from page p), '[]'::jsonb),
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000))
  into v_out;
  return v_out;
end;
$function$;

-- ═══ 6) so_backorder_ready — so 조인 · 거르기 · 행 store(can_fill 은 창고 전체 셈 그대로) ═══
CREATE OR REPLACE FUNCTION public.so_backorder_ready(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['location_id','supplier_id','brand_id','sku','product_id','kind','limit','offset','store'];
  v_bad    text;
  v_kind   text := nullif(f->>'kind', '');
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_t0     timestamptz := clock_timestamp();
  v_out    jsonb;
begin
  if not public.ims_can_view('sales') then raise exception 'Backorders needs the sales permission — nothing was read'; end if;   -- mail-1b 이견 1: definer 로 바꾸며 첫 줄(Backorders 화면 = sales · ims-auth.js:81)
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if f->>'store' is not null and f->>'store' not in ('asung', 'aone', 'manual') then raise exception 'store must be asung, aone or manual (got %)', f->>'store'; end if;   -- aone-bo-1 판정 948 · 덧붙임 3: 스토어 거르기(so_store_of)
  if v_kind is not null and v_kind not in ('backorder', 'preorder') then raise exception 'kind must be backorder or preorder'; end if;

  with ln as (select * from public.so_backorder_fill((f->>'location_id')::uuid, 'screen')),   -- mail-1b: 셈(ln · ent · avail · share · per_line)은 속 함수 하나로 옮겼다(바이트 그대로 · screen = 지금 셈)
  rows_ as (
    select ln.*,
           sp.sku as stock_sku, sp.name as stock_name,
           (public.ims_today() - ln.first_on) as days_waiting,
           cu.name as customer_name, cc.name as contact_name, cc.email as contact_email, cc.phone as contact_phone, cc.mobile_phone as contact_mobile,
           ps.supplier_id,
           public.so_store_of(so_.intake, so_.ref) as store,                                                                            -- aone-bo-1: 스토어
           (select count(*) from public.so_line o
             where o.so_id = ln.so_id and o.combo_line_id is null and o.id <> ln.line_id
               and exists (select 1 from public.so_reserve r2 join public.so_line cp2 on cp2.id = r2.so_line_id
                           where (cp2.id = o.id or cp2.combo_line_id = o.id) and r2.kind in ('backorder', 'preorder') and r2.released_at is null)) as order_other_skus
    from ln
    join public.so so_ on so_.id = ln.so_id                                                                                             -- aone-bo-1: intake · ref
    join public.product sp on sp.id = ln.stock_pid
    join public.customer cu on cu.id = ln.customer_id
    left join public.customer_contact cc on cc.customer_id = cu.id and cc.is_default and cc.is_active
    left join public.product_supplier ps on ps.product_id = ln.stock_pid and ps.is_default and ps.is_active
    where ln.can_fill_units > 0
  ),
  filtered as (
    select * from rows_ r
    where (f->>'location_id' is null or r.location_id = (f->>'location_id')::uuid)
      and (f->>'store'       is null or r.store = f->>'store')                                                                        -- aone-bo-1(can_fill 은 창고 전체 셈 그대로)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and r.supplier_id is null) or (f->>'supplier_id' <> 'none' and r.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or r.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or r.sku ilike (f->>'sku') || '%' or r.stock_sku ilike (f->>'sku') || '%'
           or exists (select 1 from jsonb_array_elements(coalesce(r.components, '[]'::jsonb)) j where j->>'sku' ilike (f->>'sku') || '%'))
      and (f->>'product_id'  is null or r.stock_pid = (f->>'product_id')::uuid or r.product_id = (f->>'product_id')::uuid)
      and (v_kind is null or r.kind = v_kind)
  )
  select jsonb_build_object(
    'as_of', public.ims_today(), 'filters', f, 'limit', v_limit, 'offset', v_offset,
    'total', count(*), 'orders', count(distinct so_id),
    'can_fill_basis', 'preview only — open backorder and pre-order lines of confirmed orders whose own warehouse has stock now: available_now_base (EA) shared longest wait first per stock product and warehouse (same rule as so_backorder_waiting); a combo line needs every component (whole combos); so_backorder_proceed re-computes per order at the moment it runs',
    'proceed_note', 'so_backorder_proceed takes the whole order: every open backorder and pre-order line of that order is sent to the engine, not only this line (proceed_moves_other_skus) · independent of receipts (ruling 490) — stock may come from adjustments, returns, cancelled orders or counts',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'kind', r.kind, 'so_id', r.so_id, 'so_number', r.so_number, 'so_status', r.status, 'can_proceed', true, 'order_date', r.order_date,
        'customer_id', r.customer_id, 'customer_name', r.customer_name, 'contact_name', r.contact_name, 'contact_email', r.contact_email, 'contact_phone', r.contact_phone, 'contact_mobile', r.contact_mobile,
        'line_id', r.line_id, 'line_no', r.line_no, 'sku', r.sku, 'product_name', r.product_name, 'via_combo', false, 'is_combo', r.is_combo, 'pack_factor', r.pack_factor, 'base_per_unit', r.pack_factor,
        'qty_ordered', r.qty_ordered, 'qty_open', r.qty_open, 'qty_base', r.qty_open * r.pack_factor, 'unit_price', r.unit_price, 'amount', r.qty_open * r.unit_price, 'free_reason', r.free_reason, 'owed', r.free_reason is not null,
        'first_reserved_at', r.first_at, 'days_waiting', r.days_waiting,
        'same_location', true, 'location_id', r.location_id, 'location_name', r.location_name, 'store', r.store,                      -- aone-bo-1
        'order_other_skus', r.order_other_skus, 'proceed_moves_other_skus', r.order_other_skus > 0,
        'can_fill_base', r.can_fill_units * r.pack_factor, 'can_fill_units', r.can_fill_units,
        'product_id', r.stock_pid, 'stock_sku', r.stock_sku, 'stock_name', r.stock_name, 'brand_id', r.brand_id, 'supplier_id', r.supplier_id,
        'available_now_base', r.avail_units * r.pack_factor, 'available_now_units', r.avail_units, 'arrived_in_period', r.arrived_in_period, 'components', r.components)
      order by r.days_waiting desc, r.order_date, r.so_number, r.line_no)
      from (select * from filtered order by days_waiting desc, order_date, so_number, line_no limit v_limit offset v_offset) r), '[]'::jsonb),
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000))
  into v_out
  from filtered;
  return v_out;
end;
$function$;

-- ═══ 7) so_backorder_demand — line 에 store · 거르기(seed · line) · 줄/행 store ═══
CREATE OR REPLACE FUNCTION public.so_backorder_demand(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','order_from','order_to','ended_from','ended_to','open','flagged','limit','offset','currency','store'];   -- bo-1c: + currency
  v_bad    text;
  v_limit  int := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_out    jsonb;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3c(판정 583): 첫 줄 문 = Backorders 의 열쇠(sales 보기) · definer 라 product_supplier 정책을 지나므로 여기서 거른다 · 이 함수는 product_supplier 에서 supplier_id 만 읽는다(단가 · 공식 안 냄)
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if f->>'store' is not null and f->>'store' not in ('asung', 'aone', 'manual') then raise exception 'store must be asung, aone or manual (got %)', f->>'store'; end if;   -- aone-bo-1 판정 948 · 덧붙임 3: 스토어 거르기(so_store_of)

  with recursive
  seed as (                                                                                        -- 백오더가 한 번이라도 있었던 수요 줄
    select l.id
    from public.so_line l join public.so s on s.id = l.so_id
    where l.combo_line_id is null and l.free_reason is null and s.channel = 'warehouse' and not public.so_demand_so_excluded(s.id)
      and (f->>'store' is null or public.so_store_of(s.intake, s.ref) = f->>'store')                                                      -- aone-bo-1: 스토어
      and (exists (select 1 from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id
                   where (cp.id = l.id or cp.combo_line_id = l.id) and r.kind = 'backorder')
           or exists (select 1 from public.so_backorder_close c where c.so_line_id = l.id))
  ),
  edge as (                                                                                        -- 연결 셋(양방향)
    select e.a, e.b from (
      select l.split_from_line_id as a, l.id as b from public.so_line l where l.split_from_line_id is not null
      union all select c.so_line_id, c.taken_by_line_id from public.so_backorder_close c where c.taken_by_line_id is not null and c.reopened_at is null
      union all select m.from_line_id, m.line_id from public.so_line_merge_source m
    ) e
    union
    select e.b, e.a from (
      select l.split_from_line_id as a, l.id as b from public.so_line l where l.split_from_line_id is not null
      union all select c.so_line_id, c.taken_by_line_id from public.so_backorder_close c where c.taken_by_line_id is not null and c.reopened_at is null
      union all select m.from_line_id, m.line_id from public.so_line_merge_source m
    ) e
  ),
  reach (seed_id, id) as (
    select s.id, s.id from seed s
    union
    select r.seed_id, e.b from reach r join edge e on e.a = r.id
  ),
  comp_of_seed as (select r.seed_id, min(r.id::text)::uuid as comp_id from reach r group by r.seed_id),   -- min(uuid) 집계가 없다 → text 로
  node as (select distinct r.id, cs.comp_id from reach r join comp_of_seed cs on cs.seed_id = r.seed_id),
  line as (                                                                                        -- 덩어리의 수요 줄 + 줄 셈 + 활성 표식
    select n.comp_id, l.id as line_id, l.so_id, s.so_number, s.channel, s.customer_id, s.location_id, s.location_name, s.order_date,
           l.line_no, l.product_id, l.sku, l.product_name, l.pack_factor,
           coalesce(p.parent_product_id, p.id) as stock_pid,
           d.*,
           fl.id as flag_id, fl.reason as flag_reason, fl.note as flag_note, fl.flagged_at, fl.flagged_by,
           case when fl.id is not null then d.lost else 0 end as flagged_qty,
           public.so_store_of(s.intake, s.ref) as store,                                                                                      -- aone-bo-1
           l.unit_price, s.currency_code,                                                                                                    -- bo-1c: 할인 뒤 단가(so_line.unit_price 주석 「할인 뒤 단가」 · null = 가격 없음) · 오더 통화
           d.demand * l.unit_price as demand_amount, d.sold * l.unit_price as sold_amount, d.lost * l.unit_price as lost_amount,            -- bo-1c: 금액 = 그 몫 × 그 줄의 단가(세금 · 운임 · 오더 할인 · 쿠폰 제외) · 단가 null 이면 null
           d.lost_unwanted * l.unit_price as lost_unwanted_amount, d.lost_expired * l.unit_price as lost_expired_amount,
           d.lost_cancelled * l.unit_price as lost_cancelled_amount, d.lost_removed * l.unit_price as lost_removed_amount,
           d.in_progress * l.unit_price as in_progress_amount, d.open_backorder * l.unit_price as open_backorder_amount,
           case when fl.id is not null then d.lost else 0 end * l.unit_price as flagged_amount,
           (select max(c.ended_at) from public.so_backorder_close c where c.so_line_id = l.id and c.reopened_at is null) as last_ended_at
    from node n
    join public.so_line l on l.id = n.id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    cross join lateral public.so_demand_line(l.id) d
    left join public.so_demand_flag fl on fl.active_line_id = l.id
    where l.combo_line_id is null and l.free_reason is null and s.channel = 'warehouse' and not public.so_demand_so_excluded(s.id)
      and (f->>'store' is null or public.so_store_of(s.intake, s.ref) = f->>'store')                                                      -- aone-bo-1: 스토어
  ),
  grp as (
    select x.comp_id,
           (array_agg(x.customer_id order by x.order_date, x.so_number, x.line_no))[1] as customer_id,
           (array_agg(x.stock_pid   order by x.order_date, x.so_number, x.line_no))[1] as stock_pid,
           (array_agg(x.location_id order by x.order_date, x.so_number, x.line_no))[1] as location_id,
           (array_agg(x.location_name order by x.order_date, x.so_number, x.line_no))[1] as location_name,
           (array_agg(x.store order by x.order_date, x.so_number, x.line_no))[1] as store,                                                   -- aone-bo-1
           count(distinct x.customer_id) as customer_n, count(distinct x.stock_pid) as product_n,
           min(x.order_date) as first_order_date, max(x.last_ended_at) as last_ended_at,
           count(*) as line_n,
           sum(x.demand) as demand_raw, sum(x.sold) as sold, sum(x.lost) as lost_raw, sum(x.in_progress) as in_progress, sum(x.open_backorder) as open_backorder,
           sum(x.flagged_qty) as flagged,
           sum(x.lost_unwanted) as lost_unwanted, sum(x.lost_expired) as lost_expired, sum(x.lost_cancelled) as lost_cancelled, sum(x.lost_removed) as lost_removed,
           sum(x.in_progress) filter (where x.so_status = 'draft') as ip_draft,
           sum(x.in_progress) filter (where x.so_status = 'confirmed') as ip_confirmed,
           sum(x.in_progress) filter (where x.so_status in ('at_wms', 'picking', 'packed')) as ip_warehouse,
           sum(x.in_progress) filter (where x.so_status not in ('draft', 'confirmed', 'at_wms', 'picking', 'packed')) as ip_other,
           count(*) filter (where x.flag_id is not null) as flagged_lines,
           sum(x.ordered) as ordered, sum(x.transferred) as transferred,                                                                     -- bo-1c: demand_raw = ordered − transferred
           sum(x.demand_amount) as demand_amount_raw, sum(x.sold_amount) as sold_amount, sum(x.lost_amount) as lost_amount_raw,              -- bo-1c: 금액 합(단가 있는 줄만 · sum 은 null 을 건너뛴다)
           sum(x.lost_unwanted_amount) as lost_unwanted_amount, sum(x.lost_expired_amount) as lost_expired_amount,
           sum(x.lost_cancelled_amount) as lost_cancelled_amount, sum(x.lost_removed_amount) as lost_removed_amount,
           sum(x.in_progress_amount) as in_progress_amount, sum(x.open_backorder_amount) as open_backorder_amount, sum(x.flagged_amount) as flagged_amount,
           count(*) filter (where x.unit_price is null) as price_missing,                                                                    -- bo-1c: 가격 없는 줄 수(그 줄의 금액은 합에 없다)
           count(distinct x.currency_code) as currency_n, min(x.currency_code) as currency,                                                 -- bo-1c: 통화가 섞이면 currency_n > 1(합치지 않는다 — 화면이 가른다)
           jsonb_agg(jsonb_build_object(
             'line_id', x.line_id, 'so_id', x.so_id, 'so_number', x.so_number, 'so_status', x.so_status, 'order_date', x.order_date, 'line_no', x.line_no,
             'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'pack_factor', x.pack_factor, 'location_name', x.location_name, 'store', x.store,   -- aone-bo-1
             'ordered', x.ordered, 'sold', x.sold, 'removed', x.removed, 'transferred', x.transferred, 'demand', x.demand,
             'lost', x.lost, 'lost_by', jsonb_build_object('unwanted', x.lost_unwanted, 'expired', x.lost_expired, 'cancelled', x.lost_cancelled, 'removed', x.lost_removed),
             'in_progress', x.in_progress, 'open_backorder', x.open_backorder, 'end_kinds', x.end_kinds, 'last_ended_at', x.last_ended_at,
             'unit_price', x.unit_price, 'currency', x.currency_code,                                                                      -- bo-1c
             'amount', jsonb_build_object('demand', x.demand_amount, 'sold', x.sold_amount, 'lost', x.lost_amount, 'in_progress', x.in_progress_amount, 'open_backorder', x.open_backorder_amount, 'flagged', x.flagged_amount),
             'flag', case when x.flag_id is null then null else jsonb_build_object('id', x.flag_id, 'reason', x.flag_reason, 'note', x.flag_note, 'flagged_at', x.flagged_at, 'flagged_by', x.flagged_by, 'qty', x.flagged_qty) end
           ) order by x.order_date, x.so_number, x.line_no) as lines,
           array_agg(distinct x.so_number) as so_numbers
    from line x
    group by x.comp_id
  ),
  base as (
    select g.*, cu.name as customer_name, sp.id as product_id, sp.sku as stock_sku, sp.name as stock_name, sp.brand_id, sp.brand_name,
           ps.supplier_id, su.name as supplier_name,
           g.demand_raw - g.flagged as demand_then, g.lost_raw - g.flagged as lost
           , g.demand_amount_raw - coalesce(g.flagged_amount, 0) as demand_amount, g.lost_amount_raw - coalesce(g.flagged_amount, 0) as lost_amount   -- bo-1c: 표식 몫은 금액에서도 함께 뺀다
    from grp g
    join public.customer cu on cu.id = g.customer_id
    join public.product sp on sp.id = g.stock_pid
    left join public.product_supplier ps on ps.product_id = sp.id and ps.is_default and ps.is_active
    left join public.supplier su on su.id = ps.supplier_id
  ),
  filtered as (
    select * from base b
    where (f->>'customer_id' is null or b.customer_id = (f->>'customer_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_id is null) or (f->>'supplier_id' <> 'none' and b.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or b.stock_sku ilike (f->>'sku') || '%' or exists (select 1 from jsonb_array_elements(b.lines) j where j->>'sku' ilike (f->>'sku') || '%'))
      and (f->>'product_id'  is null or b.product_id = (f->>'product_id')::uuid or exists (select 1 from jsonb_array_elements(b.lines) j where (j->>'product_id')::uuid = (f->>'product_id')::uuid))
      and (f->>'location_id' is null or b.location_id = (f->>'location_id')::uuid)
      and (f->>'order_from'  is null or b.first_order_date >= (f->>'order_from')::date)
      and (f->>'order_to'    is null or b.first_order_date <= (f->>'order_to')::date)
      and (f->>'ended_from'  is null or (b.last_ended_at at time zone 'America/Toronto')::date >= (f->>'ended_from')::date)
      and (f->>'ended_to'    is null or (b.last_ended_at at time zone 'America/Toronto')::date <= (f->>'ended_to')::date)
      and (f->>'open'        is null or (b.open_backorder > 0) = (f->>'open')::boolean)
      and (f->>'flagged'     is null or (b.flagged_lines > 0) = (f->>'flagged')::boolean)
      and (f->>'currency'    is null or b.currency = f->>'currency')                                                                         -- bo-1c
  )
  select jsonb_build_object(
    'total', count(*), 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'sums', jsonb_build_object('demand_then', coalesce(sum(demand_then), 0), 'sold', coalesce(sum(sold), 0), 'lost', coalesce(sum(lost), 0),
                               'in_progress', coalesce(sum(in_progress), 0), 'open_backorder', coalesce(sum(open_backorder), 0), 'flagged', coalesce(sum(flagged), 0)),
    'identity', 'demand_then = sold + lost + in_progress + open_backorder (after flags) · demand_then = Σ(ordered − transferred) − flagged · lost = unwanted + expired + cancelled(ledger + cancelled-order remainder) + removed − flagged',
    'amount_sums', jsonb_build_object('demand_amount', coalesce(sum(demand_amount), 0), 'sold_amount', coalesce(sum(sold_amount), 0), 'lost_amount', coalesce(sum(lost_amount), 0),                          -- bo-1c
                                      'in_progress_amount', coalesce(sum(in_progress_amount), 0), 'open_backorder_amount', coalesce(sum(open_backorder_amount), 0), 'flagged_amount', coalesce(sum(flagged_amount), 0),
                                      'price_missing', coalesce(sum(price_missing), 0), 'currencies', (select coalesce(jsonb_agg(distinct currency), '[]'::jsonb) from filtered)),
    'amount_rule', 'amount = qty × so_line.unit_price (discounted unit price; tax, freight, order discount and coupon excluded) · unit_price null = price missing (counted in price_missing, left out of the sums) · a cluster with currency_n > 1 mixes currencies',
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'comp_id', x.comp_id, 'customer_id', x.customer_id, 'customer_name', x.customer_name,
        'product_id', x.product_id, 'sku', x.stock_sku, 'product_name', x.stock_name, 'brand_id', x.brand_id, 'brand_name', x.brand_name,
        'supplier_id', x.supplier_id, 'supplier_name', x.supplier_name, 'location_id', x.location_id, 'location_name', x.location_name, 'store', x.store,   -- aone-bo-1
        'first_order_date', x.first_order_date, 'last_ended_at', x.last_ended_at, 'so_numbers', to_jsonb(x.so_numbers), 'line_n', x.line_n,
        'demand_then', x.demand_then, 'sold', x.sold, 'lost', x.lost, 'in_progress', x.in_progress, 'open_backorder', x.open_backorder, 'flagged', x.flagged,
        'demand_raw', x.demand_raw, 'lost_raw', x.lost_raw,
        'lost_by', jsonb_build_object('unwanted', x.lost_unwanted, 'expired', x.lost_expired, 'cancelled', x.lost_cancelled, 'removed', x.lost_removed),
        'in_progress_by', jsonb_build_object('draft', coalesce(x.ip_draft, 0), 'confirmed', coalesce(x.ip_confirmed, 0), 'warehouse', coalesce(x.ip_warehouse, 0), 'other', coalesce(x.ip_other, 0)),
        'flagged_lines', x.flagged_lines, 'customer_n', x.customer_n, 'product_n', x.product_n, 'lines', x.lines,
        'ordered', x.ordered, 'transferred', x.transferred,                                                                                   -- bo-1c: demand_raw = ordered − transferred · demand_then = demand_raw − flagged
        'demand_amount', x.demand_amount, 'sold_amount', x.sold_amount, 'lost_amount', x.lost_amount, 'in_progress_amount', x.in_progress_amount, 'open_backorder_amount', x.open_backorder_amount,
        'flagged_amount', coalesce(x.flagged_amount, 0), 'demand_amount_raw', x.demand_amount_raw, 'lost_amount_raw', x.lost_amount_raw,
        'lost_amount_by', jsonb_build_object('unwanted', x.lost_unwanted_amount, 'expired', x.lost_expired_amount, 'cancelled', x.lost_cancelled_amount, 'removed', x.lost_removed_amount),
        'price_missing', x.price_missing, 'currency', x.currency, 'currency_n', x.currency_n)
      order by x.customer_name, x.customer_id, x.stock_sku, x.first_order_date, x.comp_id)
      from (select * from filtered order by customer_name, customer_id, stock_sku, first_order_date, comp_id limit v_limit offset v_offset) x), '[]'::jsonb))
  into v_out
  from filtered;
  return v_out;
end;
$function$;

-- ═══ 8) so_backorder_overview — 분모(ordered) 거르기 · 분자는 demand 로 같은 f ═══
CREATE OR REPLACE FUNCTION public.so_backorder_overview(p_filters jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','order_from','order_to','ended_from','ended_to','open','flagged','limit','offset','currency','sort','store'];
  c_sorts  constant text[] := array['lost_amount','lost','demand_then','open_backorder','customers_waiting','repeat_asks','days_waiting_max'];
  v_bad    text;
  v_sort   text := coalesce(nullif(f->>'sort', ''), 'lost_amount');
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_d      jsonb;
  v_d2     jsonb;                                                                                   -- 판정 486: 분자 재료(기간 열쇠를 뺀 덩어리 전부 · 몫마다 제 날짜로 거른다)
  v_from   date := coalesce((f->>'order_from')::date, (f->>'ended_from')::date);
  v_to     date := coalesce((f->>'order_to')::date, (f->>'ended_to')::date);
  v_wh     text;
  v_t0     timestamptz := clock_timestamp();
  v_out    jsonb;
begin
  if not public.ims_can_view('sales') then raise exception 'You cannot view sales data — ask an admin to add the ''sales'' permission — nothing was read'; end if;   -- rls-3c(판정 583): 첫 줄 문 = Backorders 의 열쇠(sales 보기) · definer 라 product_supplier 정책을 지나므로 여기서 거른다 · 이 함수는 product_supplier 에서 supplier_id 만 읽는다(단가 · 공식 안 냄)
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if f->>'store' is not null and f->>'store' not in ('asung', 'aone', 'manual') then raise exception 'store must be asung, aone or manual (got %)', f->>'store'; end if;   -- aone-bo-1 판정 948 · 덧붙임 3: 스토어 거르기(so_store_of)
  if v_sort <> all (c_sorts) then raise exception 'sort must be one of %', array_to_string(c_sorts, ', '); end if;
  if f->>'location_id' is not null then select w.name into v_wh from public.ref_warehouse w where w.id = (f->>'location_id')::uuid; end if;
  v_d := public.so_backorder_demand((f - 'sort' - 'limit' - 'offset') || '{"limit": 1000, "offset": 0}'::jsonb);        -- 수요는 정본 하나에서(덩어리 전부 · 상한 1000)
  if v_from is null and v_to is null then v_d2 := v_d;
  else v_d2 := public.so_backorder_demand((f - 'sort' - 'limit' - 'offset' - 'order_from' - 'order_to' - 'ended_from' - 'ended_to') || '{"limit": 1000, "offset": 0}'::jsonb);   -- 판정 486: 분자 재료는 기간 없이 · 몫마다 거른다
  end if;

  with cl as (
    select r.value as r, (r.value->>'product_id')::uuid as product_id, (r.value->>'customer_id')::uuid as customer_id,
           (r.value->>'open_backorder')::numeric as open_bo, (r.value->>'first_order_date')::date as first_order_date
    from jsonb_array_elements(v_d->'rows') r
  ),
  ln as (                                                                                           -- ③ 덩어리의 줄(repeat_asks 의 재료)
    select c.product_id, (j->>'line_id')::uuid as line_id, (j->>'unit_price')::numeric as unit_price
    from cl c cross join lateral jsonb_array_elements(c.r->'lines') j
  ),
  cl2 as (                                                                                          -- 판정 486: 분자 재료 덩어리(기간 열쇠 없이)
    select r.value as r, (r.value->>'comp_id')::uuid as comp_id, (r.value->>'demand_then')::numeric as demand_then, (r.value->>'demand_amount')::numeric as demand_amount
    from jsonb_array_elements(v_d2->'rows') r
  ),
  ln2 as (
    select c.comp_id, (j->>'line_id')::uuid as line_id, (j->>'unit_price')::numeric as unit_price, (j->'flag') is not null and jsonb_typeof(j->'flag') <> 'null' as flagged,
           (j->'lost_by'->>'cancelled')::numeric as lost_cancelled
    from cl2 c cross join lateral jsonb_array_elements(c.r->'lines') j
  ),
  piece as (                                                                                        -- 판정 486 v3: 잃은 몫마다 제 날짜(토론토) · 표식 줄은 뺀다
    select n.line_id, n.unit_price, c.end_kind as kind,
           case c.end_kind when 'superseded' then c.qty_unwanted when 'expired' then c.qty_open when 'cancelled' then c.qty_open else 0 end as qty,
           (c.ended_at at time zone 'America/Toronto')::date as on_date
    from ln2 n join public.so_backorder_close c on c.so_line_id = n.line_id and c.reopened_at is null
    where not n.flagged and c.end_kind in ('superseded', 'expired', 'cancelled')
    union all
    select n.line_id, n.unit_price, 'removed', l.qty_removed, (l.removed_at at time zone 'America/Toronto')::date                      -- 475: 마무리(so_finalize)가 찍은 removed_at
    from ln2 n join public.so_line l on l.id = n.line_id where not n.flagged and l.qty_removed > 0
    union all
    select n.line_id, n.unit_price, 'cancelled',                                                                                        -- 476 · 483: 취소 오더의 남은 몫 = 줄의 lost_cancelled − 장부 cancelled 행 · 날짜 so.closed_at
           n.lost_cancelled - coalesce((select sum(c.qty_open) from public.so_backorder_close c where c.so_line_id = n.line_id and c.reopened_at is null and c.end_kind = 'cancelled'), 0),
           (s.closed_at at time zone 'America/Toronto')::date
    from ln2 n join public.so_line l on l.id = n.line_id join public.so s on s.id = l.so_id where not n.flagged and s.status = 'cancelled'
  ),
  piece_p as (
    select * from piece p where p.qty > 0 and (v_from is null or p.on_date >= v_from) and (v_to is null or p.on_date <= v_to)
  ),
  reorder_so as (                                                                                   -- 판정 487: 다시 주문 오더 = 이어받은 새 오더 · 병합의 새 오더
    select c.taken_by_so_id as so_id from public.so_backorder_close c where c.reopened_at is null and c.taken_by_so_id is not null
    union select s.merged_into_id from public.so s where s.merged_into_id is not null
  ),
  bo_line as (                                                                                      -- 판정 487: 줄의 첫 백오더 예약 · 다시 주문 오더(와 split 자손)의 줄 · 백오더가 있던 줄의 split 자손 줄은 0 · 축 = 첫 예약 allocated_at(토론토)
    select n.comp_id, n.unit_price, case when ro.is_reorder or an.had_bo or n.flagged then 0 else coalesce(fr.qty, 0) end as bo_qty, fr.on_date   -- bo-2b 판정 491: 표식 줄은 「백오더가 된 금액」에서도 0
    from ln2 n
    join public.so_line l on l.id = n.line_id
    cross join lateral (
      with recursive up as (select s.id, s.split_from_id from public.so s where s.id = l.so_id
                            union all select s.id, s.split_from_id from public.so s join up on s.id = up.split_from_id)
      select exists (select 1 from up u join reorder_so x on x.so_id = u.id) as is_reorder
    ) ro
    cross join lateral (
      with recursive anc as (select x.id, x.split_from_line_id from public.so_line x where x.id = l.split_from_line_id
                             union all select x.id, x.split_from_line_id from public.so_line x join anc on x.id = anc.split_from_line_id)
      select exists (select 1 from anc a join public.so_line cp on (cp.id = a.id or cp.combo_line_id = a.id) join public.so_reserve r on r.so_line_id = cp.id and r.kind = 'backorder') as had_bo
    ) an
    cross join lateral (
      select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty, (min(res.allocated_at) at time zone 'America/Toronto')::date as on_date
      from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
      where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind = 'backorder'
        and res.allocated_at = (select min(r2.allocated_at) from public.so_reserve r2 join public.so_line c2 on c2.id = r2.so_line_id
                                 where (c2.id = l.id or c2.combo_line_id = l.id) and r2.kind = 'backorder')
    ) fr
  ),
  bo_p as (select * from bo_line b where b.bo_qty > 0 and (v_from is null or b.on_date >= v_from) and (v_to is null or b.on_date <= v_to)),
  cl_p as (                                                                                         -- 분자의 덩어리(demand): 첫 백오더 예약 날이 기간 안
    select c.* from cl2 c
    where exists (select 1 from bo_line b where b.comp_id = c.comp_id and b.bo_qty > 0 and (v_from is null or b.on_date >= v_from) and (v_to is null or b.on_date <= v_to))
  ),
  ordered as (                                                                                      -- ② 분모
    select coalesce(sum(l.qty_ordered), 0) as qty, sum(l.qty_ordered * l.unit_price) as amount, count(*) filter (where l.unit_price is null) as price_missing, count(distinct s.id) as orders
    from public.so s join public.so_line l on l.so_id = s.id
    join public.product lp on lp.id = l.product_id                                                                                          -- bo-2b 판정 492: 분모도 줄 단위로 거른다(재고 제품 = 부모로 접힘 · 콤보 줄은 제 제품)
    left join public.product sp on sp.id = coalesce(lp.parent_product_id, lp.id)
    left join public.product_supplier ps on ps.product_id = sp.id and ps.is_default and ps.is_active
    where s.channel = 'warehouse' and s.confirmed_at is not null and not public.so_demand_so_excluded(s.id)
      and l.combo_line_id is null and l.free_reason is null
      and (f->>'sku'         is null or sp.sku ilike (f->>'sku') || '%' or l.sku ilike (f->>'sku') || '%')                                    -- bo-2b 판정 492
      and (f->>'brand_id'    is null or sp.brand_id = (f->>'brand_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and ps.supplier_id is null) or (f->>'supplier_id' <> 'none' and ps.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'product_id'  is null or sp.id = (f->>'product_id')::uuid or l.product_id = (f->>'product_id')::uuid)
      and (v_from is null or (s.confirmed_at at time zone 'America/Toronto')::date >= v_from)
      and (v_to   is null or (s.confirmed_at at time zone 'America/Toronto')::date <= v_to)
      and (f->>'customer_id' is null or s.customer_id = (f->>'customer_id')::uuid)
      and (f->>'location_id' is null or s.location_id = (f->>'location_id')::uuid)
      and (f->>'store'       is null or public.so_store_of(s.intake, s.ref) = f->>'store')                                              -- aone-bo-1: 분모도 스토어로(분자는 demand 가 같은 f 로)
      and (f->>'currency'    is null or s.currency_code = f->>'currency')
  ),
  sku as (                                                                                          -- ③ 재고 제품 하나 = 한 행
    select c.product_id,
           (array_agg(c.r->>'sku' order by c.first_order_date))[1] as sku, (array_agg(c.r->>'product_name' order by c.first_order_date))[1] as product_name,
           (array_agg(c.r->>'brand_id' order by c.first_order_date))[1] as brand_id, (array_agg(c.r->>'brand_name' order by c.first_order_date))[1] as brand_name,
           (array_agg(c.r->>'supplier_id' order by c.first_order_date))[1] as supplier_id, (array_agg(c.r->>'supplier_name' order by c.first_order_date))[1] as supplier_name,
           (array_agg(c.r->>'currency' order by c.first_order_date))[1] as currency, max((c.r->>'currency_n')::int) as currency_n_max,
           count(distinct c.customer_id) filter (where c.open_bo > 0) as customers_waiting,
           count(distinct c.customer_id) as customers_in_period,
           count(*) as clusters, count(*) filter (where c.open_bo > 0) as clusters_open,
           max(public.ims_today() - c.first_order_date) filter (where c.open_bo > 0) as days_waiting_max,
           round(avg(public.ims_today() - c.first_order_date) filter (where c.open_bo > 0), 1) as days_waiting_avg,
           min(c.first_order_date) as first_ask_on,
           sum((c.r->>'demand_then')::numeric) as demand_then, sum((c.r->>'sold')::numeric) as sold, sum((c.r->>'lost')::numeric) as lost,
           sum((c.r->>'lost_amount')::numeric) as lost_amount, sum((c.r->>'open_backorder')::numeric) as open_backorder, sum((c.r->>'open_backorder_amount')::numeric) as open_backorder_amount,
           sum((c.r->>'demand_amount')::numeric) as demand_amount, sum((c.r->>'sold_amount')::numeric) as sold_amount,
           sum((c.r->>'price_missing')::int) as price_missing, sum((c.r->>'flagged')::numeric) as flagged
    from cl c group by c.product_id
  ),
  sku2 as (
    select k.*, p.sku as base_sku,
           (select count(distinct c2.taken_by_so_id) from public.so_backorder_close c2
             where c2.end_kind = 'superseded' and c2.reopened_at is null
               and c2.so_line_id in (select n.line_id from ln n where n.product_id = k.product_id)) as repeat_asks,
           (select count(distinct s2.customer_id) from public.so_backorder_close c2 join public.so_line l2 on l2.id = c2.so_line_id join public.so s2 on s2.id = l2.so_id
             where c2.end_kind = 'superseded' and c2.reopened_at is null
               and c2.so_line_id in (select n.line_id from ln n where n.product_id = k.product_id)) as repeat_customers,
           rc.last_receipt_on
    from sku k
    join public.product p on p.id = k.product_id
    cross join lateral (
      select max(e.occurred_on) as last_receipt_on from public.inv_receipt_events(p.sku, v_wh, null, null) e                         -- bo-2: 입고 정의는 inv_receipt_events 하나(so_backorder_arrivals 와 같은 식)
    ) rc
  ),
  ranked as (
    select k.*, (k.last_receipt_on is null or k.last_receipt_on < k.first_ask_on) as no_receipt_since_first_ask,
           row_number() over (order by
             case v_sort when 'lost_amount' then k.lost_amount when 'lost' then k.lost when 'demand_then' then k.demand_then when 'open_backorder' then k.open_backorder
                         when 'customers_waiting' then k.customers_waiting when 'repeat_asks' then k.repeat_asks when 'days_waiting_max' then k.days_waiting_max end desc nulls last,
             k.lost desc, k.sku) as rn
    from sku2 k
  )
  select jsonb_build_object(
    'as_of', public.ims_today(), 'filters', f, 'sort', v_sort, 'limit', v_limit, 'offset', v_offset,
    'clusters', (v_d->>'total')::int, 'truncated', (v_d->>'total')::int >= 1000,
    'share', jsonb_build_object(
       'stock_sku_active', (select count(*) from public.product p where p.is_active and p.parent_product_id is null),
       'stock_sku_open_backorder', (select count(distinct c.product_id) from cl c where c.open_bo > 0),
       'stock_sku_backordered_in_period', (select count(distinct c.product_id) from cl c),
       'pct_open', round(100.0 * (select count(distinct c.product_id) from cl c where c.open_bo > 0) / nullif((select count(*) from public.product p where p.is_active and p.parent_product_id is null), 0), 2),
       'pct_in_period', round(100.0 * (select count(distinct c.product_id) from cl c) / nullif((select count(*) from public.product p where p.is_active and p.parent_product_id is null), 0), 2),
       'rule', 'stock product = product.is_active and parent_product_id is null (sets fold into their parent; a combo is its own product) · open = at least one open backorder cluster · in_period = clusters that pass the filters'),
    'lost_sales', jsonb_build_object(
       'period_from', v_from, 'period_to', v_to,
       'basis', 'lost_in_period_over_ordered_in_period',                                                                                     -- 판정 486
       'numerator_date', 'lost: each lost piece by its own date (Toronto) — ledger ended_at (unwanted · expired · cancelled rows) · so_line.removed_at (removed) · so.closed_at (cancelled-order remainder, incl. web auto-cancel) · backordered and demand: first backorder reservation allocated_at of the line / cluster · flagged lines excluded',
       'denominator_date', 'so.confirmed_at (Toronto)',
       'denominator_filters', 'line level: sku (stock sku or line sku prefix) · brand · supplier (product default) · product (stock or line) follow the same filter keys (ruling 492) · customer · location · currency at order level · no filter = whole company',
       'flag_rule', 'lines with an active not-real-demand flag count 0 in backordered as well as in lost (ruling 491)',
       'clusters_in_period', (select count(*) from cl_p),
       'ordered_qty', (select qty from ordered), 'ordered_amount', (select amount from ordered), 'ordered_orders', (select orders from ordered), 'ordered_price_missing', (select price_missing from ordered),
       'backordered_qty', (select coalesce(sum(bo_qty), 0) from bo_p), 'backordered_amount', (select coalesce(sum(bo_qty * unit_price), 0) from bo_p),   -- 판정 487 · 축 = 첫 예약 allocated_at
       'demand_then', (select coalesce(sum(demand_then), 0) from cl_p), 'demand_amount', (select coalesce(sum(demand_amount), 0) from cl_p),
       'lost', (select coalesce(sum(qty), 0) from piece_p), 'lost_amount', (select coalesce(sum(qty * unit_price), 0) from piece_p),                -- 빈 합은 0 · 단가 없는 몫은 lost_price_missing                       -- 판정 486 v3: 몫마다 제 날짜
       'lost_by', (select jsonb_build_object('unwanted', coalesce(sum(qty) filter (where kind = 'superseded'), 0), 'expired', coalesce(sum(qty) filter (where kind = 'expired'), 0),
                                             'cancelled', coalesce(sum(qty) filter (where kind = 'cancelled'), 0), 'removed', coalesce(sum(qty) filter (where kind = 'removed'), 0)) from piece_p),
       'lost_amount_by', (select jsonb_build_object('unwanted', coalesce(sum(qty * unit_price) filter (where kind = 'superseded'), 0), 'expired', coalesce(sum(qty * unit_price) filter (where kind = 'expired'), 0),
                                                    'cancelled', coalesce(sum(qty * unit_price) filter (where kind = 'cancelled'), 0), 'removed', coalesce(sum(qty * unit_price) filter (where kind = 'removed'), 0)) from piece_p),
       'lost_price_missing', (select count(*) from piece_p where unit_price is null),
       'pct_of_ordered', round(100.0 * (select coalesce(sum(qty * unit_price), 0) from piece_p) / nullif((select amount from ordered), 0), 2),
       'price_missing', (v_d2->'amount_sums'->>'price_missing')::int, 'currencies', v_d2->'amount_sums'->'currencies',
       'rule', 'ordered = warehouse orders with confirmed_at (unconfirmed-then-cancelled excluded), confirmed date (Toronto) in the period = order_from/to else ended_from/to else all · lost = every lost piece whose own date is in the period (ruling 486) · backordered = per cluster once, the first backorder reservation of each line, by its allocated_at; lines of re-orders (take-over or merge targets and their splits) and splits of a line that already had a backorder count 0 (ruling 487) · flagged lines count 0 (ruling 491) · demand = clusters whose first backorder reservation is in the period · ordered filters by sku · brand · supplier · product at line level (ruling 492)'),
    'total_skus', (select count(*) from ranked),
    'rows', coalesce((select jsonb_agg(jsonb_build_object(
        'product_id', k.product_id, 'sku', k.sku, 'base_sku', k.base_sku, 'product_name', k.product_name, 'brand_id', k.brand_id, 'brand_name', k.brand_name,
        'supplier_id', k.supplier_id, 'supplier_name', k.supplier_name, 'currency', k.currency, 'currency_mixed', k.currency_n_max > 1,
        'customers_waiting', k.customers_waiting, 'customers_in_period', k.customers_in_period, 'repeat_asks', k.repeat_asks, 'repeat_customers', k.repeat_customers,
        'clusters', k.clusters, 'clusters_open', k.clusters_open, 'days_waiting_max', k.days_waiting_max, 'days_waiting_avg', k.days_waiting_avg, 'first_ask_on', k.first_ask_on,
        'demand_then', k.demand_then, 'demand_amount', k.demand_amount, 'sold', k.sold, 'sold_amount', k.sold_amount, 'lost', k.lost, 'lost_amount', k.lost_amount,
        'open_backorder', k.open_backorder, 'open_backorder_amount', k.open_backorder_amount, 'flagged', k.flagged, 'price_missing', k.price_missing,
        'last_receipt_on', k.last_receipt_on, 'no_receipt_since_first_ask', k.no_receipt_since_first_ask, 'rank', k.rn)
      order by k.rn) from ranked k where k.rn > v_offset and k.rn <= v_offset + v_limit), '[]'::jsonb),
    'elapsed_ms', round(extract(epoch from (clock_timestamp() - v_t0)) * 1000))
  into v_out;
  return v_out;
end;
$function$;

-- ═══ 9) mail_backorder_pick — aone 제외 · aone_lines ═══
CREATE OR REPLACE FUNCTION public.mail_backorder_pick(p_location_id uuid, p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_wh    text := (select w.name from public.ref_warehouse w where w.id = p_location_id);
  v_pct   int  := (select c.value::int from public.inv_config c where c.key = 'mail_backorder_min_fill_pct' and c.value ~ '^[0-9]{1,3}$');
  v_since timestamptz;
  v_out   jsonb;
begin
  if p_location_id is null or v_wh is null then
    raise exception 'mail_backorder_pick needs a warehouse id (got %) — nothing was picked', p_location_id;
  end if;
  if v_pct is null then
    raise exception 'inv_config.mail_backorder_min_fill_pct is missing or not a whole number — nothing was picked';
  end if;
  v_since := public.mail_backorder_since(p_location_id, p_now);

  with fl0 as (                                                                                     -- 499 · aone-bo-1 판정 948: 백오더만 · 알림 안 받은 줄(alert 셈이 이미 뺐다) · 지금 몫 있음 · 스토어(so_store_of)
    select f.*, public.so_store_of(s.intake, s.ref) as store
    from public.so_backorder_fill(p_location_id, 'alert') f join public.so s on s.id = f.so_id
    where f.kind = 'backorder' and f.can_fill_units > 0
  ),
  fl as (select * from fl0 where store <> 'aone'),                                                  -- 948: aonebeauty.com 줄은 자동 회차에서 뺀다 — 직원이 Backorders 화면에서 골라 보낸다(mail_backorder_send)
  need as (                                                                                         -- 줄이 기다리는 재고 sku — 보통 줄 = 재고 제품 · 콤보 줄 = 구성품마다
    select fl.line_id, sp.sku from fl join public.product sp on sp.id = fl.stock_pid where not fl.is_combo
    union
    select fl.line_id, c->>'sku' from fl cross join lateral jsonb_array_elements(coalesce(fl.components, '[]'::jsonb)) c where fl.is_combo
  ),
  rsku as (                                                                                         -- 504: 지난 회차 뒤(inv_ledger.created_at) 이 창고 입고(po_in · 다른 창고에서 온 transfer_in)가 있었던 sku
    select k.sku from (select distinct n.sku from need n) k
    where exists (select 1 from public.inv_receipt_events(k.sku, v_wh, null, null) e join public.inv_ledger g on g.id = e.ledger_id where g.created_at > v_since)
  ),
  lns as (                                                                                          -- 505: receipt = 입고 + 몫 ≥ qty_open 의 pct % · full = 다 채워짐 · 둘 다 아니면 이번에 안 실림
    select fl.*,
           case when exists (select 1 from need n join rsku r on r.sku = n.sku where n.line_id = fl.line_id) and fl.can_fill_units * 100 >= fl.qty_open * v_pct then 'receipt'
                when fl.can_fill_units >= fl.qty_open then 'full' end as basis
    from fl
  ),
  lj as (
    select l.customer_id, count(*) as n,
           jsonb_agg(jsonb_build_object('line_id', l.line_id, 'so_id', l.so_id, 'so_number', l.so_number, 'line_no', l.line_no, 'sku', l.sku, 'product_name', l.product_name,
                                        'is_combo', l.is_combo, 'pack_factor', l.pack_factor, 'qty_open', l.qty_open, 'can_fill_units', l.can_fill_units, 'available_units', l.avail_units,
                                        'basis', l.basis, 'first_at', l.first_at, 'components', l.components) order by l.so_number, l.line_no) as lines
    from lns l where l.basis is not null group by l.customer_id
  ),
  cust as (                                                                                         -- 498 · 508: 오더의 customer_id 손님의 연락처만(부모로 안 올라간다)
    select c.id as customer_id, c.name as customer_name, c.is_active, c.backorder_mail,
           (select lower(btrim(cc.email)) from public.customer_contact cc
             where cc.customer_id = c.id and cc.is_active and cc.is_default and public.ims_mail_address_ok(lower(btrim(cc.email)))) as to_default,
           (select lower(btrim(cc.email)) from public.customer_contact cc
             where cc.customer_id = c.id and cc.is_active and cc.is_default is not true and public.ims_mail_address_ok(lower(btrim(cc.email)))
             order by cc.created_at, cc.id limit 1) as to_other,
           exists (select 1 from public.customer_contact cc where cc.customer_id = c.id and cc.is_active and nullif(btrim(cc.email), '') is not null) as has_email
    from public.customer c where c.id in (select j.customer_id from lj j)
  ),
  dec as (
    select cu.customer_id, cu.customer_name, coalesce(cu.to_default, cu.to_other) as to_address,
           case when not cu.is_active then 'customer_inactive'                                      -- 판정 513
                when not cu.backorder_mail then 'paused'                                            -- 판정 507
                when coalesce(cu.to_default, cu.to_other) is not null then null
                when cu.has_email then 'bad_shape'                                                  -- mail-0 이견 13
                else 'no_email' end as reason
    from cust cu
  )
  select jsonb_build_object(
    'location_id', p_location_id, 'location_name', v_wh, 'as_of', p_now, 'since', v_since, 'min_fill_pct', v_pct,
    'aone_lines', (select count(*) from fl0 where fl0.store = 'aone'),                                 -- 948 ⑥: 자동에서 빠진 aone 줄 수(회차 params · Chat 한 줄)
    'mails',   coalesce(jsonb_agg(jsonb_build_object('customer_id', d.customer_id, 'customer_name', d.customer_name, 'to', d.to_address, 'lines', j.lines)
                                  order by d.customer_name, d.customer_id) filter (where d.reason is null), '[]'::jsonb),
    'skipped', coalesce(jsonb_agg(jsonb_build_object('customer_id', d.customer_id, 'customer_name', d.customer_name, 'reason', d.reason, 'lines', j.lines)
                                  order by d.customer_name, d.customer_id) filter (where d.reason is not null), '[]'::jsonb))
  into v_out
  from dec d join lj j on j.customer_id = d.customer_id;
  return v_out;
end;
$function$;
comment on function public.mail_backorder_pick(uuid, timestamptz) is 'mail-1b — 한 창고의 백오더 알림 고르기(tick · preview 가 같은 셈): so_backorder_fill(alert) 의 백오더 줄 중 지금 몫 있는 줄 → 505 receipt(입고 + 몫 ≥ pct %) · full(다 채워짐) → 손님마다 받는 이(498 · 508) · reason(customer_inactive · paused · bad_shape · no_email). aone-bo-1 판정 948: so_store_of = aone 인 줄은 빼고(직원이 mail_backorder_send 로) 그 수를 aone_lines 로 돌려준다';

-- ═══ 10) mail_backorder_tick — 회차 params · runs 에 aone_lines ═══
CREATE OR REPLACE FUNCTION public.mail_backorder_tick(p_now timestamp with time zone DEFAULT now())
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_sched jsonb;
  v_wh    text;
  v_e     jsonb;
  v_local timestamp;
  v_run   uuid;
  v_pick  jsonb;
  v_from  text := (select c.value from public.inv_config c where c.key = 'mail_backorder_from');
  v_name  text := (select c.value from public.inv_config c where c.key = 'mail_backorder_from_name');
  v_reply text := nullif((select c.value from public.inv_config c where c.key = 'mail_backorder_reply_to'), '');
  v_mails int;
  v_lines int;
  v_runs  jsonb := '[]'::jsonb;
  v_err   text;
begin
  -- ⚠️ 꺼져 있으면 회차 · 줄 표지를 쌓지 않는다(보내지도 않은 줄이 「알림 받음」 이 된다)
  if coalesce((select c.value from public.inv_config c where c.key = 'mail_enabled'), 'off') <> 'on' then
    return jsonb_build_object('enabled', false, 'as_of', p_now, 'runs', v_runs);
  end if;
  v_sched := coalesce((select c.value::jsonb from public.inv_config c where c.key = 'mail_backorder_schedule'), '{}'::jsonb);
  for v_wh, v_e in select x.key, x.value from jsonb_each(v_sched) x order by x.key loop
    continue when not exists (select 1 from public.ref_warehouse w where w.id = v_wh::uuid and w.is_active);      -- mail-1a 이견 10: 비활성 창고는 건너뜀
    v_local := p_now at time zone (v_e->>'tz');
    continue when coalesce(public.mail_backorder_next_slot(v_wh::uuid, v_e, p_now), 'infinity') > p_now;   -- mail-1c: 503 · 512 견주기를 속 함수 하나로(미리 보기의 next_run_at 과 같은 규칙) · 요일 ∈ days · 시 ≥ hour · 그날 회차 없음
    begin                                                                                           -- 이견 4: 창고마다 서브트랜잭션 — 실패하면 이 창고의 회차 · 메일 · 줄 표지 전부 되돌림
      v_run := null;
      insert into public.mail_run (kind, location_id, run_on, started_at, params)
      values ('backorder_ready', v_wh::uuid, v_local::date, p_now,
              jsonb_build_object('schedule', v_e, 'min_fill_pct', (select c.value from public.inv_config c where c.key = 'mail_backorder_min_fill_pct'),
                                 'from', v_from, 'from_name', v_name, 'reply_to', v_reply))
      on conflict (kind, location_id, run_on) do nothing
      returning id into v_run;
      continue when v_run is null;
      v_pick := public.mail_backorder_pick(v_wh::uuid, p_now);
      insert into public.mail_outbox (kind, category, status, from_address, from_name, reply_to, to_address, payload, customer_id, location_id, run_id, next_attempt_at, dedupe_key)
      select 'backorder_ready', 'transactional', 'queued', v_from, v_name, v_reply, m->>'to',
             jsonb_build_object('customer_id', m->'customer_id', 'customer_name', m->'customer_name', 'location_id', v_pick->'location_id', 'location_name', v_pick->'location_name',
                                'as_of', p_now, 'lines', m->'lines'),
             (m->>'customer_id')::uuid, v_wh::uuid, v_run, p_now, 'bo:' || v_run || ':' || (m->>'customer_id')
      from jsonb_array_elements(v_pick->'mails') m;
      get diagnostics v_mails = row_count;
      insert into public.mail_backorder_line (outbox_id, so_line_id, basis, qty_open, can_fill_units, available_units)   -- 줄마다 한 번 — 유니크(so_line_id where released_at is null)에 걸리면 이 창고 회차 전체가 실패
      select o.id, (l->>'line_id')::uuid, l->>'basis', (l->>'qty_open')::numeric, (l->>'can_fill_units')::numeric, (l->>'available_units')::numeric
      from jsonb_array_elements(v_pick->'mails') m
      join public.mail_outbox o on o.dedupe_key = 'bo:' || v_run || ':' || (m->>'customer_id')
      cross join lateral jsonb_array_elements(m->'lines') l;
      get diagnostics v_lines = row_count;
      update public.mail_run
         set mails = v_mails, lines = v_lines,
             no_email = coalesce((select jsonb_agg(jsonb_build_object('customer_id', s->'customer_id', 'reason', s->'reason', 'lines', jsonb_array_length(s->'lines')) order by s->>'customer_id')
                                  from jsonb_array_elements(v_pick->'skipped') s), '[]'::jsonb),
             params = params || jsonb_build_object('since', v_pick->'since', 'aone_lines', v_pick->'aone_lines')   -- aone-bo-1 948 ⑥
       where id = v_run;
      v_runs := v_runs || jsonb_build_object('location_id', v_wh, 'status', 'ran', 'run_id', v_run, 'run_on', v_local::date, 'mails', v_mails, 'lines', v_lines,
                                             'skipped', jsonb_array_length(v_pick->'skipped'), 'aone_lines', v_pick->'aone_lines');
      update public.mail_run_error set resolved_at = p_now, resolved_run_id = v_run                    -- mail-4a: 그 창고 · 그날 회차가 섰다 → 앞선 실패 풀림
       where kind = 'backorder_ready' and location_id = v_wh::uuid and run_on = v_local::date and resolved_at is null;
    exception when others then
      get stacked diagnostics v_err = message_text;
      raise warning 'mail_backorder_tick: warehouse % failed and was rolled back — %', v_wh, v_err;
      insert into public.mail_run_error (kind, location_id, run_on, first_at, last_at, message)          -- mail-4a(mail-3 이견 3): 되돌아간 뒤에도 남는다 · 같은 창고 · 날은 한 줄
      values ('backorder_ready', v_wh::uuid, v_local::date, p_now, p_now, left(coalesce(v_err, 'failed'), 2000))
      on conflict (kind, location_id, run_on) where resolved_at is null
      do update set attempts = public.mail_run_error.attempts + 1, last_at = excluded.last_at, message = excluded.message;
      v_runs := v_runs || jsonb_build_object('location_id', v_wh, 'status', 'failed', 'error', v_err);
    end;
  end loop;
  return jsonb_build_object('enabled', true, 'as_of', p_now, 'runs', v_runs);
end;
$function$;

-- ═══ 11) mail_run_chat_due — aone_lines(EF Chat 한 줄) ═══
CREATE OR REPLACE FUNCTION public.mail_run_chat_due()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select coalesce(jsonb_agg(jsonb_build_object(
           'run_id', r.id, 'kind', r.kind, 'location_id', r.location_id, 'location_name', w.name, 'run_on', r.run_on, 'started_at', r.started_at,
           'mails', r.mails, 'lines', r.lines, 'aone_lines', coalesce((r.params->>'aone_lines')::int, 0), 'chat_attempts', r.chat_attempts, 'chat_error', r.chat_error,
           'by_status', coalesce((select jsonb_object_agg(x.status, x.n) from (select o.status, count(*) as n from public.mail_outbox o where o.run_id = r.id group by o.status) x), '{}'::jsonb),
           'skipped', coalesce((select jsonb_object_agg(x.reason, x.n) from (select e->>'reason' as reason, count(*) as n from jsonb_array_elements(r.no_email) e group by 1) x), '{}'::jsonb))
         order by r.started_at, r.id), '[]'::jsonb)
  from (select * from public.mail_run rr
        where rr.chat_posted_at is null and rr.chat_attempts < 5
          and not exists (select 1 from public.mail_outbox o where o.run_id = rr.id and o.status in ('queued', 'sending'))
        order by rr.started_at, rr.id limit 20) r
  join public.ref_warehouse w on w.id = r.location_id;
$function$;

-- ═══ 12) mail_backorder_send — 직원이 고른 줄 보내기(948 ③ · ④) ═══
create or replace function public.mail_backorder_send(p_line_ids uuid[], p_commit boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
-- aone-bo-1 판정 948 ③ · ④ — 직원이 Backorders 화면에서 고른 백오더 줄을 손님(· 창고)마다 한 통으로 보낸다(백오더 알림 backorder_ready 와 같은 메일 · 같은 EF 가 그린다).
--   문: sales 쓰기 + manager 이상(customer_backorder_mail 의 can_edit 와 같은 등급) · p_commit false = 미리 보기(쓰지 않는다) · true = mail_outbox queued + mail_backorder_line(basis manual)
--   줄: so_backorder_fill(창고, 'screen') 의 열린 백오더 줄만 · 지금 몫(can_fill_units) 0 이면 nothing_to_fill(mail_backorder_line_qty_ck 가 0 을 거부한다) · 이미 알림 받은 줄(조상 포함 · 497 · 509)은 already_notified
--   손님: customer.backorder_mail 을 보지 않는다(직원 판단 · 948 ④) — 응답의 backorder_mail 로 화면이 경고 · 받는 이는 doc_mail_recipient(판정 498 과 같은 고르기) · 비활성 손님 · 주소 없음은 skipped_customers
--   회차(mail_run)는 만들지 않는다(run_id null · kind CHECK · 날마다 하나 유니크) — Emails 탭(mail_outbox_list)에 보인다 · Chat 요약엔 안 실린다
--   돌려 보내기 · 켜짐 · [REDIRECT →] 는 EF mail 의 안전 검사 그대로(mail-live-1 판정 947) · mail_enabled off 면 보내기(commit)를 거부한다(표지만 남고 안 나가는 줄이 생긴다 — tick 과 같은 이유)
declare
  v_staff   public.ims_staff%rowtype;
  v_from    text := (select c.value from public.inv_config c where c.key = 'mail_backorder_from');
  v_name    text := (select c.value from public.inv_config c where c.key = 'mail_backorder_from_name');
  v_reply   text := nullif((select c.value from public.inv_config c where c.key = 'mail_backorder_reply_to'), '');
  v_enabled boolean := coalesce((select c.value from public.inv_config c where c.key = 'mail_enabled'), 'off') = 'on';
  v_now     timestamptz := now();
  v_ids     uuid[];
  v_plan    jsonb;
  v_m       jsonb;
  v_oid     uuid;
  v_mails   int := 0;
  v_lines   int := 0;
  v_n       int;
  v_out_ids uuid[] := '{}';
begin
  perform public.ims_require_write('sales', 'sent');
  select * into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff.id is null then raise exception 'You are not registered as active staff — nothing was sent'; end if;
  if coalesce(public.ims_role_rank(v_staff.role), 0) < public.ims_role_rank('manager') then
    raise exception 'Sending a backorder notice by hand needs a manager or above (you are %) — nothing was sent', v_staff.role;
  end if;
  select array_agg(distinct x) into v_ids from unnest(coalesce(p_line_ids, '{}'::uuid[])) x where x is not null;
  if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'Pick at least one backorder line — nothing was sent'; end if;
  if array_length(v_ids, 1) > 200 then raise exception 'At most 200 lines at once (got %) — nothing was sent', array_length(v_ids, 1); end if;
  if p_commit and not v_enabled then raise exception 'Emails are off (mail_enabled) — an admin turns them on in Settings before sending — nothing was sent'; end if;
  if p_commit and (v_from is null or not public.ims_mail_address_ok(v_from)) then raise exception 'mail_backorder_from is not one email address — fix it in Settings — nothing was sent'; end if;

  with ids as (select unnest(v_ids) as want_id),
  loc as (select distinct s.location_id from ids i join public.so_line l on l.id = i.want_id join public.so s on s.id = l.so_id),
  fl as (                                                                                             -- 열린 백오더 줄의 지금 몫 — 화면 Ready 와 같은 셈(screen)
    select f.* from loc cross join lateral public.so_backorder_fill(loc.location_id, 'screen') f
    where f.kind = 'backorder' and f.line_id in (select want_id from ids)
  ),
  ln as (
    select i.want_id, f.*, public.so_store_of(s.intake, s.ref) as store,
           case when f.line_id is null then 'not_open_backorder'
                when public.mail_backorder_line_notified(i.want_id) then 'already_notified'
                when f.can_fill_units <= 0 then 'nothing_to_fill' end as line_reason,
           sl.so_id as want_so_id, sl.line_no as want_line_no, sl.sku as want_sku
    from ids i
    left join fl f on f.line_id = i.want_id
    left join public.so s on s.id = f.so_id
    left join public.so_line sl on sl.id = i.want_id
  ),
  lj as (
    select l.customer_id, l.location_id, l.location_name, count(*) as n, array_agg(l.line_id) as line_ids,
           jsonb_agg(jsonb_build_object('line_id', l.line_id, 'so_id', l.so_id, 'so_number', l.so_number, 'line_no', l.line_no, 'sku', l.sku, 'product_name', l.product_name,
                                        'is_combo', l.is_combo, 'pack_factor', l.pack_factor, 'qty_open', l.qty_open, 'can_fill_units', l.can_fill_units, 'available_units', l.avail_units,
                                        'basis', 'manual', 'first_at', l.first_at, 'components', l.components, 'store', l.store) order by l.so_number, l.line_no) as lines
    from ln l where l.line_reason is null group by l.customer_id, l.location_id, l.location_name
  ),
  cust as (
    select c.id as customer_id, c.name as customer_name, c.is_active, c.backorder_mail, r->>'to' as to_address, r->>'how' as to_how,
           exists (select 1 from public.customer_contact cc where cc.customer_id = c.id and cc.is_active and nullif(btrim(cc.email), '') is not null) as has_email
    from public.customer c cross join lateral public.doc_mail_recipient(c.id) r
    where c.id in (select j.customer_id from lj j)
  ),
  dec as (
    select cu.*, case when not cu.is_active then 'customer_inactive' when cu.to_address is not null then null when cu.has_email then 'bad_shape' else 'no_email' end as reason
    from cust cu
  )
  select jsonb_build_object(
    'mails', coalesce((select jsonb_agg(jsonb_build_object('customer_id', d.customer_id, 'customer_name', d.customer_name, 'to', d.to_address, 'to_how', d.to_how, 'backorder_mail', d.backorder_mail,
                                                            'location_id', j.location_id, 'location_name', j.location_name, 'lines', j.lines, 'line_ids', to_jsonb(j.line_ids))
                                         order by d.customer_name, d.customer_id, j.location_name)
                       from dec d join lj j on j.customer_id = d.customer_id where d.reason is null), '[]'::jsonb),
    'skipped_customers', coalesce((select jsonb_agg(jsonb_build_object('customer_id', d.customer_id, 'customer_name', d.customer_name, 'reason', d.reason, 'location_id', j.location_id, 'lines', j.lines)
                                                    order by d.customer_name, d.customer_id, j.location_name)
                                   from dec d join lj j on j.customer_id = d.customer_id where d.reason is not null), '[]'::jsonb),
    'skipped_lines', coalesce((select jsonb_agg(jsonb_build_object('line_id', l.want_id, 'so_id', coalesce(l.so_id, l.want_so_id), 'so_number', l.so_number, 'line_no', coalesce(l.line_no, l.want_line_no),
                                                                   'sku', coalesce(l.sku, l.want_sku), 'reason', l.line_reason) order by l.so_number, l.line_no)
                               from ln l where l.line_reason is not null), '[]'::jsonb))
  into v_plan;

  if not p_commit then
    return jsonb_build_object('committed', false, 'as_of', v_now, 'enabled', v_enabled) || v_plan;
  end if;
  for v_m in select * from jsonb_array_elements(v_plan->'mails') loop
    insert into public.mail_outbox (kind, category, status, from_address, from_name, reply_to, to_address, payload, customer_id, location_id, run_id, next_attempt_at, dedupe_key, created_by)
    values ('backorder_ready', 'transactional', 'queued', v_from, v_name, v_reply, v_m->>'to',
            jsonb_build_object('customer_id', v_m->'customer_id', 'customer_name', v_m->'customer_name', 'location_id', v_m->'location_id', 'location_name', v_m->'location_name',
                               'as_of', v_now, 'lines', v_m->'lines', 'manual', true, 'sent_by', v_staff.id),
            (v_m->>'customer_id')::uuid, (v_m->>'location_id')::uuid, null, v_now, 'bo:manual:' || gen_random_uuid()::text, v_staff.id)
    returning id into v_oid;
    begin
      insert into public.mail_backorder_line (outbox_id, so_line_id, basis, qty_open, can_fill_units, available_units)
      select v_oid, (l->>'line_id')::uuid, 'manual', (l->>'qty_open')::numeric, (l->>'can_fill_units')::numeric, (l->>'available_units')::numeric
      from jsonb_array_elements(v_m->'lines') l;
    exception when unique_violation then
      raise exception 'A line of % was notified by another run or person just now — reload the page and send again — nothing was sent', v_m->>'customer_name';   -- 497 유니크(so_line_id where released_at is null)
    end;
    get diagnostics v_n = row_count;
    v_mails := v_mails + 1; v_lines := v_lines + v_n; v_out_ids := v_out_ids || v_oid;
  end loop;
  return jsonb_build_object('committed', true, 'as_of', v_now, 'mails', v_mails, 'lines', v_lines, 'outbox_ids', to_jsonb(v_out_ids)) || (v_plan - 'mails') || jsonb_build_object('sent', v_plan->'mails');
end;
$$;
revoke all on function public.mail_backorder_send(uuid[], boolean) from public, anon;
grant execute on function public.mail_backorder_send(uuid[], boolean) to authenticated;   -- service_role 은 기본 권한으로 남는다(다른 창구 · mail-1c 와 같은 꼴)
comment on function public.mail_backorder_send(uuid[], boolean) is 'aone-bo-1 판정 948 — 직원이 고른 백오더 줄을 손님(· 창고)마다 backorder_ready 메일 한 통으로(p_commit false = 미리 보기). 문 sales 쓰기 + manager 이상 · 줄은 so_backorder_fill(screen) 의 열린 백오더 · 몫 0 = nothing_to_fill · 이미 알림(조상 포함) = already_notified · 손님 backorder_mail 은 안 본다(응답에 실어 화면이 경고) · 받는 이 doc_mail_recipient · mail_run 없음(run_id null · dedupe bo:manual:<uuid>) · mail_backorder_line basis manual → 자동 회차(alert) 가 그 줄을 다시 싣지 않는다 · mail_enabled off 면 commit 거부';

-- ═══ 13) shop_order_prepare — aone 이면 새 손님 backorder_mail false(949 ①) ═══
CREATE OR REPLACE FUNCTION public.shop_order_prepare(p_shop_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_o        public.shop_order%rowtype;
  v_s        public.shop_store%rowtype;
  v_reasons  jsonb := '[]'::jsonb;
  v_cust     uuid;
  v_how      text;
  v_link     public.shop_customer%rowtype;
  v_n        int;
  v_cands    jsonb;
  v_name     text;
  v_ship     jsonb;
  v_bill     jsonb;
  v_tier     text;
  v_loc      uuid;
  v_payload  jsonb;
  v_res      jsonb;
  v_keys     text[];
  v_prev     jsonb;
  v_sys      uuid;
  l          record;
  v_bad      int := 0;
  v_dlv      record;  v_pick uuid;                                                                                                     -- ful-1b 판정 454: 배송 방식 · 픽업 위치의 짝 창고
begin
  select * into v_o from public.shop_order o where o.id = p_shop_order_id for update;
  if v_o.id is null then raise exception 'shop_order_prepare: shop order % not found — nothing was saved', p_shop_order_id; end if;
  if v_o.status not in ('received', 'needs_review') then
    return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'skipped', true, 'message', 'already ' || v_o.status);
  end if;
  select * into v_s from public.shop_store s where s.id = v_o.store_id;
  select s.id into v_sys from public.ims_staff s where s.is_system and s.is_active order by s.created_at limit 1;
  v_ship := v_o.raw->'shippingAddress';
  v_bill := v_o.raw->'billingAddress';
  select * into v_dlv from public.shop_order_delivery(v_o.raw);                                                                           -- ful-1b 판정 454: 픽업 오더면 브랜치 = 픽업 위치와 짝인 IMS 창고(배송지 주 430 대신)
  if v_dlv.method = 'PICK_UP' and v_dlv.locations = 1 then
    select sl.warehouse_id into v_pick from public.shop_location sl where sl.store_id = v_o.store_id and sl.is_active and sl.shopify_location_gid = v_dlv.location_gid;   -- 별칭 sl(변수 l 과 겹치지 않게)
  end if;
  v_cust := v_o.customer_id;                                                                                                             -- 직원이 골랐거나(resolve) 앞 prepare 가 정한 손님은 그대로

  -- ① 손님(판정 364) — 계정 잇기 → 이메일 하나 → 여럿(확인 필요) → 없음(새 손님)
  if v_cust is null and v_o.shopify_customer_gid is not null then
    select * into v_link from public.shop_customer x where x.store_id = v_o.store_id and x.shopify_customer_gid = v_o.shopify_customer_gid;
    if v_link.id is not null then v_cust := v_link.customer_id; v_how := 'account'; end if;
  end if;
  if v_cust is null and v_o.email is not null then
    select count(distinct cc.customer_id),
           coalesce(jsonb_agg(distinct jsonb_build_object('customer_id', c.id, 'name', c.name, 'city', (select a.city from public.customer_address a where a.customer_id = c.id and a.is_active order by (a.type = 'Shipping') desc, a.is_default_for_type desc, a.created_at limit 1))), '[]'::jsonb)
      into v_n, v_cands
      from public.customer_contact cc join public.customer c on c.id = cc.customer_id
     where cc.is_active and c.is_active and lower(trim(cc.email)) = v_o.email;
    if v_n = 1 then
      v_cust := (v_cands->0->>'customer_id')::uuid; v_how := 'email';
    elsif v_n > 1 then
      v_reasons := v_reasons || jsonb_build_object('code', 'email_multiple', 'email', v_o.email, 'count', v_n, 'candidates', v_cands,
                                                   'message', format('%s customers share the email %s — pick the customer (shop_order_resolve_customer)', v_n, v_o.email));
    end if;
  end if;
  if v_cust is null and jsonb_array_length(v_reasons) = 0 then                                                                           -- 없음 → 새 손님(판정 364 ④ · 스토어 티어 · customer_create 그대로 · 시스템 직원이 만든다)
    v_name := coalesce(nullif(trim(v_ship->>'company'), ''), nullif(trim(v_ship->>'name'), ''), nullif(trim(v_o.raw->'customer'->>'displayName'), ''),
                       nullif(trim(coalesce(v_o.raw->'customer'->>'firstName', '') || ' ' || coalesce(v_o.raw->'customer'->>'lastName', '')), ''), nullif(trim(v_bill->>'name'), ''), v_o.email);
    if v_name is null then
      v_reasons := v_reasons || jsonb_build_object('code', 'customer_unknown', 'message', 'The order has no customer account, no email and no name — pick or create the customer by hand');
    else
      select t.name into v_tier from public.ref_price_tier t where t.id = v_s.sale_tier_id;
      v_loc := coalesce(v_pick, public.shop_order_pick_location(v_o.store_id, v_o.ship_province_code, null));                                -- ful-1b: 새 손님의 기본 창고도 픽업 창고
      v_payload := jsonb_build_object('name', v_name, 'price_tier', v_tier, 'default_location_id', v_loc,
                                      'backorder_mail', (v_s.kind <> 'aone'),                                                                       -- aone-bo-1 판정 949: aonebeauty.com 웹 손님은 백오더 알림을 끈 채로 만든다(customer_create 가 받는다)
                                      'note', format('Created from Shopify order %s (store %s) by the Shopify system user', v_o.name, v_s.code),
                                      'addresses', (select coalesce(jsonb_agg(a), '[]'::jsonb) from (
                                         select jsonb_build_object('type', 'Shipping', 'is_default_for_type', true, 'label', nullif(trim(v_ship->>'name'), ''), 'line1', v_ship->>'address1', 'line2', v_ship->>'address2', 'city', v_ship->>'city',
                                                                   'state_province', coalesce(v_ship->>'provinceCode', v_ship->>'province'), 'postal_code', v_ship->>'zip', 'country', coalesce(v_ship->>'countryCodeV2', v_ship->>'country')) as a
                                          where nullif(trim(coalesce(v_ship->>'address1', '') || coalesce(v_ship->>'city', '') || coalesce(v_ship->>'zip', '')), '') is not null
                                         union all
                                         select jsonb_build_object('type', 'Billing', 'is_default_for_type', true, 'label', nullif(trim(v_bill->>'name'), ''), 'line1', v_bill->>'address1', 'line2', v_bill->>'address2', 'city', v_bill->>'city',
                                                                   'state_province', coalesce(v_bill->>'provinceCode', v_bill->>'province'), 'postal_code', v_bill->>'zip', 'country', coalesce(v_bill->>'countryCodeV2', v_bill->>'country'))
                                          where nullif(trim(coalesce(v_bill->>'address1', '') || coalesce(v_bill->>'city', '') || coalesce(v_bill->>'zip', '')), '') is not null) z),
                                      'contacts', (select coalesce(jsonb_agg(c), '[]'::jsonb) from (
                                         select jsonb_build_object('name', coalesce(nullif(trim(coalesce(v_o.raw->'customer'->>'firstName', '') || ' ' || coalesce(v_o.raw->'customer'->>'lastName', '')), ''), nullif(trim(v_ship->>'name'), '')),
                                                                   'email', v_o.email, 'phone', coalesce(nullif(trim(v_o.raw->>'phone'), ''), nullif(trim(v_ship->>'phone'), '')), 'is_default', true, 'include_in_email', true) as c
                                          where v_o.email is not null or nullif(trim(coalesce(v_o.raw->'customer'->>'firstName', '') || coalesce(v_o.raw->'customer'->>'lastName', '') || coalesce(v_o.raw->>'phone', '')), '') is not null) z));
      v_prev := public.shop_system_enter();
      v_res := public.customer_create(v_payload, false, '{}');                                                                       -- 검사만 → 경고 열쇠를 모아 → 저장(두 번 부르기 그대로)
      if jsonb_array_length(v_res->'blocks') = 0 then
        select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_res->'warnings') as w;
        v_res := public.customer_create(v_payload, true, v_keys);
      end if;
      perform public.shop_system_leave(v_prev);
      if (v_res->>'committed')::boolean then
        v_cust := (v_res->>'customer_id')::uuid; v_how := 'created';
      else
        v_reasons := v_reasons || jsonb_build_object('code', 'customer_create_blocked', 'blocks', v_res->'blocks', 'message', 'IMS could not create the customer — ' || coalesce((v_res->'blocks'->0->>'message'), 'see blocks'));
      end if;
    end if;
  end if;
  if v_cust is not null then
    if not exists (select 1 from public.customer c where c.id = v_cust and c.is_active) then
      v_reasons := v_reasons || jsonb_build_object('code', 'customer_inactive', 'customer_id', v_cust, 'message', 'The linked IMS customer is inactive — reactivate it or pick another customer');
    elsif v_how is not null and v_o.shopify_customer_gid is not null and v_how <> 'account' then                                          -- 잇기(스토어 × GID) — 계정이 있을 때만
      insert into public.shop_customer (store_id, shopify_customer_gid, customer_id, linked_how, linked_by, updated_by)
      values (v_o.store_id, v_o.shopify_customer_gid, v_cust, v_how, v_sys, v_sys)
      on conflict (store_id, shopify_customer_gid) do nothing;
    end if;
  end if;

  -- ② 줄 대조(판정 366) — SKU 글자 그대로 · 못 찾음 · 꺼짐 · 판매 안 함 → 확인 필요
  for l in select x.id, x.sku, x.line_no, p.id as pid, p.is_active, p.sellable from public.shop_order_line x left join public.product p on p.sku = x.sku where x.shop_order_id = v_o.id order by x.line_no loop
    update public.shop_order_line set product_id = l.pid,
           match = case when l.pid is null then 'not_found' when not l.is_active then 'inactive' when not l.sellable then 'not_sellable' else 'ok' end
     where id = l.id;
    if l.pid is null then v_bad := v_bad + 1; v_reasons := v_reasons || jsonb_build_object('code', 'sku_not_found', 'line_no', l.line_no, 'sku', l.sku, 'message', format('Line %s: SKU %s is not in IMS', l.line_no, coalesce(l.sku, '(none)')));
    elsif not l.is_active then v_bad := v_bad + 1; v_reasons := v_reasons || jsonb_build_object('code', 'product_inactive', 'line_no', l.line_no, 'sku', l.sku, 'message', format('Line %s: product %s is inactive in IMS', l.line_no, l.sku));
    elsif not l.sellable then v_bad := v_bad + 1; v_reasons := v_reasons || jsonb_build_object('code', 'product_not_sellable', 'line_no', l.line_no, 'sku', l.sku, 'message', format('Line %s: product %s is not for sale in IMS', l.line_no, l.sku));
    end if;
  end loop;
  if not exists (select 1 from public.shop_order_line x where x.shop_order_id = v_o.id) then
    v_reasons := v_reasons || jsonb_build_object('code', 'no_lines', 'message', 'The order has no lines with a positive quantity');
  end if;

  -- ③ 브랜치(판정 430 · 427 · ful-1b 454: 픽업 오더는 픽업 위치의 짝 창고 · 위치 둘 · 짝 없음 · 섞임(SHIPPING + PICK_UP)은 확인 필요)
  if v_dlv.method = 'PICK_UP' then
    v_loc := v_pick;
    if v_dlv.locations > 1 then
      v_reasons := v_reasons || jsonb_build_object('code', 'pickup_locations_differ', 'count', v_dlv.locations, 'message', format('Pickup order with %s pickup locations — IMS takes one warehouse per order; split or fix the order in Shopify', v_dlv.locations));
    elsif v_loc is null then
      v_reasons := v_reasons || jsonb_build_object('code', 'pickup_location_unpaired', 'location_gid', v_dlv.location_gid, 'message', format('Pickup location %s is not paired with an IMS warehouse — pair it in Settings → Shopify Stores', coalesce(v_dlv.location_name, v_dlv.location_gid, '(none)')));
    end if;
  else
    v_loc := public.shop_order_pick_location(v_o.store_id, v_o.ship_province_code, v_cust);
    if v_loc is null then
      v_reasons := v_reasons || jsonb_build_object('code', 'warehouse_unknown', 'message', format('Store %s has no active location pair — pair a warehouse in Settings → Shopify Stores', v_s.code));
    end if;
    if v_dlv.method = 'MIXED' then
      v_reasons := v_reasons || jsonb_build_object('code', 'delivery_mixed', 'message', 'The order has both shipping and pickup fulfillment orders — IMS takes one delivery method per order; split it in Shopify');
    end if;
  end if;

  update public.shop_order set customer_id = v_cust, location_id = v_loc, reasons = v_reasons,
         status = case when jsonb_array_length(v_reasons) = 0 then 'received' else 'needs_review' end
   where id = v_o.id returning * into v_o;
  return jsonb_build_object('shop_order_id', v_o.id, 'status', v_o.status, 'customer_id', v_cust, 'linked_how', v_how, 'location_id', v_loc, 'bad_lines', v_bad, 'reasons', v_reasons, 'delivery_method', v_dlv.method);   -- ful-1b
end;
$function$;

-- ═══ 14) customer_create — backorder_mail 칸(없으면 true · 칸 기본값 그대로) ═══
CREATE OR REPLACE FUNCTION public.customer_create(p_customer jsonb, p_commit boolean DEFAULT false, p_ack text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
                               backorder_mail,                                                                                            -- aone-bo-1 판정 949
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
          coalesce((p_customer->>'backorder_mail')::boolean, true),                                                                       -- aone-bo-1 판정 949: 없으면 칸 기본값과 같은 true
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
$function$;

-- ═══ 15) 착지 확인 ═══
do $$
declare v_bad text := ''; v_acl text; v_md5 text;
begin
  if to_regprocedure('public.so_store_of(text, text)') is null then v_bad := v_bad || ' so_store_of'; end if;
  if public.so_store_of('shopify', 'AO-1') <> 'aone' or public.so_store_of('shopify', 'AS-1') <> 'asung' or public.so_store_of('manual', 'AO-1') <> 'manual' or public.so_store_of('shopify', 'X-1') <> 'manual' then v_bad := v_bad || ' so_store_of-values'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'mail_backorder_line_basis_ck' and conrelid = 'public.mail_backorder_line'::regclass) !~ 'manual' then v_bad := v_bad || ' basis_ck'; end if;
  if to_regclass('public.ops_aone_bo_off') is null then v_bad := v_bad || ' ops_table'; end if;
  foreach v_md5 in array array['so_backorder_list|cbc0ee1c181ab540b569558a40cd16af', 'so_backorder_arrivals|25dee596844dba2a7cf62e38faa8fb69', 'so_backorder_ready|2ea4fe401068594ea2f9da06447b30cf',
                                'so_backorder_overview|ce3f84b03c40bf460240dd8043c527f2', 'so_backorder_demand|eec87cef20c7b626c7ea7088a04d2b4d', 'mail_backorder_pick|5b32987f6a6531a831987030185ed763',
                                'mail_backorder_tick|ed117405eed18ee101e2a05a9ec46624', 'mail_run_chat_due|fb2d46bc080f0f598bb246b6c8fe50c6', 'shop_order_prepare|b6e06d4604f6535cd0b0c935c68dbf55', 'customer_create|76f4ca450c6d087a9bd19b794f39a085'] loop
    if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = split_part(v_md5, '|', 1)) = split_part(v_md5, '|', 2) then v_bad := v_bad || ' not-reissued:' || split_part(v_md5, '|', 1); end if;
  end loop;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_backorder_list', 'so_backorder_arrivals', 'so_backorder_ready', 'so_backorder_overview', 'so_backorder_demand') and prosrc ~ $q$'store'$q$) <> 5 then v_bad := v_bad || ' windows-store'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_backorder_pick') !~ 'aone_lines' then v_bad := v_bad || ' pick'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_backorder_tick') !~ 'aone_lines' then v_bad := v_bad || ' tick'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_run_chat_due') !~ 'aone_lines' then v_bad := v_bad || ' chat_due'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_order_prepare') !~ 'backorder_mail' then v_bad := v_bad || ' prepare'; end if;
  if (select prosrc from pg_proc where pronamespace = 'public'::regnamespace and proname = 'customer_create') !~ 'backorder_mail' then v_bad := v_bad || ' customer_create'; end if;
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_backorder_send';
  if v_acl is distinct from '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' send acl ' || coalesce(v_acl, 'null'); end if;   -- 기본 권한이 service_role 을 더한다(다른 창구와 같은 꼴 · mail-1c 선례)
  select proacl::text into v_acl from pg_proc where pronamespace = 'public'::regnamespace and proname = 'mail_backorder_pick';
  if v_acl is distinct from '{postgres=X/postgres}' then v_bad := v_bad || ' pick acl ' || coalesce(v_acl, 'null'); end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_backorder_list', 'so_backorder_arrivals', 'so_backorder_ready', 'so_backorder_overview', 'so_backorder_demand', 'customer_create') and proacl::text = '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}') <> 6 then v_bad := v_bad || ' windows-acl'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM948', message = format('STOP - aone-bo-1 landing check failed:%s', v_bad); end if;
end $$;
