-- PO 모듈 ① Settings — 통화 표 신설: ref_currency + inv_config.base_currency (2026-09-11)
--
-- 목표: 마이그레이션 1개 · 표 1개 · ⭐ 표에 2행(CAD·USD) · inv_config 에 1행(base_currency=CAD). 앞선 넷(brand·category·unit·payment_term·account = 행 0건)에서 벗어나는 유일한 예외 — 이유는 아래 §값.
-- 선행: 20260911144606(ref_brand·ref_category·ref_unit) · 20260911161647(ref_payment_term) · 20260911162906(ref_account · 자연키 code). 관례(auth_all · revoke anon · revoke delete/truncate · set_updated_at 재사용)는 같다.
--
-- ═══ 실무·실측 근거 (Caleb 확인 2026-09-11 · 공급처 226곳 프로브) ═══
--   기준통화 CAD · 수입 결제 대부분 USD · KRW 는 결제만 원화로 하고 인보이스는 USD 로 받는다 ⇒ 거래 통화는 USD. [실측] 공급처 Currency = USD 159 · CAD 67 · KRW 0 — 실무 설명과 일치.
--   ⇒ ⭐ 시스템이 다루는 통화는 CAD · USD 둘. KRW 는 송금 수단이지 거래 통화가 아니다 — 넣지 않는다(넣으면 「KRW 거래 공급처가 있다」는 틀린 인상). 생기면 그때 한 줄.
--   공급처당 기본 통화는 하나(Caleb 확정) — 새 통화로 결제하면 공급처 계정을 새로 연다([실측] 이름 정규화로 묶었을 때 같은 이름 묶음 0 · 아직 발동 없음).
--   📌 KRW 송금의 환차손익은 회계 담당자 영역 — 이 표의 일이 아니다(QBO 연동 때 다시 올라온다).
--   ⚠️ 환율은 이 표에 담지 않는다 — 통화 목록은 거의 안 바뀌는 마스터, 환율은 매일 바뀌고 필요한 것은 「그 거래를 한 날의 환율」. Cin7 도 환율 목록을 주지 않고 문서마다 CurrencyRate 를 박는다
--     (⚠️ Simple Purchase 의 Invoice.CurrencyRate 는 null 이라 상위 CurrencyRate 를 쓴다 — inv-cost 실측). ⇒ 환율은 PO·인보이스 문서에 그 시점 값을 박는다 · rate 칸 없음(원장의 「소비 시점 단가를 굳힌다」와 같은 정신).
--
-- ═══ ⚠️⚠️ 앞선 표들과 갈리는 것 셋 — 결함이 아니라 판단 ═══
--   (가) cin7_id 칸이 **없다** — Cin7 에 통화 목록 엔드포인트가 없다([실측 2026-09-11] cin7-api/references/endpoint-index.md 전수 · ref/ 계열 17개 중 통화 없음 · brand·unit·category·paymentterm·account·location·tax·priceTier·carrier 등만).
--       앞선 넷에서 cin7_id 는 Cin7 행과의 매핑 고리였다 — 여기서는 영원히 비게 되므로 안 쓰는 칸을 두지 않는다(sort_order 를 뺀 것과 같은 이유). ⭐ 우리가 처음부터 세우는 첫 마스터다.
--   (나) source default 가 **'manual'** — 앞선 넷은 'cin7'. 이 표는 Cin7 에서 오지 않는다. CHECK ('cin7','manual') 는 그대로(나중에 Cin7 문서에서 통화가 발견돼 들어오는 경로를 막지 않는다).
--   (다) code 에 **형식 CHECK** ~ '^[A-Z]{3}$' — ISO 4217 은 국제 표준이고 형식이 바뀌지 않는다. ⚠️ ref_account.code 에 형식 CHECK 를 안 건 것과 반대인데, 그쪽은 Cin7 표기가 두 형식(_59_ 215 / 2000 74)이었다 —
--       **우리가 만드는 값과 남이 주는 값은 다르다.** name 유니크도 건다(우리가 만드는 표라 중복이 들어올 경로가 없다 — ref_account 와 다른 점).
--   ❌ 칸을 만들지 않는 것: rate(환율 — 위) · is_base(⭐ inv_config 로 — 표 안에 두면 둘이 true 되는 것을 막을 수단이 부분 유니크뿐 · WMS 규칙 29 · 결제조건 IsDefault 와 같은 판단) ·
--     decimal_places(CAD·USD 둘 다 2자리라 구별할 것이 없다 · KRW(0자리) 들어올 때 컬럼 추가). symbol 은 화면용으로 두되 CAD·USD 둘 다 '$' 라 구별 수단이 아니다.
--
-- ═══ ⭐ 값을 넣는 이유 — 이 표만의 예외 ═══
--   ① Cin7 에서 긁어올 데가 없다 — 누군가는 반드시 손으로 넣어야 하고 두 줄뿐이다.
--   ② inv_config 의 base_currency='CAD' 가 가리킬 대상이 표에 실재해야 한다(빈 표에 설정만 넣으면 없는 것을 가리킨다).
--   ⚠️ 이것은 「마이그레이션에 데이터를 넣어도 된다」가 아니다 — Cin7 에서 받는 표는 앞선 넷처럼 행 0건으로 만든다.
--   재실행 안전: on conflict do nothing(db reset 은 처음부터 다시 돌린다). ⚠️ ref_currency ↔ inv_config FK 없음 — inv_config 는 key-value 표라 value 가 문자열이고 FK 를 걸면 다른 설정값이 전부 막힌다.
--   inv_config 실물(테스트 DB 2026-09-11): key text PK · value text not null · note text · updated_at timestamptz default now() · 기존 행 baseline_snapshot_key 하나 — 그 행은 건드리지 않는다.
-- 📌 나머지 Settings 하나(로케이션·bin)는 따로 지시된다.

