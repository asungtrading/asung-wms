# 같은 사람 · 다중 기기 차단(세션 가드) — 설계 확정 · 구현·검증 완료 · 배포 불가로 되돌림 (2026-09-10)

> ✅ **완결 (2026-09-10 밤)** — 같은 날 밤 원장 13건이 올라간 뒤 **재적용 · 배포(`23df53a`) · 현장 검증 3종 통과**. 경위는 §10. 제목·파일명은 원 기록대로 둔다(되돌린 경위 §5 가 교훈이고, 이 파일명을 스킬·보고서 여러 곳이 링크한다).

관련: `asung-wms` 스킬 규칙 28(소유권 가드) · 백로그 「동시 작업 원자화」 보류 항목 · 보고서 3건(§8 · `docs/sessions/2026-09-10-multi-device-guard/`) ·
[실측] = 코드/DB 에서 읽은 값 · [Caleb 확정] = 다시 논의하지 않는 결정.
⚠️ **이 세션(낮)의 코드 변경은 0 이다** — 구현·검증까지 끝난 것을 파일 단위로 전부 되돌렸다(§5 · 그날 밤의 재적용은 §10). 이 문서는 **재개 시 이 문서 + 보고서 3건으로 프롬프트 한 번에 재현**되게 하려고 남긴다. 기록이 없으면 다음 세션은 이 작업이 있었다는 것 자체를 모른다.

---

## 1. 발견

[실측 2026-09-05 → 09-10 조사] admin Status 의 LIVE NOW 에 **같은 사람·같은 문서가 두 번** 떴다: `Jan Ko · Transfer · receiving · TR-04330` ×2.
⚠️ [Caleb 확인] 트랜스퍼에서 한 사람이 두 기기에 로그인한 것은 사실이다.

| 화면 | 같은 사람 두 기기 | 수량 위험 |
|---|---|---|
| **픽·팩** | `checkOwner` 가 `who===me.name` 이라 통과 → 두 화면이 나란히 스캔 | ⚠️⚠️ **완료·Hold RPC(`wms_complete_pick`·`wms_hold_pick`·`wms_complete_pack`·`wms_hold_pack`)가 그 화면의 로컬 스냅샷으로 전 라인을 덮어써** 다른 기기의 픽이 0 으로 돌아가고 `short_pick` 이 잘못 생긴다. **두 사람이면 CAS(`assigned_to = v_worker`)가 막는데 같은 사람만 뚫린다.** 📌 「Done 한 번」에 유실 — 경고로는 부족 |
| **리시빙** | 열 수 있다(점유 개념이 애초에 없다) | 같은 라인만 · 나중 저장이 이긴다(절대값 PATCH · CAS 없음) — **두 사람 때와 같은 수준**. 다른 라인·완료(unconfirmed 만 flush)는 안전 |
| **LIVE NOW** | 연결(presence 메타) 기준 · 중복 제거 없음 | 표시 문제만 — receiver 키가 `me.name|receiver:<receipt.id>` 라 같은 사람 두 연결 = 같은 키 아래 메타 2개 = 정확히 「같은 줄 두 번」 |

⚠️ **진짜 위험은 픽·팩이다.** 조사 정본 = 보고서 v5_1(§8).

## 2. ✅ 실해 0건 — 지문

```sql
-- 스캔 흔적은 있는데 최종 저장이 「안 만진 라인」 — 완료 스냅샷 덮어쓰기의 지문
select t.batch_label, t.assigned_to, t.completed_at, l.id, ol.order_sku, l.assigned_base, l.picked_base,
       l.verification_method, l.picked_at, l.picked_by
  from wms_pick_task_lines l
  join wms_pick_tasks t  on t.id = l.pick_task_id
  join wms_order_lines ol on ol.id = l.order_line_id
 where l.picked_at is not null and l.verification_method is null
 order by l.picked_at desc;                                   -- [실측 2026-09-10 · Caleb 실행] 0건
```
📌 **지문 논리**: 스캔(`saveLine`)은 항상 `verification_method` 를 찍고(`scanned_*`/`manual`), 완료·Hold RPC 만 그것을 `r.vm`(그 화면의 로컬값 · 안 만진 라인은 null)으로 덮는다. `picked_at`·`picked_by` 는 RPC 가 건드리지 않는다(`20260821201104:17` 「무접촉」). ⇒ 이 조합은 정상 경로로 생기지 않는다.
⚠️ `picked_at` 은 2026-08-21 부터 채워진다 — 그 전 사건은 이 방법으로 못 본다.
⚠️ **재개 시 이 쿼리를 다시 돌릴 것** — 그 사이 실해가 생겼을 수 있다. 팩은 RPC 가 vmethod 를 `coalesce` 로 보존하므로 같은 지문이 없다(`verified_at is not null and verified_base = 0` 이 후보 — 보고서 §4 ①-5).

