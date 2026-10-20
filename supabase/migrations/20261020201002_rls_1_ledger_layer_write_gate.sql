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

-- ═══ rls-1 — 원장 · 원가 표 쓰기 닫기 (2026-10-20 · 판정 565 · stk-av-0 조사 · rls-1 이견 1 ~ 7 · 정본 so-module §67 뒤) ═══
--   결함: inv_ledger · inv_layer · inv_layer_cost_add · inv_layer_consume 의 정책이 auth_all(ALL · true · true)이고 authenticated 에 INSERT(· UPDATE) grant 가 있어 로그인한 직원 누구나 PostgREST 로 원장 · 레이어를 쓸 수 있었다(20260816000000:89 · 20260908195949:152 · 157 · 162)
--   고침 ②: 네 표 auth_all 을 지우고 select 정책만(읽기 범위는 그대로 · 원가 열쇠로 가리는 것은 stk-av 차수) · authenticated 의 insert · update · delete · truncate 회수 · service_role 무접촉(EF inv-collect 가 원장을 쓴다)
--   고침 ①: 네 표를 쓰는 invoker 함수 13 을 security definer 로(머리 줄 하나 · 마지막 정의 바이트 그대로 · ACL 그대로 · 안의 ims_require_write 문 그대로) — 직원 신원이 definer 없이 닿던 사슬 셋(po_charge_confirm → inv_layer_post_charge · po_receipt_diff_settle_over → inv_post_receipt_over → inv_layer_post_receipt_over · settle_off_po/off_invoice → inv_post_receipt_off_po → inv_layer_post_receipt_off_po)이 그대로 돈다
--   원장 append-only 는 그대로(authenticated 의 update · delete 는 이미 없었다 · 이번엔 insert 를 더 회수) · 소유자 postgres 는 force_rls false 라 definer 창구는 정책을 지나지 않는다
--   이번 차수 밖(판정 568 · 569): inv_config 는 rls-2 · WMS 작업 표 17 은 의도된 열림 · 다른 inv_* 수집 표는 목록만(rls-1 회신)

-- ═══ ② 네 표 — select 정책만 · 쓰기 grant 회수 ═══
do $$ declare t text; begin
  foreach t in array array['inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume'] loop
    execute format('drop policy if exists auth_all on public.%I', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke insert, update, delete, truncate on public.%I from authenticated', t);
    execute format('alter table public.%I enable row level security', t);
  end loop;
end $$;
comment on policy inv_ledger_select on public.inv_ledger is 'rls-1(판정 565) — 직원은 읽기만 · 쓰기는 창구(definer)와 service_role(EF inv-collect)만 · 원장은 append-only';
comment on policy inv_layer_select on public.inv_layer is 'rls-1(판정 565) — 직원은 읽기만 · 쓰기는 창구(definer) · 재생성(inv_layer_apply)만 · 원가 열쇠로 읽기를 가리는 것은 stk-av 차수';

-- ═══ ① inv_layer_post_charge 재발행 — 원본 20261020153535_rcv_1b_post_now.sql:672 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_layer_post_charge(p_charge_id uuid, p_on date default null, p_alloc uuid default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_charge@2026-10-20.5';   -- rcv-1b(판정 553): 먼저 반영 묶음만 있는 draft 입고가 있는 발주의 배분 줄은 미룬다(deferred)   -- cogs-2(판정 107 · 113 · 114): 얹기 줄 날짜 = 얹히는 순간(p_on 없으면 ims_today) · 새 얹기 줄마다 inv_layer_cost_add_settle · 배분 줄에 posted_on · posted_ledger_id · p_alloc 으로 배분 줄 하나만(재생성)   -- inv-basis-3: 입고 확정자의 문(판정 94 ⑯) · 트랜스퍼 :over: 레이어 제외(판정 95 ㉓)   -- tr-4: 트랜스퍼 배분 갈래(판정 67 · 77 · 묶음 일곱) · tr-4b: 얹은 뒤 자식 레이어로 따라가기(판정 79) · 도착 창구의 문(판정 78)
  v_chg        public.po_charge%rowtype;
  v_cur        text;
  v_base_cur   text;
  v_factor     numeric;                -- 청구 통화 → CAD 계수. 기준통화면 1 · 아니면 po_charge.exchange_rate(CAD per 통화)
  v_alloc      record;
  v_lay        record;
  v_basis      numeric;
  v_n_layers   int;
  v_amount_cad numeric;
  v_share      numeric;
  v_given      numeric;
  v_i          int;
  v_touched    int := 0;
  v_posted     numeric := 0;
  v_no_basis   int := 0;  v_no_basis_amt numeric := 0;
  v_no_layers  int := 0;  v_no_layers_amt numeric := 0;
  v_already    int := 0;  v_already_amt numeric := 0;
  v_deferred   int := 0;  v_deferred_amt numeric := 0;   -- rcv-1b(판정 553)
  v_allocs     jsonb := '[]'::jsonb;
  v_lines      jsonb;
  v_warn       text[] := '{}';
  v_po_number  text;                   -- 발주 번호 · 트랜스퍼 배분이면 트랜스퍼 번호(cost_add.ref_number)
  v_ref        jsonb;
  v_carried    int := 0;               -- tr-4b: 얹은 레이어의 자식(운송 중 · 도착 창고)으로 따라간 행 수(settle 이 센다 · cogs-2: 어느 축이든)
  v_on         date := coalesce(p_on, public.ims_today());   -- cogs-2(판정 114): 얹기 줄 · 나간 몫 줄의 날짜 = 얹히는 순간의 토론토 날짜(재생성은 p_on = 배분 줄 posted_on)
  v_maxid      bigint;                 -- cogs-2(판정 114): 얹히는 순간의 원장 최대 id(실시간만 기록)
  v_aid        bigint;                 -- cogs-2: 새로 든 얹기 줄 id → settle
  v_sub        jsonb;
  v_late_sold  numeric := 0;  v_late_moved numeric := 0;   -- cogs-2: 이 호출이 낸 cost_late · cost_moved 합                  -- tr-4: 배분 줄 반환에 더하는 키(트랜스퍼면 transfer_id · transfer_number · 발주면 빈 객체 — 발주 반환 모양 무변)
begin
  -- 문 — 구매 열쇠(발주 비용 · 지금까지와 같다) · tr-4: transfer 열쇠는 발주 배분이 하나도 없는 비용만(트랜스퍼 운임 · 묶음 일곱 3)
  if not public.ims_can_write('purchasing') then
    if not ((public.ims_can_write('transfer') or public.ims_can_write('wms_receiving')) and not exists (select 1 from public.po_charge_alloc a where a.po_charge_id = p_charge_id and a.po_id is not null))   -- tr-4b(판정 78): 도착 창구(wms_receiving)가 도착 순간 트랜스퍼 운임을 얹는다
       and not ((public.ims_can_write('receiving') or public.ims_can_write('wms_receiving_confirm'))
                and not exists (select 1 from public.po_charge_alloc a where a.po_charge_id = p_charge_id and a.po_id is not null and not exists (select 1 from public.po_receipt r where r.po_id = a.po_id and r.status = 'confirmed'))) then   -- inv-basis-3(판정 94 ⑯): 입고 확정자(receiving · wms_receiving_confirm)는 확정 입고가 있는 발주에만 배분된 비용을 얹는다(po_receipt_confirm_by 가 입고 순간 부른다)
      perform public.ims_require_write('purchasing', 'posted');
    end if;
  end if;

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — no cost was added', p_charge_id; end if;
  if v_chg.status <> 'confirmed' or v_chg.confirmed_at is null then
    raise exception 'Charge % is % — cost is added for confirmed charges only — no cost was added', v_chg.charge_number, v_chg.status;
  end if;

  -- 통화 · 환율 (confirm 이 먼저 막지만 직접 호출·백필 경로도 여기서 막는다)
  select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which charges need an exchange rate — no cost was added'; end if;
  if v_cur is distinct from v_base_cur then
    if v_chg.exchange_rate is null or v_chg.exchange_rate <= 0 then
      raise exception 'Charge % is in % but has no % per % exchange rate — the cost cannot be put on stock without it. Enter the rate on the charge and confirm again — no cost was added',
        v_chg.charge_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
    end if;
    -- ⚠️⚠️⚠️ po_charge.exchange_rate 는 CAD per USD 다 — amount(USD) × exchange_rate = CAD. 곱한다. 나누면 반값인데 에러가 안 난다.
    v_factor := v_chg.exchange_rate;
  else
    v_factor := 1;                                                                                          -- 기준통화(CAD) — 곱하지 않는다
    if v_chg.exchange_rate is not null and v_chg.exchange_rate <> 1 then v_warn := array_append(v_warn, 'exchange_rate_ignored_base_currency'); end if;
  end if;
  if v_chg.total_amount < 0 then v_warn := array_append(v_warn, 'negative_amount'); end if;

  if not exists (select 1 from public.po_charge_alloc a where a.po_charge_id = p_charge_id) then
    raise exception 'Charge % has no allocation lines — nothing to put on cost — no cost was added', v_chg.charge_number;
  end if;

  -- 배분 줄마다(발주 또는 트랜스퍼 — 정확히 하나 · tr-4)
  for v_alloc in
    select a.id, a.po_id, a.amount, p.po_number, a.transfer_id, t.transfer_number
    from public.po_charge_alloc a left join public.po p on p.id = a.po_id left join public.inv_transfer t on t.id = a.transfer_id
    where a.po_charge_id = p_charge_id
      and (p_alloc is null or a.id = p_alloc)                                                                -- cogs-2: 재생성은 배분 줄 하나씩 부른다(posted_on 자리)
    order by p.po_number, t.transfer_number
  loop
    v_po_number  := coalesce(v_alloc.po_number, v_alloc.transfer_number);
    if v_alloc.transfer_id is not null and v_alloc.transfer_number is null then                                    -- tr-4: 이 로그인이 못 보는 트랜스퍼(RLS) — 조용히 0 을 얹지 않는다 · transfer 열쇠(또는 그 창고 열쇠)로
      raise exception 'Charge % is allocated to a transfer this login cannot see — the transfer key (or a warehouse key for that transfer) is needed — no cost was added', v_chg.charge_number;
    end if;
    v_ref        := case when v_alloc.transfer_id is not null then jsonb_build_object('transfer_id', v_alloc.transfer_id, 'transfer_number', v_alloc.transfer_number) else '{}'::jsonb end;
    -- ⚠️⚠️⚠️ CAD per USD × 청구 통화 금액 = CAD. 곱한다.
    v_amount_cad := v_alloc.amount * v_factor;

    -- 멱등 — 이 비용·이 배분 줄로 이미 얹은 행이 있으면 건너뛴다(이견 4)
    if exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number and ca.line_ref = v_alloc.id::text) then
      v_already := v_already + 1; v_already_amt := v_already_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'already_posted', 'layers', 0, 'posted_cad', 0) || v_ref);
      continue;
    end if;
    -- rcv-1b(판정 553): 그 발주에 먼저 반영 묶음이 있는 draft 입고가 있으면 얹지 않고 미룬다 — 행 0 · posted_on 비움 · 마지막 확정 ⓕ 가 not exists cost_add 로 다시 부른다 · 재생성(flush_adds ⓑ)도 같은 창구라 같은 답
    if v_alloc.po_id is not null and exists (select 1 from public.po_receipt r join public.po_receipt_post p on p.receipt_id = r.id where r.po_id = v_alloc.po_id and r.status = 'draft') then
      v_deferred := v_deferred + 1; v_deferred_amt := v_deferred_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'deferred', 'layers', 0, 'posted_cad', 0) || v_ref);
      continue;
    end if;

    -- 그 발주의 IMS 입고 레이어 — po_line 을 거쳐(이견 1) · 불러온 레이어는 cost_source 로 갈린다(이견 2)
    -- tr-4 트랜스퍼: 그 문서의 도착 레이어(origin transfer · doc_number TRF-n · 도착 창고 — leg 4 · sent_more over_4) · return(:settle: · 출발 창고) 제외 · found 는 조정 문서 레이어라 안 걸린다 · lost 는 레이어가 없다(판정 77 — 도착한 물건이 전부 떠안는다)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0)
      into v_n_layers, v_basis
    from public.inv_layer x
    left join public.po_line pl on pl.id::text = public.inv_po_line_of(x.line_ref)   -- rcv-1a: 묶음 레이어(:pN)도 같은 발주의 레이어 집합
    where (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_alloc.po_id)
       or (v_alloc.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_alloc.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%');   -- inv-basis-3(판정 95 ㉓): 더 온 몫(sent_more · :over:) 레이어에는 운임 없음 — 도착한 물건에만

    if v_n_layers = 0 then
      v_no_layers := v_no_layers + 1; v_no_layers_amt := v_no_layers_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'no_layers', 'layers', 0, 'posted_cad', 0) || v_ref);
      continue;
    end if;
    if v_basis = 0 then
      -- 정본 D — 기준이 0 이면 버린다 · 수량 비례로 대신하지 않는다(Cin7 CostDistributionType='Cost' 와 방식이 갈린다)
      v_no_basis := v_no_basis + 1; v_no_basis_amt := v_no_basis_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'no_basis', 'layers', v_n_layers, 'posted_cad', 0) || v_ref);
      continue;
    end if;

    -- 금액 비율(unit_cost × qty · 정본 B) · 6자리 · 끝수는 마지막 레이어
    v_given := 0; v_i := 0; v_lines := '[]'::jsonb;
    for v_lay in
      select x.id, x.sku, x.warehouse, x.line_ref, x.qty, x.unit_cost, x.unit_cost * x.qty as basis
      from public.inv_layer x
      left join public.po_line pl on pl.id::text = public.inv_po_line_of(x.line_ref)   -- rcv-1a: 묶음 레이어(:pN)도 같은 발주의 레이어 집합
      where (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_alloc.po_id)
         or (v_alloc.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_alloc.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')   -- inv-basis-3(판정 95 ㉓)
      order by x.sku, x.line_ref, x.id
    loop
      v_i := v_i + 1;
      if v_i = v_n_layers then
        v_share := v_amount_cad - v_given;                                                                -- 마지막 레이어에 잔액 — 합이 정확히 금액과 같다
      else
        v_share := round(v_amount_cad * v_lay.basis / v_basis, 6);
      end if;
      v_given := v_given + v_share;
      insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      values (v_lay.id, 'landed', v_share, v_on, v_chg.charge_number, v_alloc.id::text, v_po_number)                 -- cogs-2(판정 114): 날짜 = 얹히는 순간(청구서 날짜 charge_date 는 비용 문서에 그대로)
      returning id into v_aid;
      v_touched := v_touched + 1;
      v_sub := public.inv_layer_cost_add_settle(v_aid);                                                        -- cogs-2(판정 107 · 108): 새 얹기 줄을 셋으로 — 남은 몫 · 옮겨 간 몫(자식 carried · 어느 축이든 · 판정 79 · 110) · 팔리거나 빠진 몫(cost_late)
      v_carried := v_carried + coalesce((v_sub ->> 'carried_rows')::int, 0);
      v_late_sold := v_late_sold + coalesce((v_sub ->> 'sold_amount')::numeric, 0);  v_late_moved := v_late_moved + coalesce((v_sub ->> 'moved_amount')::numeric, 0);
      v_lines := v_lines || jsonb_build_object('layer_id', v_lay.id, 'sku', v_lay.sku, 'warehouse', v_lay.warehouse, 'po_line_id', v_lay.line_ref,
                                               'qty', v_lay.qty, 'unit_cost', v_lay.unit_cost, 'basis', v_lay.basis, 'share_cad', v_share);
    end loop;
    v_posted := v_posted + v_given;
    if p_on is null then                                                                                     -- cogs-2(판정 114): 실시간이 얹힌 순간을 배분 줄에 남긴다(재생성은 이것으로 같은 자리 · 같은 날 안의 앞뒤까지 재현 · 17-f (가) 모양)
      select max(g.id) into v_maxid from public.inv_ledger g;
      update public.po_charge_alloc x set posted_on = v_on, posted_ledger_id = v_maxid where x.id = v_alloc.id and x.posted_on is null;
    end if;
    v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                               'status', 'posted', 'layers', v_n_layers, 'basis', v_basis, 'posted_cad', v_given, 'lines', v_lines) || v_ref);
  end loop;

  return jsonb_build_object(
    'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'charge_kind', v_chg.kind, 'cost_add_kind', 'landed', 'charge_date', v_chg.charge_date,
    'currency', v_cur, 'base_currency', v_base_cur,
    'fx_rate', case when v_cur is distinct from v_base_cur then v_chg.exchange_rate else null end,
    'fx_direction', case when v_cur is distinct from v_base_cur then v_base_cur || ' per ' || coalesce(v_cur, '?') || ' — amount × rate'
                         else v_base_cur || ' — base currency, no conversion (× 1)' end,
    'amount_total', v_chg.total_amount, 'amount_total_cad', v_chg.total_amount * v_factor,
    'layers_touched', v_touched, 'amount_posted_cad', v_posted, 'posted_on', v_on, 'late_sold_cad', v_late_sold, 'late_moved_cad', v_late_moved,   -- cogs-2
    'no_basis_allocs', v_no_basis, 'no_basis_amount_cad', v_no_basis_amt,
    'no_layers_allocs', v_no_layers, 'no_layers_amount_cad', v_no_layers_amt,
    'already_posted_allocs', v_already, 'already_posted_amount_cad', v_already_amt,
    'deferred_allocs', v_deferred, 'deferred_amount_cad', v_deferred_amt,   -- rcv-1b(판정 553)
    'allocs', v_allocs, 'builder', c_version, 'warnings', to_jsonb(v_warn))
    || case when v_carried > 0 then jsonb_build_object('carried_rows', v_carried) else '{}'::jsonb end;   -- tr-4b: 따라간 행이 있을 때만 키(발주 반환 모양 무변)
