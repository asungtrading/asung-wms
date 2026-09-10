# 구현 보고(재적용) — 같은 사람 다중 기기 차단 · ① 픽·팩 (2026-09-10 · 2차 시도)

**1차 판.** 시작 시점 `6144b39` · `git diff --stat` 변경 0 · untracked 0 (152545 는 그 사이 커밋됨).
**작업 후** `git diff --stat`: **4 files changed, 133 insertions(+), 21 deletions(-)**
  `.claude/skills/asung-wms/SKILL.md` +9 · `packer.html` 52 · `picker.html` 67 · `wms-auth.js` +26
  새 파일(untracked): `supabase/migrations/20260910230704_session_guard_pick_pack.sql` (562줄) · `scripts/testdb/session_guard_check.sql` (217줄)
커밋·push·db push·functions deploy 전부 안 했다. diff 실물은 Caleb 이 뽑는다(규칙).
📌 v5_4(첫 구현 · 되돌림)를 **그대로 재적용**한 것이다 — 설계 재조사 없음. 차이는 마이그레이션 타임스탬프(162952 → **230704**)와
   claimSession 의 네트워크 실패 처리 명시(best-effort · 아래 §1)뿐.

## 0. 전제 재확인 (시작 시)
- 원장 13건 프로덕션 반영 · 실해 0건 — 프롬프트에 Caleb 확인으로 주어짐(이 세션은 재실행하지 않았다).
- ⚠️ **RPC 최신 정의 전수 grep 재확인** — `grep -ln "function public\.X"` 전 마이그레이션 + 4개 이름의 등장 파일 전부:
  `wms_complete_pick` → 20260806160000 · `wms_hold_pick` → 20260824192416 · `wms_complete_pack`/`wms_hold_pack` → 20260825193231.
  그 뒤 등장은 20260812100000(주석 「wms_complete_pack 패턴」) · 20260825183827(주석 「wms_hold_pick 과 같은 행」) — **재정의 아님**.
  로컬 DB pg_proc 시그니처도 v5_4 표와 동일(옛 6/3/6/2 인자). ⇒ **v5_4 가 그대로 유효.**

## 1. 무엇을 만들었나
| 파일 | 변경 |
|---|---|
| `supabase/migrations/20260910230704_session_guard_pick_pack.sql` | ① `session_id text` 컬럼 3표 + comment ② 옛 시그니처 4개 `drop function if exists` ③ RPC 4개 원문 통째 + (a)파라미터 (b)CAS 한 줄 (c)reason ④ revoke/grant 재설정(새 시그니처) |
| `wms-auth.js` | `wmsAuth.sessionId()` — `sessionStorage["wms_session_id"]` UUID · 없으면 생성 · 저장 불가면 메모리 폴백 · ⚠️「상태 vs 정체」 주석(CLAUDE.md localStorage 금지와의 구분) |
| `picker.html` | `SID` · 클레임 7곳 `session_id:SID` · `claimSession(kind,id)` 신설 + 재개 4경로(restoreFromUrl task · scanTakeover 내 것 · resumeBatch · resumeWave) · `checkOwner` select+`otherDevice` 분기 · `otherDeviceMsg`/`lostMsg` · payload 2곳 `p_session_id` · 0행 `reason==="other_device"` 전용 프리즈 2곳 |
| `packer.html` | 동형: 클레임 4곳 · `claimSessionPack` + `resumePack` in_progress(else) 분기 · checkOwner · 문구 · payload 2곳 · reason 2곳 |
| `.claude/skills/asung-wms/SKILL.md` | 규칙 28 끝에 「✅ 2026-09-10 — 같은 사람 · 다른 기기(탭) 차단」 소절 9줄(localStorage 구분 · drop 필수 · 되돌린 경위 포함). description 무접촉 → `check-skill-desc.sh` 통과 |
| `scripts/testdb/session_guard_check.sql` | 격자(§3) · `-v mig=<마이그레이션|/dev/null>` 로 적용 전/후 양쪽에서 실행 가능 |

**claimSession 의 네트워크 실패 = 통과(true)** — 규칙 28 best-effort 와 같은 방향. 이 탭은 열리되 서버 session_id 는 옛 화면 것이므로 완료·Hold 가 `other_device` 로 얼어붙고 Reload 가 다시 클레임한다 — **유실 없는 쪽으로 실패**한다. 0행(남이 가져감·풀림)만 false.

## 2. RPC — 원문 통째 복사 · diff 실물 (원문 → 새)
줄수: `wms_complete_pick +14/−3` · `wms_hold_pick +14/−3` · `wms_complete_pack +8/−2` · `wms_hold_pack +8/−2` — **목표치와 일치.**
교체된 원줄(`<`) 10개 = 마지막 파라미터 줄(콤마 추가) 4 + 0행 return 줄 6 · 그 외 원줄 변경 0.
마이그레이션 안의 함수 본문과 생성본 4개 `diff -q` 동일(추출 = `create or replace function public.X(` 부터 첫 `$$;` 까지).

