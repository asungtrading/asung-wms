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
//   qbo-sync-2e-1d-2(2026-11-06 · deferred 452 · DB 1d-1 20261105184613): KEY_ACTIONS 에 opening_candidates · opening_read · opening_search — 이월 인보이스 QBO 짝 · 읽기만(apiCall) · 창구 qbo_opening_list · qbo_opening_candidates · qbo_opening_match 는 사용자 JWT · 흐름은 handle 바로 위 블록
//   qbo-sync-2e-3-1b(2026-11-07 · 판정 998′ · 1009 · 1011 ~ 1013 · DB 2e-3-1 20261107044131 · 지시서 ~/asung/prompts/qbo-sync-2e-3-1b.md · §0 이견 1 ~ 10 Caleb 답): 이월 받아 둔 돈의 붙임 = QBO 두 장 — SEND_KINDS 14(opening_credit · opening_credit_void · opening_apply · opening_apply_void)
//     새 갈래 없음(이견 1) — opening_credit 은 credit 길(DocNumber OC-<인보이스>-<n> 멱등 · POST creditmemo · doneTxn TotalAmt · TotalTax — DB 가 붙임 금액 ∧ 0 과 견줌) · opening_credit_void 는 credit_void 길(creditmemo?operation=void) · opening_apply 는 credit_apply 길(가드 Invoice Balance ≥ a ∧ CreditMemo RemainingCredit ≥ a → POST payment 0 원 · donePayment) · opening_apply_void 는 payment_void 길(payment?operation=update&include=void)
//     entityKeyOf 명시 가지 넷(ELSE = invoice 로 떨어지지 않게) · OPENING_CREDIT_KINDS · OPENING_APPLY_KINDS 새로(TXN_KINDS · CREDIT_APPLY_KINDS 무변 · isTxnKind · isCreditApplyKind 가 합집합) · parsePaymentKey 접두 셋째 「IMS opening credit applied 」(unknown 풀기 = 그 날 Payment · PrivateNote 완전 일치 · Voided 제외)
//     assertWriteAllowed · isNeedKind 무변(이미 허용 · 이미 「customer · item 이 아니면 전부」) · cron 62 kinds 8 은 배포 + 첫 실물 뒤(1034 · supabase/ops/cron.sql 주석 블록) · cron 61 은 kinds 없이 전부를 부르므로 qbo_send_enabled 는 그대로 off
//   qbo-sync-2e-3-2-1b(2026-11-08 · 판정 1056 ~ 1058 · ⓖ-1 ~ ⓖ-8 · DB 2e-3-2-1 20261108075221 · 지시서 ~/asung/prompts/qbo-sync-2e-3-2-1b.md · §0 이견 1 ~ 11 Caleb 답): 환불(so_payment kind refund)의 크레딧 노트 몫 = QBO 두 장 — SEND_KINDS 18(refund · refund_void · refund_apply · refund_apply_void · ims_id = 환불 하나)
//     refund = Purchase(Expense) 만들기(새 갈래 · 몸은 DB qbo_refund_body 그대로 · DocNumber 멱등 없음) — 보내기 전 가드 셋: ① CreditMemo 마다 GET → RemainingCredit ≥ 몫 ② 손 기록 찾기 = Purchase · JournalEntry · RefundReceipt 를 TxnDate = paid_on ± 7 일로 받아(서버는 TxnDate 만 거른다 · sandbox 2-e · 1000 행이면 STARTPOSITION 최대 5 쪽) EF 가 손님(EntityRef · 줄 CustomerRef · JE 줄 Entity) · 금액 · Voided 아님 · 「IMS refund 」 머리 아님(이견 3 — 다른 IMS 환불은 손 기록이 아니다)으로 거른다 → 하나라도 있으면 failed(1060 꼴 · 사람이 QBO 에서 지우고 Retry · 맞으면 Skip) ③ POST purchase → doneTxn(TotalAmt · TxnTaxDetail.TotalTax — DB 가 크레딧 몫 합 ∧ 0 과 견줌) · unknown 열쇠는 결제 꼴 「IMS refund <uuid>|<EntityRef>|<TxnDate>|<TotalAmt>」
//     refund_apply = 0 원 Payment(새 갈래 · check_lines = Expense 하나 + CreditMemo 하나 이상 · Expense 줄 LinkedTxn TxnType "Expense") — 가드: GET purchase/<id>(있음 · Voided 아님 · PrivateNote = 「IMS refund <uuid>」 · TotalAmt ≥ Expense 줄 — Purchase 에 Balance 칸이 없어 열린 금액은 못 읽는다(이견 2) · 넘치면 QBO 6000 → failed) ∧ CreditMemo 마다 RemainingCredit ≥ 몫 → POST payment → donePayment(TotalAmt 0 · UnappliedAmt 0 — DB 가 견줌) · 응답 LineEx txnOpenBalance 는 note 에(DB done 에 받을 인자가 없다 · [1b2] 그 값은 잇기 **직전** 열린 금액 — openBalanceNote: after = before − Amount · Expense 줄 |after| > 0.004 · CreditMemo 줄 after < −0.004 면 경고)
//     refund_apply_void = payment_void 길(payment?operation=update&include=void · 조건에 ||) · 풀기는 Id 로 읽어 Voided 면 done
//     refund_void = Purchase Full update void 꼴(sandbox 2-d · Delete 없음 · operation 없음 = 만들기와 같은 POST …/purchase) — GET purchase/<id> → 이미 Voided 면 done(다시 보내지 않음) · LinkedTxn 에 Payment 가 남아 있으면 failed(이견 4 · 0 원 Payment 를 먼저 void) · 읽은 줄 0 개면 failed → 몸 = DB 머리 + Id + 읽은 SyncToken + 읽은 Line 전부 Amount 0(Id · LineNum · detail 그대로) + PrivateNote 「Voided - IMS refund <uuid>」 → POST → 5010 이면 다시 읽어 requestid -2 한 번 → done 조건(이견 1) = 2xx ∧ TotalAmt 0 ∧ 「Voided - 」 머리 · status 가 있고 Voided 가 아니면 failed · status 없으면 done + note
//     assertWriteAllowed(method, url, body?) — WRITE_ENTITIES + purchase · purchase 는 몸으로 가른다(이견 7): Id 없음 = 만들기 · Id 있음 = void 꼴(SyncToken · Line 비지 않음 · 모든 줄 Amount === 0 · PrivateNote 「Voided - 」 · sparse 아님)일 때만 · purchase?operation=… · include= 는 기존 가지가 거부 · 다른 엔티티의 몸은 이 차수에 보지 않는다(넓히는 안 · 크기는 보고에)
//     entityKeyOf 명시 가지 넷(refund 둘 → purchase · Purchase · PrivateNote / refund_apply 둘 → payment · Payment · PrivateNote) · REFUND_KINDS · REFUND_APPLY_KINDS 새로(TXN_KINDS · CREDIT_APPLY_KINDS · PAYMENT_KINDS · OPENING_* · isNeedKind 무변) · parsePaymentKey 접두 넷째 「IMS refund 」 · 조회 행은 기록하지 않는다(detail 은 rows · q 만)
//     ⚠️ 순서(1034 · 1055): 이 EF 배포 → 첫 실물 손 Send 2 건(화면 qbo-send · refund 와 refund_apply 를 함께 고르거나 refund 부터 — sendPicked 는 거래 kind 를 need 로 대신 보내지 않는다) → 그 뒤 cron 62 kinds 여덟 → 열둘(EF 전에 cron 을 늘리면 kindsOf 400 → 결제도 멈춘다)
//   qbo-sync-3-3(2026-11-09 · 판정 1092 ~ 1103 · 1112 · DB 3-2a 20261108170000 · 3-2b 20261108224000 · 지시서 ~/asung/prompts/qbo-sync-3-3.md · §0 이견 1 ~ 10 · ⬜1 ~ ⬜8 Caleb 답 · sandbox ② S1 ~ S3): 하루 원가 장(kind cost_day · ims_kind cost_sheet · ims_id 「YYYY-MM-DD|TOR[|rebuild]」)을 JournalEntry 로 — SEND_KINDS 19
//     kind 목록(⬜1 · 이견 3-3 ③): SEND_KINDS 19 · DEFAULT_SEND_KINDS 18(cost_day 뺌) = kindsOf(undefined | null) — cron 61(kinds 없음)은 qbo_send_enabled 를 켜도 원가 장을 집지 않는다 · kinds 에 명시(cron 길 [cost_day, customer] · 등록은 뒤 차수)할 때만 · sendPicked(화면 손 Send · job_ids)는 19(1098 처음 몇 주 손 Send)
//     엔티티 열쇠(⬜2): entityKeyOf cost_day → journalentry · JournalEntry · DocNumber(명시 가지) · WRITE_ENTITIES + journalentry · assertWriteAllowed: journalentry 는 만들기만(몸에 Id 가 있으면 거부 · operation · include 는 기존 가지가 거부 · 지우기 · void · update 길 없음 — 374 · 1060 · 1101) · txnWord "journal entry" · TXN_KINDS 무변(cost_day 는 전용 가지 — 1 행의 뜻이 인보이스와 다르다)
//     보내기(⬜3 · ⬜4 · 이견 1): findByDocNumber(JournalEntry) → 조회 실패 failed(보내지 않음 · 행 삭제 + Retry 가 다시 셈) · 1 행 이상 **unknown**(POST 0 · p_name = 열쇠 · 글 「already has JournalEntry … resolve in_qbo / remove it there, then resolve not_in_qbo」 — failed 로 두면 resolve(unknown 만 받음)가 막히고 Skip 은 void → 뒤 장이 그 몫을 또 담는다) · 0 행 → POST journalentry(몸 = DB qbo_cost_day_body 그대로 · requestid)
//       → 2xx doneJournal: p_total_amt = **응답 Line 중 PostingType Debit 의 Amount 센트 합**(S1 실측 TotalAmt 0 · HomeTotalAmt 0 — 응답 TotalAmt 를 넘기면 모든 장에 거짓 경고 · DB qbo_job_done cost_day 가지는 round(p_total_amt*100) ↔ 지문 앞 칸을 견준다 · DB 무변 · 정본은 다음 문서 차수) · p_total_tax null · Line 없으면 null → DB 가 「did not return TotalAmt」 경고(sent) · 6140 · 6210 · 5xx · 끊김 · 몸 없음 → unknown(열쇠)
//     unknown 열쇠(1112 · (가)): qbo_name = 「<DocNumber>|<차변 센트>」(costDayKeyOf · parseCostDayKey · 결제 paymentKeyOf 꼴 · 차변 센트 = ClaimJob.fingerprint 앞 칸 = claim 때 고정 · qbo_job_unknown_list 에 지문이 없어 열쇠에 싣는다 · DocNumber 제약에 | 가 없어 쪼개기 안전) · done · resolve 가 DocNumber 로 되돌린다 · unknown 동안 화면에 이 꼴이 보인다(결제 unknown 과 같음)
//     unknown 풀기(⬜5 · 1112): 쪼개기(qbo_name null = stale sending 이면 ims_id 로 DocNumber 만 · 센트 없음) → DocNumber 조회 → 0 not_found(그대로 · retry 또는 resolve not_in_qbo) · 2+ ambiguous(그대로 · QBO 에서 하나 지우고 resolve in_qbo) · 1 → GET journalentry/<Id>(Line 은 읽기로 — S3 의 「select 에 Line 이 따라온다」 에 기대지 않는다) → Debit 합(센트) = 열쇠 센트일 때만 done · 다르면 그대로 + 글 「has debits … but this cost day expects … — not recorded」 · 센트 없으면 그대로 + 글 「expected debit is not on the job」 · 조회 행은 기록하지 않는다(detail 은 rows · q 뿐 · S3 손님 이름)
//     ⚠️ 풀기는 kind 를 가리지 않고 모든 send 호출 앞에서 돈다(이견 3) — cron 62(5 분)가 cost_day unknown 도 qbo_send_cost_enabled 와 무관하게 조회 · (금액 같으면) done 한다 · 쓰기 0 · 인보이스 unknown 과 같다
//     needs(⬜6): DB 몸이 Entity 짝 없는 손님을 needs 로 → claim ④ 가 customer 일감 + blocked → sendPicked 는 isNeedKind(customer) 로 같은 호출에서 손님 먼저(바퀴 3) · cron 길 [cost_day, customer] 는 호출 셋에 걸쳐(⚠️ customer 는 큐의 모든 손님 일감 — 이견 7 · cron.sql 주석 블록) · 원가 cron 은 이 차수에 등록하지 않는다(⬜7 · 주석 블록만) · 줄 상한 · DocNumber 21 자는 첫 실물로(⬜8 · DB 제약 17 · 19 자 · S1 19 자 됨)
//   qbo-sync-3-3b(2026-11-09 · 작은 고침 · 운영 첫 cost_day 손 Send COGS-20261031-TOR 122.82 가 failed 「not sent — the DocNumber check failed before sending: HTTP 400 ValidationFault code 4001: Invalid query — QueryValidationError: Property TotalAmt not found for Entity JournalEntry」 · 가드가 맞게 막아 QBO 쓰기 0 · 같은 날 Bill 7 장은 Bill 가드(TotalAmt 포함)로 잘 갔다): JournalEntry 의 DocNumber 가드 조회에서 TotalAmt · SyncToken 을 뺀다(docNumberQueryText → select Id, DocNumber) — 금액 대조는 전부터 1 행이면 GET(readTxn → journalDebitCents) 이라 조회 칸에 기대는 곳 0 · Invoice · CreditMemo 조회는 그대로 · QUERY_UNSELECTABLE 실측 표 · 가짜 Intuit 이 그 칸을 4001 로 거부(시험 ㉙) · DB · 화면 · cron 무변
//   qbo-sync-4-4(2026-11-09 · 판정 1115 ~ 1130 · DB 4-3a 20261109103000 · 4-3b 20261109104000 · 지시서 ~/asung/prompts/qbo-sync-4-4.md · §0 이견 1 ~ 12 · sandbox 4-2a E-1 ~ E-15 = 정본 qbo-integration §15-l ③): 공급처 Vendor · Bill · VendorCredit 보내기 — SEND_KINDS 22(vendor · bill · vendor_credit) · DEFAULT_SEND_KINDS 18 그대로(SUPPLIER_KINDS 도 뺀다 — cron 61 · 62 무변 · 손 Send(sendPicked)와 kinds 명시만)
//     bill_delete_manual 은 EF 가 모른다(1126 · 사람이 QBO 에서 지운 뒤 Skip) — SEND_KINDS 밖 · kindsOf 400 · sendPicked 로 고르면 claim 이 wrong_kind
//     엔티티 열쇠: entityKeyOf 명시 가지 셋(vendor → vendor · Vendor · DisplayName / bill → bill · Bill · DocNumber / vendor_credit → vendorcredit · VendorCredit · DocNumber) · WRITE_ENTITIES + vendor · bill · vendorcredit · CREATE_ONLY_ENTITIES(journalentry 에 셋 더함 — 몸에 Id 있으면 거부 · void · delete · update 길 없음 · E-7 Bill 에는 void 가 없다) · txnWord bill · vendor credit · isNeedKind + vendor(Bill 미리 보기 · Send 가 Vendor 를 먼저 만든다 · 1128)
//     vendor: 손님 길 그대로(generic 꼬리 — POST vendor · 몸 = DB qbo_vendor_body(DisplayName + CurrencyRef) · 2xx done(DB 가 Vendor 거울 + qbo_link supplier) · 6240 이름 겹침 → failed(Item 의 ` [SKU]` 재시도 없음 · 자동 개명 없음 · DB 거울 검사가 먼저 막고 거울에 없는 Employee · 옛 이름만 여기까지 온다) · unknown 풀기 = DisplayName 조회 1 행 done)
//     bill · vendor_credit(1127 · E-5 QBO 는 같은 Vendor 같은 DocNumber Bill 을 막지 않는다): 보내기 직전 가드 조회 `select Id, DocNumber, SyncToken, TotalAmt, VendorRef from Bill|VendorCredit where DocNumber = '…' and VendorRef = '…'` — 조회 실패 failed(보내지 않음) · 0 행 POST(몸 = DB qbo_bill_body · qbo_charge_bill_body 그대로 — APAccountRef · DueDate · ExchangeRate · TxnTaxDetail 은 DB 가 싣는다) · 1 행 → GET 읽어 TotalAmt 센트 = 일감 센트(lookup.total_cents · 지문 앞 칸)면 done + note(이견 1 · 못 읽으면 failed) · 센트 다르면 unknown + 글 「not recorded (1127)」 · 2 행 이상 unknown(workflow 115 — failed 로 두면 풀기 길이 닫힌다) · VendorRef 없는 몸은 failed(이견 7)
//       → 2xx doneTxn(TotalAmt = 문서 통화 · TxnTaxDetail.TotalTax — DB qbo_job_done bill · vendor_credit 가지가 round(TotalAmt*100) ↔ 지문 앞 칸을 견줘 다르면 sent + mismatch(942 꼴) · E-1 응답에 HomeTotalAmt 없음 · HomeBalance 만) · 6140 · 6210 → unknown + 열쇠(이견 3 · 운영 WarnDuplicateBillNumber 미확인) · 5xx · 끊김 · 몸 없음 → unknown
//     unknown 열쇠: qbo_name = 「<DocNumber>|<VendorRef>|<센트>」(billKeyOf · parseBillKey 는 오른쪽부터 쪼갠다 — 공급처 번호에 | 가 올 수 있다 · 이견 2 · 센트 없으면 빈 칸) · 풀기(resolveUnknown): 가드 조회 → 0 not_found · 2+ ambiguous · 1 → GET → 센트 같을 때만 done(1127) · 다르면 amount_differs 그대로 + 글 · 센트 없음 · TotalAmt 없음 → needs_hand · qbo_name null(stale sending → unknown)은 no_name(ims_id 가 uuid 라 DocNumber 를 못 만든다 · 이견 4 · 사람이 note 와 Retry)
//     ⚠️ 풀기는 kind 를 안 가린다 — cron 62(5 분)가 Bill unknown 도 조회 · 센트 같으면 done(쓰기 0 · 3-3 과 같은 사실 · 이견 5)
//     PULL_FIELDS.TaxCode + PurchaseTaxRateList(DB qbo_entity_upsert 4-3a 가 detail 에 병합 · qbo_purchase_tax 가 TaxRateDetail[0].TaxRateRef.value 를 읽는다 · §15-l ③ 꼴) — 배포 뒤 Settings → QuickBooks matching → Refresh list(tax codes) 한 번 → HST Bill 의 TaxLine 이 선다(USD 여섯은 세금 0 이라 Refresh 전에도 간다)
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
export const ACTIONS = ["status", "start", "disconnect", "refresh", "ping", "query", "read", "pull", "send", "opening_candidates", "opening_read", "opening_search"] as const;   // [2e-1d-2 opening_*]
// ── qbo-sync-2a 판정 945 문 둘 — ADMIN_ACTIONS = qbo_admin_gate(연결 · 끊기 · 갱신 · 핑 · 원문 조회 933) · KEY_ACTIONS = qbo_key_gate(p_write true · perms 'qbo' · admin 도 켜야 한다 · 뒤에 send · job) · status 는 누구나 ──
export const ADMIN_ACTIONS = ["start", "disconnect", "refresh", "ping", "query", "read"] as const;
export const KEY_ACTIONS = ["pull", "send", "opening_candidates", "opening_read", "opening_search"] as const;   // [2e-1d-2 이월 짝 셋 — 북키퍼(열쇠 qbo)도 · ADMIN 아님]
// ── qbo-sync-2a′ 쓰기 길 — apiWrite 하나 · POST 만 · 만들기 customer · item · invoice · creditmemo(2b) · operation=void 는 invoice · creditmemo 만(2b · 2c) · operation=delete 없음 · requestid 필수(1 ~ 50 자 · Intuit 이 같은 id 면 처음 응답) · 자동 재시도 없음(retry false · 결과를 모르면 unknown → 다음 send 가 이름으로 조회) ──
export const WRITE_ENTITIES = ["customer", "item", "invoice", "creditmemo", "payment", "purchase", "journalentry", "vendor", "bill", "vendorcredit"] as const;      // [4-4 vendor · bill · vendorcredit — 만들기만(1126 · 1128)] · [3-3 journalentry — 만들기만(몸에 Id 없음)] · [2e-1c payment] · [2e-3-2-1b purchase — 만들기 + Full update void 꼴만(몸 검사)]
export const CREATE_ONLY_ENTITIES = ["journalentry", "vendor", "bill", "vendorcredit"] as const;                                       // 4-4: operation 없는 POST 에 몸 Id 가 있으면 거부(Full update 꼴) — 지우기 · void · update 길 없음(3-3 journalentry 에 공급처 셋을 더함 · E-7 Bill 에는 void 가 없다)
export const VOIDABLE_ENTITIES = ["invoice", "creditmemo"] as const;                                    // operation=void
export const UPDATE_VOID_ENTITIES = ["payment"] as const;                                              // 2e-1c: Payment 의 void = operation=update&include=void(sandbox B-6 실물) · 그 밖 update 는 없다
export const REQUESTID_MAX = 50;
export const SEND_LIMIT_DEFAULT = 15, SEND_LIMIT_MAX = 50;
export const SEND_PICK_MAX = 10, SEND_PICK_ROUNDS = 5, SEND_PICK_BUDGET_MS = 30_000, SEND_PICK_PARALLEL = 5;   // 2d1: 고른 id 한도(화면이 나눈다) · 바퀴(인보이스 → 부모 · Item → 손님 → 인보이스 다시 = 4 + 여유 1) · 바퀴 앞 예산 · 같은 바퀴 동시 수(Intuit 동시 한도 10 의 반)
export const DUPLICATE_NAME_CODE = "6240";                                                 // Intuit 「Duplicate Name Exists Error」 — 처리 안 됨이 분명 · Item 은 ` [SKU]` 로 한 번 더(다른 requestid · 이견 11)
export const DUPLICATE_DOCNUMBER_CODES = ["6140", "6210"] as const;                        // 2b2 Intuit 「Duplicate Document Number Error」(6140 · 6210 둘 다 본 적이 있다 — 지시서) → DocNumber 로 다시 찾아서 있으면 그것
export const STALE_OBJECT_CODE = "5010";                                                   // 2b2 Intuit 「Stale Object Error」 — void 의 SyncToken 이 낡았다 → 읽어서 한 번 더(requestid -2)
export const SEND_KINDS = ["customer", "item", "invoice", "invoice_void", "credit", "credit_void", "payment", "payment_void", "credit_apply", "credit_apply_void", "opening_credit", "opening_credit_void", "opening_apply", "opening_apply_void", "refund", "refund_void", "refund_apply", "refund_apply_void", "cost_day", "vendor", "bill", "vendor_credit"] as const;   // [4-4 vendor · bill · vendor_credit — 22 · bill_delete_manual 은 없다(1126 · 사람 일)] · [3-3 cost_day — 19 · 하루 원가 장 JournalEntry] · [2e-3-2-1b refund · refund_void · refund_apply · refund_apply_void] · 2b2 · [2c1 credit · credit_void] · [2e-1c payment · payment_void] · [2e-2-1b credit_apply · credit_apply_void] · [2e-3-1b opening_credit · opening_credit_void · opening_apply · opening_apply_void] 이 EF 가 보낼 줄 아는 일감 종류(claim p_kinds · DB 기본값은 customer · item)
export const COST_DAY_KINDS = ["cost_day"] as const;                                                    // 3-3 하루 원가 장(ims_kind cost_sheet · ims_id 「YYYY-MM-DD|TOR[|rebuild]」 · DocNumber COGS-YYYYMMDD-TOR(-R) · 열쇠 「<DocNumber>|<차변 센트>」)
export const SUPPLIER_KINDS = ["vendor", "bill", "vendor_credit"] as const;                                                     // 4-4 공급처 쪽(ims_kind supplier · po_invoice | po_charge · po_credit) — DEFAULT 에서 뺀다(cron 61 기본에 저절로 들어가는 함정 · §15-l ④)
export const SUPPLIER_TXN_KINDS = ["bill", "vendor_credit"] as const;                                                            // 4-4 거래 둘(DocNumber + VendorRef 가드 · 지문 「<총액 센트>|<통화>」 · 열쇠 「<DocNumber>|<VendorRef>|<센트>」)
export const DEFAULT_SEND_KINDS = SEND_KINDS.filter((k) => !(COST_DAY_KINDS as readonly string[]).includes(k) && !(SUPPLIER_KINDS as readonly string[]).includes(k)) as readonly string[];   // 3-3 ⬜1 · [4-4 공급처 셋도 뺀다]: kinds 없는 send(cron 61 · console)의 기본 18 — cost_day · vendor · bill · vendor_credit 는 kinds 에 명시하거나 job_ids 로 고를 때만(qbo_send_enabled 를 켜도 자동으로 나가지 않는다 · 1098) · sendPicked 는 SEND_KINDS 22
export const COST_DAY_DOC_RE = /^COGS-\d{8}-(TOR|EDM)(-R)?$/;                                            // 3-3 DB qbo_cost_sheet.doc_number 제약과 같은 꼴(17 · 19 자 · | 없음 → 열쇠 쪼개기 안전)
export const PAYMENT_KINDS = ["payment", "payment_void"] as const;                                     // 2e-1c 결제 일감(DocNumber 없음 · 열쇠 = 날짜 · 손님 · 금액 · PrivateNote)
export const CREDIT_APPLY_KINDS = ["credit_apply", "credit_apply_void"] as const;                      // 2e-2-1b 크레딧 붙임 = 0 원 Payment(DocNumber 없음 · 열쇠는 결제 꼴 · PrivateNote 「IMS credit applied <uuid>」)
export const TXN_KINDS = ["invoice", "invoice_void", "credit", "credit_void"] as const;      // 2c1 거래 일감(DocNumber 멱등 · 읽기 · 합계) — 인보이스 · 크레딧이 같은 길을 엔티티 열쇠만 바꿔 쓴다
export const OPENING_CREDIT_KINDS = ["opening_credit", "opening_credit_void"] as const;      // 2e-3-1b 이월 받아 둔 돈 붙임의 「쓰기」 CreditMemo(DocNumber OC-<인보이스>-<n> · credit · credit_void 길 그대로 · isTxnKind 가 TXN_KINDS 와 합쳐 본다)
export const OPENING_APPLY_KINDS = ["opening_apply", "opening_apply_void"] as const;         // 2e-3-1b 그 CreditMemo 를 인보이스에 잇는 0 원 Payment(credit_apply · credit_apply_void 길 그대로 · PrivateNote 「IMS opening credit applied <uuid>」 · isCreditApplyKind 가 합쳐 본다)
export const REFUND_KINDS = ["refund", "refund_void"] as const;                              // 2e-3-2-1b 환불의 크레딧 노트 몫 = Purchase(Expense) 만들기 · Full update void 꼴(ims_id = so_payment.id · PrivateNote 「IMS refund <uuid>」 · 열쇠는 결제 꼴)
export const REFUND_APPLY_KINDS = ["refund_apply", "refund_apply_void"] as const;            // 2e-3-2-1b 그 Purchase 와 CreditMemo 들을 잇는 0 원 Payment(Expense 줄 + CreditMemo 줄마다 · PrivateNote 「IMS refund applied <uuid>」) · void 는 payment_void 길
export const REFUND_GUARD_DAYS = 7, REFUND_GUARD_PAGES_MAX = 5;                              // 2e-3-2-1b 손 기록 찾기 = TxnDate paid_on ± 7 일(보고 ⓔ) · 1000 행 쪽은 최대 5(그 넘으면 failed · 사람이 좁힌다)
export const REFUND_GUARD_ENTITIES = ["Purchase", "JournalEntry", "RefundReceipt"] as const;  // 2e-3-2-1b 북키퍼가 환불을 손으로 넣었을 세 꼴(1060 · 60189 교훈)
export const VOIDED_NOTE_PREFIX = "Voided - ";                                                // 2e-3-2-1b sandbox 2-d: Purchase 는 금액 0 만으로는 Voided 가 아니다 — 이 머리가 가른다(QBO 의 Payment void 도 같은 머리를 붙인다)
// ── qbo-sync-1b pull — 종류 7 · 칸 · 쪽 1000 · Active 조건 없이 받는 종류(TaxCode · 11-01 실측) ──
export const PULL_ENTITIES = ["Account", "TaxCode", "Term", "PaymentMethod", "Customer", "Vendor", "Item"] as const;
export const PULL_PAGE = 1000;
export const PULL_FIELDS: Record<string, string> = {
  Account: "Id, Name, FullyQualifiedName, ParentRef, Active, SyncToken",
  TaxCode: "Id, Name, Active, SyncToken, SalesTaxRateList, PurchaseTaxRateList",                 // 2b2: TaxRateRef 를 DB 가 안다(qbo_entity.detail · qbo_invoice_body 의 TxnTaxDetail) · [4-4 PurchaseTaxRateList — Bill TaxLine 의 매입 세율(qbo_purchase_tax · DB 4-3a 가 detail 에 병합) · Refresh list(tax codes) 한 번]
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
export function assertWriteAllowed(method: string, url: string, body?: unknown): void {
  const m = String(method ?? "").toUpperCase(), u = new URL(url), path = u.pathname;
  if (m !== "POST") throw new QboError(500, `refusing ${m} ${path} — writes to QuickBooks are POST only (create · void) · nothing is ever deleted`);
  const mm = /^\/v3\/company\/[^/]+\/([a-z]+)\/?$/.exec(path);
  if (!mm || !(WRITE_ENTITIES as readonly string[]).includes(mm[1])) throw new QboError(500, `refusing POST ${path} — this function only creates ${WRITE_ENTITIES.join(", ")} (and voids ${VOIDABLE_ENTITIES.join(", ")})`);
  const op = u.searchParams.get("operation"), inc = u.searchParams.get("include");
  if (op !== null) {                                                                                 // 2e-1c: void 꼴 둘 — invoice · creditmemo 는 operation=void · payment 는 operation=update&include=void · 그 밖 operation(update 만 · delete)은 없다 · [2e-3-2-1b purchase 는 어느 operation 도 없다(void 는 Full update 꼴 · 아래)]
    const voidOk = op === "void" && (VOIDABLE_ENTITIES as readonly string[]).includes(mm[1]);
    const updVoidOk = op === "update" && inc === "void" && (UPDATE_VOID_ENTITIES as readonly string[]).includes(mm[1]);
    if (!voidOk && !updVoidOk) throw new QboError(500, `refusing POST ${path}?operation=${op}${inc !== null ? "&include=" + inc : ""} — only operation=void on ${VOIDABLE_ENTITIES.join(", ")} and operation=update&include=void on ${UPDATE_VOID_ENTITIES.join(", ")} · operation=delete is never sent`);
  } else if (inc !== null) throw new QboError(500, `refusing POST ${path}?include=${inc} — include is only sent with operation=update (void of a ${UPDATE_VOID_ENTITIES.join(", ")})`);
  if (mm[1] === "purchase") {                                                                        // 2e-3-2-1b 이견 7: Purchase 는 만들기와 Full update 가 같은 POST …/purchase — 몸으로 가른다 · Id 없음 = 만들기 · Id 있음 = void 꼴일 때만(sandbox 2-d) · 다른 엔티티의 몸은 이 차수에 보지 않는다
    const b = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
    if (b.Id !== undefined && b.Id !== null) {
      const why = purchaseVoidBodyProblem(b);
      if (why !== null) throw new QboError(500, `refusing POST ${path} with Id ${String(b.Id).slice(0, 20)} — the only update ever sent to a purchase is the void shape (every line Amount 0 · PrivateNote "${VOIDED_NOTE_PREFIX}…" · SyncToken · not sparse): ${why}`);
    }
  }
  if ((CREATE_ONLY_ENTITIES as readonly string[]).includes(mm[1])) {                                 // 3-3 ⬜2 · 이견 9 · [4-4 vendor · bill · vendorcredit 도]: 만들기만 — 몸에 Id 가 있으면(Full update · void 꼴) 거부 · 지우기 길 없음(374 · 1060 · 1101 · 1126 — 같은 장이 둘이면 사람이 QBO 에서 지운다)
    const b = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
    const word = mm[1] === "journalentry" ? "journal entry" : mm[1] === "vendorcredit" ? "vendor credit" : mm[1];
    if (b.Id !== undefined && b.Id !== null) throw new QboError(500, `refusing POST ${path} with Id ${String(b.Id).slice(0, 20)} — a ${word} is only ever created, never updated, voided or deleted from here`);
  }
  const rid = u.searchParams.get("requestid") ?? "";
  if (!rid || rid.length > REQUESTID_MAX) throw new QboError(500, `refusing POST ${path} without a requestid (1 … ${REQUESTID_MAX} characters) — every write carries the job request_id`);
}
// 2e-3-2-1b Purchase void 꼴 검사 — null 이면 void 꼴 · 글이면 왜 아닌가(assertWriteAllowed · 시험이 같이 쓴다)
export const purchaseVoidBodyProblem = (body: unknown): string | null => {
  const b = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  if (b.SyncToken === undefined || b.SyncToken === null || String(b.SyncToken).trim() === "") return "no SyncToken";
  if (b.sparse === true) return "sparse update";
  if (typeof b.PrivateNote !== "string" || !b.PrivateNote.startsWith(VOIDED_NOTE_PREFIX)) return `PrivateNote does not start with "${VOIDED_NOTE_PREFIX}"`;
  if (!Array.isArray(b.Line) || b.Line.length === 0) return "no lines";
  const bad = (b.Line as unknown[]).findIndex((l) => !(l && typeof l === "object") || (l as Record<string, unknown>).Amount !== 0);
  if (bad >= 0) return `line ${bad + 1} Amount is not 0`;
  return null;
};
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
  assertWriteAllowed("POST", u.toString(), bodyObj);                                                 // [2e-3-2-1b 몸도 — purchase 의 Full update 는 void 꼴만]
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
  fingerprint?: string | null; check_lines?: { txn_type?: string; invoice_number?: string; qbo_invoice_id?: string; credit_number?: string; qbo_creditmemo_id?: string; refund?: string; qbo_purchase_id?: string; amount: number }[] | null; lookup?: Record<string, unknown> | null };   // [2e-3-2-1b txn_type Expense · refund · qbo_purchase_id — DB qbo_refund_apply_body 꼴]   // 2e-1c 결제: (가) 가드 줄 · unknown 열쇠(1b claim) · [2e-2-1b txn_type Invoice | CreditMemo · credit_number · qbo_creditmemo_id — DB qbo_credit_apply_body 꼴]