exception
  when unique_violation then
    raise exception 'Charge % — a landed cost row with the same key already exists (%) — no cost was added', v_chg.charge_number, sqlerrm;
end;
$$;

-- ═══ ① inv_layer_post_receipt 재발행 — 원본 20261020153535_rcv_1b_post_now.sql:71 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_layer_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt@2026-10-20.4';   -- po-disc-2: 핀 → 확정 인보이스 실제 단가(낸 돈 ÷ 받은 개수 · 인보이스 체인 · 인보이스 환율) → PO 기준
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_cur      text;
  v_base     text;
  v_factor   numeric;                 -- PO 통화 → CAD 계수(PO 기준 폴백에만) · 기준통화면 1 · 아니면 po.exchange_rate · 없으면 null(PO 기준을 쓰는 줄에서만 거부)
  v_disc     numeric;                 -- po-disc-1 · PO 할인 체인 계수(1 = 할인 없음) — 입고에 적힌 값 · 없으면 지금 체인(po_discount_factor)을 읽어 적는다
  v_disc_src text;                    -- po-disc-1 · receipt_stored | po_discount_now
  v_created  int := 0;
  v_existing int := 0;
  v_qty      numeric := 0;
  v_cost     numeric := 0;
  v_rows     int := 0;
  v_price    numeric;
  v_unit     numeric;
  v_layer_id bigint;
  v_lines    jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
  x          record;
  -- po-disc-2
  v_pin      public.po_receipt_cost%rowtype;
  v_inv      record;                  -- 확정 인보이스(이 PO 줄 · confirmed_at 가장 늦은 것) — id · invoice_number · currency_id · exchange_rate
  v_basis    text;                    -- pinned | invoice | po
  v_qty_b    numeric;                 -- 인보이스 줄 qty 합(양수 줄)
  v_amt_b    numeric;                 -- 낸 돈 합(체인 뒤 · 문서 통화)
  v_ifactor  numeric;                 -- 이 줄에 쓴 할인 체인(인보이스 · 또는 PO)
  v_net      numeric;                 -- 문서 통화 단가(반올림 없음)
  v_fx       numeric;                 -- 이 줄에 쓴 환율(기준통화면 null)
  v_fx_src   text;                    -- invoice | po | null
  v_fx_cur   uuid;                    -- 이 줄의 통화(인보이스 또는 PO)
  v_icur     text;
  v_ids      uuid[];
  v_n_inv    int;
  v_inv_no   text;
  v_fx_seen  jsonb := '[]'::jsonb;    -- 반환 fx_rates — 실제로 쓴 (출처 · 환율) 묶음
