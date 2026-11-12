---
name: asung-qbo
description: >
  Asung Trading IMS 와 QuickBooks Online(QBO) 연결 — OAuth 연결 · 끊기 · 토큰 갱신 · 끊김 메일 · Settings → QuickBooks · Intuit 앱 · 설문을 다루거나 QBO 싱크를 지을 때 먼저 읽으세요.
  "QuickBooks", "QBO", "퀵북", "Intuit", "realm", "qbo_connection", "qbo_oauth_state", "qbo_call_log",
  "Vault", "needs_reconnect", "invalid_grant", "QBO_ENV", "ims-qbo-refresh", "cron 59", "EF qbo", "qbo_status", "intuit_tid",
  "qbo_alert_to", "Untie company", "Reconnect", "App assessment", "redirect URI", "minorversion", "QBO 싱크",
  "qbo_link", "qbo_entity", "qbo_match_auto", "qbo_pull_state", "pull", "QuickBooks matching",
  "qbo_job", "send", "apiWrite", "credit_apply", "QUICKBOOKS 열쇠",
  "Bill", "VendorCredit", "BillPayment", "GINR"
  가 나오면 추측하지 말고 이 스킬과 정본 docs/design/qbo-integration.md 를 확인하세요.
  ⚠️쓰기는 apiWrite 하나 — 자동 재시도 없음 · 모르면 unknown(인보이스는 아직),
  ⚠️토큰은 Vault 에만 — 표 · 화면 · 기록 · 응답에 싣지 마라,
  ⚠️REST safeupdate — 창구의 update · delete 는 WHERE 필수(psql 시험은 못 잡는다),
  ⚠️refresh_token 은 갱신마다 바뀐다 — 임대 + 판 번호로만 저장,
  ⚠️realm 고정 — 다른 회사에 잇지 마라,
  ⚠️이월 돈 손 분개가 보이면 삭제 → Retry · OC void 아님.
---

# Asung QuickBooks 연결 스킬

⭐ **정본 = `docs/design/qbo-integration.md`**(지금 규칙) · 하루 이야기 = `so-module.md` §87(판정 867 ~ 872 · 617 확인) · §95(판정 933 · 934 · 읽기 · 짝 · 받기) · 이 스킬은 「모르면 사고가 나는 것」 요약이다 — 새 사실은 정본에 먼저.
관련: `asung-workflow`(지시서 · REST 두 겹) · `asung-doc`(메일 큐 · info@) · `asung-so`(인보이스 · 결제 · 크레딧 — 싱크 때 보낼 것)

## 0. 어디까지 왔나

```
2026-10-29  연결 줄기 끝 — qbo-1a(DB) · 1b(EF qbo · 끊김 메일) · 1c(REST WHERE) · 1d(회사 이름 실패 기록) · Settings → QuickBooks(set v12) · 약관 · 처리방침(legal v1)
            샌드박스 연결 → 끊기 → 다시 연결 → Intuit 설문 제출 → 운영 키 → 11:48 실제 Asung Trading Inc. 연결(Production)
⭐ 운영 = Asung-IMS(fazgmyvzzhqybtvtktyg) — 「테스트 DB」 가 11-01 부터 그대로 운영(판정 617) · QBO_ENV = production
2026-11-01  읽기 · 짝 · 받기 — qbo-read-1(EF query · read · GET 만) · qbo-sync-1a(qbo_entity · qbo_pull_state · qbo_link · 창구 9) · 1b(EF pull) · 1c(짝 묶음 · Item select *) · Settings → QuickBooks matching(set v13)
            자동 짝 account 220 · tax 24 · term 17 · method 7 · supplier 195 · customer 9,764 · product 11,775 (정본 §12)
2026-11-01 밤  쓰기 바탕 — qbo-sync-2a(열쇠 QUICKBOOKS 945 · qbo_job · qbo_txn · 손님 · Item 몸 · 일감 창구 8) · 2a′(apiWrite · send · unknown 이름 조회) · set v14
            운영 첫 쓰기: 손님 1 명 → QBO Customer 10740 (정본 §14)
~~⬜ 인보이스 · 크레딧(2b) · 결제 · void~~ →
2026-11-01 밤  인보이스 — qbo-sync-2b1(DB 몸 · 발행 · 취소 트리거 · claim needs · qbo_txn) · 2b2(EF invoice · invoice_void · DocNumber 멱등 · cron 61 ims-qbo-send)
2026-11-02  크레딧 노트 — qbo-sync-2c1(크레딧 몸 · 트리거 · 채우기 · IMS 문: 인보이스 취소 959 · 968 · 969 · 세금만 크레딧 금지 966)
            북키퍼 골라 보내기 — qbo-sync-2d1(claim p_job_ids · preview · list · retry skipped · EF send job_ids) · 화면 Sales → QuickBooks(qbo-send.html · qs v1)
            ⭐ 첫 인보이스 60000 → QBO 172335(sent · mismatch 0 · Caleb 확인) · Cin7 ↔ QBO 연결 Caleb 이 끔(375 닫힘) · 정본 §14-b ~ §14-e
~~⬜ 결제(Payment) · 크레딧 붙이기 · 환불(964) · 스위치 켜기(971 · Caleb) — deferred 260 · 327 · 341 · 374 · 432 · 434 · 440 · 443~~ →
2026-11-02 밤  결제 — qbo-sync-2e-1a(paypal · 수표 #105 · 미래 결제일 991) · 1a2(Clearing - Shopify 993) · 1b(결제 일감 · 몸 · 지문 · 트리거 · 백필 · done 10 인자) · 1c(EF · void = operation=update&include=void · Balance 가드 · cron 62 기록)
            ~~⚠️ **아직 켜지 않음** — qbo_send_payments_enabled off · cron 62 등록 전~~ → ✅ [2026-11-04] **켜짐** — cron 62 jobid 62 `*/5` · qbo_send_payments_enabled on · 17:00 첫 회차 sent 15 · deferred 453 닫힘 · 정본 §14-f 「켜짐」
2026-11-03  크레딧 붙임 — qbo-sync-2e-2-1(DB · `20261103200000` · 붙임 한 줄 = 0 원 Payment 한 장 · CustomerRef = 매장 · 1009 · 1011 ~ 1017 · 정본 §14-g) · EF 는 2e-2-1b(~~아직~~ → 11-04 `48d5ca4` 아래 줄) · 백필 일감 1(CR-01008 → 60026 queued)
            QuickBooks matching set v17 — Review 뒤에도 쓰기 단추(쓰기 조건 = EF status caller_qbo === 'write' · Review 가 qm 을 새로 만든다)
~~⭐⭐ [11-03 밤 · 판정 1034] 다음 = **결제 먼저 켜기**(2e-2-1b 보다 먼저 · 정본 §14-f 순서) · ⚠️⚠️ 2e-2-1b 배포 전 cron 62 kinds 는 **둘**(payment · payment_void) — 넷이면 EF kindsOf 400 · 결제도 멈춤~~ → 11-04 결제 켜짐 · 2e-2-1b 끝 · cron 62 kinds **넷**
2026-11-04  크레딧 붙임 보내기 — qbo-sync-2e-2-1b(EF · `48d5ca4` · deno 24/24 · 배포 · 461 닫힘) · 첫 실물 CR-01008 → 60026(QBO 0 원 Payment Closed) · 화면 qs apply v1(asung-ims `21d4ef9` · 종류 Credits applied to invoices) · cron 62 kinds 넷 · 정본 §14-g
⭐⭐ [11-04 · 판정 1038 · Caleb 「퀵북스 작업이 우선적으로 마무리가 되어야 해」] **QBO 줄기가 다른 IMS 일보다 먼저** — 다음 = **1d 이월 짝(452)** → 2e-3(454) → 원가 · Bill(459) · 인보이스 자동 보내기 켜기(971)는 Caleb
2026-11-05 ~ 06  이월 인보이스 짝 — qbo-sync-2e-1d-1(DB `bbfcfdb` · 창구 넷 · 열쇠 QUICKBOOKS 1044 · 풀기 1045 · 수단 짝 되살리기 1039) · 1d-2(EF `9b32168` · opening_candidates · read · search 1046) · 310 장 중 자동 299 · 사람 9 · 남음 2(471) · 452 닫힘
            송장 31 자 — qbo-trk-1(`e059e73` · TrackingNum 첫 송장 · 전체는 CustomerMemo 1054) · 정본 §14-h · §14-i · 아래 5-d
2026-11-07  이월 받아 둔 돈 붙임 — qbo-sync-2e-3-1(DB `33c8cdf` · 붙임 한 줄 = CreditMemo OC-<인보이스>-<n> + 0 원 Payment · kind 넷 opening_credit · opening_credit_void · opening_apply · opening_apply_void · CustomerRef = 돈의 주인) · 1b(EF `26e019a` · SEND_KINDS 14 · deno 26/26) · 첫 실물 60172 · **cron 62 kinds 여덟**(05:40 UTC) · 정본 §14-j · 아래 5-e
            ⭐ 60189 — 가드가 중복을 막음 → 북키퍼 손 분개(JE) 삭제 → Retry → sent(판정 1060 · 1061) · 환불 2e-3-2 는 남음(454 부분 · 1056 ~ 1058) · so-module §102
2026-11-08  환불(크레딧 노트 몫) — qbo-sync-2e-3-2-1(DB `e8babe9` · 환불 한 줄 = Purchase 한 장 + 0 원 Payment · kind 넷 refund*) · 1b(EF `84afde4` · SEND_KINDS 18) · 1b2(`8b12366` · 잇기 경고 = 직전 값) · cron 62 kinds 열둘 · 첫 실물 172912 ~ 172915 · 454 · 495 닫힘 · 정본 §14-k · 아래 5-f · so-module §103
2026-11-09  하루 원가 장 DB 앞 절반 — qbo-sync-3-2a(`0228bd0` · **적용 20261108170000 · 확인 44/44** · 표 셋 qbo_cost_sheet · _sent · _hold · 키 셋 · 함수 15) · **cron 미등록 · 첫 장은 3-2b 적용 때** · 정본 §15-i · 아래 5-g · so-module §106
2026-11-09  하루 원가 장 뒤 절반 · EF · 화면 — qbo-sync-3-2b(`2fbed9d` · **적용 20261108224000 · 확인 60/60** · kind cost_day · claim 때 줄 고정 · 차례 · 재생성 hold · resolve) · cron **67** ims-qbo-cost-build · 3-3(`232dec7` · EF 배포 · JournalEntry · 가드 · 1112) · 3-4 화면 qs cost v1a · 장 0 · 보내기 cron 미등록 · 정본 §15-j · §15-k · 다음 = **공급처 쪽(qbo-sync-4-0 조사)**
2026-11-09  공급처 쪽 시작 — 4-0 조사(DB 읽기만 · 보고 레포 밖) · 4-1 운영 콘솔(GET 만 · #138 = 계좌 Id 138 MTFX USD) · 4-2a sandbox(Bill 199 ~ 205 · Vendor 69 · 70) · **판정 1115 ~ 1130 · 짓기 전** · 원가 장 12 장 built · 보낸 장 0 · 다음 = **4-3 DB Bill · VendorCredit(11 월 안 · 1120)** · 정본 §15-l · 아래 5-g · so-module §108
2026-11-09 오후  공급처 Bill 짓기 · 운영 첫 송신 — 4-3a · 4-3b(`32f2f3e` · 적용 20261109103000 · 20261109104000 · 확인 56/56 · 16/16 · USD 계좌 여섯) · 4-4(`b879381` · EF v22 · Vendor · Bill · VendorCredit) · 3-3b(`f1fb21b` · EF v23 · JE 가드 TotalAmt 뺌)
            ⭐ **운영 sent — 공급처 Bill 7 장 · 하루 원가 장 12 장**(Caleb 손 Send) · 4-2b sandbox(1123 · 1125 확정) · 판정 1131 · **매일 원가 장 · 새 공급처 Bill 은 북키퍼가 Queue/Preview → Send**(자동은 나중에 Caleb) · 다음 = **4-5 결제** · 정본 §15-m · so-module §109
2026-11-09 밤  공급처 결제 — 4-5a(`a9cb5ce` · **적용 20261109230000 · 확인 50/50** · kind bill_payment · bill_payment_void · ims_kind po_payment · 1124 강제 · 환율 입력 길) · 4-5b(`16412bc` · EF · SEND_KINDS 24 · void · 가드 · Bill 잔액 가드) · 4-5c(asung-ims pay rate v1) · 판정 1132 ~ 1134
            ⭐ **첫 공급처 결제 QBO 173092 sent**(CAD · Caleb 손 Send) · USD 3 건은 북키퍼가 MTFX 환율을 넣고 Send · 메뉴 길 **Integrations › QuickBooks**(1136) · 정본 §15-n · so-module §110
2026-11-10  손님 결제 고침 · 할인 결제 — qbo-pay-fix-1(`3f0a7a8` · 적용 20261110023000 · 손님 qbo_payment_sync 영구 blocked · 운영 1 건 → 173093 · 540 닫힘) · E-8 sandbox(Caleb · BillPayment 212) · 판정 1143 ~ 1150
            4-7a(`573b6af` · 적용 20261110034500 · 할인 VC kind vendor_credit + ims_kind po_discount · 지급 기한 자동 1144) · 4-7b(`222e96c` · 적용 20261110040718 · EF · needs 길 · VC 가드) · 4-7c 화면(inv disc v3 · qs sup v3) · 할인 받은 결제 실물 0 · 정본 §15-o · so-module §111
⬜ ~~1d 이월 짝(452)~~(11-06 끝) · 1d-3 화면(470) · ~~크레딧 붙임 2e-2-1b EF(461)~~ · ~~받아 둔 돈 2e-3-1(454)~~(11-07 끝) · ~~**환불 2e-3-2**(454 남은 몫)~~(11-08 크레딧 노트 몫 끝 · 남은 몫 = 환불을 결제에 매기 500) · ~~qbo-send opening 이름표(495)~~(qs refund v1) · USD A/R 데이터(499) · 원가 · Bill 줄기(459) · 인보이스 스위치 켜기(971 · Caleb) — deferred 260 · 327 · 341 · 374 · 440 · 443 · 454 · 486 · 493 · 495 · 496
```

