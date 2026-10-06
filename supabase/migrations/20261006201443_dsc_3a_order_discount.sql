-- ─────────────────────────────────────────────────────────────
-- 오더 할인 층 — 금액 단계(so_deal_tier) · 기준 금액 한 곳(so_lines_total) · 굳히는 한 곳(so_order_discount_apply) · 줄이 바뀌면 다시 고르기(so_line 트리거) · 나뉜 오더 잠금(order_discount_locked_at) · 규칙이 바뀌면 경고(딜 표 다섯 트리거) · 설정 키 so_invoice_unit_display · customer_scope · order_pct 삭제 (Asung-IMS · dsc-3a · 2026-10-06)
--   정본(뒤에 적는다): so-module §48 — 판정 277 · 282 · 284 · 286 · 308 ~ 315 · dsc-3 이견 1 ~ 18
--   판정 308  오더 할인을 so 에 쓰는 일은 so_order_discount_apply 하나 · so_create · so_header_update · so_reprice · so_merge 재발행(바뀐 줄만)
--   판정 309  금액 단계 = 새 표 so_deal_tier · 문지기 so_deal_tier_order_level_guard 새로 + so_deal_order_level_guard 재발행 · so_deal.order_pct 와 CHECK 둘 삭제(0행 확인 뒤)
--   판정 310  기준 금액 = so_lines_total(p_so_id) 한 곳 · so_detail 이 부른다
--   판정 311  다시 고르기 = so_line 행 트리거(qty_ordered · unit_price · free_reason · qty_removed · insert · delete) · draft ∧ source ≠ manual ∧ 잠기지 않음 · 경고 order_discount_rule_now_better 는 so_detail
--   판정 312  so.order_discount_locked_at — so_split 이 모체 · 형제에 적는다(백오더 · 손으로 나눈 것 모두) · 잠긴 오더는 트리거 · so_reprice 가 오더 할인을 건드리지 않음 · manual 은 덮을 수 있음 · so_merge 새 머리는 null
--   판정 313  딜 변경 경고 = 행 트리거 + WHEN 뜻 있는 칸 · 범위 draft · confirmed ∧ 기간 ∧ 손님 조건 · 손님 조건 표의 변경은 기간만
--   판정 314  inv_config.so_invoice_unit_display = both(both · discounted · net) · inv_config_guard 를 키마다 규칙으로 · 이 키는 어휘 검사 + master
--   판정 315  so_deal.customer_scope 와 CHECK 삭제
--   3b 자리(만들지 않음): 쿠폰(판정 283 · 317 ~ 319) · 크레딧 오더 할인 비례(316) · so_order_discount 의 source 는 그때 coupon 을 더한다
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 여섯은 마지막 정의 바이트 복사 + 바뀐 줄만(diff 는 보고에) · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
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

-- ═══ 1) so_deal_tier — 오더 딜의 금액 단계(판정 309 · 282) ═══
create table if not exists public.so_deal_tier (
  id          uuid primary key default gen_random_uuid(),
  cin7_id     uuid unique,
  source      text not null default 'manual',
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff (id) on delete no action,
  deal_id     uuid not null references public.so_deal (id) on delete no action,
  tier_no     int  not null,
  min_amount  numeric not null default 0,
  pct         numeric not null,
  constraint so_deal_tier_source_ck     check (source in ('cin7', 'manual')),
  constraint so_deal_tier_tier_no_ck    check (tier_no >= 1),
  constraint so_deal_tier_min_amount_ck check (min_amount >= 0),
  constraint so_deal_tier_pct_ck        check (pct > 0 and pct < 100),
  constraint so_deal_tier_no_uq         unique (deal_id, tier_no),
  constraint so_deal_tier_amount_uq     unique (deal_id, min_amount)
);
create index if not exists so_deal_tier_deal_idx       on public.so_deal_tier (deal_id);
create index if not exists so_deal_tier_updated_by_idx on public.so_deal_tier (updated_by);
create trigger so_deal_tier_touch before update on public.so_deal_tier for each row execute function public.ims_touch();
alter table public.so_deal_tier enable row level security;
create policy so_deal_tier_select on public.so_deal_tier for select to authenticated using (true);
create policy so_deal_tier_insert on public.so_deal_tier for insert to authenticated with check ((select public.ims_can_write('master')));
create policy so_deal_tier_update on public.so_deal_tier for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy so_deal_tier_delete on public.so_deal_tier for delete to authenticated using ((select public.ims_can_write('master')));
grant select, insert, update, delete on public.so_deal_tier to authenticated;
comment on table  public.so_deal_tier is '⭐ 오더 전체 딜의 금액 단계(dsc-3a · 판정 282 · 309) — 한 프로모션 = 딜 하나 · 단계 = 행(「$500 이상 5% · $1,000 이상 7%」= 두 행) · 기준 금액 = 줄 할인 뒤 제품 줄 합계(so_lines_total · 운임 · 부가금 · 세금 제외) · 걸리는 단계 중 가장 큰 pct(so_order_discount) · min_amount 0 = 조건 없음 · is_order_level 딜에만(so_deal_tier_order_level_guard) · 줄 딜(so_deal_line)과는 다른 표 · 쓰기는 master RLS · 창구는 dsc-4';
comment on column public.so_deal_tier.min_amount is '이 단계가 걸리는 최소 기준 금액(so_lines_total ≥ min_amount · 오더 통화 · 0 = 조건 없음) · 같은 딜 안에서 유일';
comment on column public.so_deal_tier.pct        is '오더 전체 할인 %(0 < pct < 100 · 판정 288 과 같은 범위) · 걸린 단계 중 가장 큰 것이 이긴다';

-- 문지기 셋째 — tier 는 오더 딜에만(6-a 의 반대쪽 · 줄은 줄 딜에만 그대로)
create function public.so_deal_tier_order_level_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  d public.so_deal%rowtype;
begin
  select * into d from public.so_deal where id = new.deal_id;
  if found and not d.is_order_level then
    raise exception 'Deal % is a line deal — amount tiers belong to an order-level deal — nothing was saved', d.name;
  end if;
  return new;
end;
$$;
comment on function public.so_deal_tier_order_level_guard() is 'so_deal_tier BEFORE INSERT OR UPDATE OF deal_id — 부모 딜이 is_order_level 이 아니면 거부(dsc-3a · 판정 309 · 6-a 의 거울)';
revoke all on function public.so_deal_tier_order_level_guard() from public, anon;
create trigger so_deal_tier_order_level_guard before insert or update of deal_id on public.so_deal_tier
  for each row execute function public.so_deal_tier_order_level_guard();

-- ═══ 2) so_deal_order_level_guard 재발행(6-b · 마지막 정의 20260923224900:223~234) — 단계가 있으면 오더 딜을 끌 수 없다 ═══
create or replace function public.so_deal_order_level_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if new.is_order_level and not old.is_order_level
     and exists (select 1 from public.so_deal_line l where l.deal_id = new.id) then
    raise exception 'Deal % has lines — remove them before making it an order-level deal — nothing was saved', new.name;
  end if;
  if not new.is_order_level and old.is_order_level
     and exists (select 1 from public.so_deal_tier t where t.deal_id = new.id) then                                              -- dsc-3a 판정 309: 단계가 있는 딜은 오더 딜을 끌 수 없다
    raise exception 'Deal % has amount tiers — remove them before turning off order-level — nothing was saved', new.name;
  end if;
  return new;
end;
$$;
comment on function public.so_deal_order_level_guard() is 'so_deal BEFORE UPDATE — 줄이 있는 딜에 is_order_level 을 켜면 거부(이견 6 의 반대쪽 문) · dsc-3a: 단계(so_deal_tier)가 있는 딜에서 is_order_level 을 끄면 거부(판정 309) · insert 는 줄 · 단계가 있을 수 없어 보지 않는다';

-- ═══ 2b) so_deal_line_order_level_guard 재발행(6-a · 마지막 정의 20260923224900:205~218) — 문구만: order_pct 가 사라졌다 ═══
create or replace function public.so_deal_line_order_level_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  d public.so_deal%rowtype;
begin
  select * into d from public.so_deal where id = new.deal_id;
  if found and d.is_order_level then
    raise exception 'Deal % is an order-level deal — it has no lines (its amount tiers are the discount) — nothing was saved', d.name;    -- dsc-3a 판정 309: 문구만(옛 % 칸은 지웠다)
  end if;
  return new;
end;
$$;
comment on function public.so_deal_line_order_level_guard() is 'so_deal_line BEFORE INSERT OR UPDATE OF deal_id — 부모 딜이 is_order_level 이면 거부(이견 6 · 오더 전체 딜은 금액 단계 so_deal_tier · 줄 없음 · dsc-3a 문구 갱신). FK 가 없는 deal_id 는 여기서 안 막는다(FK 가 막는다)';

-- ═══ 3) so_deal.order_pct · customer_scope 삭제(판정 309 · 315) — 0행이 아니면 멈춘다 ═══
do $$
declare v_n int;
begin
  select count(*) into v_n from public.so_deal where order_pct is not null;
  if v_n <> 0 then
    raise exception using errcode = 'IM309', message = format('STOP - %s deal(s) still carry order_pct - move them into so_deal_tier first - nothing was changed', v_n);
  end if;
  select count(*) into v_n from public.so_deal where customer_scope <> 'all';
  if v_n <> 0 then
    raise exception using errcode = 'IM315', message = format('STOP - %s deal(s) have customer_scope <> all - their customer rules must already be in so_deal_customer_rule (dsc-2 moved 0) - nothing was changed', v_n);
  end if;
end $$;
alter table public.so_deal drop constraint so_deal_order_pct_pair_ck;
alter table public.so_deal drop constraint so_deal_order_pct_ck;
alter table public.so_deal drop column order_pct;
alter table public.so_deal drop constraint so_deal_customer_scope_ck;
alter table public.so_deal drop column customer_scope;
comment on column public.so_deal.is_order_level is '오더 전체 딜인가 — true 면 줄(so_deal_line)이 없고 금액 단계(so_deal_tier)가 있다(dsc-3a · 판정 309 · 옛 order_pct 칸은 지웠다) · false 면 줄 딜(so_deal_candidates) · 바꾸기는 문지기 둘이 지킨다';

