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
-- 20261016131325_mail_1b_backorder_pick.sql — mail-1b (2026-10-16 · 회사 PC · Fable · mail-1a 3f53bd6 위에) · 이 차수는 보내지 않는다 — mail_outbox 에 queued 를 쌓을 뿐(EF mail-2b · cron mail-3)
--   판정 496 ~ 513(Caleb 2026-10-15 ~ 16) · mail-1b §0 이견 1 ~ 10(Caleb 2026-10-16) · 판정 513: 비활성 손님은 보내지 않는다(reason customer_inactive)
--   ① so_backorder_fill(p_location_id, p_mode) — 재고를 줄에 나누는 셈 하나(mail-0 이견 9): so_backorder_ready 의 ln · ent · avail · share · per_line 바이트 그대로 + 바뀐 줄 셋 · 더한 줄 둘
--      screen = 지금 셈 · alert(판정 506) = 프리오더 몫 먼저 · 알림 받은 줄(509 계보)은 줄 세우기에서 뺀다 — mail_backorder_line_notified(줄)
--   ② mail_backorder_since(창고, p_now) — 「지난 회차」 = 그 창고 마지막 mail_run.started_at · 첫 회차는 일정상 바로 앞 시각(이견 3)
--      mail_backorder_pick(창고, p_now) — 회차 하나가 누구에게 무엇을(쓰지 않는다 · tick 과 미리 보기(mail-1c)가 같은 셈)
--        basis receipt = 지난 회차 뒤 inv_ledger.created_at 인 입고(inv_receipt_events 정의) + can_fill × 100 ≥ qty_open × pct(이견 5 · 올림과 같다) · full = can_fill ≥ qty_open
--        받는 이 = 오더의 customer_id(508) · 비활성 → customer_inactive(513) · backorder_mail false → paused(507) · 기본 연락처 → 다른 활성 연락처(created_at, id) · lower(btrim()) + ims_mail_address_ok · bad_shape · no_email(498 · 이견 6)
--   ③ mail_backorder_tick(p_now) — cron(postgres)만 · mail_enabled on 일 때 창고마다 「요일 ∈ days · 시 ≥ hour · 그날 회차 없음」 이면 서브트랜잭션 하나(이견 4): mail_run · mail_outbox · mail_backorder_line · 수
--      실패한 창고는 그 회차 전부 되돌림 + raise warning + 반환 요약 · 다음 매시 틱이 다시 · 공휴일 안 봄(512)
--   ④ so_backorder_ready 재발행 — 셈은 fill('screen') · definer + 첫 줄 ims_can_view('sales')(이견 1) · 출력 jsonb 는 지금과 같다
--   ⑤ so_line.backorder_notified_at comment 만(쓰지 않는다 · 기록은 mail_backorder_line)
--   mail-1c 로 미룸: 미리 보기(mail_backorder_preview) · 알림 상태(so_backorder_notice_state) · so_backorder_list 재발행(이견 9)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/mail-1b-verify.sql

-- ═══ ① 알림 받은 줄(509 계보) · 셈 하나 ═══
create function public.mail_backorder_line_notified(p_line_id uuid) returns boolean
  language sql stable
  set search_path = public, pg_temp
as $$
  with recursive up as (                                                                            -- 그 줄과 조상(split_from_line_id 를 거슬러)
    select l.id, l.split_from_line_id, 1 as depth from public.so_line l where l.id = p_line_id
    union all
    select p.id, p.split_from_line_id, up.depth + 1 from public.so_line p join up on p.id = up.split_from_line_id where up.depth < 50
  )
  select exists (select 1 from up join public.mail_backorder_line b on b.so_line_id = up.id and b.released_at is null);
$$;
comment on function public.mail_backorder_line_notified(uuid) is 'mail-1b 판정 497 · 505 · 509 — 그 줄 또는 split_from_line_id 로 이어진 조상에 풀리지 않은(released_at is null) mail_backorder_line 이 있으면 「알림 받은 줄」 · 되돌리기로 합쳐진 줄(so_unconfirm 이 자식 수량을 부모에 더함)은 보지 않는다(미룬 거리 · 이견 10)';
revoke all on function public.mail_backorder_line_notified(uuid) from public, anon, authenticated, service_role;

