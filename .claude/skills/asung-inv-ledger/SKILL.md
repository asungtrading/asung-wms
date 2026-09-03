---
name: asung-inv-ledger
description: >
  Asung Trading 재고 원장(IMS 두 번째 모듈)을 다룰 때 먼저 읽으세요.
  Cin7 재고를 대체할 자체 장부 — 사건을 쌓아 잔고를 계산합니다.
  "원장", "inv_ledger", "재고 원장", "shadow", "shadow 모드", "기초 스냅샷",
  "inv_snapshot", "inv_compare", "inv_sync_state", "대조", "Movements",
  "ProductAvailability", "StockOnHand", "차감 시점", "Ship 차감", "Allocated",
  "IN_TRANSIT", "운송 중", "조립", "FinishedGoods", "번들", "AutoAssembly",
  "Adjustment", "ExistingStockLines", "NewStockLines", "CreditNotes Restock",
  "StockReceived Lines Date", "DepartureDate", "CompletionDate", "seq_hint",
  "line_ref", "FIFO", "원가 레이어" 등이 나오면 추측하지 말고
  이 스킬의 확정 사실·이벤트 규칙·함정을 확인하세요.
  ⚠️Adjustment는 증감분이 아니라 조정 후 수량, ⚠️NewStockLines는 규칙이 다름,
  ⚠️재고는 Ship에 빠짐(픽·팩은 Allocated), ⚠️StockOnHand는 수량이 아니라 평가액,
  ⚠️같은 날은 유입 먼저 — 어기면 원장 전체가 반대로 쌓이거나 잔고가 음수가 됩니다.
---

# Asung Trading 재고 원장 스킬

WMS 다음 모듈. **설계 정본은 레포의 `docs/design/ledger-design.md`** — 이 스킬은 그 요약과
실측 근거, 그리고 반복해서 틀렸던 지점들이다.

⚠️ **방향 정본: `docs/design/ims-principles.md`** — 모든 모듈의 상위 문서다.
최종 목표는 **Cin7 을 대체하는 자체 IMS** 이고, 앞으로 만드는 모든 것은
**Cin7 없이 독립 작동하는 것을 전제로** 설계한다. 모듈은 레고처럼 — 접점은
「사건을 남긴다」 하나뿐이고, 하나가 고장나도 전체 영향이 최소화되어야 한다.
개별 설계가 이것과 충돌하면 **그쪽이 이긴다.**

관련 스킬: `asung-wms`(같은 레포·DB), `cin7-api`(엔드포인트·파라미터)

---

## 1. 무엇을 만드는가

"지금 몇 개"를 저장하지 않고 **"무슨 일이 있었다"만 쌓는다.** 잔고는 더해서 구한다.

- **1단계 범위**: 수량만 · 창고 단위 · shadow(어디에도 안 씀)
- **기준은 Cin7 문서.** WMS 는 보조 — WMS 미경유 사건이 월 수백 건이라 WMS 기준은 처음부터 구멍
- 원가(amount)·자리(bin)는 **값만 저장하고 계산엔 안 씀** — 나중에 소급 불가라 지금부터 담는다

**진행 상태 (2026-08-20 — ⑤ 가동)**: 테이블 **5개**(`inv_conflicts` 포함) + 스냅샷 EF
(`inv-snapshot`) + 수집 EF(`inv-collect` — ②-a 전량 축 3종·②-b 증분 축 3종) 배포 · 현재
**`@2026-08-19.1`**(페이싱 1200ms·`Retry-After` 백오프 + `inv_conflicts` 변경 감지).
⚠️⚠️ **쓰기가 켜졌다 — `commit=1` 금지는 해제됐다.** ③ 검증에서 ⑤ 가동까지 2026-08-20 저녁~밤에
한 번에 넘어갔다(경위 정본: `docs/sessions/2026-08-20-ledger-go-live.md` · 설계 정본: 4부
「⑤ 쓰기 가동」).

- ✅ **④ 기초 스냅샷 완료** — `snapshot_key 2026-08-20-initial` ·
  `taken_at 2026-08-20T23:42:47.855Z` · **13,844행**(토론토 7,523 / 에드먼튼 6,321) · 44초 ·
  `truncated`·`rate_limited` false · `unexpected_warehouses []`. **8/22 예정을 8/20 로 앞당겼다**
  (창고가 멈춘 시각이면 조건이 같다).
- ✅ **커서 seed 완료** — `transfer=TR-01327` · `adjustment=ST-00646` · `assembly=FG-00128` /
  증분 축 3종(`sale`·`purchase`·`creditnote`)은 스냅샷 `taken_at`.
- ✅ **가동 첫날 정상 (2026-08-21 — 설계 4부 「가동 첫날 검증」이 정본)**: 6잡 전부 `last_run_at`
  갱신 · 커서 전진(`transfer` `TR-01327`→`TR-03974`, 밤사이 2,647건 소화) ·
  ⭐ **첫 실물 대조 통과**(`ST-01233` 파손 조정 3 SKU — Cin7 Variance 와 `qty_delta` 정확 일치,
  bin 까지. **Cin7 은 절대값·원장은 증감분 — 변환이 옳다**) ·
  `since` 실동작(`TR-03539` — 오늘 적용됐지만 사건 날짜 8/4 라 정확히 제외: 갱신 축과 사건 날짜의
  독립이 실물로) · 트랜스퍼 4행 구조 실동작(TR-04166~70 각 4행·합계 0) ·
  📌 `TR-01327` seed 판단 적중(`TR-03539` 는 버려진 게 아니라 실제 적용 대상이었다 —
  「되돌릴 수 있는 쪽을 고른다」의 값어치).
  ⚠️ **검증 범위 정직하게**: 대조는 조정 1건뿐 — 판매 45·발주 2건 미대조 · `inv_conflicts` 아직 빈 상태.
  **전량 대조는 ⑥의 일이다.**
- ⚠️ **커서 교착 중 — `TR-03975`·`03976`** (2026-08-21~ · [실측 2026-08-25] 둘 다 여전히
  IN TRANSIT·원장 0행 — `hold_intransit_before_since` 가 커서를 `TR-03974` 에 고정).
  모르면 사고가 나는 것 셋만 여기에 — **경위·수치 정본은 `docs/sessions/2026-08-25-transfer-line-deletion.md`**:
  · 교착 동안 커서 위 문서 전부(~205건)를 매 회차 재읽기한다 — ⚠️ **그 재읽기가 TR-04175 소멸
    감지를 가능하게 한 실제 이유**다(설계 의도가 아니라 교착의 덕 — **커서가 풀리면 함께 끊긴다**).
  · ✅ **[실측 2026-08-26 도착] 예측대로 일어났다** — 커서가 `TR-03974`→`TR-04172` 로 풀렸고:
    `TR-03975` IN_TRANSIT **−1,550** · `TR-03976` **−1,009** · 날짜는 도착일 하나뿐
    (leg 1·2 가 `since` 필터에 걸리고 leg 3·4 만 기표) · `it_rows = wh_rows`(도착분은 정확).
  · ✅ **「무해하다」는 판정도 검증됐다** — 같은 날 아침 대조가 **`unknown 0`** 이었다.
    IN_TRANSIT 이 −2,559 인데도. 근거(「Cin7 도 운송 중을 ON HAND 에서 뺀다」)가 맞았다.
    ~~「도착 전에 손봐야 한다」~~ 는 2026-08-25 철회 · 2026-08-28 실물로 확정.
  · ⚠️⚠️ **결정(2026-08-28): 상쇄하지 않고 그대로 둔다.**
    `FINAL-SALE`·`TR-04175` 상쇄는 **잘못을 정정**한 것이지만 이것은 **기초 스냅샷 경계의
    설계상 예정된 결손**이다 — 상쇄하면 **없던 사건을 만드는** 셈이다.
    ⚠️ **IN_TRANSIT 잔고는 영구히 음수로 남는다.** 언젠가 「운송 중 재고」를 화면에 띄울 때
    **8/20 이전 출발분은 음수**임을 알고 처리할 것. **버그가 아니다.**
- ✅ **pg_cron 6잡 등록**(jobid 6~11 · 소스별 분리 · `hello` 와 분을 어긋나게) —
  기록은 `supabase/ops/cron.sql`.
  ⚠️ **[2026-08-21 정정] purchase 는 `7-52/15` → `8-53/15`** — 최초 등록값 7·22·37·52 가
  `transfer`(`2-57/5` = 2·7·12·…·57)의 **부분집합**이라 4회 실행이 전부 동시였다(둘 다
  `inv-collect`·같은 WMS 키 → 합산 분당 ~100콜 = 한도 60의 1.7배). `alter_job` 으로 변경 완료 ·
  **현재 겹침 0**. `hello` 와는 처음부터 6잡 전부 안 겹쳤다.
  📌 **분 어긋내기는 「폴링과」가 아니라 「서로」까지 봐야 한다** — 잡이 늘면 쌍은 제곱으로 늘고,
  눈으로는 못 센다. **분 집합을 전수 계산할 것.**

- ✅ **라인 소멸 감지 배포 (2026-08-25 · 마이그레이션 `20260825142042` · `inv-collect@2026-08-25.1`
  · [실사고 TR-04175] 수집 후 Cin7 라인 138줄 삭제 → 이중 차감·unknown 138 — 경위·실동작 검증
  (첫 검출 276행 정확 일치) 정본은 `docs/sessions/2026-08-25-transfer-line-deletion.md`)**.
  모르면 사고가 나는 것만 여기에:
  · **판정**: B(원장의 그 문서 행 · `source='cin7'` 만) − A(이번 상세가 만든 행) = 사라진 라인.
    ⚠️ **A 는 sink 필터 「전」의 rows** — `since`·비재고 게이트로 걸러진 라인도 Cin7 에 실재하므로
    A 에 있어야 한다(`sink.rows` 기준이면 그것들이 전부 「사라진 라인」이 된다)
  · **게이트 넷**: G1 상세 실조회 문서만(②-b 는 부분 스킵 있으면 문서째 제외) · G2 `source='cin7'` 만
    (manual 상쇄 행 제외) · G3 회차 중단이면 소스 전체 skip · G4 갱신 시각 없으면 문서 skip
  · ⚠️ **기록·경보만 — 원장 무접촉, 자동 정정 없음**(유령 판정은 사람이 Cin7 화면으로) ·
    ⚠️ **진단은 수집을 막지 않는다**(검출·기록 4곳 try/catch — 안 감싸면 REST 순단 한 번에 원장
    쓰기·커서까지 멈추는데 `cron.job_run_details` 는 `succeeded`)
  · **아침 점검 3번째 줄**:
    `select doc_number, count(*), min(last_modified_on) from inv_missing_lines where resolved_at is null group by 1;`
- ⚠️ **문서 캡 `MISSING_MAX_PER_DOC=1500` 은 발동하지 않는다** — 회차 캡
  `MISSING_MAX_PER_RUN=500` 이 항상 먼저 걸리기 때문(문서 캡이 회차 캡 안쪽).
  **실동 방어는 500 하나**다. 500 도달 시: 앞에서부터 500건만 기록 · 잔여분은 기록되지 않고
  **다음 회차에도 같은 앞부분을 다시 담는다**(`order=id.asc` 로 결정적) · ⚠️ 내부 루프의 break 는
  `capped=true` 만 세팅하고 **warnings 를 남기지 않는다**(응답 `missing_lines_capped` 로만 보인다).
  📌 실용상 무해하다 — 500건이 뜬 것만으로 「대량 삭제」를 알 수 있고, 상쇄 SQL 용 완전 목록은
  원장을 직접 쿼리해 뽑는다(2026-08-25 에 276행을 그렇게 만들었다).
  ⬜ 개선안(미착수): 「이미 기록된 키를 제외하고 캡을 센다」 — 회차마다 다음 500건으로 넘어간다.

- ✅ **문서 변경 감지 (2026-08-31 · `20260831140218` · `inv_doc_state`)**
  변경 없는 종결 문서는 상세를 부르지 않는다. [실측] 트랜스퍼 상세 **39 → 5** ·
  `hold_capped 120 → 0` · Cin7 호출 회차당 34건 감소.
  · **시딩 불필요** — 회차마다 채워져 **20분에 156건**이 찼다
  · ⚠️ `last_modified` 가 **안 올라가는 경우**가 있으면 조용히 놓치므로 믿는 축에는 검산이
    필요하다 ⇒ **롤링 재확인**(아래 항목)이 그 일을 한다. `?recheck=1` 은 그 회차만 판정을
    끄는 **수동 조사 도구** — ❌ **cron 등록하지 않는다**(커버리지가 안 나온다 · 롤링 항목)
  · ⚠️ ②-b 는 `docIncomplete` 문서를 기록하지 않는다(`adv_no_putaway` 등의 재조회 안전망 보존)

- ✅ **수집 회차 로그 (2026-08-31 · `20260831153314` · `inv_collect_runs`)**
  결함 C·D 둘 다 **EF 응답에는 신호가 있었는데**(`cursor_after_would_be == cursor_before` ·
  `hold_capped 120`) 응답을 아무도 안 봐서 하루 반·사흘 늦게 알았다.
  ⇒ 회차별 밀림 축과 실적을 남긴다. `inv_snapshot_runs` 와 같은 틀.
  · ⚠️ **`dry` 는 안 남긴다** · 차단된 commit 회차는 `ok=false` 로 남긴다
  · ⚠️ 관측만 추가 — 커서·캡 로직 무접촉
  · **`inv-cost` 도 `source_key='cost'` 로 남긴다**(하루 1회라 응답 볼 기회가 없다)
  · ⭐ **아침 점검 ⑦** — 24시간 내 이상 회차가 **0행이면 그날 수집은 정상**
