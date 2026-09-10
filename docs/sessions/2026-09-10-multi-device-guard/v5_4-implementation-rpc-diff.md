# 구현 보고 — 같은 사람 다중 기기 차단 · ① 픽·팩 (2026-09-10)

**1차 판.** 시작 시점 `255d68b` · `git diff --stat` 변경 0 (untracked: `20260910152545_inv_doc_cost_table_only.sql`).
**작업 후** `git diff --stat`: 4 files changed, 104 insertions(+), 22 deletions(-)
  .claude/skills/asung-wms/SKILL.md | +10 · packer.html | +41/−? (41 줄 변화) · picker.html | 59 · wms-auth.js | +16
  새 파일(untracked): supabase/migrations/20260910162952_session_guard_pick_pack.sql (553줄) · scripts/testdb/session_guard_check.sql (145줄)
커밋·push·db push·functions deploy 전부 안 했다. 로컬 `supabase db reset` 도 실행하지 않았다(명령만 아래) — 검증은 로컬 DB 에
마이그레이션을 **트랜잭션 안에서 적용 → 격자 → ROLLBACK** 으로 했다(DB 무변). diff 실물은 Caleb 이 뽑는다(규칙).

## 1. 무엇을 만들었나

| 파일 | 변경 |
|---|---|
| `supabase/migrations/20260910162952_session_guard_pick_pack.sql` | ① `session_id text` 컬럼 3표(pick_tasks·waves·pack_tasks · nullable · comment) ② 옛 시그니처 4개 `drop function if exists` ③ RPC 4개 원문 전문 + (a)(b)(c) ④ revoke/grant 재설정(새 시그니처 · authenticated, service_role) |
| `wms-auth.js` | `wmsAuth.sessionId()` — `sessionStorage["wms_session_id"]` UUID · 없으면 생성 · 저장 불가면 메모리 폴백. 주석에 「상태 vs 정체」 |
| `picker.html` | `SID` 초기화 · 클레임 7곳 `session_id:SID` 동봉 · `claimSession(kind,id)` 신설 + 재개 4곳 호출(resumeBatch · restoreFromUrl task · resumeWave · scanTakeover 「내 것」) · `checkOwner` select+`otherDevice` 분기 · `otherDeviceMsg`/`lostMsg` · RPC payload 2곳 `p_session_id` · CAS 0행 `reason==="other_device"` → 전용 프리즈(finish·hold) |
| `packer.html` | 동형: 클레임 4곳 · `claimSessionPack` + `resumePack` in_progress 분기(scanTakeoverPack 내 것·restoreFromUrl·takeoverPack 이 전부 여기로 수렴) · checkOwner · 문구 · payload 2곳 · reason 분기 2곳 |
| `.claude/skills/asung-wms/SKILL.md` | 규칙 28 끝에 「✅ 2026-09-10 — 같은 사람 · 다른 기기(탭) 차단」 소절(10줄) — sessionStorage 와 localStorage 금지의 구분 포함. description 무접촉(hook 통과) |
| `scripts/testdb/session_guard_check.sql` | 격자 검증 파일(아래 §3) |

## 2. ⚠️⚠️ RPC — 원문 전수 grep · 통째 복사 · diff 실물

최신 정의(전수 grep · `grep -ln "function public.X"` 전 파일):
  wms_complete_pick → 20260806160000 (이후 재정의 없음 · 20260821201104:17 「무접촉」 명시)
  wms_hold_pick     → 20260824192416 (20260807000000 을 덮음)
  wms_complete_pack → 20260825193231 (20260806150000 → 20260821201104 → 이것)
  wms_hold_pack     → 20260825193231 (20260807000000 → 20260824192416 → 이것)
추출 = `create or replace function public.X(` 줄부터 첫 `$$;` 까지 스크립트로(자르지 않음 · complete_pick 146줄 · hold_pick 97 · complete_pack 156 · hold_pack 57).

diff(원문 → 새 본문) 줄수: complete_pick +14/−3 · hold_pick +14/−3 · complete_pack +8/−2 · hold_pack +8/−2.
교체된 원줄(`<`) 10개 전부 = 「마지막 파라미터 줄(콤마 추가)」 4 + 「0행 return 줄」 6 — 그 외 원줄 변경 0. 허용 차이 4종 안이다.