## 1. ⭐⭐ ~~연결만 · 싱크 없음~~ → 연결 + 읽기 조회 · 짝 표 · 거울 · 받기 ~~— 보내기는 없음~~ → [11-01 밤] 손님 · Item 만들기 섰음 · 인보이스는 2b — 모르면 사고

```
⭐  [2026-11-01 밤 · 정본 §14] 아래 첫 줄은 11-01 낮 상태 — 이제 손님 · Item 을 QBO 에 만든다(열쇠 qbo 의 send · 손으로) · 인보이스 · 크레딧은 2b · 거래는 아직 Cin7 → QBO 가 보낸 것뿐
~~⚠️⚠️ IMS 에는 장부로 거래를 보내는 코드가 없다~~ — 연결 뒤 하는 일 = CompanyInfo(회사 이름) + 하루 한 번 토큰 갱신 + [11-01] admin 의 읽기 조회(query · read) · 목록 받기(pull) · 짝(qbo_link)
     읽기는 apiCall 하나 · GET 만(assertReadOnlyRequest) · → [11-01 밤] 쓰기는 apiWrite 하나(§5-c) — 새 쓰기는 assertWriteAllowed 허용 목록부터(설문 374)
     「QuickBooks 에 들어갔나요?」 → 아니다 · 지금 QBO 의 거래는 Cin7 → QBO 연결이 보낸 것(그 연결은 따로 그대로 · QBO 는 여러 앱 동시 연결)
⚠️⚠️ 싱크를 지을 때 Cin7 의 QBO 싱크를 끄는 시점을 함께 정한다 — 둘이 같은 거래를 보내면 두 번 적힌다(deferred 375)
⚠️  이월 인보이스 · 받아 둔 돈(kind · method opening)은 보내지 않는다(원본이 이미 QBO · 판정 786 · deferred 341)
⚠️  싱크에서 다중 통화 · 캐나다 세금 · 지우기를 쓰게 되면 Intuit 설문에 다시 알린다(제출본은 None · No · deferred 374)
```

## 2. ⭐⭐ 토큰 · 문 — 모르면 사고

```
⭐⭐ 토큰은 Vault(qbo/<env>/refresh · qbo/<env>/access) — qbo_connection 에는 Vault id 만 · 화면은 qbo_status()(토큰 · Vault id 없음)
     처리방침의 약속(867): 토큰은 직원 화면에 안 내려간다 · 관리자가 끊으면 지운다(qbo_connection_delete = Vault 두 행 + 연결 행 + state)
     ⇒ 새 창구 · 응답 · 로그에 토큰 · client secret · code 를 싣지 마라 — EF 는 모든 글을 scrub() 으로 거른다 · 토큰 끝점 · revoke 요청 몸은 기록 안 함
⭐⭐ 문(870) = IMS admin 역할만 — 연결 · 끊기 · 다시 연결 · Untie · refresh · ping · 원문 조회 query · read · DB 가 ims_is_admin() 으로 본다(qbo_admin_gate) · 상태 읽기는 누구나
⚠️⚠️ [11-01 밤 · 945] 짝 · 받기 · 일감 · send 는 열쇠 QUICKBOOKS — perms 'qbo'(쓰기) · 'qbo:read'(보기) · qbo_key_gate(p_write) · **admin 도 켜야 한다**(글자 그대로 · ims_is_admin 안 봄)
     EF 문 둘: ADMIN_ACTIONS(start · disconnect · refresh · ping · query · read) / KEY_ACTIONS(pull · send) · 켠 사람 셋(정본 §4) · Staff 화면은 자기 행을 못 바꾼다(SQL)
     cron 길 = x-ims-cron-key == IMS_CRON_SECRET · refresh 만 · EF verify_jwt = false(Intuit 이 JWT 없이 callback 을 부른다 — 문은 함수 안)
⚠️  _shared/authgate.ts 는 옛 WMS 문 — IMS 는 사용자 JWT 를 DB 창구로 그대로
⭐  연결 · state 표는 정책 0 · grant 0(창구만) · qbo_call_log 는 authenticated 읽기 · service_role 쓰기(fc_call_log 꼴)
```

## 3. ⭐⭐ 갱신 · 끊김 — 모르면 사고

```
⚠️⚠️ Intuit 은 갱신마다 refresh_token 을 바꾼다 — 옛 값으로 다시 쓰면 invalid_grant(연결이 죽는다)
     ⇒ 잠금을 쥐고 Intuit 을 부를 수 없다(PostgREST 한 호출 = 한 트랜잭션) → 임대 + 판 번호: qbo_refresh_claim(30 s) → Intuit → qbo_refresh_save(판 번호가 같을 때만 · 새 refresh_token 매번 저장)
     ⇒ 새 갱신 길을 만들지 마라 — 늘 claim → save · 경합으로 진 쪽은 qbo_last_error_set(상태 그대로)
⭐⭐ API 401 ≠ 끊김 — 접근 토큰(1 시간) 만료도 401 · 강제 갱신 한 번 뒤 다시 · 그래도 401 일 때만 needs_reconnect
⭐⭐ invalid_grant → qbo_mark_needs_reconnect · 다시 시도 안 함 · DB 가 connected → needs_reconnect 로 **바뀌는 순간 한 번** mail_outbox(kind qbo_reconnect) → inv_config.qbo_alert_to(caleb@asung.ca · 869)
⭐  cron jobid 59 ims-qbo-refresh · 10 9 * * *(09:10 UTC) · connected 일 때만 · 접근 토큰은 부를 때 5 분 안이면 먼저 갱신
~~갱신 토큰 만료 = 연결 + 101 일 · 갱신해도 안 밀린다(실측 · 10-30 첫 운영 cron 갱신 뒤에도 그대로 — 확인됨 · deferred 370 닫힘) ⇒ **운영 연결은 2027-02-07 15:48 UTC 전에 Reconnect**(deferred 396) · 그 뒤로도 101 일마다~~
⚠️  [2026-11-09 정정 · 정본 §6 · so-module §107-c 2] 갱신 토큰 만료는 **밀린다** — 갱신 토큰이 바뀌는 갱신 때 그 시각 + 약 101 일(짐작 · 11-09 실측 2027-02-17 09:10:02Z = cron 59 09:10 UTC 갱신 + 101 일)
     ⇒ cron 59 가 돌면 고정된 Reconnect 날짜는 없다 · 지금 기한은 Settings 의 날짜 · ⚠️ cron 59 를 끄거나 갱신이 실패하면 그 기한에 끊긴다(미리 알림 deferred 371) · 396 닫힘(짐작)
```

## 4. ⭐⭐ 환경 · realm — 모르면 사고

```
⚠️⚠️ 환경은 비밀값 QBO_ENV(sandbox | production) 명시 값 + 연결 행의 env — db_role 로 가르지 마라(Asung-IMS 는 컷오버 뒤에도 db_role 'test')
     어긋나면 refresh · ping 은 409 · status · disconnect 는 열린다(빠져나오는 길) · 바꾸기 = Disconnect → QBO_ENV · 키 → Connect
⚠️⚠️ realm 고정 — 처음 연결한 회사 id 가 inv_config.qbo_realm_<env> 에 · 다른 회사는 저장 거부(callback why=realm · 받은 토큰 revoke)
     싱크가 시작되면 IMS 행이 QBO id(~~손님 · 품목 · ref_tax_rule.qbo_id~~ → [11-01] qbo_link · realm_id 칸)를 가리킨다 — 회사가 바뀌면 짝이 전부 틀어진다
     Untie company(qbo_realm_clear) = admin · 연결 없을 때만 · 회사 자체가 정말 바뀌었을 때만
⭐  callback = 언제나 302 · 본문 없음 · Location 은 코드에 고정(settings.html?t=qbo&qbo=connected | &qbo=error&why=denied|state|exchange|realm|save|env) — 요청 값을 섞지 마라
⭐  discovery 는 Intuit .well-known(24 h 캐시 · 실패면 캐시 · 없으면 500) — 주소를 코드에 박아 폴백하지 마라 · minorversion 75
```

