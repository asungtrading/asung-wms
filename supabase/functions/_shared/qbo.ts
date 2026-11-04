// ============================================================
// ASUNG IMS — _shared/qbo.ts (qbo-1b · 2026-10-29 · 판정 617 · 867 ~ 872 · DB qbo-1a 20261029160000 · 지시서 ~/asung/prompts/qbo-1b.md)
//   QuickBooks Online OAuth 2.0 연결의 순수 함수 + 흐름(handle) — 바깥은 전부 Deps 로 주입(fetch · DB 창구 · 시계 · 난수) → qbo_test.ts 가 Intuit · DB 무접촉으로 돌린다
//   EF qbo/index.ts 는 Deps 의 실물(REST · Deno.env)만 댄다.
//   ⚠️ 토큰 · client secret · code 는 응답 · 기록 · 오류 · console 어디에도 남기지 않는다 — 모든 글은 scrub() 을 지난다(정확 값 치환이 주 · 꼴 치환은 보조)
//   출처(2026-10-29 직접 읽음):
//     · discovery 둘(https://developer.api.intuit.com/.well-known/openid_sandbox_configuration · …/openid_configuration) — authorize · token · revoke 가 양쪽 같다(userinfo 만 다름)
//     · API 기본 주소 · 토큰 끝점 몸(urlencoded · Basic) · revoke 몸(JSON {token} · Basic) · 응답 칸 이름 · intuit_tid 머리 = Intuit 공식 oauth-jsclient 소스
//       (github.com/intuit/oauth-jsclient src/OAuthClient.js · src/access-token/Token.js · src/response/AuthResponse.js)
//     · minorversion 75 = 2025-08-01 부터 1 ~ 74 는 무시되고 75 로 답한다(Intuit 공지 · codat 250219/250401 요약) — 75 를 명시해도 해가 없다
//   qbo-read-1(2026-11-01 · 판정 933 · DB 20261101190000 detail jsonb): 읽기 전용 조회 query · read(admin 만 · cron 길 없음) — Intuit API 호스트로는 GET 과 POST …/query 만 나간다(apiCall 이 그 밖은 던진다 · 쓰기 액션 없음)
//     query = { q } · select 로 시작 · 세미콜론 없음 · from 의 엔터티가 QUERY_ENTITIES 안 · MAXRESULTS 없으면 100 · 1000 초과는 400 · Customer · Vendor 는 select * 와 연락처 · 주소 칸 금지(933 노출 줄이기)
//     read  = { entity, id } · 단건 GET · Preferences · CompanyInfo 는 id 없이 · Customer · Vendor 단건은 연락처 · 주소 칸을 빼고 돌려준다
//     기록 = call_log 한 줄 + detail(entity · rows · totalCount · startPosition · maxResults · q 는 리터럴을 ? 로) · 결과 행은 담지 않는다 · 결과 행에는 scrub 을 걸지 않는다(SyncToken 이 깨진다 · 이견 3) · 응답은 들여쓰기 없는 JSON · 5 MB 초과 413
//   qbo-sync-1b(2026-11-01 · 판정 934 · DB qbo-sync-1a 20261101210000): pull { entity, start? }(~~admin 만~~ → [2a 945] 열쇠 qbo · cron 길 없음) — QBO 목록 한 쪽을 qbo_entity 에 받아 둔다 · 한 번 호출 = 한 쪽(1000 행)
//   qbo-sync-2a′(2026-11-01 · 판정 935 ~ 946 · DB 2a 20261102003000 + 2a′ 20261102030000): send { limit? }(열쇠 qbo · 수동 · cron 등록 없음) — ① qbo_job_unknown_list → 이름으로 조회(send_check · GET) → 하나면 qbo_job_done · 0 · 둘 이상은 그대로 ② qbo_job_claim → 일감마다 apiWrite POST 한 번(requestid = request_id · retry 없음)
//     2xx → qbo_job_done(qbo_link created + qbo_entity upsert 는 DB 가) · 4xx → qbo_job_fail(6240 Duplicate Name 인 Item 은 name_alt ` [SKU]` 로 requestid '-2' 한 번 더 · note 로 흔적) · 5xx · 끊김 · 몸에 레코드 없음 → qbo_job_unknown(보낸 이름을 남긴다) · 401 은 withAuthRetry(처리 안 됨이 분명 · 같은 requestid)
//     쓰기는 apiWrite 하나 · assertWriteAllowed(POST · customer · item · invoice · creditmemo · operation=void 는 invoice · creditmemo 만 · delete 없음 · requestid 필수) · 읽기 길(apiCall · assertReadOnlyRequest)은 그대로 · PII 가드를 Invoice · CreditMemo · Payment · SalesReceipt · RefundReceipt 에도(select * · BillAddr · ShipAddr · BillEmail · ShipFromAddr 거부 · read 는 벗김)
//   qbo-sync-2b2(2026-11-01 · 판정 935 ~ 946 · 951 · DB 2b1 20261102040000 · 지시서 ~/asung/prompts/qbo-sync-2b.md): 인보이스 보내기 · void · cron send — claim 에 p_kinds SEND_KINDS(customer · item · invoice · invoice_void · DB 기본값은 customer · item 이라 옛 EF 는 invoice 를 안 잡는다)
//     invoice: 만들기 전 DocNumber 조회(멱등) → POST invoice(몸은 DB qbo_invoice_body 그대로 · TxnTaxDetail 포함) → 2xx 면 qbo_job_done(TotalAmt · TxnTaxDetail.TotalTax — DB 가 942 로 견줘 mismatch) · 6140 · 6210 중복 번호면 다시 찾아서 있으면 그것 · 5xx · 끊김 unknown(DocNumber) → 다음 send 가 DocNumber 로 풀어 읽어서 done
//     invoice_void: POST invoice?operation=void {Id, SyncToken}(SyncToken 없으면 GET 으로 읽는다 · 5010 Stale Object 면 읽어서 requestid -2 로 한 번 더) · 4xx failed(사람) · 5xx · 끊김 unknown → 다음 send 가 읽어서 TotalAmt 0 이면 done(짐작 · 첫 실물에서 확인)
//     cron 길(x-ims-cron-key)에 send 를 연다(CRON_ACTIONS refresh · send · by_staff null · limit 은 cron 몸이 inv_config qbo_send_batch 에서) — qbo_send_enabled off 면 cron SQL 의 where 가 호출 자체를 0 으로(supabase/ops/cron.sql ims-qbo-send)
//     PULL_FIELDS.TaxCode 에 SalesTaxRateList(DB qbo_entity.detail 로 · 몸 함수의 TaxRateRef) — 적용 뒤 TaxCode Refresh list 한 번 · Intuit API 호스트로는 여전히 GET · POST …/query · POST customer · item · invoice(+ operation=void)만
//   qbo-sync-2c1(2026-11-02 · 판정 959 ~ 966 · 968 · DB 20261102130000 · 지시서 ~/asung/prompts/qbo-sync-2c-1.md): 크레딧 노트 보내기 · void — SEND_KINDS 에 credit · credit_void · 인보이스 길과 같은 꼴을 엔티티 열쇠(entityKeyOf → creditmemo · CreditMemo · DocNumber)로 나눈다
//   qbo-sync-2d1(2026-11-02 · 판정 971 · DB 20261102150000 · 지시서 ~/asung/prompts/qbo-sync-2d-1.md): 북키퍼가 골라 보낸다 — send { job_ids[1 … 10] }(열쇠 qbo · cron 길 없음) · 바퀴 최대 5(claim(p_job_ids = 고른 id ∪ need 일감 id) → 같은 바퀴의 일감은 동시 5 로 보냄 → 다시 claim · 잡힌 것 0 이면 끝) · 30 s 넘으면 더 잡지 않음(not_reached) · requested[] = id 마다 결과 · 크레딧은 자기 인보이스를 대신 보내지 않는다(960 · blocked + 까닭) · 옛 send { limit } 은 cron 61 · console 그대로
//     credit: DocNumber(CR-01000 ~) 조회 멱등(from CreditMemo) → POST creditmemo(몸은 DB qbo_credit_body 그대로) → 2xx done(TotalAmt · TotalTax — DB 가 so_credit 과 942 로 견줌) · 6140 · 6210 → 다시 찾아 짝 · 5xx · 끊김 unknown → 다음 send 가 CreditMemo DocNumber 로 풀어 읽어서 done
//     credit_void(963): POST creditmemo?operation=void {Id, SyncToken} · SyncToken 없으면 GET creditmemo/<id> · 5010 → 읽어서 -2 한 번 · Intuit 이 거부(4xx · CreditMemo void 가능 여부는 짐작 — 첫 실물에서 확인)하면 failed + 이유(북키퍼가 QBO 에서) · delete 없음 · ReceivePayment · 환불(964)은 짓지 않는다
//   qbo-sync-2a(2026-11-01 · 판정 945 · DB 20261102003000): 문 둘 — ADMIN_ACTIONS(start · disconnect · refresh · ping · query · read)는 qbo_admin_gate 그대로 · KEY_ACTIONS(pull · 뒤에 send · job)는 qbo_key_gate(p_write true · perms 'qbo' 글자 그대로 · admin 도 켜야 한다) · 둘 다 사용자 JWT 로 DB 가 본다 · status 응답의 caller_qbo(write | read | null)는 DB qbo_status 가 준다(EF 코드 없음)
//     entity 7 = PULL_ENTITIES(Account · TaxCode · Term · PaymentMethod · Customer · Vendor · Item · 그 밖은 400) · 칸은 PULL_FIELDS(Customer · Vendor 는 Id · DisplayName · ParentRef · FullyQualifiedName · Active · SyncToken 만 · 933 · Item 은 * — qbo-sync-1c: 칸을 고른 조회는 Sku 를 안 돌려준다 · 11-01 실측)
//     조회 = select <칸> from <entity> where Active in (true, false) STARTPOSITION <start> MAXRESULTS 1000 — TaxCode 만 where 없이(11-01 실측: Account · Term · PaymentMethod 는 조건 통과 · TaxCode · TaxRate 는 조건 없이 받음 · PULL_NO_ACTIVE_FILTER)
//     start 없거나 1 = 새 run(qbo_pull_begin restart) → 조회 → qbo_entity_upsert(rows · next_start = start + 1000) → 받은 수 < 1000 이면 qbo_pull_finish(gone_at) · 창구는 전부 사용자 JWT(rpcUser · DB 가 admin 을 본다)
//     응답 { ok, entity, start, received_now, received, pages, next_start(끝이면 null), done, gone, finished_at, intuit_tid } · 기록 detail = entity · rows · start · page 만
//   qbo-sync-2e-1c(2026-11-02 밤 · 판정 978 ~ 991 · 992′ · 993 · DB 2e-1b 20261103050000 · 지시서 ~/asung/prompts/qbo-sync-2e-1.md · sandbox B-4 980 (나) · B-6 void 꼴): 결제 보내기 · void · 자동 길
//     payment: (가) check_lines[] 마다 GET invoice/<id> 로 Balance 를 읽어 Balance < 줄 금액이면 failed(「QuickBooks already shows … paid on invoice …」 · 못 읽어도 failed · 보내지 않는다) → POST payment(몸은 DB qbo_payment_body 그대로 · CustomerRef 청구처 · Line LinkedTxn Invoice)
//       → 2xx 면 qbo_job_done(p_total_amt = TotalAmt · p_total_tax null · p_unapplied_amt = UnappliedAmt — DB 가 amount · amount − Σ붙임 과 견줘 mismatch · 지문은 claim 이 일감에 적은 것) · 4xx failed · 5xx · 끊김 unknown(열쇠 「IMS payment <uuid>|<CustomerRef>|<TxnDate>|<TotalAmt>」 를 qbo_name 에)
//       unknown 풀기 = 그 날(TxnDate) Payment 를 조회(where TxnDate = … · PII 칸 없음)해 CustomerRef · TotalAmt · PrivateNote(IMS payment <uuid>) 로 고른다 → 하나 done · 0 not_found(사람 retry) · 둘 이상 ambiguous(그대로)
//     payment_void: POST payment?operation=update&include=void {Id, SyncToken, sparse true}(sandbox B-6 실물 · SyncToken 없으면 GET payment/<id> · 5010 → 읽어서 requestid -2) · 2xx(TotalAmt 0 · Line []) → done 7 인자(DB 가 voided_at + reconcile) · 4xx failed · 5xx unknown(qbo_name = Payment Id)
//       → 다음 send 가 Id 로 읽어 TotalAmt 0 ∧ PrivateNote 「Voided」 머리면 done · 아니면 not_voided
//     send { kinds? }(직원 · cron 둘 다 · SEND_KINDS 부분집합 · 없으면 전부) — cron 62 ims-qbo-send-payments 가 {kinds: [payment, payment_void]} 로 부른다(qbo_send_payments_enabled · supabase/ops/cron.sql 기록 · 등록은 Caleb) · job_ids 길은 kinds 를 안 본다
//     assertWriteAllowed: payment 는 만들기 + operation=update&include=void 만 · operation=void 는 invoice · creditmemo 그대로 · delete 없음 · Intuit API 호스트로는 GET · POST …/query · POST customer · item · invoice · creditmemo · payment(+ void 꼴 둘)만
//   qbo-sync-2e-2-1b(2026-11-04 · 판정 1009 · 1011 ~ 1016 · 1034 · DB 2e-2-1 20261103200000 · 지시서 ~/asung/prompts/qbo-sync-2e-2-1b.md · sandbox C-5″ · C-6): 크레딧 붙임 = 0 원 Payment 보내기 · void — SEND_KINDS 10(credit_apply · credit_apply_void) · CREDIT_APPLY_KINDS(PAYMENT_KINDS 무변)
//     credit_apply: check_lines 가 Invoice 줄 하나 + CreditMemo 줄 하나가 아니면 failed → GET invoice/<id> Balance ≥ a ∧ GET creditmemo/<id> RemainingCredit ≥ a(모자라거나 못 읽으면 failed · 보내지 않는다) → POST payment(몸은 DB qbo_credit_apply_body 그대로 · TotalAmt 0 · Line Invoice + CreditMemo · 계좌 · 수단 · 참조 없음)
//       → 2xx done(donePayment 10 인자 · TotalAmt 0 · UnappliedAmt 0 — DB 가 0 · 0 과 견줘 mismatch) · 4xx failed · 5xx · 끊김 unknown(열쇠 「IMS credit applied <uuid>|<CustomerRef>|<TxnDate>|0」 · parsePaymentKey 가 접두 둘)
//       unknown 풀기 = 그 날 Payment 조회 → CustomerRef · TotalAmt 0 · PrivateNote 완전 일치(includes 아님 — void 된 0 원 장은 「Voided - 」 가 붙어 빠진다) · isVoidedPayment 제외 → 하나 done · 0 not_found · 둘 이상 ambiguous · DocNumber 조회 없음
//     credit_apply_void: payment_void 길 그대로(조건 줄에 || · update&include=void · SyncToken 없으면 GET · 5010 → -2 · 풀기도 Id 로 읽어 Voided 면 done) · entityKeyOf 새 둘 = payment · Payment · nameField PrivateNote(옛 kind 무변)
//     sendPicked need 건너뛰기(960) — TXN_KINDS 만 → customer · item 이 아니면 전부(1013 으로 void 일감에 blocked 된 붙임을 북키퍼가 홀로 고르면 그 void 를 대신 보내지 않는다 · 결제 일감은 void 에 blocked 되는 길이 없다)
//     assertWriteAllowed · PAYMENT_KINDS · 결제 갈래 본문 무변(바뀐 줄 = 조건 셋 · parsePaymentKey 접두 · ClaimJob check_lines 타입)
// ============================================================