- ✅ **롤링 재확인 (2026-08-31)** — `last_modified` 를 믿는 축의 검산.
  매 회차 `seen_at` 이 가장 오래된 **5건**을 강제 재조회한다(트랜스퍼 156건 · 약 2.6시간 회전).
  · ❌ **`?recheck=1` cron 은 커버리지가 안 나온다** — 캡 40 · 커서 hold 조합이라 매번
    「커서 위 첫 40건」만 본다. ⚠️ **「검산하고 있다」는 착각만 남아 안 하는 것보다 나쁠 수 있다**
  · ⚠️ 커버리지: `transfer` **완전** / `adjustment`·`assembly` **닿지 않음**(커서 전진 —
    ⚠️ [2026-09-02 보강] **최근 7일은 재조회 창이 덮는다**(결함 E 처방). 그 밖은 여전히 안 닿는다) /
    ②-b **최근 창만**(`UpdatedSince`). 📌 어느 쪽도 **악화는 아니다**
  · **`doc_state_oldest_seen` 이 커버리지 지표**
  · `?recheck=1` 은 수동 조사 도구로 남긴다 — ⬜ cron 미등록
- ✅ **트랜스퍼 출발 bin (2026-08-31 · `inv-collect@2026-08-31.4`)**
  정본: `docs/sessions/2026-08-31-transfer-departure-bin.md` — ⚠️ **막다른 길 다섯이 거기 있다.
  다시 파지 말 것.**
  · 문제: 창고 간 이동의 출발 bin 이 비어 있었다. [실측] bin 대조에서 **토론토 8,141칸 중
    1,201칸 · 격차 15,640**(에드먼튼은 12칸·80). ⚠️ **한 건의 결손이 두 곳을 어긋나게 한다** —
    유령 `bin=''`(−7,530)과 안 뺀 실제 bin(+6,710)이 거울상이라 **창고 단위 합은 맞고
    매일 대조(⑥)에는 안 걸린다.** 대상 5문서 734행
  · ⭐ **해결: 우리 DB 에 이미 있었다.** 트랜스퍼 `Reference` → 픽용 SO → `wms_orders` →
    `wms_order_lines.bin_location`. [실측] `TR-04331` CSV 112줄 대조 **112/112 완전 일치**
  · ⚠️ **`Reference` 는 사람이 손으로 넣는다** — 빠뜨리면 `transfer_bin_no_reference` 로 뜬다.
    자가 치유 안 됨 ⇒ Reference 를 채우고 `scripts/fix-transfer-bins.mjs` 를 돌린다
  · ⚠️ **결합**: 원장이 WMS 테이블을 읽는다. **잠정이다** — 목표는 WMS 픽이 원장에
    사건을 남기는 것이고, 그때 이 조회도 `Reference` 라는 다리도 사라진다
  · ⭐ **소멸 감지 `bin 변경` 예외**(`partitionBinChanged`) — 스킬의 「키 변경 경고」 처방.
    bin 만 다른 **6키**(`doc_type`·`doc_number`·`line_ref`·`event_type`·`warehouse`·`sku`)가
    A 에 있으면 소멸이 아니다. ⚠️ **`event_type` 까지 일치를 요구**해야 IN_TRANSIT 다리가
    창고 다리를 면책하는 오판이 구조적으로 불가능하다. **캡보다 앞에서 거른다**
- ✅ **트랜스퍼 출발 bin — 잔고 규칙 우선 (2026-09-01 · `inv-collect@2026-09-01.1`)**
  정본: `docs/sessions/2026-09-01-morning-check.md` §5
  · 판정: ①그 시점 잔고(기초 스냅샷 + `occurred_on` 이하 델타 · ⚠️ **자기 문서 제외**) →
    ②유일하면 그 칸(+`wms_stale` 보고) → ③다중이면 WMS 값으로 가름, 못 가르면 비움
    (+`ambiguous`) → ④0칸이면 WMS 폴백 → ⑤비움
  · ⭐ **관점**: 재현할 것은 「작업자가 간 자리」가 아니라 **Cin7 의 bin 기록**이다.
    Cin7 은 자기 기록대로 뺀다 ⇒ 원장이 이미 가진 이동 사건으로 따라갈 수 있다
  · ⭐ **WMS 맵 없는 문서에도 적용**한다 — `no_reference`·`so_missing` 부류가 자동 해결된다
    ([실측] `resolved` 592 → 596 · `unresolved` 4 → 0)
  · ⚠️ **한계**: 같은 날 안의 순서를 못 가린다 ⇒ **유일할 때만 확정**하고 애매하면 비운다
  · ⚠️ 1,000행 캡에 닿으면 규칙을 끈다(잘린 잔고로 판정하면 틀린다)
  · ⚠️ **배포 직후 함정**: 손으로 넣은 `:binfixed` 행과 수집기의 `cin7` 행은 `line_ref` 가
    달라 **유니크 키가 막지 못한다** ⇒ `:superseded` 로 자리를 비워줘야 한다
- ✅ **재고 마스터 — 원장측 (2026-09-01)**
  정본: `docs/sessions/2026-09-01-stock-master.md` · 계약: `ledger-design.md`
  ⭐ **방향 전환**: 「검증이 깨끗해지면 화면을 연다」에는 **끝이 없다**(그날도 새 문제가 셋).
  그리고 **Caleb 이 화면 없이 코드에만 의존**한다 ⇒ **화면은 검증의 보상이 아니라 검증 도구**다.
  📌 그날 찾은 셋 중 둘은 **사람이 이미 아는 일**이었다(`SKL01861` · `FG-00131`).
  · `inv_config`(기준선) · `inv_balance`(라이브 재고) · `inv_balance_vs_cin7`(⭐ 시점 컷오프)
  · `inv_stock_master(...)` RPC — 검색·창고·이상만·페이징. ⚠️ **`jsonb_agg`**(1,000행 캡)
  · `inv_balance_diffs` + `inv_snap_balance_diffs()` — 아침에 굳힌다(cron **jobid 18**)
    ⭐ `first_seen_on`(시간 축) · `acknowledged_*`(사람이 닫는 축)
  · `inv_ack_diff(...)` · `inv_diff_summary()` · `inv_bin_notes`(코멘트 · select·insert 만)
  · [실측] `inv_balance` **244ms · 14,432칸** ⇒ 일반 뷰로 충분(머티리얼라이즈드 불필요)
  · ⚠️ **Cin7 열을 나란히 둔다** — 8,060 SKU 는 다 못 보니 틀려도 모를 수 있다.
    「원장이 정답」이라 주장하지 않으면 틀린 숫자가 **위험이 아니라 보이는 것**이 된다
- ✅ **「확인됨」 축 (2026-09-01)** — WMS 조건 ②(매일 빨간불 금지).
  ⚠️ **「확인됨」(창고가 원인을 안다)과 「해결됨」(원장이 상쇄로 맞췄다)은 다르다.**
  📌 **「해결됨」 버튼은 없다** — 상쇄를 넣으면 **다음 회차에 목록에서 저절로 사라진다.**
  ⭐ 승계는 `first_seen_on` 과 같은 규칙(직전 회차) — 재발하면 확인을 새로 받는다.
  ⚠️ 알려진 의미론: 어긋남이 0이라 **회차 자체가 비는 날은 건너뛰고** 그 전 회차에서 승계한다.
  지금은 그런 날이 없어 실현되지 않았다 — **원장이 깨끗해질수록 그 날이 온다.**
- ✅ **재조회 창 (2026-09-02 · `inv-collect@2026-09-02.1`)** — 결함 E 처방.
  정본: `docs/sessions/2026-09-02-defect-e.md`
  · ②-a 에서 목록 행의 사건 날짜가 **최근 7일** 안이면 커서 아래라도 후보에 남긴다
  · 소스별 날짜: `adjustment`=`EffectiveDate` · `transfer`=`Departure`/`Completion` 중 늦은 것 ·
    `assembly`=`Date`→`Completion`→`WIP` 폴백. ⚠️ **목록에서 얻는다**(상세 전에 판정)
  · ⚠️ 날짜를 못 얻으면 종전 동작 + 축당 1회 경고
  · 응답 `recheck_window`·`recheck_window_days`·`recheck_window_sample`·`recheck_window_no_date`
  · [실물] `recheck_window 34` · 다음 회차에 `ST-01283` 의 재료 12행이 **자동으로 들어왔다**

**⑦ 수집 회차 — 캡·동결이 있었나** (2026-08-31 신설)
```sql
select source_key, ran_at at time zone 'America/Toronto' as ran_toronto,
       detail_capped, detail_capped_reason, detail_capped_remaining, hold_capped,
       cursor_stalled_alert, cursor_frozen_alert, write_skipped
from inv_collect_runs
where ran_at > now() - interval '24 hours'
  and (detail_capped or coalesce(hold_capped,0) > 0
       or cursor_stalled_alert is not null or cursor_frozen_alert is not null or not ok)
order by ran_at desc limit 20;
```
📌 **0행이면 그날 수집은 정상이다.** 결함 C·D 를 하루 늦게 안 이유가 이것이 없어서였다.
📌 회전 확인(롤링 재확인):
`select source_key, count(*), min(seen_at), max(seen_at) from inv_doc_state group by 1;`
— `min` 이 계속 당겨지면 회전이 돈다(트랜스퍼는 2.6시간 안에 최고령 갱신).

**⑧ bin 단위 대조** (2026-09-01 · 뷰로 통일)
```sql
select warehouse, count(*) as bin_pairs,
       count(*) filter (where diff <> 0) as mismatch,
       sum(abs(diff)) filter (where diff <> 0) as abs_gap
from inv_balance_vs_cin7 group by warehouse order by 1;

select sku, warehouse, bin, ledger_qty, cin7_qty, diff
from inv_balance_vs_cin7 where diff <> 0 order by abs(diff) desc;
```
⭐ **시점 컷오프가 들어가 언제 조회해도 같은 값**이다(2026-09-01 · §함정 표).
📌 [기준선 2026-09-02 아침] **토론토 4칸 · 에드먼튼 2칸 · 격차 23**
(9/1 아침 1,201칸 · 15,640 에서). ⭐ 이 축이 **결함 E 를 잡았다** — 창고 단위로는 안 보였다.
📌 카드용 요약은 `select jsonb_pretty(inv_diff_summary());` — `unack` 이 사람이 닫는 숫자다.
📌 **어긋난 칸의 원인을 모를 때는 「언제 생겼나」부터 찾는다**(⭐ **스냅샷 소급**) — `inv_snapshot` 이 기초일부터
매일 있으므로, 날짜별 스냅샷과 「그 시점 원장 잔고(기초 + 컷오프 델타)」를 대면
**`diff` 가 0에서 값으로 바뀌는 날**이 나온다.
[실증 2026-09-02] 남은 6칸이 셋으로 갈렸다 — 9/2(미규명) · 8/29(결함 C 혼란기) ·
8/20~8/24(초기 수집기 · bin 이동). ⭐ **그럴듯한 가설(「기초 경계 잔재」)을 깨는 데도 썼다.**

**⑨ 기초 스냅샷 경계 오더 재유입** (2026-09-01)
```sql
select l.doc_number, count(*) as rows, sum(l.qty_delta) as qty,
       min(l.created_at at time zone 'America/Toronto') as first_collected
from inv_ledger l
where l.doc_type='sale' and l.source='cin7' and l.occurred_on='2026-08-21'
group by l.doc_number
having min(l.created_at) >= '2026-08-22'
   and not exists (
     select 1 from inv_ledger m
     where m.source='manual' and m.doc_number = l.doc_number
       and m.occurred_on = '2026-08-21'
   )
order by 1;
```
**0행이면 정상.** 뜨면 **또 들어온 것**이다 — 상쇄하면 된다.
📌 판정 근거는 **「8/21 에 수집 안 됐다」** 하나다 — 그때 `Updated` 가 8/20 이었다는 뜻이고,
곧 모든 활동이 8/20 에 끝났다는 뜻이다.
📌 경계 오더는 **유한한 집합**(8/20 승인분)이라 다 나오면 끝난다.

- 🔵 **스냅샷 회차 로그 (2026-08-26 · `20260826130408` · `inv_snapshot_runs`)**
  §4-c 급감 검사의 **선행 조건**. 판정에 필요한 값이 `summary` 로 계산되고도 응답 후 사라지고
  있었다 — 「직전 회차와 비교」를 하려면 지난 회차가 남아 있어야 한다.
  · **기록 3축**: `list_total` · `pages_scanned` · `duration_ms`
  · ⚠️⚠️ **행 수는 판정 축이 아니다** — [실측] 08-26 정상 −66행 vs 08-24 불량 −42행
  · ⚠️ `insert_rows` = per-run 행 수. **`inv_snapshot` 의 `count(*)` 로는 못 얻는다**
    (같은 키 재촬영이 누적 합집합이 되므로)
  · ⚠️ **`aborted` 기록 · `dry` 미기록** — `logRun` 첫 줄에서 차단. 분기 순서상 `aborted` 검사가
    `dry` 보다 앞이라 **dry+중단이 로그 경로로 온다**(수동 dry 가 429·time 으로 끊기기 쉽다)
  · ⚠️ 로그 실패가 스냅샷을 죽이지 않는다(try/catch → `summary.run_log_error`)
  · ⬜ **판정 미구현** — 임계값은 정상 회차 분포를 며칠 본 뒤. 「거부 vs 경고」도 미결
    (거부하면 **그날 대조가 통째로 사라진다**)

**아침 점검 ④ 회차 로그** (2026-08-26~ · 모레부터 회차 간 비교 가능)
```sql
select ran_at at time zone 'America/Toronto' as ran_toronto,
       snapshot_key, ok, list_total, pages_scanned, duration_ms,
       received_rows, insert_rows, wrote
from inv_snapshot_runs order by ran_at desc limit 3;
```
⚠️ `ok=false` 이면 그 회차는 한 행도 안 썼다 — **그날 대조는 옛 스냅샷을 상대로 돈다.**