begin

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — no cost layers were created', p_receipt_id; end if;
  if not (v_r.status = 'confirmed' and v_r.confirmed_at is not null) and not (v_r.status = 'draft' and exists (select 1 from public.po_receipt_post p where p.receipt_id = p_receipt_id)) then   -- rcv-1b(이견 1): 먼저 반영 묶음이 있는 draft 입고도 받는다(창구 post_now · 재생성 ims_rcv)
    raise exception 'Receipt % is % — cost layers are built for confirmed receipts, or for a draft receipt with a post-now batch — no cost layers were created', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — no cost layers were created', v_r.receipt_number; end if;

  -- 통화 · 환율 — PO 환율은 PO 기준 폴백에만 쓴다(인보이스 기준 줄은 인보이스 환율) · 없으면 그 줄에서 거부
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base from public.inv_config k where k.key = 'base_currency';
  if v_base is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — no cost layers were created'; end if;
  if v_cur is distinct from v_base then
    -- ⚠️⚠️⚠️ po.exchange_rate 는 CAD per USD 다 — unit_price(USD) × exchange_rate = CAD. 곱한다. 나누면 원가가 반으로 줄어드는데 에러가 안 난다.
    v_factor := case when v_po.exchange_rate is not null and v_po.exchange_rate > 0 then v_po.exchange_rate end;
  else
    v_factor := 1;                                                                                          -- 기준통화(CAD) — 환율을 곱하지 않는다(정본 1239행 「이미 CAD」)
    if v_po.exchange_rate is not null and v_po.exchange_rate <> 1 then v_warn := array_append(v_warn, 'exchange_rate_ignored_base_currency'); end if;
  end if;

  -- po-disc-1 · PO 할인 계수 — ⭐ 입고 확정 순간의 체인(그 뒤 PO 할인이 바뀐 몫은 (나) 인보이스 차액 차수) · 처음 세울 때 po_receipt 에 적어 재생성이 같은 값을 쓴다
  if v_r.discount_factor is not null then
    v_disc := v_r.discount_factor; v_disc_src := 'receipt_stored';
  else
    v_disc := public.po_discount_factor(v_po.id); v_disc_src := 'po_discount_now';
    update public.po_receipt set discount_factor = v_disc where id = p_receipt_id and discount_factor is null;
  end if;

  -- 원장 행을 라인 단위로 접는다(bin 을 버린다 · 이견 2 · 3) — 이 RCV 의 ims po_in 행만
  for x in
    select l.line_ref, l.sku, l.warehouse, sum(l.qty_delta) as qty, min(l.occurred_on) as received_on, count(*)::int as ledger_rows
    from public.inv_ledger l
    where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in'
      and l.doc_number = v_r.receipt_number and l.qty_delta > 0
      and l.line_ref not like '%:over' and l.line_ref not like '%:offpo'                                -- ⑤-6c1 off-PO 행은 형제 창구 inv_layer_post_receipt_off_po 가 만든다(라인이 없어 po_line 조회가 안 된다)                                                              -- ⭐ 2026-09-20 초과분 행(over 닫기 · line_ref = po_line_id||':over')은 형제 창구 inv_layer_post_receipt_over 가 만든다 — 여기서 접으면 po_line 을 못 찾아 터지거나(접미어) free 를 발주 단가로 매긴다
    group by l.line_ref, l.sku, l.warehouse
    order by min(l.id), l.line_ref                                                                                            -- rcv-1a: 원장에 든 순서(묶음 :p1 이 먼저) — 재생성의 레이어 순서(id · FIFO 동률)가 실시간과 같게 · 한 입고에 같은 SKU 가 둘일 때만 뜻이 있다
  loop
    v_rows := v_rows + x.ledger_rows;
    -- 멱등 — 같은 4키의 레이어가 있으면 건너뛴다(inv_layer_apply_po_in 과 같은 규칙) · ⚠️ po-disc-2: 있는 레이어에는 핀을 쓰지 않는다(레이어와 다른 값을 적을 수 있다 — 기존 레이어는 전환 재생성이 처음 부르며 핀다)
    if exists (select 1 from public.inv_layer y
                where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = x.line_ref
                  and y.sku = x.sku and y.warehouse = x.warehouse) then
      v_existing := v_existing + 1;
      continue;
    end if;
    -- 단가 — line_ref 가 po_line_id 다(원장 이식 2차 · Caleb 실측 확정)
    select pl.unit_price into v_price from public.po_line pl where pl.id::text = public.inv_po_line_of(x.line_ref);   -- rcv-1a: 꼬리 :pN 은 묶음 몫 · 같은 po_line
    if v_price is null then
      raise exception 'Ledger row % / % on % points at a PO line (%) that does not exist — the ledger is wrong, not this function — no cost layers were created', x.sku, x.warehouse, v_r.receipt_number, x.line_ref;
    end if;

    -- ═══ po-disc-2 · 단가 순서: ① 핀 → ② 확정 인보이스(판정 392 · 398) → ③ PO 기준(po-disc-1) ═══
    v_pin := null; v_inv := null; v_basis := null; v_qty_b := null; v_amt_b := null; v_ifactor := null; v_net := null; v_fx := null; v_fx_src := null; v_fx_cur := null; v_ids := null; v_icur := null; v_inv_no := null;
    select * into v_pin from public.po_receipt_cost k where k.receipt_id = p_receipt_id and k.po_line_id = public.inv_po_line_of(x.line_ref)::uuid;   -- rcv-1a: 핀은 라인당 하나 — 첫 묶음이 넣고 뒤 묶음은 읽는다(판정 394)
    if found then
      v_basis := 'pinned'; v_unit := v_pin.unit_cost_cad; v_net := v_pin.unit_price_net; v_fx := v_pin.exchange_rate; v_fx_src := v_pin.exchange_rate_source; v_ifactor := v_pin.discount_factor; v_fx_cur := v_pin.currency_id;
      v_qty_b := v_pin.qty_basis; v_amt_b := v_pin.amount_basis;
      select i.invoice_number into v_inv_no from public.po_invoice i where i.id = v_pin.invoice_id;
    else
      -- ② 확정 인보이스 — 이 PO 줄을 가리키는 goods 줄이 있는 confirmed invoice · 둘 이상이면 confirmed_at 이 가장 늦은 것 + 경고
      select count(distinct i.id) into v_n_inv
        from public.po_invoice i join public.po_invoice_line il on il.po_invoice_id = i.id
       where i.doc_kind = 'invoice' and i.status = 'confirmed' and il.line_kind = 'goods' and il.po_line_id = public.inv_po_line_of(x.line_ref)::uuid;   -- rcv-1a
      if v_n_inv > 1 then v_warn := array_append(v_warn, 'multiple_confirmed_invoices:' || x.line_ref); end if;
      select i.id, i.invoice_number, i.currency_id, i.exchange_rate into v_inv
        from public.po_invoice i
       where i.doc_kind = 'invoice' and i.status = 'confirmed'
         and exists (select 1 from public.po_invoice_line il where il.po_invoice_id = i.id and il.line_kind = 'goods' and il.po_line_id = public.inv_po_line_of(x.line_ref)::uuid)   -- rcv-1a
       order by i.confirmed_at desc nulls last, i.invoice_number desc
       limit 1;
      if v_inv.id is not null then
        v_inv_no := v_inv.invoice_number;
        if exists (select 1 from public.po_invoice_line il where il.po_invoice_id = v_inv.id and il.line_kind = 'goods' and il.po_line_id = public.inv_po_line_of(x.line_ref)::uuid and il.qty_ea < 0) then   -- rcv-1a
          v_warn := array_append(v_warn, 'negative_invoice_line_excluded:' || x.line_ref);                              -- ⬜2: 정정 줄은 평균에서 뺀다(실물 0)
        end if;
        v_ifactor := public.po_invoice_discount_factor(v_inv.id);
        select coalesce(sum(il.qty_ea), 0),
               coalesce(sum(il.unit_price * il.qty_ea) filter (where il.is_payable and il.unit_price > 0), 0) * v_ifactor,
               array_agg(il.id order by il.line_no)
          into v_qty_b, v_amt_b, v_ids
          from public.po_invoice_line il
         where il.po_invoice_id = v_inv.id and il.line_kind = 'goods' and il.po_line_id = public.inv_po_line_of(x.line_ref)::uuid and il.qty_ea > 0;   -- rcv-1a
        if v_qty_b > 0 then
          v_basis := 'invoice';
          v_net := v_amt_b / v_qty_b;                                                                              -- 판정 398: 낸 돈 ÷ 받은 개수(무상 줄은 개수만) · 반올림 없음
          v_fx_cur := v_inv.currency_id;
          select c.code into v_icur from public.ref_currency c where c.id = v_inv.currency_id;
          if v_icur is not distinct from v_base then
            v_fx := null; v_fx_src := null; v_unit := v_net;
          elsif v_inv.exchange_rate is not null and v_inv.exchange_rate > 0 then
            v_fx := v_inv.exchange_rate; v_fx_src := 'invoice'; v_unit := v_net * v_fx;
          elsif v_inv.currency_id = v_po.currency_id and v_po.exchange_rate is not null and v_po.exchange_rate > 0 then
            v_fx := v_po.exchange_rate; v_fx_src := 'po'; v_unit := v_net * v_fx;
          else
            raise exception 'Invoice % (PO %) is in % but has no % per % exchange rate, and the order''s rate is not for % — stock cost cannot be worked out. Enter the rate in the invoice header ("Exchange rate") and run again — no cost layers were created',
              v_inv.invoice_number, v_po.po_number, coalesce(v_icur, '?'), v_base, coalesce(v_icur, '?'), coalesce(v_icur, '?');
          end if;
        end if;
      end if;
      if v_basis is null then
        -- ③ PO 기준(인보이스 줄 없음) — po-disc-1 그대로 · 경고
        v_basis := 'po'; v_warn := array_append(v_warn, 'no_invoice_line:' || x.line_ref);
        if v_factor is null then
          raise exception 'PO % is in % but has no % per % exchange rate, and line % has no confirmed invoice line to take the rate from — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and run again — no cost layers were created',
            v_po.po_number, coalesce(v_cur, '?'), v_base, coalesce(v_cur, '?'), x.sku;
        end if;
        v_ifactor := v_disc; v_net := v_price * v_disc; v_fx_cur := v_po.currency_id;
        if v_cur is distinct from v_base then v_fx := v_factor; v_fx_src := 'po'; else v_fx := null; v_fx_src := null; end if;
        -- ⚠️⚠️⚠️ CAD per USD × USD 단가 = CAD 단가. 곱한다. (기준통화면 v_factor = 1) · po-disc-1: × PO 할인 계수(체인 · 더하지 않는다) · 반올림 없음(옛 레이어와 같은 자릿수)
        v_unit := v_price * v_disc * v_factor;
      end if;
    end if;

    insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
    values (x.sku, x.warehouse, 'purchase', v_r.receipt_number, x.line_ref, null, x.received_on, true, x.qty, v_unit, 'po_line')
    returning id into v_layer_id;
    v_created := v_created + 1;
    v_qty  := v_qty  + x.qty;
    v_cost := v_cost + x.qty * v_unit;
    -- po-disc-2 · 핀 — 이 호출이 레이어를 만들 때만 · 판정 394(입고 순간 값으로 못 박는다)
    if v_basis <> 'pinned' then
      insert into public.po_receipt_cost (receipt_id, po_line_id, source, invoice_id, invoice_line_ids, qty_basis, amount_basis, unit_price_net, discount_factor, currency_id, exchange_rate, exchange_rate_source, unit_cost_cad, builder)
      values (p_receipt_id, public.inv_po_line_of(x.line_ref)::uuid, v_basis, case when v_basis = 'invoice' then v_inv.id end, v_ids, v_qty_b, v_amt_b, v_net, v_ifactor, v_fx_cur, v_fx, v_fx_src, v_unit, c_version);
    end if;
    if v_fx_src is not null and not (v_fx_seen @> jsonb_build_array(jsonb_build_object('source', v_fx_src, 'rate', v_fx))) then
      v_fx_seen := v_fx_seen || jsonb_build_object('source', v_fx_src, 'rate', v_fx);
    end if;
    v_lines := v_lines || jsonb_build_object('layer_id', v_layer_id, 'po_line_id', x.line_ref, 'sku', x.sku, 'warehouse', x.warehouse,
                                             'qty', x.qty, 'ledger_rows', x.ledger_rows, 'unit_price', v_price, 'unit_price_net', v_net, 'unit_cost_cad', v_unit, 'received_on', x.received_on,
                                             'cost_basis', v_basis, 'invoice_number', v_inv_no, 'discount_factor', v_ifactor, 'exchange_rate', v_fx, 'exchange_rate_source', v_fx_src,
                                             'qty_basis', v_qty_b, 'amount_basis', v_amt_b);   -- po-disc-2
  end loop;
  if v_rows = 0 then v_warn := array_append(v_warn, 'no_ledger_rows_for_receipt'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'currency', v_cur, 'base_currency', v_base,
    'fx_rates', v_fx_seen,                                                                   -- po-disc-2: 실제로 쓴 (출처 · 환율) 묶음 — 줄마다 lines[].exchange_rate · exchange_rate_source
    'fx_direction', case when jsonb_array_length(v_fx_seen) = 0 then v_base || ' — base currency or nothing created, no conversion (× 1)'
                         else v_base || ' per document currency — unit_price_net × rate · rate per line (see lines[].exchange_rate_source)' end,   -- ⚠️ 거짓이면 안 된다 — 쓴 환율은 줄마다 적는다
    'discount_factor', v_disc, 'discount_factor_source', v_disc_src,                      -- po-disc-1(PO 체인 · PO 기준 줄에만 쓴다)
    'ledger_rows', v_rows, 'layers_created', v_created, 'layers_existing', v_existing,
    'qty', v_qty, 'cost_total_cad', v_cost, 'cost_source', 'po_line', 'builder', c_version,
    'lines', v_lines, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ① inv_layer_post_receipt_off_po 재발행 — 원본 20260929195458_inv_basis_2.sql:444 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_layer_post_receipt_off_po(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt_off_po@2026-09-29.1';   -- inv-basis-3: off_invoice 행도
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_wh       text;
  v_sku      text;
  v_ref      text;
  v_qty      numeric;
  v_recv_on  date;
  v_rows     int;
  v_unit     numeric;
  v_src      text;
  v_cur      text;
  v_base     text;
  v_factor   numeric;
  v_layer_id bigint;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — no cost layer was created', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — no cost layer was created', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  if v_d.kind not in ('off_po', 'off_invoice') or v_d.resolved_at is null or v_d.resolution not in ('accepted_free', 'accepted_billed') then   -- inv-basis-3: off_invoice 도 같은 창구(line_ref <diff>:offpo 그대로)
    raise exception 'Off-PO % on % is not accepted (free or billed) — no cost layer was created', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  v_ref := v_d.id::text || ':offpo';

  -- off-PO 원장 행을 접는다(한 차이 · 한 SKU · 한 창고 · 한 칸 ⇒ 레이어 하나)
  select sum(l.qty_delta), min(l.occurred_on), count(*)::int into v_qty, v_recv_on, v_rows
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in'
    and l.doc_number = v_r.receipt_number and l.line_ref = v_ref and l.sku = v_sku and l.warehouse = v_wh and l.qty_delta > 0;
  if coalesce(v_rows, 0) = 0 then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', 0, 'layers_created', 0, 'layers_existing', 0, 'qty', 0, 'builder', c_version, 'warnings', '["no_ledger_rows_for_off_po"]'::jsonb);
  end if;

  -- 멱등 — 같은 4키(purchase · RCV · <diff>:offpo · sku · warehouse)의 레이어가 있으면 건너뛴다
  if exists (select 1 from public.inv_layer y
              where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = v_ref and y.sku = v_sku and y.warehouse = v_wh) then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', v_rows, 'layers_created', 0, 'layers_existing', 1, 'qty', v_qty, 'builder', c_version, 'warnings', '[]'::jsonb);
  end if;

  if v_d.resolution = 'accepted_free' then
    v_unit := 0; v_src := 'free';                                                                         -- ⭐ 낸 돈이 없다 — 진짜 0(unknown 아님 · over 선례)
  else
    -- ⭐ 사람이 입력한 단가(PO 통화) × 그 PO 의 환율(CAD per USD · 곱한다 · 기준통화면 ×1) — inv_layer_post_receipt 와 같은 식
    if v_d.unit_price is null or v_d.unit_price <= 0 then
      raise exception 'Off-PO % on % is billed but has no unit price — no cost layer was created', coalesce(v_sku, '?'), v_r.receipt_number;
    end if;
    select * into v_po from public.po where id = v_r.po_id;
    select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
    select k.value into v_base from public.inv_config k where k.key = 'base_currency';
    if v_base is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — no cost layer was created'; end if;
    if v_cur is distinct from v_base then
      if v_po.exchange_rate is null or v_po.exchange_rate <= 0 then
        raise exception 'PO % is in % but has no % per % exchange rate — the off-PO cost cannot be worked out without it. Enter the rate in the order header and decide again — no cost layer was created',
          v_po.po_number, coalesce(v_cur, '?'), v_base, coalesce(v_cur, '?');
      end if;
      v_factor := v_po.exchange_rate;
    else
      v_factor := 1;
    end if;
    v_unit := v_d.unit_price * v_factor; v_src := 'manual';
  end if;

  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (v_sku, v_wh, 'purchase', v_r.receipt_number, v_ref, null, v_recv_on, true, v_qty, v_unit, v_src)
  returning id into v_layer_id;

  return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'warehouse', v_wh, 'resolution', v_d.resolution,
                            'ledger_rows', v_rows, 'layers_created', 1, 'layers_existing', 0, 'layer_id', v_layer_id,
                            'qty', v_qty, 'unit_price', v_d.unit_price, 'currency', v_cur, 'fx_rate', case when v_cur is distinct from v_base then v_factor end,
                            'unit_cost', v_unit, 'cost_source', v_src, 'cost_total_cad', v_qty * v_unit, 'received_on', v_recv_on,
                            'builder', c_version, 'warnings', '[]'::jsonb);
end;
$$;

-- ═══ ① inv_layer_post_receipt_over 재발행 — 원본 20261020143921_rcv_1a_receipt_line_ref_suffix.sql:1479 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_layer_post_receipt_over(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt_over@2026-09-20.1';
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_wh       text;
  v_sku      text;
  v_line_no  int;
  v_ref      text;
  v_qty      numeric;
  v_recv_on  date;
  v_rows     int;
  v_unit     numeric;
  v_src      text;
  v_layer_id bigint;
  v_base_id  bigint;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — no cost layer was created', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — no cost layer was created', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select pl.line_no into v_line_no from public.po_line pl where pl.id = v_d.po_line_id;
  if v_d.kind <> 'over' or v_d.resolved_at is null or v_d.resolution not in ('free', 'billed', 'credited') then
    raise exception 'Line % (%) on % is not an over difference settled as free, billed or credited — no cost layer was created',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  v_ref := v_d.po_line_id::text || ':over';

  -- 초과분 원장 행을 접는다(한 라인 · 한 SKU · 한 창고 ⇒ 레이어 하나 · 빈은 버린다)
  select sum(l.qty_delta), min(l.occurred_on), count(*)::int into v_qty, v_recv_on, v_rows
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in'
    and l.doc_number = v_r.receipt_number and l.line_ref = v_ref and l.sku = v_sku and l.warehouse = v_wh and l.qty_delta > 0;
  if coalesce(v_rows, 0) = 0 then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', 0, 'layers_created', 0, 'layers_existing', 0, 'qty', 0, 'builder', c_version, 'warnings', '["no_ledger_rows_for_over"]'::jsonb);
  end if;

  -- 멱등 — 같은 4키(purchase · RCV · po_line_id:over · sku · warehouse)의 레이어가 있으면 건너뛴다
  if exists (select 1 from public.inv_layer y
              where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = v_ref and y.sku = v_sku and y.warehouse = v_wh) then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', v_rows, 'layers_created', 0, 'layers_existing', 1, 'qty', v_qty, 'builder', c_version, 'warnings', '[]'::jsonb);
  end if;

  if v_d.resolution = 'free' then
    v_unit := 0; v_src := 'free';                                                                         -- ⭐ 낸 돈이 없다 — 자산이 공중에서 생기지 않게 · unknown 이 아니다(진짜 0)
  else
    -- ⭐ 같은 배 · 같은 값 — 기준 레이어의 unit_cost 그대로. 환율 곱하기 식은 inv_layer_post_receipt 한 곳에만 산다.
    select y.id, y.unit_cost into v_base_id, v_unit
    from public.inv_layer y
    where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and public.inv_po_line_of(y.line_ref) = v_d.po_line_id::text and y.sku = v_sku and y.warehouse = v_wh   -- rcv-1a
    order by y.id limit 1;
    if v_base_id is null then
      raise exception 'Line % (%) on % is settled as "%" but the receipt''s own cost layer is missing (was it confirmed without an exchange rate?) — enter the rate on the order header and run inv_post_receipt for % first, then run this again — no cost layer was created',
        coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution, v_r.receipt_number;
    end if;
    v_src := 'po_line';
  end if;

  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (v_sku, v_wh, 'purchase', v_r.receipt_number, v_ref, null, v_recv_on, true, v_qty, v_unit, v_src)
  returning id into v_layer_id;

  return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'warehouse', v_wh, 'resolution', v_d.resolution,
                            'ledger_rows', v_rows, 'layers_created', 1, 'layers_existing', 0, 'layer_id', v_layer_id, 'base_layer_id', v_base_id,
                            'qty', v_qty, 'unit_cost', v_unit, 'cost_source', v_src, 'cost_total_cad', v_qty * v_unit, 'received_on', v_recv_on,
                            'builder', c_version, 'warnings', '[]'::jsonb);
end;
$$;

-- ═══ ① inv_post_adjust 재발행 — 원본 20260928142722_inv_adjust_a.sql:422 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_post_adjust(p_adjust_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_post_adjust@2026-09-28.1';
        v_a public.inv_adjust%rowtype; v_existing int; v_rows int := 0; v_qty numeric := 0; v_cost jsonb; v_keys jsonb := '{}'::jsonb; l record;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id;
  if not found then raise exception 'Adjustment not found — nothing was posted to the ledger'; end if;
  if v_a.status <> 'confirmed' then raise exception 'Adjustment % is % — the ledger takes confirmed adjustments only — nothing was posted to the ledger', v_a.adjust_number, v_a.status; end if;
  select count(*) into v_existing from public.inv_ledger e where e.doc_type = 'adjustment' and e.doc_number = v_a.adjust_number and e.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_ea_posted', 0, 'warnings', '["already_posted"]'::jsonb);
  end if;
  for l in select * from public.inv_adjust_line x where x.adjust_id = p_adjust_id and x.delta is not null and x.delta <> 0 order by x.line_no loop
    v_cost := public.inv_layer_post_adjust(v_a.adjust_number, l.id::text, l.sku, v_a.warehouse, l.delta, v_a.posted_on, l.unit_cost, null);   -- ⭐ 레이어 먼저 · 결과를 raw.cost 에
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_a.posted_on, case when l.delta > 0 then 1 else 2 end, l.sku, v_a.warehouse, l.bin, l.delta,
            case when l.delta > 0 and l.unit_cost is not null then 'adjust_new' else 'adjust_existing' end, 'adjustment', v_a.adjust_number, v_a.id::text, l.id::text,
            nullif(v_cost->>'amount', '')::numeric, 'ims',
            jsonb_build_object('kind', 'adjust', 'poster', c_version,
              'header', jsonb_build_object('adjust_number', v_a.adjust_number, 'adjusted_on', v_a.posted_on, 'warehouse_id', v_a.warehouse_id, 'warehouse', v_a.warehouse, 'report_id', v_a.report_id, 'account_code', v_a.account_code, 'note', v_a.note, 'confirmed_by', v_a.confirmed_by),
              'line', jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'bin_id', l.bin_id, 'bin', l.bin, 'mode', l.mode, 'qty_input', l.qty_input,
                                         'seen_ledger', l.seen_ledger, 'seen_picked', l.seen_picked, 'delta', l.delta, 'reason', l.reason, 'reason_note', l.reason_note, 'unit_cost', l.unit_cost),
              'rule', format('%s: %s %s → delta %s (ledger %s − picked %s = shelf %s)', l.mode, l.qty_input, case when l.mode = 'set' then 'target' else 'input' end, l.delta, l.seen_ledger, l.seen_picked, l.seen_ledger - l.seen_picked),
              'cost', v_cost));
    v_rows := v_rows + 1; v_qty := v_qty + l.delta; v_keys := v_keys || jsonb_build_object(l.id::text, v_cost);
  end loop;
  return jsonb_build_object('adjust_id', v_a.id, 'adjust_number', v_a.adjust_number, 'already_posted', false, 'existing_rows', 0, 'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_keys, 'poster', c_version);
exception when unique_violation then
  raise exception 'Adjustment % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_a.adjust_number, sqlerrm;
end;
$$;

-- ═══ ① inv_post_credit 재발행 — 원본 20260925012354_so_credit_c1.sql:332 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_post_credit(p_credit_id uuid, p_occurred_on date) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_credit@2026-09-25.1';
  v_cr       public.so_credit%rowtype;
  v_existing int;
  v_alloc    jsonb;
  v_costs    jsonb := '{}'::jsonb;
  v_rows     int := 0;
  v_qty      numeric := 0;
  v_warn     text[] := '{}';
  k          record;
  b          record;
begin
  perform public.ims_require_write('sales', 'posted');        -- ⭐ 첫 줄 — 호출자(auth.uid())의 sales 쓰기

  select * into v_cr from public.so_credit c where c.id = p_credit_id;
  if not found then raise exception 'Credit note not found — nothing was posted to the ledger'; end if;
  if v_cr.status <> 'issued' then raise exception 'Credit note % is % — the ledger takes issued credit notes only — nothing was posted to the ledger', v_cr.credit_number, v_cr.status; end if;
  if v_cr.warehouse_name is null then raise exception 'Credit note % has no warehouse — nothing was posted to the ledger', v_cr.credit_number; end if;

  select count(*) into v_existing from public.inv_ledger l where l.doc_type = 'creditnote' and l.doc_number = v_cr.credit_number and l.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;
  if p_occurred_on > public.ims_today() then v_warn := array_append(v_warn, 'credited_on_in_future'); end if;

  -- restock 줄 모으기 — 판매 단위 → EA(pack_factor) · 낱개 SKU(세트는 parent) · 원 판매 오더 번호(IMS so_line → so · Cin7 cin7_order_number)
  with a as (
    select cl.id as line_id, cl.line_no, cl.product_id, cl.sku as credited_sku, cl.qty_returned, cl.unit_price, cl.restock_bin as bin,
           coalesce(pp.sku, pr.sku) as base_sku, coalesce(pr.pack_factor, 1) as pack_factor, cl.qty_returned * coalesce(pr.pack_factor, 1) as qty_ea,
           coalesce(s.so_number, v_cr.cin7_order_number) as origin_sale
      from public.so_credit_line cl
      join public.product pr on pr.id = cl.product_id
      left join public.product pp on pp.id = pr.parent_product_id
      left join public.so_line sl on sl.id = cl.so_line_id
      left join public.so s on s.id = sl.so_id
     where cl.credit_id = p_credit_id and cl.kind = 'product' and cl.restock_bin_id is not null
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then
    return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', false, 'existing_rows', 0, 'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["nothing_restocked"]'::jsonb);
  end if;

  -- ⭐ 레이어 먼저 — 낱개 SKU 키마다 한 번(창고 하나 · 줄 여럿은 접는다 · line_ref = 첫 줄 · 원 판매는 첫 줄의 것 — 재생성 키 (doc, sku, wh) 와 같다)
  for k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no))[1] as line_ref, (array_agg(t.origin_sale order by t.line_no))[1] as origin_sale,
           count(distinct t.origin_sale) as n_origin
      from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, origin_sale text)
     group by t.base_sku order by t.base_sku
  loop
    if k.n_origin > 1 then v_warn := array_append(v_warn, 'mixed_origin_sales:' || k.base_sku); end if;
    if k.origin_sale is null then v_warn := array_append(v_warn, 'origin_sale_unknown:' || k.base_sku); end if;
    v_costs := v_costs || jsonb_build_object(k.base_sku, public.inv_layer_post_credit(v_cr.credit_number, k.line_ref, k.base_sku, v_cr.warehouse_name, k.qty_ea, p_occurred_on, k.origin_sale, null));
    if (v_costs -> k.base_sku ->> 'traced_qty')::numeric < k.qty_ea then v_warn := array_append(v_warn, 'origin_sale_untraced:' || k.base_sku || ':' || ((v_costs -> k.base_sku -> 'remainder' ->> 'cost_source'))); end if;
  end loop;

  -- 원장 행 — 줄(= 칸 하나) · raw.header 는 Cin7 credit_in 과 같은 모양(order_number · credit_note_number · credit_note_date — 두 축을 같은 식으로 되짚는다) · raw.cost.remainder 가 재생성 hint
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, credited_sku text, qty_returned numeric, unit_price numeric, bin text,
                                                   base_sku text, pack_factor numeric, qty_ea numeric, origin_sale text)
     order by line_no
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 1, b.base_sku, v_cr.warehouse_name, b.bin, b.qty_ea, 'credit_in', 'creditnote', v_cr.credit_number, v_cr.id::text, b.line_id::text, null, 'ims',
      jsonb_build_object(
        'kind', 'credit_in', 'poster', c_version,
        'header', jsonb_build_object('order_number', b.origin_sale, 'credit_note_number', v_cr.credit_number, 'credit_note_date', p_occurred_on, 'invoice_id', v_cr.invoice_id, 'cin7_invoice_number', v_cr.cin7_invoice_number),
        'credit_id', v_cr.id, 'credit_line_id', b.line_id, 'line_no', b.line_no,
        'product_id', b.product_id, 'sku', b.credited_sku, 'base_sku', b.base_sku, 'pack_factor', b.pack_factor,
        'qty', b.qty_returned, 'qty_ea', b.qty_ea, 'unit_price', b.unit_price,
        'warehouse_id', v_cr.warehouse_id, 'warehouse', v_cr.warehouse_name, 'bin', b.bin,
        'customer_id', v_cr.customer_id, 'credited_on', p_occurred_on, 'issued_by', v_cr.issued_by,
        'cost', v_costs -> b.base_sku));
    v_rows := v_rows + 1;  v_qty := v_qty + b.qty_ea;
  end loop;

  return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'already_posted', false, 'existing_rows', 0,
                            'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Credit note % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_cr.credit_number, sqlerrm;
