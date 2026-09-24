-- SO 세금 ① — 세금 규칙 표 ref_tax_rule · 주 → 규칙 연결 ref_tax_region · 표기 별칭 ref_region_alias · 알아보기·찾기·계산 함수(읽기) · 세율 불변 (2026-09-24 UTC)
-- 지시서 ~/asung/prompts/so-tax-1.md · 판정 Caleb 2026-09-24(§1-B 판정 1~6 · 판정 회신 7 · 이견 1~10 ✅ · ⬜1~⬜8) · 정본 so-module §16(말만) · 자리: 인보이스(§8) 선행
-- 자료: docs/probes/TaxationRules_2026-09-24.csv(Cin7 Tax rules Export · 31줄 · 원본 그대로 — 씨앗을 그 줄에서 만들었다 · 요약으로 짐작하지 않았다) · ~/asung/prompts/so-tax-1-survey.txt(주 표기 137쌍 · 국가 34쌍 · 계정 넷 · tax_rule 칸 아홉)
-- 바탕: 20260923154749(ref_price_tier — 마스터 규약 모양 · 정책 셋 · ims_touch · seed on conflict do nothing) · po-module §5 · §7 갈림길(ref_tax_rule 미결 → 닫힘) · 1804~1810(_54_ GST/HST Payable · _118_ Vacation Pay 오지정)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/so-tax-1-verify.sql
--
-- ⭐ 판정(정본 §16 으로 · 말만)
--    1 세금 규칙 표를 인보이스보다 먼저(측정 먼저)   2 오더의 세금은 배송지의 주가 정한다 · customer.tax_rule 은 계산에 쓰지 않는다(91% 틀림 · 해외 Zero-rated · 예외는 초안에서 사람이)
--    3 줄마다 반올림해 더한다(Cin7 과 같다 · SO-10842 462.48 − 23.12 = 439.36 · 한 번에 매기면 1센트 다르다) · 오더 전체 할인·운임도 각자 한 줄   4 규칙의 세율은 고치지 않는다 — 세율이 바뀌면 새 규칙 + 연결에 시작일 · 인보이스는 발행 때 굳힌다 · 옛 세율 규칙 셋은 기록으로만
--    5 세율은 인보이스 발행일(토론토 ims_today)로 고른다(할인은 주문일 D7 — 기준이 갈리는 것이 맞다)   6 운임도 배송지 주의 규칙(제품과 같은 세율 · 1-p 실물 5%)   7 배송지의 나라·주가 바뀌면 사람이 바꿔 둔 규칙이라도 배송지 규칙으로(경고) — 세금 ② 의 일
--    ⬜5 나눔: 세금 ① = 이 파일(표 셋 · 씨앗 · 알아보기 · 찾기 · 계산 · 세율 불변 · 기존 창구 무접촉) · 세금 ② = 창구 여섯 재발행 · so.tax_rule_id · tax_rule_manual · 판정 7
--    이견 6 옛 연결(NS 15 등)은 싣지 않는다 — IMS 인보이스는 2026 부터 · 2025-03-31 로 NS 를 물으면 「연결 없음」   이견 7 세율 불변은 트리거로 모두에게(적재가 같은 이름·다른 세율을 만나면 그 자리에서 멈춘다 · 오타 정정은 비활성 + 새 이름)
-- ⭐ 알아보기(⬜3): 국가 원문을 먼저(별칭 표 kind country · CA·CANADA / US·USA·UNITED STATES… · 그 밖 원문이 있으면 '*' 해외) → 주 원문을 그 나라 안에서(별칭 표 kind region · 대소문자 무관) → 모르면 null(짐작 금지 · 경고 tax_region_unknown)
--    ⚠️ 'CA': country 가 Canada 면 캐나다 · United States 면 캘리포니아 · country 가 비어 있으면 null(모호) — 조사 ① 「국가 먼저 보기가 통한다」(Canada 8,774 · CANADA 504 · United States 488 · 빈 값 1줄)
-- ⭐ 찾기(⬜2): (country, region) → (country, '*') → ('*', '*') 순 · effective_from ≤ 날짜 중 최신 · 종료일 없음 = 겹칠 수 없다(전체 유니크 하나 · 규칙 29) · 캐나다 밖은 한 줄 Zero-rated · ⚠️ 캐나다는 주를 모르면 규칙 없음(해외 폴백 안 탐)
-- ⭐ 시작일(씨앗 · ⚠️ 공개 사실이지만 회계사 확인 거리 · 정본에): ON HST 13% 2010-07-01 · NB·NL HST 15% 2016-07-01 · PE HST 15% 2016-10-01 · NS HST 14% 2025-04-01 · GST 5% 2008-01-01 · 해외 Zero-rated 2008-01-01
-- ⚠️ 건드리지 않은 것 — customer·po·po_line·product·supplier·so·so_line·so_charge 의 tax_rule 원문 칸(text · CHECK 0 · 조사 ④) · 기존 창구 여섯(세금 ②) · ims_touch · ims_can_write · ims_today · so_line_total · so_order_discount
-- ⚠️ 시퀀스 무접촉 · 씨앗 = ref_tax_rule 31(CSV) · ref_tax_region 14(캐나다 13 + 해외 1) · ref_region_alias 143(캐나다 13 · 미국 50+DC·PR·VI · 국가 별칭 8)

