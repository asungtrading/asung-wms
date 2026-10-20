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

-- ═══ ch-1 — packed 오더에 비용 더하기 · 고치기 · 지우기 (2026-10-20 · 판정 531 · 539 · 540 · 549 · 동료 피드백 2) ═══
--   문(두 창구 같게 · 속 함수 so_charge_gate 한 곳): draft → 지금 그대로(sales) · packed → sales 쓰기 + master 쓰기 둘 다(540) · 그 밖 상태 거부(539)
--   packed 의 Shopify 오더(intake shopify): shop_order.so_id → store_id → shop_store.kind = 'aone' 이면 거부(549 · aonebeauty 는 배송비까지 결제가 끝난 채 내려온다) · shop_order 가 없으면 거부(모르면 막는다) · asung.ca 는 보통 오더와 같다
--   잠금: 오더 행 for update(so_require_draft 는 stable · 잠금 없음) — so_finalize 도 ① 검사에서 같은 행을 for update 로 잡는다 → 겹치면 뒤쪽이 상태를 다시 본다
--   재발행 = 마지막 정의 바이트 + 바뀐 줄: so_charge_set(20261007171939_fr_1_freight_discount.sql:73 · so_require_draft → so_charge_gate · 반환에 status) · so_charge_remove(20260923191030_so_write_rpc.sql:921 · 같은 둘)
--   무접촉: 세금 규칙 · 계정 · 할인 검사(so_charge_discount_check) · so_finalize 의 charges[](같은 표 · 같은 규칙 · 인보이스는 so_invoice_issue 가 so_charge 전부를 읽는다) · shop_order_freight(draft 에서만 부른다) · 창고 쪽(so_charge 를 읽지 않는다)

-- ═══ 1) so_charge_gate — 속 함수(바깥 창구만 부른다 · authenticated 실행권 없음) ═══
create function public.so_charge_gate(p_so_id uuid, p_verb text default 'saved') returns public.so
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_so public.so%rowtype;
begin
  select * into v_so from public.so where id = p_so_id for update;                                                -- 잠금 — so_finalize 와 겹치면 뒤쪽이 상태를 다시 본다
  if not found then
    raise exception 'Order not found — nothing was %', p_verb;
  end if;
  if v_so.status = 'draft' then
    return v_so;                                                                                                   -- 판정 540: draft 는 지금 그대로(sales)
  end if;
  if v_so.status <> 'packed' then                                                                                  -- 판정 539
    raise exception 'Order % is % — charges can be added or removed only on a draft or a packed order — nothing was %', v_so.so_number, v_so.status, p_verb;
  end if;
  if not public.ims_can_write('master') then                                                                      -- 판정 531 · 540
    raise exception 'Order % is packed — adding or changing charges after packing needs the master permission as well — nothing was %', v_so.so_number, p_verb;
  end if;
  if v_so.intake = 'shopify' then                                                                                  -- 판정 549: 스토어 종류로 가른다(결제 상태가 아니다)
    if not exists (select 1 from public.shop_order o where o.so_id = v_so.id) then
      raise exception 'Order % is a Shopify order but its store is unknown — nothing was %', v_so.so_number, p_verb;
    end if;
    if exists (select 1 from public.shop_order o join public.shop_store st on st.id = o.store_id where o.so_id = v_so.id and st.kind = 'aone') then
      raise exception 'Order % came from aonebeauty and was paid at checkout — charges cannot change after packing — nothing was %', v_so.so_number, p_verb;
    end if;
  end if;
  return v_so;
end;
$$;
revoke all on function public.so_charge_gate(uuid, text) from public, anon, authenticated;
comment on function public.so_charge_gate(uuid, text) is 'ch-1 판정 539 · 540 · 549 — so_charge_set · so_charge_remove 의 문(속 함수 · 바깥 창구만 부른다): 오더 행 for update · draft 통과 · packed 는 master 쓰기도 + aone 스토어 Shopify 오더 거부 + 스토어 모르는 Shopify 오더 거부 · 그 밖 상태 거부 · 없으면 Order not found';

