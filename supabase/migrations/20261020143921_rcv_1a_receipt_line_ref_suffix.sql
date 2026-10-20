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

-- ═══ rcv-1a — 먼저 반영(판정 550 ~ 552)의 원장 · 원가 축: 입고 line_ref 꼬리 :pN 을 읽는 쪽 (2026-10-20 · rcv-0 회신 · rcv-1a 이견 1 ~ 11) ═══
--   규칙: 입고 축(doc_type purchase · source ims · origin purchase)의 po_line = inv_po_line_of(line_ref) = split_part(line_ref, ':', 1) — 묶음 몫 line_ref 는 po_line_id || ':p' || n(rcv-1b 가 낸다) · 마지막 확정은 꼬리 없이(옛 행과 같은 꼴)
--   :offpo · :over 를 보는 조건은 글자 그대로(이견 4 · :pN:offpo 는 1b) · inv_post_receipt 의 멱등은 1b · 판정 553(비용 미루기)도 1b — 이 차수는 읽는 쪽 9 곳 + 식 인덱스
--   1b 전제(이견 7 · Caleb): 묶음 행의 occurred_on = 입고의 received_on 하나 · 다른 날 묶음은 만들지 않는다 · 재생성 ims_rcv 키는 입고 단위 그대로
--   재발행 9 = 마지막 정의 바이트 + 바뀐 줄(이 꼴 하나뿐): inv_layer_post_receipt(7) · inv_layer_post_charge(2) · inv_layer_post_cost_adjust(4) · inv_layer_apply(1) · inv_layer_apply_flush_adds(3) · po_fx_cost_lines(1) · po_credit_cost_events(1) · inv_layer_post_receipt_over(1) · inv_post_receipt_over(1)
--   무접촉: inv_post_receipt · inv_layer_post_receipt_off_po · inv_post_receipt_off_po · inv_layer_apply_po_in(Cin7 축) · inv_bin_history(꼬리표 정규식 ^[a-z]+$ 는 p1 을 안 잡는다) · tf_*(:settle:) · 뷰 0

-- ═══ 1) 속 함수 — 꼬리 규칙 한 곳 ═══
create function public.inv_po_line_of(p_line_ref text) returns text
  language sql immutable parallel safe
  set search_path = public, pg_temp
as $$ select split_part(p_line_ref, ':', 1) $$;
revoke all on function public.inv_po_line_of(text) from public, anon;
grant execute on function public.inv_po_line_of(text) to authenticated, service_role;
comment on function public.inv_po_line_of(text) is 'rcv-1a — 입고 축 line_ref(po_line_id · po_line_id:pN · 그 밖 꼬리)에서 po_line id 글자만: split_part(line_ref, '':'', 1). 레이어 · landed · 원가 조정 · 재생성 · FX · 크레딧 사건이 전부 이것으로 po_line 을 찾는다(9 곳). :offpo · :over 를 가르는 조건은 따로(글자 그대로)';

-- 식 인덱스(이견 3) — 등호 인덱스 길을 잃는 조인을 받친다 · 재생성이 표를 비우고 다시 채워도 따라온다
create index if not exists inv_layer_po_line_idx on public.inv_layer (public.inv_po_line_of(line_ref)) where origin_type = 'purchase';

-- ═══ 2) inv_layer_post_receipt 재발행 — 원본 20261008234826_po_disc_2.sql:187 바이트 + 7 줄 ═══
create or replace function public.inv_layer_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker
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
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — cost layers are built for confirmed receipts only — no cost layers were created', v_r.receipt_number, v_r.status;
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

-- ═══ 3) inv_layer_post_charge 재발행 — 원본 20260930144905_cogs_2_cost_split.sql:319 바이트 + 2 줄 ═══
create or replace function public.inv_layer_post_charge(p_charge_id uuid, p_on date default null, p_alloc uuid default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_charge@2026-09-30.4';   -- cogs-2(판정 107 · 113 · 114): 얹기 줄 날짜 = 얹히는 순간(p_on 없으면 ims_today) · 새 얹기 줄마다 inv_layer_cost_add_settle · 배분 줄에 posted_on · posted_ledger_id · p_alloc 으로 배분 줄 하나만(재생성)   -- inv-basis-3: 입고 확정자의 문(판정 94 ⑯) · 트랜스퍼 :over: 레이어 제외(판정 95 ㉓)   -- tr-4: 트랜스퍼 배분 갈래(판정 67 · 77 · 묶음 일곱) · tr-4b: 얹은 뒤 자식 레이어로 따라가기(판정 79) · 도착 창구의 문(판정 78)
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
    'allocs', v_allocs, 'builder', c_version, 'warnings', to_jsonb(v_warn))
    || case when v_carried > 0 then jsonb_build_object('carried_rows', v_carried) else '{}'::jsonb end;   -- tr-4b: 따라간 행이 있을 때만 키(발주 반환 모양 무변)
exception
  when unique_violation then
    raise exception 'Charge % — a landed cost row with the same key already exists (%) — no cost was added', v_chg.charge_number, sqlerrm;
end;
$$;

