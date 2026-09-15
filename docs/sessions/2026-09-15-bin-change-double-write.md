# 2026-09-15 아침 점검 — bin 변경 이중 기입(어긋남 2건 규명·상쇄) · ⭐ 감지 창구 ⑩-b 신설

관련: `asung-inv-ledger` §아침 점검 ⓪·②·⑧·⑩·**⑩-b**(오늘 신설)·⑪·⑫ · `docs/design/ledger-design.md` §「변경 감지가 못 보는 축 — bin 변경 이중 기입」 ·
`docs/sessions/2026-09-11-boundary-reorder.md`(같은 성격의 앞선 건) · `2026-09-09-reversal-conventions.md`(상쇄 관례).
⚠️ 표기: **[실측]** = 운영 DB · Cin7 화면(Movements · Product Availability)에서 읽은 값 · **[추론]** = 판단.

---

## 1. 경위 — 어긋남 2건 · 둘 다 규명·상쇄 완료

```
⓪ new_today 2 · total 4 · abs_gap 6 → 30
② unknown_count 2  →  ABE23012 · ABE52708 특정
⑧ 4칸 (새 2 + PRO00124 2)
감지 창구 순회  ③ 0 · ⑩ 19행(ABE23012 · ST-01306) · ⑪ 0 · ⑫ 0   ⇒ ABE52708 은 넷 다 못 잡음
원장 실물 추적  ABE52708 · TR-04729 — 같은 line_ref 에 bin 둘(E020202 08:47 · E020302 11:12)
실무자 확인     09/11 오전 12개를 E020202 에서 뽑아 빼둠 → 오후 TR-04717 bin transfer 117개 → 09/14 authorize
원인 확정       뽑은 뒤 자리 변경 → Cin7 이 authorize 시점 bin 으로 기록 → 원장에 두 벌
```
⭐ **가장 큰 성과는 감지 창구 하나를 새로 만든 것**이다(§4). 그 유형은 기존 넷(③·⑩·⑪·⑫)이 전부 못 보던 것이고 8월 말(`SKL01861`)에도 같은 일이 있었다.

## 2. `ABE23012` +12 — Cin7 수량 수정 (⑩ 이 잡았다)

```
ST-01306 · adjust_existing · EDM · EC010604 · existing −1 → incoming −13 · delta −12
```
Cin7 에서 조정 라인이 `−1 → −13` 으로 수정됐는데 원장은 **append-only 라 옛 값 보유**. ⭐ **⑩ 이 정확히 잡았다** — `inv_conflicts` id 83~101.
📌 **19행은 사건 19개가 아니다** — 같은 라인이 시간당 1회 **재검출**된 것(09-14 13:11 ~ 09-15 07:11 · `adjustment` 주기와 일치). 「행 수 ≠ 사건 수」.

**처방(실행함)** — 차액만 보정 · `:qtyfix` · ⚠️ **부호 반전이 아니다** · `occurred_on` 은 사건 날짜 **2026-09-08**(⑩ 의 `detected_at` 09-14 가 아니다):
```sql
insert into inv_ledger
  (doc_type, doc_number, source, event_type, sku, warehouse, bin,
   line_ref, qty_delta, occurred_on, seq_hint, raw)
values
  ('adjustment', 'ST-01306', 'manual', 'adjust_existing', 'ABE23012',
   'Asung - Edmonton', 'EC010604',
   '71def0b7-d65b-4a47-974f-efa87305081a:qtyfix',
   -12, '2026-09-08', 2,
   jsonb_build_object(
     'rule', 'qty change fix: Cin7 line edited -1 -> -13 after collection; ledger holds old value (append-only). add the delta only',
     'reason', 'morning-check-10 · inv_conflicts id 83-101 · existing -1 / incoming -13 / delta -12',
     'original_line_ref', '71def0b7-d65b-4a47-974f-efa87305081a',
     'by', 'caleb', 'at', '2026-09-15'
   ));
```

## 3. `ABE52708` −12 — 뽑은 뒤 자리 변경 (⑩-b 가 필요했던 건)

**경위 [실무자 확인]**
1. **09/11 오전** — 실물 12개를 **`E020202`** 에서 뽑아 트랜스퍼용으로 빼둠
2. **09/11 오후** — `TR-04717` bin transfer `E020202` → `E020302` **117개**(⚠️ 이미 빼둔 12개는 제외되어 117만 옮겨짐)
3. **09/14** — `TR-04729` transfer out **authorize** ⇒ Cin7 이 **그 시점 자리 `E020302`** 로 기록

