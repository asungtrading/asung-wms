# 2026-09-19 · 09-22 아침 점검 — 판매 축 사각지대 확정 · ⭐ 「Ship-undone」 vs 「VOID」 · 플립 기준 교체

관련: `asung-inv-ledger` §아침 점검 ④·⑤·⑧·⑩·⑩-b·**⑪**(09-22 블록)·「지금 알려진 잔재 2칸」·§2 함정 표 「수집 후 취소」 행·§하드 플립 판단(09-22 다시 씀) ·
`docs/design/ledger-design.md` §「수집 후 취소」(`sale` 축 계약 · Ship-undone) · §「플립 — 이관」(플립 기준) ·
앞선 건 `2026-09-18-cursor-stall-double-write.md`(커서 정체 계열 · `ANN07490` 신규 당시) · `2026-09-15-bin-change-double-write.md`(⑩-b).
⚠️ 표기: **[실측]** = 운영 DB(`inv_collect_runs` · `inv_voided_docs` · `inv_balance_vs_cin7` · `inv_conflicts`) · Cin7 화면·API · 레포/배포 코드에서 읽은 값 · **[추론]** = 판단.
📌 역할 분담: **스킬은 요약+함정 · `ledger-design.md` 는 계약 · 이 파일은 실측 근거.**
📌 지시서: `~/asung/prompts/prompt-doc-update-9.md`(9차). ⚠️ §A 는 지시서의 정정을 **그대로 받지 않았다** — 코드 대조 결과를 함께 적고 이의로 남긴다(§A-0).

---

## A. ⭐⭐ 09-19 판단의 정정 시도 — 그리고 코드가 그것을 받쳐주지 않는다

### A-0. ⚠️⚠️ 이의 — 「`inv_voided_docs` 는 `sale` 을 잡는다」는 코드로 설명되지 않는다

지시서 9차는 「09-19 에 `sale` 축 VOID 감시가 없다고 결론지은 것이 틀렸다 — `inv_voided_docs` 는 `sale` 을 잡는다(`SO-16464` 실증)」로 정정하라고 했다. **적용 전에 코드를 대조했다.**

```
[실측 레포 supabase/functions/inv-collect/index.ts · 2026-09-22]
  213행  주석: detectVoided — adjustment·assembly 만
  221·226·231행  detectVoided: true — SOURCES(②-a) 의 adjustment · transfer · assembly 셋
  238행  DATE_SOURCES(②-b) — sale · … : detectVoided 필드 자체가 없다
  1266~1269행  if (cfg.detectVoided) { … detectVoidedDocs(cfg.docType, …) }  ← 유일한 호출
  1998행  ②-b sale: if (Status === "VOIDED") { tally("skip_voided"); continue; }  ← 세기만 한다
  inv_voided_docs 를 쓰는 곳: upsertVoidedDocs(553행) 하나 · 호출부는 ②-a commit 경로만
[실측 운영 배포판]
  supabase functions list — inv-collect version 29 · updated_at 1788812106214 = 2026-09-07 20:15:06Z
  레포 마지막 커밋 b5accee 2026-09-07 16:19 EDT(= 20:19Z) 「VOID 감지 transfer 축 관측 켬」 — 같은 날
  supabase functions download inv-collect --use-api (스크래치 디렉터리) → diff -q 레포 → IDENTICAL · 206,981 바이트 양쪽 동일
```
⇒ **수집기(레포 = 배포판)에는 `sale` 문서를 `inv_voided_docs` 에 쓸 경로가 없다.** 다른 EF·마이그레이션·GAS 에도 이 표를 쓰는 코드는 없다(`grep -rl inv_voided_docs supabase/` — `inv-collect` 와 표 정의 마이그레이션뿐).

**그런데 표에는 있었다** — [Caleb 실측 09-22 ⑪ 조회] `SO-16464` · `ledger_rows 1` · `ledger_net −1` · `first_detected 2026-09-21 15:04:03` · `last_seen 09-22 08:19` · `ledger_net −1` 이 ⑧ 의 `diff −1` 과 일치.

