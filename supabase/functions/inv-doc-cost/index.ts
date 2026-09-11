// ============================================================
// ASUNG 재고 원장 — Edge Function: inv-doc-cost (2026-09-10)
//   Cin7 트랜스퍼 운송비(stockTransfer.ManualJournals · ~~IsSystem=false · Debit='_59_'~~ → [정정 2026-09-10] Debit='_59_' AND Credit='_136_') → inv_doc_cost
//   ⭐ 문서 단위 금액을 **읽어서 upsert 만** 한다. 배분하지 않는다(아래 「하지 않는 것」).
//   스키마: 20260910141553_inv_doc_cost_transfer_freight.sql · 설계: docs/design/ledger-design.md §원가 레이어
//   「트랜스퍼 운송비 — 배분까지 완료 · 수집기는 미착수」 소절 · 방향 정본: docs/design/ims-principles.md
// ------------------------------------------------------------
// ═══ 왜 별도 EF 인가 (Caleb 판정 2026-09-10) — inv-cost 확장이 아니다 ═══
//  1. 대상 표가 다르다 — inv-cost 는 inv_cost, 이 EF 는 inv_doc_cost. 같은 EF 에 두면 한 함수가 두 표를 관리한다.
//  2. ⚠️ 커서 시계가 다르다 — 발주와 트랜스퍼의 LastModifiedOn 이 독립적으로 움직인다. 하나로 묶으면 **어느 쪽 때문에
//     커서가 멈췄나**를 못 가린다. ⇒ inv_sync_state.source_key = 'cost_transfer' ('cost' 와 독립).
//  3. ⚠️ inv-cost 는 입력 축이 purchaseList 하나로 박혀 있다 — doc_type 이 buildCostRows 의 rows.push 에 "purchase"
//     리터럴이고 DocMode 타입이 두 값으로 좁아 분기 셋을 고쳐야 한다 [보고 2026-09-10 · /tmp/inv-cost-report.md].
//
// ═══ 무엇을 하나 ═══
//  ① stockTransferList 순회(Status=COMPLETED) → ② 후보 문서 상세(stockTransfer?TaskID=) → ③ ManualJournals 에서
//  ~~IsSystem=false · Debit='_59_'~~ → [정정 2026-09-10] Debit='_59_' AND Credit='_136_' 만 추출 → ④ inv_doc_cost upsert(on_conflict = inv_doc_cost_uq).
//
// ═══ ⚠️⚠️ 커서 축은 LastModifiedOn 이다 — CompletionDate 로 잡으면 놓친다 ═══
//  [실측 2026-09-10] TR-04175 는 Completion 09-02 인데 저널이 **09-10 에 붙었다**(LastModifiedOn = 2026-09-10T15:32:06.049Z).
//  완료일 커서는 이미 지나가 있다. 저널 날짜(도착 +1~2일)와 문서 갱신 시점은 다른 시계다.
//  [실측 2026-08-31 · inv-collect] stockTransferList 행 1000/1000 에 LastModifiedOn 존재 · 빈 값 0.
//  ⬜ 미확인: stockTransferList 에 UpdatedSince 계열 파라미터가 있는지 — cin7-api 스킬(references/stock.md)의 문서화된
//     파라미터는 Page·Limit·Status·Search 넷뿐이고 inv-collect 도 transfer 를 전량 순회(②-a)한다. ⇒ **전체 순회 후 코드에서
//     LastModifiedOn 으로 거른다**(미확인 파라미터를 보내지 않는다 — 조용히 무시되면 전량이고 400 이면 회차가 죽는다).
//     [실측 2026-09-09] Search 는 문서번호로 안 걸린다 · 목록은 최근순이 아니다(TR-03975 가 6페이지) ⇒ 정렬에 기대지 않는다.
//  커서 형식·판정은 inv-cost 관례 복제: <LastModifiedOn>|<Number> tie-breaker(동일 타임스탬프 다건 · 2026-08-31 결함 C) ·
//  비캡 회차 = 회차 시작 시각 · 캡 회차 = 마지막 처리 문서의 키 · cursorStalled 증상 가드가 commit 을 차단한다.
//  ⚠️ 전량 목록이라 「정밀도 필터」가 곧 증분 필터다 — 키 < 커서 인 문서를 코드에서 거른다(inv-cost 의 UpdatedSince −1일 +
//  정밀도 필터와 같은 결과 · 서버 창이 없을 뿐). ?from_since 는 커서 없을 때의 첫 시딩 하한 · ?recheck_since 는
//  커서 아래를 다시 태운다(커서는 뒤로 가지 않는다 · 캡이면 제자리).
//
// ═══ ⚠️⚠️ from_since · recheck_since 는 **시각**을 받는다 (2026-09-10 정정) ═══
//  커서 축이 LastModifiedOn **시각**(밀리초)인데 두 하한이 날짜(YYYY-MM-DD)만 받았다 — 하루 안에 문서가 많으면 캡 안에서 특정 문서에
//  닿을 수 없다. [실사고 2026-09-10] TR-03975(LastModifiedOn 2026-08-26T20:51:06.373Z)를 ?from_since=2026-08-26 으로 태우려 했으나
//  그날 후보 395건이 38건 캡(time)에 걸려 들어오지 않았다 — 「봤는데 저널이 없다」가 아니라 **아예 못 봤다**(docs_processed 0 의 원인은
//  파싱 결함이 아니라 도달 실패). 종전 필터는 updated.slice(0,10) 으로 날짜 10자만 비교해 시각을 넘겨도 무시했다.
//  ⇒ 두 파라미터 모두 YYYY-MM-DD(그날 T00:00:00.000Z) · YYYY-MM-DDTHH:MM · …:SS · …:SS.mmmZ 를 받아 **커서와 같은 축(정규화 ISO)** 으로
//  비교한다. 파싱 실패는 400(조용히 날짜로 떨어지지 않는다). 응답 키 lmo_floor_date → **lmo_floor**(실제 적용된 하한 값 그대로) —
//  이 EF 는 아직 아무 곳에서도 호출되지 않아(cron 미등록 · GAS 없음) 키 변경이 안전하다.
//
// ═══ ⚠️⚠️ LastModifiedOn 밀리초 자릿수가 일정하지 않다 — 비교 전에 정규화한다 (2026-09-10) ═══
//  [실측 2026-09-10] TR-03975 …:06.373Z (3자리) · TR-04214 …:06.4Z (1자리). [실측 테스트 DB inv_doc_state · transfer 349건]
//  ms3 209 · ms2 129 · ms1 10 · 소수부 없음 1 — 끝의 0 을 잘라낸 형식이다(예 .09Z · .76Z).
//  ⚠️ 원문 그대로 코드유닛 비교하면 순서가 뒤집힌다: 한 소수부가 다른 것의 접두면(".3Z" vs ".373Z" · ":06Z" vs ":06.4Z") 'Z'(0x5A) 가
//  숫자·'.' 보다 커서 **짧은 쪽이 뒤로** 간다 — 300ms 가 373ms 뒤, 0ms 가 400ms 뒤. 커서 키가 ".3Z|TR-a" 일 때 ".373Z|TR-b" 는
//  키 < 커서 로 판정돼 **건너뛴다** — 감지되지 않는 유실(어느 카운터에도 안 나타난다 · LastModifiedOn 은 그 문서의 유일한 등장 기회).
//  ⇒ normLmo(): 소수부를 3자리로 패딩(없으면 .000)하고 Z 를 붙인 뒤에만 키를 만들고 비교한다. 정렬·하한·커서 판정 **세 곳이 전부**
//  정규화된 값을 쓴다(runStartIso 는 toISOString 이라 이미 같은 형식). Date.parse 가 아니라 문자열 패딩인 이유 — inv-cost 관례
//  「절대 시각으로 파싱하지 않는다 · 코드유닛 비교」와 tie-breaker(동일 타임스탬프 다건 · <LMO>|<Number>)를 그대로 유지한다.
//  예상 밖 형식(정규식 불일치)은 원문 유지 + lmo_unnormalized 카운트(0 이 아니면 신호). 기존 저장 커서와의 호환은 문제 없다 — 배포 전이다.
//
// ═══ 진단 — skip 된 문서번호를 남긴다 (2026-09-10 · 정식 응답 필드) ═══
//  dispositions 는 개수만 세어 「어느 문서가 왜 빠졌나」를 모른다. [실사고 2026-09-10] TR-04175(LastModifiedOn 15:32 · ManualJournals ARRAY(1) ·
//  ~~IsSystem=false~~ · 249.33 — GAS 프로브 실측)를 하한 00:00 으로 태웠는데 커서가 15:41 까지 갔음에도 kept 0 · skip_no_journal 39 —
//  그 문서가 후보에 없는지 · 캡 밖인지 · 저널을 못 읽는지 구분할 수 없었다. [정정 2026-09-10] 최종 원인은 아래 「IsSystem 은 존재하지 않는 필드」.
//  ⇒ skipped_docs = 상세를 본 문서 중 processed 가 아닌 것의 {doc_number, disposition, mj_len}(최대 50 · mj_len = det.ManualJournals 배열 길이 ·
//     초과분은 skipped_docs_truncated 로 센다) · candidate_head = 커서 필터 뒤 후보 정렬 앞 10건의 {doc_number, key} — 특정 문서가 후보에 있는지 ·
//     몇 번째인지 바로 보인다(캡 안/밖 판별).
//
// ═══ ⚠️⚠️ 문서 필터 — ~~From <> To (GUID) 로 건다 · 이름으로 걸면 안 된다~~ → [정정 2026-09-10 저녁 · 운영 실측] 현재 필터는 창고간 이동을 좁히지 못한다 ═══
//  ~~FromLocation/ToLocation 은 「창고: bin」 형태라 bin 트랜스퍼가 섞인다. [실측 2026-09-09] 이름 필터 784건 vs GUID 12건.~~
//  ~~GUID 를 하드코딩하지 않는다 — From <> To 가 더 일반적이고 창고가 늘어도 돈다. 같으면 skip_same_location.~~
//  ⚠️⚠️ [실측 2026-09-10 · 운영 dry · from_since=2026-08-20T00:00:00Z] list_total 4,680 · below_floor 4,122 · **candidates 558**.
//    원인: **bin 마다 LocationID(GUID)가 따로 있다** — 같은 창고 안 bin 이동도 From <> To 가 성립해 skip_same_location 에 안 걸린다.
//    [실측] TR-03979 = 「Asung Trading Inc.: B030101」(2e2dc073…) → 「Asung Trading Inc.: B030303」(8fb43878…) — 같은 창고인데 GUID 가 다르다.
//    ⇒ 회차당 40건 캡에서 39건이 bin 트랜스퍼 상세 조회로 소모된다(dispositions {skip_no_journal: 39, processed: 1}).
//    ⚠️ 09-09 의 「784 vs 12」가 무엇을 센 것인지는 모른다 — 구간·기준 불명. 지우지 않고 오늘 실측을 나란히 둔다.
//  ⭐ 창고간 이동의 실제 모양은 셋이다 [실측 4,680건 전수 · W=콜론 없음(창고) · B=콜론 있음(bin) · CROSS=콜론 앞 창고 이름이 다름]:
//    B->B same 3,280 · W->B same 1,283 · B->W same 11 · W->W same 1(⚠️ TR-01875 토론토→토론토) / W->W CROSS 62 · W->B CROSS 9 · B->B CROSS 34 ⇒ CROSS 합계 105.
//    ⚠️⚠️ 콜론 유무만으로 거르면 43건(9+34)을 놓친다 — 진짜 창고간(TR-03267 「Asung Trading Inc.」→「Asung - Edmonton: EZ010101」 ·
//    TR-02937 「Asung Trading Inc.: J02PALLET08」→「Asung - Edmonton: ED020504」 · 둘 다 InTransitAccount _1150040007_ · DepartureDate 있음).
//    창고 이름은 정확히 둘: 「Asung - Edmonton」 1,264 · 「Asung Trading Inc.」 165 (콜론 없는 이름 집계). 창고 GUID(참고용 · 하드코딩 안 함):
//    Asung Trading Inc. f1ca3946-5a4e-4da7-b68a-ce7d3500f0be · Asung - Edmonton 623edcaa-5f18-4682-aae1-b9016d977c11.
//  ⭐ 정정 방향(Caleb 판정 2026-09-10): 기준은 GUID 가 아니라 **창고 이름** — FromLocation/ToLocation 의 **콜론 앞부분**을 떼어 비교, 다르면 창고간.
//    「이름으로 걸면 안 된다」를 뒤집는 것이 아니라 범위를 좁히는 것 — 이름 전체는 bin 이 섞이지만 콜론 앞은 창고 축이다. GUID 하드코딩은 채택 안 함(창고가 늘면 깨진다).
//    목록 행에 판정 필드가 다 있다(From·FromLocation·To·ToLocation·Status·Number·CompletionDate·DepartureDate·InTransitAccount·CostDistributionType·Reference·SkipOrder·LastModifiedOn) —
//    상세 조회 없이 판정 가능. Limit=1000 이면 전체 5페이지(6페이지는 빈 배열).
//  ✅ **[2026-09-11] 고쳤다** — listDisposition 이 FromLocation/ToLocation 의 콜론 앞 창고 이름을 비교한다(후보 558 → 105 기대).
//     [실측 2026-09-11 · 운영 dry · 배포 후] skip_same_warehouse **4,575**(09-10 GAS 전수 분류 예측과 정확히 일치) · skip_no_location **0**.
//     ⚠️⚠️ 「105」는 **전 기간 창고간 이동 수**다 — 실제 후보에는 하한(기초선 8/20)이 한 번 더 걸린다:
//       4,680 전체 COMPLETED → 105 창고간(전 기간) → **7** 기초선 이후(= 실제 상세 호출 수) → **5** 운송비 있음(TR-03975·03976·04173·04174·04175) · 2 저널 없음(TR-04330·04331).
//       [실측 recheck_since=2026-08-20T00:00:00Z] list_total 4,680 · below_floor 4,122 · skip_same_warehouse 551 · candidates 7 · processed 5 · skip_no_journal 2.
//     ⇒ 회차당 40건 캡에 걸릴 일이 사실상 없다(3주치 7건). cron 등록 2026-09-11 오전(jobid 19 · 45 4 * * * UTC · ?commit=1 · from_since 없음 — 커서가 서 있다).
//     ⭐ 빈 회차에도 커서는 전진한다(비캡 = 회차 시각 · decideCursor): [실측] candidates 0 · docs_processed 0 에서 cursor 2026-09-10T21:07:43.939Z → 2026-09-11T12:15:53.269Z.
//     disposition 이름: **skip_same_warehouse 신설 · skip_same_location 폐기 · skip_no_location 신설**(이름 빈 행 · 0 이 아니면 신호) · skip_not_completed 유지.
//    정본: docs/design/ledger-design.md §원가 레이어 12번 「②-a 수집기 작동 확인」 · docs/sessions/2026-09-10-transfer-freight-ops-notes.md
//  Status 는 COMPLETED 만 본다(목록 Status 파라미터 · 문서화됨) — 저널은 완료 뒤에 붙으므로 좁혀도 놓치지 않는다(실측 둘 다 COMPLETED).
//  서버 필터가 새는 경우를 위해 코드에서도 확인한다(skip_not_completed · 0 이 아니면 신호).
//
// ═══ ⚠️⚠️ ManualJournals 추출 — ~~IsSystem 이 관건 · 배열 길이로 판단하면 틀린다~~ → [정정 2026-09-10] 계정 화이트리스트 둘(Debit · Credit) ═══
//  ~~원소 키 여섯 [실측]: Debit · Credit · Reference · Date · Amount · IsSystem~~
//  ~~  TR-03975  ARRAY(2)  [0] Debit=_1150040007_ · Credit=_59_ · Ref=TR-03975 · 08-26 · 4878.11 · IsSystem=true~~
//  ~~                      [1] Debit=_59_ · Credit=_136_ · Ref=B6900109 · 08-27 · 398.75 · IsSystem=false~~
//  ~~  TR-04175  ARRAY(1)  [0] Debit=_59_ · Credit=_136_ · Ref=B6913286 · 09-04 · 249.33 · IsSystem=false~~
//  ~~· IsSystem=true 는 운송중 계정 이동(_1150040007_ ↔ _59_)이고 금액이 재고 자체(4,878.11) — 담지 않는다.~~
//  ~~· TR-04175 는 시스템 저널이 아예 없어 1행이고 그것이 운송비 · TR-03975 는 2행 중 [1] ⇒ 길이가 아니라 IsSystem 으로.~~
//  ~~· 거르는 조건 둘(AND): IsSystem === false · Debit === '_59_'(재고 계정).~~
//
//  ⚠️⚠️ [정정 2026-09-10 · GAS 프로브 실측 14:40 · TR-03975 · TR-04175 · TR-03976] **IsSystem 은 존재하지 않는 필드다.**
//  응답 전체를 문자열 검색해도 0건이다(세 문서 · 237,148 · 94,981 · 192,365자). ⇒ 종전 `j?.IsSystem === false` 는 `undefined === false` → false 라
//  **전량 걸러졌다** — 다섯 회차 docs_processed 0 의 최종 원인.
//  ⚠️ 위 취소선 기록의 「[0] Debit=_1150040007_ · 4878.11 · IsSystem=true」는 **창작이었다** — `1150040007` 은 저널이 아니라 문서 헤더의
//  `InTransitAccount`("CostDistributionType":"Cost","InTransitAccount":"_1150040007_", …)이고, `4878.11` 은 응답에 없다(세 문서 모두 "4878.11" 포함 false).
//  ⭐ 운송중 계정 이동은 ManualJournals 로 오지 않는다 — Cin7 이 내부에서 처리하고 헤더에 계정 코드만 알려준다. ManualJournals 에는 **운송비만** 온다.
//  [실측] Debit/Credit 을 가진 객체는 중첩 전체에서 root.ManualJournals[0] 하나뿐(세 문서 동일). 세 문서 모두 ARRAY(1):
//    TR-03975 [{"TaskID":"c456b86f-…","ID":"8ea9e56f-…","Reference":"B6900109","Amount":398.75,"Date":"2026-08-27T00:00:00","Debit":"_59_","Credit":"_136_",
//              "ManualJournalsDistributedCosts":[],"vDimensionDefaultValueStockTransferJournals":[],"ValidationText":null,"ValidationState":null}]
//    TR-04175 [{… "Reference":"B6913286","Amount":249.33,"Date":"2026-09-04T00:00:00","Debit":"_59_","Credit":"_136_" …}]
//    TR-03976 [{… "Reference":"B6900109","Amount":229.2,"Date":"2026-08-27T00:00:00","Debit":"_59_","Credit":"_136_" …}]   ← TR-03975 와 같은 인보이스를 나눠 갖는다
//  ⭐ 원소 키 11개: TaskID · ID · Reference · Amount · Date · Debit · Credit · ManualJournalsDistributedCosts · vDimensionDefaultValueStockTransferJournals ·
//     ValidationText · ValidationState.
//  ⇒ ⭐ 거르는 조건: **Debit === '_59_'(재고) AND Credit === '_136_'(Freight-COS)**. ⚠️ 둘 다 화이트리스트 — 블랙리스트는 처음 보는 계정을 조용히
//     통과시킨다. 다른 값이 오면 skip_non_inventory_debit / skip_non_freight_credit 로 세고 warning 에 계정 코드(0 이 아니면 새 계정 신호 · Credit 표본은 3건뿐).
//  ⚠️ 「배열 길이로 판단하면 틀린다」의 근거(2행 vs 1행)도 사라졐다 — 세 문서 모두 1행. ⭐ 그래도 배열이므로 **전량 순회**한다(인보이스가 여러 장 붙으면
//     늘어날 수 있다 · ⬜ 실측 표본 없음). skip_system_only disposition 과 journal_lines.system 카운터는 도달 불가능해져 **제거**했다(항상 0 인 카운터는 신호가 아니다).
//
// ═══ ⚠️ inv_doc_cost 유니크와 null ═══
//  inv_doc_cost_uq = (doc_type, doc_number, kind, ref_number, occurred_on). ⚠️ ref_number 가 null 이면 유니크가 안 걸린다
//  (Postgres null 취급) ⇒ Reference 가 비면 skip_no_reference 로 세고 **넣지 않는다**(넣으면 매 회차 중복이 쌓인다).
//  Amount 0 은 skip_zero_amount(넣지 않는다). ⚠️ 음수는 넣는다 — 정정일 수 있고 배분 단계(inv_layer_apply) 가드가 차단한다
//  (inv_doc_cost 에 amount >= 0 CHECK 를 일부러 안 걸었다). 같은 upsert 페이로드 안에 같은 5키가 두 번이면 PostgREST 가
//  거부하므로("cannot affect row a second time") 합산 1행 + merged_rows 카운트 + 경고 — ⬜ 같은 인보이스가 같은 날 두 줄로
//  오는 경우는 미확인(두 실측 문서 모두 1행)이라 그때 실물로 판단한다.
//  raw = 그 문서의 ManualJournals 배열 **전체**(~~IsSystem=true 포함~~ → 화이트리스트에 걸린 행 포함) + 최소 문서 헤더 — 「왜 이 금액만 골랐나」를 되짚을 수 있게.
//
// ═══ ⚠️⚠️ 하지 않는 것 ═══
//  · inv_layer 를 읽지 않는다 · 배분하지 않는다. 배분은 inv_layer_apply 가 한다(20260910141553). 이유: ① 수집기가 inv_layer 를
//    읽으면 의존 방향이 역전된다(ims-principles: 모듈은 레고처럼 · 접점은 사건 하나) ② 배분 결과가 굳으면 레이어 규칙이 바뀌어도
//    안 바뀐다 = 불변 조건(§3 · 레이어 = inv_ledger + inv_cost + inv_doc_cost + inv_snapshot 으로 전량 재생성) 이 깨진다.
//  · inv_cost 를 건드리지 않는다(inv-cost 의 표) · Cin7 에 쓰지 않는다(GET 만) · 배포·cron 등록은 사람이 한다.
//
// 인증(x-wms-cron-key · fail-closed)·페이싱(1,200ms = 분당 50콜 · 60/60 한도의 여유분 · 키 공유)·캡(회차 40건 · 120초)·
// dry 기본/?commit=1·회차 로그(inv_collect_runs · source_key='cost_transfer' · dry 미기록)는 inv-cost 관례 그대로.
// _shared/cin7.ts 무변(바꾸면 소비 함수 전부 재배포).
import { cin7Get, sleep } from "../_shared/cin7.ts";

