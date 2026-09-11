-- PO 모듈 ① Settings — 로케이션·bin 표 신설: ref_warehouse · ref_bin (2026-09-11) · ① Settings 여덟 축 중 일곱 번째(사용자는 wms_staff 확장 · 별건)
--
-- 목표: 마이그레이션 1개 · 표 2개 · 행 적재 0건. 뼈대만 — Cin7 에서 긁어오는 것은 별도 작업(EF·뷰·RPC 없음).
-- 선행: 20260911144606(ref_brand·category·unit + set_updated_at()) · 161647(ref_payment_term) · 162906(ref_account) · 164513(ref_currency)
-- ⚠️⚠️ 앞선 넷과 가장 다르다 — 표가 둘이고 둘 사이에 FK 가 있다(ref_ 표 사이의 첫 FK).
--
-- ═══ 실측 근거 (2026-09-11 GAS 프로브 · GET /ref/location 전량 2,678행) ═══
--   ParentID 없음(= 창고) 3 · ParentID 있음(= bin) 2,675(토론토 2,047 · 에드먼튼 628)
--   창고 셋: Asung Trading Inc.(f1ca3946-… · North York ON · IsDefault=true · Bins 2,047) · Asung - Edmonton(623edcaa-… · Edmonton AB · Bins 628)
--           · Production Facility(6160ca1b-… · 주소 전부 null · IsShopFloor=true · Bins 0 · 미사용)
--   필드 17: AddressCitySuburb·AddressCountry·AddressLine1·AddressLine2·AddressStateProvince·AddressZipPostCode·Bins·FixedAssetsLocation·ID·IsCoMan·IsDefault·IsDeprecated·IsShopFloor·IsStaging·Name·ParentID·PickZones
--   ⭐ 정정: 하위 행(bin)의 Name 이 곧 bin 이름이다 — Bins[] 원소 {ID,Name,IsDeprecated,IsStaging} 의 Name 과 2,675/2,675 일치 · 숫자만인 이름 0 · 20자 이상 0.
--     (cin7-api 스킬의 「child-location Name 은 바코드류」는 틀렸다 — 스킬 정정은 별도 작업 · 여기는 기록만)
--   PickZones 채워진 하위 행 0(bin 별 zone 은 Cin7 에 없다 · 창고 행에 "Zone1,…,Zone5" 문자열 하나) · IsDeprecated 하위 행 0
--   ⚠️ 창고 행의 주소 칸은 값이 있고 bin 행은 전부 빈 문자열('') — null 이 아니다(적재 시 '' → null 로 받을 것 · 이번 범위 아님)
--
-- ═══ §1 확인 결과 (2026-09-11 · 테스트 DB Asung-IMS 읽기) ═══
--   ① 공통 여덟 칸 정본 = ref_account 실물: id uuid PK gen_random_uuid() · cin7_id uuid(null 허용) · name text not null · is_active boolean not null default true
--      · source text not null default 'cin7' · note text · created_at/updated_at timestamptz not null default now()
--   ② ref_ 여섯(account·brand·category·currency·payment_term·unit) — ref_warehouse·ref_bin 충돌 없음
--   ③ ⭐ 기존 FK 22건의 관례: on delete CASCADE 7(문서→소유 라인: wms_order_lines·pick/pack_task_lines·receipt_lines·discrepancies…) ·
--      NO ACTION 13(참조: inv_layer_consume.layer_id · wms_pallet_items.order_line_id · wms_pick_tasks.wave_id …) · SET NULL 2(로그: wms_reports·wms_rollback_log.order_id)
--      · RESTRICT 0 · on update 는 전부 NO ACTION · ⭐ FK 컬럼엔 예외 없이 인덱스(inv_ 계열 이름 <표>_<컬럼>_idx · wms_ 계열 idx_<…>)
--      ⇒ 이 FK 는 「참조」 관례를 따라 on delete no action(명시) · on update 기본 · 인덱스 ref_bin_warehouse_idx.
--         cascade 는 쓰지 않는다(Caleb 지시 · 창고 한 줄에 bin 2,047개가 조용히 딸려 사라진다). restrict 와 no action 은 둘 다 막는다 —
--         차이는 검사 시점(restrict 즉시 · no action 문장 끝)뿐이고 기존 표에 restrict 가 0건이라 관례 쪽을 택했다.
--   ④ set_updated_at 정의 1개 · security definer 아님 ⇒ 재사용만(여기서 다시 만들지 않는다)
--
-- ═══ 설계 판단 (Caleb 확정 2026-09-11) ═══
--   · 표를 둘로 나눈다 — Cin7 은 한 표 + ParentID 자기참조지만, 창고 3 · bin 2,675 로 규모가 다르고 주소·회계 의미는 창고에만 있으며,
--     ⭐ inv_ledger 가 이미 warehouse 와 bin 을 별개 칸으로 둔다(한 표면 쓰는 쪽이 매번 갈라야 한다).
--   · Production Facility 도 담는다(적재 시 is_active=false) — Cin7 에 실재하고 삭제 불가한 시스템 창고. 없으면 갈 곳 없는 참조가 생긴다(ref_account 의 ARCHIVED 76개를 담은 것과 같은 판단).
--   · ⚠️ IN_TRANSIT 은 담지 않는다 — 원장이 만든 합성 창고(이름의 밑줄 = Cin7 원문 아님). 마스터는 실재하는 장소의 목록이다. 원장이 마스터를 참조하게 되면 그때 한 줄(아직 정해진 일 아님).
--   · zone 은 칸만 두고 비운다 — Cin7 이 bin 별 zone 을 주지 않는다. wms_sku_bins 에 있지만 ⚠️ 마스터가 WMS 표를 읽으면 안 된다(원칙 2 · 레고). 채우는 방법은 별도 판단.
--   · ⚠️ 담지 않는 Cin7 창고 필드 — FixedAssetsLocation·IsCoMan·IsShopFloor·IsStaging 넷은 우리 실무와 무관한 Cin7 기능 플래그(IsShopFloor 만 Production Facility 에 true 인데 그 창고 자체를 안 쓴다) ·
--     PickZones 는 문자열 하나라 구조가 없다(위 zone 판단) · Bins 는 ref_bin 이 된다.
--   · ⭐ is_default 를 **표에 둔다** — ref_payment_term 의 IsDefault 와 ref_currency 의 기준통화는 inv_config 로 보냈는데 여기만 다르다. 결함이 아니다:
--     창고의 is_default 는 「이 창고가 기본인가」라는 창고의 속성이고 Cin7 이 창고 행에 직접 담아 준다(IsDefault=true · Asung Trading Inc.) ⇒ 긁어올 때 받을 자리가 필요하다.
--     결제조건·통화의 기본값은 Cin7 이 그렇게 주지 않거나(통화는 목록 자체가 없다) 「새로 만들 때 무엇을 고를까」라는 설정이었다.
--     ⚠️ 둘이 true 되는 것을 제약으로 막지 않는다 — 부분 유니크가 필요해지는데 금지(WMS 규칙 29). 창고가 셋뿐이라 눈으로 보인다.
--   · ref_warehouse.name 은 유니크 — 창고는 셋이고 이름이 곧 식별자. ⭐ inv_ledger.warehouse 와 wms_orders.location 이 이 이름 문자열을 그대로 쓴다 — 나중에 잇는 고리가 name 이다.
--   · ⚠️⚠️ ref_bin.name 은 단독 유니크 없음 — bin 이름은 창고 안에서만 유일하다 ⇒ unique (warehouse_id, name). 지금은 접두어가 갈려(A… 토론토 · E… 에드먼튼) 전역 중복 0 이지만 오늘의 우연이지 규칙이 아니다.
--   · ref_bin 에 주소 칸 없음(bin 행 주소는 전부 빈 문자열) · IsDeprecated 는 is_active 로 흡수(앞선 표들과 같은 방식 · 지금 0건).
--
-- 📌 ⚠️⚠️ ref_bin 은 2,675행 예정 — PostgREST 1,000행 캡을 넘는 첫 마스터다. 모르고 전량을 읽으면 에러 없이 1,000개만 온다. 전량 조회는 페이징 또는 jsonb_agg RPC.

