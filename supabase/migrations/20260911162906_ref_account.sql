-- PO 모듈 ① Settings — 계정과목 표 신설: ref_account (2026-09-11)
--
-- 목표: 마이그레이션 1개 · 표 1개 · 행 적재 0건. 뼈대만 — Cin7 에서 긁어오는 것도 값을 채우는 것도 별도 작업.
-- 선행: 20260911144606(ref_brand·ref_category·ref_unit · 공통 여덟 칸 · 관례) · 20260911161647(ref_payment_term). ⚠️ 그 모양·관례를 그대로 따른다 — 단 자연키가 다르다(아래).
-- 왜 지금: ② 공급처가 AccountPayable 로 계정과목을 바로 참조한다([실측] 공급처 226곳 전부 계정 Code 와 일치 — _109_ 193곳 · _62_ 33곳 · ⚠️ Name 과 일치 0곳).
--   ③ 제품도 넷을 참조한다(InventoryAccount·COGSAccount·RevenueAccount·ExpenseAccount — 제품 83필드 실측). 참조되는 쪽을 먼저 세운다.
--
-- ═══ 실측 근거 (2026-09-11 GAS 프로브 전량) — GET /ref/account · Total 289 · 배열키 AccountsList · 필드 열둘 ═══
--   Class  EXPENSE 126 · ASSET 74 · LIABILITY 52 · REVENUE 26 · EQUITY 11 (다섯)        Status ACTIVE 213 · ARCHIVED 76 (둘)
--   Type   EXPENSE 109 · CURRLIAB 40 · BANK 20 · FIXED 19 · OTHERCURRENTASSET 16 · COSTOFGOODSSOLD 14 · CURRENT 13 · INCOME 11 · EQUITY 11 · OTHERINCOME 7 ·
--          CREDITCARD 7 · OTHERASSET 6 · REVENUE 5 · LONGTERMLIABILITY 5 · DIRECTCOSTS 3 · SALES 3 (열여섯)        ForPayments false 266 · true 23
--   Code   중복 0(⭐ 289개 전부 유일). ⚠️ 형식이 둘 — 「_숫자_」 215개 · 밑줄 없는 순수 숫자 74개(2000·1200·6000·8100…) ⇒ ⚠️⚠️ 형식 CHECK 를 걸지 않는다(74개가 걸린다).
--   ⭐ 우리가 코드에 박아 쓰는 계정 여섯 — 실재 확인: _59_ Inventory Asset[ASSET] · _135_ Brokerage - COS[EXPENSE](⚠️ 우리 문서의 "landed") · _136_ Freight - COS[EXPENSE] ·
--     _95_ Purchase Non Stock - COS[EXPENSE] · _1150040012_ Stock in Transit (GINR)[ASSET] · _1150040007_ In Transit[ASSET] — 전부 ACTIVE.
--   ⚠️⚠️ inv-cost·inv-doc-cost 의 계정 필터는 건드리지 않는다 — 표로 옮기는 것은 QBO 연동 때(2026-09-10 에 고친 것을 또 흔들지 않는다). 이번은 표 신설뿐.
--
-- ═══ ⚠️⚠️ 자연키가 다르다 — 앞선 표(brand·category·unit·payment_term)는 name 유니크 · 이 표는 **code** 유니크 · name 유니크 **없음** ═══
--   근거: ① 공급처가 Code 로 참조(226/226 · Name 일치 0) ② inv-cost·inv-doc-cost 가 Code 를 코드에 박아 쓴다 ③ Code 중복 0(289 전수)
--   ④ ⚠️ Name 의 중복 여부는 **측정하지 않았다** — Cin7 이 화면에 DisplayName(「_188_: Accounting」 · 코드를 앞에 붙임)을 따로 두는 것은 이름만으로 구별이 안 되는 경우가
--     있다는 신호다. 측정하지 않은 것을 제약으로 걸면 적재가 조용히 깨진다(스킬 「제약을 넣기 전에 이것이 실제로 무엇을 막는가를 확인할 것」).
--   ⇒ 다음 사람에게: 「앞선 표는 name 유니크인데 여기만 없다」는 결함이 아니라 **판단**이다. name 은 not null 만 유지.
--
-- ═══ 칸 ═══
--   공통 여덟 칸 = ref_brand 실물(테스트 DB 2026-09-11 information_schema)과 같다 — id uuid PK gen_random_uuid() · cin7_id uuid unique(plain · 부분 유니크 금지 · WMS 규칙 29) ·
--     name text not null(⚠️ unique 없음 — 위) · is_active boolean not null default true · source text not null default 'cin7' check in ('cin7','manual') · note text ·
--     created_at/updated_at timestamptz not null default now() · updated_at 은 공용 트리거 set_updated_at() 재사용(여기서 다시 만들지 않는다).
--   이 표에만 있는 네 칸 — ⚠️ 이번에 값을 넣지 않는다(행 0건):
--     code text not null unique          ⭐ 실질 자연키. 공급처·제품·inv-cost 가 이것으로 참조. ⚠️ 형식 CHECK 금지(_숫자_ 215 / 순수 숫자 74)
--     account_class text not null        다섯 종 — CHECK 있음(289 전수 실측 · 회계의 기본 다섯 · 늘어날 성질이 아니다)
--     account_type text                  열여섯 종 — ⚠️ CHECK 없음(종류가 많고 Cin7 이 늘릴 수 있다 · 전수를 봤어도 「늘어날 수 있는가」가 class 와 다르다)
--     for_payments boolean not null default false   「결제에 쓸 수 있는 계정인가」 23/289 · 지금 쓰는 코드는 없으나 칸 하나이고 회계 축에서 쓰인다
-- ═══ ❌ 담지 않는 Cin7 필드 ═══
--   DisplayName(「_188_: Accounting」 = Code+Name 화면용 — 필요하면 우리가 만든다) · Description(⭐ note 로 흡수 — 내용이 제각각: 「Accrued Purchases (GRNI)」 설명 · 「1050-421」 번호 · 사람 이름) ·
--   BankAccountId·BankAccountNumber(은행 계좌 — 우리 영역 아님) · SystemAccount·SystemAccountCode(Cin7 내부 표시 CREDITORS·DEBTORS… · 271/289 null) ·
--   Status(⭐ is_active 로 흡수 — ACTIVE→true · ARCHIVED→false · 앞선 표들과 같은 방식). ⚠️ ARCHIVED 76개도 담는다 — 과거 문서가 가리키고 있을 수 있다(거르면 옛 PO 에 갈 곳 없는 참조).
-- 📌 계정 289행은 PostgREST 1,000행 캡 아래(여유 711)지만 마스터는 늘어난다 — 화면에서 전량을 읽는 코드는 캡을 의식할 것(이번 범위 아님).
-- 📌 나머지 Settings 둘(통화 · 로케이션·bin)은 따로 지시된다.