const COLLECTOR_VERSION = "inv-doc-cost@2026-09-10.2";   // 10.2 = IsSystem 필터 제거(존재하지 않는 필드 · 전량 걸러졌다) → Debit _59_ AND Credit _136_ 화이트리스트 · 이전 10.1 = 최초(배분 없음)
const LIST_PAGE_LIMIT = 1000;
const MAX_LIST_PAGES = 12;
const LIST_SLEEP_MS = 400;
const DETAIL_SLEEP_MS = 1200;    // 분당 50콜 — 60/60 한도의 여유분(hello·receiving·inv-collect·inv-cost 와 키 공유)
const MAX_DETAIL_PER_RUN = 40;   // 1,200ms × 40 = 48초 < 60초 창 — 회차 캡(문서당 상세 1콜)
const TIME_BUDGET_MS = 120_000;  // 150초 idle timeout 앞에서 먼저 끊는다
const INSERT_BATCH = 500;
const SOURCE_KEY = "cost_transfer";                       // ⚠️ 'cost'(inv-cost) 와 독립 — 커서 시계가 다르다(헤더)
const DOC_CONFLICT = "doc_type,doc_number,kind,ref_number,occurred_on";   // = inv_doc_cost_uq 순서
const INVENTORY_DEBIT = "_59_";                            // 재고 계정 — Debit 화이트리스트(헤더)
const FREIGHT_CREDIT = "_136_";                           // Freight-COS — Credit 화이트리스트(2026-09-10 · 실측 3건 전부 · 다른 값은 세고 거른다)

