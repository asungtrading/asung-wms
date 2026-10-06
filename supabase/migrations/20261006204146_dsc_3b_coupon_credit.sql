-- ─────────────────────────────────────────────────────────────
-- 쿠폰(발행 · 넣기 · 빼기 · 확정에 쓰기 · 되살리기 · 합치기 · 가족) · 크레딧에 오더 할인 반영 (Asung-IMS · dsc-3b · 2026-10-06)
--   정본(뒤에 적는다): so-module §49 — 판정 283 · 285 · 316 ~ 329 · dsc-3b 이견 1 ~ 18
--   판정 321  쓴 것 = so_confirm · so_pos_confirm 끝(so_coupon_settle · 미리 보기는 안 적음) · 가족 = so_family_members · 되살림 = 가족에 confirmed 이상이 하나도 없을 때(so_cancel · so_unconfirm · coupon_restored)
--   판정 322  유효 판정 = so_coupon_check(coupon, so) 한 곳 · 기한은 so.order_date ≤ expires_on(오늘이 아니다 · 세일 기간과 같은 원칙) · apply · so_order_discount · confirm 셋이 같은 식
--   판정 323  짝 CHECK: deal_id ⇔ source in (deal, coupon) · source = coupon ⇒ coupon_id · so_order_discount: 쿠폰 딜(coupon_required)은 so.coupon_id 가 그 딜의 유효한 쿠폰일 때만 · 출처 coupon · 단계 · 손님 조건 AND 그대로
--   판정 324  manual 은 쿠폰을 떼지 않는다(status manual_overrides · Confirm 때 떼고 남김) · 합치기 = 원본 쿠폰 가운데 helper 로 골라 본 % 가 큰 쪽(같으면 오래된 원본) · 나누기 무접촉(머리 복사가 coupon_id 를 가져간다)
--   판정 325  크레딧 = 인보이스 거울 — 인보이스-오더마다 order_discount 음수 줄 하나(−round(Σ제품 환불액 × pct/100, 2) · 세금 따로 · 계정 = 인보이스 order_discount 줄 계정) · so_credit.order_discount_amount · 리스탁킹 피 기준 = 제품 환불액 − 오더 할인 몫 · 이미 낸 크레딧은 그대로
--   판정 326  so_coupon 은 읽기 RLS 만 · 쓰기는 창구만 · 발행 · 무효 master · 넣기 · 빼기 sales
--   판정 327  코드 = [접두-]8글자(23456789ABCDEFGHJKMNPQRSTUVWXYZ) · code(표시) + code_key(so_coupon_key · 대문자 · 공백 · - 제거 · 유일)
--   판정 328  expires_on null = 기한 없음 · 발행 뒤 기한 고치기 없음(무효 + 다시 발행)
--   판정 329  so_detail.coupon {coupon_id · code · deal_name · pct · expires_on · status won|lost|manual_overrides|invalid · reason} · 경고 coupon_not_used · coupon_detached_not_used · coupon_restored
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 여덟은 마지막 정의 바이트 복사 + 바뀐 줄만 · so_order_discount_apply · so_split · so_divide 무접촉 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
--   원칙 1: so_deal.coupon_code(Cin7 원문 칸)는 새 쿠폰과 다르다 — 계산에 쓰지 않는다
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

-- ═══ 1) so_deal.coupon_required(판정 317) · so_coupon 표(판정 326 ~ 328) · so.coupon_id · 짝 CHECK(판정 323) ═══
alter table public.so_deal add column if not exists coupon_required boolean not null default false;
comment on column public.so_deal.coupon_required is '쿠폰이 있어야 걸리는 딜(dsc-3b · 판정 317) — true 면 자동 후보가 아니고 so.coupon_id 가 이 딜의 유효한 쿠폰일 때만(so_order_discount) · 출처 coupon · 오더 딜(is_order_level)에만 뜻이 있다(so_coupon 문지기) · 단계(so_deal_tier) · 손님 조건(so_deal_customer_rule)은 그대로 AND';
comment on column public.so_deal.coupon_code is 'Cin7 에서 불러온 원문 쿠폰 코드 — ⚠️ 계산에 쓰지 않는다(원칙 1 · dsc-3b: IMS 쿠폰은 so_coupon 표 · 다른 것이다) · so_deal_coupon_code_ck 는 다듬기만';
create function public.so_coupon_key(p_code text) returns text
  language sql immutable
as $$ select upper(regexp_replace(coalesce(p_code, ''), '[\s\-]', '', 'g')) $$;
comment on function public.so_coupon_key(text) is '쿠폰 코드 정규화 한 곳(dsc-3b · 판정 327) — 대문자 · 공백 · 하이픈 제거 · so_coupon.code_key(유일) 와 입력 비교에 같이 쓴다';
create table if not exists public.so_coupon (
  id           uuid primary key default gen_random_uuid(),
  code         text not null,
  code_key     text not null,
  deal_id      uuid not null references public.so_deal (id) on delete no action,
  customer_id  uuid not null references public.customer (id) on delete no action,
  expires_on   date,
  issued_at    timestamptz not null default now(),
  issued_by    uuid references public.ims_staff (id) on delete no action,
  used_so_id   uuid references public.so (id) on delete no action,
  used_at      timestamptz,
  voided_at    timestamptz,
  voided_by    uuid references public.ims_staff (id) on delete no action,
  note         text,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  updated_by   uuid references public.ims_staff (id) on delete no action,
  constraint so_coupon_code_ck      check (code = btrim(code) and code <> '' and code = upper(code)),
  constraint so_coupon_key_ck       check (code_key = public.so_coupon_key(code)),
  constraint so_coupon_key_uq       unique (code_key),
  constraint so_coupon_used_pair_ck check ((used_so_id is null) = (used_at is null)),
  constraint so_coupon_void_pair_ck check ((voided_at is null) = (voided_by is null))
);
create index if not exists so_coupon_customer_idx on public.so_coupon (customer_id);
create index if not exists so_coupon_deal_idx     on public.so_coupon (deal_id);
create index if not exists so_coupon_used_so_idx  on public.so_coupon (used_so_id);
create trigger so_coupon_touch before update on public.so_coupon for each row execute function public.ims_touch();
alter table public.so_coupon enable row level security;
create policy so_coupon_select on public.so_coupon for select to authenticated using (true);
grant select on public.so_coupon to authenticated;
comment on table public.so_coupon is '⭐ 쿠폰(dsc-3b · 판정 283 · 326 ~ 328) — 코드 하나 = 손님 한 명 · 한 번 · 오더 전체 할인만(쿠폰 딜 so_deal.coupon_required + so_deal_tier 의 %) · code 표시([접두-]8글자) · code_key 유일(so_coupon_key) · expires_on null = 기한 없음(so.order_date ≤ expires_on 으로 판정 · 판정 322) · used_so_id = 가족 가운데 처음 Confirm 한 오더(so_coupon_settle) · 되살림 = used 둘 null(so_coupon_release · 가족에 confirmed 이상이 없을 때) · voided = 무효(so_coupon_void · 쓰지 않은 것만) · ⚠️ 쓰기 정책 없음 — 창구만(so_coupon_issue · void master · so_coupon_apply · remove sales) · 발행 뒤 기한 고치기 없음(무효 + 다시 발행)';
-- 문지기 — 쿠폰 딜(coupon_required ∧ is_order_level)에만 발행
create function public.so_coupon_deal_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare d public.so_deal%rowtype;
begin
  select * into d from public.so_deal where id = new.deal_id;
  if found and not (d.coupon_required and d.is_order_level) then
    raise exception 'Deal % is not a coupon deal — turn on Coupon required on an order-level deal first — nothing was saved', d.name;
  end if;
  return new;
end;
$$;
revoke all on function public.so_coupon_deal_guard() from public, anon;
create trigger so_coupon_deal_guard before insert or update of deal_id on public.so_coupon for each row execute function public.so_coupon_deal_guard();
alter table public.so add column if not exists coupon_id uuid references public.so_coupon (id) on delete no action;
create index if not exists so_coupon_id_idx on public.so (coupon_id);
comment on column public.so.coupon_id is '오더에 붙은 쿠폰(dsc-3b · 판정 283 · 324) — so_coupon_apply 가 붙이고 so_coupon_remove 가 뗀다 · 붙어 있어도 이긴 것은 order_discount_source = coupon 일 때뿐(진 쿠폰 · manual 이 덮은 쿠폰은 붙은 채 남는다 — 줄이 바뀌면 이길 수 있다) · Confirm 때 이기면 쓴 것으로(so_coupon_settle) · 지면 떼고 남긴다 · 나누기 형제는 머리 복사로 이어받는다(가족 · 판정 319)';
alter table public.so drop constraint so_order_discount_source_ck;
alter table public.so add constraint so_order_discount_source_ck check (order_discount_source is null or order_discount_source in ('deal', 'manual', 'coupon'));
alter table public.so drop constraint so_order_discount_deal_ck;
alter table public.so add constraint so_order_discount_deal_ck check ((order_discount_deal_id is not null) = (order_discount_source in ('deal', 'coupon')));
alter table public.so add constraint so_order_discount_coupon_ck check (order_discount_source is distinct from 'coupon' or coupon_id is not null);
comment on column public.so.order_discount_source is '오더 전체 할인의 출처 — deal(규칙 · deal_id 짝) · coupon(dsc-3b · 쿠폰 딜 · deal_id + coupon_id 짝) · manual(사람이 준 값 · 0 포함 · 자동이 덮지 않는다) · null = 할인 없음(pct 도 null)';

-- ═══ 2) so_coupon_check — 유효 판정 한 곳(판정 322) ═══
create function public.so_coupon_check(p_coupon public.so_coupon, p_so public.so) returns text
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare d public.so_deal%rowtype;
begin
  if p_coupon.id is null then return 'not_found'; end if;
  if p_coupon.customer_id is distinct from p_so.customer_id then return 'other_customer'; end if;
  if p_coupon.voided_at is not null then return 'voided'; end if;
  if p_coupon.used_so_id is not null and p_coupon.used_so_id <> p_so.id
     and not exists (select 1 from public.so_family_members(p_so.id) f where f.so_id = p_coupon.used_so_id) then return 'used_elsewhere'; end if;
  if p_coupon.expires_on is not null and p_so.order_date > p_coupon.expires_on then return 'expired'; end if;
  select * into d from public.so_deal where id = p_coupon.deal_id;
  if not d.coupon_required or not d.is_order_level then return 'deal_not_coupon'; end if;
  if not d.is_active then return 'deal_inactive'; end if;
  return null;
end;
$$;
revoke all on function public.so_coupon_check(public.so_coupon, public.so) from public, anon;
grant execute on function public.so_coupon_check(public.so_coupon, public.so) to authenticated;
comment on function public.so_coupon_check(public.so_coupon, public.so) is '쿠폰이 이 오더에 유효한가 — null = 유효 · 아니면 이유 not_found · other_customer · voided · used_elsewhere(가족 밖 오더가 씀 · so_family_members) · expired(so.order_date > expires_on · 판정 322) · deal_not_coupon · deal_inactive · so_coupon_apply · so_order_discount · so_coupon_settle · so_detail 이 같은 식을 쓴다(dsc-3b)';

