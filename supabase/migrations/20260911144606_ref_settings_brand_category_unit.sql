-- PO 모듈 ① Settings — 단순 셋 표 신설: ref_brand · ref_category · ref_unit (2026-09-11)
--
-- 목표: 마이그레이션 1개 · 표 3개 · 행 적재 0건. 뼈대만 — Cin7 에서 긁어오는 것은 별도 작업(EF 없음 · 뷰·RPC 없음).
-- 배경: IMS PO 모듈의 첫 조각(순서 ① Settings → ② 공급처 → ③ 제품 → ④ 제품↔공급처 → ⑤ PO 본체 · Caleb 확정).
--   테스트 DB 에 마스터 표는 하나도 없었다(47개 표 전부 inv_*·wms_*). wms_sku_snapshot·wms_sku_bins·inv_sku_types 는 Cin7 캐시라 마스터가 아니다.
-- 원칙(docs/design/ims-principles.md): ① Cin7 독립 — Cin7 구조를 베끼지 않고 우리 것을 만들고 Cin7 을 매핑한다 ② 레고 — 어느 모듈의 소유도 아닌 공용 마스터라 접두어 ref_
--   (Cin7 이 이 계열을 Reference Books 로 부른다).
--
-- ═══ 실측 근거 (2026-09-11 GAS 프로브 전량) ═══
--   GET /ref/brand     Total 415 · 필드 ID(guid)·Name 둘뿐 · 이름 중복 0
--   GET /ref/category  Total  19 · 필드 ID·Name · 전부 서로 다름 · ⚠️ 제품 아닌 것 섞임(Liability·Service·Unclassified·Other) — 거르지 않는다(③ 제품 단계의 판단)
--   GET /ref/unit      Total  44 · 필드 ID·Name · 전부 서로 다름 · ⚠️ 44개 중 39개가 숫자 이름(2·12·1200·960…) · 글자는 DP·EA·EA-ALT-UPC·Item·JAR 다섯
--     ⇒ Cin7 UOM 은 사실상 케이스 입수 수량으로 쓰인다. ⚠️ name 을 numeric 으로 두거나 파싱·CHECK 하지 않는다 — text 다(SKU 접미사 파싱 금지 · AMP41108-12 의 UOM="6" 원본 오류 계열).
--   ⭐ Cin7 은 마스터를 GUID 가 아니라 **이름 문자열**로 참조한다 — 제품 30행의 Brand·Category·UOM 이 이름 일치 100% · GUID꼴 0 · 공급처 226곳 PaymentTerm 226/226 이름 일치.
--     ⇒ 나중에 긁어올 때 연결 고리는 name 이다. cin7_id 는 안정성을 위해 함께 담되 매핑 실패 시 이름으로 붙일 수 있어야 한다.
--
-- ═══ §2 확인 결과 (2026-09-11 · 테스트 DB Asung-IMS 읽기) — 이 표의 모양을 정한 관례 ═══
--   ① 이름 충돌 없음(ref_brand·ref_category·ref_unit 0행).
--   ② 기존 표: inv_config(key·value·note·updated_at default now()) · inv_sku_types(refreshed_at) · wms_staff(bigint id · active boolean default true · created_at/updated_at default now() · nullable).
--   ③ RLS: 세 표 모두 정책 하나 — auth_all · ALL · {authenticated} · using(true) with check(true) + revoke all from anon. service_role 개방 없음.
--   ④ 트리거: public 스키마에 트리거 **0개** — updated_at 은 어디서도 트리거로 갱신하지 않는다(default now() 만 · 갱신은 쓰는 쪽 책임).
--   ⇒ auth_all + revoke anon 은 관례 그대로. 원장 append-only 는 정책이 아니라 관례라 베낄 것도 없다 — 마스터는 수정이 정상(오타 수정).
--   ⚠️ 관례와 다르게 간 것 둘 (Caleb 판정 2026-09-11 · §7 보고 ⑥ 에 대한 판정):
--   · DELETE·TRUNCATE 를 authenticated 에서 **막는다** — inv_config·inv_sku_types 는 지워도 다시 만들 수 있는 캐시·설정이지만 마스터는 아니다.
--     브랜드 한 줄을 지우면 그것을 가리키던 제품이 갈 곳을 잃는다 — 그래서 is_active 를 둔 것이다. 선례는 inv_voided_docs·inv_doc_cost 쪽(관례가 둘이고 이쪽이 성격에 맞다).
--   · updated_at 은 **트리거로 갱신한다** — public 스키마의 첫 트리거다. 쓰는 쪽이 매번 실어 주는 방식은 빠뜨려도 에러가 안 나고 어느 카운터에도 안 잡힌다
--     (감지되지 않는 결함 · ims-principles.md §1-a). 표가 비어 있는 지금이 넣기 가장 안전하다. 공용 함수 하나(set_updated_at · 접두어 없음 — 앞으로 마스터 계열 전부가 쓴다 ·
--     ②공급처·③제품 표가 ref_ 접두어가 아닐 수 있어 ref_ 를 붙이지 않았다) + 표당 트리거 하나 · before update · for each row · security definer 없음.
--   · name 유니크는 plain 그대로 — lower(name) 로 바꾸지 않는다. 이 부류의 실제 사례는 대소문자가 아니라 띄어쓰기다(Cin7 결제조건 「Net 30」/「Net30」 · 공급처 33곳/21곳).
--     lower() 로는 못 막으므로 제약이 아니라 ① 결제조건 표에서 실물을 보고 판단할 문제다.
--
-- ═══ 컬럼 — 셋 다 같은 모양 ═══
--   id uuid PK gen_random_uuid()      ⭐ 우리 키. Cin7 GUID 를 PK 로 쓰면 Cin7 이 사라질 때 신원이 사라진다(ims-principles §4-b)
--   cin7_id uuid unique · null 허용   Cin7 행과의 매핑 · 우리가 새로 만든 것은 null. ⚠️ plain unique — 부분 유니크 인덱스 금지(PostgREST on_conflict 를 깨뜨린 WMS 규칙 29) · null 은 서로 충돌하지 않는다
--   name text not null unique         실측 중복 0 · Cin7 이 이름으로 참조하므로 실질 자연키
--   is_active boolean not null default true   ⭐ Cin7 에 없는 우리 칸 — 지우지 않고 물러나게 하는 수단
--   source text not null default 'cin7' check in ('cin7','manual')   Cin7 에서 온 행인지 우리가 만든 것인지 — 동기화가 덮어써도 되는지의 근거
--   note text                          사람 메모(inv_config.note 선례)
--   created_at / updated_at timestamptz not null default now()   updated_at 은 트리거 set_updated_at() 이 갱신(위 판정 · §2-④ 관례에서 벗어남)
--   ⚠️ sort_order 는 넣지 않는다 — Cin7 이 주지 않고 실무 요구도 없다. 빈 표에 컬럼 추가는 공짜다.
--
-- 📌 브랜드 415행은 PostgREST 1,000행 캡 아래지만 여유가 585행뿐이다 — 화면에서 전량을 읽는 코드는 캡을 의식할 것(이번 범위 아님).
-- 📌 나머지 Settings 다섯(로케이션·bin · 결제조건 · 계정과목 · 통화 · 사용자)은 따로 지시된다 — 여기서 만들지 않는다.