export type Env = "sandbox" | "production";
export const ENVS: readonly Env[] = ["sandbox", "production"];
export const SCOPE = "com.intuit.quickbooks.accounting";
export const API_BASE: Record<Env, string> = { sandbox: "https://sandbox-quickbooks.api.intuit.com", production: "https://quickbooks.api.intuit.com" };
export const DISCOVERY_URL: Record<Env, string> = { sandbox: "https://developer.api.intuit.com/.well-known/openid_sandbox_configuration", production: "https://developer.api.intuit.com/.well-known/openid_configuration" };
export const MINOR_VERSION = "75";
export const SETTINGS_URL = "https://ims.asung.ca/settings.html?t=qbo";          // 302 가 보내는 곳 — 코드에 하나 고정 · 요청 값으로 만들지 않는다
export const CALLBACK_WHY = ["denied", "state", "exchange", "realm", "save", "env"] as const;
export type CallbackWhy = typeof CALLBACK_WHY[number];
export const DISCOVERY_TTL_MS = 24 * 3600_000;
export const REFRESH_AHEAD_MS = 5 * 60_000;                                       // 접근 토큰이 5 분 안에 끝나면 먼저 갱신
export const LEASE_WAIT_MS = 15_000, LEASE_POLL_MS = 1_500;                       // 임대 못 받으면 1.5 s 씩 최대 15 s 기다렸다 다시 읽기
export const RETRY_DELAY_MS = 1_000;                                              // 네트워크 · 5xx 만 1 회
export const CALL_LOG_KEEP_DAYS = 90;
export const ACCESS_EXPIRES_DEFAULT_S = 3600;                                     // expires_in 이 없을 때만(Intuit 문서값 · 이견 5) — 응답에 있으면 그 값
export const ACTIONS = ["status", "start", "disconnect", "refresh", "ping", "query", "read", "pull", "send"] as const;
// ── qbo-sync-2a 판정 945 문 둘 — ADMIN_ACTIONS = qbo_admin_gate(연결 · 끊기 · 갱신 · 핑 · 원문 조회 933) · KEY_ACTIONS = qbo_key_gate(p_write true · perms 'qbo' · admin 도 켜야 한다 · 뒤에 send · job) · status 는 누구나 ──
export const ADMIN_ACTIONS = ["start", "disconnect", "refresh", "ping", "query", "read"] as const;
export const KEY_ACTIONS = ["pull", "send"] as const;
// ── qbo-sync-2a′ 쓰기 길 — apiWrite 하나 · POST 만 · 만들기 customer · item · invoice · creditmemo(2b) · operation=void 는 invoice · creditmemo 만(2b · 2c) · operation=delete 없음 · requestid 필수(1 ~ 50 자 · Intuit 이 같은 id 면 처음 응답) · 자동 재시도 없음(retry false · 결과를 모르면 unknown → 다음 send 가 이름으로 조회) ──
export const WRITE_ENTITIES = ["customer", "item", "invoice", "creditmemo", "payment"] as const;      // [2e-1c payment]
export const VOIDABLE_ENTITIES = ["invoice", "creditmemo"] as const;                                    // operation=void
export const UPDATE_VOID_ENTITIES = ["payment"] as const;                                              // 2e-1c: Payment 의 void = operation=update&include=void(sandbox B-6 실물) · 그 밖 update 는 없다
export const REQUESTID_MAX = 50;
export const SEND_LIMIT_DEFAULT = 15, SEND_LIMIT_MAX = 50;
export const SEND_PICK_MAX = 10, SEND_PICK_ROUNDS = 5, SEND_PICK_BUDGET_MS = 30_000, SEND_PICK_PARALLEL = 5;   // 2d1: 고른 id 한도(화면이 나눈다) · 바퀴(인보이스 → 부모 · Item → 손님 → 인보이스 다시 = 4 + 여유 1) · 바퀴 앞 예산 · 같은 바퀴 동시 수(Intuit 동시 한도 10 의 반)
export const DUPLICATE_NAME_CODE = "6240";                                                 // Intuit 「Duplicate Name Exists Error」 — 처리 안 됨이 분명 · Item 은 ` [SKU]` 로 한 번 더(다른 requestid · 이견 11)
export const DUPLICATE_DOCNUMBER_CODES = ["6140", "6210"] as const;                        // 2b2 Intuit 「Duplicate Document Number Error」(6140 · 6210 둘 다 본 적이 있다 — 지시서) → DocNumber 로 다시 찾아서 있으면 그것
export const STALE_OBJECT_CODE = "5010";                                                   // 2b2 Intuit 「Stale Object Error」 — void 의 SyncToken 이 낡았다 → 읽어서 한 번 더(requestid -2)
export const SEND_KINDS = ["customer", "item", "invoice", "invoice_void", "credit", "credit_void", "payment", "payment_void", "credit_apply", "credit_apply_void"] as const;   // 2b2 · [2c1 credit · credit_void] · [2e-1c payment · payment_void] · [2e-2-1b credit_apply · credit_apply_void] 이 EF 가 보낼 줄 아는 일감 종류(claim p_kinds · DB 기본값은 customer · item)
export const PAYMENT_KINDS = ["payment", "payment_void"] as const;                                     // 2e-1c 결제 일감(DocNumber 없음 · 열쇠 = 날짜 · 손님 · 금액 · PrivateNote)
export const CREDIT_APPLY_KINDS = ["credit_apply", "credit_apply_void"] as const;                      // 2e-2-1b 크레딧 붙임 = 0 원 Payment(DocNumber 없음 · 열쇠는 결제 꼴 · PrivateNote 「IMS credit applied <uuid>」)
export const TXN_KINDS = ["invoice", "invoice_void", "credit", "credit_void"] as const;      // 2c1 거래 일감(DocNumber 멱등 · 읽기 · 합계) — 인보이스 · 크레딧이 같은 길을 엔티티 열쇠만 바꿔 쓴다
// ── qbo-sync-1b pull — 종류 7 · 칸 · 쪽 1000 · Active 조건 없이 받는 종류(TaxCode · 11-01 실측) ──
export const PULL_ENTITIES = ["Account", "TaxCode", "Term", "PaymentMethod", "Customer", "Vendor", "Item"] as const;
export const PULL_PAGE = 1000;
export const PULL_FIELDS: Record<string, string> = {
  Account: "Id, Name, FullyQualifiedName, ParentRef, Active, SyncToken",
  TaxCode: "Id, Name, Active, SyncToken, SalesTaxRateList",                                       // 2b2: TaxRateRef 를 DB 가 안다(qbo_entity.detail · qbo_invoice_body 의 TxnTaxDetail)
  Term: "Id, Name, Active, SyncToken",
  PaymentMethod: "Id, Name, Active, SyncToken",
  Customer: "Id, DisplayName, FullyQualifiedName, ParentRef, Active, SyncToken",                    // 연락처 · 주소 칸 없음(933)
  Vendor: "Id, DisplayName, Active, SyncToken",
  Item: "*",                                                                                         // qbo-sync-1c: 칸을 고르면 QBO 가 Sku 를 안 준다(11-01 실측 · sparse 행) → Item 은 * (연락처 칸 없는 엔터티 · 1,000 행 ≈ 1.3 MB) · DB upsert 가 필요한 칸만 담는다
};
export const PULL_NO_ACTIVE_FILTER: readonly string[] = ["TaxCode"];
export const pullQueryText = (entity: string, start: number): string =>
  `select ${PULL_FIELDS[entity]} from ${entity}${PULL_NO_ACTIVE_FILTER.includes(entity) ? "" : " where Active in (true, false)"} STARTPOSITION ${start} MAXRESULTS ${PULL_PAGE}`;
// ── qbo-read-1 읽기 전용 조회 — 허용 엔터티(정식 이름 · 대소문자 무관으로 맞춘다) · Employee 는 일부러 없다(933) ──
export const QUERY_ENTITIES = ["Account", "TaxCode", "TaxRate", "TaxAgency", "Term", "PaymentMethod", "Customer", "Vendor", "Item", "Invoice", "CreditMemo", "Payment", "RefundReceipt", "SalesReceipt", "Deposit", "JournalEntry", "Bill", "VendorCredit", "BillPayment", "Purchase", "Class", "Department", "CompanyCurrency", "ExchangeRate"] as const;
export const READ_SINGLETONS = ["Preferences", "CompanyInfo"] as const;                                 // read 만 · id 없이
export const PII_ENTITIES = ["Customer", "Vendor", "Invoice", "CreditMemo", "Payment", "SalesReceipt", "RefundReceipt"] as const;   // 연락처 · 주소 칸 금지(933 · 2a′ 이견 17: 거래 다섯도 — BillAddr · ShipAddr · BillEmail 이 그대로 오던 빈틈)
export const PII_FIELDS = ["PrimaryEmailAddr", "PrimaryPhone", "Mobile", "Fax", "BillAddr", "ShipAddr", "WebAddr", "AlternatePhone", "OtherAddr", "BillEmail", "BillEmailCc", "BillEmailBcc", "ShipFromAddr"] as const;
export const MAXRESULTS_DEFAULT = 100, MAXRESULTS_MAX = 1000, QUERY_MAX_CHARS = 2000;
export const RESPONSE_MAX_BYTES = 5 * 1024 * 1024;                                                       // Intuit 응답 몸 5 MB 초과 → 413(이견 9)
export const CRON_ACTIONS = ["refresh", "send"] as const;                                             // 2b2: cron ims-qbo-send(*/5 · qbo_send_enabled off 면 cron SQL 의 where 가 호출 0)
export const CORS: HeadersInit = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-region", "Access-Control-Allow-Methods": "POST, OPTIONS" };

export class RpcError extends Error { constructor(public status: number, message: string) { super(message); } }
export class QboError extends Error { constructor(public status: number, message: string) { super(message); } }

// ── 순수: 주소 · state · 해시 ──
export const base64url = (bytes: Uint8Array): string => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
export function newStateRaw(bytes: Uint8Array): string {
  if (bytes.length !== 32) throw new Error("state must be 32 random bytes");
  return base64url(bytes);
}
export async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return Array.from(new Uint8Array(d)).map((b) => b.toString(16).padStart(2, "0")).join("");
}
export function authorizeUrl(endpoint: string, clientId: string, redirectUri: string, state: string): string {
  const u = new URL(endpoint);
  u.search = new URLSearchParams({ client_id: clientId, scope: SCOPE, redirect_uri: redirectUri, response_type: "code", state }).toString();
  return u.toString();
}
export function callbackLocation(why: CallbackWhy | null): string {
  if (why === null) return SETTINGS_URL + "&qbo=connected";
  if (!(CALLBACK_WHY as readonly string[]).includes(why)) throw new Error("unknown callback why");
  return SETTINGS_URL + "&qbo=error&why=" + why;
}
export const redirect302 = (location: string): Response => new Response(null, { status: 302, headers: { Location: location, "Cache-Control": "no-store" } });
export const redirectUriOf = (supabaseUrl: string): string => supabaseUrl.replace(/\/+$/, "") + "/functions/v1/qbo/callback";
export const isCallbackPath = (pathname: string): boolean => /\/callback\/?$/.test(pathname);
export const envOf = (v: string | undefined | null): Env | null => (v === "sandbox" || v === "production" ? v : null);
export const secretNames = (env: Env) => ({ id: "QBO_CLIENT_ID_" + env.toUpperCase(), secret: "QBO_CLIENT_SECRET_" + env.toUpperCase() });
export const basicAuth = (id: string, secret: string): string => "Basic " + btoa(id + ":" + secret);

// ── 순수: discovery(24 h 캐시 · 실패면 캐시 · 캐시도 없으면 500 · 코드에 박은 폴백 없음) ──
export type Discovery = { authorization_endpoint: string; token_endpoint: string; revocation_endpoint: string };
export function parseDiscovery(j: unknown): Discovery | null {
  const o = (j ?? {}) as Record<string, unknown>;
  const pick = (k: string) => (typeof o[k] === "string" && /^https:\/\//.test(o[k] as string) ? (o[k] as string) : null);
  const a = pick("authorization_endpoint"), t = pick("token_endpoint"), r = pick("revocation_endpoint");
  return a && t && r ? { authorization_endpoint: a, token_endpoint: t, revocation_endpoint: r } : null;
}
export type DiscoveryState = { env: Env; cached_at: string; fresh: boolean; stale_served: boolean } | null;
export class DiscoveryCache {
  private c: { env: Env; at: number; d: Discovery } | null = null;
  private staleServed = false;
  constructor(private ttlMs = DISCOVERY_TTL_MS) {}
  async get(env: Env, fetchJson: (url: string) => Promise<unknown>, now: number): Promise<Discovery> {
    if (this.c && this.c.env === env && now - this.c.at < this.ttlMs) return this.c.d;
    try {
      const d = parseDiscovery(await fetchJson(DISCOVERY_URL[env]));
      if (!d) throw new Error("discovery document has no authorization/token/revocation endpoint");
      this.c = { env, at: now, d }; this.staleServed = false;
      return d;
    } catch (e) {
      if (this.c && this.c.env === env) { this.staleServed = true; return this.c.d; }                 // 실패면 캐시(지났어도)
      throw new QboError(500, "Intuit discovery document could not be read and nothing is cached — try again shortly: " + String((e as Error)?.message ?? e).slice(0, 200));
    }
  }
  state(now: number): DiscoveryState { return this.c ? { env: this.c.env, cached_at: new Date(this.c.at).toISOString(), fresh: now - this.c.at < this.ttlMs, stale_served: this.staleServed } : null; }
}

// ── 순수: 토큰 응답 · 오류 글 · 재시도 판정 · intuit_tid · scrub ──
export type Tokens = { access: string; refresh: string; accessExp: Date; refreshExp: Date | null; assumedExpiresIn: boolean };
export function parseTokenResponse(j: unknown, nowMs: number): Tokens {
  const o = (j ?? {}) as Record<string, unknown>;
  const access = typeof o.access_token === "string" ? o.access_token : "", refresh = typeof o.refresh_token === "string" ? o.refresh_token : "";
  if (!access || !refresh) throw new QboError(502, "Intuit token response has no access_token/refresh_token");
  const ein = Number(o.expires_in), rin = Number(o.x_refresh_token_expires_in);                        // 칸 이름 = oauth-jsclient Token.js(setToken) 그대로
  const assumed = !(ein > 0);
  return { access, refresh, accessExp: new Date(nowMs + (assumed ? ACCESS_EXPIRES_DEFAULT_S : ein) * 1000), refreshExp: rin > 0 ? new Date(nowMs + rin * 1000) : null, assumedExpiresIn: assumed };
}
export function intuitErrorText(status: number, body: unknown): string {
  let s = "HTTP " + status;
  const o = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const fault = o.Fault as Record<string, unknown> | undefined;
  if (fault && Array.isArray(fault.Error) && fault.Error.length) {
    const e = fault.Error[0] as Record<string, unknown>;
    s += " " + String(fault.type ?? "Fault") + " code " + String(e.code ?? "?") + ": " + String(e.Message ?? "") + (e.Detail ? " — " + String(e.Detail) : "");
  } else if (typeof o.error === "string") {
    s += " " + o.error + (o.error_description ? ": " + String(o.error_description) : "");
  } else if (typeof body === "string" && body.trim()) {
    s += " " + body.trim();
  }
  return s.slice(0, 400);
}
export const oauthErrorCode = (body: unknown): string | null => { const o = (body && typeof body === "object" ? body : {}) as Record<string, unknown>; return typeof o.error === "string" ? o.error : null; };
export const needsReconnect = (status: number, body: unknown): boolean => status === 400 && oauthErrorCode(body) === "invalid_grant";   // 갱신 토큰 만료 · 취소 · QBO 쪽 끊김 — 그 밖의 4xx(invalid_client 등)는 설정 문제라 표시하지 않는다
export const isRetryable = (status: number, networkError: boolean): boolean => networkError || status >= 500;
export const tidOf = (h: { get(name: string): string | null }): string | null => (h.get("intuit_tid") ?? "").trim() || null;
export const REDACTED = "[redacted]";
export function scrub(text: string, secrets: readonly string[] = []): string {
  let s = String(text ?? "");
  for (const v of secrets) if (v && v.length >= 8) s = s.split(v).join(REDACTED);
  return s
    .replace(/Bearer\s+[A-Za-z0-9\-._~+/]+=*/gi, "Bearer " + REDACTED)
    .replace(/("?(?:access|refresh|id)_token"?\s*[:=]\s*"?)[^"&\s,}]+/gi, "$1" + REDACTED)
    .replace(/("?client_secret"?\s*[:=]\s*"?)[^"&\s,}]+/gi, "$1" + REDACTED)
    .replace(/("?token"?\s*[:=]\s*"?)[^"&\s,}]+/gi, "$1" + REDACTED)
    .replace(/(\bcode=)[^&\s]+/gi, "$1" + REDACTED)
    .replace(/\beyJ[A-Za-z0-9\-_]{10,}\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+/g, REDACTED)                 // JWT 꼴(Intuit 접근 토큰 · 짐작 보강)
    .replace(/\bAB1[0-9][A-Za-z0-9\-_]{20,}/g, REDACTED);                                             // Intuit 갱신 토큰 꼴(AB11…· 짐작 보강 — 정확 값 치환이 주)
}
export const companyNameOf = (body: unknown): string | null => { const n = ((body as Record<string, unknown>)?.CompanyInfo as Record<string, unknown> | undefined)?.CompanyName; return typeof n === "string" && n.trim() ? n.trim() : null; };

