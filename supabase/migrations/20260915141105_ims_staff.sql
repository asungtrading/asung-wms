-- ─────────────────────────────────────────────────────────────
-- ims_staff — IMS 사용자 표 (Asung-IMS) · 2026-09-15
--
-- 정본: docs/design/po-module.md §10-h(표·RLS·열쇠 판단) · §10-f(로그인 절차 · 첫 admin) · §5(공통 규약)
-- 선례: 운영 wms_staff(baseline) — 베끼지 않았다(아래 「어긋나는 다섯」) · wms_is_admin()/wms_can_manage_staff() 의 security definer 패턴은 따랐다
--
-- ⭐ 왜 지금 — 화면을 ims.asung.ca 에 세우는데 Asung-IMS 에 「이 사람이 누구인가」를 볼 표가 없다.
--    운영의 wms_staff 는 다른 Supabase 프로젝트라 세션이 공유되지 않는다(§10-e). ①Settings 의 「사용자 축은 wms_staff 확장(별건)」이 가리키던 자리.
--
-- ⭐ 열쇠는 auth_user_id(= auth.uid() · JWT sub) — 이메일이 바뀌어도 끊어지지 않는다.
--    ⚠️ 이메일 매칭은 대소문자 함정을 안고 있다 — WMS 는 wms-auth.js 가 원문 .eq 를 하는 것이 불변식이 되어 EF 게이트에 정규화를 못 넣었다(규칙 8 각주).
--    email 은 사람이 읽는 칸으로 NOT NULL UNIQUE 유지. auth.users(id) FK 는 걸지 않는다 — 걸면 퇴사자의 auth 계정을 지울 때 막힌다(우리는 delete 를 닫아 두므로 영구히) · WMS 도 안 걸었다.
--
-- ⭐ RLS — 다른 IMS 표(auth_all)와 다르다. auth_all 이면 매니저가 자기 role 을 admin 으로 고친다.
--    select   authenticated 전부 (자기가 누구인지 알아야 화면이 뜬다)
--    insert·update   ims_is_admin() 인 사람만
--    delete   정책 없음 + revoke — 직원은 지우지 않고 is_active 로 물러난다(§5 · 나중에 PO created_by·감사로그가 이 행을 가리킨다)
--    ⚠️ 재귀 [로컬 실측 2026-09-15]: 정책 안의 부질의에는 그 표의 select 정책이 다시 적용된다.
--       select 가 true 인 지금 모양에서는 update 정책이 ims_staff 를 직접 읽어도 재귀가 안 난다(UPDATE 0/1 정상).
--       그러나 select 정책이 자기 표를 읽는 순간(예: 「활성 직원만 읽게」) → ERROR: infinite recursion detected in policy.
--       ⇒ security definer 함수로 판정을 뺀다 — 나중에 select 를 조여도 조용히 안 뜨는 일이 없다. WMS 선례와 같다.
--    ❌ 검토에서 기각된 안: 「지금은 auth_all 로 두고 화면에서 막는다」 — anon key 가 공개 레포에 있어 PostgREST 를 직접 치면 화면 게이트는 장식이다(규칙 8 실사고).
--
-- ⚠️ 첫 admin — 정책이 「admin 만 insert」라 첫 행은 아무 authenticated 도 못 넣는다. 마이그레이션은 행을 적재하지 않는다(규약).
--    ⇒ Caleb 이 Auth → Add user(Auto Confirm) 로 계정을 만든 뒤 그 UID 로 SQL Editor(postgres · RLS 우회)에서 자기 행을 insert 한다 — SQL 은 §10-f ②-b.
--
-- 공통 8칸에서 벗어나는 곳 — 의도된 것: cin7_id·source 없음(Cin7 대응이 없다 · ref_currency 가 cin7_id 를 뺀 것과 같은 판단) · name 은 있다(관계 표가 아니다).
-- wms_staff 와 어긋나는 다섯(의도): id bigint → uuid · email nullable → NOT NULL UNIQUE · active → is_active · perms 기본 ["split","admin","staff"] → '[]' · warehouse_access 없음(⬜ ⑤ 창고별 발주 때).
-- role 은 둘뿐(manager 일하는 사람 · admin + 사람 추가·비활성) — WMS 의 worker 에 해당하는 등급은 없다(창고 직원은 IMS 에 들어오지 않는다).
--   ⚠️ 짜는 사람/승인하는 사람을 지금 가르지 않는다 — 한 사람이 둘 다 한다(Caleb 2026-09-15). 없는 구분을 미리 칸으로 만들면 ③ 「종류 칸」 실수의 반복.
-- perms 는 빈 배열로 시작 — 화면이 하나뿐이라 쪼갤 것이 없다. 늘면 'purchasing'·'master' 같은 값(WMS requirePerm 과 같은 쓰임).
-- ─────────────────────────────────────────────────────────────