-- ═══ ① ref_tax_rule — 세금 규칙(마스터 규약 · 자연키 name) ═══
create table if not exists public.ref_tax_rule (
  id           uuid primary key default gen_random_uuid(),
  cin7_id      uuid unique,                                      -- 규약 칸 · CSV 에 ID 가 없어 늘 null(GET /ref/tax 프로브가 채울 수 있으면 그때 · ⬜7)
  name         text not null unique,                             -- ⭐ 자연키 — Cin7 은 규칙을 이름으로 참조한다 · 손님·오더 원문(customer.tax_rule · so.tax_rule)이 이 이름
  is_active    boolean not null default true,
  source       text not null default 'cin7',
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.ims_staff (id) on delete no action,
  rate_pct     numeric(7,4) not null,                            -- ⭐ 퍼센트 값(13 · 5 · 0 · 이견 3) — 계산은 round(금액 × rate_pct / 100, 2) · ⭐ 불변(트리거 ref_tax_rule_rate_lock)
  direction    text not null,                                    -- sale · purchase · other — cin7_tax1 원문에서 한 번 정한다(이름 접미어 파싱 금지 · 이견 4)
  cin7_tax1    text,                                             -- 원문 Tax1(INPUT · OUTPUT · NONE · GSTONIMPORTS · AVALARA)
  account_id   uuid references public.ref_account (id) on delete no action,   -- 세금 계정(_54_ GST/HST Payable) · FK + 원문 짝
  account_code text,
  inclusive    boolean not null default false,                   -- 기록만(CSV 전부 False · EffectivePercent 셋은 Inclusive False 라 rate_pct 와 같아 담지 않는다)
  qbo_id       text unique,                                      -- QBO 연동 때(Caleb 「나중에는 퀵북에서 불러올 수 있어야 할꺼야」) · 지금 비움
  constraint ref_tax_rule_source_ck    check (source in ('cin7','qbo','manual')),
  constraint ref_tax_rule_rate_ck      check (rate_pct >= 0 and rate_pct <= 100),
  constraint ref_tax_rule_direction_ck check (direction in ('sale','purchase','other'))
);
create index if not exists ref_tax_rule_account_idx    on public.ref_tax_rule (account_id);
create index if not exists ref_tax_rule_updated_by_idx on public.ref_tax_rule (updated_by);
comment on table public.ref_tax_rule is
  '⭐ 세금 규칙(SO 세금 ① · 2026-09-24 · po-module §7 갈림길 닫힘 · so-module §16) — Cin7 Tax rules 31줄(docs/probes/TaxationRules_2026-09-24.csv) 그대로 · 자연키 name(Cin7 이 이름으로 참조) · rate_pct 는 불변(세율이 바뀌면 새 규칙 + ref_tax_region 시작일 · 판정 4) · direction 은 cin7_tax1 에서 · 계정 FK+원문 · source cin7|qbo|manual · 마스터 규약(정책 셋 master · DELETE·TRUNCATE 없음). ⚠️ 오더의 세금은 손님 저장값이 아니라 배송지 주로 고른다(판정 2 · ref_tax_region) — customer.tax_rule 은 계산에 쓰지 않는다';
comment on column public.ref_tax_rule.rate_pct  is '⭐ 세율 퍼센트(13 = 13%) · 불변 — update 로 바꾸면 트리거가 거부(누구든) · 새 세율은 새 이름(HST NS 2025 (Sale)) · 계산 round(금액 × rate_pct/100, 2) 줄마다(판정 3)';
comment on column public.ref_tax_rule.direction is 'sale(Cin7 OUTPUT) · purchase(INPUT) · other(NONE · GSTONIMPORTS · AVALARA) — 오더 세금은 sale 만 · 이름의 (Sale)/(Purchase) 를 파싱하지 않는다(이견 4)';
comment on column public.ref_tax_rule.qbo_id    is 'QuickBooks Online 세금 코드 식별(Cin7 화면 Load from QuickBooks) · 연동 차수에서 채운다 · 지금 null';

-- 세율 불변(이견 7 · 판정 4) — 누구든(적재·사람·postgres) · 새 세율은 새 규칙
create function public.ref_tax_rule_rate_lock() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if new.rate_pct is distinct from old.rate_pct then
    raise exception 'The rate of tax rule "%" cannot change (% → %) — a rate change is a new rule (e.g. "HST NS 2025 (Sale)") linked to the region with a start date — nothing was saved', old.name, old.rate_pct, new.rate_pct;
  end if;
  return new;
end;
$$;
comment on function public.ref_tax_rule_rate_lock() is 'ref_tax_rule BEFORE UPDATE — rate_pct 변경 거부(판정 4 · 이견 7 · 누구든) · 인보이스가 굳힌 세율의 근거를 지키고 적재가 같은 이름·다른 세율을 만나면 그 자리에서 멈추게 한다 · 오타 정정 = 비활성 + 새 이름';
revoke all on function public.ref_tax_rule_rate_lock() from public, anon;
create trigger ref_tax_rule_rate_lock before update on public.ref_tax_rule for each row execute function public.ref_tax_rule_rate_lock();
create trigger ref_tax_rule_touch     before update on public.ref_tax_rule for each row execute function public.ims_touch();

alter table public.ref_tax_rule enable row level security;
create policy ref_tax_rule_select on public.ref_tax_rule for select to authenticated using (true);
create policy ref_tax_rule_insert on public.ref_tax_rule for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_tax_rule_update on public.ref_tax_rule for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
revoke all on public.ref_tax_rule from anon;
revoke delete, truncate on public.ref_tax_rule from authenticated;

