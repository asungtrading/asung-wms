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
-- 20261008193337_po_disc_1.sql — po-disc-1 (2026-10-08 · 회사 PC) · 공급처 할인을 재고 원가에 ① 입고 때 PO 할인 체인 반영
--   결함(po-tax-0 §0-3 · §2-5d): 입고 레이어 단가 = po_line.unit_price × 환율 — PO 할인 체인을 무시했다(PO-02002a factor 0.9 · 3.538855 = 2.54 × 1.39325 · 맞는 값 2.54 × 0.9 × 1.39325 = 3.1849695)
--   Caleb 결정(2026-10-08 · 판정 번호는 다음 문서 차수): ① 공급처 할인은 재고 원가를 낮춘다 — (가) 입고 때 PO 할인 체인 · (나) 인보이스 확정 때 차액 · (다) 결제 때 조기 결제 할인 · 이 차수는 (가) 하나
--   ③ 매입 세금은 원가에 넣지 않는다(po-tax-1 · 2 그대로)
--   (가)의 식: 레이어 단가 = po_line.unit_price × PO 할인 계수 × 환율 계수 · 계수 = po_discount 체인(po_mul · 식 한 곳 po_discount_factor) · ⭐ 입고 확정 순간의 계수(그 뒤 바뀐 몫은 (나)) · 6자리 반올림 없음(po-disc-1 §0 이견 — 곱셈은 정확하고 옛 레이어가 한 푼도 안 움직인다)
--   ⭐ 「확정 순간」을 재생성이 재현하려면 계수를 적어 두어야 한다 — po_receipt.discount_factor(판정 114 posted_on 과 같은 결 · 창구 inv_layer_post_receipt 가 레이어를 처음 세울 때 적는다 · null 이면 지금 체인) · 재생성(inv_layer_apply → inv_layer_post_receipt)은 같은 창구라 식이 하나(§1-1)
--   기존 레이어: 손대지 않는다(㉠ · 전환 때 재생성 한 번 — 판정 120 과 같은 결 · 실측 2026-10-08: 할인 PO 위 IMS 레이어 2(PO-02002a) · 소비 0 · 값 차이 3.538855 CAD)
--   off-PO billed · over billed · 크레딧 복원은 무접촉(§1 표 · off-PO 의 단가는 인보이스에 찍힌 단가라 PO 체인을 모른다 — (나) 거리)
--   대상: [테스트 · Asung-IMS] — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 검증 ~/asung/prompts/po-disc-1-verify.sql

-- ═══ ① po_receipt.discount_factor — 입고 확정 순간의 PO 할인 계수(재생성의 재료) ═══
alter table public.po_receipt add column if not exists discount_factor numeric;
comment on column public.po_receipt.discount_factor is 'po-disc-1 ⭐ 입고 확정 순간의 PO 할인 체인 계수(po_mul · 1 = 할인 없음) — 창구 inv_layer_post_receipt 가 이 입고의 레이어를 처음 세울 때 적는다(실시간 확정 = 같은 트랜잭션 · 옛 입고는 재생성이 처음 부를 때) · 적힌 뒤에는 PO 할인이 바뀌어도 그대로(재생성이 같은 값을 다시 쓴다 · 그 뒤 바뀐 몫은 (나) 인보이스 차액) · null = 아직 레이어를 안 세웠다 / 트랜스퍼 입고 · 2026-10-08';

-- ═══ ② 식 한 곳 — PO 할인 계수 ═══
-- po_list · po_detail · po_tax_group 은 같은 집계 식(po_mul(1 − percent/100) · po_discount 묶음)을 안에 적어 왔다(실측 37 PO 전부 같은 값) — 입고 창구는 이 함수를 부른다 · 그 셋을 재발행하는 날 이 함수로 바꾼다(말만)
create function public.po_discount_factor(p_po_id uuid) returns numeric
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce((select public.po_mul(1 - d.percent / 100) from public.po_discount d where d.po_id = p_po_id), 1);
$$;
comment on function public.po_discount_factor(uuid) is 'po-disc-1 ⭐ PO 할인 체인 계수 한 곳 — po_discount 줄의 (1 − percent/100) 을 seq 차례로 곱한다(po_mul · 더하지 않는다 · §11-e) · 줄 없으면 1 · po_list.discount_factor(6자리 표시)와 같은 식 · 입고 창구 inv_layer_post_receipt 가 부른다(그 값을 po_receipt.discount_factor 에 적는다) · 2026-10-08';
revoke all on function public.po_discount_factor(uuid) from public, anon;
grant execute on function public.po_discount_factor(uuid) to authenticated;