⇒ 둘 다 사실이면 그 행은 **수집기가 쓴 것이 아니다.** 후보(⚠️ 전부 추론): 사람이 넣었다(09-21 세션에서 등록했을 가능성) · 배포판이 09-22 이전 어느 시점에 잠깐 달랐다(⚠️ `updated_at` 이 09-07 이라 가능성 낮음).
⬜ **판별법: 그 행의 `collector`·`doc_type`·`doc_status` 를 읽는다** — EF 가 쓴 행은 `collector = 'inv-collect@2026-09-05.1'` 이 박힌다. null 이거나 다른 값이면 사람이 넣은 것.
```sql
-- [운영 · asung-WMS]
select doc_type, doc_number, doc_status, collector, ledger_rows, ledger_net,
       first_detected_at at time zone 'America/Toronto' as detected_toronto,
       last_seen_at at time zone 'America/Toronto' as last_seen_toronto,
       resolved_at, resolution_note
from inv_voided_docs where doc_number = 'SO-16464';
```
⇒ ⚠️ **확인 전까지 스킬·정본에는 「`sale` VOID 는 ⑪ 이 잡는다」를 적지 않았다.** 09-19 결론(「`sale` 축 VOID 감시가 없다」)은 **코드 기준으로 그대로 맞고**, 지시서의 정정은 이의로 남긴다. 지시서가 옳았던 부분은 따로 있다 — **판매 축의 진짜 사각지대는 Ship-undone 이고 범위가 좁다**(§A-2).

### A-1. 09-19 에 무엇을 결론지었나

`SO-16531` 이 네 창구(③·⑩·⑪·⑫)에 안 잡혔고, ⑪ 회차 관측(`voided_seen`)에 `adjustment`·`assembly`·`transfer` 셋만 나오는 것을 근거로 「`sale` 축 VOID 관측이 아예 없다」로 적었다. Claude Code 조사는 그때 「`detectVoidedDocs` 는 `Status === "VOIDED"` 만 본다」로 정확했다.
📌 09-22 코드 대조로 보면 **결론 자체는 맞았다**(경로가 없다). 지시서가 지적한 「회차 관측에 없는 것과 표에 없는 것의 혼동」은 주의로 남긴다 — 회차 관측(`voided_seen`)은 ②-a 만 채우고 `sale` 은 절대 나오지 않는다. 표는 ⑪ 첫 SQL 로만 본다.

### A-2. ⭐ 두 사건 — Ship-undone 과 VOID 는 다른 것이다

| 사건 | Cin7 `Status` | `CombinedShippingStatus`(추정 · ⬜ 어휘 실측) | 원장 | 어떻게 드러났나 |
|---|---|---|---|---|
| `SO-16531` — Shipping 만 undone · 오더는 살아 있음 | `AUTHORISED` | `SHIPPED` 아님 | `sale_out` −112 남음 | ⑧ 8칸 −112(09-19) → 재출고로 09-22 소멸 |
| `SO-16464` — 오더 자체 VOID | `VOIDED` | — | `sale_out` −1 남음 | ⑧ 1칸 −1 + ⑪ 표에 행(출처 미규명 · §A-0) |

⇒ **VOID 는 `Status` 로 판정할 수 있는 사건**이고(코드가 있으면 잡힌다 — 지금은 `sale` 에 없다), **Ship-undone 은 `Status` 로는 절대 못 잡는 사건**이다(오더가 그대로 `AUTHORISED`). 사각지대의 정확한 진술은:
> **`sale` 축은 VOID 도 Ship-undone 도 코드가 없다. 그중 VOID 는 `Status` 로 잡을 수 있어 ②-a 와 같은 모양으로 붙일 수 있고, Ship-undone 은 `CombinedShippingStatus` + 「원장에 `sale_out` 이 있나」로만 잡힌다.**

### A-3. ⬜ Ship-undone 감시 — 신호는 이미 온다

