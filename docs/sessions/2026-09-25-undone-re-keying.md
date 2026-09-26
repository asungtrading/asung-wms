# 2026-09-23 ~ 09-25 아침 점검 — ⭐⭐ `undone` 계열 · 발주 재승인 라인 재키잉 이중(`PO-01361` 31,104) · `detail_error` 첫 관측 · `TR-04496` 2주째

관련: `asung-inv-ledger` §아침 점검 ③·⑤·⑥·⑦·⑩·⑩-b·⑪·⑫ · 「📌 `undone` 계열」(⑫ 뒤 · 번호 없음) · 「다음에 할 일」 0-0 ·
`docs/design/ledger-design.md` §「`undone` 계열」(계약 · 「변경 감지가 못 보는 축 — bin 변경 이중 기입」 뒤) · §「수집 후 취소」(`sale` 축 Ship-undone) ·
앞선 건 `2026-09-22-ship-undone-vs-voided.md`(Ship-undone · 같은 계열) · `2026-09-15-bin-change-double-write.md`(⑩-b · 키 일부가 바뀌는 첫 실증) · `2026-09-18-cursor-stall-double-write.md`(커서 정체 계열 · `TR-04496`).
⚠️ 표기: **[실측]** = 운영 DB(`inv_ledger` · `inv_missing_lines` · `inv_missing_docs` · `inv_collect_runs` · `inv_balance_vs_cin7`) · Cin7 화면·Activity log · 레포 코드에서 읽은 값 · **[추론]** = 판단.
📌 역할 분담: **스킬은 요약+함정 · `ledger-design.md` 는 계약 · 이 파일은 실측 근거.**
📌 지시서: `~/asung/prompts/prompt-doc-update-10.md`(10차). ⚠️ §A-0 에 지시서의 실측 하나(⑫)가 레포 코드와 어긋난다는 대조를 함께 적는다 — 확인 전.

---

## A-0. [실측 · 레포 코드] 문서화 전 대조 둘

1. ⚠️ **⑫ `inv_missing_docs` 는 레포 코드상 발주를 기록하지 않는다 — 확인 전.**
   `supabase/functions/inv-collect/index.ts:215-233` — `detectMissingDocs: true` 는 `adjustment` · `assembly` 둘뿐이다(주석: 「다른 축은 inv_missing_lines 로 정상 처리되므로 이 표에 넣지 않는다」).
   발주가 도는 날짜 커서 경로(DATE_SOURCES)는 `insertMissingLines` 만 부르고(`:2613`) `upsertMissingDocs` 는 부르지 않는다(`:1913` 은 SOURCES 경로).
   그런데 09-25 점검은 ⑫ `missing_qty 31,104`(옛 벌과 정확히 일치)를 보고했고, 처방 SQL 이 `inv_missing_docs` 도 닫았다.
   ⬜ 운영에서 확인할 것:
   ```sql
   -- [운영 · asung-WMS]
   select doc_type, doc_number, missing_lines, missing_qty, first_detected_at, resolved_at
   from inv_missing_docs where doc_number = 'PO-01361';
   select doc_type, count(*) from inv_missing_docs group by 1;
   ```
   행이 있으면 배포판이 레포와 다르다(09-22 는 v29 = 레포 바이트 동일이었다). 없으면 그날 엇갈린 조회 중 하나였다(§F). [추론] 둘 다 가능하다.
2. **`detail_error` 는 새로 생긴 사유가 아니라 첫 관측이다.** 코드에 캡 사유가 넷 있다 — `max_detail` · `time`(`:1425-1426` · `:2189-2190`) · `rate_limited`(`:1434` · `:2216`) · `detail_error`(`:2217` · 날짜 커서 경로만).

---

## A. ⭐⭐ `undone` 계열 — 새 절로 묶는다

### A-1. 무엇이 공통인가

> **Cin7 에서 승인된 작업을 되돌리면(`undone`), 원장은 이미 받은 사건을 들고 있다.
> 그 뒤 무엇이 남는지는 축마다 다르다.**

| 축 | 조작 | Cin7 결과 | ⚠️ 원장에 남는 것 | 잡는 창구 |
|---|---|---|---|---|
| **판매** | `Shipping undone` | 오더 `Status` 는 `AUTHORISED` 유지 | 출고가 **남는다**(과다 차감) | ⚠️ **지금 없다** — 신호는 `inv-collect/index.ts:2000`(`skip_not_shipped`)에 도착해 있다 · ⬜ 어휘 실측 후 구현 가능 |
| **판매** | 오더 **VOID** | `Status = VOIDED` | 출고가 남는다 | ⭐ ⑪ `inv_voided_docs`(⚠️ 09-22 코드 대조: `sale` 축 VOID 창구 코드 없음) |
| **발주** | `Stock received undone` **+ 재승인** | 라인 GUID **재발급** | ⭐ 입고가 **두 벌**(과다 유입) | ⭐ ③ `inv_missing_lines` · ⑫ `inv_missing_docs`(⚠️ §A-0) · ⑥ |