## 5. ⭐⭐ REST safeupdate · 시험 — 모르면 사고

```
⚠️⚠️ EF 는 PostgREST 로 창구를 부른다 — authenticator 가 safeupdate 를 싣는다 → WHERE 없는 update · delete = 21000 / ping 422 「UPDATE requires a WHERE clause」
     psql 시험은 safeupdate 를 못 실어 통과한다(qbo-1a 가 그렇게 지나 샌드박스에서 막혔다 → qbo-1c)
     ⇒ 행 하나 표도 `where singleton` · 전부 지우기는 `where <PK> is not null` · insert … on conflict do update 는 대상 아님
     ⇒ 새 qbo 창구는 시험 파일에 nowhere 정적 스캐너(supabase/tests/qbo_1c_check.sql) + 적용 뒤 REST 한 번(asung-workflow §3 · §4 「REST 두 겹」)
⭐  권한 시험은 as_role 로 실제 authenticated 역할에서(claims 만 바꾸면 Vault · grant 거부를 증명 못 한다 · qbo_1a_check)
⭐  끊김 메일 실물 시험은 샌드박스로만 — 운영 연결에서 하지 않는다(deferred 377)
```

## 5-b. ⭐⭐ 읽기 · 짝 · 받기 — 모르면 사고 (2026-11-01 · 정본 §5 · §12 · §13)

```
⚠️⚠️ QBO query 는 기본 **활성만** 준다 — 목록을 다 받으려면 where Active in (true, false)(TaxCode 만 조건 없이 · 실측)
⚠️⚠️ Item 을 칸 골라 조회하면 Sku 가 안 온다(sparse) — pull 의 Item 은 select * · 받은 직후 count(sku) 한 줄로 확인 · 가짜 Intuit 도 sparse 를 흉내(1b 가 그걸 몰라 시험 통과 → 실호출 product 짝 0)
⚠️⚠️ 짝은 QBO **Id** 로 붙든다 — 이름으로 다시 찾지 마라(Cin7 이 이름으로 찾다가 같은 Sku Item 을 새로 만들어 SKU 중복 33 · 66 Item) · 같은 Sku 둘이면 「최근 것」 아님 — 이름이 IMS 와 같은 쪽
⚠️⚠️ 짝 맞추기는 묶음으로 done 까지 — qbo_match_auto(p_kind, p_after, p_limit) · REST 8 초 statement timeout(57014)을 한 번에 넘기지 마라
⚠️  ref_tax_rule.qbo_id 는 쓰지 않는다 — UNIQUE 가 Sale · Purchase 두 규칙의 한 TaxCode 를 막는다 · 세금 짝도 qbo_link(tax_rule 만 N:1)
⚠️  Customer · Vendor 는 select * 거부 · 연락처 · 주소 칸 거부 · 거울 qbo_entity 에 연락처 · 금액 칸을 더하지 마라(판정 933 · 934)
⭐  Intuit 의 응답 rows 는 scrub 하지 않는다(SyncToken 이 깨진다) — 토큰 scrub 은 오류 · 기록 글에만
⭐  IMS `_N_` 계정의 N = QBO Account.Id · COGS = #58(짐작 _100_ 은 틀렸다) · QBO 재고 추적 꺼짐(QuantityOnHand false — 원가는 분개로만)
⭐  보내기 때 opening_fix 원가 사건은 제외(판정 932 · Cin7 이 이미 COGS 를 보냈다) → [11-08 · 3-0 이견 4] 경계 = 「원가 사건이 컷 뒤 IMS 에서 생겼나」 · opening_fix 는 그 예외 하나
⚠️⚠️ [11-08 실측 · 정본 §15-f] EF query 응답 = { ok, entity, rows, count, totalCount, startPosition, maxResults, more, intuit_tid } · count(*) 는 totalCount
     **select * 는 MAXRESULTS 200 을 적어도 10 행만** · 쪽은 STARTPOSITION · **more 는 마지막 쪽에서도 true — 끝은 행 수 < 10 으로**(deferred 504) · Bill 응답에 VendorAddr 가 실린다(505)
⚠️  [11-08] Settings 콘솔에는 q · r 이 이미 선언돼 있다 — 콘솔 조회는 `(async () => { … })();` 로 감싼다 · 응답 꼴은 count 한 줄로 먼저 · 결과는 🚫 · Ctrl+L 로 비운 뒤 마지막 것만
```

## 5-c. ⭐⭐ 쓰기 · 보내기 일감 — 모르면 사고 (2026-11-01 밤 · 정본 §14 · 판정 935 ~ 946 · 951)

```
~~⚠️⚠️ [2026-11-03 밤 · 1034] **2e-2-1b EF 배포 전 cron 62(ims-qbo-send-payments) kinds 는 둘** — credit_apply · credit_apply_void 를 넣어 등록하면 지금 EF kindsOf(_shared/qbo.ts:808-814)가 400 → 결제도 안 나간다(조용한 멈춤) · cron.sql 실행 블록 = 둘 · 넷 판은 주석(배포 뒤 다시 등록)~~ → [11-04] 2e-2-1b 배포 뒤 cron 62 = **kinds 넷**(cron.sql 실행 블록 = 넷 · 둘로 되돌리면 크레딧 붙임이 조용히 멈춘다)
⚠️⚠️ [2e-2-1b 를 만들 때] entityKeyOf 의 ELSE = invoice — SEND_KINDS 에 credit_apply 를 넣으면 **명시 가지를 함께**(안 넣으면 크레딧 붙임을 invoice 로 읽는다)
⭐ 크레딧 붙임(2e-2-1 · 1009 · 1011 ~ 1017) = so_credit_alloc 한 줄마다 금액 0 Payment 한 장(Line = Invoice + CreditMemo) · 떼기 = void(operation=update&include=void) · 지문 없음 · CustomerRef = 인보이스 매장(so_invoice_store · 크레딧 매장과 다르면 failed · 1010) · 스위치 qbo_send_payments_enabled(결제와 같다) · 손 Send 는 p_kinds = SEND_KINDS 8 이라 2e-2-1b 전에는 credit_apply 를 잡지 않는다
⭐ qbo_job_claim 의 claimed = queued → sending 으로 바뀐 행 전부(뒤에 blocked · failed 로 간 것 포함) — 검증 기대값을 셀 때(so §99-c 5)
⚠️⚠️ 쓰기는 apiWrite 하나 — POST 만 · assertWriteAllowed(만들기 customer · item · invoice · creditmemo · void 는 invoice · creditmemo 만 · delete 없음) · requestid 필수
⚠️⚠️ 쓰기에 자동 재시도 없음 — 읽기 길(intuitCall)은 네트워크 · 5xx 재시도 → 쓰기에 쓰면 중복 · 결과를 모르면 qbo_job_unknown(보낸 이름을 남긴다)
     → 다음 send 첫머리가 그 이름(DisplayName · Name · 인보이스는 DocNumber)으로 GET 조회 · 하나면 done · 아니면 사람이 retry(note 필수) · skip
⚠️⚠️ retry 는 request_id 를 새로 — Intuit 은 같은 requestid 면 처음 응답(실패 포함)을 되돌려 준다
⚠️⚠️ qbo_send_enabled 는 cron 길 스위치뿐 — 손 send 를 막지 않는다 · 막으려면 열쇠를 끈다
⚠️  콘솔 조회에서 Customer · Vendor + 거래 다섯(Invoice · CreditMemo · Payment · SalesReceipt · RefundReceipt)은 select * 거부 — 칸 이름을 적는다(주소 · 이메일 칸도 거부)
⚠️  이름은 자동으로 바꾸지 않는다 — 손님 이름이 QBO Customer · Vendor 와 겹치면 실패 · Item 은 같은 이름이면 끝에 ` [SKU]` · 비활성 Item 만 있으면 실패(941 · 켜지 않는다)
⭐  몸(손님 · Item JSON)은 DB 함수(qbo_customer_body · qbo_item_body)가 만든다 — EF 에서 다시 짜지 마라(규칙이 SQL 로 시험된다)
⭐  2b 인보이스 판정: 손님 = 매장(935) · 주소 · 이메일 싣기(936) · 세금 IMS 값 그대로 · 합계 1 센트 달라도 실패(942) · 운임 할인은 운임 줄(943) · 그 밖 계정 charge 는 사람 짝(951)
⭐⭐ [2026-11-02 · 판정 971] **처음에는 북키퍼가 문서마다 확인하고 보낸다** — Sales → QuickBooks(qbo-send.html) 한 장씩 Preview → Send · Send selected(10 장씩) · Retry · Skip(메모 필수) · qbo_send_enabled **off 그대로**(cron 61 은 active 지만 where 가 걸러 호출 0 · 켜는 때는 Caleb)
     claim(p_limit, p_kinds, p_job_ids) — 고른 id 만 · requested[] 결과 · need_jobs · qbo_job_preview 는 need 일감을 **만들지 않는다**(claim 은 만든다) · QBO 호출 0 · retry 는 skipped 도(note 필수)
⚠️⚠️ [2b1] 942 「1 센트 달라도 실패」 → **sent + qbo_txn.mismatch 글 + 일감 warning**(이미 QBO 에 섰다 · 자동 void 없음 · 사람이 본다)
⚠️⚠️ 인보이스는 DocNumber 조회로 멱등(6140 / 6210 중복 번호 → 다시 찾아 짝) · void 는 POST operation=void(SyncToken 없으면 읽기 · 5010 → 다시 읽어 한 번)
⚠️⚠️ 일감은 트리거가 쌓는다 — 발행(AFTER INSERT DEFERRABLE · since 전 · 이월 · 연결 없음은 조용히 · 오류는 삼켜 발행을 막지 않는다) · 취소(안 나갔으면 skipped · sending · unknown 이면 void 를 blocked · 보냈으면 void queued) · since = 2026-11-02
⚠️⚠️ [960] 크레딧은 **자기 IMS 인보이스가 QBO 에 간 뒤** — 인보이스 일감 없음 · skipped → 크레딧 failed + 글 · 열린 일감 → blocked · 이월 인보이스 · 인보이스 없는 크레딧은 기다리지 않는다
⚠️  [961] 크레딧 other · restocking_fee 줄 = 계정 사람 짝(acct:<code> · 951 꼴 · 없으면 failed) · [962] 주소 · 이메일 = 크레딧 노트 PDF 규칙 · [963] CreditMemo void 거부 → failed · 사람이 QBO 에서 · [964] CreditMemo 만(붙이기 · 환불은 결제 차수)
⚠️  [2c1 · 2d1] 적용 순서 한 덩이 = 마이그레이션 → repair → EF 배포(DB 먼저 · 옛 EF 는 새 서명 기본값으로 그대로 돈다)
✅  짐작 풀림(11-02): QBO 캐나다판은 보낸 TxnTaxDetail(TaxLine)을 **존중한다**(60000 → 172335 세금 · 합계 그대로) · 1 장 = Intuit 2 호출 · 3.52 s · 60001 미리 보기 = Item CB-CVT18157 먼저 만든다(need)
⭐⭐ [2026-11-02 밤 · 판정 978 · 980 · 981 · 988 · qbo-sync-2e-1b · 1c · 정본 §14-f] **결제 하나(so_payment 한 줄) = QBO Payment 한 장** · CustomerRef = **청구처**(본사가 매장 인보이스 여럿을 수표 하나로 → 본사 Payment 한 장 · Line = 매장 인보이스 · 980) · 붙임이 바뀌면 **옛 Payment void + 통째로 다시**(update 길 없음 · 978) · IMS 에 적힌 결제는 모두 IMS 가 보낸다(981)
     **붙은 인보이스가 모두 QBO 에 간 순간 자동**(988 · cron 62 · 스위치 **qbo_send_payments_enabled** — 결제만 · qbo_send_enabled(971 · 인보이스 · 크레딧)와 별개) · 지문 qbo_payment_fingerprint 가 같으면 아무것도 안 한다
⚠️⚠️ Payment void 꼴 = `POST payment?operation=update&include=void` {Id, SyncToken, sparse}(invoice · creditmemo 의 operation=void 가 아니다 · assertWriteAllowed 가 payment 에만 연다) · 응답 TotalAmt 0 · Line [] · PrivateNote 「Voided - 」 · ⚠️ DepositToAccountRef 를 안 주면 QBO 가 26 으로 채운다 — 몸은 늘 계좌를 싣는다
⚠️⚠️ (가) Balance 가드 — POST 직전 붙은 인보이스마다 GET 해 Balance < 줄 금액 · 못 읽음이면 **failed · 보내지 않는다**(QBO 에서 누가 이미 받았다) · 결제 하나 = Intuit 1 + 붙은 인보이스 수
⚠️⚠️ 결제는 DocNumber 가 없다 — unknown 열쇠 = `qbo_job.qbo_name` **한 칸**에 「<PrivateNote>|<CustomerRef>|<TxnDate>|<TotalAmt>」(PrivateNote = 「IMS payment <uuid>」 · void 는 Payment Id) · 풀기 = 그 날 Payment 조회 → 하나 done · 0 · 둘 이상은 사람
⚠️  PaymentMethodRef 짝이 없으면 failed — credit_card 는 QBO 수단 하나(983)를 사람이 짝지을 때까지 · 짝 뒤 failed 를 queued 로 되살리는 것은 1d(deferred 452) → [11-05 · 1039] 섰다(수단만 · 5-d)
⚠️⚠️ **켜는 순서(Caleb · deferred 453)**: ① Settings 에서 credit_card QBO 수단 짝 ② Sales → QuickBooks → Payments 몇 장 Preview → Send ③ cron 62 ims-qbo-send-payments 등록(ops/cron.sql · jobid 실측) ④ qbo_send_payments_enabled on — ⚠️ 그 전에 화면 Send 를 누르지 마라(스위치는 자동만 막는다)
   → [2026-11-03 밤 · 판정 1034 · Caleb 「첫 작업으로 결제를 켜자」] **2e-2-1b 보다 먼저** · 켜기 전 확인(EF 판 · 대기 결제 일감 수) → Preview → Send → QBO 잔액 확인 → cron 62 등록 **kinds 둘**(비밀값 Caleb) → 스위치 on → 첫 회차 보기 → cron.sql 에 jobid 실측 · 커밋
⚠️  Cin7 수단 정정(so §98-c 1): 「Cin7 은 결제 수단 전부 Cash」 는 틀렸다 — 카드 · Debit · E-Transfer · EFT · Cheque 는 갈라 보냈고 Cash 는 Shopify · PayPal · 현금뿐 · 입금 계좌 = Cin7 꼴(수표 _105_ · PayPal _124_ · Shopify _1150040029_)
⭐⭐ [2026-11-04 · 2e-2-1b `48d5ca4` · 정본 §14-g] 크레딧 붙임 보내기 — 모르면 사고:
   · **0 원 Payment 는 계좌 없음** — 응답에 DepositToAccountRef 가 없다(결제와 다르다 · 대조하지 마라)
   · unknown 풀기 = PrivateNote **완전 일치**(「IMS credit applied <alloc uuid>」) + void 된 Payment 제외 — 0 원은 void 뒤에도 0 이라 includes · 접두로 고르면 옛 void 를 잡는다
   · need(먼저 만들 것)는 **customer · item 만** — sendPicked 는 그 밖의 kind 를 need 로 건너뛰지 않는다(isNeedKind)
   · 가드 = Invoice Balance ≥ a ∧ CreditMemo RemainingCredit ≥ a · check_lines 가 Invoice 하나 + CreditMemo 하나가 아니면 failed · void 는 결제 길(payment_void 조건에 `|| credit_apply_void`) · PAYMENT_KINDS 무변(CREDIT_APPLY_KINDS 따로)
   · 이월 인보이스에 붙은 크레딧은 failed(1016 · 1d 뒤 requeue — 11-04 CR-01014 → 50763)
⭐⭐ [2026-11-04 실측 · 정본 §14-f 「켜짐」] 결제가 **Blocked** = 앞선 인보이스 · 손님 일감이 아직 queued — 인보이스는 북키퍼가 골라 보내므로(971 · qbo_send_enabled off) 그 인보이스를 보내기 전까지 결제는 기다린다(부모 sent 뒤 cron 62 가 잡는다) · **Failed** 「Invoice N was carried over …」 = 이월 인보이스(1d · 452) · 17:56 payment sent 95 · blocked 37 · failed 7 · skipped 6
⭐ cron 62 열쇠는 화면 · 대화에 꺼내지 않는다 — ims-mail-drain command 에서 SQL 로 substring → format(%L) 로 끼운다(ops/cron.sql 머리 · 11-04)
```

