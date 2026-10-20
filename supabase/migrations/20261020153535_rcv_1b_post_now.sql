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

-- ═══ rcv-1b — 입고 「먼저 반영」(판정 550 ~ 553 · rcv-0 회신 · rcv-1a 뒤 · 이견 1 ~ 17 · 2026-10-20) ═══
--   센 줄을 묶음(po_receipt_post · batch_no)으로 먼저 재고에 넣는다 — 입고 · PO 는 열린 채 · 원장 line_ref = po_line_id || ':p' || batch_no · occurred_on = received_on · 레이어 · 핀은 rcv-1a 창구 그대로(첫 묶음이 핀을 만들고 뒤가 읽는다)
--   마지막 확정(po_receipt_confirm_by)은 반영 안 된 작업 줄만 입고 줄로 · short · off_invoice 는 합으로 한 번 · 꼬리 없는 행 · 미룬 비용 ⓕ 가 다시 집는다
--   판정 553: 그 발주에 묶음이 있는 draft 입고가 있으면 비용을 얹지 않고 미룬다(inv_layer_post_charge 배분 줄 루프 · status deferred · posted_on 비움) — 세 길(po_charge_confirm · 확정 ⓕ · 재생성 flush_adds)이 같은 창구를 지난다
--   가드 ⑤: post_id 있는 작업 줄은 qty · bin · 삭제 · 병합 대상 모두 불가(여섯 함수 · 창고 셸은 _by 를 부르므로 함께 덮인다) · 유니크 (receipt_id, po_line_id, bin_id, post_key) — 반영 뒤 나머지를 같은 칸에 놓는다(이견 4 A)
--   재발행 13 = 마지막 정의 바이트 + 줄 몇 개: inv_layer_post_receipt(2) · inv_post_receipt(drop + 새 시그니처 p_post_id) · po_receipt_confirm_by · inv_layer_post_charge · po_charge_confirm(1) · po_receipt_over_bins · po_receipt_detail
--     · po_receipt_work_save_by · putaway_by · putaway_all_by · split · unassign · work_delete
--   무접촉: po_receipt_confirm(셸) · po_receipt_delete · wms_recv_*(po_receipt_line 수로 이미 거부) · po_doc_cancel · po_invoice_confirm(po_receipt 존재로 거부) · inv_layer_apply · flush_adds(미루기는 창구 안) · inv_layer_cost_add_settle(팔린 몫 cost_late 는 그대로)

-- ═══ 1) 묶음 표 po_receipt_post · 작업 줄 · 입고 줄에 post_id · 유니크 교체 ═══
create table public.po_receipt_post (
  id          uuid primary key default gen_random_uuid(),
  receipt_id  uuid not null references public.po_receipt(id),
  batch_no    int  not null check (batch_no >= 1),                     -- 입고 안에서 1, 2, … · 원장 꼬리 :p<batch_no>
  posted_by   uuid references public.ims_staff(id),
  posted_at   timestamptz not null default now(),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff(id),
  constraint po_receipt_post_batch_key unique (receipt_id, batch_no)
);
create index po_receipt_post_receipt_id_idx on public.po_receipt_post (receipt_id);
create index po_receipt_post_posted_by_idx on public.po_receipt_post (posted_by);
create index po_receipt_post_updated_by_idx on public.po_receipt_post (updated_by);
create trigger po_receipt_post_touch before update on public.po_receipt_post for each row execute function public.ims_touch();
alter table public.po_receipt_post enable row level security;
create policy po_receipt_post_select on public.po_receipt_post for select to authenticated using (true);
create policy po_receipt_post_insert on public.po_receipt_post for insert to authenticated with check ((select public.ims_can_write('receiving')));
create policy po_receipt_post_update on public.po_receipt_post for update to authenticated using ((select public.ims_can_write('receiving'))) with check ((select public.ims_can_write('receiving')));
create policy po_receipt_post_delete on public.po_receipt_post for delete to authenticated using ((select public.ims_can_write('receiving')));
comment on table public.po_receipt_post is 'rcv-1b(판정 550) — 입고의 「먼저 반영」 묶음: 센 작업 줄 몇 개를 마지막 확정 전에 재고로 넣은 사건 · batch_no 는 입고 안 1, 2, … · 원장 line_ref 꼬리 :p<batch_no> · 쓰는 길은 po_receipt_post_now 하나 · 지우지 않는다(원장 행이 가리킨다)';

alter table public.po_receipt_work add column post_id uuid references public.po_receipt_post(id);
alter table public.po_receipt_work add column post_key uuid generated always as (coalesce(post_id, '00000000-0000-0000-0000-000000000000'::uuid)) stored;   -- 이견 4 A: 유니크에 null 을 넣을 수 없어 0-uuid 로 접는다
create index po_receipt_work_post_id_idx on public.po_receipt_work (post_id);
alter table public.po_receipt_work drop constraint po_receipt_work_receipt_line_bin_key;
alter table public.po_receipt_work add constraint po_receipt_work_receipt_line_bin_post_key unique (receipt_id, po_line_id, bin_id, post_key);   -- 같은 라인 · 같은 칸 · 같은 묶음(또는 미반영)은 한 줄 — 반영한 줄 옆에 나머지를 같은 칸에 놓을 수 있다
comment on column public.po_receipt_work.post_id is 'rcv-1b — 이 줄을 먼저 재고에 넣은 묶음(po_receipt_post) · 있으면 줄은 얼린다(qty · bin · 삭제 · 병합 대상 불가 · 가드 ⑤) · 마지막 확정은 이 줄을 다시 입고 줄로 만들지 않는다';
alter table public.po_receipt_line add column post_id uuid references public.po_receipt_post(id);
create index po_receipt_line_post_id_idx on public.po_receipt_line (post_id);
comment on column public.po_receipt_line.post_id is 'rcv-1b — 먼저 반영 묶음이 만든 입고 줄(원장 :pN 행의 근거) · null = 마지막 확정이 만든 줄';

-- ═══ 2) inv_layer_post_receipt 재발행 — 원본 20261020143921_rcv_1a_receipt_line_ref_suffix.sql:48 바이트 + 2 줄(머리 검사) ═══
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

-- ═══ 3) inv_post_receipt 재발행 — 원본 20260929195458_inv_basis_2.sql:73 바이트 + 묶음 갈래(p_post_id) · 시그니처가 바뀌어 drop 뒤 create(1-인자 호출은 default 로 그대로) · 회수는 원래대로 ═══
drop function public.inv_post_receipt(uuid);
create function public.inv_post_receipt(p_receipt_id uuid, p_post_id uuid default null) returns jsonb
language plpgsql
volatile
security invoker                                              -- 이견 3 — definer 가 필요한 표가 없다
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
revoke all on function public.inv_post_receipt(uuid, uuid) from public, anon, authenticated;   -- 5-3b 의 회수 그대로(drop 으로 ACL 이 초기화된다)
grant execute on function public.inv_post_receipt(uuid, uuid) to service_role;
comment on function public.inv_post_receipt(uuid, uuid) is 'rcv-1b — 입고 원장 창구: p_post_id 없음 = 마지막 확정(confirmed · post_id 없는 입고 줄만 · 꼬리 없는 행 · off_invoice 상한 = 기준 − 먼저 반영 합) · p_post_id = 먼저 반영 묶음(draft · 그 묶음의 입고 줄만 · line_ref :p<batch_no> · 차이 없음) · 둘 다 occurred_on = received_on(묶음 뒤 날짜가 바뀌면 거부) · 레이어는 inv_layer_post_receipt 가 입고 단위로 접는다(핀은 첫 묶음)';