⇒ ⚠️⚠️ **발주 쪽이 더 위험하다** — 재승인이 **새 `line_ref`** 를 만들어 **키가 달라지니**
⑩(`inv_conflicts`)도 ⑩-b(bin 변경)도 **전부 못 본다.**
⭐ 오늘은 ③·⑫ 가 잡았다(⑫ 는 §A-0 확인 전).

📌 Shipping undone 의 「지금 없다」는 원리적으로 불가능하다는 뜻이 아니다. 판매 목록 처리에서 `CombinedShippingStatus ≠ SHIPPED` 가 이미 `skip_not_shipped` 로 세어진다(`index.ts:2000`). 이미 수집한 오더가 이 상태로 돌아왔는지를 볼 어휘를 실측하면 창구를 붙일 수 있다(09-22 세션 §A-3).

### A-2. ⭐ 발주 재승인 — 왜 두 벌이 되나

원장 유니크 키: `doc_type + doc_number + line_ref + event_type + warehouse + bin + sku`

⇒ `line_ref` 가 바뀌면 **키 자체가 달라진다** ⇒ 원장은 「같은 라인의 갱신」이 아니라
**「새 라인」**으로 보고 그대로 쓴다. ⚠️ 충돌이 아니니 `inv_conflicts` 도 안 만든다.

📌 **설계대로다** — 2026-08-16 유니크 키 검토의 「가시적 이중 계상 > 조용한 누락」
선택의 결과다. 흡수해서 조용히 묻히는 것보다 **두 벌이 남아 시끄럽게 드러나는 쪽**을
택했고, 오늘 ③·⑫·⑥ 세 창구가 잡았다.

⇒ ⭐ **⑩·⑩-b 가 못 보는 이유도 같다**: 키의 일부가 바뀌면 충돌로 인식되지 않는다.
**세 번째 실증이다** — `bin`(`TR-04729`·`TR-04730`) · **`line_ref`**(`PO-01361`).

### A-3. ⚠️ 예상 가능해졌다

> **입고를 되돌렸다가 다시 승인하면 반드시 이중이 난다.**

⚠️ 실무에서 입고 수량 정정은 드물지 않다 ⇒ **반복될 것이다.**
⇒ ⭐ **다음에는 경위를 묻지 말고 바로 ③·⑫ 를 보고 처방하면 된다.**

📌 그리고 ⚠️ **「undone」 자체가 흔하다** — 오늘까지 관측된 것만:
`SO-16461` 의 `Sale undone`(09/17) · `SO-16531` 의 `Shipping undone`(09/18) ·
`PO-01361` 의 `Purchase order undone` + `Stock received undone`(09/25).

---

## B. 오늘의 건 — `PO-01361` (31,104 이중)

### B-1. 경위 [실측 · Cin7 Activity log · 원장]

```
09/23 11:21:45  Stock received 승인            ← 첫 입고
09/23 15:23:04  원장 수집: 5라인 31,104
                (AS91603 17,280 · AS93280 2,592 · AS93281 2,592 ·
                 AS93283 4,320 · AS93284 4,320)

09/25 11:06:55  ⚠️ Purchase order has been undone
09/25 11:07:23  ⚠️ Stock received has been undone
09/25 11:07:41  Stock received 승인 (18초 뒤)    ← 재승인
09/25 15:08:06  원장 수집: 5라인 25,344
                (AS91603 11,520 · 나머지 넷은 동일 수량)

⇒ 원장 56,448 / Cin7 25,344
```

⭐ **다섯 라인 전부 새 GUID 를 받았다** — 수량이 바뀐 것은 `AS91603` 하나뿐인데도.
⇒ 📌 **Cin7 은 `Stock received` 를 취소하면 기존 라인을 폐기하고, 재승인 시 새
GUID 로 만든다.**

### B-2. 감지

