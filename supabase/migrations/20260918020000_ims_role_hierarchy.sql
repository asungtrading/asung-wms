-- ─────────────────────────────────────────────────────────────
-- 등급에 순서를 주고, 직원 관리를 admin 밖으로 (Asung-IMS) · 2026-09-17 밤
--
-- 앞 차수: 20260915141105(ims_staff · 정책 셋 · ims_is_admin) · 20260917230000(판정 함수 여섯) · 20260917235000(표별 RLS) · 20260918010000(거부 문장).
-- 이 파일: 함수 둘 신설(ims_role_rank · ims_can_manage) · 둘 다시 냄(ims_can_view · ims_can_write — staff 특례 제거) · 카탈로그 라벨 · ims_staff 정책 둘 교체.
-- ⚠️ ims_is_admin() 은 그대로 둔다(고치지도 지우지도 않는다 — §10-h). 이제 ims_staff 정책은 그것을 안 쓴다.
--
-- ⭐ 설계 [Caleb 2026-09-17]
--   1-a 등급 순서  worker(1) < manager(2) < supervisor(3) < admin(4)  — ⚠️ role_ck 의 나열 순서는 등급 순서가 아니다(임의 나열).
--   1-b 직원 관리는 admin 전용이 아니다 — perms 에 'staff' 가 있으면(또는 role 기본) 직원을 관리한다.
--   1-c 자기보다 **아래만** 만들고 고친다 — 같은 등급도 안 된다(같은 등급을 늘리는 것은 위가 판단할 일). admin 은 전부.
--       ⚠️ 화면(staff.html)이 자기 행의 role·perms 를 잠그지만 화면은 막는 것이 아니다(anon key 공개) ⇒ DB 가 막는다.
--
-- ═══ 화면·EF 가 볼 것 ═══════════════════════════════════════════════════════════════
--  ims_role_rank(p_role text)         → int     worker 1 · manager 2 · supervisor 3 · admin 4 · 모르는 값 null(=막히는 쪽) · immutable · 순서를 아는 곳은 여기 하나
--  ims_can_manage(p_target_role text) → boolean 호출자가 그 등급의 사람을 만들고 고칠 수 있나 = admin 이면 알려진 등급 전부 · 그 외 rank(나) > rank(대상) (엄격 · 같은 등급 false · 모르는 값 false)
--                                                ⚠️ 'staff' 쓰기 권한은 따로 본다 — 정책·EF 는 ims_can_write('staff') AND ims_can_manage(role)
--  ims_can_write('staff') / ims_can_view('staff')  다른 값과 같은 규칙 — admin·supervisor 기본 · manager·worker 는 perms('staff' · 'staff:read')
--  ims_access().screens.staff          위 둘이 그대로 반영된다(함수 무접촉)
--  ⭐ 직원 쓰기는 **PostgREST 그대로** — staff.html 의 sb.from("ims_staff").update(patch).eq("id",…).select() 는 그대로 동작한다(아래 ⬜ 2-c 결론). RPC 신설 없음.
--     막히면 종전처럼 0행 → imsSaved() 「Not saved」. ⚠️ **자기 행은 admin 이 아니면 아무 칸도 못 고친다**(name·note 포함 — 아래 대가).
-- ═════════════════════════════════════════════════════════════════════════════════
--
-- ⬜ 2-c 「어떤 칸이 바뀌었나」— 결론: 트리거도 RPC 도 필요 없다. **using(옛 행) 과 with check(새 행)를 각각 엄격한 등급 비교로 두면** 두 행을 비교하지 않아도 막힌다:
--   · update using  = ims_can_write('staff') and ims_can_manage(옛 role)   → 자기보다 아래 사람의 행만 건드린다(자기 행 = 같은 등급 = 불가)
--   · update check  = ims_can_write('staff') and ims_can_manage(새 role)   → 바꾼 뒤의 등급도 자기보다 아래여야 한다(승격은 자기 등급 미만까지만)
--   · 「manager 를 worker 로 낮췄다가 다시 올리는 길」: 낮추기 자체가 옛 role(manager)을 다룰 수 있어야 하므로 manager(같은 등급)는 못 한다. supervisor 는 둘 다 아래라 되는데 그것은 의도다.
--   · 자기 role 을 올리기: 자기 행 자체가 using 에서 걸린다(같은 등급). 자기 perms 도 같다. 자기 계정을 더 높게 새로 만들기: insert check 가 막는다.
--   · 대가: admin 이 아닌 사람은 **자기 행의 name·note 도 못 고친다**(0행). 화면은 이미 role·is_active 를 잠그고 있고, name·note 자기 수정은 드물어 admin 에게 맡긴다.
--     칸 단위로 열고 싶어지면 그때 RPC(ⓑ)를 세운다 — 지금은 「자기를 승격시킬 수 있다」를 남기지 않는 것이 먼저다.
--   ⓐ 트리거는 §5 「트리거 없음」 규약을 깨고, ⓒ 느슨한 정책은 자기 승격을 남기고, ⓑ RPC 는 화면을 고쳐야 한다 — 셋 다 필요 없었다.
-- ⬜ 2-b supervisor 기본에 'staff' — **넣는다.** 「사람 관리만 admin 몫」이라던 전제가 1-b 로 사라졌고, 진짜 울타리는 이제 perms 가 아니라 등급(manager·worker 만)이다.
--   supervisor 마다 'staff' 를 따로 줘야 하는 모양이면 빠뜨렸을 때 조용히 안 보인다(앞 차수와 같은 논리). manager 는 perms 로만(창고가 걸린 사람에게 사람 관리를 기본으로 주지 않는다).
--   worker 에게 'staff' 를 줘도 아래가 없어 아무도 못 만든다 — 화면만 보인다(무해).
-- ⬜ 2-a 모양 — 둘: rank 함수(순서를 아는 한 곳 · immutable · 정렬·표시에도 쓴다)와 can_manage(정책이 한 번에 묻는 boolean). 대화 Claude 안 그대로.
--
-- 지금 실물(짐작 · 확인은 select name, role, perms from ims_staff): admin 1(Caleb) · supervisor 1(Test Staff — 앞 시험에서 바꿔 두었을 수 있다).
-- 규약: 정책 안 함수 호출은 (select …) 로 감싼다 · select 정책(true)은 무접촉(조이면 재귀) · delete 없음 그대로 · 시그니처 무변 함수는 create or replace(grant·comment 유지).
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) 등급 순서 — 한 곳 ═══
create or replace function public.ims_role_rank(p_role text) returns int
  language sql immutable
  set search_path = public, pg_temp