end;
$$;

-- ═══ ① inv_post_move 재발행 — 원본 20260928182712_inv_move_a.sql:405 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_post_move(p_move_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_post_move@2026-09-28.1';
        v_m public.inv_move%rowtype; v_existing int; v_rows int := 0; v_qty numeric := 0; v_hdr jsonb; l record;
begin
  select * into v_m from public.inv_move m where m.id = p_move_id;
  if not found then raise exception 'Move not found — nothing was posted to the ledger'; end if;
  if v_m.status <> 'confirmed' then raise exception 'Move % is % — the ledger takes confirmed moves only — nothing was posted to the ledger', v_m.move_number, v_m.status; end if;
  select count(*) into v_existing from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_m.move_number and e.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('move_id', v_m.id, 'move_number', v_m.move_number, 'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_ea_posted', 0, 'warnings', '["already_posted"]'::jsonb);
  end if;
  v_hdr := jsonb_build_object('move_number', v_m.move_number, 'moved_on', v_m.posted_on, 'warehouse_id', v_m.warehouse_id, 'warehouse', v_m.warehouse, 'note', v_m.note, 'confirmed_by', v_m.confirmed_by);
  for l in select * from public.inv_move_line x where x.move_id = p_move_id order by x.line_no loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_m.posted_on, 2, l.sku, v_m.warehouse, l.from_bin, -l.qty, 'transfer_out', 'transfer', v_m.move_number, v_m.id::text, l.id::text, null, 'ims',
            jsonb_build_object('kind', 'bin_move', 'leg', 'from', 'poster', c_version, 'header', v_hdr, 'line', to_jsonb(l),
                               'rule', format('bin move %s → %s in %s: −%s at %s (same warehouse · no transit · cost layers untouched)', l.from_bin, l.to_bin, v_m.warehouse, l.qty, l.from_bin))),
           (v_m.posted_on, 1, l.sku, v_m.warehouse, l.to_bin, l.qty, 'transfer_in', 'transfer', v_m.move_number, v_m.id::text, l.id::text, null, 'ims',
            jsonb_build_object('kind', 'bin_move', 'leg', 'to', 'poster', c_version, 'header', v_hdr, 'line', to_jsonb(l),
                               'rule', format('bin move %s → %s in %s: +%s at %s (same warehouse · no transit · cost layers untouched)', l.from_bin, l.to_bin, v_m.warehouse, l.qty, l.to_bin)));
    v_rows := v_rows + 2; v_qty := v_qty + l.qty;
  end loop;
  return jsonb_build_object('move_id', v_m.id, 'move_number', v_m.move_number, 'already_posted', false, 'existing_rows', 0, 'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'poster', c_version);
exception when unique_violation then
  raise exception 'Move % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_m.move_number, sqlerrm;
end;
$$;

-- ═══ ① inv_post_receipt 재발행 — 원본 20261020153535_rcv_1b_post_now.sql:265 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_post_receipt(p_receipt_id uuid, p_post_id uuid default null) returns jsonb
language plpgsql
volatile
security definer                                              -- rls-1: definer(네 표의 쓰기 grant 를 회수했다 · 판정 565 · 옛 주석 「이견 3 — definer 가 필요한 표가 없다」 는 rcv-1b 때의 것)
set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_post_receipt@2026-10-20.1';   -- rcv-1b: 묶음 갈래(p_post_id · :pN · post_id 줄만) · 마지막 갈래(꼬리 없는 줄만 · 상한 = 기준 − 먼저 반영 합)   -- raw.poster 에 박는다 — 배분 규칙이 바뀌면 올릴 것
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_wh        text;
  v_existing  int;
  v_baseline  date;
  v_alloc     jsonb;
  v_lines     jsonb;
  v_rows      int := 0;
  v_counted   numeric := 0;
  v_posted    numeric := 0;
  v_excess    numeric := 0;
  v_warn      text[] := '{}';
  v_layers    jsonb;                                              -- 원가 레이어 결과(원가 이식 1차 · 2026-09-19)
  b           record;
  v_post      public.po_receipt_post%rowtype;                        -- rcv-1b: 묶음(있으면) · v_tail = ':p<batch_no>' · 없으면 ''
  v_tail      text := '';
  v_bad_on    date;
begin

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was posted to the ledger', p_receipt_id; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — its ledger is inv_post_transfer_arrive — nothing was posted to the ledger', v_r.receipt_number; end if;   -- tr-3a(트랜스퍼를 막는 한 줄만)
  if p_post_id is null then
    if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
      raise exception 'Receipt % is % — the ledger takes confirmed receipts only — nothing was posted to the ledger', v_r.receipt_number, v_r.status;
    end if;
  else                                                                                        -- rcv-1b: 먼저 반영 묶음 — draft 입고 · 이 입고의 묶음
    select * into v_post from public.po_receipt_post p where p.id = p_post_id and p.receipt_id = p_receipt_id;
    if not found then raise exception 'Post-now batch % is not on receipt % — nothing was posted to the ledger', p_post_id, v_r.receipt_number; end if;
    if v_r.status <> 'draft' or v_r.confirmed_at is not null then
      raise exception 'Receipt % is % — a post-now batch goes to the ledger only while the receipt is draft — nothing was posted to the ledger', v_r.receipt_number, v_r.status;
    end if;
    v_tail := ':p' || v_post.batch_no::text;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  -- rcv-1b(이견 9): 묶음 행의 occurred_on = 입고의 received_on 하나 — 묶음 뒤 날짜가 바뀌었으면 거부(묶음 · 마지막 둘 다)
  select min(l.occurred_on) into v_bad_on from public.inv_ledger l
   where l.doc_type = 'purchase' and l.source = 'ims' and l.doc_number = v_r.receipt_number and l.line_ref ~ ':p[0-9]+$' and l.occurred_on <> v_r.received_on;
  if v_bad_on is not null then
    raise exception 'Receipt % — its date was changed to % after a post-now batch went to the ledger on % — set the date back to % and try again — nothing was posted to the ledger', v_r.receipt_number, v_r.received_on, v_bad_on, v_bad_on;
  end if;

  -- 2. 멱등 — 이미 기표된 입고는 다시 쓰지 않는다(터지지 않고 말한다 · ⬜5)
  select count(*) into v_existing
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.doc_number = v_r.receipt_number and l.source = 'ims'
    and l.line_ref not like '%:offpo'                                                           -- ⑤-6c1 off-PO 행(<diff>:offpo · 확정과 독립 · 확정 전에도 선다)은 「이미 기표됨」의 근거가 아니다
    and case when p_post_id is null then l.line_ref !~ ':' else l.line_ref like '%' || v_tail end;   -- rcv-1b: 마지막 몫 = 꼬리 없는 행 · 묶음 = 이 묶음의 :pN 행(앞 묶음이 「이미 기표됨」으로 읽히지 않게)
  if v_existing > 0 then
    -- ⭐ 원가 이식 1차(2026-09-19) — 원장은 이미 있어도 레이어는 없을 수 있다(이식 전에 확정된 RCV-00005·00006 · 백필 ⬜7).
    --   레이어 쪽도 같은 멱등 규칙(4키가 있으면 안 만든다)이라, 다시 부르면 빠진 레이어만 선다. 원장은 한 행도 다시 쓰지 않는다.
    v_layers := public.inv_layer_post_receipt(p_receipt_id);
    return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'post_id', p_post_id, 'batch_no', v_post.batch_no,   -- rcv-1b
                              'qty_counted', null, 'qty_posted', null, 'qty_excess', null, 'lines', '[]'::jsonb,
                              'layers', v_layers, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 6. 날짜 경고 — 기초선보다 이르면 · 미래면 (막지 않는다 · ⬜7)
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_baseline
  from public.inv_snapshot s
  where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key');
  if v_baseline is not null and v_r.received_on < v_baseline then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- 3·4. 기준과 배분 — 한 번의 SQL 로 계산해 jsonb 배열에 담는다(그 뒤 루프는 넣고 더하기만 한다)
  with ln as (
    select l.po_line_id, sum(l.qty_ea) as counted, d.kind as diff_kind,
           case when d.kind is not null then d.expected_qty - pb.posted_before else sum(l.qty_ea) end as basis,     -- ⭐ 이견 1 — 기록용 기준: 차이 행(over·short)이 있으면 ⓑ 가 얼린 값 · 없으면 센 것   -- rcv-1b: 이 기표의 기준 = 라인 기준 − 먼저 반영 합(묶음 기표는 차이 행이 없다)
           case when d.kind in ('over', 'off_invoice') then d.expected_qty - pb.posted_before else sum(l.qty_ea) end as cap,       -- 깎기 상한: over(옛) · off_invoice(inv-basis-3 · 인보이스 초과)만 자른다 · posted 는 이것만 본다(검증 ⑤ 정정 — basis 와 갈랐다)   -- rcv-1b: 먼저 반영 몫은 이미 재고 — 상한에서 뺀다
           pb.posted_before                                                                                                       -- rcv-1b
    from public.po_receipt_line l
    left join public.po_receipt_diff d on d.receipt_id = l.receipt_id and d.po_line_id = l.po_line_id
    cross join lateral (select coalesce(sum(q.qty_ea), 0) as posted_before from public.po_receipt_line q where q.receipt_id = p_receipt_id and q.po_line_id = l.po_line_id and q.post_id is not null) pb   -- rcv-1b
    where l.receipt_id = p_receipt_id and l.post_id is not distinct from p_post_id                                                -- rcv-1b: 이 기표의 줄만(묶음 = post_id · 마지막 = null)
    group by l.po_line_id, d.kind, d.expected_qty, pb.posted_before
  ),
  alloc as (
    select l.id as receipt_line_id, l.po_line_id, l.bin_id, rb.name as bin, l.qty_ea, l.received_by, l.note,
           pl.line_no, pl.product_id, pl.unit_price, pr.sku,
           ln.counted, ln.basis, ln.cap, ln.diff_kind, ln.posted_before,                                      -- rcv-1b
           least(l.qty_ea, greatest(ln.cap - coalesce(sum(l.qty_ea) over (partition by l.po_line_id order by l.qty_ea desc, rb.name, l.id
                                                                                  rows between unbounded preceding and 1 preceding), 0), 0)) as posted   -- ⭐ ⬜2 — 큰 빈부터 채우고 바닥나는 줄에서 자른다
    from public.po_receipt_line l
    join public.ref_bin  rb on rb.id = l.bin_id
    join public.po_line  pl on pl.id = l.po_line_id
    join public.product  pr on pr.id = pl.product_id
    join ln on ln.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id and l.post_id is not distinct from p_post_id                                                -- rcv-1b
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.qty_ea desc, a.bin, a.receipt_line_id), '[]'::jsonb) into v_alloc from alloc a;

  -- 5. 기표 — posted > 0 인 줄만 행이 된다
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(
      receipt_line_id uuid, po_line_id uuid, bin_id uuid, bin text, qty_ea numeric, received_by uuid, note text,
      line_no int, product_id uuid, unit_price numeric, sku text, counted numeric, basis numeric, diff_kind text, posted numeric, posted_before numeric)   -- rcv-1b
    order by line_no, qty_ea desc, bin
  loop
    if b.posted <= 0 then continue; end if;
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (
      v_r.received_on, 1, b.sku, v_wh, b.bin, b.posted, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, b.po_line_id::text || v_tail, null, 'ims',   -- line_ref = po_line_id(라인 id · Caleb 실측 확정) · rcv-1b: 묶음은 꼬리 :p<batch_no>
      jsonb_build_object(
        'kind', 'po_in', 'poster', c_version, 'post_id', p_post_id, 'batch_no', v_post.batch_no, 'posted_before', b.posted_before,   -- rcv-1b
        'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'receipt_line_id', b.receipt_line_id,
        'po_id', v_po.id, 'po_number', v_po.po_number,                                   -- 갈라진 뒤의 번호(ⓓ 뒤에 불린다 · §11-j)
        'po_line_id', b.po_line_id, 'line_no', b.line_no, 'product_id', b.product_id, 'sku', b.sku,
        'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', b.bin_id, 'bin', b.bin,
        'received_on', v_r.received_on, 'received_by', b.received_by, 'confirmed_by', v_r.confirmed_by, 'confirmed_at', v_r.confirmed_at,
        'line', jsonb_build_object('counted', b.counted, 'basis', b.basis, 'posted', least(b.counted, b.basis), 'excess', greatest(b.counted - b.basis, 0), 'diff_kind', b.diff_kind),
        'this_bin', jsonb_build_object('counted', b.qty_ea, 'posted', b.posted, 'trimmed', b.qty_ea - b.posted),
        'bins', (select jsonb_agg(jsonb_build_object('bin', t2.bin, 'counted', t2.qty_ea, 'posted', t2.posted, 'trimmed', t2.qty_ea - t2.posted) order by t2.qty_ea desc, t2.bin)
                 from jsonb_to_recordset(v_alloc) as t2(po_line_id uuid, bin text, qty_ea numeric, posted numeric) where t2.po_line_id = b.po_line_id),
        'trim_rule', 'fill bins by qty desc, then bin name; cut where the cap runs out; cap = po_receipt_diff.expected_qty when over, else counted (nothing to cut); basis (recorded) = expected_qty whenever a diff row exists, else counted',
        'unit_price', b.unit_price, 'currency_id', v_po.currency_id, 'exchange_rate', v_po.exchange_rate,
        'note', b.note));
    v_rows := v_rows + 1;
    v_posted := v_posted + b.posted;
  end loop;

  -- 라인 요약(0 으로 깎인 줄도 bins[] 에 남는다)
  select coalesce(jsonb_agg(jsonb_build_object(
           'po_line_id', t.po_line_id, 'line_no', t.line_no, 'sku', t.sku, 'counted', t.counted, 'basis', t.basis,
           'posted', t.posted, 'excess', greatest(t.counted - t.basis, 0), 'diff_kind', t.diff_kind, 'bins', t.bins) order by t.line_no), '[]'::jsonb),
         coalesce(sum(t.counted), 0), coalesce(sum(greatest(t.counted - t.basis, 0)), 0)
    into v_lines, v_counted, v_excess
  from (
    select a.po_line_id, min(a.line_no) as line_no, min(a.sku) as sku, min(a.counted) as counted, min(a.basis) as basis, min(a.diff_kind) as diff_kind,
           sum(a.posted) as posted,
           jsonb_agg(jsonb_build_object('bin', a.bin, 'counted', a.qty_ea, 'posted', a.posted, 'trimmed', a.qty_ea - a.posted) order by a.qty_ea desc, a.bin) as bins
    from jsonb_to_recordset(v_alloc) as a(po_line_id uuid, line_no int, sku text, bin text, qty_ea numeric, counted numeric, basis numeric, diff_kind text, posted numeric)
    group by a.po_line_id
  ) t;

  -- ⭐ 원가 레이어 — 원장 행을 만든 바로 그 수량으로(같은 트랜잭션 · 원장 사건과 함께 서거나 함께 죽는다 · 원가 이식 1차 2026-09-19).
  --   두 번 계산하지 않는다 — inv_layer_post_receipt 가 방금 넣은 inv_ledger 행(source='ims' · 이 RCV)을 읽어 라인 단위로 접는다.
  v_layers := public.inv_layer_post_receipt(p_receipt_id);

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'already_posted', false, 'existing_rows', 0, 'post_id', p_post_id, 'batch_no', v_post.batch_no,   -- rcv-1b
    'rows_posted', v_rows, 'qty_counted', v_counted, 'qty_posted', v_posted, 'qty_excess', v_excess,
    'lines', v_lines, 'layers', v_layers, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Receipt % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_r.receipt_number, sqlerrm;