| 창구 | 잡았나 |
|---|---|
| ③ `inv_missing_lines` | ⭐ **10행 · 5 SKU** |
| ⑫ `inv_missing_docs` | ⭐ **`missing_qty 31,104`** — 옛 벌과 정확히 일치 · ⚠️ 레포 코드와 어긋남(§A-0 · 확인 전) |
| ⑥ 원가 누락 | ⭐ **5행 · 25,344** |
| ⑩ `inv_conflicts` | ⚠️ 못 잡음(키가 달라 충돌 아님) |
| ⑩-b | ⚠️ 못 잡음(bin 은 같다) |

⇒ ⚠️ **⓪·② 가 깨끗했던 것은 놓친 게 아니라 아직 안 본 것**이다 —
두 번째 벌이 **15:08**(01:21 대조 이후)에 들어왔다.

### B-3. 처방(실행함 · Caleb) — 옛 벌을 일괄 상쇄

⚠️ **어느 벌이 맞는지는 Cin7 화면으로 확정했다** — 현재 PO 라인 Total **25,344**
(`AS91603` **11,520**) ⇒ **09-25 자 벌이 맞고 09-23 자가 옛 것이다.**

```sql
insert into inv_ledger
  (doc_type, doc_number, source, event_type, sku, warehouse, bin,
   line_ref, qty_delta, occurred_on, seq_hint, raw)
select e.doc_type, e.doc_number, 'manual', e.event_type, e.sku, e.warehouse, e.bin,
       e.line_ref || ':reversal',
       -e.qty_delta,
       e.occurred_on, e.seq_hint,
       jsonb_build_object(
         'rule', 'PO line re-keyed in Cin7: PO-01361 stock received was undone and re-authorised 2026-09-25 11:07, Cin7 issued new line GUIDs. the ledger wrote a second set without absorbing the first. reverse the stale 09-23 set',
         'reason', 'morning-check-3/12/6 · inv_missing_docs missing_qty 31,104 matches the stale set · Cin7 current total 25,344 · AS91603 17,280 -> 11,520',
         'original_line_ref', e.line_ref,
         'stale_written_at', '2026-09-23T15:23:04Z',
         'by', 'caleb', 'at', '2026-09-25'
       )
from inv_ledger e
where e.doc_number = 'PO-01361'
  and e.source = 'cin7'
  and e.created_at < '2026-09-24';
```

**검증**: `cin7` 10행 56,448 + `manual` 5행 **−31,104** = **25,344** = Cin7 총계 ·
`inv_balance_vs_cin7` **다섯 SKU 전부 `diff 0`** · ⑧ 토론토 **0칸** ✅

⚠️⚠️ **③ 과 ⑫ 를 둘 다 닫아야 한다** — 상쇄만으로는 안 닫힌다:
```sql
update inv_missing_lines set resolved_at = now(), resolution_note = '…'
where doc_number = 'PO-01361' and resolved_at is null;

update inv_missing_docs  set resolved_at = now(), resolution_note = '…'
where doc_number = 'PO-01361' and resolved_at is null;
```
⇒ **검증: 둘 다 `still_open 0`** ✅
📌 ⑫ 는 `net` 을 보지 않는 표라 **`resolved_at` 이 유일한 종결 수단**이다.
⚠️ ⑫ 쪽 update 가 실제로 몇 행을 닫았는지는 이 기록에 없다(§A-0 확인과 함께 본다).

---

## C. ⚠️ 새 캡 사유 — `detail_error`(Cin7 503)

**[실측] `sale` · 09-25 09:29**
```
detail_capped true · detail_capped_reason "detail_error" · remaining 2
detail_error: "Cin7 GET /sale?ID=…8b0aee64… -> 503: Service Unavailable"
docs_processed 10 · rows_written 3 · ok true
cursor_before 12:14 → cursor_after 13:24   (전진함)
```

⇒ ⭐ **지금까지 관측된 캡 사유는 `max_detail`(건수)과 `time`(120초)뿐이었다.
`detail_error` 는 「상세 조회 중 실패」로 성격이 다르다** — 앞의 둘은 「캡」, `detail_error`·`rate_limited` 는 「실패」다. 넷 다 코드에는 이미 있었다(§A-0 2).

⇒ ⭐ **설계대로 동작했다** — 실패 지점에서 멈추고, 쓴 것은 3행뿐이며, 남은 2건은
다음 회차가 이어받는다. `ok=true` 이고 커서는 전진했다.

📌 **Cin7 쪽 불안정이 이어지고 있다** — `stockTransferList` **502 다섯 번**
(09-17·09-18·09-21 두 번 등) + 오늘 `sale` 상세 **503**.
⇒ ⚠️ **[추론]**: `transfer` 목록이 5,000건대로 커진 것이 영향일 수 있으나 확인 안 됐다.

