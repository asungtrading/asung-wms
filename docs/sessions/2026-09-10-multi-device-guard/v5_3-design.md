# 설계 보고 — 같은 사람의 다중 기기 동시 작업 차단 (2026-09-10)

**1차 판.** 시점: `255d68b` · `git diff --stat` = 변경 0 (untracked: `20260910152545_inv_doc_cost_table_only.sql` 하나).
읽기 전용 조사 + 설계. 코드 수정·커밋·psql 없음. 줄 번호는 이 시점 파일 기준.

Caleb 확정: ① 막는다 ② **새 기기가 이기고 옛 기기는 얼어붙는다**(로그인은 안 막는다) ③ 범위 = 픽·팩 + 리시빙, 리시빙의 여러 사람 동시 작업은 유지.

---

## 0. 한 줄 설계

**「한 작업(배치·wave·팩·receipt)은 한 화면에서만 열린다」** — 화면(탭)마다 고정된 `session_id` 를 만들고, 작업을 **여는 순간 서버에 그 값을 쓴다(새 화면이 이긴다)**. 쓰기 직전 `checkOwner` 와 **완료·Hold RPC 의 CAS** 가 「지금 서버의 session_id = 내 것」을 확인한다. 다르면 옛 화면이 얼어붙는다(지금 「남이 이어받았다」 프리즈와 같은 UX · 문구만 전용).

사람 단위가 아니라 **작업 단위**다 — 근거는 §4.

---

## 1. 세션 식별

### 1-a. `session_id` 는 어디에 두나 → **`sessionStorage` · 탭당 1개 · 새로고침에 유지**

| 후보 | 새로고침 | 같은 기기 두 탭 | 다른 기기 | 서버에서 스스로 아나 | 판정 |
|---|---|---|---|---|---|
| 메모리 변수(매 로드 랜덤) | ❌ 바뀜 → 새로고침이 「새 기기」로 오인 | 구분 | 구분 | ✗ | 탈락 (Ctrl+Shift+R 이 흔하다) |
| **`sessionStorage` UUID** | ✅ 유지(하드 리로드 포함 · 탭 닫으면 소멸) | 구분(탭마다 다름) | 구분 | ✗ → RPC 에 `p_session_id` 로 넘긴다 | **채택** |
| `localStorage` UUID | 유지 | ❌ 두 탭이 같은 값 — 같은 기기 두 탭을 못 잡는다 | 구분 | ✗ | 탈락 |
| Supabase JWT `session_id` 클레임 | 유지(로그인 세션) | ❌ 같은 기기 두 탭 동일 | 구분 | ✅ `auth.jwt()->>'session_id'` | 대안 — ⚠️ **클레임 존재를 확인 못 함**(이 프로젝트 코드에 사용례 0 · `auth.jwt()->>'email'` 만 사용 · baseline 67·255행). 같은 기기 두 탭도 위험 시나리오라 부적합 |

- ⚠️ **CLAUDE.md 「상태를 `localStorage` 에 저장하지 말 것」과의 관계**: 그 규칙은 *작업 상태*(held_by 등)를 기기에 두면 다른 태블릿에서 깨진다는 것이다. `session_id` 는 상태가 아니라 **이 화면의 정체(identity)** 이고, 정체는 정의상 기기(탭)에만 있어야 한다. 상태(「누가·어느 화면이 잡고 있나」)는 **서버 컬럼**에 둔다. 규칙과 충돌하지 않지만, 스킬 규칙에 이 구분을 한 줄 적어야 다음 사람이 「localStorage 금지인데 sessionStorage 는?」을 다시 묻지 않는다.
- **어디서 만드나**: `wms-auth.js` 에 `wmsAuth.sessionId()` 하나 — `sessionStorage.getItem("wms_session_id") ?? (setItem(crypto.randomUUID()))`. 세 화면이 같은 헬퍼를 쓴다(화면마다 만들면 키 이름이 갈린다). `wms-auth.js` 에는 지금 세션 개념이 없다 — Supabase auth 세션(토큰)만 라이브러리가 유지하고, `me` 는 `wms_staff` 행(name·role·perms)이다(`resolveIdentity` 166~185행). 확인 완료.
- **새로고침 흐름**(picker `restoreFromUrl` 406~431행 · packer `setUrlParam("pack")` 782행 · receiver `?receipt=` 511행): 같은 탭 → 같은 `sessionStorage` → **같은 session_id** → 프리즈 없음. ⭐ 지금 `restoreFromUrl`·`resumeBatch` 는 **서버에 아무것도 안 쓴다**(읽기만) — 설계상 「여는 순간 session_id 를 쓴다」가 되면 이 두 경로도 쓰기 1회가 생긴다(§2-a).
- 탭을 닫고 새 탭에서 URL 로 들어오면 새 id → 새 화면이 이긴다 → 옛 탭은 이미 없다. 무해.