## 3. [Caleb 확정] — ⚠️ 다시 논의하지 말 것

1. **막는다.**
2. ⭐ **새 기기가 이기고 옛 기기는 얼어붙는다.** 로그인 자체를 막지 않는다 — 태블릿 배터리가 꺼지거나 브라우저가 죽으면 로그아웃을 못 하고, 「이전 세션이 있으면 거부」로 만들면 풀어줄 수단이 또 필요하다. 지금 「남이 이어받았을 때」 프리즈와 같은 UX 라 작업자에게 익숙하다.
3. **범위 = 픽·팩 + 리시빙.** ⚠️ 리시빙의 **여러 사람 동시 작업은 계속 허용** — 같은 사람만 막는다(「한 사람은 한 기기」 규칙이 화면마다 다르면 작업자가 헷갈린다).
4. **순서 = 픽·팩 먼저 → 하루 관찰 → 리시빙.** 리시빙 같은 라인 CAS(델타 재적용) · LIVE NOW 표시는 **별건**.

## 4. 확정 설계 (판정 6개 요약 — 정본은 보고서 v5_3)

- **세션 식별 = `sessionStorage` UUID** (`wmsAuth.sessionId()` · 키 `wms_session_id`). 하드 리로드(Ctrl+Shift+R — 현장에서 흔한 조작)에 유지 · 탭·기기마다 다름 · 탭 닫으면 소멸. ⚠️ 메모리 변수는 새로고침이 「새 기기」로 오인돼 탈락 · `localStorage` 는 같은 기기 두 탭을 못 가름 · JWT `session_id` 클레임은 존재 미확인 + 두 탭 동일.
  ⚠️⚠️ **CLAUDE.md 「상태를 `localStorage` 에 두지 말 것」과 「상태 vs 정체」로 구분된다** — 그 규칙은 *작업 상태*(held_by 등) 이야기고, 이것은 이 화면의 *정체(identity)* 다. 상태(어느 화면이 잡고 있나)는 서버 컬럼에 둔다. **구현 시 스킬 규칙 28 에 이 구분을 반드시 적을 것** — 안 적으면 다음 사람이 규칙 위반으로 보고 되돌린다.
- **서버 저장**: 픽·팩은 `wms_pick_tasks`·`wms_waves`·`wms_pack_tasks` 에 `session_id text`(nullable · 릴리스에서 지우지 않는다 — 모든 클레임이 덮어쓴다) · 리시빙은 새 표 `wms_receipt_sessions` pk `(receipt_id, worker)` — 「여러 사람 허용·같은 사람은 하나」가 표 구조로 표현된다.
- ⭐ **작업 단위 잠금, 사람 단위 아님** — 유실은 같은 작업 행에서만 난다. admin+picker · 다른 배치 두 기기 · picker+receiver 병행은 허용(막을 필요 없는 것을 막으면 현장이 막힌다). 규칙 문장(세 화면 공통): **「한 작업(배치·wave·팩·receipt)은 한 화면에서만 열린다.」**
- **픽·팩 고칠 곳**: `assigned_to:me.name` 을 싣는 클레임 UPDATE/INSERT **11곳 전부**(picker 7 · packer 4 — `grep -n "assigned_to:me.name"` 이 근거) `session_id:SID` 동봉 + **종전에 읽기만 하던 재개 경로**(picker `resumeBatch`·`restoreFromUrl` task·`resumeWave`·`scanTakeover` 내 것 분기 · packer `resumePack` in_progress 분기)에 조건부 UPDATE + `.select()` 1행 판정 신설(「여는 순간 이 화면이 이긴다」) · `checkOwner` 에 `who===me.name && row.session_id && row.session_id!==SID → {s:"lost", otherDevice:true}` · 전용 문구 `otherDeviceMsg`(autoHoldMsg 계열 · Reload 가 이 탭으로 되찾는 대칭) · RPC payload `p_session_id: SID` · 0행 `reason==="other_device"` → 전용 프리즈. ⚠️ 한 곳이라도 빠지면 그 경로만 조용히 뚫린다(startWave 를 13일 놓친 전례).
- **리시빙(2단계)**: `openReceipt` 에서 `wms_receipt_sessions` upsert(진입 3경로가 수렴) · `ensureReceiptOpen` 을 세션 검사 + `completed` 닫힘으로 확장하고 수량 `saveLine` 에도 **비동기 사후 검사**(렌더 앞 await 금지) · 리시빙용 freezeScreen 신설 · `finishReceipt` 의 status 무조건은 의도라 유지(세션 검사만). `wms_receipt_stage_events` 는 가드 불가(사후 증거만).