-- ═══ 4) so_lines_total — 기준 금액 한 곳(판정 310) · so_detail 의 totals.lines_total 과 같은 식 ═══
create function public.so_lines_total(p_so_id uuid)
  returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce(sum(public.so_line_total(l)), 0) from public.so_line l where l.so_id = p_so_id
$$;
revoke all on function public.so_lines_total(uuid) from public, anon;
grant execute on function public.so_lines_total(uuid) to authenticated;
comment on function public.so_lines_total(uuid) is '오더의 제품 줄 합계(dsc-3a · 판정 310 · D6) — Σ so_line_total(줄) = round(qty_ordered × unit_price, 2) · 줄 할인 뒤 · 구성품 · 무상 줄은 0 · 운임(so_charge) · 부가금 · 세금 밖 · 오더 할인의 기준 금액(so_order_discount) 이자 so_detail totals.lines_total(basis ordered) · 식은 여기 하나';

-- ═══ 5) so_order_discount 재발행 — 금액 단계(판정 282) · 마지막 정의 20261006193419(dsc-2) ═══
drop function public.so_order_discount(uuid);                                                                 -- 반환 열이 늘어(source) replace 가 안 된다 · grant 다시
create function public.so_order_discount(p_so_id uuid)
  returns table (pct numeric, deal_id uuid, source text)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with s as (select o.customer_id, o.order_date, o.price_tier_id, public.so_lines_total(o.id) as basis from public.so o where o.id = p_so_id),
  best as (
    select t.pct, x.id
    from public.so_deal x join public.so_deal_tier t on t.deal_id = x.id cross join s
    where x.is_active and x.is_order_level and x.kind = 'pct'
      and (x.date_from is null or x.date_from <= s.order_date)
      and (x.date_to   is null or x.date_to   >= s.order_date)
      and public.so_deal_customer_ok(x.id, s.customer_id, s.price_tier_id)                                        -- dsc-2 판정 296 · 299: 손님 조건은 so_deal_customer_rule(없으면 전체)
      and t.min_amount <= s.basis                                                                                 -- dsc-3a 판정 282: 걸리는 단계만 · 기준 = 줄 할인 뒤 제품 줄 합계
    order by t.pct desc, x.id, t.tier_no
    limit 1
  )
  select b.pct, b.id, case when b.pct is null then null else 'deal' end
  from (select 1) one
  left join best b on true;
$$;
revoke all on function public.so_order_discount(uuid) from public, anon;
grant execute on function public.so_order_discount(uuid) to authenticated;
comment on function public.so_order_discount(uuid) is '오더 전체 할인 하나(D6 · dsc-3a 재발행 2026-10-06 · 판정 277 · 282 · 310) — 켜짐 ∧ is_order_level ∧ kind pct ∧ 기간(오더 날짜) ∧ 손님 조건(so_deal_customer_ok) ∧ 단계 min_amount ≤ so_lines_total → 가장 큰 pct 하나(같으면 deal id · tier_no) · 늘 한 행(없으면 null 셋) · source 는 deal(3b 가 coupon 을 더한다 · 판정 317 · 쿠폰 딜은 쿠폰으로만) · 쓰는 일은 so_order_discount_apply';

-- ═══ 6) so.order_discount_locked_at(판정 312) · so_order_discount_apply — 굳히는 한 곳(판정 308) ═══
alter table public.so add column if not exists order_discount_locked_at timestamptz;
comment on column public.so.order_discount_locked_at is '오더 할인 잠금(dsc-3a · 판정 283 · 312) — so_split 이 모체 · 형제 둘 다에 적는다(백오더 · 출하 차이 · 손으로 나눈 것 모두: 손님이 주문한 금액으로 정한 % 는 나눠도 바뀌지 않는다) · 잠기면 so_line 트리거 · so_reprice 가 오더 할인을 다시 고르지 않는다(줄 할인은 다시 매긴다) · so_header_update 의 order_discount_pct(값 → manual · null → 다시 찾기)는 사람의 뜻이라 넘는다 · so_merge 의 새 머리는 null';
create function public.so_order_discount_apply(p_so_id uuid, p_staff uuid default null, p_force boolean default false)
  returns public.so
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_so public.so%rowtype;
  od   record;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then return null; end if;                                                                            -- 줄 삭제 트리거가 사라진 오더를 가리킬 수 있다 — 조용히
  if v_so.status <> 'draft' then return v_so; end if;                                                               -- 초안만 다시 고른다(확정 뒤는 so_unconfirm 으로 돌아와서)
  if not p_force and (v_so.order_discount_source is not distinct from 'manual' or v_so.order_discount_locked_at is not null) then
    return v_so;                                                                                                    -- manual(0 포함 · 판정 282) · 잠긴 오더(판정 312)는 그대로
  end if;
  select * into od from public.so_order_discount(p_so_id);
  if od.pct is distinct from v_so.order_discount_pct or od.deal_id is distinct from v_so.order_discount_deal_id or od.source is distinct from v_so.order_discount_source then
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id, order_discount_source = od.source, updated_by = coalesce(p_staff, updated_by)
    where id = p_so_id returning * into v_so;
  end if;
  return v_so;
end;
$$;
revoke all on function public.so_order_discount_apply(uuid, uuid, boolean) from public, anon, authenticated;
comment on function public.so_order_discount_apply(uuid, uuid, boolean) is '⭐ 오더 할인을 so 에 굳히는 한 곳(dsc-3a · 판정 308) — so_order_discount 의 결과(pct · deal_id · source)를 다를 때만 쓴다 · 초안만 · manual(0 포함)과 잠긴 오더(order_discount_locked_at · 판정 312)는 건너뛴다 · p_force = so_header_update 의 「다시 찾기」(order_discount_pct null · manual · 잠금을 넘는다 · 잠금 자체는 남는다) · 부르는 곳: so_create · so_header_update · so_reprice · so_merge · so_line 트리거 so_line_order_discount_repick · 직원이 직접 부를 수 없다(revoke · definer 창구 안에서만)';

-- ═══ 7) so_line 트리거 — 줄이 바뀌면 다시 고르기(판정 311) ═══
create function public.so_line_order_discount_repick() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  perform public.so_order_discount_apply(coalesce(new.so_id, old.so_id));
  return null;
end;
$$;
revoke all on function public.so_line_order_discount_repick() from public, anon;
comment on function public.so_line_order_discount_repick() is 'so_line AFTER INSERT · DELETE · UPDATE OF qty_ordered · unit_price · free_reason · qty_removed(값이 실제로 바뀔 때만 · WHEN) — 그 오더의 오더 할인을 다시 고른다(so_order_discount_apply · draft ∧ source ≠ manual ∧ 잠기지 않음 · dsc-3a 판정 311) · 어느 창구로 줄이 바뀌든 한 자리 · 줄 100 = 다시 고르기 100(≈ 3 ms 씩) · definer(직원이 so_line 에 직접 쓰는 길은 없다 · 창구 안에서 돈다)';
create trigger so_line_order_discount_repick_id after insert or delete on public.so_line
  for each row execute function public.so_line_order_discount_repick();
create trigger so_line_order_discount_repick_u after update of qty_ordered, unit_price, free_reason, qty_removed on public.so_line
  for each row when ((old.qty_ordered, old.unit_price, old.free_reason, old.qty_removed) is distinct from (new.qty_ordered, new.unit_price, new.free_reason, new.qty_removed))
  execute function public.so_line_order_discount_repick();

-- ═══ 8) 딜이 바뀌면 열린 오더에 「다시 매기기 권함」(판정 286 · 313) ═══
create function public.so_deal_flag_open_orders(p_deal_id uuid, p_from date, p_to date, p_customer boolean)
  returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_n int;
begin
  update public.so s set reprice_suggested_at = now()
  where s.status in ('draft', 'confirmed') and s.reprice_suggested_at is null
    and (p_from is null or p_from <= s.order_date) and (p_to is null or p_to >= s.order_date)
    and (not p_customer or public.so_deal_customer_ok(p_deal_id, s.customer_id, s.price_tier_id));
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;
revoke all on function public.so_deal_flag_open_orders(uuid, date, date, boolean) from public, anon, authenticated;
comment on function public.so_deal_flag_open_orders(uuid, date, date, boolean) is '딜이 바뀌었을 때 열린 오더(draft · confirmed)에 reprice_suggested_at 을 세운다(dsc-3a · 판정 286 · 313) — 기간(오더 날짜) ∧ (p_customer 면) 손님 조건 · 이미 세워진 오더는 그대로 · 제품까지 보지 않는다(가끔 지나치게 걸려도 빠뜨리지 않는 쪽) · 트리거 so_deal_changed · so_deal_part_changed 가 부른다 · 직원이 직접 부를 수 없다';
create function public.so_deal_changed() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    if old.is_active then perform public.so_deal_flag_open_orders(old.id, old.date_from, old.date_to, false); end if;    -- 딜이 사라지면 손님 조건도 없다 — 기간만
    return null;
  end if;
  if tg_op = 'UPDATE' and old.is_active then perform public.so_deal_flag_open_orders(old.id, old.date_from, old.date_to, true); end if;   -- 옛 기간(끄거나 기간을 줄였을 때 그 안의 오더)
  if new.is_active then perform public.so_deal_flag_open_orders(new.id, new.date_from, new.date_to, true); end if;                         -- 새 기간
  return null;
end;
$$;
revoke all on function public.so_deal_changed() from public, anon;
comment on function public.so_deal_changed() is 'so_deal AFTER INSERT · DELETE · UPDATE(WHEN is_active · date_from · date_to · is_order_level · kind 가 바뀔 때) — 옛 기간(켜져 있었으면) 과 새 기간(켜져 있으면)의 열린 오더에 다시 매기기 권함(dsc-3a · 판정 313) · 적재 upsert 가 값을 안 바꾸면 WHEN 이 걸러 아무 오더도 안 건드린다';
create trigger so_deal_changed_id after insert or delete on public.so_deal for each row execute function public.so_deal_changed();
create trigger so_deal_changed_u after update on public.so_deal
  for each row when ((old.is_active, old.date_from, old.date_to, old.is_order_level, old.kind) is distinct from (new.is_active, new.date_from, new.date_to, new.is_order_level, new.kind))
  execute function public.so_deal_changed();
create function public.so_deal_part_changed() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_ids uuid[];
  d     public.so_deal%rowtype;
  v_cust boolean := tg_table_name <> 'so_deal_customer_rule';                                                      -- 판정 313: 손님 조건 표가 바뀌면 기간만 보고 전부
