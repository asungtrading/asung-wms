# QuickBooks Online 연결 — 설계 정본

작성: 2026-10-29 · 회사 PC · docs-1029 · 판정 617(확인) · 867 ~ 873(원문 표는 `so-module.md` §87-a) · 선례 `freightcom-integration.md`(날짜 절은 하루의 이야기 · 이 문서가 「지금 규칙」)
⚠️ 말하는 틀 — IMS 는 Cin7 없이 돈다(ims-principles 원칙 1). 이 설계의 주어는 IMS 와 QuickBooks Online(Intuit) 둘뿐이다.
⭐ 상태 [2026-10-29] **운영 = 연결됨 · 싱크 없음** — Asung-IMS(fazgmyvzzhqybtvtktyg · 11-01 부터 그대로 운영 · 617)가 실제 회사 **Asung Trading Inc.**(realm `…6496` · Production)에 11:48(토론토) 연결 · 샌드박스로 연결 → 끊기 → 다시 연결을 실제로 한 뒤(868) Intuit 설문 제출 → 운영 키
⚠️ **연결만 한다 — IMS 에는 장부(QBO)로 거래를 보내는 코드가 없다.** 연결 뒤 하는 일 = 회사 이름 읽기(CompanyInfo) + 하루 한 번 토큰 갱신 · 그 밖의 호출 0 · 싱크는 뒤 차수(§11 · deferred 260 · 327 · 341)
⚠️ 토큰은 **Vault** 에만 — 표 · 화면 · 기록 · EF 응답 어디에도 토큰이 없다(처리방침의 약속 · 867)

---

## 1. 무엇을 하나 — 연결만 · 싱크는 뒤

- 목표(Caleb 2026-10-29): 「오늘은 컷오버전에 퀵북 인테그레이션을 해놓으려고 해. 컷오버 이후로 미뤘지만, 싱크는 컷오버이후에 하더라도, 연결은 해놓고 싶어.」
- Caleb 의 물음 「ims가 퀵북에 연결된다고 해서 퀵북과 싱크되는 것은 아니지?」 → **맞다**
  - 연결 = OAuth 2.0 승인 한 번(admin 이 Settings → QuickBooks → Connect → Intuit 동의) · 토큰을 Vault 에 두고 하루 한 번 굴린다
  - 보내는 것 0 — 인보이스 · 결제 · 크레딧 · 손님 · 품목 어느 것도 아직 QBO 로 가지 않는다
- **Cin7 → QuickBooks 연결은 따로 그대로**(QBO 는 여러 앱을 동시에 연결한다) — ⚠️ IMS 싱크를 지을 때 **Cin7 의 QBO 싱크를 끄는 시점**을 함께 정한다(둘이 같은 거래를 보내면 두 번 · deferred 375)
- 범위 밖(싱크 차수 몫): 이월 인보이스 · 받아 둔 돈(kind · method opening)은 보내지 않는다(341 · 786) · 다중 통화 · 캐나다 세금 · 지우기(deletes)

## 2. 표 — 칸 · 상태 (qbo-1a `20261029160000`)

| 표 | 무엇 | 컷오버 |
|---|---|---|
| `qbo_connection` | 연결 한 줄(`singleton` boolean PK · check) — env(sandbox · production) · realm_id · company_name · status(connected · needs_reconnect) · connected_by · at · **토큰 칸 없음**(`refresh_secret_id` · `access_secret_id` = vault.secrets.id) · access_expires_at · refresh_expires_at · `token_version`(판 번호) · `refreshing_until` · `refreshing_by`(임대) · last_refresh_at · last_error · last_error_at | K |
| `qbo_oauth_state` | CSRF state — EF 가 만든 32 바이트 무작위의 **sha256 hex 만** · staff_id · env · 10 분 · 한 번(조건부 update 1 행) · 지난 것은 state_new 가 지운다 | K |
| `qbo_call_log` | EF 호출 기록(fc_call_log 꼴 + env · realm_id · **intuit_tid**) · action · ok · http_status · error 400 자 · by_staff · ms · 90 일(EF 가 호출 끝에 지운다) | K |

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
마이그레이션: `20261029160000` qbo-1a · `20261029190000` qbo-1b(끊김 메일 · mail_outbox.kind 에 qbo_reconnect · inv_config qbo_alert_to · qbo_mark_needs_reconnect 재발행 · qbo_last_error_set) · `20261029210000` qbo-1c(WHERE — §5 끝)
EF: `supabase/functions/qbo/index.ts`(Deps 실물) + `../_shared/qbo.ts`(순수 함수 + 흐름 handle) · 시험 `qbo/qbo_test.ts`(Intuit · DB 무접촉) · DB 시험 `supabase/tests/qbo_1a_check.sql` · `qbo_1b_check.sql` · `qbo_1c_check.sql`

