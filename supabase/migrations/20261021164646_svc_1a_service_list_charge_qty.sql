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

-- ═══ svc-1a — 서비스 목록 ref_service + 비용 줄(so_charge)에 수량 · 단가 · 서비스 · 손 단가 표시 + so_charge_set 이 받는다 (2026-10-21 · 판정 590 · 593 · 596 · 597 · svc-0 조사 · 정본 so-module 판정 8 · 9 · 531 · 539 · 540 · 546 뒤) ═══
--   계기: Caleb 「우리는 아마존 Prep service를 제공해 … 서비스만 따로 끊어」 — 서비스 오더(svc-1b · 1c)의 바탕. 이 차수는 표 · 칸 · 비용 줄 창구만 · 서비스 길 · 발행 · 인보이스 줄 · 판은 짓지 않는다.
--   ① ref_service(이름 · 단가 · 매출 계정 · 켜짐 · 메모) — Settings 마스터와 같은 꼴(판정 534 · 538): 정책으로 직접 쓰기(insert · update = master 쓰기 · select = 로그인 · delete 없음) · 이름 잠금 ims_ref_name_lock(이름을 바꾸려면 끄고 새로) · 단가 · 계정 · 켜짐 · 메모는 고칠 수 있다
--      세금 칸 없음(판정 593 — 서비스 줄 세금 = 오더 세율 · 달라야 하면 오더의 세율을 바꾼다) · 계정 기본 = 이 DB 의 _153_ Services(없으면 마이그레이션이 멈춘다) · 첫 행 없음(Caleb 이 Settings 에서)
--   ② so_charge + qty · unit_price · service_id · price_set_by · price_set_at — CHECK: qty · unit_price 둘 다 null 이거나 둘 다 · qty > 0 · unit_price ≥ 0 · amount = round(qty × unit_price, 2) · service_id 면 qty 도 · price_set_by ⇔ price_set_at(so_line 판정 546 꼴) · 옛 줄(15 행)은 전부 null 그대로
--   ③ so_charge_set 재발행(인자 셋 끝에 더함 · drop + create · 옛 호출(화면 so.html Add a charge · shop_order_freight 의 위치 9 개)은 그대로 풀린다) — 몸 = 원본 바이트 + 더한 줄만:
--      수량 · 단가 · 서비스 중 하나라도 오면 「수량 × 단가」 줄 — 서비스면 목록 단가 · 이름 · 계정을 채움 · 금액은 창구가 짓고(보낸 금액이 다르면 거부) · 그 뒤 옛 검사(이름 · 금액 · 할인 · 세금 거부 · 계정)가 그대로 돈다
--      손 단가 표시(판정 596): 목록 단가와 같으면 price_set_by null · 다르거나 목록 없이 넣은 단가면 지금 직원 · 옛 꼴 호출로 수량 × 단가 줄을 고치려 하면 거부(금액만 바꿔 짝이 깨지지 않게)
--   ⚠️ to_jsonb(so_charge) 를 내는 반환(so_charge_set · 읽기 창구)에는 새 칸 다섯이 null 로 더 붙는다 — 그 밖은 같다(검증 ①)
--   ⚠️ 운영에는 닿지 않는다(가드).

create temp table svc1a_before as
select (select count(*) || '/' || md5(string_agg(to_jsonb(c)::text, ',' order by c.id)) from public.so_charge c) as charges,
       (select obj_description(p.oid, 'pg_proc') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_charge_set') as set_comment,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_charge_remove', 'so_charge_gate', 'so_finalize', 'so_tax_preview', 'so_detail', 'so_invoice_issue', 'shop_order_freight')) as others;

-- ═══ ① ref_service ═══
do $$ declare v_id uuid; begin
  select a.id into v_id from public.ref_account a where a.code = '_153_' and a.name = 'Services';
  if v_id is null then raise exception 'svc-1a: ref_account _153_ Services not found — the default revenue account for services is unknown — nothing was changed'; end if;