create function public.so_backorder_fill(p_location_id uuid, p_mode text)
  returns table (line_id uuid, so_id uuid, line_no int, sku text, product_name text, pack_factor numeric, unit_price numeric, free_reason text, qty_ordered numeric, product_id uuid,
                 stock_pid uuid, brand_id uuid, so_number text, status text, order_date date, customer_id uuid, location_id uuid, location_name text,
                 qty_open numeric, kind text, first_at timestamptz, first_on date, is_combo boolean,
                 can_fill_units numeric, avail_units numeric, components jsonb, arrived_in_period boolean)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with ln as (                                                                                      -- 열린 백오더 · 프리오더 수요 줄(confirmed)
    select l.id as line_id, l.so_id, l.line_no, l.sku, l.product_name, l.pack_factor, l.unit_price, l.free_reason, l.qty_ordered, l.product_id,
           coalesce(p.parent_product_id, p.id) as stock_pid, p.brand_id,
           s.so_number, s.status, s.order_date, s.customer_id, s.location_id, s.location_name,
           q.qty_open, q.kind, q.first_at, (q.first_at at time zone 'America/Toronto')::date as first_on,
           exists (select 1 from public.so_line cp where cp.combo_line_id = l.id) as is_combo
    from public.so_line l
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, min(res.kind) as kind, min(res.allocated_at) as first_at
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind in ('backorder', 'preorder') and res.released_at is null) q
    where l.combo_line_id is null and q.qty_open is not null and s.status = 'confirmed' and s.location_id is not null
      and (p_location_id is null or s.location_id = p_location_id)                                  -- mail-1b: 창고 하나(null = 전부) · 나누기가 창고마다라 결과는 같다
      and not (p_mode = 'alert' and public.mail_backorder_line_notified(l.id))                      -- mail-1b 판정 506 ② · 509: alert 에서 알림 받은 줄(조상 포함)은 줄 세우기에서 빠진다
  ),
  ent as (                                                                                          -- 기다리는 재고 제품 단위(보통 줄 = 제 제품 · 콤보 줄 = 구성품마다)
    select ln.line_id, ln.location_id, ln.stock_pid as need_pid, ln.pack_factor as per_unit, ln.qty_open * ln.pack_factor as qty_base, ln.first_on, ln.order_date, ln.so_number, ln.line_no,
           null::uuid as comp_line_id, ln.sku as need_sku, ln.kind as line_kind
    from ln where not ln.is_combo
    union all
    select ln.line_id, ln.location_id, coalesce(pp.parent_product_id, pp.id), cp.combo_qty * cp.pack_factor, ln.qty_open * cp.combo_qty * cp.pack_factor, ln.first_on, ln.order_date, ln.so_number, ln.line_no,
           cp.id, coalesce(pps.sku, pp.sku), ln.kind
    from ln join public.so_line cp on cp.combo_line_id = ln.line_id join public.product pp on pp.id = cp.product_id left join public.product pps on pps.id = pp.parent_product_id
    where ln.is_combo
  ),
  avail as (                                                                                        -- 창고마다 한 번
    select lw.location_id, b.stock_pid, coalesce(b.qty_ea, 0) - coalesce(b.sales_alloc_ea, 0) - coalesce(b.transfer_alloc_ea, 0) as avail
    from (select e.location_id, array_agg(distinct e.need_pid) as pids from ent e group by e.location_id) lw
    cross join lateral public.inv_available_base(lw.location_id, lw.pids) b
  ),
  share as (                                                                                        -- 재고 제품 × 창고마다 오래 기다린 줄부터 나눈다
    select e.*, coalesce(a.avail, 0) as avail,                                                                                             -- 잔고 행이 없는 제품은 inv_available_base 가 행을 안 낸다 → 가용 0(콤보 구성품이 빠지면 통째 수가 틀어진다)
           least(e.qty_base, greatest(coalesce(a.avail, 0) - coalesce(sum(e.qty_base) over (partition by e.need_pid, e.location_id order by (p_mode = 'alert' and e.line_kind <> 'preorder'), e.first_on asc, e.order_date, e.so_number, e.line_no, e.comp_line_id
                                                                               rows between unbounded preceding and 1 preceding), 0), 0)) as fill_base
    from ent e left join avail a on a.stock_pid = e.need_pid and a.location_id = e.location_id
  ),
  per_line as (                                                                                     -- 줄마다: 보통 줄 = 그 몫 · 콤보 줄 = 구성품 가운데 최소 통째 수
    select sh.line_id,
           min(floor(sh.fill_base / sh.per_unit)) as can_fill_units,
           min(floor(sh.avail / sh.per_unit)) as avail_units,
           jsonb_agg(jsonb_build_object('sku', sh.need_sku, 'product_id', sh.need_pid, 'base_per_unit', sh.per_unit, 'available_now_base', sh.avail, 'can_fill_base', sh.fill_base, 'can_fill_units', floor(sh.fill_base / sh.per_unit)) order by sh.need_sku) filter (where sh.comp_line_id is not null) as components,
           bool_or(exists (select 1 from public.inv_receipt_events(sh.need_sku, (select w.name from public.ref_warehouse w where w.id = sh.location_id), public.ims_today() - 30, null))) as arrived_in_period
    from share sh group by sh.line_id
  )
  select ln.line_id, ln.so_id, ln.line_no, ln.sku, ln.product_name, ln.pack_factor, ln.unit_price, ln.free_reason, ln.qty_ordered, ln.product_id, ln.stock_pid, ln.brand_id,
         ln.so_number, ln.status, ln.order_date, ln.customer_id, ln.location_id, ln.location_name, ln.qty_open, ln.kind, ln.first_at, ln.first_on, ln.is_combo,
         pl.can_fill_units, pl.avail_units, pl.components, pl.arrived_in_period
  from ln join per_line pl on pl.line_id = ln.line_id;