-- ═══ 4) po_receipt_confirm_by 재발행 — 원본 20261009002744_po_disc_3.sql:215 바이트 + 먼저 반영(ⓐ 반영 안 된 줄만 · ④ 안전띠 · posted_before) · 검사 ①④⑤⑥ 은 po_receipt_post_now_by 에 복사돼 있다(이견 5 · 두 집) ═══
create or replace function public.po_receipt_confirm_by(p_staff uuid, p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security definer                                              -- ⭐ 이견 1 — po·po_line·po_discount(purchasing RLS)에 쓴다. 권한은 첫머리 ims_require_write('receiving') 가 묻는다
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_pl        public.po_line%rowtype;
  v_base      text;
  v_max       text;
  v_a_num     text;
  v_b_num     text;
  v_b_id      uuid;
  v_n         int;
  v_free_txt  text;
  v_free_n    int;
  v_work_n    int;
  v_lines_n   int := 0;
  v_over      int := 0;
  v_short     int := 0;
  v_rem_total numeric := 0;
  v_reduced   int := 0;
  v_moved     int := 0;
  v_cleared   text[] := '{}';
  v_warn      text[] := '{}';
  v_rows      jsonb := '[]'::jsonb;
  v_now       timestamptz := now();
  v_ledger    jsonb;                                           -- ⓔ 원장 창구의 반환(원장 이식 2차 · 2026-09-19)
  v_cur       text;                                            -- ⑥ 환율 게이트(원가 이식 1차 · 2026-09-19) — 발주 통화 코드
  v_base_cur  text;                                            -- ⑥ 기준통화 코드 · ⚠️ v_base(접미사를 뗀 PO 번호 · 잠금·채번)와 다른 것 — 이름을 같이 쓰면 채번이 CADa 가 된다(2026-09-19 실사고)
  x           record;
  v_ob_n      int;                                             -- inv-basis-3: 초과분이 놓인 칸 수 · 칸 · 놓은 사람 · 문장용
  v_ob_bin    uuid;
  v_ob_by     uuid;
  v_ob_txt    text;
  v_cj        jsonb;                                           -- inv-basis-3 · 판정 94(⑯): 입고 순간 비용 얹기의 반환 · 얹은 것 · 오류
  v_cpost     jsonb := '[]'::jsonb;
  v_cerr      jsonb := '[]'::jsonb;
  v_aj        jsonb;                                           -- po-disc-3 · 판정 391: 보류 원가 조정 얹기의 반환
  v_apost     jsonb := '[]'::jsonb;
  v_aerr      jsonb := '[]'::jsonb;
  v_work_np   int;                                             -- rcv-1b: 먼저 반영 안 된 작업 줄 수(ⓐ 는 이것만 입고 줄로)
  v_pb_n      int := 0;  v_pb_q numeric := 0;  v_pb_r int := 0;   -- rcv-1b: posted_before(묶음 수 · 수량 · 줄 수)
begin
  if p_staff is null then raise exception 'po_receipt_confirm_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — it is confirmed by the warehouse Complete, not here — nothing was saved', v_r.receipt_number; end if;   -- tr-3a 판정 70(트랜스퍼를 막는 한 줄만)
  -- ① 이미 확정·취소
  if v_r.confirmed_at is not null or v_r.status = 'confirmed' then
    raise exception 'Receipt % was already confirmed on % — nothing was saved', v_r.receipt_number, to_char(v_r.confirmed_at, 'YYYY-MM-DD');
  end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — only a draft receipt can be confirmed — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  -- ⭐ 잠금 — PO 단위(형제 채번·분할·닫기 · 키는 접미사를 뗀 base) + 라인 단위(작업 줄 RPC 들과 같은 키 · 세는 중인 손을 줄 세운다)
  v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('po:' || v_base));
  for x in select pl.id from public.po_line pl where pl.po_id = v_po.id loop
    perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || x.id::text));
  end loop;
  -- ④ 잠금 뒤 다시 본다 — 그 사이 닫혔거나 취소됐을 수 있다
  select * into v_po from public.po where id = v_r.po_id;
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — a receipt can be confirmed only on a confirmed order — nothing was saved', v_po.po_number, v_po.status;
  end if;
  -- inv-basis-2 · 판정 88 ③ · 92 — 확정 인보이스가 없는 PO 는 받지 않는다(입고 문에서 이미 막지만, 옛 초안 · 직접 호출도 여기서 한 번 더)
  if not exists (select 1 from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id join public.po_line pl on pl.id = il.po_line_id
                  where pl.po_id = v_po.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed') then
    raise exception 'PO % has no confirmed invoice — the office confirms the supplier invoice first (Purchase Invoices), then the receipt can be confirmed — nothing was saved', v_po.po_number;
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;                     -- 잠금 뒤 다시(남이 사이에 확정했을 수 있다)
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % was changed by someone else just now (% ) — reload and try again — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  -- ③ 작업 줄이 없다
  select count(*) into v_work_n from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  if v_work_n = 0 then
    raise exception 'Receipt % has nothing counted — count at least one line before confirming, or delete the receipt — nothing was saved', v_r.receipt_number;
  end if;
  -- rcv-1b(판정 550): 먼저 반영된 작업 줄 · 묶음 — ⓐ 는 반영 안 된 줄만 입고 줄로(전량 반영이면 0 줄) · ⓑ counted 는 전부(short · off_invoice 는 합으로 한 번)
  select count(*), coalesce(sum(w.qty_ea), 0) into v_pb_r, v_pb_q from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.post_id is not null;
  select count(*) into v_pb_n from public.po_receipt_post p where p.receipt_id = p_receipt_id;
  v_work_np := v_work_n - v_pb_r;
  -- ②⭐⭐ 빈 없는 줄 — 라인·수량을 문장에 · 빠져나갈 길을 함께
  select count(*), string_agg(format('line %s (%s) %s EA', t.line_no, t.sku, t.qty_ea), ', ' order by t.line_no)
    into v_free_n, v_free_txt
  from (select pl.line_no, pr.sku, w.qty_ea
          from public.po_receipt_work w join public.po_line pl on pl.id = w.po_line_id join public.product pr on pr.id = pl.product_id
         where w.receipt_id = p_receipt_id and w.bin_id is null) t;
  if v_free_n > 0 then
    raise exception 'Receipt % cannot be confirmed — % row(s) still have no bin: %. Put them away first, or lower the count to what you actually placed — the rest stays on the order — nothing was saved',
      v_r.receipt_number, v_free_n, v_free_txt;
  end if;
  -- ⑤ 더 막는 것 — 빈이 그 사이 다른 창고 것·비활성으로 바뀌었나(배정 때 봤지만 확정은 장부에 닿는다 · 한 번 더)
  select count(*) into v_n
  from public.po_receipt_work w join public.ref_bin b on b.id = w.bin_id
  where w.receipt_id = p_receipt_id and (b.warehouse_id <> v_r.warehouse_id or not b.is_active);
  if v_n > 0 then
    raise exception 'Receipt % has % row(s) in a bin that is inactive or not in this receipt''s warehouse — move them to another bin first — nothing was saved', v_r.receipt_number, v_n;
  end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 발주인데 환율이 없거나 0 이면 **확정 자체를 거부**한다(Caleb 2026-09-19 · 원가가 조용히 틀리는 것보다 낫다 · 정본 「0 금지」).
  --   기준통화는 inv_config.base_currency(박지 않는다) · 발주 통화는 po.currency_id → ref_currency.code.
  --   ⚠️ po.exchange_rate 는 **CAD per USD** 다(Cin7 「CAD units per USD」 · 화면 칸 「CAD per USD」) — unit_price × exchange_rate = CAD. 곱한다 · 나누지 않는다.
  --   문장이 어디서 고치는지 말한다 — 발주 머리의 「Exchange rate (CAD per USD)」 칸 · 확정 뒤에도 열려 있다(po.html HEAD_ALWAYS).
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — nothing was saved'; end if;
  if v_cur is distinct from v_base_cur and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
    raise exception 'PO % is in % but has no % per % exchange rate — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and confirm again — nothing was saved',
      v_po.po_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
  end if;

  -- ═══ ⓐ 작업 줄 → 입고 줄 (1:1 · received_on 은 묶음의 것 · received_by 는 놓은 사람 → 센 사람 → 확정한 사람 · 초과분도 그대로) ═══
  insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, note, receipt_id)
  select w.po_line_id, v_r.received_on, coalesce(w.putaway_by, w.counted_by, v_staff), w.bin_id, w.qty_ea, w.note, v_r.id
  from public.po_receipt_work w
  where w.receipt_id = p_receipt_id and w.post_id is null                                       -- rcv-1b: 먼저 반영된 줄은 묶음이 이미 입고 줄(post_id)로 만들었다
  order by w.po_line_id, w.created_at;
  get diagnostics v_lines_n = row_count;
  if v_lines_n <> v_work_np then
    raise exception 'Receipt %: % work row(s) but % receipt line(s) were written — nothing was saved', v_r.receipt_number, v_work_np, v_lines_n;
  end if;

  -- ═══ ⓑ 차이 — over · short · 안 센 라인은 short(received 0) · ⭐ inv-basis-2 · 판정 88 ② · 93 ⓑ: 기준 = 확정 인보이스 goods 합(크레딧 · 초안 제외) − 앞선 입고 합(PO 수량이 아니다) ═══
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pl.qty_ea as ordered,
           coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                      where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0)
             - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as expected,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as counted,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id and w.post_id is not null), 0) as posted   -- rcv-1b
    from public.po_line pl join public.product pr on pr.id = pl.product_id
    where pl.po_id = v_po.id
    order by pl.line_no
  loop
    if x.posted > x.counted then                                                                 -- rcv-1b(④ 안전띠 — 가드 ⑤ 가 먼저 막아 보통 오지 않는다)
      raise exception 'Line % (%) on %: % EA are already in stock from post-now, but only % are counted — fix it with a stock adjustment (Adjustments), then confirm — nothing was saved', x.line_no, x.sku, v_r.receipt_number, x.posted, x.counted;
    end if;
    if x.counted > x.expected then
      -- ⭐ inv-basis-3 · 판정 88 ⑧ · 93 ⓓ: 더 온 것(인보이스 초과 · 인보이스에 없는 줄)은 off_invoice 한 행 — 창고가 놓은 칸을 행에 남긴다(판정 43 · 어느 칸에 얼마).
      --   초과분이 놓인 칸 = 원장 창구 inv_post_receipt 와 같은 자르기(큰 칸부터 · 칸 이름 · 상한 = 기준)로 정한다 · 두 칸에 걸치면 막는다(판정 92 · off-PO 와 같이 한 물건 한 칸 · 나눠 놓기 없음).
      select b.bins, b.bin_id, b.placed_by, b.bins_txt into v_ob_n, v_ob_bin, v_ob_by, v_ob_txt
        from public.po_receipt_over_bins(p_receipt_id, x.po_line_id, x.expected) b;   -- 판정 100: 자르기 식은 속 함수 한 곳 — 창고 Complete 가 먼저 막고 여기는 안전띠(칸 0 = 칸 없는 줄은 위 ② 가 먼저 막는다)
      if coalesce(v_ob_n, 0) <> 1 then
        raise exception 'Line % (%) on %: % EA more than the confirmed invoice (% counted · % invoiced) sit in more than one bin (%) — move the extra into one bin, or lower the count, so the office can decide it as one off-invoice item — nothing was saved',
          x.line_no, x.sku, v_r.receipt_number, x.counted - greatest(x.expected, 0), x.counted, greatest(x.expected, 0), coalesce(v_ob_txt, '?');
      end if;
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty, note, bin_id, placed_by, placed_at, updated_by)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, 'off_invoice', greatest(x.expected, 0), x.counted,
              'off-invoice (receipt confirm) — more than the confirmed invoice · decision pending', v_ob_bin, coalesce(v_ob_by, v_staff), v_now, v_staff);
      v_over := v_over + 1;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'off_invoice', 'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    elsif x.counted <> x.expected then
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, 'short', greatest(x.expected, 0), x.counted);
      v_short := v_short + 1;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'short', 'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    end if;
    if x.expected - x.counted > 0 then v_rem_total := v_rem_total + (x.expected - x.counted); end if;
  end loop;

  -- ═══ ⓒ 닫기 — inv-basis-2 · 판정 88 ⑤ ⑥: 입고 확정은 더 이상 가르지 않는다(가르는 자리는 인보이스 확정 · po_invoice_confirm) · 덜 받은 몫은 short 차이로 남고 크레딧은 오피스 단추 · PO 는 닫힌다(입고 종료 · §11-b) ═══
  v_a_num := v_po.po_number;
  update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
  v_warn := array_append(v_warn, 'po_closed');
  if v_over > 0 then v_warn := array_append(v_warn, 'over_receipt'); v_warn := array_append(v_warn, 'off_invoice'); end if;   -- inv-basis-3: 옛 경고 이름은 모양 무변 · 새 어휘도 함께
  if v_short > 0 then v_warn := array_append(v_warn, 'short_receipt'); end if;

  -- ═══ ⓓ 묶음 confirmed (맨 뒤 — 어디서 터져도 아무것도 안 남는다) ═══
  update public.po_receipt set status = 'confirmed', confirmed_at = v_now, confirmed_by = v_staff
   where id = p_receipt_id and status = 'draft' and confirmed_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not saved — it may have been changed by someone else just now — nothing was saved', v_r.receipt_number; end if;

  -- ═══ ⓔ 원장 — 창구를 부른다 (원장 이식 2차 · 2026-09-19 · ⬜1) ═══
  -- ⭐ 같은 트랜잭션 — 원장이 실패하면 확정도 실패한다(재고에 안 잡힐 거면 확정도 하면 안 된다). inv_ledger 에 직접 쓰지 않는다(원칙 2 · §11-j).
  -- ⭐ 자리가 ⓓ 뒤인 이유 셋: ① 창구는 「확정된 입고」만 받는다(status=confirmed 를 스스로 확인 — 직접 호출로 초안이 장부에 닿는 길을 막는다)
  --   ② raw 의 po_number 는 갈라진 뒤의 번호여야 한다(§11-j) — ⓒ 가 끝나야 안다 ③ 기준은 po_line.qty_ea 가 아니라 ⓑ 가 얼려 둔 po_receipt_diff.expected_qty 에서
  --   읽으므로(§2 의 함정 — ⓒ 가 qty_ea 를 줄인다) ⓒ 뒤라도 어긋나지 않는다. 기준을 「미리 잡아 두는」 그릇이 그 표다.
  v_ledger := public.inv_post_receipt(p_receipt_id);
  if coalesce((v_ledger->>'qty_excess')::numeric, 0) > 0 then v_warn := array_append(v_warn, 'ledger_trimmed_to_basis'); end if;
  if (v_ledger->'warnings') ? 'received_on_before_baseline' then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;

  -- ═══ ⓕ inv-basis-3 · 판정 94(⑯): 입고 전에 확정해 둔 이 발주의 비용은 지금 원가에 얹는다 — 배분 줄 단위 멱등(창구가 건너뛴다) · 오류는 경고로 모아 돌려준다(확정을 막지 않는다 · tf_arrive 판정 78 모양) ═══
  for x in select distinct c.id, c.charge_number from public.po_charge c join public.po_charge_alloc a on a.po_charge_id = c.id
            where a.po_id = v_po.id and c.status = 'confirmed' and c.confirmed_at is not null
              and not exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text)
            order by c.charge_number loop
    begin
      v_cj := public.inv_layer_post_charge(x.id);
      v_cpost := v_cpost || jsonb_build_object('charge_id', x.id, 'charge_number', x.charge_number, 'layers_touched', v_cj -> 'layers_touched', 'amount_posted_cad', v_cj -> 'amount_posted_cad', 'warnings', v_cj -> 'warnings');
    exception when others then
      v_cerr := v_cerr || jsonb_build_object('charge_id', x.id, 'charge_number', x.charge_number, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  if jsonb_array_length(v_cerr) > 0 then v_warn := array_append(v_warn, 'charge_errors'); end if;

  -- ═══ ⓖ po-disc-3 · 판정 391: 레이어가 없어 보류됐던 원가 조정(이 PO 의 줄 · 이 PO 의 비용 배분 줄)을 지금 얹는다 — ⓕ 비용 뒤(둘 다 금액만 얹어 총액은 순서와 무관 · 재생성 쏟기도 비용 뒤) · 오류는 경고로(확정을 막지 않는다) ═══
  for x in select j.id, j.source_number from public.inv_cost_adjust j
            where j.status = 'pending'
              and ((j.target_type = 'po_line' and exists (select 1 from public.po_line pl where pl.id = j.po_line_id and pl.po_id = v_po.id))
                or (j.target_type = 'charge_alloc' and exists (select 1 from public.po_charge_alloc a where a.id = j.po_charge_alloc_id and a.po_id = v_po.id)))
            order by j.created_at, j.source_number, j.reverses_id nulls first, j.id loop                       -- 원래 사건 뒤에 그 되돌림(같은 트랜잭션은 created_at 이 같다)
    begin
      v_aj := public.inv_layer_post_cost_adjust(x.id);
      v_apost := v_apost || jsonb_build_object('adjust_id', x.id, 'source_number', x.source_number, 'status', v_aj ->> 'status', 'posted_cad', v_aj -> 'posted_cad', 'layers', v_aj -> 'layers');
    exception when others then
      v_aerr := v_aerr || jsonb_build_object('adjust_id', x.id, 'source_number', x.source_number, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  if jsonb_array_length(v_aerr) > 0 then v_warn := array_append(v_warn, 'adjust_errors'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'posted_before', jsonb_build_object('batches', v_pb_n, 'qty', v_pb_q, 'rows', v_pb_r),   -- rcv-1b: 먼저 반영된 묶음 · 수량 · 줄
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', 'closed', 'closed_at', v_now),
    'split', null,                                               -- inv-basis-2: 입고 확정은 가르지 않는다(키는 모양 무변 · 값은 늘 null · 덜 받은 몫은 diffs.short)
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'charges', jsonb_build_object('posted', v_cpost, 'errors', v_cerr),   -- inv-basis-3 · 판정 94(⑯): 이 발주의 확정 비용을 입고 순간 얹은 결과
    'adjustments', jsonb_build_object('posted', v_apost, 'errors', v_aerr),   -- po-disc-3 · 판정 391: 보류 원가 조정을 입고 순간 얹은 결과
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 5) inv_layer_post_charge 재발행 — 원본 20261020143921_rcv_1a_receipt_line_ref_suffix.sql:241(rcv-1a) 바이트 + 미루기(판정 553) ═══
create or replace function public.inv_layer_post_charge(p_charge_id uuid, p_on date default null, p_alloc uuid default null) returns jsonb
language plpgsql
volatile
security invoker
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

-- ═══ 6) po_charge_confirm 재발행 — 원본 20261008174126_po_tax_2.sql:308 바이트 + 경고 1 줄 ═══
create or replace function public.po_charge_confirm(p_charge_id uuid, p_confirm boolean default true) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_doc   text;                                                 -- ②-b: 0행 문장용(returning 이 v_chg 를 null 로 덮는다)
  v_staff uuid;
  v_chg   public.po_charge%rowtype;
  v_m     record;
  v_n     int;
  v_txt   text;
  v_warn  text[] := '{}';
  v_cost  jsonb;                                                -- 원가 창구의 반환(원가 이식 2차 · 2026-09-19)
  v_cur   text;                                                 -- ⑥ 환율 게이트 — 청구 통화 코드
  v_base_cur text;                                              -- ⑥ 기준통화 코드(inv_config.base_currency) · ⚠️ 원문에 같은 이름 없음 확인(2026-09-19 v_base 실사고)
  v_rate  numeric;                                              -- po-tax-2 · 제안 규칙 세율(경고용)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  v_doc := 'Charge ' || v_chg.charge_number;
  select * into v_m from public.po_charge_money where id = p_charge_id;

  if p_confirm then
    if v_chg.status = 'confirmed' then raise exception 'Charge % is already confirmed — nothing was saved', v_chg.charge_number; end if;
    if v_chg.status = 'cancelled' then raise exception 'Charge % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_chg.charge_number; end if;
    select count(*) into v_n from public.po_charge_alloc where po_charge_id = p_charge_id;
    if v_n = 0 then raise exception 'Charge % has no allocation lines — nothing to put on cost — nothing was saved', v_chg.charge_number; end if;
    -- ⭐⭐ 거부(경고 아님) — 양쪽 다 우리가 넣는 숫자라 안 맞으면 덜 입력한 것(⑤)
    if v_m.unallocated <> 0 then
      raise exception 'Charge % is not fully allocated — total % · allocated % · unallocated % — fix the allocations (or press Spread) first — nothing was saved',
        v_chg.charge_number, v_m.total_amount, v_m.alloc_sum, v_m.unallocated;
    end if;
    if v_chg.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;
    select r.rate_pct into v_rate from public.ref_tax_rule r where r.id = v_chg.tax_rule_id;                 -- po-tax-2
    if coalesce(v_rate, 0) > 0 and v_chg.tax_amount = 0 then v_warn := array_append(v_warn, 'tax_amount_zero_with_rate'); end if;   -- po-tax-2 · 막지 않는다(세금은 낼 돈만 · 원가 무관)
    if exists (select 1 from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = p_charge_id and x.status = 'cancelled') then
      v_warn := array_append(v_warn, 'alloc_on_cancelled_po');
    end if;
    -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 비용인데 환율이 없거나 0 이면 확정 거부(입고와 같은 이유 · 원가가 조용히 틀리는 것보다 낫다 · 원가 이식 2차 2026-09-19)
    --   ⚠️ po_charge.exchange_rate 는 CAD per USD 다 — amount × exchange_rate = CAD. 곱한다 · 나누지 않는다(계산은 inv_layer_post_charge 에서).
    select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
    select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
    if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which charges need an exchange rate — nothing was saved'; end if;
    if v_cur is distinct from v_base_cur and (v_chg.exchange_rate is null or v_chg.exchange_rate <= 0) then
      raise exception 'Charge % is in % but has no % per % exchange rate — the cost cannot be put on stock without it. Enter the rate on the charge ("Exchange rate") and confirm again — nothing was saved',
        v_chg.charge_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
    end if;
    update public.po_charge set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    -- ⭐ 원가 — 같은 트랜잭션으로 레이어에 얹는다(원장 이식 2차의 ⓔ 와 같은 판단 · 원칙 2 「안에 있는 것끼리는 창구를 부른다」 · 하나가 실패하면 확정도 실패)
    v_cost := public.inv_layer_post_charge(p_charge_id);
    if coalesce((v_cost->>'no_layers_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_not_on_stock_no_receipt_yet'); end if;   -- 입고가 없는 발주 — 나중에 백필(inv_layer_post_charge 재호출)
    if coalesce((v_cost->>'no_basis_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_dropped_no_basis'); end if;                 -- 정본 D — 기준 0 은 버린다
    if coalesce((v_cost->>'deferred_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_deferred_post_now'); end if;                -- rcv-1b(판정 553) — 먼저 반영 묶음이 있는 draft 입고 · 마지막 확정 때 얹힌다
  else
    if v_chg.status <> 'confirmed' then raise exception 'Charge % is % — only a confirmed document can be reopened — nothing was saved', v_chg.charge_number, v_chg.status; end if;
    -- ⭐ po_invoice_confirm Reopen · po_doc_cancel 과 같은 선 — 결제 참조번호·금액을 이름으로
    if v_m.paid > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_charge_id = p_charge_id;
      raise exception 'Charge % has payments applied (%) — cannot reopen while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
    end if;
    -- ⭐ [원가 이식 2차] landed 가 이미 레이어에 얹혔으면 되돌리지 않는다 — 원가는 append-only. 되돌려 배분을 고치고 다시 확정해도 멱등이 건너뛰어 옛 금액이 남는다.
    select count(*) into v_n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number;
    if v_n > 0 then
      raise exception 'Charge % has already been added to stock cost (% layer row(s)) — it cannot be reopened; to correct it, enter an offsetting charge — nothing was saved', v_chg.charge_number, v_n;
    end if;
    update public.po_charge set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
  end if;

  return jsonb_build_object(
    'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status, 'confirmed_at', v_chg.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'paid', v_m.paid, 'unpaid', v_m.unpaid, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated,
                                'tax_amount', v_m.tax_amount, 'total_with_tax', v_m.total_with_tax),         -- po-tax-2
    'cost', v_cost,                                                                              -- ⭐ 원가 결과(layers_touched · amount_posted_cad · no_layers · no_basis · allocs[]) · 되돌리기면 null
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 7) po_receipt_over_bins 재발행 — 원본 20260929195458_inv_basis_2.sql:215 바이트 + 상한 = 기준 − 먼저 반영 합 · 반영 줄 제외(이견 3 · confirm_by ⓑ 와 창고 Complete 둘 다 따라온다) ═══
create or replace function public.po_receipt_over_bins(p_receipt_id uuid, p_po_line_id uuid, p_expected numeric)
  returns table(bins int, bin_id uuid, placed_by uuid, bins_txt text)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with cap as (                                                                                      -- rcv-1b(이견 3): 먼저 반영된 줄(post_id)은 이미 재고 — 상한에서 먼저 빼고 자르기에서 뺀다
    select greatest(greatest(p_expected, 0) - coalesce((select sum(q.qty_ea) from public.po_receipt_work q where q.receipt_id = p_receipt_id and q.po_line_id = p_po_line_id and q.post_id is not null), 0), 0) as v
  )
  select count(distinct t.bin_id)::int, min(t.bin_id::text)::uuid, min(t.putaway_by::text)::uuid,
         string_agg(t.bin || ' ' || (t.cum - greatest(t.cum - t.qty_ea, cap.v)) || ' EA', ', ' order by t.bin)
    from cap, (select w.bin_id, w.qty_ea, w.putaway_by, rb.name as bin, sum(w.qty_ea) over (order by w.qty_ea desc, rb.name, w.id) as cum
            from public.po_receipt_work w join public.ref_bin rb on rb.id = w.bin_id
           where w.receipt_id = p_receipt_id and w.po_line_id = p_po_line_id and w.post_id is null) t
   where t.cum > cap.v;
$$;

-- ═══ 8) po_receipt_detail 재발행 — 원본 20260929195458_inv_basis_2.sql:2336 바이트 + 열쇠 추가(lines[].posted · postable_rows · work[].post_id · batch_no · header.posts[] · post_now_ok · totals.posted · posted_batches · warnings posted_before) · 기존 모양 무변 ═══
create or replace function public.po_receipt_detail(p_receipt_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with r as (
  select * from public.po_receipt where id = p_receipt_id
),
w as (
  select k.*, b.name as bin, b.zone, pp.batch_no,                                                   -- rcv-1b: 묶음 번호(post_id 가 있으면)
         (select s.name from public.ims_staff s where s.id = k.counted_by) as counted_by_name,     -- ⚠️ 별칭 — ims_staff 자기 칸과 헷갈리지 않게
         (select s.name from public.ims_staff s where s.id = k.putaway_by) as putaway_by_name,
         (select s.name from public.ims_staff s where s.id = k.updated_by) as updated_by_name
  from public.po_receipt_work k
  left join public.ref_bin b on b.id = k.bin_id
  left join public.po_receipt_post pp on pp.id = k.post_id                                          -- rcv-1b
  where k.receipt_id = p_receipt_id
),
rl as (
  select l.*, b.name as bin, b.zone, pl.line_no,
         (select s.name from public.ims_staff s where s.id = l.received_by) as received_by_name
  from public.po_receipt_line l
  join public.po_line pl on pl.id = l.po_line_id
  left join public.ref_bin b on b.id = l.bin_id
  where l.receipt_id = p_receipt_id
),
lines as (
  select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pr.name as product_name, pl.supplier_sku, pl.qty_ea as ordered,
         pl.entered_unit_product_id, pl.entered_qty, pl.entered_pack_factor,
         coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                    where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0) as invoiced,
         coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as received_before,
         coalesce((select sum(y.qty_ea) from rl y where y.po_line_id = pl.id), 0) as received_here,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id), 0) as counted,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.bin_id is not null), 0) as allocated,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.putaway_done), 0) as placed,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.post_id is not null), 0) as posted,                      -- rcv-1b: 먼저 반영된 수량
         (select count(*) from w x where x.po_line_id = pl.id and x.bin_id is not null and x.post_id is null)::int as postable_rows        -- rcv-1b: 칸이 붙고 아직 반영 안 된 줄 수
  from r
  join public.po_line pl on pl.po_id = r.po_id
  join public.product pr on pr.id = pl.product_id
),
fm as (                                                     -- 형제 문서 — 뿌리에서 내려온 전부 · 자기 자신 포함 · 분할이 없었으면 하나(차이 닫기 차수 2026-09-19)
  select * from public.po_family_members((select po_id from r))
),
fam as (                                                    -- 형제 합계 · 제품 단위 — ⭐ 계산은 DB 가 한다(화면이 형제를 찾아 더하지 않는다)
  select * from public.po_family_lines((select po_id from r))
)
select case when not exists (select 1 from r) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', r.id, 'receipt_number', r.receipt_number, 'status', r.status, 'received_on', r.received_on,
      'po_id', r.po_id, 'po_number', p.po_number, 'po_status', p.status, 'po_closed_at', p.closed_at,
      'po_split_from_number', sf.po_number,
      'po_split_to', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'po_number', c.po_number, 'status', c.status) order by c.po_number) from public.po c where c.split_from_id = p.id), '[]'::jsonb),
      'po_family', jsonb_build_object(                                                                      -- ⭐ 형제 문서 합계(문서 단위 · 2026-09-19) — 「12 중 12 · 다 받음」의 근거
        'root_number', (select m.po_number from fm m order by m.depth, m.po_number limit 1),
        'members', coalesce((select jsonb_agg(jsonb_build_object('id', m.po_id, 'po_number', m.po_number, 'status', m.status, 'closed_at', m.closed_at, 'is_this', m.is_self) order by m.po_number) from fm m), '[]'::jsonb),
        'ordered_total',  (select coalesce(sum(f.ordered_total), 0)  from fam f),
        'received_total', (select coalesce(sum(f.received_total), 0) from fam f),
        'still_owed',     (select coalesce(sum(f.still_owed), 0)     from fam f)),
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'warehouse_id', r.warehouse_id, 'warehouse_name', wh.name,
      'created_by', r.created_by, 'created_by_name', cb.name,
      'confirmed_at', r.confirmed_at, 'confirmed_by_name', fb.name,
      'cancelled_at', r.cancelled_at, 'cancelled_by_name', xb.name,
      'note', r.note, 'created_at', r.created_at, 'updated_at', r.updated_at, 'updated_by_name', ub.name,
      'posts', coalesce((select jsonb_agg(jsonb_build_object('id', q.id, 'batch_no', q.batch_no, 'posted_by', q.posted_by, 'posted_by_name', (select s.name from public.ims_staff s where s.id = q.posted_by), 'posted_at', q.posted_at,
                                                             'qty_ea', (select coalesce(sum(x.qty_ea), 0) from w x where x.post_id = q.id), 'rows', (select count(*) from w x where x.post_id = q.id)) order by q.batch_no)
                         from public.po_receipt_post q where q.receipt_id = r.id), '[]'::jsonb),                                           -- rcv-1b: 묶음 목록(번호 · 누가 · 언제 · 수량 · 줄)
      'post_now_ok', (r.status = 'draft' and r.transfer_id is null and p.status = 'confirmed'
                      and exists (select 1 from w x where x.bin_id is not null and x.post_id is null)
                      and exists (select 1 from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id join public.po_line pl on pl.id = il.po_line_id
                                   where pl.po_id = r.po_id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed')))   -- rcv-1b: 화면이 단추를 그리는 근거(문은 창구가 다시 본다)
    from r
    join public.po p on p.id = r.po_id
    join public.supplier s on s.id = p.supplier_id
    join public.ref_warehouse wh on wh.id = r.warehouse_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = r.created_by
    left join public.ims_staff fb on fb.id = r.confirmed_by
    left join public.ims_staff xb on xb.id = r.cancelled_by
    left join public.ims_staff ub on ub.id = r.updated_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'po_line_id', l.po_line_id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', l.product_name, 'supplier_sku', l.supplier_sku,
      'entered_unit_product_id', l.entered_unit_product_id, 'entered_qty', l.entered_qty, 'entered_pack_factor', l.entered_pack_factor,
      'ordered', l.ordered, 'invoiced', l.invoiced, 'received_before', l.received_before, 'received_here', l.received_here,
      'remaining', l.ordered - l.received_before,
      'expected', l.invoiced - l.received_before,                                                             -- inv-basis-2 · 판정 88 ②: 이 문서에서 받을 기준 = 확정 인보이스 − 앞선 입고(화면 ⑱-3 · ⑱-4 가 읽는다) · remaining 은 뜻 · 이름 그대로
      'counted', l.counted, 'allocated', l.allocated, 'unallocated', l.counted - l.allocated, 'placed', l.placed,
      'posted', l.posted, 'postable_rows', l.postable_rows,                                                  -- rcv-1b
      'over', (l.counted > l.invoiced - l.received_before),                                                   -- inv-basis-2: over 도 같은 기준(화면은 diffs.kind 를 쓴다 · 이 키를 읽는 화면 0 · 2026-09-29 grep)
      'family', (select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members, 'fragments', f.fragments)
                 from fam f where f.product_id = l.product_id),                                              -- 형제 합계(제품 단위 · 2026-09-19) — 조각은 fragments[]
      'work', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', x.id, 'qty_ea', x.qty_ea, 'bin_id', x.bin_id, 'bin', x.bin, 'zone', x.zone, 'putaway_done', x.putaway_done,
          'count_method', x.count_method, 'counted_by', x.counted_by, 'counted_by_name', x.counted_by_name, 'counted_at', x.counted_at,
          'putaway_by', x.putaway_by, 'putaway_by_name', x.putaway_by_name, 'putaway_at', x.putaway_at,
          'note', x.note, 'updated_at', x.updated_at, 'updated_by_name', x.updated_by_name,
          'post_id', x.post_id, 'batch_no', x.batch_no)                                                    -- rcv-1b: 반영된 줄(얼림) · 묶음 번호
          order by x.bin_id nulls first, x.created_at)
        from w x where x.po_line_id = l.po_line_id), '[]'::jsonb))
      order by l.line_no)
    from lines l), '[]'::jsonb),
  'receipt_lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', y.id, 'po_line_id', y.po_line_id, 'line_no', y.line_no, 'qty_ea', y.qty_ea, 'bin_id', y.bin_id, 'bin', y.bin, 'zone', y.zone,
      'received_on', y.received_on, 'received_by', y.received_by, 'received_by_name', y.received_by_name, 'note', y.note, 'created_at', y.created_at)
      order by y.line_no, y.bin)
    from rl y), '[]'::jsonb),
  'diffs', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id, 'kind', d.kind, 'po_line_id', d.po_line_id, 'line_no', pl.line_no, 'sku', pr.sku,
      'expected_qty', d.expected_qty, 'received_qty', d.received_qty, 'diff_qty', d.received_qty - d.expected_qty,
      'note', d.note, 'resolved_at', d.resolved_at, 'resolved_by', d.resolved_by, 'resolved_by_name', rb.name,      -- rb = 별칭 서브쿼리(ims_staff 자기 칸과 헷갈리지 않게)
      'resolution', d.resolution, 'resolution_note', d.resolution_note,                                              -- 닫은 이유(차이 닫기 차수 2026-09-19)
      'product_id', d.product_id, 'bin_id', d.bin_id, 'bin', db.name, 'placed_by', d.placed_by, 'placed_by_name', pb.name, 'placed_at', d.placed_at,   -- ⑤-6c1 off-PO 칸(off_po 아니면 null)
      'unit_price', d.unit_price, 'removed_by', d.removed_by, 'removed_by_name', rmb.name, 'removed_at', d.removed_at,
      'family', (select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members, 'fragments', f.fragments)
                 from fam f where f.product_id = d.product_id))                                              -- ⭐ 닫을 때 「결국 다 받았나」가 여기 있다
      order by pl.line_no)
    from public.po_receipt_diff d
    left join public.po_line pl on pl.id = d.po_line_id
    join public.product pr on pr.id = d.product_id
    left join public.ims_staff rb on rb.id = d.resolved_by
    left join public.ref_bin db on db.id = d.bin_id                                                          -- ⑤-6c1
    left join public.ims_staff pb on pb.id = d.placed_by
    left join public.ims_staff rmb on rmb.id = d.removed_by
    where d.receipt_id = p_receipt_id), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'lines', count(*), 'counted_lines', count(*) filter (where l.counted > 0),
      'ordered', coalesce(sum(l.ordered), 0), 'remaining', coalesce(sum(l.ordered - l.received_before), 0),
      'counted', coalesce(sum(l.counted), 0), 'allocated', coalesce(sum(l.allocated), 0), 'placed', coalesce(sum(l.placed), 0),
      'received_here', coalesce(sum(l.received_here), 0),
      'posted', coalesce(sum(l.posted), 0), 'posted_batches', (select count(*) from public.po_receipt_post q where q.receipt_id = p_receipt_id),   -- rcv-1b
      'over_lines', count(*) filter (where l.counted > l.invoiced - l.received_before),                                       -- 판정 101(inv-basis-6): 기준 = lines[].expected
      'short_lines', count(*) filter (where l.counted < l.invoiced - l.received_before),                                      -- 판정 101
      'open_diffs', (select count(*) from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null))
    from lines l
  ),
  'warnings', (
    select coalesce(jsonb_agg(v), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select p.status from r join public.po p on p.id = r.po_id) <> 'confirmed' and (select status from r) = 'draft' then 'po_not_confirmed' end,
        case when exists (select 1 from lines l where l.counted > l.invoiced - l.received_before) then 'over_receipt' end,                -- 판정 101
        case when exists (select 1 from w x where x.bin_id is null) then 'unassigned_rows' end,
        case when not exists (select 1 from w) then 'nothing_counted' end,
        case when exists (select 1 from lines l where l.received_here <> l.counted) and (select status from r) = 'confirmed' then 'receipt_lines_differ_from_work' end,
        case when exists (select 1 from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null) then 'open_diffs' end,
        case when exists (select 1 from public.po_receipt_post q where q.receipt_id = p_receipt_id) then 'posted_before' end                 -- rcv-1b
      ], null)) as v) t
  )
) end;
$$;