-- ═══ 3) so_order_discount 재발행 — 마지막 정의 20261006201443:165~185(dsc-3a) · 판정 317 · 322 · 323(바뀐 줄: 쿠폰 딜 조건 · 출처 coupon) ═══
create or replace function public.so_order_discount(p_so_id uuid)
  returns table (pct numeric, deal_id uuid, source text)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with s as (select o, o.customer_id, o.order_date, o.price_tier_id, o.coupon_id, public.so_lines_total(o.id) as basis from public.so o where o.id = p_so_id),
  best as (
    select t.pct, x.id, x.coupon_required
    from public.so_deal x join public.so_deal_tier t on t.deal_id = x.id cross join s
    where x.is_active and x.is_order_level and x.kind = 'pct'
      and (x.date_from is null or x.date_from <= s.order_date)
      and (x.date_to   is null or x.date_to   >= s.order_date)
      and public.so_deal_customer_ok(x.id, s.customer_id, s.price_tier_id)                                        -- dsc-2 판정 296 · 299: 손님 조건은 so_deal_customer_rule(없으면 전체)
      and t.min_amount <= s.basis                                                                                 -- dsc-3a 판정 282: 걸리는 단계만 · 기준 = 줄 할인 뒤 제품 줄 합계
      and (not x.coupon_required or exists (select 1 from public.so_coupon c where c.id = s.coupon_id and c.deal_id = x.id and public.so_coupon_check(c, s.o) is null))   -- dsc-3b 판정 317 · 322 · 323: 쿠폰 딜은 붙은 쿠폰이 그 딜의 유효한 것일 때만
    order by t.pct desc, x.id, t.tier_no
    limit 1
  )
  select b.pct, b.id, case when b.pct is null then null when b.coupon_required then 'coupon' else 'deal' end
  from (select 1) one
  left join best b on true;
$$;
comment on function public.so_order_discount(uuid) is '오더 전체 할인 하나(D6 · dsc-3b 재발행 2026-10-06 · 판정 277 · 282 · 310 · 317 · 322 · 323) — 켜짐 ∧ is_order_level ∧ kind pct ∧ 기간(오더 날짜) ∧ 손님 조건(so_deal_customer_ok) ∧ 단계 min_amount ≤ so_lines_total ∧ (쿠폰 딜이면 so.coupon_id 가 그 딜의 유효한 쿠폰 · so_coupon_check) → 가장 큰 pct 하나 · 늘 한 행(없으면 null 셋) · source deal | coupon · 쓰는 일은 so_order_discount_apply';

-- ═══ 4) 창구 — 발행(master) · 무효(master) · 넣기 · 빼기(sales) · 정보(so_detail · 창구 반환) · 확정에 쓰기 · 되살리기 ═══
create function public.so_coupon_pct(p_coupon public.so_coupon, p_so public.so) returns numeric
  language sql stable
  set search_path = public, pg_temp
as $$
  select max(t.pct) from public.so_deal_tier t where t.deal_id = p_coupon.deal_id and t.min_amount <= public.so_lines_total(p_so.id)
$$;
revoke all on function public.so_coupon_pct(public.so_coupon, public.so) from public, anon;
grant execute on function public.so_coupon_pct(public.so_coupon, public.so) to authenticated;
comment on function public.so_coupon_pct(public.so_coupon, public.so) is '이 오더의 기준 금액에서 쿠폰 딜이 주는 %(단계 가운데 걸리는 가장 큰 것 · 없으면 null = below_min_amount) — 표시 · 경고용(이긴 것은 so_order_discount 가 정한다 · dsc-3b)';
create function public.so_coupon_detach(p_so_id uuid, p_staff uuid) returns void
  language sql volatile
  set search_path = public, pg_temp
as $$
  update public.so set coupon_id = null,
         order_discount_pct     = case when order_discount_source = 'coupon' then null else order_discount_pct end,
         order_discount_deal_id = case when order_discount_source = 'coupon' then null else order_discount_deal_id end,
         order_discount_source  = case when order_discount_source = 'coupon' then null else order_discount_source end,
         updated_by = coalesce(p_staff, updated_by)
  where id = p_so_id
$$;
revoke all on function public.so_coupon_detach(uuid, uuid) from public, anon, authenticated;
comment on function public.so_coupon_detach(uuid, uuid) is '쿠폰 떼기 한 곳(dsc-3b) — 쿠폰이 이기고 있었으면 오더 할인 셋도 함께 비운다(짝 CHECK so_order_discount_coupon_ck 를 한 문장 안에서 지킨다) · manual · deal 은 그대로 · 부르는 쪽이 다시 고른다(so_order_discount_apply) · so_coupon_remove · so_coupon_void · so_coupon_settle 이 쓴다';
create function public.so_coupon_info(p_so public.so) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare c public.so_coupon%rowtype; v_reason text; v_pct numeric; v_status text;
begin
  if p_so.coupon_id is null then return null; end if;
  select * into c from public.so_coupon where id = p_so.coupon_id;
  v_reason := public.so_coupon_check(c, p_so);
  v_pct := public.so_coupon_pct(c, p_so);
  v_status := case when v_reason is not null then 'invalid'
                   when p_so.order_discount_source = 'coupon' then 'won'
                   when p_so.order_discount_source = 'manual' then 'manual_overrides'
                   else 'lost' end;
  if v_status = 'lost' then v_reason := case when v_pct is null then 'below_min_amount' else 'lower_pct' end; end if;
  if v_status = 'manual_overrides' then v_reason := 'manual'; end if;
  return jsonb_build_object('coupon_id', c.id, 'code', c.code, 'deal_id', c.deal_id, 'deal_name', (select d.name from public.so_deal d where d.id = c.deal_id), 'pct', v_pct, 'expires_on', c.expires_on,
                            'used_so_id', c.used_so_id, 'status', v_status, 'reason', v_reason);
