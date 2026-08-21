# 2026-08-21 — 원장 가동 첫날 검증 · 픽 시간 결함 규명 · 라인 시각 편승 1단계

어제 두 문서(`2026-08-20-admin-warehouse-boundary.md` — admin 작업 · `2026-08-20-ledger-go-live.md`
— ⑤ 가동)의 다음 날이다. 이어 붙이지 않고 포인터만: 가동 경위는 go-live 문서, admin 창고 경계는
boundary 문서가 각각 정본이다.

커밋: `c1c84f6`(라인 시각 편승 1단계 — 코드) + 이 문서 커밋(문서만).

---

## 1. 원장 ⑤ 가동 첫날 — 정상 (정본: 설계 4부 「가동 첫날 검증」)

pg_cron 6잡 전부 `last_run_at` 갱신. 커서 전진: `transfer` `TR-01327` → **`TR-03974`**(밤사이
2,647건 소화) · `adjustment` `ST-01232` → `ST-01233` · 나머지 시각 커서 정상.

⭐ **첫 실물 대조 통과** — `ST-01233`(파손 조정): 3 SKU 전부 Cin7 Variance = 원장 `qty_delta`
(−1/−3/−20), bin(`B011202`·`B011102`)까지 정확. 📌 **Cin7 은 `New Quantity`(절대값), 원장은
증감분** — 변환이 옳다.

✅ `since` 실동작 — `TR-03539` 는 오늘 적용됐지만 **사건 날짜가 8/4** 라 정확히 제외(스냅샷에 이미
녹아 있다). 갱신 축과 사건 날짜의 독립이라는 설계 전제의 첫 실물.
✅ 트랜스퍼 4행 구조 실동작 — `TR-04166~70` 각 4행·합계 0.
📌 **`TR-01327` seed 판단 적중** — `TR-03539` 는 버려진 게 아니라 실제 적용 대상이었다.
`TR-03539` 로 seed 했다면 실재하는 이동이 통째로 빠졌고, 지나간 뒤라 알아채기 어려웠다.
「되돌릴 수 있는 쪽을 고른다」의 값어치.

⚠️ **대기 중**: `TR-03975`·`03976`(IN TRANSIT — `hold_intransit_before_since`) — **도착하면
「since 경계 아티팩트」 첫 실물**(1·2행이 걸러져 IN_TRANSIT 음수). 그때 원장 확인.

⚠️ **검증 범위 정직하게**: Cin7 대조는 조정 1건뿐 — 판매 45건·발주 2건 미대조 ·
`inv_conflicts` 는 아직 빈 상태(두 번째 회차부터 의미). **전량 대조는 ⑥의 일이다.**

---

## 2. SO-15028-1 픽 시간 결함 규명 — reaper × 08-11 backfill 조합 (정본: 스킬 규칙 37)

229라인 배치가 Stats 에 **4.1분** — 물리적으로 불가능. 조사 결과:

- **지문**: `heartbeat_at` 이 `started_at` 보다 0.12초 빠름 = `startBatch` 의 UPDATE 두 번
  (클레임 → `ensureStartedAt`) 콤보 = **클레임 순간 started_at 이 null 이었다.**
- **원인 사슬**: hold 재개(`startBatch`)가 `work_started=false` 리셋 → 3분 무스캔 방치 →
  **reaper 가 유령으로 오판, `started_at` 까지 소거**(진행은 보존) → 재클레임 시
  `ensureStartedAt`(08-11 backfill)이 「최초 시작」으로 오인해 새로 찍음 → 잔여 마감 4.1분.
  ⇒ **08-11 수정과 reaper 는 각각 옳았으나 조합이 틀렸다.**
- 📌 8/10 건(`SO-14393-3`)은 `started_at == heartbeat_at` 동일 밀리초 — 08-11 이전의 옛 결함
  (이미 수정됨). **두 건은 다른 결함이다** — 지문(밀리초 차이)이 가른다.
- ⚠️ 재발 조건이 창고 일상(held 재개 후 자리 비움) · 팩도 같은 구조.
- **처방(reaper 수정)은 보류** — 「4.1분」을 「3시간」(벽시계)이라는 **그럴듯해서 더 안 들키는
  거짓**으로 바꿀 뿐. 새 자(아래 3) 검증 후 판단.

---