-- ═══ 4) inv_layer_post_cost_adjust 재발행 — 원본 20261009002744_po_disc_3.sql:90 바이트 + 4 줄 ═══
create or replace function public.inv_layer_post_cost_adjust(p_adjust_id uuid, p_on date default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_cost_adjust@2026-10-09.1';
  v_j          public.inv_cost_adjust%rowtype;
  v_tr         record;                 -- charge_alloc 대상: 배분 줄의 po_id · transfer_id · transfer_number · po_number
  v_lay        record;
  v_n_layers   int;
  v_basis      numeric;
  v_share      numeric;
  v_given      numeric := 0;
  v_i          int := 0;
  v_aid        bigint;
  v_sub        jsonb;
  v_lines      jsonb := '[]'::jsonb;
  v_carried    int := 0;
  v_late_sold  numeric := 0;
  v_late_moved numeric := 0;
  v_ref        text;                   -- cost_add.ref_number — 발주 번호(트랜스퍼 배분이면 트랜스퍼 번호) · inv_layer_post_charge 와 같은 자리
  v_on         date := coalesce(p_on, public.ims_today());
  v_maxid      bigint;
begin
  -- 문(⬜4) — purchasing(결제 · 크레딧 · 되돌림 창구) · receiving | wms_receiving_confirm(입고 확정 길 · po_receipt_confirm_by ⓖ) · 재생성 로그인은 둘 다 가진다
  if not (public.ims_can_write('purchasing') or public.ims_can_write('receiving') or public.ims_can_write('wms_receiving_confirm')) then
    perform public.ims_require_write('purchasing', 'posted');
  end if;

  select * into v_j from public.inv_cost_adjust where id = p_adjust_id for update;
  if not found then raise exception 'Cost adjustment % not found — no cost was changed', p_adjust_id; end if;
  -- 멱등 — 실시간: 이미 posted 면 0 줄 · 재생성: posted 사건만 받고 이 사건의 얹기 줄이 이미 있으면 0 줄(같은 트랜잭션 재호출도 여기 걸린다)
  if p_on is null and v_j.status = 'posted' then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'already_posted', 'layers', 0, 'posted_cad', 0, 'posted_on', v_j.posted_on, 'builder', c_version);
  end if;
  if p_on is not null and v_j.status <> 'posted' then
    raise exception 'Cost adjustment % is still pending — regeneration replays posted adjustments only — no cost was changed', v_j.source_number;
  end if;
  if exists (select 1 from public.inv_layer_cost_add ca where ca.line_ref = 'adj:' || v_j.id::text) then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'already_posted', 'layers', 0, 'posted_cad', 0, 'posted_on', v_j.posted_on, 'builder', c_version);
  end if;

  -- 대상 — charge_alloc 이면 배분 줄의 발주 · 트랜스퍼(inv_layer_post_charge 가 읽는 것과 같은 것)
  if v_j.target_type = 'charge_alloc' then
    select a.po_id, a.transfer_id, t.transfer_number, p.po_number into v_tr
      from public.po_charge_alloc a left join public.inv_transfer t on t.id = a.transfer_id left join public.po p on p.id = a.po_id
     where a.id = v_j.po_charge_alloc_id;
    if not found then raise exception 'Cost adjustment %: allocation line % not found — no cost was changed', v_j.source_number, v_j.po_charge_alloc_id; end if;
    v_ref := coalesce(v_tr.po_number, v_tr.transfer_number);
  else
    select null::uuid as po_id, null::uuid as transfer_id, null::text as transfer_number, p.po_number into v_tr from public.po_line pl join public.po p on p.id = pl.po_id where pl.id = v_j.po_line_id;
    v_ref := v_tr.po_number;
  end if;

  -- 레이어 집합 · 기준 — po_line: 그 줄의 구매 레이어 · charge_alloc: ⬜3 inv_layer_post_charge 20260930144905 의 술어 그대로(발주 갈래 · 트랜스퍼 갈래 · :settle: · :over: 제외)
  select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_n_layers, v_basis
    from public.inv_layer x
    left join public.po_line pl on pl.id::text = public.inv_po_line_of(x.line_ref)   -- rcv-1a
   where (v_j.target_type = 'po_line' and x.origin_type = 'purchase' and x.cost_source = 'po_line' and public.inv_po_line_of(x.line_ref) = v_j.po_line_id::text)
      or (v_j.target_type = 'charge_alloc' and (
             (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_tr.po_id)
          or (v_tr.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_tr.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')));
  if v_n_layers = 0 then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'no_layers', 'layers', 0, 'basis', 0, 'posted_cad', 0, 'amount_cad', v_j.amount_cad, 'builder', c_version);
  end if;
  if v_basis = 0 then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'no_basis', 'layers', v_n_layers, 'basis', 0, 'posted_cad', 0, 'amount_cad', v_j.amount_cad, 'builder', c_version);
  end if;

  -- 금액 비율(unit_cost × qty) · 6자리 · 끝수는 마지막 레이어 · ⬜1 음수 가드 · 줄마다 settle
  for v_lay in
    select x.id, x.sku, x.warehouse, x.doc_number, x.line_ref, x.qty, x.unit_cost, x.unit_cost * x.qty as basis,
           coalesce((select sum(ca.amount) from public.inv_layer_cost_add ca where ca.layer_id = x.id), 0) as adds
      from public.inv_layer x
      left join public.po_line pl on pl.id::text = public.inv_po_line_of(x.line_ref)   -- rcv-1a
     where (v_j.target_type = 'po_line' and x.origin_type = 'purchase' and x.cost_source = 'po_line' and public.inv_po_line_of(x.line_ref) = v_j.po_line_id::text)
        or (v_j.target_type = 'charge_alloc' and (
               (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_tr.po_id)
            or (v_tr.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_tr.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')))
     order by x.sku, x.line_ref, x.id
  loop
    v_i := v_i + 1;
    if v_i = v_n_layers then v_share := v_j.amount_cad - v_given;                        -- 마지막 레이어에 잔액 — 합이 정확히 사건 금액
    else v_share := round(v_j.amount_cad * v_lay.basis / v_basis, 6); end if;
    if v_lay.basis + v_lay.adds + v_share < 0 then                                        -- ⬜1: 물건의 원가보다 큰 크레딧 — 입력 오류일 가능성 · 사건 전체 거부(앞 레이어에 넣은 줄은 예외로 함께 되돌아간다)
      raise exception 'Cost adjustment % (% CAD) is a credit larger than the cost of the goods on layer % (% % · cost % + earlier adds % + this share %) — check the amount — no cost was changed',
        v_j.source_number, v_j.amount_cad, v_lay.id, v_lay.sku, v_lay.doc_number, v_lay.basis, v_lay.adds, v_share;
    end if;
    v_given := v_given + v_share;
    insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
    values (v_lay.id, v_j.kind, v_share, v_on, v_j.source_number, 'adj:' || v_j.id::text, v_ref)
    returning id into v_aid;
    v_sub := public.inv_layer_cost_add_settle(v_aid);                                     -- 남은 몫 · 옮겨 간 몫(자식 carried · ref_number layer:<부모>:<kind>) · 팔린 몫(cost_late · split_basis.kind = 이 kind)
    v_carried    := v_carried    + coalesce((v_sub ->> 'carried_rows')::int, 0);
    v_late_sold  := v_late_sold  + coalesce((v_sub ->> 'sold_amount')::numeric, 0);
    v_late_moved := v_late_moved + coalesce((v_sub ->> 'moved_amount')::numeric, 0);
    v_lines := v_lines || jsonb_build_object('layer_id', v_lay.id, 'sku', v_lay.sku, 'warehouse', v_lay.warehouse, 'doc_number', v_lay.doc_number, 'line_ref', v_lay.line_ref,
                                             'qty', v_lay.qty, 'unit_cost', v_lay.unit_cost, 'basis', v_lay.basis, 'share_cad', v_share, 'settle_rows', coalesce((v_sub ->> 'rows_written')::int, 0));
  end loop;

  if p_on is null then                                                                    -- 실시간: 자리를 남긴다(재생성이 같은 자리 · 같은 날 안의 앞뒤까지 재현 · 비용의 posted_on 과 같은 모양)
    select max(g.id) into v_maxid from public.inv_ledger g;
    update public.inv_cost_adjust set status = 'posted', posted_on = v_on, posted_ledger_id = v_maxid where id = v_j.id;
  end if;
  return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'posted',
                            'layers', v_n_layers, 'basis', v_basis, 'amount_cad', v_j.amount_cad, 'posted_cad', v_given, 'posted_on', v_on, 'posted_ledger_id', v_maxid,
                            'late_sold_cad', v_late_sold, 'late_moved_cad', v_late_moved, 'carried_rows', v_carried, 'lines', v_lines, 'builder', c_version);
exception
  when unique_violation then
    raise exception 'Cost adjustment % — a cost row with the same key already exists (%) — no cost was changed', v_j.source_number, sqlerrm;
end;
$$;

-- ═══ 5) inv_layer_apply_flush_adds 재발행 — 원본 20261009002744_po_disc_3.sql:446 바이트 + 3 줄 ═══
create or replace function public.inv_layer_apply_flush_adds(p_day date, p_until date, p_before_id bigint, p_acc jsonb) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_landed_rows int := 0;
  v_doc         record;
  v_grp         record;
  v_fr_n        int;
  v_fr_basis    numeric;
  v_fr_rows     int := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
  v_rows        int;
  v_ims_j       jsonb;
  v_ims_chg     record;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_chg_skip    jsonb := '[]'::jsonb;                                                     -- [{d charge_date · e 원문 skip 항목}] — 본체가 원문 순서로 잇는다
  v_ids         bigint[];   v_id bigint;                                                  -- cogs-2: 새로 든 얹기 줄(on conflict do nothing 의 returning) → settle
  v_al          record;     v_chg_ids uuid[] := '{}';                                      -- cogs-2(판정 114): IMS 비용은 배분 줄 단위 · charges_posted 는 비용 문서 수(distinct)
  v_deferred    int := 0;                                                                 -- cogs-3(판정 119) 안전띠: 대상 레이어가 아직 없어 이번 경계에서 미룬 posted 배분 줄 수
  v_adj         record;                                                                  -- po-disc-3(판정 391 · 394): IMS 원가 조정 사건 — 비용 갈래와 같은 자리(posted_on · posted_ledger_id) · done kind cogs_adj
  v_adj_n int := 0;   v_adj_rows int := 0;   v_adj_amt numeric := 0;   v_adj_nolayers int := 0;   v_adj_skipped int := 0;   v_adj_deferred int := 0;   v_adj_skip jsonb := '[]'::jsonb;
begin
  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — cogs-1: 그날까지 · 아직 안 얹은 것 · 대상 레이어가 선 것만(집합 연산 한 번은 그대로) ═══
  with ins as (
  insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
  select x.id, 'landed',
         sum(c.amount),          -- ⭐ bin 이 여럿이면 합산 (실측 0건 · 방어)
         c.occurred_on,          -- ⚠️ 날짜별로 별개 행 (통관·freight·관세)
         c.doc_number, c.line_ref,
         null                    -- PO landed 는 인보이스 번호가 오지 않는다 (헤더)
    from inv_cost c
    join inv_layer x
      on  x.origin_type = 'purchase'
      and x.doc_number  = c.doc_number
      and x.line_ref    = c.line_ref
      and x.sku         = c.sku
      and x.warehouse   = c.warehouse
    where c.cost_kind = 'landed'
      and (p_until is null or c.occurred_on <= p_until)
      and (p_day is null or c.occurred_on <= p_day)                                                                                                        -- cogs-1(판정 109): 그날까지의 비용만
      and not exists (select 1 from inv_layer_cost_add ca where ca.layer_id = x.id and ca.kind = 'landed' and ca.doc_number = c.doc_number and ca.line_ref = c.line_ref and ca.occurred_on = c.occurred_on)   -- cogs-1: 아직 안 얹은 것만(inv_layer_cost_add_uq 와 같은 키)
    group by x.id, c.occurred_on, c.doc_number, c.line_ref
  on conflict on constraint inv_layer_cost_add_uq do nothing
  returning id)
  select coalesce(array_agg(ins.id order by ins.id), '{}') into v_ids from ins;
  v_landed_rows := coalesce(array_length(v_ids, 1), 0);
  foreach v_id in array v_ids loop perform inv_layer_cost_add_settle(v_id); end loop;                     -- cogs-2(판정 107): 새로 든 얹기 줄마다 셋으로(레이어가 이미 팔린 뒤 온 landed → cost_late · 자식 carried)

  -- ═══ 트랜스퍼 운송비 → inv_layer_cost_add (kind='transfer_freight' · 2026-09-10 · 헤더 B) — landed 와 같은 자리 ═══
  -- 문서 단위 루프 — 배분 기준(도착 레이어 원가 합)은 문서에 딸린 레이어로 정해지므로 문서마다 한 번 계산한다
  for v_doc in
    select doc_number, sum(amount) as amount     -- amount: no_basis 로 떨어질 때 합산할 문서 금액 (p_until 범위)
      from inv_doc_cost
      where doc_type = 'transfer' and kind = 'transfer_freight'
        and (p_until is null or occurred_on <= p_until)
      group by doc_number
      having (p_day is null or max(occurred_on) <= p_day)                                                                                                 -- cogs-1: 저널 묶음이 그날까지 다 온 문서만
      order by doc_number
  loop
    if exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_fr' and d.doc_number = v_doc.doc_number and d.sku = '' and d.warehouse = '') then continue; end if;   -- cogs-1: 이미 처리한 문서
    if p_day is not null and exists (select 1 from inv_ledger g where g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT' and g.doc_number = v_doc.doc_number
                                        and g.occurred_on > p_day and (p_until is null or g.occurred_on <= p_until)) then continue; end if;                -- cogs-1: 도착이 더 남은 문서는 기다린다(기준 = 도착 레이어 전부 · 원문과 같은 집합)
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_fr', v_doc.doc_number, '', '');
    -- B-1 대상 = 도착 창고 레이어만 (IN_TRANSIT 제외) · B-2 기준 = unit_cost × qty (remaining 아님)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_fr_n, v_fr_basis
      from inv_layer x
      where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT';
    if v_fr_n = 0 then
      v_fr_orphan := v_fr_orphan + 1;          -- 대응 레이어 없음 (0 이 아니면 신호)
      continue;
    end if;
    if v_fr_basis <= 0 then
      v_fr_nobasis := v_fr_nobasis + 1;        -- 원가 미상(unknown · unit_cost 0) 레이어만 있는 문서 — 0 으로 나누지 않는다
      v_fr_nobasis_amt := v_fr_nobasis_amt + v_doc.amount;   -- ⚠️ 버린 운송비 금액 — Cin7 대조에서 설명된 차이의 크기 (헤더)
      continue;
    end if;

    -- 날짜별 한 묶음 — cost_add 유니크 키에 ref_number 가 없으므로 같은 날 인보이스가 둘이면 합산 1행 (헤더 B-3)
    for v_grp in
      select occurred_on, sum(amount) as amount, count(*) as n,
             string_agg(distinct ref_number, ',' order by ref_number) as ref_number
        from inv_doc_cost
        where doc_type = 'transfer' and kind = 'transfer_freight' and doc_number = v_doc.doc_number
          and (p_until is null or occurred_on <= p_until)
        group by occurred_on
        order by occurred_on
    loop
      if v_grp.n > 1 then v_fr_multi := v_fr_multi + 1; end if;
      -- B-2 배분: share = round(문서금액 × 레이어원가 / 합, 6) · 마지막 레이어(id 순) = 문서금액 − 앞선 share 합 (remainder on last)
      with ins as (
      insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      select t.id, 'transfer_freight',
             case when t.rn = t.cnt
                  then v_grp.amount - coalesce(sum(t.share) over (order by t.rn rows between unbounded preceding and 1 preceding), 0)
                  else t.share end,
             v_grp.occurred_on, v_doc.doc_number, t.line_ref, v_grp.ref_number
        from (select x.id, x.line_ref,
                     round(v_grp.amount * (x.unit_cost * x.qty) / v_fr_basis, 6) as share,
                     row_number() over (order by x.id) as rn,
                     count(*) over () as cnt
                from inv_layer x
                where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT') t
      on conflict on constraint inv_layer_cost_add_uq do nothing
      returning id)
      select coalesce(array_agg(ins.id order by ins.id), '{}') into v_ids from ins;
      v_rows := coalesce(array_length(v_ids, 1), 0);
      v_fr_rows := v_fr_rows + v_rows;
      foreach v_id in array v_ids loop perform inv_layer_cost_add_settle(v_id); end loop;                 -- cogs-2(판정 107): 도착 레이어가 이미 팔렸거나 다시 떠난 뒤 온 운임 → cost_late · cost_moved · 자식 carried
    end loop;
    v_fr_docs := v_fr_docs + 1;
  end loop;

  -- ═══ IMS 비용 → inv_layer_cost_add (kind='landed' · 2026-09-20) — landed·운송비와 같은 층 · 창구 inv_layer_post_charge 에 넘긴다 ═══
  -- tr-4(2026-09-29): 비용 문서의 배분 줄이 트랜스퍼를 가리키면 그 문서의 도착 레이어에 얹는다 — 같은 창구 · 같은 규칙(판정 67 · 77 · 묶음 일곱) · 아래 exists 둘에 트랜스퍼 갈래를 더했다.
  -- 왜 여기(날짜 경계)인가(cogs-1 · 판정 109): 옛 판은 「비용은 금액만 얹어 FIFO 소진에 영향이 없다」며 끝에 두었다 — 다음 차수가 소진 단가에 얹힌 몫을 넣으면 그 전제가 깨지므로 지금 자리부터 옮긴다(입고 레이어는 루프 안 — 본체).
  -- 왜 레이어에서 훑나(Caleb 판정 2026-09-20): 비용은 원장에 사건을 남기지 않아(금액만 얹는다) 원장으로 훑을 수 없다. 레이어가 없으면 얹을 곳도 없으니 부를 이유가 없다.
  --   길: inv_layer(cost_source='po_line').line_ref = po_line.id::text → po_line.po_id = po_charge_alloc.po_id → po_charge_alloc.po_charge_id = po_charge.id (confirmed).
  --   비용 문서 단위로 한 번(한 비용이 여러 발주에 배분된다 — exists 로 접는다) · 순서 고정.
  -- 왜 창구에 넘기나: 배분 규칙(환율 · unit_cost×qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등)이 창구 안에 있다 — 두 곳에 살게 하지 않는다.
  -- p_until: cogs-2 — 얹기 줄 날짜 = posted_on(없으면 charge_date) — 그것이 p_until 안이면 고른다(as-of 재생성).
  -- 방문하지 않은 확정 비용(배분된 발주 어디에도 IMS 레이어가 없는 것 — 예: 환율이 없어 입고를 건너뛴 발주)은 따로 센다(charges_unvisited · 금액 CAD)
  --   — 「버린 금액」의 그림이 빠지지 않게. Cin7 대조에서 이 금액만큼은 설명된 차이다(정본 D 의 freight_no_basis_amount 와 같은 구실).
  -- ⭐ cogs-2(판정 114 · 115-1): 배분 줄 단위 · 자리 = 실시간이 남긴 posted_on(같은 날 안은 posted_ledger_id < p_before_id 인 것만 · 본체가 줄 id 로 부른다) · posted_on 없는 옛 배분 줄은 첫 차수 규칙(charge_date ≤ p_day · 그 배분 줄의 레이어가 선 뒤 · 얹기 줄 날짜 = charge_date)
  for v_al in
    select a.id as alloc_id, c.id as charge_id, c.charge_number, c.charge_date, a.posted_on, a.posted_ledger_id, a.po_id, a.transfer_id
      from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
      where c.status = 'confirmed' and c.confirmed_at is not null
        and (p_until is null or coalesce(a.posted_on, c.charge_date) <= p_until)
        and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')   -- 이미 부른 배분 줄
        and (
              (a.posted_on is not null                                                                                   -- ⓐ 실시간이 얹은 배분 줄: posted_on 자리 · 같은 날 안은 posted_ledger_id < p_before_id 인 것만
               and (p_day is null or a.posted_on < p_day or (a.posted_on = p_day and (p_before_id is null or coalesce(a.posted_ledger_id, -1) < p_before_id))))
           or (a.posted_on is null                                                                                       -- ⓑ 아직 안 얹힌 배분 줄(옛 것 · no_layers): 첫 차수 규칙 — charge_date ≤ p_day 이고 그 배분 줄의 레이어가 선 것 · 마지막 쏟기(p_day null)는 레이어가 없어도 넘겨 no_layers 로 센다
               and (p_day is null or c.charge_date <= p_day)
               and (p_day is null
                    or (a.po_id is not null and exists (select 1 from po_line pl join inv_layer x on inv_po_line_of(x.line_ref) = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = a.po_id))
                    or (a.transfer_id is not null and exists (select 1 from inv_transfer t join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%' where t.id = a.transfer_id))))   -- inv-basis-3(판정 95 ㉓): 창구와 같은 술어
            )
      order by coalesce(a.posted_on, c.charge_date), a.posted_ledger_id nulls first, c.charge_number, c.id, a.id
  loop
    if v_al.posted_on is not null and p_day is not null                                                                    -- cogs-3(판정 119) 안전띠: 실시간이 얹은 배분 줄인데 대상 레이어가 아직 없으면 done 을 쓰지 않고 다음 경계에서 다시 본다(마지막 쏟기 p_day null 은 창구에 넘겨 no_layers 로)
       and not ((v_al.po_id is not null and exists (select 1 from po_line pl join inv_layer x on inv_po_line_of(x.line_ref) = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = v_al.po_id))
             or (v_al.transfer_id is not null and exists (select 1 from inv_transfer t join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%' where t.id = v_al.transfer_id))) then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_chg', v_al.alloc_id::text, '', '');
    begin
      v_ims_j := inv_layer_post_charge(v_al.charge_id, coalesce(v_al.posted_on, v_al.charge_date), v_al.alloc_id);
      if not (v_al.charge_id = any (v_chg_ids)) then v_chg_ids := v_chg_ids || v_al.charge_id; v_ims_chg_n := v_ims_chg_n + 1; end if;
      v_ims_chg_rows         := v_ims_chg_rows         + coalesce((v_ims_j->>'layers_touched')::int, 0);
      v_ims_chg_amt          := v_ims_chg_amt          + coalesce((v_ims_j->>'amount_posted_cad')::numeric, 0);
      v_ims_chg_nobasis_amt  := v_ims_chg_nobasis_amt  + coalesce((v_ims_j->>'no_basis_amount_cad')::numeric, 0);    -- 기준 0 이라 버린 금액(정본 D)
      v_ims_chg_nolayers_amt := v_ims_chg_nolayers_amt + coalesce((v_ims_j->>'no_layers_amount_cad')::numeric, 0);   -- 배분 줄 중 레이어 없는 발주로 간 금액
      v_ims_chg_already      := v_ims_chg_already      + coalesce((v_ims_j->>'already_posted_allocs')::int, 0);      -- cost_add 를 지운 뒤라 0 이어야 한다(생기면 신호)
    exception when others then
      v_ims_chg_skipped := v_ims_chg_skipped + 1;
      v_chg_skip := v_chg_skip || jsonb_build_object('d', coalesce(v_al.posted_on, v_al.charge_date), 'e', jsonb_build_object('kind', 'charge', 'number', v_al.charge_number, 'id', v_al.charge_id, 'alloc_id', v_al.alloc_id, 'sqlstate', sqlstate, 'error', sqlerrm));
    end;
  end loop;

  -- ═══ IMS 원가 조정 → inv_layer_cost_add (po-disc-3 · 판정 391 · 394) — 비용 갈래와 같은 모양 · 자리 = posted_on · posted_ledger_id(같은 날 안은 < p_before_id) · done kind cogs_adj · pending(posted_on null)은 재생성이 얹지 않는다(입고 확정 사건이 그 자리 · 확정 순간 posted_on 이 적힌다) · 되돌림 줄도 자기 자리 ═══
  for v_adj in
    select j.id, j.source_number, j.posted_on, j.posted_ledger_id, j.target_type, j.po_line_id, j.po_charge_alloc_id
      from inv_cost_adjust j
      where j.status = 'posted' and j.posted_on is not null
        and (p_until is null or j.posted_on <= p_until)
        and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')
        and (p_day is null or j.posted_on < p_day or (j.posted_on = p_day and (p_before_id is null or coalesce(j.posted_ledger_id, -1) < p_before_id)))
      order by j.posted_on, j.posted_ledger_id nulls first, j.created_at, j.id
  loop
    if p_day is not null                                                                                                   -- cogs-3(판정 119) 안전띠와 같다: 대상 레이어가 아직 없으면 done 을 쓰지 않고 다음 경계로
       and not ((v_adj.target_type = 'po_line' and exists (select 1 from inv_layer x where x.origin_type = 'purchase' and x.cost_source = 'po_line' and inv_po_line_of(x.line_ref) = v_adj.po_line_id::text))
             or (v_adj.target_type = 'charge_alloc' and exists (select 1 from po_charge_alloc a left join inv_transfer t on t.id = a.transfer_id
                                                                 where a.id = v_adj.po_charge_alloc_id
                                                                   and ((a.po_id is not null and exists (select 1 from po_line pl join inv_layer x on inv_po_line_of(x.line_ref) = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = a.po_id))
                                                                     or (a.transfer_id is not null and exists (select 1 from inv_layer x where x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')))))) then
      v_adj_deferred := v_adj_deferred + 1;
      continue;
    end if;
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_adj', v_adj.id::text, '', '');
    begin
      v_ims_j := inv_layer_post_cost_adjust(v_adj.id, v_adj.posted_on);
      v_adj_n := v_adj_n + 1;
      if v_ims_j ->> 'status' in ('no_layers', 'no_basis') then v_adj_nolayers := v_adj_nolayers + 1; end if;
      v_adj_rows := v_adj_rows + coalesce((v_ims_j ->> 'layers')::int, 0);
      v_adj_amt  := v_adj_amt  + coalesce((v_ims_j ->> 'posted_cad')::numeric, 0);
    exception when others then
      v_adj_skipped := v_adj_skipped + 1;
      v_adj_skip := v_adj_skip || jsonb_build_object('d', v_adj.posted_on, 'e', jsonb_build_object('kind', 'adjust', 'number', v_adj.source_number, 'id', v_adj.id, 'sqlstate', sqlstate, 'error', sqlerrm));
    end;
  end loop;

  return jsonb_build_object(
    'landed_rows',      coalesce((p_acc ->> 'landed_rows')::int, 0)          + v_landed_rows,
    'fr_rows',          coalesce((p_acc ->> 'fr_rows')::int, 0)              + v_fr_rows,
    'fr_docs',          coalesce((p_acc ->> 'fr_docs')::int, 0)              + v_fr_docs,
    'fr_nobasis',       coalesce((p_acc ->> 'fr_nobasis')::int, 0)           + v_fr_nobasis,
    'fr_nobasis_amt',   coalesce((p_acc ->> 'fr_nobasis_amt')::numeric, 0)   + v_fr_nobasis_amt,
    'fr_orphan',        coalesce((p_acc ->> 'fr_orphan')::int, 0)            + v_fr_orphan,
    'fr_multi',         coalesce((p_acc ->> 'fr_multi')::int, 0)             + v_fr_multi,
    'chg_n',            coalesce((p_acc ->> 'chg_n')::int, 0)                + v_ims_chg_n,
    'chg_rows',         coalesce((p_acc ->> 'chg_rows')::int, 0)             + v_ims_chg_rows,
    'chg_amt',          coalesce((p_acc ->> 'chg_amt')::numeric, 0)          + v_ims_chg_amt,
    'chg_nobasis_amt',  coalesce((p_acc ->> 'chg_nobasis_amt')::numeric, 0)  + v_ims_chg_nobasis_amt,
    'chg_nolayers_amt', coalesce((p_acc ->> 'chg_nolayers_amt')::numeric, 0) + v_ims_chg_nolayers_amt,
    'chg_already',      coalesce((p_acc ->> 'chg_already')::int, 0)          + v_ims_chg_already,
    'chg_skipped',      coalesce((p_acc ->> 'chg_skipped')::int, 0)          + v_ims_chg_skipped,
    'chg_deferred',     coalesce((p_acc ->> 'chg_deferred')::int, 0)         + v_deferred,                              -- cogs-3(판정 119)
    'chg_skip',         coalesce(p_acc -> 'chg_skip', '[]'::jsonb)           || v_chg_skip,
    'adj_n',            coalesce((p_acc ->> 'adj_n')::int, 0)                + v_adj_n,                                -- po-disc-3
    'adj_rows',         coalesce((p_acc ->> 'adj_rows')::int, 0)             + v_adj_rows,
    'adj_amt',          coalesce((p_acc ->> 'adj_amt')::numeric, 0)          + v_adj_amt,
    'adj_nolayers',     coalesce((p_acc ->> 'adj_nolayers')::int, 0)         + v_adj_nolayers,
    'adj_skipped',      coalesce((p_acc ->> 'adj_skipped')::int, 0)          + v_adj_skipped,
    'adj_deferred',     coalesce((p_acc ->> 'adj_deferred')::int, 0)         + v_adj_deferred,
    'adj_skip',         coalesce(p_acc -> 'adj_skip', '[]'::jsonb)           || v_adj_skip);
end;
$$;

-- ═══ 6) inv_layer_apply 재발행 — 원본 20261009002744_po_disc_3.sql:674 바이트 + 1 줄(IMS 비용 블록 · 발주에 레이어가 있나) · ims_rcv 키는 입고 단위 그대로(이견 7) ═══
create or replace function inv_layer_apply(p_until date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_t0          timestamptz := clock_timestamp();
  v_baseline    int;
  r             record;
  v_c int; v_u int; v_rows int; v_short int; v_proc int; v_rev int; v_layers int; v_orphan int; v_nz int; v_unk int; v_unkq numeric;
  v_partial int; v_traced int; v_avg int;
  v_po          int := 0;
  v_sale        int := 0;
  v_sale_keys   int := 0;
  v_sale_rev    int := 0;
  v_tr          int := 0;
  v_tr_layers   int := 0;
  v_tr_orphan   int := 0;
  v_tr_nz       int := 0;
  v_tr_unk      int := 0;
  v_tr_unkq     numeric := 0;
  v_tr_unpaired int := 0;
  v_adj         int := 0;
  v_adj_layers  int := 0;
  v_adj_rows    int := 0;
  v_adj_unk     int := 0;
  v_adj_new_nz  int := 0;
  v_asm         int := 0;
  v_asm_layers  int := 0;
  v_asm_rows    int := 0;
  v_asm_partial int := 0;
  v_asm_nz      int := 0;
  v_asm_unpaired int := 0;
  v_cr          int := 0;
  v_cr_layers   int := 0;
  v_cr_traced   int := 0;
  v_cr_avg      int := 0;
  v_cr_unk      int := 0;
  v_cr_nz       int := 0;
  v_layers_po   int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
  -- landed (2026-09-10)
  v_landed_rows int := 0;
  v_landed_amt  numeric := 0;
  v_landed_orph int := 0;
  v_neg         record;
  -- transfer_freight (2026-09-10)
  v_fr_rows     int := 0;
  v_fr_amt      numeric := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
  -- IMS (2026-09-20) — 창구 둘(inv_layer_post_receipt · inv_layer_post_charge)의 반환을 합친다. ⚠️ 원문 변수와 겹치지 않는 v_ims_ 접두어
  v_ims_src     text;
  v_ims_task    text;
  v_ims_docno   text;
  v_ims_j       jsonb;
  v_ims_rcv         int := 0;   v_ims_rcv_layers int := 0;   v_ims_rcv_exist int := 0;   v_ims_rcv_cost numeric := 0;   v_ims_rcv_skipped int := 0;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_ims_chg_unvisited int := 0;   v_ims_chg_unvisited_amt numeric := 0;
  v_ims_carry_rows int := 0;   v_ims_carry_amt numeric := 0;   v_ims_carry record;   -- tr-4b(판정 79): IMS 트랜스퍼 자식 레이어로 따라간 얹힌 원가(마지막 한 바퀴)
  v_ims_skip    jsonb := '[]'::jsonb;
  -- IMS 초과분 (2026-09-20 · over 닫기) — 형제 창구 inv_layer_post_receipt_over 의 반환을 합친다
  v_ims_over    text;
  v_ims_over_n  int := 0;   v_ims_over_layers int := 0;   v_ims_over_skipped int := 0;
  -- IMS off-PO (⑤-6c1 · 2026-09-27) — 형제 창구 inv_layer_post_receipt_off_po 의 반환을 합친다
  v_ims_offpo   text;
  v_ims_offpo_n int := 0;   v_ims_offpo_layers int := 0;   v_ims_offpo_skipped int := 0;
  v_ims_lref    text;                                                                     -- ⑤-6c1 — off-PO 행(<diff>:offpo)은 입고 단위 창구(ims_rcv)의 근거가 아니다(초안 입고에도 서는 행)
  -- IMS 문 · 보조 넷 (2026-09-20) — 창구가 아직 없는 IMS 사건을 사건 종류별로 센다(0 이 아니면 그 창구를 만들 때다). sale_out 은 없다(문 불필요).
  v_ims_gate    jsonb := '{"transfer_in": 0, "transfer_out": 0, "manual_reversal": 0, "adjust_existing": 0, "adjust_new": 0, "assemble_in": 0, "assemble_out": 0, "credit_in": 0}'::jsonb;
  v_ims_kind    text;                                                                     -- trf-a 2026-09-28 raw.kind — 'bin_move' = 같은 창고 칸 옮기기(레이어는 창고 단위라 할 일이 없다)
  v_bin_moves   int := 0;                                                                 -- trf-a 지나간 칸 옮기기 행 수(out · in 둘 다 센다 · 반환 ims.bin_moves_passed)
  v_ims_wh      text;                                                                     -- tr-2 2026-09-28 창고(IN_TRANSIT 갈래)
  v_ims_trd     int := 0;   v_ims_trd_layers int := 0;   v_ims_trd_rows int := 0;   v_ims_trd_short numeric := 0;   v_ims_trd_skipped int := 0;   v_ims_trd_out int := 0;   -- tr-2 출발 창구 inv_layer_apply_transfer_depart_ims 의 반환 합
  v_ims_tra     int := 0;   v_ims_tra_layers int := 0;   v_ims_tra_rows int := 0;   v_ims_tra_short numeric := 0;   v_ims_tra_skipped int := 0;                            -- tr-3a 도착 창구 inv_layer_apply_transfer_arrive_ims 의 반환 합
  v_ims_leg     text;                                                                     -- tr-3b raw.leg(lost · return_in · over_2 · over_4 갈래)
  v_ims_trs     int := 0;   v_ims_trs_layers int := 0;   v_ims_trs_rows int := 0;   v_ims_trs_short numeric := 0;   v_ims_trs_skipped int := 0;   v_ims_trs_pass int := 0;   -- tr-3b 정리 창구 inv_layer_apply_transfer_settle_ims 의 반환 합
  -- cogs-1(판정 109) 얹기 쏟기 — 날짜 경계 상태 · 누적 반환(속 함수 inv_layer_apply_flush_adds)
  v_add_day     date;
  v_add_flushed boolean := false;
  v_add_acc     jsonb := '{}'::jsonb;
  v_add_j       jsonb;
  v_next_post_id bigint;                                                                  -- cogs-2(판정 114): 이날 실시간이 얹은 배분 줄 중 아직 안 부른 것의 가장 이른 원장 자리(posted_ledger_id) — 이 id 뒤 첫 줄 앞에서 쏟는다
  v_left        int;   v_ks smallint;   v_kr int;   v_ki bigint;   v_ims_chg_late int := 0;   -- cogs-3(판정 119): 아직 안 지난 「그날 id ≤ pid 줄」 수 · 그 줄들의 마지막 루프 키(seq_hint · po_in 먼저 · id) · 날 마감에서야 쏟은 배분 줄 수(0 이어야 한다)
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  -- ⭐ IMS 권한 문 (2026-09-20) — 창구 둘은 ims_require_write(receiving · purchasing) 로 auth.uid() 의 권한을 본다.
  --   권한이 없으면 창구가 전부 예외를 던지고 아래 IMS 블록이 그것을 「건너뛰었다」로 세어 버린다 — 재생성이 조용히 반쪽(IMS 만 빠진 레이어 표)이 된다.
  --   그래서 지우기 전에 먼저 막는다. psql 에서는 request.jwt.claims 에 admin 의 sub 를 심고 돌린다(20260918133858 검증 주석 선례).
  if not (ims_can_write('receiving') and ims_can_write('purchasing')) then
    raise exception 'inv_layer_apply: the IMS cost windows (inv_layer_post_receipt · inv_layer_post_charge) need write permission on receiving and purchasing for this login (auth.uid() = %) — from psql, set request.jwt.claims to an admin''s sub first — nothing was rebuilt',
      coalesce(auth.uid()::text, '(null)');
  end if;
  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  -- cogs-1: 음수 가드 둘을 루프 앞으로(원문 문장 그대로 · 원천 표 inv_cost · inv_doc_cost 만 읽으므로 자리가 바뀌어도 같은 판정) — 얹기 자체는 속 함수가 날짜 경계마다 넣는다
  -- 가드: 키(4키 + occurred_on) 합이 음수면 예외 — inv_layer_cost_add 에는 amount CHECK 가 없어 이것이 유일한 방어다
  select c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on, sum(c.amount) as amt into v_neg
    from inv_cost c
    where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)
    group by c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on
    having sum(c.amount) < 0
    order by 1, 2, 5 limit 1;
  if found then
    raise exception 'inv_cost landed sum(amount) is negative for % / % / % / % @ %: % — refusing to add cost (revaluation offset? inspect inv_cost)',
      v_neg.doc_number, v_neg.line_ref, v_neg.sku, v_neg.warehouse, v_neg.occurred_on, v_neg.amt;
  end if;
  -- B-4 가드: 저널 행 금액이 음수면 예외 — inv_doc_cost 에도 inv_layer_cost_add 에도 amount CHECK 가 없어 이것이 유일한 방어다
  select d.doc_number, d.ref_number, d.occurred_on, d.amount into v_neg
    from inv_doc_cost d
    where d.doc_type = 'transfer' and d.kind = 'transfer_freight'
      and (p_until is null or d.occurred_on <= p_until)
      and d.amount < 0
    order by d.doc_number, d.occurred_on, d.ref_number limit 1;
  if found then
    raise exception 'inv_doc_cost transfer_freight amount is negative for % / invoice % @ %: % — refusing to distribute (correction? inspect inv_doc_cost)',
      v_neg.doc_number, coalesce(v_neg.ref_number, '(null)'), v_neg.occurred_on, v_neg.amount;
  end if;

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, po_in 먼저, id · source 필터 없음 · ⭐ 2026-09-21: 같은 날 유입끼리는 po_in 을 맨 앞에 — seq_hint 는 유입·유출만 가른다. 근거는 이 파일 머리 주석)
  for r in
    select id, event_type, occurred_on, seq_hint                                                            -- cogs-1: occurred_on · seq_hint 를 더했다(순서 · 행은 무변 · 쏟기 경계에 쓴다)
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, case event_type when 'po_in' then 0 else 1 end, id
  loop
    -- ⭐ cogs-1(판정 109) 얹기 쏟기 — 날짜 경계에서만: 날이 바뀌면 지난 날 것 · 그날 첫 유출(seq_hint 2) 앞 · 루프 끝(아래) ⇒ 같은 날 = 들어옴 → 얹기 → 나감 · 행마다 부르지 않는다
    if v_add_day is not null and r.occurred_on > v_add_day then
      -- cogs-3(판정 119): 지난 날 마감 — 그날 아직 안 쏟은 posted 배분 줄을 pid 순으로(그날 줄은 다 지났다) · 트리거가 못 잡은 것(그 자리 뒤에 줄이 더 있었는데 못 잡은 것)은 late 로 센다(0 이어야 한다)
      while v_next_post_id is not null loop
        select g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id into v_ks, v_kr, v_ki from inv_ledger g          -- late 판정: 그날 id ≤ pid 줄의 마지막 루프 키 뒤에 줄이 더 있었으면 트리거가 못 잡은 것
          where g.occurred_on = v_add_day and g.id <= v_next_post_id and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in') and (p_until is null or g.occurred_on <= p_until)
          order by 1 desc, 2 desc, 3 desc limit 1;
        select count(*) into v_left from inv_ledger g
          where g.occurred_on = v_add_day and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in') and (p_until is null or g.occurred_on <= p_until)
            and (g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id) > (v_ks, v_kr, v_ki);
        if v_left > 0 then v_ims_chg_late := v_ims_chg_late + 1; end if;
        v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, v_next_post_id + 1, v_add_acc);
      select min(x.pid) into v_next_post_id from (                                                                                   -- po-disc-3: 비용 배분 줄과 원가 조정 사건의 자리를 함께 본다
        select a.posted_ledger_id as pid from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
          where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id > v_next_post_id
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')
        union all
        select j.posted_ledger_id from inv_cost_adjust j
          where j.status = 'posted' and j.posted_on = v_add_day and j.posted_ledger_id > v_next_post_id
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')) x;
      end loop;
      if not v_add_flushed then
        v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, null, v_add_acc);
      end if;
    end if;
    if r.occurred_on is distinct from v_add_day then
      v_add_day := r.occurred_on; v_add_flushed := false;
      select min(x.pid) into v_next_post_id from (                                                                                   -- cogs-2(판정 114) · po-disc-3: 이날 실시간이 얹은 배분 줄 · 원가 조정 사건의 자리
        select a.posted_ledger_id as pid from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
          where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id is not null
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')
        union all
        select j.posted_ledger_id from inv_cost_adjust j
          where j.status = 'posted' and j.posted_on = v_add_day and j.posted_ledger_id is not null
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')) x;
    end if;
    -- ⭐ cogs-3(판정 119): 쏟기 = 그날 id ≤ posted_ledger_id 인 원장 줄을 루프가 모두 지난 뒤 — 루프 순서(seq_hint · po_in 먼저 · id)가 어떻든. 지금 줄 r 앞에서 「아직 안 지난 그런 줄」 = 루프 키가 r 이상인 것(r 포함) · 같은 날 배분 줄이 여럿이면 pid 순으로 차례차례
    --   (옛 트리거 「r.id > pid 인 첫 줄 앞」은 id 순을 가정했다 — 09-29 의 뒤늦은 po_in(8951683 · 유입 맨 앞)이 TRF-00001 · TRF-00002 도착 줄보다 먼저 트리거를 당겨 운임 4줄 190.00 을 잃었다 · cogs-3c)
    --   같은 날 순서 증명: 소진하는 줄은 seq_hint 2 라 유입 전부 뒤에 id 순으로 온다 ⇒ id > pid 인 유출은 쏟기 뒤 · id > pid 인 유입(출발 소진 · 조립)은 쏟기 앞(판정 109 「들어옴 → 얹기 → 나감」 그대로 · 총액 같음)
    while v_next_post_id is not null loop
      select count(*) into v_left from inv_ledger g
        where g.occurred_on = v_add_day and g.id <= v_next_post_id
          and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
          and (p_until is null or g.occurred_on <= p_until)
          and (g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id) >= (r.seq_hint, case r.event_type when 'po_in' then 0 else 1 end, r.id);
      exit when v_left > 0;
      v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, v_next_post_id + 1, v_add_acc);
      select min(x.pid) into v_next_post_id from (                                                                                   -- po-disc-3: 비용 배분 줄과 원가 조정 사건의 자리를 함께 본다
        select a.posted_ledger_id as pid from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
          where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id > v_next_post_id
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')
        union all
        select j.posted_ledger_id from inv_cost_adjust j
          where j.status = 'posted' and j.posted_on = v_add_day and j.posted_ledger_id > v_next_post_id
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')) x;
    end loop;
    if r.seq_hint = 2 and not v_add_flushed then
      v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, r.id, v_add_acc);  v_add_flushed := true;   -- cogs-2: 그날 첫 유출 앞 — 이 줄 뒤에 얹힌 배분 줄(posted_ledger_id ≥ r.id)은 남긴다
    end if;
    -- ⭐⭐ IMS 문 · 보조 넷 (2026-09-20 · po_in 문의 형제 · Caleb 「문만 낸다 — 창구는 만들지 않는다」) — 창구가 아직 없는 IMS 사건은 보조 함수에 보내지 않고 사건 종류별로 센다.
    -- 왜 안 보내나: 보조 넷(transfer_in · adjust · assemble · credit)은 원가를 inv_cost / 레이어 평균에서 찾는다. IMS 사건은 거기 없어 unit_cost 0 · 'unknown' 레이어가 선다 — po_in 에서 실측된 사고(rcv_unknown 0→2)와 같다.
    -- 왜 창구를 지금 안 만드나: 트랜스퍼 모듈도 IMS 재고조정도 아직 없다 — 쓰지 않을 창구는 맞는지 검증할 표본이 없다. 그 사건을 내는 날 창구를 만들고 여기서 부른다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
    -- 왜 세나: 조용히 지나가면 「IMS 트랜스퍼가 재고에 안 잡힌다」를 아무도 모른다. ims.skipped_by_event 가 0 이 아니면 창구를 만들 때가 됐다는 신호다.
    -- ⚠️ sale_out 은 세지도 막지도 않는다 — 소진은 출처를 안 보는 한 원장 FIFO 가 맞다(inv_layer_fifo_take). po_in 은 아래 분기가 창구로 처리한다.
    -- ⭐ 두 leg 다 막는다(⬜4) — transfer_out · manual_reversal · assemble_out 도 IMS 면 여기서 센다. out 은 대응 in 이 처리하므로 in 만 막아도 레이어는 안 서지만, 아래 *_unpaired 신호가 IMS 것으로 오염된다(그 집계에서도 ims 를 뺀다).
    -- 원문 루프 select(id, event_type)는 바꾸지 않는다 — po_in·sale_out 이 아닌 행만 PK 조회 한 번(po_in 은 아래 분기가 이미 조회한다).
    if r.event_type not in ('po_in', 'sale_out', 'credit_in', 'adjust_existing', 'adjust_new') then   -- adj-a 2026-09-28: 조정 둘도 아래 갈래가 source 로 가른다(IMS → inv_layer_apply_adjust_ims) · ⓒ1 2026-09-25: credit_in 은 아래 갈래가 source 로 가른다(IMS → 창구 inv_layer_apply_credit_ims · 문에서 세지 않는다 · skipped_by_event.credit_in 은 늘 0)
      select source, raw ->> 'kind', warehouse, raw ->> 'leg' into v_ims_src, v_ims_kind, v_ims_wh, v_ims_leg from inv_ledger where id = r.id;   -- trf-a: kind 도 함께(조회 한 번 그대로) · tr-2: warehouse 도 · tr-3b: leg 도
      if v_ims_src = 'ims' and v_ims_kind = 'bin_move' and r.event_type in ('transfer_in', 'transfer_out') then   -- trf-a 2026-09-28 칸 옮기기(같은 창고 · inv_post_move) — 레이어는 (sku, warehouse) 단위라 할 일이 없다 · 세지 않고 지나간다(실시간 창구도 레이어를 부르지 않는다 = 같은 결과) · 창고 간 문서는 kind 가 다르다(뒤 차수의 갈래)
        v_bin_moves := v_bin_moves + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and v_ims_leg in ('lost', 'return_in', 'over_4') then   -- tr-3b 운송 중 정리(lost · return) · 더 온 몫(sent_more) → 창구(inv_layer_post_transfer_settle · 실시간과 같은 함수) · 행마다(line_ref 가 곧 키)
        begin
          v_ims_j := inv_layer_apply_transfer_settle_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_trs        := v_ims_trs + 1;
            v_ims_trs_layers := v_ims_trs_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_trs_rows   := v_ims_trs_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_trs_short  := v_ims_trs_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_trs_skipped := v_ims_trs_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_settle', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and v_ims_leg = 'over_2' then                  -- tr-3b 더 온 몫의 IN_TRANSIT in(같은 날 ±N · 레이어는 over_4 가 출발 창고에서 곧장 도착 창고로) — 세고 지나간다
        v_ims_trs_pass := v_ims_trs_pass + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_out' then     -- tr-2 2026-09-28 창고 간 트랜스퍼 출발 out(출발 창고) — IN_TRANSIT in 이 처리한다(불러온 축과 같은 결) · 세고 지나간다 · tr-3b: leg 3 · return_out · over_1 · over_3 도 여기
        v_ims_trd_out := v_ims_trd_out + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_in' and v_ims_wh = 'IN_TRANSIT' then   -- tr-2 출발 IN_TRANSIT in → 창구(inv_layer_post_transfer_depart · 실시간과 같은 함수) · (doc, sku) 한 번 · 도착 창고 in 은 ④(지금은 문이 센다)
        begin
          v_ims_j := inv_layer_apply_transfer_depart_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_trd        := v_ims_trd + 1;
            v_ims_trd_layers := v_ims_trd_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_trd_rows   := v_ims_trd_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_trd_short  := v_ims_trd_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_trd_skipped := v_ims_trd_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_depart', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_in' and v_ims_wh <> 'IN_TRANSIT' then   -- tr-3a 도착 창고 in(leg 4) → 창구(inv_layer_post_transfer_arrive · IN_TRANSIT 문서 범위 FIFO · 실시간과 같은 함수) · (doc, receipt, sku) 한 번 · leg 3 out 은 위 out 갈래가 센다
        begin
          v_ims_j := inv_layer_apply_transfer_arrive_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_tra        := v_ims_tra + 1;
            v_ims_tra_layers := v_ims_tra_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_tra_rows   := v_ims_tra_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_tra_short  := v_ims_tra_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_tra_skipped := v_ims_tra_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_arrive', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
      if v_ims_src = 'ims' then
        v_ims_gate := jsonb_set(v_ims_gate, array[r.event_type], to_jsonb(coalesce((v_ims_gate ->> r.event_type)::int, 0) + 1));
        continue;
      end if;
    end if;
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers_po := v_layers_po + v_c; v_unknown := v_unknown + v_u;
      -- ⭐⭐ IMS 입고 (2026-09-20) — 보조 inv_layer_apply_po_in 은 source='ims' 면 문에서 돌아섰다(0·0). 이 줄의 레이어는 창구 inv_layer_post_receipt 가 만든다.
      -- 왜 여기(루프 안 · 날짜순)이고 끝이 아닌가: 입고 레이어는 **수량** 레이어다 — 뒤에 오는 sale_out·transfer_out 이 FIFO 로 이것을 소진한다.
      --   끝에서 만들면 루프 안의 소진이 이 레이어를 못 보고 short 로 떨어지거나 다른 레이어를 먹어, 실시간 기표(확정 때 창구가 만든 상태)와 재생성 결과가 갈라진다.
      --   비용(cost_add)은 수량이 아니라 금액만 얹으므로 끝(landed·운송비와 같은 층)에 둔다 — 아래 「IMS 비용」 블록.
      -- 왜 창구에 넘기나: 원가 규칙(환율 곱하기 · 기준까지만 · bin 접기)이 창구 안에 있다. 여기 다시 적으면 같은 규칙이 두 곳에 살고 한쪽만 고치면 조용히 갈라진다.
      -- 왜 원장에서 훑나: 이 함수의 일은 「원장에서 레이어를 다시 만드는 것」이다 — 원장에 없으면 레이어도 없다. p_until 도 그대로 걸린다(as-of).
      -- 왜 입고 단위(doc_task_id = po_receipt.id)로 한 번인가: 입고 하나가 원장에 bin 별 여러 줄을 남긴다. 창구는 입고 단위로 일하고 4키 멱등이라 두 번 불러도 안전하지만,
      --   세는 값이 겹치지 않게 done 표(kind 'ims_rcv')로 한 번만 부른다. 같은 입고의 원장 줄은 occurred_on 이 같아(received_on) p_until 경계에 걸쳐 갈라지지 않는다.
      -- 왜 건너뛰고 세나(멈추지 않나 · Caleb 판정 2026-09-20): 이 함수는 검산 도구다. 입고 한 건의 빈칸(환율)으로 검산 자체가 안 되면 도구가 못 쓰게 된다.
      --   건너뛰어도 틀린 값이 들어가지 않는다 — 0 원가 레이어를 만드는 것과 전혀 다르다. 환율을 채우고 다시 돌리면 그 자리에 제대로 선다. 선례: freight_no_basis(기준 0 이면 버리고 금액을 센다).
      --   ⚠️ 몇 건을 왜 건너뛰었는지 반환(ims.receipts_skipped · ims.skip_reasons)에 반드시 남긴다 — 조용히 지나가면 같은 사고의 재판이다.
      select source, doc_task_id, doc_number, line_ref into v_ims_src, v_ims_task, v_ims_docno, v_ims_lref from inv_ledger where id = r.id;   -- 루프 select 는 바꾸지 않는다(원문 무변) — PK 조회 한 번 · ⑤-6c1 line_ref 도
      if v_ims_src = 'ims' and v_ims_task is not null and v_ims_lref not like '%:offpo'                                  -- ⑤-6c1 off-PO 행으로는 inv_layer_post_receipt 를 부르지 않는다(초안 입고라 거부돼 헛 skip 이 남는다)
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_rcv' and d.doc_number = v_ims_task and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_rcv', v_ims_task, '', '');   -- 입고 단위 키 — sku·warehouse 는 not null 이라 빈 문자열
        begin
          v_ims_j := inv_layer_post_receipt(v_ims_task::uuid);
          v_ims_rcv        := v_ims_rcv + 1;
          v_ims_rcv_layers := v_ims_rcv_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
          v_ims_rcv_exist  := v_ims_rcv_exist  + coalesce((v_ims_j->>'layers_existing')::int, 0);   -- 지운 뒤라 0 이어야 한다(생기면 신호 — 다른 축이 같은 4키를 먼저 만들었다)
          v_ims_rcv_cost   := v_ims_rcv_cost   + coalesce((v_ims_j->>'cost_total_cad')::numeric, 0);
        exception when others then
          -- ⚠️ 서브트랜잭션 — 창구가 던진 것(환율 없음 · 확정 아님 · po_line 없음 · base_currency 없음)만 여기로 온다. 그 호출이 넣은 레이어는 서브트랜잭션이 되돌린다 — 이 입고의 레이어는 하나도 서지 않는다.
          v_ims_rcv_skipped := v_ims_rcv_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'receipt', 'number', v_ims_docno, 'id', v_ims_task, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS 초과분 (2026-09-20 · over 닫기) — line_ref 가 ':over' 인 po_in 행은 형제 창구 inv_layer_post_receipt_over(diff_id) 가 만든다(free → 0 · billed/credited → 기준 레이어의 unit_cost).
      --   왜 여기(루프 안): 수량 레이어라 뒤의 FIFO 소진이 봐야 한다(위 입고와 같은 이유). 기준 레이어가 먼저 서야 하는데, 초과분 행은 같은 날(received_on)·더 큰 id 라 (occurred_on, seq_hint, id) 순서에서 항상 뒤다.
      --   왜 diff 단위 한 번: 한 차이가 빈 별 여러 행을 남긴다 — done 표 kind 'ims_over'. 거부(기준 레이어 없음 등)는 건너뛰고 ims.over_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_over from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:over';
      if v_ims_over is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_over' and d.doc_number = v_ims_over and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_over', v_ims_over, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_over(v_ims_over::uuid);
          v_ims_over_n      := v_ims_over_n + 1;
          v_ims_over_layers := v_ims_over_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_over_skipped := v_ims_over_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'over', 'number', v_ims_docno, 'id', v_ims_over, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS off-PO (⑤-6c1 · 2026-09-27) — line_ref 가 ':offpo' 인 po_in 행은 형제 창구 inv_layer_post_receipt_off_po(diff_id) 가 만든다(accepted_free → 0 · accepted_billed → diff.unit_price × 환율 · manual).
      --   왜 diff 단위 한 번: 한 차이 = 한 행 · 한 칸이지만 over 와 같은 모양으로 done 표 kind 'ims_offpo' · 거부는 건너뛰고 ims.offpo_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_offpo from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:offpo';
      if v_ims_offpo is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_offpo' and d.doc_number = v_ims_offpo and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_offpo', v_ims_offpo, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_off_po(v_ims_offpo::uuid);
          v_ims_offpo_n      := v_ims_offpo_n + 1;
          v_ims_offpo_layers := v_ims_offpo_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_offpo_skipped := v_ims_offpo_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'off_po', 'number', v_ims_docno, 'id', v_ims_offpo, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
    elsif r.event_type = 'sale_out' then
      select * into v_rows, v_short, v_proc, v_rev from inv_layer_apply_sale_out(r.id, p_until);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_sale_keys := v_sale_keys + v_proc; v_sale_rev := v_sale_rev + v_rev;
    elsif r.event_type = 'transfer_in' then
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan; v_tr_nz := v_tr_nz + v_nz;
      v_tr_unk := v_tr_unk + v_unk; v_tr_unkq := v_tr_unkq + v_unkq;
    elsif r.event_type in ('adjust_existing', 'adjust_new') then
      -- adj-a 2026-09-28: IMS 축(source ims)은 창구(inv_layer_post_adjust)로 · Cin7 축은 종전 inv_layer_apply_adjust — 같은 반환 모양(credit_in 갈래와 같은 식)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust_ims(r.id, p_until);
      else
        select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
      end if;
      v_adj := v_adj + 1; v_adj_layers := v_adj_layers + v_layers; v_adj_rows := v_adj_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_adj_unk := v_adj_unk + v_unk; v_adj_new_nz := v_adj_new_nz + v_nz;
    elsif r.event_type = 'assemble_in' then
      select * into v_layers, v_rows, v_short, v_partial, v_nz, v_proc from inv_layer_apply_assemble(r.id, p_until);
      v_asm := v_asm + 1; v_asm_layers := v_asm_layers + v_layers; v_asm_rows := v_asm_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_asm_partial := v_asm_partial + v_partial; v_asm_nz := v_asm_nz + v_nz;
    elsif r.event_type = 'assemble_out' then
      v_asm := v_asm + 1;   -- 부품 out 은 대응 in 이 처리한다(A-2 ④) — 여기서는 세기만
    elsif r.event_type = 'credit_in' then
      -- ⓒ1 2026-09-25: IMS 축(source ims)은 창구(inv_layer_post_credit)로 · Cin7 축은 종전 inv_layer_apply_credit — 두 축이 같은 반환 모양(17-f · 실시간과 재생성이 같은 함수)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit_ims(r.id, p_until);
      else
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit(r.id, p_until);
      end if;
      v_cr := v_cr + 1; v_cr_layers := v_cr_layers + v_layers; v_cr_traced := v_cr_traced + v_traced;
      v_cr_avg := v_cr_avg + v_avg; v_cr_unk := v_cr_unk + v_unk; v_cr_nz := v_cr_nz + v_nz;
    else
      v_tr := v_tr + 1;   -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다
    end if;
  end loop;
  -- cogs-3(판정 119): 마지막 날 마감 — 남은 posted 배분 줄을 pid 순으로(late 판정은 날 마감과 같다)
  while v_next_post_id is not null loop
    select g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id into v_ks, v_kr, v_ki from inv_ledger g          -- late 판정: 그날 id ≤ pid 줄의 마지막 루프 키 뒤에 줄이 더 있었으면 트리거가 못 잡은 것
      where g.occurred_on = v_add_day and g.id <= v_next_post_id and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in') and (p_until is null or g.occurred_on <= p_until)
      order by 1 desc, 2 desc, 3 desc limit 1;
    select count(*) into v_left from inv_ledger g
      where g.occurred_on = v_add_day and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in') and (p_until is null or g.occurred_on <= p_until)
        and (g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id) > (v_ks, v_kr, v_ki);
    if v_left > 0 then v_ims_chg_late := v_ims_chg_late + 1; end if;
    v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, v_next_post_id + 1, v_add_acc);
    select min(x.pid) into v_next_post_id from (                                                                                   -- po-disc-3: 비용 배분 줄과 원가 조정 사건의 자리를 함께 본다
      select a.posted_ledger_id as pid from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
        where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id > v_next_post_id
          and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')
      union all
      select j.posted_ledger_id from inv_cost_adjust j
        where j.status = 'posted' and j.posted_on = v_add_day and j.posted_ledger_id > v_next_post_id
          and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')) x;
  end loop;
  v_add_acc := inv_layer_apply_flush_adds(p_until, p_until, null, v_add_acc);                                    -- cogs-1: 마지막 쏟기 — 남은 것 전부(p_until 까지 · 대상이 끝내 없는 것은 아래 orphan · unvisited 신호 그대로)

  -- ⭐ 순액 > 0 인데 같은 날짜의 대응 in 이 처리하지 않은 out 키 — (doc, sku, wh, day) · 0 이어야 한다(생기면 신호)
  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse, occurred_on
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 IMS out leg 는 위 문이 세었다(ims.skipped_by_event) — 여기 섞이면 「생기면 신호」가 IMS 것으로 오염된다
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse, occurred_on
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku
                          and d.warehouse = o.warehouse and d.day = o.occurred_on);

  -- 순액 > 0 인데 대응 in 이 처리하지 않은 부품 out 키 — 0 이어야 한다(생기면 신호). 순액 ≤ 0(상쇄 소멸) 키는 제외.
  select count(*) into v_asm_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type = 'assemble_out'
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 같은 이유
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'asm_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

  -- ═══ 얹기 셋의 집계 — 속 함수의 누적 반환을 원문 카운터로 옮겨 담는다(반환 키 · 뜻 무변 · 얹기 자체는 루프 안 날짜 경계에서 끝났다 · cogs-1) ═══
  v_landed_rows          := coalesce((v_add_acc ->> 'landed_rows')::int, 0);
  v_fr_rows              := coalesce((v_add_acc ->> 'fr_rows')::int, 0);
  v_fr_docs              := coalesce((v_add_acc ->> 'fr_docs')::int, 0);
  v_fr_nobasis           := coalesce((v_add_acc ->> 'fr_nobasis')::int, 0);
  v_fr_nobasis_amt       := coalesce((v_add_acc ->> 'fr_nobasis_amt')::numeric, 0);
  v_fr_orphan            := coalesce((v_add_acc ->> 'fr_orphan')::int, 0);
  v_fr_multi             := coalesce((v_add_acc ->> 'fr_multi')::int, 0);
  v_ims_chg_n            := coalesce((v_add_acc ->> 'chg_n')::int, 0);
  v_ims_chg_rows         := coalesce((v_add_acc ->> 'chg_rows')::int, 0);
  v_ims_chg_amt          := coalesce((v_add_acc ->> 'chg_amt')::numeric, 0);
  v_ims_chg_nobasis_amt  := coalesce((v_add_acc ->> 'chg_nobasis_amt')::numeric, 0);
  v_ims_chg_nolayers_amt := coalesce((v_add_acc ->> 'chg_nolayers_amt')::numeric, 0);
  v_ims_chg_already      := coalesce((v_add_acc ->> 'chg_already')::int, 0);
  v_ims_chg_skipped      := coalesce((v_add_acc ->> 'chg_skipped')::int, 0);
  select coalesce(jsonb_agg(s -> 'e' order by (s ->> 'd')::date, s -> 'e' ->> 'number', (s -> 'e' ->> 'id')::uuid), '[]'::jsonb) into v_add_j
    from jsonb_array_elements(coalesce(v_add_acc -> 'chg_skip', '[]'::jsonb)) s;                        -- 건너뛴 비용은 원문 순서(charge_date · charge_number · id)로 · 입고 skip 뒤에 잇는다(원문과 같은 자리)
  v_ims_skip := v_ims_skip || v_add_j;
  select coalesce(sum(amount), 0) into v_landed_amt from inv_layer_cost_add where kind = 'landed' and ref_number is null;   -- cogs-1: 옛 판은 이 합을 IMS 비용을 얹기 전에 읽어 실질 「불러온 landed 만」이었다 — 자리가 뒤로 가므로 그 뜻을 술어로 굳힌다(불러온 landed 는 ref_number 가 비어 있고 IMS 비용은 발주·트랜스퍼 번호가 든다 · 반환 landed_amount 무변)

  -- orphan — 대응 purchase 레이어가 없는 landed 키 (조인에서 조용히 빠지므로 따로 센다)
  select count(*) into v_landed_orph
    from (select distinct c.doc_number, c.line_ref, c.sku, c.warehouse
            from inv_cost c
            where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)) k
    where not exists (select 1 from inv_layer x
                        where x.origin_type = 'purchase' and x.doc_number = k.doc_number and x.line_ref = k.line_ref
                          and x.sku = k.sku and x.warehouse = k.warehouse);

  select coalesce(sum(amount), 0) into v_fr_amt from inv_layer_cost_add where kind = 'transfer_freight';


  -- 방문하지 않은 확정 비용 — 위 exists 가 거른 것. 금액은 창구와 같은 규칙으로 CAD(기준통화면 ×1 · 아니면 × exchange_rate). ⚠️ 환율 null 인 외화 비용은 합에서 빠진다(확정 게이트 ⑥ 뒤엔 없다 · 건수에는 든다).
  select count(*), coalesce(sum(c.total_amount * case when cu.code is not distinct from k.value then 1 else c.exchange_rate end), 0)
    into v_ims_chg_unvisited, v_ims_chg_unvisited_amt
    from po_charge c
    join ref_currency cu on cu.id = c.currency_id
    left join inv_config k on k.key = 'base_currency'
    where c.status = 'confirmed' and c.confirmed_at is not null
      and (p_until is null or c.charge_date <= p_until)
      and not (exists (select 1
                        from po_charge_alloc a
                        join po_line  pl on pl.po_id = a.po_id
                        join inv_layer x on inv_po_line_of(x.line_ref) = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'   -- rcv-1a
                        where a.po_charge_id = c.id)
               or exists (select 1                                                       -- tr-4: 트랜스퍼 배분(위 루프와 같은 조건)
                            from po_charge_alloc a
                            join inv_transfer t on t.id = a.transfer_id
                            join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%'   -- inv-basis-3(판정 95 ㉓) — 위 루프와 같은 조건
                            where a.po_charge_id = c.id));

  -- ═══ tr-4b(판정 79) 얹힌 원가 따라가기 — 마지막 한 바퀴 = 검산(cogs-2 · 판정 110) ═══
  -- cogs-2: 얹기는 루프 안 날짜 경계에서 제자리에 들고(첫 차수) 자식이 선 순간 fifo_take 가 carry 를 · 얹히는 순간 settle 이 자식 carried 를 낸다 ⇒ 이 바퀴는 남은 것이 없어야 한다(carried_rows 0 이 정상 · 0 이 아니면 신호).
  --   어느 축이든(불러온 축 TR- 자식도 · 판정 110) 트랜스퍼 자식을 id 순(부모 먼저)으로 한 번 더 돈다 · 멱등(같은 행은 다시 넣지 않는다).
  for v_ims_carry in
    select y.id from inv_layer y
     where y.origin_type = 'transfer' and y.parent_layer_id is not null
     order by y.id
  loop
    v_ims_carry_rows := v_ims_carry_rows + inv_layer_carry(v_ims_carry.id);
  end loop;
  select coalesce(sum(amount), 0) into v_ims_carry_amt from inv_layer_cost_add where kind = 'carried';

  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                                     'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
              and (p_until is null or occurred_on <= p_until)
            group by event_type) s;

  return jsonb_build_object(
    'until',                     p_until,
    'processed_po_in',           v_po,
    'processed_sale_out',        v_sale,
    'sale_keys_processed',       v_sale_keys,
    'sale_keys_fully_reversed',  v_sale_rev,
    'processed_transfer',        v_tr,
    'transfer_layers_created',   v_tr_layers,
    'transfer_orphan_in',        v_tr_orphan,
    'transfer_keys_net_zero',    v_tr_nz,
    'transfer_unknown_layers',   v_tr_unk,
    'transfer_unknown_qty',      v_tr_unkq,
    'transfer_out_unpaired',     v_tr_unpaired,
    'processed_adjust',          v_adj,
    'adjust_layers_created',     v_adj_layers,
    'adjust_consume_rows',       v_adj_rows,
    'adjust_unknown_layers',     v_adj_unk,
    'adjust_new_net_zero',       v_adj_new_nz,
    'processed_assembly',        v_asm,
    'assembly_layers_created',   v_asm_layers,
    'assembly_consume_rows',     v_asm_rows,
    'assembly_partial_cost',     v_asm_partial,
    'assembly_net_zero',         v_asm_nz,
    'assembly_out_unpaired',     v_asm_unpaired,
    'processed_credit',          v_cr,
    'credit_layers_created',     v_cr_layers,
    'credit_traced',             v_cr_traced,
    'credit_avg',                v_cr_avg,
    'credit_unknown_layers',     v_cr_unk,
    'credit_net_zero',           v_cr_nz,
    'landed_rows',               v_landed_rows,
    'landed_amount',             v_landed_amt,
    'landed_orphan',             v_landed_orph,
    'freight_rows',              v_fr_rows,
    'freight_amount',            v_fr_amt,
    'freight_docs',              v_fr_docs,
    'freight_no_basis',          v_fr_nobasis,
    'freight_no_basis_amount',   v_fr_nobasis_amt,
    'freight_orphan',            v_fr_orphan,
    'freight_multi_ref',         v_fr_multi,
    -- ⭐ IMS (2026-09-20) — 한 칸에 중첩한다. ⚠️ jsonb_build_object 는 인자 100개 한도(키 50) — 기존 45키에 평면으로 더하면 넘는다. 기존 45칸은 이름·뜻 무변.
    'ims', jsonb_build_object(
      'receipts_posted',           v_ims_rcv,               -- 창구가 레이어를 만든 입고 수
      'layers_created',            v_ims_rcv_layers,        -- 그 레이어 행 수(라인 단위 · bin 접힘)
      'layers_existing',           v_ims_rcv_exist,         -- 0 이어야 한다
      'layers_cost_cad',           v_ims_rcv_cost,          -- Σ qty × unit_cost(CAD)
      'receipts_skipped',          v_ims_rcv_skipped,       -- ⚠️ 창구가 거부해 건너뛴 입고 수 — skip_reasons 에 문장
      'charges_posted',            v_ims_chg_n,
      'charge_rows',               v_ims_chg_rows,          -- cost_add 행 수
      'charge_amount_cad',         v_ims_chg_amt,
      'charge_no_basis_amount_cad',  v_ims_chg_nobasis_amt,   -- 버린 금액(정본 D)
      'charge_no_layers_amount_cad', v_ims_chg_nolayers_amt,  -- 버린 금액(레이어 없는 발주)
      'charge_already_posted',     v_ims_chg_already,       -- 0 이어야 한다
      'charges_skipped',           v_ims_chg_skipped,       -- ⚠️ 창구가 거부해 건너뛴 비용 수
      'charges_unvisited',         v_ims_chg_unvisited,     -- 배분된 발주 어디에도 IMS 레이어가 없어 부르지 않은 확정 비용 수
      'charges_unvisited_amount_cad', v_ims_chg_unvisited_amt,  -- 그 금액 — 설명된 차이
      'over_posted',               v_ims_over_n,            -- ⭐ 2026-09-20 초과분(over 닫기) — 창구가 레이어를 만든 차이 수
      'over_layers',               v_ims_over_layers,
      'over_skipped',              v_ims_over_skipped,      -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'over'
      'offpo_posted',              v_ims_offpo_n,           -- ⭐ ⑤-6c1 off-PO — 창구가 레이어를 만든 차이 수
      'offpo_layers',              v_ims_offpo_layers,
      'offpo_skipped',             v_ims_offpo_skipped,     -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'off_po'
      'bin_moves_passed',          v_bin_moves,             -- ⭐ trf-a 2026-09-28 raw.kind bin_move 인 칸 옮기기 행 수 — 창구가 있으니 skipped_by_event 의 transfer 두 키에 안 잡힌다(0 이 정상)
      'transfer_departs_posted',   v_ims_trd,               -- ⭐ tr-2 2026-09-28 raw.kind transfer 출발(doc × sku 키) — 창구가 레이어를 만든 수
      'transfer_depart_layers',    v_ims_trd_layers,        -- IN_TRANSIT 레이어 수
      'transfer_depart_consume_rows', v_ims_trd_rows,       -- 출발 창고 소진 행 수
      'transfer_depart_short_qty', v_ims_trd_short,         -- 출발 창고 레이어가 모자란 EA(불러온 축과 같이 short · 레이어 없음)
      'transfer_departs_skipped',  v_ims_trd_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_depart'
      'transfer_out_passed',       v_ims_trd_out,           -- 출발 out 행 수(leg 1 · tr-3a 부터 도착 leg 3 IN_TRANSIT out 도 여기) — skipped_by_event.transfer_out 에 안 잡힌다
      'transfer_arrivals_posted',  v_ims_tra,               -- ⭐ tr-3a 도착(doc × receipt × sku 키) — 창구가 레이어를 만든 수
      'transfer_arrive_layers',    v_ims_tra_layers,        -- 도착 창고 레이어 수
      'transfer_arrive_consume_rows', v_ims_tra_rows,       -- IN_TRANSIT 소진 행 수(문서 범위)
      'transfer_arrive_short_qty', v_ims_tra_short,         -- IN_TRANSIT 문서 레이어가 모자란 EA(불러온 축과 같이 short)
      'transfer_arrivals_skipped', v_ims_tra_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_arrive'
      'transfer_settles_posted',   v_ims_trs,               -- ⭐ tr-3b 정리 · 더 온 몫(lost · return_in · over_4 행마다) — 창구가 소진 · 레이어를 만든 수
      'transfer_settle_layers',    v_ims_trs_layers,        -- 되돌린 · 더 보낸 몫의 레이어 수(lost 는 0)
      'transfer_settle_consume_rows', v_ims_trs_rows,       -- 소진 행 수
      'transfer_settle_short_qty', v_ims_trs_short,         -- 문서 레이어가 모자란 EA
      'transfer_settles_skipped',  v_ims_trs_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_settle'
      'transfer_over_in_passed',   v_ims_trs_pass,          -- over_2 행 수(세고 지나감)
      'carried_rows',              v_ims_carry_rows,        -- ⭐ tr-4b(판정 79) 마지막 검산 바퀴가 넣은 따라간 행 수 — cogs-2: 0 이 정상(자식이 선 순간 · 얹히는 순간 이미 따라갔다) · 0 이 아니면 신호
      'carried_amount_cad',        v_ims_carry_amt,         -- kind carried 합
      'charge_allocs_late_boundary', v_ims_chg_late,        -- ⭐ cogs-3(판정 119) 트리거가 못 잡아 날 마감에서야 쏟은 posted 배분 줄 수 — 0 이어야 한다(0 이 아니면 세는 집합이 루프와 다르다)
      'charge_allocs_deferred',    coalesce((v_add_acc ->> 'chg_deferred')::int, 0),   -- ⭐ cogs-3(판정 119) 안전띠가 미룬 횟수 — 0 이어야 한다(0 이 아니면 쏟기 기준이 또 틀린 것)
      'adjusts', jsonb_build_object('posted', coalesce((v_add_acc ->> 'adj_n')::int, 0), 'rows', coalesce((v_add_acc ->> 'adj_rows')::int, 0), 'amount_cad', coalesce((v_add_acc ->> 'adj_amt')::numeric, 0),
                                 'no_layers', coalesce((v_add_acc ->> 'adj_nolayers')::int, 0), 'skipped', coalesce((v_add_acc ->> 'adj_skipped')::int, 0), 'deferred', coalesce((v_add_acc ->> 'adj_deferred')::int, 0),
                                 'skip_reasons', coalesce(v_add_acc -> 'adj_skip', '[]'::jsonb)),   -- ⭐ po-disc-3(판정 391 · 394) IMS 원가 조정 사건 — deferred · skipped 는 0 이어야 한다
      'skipped_by_event',          v_ims_gate,              -- ⭐ 2026-09-20 창구가 아직 없어 보조 함수에 보내지 않은 IMS 사건 수(종류별 · 여덟 키 항상) — 0 이 아니면 그 사건의 창구를 만들 때다
      'skip_reasons',              v_ims_skip),             -- [{kind receipt|charge · number · id · sqlstate · error}] — 이유 문장 그대로
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

-- ═══ 7) po_fx_cost_lines 재발행 — 원본 20261009025008_po_disc_5b.sql:40 바이트 + 1 줄 ═══
create or replace function public.po_fx_cost_lines(p_po_id uuid)
  returns table (po_line_id uuid, line_no int, sku text, layers int, layer_qty numeric, pin_source text, pin_fx numeric, unit_price_net numeric,
                 target_cad numeric, layer_cad numeric, fx_fix_cad numeric, already_cad numeric, remaining_cad numeric,
                 excluded_invoice_layers int, unpinned_layers int)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with p as (
    select x.id, x.exchange_rate, (c.code is not distinct from b.code) as is_base
      from public.po x join public.ref_currency c on c.id = x.currency_id
      left join (select k.value as code from public.inv_config k where k.key = 'base_currency') b on true
     where x.id = p_po_id
  ), ly as (
    select pl.id as po_line_id, pl.line_no, pr.sku, y.id as layer_id, y.qty, y.unit_cost,
           k.exchange_rate_source as pin_source, k.exchange_rate as pin_fx, k.unit_price_net, k.unit_cost_cad
      from public.po_line pl join public.product pr on pr.id = pl.product_id
      join public.inv_layer y on public.inv_po_line_of(y.line_ref) = pl.id::text and y.origin_type = 'purchase' and y.cost_source = 'po_line'   -- rcv-1a
      left join public.po_receipt r on r.receipt_number = y.doc_number
      left join public.po_receipt_cost k on k.receipt_id = r.id and k.po_line_id = pl.id
     where pl.po_id = p_po_id
  ), fx as (
    select j.po_line_id, coalesce(sum(j.amount_cad), 0) as fx_fix_cad
      from public.inv_cost_adjust j
     where j.source_type = 'fx_fix' or (j.source_type = 'reversal' and exists (select 1 from public.inv_cost_adjust o where o.id = j.reverses_id and o.source_type = 'fx_fix'))   -- 이견 10: fx_fix 와 그 되돌림만
     group by j.po_line_id
  ), g as (
    select ly.po_line_id, ly.line_no, ly.sku,
           count(*)::int as layers,
           coalesce(sum(ly.qty) filter (where ly.pin_source = 'po'), 0) as layer_qty,
           min(ly.pin_source) filter (where ly.pin_source = 'po') as pin_source,
           max(ly.pin_fx) filter (where ly.pin_source = 'po') as pin_fx,
           max(ly.unit_price_net) filter (where ly.pin_source = 'po') as unit_price_net,
           coalesce(sum(ly.qty * ly.unit_price_net * (select coalesce(p.exchange_rate, 0) from p)) filter (where ly.pin_source = 'po'), 0) as target_cad,
           coalesce(sum(ly.qty * ly.unit_cost_cad) filter (where ly.pin_source = 'po'), 0) as layer_cad,
           count(*) filter (where ly.pin_source = 'invoice')::int as excluded_invoice_layers,
           count(*) filter (where ly.unit_cost_cad is null)::int as unpinned_layers
      from ly group by ly.po_line_id, ly.line_no, ly.sku
  )
  select g.po_line_id, g.line_no, g.sku, g.layers, g.layer_qty, g.pin_source, g.pin_fx, g.unit_price_net,
         case when (select p.is_base from p) or (select p.exchange_rate from p) is null then 0 else g.target_cad end as target_cad,
         g.layer_cad, coalesce(fx.fx_fix_cad, 0) as fx_fix_cad,
         g.layer_cad + coalesce(fx.fx_fix_cad, 0) as already_cad,
         case when (select p.is_base from p) or (select p.exchange_rate from p) is null or g.layer_qty = 0 then 0
              else round(g.target_cad - g.layer_cad - coalesce(fx.fx_fix_cad, 0), 2) end as remaining_cad,   -- 기준통화 · 환율 없음 · po 핀 없음 → 0
         g.excluded_invoice_layers, g.unpinned_layers
    from g left join fx on fx.po_line_id = g.po_line_id
   order by g.line_no
$$;

-- ═══ 8) po_credit_cost_events 재발행 — 원본 20261009023028_po_disc_5a.sql:91 바이트 + 1 줄 ═══
create or replace function public.po_credit_cost_events(p_credit_id uuid, p_post boolean default true) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'po_credit_cost_events@2026-10-09.1';
  v_c        public.po_invoice%rowtype;
  v_cur      text;  v_base text;
  v_factor   numeric;
  v_staff    uuid;
  v_l        record;
  v_px       record;
  v_lc       record;
  v_fx       numeric;  v_fx_src text;
  v_amt      numeric;
  v_recv     numeric;
  v_id       uuid;
  v_j        jsonb;
  v_events   jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
begin
  select * into v_c from public.po_invoice where id = p_credit_id;
  if not found or v_c.doc_kind <> 'credit' then raise exception 'Credit note % not found — no cost was changed', p_credit_id; end if;
  if exists (select 1 from public.inv_cost_adjust j join public.po_invoice_line cl on cl.id = j.source_id
              where j.source_type = 'po_credit' and cl.po_invoice_id = p_credit_id and not exists (select 1 from public.inv_cost_adjust r where r.reverses_id = j.id)) then
    raise exception 'Credit note % already has cost events — they are reversed on Reopen or Cancel, not re-made — no cost was changed', v_c.invoice_number;
  end if;
  select c.code into v_cur from public.ref_currency c where c.id = v_c.currency_id;
  select k.value into v_base from public.inv_config k where k.key = 'base_currency';
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  v_factor := public.po_invoice_discount_factor(p_credit_id);                                                    -- ⬜6 크레딧 자신의 체인만
  for v_l in
    select cl.id, cl.line_no, cl.po_line_id, cl.qty_ea, cl.unit_price, pr.sku, x.po_number
      from public.po_invoice_line cl join public.po_line pl on pl.id = cl.po_line_id join public.product pr on pr.id = pl.product_id join public.po x on x.id = pl.po_id
     where cl.po_invoice_id = p_credit_id and cl.line_kind = 'goods' and cl.credit_reason = 'price_difference' and cl.is_payable and cl.qty_ea > 0 and cl.unit_price > 0
     order by cl.line_no
  loop
    v_amt := round(v_l.qty_ea * v_l.unit_price * v_factor, 2);
    if v_amt = 0 then continue; end if;
    -- ⬜2 환율: 핀(그 PO 줄의 레이어를 세운 환율) · 레이어 수량 가중 · 섞이면 경고 · 핀 없으면 줄의 출처(크레딧 → 같은 통화 PO) + 경고(비기준통화만)
    select count(*) as n, count(distinct coalesce(k.exchange_rate, 1)) as n_fx, sum(y.qty) as q, sum(coalesce(k.exchange_rate, 1) * y.qty) / nullif(sum(y.qty), 0) as fx, min(k.exchange_rate_source) as src
      into v_px
      from public.po_receipt_cost k join public.po_receipt r on r.id = k.receipt_id join public.inv_layer y on y.doc_number = r.receipt_number and public.inv_po_line_of(y.line_ref) = k.po_line_id::text and y.origin_type = 'purchase'
     where k.po_line_id = v_l.po_line_id;
    if v_cur is not distinct from v_base then
      v_fx := null; v_fx_src := null;
    elsif coalesce(v_px.n, 0) > 0 then
      v_fx := v_px.fx; v_fx_src := 'pinned';
      if v_px.n_fx > 1 then v_warn := array_append(v_warn, 'credit_fx_mixed:' || v_l.line_no); end if;
    else
      select c.exchange_rate, c.exchange_rate_source, c.net_unit_cad into v_lc from public.po_invoice_line_cost(v_l.id) c;
      if v_lc.net_unit_cad is null then
        raise exception 'Credit note % line % (%) is in % but no exchange rate is known (no receipt yet, none on the credit note or the PO) — enter the rate on the credit note first — nothing was saved', v_c.invoice_number, v_l.line_no, v_l.sku, coalesce(v_cur, '?');
      end if;
      v_fx := v_lc.exchange_rate; v_fx_src := v_lc.exchange_rate_source;
      v_warn := array_append(v_warn, 'credit_fx_unpinned:' || v_l.line_no);
    end if;
    select coalesce(sum(rl.qty_ea), 0) into v_recv from public.po_receipt_line rl where rl.po_line_id = v_l.po_line_id;
    if v_l.qty_ea > v_recv then v_warn := array_append(v_warn, 'price_credit_qty_above_received:' || v_l.line_no); end if;      -- ⬜3 경고만
    insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, amount_doc, currency_id, exchange_rate, source_type, source_id, source_number, note, created_by, updated_by)
    values ('price_adjust', 'po_line', v_l.po_line_id, -v_amt * coalesce(v_fx, 1), -v_amt, v_c.currency_id, v_fx, 'po_credit', v_l.id, v_c.invoice_number,
            format('price difference credit %s line %s (%s · %s × %s × chain %s · fx %s)', v_c.invoice_number, v_l.line_no, v_l.sku, v_l.qty_ea, v_l.unit_price, v_factor, coalesce(v_fx_src, 'base')), v_staff, v_staff)
    returning id into v_id;
    v_j := null;
    if p_post then v_j := public.inv_layer_post_cost_adjust(v_id); end if;                                       -- 판정 391 · 399 거부는 예외로 올라간다
    v_events := v_events || jsonb_build_object('id', v_id, 'line_no', v_l.line_no, 'po_line_id', v_l.po_line_id, 'po_number', v_l.po_number, 'sku', v_l.sku, 'qty', v_l.qty_ea,
                                               'amount_doc', -v_amt, 'exchange_rate', v_fx, 'exchange_rate_source', v_fx_src, 'amount_cad', -v_amt * coalesce(v_fx, 1), 'received_qty', v_recv,
                                               'status', coalesce(v_j ->> 'status', 'pending'), 'layers', coalesce((v_j ->> 'layers')::int, 0), 'posted_cad', coalesce((v_j ->> 'posted_cad')::numeric, 0));
  end loop;
  return jsonb_build_object('credit_id', p_credit_id, 'credit_number', v_c.invoice_number, 'currency', v_cur, 'factor', v_factor, 'events', v_events, 'event_count', jsonb_array_length(v_events),
                            'posted', p_post, 'warnings', to_jsonb(v_warn), 'builder', c_version);
end;
$$;

-- ═══ 9) inv_layer_post_receipt_over 재발행 — 원본 20260920171930_po_receipt_over_settle.sql:275 바이트 + 1 줄(기준 레이어 — 묶음이 둘이면 핀이 같아 값은 같다 · order by id limit 1 그대로) ═══
create or replace function public.inv_layer_post_receipt_over(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security invoker
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

-- ═══ 10) inv_post_receipt_over 재발행 — 원본 20260920171930_po_receipt_over_settle.sql:160 바이트 + 1 줄(그 빈의 기준 행 합에 묶음 행도) ═══
create or replace function public.inv_post_receipt_over(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security invoker
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

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  if public.inv_po_line_of('abc:p1') <> 'abc' or public.inv_po_line_of('abc') <> 'abc' or public.inv_po_line_of('abc:p2:offpo') <> 'abc' then v_bad := v_bad || ' helper'; end if;
  if not exists (select 1 from pg_indexes where schemaname = 'public' and indexname = 'inv_layer_po_line_idx') then v_bad := v_bad || ' index'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('inv_layer_post_receipt', 'inv_layer_post_charge', 'inv_layer_post_cost_adjust', 'inv_layer_apply', 'inv_layer_apply_flush_adds', 'po_fx_cost_lines', 'po_credit_cost_events', 'inv_layer_post_receipt_over', 'inv_post_receipt_over')
     and p.prosrc ~ 'inv_po_line_of\(';
  if v_n <> 9 then v_bad := v_bad || format(' reissued-%s-of-9', v_n); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('inv_layer_post_receipt', 'inv_layer_post_charge', 'inv_layer_post_cost_adjust', 'inv_layer_apply', 'inv_layer_apply_flush_adds', 'po_fx_cost_lines', 'po_credit_cost_events', 'inv_layer_post_receipt_over', 'inv_post_receipt_over')
     and (p.prosrc ~ 'pl\.id::text = x\.line_ref' or p.prosrc ~ 'x\.line_ref = pl\.id::text' or p.prosrc ~ 'y\.line_ref = pl\.id::text' or p.prosrc ~ 'x\.line_ref::uuid' or p.prosrc ~ 'line_ref = v_j\.po_line_id::text' or p.prosrc ~ 'line_ref = v_adj\.po_line_id::text' or p.prosrc ~ 'y\.line_ref = v_d\.po_line_id::text' or p.prosrc ~ 'x\.line_ref = v_d\.po_line_id::text' or p.prosrc ~ 'y\.line_ref = k\.po_line_id::text');
  if v_n <> 0 then v_bad := v_bad || format(' old-compare-left-%s', v_n); end if;
  if (select prosrc from pg_proc where oid = 'public.inv_layer_apply(date)'::regprocedure) !~ 'kind = ''ims_rcv''' then v_bad := v_bad || ' apply-ims_rcv'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - rcv-1a did not land as designed:%s - nothing was changed', v_bad); end if;
end $$;
