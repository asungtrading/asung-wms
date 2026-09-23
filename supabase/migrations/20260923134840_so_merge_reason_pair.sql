-- SO 모듈 마이그레이션 ⑤ — so_merge_reason_ck 빈틈 수정(양방향 짝) + 주석 둘 다시 내기 (2026-09-23 · 파일 시각 UTC)
--
-- 목표: 제약 1 다시 만들기(이름 그대로 so_merge_reason_ck · drop 뒤 add) · comment on column 2(so.merged_into_id · so.closed_reason) · ⭐ 행 0 · 표·칸 추가 없음.
-- 선행: 20260923133042_so.sql(표 넷 · ✅ 테스트 DB 적용 · 검증 (가)(나) 일치) — ⚠️ 그 파일은 고치지 않는다(적용됐다). 바뀐 것은 여기서 갈아 쓴다.
-- 정본: docs/design/so-module.md 8-b(병합 — 「어디로 합쳐졌나」 흔적이 남는 것이 void 와 다른 점) · §10(④·⑤ 함께 쓸 절 · 만든 뒤 신설).
--       지시서 ~/asung/prompts/so-mig-5-merge-reason.md · Caleb 판정 2026-09-23 · 검토 이견 없음.
--
-- ═══ 무엇이 틀렸나 (실측 2026-09-23 · Caleb · 테스트 DB) ═══
--   옛 식   check (merged_into_id is null or closed_reason = 'merged')                      (20260923133042 136행)
--   시험    draft 오더 SO-99999t 에 merged_into_id = SO-99998t 의 id → 막히지 않았다(HOLE)
--   원인    closed_reason 이 null 이면 closed_reason = 'merged' 는 null(모름) · false OR null = null · ⚠️ CHECK 는 null 을 통과시킨다
--           (④ 검증 (나) ② 의 병합 시험은 merged_into_id = id 라 so_self_ref_ck 가 대신 막아 빈틈이 가려졌다 — 시험마다 어기는 CHECK 가 하나뿐이어야 한다)
--   출처    so-mig-4 ⬜5 의 안(대화 Claude) — Claude Code 는 그대로 옮겼다
--
-- ═══ 판정 (✅ Caleb 2026-09-23) ═══
--   새 식   check ((merged_into_id is not null) = (closed_reason is not distinct from 'merged'))
--   근거    8-b — 병합이 void 와 다른 점은 「어디로 합쳐졌나」 흔적이 남는 것 · merged 인데 가리키는 곳이 없으면 그 흔적이 끊긴다 ⇒ 양방향 짝
--           다른 짝 CHECK(so_split_pair_ck · so_cancel_reason_ck · so_closed_at_ck)가 이미 양방향이고 양쪽이 null 이 될 수 없는 식(is null · is not null · NOT NULL 칸의 in)이다
--           is not distinct from 선례: 20260920163231_po_price_history.sql 71행(cur.code is not distinct from b.code)
--   대가    병합 RPC(다음 차수)는 merged_into_id · closed_reason='merged' · status='cancelled' · closed_at 을 한 문장에서 함께 넣는다
--           (짝 셋이 이어진다: merged_into_id ⇒ closed_reason=merged ⇒ status=cancelled(so_cancel_reason_ck) ⇒ closed_at(so_closed_at_ck))
--   ⭐ 규칙(정본 §10 · 스킬 함정 후보): CHECK 는 null 을 통과시킨다 — 짝 CHECK 는 = 양쪽이 null 이 될 수 없게(is null · is not null · is not distinct from) · 검증 시험은 한 번에 CHECK 하나만 어기게.
--   CHECK 전수 NULL 점검(스물셋 · ⑤ 회신 §3 표): 빈틈은 이것 하나 · 나머지 스물둘은 NOT NULL 칸의 식이거나 null 통과가 의도(할인 없음 · 티어 가격 없음 · 짝 CHECK 가 따로 막는 어휘 검사).
--
-- ⚠️ begin/commit 없음 — 적용은 psql -v ON_ERROR_STOP=1 -1 -f(한 트랜잭션) + supabase migration repair --status applied <이 파일 시각> (po-module §13-f) — 실행은 Caleb · [테스트 · Asung-IMS].
-- 행 0 이라 제약을 다시 만드는 비용은 없다. 이름은 그대로(검증 쿼리·주석·정본이 이 이름을 가리킨다).

-- ═══ ① 제약 — drop 뒤 같은 이름으로 양방향 ═══
alter table public.so
  drop constraint so_merge_reason_ck,
  add  constraint so_merge_reason_ck check ((merged_into_id is not null) = (closed_reason is not distinct from 'merged'));

-- ═══ ② 주석 둘 — 앞 문장 전문(20260923133042 192행 · 161행) + 바뀐 짝 문장 · 뺀 문장 없음 ═══
comment on column public.so.merged_into_id is '⭐ 병합으로 합쳐진 새 오더 → so(id) · 자기 참조 · nullable · on delete no action · 인덱스 so_merged_into_idx(8-b · 5-d 에 없던 칸 · 8-j) · 원본은 번호를 지킨 채 status=cancelled · closed_reason=merged 로 닫힌다 — ⭐ so_merge_reason_ck 양방향 짝 (merged_into_id is not null) = (closed_reason is not distinct from ''merged'')(⑤ 2026-09-23 · 옛 식 「merged_into_id is null or closed_reason = merged」는 closed_reason 이 null 이면 통과하는 빈틈이었다 — CHECK 는 null 을 통과시킨다 · merged 인데 가리키는 곳이 없으면 「어디로 합쳐졌나」 흔적이 끊긴다) · 릴리스 전에만(8-b) · void 와 다른 점: 흔적이 남는다 · ⚠️ so_family_members 는 이 축을 재귀에 섞지 않고 반환에 merged_into 칸 하나(8-j ⬜②)';

comment on column public.so.closed_reason is 'CHECK so_closed_reason_ck expired · superseded · voided · merged(6-a · 8-b) · ⚠️ fulfilled 는 없다(끝 상태 fulfilled 가 따로 있다 · 6-i) · cancelled 에만 선다 — so_cancel_reason_ck (status=cancelled) ⇔ (closed_reason not null) · expired 는 매일 도는 작업(5-g) · superseded 는 출하 확정이 닫는다(5-g) · merged 는 병합 원본(8-b) — ⭐ so_merge_reason_ck 양방향 짝: merged 이면 merged_into_id 가 있어야 하고, merged_into_id 가 있으면 merged 여야 한다(⑤ 2026-09-23 · 병합 RPC 는 두 칸과 status·closed_at 을 한 문장에서 함께 넣는다) · voided 그 밖은 ④(6-a ⬜)';

-- 검증(회신 · psql heredoc · begin…rollback · 번호 직접 SO-99999t·SO-99998t · 시퀀스 소비 금지 · 시험마다 어기는 CHECK 하나만):
--   ① draft + merged_into_id=다른 오더 → 23514 so_merge_reason_ck · ② cancelled+merged+closed_at · merged_into_id null → 23514 so_merge_reason_ck · ③ cancelled+merged+closed_at+merged_into_id → 통과 · ④ cancelled+voided+closed_at → 통과
--   구조: pg_get_constraintdef(so_merge_reason_ck) 가 새 식 · so 의 CHECK 개수 12 그대로.