-- ═══ 9) 가드 ⑤ — 작업 줄을 쓰는 여섯(창고 셸 wms_recv_* 는 _by 를 부르므로 함께 덮인다) ═══
-- 9a) po_receipt_work_save_by — 원본 20260929010938_transfer_3a.sql:382 바이트 + 반영 합 아래 거부
create or replace function public.po_receipt_work_save_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_receipt_id   uuid,
  p_po_line_id   uuid,
  p_qty_ea       numeric,                           -- ⭐ 그 라인의 센 수량(총량 · 낱개) · 0 = 센 것 없음
  p_count_method text default null                  -- 'scanned' | 'manual' | null
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_r      public.po_receipt%rowtype;
  v_pl     public.po_line%rowtype;
  v_tl     public.inv_transfer_line%rowtype;         -- tr-3a: 트랜스퍼 줄(receipt.transfer_id 가 있으면 p_po_line_id 는 트랜스퍼 줄 id)
  v_line_no int; v_expected numeric; v_is_tf boolean := false;
  v_sku    text;
  v_alloc  numeric;
  v_free   public.po_receipt_work%rowtype;    -- 빈 없는 줄(있으면)
  v_free_n int;
  v_rest   numeric;
  v_n      int;
  v_action text;
  v_id     uuid;
  v_now    timestamptz := now();
  v_posted numeric;                           -- rcv-1b(가드 ⑤): 이 라인의 먼저 반영 합