// ── Supabase REST 헬퍼 (inv-cost 와 같은 형태 — service_role 자동주입) ──
const SB_URL = () => Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY = () => Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
function sbHeaders(extra: Record<string, string> = {}): HeadersInit {
  return { apikey: SB_KEY(), Authorization: "Bearer " + SB_KEY(), "Content-Type": "application/json", ...extra };
}
async function sbGet(path: string): Promise<any[]> {
  const r = await fetch(SB_URL() + "/rest/v1/" + path, { headers: sbHeaders() });
  if (!r.ok) throw new Error("sbGet " + r.status + ": " + (await r.text()).slice(0, 300));
  return await r.json();
}
async function sbUpsert(table: string, conflictCol: string, rows: unknown): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/" + table + "?on_conflict=" + conflictCol, {
    method: "POST",
    headers: sbHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
    body: JSON.stringify(rows),
  });
  if (!r.ok) throw new Error("sbUpsert " + table + " " + r.status + ": " + (await r.text()).slice(0, 400));
}
// inv_doc_cost 쓰기 — ⚠️ upsert(merge-duplicates)다. amount 는 키에 없어 정정이 덮어쓴다(마이그레이션 헤더 A).
//   refreshed_at 을 매 행 명시 — merge 는 payload 에 있는 컬럼만 갱신하므로 DB default 에 맡기면 기존 행이 낡은 채 남는다.
async function writeDocCostRows(rows: Record<string, unknown>[], runIso: string): Promise<number> {
  let written = 0;
  for (let i = 0; i < rows.length; i += INSERT_BATCH) {
    const batch = rows.slice(i, i + INSERT_BATCH).map((r) => ({ ...r, refreshed_at: runIso }));
    await sbUpsert("inv_doc_cost", DOC_CONFLICT, batch);
    written += batch.length;
  }
  return written;
}