type NeedJob = { job_id: string; kind: string; ims_kind: string; ims_id: string; state: string; name: string | null; existing: boolean; for_job: string; parent_job: string | null };
type Requested = { job_id: string; kind: string | null; state: string | null; result: string; reason: string | null };
type ClaimResult = { recovered_unknown: number; unblocked: number; claimed: number; body_failed: number; blocked_for_needs?: number; blocked_for_invoice?: number; need_jobs?: NeedJob[]; requested?: Requested[]; jobs: ClaimJob[] };
type UnknownRow = { job_id: string; kind: string; ims_kind: string; ims_id: string; qbo_name: string | null; sku: string | null; request_id: string; attempts: number };
type JobOut = { job_id: string; kind: string; ims_kind: string; ims_id: string; name: string; state: string; qbo_id: string | null; error: string | null; note: string | null; linked?: boolean; link_error?: string | null; mismatch?: string | null };
type EntityKey = { path: string; key: string; nameField: string };
const entityKeyOf = (kind: string): EntityKey => kind === "customer" ? { path: "customer", key: "Customer", nameField: "DisplayName" } : kind === "item" ? { path: "item", key: "Item", nameField: "Name" }
  : kind === "credit" || kind === "credit_void" || kind === "opening_credit" || kind === "opening_credit_void" ? { path: "creditmemo", key: "CreditMemo", nameField: "DocNumber" }   // [2e-3-1b opening_credit 둘 — 명시 가지 · ELSE(invoice)로 떨어지면 CreditMemo 를 Invoice 로 읽는다]
  : kind === "credit_apply" || kind === "credit_apply_void" || kind === "opening_apply" || kind === "opening_apply_void" ? { path: "payment", key: "Payment", nameField: "PrivateNote" }   // 2e-2-1b 0 원 Payment(PaymentRefNum 없음 · 이름은 PrivateNote) · [2e-3-1b opening_apply 둘]
  : kind === "refund" || kind === "refund_void" ? { path: "purchase", key: "Purchase", nameField: "PrivateNote" }                                              // [2e-3-2-1b 환불 = Purchase(Expense) · 이름은 PrivateNote — ELSE(invoice)로 떨어지면 Purchase 를 Invoice 로 읽는다]
  : kind === "refund_apply" || kind === "refund_apply_void" ? { path: "payment", key: "Payment", nameField: "PrivateNote" }                                        // [2e-3-2-1b 환불을 잇는 0 원 Payment]
  : kind === "cost_day" ? { path: "journalentry", key: "JournalEntry", nameField: "DocNumber" }                                                                     // [3-3 하루 원가 장 = JournalEntry · 명시 가지 — ELSE(invoice)로 떨어지면 JournalEntry 를 Invoice 로 읽는다]
  : kind === "vendor" ? { path: "vendor", key: "Vendor", nameField: "DisplayName" }                                                                                 // [4-4 공급처 Vendor(1128) · 손님 꼴 — unknown 풀기는 DisplayName 조회]
  : kind === "bill" ? { path: "bill", key: "Bill", nameField: "DocNumber" }                                                                                         // [4-4 공급처 인보이스 · 비용 문서 = Bill(1115 · 1129) · 명시 가지 — ELSE(invoice)로 떨어지면 Bill 을 Invoice 로 읽는다]
  : kind === "vendor_credit" ? { path: "vendorcredit", key: "VendorCredit", nameField: "DocNumber" }                                                                // [4-4 공급처 크레딧 = VendorCredit(1121)]
  : kind === "payment" || kind === "payment_void" ? { path: "payment", key: "Payment", nameField: "PaymentRefNum" } : { path: "invoice", key: "Invoice", nameField: "DocNumber" };   // 2c1 credit → CreditMemo · [2e-1c payment → Payment]