## 5-d. ⭐⭐ 이월 인보이스 짝 · 하위 손님 · 글자 한도 — 모르면 사고 (2026-11-05 ~ 06 · 정본 §14-h · §14-i · 판정 1039 · 1044 ~ 1047 · 1054)

```
⭐⭐ 이월 인보이스(kind opening)는 다시 보내지 않고 QBO 의 그 장과 **짝**만 짓는다(qbo_txn source matched · match_how auto | manual · match_snapshot)
     자동 다섯 조건(qbo_opening_check): DocNumber 완전 일치 ∧ 한 장 ∧ CustomerRef ∈ {매장 · 청구처 짝 · 그 parent_id} ∧ TotalAmt = total ∧ Balance = total − prior_settled − IMS 가 보낸 붙임
⚠️⚠️ 문 = 열쇠 QUICKBOOKS(1044 · 북키퍼도 · admin 도 열쇠) · EF opening_candidates · opening_read · opening_search 는 KEY_ACTIONS(ADMIN 아님)
⚠️⚠️ 사람 짝 전에 peek(opening_read peek:true · 쓰기 0) → 경고는 ack(1046) · 번호가 다른 장은 opening_search(DocNumber like · 3 ~ 30 자)
⚠️⚠️ 풀기(qbo_opening_unmatch) = matched 행 **삭제** — sent 행은 절대 아님 · 보낸 것 있으면 거부 · 흔적은 qbo_opening_review(1045)
⚠️⚠️ 결제 되살림(qbo_payment_requeue_one)은 **그 결제의 남은 이월 장이 0 일 때만** — 아니면 failed 그대로 · 글 「N carried-over invoice(s) …」
⚠️  수단 짝(qbo_link_set payment_method)이 서면 그 수단의 failed 결제를 queued 로(1039) — **손님 짝은 되살리지 않는다**(손님 짝 뒤 Retry · deferred 472)
⚠️  사람 짝 9 장의 꼴: QBO TotalAmt = IMS total − prior_settled(Cin7 이 몇 달러 정산을 금액에서 빼 넘김) — 자동 조건 TotalAmt = total 에 안 걸린다 · peek 로 보고 ack
⭐  1047: 「잇기만 · 안 보내기」 없음 — QBO 에 이미 기록한 결제는 IMS 에 또 적지 않는다 · 컷 뒤 새 결제는 IMS 에만(북키퍼는 QBO 에서 Payment 를 만들지 않는다 · 981)
⚠️⚠️ **QBO 하위 손님** — 본사(청구처)가 낸 결제가 매장 인보이스에 붙으려면 QBO 에서 매장이 본사의 BillWithParent 하위 손님이어야 한다 · IMS parent_id 와 따로다
     안 묶였으면 failed 「TxnID Cannot Be Linked : <Id>」 → QBO 에서 묶고 Retry(코드로 고칠 일 아님 · 실물 CHQ #15033)
⚠️⚠️ **QBO 칸 글자 한도** — 인보이스 TrackingNum **31 자**(다상자 송장 「, 」 잇기 38 ~ 218 자 → failed 6 장) ⇒ 1054: TrackingNum = 첫 오더 첫 송장 · 전체는 CustomerMemo 둘째 줄 「Tracking: …」(1,000 자 자르기 · 손님에게 보인다) · PrivateNote 무변
     새 칸을 몸에 실을 때는 QBO 한도를 먼저 본다 — 넘으면 Intuit 이 장 전체를 거부한다
⚠️  고친 뒤 Retry 는 queued 로 돌아갈 뿐 — 인보이스는 qbo_send_enabled off(971)라 Send 를 눌러야 나간다
⚠️  `customer` 표에 email 칸이 없다(연락처는 customer_contact) — row_to_json(c)->>'email' 비교는 null = null 로 「같다」 가 나온다(so §101-e 89)
```

## 5-e. ⭐⭐ 이월 받아 둔 돈 붙임 · 북키퍼 손 분개 · 대조 기준 — 모르면 사고 (2026-11-07 · 정본 §14-j · so-module §102 · 판정 1056 ~ 1062)

