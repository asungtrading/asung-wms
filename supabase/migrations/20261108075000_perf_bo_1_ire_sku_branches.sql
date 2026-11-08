-- ─────────────────────────────────────────────────────────────
-- perf-bo-1 — inv_receipt_events 의 sku 조건을 두 갈래로(Asung-IMS · 2026-11-08 · perf-bo-0 조사 → 안 A · 이견 답 1 ~ 10)
--   증상(perf-bo-0 실측 11-08 · 메인 DB): Backorders · Arrivals 「Ready to ship now」 = so_backorder_ready 기본 거르기 5/5 statement timeout(직원 8 s) · cron 54 메일 회차 9.7 s(11-05 09:07).
--   까닭: ready → so_backorder_fill(screen) 의 arrived_in_period 가 열린 백오더 줄마다(417) inv_receipt_events 를 부른다 · 그 함수는 SET 붙은 SQL 함수(인라인 안 됨 · 일반 계획)라
--        `(p_sku is null or g.sku = p_sku)` 의 OR 가 색인 조건이 못 되어 호출마다 입고 후보 21 k 행 훑기(32.6 ms) × 420 ≈ 14 ~ 28 s. 같은 몸에서 OR 를 갈래로 나누면 Index Scan inv_ledger_sku_wh_on_idx · 0.057 ms(≈ 600 배).
--   고침(「입고 정의 하나」 그대로 · perf-rpc-1 `20261104205654` 꼴): 같은 select 두 갈래 UNION ALL —
--        ① 키 갈래(p_sku 값) = 옛 줄에서 OR 자리만 `p_sku is not null and g.sku = p_sku`(일반 계획에서 `$1 is not null` 이 One-Time Filter · sku 색인) ·
--        ② 전체 갈래(p_sku null · arrivals 길) = 옛 줄 바이트 그대로 + 문 한 줄 `and p_sku is null`.
--        다른 OR 셋(p_warehouse · p_from · p_to)은 그대로(이견 답 3 — sku 색인 뒤 남는 행이 sku 당 평균 5 · 최대 42 라 Filter 로 충분 · 0.057 ms 는 그 셋을 남긴 채 잰 값).
--        `set search_path` 그대로(이견 답 2 — 빼면 인라인되어 호출자 넷의 계획이 바뀐다 · 속도는 갈래만으로 충분).
--   무변: 시그니처 · 반환 · sql stable security invoker · search_path · acl(postgres · authenticated · service_role) · 소유자 · comment(안의 「overview · arrivals 가 쓴다」 는 낡음 — fill · mail_backorder_pick 도 쓴다 · 보고에만).
--        호출자 넷 무접촉: so_backorder_fill(sku 값 · ims_today() − 30) · so_backorder_overview(sku 값) · mail_backorder_pick(sku 값) · so_backorder_arrivals(null) — 출력 무변(검증 ① 332 쌍 + null 갈래 집합 차 0).
--   마지막 정의: 20261015015435_bo_2_arrivals_waiting.sql:36 — 파일 몸(41 ~ 50 행) = DB prosrc md5 56ecce6e032d6b09c9d67ebf8d671a00(11-08 02:57 대조 같음). 재발행 몸은 DB prosrc 에서.
--   틀리면: Backorders Arrivals · Ready · Overview(last_receipt_on) · 백오더 메일(mail_backorder_pick · cron 54) 의 「입고」 판정 — 재고 쓰기에는 닿지 않는다. 검증: supabase/tests/perf_bo_1_check.sql.
--   적용: Caleb 이 psql -1 -c "set local lock_timeout = '5s'" -f + supabase migration repair --status applied 20261108075000 · db push 금지 · 번호는 다른 창(qbo-sync-2e-3-2-1 · 20261108075221) 보다 앞(이 차수가 먼저 적용).
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) inv_receipt_events — 키 갈래(새) UNION ALL 전체 갈래(옛 줄 바이트 그대로 + 문 한 줄) · 머리는 옛 파일 그대로 ═══
create or replace function public.inv_receipt_events(p_sku text default null, p_warehouse text default null, p_from date default null, p_to date default null)
  returns table (ledger_id bigint, sku text, warehouse text, occurred_on date, kind text, doc_number text, qty_delta numeric, raw jsonb)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select g.id, g.sku, g.warehouse, g.occurred_on, g.event_type, g.doc_number, g.qty_delta, g.raw
  from public.inv_ledger g
  where p_sku is not null and g.sku = p_sku and (p_warehouse is null or g.warehouse = p_warehouse)   -- perf-bo-1: 키 갈래 — OR 없이 sku 술어만(일반 계획의 One-Time Filter · inv_ledger_sku_wh_on_idx) · 줄마다 부르는 fill · overview · mail_backorder_pick 길
    and (p_from is null or g.occurred_on >= p_from) and (p_to is null or g.occurred_on <= p_to)
    and g.qty_delta > 0
    and (g.event_type = 'po_in'
         or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
             and exists (select 1 from public.inv_ledger o
                         where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                           and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
  union all                                                                                            -- perf-bo-1: 전체 갈래(아래) = 옛 줄 바이트 그대로 + 문 한 줄 · 두 갈래는 p_sku 로 한쪽만 돈다(never executed) · arrivals(null) 길 무변
  select g.id, g.sku, g.warehouse, g.occurred_on, g.event_type, g.doc_number, g.qty_delta, g.raw
  from public.inv_ledger g
  where (p_sku is null or g.sku = p_sku) and (p_warehouse is null or g.warehouse = p_warehouse)
    and (p_from is null or g.occurred_on >= p_from) and (p_to is null or g.occurred_on <= p_to)
    and g.qty_delta > 0
    and (g.event_type = 'po_in'
         or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
             and exists (select 1 from public.inv_ledger o
                         where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                           and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
    and p_sku is null                                                                                  -- perf-bo-1: 전체 갈래 문
$$;

-- ═══ 2) 자기 검사 — 과부하 1 · 시그니처 · 반환 · 속성 · acl · comment 무변 · 태그 줄 셋 · 새 몸에서 키 갈래(첫 select ~ union all) · 문 한 줄을 빼면 옛 몸 md5 56ecce6e… · update · delete 0 ═══
do $$
declare v_bad text := ''; v_src text; v_lines text[]; v_i int; v_k3 int; v_k4 int; v_rest text[] := '{}';
begin
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_receipt_events') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if (select pg_get_function_identity_arguments(oid) from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure) <> 'p_sku text, p_warehouse text, p_from date, p_to date' then v_bad := v_bad || ' signature'; end if;
  if (select pg_get_function_result(oid) from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure) <> 'TABLE(ledger_id bigint, sku text, warehouse text, occurred_on date, kind text, doc_number text, qty_delta numeric, raw jsonb)' then v_bad := v_bad || ' result'; end if;
  if (select p.provolatile::text || p.prosecdef::text || coalesce(p.proconfig::text, '-') || (select l.lanname from pg_language l where l.oid = p.prolang) from pg_proc p where p.oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure) <> 'sfalse{"search_path=public, pg_temp"}sql' then v_bad := v_bad || ' attrs'; end if;
  if not has_function_privilege('authenticated', 'public.inv_receipt_events(text, text, date, date)', 'execute') or not has_function_privilege('service_role', 'public.inv_receipt_events(text, text, date, date)', 'execute') or has_function_privilege('anon', 'public.inv_receipt_events(text, text, date, date)', 'execute') then v_bad := v_bad || ' acl'; end if;
  if md5(coalesce(obj_description('public.inv_receipt_events(text, text, date, date)'::regprocedure, 'pg_proc'), '')) <> '7b42f83364e403585d06fe40a86823bc' then v_bad := v_bad || ' comment_changed'; end if;
  select prosrc into v_src from pg_proc where oid = 'public.inv_receipt_events(text, text, date, date)'::regprocedure;
  if (select count(*) from regexp_matches(v_src, '-- perf-bo-1', 'g')) <> 3 then v_bad := v_bad || ' tag_lines<>3'; end if;
  if (select count(*) from regexp_matches(v_src, '^\s*(update|delete)\s', 'gn')) <> 0 then v_bad := v_bad || ' write_stmt'; end if;
  -- 키 갈래(2 행 ~ union all 줄)와 문 한 줄을 빼면 옛 몸(bo-2 · 56ecce6e…)과 바이트 같아야 한다
  v_lines := string_to_array(v_src, E'\n');
  for v_i in 1 .. array_length(v_lines, 1) loop
    if v_lines[v_i] like '  union all%-- perf-bo-1%' then v_k3 := v_i; end if;
    if v_lines[v_i] like '    and p_sku is null %-- perf-bo-1%' then v_k4 := v_i; end if;
  end loop;
  if v_k3 is null or v_k4 is null or not (v_k3 < v_k4) then v_bad := v_bad || ' branch_markers'; end if;
  if v_bad = '' then
    for v_i in 1 .. array_length(v_lines, 1) loop
      if (v_i >= 2 and v_i <= v_k3) or v_i = v_k4 then continue; end if;
      v_rest := v_rest || v_lines[v_i];
    end loop;
    if md5(array_to_string(v_rest, E'\n')) <> '56ecce6e032d6b09c9d67ebf8d671a00' then v_bad := v_bad || ' old_body_not_preserved'; end if;
  end if;
  if v_bad <> '' then raise exception 'perf-bo-1 self-check failed:%', v_bad; end if;
end $$;