- 🔵 **원가(landed cost) — `inv_cost` + EF `inv-cost` (2026-08-27 · `20260827184936`)**
  조사·구현 정본은 `docs/sessions/2026-08-27-landed-cost-investigation.md` — **다시 조사하지 말 것.**
  Cin7 이 계산한 COGS 를 우리 원장 행 단위(**bin·CardID**)로 나눠 담는다.
  · ⭐ **원장과 달리 upsert 다 — append 가 아니다.** Cin7 을 베낀 값이라 재수집으로 다시 만들 수
    있고, Cin7 은 **재평가로 값을 바꾼다**(`+A/−A/+B`). append 로 담으면 `TR-04175` 와 같은
    이중 계상이 된다. 📌 **경계: 우리가 만든 사건 = 상쇄 / Cin7 을 베낀 것 = 덮어쓰기.**
  · ⚠️ **`since` 는 문서 선택에만** — `occurred_on` 필터 금지. 비용은 **입고보다 앞선 날짜로
    소급**된다(인보이스 날짜). 필터하면 유실된다.
  · **수집 축** = `UpdatedSince` + 커서(`inv_sync_state` `source_key='cost'`). 첫 시딩 8/20.
  · ✅ **실물 검증**: 47행 · **원장 조인 47/47**(`doc_number`·`line_ref`·`sku`·`warehouse`·`bin`) ·
    재계산 항등식 `ratio = 1.000000`(세금·할인·부분입고·bin 배분 네 축 동시)
  · ✅ **cron 등록 (2026-08-28 · [실측] jobid 16 · `33 4 * * *` UTC = 토론토 00:33)**
    ⚠️⚠️ URL 에 **`since=2026-08-20`** 이 반드시 있어야 한다 — 빠지면 기초 스냅샷 이전
    입고까지 원가가 들어온다. ⚠️ 킬 스위치 `select cron.alter_job(16, active := false);`
  · ⭐ **아침 점검 ⑥ — 원가가 빠진 입고** (2026-08-28 · 경고 대신 **결과로 잡는다**)
```sql
select l.doc_number, min(l.occurred_on) as received,
       count(*) as ledger_rows, sum(l.qty_delta) as qty
from inv_ledger l
left join inv_cost c
  on  c.doc_number = l.doc_number and c.line_ref = l.line_ref
  and c.sku = l.sku and c.bin = l.bin and c.warehouse = l.warehouse
where l.doc_type = 'purchase' and l.source = 'cin7'
  and l.occurred_on > '2026-08-20' and c.id is null
group by l.doc_number order by 2;
```
    📌 **이유를 묻지 않는다** — Simple 이든·캡에 걸렸든·자기검증에 막혔든 결과 하나로 잡는다.
    **해결하면 저절로 사라지는 목록**이라 닫거나 끌 장치가 필요 없다.
    ⚠️ EF 경고를 정교화하지 않기로 한 이유: `skip_simple_unverified` 는 대부분 **아직 안 받은
    오더**라 노이즈고, WMS 에 띄우는 것은 성격이 안 맞으며(창고 작업자는 PO 유형을 정하지
    않는다), 별도 테이블은 연 2건 사건에 과하다.
  · 👁 **`landed` 재방문이 마지막 미검증 지점** — 현재 `landed_rows` **0**. 통관·운임
    인보이스는 입고 후 **한두 달** 뒤에 온다. **잊지 않을 장치**:
    `select cost_kind, count(*) from inv_cost group by 1;` — **landed 가 처음 나타나는 날이
    검증일**이다(검증할 것: 소급 날짜가 `since` 에 안 걸리나 · 별도 행으로 오나 · 재평가 덮어쓰나).
  · ⬜ Simple Purchase 경로 미검증 · ⬜ freight `_95_` 정책 회계 확인 · ⬜ FIFO 레이어

- ⭐ **Simple 로 완료된 PO 도 나중에 Advanced 로 Convert 할 수 있다** ⇒ 「Simple 로 완료됨」은
  **영구 상태가 아니다.** 경고할 필요가 없고 **자가 치유된다**:
  `Convert → LastUpdatedDate 갱신 → inv-cost 가 UpdatedSince 로 포착 → 원가 기표 → ⑥ 목록 소멸`
  [실측 2026-08-28 `PO-01133`] 이 고리가 **3초**에 돌았다(`processed 1` · `rows_written 1`).
- ⚠️ **`CardID` 는 Convert 를 넘어 유지된다** — `PO-01133` 의 원장 행은 Simple 시절
  `StockReceived` 축으로, 원가 행은 Convert 후 `PutAway` 축으로 만들어졌는데 **`line_ref` 가
  같았다**(`90bc0304-…`). 실무의 예외가 원장·원가 정합을 깨지 않는다.
- [실측 2026-08-28] 4년치 1,231건 중 **Simple 인 채로 입고 완료된 것 7건**(`PO-01133`·`00893`·
  `00874`·`00583`·`00229`·`00081`·`00080`). 관행은 「대부분 Advanced 로 넘긴다」이지만
  **규칙이 아니다** — Simple 로 마무리해도 되는 오더가 실재한다.

**⑤ 진입 게이트 — 6개 전부 통과** (**정본은 설계 4부** 「commit=1 을 켜기 전에 닫아야 하는 것」):
```
☑1 CardID · 👁2 adv_no_putaway(관찰) · ☑3 재등장 전제 ·
🟡4 ON CONFLICT(코드 완료 — ⚠️ 실동작 미검증, 원장이 비어 있어 첫 회차 insert_skipped=0) ·
☑5 캡·페이싱 · ☑6 커서 seed
```
⇒ **단계는 ⑥ shadow 대조로 넘어간다.**
- ✅ **⑥ shadow 대조 가동 (2026-08-24 · 마이그레이션 `20260824130759` · cron 잡 12·13 등록 ·
  정본은 설계 4부 「⑥ shadow 대조 가동」)**: Cin7 현재고 = `inv-snapshot ?key=auto-compare` 재사용
  (리터럴일 때만 `YYYY-MM-DD-compare` 자동 생성 — `-initial` 은 여전히 수동만) · 대조 =
  RPC `inv_compare_run(p_key)`(DB 전용 — 기준선+사건 합 FULL JOIN compare 스냅샷, SKU×창고) ·
  verdict 최소 규칙(match 카운트만/IN_TRANSIT explained/나머지 unknown — **missing_event·
  calc_error 는 자동 판정 금지, 사람이 unknown 닫으며 기록**) · `inv_compare` 는 **diff≠0 만** ·
  `inv_compare_runs` 에 카운트+샘플+**cursors**(타이밍 차이 재확인 근거) · 보존 = compare 14일
  (**`-initial` 불가침 코드 강제**)·runs 90일. [로컬 검증] 테스트 6케이스 + 회귀(팩9·픽12) 통과.
  ⭐ [실측 2026-08-24 BMA15710] **Cin7 도 운송 중을 ON HAND 에서 빼고 별도 컬럼으로 관리** —
  IN_TRANSIT 합성 창고와 같은 모델. 원장 대조 토론토 910·에드먼튼 16·IN_TRANSIT 204 완전 일치
  = 스냅샷+사건 누적의 첫 증명. `inv-snapshot` 은 OnHand 만 읽으므로 **IN_TRANSIT 짝 없음이 정상**.
  ✅ **첫 회차 실측**: `compared_pairs 13,836 · match 13,835 · explained 316 · unknown 1`.
  ⚠️ **카운트 관계 — 셋을 더하지 말 것**: `compared_pairs = match + unknown` 이고
  **explained(IN_TRANSIT)는 pairs 밖의 별도 집계**다(RPC 의 `filter (warehouse <> 'IN_TRANSIT')`).
  첫 회차에서 13,835+316+1=14,152 로 배타 합산해 "정합이 안 맞는다"고 오독했다.
  ⚠️ 15분 간격(스냅샷 21분 → 대조 36분)은 **설계의 핵심**이다 — 아래 오탐 (b).

- ⚠️⚠️ **⑥의 첫 수확 = 비재고 SKU 가 재고로 쌓이던 결함 (`FINAL-SALE` · 2026-08-24)**:
  unknown 1건 = `FINAL-SALE`(원장 −34 · Cin7 0 · `SO-15097`). Cin7 `Type=Non-inventory`
  (파손품을 adjustment 로 뺀 뒤 판매하는 껍데기 SKU — Cin7 은 재고를 안 움직인다)인데
  판매 수집이 재고 사건으로 쌓았다. ⚠️ **`IsService` 와 `Type=Non-inventory` 는 다른 축**이라
  (cin7-api 스킬 15번) `IsService=false` 인 이 SKU 가 기존 필터의 **틈에 빠졌다**.
  ✅ **처방**: `inv_sku_types` 캐시(EF `inv-sku-types` · cron 일 1회 — ✅ **2026-08-26 등록 완료**
  `jobid 15`, 아래 항목) + 수집 게이트.
  · 게이트는 **`makeSink` push 진입부 한 곳**(since 필터 앞) — 6소스가 전부 그 지점을 지난다
    (배출구 = 공유 루프 2곳뿐) ⇒ **새 소스도 자동 적용**
  · 판정은 **「테이블에 있으면 차단」** — `product_type`·`is_service` **값을 보지 않는다**
    (로드가 `select=sku,refreshed_at`. 비-Stock 만 저장하는 것이 계약이므로 행의 존재가 곧 판정)
  · ⚠️ **캐시 미스는 fail-open(통과 + 경고)** — 원장은 shadow, **대조가 안전망**이다.
    차단은 정상 재고 수집까지 멈춘다. 경고 3분기(EMPTY·STALE·UNREADABLE) → `non_stock_gate`
  · ⚠️ **저장 범위 계약: Stock 은 넣지 않는다** — 넣으면 1,000행 캡에서 조용히 잘리고
    **잘린 비재고 SKU 가 게이트를 통과**한다. 마이그레이션 주석 + **800행 근접 경보** + `caps-ok`
  · **테스트 8케이스** `scripts/test-invcollect-gate.mjs` — 원본에서 `makeSink` 를 **실행 시마다
    원문 추출**해 검증(구현이 바뀌면 테스트가 따라온다). 정적 검사가 **세 번째 배출구를 잡는다**
  · 정정은 **상쇄 행**(`source='manual'`·`event_type='manual_reversal'`) — ⚠️ **물리 삭제 금지.
    append-only 의 첫 위반이 「사소한 1건」인 것이 가장 위험**하다
  📌 [실측] 비-Stock 45건(`Non Inventory` 2 + `Service` 43). `is_service` 는 **전 행 false** —
  `productList` 응답에 그 필드가 없어 기본값일 뿐 판정에 안 쓰인다(**정리 후보**).
  · 📌 **[실증 2026-08-26 전수] `Type='Service'` 47건이 전부 `IsService=false` 다.**
    두 축이 다르다는 것이 표본 하나가 아니라 **전수로** 확인됐다 — `FINAL-SALE` 은 특이 사례가
    아니라 **일반 패턴**이었다. ⇒ 게이트가 「테이블에 있으면 차단」(`product_type`·`is_service`
    **값을 보지 않음**)인 것이 옳았다. `is_service` 를 판정에 썼다면 **49건을 전부 통과**시켰을 것이다.
  · ⚠️ `inv_sku_types` 컬럼: `sku` · `product_type` · `is_service` · **`refreshed_at`**
    (⚠️ `updated_at` 이 아니다 — 2026-08-26 에 추측으로 쿼리를 써서 에러를 냈다).

- ⚠️⚠️ **대조를 잘못 돌리면 오탐이 난다 — 같은 날 3회차 실측(unknown 1 → 134 → 165, 진짜는 1건)**:
  **(a)** 같은 키로 재촬영하면 `ignore-duplicates` 라 **첫 값이 남는다**(`wrote: 5` 로 끝나고
  13,800행은 아침 값). 재촬영은 **다른 키**로.
  **(b)** 낡은 스냅샷에 최신 원장을 맞추면 그사이 판매가 원장에만 반영돼 **134건이 어긋난 것처럼**
  보인다([실측] 차이가 당일 판매 사건과 정확히 일치 — 원장은 맞고 기준이 낡았다).
  ⇒ **자동화가 준비된 것을 수동으로 급히 돌리지 말 것.** cron 15분 간격이 이걸 구조적으로 막는다.
  **(c)** ⚠️ **스냅샷이 조용히 불완전할 수 있다 — 처방 절반(기록 완료 · 판정 미결).** [실측] 밤 회차가 목록 21,877
  (아침 22,079) · 22페이지(23) · 13,787행 — `truncated:false`·`rate_limited:false` 인데
  **Cin7 이 애초에 적게 줬다**. `list_total == received_rows` 라 **all-or-nothing 가드가 구조적으로
  못 잡는다**. [실증] `AS93125` 토론토 2,662개가 그 스냅샷에만 없었다.
  ⚠️ **기준선(`-initial`)이 이렇게 찍히면 원장 전체가 잘못된 출발점을 갖고, 어느 대조에서도
  드러나지 않는다.** 🔵 **기록은 완료**(`inv_snapshot_runs` · 2026-08-26 — 위 회차 로그 항목) ·
  ⬜ **판정 미구현** = 직전 회차 대비 `list_total` 급감 검사(축 정리는 아래).

⚠️⚠️ **[실측 2026-08-28 · 첫 뺄셈] 축은 `list_total` 하나뿐이다.**

| 축 | 정상(8/28) | 불량(8/24 밤) | 판정 |
|---|---|---|---|
| **`list_total` 일일 변화** | **+33** | **−202** | ⭐ 유일한 축 |
| `duration_ms` | 45.1초 | 104초 | 보조 |
| ~~`pages_scanned`~~ | 23 | **22** | ❌ `list_total÷1000` 올림값 |
| ~~`insert_rows`~~ | −45 | −42 | ❌ 다른 물건 · 방향 무관 |

· ⚠️ **`list_total` 과 `insert_rows` 는 반대로 움직인다**(+33 vs −45) — 전자는 **Cin7 의
  product availability 행 수**, 후자는 **우리가 합쳐 만든 재고 행 수**다. 다른 물건이다.
