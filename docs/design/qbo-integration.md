# QuickBooks Online 연결 — 설계 정본

작성: 2026-10-29 · 회사 PC · docs-1029 · 판정 617(확인) · 867 ~ 873(원문 표는 `so-module.md` §87-a) · 선례 `freightcom-integration.md`(날짜 절은 하루의 이야기 · 이 문서가 「지금 규칙」)
⚠️ 말하는 틀 — IMS 는 Cin7 없이 돈다(ims-principles 원칙 1). 이 설계의 주어는 IMS 와 QuickBooks Online(Intuit) 둘뿐이다.
⭐ 상태 [2026-10-29] **운영 = 연결됨 · 싱크 없음** — Asung-IMS(fazgmyvzzhqybtvtktyg · 11-01 부터 그대로 운영 · 617)가 실제 회사 **Asung Trading Inc.**(realm `…6496` · Production)에 11:48(토론토) 연결 · 샌드박스로 연결 → 끊기 → 다시 연결을 실제로 한 뒤(868) Intuit 설문 제출 → 운영 키
⚠️ **연결만 한다 — IMS 에는 장부(QBO)로 거래를 보내는 코드가 없다.**(10-29 상태 · → [2026-11-01 밤] 아래 「쓰기 길이 섰다」) 연결 뒤 하는 일 = 회사 이름 읽기(CompanyInfo) + 하루 한 번 토큰 갱신 · 그 밖의 호출 0 · 싱크는 뒤 차수(§11 · deferred 260 · 327 · 341)
⭐ 상태 [2026-11-01 · so-module §95 · 판정 933 · 934] **연결 + 읽기 조회 · 짝 표 · 거울 · 받기(pull) — 보내기는 없음** — EF qbo 에 `query` · `read` · `pull`(GET 만 · admin · cron 불가) · 표 `qbo_entity`(거울) · `qbo_pull_state` · `qbo_link`(짝) · Settings → QuickBooks matching · QBO 로 쓰는 호출 0(위 줄의 「그 밖의 호출 0」 은 10-29 상태)
⭐ 상태 [2026-11-01 밤 · so-module §96 · 판정 935 ~ 946 · 951] **쓰기 길이 섰다 — 손님 · Item 만들기** — 열쇠 QUICKBOOKS(`qbo` · `qbo:read` · 945) · 보내기 일감 `qbo_job` · 쓰기 `apiWrite`(POST · 재시도 없음) · EF `send`(열쇠 · 손으로 · cron 없음) · **운영 첫 쓰기 2026-11-01 밤 손님 1 명 → QBO Customer 10740** · 인보이스 · 크레딧은 2b(위 줄의 「보내기는 없음」 은 11-01 낮 상태) · 정본 §14
⭐ 상태 [2026-11-02 · so-module §97 · 판정 959 ~ 966 · 968 · 969 · 971] **인보이스 · 크레딧 노트 · void 가 나간다 — 북키퍼가 골라서** — 2b1 · 2b2(인보이스 · invoice_void · cron 61) · 2c1(크레딧 노트 · credit_void) · 2d1(골라 보내기) · 화면 Sales → **QuickBooks**(`qbo-send.html` · qs v1) · **첫 인보이스 60000 → QBO 172335**(sent · mismatch 0) · `qbo_send_enabled` off 그대로(cron 61 은 호출 0 · 켜는 때는 나중에 Caleb) · Cin7 ↔ QBO 연결은 Caleb 이 끔(deferred 375 닫힘) · 정본 §14-b ~ §14-e
⭐ 상태 [2026-11-03 새벽 · so-module §98 · 판정 978 ~ 993] **결제(Payment) 보내기가 섰다 — 아직 켜지 않음** — 2e-1a(paypal · 수표 #105 · 미래 결제일) · 2e-1a2(Clearing - Shopify) · 2e-1b(결제 일감 · 몸 · 지문 · 트리거 · 백필) · 2e-1c(EF · void = operation=update&include=void · Balance 가드) · `qbo_send_payments_enabled` off · cron 62 등록 전 · 켜는 순서는 §14-f(deferred 453) · 정본 §14-f
⭐ 상태 [2026-11-03 밤 · so-module §99 · 판정 995 · 1009 ~ 1017 · 1034] **크레딧 붙임 일감(0 원 Payment)이 DB 에 섰다 — EF 는 아직(2e-2-1b)** · §14-g · ⚠️ 다음 할 일 = **결제 먼저 켜기**(1034 · §14-f 「켜는 순서」) · 2e-2-1b 배포 전 cron 62 kinds 는 **둘**
⭐ 상태 [2026-11-04 · so-module §100 · 판정 1034 · 1038] **결제 · 크레딧 붙임이 자동으로 나간다** — cron 62 `ims-qbo-send-payments`(jobid 62 · `*/5` · kinds 넷) · `qbo_send_payments_enabled` on · 2e-2-1b `48d5ca4` 배포 · 인보이스 · 크레딧 노트는 여전히 북키퍼가 골라서(`qbo_send_enabled` off · 971) · 다음 = 1d 이월 짝(452) → 2e-3(454) → 원가 · Bill(459) · §14-f 「켜짐」 · §14-g 「2e-2-1b」
⭐ 상태 [2026-11-06 · so-module §101 · 판정 1039 · 1044 ~ 1047 · 1054] **이월 인보이스 짝 끝**(1d-1 · 1d-2 · 310 장 중 자동 299 · 사람 9 · 남음 2 · §14-h · deferred 452 닫힘) · **인보이스 송장 31 자**(qbo-trk-1 · §14-i) · 결제는 QBO 하위 손님(BillWithParent) 묶음이 있어야 본사 결제가 매장 인보이스에 붙는다 · 다음 = 2e-3(454)
⭐ 상태 [2026-11-07 · so-module §102 · 판정 1056 ~ 1064] **이월 받아 둔 돈의 붙임이 나간다**(2e-3-1 · 1b · OC-<인보이스>-<n> CreditMemo + 0 원 Payment · SEND_KINDS 14 · cron 62 kinds **여덟** · 첫 실물 60172 · §14-j) · **60189** = 가드가 중복을 막음 → 북키퍼 손 분개 Delete → Retry → sent(1060 · 1061) · 대조 기준 = **손님 잔액**(QBO Open Balance = IMS Available) · 환불 2e-3-2 는 남음(454 부분 · 1056 ~ 1058) · 다음 = 2e-3-2(qbo-sync-2e-3-2-0 조사) → 459
⭐ 상태 [2026-11-08 · so-module §103 · 판정 1065 ~ 1076] **환불(크레딧 노트 몫)이 나간다** — 환불 한 줄 = Purchase(Expense) 한 장 + 0 원 Payment(CreditMemo 를 잇는다) · SEND_KINDS **18** · cron 62 kinds **열둘** · 첫 실물 CR-01011 → 172912 · 172913 / CR-01012 → 172914 · 172915 · 받아 둔 돈 몫 · 이월 몫 환불은 failed(1067 · deferred 500) · §14-k
⭐ 상태 [2026-11-08 저녁 · so-module §104 · 판정 1080 ~ 1090] **원가 · 공급처 줄기(459) 판정 끝 · 짓기 전** — 상품 Bill · 결제는 IMS 가 보낸다(1080 · 1081) · 판매 원가 = 하루 · 창고마다 JE + SO 줄(1082) · 출발점은 맞추지 않고 움직임만(1086) · §15
⭐ 상태 [2026-11-08 밤 · so-module §105 · 판정 1091 ~ 1103] **3-1 끝 · 하루 원가 장 설계 끝(3-2-0) · 짓기 전** — 계정 통화 `ref_account.currency_code` · 공급처 A/P · 손님 A/R 통화 막기(지연 제약 트리거 둘 · 1091 · deferred 499 닫힘) · 조정 기본 계정 `inv_adjust_account()`(1087) · 하루 장 = 22 칸 표 · 보낸 몫 = 센트 합 + 차액(1092) · 입고는 보류(1096) · Location 없음 · Entity = 손님(1102 · 1103) · 다음 = 3-2 DB · §15-g · §15-h
⭐ 상태 [2026-11-09 · so-module §106 · §107 · §109 · §110 · 판정 1104 ~ 1138] **하루 원가 장 · 공급처 Bill · 공급처 결제가 운영에서 나간다 — 모두 북키퍼 손 Send** — 원가 장(cost_day · JournalEntry) 12 장 sent · cron 67 은 장 행만(§15-j · §15-k) · 공급처 Bill 7 장 sent(4-3 · 4-4 · §15-m) · 공급처 결제 BillPayment 첫 실물 **173092**(4-5a · 4-5b · 4-5c · §15-n) · USD 결제 3 건은 환율 대기 · SEND_KINDS **24** · 공급처 kind 는 cron 61 · 62 밖 · 은행 피드 Match 는 북키퍼 · 다음 = USD 3 건 → 4-6(켜기 · 정본) · E-8(538)
⭐ 상태 [2026-11-10 · so-module §111 · 판정 1143 ~ 1150] **조기 결제 할인이 있는 공급처 결제도 나갈 수 있다 — 손 Send** — 할인 = VendorCredit(kind `vendor_credit` · ims_kind `po_discount`)을 결제의 같은 Send 에서 먼저 · BillPayment 에 Bill 줄 + VC 줄 · TotalAmt = 낸 돈(E-8 · 4-7a · 4-7b · 4-7c) · 막는 것 여섯(세금 몫 · 세금 있는 인보이스 · 청구서 할인 · 붙은 크레딧 · 금액 ≠ 붙임 합 · 시작일 전) · 공급처 인보이스 지급 기한 자동(1144) · 손님 결제 void 뒤 영구 blocked 고침(qbo-pay-fix-1 · 173093) · 할인 받은 결제 실물 0 · §15-o
⚠️ 토큰은 **Vault** 에만 — 표 · 화면 · 기록 · EF 응답 어디에도 토큰이 없다(처리방침의 약속 · 867)

---

## 1. 무엇을 하나 — ~~연결만~~ 연결 · 읽기 · 짝 · ~~보내기는 뒤([2026-11-01])~~ → 손님 · Item 쓰기 섰다 · 인보이스는 2b([2026-11-01 밤])

- 목표(Caleb 2026-10-29): 「오늘은 컷오버전에 퀵북 인테그레이션을 해놓으려고 해. 컷오버 이후로 미뤘지만, 싱크는 컷오버이후에 하더라도, 연결은 해놓고 싶어.」
- Caleb 의 물음 「ims가 퀵북에 연결된다고 해서 퀵북과 싱크되는 것은 아니지?」 → **맞다**
  - 연결 = OAuth 2.0 승인 한 번(admin 이 Settings → QuickBooks → Connect → Intuit 동의) · 토큰을 Vault 에 두고 하루 한 번 굴린다
  - 보내는 것 0 — 인보이스 · 결제 · 크레딧 · 손님 · 품목 어느 것도 아직 QBO 로 가지 않는다(10-29 · → [2026-11-01 밤] 손님 · 품목은 간다 · §14)
- **Cin7 → QuickBooks 연결은 따로 그대로**(QBO 는 여러 앱을 동시에 연결한다) — ⚠️ IMS 싱크를 지을 때 **Cin7 의 QBO 싱크를 끄는 시점**을 함께 정한다(둘이 같은 거래를 보내면 두 번 · deferred 375)
- → [2026-11-01 · so §95] 읽기 조회(qbo-read-1 · §5) · 짝 표 · 거울 · 받기(qbo-sync-1a ~ 1c · §12) 섰다 — 여전히 **QBO 로 보내는 것 0**(GET 만 · `assertReadOnlyRequest`)
- → [2026-11-01 밤 · so §96] **쓰기 길 섰다**(qbo-sync-2a · 2a′ · §14) — 손님 · Item 만들기(`apiWrite` POST 만 · `assertWriteAllowed`) · 첫 운영 쓰기 손님 1 명(Customer 10740) · 인보이스 · 크레딧(935 ~ 944 · 951)은 2b
- 범위 밖(싱크 차수 몫): 이월 인보이스 · 받아 둔 돈(kind · method opening)은 보내지 않는다(341 · 786) · 다중 통화 · 캐나다 세금 · 지우기(deletes)

## 2. 표 — 칸 · 상태 (qbo-1a `20261029160000`)

| 표 | 무엇 | 컷오버 |
|---|---|---|
| `qbo_connection` | 연결 한 줄(`singleton` boolean PK · check) — env(sandbox · production) · realm_id · company_name · status(connected · needs_reconnect) · connected_by · at · **토큰 칸 없음**(`refresh_secret_id` · `access_secret_id` = vault.secrets.id) · access_expires_at · refresh_expires_at · `token_version`(판 번호) · `refreshing_until` · `refreshing_by`(임대) · last_refresh_at · last_error · last_error_at | K |
| `qbo_oauth_state` | CSRF state — EF 가 만든 32 바이트 무작위의 **sha256 hex 만** · staff_id · env · 10 분 · 한 번(조건부 update 1 행) · 지난 것은 state_new 가 지운다 | K |
| `qbo_call_log` | EF 호출 기록(fc_call_log 꼴 + env · realm_id · **intuit_tid**) · action · ok · http_status · error 400 자 · by_staff · ms · 90 일(EF 가 호출 끝에 지운다) · [2026-11-01 qbo-read-1 `20261101190000`] `detail` jsonb(조회 문장은 리터럴 → `?` · entity · 받은 수 · **결과 행 없음**) | K |
| `qbo_entity` | [qbo-sync-1a `20261101210000` · 934] QBO 목록 거울 — PK (realm_id, qbo_type, qbo_id) · qbo_type 7(Account · TaxCode · Term · PaymentMethod · Customer · Vendor · Item) · name · sku · parent_id · fully_qualified_name · active · sync_token · fetched_at · gone_at(**이 칸뿐 — 연락처 · 주소 · 금액 0**) | — (컷오버 뒤 생김) |
| `qbo_pull_state` | [1a] 종류마다 받기 진행 — started_at · by · next_start · received · pages · finished_at · gone(완주 때 안 온 행에 gone_at) | — |
| `qbo_link` | [1a] IMS 행 ↔ QBO Id 짝 — ims_kind 9(account · tax_rule · payment_term · payment_method · customer · supplier · product · charge · service) · `ims_id` text 다형(FK 없음 · FK 는 by_staff → ims_staff 만) · matched_by(auto_code · auto_name · auto_map · auto_sku · auto_sku_name · manual) · qbo_name_at_match · 유일 (realm, ims_kind, ims_id) · **QBO 쪽 부분 유일 `where ims_kind <> 'tax_rule'`**(tax_rule 만 N:1 — Sale · Purchase 둘이 한 TaxCode) | — |

- RLS · grant(1a 세 표): RLS 켜고 정책 0 · grant 0 — 창구로만
- RLS · grant: `qbo_connection` · `qbo_oauth_state` = 정책 0 · grant 0(창구만) · `qbo_call_log` = authenticated 읽기 · service_role 넣기 · 지우기(fc_call_log 와 같다)
- Vault 이름: `qbo/<env>/refresh` · `qbo/<env>/access`(supabase_vault 0.3.1 · dump · 백업에는 암호문만)
- inv_config 키: `qbo_realm_sandbox` · `qbo_realm_production`(고정 회사 · §7) · `qbo_alert_to`(끊김 메일 받는 사람 · 기본 caleb@asung.ca · 869 · qbo-1b)
- 컷오버(cutover-delete.sql k11 · reload-procedure §P-1): 셋 다 **K(남김)** — 설정 · 10 분짜리 · 기록(거래 아님 · 거래 표 FK 0) · Vault 는 그 스크립트 밖 · 연결은 컷오버 날 손대지 않는다(이미 운영 회사에 연결됨)

## 3. 창구 — DB 가 문 · 검사 · 기록 · EF 는 Intuit 과 나른다

qbo-1a 창구 12 + 속 함수 4 · qbo-1b +1 · qbo-1c 재발행 6(WHERE · 바이트 그대로 + 열쇠 칸).

| 창구 | 누가 | 무엇 |
|---|---|---|
| `qbo_status()` | 로그인한 직원 누구나 | Settings 가 읽는 상태 한 줄 — 토큰 · Vault id 없음 · 연결 없으면 `status none` · `caller_is_admin`(단추를 보일지) · `pinned_realm`(env 별 고정 회사) |
| `qbo_admin_gate()` | authenticated → **admin 만** | EF 가 사용자 JWT 로 부른다 · 활성 admin 이 아니면 거부(870) · 통과하면 staff_id · name |
| `qbo_state_new(env, hash)` | admin | state 해시 한 줄(10 분) · 지난 것 지움 |
| `qbo_realm_clear(env)` | admin · 연결 없을 때만 | 고정 회사 비우기(화면 **Untie company**) |
| `qbo_state_consume(hash)` | service_role(EF callback) | 10 분 · 한 번 · 조건부 update 1 행 |
| `qbo_connection_save(…)` | service_role | 토큰 교환 뒤 — realm 고정 검사(처음이면 inv_config 에 고정 · 다르면 거부) · Vault 넣기 · 연결 행 insert … on conflict |
| `qbo_company_name_set(name)` | service_role | CompanyInfo 의 회사 이름 |
| `qbo_token_get()` | service_role | Vault 에서 토큰 둘 + 판 번호(EF 안에서만) |
| `qbo_refresh_claim(owner)` | service_role | 갱신 임대 30 s + 토큰 + 판 번호(§6) |
| `qbo_refresh_save(version, …)` | service_role | 판 번호가 같을 때만 쓰고 +1 · 임대 풀기 · 옛 판 거부 |
| `qbo_mark_needs_reconnect(error)` | service_role | connected → needs_reconnect · **바뀌는 순간 한 번** mail_outbox(kind `qbo_reconnect`)(869 · qbo-1b 재발행) |
| `qbo_connection_delete()` | service_role | Vault 두 행 + 연결 행 + state 전부 지움(처리방침 약속) |
| `qbo_last_error_set(error)` | service_role(qbo-1b) | 상태는 그대로 · last_error 만(갱신 경합으로 새 토큰을 잃었을 때 Settings 가 보이게) |

속 함수: `qbo_env_check` · `qbo_vault_put` · `qbo_vault_get` · `qbo_vault_drop`(grant 0)

[2026-11-01 · qbo-sync-1a `20261101210000` · 1c `20261101230000`] 짝 · 거울 창구 9(authenticated · 안에서 ~~`ims_is_admin`~~ → [11-01 밤 · 945] 열쇠 `qbo_key_gate` — 속 `qbo_sync_gate`) — 쓰임 · 규칙은 §12

| 창구 | 무엇 |
|---|---|
| `qbo_pull_begin(type, …)` · `qbo_entity_upsert(type, …, rows jsonb, …)` · `qbo_pull_finish(type, …)` | 받기 한 바퀴 — EF pull 이 **사용자 JWT** 로 부른다(rpcUser) · 완주 때 안 온 행 gone_at |
| `qbo_match_auto(p_kind, p_after text default null, p_limit int default 5000)` | 자동 짝 **묶음**(1c · 최대 20000) → next_after · remaining · done — 부르는 쪽이 done 까지 돈다 · 임시 표 analyze |
| `qbo_link_set(kind, ims_id, qbo_id)` · `qbo_link_clear(kind, ims_id)` | 사람 짝(manual · 덮으면 manual) · 풀기 |
| `qbo_link_summary()` · `qbo_link_page(…)` · `qbo_entity_find(…)` | 화면(set v13) 읽기 — 요약 · To match / Matched / All · QBO 찾기 |

속 함수 4(grant 0): `qbo_sync_gate` · `qbo_realm_of` · `qbo_type_of` · `qbo_ims_rows`(IMS 쪽 행 · 1c 에서 rows 20000)
마이그레이션: `20261029160000` qbo-1a · `20261029190000` qbo-1b(끊김 메일 · mail_outbox.kind 에 qbo_reconnect · inv_config qbo_alert_to · qbo_mark_needs_reconnect 재발행 · qbo_last_error_set) · `20261029210000` qbo-1c(WHERE — §5 끝)
EF: `supabase/functions/qbo/index.ts`(Deps 실물) + `../_shared/qbo.ts`(순수 함수 + 흐름 handle) · 시험 `qbo/qbo_test.ts`(Intuit · DB 무접촉) · DB 시험 `supabase/tests/qbo_1a_check.sql` · `qbo_1b_check.sql` · `qbo_1c_check.sql`

## 4. 문(권한) — 870 · [2026-11-01 밤] 945

- ⭐ [2026-11-01 밤 · 판정 945 · qbo-sync-2a `20261102003000`] **문이 둘로 갈렸다** — 아래 870 은 **연결류 · 원문 조회**에 그대로 · 짝 · 받기 · 보내기는 새 열쇠 **QUICKBOOKS**
  - 열쇠 = Staff 의 perms `qbo`(쓰기) · `qbo:read`(보기) · 문 `qbo_key_gate(p_write)` = 활성 직원 + perms 글자 그대로(`mcp_gate` 꼴) · ⚠️ **admin 도 켜야 한다**(`ims_is_admin` 을 보지 않는다 · `ims_can_view` 안 씀)
  - 열쇠 몫: 짝 화면(Settings → QuickBooks matching) · 손 짝 · Unlink · Refresh list(pull) · Match automatically · 보내기 일감 더하기 · 다시 · 건너뛰기 · **send** — 읽기 셋(`qbo_link_summary` · `qbo_link_page` · `qbo_entity_find`)은 `qbo:read` 로도 · `qbo_sync_gate` 는 몸이 `qbo_key_gate(true)` 로 바뀜(1a 창구 9 · 1c 그대로)
  - admin 몫(870 그대로): 연결 · 끊기 · 다시 연결 · Untie · refresh · ping · **원문 조회 query · read**(933) — EF `ADMIN_ACTIONS` = qbo_admin_gate · `KEY_ACTIONS`(pull · send) = qbo_key_gate(true)
  - `qbo_status()` 에 `caller_qbo`(write | read | null) · `caller_is_admin` 은 그대로(연결 칸) · 화면 set v14(asung-ims `67c168f` — 보기만이면 단추 숨김)
  - 켠 사람(2026-11-02 00:59 UTC 재셈) **셋** — Caleb(admin · SQL 로 켬 — Staff 화면은 자기 행을 못 바꾼다) · Justin Kim(manager) · Jeannie Kim(supervisor) · 모두 쓰기 `qbo` · 둘 다 담당자(Caleb 의도 확인)
  - ⚠️ 기각된 B(870 「사람마다 켜는 새 열쇠」)가 보내기에 대해서는 945 로 섰다 — 연결은 여전히 admin


- 연결(start) · 끊기(disconnect) · 다시 연결 · 고정 회사 비우기 · 갱신(refresh) · 연결 확인(ping) = **IMS admin 역할만** — 새 열쇠 없음 · DB 가 `ims_is_admin()`(20260915141105 · 하나뿐 · 다시 만들지 않는다)으로 본다 · ping · refresh 도 admin(qbo-1b 이견 8)
  - Caleb(870 「A」) · 기각 B = 사람마다 켜는 새 열쇠(장부 쓰기 권한을 사람 단위로 나누게 되고 열쇠 · Staff · 권한 목록이 따라온다)
  - 실측: IMS admin 은 1 명(2026-10-29)
- 상태 읽기(status) = 로그인한 직원 누구나(토큰 없음)
- cron 길 = `x-ims-cron-key` == 비밀값 `IMS_CRON_SECRET`(미설정이면 500 fail-closed · drive 꼴) · **refresh 만**
- EF 는 `verify_jwt = false`(Intuit 이 브라우저를 JWT 없이 GET callback 으로 보낸다 · freightcom · drive 와 같은 까닭) — 문은 함수 안: 직원 길 = 세션 JWT 를 DB 창구로 그대로 · `_shared/authgate.ts` 는 옛 WMS 문이라 쓰지 않는다

## 5. EF `qbo` — 액션 · callback · 환경

- POST JSON `{action}` + 직원 세션 JWT: `status`(누구나) · `start` · `disconnect` · `refresh` · `ping`(admin) · [2026-11-01] `query` · `read` · `pull`(admin · **cron 길 불가**) · → [2026-11-01 밤 · 945] `pull` 은 열쇠 qbo(admin 아님) · 새 `send {limit?}`(열쇠 qbo · cron 길 불가 · §14)
- **읽기 조회 query · read(qbo-read-1 `cc06d5d`)** — Intuit API **읽기** 호출은 `apiCall` 하나로(→ [11-01 밤] 쓰기는 `apiWrite` 하나 · §14) · **GET 만**(`assertReadOnlyRequest` — 다른 메서드는 거부) · 허용 목록 24 + Preferences · CompanyInfo(Employee 없음 · ExchangeRate 있음) · MAXRESULTS 기본 100 · 1 ~ 1000 밖은 400 · 응답 > 5 MB 413 · 429 재시도 없음 · 401 은 `withAuthRetry`(ping 과 공용 · §6) · rows 는 scrub 하지 않는다(SyncToken 보호 — scrub 의 꼴 치환이 값을 깨뜨린다) · Customer · Vendor 는 **`select *` 거부 · 연락처 · 주소 칸(PII_FIELDS 9)을 고르면 거부**(칸 이름을 적어야 한다 · `_shared/qbo.ts` PII_ENTITIES) · 단건 read 는 연락처를 벗겨 돌려준다(933) · → [2026-11-01 밤 · 2a′ 이견 17] **거래 다섯(Invoice · CreditMemo · Payment · SalesReceipt · RefundReceipt)도 같은 가드** — `select *` 거부 · BillAddr · ShipAddr · BillEmail(+ Cc · Bcc) · ShipFromAddr 거부 · read 는 벗김(PII_ENTITIES 7 · PII_FIELDS 13) ⇒ ⚠️ 콘솔 조회에서 이 일곱은 칸 이름을 적는다 · 기록 = `qbo_call_log.detail`(값은 ? · 결과 행 없음)
- **받기 pull `{entity, start}`(qbo-sync-1b `a7493de` · 1c `0e12be0`)** — 종류 7 · 한 번 = 한 쪽 1,000 · `where Active in (true, false)`(QBO query 는 기본 활성만 — TaxCode 만 조건 없음 · 실측) · Customer · Vendor 칸 목록에 연락처 없음 · ⚠️ **Item 은 `select *`** — 칸을 고르면 QBO 가 Sku 를 안 준다(sparse · 11-01 실측 · 1b 에서 product 짝 0 → 1c) · 1a 창구를 사용자 JWT 로 · detail 에 행 없음 · 화면이 start 를 넘기며 끝까지 부른다
- **start**: admin 문 → state 32 바이트(base64url) → DB 에 sha256 → Intuit 허락 주소(scope `com.intuit.quickbooks.accounting` · redirect_uri = `<SUPABASE_URL>/functions/v1/qbo/callback`) — 화면은 **같은 탭**으로 간다
- **callback**(GET · Intuit 이 브라우저를 보낸다) = **언제나 302 · 본문 없음 · Location 은 코드에 하나 고정** `https://ims.asung.ca/settings.html?t=qbo&qbo=connected` | `&qbo=error&why=<낱말>` — 요청 값을 Location 에 섞지 않는다(Intuit 보안 요건)
  - why 낱말 여섯: `denied`(손님이 거절 · error=) · `state`(없음 · 지남 · 두 번) · `exchange`(code 교환 실패) · `realm`(고정 회사와 다름 — 받은 토큰은 revoke) · `save` · `env`(QBO_ENV 없음 · state 의 env 와 다름 · 그 env 의 앱 키 없음)
  - 순서: error= → state 의 sha256 으로 consume → env 대조 → code 교환(Basic · urlencoded · 같은 redirect_uri) → realmId 숫자 → `qbo_connection_save` → CompanyInfo → `qbo_company_name_set` → 302
  - 회사 이름은 꾸밈 — 이름 읽기 · 저장이 실패해도 연결은 저장됐고 302 connected · 흔적은 qbo_call_log(action `company_name` · ok false · DB 거부 글) · last_error 는 안 쓴다(토큰 건강의 자리 · qbo-1d)
- **환경**: 비밀값 `QBO_ENV`(sandbox | production · 없으면 500) 와 연결 행의 env 가 같아야 한다 — **명시 값**(freightcom 의 `db_role = 'test'` 가드는 환경을 가르지 못한다 · Asung-IMS 는 컷오버 뒤에도 db_role 'test' · cutover-delete.sql:16)
  - 어긋나면 refresh · ping 은 409 「disconnect it in Settings → QuickBooks, then connect again」 · **status · disconnect 는 열려 있다**(운영 전환 날 빠져나올 길 · qbo-1b 이견 5) · status 응답에 `env_mismatch`
- 비밀값 이름: `QBO_ENV`(지금 **production**) · `QBO_CLIENT_ID_SANDBOX` · `QBO_CLIENT_SECRET_SANDBOX` · `QBO_CLIENT_ID_PRODUCTION` · `QBO_CLIENT_SECRET_PRODUCTION` · `IMS_CRON_SECRET`(기존) — 값은 Caleb 이 `read -rs` 로 넣음(화면 · 기록 0)
- **discovery**: 샌드박스 `https://developer.api.intuit.com/.well-known/openid_sandbox_configuration` · 운영 `…/openid_configuration` · 24 h 캐시(함수 인스턴스 메모리) · 실패면 캐시 · 캐시도 없으면 500 — **코드에 박은 주소 폴백 없음**
- API 기본 주소 · 토큰 끝점 몸 · revoke 몸 · intuit_tid 머리 = Intuit 공식 oauth-jsclient 소스 + discovery JSON(출처는 `_shared/qbo.ts` 머리) · `minorversion=75`(2025-08-01 부터 1 ~ 74 는 무시 · 검색 요약)
- **지역**: Supabase Regional Invocations ca-central-1 — 화면 invoke 는 region 옵션 · cron 은 `x-region: ca-central-1` 머리 · callback 은 고정하지 않는다(Intuit 이 부른다)
- **scrub**: 토큰 · client secret · code 는 응답 · 기록 · 오류 · console 어디에도 남기지 않는다 — 모든 글이 `scrub()` 을 지난다(정확 값 치환이 주 · 꼴 치환은 보조) · 토큰 끝점 · revoke 의 요청 몸은 기록하지 않는다
- **call_log**: Intuit 호출 한 번 = 한 줄(intuit_tid 와 함께 — Intuit 지원 문의 열쇠) · IMS 안 줄(callback · disconnect · company_name)도 남는다(이들은 intuit_tid 없음 — 맞다)
- ⚠️ **REST safeupdate** — EF 는 PostgREST 로 창구를 부른다 · authenticator 가 safeupdate 를 실어 **WHERE 없는 update · delete 는 21000**(psql 시험은 safeupdate 를 못 실어 통과한다) · qbo-1a · 1b 의 일곱 문장(창구 여섯)이 샌드박스 ping 에서 422 「UPDATE requires a WHERE clause」 → qbo-1c 가 `where singleton` · state 는 `where s.state_hash is not null` · `insert … on conflict do update` 는 INSERT 라 대상 아님 · qbo_1c_check.sql 의 **정적 nowhere 스캐너** + 적용 뒤 REST 한 번(asung-workflow §4 「REST 두 겹」)
- 배포: `supabase functions deploy qbo --project-ref fazgmyvzzhqybtvtktyg`(qbo-1b · 1d) · mail EF 재배포(qbo-1b · plain kind)

## 6. 갱신 — 임대 + 판 번호 · cron 59 · 끊김

- 왜 임대 + 판 번호: **잠금을 쥔 채 Intuit 을 부를 수 없다**(PostgREST 한 호출 = 한 트랜잭션) · Intuit 은 갱신마다 refresh_token 을 바꾼다 — 옛 값을 다시 쓰면 invalid_grant
  - `qbo_refresh_claim`(임대 30 s · 토큰 + 판 번호) → Intuit refresh → `qbo_refresh_save`(판 번호가 같을 때만 · 응답의 **새 refresh_token 을 매번 저장** · +1)
  - 임대를 못 받으면 1.5 s 씩 최대 15 s 기다렸다 새 판을 읽는다 · 두 갱신이 겨뤄 이쪽 토큰을 버렸으면 `qbo_last_error_set`(상태 그대로 · 다음 갱신이 invalid_grant 면 Reconnect)
- 언제: API 를 부를 때 접근 토큰(1 시간)이 **5 분 안**에 끝나면 먼저 · + cron 하루 한 번(강제 갱신 — 갱신 토큰을 굴려 둔다)
- **cron jobid 59 `ims-qbo-refresh`** · `10 9 * * *`(09:10 UTC · 토론토 05:10 EDT / 04:10 EST) · `where exists (… status = 'connected')` 일 때만 · 열쇠는 jobid 55 `ims-mail-drain` 의 command 에서 꺼냄(64 자) · `x-region: ca-central-1` · 기록 `supabase/ops/cron.sql`
- 재시도: 네트워크 · 5xx 만 1 회 · **API 401 → 강제 갱신 한 번 뒤 다시** — 그래도 401 이면 needs_reconnect(접근 토큰 만료도 401 이라 곧바로 끊김으로 보면 시간마다 끊김 메일 · qbo-1b 이견 4)
- **invalid_grant**(갱신 토큰 만료 · 취소 · QBO 쪽에서 끊김) → `qbo_mark_needs_reconnect` · 다시 시도하지 않는다 · 그 뒤 cron 은 where 가 거른다(호출 0)
- **끊김 메일(869)**: connected → needs_reconnect 로 **바뀌는 순간 한 번**(for update 행에서 봄 — EF 둘이 같이 찍어도 한 번 · 이미 needs_reconnect 면 0) · 받는 사람 `inv_config.qbo_alert_to` = caleb@asung.ca 한 사람(주소 하나) · 보내는 주소 = mail_doc_from(info@) · 메일 insert 는 서브트랜잭션(실패해도 표시는 남는다) · 주소가 비었거나 틀리면 메일만 건너뜀 · 그리기 = EF mail 의 plain kind(payload 의 subject · body_text)
  - Caleb(869 「A」) · 기각 B = info@(받는 사람이 다시 연결할 수 없다) · admin 이 늘면 받는 사람을 넓힌다 · 바꾸기는 지금 마이그레이션(화면 칸은 뒤)
  - ⬜ 실물 시험 아직(샌드박스에서 QuickBooks → Apps 로 끊은 뒤 refresh → mail_outbox 한 줄 · 한 번만 · 운영에서는 하지 않는다 · deferred 377)
- 수명(실측 2026-10-29 · §10): 접근 토큰 1 시간 · **갱신 토큰 = 연결 시각 + 101 일 · 갱신해도 밀리지 않음**(~~짐작 — 하루 뒤 cron 으로 확인 · deferred 370~~ → ✅ [2026-10-30 · so-module §90-d′] 확인 — 10-30 05:10(토론토) 첫 운영 갱신 ok 200 뒤에도 refresh_expires_at = 2027-02-07 15:48 UTC 그대로 · deferred 370 닫힘) ⇒ ~~100 일쯤마다 Reconnect 가 필요할 수 있다~~ → ~~**2027-02-07 15:48 UTC 전에 Reconnect 가 필요하다**(deferred 396)~~ · 미리 알림은 판정 전(deferred 371) → [2026-11-09 정정 · so-module §107-c 2] 11-09 실측 refresh_expires_at **2027-02-17 09:10:02Z** — 밀렸다 · 갱신 토큰이 바뀌는 갱신 때 그 시각 + 약 101 일로 밀린다(짐작 · 09:10 = cron 59 시각) · cron 59 가 돌면 고정된 Reconnect 날짜는 없다 · 지금 기한은 Settings 의 날짜 · 396 닫힘(짐작) · 371 은 「갱신이 멈췄을 때」

## 7. 끊기 · 다시 연결 · realm 고정 · Untie

- **끊기**(admin · Settings → Disconnect): Intuit revoke(refresh_token · Basic) → **실패해도** `qbo_connection_delete()`(Vault 두 행 + 연결 행 + state 전부) → call_log(action disconnect · by_staff) · revoke 가 실패했으면 응답 글에 「QuickBooks → Apps 에서도 끊어 달라」 · 처리방침 약속 「관리자가 끊으면 지운다」(867)
- **다시 연결** = Connect 와 같은 길(같은 탭 → Intuit → callback) — 새 101 일
- **realm 고정**: 처음 연결한 회사 id 를 env 별로 `inv_config.qbo_realm_<env>` 에 · 다른 회사는 저장 거부(callback why=realm · 받은 토큰은 revoke)
  - 까닭: 싱크가 시작되면 IMS 행이 QBO id(손님 · 품목 · ~~`ref_tax_rule.qbo_id`~~ → [2026-11-01] `qbo_link` · §12)를 가리킨다 — 회사가 바뀌면 짝이 전부 틀어진다 · `qbo_link` · `qbo_entity` 는 realm_id 칸을 갖는다
  - 지금: production = `…6496`(전체 값은 DB inv_config.qbo_realm_production · Settings 화면 — 판정 873)(Asung Trading Inc.) · sandbox = `9341458557490536`(Sandbox Company CA 9bca) — 둘 다 남아 있다
- **Untie company**(`qbo_realm_clear`) = admin · **연결이 없을 때만** — 회사 자체가 정말 바뀌었을 때만(화면 글 「Untie only when the company itself really changed」)
- 샌드박스 → 운영 전환 순서(2026-10-29 실제로 한 것): Settings 에서 샌드박스 Disconnect → Intuit Production Redirect URI → 운영 키 + `QBO_ENV=production` → Connect

## 8. 화면 — Settings → QuickBooks (asung-ims `settings.html` set v12 `feceed3` · 대화 Claude)

- `?t=qbo` · 상태는 EF status(토큰 없음) — 회사 · env · realm · 누가 · 언제 연결 · 승인 유효 기한(갱신 토큰 만료 날짜) · 마지막 갱신 · 마지막 오류
- needs_reconnect = **빨강**(「Reconnect needed」) · Reconnect 단추
- 단추(admin 만 · `caller_is_admin`): Connect / Reconnect(같은 탭 → Intuit → callback 302) · Check connection(ping · CompanyInfo) · Disconnect · 연결 없을 때 Untie company
- Intuit 에서 돌아오면 `&qbo=connected` | `&qbo=error&why=…` 를 읽어 안내
- Help 줄(872): 「Connection problems? Contact the IMS administrator: caleb@asung.ca」 · Caleb(872 「B」) · 기각 A(화면에 길이 없어 설문 Error Handling 4 가 사실상 No)
- [2026-11-01 · set v13 asung-ims `9e0b079`] **QuickBooks matching**(`?t=qbomatch` · admin 만) — 종류 9 요약 · Refresh list(EF pull 을 끝까지) · Match automatically(`qbo_match_auto` 묶음을 done 까지) · Review(To match · Matched · All · 검색 · 후보 단추 · Find… · Unlink) · 제품 To match 는 **후보 있는 줄만** 보인다 · QBO 에 쓰는 것 없음 — 규칙은 §12
- [2026-11-01 밤 · set v14 asung-ims `67c168f` · 945] QuickBooks matching 문 = **열쇠 QUICKBOOKS**(`caller_qbo` write · read · ~~admin 만~~) · 보기만이면 단추 숨김 · 연결 탭(`?t=qbo`)의 단추는 admin 그대로
- [2026-11-03 · set v17 asung-ims `440abee` · so-module §99-b] **Review 뒤에도 쓰기 단추(Find… · Change… · Unlink)가 보인다** — set v14 ~ v16 은 Review 가 화면 상태 `qm` 을 새로 만들며 `write` 를 빼먹어 모든 목록에서 단추가 사라졌다 · 쓰기 단추 조건 = EF status 의 `caller_qbo === 'write'`(qm.write) · 단추가 안 보이면 ① 열쇠(perms) ② EF status 값 ③ DOM(querySelectorAll) ④ 그 값을 덮는 줄(grep `qm = {`) 순서로
- ⬜ Mail outbox 목록이 kind `qbo_reconnect` 를 글자 그대로 보인다(화면 몫 · deferred 376) · ⬜ 매뉴얼 7 장에 Settings → QuickBooks 절 없음(admin · deferred 378)

## 9. Intuit 앱 — App details · Redirect URI · 설문 · 운영 키

- 약관 · 처리방침(867): `https://ims.asung.ca/terms.html` · `https://ims.asung.ca/privacy.html`(asung-ims legal v1 `c255002` · 로그인 없이 열리는 공개 페이지 · Caleb 「둘다 로그인 없이 잘 열려」) · 기각 B = asung.ca 가게 정책 페이지(가게 손님용 글이라 이 앱을 설명하지 않는다)
  - 처리방침의 약속 둘 = **짓는 조건**: 연결 정보(토큰)는 직원 화면에 안 내려간다 · 관리자가 끊으면 지운다 · 연락처 info@asung.ca · 35 Suntract Road, North York(Caleb 「외부에 놔도 되는 연락처야」)
- Redirect URI(Development · Production 둘 다): `https://fazgmyvzzhqybtvtktyg.supabase.co/functions/v1/qbo/callback` · Production 목록의 OAuth Playground 주소는 지움(Development 쪽은 남음)
- Production App details: EULA · Privacy = 위 두 주소 · Host domain `ims.asung.ca` · Launch · Disconnect · Connect/Reconnect = `https://ims.asung.ca/settings.html?t=qbo`(처음엔 `settings.html` · 바꿈) · Category = Orders & sales · Inventory · (셋째 칸은 Caleb 이 고름 — 못 봤다) · 규제 업종 None · 호스팅 Canada · IP 비움 · 개발자 프로필 주소 = 회사 주소
- ⬜ 앱 로고 — 동의 화면 아이콘이 깨져 보인다(Settings → Basic app info · deferred 372)
- **설문(App assessment) — 868**: 저장만 해 두고 개발 키 + 샌드박스로 **짓고 연결 → 끊기 → 다시 연결을 실제로 해 본 뒤** 사실대로 채워 제출(Caleb 「A로 가자」 · 기각 B = 지을 모양대로 지금 답하고 제출 — 아직 없는 것을 「시험했다」 고 서약하게 된다) · **제출하면 고칠 수 없다**(Intuit 확인 창) · 제출 → 운영 키가 **바로** 풀림(검토 대기 없음 · 2026-10-29 11:3x 쯤)
- 설문 답(제출본 · 2026-10-29):
  - General: 규제 불만 No · 법률 자문 No · 보안 정책 준수 Yes · QBO 관련 앱 Yes · 제재 No · 생성형 AI **No**(⚠️ IMS Claude 커넥터(deferred 360)가 QBO 데이터를 Claude 에 보이게 되면 답이 바뀐다)
  - App Information: 직접 코드 · Web/SaaS · reads + writes(deletes 안 고름) · private · Any admin of the QBO company · 다른 플랫폼 Yes(Shopify · Freightcom · Google Drive · QBO 데이터는 나누지 않음)
  - Authorization: 연결 · 끊기 · 다시 연결 시험 Yes · 갱신 주기 Other(「Before an API call, when the access token is within 5 minutes of expiring; plus one scheduled refresh per day …」) · 실패한 인증 재시도 No · 다시 연결 안내 Yes · discovery Yes · 만료 접근 · 만료 갱신 · invalid_grant · CSRF 모두 Yes · Playground No
  - API Usage: Accounting API · Daily + On-demand
  - Accounting API: 구독 판 **Plus**(Caleb) · 판 바뀜 대처 Yes(모든 판에 있는 기능만 · 거부되면 intuit_tid 와 기록 · 재시도 안 함) · 확인한 기능 None of the above(다중 통화 · 캐나다 세금은 싱크 때 시험 뒤 알림) · webhooks No · CDC No
  - Error Handling: 오류 시험 Yes(근거 = 자동 시험 · **실제 Intuit 오류는 0** — 싱크 때 샌드박스에서) · intuit_tid Yes · 로그 Yes · 앱 안 지원 Yes(Settings → QuickBooks Help 줄 · 끊김 메일)
  - Security: 보안 사고 No · 보안 팀 **No**(처음 Yes 로 골랐다가 사실대로 고침) · 비밀 안전 Yes · MFA **No**(871) · Captcha No · WebSocket Yes(WMS presence 다섯 화면 · QBO 길 아님) · 데이터 남에게 No
  - ⚠️ 다시 알릴 일(deferred 374): 싱크에서 다중 통화 · 캐나다 세금 · 지우기를 쓰게 되면 · 커넥터(360)가 QBO 데이터를 쓰게 되면
  - [2026-11-01 · 판정 933] IMS 읽기 조회로 내려받은 QBO 데이터를 **회사 주인(Caleb)이 Claude 로 분석**하는 것은 「생성형 AI No」 · 「데이터 남에게 No」 와 어긋나지 않는 것으로 본다(IMS 앱은 AI 를 부르지 않는다 · 노출은 줄인다 — 연락처 칸 거부) · [판정 934] `qbo_entity` 거울은 「조회 결과는 표에 저장하지 않는다」 의 예외 · **둘 다 374 재알림 때 적는다** · IMS Claude 커넥터(360)의 도구는 QBO 를 읽지 않는다(2026-11-01)
- **MFA(871)**: IMS 로그인 MFA 는 지금 없다 · 설문 「No」 · 컷오버가 자리 잡은 뒤 따로(deferred 373) · Caleb 「A」 · 기각 B = 컷오버 전 켜기(사흘 전에 23 명의 로그인 방식이 바뀐다)

## 10. 운영 상태 — 실측 (2026-10-29 · 토론토 시각)

```
샌드박스   10:52 연결(Sandbox Company CA 9bca · realm 9341458557490536) · company_name null(→ qbo-1c safeupdate)
           11:04 refresh v2 · 11:05 disconnect(revoked · deleted · vault 2 · state 1) · 11:06 다시 연결 · 회사 이름 바로 · Settings Check connection OK
갱신 토큰   만료 = 연결 시각 + 101 일 · 갱신해도 밀리지 않음(10:52 연결 → 2027-02-07 14:52 UTC · refresh 뒤에도 초까지 같음 · 다시 연결하면 새 101 일)
            → [2026-11-09 정정 · so-module §107-c 2] 갱신 토큰이 바뀌는 갱신 때 + 약 101 일로 밀린다(짐작 · 11-09 실측 2027-02-17 09:10:02Z)
           [2026-10-30] 운영 연결(11:48 EDT)의 만료 = 2027-02-07 15:48 UTC — 10-30 05:10 첫 운영 cron 갱신(ok 200) 뒤에도 그대로 ⇒ 「밀리지 않는다」 확인(deferred 370 닫힘 · Reconnect 할 일 396)
           ~~하루 뒤 바뀌는지는 cron 뒤에 확인 — 「밀리지 않는다」 는 짐작(deferred 370)~~ → 확인됨(위 줄)
접근 토큰   1 시간
call_log   13 줄 — Intuit 호출(companyinfo · token_exchange · refresh · revoke) 9 줄 모두 intuit_tid 있음 · IMS 안 줄(callback · disconnect)은 없음(맞음) · 0.4 ~ 1.2 s
설문       제출(11:3x 쯤) → 운영 키 바로
운영       Settings 에서 샌드박스 Disconnect → Production Redirect URI → 운영 키 + QBO_ENV=production
           → 11:48 실제 Asung Trading Inc. 연결(realm …6496 · Production · 승인 유효 2027-02-07) · 운영 고정 realm 이 이 회사로 섬 · 샌드박스 고정도 따로 남음
QBO 판     Plus(Caleb)
```

- 시험: qbo-1a OK 43(4 회 · `as_role` 로 **실제 authenticated 역할**에서 Vault · 창구 거부 증명) · qbo-1b 시험 OK 20(2 회째 · 시험 결함 B8 · B5 고침) · 확인 OK 20 · deno 11 + mail 17 · qbo-1c 시험 OK 6 · 확인 OK 5 · REST ping · refresh v2 · disconnect · reconnect · qbo-1d deno 12 + mail 17
- ~~⬜ 내일(10-30) 아침 cron 59 첫 운영 refresh 확인 — `select called_at, action, ok, http_status, intuit_tid from qbo_call_log where action = 'refresh' order by called_at desc limit 3;` · 갱신 토큰 만료가 밀렸는지(deferred 370)~~ → ✅ [2026-10-30] 05:10(토론토 · 09:10 UTC) refresh ok 200 · 만료 2027-02-07 15:48 UTC 그대로(deferred 370 닫힘) · ⚠️ cron 59 는 컷오버 1 단계에서 꺼졌다 — reload-procedure P-3 4 에서 다시 켠다

## 11. 싱크로 가는 조건 (deferred 260 · 327 · 341)

- 연결 줄기는 섰다(qbo-1a ~ 1d · 운영 연결 2026-10-29) — 싱크는 열림
- 싱크 차수에서 정할 것:
  - **Cin7 의 QBO 싱크를 끄는 시점**(이중 기록 · deferred 375)
  - 이월 인보이스 · 받아 둔 돈(kind · method opening)은 보내지 않는다 · IMS 에서 이월 인보이스에 붙인 결제 · 크레딧은 QBO 의 기존 인보이스(옛 번호)에 붙인다(341 · 786)
  - ~~짝 칸(손님 · 품목 · `ref_tax_rule.qbo_id` — 지금은 자리만 · so-module §16)~~ → [2026-11-01] 짝은 `qbo_link`(§12 · `ref_tax_rule.qbo_id` 는 쓰지 않는다) · realm 고정이 그 전제(§7)
  - [2026-11-01] 보내기 차수의 판정 거리 — 비활성만 있는 Item 다시 켜기(431) · credit_card 1:3(432) · 북키퍼 넷(433) · 컷 뒤 입금 자리(434) · opening_fix 사건 제외(§13 끝) · 트랜스퍼 분개를 보낼지(433)
  - 다중 통화 · 캐나다 세금 · 지우기 → 샌드박스 시험 뒤 Intuit 에 설문 다시 알림(374) → [2026-11-09 · §15-l] 공급처 쪽 거리 더함(매입 세금 코드 · Bill 환율 1118 · Vendor 만들기 1128 · Bill delete 는 쓰지 않음 1126)
  - 오류 시험을 실제 Intuit 거부로(설문 Error Handling 1 의 근거는 지금 자동 시험뿐)
- 승인 유효 기한(약 101 일 · → [2026-11-09] 갱신으로 밀린다 · 「갱신이 멈췄을 때」) 전 미리 알림(371) · MFA(373)
- 진행(2026-11-01): 연결 ✅ · 읽기 ✅ · 짝 · 거울 · 받기 ✅ · **보내기 ⬜**(deferred 260 · 327) → [2026-11-01 밤] 쓰기 길 · 손님 · Item 만들기 ✅(2a · 2a′ · §14) · 인보이스 · 크레딧 ⬜(2b) · 결제 · void ⬜
- [2026-11-01 밤] 판정 거리 정리: 431 닫힘(941 — 비활성 Item 은 켜지 않는다) · 433 닫힘(북키퍼 답 · so §96-c 7) · ⚠️ **트랜스퍼 분개를 장부에 보낼지는 여전히 판정 거리**(북키퍼: In Transit 은 Inventory Asset 하위 · 재무제표 영향 없음 · TR-06396 ~ 99 분개 0) · 컷 뒤 입금 = IMS 에(434) · 카드 수수료 세금 = 회계사 확인(443)

## 12. 짝 · 받기 — `qbo_link` · `qbo_entity` (2026-11-01 · qbo-sync-1a ~ 1c · set v13 · 판정 934 · so-module §95)

- **짝은 한 번 정하면 QBO Id 로 붙든다** — IMS 이름 · QBO 이름이 바뀌어도 그 Id(`qbo_name_at_match` 는 그때 이름 기록만) · ⚠️ 까닭 실물: Cin7 은 Item 을 **이름으로** 찾아, 제품 이름이 바뀌면 같은 Sku 로 새 Item 을 만들었다(짐작 · 패턴 근거) → 같은 Sku 의 Item 둘 = 33 SKU · 66 Item(§13)
- **`ref_tax_rule.qbo_id` 는 쓰지 않는다** — 그 칸의 UNIQUE 가 Sale · Purchase 두 세금 규칙이 한 TaxCode 를 가리키는 것을 막는다(주석만 · 칸은 그대로) · 세금 짝도 `qbo_link`(tax_rule 만 N:1)
- **받기(pull)** = 종류마다 begin → 쪽마다 entity_upsert(1,000) → finish(완주 때 안 온 행에 gone_at) · `qbo_pull_state` 가 진행 · 화면 Refresh list 가 끝까지 · 자동 짝은 **그 종류 pull 완주가 전제**
- **자동 짝(`qbo_match_auto`)** — **활성 IMS 행만 · 짝 없는 것만** · 결과 linked · absent(QBO 에 없음) · ambiguous(후보 둘 이상 · 짓지 않음)
  - account: IMS code `_N_` 의 **N = QBO Account.Id**(auto_code · 12 개 눈 확인 · 220/220 이 이 규칙으로 섰다)
  - tax_rule: 「 (Sale)」 「 (Purchase)」 꼬리 뗀 이름 = TaxCode 이름(auto_name)
  - payment_term · customer · supplier: `lower(btrim(name))`(auto_name) — **속 빈칸은 접지 않는다**(「Christina  Spataro」 ≠ 「Christina Spataro」 · 실제 두 손님)
  - product: `lower(btrim(sku))`(auto_sku) → 활성 Item 둘 이상이면 `lower(btrim(left(name,100)))` 같은 쪽(auto_sku_name) — 「최근 것」 규칙은 틀린다(SKU 중복 22 중 5 는 옛 Item 쪽이 IMS 이름과 같다 · §13)
  - payment_method: 고정 표(auto_map) — cheque 2 · debit_card 4 · e_transfer 5 · wire 11 · cash 1 · shopify 8 · direct_deposit 12 · **credit_card · opening 은 짝 없음**(credit_card 는 QBO 셋 — deferred 432)
  - charge · service: 자동 없음 · 사람 짝(manual)
- **묶음 계약(qbo-sync-1c)** — `qbo_match_auto(p_kind, p_after, p_limit 5000 · 최대 20000)` → next_after · remaining · done · 부르는 쪽이 done 까지 돈다 · 까닭 = 첫 `qbo_match_auto('customer')` 가 REST 8 초 statement timeout(57014 · 다시 재면 ≈ 1 초 · 재현 안 됨 · 같은 시각 autovacuum 짐작) ⇒ 상한을 「더 빠르게」 가 아니라 묶음 크기로
- 실호출(11-01 운영 · `qbo_link` 재셈): account 220 · tax_rule 24 · payment_term 17 · payment_method 7(+ skipped 1 credit_card) · supplier 195(absent 33) · customer 9,764(absent 27) · product 11,775(auto_sku 11,755 + auto_sku_name 20 · absent 2,941 · ambiguous 1 = LGL99950SIL — QBO Item #4153 지워짐 · 짝 짓지 않음) · charge 손 짝 2(freight → Item 4 · discount → Item 2170 · surcharge · freight_discount 남음) · service 11 남음
  - product absent 2,941 = Cin7 은 **처음 팔 때만** Item 을 만든다(안 팔린 제품은 QBO 에 없다) — 「제품 짝 1 만 4 천」 짐작이 깨진 자리(so §95-e 41)
- 화면 = Settings → QuickBooks matching(§8) · 문 = ~~admin~~ → [11-01 밤] 열쇠 QUICKBOOKS(창구 안 `qbo_sync_gate` → `qbo_key_gate` · §4)

## 13. QBO 실물 — 보내기를 지을 때의 바탕 (2026-11-01 · Settings 콘솔 조회 · 판정 933 범위 · Caleb 캡처 — 「11-01 실측(대화)」 · 재셈한 것은 표시)

- **회사 설정**: MultiCurrency true · Home CAD · Location 추적 켜짐(인보이스엔 비어 있음) · Class 줄 단위 켜짐(안 씀) · **QuantityOnHand false**(재고 추적 꺼짐 — 원가는 분개로만) · CustomTxnNumbers true
- **목록**(거울 재셈 11-01): Account 238(활성 220) · PaymentMethod 14 · TaxCode 16(「GST」 둘 — 7 비활성 · 8 활성) · Term 18(DueDays 만 · 할인 칸 없음) · Customer 10,032(하위 손님 18 — 모두 BillWithParent · Clore Inc. 13 · Lowe Opco 1 … · DisplayName 중복 0) · Vendor 642(USD 211 · KRW 1) · Item 14,743(활성 13,654 · Service 14,702 · NonInventory 41 · 수입 #98 · 비용 **#58 Cost of Goods Sold** · Item 4 Freight(수입 #99) · Item 2170 Discount)
- **Cin7 → QBO 가 하던 것(Caleb 캡처)**: Authorized · **Auto sync 꺼짐**(Sync now 를 눌러야 보냄 · 마지막 10-30 17:31) · Invoice · COGS sync type Individual
  - 보냄 = 판매 인보이스 · Credit memo · 결제 · 환불 · **SO 마다 COGS JournalEntry(차 #58 / 대 #59 · DocNumber = SO 번호 · 줄 설명 = 손님 이름)** · Bill(상품 → **GINR #1150040012** · USD 는 A/P USD #109 + 환율) · Vendor credit · 입고 분개(차 Inventory / 대 GINR) · 운임 · 관세 · 통관은 COS 계정 → 분개로 재고에 얹음 · 트랜스퍼 분개(Inventory ↔ In Transit · 10 월 93) [2026-11-08 · 원장 실측: 창고 간 19 · 빈 이동 919 · QBO 10-15 TR 꼴 둘(M8) · 93 의 뜻은 deferred 506]
  - 받음 = 계정과목 · 세금 · 결제조건 · Bill payment(공급처 결제는 QBO 에서 넣는다) → [2026-11-08 · 1081] 컷 전 Bill 에만 · IMS Bill 의 결제는 IMS 가 보낸다(§15)
  - 인보이스 꼴: DocNumber = IMS 인보이스 번호 · 손님 이름 · 줄 Product/Service = 제품 이름 + SKU 칸 · 줄마다 「HST ON」 · 운임 = Item 「Freight」 한 줄 · 「Customer Reference: AS-…」 가 인보이스 메모 · 명세서 메모 두 곳 · 결제 = 별도 Payment(예: method Cheque · Ref 「CHQ #1607」 · Deposit To BMO CAD CHEQUING #105)
- **결제 입금 계좌**(Payment 08-01 ~ · 3,505 건): 카드 → Clearing - TD Merchant TOR #1150040027 · EDM #1150040030 · 이트랜스퍼 → Clearing - E-Transfer #1150040028 · 수표 · EFT · Wire → BMO CAD CHEQUING #105 · 현금 → Cash on hand TOR #137 · EDM #1150040031 · ⚠️ 이상한 갈래 둘(현금 → TD Merchant TOR 514 건 174,154.20 · 현금 → Clearing - Shopify 852 건 38,217.70) = 북키퍼에게 묻는 중(deferred 433) · Undeposited Funds 는 거의 안 씀 · Deposit 은 현금 → 은행 묶음 정도
- ⚠️ [2026-11-02 밤 · so §98-c 1] **Cin7 이 보낸 결제 수단 — 정정**: 「Cin7 은 결제 수단 전부 Cash」(북키퍼 11-01 · so §96-c 7 ①)는 틀렸다 → 실물: 카드 Visa 3 · MC 6 · Amex 9 · Debit 4 · E-Transfer 5 · EFT 12 · Cheque 2 로 갈라 보냈다 · Cash 로 간 것은 Shopify · PayPal · 현금뿐 ⇒ IMS 는 카드 하나(983) · 입금 계좌는 Cin7 꼴(수표 #105 984 · PayPal #124 986 · Shopify Clearing - Shopify #1150040029 993 · §14-f)
- **결제 실무(Caleb)**: 계산대 손님은 현금 · 데빗 · 크레딧 · 이트랜스퍼 · 캐시어가 기록 · 카드는 IMS 와 무관한 **TD Merchant 단말기** · TD 가 **다음 날 하루치를 묶어** TD 체킹에 넣음 · **수수료는 떼지 않고 나중에 한꺼번에 뺌** · 북키퍼는 스테이트먼트로 대조 · 손님 결제는 기본 IMS · 부득이하게 QBO 에서 넣는 경우가 있다(deferred 434)
- **컷 경계(Caleb)**: 10 월까지(컷 전) 거래는 실무자가 Cin7 → QBO 로 올린다(11-02 중) · 컷 뒤는 IMS 가 보낸다 · Cin7 ↔ QBO 연결은 아직 살아 있다 · 끊는 시점 = 실무자 작업 확인 뒤(deferred 375) · 인보이스 50754 · 50780 은 QBO 에 있음(확인)
- **살린 트럭 TR-06396 ~ 06399**(판정 896): QBO 에 그 DocNumber 의 JournalEntry 가 **하나도 없다**(날짜 조건 없이 · 11-01) ⇒ 받을 때 보낼 분개 없음 · 트랜스퍼를 장부에 보낼지는 보내기 차수의 판정 거리
- **opening_fix 사건은 보내지 않는다**(판정 932 · ledger-design 「기초 이전 원가 바로잡기」) — 그 판매의 COGS 는 Cin7 이 이미 QBO 로 보냈다 · 가르는 열쇠 = `inv_layer_consume.line_ref like 'adj:%'` → `inv_cost_adjust.id` → kind `opening_fix` → [2026-11-08 · 3-0 이견 4] 보낼 원가의 경계는 「원가 사건이 컷 뒤 IMS 에서 생겼나」 · opening_fix 는 그 예외 하나 · 10-30 Cin7 몫은 이미 QBO 에(17:33 · M6) · cost-fix-1 의 carried 도 보내지 않는다(1090)
- **QBO 재고 잔액(2026-11-08 · M7)** — Account CurrentBalance(부호 = 차변 + / 대변 −): #62 A/P −35,954.56 · #109 A/P USD −62,398.26 · #58 0(⚠️ API 는 손익 계정 잔액을 0 으로 준다 — 원가 검산은 기간 보고서로) · **#59 1,464,935.89**(하위 포함 1,422,924.05) · #1150040007 In Transit −412.06 · #1150040011 GRNI −42,062.28(→ [2026-11-08 밤 · 1096] IMS 는 GRNI 를 쓰지 않는다 — Cin7 시절 찌꺼기 · 입고 짝은 GINR 하나 · §15-h) · #1150040012 GINR 462.50 — 셋은 #59 의 **하위 계정**(1,464,935.89 − 42,011.84 = 1,422,924.05) · IMS 재고 금액과 약 150 만 차이 = 알려진 차이(1086 · deferred 503)

## 14. 보내기 줄 · 쓰기 길 — `qbo_job` · `apiWrite` · send (→ [2026-11-03] 결제 §14-f · [2026-11-07] 이월 받아 둔 돈 붙임 §14-j · [2026-11-08] 환불 §14-k · [2026-11-09] 하루 원가 장 cost_day §15-j · §15-k · 2026-11-01 밤 · qbo-sync-2-0 · 2a `20261102003000` · 2a′ `20261102030000` · 판정 935 ~ 946 · 951 · so-module §96)

- **조사(qbo-sync-2-0)**: 보내기 줄 = `drive_job` 꼴 + 메일의 unknown 갈래 · ⚠️ 읽기 길 `intuitCall` 은 네트워크 · 5xx 에서 **자동 재시도** → 쓰기에 쓰면 중복 ⇒ 쓰기는 재시도 끔 + 결과를 모르면 DocNumber · 이름으로 조회
- **문** = 열쇠 QUICKBOOKS(§4 · 945) — 일감 창구 · EF send 는 `qbo_key_gate(true)` · 몸 · claim · done 은 service_role
- **표**(RLS · 창구로만 · ims_id text 다형 · FK 는 ims_staff · 자기 참조 blocked_by 뿐 · 거래 표 FK 0 → 컷오버 지우는 순서 영향 없음)
  - `qbo_job` — 일감 하나 · kind(customer · item · invoice · credit · invoice_void · credit_void · → [2e-1b] payment · payment_void §14-f) · ims_kind(customer · product · charge · invoice · credit) · state(queued · blocked · sending · sent · failed · unknown · skipped) · attempts · request_id(uuid) · blocked_by · qbo_id · **qbo_name(그때 실제로 보낸 이름 · 2a′)** · sync_token · last_error · last_intuit_tid · warning · note · **열린 일감은 (realm, kind, ims_kind, ims_id) 하나**(부분 유일)
  - `qbo_txn` — 거래 짝(invoice · credit ↔ QBO · doc_number · total_amt · total_tax · voided_at) · 표만 · 2b 가 채운다(11-02 재셈 0 행)
  - `qbo_link.matched_by` 에 `created`(IMS 가 만든 QBO 행 · 일감 done 이 넣는다)
  - inv_config 4 키: `qbo_send_enabled` off(⚠️ **cron 길 스위치일 뿐 — 손 send 는 이 값과 무관** · 2a 이견 16 · cron 등록은 2b) · `qbo_send_since` ''(이 날 이후 발행분만 일감 · 비면 안 쌓음 · 2b 트리거) · `qbo_send_batch` 15(1 ~ 50) · `qbo_cogs_account_code` `_58_`
- **몸 함수**(grant 0 · claim · add 가 부른다 · 규칙이 SQL 로 시험된다)
  - 손님 `qbo_customer_body`(936 · 946): DisplayName = `left(btrim(name),100)` · Customer · Vendor 거울과 이름 충돌이면 **실패**(자동으로 바꾸지 않는다 · Employee 는 거울에 없어 실제 쓰기의 6240 이 남는다) · CompanyName · BillAddr(기본 Billing 주소 · Country = 나라 이름 CA → Canada · US → USA · 그 밖은 그대로 + 경고) · PrimaryEmailAddr(`doc_mail_recipient` 와 같은 선) · CurrencyRef · SalesTermRef(qbo_link payment_term) · DefaultTaxCodeRef(customer.tax_rule → ref_tax_rule → qbo_link · 없으면 비움) · Taxable true · 전화 · 배송 주소 없음 · parent_id 있으면 ParentRef · Job · BillWithParent — 부모 짝이 없으면 부모 일감 먼저 + blocked
  - Item `qbo_item_body`(937 · 941 · 943 · 944): Name = `left(btrim(name),100)` · 콜론 → '-' · gone 아닌 QBO Item 과 `lower(btrim)` 정확 비교로 같으면 끝에 ` [SKU]`(「(deleted)」 꼬리 떼지 않음 · EF 가 6240 에 한 번 더) · **같은 Sku 가 비활성뿐이면 실패 「QuickBooks item is inactive」(941 · 사람이 QBO 에서 켠 뒤 retry)** · 활성이 있으면 실패(사람 짝) · Type Service · Taxable true · IncomeAccountRef = `coalesce(product.revenue_account_code, customer_default_sale_account_code)` 의 짝 · ExpenseAccountRef = `qbo_cogs_account_code` 의 짝 · surcharge → 「Tariff Surcharge」 · `so_surcharge_account_code`(`_94_`) · **freight · discount · freight_discount 는 거부**(943 — 운임은 Item 4 Freight · 할인은 운임 줄에서 뺀다)
- **일감 창구 8**: 열쇠 = `qbo_job_add`(customer | item · 미리 보기 · 열린 일감이 있으면 그것 · 부모 먼저 + blocked) · `qbo_job_list` · `qbo_job_retry`(failed · unknown → queued · **request_id 새로** · unknown 은 note 필수 — 「QuickBooks 에서 무엇을 봤나」) · `qbo_job_skip`(note 필수) / service_role = `qbo_job_claim`(stale sending 10 분 → unknown 먼저 · blocked → queued(부모 sent) · queued → sending · `for update skip locked` · 몸 실패는 그 일감만 failed) · `qbo_job_done`(sent + qbo_link created + qbo_entity upsert + 자식 풀기) · `qbo_job_fail` · `qbo_job_unknown(p_job, p_error, p_intuit_tid, p_name)`(2a′ · 4 인자 · 옛 서명 없음) · + `qbo_job_unknown_list()`(2a′)
- **쓰기 길 `apiWrite`(2a′)** — API 호스트로 나가는 모든 쓰기가 여기를 지난다 · **POST 만** · `assertWriteAllowed` 허용 목록 = 만들기 customer · item · invoice · creditmemo(2b) · `operation=void` 는 invoice · creditmemo 만(2b · 2c) · → [2026-11-03 · 2e-1c] 만들기 + payment · payment 의 void 는 `operation=update&include=void` 만(§14-f) · **delete 없음** · `requestid` 필수(1 ~ 50 자 = `qbo_job.request_id` — Intuit 은 같은 id 면 처음 응답(실패 포함)을 되돌려 주므로 retry 마다 새로) · **자동 재시도 없음** · 몸은 기록하지 않는다(detail 은 job id 만) · 읽기 길(`apiCall` · `assertReadOnlyRequest`)은 그대로
- **send `{limit?}`**(열쇠 · 손으로 · 기본 15 · 최대 50 · ~~cron 없음~~ → [11-01 밤 · 2b2] cron 61 이 이 길로 부른다 · 스위치 off 면 호출 0 · §14-b · [11-02 · 2d1] `{job_ids}` 도 §14-d · [11-03 · 2e-1c] `{kinds}` · 결제 kind 둘 · Payment void = `operation=update&include=void` 는 §14-f) — ① `qbo_job_unknown_list` → 보낸 이름(DisplayName · Name)으로 **GET 조회** → 하나면 `qbo_job_done` · 0 · 둘 이상은 그대로(사람이 retry · skip) ② `qbo_job_claim` → 일감마다 `apiWrite` POST 한 번 → done | fail | unknown · 응답 = resolved · recovered_unknown · unblocked · body_failed · claimed · sent · failed · unknown · jobs
- **첫 운영 쓰기(11-01 밤)**: `qbo_job_add` 미리 보기 → send limit 1 → QBO 화면 확인 · 손님 1 명 → **Customer 10740**(이름 · 주소 · 이메일 · 결제조건 C.B.S 맞음 · 배송 주소는 QBO 가 「청구와 같음」 으로 채움) · 재셈(11-02 00:59 UTC): qbo_job 1(sent) · qbo_link created 1 · qbo_txn 0
- **인보이스 · 크레딧의 꼴(2b 가 짓는다 · 판정)**:
  - CustomerRef = **매장**(`so_invoice_order.customer_id` · 크레딧 `store_customer_id` · 935) · 청구 · 배송 주소 · 손님 이메일을 싣는다(IMS 문서 값 · 발행 때 · 936)
  - 없는 제품은 처음 팔 때 Item 을 만들고 이어서 인보이스(937) · 0 원 운임 줄도 싣는다(938) · 운임 할인은 운임 줄에서 뺀다(Item 4 · #99 음수 줄 · 943) · Surcharge = 「Tariff Surcharge」(#94 · 944)
  - IMS 직원 메모는 보내지 않는다 · PrivateNote = `Customer Reference: <so.ref>` · CustomerMemo = `Customer Reference: <so.ref>, <매장 이름>`(939)
  - USD 는 QBO 기본 환율(940) · 세금 = IMS 문서 값 그대로 · **QBO 가 돌려준 합계가 1 센트라도 다르면 실패**(942 · 실물 48160 — IMS 는 줄마다 반올림 10.74 · 합 한 번 셈 10.73)
  - 그 밖 계정 charge 줄(카드 수수료 등)은 **사람 짝**(`qbo_link` charge · ims_id `'acct:_20_'` 꼴 · QBO 14735 「Credit Card Processing Fee (3%)」) · 자동 Item 없음 · 세금은 IMS 값 그대로(951 · 회계사 확인 deferred 443)
  - ⚠️ 북키퍼에게 전한 것(Caleb 11-02): IMS 가 보낸 인보이스는 QBO 에서 고치지 않는다 · 카드 수수료도 IMS 에서 · 컷 뒤 입금은 IMS 에(434)
- 시험: 2a 검증 48 · deno 16 · 2a′ 검증 7 · 2a 확인 47 · deno 18 · `supabase/tests/qbo_sync_2a_check.sql` · `qbo_sync_2a2_check.sql`(L2 「적용 앞 지문」 은 시험 갈래만 — 확인 갈래는 begin 앞 지문이 없어 null · so §96-e 52)

### 14-a′ 바로잡기 — 942 의 「실패」(2b1 에서 바뀜)

- 위 「인보이스 · 크레딧의 꼴」 의 942 「1 센트라도 다르면 **실패**」 → 2b1 부터 **sent + `qbo_txn.mismatch` 글 + 일감 warning**(이미 QBO 에 섰으므로 · **자동 void 없음** · 사람이 본다) · 첫 실물 60000 은 mismatch 0

### 14-b 인보이스 — qbo-sync-2b1 · 2b2 (2026-11-01 밤 · `8f1698a` · `20261102040000` · EF `b9f5c19` · 판정 935 ~ 946 · 951 · 원천 = 마이그레이션 머리 주석 · 커밋 글)

- **경계**: 2b1 = DB 가 몸 · 상태 · 거래 짝을 다 만든다 / 2b2 = EF 가 나른다(invoice POST · DocNumber 멱등 · 응답 합계 · void · cron send)
- **표 · 칸**: `qbo_entity.detail` jsonb(TaxCode 의 SalesTaxRateList — TxnTaxDetail 의 TaxRateRef 를 DB 가 안다 · EF pull 이 TaxCode 에 SalesTaxRateList 를 더함 · 11-01 밤 pull 로 세율 13) · `qbo_txn.mismatch` text(942)
- **몸 `qbo_invoice_body`**: CustomerRef = 매장(오더 매장이 둘 이상이면 실패 「cancel and reissue per store」) · SalesTermRef(qbo_link payment_term · 짝 없으면 실패 · 결제조건 없으면 생략 + 경고) · CurrencyRef · BillAddr(so_invoice.bill_to_* · Line1 = 이름) · ShipAddr(첫 오더 · 다르면 경고) · BillEmail(`doc_mail_recipient`(청구처) · 없으면 생략 + 경고) · PrivateNote · CustomerMemo(939 · ref 없는 오더는 so_number) · ShipDate · TrackingNum(첫 오더) · GlobalTaxCalculation TaxExcluded
  - 줄 = so_invoice_line 순서: product → Item 짝(없으면 needs item) · Description = 이름 + 「 (list x, y% off)」 / surcharge → 「Tariff Surcharge」(needs · 944) / order_discount → charge discount(음수 · 짝 없으면 실패) / charge → service 짝 · `_99_` 는 freight · 그 밖 계정 `acct:<code>`(951) / charge_discount → 그 운임 줄 Item 음수(943) · 0 원 줄 그대로(938) · TaxCodeRef = 그 오더 세금 규칙 짝
  - TxnTaxDetail = TotalTax(so_invoice.tax_amount) + 규칙마다 TaxLine(TaxRateRef = qbo_entity.detail · NetAmountTaxable · Amount) · detail 없으면 실패 「Refresh list」
  - ✅ **짐작 풀림(11-02 첫 실물)**: 「QBO 캐나다판이 보낸 TaxLine(TxnTaxDetail)을 존중하나」 = **존중한다**(60000 → 172335 세금 · 합계 그대로 · mismatch 0)
- **트리거 둘**: `so_invoice_qbo_job`(AFTER INSERT DEFERRABLE INITIALLY DEFERRED · 같은 트랜잭션 취소 · since 전 · 이월(opening) · 연결 없음은 조용히 · 오류는 삼켜 발행을 막지 않는다 → invoice 일감 queued · by_staff = issued_by) · `so_invoice_qbo_cancel`(취소 → 안 나간 일감은 skipped · sending · unknown 이면 invoice_void 를 그 일감에 blocked · 보냈으면 invoice_void queued · since 전 · 이월은 아무것도)
- **claim(p_limit, p_kinds)**: needs 일감(손님 · 부모 손님 · Item)을 전부 쌓고 인보이스 일감은 blocked(마지막 need) · 다음 바퀴에 몸을 다시 만든다 · need 가 거부되면(941 비활성 Item · 활성 Sku 사람 짝) 인보이스 일감 failed + 까닭 · ⚠️ p_kinds 기본 {customer, item} — 2b2 EF 가 invoice · invoice_void 를 명시
- **done(+ total_amt · total_tax)** → `qbo_txn` 넣기(unknown 을 조회로 푼 뒤에도) · 942 대조 · QBO Id 가 다른 IMS 인보이스의 짝이면 failed · void → voided_at · 읽기 창구 `qbo_txn_of(kind, ims_id)`(활성 직원 누구나 · 화면 꼬리표)
- **EF(2b2)**: invoice = **DocNumber 조회로 멱등**(이미 있으면 그것과 짝) → POST → 942 합계 대조 · 6140 / 6210(중복 번호) → 다시 찾아 짝 · invoice_void = POST `operation=void`(SyncToken 없으면 읽기 · 5010 → 다시 읽어 한 번) · unknown 풀기에 invoice · void 갈래 · CRON_ACTIONS refresh · send · deno 20
- **cron 61 `ims-qbo-send`** `*/5 * * * *` — `qbo_send_enabled` on · 연결 connected · 할 일이 있을 때만 EF send 를 부른다 · **11-02 실측(Caleb psql): active · 스위치 off → 호출 0** · `qbo_send_since` = **2026-11-02**(이 날 이후 발행분만 일감) · 기록 `supabase/ops/cron.sql`

### 14-c 크레딧 노트 — qbo-sync-2c1 (2026-11-02 · `671dcad` · `20261102130000` · 판정 959 ~ 966 · 968 · 969)

- **IMS 문 셋(보내기 전에)** — `so_invoice_cancel`: **손으로 넣은 결제(manual)** 충당이 살아 있으면 거부(968 · 969 — auto_deposit · auto_balance 는 옛 동작 그대로 취소와 함께 void → 손님 계정으로) · **issued 크레딧이 가리키는 인보이스**는 거부(959 · 번호 나열) / `so_credit_issue`: **kind tax 줄 거부**(966 · 글 「A tax-only credit note is not allowed — credit the invoice in full and issue a corrected invoice instead」 · 옛 행 그대로)
- **몸 `qbo_credit_body`**: CustomerRef = coalesce(store_customer_id, customer_id) · 주소 = **크레딧 노트 PDF 와 같은 규칙**(인보이스 크레딧 = 그 인보이스 bill_to + 첫 오더 ship_to · 참조 크레딧 = 청구처 기본 Billing + 매장 기본 Shipping · 962) · BillEmail = `doc_mail_recipient(customer_id)` · PrivateNote = 「Credit for invoice <번호> · Customer Reference: <refs>」 · CustomerMemo = 같은 글 + 「, <매장>」
  - 줄 = so_credit_line 순(**콤보 구성품 줄 0 원은 보내지 않는다**) · product · price_adjustment → Item 짝 · surcharge · order_discount · freight · freight_discount → 그 인보이스 줄의 charge 짝 · **other · restocking_fee → `acct:<account_code>` 사람 짝**(961 · 951 꼴 · 없으면 failed 「link account item …」 · Settings → QuickBooks matching 의 「Freight, discount & account lines」 — set v15) · tax 줄(옛 행) → 예외 · TaxLine 은 인보이스 꼴
  - **960** — 크레딧은 자기 IMS 인보이스가 QBO 에 간 뒤에: 인보이스 일감 없음 → failed 「Invoice N has no QuickBooks job — send the invoice first」 · skipped → failed 「… was skipped — skip this credit note too, or retry the invoice first」 · 열린 일감 → 그 일감에 blocked · sent → 간다 · **since 전 · 이월 인보이스(Cin7 시절) · 인보이스 없는 크레딧은 기다리지 않는다**
  - `qbo_credit_void_body` — 보낸 적 없음 · 이미 void 면 예외 · **963 CreditMemo void 가 QBO 에서 거부되면 failed — 사람이 QBO 에서**
- **트리거 둘** `so_credit_qbo_job` · `so_credit_qbo_cancel`(인보이스 꼴) · **채우기 `qbo_credit_backfill()`**(965 · since 2026-11-02 이후 발행 · 일감 없는 크레딧 · 적용 때 한 번 · 11-02 채운 수 0)
- **964** — 2c 는 CreditMemo 만 · 인보이스에 붙이기(apply) · 환불은 결제 차수
- 짝 열쇠 961 = `qbo_ims_rows('charge')` 의 acct: 행에 크레딧 줄 계정을 더함 · done(credit → qbo_txn CreditMemo + 942 대조) · EF SEND_KINDS 6 · creditmemo POST · void · DocNumber 멱등 · 검증 22 · deno 21
- ⚠️ 적용 순서 한 덩이: 마이그레이션 → repair → EF 배포(트리거가 먼저 서고 EF 가 옛 SEND_KINDS 면 빈 claim)
- **리스탁킹 피**(cr-ref-fee-1 · 11-02): 서버는 참조 크레딧의 restocking_fee 를 이미 받는다(수리 없음 · 실측) · 화면 cr v7(asung-ims `0c2a6c0` · 이력(참조) 크레딧 창 Charge a fee · % · Fee account(REVENUE 만)) · **계정은 북키퍼가 새로 정한다** → QBO 계정 + Item → pull → Id → `supabase/ops/restock-fee-account.sql`(ref_account `_<QBO Id>_` · 설정 키 · qbo_link auto_code · 검산 4 · dry-run 기본 · `859d72b`)

### 14-d 북키퍼가 골라 보낸다 — qbo-sync-2d1 · qs v1 (2026-11-02 · `c0cf4c0` · `20261102150000` · asung-ims `3659dbd` · 판정 971)

- **971 (나)** — 처음에는 **북키퍼가 문서마다 확인하고 보낸다**(한 장씩 Preview → Send · Send selected) · `qbo_send_enabled` off 그대로 · 켜는 시점은 나중에 Caleb
- **claim(p_limit, p_kinds, p_job_ids uuid[] default null)** — 고른 id 만(≤ 200) · 만든 need 일감을 `need_jobs` 로(손님 need 우선) · `requested[]` = id 마다 결과(not_found · not_queued · wrong_kind · not_due · locked · claimed · blocked · failed) · 옛 EF 두 인자 호출 그대로 돈다
- **`qbo_job_preview(p_job)`**(열쇠 qbo 또는 qbo:read) — 몸 함수 여섯을 kind 로 부르고 예외를 잡는다 · **need 일감을 만들지 않는다** · needs · wait(960) · blocked_by · error · sendable · QBO 호출 0
- **`qbo_job_list(p_state, p_kinds, p_from, p_to, p_q, p_limit, p_offset)`** — 날짜 = 일감 created_at 의 토론토 날짜 · 문서 번호 · 이름 · 통화 · 총액 · 문서 날짜 · 상태 · 막은 부모 · 정렬 unknown → failed → sending → queued(오래된 것 먼저) → blocked → 그 밖(최신) · ≤ 200 · 속 함수 `qbo_job_doc`
- **`qbo_job_retry`** — **skipped 도** 받는다(note 필수 · 문서가 issued(void 는 cancelled)일 때만 · 같은 열쇠 열린 일감 있으면 거부)
- **EF send `{job_ids}`** — 한도 10 · 바퀴 최대 5 · 동시 5 · 30 s · 옛 `{limit}` 그대로 · 검증 18 · deno 22 · EF 50 kB
- **화면** Sales → **QuickBooks**(`qbo-send.html` · nav v14 · 열쇠 qbo · 보기 qbo:read) — 목록(상태 · 종류 · 날짜 · 찾기 · 쪽) · Preview(QBO 에 갈 몸 · 먼저 만들 손님 · Item · 막힌 이유) · Send · Send selected(10 장씩) · Retry · Skip(메모 필수)

### 14-e 첫 실물 · 운영 (2026-11-02 · 「11-02 실측(대화)」)

- **첫 인보이스 60000 → QBO 172335** — sent · mismatch 0 · 손님 · 줄 · 세금 · 주소 · 메모를 Caleb 이 QBO 화면에서 확인 ⇒ 14-b 의 짐작(TxnTaxDetail) 풀림
- **60001 미리 보기**: Item CB-CVT18157 짝 없음 → 보낼 때 먼저 만든다(937 · need 일감)
- 실측 1 장 = Intuit 호출 2 번 · 3.52 s
- **Cin7 ↔ QBO 연결을 Caleb 이 끔**(deferred 375 닫힘) · 북키퍼에게 알림
- Intuit 알림 문구(⑤ · 크레딧 · 북키퍼 확인 · CreditMemo void 포함)는 대화 Claude 가 고침 — **보냈는지는 Caleb 확인**(deferred 374 열림)

### 14-f 결제 — qbo-sync-2e-1a · 1a2 · 1b · 1c (2026-11-02 밤 ~ 11-03 새벽 · `f7ca811` · `da6606b` · `6d37cea` · `7047a80` · `20261103020000` · `040000` · `050000` · EF qbo · 판정 978 ~ 993 · so-module §98)

- **판정**: **978 (다)** 결제 하나(so_payment 한 줄) = QBO Payment 한 장 · 보낸 뒤 붙임이 바뀌면 옛 Payment void + 통째로 다시 · update 길 없음 · **980 (나)** 본사가 매장 인보이스 여럿을 수표 하나로 → 본사(청구처) 이름 Payment 한 장 · Line = 매장 인보이스(sandbox B-4: Payment 183 → Invoice 182 Balance 0) · **981 (가)** IMS 에 적힌 결제는 날짜와 상관없이 모두 IMS 가 보낸다 · 북키퍼는 QBO 에서 Payment 를 만들지 않는다 · **982** 이월 인보이스는 다시 보내지 않고 이월에 붙은 IMS 결제는 보낸다(짝 = DocNumber + 매장 손님 + 금액 · 1d) · **983** 카드는 QBO 수단 하나 · **985** QBO 「Automatically apply credits」 off 그대로 · **988 · 989** 결제(· 크레딧 붙임 · 환불)는 붙은 인보이스가 모두 QBO 에 간 순간 자동 · 인보이스 · 크레딧 노트는 971 그대로 북키퍼가 고른다 · **991 (가)** 미래 TxnDate 그대로(QBO 는 받는다 · Cin7 실물 24 장)
- **입금 계좌(so_payment_account_default · Cin7 꼴)**: cheque CAD TOR · EDM `_5_` → **`_105_` BMO CAD CHEQUING**(984 · 2e-1a) · **paypal** 신설 CAD TOR · EDM → **`_124_` PayPal**(986 · QBO 수단 7 · `qbo_ims_rows` + paypal · 받기만 — Shopify 게이트웨이 paypal) · shopify CAD `_104_` → **`_1150040029_` Clearing - Shopify**(993 · 2e-1a2) · ops 실물 고침 `shopify-paypal-fix.sql`(3 건) · `shopify-clearing-fix.sql`(34 건 1,569.49) apply 끝
- **표 · 일감(2e-1b)**: qbo_job kind + `payment` · `payment_void` · ims_kind + payment · 칸 `fingerprint` / qbo_txn kind + payment · type + Payment · 칸 fingerprint · `source`(sent | matched — matched 는 1d) · 스위치 **`qbo_send_payments_enabled` off**(결제만 · `qbo_send_enabled`(971)와 별개)
- **지문 `qbo_payment_fingerprint`** = md5(amount · paid_on · method · account_code · currency · 정렬한 (invoice_id, amount)) · 활성 · kind payment · opening 아님 · 붙임 ≥ 1 이 아니면 null(= QBO 에 없어야 한다)
- **몸 `qbo_payment_body`**: CustomerRef = 청구처(so_payment.customer_id · 짝 없으면 needs 손님) · TxnDate = paid_on · TotalAmt · CurrencyRef · PaymentMethodRef(짝 없으면 **failed** — credit_card 는 사람 짝 전까지) · DepositToAccountRef(account_code 짝 · ⚠️ 안 주면 QBO 가 26 으로 채운다) · PaymentRefNum = left(reference, 21) · PrivateNote 「IMS payment <uuid>」 · Line = 활성 붙임마다 LinkedTxn(Invoice Id 는 `qbo_txn` 에서만 · 열린 인보이스 일감 → 기다림 · 일감 없음 · skipped · 이월 · since 전 짝 없음 → failed 글) · 일부만 붙었으면 UnappliedAmt + 경고 · `check_lines` · `lookup` / `qbo_payment_void_body` = qbo_txn 의 Id · SyncToken · sparse true
- **상태 표 `qbo_payment_sync`**(트리거 · done reconcile · 백필 · requeue 가 부른다): 보낸 적 없음 — fp 있으면 queued · failed 는 fp 바뀌면 되살림 · fp 없으면 skipped · sending · unknown 이면 void 를 그 뒤에 blocked / QBO 에 서 있음 — fp 같으면 아무것도 · 다르면 payment_void queued + 새 payment blocked_by void / QBO 쪽 void 됨 — fp 있으면 payment queued
- **트리거 둘**: so_payment_alloc AFTER INSERT OR UPDATE OF voided_at **DEFERRABLE INITIALLY DEFERRED**(발행 안의 auto_deposit · auto_balance · 취소 void 가 커밋 때 한 번에) · so_payment AFTER UPDATE OF status(void · POS 취소) · opening · 연결 없음은 조용히 · 오류는 삼킨다 · `qbo_payment_requeue(p_invoice_id)`(1d 가 부른다) · `qbo_payment_backfill()`(적용 때 한 번 · 커밋 글 「백필 61」)
- **재발행**: claim(kinds 8 · 일감에 지문 · jobs 에 fingerprint · check_lines · lookup) · preview(몸 둘 · check_lines) · doc · list(kinds 8 · ims_name · txn 짝) · retry(payment 는 활성 · 붙임 ≥ 1 · void 는 QBO 에 서 있을 때만) · **done 10 인자**(옛 9 인자 drop · `p_unapplied_amt` · payment → qbo_txn Payment + 지문 + 대조 · payment_void → voided_at · 끝에 reconcile) · 마지막 정의 `20261103050000` · 검증 33/33
- **EF(2e-1c)**: SEND_KINDS 8 · WRITE_ENTITIES + payment · `assertWriteAllowed` — payment 는 만들기 + **`operation=update&include=void`** 만(invoice · creditmemo 는 operation=void 그대로 · delete 없음)
  - **(가) Balance 가드** — POST 직전 check_lines 마다 `GET invoice/<id>` · Balance < 줄 금액 · Balance 없음 · 못 읽음 → **failed · 보내지 않는다**(「QuickBooks already shows … paid on invoice …」) · 결제 하나 = Intuit 1 + 붙은 인보이스 수
  - 2xx → done(p_total_amt = TotalAmt · p_unapplied_amt = UnappliedAmt — DB 가 amount · amount − Σ붙임 과 대조) · 4xx failed · 5xx · 끊김 unknown
  - **unknown 열쇠 = `qbo_job.qbo_name` 한 칸** 「<PrivateNote>|<CustomerRef>|<TxnDate>|<TotalAmt>」(void 는 QBO Payment Id) · 풀기 = 그 날 Payment 조회(`where TxnDate = …` · PII 칸 없음 · MAXRESULTS 100) → CustomerRef · TotalAmt · PrivateNote 로 고름 → 하나 done · 0 not_found(사람 retry) · 둘 이상 ambiguous
  - void = `POST payment?operation=update&include=void` {Id, SyncToken, sparse}(SyncToken 없으면 GET · 5010 → 읽어서 requestid -2) · 2xx(TotalAmt 0 · Line []) → done · unknown 풀기는 Id 로 읽어 TotalAmt 0 ∧ PrivateNote 「Voided」 머리면 done
  - send `{kinds}` · deno 23/23 · 배포 11-03 새벽
- **cron 62 `ims-qbo-send-payments`** `*/5 * * * *` — `qbo_send_payments_enabled` on ∧ connected ∧ 결제 일감에 할 일(queued · next_at 지남 / unknown / 부모 sent 인 blocked)이 있을 때만 EF `{"action":"send","kinds":["payment","payment_void"],"limit":qbo_send_batch}` · timeout 120 s · **11-03 현재 등록 전**(`supabase/ops/cron.sql` 에 명령만 · jobid 는 등록 뒤 실측해 적는다) · → [2026-11-03 밤 · 1034] ⚠️⚠️ **2e-2-1b 배포 전 등록은 kinds 둘**(`payment` · `payment_void`) — 넷(+ `credit_apply` · `credit_apply_void`)으로 등록하면 지금 EF `kindsOf`(`_shared/qbo.ts:808-814`)가 모르는 kind 를 **400 으로 거부 → 결제도 안 나간다(조용한 멈춤)** · cron.sql 실행 블록 = 둘 · 넷 판은 주석 · 2e-2-1b 배포 때 넷으로 다시 등록(unschedule → schedule · jobid 다시 실측) → ✅ [2026-11-04] 등록 jobid **62** · 2e-2-1b 뒤 **kinds 넷**(같은 이름 schedule · 번호 그대로 · unschedule 없이) · cron.sql 실행 블록 = 넷(아래 「켜짐」)
- **켜는 순서(Caleb · deferred 453)**: ① Settings 에서 credit_card QBO 수단 하나 짝 ② Sales → QuickBooks → Payments 몇 장 Preview → Send ③ cron 62 등록(jobid 실측) ④ `qbo_send_payments_enabled` on · ⚠️ **그 전에는 화면의 Send 를 누르지 말 것**(스위치는 자동만 막는다 · 손 send 는 열쇠로만 막힌다)
  - → [2026-11-03 밤 · 판정 1034 · Caleb 「첫 작업으로 결제를 켜자」] **결제 켜기를 2e-2-1b 보다 먼저** — 인보이스는 QBO 로 가는데 결제가 안 가면 QBO 에서 낸 손님이 안 낸 것으로 보인다 · 북키퍼가 A/R Aging 을 보고 스테이트먼트를 손님에게 보낸다 · 붙이지 않은 CreditMemo 는 손님 합계를 이미 줄이므로 덜 급하다
  - 순서(1034): 켜기 전 확인(EF 판 · 대기 결제 일감 수) → 몇 장 Preview → Send → QBO 에서 잔액 확인 → cron 62 등록 **kinds 둘**(비밀값 Caleb) → 스위치 `qbo_send_payments_enabled` on → 첫 회차 보기 → cron.sql 에 「지금 등록 = 둘 · jobid 실측」 적고 커밋
  - ⭐ 손 Send 는 `qbo_job_claim(p_kinds = SEND_KINDS 8, p_job_ids)` 로 잡는다(`_shared/qbo.ts:857`) → 2e-2-1b 전에 credit_apply 일감을 골라도 **잡히지 않는다**(코드 읽음 · 실행은 안 봤다) · 같은 스위치가 크레딧 붙임도 연다(1015) — 2e-2-1b 배포 전에는 cron kinds 로 갈린다
- **화면**(pay screens v1 asung-ims `4d9b62a`): qbo-send 의 Payments 종류 · 결제 미리 보기(check_lines · 합계 · void) · settings 카드 수단 한 수단으로 Find…(983) · 결제 날짜 오늘 + 1 년 · post-dated 칩 · 환불 날짜는 오늘까지 · ⚠️ 일감은 claim 때 blocked 가 된다 — 보내기 전 붙은 인보이스가 안 갔으면 목록에는 waiting(so §98-e 68)
- **안 지은 것**: 1d 이월 짝(452) · 2e-2 크레딧 붙임 · 2e-3 환불 · 받아 둔 돈(454) → [2026-11-04] 2e-2 끝(§14-g) · 남은 것 1d(452) · 2e-3(454) → [2026-11-06] 1d 끝(§14-h) · 남은 것 2e-3(454) → [2026-11-07] 2e-3-1 · 1b 끝(§14-j · 받아 둔 돈 붙임) · 남은 것 2e-3-2 환불(454 부분)
- ⭐ **켜짐 — [2026-11-04 · so-module §100-c 5 · deferred 453 닫힘]** (대화 실측 + 메인 DB 읽기)
  - 켠 순서(1034 그대로): 16:5x 확인(스위치 둘 off · cron 59 · 61 만 · payment queued 139 · skipped 6) → 손 Send 1 장(VISA · 401.45 → 인보이스 60001(QBO #172375) PAID · Credit Card · Deposit to = Clearing - TD Merchant TOR · QBO 결제 #172499) → **cron 62 등록 kinds 둘**(Caleb psql · jobid **62** · `*/5` · active · key_len 64) → 스위치 `qbo_send_payments_enabled` **on** → 17:00 첫 회차 claimed 15 · sent 15 · failed 0 · unknown 0 → 2e-2-1b 배포 · 첫 실물(§14-g) → cron 62 **kinds 넷**(같은 이름 cron.schedule = 번호 62 그대로 명령만 바뀐다 · kinds_four t · key_len 64)
  - ⭐ 열쇠는 화면 · 대화에 안 찍힌다 — jobname `ims-mail-drain` 의 command 에서 `substring(… 'x-ims-cron-key'', ''([^'']+)')` 로 꺼내 `format($fmt$ … %L … $fmt$, s.k)` 로 끼움 · `where length(s.k) = 64`(`supabase/ops/cron.sql` 실행 블록)
  - 실측(17:56 토론토 · begin read only): `inv_config` qbo_send_enabled off · qbo_send_batch 15 · qbo_send_payments_enabled on · qbo_send_since 2026-11-02 / cron 59 · 61 · 62 active · 62 만 credit_apply / `qbo_job` payment **sent 95 · blocked 37 · failed 7 · skipped 6**(합 145) · credit_apply sent 1 · failed 1
    - **blocked 37** — 앞선 일감이 queued(invoice 28 · customer 9) · 인보이스는 북키퍼가 골라 보내므로(971) **인보이스를 QuickBooks 에 보내기 전까지 그 결제는 Blocked 로 기다린다**(부모 sent 뒤 cron 62 가 잡는다)
    - **failed 7** — 모두 「Invoice N was carried over from the previous system and has no QuickBooks match yet」(이월 인보이스 · 1d 짝 뒤 requeue · deferred 452)
  - **skipped 의 두 길**(코드 확인): IMS 가 스스로(보내기 전 void · 붙임 전부 떼기 · 메모 「payment voided or fully detached …」) · 사람이 화면 Skip(메모 필수)
  - 북키퍼는 QBO 에서 결제를 손으로 넣지 않는다(981 · 매뉴얼 01-sales QuickBooks 절)

### 14-g 크레딧 붙임 — qbo-sync-2e-2-1 (2026-11-03 · `487f678` · `20261103200000` · 판정 995 · 1009 ~ 1017 · so-module §99 · EF 는 2e-2-1b 몫 → [2026-11-04] 2e-2-1b `48d5ca4` 끝 · 아래)

- **판정**: **995 (나)** 2e-2 전 크레딧 노트는 CreditMemo 로만 · 북키퍼는 QBO 에서 손으로 붙이지 않는다 · **998 · 998′ → 1009 (나)** IMS 크레딧 노트는 QBO 표준(A/R · 2c 무변) · 쓰기 = **붙임(so_credit_alloc) 한 줄마다 금액 0 Payment 한 장**(Line 둘 = Invoice + CreditMemo · 같은 금액 · sandbox C-5″) · 「쓰기」 두 장 길은 이월 돈(2e-3)만 · **1010** 크레딧은 낸 매장의 인보이스에만(cr-store-1a 가 먼저 섰다) · **1011** 떼기 = 그 장 void(`operation=update&include=void` · C-6) · 지문 없음 · **1012** CreditMemo · Invoice 둘 다 qbo_txn 뒤 · blocked_by 한 칸 차례로 · **1013** 새 0 원 Payment 만 같은 인보이스의 열린 void 일감을 기다림 · **1014** CustomerRef = 매장 · **1015** 스위치 `qbo_send_payments_enabled` 하나 · **1016** 이월 인보이스 붙임 = failed + 1d(452) requeue · **1017** 백필 적용 때 한 번 · TxnDate = 붙임 created_at 토론토 날짜 · 환불 대상 → 2e-3
- **표**: qbo_job kind + `credit_apply` · `credit_apply_void` · ims_kind + `credit_alloc`(ims_id = so_credit_alloc.id) / qbo_txn kind + credit_alloc(type Payment)
- **몸 `qbo_credit_apply_body(alloc)`**: CustomerRef = 인보이스 매장(`so_invoice_store`) 짝(크레딧 매장과 다르면 failed · 짝 없으면 needs) · TxnDate = 붙임 created_at 토론토 · TotalAmt 0 · PrivateNote 「IMS credit applied <alloc uuid>」 · Line 둘 · 기다림 = 크레딧 메모 → 인보이스 → 같은 인보이스의 열린 void 일감(payment_void · credit_apply_void) 차례로 wait_job + wait_reason / `qbo_credit_apply_void_body(alloc)` = qbo_txn credit_alloc 의 Id · SyncToken · sparse true
- **상태 `qbo_credit_alloc_sync`** · **트리거 `so_credit_alloc_qbo`**(so_credit_alloc AFTER INSERT OR UPDATE OF voided_at · DEFERRABLE INITIALLY DEFERRED · 결제 트리거와 같은 커밋 끝 · 오류는 삼킨다) · **백필 `qbo_credit_apply_backfill()`** · `qbo_payment_requeue` 넓힘(그 인보이스의 활성 크레딧 붙임도)
- **재발행**: claim · preview · doc · list · retry · done(kinds 10 · credit_apply → qbo_txn credit_alloc · TotalAmt 0 · UnappliedAmt 0 대조) · 마지막 정의 `20261103200000`
  - ⭐ claim 반환의 **`claimed` = ③ 「잡기」 에서 queued → sending 으로 바뀐 행 전부**(뒤에 blocked · failed 로 간 것 포함) — 2e-1b `20261103050000` 451 행 · 2e-2-1 397 행 · DB 현재본이 같다(so §99-c 5)
- **실물**: 백필 일감 1 — CR-01008 → 60026(일감 `512afdee-…` · queued) · 시험 30/30 · 확인 29/29
- ~~**안 지은 것 — 2e-2-1b EF(deferred 461)**~~ → 아래 「2e-2-1b」(11-04 · 461 닫힘) ·: SEND_KINDS 10 · ⚠️⚠️ **`entityKeyOf` 에 credit_apply 명시 가지** — 지금 ELSE = invoice 라 SEND_KINDS 만 넓히고 가지를 안 넣으면 크레딧 붙임을 invoice 로 읽는다(만들 때의 위험 · 1034 의 cron 위험과 다르다) · 가드 Invoice Balance ≥ a ∧ CreditMemo RemainingCredit ≥ a · unknown 풀기 PrivateNote 접두 둘 · void · deno · 배포 Caleb → 화면 qbo-send → 첫 실물 CR-01008 → 60026 Preview → Send(매장 손님은 sandbox 미시험) → cron 62 kinds 넷으로 다시 등록 · N1 · N2 void 순서 · 2e-3 환불 · 받아 둔 돈(454)
- ⭐ **2e-2-1b — EF(2026-11-04 · `48d5ca4` · Fable · deno 24/24 · 배포 Caleb · deferred 461 닫힘 · so-module §100-b)**
  - 배포: `supabase functions deploy qbo --project-ref …` — 노트북 CLI 3.0 이 Yes/No 를 묻는다
  - 이견 답 1 ~ 10: ① (a) payment_void 조건 둘에 `|| credit_apply_void` ② `CREDIT_APPLY_KINDS` + `isCreditApplyKind`(PAYMENT_KINDS 무변) ③ check_lines 가 Invoice 하나 + CreditMemo 하나가 아니면 failed ④ unknown 풀기는 PrivateNote **완전 일치** + isVoidedPayment 제외(0 원은 void 뒤에도 0 이라 includes 면 옛 void 를 잡는다) ⑤ sendPicked 의 need 건너뛰기를 「customer · item 이 아니면 전부」(isNeedKind) ⑥ nameField = PrivateNote ⑦ 가짜 Intuit 넷(RemainingCredit · CreditMemo LinkedTxn · 0 원 응답 계좌 없음 · done 가지) ⑧ 스킬에 「0 원 Payment 는 계좌 없음」 ⑨ 넷 뒤 첫 회차 failed 1 = CR-01014 → 50763(이월 인보이스 · 1016) ⑩ parsePaymentKey 접두 `IMS credit applied `
  - 화면 qs apply v1(asung-ims `21d4ef9`): 종류 「Credits applied to invoices」 · 라벨 Credit applied · Undo credit applied · applyPreview
  - **첫 실물** CR-01008 → 60026: Preview(9242 매장 · 13.52 · QBO #172453 · #172452) → Send → QBO 에 「IMS credit applied …」 Payment $0.00 Closed · 남은 $1.15 는 IMS 결제로 이미 들어가 손님 잔액 $0.00 ⇒ 1014(CustomerRef = 매장) 실물 확인 → 그 뒤 cron 62 kinds 넷
- ⭐ **순서(판정 1038 · Caleb 「퀵북스 작업이 우선적으로 마무리가 되어야 해」)**: QBO 줄기를 다른 IMS 일보다 먼저 — 2e-2-1b(끝) → ~~**1d 이월 인보이스 짝**(452)~~ → [2026-11-06] 1d 끝(§14-h · 452 닫힘) → ~~**2e-3 받아 둔 돈 · 환불**(454)~~ → [2026-11-07] 2e-3-1 · 1b 붙임 끝(§14-j) → **2e-3-2 환불**(454 남은 몫 · 첫 수 qbo-sync-2e-3-2-0 조사) → 원가(COGS) 분개 · 공급처 Bill · 입고 분개(459) · 인보이스 자동 보내기 켜기(971 · `qbo_send_enabled`)는 Caleb
- **그 다음(Caleb 「순서대로」 · deferred 459)**: 원가(COGS) 분개 · 공급처 청구서(Bill) · 공급처 크레딧 · 입고 분개(Inventory / GINR) · 운임 · 관세 분개 — 안 지음 · QBO 는 QuantityOnHand false 라 컷 뒤 IMS 판매 원가가 QBO 에 0

### 14-h 이월 인보이스 짝 — qbo-sync-2e-1d-1 · 1d-2 (2026-11-05 ~ 06 · `bbfcfdb` · `20261105184613` · EF qbo `9b32168` · 판정 1039 · 1044 ~ 1047 · so-module §101 · deferred 452 닫힘)

- **왜**: 이월 인보이스(so_invoice kind opening · 원본이 이미 QuickBooks · 341 · 786)에 컷 뒤 IMS 결제 · 크레딧 붙임이 걸리면 QBO 의 그 인보이스를 알아야 보낸다 — 짝 없으면 failed 「Invoice N was carried over from the previous system and has no QuickBooks match yet」(§14-f)
- **판정**: **1044** 창구 문 = 열쇠 QUICKBOOKS(북키퍼도 · admin 도 열쇠 · 945) · EF action 은 KEY_ACTIONS / **1045** 풀기 = source matched 행 **삭제**(sent 행 아님 · 보낸 것 있으면 거부 · 흔적 qbo_opening_review) · 결제 되살림은 남은 이월 장 0 일 때만 · 풀 때 queued · blocked 는 failed 로 · 목록은 definer 창구 / **1046** 사람 짝 전에 peek(ack) · opening_search / **1047** 「잇기만 하고 보내지 않기」 없음 — 약속 둘: QBO 에 이미 기록한 결제는 IMS 에 또 기록하지 않는다(24 장 선일자 수표) · 컷 뒤 새 결제는 IMS 에만 / **1039** 수단 짝이 서면 그 수단의 failed 결제를 queued 로
- **표**: qbo_txn + `match_how`(auto | manual · source matched 일 때만) · `match_snapshot`(짝 당시 QBO 행 일곱 칸 — Id · DocNumber · TotalAmt · Balance · CustomerRef · SyncToken · TxnDate) / 새 표 `qbo_opening_review`(이월 인보이스마다 마지막 검사 — reason · warning · 본 QBO 행 · 풀림)
- **자동 짝 다섯 조건**(`qbo_opening_check`): DocNumber 완전 일치 ∧ 한 장뿐 ∧ CustomerRef ∈ {매장 짝 · 청구처 짝 · 그 둘의 qbo_entity.parent_id} ∧ TotalAmt = total ∧ Balance = total − prior_settled − IMS 가 이미 보낸 붙임 합
- **창구**(열쇠 QUICKBOOKS): `qbo_opening_candidates`(물은 번호 + QBO 행 → 자동 짝 · 못 지으면 review 에 까닭 · 멱등) · `qbo_opening_match`(사람 짝 · 경고는 p_ack) · `qbo_opening_unmatch`(1045) · 목록 / 속: qbo_opening_slim · check · record · remaining · `qbo_payment_requeue_one`(남은 장 0 일 때만 · 아니면 failed 그대로 · 글 「N carried-over invoice(s) …」) · `qbo_payment_method_requeue`(1039 · `qbo_link_set` 재발행)
- **EF**(1d-2): `opening_candidates {invoice_numbers?, batch?}`(qbo_opening_list 의 match none 번호 → 묶음 150 마다 `select … from Invoice where DocNumber in (…)` · 실측 262 ms) · `opening_read {qbo_id, invoice_id, ack?, peek?}`(GET invoice/<Id> · peek 면 행만 · 쓰기 0) · `opening_search {doc_like}`(3 ~ 30 자 · DocNumber like · MAXRESULTS 20 · 번호가 다른 장 — 「2329611 \| ITRA6260-1」 꼴)
- **첫 실물**(11-06 · 대화): 310 장 중 **자동 299 · 사람 짝 9 · 남음 2**
  - 사람 짝 9 = QBO TotalAmt = IMS total − prior_settled(Cin7 이 몇 달러 정산을 결제가 아니라 금액에서 빼 넘겼다) — 49558 · 49979 · 50171 · 50315 · 50364 · 50383 · 50387 · 50411 · 50599 · peek → ack
  - 남음 2: 2329611 not_found · 47938 잔액 2 센트(deferred 471)
  - 결제 sent 132 → 198 · 크레딧 붙임 1 → 8 / 메인 DB 22:03: matched auto 299 · manual 9 · payment sent 204 · blocked 48 · failed 1 · skipped 11
- ⚠️ **손님 짝은 failed 결제를 되살리지 않는다**(1039 는 수단만) — 손님 짝을 지은 뒤 Retry(deferred 472)
- ⭐ **QBO 하위 손님** — 본사가 낸 결제가 매장 인보이스에 붙으려면 QBO 에서 매장이 본사의 **BillWithParent 하위 손님**이어야 한다(IMS 의 parent_id 와 따로) · 「IMS 부모 · 자식 ≠ QBO 하위 손님」 은 본사 그룹 하나(매장 8) — CHQ #15033 failed 「TxnID Cannot Be Linked : 160028」 · 북키퍼가 QBO 에서 묶고 Retry(deferred 482)
- 손님 중복 레코드 하나(손님 A · 새 레코드를 QBO #4556 에 이음 · 결제 blocked · deferred 481)
- **안 지은 것**: 1d-3 화면(Settings → QuickBooks → Opening invoices · deferred 470) — 지금은 EF 호출(Caleb 콘솔)
- **다음**: 2e-3 받아 둔 돈 · 환불(454) → 459

### 14-i 인보이스 송장 31 자 — qbo-trk-1 (2026-11-06 · `e059e73` · `20261107021000` · 판정 1054 · so-module §101)

- **실물**: 다상자 Freightcom 예약 SO 9 건이 tracking_number 를 「, 」 로 이어 38 ~ 218 자 — QBO TrackingNum 한도 **31 자**를 넘어 인보이스 6 장 failed(60202 · 60203 · 60226 · 60231 · 60235 · 60236)
- **1054**: `qbo_invoice_body` 재발행 하나 — TrackingNum = **첫 오더의 첫 송장번호**(넘으면 31 자 + 경고) · 전체 송장은 **CustomerMemo 둘째 줄 「Tracking: …」**(오더 여럿이면 SO 별 · 1,000 자 자르기) · PrivateNote 무변 · 송장 하나인 인보이스 몸은 바이트 그대로 · 확인 14/14
- ⚠️ CustomerMemo 는 **손님에게도 보인다**(QBO 인보이스 메모 · 북키퍼 안내 deferred 483)
- ⚠️ 고친 뒤 **Retry 는 queued(대기)로 돌아갈 뿐** — 인보이스 자동 보내기가 꺼져 있어(971 · qbo_send_enabled off) Send 를 눌러야 나간다 · 6 장 sent
- 검사 `supabase/tests/qbo_sync_2b1_check.sql` 이 TrackingNum 옛 꼴을 단언하는지 확인 거리(deferred 476)

### 14-j 이월 받아 둔 돈 붙임 — qbo-sync-2e-3-1 · 1b (2026-11-07 · `33c8cdf` · `20261107044131` · EF qbo `26e019a` · 판정 1056 ~ 1062 · so-module §102 · deferred 454 부분 · 341 잇기)

- **왜**: 컷 전에 받아 둔 돈(so_payment method opening · 62 줄 · 6,628.40 · 계정 `_1150040009_`)이 컷 뒤 새 인보이스에 auto_balance 로 붙는다(10 건 · 83.92) — 그 돈은 QBO 에서 AR 이 아니라 **Customer Credits(1150040009)** 계정에 있다(Cin7 이 Sales Receipt · Item 5624 「Customer Credit」 으로 보냈다 · **1059** 실물) · 붙임만 보내면 QBO 인보이스는 열린 채 · 손님 잔액이 두 장부에서 갈린다
- **조사 qbo-sync-2e-3-0**(Opus · 11-06 밤): 이월 받아 둔 돈 62 줄 · 컷 뒤 붙임 10 건 · 모두 auto_balance(paid_on 순이라 이월분이 먼저 쓰임 · 남은 4,234.18 · 손님 47) · 환불 10 건(컷 전 결제일 8 · 2,310.30 / CR-01011 · 01012 2 · 219.79) · 조사 안 「두 장 길 = JournalEntry」 는 이견으로 **CreditMemo**(998′)
- **판정(부록 A · so-module §102-a)**: **1056** 환불 보내기 기준 = 결제일(paid_on)이 컷(10-30) 전이면 안 보냄 · 뒤면 보냄(created_at 기준 기각) / **1057** 환불의 QBO 꼴 = Expense(Purchase) · 정산 계좌 · 줄 Customer Credits + 손님 **→ [2026-11-08] 1065**(크레딧 노트 몫 = A/R 줄 · 이월 돈 몫만 Customer Credits · §14-k) / **1058** 북키퍼는 환불도 QBO 에 손으로 넣지 않는다(→ 1061) / **1060** 북키퍼 손 분개가 보이면 QBO 에서 분개 Delete → 인보이스 잔액 확인 → IMS Retry(OC void 길 기각) / **1061** 이월 돈 손 분개가 실제로 있었다 — 북키퍼에게 「이월 크레딧 분개 손으로 넣지 말 것」 전달 / 1059 · 1062 는 사실(§102-c 2)
- **붙임 한 줄 = QBO 두 장(2e-3-1 · `33c8cdf`)**: 「쓰기」 **CreditMemo `OC-<인보이스>-<n>`**(Item = qbo_link charge `acct:<결제 계정>` → Customer Credits 에서 AR 로 옮긴다 · 세금 2c 꼴 Out of Scope 4 + TaxLine 0 · CustomerMemo 「Credit on account applied to invoice N」 그대로 둠) + **0 원 Payment**(CreditMemo 를 인보이스에 잇는다 · PrivateNote 접두 「IMS opening credit applied 」) · kind 넷 `opening_credit` · `opening_credit_void` · `opening_apply` · `opening_apply_void` · qbo_txn ims_kind 둘(opening_credit ↔ CreditMemo · opening_alloc ↔ Payment)
  - 트리거 = `qbo_job_on_payment_alloc` 본문 재발행(새 트리거 0 · so_payment_alloc 잠금 0) · 기다림 = 인보이스 → credit → apply(blocked 사슬) · **CustomerRef = 돈의 주인** · 인보이스 매장과 다르면 failed(QBO 하위 손님이면 경고) · qbo_credit_apply_body 1013 에 opening_apply_void · requeue 넓힘 · retry 넷 · done 대조 · 백필 10 → 20 · claim · preview · doc · list 재발행 · 시험 34/34 · 확인 33/33 · 잠금 9.1 s
- **EF(2e-3-1b · `26e019a`)**: SEND_KINDS **14**(customer · item · invoice · invoice_void · credit · credit_void · payment · payment_void · credit_apply · credit_apply_void · opening_credit · opening_credit_void · opening_apply · opening_apply_void) · 새 갈래 0 — credit · credit_void · credit_apply · payment_void 길에 조건 여덟 · entityKeyOf 명시 가지 넷 · OPENING_CREDIT_KINDS · OPENING_APPLY_KINDS(TXN_KINDS · CREDIT_APPLY_KINDS 무변) · 시험 ㉕ · deno 26/26 · **가드 둘** = 보내기 직전 QBO 다시 읽기(Invoice Balance ≥ a · CreditMemo RemainingCredit ≥ a · 아니면 failed) + 모르면 unknown(apiWrite 재시도 없음)
- **cron 62**: 첫 실물 두 호출(손으로 · 05:36 ~ 05:38 UTC · **OC-60172-1 → 60172** 두 장) 뒤 `ims-qbo-send-payments` 를 kinds **여덟**으로 다시 schedule(같은 이름 = jobid 62 그대로 · 05:40 UTC 첫 회차 · kinds_eight t · where_eight t · key_len 64) · 레포 `supabase/ops/cron.sql` 실행 블록은 docs-1107 이 DB 실물에 맞췄다(넷 판은 기록 주석)
- ⭐ **60189 — 가드가 막은 중복 · 북키퍼 손 분개 · 삭제 → Retry(§102-c 2)**: opening_apply 13.47 이 「QuickBooks already shows 1330.01 paid on invoice 60189(balance 0 < 13.47)」 로 failed → QBO Audit history 에서 **Journal Entry TEST10312026**(북키퍼 · 차 Customer Credits / 대 A/R 13.47 · 결제 안에서 그 크레딧을 써 인보이스를 1330.01 로) → 그 뒤 OC-60189-1(172901)이 같은 13.47 을 또 옮겨 Open Balance −27.93(IMS 14.46) → Caleb 이 분개 **Delete**(Reverse 아님) → 잔액 13.47 → Retry → cron 62 → opening_apply **sent 172911**(attempts 2) → PAID · Open Balance **−14.46 = IMS 14.46** · 「Automatically apply credits」 짐작은 기각(985 off)
- ⭐ **QBO 와 IMS 대조의 기준 = 손님 잔액(QBO Open Balance = IMS Available)** — 구성이 달라도 잔액이 같은지부터 · 어긋나면 QBO 거래 목록 · Audit history 를 먼저
- **실측(11-07 19:15 토론토)**: opening_credit sent 7 · blocked 3 / opening_apply sent 7 · blocked 3 · failed 0 · 결제 식구 전체 payment sent 204 · blocked 48 · failed 1(CHQ #15033 · 482) · skipped 11 · credit_apply sent 8 · blocked 3 · qbo_send_payments_enabled on · qbo_send_enabled off(971)
- ⚠️ sent 일감에 옛 `last_error` 가 남는다(sent 489 중 37) — 비울지 기록으로 둘지 판정 대기(deferred 486) · 화면 qbo-send 는 opening 넷의 이름표가 아직 원래 이름(`opening_apply` · deferred 495)
- **남은 것**: 북키퍼 QBO Audit log(붙임 성공 6 건 + 대기 3 건 60257 · 60258 · 60282 · 손 분개 있으면 삭제 · deferred 496) · **2e-3-2 환불**(454 남은 몫 — 첫 수 qbo-sync-2e-3-2-0 조사: CreditMemo 환불의 QBO 꼴 sandbox · paid_on 컷 뒤 대상 쿼리(1056) · 컷 전 8 건 「손으로 들어감」 표시 · 989 실측 · 보내기 전 「QBO 에 북키퍼 손 기록이 이미 있나」 확인 길) · D-2 선결제 공백(493)
- **다음**: 2e-3-2(454) → 459 → [2026-11-08] 2e-3-2 크레딧 노트 몫 끝(§14-k · 454 닫힘)

### 14-k 환불(크레딧 노트 몫) — qbo-sync-2e-3-2-0 · 2e-3-2-1 · 1b · 1b2 (2026-11-08 · `e8babe9` · `20261108075221` · EF qbo `84afde4` · `8b12366` · 판정 1065 ~ 1075 · so-module §103 · deferred 454 · 495 닫힘)

- **왜**: 크레딧 노트를 돈으로 돌려준 환불(so_payment kind refund · 손님 크레딧을 갚는다)이 QBO 에 없으면 CreditMemo 가 손님 크레딧으로 열린 채 남는다 · 북키퍼는 환불을 손으로 넣지 않는다(1058)
- **조사 2e-3-2-0**(Opus) + **sandbox 두 회**(Caleb · API Explorer · 대화 Claude 안내 · 원문 `~/asung/prompts/qbo-sync-2e-3-2-0-sandbox.md` md5 8 `f6c91ee7` · `…-sandbox-2.md` `6e8bb4c9` — 손님 이름 · realm 은 여기 안 적음):
  - Purchase(PaymentType Cash · 줄 AccountBasedExpense **A/R** + CustomerRef) = 손님 잔액 +a · **Customer Credits** 줄은 잔액 무변 · 섞인 한 장의 열린 금액 = A/R 줄 합
  - 0 원 Payment LinkedTxn TxnType **"Expense"** · CreditMemo 여럿을 한 장에
  - 잇기 · 풀기가 Purchase · CreditMemo **SyncToken 을 올린다**(안 읽으면 5010)
  - Purchase 는 Void 메뉴 없음 · Full update 금액 0 + PrivateNote 「Voided - 」 = status Voided(금액 0 만으로는 아님)
  - Purchase query 는 **TxnDate 만**(EntityRef · PrivateNote 는 4001) ⇒ 손 기록 가드는 TxnDate 범위(±7 일)로 읽고 거른다
  - Payment 응답 **txnOpenBalance = 잇기 직전** 열린 금액 · ⚠️ Purchase 의 열린 금액은 Purchase 에서 못 읽는다(Payment 응답으로만)
  - CreditMemo 몸 GlobalTaxCalculation NotApplicable → QBO 가 TaxExcluded 로 둔다
- **판정(so-module §103-a)**: **1065** 환불 한 줄 = Purchase 한 장(크레딧 몫 A/R · 이월 몫 Customer Credits · 첫 짓기 = 크레딧 노트 몫만 · 1057 을 바꿈) / **1066** 환불된 이월 결제를 쓰는 이월 붙임은 failed(qbo_opening_refunded_block) / **1067** refund_from_account > 0 이면 환불 통째로 failed / **1068** 컷 = paid_on 고정 date '2026-10-30'(qbo_send_since · created_at 재사용 금지) / **1069** 적용일(2026-11-08) 뒤 created ∧ paid_on < 컷 → failed 「check QuickBooks, then Retry or Skip」 / **1070** 컷 전 8 건(2,310.30) 일감 없음 · IMS void 시 refund_void failed 알림(Retry 거부 → Skip) / **1071** 0 원 Payment 는 환불 하나에 한 장 · kind 넷이 so_payment.id 하나를 열쇠로 / **1072** 되돌리기 = Payment void → 다시 읽어 SyncToken → Full update(줄 0 + 「Voided - 」) · Delete 없음(374) / **1073** 줄 세금 = Out of Scope (Purchase) 짝(운영 4 · sandbox 6) / **1074** refund_void 전 읽은 Purchase 에 LinkedTxn Payment 남으면 failed / **1075** 잇기 경고 = txnOpenBalance − Amount
- **DB(2e-3-2-1 · `e8babe9`)**: qbo_job kind **넷**(refund · refund_void · refund_apply · refund_apply_void · ims_kind refund · ims_id = so_payment.id) · qbo_txn ims_kind refund · refund_apply · 몸 넷 = qbo_refund_body(Purchase · PaymentType Cash · AccountRef = 환불 계정 짝 · EntityRef 손님 · 줄 = A/R 몫 합 + CustomerRef + TaxCodeRef) · qbo_refund_apply_body(0 원 Payment · Purchase + CreditMemo 들) · apply_void_body · void_body · 상태 맞추기 qbo_refund_sync · 트리거 `so_payment_refund_qbo`(AFTER INSERT · deferrable initially deferred · kind refund) + qbo_job_on_payment_status 가지(void) · 기다림 = 크레딧 노트(qbo_txn credit) → refund → refund_apply(blocked 사슬) · 백필 2 건(CR-01011 · 01012) · qbo_refund_requeue(세금 짝이 서면) · 재발행 claim · preview · doc · list(kinds 18) · retry · done · link_set · 시험 35/35 · 확인 35/35
  - 막힘 글(qbo_refund_block): 통화 없음 · 통화 ≠ 기본 통화(USD 손님 셋의 A/R 계정이 `_61_` CAD — deferred 499) · 받아 둔 돈 몫(1067) · 세금 짝 없음(1073) · 컷 전 늦게 적음(1069) → [2026-11-08 밤 · 3-1 ⬜3 · §15-g] 499 를 고쳐도(A/R `_212_`) **통화 ≠ 기본 통화면 failed 그대로** — 블록은 so_payment 통화를 본다(블록 무변 · USD 환불을 여는 차수 = deferred 511)
- **EF(2e-3-2-1b · `84afde4` · 1b2 `8b12366`)**: SEND_KINDS **18**(… opening 넷 + refund · refund_void · refund_apply · refund_apply_void) · assertWriteAllowed 에 **purchase 몸 검사**(만들기 · void 꼴만 · 다른 엔티티로 넓히기 = deferred 501) · 가드 = CreditMemo RemainingCredit ≥ 몫 · 같은 손님 손 기록(TxnDate ±7 일) · **refund_void = 잇는 Payment void 먼저(1074) → Purchase 다시 읽기 → Full update** · unknown 풀기(refund = 그날 Purchase 조회 → PrivateNote 완전 일치 ∧ 손님 · 여럿이면 ambiguous · refund_apply 는 접두 「IMS refund applied 」) · 1b2 openBalanceNote(Expense 줄 \|after\| > 0.004 경고 · 남음 · 모자람 「short」 · CreditMemo 줄은 모자람만 · 1075) · 시험 27/27 · 배포(사람)
- **첫 실물(11-08 · Caleb 손 Send 넷)**: CR-01011 → Purchase **172912** · Payment **172913** / CR-01012 → **172914** · **172915** · CreditMemo 172491 · 172490 RemainingCredit 0 · 손님(QBO 10505) Balance 0 · Paid from `1150040028` Clearing - E-Transfer(Bank · CAD) · 172913 · 172915 결과 글 「after linking … not all 0」 = **거짓 경고 · 실제 0**(1b 가짜 Intuit 이 txnOpenBalance 를 뒤 값으로 줬다 → 1b2 · 옛 글은 DB 무접촉)
- **cron 62 = kinds 열둘**(11-08 · jobid 62 그대로 · 같은 이름 cron.schedule · 열쇠는 그 job 자신의 command 에서 format(%L)) · 확인 11-08 04:35 ~ 04:50 토론토 succeeded · `supabase/ops/cron.sql` 실행 블록 = DB command 글자 그대로(열쇠 자리표)
- **화면(qs refund v1 `0922a44` · v1a `7082d84` · 대화 Claude)**: Sales → QuickBooks 종류 **Carried-over money**(opening 넷) · **Refunds**(refund 넷) · 이름표 여덟 · 미리 보기(Purchase · 0 원 Payment · void 몸) · v1a 「Refund linked to credit」 = Refund 먼저 또는 둘을 함께 보낸다(blocked 사슬)
- **남은 것**: 받아 둔 돈 몫 · 이월 몫 · 컷 뒤 결제 몫 환불 = 「환불을 결제에 매기」(deferred 500) · ~~USD A/R 데이터(499)~~(→ [2026-11-08 밤] 3-1 로 닫힘 · USD 환불은 블록 통화 때문에 failed 그대로 = 511) · 몸 검사 넓히기(501)
- **다음**: 459(원가 · 공급처) · 470 · 471 → 500

## 15. 원가 · 공급처 줄기 — 판정과 Cin7 꼴 (2026-11-08 저녁 · qbo-sync-3-0 · 판정 1080 ~ 1090 · so-module §104 · deferred 459)

- **상태**: 판정 끝 · **짓기 전** — QBO 로 원가 · 공급처 거래를 보내는 코드는 아직 0 · 이 절은 짓기의 바탕 → [2026-11-09] 하루 원가 장 짓기 끝(§15-i ~ §15-k · 보낸 장 0) · **공급처 쪽 판정 끝(1115 ~ 1130) · 4-0 조사 · 4-1 콘솔 · 4-2a sandbox 끝 · 짓기 전**(§15-l · so-module §108) → [2026-11-09 오후 · §15-m · so-module §109] **공급처 Bill · VendorCredit 지음(4-3 · 4-4) · 운영 첫 송신 — 공급처 Bill 7 장 · 하루 원가 장 12 장 sent** · 공급처 결제(BillPayment) 보낸 것 0 · 자동 없음 — **매일 원가 장 · 새 공급처 Bill 은 북키퍼가 Queue/Preview → Send**(Caleb 「ㄱ」 · 자동은 나중에 Caleb)
- **다음**(2026-11-09 · Caleb 「좋아」): ~~**4-3 DB Bill · VendorCredit(11 월 안 · 1120)** → 4-4 EF + 화면 + 첫 실물 손 Send → 4-2b sandbox →~~ 4-5 결제 → 4-6 켜기 · 북키퍼 안내 · 정본(§15-l ⑤) → [2026-11-09 오후 · §15-m ⑦] 4-3 · 4-4 · 첫 실물 · 4-2b 끝 · 다음 = **4-5 결제 DB + EF + 화면**(1123 · 1124 · 1125 · 4-2b 규칙 · 밀린 IMS 결제 4 건 — USD 3 건은 환율 칸을 채운 뒤) → 4-6(켜기 · 정본) · 화면 차수(qbo-send 공급처 꼴 · 보낸 장 미리 보기) · 1131 나
- **원천**: 조사 qbo-sync-3-0(Opus · DB 읽기만 · QBO 쓰기 0 · 보고 `~/asung/prompts/qbo-sync-3-0-report.md` 296 행 · md5 8 `21e85439`) + 운영 QBO 콘솔 실측 **M1 ~ M10**(11-08 저녁 · Settings 콘솔 · 읽기만 · 운영 realm · Caleb 실행 · 대화 Claude 판독 · 걸음 11) · 판정 원문 표는 so-module **§104-a** 가 정본(이 절은 요지)
- ⚠️ 공개 레포 — 공급처 · 손님 상호 · 사람 이름은 적지 않는다(북키퍼는 「북키퍼」) · QBO Id · 문서 번호 · 계정 번호 · 금액은 적는다

### 15-a 판정 요지 (1080 ~ 1090)

| 판정 | 요지 |
|---|---|
| 1080 | 상품 공급처 Bill 은 **IMS 가 보낸다** · 북키퍼는 컷 뒤 상품 Bill 을 손으로 넣지 않고 기다린다 · 운영 비용 Bill 은 지금처럼 북키퍼가 QBO 에서 · 밀린 IMS 공급처 인보이스 7 장(USD 108,794.98 · CAD 1,073.50)은 싱크가 서면 보낸다 ⇒ 3-0 의 안 (다)(원가 · 재고 합계 + 공급처 문서는 문서마다) · 손 Bill 짝 맞추기 차수 없음 |
| 1081 | 공급처 결제는 **Bill 이 태어난 곳에서** — 컷 전 Bill(Cin7 이 보낸 것)은 북키퍼가 QBO 에서(913 그대로) · IMS Bill 은 IMS 에서 결제하고 IMS 가 **BillPayment** 를 보낸다 · 밀린 IMS 결제 4 건(USD 72,881.34 · CAD 1,073.50)은 Bill 과 함께 · 짓기 때 IMS 결제에 「어느 계좌에서 나갔나」(#104 CAD 수표 · ~~#138 USD 수표~~ → [11-09 · §15-l ②] #138 = 계좌 Id 138 MTFX USD(수표 번호 아님) · #132 카드) · 북키퍼에게 「IMS Bill 은 IMS 에서 결제」 전달 · §13 「Bill payment 받음」 은 컷 전 Bill 에만 |
| 1082 | 판매 원가 = **하루 · 창고마다 JournalEntry 한 장**, 그 안에 **SO 마다 줄**(차 #58 / 대 #59 · 줄 설명에 SO 번호) · 늦게 생긴 변동은 보낸 장을 고치지 않고 **다음 장에 그 SO 번호 줄**로 |
| 1083 | 밀린 판매 원가는 1082 꼴로 **11-02 부터 날마다 그날 날짜로**(따로 코드 없음) · 10-30 몫은 Cin7 이 이미 보냄(M6) · 밀린 Bill 7 장 · 결제 4 건도 문서마다 원래 날짜로 · 짓기 시험에 「10-30 Cin7 SO 78 장 ↔ QBO JE 하나씩 맞대기」 |
| 1084 | 팔린 뒤 확정된 운임 · 관세 · 통관(cost_late)의 **팔린 몫 → #58**(하루 장에 그 SO 번호 줄 · 차 #58 / 대 해당 COS 계정) · 남은 몫 → #59 ⇒ QBO #58 = IMS 판매 원가 · #59 움직임 = IMS 재고 금액 움직임 |
| 1085 | 창고 간 트랜스퍼는 하루 장에 줄로(출발 차 In Transit #1150040007 / 대 #59 · 도착 차 #59 / 대 In Transit) · 같은 창고 빈 이동은 보내지 않는다 · ⚠️ **살린 트럭 TR-06396 ~ 06399 도착은 보내지 않는다**(출발 분개가 QBO 에 없음 · 보내면 In Transit −15,159) |
| 1086 | QBO 재고 **출발점은 지금 맞추지 않는다** — 싱크는 컷 뒤 **움직임**만 · 월 검산 = 「그달 QBO #59 움직임 = 그달 IMS 재고 금액 움직임」 · 잔액 차이 약 150 만은 **알려진 차이** · 출발점 맞추기 · 오래된 재고 write-off 는 회계사와 결산 때(deferred 503) · ⚠️ 그 write-off 를 일반 조정으로 보내면 QBO 에서 두 번 빠질 수 있다 |
| 1087 | 재고 조정 계정 = `inv_adjust.account_code`, 비면 **Settings 기본 #1150040010(COGS:Inventory Discrepancy)** · 늘어남 · 줄어듦 같은 계정 · 지금 빈 확정 41 건은 기본값으로 · 오래된 재고 write-off 는 1086 대로 따로 |
| 1088 | CAD 공급처 11 곳 `account_payable_code` → `_62_` · 공급처 기본 A/P 를 **통화별로**(CAD #62 · USD #109) · 저장 때 「A/P 계정 통화 = 공급처 통화」 아니면 거부 · 손님 쪽 deferred 499(A/R 계정 통화 = 손님 통화)도 **같은 차수 · 같은 방식** |
| 1089 | 비용 문서(`po_charge`) → QBO Bill: 관세 → **#134 Duty - COS**(세금 없음) · 관세 문서의 세금(수입 GST) → **#125 GST Payable on Import 줄**(세금 코드 아님 · 원가에 얹지 않음) · 통관 → #135 · 운임 → #136(보통 세금 코드) · 재고에 얹기 · 팔린 몫은 1084 · 관세 「금액 0 · 세금 600.26」 은 **정상 꼴**(3-0 이견 9 의 「결함」 짐작 정정) |
| 1090 | 보내는 사건의 경계 = **컷(10-30 18:57) 뒤 IMS 에서 생긴 원가 사건** — 판매 원가 11-02(첫 IMS 출고)부터 · **조정은 10-31 부터**(확정 41 건 포함) · cost-fix-1(11-01)의 **opening_fix · carried(526 줄 · 20,783.50) 둘 다 안 보냄**(IMS 기초를 Cin7 · QBO 가 이미 가진 값으로 바로잡은 것 — 보내면 #59 가 두 번 · 932 와 같은 이유) · 1083 의 「11-02 부터」 는 판매 원가로 좁힘 |

### 15-b Cin7 이 QBO 에 보내던 꼴 — 짓기의 바탕 (M8 · M9 · M10)

**M8** 10-15 하루 JE 87 장(DocNumber 앞머리 | 계정 짝 · 장 수):

| DocNumber | 계정 짝 | 장 | 뜻 |
|---|---|---|---|
| `SO` | 차 #58 / 대 #59 | 59 | 판매 원가 |
| 숫자만(예 50056 · 50091 · 50081) | 차 #58 / 대 #59 | 11 | 판매 원가 · DocNumber 가 인보이스 번호(뜻 미확인 · deferred 506) |
| `ST` | 차 #1150040010 / 대 #59 | 5 | 조정 줄어듦 |
| `ST` | 차 #59 / 대 #1150040010 | 1 | 조정 늘어남 |
| `CR` | 차 #59 / 대 #58 | 2 | 반품 restock |
| `TR`(TR-05752 · 05753) | 차 #59 / 대 #1150040007 | 2 | 트랜스퍼 도착 |
| `TR`(TR-06114 · 06117) | 두 계정 양쪽 | 2 | 뜻 미확인(deferred 506) |
| 숫자 109596 | 차 #59 / 대 #134 · 차 #59 / 대 #135 | 1 · 1 | 관세 · 통관을 재고에 얹음 |
| `INV0350520` · `2204251` | 차 #59 / 대 GINR | — | 입고 |
| `FG` | #59 ↔ #59 | 1 | 조립 |

- **M9** DocNumber 109596 = 공급처 **상품** Bill 169649(10-13 · USD 12,271.17 · 줄 50 개 모두 GINR #1150040012 · 세금 코드 2 · 세금 0) + JE 169749(10-15 · 관세 853.95 · 차 #59 / 대 #134) · 169748(10-15 · 통관 103.75 · 차 #59 / 대 #135) · 170041(10-20 · 입고 17,446.78 · 차 #59 / 대 GINR) ⇒ Cin7 은 landed JE 의 DocNumber 로 **그 PO 의 공급처 인보이스 번호**를 썼고, 관세 · 통관을 **입고(10-20)보다 먼저(10-15)** 재고에 얹었다(Invoice First · IMS 와 시점 차이 = deferred 507 → [2026-11-08 밤] 닫힘 — 하루 장의 landed 날짜 = IMS 가 얹은 날 · §15-h) · 입고 CAD 와 Bill USD × 환율이 다르면 GINR 에 찌꺼기(지금 462.50 — 짐작) — 1080 으로 Bill · 입고를 둘 다 IMS 가 보내면 같은 환율을 박을 수 있다
- **M10** 10 월 Bill 80 장 훑음 · 계정 134 · 135 · 136 · 13 · 125 가 든 것 30 · 통관 업체(Vendor 6078) Bill = **관세 #134(세금 코드 2) + 수입 GST #125(세금 코드 4)** 두 줄(예 169541 = 853.95 + 918.31 — 관세 853.95 가 M9 의 관세 JE 와 같은 돈) · **수입 GST 만 있는 Bill 도 있다**(169992 317.71 · 168149 1,596.06 — #125 한 줄) · 운임 Bill = #136 + 보통 세금 코드(예 168153 885.46 + 세금 44.27) ⇒ 1089

### 15-c 컷 뒤 QBO 실측 — 북키퍼가 넣는 것 · 안 넣는 것 (M1 ~ M7)

- **M1** JournalEntry TxnDate 10-01 ~ 10-29 count **1,538**(10 월 Cin7 SO 1,190 → SO 마다 한 장 꼴 확정)
- **M2** IMS 공급처 인보이스 7 장 번호(`AST261028` · `V137500-IN` · `1801158180` · `RIH2026000000` · `2026-02394` · `Order #8884650` · `484908, 484909`)로 Bill 조회 = **0** ⇒ IMS 가 보내도 두 번이 아니다(AST261028 의 invoice_date 10-28 포함)
- **M3** Bill CreateTime ≥ 2026-10-30T19:00:00-04:00 첫 쪽 10 장(10 행 캡 · 전체 수는 안 셈): 모두 CAD · A/P #62 · 줄 계정 24 · 80 · 183 · 182 · 78 · 36(운영 비용) · GINR 0 · IMS 공급처 Vendor(7170 · 5835 · 108 · 7640 · 3646 · 7204 · 315) 0 · 합 8,844.42 · 만든 시각이 근무 시간에 흩어짐(손 입력) ⇒ 북키퍼는 운영 비용 Bill 만 넣는다
- **M4** BillPayment 같은 조건 count **15** — 모두 QBO 에 있는 Bill 에 붙음(대부분 컷 전 Bill Id 162446 ~ 171793) · USD 셋(20,310.48 · 10,640.10 · 43,517.84 · ~~#138 수표~~ → [11-09 · §15-l ②] 계좌 Id 138 MTFX USD) · CAD 34,155.26(Bill 12 장 · Vendor 6078 의 10 월 Bill 한꺼번에) · 나머지는 컷 뒤 운영 비용 Bill(172391 · 172320 · 172321 · 172358 등)의 결제 · 지급 수단 Check #104 / #138 · CreditCard #132 · **IMS po_payment 4 건과 겹침 0**
- **M5** Purchase TxnDate ≥ 10-30 count **45**(CAD 43 · 251,941.84 / USD 2 · 13.56 · 7.00) · IMS 금액 · Vendor 와 겹침 0 ⇒ IMS 공급처 결제 4 건은 QBO 어디에도 없다
- **M6** JournalEntry TxnDate = 10-30 count **81** · SO-18513 · SO-18622 · SO-18639 · SO-18607 · SO-18004 다섯 모두 있음(차 #58 / 대 #59 · 예 SO-18513 60,655.00) · CreateTime 14:32:59 ~ 14:33:04 −07:00 = **토론토 17:33**(§13 마지막 Sync 17:31) ⇒ 10-30 판매 원가는 Cin7 이 보냈다(1083 경계 11-02) · 81 ≥ IMS 원장 10-30 SO 78 — 17:31 ~ 18:00 SO 가 빠졌을 가능성은 낮다(짐작 · 짓기 시험에서 하나씩 맞댄다)
- **M7** 잔액 = §13 「QBO 재고 잔액」 줄 · ⚠️ API 는 손익 계정(#58) 잔액을 0 으로 준다 — 원가 검산은 기간 보고서로
- **알려진 차이(1086)**: QBO #59 1,464,935.89(하위 포함 1,422,924.05) vs IMS 토론토 2,726,926.82 + 에드먼턴 241,056.08(= 2,967,982.90 · IN_TRANSIT 20,647.70 를 더하면 2,988,630.60) — #59 단독 대 두 창고면 1,503,047.01 · 하위 포함 대 IN_TRANSIT 포함이면 1,565,706.55 · 어느 쪽이든 약 150 만 · 까닭(Caleb): 기초 재고를 QBO 와 맞추지 않았고 Cin7 이 재고 자산을 QBO 와 다르게 다뤘으며 IMS 재고에 write-off 할 것이 상당수 남아 있다 ⇒ 맞추기는 결산 때(deferred 503)

### 15-d IMS 쪽 실측 (3-0 보고 ② 인용 · 11-08 · 이 차수는 DB 를 다시 세지 않았다)

- **판매 원가**(`inv_layer_consume` doc_type sale): 11-02 ~ 06 IMS **264 SO · 126,715.43**(5,108 줄) · 10-30 Cin7 원장 78 SO · 85,898.72 · 10 월(10-01 ~ 29 · Cin7) 707,736.29 · SO 1,190 · 컷 뒤 264 SO 는 모두 인보이스 있음(QBO 에 있음 208 SO · 108,084.69 / 인보이스 일감 대기 56 SO · 18,630.74)
- **opening_fix · cost_late**: `inv_cost_adjust` opening_fix 259 건 · 13,035.48(posted 11-01) · 열쇠 `line_ref like 'adj:%'` 소진 줄 701 · 컷 뒤 cost_late 가 떨어진 판매는 전부 10-30(Cin7) 몫 79.34 · **IMS 판매(11-02 ~)에 떨어진 cost_late 0**
- **공급처 인보이스** `po_invoice` confirmed **7**(크레딧 0 · 모두 Vendor 짝 있음): AST261028(10-28 · USD 33,366.24) · V137500-IN(USD 14,555.10) · 1801158180(USD 8,599.66) · RIH2026000000(USD 24,960.00) · 2026-02394(USD 16,195.50) · Order #8884650(CAD 1,073.50 · A/P `_62_`) · 484908, 484909(USD 11,118.48) — USD 합 **108,794.98** · USD 여섯 모두 A/P `_109_`
- **입고**: PO 입고 2(RCV-00117 PO-02048 · RCV-00121 PO-02004) · 레이어 18 줄 · **12,989.53 CAD**(토론토) · 나머지 confirmed 4 는 PO 없는 트랜스퍼 도착 입고(RCV-00115 · 116 · 118 · 119 = TR-06396 ~ 06399) ⇒ 청구 대부분이 「청구됐지만 아직 안 받은 재고」(Cin7 꼴의 GINR)
- **공급처 결제** `po_payment` **4**: USD 72,881.34(AST261028 33,366.24 + V137500-IN 14,555.10 + RIH2026000000 24,960.00) · CAD 1,073.50(Order #8884650)
- **landed**: 컷 뒤 `po_charge` 4 장 **모두 draft · 배분 0**(freight 408.76 + 세금 20.44 · freight 897.66 + 44.88 · duty 0 + **600.26** · brokerage 90 + 11.70) ⇒ 컷 뒤 landed · cost_late **0** · 10 월(Cin7) landed 8 PO · 10,007.71 · 그 중 팔린 뒤 얹혀 COGS 로 간 몫 4,403.29
- **트랜스퍼**: 창고 간 10 월 19 문서(빈 이동 919) · 컷 뒤 출발 2(TRF-00003 11,150.38 · TRF-00005 9,482.65) · 도착 = 살린 트럭 TR-06396 ~ 06399(합 15,158.90 · 1085 로 안 보냄) · IN_TRANSIT 재고 가치 20,647.70
- **조정** `inv_adjust` confirmed 41(10-31 ~ 11-06) · 들어온 레이어 472.05 · 나간 소진 1,082.02 · **account_code 41 건 모두 빈 값**(→ 1087) · 10 월(Cin7) 조정 107 문서
- **반품 restock**(`so_credit` 19 장 11-02 ~ 06): COGS 되돌림 몫 1,705.94 · 조립 컷 뒤 0
- **데이터 결함**(3-0 이견 8): CAD 공급처 11 곳 A/P `_109_` · 설정 `supplier_default_account_payable_code` `_109_` 하나(→ 1088) · `product.inventory_account_code = _58_` 1 행(작은 것)
- **IMS 재고 금액**(레이어 + 얹기 − 소진 직접 합): 토론토 **2,726,926.82** · 에드먼턴 **241,056.08** · IN_TRANSIT **20,647.70**(합 2,988,630.60)

### 15-e 짓기 순서 · 크기 · 짓기 때 정할 것

- **순서**(Caleb 「니가 말한 순서대로 가자」): ① **데이터 바로잡기 3-1**(1087 조정 기본 계정 · 1088 + 499 A/P · A/R 통화 · Fable) → ② **하루 원가 장**(1082 ~ 1085 · 1087) DB → ③ 보내기 EF · 시험 → ④ 공급처 Bill · 비용 Bill · 입고 분개(1080 · 1089) → ⑤ 공급처 결제 BillPayment(1081) → ⑥ 밀린 것 보내기 · 켜기(1083)
- 짓기 때 확인: AST261028 은 TxnDate 10-28 — QBO 10 월 마감(closing date) 여부를 먼저 본다 → [2026-11-08 밤 · 콘솔 C4 · Caleb QBO 화면] 마감일 **2026-08-31** · 회계연도 9 월 시작 ⇒ 10 월 날짜로 보낼 수 있다(§15-h)
- **크기**(짐작 · 3-0 보고 안 (다)): **8 ~ 10 차수**
- **짓기 때 정할 것**: ~~landed 를 하루 장의 어느 날짜로(deferred 507)~~ → [2026-11-08 밤] IMS 가 얹은 날(507 닫힘 · §15-h) · Cin7 JE 꼴 둘의 뜻(506) · 10-30 Cin7 SO 78 ↔ QBO JE 맞대기(1083) · IMS 결제의 지급 계좌 칸(1081) · 북키퍼 전달(1081)

### 15-f EF query 꼴 · 콘솔 꼴 (실측 11-08)

- **EF qbo query 응답**: `{ ok, entity, rows, count, totalCount, startPosition, maxResults, more, intuit_tid }` · `select count(*)` 는 totalCount · ⚠️ **`select *` 는 쿼리에 MAXRESULTS 200 을 적어도 `maxResults 10` 으로 10 행만** · STARTPOSITION 으로 쪽 · ⚠️ **`more` 가 마지막 쪽(5 행)에서도 true** — 끝은 **행 수 < 10** 으로 판단(deferred 504) · Purchase 는 TxnDate 로 거른다(§14-k) · Bill 응답에 VendorAddr 가 실린다(읽기 가드 PII_FIELDS 에 넣을지 deferred 505)
- **콘솔 꼴**: Settings 콘솔에 이미 `q` · `r` 이 선언돼 있다(`Identifier 'q' has already been declared`) ⇒ 콘솔 조회는 `(async () => { … })();` 로 감싸 이름 충돌을 피한다 · 결과를 붙일 때 콘솔을 비우고(🚫 · Ctrl+L) 마지막 결과만 · 응답 꼴은 count 한 줄로 먼저 본다

### 15-g qbo-sync-3-1 결과 — 계정 통화 · 데이터 바로잡기 (2026-11-08 밤 · asung-wms `b7bb430` · `20261108150000` · 판정 1087 · 1088 · 1091 · deferred 499 닫힘 · so-module §105-c 1)

- **파일**: 마이그레이션 `20261108150000_qbo_sync_3_1_account_currency.sql`(1,423 행 · md5 `99ea7918…`) · 시험 `supabase/tests/qbo_sync_3_1_check.sql`(207 행 · `4f742f57…`) · 시험 41/41 · 적용 뒤 확인 41/41 · `rolled_back_clean` · 확인 앞뒤 시퀀스 무변(pg_sequences diff)
- **계정 통화(1091)**: `ref_account.currency_code` text null(CHECK 세 글자 · **FK 없음** — KRW 가 ref_currency 에 없다) · null = 본사 통화 CAD · 채움 `_109_` USD · `_212_` USD · `_203_` KRW — **A/P · A/R 통제 계정만** · 은행 · 결제 계좌의 통화는 채우지 않는다(1081 차수) · po-module §11-h(3369) 의 기각을 이 범위에서만 뒤집음
- **inv_config 키 다섯**: `inv_adjust_default_account_code` = `_1150040010_`(1087) · `supplier_default_account_payable_code_cad` `_62_` · `_usd` `_109_` · `customer_default_ar_account_code_cad` `_61_` · `_usd` `_212_`(1088 · 499) · 옛 키 둘(`supplier_default_account_payable_code` · `customer_default_ar_account_code`)은 값 무변 폴백 · 572 거부 목록에 자동(바꾸기는 마이그레이션) · **KRW 키 없음**(ref_currency = CAD · USD 둘뿐 → KRW 공급처를 만들 수 없다)
- **도우미**: `ims_account_currency(account_id)`(null → 본사 통화) · `ims_account_currency_msg(…)`(거부 글 · 빠져나오는 길)
- **데이터**: CAD 공급처 11 곳 A/P `_109_` → `_62_`(1088) · USD 손님 셋 A/R `_61_` → `_212_`(499 · USD 시험 손님 하나 포함) · touch 트리거를 잠시 꺼 updated_by 보존 · USD 공급처 184 곳은 모두 이미 `_109_`
- **막기**: 지연 제약 트리거 `supplier_account_currency_ck` · `customer_account_currency_ck`(deferrable initially deferred · 발화 때 행을 다시 읽음 · 통화 · 계정 null 이면 통과) — 창구 · 적재 · 손 SQL 모두에 걸린다 · 창구 넷(supplier_create · update · customer_create · update)은 글자 추론 warn → **block `currency_account_mismatch`** · supplier_create 는 통화 블록을 계정 블록 앞으로(통화가 정해져야 기본 키를 고른다)
- **조정 계정(1087 · 1090)**: `inv_adjust_account(adj)` → (account_id · account_code · is_default) — `inv_adjust.account_code` 가 비면 기본 키 · 확정 41 건에 값을 쓰지 않는다(읽을 때 정한다) · 하루 장 · 늦은 원가 조정 몫(1095)이 이것 하나만 읽는다
- **실측 덧**: qbo_entity Account detail 에 CurrencyRef 없음(거울로 통화를 알 수 없었다 → 계정 통화는 IMS 칸) · `qbo_refund_block` 은 so_payment 통화를 본다 — 499 를 고쳐도 USD 환불 failed 그대로(블록 무변 · deferred 511)
- **REST 두 겹 ②(Caleb 화면 · 11-08 밤)**: CAD 공급처 하나 — 통화만 USD 로 저장 → 거부 글(빠져나오는 길 포함) · USD + `_109_` 함께 → 통과 · 되돌림 / USD 시험 손님 — A/R `_212_` 보임 · 통화만 CAD → 같은 꼴 거부
- **화면(asung-ims `bd3d396` · 대화 Claude)**: sup v4a · cs v8c — 계정 고르기 글에 계정 통화(` · USD`) · 통화를 바꾸면 같은 account_type 의 그 통화 계정이 **하나뿐일 때** 자동으로 바꾸고 한 줄 알림(여럿 · 없음이면 알림만) · 본사 통화 = 화면 상수 CAD(빈 currency_code) / set v17a — Reference Book → Account 에 Currency 칸 · 안내 글
- **남은 것**: 조정 계정을 고를 길(509) · 적재 재실행 때 CAD 공급처 11 행 거부(510 · 적재를 고친다) · `qbo_refund_purchase_head` 폴백 통화별 키(511)

### 15-h 하루 원가 장 — 설계 (2026-11-08 밤 · qbo-sync-3-2-0 조사 · 판정 1092 ~ 1103 · 1090 구현 규칙 · so-module §105 · 짓기 전)

- **원천**: 보고 `~/asung/prompts/qbo-sync-3-2-0-report.md`(256 행 · md5 8 `e49b3929` · Opus · DB 읽기만 · QBO · EF · git 쓰기 0) ② · ④ 절 · 운영 QBO 콘솔 C1 · C3 · C4 · C5 · 판정 원문은 so-module **§105-a** 가 정본(이 절은 요지)
- **상태**: 설계 끝 · **짓기 전** — 다음 차수 3-2(DB) → [2026-11-09] 3-2a **적용**(§15-i) · 다음 3-2b → [2026-11-09] 3-2b · 3-3 · 3-4 끝(§15-j · §15-k) · 다음 공급처 쪽(4-0)

**① 22 칸 — 원가 사건 종류의 정본은 DB 제약이다**(레이어 origin 8 · 소진 reason 8 · 얹기 kind 6) · 하루 장은 칸마다 「보냄 · 안 보냄 · 보류 · 막음」 · **제약이 넓어져 표에 없는 칸이 생기면 장을 막고 알린다** · 출고 취소는 레이어 표에 되돌리는 길이 없다(reversal 소진을 쓰는 함수는 `so_credit_cancel` 하나 — 크레딧 노트 취소) · 분할 SO · put_back 은 원가 사건 종류가 아니다

| 칸 | 열쇠(줄 설명) | 차 | 대 | 컷 뒤 실물 |
|---|---|---|---|---|
| 소진 sale | SO 번호 | #58(Entity = 인보이스 손님 · 1103) | #59(창고) | 264 SO · 126,715.43 |
| 레이어 creditnote(restock) | CR 번호 | #59 | #58(Entity = 크레딧 노트 손님 · 1103) | 18 CR · 1,705.94 |
| 소진 reversal(크레딧 취소) | CR 번호 | #58 | #59 | 2 CR · 429.19 |
| 레이어 adjust_new · adjust_existing | ADJ 번호 | #59 | `inv_adjust_account(adj)`(1087) · 한 건 금액이 문턱 1,000 넘으면 **보류**(1099) | 472.05 대(0 원 7 줄은 줄 없음) |
| 소진 adjust_out | ADJ 번호 | `inv_adjust_account(adj)`(1087) · 문턱 넘으면 **보류**(1099) | #59 | 1,082.02 |
| 소진 transfer(보낸 창고 TOR · EDM) | TRF 번호 「depart」 | In Transit #1150040007 | #59 | TRF-00003 · 00005 · 20,633.03 |
| 소진 transfer(IN_TRANSIT → 받는 창고) | TRF 번호 「arrive」 | #59 | #1150040007 | 0(살린 트럭 넷은 **제외** · 1085) |
| 얹기 landed(IMS 비용) | 비용 번호 | #59(IN_TRANSIT 레이어면 #1150040007) | 비용 종류 → #134 · #135 · #136(1089) · 날짜 = IMS 가 얹은 날(507 닫힘) | 0 |
| 소진 cost_late(IMS 비용 · items sale) | items 의 SO 번호 | #58(1084) | #59 | 0 |
| 소진 cost_late(items adjust_out · lost) | ADJ 번호(items 의 doc_number · share) | 그 조정의 계정 `inv_adjust_account()`(1095) | #59 | 0 |
| 소진 cost_moved + 얹기 carried(같은 늦은 원가) | — | 같은 계정 사이면 **줄 없음** · #59 ↔ IN_TRANSIT 사이면 그 둘 | | 0 |
| 얹기 carried(트랜스퍼 복사) | — | **세지 않는다**(트랜스퍼 소진에 이미 들어 있음 · ③) | | 1,008 줄 |
| 레이어 sale_shortfall | SO 번호 | #59 | 재고 조정 기본 #1150040010(1094 · 판매 원가 줄은 그대로) | 1 · 6.33(SO-21090 · 에드먼턴) |
| 레이어 purchase(입고) | RCV · PO | #59 | GINR #1150040012 | **보류**(1096 · 공급처 Bill 차수 1080 에서 연다) · 12,989.53 |
| 얹기 price_adjust · settlement_discount | — | **보류**(공급처 Bill · BillPayment 차수 — 1080 · 1081) | | 0 |
| 얹기 transfer_freight | TRF 번호 | #59 / 받는 레이어가 운송 중이면 #1150040007 | 비용 문서 종류(운임 #136 · 통관 #135 · 관세 #134 · 모르면 #136 · 1100) | 0 |
| 레이어 assembly + 소진 assembly_in | FG/조립 번호 | 같은 창고 #59 ↔ #59 = **줄 없음**(값 차이가 생기면 막음) | | 0 |
| 소진 lost | — | **막음**(뜻 판정 전 · deferred 512) | | 0 |
| opening_fix 가족(adj: → `inv_cost_adjust.kind='opening_fix'`) | — | **보내지 않음**(932 · 1090) | | 13,035.48 · 20,783.50 |
| baseline · Cin7 출처 문서 | — | **보내지 않음** | | |
| 그 밖(제약이 넓어져 새 칸) | — | **장을 막고 알린다** | | |

- 표는 보고 ④-1 그대로 · 「⑤ J」 칸만 판정 번호로 바꿨다(J3 → 1094 · J4 → 1095 · J5 → 1096 · J10 → 1100 · lost → 512) · 조정 두 줄에 1099 · 손님 줄에 1103 을 더함
- ⚠️ **GRNI #1150040011 은 IMS 가 쓰지 않는다**(1096 · 판정 88: 확정 인보이스 없이 입고 불가 · po-disc-2-0 실측 입고 9/9 가 인보이스 뒤) — 잔액 −42,062.28 = Cin7 시절 찌꺼기(503 과 함께) · Bill 차수에서 확인: Off-invoice 「청구로 받음(accepted_billed)」 몫의 짝

**② 경계 = 출처(1090 의 구현 규칙 · 3-2-0 이견 4)** — 「`inv_ledger.source='ims'` 인 문서의 사건 + IMS 비용 문서(charge_number)의 얹기 · 늦은 원가 − 제외 목록(opening_fix 가족 · 살린 트럭 TR-06396 ~ 06399 도착)」 · 원장 문서 번호: IMS = SO-20000 ~ · ADJ- · CR-0100x ~ · RCV- · TRF- · MV- / Cin7 = SO-17xxx ~ 18xxx · ST- · FG- · TR- · PO- · 두 출처에 다 있는 문서는 살린 트럭 넷뿐 · 날짜로 짜면 ① 뒤 날짜로 적은 IMS 사건을 영원히 빠뜨리고 ② 컷 뒤 날짜의 비-IMS 사건(opening_fix)을 못 거른다

**③ 트랜스퍼는 소진 줄로만 센다** — carried 얹기 줄의 `occurred_on` 은 원래 얹힌 날(08-22 ~ 10-27 · 1,008 줄 · 793.93)이라 날짜로 세면 값이 옛 날짜 · 다른 창고로 샌다 · 출발 = 보낸 창고 소진 · 도착 = IN_TRANSIT 소진(occurred_on = 그 이동 날) · 보존 검산: 문서마다 소진 = 자식 바탕 + carried(TRF-00003 11,150.38 = 10,891.38 + 258.99 · 차이 ≤ 0.0001) ⇒ 트랜스퍼는 회사 전체로 값 중립 · 계정 사이로만 옮긴다

**④ 보낸 몫 기억(1092) · 재생성(1093)**
- 표 `qbo_cost_sheet`(realm · 날짜 · 창고 · state · job_id · qbo_id · doc_number · 줄 수 · 차대 합) · `qbo_cost_sent`(sheet · 창고 · 열쇠 종류 · 열쇠 · 차 · 대 · **센트**) — 원가 줄 id 를 담지 않는다 ⇒ 재생성에 견딘다
- 기대값 함수 `qbo_cost_expected(p_until)` → (창고 · 열쇠 · 차 · 대 · 누적 센트) · 다음 장 = 지금 셈 − 보낸 합의 **차액** · 0 은 버림 · 음수면 차대를 뒤집음 · 늦게 적은 과거 사건(TR-06397 꼴 · 11-06 에 적고 occurred_on 11-05) · 다른 날 SO 를 가리키는 늦은 원가 · 크레딧 취소도 같은 규칙으로 다음 장에 그 문서 번호 줄 · 미리 보기에 열쇠마다 「이번 셈 · 보낸 합 · 차액 · 처음 보낸 날」
- 재생성(`inv_layer_apply`)을 하면 하루 장 보내기가 **멈춘다** · 사람이 확인하고 풀면 재생성 차액을 계정 짝당 한 줄 「IMS cost rebuild」 로 묶은 한 장 · SO 별 내역은 IMS 화면 · 평소 작은 차액은 SO 줄
- **재생성 실측**: 컷 뒤 1 번 — 10-31 12:08(토론토 · `supabase/ops/layer-fix-1-regen.sql` · 사람이 psql) · 레이어 22,797 · 소진 78,398 · 얹기 9,859 · `inv_layer_apply` 를 부르는 함수 · cron 0 · 레이어 표를 지우는 함수 = `inv_layer_apply` · `inv_layer_seed_baseline` 둘 · update 하는 함수 0 · 재생성은 id 만이 아니라 **금액도 바꾼다**(FIFO 를 처음부터)

**⑤ 장의 모양(1097 · 1102 · 1103)**
- 장 = 하루 · 창고(TOR · EDM) 하나 · IN_TRANSIT 은 장이 아니라 계정(#1150040007) — 출발은 보낸 창고 장, 도착은 받는 창고 장 · 사건 0 인 날은 장 없음 · 차액만 있는 날은 장을 만든다
- 줄 = 열쇠(SO · CR · ADJ · TRF …)마다 뜻 있는 쪽 한 줄 + 짝 계정은 장마다 계정당 한 줄로 모음(합 = **줄마다 반올림한 값의 합** · 실측 SO 별 반올림 합 − 합 반올림 = ±0.01 · 10 장 중 7) · 줄 설명 = 문서 번호(+ 차액 꼬리) · **손님 이름 글자는 싣지 않음** · 한 장 약 60 줄
- DocNumber `COGS-YYYYMMDD-TOR` · `-EDM`(17 자) · TxnDate = 그날 · **Location(DepartmentRef) 싣지 않음**(1102 · 금액 무영향 — 에드먼턴 원가는 에드먼턴 레이어 원가 그대로 · Location 은 꼬리표뿐)
- SO 원가 줄(#58 쪽) **Entity = 그 인보이스의 QBO 손님(청구처)** · 반품 restock(CR) 줄은 그 크레딧 노트의 손님 · #59 모음 줄에는 안 검 · 손님 번호는 인보이스 보내기의 짝(qbo_link) 그대로(1103 · 번호는 QBO 안에서 이름 변경을 따라간다)

**⑥ 보내기(1098 · 1099 · 1101)**
- 새 스위치 `qbo_send_cost_enabled`(처음 off) · 장 **만들기** = SQL cron 매일 토론토 03:00 쯤 전날 몫 · 처음 몇 주 화면 미리 보기 → 손 Send(971 꼴) · 익숙해지면 자동 · cron 62(결제)와 묶지 않음 · 밀린 장도 같은 미리 보기로
- 창고마다 차례 — 그 창고의 앞 장이 sent 일 때만 다음 장 · failed · unknown 이면 그 창고의 뒤 장 멈춤(안 막으면 보낸 합이 틀려 두 번 보낸다)
- 일감 kind `cost_day` · ims_id `'YYYY-MM-DD|TOR'` · `qbo_txn.qbo_type` 에 JournalEntry · EF `assertWriteAllowed` 에 journalentry **만들기만**(지우기 · void 길 없음 · 374 · 1060 원칙) · QBO 에 같은 장이 두 장 서면 사람이 QBO 에서 하나 지우고 IMS 일감은 skip(사유) · unknown 은 DocNumber 조회로 먼저(1101) → [2026-11-09 · §15-j ⬜5 · §15-k] `qbo_cost_sheet_resolve(in_qbo | not_in_qbo)` · QBO 는 JE DocNumber 중복을 **막지 않는다**(sandbox S2) — 막는 것은 보내기 직전 가드뿐 · 1 행 자동 done 은 Debit 합이 같을 때만(1112)
- 재고 조정 한 건(들어옴 · 나감 절대값 합)이 문턱을 넘으면 「보류」 — 사람이 「보냄 / 안 보냄」 고르기 전에는 안 나감 · 문턱 = inv_config 값(처음 **1,000** · 바꾸기는 마이그레이션 · 572) · write-off 를 가르는 칸은 503 차수(1099)

**⑦ 밀린 장 · 실측 · 콘솔**
- 밀린 장 **12** — 10-31 조정 둘(TOR 240.93 · EDM 80.15) · 11-02 ~ 06 × 두 창고 · 한 장 최대 열쇠 ~~56~~(토론토 11-06) [2026-11-09 정정 · §15-i] 56 은 사건 열쇠 · 보낼 열쇠 **54** + 보류 2(CR-01025 restock + 취소 상계 0 · RCV-00117 · 00121 보류) · 11-07 · 08 사건 0 · 11-02 ~ 06 판매 원가 264 SO · 126,715.43 · 한 SO 가 여러 날 · 창고에 걸친 것 0
- **C1** SO-18513 Cin7 JE 줄 = 차 #58 / 대 #59 · dept 없음 · class 없음 · **Entity Customer** · detail 칸 PostingType · Entity · AccountRef(→ 1102 · 1103) / **C3** Department 1 행 「Edmonton」(active · 인보이스도 안 씀) / **C4** Preferences 조회는 EF 가 거부(400 · 읽기 허용 종류 밖 — 열 필요 없음) → Caleb QBO 화면: **회계연도 시작 9 월 · Close the books 켜짐 · 마감일 2026-08-31**(경고 + 비밀번호로 고치기 허용) ⇒ 10 월 날짜(10-28 · 10-31)로 보낼 수 있다 / **C5** JournalEntry DocNumber `COGS-%` = 0(겹침 없음)
- **월 검산(1086)** 뷰 `qbo_cost_month(월, 창고)`: IMS 재고 금액 움직임(출처 경계 · 트랜스퍼 복사 carried 제외) = 보낸 줄의 #59 · #1150040007 합 + **보류 칸**(입고 · price_adjust · settlement_discount · 문턱 조정) + 제외 칸(opening_fix · 살린 트럭 · Cin7 출처) + 반올림 센트 + 안 보낸 날 · 판매 원가 쪽은 「IMS 판매 원가(sale − restock + reversal + cost_late 판매 몫) = 보낸 #58 합」 · QBO 쪽은 첫 판에 사람이 기간 보고서와 맞댄다 → [2026-11-09 · deferred 533] QBO 쪽 #59 는 **하위 제외** 값으로(GINR · In Transit 이 #59 하위 — 하위 포함 값에는 안 받은 Bill 금액이 섞인다 · In Transit 은 #1150040007 로 따로) · 503(출발점)은 섞지 않는다

**⑧ 짓기 순서** — 3-2 DB(표 둘 · 기대값 · 장 만들기 · claim/done/fail/unknown · 미리 보기 · 월 뷰 · 시험 = 126,715.43 · 장 12 · 열쇠 ~~56~~ → 보낼 54 · 보류 2(§15-i) 재현 · 1 센트 차액 · 모르는 칸 예외 · 살린 트럭 · opening_fix 0 · 약 700 ~ 900 행 짐작) → 3-3 EF + sandbox(JE 몸 검사 · DocNumber 멱등 · unknown 풀기 · 줄 60 · 음수 → 뒤집기 · 같은 DocNumber 두 번 — 줄 상한 · DocNumber 21 자 상한은 짐작 · sandbox 에서 확인) → [2026-11-09 · §15-j · §15-k] 3-2b · 3-3 · 3-4 끝 · sandbox: 19 자 통과 · 같은 DocNumber 두 번 받음(멱등은 IMS 가드) · TotalAmt 0 · 줄 상한 · 21 자는 첫 실물(deferred 525) → 3-4 화면(대화 Claude · Sales → QuickBooks 에 Cost days) → 공급처 · 비용 Bill · 입고(보류 칸 풀기 · 1080 · 1089 · 1096) → BillPayment(1081) → 밀린 것 · 켜기(1083)

### 15-i qbo-sync-3-2a 결과 — 표 셋 · 키 셋 · 함수 15 · 시험 44/44 · 적용 20261108170000 (2026-11-08 밤 짓기 · 11-09 적용 · so-module §106)

- ⚠️ **상태**: **적용 20261108170000 · 확인 44/44(fail 0 · rolled_back_clean t) · 커밋 0228bd0 · cron 미등록(3-2b 때 · cron.sql 은 3-2b 와 함께)** · 스위치 `qbo_send_cost_enabled` off · 장은 아직 하나도 만들지 않았다(첫 장 = 3-2b 적용 때) → [2026-11-09 · §15-j] cron 67 등록 · 장 0(콘솔)
- **원천**: 마이그레이션 `20261108170000_qbo_sync_3_2a_cost_sheet_db.sql`(688 행 · md5 8 `a1f55439` · 머리 주석이 설계 요지) · 시험 `supabase/tests/qbo_sync_3_2a_check.sql`(205 행 · `d0105cc2`) · 지시서 `~/asung/prompts/qbo-sync-3-2.md` · 판정 원문 so-module §104-a · §105-a
- **나눔**: 3-2a = 표 · 키 · 상수 · 기대값(22 칸) · 장 셈(차액) · 장 만들기(장 행만) · 만들기 due(cron 몸) · 미리 보기 · 장 목록 · 보류 결정 · 월 검산 · grant / **3-2b** = `qbo_job` kind `cost_day` · 몸(JE JSON) · claim / done / fail / unknown / retry · 차례(wait_job) · 재생성 hold · release · resolve(1101) / 3-3 EF + sandbox / 3-4 화면(대화 Claude)

**① 만든 것**
- 표 셋(RLS + grant 0 · 창구만 · PK uuid · 거래 표 FK 0 · sent → sheet 만 cascade): `qbo_cost_sheet`(realm · 날 · 창고 TOR | EDM · kind day | rebuild · doc_number `^COGS-[0-9]{8}-(TOR|EDM)(-R)?$` · state · hold_reason · job_id · qbo_id · **epoch** · built_keys · built_lines · built_hold_keys · built_debit_cents · 유니크 (realm, 날, 창고, kind) · (realm, doc_number)) · `qbo_cost_sent`(장 · 창고 · 열쇠 종류 SO · CR · ADJ · TRF · CHG · RCV · CADJ · FG · 열쇠 · 짝 · 센트 — 원가 줄 id 없음) · `qbo_cost_hold`(문턱 조정의 보냄 / 안 보냄)
- inv_config 키 셋: `qbo_send_cost_enabled`(off) · `qbo_cost_adjust_hold_over`(1000 · 1099) · `qbo_cost_since`(2026-10-31 · 날짜 바닥)
- 함수 15: 열 = `qbo_cost_expected` · `qbo_cost_sheet_calc` · `qbo_cost_sheet_build` · `qbo_cost_sheet_build_due`(cron 몸) · `qbo_cost_build_now` · `qbo_cost_preview` · `qbo_cost_sheet_list` · `qbo_cost_hold_decide` · `qbo_cost_hold_list` · `qbo_cost_month` / 상수 넷(이견 14 · inv_config 가 아니라 함수 — 판이 남는다) = `qbo_cost_wh_code` · `qbo_cost_wh_name` · `qbo_cost_excluded_docs` · `qbo_cost_charge_account` / 도우미 하나 = `qbo_cost_layer_wh`
- cron(⬜2): `supabase/ops/cron.sql` 블록 `ims-qbo-cost-build`(`0 8 * * *` UTC · `select public.qbo_cost_sheet_build_due()`) — **등록 안 함**(3-2b 적용 때 · 3-2b 전 장이 규칙과 어긋날 여지 없게) · 보내기 cron 은 3-3 뒤

**② 구현 규칙 — 3-2 이견 답(판정 번호 없음 · 1090 처럼 뜻 무변)**

| # | 규칙 | 자리 |
|---|---|---|
| ⬜1 | 재생성 세대 epoch = `min(inv_layer_consume.id)` 를 장에 적는다(`inv_layer_apply` 가 소진 표를 지우고 다시 넣으므로 반드시 커진다) | 3-2a 적음 · 비교 · hold · release 는 3-2b |
| ⬜2 | 만들기는 cron 만 · 손 등록(`0 8 * * *` UTC) · 밀린 장을 창고마다 차례로 전부 만든다 | 3-2a(몸) · 등록은 3-2b 때 |
| 1 | 3-2a / 3-2b 로 나눈다 | — |
| 2 | 살린 트럭 TR-06396 ~ 06399 은 **문서 전체**(두 다리) 제외 + 날짜 바닥 `qbo_cost_since` 10-31 | 3-2a |
| 3 | 손님 없는 SO 7 개 → needs | 3-2b(claim) |
| 4 | `qbo_cost_sheet_resolve(in_qbo | not_in_qbo)`(1101) | 3-2b |
| 5 | 창고마다 차례 = wait_job | 3-2b |
| 6 | 문턱 조정의 보냄 / 안 보냄 = hold 표(`qbo_cost_hold`) · 입고 · 원가 조정 보류는 결정을 받지 않는다(Bill · BillPayment 차수가 연다) | 3-2a |
| 7 | 열쇠마다 **부호 있는 한 짝**(acct_a < acct_b 코드 순 · 양수 = 차 a / 대 b) — restock(+)과 취소 reversal(−)이 같은 CR 열쇠에서 상계 | 3-2a |
| 8 | 「그 창고 #59 만 장마다 순액 한 줄 · 나머지 계정은 열쇠 줄」(1097 의 구현) | 3-2a(미리 보기 줄 모양) |
| 9 | 앞에 아직 안 보낸 장 P 가 있으면 기대(≤ D) − 기대(≤ P)(만들 때 셈) · 보낸 몫 줄(`qbo_cost_sent`)은 claim 때 | 셈 3-2a · claim 3-2b |
| 10 | 시험은 문턱 100 으로 보류 길을 돈다(시험 H1) · 새 표 PK uuid(시퀀스 없음 · 마이그레이션 머리의 「이견 10」) | 3-2a |
| 11 | 10-31 조정은 들어옴 · 나감 양방향을 함께 센다(시험 E10: TOR adjust_out 240.93 · 레이어 118.11 · EDM 80.15 · 47.37 · 순 EDM −32.79) | 3-2a |
| 12 | 월 검산 = 뷰가 아니라 함수 `qbo_cost_month` | 3-2a |
| 13 | 재생성 장 = kind `rebuild` · ims_id `|rebuild` · DocNumber 꼬리 `-R` | 3-2a(칸 · 제약) · 만들기 3-2b |
| 14 | 상수는 함수(위 넷) | 3-2a |
| 15 | Entity 는 열쇠가 아니다(1103 · 인보이스 손님 = `so_invoice_order.customer_id` · CR = `coalesce(store_customer_id, customer_id)`) | 3-2a |
| 16 | 모르는 칸(제약이 넓어짐) · 창고 모름 · `lost`(512)는 막음 — block 이 하나라도 있으면 그 창고 장을 만들지 않고 예외(문서 번호 · 칸을 글에) | 3-2a |

**③ 실측(시험 44/44 · 두 번 — 두 번째는 mcp-conc-1 160000 적용 뒤 · 확인 44/44 · 시퀀스 무변)**
- 11-02 ~ 06 판매 원가 264 SO · 126,715.43 · 밀린 장 12 · 모두 차대 일치 · EDM 10-31 32.79
- 토론토 11-06 = **보낼 열쇠 54 · 보류 열쇠 2**(시험 B3 원문 「56 = SO 46 + ADJ 4 + CR 4 + RCV 1 + TRF 1 · RCV-00121 은 보류 · CR-01025 는 restock + 취소 상계 0 → 보낼 열쇠 54 · 보류 열쇠 2 = RCV-00117 · 00121 누적」) · 11-02 TOR SO 49 — §15-h ⑦ 의 56 은 사건 열쇠(틀린 셈 아님 · 세는 것이 다르다)
- 기대값 함수 35 s → **0.95 s**(두 번 참조된 CTE 를 materialized) · inv_layer 계열 무접촉(색인도 안 더함 · occurred_on 거르기 seq scan 85k 행 · 호출당 0.1 s 안쪽)

**④ 3-2b 에서 볼 것**
- 손님 없는 SO 7 개의 손님 일감이 `qbo_send_enabled`(off)에 막혀 원가 장이 영원히 못 서는 길(대화 Claude) → [§15-j ⬜6] 기다린다(Caleb) · 손 Send 가 손님 일감을 함께 보낸다
- cron `ims-qbo-cost-build` 등록 · 첫 장 만들기는 3-2b 적용과 함께 · `supabase/ops/cron.sql` 도 그때 커밋 → [§15-j] jobid 67 · `2fbed9d`

### 15-j qbo-sync-3-2b 결과 — 일감 cost_day · 몸 · claim 때 줄 고정 · 차례 · 재생성 hold · resolve · 적용 20261108224000 · cron 67 (2026-11-09 · so-module §107)

- ⚠️ **상태**: **적용 20261108224000 · 확인 60/60(fail 0 · rolled_back_clean t) · 커밋 2fbed9d** · cron **67** `ims-qbo-cost-build`(`0 8 * * *` UTC = 토론토 03:00 · `select public.qbo_cost_sheet_build_due();` · 장 행만 만든다) · 스위치 `qbo_send_cost_enabled` off · **자동 일감 0**(사람 창구 queue 만) · 11-09 콘솔: 장 0 · cost_day 일감 0 · rebuild held []
- **원천**: 마이그레이션 `20261108224000_qbo_sync_3_2b_cost_day_jobs.sql`(984 행 · 새로 쓰거나 바꾼 줄 347 · md5 `82c6c43007392b6215a337f7c53728c4`) · 시험 `supabase/tests/qbo_sync_3_2b_check.sql`(414 행 · `7e204a33eab031d316ec6ab534151d15`) · 회신 원문 `~/asung/prompts/docs-1109c-sources.md` S1 · S2 · S6

**① 만든 것(마이그레이션 차례)**
- ⓪ 가드 → ① `qbo_cost_sheet_ims_id` · `qbo_cost_sheet_id_for_job` → ② 몸 `qbo_cost_day_body`(JE JSON · stable · 「그 창고 #59 순액 한 줄」 · SO · CR 줄 Entity = 1103 · DepartmentRef 없음) → ③ `qbo_cost_sheet_queue_one` · `qbo_cost_sheet_queue` · `qbo_cost_queue_due`(사람 창구 · 날짜 순) → ④ 트리거 `qbo_job_cost_sheet_sync`(qbo_job AFTER UPDATE OF state → 장 state) → ⑤ `qbo_cost_hold_all` · `qbo_cost_rebuild_calc` · `qbo_cost_rebuild_preview` · `qbo_cost_rebuild_release` → ⑥ `qbo_cost_sheet_resolve` → ⑦ 재발행 여섯 → ⑧ CHECK(qbo_job kind **19** · ims_kind + cost_sheet · qbo_txn kind + cost_sheet · type + JournalEntry) · grant
- 재발행 여섯(원본 → 새 md5 8): claim `de6a6fec` → `f108aaa1`(kinds 19 · ② 부모 skipped 도 푼다(cost_day 만) · 재생성 감지 → hold_all + failed · 줄 0 → 장 empty + 일감 skipped · 성공 뒤 `qbo_cost_sent` insert) · done `bfde1f10` → `79674624`(cost_day 가지 · qbo_txn JournalEntry · 응답 금액 ↔ 지문 차변 대조) · retry `004924bc` → `263592d5`(hold · sent · 뒤 장 · skipped rebuild 거부 · skipped day 는 note 필수) · list `d72b4c8e` → `9f357ea4` · preview `07c73ffd` → `edfed63a` · doc `4291e46d` → `ddc7cff5` · fail · skip · unknown · unknown_list 무변
- 본뜬 원본(마지막 정의): claim · done · retry · list · preview · doc = `20261108075221` · fail · skip = `20261102003000` · unknown · unknown_list = `20261102030000` · 열 개 모두 파일 몸 md5 = DB prosrc md5 · ⚠️ `<이름>\(` grep 은 「claim (」 공백 꼴을 못 잡아 `20261107044131` 을 가리킨다 — `\s*\(` 로
- 컷오버: 새 표 0 · 거래 표 FK 0

**② 구현 규칙 — 3-2b ⬜ · 이견 답(판정 번호 없음 · 1090 처럼 뜻 무변)**

| # | 규칙 |
|---|---|
| ⬜1 | 장 하나 = 일감 하나 — kind `cost_day` · ims_kind `cost_sheet` · ims_id `'YYYY-MM-DD\|TOR'`(재생성 장 `'…\|rebuild'`) |
| ⬜2 | 줄 고정 = **claim 때** `qbo_cost_sent` 행(몸 `qbo_cost_day_body` stable) · done 은 다시 셈하지 않고 장 sent + qbo_txn JournalEntry · fail 은 그 행 삭제 · unknown 은 행 유지 |
| ⬜3 | 차례 = 같은 창고 앞 장이 sent · empty · void 가 아니면 wait_job · 앞 장 일감이 없으면 failed 「queue the earlier sheet first」 · skip = 장 void + 보낸 몫 행 삭제 · claim ② 는 cost_day 에 한해 부모 skipped 도 푼다 |
| ⬜4 | 재생성 = claim 때 `min(inv_layer_consume.id)` > 장의 epoch 면 realm 의 미보낸 장 **전부** hold · 일감 failed · `qbo_cost_rebuild_preview` · `qbo_cost_rebuild_release`(TxnDate = 풀어 준 날 · `COGS-<날>-TOR-R`) |
| ⬜5 | `qbo_cost_sheet_resolve(in_qbo \| not_in_qbo)`(1101) — QBO 에 하나 남김 = in_qbo · 하나도 안 남김 = skip(이견 3 의 skip 읽기) · 화면은 in_qbo(JE Id 필수) · not_in_qbo(다시 보냄) |
| ⬜6 | Entity 짝 없음(손님이 QBO 에 없는 SO) = needs → blocked · **Caleb: 그 손님이 QBO 에 만들어질 때까지 기다린다(뒤 장도 차례로) · Entity 없이 보내면 손님별 손익에서 영영 빠진다** · 빠져나오는 길 셋: 손 Send(isNeedKind 가 손님 일감을 함께) · 원가 cron kinds [cost_day, customer](deferred 522) · 그 인보이스가 먼저 나감 |
| ⬜7 | 자동 일감 0 — 사람 창구 `qbo_cost_sheet_queue` · `qbo_cost_queue_due` 만(cron 67 은 장 행만) |
| ⬜8 | 한 파일 |
| 이견 2 | 장 state = qbo_job `AFTER UPDATE OF state` 트리거 하나 · 재발행 여섯 |
| 이견 4 | 줄 0 = 장 empty · 일감 skipped(note 자동) |
| 이견 5 | hold 의 일감 = failed |
| 이견 6 | qbo_txn 제약 셋 넓힘 · 거래 표 FK 0 |
| 이견 7 | 계정 Ref = `qbo_account_ref` · 여덟 계정 짝 8/8 · JE 몸 DepartmentRef 없음(1102) |
| 이견 8 | `supabase/ops/cron.sql` = 3-2a 블록 + 한 줄 |
| 이견 9 · 10 | 시험 10 초(잠금 구간) · 시험 S8 은 가짜 재료 |

**③ 조사 Q1 ~ Q4(3-2b §0 · 운영 메인 · db_role test · max(version) 20261108170000)**
- Q1 장 0 · cost_day 일감 0(kind CHECK 18 종에 없었다) · sent · hold 0 · cron 59 · 61(*/5 active) · 62(*/5 active) · cost-build 미등록 · cfg `qbo_send_enabled` off · `qbo_send_payments_enabled` on · `qbo_send_cost_enabled` off · `qbo_cost_since` 2026-10-31 · hold_over 1000
- Q2 `qbo_cost_sheet_calc('2026-11-02','TOR')` 54 행(0.47 s) = SO 49(SO-20008 ~ SO-20898 · 전부 #58/#59 · 손님 번호 있음) + ADJ 3(ADJ-00011 12282 센트 · 10-31 사건 · baseline none ← 실 DB 에 10-31 장이 없어 셈이 10-31 부터 누적 · ADJ-00015 −1584 · ADJ-00016 1584) + CR 1(CR-01008 −336) + TRF 1(TRF-00003 1115038) · 3-2a 시험 B 는 10-31 장을 먼저 만들어 11-02 TOR 열쇠 53 · je_lines 54 · 늦게 적힌 사건 없음 · 「52」 는 근거 없는 수(정본에 없음 · 정정 없음)
- Q3 손님은 있는데 qbo_link 없는 SO **7**(모두 11-06 · EDM 3 · TOR 4 · 일곱 손님 모두 customer 일감 queued — 11-06 인보이스 claim 의 needs · 인보이스 queued 48 과 함께 북키퍼가 아직 안 고름) · entity_customer_id null 인 EDM SO 102 는 opening_fix 로 excluded(무관)
- Q4 claim kinds: EF `send()` → `kindsOf(body.kinds)` → 없으면 (3-3 전) SEND_KINDS 18 · `qbo_job_claim` 에 p_kinds 를 늘 넘긴다 · sendPicked 도 고정 · cron 61 command 에 kinds 없음 · cron 62 kinds 열둘 + where 도 열둘 ⇒ 둘 다 cost_day 를 못 집는다 → 3-3 에서 DEFAULT_SEND_KINDS(§15-k)

**④ 시험 · 적용 실측**
- 시험 5 회차: 1 S8 done 「queued 는 못 끝낸다」(시험 결함) · 2 50/57(S1e · S3h · S8a · S8c 「done 이 자식을 푼다」 · S5b 괄호 · G1 · G4) · 3 54/60(EDM 01-07 일감이 S5 hold 에 realm 전체로 — 설계대로) · 4 60/60 · 5 EXPECT_OK 60 · 마이그레이션 본문은 1 회차 뒤 무변 · begin ~ rollback 22.1 s(그중 `\i` 38 문장 × 왕복 ≈ 0.3 s ≈ 13.3 s · 적용 뒤 ~ rollback 8.8 s · 표 잠금은 파일 끝에서 시작 · 잠금 ≈ 10 s)
- 3-2a 적용 뒤 콘솔 `qbo_cost_preview('2026-11-02','TOR')`: balanced true · sheet null · keys 54 · je_lines 55 · 차 = 대 1519323 센트 · epoch_now 11642829
- 적용(Caleb · 11-09): applied 0 · last 170000 → APPLY_OK → repair applied → 확인 60 · 0 · 60 · 60 · t · ⚠️ 확인 갈래는 **cron 등록 전에**(시험 S5 절의 hold_all 이 realm 의 pending 장을 스친다)
- cron 67 등록: 첫 가드 `select case when exists(…) then (1/0)::text else 'new' end` 가 잡이 없는데도 division by zero — 상수 1/0 은 계획 단계에서 셈한다(PostgreSQL 문서 §9.18.1 · §4.2.14 · so-module §107-e 128) → DO 블록 가드로 고쳐 등록 · jobid 67 · active t
- REST 둘째 겹(콘솔): `qbo_job_list(cost_day)` rows [] · counts sent 493 · failed 1 · queued 58 · blocked 57 · skipped 15 / `qbo_cost_sheet_list` rows [] · since 2026-10-31 · send_enabled off / `qbo_cost_rebuild_preview` held []

### 15-k qbo-sync-3-3 · 3-4 결과 — EF cost_day = JournalEntry · sandbox 실측 · 판정 1112 · 화면 Cost days · 첫 실물 순서 (2026-11-09 · so-module §107)

- ⚠️ **상태**: 커밋 `232dec7` · EF `qbo` **배포 11-09**(Target Asung-IMS production · 올라간 파일 `index.ts` · `_shared/qbo.ts`) · 배포 뒤 cron 62 00:35 UTC succeeded 「0 rows」 · Settings Check connection → Connected · **원가 보내기 cron 미등록**(cron.sql 주석 블록만 · deferred 522) · 장 0 · 보낸 장 0(첫 실물 = deferred 525)
- **원천**: `_shared/qbo.ts`(1514 행 · md5 `313847a28f31c9f6d381d9dc2499759f`) · `qbo/qbo_test.ts`(2836 · `e9552f566bcf6b9f72199ebbf1a43a56`) · `qbo/index.ts`(71 · `a63056981dab00f3062c56e68e912ad4`) · `supabase/ops/cron.sql`(1045 · `74aac8c6deea7f7f23d5f1afa583d814`) · diff 4 files 289+ 16− · 회신 원문 S3 · S4 · S5

**① sandbox 실측(11-09 · Caleb · Intuit API Explorer · Sandbox Company CA · 대화 Claude 안내)**
- 계정 Cost of Goods Sold Id 84 · Inventory Asset Id 85 · 손님 Id 61
- S1 POST journalentry `{DocNumber "COGS-20261102-TOR-R"(19 자) · TxnDate "2026-11-02" · Line[ Debit 12.34 · Description "SO-20008" · AccountRef 84 · Entity{Type Customer · EntityRef 61} / Credit 12.34 · AccountRef 85 ]}` → Id 197 · SyncToken "0" · DocNumber 그대로 · Entity 그대로(응답에 EntityRef.name) · TxnTaxDetail {} · CurrencyRef CAD · ExchangeRate 1 · ⚠️ **TotalAmt 0 · HomeTotalAmt 0**
- S2 같은 DocNumber 다시 → Id 198 — ⚠️ **QBO 는 JournalEntry DocNumber 중복을 막지 않는다** ⇒ 중복을 막는 것은 IMS 의 보내기 직전 가드뿐
- S3 `select Id, DocNumber, … from JournalEntry where DocNumber = 'COGS-20261102-TOR-R'` → totalCount 2(198 · 197) · 고른 칸에 없는 **Line 이 따라온다**(Entity name 포함)

**② EF `_shared/qbo.ts`(3-3 ⬜ · 이견 답 · 판정 1112)**
- `SEND_KINDS` **19** · `DEFAULT_SEND_KINDS` **18**(kinds 없음 = cost_day 뺌 ⇒ cron 61 은 원가 장을 못 집는다) · sendPicked(손 Send) `p_kinds [...SEND_KINDS]` 19 · `COST_DAY_KINDS` · `COST_DAY_DOC_RE`
- `WRITE_ENTITIES` + journalentry · `assertWriteAllowed`: journalentry 는 **만들기만**(지우기 · void 길 없음 · 1101) · operation 없는 몸에 Id 가 있으면 거부(purchase 에 이어 둘째 · deferred 501 범위 좁아짐)
- `entityKeyOf` cost_day 명시(journalentry / JournalEntry / DocNumber) · `isTxnKind` 에 넣지 않음 · `txnWord` 「journal entry」
- **가드**: 보내기 직전 DocNumber 조회 — 0 행 → POST · 조회 실패 → failed · 1 행 이상 → **unknown**(`qbo_job_unknown` · 글에서 「then Retry」 뺌) — 지시서 안 「failed」 는 failed 가 트리거로 보낸 몫 행을 지워 resolve 길이 닫혀 바꿈(3-3 이견 1)
- **done**: `p_total_amt` = 응답 TotalAmt(JE 는 0 · S1) 대신 **Debit 줄 합**(`journalDebitCents` · DB 무변) · 2xx 에 Line 이 없으면 null → mismatch 경고 + sent · 응답 TotalAmt 를 넘기는 cost_day 줄 0(grep)
- **unknown 열쇠**: `qbo_name` = `<DocNumber>|<차변 센트>`(`costDayKeyOf` · 결제 paymentKeyOf 선례 · EF 만) · qbo_name null(stale sending → unknown)이면 ims_id 로 DocNumber(`costDayDocOfImsId`) · 센트 없음 → 자동 없음(사람 resolve)
- **풀기(`resolveUnknown` cost_day · 1112)**: 0 행 not_found · 1 행 → `GET journalentry/<Id>` 로 Line → **Debit 합 = 열쇠 센트일 때만 done** · 다르면 unknown 그대로 + 글 「… has debits X but this cost day expects Y — not recorded …」 · 2 행 이상 ambiguous(1101)
- 순수 함수 다섯 `journalDebitCents` · `fingerprintDebitCents` · `costDayKeyOf` · `parseCostDayKey` · `costDayDocOfImsId` · `doneJournal` · `sendOne` cost_day · `kindsOf` 기본 = DEFAULT
- grep 근거(회신): journalentry 닿는 줄 92 · 298 · 614 · DEFAULT_SEND_KINDS 103 · 1187 · sendPicked 1234
- 사실(막지 않음): 풀기는 kind 를 안 가려 **cron 62 가 cost_day unknown 도 조회** · 금액 같으면 done(쓰기 0 · 적기만) · cron 61 WHERE 는 kind 를 안 거른다(deferred 520 · `qbo_send_enabled` off 유지 — Caleb 11-08 「인보이스 자동 켜기는 당분간 안할 예정이야」) · unknown 동안 화면에 `COGS-…|센트` 꼴(깨끗한 판 = unknown_list fingerprint · deferred 521)
- 3-3 ⬜(받음): 1 SEND 19 · DEFAULT 18 · sendPicked 19 / 2 entityKeyOf · WRITE_ENTITIES / 3 (가) Debit 합 / 4 가드 0 · 실패 · 1+ / 5 풀기 0 · 1 · 2+ / 6 needs 코드로 확인 · 그대로 됨 / 7 원가 cron 등록 안 함 · 주석 블록 / 8 줄 상한 · 21 자는 첫 실물로
- 시험: deno `28 passed | 0 failed`(355 ms · 기준선 27 → ㉗ 하나) · deno check 통과 · 회차 넷(옛 단언 18 → 19 · await 빠짐 · T3(f) Line [] 재료 · 가짜 JE Id 충돌 → 10001 ~ — 전부 시험 재료 · EF 무변) · 바뀐 옛 단언 줄 1379 · 1709 · 1722 · 1815 · 1842 · 2169 · 2394 ~ 2395 · 가짜 Intuit JournalEntry 장부(it.journals)
- `supabase/ops/cron.sql`: 67 블록 아래 「등록 전 · 판」 주석 블록 `ims-qbo-cost-send`(kinds [cost_day, customer] · ⚠️ customer 는 큐의 **모든** customer 일감을 보낸다 — 등록 때 Caleb · 522)

**③ 화면 — 3-4(asung-ims · 대화 Claude)**
- `a0693ee` qs cost v1 · set v17b: Sales → QuickBooks 종류 「Cost of goods — daily journal」 · Cost days 카드 — 장 목록(Date · Warehouse · Number · Status · Keys · Lines · Debits · QuickBooks · Note) · 장 미리 보기(By document · Held back on this day · Left out on purpose) · **Queue**(그 창고 첫 built 장에만) · Queue all ready sheets · Build sheets now · Held back(문턱 조정 Send / Never / Undo · 입고 · 공급처 원가는 Bill 차수) · 「Cost days are on hold」 → Review the rebuild → Release(메모 필수) · unknown 장 Resolve(in_qbo + JE Id | not_in_qbo) · 일감 미리 보기에 JournalEntry 줄(차 · 대 · 계정 · 손님) · Settings → QuickBooks 안내 글 둘(보내는 것 · 승인 기한은 갱신으로 밀린다)
- `65244a8` qs cost v1a: Cost days 칸을 목록 카드 안 거르기 줄 바로 아래로(Caleb 「이 상태에서는 다른 것을 선택할 옵션이 안보이네」 → 「이제는 잘 보여」) · 동작 무변
- 보류 칸 실물: RCV-00117 −950.00 · RCV-00121 −12,039.53(acct_a = GINR 기준 부호라 음수 · 방향 글 deferred 523) · 셈은 맞다(least/greatest · 3-2a 388 ~ 389 행 · 4-0 보고 C-1 — 523 은 표시만)
- 매뉴얼: 01-sales `sales-quickbooks-cost`(en · ko)

**④ 첫 실물 순서(deferred 525)**
- 장 만들기 = cron 67(토론토 03:00 · 전날까지) 또는 Build sheets now
- 창고마다 **10-31 부터 차례로**: Queue(또는 Queue all ready sheets) → 목록의 Cost day 줄 Preview → Send · 앞 장이 sent · empty · void 가 아니면 뒤 장은 기다린다 → [2026-11-09 · 판정 1120 · §15-l] **TOR 은 11-04 까지만** 먼저 — 11-05 · 11-06 TOR 장에 입고 보류(RCV-00117 · RCV-00121)가 걸려 4-3 이 서서 보류가 풀린 뒤 · EDM 은 차례대로 다 · 4-3 은 11 월 안(늦으면 「푸는 날 장」 으로 바꾸는 길)
- 볼 것: QBO JE 줄 상한(한 장 약 60 줄 · sandbox 미확인) · DocNumber 21 자(`-R` 19 자는 통과) · done 의 Debit 합 · Entity · 손님 짝 없는 SO 7 이 든 11-06 장(손 Send 가 손님을 먼저 만든다)
- 그 뒤 원가 보내기 cron(522) · 그 다음 **공급처 쪽**(qbo-sync-4-0 조사부터 · 1080 · 1081 · 1089 · 1096 · Caleb 11-08 저녁 「공급처 쪽을 우선 작업을 시작하자」)

### 15-l 공급처 Bill · VendorCredit · BillPayment — 판정 · 실측 (2026-11-09 · qbo-sync-4-0 조사 · 4-1 운영 콘솔 · 4-2a sandbox · 판정 1115 ~ 1130 · so-module §108 · 짓기 전)

- **상태**: 판정 끝 · **짓기 전** — 공급처 쪽 QBO 쓰기 코드 0 · 운영 QBO 쓰기 0(4-1 은 GET 만) · sandbox 쓰기만(4-2a) → [2026-11-09 오후] 지음 · 운영 Bill 7 장 sent(§15-m)
- **원천**: 조사 보고 `~/asung/scratch/qbo-sync-4-0-report.md`(레포 밖 · 371 행 · md5 8 `b37c9369` · ⚠️ 판정 **전** 안 — 판정이 다른 곳은 so-module §108-a 가 맞다) + 4-1 운영 콘솔(Settings 콘솔 · EF query · GET 만 · Caleb 실행 · 대화 Claude 판독) + 4-2a Canada sandbox(Caleb API Explorer) · 판정 원문 표는 so-module **§108-a** 가 정본(이 절은 요지)
- ⚠️ 공개 레포 — 공급처 · 손님 상호 · 사람 이름은 적지 않는다 · QBO Id · 문서 번호 · 계정 번호 · 금액은 적는다

**① 판정 요지 (1115 ~ 1130 · 원문 so-module §108-a)**

| 판정 | 요지 |
|---|---|
| 1115 | Bill · VendorCredit · BillPayment 는 #59 · #58 무접촉 — Bill = 차 GINR `_1150040012_` / 대 A/P · 재고 · 판매 원가는 하루 원가 장만 |
| 1116 | Bill 줄 = IMS 인보이스 줄마다(설명 SKU · 수량 · 단가) |
| 1117 | 인보이스 할인 = 음수 줄 따로(계정 GINR) |
| 1118 | USD Bill 환율 = `po_invoice.exchange_rate` 를 박는다(940 과 반대) · 비면 막음 |
| 1119 | 입고 보류(1096)는 공급처 차수가 서면 **무조건** 푼다 |
| 1120 | 풀린 입고는 **입고 날짜 장**에 — TOR 원가 장은 11-04 까지만 먼저 · 11-05 부터는 4-3 뒤 · EDM 은 다 · 4-3 은 **11 월 안**(늦으면 「푸는 날 장」) |
| 1121 | 할인 · 가격 크레딧 = VendorCredit(차 A/P / 대 GINR) + 원가 장 CADJ(차 GINR / 대 #59 · #58) · not_received 크레딧은 VC 만 · 「할인」 = 둘 다(판정 때 함께 정함) — 조기 결제 할인(`po_payment.discount_taken` → settlement_discount) · 가격 크레딧(po_invoice doc_kind credit · credit_reason price_difference → price_adjust) · 걸리는 차수: 가격 크레딧 = 4-3(VendorCredit 문서) · 조기 결제 할인 = 4-5(결제 저장 때 VendorCredit + BillPayment 에 붙임) |
| 1122 | USD 은행 계좌 `ref_account.currency_code` 채움 · 결제 통화 ≠ 계좌 통화면 거부 |
| 1123 | USD 결제 환율 = 그 돈을 산 날의 MTFX 환율(필수) · 결제 날짜 = 실제 보낸 날 · 저장된 USD 결제 3 건은 보내기 전에 채움 · 전제(짐작): 매주 USD 사기는 북키퍼가 QBO 에 따로 |
| 1124 | 결제 하나 = 공급처 하나 · 섞이면 거부 |
| 1125 | IMS 결제 삭제 → BillPayment void 일감(E-13 이 안 되면 다시) |
| 1126 | IMS 인보이스 취소 → 일감 「QuickBooks 에서 손으로 지워 주세요」 → 북키퍼 삭제 → Skip · **API delete 안 씀** · 복원 = 새 Bill |
| 1127 | unknown Bill 자동 done = 같은 Vendor + DocNumber + 합계(Bill 통화 센트) **한 장**일 때만 |
| 1128 | QBO 에 없는 공급처는 IMS 가 Vendor 를 만든다(DisplayName + CurrencyRef 만 · A/P 안 실음 · 같은 이름 있으면 failed · 자동 개명 없음) |
| 1129 | 비용 문서 Bill 은 **확정 때**(배분과 무관) · 차 #134 · #135 · #136 / 대 A/P |
| 1130 | 공급처 인보이스 번호 > 21 자면 DocNumber 앞 21 자 · 전체는 PrivateNote |

**② 4-1 운영 QBO 콘솔 실측 (2026-11-09 토론토 03:5x ~ 04:3x · Settings 콘솔 · EF query · GET 만)**

| # | 본 것 | 결과 |
|---|---|---|
| R1 | 열린 Bill(Balance > 0) | CAD 18 장 39,406.42 · USD 6 장 72,190.36 · 공급처 20 곳 · 가장 오래된 2026-09-01 — 모두 Cin7 이 컷 전에 보낸 Bill(IMS 인보이스는 QBO 에 없다 · M2) · 913 대로 북키퍼 몫 |
| R2 | BillPayment | 전체 5,722 · TxnDate ≥ 11-01 = **17 장** · IMS 결제 4 건(1,073.50 · 14,555.10 · 33,366.24 · 24,960.00)과 같은 금액 **0** · USD 셋(20,310.48 · 10,640.10 · 43,517.84)은 M4 그대로 · 운임 공급처 Vendor 3563 에 11-06 Check 929.73(IMS draft 운임 2 장과 금액 다름 · 컷 전 Bill 결제로 짐작) · ⚠️ EF query: `PayType` 은 BillPayment 의 고를 수 있는 칸이 아니다(4001 「Property PayType not found」) — `select *` 로는 온다 |
| R3 | Vendor 열 곳(7170 · 5835 · 108 · 7640 · 3646 · 7204 · 315 · 3563 · 6078 · 409) | 통화 USD 7 · CAD 3 = IMS 와 같다 · APAccountRef 모두 없음(기본) · 모두 활성 |
| R4 | 계좌 | 104 TD CAD CHEQUING CAD · 106 BMO USD CHEQUING **USD** · 122 MTFX CAD CAD · 138 MTFX USD **USD** · 132 BMO Mastercard 1552 CAD(Credit Card) ⇒ **「QBO 수표 #138」 = 계좌 Id 138 MTFX USD(수표 번호 아님) — 확정** · 「MTFX」 = 환전 업체 계좌 이름 · IMS 는 `_106_` · `_138_` 통화 null(= CAD 뜻) → 1122 |

**③ 4-2a sandbox 실측 (Canada sandbox realm 9341458557490536 · 2026-11-09 01:16 ~ 01:37 PST · Caleb API Explorer)**

- Preferences: MultiCurrencyEnabled true · HomeCurrency CAD · `WarnDuplicateBillNumber` false(sandbox — 운영 값은 안 봤다)
- sandbox 번호(운영과 다르다): CAD A/P 31 · USD A/P 없음 → 첫 USD Bill 때 QBO 가 97 「Accounts Payable (A/P) - USD」 를 **스스로 만들었다** · 자산 16 Prepaid(GINR 대역) · 세금 코드 Zero-rated 3 · Out of Scope 6 · HST ON 5(매입 세율 11) · Exempt 2 · GST 단독 코드 없음
- 만든 것: Vendor 69(USD) · 70(CAD) · Bill 199(E-1) · 200(E-2) · 201(E-4 100 줄) · 202(E-4 250 줄) · 203(E-5 같은 번호) · 204(E-6 21 자) · 205(E-15)

| # | 시험 | 결과 ⇒ 짓기 규칙 |
|---|---|---|
| E-1 | USD Bill `ExchangeRate 1.4` | 그대로 · Balance 100 · HomeBalance 140 · 응답에 HomeTotalAmt 없음(HomeBalance 만) ⇒ done 대조는 USD TotalAmt(1127) · ⇒ Bill 마다 **`APAccountRef`(공급처 A/P 코드 · USD 면 운영 #109) 반드시** — 안 실으면 QBO 가 제 기본 USD A/P 를 고른다 |
| E-2 | 음수 줄 | −0.50 받음(TotalAmt 99.5 · HomeBalance 139.3) → 1117 |
| E-3 | 반올림 | HomeBalance = **합계 × 환율**(100 줄 × 0.33 × 1.4 = 46.2 · 줄마다 반올림이면 46.00) ⇒ IMS 입고 원가(줄마다 반올림 · 예 RCV-00121 12,039.53)와 Bill(8,599.66 × 1.4 = 12,039.52)이 **센트 단위로** 다를 수 있다 → GINR 센트 찌꺼기는 정상(북키퍼 안내 4-6) |
| E-4 | 줄 수 | 100 줄 · 250 줄 모두 받음 → 1116 |
| E-5 | 같은 Vendor 같은 DocNumber | 또 선다(203) ⇒ 보내기 직전 가드 필수 · 조회 `select Id, DocNumber, TotalAmt, VendorRef from Bill where DocNumber = '…' and VendorRef = '…'`(두 장 다 잡힘 · 1127) |
| — | DueDate | 몸에서 빼면 QBO 가 TxnDate 로 채운다 ⇒ **`DueDate`(po_invoice.due_date) 반드시** |
| E-6 | DocNumber 길이 | 최대 21 자(25 자 → 2050 「Max:21」) · `#` · 쉼표 · 공백은 그대로 → 1130 |
| E-7 | Bill void | Intuit 문서의 Bill 작업 = Create · Delete · Query · Read · Full update — void 없음 → 1126 |
| E-14 | (시험 안 함) | 운영에 그 꼴 Bill 이 이미 있다(M10 · #125 한 줄 · 세금 코드 4) |
| E-15 | `TxnTaxDetail` 11.69(셈하면 11.70) | **11.69 그대로**(Bill 205 · TotalAmt 101.69) ⇒ QBO 는 보낸 세금을 존중 · Bill 마다 IMS 세금을 싣는다 · 다시 셈해 잡아 주지 않으니 IMS 세금이 맞아야 한다 |

- 남은 sandbox = **4-2b**(4-5 결제 차수 앞 · → [2026-11-09 · §15-m ⑥] 함 — E-9 · E-11 · E-12 · E-13 · E-10 안 함 · E-8 미룸): E-8 VendorCredit + BillPayment 에 붙이기 · E-9 BillPayment Check · USD 계좌 · 다른 환율 → 환차손익 줄 · E-10 USD 결제를 CAD 계좌로 · E-11 CreditCard · E-12 부분 결제 · Bill 둘 · E-13 BillPayment void

**④ 4-0 조사 결론 (보고 `b37c9369` 에서 판정 뒤에도 그대로 선 것)**

- 공급처 크레딧 = `po_invoice.doc_kind='credit'`(별도 표 없음) · 지금 0 장
- 컷 전 생성 0(po_invoice · po_charge · po_payment 모두) ⇒ 「IMS 결제가 컷 전 Bill 에 붙어 두 번」 은 구조상 불가 · **deferred 428 닫힘**(913 + 1081 + 이 실측)
- 공급처 10 곳(인보이스 7 + 비용 3) 모두 qbo_link supplier → Vendor 있음 · 짝 없는 활성 공급처 46
- 보류 칸 부호(RCV 음수) = GINR 기준 부호 · 셈은 맞다(least/greatest · 3-2a 388 ~ 389 행) · deferred 523 이 그 할 일(§15-k ③ 보류 칸 실물 줄)
- ⚠️ 이름 충돌: ims_kind `invoice · credit · payment · charge` 는 SO 쪽이 쓴다(`qbo_link.ims_kind 'charge'` 6 행 = SO 부대 Item) → 공급처는 다른 이름(4-3 이 정한다 · 안: kind `bill · bill_void · vendor_credit · vendor_credit_void · bill_payment · bill_payment_void` · ims_kind `po_invoice · po_charge · po_payment`) → [실제 · 4-3a · 4-5a] kind `vendor · bill · vendor_credit · bill_delete_manual`(Bill 에 void 가 없어 bill_void · vendor_credit_void 는 없다 · 1126) · `bill_payment · bill_payment_void` · ims_kind `supplier · po_invoice · po_credit · po_charge · po_payment`(§15-m ② · §15-n)
- ⚠️ `DEFAULT_SEND_KINDS = SEND_KINDS − cost_day`(qbo.ts 103) — 새 kind 를 SEND_KINDS 에 넣으면 cron 61 기본에 저절로 들어간다 ⇒ 공급처 kind 도 DEFAULT 에서 뺀다(cost_day 꼴)
- ⚠️ `entityKeyOf` ELSE = invoice · `qbo_job_pair_ck` ELSE = ims_kind — 새 kind 는 명시 가지 필수
- 화면: Sales → QuickBooks 와 같은 화면에 「Supplier bills」 · 「Supplier payments」 종류(4-0 안 · 화면 차수 때 대화 Claude 가 정한다) → [2026-11-09 밤] 같은 화면 qbo-send.html 의 종류 「Supplier bills and credits」 · 「Supplier payments」(qs sup v1 · v2) · 메뉴 길은 **Integrations › QuickBooks**(판정 1136 · nav v16) · §15-n

**⑤ 차수 계획 (Caleb 「좋아」 · 11-09)**

4-0 조사(끝) → 4-1 콘솔(끝) → 4-2a sandbox(끝) → **4-3 DB Bill · VendorCredit**(일감 kind · 몸 함수 · 확정/취소/복원 트리거 · 입고 보류 풀기 · 은행 계좌 통화 막기 · Vendor 몸 · **11 월 안** · 1120) → 4-4 EF Bill · VendorCredit + 화면 + 첫 실물 손 Send(Bill 7 장 · 원가 장 RCV 두 줄 · 비용 Bill) → 4-2b sandbox → 4-5 결제 DB + EF + 화면 → 4-6 켜기 · 북키퍼 안내 · 정본

- 4-3 에서 볼 것(so-module §108-d′): accepted_billed 짝(1096 이 남김) · ~~1121 「할인」 의 뜻~~(정함 — 가격 크레딧 4-3 · 조기 결제 할인 4-5) · USD 은행 계좌 수 · KRW 기본 A/P 키 · 저장된 USD 결제 3 건 환율(4-5)

**⑥ 하루 원가 장 상태 · 북키퍼 안내 거리 (11-09)**

- cron 67 첫 실행 11-09 03:00 토론토 succeeded(22 s) · 장 12 built(10-31 · 11-02 ~ 11-06 · 두 창고) · **보낸 장 0**(→ [11-09 오후 · §15-m ⑤] 12 장 sent) · 10-31 TOR = ADJ-00011 한 줄 122.82(차 #1150040010 / 대 #59) · 11-02 TOR = 문서 53 + #59 한 줄 = 줄 54(화면 목록 KEYS 53 · LINES 53)
- 첫 실물(525): **TOR 은 11-04 까지 · EDM 은 다**(1120) · 원가 보내기 cron(522)은 4-3 뒤
- 곁가지 deferred 528 ~ 533(DEBITS 칸 · built 시각 · 원가 0.01 ~ 0.06 SO 줄 · Vendor 거울 detail · PO-02009 RCV-00082 draft · 월 검산 #59 하위 제외)
- **북키퍼 안내**(4-6): ① IMS 가 보낸 Bill 의 결제는 **IMS 에서** 적는다 — QBO 에서 직접 결제하면 IMS 는 미지급으로 남는다(1081 · Vendor 3563 사례) ② GINR 센트 찌꺼기는 정상(E-3) ③ 취소된 Bill 은 QBO 에서 손으로 지우고 Skip(1126)

### 15-m 4-3 · 4-4 · 3-3b · 운영 첫 송신 · 4-2b — 공급처 Bill · VendorCredit 이 나간다 (2026-11-09 · asung-wms `32f2f3e` · `b879381` · `f1fb21b` · 판정 1131 · so-module §109)

- **상태**: 공급처 Bill · VendorCredit **운영에서 보냄**(Bill 7 장 sent · VendorCredit 0 · 비용 Bill 0 — 모두 draft) · 하루 원가 장 **12 장 sent** · 공급처 결제(BillPayment)는 4-5 전(→ [11-09 밤] 4-5 끝 · 첫 173092 sent · §15-n) · 자동 보내기 없음 — **매일 원가 장 · 새 공급처 Bill 은 북키퍼가 Queue/Preview → Send**(Caleb 「ㄱ」 · 자동은 나중에 Caleb · deferred 522) · 북키퍼 안내서(Claude Doc)는 고쳤고 전달은 Caleb 이 직접
- **원천**: 지시서 docs-1109e(대화 · 운영 미리 보기 응답 · QBO 화면 · sandbox API Explorer 실측) · 커밋 글 원문 · 판정 원문 표는 so-module **§109-a**
- ⚠️ 공개 레포 — 공급처 · 손님 상호 · 사람 이름은 적지 않는다

**① 판정 1131 요지**: 공급처 인보이스에 지급 기한이 비면 Bill `DueDate` = 인보이스 날짜 + 경고(DB 몸 `qbo_bill_body` · 4-3a) · 「확정 때 지급 기한 필수」 는 다음 차수(deferred 536) · 기한이 빈 Bill 은 QBO A/P 기한표에 연체로 보인다 → 북키퍼가 QBO 에서 손봄(IMS 는 보낸 Bill 을 고치지 않는다) · 공급처 결제 조건에 QBO 짝이 있으면 `SalesTermRef` 가 함께 간다(AST261028 → 「Due on Receipt」 · 실제 조건인지는 짐작 · deferred 537)

**② 4-3a · 4-3b DB (`32f2f3e`)**

| | 4-3a `20261109103000` | 4-3b `20261109104000` |
|---|---|---|
| 적용 (토론토) | 11-09 06:02 | 06:11 |
| 확인 | 56/56 | 16/16 — F1 확인 갈래 기대값 「기준 + 6」 → 「+ 0」 결함 · 검사 파일만 고침(md5 8 `4bca3e25`) |
| 무엇 | kind vendor · bill · vendor_credit · bill_delete_manual(합 23) · ims_kind supplier · po_invoice · po_credit · po_charge(14) · 몸 넷(`qbo_vendor_body` · `qbo_bill_body` · `qbo_vendor_credit_body` · `qbo_charge_bill_body`) · 트리거 `qbo_job_on_po_doc_status`(확정 · 복원 · 취소 · 다시 열기 · 1126) · 재발행 여덟 · `qbo_txn` Bill · VendorCredit | `qbo_cost_expected` 재발행(RCV 보류 풀기 · 날짜 = 입고일 · CADJ 대 GINR · price_adjust send · settlement_discount hold) · `ref_account` USD 여섯 · 트리거 `po_payment_account_currency_ck`(1122) |
| 백필 | bill 일감 7(USD 6 · CAD HST 1) · vendor_credit 0 · charge 0 | — |

- **USD 계좌 여섯**(운영 QBO R5 · 11-09 모두 USD 확인): `_106_` BMO USD CHEQUING · `_138_` MTFX USD · `_141_` TD USD CHEQUING · `_144_` BMO USD Mastercard(Credit Card) · `_145_` Cash on hand_USD · `_204_` WISE USD — ⚠️ 이 밖의 USD 계좌는 안 봤다 · 빠졌으면 IMS 가 CAD 로 알고 **막는 쪽**으로 틀린다(USD 결제 저장 거부)
- 적용 중 사고(장부 무관): 출장지 네트워크로 psql 이 DNS · 연결 단계에서 멈춤 → 적용 0 인 채 창 닫음 → 연결 10 초 제한 스크립트 파일로 다시(so-module §109-e 143 · 144)
- 4-3 이 답하지 않은 것: accepted_billed 짝(1096) · KRW 기본 A/P 키(1128) — 두 마이그레이션 grep 0

**③ 4-4 EF (`b879381` · 배포 v22 2026-11-09 13:05 UTC · deno 29/29)**

- SEND_KINDS 22 · DEFAULT 18 그대로(공급처 셋은 DEFAULT 에서 뺌 — cron 61 에 안 섞인다) · `bill_delete_manual` 은 EF 가 집지 않음(사람이 QBO 에서 지우고 Skip · 1126) · `entityKeyOf` 명시 가지 · CREATE_ONLY
- 가드 조회 `select Id, DocNumber, SyncToken, TotalAmt, VendorRef from Bill|VendorCredit where DocNumber = … and VendorRef = …`(`billGuardQueryText`) · 1127 센트 같을 때만 done · PULL_FIELDS TaxCode `PurchaseTaxRateList`
- 배포 뒤 Settings → QuickBooks matching → **Refresh list(tax codes)** → HST CAD 인보이스(Order #8884650) 몸이 풀림: 줄 `TaxCodeRef 6` · `TxnTaxDetail TaxRateRef 11 · 13 % · 123.50`(운영 미리 보기 응답 실측) ⇒ 매입 세율이 거울에 없으면 몸이 막힌다 — 새 세금 코드 뒤엔 Refresh list 먼저
- 미리 보기 응답 실측(AST261028): 14 줄 모두 GINR `1150040012` · 세금 코드 2 · `ExchangeRate 1.397` · `APAccountRef 109` · `VendorRef 7170` · `TxnTaxDetail {TotalTax 0}`(TaxLine 없음) · `SalesTermRef 1` · 합 33,366.24 — **TaxLine 없는 TotalTax 0 꼴을 운영 QBO 가 받았다**

**④ 3-3b EF (`f1fb21b` · 배포 v23 2026-11-09 20:58 UTC · deno 30/30)**

| | |
|---|---|
| 증상 | 첫 cost_day 손 Send(COGS-20261031-TOR) failed 「Property TotalAmt not found for Entity JournalEntry」(4001) — 보내기 전 가드에서 멈춤 · **QBO 쓰기 0** |
| 고침 | JournalEntry 가드 조회 = `select Id, DocNumber`(TotalAmt · SyncToken 뺌 · `docNumberQueryText`) · 금액 대조는 원래부터 GET 의 Line 차변 합(무변) · `QUERY_UNSELECTABLE` 표 신설(`qbo.ts` 752 · 지금 JournalEntry TotalAmt · BillPayment PayType) |
| 뒤 | Retry(메모 「EF fix v23 …」) → sent |

**⑤ 운영 첫 송신 (2026-11-09 토론토 오후 · Caleb 손 Send)**

| 무엇 | 결과 |
|---|---|
| 공급처 Bill 7 장 | **모두 sent** — AST261028(QBO txnId 173045 · USD 33,366.24 · 화면 환율 1 USD = 1.397 CAD · Terms Due on Receipt · 기한 10/28 · 「Overdue」) · V137500-IN · 1801158180 · RIH2026000000 · 2026-02394 · 484908, 484909 · Order #8884650(CAD · HST 123.50) |
| 하루 원가 장 12 장 | **모두 sent**(10-31 · 11-02 ~ 11-06 · TOR · EDM) · COGS-20261031-TOR = QBO #173061 · 11-05 TOR #173071 · 11-06 TOR #173072 · deferred 525 닫힘 |
| 날짜 검산(QBO JE 열어 봄) | 11-05 TOR 에 RCV-00117 950.00 · 11-06 TOR 에 RCV-00121 12,039.53 — **1120 대로 제 날짜** · 입고 줄 계정 = QBO 이름 「Inventory Asset:Stock in Trans…」(Id 1150040012 = GINR) |
| GINR 센트 | RCV-00121 JE 대 12,039.53 vs Bill 1801158180 차 8,599.66 × 1.4 = 12,039.52 → 0.01 남음(E-3 예상 그대로 · 정상) |
| Queue | 창고마다 바로 다음 장 하나만(설계 · 1098) — 두 창고를 나란히 한 바퀴 두 장씩 |

- ⚠️ 북키퍼 주의(짐작): 보낸 Bill 7 장은 QBO 에 미지급으로 서 있다 — IMS 결제 4 건은 4-5 가 보낸다 · 그 전에 QBO 에서 결제하면 두 번(1081) · 안내서에 이 줄이 있는지는 문서 차수가 못 봤다

**⑥ 4-2b sandbox (Canada · realm 9341458557490536 · 11-09 13:20 ~ 13:35 PST — sandbox 표시 시각 · Caleb API Explorer)**

- 새로 만든 것: USD 은행 98 · USD 카드 99 · BillPayment 206(E-9) · 207(E-12) · 208(E-11) · 209(E-13 · void)

| 시험 | 결과 | 4-5 규칙 |
|---|---|---|
| E-9 | 환율 1.39 그대로 · Bill 199(1.4)의 HomeBalance 0 → 환차이익 1.00 QBO 가 셈 | 1123 확정 |
| 외화 결제 | `ExchangeRate` 만 → 2410 「Currency is missing」 | `CurrencyRef` 반드시 |
| E-12 | 한 결제 줄 둘(200 에 50 · 201 에 33) · 부분 됨 | 결제 줄 = 붙임마다 |
| E-11 | `PayType CreditCard` · `CreditCardPayment.CCAccountRef` 됨 · 인쇄 칸 없음 | 계좌 종류로 PayType |
| 인쇄 | 수표 기본 `PrintStatus NeedToPrint` · `NotSet` 받음 | 수표는 `NotSet` 반드시 |
| E-13 | void 됨(BillPayment 작업 「Void a billpayment」 · 몸 `{Id, SyncToken, sparse:true}`) · 응답 TotalAmt 0 · Line [] · PrivateNote 앞 「Voided - 」 · Bill 202 Balance 82.5 로 다시 열림 | 1125 단서 풀림 · 확정 |
| Bill 쪽 이름 | 카드 결제 208 도 Bill 의 LinkedTxn 에 `BillPaymentCheck` 로 보임 | Bill 쪽 이름으로 결제 종류를 가르지 마라 |
| 조회 칸 | Bill `HomeBalance` 조회 불가(4001) — 읽기(GET)에는 옴 | `QUERY_UNSELECTABLE` 에 셋째(4-5 에서 · 지금 코드는 둘) → [4-5b `16412bc`] 셋째 더함(`qbo.ts` 793) |
| E-10 | 안 함 — IMS 가 저장 때 막음(1122 · 4-3b) | — |
| E-8 | 미룸 — 조기 결제 할인 실물 0 | 4-5 에서 할인 있는 결제는 막고 사람에게(짐작 · 4-5 판정 거리 · deferred 538) → [11-09 밤] 판정 **1132** 로 확정 — 할인 · 크레딧 붙음 · 금액 ≠ 붙임 합은 몸이 막는다(§15-n) |

- 「조회 불가 칸」 실측 셋: JournalEntry `TotalAmt`(3-3b) · BillPayment `PayType`(4-1 R2) · Bill `HomeBalance`(4-2b)

**⑦ 다음**

4-5 결제 DB + EF + 화면(판정 1123 · 1124 · 1125 · ⑥ 규칙 · 밀린 IMS 결제 4 건 — USD 3 건은 환율 칸을 채운 뒤) → 4-6(켜기 · 정본) · 화면 차수(qbo-send 공급처 꼴 535 · 보낸 장 미리 보기 534) · 1131 나(536) → [11-09 밤] 4-5 · 535 끝 · 남은 다음 = §15-n ⑨

- 곁가지 deferred 534 ~ 538 · 잇기 459 · 522 · 528

### 15-n 4-5a · 4-5b · 4-5c — 공급처 결제(BillPayment)가 나간다 · 첫 실물 173092 · 은행 피드 · 두 환율 (2026-11-09 밤 · asung-wms `a9cb5ce` · `16412bc` · asung-ims `697dd2e` · `53edc22` · `e745754` · 판정 1132 ~ 1134 · so-module §110)

- **상태**: 공급처 결제 **운영에서 보냄** — 밀린 IMS 결제 4 건 중 CAD 1 건 → QBO **173092** sent · USD 3 건은 환율이 비어 몸이 막음(북키퍼가 MTFX 환율을 넣고 Send — Caleb) · 공급처 kind 는 cron 61 · 62 **밖** — 손 Send 만 · 은행 피드 Match 는 북키퍼(Caleb)
- **원천**: 지시서 docs-1109f · `~/asung/prompts/docs-1109f-sources.md`(S1 · S2 · S5 · S6 · S8 · S9) · 커밋 글 원문 · 마이그레이션 · EF 머리 주석 · 판정 원문 표는 so-module **§110-a**
- ⚠️ 공개 레포 — 공급처 · 손님 상호 · 사람 이름은 적지 않는다 · 운영 realm 은 `…6496`

**① 판정 요지 (원문 so-module §110-a)**

| 판정 | 요지 |
|---|---|
| 1132 | QBO 에 그대로 옮길 수 없는 결제 = ① 조기 결제 할인 ② 붙임 문서에 크레딧 붙음 ③ 결제 금액 ≠ 붙임 합 → **몸이 막고 사람에게**(QBO 에 손으로 → IMS Skip) · IMS 에서 고쳐 벗어나면 다시(① ③ 은 지문이 바뀌어 저절로 · ② 는 Retry) · E-8(538)이 서면 다시 연다 → [2026-11-10 · §15-o] ① 할인은 4-7 로 보낸다(세금 몫 · 세금 있는 인보이스 · 청구서 할인은 그대로 막음 1145) · ② 는 그대로 막음(초안 포함 1147) |
| 1133 | PayType = IMS 계좌 종류(BANK → `Check` + `CheckPayment {PrintStatus NotSet, BankAccountRef}` · CREDITCARD → `CreditCard` + `CreditCardPayment.CCAccountRef`) · QBO 계좌 거울의 AccountType · 통화와 대조 · 다르거나 거울 값 없으면 막음(Refresh list 안내) |
| 1134 | unknown 자동 done = TxnDate + VendorRef + 금액(센트) + PrivateNote 표지 「IMS supplier payment <po_payment.id>」 가 모두 맞는 BillPayment **한 장**일 때만 · 0 · 2+ = 사람 |

- 앞 판정 그대로 이 차수가 지은 것: 1122(결제 통화 ≠ 계좌 통화 거부 · 4-3b 트리거) · 1123(USD 결제 환율 = 산 날 MTFX · 필수) · 1124(결제 하나 = 공급처 하나 · **이제 강제**) · 1125(IMS 결제 삭제 → void 일감) · 1130(DocNumber 21 자 + PrivateNote 전체)

**② 4-5a DB (`a9cb5ce` · 적용 `20261109230000` · 시험 51/51 · 확인 50/50)**

| | |
|---|---|
| 이름 | kind `bill_payment` · `bill_payment_void` · ims_kind `po_payment` · ims_id = `po_payment.id` — ⚠️ **`payment` 를 쓰지 마라**: cron 62(`ims-qbo-send-payments` · `qbo_send_payments_enabled` on)의 kinds 에 `payment` · `payment_void` 가 있어 공급처 결제가 5 분마다 저절로 나간다(4-5-0) |
| CHECK 일곱 | qbo_job 셋(kind · ims_kind · pair 명시 가지) · qbo_txn 셋(type BillPayment · pair) · `po_payment_exchange_rate_ck`(> 0) |
| 새 함수 | 지문 · 몸 `qbo_bill_payment_body` · void 몸 · sync(`p_payment_id, p_by, p_detached`) · 표 트리거 함수 `qbo_job_on_po_payment` · 백필 `qbo_bill_payment_backfill` |
| 표 트리거 둘 | po_payment · po_payment_alloc — deferred constraint trigger FOR EACH ROW(한 트랜잭션의 결제 + 붙임을 끝에 한 번 맞춘다) |
| 몸 검사 순서 | 1124(공급처 둘 이상) → 1132 ① ② ③ → 환율(1123) → 계좌 종류(1133) → 거울(1133) · 모두 raise(사람 글 · 「— nothing was sent」) · 1132 글 머리 = 「Enter this payment in QuickBooks by hand, then press Skip on this job」 |
| 지문 | 붙임 0 = 지문 null(보낼 것 없음) · 지문이 바뀌면 보낸 결제는 void + 다시(손님 `qbo_payment_sync` 꼴) · 날짜 · 계좌 · 금액 · 붙임을 직접 고쳐도 같은 길 |
| 1124 강제 | `po_payment_create` · `po_payment_alloc_set` 거부 + 붙임 대상(문서) **직접 UPDATE 거부**(「The document on this payment line is not changed here — remove the line and add the document again」) |
| 환율 입력 | `po_payment_create(…, p_exchange_rate)`(맨 뒤 · 기본 null · drop/create · 11 인자) · 머리 칸 `exchange_rate` 는 PostgREST 로 고친다(pay rate v1) |
| 거울 | `qbo_entity_upsert` Account 가지 — detail 에 `AccountType` · `CurrencyRef` 만 · 열쇠 `detail->>'AccountType'` · `detail->'CurrencyRef'->>'value'` |
| 취소 순서 | 붙임 DELETE 트리거가 OLD 문서 id 를 void 일감 note 에 남기고 `qbo_job_on_po_doc_status` 가 그 문서의 열린 `bill_payment_void` 를 blocked_by 로 ⇒ **`bill_delete_manual` 은 결제 void 뒤** · ⚠️ 가장 오래된 열린 void 하나만 기다린다(deferred 541) |
| since | since 전 문서에 붙는 결제 = raise · 백필 `{"seen": 4, "queued": 4, "realm_id": "…6496"}` → `bill_payment|queued|4`(EF 는 4-5b 전 이 kind 를 안 보냄) |
| 재발행 | 더한 66 · 바뀐 7 · 빠진 0 — claim(wait_job 꼴) · done · preview · retry · doc · list(po_payment 라벨) · po_doc_status · alloc_guard · po_payment_create · alloc_set · qbo_entity_upsert |
| 시험이 잡은 결함 | 지문이 QBO 와 같아져 void 를 거둘 때 그 void 뒤 다시 보내기 일감이 skipped 부모에 영구 blocked → sync ① void 거둘 때 뒤 bill_payment 도 skipped ② 새 void 서면 blocked 일감도 그 뒤로 · ⚠️ **손님 `qbo_payment_sync` 에 같은 결함 남음**(무접촉 · deferred 540) → [2026-11-10 · §15-o ①] 손님 쪽 고침(qbo-pay-fix-1 · 540 닫힘) |

- 적용 직후 둘째 겹(화면): CAD 1 건 「QuickBooks account #104 (IMS _104_) has no account type or currency on file yet — Settings → QuickBooks matching → Refresh list (accounts), then retry (1133)」 · USD 3 건 「… is in USD but has no exchange rate — enter the MTFX rate of the day the money was bought (1123) …」 — 설계대로

**③ 4-5b EF (`16412bc` · deno 31/31 · 변이 넷 잡힘 · 배포 Caleb)**

| | |
|---|---|
| 보내기 목록 | SEND_KINDS **24** · `SUPPLIER_KINDS` + `bill_payment` · `bill_payment_void` — DEFAULT 밖(cron 61 · 62 에 안 섞인다 · 손 Send 만) |
| 만들기 | POST billpayment · `assertWriteAllowed` 가 billpayment 몸을 검사 |
| void 주소 | `POST billpayment?operation=update&include=void` · 몸 `{Id, SyncToken, sparse:true}`(손님 Payment void 와 같은 꼴 · 4-2b sandbox 209 · 2 차 자료 같은 주소 · Intuit 원문은 JS 라 못 읽음 · 틀리면 4xx 쓰기 0) |
| 가드 ① 조회 | `select * from BillPayment where TxnDate = '<d>' MAXRESULTS 1000`(`PayType` 은 고를 수 없다 · VendorRef 조건은 미실측 → 공급처 · 표지 · 센트는 EF 가 거른다) · 1000 이상이면 failed |
| 가드 ② 결과 | 표지 장 0 → 계속 · 표지 · 공급처 · 센트 같은 1 장 → 바로 done 「already in QuickBooks (bill payment #… — same date, vendor, amount and IMS note found before sending) — recorded, not created again」 · 표지 같고 공급처 · 금액 다른 살아 있는 장 1 = **unknown**(두 장 방지 · 답 밖 더함) · 표지 2+ = unknown · 표지 일치 = 표지 그대로 또는 「표지 · full reference:」 로 시작 |
| Bill 잔액 가드 | POST 직전 붙임마다 GET bill/<id> · Balance < 붙일 금액이면 **failed** — 글에 출구 둘(QuickBooks 의 손 결제를 지우고 Retry · 그 손 결제를 남기려면 IMS 에서 Skip) · 1081 · 「Bill 에 붙인 손 결제」 만 잡는다(은행 피드에서 따로 분류된 출금은 못 잡는다) |
| 열쇠 | `billPaymentKeyOf` · `parseBillPaymentKey`(손님 열쇠와 따로) · 재료는 몸 lookup(DB 가 주고 EF 가 조립) · 풀기(cron 62 의 unknown 풀기)는 1134 · void unknown 풀기 = Id GET · TotalAmt 0 + PrivateNote 「Voided - 」 머리면 done |
| done | `p_qbo_name` = doc_number ?? name · 통화 다름은 `p_note` 경고 |
| 조회 불가 칸 | `QUERY_UNSELECTABLE` = JournalEntry `TotalAmt` · BillPayment `PayType` · Bill `HomeBalance`(셋째 · `qbo.ts` 793) |
| 거울 | `PULL_FIELDS.Account` = `*`(1133 · AccountType · CurrencyRef) — 배포 뒤 Settings → QuickBooks matching → Refresh list(accounts) → 「QuickBooks Account list read — 238 records」 · 238 모두 type · currency 있음 |
| 변이 넷 | 잔액 가드 끔 · 이미 있음 done 끔 · SUPPLIER_KINDS 에서 뺌 · void 조건 뺌 — 모두 FAILED → 되돌려 31/31 |

**④ 4-5c 화면 (asung-ims · 대화 Claude)**

- payments.html pay rate v1(`697dd2e`): 외화 결제 상세 **Exchange rate**(「CAD per 1 USD」 · saveHead · 0 이하 막음 · 비면 「needed before this payment can go to QuickBooks」) · To pay 창 **Exchange rate**(USD 문서면 나타남 · 자리 글 「CAD per 1 USD — MTFX rate of the day the money was bought」 · `p_exchange_rate` · 비우면 한 번 묻고 저장) · 경고 `exchange_rate_missing`
- qbo-send.html qs sup v1(`53edc22`) · v2(`e745754`): 종류 「Supplier bills and credits」 · 「Supplier payments」 · 이름표 Supplier · Supplier bill · Supplier credit · Delete bill by hand · Supplier payment · Void supplier payment · 공급처 미리 보기(공급처 · 결제 방식 · 낸 계좌 · 수표 인쇄 · A/P · 금액 · 환율 · CAD 환산 · 붙는 Bill) · QBO 참조는 번호(#)만(이름은 deferred 542)
- 메뉴 길 = **Integrations › QuickBooks**(판정 1136 · nav v16)

**⑤ 첫 실물 (2026-11-09 토론토 저녁 · Caleb 손 Send)**

| | |
|---|---|
| IMS 결제 | e-Transfer `C1ACHPfyTpkZ` · CAD 1,073.50 · 11-04 · 계좌 `_104_` TD CAD CHEQUING(BANK) |
| 미리 보기 몸 | VendorRef 7204 · PayType Check · `CheckPayment {PrintStatus NotSet, BankAccountRef 104}` · APAccountRef 62 · CurrencyRef CAD · TotalAmt 1073.5 · Line LinkedTxn 173051 Bill · DocNumber 「e-Transfer C1ACHPfyTp」(21 자) · PrivateNote 「IMS supplier payment 6c178695-69de-419d-9ea4-9622ebe09ae1 · full reference: e-Transfer C1ACHPfyTpkZ」 · sendable · needs [] |
| 거울 짝 | `_104_` TD CAD CHEQUING BANK ↔ QBO 104 Bank CAD(detail 에 Name 없음) |
| 결과 | sent · **QBO 173092** · Bill Payment no. e-Transfer C1ACHPfyTp · TD CAD CHEQUING · Print later 꺼짐 · Bill Order #8884650 Paid · 잔액 0 · 화면 waiting 94 → 93 · sent 630 → 631 |

- 목록이 한 번 「canceling statement due to statement timeout」(All · Supplier payments) — 열린 트랜잭션 · 잠금 0 · 새로 고침 뒤 정상 · 원인 모름(deferred 546)

**⑥ 은행 피드 · Match (북키퍼 몫 · Caleb)**

- TD 피드: 보내기 전 11/04 「SEND E-TFR *pkZ」 1,073.50 For review · 「1 match found · Bill」 — QBO 가 열린 **Bill** 을 짝으로 내민다 · **누르지 않는다**(QBO 가 결제를 따로 만들어 IMS 결제와 두 번) → IMS 가 보낸 뒤 짝이 「Bill Payment e-Transfer C1ACHPfyTp」 로 바뀜 → 그때 북키퍼가 Match
- 순서: 피드를 먼저 분류하지 않는다 → IMS Preview → Send → 짝이 Bill Payment 로 바뀌면 Match(여러 줄 Batch actions › Accept Selected) · 은행 규칙 「Automatically add to books」 금지(새 거래를 만들어 두 번) · QBO 자동 매칭은 QBO Payroll · Payments 거래에만(Intuit 도움말)
- **MTFX 는 QuickBooks 은행 피드에 연결 안 됨**(Caleb) → USD 결제는 Match 단계 없음

**⑦ 두 환율 · MTFX 장부 (북키퍼 실무 · IMS 밖 — deferred 줄 없음 · docs-1109f 이견 6)**

- Bill 환율 = IMS 인보이스 환율(재고 원가도 이것) · 결제 환율 = 그 돈을 산 날의 MTFX 환율(1123) · 차이 = QBO 가 셈하는 환차손익 · 예 AST261028 33,366.24 USD × 1.397 = 46,612.64 CAD · × 1.404312 = 46,856.61 CAD → 243.97 환차손 · IMS 재고 원가 무변 · **결제 환율을 Bill 환율에 맞추지 마라**
- MTFX USD 장부(10/16 ~ 11/05): 북키퍼가 MTFX 송금을 「Bill Payment (Cheque) · WIRE」 로 손으로 적고 설명에 ER(10/16 1.42708 · 1.424031 · 10/23 1.410309 · 10/27 ~ 28 1.407932 · 11/03 1.401212 · 11/05 1.404312) · USD 사기 Transfer 가 10/21 뒤 없음 · MTFX USD 잔액 음수 · 11-04 출금 없음 → 밀린 USD 셋(14,555.10 · 33,366.24 · 24,960.00)은 QBO 에 없다(두 번 걱정 없음)
- 11-03 손 송금 둘 · 11-05 하나가 IMS(컷 뒤) 인보이스의 송금인지는 안 봤다 — 맞다면 1081 위반(QBO 손 결제 + 나중 IMS 결제 = 두 번) · deferred 547

**⑧ 북키퍼 안내서** (Claude Doc rev 49 · Caleb 전달): 메뉴 길 Integrations › QuickBooks · 「공급처 결제 보내기와 은행 피드 맞추기 — Match 는 북키퍼님 몫」 · 「환율은 두 개」 · 표 「IMS 에 적은 공급처 결제 4 건」(CAD 1 sent 173092 · USD 3 환율 대기) — so-module §110-c 10

**⑨ 다음**

USD 3 건(북키퍼 환율 → Send) → 4-6(켜기 · 정본) · E-8 sandbox → 할인 결제 짓기(538 · 첫 후보 2223170 할인 기한 **11-19**) · 1131 나(536) · 화면 거리 534 · 542 · 543 · 곁가지 deferred 539 ~ 547 → [2026-11-10 · §15-o] E-8 · 할인 결제 끝 · 536 은 1144 로 닫힘 · 다음 = §15-o ⑧

### 15-o qbo-pay-fix-1 · E-8 · 4-7a · 4-7b · 4-7c — 조기 결제 할인 공급처 결제 · 지급 기한 자동 (2026-11-09 밤 ~ 11-10 · asung-wms `3f0a7a8` · `573b6af` · `222e96c` · asung-ims `e340db4` · 판정 1143 ~ 1150 · so-module §111)

- **상태**: 할인 있는 공급처 결제가 QuickBooks 로 **갈 수 있다**(손 Send · 공급처 kind 는 cron 61 · 62 밖 그대로) · 할인 받은 결제 실물 0 · 첫 후보 2223170(할인 기한 11-19) · USD 할인 결제 sandbox 는 아직(deferred 554)
- **원천**: 지시서 docs-1110a · `~/asung/prompts/docs-1110a-sources.md`(S2 ~ S7 · S10) · 마이그레이션 · 커밋 글 원문 · 판정 원문 표는 so-module **§111-a**
- ⚠️ 공개 레포 — 공급처 상호 · 사람 이름은 적지 않는다 · 운영 realm `…6496`

**① qbo-pay-fix-1 — 손님 결제 (`3f0a7a8` · `20261110023000` · deferred 540 닫힘)**

- 손님 `qbo_payment_sync` 에 4-5a 의 두 고침을 넣었다 — ① void 를 거둘 때 그 뒤 다시 보내기 일감도 skipped ② 새 void 가 서면 blocked 일감도 그 뒤로(blocked_by) · 둘이 없으면 **QBO Payment 는 void · 다시 보내기는 영구 blocked**
- 운영 1 건 풀림: 결제 161.34(e_transfer · 11-04) · QBO Payment 172656 이 11-06 void(붙임 더함 → 뗌 → 다른 인보이스에 붙임) → 적용 때 한 행 풀기(released 1) → **QBO Payment 173093** sent · 172656 은 void 그대로
- 같은 꼴 다른 sync 셋(크레딧 붙임 · 이월 붙임 · 환불) 없음 · ⚠️ 인접 꼴 — **부모를 skipped 로 닫을 때 뒤 blocked 일감을 안 본다**(`qbo_job_skip` · `qbo_job_on_invoice_cancel` · `on_credit_cancel` · `on_po_doc_status` · 모든 kind · 운영 0 · 11-10) → deferred 548 · 할인 VC → 결제만 4-7b 가 풀었다(④)

**② E-8 sandbox (11-09 밤 · Caleb · API Explorer · 실측 so-module §111-c 1)**

- BillPayment Line 에 `[Bill 210 100, VendorCredit 211 2]` · TotalAmt 98 → 받아 줌 · 둘 다 Balance 0 · void → Line [] · BankAccountRef 빠짐 · Bill 과 VC 가 **함께** 다시 열림
- ⇒ 할인 결제 몸 = Bill 줄(`alloc.amount` = 할인 포함 갚은 몫) + VC 줄(`discount_amount`) · TotalAmt = 낸 돈 · void 하면 VC 가 다시 열려 같은 할인이면 다시 쓴다(1146)
- 「Automatically apply bill payments」(운영 · sandbox On)는 API VC 를 열린 Bill 에 붙이지 않는다(VC 211 이 Bill 210 에 저절로 안 붙음) ⇒ 화면 입력에만 작동 · On 그대로(4-7a 이견 4)

**③ 4-7a DB (`573b6af` · 적용 `20261110034500` · 시험 41/41 · 확인 41/41 · 마른 실행 FAIL 18)**

| | |
|---|---|
| 할인 VC 일감 | kind `vendor_credit` + ims_kind **`po_discount`** · ims_id = `po_payment_alloc.id`(1143) · 새 함수 `qbo_discount_credit_body` · `qbo_discount_credit_sync` · 자기 Bill 뒤 wait · VC 일감 skipped → 결제 raise |
| VC 몸 | DocNumber `D<결제일 yymmdd>-<인보이스>`(21 자) · PrivateNote `IMS early-payment discount <alloc id>` · 한 줄 → GINR · 환율 = **인보이스 환율**(1148) |
| 결제 몸 | `check_lines` 원소 `{txn_type, qbo_txn_id, …}` — Bill 줄 + VendorCredit 줄 · TotalAmt = 낸 돈 |
| 막힘(사람에게) | 머리 「Enter this payment in QuickBooks by hand, then press Skip on this job」 + 까닭 · ① 할인 세금 몫(1145 · 「or change it to a before-tax discount in IMS」) ② 세금 있는 인보이스의 할인(4-7a 이견 2) ③ 청구서(charge) 할인(VC 계정 미정 · 이견 1) ④ 인보이스에 붙은 크레딧 — **초안 포함**(1132 ② · 1147 · 「or cancel that credit in IMS, then press Retry」) ⑤ 붙임 합 ≠ 결제 금액(1132 ③) ⑥ QuickBooks 시작일 전 문서 · (+ 상품 아닌 줄에 걸친 할인 — 보낼 수 있는 Bill 에서 늘 0) |
| 바뀜 | 할인 A → B → A 되돌림(qbo-pay-fix-1 꼴) · VC sending/unknown 중 할인 변경 · done 뒤 맞추기 · 할인이 바뀌거나 없어지면 `bill_delete_manual`(po_discount · 「delete QuickBooks vendor credit #… by hand, then press Skip」 · 1146 · 1126) |
| 원가 장 | `settlement_discount` → send(보류 글 「opens with the supplier payment round」 지움 · 1149) · 지금 보류 열쇠 0 |
| 지급 기한(1144) | `po_invoice` BEFORE INSERT/UPDATE 트리거(인보이스 · draft) → `po_invoice_due_auto`(실행권 0) = 문서 날짜 + net_days · 칸 **`due_date_manual`**(사람 값 지킴) · 기존 10 장 값 무변 · 조건과 다른 장만 표지 true(484908, 484909 한 장) · 확정 경고 `due_date_missing` · `due_date_differs_from_term`(막지 않음) |
| 재발행 | claim 2 곳 · preview · done · retry · doc · list · `qbo_job_on_po_payment` · `qbo_bill_payment_body` · `qbo_cost_expected` · `po_invoice_confirm` · − 줄은 모두 그 자리 고침 |
| 시험 안 본 것 | 청구서 할인 시나리오 · 원가 장 실제 실행 · 확정 경고 실제 호출 |

**④ 4-7b DB + EF (`222e96c` · 적용 `20261110040718` · 시험 23/23 · 확인 23/23 · deno 32/32 · 변이 16 모두 잡힘)**

| | |
|---|---|
| needs 길 | 「먼저 만들기」 = claim 이 needs 를 `qbo_job_open_or_add` 로 세우고 본 일감 blocked → EF sendPicked 바퀴 · ⚠️ open_or_add 는 customer · item · vendor 만 받았다 → 4-7a 의 wait 꼴은 이 길을 안 탐(「blocked · no_progress」) ⇒ 4-7b 가 `vendor_credit` 가지(열린 po_discount 일감을 **찾아 돌려주기만**)를 더함 |
| DB 재발행 셋 | `qbo_bill_payment_body`(안 간 할인 VC 를 needs 로 · Bill 안 갔으면 Bill 만 wait) · `qbo_job_open_or_add` · `qbo_job_claim`(② Skip 된 할인 VC 를 기다리던 결제 풀기 · 4-7b 이견 4) |
| EF 순서(1150) | 할인 VC need 를 같은 호출에서 먼저(ims_kind po_discount · 기다리는 일감이 bill_payment 일 때만 · 바퀴 3 · 할인 둘이어도 3) |
| EF 검사 | `check_lines` txn_type 가르기 · Σ Bill − Σ VC = 낸 돈 · **VC Balance 가드**(못 읽음 · 공급처 다름 · 통화 다름 · 모자람 → failed · 응답에 CurrencyRef 없으면 통화는 지나감 — deferred 554) · 실패 글 꼬리 「vendor credit #N is already in QuickBooks and stays open there until this payment goes through」 |
| Line 조임 | `billPaymentLineProblem` — 줄마다 LinkedTxn 하나 · TxnId · TxnType Bill \| VendorCredit · Bill 줄 하나 이상(4-7b 이견 6 · 빈 Line billpayment 거부 → 기존 시험 단언 둘 고침) |
| VC 표지 | PrivateNote 표지로 가드 · unknown 풀기 `note_differs`(4-7b 이견 7) · void 무변 |
| EF | `_shared/qbo.ts` md5 `8fedf424` · 1792 행 |
| 넘긴 것 | USD 할인 결제 sandbox(걸음 1 ~ 6 · Caleb · 아직 · deferred 554) |

**⑤ 4-7c 화면 (asung-ims `e340db4` · 대화 Claude)**

- invoices.html inv disc v3: 지급 기한 옆 할인 칩 「Pay by … → save … · N days left」(3 일 이하 주황) · 기한 출처 「from the payment term」 / 「set by hand」 · 목록 Due 칸 칩 · 확정 경고 두 코드 사람 말 · 「Cancel invoice…」 — ⚠️ 출처 · 목록 칩은 창구에 칸이 없어 **안 보인다**(deferred 555)
- qbo-send.html qs sup v3: 「Early-pay discount credit」 · 「Delete discount credit by hand」 · 결제 미리 보기 「discount credit」 칩 · 「created first, in the same send」 · 합계 Bills · Early-pay discount · Paid

**⑥ 남은 막힘 · 거리** — 548 Skip 일반 · 549 크레딧 붙은 결제(「0 원 BillPayment 붙임」 sandbox) · 550 할인 세금 몫 · 세금 있는 인보이스(회계사) · 551 청구서 할인 VC 계정 · 552 결제 Skip 뒤 안 붙은 할인 VC · 553 할인 VC DocNumber 겹침(같은 날 · 같은 인보이스 · 두 결제) · 554 USD sandbox + VC 통화 가드 · 555 화면 칸

**⑦ 북키퍼 안내** — 쉬운 말판 rev 53(할인 칩 · 할인 결제 Send 한 번 · 「Cancel invoice…」 는 나가기 아님) · 상세판(계정 지도 · 분개 표 · 대사 · 판정 색인) — so-module §111-c 10 · 11

**⑧ 다음**

2223170 Bill Send → 11-19 안에 할인 결제(첫 실물) · USD 할인 sandbox(554) · USD 3 건 환율(§15-n) · 4-6(켜기 · 정본)
