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
-- 20261007142513_dsc_4e_reprice_flag_draft_only.sql — dsc-4e (2026-10-07 · 회사 PC)
--   판정 349  「가격 다시 매겨 보세요」 깃발(so.reprice_suggested_at)은 초안에만 — Confirm = 손님과 가격이 정해진 순간 · 그 뒤 딜 · 제품 속성이 바뀌어도 찍지 않는다 · 다시 매기려면 Unconfirm → Reprice(지금처럼)
--     1) so_deal_flag_open_orders 의 상태 목록 ('draft', 'confirmed') → 'draft' 하나(바이트 복사 + 바뀐 줄 하나 · 이름 · 인자 · 권한 · 부르는 곳 그대로)
--     2) 초안을 떠나는 순간 깃발을 지운다 — so BEFORE UPDATE OF status 트리거(old draft → new ≠ draft ∧ 깃발 있음) · 확정 창구(so_confirm · so_pos_confirm · so_cancel …)를 재발행하지 않아도 모든 길을 덮는다 · Unconfirm 으로 돌아올 때는 세우지 않는다
--     3) 이미 남은 깃발 정리 — status <> 'draft' 인 오더의 깃발을 비운다(지운 행 수 raise notice · ims_touch 를 비껴 updated_at · updated_by 는 그대로 — 사람이 고친 것이 아니다) · 초안의 깃발은 그대로(영업이 Reprice 로 지운다)
--   훑기(§1): 세우는 곳 = so_header_update(초안만 · so_require_draft) · so_merge(새 머리 = 초안) · so_deal_flag_open_orders(초안 + Confirmed → 여기서 고침) · 지우는 곳 = so_reprice(초안만) — 초안이 아닌 오더에 세우는 다른 곳 없음 · so_create 는 세우지 않는다
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록이 실물을 세어 어긋나면 전부 되돌린다 · 검증 supabase/tests/dsc-4e-verify.sql

-- ═══ 1) so_deal_flag_open_orders 재발행 — 마지막 정의 20261007005851:42~57(DB md5 4e54213c · 검증 G0 대조) · 바뀐 줄 하나(상태 목록) · 시그니처 같아 create or replace(권한 · 부르는 곳 그대로) ═══
create or replace function public.so_deal_flag_open_orders(p_deal_id uuid, p_from date, p_to date, p_customer boolean, p_product_ids uuid[] default null)
  returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_n int;
begin
  update public.so s set reprice_suggested_at = now()
  where s.status = 'draft' and s.reprice_suggested_at is null                                                                              -- dsc-4e 판정 349: 깃발은 초안에만(Confirm = 손님과 가격이 정해진 순간 · 그 뒤 딜이 바뀌어도 찍지 않는다)
    and (p_from is null or p_from <= s.order_date) and (p_to is null or p_to >= s.order_date)
    and (not p_customer or public.so_deal_customer_ok(p_deal_id, s.customer_id, s.price_tier_id))
    and (p_product_ids is null or exists (select 1 from public.so_line l where l.so_id = s.id and l.product_id = any (p_product_ids)));   -- dsc-4c 판정 344: 그 제품이 든 줄의 오더만
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
comment on function public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[]) is '딜이 바뀌었을 때(또는 제품 속성이 바뀌었을 때 · dsc-4c) 열린 초안(draft — ⭐ dsc-4e 판정 349: Confirmed 는 찍지 않는다 · Confirm 뒤 다시 매기려면 Unconfirm → Reprice)에 reprice_suggested_at 을 세운다(dsc-3a · 판정 286 · 313 · 344 · 349) — 기간(오더 날짜) ∧ (p_customer 면) 손님 조건 ∧ (p_product_ids 가 있으면) 그 제품이 든 줄 · 이미 세워진 오더는 그대로 · 열린 상태 집합은 여기 한 곳 · 트리거 so_deal_changed · so_deal_part_changed(4인자) · product_deal_hit_changed · product_tag_deal_hit_changed(제품 목록만) · 창구 so_deal_save(dsc-4d · 5인자)가 부른다 · 직원이 직접 부를 수 없다';

