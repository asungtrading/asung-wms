-- ⑤-6a2 (2026-09-27) — 판정 39: 창고 worker 도 WMS 화면을 사람마다 켠다(staff.html 에 보이는 대로 동작)
--   [테스트 · Asung-IMS] 전용 — 첫 문장은 supabase/ops/guard-test-only.sql 의 바이트 복사(운영 WMS 는 이 함수들과 무관하다 — 운영은 wms-auth · 그래도 첫 문장은 가드).
--   무엇: ims_can_view · ims_can_write 를 마지막 정의(20260926192314 ⑤-2a1)에서 create or replace — 「worker × wms 방 × min_role 없음 → true」 자동 가지(세 줄)만 뺀다.
--         그 밖(시그니처 · stable · security definer · search_path · grant · admin/supervisor 전부 · manager 는 perms · 모르는 화면 false)은 그대로.
--   왜: R8 실측(⑤-6a) — perms 가 ["wms"] 뿐인 worker 도 picking · packing · fulfillment · wms_receiving 이 저절로 열렸다(판정 25 의 A 모양) · Caleb 「그러면 지금은 B로 가자」(판정 39).
--   ⭐ 안전 문(둘째 do 블록 · fail-closed): 적용하는 순간 활성 worker 가운데 wms 방 화면(min_role 없는 것)을 perms 로 하나도 못 보게 되는 사람이 있으면 멈춘다 —
--      Caleb 이 staff.html 에서 worker 마다 Picking · Packing · Fulfillment · Receiving 을 켠 뒤에 적용한다(거꾸로면 현장이 멈춘다). 이름은 문장에 넣지 않는다(수만).
--   perms 어휘(20260917230000 · ims_staff.perms comment): 쓰기 = '<screen>' · 읽기만 = '<screen>:read' — 그 밖('<screen>:write' 등)은 모르는 값 = false.
--   B→A(되돌리기) = 가지를 다시 넣는 재발행(넓어지는 쪽이라 안전).
--   시험 적용 + 검증: ~/asung/prompts/wms-5-6a2-verify.sql (시험 적용 장치 · 전부 rollback)

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

-- ═══ 안전 문 — 활성 worker 가운데 새 규칙으로 wms 방 화면(min_role 없음)을 하나도 못 보는 사람이 있으면 멈춘다(fail-closed · 이름 없이 수만) ═══
do $$
declare
  v_n bigint;
begin
  select count(*) into v_n
  from public.ims_staff s
  where s.is_active and s.role = 'worker'
    and not exists (
      select 1
      from jsonb_each(public.ims_perm_catalog()->'screens') c
      where c.value->>'room' = 'wms' and c.value->>'min_role' is null
        and (s.perms ? c.key or s.perms ? (c.key || ':read'))            -- ims_can_view 와 같은 해석: 쓰기 '<screen>' 또는 읽기 '<screen>:read'
    );
  if v_n > 0 then
    raise exception using errcode = 'WM502',
      message = format('STOP - %s active warehouse worker(s) would lose every warehouse screen the moment this applies - turn their warehouse screens on in Staff first (Picking · Packing · Fulfillment · Receiving) - nothing was changed', v_n);
  end if;
end $$;

-- ═══ 1) ims_can_view 재발행 — 원본 20260926192314:266~284 에서 worker × wms 방 자동 가지 세 줄만 뺐다 ═══
create or replace function public.ims_can_view(p_screen text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'screens' ? p_screen) then false        -- 모르는 화면 = false (admin 도)
      when s.role in ('admin', 'supervisor') then true                             -- supervisor = almost everything (staff 포함 · 2026-09-17 1-b)
      else s.perms ? p_screen or s.perms ? (p_screen || ':read')                   -- manager · worker(ims 방) = perms
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_view(text) is
  '호출자가 화면을 볼 수 있는가(:read 포함). admin·supervisor 전부 · 그 외(manager · worker)는 perms — 화면마다 켠다(⑤-6a2 판정 39: worker 의 wms 방 자동 가지를 뺐다 · staff.html 에 보이는 대로 동작) · 카탈로그 min_role 은 ims_perm_catalog 가 말하고 perms 로 넘는 것은 없다. staff 도 같은 규칙(2026-09-17 1-b). 모르는 값·비활성·행 없음 = false';

-- ═══ 2) ims_can_write 재발행 — 원본 20260926192314:288~304 에서 같은 가지 세 줄만 뺐다 ═══
create or replace function public.ims_can_write(p_screen text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'screens' ? p_screen) then false
      when s.role in ('admin', 'supervisor') then true                             -- staff 도 포함 — 누구를 다룰 수 있나는 ims_can_manage 가 따로 본다
      else s.perms ? p_screen                                                       -- ':read' 는 세지 않는다
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_write(text) is
  '호출자가 화면에서 저장할 수 있는가. :read 만 가진 화면은 false. admin·supervisor 전부 · 그 외(manager · worker)는 perms ? 화면(⑤-6a2 판정 39: worker 의 wms 방 자동 가지를 뺐다). staff 는 다른 값과 같다(admin 전용 아님 · 2026-09-17 1-b) — 누구를 다룰 수 있나는 ims_can_manage. ② RLS with check · ims_require_write 가 이 함수를 쓴다';
