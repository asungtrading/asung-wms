# 2026-08-12 저녁(집) 추가분 — 병렬 검증 닫힘 · admin 3건

> 기존 `docs/sessions/2026-08-12-hold-and-postgrest-cap.md` 에 **이어 붙일 추가분**이다.
> 오후 세션 기록 커밋(e83a3ae) 이후 집에서 진행한 내용.

---

## A. 배포된 것 (1커밋)

`fix(admin)` — Rollback 레이아웃·finalize 기본 숨김 · Work Screens 탭 제거 · PHASE `Pack ready` 분리

### ① Rollback 레이아웃 + finalize 숨김
- **문제**: 오늘 낮 응급 조치로 넣은 비활성 사유 2줄이 버튼 열 폭을 밀어 **`Void` 버튼이 잘렸다**(실측)
- **처방**: 배지(`Finalized — no undo`) + 툴팁(전문). ⚠️ **툴팁은 태블릿에서 안 보이므로 배지 문구가 스스로 설명해야 한다** — `Finalized` 만으로는 "왜 안 눌리는지"가 안 읽힌다
- **finalize 기본 숨김 토글** — `finalized_at` 기준이라 direct·packing_list 둘 다 잡힘
- 📌 **근거 [실측]**: 롤백 대상 오더 중 **finalized 640 vs 미finalized 21**. **97%가 되돌릴 수 없는 것**이었다. 되돌릴 수 있는 21건만 보이는 게 이 화면의 목적에 맞다

### ② Work Screens 탭 제거
- Menu 에 4개(Order Splitting·Picking·Packing·Staff Management)가 **전부 있음**을 코드로 확인
- ⚠️ 화면 안내문 *"Opens files in the same folder. After deployment these link to the real URLs"* 는 **`location.href` 를 쓰므로 이미 죽은 문구**였다(로컬 파일 이동 기능은 실재하지 않았다)

### ③ BATCH ACTIVITY 의 PHASE — `Packing` → `Pack ready` 분리
- **판정**: `pack_started` 가 null 이면 `Pack ready`(회색), 있으면 `Packing`
- ⚠️ **STATE 열(Active/Away/Waiting)과 축이 다르다** — PHASE 는 배치 단계, STATE 는 화면 점유. 중복 아님

---

## B. [실측] 병렬 배치 검증 — 닫는다

### Cin7 API Log 실측 (2026-08-12 오후, 토론토 시각)
```
17:57:56  GET × 2  ?TaskID=          ← 회차 시작
17:57:56  POST × 4                    ← 배치 1 (같은 초)
17:58:06  POST × 4                    ← 배치 2 (같은 초)

18:18:20  GET  ?TaskID=8b6da07d
18:18:20~21  POST × 4                 ← 배치 1
18:18:29     POST × 4                 ← 배치 2
18:18:38     POST × 4                 ← 배치 3   ← 한 회차에 12그룹(APPLY_MAX_GROUPS 상한)
18:18:48  GET × 2  ?TaskID=           ← 새 회차 (경계 10초)
18:18:49     POST × 2
```

### 판정 근거 셋
1. **POST 4건이 같은 초에 묶여 나간다** — 여러 트랜스퍼에서 반복 확인
2. **회차당 12그룹 달성** — `APPLY_MAX_GROUPS` 상한에 걸림(어제 예상 "8~12그룹" 실현)
3. **TR 번호 역전** — TR-03533 의 `ED020701(3932) → EB020303(3931)` 순서 어긋남 = **큐잉 없음**. 어제 프로브와 같은 지문

**배치 간격 8~10초** = POST 처리 6~9초 + sleep 1.2초. 설계 그대로.

### ⚠️ 회차 경계 45초 — 재현되지 않는다
어제 TR-03738 에서 관측한 45초가 **오늘은 10초**다.
- 어제는 **표본이 회차 경계 1개**뿐이었다
- 어제 관측은 **폴링 수정(52콜 → 2~3콜) 전**이었다
→ **백로그에서 "관찰 대기"로 낮춘다.** 재현되면 그때 F12 Network 로 조사.

### 오늘 트랜스퍼 4건 [실측]
| TR | applied_by | 그룹 | 라인 |
|---|---|---|---|
| TR-03531 | Changmo Ku | 11 | 41/41 |
| TR-03534 | Changmo Ku | 3 | 117/117 |
| TR-03533 | Changmo Ku | 8 | 197/197 |
| TR-03532 | Changmo Ku | 6 | 44/44 |

넷 다 `ALL GROUPS DONE` · 전량 exported · **한 회차에 완주**(시간 예산에 걸린 적 없음).
⚠️ `RETRY of a partial apply from **?**` 표시 결함이 넷 다 나온다 — 흔한 경로다(백로그).