end $$;
create table public.ref_service (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  unit_price  numeric not null,
  account_id  uuid references public.ref_account(id),
  is_active   boolean not null default true,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff(id),
  constraint ref_service_name_ck check (name = btrim(name) and name <> ''),
  constraint ref_service_unit_price_ck check (unit_price >= 0)
);
create unique index ref_service_name_uq on public.ref_service (lower(name));
do $$ begin
  execute format('alter table public.ref_service alter column account_id set default %L::uuid', (select a.id from public.ref_account a where a.code = '_153_'));   -- 이 DB 의 _153_ Services(테스트 · 운영의 id 가 다르다)
end $$;
create trigger ref_service_touch before insert or update on public.ref_service for each row execute function public.ims_touch();
create trigger ref_service_name_lock before update on public.ref_service for each row execute function public.ims_ref_name_lock();
alter table public.ref_service enable row level security;
create policy ref_service_select on public.ref_service for select to authenticated using (true);
create policy ref_service_insert on public.ref_service for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_service_update on public.ref_service for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
revoke all on public.ref_service from anon, public;
revoke delete, truncate on public.ref_service from authenticated;
comment on table public.ref_service is 'svc-1a(판정 590 · 593 · 597 · 2026-10-21) — 미리 정한 서비스(예 Amazon Prep service 0.45/개) · 비용 줄(so_charge)이 service_id 로 고른다 · 이름 · 단가 · 매출 계정 · 켜짐 · 메모 · 세금 칸 없음(판정 593 — 오더 세율) · 쓰기 = master(정책 · Settings 마스터와 같은 꼴 · 판정 534 · 538) · 이름은 잠금(바꾸려면 끄고 새로) · 지우기 없음(끄기)';
comment on column public.ref_service.unit_price is '목록 단가(오더 통화 그대로 · 판정 596 — 줄에서 손으로 바꿀 수 있고 그러면 so_charge.price_set_by 가 남는다)';
comment on column public.ref_service.account_id is '매출 계정 — 기본은 마이그레이션 때 이 DB 의 _153_ Services(id 를 박는다)';

-- ═══ ② so_charge 칸 ═══
alter table public.so_charge
  add column qty numeric,
  add column unit_price numeric,
  add column service_id uuid references public.ref_service(id),
  add column price_set_by uuid references public.ims_staff(id),
  add column price_set_at timestamptz,
  add constraint so_charge_qty_pair_ck check ((qty is null) = (unit_price is null)),
  add constraint so_charge_qty_pos_ck check (qty is null or qty > 0),
  add constraint so_charge_unit_price_ck check (unit_price is null or unit_price >= 0),
  add constraint so_charge_qty_amount_ck check (qty is null or amount = round(qty * unit_price, 2)),
  add constraint so_charge_service_qty_ck check (service_id is null or qty is not null),
  add constraint so_charge_price_set_pair_ck check ((price_set_by is null) = (price_set_at is null));
comment on column public.so_charge.qty is 'svc-1a(판정 590) — 수량(예 1,200 개) · unit_price 와 짝 · 있으면 amount = round(qty × unit_price, 2)(창구가 짓는다) · 옛 줄 · 운임은 null';
comment on column public.so_charge.unit_price is 'svc-1a(판정 590 · 596) — 개당 단가 · 서비스면 목록 단가가 채워지고 손으로 바꿀 수 있다';
comment on column public.so_charge.service_id is 'svc-1a — 고른 서비스(ref_service) · 이름 · 계정 · 단가의 출처 · 있으면 qty · unit_price 도 있다';
comment on column public.so_charge.price_set_by is 'svc-1a(판정 596 · so_line 판정 546 꼴) — 단가를 손으로 정한 직원(목록 단가와 다르거나 목록 없이 넣었을 때) · 목록 단가 그대로면 null · price_set_at 과 짝';

