-- SO 모듈 마이그레이션 ② — customer_contact.job_title 칸 + 프로브 실측으로 닫힌 주석 갱신 (2026-09-22 토론토 밤 · 파일 시각은 UTC 09-23)
--
-- 목표: 칸 하나(job_title) · 주석 열(칸 8 · 표 2) · ⭐ 행 적재 0 · 스키마 변경은 job_title 하나뿐. 적재 GAS(ImsLoadCustomer.gs)는 다음 차수.
-- 선행: 20260922201223_customer.sql(손님 표 셋 · 테스트 DB 적용·검증 완료) — ⚠️ 그 파일은 고치지 않는다. 바뀐 것은 여기서 comment on 으로 갈아 쓴다.
-- 정본: docs/design/so-module.md §9-g(프로브 실측) · §9-h(판정 ⑥~⑨) · §9-e(줄마다 결과) · §9-d(뒤집은 것 표 — 9-c ⬜5 를 뒤집었다).
--       이 파일과 정본이 어긋나면 정본이 이긴다. 지시서 ~/asung/prompts/so-mig-2-customer-probe.md · 검토 이견 1~7 은 Caleb 판정(2026-09-22 밤) 전부 채택.
--
-- ═══ 실측 근거 (2026-09-22 16:52~16:56 EDT · docs/probes/CustomerProbe.gs · 9,468명 전량 · 95페이지 · Caleb 실행 · so-module §9-g) ═══
--   ID            Address 19,001 · Contact 9,912 — 전부 있고 전부 고유 ⇒ 두 관계 표의 적재 열쇠는 cin7_id(9-a ② 의 ⬜ 닫힘).
--   Contact       JobTitle 키 9,912 · 값 288 ⇒ ⭐ 판정 ⑨ job_title 을 더한다(9-c ⬜5 「만들지 않는다」를 뒤집었다 — 공급처 API 에 없던 키라 「오지 않는다」는 짐작이었다).
--   MarketingConsent ⚠️ boolean 이 아니라 숫자 — 0 13 · 1 9,898 · 2 1 · 3 0(수집 시점) · 네 값 모두 Caleb 화면 대조 ⇒ 판정 ⑥ 옮기기 표(아래 주석).
--   DefaultForType Shipping 체크 1개 8,687 · 없고 하나 44 · 없고 여럿 7 · 둘 이상 1 / Billing 체크 1개 9,432 · 없고 하나 5 / Business 체크 1개 1 · 없고 하나 3 ⇒ 판정 ⑦ 확정.
--   Address Type  Billing 9,806 · Shipping 9,191 · Business 4 · 셋 밖 0 · 빈 값 0 · Business 만 있고 Shipping 없는 손님 2.
--   Status Active 9,460 · Deprecated 8 · TaxNumber 값 12 · Tags 쉼표 문자열 · 이름 중복 원문 0 · 정규화 뒤 2.
--
-- ⚠️ begin/commit 없음 — 적용은 psql -v ON_ERROR_STOP=1 -1 -f(한 트랜잭션) + supabase migration repair --status applied 20260923012022 (po-module §13-f).
-- ⚠️ 칼럼 순서는 신경 쓰지 않는다(Postgres 는 끝에 붙인다 · 자리 바꾸기로 표를 다시 만들지 않는다).

-- ═══ ① 칸 — customer_contact.job_title (판정 ⑨) ═══
alter table public.customer_contact add column if not exists job_title text;

comment on column public.customer_contact.job_title           is 'Cin7 Contact.JobTitle 원문 · 값 288/9,912(2026-09-22 프로브) · ⭐ 판정 ⑨ — 9-c ⬜5 「job_title 은 만들지 않는다」를 뒤집었다: 공급처 API Contact 키(cin7-api references/supplier.md 101행)에 없던 키라 「오지 않는다」는 공급처에서 옮긴 짐작이었고 손님 연락처에는 온다 · ⚠️ Comment(cin7_comment · 값 18)에도 WIFE · OWNER · PREVIOUS OWNER 같은 직책·관계 말이 섞이지만 합치지 않는다 — Cin7 두 칸 그대로 · Cin7 원문 칸이라 재적재가 덮는다 · 마이그레이션 ② 2026-09-22 신설(§9-h)';

-- ═══ ② 주석 갱신 — 앞 뜻 그대로 + 프로브 결과 (앞 파일 20260922201223 의 문장을 옮겨 와 이어 썼다 · 뺀 문장 없음) ═══