end;
$$;

-- ═══ ① inv_post_receipt_off_po 재발행 — 원본 20260929195458_inv_basis_2.sql:536 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_post_receipt_off_po(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_receipt_off_po@2026-09-29.1';   -- inv-basis-3: off_invoice 행도 · 수량 = received − expected
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_wh       text;
  v_sku      text;
  v_bin      text;
  v_ref      text;
  v_existing int;
  v_layer    jsonb;
  v_qty      numeric;                                                                                -- inv-basis-3: 장부에 넣는 수량 = received − expected(off_po 는 expected 0)
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  if v_d.kind not in ('off_po', 'off_invoice') then
    raise exception 'Difference on % is a "%" line — only off-PO / off-invoice items are posted here (over → inv_post_receipt_over) — nothing was posted to the ledger', v_r.receipt_number, v_d.kind;
  end if;
  v_qty := v_d.received_qty - v_d.expected_qty;
  if v_d.resolved_at is null or v_d.resolution not in ('accepted_free', 'accepted_billed') then
    raise exception 'Off-PO % on % is not accepted (free or billed) — decide it first (po_receipt_diff_settle_off_po) — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if v_d.bin_id is null or v_d.placed_at is null then
    raise exception 'Off-PO % on % is not on a shelf yet — the warehouse puts it away first — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if v_qty <= 0 then raise exception 'Off-PO % on % has quantity % — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number, v_qty; end if;
  select * into v_po from public.po where id = v_r.po_id;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  select b.name into v_bin from public.ref_bin b where b.id = v_d.bin_id;
  v_ref := v_d.id::text || ':offpo';                                                                  -- ⭐ 라인이 없다 — diff_id 가 열쇠 · 접미어로 유니크 7키 · 레이어 4키가 갈린다(:over 선례)

  -- 멱등 — 이미 행이 있으면 다시 쓰지 않는다 · 레이어만 다시(백필)
  select count(*) into v_existing from public.inv_ledger l
   where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in' and l.doc_number = v_r.receipt_number and l.line_ref = v_ref;
  if v_existing > 0 then
    v_layer := public.inv_layer_post_receipt_off_po(p_diff_id);
    return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_posted', 0, 'bin', v_bin, 'layer', v_layer, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 한 행 — 한 제품 · 한 칸 · occurred_on = 문서의 received_on(같은 배로 왔다 · 결정한 날이 아니다 · 일곱 묶음 4) · seq 1(유입)
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
  values (
    v_r.received_on, 1, v_sku, v_wh, v_bin, v_qty, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, v_ref, null, 'ims',
    jsonb_build_object(
      'kind', case v_d.kind when 'off_invoice' then 'po_off_invoice' else 'po_off_po' end, 'poster', c_version,
      'diff_id', v_d.id, 'resolution', v_d.resolution, 'resolution_note', v_d.resolution_note, 'decided_by', v_d.resolved_by, 'decided_at', v_d.resolved_at,
      'unit_price', v_d.unit_price, 'currency_id', v_po.currency_id, 'exchange_rate', v_po.exchange_rate,
      'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'receipt_status', v_r.status, 'po_id', v_po.id, 'po_number', v_po.po_number,
      'product_id', v_d.product_id, 'sku', v_sku,
      'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', v_d.bin_id, 'bin', v_bin, 'placed_by', v_d.placed_by, 'placed_at', v_d.placed_at,
      'received_on', v_r.received_on, 'qty', v_qty, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty,
      'cost_rule', case v_d.resolution when 'accepted_free' then 'free — unit_cost 0 (nothing was paid)' else 'billed — unit_price typed from the invoice (PO currency) × po.exchange_rate' end));

  -- ⭐ 레이어 — 같은 트랜잭션(함께 서거나 함께 죽는다)
  v_layer := public.inv_layer_post_receipt_off_po(p_diff_id);

  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                            'already_posted', false, 'existing_rows', 0, 'rows_posted', 1, 'qty_posted', v_qty, 'bin', v_bin, 'occurred_on', v_r.received_on,
                            'layer', v_layer, 'warnings', '[]'::jsonb);