begin
  if tg_table_name = 'so_deal_target' then
    select array_agg(distinct l.deal_id) into v_ids from public.so_deal_line l
     where l.id in (case when tg_op <> 'INSERT' then old.line_id end, case when tg_op <> 'DELETE' then new.line_id end);
  else
    select array_agg(distinct x) into v_ids from unnest(array[case when tg_op <> 'INSERT' then old.deal_id end, case when tg_op <> 'DELETE' then new.deal_id end]) x where x is not null;
  end if;
  for d in select * from public.so_deal where id = any (coalesce(v_ids, '{}')) and is_active loop
    perform public.so_deal_flag_open_orders(d.id, d.date_from, d.date_to, v_cust);
  end loop;
  return null;
end;
$$;
revoke all on function public.so_deal_part_changed() from public, anon;
comment on function public.so_deal_part_changed() is 'so_deal_tier · so_deal_line · so_deal_target · so_deal_customer_rule AFTER INSERT · DELETE · UPDATE(WHEN 뜻 있는 칸) — 그 딜(옛 · 새 deal_id · target 은 줄을 거쳐)이 켜져 있으면 열린 오더에 다시 매기기 권함(dsc-3a · 판정 313) · 손님 조건 표의 변경은 손님 조건을 보지 않는다(빠진 손님을 놓치지 않게)';
create trigger so_deal_tier_changed_id after insert or delete on public.so_deal_tier for each row execute function public.so_deal_part_changed();
create trigger so_deal_tier_changed_u  after update on public.so_deal_tier for each row
  when ((old.deal_id, old.min_amount, old.pct) is distinct from (new.deal_id, new.min_amount, new.pct)) execute function public.so_deal_part_changed();
create trigger so_deal_line_changed_id after insert or delete on public.so_deal_line for each row execute function public.so_deal_part_changed();
create trigger so_deal_line_changed_u  after update on public.so_deal_line for each row
  when ((old.deal_id, old.pct, old.min_qty_mode, old.min_qty) is distinct from (new.deal_id, new.pct, new.min_qty_mode, new.min_qty)) execute function public.so_deal_part_changed();
create trigger so_deal_target_changed_id after insert or delete on public.so_deal_target for each row execute function public.so_deal_part_changed();
create trigger so_deal_target_changed_u  after update on public.so_deal_target for each row
  when ((old.line_id, old.kind, old.target, old.tag, old.brand_id, old.product_id, old.category_id) is distinct from (new.line_id, new.kind, new.target, new.tag, new.brand_id, new.product_id, new.category_id)) execute function public.so_deal_part_changed();
create trigger so_deal_customer_rule_changed_id after insert or delete on public.so_deal_customer_rule for each row execute function public.so_deal_part_changed();
create trigger so_deal_customer_rule_changed_u  after update on public.so_deal_customer_rule for each row
  when ((old.deal_id, old.kind, old.target, old.customer_id, old.warehouse_id, old.tier_id) is distinct from (new.deal_id, new.kind, new.target, new.customer_id, new.warehouse_id, new.tier_id)) execute function public.so_deal_part_changed();