begin
  if p_staff is null then raise exception 'po_receipt_work_save_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  if p_qty_ea is null or p_qty_ea < 0 then raise exception 'p_qty_ea must be 0 or more — nothing was saved'; end if;
  if p_count_method is not null and p_count_method not in ('scanned', 'manual') then
    raise exception 'p_count_method must be scanned, manual or null — nothing was saved';
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — counts can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  if v_r.transfer_id is not null then                                          -- tr-3a 판정 66 · 74: 트랜스퍼 입고 — 기대 = 보낸 수량(qty_sent × pack_factor · 낱개)
    v_is_tf := true;
    select * into v_tl from public.inv_transfer_line where id = p_po_line_id;
    if not found then raise exception 'Transfer line % not found — nothing was saved', p_po_line_id; end if;
    if v_tl.transfer_id <> v_r.transfer_id then
      raise exception 'Transfer line % does not belong to the transfer of receipt % — nothing was saved', p_po_line_id, v_r.receipt_number;
    end if;
    v_line_no := v_tl.line_no; v_expected := coalesce(v_tl.qty_sent, 0) * v_tl.pack_factor;
    select pr.sku into v_sku from public.product pr where pr.id = v_tl.product_id;
  else
  select * into v_pl from public.po_line where id = p_po_line_id;
  if not found then raise exception 'PO line % not found — nothing was saved', p_po_line_id; end if;
  if v_pl.po_id <> v_r.po_id then                                              -- 남의 PO 라인을 붙이지 못하게
    raise exception 'PO line % does not belong to the PO of receipt % — nothing was saved', p_po_line_id, v_r.receipt_number;
  end if;
  v_line_no := v_pl.line_no; v_expected := v_pl.qty_ea;
  select pr.sku into v_sku from public.product pr where pr.id = v_pl.product_id;
  end if;
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지)

  -- 배정 합(빈 붙은 줄들) · 빈 없는 줄
  select coalesce(sum(w.qty_ea), 0) into v_alloc from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is not null;
  select count(*) into v_free_n from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is null;
  if v_free_n > 1 then                                                          -- 불변식 ① 이 깨져 있다 — 자동으로 고치지 않고 알린다
    raise exception 'Line % of receipt % has % unassigned rows — this should not happen; fix the rows first — nothing was saved', v_line_no, v_r.receipt_number, v_free_n;
  end if;
  select * into v_free from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is null;

  -- rcv-1b(가드 ⑤): 먼저 반영된 수량 아래로 못 내린다(반영 줄은 얼려 있어 배정 합에 들어 있다 — 글만 따로)
  select coalesce(sum(w.qty_ea), 0) into v_posted from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.post_id is not null;
  if p_qty_ea < v_posted then
    raise exception 'Line % (%) of receipt %: % EA are already in stock from post-now — the count cannot go below that; change it with a stock adjustment (Adjustments) — nothing was saved',
      v_line_no, v_sku, v_r.receipt_number, v_posted;
  end if;
  -- ⬜2 나머지 = 센 수량 − 배정 합
  v_rest := p_qty_ea - v_alloc;
  if v_rest < 0 then
    raise exception 'Line % (%) of receipt %: counted % is less than the % already assigned to bins — reduce or remove the bin rows first — nothing was saved',
      v_line_no, v_sku, v_r.receipt_number, p_qty_ea, v_alloc;
  end if;

  if v_rest = 0 then
    if v_free.id is not null then
      delete from public.po_receipt_work where id = v_free.id;
      get diagnostics v_n = row_count;
      if v_n = 0 then raise exception 'Line % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_r.receipt_number; end if;
      v_action := 'deleted';
    else
      v_action := 'unchanged';                                                  -- 0 을 세었고 줄도 없다 — 쓸 것이 없다
    end if;
  elsif v_free.id is not null then
    update public.po_receipt_work
       set qty_ea = v_rest, count_method = coalesce(p_count_method, count_method), counted_by = v_staff, counted_at = v_now
     where id = v_free.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Line % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_r.receipt_number; end if;
    v_id := v_free.id; v_action := 'updated';
  else
    insert into public.po_receipt_work (receipt_id, po_line_id, transfer_line_id, qty_ea, count_method, counted_by, counted_at)
    values (p_receipt_id, case when v_is_tf then null else p_po_line_id end, case when v_is_tf then p_po_line_id end, v_rest, p_count_method, v_staff, v_now)
    returning id into v_id;
    v_action := 'inserted';
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', p_po_line_id, 'line_no', v_line_no, 'sku', v_sku,
    'counted', p_qty_ea, 'allocated', v_alloc, 'unallocated', v_rest,
    'work_id', v_id, 'action', v_action, 'counted_by', v_staff, 'counted_at', v_now,
    'over_ordered', (p_qty_ea > v_expected));                                   -- 초과 신호(표시용 · 판정·큐는 2-b 확정 RPC · 트랜스퍼는 보낸 수량 기준)
