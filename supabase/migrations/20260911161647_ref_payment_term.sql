-- PO 모듈 ① Settings — 결제조건 표 신설: ref_payment_term (2026-09-11)
--
-- 목표: 마이그레이션 1개 · 표 1개 · 행 적재 0건. 뼈대만 — Cin7 에서 긁어오는 것도 값을 채우는 것도 별도 작업.
-- 선행: 20260911144606_ref_settings_brand_category_unit.sql (ref_brand·ref_category·ref_unit · 공통 여덟 칸 · 관례). ⚠️ 그 모양을 그대로 따른다.
-- 왜 지금: ② 공급처 표가 결제조건을 바로 참조한다([실측] 공급처 226곳의 PaymentTerm 이 ref/paymentterm 의 Name 과 226/226 이름 일치). 참조되는 쪽을 먼저 세운다.
--   ⭐ Cin7 은 마스터를 GUID 가 아니라 이름 문자열로 잇는다(선행 작업에서 확정).
--
-- ═══ 실측 근거 (2026-09-11 GAS 프로브 전량) — GET /ref/paymentterm · Total 34 · 필드 ID·Name·Duration·Method·IsActive·IsDefault ═══
--   IsActive true 17/34 · IsDefault = C.B.S (Cash Before Shipment) 하나 · Method 34개 전부 'number of days'(⇒ 칸을 만들지 않는다 — 값이 하나뿐인 칸은 아무것도 구별하지 않는다).
--   활성 17 (Name(Duration)): 1% Warehouse Allowance + 2%10 Net30(10) · 1%30 Net31(30) · 2%10 Net30(10) · 2%19 Net30(19) · 2%30 Net31(30) · 2.1%13 Net30(13) ·
--     50% COD & 50% N30(30) · C.B.S (Cash Before Shipment)(0) · C.O.D(0) · Due on receipt(0) · Net 14(14) · Net 15(15) · Net 21(21) · Net 30(30) · Net 45(45) · Net 60(60) · Net 7(7)
--   공급처 226곳이 실제로 쓰는 14종: Due on receipt 92 · C.B.S 59 · Net 30 33 · Net30 21 · C.O.D 4 · Net 60 3 · 1%30 Net31 3 · 2%10 Net30 2 · Net45 2 · Net 45 2 · 2%19 Net30 2 · 2%30 Net31 1 · Net 15 1 · 1%20 Net30 1
--   ⚠️ 띄어쓰기만 다른 같은 조건이 따로 있고 공급처가 양쪽에 나뉘어 있다 — Net 30(33)/Net30(21) · Net 45(2)/Net45(2). ⚠️ Net30·Net45·1%20 Net30 은 비활성인데 공급처 24곳이 여전히 쓴다.
--
-- ═══ ⚠️⚠️ Cin7 Duration 을 기일로 쓰면 안 된다 (Caleb 확인 2026-09-11) ═══
--   「2%10 Net30」= 기일 30일 · 단 10일 안에 내면 2% 할인(회계 관용 표기). Cin7 Duration 은 **10** — 칸이 하나라 할인 기한 쪽을 담았다.
--   그대로 기일 계산에 쓰면 20일이 당겨져 아직 기한이 남은 건이 연체로 잡힌다. ⇒ ⭐ 우리는 칸을 나눠 담는다(net_days · discount_days · discount_percent · is_split) —
--   Cin7 이 못 담는 것을 우리가 담는 첫 사례(ims-principles.md 원칙 1 · Cin7 구조를 베끼는 것이 아니다).
--
-- ═══ 공통 여덟 칸 — ref_brand 실물(테스트 DB 2026-09-11 information_schema)과 완전히 같다 ═══
--   id uuid PK gen_random_uuid() · cin7_id uuid unique(plain · null 허용 · 부분 유니크 금지 · WMS 규칙 29) · name text not null unique · is_active boolean not null default true ·
--   source text not null default 'cin7' check in ('cin7','manual') · note text · created_at/updated_at timestamptz not null default now() · updated_at 은 공용 트리거 set_updated_at() 재사용.
-- ═══ 이 표에만 있는 네 칸 — ⚠️⚠️ 이번에 값을 넣지 않는다(셋은 null · is_split 은 default false) ═══
--   net_days integer            ⭐ 최종 기일 — 2%10 Net30 이면 30. 실제 계산에 쓰는 값
--   discount_days integer       조기 결제 할인 기한 — 2%10 Net30 이면 10 · 할인 없으면 null
--   discount_percent numeric    할인율 — 2%10 Net30 이면 2 · 할인 없으면 null
--   is_split boolean not null default false   ⭐ 분할 결제 표시 — 숫자 한 칸으로 안 담기는 조건. 실물 「50% COD & 50% Net30」(Avlon · 절반 즉시 · 절반 30일) → net_days=30 + is_split=true
--     (⚠️ Cin7 공급처 마스터에는 아직 C.O.D 로 남아 있다)
--   ⭐ 값은 손으로 채운다 — 이름에서 숫자를 뽑는 파싱을 하지 않는다. 표기가 흔들린다(Net31 · N30 · 1% Warehouse Allowance + 2%10 Net30). 17개뿐이고 자주 늘지 않는다
--     (Caleb 판정 · 스킬 「SKU 접미사 파싱 금지」 계열). ⚠️ 파서·정규식·split_part 로 채우는 코드 금지.
-- ═══ 넣지 않는 것 ═══
--   method(전부 number of days) · is_default(⭐ inv_config 로 간다 — 표 안에 두면 둘이 true 되는 것을 막을 수단이 부분 유니크뿐 · 「새 공급처의 기본값」은 설정값 · ⚠️ 이번에 inv_config 행은 넣지 않는다) ·
--   canonical_id 류 통합 칸(⭐ Caleb 판정: 표에는 정리된 것만 남긴다 — 띄어쓰기 흔들림은 불러올 때 매칭이 흡수) · sort_order(Cin7 이 안 주고 실무 요구 없음).
-- 📌 매칭은 여기서 만들지 않는다 — 불러오는 코드의 일. 원칙 하나만 정해졌다: 정확히 못 이으면 비워 두고 센다(억지로 붙이면 Net 30/Net 45 를 헷갈려 기일이 15일 틀린다).
--   Caleb 방침: Cin7 값을 그대로 불러온 뒤 사람이 전수 검사 ⇒ 이 표는 활성 17개(띄어쓰기 중복 포함)를 그대로 받을 수 있어야 하고, 정리는 is_active 를 끄는 것으로. ⭐ source 가 그 검사의 근거(cin7 vs manual · 재동기화가 손댄 것을 덮지 않게).
-- 📌 나머지 Settings 넷(로케이션·bin · 계정과목 · 통화 · 사용자)은 따로 지시된다.