exception
  when unique_violation then
    raise exception 'Off-PO % on % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', p_diff_id, coalesce(v_r.receipt_number, '?'), sqlerrm;
end;
$$;

-- ═══ ① inv_post_receipt_over 재발행 — 원본 20261020143921_rcv_1a_receipt_line_ref_suffix.sql:1560 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_post_receipt_over(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_receipt_over@2026-09-20.1';
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_wh       text;
  v_sku      text;
  v_line_no  int;
  v_gap      numeric;
  v_ref      text;
  v_existing int;
  v_rows     int := 0;
  v_posted   numeric := 0;
  v_lines    jsonb := '[]'::jsonb;
  v_layer    jsonb;
  b          record;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select pl.line_no into v_line_no from public.po_line pl where pl.id = v_d.po_line_id;
  if v_d.kind <> 'over' then
    raise exception 'Line % (%) on % is a "%" difference — only over differences put extra stock on the ledger — nothing was posted to the ledger',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.kind;
  end if;
  if v_d.resolved_at is null or v_d.resolution not in ('free', 'billed', 'credited') then
    raise exception 'Line % (%) on % is not settled as free, billed or credited — settle it first (po_receipt_diff_settle_over) — nothing was posted to the ledger',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — the ledger takes confirmed receipts only — nothing was posted to the ledger', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  v_gap := v_d.received_qty - v_d.expected_qty;
  if v_gap <= 0 then
    raise exception 'Line % (%) on % says over but received % is not above expected % — nothing was posted to the ledger',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.received_qty, v_d.expected_qty;
  end if;
  v_ref := v_d.po_line_id::text || ':over';                                                            -- ⭐ 유니크 7키가 기준 행과 부딪히지 않게 · 레이어 4키도 갈린다 · ':reversal' 선례

  -- 멱등 — 이미 초과분 행이 있으면 다시 쓰지 않는다 · 레이어만 다시(백필)
  select count(*) into v_existing from public.inv_ledger l
   where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in' and l.doc_number = v_r.receipt_number and l.line_ref = v_ref;
  if v_existing > 0 then
    v_layer := public.inv_layer_post_receipt_over(p_diff_id);
    return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_posted', 0, 'gap', v_gap,
                              'lines', '[]'::jsonb, 'layer', v_layer, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 빈마다: 센 것(po_receipt_line · 확정된 사실) − 그 빈에 이미 기표된 것(기준 행) = 그 빈의 초과분. 0 으로 깎인 빈은 기준 행이 없어 센 것 전부가 초과분이다.
  for b in
    select rb.name as bin, l.bin_id, sum(l.qty_ea) as counted,
           coalesce((select sum(x.qty_delta) from public.inv_ledger x
                      where x.doc_type = 'purchase' and x.source = 'ims' and x.event_type = 'po_in'
                        and x.doc_number = v_r.receipt_number and public.inv_po_line_of(x.line_ref) = v_d.po_line_id::text and x.line_ref not like '%:over' and x.line_ref not like '%:offpo' and x.bin = rb.name), 0) as posted_base   -- rcv-1a: 묶음 행(:pN)도 기준 행 · :over · :offpo 는 아니다(옛 행은 po_line_id 그대로라 꼬리 조건은 무변)
    from public.po_receipt_line l
    join public.ref_bin rb on rb.id = l.bin_id
    where l.receipt_id = v_r.id and l.po_line_id = v_d.po_line_id
    group by rb.name, l.bin_id
    order by rb.name
  loop
    if b.counted - b.posted_base <= 0 then continue; end if;
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (
      v_r.received_on, 1, v_sku, v_wh, b.bin, b.counted - b.posted_base, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, v_ref, null, 'ims',
      jsonb_build_object(
        'kind', 'po_over', 'poster', c_version,
        'diff_id', v_d.id, 'resolution', v_d.resolution, 'resolution_note', v_d.resolution_note, 'settled_by', v_d.resolved_by, 'settled_at', v_d.resolved_at,
        'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_id', v_po.id, 'po_number', v_po.po_number,
        'po_line_id', v_d.po_line_id, 'line_no', v_line_no, 'product_id', v_d.product_id, 'sku', v_sku,
        'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', b.bin_id, 'bin', b.bin,
        'received_on', v_r.received_on, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty, 'gap', v_gap,
        'this_bin', jsonb_build_object('counted', b.counted, 'posted_base', b.posted_base, 'over', b.counted - b.posted_base),
        'cost_rule', case v_d.resolution when 'free' then 'free — unit_cost 0 (nothing was paid)' else v_d.resolution || ' — unit_cost of the receipt''s own layer (same shipment, same price)' end));
    v_rows := v_rows + 1;
    v_posted := v_posted + (b.counted - b.posted_base);
    v_lines := v_lines || jsonb_build_object('bin', b.bin, 'counted', b.counted, 'posted_base', b.posted_base, 'over', b.counted - b.posted_base);
  end loop;
  if v_posted <> v_gap then
    raise exception 'Line % (%) on %: the bins add up to % extra but the difference says % — the receipt lines and the ledger disagree; nothing was posted to the ledger',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_posted, v_gap;
  end if;

  -- ⭐ 레이어 — 방금 넣은 초과분 행으로(같은 트랜잭션 · 함께 서거나 함께 죽는다)
  v_layer := public.inv_layer_post_receipt_over(p_diff_id);

  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                            'already_posted', false, 'existing_rows', 0, 'rows_posted', v_rows, 'qty_posted', v_posted, 'gap', v_gap,
                            'lines', v_lines, 'layer', v_layer, 'warnings', '[]'::jsonb);