-- ═══ 2) so_charge_set 재발행 — 원본 20261007171939_fr_1_freight_discount.sql:73 바이트 + so_charge_gate · 반환 status ═══
create or replace function public.so_charge_set(
  p_so_id       uuid,
  p_name        text,
  p_amount      numeric,
  p_charge_id   uuid default null,
  p_description text default null,
  p_tax_rule    text default null,
  p_account_id  uuid default null,
  p_discount_pct    numeric default null,                       -- fr-1 판정 353 · 356: 운임 할인 %(0 < x ≤ 100) — 금액과 둘 중 하나 · 둘 다 null = 할인 없음(고치기도 전체 모양)
  p_discount_amount numeric default null                        -- fr-1 판정 356: 운임 할인 금액(> 0 · ≤ 운임)
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_name   text;
  v_acct   public.ref_account%rowtype;
  v_ch     public.so_charge%rowtype;
  v_next   int;
  v_warn   text[] := '{}';
  v_n      int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_charge_gate(p_so_id, 'saved');                                                                  -- ch-1 판정 539 · 540 · 549: draft 또는 packed(master 도 · aone 거부) · 오더 행 잠금

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
    return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'status', v_so.status, 'charge', to_jsonb(v_ch) || jsonb_build_object('discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount)), 'warnings', to_jsonb(v_warn));   -- fr-1: 할인액 · 순 운임
  end if;

  select * into v_ch from public.so_charge where id = p_charge_id and so_id = p_so_id;
  if not found then
    raise exception 'Charge not found on order % — nothing was saved', v_so.so_number;
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
$$;
comment on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric) is
  '⭐ SO 운임 · 비용 줄 넣기 · 고치기(①b · 세금 ② · fr-1 · ch-1 재발행 · 판정 352 ~ 357 · 539 · 540 · 549) — definer · 첫 줄 ims_require_write(sales) · 문 = so_charge_gate(draft 그대로 · packed 는 master 쓰기도 · aone 스토어 Shopify 오더는 packed 거부 · 그 밖 상태 거부 · 오더 행 for update) · 세금은 오더 규칙(다르면 거부) · 기본 계정 _99_ · 할인 % 또는 금액 하나(so_charge_discount_check) · 반환 {action added|updated, so_number, status draft|packed, charge{… discount, net}, warnings}';

-- ═══ 3) so_charge_remove 재발행 — 원본 20260923191030_so_write_rpc.sql:921 바이트 + so_charge_gate · 반환 status ═══
create or replace function public.so_charge_remove(p_charge_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_ch  public.so_charge%rowtype;
  v_so  public.so%rowtype;
  v_n   int;
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  perform public.so_current_staff();
  select * into v_ch from public.so_charge where id = p_charge_id;
  if not found then
    raise exception 'Charge not found — nothing was deleted';
  end if;
  v_so := public.so_charge_gate(v_ch.so_id, 'deleted');                                                             -- ch-1 판정 539 · 540 · 549
  delete from public.so_charge where id = p_charge_id;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Charge was not deleted — it may have been removed by someone else just now — nothing was deleted';
  end if;
  return jsonb_build_object('so_number', v_so.so_number, 'status', v_so.status, 'removed_line_no', v_ch.line_no);   -- ch-1
end;
$$;
comment on function public.so_charge_remove(uuid) is '⭐ SO 운임 · 비용 줄 지우기(①b · ch-1 재발행 · 판정 539 · 540 · 549) — definer · 첫 줄 ims_require_write(sales, deleted) · 문 = so_charge_gate(draft 그대로 · packed 는 master 쓰기도 · aone 거부) · 반환 {so_number, status, removed_line_no}';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.so_charge_gate(uuid, text)') is null or has_function_privilege('authenticated', 'public.so_charge_gate(uuid, text)', 'execute') or has_function_privilege('anon', 'public.so_charge_gate(uuid, text)', 'execute') then v_bad := v_bad || ' gate'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)'::regprocedure) !~ 'so_charge_gate\(p_so_id' or (select prosrc from pg_proc where oid = 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)'::regprocedure) ~ 'so_require_draft' then v_bad := v_bad || ' so_charge_set'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_charge_remove(uuid)'::regprocedure) !~ 'so_charge_gate\(v_ch\.so_id' or (select prosrc from pg_proc where oid = 'public.so_charge_remove(uuid)'::regprocedure) ~ 'so_require_draft' then v_bad := v_bad || ' so_charge_remove'; end if;
  if (select prosrc from pg_proc where oid = 'public.so_charge_gate(uuid, text)'::regprocedure) !~ 'st\.kind = ''aone''' or (select prosrc from pg_proc where oid = 'public.so_charge_gate(uuid, text)'::regprocedure) !~ 'ims_can_write\(''master''\)' then v_bad := v_bad || ' gate-body'; end if;
  if not has_function_privilege('authenticated', 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)', 'execute') or not has_function_privilege('authenticated', 'public.so_charge_remove(uuid)', 'execute') then v_bad := v_bad || ' acl'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - ch-1 did not land as designed:%s - nothing was changed', v_bad); end if;
end $$;
