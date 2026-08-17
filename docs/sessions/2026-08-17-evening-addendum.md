# 2026-08-17 저녁 추가분 — 리시빙 작업자 기록 · PO-01083 정리

`docs/sessions/2026-08-17-ledger-02b.md`(원장 ②-b) 이후, 같은 날 저녁에 한 **원장과 무관한**
작업 기록. 스킬·설계 정본 갱신(`fb5bd73`) 이후의 커밋들이다.

---

## 1. ⚠️ 내일 아침 확인할 것 (가장 먼저)

### A. 라인별 작업자 기록이 실제로 들어가는지

오늘 만든 컬럼은 **신규 작업분부터만** 찬다. 배포가 오늘 저녁이라 **오늘 데이터는 전부 NULL** 이다.
내일 리시빙 작업이 한 건이라도 돌면 확인할 것:

```sql
select r.po_number, l.last_received_by, count(*) as lines,
       min(l.last_received_at at time zone 'America/Toronto') as first_touch,
       max(l.last_received_at at time zone 'America/Toronto') as last_touch
from wms_receipt_lines l join wms_receipts r on r.id = l.receipt_id
where l.last_received_by is not null
group by 1,2 order by 1,3;
```

**볼 것**:
- 값이 들어가는가 (0행이면 receiver 쓰기 경로가 안 도는 것 — `patchFor` 확인)
- **한 receipt 에 여러 이름이 나오는가** — 나눠 받기가 제대로 기록되는지의 증거
- `Putaway →`(자동배정) 버튼만 눌러도 이름이 찍히지 않는가 — 찍히면 `putaway_auto` 분리가 깨진 것

### B. admin 화면 3곳이 정상인지

- Receiving 이력 `RECEIVED BY` 열 — 실명 여러 개 또는 `~이름 (started by)` 회색 폴백
- Stats `Throughput by worker` — 실명 행과 `~이름` 폴백 행이 **분리**되어 있는지
- Review 모달 — 참여자 전원 나열

⚠️ **오늘 데이터는 거의 전부 폴백이라 화면이 종전과 비슷해 보이는 것이 정상.**

### C. ⚠️ PO-01113 은 오늘도 내일도 화면에 안 나온다 — 오판 금지

`created 08-14 → completed 08-17 · 101 lines · 8,622 units (Jaeyoung Choi)`.
기간 기준 수정(`6ee3d16`)의 대상 케이스지만, **그 라인들은 컬럼 도입 전에 받은 것이라
`last_received_at` 이 NULL** 이고 `created_at` 은 08-14 다 → 오늘/내일 기간에서 탈락.

**"안 고쳐졌다"고 판단하지 말 것 — 데이터가 없어서지 로직이 틀려서가 아니다.**
실제 검증은 **며칠에 걸친 receipt 를 새로 작업했을 때** 가능하다.

---

## 2. 리시빙 작업자 기록 (커밋 4개)

### 문제

`wms_receipts.received_by` 는 **receipt 를 처음 만든 사람**이고 이후 갱신되지 않는다.
리시빙은 **여러 작업자가 나눠 받는 것이 기능**인데(규칙 24) 귀속이 receipt 단위였다.

[실례] **PO-01131** — `RECEIVED BY` = Joyce Chang. 실제로는 **들어갔다 나온 사람**이고
62라인·3,570유닛은 다른 사람들이 받았다.

⚠️ 틀린 표시가 **한 곳이 아니라 셋**이었다:
1. admin Receiving 이력 `RECEIVED BY` 열
2. Stats `Receive N lines` — 시작한 사람에게 **전량 귀속**
3. Stats `avg N min work time` · `putaway N%` — 나눠 한 작업이 한 사람 실적으로