-- 씨앗 31 — CSV 그대로(Description · Tax1 · AccountCode · Inclusive · IsActive · EffectivePercentExclusive = EffectivePercent) · 계정은 code 로 조회(uuid 를 박지 않는다 · ref_price_tier 이견 8 선례) · on conflict (name) do nothing
insert into public.ref_tax_rule (name, cin7_tax1, direction, account_code, account_id, inclusive, is_active, rate_pct, source, note)
select v.name, v.tax1, v.direction, v.account_code, (select a.id from public.ref_account a where a.code = v.account_code), v.inclusive, v.is_active, v.rate_pct, 'cin7', v.note
from (values
  ('Tax on Purchases', 'INPUT', 'purchase', '_109_', false, false, 10.00, 'Cin7 기본 규칙 · 계정 _109_ A/P USD · 쓰지 않는다'),
  ('Tax on Sales', 'OUTPUT', 'sale', '_118_', false, false, 10.00, 'Cin7 기본 규칙 · 계정 _118_ Vacation Pay 오지정(po-module 1806) · 쓰지 않는다'),
  ('Tax Exempt', 'NONE', 'other', '_118_', false, false, 0.00, 'Cin7 기본 규칙 · 계정 _118_ Vacation Pay 오지정(po-module 1806) · 쓰지 않는다'),
  ('Sales Tax on Imports', 'GSTONIMPORTS', 'other', '_118_', false, false, 0.00, 'Cin7 기본 규칙 · 계정 _118_ Vacation Pay 오지정(po-module 1806) · 쓰지 않는다 · 수입 세금 규칙 · 우리 계산에 쓰지 않는다'),
  ('HST NB 2016 (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 15.00, null),
  ('HST NS (Purchase)', 'INPUT', 'purchase', '_54_', false, false, 15.00, 'NS 15% (2025-03-31 까지) · Cin7 비활성 · 옛 연결은 싣지 않는다(이견 6)'),
  ('Exempt (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 0.00, null),
  ('HST NS 2025 (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 14.00, null),
  ('HST NS 2025 (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 14.00, null),
  ('HST ON (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 13.00, null),
  ('Auto Look Up', 'AVALARA', 'other', '_54_', false, false, 0.00, 'Avalara 자동 조회 규칙 · 우리 계산에 쓰지 않는다'),
  ('Exempt (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 0.00, null),
  ('HST NL (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 13.00, '옛 세율(판정 4) — 기록으로만 · 연결(ref_tax_region)에 쓰지 않는다 · Cin7 비활성 전환은 Caleb(회계사와)'),
  ('HST PE 2016 (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 15.00, null),
  ('Zero-rated (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 0.00, null),
  ('HST PE (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 14.00, '옛 세율(판정 4) — 기록으로만 · 연결(ref_tax_region)에 쓰지 않는다 · Cin7 비활성 전환은 Caleb(회계사와)'),
  ('Out of Scope (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 0.00, null),
  ('Zero-rated (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 0.00, null),
  ('HST PE (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 14.00, '옛 세율(판정 4) — 기록으로만 · 연결(ref_tax_region)에 쓰지 않는다 · Cin7 비활성 전환은 Caleb(회계사와)'),
  ('HST ON (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 13.00, null),
  ('HST NL 2016 (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 15.00, null),
  ('GST (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 5.00, null),
  ('HST NB 2016 (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 15.00, null),
  ('GST (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 5.00, null),
  ('HST NB (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 13.00, '옛 세율(판정 4) — 기록으로만 · 연결(ref_tax_region)에 쓰지 않는다 · Cin7 비활성 전환은 Caleb(회계사와)'),
  ('HST NL 2016 (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 15.00, null),
  ('HST NB (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 13.00, '옛 세율(판정 4) — 기록으로만 · 연결(ref_tax_region)에 쓰지 않는다 · Cin7 비활성 전환은 Caleb(회계사와)'),
  ('Out of Scope (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 0.00, null),
  ('HST NL (Purchase)', 'INPUT', 'purchase', '_54_', false, true, 13.00, '옛 세율(판정 4) — 기록으로만 · 연결(ref_tax_region)에 쓰지 않는다 · Cin7 비활성 전환은 Caleb(회계사와)'),
  ('HST NS (Sale)', 'OUTPUT', 'sale', '_54_', false, false, 15.00, 'NS 15% (2025-03-31 까지) · Cin7 비활성 · 옛 연결은 싣지 않는다(이견 6)'),
  ('HST PE 2016 (Sale)', 'OUTPUT', 'sale', '_54_', false, true, 15.00, null)
) as v(name, tax1, direction, account_code, inclusive, is_active, rate_pct, note)
on conflict (name) do nothing;

-- ═══ ② ref_tax_region — 나라·주 → 규칙 연결(시작일 · 종료일 없음 · 겹칠 수 없다) ═══
create table if not exists public.ref_tax_region (
  id             uuid primary key default gen_random_uuid(),
  cin7_id        uuid unique,                                    -- 규약 칸 · 늘 null(Cin7 에 없는 표 · IMS 판정 값)
  name           text not null unique,                           -- 사람이 읽는 이름 · 'CA-ON sale 2010-07-01'(씨앗이 만든다)
  is_active      boolean not null default true,
  source         text not null default 'manual',
  note           text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.ims_staff (id) on delete no action,
  country_code   text not null,                                  -- ISO2 대문자(CA · US) · '*' = 그 밖 전부(해외)
  region_code    text not null,                                  -- 주·준주 코드(ON · QC …) · '*' = 나라 전체
  direction      text not null default 'sale',
  tax_rule_id    uuid not null references public.ref_tax_rule (id) on delete no action,
  effective_from date not null,                                  -- ⭐ 이 날부터 이 규칙 · 종료일 없음 — 그 날짜 이하 중 가장 늦은 시작일 하나가 답(겹침 불가 · 이견 5)
  constraint ref_tax_region_source_ck    check (source in ('manual')),
  constraint ref_tax_region_direction_ck check (direction in ('sale','purchase')),
  constraint ref_tax_region_codes_ck     check (country_code = upper(country_code) and region_code = upper(region_code) and (country_code <> '*' or region_code = '*')),
  constraint ref_tax_region_key          unique (country_code, region_code, direction, effective_from)
);
create index if not exists ref_tax_region_rule_idx       on public.ref_tax_region (tax_rule_id);
create index if not exists ref_tax_region_updated_by_idx on public.ref_tax_region (updated_by);
comment on table public.ref_tax_region is
  '⭐ 나라·주 → 세금 규칙 연결(SO 세금 ① · 판정 2·4 · ⬜2) — (country_code, region_code, direction, effective_from) 전체 유니크 하나 · 종료일 없음(effective_from ≤ 날짜 중 최신이 답 · 겹칠 수 없다 · 규칙 29) · 찾기 순서 (country, region) → (country, ''*'') → (''*'', ''*'')(해외 Zero-rated · 캐나다는 폴백 안 탐) · 세율이 바뀌면 새 규칙을 가리키는 새 줄(시작일) · ⚠️ 옛 연결(NS 15% 등)은 싣지 않았다(이견 6 · IMS 인보이스는 2026 부터) · 시작일은 공개 사실이지만 회계사 확인 거리(§16)';

create trigger ref_tax_region_touch before update on public.ref_tax_region for each row execute function public.ims_touch();
alter table public.ref_tax_region enable row level security;
create policy ref_tax_region_select on public.ref_tax_region for select to authenticated using (true);
create policy ref_tax_region_insert on public.ref_tax_region for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_tax_region_update on public.ref_tax_region for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
revoke all on public.ref_tax_region from anon;
revoke delete, truncate on public.ref_tax_region from authenticated;

-- 씨앗 14(sale · 캐나다 13 + 해외 1) — 규칙은 이름으로 조회 · 시작일은 회계사 확인 거리 · 옛 연결 없음
insert into public.ref_tax_region (name, country_code, region_code, direction, tax_rule_id, effective_from, note)
select format('%s-%s %s %s', v.cc, v.rc, 'sale', v.eff), v.cc, v.rc, 'sale', (select r.id from public.ref_tax_rule r where r.name = v.rule), v.eff::date, v.note
from (values
  ('CA','ON','HST ON (Sale)',       '2010-07-01', 'Ontario HST 13% (2010-07-01~)'),
  ('CA','NB','HST NB 2016 (Sale)',  '2016-07-01', 'New Brunswick HST 15% (2016-07-01~ · 13% 규칙 HST NB (Sale) 은 옛 세율 · 연결 안 함)'),
  ('CA','NL','HST NL 2016 (Sale)',  '2016-07-01', 'Newfoundland and Labrador HST 15% (2016-07-01~ · 13% 규칙은 옛 세율)'),
  ('CA','PE','HST PE 2016 (Sale)',  '2016-10-01', 'Prince Edward Island HST 15% (2016-10-01~ · 14% 규칙은 옛 세율)'),
  ('CA','NS','HST NS 2025 (Sale)',  '2025-04-01', 'Nova Scotia HST 14% (2025-04-01~ · 15% 규칙 HST NS (Sale) 은 Cin7 비활성 · 옛 연결 안 실음 — 2025-03-31 이전 날짜는 연결 없음)'),
  ('CA','QC','GST (Sale)',          '2008-01-01', 'Quebec — GST 5% 만(QST 는 지금 실무에서 받지 않는다 · 회계사 확인 거리)'),
  ('CA','AB','GST (Sale)',          '2008-01-01', 'Alberta GST 5%'),
  ('CA','BC','GST (Sale)',          '2008-01-01', 'British Columbia — GST 5% 만(PST 회계사 확인 거리)'),
  ('CA','MB','GST (Sale)',          '2008-01-01', 'Manitoba — GST 5% 만(PST 회계사 확인 거리)'),
  ('CA','SK','GST (Sale)',          '2008-01-01', 'Saskatchewan — GST 5% 만(PST 회계사 확인 거리)'),
  ('CA','YT','GST (Sale)',          '2008-01-01', 'Yukon GST 5%'),
  ('CA','NT','GST (Sale)',          '2008-01-01', 'Northwest Territories GST 5%'),
  ('CA','NU','GST (Sale)',          '2008-01-01', 'Nunavut GST 5%'),
  ('*', '*', 'Zero-rated (Sale)',   '2008-01-01', '캐나다 밖 전부(미국 포함) — 수출 Zero-rated 0% (판정 2 · 회계사 확인 거리)')
) as v(cc, rc, rule, eff, note)
on conflict (country_code, region_code, direction, effective_from) do nothing;

-- ═══ ③ ref_region_alias — 나라·주 표기 별칭(관계 표 규약 · DELETE 열림 · 사람이 더한다) ═══
--   kind country: 국가 원문 → country_code · kind region: 주 원문 → (country_code, region_code) · alias_norm 은 upper(trim(원문)) · (kind, alias_norm) 유니크
--   씨앗: 캐나다 13 주·준주 코드+이름(+QUÉBEC · PEI · NEWFOUNDLAND) · 미국 50 주 + DC · PR · VI 코드+이름 · 국가 8 — 조사 ② 137쌍의 실물 표기가 전부 이 안에 든다(Scarborough · ENG · Dubai 류는 나라로 가르거나 null)
create table if not exists public.ref_region_alias (
  id            uuid primary key default gen_random_uuid(),
  cin7_id       uuid unique,                                     -- 규약 칸 · 늘 null
  is_active     boolean not null default true,
  source        text not null default 'manual',
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  kind          text not null,                                   -- country · region
  country_code  text not null,
  region_code   text not null,                                   -- kind country 면 '*'
  alias_norm    text not null,                                   -- ⭐ upper(trim(원문)) — 찾을 때도 같은 식
  constraint ref_region_alias_source_ck    check (source in ('manual')),
  constraint ref_region_alias_kind_ck      check (kind in ('country','region')),
  constraint ref_region_alias_kind_pair_ck check ((kind = 'country') = (region_code = '*')),
  constraint ref_region_alias_norm_ck      check (alias_norm = upper(trim(alias_norm)) and alias_norm <> ''),
  constraint ref_region_alias_key          unique (kind, alias_norm)
);
create index if not exists ref_region_alias_code_idx       on public.ref_region_alias (country_code, region_code);
create index if not exists ref_region_alias_updated_by_idx on public.ref_region_alias (updated_by);
comment on table public.ref_region_alias is
  '⭐ 나라·주 표기 별칭(SO 세금 ① · ⬜3 · 표로 둔다 — Scarborough·ENG 같은 실물을 만날 때마다 마이그레이션이 되지 않게) — kind country(국가 원문 → country_code) · kind region(주 원문 → country_code+region_code) · alias_norm = upper(trim(원문)) · (kind, alias_norm) 유니크 · 사람이 더한다(master · DELETE 열림 — 잘못 넣은 별칭은 지운다) · ims_region_from_address 가 읽는다';

create trigger ref_region_alias_touch before update on public.ref_region_alias for each row execute function public.ims_touch();
alter table public.ref_region_alias enable row level security;
create policy ref_region_alias_select on public.ref_region_alias for select to authenticated using (true);
create policy ref_region_alias_insert on public.ref_region_alias for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_region_alias_update on public.ref_region_alias for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy ref_region_alias_delete on public.ref_region_alias for delete to authenticated using ((select public.ims_can_write('master')));
revoke all on public.ref_region_alias from anon;
revoke truncate on public.ref_region_alias from authenticated;

insert into public.ref_region_alias (kind, country_code, region_code, alias_norm)
values
  ('region','CA','ON','ON'),
  ('region','CA','ON','ONTARIO'),
  ('region','CA','QC','QC'),
  ('region','CA','QC','QUEBEC'),
  ('region','CA','QC','QUÉBEC'),
  ('region','CA','NS','NS'),
  ('region','CA','NS','NOVA SCOTIA'),
  ('region','CA','NB','NB'),
  ('region','CA','NB','NEW BRUNSWICK'),
  ('region','CA','MB','MB'),
  ('region','CA','MB','MANITOBA'),
  ('region','CA','BC','BC'),
  ('region','CA','BC','BRITISH COLUMBIA'),
  ('region','CA','PE','PE'),
  ('region','CA','PE','PRINCE EDWARD ISLAND'),
  ('region','CA','PE','PEI'),
  ('region','CA','SK','SK'),
  ('region','CA','SK','SASKATCHEWAN'),
  ('region','CA','AB','AB'),
  ('region','CA','AB','ALBERTA'),
  ('region','CA','NL','NL'),
  ('region','CA','NL','NEWFOUNDLAND AND LABRADOR'),
  ('region','CA','NL','NEWFOUNDLAND'),
  ('region','CA','NT','NT'),
  ('region','CA','NT','NORTHWEST TERRITORIES'),
  ('region','CA','YT','YT'),
  ('region','CA','YT','YUKON'),
  ('region','CA','NU','NU'),
  ('region','CA','NU','NUNAVUT'),
  ('region','US','AL','AL'),
  ('region','US','AL','ALABAMA'),
  ('region','US','AK','AK'),
  ('region','US','AK','ALASKA'),
  ('region','US','AZ','AZ'),
  ('region','US','AZ','ARIZONA'),
  ('region','US','AR','AR'),
  ('region','US','AR','ARKANSAS'),
  ('region','US','CA','CA'),
  ('region','US','CA','CALIFORNIA'),
  ('region','US','CO','CO'),
  ('region','US','CO','COLORADO'),
  ('region','US','CT','CT'),
  ('region','US','CT','CONNECTICUT'),
  ('region','US','DE','DE'),
  ('region','US','DE','DELAWARE'),
  ('region','US','FL','FL'),
  ('region','US','FL','FLORIDA'),
  ('region','US','GA','GA'),
  ('region','US','GA','GEORGIA'),
  ('region','US','HI','HI'),
  ('region','US','HI','HAWAII'),
  ('region','US','ID','ID'),
  ('region','US','ID','IDAHO'),
  ('region','US','IL','IL'),
  ('region','US','IL','ILLINOIS'),
  ('region','US','IN','IN'),
  ('region','US','IN','INDIANA'),
  ('region','US','IA','IA'),
  ('region','US','IA','IOWA'),
  ('region','US','KS','KS'),
  ('region','US','KS','KANSAS'),
  ('region','US','KY','KY'),
  ('region','US','KY','KENTUCKY'),
  ('region','US','LA','LA'),
  ('region','US','LA','LOUISIANA'),
  ('region','US','ME','ME'),
  ('region','US','ME','MAINE'),
  ('region','US','MD','MD'),
  ('region','US','MD','MARYLAND'),
  ('region','US','MA','MA'),
  ('region','US','MA','MASSACHUSETTS'),
  ('region','US','MI','MI'),
  ('region','US','MI','MICHIGAN'),
  ('region','US','MN','MN'),
  ('region','US','MN','MINNESOTA'),
  ('region','US','MS','MS'),
  ('region','US','MS','MISSISSIPPI'),
  ('region','US','MO','MO'),
  ('region','US','MO','MISSOURI'),
  ('region','US','MT','MT'),
  ('region','US','MT','MONTANA'),
  ('region','US','NE','NE'),
  ('region','US','NE','NEBRASKA'),
  ('region','US','NV','NV'),
  ('region','US','NV','NEVADA'),
  ('region','US','NH','NH'),
  ('region','US','NH','NEW HAMPSHIRE'),
  ('region','US','NJ','NJ'),
  ('region','US','NJ','NEW JERSEY'),
  ('region','US','NM','NM'),
  ('region','US','NM','NEW MEXICO'),
  ('region','US','NY','NY'),
  ('region','US','NY','NEW YORK'),
  ('region','US','NC','NC'),
  ('region','US','NC','NORTH CAROLINA'),
  ('region','US','ND','ND'),
  ('region','US','ND','NORTH DAKOTA'),
  ('region','US','OH','OH'),
  ('region','US','OH','OHIO'),
  ('region','US','OK','OK'),
  ('region','US','OK','OKLAHOMA'),
  ('region','US','OR','OR'),
  ('region','US','OR','OREGON'),
  ('region','US','PA','PA'),
  ('region','US','PA','PENNSYLVANIA'),
  ('region','US','RI','RI'),
  ('region','US','RI','RHODE ISLAND'),
  ('region','US','SC','SC'),
  ('region','US','SC','SOUTH CAROLINA'),
  ('region','US','SD','SD'),
  ('region','US','SD','SOUTH DAKOTA'),
  ('region','US','TN','TN'),
  ('region','US','TN','TENNESSEE'),
  ('region','US','TX','TX'),
  ('region','US','TX','TEXAS'),
  ('region','US','UT','UT'),
  ('region','US','UT','UTAH'),
  ('region','US','VT','VT'),
  ('region','US','VT','VERMONT'),
  ('region','US','VA','VA'),
  ('region','US','VA','VIRGINIA'),
  ('region','US','WA','WA'),
  ('region','US','WA','WASHINGTON'),
  ('region','US','WV','WV'),
  ('region','US','WV','WEST VIRGINIA'),
  ('region','US','WI','WI'),
  ('region','US','WI','WISCONSIN'),
  ('region','US','WY','WY'),
  ('region','US','WY','WYOMING'),
  ('region','US','DC','DC'),
  ('region','US','DC','DISTRICT OF COLUMBIA'),
  ('region','US','PR','PR'),
  ('region','US','PR','PUERTO RICO'),
  ('region','US','VI','VI'),
  ('region','US','VI','VIRGIN ISLANDS'),
  ('country','CA','*','CA'),
  ('country','CA','*','CANADA'),
  ('country','US','*','US'),
  ('country','US','*','USA'),
  ('country','US','*','UNITED STATES'),
  ('country','US','*','UNITED STATES OF AMERICA'),
  ('country','US','*','U.S.'),
  ('country','US','*','U.S.A.')
on conflict (kind, alias_norm) do nothing;

-- ═══ ④ ims_region_from_address — 주소 원문 → (country_code, region_code) · 모르면 null(짐작 금지) ═══
create function public.ims_region_from_address(p_country text, p_state text)
  returns table (country_code text, region_code text, how text)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  c   text := nullif(upper(trim(coalesce(p_country, ''))), '');
  s   text := nullif(upper(trim(coalesce(p_state, ''))), '');
  cc  text;
  rc  text;
  n   int;
begin
  -- ① 국가 먼저(조사 ① · 'CA' 는 국가로 가른다)
  if c is not null then
    select a.country_code into cc from public.ref_region_alias a where a.kind = 'country' and a.is_active and a.alias_norm = c;
    if cc is null then
      return query select '*'::text, '*'::text, 'country_other'::text;      -- 국가 원문이 있는데 CA·US 가 아니다 = 해외(Zero-rated 자리)
      return;
    end if;
    if s is null then
      return query select cc, null::text, 'region_missing'::text;           -- 나라는 알되 주가 없다(CA 는 규칙을 못 고른다 · US 는 해외 폴백)
      return;
    end if;
    select a.region_code into rc from public.ref_region_alias a where a.kind = 'region' and a.is_active and a.country_code = cc and a.alias_norm = s;
    if rc is null then
      return query select cc, null::text, 'region_unknown'::text;           -- 표기를 모른다 → 별칭 표에 더하거나 사람이 고른다
      return;
    end if;
    return query select cc, rc, 'address'::text;
    return;
  end if;
  -- ② 국가가 비어 있다 — 주 표기로 짐작하지 않는다 · 단 한 나라에서만 나오는 표기면 그 나라(그 표기가 국가 별칭과도 겹치면(CA) null)
  if s is null then
    return query select null::text, null::text, 'unknown'::text;
    return;
  end if;
  if exists (select 1 from public.ref_region_alias a where a.kind = 'country' and a.is_active and a.alias_norm = s) then
    return query select null::text, null::text, 'ambiguous'::text;         -- 'CA' 만 있고 나라가 없다 — 캐나다인지 캘리포니아인지 모른다
    return;
  end if;
  select count(distinct a.country_code) into n from public.ref_region_alias a where a.kind = 'region' and a.is_active and a.alias_norm = s;
  if n = 1 then
    select a.country_code, a.region_code into cc, rc from public.ref_region_alias a where a.kind = 'region' and a.is_active and a.alias_norm = s limit 1;
    return query select cc, rc, 'inferred_from_region'::text;
    return;
  end if;
  return query select null::text, null::text, 'unknown'::text;
end;
$$;
comment on function public.ims_region_from_address(text, text) is
  '⭐ 주소 원문 → (country_code, region_code, how)(SO 세금 ① · ⬜3) — 국가 먼저(별칭 kind country · 없으면 ''*'' 해외 · country_other) → 주(별칭 kind region · 그 나라 안에서 · region_unknown/region_missing) · 국가가 비면 주 표기가 한 나라에서만 나올 때만 그 나라(inferred_from_region · ''CA'' 처럼 국가 별칭과 겹치면 ambiguous → null). 늘 한 행 · null = 세금을 매길 수 없다(경고 tax_region_unknown · 사람이 초안에서 고른다) · 짐작하지 않는다';
revoke all on function public.ims_region_from_address(text, text) from public, anon;
grant execute on function public.ims_region_from_address(text, text) to authenticated;

-- ═══ ⑤ so_tax_rule_for — (나라 · 주 · 날짜 · 방향) → 규칙(jsonb 한 개) ═══
create function public.so_tax_rule_for(p_country text, p_state text, p_on date default null, p_direction text default 'sale') returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_on   date := coalesce(p_on, public.ims_today());
  g      record;
  m      record;
begin
  select * into g from public.ims_region_from_address(p_country, p_state);
  if g.country_code is null then
    return jsonb_build_object('rule_id', null, 'rule', null, 'rate_pct', null, 'region', jsonb_build_object('country_code', null, 'region_code', null, 'how', g.how), 'matched', null, 'on', v_on, 'warnings', '["tax_region_unknown"]'::jsonb);
  end if;
  -- (country, region) → (country, '*') → ('*', '*') · effective_from ≤ 날짜 중 최신 · 활성 연결 · 활성 규칙 · ⚠️ 캐나다는 해외 폴백을 타지 않는다(주를 모르면 규칙 없음)
  select t.tax_rule_id, r.name, r.rate_pct, t.effective_from,
         case when t.country_code = '*' then 'world' when t.region_code = '*' then 'country' else 'region' end as matched
    into m
  from public.ref_tax_region t join public.ref_tax_rule r on r.id = t.tax_rule_id
  where t.is_active and r.is_active and t.direction = p_direction and t.effective_from <= v_on
    and ((t.country_code = g.country_code and t.region_code = coalesce(g.region_code, '-'))
      or (t.country_code = g.country_code and t.region_code = '*')
      or (t.country_code = '*' and t.region_code = '*' and g.country_code <> 'CA'))
  order by case when t.country_code = '*' then 3 when t.region_code = '*' then 2 else 1 end, t.effective_from desc
  limit 1;
  if m.tax_rule_id is null then
    return jsonb_build_object('rule_id', null, 'rule', null, 'rate_pct', null, 'region', jsonb_build_object('country_code', g.country_code, 'region_code', g.region_code, 'how', g.how), 'matched', null, 'on', v_on,
                              'warnings', case when g.region_code is null then '["tax_region_unknown"]'::jsonb else '["tax_rule_not_linked"]'::jsonb end);
  end if;
  return jsonb_build_object('rule_id', m.tax_rule_id, 'rule', m.name, 'rate_pct', m.rate_pct, 'effective_from', m.effective_from,
                            'region', jsonb_build_object('country_code', g.country_code, 'region_code', g.region_code, 'how', g.how), 'matched', m.matched, 'on', v_on, 'warnings', '[]'::jsonb);
end;
$$;
comment on function public.so_tax_rule_for(text, text, date, text) is
  '⭐ 배송지 → 세금 규칙(SO 세금 ① · 판정 2·5 · ⬜4) — ims_region_from_address → ref_tax_region 찾기 순서 (country, region) → (country, ''*'') → (''*'', ''*'') · effective_from ≤ 날짜(기본 ims_today · 인보이스는 발행일) 중 최신 · ⚠️ 캐나다는 주를 모르면 규칙 없음(해외 폴백을 타지 않는다) · jsonb 한 개(rule_id · rule · rate_pct · effective_from · region(how) · matched region|country|world · warnings tax_region_unknown | tax_rule_not_linked)';
revoke all on function public.so_tax_rule_for(text, text, date, text) from public, anon;
grant execute on function public.so_tax_rule_for(text, text, date, text) to authenticated;

-- ═══ ⑥ so_tax_amount — 줄 세금 식 한 곳(판정 3 · 줄마다 반올림) ═══
create function public.so_tax_amount(p_amount numeric, p_rate_pct numeric) returns numeric
  language sql immutable
  set search_path = public, pg_temp
as $$
  select case when p_amount is null or p_rate_pct is null then null else round(p_amount * p_rate_pct / 100, 2) end;
$$;
comment on function public.so_tax_amount(numeric, numeric) is '⭐ 줄 세금 식 한 곳(판정 3 · Cin7 과 같다) — round(줄 금액 × rate_pct/100, 2) · 줄마다 반올림해 더한다(10.05 × 3줄 13% = 1.31 × 3 = 3.93 · 한 번에 3.92 가 아니다) · 오더 전체 할인·운임도 각자 한 줄 · 무상 줄은 금액 0 이라 0';
revoke all on function public.so_tax_amount(numeric, numeric) from public, anon;
grant execute on function public.so_tax_amount(numeric, numeric) to authenticated;

-- ═══ ⑦ so_tax_preview — 오더의 세금 미리 보기(읽기 · so 에 규칙 FK 가 없어 배송지에서 고른다 · 출처를 적는다 · 세금 ② 가 so.tax_rule_id 를 두면 그것을 먼저) ═══
create function public.so_tax_preview(p_so_id uuid, p_on date default null, p_rule_id uuid default null) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_on     date := coalesce(p_on, public.ims_today());
  v_pick   jsonb;
  v_rate   numeric;
  v_rule   text;
  v_source text;
  v_lines  jsonb;  v_lines_tax numeric;  v_lines_amt numeric;
  v_chg    jsonb;  v_chg_tax numeric;    v_chg_amt numeric;
  v_od_amt numeric := 0;  v_od_tax numeric := 0;
  v_warn   jsonb := '[]'::jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found'; end if;

  if p_rule_id is not null then
    select r.name, r.rate_pct into v_rule, v_rate from public.ref_tax_rule r where r.id = p_rule_id and r.is_active and r.direction = 'sale';
    if v_rule is null then raise exception 'Tax rule % is not an active selling rule', p_rule_id; end if;
    v_source := 'explicit';
    v_pick := jsonb_build_object('rule_id', p_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on);
  else
    v_pick := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, v_on, 'sale');
    v_rate := (v_pick->>'rate_pct')::numeric;  v_rule := v_pick->>'rule';
    v_source := 'ship_to';
    v_warn := coalesce(v_pick->'warnings', '[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'amount', public.so_line_total(l), 'tax', public.so_tax_amount(public.so_line_total(l), v_rate), 'free', l.free_reason is not null) order by l.line_no), '[]'::jsonb),
         coalesce(sum(public.so_tax_amount(public.so_line_total(l), v_rate)), 0), coalesce(sum(public.so_line_total(l)), 0)
    into v_lines, v_lines_tax, v_lines_amt
  from public.so_line l where l.so_id = p_so_id;

  if coalesce(v_so.order_discount_pct, 0) > 0 then                                  -- 오더 전체 할인은 제품 줄 합계에 한 번(D6 · 운임 제외) · 세금은 그 줄에 따로(판정 3 · SO-10842 −23.12)
    v_od_amt := -round(v_lines_amt * v_so.order_discount_pct / 100, 2);
    v_od_tax := public.so_tax_amount(v_od_amt, v_rate);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', c.line_no, 'name', c.name, 'amount', c.amount, 'tax', public.so_tax_amount(c.amount, v_rate)) order by c.line_no), '[]'::jsonb),
         coalesce(sum(public.so_tax_amount(c.amount, v_rate)), 0), coalesce(sum(c.amount), 0)
    into v_chg, v_chg_tax, v_chg_amt
  from public.so_charge c where c.so_id = p_so_id;                                  -- 운임도 배송지 주의 규칙 · 줄마다(판정 6)

  return jsonb_build_object(
    'so_number', v_so.so_number, 'on', v_on, 'source', v_source, 'rule', v_pick,
    'lines', v_lines, 'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'amount', v_od_amt, 'tax', v_od_tax), 'charges', v_chg,
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'lines_tax', v_lines_tax, 'order_discount_amount', v_od_amt, 'order_discount_tax', v_od_tax,
                                 'charges_amount', v_chg_amt, 'charges_tax', v_chg_tax,
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt,
                                 'tax', case when v_rate is null then null else v_lines_tax + v_od_tax + v_chg_tax end,
                                 'total', case when v_rate is null then null else v_lines_amt + v_od_amt + v_chg_amt + v_lines_tax + v_od_tax + v_chg_tax end),
    'warnings', v_warn);
end;
$$;
comment on function public.so_tax_preview(uuid, date, uuid) is
  '⭐ 오더 세금 미리 보기(SO 세금 ① · 판정 3·5·6 · ⬜4) — 규칙은 p_rule_id(explicit) 아니면 배송지(ship_to_country · ship_to_state_province)에서 so_tax_rule_for(날짜 기본 ims_today · 인보이스는 발행일) · 제품 줄(so_line_total)·오더 전체 할인 줄(−round(Σ × pct/100, 2))·운임 줄마다 so_tax_amount 로 반올림해 더한다 · 규칙 없으면 tax null + warnings · 읽기만(굳히는 것은 인보이스 · so.tax_rule_id 는 세금 ②)';
revoke all on function public.so_tax_preview(uuid, date, uuid) from public, anon;
grant execute on function public.so_tax_preview(uuid, date, uuid) to authenticated;

-- ═══ 검증(Caleb · ~/asung/prompts/so-tax-1-verify.sql) — 표 셋 실물 · 씨앗 31/14/143 · 옛 세율 셋은 연결에 없다 · 세율 update 거부 · 같은 시작일 두 번 23505 · 알아보기 · 계산(3.93 · SO-10842 439.36 · 운임 5.53 · 무상 0 · NS 2025-03-31 연결 없음 · 2025-04-01 14 · 해외 0) · 권한 ═══