### 1-b. 서버에는 어떻게 남기나 → **픽·팩 = 컬럼 추가 · 리시빙 = 별도 표**

| 대상 | 방식 | 이유 |
|---|---|---|
| `wms_pick_tasks` · `wms_waves` · `wms_pack_tasks` | `add column session_id text` (assigned_to 옆) | 점유가 **행 하나**에 있고 CAS 가 그 행을 본다. 조건 한 줄 추가로 끝. 별도 표면 CAS 가 조인이 된다 |
| 리시빙 | 새 표 `wms_receipt_sessions (receipt_id bigint, worker text, session_id text, opened_at, last_seen_at, primary key (receipt_id, worker))` | receipt 한 장에 **사람이 여럿**이라 receipt 행에 컬럼 하나로는 못 담는다. (receipt, 사람) 당 세션 1개 = 「여러 사람 허용 · 같은 사람은 하나」를 그대로 표현 |

컬럼은 nullable — 배포 전에 잡힌 클레임(session_id null)은 **통과**시킨다(레거시 호환 · §2-b). 릴리스(`assigned_to=null` 로 되돌리는 곳들 — Hold RPC·자동 Hold·admin 롤백 3곳)에서 session_id 를 지울 필요는 없다: **모든 클레임이 덮어쓴다**. 남겨두면 「마지막으로 잡았던 화면」 기록이 돼 오히려 유용하다.

---

## 2. 픽·팩 — 어디를 고치나

### 2-a. 클레임 = session_id 를 쓰는 순간 (전수)
`assigned_to:me.name` 을 싣는 UPDATE/INSERT 11곳 전부에 `session_id: SID` 를 더한다:

| 파일:행 | 함수 | 비고 |
|---|---|---|
| picker 682 | `scanTakeover` | |
| picker 710 | `startBatch` | |
| picker 732 | `takeoverBatch` | |
| picker 929 · 935 | `startWave` (wave 행 + 멤버) | wave 는 **wave 행**이 CAS 단위 — 멤버 task 에도 같이 싣는다(983행과 같은 `.eq("wave_id")`) |
| picker 975 · 983 | `takeoverWave` | |
| packer 647 | `scanTakeoverPack` | |
| packer 678 | `startPack` (insert) | |
| packer 699 | `resumePack` (pending → 클레임) | |
| packer 740 | `takeoverPack` | |

⭐ **새로 쓰기가 생기는 곳 둘**: picker `resumeBatch`(744행)·`restoreFromUrl`(413행) 와 `resumeWave`(954행), packer `resumePack` 의 **in_progress 재개 분기**(699행은 pending 분기만) — 지금은 읽기만 한다. 「여는 순간 새 화면이 이긴다」가 되려면 여기서
`update … set session_id = SID where id = ? and assigned_to = me.name and status = 'in_progress'` `.select()` **1행 판정**(규칙 20/24 관례)을 한다. 0행이면 남이 가져간 것 → 지금의 「no longer in My In Progress」 토스트 그대로.

### 2-b. `checkOwner` — 이름 비교에 session 비교를 더한다
`picker.html:333~352` · `packer.html:352~370`. `select("assigned_to,held_by,session_id")` 로 바꾸고:
```
who !== me.name                         → 지금 그대로 {s:"lost", who, heldMine}
who === me.name && row.session_id && row.session_id !== SID
                                        → {s:"lost", who:me.name, otherDevice:true}   ← 신설
who === me.name && row.session_id == null → {s:"ok"}  (배포 전 클레임 — 레거시 통과)
```
`ensureMine`(360행 · 374행)이 `otherDevice` 면 `freezeScreen(null, otherDeviceMsg())`. `guardOnReturn`(복귀 감지) 동일. 호출처는 무변(`saveLine`·선언·완료·Hold 앞 — picker 1305·1336·1386·1535 / packer 1094·1298·1352·1488).