exception
  when unique_violation then
    raise exception 'Difference % on % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', p_diff_id, coalesce(v_r.receipt_number, '?'), sqlerrm;
end;
$$;

-- ═══ ① inv_post_sale 재발행 — 원본 20261005201634_asm_2b1_combo_warehouse_path.sql:384 바이트 + 머리 줄 하나(security invoker → definer) · rls-1 ═══
create or replace function public.inv_post_sale(p_so_id uuid, p_picks jsonb, p_occurred_on date) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_sale@2026-09-24.1';
  v_so       public.so%rowtype;
  v_wh       text;
  v_existing int;
  v_baseline date;
  v_alloc    jsonb;
  v_bad      text;
  v_costs    jsonb := '{}'::jsonb;
  v_rows     int := 0;
  v_qty      numeric := 0;
  v_warn     text[] := '{}';
  k          record;
  b          record;
begin
  perform public.ims_require_write('sales', 'posted');        -- ⭐ 첫 줄 — 호출자(auth.uid())의 sales 쓰기

  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was posted to the ledger'; end if;
  if v_so.status <> 'shipped' or v_so.shipped_at is null then
    raise exception 'Order % is % — the ledger takes shipped orders only — nothing was posted to the ledger', v_so.so_number, v_so.status;
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_so.location_id;
  if v_wh is null then raise exception 'Order % has no warehouse — nothing was posted to the ledger', v_so.so_number; end if;

  -- 멱등 — 이미 기표된 출고는 다시 쓰지 않는다(말하는 0)
  select count(*) into v_existing from public.inv_ledger l
  where l.doc_type = 'sale' and l.doc_number = v_so.so_number and l.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'already_posted', true, 'existing_rows', v_existing,
                              'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 날짜 경고 — 기초선보다 이르면 · 미래면(막지 않는다 · inv_post_receipt 와 같다)
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_baseline
  from public.inv_snapshot s where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key');
  if v_baseline is not null and p_occurred_on < v_baseline then v_warn := array_append(v_warn, 'shipped_on_before_baseline'); end if;
  if p_occurred_on > public.ims_today() then v_warn := array_append(v_warn, 'shipped_on_in_future'); end if;

  -- 줄×칸 모으기 — 판매 단위 → EA(pack_factor) · 낱개 SKU(세트 줄은 parent) · 이 오더의 줄만
  select string_agg(distinct p.line_id::text, ', ') into v_bad
  from (select (e->>'line_id')::uuid as line_id from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e) p
  where not exists (select 1 from public.so_line l where l.id = p.line_id and l.so_id = p_so_id);
  if v_bad is not null then
    raise exception 'Pick line % is not on order % — nothing was posted to the ledger', v_bad, v_so.so_number;
  end if;
  select string_agg(distinct l.line_no::text, ', ') into v_bad                                                                          -- asm-2b1(판정 244): 콤보 줄은 원장에 닿지 않는다 — 구성품 줄만
  from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e join public.so_line l on l.id = (e->>'line_id')::uuid
  where exists (select 1 from public.so_line kk where kk.combo_line_id = l.id);                                                            -- 별칭 kk — 이 함수의 declare 에 k record 가 있다(「declare 변수 ≠ 조회 별칭」)
  if v_bad is not null then
    raise exception 'Pick line % of % is a combo line — components carry the stock — nothing was posted to the ledger', v_bad, v_so.so_number;
  end if;
  with p as (
    select (e->>'line_id')::uuid as line_id, coalesce(nullif(trim(e->>'bin'), ''), '') as bin, (e->>'qty')::numeric as qty
    from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e
  ),
  g as (select line_id, bin, sum(qty) as qty from p group by 1, 2),
  a as (
    select l.id as line_id, l.line_no, l.product_id, l.sku as sold_sku, l.pack_factor, l.unit_price,
           coalesce(pp.sku, pr.sku) as base_sku, g.bin, g.qty, g.qty * l.pack_factor as qty_ea
    from g
    join public.so_line l on l.id = g.line_id and l.so_id = p_so_id
    join public.product pr on pr.id = l.product_id
    left join public.product pp on pp.id = pr.parent_product_id
    where g.qty > 0
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.bin), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then
    raise exception 'Order % has no picked quantity — nothing was posted to the ledger', v_so.so_number;
  end if;

  -- ⭐ 소진 먼저 — 낱개 SKU 키마다 한 번(창고 하나 · 줄 여럿은 접는다 · consume.line_ref = 첫 줄 · 재생성 키와 같다)
  for k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no, t.bin))[1] as line_ref
    from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, bin text)
    group by t.base_sku order by t.base_sku
  loop
    v_costs := v_costs || jsonb_build_object(k.base_sku,
                 public.inv_layer_post_sale(v_so.so_number, k.line_ref, k.base_sku, v_wh, k.qty_ea, p_occurred_on, null));
  end loop;

  -- 원장 행 — 줄×칸 · raw.cost 에 그 키의 소진·보충 결과(재생성이 raw.cost.shortfall 을 hint 로 읽는다 · 17-f (가))
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sold_sku text, pack_factor numeric, unit_price numeric,
                                                   base_sku text, bin text, qty numeric, qty_ea numeric)
    order by line_no, bin
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 2, b.base_sku, v_wh, b.bin, -b.qty_ea, 'sale_out', 'sale', v_so.so_number, v_so.id::text, b.line_id::text, null, 'ims',
      jsonb_build_object(
        'kind', 'sale_out', 'poster', c_version,
        'so_id', v_so.id, 'so_number', v_so.so_number, 'so_line_id', b.line_id, 'line_no', b.line_no,
        'product_id', b.product_id, 'sku', b.sold_sku, 'base_sku', b.base_sku, 'pack_factor', b.pack_factor,
        'qty', b.qty, 'qty_ea', b.qty_ea, 'unit_price', b.unit_price,
        'warehouse_id', v_so.location_id, 'warehouse', v_wh, 'bin', b.bin,
        'customer_id', v_so.customer_id, 'channel', v_so.channel, 'intake', v_so.intake,
        'shipped_on', p_occurred_on, 'shipped_at', v_so.shipped_at, 'shipped_by', v_so.shipped_by,
        'cost', v_costs->b.base_sku));
    v_rows := v_rows + 1;
    v_qty  := v_qty + b.qty_ea;
  end loop;

  return jsonb_build_object(
    'so_id', v_so.id, 'so_number', v_so.so_number, 'already_posted', false, 'existing_rows', 0,
    'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Order % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_so.so_number, sqlerrm;
end;
$$;

-- ═══ ① inv_post_transfer_arrive 재발행 — 원본 20260929010938_transfer_3a.sql:122 바이트 + 머리 줄 하나(language 줄에 security definer 추가) · rls-1 ═══
create or replace function public.inv_post_transfer_arrive(p_receipt_id uuid) returns jsonb
  language plpgsql volatile security definer   -- rls-1: (기본 invoker 였다)
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_post_transfer_arrive@2026-09-28.1';
        v_r public.po_receipt%rowtype; v_x public.inv_transfer%rowtype; v_fw text; v_tw text; v_existing int; v_alloc jsonb; v_costs jsonb := '{}'::jsonb; v_rows int := 0; v_qty numeric := 0; v_hdr jsonb;
        v_k record; v_b record; v_g record;                                                       -- ⚠️ CTE 별칭과 겹치지 않게 v_ 접두
begin
  select * into v_r from public.po_receipt r where r.id = p_receipt_id;
  if not found then raise exception 'Receipt not found — nothing was posted to the ledger'; end if;
  if v_r.transfer_id is null then raise exception 'Receipt % is a purchase receipt — its ledger is inv_post_receipt — nothing was posted to the ledger', v_r.receipt_number; end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then raise exception 'Receipt % is % — the ledger takes completed (confirmed) arrivals only — nothing was posted to the ledger', v_r.receipt_number, v_r.status; end if;
  select * into v_x from public.inv_transfer x where x.id = v_r.transfer_id;
  select w.name into v_fw from public.ref_warehouse w where w.id = v_x.from_warehouse_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_fw is null or v_tw is null then raise exception 'Transfer % has no warehouse pair — nothing was posted to the ledger', v_x.transfer_number; end if;
  -- 멱등 — 이 입고의 도착 행이 있으면 다시 쓰지 않는다(같은 문서의 다른 입고 · 출발 행은 근거가 아니다 · line_ref 접미어 = 입고 번호)
  select count(*) into v_existing from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_x.transfer_number and e.source = 'ims' and e.line_ref like '%:' || v_r.receipt_number;
  if v_existing > 0 then
    return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'already_posted', true, 'existing_rows', v_existing,
                              'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;
  -- 입고 줄(확정 사실 · 칸마다 · 보낸 수량까지 잘린 뒤의 EA)에서 줄×칸 모으기 · 낱개 SKU(세트 줄은 parent)
  with a as (
    select l.id as receipt_line_id, tl.id as line_id, tl.line_no, tl.product_id, tl.sku, tl.pack_factor, tl.qty as qty_requested, tl.qty_sent, tl.qty_received,
           coalesce(pp.sku, pr.sku) as base_sku, rb.name as bin, l.bin_id, l.qty_ea
      from public.po_receipt_line l
      join public.inv_transfer_line tl on tl.id = l.transfer_line_id
      join public.ref_bin rb on rb.id = l.bin_id
      join public.product pr on pr.id = tl.product_id left join public.product pp on pp.id = pr.parent_product_id
     where l.receipt_id = p_receipt_id and l.qty_ea > 0
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.bin), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then raise exception 'Receipt % has no received quantity — nothing was posted to the ledger', v_r.receipt_number; end if;
  v_hdr := jsonb_build_object('transfer_number', v_x.transfer_number, 'from_warehouse_id', v_x.from_warehouse_id, 'from_warehouse', v_fw, 'to_warehouse_id', v_r.warehouse_id, 'to_warehouse', v_tw,
                              'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'received_on', v_r.received_on, 'received_at', v_x.received_at, 'received_by', v_x.received_by, 'confirmed_by', v_r.confirmed_by);
  -- ⭐ 레이어 먼저 — 낱개 SKU 키마다 한 번(IN_TRANSIT 문서 범위 → 도착 창고) · line_ref = 첫 줄 id ':' 입고 번호(묶음 아홉 7 · 재생성 키와 같다)
  for v_k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no, t.bin))[1] || ':' || v_r.receipt_number as line_ref
      from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, bin text)
     group by t.base_sku order by t.base_sku
  loop
    v_costs := v_costs || jsonb_build_object(v_k.base_sku, public.inv_layer_post_transfer_arrive(v_x.transfer_number, v_k.line_ref, v_k.base_sku, v_tw, v_k.qty_ea, v_r.received_on, null));
  end loop;
  -- leg 3 — 줄마다 IN_TRANSIT(칸 '') −EA(seq 2 · line_ref = 줄:입고)
  for v_g in
    select t.line_id, t.line_no, t.product_id, t.sku, t.base_sku, t.pack_factor, t.qty_requested, t.qty_sent, t.qty_received, sum(t.qty_ea) as qty_ea
      from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sku text, base_sku text, pack_factor numeric, qty_requested numeric, qty_sent numeric, qty_received numeric, bin text, qty_ea numeric)
     group by t.line_id, t.line_no, t.product_id, t.sku, t.base_sku, t.pack_factor, t.qty_requested, t.qty_sent, t.qty_received order by t.line_no
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_r.received_on, 2, v_g.base_sku, 'IN_TRANSIT', '', -v_g.qty_ea, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_g.line_id::text || ':' || v_r.receipt_number, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', 3, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_g.line_id, 'line_no', v_g.line_no, 'product_id', v_g.product_id, 'sku', v_g.sku, 'base_sku', v_g.base_sku, 'pack_factor', v_g.pack_factor,
                                         'qty_requested', v_g.qty_requested, 'qty_sent', v_g.qty_sent, 'qty_received', v_g.qty_received, 'qty_ea', v_g.qty_ea),
              'rule', format('transfer %s → %s leg 3: −%s EA out of IN_TRANSIT at arrival (receipt %s · received units only · the rest stays in transit)', v_fw, v_tw, v_g.qty_ea, v_r.receipt_number),
              'cost', v_costs -> v_g.base_sku));
    v_rows := v_rows + 1;
  end loop;
  -- leg 4 — 줄×칸 · 도착 창고 칸에 +EA(seq 1)
  for v_b in
    select * from jsonb_to_recordset(v_alloc) as t(receipt_line_id uuid, line_id uuid, line_no int, product_id uuid, sku text, pack_factor numeric, qty_requested numeric, qty_sent numeric, qty_received numeric, base_sku text, bin text, bin_id uuid, qty_ea numeric)
     order by line_no, bin
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_r.received_on, 1, v_b.base_sku, v_tw, v_b.bin, v_b.qty_ea, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_b.line_id::text || ':' || v_r.receipt_number, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', 4, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_b.line_id, 'line_no', v_b.line_no, 'product_id', v_b.product_id, 'sku', v_b.sku, 'base_sku', v_b.base_sku, 'pack_factor', v_b.pack_factor,
                                         'qty_requested', v_b.qty_requested, 'qty_sent', v_b.qty_sent, 'qty_received', v_b.qty_received, 'receipt_line_id', v_b.receipt_line_id, 'bin_id', v_b.bin_id, 'bin', v_b.bin, 'qty_ea', v_b.qty_ea),
              'rule', format('transfer %s → %s leg 4: +%s EA into %s / %s (receipt %s · arrival = warehouse Complete)', v_fw, v_tw, v_b.qty_ea, v_tw, v_b.bin, v_r.receipt_number),
              'cost', v_costs -> v_b.base_sku));
    v_rows := v_rows + 1; v_qty := v_qty + v_b.qty_ea;
  end loop;
  return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'already_posted', false, 'existing_rows', 0,
                            'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version);