$$;
comment on function public.so_backorder_fill(uuid, text) is 'mail-1b(mail-0 이견 9) — 열린 백오더 · 프리오더 줄(confirmed)에 그 오더 창고의 지금 가용을 나누는 셈 하나(so_backorder_ready 의 bo-2b 셈 바이트 그대로). p_mode screen = 오래 기다린 순서(화면 Ready to ship now) · alert = 판정 506: ① 프리오더 몫을 먼저 ② 알림 받은 줄(mail_backorder_line_notified · 509 계보)은 줄 세우기에서 뺀다 ③ 나머지 오래 기다린 순서 · alert 아닌 값은 screen. p_location_id null = 모든 창고. can_fill_units 0 인 줄도 낸다(거르기는 부르는 쪽) · 속 함수 — 직원 실행 없음';
revoke all on function public.so_backorder_fill(uuid, text) from public, anon, authenticated, service_role;

-- ═══ ② 지난 회차 · 고르기 ═══
create function public.mail_backorder_since(p_location_id uuid, p_now timestamptz) returns timestamptz
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_last timestamptz;
  v_e    jsonb;
  v_day  date;
  v_d    int;
begin
  select max(r.started_at) into v_last from public.mail_run r where r.kind = 'backorder_ready' and r.location_id = p_location_id and r.started_at < p_now;
  if v_last is not null then
    return v_last;
  end if;
  -- 첫 회차(이견 3): 일정상 바로 앞 시각 — 그 창고 시각으로 오늘 앞 날들 가운데 요일이 맞는 가장 가까운 날의 hour 시
  v_e := (select c.value::jsonb from public.inv_config c where c.key = 'mail_backorder_schedule') -> p_location_id::text;
  if v_e is null then
    return p_now - interval '4 days';                                                               -- 일정에 없는 창고(미리 보기만 부른다) — 지금 GAS 의 STOCK_COMPARE_DAYS
  end if;
  v_day := (p_now at time zone (v_e->>'tz'))::date;
  for v_d in 1 .. 7 loop
    if (v_e->'days') @> to_jsonb(extract(isodow from v_day - v_d)::int) then
      return ((v_day - v_d) + make_time((v_e->>'hour')::int, 0, 0)) at time zone (v_e->>'tz');
    end if;
  end loop;
  return p_now - interval '4 days';
end;
$$;
comment on function public.mail_backorder_since(uuid, timestamptz) is 'mail-1b 이견 3 — 「지난 회차」: 그 창고 backorder_ready 회차 가운데 p_now 앞의 마지막 started_at · 없으면 일정상 바로 앞 시각(그 창고 시각 · 오늘 앞 날) · 일정에 없는 창고는 4 일 전. ⚠️ 컷오버 때 들인 입고의 inv_ledger.created_at 은 들인 시각이다(미룬 거리 · mail-0 F6)';
revoke all on function public.mail_backorder_since(uuid, timestamptz) from public, anon, authenticated, service_role;