as $$
  select case p_role
    when 'worker'     then 1
    when 'manager'    then 2
    when 'supervisor' then 3
    when 'admin'      then 4
    else null                                                           -- 모르는 값 = null → 어떤 비교도 false(막히는 쪽)
  end;
$$;
comment on function public.ims_role_rank(text) is
  '등급 순서 한 곳 — worker 1 < manager 2 < supervisor 3 < admin 4 (Caleb 2026-09-17). ⚠️ ims_staff_role_ck 의 나열 순서는 등급이 아니다. 모르는 값 null. 정책·함수·EF 는 이 함수만 본다';
revoke all on function public.ims_role_rank(text) from public, anon;
grant execute on function public.ims_role_rank(text) to authenticated;

-- ═══ 2) 호출자가 그 등급의 사람을 다룰 수 있나 ═══
create or replace function public.ims_can_manage(p_target_role text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when public.ims_role_rank(p_target_role) is null then false        -- 모르는 등급 = admin 이어도 false
      when s.role = 'admin' then true                                      -- admin 은 전부(같은 admin 포함)
      else public.ims_role_rank(s.role) > public.ims_role_rank(p_target_role)   -- 엄격 — 같은 등급 false
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_manage(text) is
  '호출자가 p_target_role 등급의 사람을 만들고 고칠 수 있나 — admin 전부 · 그 외 자기 등급보다 엄격히 아래만(같은 등급 false · Caleb 2026-09-17). 모르는 값·비활성·행 없음 = false. ⚠️ staff 쓰기 권한은 ims_can_write(''staff'') 로 따로 본다';
revoke all on function public.ims_can_manage(text) from public, anon;
grant execute on function public.ims_can_manage(text) to authenticated;

-- ═══ 3) ims_can_view / ims_can_write — 'staff' 특례 제거 (그 외 무변 · 20260917230000 원문 기준) ═══
create or replace function public.ims_can_view(p_screen text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'screens' ? p_screen) then false        -- 모르는 화면 = false (admin 도)
      when s.role in ('admin', 'supervisor') then true                             -- supervisor = almost everything (staff 포함 · 2026-09-17 1-b)
      when s.role = 'worker'
           and public.ims_perm_catalog()->'screens'->p_screen->>'room' = 'wms' then true   -- 창고 사람은 wms 방 화면이 기본
      else s.perms ? p_screen or s.perms ? (p_screen || ':read')                   -- manager · worker(ims 방) = perms
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_view(text) is
  '호출자가 화면을 볼 수 있는가(:read 포함). admin·supervisor 전부 · worker 는 wms 방 화면 기본 · 그 외 perms. staff 도 같은 규칙(2026-09-17 1-b). 모르는 값·비활성·행 없음 = false';

