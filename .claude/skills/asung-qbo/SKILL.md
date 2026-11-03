---
name: asung-qbo
description: >
  Asung Trading IMS 와 QuickBooks Online(QBO) 연결 — OAuth 연결 · 끊기 · 다시 연결 · 토큰 갱신 · 끊김 메일 · Settings → QuickBooks · Intuit 앱 · 설문을 다루거나 QBO 싱크를 지을 때 먼저 읽으세요.
  "QuickBooks", "QBO", "퀵북", "QuickBooks 연결", "Intuit", "realm", "realmId", "qbo_connection", "qbo_oauth_state", "qbo_call_log",
  "Vault", "needs_reconnect", "invalid_grant", "QBO_ENV", "ims-qbo-refresh", "cron 59", "EF qbo", "qbo_status", "intuit_tid",
  "qbo_alert_to", "Untie company", "Reconnect", "App assessment", "redirect URI", "minorversion", "QBO 싱크", "Cin7 QBO 싱크",
  "qbo_link", "qbo_entity", "qbo_match_auto", "qbo_pull_state", "pull", "QuickBooks matching",
  "qbo_job", "send", "apiWrite", "QUICKBOOKS 열쇠"
  가 나오면 추측하지 말고 이 스킬과 정본 docs/design/qbo-integration.md 를 확인하세요.
  ⚠️쓰기는 apiWrite 하나 — 자동 재시도 없음 · 모르면 unknown(인보이스는 아직),
  ⚠️토큰은 Vault 에만 — 표 · 화면 · 기록 · 응답에 싣지 마라,
  ⚠️REST safeupdate — 창구의 update · delete 는 WHERE 필수(psql 시험은 못 잡는다),
  ⚠️refresh_token 은 갱신마다 바뀐다 — 임대 + 판 번호로만 저장,
  ⚠️realm 고정 — 다른 회사에 잇지 마라.
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
            ⚠️ **아직 켜지 않음** — qbo_send_payments_enabled off · cron 62 등록 전 · 켜는 순서 = 아래 5절 · 정본 §14-f · deferred 453
⬜ 1d 이월 짝(452) · 크레딧 붙임 2e-2 · 환불 · 받아 둔 돈 2e-3(454) · 인보이스 스위치 켜기(971 · Caleb) — deferred 260 · 327 · 341 · 374 · 434 · 440 · 443 · 452 ~ 454
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
⚠️  갱신 토큰 만료 = 연결 + 101 일 · 갱신해도 안 밀린다(실측 · 10-30 첫 운영 cron 갱신 뒤에도 그대로 — 확인됨 · deferred 370 닫힘) ⇒ **운영 연결은 2027-02-07 15:48 UTC 전에 Reconnect**(deferred 396) · 그 뒤로도 101 일마다
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
⭐  보내기 때 opening_fix 원가 사건은 제외(판정 932 · Cin7 이 이미 COGS 를 보냈다)
```

## 5-c. ⭐⭐ 쓰기 · 보내기 일감 — 모르면 사고 (2026-11-01 밤 · 정본 §14 · 판정 935 ~ 946 · 951)

```
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
⚠️  PaymentMethodRef 짝이 없으면 failed — credit_card 는 QBO 수단 하나(983)를 사람이 짝지을 때까지 · 짝 뒤 failed 를 queued 로 되살리는 것은 1d(deferred 452)
⚠️⚠️ **켜는 순서(Caleb · deferred 453)**: ① Settings 에서 credit_card QBO 수단 짝 ② Sales → QuickBooks → Payments 몇 장 Preview → Send ③ cron 62 ims-qbo-send-payments 등록(ops/cron.sql · jobid 실측) ④ qbo_send_payments_enabled on — ⚠️ 그 전에 화면 Send 를 누르지 마라(스위치는 자동만 막는다)
⚠️  Cin7 수단 정정(so §98-c 1): 「Cin7 은 결제 수단 전부 Cash」 는 틀렸다 — 카드 · Debit · E-Transfer · EFT · Cheque 는 갈라 보냈고 Cash 는 Shopify · PayPal · 현금뿐 · 입금 계좌 = Cin7 꼴(수표 _105_ · PayPal _124_ · Shopify _1150040029_)
```

## 6. 화면 · 바깥

```
settings.html  Settings → QuickBooks matching(?t=qbomatch · set v13 · ~~admin~~ → set v14 열쇠 QUICKBOOKS · 보기만이면 단추 숨김) — 요약 · Refresh list · Match automatically · Review · Unlink · 짝 화면은 QBO 에 쓰지 않는다(쓰기는 EF send)
qbo-send.html  Sales → QuickBooks(qs v1 · nav v14 · 열쇠 qbo · 보기 qbo:read · 971) — 목록(상태 · 종류 · 날짜 · 찾기 · 쪽) · Preview(QBO 에 갈 몸 · 먼저 만들 손님 · Item · 막힌 이유) · Send · Send selected · Retry · Skip · 북키퍼 화면(매뉴얼 01 Sales 「QuickBooks」)
qbo-send.html  [2026-11-02 밤 · pay screens v1 asung-ims `4d9b62a`] Payments 종류 · 결제 미리 보기(check_lines · 합계 · void) · 목록의 waiting 은 붙은 인보이스가 아직 안 간 결제(claim 때 blocked 가 된다) · settings 카드 수단 한 수단 Find…(983)
settings.html  Settings → QuickBooks matching 의 charge 행 이름 「Freight, discount & account lines」 + 크레딧 계정 줄 안내(set v15 · 961)
settings.html  Settings → QuickBooks(?t=qbo · set v12) — 상태(빨강 = needs_reconnect) · Connect / Reconnect(같은 탭) · Check connection · Disconnect · Untie company · Help 줄 「Connection problems? Contact the IMS administrator: caleb@asung.ca」(872)
terms.html · privacy.html  ims.asung.ca 공개 페이지(로그인 없이 · Intuit App details 의 EULA · Privacy · 867)
Intuit         Redirect URI = https://fazgmyvzzhqybtvtktyg.supabase.co/functions/v1/qbo/callback(Development · Production) · 설문 제출본 = 정본 §9(⚠️ 제출하면 못 고친다 · 서약하는 근거는 call_log 로 본 것만)
EF 배포        supabase functions deploy qbo --project-ref fazgmyvzzhqybtvtktyg(사람이)
```

## 7. 이 스킬을 갱신할 때

- 새 사실은 **정본 `qbo-integration.md` 에 먼저**, 여기에는 「모르면 사고가 나는 것」만 한 줄 · 실측 숫자 · 오늘 상태는 정본에.
- `description` 은 1024자(pre-commit `scripts/check-skill-desc.sh`) — 싱크 차수에서 키워드가 늘면 이 스킬에(asung-so · asung-inv-ledger 는 여유 1 자 · 2026-10-29).
- SKILL.md 하나뿐 — zip 의 references/ 는 0 이 맞다.
- 옛 문장은 `~~취소선~~ + [정정 날짜]`.
