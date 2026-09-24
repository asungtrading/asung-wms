-- SO 쓰기 ③b″ — 무상 줄 백오더 = 「우리가 줄 것」(판정 15·16) · 만료 기간 설정 잠금(판정 14) (2026-09-24 UTC)
-- 판정(Caleb 2026-09-24 · 말 그대로)
--   15 「a로가 넷다 뺀다가 맞아 보여」 — 무상 줄 백오더는 이어받기 대상에서 뺀다 · 무상 사유 넷(sample · promotion · replacement · other) 모두
--      근거: 무상 줄은 손님의 수요가 아니라 우리가 줘야 할 것 — 손님이 같은 제품을 새로 사도 없어지지 않는다(프리오더 「보낼 약속」과 같은 이유 · 판정 9)
--   16 「좋아 a로 가자」 — 무상 줄 백오더는 만료에 걸리지 않는다 · 석 달째 밤에 유상 줄만 expired · 무상 줄은 계속 기다린다 · 무상 줄이 열려 있는 동안 오더는 닫히지 않는다
--      무상 줄이 끝나는 길 둘: so_backorder_proceed(들어오면 보낸다 · proceeded) · 사람이 so_cancel(크레딧 등으로 정리 · cancelled) · 대가: 누가 정리하기 전까지 끝없이 남을 수 있다 ⇒ 백오더 화면에 「우리가 줄 것」으로 따로 · 기다린 날수와 함께
--   14 「나도 수퍼바이저 이상만이라고 생각해」 — 만료 기간(inv_config so_backorder_expire_days)은 supervisor 이상만 바꾼다
--      사정: inv_config 는 auth_all(20260901163300:30) — 로그인한 누구나 바꿀 수 있다 · 티어 설정은 경고만 좌우하지만 이 값은 데이터를 닫는다(90 → 9 면 그날 밤 9일 넘은 백오더 오더가 전부 닫힌다 · 닫힌 오더는 되살리지 않는다 · 판정 11)
-- 사정(③b v3 13 실측): so_backorder_supersede(20260924151719)는 새 오더의 무상 줄은 세지 않았지만(판정 13) 대상 줄에 무상 줄 백오더가 들어갔다 — FB 의 무상 교환품 백오더 1 이 FC 확정 때 0/1 로 닫혔다.
-- 바탕(마지막 정의 · 바이트 그대로 뽑아 더한 줄만 · diff 는 회신): so_backorder_supersede 20260924151719:10~68 · so_backorder_sweep 20260924151038:32~111 · so_backorder_list 20260924151038:116~253
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/so-write-3b-verify.sql v4 13) · so-write-3c-verify.sql v2 8)~10)
--
-- ⭐ 무엇을 하나
--    ① so_backorder_supersede 재발행 — 대상 줄 조회에 l.free_reason is null(수량 쪽 ③b′ 는 그대로)
--    ② so_backorder_sweep 재발행 — 대상: 열린 유상 백오더가 하나라도 있거나 열린 예약이 0 인 오더만(무상 줄뿐인 오더는 고르지 않는다 · 상한 200 을 안 먹는다) · 닫기: 유상 줄만 expired · 그 뒤 열린 예약 0 일 때만 오더 cancelled · 남으면 confirmed 그대로 · 반환 orders_left_open_free
--    ③ so_backorder_list 재발행 — 줄마다 free_reason · owed · days_waiting(ims_today() − order_date) · 필터 owed · 머리 open_owed
--    ④ 설정 잠금(판정 14) — 잠긴 키 목록 한 곳 ims_config_locked_keys() · inv_config.updated_by(누가) · 트리거 inv_config_guard(BEFORE INSERT/UPDATE/DELETE · 잠긴 키만 · authenticated 면 supervisor 이상 · 값은 양의 정수 · postgres·service_role 은 통과) · 다른 키·다른 쓰기 길은 무접촉
--       ⚠️ 잠금 전 실물(회신에 붙임): inv_config 트리거 0 · 정책 auth_all 하나 · anon revoke · 레포에서 authenticated 로 inv_config 를 쓰는 화면·함수 0(inventory.html:710 · ImsRefLoad.gs:256 은 글자만 · seed 다섯은 psql=postgres) ⇒ 잠금이 기존 흐름을 깨지 않는다
--
-- ⭐ 같은 모양 훑기 — 백오더 줄을 「수요」로 다루는 자리(마지막 정의 · 회신에 file:line): 이어받기(supersede 대상·수량) · 만료(sweep 대상·닫기) · 읽기(list) 셋을 이 파일이 고친다 ·
--    so_cancel(cancelled 기록 · 무상 줄도 적는다 — 판정 16 의 「사람이 정리」 길) · so_backorder_proceed(proceeded · 무상 줄도 — 「들어오면 보낸다」 길) · so_backorder_reopen(장부 superseded 줄만 · 무상 줄은 superseded 가 될 수 없어 무관) · so_allocate_run/so_ship(백오더 예약을 만들기만) 은 그대로가 맞다
-- ⚠️ 다시 만들지 않은 것 — so_backorder_record · so_backorder_reopen · so_confirm · so_cancel · so_backorder_proceed · ims_role_rank · ims_today