## 5. ⚠️⚠️ 되돌린 이유 — 이 문서의 핵심

배포가 **DB → HTML** 순서여야 하는데(RPC 시그니처 변경 · 새 HTML 이 옛 RPC 를 만나면 400) **그 DB 를 올릴 수 없었다**:
```
supabase migration list --linked → 프로덕션 미적용 14건 · 그중 13건이 원장 inv_layer 계열   [실측 2026-09-10 · Caleb]
```
- ⚠️ `db push --linked` 는 미적용 전부를 올리므로 **WMS 것 하나만 올릴 수 없다.**
- ⚠️ **커밋만 해두면 다음 `git push` 에 화면(picker·packer·wms-auth)이 딸려 올라가** DB 없이 배포된다 → 새 HTML 이 `p_session_id` 를 보내는데 옛 RPC 는 그 인자를 모른다 → **픽·팩 완료·Hold 전면 실패.** ⇒ 커밋도 못 하고 되돌리는 쪽을 택했다.
- 📌 실해 0건이라 급하지 않았다 — **기다릴 수 있는 쪽**이었다. 원장 13건이 올라간 뒤 재개한다.
- 📌 **교훈**: 남의 모듈과 마이그레이션 큐(`supabase/migrations/`)를 공유하면, **내 배포 시점이 남의 준비 상태에 묶인다.** 시그니처가 바뀌는 RPC 처럼 DB→HTML 순서가 강제되는 변경은 큐가 비어 있을 때 넣어야 한다.

## 6. ⚠️ 재개 시 최대 위험 — RPC 시그니처 교체

`p_session_id` 를 더하면 시그니처가 바뀐다. **옛 시그니처를 drop 하지 않으면 오버로드 둘이 남아 PostgREST 가 모호성으로 거부** ⇒ 완료·Hold 전면 실패(작업자가 완료를 못 누른다).

| RPC | 최신 정의(전수 grep · 2026-09-10 시점) | 옛 시그니처(drop 대상) |
|---|---|---|
| `wms_complete_pick` | `20260806160000_wms_complete_pick_rpc.sql` (이후 재정의 없음) | `(jsonb, bigint, bigint, jsonb, jsonb, jsonb)` |
| `wms_hold_pick` | `20260824192416_task_holds.sql` | `(jsonb, bigint, bigint)` |
| `wms_complete_pack` | `20260825193231_preserve_verification_method.sql` | `(bigint, jsonb, jsonb, jsonb, jsonb, jsonb)` |
| `wms_hold_pack` | `20260825193231_preserve_verification_method.sql` | `(bigint, jsonb)` |