// ── 계산 핵심 (pure — scripts/test-invdoccost.mjs 가 이 구간을 원문 추출해 검증한다) ──
const dateOnly = (s: unknown): string | null => {
  const t = String(s ?? "").slice(0, 10);
  return /^\d{4}-\d{2}-\d{2}$/.test(t) ? t : null;
};
const norm = (s: unknown) => String(s ?? "").trim().toUpperCase();
const round6 = (x: number) => Math.round(x * 1e6) / 1e6;

type DocCostRow = {
  doc_type: string; doc_number: string; kind: string; amount: number; occurred_on: string;
  ref_number: string; debit_account: string | null; credit_account: string | null;
  collector: string; raw: Record<string, unknown>;
};
// 저널 행 단위 집계 — 문서 disposition(문서 수)과 단위가 다르다. processed 문서 안에서도 skip 된 행이 보여야 신호가 산다.
//   ~~system~~ 제거(2026-09-10) — IsSystem 필드가 없어 「시스템 저널 수」는 셀 수 없고 항상 0 이 될 카운터였다. 대신 non_freight_credit 신설:
//   Debit 은 맞는데 Credit 이 '_136_' 이 아닌 행(새 비용 계정 신호). 화이트리스트에 걸린 행 수 = non_inventory_debit + non_freight_credit.
type JournalTally = { kept: number; non_inventory_debit: number; non_freight_credit: number; no_reference: number; zero_amount: number; bad_amount: number; no_date: number };
const emptyTally = (): JournalTally => ({ kept: 0, non_inventory_debit: 0, non_freight_credit: 0, no_reference: 0, zero_amount: 0, bad_amount: 0, no_date: 0 });

// 목록 레벨 disposition — 상세 조회 전에 정한다.
// ⚠️⚠️ [정정 2026-09-11] 기준은 GUID 가 아니라 **창고 이름**이다 — FromLocation/ToLocation 의 **콜론 앞부분**(「창고: bin」의 창고 부분)을
//   떼어 비교하고, 다르면 창고간 이동이다. 「이름으로 걸면 안 된다」를 뒤집는 것이 아니라 범위를 좁히는 것 — 이름 **전체**로 걸면
//   bin 트랜스퍼가 섞이지만, **콜론 앞**은 창고 축이다(헤더 「문서 필터」 절 실측 · bin 마다 GUID 가 따로라 From <> To 는 창고를 못 가른다).
//   ~~From/To GUID 비교 · skip_same_location~~ 폐기. 기대값[실측 4,680건]: skip_same_warehouse 4,575 · candidate 105(W→W 62 · W→B 9 · B→B 34).
function listDisposition(row: any): string {
  if (norm(row?.Status) !== "COMPLETED") return "skip_not_completed";   // 서버 Status 필터가 새면 여기서 잡힌다(0 이 아니면 신호)
  const wh = (s: unknown) => String(s ?? "").split(":")[0].trim();      // 「Asung Trading Inc.: B030101」 → 「Asung Trading Inc.」 · 콜론 없으면 그대로
  const f = wh(row?.FromLocation), t = wh(row?.ToLocation);
  if (!f || !t) return "skip_no_location";      // ⚠️ 이름이 없으면 창고간으로 볼 수 없다 — 조용히 버리지 않고 센다(0 이 아니면 신호)
  if (f === t) return "skip_same_warehouse";    // 같은 창고 안(bin↔bin · 창고↔bin 둘 다) — 옛 GUID 기준에서 candidate 로 새던 TR-01875(토론토→토론토)도 여기
  return "candidate";
}