· ⚠️ **`pages_scanned` 는 독립 정보가 아니다** — 22,009 는 22,000 을 넘어 23페이지가 됐을 뿐이고,
  **8/24 불량(21,877)과 8/27 정상(21,976)은 똑같이 22페이지**였다.
· ⬜ 임계값은 정상 표본 2점뿐이라 아직 정하지 않는다.
- 👁2 는 **관찰 대기**(WMS 는 put-away 없이 Apply 하지 않아 우리 시스템이 만들 수 없는 상태.
  ⚠️ Advanced 기본값을 켜면 게이트로 복귀) · 🟡4 만 **실동작 미검증**으로 남는다.

- ✅ **`inv-sku-types` cron 등록 완료 (2026-08-26 · [실측] jobid 15 · `26 3 * * *`)**
  08-24 에 「잡 14」로 문서화했으나 실제로는 등록되지 않았던 항목(발견 경위: WMS 자동 Hold 의
  실물 jobid 가 14 였고, **12·13 다음이 14 라는 사실 자체가 미등록의 증거**였다). 백로그 소진.
  · ⚠️ **킬 스위치**: `select cron.alter_job(15, active := false);`
  · ⚠️ **확인은 결과물로만** — `cron.job_run_details` 의 `succeeded` 는 아무것도 보장하지 않는다.
    유일한 증거는 `refreshed_at` 갱신이다:
    `select count(*), max(refreshed_at) from inv_sku_types;`
  · [실측 2026-08-26 수동 실행] **49행**(Service 47 + Non Inventory 2) · 15콜 · 15초 ·
    `total=received=14,754`(전량 수신) · `added`/`removed`/`type_changed` 전부 없음
    ⇒ 미등록 기간에 새 비재고 SKU 가 생기지 않았다 — **운이 좋았던 것이지 안전했던 것이 아니다.**
  · 📌 **첫 cron 실행 = 토론토 23:26**(03:26 UTC · 여름 −4). 수동 실행(15:31)과 시각으로 구별된다.

⚠️⚠️ **`since=<스냅샷 날짜>` 는 매 호출에 필요하다 — cron URL 6줄에 `since=2026-08-20` 이 박혀 있다.**
코드가 `occurred_on > since`(**엄격히 큼**)를 쓰므로 8/20 전체가 제외된다 — 그날 낮 사건은 스냅샷에
이미 녹아 있다. `since=2026-08-19` 로 하면 8/20 낮이 **이중 계상**된다.
📌 **스냅샷을 다시 찍으면 cron 6잡의 `since` 를 손으로 갱신할 것**(테이블 영속화 대신 URL 을 고른 대가).

⚠️ **`TIME_BUDGET_MS=120초` 안에 6종을 다 돌 수 없다**(첫 소스가 예산을 소진 → 나머지는
`aborted: "time budget exhausted before this source"`) → **소스별 cron 분리로 해결했다**.
📌 **시간 가드에 걸린 것은 페이싱 실패가 아니다** — 페이싱 판정 기준은 `rate_limited` 다.

⚠️ **회차 소요는 「후보 수 ÷ 캡」으로 추정하면 틀린다 — 가르는 것은 「상세를 봐야 하는가」다.**
[실측 2026-08-20 가동] `adjustment` 는 후보 586건이 **한 회차에 끝났다**(`detail_fetched: 0` —
`skip_since` 가 목록 레벨에서 판정된다) · `transfer` 는 두 날짜를 봐야 해서 캡 40에 걸린다
(`detail_capped_remaining: 1,787`, 5회차에 214건 전진).

⚠️ **`precision_skipped` 가 「목록은 많은데 후보가 0」을 설명한다** — `UpdatedSince` 는 날짜 단위라
겹치게 받고(커서 − 1일) 커서 **시각** 이전 갱신분을 우리 쪽에서 다시 거른다. [실측] 발주 88 =
45(서비스 전용) + **43(precision)** · 판매 273 = **179(precision)** + 78(미출하) + 16(void).
📌 **검증 커맨드에 이 필드를 넣을 것** — 없으면 「왜 안 들어왔지」를 추적할 수 없다.

⚠️⚠️ **`cron.job_run_details` 의 `succeeded` 는 아무것도 보장하지 않는다 — 세 번 겪었다:**
`inv-sku-types` cron 미등록(08-24 · 돌지 않는데 succeeded) · `inv-cost` placeholder
(08-28 · 401 인데 succeeded) · **결함 C**(08-29 · 350회+ succeeded인데 수집 동결).
⇒ **확인은 언제나 결과물로.** 커서 전진 · 행 수 · `refreshed_at` 갱신.
📌 **2026-08-31 부터는 `inv_collect_runs` 가 그 창구다** — 회차 결과가 남으므로
「돌았는데 아무 일도 안 했다」를 아침에 본다. ⚠️ 다만 **`dry` 는 안 남는다**(의도).
(HTTP 요청을 띄운 것까지만 본다 — cron 검증의 유일한 증거는 `inv_sync_state.last_run_at` 갱신 +
`last_cursor` 전진이다.)
⚠️ **원장 쓰기 뒤 `insert_skipped ≠ 0` 은 정상**(재수집) · `conflicts_detected ≠ 0` 이면
`select * from inv_conflicts order by detected_at desc`. **첫 회차는 원장이 비어 `insert_skipped` 0** —
두 번째 회차부터 의미가 있다. ⚠️ `R.written` 의미가 「시도 행수」 → **「실삽입 행수」**로 바뀌었다.
(~~CardID 재수집 안정성~~ 은 2026-08-18 저녁 PO-01117 실측으로 닫힘 — Convert 를 통과해도 유지.)
⚠️ **PA 블록은 `DRAFT` 로 생성 → 승인되면 `AUTHORISED`.** [실측] PO-01117 은 Convert 직후 DRAFT,
**다음 날 아침 AUTHORISED** — 화면이 먼저 바뀌고 API 가 따라온다(**지연 확정**, 2026-08-19).
⇒ `putaway:DRAFT` 는 오류가 아니라 진행 중 상태고, 원장은 다음 회차에 기표한다(유실 아님).

---

## 2. ⚠️ 반복해서 틀렸던 것 (가장 중요)