⚠️ 재개 시 **전수 grep 을 다시** 할 것 — 그 사이 재정의가 생겼을 수 있다.
- drop → 재생성 → revoke/grant(authenticated, service_role) 를 **한 마이그레이션 안에서**. drop 뒤 ACL 은 보존되지 않는다.
- 바꾸는 것 셋만: (a) 마지막 파라미터 `p_session_id text default null` (b) CAS where 에 `and (p_session_id is null or 행.session_id is null or 행.session_id = p_session_id)` 한 줄 (c) 0행 반환에 `'reason'`(같은 사람·in_progress 인데 세션만 다르면 `'other_device'`, 그 외 null). ⚠️ wave 멤버 UPDATE 에는 session 조건을 넣지 않는다(레거시 wave 「n of m matched」 예외 방지).
- ⚠️ **DB 만 나간 중간 창 호환**(옛 HTML 이 `p_session_id` 없이 호출 → `default null` 로 종전 동작)을 **fixture 로 증명.**
- 함수 원문은 자르지 말고 통째 복사 → diff 동일성 증명. 📌 **직전 구현의 목표치**: `wms_complete_pick +14/−3` · `wms_hold_pick +14/−3` · `wms_complete_pack +8/−2` · `wms_hold_pack +8/−2` — 교체된 원줄 10개가 전부 「마지막 파라미터 줄(콤마 추가) 4」+「0행 return 줄 6」이고 그 외 원줄 변경 0. diff 실물은 보고서 v5_4 §2 에 그대로 있다.
- 직전 검증 격자(v5_4 §3 · 전부 일치): 오버로드 정의 1개 · ACL · 생략 호출 회귀 · 일치 · 불일치(0행+reason · 라인/discrepancy 무변) · 레거시 null 통과 · 남의 배치(reason null) · wave · 팩 완료/Hold · 새 화면 클레임 뒤 완료.

## 7. 재개 절차

✅ **재개 완료 2026-09-10 밤 — 보고서 `docs/sessions/2026-09-10-multi-device-guard/v5_7-reapply-implementation.md`** (마이그레이션 `20260910230704` · 격자 전부 통과 · 회귀 5파일 통과 · 배포·현장 검증은 §10).

```
① 전제: 원장 마이그레이션 13건이 프로덕션에 올라갔는지 확인 — supabase migration list --linked 가 비어 있어야 한다
② 실해 재확인 — §2 쿼리 (0건이어야 한다 · 아니면 먼저 보정)
③ 이 문서 + 보고서 3건(§8 · `docs/sessions/2026-09-10-multi-device-guard/`)으로 구현 프롬프트 1회 — ⚠️ 설계는 확정(§3·§4), 다시 조사·논의하지 말 것.
   산출물 = 마이그레이션 1개(컬럼 3표 + RPC 4개 drop/재생성/ACL) · wms-auth.js sessionId() · picker/packer · 스킬 규칙 28 소절(localStorage 구분 포함) · scripts/testdb/session_guard_check.sql
④ 로컬 db reset + 격자 → 테스트 DB(Asung-IMS) db push → 프로덕션(asung-WMS) db push → 그 다음에만 HTML git push
```

## 8. 보고서 위치 — 레포 안 (2026-09-10 이동 · 집·회사 어느 PC 에서도 재개 가능)

```
docs/sessions/2026-09-10-multi-device-guard/v5_1-investigation.md            조사 (재저장본 — §9)
docs/sessions/2026-09-10-multi-device-guard/v5_3-design.md                   설계 정본 (판정 6개 · 근거 · 대안 기각)
docs/sessions/2026-09-10-multi-device-guard/v5_4-implementation-rpc-diff.md  구현 · RPC 4개 diff 실물 · 격자 결과 · 배포 순서
```
📌 이 문서와 같은 폴더(`docs/sessions/`)의 **하위 폴더**에 둔다 — 세션 산출물이라 `design/`(계약)·`probes/`(실측 원문)·`audits/` 어느 분류도 아니고, 세 파일이 이 세션 문서 하나에만 딸린 것이라 평면에 흩어두면 짝이 안 보인다. ~~`~/asung/reports/`~~ 는 회사 PC 에만 있어 옮겼다(원본 삭제 · 재부팅에 사라지는 `/tmp` 도 아니다).
⚠️ 보고서 본문 안의 `/tmp/report.md`·`/tmp/wms_v5_4.txt` 언급은 **당시 경로**다 — 지금은 위 파일이 정본.