// 문서 하나 → inv_doc_cost 행들. 실패는 문서 단위 격리(다른 문서는 계속).
function buildDocCostRows(input: { docNo: string; det: any; row: any }): {
  rows: DocCostRow[]; disposition: string; warnings: string[]; tally: JournalTally; mergedRows: number;
} {
  const { docNo, det, row } = input;
  const warnings: string[] = [];
  const tally = emptyTally();
  // ManualJournals 는 배열 [실측] — inv-cost 와 같이 {Lines:[…]} 형태도 받아준다(방어)
  const mjArr: any[] = Array.isArray(det?.ManualJournals) ? det.ManualJournals
    : Array.isArray(det?.ManualJournals?.Lines) ? det.ManualJournals.Lines : [];
  const done = (disposition: string, rows: DocCostRow[] = [], mergedRows = 0) => ({ rows, disposition, warnings, tally, mergedRows });
  if (mjArr.length === 0) return done("skip_no_journal");

  // ~~const userRows = mjArr.filter(j => j?.IsSystem === false)~~ [정정 2026-09-10] IsSystem 은 존재하지 않는 필드 — undefined === false 로 전량 걸러졌다(헤더).
  //   ManualJournals 에는 운송비만 오므로 배열 전체를 계정 화이트리스트(Debit · Credit)로 판정한다. 전량 순회 — 인보이스 여러 장이면 늘어날 수 있다.
  const raw = {
    manual_journals: mjArr,                                            // ⭐ 배열 전체(화이트리스트에 걸린 행 포함) — 「왜 이 금액만 골랐나」
    doc: {
      task_id: det?.TaskID ?? row?.TaskID ?? null, status: det?.Status ?? row?.Status ?? null,
      from: row?.From ?? null, to: row?.To ?? null,
      departure_date: det?.DepartureDate ?? row?.DepartureDate ?? null, completion_date: det?.CompletionDate ?? row?.CompletionDate ?? null,
      last_modified_on: row?.LastModifiedOn ?? det?.LastModifiedOn ?? null, cost_distribution_type: row?.CostDistributionType ?? null,
    },
    collector: COLLECTOR_VERSION,
  };
  const rows: DocCostRow[] = [];
  let firstSkip: string | null = null;   // 행이 하나도 안 남았을 때의 문서 disposition — 처음 걸린 사유
  const skipRow = (k: keyof JournalTally, disposition: string) => { tally[k]++; firstSkip ??= disposition; };
  for (const j of mjArr) {
    const debit = String(j?.Debit ?? "").trim(), credit = String(j?.Credit ?? "").trim();
    if (debit !== INVENTORY_DEBIT) {
      // Debit 화이트리스트 밖 — 새 계정이 나타났다는 신호. 조용히 통과시키지 않는다(헤더)
      skipRow("non_inventory_debit", "skip_non_inventory_debit");
      warnings.push(docNo + ": journal with Debit '" + (debit || "(empty)") + "' (Credit '" + credit + "', Ref '" + String(j?.Reference ?? "")
        + "', Amount " + String(j?.Amount) + ") is not the inventory account " + INVENTORY_DEBIT + " - skipped (skip_non_inventory_debit)");
      continue;
    }
    if (credit !== FREIGHT_CREDIT) {
      // Credit 화이트리스트 밖 (2026-09-10) — 실측 3건 전부 _136_(Freight-COS). 다른 값 = 새 비용 계정 신호 · 세고 거른다
      skipRow("non_freight_credit", "skip_non_freight_credit");
      warnings.push(docNo + ": journal with Debit " + INVENTORY_DEBIT + " but Credit '" + (credit || "(empty)") + "' (Ref '" + String(j?.Reference ?? "")
        + "', Amount " + String(j?.Amount) + ") is not the freight account " + FREIGHT_CREDIT + " - skipped (skip_non_freight_credit)");
      continue;
    }
    const ref = String(j?.Reference ?? "").trim();
    if (!ref) {
      // ref_number 는 유니크 키 — null 이면 유니크가 안 걸려 매 회차 중복이 쌓인다(헤더)
      skipRow("no_reference", "skip_no_reference");
      warnings.push(docNo + ": freight journal without Reference (Amount " + String(j?.Amount) + " @ " + String(j?.Date) + ") - skipped (skip_no_reference)");
      continue;
    }
    const amount = Number(j?.Amount);
    if (!Number.isFinite(amount)) { skipRow("bad_amount", "skip_bad_amount"); warnings.push(docNo + ": freight journal Ref '" + ref + "' has non-numeric Amount " + String(j?.Amount) + " - skipped"); continue; }
    if (amount === 0) { skipRow("zero_amount", "skip_zero_amount"); continue; }
    const occurredOn = dateOnly(j?.Date);
    if (!occurredOn) { skipRow("no_date", "skip_no_date"); warnings.push(docNo + ": freight journal Ref '" + ref + "' without Date - skipped"); continue; }
    tally.kept++;
    rows.push({
      doc_type: "transfer", doc_number: docNo, kind: "transfer_freight",
      amount: round6(amount),                 // ⚠️ 음수도 넣는다 — 배분 단계 가드가 차단한다(헤더)
      occurred_on: occurredOn,                // ⚠️ 저널 Date(인보이스 날짜)
      ref_number: ref,                        // ⭐ Service Invoice 번호
      debit_account: debit, credit_account: credit,
      collector: COLLECTOR_VERSION, raw,
    });
  }
  // 페이로드 안 5키 중복 — PostgREST 가 거부하므로 합산. 0 이 아니면 「같은 인보이스가 같은 날 두 줄」 표본이 나온 것(⬜ 헤더)
  const byKey = new Map<string, DocCostRow>();
  let mergedRows = 0;
  for (const r of rows) {
    const k = [r.doc_type, r.doc_number, r.kind, r.ref_number, r.occurred_on].join("\u0001");
    const cur = byKey.get(k);
    if (cur) { mergedRows++; cur.amount = round6(cur.amount + r.amount); } else byKey.set(k, r);
  }
  if (mergedRows) warnings.push(docNo + ": " + mergedRows + " duplicate (ref, date) journal line(s) merged into one row - first real sample of same-invoice-same-day, inspect raw");
  if (byKey.size === 0) return done(firstSkip ?? "skip_no_journal");   // firstSkip 은 mjArr 이 비지 않으면 항상 있다 — 폴백은 방어용(~~skip_system_only~~ 제거 · 2026-09-10)
  return done("processed", [...byKey.values()], mergedRows);
}
// ── 계산 핵심 끝 ──