`inv-collect/index.ts` 2000행: `if (norm(row?.CombinedShippingStatus) !== "SHIPPED") { tally("skip_not_shipped"); continue; }` — 배송 전 오더를 걸러내는 자리다. **여기서 「이 `doc_number` 가 원장에 `sale_out` 을 갖고 있나」를 묻는 코드가 없다.** 목록에 이미 있으므로 새 API 호출 0건 · 원장 REST 조회 하나(⑪ 과 같은 모양).
⬜ **구현 전 `CombinedShippingStatus` 어휘 실측** — GAS 프로브로 `saleList` 분포를 센다. `PARTIALLY SHIPPED` 가 있으면 부분 배송을 오탐한다. 어휘를 모르고 조건을 넓히지 않는다(⑩-b 와 같은 원칙).
⭐ 판매 취소는 **가장 빈번한 축**이다(Caleb 확인 · 손님 변심 · 결제 후 픽업 전 fulfillment 선생성 후 취소).

---

## B. 09-19 `SO-16531` — Ship-undone (기다려서 해소)

```
09-18 15:33:23  Shipping 승인
09-18 15:34:06  원장 수집 (−112 · 8 SKU)   ← 43초 뒤
09-18 16:33:22  ⚠️ Shipping undone
09-19 01:21     스냅샷 대조에서 8칸 −112
09-22 01:21     ⭐ 사라짐 — 재출고되어 저절로 맞았다
```
⇒ ⭐⭐ **상쇄하지 않은 판단이 옳았다.** 오더가 open 이었고 재출고로 해소됐다. ⚠️ 상쇄했다면 재출고 때 이중이 될 뻔했다.
📌 8 SKU 합계 112 = Cin7 오더 라인 Total 112 = ⑧ 토론토 `abs_gap` 112.
📌 그동안 안 보였던 것은 **타이밍 운**이다 — Ship 승인 43초 뒤에 수집이 들어갔다.

⇒ **판정 기준(스킬 ⑪ · 정본 §「수집 후 취소」에 적었다):** Ship-undone 으로 보이는 어긋남은 오더 상태로 처방이 갈린다 — **살아 있으면 기다린다 · VOID 됐으면 상쇄한다**(§C).

---

## C. 09-22 `SO-16464` — 판매 VOID (상쇄)

**경위**
- `SO-16461`·`SO-16464` 두 오더가 09-21 14:39 같은 회차에 수집(각 −1)
- `SO-16461` — 정상 Ship → Completed → **Closed** ✅
- ⚠️ `SO-16464` — Ship 후 VOID(Caleb 확인)
- ⇒ 원장은 둘 다 뺐고 Cin7 은 하나만 ⇒ `ASHHNVW18`/`EU070202` **−1**(`baseline 3` · `delta −2` · `qty 1` vs Cin7 2)

**처방(실행함 · [운영 · asung-WMS])** — 원래 타입 유지 · 부호 반전 · `:voided` 접미어 · `resolved_at` 함께
```sql
insert into inv_ledger
  (doc_type, doc_number, source, event_type, sku, warehouse, bin,
   line_ref, qty_delta, occurred_on, seq_hint, raw)
values
  ('sale', 'SO-16464', 'manual', 'sale_out', 'ASHHNVW18',
   'Asung - Edmonton', 'EU070202',
   'b79f7870-2ff6-4d95-9a9a-50175660925a:d131008c-06e4-4978-b55d-6f4f53b9074d:voided',
   1, '2026-09-21', 2,
   jsonb_build_object(
     'rule', 'voided after collection: Cin7 sale VOIDed after the ship was already collected. reverse the ledger row',
     'reason', 'morning-check-11 · inv_voided_docs detected 2026-09-21 15:04 · ledger_net -1 · order is voided (not re-shipping)',
     'original_line_ref', 'b79f7870-2ff6-4d95-9a9a-50175660925a:d131008c-06e4-4978-b55d-6f4f53b9074d',
     'by', 'caleb', 'at', '2026-09-22'
   ));

update inv_voided_docs
set resolved_at = now(),
    resolution_note = 'reversed 2026-09-22: manual sale_out +1 with :voided suffix. order VOIDed in Cin7, not re-shipping.'
where doc_number = 'SO-16464' and resolved_at is null;
```
**검증**: `doc_net 0` · `rows 2` · `inv_balance_vs_cin7` `ledger 2 / cin7 2 / diff 0` ✅
⚠️ **⑪ 은 상쇄만으로 닫히지 않는다 — `resolved_at` 을 함께 넣어야 한다.** 스킬에 있던 규칙의 **첫 실전 적용**이다.
📌 판매 `line_ref` 는 `<fulfilment TaskID>:<ProductID>` **복합**이다 — 접미어는 그대로 이어붙인다. ⚠️ `:` 로 자르지 말 것.

