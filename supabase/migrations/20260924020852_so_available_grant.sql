-- SO 쓰기 ②a″ — so_available_many 에 authenticated execute (2026-09-24 UTC · 토론토 2026-09-23 밤)
-- 결함(Caleb 실측 2026-09-23 · ②a 검증 :98): 화면용 so_available(invoker · authenticated 가 실행)이 속 함수 so_available_many(authenticated revoke)를 불러
--   직원 신원에서 「permission denied for function so_available_many」 — postgres 로 잰 \timing 에서는 안 드러났다 · 가짜 직원 신원에서 처음 걸렸다
-- 판정(Caleb): grant execute to authenticated — 읽기만 하는 계산이고 재고(ims_inv_balance)·예약(so_reserve)은 직원이 이미 읽을 수 있다 · definer 로 바꾸지 않는다(RLS 를 비껴갈 이유가 없다)
-- 같은 모양 점검(②a 두 파일 · invoker+authenticated 함수가 revoke 된 속 함수를 부르는 곳): 이것 하나 — so_family_lines → so_family_members 는 둘 다 authenticated · so_require_role·so_split·so_allocate_run 은 definer 창구만 부른다
-- 바탕: 20260924015859_so_confirm_fast.sql(so_available_many · revoke all … from public, anon, authenticated)
-- 대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음)

grant execute on function public.so_available_many(uuid[], uuid) to authenticated;   -- 읽기 계산 · so_available(화면 창구 · invoker)이 직원 신원으로 부른다

comment on function public.so_available_many(uuid[], uuid) is
  '⭐⭐ 가용 재고 식 한 곳(②a′ · 5-f · 2-d) — 낱개 제품 배열 × 창고 → 행마다 (stock_pid · qty_ea 창고 잔고(ims_inv_balance 모든 bin 합) · allocated_ea Σ 열린 allocated 예약 × pack_factor · available_ea 차) · 부른 pid 마다 한 행(잔고 없으면 0) · 음수 그대로(엔진이 0 으로 본다) · preorder·hold·backorder 는 빼지 않는다 · 뷰를 한 번만 계산한다(제품마다 부르면 ~150ms × n · 2026-09-23 실측) · so_available(화면 창구 · invoker · 직원이 부른다 ⇒ authenticated execute · 2026-09-24 ②a″)·so_allocate_run(엔진)이 이것을 부른다 — 식이 두 곳이 되지 않게 · ⚠️ 낱개를 받는다(세트→낱개 환산은 부르는 쪽) · invoker(RLS 그대로 · 읽기만)';