end;
$$;
revoke all on function public.so_coupon_info(public.so) from public, anon;
grant execute on function public.so_coupon_info(public.so) to authenticated;
comment on function public.so_coupon_info(public.so) is '오더에 붙은 쿠폰의 모양(dsc-3b · 판정 329) — null(없음) | {coupon_id · code · deal_id · deal_name · pct(이 기준 금액의 단계 %) · expires_on · used_so_id · status won|lost|manual_overrides|invalid · reason lower_pct|below_min_amount|manual|<so_coupon_check 이유>} · so_detail.coupon · 창구 반환이 쓴다';
create function public.so_coupon_issue(p_deal_id uuid, p_customer_ids uuid[], p_expires_on date default null, p_prefix text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_alpha constant text := '23456789ABCDEFGHJKMNPQRSTUVWXYZ';
  v_staff uuid; d public.so_deal%rowtype; v_prefix text; v_ids uuid[]; v_cid uuid; cu public.customer%rowtype;
  v_code text; v_key text; v_try int; v_bytes bytea; v_out jsonb := '[]'::jsonb; v_cp public.so_coupon%rowtype; i int;
begin
  perform public.ims_require_write('master', 'issued');        -- ⭐ 첫 줄 — 발행은 master(판정 285 · 326)
  v_staff := public.so_current_staff();
  select * into d from public.so_deal where id = p_deal_id;
  if not found then raise exception 'Deal not found — nothing was issued'; end if;
  if not (d.coupon_required and d.is_order_level) then raise exception 'Deal % is not a coupon deal — turn on Coupon required on an order-level deal first — nothing was issued', d.name; end if;
  if p_expires_on is not null and p_expires_on < public.ims_today() then raise exception 'Expiry % is in the past — nothing was issued', p_expires_on; end if;
  v_prefix := nullif(upper(btrim(coalesce(p_prefix, ''))), '');
  if v_prefix is not null and v_prefix !~ '^[A-Z0-9]{2,8}$' then raise exception 'Prefix must be 2 to 8 letters or digits (got %) — nothing was issued', p_prefix; end if;
  select array_agg(distinct x) into v_ids from unnest(coalesce(p_customer_ids, '{}'::uuid[])) x where x is not null;
  if coalesce(array_length(v_ids, 1), 0) = 0 then raise exception 'Pick at least one customer — nothing was issued'; end if;
  foreach v_cid in array v_ids loop
    select * into cu from public.customer where id = v_cid;
    if not found then raise exception 'Customer % not found — nothing was issued', v_cid; end if;
    if not cu.is_active then raise exception 'Customer % is inactive — nothing was issued', cu.name; end if;
    v_try := 0;
    loop
      v_try := v_try + 1;
      v_bytes := decode(replace(gen_random_uuid()::text, '-', ''), 'hex');  v_code := '';                                   -- 코어 난수(pgcrypto 없이) · 16바이트 중 8
      for i in 0..7 loop v_code := v_code || substr(c_alpha, (get_byte(v_bytes, i) % 31) + 1, 1); end loop;
      v_code := case when v_prefix is null then v_code else v_prefix || '-' || v_code end;
      v_key := public.so_coupon_key(v_code);
      exit when not exists (select 1 from public.so_coupon c where c.code_key = v_key);
      if v_try >= 5 then raise exception 'Could not make a unique code after 5 tries — try again — nothing was issued'; end if;
    end loop;
    insert into public.so_coupon (code, code_key, deal_id, customer_id, expires_on, issued_by, updated_by) values (v_code, v_key, d.id, cu.id, p_expires_on, v_staff, v_staff) returning * into v_cp;
    v_out := v_out || jsonb_build_object('coupon_id', v_cp.id, 'customer_id', cu.id, 'customer_name', cu.name, 'code', v_cp.code, 'expires_on', v_cp.expires_on);
  end loop;
  return jsonb_build_object('deal_id', d.id, 'deal_name', d.name, 'issued', jsonb_array_length(v_out), 'coupons', v_out);
end;
$$;
revoke all on function public.so_coupon_issue(uuid, uuid[], date, text) from public, anon;
grant execute on function public.so_coupon_issue(uuid, uuid[], date, text) to authenticated;
comment on function public.so_coupon_issue(uuid, uuid[], date, text) is '⭐ 쿠폰 발행(dsc-3b · 판정 283 · 326 ~ 328) — master · 쿠폰 딜(coupon_required ∧ is_order_level)에 · 손님 여럿 한 번에(손님마다 다른 코드 · 중복 손님은 한 번) · 코드 = [접두-]8글자(23456789ABCDEFGHJKMNPQRSTUVWXYZ · gen_random_uuid 바이트 · 겹치면 다시 5번) · 접두 2~8 영숫자(없으면 접두 없음) · expires_on null = 기한 없음 · 과거 기한 · 꺼진 손님 · 쿠폰 딜 아님 거부 · 반환 {deal_id · deal_name · issued · coupons[{coupon_id · customer_id · customer_name · code · expires_on}]} · definer';
create function public.so_coupon_void(p_code text, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; c public.so_coupon%rowtype; v_n int := 0; r record;
begin
  perform public.ims_require_write('master', 'voided');        -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  select * into c from public.so_coupon where code_key = public.so_coupon_key(p_code);
  if not found then raise exception 'Coupon % not found — nothing was voided', p_code; end if;
  if c.voided_at is not null then raise exception 'Coupon % is already void — nothing was voided', c.code; end if;
  if c.used_so_id is not null then raise exception 'Coupon % was used on order % — a used coupon cannot be voided — nothing was voided', c.code, (select s.so_number from public.so s where s.id = c.used_so_id); end if;
  update public.so_coupon set voided_at = now(), voided_by = v_staff, note = coalesce(nullif(trim(p_note), ''), note), updated_by = v_staff where id = c.id returning * into c;
  for r in select s.id from public.so s where s.coupon_id = c.id and s.status = 'draft' loop                        -- 초안에 붙어 있던 것은 떼고 다시 고른다
    perform public.so_coupon_detach(r.id, v_staff);
    perform public.so_order_discount_apply(r.id, v_staff);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('coupon_id', c.id, 'code', c.code, 'voided_at', c.voided_at, 'detached_from_drafts', v_n);
end;
$$;
revoke all on function public.so_coupon_void(text, text) from public, anon;
grant execute on function public.so_coupon_void(text, text) to authenticated;
comment on function public.so_coupon_void(text, text) is '쿠폰 무효(dsc-3b · 판정 326 · 328) — master · 쓰지 않은 것만 · 초안에 붙어 있었으면 떼고 오더 할인을 다시 고른다 · 반환 {coupon_id · code · voided_at · detached_from_drafts} · 기한을 바꾸려면 무효 + 다시 발행';
create function public.so_coupon_apply(p_so_id uuid, p_code text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_so public.so%rowtype; c public.so_coupon%rowtype; v_reason text; v_old text; v_info jsonb; v_warn text[] := '{}';
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 넣기는 sales(판정 285)
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');
  select * into c from public.so_coupon where code_key = public.so_coupon_key(p_code);
  if not found then raise exception 'Coupon % not found — nothing was saved', p_code; end if;
  v_reason := public.so_coupon_check(c, v_so);
  if v_reason is not null then
    raise exception '%', case v_reason
      when 'other_customer' then format('Coupon %s belongs to another customer — nothing was saved', c.code)
      when 'voided'         then format('Coupon %s is void — nothing was saved', c.code)
      when 'used_elsewhere' then format('Coupon %s was already used on order %s — nothing was saved', c.code, (select s.so_number from public.so s where s.id = c.used_so_id))
      when 'expired'        then format('Coupon %s expired on %s — the order date %s is later — nothing was saved', c.code, c.expires_on, v_so.order_date)
      when 'deal_inactive'  then format('Coupon %s belongs to a deal that is switched off — nothing was saved', c.code)
      else format('Coupon %s cannot be used (%s) — nothing was saved', c.code, v_reason) end;
  end if;
  if v_so.coupon_id is not null and v_so.coupon_id <> c.id then select x.code into v_old from public.so_coupon x where x.id = v_so.coupon_id; end if;
  update public.so set coupon_id = c.id, updated_by = v_staff where id = p_so_id;
  v_so := public.so_order_discount_apply(p_so_id, v_staff);                 -- manual 은 helper 가 그대로(판정 324 · status manual_overrides)
  v_info := public.so_coupon_info(v_so);
  if v_info->>'status' <> 'won' then v_warn := array_append(v_warn, 'coupon_not_used'); end if;
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'coupon', v_info, 'replaced_code', v_old,
                            'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'source', v_so.order_discount_source, 'deal_id', v_so.order_discount_deal_id),
                            'coupon_not_used', case when v_info->>'status' = 'won' then null else jsonb_build_object('coupon_pct', v_info->'pct', 'winner_pct', v_so.order_discount_pct, 'winner_source', v_so.order_discount_source, 'reason', v_info->>'reason') end,
                            'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.so_coupon_apply(uuid, text) from public, anon;
grant execute on function public.so_coupon_apply(uuid, text) to authenticated;
comment on function public.so_coupon_apply(uuid, text) is '⭐ 오더에 쿠폰 넣기(dsc-3b · 판정 283 · 322 · 324 · 329) — sales · 초안만 · so_coupon_check 가 막는 것은 사람이 읽는 말로 거부 · 붙이고 so_order_discount_apply 로 다시 고른다(큰 하나 · manual 은 그대로) · 이미 쿠폰이 있으면 바꾼다(replaced_code) · 지면 코드는 붙은 채 남고 경고 coupon_not_used {coupon_pct · winner_pct · winner_source · reason} · 반환 {so_id · so_number · coupon(so_coupon_info) · replaced_code · order_discount · coupon_not_used · warnings}';
create function public.so_coupon_remove(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_so public.so%rowtype; v_old text;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');
  if v_so.coupon_id is null then raise exception 'Order % has no coupon — nothing was saved', v_so.so_number; end if;
  select x.code into v_old from public.so_coupon x where x.id = v_so.coupon_id;
  perform public.so_coupon_detach(p_so_id, v_staff);
  v_so := public.so_order_discount_apply(p_so_id, v_staff);
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'removed_code', v_old,
                            'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'source', v_so.order_discount_source, 'deal_id', v_so.order_discount_deal_id));
end;
$$;
revoke all on function public.so_coupon_remove(uuid) from public, anon;
grant execute on function public.so_coupon_remove(uuid) to authenticated;
comment on function public.so_coupon_remove(uuid) is '오더에서 쿠폰 빼기(dsc-3b · 판정 283) — sales · 초안만 · 떼고 다시 고른다 · 초안에서 넣었다 뺀 것은 쓴 것이 아니다 · 반환 {so_id · so_number · removed_code · order_discount}';
create function public.so_coupon_settle(p_so_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_so public.so%rowtype; c public.so_coupon%rowtype; v_info jsonb; v_reason text; od record;
begin
  select * into v_so from public.so where id = p_so_id;
  if v_so.coupon_id is null then return null; end if;
  select * into c from public.so_coupon where id = v_so.coupon_id;
  v_info := public.so_coupon_info(v_so);
  if v_so.order_discount_source = 'coupon' and public.so_coupon_check(c, v_so) is null then
    if c.used_so_id is null then
      update public.so_coupon set used_so_id = p_so_id, used_at = now(), updated_by = p_staff where id = c.id;        -- 가족이 이미 썼으면(형제 Confirm) 그대로 · 판정 319 · 321
    end if;
    return jsonb_build_object('code', c.code, 'action', 'used', 'used_so_id', coalesce(c.used_so_id, p_so_id), 'pct', v_so.order_discount_pct);
  end if;
  v_reason := case v_info->>'status' when 'manual_overrides' then 'manual' when 'invalid' then v_info->>'reason' else 'lost_to_deal' end;
  perform public.so_coupon_detach(p_so_id, p_staff);                                                                 -- 진 쿠폰 · manual 이 덮은 쿠폰 · 기한이 지난 쿠폰은 떼고 남긴다(판정 322 · 324)
  if v_so.order_discount_source = 'coupon' then                                                                      -- 골라진 뒤 무효가 된 쿠폰(딜을 껐다 …): 오더 할인을 규칙으로 다시(확정된 오더라 helper 가 아니라 직접)
    select * into od from public.so_order_discount(p_so_id);
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id, order_discount_source = od.source where id = p_so_id;
    select * into v_so from public.so where id = p_so_id;
  end if;
  return jsonb_build_object('code', c.code, 'action', 'detached', 'reason', v_reason, 'coupon_pct', v_info->'pct', 'winner_pct', v_so.order_discount_pct, 'winner_source', v_so.order_discount_source);
end;
$$;
revoke all on function public.so_coupon_settle(uuid, uuid) from public, anon, authenticated;
comment on function public.so_coupon_settle(uuid, uuid) is 'Confirm 끝에서 쿠폰을 정리한다(dsc-3b · 판정 321 · 322 · 324) — 이겼으면(source coupon ∧ 유효) used_so_id = 이 오더(가족이 이미 썼으면 그대로) · 아니면 뗀다(reason manual · lost_to_deal · expired …) · 반환 null | {code · action used|detached · …} · so_confirm · so_pos_confirm 이 부른다(미리 보기는 안 부른다) · 직원이 직접 부를 수 없다';
create function public.so_coupon_release(p_so_ids uuid[], p_staff uuid) returns text[]
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c public.so_coupon%rowtype; v_out text[] := '{}';
begin
  for c in select x.* from public.so_coupon x                                                                       -- 취소 · 되돌린 오더의 가족 누군가가 쓴 쿠폰 전부(형제를 취소해도 모체가 쓴 쿠폰을 본다)
           where x.used_so_id in (select f.so_id from unnest(coalesce(p_so_ids, '{}'::uuid[])) u cross join lateral public.so_family_members(u) f) loop
    if not exists (select 1 from public.so_family_members(c.used_so_id) f
                    where f.status in ('confirmed', 'at_wms', 'picking', 'packed', 'shipped', 'fulfilled')) then                 -- 가족에 confirmed 이상이 하나도 없을 때만(판정 319 · 321)
      update public.so_coupon set used_so_id = null, used_at = null, updated_by = p_staff where id = c.id;
      v_out := array_append(v_out, c.code);
    end if;
  end loop;
  return v_out;
end;
$$;
revoke all on function public.so_coupon_release(uuid[], uuid) from public, anon, authenticated;
comment on function public.so_coupon_release(uuid[], uuid) is '취소 · 되돌리기 뒤 쿠폰 되살리기(dsc-3b · 판정 319 · 321) — 그 오더들의 가족(so_family_members) 누군가가 쓴 쿠폰 가운데 가족에 confirmed 이상이 하나도 없는 것만 used 둘을 비운다 · 반환 되살린 코드들 · so_cancel · so_unconfirm 이 부른다 · 크레딧은 부르지 않는다(판정 283)';

-- ═══ 5) so_confirm 재발행 — 마지막 정의 20260925142307:337~389 · 판정 321(바뀐 줄: 쿠폰 정리 · 반환 coupon) ═══
create or replace function public.so_confirm(
  p_so_id              uuid,
  p_preorder_line_ids  uuid[]  default '{}'::uuid[],   -- 사람이 고른 프리오더 줄(6-d) · 따로 뗀다(R2)
  p_hold               boolean default false,          -- 처음부터 보류로 확정(R3 · 오더 전체 · 재고를 잡지 않고 나누지 않는다)
  p_commit             boolean default true            -- false = 미리 보기(무엇이 할당·백오더·프리오더로 가나)
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  c        public.customer%rowtype;
  v_wh     public.ref_warehouse%rowtype;
  v_bad    text;
  v_n      int;
  v_warn   text[] := '{}';
  v_res    jsonb;
  v_cp     jsonb;                                              -- dsc-3b 판정 321 — 쿠폰 정리
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — manager 이상(R5)
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if v_so.channel <> 'warehouse' then
    raise exception 'Order % is a % order — confirming pos and counter orders comes in a later step — nothing was saved', v_so.so_number, v_so.channel;
  end if;
  if p_hold and coalesce(array_length(p_preorder_line_ids, 1), 0) > 0 then
    raise exception 'Choose either hold (whole order) or preorder lines, not both — nothing was saved';
  end if;

  perform public.so_confirm_precheck(v_so);                    -- R6 막는 조건 — 손님 · 창고 · 줄 · 세금(고침 ② · so_pos_confirm 과 한 곳)
  select string_agg(x::text, ', ') into v_bad
  from unnest(coalesce(p_preorder_line_ids, '{}'::uuid[])) x where not exists (select 1 from public.so_line l where l.id = x and l.so_id = p_so_id);
  if v_bad is not null then
    raise exception 'Preorder line % is not on order % — nothing was saved', v_bad, v_so.so_number;
  end if;

  -- 경고(막지 않는다) — 티어·통화 · 다시 매기기 권고 · 세일 끝난 뒤 넣은 줄
  v_warn := public.so_tier_warnings(v_so);
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if exists (select 1 from public.so_line l where l.so_id = p_so_id and l.deal_line_id is not null
               and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)) then
    v_warn := array_append(v_warn, 'deal_ended_before_line_added');
  end if;

  v_res := public.so_allocate_run(p_so_id, v_so.location_id, p_preorder_line_ids, p_hold, true, p_commit, v_staff);
  if p_commit then                                               -- ③b 판정 4·5·8: 같은 손님·같은 제품의 열린 백오더 줄을 이어받는다(가족 밖 · 브랜치 무관 · 가장 오래된 줄부터 · 나머지는 더 원하지 않음)
    v_res := v_res || jsonb_build_object('superseded', public.so_backorder_supersede(p_so_id, v_staff));
    v_cp := public.so_coupon_settle(p_so_id, v_staff);                                                   -- dsc-3b 판정 321 · 324: 이긴 쿠폰은 쓴 것으로 · 진 쿠폰은 떼고 남김
    if v_cp->>'action' = 'detached' then v_warn := array_append(v_warn, 'coupon_detached_not_used'); end if;
  end if;
  return v_res || jsonb_build_object('coupon', v_cp, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 6) so_pos_confirm 재발행 — 마지막 정의 20260925142307:617~651 · 판정 321(바뀐 줄: 쿠폰 정리 · 반환 coupon) ═══
create or replace function public.so_pos_confirm(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_so    public.so%rowtype;
  v_n     int;
  v_warn  text[] := '{}';
  v_cp    jsonb;                                               -- dsc-3b 판정 321
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 6: POS 는 sales 만(R5 예외)
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');
  if v_so.channel = 'warehouse' then
    raise exception 'Order % is a warehouse order — confirm it with so_confirm — nothing was saved', v_so.so_number;
  end if;
  if v_so.channel = 'counter' then
    perform public.so_require_role('manager', 'saved');        -- ⭐ counter 는 manager 이상(6-b · 판정 12)
  end if;
  perform 1 from public.so s where s.id = p_so_id for update;
  perform public.so_confirm_precheck(v_so);                    -- R6(고침 ② · so_confirm 과 한 곳)

  v_n := public.so_allocate_all(p_so_id, v_staff);            -- 전 줄 allocated · 재고 안 봄 · 이어받기 없음(판정 13)
  update public.so set status = 'confirmed', confirmed_at = now(), confirmed_by = v_staff, updated_by = v_staff
  where id = p_so_id and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not confirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

  v_warn := public.so_tier_warnings(v_so);                     -- 판정 14: intake pos 도 직접 오더 경고
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  v_cp := public.so_coupon_settle(p_so_id, v_staff);                                                     -- dsc-3b 판정 321 · 324(POS 확정 포함)
  if v_cp->>'action' = 'detached' then v_warn := array_append(v_warn, 'coupon_detached_not_used'); end if;
  return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'channel', v_so.channel, 'status', 'confirmed', 'coupon', v_cp,
                            'lines_allocated', (select count(*) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so_id and r.released_at is null and r.kind = 'allocated'),
                            'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 7) so_unconfirm 재발행 — 마지막 정의 20260924145105:295~397 · 판정 321(바뀐 줄: 반환 coupon_restored) ═══
create or replace function public.so_unconfirm(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  s         public.so%rowtype;
  l         public.so_line%rowtype;
  v_next    int;
  v_merged  text[] := '{}';
  v_moved   int := 0;  v_added int := 0;  v_released int := 0;
  v_reopen  jsonb;                                              -- ③b: 이 확정이 이어받아 닫은 남의 백오더 줄
  v_n       int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('supervisor', 'saved');       -- ⭐ 둘째 줄 — supervisor 이상(R9)
  v_staff := public.so_current_staff();

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if v_so.split_from_id is not null and v_so.confirmed_at is not null
     and exists (select 1 from public.so m where m.id = v_so.split_from_id and m.confirmed_at = v_so.confirmed_at) then
    raise exception 'Order % was itself split off at confirmation — unconfirm the original order % instead — nothing was saved',
      v_so.so_number, (select m.so_number from public.so m where m.id = v_so.split_from_id);
  end if;

  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));

  -- ⭐ 사슬로 판정한다 — 시각에만 기대지 않는다(2026-09-24 결함 고침: 한 트랜잭션에서 so_divide 로 난 형제의 created_at 이 confirmed_at 과 같았다)
  if exists (select 1 from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason = 'manual') then
    raise exception 'Order % has a hand-made split order (%) — unconfirm is not possible while it is open (cancel or merge it first) — nothing was saved',
      v_so.so_number, (select string_agg(x.so_number, ', ' order by x.so_number) from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason = 'manual');
  end if;

  -- 형제 검사(자기 행만 보는 것이 아니라 여기서 다른 행을 본다 — RPC 의 일 · 6-g′) · ⭐ 열린 자식만(cancelled = 앞선 되돌리기로 merged 된 것·취소된 것은 무시 · 2026-09-24 결함 고침)
  for s in select * from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason in ('stock_short','preorder') order by x.so_number loop
    if s.created_at is distinct from v_so.confirmed_at then
      raise exception 'Order % was split again after confirmation (%) — unconfirm only undoes the split made at confirmation — nothing was saved', v_so.so_number, s.so_number;
    end if;
    if s.status <> 'confirmed' then
      raise exception 'Split order % is % — it must still be confirmed and in IMS to merge it back — nothing was saved', s.so_number, s.status;
    end if;
    if exists (select 1 from public.so y where y.split_from_id = s.id) then
      raise exception 'Split order % has itself been split again (%) — unconfirm is not possible — nothing was saved',
        s.so_number, (select string_agg(y.so_number, ', ' order by y.so_number) from public.so y where y.split_from_id = s.id);
    end if;
    if s.updated_at is distinct from s.created_at
       or exists (select 1 from public.so_line x where x.so_id = s.id and x.updated_at is distinct from s.created_at)
       or exists (select 1 from public.so_reserve r join public.so_line x on x.id = r.so_line_id where x.so_id = s.id and r.released_at is null and r.updated_at is distinct from s.created_at)   -- 열린 예약만 · 풀린 이력은 무시(2026-09-24 결함 고침 — 돌아온 줄이 옛 풀림을 달고 온다)
       or exists (select 1 from public.so_charge ch where ch.so_id = s.id) then
      raise exception 'Split order % was changed after the split — unconfirm is only possible while the split orders are untouched — nothing was saved', s.so_number;
    end if;
  end loop;

  -- ③b 판정 5·⬜8: 이 확정이 이어받아 닫은 남의 백오더 줄을 다시 연다 — 대상 백오더 오더가 끝 상태(만료·취소)면 거부(판정 11) · 쓰기 전에 먼저(거부면 아무것도 안 쓴다)
  v_reopen := public.so_backorder_reopen(array[p_so_id], v_staff);

  -- 예약 전부 풀기 — 원래(allocated · hold · backorder · preorder) + 형제(backorder · preorder) · 지우지 않는다(5-f)
  update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x
  where x.id = r.so_line_id and r.released_at is null
    and (x.so_id = p_so_id or x.so_id in (select id from public.so where split_from_id = p_so_id and status <> 'cancelled' and split_reason in ('stock_short','preorder')));
  get diagnostics v_released = row_count;

  -- 형제 줄 도로 합치기 · 형제 닫기
  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;
  for s in select * from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason in ('stock_short','preorder') order by x.so_number loop
    for l in select * from public.so_line x where x.so_id = s.id order by x.line_no loop
      if l.split_from_line_id is not null then
        update public.so_line set qty_ordered = qty_ordered + l.qty_ordered, updated_by = v_staff
        where id = l.split_from_line_id and so_id = p_so_id;
        get diagnostics v_n = row_count;
        if v_n <> 1 then raise exception 'Line % of % has lost its original line — nothing was saved', l.line_no, s.so_number; end if;
        v_added := v_added + 1;                                  -- 형제 줄 행은 이력으로 남는다(합계는 merged 문서를 뺀다)
      else
        v_next := v_next + 1;
        update public.so_line set so_id = p_so_id, line_no = v_next, updated_by = v_staff where id = l.id;
        v_moved := v_moved + 1;
      end if;
    end loop;
    update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = p_so_id, closed_at = now(),
                         closed_note = format('Unconfirmed with %s', v_so.so_number), cancelled_by = v_staff, updated_by = v_staff
    where id = s.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not merged back — it may have been changed by someone else just now — nothing was saved', s.so_number; end if;
    v_merged := array_append(v_merged, s.so_number);
  end loop;

  -- 원래 → draft · 되돌리기 기록 · 확정 흔적 비움(다시 확정하면 새로 찍힌다)
  update public.so set status = 'draft', confirmed_at = null, confirmed_by = null, unconfirmed_at = now(), unconfirmed_by = v_staff, updated_by = v_staff
  where id = p_so_id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not unconfirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

  return jsonb_build_object('so_number', v_so.so_number, 'status', 'draft', 'merged', to_jsonb(v_merged),
                            'lines_moved_back', v_moved, 'lines_added_back', v_added, 'reserves_released', v_released,
                            'backorders_reopened', v_reopen, 'coupon_restored', to_jsonb(public.so_coupon_release(array[p_so_id], v_staff)));   -- dsc-3b 판정 321: 가족에 confirmed 이상이 없으면 되살림
end;
$$;

-- ═══ 8) so_cancel 재발행 — 마지막 정의 20261006000805:795~881 · 판정 321(바뀐 줄: 반환 coupon_restored) ═══
create or replace function public.so_cancel(p_so_id uuid, p_note text, p_keep uuid[] default '{}'::uuid[], p_commit boolean default true, p_reopen_superseded boolean default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_note text;  r record;
  v_plan jsonb := '[]'::jsonb;  v_cancel uuid[] := '{}';  v_warn text[] := '{}';  v_released int := 0;  v_n int;
  v_taken jsonb := '[]'::jsonb;  v_taken_n int := 0;  v_reopen jsonb := null;  v_bo int := 0;     -- ③b 판정 10: 이어받은 장부 줄 · 다시 열기 · 취소되는 백오더 줄
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'A cancel needs a reason (p_note) — nothing was saved'; end if;
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status not in ('draft', 'confirmed') then
    raise exception 'Order % is % — only a draft or confirmed order still in IMS can be cancelled (if it went to the warehouse, roll it back in WMS first) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));

  -- 자손(열린 것만) · path 로 「살린 형제 아래」를 가른다
  for r in
    with recursive down as (
      select s.id, s.so_number, s.status, s.split_reason, 0 as depth, array[s.id] as path from public.so s where s.id = p_so_id
      union all
      select c.id, c.so_number, c.status, c.split_reason, down.depth + 1, down.path || c.id
      from down join public.so c on c.split_from_id = down.id
      where down.depth < 50 and not (c.id = any(down.path)) and c.status <> 'cancelled'
    )
    select d.*, (d.path && p_keep) as kept from down d order by d.so_number
  loop
    if r.kept then
      v_plan := v_plan || jsonb_build_object('so_number', r.so_number, 'status', r.status, 'split_reason', r.split_reason, 'action', 'kept');
    elsif r.status not in ('draft', 'confirmed') then
      v_plan := v_plan || jsonb_build_object('so_number', r.so_number, 'status', r.status, 'split_reason', r.split_reason, 'action', 'in_warehouse_untouched');
      v_warn := array_append(v_warn, 'sibling_in_warehouse:' || r.so_number);
    else
      v_plan := v_plan || jsonb_build_object('so_number', r.so_number, 'status', r.status, 'split_reason', r.split_reason, 'action', 'cancel');
      v_cancel := array_append(v_cancel, r.id);
    end if;
  end loop;
  if not (p_so_id = any(v_cancel)) then
    raise exception 'Order % itself is in p_keep — nothing was saved', v_so.so_number;
  end if;
  -- ③b 판정 10: 취소 대상(자손 포함)이 이어받아 닫은 남의 백오더 줄(장부 · 다시 열지 않은 것) — 미리 보기에 목록 · commit 은 p_reopen_superseded 로 사람이 고른다(§7-e 「시스템이 짐작하지 않는다」)
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
                                              'taken_by', t.so_number, 'target_status', s.status) order by s.so_number, l.line_no), '[]'::jsonb), count(*)
    into v_taken, v_taken_n
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_cancel) and c.reopened_at is null;
  if not p_commit then
    return jsonb_build_object('so_number', v_so.so_number, 'committed', false, 'note', v_note, 'orders', v_plan, 'superseded_lines', v_taken, 'warnings', to_jsonb(v_warn));
  end if;
  if v_taken_n > 0 and p_reopen_superseded is null then
    raise exception 'Order % took over % backorder line(s) from earlier orders — choose whether to reopen them (p_reopen_superseded true or false) — nothing was saved', v_so.so_number, v_taken_n;
  end if;
  -- ③b: 취소되는 오더의 열린 백오더 줄은 장부에 cancelled 로 적고 예약을 closed 로 닫는다(아래 일괄 풀기 앞) — 백오더가 조용히 사라지지 않게
  for r in                                                                       -- asm-2b2(묶음 4 · 7): 수요 줄 단위 — 콤보 줄은 구성품 예약을 콤보 수로 세고 장부는 콤보 줄에 · 구성품 예약은 함께 닫힌다
    select x.id as so_line_id, q.qty_open, q.ids as reserve_ids
    from public.so_line x
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, array_agg(res.id) as ids
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = x.id or cp.combo_line_id = x.id) and res.released_at is null and res.kind = 'backorder') q
    where x.so_id = any(v_cancel) and x.combo_line_id is null and q.qty_open is not null
  loop
    perform public.so_backorder_record(r.so_line_id, 'cancelled', r.qty_open, 0, 0, null, null, v_staff, v_note);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = any(r.reserve_ids);
    v_bo := v_bo + 1;
  end loop;
  if v_taken_n > 0 and p_reopen_superseded then                 -- true = so_unconfirm 과 같은 다시 열기 · false = 닫힌 채(손님의 새 답)
    v_reopen := public.so_backorder_reopen(v_cancel, v_staff);
  end if;

  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_cancel);
  get diagnostics v_released = row_count;
  update public.so set status = 'cancelled', closed_reason = 'voided', closed_note = v_note, closed_at = now(), cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_cancel) and status in ('draft', 'confirmed');
  get diagnostics v_n = row_count;
  if v_n <> coalesce(array_length(v_cancel, 1), 0) then
    raise exception 'Not every order could be cancelled — one may have been changed by someone else just now — nothing was saved';
  end if;
  return jsonb_build_object('so_number', v_so.so_number, 'committed', true, 'note', v_note, 'orders', v_plan, 'cancelled', v_n, 'reserves_released', v_released,
                            'backorder_lines_recorded', v_bo, 'superseded_lines', v_taken, 'reopen_superseded', p_reopen_superseded, 'reopened', v_reopen,
                            'coupon_restored', to_jsonb(public.so_coupon_release(v_cancel, v_staff)), 'warnings', to_jsonb(v_warn));   -- dsc-3b 판정 321: 취소된 가족이 쓴 쿠폰 · confirmed 이상이 남아 있으면 그대로