---

## D. ⚠️ `TR-04496` — 열하루 정체 (실무 처리 필요)

```
[실측] summary->'cursor_held_by' = { "reason": "hold_status:ORDERED", "doc_number": "TR-04496" }
       transfer 커서 TR-04495 — 2026-09-12 부터 열하루
```
⇒ ⭐ `ST-01300`(DRAFT 13일)과 같은 상황이다. 홀드만으로는 무해하지만 쌓인 문서를 매 회차 다시 훑는다.

**[실측] 부작용이 나타나기 시작했다:**
| 날짜·시각(토론토) | 관측 |
|---|---|
| 09-21 09:22 | ⚠️ `ok=false` · **502** · `list_total 5,085` |
| 09-21 17:37 | ⚠️ `ok=false` · **502** · `list_total 5,126` |
| 09-22 05:47 | `detail_capped` · `max_detail` · `remaining 3` · `list_total 5,075` |

⇒ `stockTransferList` 502 가 누적 **다섯 번**(09-17 · 09-18 · 09-21 두 번 + 이전). 📌 `list_total` 5,000건대가 부담이라는 것은 **추론**. ⭐ 502 회차는 아무것도 안 쓴다(`ok=false` · `write_skipped`) — 설계 정상 동작.
⇒ ⭐ **처방: Cin7 에서 `TR-04496` 을 출고하거나 취소하면 커서가 풀린다.** ⚠️ 두지 말 것 — 09-18 `TR-04730`(bin 해석 실패 · 24행 중복)이 이 상태에서 났다.

---

## E. 해소·종결된 것 셋

1. ⭐ **`ANN07490` 해소**(09-19) — 실무에서 조정으로 1개를 털었다. 원장이 받아 양쪽 0. 8차 지시서에서 「잔재 2칸 → 3칸」으로 올린 것을 **2칸으로 되돌렸다**(스킬 ⑧ · 잔재 표 · 다음에 할 일 3 · 09-18 기록 헤더·§E 후기). 📌 「Deprecated 라 계속 남는다」 예상은 하루 만에 깨졌다 — **해소는 실무 쪽**이라는 판정과 **상쇄 금지**가 맞았다.
2. ⭐ **`ST-01306` 완전 종결**(09-19~22 조용) — 09-18 에 id 128 을 닫은 뒤 재검출 0. 📌 `adjustment` 커서 전진으로 재조회 창을 벗어난 것으로 보인다(**추론**).
3. ⭐ **`SO-16531` 해소**(09-22) — §B.

---

## F. 관측 갱신

### F-1. ⚠️ `PRO00124` 가 음수로 보이기 시작했다
| | 09-19 이전 | 09-22 |
|---|---|---|
| `EB010302` | 원장 3 / Cin7 0 · **+3** | 원장 **12** / Cin7 9 · **+3** |
| `EB010304` | 원장 0 / Cin7 3 · **−3** | 원장 **−3** / Cin7 0 · **−3** |
⇒ **확정된 것만**: `diff` ±3 그대로(거울상 유지) · `EB010304` 원장이 −3 으로 음수가 됐다(원장은 음수를 허용) · 같은 건이고 **재기준선이 지운다** · ⚠️ 상쇄하지 않는다.
⚠️ [Caleb 09-22] 「`EB010302` 실물이 소진되며 기초 3개가 함께 나갔다」는 쓰지 않는다 — `EB010302` 는 3 → 12 로 **늘었다.** 그 칸에 다른 입고가 있었다는 뜻이고, 위 표만으로는 어느 사건이 12 를 만들었는지 모른다. **원장 행을 확인하지 않았다.**