⇒ 스킬 ⑦ 에 캡 사유 넷(캡 둘 · 실패 둘)을 적었다.

---

## D. ⚠️⚠️ `TR-04496` — 2주째 (실무 처리 필요)

```
cursor_held_by: hold_status:ORDERED · TR-04496
transfer 커서 TR-04495 — 2026-09-12 부터 2주
list_total 5,048(09-18) → 5,075(09-22) → 5,231(09-25)   ⚠️ 계속 커진다
```

⇒ 09-25 09:32 에 캡 한 번(`remaining 1` · 소진됨).
⇒ ⭐ **출고하거나 취소하면 풀린다.** ⚠️ 두면 09-18 `TR-04730`(bin 해석 실패 ·
24행 중복)이 재발한다.

📌 **`ST-01300`(DRAFT 13일) 전례와 같다** — 그때도 홀드만으로는 무해했으나
캡과 겹쳐 터졌다.

---

## E. 사흘치 점검 요약 (09-23 ~ 09-25)

| | |
|---|---|
| ② | ⭐ **09-23·24·25 사흘 연속 `unknown 0`** · 09-22 `SO-16464` 상쇄가 다음 날 반영 |
| ① ④ | 사흘 전부 01:21 촬영 · `ok=true` · `insert_rows` 일치 |
| ⑧ | ⭐ 토론토 **0칸** · 에드먼튼 2칸(`PRO00124`) |
| ⑥ | `PO-01361` 외 0행 |
| ⑨ ⑩ | 0행 |
| ⑩-b | 기준선 2건(`total_rows 2`) |
| ⑪ | 0행 · `assembly` `in_ledger 3` · `adjustment` `seen` 32→33 |
| ⚠️ ⑪ 경고 | `transfer` 「4 below-cursor doc(s)」 **보름째**(09-09 부터) |

📌 `compared_pairs` 14,347 → **14,422** · `explained_count` 795 → **568**(09-24 부터).
⚠️ 후자의 이유는 확인하지 않았다(**추론 없음** · 판정에 영향 없음).

---

## F. ⚠️ 내가 틀린 것 (점검 세션)

- ⭐ **상쇄 직후 `inv_balance_vs_cin7` 이 `−5,760` 으로 보여 「과잉 상쇄」로 판단하고 정정 SQL 까지 만들었다** → **틀렸다.** 그것은 상쇄가 반영되기 전 시점의 값이었고, 다시 조회하니 **`diff 0`** 이었다.
  ⇒ ⚠️ **상쇄 직후 조회는 시점이 엇갈릴 수 있다. 「또 틀렸다」로 판단하기 전에 다시 확인할 것** — 넣었으면 진짜로 꼬였다.
- `transfer` 축이 `inv_sync_state` 에서 사라지고 `parts` 라는 새 축이 생긴 것으로 읽었다 → **결과가 섞인 것**이었다(`count(*)` 로 여덟 축 확인).
- `last_run 21:32` 을 **미래 시각**으로 읽고 시간대 문제를 의심했다 → ⚠️ **그때가 밤 9시였다.** Caleb 이 정정.
- ③ 을 「0행」으로 받고 넘어갈 뻔했다 → 실제로는 `PO-01361` 1행.
- ⚠️ **오늘 조회 결과가 다섯 번 이상 엇갈렸다**(③·④·⑤·⑦·⑧) ⇒ ⭐ **판정이 갈리는 값은 `count(*)`·`id` 로 재확인하는 습관이 필요하다.**
  📌 §A-0 의 ⑫ 어긋남도 이 엇갈림 중 하나일 수 있다([추론] · 확인 전).

---

## G. ⬜ 남는 것

- ⬜ **`TR-04496` 실무 처리** — 2주째 · Cin7 에서 출고 또는 취소(§D).
- ⬜ **`PO-01361` 원가** — 다음 원가 회차(00:33)에 ⑥ 5행이 닫히는지.
- ⬜ **⑫ 어긋남 확인** — 운영 `inv_missing_docs` 의 `doc_type` 분포(§A-0 1).
- ⬜ **Ship-undone 감시** — 어휘 실측 선행 · 신호 `index.ts:2000` `skip_not_shipped`(§A-1).
- ⬜ **`cursor_stalled_alert` 발화 조건** — `ST-01300` 13일 · `TR-04496` 2주 동안 한 번도 안 울렸다(코드 미확인).
- ⬜ **⑩-b 사각지대 둘** — 빈 bin(`TR-04730`) · `line_ref` 재키잉(`PO-01361`).
- ⬜ **`transfer` 경고 4건** — 보름째(09-09 부터).