**원장 [실측]** — 두 벌:
```
08:47  transfer_out · E020202 · −12      ⚠️ 옛 벌
08:47  transfer_in  · IN_TRANSIT · +12   ✅ 한 번만
11:12  transfer_out · E020302 · −12      ✅ Cin7 과 일치
                                 문서 순액 −12
```
⚠️ `line_ref` 가 **두 행 모두 같다**(`bc9ae34d-…`) ⇒ **같은 라인의 bin 이 바뀐 것**이라는 확증. 라인이 둘인 것이 아니다.
📌 Cin7 Movements 에는 `E020302` **한 줄뿐**(`IN TRANSIT` · −12).

**처방(실행함)** — 옛 벌을 부호 반전 · `:reversal` · 원래 타입 유지:
```sql
insert into inv_ledger
  (doc_type, doc_number, source, event_type, sku, warehouse, bin,
   line_ref, qty_delta, occurred_on, seq_hint, raw)
values
  ('transfer', 'TR-04729', 'manual', 'transfer_out', 'ABE52708',
   'Asung Trading Inc.', 'E020202',
   'bc9ae34d-2304-4c09-a778-46226cce986c:reversal',
   12, '2026-09-14', 2,
   jsonb_build_object(
     'rule', 'departure bin double-write: TR-04729 out leg written twice (E020202 08:47, E020302 11:12). Cin7 has only E020302. reverse the stale one',
     'reason', 'morning-check-8 · E020202 ledger -8 vs cin7 4 · transfer_in was written once only',
     'original_line_ref', 'bc9ae34d-2304-4c09-a778-46226cce986c',
     'by', 'caleb', 'at', '2026-09-15'
   ));
```

**검증(실행함)** — `inv_balance_vs_cin7` 전 칸 `diff 0` [실측]:
```
ABE23012 · EC010604    0 /   0
ABE52708 · E020202     4 /   4
ABE52708 · E020302   201 / 201
```
⭐ **Cin7 Product Availability 화면과도 일치** — ON HAND `E020202` 4 · `E020302` 201 · `EC010503` 10 · EDM IN TRANSIT 12.

**⭐ 이것은 결함이 아니라 「구조가 만드는 경우의 수」다.** 아무도 틀리지 않았다 — 실무자(있는 자리에서 뽑았고 자리 변경도 정상 업무) · Cin7(authorize
시점의 bin 으로 기록 · 자기 규칙대로) · 원장(Cin7 이 준 것을 그대로 받음 · 두 벌이 된 것은 유니크 키에 `bin` 이 있기 때문이고 설계대로) · ⑧ 대조(어긋남을
정확히 잡았다). ⇒ 09-11 `SO-14986`(기초 경계 재유입)과 **같은 성격**. ⇒ **예측할 수 없으니 감지로 대응한다** — 그래서 ⑩-b 를 만들었다.

## 4. ⭐⭐ ⑩-b 신설 — bin 변경 이중 기입 (판별식 도출 과정)

### 4-1. 왜 넷이 못 보나
유니크 키 `(doc_type, doc_number, line_ref, event_type, warehouse, bin, sku)` 에 `bin` 이 있어 **키 자체가 달라져** 충돌로 인식되지 않는다(`inv_conflicts` 는
「같은 키에 다른 값」만 신고). ⑩ 은 **같은 키에 다른 값**, ⑩-b 는 **키 자체가 달라진 값** — 한 문장으로 가르면 다른 키 컬럼이 바뀔 때도 같은 구멍을 예상할 수 있다.
📌 2026-08-16 유니크 키 검토(「가시적 이중 계상 > 조용한 누락」 · 마이그레이션 주석)의 **나머지 반쪽** — 이중 계상이 ⑧ 에 시끄럽게 잡히는 것까지는 설계대로였고,
없던 것은 원인을 읽는 창구다. ⇒ ⑩-b 는 결함 수정이 아니라 그때 선택을 완성하는 것.

### 4-2. 첫 시도 — ⚠️ 빈 bin 을 제외하지 않아 전 문서가 걸렸다
정상 4-leg 트랜스퍼는 IN_TRANSIT leg 의 bin 이 비어 있어 `(빈) | 실제bin` 조합으로 **전 문서가 다 걸렸다**. ⭐ `net` 이 정확히 **두 배**로 나오는 것을 보고
바로 알아챘다 — 그것이 표시다. ⇒ `bin is not null and bin <> ''` 를 넣었다.

### 4-3. 판별식 — 「시각이 다른가」
> 같은 `(doc_type, doc_number, sku, line_ref, event_type, warehouse)` 에 실제 bin 이 둘 이상이고 `min(created_at) <> max(created_at)` 이면 이상.