| 함정 | 진실 |
|---|---|
| 커서 아래로 내려간 문서가 편집되면? | ⚠️⚠️ **결함 E — 영영 못 본다.** ②-a(문서번호 커서)는 커서 아래를 `skip_before_floor` 로 떨어뜨린다. [실사고 `ST-01283`] 8/31 13:11 수집 시 완제품 3행이었는데 9/1 에 실무가 「완제품이 아니라 재료였다」로 정정해 **재료 12행으로 통째로 바꿨다**(ref `"Shrikage - UNI (EDM Transfer Adjustment For ST-01283)"`). 원장은 9/2 아침까지 옛 3행을 들고 있었다. ⇒ ✅ **최근 7일 재조회 창**(`inv-collect@2026-09-02.1`) — 목록 행의 사건 날짜가 창 안이면 커서 아래라도 후보에 남긴다. ⚠️ 비용은 `inv_doc_state` 가 지운다. ⚠️ **창 문서는 커서에 관여하지 않는다** — 전진값으로 쓰면 커서가 후퇴하고 hold 로 세우면 위쪽 전진을 막는다. 📌 ②-b 는 해당 없다(`UpdatedSince` 라 편집되면 목록에 다시 나온다) |
| ⚠️⚠️ 소멸 감지가 못 보는 축이 있나? | **있다 — 둘이다.** 판정에 「언제 편집됐나」가 필요한데 **목록에 그 값이 없는 축**이 있다. `stockTransferList` 만 `LastModifiedOn` 을 준다. `stockAdjustmentList`(`TaskID`·`EffectiveDate`·`StocktakeNumber`·`Status`·`Account`·`Reference`·`Comment`)와 `finishedGoodsList`(`TaskID`·`AssemblyNumber`·…·`Date`·`Status`·`Notes`)에는 **없다.** ⇒ **`adjustment`·`assembly` 의 라인 삭제·교체는 아무도 못 본다.** [실측 2026-09-02] `missing_lines_skipped_no_lmo` **33 = `detail_fetched` 33** — 조회한 문서 전부가 A 집합에서 빠졌다. ⭐ **`bin` 단위 대조만이 잡는다.** 📌 부수 효과: 그 둘은 `inv_doc_state` 도 같은 값을 쓰므로 **매 회차 상세를 다 부른다**(`skipped_unchanged 0`) — 비용은 크지만 덕분에 재조회 창이 잘 작동한다. ⬜ 처방 후보: `LastModifiedOn` 은 **판정 기준**이지 A 집합의 재료가 아니고, 그 둘은 전량 상세를 부르므로 **재료가 이미 있다** ⇒ `lmoRaw` 조건만 완화하면 될 가능성이 크다(안전장치 `listAborted`·`truncated`·`detailCapped` 는 이미 있다) |
| 원장과 Cin7 을 대조할 때 시점을 어떻게 맞추나? | ⚠️⚠️ **잘못 자르면 세 번 틀린다.** [실측 2026-09-01] 같은 날 같은 쿼리가 **9 · 49 · 128 · 475 · 161 · 7 · 9** 를 냈다. Cin7 스냅샷은 **01:21 의 한순간**인데 원장 델타는 계속 쌓이기 때문이다. ❌ **날짜 필터(`occurred_on < 오늘`)는 답이 아니다** — 01:21 스냅샷이 그날 00:00~01:21 사건을 **이미 포함**하는데 날짜로 자르면 그것까지 뺀다. ⇒ ⭐ **최종 규칙 셋을 함께 쓴다**: `source='manual'`(정정은 뒤늦게 적은 과거 사실) **or** `occurred_on < 스냅샷의 토론토 날짜`(⭐ **과거 사건은 늦게 수집돼도 자르지 않는다** — Cin7 이 이미 반영했다) **or** `created_at <= taken_at`(당일 사건은 수집 시각이 가른다). ⚠️ 세 조건이 **서로를 보완한다** — 하나만 쓰면 반드시 틀린다. 정본: `docs/sessions/2026-09-01-stock-master.md` §3 |
| ⭐ 「과거 사건을 오늘 수집」이 왜 계속 생기나? | **커서가 밀리거나(결함 C·D) 재수집하거나 bin 규칙을 바꾸면** `occurred_on` 이 과거인 행이 오늘 `created_at` 으로 들어온다. [실사고] 트랜스퍼 bin 을 채우자 `cin7 A070401 −60`(8/21 사건)이 그날 낮에 수집됐고, `created_at` 컷오프가 그것을 잘라 **상쇄와 재기록의 짝 중 반쪽만** 남았다(`WTA00219` diff +60). ⇒ 컷오프의 축은 **수집 시각이 아니라 사건 시각**이다 |
| `manual` 정정을 컷오프에서 빼도 되나? | ⭐ **빼야 한다.** 정정은 **사건 시각이 과거인데 기록 시각은 현재**다. [실사고 `ANN01111`] 라이브 20(Cin7 과 일치)인데 컷오프가 상쇄를 잘라 `at_snapshot −4 · diff −24` 로 **상쇄 전 상태로 되돌렸다**(`total 157` = 그날 아침 상쇄한 경계 오더 행 수). ⇒ **고쳤으면 대조가 바로 맞아야** 한다. ⚠️ **대가**: `manual` 을 잘못 넣으면 대조가 **즉시** 그것을 정답으로 받아들인다 — 정정 전에 근거를 `raw` 에 남기는 관례가 그래서 중요하다 |
| 원인 모를 어긋남을 상쇄해도 되나? | ⚠️ **안 된다 — 그건 원장을 Cin7 에 맞추는 것이다.** 그러면 대조가 항상 0이 되어 **아무것도 못 잡게 된다.** 지금까지 한 상쇄는 **전부 원인을 알고** 했다(`ST-01283` 편집 확인 · `FG-00133` VOID 확인 · 경계 오더의 승인 시각 확인). ⇒ 원인을 모르면 **`inv_ack_diff` 로 「확인됨」 표시**만 한다 — 숫자는 틀린 채로 두고 `unack` 만 0으로 간다. 그래야 **내일 하나 늘어나는 것**을 놓치지 않는다. 📌 누적된 미상은 **재기준선**이 지운다. ⚠️ 다만 사각지대를 메우기 전에 재기준선을 잡으면 같은 부류가 다시 쌓인다 |
| 뷰를 만들 때 `anon` 을 신경 써야 하나? | ⚠️⚠️ **반드시.** 뷰는 **소유자 권한으로 실행**되므로(`security_invoker` 없이) `anon` 에 열어두면 `inv_ledger`·`inv_snapshot` 의 `anon` 회수를 **우회한다.** `anon` key 는 커밋되는 값이라 **실질 공개**다. ⇒ `revoke all ... from anon` 을 **`create or replace` 할 때마다** 다시 건다 |
| 수집한 뒤 Cin7 에서 문서가 **취소**되면? | ⚠️⚠️ **아무도 안 본다 — 구조적 구멍이다.** 수집 시 `VOIDED` 는 제외하지만(`skip_voided`), **이미 원장에 들어온 문서가 나중에 취소되면 상쇄가 안 된다.** `raw.header.status` 의 `COMPLETED` 는 **수집 당시 값**이라 그 뒤의 취소는 어디에도 없다. [실사고 2026-09-01 `FG-00131`] 8/28 13:13 수집 시 COMPLETED → 지금 VOIDED. 검산이 정확히 맞았다 — `UNF18050` 기초 84 − 우리 18 = 66 인데 Cin7 은 72 로 **한 건 몫(6)이 남았다.** ⚠️ **빈도와 기제**: 조립 132건 중 VOIDED 86건이지만 **업무상 취소가 아니다 — Cin7 의 기계적 동작이다.** 기제 둘: **①SO 편집 → Cin7 이 기존 자동조립을 VOID 하고 재생성**(`Notes` 가 `by System` · SO 묶음 30개가 「VOIDED → COMPLETED」 짝) · **②트랜스퍼 픽용 SO 를 VOID**([실증 `SO-14692`] `wms_orders` 에 `ASUNG EDM TRANSFER` 로 실재 · 딸린 `FG-00115~00120` 6건 전부 VOID — **설계된 동작**). ⚠️ 조립 자체는 **월 20건 안팎의 드문 작업**이다. ⭐ **그리고 우리가 걸리는 조건은 좁다** — 수집 주기(1시간) 안에 상태 변화가 안 끝날 때뿐이고, [실측] **8월 VOID 12건 중 잡힌 것은 `FG-00131` 하나**다(13:13 수집 → 16:13 에 재생성). ⚠️ **다만 기제 ②는 창이 길다** — 픽 시작과 SO VOID 사이가 몇 시간~며칠이라 그 사이에 수집이 들어간다. **트랜스퍼 픽은 정기적이므로 ①보다 잘 걸릴 수 있다.** ⚠️ **그리고 전 축 공통이다** — 판매·트랜스퍼·조정 모두 같은 구조(트랜스퍼 화면에도 Void 버튼이 있다). 📌 **소멸 감지(`inv_missing_lines`)는 라인 삭제만 잡는다** — 문서 전체 취소는 다른 축이다. ⬜ 처방 미착수 |
| `Adjustment` 가 증감분? | **아니다. 조정 후 목표 수량.** 증감 = `Adjustment − QuantityOnHand` |
| `NewStockLines` 도 같은 규칙? | **아니다.** `Quantity` 가 그대로 증가분. 섞으면 원장이 통째로 틀림 |
| `StockOnHand` 가 수량? | **아니다. 평가액.** 원장 기준값은 `OnHand` |
| 재고가 픽/팩에 빠지나? | **아니다. Ship 시점.** 픽·팩·Finalize 는 `Allocated` 일 뿐 |
| 문서 번호로 순서를 정하면? | **안 된다.** 접두어가 달라 비교 무의미. **유입(+) 먼저, 유출(−) 나중** |
| `Bin=null` 행이 창고 집계행? | **아니다.** 빈 미지정 재고 자리. 99.8%가 0이고, 0이 아닌 14행은 진짜 재고 |
| UOM SKU 도 재고가 있나? | 평소 없다(`OnHand=0`·`Available` 만 파생). 다만 **구조상 가질 수는 있다** |
| `ProductID` 가 라인 식별자? | 상품 ID 다. 같은 SKU 두 줄이면 겹침. **다만 실무상 안 겹쳐서 line_ref 로 씀** (⚠️ 판매 예외 — 5절) |
| 발주 블록 `Status` 는 DRAFT 만 제외? | **아니다 — 그리고 어느 배열의 상태를 보느냐가 먼저다(08-18).** 화이트리스트 = **PA 축 기준 `AUTHORISED` 만** + 미지값 경고. ~~SR 기준 AUTHORISED·`""` 통과(08-17)~~ 는 폐기 — 빈 문자열 예외의 근거 PO-01128 은 빈 상태가 **SR 블록**이었다(PA 는 AUTHORISED 84줄). SR 상태로 거른 "−90행 유령 재고 차단" 판정도 무효(실재 입고를 지운 것) |
| 발주 라인 수량은 나중에 바뀔 수 있는가? | **그렇다(2026-08-19).** PO 를 닫으려면 인보이스 수량과 정확히 같아야 해서 **PO 수량을 인보이스 수량으로 채운다** — [실측] PO-01117 PA `CAN01620` **168→192**(`CardID`·bin·문서번호 전부 동일, 수량만). 차액은 **stock adjustment 로 되돌아온다**(`ST-01220` −24/+24) — 한 입고가 `po_in`+`adjustment` **두 소스에 걸친 사건**이 된다. ⚠️ 유니크 키가 같아 `DO NOTHING` 이면 새 수량이 조용히 버려진다(설계 정본 4부 3번) |
| 발주 입고는 `StockReceived` 를 읽으면 되나? | **아니다(2026-08-18 확정).** Advanced = **`PutAway`** / Simple = `StockReceived`. SR 은 ① `LocationID` 가 null 이거나 창고 GUID 라 **bin 이 구조적으로 없다** ② `Status` 가 stock receiving 단계의 **워크플로 상태**라 재고 반영 여부가 아니다(PO-00703 SR=DRAFT/PA=AUTHORISED · PO-01131 SR=NOT AVAILABLE/PA=AUTHORISED 3,570u). SR·PA 는 같은 입고의 두 표현 — 둘 다 읽으면 두 배 |
| 목록 `StockReceivedStatus` 로 후보를 좁히면? | **안 된다.** 상세 블록 상태와 **상관이 없다**(양방향 불일치 — PO-01131 목록 AUTHORISED/상세 NOT AVAILABLE ↔ PO-00848 반대). 표본 6건 중 4건(12,552u)이 실재 입고인데 문서째 유실됐다. 판정 권한은 상세 한 곳 — 목록 값은 분포만 센다 |
| 트랜스퍼도 bin 을 가져오는가? | ⚠️⚠️ **[정정 2026-08-31] 「트랜스퍼가 bin 을 안 읽는다」는 틀렸다.** 같은 창고 안 bin 이동은 이미 헤더에서 읽고 있다([실측] `TR-04166` `E050202 → E050103` · 335행). **문제는 창고 간 이동에 헤더 bin 이 아예 없다는 것**이었다(창고 이름만 온다) ⇒ 출발 bin 은 **WMS 픽에서** 얻는다(아래 항목 · 정본 `docs/sessions/2026-08-31-transfer-departure-bin.md`). 헤더 형태는 그대로다: `FromLocation`/`ToLocation` 이 **`"창고: bin"` 문자열**([실측] TR-02645 `"Asung - Edmonton: EZ01Pallet03"`→`"Asung Trading Inc.: F0300PALLET01"`) · **문서 하나 = bin 하나 → bin 하나**라 라인에 없는 게 정상. ⚠️ 창고 판정은 **`resolveLoc` 가 GUID 로 푼다** — `": "` 콜론 파싱은 금지 관례다(이름이 바뀌면 조용히 깨진다). ⚠️ `Lines[].ProductCustomField1/2` 는 상품 마스터 필드 — 쓰지 말 것(TR-02644 null). ⚠️ ~~"라인에 bin 필드가 없다=데이터 없음"~~ 은 오판이었다(응답 한 부분만 보고 판단 — 발주 SR/PA 와 같은 실수) |
| `saleCreditNoteList` 행은 CN 단위? | **아니다. sale 단위.** 목록 `RestockStatus` 로 거르면 같은 오더의 AUTHORISED CN 이 유실 — 판정은 상세 `CreditNotes[]` 순회 한 곳만 |
| `Restock[]` 이 비면 DRAFT? | **아니다.** AUTHORISED+빈 배열 실재(표본 하나 CR-00024 의 일반화였다) — 판정은 배열 실제 길이로 |
| `UpdatedSince` 로 받으면 그 기간 이벤트만? | **아니다. 갱신 축과 이벤트 날짜는 분리** — 8월 갱신 문서가 4월 이벤트를 품는다. **`since=`(이벤트 필터)가 스냅샷 경계 방어 — 쓰기 켤 때 필수.** `from_since` 는 커서 씨앗으로 딴 것 — 혼동 금지 |
| `SR=[""]` 빈 상태 블록을 이상 신호로 볼 것인가? | **아니다. Convert 를 거친 문서의 정상 흔적**(라인이 PA 로 옮겨간 뒤 껍데기만 남는다 — PO-01117 실측: Convert 직후 SR 0줄·PA 51줄, CardID 동일) |
| 원장이 재수집하면 문서 변경을 다 잡나? | **아니다 — `inv_conflicts` 는 「변경」 전용이다.** 삭제된 라인은 **다시 오지 않으므로 비교 대상 자체가 없다**(재수집 세트에 없는 것은 아무 일도 일으키지 않는다). ⇒ 소멸은 `inv_missing_lines`(B−A 집합 뺄셈 · 2026-08-25 TR-04175 실사고)가 잡는다. 📌 `inv_conflicts` 가 오래 0인 것은 「감지가 안 된다」가 아니라 「수량 변경이 아직 없었다」일 수 있다 — 두 가설을 섞지 말 것 |
| 커서가 지나간 문서는 다시 안 읽나? | **아니다 — 커서는 비종결 문서 앞에서 멈춘다.** `processed`·`skip_voided`·`skip_since` 만 넘어가고 `processed_nonterminal`(IN TRANSIT)·`hold_*` 는 커서를 잡는다. ⇒ **편집 가능한 기간 = 재읽기되는 기간**이라 소멸 감지를 붙일 자리가 구조적으로 보장된다(새 수집 축 불필요). ⚠️ 단 커서 **위쪽** 문서는 매 회차 전부 다시 훑는다 — 교착이 길어지면 API 예산을 계속 쓴다. ⚠️⚠️ **[정정 2026-09-02] 「편집 가능한 기간 = 재읽기되는 기간」은 커서 아래에서 깨진다** — 커서가 지나간(=종결된) 문서도 실무가 편집한다(결함 E · `ST-01283`). 이 표 맨 위 「커서 아래로 내려간 문서가 편집되면?」 행이 정본이다 |
| 원가도 원장처럼 append 로 담나? | **아니다 — `inv_cost` 는 upsert 다.** 원장은 「우리가 만든 사건」이라 상쇄로만 고치지만, 원가는 **Cin7 의 계산 결과를 베낀 것**이고 언제든 다시 가져올 수 있다. Cin7 이 재평가로 값을 바꾸므로 append 로 담으면 옛 값이 남아 이중 계상된다. 📌 **하드 플립 시점의 값이 원가의 기초**가 된다(`inv_snapshot` 이 수량에 한 역할과 같다) — 그 이후에는 우리가 계산해 쌓으므로 그때는 append 가 맞다 |
| `Updated` 로 커서를 옮기면 되나? | ⚠️ **동률 그룹이 캡보다 크면 영구 동결된다(결함 C · 2026-08-29 실사고).** [실측] 밀리초까지 같은 `Updated` 를 가진 판매 문서 **238건** — 캡(40건/120초)이 그 안에서 끝나니 마지막 처리 문서의 `Updated` 가 늘 커서와 같아 제자리였다. **캡을 올려도 안 된다**(238×1200ms=286초 > 예산 120초). ⇒ 커서 단위는 **`<Updated>\|<문서식별자>`** 다(`inv-collect@2026-08-30.1`). 📌 원인은 **Cin7 플랫폼 일괄 갱신**이라 통제 불가·재발 전제(History 에 그 시각 활동이 없다) |
| `occurred_on`(ShipmentDate)이 재고가 빠진 시각인가? | ⚠️⚠️ **아니다.** [실측 `SO-15041`] 출하 승인은 **8/20 16:29**(Cin7 이 그때 차감)인데 API `ShipmentDate` 는 **8/21** 이다 — 사용자가 적는 날짜다. ⇒ **기초 스냅샷(8/20 19:42) 경계를 넘는 어긋남을 `since` 필터가 못 막는다.** 2026-08-30 회수에서 4문서 522행이 **이중 차감**됐고 상쇄로 정정했다. 📌 트랜스퍼 「since 경계 아티팩트」의 판매판이다 |
| 커서가 비종결 문서 앞에 멈추면 그 위는 다 처리되나? | ⚠️ **아니다 — 캡을 넘으면 뒤쪽은 영영 안 들어온다(결함 D).** [실측 2026-08-31 transfer] `processed 36 · processed_nonterminal 3 · hold_capped 120`. `TR-04330`(8/28 · −144)이 그 안에 있어 누락됐고 `BMA15710` 대조 차이 144와 정확히 일치했다. ⚠️ 8/27 에는 `capped_remaining 0` 이었다 — **문서가 늘면서 조용히 넘어간다.** 그리고 `processed 36` 은 **이미 원장에 있는 완료 문서를 매 회차 다시 읽는 낭비**다 |
| 완료된 문서를 건너뛰면 되나? | ⚠️ **판정 기준은 「완료됐나」가 아니라 「안 바뀌었나」다.** 완료 문서도 나중에 편집된다(`TR-04175` 가 그랬다). ⇒ `inv_doc_state` 에 문서별 `last_modified` 를 기록하고 값이 같을 때만 skip 한다. [실측 2026-08-31] 세 축 모두 그 값이 **라인 편집에 반응한다**(`SO-15440` 삭제 3분 뒤 · `PO-01117` 수량변경 3주 뒤). ⚠️ **비종결은 절대 skip 금지**(도착 시 반응 여부 미확인) · ⚠️ **skip 문서도 커서 전진에 포함** · ⚠️ `last_modified` 는 **문자열 그대로**(발주는 `Z` 가 없다) |
| 창고 간 트랜스퍼의 출발 bin 을 API 로 얻을 수 있나? | ⚠️ **없다.** [전수 확인 2026-08-31] `stockTransfer`→`Lines` · `Order.Lines` · `stockTransfer/order`→`Lines` 가 **키까지 완전히 동일**하고 bin 이 없다. 공식 `apib` 의 **Stock Transfer Line Model 에 정의 자체가 없다.** 엔드포인트 **102개 전수**에 **재고 이동 조회 API 가 존재하지 않는다.** 픽용 SO 는 **VOID 하면 `Pick`/`Pack`/`Ship` lines 가 0**이 된다. ⇒ **우리 WMS 에서 얻는다**(`wms_order_lines.bin_location` · 112/112 실증) |
| 화면에 보이는 bin 을 믿어도 되나? | ⚠️ **화면과 Export 가 다르다.** 트랜스퍼 화면의 `LOCATION` 컬럼은 **현재 재고 조회**다(`QuantityOnHand` 처럼 참고값 · 4/4 현재 bin 과 일치). **Export CSV 의 `Location` 이 문서 데이터**다 — [결정적 실측 `TR-04166`] CSV 는 출발 bin `E050202` 를 주는데 그 제품은 지금 `E050103` 에 있다 |
| 「비슷한 것」으로 이어 붙여도 되나? | ⚠️ **안 된다 — 틀린 값을 채우느니 비워둔다.** [실증 2026-08-31] `TR-04331` Reference 에 **존재하지 않는 `SO-15834`** 가 손으로 적혀 있었다(실제 `SO-15483` · 숫자 두 개 바뀐 오타). 폴백이 없었기에 시스템이 **조용히 틀리지 않고 `so_missing` 으로 이름을 대며 멈췄다.** 「손님 이름+날짜」·「비슷한 번호」 같은 폴백을 만들지 말 것 |
| `ShipmentDate` 를 차감 시각으로 믿어도 되나? | ⚠️ **아니다 — 사용자 입력 날짜다.** [실사고 2026-08-30 · 재발 2026-09-01] 8/20 저녁 출하 승인 → Cin7 차감 → 기초 스냅샷(19:42)이 그 값을 찍음 → `ShipmentDate` 는 8/21 이라 `since` 필터를 통과 → **이중 차감.** 08-30 에 4문서(522행), 09-01 에 3문서(157행)를 상쇄했다. ⚠️ **재발 경로**: Cin7 이 대량 갱신하면(8/28 · 8/31 오후 — 사흘 간격) 옛 문서가 재유입되고 그때 경계 오더가 **처음** 들어온다. ⇒ 아침 점검 ⑨ |
| 트랜스퍼 출발 bin 을 `wms_order_lines.bin_location` 으로 채워도 되나? | ⚠️ **그 값은 오더 유입 시점 것이다.** 유입~픽 사이에 `wrong_location` 정정이나 재배치가 있으면 **낡는다.** [실사고 2026-09-01 `SKL01861`] 유입 8/20 18:50 `D110302` → **8/21 10:27 `TR-04169` 가 `D110301` 로 옮김** → 14:52 픽 → Cin7 은 `D110301` 에서 뺐다. ⇒ **잔고 규칙 우선 + WMS 교차**로 바꿨다(`inv-collect@2026-09-01.1`). ⚠️ **WMS 에서 더 얻을 것이 없다** — 픽 화면도 sticky 도 같은 낡은 값이다(WMS 세션이 코드로 확정 · sticky 는 05:00 배치라 당일 정정을 모른다). [실측] 이 부류 빈도 **596건 중 1건**(`transfer_bin_wms_stale`) |