exception when unique_violation then
  raise exception 'Transfer % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_x.transfer_number, sqlerrm;
end;
$$;

-- ═══ ① inv_post_transfer_depart 재발행 — 원본 20260929003624_transfer_2.sql:76 바이트 + 머리 줄 하나(language 줄에 security definer 추가) · rls-1 ═══
create or replace function public.inv_post_transfer_depart(p_transfer_id uuid, p_picks jsonb, p_occurred_on date) returns jsonb
  language plpgsql volatile security definer   -- rls-1: (기본 invoker 였다)
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_post_transfer_depart@2026-09-28.1';
        v_x public.inv_transfer%rowtype; v_fw text; v_tw text; v_existing int; v_alloc jsonb; v_bad text; v_costs jsonb := '{}'::jsonb; v_rows int := 0; v_qty numeric := 0; v_hdr jsonb;
        v_k record; v_b record; v_g record;                                                     -- ⚠️ CTE 별칭(p · g · a)과 겹치지 않게 v_ 접두
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id;
  if not found then raise exception 'Transfer not found — nothing was posted to the ledger'; end if;
  if v_x.status <> 'in_transit' or v_x.departed_at is null then
    raise exception 'Transfer % is % — the ledger takes departed transfers only — nothing was posted to the ledger', v_x.transfer_number, v_x.status;
  end if;
  select w.name into v_fw from public.ref_warehouse w where w.id = v_x.from_warehouse_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_x.to_warehouse_id;
  if v_fw is null or v_tw is null then raise exception 'Transfer % has no warehouse pair — nothing was posted to the ledger', v_x.transfer_number; end if;
  -- 멱등 — 이미 기표된 출발은 다시 쓰지 않는다(말하는 0)
  select count(*) into v_existing from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = v_x.transfer_number and e.source = 'ims';
  if v_existing > 0 then
    return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'already_posted', true, 'existing_rows', v_existing,
                              'rows_posted', 0, 'qty_ea_posted', 0, 'keys', '{}'::jsonb, 'warnings', '["already_posted"]'::jsonb);
  end if;
  -- 줄×칸 모으기 — picks {line_id, bin, qty}(판매 단위 · wms_so_handoff) → EA(pack_factor) · 낱개 SKU(세트 줄은 parent) · 이 문서의 줄만
  select string_agg(distinct p.line_id::text, ', ') into v_bad
    from (select (e->>'line_id')::uuid as line_id from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e) p
   where not exists (select 1 from public.inv_transfer_line l where l.id = p.line_id and l.transfer_id = p_transfer_id);
  if v_bad is not null then raise exception 'Pick line % is not on transfer % — nothing was posted to the ledger', v_bad, v_x.transfer_number; end if;
  with p as (
    select (e->>'line_id')::uuid as line_id, coalesce(nullif(trim(e->>'bin'), ''), '') as bin, (e->>'qty')::numeric as qty
      from jsonb_array_elements(coalesce(p_picks, '[]'::jsonb)) e
  ), g as (select line_id, bin, sum(qty) as qty from p group by 1, 2),
  a as (
    select l.id as line_id, l.line_no, l.product_id, l.sku, l.pack_factor, l.qty as qty_requested, l.qty_sent,
           coalesce(pp.sku, pr.sku) as base_sku, g.bin, g.qty, g.qty * l.pack_factor as qty_ea
      from g join public.inv_transfer_line l on l.id = g.line_id and l.transfer_id = p_transfer_id
      join public.product pr on pr.id = l.product_id left join public.product pp on pp.id = pr.parent_product_id
     where g.qty > 0
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.bin), '[]'::jsonb) into v_alloc from a;
  if jsonb_array_length(v_alloc) = 0 then raise exception 'Transfer % has no picked quantity — nothing was posted to the ledger', v_x.transfer_number; end if;
  v_hdr := jsonb_build_object('transfer_number', v_x.transfer_number, 'from_warehouse_id', v_x.from_warehouse_id, 'from_warehouse', v_fw, 'to_warehouse_id', v_x.to_warehouse_id, 'to_warehouse', v_tw,
                              'departed_on', p_occurred_on, 'departed_at', v_x.departed_at, 'departed_by', v_x.departed_by, 'note', v_x.note);
  -- ⭐ 레이어 먼저 — 낱개 SKU 키마다 한 번(출발 창고 하나 · 줄 여럿은 접는다 · consume.line_ref = 첫 줄 · 재생성 키와 같다 · inv_post_sale 과 같은 결)
  for v_k in
    select t.base_sku, sum(t.qty_ea) as qty_ea, (array_agg(t.line_id::text order by t.line_no, t.bin))[1] as line_ref
      from jsonb_to_recordset(v_alloc) as t(base_sku text, qty_ea numeric, line_id uuid, line_no int, bin text)
     group by t.base_sku order by t.base_sku
  loop
    v_costs := v_costs || jsonb_build_object(v_k.base_sku, public.inv_layer_post_transfer_depart(v_x.transfer_number, v_k.line_ref, v_k.base_sku, v_fw, v_k.qty_ea, p_occurred_on, null));
  end loop;
  -- leg 1 — 줄×칸 · 출발 창고 실제 칸에서 −EA(seq 2 · 팩 회복 칸 포함 = 픽커가 뽑은 것과 같은 기록)
  for v_b in
    select * from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sku text, pack_factor numeric, qty_requested numeric, qty_sent numeric, base_sku text, bin text, qty numeric, qty_ea numeric)
     order by line_no, bin
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 2, v_b.base_sku, v_fw, v_b.bin, -v_b.qty_ea, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_b.line_id::text, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', 1, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_b.line_id, 'line_no', v_b.line_no, 'product_id', v_b.product_id, 'sku', v_b.sku, 'base_sku', v_b.base_sku, 'pack_factor', v_b.pack_factor,
                                         'qty_requested', v_b.qty_requested, 'qty_sent', v_b.qty_sent, 'bin', v_b.bin, 'qty', v_b.qty, 'qty_ea', v_b.qty_ea),
              'rule', format('transfer %s → %s leg 1: −%s EA at %s / %s (picked bins · pack recovery included · departure = warehouse finalize)', v_fw, v_tw, v_b.qty_ea, v_fw, v_b.bin),
              'cost', v_costs -> v_b.base_sku));
    v_rows := v_rows + 1; v_qty := v_qty + v_b.qty_ea;
  end loop;
  -- leg 2 — 줄마다 IN_TRANSIT(칸 '') +EA(seq 1 · 같은 날 유입 먼저 · 재생성은 이 행에서 출발 창구를 부른다)
  for v_g in
    select t.line_id, t.line_no, t.product_id, t.sku, t.base_sku, t.pack_factor, t.qty_requested, t.qty_sent, sum(t.qty) as qty, sum(t.qty_ea) as qty_ea
      from jsonb_to_recordset(v_alloc) as t(line_id uuid, line_no int, product_id uuid, sku text, pack_factor numeric, qty_requested numeric, qty_sent numeric, base_sku text, bin text, qty numeric, qty_ea numeric)
     group by t.line_id, t.line_no, t.product_id, t.sku, t.base_sku, t.pack_factor, t.qty_requested, t.qty_sent order by t.line_no
  loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (p_occurred_on, 1, v_g.base_sku, 'IN_TRANSIT', '', v_g.qty_ea, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_g.line_id::text, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', 2, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_g.line_id, 'line_no', v_g.line_no, 'product_id', v_g.product_id, 'sku', v_g.sku, 'base_sku', v_g.base_sku, 'pack_factor', v_g.pack_factor,
                                         'qty_requested', v_g.qty_requested, 'qty_sent', v_g.qty_sent, 'qty', v_g.qty, 'qty_ea', v_g.qty_ea),
              'rule', format('transfer %s → %s leg 2: +%s EA into IN_TRANSIT (arrival at %s is the next step)', v_fw, v_tw, v_g.qty_ea, v_tw),
              'cost', v_costs -> v_g.base_sku));
    v_rows := v_rows + 1;
  end loop;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'already_posted', false, 'existing_rows', 0,
                            'rows_posted', v_rows, 'qty_ea_posted', v_qty, 'keys', v_costs, 'poster', c_version);
exception when unique_violation then
  raise exception 'Transfer % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_x.transfer_number, sqlerrm;
end;
$$;

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and policyname = 'auth_all';
  if v_n <> 0 then v_bad := v_bad || format(' auth_all_left_%s', v_n); end if;
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and cmd = 'SELECT' and roles::text ~ 'authenticated';
  if v_n <> 4 then v_bad := v_bad || format(' select_policies_%s_of_4', v_n); end if;
  select count(*) into v_n from pg_policies where schemaname = 'public' and tablename in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and cmd <> 'SELECT';
  if v_n <> 0 then v_bad := v_bad || format(' write_policies_%s', v_n); end if;
  select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and grantee = 'authenticated' and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  if v_n <> 0 then v_bad := v_bad || format(' auth_write_grants_%s', v_n); end if;
  select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and grantee = 'authenticated' and privilege_type = 'SELECT';
  if v_n <> 4 then v_bad := v_bad || format(' auth_select_%s_of_4', v_n); end if;
  select count(*) into v_n from information_schema.role_table_grants where table_schema = 'public' and table_name in ('inv_ledger', 'inv_layer', 'inv_layer_cost_add', 'inv_layer_consume') and grantee = 'service_role' and privilege_type = 'INSERT';
  if v_n <> 4 then v_bad := v_bad || format(' service_role_insert_%s_of_4', v_n); end if;
  select count(*) into v_n from pg_proc where pronamespace = 'public'::regnamespace and prosecdef
     and proname in ('inv_layer_post_charge', 'inv_layer_post_receipt', 'inv_layer_post_receipt_off_po', 'inv_layer_post_receipt_over', 'inv_post_adjust', 'inv_post_credit', 'inv_post_move', 'inv_post_receipt', 'inv_post_receipt_off_po', 'inv_post_receipt_over', 'inv_post_sale', 'inv_post_transfer_arrive', 'inv_post_transfer_depart');
  if v_n <> 13 then v_bad := v_bad || format(' definer_%s_of_13', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and not p.prosecdef
     and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?inv_(ledger|layer|layer_cost_add|layer_consume)\M';
  if v_n <> 0 then v_bad := v_bad || format(' invoker_writers_left_%s', v_n); end if;
  if v_bad <> '' then raise exception 'rls-1 landing check failed:%', v_bad; end if;
end $$;