### F-2. ⑩-b 읽는 법 — 「0행이 정상」이 아니다
기준선 2건(`TR-04729` · `TR-04174`)이 나오는 것이 정상이다. **0행이면 검사가 죽은 신호**로 읽어야 한다. [09-19] 조회가 0행으로 나와 검사가 죽은 줄 알았으나 `select count(*) from d` 로 **`total_rows 2`** 를 확인해 살아 있음을 확정했다. ⇒ ⭐ 판정이 갈리는 값은 `count(*)`·`id` 를 함께 뽑아 확인한다.

### F-3. ④ 관측폭
09-20 **0** / 09-21 −36 / 09-22 **+65**. 주말 이틀 `insert_rows` **13,835 무변** — ① 과 정합. 관측폭 −700 ~ +535 유지(갱신 없음).

---

## G. ⭐⭐ 플립 기준 교체 — 「30일 어긋남 0건」 폐기

### G-1. 왜 폐기하나
그 기준의 전제는 「어긋남이 나오는 것 = 원장에 문제가 있는 것」이었다. 한 달 실측(2026-08-20 ~ 09-22)이 그 전제를 반증했다.

| 원인 층 | 건수(지시서 집계) | 문서 대응(⚠️ **추론** — 이 기록에서 붙인 것 · 지시서에는 층 이름만 있다) |
|---|---|---|
| Cin7 쪽 변경(수량 수정 · 자리 변경 · Deprecated · Ship-undone · VOID) | 5 | `SO-15440`(09-04 수량) · `TR-04729`(09-15 자리) · `ANN07490`(09-18 Deprecated) · `SO-16531`(09-19 Ship-undone) · `SO-16464`(09-22 VOID) |
| 수집 층(홀드+캡 · bin 해석 실패) | 2 | `ST-01300`(09-16) · `TR-04730`(09-18) |
| 기초 경계(재기준선이 지울 것) | 2 | `PRO00124` 짝 2칸 |
| ⭐ **원장 계산 오류** | **0** | — |

⇒ 「받은 사건으로 잔고를 계산하는」 일에서 틀린 적이 없다. 업무 관행이 바뀌지 않는 한 어긋남은 계속 나온다 ⇒ 「0건 30일」을 기다리면 영원히 못 넘어간다.
📌 08-24~09-04 의 결함 다섯(`FINAL-SALE` · `TR-04175` · `PO-01133` · `FG-00134` · `SO-15440`)은 스킬 §하드 플립 판단의 옛 (가) 표에 **경위로 그대로 남겼다** — 새 표와 세는 창·기준이 다르므로 합치지 않았다.

### G-2. 대체 기준
> **「틀린 적이 없다」가 아니라 「틀렸을 때 왜인지 안다」.** 한 달간 어긋남 9건이 전부 원인이 규명됐고 「모르겠다」로 남은 것이 없다.
📌 이것이 ①재생성 일치·②사건 종류 전수보다 강한 운영 신뢰의 근거다.

### G-3. ⚠️ 두 조건을 섞지 말 것
| | 상태 |
|---|---|
| 원장의 정확성 | ⭐ 사실상 입증됨 |
| 운영 기능의 완성 | ⚠️ **시작 전** — 가용 재고 · 할당 · 음수 게이트 · 동시성 · 성능 · 되돌리기 |
⇒ 「원장이 정확하다」≠「Cin7 을 덜어낼 수 있다」. 지금 원장은 장부이고 그 위의 운영 층이 없다 — 없어서 에러도 안 났다. 정본은 **IMS 부착 지시서**(§H).
⇒ 스킬 §하드 플립 판단 절 머리에 이 셋을 새로 썼고, 옛 「닫힘 기준 셋 · (가)~(라)」는 경위로 남겼다(지우지 않음). 정본 `ledger-design.md` §「플립 — 이관」에도 계약으로 넣었다.

