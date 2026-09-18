# 2026-09-16 · 17 · 18 아침 점검 — 커서 정체 계열 · 어긋남 세 건(전부 해소) · ⭐ 두 사고가 같은 구조

관련: `asung-inv-ledger` §아침 점검 ④·⑤·⑦·⑧·⑩·**⑩-b**·「지금 알려진 잔재 3칸」·§2 「커서 결함 계보」 F · `docs/design/ledger-design.md` §「변경 감지가 못 보는 축 — bin 변경 이중 기입」(사각지대 · 도구 계약 · `fix_kind` 표) ·
앞선 건 `2026-09-15-bin-change-double-write.md`(⑩-b 신설) · `2026-08-31-cursor-defects.md`(결함 A~E) · `2026-09-13-list-total-axis.md`(④ 축).
⚠️ 표기: **[실측]** = 운영 DB(`inv_collect_runs` · `inv_sync_state` · `inv_balance_vs_cin7` · `inv_conflicts`) · Cin7 화면·API 에서 읽은 값 · **[추론]** = 판단.
📌 역할 분담: **스킬은 요약+함정 · `ledger-design.md` 는 계약 · 이 파일은 실측 근거.**

---

## A. ⭐⭐ 커서 정체 — 두 사고의 공통 구조

### A-1. 09-16 `ST-01300` — 홀드 + 캡 교착

```
경위    ST-01300(9/3 작성 · DRAFT)이 adjustment 커서를 ST-01299 에 붙잡았다.
        원장은 미확정 문서를 건너뛰지 않고 기다린다 — 건너뛰면 나중에 확정돼도 못 받는다. 설계대로다.
        ⭐ 13일간 무해했다 — 커서는 멈췼지만 수집은 계속 돌았다(docs_processed 18 → 22 → 29 → 35).
        ⚠️ 09-15 16:00 에 처리 대상이 40건 캡에 도달 → 41번째부터 영구히 밀렸다. docs_processed 가 40 에서 18시간 고정.
        ⇒ 밀린 조정이 ⑧ 의 10칸 288(전부 토론토 · ± 짝을 이루는 실사 조정 모양)
처방    ⚠️⚠️ 상쇄하지 않았다. Cin7 에서 ST-01300 을 Void 하자 커서가 ST-01299 → ST-01342(43문서) → 밤사이 ST-01353 까지 전진.
        ⭐ 09-17 아침 abs_gap 318 → 6 으로 저절로 맞았다.
        ⇒ 「원장이 틀린 게 아니라 못 받은 것」 판정이 옳았다. 상쇄했다면 두 배로 틀어졌다.
```
⚠️ **`summary->'cursor_held_by'` 가 원인을 바로 알려줬다** — `{ "reason": "hold_status:DRAFT", "doc_number": "ST-01300" }` · `cursor_before = cursor_after = ST-01299`.
⇒ ⭐ ⑦ 조회에 `held_by`·`docs_processed`·`list_total` 을 함께 뽑는다(스킬 ⑦ SQL 갱신). 그것이 없어 처음에 한참 돌아갔다.
📌 [실측 코드] `cursor_held_by` 는 컬럼이 아니다 — `inv_collect_runs` 정의(`20260831153314`)에 없고 EF `inv-collect/index.ts` 1748행이 결과 객체 `R` 에 넣으며, `buildCollectRun`(871행)이 `summary` = `R` 전체(samples 제외)로 저장한다 ⇒ `summary->'cursor_held_by'`. `hold_capped` 는 반대로 컬럼(`dispositions.hold_capped` 에서 뽑음)이고 `summary` 최상위 키로는 없다 — 09-16 의 「전 기간 null」은 그래서였다.

### A-2. 09-18 `TR-04730` — 홀드 + 재훑기 + bin 해석 실패

```
경위    TR-04496(ORDERED · 미확정)이 transfer 커서를 TR-04495 에 붙잡았다(09-12 부터 이레).
        ⇒ 수집기는 매 회차 커서 이후 5,000건을 다시 훑는다. TR-04730 도 매번 목록에 들어왔고 평소에는 걸러졌다(⚠️ skipped_unchanged 로 추론).
        ⚠️ 09-17 13:23 회차 — 밀린 것을 따라잡던 중 TR-04730 이 상세 조회 40건 안에 들어갔고, 그 회차에 잔고 조회가 502 로 실패:
          transfer-bin balance lookup failed (collection unaffected, WMS-value fallback): sbGet 502: "gateway error: Error: Network connection lost."
          24 transfer_out line(s) left with empty departure bin — fill Reference in Cin7 and run scripts/fix-transfer-bins.mjs
        bin_unresolved 24 — ⑧ 의 24칸과 정확히 일치.
        ⇒ bin 을 못 구한 채 빈 값으로 새 행 24개(−299). 09-14 08:52 에 이미 올바른 bin 행이 있었으므로 중복이다.
Cin7    ⭐ 아무것도 안 바꿨다 — [실측] stockTransferList LastModifiedOn = 2026-09-14T12:48:39.967Z(= Activity log 마지막 줄 「products has been sent」와 동일 시각).
        ⇒ 「누군가 열어서 갱신됐다」 가설 기각. 여는 것으로는 LastModifiedOn 이 바뀌지 않는다.
처방    scripts/fix-transfer-bins.mjs dry → 24줄 전부 (상쇄만) · 미해결 0 · 재삽입 0 ⇒ commit. manual_reversal + :binfix · +299 · 빈 bin 순액 0 · abs_gap 306 → 7. (§C)
```

