-- ─────────────────────────────────────────────────────────────
-- 제품 속성이 바뀌면 그 제품이 든 열린 오더에 reprice 표시 — 표에 붙은 문장 트리거(product · product_tag) (Asung-IMS · dsc-4c · 2026-10-06)
--   정본(뒤에 적는다): so-module 판정 344(Caleb · 2026-10-06) — 길은 트리거(화면 product_update 든 Cin7 재적재(service_role)든 같은 길) · 판정 286 · 313 과 같은 결
--   일으키는 칸(so_deal_candidates 의 hit · so_deal_products 가 읽는 것 전부): product.brand_id · category_id · parent_product_id(세트의 낱개) · product_tag 의 (product_id, tag) 행 — is_active · sellable 은 걸림 판정이 읽지 않는다(⬜2 · 넣지 않음)
--   ⚠️ 문장 트리거 + transition table 은 UPDATE OF 칸 목록을 못 쓴다 → AFTER UPDATE 전체에 돌고 함수가 세 칸의 실제 변화만 고른다(안 바뀐 문장은 o·n 조인 한 번으로 끝 · P7 로 잰다)
--   범위(판정 302): 바뀐 제품 X 와 X 를 낱개로 둔 세트들(parent_product_id = X)이 든 줄의 열린 오더 — 세트 줄은 낱개의 속성으로도 걸리므로 낱개가 바뀌면 그 세트 줄도 대상
--   싼 선검사: 켜진 딜(is_active · 줄 딜)의 켜진 줄의 대상 가운데 그 종류(tag 옛·새 글자 · brand_id 옛·새 · category_id 옛·새)가 하나라도 있을 때만 오더를 찾는다 · parent_product_id 가 바뀌면 걸기 대상이 하나라도 있을 때
--   열린 상태 집합은 so_deal_flag_open_orders 한 곳 — p_product_ids 인자 하나를 더해 재사용(바이트 복사 + 더한 줄 · drop + create · 부르는 둘(so_deal_changed · so_deal_part_changed)은 4인자 호출 그대로)
--   ⬜1 문장 트리거(transition table) — 재적재의 대량 갱신이 한 문장이면 트리거 한 번 · 바뀐 행만 모아 flag 한 번(잰 값은 검증 P7) · 딜 표 다섯의 행 트리거(판정 338)는 그대로
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 하나(so_deal_flag_open_orders 20261006201443:238~252 바이트 복사 + 더한 줄 둘) · product_update 무접촉 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
--   원칙 1: IMS 는 Cin7 없이 돈다 — 적재는 「제품 속성을 바꾸는 한 길」일 뿐이고 표시 규칙은 IMS 의 것
-- ─────────────────────────────────────────────────────────────
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

-- ═══ 1) so_deal_flag_open_orders 재발행 — 마지막 정의 20261006201443:238~252(DB md5 b70a24a0 · 검증 G0 대조) · p_product_ids 인자 하나(기본 null) · WHERE 한 줄 ═══
drop function public.so_deal_flag_open_orders(uuid, date, date, boolean);
create function public.so_deal_flag_open_orders(p_deal_id uuid, p_from date, p_to date, p_customer boolean, p_product_ids uuid[] default null)
  returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_n int;
begin
  update public.so s set reprice_suggested_at = now()
  where s.status in ('draft', 'confirmed') and s.reprice_suggested_at is null
    and (p_from is null or p_from <= s.order_date) and (p_to is null or p_to >= s.order_date)
    and (not p_customer or public.so_deal_customer_ok(p_deal_id, s.customer_id, s.price_tier_id))
    and (p_product_ids is null or exists (select 1 from public.so_line l where l.so_id = s.id and l.product_id = any (p_product_ids)));   -- dsc-4c 판정 344: 그 제품이 든 줄의 오더만
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[]) from public, anon, authenticated;
comment on function public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[]) is '딜이 바뀌었을 때(또는 제품 속성이 바뀌었을 때 · dsc-4c) 열린 오더(draft · confirmed)에 reprice_suggested_at 을 세운다(dsc-3a · 판정 286 · 313 · 344) — 기간(오더 날짜) ∧ (p_customer 면) 손님 조건 ∧ (p_product_ids 가 있으면) 그 제품이 든 줄 · 이미 세워진 오더는 그대로 · 열린 상태 집합은 여기 한 곳 · 트리거 so_deal_changed · so_deal_part_changed(4인자) · product_deal_hit_changed · product_tag_deal_hit_changed(제품 목록만)가 부른다 · 직원이 직접 부를 수 없다';