create or replace function public.ims_can_write(p_screen text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'screens' ? p_screen) then false
      when s.role in ('admin', 'supervisor') then true                             -- staff 도 포함 — 누구를 다룰 수 있나는 ims_can_manage 가 따로 본다
      when s.role = 'worker'
           and public.ims_perm_catalog()->'screens'->p_screen->>'room' = 'wms' then true
      else s.perms ? p_screen                                                       -- ':read' 는 세지 않는다
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_write(text) is
  '호출자가 화면에서 저장할 수 있는가. :read 만 가진 화면은 false. staff 는 다른 값과 같다(admin 전용 아님 · 2026-09-17 1-b) — 누구를 다룰 수 있나는 ims_can_manage. ② RLS with check · ims_require_write 가 이 함수를 쓴다';

-- ═══ 4) 카탈로그 라벨 — 「write is admin only」는 틀린 문장이 됐다 ═══
create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products"},
      "receiving":  {"room": "wms", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Staff (people below your own role)"}
    }
  }'::jsonb;
$$;

-- ═══ 5) ims_staff 정책 — insert·update 를 ims_is_admin() 에서 「staff 쓰기 + 등급」으로 ═══
drop policy if exists ims_staff_insert on public.ims_staff;
create policy ims_staff_insert on public.ims_staff
  for insert to authenticated
  with check ((select public.ims_can_write('staff')) and (select public.ims_can_manage(role)));

drop policy if exists ims_staff_update on public.ims_staff;
create policy ims_staff_update on public.ims_staff
  for update to authenticated
  using      ((select public.ims_can_write('staff')) and (select public.ims_can_manage(role)))   -- 옛 행: 자기보다 아래 사람만(자기 행 = 같은 등급 = 불가)
  with check ((select public.ims_can_write('staff')) and (select public.ims_can_manage(role)));  -- 새 행: 바꾼 뒤 등급도 아래여야(승격 상한)
-- select 정책(true)·delete 없음·revoke 는 20260915141105 그대로.

comment on table public.ims_staff is
  'IMS 사용자(Asung-IMS · 운영 wms_staff 와 별개). 열쇠 auth_user_id(=auth.uid()). role 넷 worker<manager<supervisor<admin(ims_role_rank) · perms 두 축 · warehouse_access(빈=전부). 쓰기 = staff 쓰기 권한 + 자기보다 아래 등급만(insert/update 정책 · ims_can_manage · 2026-09-17) · 자기 행은 admin 외 불가 · delete 없음. 정본 po-module §10-h';

-- ═══ 검증 (Caleb · psql heredoc · 회신 §4) ═══
-- select policyname, cmd, qual, with_check from pg_policies where tablename='ims_staff' order by 1;   → 3행(select·insert·update) · insert/update 에 ims_can_manage
-- select ims_role_rank('worker'), ims_role_rank('manager'), ims_role_rank('supervisor'), ims_role_rank('admin'), ims_role_rank('boss');   → 1 2 3 4 null