### A-3. ⭐ 공통 구조 (스킬 ⑤ 에 적었다)

> **미확정 문서 하나가 커서를 붙잡으면, 그 뒤로 쌓인 문서를 매 회차 다시 훑게 된다. 그 자체는 무해하지만, 캡(40건 / 120초)이나 일시적 장애와 겹치면 사고가 된다.**

| | 홀드만 | 홀드 + 캡 | 홀드 + 재훑기 + 해석 실패 |
|---|---|---|---|
| 09-16 `ST-01300` | 13일 무해 | ⚠️ **영구 교착**(41번째부터 안 옴) | — |
| 09-18 `TR-04730` | 이레 무해 | — | ⚠️ **중복 행 생성** |

⚠️⚠️ **그래서 커서 정체 자체가 감시 대상이다.** 지금은 사고가 난 뒤에야 안다. → §B 의 대체 판정 · 스킬 §2 커서 결함 계보에 **F** 로 올렸다.

---

## B. ⚠️ `cursor_stalled_alert` 가 울리지 않았다

`inv_collect_runs` 에 `cursor_stalled_alert` 컬럼이 있고 ⑦ 에서 매일 본다. ⚠️ `ST-01300` 13일 · `TR-04496` 이레 동안 **한 번도 안 울렸다.**
⇒ ⭐ 있는데 안 울린 것과 없는 것은 다르다. ⬜ 발화 조건 확인(코드 미확인 · 별건 — 스킬 §2 의 설명은 `cursorStalled = detailCapped && cursorWouldBe <= cursorBefore` · ②-b 전용 · [추론] ②-a 홀드는 그 식에 안 걸린다).
📌 대체 판정(스킬 ⑤ 에 적었다): **`last_run` = `last_ok` 만 보면 커서 정체를 못 잡는다. 커서 값이 며칠째 같은지도 함께 본다.** 문서번호 커서(`adjustment`·`transfer`·`assembly`)가 **3일 이상 같으면** ⑦ 에서 `summary->'cursor_held_by'` 를 확인한다. [실측] 둘 다 이 방법으로 알아챘다 — `inv_sync_state` 시각이 아니라 **커서 값**이 단서였다.

---

## C. ⭐ `scripts/fix-transfer-bins.mjs` 사용 절차 (스킬 ⑩-b 에 적었다)

빈 bin 으로 남은 `transfer_out` 행을 정리하는 도구. ⚠️ 전제는 「올바른 bin 행이 없다」이므로 `TR-04730` 처럼 **이미 있는** 경우에는 dry 확인이 필수.
```bash
cd ~/asung/asung-wms
 export SUPABASE_URL='https://gftpcnkxbdjzzfvzwcfl.supabase.co'
 export SUPABASE_SERVICE_ROLE_KEY='…'   # Settings → API → service_role
 export CIN7_ACCOUNT_ID='…'
 export CIN7_APPLICATION_KEY='…'
node scripts/fix-transfer-bins.mjs --doc TR-XXXXX          # dry
node scripts/fix-transfer-bins.mjs --doc TR-XXXXX --commit # 확인 후
```
📌 `export` 앞 공백 한 칸 = 셸 히스토리 기록 방지 · `.env` 없음 · 레포는 `asung-wms`(`asung-ims` 아님).

| dry 출력 | 판정 |
|---|---|
| **`(상쇄만 — cin7 재수집이 이미 올바른 bin 행을 썼다)`** | ⭐ 안전 — 중복만 지운다 |
| ⚠️ `(상쇄 + 재삽입)` | 이중이 된다 — commit 금지 · SQL 로 직접 상쇄 |
| ⚠️ `✗ bin 미해결` | 도구가 손 못 댄다 — SQL 상쇄 |
| ⚠️ `잔고 조회 실패` 줄 | 502 재현 — 나중에 다시 |