-- ── ref_currency ──
create table if not exists ref_currency (
  id         uuid primary key default gen_random_uuid(),
  code       text not null unique,
  name       text not null unique,
  symbol     text,
  is_active  boolean not null default true,
  source     text not null default 'manual',
  note       text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ref_currency_code_ck   check (code ~ '^[A-Z]{3}$'),
  constraint ref_currency_source_ck check (source in ('cin7','manual'))
);
comment on table  ref_currency is 'PO 모듈 Settings 마스터 · ⚠️ Cin7 에 대응 엔드포인트가 없어 우리가 세운 표다(그래서 cin7_id 없음 · source default manual) · 환율은 여기가 아니라 문서에 박는다 · 기준통화는 inv_config.base_currency · 2026-09-11 신설';
comment on column ref_currency.code   is '⭐ 자연키 · ISO 4217 세 글자 대문자 · CHECK ~ ''^[A-Z]{3}$''(국제 표준 · 형식이 바뀌지 않는다 — ref_account.code 와 달리 우리가 만드는 값)';
comment on column ref_currency.symbol is '화면용. ⚠️ CAD·USD 둘 다 $ 라 구별 수단이 아니다';
comment on column ref_currency.source is 'default manual — 이 표는 Cin7 에서 오지 않는다(앞선 ref_ 표들은 cin7). CHECK 는 같게 두어 나중 경로를 막지 않는다';

-- ── updated_at 트리거 — 공용 함수 set_updated_at() **재사용**(20260911144606 · 다시 만들지 않는다) ──
create trigger ref_currency_set_updated_at before update on ref_currency for each row execute function set_updated_at();

-- ── RLS · 권한 — 선행 표와 동일 ──
alter table ref_currency enable row level security;
create policy auth_all on ref_currency for all to authenticated using (true) with check (true);
revoke all on ref_currency from anon;
revoke delete, truncate on ref_currency from authenticated;

-- ── ⭐ 값 — 정확히 둘 (KRW 없음 · 재실행 안전) ──
insert into ref_currency (code, name, symbol, source) values
  ('CAD', 'Canadian Dollar', '$', 'manual'),
  ('USD', 'US Dollar',       '$', 'manual')
on conflict (code) do nothing;

-- ── ⭐ 기준통화 설정 — inv_config 1행 (PK key · 재실행 안전 · FK 없음) ──
insert into inv_config (key, value, note) values
  ('base_currency', 'CAD', '기준통화 · ref_currency.code 를 가리킨다(FK 없음 — key-value 표) · is_base 칸 대신 설정으로(둘이 true 되는 것을 부분 유니크 없이 막는다) · 2026-09-11')
on conflict (key) do nothing;
