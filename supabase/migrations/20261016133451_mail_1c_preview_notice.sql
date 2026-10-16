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
-- 20261016133451_mail_1c_preview_notice.sql — mail-1c (2026-10-16 · 회사 PC · Fable · mail-1b c4438f0 위에) · 이 차수도 보내지 않는다 — 읽는 창구 둘 · 목록 재발행 하나 · 일정 견주기 속 함수
--   판정 497 · 499 · 503 · 505 · 509 · 512 · 513 · mail-1b §0 이견 1 · 2 · 8 · 9(Caleb 2026-10-16) · mail-1c §0 이견 1 ~ 6(작아 그대로 만듦 · 보고에)
--   ① mail_backorder_next_slot(창고, 일정 한 칸, p_now) — 그 창고 시각으로 오늘부터 요일 ∈ days 이고 그날 회차가 없는 첫 날의 hour 시 · tick 의 견주기(시 ≥ hour · 그날 회차 없음 ⇔ next_slot ≤ p_now)와 미리 보기의 next_run_at 이 같은 식
--   ② mail_backorder_tick 재발행(20261016131325:228 바이트 + 견주기 두 줄 → ① 한 줄)
--   ③ mail_backorder_preview(창고) — definer · 첫 줄 sales · mail_backorder_pick(창고, now()) 그대로(셈을 다시 짜지 않는다) · 쓰지 않는다
--   ④ so_backorder_notice_state(줄 id[]) — definer · 첫 줄 sales · 상태 queued · sent · unknown · cancelled · failed · not_sent · unknown_pre_ims · 프리오더 · 백오더 아닌 줄 null · 509 계보
--   ⑤ so_backorder_list 재발행(20261007163823:34 바이트 + definer · 첫 줄 sales · notified_* 를 ④ 에서) — 그 밖의 출력은 같다
--   무접촉: so_backorder_fill · mail_backorder_pick · so_backorder_ready · 화면(asung-ims 는 notified_* 를 읽지 않는다 — grep 0)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/mail-1c-verify.sql

-- ═══ ① 일정 견주기 하나 ═══
create function public.mail_backorder_next_slot(p_location_id uuid, p_entry jsonb, p_now timestamptz) returns timestamptz
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_day date;
  v_d   int;
begin
  if p_entry is null then
    return null;                                                                                    -- 일정 키에 없는 창고 — 회차 없음
  end if;
  v_day := (p_now at time zone (p_entry->>'tz'))::date;
  for v_d in 0 .. 7 loop
    continue when not ((p_entry->'days') @> to_jsonb(extract(isodow from v_day + v_d)::int));
    continue when exists (select 1 from public.mail_run r where r.kind = 'backorder_ready' and r.location_id = p_location_id and r.run_on = v_day + v_d);
    return ((v_day + v_d) + make_time((p_entry->>'hour')::int, 0, 0)) at time zone (p_entry->>'tz');
  end loop;
  return null;
end;
$$;
comment on function public.mail_backorder_next_slot(uuid, jsonb, timestamptz) is 'mail-1c — 백오더 알림의 다음 회차 시각(판정 503 · 512): 그 창고 시각(p_entry.tz)으로 오늘부터 요일 ∈ p_entry.days 이고 그날(run_on) backorder_ready 회차가 없는 첫 날의 p_entry.hour 시. 오늘 회차가 아직 없고 시가 지났으면 오늘 시각(≤ p_now = 지금 돌 차례). tick 은 next_slot ≤ p_now 일 때 돈다(시 ≥ hour · 그날 회차 없음과 같은 뜻) · 미리 보기의 next_run_at 도 이것 · 공휴일 안 봄';
revoke all on function public.mail_backorder_next_slot(uuid, jsonb, timestamptz) from public, anon, authenticated, service_role;

-- ═══ ② mail_backorder_tick 재발행 — 원본 20261016131325_mail_1b_backorder_pick.sql:228 · 견주기 두 줄 → ① 한 줄 ═══
create or replace function public.mail_backorder_tick(p_now timestamptz default now()) returns jsonb
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