-- ═══ 2) 핵심 helper — 바뀐 제품 목록 → 범위(제품 + 그 세트들) → flag 한 번 ═══
create function public.so_product_flag_open_orders(p_product_ids uuid[])
  returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_ids uuid[];
begin
  if p_product_ids is null or cardinality(p_product_ids) = 0 then return 0; end if;
  select array_agg(distinct x) into v_ids
    from (select unnest(p_product_ids) as x
          union all
          select s.id from public.product s where s.parent_product_id = any (p_product_ids)) u;                       -- 판정 302: 낱개가 바뀌면 그 세트 줄도
  return public.so_deal_flag_open_orders(null, null, null, false, v_ids);
end;
$$;
revoke all on function public.so_product_flag_open_orders(uuid[]) from public, anon, authenticated;
comment on function public.so_product_flag_open_orders(uuid[]) is '제품 속성이 바뀐 제품들(과 그 세트들)이 든 줄의 열린 오더에 다시 매기기 권함(dsc-4c · 판정 344 · 302) — so_deal_flag_open_orders(p_product_ids) 한 번 · 트리거 둘이 부른다 · 직원이 직접 부를 수 없다';

-- ═══ 3) product — AFTER UPDATE OF brand_id · category_id · parent_product_id · 문장 트리거(transition table) · 값이 실제로 바뀐 행만 · 선검사 ═══
create function public.product_deal_hit_changed() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_ids uuid[];
begin
  with tg as (                                                                                 -- 켜진 줄 딜의 켜진 줄의 대상(선검사 재료 · 보통 수십 행)
    select x.target, x.brand_id, x.category_id
      from public.so_deal_target x
      join public.so_deal_line l on l.id = x.line_id and l.is_active
      join public.so_deal d on d.id = l.deal_id and d.is_active and not d.is_order_level)
  select array_agg(n.id) into v_ids
    from n join o on o.id = n.id
   where (o.brand_id, o.category_id, o.parent_product_id) is distinct from (n.brand_id, n.category_id, n.parent_product_id)
     and (   exists (select 1 from tg where tg.target = 'brand'    and tg.brand_id    in (o.brand_id, n.brand_id))
          or exists (select 1 from tg where tg.target = 'category' and tg.category_id in (o.category_id, n.category_id))
          or (o.parent_product_id is distinct from n.parent_product_id and exists (select 1 from tg)));
  if v_ids is not null then perform public.so_product_flag_open_orders(v_ids); end if;
  return null;
end;
$$;
revoke all on function public.product_deal_hit_changed() from public, anon, authenticated;
comment on function public.product_deal_hit_changed() is 'product AFTER UPDATE FOR EACH STATEMENT(old table o · new table n · dsc-4c 판정 344 · ⚠️ transition table 은 UPDATE OF 칸 목록과 같이 못 써 모든 update 문장에 돌고 brand_id · category_id · parent_product_id 가 실제로 바뀐 행만 고른다) — 값이 실제로 바뀐 행 가운데 켜진 줄 딜의 켜진 줄 대상이 옛·새 브랜드 · 카테고리를 걸거나(낱개가 바뀌면 걸기 대상이 하나라도 있으면) 그 제품(과 세트들)이 든 열린 오더에 표시 · 재적재의 한 문장 = 트리거 한 번';
create trigger product_deal_hit_changed after update on public.product                                                 -- ⚠️ transition table 은 UPDATE OF 칸 목록과 같이 못 쓴다 — 칸 판정은 함수 안(o·n 비교)
  referencing old table as o new table as n for each statement execute function public.product_deal_hit_changed();