-- ═══ 9) so_create 재발행 — 마지막 정의 20260925142307:18~113 · 판정 308(바뀐 줄: 할인 굳히기 블록 → helper) ═══
create or replace function public.so_create(
  p_customer_id uuid,
  p_channel     text default 'warehouse',
  p_intake      text default 'manual',
  p_location_id uuid default null,
  p_comments    text default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_so     public.so%rowtype;
  v_copy   jsonb;
  v_warn   text[] := '{}';
  od       record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 유일한 문 — 첫 줄
  v_staff := public.so_current_staff();

  if p_channel is null or p_channel not in ('warehouse', 'pos', 'counter') then                       -- ④a2: 길 셋(6-b)
    raise exception 'Channel % is not one of warehouse, pos, counter — nothing was saved', coalesce(p_channel, 'null');
  end if;
  if p_intake is null or p_intake not in ('manual', 'csv', 'pos') then
    raise exception 'Intake % is not accepted here — manual, csv or pos (shopify is another path) — nothing was saved', coalesce(p_intake, 'null');
  end if;
  if (p_channel = 'pos') <> (p_intake = 'pos') then                                                     -- ④a2 ⬜3: pos ⇔ intake pos · counter → manual
    raise exception 'Channel % goes with intake % — a pos order has intake pos, a counter order has intake manual — nothing was saved', p_channel, p_intake;
  end if;
  if p_channel in ('pos', 'counter') and p_location_id is null then                                     -- ④a2 ⬜3: 계산대·선반이 있는 창고
    raise exception 'A % order needs the store warehouse (p_location_id) — nothing was saved', p_channel;
  end if;

  select * into c from public.customer where id = p_customer_id;
  if not found then
    raise exception 'Customer not found — nothing was saved';
  end if;
  if not c.is_active then                                       -- 판정 A — 막는다
    raise exception 'Customer % is inactive — reactivate it first — nothing was saved', c.name;
  end if;
  if c.currency_id is null then
    raise exception 'Customer % has no currency — set it on the customer first — nothing was saved', c.name;
  end if;

  if p_location_id is not null then
    select * into v_wh from public.ref_warehouse where id = p_location_id;
    if not found then
      raise exception 'Warehouse not found — nothing was saved';
    end if;
    if not v_wh.is_active then
      raise exception 'Warehouse % is inactive — nothing was saved', v_wh.name;
    end if;
  end if;

  -- so 한 행 — so_number 는 기본값 so_next_number() · status 기본 draft(so_status_guard 가 insert 를 본다) · currency 는 손님 것(so_copy_customer 가 다시 덮는다)
  insert into public.so (customer_id, channel, intake, currency_id, location_id, location_name, comments, created_by, updated_by)
  values (c.id, p_channel, p_intake, c.currency_id, v_wh.id, v_wh.name, nullif(trim(p_comments), ''), v_staff, v_staff)
  returning * into v_so;

  -- 손님 값 복사(①a · 준 창고가 있으면 그대로 · 없으면 손님 default_location) — 티어는 손님 기본(판정 B ①)
  v_copy := public.so_copy_customer(v_so.id, c.id);

  -- 오더 전체 할인(D6 · ⬜4) — 손님·오더 날짜로 찾아 굳힌다(source deal) · 없으면 null 셋 · dsc-3a 판정 308: 굳히는 일은 so_order_discount_apply 한 곳(줄이 없어 금액 단계는 줄이 들어오며 트리거가 고른다)
  v_so := public.so_order_discount_apply(v_so.id, v_staff);

  select array_agg(t.v) into v_warn from jsonb_array_elements_text(v_copy->'warnings') as t(v);
  v_warn := coalesce(v_warn, '{}') || public.so_tier_warnings(v_so);

  return jsonb_build_object(
    'id',            v_so.id,
    'so_number',     v_so.so_number,
    'status',        v_so.status,
    'channel',       v_so.channel,
    'intake',        v_so.intake,
    'customer_id',   v_so.customer_id,
    'currency_code', v_so.currency_code,
    'price_tier',    v_so.price_tier,
    'price_tier_id', v_so.price_tier_id,
    'location_id',   v_so.location_id,
    'location_name', v_so.location_name,
    'order_discount_pct',     v_so.order_discount_pct,
    'order_discount_deal_id', v_so.order_discount_deal_id,
    'tax_rule',      v_so.tax_rule,
    'tax_rule_id',   v_so.tax_rule_id,
    'tax_rule_manual', v_so.tax_rule_manual,
    'ship_to_is_company', v_copy->'ship_to_is_company',
    'warnings',      to_jsonb(v_warn));
end;
$$;

-- ═══ 10) so_header_update 재발행 — 마지막 정의 20260924175014:400~604 · 판정 308 · 312(바뀐 줄: 다시 찾기 두 갈래 → helper) ═══
create or replace function public.so_header_update(p_so_id uuid, p_patch jsonb) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_keys  constant text[] := array[
    'customer_id', 'location_id', 'payment_term_id', 'discount_pct', 'tax_rule', 'price_tier',
    'order_date', 'required_by', 'ref', 'comments', 'shipping_notes', 'carrier', 'tracking_number',
    'bill_to_name', 'bill_to_line1', 'bill_to_line2', 'bill_to_city', 'bill_to_state_province', 'bill_to_postal_code', 'bill_to_country',
    'ship_to_company', 'ship_to_contact', 'ship_to_phone', 'ship_to_line1', 'ship_to_line2', 'ship_to_city', 'ship_to_state_province', 'ship_to_postal_code', 'ship_to_country',
    'order_discount_pct'];
  v_staff uuid;
  v_so    public.so%rowtype;
  v_key   text;
  v_bad   text;
  v_n_lines int;  v_n_charges int;
  c       public.customer%rowtype;
  v_wh    public.ref_warehouse%rowtype;
  v_pt    public.ref_payment_term%rowtype;
  v_tier  public.ref_price_tier%rowtype;
  v_disc  numeric;
  v_od    numeric;
  od      record;
  v_reprice boolean := false;
  v_warn  text[] := '{}';
  v_n     int;
  v_prev_c text;  v_prev_s text;                              -- 세금 ② — 바뀌기 전 배송지 나라·주(판정 7)
  v_tax   jsonb;  v_tw text[];
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;
  select k into v_bad from jsonb_object_keys(p_patch) k where k <> all (c_keys) limit 1;
  if v_bad is not null then
    raise exception 'Unknown field % — nothing was saved', v_bad;
  end if;
  if p_patch = '{}'::jsonb then
    raise exception 'Nothing to change — nothing was saved';
  end if;

  select count(*) into v_n_lines   from public.so_line   where so_id = p_so_id;
  select count(*) into v_n_charges from public.so_charge where so_id = p_so_id;

  -- 손님 바꾸기(⬜6) — 줄·운임이 있으면 거부 · 비활성 거부(판정 A) · so_copy_customer 가 다시 굳힌다(창고는 이미 있으면 그대로)
  if p_patch ? 'customer_id' then
    if v_n_lines + v_n_charges > 0 then
      raise exception 'Remove all lines and charges before changing the customer — nothing was saved';
    end if;
    select * into c from public.customer where id = nullif(p_patch->>'customer_id', '')::uuid;
    if not found then
      raise exception 'Customer not found — nothing was saved';
    end if;
    if not c.is_active then
      raise exception 'Customer % is inactive — reactivate it first — nothing was saved', c.name;
    end if;
    perform public.so_copy_customer(p_so_id, c.id);
    select * into v_so from public.so where id = p_so_id;
  end if;

  -- 창고 — 준 값 검사(null 이면 비운다)
  if p_patch ? 'location_id' then
    if jsonb_typeof(p_patch->'location_id') = 'null' or p_patch->>'location_id' = '' then
      v_wh := null;
    else
      select * into v_wh from public.ref_warehouse where id = (p_patch->>'location_id')::uuid;
      if not found then
        raise exception 'Warehouse not found — nothing was saved';
      end if;
      if not v_wh.is_active then
        raise exception 'Warehouse % is inactive — nothing was saved', v_wh.name;
      end if;
    end if;
  end if;

  -- 결제조건 — FK + 원문 짝
  if p_patch ? 'payment_term_id' then
    if jsonb_typeof(p_patch->'payment_term_id') = 'null' or p_patch->>'payment_term_id' = '' then
      v_pt := null;
    else
      select * into v_pt from public.ref_payment_term where id = (p_patch->>'payment_term_id')::uuid;
      if not found then
        raise exception 'Payment term not found — nothing was saved';
      end if;
    end if;
  end if;

  -- 손님 기본 할인 — 0~100 · 이미 들어간 줄의 할인은 따라가지 않는다(넣는 순간 굳힌다 · ⬜5) · 줄이 있으면 reprice_suggested(판정 3)
  if p_patch ? 'discount_pct' then
    v_disc := nullif(p_patch->>'discount_pct', '')::numeric;
    if v_disc is not null and (v_disc < 0 or v_disc > 100) then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    if v_n_lines > 0 then v_warn := array_append(v_warn, 'lines_keep_prices'); v_reprice := true; end if;
  end if;

  -- 티어(판정 B ⑤) — 이름으로 받아 purpose sale · 활성만 · 원문 + FK 짝으로 · 들어간 줄의 가격은 그대로(④ 로 보인다) · 줄이 있으면 reprice_suggested
  if p_patch ? 'price_tier' then
    select * into v_tier from public.ref_price_tier where name = p_patch->>'price_tier';
    if not found then
      raise exception 'Price tier % not found — nothing was saved', p_patch->>'price_tier';
    end if;
    if v_tier.purpose <> 'sale' then
      raise exception 'Price tier % is not a selling tier (purpose %) — nothing was saved', v_tier.name, v_tier.purpose;
    end if;
    if not v_tier.is_active then
      raise exception 'Price tier % is inactive — nothing was saved', v_tier.name;
    end if;
    if v_n_lines > 0 then v_warn := array_append(v_warn, 'lines_keep_prices'); v_reprice := true; end if;
  end if;

  -- 오더 날짜 — 딜 기간의 기준(D7) · 줄이 있으면 reprice_suggested(줄은 그대로 · 판정 3)
  if p_patch ? 'order_date' and v_n_lines > 0 and nullif(p_patch->>'order_date', '')::date is distinct from v_so.order_date then
    v_reprice := true;
  end if;

  -- 오더 전체 할인 — 값이면 manual(0~100 · 0 = 사람이 껐다) · null 이면 다시 찾기(아래)
  if p_patch ? 'order_discount_pct' then
    v_od := nullif(p_patch->>'order_discount_pct', '')::numeric;
    if v_od is not null and (v_od < 0 or v_od > 100) then
      raise exception 'order_discount_pct must be between 0 and 100 — nothing was saved';
    end if;
  end if;

  v_prev_c := v_so.ship_to_country;  v_prev_s := v_so.ship_to_state_province;     -- 세금 ② — 손님을 바꿨으면 이미 새 손님의 배송지(so_copy_customer 가 그 안에서 골랐다)
  update public.so s set
    location_id        = case when p_patch ? 'location_id'     then v_wh.id   else s.location_id end,
    location_name      = case when p_patch ? 'location_id'     then v_wh.name else s.location_name end,
    payment_term_id    = case when p_patch ? 'payment_term_id' then v_pt.id   else s.payment_term_id end,
    payment_term_name  = case when p_patch ? 'payment_term_id' then v_pt.name else s.payment_term_name end,
    discount_pct       = case when p_patch ? 'discount_pct'    then v_disc    else s.discount_pct end,
    price_tier         = case when p_patch ? 'price_tier'      then v_tier.name else s.price_tier end,
    price_tier_id      = case when p_patch ? 'price_tier'      then v_tier.id   else s.price_tier_id end,
    order_date         = case when p_patch ? 'order_date'      then coalesce(nullif(p_patch->>'order_date', '')::date, s.order_date) else s.order_date end,
    required_by        = case when p_patch ? 'required_by'     then nullif(p_patch->>'required_by', '')::date else s.required_by end,
    ref                = case when p_patch ? 'ref'             then nullif(trim(p_patch->>'ref'), '') else s.ref end,
    comments           = case when p_patch ? 'comments'        then nullif(trim(p_patch->>'comments'), '') else s.comments end,
    shipping_notes     = case when p_patch ? 'shipping_notes'  then nullif(trim(p_patch->>'shipping_notes'), '') else s.shipping_notes end,
    carrier            = case when p_patch ? 'carrier'         then nullif(trim(p_patch->>'carrier'), '') else s.carrier end,
    tracking_number    = case when p_patch ? 'tracking_number' then nullif(trim(p_patch->>'tracking_number'), '') else s.tracking_number end,
    bill_to_name           = case when p_patch ? 'bill_to_name'           then nullif(trim(p_patch->>'bill_to_name'), '')           else s.bill_to_name end,
    bill_to_line1          = case when p_patch ? 'bill_to_line1'          then nullif(trim(p_patch->>'bill_to_line1'), '')          else s.bill_to_line1 end,
    bill_to_line2          = case when p_patch ? 'bill_to_line2'          then nullif(trim(p_patch->>'bill_to_line2'), '')          else s.bill_to_line2 end,
    bill_to_city           = case when p_patch ? 'bill_to_city'           then nullif(trim(p_patch->>'bill_to_city'), '')           else s.bill_to_city end,
    bill_to_state_province = case when p_patch ? 'bill_to_state_province' then nullif(trim(p_patch->>'bill_to_state_province'), '') else s.bill_to_state_province end,
    bill_to_postal_code    = case when p_patch ? 'bill_to_postal_code'    then nullif(trim(p_patch->>'bill_to_postal_code'), '')    else s.bill_to_postal_code end,
    bill_to_country        = case when p_patch ? 'bill_to_country'        then nullif(trim(p_patch->>'bill_to_country'), '')        else s.bill_to_country end,
    ship_to_company        = case when p_patch ? 'ship_to_company'        then nullif(trim(p_patch->>'ship_to_company'), '')        else s.ship_to_company end,
    ship_to_contact        = case when p_patch ? 'ship_to_contact'        then nullif(trim(p_patch->>'ship_to_contact'), '')        else s.ship_to_contact end,
    ship_to_phone          = case when p_patch ? 'ship_to_phone'          then nullif(trim(p_patch->>'ship_to_phone'), '')          else s.ship_to_phone end,
    ship_to_line1          = case when p_patch ? 'ship_to_line1'          then nullif(trim(p_patch->>'ship_to_line1'), '')          else s.ship_to_line1 end,
    ship_to_line2          = case when p_patch ? 'ship_to_line2'          then nullif(trim(p_patch->>'ship_to_line2'), '')          else s.ship_to_line2 end,
    ship_to_city           = case when p_patch ? 'ship_to_city'           then nullif(trim(p_patch->>'ship_to_city'), '')           else s.ship_to_city end,
    ship_to_state_province = case when p_patch ? 'ship_to_state_province' then nullif(trim(p_patch->>'ship_to_state_province'), '') else s.ship_to_state_province end,
    ship_to_postal_code    = case when p_patch ? 'ship_to_postal_code'    then nullif(trim(p_patch->>'ship_to_postal_code'), '')    else s.ship_to_postal_code end,
    ship_to_country        = case when p_patch ? 'ship_to_country'        then nullif(trim(p_patch->>'ship_to_country'), '')        else s.ship_to_country end,
    reprice_suggested_at   = case when v_reprice then now() else s.reprice_suggested_at end,
    updated_by         = v_staff
  where s.id = p_so_id and s.status = 'draft'
  returning * into v_so;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;

  -- 오더 전체 할인(D6 · ⬜4) — 값을 받았으면 manual · null 을 받았거나(다시 찾기) 손님·오더 날짜가 바뀌었는데 source 가 manual 이 아니면 so_order_discount 로 다시
  if p_patch ? 'order_discount_pct' and v_od is not null then
    update public.so set order_discount_pct = v_od, order_discount_deal_id = null, order_discount_source = 'manual', updated_by = v_staff
    where id = p_so_id and status = 'draft' returning * into v_so;
  elsif p_patch ? 'order_discount_pct' then
    v_so := public.so_order_discount_apply(p_so_id, v_staff, true);         -- dsc-3a 판정 308 · 312: null = 다시 찾기 — 사람의 뜻이라 manual · 잠금을 넘는다(잠금 자체는 남는다)
  elsif p_patch ? 'customer_id' or p_patch ? 'order_date' then
    v_so := public.so_order_discount_apply(p_so_id, v_staff);               -- dsc-3a 판정 308: manual · 잠긴 오더는 helper 가 그대로 둔다
  end if;

  -- 세금 규칙(세금 ② · 판정 7·8·9) — 배송지의 나라·주 열쇠가 오면 다시 고른다(manual 이었으면 같은 나라·주는 그대로 · 다르면 되돌리고 경고 tax_rule_reset_by_ship_to) ·
  --   열쇠 tax_rule: 활성 sale 규칙 이름 → manual(so_tax_set_manual) · null → manual 을 풀고 배송지로(so_tax_refresh p_clear_manual) · 줄·운임의 tax_rule 은 두 속 함수가 함께 맞춘다
  if p_patch ? 'ship_to_country' or p_patch ? 'ship_to_state_province' then
    v_tax := public.so_tax_refresh(p_so_id, v_staff, v_prev_c, v_prev_s);
    select array_agg(t.v) into v_tw from jsonb_array_elements_text(v_tax->'warnings') as t(v);
    v_warn := v_warn || coalesce(v_tw, '{}');
  end if;
  if p_patch ? 'tax_rule' then
    if nullif(trim(p_patch->>'tax_rule'), '') is null then
      v_tax := public.so_tax_refresh(p_so_id, v_staff, null, null, true);
    else
      v_tax := public.so_tax_set_manual(p_so_id, v_staff, p_patch->>'tax_rule');
    end if;
    select array_agg(t.v) into v_tw from jsonb_array_elements_text(v_tax->'warnings') as t(v);
    v_warn := v_warn || coalesce(v_tw, '{}');
  end if;
  if v_tax is not null then
    select * into v_so from public.so where id = p_so_id;
  end if;

  if v_reprice then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  v_warn := v_warn || public.so_tier_warnings(v_so);
  return jsonb_build_object('so', to_jsonb(v_so), 'tax', v_tax, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 11) so_reprice 재발행 — 마지막 정의 20261006000805:1703~1776 · 판정 308 · 312(바뀐 줄: 오더 할인 블록 → helper · kept 에 잠김 · locked 키) ═══