-- ═══ ① so_backorder_supersede 재발행 — 마지막 정의 20260924151719:10~68 · 더한 줄 1(대상 where) · comment 한 문장 ═══
create or replace function public.so_backorder_supersede(p_so_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so    public.so%rowtype;
  v_base  text;
  k       record;
  t       record;
  v_rem   numeric;
  v_take  numeric;
  v_n     int := 0;
  v_out   jsonb := '[]'::jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' or v_so.confirmed_at is null then
    raise exception 'Order % is % — backorders are taken over at confirmation only — nothing was saved', v_so.so_number, v_so.status;
  end if;
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');

  for k in
    select l.product_id, sum(l.qty_ordered) as qty,
           (array_agg(l.id order by (s.id <> p_so_id), s.so_number, l.line_no))[1] as line_id
    from public.so_line l join public.so s on s.id = l.so_id and l.free_reason is null     -- ③b′ 판정 13: 값을 매긴 줄만 센다(무상 줄은 우리가 준 것 · 수요가 아니다) · 무상 줄만 있는 제품은 이어받지 않는다 · 대표 줄도 유상 줄에서
    where s.id = p_so_id
       or (s.split_from_id = p_so_id and s.confirmed_at = v_so.confirmed_at and s.created_at = v_so.confirmed_at)
    group by l.product_id
  loop
    v_rem := k.qty;
    for t in
      select res.id as reserve_id, res.qty_allocated, l.id as line_id, l.line_no, l.sku, s.so_number, s.order_date, s.location_name
      from public.so_reserve res
      join public.so_line l on l.id = res.so_line_id
      join public.so s on s.id = l.so_id
      where res.kind = 'backorder' and res.released_at is null
        and l.free_reason is null                                    -- 판정 15: 무상 줄 백오더는 이어받기 대상이 아니다(우리가 줄 것 · 손님의 수요가 아니다)
        and s.status = 'confirmed'
        and s.customer_id = v_so.customer_id
        and l.product_id = k.product_id
        and regexp_replace(s.so_number, '[a-z]+$', '') <> v_base
      order by s.order_date, s.created_at, s.so_number, l.line_no
    loop
      perform pg_advisory_xact_lock(hashtext('so_reserve:' || t.line_id::text));
      v_take := least(t.qty_allocated, v_rem);
      perform public.so_backorder_record(t.line_id, 'superseded', t.qty_allocated, v_take, t.qty_allocated - v_take, p_so_id, k.line_id, p_staff, null);
      update public.so_reserve set released_at = now(), released_by = p_staff, released_reason = 'closed', updated_by = p_staff
      where id = t.reserve_id and released_at is null;
      v_rem := v_rem - v_take;
      v_n := v_n + 1;
      v_out := v_out || jsonb_build_object('so_number', t.so_number, 'line_no', t.line_no, 'sku', t.sku, 'order_date', t.order_date, 'location', t.location_name,
                                           'qty_open', t.qty_allocated, 'qty_taken', v_take, 'qty_unwanted', t.qty_allocated - v_take, 'taken_by_line_id', k.line_id);
    end loop;
  end loop;
  return jsonb_build_object('lines_closed', v_n, 'lines', v_out);
end;
$$;
comment on function public.so_backorder_supersede(uuid, uuid) is
  '⭐ 확정 때 이어받기(③b · 판정 3·4·5·8·9 · so_confirm 끝에서 commit 만) — 같은 손님·같은 제품의 열린 백오더 줄(가족 밖 · confirmed · 브랜치 무관 · 프리오더 제외)을 가장 오래된 줄부터 새 수량으로 채우고(qty_taken) 나머지는 더 원하지 않음(qty_unwanted) · ⭐ 새 수량은 값을 매긴 줄만(free_reason null · 판정 13 · 무상 줄만 있는 제품은 이어받지 않는다) · 대상 줄도 유상 백오더만(판정 15 · 무상 줄 백오더는 proceed·cancel 로만 끝난다) · 예약 closed · 장부 superseded(taken_by = 확정한 오더 · 그 제품의 첫 줄) · 오더는 닫지 않는다(판정 11 · 만료가 닫는다)';
revoke all on function public.so_backorder_supersede(uuid, uuid) from public, anon, authenticated;

-- ═══ ② so_backorder_sweep 재발행 — 마지막 정의 20260924151038:32~111 · 더한 줄: 선언 2 · 대상 조건 4 · 유상 줄만 1 · 무상 남으면 건너뛰기 6 · remaining 조건 4 · 반환 1 · create → create or replace ═══
create or replace function public.so_backorder_sweep() returns jsonb
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
  v_left   int;                                     -- 유상 줄을 닫은 뒤 남은 열린 예약(무상 백오더) · 0 일 때만 오더를 닫는다(판정 16)
  v_kept   int := 0;                                -- 무상 줄이 남아 닫지 않은 오더 수
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
      and (exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                   where l.so_id = x.id and rr.released_at is null and rr.kind = 'backorder' and l.free_reason is null)     -- 판정 16: 유상 백오더가 하나라도 있거나
           or not exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                          where l.so_id = x.id and rr.released_at is null))                                                  --          열린 예약이 0 인 오더만 — 무상 줄뿐인 오더는 고르지 않는다(상한을 안 먹는다)
    order by x.order_date, x.so_number
    limit c_cap
  loop
    perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(s.so_number, '[a-z]+$', '')));
    v_open := 0;
    for r in
      select rr.id as reserve_id, rr.so_line_id, rr.qty_allocated
      from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
      where l.so_id = s.id and rr.released_at is null and rr.kind = 'backorder'
        and l.free_reason is null                                                  -- 판정 16: 유상 줄만 만료 · 무상 줄은 계속 기다린다(proceed · cancel 로만 끝난다)
      order by l.line_no
    loop
      perform pg_advisory_xact_lock(hashtext('so_reserve:' || r.so_line_id::text));
      perform public.so_backorder_record(r.so_line_id, 'expired', r.qty_allocated, 0, 0, null, null, null,
                                         format('Expired after %s days (order_date %s · today %s)', v_days, s.order_date, v_today));
      update public.so_reserve set released_at = now(), released_by = null, released_reason = 'closed' where id = r.reserve_id and released_at is null;
      v_open := v_open + 1;
    end loop;
    select count(*) into v_left from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id where l.so_id = s.id and rr.released_at is null;
    if v_left > 0 then                                -- 판정 16: 무상 백오더가 남았다 — 오더는 confirmed 그대로(「우리가 줄 것」 · 화면이 따로 · 매니저가 정리)
      v_kept := v_kept + 1;  v_lines := v_lines + v_open;
      v_out := v_out || jsonb_build_object('so_number', s.so_number, 'order_date', s.order_date, 'closed_reason', null, 'lines_expired', v_open, 'free_lines_left_open', v_left);
      continue;
    end if;
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
                    where l.so_id = x.id and rr.released_at is null and rr.kind <> 'backorder')
    and (exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                 where l.so_id = x.id and rr.released_at is null and rr.kind = 'backorder' and l.free_reason is null)
         or not exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                        where l.so_id = x.id and rr.released_at is null));

  return jsonb_build_object('today', v_today, 'expire_days', v_days, 'cutoff_order_date_before', v_cut, 'cap', c_cap,
                            'orders_closed', v_orders, 'lines_expired', v_lines, 'orders_left_open_free', v_kept, 'remaining', v_remaining, 'orders', v_out);
