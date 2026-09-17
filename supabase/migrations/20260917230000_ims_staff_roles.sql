-- ─────────────────────────────────────────────────────────────
-- ims_staff 확장 — role 넷 · warehouse_access · perms 두 축 · 판정 함수 (Asung-IMS) · 2026-09-17 밤
--
-- 정본: docs/design/po-module.md §10-h — ⚠️ 이 마이그레이션으로 그 절의 세 문장이 틀린 문장이 됐다
--       (「창고 직원은 IMS 에 들어오지 않는다」·「role 은 둘뿐」·「perms 는 빈 배열로 시작」) — 회신의 「정본 갱신」 목록.
-- 대상: 20260915141105_ims_staff.sql (적용됨 · 그 파일은 고치지 않는다) 위에 ALTER · 함수 추가만.
-- 자리: 리시빙을 IMS 로 옮기는 여덟 차수의 0번 — ② 표별 RLS · ③ 화면(모드 전환·메뉴) · ④ 동시 편집 · ⑤~⑩ 리시빙이 이 위에 선다.
--
-- ⭐ 왜 지금 [Caleb 2026-09-17] — WMS 리시빙을 IMS(asung-ims · ims.asung.ca)로 복사해 온다. WMS 는 2026-01-01 컷오버까지 그대로.
--    ⇒ 창고 직원이 IMS 에 로그인해야 한다. 「모든 유저는 ims.asung.ca 에서 통합 관리 · WMS 모드와 IMS 모드로 나눈다」.
--
-- ═══ 화면이 부를 모양 — 대화 Claude 는 이 블록만 보고 화면을 쓴다 ═══════════════════════════════════
--  공통: security definer · stable · set search_path = public, pg_temp · anon 회수 · authenticated 만 실행.
--        호출자 = auth.uid() · ims_staff 행이 없거나 is_active=false 면 **전부 false / null**. 모르는 값(없는 모드·없는 화면)은 admin 이어도 false.
--
--  ims_can_enter(p_mode text)      → boolean   'wms' | 'ims' 방에 들어갈 수 있는가(헤더 모드 전환 노출 판정)
--  ims_can_view(p_screen text)     → boolean   화면을 볼 수 있는가 — 읽기 전용(':read')도 true
--  ims_can_write(p_screen text)    → boolean   화면에서 저장할 수 있는가 — ':read' 만 있으면 false · ② 차수 RLS 의 with check 가 이것을 쓴다
--  ims_can_warehouse(p_wh uuid)    → boolean   그 창고(ref_warehouse.id)에 접근하는가 · warehouse_access 가 비어 있으면 전부 true
--  ims_perm_catalog()              → jsonb     알려진 값 한 곳: {"modes":["wms","ims"],"screens":{"<screen>":{"room":"wms"|"ims","label":…}}}
--                                              perms 편집 UI 가 선택지를 여기서 받는다(화면에 값을 하드코딩하지 않는다)
--  ims_access()                    → jsonb     ⭐ 헤더가 로그인 직후 한 번 부른다 — 위 판정을 한 행으로:
--                                              {"role":…,"name":…,"modes":["wms","ims"…],
--                                               "screens":{"purchasing":"write"|"read"|null, "master":…, "receiving":…, "staff":…},
--                                               "warehouses": null(=전부) | ["<ref_warehouse.id>",…]}
--                                              행이 없거나 비활성이면 null.
--  ims_is_admin()                  (20260915141105 · 그대로 · 고치지도 다시 만들지도 않았다)
--
--  perms(jsonb 배열) 원소 — 두 축을 한 배열에 [Caleb 2026-09-17]
--    축 1 모드   'wms' · 'ims'
--    축 2 화면   'purchasing'(po·invoices·charges·payments) · 'master'(settings·suppliers·products·families·supplier-products)
--               · 'receiving'(리시빙·풋어웨이 — 다음 차수 화면) · 'staff'(staff.html)
--               쓰기 = '<screen>' · 읽기만 = '<screen>:read' (화면은 뜨고 저장이 막힌다 · 진짜 게이트는 ② 차수 RLS)
--    ⚠️ 화면 값에 CHECK 를 걸지 않는다 — 화면이 늘 때 표를 안 고치기 위해서다(Caleb). 대신 모르는 값은 함수가 false 로 답한다.
--
--  role 기본값(함수 안 · 화면과 정책이 같은 판정을 쓰게)                 ⭐ 원칙: **더하기만 한다** — perms 는 role 기본으로 열린 것을 닫지 못한다.
--    admin       모드 둘 · 화면 전부 쓰기 · 창고 전부                          닫는 길이 필요해지면 그때 별도 값(예 'purchasing:none')을 만든다.
--    supervisor  모드 둘 · 화면 전부 쓰기 · 창고 전부 · ⚠️ 'staff' 만 제외      근거: 두 축이 서로 막으면 「왜 안 보이지」를 두 곳에서 찾게 된다.
--                (「almost everything · 사람 관리만 admin 몫」 Caleb)
--    manager     모드 둘 · 화면 = perms · 창고 = warehouse_access
--    worker      모드 'wms' + perms · 화면 = wms 방의 화면(지금 'receiving') 쓰기 + perms · 창고 = warehouse_access
--                ⭐ 방 판정은 화면 값에서도 열린다: 'receiving' 만 준 worker 도 wms 방에 들어간다(모드 토큰을 따로 안 줘도) —
--                   같은 이유로 'purchasing:read' 만 준 worker 는 ims 방이 열린다. 방과 화면을 따로 맞춰야 하는 실수를 없애기 위해서다.
--    'staff' 쓰기는 role 이 admin 일 때만 — ims_is_admin() 과 같은 답. RLS(insert/update = ims_is_admin())가 이미 그렇게 막고 있어 함수가 다르게 답하면 거짓말이 된다.
-- ═══════════════════════════════════════════════════════════════════════════════════════════════
--
-- warehouse_access 의 모양 — uuid[] (ref_warehouse.id) · NOT NULL default '{}' · ⭐ 빈 배열 = 전부
--  · 왜 uuid[] 인가: 문서가 창고를 id 로 든다(po.ship_to_warehouse_id · ref_bin.warehouse_id · 리시빙 머리도 그럴 것) ⇒ 정책이 조인 없이
--    ims_can_warehouse(문서.warehouse_id) 한 번으로 끝난다. text(이름)면 정책마다 ref_warehouse 조인이 붙고, 이름은 바뀔 수 있다(source manual 허용).
--  · 왜 관계 표가 아닌가: 창고 셋 × 매니저 몇 명이다. 표 하나·FK 둘·RLS 를 더 얹을 크기가 아니다. 커지면 그때 표로 뺀다(배열 → 표는 한 문장).
--  · ⚠️ 배열에는 FK 를 못 건다 — 없는 uuid 가 들어가면 그 창고만 조용히 안 열린다(닫히는 쪽 · 안전). 존재 검증은 perms 편집 화면/RPC 몫(③ 차수).
--  · ⭐ 빈 값 = 전부(대화 Claude 안 채택): 채워야 열리는 모양이면 사람을 더할 때마다 빠뜨리고, 빠뜨리면 조용히 아무것도 안 보인다.
--    supervisor·admin 은 비워 둔다(함수가 role 로 먼저 true). manager·worker 만 채운다.
--  · WMS 에서 옮길 때(컷오버): wms_staff.warehouse_access 'toronto' → ref_warehouse 'Asung Trading Inc.' 의 id · 'edmonton' → 'Asung - Edmonton' 의 id ·
--    'both' → '{}'. (이름은 EF receiving WH_NAME 맵의 실물 · 셋째 창고 이름은 안 봤다 — 짐작하지 않는다)
--
-- 기존 행(Caleb admin · Test Staff manager — 행 수는 짐작): role 이 둘 다 새 CHECK 안에 있어 살아 있다 · 새 칸은 default '{}' 로 채워진다 · perms 는 그대로 '[]'.
-- ⚠️ EF ims-staff-create 는 role 을 manager/admin 둘로 검사한다(index.ts:96) · staff.html 의 role 선택지도 둘 — ③ 차수에서 넷으로. 이 마이그레이션은 그 둘을 깨뜨리지 않는다(둘은 여전히 유효한 값).
-- 규약: set_updated_at() 재사용(트리거 이미 있음) · 부분 유니크 없음 · 데이터 적재 없음 · ims_is_admin() 무접촉.
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) role 넷 — CHECK 교체 (기존 manager/admin 은 그대로 유효) ═══
alter table public.ims_staff
  drop constraint if exists ims_staff_role_ck;
