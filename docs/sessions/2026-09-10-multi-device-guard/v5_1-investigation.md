# 조사 보고 — 같은 사람이 두 태블릿에서 동시에 작업할 때 안전한가 (2026-09-10)

⚠️ 재저장본 — 원본 `/tmp/report.md`(v5_1) 은 같은 날 v5_3 설계 보고가 같은 경로에 덮어써 파일이 사라졐다. 이 파일은 그때 보고한 본문을 대화 기록에서 그대로 다시 쓴 것이다(내용 추가 없음 · 2026-09-10 저장).

**1차 판.** 시점: `255d68b feat(inv-doc-cost)` · `git diff --stat` = 변경 0 (untracked: `20260910152545_inv_doc_cost_table_only.sql` 하나).
읽기 전용 조사 — 코드 수정·커밋·psql 실행 없음. 줄 번호는 이 시점 파일 기준.

---

## 요약 (결론 먼저)

| 화면 | 같은 사람 두 태블릿 | 수량이 틀어지는가 | 근거 |
|---|---|---|---|
| **admin LIVE NOW** | 같은 줄이 **두 번** 뜬다 — 연결 기준(중복 제거 없음) | 표시 문제만 | §1 |
| **리시빙** | 열 수 있다(점유 없음). **같은 라인**을 양쪽에서 만지면 **나중 저장이 이긴다**(절대값 PATCH · CAS 없음). 다른 라인은 안전. 완료는 전체 덮어쓰기 안 함 | ⚠️ **같은 라인에서만** 유실 가능 — 두 사람일 때와 같은 위험. 같은 사람이라 더 나빠지지 않는다 | §2 |
| **픽·팩** | 같은 사람은 `ensureMine`·RPC CAS 를 **통과**한다(이름 비교). 두 화면이 나란히 스캔 가능 | ⚠️⚠️ **완료·Hold RPC 가 그 화면의 로컬 스냅샷으로 전 라인을 덮어쓴다** — 다른 화면이 스캔한 라인이 옛 값(0)으로 돌아가고 `short_pick` 이 잘못 기록된다. **두 사람은 막히고 같은 사람만 뚫리는 구멍** | §3 |

⭐ **실해 여부는 미확정** — 이 보고는 코드 판독이다. §4 의 SQL 로 흔적을 확인해야 「이론상 위험」에서 「일어났다」로 넘어간다.
[후속 실측 2026-09-10 · Caleb] ①-1(스캔 흔적 있는데 `verification_method` null) = **0건** ⇒ 픽 실해 없음. 트랜스퍼에서 한 사람이 두 기기에 로그인한 사실은 확인됨.

---

## 1. LIVE NOW 는 무엇을 세는가 — **연결(presence 메타) 기준 · 중복 제거 없음**

### 만드는 코드
- **admin** `admin.html:773~786` — `sb.channel("wms-presence",{presence:{key:"admin|"+me.name}})` 구독 · `sync` 마다 `presenceState()` 전체를 받아 `liveList()` 가 **키별 배열의 원소를 전부 펼친다**:
  ```js
  Object.keys(presence).forEach(k=>{ if(k.startsWith("admin|")) return;
    (presence[k]||[]).forEach(m=>{ if(m&&m.name) out.push(m); }); });
  ```
  `renderLiveStrip()`(812행)은 그 배열을 그대로 칩으로 그린다. **이름·문서로 묶는 코드가 없다.**
- **참여 쪽 키**: receiver `me.name+"|receiver:"+receipt.id` (`receiver.html:456`) · picker `me.name+"|picker"` (`picker.html:304`) · packer `me.name+"|packer"` (`packer.html:331`) · fulfillment `me.name+"|fulfillment"` (`fulfillment.html:407`).
- receiver 자신의 「also here」(`receiver.html:482~500`)는 **자기 키를 제외**하고 이름을 `Set` 으로 중복 제거한다 — 같은 사람이 두 태블릿을 열어도 **작업자 화면에는 자기 자신이 안 보인다.** admin 만 두 줄을 본다.

