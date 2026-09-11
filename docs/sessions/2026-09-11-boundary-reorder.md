# 2026-09-11 아침 점검 — `SO-14986` 경계 오더 재유입(이레 만의 어긋남 1건)과 관측 넷

관련: `asung-inv-ledger` §아침 점검 ⓪·②·⑤·⑦·⑨·⑩·⑪ · `docs/sessions/2026-09-10-morning-check.md`(어제 아침) · `2026-09-09-reversal-conventions.md`(상쇄 관례).
⚠️ 표기: **[실측]** = 운영 DB·Cin7 Activity log 에서 읽은 값 · **[추론]** = 판단.

---

## 1. 점검 요약 — 14항목 · 어긋남 1건 발견·규명·상쇄 완료
⓪ `new_today 1` · `abs_gap 6→18` → ② `unknown_count 1` → 실물 `AS01287AST` → 원인 규명 → ⑨ 관례 상쇄 → `inv_balance` 검증. 나머지 항목은 §3 관측 넷 외 변동 없음.
⚠️ ⑧ 대조는 01:21 스냅샷 기준이라 오늘 화면에는 그대로 남는다 — **내일 아침 ⑧ 에서 사라지는 것이 최종 확인**이다.

## 2. `SO-14986` · `AS01287AST` −12 전문

| | |
|---|---|
| 발견 | ⓪ `new_today 1` · `abs_gap 6→18` → ② `unknown_count 1` |
| 실물 | `AS01287AST` · `Asung Trading Inc.` · 원장 **174** / Cin7 **186** · `diff −12` |
| 원인 | `header.ship_date = 2026-08-21` 인데 **실물 출고는 08/20 15:55 EDT**(기초 촬영 08/20 19:42 **전**) ⇒ 기초에 이미 반영된 출고를 원장이 또 차감 |
| ⭐ 트리거 | **QuickBooks 결제** — Cin7 Activity log `09/10 19:04:17 Payment has been added, 17.53, CHQ #13611` · `Unpaid → Paid`. 그 **5분 뒤 19:09:32** 원장이 재수집 |
| 처방 | ⑨ 관례대로 상쇄 — `manual` · `sale_out`(원래 타입 유지) · `line_ref` + `:reversal` · `qty_delta +12` · `bin`·`occurred_on`·`seq_hint` 원본과 동일 |
| 검증 | `inv_balance` `AS01287AST`/`B020402` = `baseline 192` + `delta −6` = **186** ⇒ **Cin7 186 과 일치** |

**Activity log 타임라인(핵심)**: `08/19 14:31` 생성 → `08/20 07:24` 피킹 승인 → `08/20 07:25` 패킹 승인 → **`08/20 15:55:46` Shipping 승인** → `08/20 15:56:23` Ordered→Closed → **`09/10 19:04:17` QuickBooks 결제**.

**`raw.header` 원문**: `"header": { "ship_date": "2026-08-21", "status": "CLOSED", … }` — `occurred_on` 은 이 `ship_date` 에서 온다(승인 시각이 아니다).

**상쇄 SQL(2026-09-11 07:09 실행문 그대로)**:
```sql
insert into inv_ledger
  (doc_type, doc_number, source, event_type, sku, warehouse, bin,
   line_ref, qty_delta, occurred_on, seq_hint, raw)
values
  ('sale', 'SO-14986', 'manual', 'sale_out', 'AS01287AST',
   'Asung Trading Inc.', 'B020402',
   '0f707e8f-d1c9-4a9e-bba1-8a0059763d82:f4ea59dd-a033-4f76-aa4f-9588453d7e70:reversal',
   12, '2026-08-21', 2,
   jsonb_build_object(
     'rule', 'baseline boundary reversal: ship_date 2026-08-21 but shipped 2026-08-20 15:55 EDT (before baseline snapshot 2026-08-20 19:42) - already in baseline',
     'reason', 'morning-check-9 · re-collected 2026-09-10 19:09 after QuickBooks payment reopened the doc',
     'original_line_ref', '0f707e8f-d1c9-4a9e-bba1-8a0059763d82:f4ea59dd-a033-4f76-aa4f-9588453d7e70',
     'by', 'caleb', 'at', '2026-09-11'
   ));
```
검증: `inv_balance` `AS01287AST`/`B020402` = `baseline 192` + `delta −6` = **186** = Cin7 186.

## 3. 관측 넷 (스킬에 반영 · 여기는 근거)

### 3-1. ⑨ — 「유한한 집합이라 다 나오면 끝난다」는 속도가 결제에 묶여 있다
기존 ⑨ 건들은 8/24·8/31 수집이었는데 `SO-14986` 은 **20일 뒤(09-10)**. QuickBooks 결제 연동이 옛 문서의 `LastModifiedOn` 을 갱신해 재수집을 유발한다(결제 19:04:17 → 재수집 19:09:32 · 5분). ⇒ 8/20 승인분이 전부 결제될 때까지 이어진다(Net 30 이면 9월 하순). **재기준선이 근본 해법.**

### 3-2. ⑨ — `occurred_on` = `header.ship_date` · 8/21 하루만 보는 것으로 현재는 충분
위험 조건: **`ship_date` 8/21 인데 실물 출고는 8/20 기초 촬영(19:42 EDT) 전인 문서.** 8/19 이전은 `since=2026-08-20` 이 거른다.