-- ═══ 2) 초안을 떠나면 깃발을 지운다 — so BEFORE UPDATE OF status · WHEN(old draft → new ≠ draft ∧ 깃발 있음) · 이름이 so_status_guard 보다 앞이라 먼저 돌지만 둘은 서로 무관(문지기가 거부하면 전부 되돌아간다) ═══
create function public.so_reprice_flag_draft_only() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  new.reprice_suggested_at := null;                                                                                   -- dsc-4e 판정 349: 초안을 떠나는 순간(confirmed · cancelled · …) 깃발을 지운다 — 어느 창구로 떠나든 한 자리
  return new;
end;
$$;
revoke all on function public.so_reprice_flag_draft_only() from public, anon, authenticated;
comment on function public.so_reprice_flag_draft_only() is 'so BEFORE UPDATE OF status(WHEN old.status = draft ∧ new.status ≠ draft ∧ 깃발 있음 · dsc-4e 판정 349) — 초안을 떠나는 순간 reprice_suggested_at 을 비운다(Confirm = 손님과 가격이 정해진 순간 · Reprice 없이 Confirm 해도 Confirmed 오더에 깃발이 남지 않게) · Unconfirm 으로 초안이 되돌아올 때는 세우지 않는다 · 확정 · 취소 창구는 무접촉(표 트리거라 모든 길을 덮는다) · 직원이 직접 부를 수 없다';
create trigger so_reprice_flag_draft_only before update of status on public.so
  for each row when (old.status = 'draft' and new.status is distinct from 'draft' and new.reprice_suggested_at is not null)
  execute function public.so_reprice_flag_draft_only();

-- ═══ 3) 이미 남은 깃발 정리 — 초안이 아닌 오더만 · ims_touch 를 비껴(updated_at · updated_by 그대로) · 지운 행 수를 남긴다 ═══
set local session_replication_role = replica;
do $$
declare v_n int; v_by text;
begin
  select coalesce(string_agg(s.status || '=' || s.n, ' · ' order by s.status), '-') into v_by
    from (select status, count(*) as n from public.so where status <> 'draft' and reprice_suggested_at is not null group by status) s;
  update public.so set reprice_suggested_at = null where status <> 'draft' and reprice_suggested_at is not null;
  get diagnostics v_n = row_count;
  raise notice 'dsc-4e: cleared the reprice flag on % non-draft order(s) (%) — draft flags untouched', v_n, v_by;
end $$;
set local session_replication_role = origin;

-- ═══ 4) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text; v_src text;
begin
  if to_regprocedure('public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[])') is null or to_regprocedure('public.so_reprice_flag_draft_only()') is null then v_bad := v_bad || ' missing'; end if;
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_flag_open_orders';
  if v_src not like '%s.status = ''draft'' and s.reprice_suggested_at is null%' or v_src like '%''confirmed''%' then v_bad := v_bad || ' flag_open_orders(body)'; end if;
  foreach v_t in array array['public.so_reprice_flag_draft_only()', 'public.so_deal_flag_open_orders(uuid, date, date, boolean, uuid[])'] loop
    if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(open)', v_t); end if;
  end loop;
  if (select count(*) from pg_trigger where tgrelid = 'public.so'::regclass and tgname = 'so_reprice_flag_draft_only' and tgenabled <> 'D' and pg_get_triggerdef(oid) like 'CREATE TRIGGER so_reprice_flag_draft_only BEFORE UPDATE OF status ON public.so FOR EACH ROW WHEN %') <> 1 then v_bad := v_bad || ' trigger'; end if;
  if (select count(*) from public.so where status <> 'draft' and reprice_suggested_at is not null) <> 0 then v_bad := v_bad || ' leftover_flags'; end if;
  if current_setting('session_replication_role') <> 'origin' then v_bad := v_bad || ' replication_role'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_reprice', 'so_header_update', 'so_merge', 'so_confirm', 'so_unconfirm', 'so_cancel', 'so_pos_confirm', 'so_status_guard', 'so_product_flag_open_orders') and p.prosrc like '%dsc-4e%') <> 0 then v_bad := v_bad || ' untouched(touched)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM349', message = format('STOP - dsc-4e did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