## 4. 문(권한) — 870

- 연결(start) · 끊기(disconnect) · 다시 연결 · 고정 회사 비우기 · 갱신(refresh) · 연결 확인(ping) = **IMS admin 역할만** — 새 열쇠 없음 · DB 가 `ims_is_admin()`(20260915141105 · 하나뿐 · 다시 만들지 않는다)으로 본다 · ping · refresh 도 admin(qbo-1b 이견 8)
  - Caleb(870 「A」) · 기각 B = 사람마다 켜는 새 열쇠(장부 쓰기 권한을 사람 단위로 나누게 되고 열쇠 · Staff · 권한 목록이 따라온다)
  - 실측: IMS admin 은 1 명(2026-10-29)
- 상태 읽기(status) = 로그인한 직원 누구나(토큰 없음)
- cron 길 = `x-ims-cron-key` == 비밀값 `IMS_CRON_SECRET`(미설정이면 500 fail-closed · drive 꼴) · **refresh 만**
- EF 는 `verify_jwt = false`(Intuit 이 브라우저를 JWT 없이 GET callback 으로 보낸다 · freightcom · drive 와 같은 까닭) — 문은 함수 안: 직원 길 = 세션 JWT 를 DB 창구로 그대로 · `_shared/authgate.ts` 는 옛 WMS 문이라 쓰지 않는다

## 5. EF `qbo` — 액션 · callback · 환경

- POST JSON `{action}` + 직원 세션 JWT: `status`(누구나) · `start` · `disconnect` · `refresh` · `ping`(admin)
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
- 수명(실측 2026-10-29 · §10): 접근 토큰 1 시간 · **갱신 토큰 = 연결 시각 + 101 일 · 갱신해도 밀리지 않음**(짐작 — 하루 뒤 cron 으로 확인 · deferred 370) ⇒ 100 일쯤마다 Reconnect 가 필요할 수 있다 · 미리 알림은 판정 전(deferred 371)

## 7. 끊기 · 다시 연결 · realm 고정 · Untie

- **끊기**(admin · Settings → Disconnect): Intuit revoke(refresh_token · Basic) → **실패해도** `qbo_connection_delete()`(Vault 두 행 + 연결 행 + state 전부) → call_log(action disconnect · by_staff) · revoke 가 실패했으면 응답 글에 「QuickBooks → Apps 에서도 끊어 달라」 · 처리방침 약속 「관리자가 끊으면 지운다」(867)
- **다시 연결** = Connect 와 같은 길(같은 탭 → Intuit → callback) — 새 101 일
- **realm 고정**: 처음 연결한 회사 id 를 env 별로 `inv_config.qbo_realm_<env>` 에 · 다른 회사는 저장 거부(callback why=realm · 받은 토큰은 revoke)
  - 까닭: 싱크가 시작되면 IMS 행이 QBO id(손님 · 품목 · `ref_tax_rule.qbo_id`)를 가리킨다 — 회사가 바뀌면 짝이 전부 틀어진다
  - 지금: production = `…6496`(전체 값은 DB inv_config.qbo_realm_production · Settings 화면 — 판정 873)(Asung Trading Inc.) · sandbox = `9341458557490536`(Sandbox Company CA 9bca) — 둘 다 남아 있다
- **Untie company**(`qbo_realm_clear`) = admin · **연결이 없을 때만** — 회사 자체가 정말 바뀌었을 때만(화면 글 「Untie only when the company itself really changed」)
- 샌드박스 → 운영 전환 순서(2026-10-29 실제로 한 것): Settings 에서 샌드박스 Disconnect → Intuit Production Redirect URI → 운영 키 + `QBO_ENV=production` → Connect

## 8. 화면 — Settings → QuickBooks (asung-ims `settings.html` set v12 `feceed3` · 대화 Claude)