-- ── 공용 트리거 함수 — updated_at 갱신 (public 첫 트리거 · 마스터 계열 공용 · security definer 없음) ──
--   returns trigger 함수는 SQL 로 직접 호출할 수 없어 PostgREST RPC 로 노출되지 않는다 — RPC 관례의 revoke/grant 가 필요 없다.
create or replace function set_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- ── ref_brand ──
create table if not exists ref_brand (
  id         uuid primary key default gen_random_uuid(),
  cin7_id    uuid unique,
  name       text not null unique,
  is_active  boolean not null default true,
  source     text not null default 'cin7',
  note       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ref_brand_source_ck check (source in ('cin7','manual'))
);
comment on table ref_brand is 'Cin7 ref/brand 대응 · PO 모듈 Settings 마스터(캐시 아님 · 우리 키 id · cin7_id 는 매핑) · 2026-09-11 신설';

-- ── ref_category ──
create table if not exists ref_category (
  id         uuid primary key default gen_random_uuid(),
  cin7_id    uuid unique,
  name       text not null unique,
  is_active  boolean not null default true,
  source     text not null default 'cin7',
  note       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ref_category_source_ck check (source in ('cin7','manual'))
);
comment on table ref_category is 'Cin7 ref/category 대응 · PO 모듈 Settings 마스터(캐시 아님 · 제품 아닌 카테고리도 그대로 담는다) · 2026-09-11 신설';

-- ── ref_unit ──
create table if not exists ref_unit (
  id         uuid primary key default gen_random_uuid(),
  cin7_id    uuid unique,
  name       text not null unique,
  is_active  boolean not null default true,
  source     text not null default 'cin7',
  note       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ref_unit_source_ck check (source in ('cin7','manual'))
);
comment on table ref_unit is 'Cin7 ref/unit 대응(UOM · name 은 text — 39/44 가 숫자 이름이지만 파싱하지 않는다) · PO 모듈 Settings 마스터(캐시 아님) · 2026-09-11 신설';

-- ── updated_at 트리거 — 표당 하나 (Caleb 판정 2026-09-11) ──
create trigger ref_brand_set_updated_at    before update on ref_brand    for each row execute function set_updated_at();
create trigger ref_category_set_updated_at before update on ref_category for each row execute function set_updated_at();
create trigger ref_unit_set_updated_at     before update on ref_unit     for each row execute function set_updated_at();

-- ── RLS · 권한 — auth_all + revoke anon(§2-③ 관례) · service_role 개방 없음 · ⚠️ DELETE·TRUNCATE 는 authenticated 에서 막는다(마스터 · is_active 로 물러나게 한다 · Caleb 판정) ──
alter table ref_brand    enable row level security;
alter table ref_category enable row level security;
alter table ref_unit     enable row level security;
create policy auth_all on ref_brand    for all to authenticated using (true) with check (true);
create policy auth_all on ref_category for all to authenticated using (true) with check (true);
create policy auth_all on ref_unit     for all to authenticated using (true) with check (true);
revoke all on ref_brand    from anon;
revoke all on ref_category from anon;
revoke all on ref_unit     from anon;
revoke delete, truncate on ref_brand    from authenticated;
revoke delete, truncate on ref_category from authenticated;
revoke delete, truncate on ref_unit     from authenticated;