## 9. 함께 기록 — 되돌리기 중 발견

- `supabase/migrations/20260910152545_inv_doc_cost_table_only.sql` 이 **커밋 전으로 로컬에만** 있다(원장 대화의 작업물 · `inv_doc_cost` 표만 운영에 올리기 위한 복제 파일). 되돌릴 때 이것을 건드리지 않는 것이 조건이었고 지켰다(`git status --short` 에 그 한 줄만 남음). ⇒ **원장 세션에 알릴 항목**: 이 파일이 아직 커밋되지 않았다.
- Claude Code 자기 정정: 조사 보고(v5_1)와 설계 보고(v5_3)를 **같은 `/tmp/report.md` 에 차례로 저장해 앞의 것이 사라졌다** — 대화 기록에서 같은 본문으로 재저장했다(재저장본 표기). 📌 **보고서를 같은 파일명에 쌓으면 앞의 것이 사라진다** — 판마다 파일명을 달리 할 것.
- 되돌리기는 `git checkout -- <파일>` 4개 + `rm` 2개, 파일 단위로만(`git checkout .`·`git clean` 미사용). 되돌린 뒤 `git diff --stat` 변경 0.

## 10. ✅ 완결 — 재적용 · 배포 · 현장 검증 (2026-09-10 밤)

§7 의 절차를 그대로 밟았다. 되돌린 이유(§5)가 해소된 것을 먼저 확인한 뒤에만 움직였다.

| 단계 | 내용 | 근거 |
|---|---|---|
| ① 전제 | `supabase migration list --linked` 미적용 0건(원장 13건 + 152545 전부 반영) · 실해 재확인 0건(§2 쿼리) | [실측 · Caleb] |
| ② 재구현 | v5_4 를 그대로 재적용 — RPC 최신 정의 전수 grep 재확인(재정의 없음) · 원문 통째 복사 · diff `+14/−3 · +14/−3 · +8/−2 · +8/−2` 목표치 일치 · 마이그레이션 **`20260910230704`**(새 타임스탬프) | 보고서 v5_7 §0·§2 |
| ③ 로컬 검증 | 격자 7케이스 통과(트랜잭션 안 적용 → 격자 → ROLLBACK) + 기존 `supabase/tests/` 5파일 회귀 통과(옛 arity = `default null` 호환 증명) | v5_7 §3 |
| ④ 배포 | DB → HTML 순서. 프로덕션 pg_proc 4줄 전부 `p_session_id text` — **오버로드 잔존 0**(§6 최대 위험 해소) · `session_id` 컬럼 3표 확인 · 커밋 `23df53a` push | [실측 · Caleb] |
| ⑤ 현장 검증 | ⭐ 3종 전부 통과 — ① 다른 탭이 열면 얼어붙음("another device that is signed in as you" 모달 실물) ② Reload 로 되찾으면 저쪽이 얼어붙음 — **대칭 성립**(§4 「새 것이 이긴다」) ③ 탭 하나만 열고 Ctrl+Shift+R → 아무 일 없음 — **오탐 없음 = sessionStorage 선택(§4 첫 항목)의 실증** | [실측 · Caleb] |

**남은 것(별도 항목 — 스킬 백로그 「동시 작업 원자화」에 같은 내용)**
- ⬜ 하루 관찰 — 작업자가 예상 밖으로 얼어붙는지. `other_device` 프리즈는 응답만 있고 서버 로그가 없으므로 청취로 확인한다.
- ⬜ 리시빙 2단계(`wms_receipt_sessions (receipt_id, worker)` · §4 마지막 항목) — 하루 관찰 뒤.
- ⬜ 별건: 리시빙 같은 라인 CAS(델타 재적용) · LIVE NOW 같은 사람 중복 표시(×2 배지 vs 화면 수 — v5_3 §6).

📌 **교훈 정리**: §5 의 「큐가 비어 있을 때 넣는다」는 그대로 유효하다 — 되돌린 낮과 재적용한 밤 사이의 유일한 차이는 큐가 비었다는 것이었고, 구현물은 v5_4 와 동일했다. 되돌림이 헛수고가 아니라 **배포 순서를 지킨 값**이었다.