const isTxnKind = (kind: string): boolean => (TXN_KINDS as readonly string[]).includes(kind) || (OPENING_CREDIT_KINDS as readonly string[]).includes(kind);   // [2e-3-1b 합집합 — TXN_KINDS 무변]
const isPaymentKind = (kind: string): boolean => (PAYMENT_KINDS as readonly string[]).includes(kind);                            // 2e-1c
const isCreditApplyKind = (kind: string): boolean => (CREDIT_APPLY_KINDS as readonly string[]).includes(kind) || (OPENING_APPLY_KINDS as readonly string[]).includes(kind);   // 2e-2-1b · [2e-3-1b 합집합 — CREDIT_APPLY_KINDS 무변]
const isRefundKind = (kind: string): boolean => (REFUND_KINDS as readonly string[]).includes(kind);                              // 2e-3-2-1b Purchase 둘
const isRefundApplyKind = (kind: string): boolean => (REFUND_APPLY_KINDS as readonly string[]).includes(kind);                   // 2e-3-2-1b 0 원 Payment 둘(결제 꼴 열쇠 · void 는 Id)
const isCostDayKind = (kind: string): boolean => (COST_DAY_KINDS as readonly string[]).includes(kind);                           // 3-3 하루 원가 장
const isSupplierTxnKind = (kind: string): boolean => (SUPPLIER_TXN_KINDS as readonly string[]).includes(kind);                   // 4-4 Bill · VendorCredit(전용 가지 — isTxnKind 에 넣지 않는다 · 가드가 VendorRef 까지 본다)
const isNeedKind = (kind: string): boolean => kind === "customer" || kind === "item" || kind === "vendor";                      // 2e-2-1b 960: 같은 호출에서 대신 보내는 need 는 손님 · Item(· 부모 손님) · [4-4 공급처 Vendor(1128)] — 거래 · void 는 북키퍼가 고른다
// 4-4 공급처 Bill · VendorCredit — 순수: unknown 열쇠 「<DocNumber>|<VendorRef>|<센트>」(결제 paymentKeyOf · 원가 costDayKeyOf 꼴) · 오른쪽부터 쪼갠다(공급처 번호에 | 가 올 수 있다 — E-6: # · 쉼표 · 공백이 그대로 간다) · 지문 「<총액 센트>|<통화>」 앞 칸 · 가드 조회 글 · 응답 TotalAmt 센트
export const billKeyOf = (doc: string, vendorRef: string, cents: number | null): string => `${doc}|${vendorRef}|${cents === null ? "" : cents}`;
export const parseBillKey = (s: string | null | undefined): { doc: string; vendorRef: string; cents: number | null } | null => {
  const parts = String(s ?? "").split("|");
  if (parts.length < 3) return null;
  const cs = parts[parts.length - 1], vr = parts[parts.length - 2], doc = parts.slice(0, -2).join("|");
  if (!doc || !/^\d+$/.test(vr) || !(cs === "" || /^-?\d+$/.test(cs))) return null;
  return { doc, vendorRef: vr, cents: cs === "" ? null : Number(cs) };
};
export const fingerprintTotalCents = (fingerprint: string | null | undefined): number | null => {          // DB 지문 「<총액 센트>|<통화>」(qbo_bill_body · qbo_charge_bill_body · claim 때 고정)의 앞 칸
  const m = /^(-?\d+)\|/.exec(String(fingerprint ?? ""));
  return m ? Number(m[1]) : null;
};
export const billGuardQueryText = (key: string, doc: string, vendorRef: string): string => `select Id, DocNumber, SyncToken, TotalAmt, VendorRef from ${key} where DocNumber = ${sqlQuote(doc)} and VendorRef = ${sqlQuote(vendorRef)}`;   // 1127 · E-5(sandbox 에서 두 장 다 잡혔다) · Bill · VendorCredit 은 PII 엔티티가 아니다 · parseQuery 통과(MAXRESULTS 는 parseQuery 가 붙인다)
export const billTotalCents = (row: Record<string, unknown> | null): number | null => { const a = num(row?.TotalAmt); return a === null ? null : Math.round(a * 100); };   // 응답 · 읽은 Bill 의 TotalAmt(문서 통화 · E-1: HomeTotalAmt 는 응답에 없다 — HomeBalance 만)
// 3-3 하루 원가 장 — 순수: Debit 합(센트) · unknown 열쇠 「<DocNumber>|<차변 센트>」 · ims_id → DocNumber(stale sending 이라 열쇠가 없을 때 조회만)
export const journalDebitCents = (row: Record<string, unknown> | null): number | null => {                 // 응답 · 읽은 JournalEntry 의 Line 중 PostingType Debit 의 Amount 를 센트 정수로 더한다 · Line 이 없으면 null(S1: TotalAmt 는 0 으로 온다 — 쓰지 않는다)
  if (!row || !Array.isArray(row.Line)) return null;
  let cents = 0;
  for (const l of row.Line as Record<string, unknown>[]) {
    const d = ((l?.JournalEntryLineDetail ?? {}) as Record<string, unknown>);
    if (String(d.PostingType ?? "") !== "Debit") continue;
    const a = num(l?.Amount); if (a === null) continue;
    cents += Math.round(a * 100);
  }
  return cents;
};
export const fingerprintDebitCents = (fingerprint: string | null | undefined): number | null => {          // DB 지문 「<차변 센트>|<줄 md5>」(claim 때 고정)의 앞 칸
  const m = /^(\d+)\|/.exec(String(fingerprint ?? ""));
  return m ? Number(m[1]) : null;
};
export const costDayKeyOf = (doc: string, cents: number | null): string => cents === null ? doc : `${doc}|${cents}`;   // 1112 (가): 보내려던 차변을 열쇠에 싣는다(qbo_job_unknown_list 에 지문이 없다) · 결제 paymentKeyOf 꼴
export const parseCostDayKey = (s: string | null | undefined): { doc: string; cents: number | null } | null => {
  const parts = String(s ?? "").split("|");
  if (parts.length < 1 || parts.length > 2 || !COST_DAY_DOC_RE.test(parts[0])) return null;
  if (parts.length === 1) return { doc: parts[0], cents: null };
  return /^\d+$/.test(parts[1]) ? { doc: parts[0], cents: Number(parts[1]) } : null;
};
export const costDayDocOfImsId = (imsId: string | null | undefined): string | null => {                 // 「YYYY-MM-DD|TOR[|rebuild]」 → COGS-YYYYMMDD-TOR[-R](DB qbo_cost_sheet_ims_id 의 역) · 꼴이 아니면 null
  const m = /^(\d{4})-(\d{2})-(\d{2})\|(TOR|EDM)(\|rebuild)?$/.exec(String(imsId ?? ""));
  return m ? `COGS-${m[1]}${m[2]}${m[3]}-${m[4]}${m[5] ? "-R" : ""}` : null;
};
// 2e-1c 결제 unknown 열쇠 — qbo_job.qbo_name 한 칸에 「<PrivateNote>|<CustomerRef>|<TxnDate>|<TotalAmt>」(PrivateNote = 「IMS payment <uuid>」) · void 는 QBO Payment Id 만
export const paymentKeyOf = (lookup: Record<string, unknown> | null | undefined, body: Record<string, unknown>): string => {
  const l = lookup ?? {};
  const note = String(l.private_note ?? body.PrivateNote ?? ""), cust = String(l.customer_ref ?? ((body.CustomerRef ?? {}) as Record<string, unknown>).value ?? ""), date = String(l.txn_date ?? body.TxnDate ?? ""), amt = String(l.total_amt ?? body.TotalAmt ?? "");
  return [note, cust, date, amt].join("|");
};
export const parsePaymentKey = (s: string | null): { privateNote: string; customerRef: string; txnDate: string; totalAmt: number } | null => {
  const parts = String(s ?? "").split("|");
  if (parts.length !== 4 || !(parts[0].startsWith("IMS payment ") || parts[0].startsWith("IMS credit applied ") || parts[0].startsWith("IMS opening credit applied ") || parts[0].startsWith("IMS refund ")) || !/^\d{4}-\d{2}-\d{2}$/.test(parts[2]) || Number.isNaN(Date.parse(parts[2] + "T00:00:00Z")) || new Date(parts[2] + "T00:00:00Z").toISOString().slice(0, 10) !== parts[2] || !Number.isFinite(Number(parts[3]))) return null;
  return { privateNote: parts[0], customerRef: parts[1], txnDate: parts[2], totalAmt: Number(parts[3]) };
};
export const paymentsByDateQueryText = (date: string): string => `select Id, TotalAmt, UnappliedAmt, SyncToken, PrivateNote, PaymentRefNum, CustomerRef, TxnDate from Payment where TxnDate = ${sqlQuote(date)} MAXRESULTS 100`;   // PII 칸 없음(parseQuery 통과) · 하루치(실물 최대 64/일)
export const isVoidedPayment = (row: Record<string, unknown> | null): boolean => !!row && (num(row.TotalAmt) ?? -1) === 0 && String(row.PrivateNote ?? "").startsWith("Voided");   // sandbox B-6: TotalAmt 0 · PrivateNote 「Voided - …」
// 2e-3-2-1b Purchase — void 판정 · 그날 조회(unknown 풀기) · 손 기록 조회(TxnDate 범위 · 서버는 TxnDate 만 거른다) · 손님 · 금액 거르기(EF)
export const isVoidedPurchase = (row: Record<string, unknown> | null): boolean => !!row && (num(row.TotalAmt) ?? -1) === 0 && String(row.PrivateNote ?? "").startsWith(VOIDED_NOTE_PREFIX);   // sandbox 2-d: 금액 0 ∧ 「Voided - 」 머리 = status Voided(금액 0 만으로는 아니다)
export const purchasesByDateQueryText = (date: string): string => `select * from Purchase where TxnDate = ${sqlQuote(date)} MAXRESULTS ${MAXRESULTS_MAX}`;   // Purchase 는 PII 엔티티가 아니다(select * 통과 · 줄 CustomerRef 가 필요) · 행은 기록하지 않는다
export const refundGuardQueryText = (entity: string, from: string, to: string, start = 1): string =>
  `select ${entity === "RefundReceipt" ? "Id, TxnDate, TotalAmt, CustomerRef, PrivateNote, DocNumber" : "*"} from ${entity} where TxnDate >= ${sqlQuote(from)} and TxnDate <= ${sqlQuote(to)} STARTPOSITION ${start} MAXRESULTS ${MAXRESULTS_MAX}`;   // RefundReceipt 는 PII 엔티티라 칸을 적는다