```
⭐⭐ 이월 받아 둔 돈(so_payment method opening · Cin7 과입금 · 보증금)은 QBO 에서 AR 이 아니라 **Customer Credits(1150040009)** 에 있다(Cin7 이 Sales Receipt · Item 5624 「Customer Credit」 으로 보냈다 · 1059 실물)
     ⇒ 컷 뒤 인보이스에 붙은 이월 돈 한 줄 = QBO **두 장**: 「쓰기」 CreditMemo **OC-<인보이스>-<n>**(Item = qbo_link charge acct:<결제 계정> · Customer Credits → AR) + **0 원 Payment**(CreditMemo 를 인보이스에 잇는다 · PrivateNote 접두 「IMS opening credit applied 」)
⭐⭐ 일감 kind 넷 opening_credit · opening_credit_void · opening_apply · opening_apply_void — 기다림 = 인보이스 → credit → apply(blocked 사슬) · qbo_txn ims_kind 둘(opening_credit ↔ CreditMemo · opening_alloc ↔ Payment) · 트리거는 qbo_job_on_payment_alloc 본문(새 트리거 0)
⚠️⚠️ **CustomerRef = 돈의 주인** — 인보이스 매장과 다르면 failed(QBO 하위 손님이면 경고) · 2e-2 의 「CustomerRef = 매장」(1014) 과 다르다
⚠️⚠️ EF SEND_KINDS **14** · 새 갈래 0(credit · credit_void · credit_apply · payment_void 길에 조건 여덟) · entityKeyOf 명시 가지 넷 · **cron 62 kinds 여덟**(11-07 05:40 UTC · jobid 62 그대로 · ops/cron.sql 실행 블록 = DB) — 둘 · 넷 판으로 되돌리면 opening_* 가 조용히 멈춘다 → [2026-11-08] SEND_KINDS **18** · cron 62 kinds **열둘**(아래 5-f)
⭐⭐ 가드 둘 = ① 보내기 직전 QBO 다시 읽기(Invoice Balance ≥ a · CreditMemo RemainingCredit ≥ a · 아니면 failed 「QuickBooks already shows … paid on invoice N」) ② 모르면 unknown(apiWrite 재시도 없음) — 60189 에서 ① 이 실제로 중복 쓰기를 막았다
⚠️⚠️ **1060** 북키퍼가 이월 돈을 손 분개(Journal Entry · Customer Credits ↔ A/R)로 먼저 정리한 것이 보이면 = QBO 에서 분개 **Delete**(Reverse 아님 — Reverse 는 AR 에 받을 돈을 새로 만든다) → 인보이스 잔액 확인 → IMS **Retry**(IMS 가 기록 주인) · OC CreditMemo 를 void 하는 길은 기각(IMS 가 모르는 분개가 기록으로 남는다)
⚠️⚠️ **1061** 북키퍼는 이월 크레딧 분개를 손으로 넣지 않는다(981 · 1058 의 예외가 실제로 있었다 = 60189) — 10/30 뒤 손 분개는 지운다 · 붙임 성공 6 건 · 대기 3 건(60257 · 60258 · 60282)의 Audit log 확인(deferred 496)
⭐⭐ **QBO 와 IMS 대조의 기준 = 손님 잔액(QBO Open Balance = IMS Available)** — 구성이 달라도 잔액이 같은지부터 · 어긋나면 QBO 거래 목록 · Audit history(거래 화면 More → Audit history · 회사 전체 톱니바퀴 → Audit log)를 **먼저** · 「Automatically apply credits」 짐작은 기각(985 off)
⚠️  QBO 북키퍼 사용자 이름은 ims_staff 의 북키퍼 이름과 다르다(1062 · 같은 사람인지 짐작 · 공개 레포라 이름은 안 적는다 · Audit log Filter User 로 찾는다)
⚠️  sent 일감에도 옛 last_error 가 남는다(sent 489 중 37 · deferred 486) — 화면 · 쿼리의 옛 실패 글을 지금 상태로 읽지 마라 · qbo-send 화면은 opening 넷 이름표가 아직 원래 이름(495)
~~환불 2e-3-2 는 아직(454 남은 몫): 1056 보내기 기준 = 결제일(paid_on) 컷(10-30) 뒤만 · 1057 QBO 꼴 = Expense · 정산 계좌 · 줄 Customer Credits + 손님 · 1058 북키퍼는 환불도 손으로 안 넣는다 · 보내기 전 「QBO 에 손 기록이 이미 있나」 확인 길을 함께~~ → [2026-11-08] 크레딧 노트 몫은 나간다 — 아래 5-f(1065 가 1057 을 바꿈 · 크레딧 몫 = A/R 줄)
```

## 5-f. ⭐⭐ 환불(크레딧 노트 몫) — 모르면 사고 (2026-11-08 · 정본 §14-k · so-module §103 · 판정 1065 ~ 1075)

```
⭐⭐ 환불 한 줄 = QBO **Purchase(Expense) 한 장** + **0 원 Payment 한 장**(Purchase 와 CreditMemo 들을 잇는다 · LinkedTxn TxnType "Expense") — 1065 · 1071
     줄: 크레딧 노트 몫 = **A/R** 줄 + CustomerRef(손님 잔액 +a → CreditMemo 로 상쇄) · 이월 돈 몫 = Customer Credits 줄(지금은 안 짓는다) · 세금 = Out of Scope (Purchase) 짝(운영 4 · 1073)
     kind 넷 refund · refund_void · refund_apply · refund_apply_void — 열쇠는 모두 so_payment.id 하나 · 트리거 so_payment_refund_qbo(AFTER INSERT · deferred) + status 가지
⚠️⚠️ **보내는 것은 크레딧 노트 몫만** — refund_from_account > 0(받아 둔 돈 몫)이면 환불 **통째로 failed**(반쪽 금지 · 1067) · 환불된 이월 결제를 쓰는 opening 붙임도 failed(1066) · 둘 다 「환불을 결제에 매기」(deferred 500) 전까지
⚠️⚠️ **컷 = paid_on 고정 date '2026-10-30'**(1068) — qbo_send_since(발행 기준) · created_at 재사용 금지 · 컷 전 8 건(2,310.30)은 QBO 에 이미 있어 일감 없음 · 그걸 IMS 에서 void 하면 refund_void failed 알림(Retry 거부 → Skip · 1070) · 11-08 뒤 created ∧ 컷 전 paid_on → failed 「check QuickBooks, then Retry or Skip」(1069)
⚠️⚠️ **void 순서** = 잇는 Payment void 먼저 → Purchase 다시 읽어 SyncToken → **Full update**(모든 줄 0 + PrivateNote 「Voided - 」 · Purchase 는 Void 메뉴 · Delete 없음 · 금액 0 만으로는 Voided 아님) · 읽은 Purchase 에 LinkedTxn Payment 가 남아 있으면 failed(1072 · 1074)
⚠️  잇기 · 풀기가 Purchase · CreditMemo 의 SyncToken 을 올린다 — 쓰기 전에 다시 읽어라(5010) · Purchase query 는 TxnDate 만(EntityRef · PrivateNote 4001) ⇒ 손 기록 가드는 TxnDate ±7 일을 읽고 EF 가 거른다
⚠️⚠️ **Purchase 의 열린 금액은 Purchase 에서 못 읽는다** — Payment 응답의 **txnOpenBalance = 잇기 직전** 값 ⇒ after = txnOpenBalance − Amount · Expense 줄 |after| > 0.004 경고 · CreditMemo 줄은 모자람만(1075 · 1b2) · 시험 가짜도 「직전」 값을 줘라(1b 가짜가 뒤 값을 줘서 거짓 경고 「not all 0」 이 시험을 지났다 · 172913 · 172915)
⭐  EF SEND_KINDS **18** · assertWriteAllowed purchase 몸 검사(만들기 · void 꼴만 · 다른 엔티티는 deferred 501) · **cron 62 kinds 열둘**(11-08 · 실행 블록 = DB 글자 그대로 · 열쇠는 그 job 자신의 command 에서)
⭐  화면 qbo-send(qs refund v1 · v1a): 종류 Refunds · Carried-over money · 「Refund linked to credit」 은 Refund 먼저 또는 둘을 함께 보낸다(blocked 사슬)
⭐  [2026-11-09 · 판정 1114] 받아 둔 돈을 크레딧 노트 없이 돌려준 환불(오버페이) · USD 환불은 **짓지 않는다**(드묾) — 생기면 IMS failed 그대로 · 북키퍼가 QBO 에 손으로 + IMS 줄 Skip(「QuickBooks 에 손으로 넣음」) · deferred 500 · 511 열림
~~⚠️  USD 손님 셋의 A/R 계정이 `_61_`(CAD) — USD 환불은 failed(통화 ≠ 기본 통화 · deferred 499)~~ → [2026-11-08 밤 · 3-1] A/R 은 `_212_` 로 바로잡음(499 닫힘) · ⚠️ USD 환불 failed 는 그대로 — 블록이 so_payment 통화를 본다(511 · §5-g)
```

## 5-g. ⭐⭐ 원가 · 공급처 줄기(459) — 판정 끝 · ~~짓기 전~~ → 3-2a 적용(11-09) · ~~다음 3-2b~~ → 3-2b · 3-3 · 3-4 끝(11-09) · ~~다음 공급처(4-0)~~ → 공급처 판정 끝 · ~~다음 4-3~~ → 4-3 · 4-4 · 첫 송신 끝 · ~~다음 4-5(11-09)~~ → 4-5 끝 · 첫 BillPayment 173092(11-09 밤) · → 4-7 할인 결제 끝(11-10 · §15-o) (2026-11-08 저녁 · 정본 §15 · so-module §104 · 판정 1080 ~ 1090)