end;
$$;
-- 9b) po_receipt_work_putaway_by — 원본 20260929010938_transfer_3a.sql:489 바이트 + 반영 줄 거부 · 병합 대상에서 제외
create or replace function public.po_receipt_work_putaway_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_work_id uuid,
  p_bin_id  uuid,
  p_done    boolean default true
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_w      public.po_receipt_work%rowtype;
  v_r      public.po_receipt%rowtype;
  v_b      public.ref_bin%rowtype;
  v_dup    public.po_receipt_work%rowtype;
  v_n      int;
  v_now    timestamptz := now();
  v_out_id uuid;
  v_merged uuid;
begin
  if p_staff is null then raise exception 'po_receipt_work_putaway_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — putaway can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  if v_w.post_id is not null then                                              -- rcv-1b(가드 ⑤): 반영된 줄의 칸은 원장 행의 칸이다
    raise exception 'Work row % of receipt % is already in stock from post-now — its bin cannot be changed; change it with a stock adjustment (Adjustments) — nothing was saved', p_work_id, v_r.receipt_number;
  end if;
  v_b := public.po_receipt_bin_check(v_w.receipt_id, p_bin_id);                -- 창고·활성
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || coalesce(v_w.po_line_id, v_w.transfer_line_id)::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지) · tr-3a 트랜스퍼 줄도 같은 열쇠

  -- 같은 라인에 그 빈 줄이 이미 있으면(다른 줄) — 합친다(유니크가 막는 자리를 병합으로 · 합 불변)
  select * into v_dup from public.po_receipt_work w
   where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id) and w.bin_id = p_bin_id and w.id <> p_work_id and w.post_id is null;   -- rcv-1b: 반영된 줄은 병합 대상이 아니다(같은 칸에 따로 선다 · 유니크 post_key)
  if found then
    update public.po_receipt_work set qty_ea = qty_ea + v_w.qty_ea, putaway_done = coalesce(p_done, true), putaway_by = v_staff, putaway_at = v_now where id = v_dup.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_dup.id, v_r.receipt_number; end if;
    delete from public.po_receipt_work where id = p_work_id and qty_ea = v_w.qty_ea;                  -- 읽은 수량 그대로일 때만 지운다
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_dup.id; v_merged := v_dup.id;
  else
    update public.po_receipt_work
       set bin_id = p_bin_id, putaway_done = coalesce(p_done, true), putaway_by = v_staff, putaway_at = v_now
     where id = p_work_id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := p_work_id;
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'work_id', v_out_id, 'po_line_id', coalesce(v_w.po_line_id, v_w.transfer_line_id),
    'bin_id', p_bin_id, 'bin', v_b.name, 'zone', v_b.zone, 'putaway_done', coalesce(p_done, true),
    'putaway_by', v_staff, 'putaway_at', v_now, 'merged_into', v_merged);
