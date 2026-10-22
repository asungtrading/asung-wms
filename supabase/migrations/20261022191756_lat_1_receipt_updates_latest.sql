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

-- ═══ lat-1 — 입고 완료가 공급처 「최근 단가(Latest)」 · 마지막 공급일을 고친다 (2026-10-22 · 판정 626 · 627 · Caleb 「컷오버전에 하자 · 고치는 시점은 입고가 완료된 시점」) ═══
--   지금까지 product_supplier.cost · last_supplied 를 바꾸는 것은 Cin7 적재뿐이었다(po-module 2989) — 컷오버 뒤 적재가 멈추면 다음 PO 기본 가격(po_lines_paste Fixed → Latest → 0) · 판매가 공식(price_1)이 낡은 값을 쓴다.
--   ① 도우미 po_receipt_latest_apply(receipt, post, staff)(속 · 실행권 없음) ② po_receipt_confirm_by 재발행 — ⓔ 원장 뒤 ⓔ-2 로 부른다 · 반환에 latest_updated · latest_skipped · 경고
--   ③ po_receipt_post_now_by 재발행 — 묶음 원장 뒤 그 묶음 줄만(먼저 반영된 몫도 이미 재고 · 확정 때 같은 값은 unchanged) · 값 = 할인 전 단가(627 · Cin7 Latest 실측 56/69 gross · net 0) · fixed_cost 무변(607)
--   원본: po_receipt_confirm_by = 20261021171531_rcv_3_short_keeps_po_open.sql:90(DB md5 d2734ecd59053597f3c91cf4c6b52b4f · 243 줄) · po_receipt_post_now_by = 20261020153535_rcv_1b_post_now.sql(30ab6c2aeb3a91903479d986eb028719 · 152 줄) — 바이트 + 더한 줄만(각 3 자리) · 새 md5 0437dd9fa83c9320f032f5db5ab3b889 · a246129b612853f2411594e7acc76d35
--   무접촉: po_receipt_confirm · po_receipt_post_now(셸) · inv_post_receipt · inv_layer_post_receipt · po_receipt_keep_open · 표 · 뷰 · 시퀀스 0(판정 615)
-- ═══ ① 도우미 — po_receipt_latest_apply(receipt, post, staff): 이 입고(또는 이 먼저 반영 묶음)의 줄마다 Latest(product_supplier.cost) · last_supplied 를 고친다 ═══
create function public.po_receipt_latest_apply(p_receipt_id uuid, p_post_id uuid, p_staff uuid) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- 판정 626 · 627: 값 = 그 PO 줄을 청구한 마지막 확정 인보이스 줄의 단가(할인 전 · 인보이스 통화) · 날짜 = 입고의 received_on · fixed_cost 는 안 건드린다
--   고치지 않는 줄: 확정 인보이스 줄 없음 · 단가 0(무상) · 받은 수량 0 · 연결 없음(latest_no_link) · 통화 다름(latest_currency_mismatch) · 더 새 공급일이 이미 있음(latest_older_skipped) · 같은 값(unchanged · 조용히)
--   꺼진 연결은 고친다(값은 사실) · 세트 줄(제품에 parent)은 낱개 단가(÷ pack_factor)로 낱개 행에(latest_set_converted) · 같은 날 둘이면 나중 확정이 이긴다(>= 로 덮는다)
declare
  v_r   public.po_receipt%rowtype;  v_po public.po%rowtype;
  v_upd jsonb := '[]'::jsonb;  v_skip jsonb := '[]'::jsonb;  v_warn text[] := '{}';
  x record;  v_ps record;  v_cur uuid;  v_target uuid;  v_unit numeric;  v_tsku text;