### diff wms_complete_pick
```
7c7,8
<   p_short_delete  jsonb default '[]'      -- [{order_id, sku}] — 선언했지만 채움 (stale delete)
---
>   p_short_delete  jsonb default '[]',     -- [{order_id, sku}] — 선언했지만 채움 (stale delete)
>   p_session_id    text default null     -- 화면 세션 (2026-09-10 · 다중 기기 차단). null = 옛 클라이언트(배포 창) 호환 · 행의 session_id 가 null(배포 전 클레임)이면 통과
41a43
>        and (p_session_id is null or w.session_id is null or w.session_id = p_session_id)
44c46,50
<       return jsonb_build_object('completed', false, 'worker', v_worker);
---
>       return jsonb_build_object('completed', false, 'worker', v_worker,
>         'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
>                                 and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
>                                then 'other_device' end
>                      from wms_waves x where x.id = p_wave_id));
66a73
>        and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
69c76,80
<       return jsonb_build_object('completed', false, 'worker', v_worker);
---
>       return jsonb_build_object('completed', false, 'worker', v_worker,
>         'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
>                                 and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
>                                then 'other_device' end
>                      from wms_pick_tasks x where x.id = p_task_id));
```

### diff wms_hold_pick
```
4c4,5
<   p_wave_id bigint default null    -- wave 모드 (둘 중 정확히 하나)
---
>   p_wave_id bigint default null,   -- wave 모드 (둘 중 정확히 하나)
>   p_session_id    text default null     -- 화면 세션 (2026-09-10 · 다중 기기 차단). null = 옛 클라이언트(배포 창) 호환 · 행의 session_id 가 null(배포 전 클레임)이면 통과
33a35
>        and (p_session_id is null or w.session_id is null or w.session_id = p_session_id)
36c38,42
<       return jsonb_build_object('held', false, 'worker', v_worker);
---
>       return jsonb_build_object('held', false, 'worker', v_worker,
>         'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
>                                 and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
>                                then 'other_device' end
>                      from wms_waves x where x.id = p_wave_id));
58a65
>        and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
61c68,72
<       return jsonb_build_object('held', false, 'worker', v_worker);
---
>       return jsonb_build_object('held', false, 'worker', v_worker,
>         'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
>                                 and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
>                                then 'other_device' end
>                      from wms_pick_tasks x where x.id = p_task_id));
```

### diff wms_complete_pack
```
7c7,8
<   p_recovered     jsonb default '[]'      -- ["sku"] — 팩에서 회복 → short_pick 을 resolved_pack_recovery 로
---
>   p_recovered     jsonb default '[]',     -- ["sku"] — 팩에서 회복 → short_pick 을 resolved_pack_recovery 로
>   p_session_id    text default null     -- 화면 세션 (2026-09-10 · 다중 기기 차단). null = 옛 클라이언트(배포 창) 호환 · 행의 session_id 가 null(배포 전 클레임)이면 통과
53a55
>      and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
57c59,63
<     return jsonb_build_object('completed', false, 'worker', v_worker);
---
>     return jsonb_build_object('completed', false, 'worker', v_worker,
>         'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
>                                 and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
>                                then 'other_device' end
>                      from wms_pack_tasks x where x.id = p_task_id));
```

### diff wms_hold_pack
```
3c3,4
<   p_lines   jsonb                  -- [{id, verified_base, status('verified'|'in_progress'|'pending'), verification_method|null}]
---
>   p_lines   jsonb,                 -- [{id, verified_base, status('verified'|'in_progress'|'pending'), verification_method|null}]
>   p_session_id    text default null     -- 화면 세션 (2026-09-10 · 다중 기기 차단). null = 옛 클라이언트(배포 창) 호환 · 행의 session_id 가 null(배포 전 클레임)이면 통과
23a25
>      and (p_session_id is null or t.session_id is null or t.session_id = p_session_id)
26c28,32
<     return jsonb_build_object('held', false, 'worker', v_worker);
---
>     return jsonb_build_object('held', false, 'worker', v_worker,
>         'reason', (select case when x.assigned_to = v_worker and x.status = 'in_progress'
>                                 and x.session_id is not null and p_session_id is not null and x.session_id <> p_session_id
>                                then 'other_device' end
>                      from wms_pack_tasks x where x.id = p_task_id));
```