-- ── ref_account ──
create table if not exists ref_account (
  id             uuid primary key default gen_random_uuid(),
  cin7_id        uuid unique,
  name           text not null,
  is_active      boolean not null default true,
  source         text not null default 'cin7',
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  code           text not null unique,
  account_class  text not null,
  account_type   text,
  for_payments   boolean not null default false,
  constraint ref_account_source_ck check (source in ('cin7','manual')),
  constraint ref_account_class_ck  check (account_class in ('EXPENSE','ASSET','LIABILITY','REVENUE','EQUITY'))
);
comment on table  ref_account is 'Cin7 ref/account 대응 · PO 모듈 Settings 마스터(캐시 아님) · ⚠️ 자연키는 name 이 아니라 code(name 유니크 없음 — 헤더 판단) · 2026-09-11 신설';
comment on column ref_account.code          is '⭐ 자연키 · unique. 공급처 AccountPayable·제품 계정 넷·inv-cost/inv-doc-cost 가 이 값으로 참조. ⚠️ 형식이 둘(「_숫자_」 215 · 순수 숫자 74) — 형식 CHECK 금지';
comment on column ref_account.account_class is 'Cin7 Class · 다섯(EXPENSE·ASSET·LIABILITY·REVENUE·EQUITY) · CHECK 있음(289 전수 실측 · 회계 기본 다섯)';
comment on column ref_account.account_type  is 'Cin7 Type · 열여섯 종(EXPENSE·CURRLIAB·BANK·FIXED·…) · ⚠️ CHECK 없음 — Cin7 이 늘릴 수 있다';
comment on column ref_account.for_payments  is 'Cin7 ForPayments · 결제에 쓸 수 있는 계정인가(23/289 true) · default false';

-- ── updated_at 트리거 — 공용 함수 set_updated_at() **재사용**(20260911144606 에서 만들었다 · 여기서 다시 만들지 않는다) ──
create trigger ref_account_set_updated_at before update on ref_account for each row execute function set_updated_at();

-- ── RLS · 권한 — 선행 표와 동일(auth_all + revoke anon · service_role 개방 없음 · DELETE·TRUNCATE 는 authenticated 에서 막는다 — 마스터는 is_active 로 물러나게 한다) ──
alter table ref_account enable row level security;
create policy auth_all on ref_account for all to authenticated using (true) with check (true);
revoke all on ref_account from anon;
revoke delete, truncate on ref_account from authenticated;