alter table public.ims_staff
  add constraint ims_staff_role_ck check (role in ('worker', 'supervisor', 'manager', 'admin'));

comment on column public.ims_staff.role is
  'worker = 창고 사람(기본 wms 방 · 화면·창고는 perms·warehouse_access) · supervisor = almost everything(창고 경계·기능 제한 없음 · 사람 관리만 못 한다) · manager = 창고가 걸린다(warehouse_access) + 화면은 perms · admin = 전부. 값은 WMS 와 같은 낱말(컷오버 때 wms_staff 를 옮기기 쉽게) · supervisor 만 IMS 신설. 기본값 manager. 판정은 ims_can_*() 함수가 한 곳에서(2026-09-17)';

-- ═══ 2) warehouse_access — uuid[] · 빈 배열 = 전부 ═══
alter table public.ims_staff
  add column if not exists warehouse_access uuid[] not null default '{}'::uuid[];

alter table public.ims_staff
  drop constraint if exists ims_staff_warehouse_access_no_null_ck;
alter table public.ims_staff
  add constraint ims_staff_warehouse_access_no_null_ck check (array_position(warehouse_access, null) is null);   -- 원소 null 금지(비교가 null 이 된다)

comment on column public.ims_staff.warehouse_access is
  'ref_warehouse.id 의 배열. ⭐ 빈 배열 = 전부 접근(supervisor·admin 은 비워 둔다 · manager·worker 만 채운다). FK 없음(배열) — 없는 id 는 그 창고만 조용히 안 열린다(닫히는 쪽). 판정은 ims_can_warehouse(uuid). WMS 매핑: toronto/edmonton → 해당 ref_warehouse.id · both → {} (2026-09-17)';

