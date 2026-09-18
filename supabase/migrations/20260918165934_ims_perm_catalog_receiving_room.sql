-- ─────────────────────────────────────────────────────────────
-- ims_perm_catalog() — receiving 의 room 을 'wms' → 'ims' (Asung-IMS) · 2026-09-18
--
-- 왜: 지금 세우는 리시빙(20260918161537 표 셋 · 20260918163552 RPC · 화면 receiving.html)은 PO 문서의 한 갈래다 —
--     인보이스·비용·결제와 같은 층이라 IMS 모드의 탭 줄에서 구매 넷 뒤에 선다(Caleb 2026-09-18).
--     나중에 WMS 를 옮겨 오면 창고 작업 화면이 WMS 모드에 따로 선다(같은 표 · 화면은 둘) — 지금 것을 wms 로 두면 그 자리가 헷갈린다.
-- 앞 정의: 20260918023000(라벨) ← 20260918020000 ← 20260917230000. 이 파일이 넷째 정의 · 값은 receiving.room 하나만 · 라벨·modes·나머지 셋 그대로.
-- immutable · 시그니처 무변 ⇒ create or replace(grant·comment 유지).
--
-- ⚠️⚠️ 값만 바뀌는 것이 아니다 — room 을 읽는 함수 셋의 판정이 함께 바뀐다(20260918020000 · 20260917230000 본문 확인):
--   ① ims_can_view/ims_can_write(p_screen): 「worker 는 room='wms' 화면이 기본」 ⇒ 이제 worker 에게 receiving 이 **기본으로 열리지 않는다**.
--      worker 가 리시빙을 쓰려면 perms 에 'receiving'(쓰기) 또는 'receiving:read' 를 준다(staff.html 권한 편집). admin·supervisor 는 무변 · manager 는 전부터 perms.
--   ② ims_can_enter('ims'): perms 에 receiving 을 가진 worker 는 ims 방이 열린다(그 방의 화면 값을 하나라도 가지면) — 탭 줄이 IMS 모드에 서는 것과 맞다.
--   ③ ims_can_enter('wms'): worker 기본 그대로 — 다만 wms 방에 화면이 하나도 없어져 탭 줄에 WMS 모드는 그려지지 않는다(ims-auth.js setupTabs · vis.some).
--   화면 쪽(asung-ims) 에는 room 값을 읽어 가르는 코드가 없다(2026-09-18 grep 전수 · staff.html 은 안내 문장 둘뿐).
-- ─────────────────────────────────────────────────────────────

create or replace function public.ims_perm_catalog() returns jsonb
  language sql immutable
  set search_path = public, pg_temp
as $$
  select '{
    "modes": ["wms", "ims"],
    "screens": {
      "purchasing": {"room": "ims", "label": "Purchase orders, invoices, charges, payments"},
      "master":     {"room": "ims", "label": "Settings, suppliers, products, families, supplier products"},
      "receiving":  {"room": "ims", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"}
    }
  }'::jsonb;
$$;
comment on function public.ims_perm_catalog() is
  'perms 의 알려진 값 한 곳 — modes 둘 · screens 넷(room 은 그 화면이 속한 방). ims_can_* 가 모르는 값을 false 로 답하는 근거 · perms 편집 UI(staff.html)의 선택지. 화면이 늘면 여기만 바꾼다(2026-09-17). ⭐ 2026-09-18 receiving.room wms→ims — 지금 리시빙은 PO 문서의 갈래(IMS 모드) · WMS 창고 작업 화면은 나중에 따로. ⚠️ 그 결과 worker 에게 receiving 은 기본이 아니라 perms 다';

-- 검증(회신에 따로): select key, value->>'room' as room, value->>'label' as label from jsonb_each(ims_perm_catalog()->'screens') order by 1;