// ── qbo-read-1 순수: 조회 문장 검사 · 기록용 다듬기 · 읽기 전용 요청 검사 · 연락처 칸 빼기 ──
export const canonicalEntity = (name: string, list: readonly string[]): string | null => list.find((e) => e.toLowerCase() === String(name ?? "").trim().toLowerCase()) ?? null;
export type ParsedQuery = { entity: string; text: string; maxResults: number; startPosition: number; isCount: boolean };
export function parseQuery(raw: unknown): ParsedQuery {
  const q = String(raw ?? "").trim();
  if (!q) throw new QboError(400, "q is required — a QuickBooks query such as: select * from Item MAXRESULTS 100");
  if (q.length > QUERY_MAX_CHARS) throw new QboError(400, `q is longer than ${QUERY_MAX_CHARS} characters`);
  if (q.includes(";")) throw new QboError(400, "q must not contain a semicolon");
  if (!/^select\s/i.test(q)) throw new QboError(400, "q must start with select — this connector only reads");
  const m = /\bfrom\s+([A-Za-z]+)/i.exec(q);
  if (!m) throw new QboError(400, "q has no from <entity>");
  const entity = canonicalEntity(m[1], QUERY_ENTITIES);
  if (!entity) throw new QboError(400, `entity ${m[1]} is not readable here — allowed: ${QUERY_ENTITIES.join(", ")}`);
  const fields = q.slice(6, m.index).trim();
  const isCount = /^count\s*\(\s*\*\s*\)$/i.test(fields);
  if ((PII_ENTITIES as readonly string[]).includes(entity) && !isCount) {
    if (fields === "*") throw new QboError(400, `select * is not allowed on ${entity} — name the fields (Id, DisplayName / DocNumber, TotalAmt, TxnDate, CustomerRef, SyncToken, MetaData …); contact and address fields are excluded (${PII_FIELDS.join(", ")})`);
    const hit = PII_FIELDS.find((f) => new RegExp("\\b" + f + "\\b", "i").test(fields));
    if (hit) throw new QboError(400, `${hit} is not readable on ${entity} — contact and address fields are excluded (${PII_FIELDS.join(", ")})`);
  }
  const mr = /\bmaxresults\s+(\d+)/i.exec(q);
  let maxResults = MAXRESULTS_DEFAULT, text = q;
  if (mr) {
    maxResults = Number(mr[1]);
    if (!(maxResults >= 1 && maxResults <= MAXRESULTS_MAX)) throw new QboError(400, `MAXRESULTS must be 1 … ${MAXRESULTS_MAX} (got ${mr[1]}) — page with STARTPOSITION instead`);
  } else if (!isCount) text = q + " MAXRESULTS " + MAXRESULTS_DEFAULT;
  const sp = /\bstartposition\s+(\d+)/i.exec(q);
  const startPosition = sp ? Number(sp[1]) : 1;
  if (!(startPosition >= 1)) throw new QboError(400, "STARTPOSITION must be 1 or more");
  return { entity, text, maxResults, startPosition, isCount };
}
export const queryForLog = (text: string): string => text.replace(/'(?:[^']|'')*'/g, "?");                 // 따옴표 리터럴 → ?(손님 이름 · 이메일이 call_log 에 남지 않는다 · 이견 2)
export function assertReadOnlyRequest(method: string, url: string): void {                                // Intuit API 호스트로는 GET 과 POST …/query 만(이견 4)
  const m = String(method ?? "GET").toUpperCase(), path = new URL(url).pathname;
  if (m === "GET") return;
  if (m === "POST" && /\/query\/?$/.test(path)) return;
  throw new QboError(500, `refusing ${m} ${path} — this function only reads from QuickBooks (GET, or POST …/query)`);
}
// ── qbo-sync-2a′ 순수: 쓰기 허용 검사(apiWrite 가 부른다 · 그 밖은 던진다) · Fault code · 쓰기 결과 갈래 ──
export function assertWriteAllowed(method: string, url: string): void {
  const m = String(method ?? "").toUpperCase(), u = new URL(url), path = u.pathname;
  if (m !== "POST") throw new QboError(500, `refusing ${m} ${path} — writes to QuickBooks are POST only (create · void) · nothing is ever deleted`);
  const mm = /^\/v3\/company\/[^/]+\/([a-z]+)\/?$/.exec(path);
  if (!mm || !(WRITE_ENTITIES as readonly string[]).includes(mm[1])) throw new QboError(500, `refusing POST ${path} — this function only creates ${WRITE_ENTITIES.join(", ")} (and voids ${VOIDABLE_ENTITIES.join(", ")})`);
  const op = u.searchParams.get("operation"), inc = u.searchParams.get("include");
  if (op !== null) {                                                                                 // 2e-1c: void 꼴 둘 — invoice · creditmemo 는 operation=void · payment 는 operation=update&include=void · 그 밖 operation(update 만 · delete)은 없다
    const voidOk = op === "void" && (VOIDABLE_ENTITIES as readonly string[]).includes(mm[1]);
    const updVoidOk = op === "update" && inc === "void" && (UPDATE_VOID_ENTITIES as readonly string[]).includes(mm[1]);
    if (!voidOk && !updVoidOk) throw new QboError(500, `refusing POST ${path}?operation=${op}${inc !== null ? "&include=" + inc : ""} — only operation=void on ${VOIDABLE_ENTITIES.join(", ")} and operation=update&include=void on ${UPDATE_VOID_ENTITIES.join(", ")} · operation=delete is never sent`);
  } else if (inc !== null) throw new QboError(500, `refusing POST ${path}?include=${inc} — include is only sent with operation=update (void of a ${UPDATE_VOID_ENTITIES.join(", ")})`);
  const rid = u.searchParams.get("requestid") ?? "";
  if (!rid || rid.length > REQUESTID_MAX) throw new QboError(500, `refusing POST ${path} without a requestid (1 … ${REQUESTID_MAX} characters) — every write carries the job request_id`);
}
export const faultCode = (body: unknown): string | null => { const f = ((body && typeof body === "object" ? body : {}) as Record<string, unknown>).Fault as Record<string, unknown> | undefined; const e = Array.isArray(f?.Error) ? f!.Error[0] as Record<string, unknown> : null; return e && e.code != null ? String(e.code) : null; };
export type WriteClass = "ok" | "fail" | "unknown";
export function classifyWrite(status: number, networkError: string | null): WriteClass {               // 2xx 처리됨 · 4xx 처리 안 됨이 분명 · 5xx · 0(끊김) 은 모른다(QBO 에 닿았을 수 있다)
  if (networkError !== null || status === 0) return "unknown";
  if (status >= 200 && status < 300) return "ok";
  if (status >= 400 && status < 500) return "fail";
  return "unknown";
}
export const sqlQuote = (s: string): string => "'" + String(s ?? "").replace(/'/g, "''") + "'";          // QBO 조회 리터럴(따옴표 둘로)
export function stripPii<T>(entity: string, row: T): T {
  if (!(PII_ENTITIES as readonly string[]).includes(entity) || !row || typeof row !== "object") return row;
  const out = { ...(row as Record<string, unknown>) };
  for (const f of PII_FIELDS) delete out[f];
  return out as T;
}
export const readPath = (entity: string, realm: string, id: string | null): string => {
  const r = encodeURIComponent(realm);
  if (entity === "CompanyInfo") return `/v3/company/${r}/companyinfo/${r}`;
  if (entity === "Preferences") return `/v3/company/${r}/preferences`;
  return `/v3/company/${r}/${entity.toLowerCase()}/${encodeURIComponent(id ?? "")}`;
};

// ── Deps — 바깥은 전부 여기로(시험은 가짜) ──
export type LogRow = { env: string | null; realm_id: string | null; action: string; ok: boolean; http_status: number | null; intuit_tid: string | null; error: string | null; by_staff: string | null; ms: number; detail?: Record<string, unknown> | null };   // detail = query · read 의 요약만(20261101190000) · 결과 행 없음
export type Deps = {
  env: (name: string) => string | undefined;
  fetch: (url: string, init: RequestInit) => Promise<Response>;                                      // Intuit 만(DB 는 rpc)
  rpcUser: (fn: string, args: Record<string, unknown>, jwt: string) => Promise<unknown>;            // 사용자 JWT 그대로(DB 의 문이 그 사람을 본다) · 실패 RpcError
  rpcService: (fn: string, args: Record<string, unknown>) => Promise<unknown>;                       // service_role 창구 · 실패 RpcError
  log: (row: LogRow) => Promise<void>;                                                               // qbo_call_log 한 줄 + 90 일 지우기 — 던지지 않는다
  now: () => number;
  sleep: (ms: number) => Promise<void>;
  randomBytes: (n: number) => Uint8Array;
  uuid: () => string;
  warn: (msg: string) => void;                                                                       // 이미 scrub 된 글만 온다
  discovery: DiscoveryCache;
};
type Ctx = { d: Deps; secrets: string[]; env: Env | null; byStaff: string | null };
const json = (status: number, obj: unknown): Response => new Response(JSON.stringify(obj, null, 2), { status, headers: { "Content-Type": "application/json", ...CORS } });
const jsonCompact = (status: number, obj: unknown): Response => new Response(JSON.stringify(obj), { status, headers: { "Content-Type": "application/json", ...CORS } });   // query · read — 들여쓰기 없음(크기 · CPU · 이견 9)
const cfgOf = (d: Deps): { qboEnv: Env | null; raw: string | undefined } => { const raw = d.env("QBO_ENV"); return { qboEnv: envOf(raw), raw }; };
function clientOf(c: Ctx, env: Env): { id: string; secret: string } {
  const n = secretNames(env), id = (c.d.env(n.id) ?? "").trim(), secret = (c.d.env(n.secret) ?? "").trim();
  if (!id || !secret) throw new QboError(500, `QuickBooks ${env} app keys are not set (${n.id} · ${n.secret}) — refusing (fail-closed)`);
  c.secrets.push(secret);
  return { id, secret };
}
const sc = (c: Ctx, s: string) => scrub(s, c.secrets);

// ── Intuit 호출 하나 = 기록 한 줄 · 네트워크 · 5xx 만 1 회 재시도 · 2xx 가 아니어도 던지지 않고 돌려준다(갈래는 부르는 쪽이) ──
type IntuitResult = { status: number; body: unknown; tid: string | null; networkError: string | null; error: string | null; bytes: number };
async function intuitCall(c: Ctx, action: string, url: string, init: RequestInit, realm: string | null, retry = true, detailOf?: (r: IntuitResult) => Record<string, unknown> | null): Promise<IntuitResult> {
  const t0 = c.d.now();
  let r: IntuitResult = { status: 0, body: null, tid: null, networkError: null, error: null, bytes: 0 };
  for (let attempt = 0; attempt < 2; attempt++) {
    r = { status: 0, body: null, tid: null, networkError: null, error: null, bytes: 0 };
    try {
      const res = await c.d.fetch(url, init);
      r.status = res.status; r.tid = tidOf(res.headers);
      const text = await res.text();
      r.bytes = text.length;
      try { r.body = text ? JSON.parse(text) : null; } catch { r.body = text; }
      if (!res.ok) r.error = sc(c, intuitErrorText(r.status, r.body));
    } catch (e) {
      r.networkError = sc(c, String((e as Error)?.message ?? e).slice(0, 200));
      r.error = "Intuit " + action + " unreachable: " + r.networkError;
    }
    if (!(retry && attempt === 0 && isRetryable(r.status, r.networkError !== null))) break;
    await c.d.sleep(RETRY_DELAY_MS);
  }
  await c.d.log({ env: c.env, realm_id: realm, action, ok: r.error === null, http_status: r.status || null, intuit_tid: r.tid, error: r.error ? r.error.slice(0, 400) : null, by_staff: c.byStaff, ms: c.d.now() - t0, detail: detailOf ? detailOf(r) : null });
  return r;
}
const form = (o: Record<string, string>): string => new URLSearchParams(o).toString();
async function tokenCall(c: Ctx, action: "token_exchange" | "refresh", env: Env, endpoint: string, body: Record<string, string>, realm: string | null): Promise<IntuitResult> {
  const k = clientOf(c, env);
  return await intuitCall(c, action, endpoint, { method: "POST", headers: { Authorization: basicAuth(k.id, k.secret), Accept: "application/json", "Content-Type": "application/x-www-form-urlencoded" }, body: form(body) }, realm);
}
async function revokeCall(c: Ctx, env: Env, endpoint: string, refreshToken: string, realm: string | null): Promise<IntuitResult> {
  const k = clientOf(c, env);
  c.secrets.push(refreshToken);
  return await intuitCall(c, "revoke", endpoint, { method: "POST", headers: { Authorization: basicAuth(k.id, k.secret), Accept: "application/json", "Content-Type": "application/json" }, body: JSON.stringify({ token: refreshToken }) }, realm);
}
async function companyInfoCall(c: Ctx, env: Env, realm: string, access: string): Promise<IntuitResult> {
  c.secrets.push(access);
  const url = `${API_BASE[env]}/v3/company/${encodeURIComponent(realm)}/companyinfo/${encodeURIComponent(realm)}?minorversion=${MINOR_VERSION}`;
  return await intuitCall(c, "companyinfo", url, { method: "GET", headers: { Authorization: "Bearer " + access, Accept: "application/json" } }, realm);
}
const discoveryOf = (c: Ctx, env: Env) => c.d.discovery.get(env, async (url) => { const r = await c.d.fetch(url, { method: "GET", headers: { Accept: "application/json" } }); if (!r.ok) throw new Error("HTTP " + r.status); return await r.json(); }, c.d.now());

// ── 토큰 쥐기(갱신 포함) — qbo_token_get → 5 분 안이면 claim → Intuit refresh → save(판 번호) · 임대 못 받으면 기다렸다 다시 읽기 ──
type TokenRow = { env: Env; realm_id: string; status: string; token_version: number; access_expires_at: string; refresh_expires_at: string | null; refresh_token: string; access_token: string };
async function tokenGet(c: Ctx): Promise<TokenRow> {
  try {
    const t = await c.d.rpcService("qbo_token_get", {}) as TokenRow;
    c.secrets.push(t.access_token, t.refresh_token);
    return t;
  } catch (e) {
    if (e instanceof RpcError && /not connected/i.test(e.message)) throw new QboError(409, "QuickBooks is not connected — connect it in Settings → QuickBooks");
    throw e;
  }
}
function envGuard(c: Ctx, rowEnv: string): Env {
  const env = c.env;
  if (!env) throw new QboError(500, "QBO_ENV is not set (sandbox | production) — refusing (fail-closed)");
  if (rowEnv !== env) throw new QboError(409, `The QuickBooks connection on file is ${rowEnv} but this function runs as ${env} (QBO_ENV) — disconnect it in Settings → QuickBooks, then connect again`);
  return env;
}
export type Held = { access: string; env: Env; realm: string; token_version: number; access_expires_at: string; refresh_expires_at: string | null; refreshed: boolean };
async function ensureToken(c: Ctx, force: boolean): Promise<Held> {
  const t = await tokenGet(c);
  const env = envGuard(c, t.env);
  if (t.status === "needs_reconnect") throw new QboError(409, "QuickBooks needs to be reconnected — an admin can do it in Settings → QuickBooks → Reconnect");
  const held = (x: TokenRow, refreshed: boolean): Held => ({ access: x.access_token, env, realm: x.realm_id, token_version: x.token_version, access_expires_at: x.access_expires_at, refresh_expires_at: x.refresh_expires_at, refreshed });
  if (!force && new Date(t.access_expires_at).getTime() - c.d.now() > REFRESH_AHEAD_MS) return held(t, false);
  let claim: TokenRow & { refreshing_until: string };
  try {
    claim = await c.d.rpcService("qbo_refresh_claim", { p_owner: c.d.uuid() }) as TokenRow & { refreshing_until: string };
    c.secrets.push(claim.access_token, claim.refresh_token);
  } catch (e) {
    if (!(e instanceof RpcError)) throw e;
    if (/needs to be reconnected/i.test(e.message)) throw new QboError(409, "QuickBooks needs to be reconnected — an admin can do it in Settings → QuickBooks → Reconnect");
    if (!/Another refresh is running/i.test(e.message)) throw e;
    const t0 = c.d.now();                                                                           // 다른 갱신이 쥐고 있다 — 새 판이 저장될 때까지 기다렸다 읽는다
    while (c.d.now() - t0 < LEASE_WAIT_MS) {
      await c.d.sleep(LEASE_POLL_MS);
      const again = await tokenGet(c);
      if (again.status === "needs_reconnect") throw new QboError(409, "QuickBooks needs to be reconnected — an admin can do it in Settings → QuickBooks → Reconnect");
      if (again.token_version !== t.token_version) return held(again, true);
    }
    throw new QboError(503, "Another QuickBooks token refresh is still running — try again in a moment");
  }
  const disc = await discoveryOf(c, env);
  const r = await tokenCall(c, "refresh", env, disc.token_endpoint, { grant_type: "refresh_token", refresh_token: claim.refresh_token }, claim.realm_id);
  if (r.error) {
    if (needsReconnect(r.status, r.body)) {                                                         // invalid_grant — 다시 시도 안 함 · needs_reconnect(+ DB 가 메일 869 · 바뀌는 순간 한 번)
      const marked = await c.d.rpcService("qbo_mark_needs_reconnect", { p_error: r.error }) as { mailed?: boolean };
      throw new QboError(409, "QuickBooks refused the refresh token (invalid_grant) — the connection must be made again: Settings → QuickBooks → Reconnect" + (marked?.mailed ? " (alert mail queued)" : ""));
    }
    throw new QboError(502, "QuickBooks token refresh failed — " + r.error);                        // 임대는 30 s 뒤 풀린다 · 다음 호출이 다시 시도
  }
  const tk = parseTokenResponse(r.body, c.d.now());
  c.secrets.push(tk.access, tk.refresh);
  if (tk.assumedExpiresIn) c.d.warn("qbo refresh: expires_in missing in the token response — assumed " + ACCESS_EXPIRES_DEFAULT_S + " s");
  let saved: { token_version: number; access_expires_at: string; refresh_expires_at: string | null };
  try {
    saved = await c.d.rpcService("qbo_refresh_save", { p_version: claim.token_version, p_refresh: tk.refresh, p_access: tk.access, p_access_exp: tk.accessExp.toISOString(), p_refresh_exp: tk.refreshExp ? tk.refreshExp.toISOString() : null }) as typeof saved;
  } catch (e) {
    if (e instanceof RpcError && /stale/i.test(e.message)) {                                         // 판 번호 다름 = 새 토큰을 잃음 → last_error 와 사람 말(상태는 안 바꾼다)
      const msg = "Two refreshes raced: another one saved first and the token from this refresh was discarded. If QuickBooks answers invalid_grant at the next refresh, reconnect in Settings → QuickBooks";
      try { await c.d.rpcService("qbo_last_error_set", { p_error: msg }); } catch (e2) { c.d.warn("qbo_last_error_set failed: " + sc(c, String((e2 as Error)?.message ?? e2))); }
      throw new QboError(409, msg);
    }
    throw e;
  }
  return { access: tk.access, env, realm: claim.realm_id, token_version: saved.token_version, access_expires_at: saved.access_expires_at, refresh_expires_at: saved.refresh_expires_at, refreshed: true };
}

// ── 회사 이름 저장 — DB 창구가 거부하면 call_log 한 줄(action company_name · ok false · DB 거부 글) · last_error 는 안 쓴다(토큰 건강의 자리) · 돌려주는 값 = 오류 글 | null ──
async function companyNameSet(c: Ctx, env: Env, realm: string, name: string): Promise<string | null> {
  const t0 = c.d.now();
  try { await c.d.rpcService("qbo_company_name_set", { p_name: name }); return null; }
  catch (e) {
    const msg = sc(c, e instanceof RpcError ? e.message : String((e as Error)?.message ?? e)).slice(0, 400);
    await c.d.log({ env, realm_id: realm, action: "company_name", ok: false, http_status: null, intuit_tid: null, error: msg, by_staff: c.byStaff, ms: c.d.now() - t0 });
    return msg;
  }
}

// ── Intuit API 호출 하나(qbo-read-1) — API 호스트로 나가는 모든 읽기가 여기를 지난다 · GET 과 POST …/query 만(assertReadOnlyRequest · 그 밖은 던진다) ──
async function apiCall(c: Ctx, action: string, h: Held, path: string, query: Record<string, string>, detailOf?: (r: IntuitResult) => Record<string, unknown> | null): Promise<IntuitResult> {
  c.secrets.push(h.access);
  const u = new URL(API_BASE[h.env] + path);
  for (const [k, v] of Object.entries(query)) u.searchParams.set(k, v);
  u.searchParams.set("minorversion", MINOR_VERSION);
  assertReadOnlyRequest("GET", u.toString());
  return await intuitCall(c, action, u.toString(), { method: "GET", headers: { Authorization: "Bearer " + h.access, Accept: "application/json" } }, h.realm, true, detailOf);
}
// ── Intuit API 쓰기 하나(qbo-sync-2a′) — API 호스트로 나가는 모든 쓰기가 여기를 지난다 · POST · 허용 목록(assertWriteAllowed) · requestid 필수 · ⚠️ 자동 재시도 없음(retry false) · 몸은 기록하지 않는다(detailOf 는 job id 만) ──
async function apiWrite(c: Ctx, action: string, h: Held, path: string, query: Record<string, string>, bodyObj: unknown, detailOf?: (r: IntuitResult) => Record<string, unknown> | null): Promise<IntuitResult> {
  c.secrets.push(h.access);
  const u = new URL(API_BASE[h.env] + path);
  for (const [k, v] of Object.entries(query)) u.searchParams.set(k, v);
  u.searchParams.set("minorversion", MINOR_VERSION);
  assertWriteAllowed("POST", u.toString());
  return await intuitCall(c, action, u.toString(), { method: "POST", headers: { Authorization: "Bearer " + h.access, Accept: "application/json", "Content-Type": "application/json" }, body: JSON.stringify(bodyObj) }, h.realm, false, detailOf);
}
// ── 401 한 번(이견 6) — 접근 토큰으로 부르고 401 이면 강제 갱신 한 번 뒤 다시 · 그래도 401 이면 needs_reconnect(ping · query · read 가 같이 쓴다) ──
async function withAuthRetry(c: Ctx, call: (h: Held) => Promise<IntuitResult>): Promise<{ h: Held; r: IntuitResult }> {
  let h = await ensureToken(c, false);
  let r = await call(h);
  if (r.status === 401) {
    h = await ensureToken(c, true);
    r = await call(h);
    if (r.status === 401) {
      await c.d.rpcService("qbo_mark_needs_reconnect", { p_error: "QuickBooks rejected the access token right after a refresh (401) — the connection was probably revoked on the QuickBooks side" });
      throw new QboError(409, "QuickBooks rejected the token even after a refresh — the connection must be made again: Settings → QuickBooks → Reconnect");
    }
  }
  return { h, r };
}

// ── 핑 — CompanyInfo → company_name · 401 은 withAuthRetry ──
async function ping(c: Ctx): Promise<{ company_name: string; realm_id: string; env: Env; refreshed: boolean }> {
  const { h, r } = await withAuthRetry(c, (x) => companyInfoCall(c, x.env, x.realm, x.access));
  if (r.error) throw new QboError(502, "QuickBooks CompanyInfo failed — " + r.error);
  const name = companyNameOf(r.body);
  if (!name) throw new QboError(502, "QuickBooks CompanyInfo answered without CompanyName");
  const err = await companyNameSet(c, h.env, h.realm, name);
  if (err) throw new QboError(422, "QuickBooks answered, but the company name could not be saved — " + err);
  return { company_name: name, realm_id: h.realm, env: h.env, refreshed: h.refreshed };
}

// ── query(qbo-read-1) — { q } → GET /query?query=… · 응답 { ok, entity, rows, count, totalCount, startPosition, maxResults, more, intuit_tid } · rows 는 scrub 없이 그대로 ──
function readFailure(what: string, r: IntuitResult): QboError {
  if (r.bytes > RESPONSE_MAX_BYTES) return new QboError(413, `QuickBooks answered with ${(r.bytes / 1048576).toFixed(1)} MB — lower MAXRESULTS (limit ${RESPONSE_MAX_BYTES / 1048576} MB per call)`);
  if (r.status === 400) return new QboError(400, `QuickBooks rejected the ${what} — ` + r.error);
  if (r.status === 429) return new QboError(429, "QuickBooks rate limit (429) — wait a moment and call again (no automatic retry)");
  return new QboError(502, `QuickBooks ${what} failed — ` + r.error);
}
async function query(c: Ctx, body: Record<string, unknown>): Promise<Response> {
  const p = parseQuery(body.q);
  const qlog = queryForLog(p.text);
  const detailOf = (r: IntuitResult): Record<string, unknown> => {
    const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
    const rows = Array.isArray(qr[p.entity]) ? (qr[p.entity] as unknown[]).length : 0;
    return { entity: p.entity, rows, totalCount: typeof qr.totalCount === "number" ? qr.totalCount : null, startPosition: typeof qr.startPosition === "number" ? qr.startPosition : p.startPosition, maxResults: typeof qr.maxResults === "number" ? qr.maxResults : p.maxResults, q: qlog, bytes: r.bytes };
  };
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "query", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
  if (r.error || r.bytes > RESPONSE_MAX_BYTES) throw readFailure("query", r);
  const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
  const rows = Array.isArray(qr[p.entity]) ? qr[p.entity] as unknown[] : [];
  const maxResults = typeof qr.maxResults === "number" ? qr.maxResults : p.maxResults;
  return jsonCompact(200, { ok: true, entity: p.entity, rows, count: rows.length, totalCount: typeof qr.totalCount === "number" ? qr.totalCount : null,
    startPosition: typeof qr.startPosition === "number" ? qr.startPosition : p.startPosition, maxResults, more: !p.isCount && rows.length >= maxResults, intuit_tid: r.tid });
}
// ── read(qbo-read-1) — { entity, id } → GET /<entity>/<id> · Preferences · CompanyInfo 는 id 없이 · Customer · Vendor 는 연락처 · 주소 칸을 빼고 ──
async function read(c: Ctx, body: Record<string, unknown>): Promise<Response> {
  const entity = canonicalEntity(String(body.entity ?? ""), [...QUERY_ENTITIES, ...READ_SINGLETONS]);
  if (!entity) throw new QboError(400, `entity ${String(body.entity ?? "")} is not readable here — allowed: ${[...QUERY_ENTITIES, ...READ_SINGLETONS].join(", ")}`);
  const singleton = (READ_SINGLETONS as readonly string[]).includes(entity);
  const id = singleton ? null : String(body.id ?? "").trim();
  if (!singleton && !/^[0-9]{1,20}$/.test(id ?? "")) throw new QboError(400, "id must be a number (the QuickBooks Id of the " + entity + ")");
  const detailOf = (r: IntuitResult): Record<string, unknown> => ({ entity, id, rows: r.body && typeof r.body === "object" && (r.body as Record<string, unknown>)[entity] ? 1 : 0, bytes: r.bytes });
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "read", h, readPath(entity, h.realm, id), {}, detailOf));
  if (r.error || r.bytes > RESPONSE_MAX_BYTES) throw readFailure("read", r);
  const row = (r.body as Record<string, unknown>)?.[entity] ?? null;
  return jsonCompact(200, { ok: true, entity, id, row: stripPii(entity, row), intuit_tid: r.tid });
}