end;
$$;
comment on function public.so_backorder_sweep() is
  '⭐ 백오더 만료 스윕(③c · 5-g · 판정 9·11 · cron 매일 · postgres 만) — inv_config so_backorder_expire_days(90) · 대상 = confirmed ∧ order_date + days < ims_today() ∧ 열린 예약이 전부 backorder 이거나 0개(preorder·hold·allocated 있으면 제외) · 남은 열린 유상 백오더 줄은 장부 expired(시스템) + 예약 closed · 그 뒤 열린 예약이 0 일 때만 오더 cancelled(열린 줄 있었으면 expired · 0 이면 superseded) · 무상 줄(free_reason)은 만료하지 않고 그 오더도 닫지 않는다(판정 16 · 무상 줄뿐인 오더는 대상에서 뺀다 · 반환 orders_left_open_free) · 상한 200(오래된 것 먼저 · remaining 반환) · 설정이 없으면 예외로 멈춘다 · 두 번 돌려도 같다. ⚠️ authenticated 는 부르지 못한다(cron 소유자만 · wms_auto_hold 모양)';
-- cron(postgres 소유자)만 부른다 — 화면·직원이 남의 백오더를 닫는 경로 차단(wms_auto_hold 20260824202539:185~187 과 같은 모양)
revoke all on function public.so_backorder_sweep() from public;
revoke all on function public.so_backorder_sweep() from anon;
revoke all on function public.so_backorder_sweep() from authenticated;