create or replace function public.so_reprice(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  l         public.so_line%rowtype;
  q         record;
  od        record;
  v_rows    jsonb := '[]'::jsonb;
  v_changed int := 0;
  v_diff    boolean;
  v_old_pct numeric;  v_old_src text;  v_old_deal uuid;
  v_n       int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  for l in select * from public.so_line where so_id = p_so_id order by line_no loop
    if l.combo_line_id is not null then                                                                            -- asm-2b2(묶음 2): 구성품 줄은 값이 없다(0) — 다시 매기기 대상이 아니다 · 콤보 줄은 보통 줄처럼
      v_rows := v_rows || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'kept', true, 'reason', 'combo_component', 'discount_pct', null, 'discount_source', null, 'changed', false);
      continue;
    end if;
    if l.price_override or l.discount_source is not distinct from 'manual' then
      v_rows := v_rows || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'kept', true,
                  'reason', case when l.price_override then 'price_override' else 'manual_discount' end,
                  'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'changed', false);
      continue;
    end if;
    select * into q from public.so_line_quote(v_so, l.product_id, l.qty_ordered);
    v_diff := q.discount_pct is distinct from l.discount_pct or q.discount_source is distinct from l.discount_source or q.deal_line_id is distinct from l.deal_line_id;
    if v_diff then
      update public.so_line set
        discount_pct    = q.discount_pct,
        unit_price      = case when list_price is null then null else list_price * (1 - q.discount_pct / 100) end,
        discount_source = q.discount_source,
        deal_line_id    = q.deal_line_id,
        updated_by      = v_staff
      where id = l.id;
      v_changed := v_changed + 1;
    end if;
    v_rows := v_rows || jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'kept', false,
                'old_discount_pct', l.discount_pct, 'old_discount_source', l.discount_source, 'old_deal_line_id', l.deal_line_id,
                'new_discount_pct', q.discount_pct, 'new_discount_source', q.discount_source, 'new_deal_line_id', q.deal_line_id, 'changed', v_diff);
  end loop;

  -- 오더 전체 할인 — manual 은 덮지 않는다
  v_old_pct := v_so.order_discount_pct;  v_old_src := v_so.order_discount_source;  v_old_deal := v_so.order_discount_deal_id;
  perform public.so_order_discount_apply(p_so_id, v_staff);                 -- dsc-3a 판정 308 · 312: manual · 잠긴 오더(나뉜 가족)는 helper 가 건너뛴다 — 줄 할인은 위에서 다시 매겼다
  update public.so set reprice_suggested_at = null, updated_by = v_staff
  where id = p_so_id and status = 'draft' returning * into v_so;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;

  return jsonb_build_object(
    'so_number', v_so.so_number, 'lines', v_rows, 'changed_lines', v_changed,
    'order_discount', jsonb_build_object(
      'old_pct', v_old_pct, 'old_source', v_old_src, 'old_deal_id', v_old_deal,
      'new_pct', v_so.order_discount_pct, 'new_source', v_so.order_discount_source, 'new_deal_id', v_so.order_discount_deal_id,
      'kept', v_old_src is not distinct from 'manual' or v_so.order_discount_locked_at is not null, 'locked', v_so.order_discount_locked_at is not null,
      'changed', v_so.order_discount_pct is distinct from v_old_pct or v_so.order_discount_deal_id is distinct from v_old_deal));
end;
$$;