// ── pull(qbo-sync-1b) — { entity, start? } → 한 쪽을 qbo_entity 에 · start 1 = 새 run(begin restart) · 받은 수 < 1000 이면 finish · 창구는 사용자 JWT ──
async function pull(c: Ctx, body: Record<string, unknown>, jwt: string): Promise<Response> {
  const entity = canonicalEntity(String(body.entity ?? ""), PULL_ENTITIES);
  if (!entity) throw new QboError(400, `entity must be one of ${PULL_ENTITIES.join(", ")} (got ${String(body.entity ?? "")}) — pull reads only the lists IMS links to`);
  const start = body.start === undefined || body.start === null || body.start === "" ? 1 : Number(body.start);
  if (!(Number.isInteger(start) && start >= 1)) throw new QboError(400, "start must be a whole number of 1 or more (the STARTPOSITION of the page to fetch; omit it for a new pull)");
  const p = parseQuery(pullQueryText(entity, start));                                               // 같은 검사(허용 목록 · 연락처 칸 · MAXRESULTS ≤ 1000)를 지난다
  const page = Math.floor((start - 1) / PULL_PAGE) + 1;
  const h0 = await ensureToken(c, false);                                                           // realm(연결된 회사) — begin 은 조회 앞
  if (start === 1) await c.d.rpcUser("qbo_pull_begin", { p_realm: h0.realm, p_type: entity, p_restart: true }, jwt);
  const detailOf = (r: IntuitResult): Record<string, unknown> => {
    const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
    return { entity, rows: Array.isArray(qr[entity]) ? (qr[entity] as unknown[]).length : 0, start, page, bytes: r.bytes };
  };
  const { h, r } = await withAuthRetry(c, (x) => apiCall(c, "pull", x, `/v3/company/${encodeURIComponent(x.realm)}/query`, { query: p.text }, detailOf));
  if (r.error || r.bytes > RESPONSE_MAX_BYTES) throw readFailure("pull", r);
  const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
  const rows = Array.isArray(qr[entity]) ? qr[entity] as unknown[] : [];
  let up: { received: number; pages: number; next_start: number };
  try { up = await c.d.rpcUser("qbo_entity_upsert", { p_realm: h.realm, p_type: entity, p_rows: rows, p_next_start: start + PULL_PAGE }, jwt) as typeof up; }
  catch (e) {
    if (e instanceof RpcError && /No pull in progress/i.test(e.message)) throw new QboError(409, e.message + " — start the pull again with start 1 (or omit start)");
    throw e;
  }
  const done = rows.length < PULL_PAGE;
  const fin = done ? await c.d.rpcUser("qbo_pull_finish", { p_realm: h.realm, p_type: entity }, jwt) as { gone: number; finished_at: string; received: number; pages: number } : null;
  return jsonCompact(200, { ok: true, entity, start, received_now: rows.length, received: up.received, pages: up.pages, next_start: done ? null : start + PULL_PAGE, done, gone: fin?.gone ?? null, finished_at: fin?.finished_at ?? null, intuit_tid: r.tid });
}