export const shiftDate = (d: string, days: number): string => new Date(Date.parse(d + "T00:00:00Z") + days * 86_400_000).toISOString().slice(0, 10);
export const purchaseCustomerRefs = (row: Record<string, unknown>): string[] => {                     // EntityRef(Customer) + 줄 CustomerRef — 손 환불은 둘 중 어느 쪽에만 있을 수 있다
  const out: string[] = [], er = (row.EntityRef ?? null) as Record<string, unknown> | null;
  if (er && er.value != null && (er.type == null || String(er.type) === "Customer")) out.push(String(er.value));
  for (const l of Array.isArray(row.Line) ? row.Line as Record<string, unknown>[] : []) {
    const d = ((l?.AccountBasedExpenseLineDetail ?? l?.ItemBasedExpenseLineDetail ?? {}) as Record<string, unknown>), cr = (d.CustomerRef ?? null) as Record<string, unknown> | null;
    if (cr && cr.value != null) out.push(String(cr.value));
  }
  return out;
};
export const journalCustomerAmounts = (row: Record<string, unknown>, cust: string): { any: number[]; debit: number } => {   // JE 줄 Entity(Customer) 가 그 손님인 줄의 금액 · Debit(A/R 를 늘리는 쪽) 합
  const any: number[] = []; let debit = 0;
  for (const l of Array.isArray(row.Line) ? row.Line as Record<string, unknown>[] : []) {
    const d = ((l?.JournalEntryLineDetail ?? {}) as Record<string, unknown>), en = (d.Entity ?? null) as Record<string, unknown> | null, ref = (en?.EntityRef ?? null) as Record<string, unknown> | null;
    if (!ref || String(ref.value ?? "") !== cust || (en!.Type != null && String(en!.Type) !== "Customer")) continue;
    const a = num(l.Amount); if (a === null) continue;
    any.push(a); if (String(d.PostingType ?? "") === "Debit") debit = Math.round((debit + a) * 100) / 100;
  }
  return { any, debit };
};
const near = (a: number | null, b: number): boolean => a !== null && Math.abs(a - b) < 0.005;
export const refundHandHit = (entity: string, row: Record<string, unknown>, cust: string, amount: number): boolean => {   // 이견 3: 「IMS refund 」 머리(다른 IMS 환불)는 손 기록이 아니다 · Voided 제외 · PaymentType 은 보지 않는다
  if (entity === "Purchase") return !isVoidedPurchase(row) && !String(row.PrivateNote ?? "").startsWith("IMS refund ") && purchaseCustomerRefs(row).includes(cust) && near(num(row.TotalAmt), amount);
  if (entity === "JournalEntry") { const a = journalCustomerAmounts(row, cust); return a.any.some((x) => near(x, amount)) || (a.debit > 0 && near(a.debit, amount)); }
  if (entity === "RefundReceipt") return String(((row.CustomerRef ?? {}) as Record<string, unknown>).value ?? "") === cust && (num(row.TotalAmt) ?? 0) !== 0 && near(num(row.TotalAmt), amount);
  return false;
};
export const txnOpenBalances = (row: Record<string, unknown>): { type: string; id: string; open: string | null }[] =>   // Payment 응답 Line[].LineEx.any[] 의 txnOpenBalance(sandbox 걸음 25)
  (Array.isArray(row.Line) ? row.Line as Record<string, unknown>[] : []).map((l) => {
    const lt = ((((l.LinkedTxn ?? []) as Record<string, unknown>[])[0] ?? {}) as Record<string, unknown>);
    const any = (((l.LineEx ?? {}) as Record<string, unknown>).any ?? []) as Record<string, unknown>[];
    const hit = any.map((x) => (x?.value ?? {}) as Record<string, unknown>).find((v) => String(v.Name ?? "") === "txnOpenBalance");
    return { type: String(lt.TxnType ?? "?"), id: String(lt.TxnId ?? "?"), open: hit && hit.Value != null ? String(hit.Value) : null };
  });
const txnWord = (e: EntityKey): string => e.key === "CreditMemo" ? "credit memo" : e.key === "Purchase" ? "expense" : e.key === "JournalEntry" ? "journal entry" : e.key === "Bill" ? "bill" : e.key === "VendorCredit" ? "vendor credit" : "invoice";   // 사람 글의 낱말(failed · note) · [3-3 journal entry] · [4-4 bill · vendor credit]
const createdIdOf = (body: unknown, key: string): string | null => { const row = (body as Record<string, unknown>)?.[key] as Record<string, unknown> | undefined; return row && row.Id != null ? String(row.Id) : null; };
const rowOf = (body: unknown, key: string): Record<string, unknown> | null => { const row = (body as Record<string, unknown>)?.[key]; return row && typeof row === "object" && (row as Record<string, unknown>).Id != null ? row as Record<string, unknown> : null; };
const num = (v: unknown): number | null => (typeof v === "number" && Number.isFinite(v) ? v : typeof v === "string" && v.trim() !== "" && Number.isFinite(Number(v)) ? Number(v) : null);
export const openBalanceNote = (row: Record<string, unknown>): { note: string | null; warn: boolean } => {                           // 2e-3-2-1b2 이견 3 (나) — Payment 응답의 txnOpenBalance 는 잇기 **직전** 열린 금액(sandbox P3 잇기 · 걸음 25 → 26) · 줄마다 after = before − Line.Amount · Expense 줄은 |after| > 0.004 면 경고(남음 left · 모자람 short) · CreditMemo 줄은 after < −0.004 만(남는 크레딧은 정상 · 부분 사용)
  const lines = Array.isArray(row.Line) ? row.Line as Record<string, unknown>[] : [], parts: string[] = [], warns: string[] = [];
  for (const l of lines) {
    const ob = txnOpenBalances({ Line: [l] })[0], before = ob.open === null ? null : num(ob.open), amt = num(l.Amount) ?? 0;
    const after = before === null ? null : Math.round((before - amt) * 100) / 100;
    parts.push(`${ob.type} #${ob.id} ${ob.open ?? "?"} → ${after === null ? "?" : after} after`);
    if (after !== null && (ob.type === "CreditMemo" ? after < -0.004 : Math.abs(after) > 0.004)) warns.push(`${ob.type} #${ob.id} ${Math.abs(after)} ${after > 0 ? "left" : "short"}`);
  }
  if (!parts.length) return { note: null, warn: false };
  return { note: `QuickBooks open balance before linking: ${parts.join(" · ")}` + (warns.length ? ` — ${warns.join(" · ")}, check the refund in QuickBooks` : ""), warn: warns.length > 0 };
};
export const invoiceTotals = (row: Record<string, unknown> | null): { total_amt: number | null; total_tax: number | null } =>
  ({ total_amt: num(row?.TotalAmt), total_tax: num(((row?.TxnTaxDetail ?? {}) as Record<string, unknown>).TotalTax) });