⚠️ **같은 시각이면 정상** — 한 회차에 두 bin 에서 나눠 픽. [실측 전수] 판매 7건이 이 형태였고 ⑧ 이 깨끗했다(예 `SO-16010`/`CON47506` · `E050302` 1 + `E050402` 1).
SQL 전문은 스킬 ⑩-b(`manual_net` 서브쿼리 — 본문 CTE 는 `source='cin7'`, `manual_net` 은 필터 없이 · 두 축을 섞지 않는다 — 09-09 함정 1).

### 4-4. 기준선 — 문서명 둘 · 「0행」이 아니라 「이 둘이면 정상」
| 문서 | SKU | bin | 경위 | `manual_net` |
|---|---|---|---|---|
| `TR-04729` | `ABE52708` | `E020202` → `E020302` | 09-14 뽑은 뒤 자리 변경 | **12** |
| `TR-04174` | `SKL01861` | `D110301` → `D110302` | 08-31 배포 · 09-01 정정 | **12** |

⚠️ 숫자(2행)로 외우지 말 것 — ⑦-b 의 「3 이면 정상」 전례. 새 문서가 뜨거나 `manual_net` 이 비면 `inv_balance_vs_cin7` → 틀린 bin 쪽 `:reversal`.

## 5. ⬜ IMS 설계 요구사항(미구현) — 반품 리스탁 bin 은 「현재 자리」로 (Caleb 확정)
정본은 `ledger-design.md` §「변경 감지가 못 보는 축」 아래 소절(⬜ 표지). 요지:
반품 리스탁은 판매 시점 bin 이 아니라 **그 SKU 가 현재 있는 bin** 으로 — 옮겨졌으면 옮겨진 자리로 따라간다. [실측] 09-14 `SO-16076` Restock **+4** 가 이미 비워진
`E020202` 로 복귀해 재고가 `E020202` 4 / `E020302` 201 로 갈라졌다 · 피커가 헷갈린다 · Cin7 에서는 못 바꾼다.
IMS 이후: 폴링 이중은 사라진다(전환 기간엔 그대로) · 키에 `bin` 이 있는 구조는 남아 **⑩-b 는 유효 · 트리거만 바뀐다** · 정정을 상쇄로 남길지 대체할지는 설계 판단.

## 6. 09-15 점검 나머지

| | 결과 |
|---|---|
| ① | 01:21 · 13,682행(−25) — **나흘 만에 움직임**(월요일 물량) |
| ④ | `ok=true` · `insert_rows` 13,682(① 일치) · `list_total` +372 |
| ⑤ | 8축 전부 `last_run`=`last_ok` · **시각도 전부 오늘** · `cost_transfer` 사흘 연속 |
| ⑥ | 0행 (이레째) |
| ⑦ | `sale` **1회차** 캡(`max_detail` · `remaining 29`) — 다음 회차가 이어받아 **정상 소진** |
| ⑨ | 0행 |
| ⑪⑫ | 0행 · `assembly` `in_ledger 3` 기준선 · `transfer` 경고 4건 **엿새째** |

📌 ④ 는 오늘 **두 축이 같은 방향**으로 움직였다(`insert_rows` −25 · `list_total` +372). 09-12~14 는 `insert_rows` 평평 · `list_total` 만 상승.
⇒ ⭐ 어제 규명(`2026-09-13-list-total-axis.md` §1) 덕분에 추세를 의심할 필요가 없었다.

## 7. ⚠️ 내가 틀린 것
- ⭐ **「Cin7 이 실물과 12 어긋났다」를 두 번 단정했다.** 두 번 다 근거 없이 앞서간 추론이었고 **실물 4개는 처음부터 맞았다.** 09-14 `SO-16076` Restock +4 한 줄이
  Movements 화면에 있었는데 못 봤다 ⇒ **화면을 끝까지 읽지 않았다.**
- `ABE52708` 의 원인을 처음에 **`TR-04330`** 으로 지목했다 → 무관했다(`TR-04330` 은 에드먼튼 도착 leg). **Cin7 Movements 를 보기 전에 원장만으로 추론한 결과다.**
- 첫 ⑩-b 검사가 **빈 bin 을 제외하지 않아** 정상 4-leg 을 전부 잡았다. ⭐ 다만 `net` 이 두 배로 나오는 것을 보고 바로 알아챘다.
- ⑧ 뷰가 「01:21 스냅샷 기준이라 상쇄가 당일에 안 보인다」고 했으나 **틀렸다** — `inv_snapshot`(Cin7 쪽)만 그 시점이고 **원장 쪽은 실시간**이라 바로 반영된다.

## 8. ⬜ 남는 것
- `transfer` 경고 4건 — 엿새째 미특정
- `null_bin_nonzero` 6건이 ⑧ 에서 어떻게 취급되는지
- WMS 픽 리스트의 **다중 bin 표시 여부**(§5 · 별건 · WMS 스킬 무접촉)