// ── send(qbo-sync-2a′ · 열쇠 qbo · [2b2] cron 길도 · 판정 935 ~ 946 · 951) — ① unknown 일감을 이름 · DocNumber 로 조회해 풀기(있으면 done · 없으면 그대로 · 둘 이상이면 그대로) ② claim(p_kinds = SEND_KINDS) → 일감마다 POST 한 번(requestid = request_id)
//    customer · item: 2xx done · 4xx fail(6240 Item 은 ` [SKU]` 로 다른 requestid 한 번 더) · 5xx · 끊김 · 몸 없음 unknown(보낸 이름을 남긴다)
//    invoice(2b2): 만들기 전 DocNumber 조회(멱등 · 있으면 만들지 않고 읽어서 done + note · 둘 이상이면 failed) → POST invoice → 2xx done(TotalAmt · TxnTaxDetail.TotalTax 를 DB 가 942 로 견준다 · 다르면 DB 가 mismatch) · 6140 · 6210 중복 번호면 다시 조회해 있으면 done · 그 밖 4xx failed · 5xx · 끊김 unknown(DocNumber 를 남긴다)
//    invoice_void(2b2): POST invoice?operation=void {Id, SyncToken} · SyncToken 없으면 먼저 읽는다 · 5010 Stale Object 면 읽어서 한 번 더(requestid -2) · 2xx done(voided_at 은 DB) · 4xx failed(결제가 붙었다 · 마감 등 — 사람) · 5xx · 끊김 unknown
//    unknown 풀기(2b2): invoice 는 DocNumber 조회 → 하나면 읽어서 합계와 함께 done · invoice_void 는 DocNumber 조회 → 읽어서 TotalAmt 0 이면(QBO 는 void 한 인보이스의 금액을 0 으로 둔다 — 짐작 · 첫 실물에서 확인) done · 아니면 not_voided(사람이 retry)
//    credit · credit_void(2c1): 위 invoice · invoice_void 와 같은 길 — 엔티티 열쇠(creditmemo · CreditMemo · DocNumber)만 다르다(findByDocNumber · readTxn · doneTxn 이 열쇠를 받는다) ──
type ClaimJob = { job_id: string; kind: string; ims_kind: string; ims_id: string; attempt: number; request_id: string; name: string; name_alt: string | null; sku: string | null; doc_number?: string | null; qbo_id?: string | null; body: Record<string, unknown>; warnings: string[]; totals?: Record<string, unknown> | null;
  fingerprint?: string | null; check_lines?: { txn_type?: string; invoice_number?: string; qbo_invoice_id?: string; credit_number?: string; qbo_creditmemo_id?: string; amount: number }[] | null; lookup?: Record<string, unknown> | null };   // 2e-1c 결제: (가) 가드 줄 · unknown 열쇠(1b claim) · [2e-2-1b txn_type Invoice | CreditMemo · credit_number · qbo_creditmemo_id — DB qbo_credit_apply_body 꼴]
type NeedJob = { job_id: string; kind: string; ims_kind: string; ims_id: string; state: string; name: string | null; existing: boolean; for_job: string; parent_job: string | null };
type Requested = { job_id: string; kind: string | null; state: string | null; result: string; reason: string | null };
type ClaimResult = { recovered_unknown: number; unblocked: number; claimed: number; body_failed: number; blocked_for_needs?: number; blocked_for_invoice?: number; need_jobs?: NeedJob[]; requested?: Requested[]; jobs: ClaimJob[] };
type UnknownRow = { job_id: string; kind: string; ims_kind: string; ims_id: string; qbo_name: string | null; sku: string | null; request_id: string; attempts: number };
type JobOut = { job_id: string; kind: string; ims_kind: string; ims_id: string; name: string; state: string; qbo_id: string | null; error: string | null; note: string | null; linked?: boolean; link_error?: string | null; mismatch?: string | null };
type EntityKey = { path: string; key: string; nameField: string };
const entityKeyOf = (kind: string): EntityKey => kind === "customer" ? { path: "customer", key: "Customer", nameField: "DisplayName" } : kind === "item" ? { path: "item", key: "Item", nameField: "Name" }
  : kind === "credit" || kind === "credit_void" ? { path: "creditmemo", key: "CreditMemo", nameField: "DocNumber" }
  : kind === "credit_apply" || kind === "credit_apply_void" ? { path: "payment", key: "Payment", nameField: "PrivateNote" }   // 2e-2-1b 0 원 Payment(PaymentRefNum 없음 · 이름은 PrivateNote)
  : kind === "payment" || kind === "payment_void" ? { path: "payment", key: "Payment", nameField: "PaymentRefNum" } : { path: "invoice", key: "Invoice", nameField: "DocNumber" };   // 2c1 credit → CreditMemo · [2e-1c payment → Payment]
const isTxnKind = (kind: string): boolean => (TXN_KINDS as readonly string[]).includes(kind);
const isPaymentKind = (kind: string): boolean => (PAYMENT_KINDS as readonly string[]).includes(kind);                            // 2e-1c
const isCreditApplyKind = (kind: string): boolean => (CREDIT_APPLY_KINDS as readonly string[]).includes(kind);                   // 2e-2-1b
const isNeedKind = (kind: string): boolean => kind === "customer" || kind === "item";                                           // 2e-2-1b 960: 같은 호출에서 대신 보내는 need 는 손님 · Item(· 부모 손님)뿐 — 거래 · void 는 북키퍼가 고른다
// 2e-1c 결제 unknown 열쇠 — qbo_job.qbo_name 한 칸에 「<PrivateNote>|<CustomerRef>|<TxnDate>|<TotalAmt>」(PrivateNote = 「IMS payment <uuid>」) · void 는 QBO Payment Id 만
export const paymentKeyOf = (lookup: Record<string, unknown> | null | undefined, body: Record<string, unknown>): string => {
  const l = lookup ?? {};
  const note = String(l.private_note ?? body.PrivateNote ?? ""), cust = String(l.customer_ref ?? ((body.CustomerRef ?? {}) as Record<string, unknown>).value ?? ""), date = String(l.txn_date ?? body.TxnDate ?? ""), amt = String(l.total_amt ?? body.TotalAmt ?? "");
  return [note, cust, date, amt].join("|");
};
export const parsePaymentKey = (s: string | null): { privateNote: string; customerRef: string; txnDate: string; totalAmt: number } | null => {
  const parts = String(s ?? "").split("|");
  if (parts.length !== 4 || !(parts[0].startsWith("IMS payment ") || parts[0].startsWith("IMS credit applied ")) || !/^\d{4}-\d{2}-\d{2}$/.test(parts[2]) || Number.isNaN(Date.parse(parts[2] + "T00:00:00Z")) || new Date(parts[2] + "T00:00:00Z").toISOString().slice(0, 10) !== parts[2] || !Number.isFinite(Number(parts[3]))) return null;
  return { privateNote: parts[0], customerRef: parts[1], txnDate: parts[2], totalAmt: Number(parts[3]) };
};
export const paymentsByDateQueryText = (date: string): string => `select Id, TotalAmt, UnappliedAmt, SyncToken, PrivateNote, PaymentRefNum, CustomerRef, TxnDate from Payment where TxnDate = ${sqlQuote(date)} MAXRESULTS 100`;   // PII 칸 없음(parseQuery 통과) · 하루치(실물 최대 64/일)
export const isVoidedPayment = (row: Record<string, unknown> | null): boolean => !!row && (num(row.TotalAmt) ?? -1) === 0 && String(row.PrivateNote ?? "").startsWith("Voided");   // sandbox B-6: TotalAmt 0 · PrivateNote 「Voided - …」
const txnWord = (e: EntityKey): string => e.key === "CreditMemo" ? "credit memo" : "invoice";                           // 사람 글의 낱말(failed · note)
const createdIdOf = (body: unknown, key: string): string | null => { const row = (body as Record<string, unknown>)?.[key] as Record<string, unknown> | undefined; return row && row.Id != null ? String(row.Id) : null; };
const rowOf = (body: unknown, key: string): Record<string, unknown> | null => { const row = (body as Record<string, unknown>)?.[key]; return row && typeof row === "object" && (row as Record<string, unknown>).Id != null ? row as Record<string, unknown> : null; };
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v)) ? Number(v) : null);
export const invoiceTotals = (row: Record<string, unknown> | null): { total_amt: number | null; total_tax: number | null } =>
  ({ total_amt: num(row?.TotalAmt), total_tax: num(((row?.TxnTaxDetail ?? {}) as Record<string, unknown>).TotalTax) });