### ⚠️ 커서 결함 계보 — 전부 「캡에 걸렸는데 커서가 안 나갔다」

| | 내용 | 가드 |
|---|---|---|
| **A** (08-17) | `UpdatedSince` 를 날짜로 자르는 탓에 후보 집합이 안 줄어 앞 40건 반복 | 전체 정밀도 필터 |
| **B** (08-17) | `Updated` 가 null 인 문서(정렬 맨 앞)가 캡을 채움 | `cappedNoUpdated` → commit 차단 |
| **C** (08-29) | **`Updated` 동률 그룹이 캡보다 크다** | 커서 tie-breaker + `cursorStalled` |
| **D** (08-31) | ②-a 비종결 홀드 + 캡 → 뒤쪽 문서 영구 누락 | ✅ `inv_doc_state` — 변경 없는 문서는 상세 미조회(39→5) |
| **E** (09-02) | ②-a 커서 아래 문서가 **편집돼도 다시 안 읽는다** | ✅ 최근 7일 재조회 창(`recheck_window` · `inv-collect@2026-09-02.1`) |

📌 **A·B·C 가 전부 같은 증상**이었고 원인별 가드는 매번 사촌을 놓쳤다 ⇒ **증상 가드**를 넣었다:
`cursorStalled = detailCapped && cursorWouldBe <= cursorBefore` → 경고 + commit 차단.
⚠️ **②-b 에만 있다.** ②-a 는 커서가 안 움직이는 게 설계대로라 이 가드가 소음이 된다 —
진짜 신호는 **`hold_capped` 가 0이 아닌 것**이다.

✅ **결함 D 는 (D) 「이미 원장에 있는 문서는 상세를 부르지 않는다」로 풀었다**(`inv_doc_state`
— 위 진행 상태 항목). ⚠️ **캡을 푼 것이지 커서를 푼 것이 아니다** — 커서는 여전히 비종결 문서
앞에 묶여 있고, 캡에 안 닿으면 무해하다.
⬜ **(C) 「홀드 목록」과 「커서 바닥」 분리**(비종결을 따로 추적하고 커서는 전진)는 남아 있다.
❌ 커서를 비종결 문서 뒤로 미는 것 — **도착 다리를 영영 못 받아 실재고가 틀어진다**(폐기).

📌 경위·수치 정본은 `docs/sessions/2026-08-31-cursor-defects.md`.

### 조사 자체에서 반복된 실패 (같은 실수 반복 금지)

- **1페이지만 받고 판정** — `/transactions` 30일이 6,451행인데 1,000행만 보고 "86% 미대응"이라 오판.
  전량 받으니 **87% 일치**로 정반대였다. **Total 과 수신 행 수를 항상 대조할 것**
- **정렬 가정** — 목록 앞쪽 1,000행이 전부 UOM 집계행이라 "빈 지정 0%"로 오판
- **파라미터 이름 추측** — `stockadjustment?ID=` 로 400. 문서엔 `TaskID` 로 적혀 있었다
- **대조군 없이 판정** — Cin7 은 모르는 파라미터를 조용히 무시한다.
  존재하지 않는 이름(`ZzzNotARealParam`)을 같이 던져 "무시" 기준선을 만들 것
- **표본 하나에서 규칙을 만들었다** (2026-08-17) — 명세 전제 4개 중 3개가 실측에서 깨졌다
  (발주 블록 상태 어휘 · CN 행 단위 · 빈 Restock). **블랙리스트는 처음 보는 값을 조용히
  통과시킨다 → 화이트리스트 + 미지값 경고가 정답**
- **응답 필드명을 추측했다** (2026-08-17) — `updated_since_req`·`srs_counts`·`advanced_count`
  전부 오답(실제 `updated_since_requested`·`sr_block_status_counts`·`advanced_docs`).
  **`jq 'keys'` 로 먼저 확인할 것** — 위 「파라미터 이름 추측」과 같은 계열
- ⚠️ **응답의 한 부분만 보고 「없다」고 결론내지 말 것 — 이틀 만에 두 번 반복했다.**
  ① 2026-08-18 발주: `StockReceived` 라인만 보고 「Advanced 는 bin 을 못 얻는다」 →
     실제로는 `PutAway` 블록에 있었다.
  ② 2026-08-19 트랜스퍼: `Lines[]` 와 dry 의 `bins=[""]` 만 보고 「트랜스퍼는 bin 이 없다」 →
     실제로는 헤더 `FromLocation`/`ToLocation` 에 `"창고: bin"` 문자열로 있었다.
  📌 **점검 질문**: 라인에 없으면 **헤더·다른 블록·다른 엔드포인트**에는? 그리고
  **화면에 보이는데 API 에 없어 보이면 API 를 덜 본 것이다.**
  ⚠️ 둘 다 **Caleb 이 화면을 보고 지적해서** 잡혔다 — dry 숫자만으로는 두 번 다 못 잡았다
- ⚠️⚠️ **숫자가 대칭이면 「같은 것 두 벌」이라고 단정하지 말 것** (2026-08-25).
  `TR-04174`·`04175` 의 138 SKU 가 **수량까지 완전히 동일**해서 "복제 후 편집"이라 추론했으나,
  실제로는 **업로드 목록이 겹친 것**이었다. 대칭은 「같은 원천에서 나왔다」는 뜻이지
  「한쪽이 다른 쪽의 사본」이라는 뜻이 아니다.
  📌 그리고 **어느 문서가 몇 줄인지는 Caleb 이 화면을 보고 알려줘서** 갈렸다 — 원장 쪽 숫자만
  보고 04174 를 유령으로 지목했다면 **실재 차감을 지웠을 것이다.** (경위 정본 `docs/sessions/2026-08-25-transfer-line-deletion.md`)

---

## 3. 이벤트 8종 — 어디서 무엇을 읽나

| 사건 | 출처 | 부호 | 날짜 |
|---|---|---|---|
| 판매 출고 | `sale` → `Fulfilments[].Pick.Lines` | − | `Ship.Lines[].ShipmentDate` |
| 반품 입고 | `sale` → `CreditNotes[].Restock` | + | `CreditNoteDate` |
| 발주 입고 | Advanced → **`PutAway[].Lines`** / Simple → `StockReceived.Lines` (08-18) | + | **`Lines[].Date`** |
| 이동 출발 | `stockTransfer` → `Lines[].TransferQuantity` | − | `DepartureDate` |
| 이동 도착 | 같은 문서 | + | `CompletionDate` |
| 조정 기존 | `stockadjustment` → `ExistingStockLines` | `Adjustment − QuantityOnHand` | `EffectiveDate` |
| 조정 신규 | `stockadjustment` → `NewStockLines` | `+Quantity` | `EffectiveDate` |
| 조립 | `finishedGoods` → `PickLines`(−) + 헤더(+) | 양방향 | 오더 생성 시점 |

**원가만 바뀌는 6종**(`* Cost Change`)은 `Quantity=0` — 수량 원장에서 무시.

### 문서별 함정

- **발주 (2026-08-18 재설계 확정 — `@2026-08-18.1` 반영)**: 축은 목록 `Type` 으로 가른다 —
  **Advanced = `PutAway`**(bin 있음·확정 반영) / **Simple = `StockReceived`**(객체 하나 · bin 있음
  — PO-00874). SR 을 쓰면 안 되는 이유 둘: ① SR 라인의 `LocationID` 는 null 이거나 **창고
  GUID** 라 bin 이 구조적으로 없다 ② SR `Status` 는 stock receiving 단계의 **워크플로 상태**지
  재고 반영 여부가 아니다(PO-00703 SR=DRAFT/PA=AUTHORISED 62줄 `FULLY RECEIVED` · PO-01131
  SR=NOT AVAILABLE/PA=AUTHORISED 3,570u · PO-01128 SR=""/PA=AUTHORISED 84줄). SR·PA 는 같은
  입고의 두 표현(15건 srLines==paLines) — **둘 다 읽으면 정확히 두 배**.
  블록 화이트리스트: **통과는 두 축 모두 AUTHORISED 만** + 미지값 경고(~~빈 문자열 통과~~ 는
  근거 소멸로 삭제). **PA 축의 알려진 어휘 = `AUTHORISED`·`VOIDED`·`DRAFT`**(08-18 · Convert
  직후 PA 는 DRAFT 로 생성 — PO-01117) — ⚠️ 어휘와 통과 기준은 다르다: DRAFT 는 경고 없이
  건너뛰는 정상 상태일 뿐 기표되지 않는다. 목록 `StockReceivedStatus` 게이트 없음(위 함정 표).
  Advanced 인데 PA 없음 = 행 미기표 + 보고, 커서는 안 멈춘다(~~재등장 전제 미확인~~ →
  **08-19 실측으로 닫힘 — PA 승인 후 +51행 재등장**. 정본 4부 체크리스트 ☑3).
  ⚠️ `Type` 은 가변이지만 **Convert 는 사람이 누르는 명시적 동작 — 시간 아님(PO-01117 31분 무변)**.
  ~~"Apply 후 ~10분 자동 전환(12/12)"~~ 은 Convert 가 보통 빨리 눌렸던 것의 오인.
  `simple_docs: 0` 도 `> 0` 도 정상이고, 전환이 `LastUpdatedDate` 를 올려 **모든 PO 가
  UpdatedSince 에 최소 두 번 잡힌다**. ~~"최근 40건 전부 Advanced — Simple 분기 미실행"(08-17)~~ 은 닫혔다:
  목록 게이트 제거 후 `simple_docs: 7` 실행·정상 동작(SR NOT AVAILABLE 올바르게 배제).
  [실측 08-18 dry 전/후] rows 383→643(+68%) · UNMAPPED 소멸 · bin 실제 선반으로
  ✅ **Simple 분기가 실제로 행을 만들었다 (08-19 PO-01112)** — 종전엔 `simple_docs > 0` 이어도 SR 이
  전부 `NOT AVAILABLE` 이라 걸러졌을 뿐 **Simple 축이 행을 만든 적은 없었다**. PO-01112 Apply 로
  `sr_block_status_counts={AUTHORISED:1, NOT AVAILABLE:5}` → **102행**(같은 창 727→829).
  ⇒ Simple=SR 축 결정이 실동작으로 검증됐다. 📌 이 증가는 코드가 아니라 **데이터 변화**다
  (`candidates`·`docs_processed` 는 20 으로 동일한데 행만 늘어 감지 로직을 의심했다 — 확인은
  `wms_receipts.applied_at` 조회. **행 수가 늘면 코드보다 그날의 입고를 먼저 볼 것**)
- **발주 날짜**: `OrderDate`·`InvoiceDate`·`LastUpdatedDate` 전부 어긋남. 우연히 맞는 경우가 있어
  **한 건만 보고 판단 금지**
- **반품**: `RestockStatus='AUTHORISED'` 일 때만 재고 복귀. `DRAFT` 는 금액만.
  한 오더에 크레딧 노트가 **여러 개** 붙을 수 있음.
  ⚠️ 정정(08-17): **AUTHORISED 인데 `Restock[]` 빈 배열 실재** — 판정은 배열 길이로.
  목록 행은 **sale 단위** — 목록에서 `RestockStatus` 로 거르지 말 것(같은 오더의 승인 CN 유실).
  원장 doc_number = **CreditNoteNumber**(오더번호면 다중 CN 이 유니크 키를 깬다)
  · ⭐ **CN 의 `occurred_on` = CreditNoteDate = 발행일**이다(원본 오더일이 아니다).
    모든 CN 은 **원본 구매 이력과 연동**되지만(반품 시 그 손님의 오더에서 해당 제품을 찾아 작성),
    물건은 CN 을 쓰는 시점에 돌아오므로 발행일이 맞다.
    [실측 2026-08-28 · 8건] `occurred_on` 과 `created_at` 이 **같은 날 1시간 안** ·
    `qty_delta` 전부 **양수**(재고 유입) · `CR-00575` 는 **4 SKU 한 문서**.
    ⇒ **전달 Lock 후에 CN 이 생겨도 `since` 필터에 안 걸린다** — 안전하다.