```
⭐⭐ 상품 공급처 Bill · 그 결제(BillPayment)는 **IMS 가 보낸다**(1080 · 1081) — 북키퍼는 운영 비용 Bill 만 QBO 에서 · 컷 전 Bill 결제는 QBO 에서(913) · 밀린 IMS 인보이스 7 장 · 결제 4 건은 싱크가 서면 원래 날짜로
⭐⭐ 판매 원가 = **하루 · 창고마다 JE 한 장 + SO 마다 줄**(차 #58 / 대 #59 · 줄 설명 SO 번호 · 1082) · 늦은 변동은 다음 장에 그 SO 줄 · 밀린 몫은 11-02 부터 그날 날짜로(1083)
     cost_late 팔린 몫 → #58 · 남은 몫 → #59(1084) · 창고 간 트랜스퍼는 하루 장에 In Transit #1150040007 ↔ #59(빈 이동은 안 보냄 · 1085) · 조정 계정 빈칸 = 기본 #1150040010(1087)
     비용 Bill: 관세 #134(세금 없음) · 수입 GST = #125 줄(세금 코드 아님 · 원가 아님) · 통관 #135 · 운임 #136(1089) · 관세 「금액 0 · 세금만」 은 정상 꼴
⚠️⚠️ **출발점은 맞추지 않는다 — 움직임만**(1086) · 월 검산 = 그달 #59 움직임 = 그달 IMS 재고 금액 움직임 · 잔액 차이 약 150 만은 알려진 차이 · **오래된 재고 write-off 를 일반 조정으로 보내지 마라**(QBO 에서 두 번 빠진다 · 503)
⚠️⚠️ **살린 트럭 TR-06396 ~ 06399 도착은 보내지 마라**(출발 분개가 QBO 에 없다 · 보내면 In Transit −15,159 · 1085)
⚠️⚠️ **10-30 판매 원가는 이미 QBO 에 있다**(Cin7 · JE 81 장 · 토론토 17:33 · 1083) — 밀린 몫 경계는 11-02 · cost-fix-1(opening_fix · carried)은 보내지 마라 · 조정은 10-31 부터(1090)
~~⚠️  CAD 공급처 11 곳 A/P 가 `_109_`(USD) · 기본값도 `_109_` 하나 — 3-1 에서 통화별 기본 + 저장 거부(1088 · 손님 A/R 499 와 같이)~~ → 아래 ✅ 줄(3-1 끝)
⚠️  API 는 손익 계정(#58) 잔액을 0 으로 준다 — 원가 검산은 기간 보고서로 · #59 잔액은 하위(In Transit · GRNI · GINR) 제외 값과 포함 값이 따로 → 월 검산 QBO 쪽은 **하위 제외**(포함 값에는 안 받은 Bill 의 GINR 이 섞인다 · deferred 533)
✅ [2026-11-08 밤 · qbo-sync-3-1 `b7bb430` · 정본 §15-g] **계정 통화 = 상대 통화**(1091) — `ref_account.currency_code`(null = CAD · A/P · A/R 통제 계정만 · `_109_` · `_212_` USD · `_203_` KRW · FK 없음)
     막기 = 지연 제약 트리거 `supplier_account_currency_ck` · `customer_account_currency_ck`(창구 · 적재 · 손 SQL 모두) + 창구 넷 block `currency_account_mismatch` · 기본 키 통화별(`supplier_default_account_payable_code_cad` · `_usd` · `customer_default_ar_account_code_cad` · `_usd` · KRW 키 없음) · 499 닫힘
     ⚠️ 조정 계정은 **`inv_adjust_account(adj)` 하나만 읽는다**(빈칸 = `inv_adjust_default_account_code` `_1150040010_` · 1087) — account_code 를 직접 읽어 기본값을 따로 짜지 마라
     ⚠️ qbo_refund_block 은 so_payment 통화를 본다 — 499 를 고쳐도 USD 환불 failed 그대로(511)
⭐⭐ [2026-11-08 밤 · 3-2-0 · 판정 1092 ~ 1103 · 정본 §15-h] **하루 원가 장 설계 끝** ~~· 짓기 전(다음 3-2 DB)~~ → 아래 3-2a 줄
✅ [2026-11-09 · qbo-sync-3-2a `0228bd0` · 정본 §15-i] **적용 20261108170000 · 확인 44/44 · cron 미등록(3-2b 때 · cron.sql 은 3-2b 와 함께)** · 스위치 `qbo_send_cost_enabled` off · 장 0 장
     ⚠️ 장 만들기는 `qbo_cost_sheet_build_due`(cron 몸) · 미리 보기 `qbo_cost_preview` 로만 — 새 표 셋은 RLS + grant 0(창구만) · 일감 · claim · 재생성 hold · resolve 는 3-2b · 3-2b 전에 cron 을 등록하지 마라(장이 3-2b 규칙과 어긋난다)
     ⚠️ 열쇠마다 **부호 있는 한 짝**(restock + 취소가 같은 CR 에서 상계) · 「그 창고 #59 만 순액 한 줄」 · 상수(창고 코드 · 제외 문서 · 비용 종류 → 계정)는 inv_config 가 아니라 함수 · 「한 장 최대 열쇠」 는 보낼 54 + 보류 2(56 은 사건 열쇠)
⚠️⚠️ **트랜스퍼는 소진 줄로만 센다** — carried 얹기의 occurred_on 은 원래 얹힌 날(트랜스퍼가 옮겨 적어도 옛 날짜)이라 날짜로 세면 값이 옛 날짜 · 다른 창고로 샌다 · 트랜스퍼 복사 carried 는 세지 않는다
⚠️⚠️ **경계는 날짜가 아니라 출처** — `inv_ledger.source='ims'` 문서의 사건 + IMS 비용 문서(charge_number)의 얹기 · 늦은 원가 − 제외 목록(opening_fix 가족 · 살린 트럭 TR-06396 ~ 06399 도착 · 1090 구현 규칙)
⚠️⚠️ **모르는 원가 칸이면 장을 막는다** — 정본은 DB 제약 22 칸(origin 8 · reason 8 · kind 6) · 제약이 넓어지면 막고 알린다 · `lost` 는 막음(512) · 입고 · price_adjust · settlement_discount 는 보류(Bill 차수) → [2026-11-10 · 1149 · 4-7a] settlement_discount 는 이제 send(보류 아님)
     판정 요지: 보낸 몫 = 문서 번호 · 계정 짝마다 **센트 합**(원가 줄 id 없음) · 다음 장 = 지금 셈 − 보낸 합의 차액(1092) · 재생성(`inv_layer_apply`)이면 보내기 멈춤 → 사람이 풀면 「IMS cost rebuild」 한 장(1093) · sale_shortfall = 차 #59 / 대 #1150040010(1094) · 늦은 원가 조정 몫 = 그 조정 계정(1095) · 입고는 보류 · 짝 GINR 하나 · GRNI 는 IMS 가 안 씀(1096 · 판정 88) · 줄 = 열쇠마다 한 줄 + 짝 계정 모음(합 = 줄 반올림 합) · 손님 이름 글자 안 실음(1097) · `qbo_send_cost_enabled` off · SQL cron 03:00 전날 몫 · 처음엔 손 Send · 창고마다 차례 · failed · unknown 이면 뒤 장 멈춤(1098) · 조정 한 건 문턱 1,000 넘으면 보류(1099) · transfer_freight 짝 = 비용 문서 종류 · 모르면 #136(1100) · 두 장 서면 QBO 에서 지우고 IMS skip · JE 는 만들기만(1101) · Location 안 실음 · DocNumber `COGS-YYYYMMDD-TOR` · `-EDM`(1102) · SO 줄 Entity = 인보이스 손님 · CR 줄 = 크레딧 노트 손님 · #59 모음 줄은 안 검(1103)
     QBO 마감일 2026-08-31(회계연도 9 월 시작) — 10 월 날짜로 보낼 수 있다 · landed 날짜 = IMS 가 얹은 날(507 닫힘)
✅ [2026-11-09 · 3-2b `2fbed9d` · 3-3 `232dec7` · 정본 §15-j · §15-k] **하루 원가 장 = 일감 kind `cost_day`(ims_kind cost_sheet · ims_id 'YYYY-MM-DD|TOR') · QBO JournalEntry** · 적용 · EF 배포 · cron 67(장 행만) · 장 0
⚠️⚠️ **원가 장을 cron 61 · 62 에 섞지 마라** — EF `DEFAULT_SEND_KINDS` 18(kinds 없음 = cost_day 뺌) · 손 Send(sendPicked)만 19 · 원가 보내기 cron 은 주석 블록뿐(kinds [cost_day, customer] — customer 는 큐의 **모든** 손님 일감을 보낸다 · 등록은 Caleb · deferred 522)
⚠️⚠️ **journalentry 는 만들기만** — `assertWriteAllowed` 가 지우기 · void · 몸에 Id 있는 POST 를 막는다 · QBO 는 JE DocNumber **중복을 막지 않는다**(sandbox) ⇒ 막는 것은 보내기 직전 DocNumber 조회 가드뿐 — 0 행 POST · 조회 실패 failed · 1 행 이상 **unknown**(failed 로 보내면 트리거가 보낸 몫 행을 지워 resolve 길이 닫힌다)
⚠️⚠️ **JE 응답 TotalAmt 는 0** — done 금액은 Debit 줄 합(journalDebitCents) · TotalAmt 로 대조하지 마라
⚠️⚠️ **1112 — 자동 done 은 금액이 같을 때만** · QBO 에 같은 DocNumber JE 1 행이면 GET 해서 Debit 합 = 일감 차변(claim 때 고정)일 때만 done · 다르면 unknown 그대로 · 2 행 ambiguous · 열쇠 = qbo_name `<DocNumber>|<차변 센트>`(EF 만 · 센트 없으면 자동 없음) · cron 62 의 풀기가 kind 를 안 가려 cost_day unknown 도 이 규칙으로 푼다
⚠️  줄 고정은 **claim 때**(qbo_cost_sent) · 창고마다 차례(앞 장이 sent · empty · void 가 아니면 wait) · 재생성 감지면 realm 의 미보낸 장 전부 hold → rebuild_preview · release(`COGS-<날>-TOR-R`) · unknown 장은 `qbo_cost_sheet_resolve(in_qbo | not_in_qbo)` · 손님 짝 없는 SO 가 든 장은 그 손님이 QBO 에 생길 때까지 기다린다(Caleb)
⚠️  인보이스 자동 보내기(qbo_send_enabled)는 **당분간 off**(Caleb 11-08) · 다음 줄기 = 공급처 쪽(qbo-sync-4-0 조사 · 1080 · 1081 · 1089 · 1096)
⭐⭐ [2026-11-09 · 판정 1115 ~ 1130 · 정본 §15-l · so-module §108] **공급처 쪽 판정 끝 · 짓기 전**(다음 4-3 DB Bill · VendorCredit · 11 월 안) → [11-09 오후] 4-3 · 4-4 지음 · 운영 sent(아래 ✅ 줄)
⚠️⚠️ **Bill · VendorCredit · BillPayment 는 #59 · #58 을 건드리지 않는다**(1115) — Bill = 차 GINR `_1150040012_` / 대 A/P · 재고 · 판매 원가 계정은 하루 원가 장만 · 할인 · 가격 크레딧도 VC 는 A/P ↔ GINR, #59 · #58 은 원가 장 CADJ(1121 · 「할인」 = 둘 다: 가격 크레딧(credit_reason price_difference → price_adjust) = **4-3** VendorCredit 문서 · 조기 결제 할인(discount_taken → settlement_discount) = **4-5** 결제 저장 때 VendorCredit + BillPayment 에 붙임)
⚠️⚠️ Bill 몸에 **반드시** — `APAccountRef`(공급처 A/P · USD = 운영 #109 · 빼면 QBO 가 제 기본 USD A/P 를 고른다 — sandbox 는 스스로 만들었다) · `DueDate`(po_invoice.due_date · 빼면 TxnDate) · `TxnTaxDetail`(IMS 세금 — QBO 는 보낸 세금을 그대로 받고 다시 셈하지 않는다) · USD `ExchangeRate` = po_invoice.exchange_rate(비면 막음 · 1118) · 줄 = 인보이스 줄마다 · 인보이스 할인 = 음수 줄(1116 · 1117)
⚠️⚠️ **DocNumber 최대 21 자**(25 자 → 2050 「Max:21」) — 넘으면 앞 21 자 + 전체 번호는 PrivateNote(1130)
⚠️⚠️ **QBO 는 같은 Vendor 같은 DocNumber Bill 을 막지 않는다**(sandbox 203) ⇒ 보내기 직전 조회 가드 필수 · unknown 자동 done = 같은 Vendor + DocNumber + 합계(Bill 통화 센트) **한 장**일 때만(1127) · done 대조는 USD TotalAmt(응답에 HomeTotalAmt 없음)
⚠️⚠️ **Bill 에는 void 가 없다**(Create · Delete · Query · Read · Full update) — IMS 취소 = 일감을 「QuickBooks 에서 손으로 지워 주세요」 로 멈춤 → 북키퍼 삭제 → Skip · **API delete 쓰지 마라**(1126) · IMS 결제 삭제 = BillPayment void(1125 · ~~sandbox E-13 미확인~~ → 4-2b 확인 · 4-5b 지음)
⚠️⚠️ **새 kind 를 SEND_KINDS 에 넣으면 cron 61 기본에 저절로 들어간다**(`DEFAULT_SEND_KINDS = SEND_KINDS − cost_day`) — 공급처 kind 도 DEFAULT 에서 뺀다 · `entityKeyOf` ELSE = invoice · `qbo_job_pair_ck` ELSE = ims_kind ⇒ 새 kind 는 명시 가지
⚠️⚠️ **ims_kind `invoice · credit · payment · charge` 는 SO 쪽 것** — 공급처는 다른 이름(4-3 이 정함 · ~~안~~ → 실제 ims_kind `supplier · po_invoice · po_credit · po_charge · po_payment` · 공급처 결제 kind `bill_payment` · `bill_payment_void` — `payment` 를 쓰면 cron 62 가 5 분마다 내보낸다(아래 [2026-11-09 밤 · 정본 §15-n · so-module §110] 줄))
⚠️  Vendor 가 없으면 IMS 가 만든다(1128 · DisplayName + CurrencyRef 만 · A/P 안 실음 · 같은 이름 있으면 failed — 자동 개명 금지) · 결제 하나 = 공급처 하나(1124) · USD 결제 환율 = 그 돈을 산 날 MTFX 환율 필수(1123) · 결제 통화 ≠ 계좌 통화면 거부(1122)
⚠️  입고 보류는 공급처 차수가 서면 무조건 풀고 **입고 날짜 장**에(1119 · 1120) — **TOR 원가 장은 11-04 까지만 먼저 보내라**(11-05 · 11-06 에 RCV 두 줄) · 원가 보내기 cron(522)은 4-3 뒤 · Bill HomeBalance = 합계 × 환율이라 IMS 입고 원가(줄마다 반올림)와 센트 차 = 정상
⚠️  「#138」 은 수표 번호가 아니라 **계좌 Id 138 MTFX USD**
✅ [2026-11-09 오후 · 4-3 `32f2f3e` · 4-4 `b879381` · 3-3b `f1fb21b` · 정본 §15-m · so-module §109] **Bill 7 장 · 원가 장 12 장 운영 sent** · BillPayment 0(4-5) · 자동 없음 — 북키퍼가 매일 손 Send
⚠️⚠️ **QBO query 에서 고를 수 없는 칸(4001 「Property X not found for Entity Y」)** — JournalEntry `TotalAmt`(3-3b · 첫 원가 장이 가드에서 failed · QBO 쓰기 0 → JE 가드 = `select Id, DocNumber`) · BillPayment `PayType` · Bill `HomeBalance`(GET 에는 옴) · 코드 `QUERY_UNSELECTABLE` 은 ~~지금 앞 둘 — **셋째는 4-5 에서 더한다**~~ → 셋 다(4-5b `16412bc` · `qbo.ts` 793) · 가드 조회에 새 칸을 넣기 전에 이 표부터
⚠️  공급처 kind 셋(vendor · bill · vendor_credit)은 DEFAULT_SEND_KINDS 밖(cron 61 에 안 섞임) · `bill_delete_manual` 은 EF 가 집지 않는다(사람 삭제 → Skip) · 매입 세율이 거울에 없으면 Bill 몸이 막힌다 → Settings → QuickBooks matching → Refresh list(tax codes)
⚠️  기한 빈 공급처 인보이스 = DueDate 인보이스 날짜 + 경고(1131 · `qbo_bill_body`) → QBO 에 Overdue 로 보인다 · IMS 는 보낸 Bill 을 고치지 않는다 · 보낸 Bill 은 4-5 전까지 QBO 에 미지급 — 북키퍼가 QBO 에서 결제하면 두 번(1081) → [2026-11-10 · 1144 · 4-7a] 지급 기한은 결제 조건에서 자동(트리거 · `due_date_manual` 이 사람 값 지킴) · 확정 경고 `due_date_missing` · `due_date_differs_from_term`
⚠️⚠️ **4-5 BillPayment 규칙(4-2b sandbox)** — 외화 결제는 **`CurrencyRef` 반드시**(`ExchangeRate` 만이면 2410 「Currency is missing」) · 환율은 그대로 받고 환차손익은 QBO 가 셈(1123) · 결제 줄 = 붙임마다(부분 · Bill 둘 됨) · **PayType 은 IMS 계좌 종류로**(카드 = `CreditCard` + `CreditCardPayment.CCAccountRef`) · 수표는 **`PrintStatus NotSet` 반드시**(기본 NeedToPrint) · void = 「Void a billpayment」 몸 `{Id, SyncToken, sparse:true}`(응답 TotalAmt 0 · Line [] · PrivateNote 「Voided - 」 · Bill 다시 열림 · 1125 확정) · **Bill 의 LinkedTxn 이름(`BillPaymentCheck`)으로 결제 종류를 가르지 마라**(카드 결제도 그 이름) · E-8(VC 붙이기)은 미확인 — 할인 있는 결제는 막고 사람에게(~~짐작~~ → 판정 1132 · deferred 538)
✅ [2026-11-09 밤 · 정본 §15-n · so-module §110] **공급처 결제 BillPayment 가 나간다 — 손 Send 만** · 첫 실물 173092 · 4-5a 적용 · 4-5b 배포 · 4-5c 화면
⚠️⚠️ **kind 이름 = `bill_payment` · `bill_payment_void`(ims_kind `po_payment`)** — `payment` · `payment_void` 는 손님 것이고 cron 62 kinds 에 있다(`qbo_send_payments_enabled` on) ⇒ 같은 이름을 쓰면 공급처 결제가 5 분마다 저절로 나간다 · 공급처 kind 는 모두 `SUPPLIER_KINDS`(DEFAULT 밖 · cron 61 · 62 밖) · SEND_KINDS 24
⚠️⚠️ **1132 — 몸이 막고 사람에게**: 조기 결제 할인 · 붙임 문서에 크레딧 붙음 · 결제 금액 ≠ 붙임 합 → 「Enter this payment in QuickBooks by hand, then press Skip on this job」 · IMS 에서 고치면 ①③ 은 지문으로 다시 · ② 는 Retry · E-8(538)이 서기 전에 할인 결제를 보내는 길을 만들지 마라 → [2026-11-10 · 4-7a · 4-7b · §15-o] ① 할인은 이제 보낸다(아래 4-7 줄) · ② ③ 은 그대로
⚠️⚠️ **1133 — PayType 은 IMS 계좌 종류**(BANK → Check + `PrintStatus NotSet` · CREDITCARD → CreditCard + `CCAccountRef`) + QBO 거울 AccountType · 통화 대조 · 거울 값 없으면 막음 → Settings → QuickBooks matching → Refresh list(accounts) · `PULL_FIELDS.Account` = `*`(거울 detail 에 AccountType · CurrencyRef)
⚠️⚠️ **void 주소** = `POST billpayment?operation=update&include=void` · 몸 `{Id, SyncToken, sparse:true}` · 결제를 지우거나 지문(금액 · 날짜 · 할인 · 계좌 · 환율 · reference · 붙임)이 바뀌면 void + 다시 · `bill_delete_manual` 은 그 문서의 열린 void 뒤(가장 오래된 하나만 · 541)
⚠️⚠️ **가드** — 같은 날 `select * from BillPayment where TxnDate = …`(PayType 은 못 고른다 · 공급처 · 표지 · 센트는 EF) · 표지 「IMS supplier payment <po_payment.id>」 · 1 장 꼭 맞으면 done(already in QuickBooks) · 표지 같고 공급처 · 금액 다르면 unknown · 1134 자동 done 도 이 넷이 모두 맞는 한 장일 때만 · **Bill 잔액 가드**: POST 직전 Bill 마다 GET · Balance 가 모자라면 failed(손 결제를 지우고 Retry · 남기려면 IMS Skip · 1081)
⚠️⚠️ **1124 이제 강제** — 결제 하나 = 공급처 하나(create · alloc_set) · 붙임 줄의 문서를 직접 UPDATE 로 바꾸지 못한다 · USD 결제는 환율(`po_payment.exchange_rate` · CAD per 1 USD · 산 날 MTFX)이 비면 몸이 막는다(1123)
⚠️⚠️ **은행 피드 Match 는 북키퍼(사람)** — QBO 가 열린 **Bill** 을 짝으로 내밀면 누르지 마라(QBO 가 결제를 따로 만들어 두 번) · IMS 가 보낸 뒤 짝이 Bill Payment 로 바뀌면 Match · 은행 규칙 「Automatically add to books」 금지 · MTFX 는 피드에 연결 안 됨(USD 는 Match 없음)
⚠️  **두 환율** — Bill = IMS 인보이스 환율(재고 원가) · 결제 = 산 날 MTFX 환율 · 차이는 QBO 환차손익 · 결제 환율을 Bill 환율에 맞추지 마라 · IMS 재고 원가 무변
⚠️  첫 실물 전에 사람에게 묻는다 — 실제로 돈이 나간 계좌 · 그 출금이 은행 피드에서 이미 분류됐는지(가드는 「Bill 에 붙인 손 결제」 만 잡는다) · QBO 계좌 번호의 뜻은 IMS 계좌 짝을 select 로 본 뒤 말한다(workflow 128)
~~⚠️  손님 `qbo_payment_sync` 에는 「void 를 거둘 때 뒤 다시 보내기 일감이 영구 blocked」 결함이 남아 있다(공급처 쪽은 4-5a 가 고침 · deferred 540)~~ → ✅ [2026-11-10 · qbo-pay-fix-1 `3f0a7a8`] 고침 · 540 닫힘
✅ [2026-11-10 · 4-7a `573b6af` · 4-7b `222e96c` · 정본 §15-o · so-module §111] **조기 결제 할인 공급처 결제가 나갈 수 있다 — 결제의 Send 한 번**(1150) · 실물 0
⚠️⚠️ **할인 = VendorCredit 따로 일감**(1143) — kind `vendor_credit` + ims_kind **`po_discount`** · ims_id = `po_payment_alloc.id` · DocNumber `D<결제일 yymmdd>-<인보이스>` · PrivateNote 표지 `IMS early-payment discount <alloc id>` · 환율 = 인보이스(1148) · 결제 몸 Line = Bill 줄(충당 amount) + VC 줄(할인) · TotalAmt = 낸 돈(E-8)
⚠️⚠️ **「먼저 만들기」 는 needs 길로만** — claim 이 `qbo_job_open_or_add` 로 needs 를 세우고 본 일감 blocked → EF 가 같은 호출에서 먼저 보낸다 · wait 꼴(blocked_by)은 이 길을 안 탄다(「blocked · no_progress」) · open_or_add 의 `vendor_credit` 가지는 열린 po_discount 일감을 **찾아 돌려주기만**(만들지 않는다)
⚠️⚠️ **EF 가드** — Σ Bill − Σ VC = 낸 돈 · VC Balance 가드(못 읽음 · 공급처 · 통화 · 모자람 → failed · 응답에 CurrencyRef 없으면 통화는 지나감 554) · `billPaymentLineProblem`(줄마다 LinkedTxn 하나 · Bill | VendorCredit · Bill 줄 하나 이상 · 빈 Line 거부)
⚠️⚠️ **아직 막는 것 여섯**(머리 「Enter this payment in QuickBooks by hand, then press Skip on this job」) — 할인 세금 몫(1145) · 세금 있는 인보이스의 할인 · 청구서 할인 · 붙은 크레딧(**초안 포함** · 1147) · 붙임 합 ≠ 결제 금액 · 시작일 전 문서 — 「아직 안 정함」 을 몸 밖에서 풀지 마라(549 ~ 551)
⚠️⚠️ **할인 고침 · 지움**(1146) — BillPayment void · 같은 할인이면 열린 VC 다시 씀 · 바뀌거나 없어지면 `bill_delete_manual`(po_discount · 사람이 QBO 에서 지우고 Skip) · VC 를 API 로 지우지 마라(1126)
⚠️⚠️ **Skip 일반 함정** — 부모를 skipped 로 닫을 때 뒤 blocked 일감을 안 본다(`qbo_job_skip` · `on_invoice_cancel` · `on_credit_cancel` · `on_po_doc_status` · 548) · 풀린 것은 할인 VC → 결제(claim ②)와 void 거둠(4-5a · qbo-pay-fix-1)뿐 — 새 blocked_by 를 만들면 부모 skipped 길을 함께 짓는다
⚠️  QBO 「Automatically apply bill payments」(운영 On)는 화면 입력에만 — API VC 는 열린 Bill 에 안 붙는다(E-8) · 설정을 끄기 전에 sandbox 실측
✅ [2026-11-11 · qbo-hide-1 `363970b` · 판정 1152 · 정본 §15-p] **Skip 한 일감 숨기기** — `qbo_job.hidden_at · hidden_by`(CHECK skipped 만) · `qbo_job_hide(p_jobs uuid[], p_hide)` 전부 아니면 0(blocked-waiting skipped · 중복 · 다른 realm · 500 초과 거부) · `qbo_job_list` p_state `hidden` · counts.hidden · **Retry 가 숨김을 푼다** · 트리거 `qbo_job_touch_hidden` — 숨김만 바뀌면 updated_at · updated_by 보존
⚠️⚠️ [2026-11-11 · qbo-list-perf-1 `2194110` · 561] **목록에서 무거운 함수는 한 쪽의 행에만 · 행마다 한 번** — 옆 서브쿼리 `(select qbo_job_doc(…) as doc)` 는 펴져서 d.doc 을 읽는 칸마다 다시 돈다 ⇒ `offset 0`(All 9.9 s → 0.11 s) · 찾기는 아직 일감 수에 비례(`id::text = p_ims_id` 통째 훑기 · 566) · 정렬 동률(567)
⚠️⚠️ [2026-11-11 · qbo-dname-1 `7573009` · 판정 1153] **손님 QBO 이름 = Display name 우선** — 자동 짝 열쇠 `coalesce(nullif(btrim(display_name), ''), name)` · DisplayName = Display name · CompanyName = name · 콜론 · 탭 · 줄바꿈 거부 · customer 6240 에 할 일 안내(앞) + 「QuickBooks answered: …」(뒤) · Vendor 6240 은 아직(570)
⚠️⚠️ **같은 이름 = 같은 사람이 아니다** — 이메일 · 전화 · 주소가 실제로 같을 때만 matching 으로 잇는다 · 빈 이메일끼리는 같음이 아니다(11-06 A 건: 새 손님이 QBO #4556 에 잘못 이어져 인보이스 60247 · 결제 AO-17358 이 옛 손님으로 감 · 정본 §15-p ④) · 다른 사람이면 Display name → Retry
✅ [2026-11-11 · qbo-bill-charge-1 `361613d` · 판정 1189 ~ 1192 · 정본 §12 끝 · §15-q] **공급처 인보이스 charge · other 줄 = 설정 계정**(inv_config `qbo_supplier_line_charge_account_code` · `_other_` · 기본 `_95_` Purchase Non Stock - COS) · 바꾸기는 창구 `qbo_supplier_line_account_set`(열쇠 QUICKBOOKS · COGS · EXPENSE 만) — ⚠️ `ims_config_set` 이 아니다(두 키를 거부)
⚠️⚠️ **안 낼 줄(is_payable false)은 Bill · VendorCredit 에서 뺀다**(1191 · 줄 · 할인 · 세금 · 합계 · 지문 모두 낼 돈 기준 ⇒ QBO 미지급 = IMS 미지급) · Bill 몸의 줄 루프는 **left join**(charge · other 는 po_line_id null — inner join 이면 조용히 빠진다) · TaxCodeRef = coalesce(줄 규칙, 머리 규칙)
⭐  세금은 묶음 소계에 한 번(1193 · po-tax-once-1) — 첫 실물 15335 → Bill 173348 · USD 공급처 charge 줄은 아직 실측 없음(deferred 590)
```