---

## H. ⬜ IMS 부착 지시서를 레포에 둘지 — Caleb 판단

09-19 작성 「IMS 에 원장을 붙일 때 — 할 일과 뒤따라야 할 검증」. ⚠️ **[실측 09-22] 지시서가 가리킨 `~/asung/prompts/prompt-ims-ledger-attach.md` 경로에 파일이 없다**(`ls` — No such file). 다른 이름으로 있거나 다른 머신에 있을 수 있다(⬜ 확인).
- ✅ **[Caleb 승인 09-22] 둔다** — `docs/design/ims-ledger-attach.md` 로 복사 + `ledger-design.md` 포인터. ⚠️ 넣을 때 그 문서 §6 경고 「원장 축만 봤다 · WMS·PO+원가에 확인할 것」이 살아 있는지 확인(레포에 들어가면 다른 세션도 읽는다).
- ⚠️ **복사는 못 했다** — 09-22 이 머신에서 `~/asung/prompts/` · `/mnt/c/Users/chang/Downloads` 를 이름·본문 문구(「뒤따라야 할 검증」·「음수 게이트」)로 찾았으나 없었다. 다른 머신에 있을 것으로 본다(추론). 포인터는 정본·스킬에 「복사 대기」로 먼저 넣었다.

---

## I. 점검 요약 · 틀린 것 · 남는 것

### I-1. 점검 요약
```
09-19   ⑧ 8칸 −112 (SO-16531 · Ship-undone) → 상쇄 없이 대기 · ANN07490 해소(실무 조정)
09-22   ⑧ 1칸 −1 (SO-16464 · VOID) → 상쇄 + resolved_at · total 10 → 3 · SO-16531 8칸 저절로 소멸
```

### I-2. ⚠️ 내가(대화 Claude) 틀린 것
- ⭐⭐ 09-19 에 「`sale` 축 VOID 감시가 없다」로 결론 → 지시서 9차는 이것을 「틀렸다」로 정정하려 했다. ⚠️ **그러나 Claude Code 의 코드 대조(§A-0)에서 감시 코드가 없음이 배포판까지 확정됐다** — 결론은 맞았고, 틀린 것은 「표에 `SO-16464` 가 있으니 수집기가 잡은 것」이라는 **09-22 의 추정**이다. 회차 관측(`voided_seen`)에 없는 것과 표에 없는 것을 혼동했다는 지적은 주의로 유효하다.
- 09-22 에 `SO-16464` 도 ⑪ 이 못 잡을 것으로 예상 → 표에는 있었다(출처 미규명 · ⬜ `collector`).
- `SO-16464` 의 `line_ref` 를 단일 GUID 로 받아 상쇄 SQL 을 만들었다 → 실제는 `GUID:GUID` 복합(조회 결과가 섞인 것을 검산 없이 썼다).
- ⚠️ 오늘 조회 결과가 여러 번 엇갈렸다(④·⑤·⑦·⑩-b·⑪) — ⭐ 판정이 갈리는 값은 `count(*)`·`id` 로 재확인하는 습관이 필요하다.

### I-3. ⬜ 남는 것
- ⬜ **`SO-16464` 행의 `collector` 확인**(§A-0 SQL) — 결과에 따라 스킬 ⑪ 09-22 블록의 「미규명」을 닫는다
- ⬜ Ship-undone 감시(어휘 실측 선행 · §A-3) · ⬜ `sale` VOID 감시(②-a 와 같은 모양 · 코드 없음이 확정됐으므로 설계 대상)
- ⬜ `TR-04496` 실무 처리(§D) · ⬜ `cursor_stalled_alert` 발화 조건 · ⬜ ⑩-b 빈 bin 사각지대 · ⬜ `transfer` 경고 4건(열이틀째) · ⬜ `null_bin_nonzero` 6건
- ⬜ IMS 부착 지시서 **파일 소재 확인 → 복사**(§H · 승인됨 · §6 경고 유지 확인)