-- ═══ 12) so_merge 재발행 — 마지막 정의 20261006000805:1811~2087 · 판정 308 · 312(바뀐 줄: 새 머리 locked_at null · 할인 블록 → helper) ═══
create or replace function public.so_merge(p_so_ids uuid[], p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_head_fields constant text[] := array['ship_to_company','ship_to_contact','ship_to_phone','ship_to_line1','ship_to_line2','ship_to_city','ship_to_state_province','ship_to_postal_code','ship_to_country',
                                         'bill_to_customer_id','bill_to_name','bill_to_line1','bill_to_line2','bill_to_city','bill_to_state_province','bill_to_postal_code','bill_to_country',
                                         'payment_term_id','payment_term_name','price_tier','price_tier_id','tax_rule','tax_rule_id','tax_rule_manual','discount_pct',
                                         'order_discount_pct','order_discount_source','order_discount_deal_id','required_by','ref','comments','intake',
                                         'carrier','tracking_number','shipping_notes','ar_account_code','sale_account_code'];
  v_staff   uuid;
  v_ids     uuid[];
  v_n       int;
  v_today   date := public.ims_today();
  v_old     public.so%rowtype;                       -- 가장 오래된 원본 = 머리(⬜2)
  v_head    public.so%rowtype;                       -- 미리 보기용 가상 머리(order_date = 오늘)
  v_new     public.so%rowtype;
  v_cust    public.customer%rowtype;
  v_numbers text;
  v_any_confirmed boolean;
  v_diffs   jsonb; v_plan jsonb; v_calc_in jsonb; v_hint jsonb; v_pay jsonb; v_sib jsonb; v_sup jsonb; v_charges jsonb;
  v_warn    text[] := '{}';
  v_note    text;
  v_id      uuid;
  v_line_id uuid;
  v_cnt     int;
  v_bo      int := 0; v_reopened int := 0; v_released int := 0; v_moved int := 0; v_lines_n int := 0;
  v_combos  jsonb := '[]'::jsonb;  v_comp_n int := 0;                 -- asm-2b2(묶음 2 · 3): 콤보 줄끼리 합친다(열쇠 + 구성품 모양) · 합친 콤보 줄 아래 구성품을 다시 매단다(합친 콤보 수 × combo_qty · 저장된 combo_qty 로 · 정의가 바뀐 콤보는 열쇠가 갈라 따로 둔다)
  r record;
  e jsonb;
  od record;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  v_staff := public.so_current_staff();

  -- ── 대상 검사 ──
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;
  if coalesce(array_length(p_so_ids, 1), 0) <> coalesce(array_length(v_ids, 1), 0) then raise exception 'The same order is listed twice — nothing was saved'; end if;
  if coalesce(array_length(v_ids, 1), 0) < 2 then raise exception 'A merge needs at least two orders — nothing was saved'; end if;
  perform 1 from public.so s where s.id = any(v_ids) order by s.id for update;
  get diagnostics v_n = row_count;
  if v_n <> array_length(v_ids, 1) then raise exception 'Order not found — nothing was saved'; end if;
  for r in select s.* from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number loop
    if r.status not in ('draft', 'confirmed') then
      raise exception 'Order % is % — only draft or confirmed orders still in IMS can be merged — nothing was saved', r.so_number,
        r.status || case when r.status = 'cancelled' and r.closed_reason = 'merged' then ' (already merged into ' || coalesce((select m.so_number from public.so m where m.id = r.merged_into_id), '?') || ')'
                         when r.status in ('at_wms', 'picking', 'packed') then ' (it is with the warehouse — merge is only possible before release)'
                         else '' end;
    end if;
    if r.channel <> 'warehouse' then raise exception 'Order % is a % order — only warehouse orders can be merged — nothing was saved', r.so_number, r.channel; end if;
  end loop;
  if (select count(distinct s.customer_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders belong to different customers — nothing was saved'; end if;
  if (select count(distinct coalesce(s.location_id::text, '(none)')) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are for different warehouses — change the warehouse first — nothing was saved'; end if;
  if (select count(distinct s.currency_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are in different currencies — nothing was saved'; end if;
  select c.* into v_cust from public.customer c where c.id = (select s.customer_id from public.so s where s.id = v_ids[1]);
  if not v_cust.is_active then raise exception 'Customer % is inactive — nothing was saved', v_cust.name; end if;
  v_any_confirmed := exists (select 1 from public.so s where s.id = any(v_ids) and s.status = 'confirmed');
  if v_any_confirmed then perform public.so_require_role('manager', 'saved'); end if;   -- 판정 5 · R5: 확정 오더의 재고를 푸는 순간 선을 넘는다

  select s.* into v_old from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number limit 1;
  select string_agg(s.so_number, ', ' order by s.order_date, s.so_number) into v_numbers from public.so s where s.id = any(v_ids);

  -- ── 머리 차이(판정 2·7 · 막지 않는다) ──
  select coalesce(jsonb_agg(jsonb_build_object('field', d.f, 'values', d.vals) order by d.f), '[]'::jsonb) into v_diffs
  from (select f, jsonb_agg(jsonb_build_object('so_number', s.so_number, 'value', to_jsonb(s)->f) order by s.order_date, s.so_number) as vals
        from public.so s cross join unnest(c_head_fields) f
        where s.id = any(v_ids)
        group by f having count(distinct coalesce(to_jsonb(s)->f, 'null'::jsonb)) > 1) d;

  -- ── 줄 계획(판정 4 · 고침 ①: 열쇠 = 제품 · 단가 · 정가 · 할인 % · 무상 사유 · override · 부가 셋 — tax_rule 은 열쇠 밖 · 전부 합친 오더 규칙) ──
  with src as (
    select l.*, s.so_number, dense_rank() over (order by s.order_date, s.so_number) as ord,
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'preorder')  as was_preorder,    -- asm-2b2: 콤보 줄의 예약은 구성품에
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'backorder') as was_backorder,
           (l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, v_today)) as deal_ended,
           (select string_agg(cp.sku || ':' || trim_scale(cp.combo_qty)::text, ',' order by cp.sku) from public.so_line cp where cp.combo_line_id = l.id) as combo_sig   -- asm-2b2: 콤보 줄의 구성품 모양(열쇠에 든다 · 보통 줄은 null)
    from public.so_line l join public.so s on s.id = l.so_id
    where s.id = any(v_ids) and l.combo_line_id is null                                                                                  -- asm-2b2: 구성품 줄은 계획에 들지 않는다(콤보 줄을 따라 다시 선다)
  ), grp as (
    select product_id, unit_price, list_price, discount_pct, free_reason, price_override, surcharge_pct, surcharge_amount, surcharge_label, combo_sig,
           min(ord * 100000 + line_no) as first_pos, sum(qty_ordered) as qty, count(*) as n, (array_agg(id order by ord, line_no))[1] as first_line_id,
           (array_agg(sku order by ord, line_no))[1] as sku, (array_agg(product_name order by ord, line_no))[1] as product_name,
           (array_agg(unit order by ord, line_no))[1] as unit, (array_agg(pack_factor order by ord, line_no))[1] as pack_factor,
           (array_agg(comments order by ord, line_no) filter (where comments is not null))[1] as comments,
           bool_or(was_preorder) as was_preorder, bool_or(was_backorder) as was_backorder, bool_or(deal_ended) as deal_ended,
           jsonb_agg(jsonb_build_object('so_number', so_number, 'line_no', line_no, 'line_id', id, 'qty', qty_ordered, 'discount_source', discount_source, 'deal_line_id', deal_line_id,
                                        'was_preorder', was_preorder, 'was_backorder', was_backorder) order by ord, line_no) as sources
    from src
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
  ), numbered as (
    select g.*, row_number() over (order by g.first_pos) as line_no,
           count(*) over (partition by g.product_id) as n_same_product,
           first_value(g.unit_price)     over (partition by g.product_id order by g.first_pos) as p_unit_price,
           first_value(g.list_price)     over (partition by g.product_id order by g.first_pos) as p_list_price,
           first_value(g.discount_pct)   over (partition by g.product_id order by g.first_pos) as p_discount_pct,
           first_value(g.free_reason)    over (partition by g.product_id order by g.first_pos) as p_free_reason,
           first_value(g.price_override) over (partition by g.product_id order by g.first_pos) as p_override,
           first_value(g.surcharge_label) over (partition by g.product_id order by g.first_pos) as p_surcharge_label,
           first_value(g.combo_sig)      over (partition by g.product_id order by g.first_pos) as p_combo_sig
    from grp g
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_no', x.line_no, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'unit', x.unit, 'pack_factor', x.pack_factor,
           'qty', x.qty, 'list_price', x.list_price, 'discount_pct', x.discount_pct, 'unit_price', x.unit_price, 'price_override', x.price_override, 'free_reason', x.free_reason,
           'discount_source', case when x.price_override then null when x.discount_pct is not null then 'manual' else null end,
           'surcharge_pct', x.surcharge_pct, 'surcharge_amount', x.surcharge_amount, 'surcharge_label', x.surcharge_label, 'comments', x.comments,
           'source_lines', x.n, 'sources', x.sources, 'was_preorder', x.was_preorder, 'was_backorder', x.was_backorder, 'deal_ended', x.deal_ended,
           'is_combo', x.combo_sig is not null, 'combo_sig', x.combo_sig, 'first_line_id', x.first_line_id,                                              -- asm-2b2
           'kept_apart', (x.n_same_product > 1),
           'differs_in', case when x.n_same_product > 1 then
              (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array[
                 case when x.unit_price is distinct from x.p_unit_price then 'unit_price' end,
                 case when x.list_price is distinct from x.p_list_price then 'list_price' end,
                 case when x.discount_pct is distinct from x.p_discount_pct then 'discount_pct' end,
                 case when x.free_reason is distinct from x.p_free_reason then 'free_reason' end,
                 case when x.price_override is distinct from x.p_override then 'price_override' end,
                 case when x.surcharge_label is distinct from x.p_surcharge_label then 'surcharge' end,
                 case when x.combo_sig is distinct from x.p_combo_sig then 'combo_definition' end]) k where k is not null)
              else '[]'::jsonb end) order by x.line_no), '[]'::jsonb)
    into v_plan
  from numbered x;
  v_lines_n := coalesce(jsonb_array_length(v_plan), 0);

  -- ── 판정 4 보완 ①: 가상 머리(가장 오래된 원본 + 오늘) 로 다시 견적 ──
  v_head := v_old;
  v_head.order_date := v_today;
  select coalesce(jsonb_agg(jsonb_build_object('line_no', p->'line_no', 'product_id', p->'product_id', 'sku', p->'sku', 'qty', p->'qty', 'unit_price', p->'unit_price', 'discount_pct', p->'discount_pct',
                                               'discount_source', p->'discount_source', 'free_reason', p->'free_reason', 'price_override', p->'price_override')), '[]'::jsonb)
    into v_calc_in from jsonb_array_elements(v_plan) p;
  v_hint := public.so_merge_requote_calc(v_head, v_calc_in);

  -- ── 선결제 대상(옮긴다 · 조사 ③ unique (payment_id, so_id)) ──
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', x.id, 'amount', x.amount, 'method', x.method, 'paid_on', x.paid_on, 'targets', x.targets) order by x.paid_on, x.id), '[]'::jsonb) into v_pay
  from (select p.id, p.amount, p.method, p.paid_on, jsonb_agg(s.so_number order by s.so_number) as targets
        from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active' join public.so s on s.id = o.so_id
        where o.so_id = any(v_ids) group by p.id, p.amount, p.method, p.paid_on) x;

  -- ── 판정 1 로 이어받기에서 빠질 형제(원본의 split 자손 중 열린 백오더가 있는 confirmed 오더) ──
  with recursive d as (
    select s.id, 0 as depth, array[s.id] as path from public.so s where s.id = any(v_ids)
    union all
    select c.id, d.depth + 1, d.path || c.id from d join public.so c on c.split_from_id = d.id where d.depth < 50 and not (c.id = any(d.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'status', s.status, 'split_reason', s.split_reason,
           'open_backorder_lines', (select count(*) from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null)) order by s.so_number), '[]'::jsonb)
    into v_sib
  from d join public.so s on s.id = d.id
  where d.depth > 0 and not (s.id = any(v_ids)) and s.status = 'confirmed'
    and exists (select 1 from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null);

  -- ── 원본이 확정 때 이어받은 남의 백오더 줄(⬜4 · 0-7: confirmed 이고 열린 예약이 없는 줄만 다시 연다 · 나머지는 닫힌 채 + 경고) ──
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
           'taken_by', t.so_number, 'target_status', s.status,
           'reopenable', (s.status = 'confirmed' and not exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null))) order by s.so_number, l.line_no), '[]'::jsonb)
    into v_sup
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_ids) and c.reopened_at is null and c.end_kind = 'superseded';

  -- ── 운임(판정 8: 옮기지 않는다 · 다시 계산한다) ──
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'line_no', c.line_no, 'name', c.name, 'amount', c.amount) order by s.so_number, c.line_no), '[]'::jsonb) into v_charges
  from public.so_charge c join public.so s on s.id = c.so_id where c.so_id = any(v_ids);

  -- ── 경고(막지 않는다) ──
  if jsonb_array_length(v_diffs) > 0 then v_warn := array_append(v_warn, 'head_differs'); end if;
  if jsonb_array_length(v_charges) > 0 then v_warn := array_append(v_warn, 'charges_not_merged'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'was_preorder')::boolean) then v_warn := array_append(v_warn, 'preorder_lines_need_reflag'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'deal_ended')::boolean) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if exists (select 1 from jsonb_array_elements(v_sup) x where not (x->>'reopenable')::boolean) then v_warn := array_append(v_warn, 'superseded_not_reopenable'); end if;
  if v_old.order_date <> v_today and v_lines_n > 0 then v_warn := array_append(v_warn, 'reprice_suggested'); end if;   -- §13 판정 3: 주문일이 바뀌면 줄은 그대로 + 표시 + 경고
  if jsonb_array_length(v_sib) > 0 then v_warn := array_append(v_warn, 'backorder_siblings_stay_open'); end if;      -- 판정 1 · 0-1 대가

  if not p_commit then
    return jsonb_build_object('committed', false, 'orders', to_jsonb(string_to_array(v_numbers, ', ')), 'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today,
                              'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'charges', v_charges,
                              'needs_manager', v_any_confirmed, 'warnings', to_jsonb(v_warn));
  end if;

  -- ── 실행 ① 새 오더(머리 통째 복사 · 위 주석의 칸 표) ──
  v_id := gen_random_uuid();
  v_note := 'Merged from ' || v_numbers;
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_old) || jsonb_build_object(
      'id', v_id, 'so_number', public.so_next_number(), 'status', 'draft', 'order_date', v_today, 'ref', null,
      'comments', case when v_old.comments is null then v_note else v_old.comments || E'\n' || v_note end,
      'split_from_id', null, 'split_reason', null,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null, 'carrier', null, 'tracking_number', null, 'reprice_suggested_at', null, 'order_discount_locked_at', null,
      'created_at', now(), 'created_by', v_staff, 'updated_at', now(), 'updated_by', v_staff));
  select * into v_new from public.so where id = v_id;
  perform public.so_order_discount_apply(v_id, v_staff);                             -- 판정 7 · dsc-3a 판정 308 · 312: 새 머리는 잠기지 않는다 · manual 은 helper 가 그대로 · 줄이 들어오며 so_line 트리거가 금액 단계로 다시 고른다

  -- ── 실행 ② 줄(계획 그대로 · tax_rule = 합친 오더 규칙 · 짝 표) ──
  for e in select p from jsonb_array_elements(v_plan) p order by (p->>'line_no')::int loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by)
    values (v_id, (e->>'line_no')::int, (e->>'product_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
            (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, (e->>'unit_price')::numeric, (e->>'price_override')::boolean, e->>'discount_source', null, e->>'free_reason',
            (e->>'surcharge_pct')::numeric, (e->>'surcharge_amount')::numeric, e->>'surcharge_label', v_new.tax_rule, e->>'comments', v_staff)
    returning id into v_line_id;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select v_line_id, (x->>'line_id')::uuid, v_staff from jsonb_array_elements(e->'sources') x;
    if (e->>'is_combo')::boolean then v_combos := v_combos || jsonb_build_object('line_id', v_line_id, 'first_line_id', e->'first_line_id', 'qty', e->'qty', 'sources', e->'sources'); end if;
  end loop;
  -- asm-2b2(묶음 2): 합친 콤보 줄마다 구성품을 다시 매단다 — 첫 원본 콤보 줄의 구성품(저장된 combo_qty · 정의를 다시 읽지 않는다) · 수량 = 합친 콤보 수 × combo_qty · 값 0 · 줄 번호는 끝에(so_line_add 와 같은 자리) · 짝 표에 원본 구성품 줄도
  for e in select p from jsonb_array_elements(v_combos) p loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by, combo_line_id, combo_qty)
    select v_id, (select coalesce(max(n.line_no), 0) from public.so_line n where n.so_id = v_id) + row_number() over (order by cp.line_no), cp.product_id, cp.sku, cp.product_name, cp.unit, cp.pack_factor, (e->>'qty')::numeric * cp.combo_qty,
           null, null, 0, false, null, null, null, null, null, null, v_new.tax_rule, null, v_staff, (e->>'line_id')::uuid, cp.combo_qty
    from public.so_line cp where cp.combo_line_id = (e->>'first_line_id')::uuid;
    get diagnostics v_cnt = row_count;  v_comp_n := v_comp_n + v_cnt;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select n.id, sc.id, v_staff
    from public.so_line n join jsonb_array_elements(e->'sources') sx on true join public.so_line sc on sc.combo_line_id = (sx->>'line_id')::uuid and sc.product_id = n.product_id
    where n.so_id = v_id and n.combo_line_id = (e->>'line_id')::uuid;
  end loop;
  if v_old.order_date <> v_today and v_lines_n > 0 then
    update public.so set reprice_suggested_at = now(), updated_by = v_staff where id = v_id;
  end if;

  -- ── 실행 ③ 원본의 열린 백오더 줄 → 장부 merged + 예약 closed(0-4) · asm-2b2: 수요 줄 단위(콤보 줄은 구성품 예약을 콤보 수로 · 장부는 콤보 줄에 · 구성품 예약 함께 닫힘) ──
  for r in
    select x.id as so_line_id, q.qty_open, q.ids as reserve_ids
    from public.so_line x
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, array_agg(res.id) as ids
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = x.id or cp.combo_line_id = x.id) and res.released_at is null and res.kind = 'backorder') q
    where x.so_id = any(v_ids) and x.combo_line_id is null and q.qty_open is not null
  loop
    perform public.so_backorder_record(r.so_line_id, 'merged', r.qty_open, 0, 0, null, null, v_staff, 'Merged into ' || v_new.so_number);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = any(r.reserve_ids);
    v_bo := v_bo + 1;
  end loop;

  -- ── 실행 ④ 원본이 이어받은 남의 줄 다시 열기(⬜4 · confirmed 이고 열린 예약 없는 줄만 · so_backorder_reopen 과 같은 모양) ──
  for r in select (x->>'close_id')::uuid as close_id, (x->>'reopenable')::boolean as ok from jsonb_array_elements(v_sup) x loop
    if r.ok then
      update public.so_backorder_close set reopened_at = now(), reopened_by = v_staff, updated_by = v_staff where id = r.close_id and reopened_at is null;
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
      select c.so_line_id, c.qty_open, 'backorder', null from public.so_backorder_close c where c.id = r.close_id;
      v_reopened := v_reopened + 1;
    end if;
  end loop;

  -- ── 실행 ⑤ 원본의 남은 열린 예약(allocated · preorder · hold) 풀기 → released(트리거가 reason 을 넣는다 · ⬜5) ──
  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_ids);
  get diagnostics v_released = row_count;

  -- ── 실행 ⑥ 원본 닫기(한 문장 · so_merge_reason_ck 양방향 · so_closed_at_ck) ──
  update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = v_id, closed_at = now(), closed_note = 'Merged into ' || v_new.so_number, cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_ids) and status in ('draft', 'confirmed');
  get diagnostics v_cnt = row_count;
  if v_cnt <> array_length(v_ids, 1) then
    raise exception 'Not every order could be merged — one may have been changed by someone else just now — nothing was saved';
  end if;

  -- ── 실행 ⑦ 선결제 대상 옮기기(원본 행은 기록으로 · 합친 오더 행 하나) ──
  insert into public.so_payment_order (payment_id, so_id, created_by)
  select distinct o.payment_id, v_id, v_staff
  from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active'
  where o.so_id = any(v_ids)
  on conflict on constraint so_payment_order_uq do nothing;
  get diagnostics v_moved = row_count;

  return jsonb_build_object('committed', true, 'so_id', v_id, 'so_number', v_new.so_number, 'status', 'draft', 'orders', to_jsonb(string_to_array(v_numbers, ', ')),
                            'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today, 'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint,
                            'payments_moved', v_moved, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'superseded_reopened', v_reopened,
                            'backorder_lines_recorded', v_bo, 'reserves_released', v_released, 'charges', v_charges, 'component_lines', v_comp_n, 'warnings', to_jsonb(v_warn));   -- asm-2b2: 다시 매단 구성품 줄 수