## 6. 화면 · 바깥

```
settings.html  Settings → QuickBooks matching(?t=qbomatch · set v13 · ~~admin~~ → set v14 열쇠 QUICKBOOKS · 보기만이면 단추 숨김) — 요약 · Refresh list · Match automatically · Review · Unlink · 짝 화면은 QBO 에 쓰지 않는다(쓰기는 EF send)
qbo-send.html  ~~Sales → QuickBooks~~ → **Integrations → QuickBooks**(판정 1136 · nav v16 · 11-09)(qs v1 · nav v14 · 열쇠 qbo · 보기 qbo:read · 971) — 목록(상태 · 종류 · 날짜 · 찾기 · 쪽) · Preview(QBO 에 갈 몸 · 먼저 만들 손님 · Item · 막힌 이유) · Send · Send selected · Retry · Skip · 북키퍼 화면(매뉴얼 01 Sales 「QuickBooks」)
qbo-send.html  [2026-11-02 밤 · pay screens v1 asung-ims `4d9b62a`] Payments 종류 · 결제 미리 보기(check_lines · 합계 · void) · ~~목록의 waiting 은 붙은 인보이스가 아직 안 간 결제(claim 때 blocked 가 된다)~~ → [2026-11-04 정정 · 화면 코드 grep] 배지 **waiting = queued**(qbo-send.html `queued: ["", "waiting"]`) · 인보이스를 기다리는 결제는 **blocked** 배지 · 거르기 「Waiting — not sent yet」 = 안 나간 것 전부(open) · settings 카드 수단 한 수단 Find…(983)
qbo-send.html  [2026-11-04 · qs apply v1 asung-ims `21d4ef9`] 종류 「Credits applied to invoices」 · 라벨 Credit applied · Undo credit applied · applyPreview(크레딧 붙임 미리 보기)
qbo-send.html  [2026-11-08 · qs refund v1 asung-ims `0922a44` · v1a `7082d84`] 종류 Carried-over money(opening 넷) · Refunds(refund 넷) · 이름표 여덟 · 미리 보기(Purchase · 0 원 Payment · void 몸) · deferred 495 닫힘
qbo-send.html  [2026-11-09 · qs cost v1 `a0693ee` · v1a `65244a8`] 종류 「Cost of goods — daily journal」 · Cost days 카드(장 목록 · Preview · Queue 는 그 창고 첫 built 장에만 · Queue all ready sheets · Build sheets now · Held back Send / Never · Review the rebuild → Release · Resolve) · 매뉴얼 01 `sales-quickbooks-cost`
qbo-send.html  [2026-11-09 · qs sup v1 asung-ims `53edc22` · v2 `e745754`] 종류 「Supplier bills and credits」 · 「Supplier payments」 · 이름표 Supplier · Supplier bill · Supplier credit · Delete bill by hand · Supplier payment · Void supplier payment · 공급처 미리 보기 supPreview(QBO 참조는 번호만 · 이름 542) · 목록 머리 Customer · supplier
payments.html  [2026-11-09 · pay rate v1 `697dd2e` · 4-5c] 외화 결제 Exchange rate(상세 · To pay 창 · CAD per 1 USD · 비면 QuickBooks 로 안 간다)
qbo-send.html  [2026-11-10 · qs sup v3 asung-ims `e340db4`] 이름표 Early-pay discount credit · Delete discount credit by hand · 결제 미리 보기 discount credit 칩 · 「created first, in the same send」 · 합계 Bills · Early-pay discount · Paid
invoices.html  [2026-11-10 · inv disc v3 `e340db4`] 할인 칩 Pay by … → save … · 확정 경고 두 코드 · 「Cancel invoice…」(기한 출처 · 목록 칩은 창구 칸이 없어 안 보임 · 555)
settings.html  Settings → QuickBooks matching 의 charge 행 이름 「Freight, discount & account lines」 + 크레딧 계정 줄 안내(set v15 · 961)
settings.html  Settings → QuickBooks(?t=qbo · set v12) — 상태(빨강 = needs_reconnect) · Connect / Reconnect(같은 탭) · Check connection · Disconnect · Untie company · Help 줄 「Connection problems? Contact the IMS administrator: caleb@asung.ca」(872)
terms.html · privacy.html  ims.asung.ca 공개 페이지(로그인 없이 · Intuit App details 의 EULA · Privacy · 867)
Intuit         Redirect URI = https://fazgmyvzzhqybtvtktyg.supabase.co/functions/v1/qbo/callback(Development · Production) · 설문 제출본 = 정본 §9(⚠️ 제출하면 못 고친다 · 서약하는 근거는 call_log 로 본 것만)
EF 배포        supabase functions deploy qbo --project-ref fazgmyvzzhqybtvtktyg(사람이)
```

## 7. 이 스킬을 갱신할 때

- 새 사실은 **정본 `qbo-integration.md` 에 먼저**, 여기에는 「모르면 사고가 나는 것」만 한 줄 · 실측 숫자 · 오늘 상태는 정본에.
- `description` 은 1024자(pre-commit `scripts/check-skill-desc.sh`) — 싱크 차수에서 키워드가 늘면 이 스킬에(asung-so · asung-inv-ledger 는 여유 1 자 · 2026-10-29).
  - [2026-11-09 · docs-1109d] 1024(여유 0) → 「Bill」 · 「VendorCredit」 · 「BillPayment」 · 「GINR」 를 넣으며 중복어를 뺐다: 「QuickBooks 연결」(QuickBooks) · 「Cin7 QBO 싱크」(QBO 싱크 · Cin7 근거 금지 원칙) · 「realmId」(realm) · 산문 「다시 연결」(Reconnect) → **1020(여유 4)** · 다음 키워드는 또 압축이 필요하다
- SKILL.md 하나뿐 — zip 의 references/ 는 0 이 맞다.
- 옛 문장은 `~~취소선~~ + [정정 날짜]`.