create function public.mail_backorder_pick(p_location_id uuid, p_now timestamptz default now()) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
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

  with fl as (                                                                                      -- 499: 백오더만 · 알림 안 받은 줄(alert 셈이 이미 뺐다) · 지금 몫 있음
    select f.* from public.so_backorder_fill(p_location_id, 'alert') f
    where f.kind = 'backorder' and f.can_fill_units > 0
  ),
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
    'mails',   coalesce(jsonb_agg(jsonb_build_object('customer_id', d.customer_id, 'customer_name', d.customer_name, 'to', d.to_address, 'lines', j.lines)
                                  order by d.customer_name, d.customer_id) filter (where d.reason is null), '[]'::jsonb),
    'skipped', coalesce(jsonb_agg(jsonb_build_object('customer_id', d.customer_id, 'customer_name', d.customer_name, 'reason', d.reason, 'lines', j.lines)
                                  order by d.customer_name, d.customer_id) filter (where d.reason is not null), '[]'::jsonb))
  into v_out
  from dec d join lj j on j.customer_id = d.customer_id;
  return v_out;
end;
$$;
comment on function public.mail_backorder_pick(uuid, timestamptz) is 'mail-1b — 백오더 알림 회차 하나가 그 창고에서 누구에게 무엇을 보낼지(쓰지 않는다 · tick 과 미리 보기가 같은 셈). so_backorder_fill alert · 백오더만(499) · can_fill > 0 · basis receipt(504 · 505: 지난 회차 뒤 inv_ledger.created_at 입고 + can_fill × 100 ≥ qty_open × mail_backorder_min_fill_pct) / full(can_fill ≥ qty_open) · 받는 이: 오더 손님(508) · customer_inactive(513) · paused(507) · 기본 → 다른 활성 연락처(created_at, id) · lower(btrim) + ims_mail_address_ok · bad_shape · no_email. 반환 {location_id, location_name, as_of, since, min_fill_pct, mails[{customer_id, customer_name, to, lines[]}], skipped[{…, reason, lines}]}';
revoke all on function public.mail_backorder_pick(uuid, timestamptz) from public, anon, authenticated, service_role;

-- ═══ ③ 회차 생산 ═══
create function public.mail_backorder_tick(p_now timestamptz default now()) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
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
    continue when not ((v_e->'days') @> to_jsonb(extract(isodow from v_local)::int)) or extract(hour from v_local) < (v_e->>'hour')::int;   -- 503 · 512: 요일 · 시 ≥ hour(놓쳐도 그날 안에 한 번) · 공휴일 안 봄
    continue when exists (select 1 from public.mail_run r where r.kind = 'backorder_ready' and r.location_id = v_wh::uuid and r.run_on = v_local::date);
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
             params = params || jsonb_build_object('since', v_pick->'since')
       where id = v_run;
      v_runs := v_runs || jsonb_build_object('location_id', v_wh, 'status', 'ran', 'run_id', v_run, 'run_on', v_local::date, 'mails', v_mails, 'lines', v_lines,
                                             'skipped', jsonb_array_length(v_pick->'skipped'));
    exception when others then
      get stacked diagnostics v_err = message_text;
      raise warning 'mail_backorder_tick: warehouse % failed and was rolled back — %', v_wh, v_err;
      v_runs := v_runs || jsonb_build_object('location_id', v_wh, 'status', 'failed', 'error', v_err);
    end;
  end loop;
  return jsonb_build_object('enabled', true, 'as_of', p_now, 'runs', v_runs);
end;
$$;
comment on function public.mail_backorder_tick(timestamptz) is 'mail-1b — 백오더 알림 회차 생산(매시 cron · mail-3 이 등록). mail_enabled on 일 때만 · 일정 키의 활성 창고마다 그 창고 시각으로 요일 ∈ days · 시 ≥ hour · 그날 회차 없음이면 서브트랜잭션 하나: mail_run(started_at = p_now · params) → mail_backorder_pick → 손님마다 mail_outbox queued(dedupe bo:<run>:<customer>) → 줄마다 mail_backorder_line → 수 · no_email(skipped: customer_id · reason · lines). 실패한 창고는 전부 되돌리고 raise warning + 반환 status failed · 다음 틱이 다시. 반환 {enabled, as_of, runs[]} · cron(postgres)만';
revoke all on function public.mail_backorder_tick(timestamptz) from public, anon, authenticated, service_role;