end;
$$;
-- 9c) po_receipt_work_putaway_all_by — 원본 20260926213035_wms_5_3a_receiving_split.sql:307 바이트 + 반영 줄 제외
create or replace function public.po_receipt_work_putaway_all_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_receipt_id uuid,
  p_bin_id     uuid,
  p_done       boolean default true
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_r     public.po_receipt%rowtype;
  v_b     public.ref_bin%rowtype;
  v_n     int;
  v_now   timestamptz := now();
begin
  if p_staff is null then raise exception 'po_receipt_work_putaway_all_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — putaway can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  v_b := public.po_receipt_bin_check(p_receipt_id, p_bin_id);

  update public.po_receipt_work
     set putaway_done = coalesce(p_done, true), putaway_by = v_staff, putaway_at = v_now
   where receipt_id = p_receipt_id and bin_id = p_bin_id and putaway_done is distinct from coalesce(p_done, true) and post_id is null;   -- 이미 그 상태인 줄은 안 건드린다(WMS 와 같다) · rcv-1b: 반영된 줄은 얼려 있다
  get diagnostics v_n = row_count;
  -- 0행은 여기서 거짓말이 아니다 — 「바꿀 줄이 없었다」를 그대로 알린다(rows_changed 0) · 권한 거부는 첫머리가 이미 걸렀다
  return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'bin_id', p_bin_id, 'bin', v_b.name,
                            'rows_changed', v_n, 'putaway_done', coalesce(p_done, true), 'putaway_by', v_staff, 'putaway_at', v_now);
end;
$$;
-- 9d) po_receipt_work_split — 원본 20260929010938_transfer_3a.sql:551 바이트 + 반영 줄 거부 · 병합 대상에서 제외
create or replace function public.po_receipt_work_split(
  p_work_id uuid,
  p_qty_ea  numeric,                                -- 떼어 낼 수량(낱개) · 0 < p_qty_ea < 원래 수량
  p_bin_id  uuid                                    -- ⭐ 새 줄의 빈(필수 · 그 입고의 창고 · 활성)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_w      public.po_receipt_work%rowtype;
  v_r      public.po_receipt%rowtype;
  v_b      public.ref_bin%rowtype;
  v_to     public.po_receipt_work%rowtype;
  v_to_id  uuid;
  v_to_before numeric := 0;
  v_merged boolean := false;
  v_n      int;
  v_total  numeric;
  v_now    timestamptz := now();
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — rows can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  if v_w.post_id is not null then                                              -- rcv-1b(가드 ⑤)
    raise exception 'Work row % of receipt % is already in stock from post-now — it cannot be split; change it with a stock adjustment (Adjustments) — nothing was saved', p_work_id, v_r.receipt_number;
  end if;
  if p_qty_ea is null or p_qty_ea <= 0 then raise exception 'p_qty_ea must be above 0 — nothing was saved'; end if;
  if p_qty_ea >= v_w.qty_ea then
    raise exception 'Cannot split % of % — the row would be left with nothing; use putaway to move the whole row — nothing was saved', p_qty_ea, v_w.qty_ea;
  end if;
  v_b := public.po_receipt_bin_check(v_w.receipt_id, p_bin_id);                -- 창고·활성(도우미 · 문장은 거기)
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || coalesce(v_w.po_line_id, v_w.transfer_line_id)::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지) · tr-3a
  if v_w.bin_id = p_bin_id then
    raise exception 'The row is already in bin % — pick a different bin to split into — nothing was saved', v_b.name;
  end if;

  -- 원래 줄에서 뺀다
  update public.po_receipt_work set qty_ea = qty_ea - p_qty_ea where id = p_work_id and qty_ea = v_w.qty_ea;   -- ⭐ 읽은 수량 그대로일 때만(남이 사이에 바꿨으면 0행)
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;

  -- 같은 라인·같은 빈 줄이 있으면 합친다(유니크가 막는 자리를 병합으로) · 없으면 새 줄
  select * into v_to from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id) and w.bin_id = p_bin_id and w.post_id is null;   -- rcv-1b: 반영된 줄은 병합 대상이 아니다
  if found then
    v_to_id := v_to.id; v_to_before := v_to.qty_ea; v_merged := true;
    update public.po_receipt_work set qty_ea = qty_ea + p_qty_ea, putaway_done = true, putaway_by = v_staff, putaway_at = v_now where id = v_to.id;   -- ⬜1 합쳐진 줄도 놓인 것 · by/at 은 putaway 병합 가지와 같은 모양(덮는다)
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_to.id, v_r.receipt_number; end if;
  else
    insert into public.po_receipt_work (receipt_id, po_line_id, transfer_line_id, qty_ea, bin_id, putaway_done, count_method, counted_by, counted_at, putaway_by, putaway_at)
    values (v_w.receipt_id, v_w.po_line_id, v_w.transfer_line_id, p_qty_ea, p_bin_id, true, v_w.count_method, v_w.counted_by, v_w.counted_at, v_staff, v_now)    -- ⭐ 빈을 고르는 순간 놓인 것(true · Caleb 2026-09-18) · 수량 축은 원래 줄의 것을 물려받는다(센 사람은 안 바뀐다)
    returning id into v_to_id;
  end if;

  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id);
  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
    'from', jsonb_build_object('work_id', v_w.id, 'bin_id', v_w.bin_id, 'qty_before', v_w.qty_ea, 'qty_after', v_w.qty_ea - p_qty_ea),
    'to',   jsonb_build_object('work_id', v_to_id, 'bin_id', p_bin_id, 'bin', v_b.name, 'zone', v_b.zone, 'qty_before', v_to_before, 'qty_after', v_to_before + p_qty_ea, 'merged', v_merged),
    'line_total', v_total);                                                    -- ⭐ 쪼개기 전과 같아야 한다
end;
$$;
-- 9e) po_receipt_work_unassign — 원본 20260929010938_transfer_3a.sql:622 바이트 + 반영 줄 거부
create or replace function public.po_receipt_work_unassign(p_work_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_w       public.po_receipt_work%rowtype;
  v_r       public.po_receipt%rowtype;
  v_b       public.ref_bin%rowtype;
  v_free    public.po_receipt_work%rowtype;    -- 그 라인의 빈 없는 줄(있으면)
  v_free_n  int;
  v_before  numeric;
  v_after   numeric;
  v_n       int;
  v_out_id  uuid;
  v_removed uuid;
  v_merged  uuid;
  v_qty     numeric;
  v_action  text;
begin
  perform public.ims_require_write('receiving', 'saved');      -- §5 ②
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was saved', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.confirmed_at is not null or v_r.status <> 'draft' then                    -- 축은 confirmed_at · status 도 함께(cancelled 도 못 고친다) — work_delete 와 같은 검사
    raise exception 'Receipt % is % — rows can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  if v_w.post_id is not null then                                              -- rcv-1b(가드 ⑤)
    raise exception 'Work row % of receipt % is already in stock from post-now — it cannot be taken out of its bin; change it with a stock adjustment (Adjustments) — nothing was saved', p_work_id, v_r.receipt_number;
  end if;

  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || coalesce(v_w.po_line_id, v_w.transfer_line_id)::text));   -- 2-a 이견 12 와 같은 키 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지) · tr-3a
  select coalesce(sum(w.qty_ea), 0) into v_before from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id);

  -- ⬜1 이미 빈이 없다 — 쓸 것이 없다(멱등)
  if v_w.bin_id is null then
    return jsonb_build_object(
      'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
      'work_id', v_w.id, 'removed_work_id', null, 'merged_into', null,
      'qty_moved', 0, 'qty_after', v_w.qty_ea, 'bin_before', null, 'line_total', v_before, 'action', 'unchanged');
  end if;
  select * into v_b from public.ref_bin where id = v_w.bin_id;                     -- 반환용 이름(없어도 진행 — 되돌리는 데 빈 표는 필요 없다)

  -- 그 라인의 빈 없는 줄 — 둘 이상이면 불변식이 깨져 있다(work_save 와 같은 처방 · 자동으로 고치지 않는다)
  select count(*) into v_free_n from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id) and w.bin_id is null;
  if v_free_n > 1 then
    raise exception 'Line of receipt % has % unassigned rows — this should not happen; fix the rows first — nothing was saved', v_r.receipt_number, v_free_n;
  end if;
  select * into v_free from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id) and w.bin_id is null;

  if v_free.id is not null then
    -- ⭐ 병합 — 빈 없는 줄에 더하고 이 줄을 지운다(putaway 의 v_dup 가지와 같은 결 · 수량 축 counted_* 은 안 건드린다)
    update public.po_receipt_work set qty_ea = qty_ea + v_w.qty_ea where id = v_free.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_free.id, v_r.receipt_number; end if;
    delete from public.po_receipt_work where id = p_work_id and qty_ea = v_w.qty_ea;                  -- 읽은 수량 그대로일 때만 지운다
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_free.id; v_removed := v_w.id; v_merged := v_free.id; v_qty := v_free.qty_ea + v_w.qty_ea; v_action := 'merged';
  else
    -- 빈 없는 줄이 없다 — 이 줄이 그 줄이 된다(빈·놓았나·넣은 사람 전부 되돌린다 · putaway_bin_ck 와 함께)
    update public.po_receipt_work
       set bin_id = null, putaway_done = false, putaway_by = null, putaway_at = null
     where id = p_work_id and bin_id = v_w.bin_id;                                                     -- 읽은 빈 그대로일 때만(남이 사이에 옮겼으면 0행)
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Work row % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_work_id, v_r.receipt_number; end if;
    v_out_id := v_w.id; v_removed := null; v_merged := null; v_qty := v_w.qty_ea; v_action := 'unassigned';
  end if;

  -- ⭐ 합 불변 — 함수가 보장한다(다르면 전부 되돌린다)
  select coalesce(sum(w.qty_ea), 0) into v_after from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id);
  if v_after <> v_before then
    raise exception 'Line total of receipt % changed from % to % while taking the row out of its bin — nothing was saved', v_r.receipt_number, v_before, v_after;
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', v_w.po_line_id,
    'work_id', v_out_id, 'removed_work_id', v_removed, 'merged_into', v_merged,
    'qty_moved', v_w.qty_ea, 'qty_after', v_qty,
    'bin_before', jsonb_build_object('bin_id', v_w.bin_id, 'bin', v_b.name, 'zone', v_b.zone),
    'line_total', v_after, 'action', v_action);