begin
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pr.parent_product_id, pr.pack_factor, sum(l.qty_ea) as qty,
           iv.unit_price as gross, iv.currency_id as inv_cur, iv.invoice_number
    from public.po_receipt_line l
    join public.po_line pl on pl.id = l.po_line_id
    join public.product pr on pr.id = pl.product_id
    left join lateral (select il.unit_price, i.currency_id, i.invoice_number
                         from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                        where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed' and il.is_payable and il.qty_ea > 0
                        order by i.confirmed_at desc nulls last, i.invoice_number desc limit 1) iv on true
    where l.receipt_id = p_receipt_id and (p_post_id is null or l.post_id = p_post_id)
    group by pl.id, pl.line_no, pl.product_id, pr.sku, pr.parent_product_id, pr.pack_factor, iv.unit_price, iv.currency_id, iv.invoice_number
    order by pl.line_no
  loop
    if coalesce(x.qty, 0) <= 0 then v_skip := v_skip || jsonb_build_object('sku', x.sku, 'reason', 'zero_qty'); continue; end if;
    if x.gross is null then v_skip := v_skip || jsonb_build_object('sku', x.sku, 'reason', 'no_confirmed_invoice_line'); continue; end if;
    if x.gross <= 0 then v_skip := v_skip || jsonb_build_object('sku', x.sku, 'reason', 'free'); continue; end if;
    v_target := x.product_id; v_unit := x.gross; v_tsku := x.sku;
    if x.parent_product_id is not null and coalesce(x.pack_factor, 0) > 0 then                       -- 세트로 주문한 줄 — 낱개 행 · 낱개 단가
      v_target := x.parent_product_id; v_unit := round(x.gross / x.pack_factor, 7);
      select p.sku into v_tsku from public.product p where p.id = v_target;
      v_warn := array_append(v_warn, 'latest_set_converted:' || x.sku);
    end if;
    select ps.id, ps.cost, ps.fixed_cost, ps.last_supplied, ps.is_active, coalesce(ps.currency_id, s.currency_id) as cur
      into v_ps from public.product_supplier ps join public.supplier s on s.id = ps.supplier_id where ps.product_id = v_target and ps.supplier_id = v_po.supplier_id;
    if not found then v_warn := array_append(v_warn, 'latest_no_link:' || v_tsku); v_skip := v_skip || jsonb_build_object('sku', v_tsku, 'reason', 'no_link'); continue; end if;
    if v_ps.cur is distinct from x.inv_cur then v_warn := array_append(v_warn, 'latest_currency_mismatch:' || v_tsku); v_skip := v_skip || jsonb_build_object('sku', v_tsku, 'reason', 'currency_mismatch'); continue; end if;
    if v_ps.last_supplied is not null and v_ps.last_supplied > v_r.received_on then v_warn := array_append(v_warn, 'latest_older_skipped:' || v_tsku); v_skip := v_skip || jsonb_build_object('sku', v_tsku, 'reason', 'newer_supply_exists', 'last_supplied', v_ps.last_supplied); continue; end if;
    if v_ps.cost is not distinct from v_unit and v_ps.last_supplied is not distinct from v_r.received_on then v_skip := v_skip || jsonb_build_object('sku', v_tsku, 'reason', 'unchanged'); continue; end if;
    update public.product_supplier set cost = v_unit, last_supplied = v_r.received_on, updated_by = p_staff where id = v_ps.id;
    v_upd := v_upd || jsonb_build_object('sku', v_tsku, 'product_id', v_target, 'supplier_id', v_po.supplier_id, 'supplier', (select s.name from public.supplier s where s.id = v_po.supplier_id),
                                         'old_cost', v_ps.cost, 'new_cost', v_unit, 'old_last_supplied', v_ps.last_supplied, 'new_last_supplied', v_r.received_on,
                                         'invoice_number', x.invoice_number, 'link_active', v_ps.is_active, 'po_line_no', x.line_no);
  end loop;
  return jsonb_build_object('updated', v_upd, 'skipped', v_skip, 'warnings', to_jsonb(v_warn));