-- ═══ 3) perms 주석 — 값이 들어간다 ═══
comment on column public.ims_staff.perms is
  '두 축을 한 배열에: 모드 wms·ims / 화면 purchasing·master·receiving·staff (쓰기) · <screen>:read (읽기만). 값 목록은 ims_perm_catalog() 한 곳 · CHECK 없음(화면이 늘 때 표를 안 고친다 · 모르는 값은 함수가 false). ⭐ 더하기만 한다 — role 기본으로 열린 것을 perms 로 닫지 못한다. 판정은 ims_can_enter/view/write (2026-09-17)';

comment on table public.ims_staff is
  'IMS 사용자(Asung-IMS · 운영 wms_staff 와 별개). 열쇠 auth_user_id(=auth.uid()). ⭐ 2026-09-17 부터 창고 직원(worker)도 이 표에 들어온다 — ims.asung.ca 가 WMS 모드·IMS 모드를 가진다. role 넷 · perms 두 축 · warehouse_access(빈=전부). 쓰기는 admin 만(RLS · ims_is_admin()) · delete 없음. 정본 po-module §10-h';

-- ═══ 4) 알려진 값 한 곳 — ims_perm_catalog() ═══
-- immutable: 상수다. 화면이 늘면 이 함수만 create or replace 로 바꾼다(표 무접촉).
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
      "staff":      {"room": "ims", "label": "Staff (write is admin only)"}
    }
  }'::jsonb;
$$;
comment on function public.ims_perm_catalog() is
  'perms 의 알려진 값 한 곳 — modes 둘 · screens 넷(room 은 그 화면이 속한 방). ims_can_* 가 모르는 값을 false 로 답하는 근거 · perms 편집 UI 의 선택지. 화면이 늘면 여기만 바꾼다(2026-09-17)';
revoke all on function public.ims_perm_catalog() from public, anon;
grant execute on function public.ims_perm_catalog() to authenticated;

-- ═══ 5) 판정 함수 넷 — security definer(ims_staff 정책을 다시 타지 않는다 · ims_is_admin 과 같은 모양) ═══

-- ① 모드(방) 접근
create or replace function public.ims_can_enter(p_mode text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'modes' ? p_mode) then false            -- 모르는 모드 = false (admin 도)
      when s.role in ('admin', 'supervisor', 'manager') then true                   -- role 기본: 둘 다
      else                                                                          -- worker: 기본 wms · 그 외는 perms
           p_mode = 'wms'
        or s.perms ? p_mode
        or exists (                                                                 -- 그 방의 화면 값(쓰기·읽기)을 하나라도 가졌으면 방이 열린다
             select 1 from jsonb_each(public.ims_perm_catalog()->'screens') sc
             where sc.value->>'room' = p_mode
               and (s.perms ? sc.key or s.perms ? (sc.key || ':read')))
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_enter(text) is
  '호출자가 wms/ims 방에 들어갈 수 있는가. admin·supervisor·manager 둘 다 · worker 는 wms 기본 + perms(모드 토큰 또는 그 방의 화면 값). 모르는 값·비활성·행 없음 = false (2026-09-17)';
revoke all on function public.ims_can_enter(text) from public, anon;
grant execute on function public.ims_can_enter(text) to authenticated;