end;
$$;

-- ═══ 9) so_merge 재발행 — 마지막 정의 20261006201443:679~952(dsc-3a) · 판정 324(바뀐 줄: 원본 쿠폰 가운데 큰 쪽 · 반환 coupons) ═══
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
  v_cps jsonb := '[]'::jsonb;  v_best_cp uuid;  v_best_pct numeric := -1;  v_cp_pct numeric;   -- dsc-3b 판정 324 — 원본 쿠폰 가운데 큰 쪽
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
  -- dsc-3b 판정 324: 원본들의 쿠폰 가운데 helper 로 골라 본 % 가 큰 쪽만 새 머리에(같으면 오래된 원본 것) · 나머지는 뗀 채 남는다(원본은 merged 라 가족 판정에 안 걸린다)
  for r in select s.coupon_id, s.so_number, s.created_at from public.so s where s.id = any(v_ids) and s.coupon_id is not null order by s.created_at, s.so_number loop
    update public.so set coupon_id = r.coupon_id where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select case when s.order_discount_source = 'coupon' then s.order_discount_pct else -1 end into v_cp_pct from public.so s where s.id = v_id;
    v_cps := v_cps || jsonb_build_object('so_number', r.so_number, 'code', (select c.code from public.so_coupon c where c.id = r.coupon_id),
                                         'pct', (select public.so_coupon_pct(c, s) from public.so_coupon c, public.so s where c.id = r.coupon_id and s.id = v_id), 'won_pct', nullif(v_cp_pct, -1));
    if v_cp_pct > v_best_pct then v_best_pct := v_cp_pct; v_best_cp := r.coupon_id; end if;
  end loop;
  if v_cps <> '[]'::jsonb then
    update public.so set coupon_id = case when v_best_pct > -1 then v_best_cp else null end where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select coalesce(jsonb_agg(c || jsonb_build_object('kept', (select s.coupon_id from public.so s where s.id = v_id) = (select x.id from public.so_coupon x where x.code = c->>'code'))), '[]'::jsonb) into v_cps from jsonb_array_elements(v_cps) c;
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
                            'backorder_lines_recorded', v_bo, 'reserves_released', v_released, 'charges', v_charges, 'component_lines', v_comp_n, 'coupons', v_cps, 'warnings', to_jsonb(v_warn));   -- asm-2b2: 다시 매단 구성품 줄 수
