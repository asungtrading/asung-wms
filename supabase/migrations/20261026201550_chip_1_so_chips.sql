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

-- ═══ chip-1 — SO 상태 칩 「실제 모습대로」 의 DB 몫 (2026-10-26 · 판정 465 · 479 ~ 481 · deferred 235) ═══
--   DB status 는 그대로(465 · 기각 안 2 새 status) · 화면이 칩 · Status 거르기를 더한다 — 칩 = 열린 예약(so_reserve.released_at null)의 kind
--   ① so_chip_ids()           — 거르기 재료 한 번: {backorder:[id…], preorder:[…], hold:[…], ended:[…]} (so.html loadPayIds 꼴 · id.in) · 「Confirmed(다 잡힘)」 = status confirmed 에서 넷의 합집합을 not.in
--   ② so_chips_many(p_so_ids) — 칩 채우기(fillTotals 꼴 · 한 쪽) : 오더마다 {so_id, n_allocated, n_backorder, n_preorder, n_hold, ended} · n_* = 그 kind 의 열린 예약이 있는 줄 수 · 요청한 id 는 모두 한 행(없으면 0 · false)
--   ⭐ Backorder · Pre-order · On hold = 열린 예약의 kind 로만(status 무관 · 479 「하나라도 맞으면」 · chip-1 답 4) · 지금 자료에서는 전부 confirmed(at_wms · picking · packed 는 allocated 뿐)
--   ⭐ Backorder ended(480) = status confirmed ∧ 열린 예약 0 ∧ 그 오더 줄에 so_backorder_close 가 있다(「백오더 오더」 — 서비스 오더처럼 예약이 없는 confirmed 는 아니다 · chip-1 답 2 A) · 예 SO-25088
--   ⭐ PO(481)는 DB 몫 없음 — 뷰 po_list 의 split_from_number · status · has_confirmed_invoice(확정 goods 인보이스 · 크레딧 · 초안 제외) 세 칸이 이미 있다(chip-1 답 1) · 화면이 거른다
--   invoker · stable(so · so_line · so_reserve · so_backorder_close 의 select 정책이 전부 using(true) — so_totals_many 와 같은 꼴) · authenticated 만 · 원가 값 없음 · 쓰기 0
--   새 표 · 칸 · 시퀀스 0 · 무접촉: so · so_reserve · so_backorder_close · po_list · 화면 · 검증 supabase/tests/chip_1_check.sql

do $$
declare v_bad text := '';
begin
  if to_regclass('public.so') is null then v_bad := v_bad || ' so'; end if;
  if to_regclass('public.so_line') is null then v_bad := v_bad || ' so_line'; end if;
  if to_regclass('public.so_reserve') is null then v_bad := v_bad || ' so_reserve'; end if;
  if to_regclass('public.so_backorder_close') is null then v_bad := v_bad || ' so_backorder_close'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - chip-1 needs%s - nothing was changed', v_bad); end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_chip_ids', 'so_chips_many')) then
    raise exception using errcode = 'IM511', message = 'STOP - so_chip_ids / so_chips_many already exist (applied?) - nothing was changed';
  end if;
end $$;

-- ═══ ① 거르기 재료 ═══
create function public.so_chip_ids() returns jsonb
language sql stable security invoker set search_path = public, pg_temp as $$
  with o as (                                   -- 열린 예약 → 오더 · kind(줄 수는 여기서 안 센다)
    select distinct l.so_id, r.kind
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    where r.released_at is null
  ),
  ended as (                                    -- 480: confirmed · 열린 예약 0 · 백오더 장부(so_backorder_close)가 있는 오더
    select s.id
    from public.so s
    where s.status = 'confirmed'
      and not exists (select 1 from o where o.so_id = s.id)
      and exists (select 1 from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id where l.so_id = s.id)
  )
  select jsonb_build_object(
    'backorder', coalesce((select jsonb_agg(so_id order by so_id) from o where kind = 'backorder'), '[]'::jsonb),
    'preorder',  coalesce((select jsonb_agg(so_id order by so_id) from o where kind = 'preorder'),  '[]'::jsonb),
    'hold',      coalesce((select jsonb_agg(so_id order by so_id) from o where kind = 'hold'),      '[]'::jsonb),
    'ended',     coalesce((select jsonb_agg(id    order by id)    from ended),                      '[]'::jsonb))
$$;
revoke all on function public.so_chip_ids() from public, anon, service_role;
grant execute on function public.so_chip_ids() to authenticated;
comment on function public.so_chip_ids() is 'chip-1 판정 465 · 479 · 480 — Status 거르기 재료 한 번: {backorder:[so id…], preorder:[…], hold:[…], ended:[…]} · 열린 예약(released_at null)의 kind 로(status 무관) · ended = confirmed ∧ 열린 예약 0 ∧ so_backorder_close 있음 · 화면은 id.in(loadPayIds 꼴) · Confirmed(다 잡힘) = status confirmed 에서 넷의 합집합을 not.in · invoker · stable · authenticated 만';

-- ═══ ② 칩 채우기 ═══
create function public.so_chips_many(p_so_ids uuid[])
returns table (so_id uuid, n_allocated int, n_backorder int, n_preorder int, n_hold int, ended boolean)
language plpgsql stable security invoker set search_path = public, pg_temp as $$
begin
  if cardinality(p_so_ids) > 200 then
    raise exception 'so_chips_many takes at most 200 order ids at a time (got %) — nothing was read', cardinality(p_so_ids);
  end if;
  return query
  with ids as (select distinct x as sid from unnest(p_so_ids) x where x is not null),
  o as (                                        -- 오더 × kind → 열린 예약이 있는 줄 수
    select l.so_id as sid, r.kind, count(distinct l.id)::int as n
    from public.so_reserve r
    join public.so_line l on l.id = r.so_line_id
    where r.released_at is null and l.so_id = any (p_so_ids)
    group by l.so_id, r.kind
  )
  select i.sid,
         coalesce((select o.n from o where o.sid = i.sid and o.kind = 'allocated'), 0),
         coalesce((select o.n from o where o.sid = i.sid and o.kind = 'backorder'), 0),
         coalesce((select o.n from o where o.sid = i.sid and o.kind = 'preorder'),  0),
         coalesce((select o.n from o where o.sid = i.sid and o.kind = 'hold'),      0),
         (s.status = 'confirmed'
          and not exists (select 1 from o where o.sid = i.sid)
          and exists (select 1 from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id where l.so_id = i.sid))
  from ids i
  join public.so s on s.id = i.sid;
end $$;
revoke all on function public.so_chips_many(uuid[]) from public, anon, service_role;
grant execute on function public.so_chips_many(uuid[]) to authenticated;
comment on function public.so_chips_many(uuid[]) is 'chip-1 판정 465 · 479 · 480 — 칩 채우기(fillTotals 꼴 · 한 쪽 ≤ 200 · 넘으면 거부 — so_totals_many 와 같다): 오더마다 (so_id, n_allocated, n_backorder, n_preorder, n_hold, ended) · n_* = 그 kind 의 열린 예약이 있는 줄 수 · 요청한 오더는 모두 한 행(예약 없으면 0 · false) · 칩 = Backorder · Pre-order · On hold · Backorder ended(회색) · 셋 다 0 이고 ended 아니면 칩 없음(Confirmed 는 status 배지) · invoker · stable · authenticated 만';
