-- ─────────────────────────────────────────────────────────────
-- ims_perm_catalog() — 'staff' 라벨 정정 (Asung-IMS) · 2026-09-17 밤
--
-- 왜: 20260917230000 의 라벨 「Staff (write is admin only)」는 20260918020000(직원 관리 = staff 쓰기 권한 + 자기보다 아래 등급)으로 틀린 문장이 됐다.
--     20260918020000 §4 가 「Staff (people below your own role)」로 한 번 고쳤고, 이 파일이 Caleb 의 문구로 다시 낸다 — 이 함수 하나만.
-- ⚠️ 값(modes 둘 · screens 넷 · room)은 그대로 — 라벨만. 이 라벨은 perms 편집 UI(staff.html · 다음 차수)가 선택지 옆에 그린다.
-- immutable · 시그니처 무변 ⇒ create or replace(grant·comment 유지).
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
      "receiving":  {"room": "wms", "label": "Receiving and putaway"},
      "staff":      {"room": "ims", "label": "Adding and editing people (below your own rank)"}
    }
  }'::jsonb;
$$;

-- 검증: select ims_perm_catalog()->'screens'->'staff'->>'label';   → Adding and editing people (below your own rank)
