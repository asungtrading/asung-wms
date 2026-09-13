# 2026-09-13 아침 점검(09-12·09-13 이틀치) — ⭐ `list_total` 축 규명 · `inv-doc-cost` 25시간 정지 · ⑨ 상쇄 검증

관련: `asung-inv-ledger` §아침 점검 ④(정정 블록)·⑤(진단 경로)·⑨(확인 시점) · `asung-ops` §2-b·§5-b · `docs/sessions/2026-09-11-boundary-reorder.md`(`SO-14986` 상쇄 원문).
⚠️ 표기: **[실측]** = 운영 DB·대시보드에서 읽은 값 · **[추론]** = 판단. 이틀치 점검은 새 결함이 없어 짧고, **본문은 §1 `list_total` 규명**이다.

---

## 1. ⭐⭐ `list_total` 이 무엇을 세는가 — `summary` 원문으로 확정

### 1-1. [실측 09-13 회차 `inv_snapshot_runs.summary`]
```
list_total          22,022   = received_rows (Cin7 ProductAvailability 가 준 전체 행)
dropped_zero_nobin   8,315   ← 버려진 것 (bin 이 없으면서 수량 0)
kept_source_rows    13,707   = insert_rows = db_rows_after
```
⭐ **22,022 − 8,315 = 13,707** — 정확히 맞는다.

같은 `summary` 의 다른 필드: `pages_scanned 23` · `inserted_batches 28` · `merged_rows 0` · `skipped_no_sku 0` · `negative_rows []` · `rate_limited false` · `unexpected_warehouses []` · `existing_rows_before 0` · `truncated false` ·
창고별 `warehouses{}`: 에드먼튼 rows 6,266 / bins 506 / value_sum 259,482.40 / onhand_sum 89,262 · 토론토 rows 7,441 / bins 1,468 / value_sum 3,038,581.20 / onhand_sum 1,845,822.

### 1-2. ⭐ 실증 — 주말에도 `list_total` 은 변한다
[실측 09-12 → 09-13] `insert_rows` **13,707 이틀 연속 동일**(재고 무변 · 주말) · `list_total` 21,920 → 22,022 = **+102**.
⇒ 늘어난 102 는 전부 「bin 없고 수량 0」 행이고 `dropped_zero_nobin` 에서 흡수됐다.
⇒ **`list_total` 은 Cin7 마스터의 모양**(제품 추가·비활성화 · bin 배정 변화 · 수량 0 전환)을 반영하고 **재고 변동과 직접 연동되지 않는다.** **`insert_rows`(= `kept_source_rows`)가 실제 저장된 재고 행**이다.
⇒ ⭐ **재고 급감을 보려면 `insert_rows` 를 본다.** `list_total` 이 크게 움직여도 `insert_rows` 가 평평하면 재고 문제가 아니다.

### 1-3. 스킬 ④ 원 문장 「`list_total` 이 유일한 급감 축」과의 정합
원 문장은 취소선으로 지우지 않고 아래에 정정 블록을 덧붙였다. **출처를 찾았다** — 같은 스킬 「스냅샷이 조용히 불완전할 수 있다」 절의 [실측 2026-08-28 · 첫 뺄셈] 표 와 `ledger-design.md` 「판정 축은 행 수가 아니다」.
거기서 「급감」은 **Cin7 이 애초에 적게 준 회차(불완전 스냅샷 · 8/24 밤 `AS93125` 토론토 2,662개 누락 · `list_total` 22,079→21,877)** 를 잡는 축이라는 뜻이고, 그 표에 이미 「`list_total` 과 `insert_rows` 는 반대로 움직인다 — 다른 물건」이라 적혀 있다.
⇒ 두 서술은 **다른 질문**에 답한다: **스냅샷이 온전한가 → `list_total`** · **재고가 줄었나 → `insert_rows`**. 서로 틀린 것이 아니라 ④ 의 제목 「급감이 있었나」가 두 뜻을 가리지 않았던 것이다.
⬜ 원 문장을 「불완전 스냅샷 축」으로 고쳐 쓸지는 Caleb 판단.

### 1-4. ⭐ 임계값 판정 기준 — 「연속 횟수」가 아니라 「누적 폭과 반등」
| 날짜 | `list_total` | 변화 | `insert_rows` | `duration_ms` |
|---|---|---|---|---|
| 09-08 | 22,662 | +63 | 13,759 | 42,154 |
| 09-09 | 23,197 | **+535** | 13,750 | 44,250 |
| 09-10 | 22,582 | **−615** | 13,670 | 43,835 |
| 09-11 | 22,237 | −345 | 13,712 | 42,461 |
| 09-12 | 21,920 | −317 | 13,707 | 38,470 |
| 09-13 | 22,022 | **+102** | 13,707 | 39,241 |