end;
$$;

-- ═══ 10) so_detail 재발행 — 마지막 정의 20261006201443:1049~1148(dsc-3a) · 판정 329(바뀐 줄: coupon · 경고 coupon_not_used) ═══
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
  v_cp       jsonb;                                            -- dsc-3b 판정 329 — 붙은 쿠폰
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

  v_cp := public.so_coupon_info(v_so);
  if v_cp is not null and v_cp->>'status' <> 'won' then v_warn := array_append(v_warn, 'coupon_not_used'); end if;   -- dsc-3b 판정 329

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
    'coupon', v_cp,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 11) 크레딧에 오더 할인(판정 316 · 325) — so_credit.order_discount_amount · 줄 종류 order_discount · total 식 ═══
alter table public.so_credit add column if not exists order_discount_amount numeric not null default 0;
alter table public.so_credit add constraint so_credit_order_discount_ck check (order_discount_amount <= 0);
alter table public.so_credit drop constraint so_credit_total_ck;
alter table public.so_credit add constraint so_credit_total_ck check (total = lines_amount + order_discount_amount + fee_amount + surcharge_amount + tax_amount);
comment on column public.so_credit.order_discount_amount is '오더 할인 몫(dsc-3b · 판정 316 · 325 · 음수 또는 0) — Σ order_discount 줄 · 인보이스-오더마다 −round(제품 환불액 × 그 오더의 order_discount_pct/100, 2) · 리스탁킹 피 기준에 들어간다(제품 − 이것) · 이미 낸 크레딧은 0 그대로(고치지 않는다)';
alter table public.so_credit_line drop constraint so_credit_line_kind_ck;
alter table public.so_credit_line add constraint so_credit_line_kind_ck check (kind in ('product', 'freight', 'tax', 'other', 'restocking_fee', 'surcharge', 'order_discount'));
alter table public.so_credit_line drop constraint so_credit_line_amount_ck;
alter table public.so_credit_line add constraint so_credit_line_amount_ck check (case when kind in ('restocking_fee', 'order_discount') then amount <= 0 else amount >= 0 end);
comment on column public.so_credit_line.kind is 'product · freight · tax · other · restocking_fee(≤ 0) · surcharge(자동) · order_discount(dsc-3b · 자동 · ≤ 0 · 인보이스-오더마다 하나 · so_invoice_line_id = 그 인보이스의 order_discount 줄)';