⬜ **176그룹급에서 회차가 여러 번 도는 상황은 아직 안 겪었다** — 원래 검증 목적이었으나, 12그룹 상한 달성과 병렬 지문 확인으로 **충분하다고 판단해 닫는다.**

---

## C. [실측] PHASE 라벨이 오해를 만든 경위

### SO-14496 조사
| batch | pick | pack 태스크 | 종전 화면 |
|---|---|---|---|
| `-11` | completed | **없음** | `Pick done` |
| `-10` | completed | **pending**(assigned_to·started_at 전부 null) | **`Packing`** |

⚠️ **둘 다 팩 대기열에 있고 아무나 잡으면 되는 같은 상태**인데 다른 단계처럼 보였다.
`Packing` 은 "팩 진행 중"이 아니라 **"팩 태스크 행이 존재함"** 이었다 — 누가 `Start verify` 를 눌렀다가 스캔 없이 나가면 행만 남는다.

📌 **사용자와 나 둘 다 "팩이 시작됐는데 멈춘 것"으로 오해했다.** 표시가 내부 구현(행 유무)을 노출하고 실제 상태를 감췄다.

### 수정 후
`pack_started` 기준이라 **`-10`·`-11` 둘 다 `Pack ready`** 로 나온다 — 실제 상태와 일치한다.

---

## D. [정정] 저녁에도 추측으로 빗나갔다

| 주장 | 실제 |
|---|---|
| SO-14496-10 은 "팩 시작 후 Hold" | `held_by` null · `started_at` null — **아무도 안 열었다** |
| "코드 에러 같다"에 동조할 뻔 | `status='pending'` · 전부 null = **정상 상태** |
| `Packing` = 팩 태스크 유무 | `-11` 도 태스크가 있다고 해서 뒤집었는데, **실제로는 없었다**(내가 데이터를 잘못 읽음) |
| `updated_at` 컬럼 사용 | `wms_pack_tasks` 는 `created_at` — **오늘 컬럼명 오류 3회째** |

📌 **오늘 "최근 배포를 먼저 의심"이 세 번 빗나갔다.** 팩 대기열 장애 · SO-14496-10 · PHASE 라벨.
📌 **데이터부터 보는 것이 매번 옳았다.**

---

## E. 집 PC 설정 — 커밋 훅

⚠️ **`core.hooksPath` 는 머신 로컬 설정이다.** 회사에서 설정해도 집에는 없다.
```bash
cd ~/asung/asung-wms
git config core.hooksPath scripts/hooks
bash scripts/test-caps-hook.sh   # 9/9 PASS 확인
```
⚠️ **레포를 헷갈리지 말 것** — GAS 레포에 잘못 걸면 그 레포엔 `scripts/hooks` 가 없어 훅이 조용히 안 돈다(실제로 한 번 그랬고 `git config --unset` 으로 되돌림).

⚠️ 그리고 훅 자체 테스트의 마지막 두 항목이 중요하다:
- `레포 전체 클린` — 기존 27곳에 `caps-ok` 가 다 붙어 있어 **파일을 건드려도 커밋이 안 막힌다**
- `사유 없는 caps-ok 거부` — 예외를 남발할 수 없다

---

## F. 신규 백로그

1. **Rollback 토글 라벨 숫자** — `Hide finalized (640)` 인데 목록에는 **200건뿐**이다(캡션 `Latest 200 of 640` 과 같은 숫자를 쓴다). 매니저가 "640개라더니 왜 200개만?"으로 헷갈린다. ⚠️ 표시 문제라 작업은 안 막힘
2. **MISTAKES BY WORKER 항목** — ⬜ **수정 내용 미확정.** 사용자가 남은 항목으로 지목했으나 구체 내용은 다음에 확인
3. **회차 경계 45초** — 기존 항목을 **"관찰 대기"로 낮춤**(오늘 10초, 재현 안 됨)

---

## G. admin 남은 것 (우선순위)

| # | 항목 | 크기 |
|---|---|---|
| 1 | **Status 확장** — 카드 클릭 → 오더 목록 · state/phase 정렬 · 지체 표시(대기시간 + `ship_by`, 2일 목표) | 큼 (지표 설계 판단 포함) |
| 2 | **`short_pick` 작업자 이름** — (가') `wms_discrepancies` 새 컬럼 + `responsible` 과 구분되는 꼬리표 | ⚠️ admin 밖(마이그레이션 + 픽 완료 RPC) |
| 3 | **MISTAKES BY WORKER** | 내용 미확정 |
| 4 | **Rollback 토글 라벨 숫자** | 작음 |

---

## H. 앵커 갱신

08-12 열에 반영할 것:
- **배포 15건**(오후 14 + 저녁 1)
- **조용한 결함 6건** — 저녁 작업에서 추가 발견 없음(PHASE 라벨은 표시 오해지 데이터 오류가 아니다)
- ⚠️ **정정 8건 → 12건** — 저녁에 4건 추가(D절)