end;
$$;

-- ═══ 13) so_split 재발행 — 마지막 정의 20261005195104:1017~1107 · 판정 312(바뀐 줄: 모체 잠금 · 형제 잠금) ═══
create or replace function public.so_split(p_so_id uuid, p_reason text, p_moves jsonb, p_target_status text, p_staff uuid) returns public.so
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_new    public.so%rowtype;
  v_base   text;
  v_max    text;
  v_num    text;
  v_id     uuid := gen_random_uuid();
  m        record;
  l        public.so_line%rowtype;
  v_next   int := 0;
  v_n      int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if p_reason not in ('stock_short','warehouse','preorder','manual','pick_short') then                       -- ③a′ 2026-09-24: pick_short(출하 차이 · so_ship) — CHECK so_split_reason_ck 와 같은 다섯
    raise exception 'split_reason % is not one of stock_short, warehouse, preorder, manual, pick_short — nothing was saved', p_reason;
  end if;
  if p_target_status not in ('draft','confirmed') then
    raise exception 'A split order can only be born draft or confirmed — nothing was saved';
  end if;
  if coalesce(jsonb_array_length(p_moves), 0) = 0 then
    raise exception 'Nothing to split off — nothing was saved';
  end if;

  -- 번호 — base(접미어를 뗀 것)로 잠그고 그 base 의 접미어 최댓값 다음 글자 하나(5-d · PO 20260924001820:278~370 과 같은 자리 · cancelled·merged 도 센다 — 글자는 다시 쓰지 않는다)
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('so:' || v_base));
  select max(substring(s.so_number from length(v_base) + 1)) into v_max
  from public.so s where s.so_number ~ ('^' || v_base || '[a-z]$');
  if v_max is null then
    v_num := v_base || 'a';
  elsif v_max >= 'x' then
    raise exception 'Order % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_so.so_number, v_max;
  else
    v_num := v_base || chr(ascii(v_max) + 1);
  end if;

  -- 머리 통째 복사(칸이 늘어도 따라온다) — draft 로 태어난다(문지기 · 이견 4) · 닫힘·창고·출하·되돌리기 흔적은 비운다 · 확정 흔적은 target 이 confirmed 일 때 아래 update 에서 물려받는다
  update public.so set order_discount_locked_at = coalesce(order_discount_locked_at, now()) where id = p_so_id;   -- dsc-3a 판정 312: 모체부터 잠근다(아래 줄 옮기기가 so_line 트리거를 깨운다)
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_so) || jsonb_build_object(
      'id', v_id, 'so_number', v_num, 'status', 'draft', 'order_discount_locked_at', coalesce(v_so.order_discount_locked_at, now()),
      'split_from_id', v_so.id, 'split_reason', p_reason,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null,
      'created_at', now(), 'created_by', p_staff, 'updated_at', now(), 'updated_by', p_staff));

  -- 줄 옮기기(모체 line_no 순 · 형제 line_no 1부터)
  for m in
    select (e->>'line_id')::uuid as line_id, (e->>'qty')::numeric as qty
    from jsonb_array_elements(p_moves) e
    join public.so_line x on x.id = (e->>'line_id')::uuid
    order by x.line_no
  loop
    select * into l from public.so_line where id = m.line_id and so_id = p_so_id;
    if not found then raise exception 'Line % is not on order % — nothing was saved', m.line_id, v_so.so_number; end if;
    if m.qty is null or m.qty <= 0 then raise exception 'Split quantity for line % must be positive — nothing was saved', l.line_no; end if;
    v_next := v_next + 1;
    if m.qty >= l.qty_ordered then
      update public.so_line set so_id = v_id, line_no = v_next, updated_by = p_staff where id = l.id;                       -- 통째 — 행이 간다(id 그대로)
    else
      update public.so_line set qty_ordered = qty_ordered - m.qty, updated_by = p_staff where id = l.id;                    -- 일부 — 원래 줄을 줄이고
      insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped,
                                  list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                  surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, split_from_line_id, updated_by, combo_line_id, combo_qty)
      values (v_id, v_next, l.product_id, l.sku, l.product_name, l.unit, l.pack_factor, m.qty, 0,
              l.list_price, l.discount_pct, l.unit_price, l.price_override, l.discount_source, l.deal_line_id, l.free_reason,
              l.surcharge_pct, l.surcharge_amount, l.surcharge_label, l.tax_rule, l.comments, l.id, p_staff, l.combo_line_id, l.combo_qty);   -- 형제에 새 줄 · 계보 · asm-2a: 콤보 매듭 두 칸도
    end if;
  end loop;
  -- asm-2a(판정 244 · 묶음 4): 일부만 간 콤보의 구성품 줄은 형제에 새로 선 콤보 줄에 다시 매단다(통째로 간 줄은 id 그대로라 매듭도 그대로) · 매듭 검사는 deferred 트리거라 문장 끝에 본다
  update public.so_line c set combo_line_id = n.id
    from public.so_line n
   where c.so_id = v_id and c.combo_line_id is not null and n.so_id = v_id and n.combo_line_id is null and n.split_from_line_id = c.combo_line_id;

  if p_target_status = 'confirmed' then
    update public.so set status = 'confirmed', confirmed_at = v_so.confirmed_at, confirmed_by = v_so.confirmed_by, updated_by = p_staff
    where id = v_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not saved — nothing was saved', v_num; end if;
  end if;

  select * into v_new from public.so where id = v_id;
  return v_new;