-- customer_contact.marketing_consent — 판정 ⑥ 숫자 옮기기 표
comment on column public.customer_contact.marketing_consent   is '⭐ Cin7 MarketingConsent · nullable · 기본값 없음 — true 동의 · false 동의 안 함 · null 모름(IMS 에서 새로 만든 연락처) · CASL — 동의 기록은 나중에 만들 수 없는 종류라 Cin7 값을 그대로 받아 둔다 · ⚠️⚠️ 보낼 때는 null 을 false 와 똑같이 다룬다 — 확인된 동의(true)에만 마케팅 메일(검토 이견 4 채택) · ⭐⭐ Cin7 값은 boolean 이 아니라 숫자다(2026-09-22 프로브 · 판정 ⑥) — 옮기기: 2 → true(Opt in) · 3 → false(Opt out) · 0 · 1 → null(둘 다 Unknown) · 그 밖 → 적재를 멈추고 보고한다(추정해 넣지 않는다) · 네 값 모두 Caleb 이 Cin7 화면에서 대조(0 Korean Aura · 1 CHOPPAVARAPU SAIDA RAO · 2 Asung Employee - Jason Lee · 3 은 수집 때 0건이라 JOJOJO - Joel Chang 을 Opt out 으로 저장한 뒤 다시 읽어 3 확인) · 분포 0 13 · 1 9,898 · 2 1 · 3 0(수집 시점 · 적재 첫 회엔 JOJOJO 1명이 false 로 들어올 것) · ⚠️ 순서·추론으로 옮기지 마라 — 숫자는 선택 목록 순서(Unknown · Opt in · Opt out)와 다르고 Unknown 이 둘이다 · 「셋 중 남은 하나」로 0 을 Opt out 이라 추론했다가 화면에서 틀렸다';

-- customer_contact (표) — 하위 ID 있음 · JobTitle 더했다
comment on table  public.customer_contact is 'SO 모듈 손님 연락처(Cin7 customer.Contacts[] 대응 · 우리 키 id · 열쇠 cin7_id — ⬜ 하위 ID 유무는 적재 첫 회에 → ✅ Cin7 Contact.ID 있음 · 9,912 전부 고유(2026-09-22 프로브) · 적재 열쇠 cin7_id 확정) · 관계 표 규약 7칸 · DELETE 열림 · TRUNCATE 막음 · ⚠️ is_default · include_in_email · marketing_consent 는 받아 두기만 — 어느 칸이 메일 수신처를 정하는지는 메일 절에서 실물로(판정 ④ · 5-c ⬜) · 적재 첫 페이지에서 Contacts 키 목록을 그대로 센다(JobTitle 이 오면 그때 더한다 → ✅ 왔다 · 값 288 · job_title 을 더했다 · 마이그레이션 ② 2026-09-22 · 판정 ⑨) · 손님당 연락처 0개 12 · 1개 9,191 · 2개 176 · 3개 57 · 4개 13 · 5+ 19 · Default 둘 이상 0 · 기본 없음 2 · ⬜ 재적재 방식(이번 회차에 안 온 cin7_id 를 지울지 is_active=false 로 둘지)은 적재 차수(§9-e) · 정본 docs/design/so-module.md §5-c · §9 · 2026-09-22 신설';

-- customer_address (표) — 하위 ID 있음
comment on table  public.customer_address is 'SO 모듈 손님 주소록(Cin7 customer.Addresses[] 대응 · 우리 키 id · 열쇠 cin7_id — ⬜ Cin7 하위 ID 유무는 적재 첫 회에 · 없으면 손님 단위로 지우고 다시 넣는다 · 그래서 DELETE 가 열려 있다 → ✅ Cin7 Address.ID 있음 · 19,001 전부 고유(2026-09-22 프로브) · 적재 열쇠 cin7_id 확정 · DELETE 는 여전히 열어 둔다 — Cin7 에서 지운 주소가 실제로 생겼다(DALIANA MOMBRUN 중복 배송지 · 9-g) · ⬜ 지울지 is_active=false 로 둘지는 적재 차수 §9-e) · 관계 표 규약 7칸(name 없음) · TRUNCATE 막음 · 오더의 bill_to_*·ship_to_* 는 여기서 칸칸이 복사된다(5-d · 주소록을 FK 로 가리키지 않는다) · 손님당 주소 0개 18 · 1개 712 · 2개 8,286 · 3개 168 · 4+ 284 · 정본 docs/design/so-module.md §5-b · §9 · 2026-09-22 신설';