-- ═══ 12) so_credit_issue 재발행 — 마지막 정의 20261006000805:1371~1700 · 판정 325(바뀐 줄: 선언 · order_discount 줄 바퀴 · 피 기준 · totals · insert) ═══
create or replace function public.so_credit_issue(p jsonb, p_commit boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons   constant text[] := array['customer_return','damaged','billing_error','other'];
  c_nr        constant text[] := array['damaged','b_grade','not_returned','other'];
  v_staff     uuid;
  v_on        date;
  v_reason    text;
  v_inv       public.so_invoice%rowtype;
  v_c         public.customer%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_w         public.ref_warehouse%rowtype;
  v_rule      public.ref_tax_rule%rowtype;
  v_cr        public.so_credit%rowtype;
  v_il        public.so_invoice_line%rowtype;
  v_io        public.so_invoice_order%rowtype;
  v_pr        public.product%rowtype;
  v_bin       public.ref_bin%rowtype;
  v_acct      public.ref_account%rowtype;
  v_cin7      boolean := false;
  v_cin7_inv  text;  v_cin7_ord text;  v_cin7_date date;
  v_cust      uuid;
  v_origin_on date;
  v_wh        uuid;
  v_first_io  public.so_invoice_order%rowtype;
  v_fee_days  int;  v_fee_pct numeric;  v_fee_acct_code text;
  v_lines     jsonb := '[]'::jsonb;
  v_ln        int := 0;
  v_kind      text;
  v_qty       numeric;  v_already numeric;  v_unit numeric;  v_amount numeric;  v_rate numeric;  v_tax numeric;
  v_bin_name  text;  v_bin_id uuid;  v_nr text;  v_nr_note text;  v_desc text;  v_acct_id uuid;  v_acct_code text;
  v_product_id uuid;  v_so_line_id uuid;  v_sku text;  v_il_id uuid;
  v_lines_amt numeric := 0;  v_fee_amt numeric := 0;  v_tax_amt numeric := 0;  v_product_amt numeric := 0;
  v_od_amt    numeric := 0;  v_od record;  v_od_il public.so_invoice_line%rowtype;                                      -- dsc-3b 판정 325 — 오더 할인 몫(인보이스-오더마다 음수 줄 하나)
  v_sc        public.so_invoice_line%rowtype;  v_sc_amt numeric := 0;  v_sc_line numeric;  v_sc_tax numeric;  v_sc_already numeric;   -- surcharge-2b(묶음 7)
  v_rates     numeric[] := '{}';  v_first_rate numeric;
  v_fee_lines int := 0;  v_restock_n int := 0;
  v_fee_sugg  jsonb;
  v_warn      text[] := '{}';
  v_ledger    jsonb;
  v_est       numeric;  v_est_qty numeric;
  v_ask       numeric;
  x           jsonb;
  e           jsonb;
  -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄의 반품 — 콤보 크레딧 줄(금액 · qty = 콤보 수 · 칸 · 사유 없음 · combo_components) + 구성품 크레딧 줄(금액 0 · qty = n × combo_qty · 제 칸 또는 사유 · combo_credit_line_id) · 구성품 하나만의 상품 줄은 거부
  v_combo     jsonb;  cj jsonb;  v_cov jsonb;  v_def_bin text;  v_def_nr text;  v_def_note text;  v_cpr public.product%rowtype;  v_cq numeric;  v_idmap jsonb := '{}'::jsonb;  v_parent_ln int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — 발행은 manager 이상(판정 3)
  v_staff := public.so_current_staff();
  v_on := coalesce(nullif(p->>'issued_on', '')::date, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Credit date % is in the future — nothing was saved', v_on; end if;
  v_reason := nullif(trim(p->>'reason'), '');
  if v_reason is null or v_reason <> all (c_reasons) then raise exception 'reason must be one of customer_return, damaged, billing_error, other — nothing was saved'; end if;
  if v_reason = 'other' and nullif(trim(p->>'note'), '') is null then raise exception 'reason other needs a note — nothing was saved'; end if;
  if p->'lines' is null or jsonb_typeof(p->'lines') <> 'array' or jsonb_array_length(p->'lines') = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  -- 설정(판정 5·7)
  select nullif(k.value, '')::int into v_fee_days from public.inv_config k where k.key = 'so_credit_restock_fee_days';
  select nullif(k.value, '')::numeric into v_fee_pct from public.inv_config k where k.key = 'so_credit_restock_fee_pct';
  select nullif(k.value, '') into v_fee_acct_code from public.inv_config k where k.key = 'so_credit_restock_fee_account_code';

  -- 원본 — IMS 인보이스 또는 Cin7 번호 원문(판정 6 · 0-4)
  if nullif(p->>'invoice_id', '') is not null then
    select * into v_inv from public.so_invoice i where i.id = (p->>'invoice_id')::uuid for update;
    if not found then raise exception 'Invoice not found — nothing was saved'; end if;
    if v_inv.status <> 'issued' then raise exception 'Invoice % is % — credit the live invoice, not a cancelled one — nothing was saved', v_inv.invoice_number, v_inv.status; end if;
    v_cust := v_inv.bill_to_customer_id;  v_origin_on := v_inv.issued_on;
    select * into v_cur from public.ref_currency c where c.id = v_inv.currency_id;
    select o.* into v_first_io from public.so_invoice_order o where o.invoice_id = v_inv.id order by o.so_number limit 1;
    select s.location_id into v_wh from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id order by o.so_number limit 1;
  elsif p->'cin7' is not null and jsonb_typeof(p->'cin7') = 'object' then
    v_cin7 := true;
    v_cin7_inv := nullif(trim(p->'cin7'->>'invoice_number'), '');  v_cin7_ord := nullif(trim(p->'cin7'->>'order_number'), '');  v_cin7_date := nullif(p->'cin7'->>'invoice_date', '')::date;
    if v_cin7_inv is null then raise exception 'A Cin7 credit needs cin7.invoice_number (the paper number) — nothing was saved'; end if;
    if nullif(p->>'customer_id', '') is null then raise exception 'A Cin7 credit needs customer_id — nothing was saved'; end if;
    v_cust := (p->>'customer_id')::uuid;  v_origin_on := v_cin7_date;
    if v_cin7_ord is null then v_warn := array_append(v_warn, 'origin_sale_unknown'); end if;
    select * into v_cur from public.ref_currency c
     where c.id = coalesce(nullif(p->>'currency_id', '')::uuid, (select c2.id from public.ref_currency c2 where c2.code = upper(nullif(trim(p->>'currency_code'), ''))), (select c3.currency_id from public.customer c3 where c3.id = v_cust));
    if v_cur.id is null then raise exception 'Currency is required — the customer has no default currency — nothing was saved'; end if;
    if nullif(trim(p->>'tax_rule'), '') is null then raise exception 'A Cin7 credit needs tax_rule (an active sale tax rule name) — nothing was saved'; end if;
    select * into v_rule from public.ref_tax_rule r where r.name = trim(p->>'tax_rule') and r.direction = 'sale' and r.is_active;
    if v_rule.id is null then raise exception 'Tax rule % is not an active sale rule — nothing was saved', trim(p->>'tax_rule'); end if;
    select c.default_location_id into v_wh from public.customer c where c.id = v_cust;
  else
    raise exception 'Give invoice_id (an IMS invoice) or cin7 {invoice_number, order_number, invoice_date} — nothing was saved';
  end if;
  select * into v_c from public.customer c where c.id = v_cust for update;         -- 청구처 손님 행 잠금(잔액 직렬화 · ⓑ 와 같은 자물쇠)
  if not found then raise exception 'Customer not found — nothing was saved'; end if;

  -- 창고(반품을 받은 창고 · ⬜4) — 지정 → 원 판매 창고 → 손님 기본 창고 → 거부
  v_wh := coalesce(nullif(p->>'warehouse_id', '')::uuid, v_wh);
  if v_wh is null then raise exception 'warehouse_id is required — where were the goods returned to? — nothing was saved'; end if;
  select * into v_w from public.ref_warehouse w where w.id = v_wh;
  if not found then raise exception 'Warehouse not found — nothing was saved'; end if;
  if not v_w.is_active then raise exception 'Warehouse % is inactive — nothing was saved', v_w.name; end if;

  -- 줄 — 첫 바퀴: product · freight · tax · other(수수료는 둘째 바퀴 · 제품 합이 먼저 필요하다)
  for x in select t from jsonb_array_elements(p->'lines') t loop
    v_kind := nullif(trim(x->>'kind'), '');
    if v_kind = 'surcharge' then raise exception 'Surcharge lines are added automatically from the returned product lines — do not send them — nothing was saved'; end if;   -- surcharge-2b(D-3 · 자동만)
    if v_kind is null or v_kind not in ('product','freight','tax','other','restocking_fee') then raise exception 'Line kind must be one of product, freight, tax, other, restocking_fee — nothing was saved'; end if;
    if v_kind = 'restocking_fee' then v_fee_lines := v_fee_lines + 1; continue; end if;
    v_il := null;  v_io := null;  v_pr := null;  v_bin := null;  v_acct := null;
    v_qty := null;  v_unit := null;  v_rate := null;  v_bin_id := null;  v_bin_name := null;  v_nr := null;  v_nr_note := null;  v_product_id := null;  v_so_line_id := null;  v_sku := null;  v_il_id := null;  v_desc := null;  v_est := null;
    v_acct_id := nullif(x->>'account_id', '')::uuid;
    if v_acct_id is not null then
      select * into v_acct from public.ref_account a where a.id = v_acct_id;
      if v_acct.id is null then raise exception 'Account % not found — nothing was saved', v_acct_id; end if;
    end if;

    if v_kind = 'product' then
      v_qty := nullif(x->>'qty_returned', '')::numeric;
      if v_qty is null or v_qty <= 0 then raise exception 'A product line needs qty_returned > 0 — nothing was saved'; end if;
      if v_cin7 then
        v_sku := nullif(trim(x->>'sku'), '');
        if v_sku is null then raise exception 'A Cin7 product line needs sku — nothing was saved'; end if;
        select * into v_pr from public.product pr where pr.sku = v_sku;
        if v_pr.id is null then raise exception 'Product % not found — nothing was saved', v_sku; end if;
        v_unit := nullif(x->>'unit_price', '')::numeric;
        if v_unit is null or v_unit < 0 then raise exception 'A Cin7 product line needs unit_price (the price on that invoice) — nothing was saved'; end if;
        v_rate := v_rule.rate_pct;  v_product_id := v_pr.id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_pr.name);
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_98_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then
          if exists (select 1 from public.so_line cl2 join public.so_invoice_order io2 on io2.so_id = cl2.so_id                                  -- asm-2b2(판정 245): 구성품은 인보이스 줄이 없다 — 하나만 돌려받는 길은 「other」 금액 줄
                      where io2.invoice_id = v_inv.id and cl2.combo_line_id is not null and (cl2.id = nullif(x->>'so_line_id', '')::uuid or cl2.sku = nullif(trim(x->>'sku'), ''))) then
            raise exception 'Line % is a component of a combo on invoice % — a combo is credited whole (credit the combo line); for one component use an other line (amount only, no stock) — nothing was saved', coalesce(nullif(trim(x->>'sku'), ''), x->>'so_line_id'), v_inv.invoice_number;
          end if;
          raise exception 'An IMS product line needs so_invoice_line_id (the invoice line being returned) — nothing was saved';
        end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'product';
        if v_il.id is null then raise exception 'Invoice line % is not a product line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        select coalesce(sum(cl.qty_returned), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id
         where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        select coalesce(sum((t->>'qty_returned')::numeric), 0) into v_ask from jsonb_array_elements(p->'lines') t where t->>'kind' = 'product' and nullif(t->>'so_invoice_line_id', '')::uuid = v_il.id;
        if v_already + v_ask > v_il.qty then
          raise exception 'Invoice % line % (%): % of % already credited and % asked now — only % can still be returned — nothing was saved', v_inv.invoice_number, v_il.line_no, v_il.sku, v_already, v_il.qty, v_ask, v_il.qty - v_already;
        end if;
        v_unit := v_il.unit_price;  v_rate := v_io.rate_pct;  v_sku := v_il.sku;  v_so_line_id := v_il.so_line_id;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select sl.product_id into v_product_id from public.so_line sl where sl.id = v_il.so_line_id;
        select * into v_pr from public.product pr where pr.id = v_product_id;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      v_amount := round(v_qty * coalesce(v_unit, 0), 2);  v_tax := public.so_tax_amount(v_amount, v_rate);
      v_product_amt := v_product_amt + v_amount;  v_rates := array_append(v_rates, v_rate);
      -- 돌아오나(판정 1) — not_restocked_reason 이 있으면 안 돌아옴 · 아니면 칸(지정 → ims_last_bin → 거부 · '' 불허 · ⬜4)
      v_combo := case when v_cin7 then null else nullif(v_il.combo_components, 'null'::jsonb) end;
      v_nr := nullif(trim(x->>'not_restocked_reason'), '');
      if v_combo is not null then                                                                                 -- asm-2b2: 콤보 줄 자체는 칸 · 사유가 없다 — 줄에 적은 칸 · 사유는 구성품 전부의 기본값(components[] 가 덮는다)
        v_def_nr := v_nr;  v_def_note := nullif(trim(x->>'not_restocked_note'), '');  v_def_bin := nullif(trim(x->>'restock_bin'), '');  v_nr := null;
        if v_def_nr is not null and v_def_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        if v_def_nr = 'other' and v_def_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        if exists (select 1 from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where not exists (select 1 from jsonb_array_elements(v_combo) cy where cy->>'sku' = nullif(trim(cx->>'sku'), ''))) then
          raise exception 'components[] of combo % names a sku that is not part of that combo on invoice % — nothing was saved', v_sku, v_inv.invoice_number;
        end if;
      elsif v_nr is not null then
        if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
        v_nr_note := nullif(trim(x->>'not_restocked_note'), '');
        if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
      else
        v_bin_name := nullif(trim(x->>'restock_bin'), '');
        if v_bin_name is null then
          v_bin_name := public.ims_last_bin(array[coalesce(v_pr.parent_product_id, v_pr.id)], v_w.id) -> coalesce(v_pr.parent_product_id, v_pr.id)::text ->> 'bin';
          if v_bin_name is null then raise exception 'No bin known for % in % — pick a restock bin (or mark the line not restocked) — nothing was saved', v_sku, v_w.name; end if;
        end if;
        select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
        if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
        if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
        v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
        -- 원가 복원 예상(미리 보기 · 원 판매의 소비 기록 평균 × EA · 없으면 null)
        select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0), sum(cs.qty) into v_est, v_est_qty
          from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
         where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_pr.parent_product_id), v_pr.sku)
           and cs.doc_number = case when v_cin7 then v_cin7_ord else (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id)) end;
      end if;
    elsif v_kind = 'freight' then
      if v_cin7 then
        v_amount := nullif(x->>'amount', '')::numeric;  v_rate := v_rule.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Freight');
        if v_acct.id is null then select * into v_acct from public.ref_account a where a.code = '_99_'; end if;
      else
        v_il_id := nullif(x->>'so_invoice_line_id', '')::uuid;
        if v_il_id is null then raise exception 'An IMS freight line needs so_invoice_line_id (the charge line) — nothing was saved'; end if;
        select * into v_il from public.so_invoice_line il where il.id = v_il_id and il.invoice_id = v_inv.id and il.kind = 'charge';
        if v_il.id is null then raise exception 'Invoice line % is not a charge line of invoice % — nothing was saved', v_il_id, v_inv.invoice_number; end if;
        select * into v_io from public.so_invoice_order o where o.id = v_il.invoice_order_id;
        v_amount := coalesce(nullif(x->>'amount', '')::numeric, v_il.amount);  v_rate := v_io.rate_pct;  v_desc := coalesce(nullif(trim(x->>'description'), ''), v_il.description);
        select coalesce(sum(cl.amount), 0) into v_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_il.id and c.status = 'issued';
        if v_already + v_amount > v_il.amount then raise exception 'Invoice % charge % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_already, v_il.amount, v_il.amount - v_already; end if;
        if v_acct.id is null and v_il.account_id is not null then select * into v_acct from public.ref_account a where a.id = v_il.account_id; end if;
      end if;
      if v_amount is null or v_amount < 0 then raise exception 'A freight line needs amount ≥ 0 — nothing was saved'; end if;
      v_tax := public.so_tax_amount(v_amount, v_rate);
    elsif v_kind = 'tax' then
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null or v_amount < 0 then raise exception 'A tax line needs amount ≥ 0 (the tax being returned) — nothing was saved'; end if;
      v_rate := null;  v_tax := 0;  v_desc := coalesce(nullif(trim(x->>'description'), ''), 'Tax');
      if v_acct.id is null then
        select * into v_acct from public.ref_account a where a.id = (case when v_cin7 then v_rule.account_id else (select r.account_id from public.ref_tax_rule r where r.id = v_first_io.tax_rule_id) end);
      end if;
    else   -- other
      v_amount := nullif(x->>'amount', '')::numeric;  v_desc := nullif(trim(x->>'description'), '');
      if v_amount is null or v_amount < 0 then raise exception 'An other line needs amount ≥ 0 — nothing was saved'; end if;
      if v_desc is null then raise exception 'An other line needs a description — nothing was saved'; end if;
      if v_acct.id is null then raise exception 'An other line needs account_id (no default) — nothing was saved'; end if;
      v_rate := case when v_cin7 then v_rule.rate_pct else v_first_io.rate_pct end;  v_tax := public.so_tax_amount(v_amount, v_rate);
    end if;
    v_ln := v_ln + 1;  v_lines_amt := v_lines_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);  v_parent_ln := v_ln;
    v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', v_kind, 'so_invoice_line_id', v_il_id, 'so_line_id', v_so_line_id, 'product_id', v_product_id, 'sku', v_sku, 'description', v_desc,
                                             'qty_returned', v_qty, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                             'unit_price', v_unit, 'amount', v_amount, 'rate_pct', v_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code,
                                             'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_qty * coalesce(v_pr.pack_factor, 1), 6) end,
                                             'combo_components', case when v_kind = 'product' then v_combo end);                                           -- asm-2b2: 콤보 크레딧 줄에 includes(인보이스 줄 사본)
    if v_kind = 'product' and not v_cin7 then                                                                  -- surcharge-2b(묶음 7): 그 상품의 인보이스 surcharge 줄이 있으면 크레딧 surcharge 줄을 자동으로 · 개당은 인보이스 줄의 것(문서는 문서에서) · 세금은 그 줄 세율로 따로 · 계정 복사 · 물건값(v_lines_amt) · 리스탁킹 피 바탕(v_product_amt) 밖
      select * into v_sc from public.so_invoice_line il where il.invoice_id = v_inv.id and il.kind = 'surcharge' and il.so_line_id = v_il.so_line_id;
      if v_sc.id is not null then
        v_sc_line := public.so_line_surcharge_total(v_sc.unit_price, v_qty);
        select coalesce(sum(cl.amount), 0) into v_sc_already from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = v_sc.id and c.status = 'issued';
        if v_sc_already + v_sc_line > v_sc.amount then raise exception 'Invoice % surcharge of line % : % of % already credited — only % left — nothing was saved', v_inv.invoice_number, v_il.line_no, v_sc_already, v_sc.amount, v_sc.amount - v_sc_already; end if;
        v_sc_tax := public.so_tax_amount(v_sc_line, v_io.rate_pct);
        v_ln := v_ln + 1;  v_sc_amt := v_sc_amt + v_sc_line;  v_tax_amt := v_tax_amt + coalesce(v_sc_tax, 0);
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'surcharge', 'so_invoice_line_id', v_sc.id, 'so_line_id', v_sc.so_line_id, 'product_id', v_product_id, 'sku', v_sc.sku, 'description', v_sc.description,
                                                 'qty_returned', v_qty, 'unit_price', v_sc.unit_price, 'amount', v_sc_line, 'rate_pct', v_io.rate_pct, 'tax_amount', coalesce(v_sc_tax, 0), 'account_id', v_sc.account_id, 'account_code', v_sc.account_code);
      end if;
    end if;
    if v_kind = 'product' and v_combo is not null then                                                             -- asm-2b2(묶음 7 · 판정 245): 구성품 크레딧 줄 — 콤보 n 개 ⇒ 구성품마다 n × combo_qty 가 재고로(제 칸 · 또는 안 돌아온 사유) · 금액 0 · 원장(credit_in)은 이 줄들만 · 원가 갈래 ① 은 구성품 SKU 의 소비 기록으로
      for cj in select c2.v from jsonb_array_elements(v_combo) with ordinality c2(v, ord) order by c2.ord loop
        select * into v_cpr from public.product pr where pr.id = nullif(cj->>'product_id', '')::uuid;
        if v_cpr.id is null then select * into v_cpr from public.product pr where pr.sku = cj->>'sku'; end if;
        if v_cpr.id is null then raise exception 'Component % of combo % is not a product any more — nothing was saved', cj->>'sku', v_sku; end if;
        select cx into v_cov from jsonb_array_elements(coalesce(nullif(x->'components', 'null'::jsonb), '[]'::jsonb)) cx where nullif(trim(cx->>'sku'), '') = cj->>'sku' limit 1;
        v_cq := v_qty * (cj->>'qty_per_combo')::numeric;
        v_bin := null;  v_bin_id := null;  v_bin_name := null;  v_est := null;  v_nr_note := null;
        v_nr := coalesce(nullif(trim(v_cov->>'not_restocked_reason'), ''), v_def_nr);
        if v_nr is not null then
          if v_nr <> all (c_nr) then raise exception 'not_restocked_reason must be one of damaged, b_grade, not_returned, other — nothing was saved'; end if;
          v_nr_note := coalesce(nullif(trim(v_cov->>'not_restocked_note'), ''), v_def_note);
          if v_nr = 'other' and v_nr_note is null then raise exception 'not_restocked_reason other needs not_restocked_note — nothing was saved'; end if;
        else
          v_bin_name := coalesce(nullif(trim(v_cov->>'restock_bin'), ''), v_def_bin);
          if v_bin_name is null then
            v_bin_name := public.ims_last_bin(array[coalesce(v_cpr.parent_product_id, v_cpr.id)], v_w.id) -> coalesce(v_cpr.parent_product_id, v_cpr.id)::text ->> 'bin';
            if v_bin_name is null then raise exception 'No bin known for % (component of combo %) in % — pick a restock bin for it in components[] (or mark it not restocked) — nothing was saved', v_cpr.sku, v_sku, v_w.name; end if;
          end if;
          select * into v_bin from public.ref_bin rb where rb.warehouse_id = v_w.id and rb.name = v_bin_name;
          if v_bin.id is null then raise exception 'Bin % is not in warehouse % — nothing was saved', v_bin_name, v_w.name; end if;
          if not v_bin.is_active then v_warn := array_append(v_warn, 'inactive_bin:' || v_bin_name); end if;
          v_bin_id := v_bin.id;  v_restock_n := v_restock_n + 1;
          select sum(cs.qty * cs.unit_cost) / nullif(sum(cs.qty), 0) into v_est
            from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
           where cs.doc_type = 'sale' and cs.reason = 'sale' and l.sku = coalesce((select pp.sku from public.product pp where pp.id = v_cpr.parent_product_id), v_cpr.sku)
             and cs.doc_number = (select s.so_number from public.so s where s.id = (select sl.so_id from public.so_line sl where sl.id = v_so_line_id));
        end if;
        v_ln := v_ln + 1;
        v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'product', 'so_invoice_line_id', null, 'so_line_id', nullif(cj->>'so_line_id', '')::uuid, 'product_id', v_cpr.id, 'sku', v_cpr.sku, 'description', coalesce(cj->>'description', v_cpr.name),
                                                 'qty_returned', v_cq, 'restock_bin_id', v_bin_id, 'restock_bin', case when v_bin_id is null then null else v_bin_name end, 'not_restocked_reason', v_nr, 'not_restocked_note', v_nr_note,
                                                 'unit_price', 0, 'amount', 0, 'rate_pct', v_rate, 'tax_amount', 0, 'account_id', v_acct.id, 'account_code', v_acct.code,
                                                 'cost_estimate', case when v_bin_id is null or v_est is null then null else round(v_est * v_cq * coalesce(v_cpr.pack_factor, 1), 6) end,
                                                 'combo_parent_line_no', v_parent_ln, 'combo_qty', (cj->>'qty_per_combo')::numeric, 'combo_sku', v_sku);
      end loop;
    end if;
  end loop;

  -- dsc-3b 판정 325 · 316: 인보이스 거울 — 인보이스-오더마다 오더 할인 % 가 있으면 그 오더의 제품 환불액에 음수 줄 하나(세금 따로 · 계정 = 그 인보이스의 order_discount 줄) · surcharge 는 기준 밖(인보이스와 같다) · Cin7 크레딧은 해당 없음
  if not v_cin7 then
    for v_od in
      select io.id as io_id, io.so_number, io.order_discount_pct as pct, io.rate_pct, sum((le->>'amount')::numeric) as amt
      from jsonb_array_elements(v_lines) le join public.so_invoice_line il on il.id = nullif(le->>'so_invoice_line_id', '')::uuid join public.so_invoice_order io on io.id = il.invoice_order_id
      where le->>'kind' = 'product' and coalesce(io.order_discount_pct, 0) > 0
      group by io.id, io.so_number, io.order_discount_pct, io.rate_pct order by io.so_number
    loop
      v_amount := -round(v_od.amt * v_od.pct / 100, 2);  v_tax := public.so_tax_amount(v_amount, v_od.rate_pct);
      select * into v_od_il from public.so_invoice_line il where il.invoice_order_id = v_od.io_id and il.kind = 'order_discount' limit 1;
      v_ln := v_ln + 1;  v_od_amt := v_od_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'order_discount', 'so_invoice_line_id', v_od_il.id, 'description', format('Order discount %s%% (%s)', v_od.pct, v_od.so_number),
                                               'amount', v_amount, 'rate_pct', v_od.rate_pct, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_od_il.account_id, 'account_code', v_od_il.account_code);
    end loop;
  end if;

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수 · dsc-3b 판정 325: 기준 = 제품 환불액 − 오더 할인 몫(손님이 실제 낸 값)
  v_first_rate := case when v_cin7 then v_rule.rate_pct else v_rates[1] end;
  if v_fee_lines > 0 then
    if v_fee_lines > 1 then raise exception 'Only one restocking_fee line per credit note — nothing was saved'; end if;
    if (select count(distinct r) from unnest(v_rates) r) > 1 then v_warn := array_append(v_warn, 'fee_rate_mixed'); end if;
    for x in select t from jsonb_array_elements(p->'lines') t where t->>'kind' = 'restocking_fee' loop
      v_acct := null;  v_acct_id := nullif(x->>'account_id', '')::uuid;
      if v_acct_id is not null then select * into v_acct from public.ref_account a where a.id = v_acct_id;
      elsif v_fee_acct_code is not null then select * into v_acct from public.ref_account a where a.code = v_fee_acct_code; end if;
      if v_acct.id is null then raise exception 'A restocking fee line needs account_id — no default account is set (inv_config so_credit_restock_fee_account_code) — nothing was saved'; end if;
      v_amount := nullif(x->>'amount', '')::numeric;
      if v_amount is null then v_amount := -round((v_product_amt + v_od_amt) * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;   -- dsc-3b 판정 325: v_od_amt 는 음수
      if v_amount > 0 then raise exception 'A restocking fee reduces the credit — amount must be ≤ 0 (got %) — nothing was saved', v_amount; end if;
      v_tax := public.so_tax_amount(v_amount, v_first_rate);
      v_ln := v_ln + 1;  v_fee_amt := v_fee_amt + v_amount;  v_tax_amt := v_tax_amt + coalesce(v_tax, 0);
      v_lines := v_lines || jsonb_build_object('line_no', v_ln, 'kind', 'restocking_fee', 'description', coalesce(nullif(trim(x->>'description'), ''), format('Restocking fee %s%%', coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct))),
                                               'amount', v_amount, 'rate_pct', v_first_rate, 'tax_amount', coalesce(v_tax, 0), 'account_id', v_acct.id, 'account_code', v_acct.code);
    end loop;
  end if;
  -- 알림(판정 5) — 원 인보이스 발행일 + N일이 지났고 수수료 줄이 없으면 「대상」만 알린다(자동으로 붙이지 않는다)
  if v_origin_on is null then v_warn := array_append(v_warn, 'fee_window_unknown');
  elsif v_fee_days is not null and v_on - v_origin_on > v_fee_days and v_fee_lines = 0 and v_product_amt > 0 then
    v_warn := array_append(v_warn, 'restock_fee_window:' || (v_on - v_origin_on)::text);
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round((v_product_amt + v_od_amt) * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);   -- dsc-3b 판정 325
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'fee_amount', v_fee_amt, 'surcharge_amount', v_sc_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_od_amt + v_fee_amt + v_sc_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, cin7_invoice_number, cin7_order_number, cin7_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, order_discount_amount, fee_amount, surcharge_amount, tax_amount, total, created_by, updated_by)
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_cin7_inv, v_cin7_ord, v_cin7_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_od_amt, v_fee_amt, v_sc_amt, v_tax_amt, v_lines_amt + v_od_amt + v_fee_amt + v_sc_amt + v_tax_amt, v_staff, v_staff)
  returning * into v_cr;
  for e in select t from jsonb_array_elements(v_lines) t loop
    insert into public.so_credit_line (credit_id, line_no, kind, so_invoice_line_id, so_line_id, product_id, sku, description, qty_returned, restock_bin_id, restock_bin, not_restocked_reason, not_restocked_note,
                                       unit_price, amount, rate_pct, tax_amount, account_id, account_code, updated_by, combo_credit_line_id, combo_qty, combo_components)
    values (v_cr.id, (e->>'line_no')::int, e->>'kind', nullif(e->>'so_invoice_line_id', '')::uuid, nullif(e->>'so_line_id', '')::uuid, nullif(e->>'product_id', '')::uuid, e->>'sku', e->>'description',
            nullif(e->>'qty_returned', '')::numeric, nullif(e->>'restock_bin_id', '')::uuid, e->>'restock_bin', e->>'not_restocked_reason', e->>'not_restocked_note',
            nullif(e->>'unit_price', '')::numeric, (e->>'amount')::numeric, nullif(e->>'rate_pct', '')::numeric, (e->>'tax_amount')::numeric, nullif(e->>'account_id', '')::uuid, e->>'account_code', v_staff,
            (v_idmap->>(e->>'combo_parent_line_no'))::uuid, nullif(e->>'combo_qty', '')::numeric, nullif(e->'combo_components', 'null'::jsonb))                   -- asm-2b2: 구성품 줄은 앞서 넣은 콤보 줄(line_no → id)에 매단다 · 콤보 줄은 includes 를 든다
    returning id into v_il_id;
    v_idmap := v_idmap || jsonb_build_object((e->>'line_no'), v_il_id);
  end loop;
  if v_restock_n > 0 then
    v_ledger := public.inv_post_credit(v_cr.id, v_on);
    v_warn := v_warn || coalesce((select array_agg(t.w) from jsonb_array_elements_text(coalesce(v_ledger->'warnings', '[]'::jsonb)) as t(w)), '{}');
  end if;

  return jsonb_build_object('committed', true, 'credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', v_cr.status, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code,
                            'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                            'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                           else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'order_discount_amount', v_cr.order_discount_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 13) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regclass('public.so_coupon') is null or (select count(*) from pg_policies where schemaname = 'public' and tablename = 'so_coupon') <> 1 then v_bad := v_bad || ' so_coupon'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so' and column_name = 'coupon_id') then v_bad := v_bad || ' so.coupon_id'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so_deal' and column_name = 'coupon_required') then v_bad := v_bad || ' coupon_required'; end if;
  if not exists (select 1 from pg_constraint where conname = 'so_order_discount_source_ck' and pg_get_constraintdef(oid) like '%coupon%') or not exists (select 1 from pg_constraint where conname = 'so_order_discount_coupon_ck') then v_bad := v_bad || ' so_checks'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('so_coupon_key', 'so_coupon_check', 'so_coupon_pct', 'so_coupon_info', 'so_coupon_issue', 'so_coupon_void', 'so_coupon_apply', 'so_coupon_remove', 'so_coupon_settle', 'so_coupon_release', 'so_coupon_deal_guard', 'so_coupon_detach')) <> 12 then v_bad := v_bad || ' functions'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_confirm', 'so_pos_confirm') and p.prosrc not like '%so_coupon_settle(%') then v_bad := v_bad || ' settle_callers'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_unconfirm', 'so_cancel') and p.prosrc not like '%so_coupon_release(%') then v_bad := v_bad || ' release_callers'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_order_discount(uuid)');
  if v_src not like '%coupon_required%' or v_src not like '%so_coupon_check(%' then v_bad := v_bad || ' so_order_discount'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_merge(uuid[], boolean)');
  if v_src not like '%v_best_cp%' then v_bad := v_bad || ' so_merge'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_detail(uuid)');
  if v_src not like '%so_coupon_info(%' then v_bad := v_bad || ' so_detail'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so_credit' and column_name = 'order_discount_amount') or not exists (select 1 from pg_constraint where conname = 'so_credit_line_kind_ck' and pg_get_constraintdef(oid) like '%order_discount%') then v_bad := v_bad || ' credit'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.so_credit_issue(jsonb, boolean)');
  if v_src not like '%''order_discount''%' or v_src not like '%v_product_amt + v_od_amt%' then v_bad := v_bad || ' so_credit_issue'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM320', message = format('STOP - dsc-3b did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