-- ── ref_warehouse (먼저 — FK 순서) ──
create table if not exists ref_warehouse (
  id             uuid primary key default gen_random_uuid(),
  cin7_id        uuid unique,
  name           text not null unique,
  is_active      boolean not null default true,
  source         text not null default 'cin7',
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  address_line1  text,
  address_line2  text,
  city           text,
  state_province text,
  postal_code    text,
  country        text,
  is_default     boolean not null default false,
  constraint ref_warehouse_source_ck check (source in ('cin7','manual'))
);
comment on table ref_warehouse is 'Cin7 ref/location 의 ParentID 없는 행 대응 · PO 모듈 Settings 마스터(캐시 아님 · 우리 키 id · cin7_id 는 매핑) · name 이 inv_ledger.warehouse·wms_orders.location 과 잇는 고리 · ⚠️ IN_TRANSIT 은 원장의 합성 창고라 담지 않는다 · 2026-09-11 신설';
comment on column ref_warehouse.is_default is 'Cin7 IsDefault 그대로(창고의 속성 · Cin7 이 창고 행에 담아 준다 ⇒ 받을 자리). ⚠️ ref_payment_term·ref_currency 의 기본값은 inv_config 로 보냈는데 여기만 표에 둔 것은 결함이 아니다 — 그쪽은 「새로 만들 때 무엇을 고를까」 설정이었다. 둘이 true 되는 것을 제약으로 막지 않는다(부분 유니크 금지 · 창고 셋이라 눈으로 보인다)';