end;
$$;
-- 9f) po_receipt_work_delete — 원본 20260929010938_transfer_3a.sql:709 바이트 + 반영 줄 거부
create or replace function public.po_receipt_work_delete(p_work_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_w  public.po_receipt_work%rowtype;
  v_r  public.po_receipt%rowtype;
  v_n  int;
  v_total numeric;
begin
  perform public.ims_require_write('receiving', 'deleted');    -- §5 ②
  select * into v_w from public.po_receipt_work where id = p_work_id;
  if not found then raise exception 'Work row % not found — nothing was deleted', p_work_id; end if;
  select * into v_r from public.po_receipt where id = v_w.receipt_id;
  if v_r.confirmed_at is not null or v_r.status <> 'draft' then                    -- 축은 confirmed_at(20260917100000) · status 도 함께(cancelled 도 못 고친다)
    raise exception 'Receipt % is % — rows can be deleted only while draft — nothing was deleted', v_r.receipt_number, v_r.status;
  end if;
  if v_w.post_id is not null then                                              -- rcv-1b(가드 ⑤)
    raise exception 'Work row % of receipt % is already in stock from post-now — it cannot be deleted; change it with a stock adjustment (Adjustments) — nothing was deleted', p_work_id, v_r.receipt_number;
  end if;
  delete from public.po_receipt_work where id = p_work_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Work row % of receipt % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_work_id, v_r.receipt_number; end if;
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = v_w.receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = coalesce(v_w.po_line_id, v_w.transfer_line_id);
  return jsonb_build_object('deleted', true, 'work_id', v_w.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number,
                            'po_line_id', v_w.po_line_id, 'qty_removed', v_w.qty_ea, 'bin_id', v_w.bin_id, 'line_total', v_total);
end;
$$;

-- ═══ 10) 창구 — 먼저 반영(판정 550 · 551 · 552): 셸 po_receipt_post_now(오피스 · ims_require_write('receiving')) + 속 po_receipt_post_now_by(definer · 회수) ═══
--   검사 ①④⑤⑥ 은 po_receipt_confirm_by 의 것을 복사했다(이견 5 · 두 집 — 한쪽을 고치면 다른 쪽도) · 창고 Complete(wms_recv_state)는 보지 않는다(세는 중 반영이 목적) · 창고 셸은 없다(판정 552)
create function public.po_receipt_post_now_by(p_staff uuid, p_receipt_id uuid, p_lines jsonb, p_commit boolean default false) returns jsonb
language plpgsql
volatile
security definer                                              -- po · po_line · po_invoice(purchasing RLS) · po_receipt_post 에 쓴다 · 문은 셸 첫 줄
set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_base     text;
  v_cur      text;
  v_base_cur text;
  v_ids      uuid[];
  v_id       uuid;
  v_w        public.po_receipt_work%rowtype;
  v_n        int;
  v_batch    int;
  v_post_id  uuid;
  v_qty      numeric := 0;
  v_rows     int := 0;
  v_lines    jsonb := '[]'::jsonb;
  v_avail    jsonb := '[]'::jsonb;
  v_pb_n     int := 0;  v_pb_q numeric := 0;
  v_bad_on   date;
  v_ledger   jsonb;
  v_warn     text[] := '{}';
  v_now      timestamptz := now();
  x          record;
  v_basis    text;  v_unit numeric;  v_inv_no text;
begin
  if p_staff is null then raise exception 'po_receipt_post_now_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then
    raise exception 'Pick at least one counted row that has a bin — nothing was saved';
  end if;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — post-now is for purchase receipts only — nothing was saved', v_r.receipt_number; end if;
  -- ① (confirm_by 와 같다) 이미 확정 · 취소
  if v_r.confirmed_at is not null or v_r.status <> 'draft' then
    raise exception 'Receipt % is % — post-now works on a draft receipt only — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  -- 잠금 — confirm_by 와 같은 열쇠(PO base + 라인 전부) · 세는 손 · 확정과 줄 세운다
  v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('po:' || v_base));
  for x in select pl.id from public.po_line pl where pl.po_id = v_po.id loop
    perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || x.id::text));
  end loop;
  -- ④ 잠금 뒤 다시 본다(confirm_by 와 같다)
  select * into v_po from public.po where id = v_r.po_id;
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — stock can be posted only on a confirmed order — nothing was saved', v_po.po_number, v_po.status;
  end if;
  if not exists (select 1 from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id join public.po_line pl on pl.id = il.po_line_id
                  where pl.po_id = v_po.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed') then
    raise exception 'PO % has no confirmed invoice — the office confirms the supplier invoice first (Purchase Invoices), then stock can be posted — nothing was saved', v_po.po_number;
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % was changed by someone else just now (% ) — reload and try again — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  -- 이견 9: 묶음 뒤 날짜가 바뀌었으면 여기서도(미리 보기가 말하게) · 원장 창구가 한 번 더 본다
  select min(l.occurred_on) into v_bad_on from public.inv_ledger l
   where l.doc_type = 'purchase' and l.source = 'ims' and l.doc_number = v_r.receipt_number and l.line_ref ~ ':p[0-9]+$' and l.occurred_on <> v_r.received_on;
  if v_bad_on is not null then
    raise exception 'Receipt % — its date was changed to % after a post-now batch went to the ledger on % — set the date back to % and try again — nothing was saved', v_r.receipt_number, v_r.received_on, v_bad_on, v_bad_on;
  end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;
  -- ⑥ 환율(confirm_by 와 같다)
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — nothing was saved'; end if;
  if v_cur is distinct from v_base_cur and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
    raise exception 'PO % is in % but has no % per % exchange rate — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and try again — nothing was saved',
      v_po.po_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
  end if;

  -- 고른 줄 — 이 입고의 작업 줄 · 칸 있음 · 아직 반영 안 됨 · 칸은 이 창고 · 활성(⑤ 와 같다) · 중복은 접는다
  select array_agg(distinct e::uuid) into v_ids from jsonb_array_elements_text(p_lines) e;
  foreach v_id in array v_ids loop
    select * into v_w from public.po_receipt_work w where w.id = v_id;
    if not found or v_w.receipt_id <> p_receipt_id then raise exception 'Work row % is not on receipt % — nothing was saved', v_id, v_r.receipt_number; end if;
    select pl.line_no, pr.sku, pl.product_id, rb.name as bin, rb.warehouse_id as bin_wh, rb.is_active as bin_active
      into x from public.po_line pl join public.product pr on pr.id = pl.product_id left join public.ref_bin rb on rb.id = v_w.bin_id where pl.id = v_w.po_line_id;
    if v_w.post_id is not null then
      raise exception 'Line % (%) of receipt %: the row in bin % is already in stock from post-now — nothing was saved', x.line_no, x.sku, v_r.receipt_number, x.bin;
    end if;
    if v_w.bin_id is null then
      raise exception 'Line % (%) of receipt %: % EA have no bin — put them away first, then post — nothing was saved', x.line_no, x.sku, v_r.receipt_number, v_w.qty_ea;
    end if;
    if x.bin_wh <> v_r.warehouse_id or not x.bin_active then
      raise exception 'Line % (%) of receipt %: bin % is inactive or not in this receipt''s warehouse — move the row to another bin first — nothing was saved', x.line_no, x.sku, v_r.receipt_number, x.bin;
    end if;
    -- 단가 근거만(이견 11): 핀 → 확정 인보이스 → PO · 금액 식은 레이어 창구 한 곳
    v_basis := null; v_unit := null; v_inv_no := null;
    select k.unit_cost_cad into v_unit from public.po_receipt_cost k where k.receipt_id = p_receipt_id and k.po_line_id = v_w.po_line_id;
    if found then
      v_basis := 'pinned';
      select i.invoice_number into v_inv_no from public.po_receipt_cost k join public.po_invoice i on i.id = k.invoice_id where k.receipt_id = p_receipt_id and k.po_line_id = v_w.po_line_id;
    else
      select i.invoice_number into v_inv_no from public.po_invoice i
       where i.doc_kind = 'invoice' and i.status = 'confirmed'
         and exists (select 1 from public.po_invoice_line il where il.po_invoice_id = i.id and il.line_kind = 'goods' and il.po_line_id = v_w.po_line_id and il.qty_ea > 0)
       order by i.confirmed_at desc nulls last, i.invoice_number desc limit 1;
      v_basis := case when v_inv_no is not null then 'invoice' else 'po' end;
    end if;
    v_qty := v_qty + v_w.qty_ea; v_rows := v_rows + 1;
    v_lines := v_lines || jsonb_build_object('work_id', v_w.id, 'po_line_id', v_w.po_line_id, 'line_no', x.line_no, 'sku', x.sku, 'product_id', x.product_id,
                                             'qty_ea', v_w.qty_ea, 'bin_id', v_w.bin_id, 'bin', x.bin, 'cost_basis', v_basis, 'unit_cost_cad', v_unit, 'invoice_number', v_inv_no);
  end loop;

  -- 이 반영 뒤 그 SKU 의 가용(stk_availability 와 같은 식: 장부 − 판매 예약 − 트랜스퍼 예약 · + 반영 수량)
  select coalesce(jsonb_agg(jsonb_build_object('product_id', t.pid, 'sku', pr.sku, 'post_qty', t.q,
                                               'available_now', coalesce(a.qty_ea, 0) - coalesce(a.sales_alloc_ea, 0) - coalesce(a.transfer_alloc_ea, 0),
                                               'available_after', coalesce(a.qty_ea, 0) - coalesce(a.sales_alloc_ea, 0) - coalesce(a.transfer_alloc_ea, 0) + t.q) order by pr.sku), '[]'::jsonb)
    into v_avail
    from (select (e->>'product_id')::uuid as pid, sum((e->>'qty_ea')::numeric) as q from jsonb_array_elements(v_lines) e group by 1) t
    join public.product pr on pr.id = t.pid
    left join public.inv_available_base(v_r.warehouse_id, (select array_agg(distinct (e->>'product_id')::uuid) from jsonb_array_elements(v_lines) e)) a on a.stock_pid = t.pid;
  select count(*), coalesce(sum(w.qty_ea), 0) into v_pb_n, v_pb_q from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.post_id is not null;
  select coalesce(max(q.batch_no), 0) + 1 into v_batch from public.po_receipt_post q where q.receipt_id = p_receipt_id;

  if not p_commit then
    return jsonb_build_object('committed', false, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'received_on', v_r.received_on,
                              'batch_no', v_batch, 'rows', v_rows, 'qty_ea', v_qty, 'lines', v_lines, 'availability', v_avail,
                              'posted_before', jsonb_build_object('batches', v_batch - 1, 'qty', v_pb_q), 'warnings', to_jsonb(v_warn));
  end if;

  -- 실행: 묶음 행 → 작업 줄 얼림(post_id) → 입고 줄(post_id) → 원장 :pN(+ 레이어 · 핀) · 비용은 얹지 않는다(판정 553)
  insert into public.po_receipt_post (receipt_id, batch_no, posted_by, posted_at, updated_by) values (p_receipt_id, v_batch, v_staff, v_now, v_staff) returning id into v_post_id;
  update public.po_receipt_work set post_id = v_post_id, updated_by = v_staff where id = any(v_ids) and post_id is null and bin_id is not null;
  get diagnostics v_n = row_count;
  if v_n <> cardinality(v_ids) then raise exception 'Receipt % — a picked row was changed by someone else just now — reload and try again — nothing was saved', v_r.receipt_number; end if;
  insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, note, receipt_id, post_id)
  select w.po_line_id, v_r.received_on, coalesce(w.putaway_by, w.counted_by, v_staff), w.bin_id, w.qty_ea, w.note, v_r.id, v_post_id
    from public.po_receipt_work w where w.id = any(v_ids)
   order by w.po_line_id, w.created_at;
  get diagnostics v_n = row_count;
  if v_n <> v_rows then raise exception 'Receipt %: % row(s) picked but % receipt line(s) were written — nothing was saved', v_r.receipt_number, v_rows, v_n; end if;
  v_ledger := public.inv_post_receipt(p_receipt_id, v_post_id);
  if (v_ledger->'warnings') ? 'received_on_before_baseline' then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;
  if coalesce((v_ledger->>'rows_posted')::int, 0) <> v_rows or coalesce((v_ledger->>'qty_posted')::numeric, -1) <> v_qty then
    raise exception 'Receipt % batch %: % row(s) · % EA picked but the ledger took % row(s) · % EA — nothing was saved', v_r.receipt_number, v_batch, v_rows, v_qty, v_ledger->>'rows_posted', v_ledger->>'qty_posted';
  end if;

  return jsonb_build_object('committed', true, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'received_on', v_r.received_on,
                            'post_id', v_post_id, 'batch_no', v_batch, 'posted_by', v_staff, 'posted_at', v_now,
                            'rows', v_rows, 'qty_ea', v_qty, 'lines', v_lines, 'availability', v_avail,
                            'ledger', jsonb_build_object('rows_posted', v_ledger->'rows_posted', 'qty_posted', v_ledger->'qty_posted', 'lines', v_ledger->'lines'),
                            'layers', jsonb_build_object('layers_created', v_ledger->'layers'->'layers_created', 'layers_existing', v_ledger->'layers'->'layers_existing', 'cost_total_cad', v_ledger->'layers'->'cost_total_cad', 'lines', v_ledger->'layers'->'lines'),
                            'posted_before', jsonb_build_object('batches', v_batch - 1, 'qty', v_pb_q),
                            'receipt_status', 'draft', 'po_status', v_po.status, 'warnings', to_jsonb(v_warn));