-- ═══ ③ so_backorder_list 재발행 — 마지막 정의 20260924151038:116~253 · 더한 줄: 열쇠 owed · 선언 1 · 합집합 free_reason 2 · owed·days_waiting 2 · 필터 1 · 반환 칸 3 · 머리 open_owed ═══
create or replace function public.so_backorder_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','state','end_kind','order_from','order_to','ended_from','ended_to','arrived','notified','owed','limit','offset'];
  v_bad    text;
  v_state  text := coalesce(nullif(f->>'state', ''), 'all');
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_rows   jsonb;
  v_total  int;
  v_open   int;
  v_ended  int;
  v_open_owed int;                                 -- 열린 무상 백오더(우리가 줄 것) 수
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
           null::text as end_kind, null::numeric as qty_taken, null::numeric as qty_unwanted, null::uuid as taken_by_so_id, null::timestamptz as ended_at, l.backorder_notified_at as notified_at,
           l.free_reason                                                                                          -- 판정 15·16: 무상 줄 = owed(우리가 줄 것)
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
           c.end_kind, c.qty_taken, c.qty_unwanted, c.taken_by_so_id, c.ended_at, l.backorder_notified_at,
           l.free_reason
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
           (t.free_reason is not null) as owed,                                                                  -- 무상 줄 백오더 = 우리가 줄 것(판정 16 · 이어받기·만료 대상 아님)
           (public.ims_today() - t.order_date) as days_waiting,                                                  -- 기다린 날수(원래 주문일 기준 · 오래된 것을 매니저가 정리)
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
      and (f->>'owed'        is null or b.owed = (f->>'owed')::boolean)
  )
  select count(*), count(*) filter (where state = 'open'), count(*) filter (where state = 'ended'),
         count(*) filter (where state = 'open' and owed) as open_owed_n,
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
             'free_reason', x.free_reason, 'owed', x.owed, 'days_waiting', x.days_waiting,
             'arrived', x.arrived, 'available_here', x.available_here, 'available_other', x.available_other)
           order by x.customer_name, x.customer_id, x.base_sku, x.order_date, x.so_number, x.line_id)
           from (select * from filtered order by customer_name, customer_id, base_sku, order_date, so_number, line_id limit v_limit offset v_offset) x), '[]'::jsonb)
    into v_total, v_open, v_ended, v_open_owed, v_rows
  from filtered;

  return jsonb_build_object(
    'total', v_total, 'open', v_open, 'ended', v_ended, 'open_owed', v_open_owed, 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'notify_tracking', 'pre_ims — backorder_notified_at is not written yet (GAS sends arrival mail from Cin7); notified_state unknown_pre_ims is not "not sent"',
    'arrived_rule', 'po_in or transfer_in from another warehouse (same doc transfer_out at a different, non-IN_TRANSIT warehouse) at the order warehouse since the backorder was made; adjustments, credits, assemblies and arrivals without a departure leg do not count',
    'rows', v_rows);