⚠️ `saveLine` 의 라인 UPDATE 자체(`wms_pick_task_lines … eq id`)에는 session 조건을 못 건다(라인 표에 세션이 없다). 「확인 → 쓰기」 사이 수십 ms 경합은 남지만 유실은 스캔 1건 규모다. **큰 구멍(스냅샷 전량 덮어쓰기)은 RPC CAS 가 닫는다** — 그래서 2-c 가 필수다.

### 2-c. ⚠️⚠️ RPC 4개의 CAS — `p_session_id` 추가
| RPC | 최신 정의(전수 grep) | CAS 절 |
|---|---|---|
| `wms_complete_pick` | `20260806160000_wms_complete_pick_rpc.sql` (이후 재정의 없음 — `20260821201104:17` 「무접촉」) | wave 69행 · 단일 94행 |
| `wms_hold_pick` | `20260824192416_task_holds.sql` (20260807000000 을 덮음) | wave 90행 · 단일 115행 |
| `wms_complete_pack` | `20260825193231_preserve_verification_method.sql` (20260806150000 → 20260821201104 → 이것) | 79행 |
| `wms_hold_pack` | `20260825193231_preserve_verification_method.sql` (20260807000000 → 20260824192416 → 이것) | 206행 |

바꾸는 것 **세 가지만**:
1. 시그니처 끝에 `p_session_id text default null` 추가.
2. CAS `where` 에 `and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)` 한 줄. (wave 는 `w.session_id`.) — `p_session_id null` = 옛 클라이언트(배포 창) 호환 · `t.session_id null` = 레거시 클레임 통과 · 둘 다 있으면 같아야 한다.
3. CAS 0행 반환에 `'reason'` 추가: `session_id` 가 달라서 0행이면 `'other_device'`(같은 행을 한 번 더 읽어 판정 — `completeCasFailed` 가 지금 하는 재조회를 서버로 옮기는 셈). 클라이언트가 이름 드리프트·자동 Hold·타인 이어받기·**다른 기기**를 한 분기씩 가른다.

⚠️ **시그니처가 바뀌면 `create or replace` 가 새 오버로드를 만든다** — 옛 6인자 함수가 남아 PostgREST 가 이름 기반 매칭에서 둘 다 맞는 옛 호출(p_session_id 생략)을 **모호하다고 거부**한다. ⇒ 마이그레이션에서 `drop function if exists public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb);` 처럼 **옛 시그니처를 먼저 drop** 하고 새로 만들고 **revoke/grant 를 다시 건다**(ACL 보존은 같은 시그니처 replace 에서만 — `20260825193231:24` 주석). 선례: `20260909174046:85~86` 의 `drop function if exists inv_layer_apply_po_in(bigint, date)`.

### 2-d. 동작 동일성 증명 — 검증된 경로라 셋으로 묶는다
1. **원문 기준 diff**: 위 표의 최신 파일에서 함수 본문을 **통째로 복사**(자르지 않음)해 새 마이그레이션에 넣고, `diff <(옛 본문) <(새 본문)` 을 보고에 첨부 — 허용되는 차이는 ① 파라미터 1줄 ② CAS 조건 1줄(함수당 1~2곳) ③ 0행 반환의 `reason` 필드 ④ drop/revoke/grant 만. 그 외 한 글자라도 다르면 실패.
2. **로컬 `db reset` + fixture 트랜잭션**(원가 레이어 검증과 같은 방식 · 파일은 `scripts/testdb/session_guard_check.sql` 로 남긴다):
   - 회귀 — `p_session_id` **null** 로 호출: 정상 완료(플립·라인 저장·short_pick 생성·stock_short 정리) 결과가 종전과 **행 단위로 동일** · `assigned_to` 불일치 → `completed:false` · wave 멤버 수 불일치 → 예외·전체 롤백.
   - 신규 — `t.session_id='A'`, `p_session_id='A'` → 성공 / `'B'` → `completed:false, reason:'other_device'` 이고 **라인·discrepancy 행 변화 0**(트랜잭션 안에서 count 대조) / `t.session_id null`, `p='B'` → 성공(레거시).
   - Hold 둘도 같은 격자.