- `?t=qbo` · 상태는 EF status(토큰 없음) — 회사 · env · realm · 누가 · 언제 연결 · 승인 유효 기한(갱신 토큰 만료 날짜) · 마지막 갱신 · 마지막 오류
- needs_reconnect = **빨강**(「Reconnect needed」) · Reconnect 단추
- 단추(admin 만 · `caller_is_admin`): Connect / Reconnect(같은 탭 → Intuit → callback 302) · Check connection(ping · CompanyInfo) · Disconnect · 연결 없을 때 Untie company
- Intuit 에서 돌아오면 `&qbo=connected` | `&qbo=error&why=…` 를 읽어 안내
- Help 줄(872): 「Connection problems? Contact the IMS administrator: caleb@asung.ca」 · Caleb(872 「B」) · 기각 A(화면에 길이 없어 설문 Error Handling 4 가 사실상 No)
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
- **MFA(871)**: IMS 로그인 MFA 는 지금 없다 · 설문 「No」 · 컷오버가 자리 잡은 뒤 따로(deferred 373) · Caleb 「A」 · 기각 B = 컷오버 전 켜기(사흘 전에 23 명의 로그인 방식이 바뀐다)

## 10. 운영 상태 — 실측 (2026-10-29 · 토론토 시각)

```
샌드박스   10:52 연결(Sandbox Company CA 9bca · realm 9341458557490536) · company_name null(→ qbo-1c safeupdate)
           11:04 refresh v2 · 11:05 disconnect(revoked · deleted · vault 2 · state 1) · 11:06 다시 연결 · 회사 이름 바로 · Settings Check connection OK
갱신 토큰   만료 = 연결 시각 + 101 일 · 갱신해도 밀리지 않음(10:52 연결 → 2027-02-07 14:52 UTC · refresh 뒤에도 초까지 같음 · 다시 연결하면 새 101 일)
           하루 뒤 바뀌는지는 cron 뒤에 확인 — 「밀리지 않는다」 는 짐작(deferred 370)
접근 토큰   1 시간
call_log   13 줄 — Intuit 호출(companyinfo · token_exchange · refresh · revoke) 9 줄 모두 intuit_tid 있음 · IMS 안 줄(callback · disconnect)은 없음(맞음) · 0.4 ~ 1.2 s
설문       제출(11:3x 쯤) → 운영 키 바로
운영       Settings 에서 샌드박스 Disconnect → Production Redirect URI → 운영 키 + QBO_ENV=production
           → 11:48 실제 Asung Trading Inc. 연결(realm …6496 · Production · 승인 유효 2027-02-07) · 운영 고정 realm 이 이 회사로 섬 · 샌드박스 고정도 따로 남음
QBO 판     Plus(Caleb)
```

- 시험: qbo-1a OK 43(4 회 · `as_role` 로 **실제 authenticated 역할**에서 Vault · 창구 거부 증명) · qbo-1b 시험 OK 20(2 회째 · 시험 결함 B8 · B5 고침) · 확인 OK 20 · deno 11 + mail 17 · qbo-1c 시험 OK 6 · 확인 OK 5 · REST ping · refresh v2 · disconnect · reconnect · qbo-1d deno 12 + mail 17
- ⬜ 내일(10-30) 아침 cron 59 첫 운영 refresh 확인 — `select called_at, action, ok, http_status, intuit_tid from qbo_call_log where action = 'refresh' order by called_at desc limit 3;` · 갱신 토큰 만료가 밀렸는지(deferred 370)

## 11. 싱크로 가는 조건 (deferred 260 · 327 · 341)

- 연결 줄기는 섰다(qbo-1a ~ 1d · 운영 연결 2026-10-29) — 싱크는 열림
- 싱크 차수에서 정할 것:
  - **Cin7 의 QBO 싱크를 끄는 시점**(이중 기록 · deferred 375)
  - 이월 인보이스 · 받아 둔 돈(kind · method opening)은 보내지 않는다 · IMS 에서 이월 인보이스에 붙인 결제 · 크레딧은 QBO 의 기존 인보이스(옛 번호)에 붙인다(341 · 786)
  - 짝 칸(손님 · 품목 · `ref_tax_rule.qbo_id` — 지금은 자리만 · so-module §16) · realm 고정이 그 전제(§7)
  - 다중 통화 · 캐나다 세금 · 지우기 → 샌드박스 시험 뒤 Intuit 에 설문 다시 알림(374)
  - 오류 시험을 실제 Intuit 거부로(설문 Error Handling 1 의 근거는 지금 자동 시험뿐)
- 승인 유효 기한(약 101 일) 전 미리 알림(371) · MFA(373)