📌 **처음 진단은 "헤더를 `STARTED BY` 로 고치면 된다"였고, 그것은 불충분했다.**
Caleb 이 Stats 화면을 지목해 「이미 라인별 작업자가 있는 것 아닌가」물었고, 확인 결과
Stats 도 같은 `received_by` 기반이었다 — 즉 **화면 하나의 문구 문제가 아니라 데이터 결손**이었다.
(교훈: 표시 문제로 보이는 것의 뿌리가 스키마인 경우가 있다)

### 확정한 설계

**`wms_receipt_lines.last_received_by` — 라인당 1명(마지막으로 만진 사람).**

한 라인을 두 사람이 나눠 받으면 앞사람이 사라지지만, **receipt 전체로는 참여자가 전원 드러난다**
(각자 마지막으로 만진 라인이 있으므로) → 표시는 **receipt 의 distinct**.

⊘ 폐기한 대안: 라인당 참여자 배열(`text[]`) — 정확하지만 한 라인이 두 사람에게 각각 1줄로
세어져 **"N lines 받았다"의 합계가 실제 라인 수를 넘는다.** 지표의 의미가 흐려진다.

### 커밋

| 커밋 | 내용 |
|---|---|
| `41ef76b` | 마이그레이션 — `last_received_by` text NULL · `last_received_at` timestamptz NULL |
| `1acfcd1` | receiver.html — 라인 저장 시 기록 |
| `64afcb2` | admin.html — 표시 3곳 + Stats 라인 단위 귀속 |
| `6ee3d16` | admin.html — Stats 기간 기준을 라인 작업 시각으로 |

⚠️ **NOT NULL·DEFAULT·백필 전부 금지**로 만들었다. 특히 **`received_by` 복사 금지** —
그게 바로 지금 틀린 값이다. NULL = "컬럼 도입 전 라인"이라는 정보 자체가 의미를 갖는다.

### 어디에 찍고 어디를 뺐나 (`1acfcd1`)

| 경로 | kind | 스탬프 | 근거 |
|---|---|---|---|
| `saveLine`(스캔·스테퍼·수동입력) | `qty` | ✅ | 실물을 센 사람 |
| `savePutaway`(수동 bin/Change/Placed) | `putaway` | ✅ | 라인을 실제로 만진 작업 |
| `Place all in this bin` | `putaway` | ✅ | 물리적으로 다 놓고 누르는 실작업 |
| 재시도 병합 flush | `all` | ✅ | 실작업이 섞였을 때만 생기는 kind |
| off-PO 라인 생성 | `insert` | ✅ | 사람이 실물을 보고 만드는 라인 |
| **자동배정 저장** | **`putaway_auto`**(신규) | ❌ | ⚠️ `Putaway →` 버튼 하나로 전 라인에 누른 사람이 찍히면 **"연 사람 = 전량 귀속" 버그의 라인판 재현.** 그 라인들도 이후 Placed/Change 때 정상 기록된다 |
| PO 라인 초기 적재(`startPo`) | — | ❌ | 껍데기 생성(받은 것 0) |

📌 `mergeKind` 로 `putaway_auto` 가 수동 쓰기와 병합되면 `all` 로 승격해 스탬프가 찍힌다 —
실작업이 섞였다는 뜻이라 의도된 동작.

### 폴백 규칙 (`64afcb2`)

- 라인에 값이 **하나라도** 있으면 **라인 값만** 쓴다(NULL 라인 무시)
- 라인이 **전부 NULL** 이면 `received_by` 폴백 — **회색 + `~` 접두 + `(started by)` 꼬리표**
- Stats 는 폴백 키 자체가 **`~이름`** → 실명 행과 **병합되지 않는 별도 행**
- ⚠️ **폴백 값은 틀린 값이다**(시작한 사람). 정확한 값처럼 보이면 이번 수정의 의미가 없다

**work time 재정의**: 사람별 `min(last_received_at) ~ max(last_received_at)`.
종전 `workMinutes(created_at, completed_at)` 은 receipt 전체 구간이라 사람별로 쪼갤 수 없었다
(셋이 나눈 4시간을 셋에게 4시간씩 주면 합계가 부푼다). **폴백 그룹은 계산하지 않는다** —
없는 값을 만들어내지 않는다(기존 렌더 가드가 `rN=0` 을 자연 처리).