| `occurred_on` | 문서 | `manual_rows` | `latest_collected` |
|---|---|---|---|
| 08-24 | 60 | **0** | 08-25 17:04 |
| 08-25 | 61 | **0** | **09-04 13:04** |
| 08-26 | 66 | **0** | 09-01 14:49 |

⇒ 재유입 자체는 무해하다(기초에 없는 사건은 원장이 차감하는 것이 맞다). 문제는 「기초에 이미 반영된 사건이 다시 들어올 때」뿐이고 그 날짜는 8/21. 8/22·8/23 은 주말이라 `sale` 0건.
⚠️ `ship_date` 가 8/22 이상으로 밀린 8/20 승인분은 논리적으로 가능하다([추론] · Cin7 전수 조회는 하지 않았다) — 지금은 없다. **그래도 ⑧·② 가 잡는다** — `SO-14986` 은 ⑨ 전에 ② `unknown_count 1` 에서 이미 걸렸다(창구 이중).
[실측] 8/21 자 **72문서** 중 상쇄 **9건** · 나머지 **63문서**는 `first_collected` 8/21 09:19~18:09(당일 수집 · 기초 이후 진짜 출고). 위험한 것은 「당일에 안 들어오고 나중에 들어온 것」. 상쇄 9건의 수집 시각: 8/21(1건 `SO-15097` · ⚠️ 당일인데 상쇄 필요 — 다른 계열 · SKU `FINAL-SALE` · bin 비어 있음) · 8/30(4건) · 8/31(3건) · 09-10(1건 `SO-14986`). 8/30~31 의 7건은 결제가 아니라 Cin7 대량 갱신으로 보인다([추론]).

### 3-3. ⑩ — 재유입이 있어도 `inv_conflicts` 가 안 생길 수 있다
`inv_conflicts` 는 「기존 원장 행과 다른 값」일 때만. 새 행 추가형(`SO-14986` · 기존 행 없음)은 ⑨ 가 잡고 ⑩ 은 0행. [실측] 09-10 `backdated_rows 1` 인데 ⑩ 0행 — 축이 다르다. 두 창구를 함께 본다.

### 3-4. ⑤·⓪ — `cost_transfer` 축은 cron 미등록 · `lag_source` 를 가린다
`inv_sync_state` 에 `cost_transfer` 축 생김(`inv-doc-cost` · 09-10 배포) · `last_run`=`last_ok`=09-10 17:08 · `cron.job` jobid 1~18 전수(17 결번)에 없음 ⇒ 자동화 전(결함 아님). ⚠️ `inv_diff_summary()` 가 이 축을 신선도에 넣어 ⓪ `ledger_lag_source` 가 매일 `cost_transfer`(15시간+) — 다른 축 지연을 가린다. ⬜ cron 등록 또는 계산 제외 미정(📌 백로그 10번: ③ 이 끝나 cron 등록이 다음 순서).

### 3-5. ⑦·⑪ — 캡은 정상 소진 형태 · `transfer` 경고 4건은 커서와 무관 · `assembly` 기준선 유지
- ⑦ 0행 아님이었으나 정상: `cost_transfer` 13회차 `max_detail` `remaining` 495→27(09-10 16:50~17:07 수동 백필) · `transfer` 5회차(첫 `time`, 나머지 `max_detail`) `hold_capped` 27→10 → 소멸. **줄어드는 방향 = 정상 · 고정 = 교착.** `transfer` 커서 `TR-04329` → `TR-04495`.
- ⑪ `transfer` 경고 「4 below-cursor doc(s) had no usable list date」 — 커서 대폭 전진 뒤에도 그대로 ⇒ 별개 사각지대. ⬜ 4건 미특정.
- ⑪ `assembly` `seen 88 · in_ledger 3 · open 0` — 어제 확정한 셋(`FG-00131`·`FG-00133`·`FG-00134`) 그대로. **문서명 기준 판정의 첫 적용 · 역추적 불필요.** `adjustment` `seen 30 → 31 · in_ledger 0`.

## 4. ⚠️ 내가 틀린 것
- 「8/20 저녁 EDT 승인분이 UTC 로 8/21 이 되어 걸린다」고 시간대 변환으로 설명했다 → **틀렸다.** `occurred_on` 은 `header.ship_date` 이고 Cin7 이 그 값을 8/21 로 들고 있었다. **`raw` 를 먼저 읽었으면 두 단계 줄었다.**
- `transfer` 캡(`hold_capped`)을 보고 「`AS01287AST` 가 홀드된 트랜스퍼에 걸려 있을 가능성」을 세웠다 → **아니었다.** 원장 실물을 먼저 보는 것이 순서였다.
- ⑪ 조회에서 `order by source_key` 로 `adjustment` 가 목록을 다 먹었다(`distinct on` 으로 고쳤다).

## 5. ⬜ 남는 것 — 어제 목록(`2026-09-10-morning-check.md` §8) + 둘
- Simple `landed` 표본 대기 · 테스트 재복사는 적재 함수 착수 시점(📌 09-10 밤 재복사 실행됨 — 스킬 ⑭) · `x-wms-cron-key` 교체는 시스템 완성 후 · ~~트랜스퍼 운임 미수집~~ → 09-10 5건 적재 완료(백로그 10번)
- ⑨ 가 `occurred_on='2026-08-21'` 하루만 본다 — 현재는 충분(§3-2) · `ship_date` 가 밀린 건은 못 잡음([추론] · ⑧·② 가 이중 창구)
- `cost_transfer` cron 등록 또는 `inv_diff_summary()` 신선도 계산에서 제외