3. **배포 순서(규칙 23)**: 마이그레이션(컬럼 + RPC) 먼저 → HTML. 옛 HTML(캐시)은 `p_session_id` 없이 호출해도 default null 로 종전 동작. 새 HTML 이 옛 RPC 를 만나면 400 — 그래서 순서가 고정이다.

### 2-e. 프리즈 문구 — 전용 (`autoHoldMsg` 선례)
지금 문구 「This batch is now assigned to {who}」는 who 가 자기 이름이면 어색하다. 신설:
```
otherDeviceMsg(): "This {batch|wave} is now open on another device that is signed in as you.
                   This screen is out of date and won't save. Continue on the other device —
                   or tap Reload here to take it back to this one."
```
Reload → `restoreFromUrl` → session_id 를 이 탭으로 다시 씀 → **저쪽이 얼어붙는다**. 「새 것이 이긴다」 규칙이 양쪽에 대칭으로 적용된다. 완료 RPC 0행의 `reason:'other_device'` 도 같은 문구로.

---

## 3. 리시빙 — 여러 사람 허용 · 같은 사람은 하나

### 3-a. 표 `wms_receipt_sessions` — (receipt, worker) 당 세션 하나
- `openReceipt()`(`receiver.html:774`) 진입 시 `upsert({receipt_id, worker: me.name, session_id: SID, opened_at, last_seen_at})` on conflict `(receipt_id, worker)` → **새 화면이 이긴다**. 진입 경로는 셋(511 딥링크 · 763 startPo · 770 resumeReceipt) 이고 전부 `openReceipt` 로 수렴하므로 **한 곳**이다.
- 다른 사람은 다른 행 → 서로 무관. 「여러 사람 허용 · 같은 사람은 하나」가 표 구조로 표현된다.

### 3-b. 가드 — `ensureReceiptOpen` 확장 (있는 것을 넓힌다)
`ensureReceiptOpen()` (1507~1527행)은 이미 「쓰기 직전 · 3초 억제 · 확인 실패 시 통과」 관례로 `applied_at` 을 본다. 여기에 `wms_receipt_sessions` 의 내 행을 함께 읽어(요청 1개 추가가 아니라 **두 select 를 병렬** 또는 뷰 하나) `session_id !== SID` 면 **리시빙용 freezeScreen**(신설 — 스캔 입력 비활성 · 완료/Hold 비활성 · 오버레이 · Reload 버튼 · picker 와 같은 모양)을 띄우고 `unconfirmed` 를 **버린다**(flush 금지 — 스테일 값을 쓰면 안 된다 · picker 367행 주석과 같은 원칙).
- 호출처 확대: 지금은 풋어웨이 두 곳(`savePutaway`·`placeAllInBin`)만. **`saveLine`(수량) 에도** 건다 — ⚠️ 단, `saveLine` 은 `await` 를 걸어 렌더·비프를 막으면 안 된다(1481~1482행 · 재스캔 과다계상 실사고). ⇒ 낙관적 렌더 뒤 `ensureReceiptOpen().then(ok=>{ if(!ok) … })` 로 **비동기 사후 검사**. 3초 억제라 스캔 연타에 요청이 늘지 않는다. 얼면 그 뒤 스캔은 `frozen` 으로 차단.
- `visibilitychange`/`focus` 복귀 감지도 picker `guardOnReturn` 그대로.
- 완료 뒤 열린 화면 문제(v5_1 §2-f)도 같은 자리에서 잡을 수 있다: `status in ('completed','externally_applied')` 도 닫힘으로 본다 — **범위에 넣기를 권한다**(한 함수의 조건 한 줄).