## 3. 라인 시각 편승 1단계 배포 (`c1c84f6` — 정본: 스킬 백로그 「picked_at 살리기」)

스캔 저장(`saveLine`)에 `picked_at/picked_by`·`verified_at/verified_by` 편승 — **왕복 +0**
(기존 UPDATE 에 필드만 추가 · 배터리 영향 0 — heartbeat 제거 사유와 충돌하지 않는다).
팩 RPC 는 `coalesce(l.verified_at, v_now)` **한 단어**(스캔 시각 보존) · 픽 RPC 무접촉.
테스트 39케이스 통과(팩 9 — 신규 보존 케이스 포함 · 픽 12 · hold 18).

- ⚠️⚠️ **화면은 아직 안 바뀐다** — 시각이 조용히 쌓이기만 한다. Stats 교체는 2단계.
- ⚠️ 과거는 영영 계산 불가(배포 이전 19,375행 — 2단계에서 「—」 표시).
- **목표**: 벽시계가 아니라 **스캔 구간 누적**(갭 15분+ 세션 분리 — N 은 분포 보고 확정).
- 📌 **Caleb 확인**: 첫 스캔 전 준비·마지막 스캔 후 정리가 빠지는 것 **수용**(「손을 댄 시간」이지
  자리를 지킨 시간이 아니다). ⚠️ 한 라인 세션 = 0분 — 분포 보고 판단(추측 보정 금지).
- 📌 리시빙은 갭 컷 없이 그대로 — **의도된 임시 불일치**(검증 대상을 셋으로 안 늘린다).
- 📌 백로그 재평가: 종전 비용 ②(「스캔마다 쓰기 = 왕복 급증」)는 **오판**이었다 — saveLine 이
  이미 스캔마다 UPDATE 1개를 보내고 있었다. 그 오판이 항목을 8일 보류시켰다.

---

## 4. ⚠️ 검증 대기 — 다음 세션이 먼저 볼 것 (스킬 「검증 대기」 맨 위에도 동일 기재)

```
⬜ 1. 라인 시각 기록 검증 — 다음 픽·팩 작업 직후
   select picked_at, picked_by, picked_base, status
   from wms_pick_task_lines where picked_at is not null order by picked_at desc limit 5;
   (팩은 verified_at·verified_by 동일)
   ⚠️ 값이 안 들어오면 프론트 캐시(Ctrl+Shift+R) 또는 배포 순서 확인

⬜ 2. 2단계 — Stats 계산 교체 (다음 주 예정)
   갭 분포 SQL 로 N 확정 → 스캔 구간 누적 계산 → ⚠️ 벽시계 avg 와 병기(교체 아님 — 대조군)
   select width_bucket(extract(epoch from gap)/60, 0, 60, 12) as bucket_5min, count(*)
   from (select picked_at - lag(picked_at) over (partition by pick_task_id, picked_by order by picked_at) as gap
         from wms_pick_task_lines where picked_at > '2026-08-21') g
   where gap is not null group by 1 order by 1;

⬜ 3. 리시빙 갭 컷 통일 — 2단계 검증 후

⬜ 4. reaper started_at=null 제거 — 새 자 검증 후 판단(§2)
```

---

## 5. 다음에 할 것

1. **⑥ shadow 대조 설계 — 다음 원장 작업.** 매일 Cin7 과 비교 · 차이 분류
   (타이밍/구조적/사각지대/영구) · 불일치 0이 30일 지속되면 하드 플립.
   📌 이미 아는 구조적 차이 2종: WMS discrepancy 큐 ≠ 최종 진실(매니저 실사 기준) ·
   IN TRANSIT 경계 아티팩트.
   ⚠️ `inv_compare` 가 설계에 이름만 있는지 어디까지 구현됐는지 **조사가 선행**.
2. **검증 대기 4건** (§4)
3. **TR-03975·03976 도착 시** IN_TRANSIT 경계 아티팩트 확인 (§1)

**별건**: WarehouseMap 을 WMS 로(재고·이미지 전부 WMS · 레이아웃 DB 화) ·
브랜치 변경 대응 · `hello` `DETAIL_DELAY_MS=250ms` · Advanced PO 기본값 실물 검증 ·
`product-images` cron 결과물 확인 · `asung-ops` 이관 · 조직 이전(버스팩터)