create table if not exists public.ims_staff (
  id            uuid primary key default gen_random_uuid(),
  auth_user_id  uuid not null unique,                      -- ⭐ 열쇠 · auth.users.id (= auth.uid()) · FK 는 걸지 않는다
  email         text not null unique,                      -- 사람이 읽는 칸 · 로그인 열쇠가 아니다
  name          text not null,
  role          text not null default 'manager',
  perms         jsonb not null default '[]'::jsonb,
  is_active     boolean not null default true,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),

  constraint ims_staff_role_ck check (role in ('manager', 'admin'))
);

comment on table  public.ims_staff is 'IMS 사용자(Asung-IMS 프로젝트 · 운영 wms_staff 와 별개 — 세션이 공유되지 않는다). 열쇠는 auth_user_id(=auth.uid()). 쓰기는 admin 만(RLS · ims_is_admin()) · delete 없음(is_active 로 물러난다). 정본 po-module §10-h · 2026-09-15 신설';
comment on column public.ims_staff.auth_user_id is '⭐ auth.users.id — JWT sub · 이메일이 바뀌어도 끊어지지 않는다. FK 없음(퇴사자 auth 삭제를 막지 않기 위해 · WMS 도 없음). Add user 뒤 UID 를 복사해 넣는다(§10-f ②-b)';
comment on column public.ims_staff.email        is 'NOT NULL UNIQUE · 사람이 읽는 칸. ⚠️ 로그인 매칭에 쓰지 않는다 — 대소문자 함정(WMS 규칙 8 각주 · wms-auth.js 원문 .eq)';
comment on column public.ims_staff.role         is 'manager = 일하는 사람(발주·마스터 편집) · admin = + 사람 추가·비활성. worker 없음. ⚠️ 짜는/승인을 지금 가르지 않는다';
comment on column public.ims_staff.perms        is '빈 배열로 시작. 화면이 늘면 purchasing·master 같은 값(WMS requirePerm 과 같은 쓰임). ⚠️ WMS 처럼 admin 을 기본값에 넣지 않는다';
comment on column public.ims_staff.is_active    is '퇴사·중지는 false — 행을 지우지 않는다(delete 닫힘). ims_is_admin() 도 이 칸을 본다';

-- ⭐ 판정 함수 — security definer · 정책 안에서 ims_staff 를 읽어도 그 표의 select 정책을 다시 타지 않는다(재귀 없음)
--    ⚠️ 하나뿐이다 — 정책·EF 게이트가 같은 판정을 쓴다. 다시 만들지 마라(set_updated_at 과 같은 원칙)
create function public.ims_is_admin() returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.ims_staff s
    where s.auth_user_id = auth.uid()
      and s.is_active
      and s.role = 'admin'
  );
$$;
comment on function public.ims_is_admin() is 'RLS 판정 — 호출자(auth.uid())가 활성 admin 인가. security definer 라 ims_staff 정책을 타지 않는다(재귀 방지 · 실측 2026-09-15). 정본 po-module §10-h';
revoke all on function public.ims_is_admin() from public, anon;
grant execute on function public.ims_is_admin() to authenticated;

-- 트리거 — ⚠️ set_updated_at() 은 20260911144606 에 하나뿐. 다시 만들지 마라
create trigger ims_staff_set_updated_at
  before update on public.ims_staff
  for each row execute function public.set_updated_at();

-- RLS — ⚠️ auth_all 이 아니다
alter table public.ims_staff enable row level security;

create policy ims_staff_select on public.ims_staff
  for select to authenticated using (true);                 -- ⚠️ 여기를 자기 표 참조로 조이면 재귀 — 조이려면 함수로

create policy ims_staff_insert on public.ims_staff
  for insert to authenticated with check (public.ims_is_admin());

create policy ims_staff_update on public.ims_staff
  for update to authenticated using (public.ims_is_admin()) with check (public.ims_is_admin());

-- delete 정책 없음 — 그리고 권한도 닫는다
revoke all on public.ims_staff from anon;
revoke delete, truncate on public.ims_staff from authenticated;