### diff wms_complete_pick (원문 → 새)
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
### diff wms_hold_pick (원문 → 새)
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
### diff wms_complete_pack (원문 → 새)
```
7c7,8
<   p_recovered     jsonb default '[]'      -- ["sku"] — 팩에서 회복 → short_pick 을 resolved_pack_recovery 로
---
>   p_recovered     jsonb default '[]',    -- ["sku"] — 팩에서 회복 → short_pick 을 resolved_pack_recovery 로
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
### diff wms_hold_pack (원문 → 새)
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

## 3. 검증 — 로컬 트랜잭션 격자 (scripts/testdb/session_guard_check.sql · 전부 기대와 일치 · ROLLBACK)

| # | 케이스 | 기대 | 실측 |
|---|---|---|---|
| 0 | 오버로드 | 이름당 정의 1개 · args 끝 `p_session_id text` | 4개 모두 defs=1 · 새 시그니처 |
| 0 | ACL | authenticated 실행 가능 · anon 불가 | 4개 모두 auth t · anon f |
| 1 | 픽 완료 T1 **p_session_id 생략(옛 HTML · DB 만 먼저 나간 배포 창)** | 종전 동작: completed · 라인 A=10 B=3 · short_pick 1 | 일치 |
| 1 | T2 행 S1 · p S1 | completed | 일치 |
| 1 | T3 행 S1 · p S2 (다른 기기) | completed:false · reason other_device · 라인 무변(3·0) · short_pick 0 · status in_progress | 일치 |
| 1 | T4 행 null(배포 전 클레임) · p S2 | completed (레거시 통과) | 일치 |
| 1 | T5 assigned_to 남 · p S1 | completed:false · reason null (종전 분기) | 일치 |
| 1 | 집계 | 성공 3건 → discrepancy +3 · picked_base +30 (10 씩) | +3 · +30 |
| 2 | 픽 Hold T6 생략 / T7 불일치 / T8 레거시 / T9 남 | held·other_device·held·null | 일치 (T6·T8 pending + held_by + holds 1 / T7·T9 in_progress · holds 0) |
| 3 | wave W1 행 S1 · p S2 | 0행 other_device · 멤버 2 in_progress 무변 | 일치 |
| 3 | W1 p S1 | completed · members_completed 2 | 일치 |
| 4 | 팩 완료 P1 생략 / P2 일치 / P3 불일치 / P4 레거시 / P5 남 | completed·completed·other_device(verified 4 무변)·completed·null | 일치 |
| 5 | 팩 Hold P6 생략 / P7 불일치 / P8 레거시 | held·other_device·held | 일치 |
| 6 | T3 를 새 화면 S2 가 클레임(UPDATE session_id='S2') 후 p S2 로 완료 | completed | 일치 — 「새 화면이 이긴다」 흐름 |

⚠️ 검증 방식 주의: `security invoker` + `auth.email()` 이라 psql 에서 `set_config('request.jwt.claims', …)` 로 신원을 흘렸다(auth.email 정의 확인 후). RLS 는 postgres 역할이라 안 걸린다 — RLS 회귀는 이 파일이 보지 않는다(정책 무변이라 영향 없음).
⚠️ PostgREST 의 오버로드 모호성은 psql 로 재현할 수 없다 — pg_proc 정의 1개가 대리 증거다.

## 4. 클레임 경로 전수 — grep 근거 (「한 곳이라도 빠지면 그 경로만 조용히 뚫린다」)
```
grep -n "assigned_to:me.name" picker.html packer.html | grep -v "session_id:SID"   → (0줄)  = 11곳 전부 동봉
grep -c "session_id:SID" picker.html → 9 (클레임 7 + claimSession 내부 UPDATE 2)   packer.html → 5 (클레임 4 + claimSessionPack 1)
claimSession 호출: picker 433(restoreFromUrl task) · 686(scanTakeover 내 것) · 778(resumeBatch) · 987(resumeWave)
claimSessionPack 호출: packer 719(resumePack in_progress 분기 — scanTakeoverPack·restoreFromUrl·takeoverPack 수렴점)
```
picker `restoreFromUrl` 의 wave 분기는 `resumeWave` 를 재사용하므로 987 로 덮인다. picker `startWave`(929 wave 행 · 935 멤버) · `takeoverWave`(975 · 983 멤버) 에도 동봉 — 멤버는 CAS 가 안 보지만 같은 UPDATE 라 비용 0.

## 5. 문법·정합
- `node --check`: wms-auth.js OK · picker/packer `<script>` 블록 추출 OK.
- `scripts/check-skill-desc.sh` 통과(description 무접촉).
- 레거시: 배포 전 in_progress 배치는 `session_id null` → checkOwner·RPC 모두 통과. 다음 클레임/재개에서 채워진다.
- 릴리스(Hold·자동 Hold·admin 롤백)에서 session_id 를 지우지 않는다 — 모든 클레임이 덮어쓴다(설계 §1-b).

## 6. 배포 순서 (Caleb 실행 · 제시만) — ⚠️ DB → HTML 절대 준수
```bash
# 0) 로컬 재생 검증(선택) — 전체 마이그레이션이 처음부터 재생되는지
supabase start && supabase db reset && \
  psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -v mig=/dev/null -f scripts/testdb/session_guard_check.sql && supabase stop
# 1) 테스트 DB 먼저 (Asung-IMS)  ⚠️ 그 파일 경로가 보이면 테스트
supabase db push --db-url "$(cat ~/.asung-testdb-url)"
# 2) 운영 (asung-WMS) — ⚠️ 미적용 마이그레이션이 전부 올라간다(132601·141553·152545·162952) — 의도한 것인지 먼저 supabase migration list --linked 로 확인
supabase migration list --linked
supabase db push --linked
# 3) 그 다음 HTML/JS push (GitHub Pages) — 옛 HTML 은 default null 로 종전 동작 · 새 HTML 이 옛 RPC 를 만나면 400
```
⚠️ 2) 에서 `20260910141553`(배분 블록 · 원가 레이어) 이 함께 올라간다 — 표만 올리려던 152545 의 취지와 어긋나면 141553 을 먼저 다루고 push 할 것(이 판단은 Caleb).

## 7. 남은 것 · 확인 못 한 것
- 현장 미검증: 두 기기로 같은 배치 열기 → 옛 기기 프리즈 문구 · Reload 되찾기.
- 2단계 리시빙(`wms_receipt_sessions`) · 별건: 리시빙 같은 라인 CAS · LIVE NOW 표시.
- 관찰 지표: `wms_pick_tasks.session_id` 채워지는 비율 · 프리즈 발생 시 `reason:'other_device'` 는 로그가 없다(응답만) — 필요하면 `wms_collect_runs` 류 기록은 다음 판단.