-- ═══ 4) product_tag — AFTER INSERT · DELETE · UPDATE OF tag, product_id · 문장 트리거 셋(함수 하나 · tg_op 로 가른다) ═══
create function public.product_tag_deal_hit_changed() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_ids uuid[];
begin
  if tg_op = 'INSERT' then
    select array_agg(distinct n.product_id) into v_ids from n
     where exists (select 1 from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id and l.is_active join public.so_deal d on d.id = l.deal_id and d.is_active and not d.is_order_level
                    where x.target = 'tag' and x.tag = n.tag);
  elsif tg_op = 'DELETE' then
    select array_agg(distinct o.product_id) into v_ids from o
     where exists (select 1 from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id and l.is_active join public.so_deal d on d.id = l.deal_id and d.is_active and not d.is_order_level
                    where x.target = 'tag' and x.tag = o.tag);
  else
    select array_agg(distinct u.pid) into v_ids
      from (select n.product_id as pid, n.tag from n join o on o.id = n.id where (o.tag, o.product_id) is distinct from (n.tag, n.product_id)
            union all
            select o.product_id, o.tag from n join o on o.id = n.id where (o.tag, o.product_id) is distinct from (n.tag, n.product_id)) u
     where exists (select 1 from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id and l.is_active join public.so_deal d on d.id = l.deal_id and d.is_active and not d.is_order_level
                    where x.target = 'tag' and x.tag = u.tag);
  end if;
  if v_ids is not null then perform public.so_product_flag_open_orders(v_ids); end if;
  return null;
end;
$$;
revoke all on function public.product_tag_deal_hit_changed() from public, anon, authenticated;
comment on function public.product_tag_deal_hit_changed() is 'product_tag AFTER INSERT · DELETE · UPDATE FOR EACH STATEMENT(transition table · dsc-4c 판정 344 · update 는 tag · product_id 가 실제로 바뀐 행만) — 켜진 줄 딜의 켜진 줄이 그 태그(옛·새 글자)로 걸 때만 그 제품(과 세트들)이 든 열린 오더에 표시 · 적재 upsert · 화면 product_update(tag_add · tag_off) 둘 다 같은 길';
create trigger product_tag_deal_hit_changed_i after insert on public.product_tag referencing new table as n for each statement execute function public.product_tag_deal_hit_changed();
create trigger product_tag_deal_hit_changed_d after delete on public.product_tag referencing old table as o for each statement execute function public.product_tag_deal_hit_changed();
create trigger product_tag_deal_hit_changed_u after update on public.product_tag referencing old table as o new table as n for each statement execute function public.product_tag_deal_hit_changed();   -- 칸 목록 없음(위와 같은 제약) · 함수가 tag · product_id 변화만 본다

-- ═══ 5) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text;
begin
  if to_regprocedure('public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[])') is null or to_regprocedure('public.so_deal_flag_open_orders(uuid, date, date, boolean)') is not null then v_bad := v_bad || ' flag_open_orders(signature)'; end if;
  foreach v_t in array array['public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[])', 'public.so_product_flag_open_orders(uuid[])', 'public.product_deal_hit_changed()', 'public.product_tag_deal_hit_changed()'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(open)', v_t); end if;
  end loop;
  if (select count(*) from pg_trigger where tgrelid = 'public.product'::regclass and tgname = 'product_deal_hit_changed' and tgenabled <> 'D' and pg_get_triggerdef(oid) like 'CREATE TRIGGER product_deal_hit_changed AFTER UPDATE ON public.product REFERENCING OLD TABLE AS o NEW TABLE AS n FOR EACH STATEMENT EXECUTE FUNCTION %') <> 1 then v_bad := v_bad || ' product(trigger)'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.product_tag'::regclass and tgname in ('product_tag_deal_hit_changed_i', 'product_tag_deal_hit_changed_d', 'product_tag_deal_hit_changed_u') and tgenabled <> 'D') <> 3 then v_bad := v_bad || ' product_tag(triggers)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_changed', 'so_deal_part_changed') and p.prosrc like '%so_deal_flag_open_orders(%') <> 2 then v_bad := v_bad || ' callers'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'product_update' and p.prosrc like '%dsc-4c%') <> 0 then v_bad := v_bad || ' product_update(touched)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM344', message = format('STOP - dsc-4c did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