⚠️ 09-12 시점에 「나흘 연속 하락 = 추세 확정」으로 판정했으나 09-13 에 반등해 틀렸다. 누적 −1,277 까지 갔다가 돌아왔다.
⇒ **연속 횟수로 판정하지 말 것.** 관측폭은 이제 **−615 ~ +535**. 📌 `duration_ms` 는 `list_total` 과 같은 방향으로 움직인다(조회량 연동).

### 1-5. 📌 부수 — `null_bin_nonzero` 6건
[실측 09-13] bin 이 없는데 수량이 있는 행: `AS91459`(EDM 10) · `AS91457`(EDM 20) · `ABE16004`(EDM 3) · `UNF18155`(EDM 1) · `EBI03960`(TOR 8) · `AIA03588`(TOR 6).
`dropped_zero_nobin` 과 달리 **버려지지 않고 기록만 남는다**(수량이 0 이 아니므로).
⬜ ⚠️ 이 행들이 ⑧ bin 대조에서 어떻게 취급되는지 확인하지 않았다 — bin 미배정 재고이므로 `bin=''` 으로 들어갈 텐데 ⑧ 이 Cin7 쪽과 어떻게 맞추는지 미확인. **별건.**

---

## 2. ⚠️⚠️ `inv-doc-cost` 가 조용히 죽고 있었다 — 발견(09-12 ⑤) → 오진 → 원인 → 해결(09-13 확인)

### 2-1. [실측 09-12 아침] 네 창구
| 축 | 관측 | 판정 |
|---|---|---|
| `cron.job` | jobid **19** · `45 4 * * *` · `active=true` | ✅ 등록 정상 |
| `cron.job_run_details` | 09-12 **00:45** · **`succeeded`** | ⚠️ **거짓 안심** — `net.http_get` 은 비동기라 요청을 큐에 넣은 것만으로 성공 |
| `inv_collect_runs` | ⚠️ **00:45 회차 없음**(마지막 09-11 08:15) | ⚠️ EF 가 안 돌았으니 아무것도 안 썼다 — 「없음」은 경고를 만들지 않는다 |
| `inv_sync_state` | ⚠️ **25시간 정지** · `last_run`=`last_ok` | ⚠️ 실패로도 안 보임 |
| `net._http_response` | `Timeout of 5000 ms reached` | ⚠️ 아침엔 이것을 원인으로 봤다 — **아래 2-2** |

📌 **알아챈 방법**: ⑤ 에서 `inv_sync_state` 시각이 **하루 전**이라는 것 하나. ⇒ ⭐ ⑤ 는 `last_run`=`last_ok` 만 보면 이 실패를 못 잡는다 — **시각이 주기를 넘겼는지도 함께 봐야 한다**(스킬 ⑤ 에 넣었다).

### 2-2. ⚠️ 아침 판정 「원인 = 5초 타임아웃」은 오진이었다 — 같은 날 낮에 401 로 정정
아침에는 「`inv-doc-cost` 는 `list_total 4,680`(5페이지) 순회 + 캡(40건 또는 120초)까지 가는 작업이라 5초 안에 끝날 수 없다」로 타임아웃을 원인으로 봤다.
⚠️ **틀렸다.** 같은 날 낮의 확인(`docs/design` 정본은 `asung-ops` §2-b·§5-b · `supabase/config.toml` `[functions.inv-doc-cost]` 주석):
- [실측] 13:11 타임아웃 ↔ `inv-collect-adjustment` `last_run_at` 13:11:44 — 돌았다 · 13:22 타임아웃 ↔ `inv-collect-transfer` 13:22:23 — 돌았다. ⇒ **타임아웃은 pg_net 이 5초 기다리다 포기한 기록일 뿐, EF 는 그 뒤로도 돌아 제 일을 끝낸다.** 원장 수집 축은 매 회차 타임아웃이 찍히지만 전부 정상이다.
- ⭐ **진짜 원인** — `config.toml` 에 `[functions.inv-doc-cost]` 블록이 없어 배포 시 기본값(JWT 검증 켜짐)이 적용됐고, cron 의 `x-wms-cron-key` 호출이 **게이트웨이에서 401**. 함수 코드는 실행조차 안 됐다. 401 은 EF Logs 에 안 남고 **Invocations 탭**에만 찍혔다(`12 Sep 26 00:45:05 · 401 · GET`).
- 처방: `config.toml` 블록 신설(커밋 `3e3c105`) + 대시보드 토글. [실측 09-12 13:36 손 실행] `candidates 0` · `rows_written 0` — **25시간 정지에도 밀린 문서 0건.**