end;
$$;
revoke all on function public.po_receipt_post_now_by(uuid, uuid, jsonb, boolean) from public, anon, authenticated;
comment on function public.po_receipt_post_now_by(uuid, uuid, jsonb, boolean) is 'rcv-1b(판정 550) 속 — 먼저 반영: 고른 작업 줄(칸 있음 · 미반영)을 묶음으로 재고에 넣는다 · p_commit false = 미리 보기(쓰기 0 · 줄 · 단가 근거 · 가용) · 검사 ①④⑤⑥ 은 po_receipt_confirm_by 의 복사(두 집) · 원장 inv_post_receipt(receipt, post) · 비용은 얹지 않는다(판정 553)';

create function public.po_receipt_post_now(p_receipt_id uuid, p_lines jsonb, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer                  -- 셸: 문 첫 줄 · 활성 직원 · 창고 · 속을 부른다(po_receipt_confirm 과 같은 꼴 · 창고 Complete 는 보지 않는다)
  set search_path = public, pg_temp
as $$
declare v_staff uuid;
begin
  perform public.ims_require_write('receiving', 'saved');      -- 판정 551 · 552: 입고 확정을 하는 사람만 · 오피스 문 하나
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if not public.ims_can_warehouse((select r.warehouse_id from public.po_receipt r where r.id = p_receipt_id)) then
    raise exception 'This receipt is at another warehouse — you are not set up for it — nothing was saved';
  end if;
  return public.po_receipt_post_now_by(v_staff, p_receipt_id, p_lines, coalesce(p_commit, false));
end;
$$;
revoke all on function public.po_receipt_post_now(uuid, jsonb, boolean) from public, anon;
grant execute on function public.po_receipt_post_now(uuid, jsonb, boolean) to authenticated, service_role;
comment on function public.po_receipt_post_now(uuid, jsonb, boolean) is 'rcv-1b(판정 550 · 551 · 552) 셸 — 먼저 반영(오피스): p_lines = 작업 줄 id 의 jsonb 배열 · p_commit false 미리 보기 / true 반영 · 문 ims_require_write(receiving) · 속 po_receipt_post_now_by';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int; v_src text;
begin
  if to_regclass('public.po_receipt_post') is null then v_bad := v_bad || ' no_table'; end if;
  select count(*) into v_n from information_schema.columns where table_schema = 'public' and ((table_name = 'po_receipt_work' and column_name in ('post_id', 'post_key')) or (table_name = 'po_receipt_line' and column_name = 'post_id'));
  if v_n <> 3 then v_bad := v_bad || format(' columns_%s', v_n); end if;
  if not exists (select 1 from pg_constraint where conname = 'po_receipt_work_receipt_line_bin_post_key' and conrelid = 'public.po_receipt_work'::regclass) then v_bad := v_bad || ' no_new_unique'; end if;
  if exists (select 1 from pg_constraint where conname = 'po_receipt_work_receipt_line_bin_key') then v_bad := v_bad || ' old_unique_left'; end if;
  if to_regprocedure('public.inv_post_receipt(uuid)') is not null then v_bad := v_bad || ' old_inv_post_receipt_left'; end if;
  if to_regprocedure('public.inv_post_receipt(uuid, uuid)') is null then v_bad := v_bad || ' no_inv_post_receipt2'; end if;
  if to_regprocedure('public.po_receipt_post_now(uuid, jsonb, boolean)') is null or to_regprocedure('public.po_receipt_post_now_by(uuid, uuid, jsonb, boolean)') is null then v_bad := v_bad || ' no_post_now'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~ 'rcv-1b'
     and p.proname in ('inv_layer_post_receipt', 'inv_post_receipt', 'po_receipt_confirm_by', 'inv_layer_post_charge', 'po_charge_confirm', 'po_receipt_over_bins', 'po_receipt_detail',
                       'po_receipt_work_save_by', 'po_receipt_work_putaway_by', 'po_receipt_work_putaway_all_by', 'po_receipt_work_split', 'po_receipt_work_unassign', 'po_receipt_work_delete');
  if v_n <> 13 then v_bad := v_bad || format(' reissued_%s_of_13', v_n); end if;
  select prosrc into v_src from pg_proc where oid = 'public.inv_layer_post_charge(uuid, date, uuid)'::regprocedure;
  if v_src !~ '''deferred''' or v_src !~ 'deferred_allocs' then v_bad := v_bad || ' charge_no_deferral'; end if;
  select prosrc into v_src from pg_proc where oid = 'public.inv_layer_post_receipt(uuid)'::regprocedure;
  if v_src !~ 'po_receipt_post' then v_bad := v_bad || ' layer_post_receipt_no_draft_branch'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosrc ~ 'already in stock from post-now'
     and p.proname in ('po_receipt_work_save_by', 'po_receipt_work_putaway_by', 'po_receipt_work_split', 'po_receipt_work_unassign', 'po_receipt_work_delete', 'po_receipt_confirm_by');
  if v_n <> 6 then v_bad := v_bad || format(' guards_%s_of_6', v_n); end if;
  if (select proacl::text from pg_proc where oid = 'public.inv_post_receipt(uuid, uuid)'::regprocedure) ~ 'authenticated' then v_bad := v_bad || ' inv_post_receipt_acl'; end if;
  if (select proacl::text from pg_proc where oid = 'public.po_receipt_post_now_by(uuid, uuid, jsonb, boolean)'::regprocedure) ~ 'authenticated' then v_bad := v_bad || ' post_now_by_acl'; end if;
  if v_bad <> '' then raise exception 'rcv-1b landing check failed:%', v_bad; end if;
end $$;