end $$;
revoke all on function public.po_receipt_latest_apply(uuid, uuid, uuid) from public, anon, authenticated, service_role;
comment on function public.po_receipt_latest_apply(uuid, uuid, uuid) is 'lat-1 판정 626 · 627 — 입고 확정(po_receipt_confirm_by) · 먼저 반영(po_receipt_post_now_by)이 부르는 속 도우미: 줄마다 마지막 확정 인보이스 줄의 할인 전 단가를 product_supplier.cost 에 · last_supplied = received_on · 실행권 없음';

-- ═══ ② po_receipt_confirm_by 재발행 — 원본 rcv-3 바이트 + declare 1 줄 + ⓔ-2 3 줄 + 반환 1 줄 ═══
CREATE OR REPLACE FUNCTION public.po_receipt_confirm_by(p_staff uuid, p_receipt_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_keep      jsonb;                                           -- rcv-3(판정 598 · 599): 「아직 올 몫이 있나」 — po_receipt_keep_open 의 반환
  v_latest    jsonb;                                           -- lat-1(판정 626 · 627): Latest · last_supplied 갱신의 반환(updated · skipped · warnings)
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
  v_keep := public.po_receipt_keep_open(v_po.id, null);                                       -- rcv-3(판정 598 · 599): 열린 short(이 확정이 방금 남긴 것 포함) · split_shipment 가 있으면 PO 는 열린 채 — 다음 입고가 「확정 인보이스 − 받은 것」을 기대한다
  if (v_keep->>'keep_open')::boolean then
    select count(*) into v_n from public.po where id = v_po.id and status = 'confirmed';
    if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
    v_warn := array_append(v_warn, 'po_kept_open');
  else
  update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
  v_warn := array_append(v_warn, 'po_closed');
  end if;
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

  -- ═══ ⓔ-2 lat-1 · 판정 626 · 627: 입고 완료가 공급처 Latest(product_supplier.cost) · last_supplied 를 고친다 — 값 = 마지막 확정 인보이스 줄의 할인 전 단가 · 식은 도우미 한 곳(먼저 반영도 같은 도우미) · 경고는 모아 돌려준다 ═══
  v_latest := public.po_receipt_latest_apply(p_receipt_id, null, v_staff);
  v_warn := v_warn || (select coalesce(array_agg(w), '{}'::text[]) from jsonb_array_elements_text(v_latest->'warnings') w);

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
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', case when (v_keep->>'keep_open')::boolean then 'confirmed' else 'closed' end, 'closed_at', case when (v_keep->>'keep_open')::boolean then null else v_now end,
                              'kept_open', (v_keep->>'keep_open')::boolean, 'remaining_ea', v_keep->'remaining_ea', 'outlook', v_keep->'lines'),   -- rcv-3: 열린 채 남았나 · 남은 EA · 줄마다 상태
    'split', null,                                               -- inv-basis-2: 입고 확정은 가르지 않는다(키는 모양 무변 · 값은 늘 null · 덜 받은 몫은 diffs.short)
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'charges', jsonb_build_object('posted', v_cpost, 'errors', v_cerr),   -- inv-basis-3 · 판정 94(⑯): 이 발주의 확정 비용을 입고 순간 얹은 결과
    'adjustments', jsonb_build_object('posted', v_apost, 'errors', v_aerr),   -- po-disc-3 · 판정 391: 보류 원가 조정을 입고 순간 얹은 결과
    'latest_updated', v_latest->'updated', 'latest_skipped', v_latest->'skipped',   -- lat-1 · 판정 626 · 627: 고친 Latest 줄(sku · 공급처 · old/new cost · old/new last_supplied) · 건너뛴 줄과 이유
    'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ ③ po_receipt_post_now_by 재발행 — 원본 rcv-1b 바이트 + declare 1 줄 + 묶음 뒤 3 줄 + 반환 1 줄 ═══