### 사람 기준인가 연결 기준인가 → **연결 기준**
Supabase(Phoenix) presence 는 **같은 키로 두 연결이 track 하면 그 키 아래 메타가 두 개**다. admin 은 메타를 펼치므로 **같은 사람·같은 receipt 가 두 탭/두 태블릿이면 정확히 「같은 줄 두 번」**이 된다. 실측(`Jan Ko · Transfer · receiving · TR-04330` ×2)과 모양이 일치한다 — 두 연결 모두 `stage:"receiving"` 이었다는 점까지.

### 닫으면 즉시 빠지는가
- **정상 이탈**은 즉시: `presenceLeave()` 가 `untrack()`+`removeChannel()` (receiver 478행 · `exitToList` 1569행).
- **비정상 이탈**(화면 꺼짐·앱 킬·와이파이 끊김)은 클라이언트가 untrack 을 못 부르므로 **서버가 소켓 끊김/하트비트 실패를 감지할 때까지** 메타가 남는다. ⚠️ **그 시간은 코드에 없다** — supabase-js CDN `@2`(버전 고정 없음 · `receiver.html:357`) 기본 하트비트와 Realtime 서버 타임아웃에 좌우된다. **확인 못 함.** (추측: 수십 초~1분대. 근거 없음.)
- ⇒ 「같은 줄 두 번」은 **(a) 실제 두 연결** 또는 **(b) 옛 연결 + 새 연결(재접속 직후)** 둘 다 가능. 가르는 방법: §4-A 세 번째 SQL — 같은 worker 가 같은 receipt 에 **짧은 간격으로 같은 stage 전환을 두 번** 남겼으면 (a)다(전환은 화면당 1행 insert · `receiver.html:1672`).

### 중복 제거를 안 하는 것은 의도인가 누락인가
「연결 수를 보이려 한다」는 의도가 코드·주석 어디에도 없다. 헤딩은 "screens open this second"(`admin.html:173`) — **화면 수로 읽으면 두 줄이 맞고, 사람 수로 읽으면 누락.** 판단은 Caleb 몫. 부수 영향: `liveBatchSet()`(787행)은 `Set` 이라 픽·팩 배치 판정에는 중복이 무해.

---

## 2. 리시빙 — 같은 사람 두 태블릿이면 수량이 어긋나는가

### 2-a. 진입: 막는 것이 없다 (설계)
`startPo()` (`receiver.html:707~727`)는 그 PO 의 receipt 가 열려 있으면 **누구든** `resumeReceipt → openReceipt` 로 들어간다. 점유·「내가 이미 열었다」 검사 없음. 같은 사람 두 태블릿 = 두 사람과 구조가 같다.

### 2-b. 로컬 배열은 화면마다 따로 · 서로 동기화되지 않는다
- `openReceipt()` (774~817행)가 서버 라인을 읽어 **그 화면의 `lines`** 를 만든다. `unconfirmed`·`writeChain` 도 화면별(381~382행).
- **다른 화면의 변경을 받는 경로가 없다** — `postgres_changes` 구독 0건(grep) · 폴링 없음(규칙 22). 서버 값을 다시 읽는 곳은 ① 수동 입력 직전 `serverLineQty()` (1126행) ② 완료 직전 `serverChecks()→mergeServerRows()` (1932·1959행) 둘뿐.
- ⇒ A 가 스캔해도 **B 화면은 완료 버튼 전까지 옛 수량**을 보여준다.