const docNumberQueryText = (doc: string, key = "Invoice"): string => `select Id, DocNumber, SyncToken, TotalAmt from ${key} where DocNumber = ${sqlQuote(doc)}`;   // PII 칸 없음(parseQuery 통과) · [2c1] CreditMemo 도
const jobDetail = (j: { job_id: string; kind: string; ims_kind: string; ims_id: string }, extra: Record<string, unknown> = {}): Record<string, unknown> => ({ job_id: j.job_id, kind: j.kind, ims_kind: j.ims_kind, ims_id: j.ims_id, ...extra });
// DocNumber 로 찾기(send_check · GET …/query) — rows(0 · 1 · n) · 실패면 error
async function findByDocNumber(c: Ctx, doc: string, j: { job_id: string; kind: string; ims_kind: string; ims_id: string }, e: EntityKey = entityKeyOf(j.kind)): Promise<{ r: IntuitResult; rows: Record<string, unknown>[] }> {
  const p = parseQuery(docNumberQueryText(doc, e.key));
  const detailOf = (r: IntuitResult): Record<string, unknown> => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return jobDetail(j, { rows: Array.isArray(qr[e.key]) ? (qr[e.key] as unknown[]).length : 0, q: queryForLog(p.text) }); };
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "send_check", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
  const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
  return { r, rows: r.error ? [] : Array.isArray(qr[e.key]) ? qr[e.key] as Record<string, unknown>[] : [] };
}
// 거래 한 장 읽기(send_read · GET …/invoice/<id> · [2c1] …/creditmemo/<id>) — 합계 · SyncToken 을 쓰려고 · 행은 돌려주되 기록 · 응답에는 싣지 않는다
async function readTxn(c: Ctx, id: string, j: { job_id: string; kind: string; ims_kind: string; ims_id: string }, e: EntityKey = entityKeyOf(j.kind)): Promise<{ r: IntuitResult; row: Record<string, unknown> | null }> {
  const detailOf = (r: IntuitResult): Record<string, unknown> => jobDetail(j, { qbo_id: id, rows: rowOf(r.body, e.key) ? 1 : 0 });
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "send_read", h, readPath(e.key, h.realm, id), {}, detailOf));
  return { r, row: r.error ? null : rowOf(r.body, e.key) };
}
// 2e-1c 그 날의 Payment 전부(send_check · GET …/query) — 풀기 쪽이 CustomerRef · TotalAmt · PrivateNote 로 고른다
async function findPaymentsByDate(c: Ctx, date: string, j: { job_id: string; kind: string; ims_kind: string; ims_id: string }): Promise<{ r: IntuitResult; rows: Record<string, unknown>[] }> {
  const p = parseQuery(paymentsByDateQueryText(date));
  const detailOf = (r: IntuitResult): Record<string, unknown> => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return jobDetail(j, { rows: Array.isArray(qr.Payment) ? (qr.Payment as unknown[]).length : 0, q: queryForLog(p.text) }); };
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "send_check", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
  const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
  return { r, rows: r.error ? [] : Array.isArray(qr.Payment) ? qr.Payment as Record<string, unknown>[] : [] };
}
// 2e-1c 결제 done — 10 인자(p_unapplied_amt · DB 가 amount · amount − Σ붙임 과 견준다 · total_tax 는 null)
async function donePayment(c: Ctx, jobId: string, row: Record<string, unknown>, name: string, tid: string | null, note: string | null): Promise<Record<string, unknown>> {
  return await c.d.rpcService("qbo_job_done", { p_job: jobId, p_qbo_id: String(row.Id), p_qbo_name: name, p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: tid, p_note: note, p_sku: null, p_total_amt: num(row.TotalAmt), p_total_tax: null, p_unapplied_amt: num(row.UnappliedAmt) }) as Record<string, unknown>;
}
async function doneTxn(c: Ctx, jobId: string, row: Record<string, unknown>, doc: string, tid: string | null, note: string | null): Promise<Record<string, unknown>> {
  const t = invoiceTotals(row);
  return await c.d.rpcService("qbo_job_done", { p_job: jobId, p_qbo_id: String(row.Id), p_qbo_name: String(row.DocNumber ?? doc), p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: tid, p_note: note, p_sku: null, p_total_amt: t.total_amt, p_total_tax: t.total_tax }) as Record<string, unknown>;
}
async function resolveUnknown(c: Ctx, u: UnknownRow): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = { job_id: u.job_id, kind: u.kind, ims_kind: u.ims_kind, ims_id: u.ims_id };
  if (!u.qbo_name) return { ...out, result: "no_name", message: "the name that was sent is not on the job — retry it by hand after checking QuickBooks" };
  if (isPaymentKind(u.kind) || isCreditApplyKind(u.kind)) {                                          // 2e-1c — 결제: 열쇠(날짜 · 손님 · 금액 · PrivateNote) · void 는 Id 로 읽어 Voided 인지 · [2e-2-1b 크레딧 붙임도 이 문으로(0 원 Payment)]
    const e = entityKeyOf(u.kind);
    if (u.kind === "payment_void" || u.kind === "credit_apply_void") {                               // [2e-2-1b credit_apply_void 도 같은 길 — Id 로 읽어 Voided 면 done]
      const rd = await readTxn(c, u.qbo_name, u, e);
      if (rd.r.error || !rd.row) return { ...out, result: "not_found", message: `QuickBooks payment #${u.qbo_name} could not be read (${rd.r.error ?? "no row"}) — check by hand, then retry or skip the job` };
      if (!isVoidedPayment(rd.row)) return { ...out, result: "not_voided", qbo_id: String(rd.row.Id), message: "the QuickBooks payment still carries an amount — the void did not go through; retry the job by hand" };
      const d = await c.d.rpcService("qbo_job_done", { p_job: u.job_id, p_qbo_id: String(rd.row.Id), p_qbo_name: String(rd.row.PaymentRefNum ?? ("payment " + String(rd.row.Id))), p_sync_token: rd.row.SyncToken != null ? String(rd.row.SyncToken) : null, p_intuit_tid: rd.r.tid, p_note: "result was unknown — the QuickBooks payment is voided (amount 0)", p_sku: null }) as Record<string, unknown>;
      return { ...out, result: "found", qbo_id: String(rd.row.Id), state: d?.state ?? "sent" };
    }
    const k = parsePaymentKey(u.qbo_name);
    if (!k) return { ...out, result: "no_name", message: "the payment key on the job is not readable — retry it by hand after checking QuickBooks" };
    const { r, rows } = await findPaymentsByDate(c, k.txnDate, u);
    if (r.error) return { ...out, result: "error", message: "the QuickBooks check failed: " + r.error };
    if (u.kind === "credit_apply") {                                                                 // 2e-2-1b — 0 원 Payment: 손님 · TotalAmt 0 · PrivateNote 완전 일치(void 된 장은 「Voided - 」 가 붙어 빠진다) · Voided 제외 · DocNumber 조회 없음
      const ch = rows.filter((p) => String(((p.CustomerRef ?? {}) as Record<string, unknown>).value ?? "") === k.customerRef && num(p.TotalAmt) === 0 && String(p.PrivateNote ?? "") === k.privateNote && !isVoidedPayment(p));
      if (ch.length === 0) return { ...out, result: "not_found", message: `QuickBooks has no 0.00 payment on ${k.txnDate} for customer ${k.customerRef} with note "${k.privateNote}" — if it really is not there, retry the job by hand (Sales → QuickBooks)` };
      if (ch.length > 1) return { ...out, result: "ambiguous", rows: ch.length, message: `QuickBooks has ${ch.length} 0.00 payments matching this credit application — pick by hand (skip the job and link, or void the extra in QuickBooks)` };
      const d = await donePayment(c, u.job_id, ch[0], k.privateNote, r.tid, "result was unknown — found in QuickBooks by date, customer, amount 0 and note, and recorded");
      return { ...out, result: "found", qbo_id: String(ch[0].Id), state: d?.state ?? "sent", mismatch: (d?.mismatch as string | null) ?? null };
    }
    const hits = rows.filter((p) => String(((p.CustomerRef ?? {}) as Record<string, unknown>).value ?? "") === k.customerRef && num(p.TotalAmt) === k.totalAmt && String(p.PrivateNote ?? "").includes(k.privateNote));
    if (hits.length === 0) return { ...out, result: "not_found", message: `QuickBooks has no payment on ${k.txnDate} for customer ${k.customerRef} of ${k.totalAmt} with note "${k.privateNote}" — if it really is not there, retry the job by hand (Sales → QuickBooks)` };
    if (hits.length > 1) return { ...out, result: "ambiguous", rows: hits.length, message: `QuickBooks has ${hits.length} payments matching this one — pick by hand (skip the job and link, or void the extra in QuickBooks)` };
    const d = await donePayment(c, u.job_id, hits[0], String(hits[0].PaymentRefNum ?? k.privateNote), r.tid, "result was unknown — found in QuickBooks by date, customer, amount and note, and recorded");
    return { ...out, result: "found", qbo_id: String(hits[0].Id), state: d?.state ?? "sent", mismatch: (d?.mismatch as string | null) ?? null };
  }
  if (isTxnKind(u.kind)) {                                                                             // 2b2 — DocNumber 로 · [2c1] credit · credit_void 도(CreditMemo)
    const e = entityKeyOf(u.kind), word = txnWord(e), isVoid = u.kind.endsWith("_void");
    const { r, rows } = await findByDocNumber(c, u.qbo_name, u, e);
    if (r.error) return { ...out, result: "check_failed", error: r.error };
    if (rows.length === 0) return { ...out, result: "not_found", message: !isVoid ? `QuickBooks has no ${word} with that number — if it really is not there, retry the job by hand (Settings → QuickBooks)` : `QuickBooks has no ${word} with that number — nothing to void; skip the job by hand` };
    if (rows.length > 1) return { ...out, result: "ambiguous", count: rows.length, message: `more than one QuickBooks ${word} has that number — fix by hand` };
    const rd = await readTxn(c, String(rows[0].Id), u, e);
    if (rd.r.error || !rd.row) return { ...out, result: "check_failed", error: rd.r.error ?? `${word} could not be read` };
    if (isVoid && (num(rd.row.TotalAmt) ?? -1) !== 0) return { ...out, result: "not_voided", qbo_id: String(rd.row.Id), message: `the QuickBooks ${word} still carries an amount — the void did not go through; retry the job by hand` };
    const d = await doneTxn(c, u.job_id, rd.row, u.qbo_name, rd.r.tid, !isVoid ? "result was unknown — found in QuickBooks by DocNumber and recorded" : `result was unknown — the QuickBooks ${word} is voided (amount 0)`);
    return { ...out, result: "found", qbo_id: String(rd.row.Id), state: d?.state ?? null, mismatch: d?.mismatch ?? null, link_error: d?.link_error ?? null };
  }
  const e = entityKeyOf(u.kind);
  const p = parseQuery(`select Id, ${e.nameField}${u.kind === "item" ? ", Sku" : ""}, SyncToken from ${e.key} where ${e.nameField} = ${sqlQuote(u.qbo_name)}`);
  const detailOf = (r: IntuitResult): Record<string, unknown> => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return jobDetail(u, { rows: Array.isArray(qr[e.key]) ? (qr[e.key] as unknown[]).length : 0, q: queryForLog(p.text) }); };
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "send_check", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
  if (r.error) return { ...out, result: "check_failed", error: r.error };                                           // 다음 send 가 다시 본다
  const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
  const rows = Array.isArray(qr[e.key]) ? qr[e.key] as Record<string, unknown>[] : [];
  if (rows.length === 0) return { ...out, result: "not_found", message: "QuickBooks has no record with that name — if it really is not there, retry the job by hand (Settings → QuickBooks)" };
  if (rows.length > 1) return { ...out, result: "ambiguous", count: rows.length, message: "more than one QuickBooks record has that name — link it by hand" };
  const row = rows[0];
  const d = await c.d.rpcService("qbo_job_done", { p_job: u.job_id, p_qbo_id: String(row.Id), p_qbo_name: String(row[e.nameField] ?? u.qbo_name), p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: r.tid,
    p_note: "result was unknown — found in QuickBooks by name and linked", p_sku: typeof row.Sku === "string" ? row.Sku : u.sku }) as Record<string, unknown>;
  return { ...out, result: "found", qbo_id: String(row.Id), state: d?.state ?? null, linked: d?.linked ?? null, link_error: d?.link_error ?? null };
}
async function sendOne(c: Ctx, j: ClaimJob): Promise<JobOut> {
  const e = entityKeyOf(j.kind);
  const base: JobOut = { job_id: j.job_id, kind: j.kind, ims_kind: j.ims_kind, ims_id: j.ims_id, name: j.name, state: "sending", qbo_id: null, error: null, note: null };
  const attempt = (bodyObj: Record<string, unknown>, requestId: string, query: Record<string, string> = {}) => withAuthRetry(c, (h) => apiWrite(c, "send", h, `/v3/company/${encodeURIComponent(h.realm)}/${e.path}`, { ...query, requestid: requestId }, bodyObj,
    (r) => jobDetail(j, { request_id: requestId, attempt: j.attempt, qbo_id: createdIdOf(r.body, e.key), fault: faultCode(r.body), ...(query.operation ? { operation: query.operation } : {}), ...(query.include ? { include: query.include } : {}) })));
  const fail = async (err: string, tid: string | null): Promise<JobOut> => { await c.d.rpcService("qbo_job_fail", { p_job: j.job_id, p_error: err, p_intuit_tid: tid }); return { ...base, state: "failed", error: err }; };
  const unknown = async (err: string, tid: string | null, nameSent: string): Promise<JobOut> => { await c.d.rpcService("qbo_job_unknown", { p_job: j.job_id, p_error: err, p_intuit_tid: tid, p_name: nameSent }); return { ...base, name: nameSent, state: "unknown", error: err }; };
  let nameSent = j.name, note: string | null = null;
  try {
    if (j.kind === "invoice" || j.kind === "credit") {                                                  // 2b2 · [2c1 credit] — 멱등: DocNumber 가 이미 있으면 만들지 않는다
      const word = txnWord(e);
      const doc = String(j.doc_number ?? j.name); nameSent = doc;
      const pre = await findByDocNumber(c, doc, j, e);
      if (pre.r.error) return await fail("not sent — the DocNumber check failed before sending: " + pre.r.error, pre.r.tid);
      if (pre.rows.length > 1) return await fail(`not sent — QuickBooks already has ${pre.rows.length} ${word}s with number ${doc} — fix by hand, then retry or skip`, pre.r.tid);
      if (pre.rows.length === 1) {
        const rd = await readTxn(c, String(pre.rows[0].Id), j, e);
        if (rd.r.error || !rd.row) return await fail(`not sent — ${word} ` + doc + " is already in QuickBooks (#" + String(pre.rows[0].Id) + ") but could not be read: " + (rd.r.error ?? "no row"), rd.r.tid);
        note = "already in QuickBooks (DocNumber found before sending) — recorded, not created again";
        const d = await doneTxn(c, j.job_id, rd.row, doc, rd.r.tid, note);
        return { ...base, name: doc, state: String(d?.state ?? "sent"), qbo_id: String(rd.row.Id), note, mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
      }
      let { r } = await attempt(j.body, j.request_id);
      let cls = classifyWrite(r.status, r.networkError);
      if (cls === "fail" && (DUPLICATE_DOCNUMBER_CODES as readonly string[]).includes(faultCode(r.body) ?? "")) {   // 번호가 이미 있다(우리 멱등 조회 뒤에 생겼거나 Cin7 이 보낸 번호) → 다시 찾아서 있으면 그것
        const again = await findByDocNumber(c, doc, j, e);
        if (!again.r.error && again.rows.length === 1) {
          const rd = await readTxn(c, String(again.rows[0].Id), j, e);
          if (!rd.r.error && rd.row) {
            note = `QuickBooks answered duplicate DocNumber (${faultCode(r.body)}) — the existing ${word} #${String(rd.row.Id)} was recorded instead`;
            const d = await doneTxn(c, j.job_id, rd.row, doc, rd.r.tid, note);
            return { ...base, name: doc, state: String(d?.state ?? "sent"), qbo_id: String(rd.row.Id), note, mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
          }
        }
        return await fail((r.error ?? "duplicate DocNumber") + ` — and the ${word} could not be found by number afterwards (` + (again.r.error ?? again.rows.length + " rows") + ") — check QuickBooks by hand", r.tid);
      }
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the created ${e.key} — checked by number at the next send`, r.tid, doc);
        const d = await doneTxn(c, j.job_id, row, doc, r.tid, null);
        return { ...base, name: doc, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail(r.error ?? ("HTTP " + r.status), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, doc);
    }
    if (j.kind === "payment") {                                                                        // 2e-1c — (가) Balance 가드(check_lines 마다 GET invoice/<id>) → POST payment → done 10 인자 · unknown 은 열쇠를 남긴다
      const key = paymentKeyOf(j.lookup, j.body); nameSent = key;
      const inv = entityKeyOf("invoice");
      for (const cl of j.check_lines ?? []) {
        const rd = await readTxn(c, String(cl.qbo_invoice_id), j, inv);
        if (rd.r.error || !rd.row) return await fail(`not sent — could not read invoice ${cl.invoice_number} (QuickBooks #${cl.qbo_invoice_id}) before sending: ${rd.r.error ?? "no row"} — nothing was written`, rd.r.tid);
        const bal = num(rd.row.Balance);
        if (bal === null) return await fail(`not sent — invoice ${cl.invoice_number} (QuickBooks #${cl.qbo_invoice_id}) has no Balance in QuickBooks (voided?) — check by hand, then retry or skip`, rd.r.tid);
        if (bal + 0.004 < Number(cl.amount)) return await fail(`not sent — QuickBooks already shows ${Math.round(((num(rd.row.TotalAmt) ?? 0) - bal) * 100) / 100} paid on invoice ${cl.invoice_number} (balance ${bal} < ${cl.amount}) — a payment entered before the switch-over or in QuickBooks? check before sending, then retry or skip`, rd.r.tid);
      }
      const { r } = await attempt(j.body, j.request_id);
      const cls = classifyWrite(r.status, r.networkError);
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the created Payment — checked by date, customer, amount and note at the next send`, r.tid, key);
        const d = await donePayment(c, j.job_id, row, j.name, r.tid, null);
        return { ...base, name: j.name, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail(r.error ?? ("HTTP " + r.status), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, key);
    }
    if (j.kind === "credit_apply") {                                                                   // 2e-2-1b 판정 1009 · 1012 · 1016 · sandbox C-5″ — 가드 둘(Invoice Balance ≥ a · CreditMemo RemainingCredit ≥ a · 모자라거나 못 읽으면 failed · 보내지 않는다) → POST payment(0 원 · 몸 그대로) → donePayment 10 인자(TotalAmt 0 · UnappliedAmt 0) · unknown 은 결제 꼴 열쇠
      const key = paymentKeyOf(j.lookup, j.body); nameSent = key;
      const lines = j.check_lines ?? [], invL = lines.filter((cl) => cl.txn_type === "Invoice"), cmL = lines.filter((cl) => cl.txn_type === "CreditMemo");
      if (lines.length !== 2 || invL.length !== 1 || cmL.length !== 1) return await fail(`not sent — the job carries ${lines.length} check line(s) instead of one invoice and one credit memo — nothing was written; retry it after checking the credit application`, null);
      const ci = invL[0], cc = cmL[0];
      const rdI = await readTxn(c, String(ci.qbo_invoice_id), j, entityKeyOf("invoice"));
      if (rdI.r.error || !rdI.row) return await fail(`not sent — could not read invoice ${ci.invoice_number} (QuickBooks #${ci.qbo_invoice_id}) before sending: ${rdI.r.error ?? "no row"} — nothing was written`, rdI.r.tid);
      const bal = num(rdI.row.Balance);
      if (bal === null) return await fail(`not sent — invoice ${ci.invoice_number} (QuickBooks #${ci.qbo_invoice_id}) has no Balance in QuickBooks (voided?) — check by hand, then retry or skip`, rdI.r.tid);
      if (bal + 0.004 < Number(ci.amount)) return await fail(`not sent — QuickBooks already shows ${Math.round(((num(rdI.row.TotalAmt) ?? 0) - bal) * 100) / 100} paid on invoice ${ci.invoice_number} (balance ${bal} < ${ci.amount}) — a payment or credit entered before the switch-over or in QuickBooks? check before sending, then retry or skip`, rdI.r.tid);
      const rdC = await readTxn(c, String(cc.qbo_creditmemo_id), j, entityKeyOf("credit"));
      if (rdC.r.error || !rdC.row) return await fail(`not sent — could not read credit memo ${cc.credit_number} (QuickBooks #${cc.qbo_creditmemo_id}) before sending: ${rdC.r.error ?? "no row"} — nothing was written`, rdC.r.tid);
      const rem = num(rdC.row.RemainingCredit);
      if (rem === null) return await fail(`not sent — credit memo ${cc.credit_number} (QuickBooks #${cc.qbo_creditmemo_id}) has no RemainingCredit in QuickBooks (voided?) — check by hand, then retry or skip`, rdC.r.tid);
      if (rem + 0.004 < Number(cc.amount)) return await fail(`not sent — QuickBooks shows only ${rem} left on credit memo ${cc.credit_number} (less than ${cc.amount}) — applied in QuickBooks or before the switch-over? check before sending, then retry or skip`, rdC.r.tid);
      const { r } = await attempt(j.body, j.request_id);
      const cls = classifyWrite(r.status, r.networkError);
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the created Payment — checked by date, customer, amount 0 and note at the next send`, r.tid, key);
        const d = await donePayment(c, j.job_id, row, j.name, r.tid, null);
        return { ...base, name: j.name, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail(r.error ?? ("HTTP " + r.status), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, key);
    }
    if (j.kind === "payment_void" || j.kind === "credit_apply_void") {                                // 2e-1c 978 · sandbox B-6 — POST payment?operation=update&include=void {Id, SyncToken, sparse} · 5010 → 읽어서 -2 · 4xx failed · 5xx unknown(qbo_name = Id) · [2e-2-1b credit_apply_void 는 같은 길 · 1011 · C-6]
      const id = String(j.qbo_id ?? j.body.Id ?? ""); nameSent = id;
      if (!id) return await fail("not sent — no QuickBooks payment id on the void job", null);
      let syncToken = j.body.SyncToken != null ? String(j.body.SyncToken) : null;
      if (!syncToken) {
        const rd = await readTxn(c, id, j, e);
        if (rd.r.error || !rd.row) return await fail("not sent — payment #" + id + " could not be read for its SyncToken: " + (rd.r.error ?? "no row"), rd.r.tid);
        syncToken = String(rd.row.SyncToken ?? "");
        note = "SyncToken read from QuickBooks before voiding";
      }
      let { r } = await attempt({ Id: id, SyncToken: syncToken, sparse: true }, j.request_id, { operation: "update", include: "void" });
      let cls = classifyWrite(r.status, r.networkError);
      if (cls === "fail" && faultCode(r.body) === STALE_OBJECT_CODE) {
        const rd = await readTxn(c, id, j, e);
        if (rd.r.error || !rd.row) return await fail((r.error ?? "stale SyncToken") + " — and the payment could not be re-read: " + (rd.r.error ?? "no row"), rd.r.tid);
        note = `stale SyncToken (${STALE_OBJECT_CODE}) — re-read and voided again`;
        ({ r } = await attempt({ Id: id, SyncToken: String(rd.row.SyncToken ?? ""), sparse: true }, (j.request_id + "-2").slice(0, REQUESTID_MAX), { operation: "update", include: "void" }));
        cls = classifyWrite(r.status, r.networkError);
      }
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the voided Payment — checked by id at the next send`, r.tid, id);
        const d = await c.d.rpcService("qbo_job_done", { p_job: j.job_id, p_qbo_id: String(row.Id), p_qbo_name: j.name, p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: r.tid, p_note: note, p_sku: null }) as Record<string, unknown>;
        return { ...base, name: j.name, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), note, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail((note ? note + " · " : "") + (r.error ?? ("HTTP " + r.status)), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, id);
    }
    if (j.kind === "invoice_void" || j.kind === "credit_void") {                                        // 2b2 · [2c1 credit_void · 963] — void: Id · SyncToken(없으면 읽는다) · 5010 이면 읽어서 한 번 더 · 거부는 failed(사람)
      const word = txnWord(e);
      const doc = String(j.doc_number ?? j.name); nameSent = doc;
      const id = String(j.qbo_id ?? j.body.Id ?? "");
      if (!id) return await fail(`not sent — no QuickBooks ${word} id on the void job`, null);
      let syncToken = j.body.SyncToken != null ? String(j.body.SyncToken) : null;
      if (!syncToken) {
        const rd = await readTxn(c, id, j, e);
        if (rd.r.error || !rd.row) return await fail(`not sent — ${word} #` + id + " could not be read for its SyncToken: " + (rd.r.error ?? "no row"), rd.r.tid);
        syncToken = String(rd.row.SyncToken ?? "");
        note = "SyncToken read from QuickBooks before voiding";
      }
      let { r } = await attempt({ Id: id, SyncToken: syncToken }, j.request_id, { operation: "void" });
      let cls = classifyWrite(r.status, r.networkError);
      if (cls === "fail" && faultCode(r.body) === STALE_OBJECT_CODE) {
        const rd = await readTxn(c, id, j, e);
        if (rd.r.error || !rd.row) return await fail((r.error ?? "stale SyncToken") + ` — and the ${word} could not be re-read: ` + (rd.r.error ?? "no row"), rd.r.tid);
        note = `stale SyncToken (${STALE_OBJECT_CODE}) — re-read and voided again`;
        ({ r } = await attempt({ Id: id, SyncToken: String(rd.row.SyncToken ?? "") }, (j.request_id + "-2").slice(0, REQUESTID_MAX), { operation: "void" }));
        cls = classifyWrite(r.status, r.networkError);
      }
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the voided ${e.key} — checked by number at the next send`, r.tid, doc);
        const d = await c.d.rpcService("qbo_job_done", { p_job: j.job_id, p_qbo_id: String(row.Id), p_qbo_name: String(row.DocNumber ?? doc), p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: r.tid, p_note: note, p_sku: null }) as Record<string, unknown>;
        return { ...base, name: doc, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), note, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail((note ? note + " · " : "") + (r.error ?? ("HTTP " + r.status)), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, doc);
    }
    let { r } = await attempt(j.body, j.request_id);
    let cls = classifyWrite(r.status, r.networkError);
    if (cls === "fail" && faultCode(r.body) === DUPLICATE_NAME_CODE && j.kind === "item" && j.name_alt && j.name_alt !== nameSent) {   // 이견 11 — 「다른 요청」 으로 한 번(requestid 도 다르게)
      note = `Duplicate Name (${DUPLICATE_NAME_CODE}) on "${nameSent}" — sent again as "${j.name_alt}"`;
      nameSent = j.name_alt;
      ({ r } = await attempt({ ...j.body, Name: j.name_alt }, (j.request_id + "-2").slice(0, REQUESTID_MAX)));
      cls = classifyWrite(r.status, r.networkError);
    }
    if (cls === "ok") {
      const row = (r.body as Record<string, unknown>)?.[e.key] as Record<string, unknown> | undefined;
      if (!row || row.Id == null) return await unknown(`QuickBooks answered ${r.status} without the created ${e.key} — checked by name at the next send`, r.tid, nameSent);
      const d = await c.d.rpcService("qbo_job_done", { p_job: j.job_id, p_qbo_id: String(row.Id), p_qbo_name: String(row[e.nameField] ?? nameSent), p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: r.tid, p_note: note,
        p_sku: typeof row.Sku === "string" && row.Sku ? row.Sku : j.sku }) as Record<string, unknown>;
      return { ...base, name: nameSent, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), linked: d?.linked === true, link_error: (d?.link_error as string | null) ?? null, note };
    }
    if (cls === "fail") return { ...(await fail((note ? note + " · " : "") + (r.error ?? ("HTTP " + r.status)), r.tid)), name: nameSent, note };
    return { ...(await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, nameSent)), note };
  } catch (err) {                                                                                      // 토큰 · DB 창구가 던짐 — 보내기 전이면 failed(사람이 retry) · 보낸 뒤면 sending 그대로(10 분 뒤 unknown · 다음 send 가 이름 · 번호로 푼다)
    const msg = sc(c, String((err as Error)?.message ?? err)).slice(0, 400);
    try { await c.d.rpcService("qbo_job_fail", { p_job: j.job_id, p_error: "not sent — " + msg, p_intuit_tid: null }); return { ...base, name: nameSent, state: "failed", error: "not sent — " + msg, note }; }
    catch { return { ...base, name: nameSent, state: "sending", error: msg, note }; }
  }
}
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
// 같은 바퀴의 일감을 동시 n 개로(2d1) — 하나가 실패 · unknown 이어도 나머지는 계속 · 결과는 일감마다(sendOne 이 자기 일감의 상태를 DB 에 적고 돌려준다 · 던지지 않는다)
async function sendAll(c: Ctx, jobs: ClaimJob[], parallel: number): Promise<JobOut[]> {
  const out: JobOut[] = new Array(jobs.length);
  let next = 0;
  const worker = async () => { while (next < jobs.length) { const i = next++; out[i] = await sendOne(c, jobs[i]); } };
  await Promise.all(Array.from({ length: Math.max(1, Math.min(parallel, jobs.length)) }, () => worker()));
  return out;
}
type PickOut = { job_id: string; kind: string | null; result: string; state: string | null; reason: string | null; qbo_id: string | null; name: string | null; error: string | null; note: string | null; mismatch: string | null; round: number };
// 2e-1c send { kinds } — SEND_KINDS 의 부분집합(중복 접음) · 없으면 전부 · 빈 배열 · 배열 아님 · 모르는 값은 400
export function kindsOf(raw: unknown): string[] {
  if (raw === undefined || raw === null) return [...SEND_KINDS];
  if (!Array.isArray(raw) || raw.length === 0) throw new QboError(400, `kinds must be a non-empty list among ${SEND_KINDS.join(", ")}`);
  const out = [...new Set(raw.map((x) => String(x ?? "").trim()))];
  const bad = out.find((k) => !(SEND_KINDS as readonly string[]).includes(k));
  if (bad !== undefined) throw new QboError(400, `kinds must be among ${SEND_KINDS.join(", ")} (got "${bad.slice(0, 40)}")`);
  return out;
}
async function send(c: Ctx, body: Record<string, unknown>): Promise<Response> {
  if (body.job_ids !== undefined && body.job_ids !== null) return await sendPicked(c, body);                      // 2d1 — 고른 id 만(limit 은 읽지 않는다)
  const limit = body.limit === undefined || body.limit === null || body.limit === "" ? SEND_LIMIT_DEFAULT : Number(body.limit);
  if (!(Number.isInteger(limit) && limit >= 1 && limit <= SEND_LIMIT_MAX)) throw new QboError(400, `limit must be a whole number 1 … ${SEND_LIMIT_MAX} (got ${String(body.limit)})`);
  const kinds = kindsOf(body.kinds);                                                                 // 2e-1c: 없으면 SEND_KINDS 전부(옛 동작) · cron 62 는 [payment, payment_void]
  await ensureToken(c, false);                                                                       // 연결 · env 를 먼저 본다(없으면 409 · 일감은 건드리지 않는다)
  const unknowns = (await c.d.rpcService("qbo_job_unknown_list", {}) as UnknownRow[] | null) ?? [];
  const resolved: Record<string, unknown>[] = [];
  for (const u of unknowns) resolved.push(await resolveUnknown(c, u));
  const cl = (await c.d.rpcService("qbo_job_claim", { p_limit: limit, p_kinds: kinds }) as ClaimResult);   // 2b2: EF 가 아는 kind 만(DB 기본값은 customer · item) · [2e-1c kinds]
  const jobs: JobOut[] = [];
  for (const j of cl.jobs ?? []) jobs.push(await sendOne(c, j));
  const n = (st: string) => jobs.filter((x) => x.state === st).length;
  return jsonCompact(200, { ok: true, mode: "oldest", limit, kinds, resolved, recovered_unknown: cl.recovered_unknown ?? 0, unblocked: cl.unblocked ?? 0, body_failed: cl.body_failed ?? 0, blocked_for_needs: cl.blocked_for_needs ?? 0, claimed: cl.claimed ?? 0,
    sent: n("sent"), failed: n("failed"), unknown: n("unknown"), mismatch: jobs.filter((x) => x.mismatch).length, jobs });
}
// 2d1 — 고른 일감만 · 바퀴(claim → 동시 보내기 → claim …) · need 일감(손님 · Item · 부모 손님)은 같은 호출에서 먼저 · 크레딧이 기다리는 인보이스는 대신 보내지 않는다(960 · blocked + 까닭)
async function sendPicked(c: Ctx, body: Record<string, unknown>): Promise<Response> {
  const raw = body.job_ids;
  if (!Array.isArray(raw) || raw.length === 0) throw new QboError(400, `job_ids must be a list of 1 … ${SEND_PICK_MAX} job ids`);
  const ids = [...new Set(raw.map((x) => String(x ?? "").trim().toLowerCase()))];
  if (ids.length > SEND_PICK_MAX) throw new QboError(400, `job_ids may name at most ${SEND_PICK_MAX} jobs in one call (got ${ids.length}) — send them in smaller batches`);
  const bad = ids.find((x) => !UUID_RE.test(x));
  if (bad !== undefined) throw new QboError(400, `job_ids must be job ids (uuid) — got "${bad.slice(0, 40)}"`);
  await ensureToken(c, false);
  const unknowns = (await c.d.rpcService("qbo_job_unknown_list", {}) as UnknownRow[] | null) ?? [];
  const resolved: Record<string, unknown>[] = [];
  for (const u of unknowns) resolved.push(await resolveUnknown(c, u));
  const t0 = c.d.now();
  const selected = new Set(ids), extra = new Set<string>();                                          // extra = claim 이 만든 need 일감(손님 · Item · 부모) — 다음 바퀴에 같이 잡는다
  const outcome = new Map<string, PickOut>();                                                        // 고른 id + need id 마다 마지막 뜻 있는 결과
  const jobs: JobOut[] = [], needJobs: NeedJob[] = [];
  let rounds = 0, stopped: string | null = null, claimedTotal = 0, unblockedTotal = 0;
  const put = (id: string, o: Partial<PickOut> & { result: string }, round: number) => { const prev = outcome.get(id); outcome.set(id, { job_id: id, kind: o.kind ?? prev?.kind ?? null, state: o.state ?? prev?.state ?? null, reason: o.reason ?? null, qbo_id: o.qbo_id ?? prev?.qbo_id ?? null, name: o.name ?? prev?.name ?? null, error: o.error ?? null, note: o.note ?? null, mismatch: o.mismatch ?? null, result: o.result, round }); };
  const terminal = (id: string) => { const r = outcome.get(id)?.result; return r === "sent" || r === "failed" || r === "unknown" || r === "not_found" || r === "wrong_kind" || r === "not_due" || (r === "not_queued" && outcome.get(id)?.state !== "blocked"); };
  for (let r = 1; r <= SEND_PICK_ROUNDS; r++) {
    const want = [...selected, ...extra].filter((id) => !terminal(id));
    if (want.length === 0) break;
    if (c.d.now() - t0 > SEND_PICK_BUDGET_MS) { stopped = "time"; break; }                            // 예산 — 바퀴 앞에서만(잡은 것은 끝까지 보낸다)
    rounds = r;
    const cl = (await c.d.rpcService("qbo_job_claim", { p_limit: SEND_LIMIT_MAX, p_kinds: [...SEND_KINDS], p_job_ids: want }) as ClaimResult);
    claimedTotal += cl.claimed ?? 0; unblockedTotal += cl.unblocked ?? 0;
    for (const nj of cl.need_jobs ?? []) {                                                              // need = 손님 · Item · 부모 손님만 같이 잡는다 · 거래 종류(크레딧이 기다리는 인보이스 · 960)는 북키퍼가 골라야 한다
      const id = nj.job_id.toLowerCase(); needJobs.push(nj);
      if (!isNeedKind(nj.kind)) continue;                                                              // 2e-2-1b: 거래 · void(payment_void · credit_apply_void · 1013)도 대신 보내지 않는다
      extra.add(id); if (!outcome.has(id)) put(id, { result: "need", kind: nj.kind, state: nj.state, name: nj.name, reason: nj.existing ? `already waiting for job ${nj.for_job}` : `created first for job ${nj.for_job}` }, r);
    }
    for (const q of cl.requested ?? []) {
      const id = q.job_id.toLowerCase();
      if (q.result === "claimed") continue;                                                          // 보낸 뒤 결과로 적는다
      if (q.result === "not_queued" && outcome.has(id) && outcome.get(id)!.result !== "need") continue;   // 이미 뜻 있는 결과가 있으면(blocked 까닭 등) 덮지 않는다
      put(id, { result: q.result, kind: q.kind, state: q.state, reason: q.reason, error: q.result === "failed" ? q.reason : null }, r);
    }
    const outs = await sendAll(c, cl.jobs ?? [], SEND_PICK_PARALLEL);
    for (const o of outs) { jobs.push(o); put(o.job_id.toLowerCase(), { result: o.state, kind: o.kind, state: o.state, qbo_id: o.qbo_id, name: o.name, error: o.error, note: o.note, mismatch: o.mismatch ?? null, reason: null }, r); }
    if (outs.length === 0 && (cl.unblocked ?? 0) === 0 && !(cl.need_jobs ?? []).some((nj) => isNeedKind(nj.kind) && !terminal(nj.job_id.toLowerCase()))) break;   // [2e-2-1b 같은 술어 — 건너뛴 need 를 「새 need」 로 세면 바퀴만 돈다]   // 이 바퀴에 보낸 것 · 풀린 것 · 새 need 가 없다 = 다음 바퀴도 그대로(blocked 는 부모가 sent 가 돼야 풀린다)
  }
  const requested: PickOut[] = ids.map((id) => outcome.get(id) ?? { job_id: id, kind: null, result: "not_reached", state: null, reason: stopped === "time" ? "not started — the time budget ran out; send again" : "not started — too many rounds; send again", qbo_id: null, name: null, error: null, note: null, mismatch: null, round: 0 });
  const needs: PickOut[] = [...extra].map((id) => outcome.get(id)!).filter(Boolean);
  const n = (st: string) => requested.filter((x) => x.result === st).length;
  const left = [...selected, ...extra].filter((id) => !terminal(id)).length;
  if (!stopped && left > 0) stopped = rounds >= SEND_PICK_ROUNDS ? "rounds" : "no_progress";
  return jsonCompact(200, { ok: true, mode: "selected", job_ids: ids, kinds: [...SEND_KINDS], rounds, parallel: SEND_PICK_PARALLEL, stopped, resolved, claimed: claimedTotal, unblocked: unblockedTotal,
    sent: n("sent"), failed: n("failed"), unknown: n("unknown"), blocked: n("blocked"), not_sent: requested.length - n("sent") - n("failed") - n("unknown") - n("blocked"), mismatch: requested.filter((x) => x.mismatch).length,
    requested, needs, jobs });
}

// ── callback(GET · Intuit 이 브라우저를 보낸다) — 언제나 302 · 본문 비움 · Location 은 고정 주소 + 정해진 why 낱말뿐 ──
async function callback(url: URL, c: Ctx): Promise<Response> {
  const q = url.searchParams;
  const fail = async (why: CallbackWhy, error: string, realm: string | null = null): Promise<Response> => {
    await c.d.log({ env: c.env, realm_id: realm, action: "callback", ok: false, http_status: null, intuit_tid: null, error: sc(c, error).slice(0, 400), by_staff: c.byStaff, ms: 0 });
    return redirect302(callbackLocation(why));
  };
  if (q.get("error")) return await fail("denied", "denied: " + (q.get("error") ?? "").slice(0, 100));
  const state = q.get("state") ?? "", code = q.get("code") ?? "", realm = (q.get("realmId") ?? "").trim();
  if (code) c.secrets.push(code);
  if (!state) return await fail("state", "callback without state");
  let st: { staff_id: string; env: string };
  try { st = await c.d.rpcService("qbo_state_consume", { p_state_hash: await sha256Hex(state) }) as typeof st; }
  catch (e) { return await fail("state", e instanceof RpcError ? e.message : String((e as Error)?.message ?? e)); }
  c.byStaff = st.staff_id;
  if (!c.env) return await fail("env", "QBO_ENV is not set");
  if (st.env !== c.env) return await fail("env", `state was made for ${st.env} but QBO_ENV is ${c.env}`);
  const env = c.env;
  if (!code) return await fail("exchange", "callback without code");
  let disc: Discovery;
  try { clientOf(c, env); disc = await discoveryOf(c, env); } catch (e) { return await fail(e instanceof QboError && /app keys/.test(e.message) ? "env" : "exchange", String((e as Error)?.message ?? e)); }
  const redirectUri = redirectUriOf(c.d.env("SUPABASE_URL") ?? "");
  const r = await tokenCall(c, "token_exchange", env, disc.token_endpoint, { grant_type: "authorization_code", code, redirect_uri: redirectUri }, realm || null);
  if (r.error) return await fail("exchange", "token exchange: " + r.error, realm || null);
  let tk: Tokens;
  try { tk = parseTokenResponse(r.body, c.d.now()); } catch (e) { return await fail("exchange", String((e as Error)?.message ?? e), realm || null); }
  c.secrets.push(tk.access, tk.refresh);
  if (tk.assumedExpiresIn) c.d.warn("qbo callback: expires_in missing in the token response — assumed " + ACCESS_EXPIRES_DEFAULT_S + " s");
  const revokeReceived = async () => { await revokeCall(c, env, disc.revocation_endpoint, tk.refresh, realm || null); };   // 받은 토큰은 바로 되돌려 준다(저장하지 않았으니)
  if (!/^[0-9]{4,32}$/.test(realm)) { await revokeReceived(); return await fail("realm", "callback realmId missing or not a number", realm || null); }
  try {
    await c.d.rpcService("qbo_connection_save", { p_env: env, p_realm: realm, p_refresh: tk.refresh, p_access: tk.access, p_access_exp: tk.accessExp.toISOString(), p_refresh_exp: tk.refreshExp ? tk.refreshExp.toISOString() : null, p_staff: st.staff_id });
  } catch (e) {
    const msg = e instanceof RpcError ? e.message : String((e as Error)?.message ?? e);
    const realmRefused = /not the company this IMS was first connected to/i.test(msg);               // qbo_connection_save 의 거부 글(20261029160000)
    await revokeReceived();
    return await fail(realmRefused ? "realm" : "save", "save: " + msg, realm);
  }
  try {                                                                                              // 이름은 꾸밈 — 실패해도 연결은 저장됐고 302 connected · 흔적은 call_log(company_name 줄 · companyinfo 줄) · ping 이 다시 시도
    const ci = await companyInfoCall(c, env, realm, tk.access);
    const name = ci.error ? null : companyNameOf(ci.body);
    if (name) { const err = await companyNameSet(c, env, realm, name); if (err) c.d.warn("qbo callback: company name not saved — " + err + " (connection saved; ping later)"); }
    else c.d.warn("qbo callback: company name not read — " + sc(c, ci.error ?? "no CompanyName") + " (connection saved; ping later)");
  } catch (e) { c.d.warn("qbo callback: company name step failed — " + sc(c, String((e as Error)?.message ?? e))); }
  await c.d.log({ env, realm_id: realm, action: "callback", ok: true, http_status: null, intuit_tid: null, error: null, by_staff: st.staff_id, ms: 0 });
  return redirect302(callbackLocation(null));
}

// ── 문 둘 — 직원(사용자 JWT → DB 창구가 본다) · cron(x-ims-cron-key == IMS_CRON_SECRET · refresh 만) ──
function sameSecret(a: string, b: string): boolean {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}
async function disconnect(c: Ctx): Promise<Response> {
  let revoked: boolean | null = null, note: string | null = null, env: Env | null = null, realm: string | null = null;
  try {
    const t = await tokenGet(c);
    env = envOf(t.env); realm = t.realm_id;
    if (env) {
      try {
        const disc = await discoveryOf(c, env);
        const r = await revokeCall(c, env, disc.revocation_endpoint, t.refresh_token, realm);
        revoked = r.error === null;
        if (!revoked) note = "Intuit revoke failed (" + r.error + ")";
      } catch (e) { revoked = false; note = "Intuit revoke was not possible (" + sc(c, String((e as Error)?.message ?? e)).slice(0, 200) + ")"; }
    }
  } catch (e) {
    if (!(e instanceof QboError && e.status === 409)) throw e;                                       // 연결 없음 — 그래도 delete 로 짝 잃은 Vault 행 · state 를 치운다
    note = "No connection was on file";
  }
  const del = await c.d.rpcService("qbo_connection_delete", {}) as Record<string, unknown>;        // revoke 가 실패해도 지운다(처리방침 약속)
  await c.d.log({ env: env ?? c.env, realm_id: realm, action: "disconnect", ok: true, http_status: null, intuit_tid: null, error: note ? note.slice(0, 400) : null, by_staff: c.byStaff, ms: 0 });
  const message = revoked === false ? "Disconnected in IMS, but QuickBooks could not be told — please also remove Asung IMS under QuickBooks → Apps → Connected apps. " + note
    : revoked === true ? "Disconnected — tokens revoked at Intuit and removed from IMS" : "Nothing was connected — leftover tokens and sign-in states (if any) were removed";
  return json(200, { ok: true, revoked, deleted: del?.deleted === true, vault_rows_removed: del?.vault_rows_removed ?? 0, states_removed: del?.states_removed ?? 0, message });
}
async function status(c: Ctx, jwt: string): Promise<Response> {
  const db = await c.d.rpcUser("qbo_status", {}, jwt) as Record<string, unknown>;
  const env = c.env, n = env ? secretNames(env) : null;
  const rowEnv = typeof db?.env === "string" ? db.env as string : null;
  return json(200, {
    ok: true, ...db,
    qbo_env: env, env_mismatch: rowEnv !== null && env !== null && rowEnv !== env,
    secrets: { client_id: n ? !!(c.d.env(n.id) ?? "").trim() : false, client_secret: n ? !!(c.d.env(n.secret) ?? "").trim() : false, cron_secret: !!(c.d.env("IMS_CRON_SECRET") ?? "").trim(), names: n },
    discovery: c.d.discovery.state(c.d.now()), redirect_uri: redirectUriOf(c.d.env("SUPABASE_URL") ?? ""), settings_url: SETTINGS_URL, minorversion: MINOR_VERSION,
  });
}
export async function handle(req: Request, d: Deps): Promise<Response> {
  const c: Ctx = { d, secrets: [], env: cfgOf(d).qboEnv, byStaff: null };
  for (const e of ENVS) { const n = secretNames(e); const s = (d.env(n.secret) ?? "").trim(); if (s) c.secrets.push(s); }
  try {
    const url = new URL(req.url);
    if (req.method === "GET" && isCallbackPath(url.pathname)) return await callback(url, c);
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    if (req.method !== "POST") return json(405, { ok: false, error: "POST only (GET is only /callback)" });
    if (!c.env) return json(500, { ok: false, error: "QBO_ENV is not set (sandbox | production) — refusing (fail-closed)" + (cfgOf(d).raw ? " (got " + scrub(String(cfgOf(d).raw)) + ")" : "") });
    const body = await req.json().catch(() => ({})) as Record<string, unknown>;
    const action = String(body?.action ?? "");
    const cronKey = req.headers.get("x-ims-cron-key");
    if (cronKey !== null) {                                                                          // cron 길 — 열쇠만 · refresh 만 · by_staff 없음
      const secret = d.env("IMS_CRON_SECRET") ?? "";
      if (!secret) return json(500, { ok: false, error: "IMS_CRON_SECRET not configured - refusing (fail-closed)" });
      if (!cronKey || !sameSecret(cronKey, secret)) return json(401, { ok: false, error: "unauthorized" });
      if (!(CRON_ACTIONS as readonly string[]).includes(action)) return json(400, { ok: false, error: "cron may only call: " + CRON_ACTIONS.join(", ") });
      if (action === "send") return await send(c, body);                                              // 2b2 cron ims-qbo-send — 열쇠 문 없음(by_staff null) · limit 은 cron 몸에서
      const h = await ensureToken(c, true);
      return json(200, { ok: true, refreshed: h.refreshed, token_version: h.token_version, access_expires_at: h.access_expires_at, refresh_expires_at: h.refresh_expires_at, env: h.env, realm_id: h.realm });
    }
    if (!(ACTIONS as readonly string[]).includes(action)) return json(400, { ok: false, error: "action must be one of: " + ACTIONS.join(", ") });
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json(401, { ok: false, error: "Missing Authorization" });
    if (action === "status") return await status(c, jwt);
    try {                                                                                            // qbo-sync-2a 판정 945 — 문 둘: 연결류 · 원문 조회는 admin(qbo_admin_gate) · 짝 · 받기 · 보내기는 열쇠 qbo(qbo_key_gate(write) · admin 도 켜야 한다)
      if ((KEY_ACTIONS as readonly string[]).includes(action)) { const sid = await d.rpcUser("qbo_key_gate", { p_write: true }, jwt); c.byStaff = typeof sid === "string" && sid ? sid : null; }
      else { const gate = await d.rpcUser("qbo_admin_gate", {}, jwt) as { staff_id: string | null; name: string | null }; c.byStaff = gate?.staff_id ?? null; }
    } catch (e) { if (e instanceof RpcError) return json(e.status === 401 ? 401 : 403, { ok: false, error: e.status === 401 ? "Invalid session — sign in again" : e.message }); throw e; }
    if (action === "start") {
      const env = c.env;
      clientOf(c, env);
      const disc = await discoveryOf(c, env);
      const raw = newStateRaw(d.randomBytes(32));
      const st = await d.rpcUser("qbo_state_new", { p_env: env, p_state_hash: await sha256Hex(raw) }, jwt) as { expires_at: string };
      return json(200, { ok: true, url: authorizeUrl(disc.authorization_endpoint, clientOf(c, env).id, redirectUriOf(d.env("SUPABASE_URL") ?? ""), raw), env, expires_at: st?.expires_at ?? null, redirect_uri: redirectUriOf(d.env("SUPABASE_URL") ?? "") });
    }
    if (action === "disconnect") return await disconnect(c);
    if (action === "refresh") { const h = await ensureToken(c, true); return json(200, { ok: true, refreshed: h.refreshed, token_version: h.token_version, access_expires_at: h.access_expires_at, refresh_expires_at: h.refresh_expires_at, env: h.env, realm_id: h.realm }); }
    if (action === "ping") return json(200, { ok: true, ...(await ping(c)) });
    if (action === "query") return await query(c, body);
    if (action === "read") return await read(c, body);
    if (action === "pull") return await pull(c, body, jwt);
    if (action === "send") return await send(c, body);
    return json(400, { ok: false, error: "unknown action" });
  } catch (e) {
    if (e instanceof QboError) return json(e.status, { ok: false, error: sc(c, e.message) });
    if (e instanceof RpcError) return json(e.status === 401 ? 401 : 422, { ok: false, error: sc(c, e.status === 401 ? "Invalid session — sign in again" : e.message) });
    const msg = sc(c, String((e as Error)?.message ?? e)).slice(0, 400);
    d.warn("qbo failed: " + msg);
    return json(500, { ok: false, error: msg });
  }
}