end;
$$;
comment on function public.so_backorder_list(jsonb) is
  '⭐ 백오더 읽기 창구 하나(③c · 판정 5·6·7 · ⬜11) — 줄 = 열린 backorder 예약(open) ∪ 장부 활성 줄(ended · so_backorder_close.reopened_at null) · 분류 여덟(손님 · 기본 공급처 없음=null/필터 none · 브랜드 · SKU · 주문일·끝난 날 · 브랜치 · 알림 · 입고됨) + owed(무상 줄 백오더 = 우리가 줄 것 · 판정 15·16 · 이어받기·만료 대상 아님 · days_waiting 과 함께 · 필터 owed) · 가용 here/other(창고마다 so_available_many 한 번) · 손님별 흐름은 손님·제품·order_date 순 · jsonb 하나(limit ≤ 1000 · offset). 알림 칸은 pre_ims(notified_state unknown_pre_ims 는 「안 보냄」이 아니다). invoker · stable(임시 표 없음 — stable 은 INSERT 를 못 한다 · 합집합을 두 번 읽는다)';
revoke all on function public.so_backorder_list(jsonb) from public, anon;
grant execute on function public.so_backorder_list(jsonb) to authenticated;

-- ═══ ④ 설정 잠금(판정 14) — 잠긴 키 목록 한 곳 · updated_by · BEFORE 트리거 ═══
-- 방법(대화 Claude 안 채택): 표 정책·grant·다른 키는 그대로 두고 트리거가 잠긴 키만 본다 — authenticated 호출이면 supervisor 이상(ims_role_rank ≥ 3) · postgres·service_role(psql seed · GAS · EF)은 통과 · 값은 양의 정수(쓰는 순간 막는다 · 스윕의 예외는 두 번째 문) · authenticated 의 delete 는 거부
-- 누가·언제: inv_config 에 updated_by(→ ims_staff · nullable · 아무 쓰기 길도 이 칸을 안 보낸다) 를 더하고 트리거가 잠긴 키에만 updated_at=now() · updated_by=호출자 staff 를 채운다(다른 키는 종전대로 · updated_at 기본값만)
create function public.ims_config_locked_keys() returns text[]
  language sql immutable
  set search_path = public, pg_temp
as $$
  select array['so_backorder_expire_days'];       -- ⭐ 다음에 잠글 키는 여기 한 줄 — so_direct_order_tier_code 는 경고만 좌우해 잠그지 않는다(12-g)