-- customer_address.is_default_for_type — 판정 ⑦ 확정
comment on column public.customer_address.is_default_for_type is '⭐ Cin7 DefaultForType 을 받되 빈 곳은 규칙으로 메운다(판정 ③): 체크된 것은 그대로 믿는다 · 체크가 없고 그 type 이 하나면 그것을 기본으로 · 여럿이면 비워 두고 그 손님 수를 세어 사람이 정한다 · ⚠️ 확정은 적재 첫 회에 체크율을 센 뒤(거의 다 체크면 메울 필요 없음 · 거의 비었으면 supplier 처럼 Cin7 값을 버리는 쪽) → ✅ 확정(2026-09-22 프로브 · 판정 ⑦): 체크는 믿을 만하다 — Shipping 가진 손님 체크 1개 8,687 · 없고 하나 44 · 없고 여럿 7 · ⚠️ 둘 이상 1 / Billing 체크 1개 9,432 · 없고 하나 5 · 여럿 0 · 둘 이상 0 / Business 체크 1개 1 · 없고 하나 3 · 값 true 18,122 · false 879 · 표: 체크 1개 → 그대로 기본 · 없고 그 type 하나 → 그것 · 없고 여럿 → 비워 둔다 · ⚠️ 둘 이상 → 비워 둔다(둘 중 하나를 고르지 않는다 — 먼저 나온 것·최근 것 모두 추정 · Cin7 이 체크 둘을 막지 않는다 · DALIANA MOMBRUN 사례 · 재적재마다 또 나올 수 있다) · 비워 둔 손님은 「기본을 사람이 정할 손님」으로 세어 적재 보고에 이름을 낸다 · 메운 수 52(44+5+3) · ⬜ 규칙으로 메운 것과 Cin7 값을 가를 표시가 필요한지는 적재 차수(안: 두지 않는다 · 보고에 수만) · 「손님·type 당 하나」는 default_customer_id + customer_address_default_uq 가 지킨다';

-- customer_address.type — 분포 · 판정 ⑧ 배송지 기본값 찾는 순서
comment on column public.customer_address.type                is 'Cin7 Type 원문 · ⭐ CHECK customer_address_type_ck 셋(Billing · Business · Shipping · Cin7 손님 주소 화면 선택지 실측 — 그 밖은 고를 수 없다 · Caleb 2026-09-22 · 검토 이견 2) · null 허용(선택지가 빈 채로 시작한다) · ⚠️ 빈 문자열은 적재 때 null 로(ims_blank_ 전례) · ⭐ Business 는 배송지·청구지 기본값 찾기에 쓰지 않는다 · 📌 주소 type 을 제약하는 첫 표(supplier_address 는 CHECK 없음) · 적재 첫 회에 셀 것: type 빈 줄 수 · 「Business 만 있고 Shipping 없는 손님」 수 → ✅ 셌다(2026-09-22 프로브): Billing 9,806 · Shipping 9,191 · Business 4 · 셋 밖 0 · 빈 값 0 · Business 만 있고 Shipping 없는 손님 2 · Shipping 없는 손님 711(주소가 있으면서 · 주소 0개 18 은 따로) = Billing×1 699 · Billing×2 10 · Business×1 2 · ⭐ 판정 ⑧ 배송지 기본값 찾는 순서(오더를 만드는 자리에서만 · 구현은 SO 오더 화면 차수): ① 기본 Shipping ② Shipping 이 하나도 없을 때만 → 기본 Billing(오더 화면에 「청구지에서 가져옴」 표시 · 체크 기준 708 · 메운 뒤 709) ③ 그 밖 → 비워 둔다(사람이 고른다) · ⚠️ 주소록은 건드리지 않는다 — Billing 을 Shipping 으로 복사해 넣지 않는다';

-- customer.is_active — Status 어휘 둘
comment on column public.customer.is_active                   is '⭐ Cin7 Status 를 여기로 받는다(판정 ① · so.status 와 한 모듈에서 두 뜻이 되는 것을 피한다). ⬜ Cin7 Status 어휘가 둘뿐인지 모른다 — 적재 첫 회에 distinct 를 세고 셋 이상이면 그때 원문 칸을 옆에 더한다(지금 만들지 않는다) → ✅ 둘뿐(2026-09-22 프로브 · Active 9,460 · Deprecated 8 · IncludeDeprecated=true 로 전량) · 원문 칸은 만들지 않는다(확정). 재적재에 안 들어온 cin7 행은 false 로 물러난다';

-- customer.tax_number — 필드명 확정
comment on column public.customer.tax_number                  is '손님 세금 등록번호 · ⬜ §1-s 프로브 목록에 없던 칸(화면에만 보였다) — 필드명·유무는 적재 때 실물로(5-a ⬜) → ✅ 필드명 TaxNumber 확정 · 값 12/9,468(2026-09-22 프로브)';

-- customer.tags — 형식 확정
comment on column public.customer.tags                        is 'Cin7 Tags 원문 · ⚠️ 형식 미확인(문자열인지 배열인지 안 봤다) — text 로 받고 적재 때 본다(검토 이견 5) → ✅ 쉼표로 이은 문자열(2026-09-22 프로브 · null 8,009 · "" 603 · 값 856) · text 원문 그대로 · 빈 문자열은 적재 때 null(ims_blank_ 전례)';

-- customer.name — 이름 중복 실측
comment on column public.customer.name                        is 'Cin7 Name 원문 · NOT NULL(부분 객체를 첫 요청에서 세우는 제약 · po-module §5) · ⚠️ 유니크 없음 — product 576종 중복 선례 · 손님 이름 중복은 미측정 → ✅ 셌다(2026-09-22 프로브 · 원문 중복 0 · 정규화 뒤 2 · 유니크 안 건 판단 그대로) · 열쇠는 cin7_id';