⚠️ **왜 「상쇄 + 재삽입」이 위험한가** — 중복 검사 키가 `[line_ref, warehouse, bin, sku]`(스크립트 221·253행 · [실측] 코드 확인) 라 `bin` 을 포함 ⇒ 「내가 구한 bin 과 같은 행이 있나」를 묻는다. 해결 bin 이 기존 행과 다르면 재삽입이 실행되어 이중.
📌 **[실측 09-18 `TR-04730`]** dry 24줄 전부 `(상쇄만)` · 미해결 0 · 재삽입 0 ⇒ commit. `manual_reversal` + `:binfix` · +299 · 빈 bin 순액 0 · `abs_gap 306 → 7`. ⇒ 손으로 쓴 SQL 상쇄보다 이 도구가 낫다 — 기존 관례(`:binfix`)를 쓰고 `raw` 에 근거(잔고/WMS · SO · 원본 id · collector 버전)를 남긴다.

---

## D. ⚠️⚠️ ⑩-b 의 사각지대 — 빈 bin 쪽을 못 본다 (계약은 `ledger-design.md`)

⑩-b 가 `bin is not null and bin <> ''` 로 빈 bin 을 제외한다 ⇒ `TR-04730`(빈 bin 쪽 중복)을 못 잡았다. 제외에는 이유가 있다 — 정상 4-leg 의 IN_TRANSIT leg 의 bin 이 비어 있어, 제외하지 않으면 전 문서가 걸린다(09-15 첫 시도).

| 형태 | 예 | ⑩-b |
|---|---|---|
| 실제 bin → 다른 실제 bin | `TR-04729` · `TR-04174` | ✅ |
| 실제 bin → **빈 bin** | **`TR-04730`** | ⚠️ 못 잡는다 |

⬜ 넓히는 방향(판단은 Caleb): ⓐ `warehouse <> 'IN_TRANSIT'` 로 IN_TRANSIT leg 만 걸러 빈 bin 포함(⚠️ 정상 4-leg 의 창고 쪽 leg 에도 빈 bin 이 있는지 먼저 실측) ⓑ 빈 bin 전용 검사(`bin=''` 인 `transfer_out` 중 같은 `line_ref` 에 bin 있는 행 존재). ⚠️ 지금 정하지 말 것.
📌 근본 원인은 같다 — 유니크 키에 `bin` 이 있어 같은 `line_ref` 가 빈 bin 과 실제 bin 으로 공존(2026-08-16 「가시적 이중 계상 > 조용한 누락」의 대가 · ⑩-b 가 그 창구).
⇒ ⬜ 수집기 근본 처방(별건 · 범위 큼): `inv-collect` 가 빈 bin 행을 쓰기 전에 「이 `line_ref` 에 bin 있는 행이 이미 있나」 확인.

---

## E. ⭐ 새 유형 — `Deprecated` 잔재 (스킬 ⑧ 잔재 표에 적었다)

**[실측 09-18] `ANN07490` · `B040803` · 원장 1 / Cin7 0 · `diff +1`**
- 원장에 행이 하나도 없다(`baseline 1` · `delta 0`) — 기초에 1개, 그 뒤 사건 없음
- Cin7 Movements: 입고 1건(2025-10-31 `PO-00001`)뿐 · 출고 없음
- ⚠️ 09-17 에 제품이 `Deprecated` 처리됐다(재고를 털지 않고 · Caleb 확인) ⇒ Cin7 이 `ProductAvailability` 목록에서 뺀 것 · **원장이 옳다** · 실물 1개는 `B040803`
⇒ ⚠️⚠️ **상쇄 금지**(실물 1개가 장부에서 사라진다) · 알려진 잔재로 `PRO00124` 옆에 · ⑧ 에 1칸으로 남는다 · 해소는 실무 쪽(조정으로 털거나 재활성화 후 정상 출고).
⭐ 지금까지와 다른 부류 — 「못 받았다」도 「두 번 받았다」도 아닌 **「Cin7 이 스냅샷에서 뺐다」**.

---

## F. ⑩ `ST-01306` 재검출이 멈췼다

09-16 에 45행을 `resolved_at` 으로 닫았고 직후 회차(09-16 10:11)에 한 건(id 128)이 더 들어와 09-17 에 「닫아도 계속 재검출된다」로 판단했다. ⚠️ **틀렸다.** [실측 09-18] `last_detected` 가 09-16 10:11 그대로 · 이틀째 새 검출 없음 ⇒ id 128 닫아 `still_open 0`.
📌 멈춘 이유: `adjustment` 커서가 `ST-01299` → `ST-01358` 로 전진하며 `ST-01306` 이 재조회 창을 벗어난 것(⚠️ 추론 · ⑦-b `ST-01283` 과 같은 계열). ⇒ 내일 아침에 다시 뜨지 않으면 완전 종결.
⭐ ⑩ 읽는 법(스킬에 적었다): 닫은 직후 한 회차 정도는 더 들어올 수 있다 — 그것까지 닫고 **다음 날 재검출 여부로 종결을 판정**한다.