-- ② 화면 보기(읽기 전용 포함)
create or replace function public.ims_can_view(p_screen text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'screens' ? p_screen) then false        -- 모르는 화면 = false (admin 도)
      when s.role = 'admin' then true
      when s.role = 'supervisor' then p_screen <> 'staff' or s.perms ? p_screen    -- 사람 관리만 admin 몫 · 그래도 perms 로 더할 수는 있다(더하기 원칙)
      when s.role = 'worker'
           and public.ims_perm_catalog()->'screens'->p_screen->>'room' = 'wms' then true   -- 창고 사람은 wms 방 화면이 기본
      else s.perms ? p_screen or s.perms ? (p_screen || ':read')                   -- manager · worker(ims 방) = perms
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_view(text) is
  '호출자가 화면을 볼 수 있는가(:read 포함). admin 전부 · supervisor 는 staff 빼고 전부 · worker 는 wms 방 화면 기본 · 그 외 perms. 모르는 값·비활성·행 없음 = false (2026-09-17)';
revoke all on function public.ims_can_view(text) from public, anon;
grant execute on function public.ims_can_view(text) to authenticated;

-- ③ 화면 쓰기(':read' 만 있으면 false)
create or replace function public.ims_can_write(p_screen text) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when not (public.ims_perm_catalog()->'screens' ? p_screen) then false
      when s.role = 'admin' then true
      when p_screen = 'staff' then false                                            -- ⭐ staff 쓰기는 admin 만 — RLS(ims_is_admin) 와 같은 답
      when s.role = 'supervisor' then true
      when s.role = 'worker'
           and public.ims_perm_catalog()->'screens'->p_screen->>'room' = 'wms' then true
      else s.perms ? p_screen                                                       -- ':read' 는 세지 않는다
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_write(text) is
  '호출자가 화면에서 저장할 수 있는가. :read 만 가진 화면은 false. staff 는 admin 만(RLS 와 같은 답). ② 차수 RLS 의 insert/update with check 가 이 함수를 쓴다 (2026-09-17)';
revoke all on function public.ims_can_write(text) from public, anon;
grant execute on function public.ims_can_write(text) to authenticated;

-- ④ 창고 접근 — 빈 warehouse_access = 전부
create or replace function public.ims_can_warehouse(p_wh uuid) returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select coalesce((
    select case
      when s.role in ('admin', 'supervisor') then true                              -- 창고 경계 없음
      when cardinality(s.warehouse_access) = 0 then true                            -- ⭐ 빈 = 전부 (manager · worker)
      else p_wh = any (s.warehouse_access)                                          -- p_wh null → null → coalesce false
    end
    from public.ims_staff s
    where s.auth_user_id = auth.uid() and s.is_active
  ), false);
$$;
comment on function public.ims_can_warehouse(uuid) is
  '호출자가 그 창고(ref_warehouse.id)에 접근하는가. admin·supervisor 전부 · warehouse_access 빈 배열 = 전부 · 그 외 배열 포함 여부. p_wh null = false(문서에 창고가 없으면 정책이 따로 다룬다 · ② 차수) (2026-09-17)';
revoke all on function public.ims_can_warehouse(uuid) from public, anon;
grant execute on function public.ims_can_warehouse(uuid) to authenticated;

-- ═══ 6) 헤더용 한 번에 — ims_access() (위 넷을 부른다 · 화면이 판정을 다시 짜지 않게) ═══
create or replace function public.ims_access() returns jsonb
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'role',  s.role,
    'name',  s.name,
    'modes', (select coalesce(jsonb_agg(m) filter (where public.ims_can_enter(m)), '[]'::jsonb)
                from jsonb_array_elements_text(public.ims_perm_catalog()->'modes') m),
    'screens', (select jsonb_object_agg(k,
                  case when public.ims_can_write(k) then 'write'
                       when public.ims_can_view(k)  then 'read'
                       else null end)
                from jsonb_object_keys(public.ims_perm_catalog()->'screens') k),
    'warehouses', case when s.role in ('admin', 'supervisor') or cardinality(s.warehouse_access) = 0
                       then null                                                    -- null = 전부
                       else to_jsonb(s.warehouse_access) end
  )
  from public.ims_staff s
  where s.auth_user_id = auth.uid() and s.is_active;                                -- 행 없음·비활성 → null
$$;
comment on function public.ims_access() is
  '헤더가 로그인 직후 한 번 부른다 — {role, name, modes[], screens{screen: write|read|null}, warehouses: null(전부)|uuid[]}. 값은 ims_can_* 에서 나온다(화면이 판정을 복제하지 않는다). 행 없음·비활성 = null (2026-09-17)';
revoke all on function public.ims_access() from public, anon;
grant execute on function public.ims_access() to authenticated;