### 3-c. `wms_receipt_stage_events` 로 판정 가능한가 → **아니다**
전환(Putaway↔Receiving) 때만 append 되는 이력이라 「지금 어느 화면이 살아 있나」를 모른다 — 새로고침·전환 없는 스캔은 기록이 없고, 옛 행을 지울 수도 없다. **증거(사후)** 로는 최적이고 **가드(사전)** 로는 부적합. 표는 그대로 두고 지표(「복귀 빈도」)만 두 화면 시절 값이 부풀었음을 각주.

### 3-d. `finishReceipt` 에 CAS 가 필요한가 → **status 조건은 넣지 않는다 · 세션 검사만**
- `completed` UPDATE 의 무조건은 **의도**(A 가 Hold 한 문서를 B 가 완료 · 2034~2036행). 같은 사람 문제는 이 무조건이 만드는 것이 아니다 — 완료는 라인을 덮지 않는다(`flushUnconfirmed` 만).
- 필요한 것은 `preFinish` 맨 앞에 `ensureReceiptOpen()`(세션 검사 포함) 한 번 — 얼어붙은 화면의 Complete 를 막는다. `partial` 은 RPC CAS 가 이미 있다.

### 3-e. 서버 측 강제는? → **2단계로 미룬다**
라인은 클라이언트가 직접 PATCH 하므로 RPC CAS 를 둘 자리가 없다. 강제하려면 ① `wms_receipt_lines.session_id` 컬럼을 PATCH 에 싣고 ② BEFORE UPDATE 트리거가 `wms_receipt_sessions` 와 대조해 raise — 가능하지만 기계가 커진다. 리시빙의 위해는 「같은 라인 lost update(스캔 1건 규모)」라 **클라이언트 best-effort 가드(규칙 28 계열)가 비례적**이다. §4 SQL(v5_1 ③) 실측이 「나란히 스캔」을 보이면 그때 트리거로 올린다.

---

## 4. 정당한 다중 기기 — **작업 단위로 잠근다 (사람 단위 아님)**

| 상황 | 사람 단위 잠금이면 | 작업 단위 잠금이면 | 판정 |
|---|---|---|---|
| 매니저가 admin(PC) + picker(태블릿) | admin 은 클레임이 없어 어느 쪽이든 무관 | 무관 | 둘 다 OK |
| 같은 사람 · **다른 배치** 두 기기 | ❌ 한쪽이 얼어붙음 — 수량 유실이 없는 경우를 막는다 | 허용 | **작업 단위** |
| 같은 사람 · picker(배치 A) + receiver(TR) | ❌ 막힘 — 정당한 병행(소량 창고에서 실재할 수 있다 · 추측) | 허용 | **작업 단위** |
| 같은 사람 · **같은 배치** 두 기기 | 막힘 | 막힘 | 둘 다 OK — 이것이 유일한 실위험 |

- 수량 유실은 **같은 작업 행을 두 화면이 쓰는 경우에만** 난다(v5_1 §2·§3 — 라인 표 절대값 PATCH · 완료 RPC 스냅샷). 다른 배치는 다른 행이라 물리적으로 겹치지 않는다. 사람 단위로 막으면 **막을 이유가 없는 것을 막고 풀어줄 수단이 또 필요**해진다(Caleb 이 로그인 차단을 배제한 것과 같은 이유).
- Caleb 의 「한 사람은 한 기기가 화면마다 다르면 헷갈린다」는 **규칙의 일관성** 문제다 — 작업 단위 규칙도 세 화면에서 **문장이 하나**다: 「한 작업은 한 화면에서만. 다른 화면에서 열면 이전 화면은 멈춘다.」 픽·팩(배치/wave/팩)·리시빙(receipt) 모두 같은 문구로 얼어붙는다.
- ⚠️ 작업 단위의 한계: 같은 사람이 배치 A 를 기기 1 에서, 배치 B 를 기기 2 에서 여는 것은 허용되므로 「한 사람이 두 기기를 들고 다닌다」 자체는 안 막힌다. 그건 위험이 아니라 관리 문제이고, LIVE NOW 가 보여주면 된다(§6).

---

## 5. 순서 — 실해 0건을 감안해 **한 화면씩**