// ── 커서 tie-breaker (inv-cost 의 복제 — 원본 inv-collect 「②-b 커서 tie-breaker (2026-08-30 결함 C)」 절) ──
// 커서 = <LastModifiedOn 정규화>|<Number>. LastModifiedOn 은 절대 시각으로 파싱하지 않고 **문자열 패딩으로 정규화**(normLmo · 헤더)한다.
// 비캡 회차 = 회차 시작 시각(ISO Z) · 캡 회차 = 마지막 처리 문서의 키 — 동률 그룹 안에서도 식별자로 전진.
// ⚠️ 코드유닛 비교(localeCompare 금지) — 필터·저장이 같은 순서여야 문서가 유실되지 않는다. null(LMO 없음)은 맨 앞 = 거르지 않는다.
// LastModifiedOn 정규화 — 밀리초 3자리 고정 + Z (2026-09-10 · 헤더 「밀리초 자릿수」). 정규식 불일치는 원문 그대로(호출자가 lmo_unnormalized 로 센다).
const LMO_RE = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d+))?Z?$/;
function normLmo(s: string | null): string | null {
  if (!s) return null;
  const m = LMO_RE.exec(s);
  if (!m) return s;
  return m[1] + "." + (m[2] ?? "").slice(0, 3).padEnd(3, "0") + "Z";
}
// from_since · recheck_since 파서 — 날짜 또는 ISO 시각을 커서와 같은 축(정규화 ISO)으로. 실패 = null → 호출부가 400.
//   YYYY-MM-DD → T00:00:00.000Z · YYYY-MM-DDTHH:MM[:SS[.mmm]][Z]. 달력·시각 범위는 Date.parse 재직렬화로 검증(2026-13-99 · T99:99 거부).
function parseFloor(raw: string): string | null {
  let iso: string | null = null;
  if (/^\d{4}-\d{2}-\d{2}$/.test(raw)) iso = raw + "T00:00:00.000Z";
  else {
    const m = /^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?Z?$/.exec(raw);
    if (!m) return null;
    iso = m[1] + ":" + (m[2] ?? "00") + "." + (m[3] ?? "").padEnd(3, "0") + "Z";
  }
  const t = Date.parse(iso);
  if (!Number.isFinite(t) || new Date(t).toISOString() !== iso) return null;   // 달력·범위 밖(2026-13-99 · T99:99) — 재직렬화가 다르다
  return iso;
}
type CursorCand = { updated: string | null };
function cursorDocIdent(row: any): string {
  return String(row?.Number ?? "").trim() || String(row?.TaskID ?? "").trim();
}
function cursorKeyOf(updated: string | null, ident: string): string | null {
  return updated ? updated + "|" + ident : null;
}
function cursorKeyCompare(a: string | null, b: string | null): number {
  const ka = a ?? "", kb = b ?? "";
  return ka < kb ? -1 : ka > kb ? 1 : 0;
}
function countUpdatedTies(cands: CursorCand[]): number {
  const freq = new Map<string, number>();
  for (const cd of cands) if (cd.updated) freq.set(cd.updated, (freq.get(cd.updated) ?? 0) + 1);
  let n = 0;
  for (const cd of cands) if (cd.updated && (freq.get(cd.updated) ?? 0) > 1) n++;
  return n;
}
// 증상 가드 — 「캡에 걸렸는데 커서가 안 나갔다」를 직접 본다(결함 A·B·C 공통 증상). stalled 면 commit 차단.
function decideCursor(detailCapped: boolean, lastProcessedKey: string | null, cursorBefore: string | null, runStartIso: string) {
  const cursorWouldBe = detailCapped ? (lastProcessedKey ?? cursorBefore) : runStartIso;
  const cursorStalled = detailCapped && String(cursorWouldBe ?? "") <= String(cursorBefore ?? "");
  return { cursorWouldBe, cursorStalled };
}

// ── 회차 로그 (inv_collect_runs · source_key='cost_transfer' — inv-cost buildCostRun 의 복제 · 규칙 변경은 함께) ──
// dry 미기록 · 차단 회차도 기록(ok=false) · 로그 실패가 수집을 막지 않는다. inv-doc-cost 에 없는 개념은 null.
function buildDocCostRun(out: Record<string, unknown>, warnings: string[], durationMs: number): Record<string, unknown> {
  const num = (v: unknown) => (v == null ? null : Number(v));
  const warnCapped = warnings.slice(0, 50);
  const summary: Record<string, unknown> = {};
  for (const k of Object.keys(out)) if (k !== "samples") summary[k] = k === "warnings" ? warnCapped : out[k];
  return {
    source_key: SOURCE_KEY,
    ok: out.write_skipped ? false : true,
    collector: COLLECTOR_VERSION,
    detail_capped: out.detail_capped === true,
    detail_capped_reason: out.detail_capped_reason ?? null,
    detail_capped_remaining: num(out.detail_capped_remaining) ?? 0,
    hold_capped: null,
    cursor_before: out.cursor_before ?? null,
    cursor_after: out.cursor_after ?? out.cursor_after_would_be ?? null,
    cursor_stalled_alert: out.cursor_stalled_alert ?? null,
    cursor_frozen_alert: null,
    list_total: num(out.list_total),
    list_received: num(out.list_received),
    pages: num(out.pages),
    truncated: out.truncated ?? null,
    list_aborted: out.list_aborted ?? null,
    candidates: num(out.candidates),
    docs_processed: num(out.docs_processed),
    detail_fetched: num(out.detail_fetched),
    ledger_rows: null,
    inserted: null,
    insert_skipped: null,
    skipped_unchanged: null,
    precision_skipped: num(out.precision_skipped),
    write_skipped: out.write_skipped ?? null,
    dispositions: out.dispositions ?? null,
    warnings: warnCapped,
    summary,
    duration_ms: durationMs,
  };
}
async function writeCollectRun(row: Record<string, unknown>): Promise<void> {
  const r = await fetch(SB_URL() + "/rest/v1/inv_collect_runs", {
    method: "POST",
    headers: sbHeaders({ Prefer: "return=minimal" }),
    body: JSON.stringify([row]),
  });
  if (!r.ok) throw new Error("sbInsert inv_collect_runs " + r.status + ": " + (await r.text()).slice(0, 400));
}