### 2-c. ⚠️⚠️ 같은 라인을 양쪽에서 만지면 — **나중에 보낸 쪽이 이긴다 (lost update)**
- 스캔(`processScan` 1197행)·스테퍼(`manualAdjust` 1350행)는 **로컬 `l.received` 증감** 뒤 `saveLine → queueWrite → writeLine` 으로 **절대값**을 보낸다: `patchFor()` (1378행) `p.received_base=l.received` · `writeLine()` (1418행) `.update(patch).eq("id",l.id).select("id")`. **필터는 id 하나** — 주석이 「CAS 조건이 붙는 다음 단계」라고 적어 아직 CAS 가 없음을 확인(1426~1427행).
- 시나리오: 라인 X 서버 0. A 스캔 3 → 서버 3. B(화면 0) 스캔 1 → `received=1` 전송 → **서버 1. A 의 3 이 사라진다.** B 는 1행 반영으로 성공 판정 — 재시도 없음. **조용한 유실.**
- `writeChain`(1436행)은 **같은 화면 안** 같은 라인의 PATCH 추월만 막는다. 화면 간에는 무력.
- **수동 입력만** 예외: `manualSet()` (1162행)이 `serverLineQty()` 로 서버 값을 읽어 프롬프트 열 때 값과 다르면 `askQtyConflict` 모달. ⚠️ 후보 `othersLabel()` = **자기 키를 제외한 presence** 라 같은 사람 두 태블릿이면 **후보가 비어 "Changed by another receiver."** — 사실은 자기 다른 태블릿인데 알 길이 없다.
- **다른 라인**은 안전: 라인 단위 PATCH 라 A 가 만진 라인을 B 의 저장이 건드리지 않는다(2026-08 「전체 배열 덮어쓰기 제거」 · 1547~1548행 주석).
- ⭐ **이 위험은 두 사람일 때와 정확히 같다.** 같은 사람이라 더 나빠지는 것은 conflict 모달의 후보가 비는 것뿐.

### 2-d. 큐: 「대기하지 않는다」의 실체
`saveLine` 은 `queueWrite` 결과를 기다리지 않고 즉시 렌더(1483~1500행). 큐는 **화면별·라인별 Promise 체인**이라 두 화면이 각자 큐를 들고 있으면 **서버 도착 순서 = 이기는 순서**. 백로그가 밀린 화면의 옛 값이 늦게 도착해 새 값을 덮을 수 있다 — `last_qty_at` 은 터치 시각을 싣지만 서버는 그 시각을 비교하지 않는다(단순 UPDATE).

### 2-e. 오프-PO 스캔 — **같은 SKU 라인이 둘 생길 수 있다**
`offPoScan()` (1227행)은 기존 오프-PO 라인 존재를 **로컬 `lines`(bcMap)만** 보고 insert 한다. `wms_receipt_lines` 에 (receipt_id, order_sku) 유니크 없음(baseline 610~630행). 완료 요약 `unknown`(1955행)이 "added by someone else" 로 알려주긴 한다.

### 2-f. 완료(`finishReceipt`)를 양쪽에서 누르면
- **전체 덮어쓰기 없음**: `flushUnconfirmed()` 는 `unconfirmed` 잔여만 다시 쓴다(1458행) — 정상이면 비어 있다. ⭐ 안전.
- `completed`: `.update({status,completed_at}).eq("id")` — **status 조건 없음(의도 · 2034~2036행 주석)**. 두 번 눌러도 같은 값 두 번. 무해.
- `partial`: `wms_pause_receipt` RPC **CAS(in_progress 만)**. 안전. Apply(EF): `apply_lock_at` 조건부 PATCH 잠금 + `applied_at` 재확인(`receiving/index.ts:1001~1043`). 안전.
- ⚠️ **완료 뒤 다른 태블릿이 계속 스캔하면**: `openReceipt` 는 completed 를 막지 않고(applied/externally_applied 만 · 777·781행) 이미 열린 화면은 검사가 없다 — 수량 PATCH 가 **그대로 들어간다**(`ensureReceiptOpen` 은 풋어웨이 쓰기에서만 · `applied_at` 만 봄 · 1507행). Apply 는 Apply 시점의 DB 를 읽는다.

### 2-g. 축 컬럼·전환 이력
- `last_qty_at/by`·`last_putaway_at/by`: 두 화면이 **같은 이름**을 쓰므로 by 로는 화면을 못 가른다. 라인 변경 이력 표 없음(grep 0건) — 마지막 값만 남는다.
- `wms_receipt_stage_events`: 화면마다 전환 때 1행(1672행) — 두 태블릿이면 **같은 worker 의 전환 행이 두 배**. ⭐ 두 태블릿 사용을 사후에 증명하는 유일한 서버 기록.

---

## 3. 픽·팩 — 같은 사람에게는 방어가 작동하지 않는다

### 3-a. 진입
`resumeBatch()` (`picker.html:744~756`) 조건은 `status==="in_progress" && assigned_to===me.name` — 두 번째 태블릿의 「My In Progress」에도 같은 배치가 뜨고 **그대로 열린다**. packer `resumePack` 동형.