---

## G. 네트워크 오류 — 설계대로 처리됐다 (스킬 ⑦ 에 적었다)

[실측] 09-17 21:07 `client err` · 09-18 05:07 `502` · 둘 다 `transfer`:
```
ok: false · list_aborted: "page_error: Cin7 GET /stockTransferList -> 502: …" · write_skipped 같은 사유 · missing_check_skipped_reason 같은 사유
cursor_before = cursor_after(안 움직임) · docs_processed 0 · ledger_rows 0
```
⇒ 목록 조회가 실패하자 아무것도 쓰지 않고 커서도 그대로 — 「반쪽만 받고 커서를 전진시켜 나머지를 영영 놓치는」 최악을 피했다. 소멸 감지도 함께 건너뛰었다(불완전한 목록으로 「사라졌다」 오판 방지). 각각 한 회차뿐이고 다음 회차에 복구.
⚠️ **`sbGet 502`(잔고 조회 실패)는 다르다** — 수집을 계속하고 WMS 폴백으로 넘어간다(`collection unaffected`). 그 결과가 §A-2 의 빈 bin 24행. ⇒ ⭐ 「목록 실패 = 중단」 · 「잔고 실패 = 계속 + 폴백」.

---

## H. ④ `list_total` 관측 갱신 (스킬 ④ 에 적었다)

| 날짜 | `list_total` | 변화 | `insert_rows` |
|---|---|---|---|
| 09-16 | 22,465 | −47 | 13,674 |
| 09-17 | 21,765 | **−700** ⚠️ 새 하한 | 13,640 |
| 09-18 | 21,553 | −212 | **13,883**(+243 · 관측 중 최대 증가) |

⇒ 09-18 에 두 축이 반대로 갈렸다(−212 / +243) — 09-13 규명대로 `dropped_zero_nobin` 이 줄고 실제 재고 칸이 늘어난 것 · 입고 신호와 정합. 관측폭 −700 ~ +535. ⚠️ `insert_rows` 가 ① 과 맞으면 `list_total` 은 판정 축이 아니다.

---

## I. 점검 요약 · 틀린 것 · 남는 것

### I-3. 점검 요약
```
09-16   ⑧ 12칸 — ST-01300 홀드+캡 규명 · Void 처방(상쇄 없음) · ST-01306 45행 닫음
09-17   전부 해소 — abs_gap 318 → 6 · unknown 10 → 0
09-18   25칸 → 1칸 — TR-04730 24칸(fix-transfer-bins · abs_gap 306 → 7) · ANN07490 1칸(Deprecated 잔재 · 남긴다)
```

### I-4. ⚠️ 내가 틀린 것
- **`ST-01300` 을 원인으로 단정**했다가 「홀드는 13일간 무해했고 캡과 겹쳐 터진 것」으로 정정 ⇒ ⭐ **`hold_capped` 를 ⑦ 컬럼에서 읽고 `summary` 안에도 있다고 가정**한 것이 출발이었다(`summary` 에는 전 기간 null). 반대로 `cursor_held_by` 는 컬럼이 아니라 `summary` 안이다(스킬 ⑦ SQL 을 `summary->'cursor_held_by'` 로 적었다).
- 09-17 에 **「`ST-01306` 은 닫아도 계속 재검출된다」**고 판단 → 틀렸다. `last_detected` 를 보지 않고 `resolved_at is null` 만 봤다.
- 09-18 에 **`TR-04730` 이 09-14 부터 두 벌이었다**고 읽었다 → 표를 잘못 읽은 것. 09-14 는 전부 실제 bin 이었다.
- 「누군가 열어서 `LastModifiedOn` 이 갱신됐다」 가설 → 실측으로 기각(09-14 12:48:39.967Z 그대로).
- ⚠️ **`ANN07490` 을 「원장이 못 받았다」로 읽을 뻔했다** — Movements 에 입고 1건뿐인 것을 보고서야 「Cin7 이 뺀 것」임을 알았다.

### I-5. ⬜ 남는 것
- `cursor_stalled_alert` 발화 조건(§B) · ⑩-b 사각지대 확장(§D · 판단은 Caleb) · `inv-collect` 의 빈 bin 방지(§D) · `transfer` 경고 4건(아흐레째) · `null_bin_nonzero` 6건(④)