Deno.serve(async (req) => {
  const t0 = Date.now();
  try {
    if (req.method === "OPTIONS") {
      return new Response("ok", { headers: { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "x-wms-cron-key, content-type" } });
    }
    // ── 인증 (fail-closed — inv-collect·inv-cost 동일 · WMS_CRON_SECRET 공유) ──
    const secret = Deno.env.get("WMS_CRON_SECRET") ?? "";
    if (!secret) return json({ ok: false, error: "WMS_CRON_SECRET not configured - refusing (fail-closed)" }, 500);
    if ((req.headers.get("x-wms-cron-key") ?? "") !== secret) return json({ ok: false, error: "unauthorized" }, 401);

    // ── 파라미터 (관례: 기본 dry · ?commit=1 이 있어야 쓴다) ──
    const url = new URL(req.url);
    const commit = url.searchParams.get("commit") === "1";
    // ?from_since=<날짜|ISO 시각> — 커서 없을 때의 첫 시딩 하한. ⚠️ 시각을 받는다(2026-09-10 · 헤더 실사고 TR-03975) — 커서와 같은 축.
    const fromSinceRaw = (url.searchParams.get("from_since") ?? "").trim() || null;
    const fromSince = fromSinceRaw ? parseFloor(fromSinceRaw) : null;
    if (fromSinceRaw && !fromSince) return json({ ok: false, error: "from_since must be YYYY-MM-DD or YYYY-MM-DDTHH:MM[:SS[.mmm]][Z] (UTC) - got '" + fromSinceRaw + "'" }, 400);
    // ?recheck_since=<날짜|ISO 시각> — 커서 아래 문서를 다시 태운다(이 시각 이후 LastModifiedOn 전부 · 커서 필터 끔). 커서는 손대지 않는다 —
    //   비캡 회차면 회차 시작 시각으로 전진(재조회 창 ⊇ 평시 창 · 중복은 upsert 흡수) · 캡 회차면 제자리(뒤로 가지 않는다).
    //   ⚠️ from_since 와 같은 축 결함이 있었다(날짜만) — 함께 고쳤다(2026-09-10).
    const recheckSinceRaw = (url.searchParams.get("recheck_since") ?? "").trim() || null;
    const recheckSince = recheckSinceRaw ? parseFloor(recheckSinceRaw) : null;
    if (recheckSinceRaw && !recheckSince) return json({ ok: false, error: "recheck_since must be YYYY-MM-DD or YYYY-MM-DDTHH:MM[:SS[.mmm]][Z] (UTC) - got '" + recheckSinceRaw + "'" }, 400);
    const timeLeft = () => TIME_BUDGET_MS - (Date.now() - t0);
    const warnings: string[] = [];

    // ── 커서 (inv_sync_state · source_key='cost_transfer') ──
    const stateRows = await sbGet("inv_sync_state?source_key=eq." + SOURCE_KEY + "&select=source_key,last_cursor");
    const cursorBefore: string | null = stateRows[0]?.last_cursor ?? null;
    let sinceSource: "state" | "param" | "recheck" | "none" = "none";
    if (recheckSince) sinceSource = "recheck";
    else if (cursorBefore) sinceSource = "state";
    else if (fromSince) sinceSource = "param";
    if (sinceSource === "none") warnings.push("NO CURSOR - every COMPLETED transfer is a candidate (pass ?from_since=2026-08-20 or seed inv_sync_state '" + SOURCE_KEY + "'); the detail cap will page through them run by run");
    if (recheckSince) warnings.push("RECHECK_SINCE=" + recheckSince + " - candidates widened below cursor (" + cursorBefore + "), cursor filter off for this run; cursor is not moved backwards");
    // 코드 측 하한 — 전량 목록이라 서버 창이 없다(헤더). recheck > 커서 > from_since. 하한은 정규화 ISO 시각 · 정규화된 LastModifiedOn 과
    //   같은 축으로 비교한다(종전 「앞 10자」 비교 폐기 — 헤더 실사고). 커서 회차는 null(키 필터가 대신한다).
    const lmoFloor: string | null = recheckSince ?? (cursorBefore ? null : fromSince);

    // ── 1) 목록 — stockTransferList 전량(Status=COMPLETED) · 최근순이 아니므로 끝까지 받는다 ──
    let listTotal: number | null = null, listReceived = 0, pages = 0;
    const listRows: any[] = [];
    let listAborted: string | null = null;
    let rateLimited = false;
    for (let page = 1; page <= MAX_LIST_PAGES; page++) {
      if (timeLeft() < 0) { listAborted = "time"; break; }
      let j: any;
      try {
        j = await cin7Get("/stockTransferList?Page=" + page + "&Limit=" + LIST_PAGE_LIMIT + "&Status=" + encodeURIComponent("COMPLETED"));
      } catch (e: any) {
        if (Number(e?.status) === 429) { rateLimited = true; listAborted = "rate_limited"; }
        else listAborted = "page_error: " + String(e?.message ?? e).slice(0, 200);
        break;
      }
      pages++;
      if (j?.Total != null) listTotal = Number(j.Total);
      const batch = (j?.StockTransferList ?? []) as any[];
      listReceived += batch.length;
      listRows.push(...batch);
      if (batch.length < LIST_PAGE_LIMIT) break;
      await sleep(LIST_SLEEP_MS);
    }
    const truncated = listTotal == null ? null : listReceived < listTotal;

    // ── 2) 후보 — 정규화(normLmo) → 하한(시각) → 목록 disposition → 키 정렬 → 커서 필터 ──
    //   ⚠️ 목록 disposition 은 하한 안의 행만 센다 — 전량 목록에서 매 회차 「같은 창고 이동 772건」을 세면 기준선을 외우게 된다.
    const dispositions: Record<string, number> = {};
    const tally = (k: string) => { dispositions[k] = (dispositions[k] ?? 0) + 1; };
    const cands: { row: any; updated: string | null; key: string | null }[] = [];
    let belowFloor = 0, lmoMissing = 0, lmoUnnormalized = 0;
    for (const row of listRows) {
      const rawLmo = String(row?.LastModifiedOn ?? "").trim() || null;
      if (!rawLmo) lmoMissing++;   // [실측 2026-08-31] 1000/1000 존재 — 0 이 아니면 신호(그 문서는 매 회차 후보가 된다 · 유실 방지 방향)
      const updated = normLmo(rawLmo);   // ⚠️ 밀리초 3자리 정규화 — 정렬·하한·커서 판정이 전부 이 값을 쓴다(헤더 「밀리초 자릿수」)
      if (rawLmo && !LMO_RE.test(rawLmo)) lmoUnnormalized++;   // 예상 밖 형식 — 원문 그대로 비교된다(0 이 아니면 신호)
      if (lmoFloor && updated && updated < lmoFloor) { belowFloor++; continue; }
      const d = listDisposition(row);
      if (d !== "candidate") { tally(d); continue; }
      cands.push({ row, updated, key: cursorKeyOf(updated, cursorDocIdent(row)) });
    }
    cands.sort((a, b) => cursorKeyCompare(a.key, b.key));
    // 커서 필터 = 증분 (inv-cost 의 정밀도 필터와 같은 비교 · 키 < 커서 는 이미 본 문서). recheck 회차는 끔.
    let precisionSkipped = 0;
    if (!recheckSince && cursorBefore) {
      const kept: typeof cands = [];
      for (const cd of cands) {
        if (cd.key && cd.key < cursorBefore) { precisionSkipped++; continue; }
        kept.push(cd);
      }
      cands.length = 0;
      cands.push(...kept);
    }
    const updatedTies = countUpdatedTies(cands);
    // 진단 — 후보 정렬(커서 필터 뒤 = 실제 처리 순서) 앞 10건 (헤더 「진단」)
    const candidateHead = cands.slice(0, 10).map((cd, i) => ({ n: i + 1, doc_number: cursorDocIdent(cd.row), key: cd.key }));

    // ── 3) 상세 → 운송비 행 ──
    const allRows: DocCostRow[] = [];
    const journal = emptyTally();
    let detailFetched = 0, docsProcessed = 0, mergedRows = 0;
    let detailCapped = false, detailCapReason: string | null = null, cappedRemaining = 0;
    const SKIPPED_DOCS_MAX = 50;   // 진단 목록 상한 — 응답 폭주 방지 (헤더 「진단」)
    const skippedDocs: { doc_number: string; disposition: string; mj_len: number | null }[] = [];
    let skippedDocsTruncated = 0;
    const mjLenOf = (det: any): number | null => Array.isArray(det?.ManualJournals) ? det.ManualJournals.length
      : Array.isArray(det?.ManualJournals?.Lines) ? det.ManualJournals.Lines.length : (det?.ManualJournals == null ? null : 0);
    let lastProcessedKey: string | null = null;
    for (let i = 0; i < cands.length; i++) {
      if (detailFetched >= MAX_DETAIL_PER_RUN) { detailCapped = true; detailCapReason = "max_detail"; cappedRemaining = cands.length - i; break; }
      if (timeLeft() < 5_000) { detailCapped = true; detailCapReason = "time"; cappedRemaining = cands.length - i; break; }
      const cd = cands[i];
      const id = String(cd.row?.TaskID ?? "").trim();
      let det: any;
      try {
        det = await cin7Get("/stockTransfer?TaskID=" + encodeURIComponent(id));
        detailFetched++;
        await sleep(DETAIL_SLEEP_MS);
      } catch (e: any) {
        // 상세 오류 = 캡과 같은 정지 — 지나치면 그 문서가 조용히 유실된다(커서가 넘어간다)
        if (Number(e?.status) === 429) { rateLimited = true; detailCapReason = "rate_limited"; }
        else { detailCapReason = "detail_error"; warnings.push("detail error " + String(cd.row?.Number ?? id) + ": " + String(e?.message ?? e).slice(0, 200)); }
        detailCapped = true;
        cappedRemaining = cands.length - i;
        break;
      }
      const docNo = String(det?.Number ?? cd.row?.Number ?? "").trim();
      const r = buildDocCostRows({ docNo, det, row: cd.row });
      tally(r.disposition);
      if (r.disposition !== "processed") {   // 진단 — 어느 문서가 왜 빠졌나 (mj_len null = ManualJournals 키 자체 없음 · 0 = 빈 배열)
        if (skippedDocs.length < SKIPPED_DOCS_MAX) skippedDocs.push({ doc_number: docNo, disposition: r.disposition, mj_len: mjLenOf(det) });
        else skippedDocsTruncated++;
      }
      warnings.push(...r.warnings);
      mergedRows += r.mergedRows;
      for (const k of Object.keys(journal) as (keyof JournalTally)[]) journal[k] += r.tally[k];
      if (r.disposition === "processed") { docsProcessed++; allRows.push(...r.rows); }
      if (cd.key) lastProcessedKey = cd.key;
    }

    // ── 커서 (inv-cost 동형): 비캡 = 회차 시작 시각 · 캡 = 마지막 처리 문서의 키 ──
    const runStartIso = new Date(t0).toISOString();
    let { cursorWouldBe, cursorStalled } = decideCursor(detailCapped, lastProcessedKey, cursorBefore, runStartIso);
    if (recheckSince && detailCapped) {
      cursorWouldBe = cursorBefore;
      cursorStalled = false;
      warnings.push("RECHECK capped - cursor held at " + cursorBefore + "; re-run with a later recheck_since to cover the remaining " + cappedRemaining + " doc(s)");
    }
    const cappedNoUpdated = detailCapped && lastProcessedKey == null;
    if (cursorStalled) warnings.push("CURSOR STALLED - capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - transfer freight collection is frozen; commit is blocked");
    if (journal.non_inventory_debit) warnings.push("SIGNAL: " + journal.non_inventory_debit + " journal line(s) with a non-inventory Debit account were skipped - a new account appeared, inspect warnings above");
    if (journal.non_freight_credit) warnings.push("SIGNAL: " + journal.non_freight_credit + " journal line(s) with Debit _59_ but a non-freight Credit account were skipped - a new cost account appeared, inspect warnings above");
    if (journal.no_reference) warnings.push("SIGNAL: " + journal.no_reference + " freight journal line(s) without Reference were skipped (would break inv_doc_cost_uq)");

    // ── 4) commit — 쓰기 성공 뒤에만 커서 전진 ──
    let rowsWritten: number | null = null;
    let writeSkipped: string | null = null;
    if (commit) {
      if (listAborted) writeSkipped = "list_aborted: " + listAborted;
      else if (truncated) writeSkipped = "list truncated";
      else if (cappedNoUpdated) writeSkipped = "capped with no usable LastModifiedOn - cursor would freeze";
      else if (cursorStalled) writeSkipped = "capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - transfer freight collection is frozen";
      if (!writeSkipped) {
        rowsWritten = await writeDocCostRows(allRows as unknown as Record<string, unknown>[], new Date().toISOString());
        await sbUpsert("inv_sync_state", "source_key", [{
          source_key: SOURCE_KEY,
          last_cursor: cursorWouldBe,
          last_run_at: new Date().toISOString(),
          last_ok_at: new Date().toISOString(),
          note: COLLECTOR_VERSION + " rows=" + allRows.length + (detailCapped ? " capped" : ""),
        }]);
      }
    }
    // commit 블록 끝 — ⚠️ writeDocCostRows 호출은 위 블록 안 한 곳뿐이다(dry 는 절대 쓰지 않는다)

    const out: Record<string, unknown> = {
      ok: true,
      mode: commit ? "commit" : "dry",
      collector_version: COLLECTOR_VERSION,
      source_key: SOURCE_KEY,
      list_total: listTotal,
      list_received: listReceived,
      pages,
      truncated,
      list_aborted: listAborted,
      rate_limited: rateLimited,
      lmo_floor: lmoFloor,                   // 실제 적용된 하한(정규화 ISO 시각 · recheck_since / from_since 파싱 결과) · 커서 회차는 null(키 필터가 대신한다)
      below_floor: belowFloor,
      lmo_missing: lmoMissing,               // LastModifiedOn 없는 목록 행 — [실측] 0 · 0 이 아니면 신호
      lmo_unnormalized: lmoUnnormalized,     // LastModifiedOn 이 예상 형식(YYYY-MM-DDTHH:MM:SS[.f]Z)이 아닌 행 — 원문 비교로 떨어진다 · 0 이 아니면 신호
      dispositions,
      candidates: cands.length,
      precision_skipped: precisionSkipped,   // 키 < 커서 (이미 본 문서)
      updated_ties: updatedTies,             // 동률 그룹 조기 신호 — 캡보다 커지면 결함 C 상황(가드가 잡는다)
      candidate_head: candidateHead,         // 진단 — 커서 필터 뒤 후보 앞 10건 {n, doc_number, key} (특정 문서가 후보에 있나 · 몇 번째인가)
      detail_fetched: detailFetched,
      detail_capped: detailCapped,
      detail_capped_reason: detailCapReason,
      detail_capped_remaining: cappedRemaining,
      docs_processed: docsProcessed,
      rows_built: allRows.length,
      rows_written: rowsWritten,
      write_skipped: writeSkipped ?? undefined,
      skipped_docs: skippedDocs,             // 진단 — 상세를 봤는데 processed 가 아닌 문서 {doc_number, disposition, mj_len} · 최대 50
      skipped_docs_truncated: skippedDocsTruncated,   // 50 을 넘어 목록에서 빠진 skip 문서 수
      journal_lines: journal,                // 저널 행 단위 집계(kept·non_inventory_debit·non_freight_credit·no_reference·zero_amount·bad_amount·no_date) · ~~system~~ 제거(2026-09-10)
      merged_rows: mergedRows,               // 같은 (ref, date) 두 줄 합산 — ⬜ 표본 없음 · 0 이 아니면 첫 실물
      amount_built: round6(allRows.reduce((s, r) => s + r.amount, 0)),
      recheck_since: recheckSince,           // 정규화 ISO(입력 원문은 recheck_since_raw)
      recheck_since_raw: recheckSinceRaw,
      from_since_raw: fromSinceRaw,
      cursor_before: cursorBefore,
      cursor_after: commit && !writeSkipped ? cursorWouldBe : cursorBefore,
      cursor_after_would_be: cursorWouldBe,
      cursor_held_by: detailCapped ? "capped:" + detailCapReason + " - cursor held at last processed doc's cursor key" : null,
      cursor_stalled_alert: cursorStalled
        ? "capped and cursor would not advance (cursorBefore=" + cursorBefore + ", wouldBe=" + cursorWouldBe + ") - transfer freight collection is frozen; commit is blocked"
        : undefined,
      cursor_source: sinceSource,
      samples: allRows.slice(0, 5),
      warnings,
      duration_ms: Date.now() - t0,
    };

    // 회차 로그 (inv_collect_runs source_key='cost_transfer' — dry 미기록 · 차단 회차도 기록 · 실패는 경고만)
    if (commit) {
      try {
        await writeCollectRun(buildDocCostRun(out, warnings, Date.now() - t0));
        out.collect_run_logged = true;
      } catch (e: any) {
        out.collect_run_logged = false;
        out.collect_run_error = String(e?.message ?? e).slice(0, 200);
        warnings.push("collect-run log failed (freight collection unaffected): " + out.collect_run_error);
      }
    } else out.collect_run_logged = false;
    return json(out);
  } catch (e) {
    return json({ ok: false, error: String(e).slice(0, 500), duration_ms: Date.now() - t0 }, 500);
  }
});

function json(obj: unknown, status = 200): Response {
  return new Response(JSON.stringify(obj, null, 2), {
    status, headers: { "Content-Type": "application/json", "Access-Control-Allow-Origin": "*" },
  });
}