### 3-b. `ensureMine`·`freezeScreen` 은 이름 비교 → **같은 사람 통과**
`checkOwner()` (`picker.html:333~352`, `packer.html:352~370`): `who===me.name ? {s:"ok"} : {s:"lost"}`. 두 태블릿 모두 자기 이름이라 **둘 다 ok** — 프리즈 없음.

### 3-c. 스캔 저장 — 절대값 · 화면별 bcMap · 같은 라인은 lost update
`saveLine()` (`picker.html:1334~1347`) `update({picked_base:l.picked,...}).eq("id",l.id)`. 같은 라인을 두 화면이 스캔하면 **한쪽 스캔이 사라진다**(이중 가산이 아니라 **유실**). packer `saveLine` (`packer.html:1296~1305`) 동형(`verified_base`).

### 3-d. ⚠️⚠️ 완료·Hold RPC 가 **전 라인을 로컬 스냅샷으로 덮어쓴다** — 핵심 위험
- picker `finish()` payload (`picker.html:1400~1408`): `p_lines: lines.map(...)` — **화면의 전 라인**.
- `wms_complete_pick` (`20260806160000_wms_complete_pick_rpc.sql:125~137`): `update wms_pick_task_lines set picked_base=r.pb ...` — 받은 값을 **그대로** 쓴다. CAS 는 task 행에만(`assigned_to = v_worker and status='in_progress'` · 94행) — **같은 사람이면 통과.**
- 시나리오: 같은 사람 A·B 태블릿, 같은 배치. B 가 라인 5~9 스캔. A 화면은 5~9 가 0. A 가 Done → RPC 가 5~9 를 **0 으로 되돌리고** `p_disc` 로 **`wms_discrepancies(short_pick)` 가 잘못 생성**된다.
- packer 도 같다: `wms_complete_pack`·`wms_hold_pack` 둘 다 `p_lines` 전량 덮어쓰기(`20260825193231_preserve_verification_method.sql:91~110 · 213~227`).
- ⭐ **두 사람**이면 이 경로가 막힌다(이어받기로 `assigned_to` 가 바뀌어 CAS 0행). **같은 사람 두 태블릿은 이 방어를 전부 통과하는 유일한 경우다.**

### 3-e. 이중 가산?
없다. 세 화면 모두 로컬 증감 → 절대값 전송이라 **가산이 아니라 유실**로 나타난다.

---

## 4. 실해 확인 SQL (제시만 · Caleb 실행)
(별도 메시지로 제시했고 ①-1 실측 0건. 핵심 지문: `wms_pick_task_lines.picked_at is not null and verification_method is null` — 정상 경로로는 생기지 않는 조합 · 완료 RPC 가 `verification_method = r.vm` 으로 덮고 `picked_at` 은 안 건드린다.)

---

## 5. 막아야 하는가 — 제안
| 화면 | 결론 |
|---|---|
| LIVE NOW | 표시만 — 「화면 수」인지 「사람·문서 ×N」인지 결정 후 |
| 리시빙 | 지금 구조가 두 사람 때와 같은 수준 — 막을 근거 약함. 고칠 것은 같은 라인 CAS(델타 재적용) · 오프-PO 서버 조회 · 완료 후 수량 쓰기 차단 |
| 픽·팩 | ⚠️⚠️ 막는 것이 맞다 — `session_id`(화면마다 랜덤)를 `assigned_to` 와 함께 쓰고 `checkOwner`·RPC CAS 가 비교. 새 기기가 이기고 옛 기기는 프리즈(지금 이어받기 UX). 경고만으로는 Done 한 번에 유실 |

## 확인 못 한 것
Realtime presence 비정상 이탈 후 잔존 시간 · TR-04330 이 실제 두 태블릿인지 · 픽 완료 RPC 후 `assigned_to` 잔존값 · `wms_discrepancies.reason` CHECK 어휘(후에 확인: `short_pick`·`short_after_pack`·`over_pick`·`resolved_pack_recovery`·`stock_short`·`pack_scan_mistake`).