end;
$$;

-- ═══ 14) so_detail 재발행 — 마지막 정의 20261005195104:714~804 · 판정 310 · 311(바뀐 줄: lines_total → so_lines_total · 경고 order_discount_rule_now_better · 키 order_discount_rule) ═══
create or replace function public.so_detail(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_cust     text;
  v_lines    jsonb;
  v_charges  jsonb;
  v_lines_n  int;  v_no_price int;  v_free int;  v_charges_n int;  v_deal_ended int;
  v_lines_total numeric;  v_charges_total numeric;  v_od_amt numeric;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;                            -- surcharge-2a — so_tax_preview totals 에서 읽는다(식 한 곳 · basis 를 따라간다)
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
  v_bal      jsonb;                                            -- ⓑ2 — 청구처 손님 잔액(그 통화 행)
  v_rule     record;  v_rule_j jsonb;                          -- dsc-3a 판정 311 — manual 인데 규칙 쪽이 더 크면 경고
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'is_combo', exists (select 1 from public.so_line c where c.combo_line_id = l.id),                                                           -- asm-2a(묶음 2 · 5): 콤보 줄 · 구성품 줄(combo_line_id · combo_qty 는 to_jsonb(l) 에 있다)
                                                              'combo_sku', (select c.sku from public.so_line c where c.id = l.combo_line_id)) order by l.line_no), '[]'::jsonb),
         count(*) filter (where l.combo_line_id is null), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), public.so_lines_total(p_so_id),   -- dsc-3a 판정 310: 기준 금액 식 한 곳
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · ⓑ2: invoiced 값 없음(판정 1)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  v_sc_amt := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);  v_sc_tax := coalesce((v_tax->'totals'->>'surcharge_tax')::numeric, 0);   -- surcharge-2a(묶음 3 · 4)
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
    v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;
  end if;
  select jsonb_build_object('invoice_id', i.id, 'invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'due_on', i.due_on, 'total', i.total,
                            'deposit_applied', i.deposit_applied, 'credit_applied', i.credit_applied, 'balance_forward', i.balance_forward, 'amount_due', i.amount_due,
                            'remaining', public.so_invoice_remaining(i.id), 'paid', i.total - public.so_invoice_remaining(i.id),
                            'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'total', c.total) order by c.credit_number), '[]'::jsonb) from public.so_credit c where c.invoice_id = i.id),
                            'credited_total', (select coalesce(sum(c.total), 0) from public.so_credit c where c.invoice_id = i.id and c.status = 'issued')) into v_inv
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id and o.cancelled_at is null;
  select coalesce(jsonb_agg(jsonb_build_object('invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'cancelled_at', i.cancelled_at) order by i.invoice_number), '[]'::jsonb) into v_inv_hist
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id;
  select to_jsonb(b) into v_bal from public.so_customer_balance(coalesce(v_so.bill_to_customer_id, v_so.customer_id)) b where b.currency_id = v_so.currency_id;   -- ⓑ2: 청구처의 그 통화 잔액(받아 둔 돈 · 예약 · available · 미수)

  v_warn := public.so_tier_warnings(v_so);
  if v_so.tax_rule_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;
  if v_removed > 0 then v_warn := array_append(v_warn, 'lines_removed'); end if;
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(coalesce(v_tax->'warnings', '[]'::jsonb)) as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if v_so.status = 'draft' and v_so.order_discount_source = 'manual' then                                          -- dsc-3a 판정 282 · 311: manual(0 포함)은 그대로 + 규칙 쪽이 더 크면 경고
    select * into v_rule from public.so_order_discount(p_so_id);
    if coalesce(v_rule.pct, 0) > coalesce(v_so.order_discount_pct, 0) then
      v_warn := array_append(v_warn, 'order_discount_rule_now_better');
      v_rule_j := jsonb_build_object('rule_pct', v_rule.pct, 'rule_deal_id', v_rule.deal_id, 'manual_pct', v_so.order_discount_pct);
    end if;
  end if;

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'combo_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and exists (select 1 from public.so_line c where c.combo_line_id = x.id)),
                                 'component_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and x.combo_line_id is not null), 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                        -- surcharge-2a — 물건값 · 오더 할인 기준 밖(묶음 3)
                                 'order_total', v_lines_total - v_od_amt + v_charges_total + v_sc_amt,
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total + v_sc_amt + (v_tax->'totals'->>'tax')::numeric end),
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'order_discount_rule', v_rule_j,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 15) inv_config 설정 키(판정 284 · 314) · inv_config_guard 재발행 — 마지막 정의 20260924153856:350~386(바뀐 줄: 키마다 규칙 갈래 하나) ═══
create or replace function public.inv_config_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare
  v_key   text := coalesce(new.key, old.key);
  v_staff public.ims_staff%rowtype;
begin
  -- dsc-3a 판정 314: 키마다 규칙 — 설정 키(so_invoice_unit_display)는 어휘 검사 + master · 잠긴 키 셋은 아래 종전 규칙(양의 정수 · supervisor)
  if v_key = 'so_invoice_unit_display' then
    if tg_op in ('INSERT', 'UPDATE') and (new.value is null or new.value not in ('both', 'discounted', 'net')) then
      raise exception 'inv_config.so_invoice_unit_display must be one of both, discounted, net (got %) — nothing was saved', coalesce(new.value, 'null');
    end if;
    if current_user = 'authenticated' then
      if not public.ims_can_write('master') then
        raise exception 'Changing % needs the master permission — nothing was saved', v_key;
      end if;
      if tg_op = 'DELETE' then
        raise exception 'inv_config.% cannot be deleted from the app — set it to both instead — nothing was deleted', v_key;
      end if;
      new.updated_at := now();
      new.updated_by := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active);
    end if;
    return case when tg_op = 'DELETE' then old else new end;
  end if;
  if not (v_key = any (public.ims_config_locked_keys())) then
    return case when tg_op = 'DELETE' then old else new end;     -- 잠기지 않은 키 — 종전 그대로(아무것도 안 바꾼다)
  end if;

  -- 값 — 양의 정수만(누가 쓰든 · 스윕은 숫자 아니면 멈추지만 쓰는 순간 막는 편이 낫다)
  if tg_op in ('INSERT', 'UPDATE') then
    if new.value is null or new.value !~ '^[0-9]{1,4}$' or new.value::int <= 0 then
      raise exception 'inv_config.% must be a positive whole number of days (got %) — nothing was saved', v_key, coalesce(new.value, 'null');
    end if;
  end if;

  -- 누가 — authenticated(화면·PostgREST)만 묻는다 · postgres(psql seed · cron) · service_role(GAS · EF) 은 통과
  if current_user = 'authenticated' then
    select * into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff.id is null then
      raise exception 'You are not registered as active staff — nothing was saved';
    end if;
    if coalesce(public.ims_role_rank(v_staff.role), 0) < public.ims_role_rank('supervisor') then
      raise exception 'Changing % needs a supervisor or above (you are %) — this value closes backorder orders for good — nothing was saved', v_key, v_staff.role;
    end if;
    if tg_op = 'DELETE' then
      raise exception 'inv_config.% cannot be deleted from the app — ask an admin to change its value instead — nothing was deleted', v_key;
    end if;
    new.updated_at := now();
    new.updated_by := v_staff.id;
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end;
$$;
comment on function public.inv_config_guard() is 'inv_config BEFORE INSERT · UPDATE · DELETE — 키마다 규칙(dsc-3a · 판정 314): so_invoice_unit_display 는 both · discounted · net 만 + 화면에서는 master 만 · 잠긴 키 셋(ims_config_locked_keys · 백오더 만료 · 재입고 수수료)은 양의 정수 + supervisor 이상 + 삭제 금지 · 그 밖의 키는 종전 그대로 · postgres · service_role 은 값 검사만';
insert into public.inv_config (key, value, note) values ('so_invoice_unit_display', 'both', 'dsc-3a 판정 284 · 314 — 인보이스의 줄 단가 표시: both(할인가 + 실제 단가) · discounted(할인가만) · net(실제 단가만 = unit × (1 − 오더 할인 %/100) · 그릴 때 계산) · 합계는 늘 오더 할인 줄 기준 · 바꾸기는 master')
  on conflict (key) do nothing;

-- ═══ 16) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regclass('public.so_deal_tier') is null or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'so_deal_tier') <> 4 then v_bad := v_bad || ' so_deal_tier'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so_deal' and column_name in ('order_pct', 'customer_scope')) then v_bad := v_bad || ' so_deal_columns'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so' and column_name = 'order_discount_locked_at') then v_bad := v_bad || ' so.locked_at'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_line'::regclass and tgname like 'so_line_order_discount_repick_%') <> 2 then v_bad := v_bad || ' so_line_triggers'; end if;
  if (select count(*) from pg_trigger where tgname like 'so_deal%changed_%') <> 10 then v_bad := v_bad || ' deal_triggers'; end if;
  if to_regprocedure('public.so_lines_total(uuid)') is null or to_regprocedure('public.so_order_discount_apply(uuid, uuid, boolean)') is null or to_regprocedure('public.so_deal_flag_open_orders(uuid, date, date, boolean)') is null then v_bad := v_bad || ' functions'; end if;
  if (select count(*) from public.inv_config where key = 'so_invoice_unit_display' and value = 'both') <> 1 then v_bad := v_bad || ' config_key'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_create', 'so_header_update', 'so_reprice', 'so_merge') and p.prosrc not like '%so_order_discount_apply(%') then v_bad := v_bad || ' helper_callers'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_create', 'so_header_update', 'so_reprice', 'so_merge') and p.prosrc like '%order_discount_source = ''deal''%') then v_bad := v_bad || ' deal_literal_left'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_split(uuid, text, jsonb, text, uuid)');
  if v_src not like '%order_discount_locked_at%' then v_bad := v_bad || ' so_split'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_detail(uuid)');
  if v_src not like '%so_lines_total(p_so_id)%' or v_src not like '%order_discount_rule_now_better%' then v_bad := v_bad || ' so_detail'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and (p.prosrc like '%order_pct%' or p.prosrc like '%customer_scope%')) then v_bad := v_bad || ' old_columns_still_read'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM308', message = format('STOP - dsc-3a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