export const QUERY_UNSELECTABLE: Record<string, readonly string[]> = { JournalEntry: ["TotalAmt"], BillPayment: ["PayType"] };   // 3-3b 실측 4001 「Invalid query — QueryValidationError: Property X not found for Entity Y」 — JournalEntry TotalAmt(운영 11-09 첫 cost_day 손 Send COGS-20261031-TOR) · BillPayment PayType(4-1 운영 콘솔 11-09) · select * 로는 온다 · 조회 문장에 적지 마라(가짜 Intuit 도 거부한다)
export const docNumberQueryText = (doc: string, key = "Invoice"): string => `select Id, DocNumber${key === "JournalEntry" ? "" : ", SyncToken, TotalAmt"} from ${key} where DocNumber = ${sqlQuote(doc)}`;   // PII 칸 없음(parseQuery 통과) · [2c1] CreditMemo 도 · [3-3b] JournalEntry 는 Id · DocNumber 만(TotalAmt 4001 · SyncToken 도 안 쓴다 — 금액 · SyncToken 은 1 행이면 GET(readTxn) 응답의 Line · SyncToken 으로)
const jobDetail = (j: { job_id: string; kind: string; ims_kind: string; ims_id: string }, extra: Record<string, unknown> = {}): Record<string, unknown> => ({ job_id: j.job_id, kind: j.kind, ims_kind: j.ims_kind, ims_id: j.ims_id, ...extra });
// DocNumber 로 찾기(send_check · GET …/query) — rows(0 · 1 · n) · 실패면 error
async function findByDocNumber(c: Ctx, doc: string, j: { job_id: string; kind: string; ims_kind: string; ims_id: string }, e: EntityKey = entityKeyOf(j.kind)): Promise<{ r: IntuitResult; rows: Record<string, unknown>[] }> {
  const p = parseQuery(docNumberQueryText(doc, e.key));
  const detailOf = (r: IntuitResult): Record<string, unknown> => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return jobDetail(j, { rows: Array.isArray(qr[e.key]) ? (qr[e.key] as unknown[]).length : 0, q: queryForLog(p.text) }); };
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "send_check", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
  const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
  return { r, rows: r.error ? [] : Array.isArray(qr[e.key]) ? qr[e.key] as Record<string, unknown>[] : [] };
}
// 4-4 공급처 Bill · VendorCredit 가드 조회(send_check · DocNumber + VendorRef · 1127 · E-5) — rows(0 · 1 · n) · 실패면 error · 행은 기록하지 않는다(detail 은 rows · q 뿐)
async function findByVendorDoc(c: Ctx, doc: string, vendorRef: string, j: { job_id: string; kind: string; ims_kind: string; ims_id: string }, e: EntityKey): Promise<{ r: IntuitResult; rows: Record<string, unknown>[] }> {
  const p = parseQuery(billGuardQueryText(e.key, doc, vendorRef));
  const detailOf = (r: IntuitResult): Record<string, unknown> => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return jobDetail(j, { rows: Array.isArray(qr[e.key]) ? (qr[e.key] as unknown[]).length : 0, q: queryForLog(p.text) }); };
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "send_check", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
  const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
  return { r, rows: r.error ? [] : Array.isArray(qr[e.key]) ? qr[e.key] as Record<string, unknown>[] : [] };
}
// 거래 한 장 읽기(send_read · GET …/invoice/<id> · [2c1] …/creditmemo/<id> · [4-4] …/bill/<id> · …/vendorcredit/<id>) — 합계 · SyncToken 을 쓰려고 · 행은 돌려주되 기록 · 응답에는 싣지 않는다
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
// 2e-3-2-1b 그 날의 Purchase 전부(send_check) — unknown 풀기가 PrivateNote 완전 일치 · 손님 · Voided 아님으로 고른다
async function findPurchasesByDate(c: Ctx, date: string, j: { job_id: string; kind: string; ims_kind: string; ims_id: string }): Promise<{ r: IntuitResult; rows: Record<string, unknown>[] }> {
  const p = parseQuery(purchasesByDateQueryText(date));
  const detailOf = (r: IntuitResult): Record<string, unknown> => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return jobDetail(j, { rows: Array.isArray(qr.Purchase) ? (qr.Purchase as unknown[]).length : 0, q: queryForLog(p.text) }); };
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "send_check", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
  const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>;
  return { r, rows: r.error ? [] : Array.isArray(qr.Purchase) ? qr.Purchase as Record<string, unknown>[] : [] };
}
// 2e-3-2-1b 손 기록 찾기(send_check · TxnDate 범위 · 1000 행 쪽 · 최대 REFUND_GUARD_PAGES_MAX) — 거르기는 부르는 쪽(refundHandHit) · 행은 기록하지 않는다
async function findByDateRange(c: Ctx, entity: string, from: string, to: string, j: { job_id: string; kind: string; ims_kind: string; ims_id: string }): Promise<{ r: IntuitResult; rows: Record<string, unknown>[]; pages: number; truncated: boolean }> {
  const rows: Record<string, unknown>[] = []; let start = 1, pages = 0, last: IntuitResult | null = null;
  while (pages < REFUND_GUARD_PAGES_MAX) {
    const p = parseQuery(refundGuardQueryText(entity, from, to, start));
    const detailOf = (r: IntuitResult): Record<string, unknown> => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return jobDetail(j, { rows: Array.isArray(qr[entity]) ? (qr[entity] as unknown[]).length : 0, q: queryForLog(p.text), page: pages + 1 }); };
    const { r } = await withAuthRetry(c, (h) => apiCall(c, "send_check", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
    last = r; pages++;
    if (r.error) return { r, rows: [], pages, truncated: false };
    const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>, got = Array.isArray(qr[entity]) ? qr[entity] as Record<string, unknown>[] : [];
    rows.push(...got);
    if (got.length < MAXRESULTS_MAX) return { r, rows, pages, truncated: false };
    start += MAXRESULTS_MAX;
  }
  return { r: last!, rows, pages, truncated: true };
}
// 2e-1c 결제 done — 10 인자(p_unapplied_amt · DB 가 amount · amount − Σ붙임 과 견준다 · total_tax 는 null)
async function donePayment(c: Ctx, jobId: string, row: Record<string, unknown>, name: string, tid: string | null, note: string | null): Promise<Record<string, unknown>> {
  return await c.d.rpcService("qbo_job_done", { p_job: jobId, p_qbo_id: String(row.Id), p_qbo_name: name, p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: tid, p_note: note, p_sku: null, p_total_amt: num(row.TotalAmt), p_total_tax: null, p_unapplied_amt: num(row.UnappliedAmt) }) as Record<string, unknown>;
}
async function doneTxn(c: Ctx, jobId: string, row: Record<string, unknown>, doc: string, tid: string | null, note: string | null): Promise<Record<string, unknown>> {
  const t = invoiceTotals(row);
  return await c.d.rpcService("qbo_job_done", { p_job: jobId, p_qbo_id: String(row.Id), p_qbo_name: String(row.DocNumber ?? doc), p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: tid, p_note: note, p_sku: null, p_total_amt: t.total_amt, p_total_tax: t.total_tax }) as Record<string, unknown>;
}
// 3-3 하루 원가 장 done — p_total_amt = Debit 합(센트 → 금액 · S1 TotalAmt 0 이라 응답 합계를 쓰지 않는다) · p_total_tax null · DB 가 round(*100) ↔ 지문 앞 칸을 견줘 mismatch · qbo_name 은 DocNumber 로(열쇠 꼴을 되돌린다)
async function doneJournal(c: Ctx, jobId: string, row: Record<string, unknown>, doc: string, tid: string | null, note: string | null): Promise<Record<string, unknown>> {
  const cents = journalDebitCents(row);
  return await c.d.rpcService("qbo_job_done", { p_job: jobId, p_qbo_id: String(row.Id), p_qbo_name: String(row.DocNumber ?? doc), p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: tid, p_note: note, p_sku: null, p_total_amt: cents === null ? null : cents / 100, p_total_tax: null }) as Record<string, unknown>;
}
async function resolveUnknown(c: Ctx, u: UnknownRow): Promise<Record<string, unknown>> {
  const out: Record<string, unknown> = { job_id: u.job_id, kind: u.kind, ims_kind: u.ims_kind, ims_id: u.ims_id };
  if (isCostDayKind(u.kind)) {                                                                         // 3-3 ⬜5 · 판정 1112 — 열쇠 「<DocNumber>|<차변 센트>」(qbo_name) · 없으면(stale sending) ims_id 로 DocNumber 만 → 조회 → 0 · 2+ 그대로 · 1 → 읽어서 Debit 합 = 열쇠 센트일 때만 done · 다르면 그대로 + 글 · 센트 없으면 그대로 + 글(금액을 못 견주면 자동 없음)
    const e = entityKeyOf(u.kind), word = txnWord(e);
    const k = parseCostDayKey(u.qbo_name) ?? (u.qbo_name ? null : (() => { const d = costDayDocOfImsId(u.ims_id); return d ? { doc: d, cents: null } : null; })());
    if (!k) return { ...out, result: "no_name", message: "the cost day key on the job is not readable — check QuickBooks by hand, then resolve the cost day as in_qbo or not_in_qbo" };
    const { r, rows } = await findByDocNumber(c, k.doc, u, e);
    if (r.error) return { ...out, result: "check_failed", error: r.error };
    if (rows.length === 0) return { ...out, result: "not_found", message: `QuickBooks has no ${word} with number ${k.doc} — if it really is not there, retry the job by hand or resolve the cost day as not_in_qbo (Cost days)` };
    if (rows.length > 1) return { ...out, result: "ambiguous", count: rows.length, message: `QuickBooks has ${rows.length} ${word}s with number ${k.doc} (#${rows.map((x) => String(x.Id)).join(", #")}) — remove the extra in QuickBooks, then resolve the cost day as in_qbo with the one left` };
    const rd = await readTxn(c, String(rows[0].Id), u, e);
    if (rd.r.error || !rd.row) return { ...out, result: "check_failed", error: rd.r.error ?? `${word} could not be read` };
    const id = String(rd.row.Id), got = journalDebitCents(rd.row);
    if (k.cents === null) return { ...out, result: "needs_hand", qbo_id: id, message: `QuickBooks has ${word} #${id} with number ${k.doc} but the expected debit is not on the job — check it in QuickBooks, then resolve the cost day as in_qbo (with #${id}) or not_in_qbo by hand` };
    if (got === null) return { ...out, result: "needs_hand", qbo_id: id, message: `QuickBooks ${word} #${id} with number ${k.doc} came back without lines — check it in QuickBooks, then resolve the cost day as in_qbo (with #${id}) or not_in_qbo by hand` };
    if (got !== k.cents) return { ...out, result: "amount_differs", qbo_id: id, qbo_debit: got / 100, expected_debit: k.cents / 100, message: `QuickBooks JournalEntry #${id} with DocNumber ${k.doc} has debits ${(got / 100).toFixed(2)} but this cost day expects ${(k.cents / 100).toFixed(2)} — not recorded. Check it in QuickBooks: if it is right, resolve in_qbo with that Id; if not, remove it there, then resolve not_in_qbo` };
    const d = await doneJournal(c, u.job_id, rd.row, k.doc, rd.r.tid, "result was unknown — found in QuickBooks by DocNumber with the same debits and recorded");
    return { ...out, result: "found", qbo_id: id, state: d?.state ?? null, mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
  }
  if (!u.qbo_name) return { ...out, result: "no_name", message: "the name that was sent is not on the job — retry it by hand after checking QuickBooks" };
  if (isSupplierTxnKind(u.kind)) {                                                                     // 4-4 판정 1127 — 열쇠 「<DocNumber>|<VendorRef>|<센트>」 → 가드 조회(DocNumber + VendorRef) → 0 · 2+ 그대로 · 1 → GET 읽어 TotalAmt 센트 = 열쇠 센트일 때만 done · 다르면 그대로 + 글 · 센트 없으면 그대로 + 글(자동 없음 · 사람이 본다)
    const e = entityKeyOf(u.kind), word = txnWord(e);
    const k = parseBillKey(u.qbo_name);
    if (!k) return { ...out, result: "no_name", message: `the ${word} key on the job is not readable — check QuickBooks by hand, then retry the job with a note or skip it` };
    const { r, rows } = await findByVendorDoc(c, k.doc, k.vendorRef, u, e);
    if (r.error) return { ...out, result: "check_failed", error: r.error };
    if (rows.length === 0) return { ...out, result: "not_found", message: `QuickBooks has no ${word} with number ${k.doc} for vendor #${k.vendorRef} — if it really is not there, retry the job by hand (Sales → QuickBooks)` };
    if (rows.length > 1) return { ...out, result: "ambiguous", count: rows.length, message: `QuickBooks has ${rows.length} ${word}s with number ${k.doc} for vendor #${k.vendorRef} (#${rows.map((x) => String(x.Id)).join(", #")}) — remove the extra in QuickBooks by hand (nothing is deleted from here), then retry the job with a note; or skip it` };
    const rd = await readTxn(c, String(rows[0].Id), u, e);
    if (rd.r.error || !rd.row) return { ...out, result: "check_failed", error: rd.r.error ?? `${word} could not be read` };
    const id = String(rd.row.Id), got = billTotalCents(rd.row);
    if (k.cents === null) return { ...out, result: "needs_hand", qbo_id: id, message: `QuickBooks has ${word} #${id} with number ${k.doc} for vendor #${k.vendorRef} but the expected total is not on the job — check it in QuickBooks, then retry the job with a note or skip it` };
    if (got === null) return { ...out, result: "needs_hand", qbo_id: id, message: `QuickBooks ${word} #${id} with number ${k.doc} for vendor #${k.vendorRef} came back without TotalAmt — check it in QuickBooks, then retry the job with a note or skip it` };
    if (got !== k.cents) return { ...out, result: "amount_differs", qbo_id: id, qbo_total: got / 100, expected_total: k.cents / 100, message: `QuickBooks ${word} #${id} with number ${k.doc} for vendor #${k.vendorRef} totals ${(got / 100).toFixed(2)} but this job expects ${(k.cents / 100).toFixed(2)} — not recorded (1127). Check it in QuickBooks: if it is this document, fix whichever side is wrong, then retry the job with a note; if it is another document, change its number there, then retry` };
    const d = await doneTxn(c, u.job_id, rd.row, k.doc, rd.r.tid, `result was unknown — found in QuickBooks by vendor, number and total (${word} #${id}) and recorded`);
    return { ...out, result: "found", qbo_id: id, state: d?.state ?? null, mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
  }
  if (isPaymentKind(u.kind) || isCreditApplyKind(u.kind) || isRefundApplyKind(u.kind)) {           // [2e-3-2-1b refund_apply 둘도 — 0 원 Payment]                                          // 2e-1c — 결제: 열쇠(날짜 · 손님 · 금액 · PrivateNote) · void 는 Id 로 읽어 Voided 인지 · [2e-2-1b 크레딧 붙임도 이 문으로(0 원 Payment)] · [2e-3-1b opening_apply 둘도]
    const e = entityKeyOf(u.kind);
    if (u.kind === "payment_void" || u.kind === "credit_apply_void" || u.kind === "opening_apply_void" || u.kind === "refund_apply_void") {   // [2e-3-2-1b refund_apply_void]   // [2e-2-1b credit_apply_void 도 같은 길 — Id 로 읽어 Voided 면 done] · [2e-3-1b opening_apply_void]
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
    if (u.kind === "credit_apply" || u.kind === "opening_apply" || u.kind === "refund_apply") {       // [2e-3-2-1b refund_apply — 접두 「IMS refund applied 」]                                   // 2e-2-1b — 0 원 Payment: 손님 · TotalAmt 0 · PrivateNote 완전 일치(void 된 장은 「Voided - 」 가 붙어 빠진다) · Voided 제외 · DocNumber 조회 없음 · [2e-3-1b opening_apply 도 — 접두 「IMS opening credit applied 」]
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
  if (isRefundKind(u.kind)) {                                                                          // 2e-3-2-1b — refund: 그날 Purchase 조회 → PrivateNote 완전 일치 ∧ 손님 ∧ Voided 아님(1 done · 0 not_found · 2+ ambiguous) · refund_void: Id 로 읽어 금액 0 ∧ 「Voided - 」 면 done
    const e = entityKeyOf(u.kind);
    if (u.kind === "refund_void") {
      const rd = await readTxn(c, u.qbo_name, u, e);
      if (rd.r.error || !rd.row) return { ...out, result: "not_found", message: `QuickBooks expense #${u.qbo_name} could not be read (${rd.r.error ?? "no row"}) — check by hand, then retry or skip the job` };
      if (!isVoidedPurchase(rd.row)) return { ...out, result: "not_voided", qbo_id: String(rd.row.Id), message: "the QuickBooks expense still carries an amount or lacks the Voided note — the void did not go through; retry the job by hand" };
      const d = await c.d.rpcService("qbo_job_done", { p_job: u.job_id, p_qbo_id: String(rd.row.Id), p_qbo_name: String(rd.row.DocNumber ?? ("expense " + String(rd.row.Id))), p_sync_token: rd.row.SyncToken != null ? String(rd.row.SyncToken) : null, p_intuit_tid: rd.r.tid, p_note: "result was unknown — the QuickBooks expense is voided (amount 0 · Voided note)", p_sku: null }) as Record<string, unknown>;
      return { ...out, result: "found", qbo_id: String(rd.row.Id), state: d?.state ?? "sent" };
    }
    const k = parsePaymentKey(u.qbo_name);
    if (!k) return { ...out, result: "no_name", message: "the expense key on the job is not readable — retry it by hand after checking QuickBooks" };
    const { r, rows } = await findPurchasesByDate(c, k.txnDate, u);
    if (r.error) return { ...out, result: "error", message: "the QuickBooks check failed: " + r.error };
    const ch = rows.filter((p) => String(p.PrivateNote ?? "") === k.privateNote && !isVoidedPurchase(p) && purchaseCustomerRefs(p).includes(k.customerRef));
    if (ch.length === 0) return { ...out, result: "not_found", message: `QuickBooks has no expense on ${k.txnDate} for customer ${k.customerRef} with note "${k.privateNote}" — if it really is not there, retry the job by hand (Sales → QuickBooks)` };
    if (ch.length > 1) return { ...out, result: "ambiguous", rows: ch.length, message: `QuickBooks has ${ch.length} expenses matching this refund — pick by hand (skip the job and link, or void the extra in QuickBooks)` };
    const d = await doneTxn(c, u.job_id, ch[0], String(ch[0].DocNumber ?? k.privateNote), r.tid, "result was unknown — found in QuickBooks by date, customer and note, and recorded");
    return { ...out, result: "found", qbo_id: String(ch[0].Id), state: d?.state ?? "sent", mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
  }
  if (isTxnKind(u.kind)) {                                                                             // 2b2 — DocNumber 로 · [2c1] credit · credit_void 도(CreditMemo) · [2e-3-1b opening_credit 둘도(OC-<인보이스>-<n> · CreditMemo)]
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
    if (isCostDayKind(j.kind)) {                                                                       // 3-3 ⬜3 · ⬜4 · 이견 1 · 판정 1112 — 하루 원가 장: DocNumber 조회(0 행만 보낸다 · 1 행 이상은 unknown + 글 · 조회 실패는 failed) → POST journalentry(몸 = DB qbo_cost_day_body 그대로) → doneJournal(Debit 합) · 6140 · 6210 · 5xx · 끊김 · 몸 없음 → unknown(열쇠 「<doc>|<센트>」)
      const word = txnWord(e);
      const doc = String(j.doc_number ?? j.name), cents = fingerprintDebitCents(j.fingerprint), key = costDayKeyOf(doc, cents); nameSent = key;
      const pre = await findByDocNumber(c, doc, j, e);
      if (pre.r.error) return await fail("not sent — the DocNumber check failed before sending: " + pre.r.error, pre.r.tid);
      if (pre.rows.length >= 1) return await unknown(`not sent — QuickBooks already has ${word} #${pre.rows.map((x) => String(x.Id)).join(", #")} with DocNumber ${doc} — if it is this cost day, resolve it as in_qbo with that Id; if not, remove it in QuickBooks, then resolve not_in_qbo`, pre.r.tid, key);
      const { r } = await attempt(j.body, j.request_id);
      const cls = classifyWrite(r.status, r.networkError);
      if (cls === "fail" && (DUPLICATE_DOCNUMBER_CODES as readonly string[]).includes(faultCode(r.body) ?? "")) return await unknown(`QuickBooks answered duplicate DocNumber (${faultCode(r.body)}) after the check found none — checked by number at the next send`, r.tid, key);   // 짐작 밖(S2: QBO 는 JE 번호 중복을 막지 않는다) — 와도 다음 풀기가 1112 로 견준다
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the created ${e.key} — checked by number at the next send`, r.tid, key);
        const d = await doneJournal(c, j.job_id, row, doc, r.tid, null);
        return { ...base, name: doc, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail(r.error ?? ("HTTP " + r.status), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, key);
    }
    if (isSupplierTxnKind(j.kind)) {                                                                  // 4-4 판정 1115 ~ 1118 · 1121 · 1127 · 1129 · 1130 · 이견 1 ~ 3 · 7 — Bill · VendorCredit: 가드 조회(DocNumber + VendorRef · E-5) → 조회 실패 failed · 2+ unknown · 1 행 → GET 읽어 센트 같으면 done + note · 다르면 unknown · 0 행 → POST(몸 = DB qbo_bill_body · qbo_charge_bill_body 그대로) → doneTxn(TotalAmt · TotalTax) · 6140 · 6210 · 5xx · 끊김 · 몸 없음 → unknown(열쇠 「<DocNumber>|<VendorRef>|<센트>」)
      const word = txnWord(e), l = j.lookup ?? {};
      const doc = String(l.doc_number ?? j.doc_number ?? j.name), cur = String(l.currency ?? ((j.body.CurrencyRef ?? {}) as Record<string, unknown>).value ?? "");
      const vendorRef = String(((j.body.VendorRef ?? {}) as Record<string, unknown>).value ?? l.vendor_ref ?? "");
      const lc = l.total_cents, cents = lc !== null && lc !== undefined && String(lc) !== "" && Number.isInteger(Number(lc)) ? Number(lc) : fingerprintTotalCents(j.fingerprint);
      const key = billKeyOf(doc, vendorRef, cents); nameSent = key;
      if (!vendorRef) return await fail(`not sent — the job carries no QuickBooks vendor for ${word} ${doc} — nothing was written; link or create the supplier's QuickBooks vendor first, then retry`, null);
      const pre = await findByVendorDoc(c, doc, vendorRef, j, e);
      if (pre.r.error) return await fail(`not sent — the QuickBooks check for an existing ${word} failed before sending: ` + pre.r.error, pre.r.tid);
      if (pre.rows.length > 1) return await unknown(`not sent — QuickBooks already has ${pre.rows.length} ${word}s with number ${doc} for vendor #${vendorRef} (#${pre.rows.map((x) => String(x.Id)).join(", #")}) — remove the extra in QuickBooks by hand (nothing is deleted from here), then retry the job with a note; or skip it`, pre.r.tid, key);
      if (pre.rows.length === 1) {
        const id = String(pre.rows[0].Id), rd = await readTxn(c, id, j, e);
        if (rd.r.error || !rd.row) return await fail(`not sent — QuickBooks already has ${word} #${id} with number ${doc} for vendor #${vendorRef} but it could not be read: ${rd.r.error ?? "no row"} — nothing was written`, rd.r.tid);
        const got = billTotalCents(rd.row);
        if (cents !== null && got !== null && got === cents) {
          note = `already in QuickBooks (${word} #${id} — same vendor, number and total found before sending) — recorded, not created again`;
          const d = await doneTxn(c, j.job_id, rd.row, doc, rd.r.tid, note);
          return { ...base, name: doc, state: String(d?.state ?? "sent"), qbo_id: id, note, mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
        }
        return await unknown(`not sent — QuickBooks already has ${word} #${id} with number ${doc} for vendor #${vendorRef} totalling ${got === null ? "?" : (got / 100).toFixed(2)} ${cur} while this job expects ${cents === null ? "?" : (cents / 100).toFixed(2)} ${cur} — not recorded (1127). Check it in QuickBooks: if it is this document, fix whichever side is wrong, then retry the job with a note; if it is another document, change its number there, then retry`, rd.r.tid, key);
      }
      const { r } = await attempt(j.body, j.request_id);
      const cls = classifyWrite(r.status, r.networkError);
      if (cls === "fail" && (DUPLICATE_DOCNUMBER_CODES as readonly string[]).includes(faultCode(r.body) ?? "")) return await unknown(`QuickBooks answered duplicate DocNumber (${faultCode(r.body)}) after the check found none — checked by vendor, number and total at the next send`, r.tid, key);   // 이견 3: 운영 WarnDuplicateBillNumber 미확인 — 와도 다음 풀기가 1127 로 견준다
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the created ${e.key} — checked by vendor, number and total at the next send`, r.tid, key);
        const d = await doneTxn(c, j.job_id, row, doc, r.tid, null);
        return { ...base, name: doc, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail(r.error ?? ("HTTP " + r.status), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, key);
    }
    if (j.kind === "invoice" || j.kind === "credit" || j.kind === "opening_credit") {                   // 2b2 · [2c1 credit] · [2e-3-1b opening_credit — 「쓰기」 CreditMemo · 몸은 DB qbo_opening_credit_body 그대로] — 멱등: DocNumber 가 이미 있으면 만들지 않는다
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
    if (j.kind === "credit_apply" || j.kind === "opening_apply") {                                     // 2e-2-1b 판정 1009 · 1012 · 1016 · sandbox C-5″ · [2e-3-1b opening_apply — 몸은 DB qbo_opening_apply_body 그대로 · check_lines 의 credit_number = OC 번호] — 가드 둘(Invoice Balance ≥ a · CreditMemo RemainingCredit ≥ a · 모자라거나 못 읽으면 failed · 보내지 않는다) → POST payment(0 원 · 몸 그대로) → donePayment 10 인자(TotalAmt 0 · UnappliedAmt 0) · unknown 은 결제 꼴 열쇠
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
    if (j.kind === "payment_void" || j.kind === "credit_apply_void" || j.kind === "opening_apply_void" || j.kind === "refund_apply_void") {   // [2e-3-2-1b refund_apply_void — ⓖ-7 Purchase void 보다 먼저(DB 사슬)]   // 2e-1c 978 · sandbox B-6 · [2e-3-1b opening_apply_void 도 같은 길] — POST payment?operation=update&include=void {Id, SyncToken, sparse} · 5010 → 읽어서 -2 · 4xx failed · 5xx unknown(qbo_name = Id) · [2e-2-1b credit_apply_void 는 같은 길 · 1011 · C-6]
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
    if (j.kind === "refund") {                                                                         // 2e-3-2-1b 판정 1056 ~ 1058 · 이견 3 · sandbox 2-a — Purchase(Expense) 만들기: 가드 ① CreditMemo RemainingCredit ≥ 몫 ② 손 기록 찾기(Purchase · JournalEntry · RefundReceipt · paid_on ± 7 일 · EF 가 거른다) → POST purchase(몸은 DB qbo_refund_body 그대로) → doneTxn(TotalAmt · TotalTax) · unknown 은 결제 꼴 열쇠
      const key = paymentKeyOf(j.lookup, j.body); nameSent = key;
      const l = j.lookup ?? {}, lineSum = (Array.isArray(j.body.Line) ? j.body.Line as Record<string, unknown>[] : []).reduce((a, x) => a + (num(x.Amount) ?? 0), 0);
      const cust = String(l.customer_ref ?? ((j.body.EntityRef ?? {}) as Record<string, unknown>).value ?? ""), date = String(l.txn_date ?? j.body.TxnDate ?? ""), amount = num(l.total_amt) ?? num(((j.totals ?? {}) as Record<string, unknown>).credit_covered) ?? Math.round(lineSum * 100) / 100;
      if (!cust || !/^\d{4}-\d{2}-\d{2}$/.test(date) || !(amount > 0)) return await fail(`not sent — the job carries no QuickBooks customer, date or amount (customer "${cust}" · date "${date}" · amount ${amount}) — nothing was written; check the refund and retry`, null);
      const cmL = (j.check_lines ?? []).filter((cl) => cl.txn_type === "CreditMemo");
      if (cmL.length === 0) return await fail("not sent — the job carries no credit memo line to check — nothing was written; check the refund and retry", null);
      for (const cc of cmL) {                                                                          // ① credit_apply 가드 꼴 — 손 기록이 그 크레딧을 썼으면 여기서 잡힌다(60189)
        const rdC = await readTxn(c, String(cc.qbo_creditmemo_id), j, entityKeyOf("credit"));
        if (rdC.r.error || !rdC.row) return await fail(`not sent — could not read credit memo ${cc.credit_number} (QuickBooks #${cc.qbo_creditmemo_id}) before sending: ${rdC.r.error ?? "no row"} — nothing was written`, rdC.r.tid);
        const rem = num(rdC.row.RemainingCredit);
        if (rem === null) return await fail(`not sent — credit memo ${cc.credit_number} (QuickBooks #${cc.qbo_creditmemo_id}) has no RemainingCredit in QuickBooks (voided?) — check by hand, then retry or skip`, rdC.r.tid);
        if (rem + 0.004 < Number(cc.amount)) return await fail(`not sent — QuickBooks shows only ${rem} left on credit memo ${cc.credit_number} (less than the ${cc.amount} this refund pays out) — refunded or applied in QuickBooks already? check before sending, then retry or skip`, rdC.r.tid);
      }
      const from = shiftDate(date, -REFUND_GUARD_DAYS), to = shiftDate(date, REFUND_GUARD_DAYS);        // ② 60189 교훈 · 1060 꼴 — 북키퍼가 손으로 넣은 환불이 이미 있으면 보내지 않는다
      for (const ent of REFUND_GUARD_ENTITIES) {
        const q = await findByDateRange(c, ent, from, to, j);
        if (q.r.error) return await fail(`not sent — the QuickBooks check for hand-entered refunds (${ent}) failed before sending: ${q.r.error} — nothing was written`, q.r.tid);
        if (q.truncated) return await fail(`not sent — QuickBooks has more than ${REFUND_GUARD_PAGES_MAX * MAXRESULTS_MAX} ${ent} records between ${from} and ${to}, too many to check — look for a hand-entered refund in QuickBooks by hand, then retry or skip`, q.r.tid);
        const hit = q.rows.find((row) => refundHandHit(ent, row, cust, amount));
        if (hit) {
          const word = ent === "Purchase" ? "an expense" : ent === "JournalEntry" ? "a journal entry" : "a refund receipt", shown = ent === "JournalEntry" ? amount : (num(hit.TotalAmt) ?? amount);
          return await fail(`not sent — QuickBooks already shows ${word} of ${shown} to this customer on ${String(hit.TxnDate ?? "?")} (${ent} #${String(hit.Id ?? "?")}) — if it was entered by hand, delete it in QuickBooks, then Retry; if it is right, Skip this job`, q.r.tid);
        }
      }
      const { r } = await attempt(j.body, j.request_id);
      const cls = classifyWrite(r.status, r.networkError);
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the created Purchase — checked by date, customer and note at the next send`, r.tid, key);
        const d = await doneTxn(c, j.job_id, row, String(row.DocNumber ?? j.name), r.tid, null);
        return { ...base, name: j.name, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail(r.error ?? ("HTTP " + r.status), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, key);
    }
    if (j.kind === "refund_apply") {                                                                   // 2e-3-2-1b ⓖ-6 · 이견 2 · sandbox 2-a · 걸음 25 — 0 원 Payment(Expense 줄 + CreditMemo 줄마다 · 몸은 DB qbo_refund_apply_body 그대로): 가드 = GET purchase(있음 · Voided 아님 · 이 환불의 메모 · TotalAmt ≥ Expense 줄) ∧ CreditMemo 마다 RemainingCredit ≥ 몫 → POST payment → donePayment(TotalAmt 0 · UnappliedAmt 0 · [1b2] openBalanceNote — txnOpenBalance 는 잇기 직전 값 · after = before − Amount 로 경고)
      const key = paymentKeyOf(j.lookup, j.body); nameSent = key;
      const lines = j.check_lines ?? [], exL = lines.filter((cl) => cl.txn_type === "Expense"), cmL = lines.filter((cl) => cl.txn_type === "CreditMemo");
      if (exL.length !== 1 || cmL.length === 0 || lines.length !== exL.length + cmL.length) return await fail(`not sent — the job carries ${lines.length} check line(s) instead of one expense and at least one credit memo — nothing was written; retry it after checking the refund`, null);
      const ex = exL[0], pid = String(ex.qbo_purchase_id ?? ""), label = String(ex.refund ?? j.name);
      if (!pid) return await fail("not sent — no QuickBooks expense id on the check line — nothing was written; retry it after checking the refund", null);
      const rdP = await readTxn(c, pid, j, entityKeyOf("refund"));
      if (rdP.r.error || !rdP.row) return await fail(`not sent — could not read the expense of refund ${label} (QuickBooks #${pid}) before sending: ${rdP.r.error ?? "no row"} — nothing was written`, rdP.r.tid);
      if (isVoidedPurchase(rdP.row)) return await fail(`not sent — the expense of refund ${label} (QuickBooks #${pid}) is voided in QuickBooks — check by hand, then retry or skip`, rdP.r.tid);
      const expectNote = "IMS refund " + j.ims_id;
      if (String(rdP.row.PrivateNote ?? "") !== expectNote) return await fail(`not sent — QuickBooks expense #${pid} does not carry the note of refund ${label} ("${expectNote}") — check by hand, then retry or skip`, rdP.r.tid);
      const tot = num(rdP.row.TotalAmt);
      if (tot === null || tot + 0.004 < Number(ex.amount)) return await fail(`not sent — QuickBooks expense #${pid} of refund ${label} totals ${tot ?? "nothing"} (less than ${ex.amount}) — check by hand, then retry or skip`, rdP.r.tid);
      for (const cc of cmL) {
        const rdC = await readTxn(c, String(cc.qbo_creditmemo_id), j, entityKeyOf("credit"));
        if (rdC.r.error || !rdC.row) return await fail(`not sent — could not read credit memo ${cc.credit_number} (QuickBooks #${cc.qbo_creditmemo_id}) before sending: ${rdC.r.error ?? "no row"} — nothing was written`, rdC.r.tid);
        const rem = num(rdC.row.RemainingCredit);
        if (rem === null) return await fail(`not sent — credit memo ${cc.credit_number} (QuickBooks #${cc.qbo_creditmemo_id}) has no RemainingCredit in QuickBooks (voided?) — check by hand, then retry or skip`, rdC.r.tid);
        if (rem + 0.004 < Number(cc.amount)) return await fail(`not sent — QuickBooks shows only ${rem} left on credit memo ${cc.credit_number} (less than ${cc.amount}) — applied or refunded in QuickBooks already? check before sending, then retry or skip`, rdC.r.tid);
      }
      const { r } = await attempt(j.body, j.request_id);
      const cls = classifyWrite(r.status, r.networkError);
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the created Payment — checked by date, customer, amount 0 and note at the next send`, r.tid, key);
        note = openBalanceNote(row).note;                                                                  // [1b2] 잇기 직전 값 → after 계산 · 경고는 도우미가
        const d = await donePayment(c, j.job_id, row, j.name, r.tid, note);
        return { ...base, name: j.name, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), note, mismatch: (d?.mismatch as string | null) ?? null, link_error: (d?.link_error as string | null) ?? null };
      }
      if (cls === "fail") return await fail(r.error ?? ("HTTP " + r.status), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, key);
    }
    if (j.kind === "refund_void") {                                                                    // 2e-3-2-1b ⓖ-7 · 이견 1 · 4 · 5 · sandbox 2-d — Purchase Full update void 꼴: GET → (이미 Voided 면 done) · LinkedTxn Payment 남아 있으면 failed · 줄 0 이면 failed → DB 머리 + Id + 읽은 SyncToken + 읽은 Line(Amount 0) + 「Voided - 」 메모 → POST purchase(operation 없음 · assertWriteAllowed 가 몸을 본다) · 5010 → 다시 읽어 -2 · done = 금액 0 ∧ Voided 메모(status 가 있고 Voided 가 아니면 failed · 없으면 note)
      const id = String(j.qbo_id ?? j.body.Id ?? ""); nameSent = id;
      if (!id) return await fail("not sent — no QuickBooks expense id on the void job", null);
      const doneVoid = async (row: Record<string, unknown>, tid: string | null, n: string | null) => {
        const d = await c.d.rpcService("qbo_job_done", { p_job: j.job_id, p_qbo_id: String(row.Id), p_qbo_name: String(row.DocNumber ?? j.name), p_sync_token: row.SyncToken != null ? String(row.SyncToken) : null, p_intuit_tid: tid, p_note: n, p_sku: null }) as Record<string, unknown>;
        return { ...base, name: j.name, state: String(d?.state ?? "sent"), qbo_id: String(row.Id), note: n, link_error: (d?.link_error as string | null) ?? null };
      };
      const voidBodyOf = (row: Record<string, unknown>): Record<string, unknown> | string => {
        const linked = (Array.isArray(row.LinkedTxn) ? row.LinkedTxn as Record<string, unknown>[] : []).filter((t) => String(t?.TxnType ?? "") === "Payment");
        if (linked.length) return `the zero payment #${linked.map((t) => String(t.TxnId ?? "?")).join(", ")} is still linked to expense #${id} — void it first`;   // 이견 4
        const lines = (Array.isArray(row.Line) ? row.Line as unknown[] : []).filter((x) => x && typeof x === "object") as Record<string, unknown>[];
        if (lines.length === 0) return `expense #${id} has no lines in QuickBooks — check by hand`;
        const noteDb = String(j.body.PrivateNote ?? "");
        return { ...j.body, Id: id, SyncToken: String(row.SyncToken ?? ""), PrivateNote: noteDb.startsWith(VOIDED_NOTE_PREFIX) ? noteDb : VOIDED_NOTE_PREFIX + (noteDb || "IMS refund " + j.ims_id), Line: lines.map((x) => ({ ...x, Amount: 0 })) };
      };
      let rd = await readTxn(c, id, j, e);
      if (rd.r.error || !rd.row) return await fail(`not sent — expense #${id} could not be read before voiding: ${rd.r.error ?? "no row"} — nothing was written`, rd.r.tid);
      if (isVoidedPurchase(rd.row)) return await doneVoid(rd.row, rd.r.tid, "already voided in QuickBooks (amount 0 · Voided note) — recorded, not sent again");
      let vb = voidBodyOf(rd.row);
      if (typeof vb === "string") return await fail("not sent — " + vb, rd.r.tid);
      note = "SyncToken and lines read from QuickBooks before voiding";
      let { r } = await attempt(vb, j.request_id);
      let cls = classifyWrite(r.status, r.networkError);
      if (cls === "fail" && faultCode(r.body) === STALE_OBJECT_CODE) {
        rd = await readTxn(c, id, j, e);
        if (rd.r.error || !rd.row) return await fail((r.error ?? "stale SyncToken") + " — and the expense could not be re-read: " + (rd.r.error ?? "no row"), rd.r.tid);
        if (isVoidedPurchase(rd.row)) return await doneVoid(rd.row, rd.r.tid, `stale SyncToken (${STALE_OBJECT_CODE}) — re-read: already voided in QuickBooks`);
        vb = voidBodyOf(rd.row);
        if (typeof vb === "string") return await fail("not sent — " + vb, rd.r.tid);
        note = `stale SyncToken (${STALE_OBJECT_CODE}) — re-read and voided again`;
        ({ r } = await attempt(vb, (j.request_id + "-2").slice(0, REQUESTID_MAX)));
        cls = classifyWrite(r.status, r.networkError);
      }
      if (cls === "ok") {
        const row = rowOf(r.body, e.key);
        if (!row) return await unknown(`QuickBooks answered ${r.status} without the voided Purchase — checked by id at the next send`, r.tid, id);
        const st = row.status === undefined || row.status === null ? null : String(row.status);
        if (!isVoidedPurchase(row)) return await fail(`QuickBooks answered ${r.status} but expense #${id} is not voided (TotalAmt ${String(row.TotalAmt ?? "?")} · note "${String(row.PrivateNote ?? "").slice(0, 40)}"${st !== null ? ` · status ${st}` : ""}) — check by hand, then retry`, r.tid);
        if (st !== null && st !== "Voided") return await fail(`QuickBooks answered status "${st}" instead of Voided for expense #${id} (amount 0 and the Voided note are on file) — check by hand, then retry`, r.tid);
        if (st === null) note = note + " · no status in the answer — amount 0 and the Voided note are on file";
        return await doneVoid(row, r.tid, note);
      }
      if (cls === "fail") return await fail((note ? note + " · " : "") + (r.error ?? ("HTTP " + r.status)), r.tid);
      return await unknown(r.error ?? ("no answer (HTTP " + r.status + ")"), r.tid, id);
    }
    if (j.kind === "invoice_void" || j.kind === "credit_void" || j.kind === "opening_credit_void") {    // 2b2 · [2c1 credit_void · 963] · [2e-3-1b opening_credit_void — creditmemo?operation=void 같은 길] — void: Id · SyncToken(없으면 읽는다) · 5010 이면 읽어서 한 번 더 · 거부는 failed(사람)
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
// 2e-1c send { kinds } — SEND_KINDS 의 부분집합(중복 접음) · 없으면 DEFAULT_SEND_KINDS(3-3: cost_day 뺀 18 — cron 61 · console 의 옛 호출 · [4-4] 공급처 셋도 뺀 18 그대로) · 빈 배열 · 배열 아님 · 모르는 값은 400(bill_delete_manual 도 — EF 는 모른다 · 1126)
export function kindsOf(raw: unknown): string[] {
  if (raw === undefined || raw === null) return [...DEFAULT_SEND_KINDS];
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
  const kinds = kindsOf(body.kinds);                                                                 // 2e-1c: 없으면 DEFAULT_SEND_KINDS(옛 동작 · [3-3] cost_day 는 명시할 때만) · cron 62 는 열둘
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
// ── qbo-sync-2e-1d-2(2026-11-06 · deferred 452 · DB 1d-1 20261105184613 · 지시서 ~/asung/prompts/qbo-sync-2e-1d-2.md · 이견 답 1 · 2 · 4 · 5 · 6 A · 7 ~ 16) — 이월 인보이스 QBO 짝 · 읽기만(apiCall · QBO 에 쓰지 않는다) · 창구는 사용자 JWT(rpcUser · service_role 없음) · 열쇠 qbo(KEY_ACTIONS · 북키퍼도)
//    opening_candidates { invoice_numbers?, batch? } — qbo_opening_list(JWT) 의 match none 번호(화면이 준 번호는 교집합만 · 나머지 ignored) → 묶음마다 select … from Invoice where DocNumber in (…) MAXRESULTS 1000 → 일곱 칸으로 줄여 qbo_opening_candidates(p_doc_numbers, p_rows)
//      묶음 실패(intuit_failed · too_many_rows(행 ≥ 1000 — 덜 준 것일 수 있어 RPC 안 부름) · db_failed(기록 한 줄 ok=false http_status null)) 는 그 묶음만 · 다음 묶음은 간다 · 예산 60 s 넘으면 남은 번호 not_run · 응답은 늘 200 · batches_failed 로 본다 · 멱등(다시 돌리면 된다)
//    opening_read { qbo_id, invoice_id, ack?, peek? } — GET invoice/<Id> → 일곱 칸(CustomerRef 는 {value} 객체 — DB qbo_opening_slim 이 ->'CustomerRef'->>'value' 로 읽는다) → peek 면 행만(쓰기 0) · 아니면 qbo_opening_match(JWT) · 경고 + ack 없음은 DB 거부 글 그대로 422 · Fault 610 · 404 는 404
//    opening_search { doc_like } — 글자 · 숫자 · 공백 · - 3 ~ 30 자 → DocNumber like '%…%' MAXRESULTS 20 → 줄인 행(not_found 장의 사람 짝 — 「2329611 | ITRA6260-1」 꼴)
//    응답 · 기록 어디에도 손님 이름 · 주소 · 이메일 없음(CustomerRef.name · BillAddr · Line · CustomerMemo 는 줄이기에서 빠진다 · 기록 q 는 리터럴 → ?) ──
export const OPENING_FIELDS = "Id, SyncToken, DocNumber, TxnDate, TotalAmt, Balance, CustomerRef";
export const OPENING_BATCH_DEFAULT = 150, OPENING_BATCH_MAX = 150;                                  // 이견 2 · 3: 상한은 QUERY_MAX_CHARS 2000(머리 ≈ 120 자 + 7 자리 번호 11 자 × 150 ≈ 1,770) · 기본값 = 상한 — IMS 메인 실측(2026-11-06 · begin → rollback · 꾸민 행 전부 짝 = 가장 무거운 길): 50 장 58 ms · 100 장 108 ms · 150 장 262 ms(빈 rows 는 15 · 21 · 34 ms) — REST 8 s 의 1/30 · 310 장 = 묶음 3 · Intuit IN 150 개가 거부되면 그 묶음만 실패 · 몸의 batch 로 줄인다(이견 16)
export const OPENING_BUDGET_MS = 60_000;                                                            // 이견 10: 묶음 시작 전 예산 · 남은 번호는 not_run
export const OPENING_SEARCH_MAX = 20, OPENING_SEARCH_RE = /^[A-Za-z0-9 -]{3,30}$/;                   // 이견 6 A
export const OPENING_REASONS = ["not_found", "many", "unlinked", "customer", "total", "balance", "docnumber", "taken"] as const;   // qbo_opening_review.reason(DB) — 응답 reasons 의 열쇠
export const openingQueryText = (numbers: readonly string[]): string => `select ${OPENING_FIELDS} from Invoice where DocNumber in (${numbers.map((n) => sqlQuote(n)).join(", ")}) MAXRESULTS ${MAXRESULTS_MAX}`;
export const openingSearchQueryText = (like: string): string => `select ${OPENING_FIELDS} from Invoice where DocNumber like ${sqlQuote("%" + like + "%")} MAXRESULTS ${OPENING_SEARCH_MAX}`;
export type OpeningRow = { Id: string; SyncToken: string | null; DocNumber: string | null; TxnDate: string | null; TotalAmt: number | null; Balance: number | null; CustomerRef: { value: string | null } };
export function openingSlim(raw: unknown): OpeningRow | null {                                     // 일곱 칸만 · 그 밖(Line · BillAddr · BillEmail · CustomerMemo · CustomerRef.name …)은 버린다
  const r = raw && typeof raw === "object" ? raw as Record<string, unknown> : null;
  if (!r || r.Id == null || String(r.Id).trim() === "") return null;
  const str = (v: unknown): string | null => (v == null ? null : String(v).trim() || null);
  const cr = r.CustomerRef && typeof r.CustomerRef === "object" ? (r.CustomerRef as Record<string, unknown>).value : null;
  return { Id: String(r.Id).trim(), SyncToken: str(r.SyncToken), DocNumber: str(r.DocNumber), TxnDate: str(r.TxnDate), TotalAmt: num(r.TotalAmt), Balance: num(r.Balance), CustomerRef: { value: str(cr) } };
}
type OpeningBatch = { batch: number; numbers: number; status: "ok" | "intuit_failed" | "too_many_rows" | "db_failed"; intuit_tid: string | null; error: string | null; qbo_rows: number; matched: number; taken: number; already: number; review_changed: number; review_same: number; unknown_numbers: number };
const cnt = (v: unknown): number => (typeof v === "number" && Number.isFinite(v) ? v : 0);
async function openingCandidates(c: Ctx, body: Record<string, unknown>, jwt: string): Promise<Response> {
  const batch = body.batch === undefined || body.batch === null || body.batch === "" ? OPENING_BATCH_DEFAULT : Number(body.batch);
  if (!(Number.isInteger(batch) && batch >= 1 && batch <= OPENING_BATCH_MAX)) throw new QboError(400, `batch must be a whole number 1 … ${OPENING_BATCH_MAX} (invoice numbers per QuickBooks query · default ${OPENING_BATCH_DEFAULT})`);
  let only: Set<string> | null = null;
  if (body.invoice_numbers !== undefined && body.invoice_numbers !== null) {
    const a = body.invoice_numbers;
    if (!Array.isArray(a) || a.length === 0 || !a.every((x) => typeof x === "string" && x.trim())) throw new QboError(400, "invoice_numbers must be a non-empty array of IMS invoice numbers (strings) — or leave it out to check every unmatched carried-over invoice");
    only = new Set((a as string[]).map((x) => x.trim()));
  }
  const list = await c.d.rpcUser("qbo_opening_list", {}, jwt) as { rows?: { invoice_number?: unknown; match?: unknown }[] } | null;   // 이견 1: 번호는 DB 에서 · 이름(store_name · bill_to_name)은 여기서 버린다
  const open: string[] = [];
  for (const x of Array.isArray(list?.rows) ? list!.rows! : []) { const n = String(x?.invoice_number ?? "").trim(); if (n && x?.match === "none" && !open.includes(n)) open.push(n); }
  const asked = only ? open.filter((n) => only!.has(n)) : open;
  const ignored = only ? [...only].filter((n) => !open.includes(n)) : [];
  const t0 = c.d.now();
  const batches: OpeningBatch[] = [], rows: unknown[] = [], missing: string[] = [];
  const reasons: Record<string, number> = Object.fromEntries(OPENING_REASONS.map((k) => [k, 0]));
  let notRun = 0, numbersFailed = 0;
  for (let i = 0; i < asked.length; i += batch) {
    const nums = asked.slice(i, i + batch), n = Math.floor(i / batch) + 1;
    if (c.d.now() - t0 > OPENING_BUDGET_MS) { notRun += nums.length; continue; }
    const p = parseQuery(openingQueryText(nums));
    const qrowsOf = (r: IntuitResult): unknown[] => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return Array.isArray(qr.Invoice) ? qr.Invoice as unknown[] : []; };
    const detailOf = (r: IntuitResult): Record<string, unknown> => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return { batch: n, numbers: nums.length, rows: qrowsOf(r).length, totalCount: typeof qr.totalCount === "number" ? qr.totalCount : null, q: queryForLog(p.text), bytes: r.bytes }; };
    const { h, r } = await withAuthRetry(c, (x) => apiCall(c, "opening_candidates", x, `/v3/company/${encodeURIComponent(x.realm)}/query`, { query: p.text }, detailOf));
    const b: OpeningBatch = { batch: n, numbers: nums.length, status: "ok", intuit_tid: r.tid, error: null, qbo_rows: 0, matched: 0, taken: 0, already: 0, review_changed: 0, review_same: 0, unknown_numbers: 0 };
    batches.push(b);
    if (r.error || r.bytes > RESPONSE_MAX_BYTES) { b.status = "intuit_failed"; b.error = readFailure("opening_candidates", r).message; numbersFailed += nums.length; continue; }
    const qrows = qrowsOf(r);
    b.qbo_rows = qrows.length;
    if (qrows.length >= p.maxResults) {                                                            // 이견 9: 쪽이 찼다 — 안 온 번호를 「QBO 에 없음」 으로 적게 된다 · RPC 안 부름
      b.status = "too_many_rows"; b.error = `QuickBooks returned ${qrows.length} invoices for ${nums.length} numbers — the page is full, so numbers it did not return cannot be told from missing ones — call again with a smaller batch`; numbersFailed += nums.length; continue;
    }
    const slim = qrows.map(openingSlim).filter((x): x is OpeningRow => x !== null);
    const seen = new Set(slim.map((x) => x.DocNumber));
    let res: Record<string, unknown>;
    try { res = await c.d.rpcUser("qbo_opening_candidates", { p_doc_numbers: nums, p_rows: slim }, jwt) as Record<string, unknown>; }
    catch (e) {
      if (!(e instanceof RpcError) || e.status === 401) throw e;
      b.status = "db_failed"; b.error = e.message; numbersFailed += nums.length;                      // 이견 7: company_name 선례 — DB 실패도 기록 한 줄(http_status null)
      await c.d.log({ env: c.env, realm_id: h.realm, action: "opening_candidates", ok: false, http_status: null, intuit_tid: null, error: e.message.slice(0, 400), by_staff: c.byStaff, ms: 0, detail: { batch: n, numbers: nums.length, rows: slim.length, db: true } });
      continue;
    }
    for (const x of nums) if (!seen.has(x)) missing.push(x);
    b.matched = cnt(res?.matched); b.taken = cnt(res?.taken); b.already = cnt(res?.already); b.review_changed = cnt(res?.review_changed); b.review_same = cnt(res?.review_same); b.unknown_numbers = cnt(res?.unknown_numbers);
    for (const x of Array.isArray(res?.rows) ? res.rows as Record<string, unknown>[] : []) {
      rows.push(x);
      const k = x?.result === "taken" ? "taken" : x?.result === "review" && typeof x.reason === "string" ? x.reason : null;
      if (k) reasons[k] = (reasons[k] ?? 0) + 1;
    }
  }
  const sum = (k: keyof OpeningBatch): number => batches.reduce((a, b) => a + (typeof b[k] === "number" ? b[k] as number : 0), 0);
  const failed = batches.filter((b) => b.status !== "ok").length;
  return jsonCompact(200, { ok: true, asked: asked.length, open: open.length, ignored, not_run: notRun, batch, batches,
    totals: { batches: batches.length, batches_failed: failed, numbers_failed: numbersFailed, qbo_rows: sum("qbo_rows"), qbo_missing: missing.length, matched: sum("matched"), taken: sum("taken"), already: sum("already"), review_changed: sum("review_changed"), review_same: sum("review_same"), unknown_numbers: sum("unknown_numbers") },
    reasons, missing_numbers: missing, rows, ms: c.d.now() - t0 });
}
async function openingRead(c: Ctx, body: Record<string, unknown>, jwt: string): Promise<Response> {
  const peek = body.peek === true;
  const qboId = String(body.qbo_id ?? "").trim();
  if (!/^[0-9]{1,20}$/.test(qboId)) throw new QboError(400, "qbo_id must be a number (the QuickBooks Id of the Invoice)");
  const invoiceId = String(body.invoice_id ?? "").trim();
  if (!peek && !UUID_RE.test(invoiceId)) throw new QboError(400, "invoice_id must be the IMS invoice id (uuid) — or pass peek: true to only read the QuickBooks invoice");
  if (body.ack !== undefined && body.ack !== null && typeof body.ack !== "boolean") throw new QboError(400, "ack must be true or false");
  const detailOf = (r: IntuitResult): Record<string, unknown> => ({ entity: "Invoice", id: qboId, rows: rowOf(r.body, "Invoice") ? 1 : 0, peek, bytes: r.bytes });
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "opening_read", h, readPath("Invoice", h.realm, qboId), {}, detailOf));
  if (r.error && r.bytes <= RESPONSE_MAX_BYTES && (faultCode(r.body) === "610" || r.status === 404)) throw new QboError(404, `QuickBooks has no Invoice #${qboId} — check the Id`);   // 이견 11
  if (r.error || r.bytes > RESPONSE_MAX_BYTES) throw readFailure("opening_read", r);
  const row = openingSlim(rowOf(r.body, "Invoice"));
  if (!row) throw new QboError(502, `QuickBooks answered without an Invoice row for #${qboId}`);
  if (peek) return jsonCompact(200, { ok: true, peek: true, qbo_id: qboId, row, intuit_tid: r.tid });                  // 이견 5: 쓰기 0
  const res = await c.d.rpcUser("qbo_opening_match", { p_invoice_id: invoiceId, p_qbo_id: qboId, p_row: row, p_ack: body.ack === true }, jwt) as Record<string, unknown>;   // DB 거부(경고 + ack 없음 · 이미 섬 · 남이 쥠)는 RpcError → handle 이 422 + 글 그대로
  return jsonCompact(200, { ok: true, peek: false, qbo_id: qboId, invoice_id: invoiceId, row, intuit_tid: r.tid, ...(res && typeof res === "object" ? res : {}) });
}
async function openingSearch(c: Ctx, body: Record<string, unknown>): Promise<Response> {
  const like = String(body.doc_like ?? "").trim();
  if (!OPENING_SEARCH_RE.test(like)) throw new QboError(400, "doc_like must be 3 … 30 letters, digits, spaces or dashes — part of the QuickBooks invoice number");
  const p = parseQuery(openingSearchQueryText(like));
  const qrowsOf = (r: IntuitResult): unknown[] => { const qr = ((r.body as Record<string, unknown>)?.QueryResponse ?? {}) as Record<string, unknown>; return Array.isArray(qr.Invoice) ? qr.Invoice as unknown[] : []; };
  const detailOf = (r: IntuitResult): Record<string, unknown> => ({ entity: "Invoice", rows: qrowsOf(r).length, q: queryForLog(p.text), bytes: r.bytes });
  const { r } = await withAuthRetry(c, (h) => apiCall(c, "opening_search", h, `/v3/company/${encodeURIComponent(h.realm)}/query`, { query: p.text }, detailOf));
  if (r.error || r.bytes > RESPONSE_MAX_BYTES) throw readFailure("opening_search", r);
  const rows = qrowsOf(r).map(openingSlim).filter((x): x is OpeningRow => x !== null);
  return jsonCompact(200, { ok: true, doc_like: like, rows, count: rows.length, more: rows.length >= OPENING_SEARCH_MAX, intuit_tid: r.tid });
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
    if (action === "opening_candidates") return await openingCandidates(c, body, jwt);                 // 2e-1d-2 — 창구는 그 사람 JWT
    if (action === "opening_read") return await openingRead(c, body, jwt);
    if (action === "opening_search") return await openingSearch(c, body);
    return json(400, { ok: false, error: "unknown action" });
  } catch (e) {
    if (e instanceof QboError) return json(e.status, { ok: false, error: sc(c, e.message) });
    if (e instanceof RpcError) return json(e.status === 401 ? 401 : 422, { ok: false, error: sc(c, e.status === 401 ? "Invalid session — sign in again" : e.message) });
    const msg = sc(c, String((e as Error)?.message ?? e)).slice(0, 400);
    d.warn("qbo failed: " + msg);
    return json(500, { ok: false, error: msg });
  }
}