-- ═══ ③ inv_layer_post_receipt 재발행 — 마지막 정의 20260928025627 · 단가에 PO 할인 계수 · 계수를 po_receipt 에 적는다 · 반환 discount_factor · discount_factor_source · lines[].unit_price_net ═══
create or replace function public.inv_layer_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt@2026-10-08.2';   -- po-disc-1: 단가에 PO 할인 체인 계수(입고 확정 순간 · po_receipt.discount_factor)
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_cur      text;
  v_base     text;
  v_factor   numeric;                 -- 통화 → CAD 계수. 기준통화면 1 · 아니면 po.exchange_rate(CAD per 통화)
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
begin

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — no cost layers were created', p_receipt_id; end if;
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — cost layers are built for confirmed receipts only — no cost layers were created', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — no cost layers were created', v_r.receipt_number; end if;

  -- 통화 · 환율 (이견 4 — confirm 이 먼저 막지만 직접 호출·백필 경로도 여기서 막는다)
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base from public.inv_config k where k.key = 'base_currency';
  if v_base is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — no cost layers were created'; end if;
  if v_cur is distinct from v_base then
    if v_po.exchange_rate is null or v_po.exchange_rate <= 0 then
      raise exception 'PO % is in % but has no % per % exchange rate — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and run again — no cost layers were created',
        v_po.po_number, coalesce(v_cur, '?'), v_base, coalesce(v_cur, '?');
    end if;
    -- ⚠️⚠️⚠️ po.exchange_rate 는 CAD per USD 다 — unit_price(USD) × exchange_rate = CAD. 곱한다. 나누면 원가가 반으로 줄어드는데 에러가 안 난다.
    v_factor := v_po.exchange_rate;
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
    order by l.line_ref
  loop
    v_rows := v_rows + x.ledger_rows;
    -- 멱등 — 같은 4키의 레이어가 있으면 건너뛴다(inv_layer_apply_po_in 과 같은 규칙)
    if exists (select 1 from public.inv_layer y
                where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = x.line_ref
                  and y.sku = x.sku and y.warehouse = x.warehouse) then
      v_existing := v_existing + 1;
      continue;
    end if;
    -- 단가 — line_ref 가 po_line_id 다(원장 이식 2차 · Caleb 실측 확정)
    select pl.unit_price into v_price from public.po_line pl where pl.id::text = x.line_ref;
    if v_price is null then
      raise exception 'Ledger row % / % on % points at a PO line (%) that does not exist — the ledger is wrong, not this function — no cost layers were created', x.sku, x.warehouse, v_r.receipt_number, x.line_ref;
    end if;
    -- ⚠️⚠️⚠️ CAD per USD × USD 단가 = CAD 단가. 곱한다. (기준통화면 v_factor = 1) · po-disc-1: × PO 할인 계수(체인 · 더하지 않는다) · 반올림 없음(옛 레이어와 같은 자릿수)
    v_unit := v_price * v_disc * v_factor;

    insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
    values (x.sku, x.warehouse, 'purchase', v_r.receipt_number, x.line_ref, null, x.received_on, true, x.qty, v_unit, 'po_line')
    returning id into v_layer_id;
    v_created := v_created + 1;
    v_qty  := v_qty  + x.qty;
    v_cost := v_cost + x.qty * v_unit;
    v_lines := v_lines || jsonb_build_object('layer_id', v_layer_id, 'po_line_id', x.line_ref, 'sku', x.sku, 'warehouse', x.warehouse,
                                             'qty', x.qty, 'ledger_rows', x.ledger_rows, 'unit_price', v_price, 'unit_price_net', v_price * v_disc, 'unit_cost_cad', v_unit, 'received_on', x.received_on);   -- po-disc-1 unit_price_net
  end loop;
  if v_rows = 0 then v_warn := array_append(v_warn, 'no_ledger_rows_for_receipt'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'currency', v_cur, 'base_currency', v_base, 'fx_rate', case when v_cur is distinct from v_base then v_po.exchange_rate else null end,
    'fx_direction', case when v_cur is distinct from v_base then v_base || ' per ' || coalesce(v_cur, '?') || ' — unit_price × rate'
                        else v_base || ' — base currency, no conversion (× 1)' end,          -- ⚠️ 나중에 방향을 의심할 때 보는 문장 — 거짓이면 안 된다(검증 ⑤ 정정)
    'discount_factor', v_disc, 'discount_factor_source', v_disc_src,                      -- po-disc-1
    'ledger_rows', v_rows, 'layers_created', v_created, 'layers_existing', v_existing,
    'qty', v_qty, 'cost_total_cad', v_cost, 'cost_source', 'po_line', 'builder', c_version,
    'lines', v_lines, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.inv_layer_post_receipt(uuid) is '⭐ 원가의 창구(원가 이식 1차 · 2026-09-19) — 확정 입고 하나의 IMS 원장 행(po_in · source ims)을 라인 단위로 접어 inv_layer 를 만든다(키 = 원장 키 · bin 접기 · cost_source po_line · 멱등 4키). 단가 = po_line.unit_price × ⭐ PO 할인 체인 계수(po-disc-1 2026-10-08 · po_discount_factor · 입고 확정 순간의 값을 po_receipt.discount_factor 에 적고 다음부터 그 값 · 반올림 없음) × 환율(CAD per USD · 곱한다 · 기준통화면 1 · 없으면 거부). 세금은 안 들어간다(po-tax-1). 재생성 inv_layer_apply 가 같은 창구를 부른다(식 하나). off-PO · 초과분은 형제 창구. 반환 discount_factor · discount_factor_source(receipt_stored | po_discount_now) · lines[].unit_price_net. security invoker · append-only';

-- ═══ ④ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_receipt' and column_name = 'discount_factor') <> 1 then v_bad := v_bad || ' column'; end if;
  if to_regprocedure('public.po_discount_factor(uuid)') is null then v_bad := v_bad || ' po_discount_factor'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_layer_post_receipt';
  if v_n <> 1 then v_bad := v_bad || format(' duplicate-signatures(%s)', v_n); end if;
  if (select prosrc from pg_proc where oid = to_regprocedure('public.inv_layer_post_receipt(uuid)')) not like '%v_price * v_disc * v_factor%' then v_bad := v_bad || ' body'; end if;
  select count(*) into v_n from public.po_list l where l.discount_factor <> round(public.po_discount_factor(l.id), 6);
  if v_n <> 0 then v_bad := v_bad || format(' factor_mismatch(%s)', v_n); end if;
  if has_function_privilege('anon', 'public.po_discount_factor(uuid)', 'execute') then v_bad := v_bad || ' anon'; end if;
  if v_bad <> '' then raise exception 'po-disc-1 self-check failed:% — nothing was applied', v_bad; end if;
end $$;