CREATE OR REPLACE FUNCTION public.po_receipt_post_now_by(p_staff uuid, p_receipt_id uuid, p_lines jsonb, p_commit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_latest   jsonb;                                           -- lat-1(판정 626 · 627)
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
  -- lat-1 · 판정 626 · 627: 먼저 반영된 몫도 이미 재고다 — 이 묶음의 줄만 Latest · last_supplied 갱신(확정 때 같은 값을 한 번 더 써도 unchanged)
  v_latest := public.po_receipt_latest_apply(p_receipt_id, v_post_id, v_staff);
  v_warn := v_warn || (select coalesce(array_agg(w), '{}'::text[]) from jsonb_array_elements_text(v_latest->'warnings') w);

  return jsonb_build_object('committed', true, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'received_on', v_r.received_on,
                            'post_id', v_post_id, 'batch_no', v_batch, 'posted_by', v_staff, 'posted_at', v_now,
                            'rows', v_rows, 'qty_ea', v_qty, 'lines', v_lines, 'availability', v_avail,
                            'ledger', jsonb_build_object('rows_posted', v_ledger->'rows_posted', 'qty_posted', v_ledger->'qty_posted', 'lines', v_ledger->'lines'),
                            'layers', jsonb_build_object('layers_created', v_ledger->'layers'->'layers_created', 'layers_existing', v_ledger->'layers'->'layers_existing', 'cost_total_cad', v_ledger->'layers'->'cost_total_cad', 'lines', v_ledger->'layers'->'lines'),
                            'posted_before', jsonb_build_object('batches', v_batch - 1, 'qty', v_pb_q),
                            'latest_updated', v_latest->'updated', 'latest_skipped', v_latest->'skipped',   -- lat-1
                            'receipt_status', 'draft', 'po_status', v_po.status, 'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ 착지 — 재발행 둘 md5 · 도우미 ACL(아무도 못 부름) · 셸 · 원장 창구 무변 · 새 표 · 뷰 · 시퀀스 0 ═══
do $$
declare v_bad text := '';  v_n int;
begin
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_confirm_by') <> '0437dd9fa83c9320f032f5db5ab3b889' then v_bad := v_bad || ' confirm_by_body'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_post_now_by') <> 'a246129b612853f2411594e7acc76d35' then v_bad := v_bad || ' post_now_by_body'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm_by', 'po_receipt_post_now_by', 'po_receipt_latest_apply');
  if v_n <> 3 then v_bad := v_bad || format(' overloads_%s', v_n); end if;
  if (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-') || ':' || p.prosecdef::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm_by', 'po_receipt_post_now_by'))
     <> 'po_receipt_confirm_by:{postgres=X/postgres,service_role=X/postgres}:true po_receipt_post_now_by:{postgres=X/postgres,service_role=X/postgres}:true' then v_bad := v_bad || ' reissued_acl'; end if;
  if has_function_privilege('authenticated', 'public.po_receipt_latest_apply(uuid, uuid, uuid)', 'execute') or has_function_privilege('anon', 'public.po_receipt_latest_apply(uuid, uuid, uuid)', 'execute') or has_function_privilege('service_role', 'public.po_receipt_latest_apply(uuid, uuid, uuid)', 'execute') then v_bad := v_bad || ' helper_acl'; end if;
  if (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm', 'po_receipt_post_now', 'inv_post_receipt', 'inv_layer_post_receipt', 'po_receipt_keep_open'))
     <> 'inv_layer_post_receipt=4568a2cac4fc4814e20aa0805fef1cd9 inv_post_receipt=f94f20d56a0fa79dc10389e5a0b137e5 po_receipt_confirm=0476a2db6e3a2e2a0b3a80f2b657bf5d po_receipt_keep_open=0d6c9d33a6d9bd633c47d4411180ddbd po_receipt_post_now=7e006e7cce991b4551a555b9b2685c15' then v_bad := v_bad || ' others_changed'; end if;
  if v_bad <> '' then raise exception 'lat-1 landing check failed:%', v_bad; end if;
end $$;
