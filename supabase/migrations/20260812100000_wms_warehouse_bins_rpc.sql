-- 캡 위험 #11 근본 해결 (2026-08-12 2단계) — receiver 빈 지정 드롭다운 폴백용 RPC.
--
-- 문제: 폴백이 wms_sku_bins 를 통째로 받아(toronto 8105 / edmonton 7371 행 — 실측)
--       클라이언트에서 distinct 했다. PostgREST 1000행 캡의 8배 초과 —
--       드롭다운에 1481개(toronto) 중 최대 1000개만, **어느 bin 이 빠지는지도 미정의**.
--       이미 틀린 상태였다(예방이 아니라 수리).
--
-- 왜 뷰가 아니라 RPC 인가 (규칙 20 캡 절에 원리 기록):
--   distinct 뷰를 만들어도 toronto 1481행 > 1000 캡 — **행을 반환하는 한 캡을 벗어날 수 없다.**
--   jsonb_agg 로 단일 jsonb 값(행 1개)을 반환하면 행 캡이 원천적으로 적용되지 않는다.
--   1왕복 · ~1500 bin ≈ 수십 KB.
--
-- 동작 동일성 (검증된 경로 — 종전 폴백과 같은 의미 유지):
--  · is_current 무필터 — 종전 폴백도 필터하지 않았고, 실측 1481/509 도 무필터 distinct 다.
--    ("재고가 앉아본 bin" 의미 그대로. 1순위 EF action=bins 는 빈 자리 포함 Cin7 전체라 원래 더 넓다.)
--  · bin 별 zone 은 min(zone) — 종전 클라이언트 dedupe 는 "먼저 온 행" 승리였는데 순서가
--    미정의였다. min 은 결정적이고, null 이면 클라이언트가 zoneOfBin() 으로 채운다(기존 로직 유지).
--
-- 권한: wms_complete_pack 패턴 — SECURITY INVOKER(베이스 테이블 RLS 상속) ·
--       PUBLIC/anon revoke · authenticated/service_role 만.

create or replace function public.wms_warehouse_bins(p_warehouse text)
returns jsonb
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select coalesce(jsonb_agg(jsonb_build_object('bin', bin, 'zone', zone) order by bin), '[]'::jsonb)
  from (
    select bin, min(zone) as zone
    from wms_sku_bins
    where warehouse = p_warehouse
    group by bin
  ) d;
$$;

revoke all on function public.wms_warehouse_bins(text) from public;
revoke all on function public.wms_warehouse_bins(text) from anon;
grant execute on function public.wms_warehouse_bins(text) to authenticated, service_role;