## 3. 검증 — 로컬 DB · 트랜잭션 안 적용 → 격자 → ROLLBACK (전부 통과 · DB 무변 재확인)
실행: `psql <local> -v mig=supabase/migrations/20260910230704_session_guard_pick_pack.sql -f scripts/testdb/session_guard_check.sql`
| # | 케이스 | 기대 | 실측 |
|---|---|---|---|
| 0 | 오버로드 | 이름당 pg_proc 정의 1 · identity args 끝 `p_session_id text` · authenticated t / anon f | 4개 모두 일치 |
| 1 | 픽 완료 T1 **생략**(옛 HTML) / T2 S1=S1 / T3 S1≠S2 / T4 null·S2 / T5 남 | completed·completed·`false+other_device`(라인 3/0·disc 0·in_progress 무변)·completed·`false+reason null` | 일치 · 집계 disc +3 · picked +30 |
| 2 | 픽 Hold T6 생략 / T7 불일치 / T8 레거시 / T9 남 | held·other_device(라인 무변·holds 0)·held·null | 일치 (T6·T8 pending+held_by+holds 2) |
| 3 | wave W1 행 S1(멤버 null) · p S2 → p S1 | 0행 other_device·멤버 2 in_progress 무변 → completed·members_completed 2 | 일치 |
| 4 | 팩 완료 P1 생략 / P2 / P3 불일치 / P4 레거시 / P5 남 | completed·completed·other_device(verified 4 무변·in_progress)·completed·null | 일치 |
| 5 | 팩 Hold P6 생략 / P7 불일치 / P8 레거시 | held·other_device·held | 일치 |
| 6 | T3 를 새 화면 S2 가 클레임(UPDATE 1행) → p S2 완료 · 옛 화면 S1 Hold | completed · 0행 reason null(completed 라 other_device 아님) | 일치 |
**회귀**: 기존 `supabase/tests/` 5개를 새 마이그레이션 위에서(같은 트랜잭션 · rollback) 실행 — `wms_complete_pick_test` 12 · `wms_hold_pick_test` 17 · `wms_complete_pack_test` 10 · `wms_hold_pack_test` 10 · `wms_auto_hold_test` 7 **전부 PASSED**(옛 arity 호출 = `default null` 호환 증명).
⚠️ psql 은 postgres 역할이라 RLS 회귀는 보지 않는다(정책 무변). PostgREST 오버로드 모호성은 psql 로 재현 불가 — pg_proc 1개가 대리 증거.
⚠️ 로컬 DB 는 20260909235347 까지만 적용된 상태(132601·141553·152545 미적용)였다 — 이 마이그레이션은 WMS 표만 건드려 무관. `supabase db reset` 은 실행하지 않았다(명령만 §5).

## 4. 클레임 경로 전수 — grep 근거
```
grep -n "assigned_to:me.name" picker.html packer.html | grep -v "session_id:SID"   → 0줄 (11곳 전부 동봉)
grep -c "session_id:SID" picker.html → 9 (클레임 7 + claimSession 내부 2)   packer.html → 5 (클레임 4 + claimSessionPack 1)
claimSession 호출: picker 438(restoreFromUrl task) · 691(scanTakeover 내 것) · 787(resumeBatch) · 996(resumeWave — restoreFromUrl wave 수렴)
claimSessionPack 호출: packer 738(resumePack in_progress 분기 — scanTakeoverPack 내 것·restoreFromUrl·takeoverPack 수렴점)
p_session_id payload: picker 1439·1586 · packer 1396·1534   reason 분기: picker 1464·1601 · packer 1425·1549
```
문법: `node --check` wms-auth.js · picker/packer `<script>` 추출 전부 OK.

## 5. 배포 순서 (Caleb 실행 · 제시만) — ⚠️ DB → HTML 절대
```bash
# 0) 로컬 전체 재생(선택)
supabase db reset && psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v mig=/dev/null -f scripts/testdb/session_guard_check.sql && supabase stop
# 1) 테스트 DB (Asung-IMS) — ⚠️ 그 파일 경로가 보이면 테스트
supabase db push --db-url "$(cat ~/.asung-testdb-url)"
# 2) 운영 (asung-WMS) — 미적용이 이 1건뿐인지 먼저 확인
supabase migration list --linked
supabase db push --linked
# 3) 그 다음에만 HTML/JS push (GitHub Pages) — 옛 HTML 은 default null 로 종전 동작 · 새 HTML 이 옛 RPC 를 만나면 400
```

## 6. 남은 것
- 현장 미검증: 두 기기로 같은 배치 → 옛 기기 프리즈 문구 · Reload 되찾기 · sessionStorage 가 하드 리로드에 유지되는지(설계 근거는 브라우저 사양).
- 하루 관찰 후 ② 리시빙(`wms_receipt_sessions`) · 별건 LIVE NOW ×2 · 리시빙 같은 라인 CAS.
- 부수: `supabase migration new` 는 stdin 이 파이프면 **입력을 기다리며 멈춘다**(비대화식 셸) — 빈 파일은 만들어지므로 그 파일에 직접 썼다.