-- ═══ ④ so_backorder_ready 재발행 — 원본 20261015024520_bo_2b_ready_fixes.sql:161 · 셈은 fill('screen') · definer + 첫 줄 sales ═══
create or replace function public.so_backorder_ready(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['location_id','supplier_id','brand_id','sku','product_id','kind','limit','offset'];
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
  if v_kind is not null and v_kind not in ('backorder', 'preorder') then raise exception 'kind must be backorder or preorder'; end if;

  with ln as (select * from public.so_backorder_fill((f->>'location_id')::uuid, 'screen')),   -- mail-1b: 셈(ln · ent · avail · share · per_line)은 속 함수 하나로 옮겼다(바이트 그대로 · screen = 지금 셈)
  rows_ as (
    select ln.*,
           sp.sku as stock_sku, sp.name as stock_name,
           (public.ims_today() - ln.first_on) as days_waiting,
           cu.name as customer_name, cc.name as contact_name, cc.email as contact_email, cc.phone as contact_phone, cc.mobile_phone as contact_mobile,
           ps.supplier_id,
           (select count(*) from public.so_line o
             where o.so_id = ln.so_id and o.combo_line_id is null and o.id <> ln.line_id
               and exists (select 1 from public.so_reserve r2 join public.so_line cp2 on cp2.id = r2.so_line_id
                           where (cp2.id = o.id or cp2.combo_line_id = o.id) and r2.kind in ('backorder', 'preorder') and r2.released_at is null)) as order_other_skus
    from ln
    join public.product sp on sp.id = ln.stock_pid
    join public.customer cu on cu.id = ln.customer_id
    left join public.customer_contact cc on cc.customer_id = cu.id and cc.is_default and cc.is_active
    left join public.product_supplier ps on ps.product_id = ln.stock_pid and ps.is_default and ps.is_active
    where ln.can_fill_units > 0
  ),
  filtered as (
    select * from rows_ r
    where (f->>'location_id' is null or r.location_id = (f->>'location_id')::uuid)
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
        'same_location', true, 'location_id', r.location_id, 'location_name', r.location_name,
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
$$;
comment on function public.so_backorder_ready(jsonb) is
  '⭐ Arrivals 맨 위 「지금 보낼 수 있는 백오더」(bo-2b · 판정 490) — 입고와 상관없이 그 오더 창고에 지금 가용이 있어 can_fill > 0 인 열린 백오더 · 프리오더 수요 줄(confirmed 만). mail-1b: 셈은 so_backorder_fill(창고, screen)(오래 기다린 순서 · 알림과 상관없음 — 판정 506 의 화면 쪽은 철회) · definer + 첫 줄 ims_can_view(sales)(Backorders 화면과 같은 열쇠) · 출력은 bo-2b 와 같다';
revoke all on function public.so_backorder_ready(jsonb) from public, anon;
grant execute on function public.so_backorder_ready(jsonb) to authenticated;

-- ═══ ⑤ 옛 칸 comment ═══
comment on column public.so_line.backorder_notified_at is '⚠️ 쓰지 않는다(mail-1a 이견 11) — 백오더 입고 알림의 기록은 mail_backorder_line(줄마다 한 번 · 판정 497 · 505 · 509 계보) · so_line 에 쓰면 ims_touch 가 updated_at 을 바꿔 so_unconfirm 형제 검사가 그 오더를 막는다(판정 478 과 같은 뿌리) · so_backorder_list 의 notified_state 를 새 표로 옮기는 것은 mail-1c';

-- ═══ ⑥ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname in ('mail_backorder_line_notified', 'so_backorder_fill', 'mail_backorder_since', 'mail_backorder_pick', 'mail_backorder_tick', 'so_backorder_ready')) <> 6 then v_bad := v_bad || ' functions'; end if;
  if not (select prosecdef from pg_proc where oid = 'public.so_backorder_ready(jsonb)'::regprocedure) then v_bad := v_bad || ' ready-not-definer'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_backorder_ready(jsonb)'::regprocedure) !~ 'so_backorder_fill\(\(f->>''location_id''\)::uuid, ''screen''\)' then v_bad := v_bad || ' ready-body'; end if;
  if has_function_privilege('authenticated', 'public.so_backorder_fill(uuid, text)', 'execute') or has_function_privilege('authenticated', 'public.mail_backorder_pick(uuid, timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.mail_backorder_tick(timestamptz)', 'execute') or has_function_privilege('anon', 'public.mail_backorder_tick(timestamptz)', 'execute')
     or has_function_privilege('service_role', 'public.mail_backorder_tick(timestamptz)', 'execute') or has_function_privilege('anon', 'public.so_backorder_ready(jsonb)', 'execute')
     or not has_function_privilege('authenticated', 'public.so_backorder_ready(jsonb)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM513', message = format('STOP - mail-1b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