- **이동**: 한 문서가 원장 4행(출발창고− / IN_TRANSIT+ / IN_TRANSIT− / 도착창고+).
  미완료면 출발만. **97%가 같은 창고 안 자리 이동** — 창고 단위로는 ±0이지만 **두 줄 다 기록**.
  ⚠️ **빈 이동의 `DepartureDate` 결손은 구조적이다**(Cin7 WMS 모바일 빈 이동이 만든다 —
  실측 15건 · 우리 WMS 에 빈 이동 기능이 없어 **계속 발생**). 대체 규칙: **같은 창고 →
  `LastModifiedOn` 으로 대체 + raw 에 대체 사실 기록**(창고 잔고 ±0 이라 무영향) /
  **다른 창고 → hold**(잔고가 움직이는데 시점 불명 = 진짜 이상)
- **조립**: 오더 생성 시점에 실제로 재고가 움직인다. 출고는 배송 때 — 그 사이 번들이 재고로 존재(0~15일).
  물리적 이동이 아니라 **재분류**라 실사 때 장부와 선반이 달라 보임.
  ⚠️ 조립 없이 팔리는 경우도 있다(조정으로 재고를 잡아둔 것 — 3건 확인).
  ⚠️ 필드 실측(2026-08-17): `sku` 출처는 **`ProductCode`**(PickLines·헤더 둘 다 — SKU 필드가
  없다) · `doc_number` = **`AssemblyNumber`**(목록 배열 키는 **`FinishedGoods`**) ·
  날짜 = `CompletionDate`(FG-00110 = 2026-08-06 — `Date`/`CompletionDate`/`WIPDate` 세 값 동일 ·
  재고 이동일과 일치) · `Status='COMPLETED'` 만(120건 중 VOIDED 77)

---

## 4. 수집 경로

### 문서 목록 축으로 수집한다 (`/transactions` 아님)

⚠️ **`/transactions` 는 탐지 축으로 쓸 수 없다** — 창고내 이동의 94%가 회계 분개를 안 만든다.
금액 이동이 없어서다. 실측: 창고내 분개있음 123 / 없음 1,882 · 창고간 23 / 4.

### 목록별 증분 가능 여부 (실측)

| 목록 | Total | 증분 |
|---|---|---|
| `saleList` | 14,752 | ✅ `UpdatedSince` |
| `purchaseList` | 1,155 | ✅ `UpdatedSince` |
| `saleCreditNoteList` | 3,583 | ✅ `UpdatedSince` |
| `stockadjustmentList` | 1,201 | ❌ 전량 2p |
| `stockTransferList` | 3,977 | ❌ 전량 4p |
| `finishedGoodsList` | 120 | ❌ 전량 1p |

날짜 축 없는 셋은 **매번 전량 받아 우리 쪽에서 날짜로 거른다.** 하루 10페이지 안팎.

**전량 셋의 커서 하한(`?from_cursor=` — 2026-08-17)**: 저장된 커서가 없을 때의 시야 하한 —
그 번호 이하 문서는 후보에서 아예 제외(스냅샷에 녹아 있어 볼 이유가 없다).
⚠️ 근거 사고: `DepartureDate` 없는 2025-11 초기 트랜스퍼 **TR-00012~76 40건이
hold_missing_date 로 상세 캡 40을 정확히 소진**해 뒤 ~3,000건을 한 건도 못 봤다.
**`since` 로는 못 푼다 — 커서 정지가 필터보다 먼저다.** ⚠️ 하한은 "옛 데이터를 안 보는 것"이지
**이상 감지를 끄는 것이 아니다** — 하한 이후의 날짜 결손·DRAFT 는 여전히 커서를 막는다.

⚠️⚠️ **`from_cursor` 형식·함정 (2026-08-24 규명 — 두 번 헤맸다)**:
- **형식 2종**: bare `from_cursor=TR-03900`(②-a 전량 축 3종 전부에 같은 하한) 또는
  `from_cursor=transfer:TR-03900,adjustment:ST-01150,assembly:FG-00110`(소스별).
- ⚠️ **②-a(조정·이동·조립) 전용이다** — 판매·발주·반품(②-b 시각 커서)은 이 파라미터를
  **아예 읽지 않는다**(그쪽 씨앗은 `from_since=YYYY-MM-DD`).
- 📌 **[2026-08-21 실측 재구성] `from_cursor=TR-03538` 이 "조용히 무시"였던 이유 — 에러가
  아니라 무시가 맞고, 두 겹이었다**: ① 판매 등 ②-b 에는 참조 코드 자체가 없다(구조적 무시)
  ② ②-a 에서도 **state 커서가 있으면 param 은 무시**(`floor 우선순위 state → param` —
  `from_cursor_param_ignored` 로 표시만 된다). ⑤ 가동 후에는 state 가 항상 있으므로
  **from_cursor 는 사실상 죽은 파라미터다** — 커서를 옮기려면 `inv_sync_state.last_cursor`
  를 직접 고치는 것뿐(쓰기 — dry 로는 불가).
- ⚠️ **[2026-08-24 실측] 시각 문자열을 넣으면 콜론이 형식 구분자와 충돌한다** —
  `from_cursor=2026-08-21T00:00:00` → `2026-08-21T00` 이 소스 키로 오파싱 →
  400 `"from_cursor: unknown source '2026-08-21T00'"`. 시각 커서 소스를 겨냥할 파라미터가
  아니다(위 ②-a 전용).
- ⇒ **커서를 무시하고 특정 창을 강제 조회하는 무해 파라미터는 없다**(2026-08-24 확인) —
  지나간 문서의 게이트 검증은 실데이터 재조회가 아니라 **로컬 테스트**로 한다
  (`scripts/test-invcollect-gate.mjs` — makeSink 를 원문 추출해 node 모의, 8케이스).

**증분 셋의 날짜 커서 규칙 (2026-08-17 구현 확정 · 2026-08-30 커서 단위 갱신)**:
`UpdatedSince = last_cursor − 1일`
(겹침 수신 — 중복은 유니크 키 흡수) · 문서 상태로 커서 안 멈춤(갱신되면 재등장) ·
⚠️ **캡 회차만 커서 = 마지막 처리 문서의 키 `<Updated>|<문서식별자>`**(오름차순 처리 전제 —
회차 시작 시각으로 옮기면 캡 밖 후보가 영영 유실. 판매는 캡 초과가 일상)
⚠️ **맨 `Updated` 가 아니다 — 동률 그룹에서 동결됐다(결함 C · §2 계보)**. `inv-collect` ②-b 만
tie-breaker 를 쓴다(`@2026-08-30.1`) · ⚠️ 커서는 시각 전체 정밀도로 저장하고
**거르기도 우리 쪽 전체 정밀도로**(날짜 절단이 "매 회차 같은 40건 반복·삽입 0행·정상 응답"의
완전히 조용한 정체를 만든다 — dry 로는 재현 불가) · ⚠️ **`since=<스냅샷 날짜>`(이벤트 필터)는
쓰기 켤 때 필수** — 갱신 축과 이벤트 날짜가 분리라 과거 이벤트가 스냅샷과 이중 계상된다.

⚠️ **`stockTransferList.LastModifiedOn` 은 「라인 삭제」도 갱신한다** ([실측 2026-08-25] GAS 프로브 —
TR-04175 의 값이 정확히 138줄 삭제 시각이었다 · 대조군 TR-04174 무변. 표·수집 시각 대조 정본은
`docs/sessions/2026-08-25-transfer-line-deletion.md`).
⇒ **삭제도 갱신 축에 잡힌다** ⇒ 증분 축(판매·발주)도 편집된 문서가 `UpdatedSince` 에 재등장한다.
📌 목록 행의 키: `TaskID, From, FromLocation, To, ToLocation, Status, Number, CompletionDate,
DepartureDate, InTransitAccount, CostDistributionType, Reference, SkipOrder, LastModifiedOn`
⚠️ ②-b(판매·발주·CN)에 `LastModifiedOn` 이라는 **이름의** 필드가 있는지는 **미확인**이다 —
코드는 실측된 갱신 필드(`cd.updated` = saleList `Updated` · purchaseList `LastUpdatedDate`)를 쓴다.

### `Movements` 는 검증용

`product?ID=…&IncludeMovements=true` 로 SKU 단위 전체 이력. **부호가 이미 들어 있고 완전하다**
(3건 전수: 누적 = 현재 `OnHand`). 그런데 **날짜 필터가 없고**(후보 7종+대조군 전부 무시)
**SKU 단위 조회**라 수집엔 못 쓴다. → **대조·검산 축**으로 쓴다.

`Movements` Type 어휘 14종 = 수량 8종 + 원가 6종. 필드: `TaskID·Type·Date·Number·Quantity·Amount·Location(빈 포함)·FromTo`

---

## 5. 스키마 (배포 완료)

`inv_ledger` · `inv_snapshot` · `inv_compare` · `inv_sync_state`

### `inv_ledger` 핵심

- **append-only** — `authenticated` 는 INSERT+SELECT 만(`wms_rollback_archive` 선례). `anon` 전부 회수
- 유니크: `(doc_type, doc_number, line_ref, event_type, warehouse, bin, sku)`
  - ⚠️ `bin` 은 **NOT NULL DEFAULT `''`** — 부분 유니크 금지 규칙(29) 때문
  - ⚠️ `sku` 를 넣은 이유: `line_ref` 가 흔들려도 **조용한 누락 대신 가시적 이중 계상**이 되게
- `seq_hint` — **1=유입 / 2=유출**. 같은 날 정렬용
- `warehouse` — **Cin7 원문 그대로** + `IN_TRANSIT`(언더스코어 = Cin7 원문 아님 표시)
- `line_ref` = **`ProductID`** (WMS 의 `cin7_po_line_id` 선례) — ⚠️⚠️ ~~판매만 예외~~ →
  **예외 둘(08-18): 판매·발주.** 규칙의 정본은 설계 문서 2부 「중복 방지」 소스별 표
  ("소스마다 가장 안정적인 라인 식별자" — 통일보다 정확성 우선). **판매 예외:
  `<fulfilment TaskID>:<ProductID>`** (2026-08-17 · 의도적 이탈). 유니크 키에 **occurred_on 이
  없어서**, 분할 출하(같은 SKU·같은 bin·날짜만 다름)의 두 행이 키가 완전히 같아져 두 번째
  출고가 조용히 사라진다. **"스킬대로 ProductID 로 되돌리자"는 제안이 나오면 이 줄이 근거다 —
  되돌리면 분할 출하가 뭉개진다.** fulfilment 식별자는 TaskID(GUID — 재수집에도 안정 · 배열
  인덱스 금지). [실측] TaskID 폴백 발동 0회. ~~발주의 진짜 라인 식별자 CardID 는 raw 원문에만~~
  → 08-18 부터 발주의 line_ref 자체가 CardID 다(아래).
  ⚠️ **발주는 `CardID` 로 확정(2026-08-18 · `@2026-08-18.1`)** — 같은 SKU 가 여러 빈으로 쪼개지고
  같은 빈·같은 SKU 가 날짜만 달리 두 줄인 사례 실측(PO-00944 KUZ77036). `ProductID` 는 유일성
  94/97 · 109/110 으로 부족, `CardID` 는 97/97 · 110/110. [실측] `.7` dry `merged_lines: 5`
  (가설이던 뭉개짐이 실재) → `.1` 에서 **0**. ✅ CardID 의 재수집 안정성은 **닫힘(08-18 저녁
  PO-01117)** — Convert(SR→PA)를 통과해도 51줄 전부 CardID·LocationID·순서 유지, 재생성 아님
- `raw` = **그 행을 만든 라인 원본 + 계산에 쓴 머리말 + 우리가 적용한 계산 규칙**.
  문서 전체 금지(344라인 트랜스퍼면 수천 벌 중복)
- ⚠️ `qty_delta` 에 CHECK 없음 — **소수 수량이 실재**(5.25개 · ×0.25)

### 기초 스냅샷

`ref/productavailability` 전량 22,133행 · 23페이지 · 1분. 페이지 상한 없음.

**스냅샷 조건**: 자리 지정된 것은 자리별로, **자리 없이 떠 있는 재고(`Bin=null` & `OnHand≠0`)도 담는다.**
자리 있는 것만 담으면 11건이 통째로 누락된다.

✅ **실촬영 완료 (2026-08-20)** — `snapshot_key 2026-08-20-initial` ·
`taken_at 2026-08-20T23:42:47.855Z`(19:42:47 토론토) · **13,844행**(토론토 7,523 / 에드먼튼 6,321) ·
44초 · `truncated` false · `rate_limited` false · `unexpected_warehouses []`.
낮 dry 리허설은 41초·13,871행 — **27행 차이는 그사이 5시간의 실제 재고 변동**이다(정상).
📌 DB 검증 일치. `bins` 만 SQL 쪽이 1씩 많은데(506→507 · 1467→1468) **빈 문자열 bin 이 `distinct` 에
세어진 것**이지 불일치가 아니다.

⚠️ **`key` 파라미터가 필수다** — 자동 생성을 하지 않으며 **dry 에도 요구**한다. 인증은 `inv-collect` 와
같은 `WMS_CRON_SECRET`.