| 단계 | 내용 | 산출물 | 근거 |
|---|---|---|---|
| **1** | **픽·팩** — 마이그레이션 1개(컬럼 3표 + RPC 4개 drop/재생성) + picker/packer(클레임 11곳 + 재개 2곳 쓰기 + checkOwner + 문구) + `scripts/testdb/session_guard_check.sql` | 마이그레이션 · HTML 2 · 검증 SQL · diff 보고 | 위험이 크고(스냅샷 전량) 방어가 전부 뚫리는 유일한 경우 |
| **2** | **리시빙** — 마이그레이션 1개(`wms_receipt_sessions`) + receiver(openReceipt upsert · ensureReceiptOpen 확장 · saveLine 사후 검사 · freezeScreen 신설 · preFinish 검사 · completed 닫힘) | 마이그레이션 · HTML 1 | 위해가 작고 클라이언트 변경이 크다 — 1 의 문구·프리즈 모양을 그대로 이식 |
| **별건** | 리시빙 **같은 라인 CAS(델타 재적용)** | — | **이번 범위에서 뺀다.** 그것은 「두 사람」 문제이고 저장 엔진(`writeLine` 0행 분기)을 바꾸는 일이라 성격이 다르다. 같은 사람 차단이 들어가면 같은 라인 충돌의 절반(같은 사람)은 사라지므로 급하지 않다 |
| **별건** | LIVE NOW 표시 | — | §6 |

1 → 2 사이에 1 의 현장 관찰(프리즈가 언제 뜨나 · `reason:'other_device'` 발생 수)을 하루 이상 두기를 권한다 — 리시빙 프리즈 모양을 그 관찰로 다듬는다.

---

## 6. LIVE NOW — 이번 범위에서 뺀다 · 결정만 먼저
- 지금은 「연결 수」다(v5_1 §1). 작업 단위 잠금이 들어가면 **같은 작업의 두 연결은 몇 초 뒤 하나가 얼어붙어 untrack** 되므로 「같은 줄 두 번」은 **자연히 짧아진다**(비정상 이탈 잔존은 그대로).
- 결정할 것은 하나: 헤딩 "screens open this second" 를 유지해 **화면 수**로 읽을지, 사람·문서로 묶어 **`×2` 배지**를 붙일지. 어느 쪽이든 `liveList()`/`renderLiveStrip()` 두 함수 안의 변경이고 20줄 안이다. 결정 뒤 2 단계 뒤에 붙이면 된다 — 1·2 와 섞으면 프리즈 검증과 표시 검증이 뒤섞인다.

---

## 7. 확인 못 한 것 · 추측
- Supabase JWT 의 `session_id` 클레임 존재 — 사용하지 않기로 했으므로 결정에 영향 없음. 확인 못 함.
- Realtime presence 의 비정상 이탈 후 잔존 시간 — 가드에 presence 를 **쓰지 않는** 이유이기도 하다(오탐). 확인 못 함.
- 「같은 사람이 picker + receiver 를 병행하는 정당한 경우가 실재한다」 — 추측. 있어도 없어도 작업 단위 설계는 안전한 쪽이다.
- 새 HTML 이 옛 RPC(6인자)를 만날 때 PostgREST 가 400 을 내는 것 — 일반 동작에서 추론(이름 매칭 실패). 배포 순서를 지키면 발생하지 않는다.
- `wms_complete_pick` 의 wave 멤버 UPDATE(`where t.wave_id = p_wave_id and t.assigned_to = v_worker`)에 session 조건을 **넣지 않는다** — wave 행 CAS 가 소유권 단위이고 멤버는 서버 유도(원문 주석)라 종전 구조를 유지한다. 멤버에도 걸면 startWave 가 멤버에 session_id 를 안 쓴 레거시 wave 에서 「n of m matched」 예외가 난다.

---

## 승인 요청 항목 (구현 전)
1. `sessionStorage` UUID + `wmsAuth.sessionId()` (1-a) — 스킬 규칙에 localStorage/sessionStorage 구분 한 줄 추가 포함.
2. 컬럼 3개 + 표 1개 (1-b).
3. RPC 4개 drop/재생성 + `p_session_id default null` + CAS 한 줄 + `reason` (2-c) · 증명 방식 (2-d).
4. 작업 단위 잠금 (§4).
5. 순서: 픽·팩 → 리시빙 → (별건) 라인 CAS · LIVE NOW (§5·§6).
6. 문구 (2-e).