**부수 변화**: 받은 라인이 0인 receipt 는 이제 `byWorker` 에 안 잡힌다(종전 `n=1·lines=0`).

### ⚠️ 기간 기준 결함 (`6ee3d16`) — 별개로 발견된 것

Stats 가 **`wms_receipts.created_at`** 으로 기간을 잘랐다.

리시빙은 픽/팩과 다르다: **한 PO 가 며칠 열려 있고**(분할 입고·held) 그동안 여러 사람이 붙는다.
"언제 시작했나"로는 "언제 일했나"를 못 센다.

[실측] `PO-01113` created **08-14** → completed **08-17** · 101 lines · 8,622 units
⇒ 오늘 8,622유닛을 받았는데 **오늘 Stats 에서 통째로 빠졌다.** 화면에는
`Jaeyoung Choi · Receive 0 lines / 1 receipt`(그 1건은 오늘 만든 빈 receipt PO-01117).
**오늘 가장 많이 받은 사람이 실적 0으로 보였다.**

수정 = **(가)안**: 쿼리는 `created_at <= to` + `completed_at is null or >= from` 으로 넉넉히 받고,
**귀속 판정은 라인에서** — 라인에 `last_received_at` 이 있으면 그 값 기준, NULL 이면 receipt
`created_at` 폴백. 한 receipt 가 실명 그룹과 `~폴백` 그룹에 **동시에 기여할 수 있다**(의도).

**지표별 기준**:

| 기준 | 지표 |
|---|---|
| `created_at` (receipt 단위 유지) | PO/Transfer receipts 카운트 · Applied / bins failed / not applied · avg receive · avg complete→apply |
| 라인 `last_received_at` (NULL 은 폴백) | T/byWh 의 lines·units(상단 Units received 카드 포함) · putaway · backlog · transfer moved · `byWorker` 전부 |

### 아직 안 한 것

- **`saveLine` 의 `qty` 경로가 "값이 실제로 바뀔 때만" 도는지 미확인** — 같은 값 재저장에도
  UPDATE 가 나가면, 확인차 스테퍼를 눌렀다 되돌린 사람이 마지막 작업자가 된다.
  드물고 "마지막으로 만진 사람" 정의상 틀린 것도 아니라 **실데이터 보고 판단**
- 과거 데이터 소급 불가 — 영구히 폴백으로 남는다

---

## 3. PO-01083 정리 (매니저 오조작 대응)

### 경위

PO-01083 은 **"손대지 말고 매니저 상의 후 처리"로 정해둔 건**(크레딧 노트 / 이중 인보이스)이었는데
매니저가 Apply 를 눌렀다. 14:54 첫 Apply 부분 실패 → 15:27 Retry.

**Cin7 응답 400**:
```
BNAT48137 has quantity invoiced 107.0000 which is different from quantity received 214.0000
```
(214 = 107 × 2 — 이중 인보이스 건의 그 모양)

### 상태 판정

- `exported_base = 0` (36라인 전부) — **WMS 가 쓴 것으로 마킹된 라인 없음.** PO-01027 때의
  최악(부분 exported 잔류)은 아니었다
- stage2(빈 배치)는 **all-or-nothing** → 0 bin posted
- ⚠️ 단 **stage1(입고)은 이미 AUTHORISED** 라 이번 회차에 건너뛰었다 —
  `STOCK IS IN Cin7 WITHOUT SHELF LOCATIONS`. "아무 일도 안 일어났다"가 아니었다
- **매니저가 Cin7 에서 수동으로 리시빙 + put-away 완료** → Cin7 쪽은 완결

### 처치