-- ═══ ③ 미리 보기 ═══
create function public.mail_backorder_preview(p_location_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_now  timestamptz := now();
  v_pick jsonb;
  v_next timestamptz;
begin
  if not public.ims_can_view('sales') then raise exception 'Backorders needs the sales permission — nothing was read'; end if;   -- 손님 이메일이 보인다 — Ready 와 같은 수준
  if p_location_id is null or not exists (select 1 from public.ref_warehouse w where w.id = p_location_id and w.is_active) then
    raise exception 'Pick one active warehouse for the backorder mail preview (got %) — nothing was read', coalesce(p_location_id::text, 'none');
  end if;
  v_pick := public.mail_backorder_pick(p_location_id, v_now);                                      -- tick 과 같은 셈 — 다시 짜지 않는다
  v_next := public.mail_backorder_next_slot(p_location_id, (select c.value::jsonb from public.inv_config c where c.key = 'mail_backorder_schedule') -> p_location_id::text, v_now);
  return jsonb_build_object(
    'location_id', p_location_id, 'location_name', v_pick->'location_name', 'as_of', v_now,
    'enabled', coalesce((select c.value from public.inv_config c where c.key = 'mail_enabled'), 'off') = 'on',
    'redirect_to', nullif((select c.value from public.inv_config c where c.key = 'mail_redirect_to'), ''),
    'next_run_at', v_next, 'due_now', coalesce(v_next <= v_now, false),
    'last_run_at', (select max(r.started_at) from public.mail_run r where r.kind = 'backorder_ready' and r.location_id = p_location_id),
    'receipt_since', v_pick->'since', 'min_fill_pct', v_pick->'min_fill_pct',
    'mails', v_pick->'mails', 'skipped', v_pick->'skipped',
    'totals', jsonb_build_object(
      'mails', jsonb_array_length(v_pick->'mails'),
      'customers', jsonb_array_length(v_pick->'mails') + jsonb_array_length(v_pick->'skipped'),
      'lines', (select count(*) from jsonb_array_elements(v_pick->'mails') m cross join lateral jsonb_array_elements(m->'lines') l),
      'skipped_customers', jsonb_array_length(v_pick->'skipped')));
end;
$$;
comment on function public.mail_backorder_preview(uuid) is 'mail-1c — 백오더 알림 「지금 돌면」(직원 화면 · mail-4): mail_backorder_pick(창고, now()) 그대로 · 일정 · mail_enabled 와 상관없이 · 쓰지 않는다. 반환 {location_id, location_name, as_of, enabled, redirect_to(비면 null), next_run_at(mail_backorder_next_slot — 일정 키에 없으면 null), due_now, last_run_at, receipt_since, min_fill_pct, mails[{customer_id, customer_name, to, lines[pick 의 줄 그대로]}], skipped[{…, reason, lines}], totals{mails, customers, lines, skipped_customers}} · 활성 창고 하나 · sales';
revoke all on function public.mail_backorder_preview(uuid) from public, anon;
grant execute on function public.mail_backorder_preview(uuid) to authenticated;

-- ═══ ④ 줄의 알림 상태 ═══
create function public.so_backorder_notice_state(p_line_ids uuid[])
  returns table (line_id uuid, notified_state text, notified_at timestamptz, outbox_id uuid, basis text)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  if not public.ims_can_view('sales') then raise exception 'Backorders needs the sales permission — nothing was read'; end if;
  return query
  with recursive ids as (
    select distinct x as id from unnest(coalesce(p_line_ids, '{}'::uuid[])) x where x is not null
  ),
  up as (                                                                                           -- 509: 그 줄과 조상(split_from_line_id) · depth 0 = 그 줄
    select i.id as lid, i.id as anc, 0 as depth from ids i
    union all
    select up.lid, l.split_from_line_id, up.depth + 1 from up join public.so_line l on l.id = up.anc where l.split_from_line_id is not null and up.depth < 50
  ),
  kd as (                                                                                           -- 프리오더(열린 preorder 예약) · 백오더 줄(백오더 예약이 있었거나 장부 줄이 있다) — 콤보는 구성품 줄의 예약
    select i.id,
           exists (select 1 from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id
                    where (cp.id = i.id or cp.combo_line_id = i.id) and r.kind = 'preorder' and r.released_at is null) as is_pre,
           exists (select 1 from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id
                    where (cp.id = i.id or cp.combo_line_id = i.id) and r.kind = 'backorder')
             or exists (select 1 from public.so_backorder_close c where c.so_line_id = i.id) as is_bo,
           (select s.location_id from public.so_line l join public.so s on s.id = l.so_id where l.id = i.id) as location_id
    from ids i
  ),
  nb as (                                                                                           -- 알림 기록 하나 — 풀리지 않은 것 먼저 · 가까운 조상 먼저 · 최근 것
    select distinct on (u.lid) u.lid, b.outbox_id, b.basis, b.released_at, b.created_at, o.status, o.sent_at
    from up u join public.mail_backorder_line b on b.so_line_id = u.anc join public.mail_outbox o on o.id = b.outbox_id
    order by u.lid, (b.released_at is null) desc, u.depth, b.created_at desc
  ),
  st as (                                                                                           -- 백오더가 된 때 = 계보 전체의 가장 이른 백오더 예약(나뉜 줄은 조상의 때)
    select u.lid, min(r.allocated_at) as first_at
    from up u join public.so_line cp on cp.id = u.anc or cp.combo_line_id = u.anc join public.so_reserve r on r.so_line_id = cp.id and r.kind = 'backorder'
    group by u.lid
  ),
  fr as (
    select r.location_id, min(r.started_at) as first_run from public.mail_run r where r.kind = 'backorder_ready' group by r.location_id
  ),
  stt as (
    select k.id,
           case when k.is_pre or not k.is_bo then null
                when n.lid is not null and n.released_at is null then
                  case n.status when 'queued' then 'queued' when 'sending' then 'queued' when 'sent' then 'sent' when 'unknown' then 'unknown'
                                when 'failed' then 'failed' when 'cancelled' then 'cancelled' end
                when n.lid is not null then 'failed'                                                -- 풀린 기록만 — 다음 회차에 다시 실린다
                when s.first_at is not null and f.first_run is not null and s.first_at >= f.first_run then 'not_sent'
                else 'unknown_pre_ims' end as state,
           n.*
    from kd k
    left join nb n on n.lid = k.id
    left join st s on s.lid = k.id
    left join fr f on f.location_id = k.location_id
  )
  select t.id, t.state,
         case when t.state = 'sent' then t.sent_at when t.state in ('queued', 'unknown') then t.created_at end,
         case when t.state is not null then t.outbox_id end,
         case when t.state is not null then t.basis end
  from stt t;
end;
$$;
comment on function public.so_backorder_notice_state(uuid[]) is 'mail-1c — 줄마다 백오더 알림 상태(mail-1b 이견 8): queued(큐 · 보내는 중) · sent · unknown(요청은 갔는데 응답 없음) · cancelled(취소 · 풀리지 않음) · failed(풀림 — 다음 회차에 다시) · not_sent(그 창고 첫 회차 뒤 백오더가 됨 · 알림 없음) · unknown_pre_ims(첫 회차 전 · 회차 없으면 전부) · 프리오더(열린 preorder 예약) · 백오더 아닌 줄 null. 509: 조상(split_from_line_id)의 기록을 이어받고 notified_at 도 조상의 것 · 풀리지 않은 기록이 풀린 기록보다 앞 · 백오더가 된 때는 계보의 가장 이른 백오더 예약. notified_at = sent 면 보낸 때 · queued · unknown 이면 큐에 넣은 때 · 그 밖은 null';
revoke all on function public.so_backorder_notice_state(uuid[]) from public, anon;
grant execute on function public.so_backorder_notice_state(uuid[]) to authenticated;

-- ═══ ⑤ so_backorder_list 재발행 — 원본 20261007163823_bo_pre_1_preorder_list.sql:34 · definer + 첫 줄 sales · notified_* 는 ④ ═══
create or replace function public.so_backorder_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','state','end_kind','order_from','order_to','ended_from','ended_to','arrived','notified','owed','limit','offset','kind'];   -- bo-pre-1 판정 351: 거르기 kind
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
           l.free_reason                                                                                          -- 판정 15·16: 무상 줄 = owed(우리가 줄 것)
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
           l.free_reason
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
             'location_id', x.location_id, 'location_name', x.location_name,
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
$$;

-- ═══ ⑥ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace
        and proname in ('mail_backorder_next_slot', 'mail_backorder_tick', 'mail_backorder_preview', 'so_backorder_notice_state', 'so_backorder_list')) <> 5 then v_bad := v_bad || ' functions'; end if;
  if not (select prosecdef from pg_proc where oid = 'public.so_backorder_list(jsonb)'::regprocedure) then v_bad := v_bad || ' list-not-definer'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_backorder_list(jsonb)'::regprocedure) ~ 'backorder_notified_at end' then v_bad := v_bad || ' list-old-notified'; end if;
  if (select prosrc from pg_proc where oid = 'public.mail_backorder_tick(timestamptz)'::regprocedure) !~ 'mail_backorder_next_slot\(v_wh::uuid, v_e, p_now\)' then v_bad := v_bad || ' tick-body'; end if;
  if has_function_privilege('anon', 'public.so_backorder_list(jsonb)', 'execute') or has_function_privilege('anon', 'public.mail_backorder_preview(uuid)', 'execute')
     or has_function_privilege('anon', 'public.so_backorder_notice_state(uuid[])', 'execute') or not has_function_privilege('authenticated', 'public.mail_backorder_preview(uuid)', 'execute')
     or not has_function_privilege('authenticated', 'public.so_backorder_notice_state(uuid[])', 'execute') or not has_function_privilege('authenticated', 'public.so_backorder_list(jsonb)', 'execute')
     or has_function_privilege('authenticated', 'public.mail_backorder_next_slot(uuid, jsonb, timestamptz)', 'execute') or has_function_privilege('authenticated', 'public.mail_backorder_tick(timestamptz)', 'execute')
     or has_function_privilege('authenticated', 'public.mail_backorder_pick(uuid, timestamptz)', 'execute') or has_function_privilege('authenticated', 'public.so_backorder_fill(uuid, text)', 'execute') then v_bad := v_bad || ' fn-acl'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM514', message = format('STOP - mail-1c did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