### 2-3. 진단 경로 — 「cron 은 성공인데 커서가 안 움직인다」
```sql
select id, status_code, error_msg,
       created at time zone 'America/Toronto' as created,
       left(content, 300) as body
from net._http_response
where created > now() - interval '30 hours'
order by created desc limit 20;
```
읽는 법: **401** = 인증(게이트웨이 · Invocations 탭) · **500** = EF 내부 에러 · **`status_code` null + `Timeout`** = 5초 초과 — ⚠️ 실패가 아니다(2-2). 커서 전진 여부로 판정한다.

### 2-4. ✅ [실측 09-13] 해결 확인
`cost_transfer` `last_run` = `last_ok` = **09-13 00:45:03**(cron 시각 정확) · 커서 `2026-09-11T12:15:53Z` → **`2026-09-13T04:45:00Z`** · ⑦ 캡 없음. ⇒ **이틀치를 한 회차에 완주했다.**

---

## 3. 09-12 · 09-13 점검 요약

### 3-1. ⭐ 09-12 — 09-11 상쇄가 세 창구에서 검증됐다
`SO-14986`(`AS01287AST` −12 · 기초 경계 재유입)을 09-11 에 ⑨ 관례대로 상쇄 → 09-12 **01:21 스냅샷 기준** 대조에서 전부 사라졌다:

| 창구 | 09-11 | 09-12 |
|---|---|---|
| ⓪ `total` / `abs_gap` | 3 / **18** | **2 / 6** |
| ② `unknown_count` | **1** | **0** |
| ⑧ 토론토 | 1칸 | **0칸** |

⇒ ⭐ **⑨ 상쇄 처방(`manual`·`sale_out`·`:reversal`·부호 반전)이 실물로 검증됐다.** 📌 ⑧ 대조는 01:21 스냅샷 기준이라 **상쇄 당일에는 안 사라진다 — 다음 날 아침이 최종 확인**(스킬 ⑨ 에 넣었다).
나머지 09-12: ⑥ 0행(나흘째) · ⑦ 0행 · ⑨⑩⑪⑫ 0행 · `assembly` `in_ledger 3` 기준선 유지. 📌 09-11 에 있던 `transfer` 5회차 캡이 사라졌다 — 밀린 것을 소진했고 「`remaining`·`hold_capped` 가 줄어들면 정상」 기준이 맞았다.

### 3-2. 09-13 — 14항목 완주 · 새 결함 0건
| | 결과 |
|---|---|
| ⓪ | `new_today 0` · `total 2` = `prev_total` · `abs_gap 6` |
| ① | 01:21 · 13,707행(전일 **0** · 주말) |
| ② | `compared_pairs 14,205` 전량 일치 · `unknown 0`(09-12 와 동일 수치) |
| ④ | `list_total` **+102 반등**(§1-4) |
| ⑤ | 8축 전부 `last_run`=`last_ok` · ⭐ `cost_transfer` 정상화(§2-4) |
| ⑥ | 0행(닷새째) |
| ⑦ | 0행 — `cost_transfer` 가 이틀치를 캡 없이 완주 |
| ⑧ | 토론토 0칸 · 에드먼튼 2칸(`PRO00124`) · `bin_pairs` 09-12 와 동일 |
| ⑨⑩⑪⑫ | 전부 0행 · `assembly` 3 기준선 · `transfer` 경고 4건 **나흘째** |

📌 주말이라 `insert_rows`·`compared_pairs`·`bin_pairs` 가 전부 전일과 동일 — **「재고가 안 움직이는 것이 정상」의 실물**이다.

---

## 4. ⚠️ 내가 틀린 것
1. 09-12 에 「`list_total` 나흘 연속 하락 = 추세 확정」으로 판정했으나 **다음 날 반등했다.** 연속 횟수로 판정한 것이 잘못이었다(§1-4).
2. `list_total`/`insert_rows` 차이를 「재고 0 SKU 가 목록에서 빠지는 것」으로 **추론**했으나, `summary` 에 **`dropped_zero_nobin` 이라는 이름으로 이미 기록돼 있었다.** ⭐ **`summary` 원문을 먼저 읽었으면 사흘을 아꼈다**(§1-1).
3. `cost_transfer` 09-12 실행을 「PO+원가 쪽 수동 실행」으로 추론했으나 **cron 이 돈 것**이었다(Caleb 정정).
4. `inv-doc-cost` 정지의 원인을 아침에 「5초 타임아웃」으로 판정했으나 **401(`config.toml` 블록 누락)** 이었다(§2-2). 타임아웃 행은 다른 축에서도 매 회차 찍히는 정상 기록이다.

## 5. ⬜ 남는 것
- `transfer` 경고 4건 — 나흘째 미특정
- `null_bin_nonzero` 6건이 ⑧ 에서 어떻게 취급되는지(§1-5)
- ④ 원 문장 「유일한 급감 축」을 「불완전 스냅샷 축」으로 고쳐 쓸지(§1-3 · 출처는 찾았다)
