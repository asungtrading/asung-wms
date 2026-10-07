do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;
-- 20261007161321_so_tot_1_totals_many.sql — so-tot-1 (2026-10-07 · 회사 PC)
--   Caleb 2026-10-07 「세일즈 오더 화면에도 오더 토탈 금액이 나오게 해줘」 · 안 A: 목록의 Total = 오더 화면(so.html)의 Total 과 같은 숫자(so_detail.totals.order_total_with_tax · 세금 포함 · 나가기 전 주문 수량 · 나간 뒤(shipped · fulfilled) 보낸 수량 · 세금 규칙 없으면 null)
--   읽기 창구 so_totals_many(p_so_ids uuid[]) — so_detail 의 totals 와 **같은 식 · 같은 값**(검증 so-tot-1-verify.sql 이 테스트 DB 의 모든 오더에서 여덟 열을 numeric 으로 대조)
--   식은 so_detail 과 같은 속 함수 둘에 있다: so_lines_total(판정 310 · 기준 금액 한 곳) · so_tax_preview(세금 · surcharge · 보낸 수량 기준 · 식 한 곳) — 여기 남는 것은 그 둘을 잇는 산수 다섯 줄(basis · 오더 할인 round · 운임 합 · 두 합계)
--   so_detail 은 무접촉(재발행하지 않는다 — 이유는 so-tot-1 보고 ⬜ 판단) · invoker · stable · RLS 그대로(볼 수 없는 오더 · 없는 id 는 행 없이 지나간다) · 인자 상한 200(중복 · null 을 뺀 수) · anon · public 회수 · authenticated execute
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록이 실물을 세어 어긋나면 되돌린다

-- ═══ 1) so_totals_many — 오더 여럿의 totals 한 번에(목록 화면용) ═══
create function public.so_totals_many(p_so_ids uuid[])
  returns table (so_id uuid, basis text, lines_total numeric, order_discount_amount numeric, charges_total numeric, surcharge_amount numeric, tax numeric, order_total numeric, order_total_with_tax numeric)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_ids uuid[];
  v_r   record;
  v_tax jsonb;
  v_lt  numeric;  v_od numeric;  v_chg numeric;  v_sc numeric;  v_t numeric;  v_b text;
begin
  if p_so_ids is null then return; end if;
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;                            -- 중복 · null 은 센다 · 한 오더는 한 행
  if v_ids is null then return; end if;
  if cardinality(v_ids) > 200 then
    raise exception 'so_totals_many takes at most 200 order ids at a time (got %) — nothing was read', cardinality(v_ids);
  end if;
  for v_r in select s.id, s.status, s.order_discount_pct from public.so s where s.id = any (v_ids) order by s.id loop   -- RLS 가 숨긴 오더 · 없는 id 는 여기서 빠진다(행 없음)
    v_b   := case when v_r.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;                    -- so_detail: 나간 뒤에는 보낸 수량이 금액(ⓐ2)
    v_tax := public.so_tax_preview(v_r.id, null, null, v_b);                                                        -- so_detail 과 같은 호출(오늘 · 오더에 고른 규칙 · basis)
    v_lt  := case when v_b = 'shipped' then (v_tax->'totals'->>'lines_amount')::numeric else public.so_lines_total(v_r.id) end;   -- so_detail: ordered 는 so_lines_total(판정 310) · shipped 는 tax 의 lines_amount
    v_od  := case when v_r.order_discount_pct is null then 0 else round(v_lt * v_r.order_discount_pct / 100, 2) end;   -- so_detail: 오더 할인은 제품 줄 합계에 한 번 · round 2(D6)
    select coalesce(sum(c.amount), 0) into v_chg from public.so_charge c where c.so_id = v_r.id;                     -- so_detail: charges_total
    v_sc  := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);                                          -- so_detail: surcharge-2a — tax totals 에서
    v_t   := (v_tax->'totals'->>'tax')::numeric;                                                                    -- 세금 규칙 없으면 null
    so_id := v_r.id;  basis := v_b;  lines_total := v_lt;  order_discount_amount := v_od;  charges_total := v_chg;  surcharge_amount := v_sc;  tax := v_t;
    order_total := v_lt - v_od + v_chg + v_sc;
    order_total_with_tax := case when v_t is null then null else v_lt - v_od + v_chg + v_sc + v_t end;
    return next;
  end loop;
end;
$$;
revoke all on function public.so_totals_many(uuid[]) from public, anon;
grant execute on function public.so_totals_many(uuid[]) to authenticated;
comment on function public.so_totals_many(uuid[]) is '오더 여럿의 totals 한 번에(so-tot-1 · 2026-10-07 · Caleb 「세일즈 오더 화면에도 오더 토탈 금액이 나오게」 · 안 A) — 행마다 so_detail(id).totals 의 basis · lines_total · order_discount_amount · charges_total · surcharge_amount · tax · order_total · order_total_with_tax 와 **같은 값**(검증 so-tot-1-verify 가 모든 오더에서 대조) · 같은 속 함수(so_lines_total · so_tax_preview(id, null, null, basis))를 부른다 · 세금 규칙이 없는 오더는 tax · order_total_with_tax null(화면 「no tax rule」) · invoker · stable · RLS 그대로 — 볼 수 없는 오더 · 없는 id 는 행이 안 나온다(목록은 빈 칸) · 중복 · null 은 빼고 센다 · 한 번에 200 개까지(넘으면 거부) · 목록 화면(so.html 넓은 · 좁은 목록 Total 열)이 부른다 · 금액은 오더에 저장되지 않는다 — 보일 때마다 계산';

-- ═══ 2) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text := 'public.so_totals_many(uuid[])';
begin
  if to_regprocedure(v_t) is null then v_bad := v_bad || ' missing'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_totals_many') <> 1 then v_bad := v_bad || ' count'; end if;
  if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || ' acl'; end if;
  if (select p.prosecdef or p.provolatile <> 's' from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_totals_many') then v_bad := v_bad || ' invoker/stable'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_detail', 'so_tax_preview', 'so_lines_total') and p.prosrc like '%so_totals_many%') <> 0 then v_bad := v_bad || ' untouched(touched)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM350', message = format('STOP - so-tot-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