`apply_note` 안의 **`failed_moves(9)`** 문자열이 카드/버튼의 근거였다(admin 2586행 정규식).
⚠️ 이 문자열은 **EF `buildApplyPlan` 재개 게이트와 공유하는 계약 포맷**(2588행 주석) —
한쪽만 바꾸면 안 되는데, 이 경우 양쪽에 동시에 작용하는 것이 원하는 결과였다.

```sql
update wms_receipts
set apply_note = replace(apply_note, 'failed_moves(9)',
      'RESOLVED_MANUALLY_IN_CIN7 2026-08-17 (was failed_moves 9 bins; Cin7 receiving +
       put-away completed by manager; WMS exported_base intentionally left 0) resolved_moves(9)')
where po_number = 'PO-01083' and apply_note like '%failed_moves(9)%';
```

- 정규식 `failed_moves\((\d+)\)` 이 `resolved_moves(9)` 는 안 잡는다 → 카드 소멸(확인됨)
- **원문 로그는 전부 보존** — 실패 사유·bin 목록·수량이 그대로 남는다
- `exported_base` 는 **0으로 둔다** — WMS 가 쓴 게 실제로 없으니 사실이고,
  ⚠️ 규칙 30-4(수동 UPDATE 금지) 대상 컬럼이다
- `where ... like` 로 재실행 방지

### ⚠️ 남는 것 — 근본 원인은 오조작이 아니다

**"손대지 말 것" 표시가 WMS 에 없다.** PO-01083 은 매니저 기억으로만 구별되고 있었고,
Apply 화면에서는 다른 receipt 와 똑같이 버튼과 함께 서 있었다.

⇒ **receipt 단위 보류(hold) 표시**가 필요하다. 백로그의 「I&R 그룹 분리 검출」(그룹 2개면 차단)은
같은 계열이지만 그것만으로는 안 덮인다(이번 건은 그룹이 아니라 인보이스 수량 문제였다).

---

## 4. 그 외 오늘 확인된 것

- **Cin7 POS 오더는 원장에 정상 기록된다** — 원장은 WMS 가 아니라 **Cin7 문서**를 본다.
  POS 판매도 `sale` 문서이고 SHIPPED 면 `saleList` 수집이 잡는다.
  WMS 의 `⊘ Void` 는 **작업 큐 정리**이지 재고 처리가 아니다(둘은 독립).
  ⚠️ 단 **POS 경로의 `CombinedShippingStatus` 가 SHIPPED 로 서는지는 미확인** —
  안 서면 `skip_not_shipped` 로 탈락해 출고가 원장에 안 잡힌다. ③ 검증 항목으로 추가할 것
  (오늘 dry 의 `skip_not_shipped: 143` 에 POS 건이 섞였는지 미확인)
- **SO-14839**(PURE CRATE) — Cin7 CLOSED 감지, `0/1 packed`. Void 로 정리 가능.
  ⚠️ 물리적으로 픽된 물건은 **사람이 선반에 되돌려야 한다**(버튼은 데이터만 정리)

---

## 5. 다음 (원장 ③ 검증과 별개로 열려 있는 것)

1. **내일 아침 §1 확인 3종**
2. `saveLine` qty 경로 무변경 저장 여부 판단(실데이터 보고)
3. **receipt 보류(hold) 표시** — 오늘 사고의 근본 원인
4. `CLAUDE.md` 에 `git push` 금지 명시 (Claude Code 가 두 번 어김)
5. 스킬 zip 을 claude.ai 에 업로드 — zip 은 만들어 뒀다(`~/asung-inv-ledger.zip`),
   `chang/Downloads` 복사만 남음
6. `asung-wms` 스킬 규칙 33 에 「원장 날짜 정확도」 한 줄
7. ⚠️ **`asung-wms` 스킬에 이번 리시빙 작업자 변경 반영** — `wms_receipt_lines` 스키마에
   컬럼 2개 추가, `received_by` 의미("시작한 사람") 명확화, 규칙 24(나눠 받기)와의 관계