⚠️ **자리 미상 재고가 기준선에 포함된다 — 알고 시작하는 위험.** `null_bin_nonzero` **15건**
(토론토 1,421개 · 에드먼튼 6개). 최대는 **`AS00879BLA` 1,200개 · $12,065** · `AIA*` 7종은 전부
6개·$0.0831 로 같은 패턴(샘플·디스플레이 추정) · `SUN31504` 159개는 원가 $0.
⇒ 원장은 그대로 기록하고 **⑥ 대조에서 드러난다.**
📌 **`null_bin_nonzero` 에 샘플 상한은 없다**(코드 확인 — `nullBinNonzero` 는 조건 없이 `push`,
`slice` 없음). 15건이 전량이다.

**스냅샷 이력** (2026-08-25 기준):

| `snapshot_key` | rows | 촬영(토론토) | |
|---|---|---|---|
| `2026-08-20-initial` | 13,844 | 08-20 19:42 | 기준선 — 정상 촬영·검증 완료 |
| `2026-08-24-compare` | 13,834 | 08-24 09:19 | ⚠️ **혼합** — 아침 13,829 + 밤 재촬영 신규 5(§4-a) |
| `2026-08-25-compare` | 13,804 | 08-25 01:21 | 첫 자동 회차 · 정상 |

📌 하루 1회 cron 은 키가 날마다 달라 재촬영이 없다 — **혼합 위험은 수동 재실행에서만 생긴다.**

---

## 6. 창고

`ref/location` 2,676행 · **`ParentID` 없는 것이 창고**(2단 트리, 재귀 불필요) · 창고 3개

| Cin7 | WMS `warehouse` | WMS `location` |
|---|---|---|
| `Asung Trading Inc.` | `toronto` | 같음 |
| `Asung - Edmonton` | `edmonton` | 같음 |
| `Production Facility` | 없음 | — |

- `wms_orders.location` 은 **Cin7 표기 그대로** → 매핑 불필요
- `wms_receipts`·`wms_waves` 는 `warehouse` 만 → **2줄 매핑 필요**
- ⚠️ `Production Facility` 는 삭제 불가한 시스템 창고, 미사용(재고 0 전수 확인).
  **제외하되 `OnHand>0` 이 나타나면 경고할 것**

---

## 7. 재고 조회 규칙 (`ref/productavailability`)

- ⚠️ `Sku` 는 **전방 부분일치** — `ANN04350` 요청에 `ANN04350-12` 도 온다. **정확일치로 재필터**
- ⚠️ `Bin=null` 행과 빈행을 **합산하면 이중 계산**
- ⚠️ UOM SKU 는 `OnHand=0` · `Available>0`(파생값) — 원장 대상 아님
- `StockOnHand ÷ OnHand` = 단가. 빈마다 다르다(68%) → **FIFO 구조**. 초기 단가로 쓸 수 있으나
  **레이어 구조는 여기서 못 얻는다**
- `InTransit` 필드는 창고이동과 무관 — `OnOrder` 와 같은 값(발주 잔량)

---

## 8. 알고 시작하는 위험

- **원가 0 재고** — 조정으로 새로 잡을 때 `UnitCost=0` 이 들어온다. 원가 단계에서 공짜 재고
- **원본 데이터 오류** — `AMP41108-12` 의 `UOM="6"`(SKU 접미어와 불일치).
  ⚠️ **SKU 접미사 파싱 금지**. 원장은 원본 오류를 그대로 물려받는다
- **전체 합계 검산 경로 없음** — SKU 단위는 `Movements` 누적으로 되지만, 창고 총계는 화면 리포트뿐
- **수동 단계** — 매니저의 `2.Release to WMS`(`sale` 의 `AdditionalAttributes.AdditionalAttribute1`).
  주 5일이라 월요일에 몰린다. 재고와 무관하나 대조 때 설명이 필요
- **주말·공휴일** — 재고가 안 움직이는 게 정상. 온타리오와 앨버타의 공휴일이 다르다
- ⚠️⚠️ **키 생성 규칙을 바꾸면 원장 전체가 「삭제됨」으로 검출된다** (2026-08-25 · 소멸 감지 도입 후)
  A·B 비교는 7키(`doc_type,doc_number,line_ref,event_type,warehouse,bin,sku`)로 한다.
  `bin`·`line_ref`·`warehouse` 의 **생성 규칙**이 바뀌면 A 는 새 규칙·B 는 옛 규칙이라 집합이
  통째로 어긋나 **기존 행 전부가 「사라진 라인」**이 된다.
  · ✅ **[발동·처방 완료 2026-08-31] 트랜스퍼 출발 bin 해결**이 정확히 이 변경이었다 —
    옛 `bin=""` 행의 키가 새 A 집합에 영원히 없어 매 회차 734행이 「사라짐」으로 검출되고
    **회차 캡 500 을 소진해 진짜 소멸을 가렸다**(⚠️ 상쇄로도 안 없어진다 — 옛 cin7 행은 B 에
    그대로 남는다). ⇒ **`bin 변경` 예외**(`partitionBinChanged` · 위 진행 상태 항목):
    bin 만 다른 6키가 A 에 있으면 소멸이 아니다. **앞으로의 어떤 bin 규칙 변경에도 이 예외가
    방어한다** — ⚠️ 다만 **`line_ref`·`sku`·`warehouse` 변경은 여전히 무방비**다.
  · **[전례] 발주 `line_ref` `ProductID` → `CardID`** (2026-08-18) — 같은 성질의 변경이었다
  ⇒ **bin 외의** 키 규칙을 바꿀 때는 **검출을 일시 정지하거나 기존 원장 행을 함께
    마이그레이션**할 것.

---

## 9. 작업 방식

- 조사·판단 먼저 → Caleb 확인 → 구현. **한 번에 한 단계**
- git·SQL·EF 배포·Cin7 호출은 **Caleb 이 직접**. 프로덕션 직접 요청 금지
- 마이그레이션은 항상 새 파일. baseline 수정 금지. `supabase db reset` 으로 로컬 재생 검증 후 push
- 커밋 메시지에 `Co-Authored-By` 금지
- GAS 프로브가 표준 조사 도구 — EF 구현 전에 항상 실측
- ⚠️ **승인된 SQL·스키마는 프롬프트에 전문을 붙일 것.** [2026-08-26] 지시문에
  `[여기에 승인된 SQL 을 붙여넣을 것]` placeholder 를 그대로 남겨 보냈고, Claude Code 는
  **지어내지 않고 명시적으로 보고한 뒤** 같은 성격의 테이블(`inv_compare_runs`) 관례를 따라
  작성했다. 결과는 오히려 더 정확했지만(`aborted` 어휘를 소스에서 읽어 적었다 — 지시문 쪽
  `'time_budget'`·`'truncated'` 는 추측이었고 틀렸다), **승인한 것과 다른 물건이 들어올 수 있다.**
  📌 같은 건에서 지시문의 유니크 인덱스 `(snapshot_key, ran_at)` 도 **무의미**했다 —
  `ran_at` 이 DB `default now()` 라 재삽입해도 충돌하지 않는다. **제약을 넣기 전에
  「이것이 실제로 무엇을 막는가」를 확인할 것.**
- ⚠️ **새 Edge Function 을 만들 때 `supabase/config.toml` 블록을 반드시 함께 추가할 것.**
  [2026-08-27] `inv-cost` 를 배포했는데 블록이 없어 첫 호출이 `UNAUTHORIZED_NO_AUTH_HEADER` 로
  막혔다 — **함수에 도달하기 전 게이트웨이가 막는다**(새 함수는 `verify_jwt` 기본 켜짐).
  형식: `enabled = true` · `verify_jwt = false` · `entrypoint = "./functions/<name>/index.ts"`.

---

## 다음에 할 일 (우선순위 — 2026-09-02 갱신)

1. ⚠️⚠️ **소멸 감지 사각지대** — `adjustment`·`assembly` 는 목록에 last-modified 가 없어
   **라인 삭제·교체를 아무도 못 본다**(§함정 표). ⬜ `lmoRaw` 조건 완화가 후보다
2. ⚠️ **「수집 후 취소」 감지** — 2026-09-01 오전 발견. 여전히 미착수
3. ⬜ **`TR-04175` 276행 소멸 감지** — 9/1 20:32 편집. 별건
4. ⬜ **잔여 어긋남 — 발생 시점은 규명, 원인은 미규명**(스냅샷 소급 · 2026-09-02).
   `WEL04770`·`WEL04771`(`A090203`) **9/2 발생 · ⚠️ 원인 못 찾음** ·
   `BNAT48173` +11 · `CAN01003` −4 는 **8/29**(결함 C 혼란기) ·
   `PRO00124` 짝은 **8/20~8/24**(초기 수집기 · 에드먼튼 bin 이동).
   여섯 다 `inv_ack_diff` 로 「확인됨」 — ⚠️ **상쇄하지 않았다**(§함정 표)
5. ⬜ **커서 근본 해결** — 홀드 목록과 커서 바닥 분리
6. ⭐ **WMS 재고 마스터 화면** — 원장 준비 완료 · 통지함. ⬜ `ledger_collected_at` 추가 요청 처리
7. ⏸ 표본 대기: 급감 검사 임계값 · `landed cost` 첫 발생 · Simple Purchase 원가

📌 **플립 시점은 날짜가 아니라 사건 목록으로 센다** (2026-08-28 재검토 — ⚠️⚠️ **「30일」은 근거가
없는 숫자였다**). 재려는 것은 「시간이 흘렀다」가 아니라 **「일어날 만한 일이 다 일어났다」**다.

**[실측 2026-08-28] 사건 목록은 8일 만에 거의 다 닫혔다:**
adjust(existing 106 · new 7) · assembly(in 1 · out 4) · **creditnote 8** · po_in 48 ·
sale_out 5,481 · transfer 925×2 · 라인 삭제 · 부분입고 · 분할입고 · Simple→Advanced 전환 ·
재평가 · since 경계 아티팩트.
⬜ **남은 것은 `landed cost` 소급 입력 하나**(통관·운임 인보이스 · 한두 달).
⚠️ **월말 마감·연말 실사는 목록에서 뺀다** — 우리는 아무것도 닫지 않고 Lock 만 걸며
(전달 HST 보고 후), 실사는 **수시 조정** 방식이다(WMS declare → 매니저 실사 → adjustment ·
매니저만 · 사유 필수).

⚠️ **그러나 「사건을 겪었다」와 「정확하다」는 다르다.** 닫힘 기준 셋:
| | |
|---|---|
| ① 사건 종류를 다 겪었다 | `landed` 만 남음 |
| ② 알려진 결손이 없다 | ⚠️ **트랜스퍼 bin 단위** · **초과·미달 입고 bin** · **급감 판정 미구현** |
| ③ 새 결함 빈도가 떨어졌다 | ⚠️ **11일간 5건** — 다만 **성격을 나눠 읽어야 한다**(아래) |

**⚠️ 그냥 세면 판단이 오도된다. 셋으로 나눈다.**

**(가) 원장 데이터 결함 — 3건.** ⭐ **이것이 하드 플립 판단의 축이다.**
| | |
|---|---|
| `FINAL-SALE` (08-24) | 비재고 SKU 가 필터 틈에 빠져 재고 사건으로 쌓였다 → 게이트로 닫힘 |
| `TR-04175` (08-25) | Cin7 에서 라인을 지웠는데 원장이 몰랐다 → 소멸 감지로 닫힘 |
| `PO-01133` (08-28) | Simple 로 완료돼 원가가 안 붙었다 → 아침 점검 ⑥ 으로 닫힘 |

📌 **셋은 서로 무관한 별개 원인이다**(공통점은 「원장에 잘못된 데이터가 들어갔다」뿐).
📌 셋 다 **새로운 사건 종류가 아니라 드문 조합**이었다 — 판매·트랜스퍼·발주는 이미 수백 건
겪은 것들이고, 특이 SKU · 수집 후 편집 · Simple 로 완료라는 **조합**이 처음이었다.
⇒ 시간이 필요한 이유는 새 종류를 기다리는 게 아니라 **드문 조합이 나올 확률을 쌓는 것**이다.
그 조합은 **실무가 만든다** — 우리가 예상할 수 없다.
📌 **(가)는 2026-08-28 이후 0건.**

**(나) 수집 경계 결함 — 2건.** 결함 C(08-29 커서 동결) · 결함 D(08-31 캡 누락).
📌 ⭐ **커서·캡·`UpdatedSince` 는 남의 시스템에서 긁어오기 때문에 있는 장치다.**
우리 IMS 가 완성되면 **이 계열은 통째로 사라진다**(사건이 일어나는 순간 원장에 기록되므로
「어디까지 읽었나」를 기억할 이유가 없다) ⇒ ⚠️ **플립을 미루는 근거로 쓰지 말 것.**
⚠️ 다만 **shadow 기간 동안은 데이터를 실제로 잃는다** — 회수 가능하지만
**늦게 알면 비싸다**(결함 C 는 하루 반, D 는 사흘 늦게 알았고 그 지연이 잘못된 응급조치를 낳았다).

**(다) 우리가 만든 것 — 1건.** 이중 차감(08-30 · 같은 날 발견·상쇄 522행).
⚠️ **앵커에 세지 않는다** — 발견한 결함이 아니라 **내가 만든 것**이다.
정본은 `docs/sessions/2026-08-31-cursor-defects.md` §2 와 §4-c 「내가 틀린 것」.

⚠️ **읽을 때의 주의**: 발견 수는 **얼마나 파고들었느냐에 좌우된다** — 08-29~31 은 사흘 내내
깊이 판 세션이었다. **얕게 지나간 날의 0건은 「결함이 없다」가 아니라 「안 봤다」일 수 있다.**

📌 ⇒ **「30일 뒤 한 번에 플립」이 아니라 「위험이 낮은 것부터」**:
읽기 전용 화면(지금 가능 · ③을 오히려 앞당긴다) → 발주 판단(③ 이후) → Cin7 끄기(훨씬 뒤).
⚠️ 화면이 원장 숫자를 「정답」처럼 보이게 하면 안 된다 — **shadow 임을 화면이 말해야** 한다.
📌 경위·실측 정본은 `docs/sessions/2026-08-28-cost-first-verification.md` §9.
