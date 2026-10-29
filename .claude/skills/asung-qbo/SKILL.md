---
name: asung-qbo
description: >
  Asung Trading IMS 와 QuickBooks Online(QBO) 연결 — OAuth 연결 · 끊기 · 다시 연결 · 토큰 갱신 · 끊김 메일 · Settings → QuickBooks · Intuit 앱 · 설문을 다루거나 QBO 싱크를 지을 때 먼저 읽으세요.
  "QuickBooks", "QBO", "퀵북", "QuickBooks 연결", "Intuit", "realm", "realmId", "qbo_connection", "qbo_oauth_state", "qbo_call_log",
  "Vault", "needs_reconnect", "invalid_grant", "QBO_ENV", "ims-qbo-refresh", "cron 59", "EF qbo", "qbo_status", "intuit_tid",
  "qbo_alert_to", "Untie company", "Reconnect", "App assessment", "redirect URI", "minorversion", "QBO 싱크", "Cin7 QBO 싱크"
  가 나오면 추측하지 말고 이 스킬과 정본 docs/design/qbo-integration.md 를 확인하세요.
  ⚠️연결만 · 싱크 없음 — IMS 는 아직 QBO 로 아무것도 보내지 않는다,
  ⚠️토큰은 Vault 에만 — 표 · 화면 · 기록 · 응답에 싣지 마라,
  ⚠️REST safeupdate — 창구의 update · delete 는 WHERE 필수(psql 시험은 못 잡는다),
  ⚠️refresh_token 은 갱신마다 바뀐다 — 임대 + 판 번호로만 저장,
  ⚠️realm 고정 — 다른 회사에 잇지 마라.
---

# Asung QuickBooks 연결 스킬

⭐ **정본 = `docs/design/qbo-integration.md`**(지금 규칙) · 하루 이야기 = `so-module.md` §87(판정 867 ~ 872 · 617 확인) · 이 스킬은 「모르면 사고가 나는 것」 요약이다 — 새 사실은 정본에 먼저.
관련: `asung-workflow`(지시서 · REST 두 겹) · `asung-doc`(메일 큐 · info@) · `asung-so`(인보이스 · 결제 · 크레딧 — 싱크 때 보낼 것)

## 0. 어디까지 왔나

```
2026-10-29  연결 줄기 끝 — qbo-1a(DB) · 1b(EF qbo · 끊김 메일) · 1c(REST WHERE) · 1d(회사 이름 실패 기록) · Settings → QuickBooks(set v12) · 약관 · 처리방침(legal v1)
            샌드박스 연결 → 끊기 → 다시 연결 → Intuit 설문 제출 → 운영 키 → 11:48 실제 Asung Trading Inc. 연결(Production)
⭐ 운영 = Asung-IMS(fazgmyvzzhqybtvtktyg) — 「테스트 DB」 가 11-01 부터 그대로 운영(판정 617) · QBO_ENV = production
⬜ 싱크(보내기)는 짓지 않았다 — deferred 260 · 327 · 341 · 374 · 375
```

## 1. ⭐⭐ 연결만 · 싱크 없음 — 모르면 사고

```
⚠️⚠️ IMS 에는 장부로 거래를 보내는 코드가 없다 — 연결 뒤 하는 일 = CompanyInfo(회사 이름) + 하루 한 번 토큰 갱신뿐
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
⭐⭐ 문(870) = IMS admin 역할만 — 연결 · 끊기 · 다시 연결 · Untie · refresh · ping · DB 가 ims_is_admin() 으로 본다(qbo_admin_gate) · 새 열쇠 없음 · 상태 읽기는 누구나
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
⚠️  갱신 토큰 만료 = 연결 + 101 일 · 갱신해도 안 밀린다(실측 · 하루 뒤 확인 대기 deferred 370) ⇒ 100 일쯤마다 Reconnect 가 필요할 수 있다(2027-02-07 전)
```

## 4. ⭐⭐ 환경 · realm — 모르면 사고

```
⚠️⚠️ 환경은 비밀값 QBO_ENV(sandbox | production) 명시 값 + 연결 행의 env — db_role 로 가르지 마라(Asung-IMS 는 컷오버 뒤에도 db_role 'test')
     어긋나면 refresh · ping 은 409 · status · disconnect 는 열린다(빠져나오는 길) · 바꾸기 = Disconnect → QBO_ENV · 키 → Connect
⚠️⚠️ realm 고정 — 처음 연결한 회사 id 가 inv_config.qbo_realm_<env> 에 · 다른 회사는 저장 거부(callback why=realm · 받은 토큰 revoke)
     싱크가 시작되면 IMS 행이 QBO id(손님 · 품목 · ref_tax_rule.qbo_id)를 가리킨다 — 회사가 바뀌면 짝이 전부 틀어진다
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

## 6. 화면 · 바깥

```
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