$$;
comment on function public.ims_config_locked_keys() is '⭐ inv_config 에서 supervisor 이상만 바꿀 수 있는 키 목록(판정 14 · 2026-09-24) — 데이터를 닫거나 지우는 값만. 지금 so_backorder_expire_days 하나 · 트리거 inv_config_guard 가 읽는다 · 키를 더하면 여기 한 곳';
revoke all on function public.ims_config_locked_keys() from public, anon;
grant execute on function public.ims_config_locked_keys() to authenticated;

alter table public.inv_config add column if not exists updated_by uuid references public.ims_staff (id) on delete no action;
create index if not exists inv_config_updated_by_idx on public.inv_config (updated_by);
comment on column public.inv_config.updated_by is '잠긴 키(ims_config_locked_keys)를 authenticated 가 바꿨을 때 그 사람(ims_staff.id) — 트리거 inv_config_guard 가 채운다 · 다른 키·postgres 쓰기는 null 그대로(2026-09-24 판정 14)';

create function public.inv_config_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_key   text := coalesce(new.key, old.key);
  v_staff public.ims_staff%rowtype;
begin
  if not (v_key = any (public.ims_config_locked_keys())) then
    return case when tg_op = 'DELETE' then old else new end;     -- 잠기지 않은 키 — 종전 그대로(아무것도 안 바꾼다)
  end if;

  -- 값 — 양의 정수만(누가 쓰든 · 스윕은 숫자 아니면 멈추지만 쓰는 순간 막는 편이 낫다)
  if tg_op in ('INSERT', 'UPDATE') then
    if new.value is null or new.value !~ '^[0-9]{1,4}$' or new.value::int <= 0 then
      raise exception 'inv_config.% must be a positive whole number of days (got %) — nothing was saved', v_key, coalesce(new.value, 'null');
    end if;
  end if;

  -- 누가 — authenticated(화면·PostgREST)만 묻는다 · postgres(psql seed · cron) · service_role(GAS · EF) 은 통과
  if current_user = 'authenticated' then
    select * into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff.id is null then
      raise exception 'You are not registered as active staff — nothing was saved';
    end if;
    if coalesce(public.ims_role_rank(v_staff.role), 0) < public.ims_role_rank('supervisor') then
      raise exception 'Changing % needs a supervisor or above (you are %) — this value closes backorder orders for good — nothing was saved', v_key, v_staff.role;
    end if;
    if tg_op = 'DELETE' then
      raise exception 'inv_config.% cannot be deleted from the app — ask an admin to change its value instead — nothing was deleted', v_key;
    end if;
    new.updated_at := now();
    new.updated_by := v_staff.id;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
comment on function public.inv_config_guard() is
  'inv_config BEFORE INSERT/UPDATE/DELETE — 잠긴 키(ims_config_locked_keys)만 본다(판정 14): 값은 양의 정수 · authenticated 면 supervisor 이상(ims_role_rank) · delete 거부 · updated_at/updated_by 기록 · postgres·service_role 은 값 검사만. 다른 키는 아무것도 바꾸지 않는다(auth_all 정책 · GAS·EF 흐름 무접촉)';
revoke all on function public.inv_config_guard() from public, anon;
create trigger inv_config_guard before insert or update or delete on public.inv_config
  for each row execute function public.inv_config_guard();

-- ═══ 검증 — ③b v4 13)(FC lines_closed 1 · FB 무상 백오더 열린 채 · 합계 11·9·1·1·2) · ③c v2 8) 판정 16(유상+무상 섞인 91일 → 유상 expired · 무상 열림 · confirmed · 무상만 91일 → 무접촉 · 두 번째 회차 0 · proceed → proceeded · cancel → cancelled · list owed·days_waiting) · 9) 판정 14(manager 거부 · supervisor 통과 · 0·음수·문자 거부 · 다른 키 그대로 · postgres 통과 · updated_by) ═══