-- ═══ ③ so_charge_set 재발행 — 원본 20261020134522_ch_1_packed_charges.sql:70 바이트 + 더한 줄 43(인자 셋 · declare 셋 · 수량 × 단가 갈래) ═══
drop function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric);
CREATE FUNCTION public.so_charge_set(p_so_id uuid, p_name text, p_amount numeric, p_charge_id uuid DEFAULT NULL::uuid, p_description text DEFAULT NULL::text, p_tax_rule text DEFAULT NULL::text, p_account_id uuid DEFAULT NULL::uuid, p_discount_pct numeric DEFAULT NULL::numeric, p_discount_amount numeric DEFAULT NULL::numeric,
                                     p_qty numeric DEFAULT NULL::numeric, p_unit_price numeric DEFAULT NULL::numeric, p_service_id uuid DEFAULT NULL::uuid)   -- svc-1a
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_name   text;
  v_acct   public.ref_account%rowtype;
  v_ch     public.so_charge%rowtype;
  v_next   int;
  v_warn   text[] := '{}';
  v_n      int;
  v_svc    public.ref_service%rowtype;                                                                           -- svc-1a(판정 590 · 596): 서비스 줄
  v_qmode  boolean := p_qty is not null or p_unit_price is not null or p_service_id is not null;                  -- svc-1a: 수량 · 단가 · 서비스 중 하나라도 오면 「수량 × 단가」 줄
  v_old    public.so_charge%rowtype;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_charge_gate(p_so_id, 'saved');                                                                  -- ch-1 판정 539 · 540 · 549: draft 또는 packed(master 도 · aone 거부) · 오더 행 잠금
  -- ═══ svc-1a(판정 590 · 596) — 수량 × 단가 줄: 서비스 목록 단가 · 이름 · 계정을 채우고 금액은 창구가 짓는다 · 아래 옛 검사(이름 · 금액 · 할인 · 세금 · 계정)는 그대로 돈다 ═══
  if p_charge_id is not null and not v_qmode then
    select * into v_old from public.so_charge where id = p_charge_id and so_id = p_so_id;
    if found and v_old.qty is not null then
      raise exception 'Charge % is a quantity × unit price line — send qty and unit_price (or service_id) to change it — nothing was saved', v_old.name;
    end if;
  end if;
  if v_qmode then
    if p_service_id is not null then
      select * into v_svc from public.ref_service where id = p_service_id;
      if not found then raise exception 'Service not found — nothing was saved'; end if;
      if not v_svc.is_active then raise exception 'Service % is switched off — pick an active service — nothing was saved', v_svc.name; end if;
      p_unit_price := coalesce(p_unit_price, v_svc.unit_price);
      p_name       := coalesce(nullif(trim(p_name), ''), v_svc.name);
      p_account_id := coalesce(p_account_id, v_svc.account_id);
    end if;
    if p_qty is null or p_unit_price is null then
      raise exception 'A quantity × unit price line needs both qty and unit_price (or a service for the price) — nothing was saved';
    end if;
    if p_qty <= 0 then raise exception 'Quantity must be more than 0 — nothing was saved'; end if;
    if p_unit_price < 0 then raise exception 'A unit price cannot be negative — use a credit note — nothing was saved'; end if;
    if p_amount is not null and p_amount <> round(p_qty * p_unit_price, 2) then
      raise exception 'Amount % does not match % × % — leave the amount out, it is worked out from quantity and unit price — nothing was saved', p_amount, trim_scale(p_qty), trim_scale(p_unit_price);
    end if;
    p_amount := round(p_qty * p_unit_price, 2);
  end if;

  v_name := nullif(trim(p_name), '');
  if v_name is null then
    raise exception 'A charge needs a name — nothing was saved';
  end if;
  if p_amount is null then
    raise exception 'A charge needs an amount — nothing was saved';
  end if;
  if p_amount < 0 then                                          -- ①c 판정(Caleb 2026-09-23) — 돌려줄 돈은 크레딧 노트(8-g) · CHECK so_charge_amount_ck 가 마지막 문
    raise exception 'A charge cannot be negative — use a credit note — nothing was saved';
  end if;
  perform public.so_charge_discount_check(p_amount, p_discount_pct, p_discount_amount);                              -- fr-1 판정 356: 한 곳의 검사(둘 다 · 0 · 100 초과 · 운임보다 큰 금액)
  if nullif(trim(p_tax_rule), '') is not null and nullif(trim(p_tax_rule), '') is distinct from v_so.tax_rule then   -- 세금 ② · 판정 8·9 — 운임 줄만 따로 바꾸는 길은 없다(조용히 무시하지 않고 거부)
    raise exception 'Freight and charges follow the order tax rule (%) — change it on the order, not on the charge — nothing was saved', coalesce(v_so.tax_rule, 'none yet');
  end if;

  if p_account_id is not null then
    select * into v_acct from public.ref_account where id = p_account_id;
    if not found then
      raise exception 'Account not found — nothing was saved';
    end if;
  end if;

  if p_charge_id is null then
    if p_account_id is null then
      select * into v_acct from public.ref_account where code = '_99_';          -- 기본 Freight Sales · 없으면 비우고 알린다(짐작 값을 박지 않는다)
      if not found then v_warn := array_append(v_warn, 'charge_account_unset'); end if;
    end if;
    select coalesce(max(line_no), 0) + 1 into v_next from public.so_charge where so_id = p_so_id;
    insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by, discount_pct, discount_amount)
    values (p_so_id, v_next, v_name, nullif(trim(p_description), ''), p_amount, v_so.tax_rule, v_acct.id, v_acct.code, v_staff, p_discount_pct, p_discount_amount)   -- 세금 ②: 오더 규칙을 기록 · fr-1 할인 칸 둘
    returning * into v_ch;
    if v_qmode then                                                                                                  -- svc-1a: 같은 문장 안에서 금액과 짝이 맞게(금액은 위에서 qty × 단가)
      update public.so_charge set qty = p_qty, unit_price = p_unit_price, service_id = p_service_id,
             price_set_by = case when p_service_id is not null and p_unit_price = v_svc.unit_price then null else v_staff end,
             price_set_at = case when p_service_id is not null and p_unit_price = v_svc.unit_price then null else now() end
       where id = v_ch.id returning * into v_ch;
    end if;
    return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'status', v_so.status, 'charge', to_jsonb(v_ch) || jsonb_build_object('discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount)), 'warnings', to_jsonb(v_warn));   -- fr-1: 할인액 · 순 운임
  end if;

  select * into v_ch from public.so_charge where id = p_charge_id and so_id = p_so_id;
  if not found then
    raise exception 'Charge not found on order % — nothing was saved', v_so.so_number;
  end if;
  if v_qmode then                                                                                                    -- svc-1a: 수량 · 단가 · 금액을 한 문장으로 먼저(아래 옛 update 는 같은 금액을 다시 쓴다)
    update public.so_charge c set qty = p_qty, unit_price = p_unit_price, amount = p_amount, service_id = p_service_id,
           price_set_by = case when p_service_id is not null and p_unit_price = v_svc.unit_price then null
                               when c.unit_price is not distinct from p_unit_price and c.service_id is not distinct from p_service_id then c.price_set_by else v_staff end,
           price_set_at = case when p_service_id is not null and p_unit_price = v_svc.unit_price then null
                               when c.unit_price is not distinct from p_unit_price and c.service_id is not distinct from p_service_id then c.price_set_at else now() end
     where c.id = p_charge_id;
  end if;
  update public.so_charge c set
    name         = v_name,
    description  = nullif(trim(p_description), ''),
    amount       = p_amount,
    discount_pct = p_discount_pct,  discount_amount = p_discount_amount,                               -- fr-1 판정 353: 고치기는 전체 모양(이름 · 설명 · 금액처럼) — 둘 다 null 이면 할인을 지운다
    tax_rule     = v_so.tax_rule,                             -- 세금 ②: 오더 규칙을 기록
    account_id   = case when p_account_id is not null then v_acct.id   else c.account_id end,
    account_code = case when p_account_id is not null then v_acct.code else c.account_code end,
    updated_by   = v_staff
  where c.id = p_charge_id
  returning * into v_ch;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Charge was not saved — it may have been removed by someone else just now — nothing was saved';
  end if;
  return jsonb_build_object('action', 'updated', 'so_number', v_so.so_number, 'status', v_so.status, 'charge', to_jsonb(v_ch) || jsonb_build_object('discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount)), 'warnings', to_jsonb(v_warn));   -- fr-1
end;
$function$;
revoke all on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric, numeric, numeric, uuid) from public, anon;
grant execute on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric, numeric, numeric, uuid) to authenticated, service_role;
do $$ begin
  execute format('comment on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric, numeric, numeric, uuid) is %L',
    (select set_comment from svc1a_before) || ' · ⭐ svc-1a(판정 590 · 593 · 596): p_qty · p_unit_price · p_service_id — 하나라도 오면 수량 × 단가 줄(서비스면 목록 단가 · 이름 · 계정 채움 · 금액 = round(qty × unit_price, 2) 창구가 짓고 보낸 금액이 다르면 거부 · 손 단가면 price_set_by) · 세금은 오더 세율 그대로 · 꺼진 서비스 거부 · 옛 꼴 호출로 수량 × 단가 줄을 고치면 거부');
end $$;

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int; v_b record;
begin
  select * into v_b from svc1a_before;
  if to_regclass('public.ref_service') is null then v_bad := v_bad || ' ref_service_missing'; end if;
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename = 'ref_service';
  if v_n <> 3 or not exists (select 1 from pg_policies where tablename = 'ref_service' and cmd = 'SELECT' and qual = 'true')
     or (select count(*) from pg_policies where tablename = 'ref_service' and cmd in ('INSERT', 'UPDATE') and coalesce(with_check, '') ~ 'ims_can_write\(''master''') <> 2 then v_bad := v_bad || format(' ref_service_policies_%s', v_n); end if;
  if has_table_privilege('anon', 'public.ref_service', 'select') or has_table_privilege('authenticated', 'public.ref_service', 'delete') or has_table_privilege('authenticated', 'public.ref_service', 'truncate')
     or not has_table_privilege('authenticated', 'public.ref_service', 'insert') or not has_table_privilege('authenticated', 'public.ref_service', 'update') then v_bad := v_bad || ' ref_service_grants'; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.ref_service'::regclass) then v_bad := v_bad || ' ref_service_rls_off'; end if;
  if (select column_default from information_schema.columns where table_schema = 'public' and table_name = 'ref_service' and column_name = 'account_id') is distinct from format('%L::uuid', (select a.id from public.ref_account a where a.code = '_153_')) then v_bad := v_bad || ' account_default'; end if;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and table_name = 'so_charge' and column_name in ('qty', 'unit_price', 'service_id', 'price_set_by', 'price_set_at');
  if v_n <> 5 then v_bad := v_bad || format(' so_charge_cols_%s_of_5', v_n); end if;
  select count(*) into v_n from pg_constraint where conrelid = 'public.so_charge'::regclass and conname in ('so_charge_qty_pair_ck', 'so_charge_qty_pos_ck', 'so_charge_unit_price_ck', 'so_charge_qty_amount_ck', 'so_charge_service_qty_ck', 'so_charge_price_set_pair_ck');
  if v_n <> 6 then v_bad := v_bad || format(' so_charge_checks_%s_of_6', v_n); end if;
  if (select count(*) || '/' || md5(string_agg((to_jsonb(c) - 'qty' - 'unit_price' - 'service_id' - 'price_set_by' - 'price_set_at')::text, ',' order by c.id)) from public.so_charge c) is distinct from v_b.charges
     or exists (select 1 from public.so_charge where qty is not null or service_id is not null or price_set_by is not null) then v_bad := v_bad || ' old_charges_changed'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_charge_set';
  if v_n <> 1 then v_bad := v_bad || format(' so_charge_set_overloads_%s', v_n); end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_charge_set') is distinct from 'ea448cecccf9427a360a6f4748a64426'
     or not (select p.prosecdef and p.proconfig::text ~ 'search_path=public, pg_temp' and pg_get_function_identity_arguments(p.oid) = 'p_so_id uuid, p_name text, p_amount numeric, p_charge_id uuid, p_description text, p_tax_rule text, p_account_id uuid, p_discount_pct numeric, p_discount_amount numeric, p_qty numeric, p_unit_price numeric, p_service_id uuid'
             from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_charge_set') then v_bad := v_bad || ' so_charge_set_body_or_signature'; end if;
  if not has_function_privilege('authenticated', 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric, numeric, numeric, uuid)', 'execute')
     or has_function_privilege('anon', 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric, numeric, numeric, uuid)', 'execute') then v_bad := v_bad || ' so_charge_set_acl'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_charge_remove', 'so_charge_gate', 'so_finalize', 'so_tax_preview', 'so_detail', 'so_invoice_issue', 'shop_order_freight')) is distinct from v_b.others then v_bad := v_bad || ' other_charge_functions_changed'; end if;
  if v_bad <> '' then raise exception 'svc-1a landing check failed:%', v_bad; end if;
end $$;
drop table svc1a_before;