-- ── ref_bin (뒤 — ref_warehouse 를 참조) ──
create table if not exists ref_bin (
  id           uuid primary key default gen_random_uuid(),
  cin7_id      uuid unique,
  name         text not null,
  is_active    boolean not null default true,
  source       text not null default 'cin7',
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  warehouse_id uuid not null references ref_warehouse(id) on delete no action,
  zone         text,
  is_staging   boolean not null default false,
  constraint ref_bin_source_ck check (source in ('cin7','manual')),
  constraint ref_bin_warehouse_id_name_key unique (warehouse_id, name)
);
create index ref_bin_warehouse_idx on ref_bin (warehouse_id);
comment on table ref_bin is 'Cin7 ref/location 의 ParentID 있는 행 대응(bin 이름 = 하위 행 Name · IsDeprecated → is_active) · PO 모듈 Settings 마스터(캐시 아님) · name 은 창고 안에서만 유일(unique(warehouse_id,name)) · ⚠️⚠️ 2,675행 예정 — PostgREST 1,000행 캡을 넘는다. 전량을 읽는 코드는 반드시 페이징하거나 jsonb_agg RPC 를 쓸 것 · 2026-09-11 신설';
comment on column ref_bin.warehouse_id is 'FK → ref_warehouse(id) · on delete no action(기존 참조 FK 관례 · cascade 금지 — 창고 한 줄에 bin 2,047개가 딸려 사라진다) · 인덱스 ref_bin_warehouse_idx(Postgres 는 FK 에 자동 인덱스를 만들지 않는다 · 창고로 거르는 조회가 기본 패턴)';
comment on column ref_bin.zone is '⚠️ 비워 둔다 — Cin7 은 bin 별 zone 을 주지 않는다(창고 행 PickZones 문자열 하나 · 하위 행 0건). wms_sku_bins 에는 있지만 마스터가 WMS 표를 읽으면 안 된다(원칙 2). 채우는 방법 미정';

-- ── updated_at 트리거 — 공용 함수 set_updated_at() 재사용(다시 만들지 않는다) ──
create trigger ref_warehouse_set_updated_at before update on ref_warehouse for each row execute function set_updated_at();
create trigger ref_bin_set_updated_at       before update on ref_bin       for each row execute function set_updated_at();

-- ── RLS · 권한 — 선행 표와 동일: auth_all + revoke anon · ⚠️ DELETE·TRUNCATE 는 authenticated 에서 막는다(마스터 · is_active 로 물러나게 한다) ──
alter table ref_warehouse enable row level security;
alter table ref_bin       enable row level security;
create policy auth_all on ref_warehouse for all to authenticated using (true) with check (true);
create policy auth_all on ref_bin       for all to authenticated using (true) with check (true);
revoke all on ref_warehouse from anon;
revoke all on ref_bin       from anon;
revoke delete, truncate on ref_warehouse from authenticated;
revoke delete, truncate on ref_bin       from authenticated;