-- ── ref_payment_term ──
create table if not exists ref_payment_term (
  id               uuid primary key default gen_random_uuid(),
  cin7_id          uuid unique,
  name             text not null unique,
  is_active        boolean not null default true,
  source           text not null default 'cin7',
  note             text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  net_days         integer,
  discount_days    integer,
  discount_percent numeric,
  is_split         boolean not null default false,
  constraint ref_payment_term_source_ck check (source in ('cin7','manual'))
);
comment on table  ref_payment_term is 'Cin7 ref/paymentterm 대응 · PO 모듈 Settings 마스터(캐시 아님) · ⚠️ Cin7 Duration 은 할인 기한이라 net_days 와 다르다 · 2026-09-11 신설';
comment on column ref_payment_term.net_days         is '⭐ 최종 기일(일). 「2%10 Net30」= 30. 실제 기일 계산에 쓰는 값. ⚠️ Cin7 Duration(=10 · 할인 기한)을 여기에 넣으면 20일 당겨져 연체 오판 — 손으로 채운다(파싱 금지)';
comment on column ref_payment_term.discount_days    is '조기 결제 할인 기한(일). 「2%10 Net30」= 10 · 할인 없으면 null. Cin7 Duration 이 담고 있던 값이 이쪽이다';
comment on column ref_payment_term.discount_percent is '조기 결제 할인율(%). 「2%10 Net30」= 2 · 할인 없으면 null';
comment on column ref_payment_term.is_split         is '⭐ 분할 결제 — 숫자 한 칸으로 안 담기는 조건. 실물 「50% COD & 50% Net30」→ net_days=30 + is_split=true. default false · 값은 손으로';

-- ── updated_at 트리거 — 공용 함수 set_updated_at() **재사용**(20260911144606 에서 만들었다 · 여기서 다시 만들지 않는다) ──
create trigger ref_payment_term_set_updated_at before update on ref_payment_term for each row execute function set_updated_at();

-- ── RLS · 권한 — 선행 표와 동일(auth_all + revoke anon · service_role 개방 없음 · DELETE·TRUNCATE 는 authenticated 에서 막는다 — 마스터는 is_active 로 물러나게 한다) ──
alter table ref_payment_term enable row level security;
create policy auth_all on ref_payment_term for all to authenticated using (true) with check (true);
revoke all on ref_payment_term from anon;
revoke delete, truncate on ref_payment_term from authenticated;
