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

-- ─────────────────────────────────────────────────────────────
-- 콤보 오더의 돈 · 마무리 — Finalize 줄이기 · 백오더 여섯 · 인보이스 · 세금 · 크레딧 · 다시 매기기 · 합치기 (Asung-IMS · asm-2b2 · 2026-10-05)
--   정본(뒤에 적는다): so-module §44 — 판정 244(콤보는 팔 때 구성품을 바로 뺀다) · 245(크레딧의 상품 줄은 콤보 단위로만 · 구성품 하나는 「other」 금액 줄 · 재고는 조정으로) · 246(반쪽 콤보 픽은 Finalize 가 통째 콤보로 줄인다 · put_back)
--                      · asm 묶음 2(값은 콤보 줄 · 재고 · 예약 · 픽 · 출고 · 원가는 구성품 줄) · 3(콤보 줄만 고친다) · 4(콤보 단위 백오더 · 반쪽 없음) · 5(손님 문서엔 콤보 줄만 + includes) · 7(반품 · 크레딧은 콤보 단위)
--   앞 차수 asm-1(20261005192944) · asm-2a(20261005195104 · so_line.combo_line_id · combo_qty) · asm-2b1(20261005201634 · 창고 길 · so_ship 콤보 고리 · so_merge 거부) — 이 파일이 2b2(돈 · 마무리) · asm-3 은 화면
--   든 것:
--     1) 표 — so_invoice_line.combo_components jsonb(콤보 product 줄만 · [{so_line_id, product_id, sku, description, unit, qty_per_combo, qty}] · CHECK product 줄에만 · 옛 행 null)
--             so_credit_line.combo_credit_line_id(구성품 크레딧 줄 → 콤보 크레딧 줄 · cascade) · combo_qty · combo_components(콤보 크레딧 줄 표식 · 인보이스 줄 사본) · CHECK 넷(restock_ck 다시 · pair · child · parent · self) · 옛 행은 전부 null 이라 옛 뜻 그대로 통과
--             wms_order_finalize.put_back jsonb(⬜6 — Finalize 가 덜어낸 실물 목록 · 창고가 제자리에 놓는다 · 원장은 닿지 않는다)
--     2) 재발행 열다섯(마지막 정의 · DB prosrc md5 와 바이트 일치 확인 뒤 복사 · 바뀐 줄만 · 보고에 diff `<` 원문) —
--        so_finalize(20261002141516 · 40b437f4) · so_backorder_proceed(20260924145105 · 844000f9) · so_backorder_sweep(20260924153856 · 33c6e3f9) · so_backorder_supersede(20260925151823 · 4839e65b) · so_backorder_reopen(20260924145105 · 54c367a9)
--        so_backorder_list(20260924153856 · 70e57af7) · so_cancel(20260924145105 · 64b854ab) · so_tax_preview(20261002141516 · a0f1b638) · so_invoice_issue(20261002144956 · 229acbfc) · so_proforma(20261002141516 · 16bc1e2d)
--        so_credit_prepare(20261002144956 · 9c01cd88) · so_credit_issue(20261002144956 · 7414a52b) · so_reprice(20260923232500 · 2f1e287c) · so_line_requote(20260924202425 · b16f8b5d) · so_merge(20261005201634 · 0de19b67)
--   ⭐ 수요 줄 = 보통 줄 또는 콤보 줄(combo_line_id null) — 백오더 예약은 그대로 구성품 줄에 있지만 장부(so_backorder_close) · 목록 · 이어받기 · 만료 · proceed · 취소 · 병합은 수요 줄 단위(콤보 수 = min(구성품 예약 ÷ combo_qty)) · 다시 열면 구성품 줄에 콤보 수 × combo_qty
--   ⚠️ 재발행 없음 — so_backorder_record(줄 id 를 받을 뿐 · 콤보 줄 id 가 그대로 간다) · inv_post_credit(restock 줄 = bin 있는 product 줄 — 구성품 크레딧 줄만 걸리고 콤보 크레딧 줄은 bin 이 없어 저절로 빠진다 · 원 판매는 so_line_id → so) · inv_layer_post_credit · so_credit_cancel(원장 행 기준)
--        so_credit_detail · so_invoice_detail(to_jsonb(l) 이 새 칸을 싣는다) · so_credit_list · so_invoice_list(머리만) · so_detail(qty_credited = so_line_id 합 — 콤보 줄은 콤보 수 · 구성품 줄은 낱개 · 둘 다 제 뜻) · so_invoice_cancel · so_payment_* · so_customer_balance(줄을 안 본다)
--        so_unconfirm(so_backorder_reopen 이 콤보를 안다) · so_pos_complete · so_pos_open_list(totals 만 · 픽 계획은 구성품) · so_ship · so_divide(2b1 그대로)
--   ⚠️ 부분 유니크 인덱스 없음 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 정책 · 권한 무접촉(새 칸은 기존 select 정책 아래)
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) 표 — 인보이스 줄 includes · 크레딧 줄 매듭 · 창고 마무리 put_back ═══
alter table public.so_invoice_line add column combo_components jsonb;
alter table public.so_invoice_line add constraint so_invoice_line_combo_ck check (combo_components is null or kind = 'product');
comment on column public.so_invoice_line.combo_components is 'asm-2b2(묶음 5): on a combo product line — the components frozen at issue [{so_line_id, product_id, sku, description, unit, qty_per_combo, qty}] (qty = invoiced combos × qty_per_combo) · the paper says "Includes: 2 × …, 1 × …" · null on every other line · component so_lines are not invoice lines at all';

alter table public.so_credit_line
  add column combo_credit_line_id uuid references public.so_credit_line (id) on delete cascade,
  add column combo_qty numeric,
  add column combo_components jsonb;
create index so_credit_line_combo_idx on public.so_credit_line (combo_credit_line_id) where combo_credit_line_id is not null;
alter table public.so_credit_line drop constraint so_credit_line_restock_ck;
alter table public.so_credit_line
  add constraint so_credit_line_restock_ck      check (case when kind = 'product' then (restock_bin_id is null) = (not_restocked_reason is not null) or (combo_components is not null and restock_bin_id is null and not_restocked_reason is null)
                                                           else restock_bin_id is null and not_restocked_reason is null end),   -- 원문 + 콤보 크레딧 줄(구성품이 달린 줄)은 칸 · 사유 둘 다 null
  add constraint so_credit_line_combo_pair_ck   check ((combo_credit_line_id is null) = (combo_qty is null)),
  add constraint so_credit_line_combo_child_ck  check (combo_credit_line_id is null or (kind = 'product' and amount = 0 and tax_amount = 0 and so_invoice_line_id is null and combo_components is null)),
  add constraint so_credit_line_combo_parent_ck check (combo_components is null or (kind = 'product' and combo_credit_line_id is null)),
  add constraint so_credit_line_combo_self_ck   check (combo_credit_line_id is distinct from id);
comment on column public.so_credit_line.combo_credit_line_id is 'asm-2b2(묶음 7 · 판정 245): set on a component credit line — the combo credit line it hangs under (same credit note) · null on ordinary and combo lines · cascade';
comment on column public.so_credit_line.combo_qty            is 'asm-2b2: component credit line only — units of this component per one combo (copied from the invoice line) · qty_returned = combos returned × combo_qty';
comment on column public.so_credit_line.combo_components     is 'asm-2b2: combo credit line only — the invoice line''s combo_components copied · marks the line as a combo (no bin · no reason of its own · the money) · component lines carry the stock';
alter table public.wms_order_finalize add column put_back jsonb;
comment on column public.wms_order_finalize.put_back is 'asm-2b2(판정 246 · ⬜6): what so_finalize cut from the component picks so the combos ship whole — [{so_number, combo_sku, combo_line_no, line_id, sku, bin, qty}] · the goods are physically at the pack station and go back to that bin · the ledger never moved them (sale_out posts shipped picks only) · null when nothing was cut';

-- ═══ 2) so_finalize 재발행 — 원본 20261002141516_surcharge_2a.sql · 콤보 단위 removed(구성품 removed 거부 · 펼침) · 구성품 픽을 통째 콤보로 줄이기(마지막 칸부터 · put_back) · 줄인 picks 를 so_ship 에 · 반환 줄에 combo · combo_sku · put_back(미리 보기 · 실행) · wms_order_finalize.put_back ═══
create or replace function public.so_finalize(p_orders jsonb, p_commit boolean default true, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons  constant text[] := array['customer_removed', 'not_wanted', 'other'];
  v_staff    uuid;
  v_on       date;
  v_n        int;  v_cnt int;
  v_bad      text;
  e          jsonb;  x jsonb;
  v_so       public.so%rowtype;
  v_l        public.so_line%rowtype;
  v_c        public.customer%rowtype;
  v_acct     public.ref_account%rowtype;
  v_ch       public.so_charge%rowtype;
  q          record;
  v_qty      numeric;  v_remaining numeric;  v_new_unit numeric;
  v_reason   text;  v_key text;  k text;
  v_next     int;
  v_removed  jsonb;  v_repriced jsonb;  v_charges jsonb;  v_ship jsonb;  v_iss jsonb;
  v_surcharges jsonb;  v_spct numeric;  v_samt numeric;  v_slbl text;                 -- surcharge-2a(판정 230)
  v_orders   jsonb := '[]'::jsonb;
  v_groups   jsonb := '{}'::jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_ids      uuid[];
  v_warn     text[] := '{}';
  v_tw       text[];
  v_rm       jsonb;  v_pk jsonb;  v_pb jsonb;  v_put_back jsonb := '[]'::jsonb;  v_ord int;  v_cut numeric;  i int;  cb record;  kk record;   -- asm-2b2(판정 246 · 묶음 3 · 4): 콤보 단위 removed(펼친 목록 v_rm) · 구성품 픽을 통째 콤보로 줄이기(v_pk · put_back) — 별칭은 cp · p2 · z · t2(declare 변수와 다르게)
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 8: 마무리는 오더 담당(sales)부터 · 역할 문 없음(R5 의 예외)
  v_staff := public.so_current_staff();
  v_on := coalesce(p_shipped_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Ship date % is in the future — nothing was saved', v_on; end if;
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' or jsonb_array_length(p_orders) = 0 then
    raise exception 'p_orders must be a JSON array of orders — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_orders) t where jsonb_typeof(t) <> 'object' or nullif(t->>'so_id', '') is null) then
    raise exception 'Every order needs a so_id — nothing was saved';
  end if;
  select count(*), count(distinct t->>'so_id') into v_cnt, v_n from jsonb_array_elements(p_orders) t;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;
  -- ⑤-2b(판정 16 · ⬜7): picks 가 없으면 WMS 인계(wms_so_handoff)의 picks 를 쓴다(있으면 그대로 — 오피스가 고칠 길)
  select jsonb_agg(case when t.e ? 'picks' then t.e else t.e || jsonb_build_object('picks', (public.wms_so_handoff((t.e->>'so_id')::uuid))->'picks') end order by t.ord) into p_orders from jsonb_array_elements(p_orders) with ordinality t(e, ord);

  -- ① 검사 — 오더마다(잠금) · 하나라도 막히면 전체 거부 · 오더 번호로 말한다
  v_ord := -1;
  for e in select t from jsonb_array_elements(p_orders) t loop
    v_ord := v_ord + 1;                                                                 -- asm-2b2: 줄인 picks · 펼친 removed 를 이 자리에 되적는다(②~⑤ 가 읽는다)
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid for update;
    if not found then raise exception 'Order % not found — nothing was saved', e->>'so_id'; end if;
    if v_so.status <> 'packed' then
      raise exception 'Order % is % — only a packed order (warehouse work finished) can be finalized here — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if v_so.bill_to_customer_id is null then raise exception 'Order % has no bill-to customer — nothing was saved', v_so.so_number; end if;
    -- 뺀 몫(판정 5) — 모양 · 줄 · 수량 · 사유 · 중복
    if e ? 'removed' and jsonb_typeof(e->'removed') not in ('array', 'null') then
      raise exception 'Order %: removed must be an array of {line_id, qty, reason, note} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: removed line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      if v_l.combo_line_id is not null then                                                                                                    -- asm-2b2(묶음 3): 뺀 몫은 콤보 줄에만 · 구성품은 따라간다
        raise exception 'Order %: line % is a component of combo % (line %) — remove from the combo line instead — nothing was saved', v_so.so_number, v_l.line_no,
          (select p2.sku from public.so_line p2 where p2.id = v_l.combo_line_id), (select p2.line_no from public.so_line p2 where p2.id = v_l.combo_line_id);
      end if;
      if v_l.qty_removed > 0 then raise exception 'Order % line % already has a removed quantity — nothing was saved', v_so.so_number, v_l.line_no; end if;
      v_qty := case when (x->>'qty') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (x->>'qty')::numeric else null end;
      if v_qty is null or v_qty <= 0 then raise exception 'Order % line %: removed qty must be a positive number — nothing was saved', v_so.so_number, v_l.line_no; end if;
      if v_qty > v_l.qty_ordered then raise exception 'Order % line %: cannot remove % — only % ordered — nothing was saved', v_so.so_number, v_l.line_no, v_qty, v_l.qty_ordered; end if;
      v_reason := nullif(trim(x->>'reason'), '');
      if v_reason is null or v_reason <> all (c_reasons) then
        raise exception 'Order % line %: removed reason must be one of customer_removed, not_wanted, other — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
      if v_reason = 'other' and nullif(trim(x->>'note'), '') is null then
        raise exception 'Order % line %: reason other needs a note — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line is removed twice — nothing was saved', v_so.so_number;
    end if;
    -- asm-2b2(묶음 3): 뺀 몫을 펼친다 — 콤보 줄 removed n ⇒ 구성품 줄 removed = n × combo_qty(같은 사유 · 메모 · derived true) · 아래 검사 · ③ · ④ 가 전부 이 목록(v_rm)을 본다
    select coalesce(jsonb_agg(jsonb_build_object('line_id', z.line_id, 'qty', z.qty, 'reason', z.reason, 'note', z.note, 'derived', z.derived)), '[]'::jsonb) into v_rm
    from (select (t2->>'line_id')::uuid as line_id, (t2->>'qty')::numeric as qty, nullif(trim(t2->>'reason'), '') as reason, nullif(trim(t2->>'note'), '') as note, false as derived
            from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t2
          union all
          select cp.id, (t2->>'qty')::numeric * cp.combo_qty, nullif(trim(t2->>'reason'), ''), nullif(trim(t2->>'note'), ''), true
            from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t2 join public.so_line cp on cp.combo_line_id = (t2->>'line_id')::uuid) z;
    -- 판정 9 — 모든 줄을 다 뺐다 → 거부 + 길
    if not exists (select 1 from public.so_line l
                   left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
                   where l.so_id = v_so.id and l.qty_ordered - coalesce(rm.q, 0) > 0) then
      raise exception 'Order % — every line was removed, there is nothing to ship: roll the order back in WMS, then cancel it (so_unconfirm / so_cancel) — nothing was saved', v_so.so_number;
    end if;
    -- 픽 — 모양 · 줄 · 수량 · 목표 초과(칸은 실행 때 so_ship 이 본다)
    if e->'picks' is null or jsonb_typeof(e->'picks') <> 'array' or jsonb_array_length(e->'picks') = 0 then
      raise exception 'Order %: picks must be a JSON array of {line_id, bin, qty} — nothing was saved', v_so.so_number;
    end if;
    if exists (select 1 from jsonb_array_elements(e->'picks') t where nullif(t->>'line_id', '') is null or (t->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (t->>'qty')::numeric <= 0) then
      raise exception 'Order %: every pick needs a line_id and a positive qty — nothing was saved', v_so.so_number;
    end if;
    select string_agg(distinct t->>'line_id', ', ') into v_bad from jsonb_array_elements(e->'picks') t
    where not exists (select 1 from public.so_line l where l.id = (t->>'line_id')::uuid and l.so_id = v_so.id);
    if v_bad is not null then raise exception 'Order %: pick line % is not on this order — nothing was saved', v_so.so_number, v_bad; end if;
    select string_agg(distinct l.line_no::text, ', ') into v_bad from jsonb_array_elements(e->'picks') t join public.so_line l on l.id = (t->>'line_id')::uuid
    where l.so_id = v_so.id and exists (select 1 from public.so_line cp where cp.combo_line_id = l.id);                                           -- asm-2b2: 콤보 줄에는 픽이 없다(so_ship 과 같은 문장 · 미리 보기에서도 걸린다)
    if v_bad is not null then raise exception 'Order %: pick line % is a combo line — pick its component lines instead — nothing was saved', v_so.so_number, v_bad; end if;
    -- asm-2b2(판정 246 · 묶음 4): 콤보 줄마다 whole = least(남은 콤보 수, min(구성품 픽 ÷ combo_qty)) · 어느 구성품 픽이 whole × combo_qty 를 넘으면 넘는 몫을 그 줄 picks 의 마지막 칸부터 덜어낸다(wms_so_handoff 의 cut 모양)
    --   덜어낸 것은 put_back(SKU · 칸 · 수량 — 실물만 제자리에 · 장부는 출고 때 빠지므로 닿지 않는다) · 줄인 picks 를 so_ship 에 넘긴다(so_ship 의 반쪽 거부는 안전망으로 그대로) · 보통 줄의 과다 픽은 아래에서 여전히 거부
    v_pk := e->'picks';  v_pb := '[]'::jsonb;
    for cb in
      select p2.id, p2.line_no, p2.sku,
             least(p2.qty_ordered - coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_rm) t2 where (t2->>'line_id')::uuid = p2.id), 0),
                   (select min(floor(coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_pk) t2 where (t2->>'line_id')::uuid = cp.id), 0) / cp.combo_qty)) from public.so_line cp where cp.combo_line_id = p2.id)) as whole
      from public.so_line p2 where p2.so_id = v_so.id and exists (select 1 from public.so_line cp where cp.combo_line_id = p2.id) order by p2.line_no
    loop
      for kk in select cp.id, cp.sku, cp.combo_qty from public.so_line cp where cp.combo_line_id = cb.id order by cp.line_no loop
        v_cut := coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_pk) t2 where (t2->>'line_id')::uuid = kk.id), 0) - greatest(cb.whole, 0) * kk.combo_qty;
        i := jsonb_array_length(v_pk) - 1;
        while v_cut > 0 and i >= 0 loop
          if (v_pk->i->>'line_id')::uuid = kk.id and (v_pk->i->>'qty')::numeric > 0 then
            v_qty := least(v_cut, (v_pk->i->>'qty')::numeric);
            v_pb := v_pb || jsonb_build_object('so_number', v_so.so_number, 'combo_sku', cb.sku, 'combo_line_no', cb.line_no, 'line_id', kk.id, 'sku', kk.sku, 'bin', coalesce(v_pk->i->>'bin', ''), 'qty', v_qty);
            v_pk := jsonb_set(v_pk, array[i::text, 'qty'], to_jsonb((v_pk->i->>'qty')::numeric - v_qty));
            v_cut := v_cut - v_qty;
          end if;
          i := i - 1;
        end loop;
      end loop;
    end loop;
    select coalesce(jsonb_agg(t2), '[]'::jsonb) into v_pk from jsonb_array_elements(v_pk) t2 where (t2->>'qty')::numeric > 0;                     -- 0 이 된 픽은 뺀다(so_ship 은 양수만 받는다)
    v_put_back := v_put_back || v_pb;
    p_orders := jsonb_set(jsonb_set(jsonb_set(p_orders, array[v_ord::text, 'picks'], v_pk), array[v_ord::text, 'removed_expanded'], v_rm), array[v_ord::text, 'put_back'], v_pb);
    select string_agg(format('line %s picked %s but %s to ship', l.line_no, pk.q, l.qty_ordered - coalesce(rm.q, 0)), '; ' order by l.line_no) into v_bad
    from public.so_line l
    join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_pk) t where (t->>'line_id')::uuid = l.id) pk on true
    left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
    where l.so_id = v_so.id and l.combo_line_id is null and pk.q > l.qty_ordered - coalesce(rm.q, 0);                                           -- asm-2b2: 구성품 줄은 위에서 줄였다 · 보통 줄은 그대로 거부
    if v_bad is not null then raise exception 'Order %: over-pick — % — over-pick goes back to its bin — nothing was saved', v_so.so_number, v_bad; end if;
    -- 운임(판정 4 · so_charge_set 의 규칙)
    if e ? 'charges' and jsonb_typeof(e->'charges') not in ('array', 'null') then
      raise exception 'Order %: charges must be an array of {charge_id, name, amount, description, account_id} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      if nullif(trim(x->>'name'), '') is null then raise exception 'Order %: a charge needs a name — nothing was saved', v_so.so_number; end if;
      if (x->>'amount') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then raise exception 'Order %: charge % needs an amount — nothing was saved', v_so.so_number, trim(x->>'name'); end if;
      if (x->>'amount')::numeric < 0 then raise exception 'Order %: a charge cannot be negative — use a credit note — nothing was saved', v_so.so_number; end if;
      if nullif(x->>'charge_id', '') is not null and not exists (select 1 from public.so_charge c where c.id = (x->>'charge_id')::uuid and c.so_id = v_so.id) then
        raise exception 'Order %: charge % is not on this order — nothing was saved', v_so.so_number, x->>'charge_id';
      end if;
      if nullif(x->>'account_id', '') is not null and not exists (select 1 from public.ref_account a where a.id = (x->>'account_id')::uuid) then
        raise exception 'Order %: account % not found — nothing was saved', v_so.so_number, x->>'account_id';
      end if;
    end loop;
    -- 부가 요금(판정 230 · surcharge-2a) — 운임과 같은 자리 · 모양 · 줄 · 짝·범위·무상(so_surcharge_check · so_line_update 와 한 곳) · 중복
    if e ? 'surcharges' and jsonb_typeof(e->'surcharges') not in ('array', 'null') then
      raise exception 'Order %: surcharges must be an array of {line_id, surcharge_pct, surcharge_amount, surcharge_label} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: surcharge line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      v_spct := case when x ? 'surcharge_pct'    then nullif(x->>'surcharge_pct', '')::numeric    else v_l.surcharge_pct end;
      v_samt := case when x ? 'surcharge_amount' then nullif(x->>'surcharge_amount', '')::numeric else v_l.surcharge_amount end;
      v_slbl := case when x ? 'surcharge_label'  then nullif(trim(x->>'surcharge_label'), '')     else v_l.surcharge_label end;
      perform public.so_surcharge_check(v_spct, v_samt, v_slbl, v_l.free_reason);
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line has two surcharge changes — nothing was saved', v_so.so_number;
    end if;
  end loop;

  -- ②~⑤ 오더마다(주어진 순서) — 실행이면 쓰고 미리 보기면 계산만
  for e in select t from jsonb_array_elements(p_orders) t loop
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid;
    v_removed := '[]'::jsonb;  v_repriced := '[]'::jsonb;  v_charges := '[]'::jsonb;
    v_surcharges := '[]'::jsonb;                                                       -- surcharge-2a
    v_rm := coalesce(e->'removed_expanded', '[]'::jsonb);                               -- asm-2b2: ① 이 펼친 뺀 몫(구성품 derived 포함) · e->'picks' 는 줄인 picks

    -- ② 택배사 · 추적번호 · 배송 메모(열쇠가 온 것만) · 운임 줄(새로 · 또는 charge_id 로 고침 · 세금은 오더 규칙 · 기본 계정 _99_)
    if p_commit and (e ? 'carrier' or e ? 'tracking_number' or e ? 'shipping_notes') then
      update public.so s set
        carrier         = case when e ? 'carrier'         then nullif(trim(e->>'carrier'), '')         else s.carrier end,
        tracking_number = case when e ? 'tracking_number' then nullif(trim(e->>'tracking_number'), '') else s.tracking_number end,
        shipping_notes  = case when e ? 'shipping_notes'  then nullif(trim(e->>'shipping_notes'), '')  else s.shipping_notes end,
        updated_by      = v_staff
      where s.id = v_so.id;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      v_acct := null;
      if nullif(x->>'account_id', '') is not null then
        select * into v_acct from public.ref_account a where a.id = (x->>'account_id')::uuid;
      elsif nullif(x->>'charge_id', '') is null then
        select * into v_acct from public.ref_account a where a.code = '_99_';                      -- 기본 Freight Sales · 없으면 비우고 알린다(so_charge_set 과 같다)
        if not found then v_warn := array_append(v_warn, 'charge_account_unset:' || v_so.so_number); end if;
      end if;
      if p_commit then
        if nullif(x->>'charge_id', '') is null then
          select coalesce(max(c.line_no), 0) + 1 into v_next from public.so_charge c where c.so_id = v_so.id;
          insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by)
          values (v_so.id, v_next, trim(x->>'name'), nullif(trim(x->>'description'), ''), (x->>'amount')::numeric, v_so.tax_rule, v_acct.id, v_acct.code, v_staff)
          returning * into v_ch;
        else
          update public.so_charge c set
            name = trim(x->>'name'), description = nullif(trim(x->>'description'), ''), amount = (x->>'amount')::numeric, tax_rule = v_so.tax_rule,
            account_id = case when v_acct.id is not null then v_acct.id else c.account_id end, account_code = case when v_acct.id is not null then v_acct.code else c.account_code end, updated_by = v_staff
          where c.id = (x->>'charge_id')::uuid returning * into v_ch;
        end if;
        v_charges := v_charges || jsonb_build_object('charge_id', v_ch.id, 'line_no', v_ch.line_no, 'name', v_ch.name, 'amount', v_ch.amount, 'tax_rule', v_ch.tax_rule, 'account_code', v_ch.account_code);
      else
        v_charges := v_charges || jsonb_build_object('charge_id', nullif(x->>'charge_id', ''), 'name', trim(x->>'name'), 'amount', (x->>'amount')::numeric, 'tax_rule', v_so.tax_rule, 'account_code', v_acct.code, 'preview', true);
      end if;
    end loop;

    -- ②′ 부가 요금(판정 230 · surcharge-2a) — so_line_update 와 같은 패치 모양(열쇠가 온 칸만 · '' 은 비움) · 실행이면 쓰고 미리 보기면 old → new 만 · ③ 다시 견적 앞(%형은 저장값이 아니라 계산 때 단가를 읽는다)
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_spct := case when x ? 'surcharge_pct'    then nullif(x->>'surcharge_pct', '')::numeric    else v_l.surcharge_pct end;
      v_samt := case when x ? 'surcharge_amount' then nullif(x->>'surcharge_amount', '')::numeric else v_l.surcharge_amount end;
      v_slbl := case when x ? 'surcharge_label'  then nullif(trim(x->>'surcharge_label'), '')     else v_l.surcharge_label end;
      if p_commit then
        update public.so_line set surcharge_pct = v_spct, surcharge_amount = v_samt, surcharge_label = v_slbl, updated_by = v_staff where id = v_l.id;
      end if;
      v_surcharges := v_surcharges || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku,
                                                         'old', jsonb_build_object('surcharge_pct', v_l.surcharge_pct, 'surcharge_amount', v_l.surcharge_amount, 'surcharge_label', v_l.surcharge_label),
                                                         'new', jsonb_build_object('surcharge_pct', v_spct, 'surcharge_amount', v_samt, 'surcharge_label', v_slbl),
                                                         'surcharge_unit', public.so_line_surcharge_unit(v_l.unit_price, v_spct, v_samt));
      if v_spct is not null and v_spct > 100 then v_warn := array_append(v_warn, 'surcharge_pct_over_100:' || v_so.so_number || ':' || v_l.line_no); end if;
    end loop;

    -- ③ 뺀 몫(판정 5) + 시스템 줄 다시 견적(판정 6 · 할인만 · 남은 수량 > 0 · 사람이 정한 줄은 그대로)
    for x in select t from jsonb_array_elements(v_rm) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_qty := (x->>'qty')::numeric;  v_remaining := v_l.qty_ordered - v_qty;
      if p_commit then
        update public.so_line set qty_removed = v_qty, removed_reason = nullif(trim(x->>'reason'), ''), removed_note = nullif(trim(x->>'note'), ''), removed_at = now(), removed_by = v_staff, updated_by = v_staff
        where id = v_l.id;
      end if;
      v_removed := v_removed || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty_ordered', v_l.qty_ordered, 'qty_removed', v_qty, 'remaining', v_remaining,
                                                   'reason', nullif(trim(x->>'reason'), ''), 'free', v_l.free_reason is not null, 'derived', (x->>'derived')::boolean);
      if v_remaining > 0 and not (x->>'derived')::boolean and not v_l.price_override and v_l.discount_source is distinct from 'manual' then   -- asm-2b2: 구성품 줄은 다시 견적하지 않는다(값 0 · so_line_requote 가 거부한다)
        select * into q from public.so_line_quote(v_so, v_l.product_id, v_remaining);
        v_new_unit := case when v_l.list_price is null then null else v_l.list_price * (1 - q.discount_pct / 100) end;
        if p_commit then perform public.so_line_requote(v_l.id, v_remaining, false); end if;
        v_repriced := v_repriced || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty', v_remaining,
                                                       'old_unit_price', v_l.unit_price, 'new_unit_price', v_new_unit, 'old_discount_pct', v_l.discount_pct, 'new_discount_pct', q.discount_pct,
                                                       'old_discount_source', v_l.discount_source, 'new_discount_source', q.discount_source, 'changed', v_new_unit is distinct from v_l.unit_price);
      end if;
    end loop;

    -- ④ 출고(so_ship · 목표 = 주문 − 뺀 것 · 그 아래 차이만 pick_short 판정 7) — 미리 보기는 줄별 계산만(칸 검사·원장은 실행 때)
    if p_commit then
      v_ship := public.so_ship(v_so.id, e->'picks', v_staff, v_on);
      select array_agg(v_so.so_number || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_ship->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
      select jsonb_set(v_ship, '{lines}', coalesce(jsonb_agg(case when p2.sku is null then t2.x else t2.x || jsonb_build_object('combo_sku', p2.sku) end order by t2.ord), '[]'::jsonb)) into v_ship   -- asm-2b2: 구성품 줄에 combo_sku(콤보 줄의 combo true 는 so_ship 이 준다)
      from jsonb_array_elements(v_ship->'lines') with ordinality t2(x, ord) left join public.so_line cp on cp.id = (t2.x->>'line_id')::uuid left join public.so_line p2 on p2.id = cp.combo_line_id;
      if jsonb_array_length(coalesce(e->'put_back', '[]'::jsonb)) > 0 then                                                                           -- asm-2b2(⬜6): 되돌려 놓을 것을 창고 마무리 행에 남긴다(창고가 제자리에 놓는다 · 원장은 닿지 않는다) · 행이 없으면 반환만 + 경고
        update public.wms_order_finalize f set put_back = e->'put_back' where f.order_id = v_so.id;
        get diagnostics v_n = row_count;
        if v_n = 0 then v_warn := array_append(v_warn, 'put_back_unrecorded:' || v_so.so_number); end if;
      end if;
    else
      select jsonb_build_object('preview', true,
               'lines', coalesce(jsonb_agg((jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'ordered', l.qty_ordered, 'removed', coalesce(rm.q, 0), 'to_ship', l.qty_ordered - coalesce(rm.q, 0),
                                                              'picked', coalesce(pk.q, 0), 'short', l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0))
                                           || case when cm.is_combo then '{"combo": true}'::jsonb else '{}'::jsonb end || case when p2.sku is null then '{}'::jsonb else jsonb_build_object('combo_sku', p2.sku) end) order by l.line_no), '[]'::jsonb),   -- asm-2b2: 콤보 줄 picked = 통째 콤보 수 · 구성품 줄에 combo_sku · 보통 오더의 모양은 그대로
               'backorder_lines', count(*) filter (where l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0) > 0))
        into v_ship
      from public.so_line l
      left join public.so_line p2 on p2.id = l.combo_line_id
      cross join lateral (select exists (select 1 from public.so_line cp where cp.combo_line_id = l.id) as is_combo) cm
      left join lateral (select case when cm.is_combo then (select min(floor(coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(e->'picks') t2 where (t2->>'line_id')::uuid = cp.id), 0) / cp.combo_qty)) from public.so_line cp where cp.combo_line_id = l.id)
                                     else (select sum((t->>'qty')::numeric) from jsonb_array_elements(e->'picks') t where (t->>'line_id')::uuid = l.id) end as q) pk on true
      left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
      where l.so_id = v_so.id;
    end if;

    -- ⑤ 묶음 열쇠(판정 2) — 청구처 · 청구처 설정이 켜졌으면 오더의 손님(매장) · invoice_group 이 오면 그것(청구처 안에서 · 직원이 바꾼 묶음)
    select * into v_c from public.customer c where c.id = v_so.bill_to_customer_id;
    v_key := v_so.bill_to_customer_id::text || '|' || coalesce(nullif(trim(e->>'invoice_group'), ''), case when coalesce(v_c.invoice_split_by_store, false) then 'store:' || v_so.customer_id::text else '' end);
    v_groups := jsonb_set(v_groups, array[v_key], coalesce(v_groups->v_key, '[]'::jsonb) || to_jsonb(v_so.id));
    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'invoice_group', v_key, 'removed', v_removed, 'repriced', v_repriced, 'charges', v_charges, 'surcharges', v_surcharges, 'ship', v_ship, 'put_back', coalesce(e->'put_back', '[]'::jsonb));   -- asm-2b2: 오더마다 put_back
  end loop;

  -- ⑥ 발행 — 묶음마다 한 장(so_invoice_issue · 발행일 = 오늘 ims_today · §16 판정 5) · 미리 보기는 몇 장 · 어느 오더
  for k in select t.key_txt from jsonb_object_keys(v_groups) as t(key_txt) order by t.key_txt loop   -- 별칭은 변수 이름(x · e · k)과 다르게
    select array_agg(t.v::uuid) into v_ids from jsonb_array_elements_text(v_groups->k) as t(v);
    if p_commit then
      v_iss := public.so_invoice_issue(v_ids, v_staff, null);
      select array_agg((v_iss->>'invoice_number') || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
      v_invoices := v_invoices || jsonb_build_object('group', k, 'invoice_id', v_iss->'invoice_id', 'invoice_number', v_iss->'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                                                     'orders', (select jsonb_agg(o->>'so_number') from jsonb_array_elements(v_iss->'orders') o), 'totals', v_iss->'totals', 'warnings', v_iss->'warnings');
    else
      v_invoices := v_invoices || jsonb_build_object('group', k, 'preview', true, 'orders', (select jsonb_agg(s.so_number order by s.so_number) from public.so s where s.id = any(v_ids)), 'order_count', array_length(v_ids, 1));
    end if;
  end loop;

  return jsonb_build_object('committed', p_commit, 'shipped_on', v_on, 'orders', v_orders, 'invoices', v_invoices, 'invoice_count', jsonb_array_length(v_invoices), 'put_back', v_put_back, 'warnings', to_jsonb(v_warn));   -- asm-2b2(판정 246): put_back — 미리 보기 · 실행 둘 다 · 화면이 「Put back」 목록으로 그린다
end;
$$;

-- ═══ 3) so_backorder_proceed 재발행 — 원본 20260924145105_so_backorder_ledger.sql · 수요 줄 단위(콤보 줄 = 구성품 예약을 콤보 수로) · proceeded 는 구성품이 잡혔을 때 콤보 줄에 ═══
create or replace function public.so_backorder_proceed(p_so_id uuid, p_commit boolean default false) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_so public.so%rowtype;  v_res jsonb;  v_n int;
  v_bo jsonb := '[]'::jsonb;  bo record;  v_ended int := 0;                       -- ③b: 진행 전 열린 백오더 줄 · 잡힌 줄은 장부 proceeded
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed backorder still in IMS can proceed — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if v_so.location_id is null then raise exception 'Order % has no warehouse — nothing was saved', v_so.so_number; end if;
  begin
    select coalesce(jsonb_agg(jsonb_build_object('line_id', x.id, 'qty', q.qty_open, 'reserve_ids', to_jsonb(q.ids))), '[]'::jsonb) into v_bo     -- asm-2b2(묶음 4): 수요 줄 단위 — 보통 줄은 제 예약 · 콤보 줄은 구성품 예약을 콤보 수로(min(예약 ÷ combo_qty))
    from public.so_line x
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, array_agg(res.id) as ids
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = x.id or cp.combo_line_id = x.id) and res.released_at is null and res.kind = 'backorder') q
    where x.so_id = p_so_id and x.combo_line_id is null and q.qty_open is not null;                 -- ③b: 풀기 전에 담아 둔다
    update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
    from public.so_line x where x.id = r.so_line_id and x.so_id = p_so_id and r.released_at is null and r.kind in ('backorder', 'preorder');
    get diagnostics v_n = row_count;
    if v_n = 0 then
      raise exception 'Order % has no backorder or preorder lines to proceed — nothing was saved', v_so.so_number;
    end if;
    v_res := public.so_allocate_run(p_so_id, v_so.location_id, '{}'::uuid[], false, false, p_commit, v_staff) || jsonb_build_object('lines_released', v_n);
    -- ③b 판정 2: 엔진이 잡은 줄(이 오더에 남아 allocated 예약이 열린 줄)은 백오더가 끝났다 → 장부 proceeded · 옛 예약은 closed · 못 잡아 형제로 간 줄은 같은 줄이 이어진다(장부 없음)
    for bo in select (e->>'line_id')::uuid as line_id, (e->>'qty')::numeric as qty, (select array_agg(v::uuid) from jsonb_array_elements_text(e->'reserve_ids') v) as reserve_ids from jsonb_array_elements(v_bo) e loop
      if exists (select 1 from public.so_reserve a join public.so_line x on x.id = a.so_line_id where (x.id = bo.line_id or x.combo_line_id = bo.line_id) and x.so_id = p_so_id and a.released_at is null and a.kind = 'allocated') then   -- asm-2b2: 콤보는 구성품이 잡혔으면 끝났다(엔진이 통째로 잡는다)
        perform public.so_backorder_record(bo.line_id, 'proceeded', bo.qty, 0, 0, null, null, v_staff, null);
        update public.so_reserve set released_reason = 'closed', updated_by = v_staff where id = any(bo.reserve_ids);
        v_ended := v_ended + 1;
      end if;
    end loop;
    v_res := v_res || jsonb_build_object('backorder_lines_ended', v_ended);
    if not p_commit then
      raise exception using errcode = 'P0777', message = v_res::text;
    end if;
  exception when sqlstate 'P0777' then
    v_res := sqlerrm::jsonb;
  end;
  return v_res;
end;
$$;

-- ═══ 4) so_backorder_sweep 재발행 — 원본 20260924153856_so_backorder_free_owed.sql · 만료는 수요 줄 단위 · 콤보 줄 장부 + 구성품 예약 함께 닫힘 ═══
create or replace function public.so_backorder_sweep() returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  c_cap    constant int := 200;                      -- 회차 상한(오래된 order_date 먼저 · 남은 수는 remaining)
  v_cfg    text;
  v_days   int;
  v_today  date := public.ims_today();
  v_cut    date;
  s        record;
  r        record;
  v_open   int;
  v_reason text;
  v_orders int := 0;
  v_lines  int := 0;
  v_remaining int := 0;
  v_left   int;                                     -- 유상 줄을 닫은 뒤 남은 열린 예약(무상 백오더) · 0 일 때만 오더를 닫는다(판정 16)
  v_kept   int := 0;                                -- 무상 줄이 남아 닫지 않은 오더 수
  v_n      int;
  v_out    jsonb := '[]'::jsonb;
begin
  select k.value into v_cfg from public.inv_config k where k.key = 'so_backorder_expire_days';
  if v_cfg is null or v_cfg !~ '^[0-9]{1,4}$' or v_cfg::int <= 0 then
    raise exception 'inv_config.so_backorder_expire_days is missing or not a positive whole number (%) — the backorder sweep did not run', coalesce(v_cfg, 'null');
  end if;
  v_days := v_cfg::int;
  v_cut  := v_today - v_days;                        -- order_date < v_cut  ⇔  order_date + days < today

  for s in
    select x.id, x.so_number, x.order_date
    from public.so x
    where x.status = 'confirmed'
      and x.order_date < v_cut
      and not exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                      where l.so_id = x.id and rr.released_at is null and rr.kind <> 'backorder')   -- preorder · hold · allocated 가 하나라도 있으면 대상 아님
      and (exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                   where l.so_id = x.id and rr.released_at is null and rr.kind = 'backorder' and l.free_reason is null)     -- 판정 16: 유상 백오더가 하나라도 있거나
           or not exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                          where l.so_id = x.id and rr.released_at is null))                                                  --          열린 예약이 0 인 오더만 — 무상 줄뿐인 오더는 고르지 않는다(상한을 안 먹는다)
    order by x.order_date, x.so_number
    limit c_cap
  loop
    perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(s.so_number, '[a-z]+$', '')));
    v_open := 0;
    for r in                                                                       -- asm-2b2(묶음 4 · 7): 수요 줄 단위 — 콤보 줄은 구성품 예약을 콤보 수로 세고 장부는 콤보 줄에 · 구성품 예약은 함께 닫힌다(하나만 남는 상태 0)
      select x.id as so_line_id, q.qty_open, q.ids as reserve_ids
      from public.so_line x
      cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, array_agg(res.id) as ids
                          from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                          where (cp.id = x.id or cp.combo_line_id = x.id) and res.released_at is null and res.kind = 'backorder') q
      where x.so_id = s.id and x.combo_line_id is null and q.qty_open is not null
        and x.free_reason is null                                                  -- 판정 16: 유상 줄만 만료 · 무상 줄은 계속 기다린다(proceed · cancel 로만 끝난다)
      order by x.line_no
    loop
      perform pg_advisory_xact_lock(hashtext('so_reserve:' || cp.id::text)) from public.so_line cp where cp.id = r.so_line_id or cp.combo_line_id = r.so_line_id;
      perform public.so_backorder_record(r.so_line_id, 'expired', r.qty_open, 0, 0, null, null, null,
                                         format('Expired after %s days (order_date %s · today %s)', v_days, s.order_date, v_today));
      update public.so_reserve set released_at = now(), released_by = null, released_reason = 'closed' where id = any(r.reserve_ids) and released_at is null;
      v_open := v_open + 1;
    end loop;
    select count(*) into v_left from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id where l.so_id = s.id and rr.released_at is null;
    if v_left > 0 then                                -- 판정 16: 무상 백오더가 남았다 — 오더는 confirmed 그대로(「우리가 줄 것」 · 화면이 따로 · 매니저가 정리)
      v_kept := v_kept + 1;  v_lines := v_lines + v_open;
      v_out := v_out || jsonb_build_object('so_number', s.so_number, 'order_date', s.order_date, 'closed_reason', null, 'lines_expired', v_open, 'free_lines_left_open', v_left);
      continue;
    end if;
    v_reason := case when v_open > 0 then 'expired' else 'superseded' end;
    update public.so set status = 'cancelled', closed_reason = v_reason, closed_at = now(), cancelled_by = null,
           closed_note = case when v_open > 0 then format('Expired after %s days — %s backorder line(s) still open (order_date %s)', v_days, v_open, s.order_date)
                              else format('All lines already taken over or ended — closed by the backorder sweep after %s days (order_date %s)', v_days, s.order_date) end
    where id = s.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n <> 1 then
      raise exception 'Backorder order % was not closed — it may have been changed by someone else just now — the sweep stopped', s.so_number;
    end if;
    v_orders := v_orders + 1;  v_lines := v_lines + v_open;
    v_out := v_out || jsonb_build_object('so_number', s.so_number, 'order_date', s.order_date, 'closed_reason', v_reason, 'lines_expired', v_open);
  end loop;

  select count(*) into v_remaining
  from public.so x
  where x.status = 'confirmed' and x.order_date < v_cut
    and not exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                    where l.so_id = x.id and rr.released_at is null and rr.kind <> 'backorder')
    and (exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                 where l.so_id = x.id and rr.released_at is null and rr.kind = 'backorder' and l.free_reason is null)
         or not exists (select 1 from public.so_reserve rr join public.so_line l on l.id = rr.so_line_id
                        where l.so_id = x.id and rr.released_at is null));

  return jsonb_build_object('today', v_today, 'expire_days', v_days, 'cutoff_order_date_before', v_cut, 'cap', c_cap,
                            'orders_closed', v_orders, 'lines_expired', v_lines, 'orders_left_open_free', v_kept, 'remaining', v_remaining, 'orders', v_out);
end;
$$;

-- ═══ 5) so_backorder_supersede 재발행 — 원본 20260925151823_so_merge_b.sql · 수요 = 보통 줄 · 콤보 줄(구성품 줄 제외) · 후보도 같은 제품의 수요 줄(보통 ↔ 보통 · 콤보 ↔ 콤보) · 콤보 단위 이어받기(구성품 예약 함께) ═══
create or replace function public.so_backorder_supersede(p_so_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so    public.so%rowtype;
  v_base  text;
  k       record;
  t       record;
  v_rem   numeric;
  v_take  numeric;
  v_n     int := 0;
  v_out   jsonb := '[]'::jsonb;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if v_so.status <> 'confirmed' or v_so.confirmed_at is null then
    raise exception 'Order % is % — backorders are taken over at confirmation only — nothing was saved', v_so.so_number, v_so.status;
  end if;
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');

  for k in
    select l.product_id, sum(l.qty_ordered) as qty,
           (array_agg(l.id order by (s.id <> p_so_id), s.so_number, l.line_no))[1] as line_id
    from public.so_line l join public.so s on s.id = l.so_id and l.free_reason is null and l.combo_line_id is null     -- ③b′ 판정 13: 값을 매긴 줄만 센다(무상 줄은 우리가 준 것 · 수요가 아니다) · 무상 줄만 있는 제품은 이어받지 않는다 · 대표 줄도 유상 줄에서 · asm-2b2(묶음 4): 수요는 콤보 줄(콤보 제품)과 보통 줄 — 구성품 줄은 수요가 아니다
    where s.id = p_so_id
       or (s.split_from_id = p_so_id and s.confirmed_at = v_so.confirmed_at and s.created_at = v_so.confirmed_at)
    group by l.product_id
  loop
    v_rem := k.qty;
    for t in                                                                       -- asm-2b2(묶음 4): 후보도 수요 줄 — 같은 제품의 보통 줄(제 예약)끼리 · 같은 콤보 제품의 콤보 줄(구성품 예약을 콤보 수로)끼리 · 보통 줄 A 는 옛 콤보의 구성품 A 를 · 콤보의 구성품은 옛 보통 줄을 이어받지 않는다(product_id 가 가른다)
      select l.id as line_id, l.line_no, l.sku, s.so_number, s.order_date, s.location_name,
             (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
               where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind = 'backorder' and res.released_at is null) as qty_allocated
      from public.so_line l
      join public.so s on s.id = l.so_id
      where l.combo_line_id is null
        and exists (select 1 from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and res.kind = 'backorder' and res.released_at is null)
        and l.free_reason is null                                    -- 판정 15: 무상 줄 백오더는 이어받기 대상이 아니다(우리가 줄 것 · 손님의 수요가 아니다)
        and s.status = 'confirmed'
        and s.customer_id = v_so.customer_id
        and l.product_id = k.product_id
        and regexp_replace(s.so_number, '[a-z]+$', '') <> v_base
        and not public.so_merge_chain_reaches(s.id, p_so_id)                         -- ④b 판정 1(so-merge-1 · 2026-09-25): 후보 오더의 split 조상 중 하나라도 merged_into_id 사슬로 이 오더(T)에 닿으면 제외 — 원본의 백오더 형제는 못 보낸 몫이지 준 수요가 아니다(0-2 · 조상 전부 · so_unconfirm 의 merged 도 같은 사슬)
      order by s.order_date, s.created_at, s.so_number, l.line_no
    loop
      perform pg_advisory_xact_lock(hashtext('so_reserve:' || cp.id::text)) from public.so_line cp where cp.id = t.line_id or cp.combo_line_id = t.line_id;
      v_take := least(t.qty_allocated, v_rem);
      perform public.so_backorder_record(t.line_id, 'superseded', t.qty_allocated, v_take, t.qty_allocated - v_take, p_so_id, k.line_id, p_staff, null);
      update public.so_reserve res set released_at = now(), released_by = p_staff, released_reason = 'closed', updated_by = p_staff
      from public.so_line cp where cp.id = res.so_line_id and (cp.id = t.line_id or cp.combo_line_id = t.line_id) and res.kind = 'backorder' and res.released_at is null;   -- asm-2b2: 콤보 줄이면 구성품 예약이 함께 닫힌다
      v_rem := v_rem - v_take;
      v_n := v_n + 1;
      v_out := v_out || jsonb_build_object('so_number', t.so_number, 'line_no', t.line_no, 'sku', t.sku, 'order_date', t.order_date, 'location', t.location_name,
                                           'qty_open', t.qty_allocated, 'qty_taken', v_take, 'qty_unwanted', t.qty_allocated - v_take, 'taken_by_line_id', k.line_id);
    end loop;
  end loop;
  return jsonb_build_object('lines_closed', v_n, 'lines', v_out);
end;
$$;

-- ═══ 6) so_backorder_reopen 재발행 — 원본 20260924145105_so_backorder_ledger.sql · 콤보 줄 장부를 열면 구성품 줄에 콤보 수 × combo_qty ═══
create or replace function public.so_backorder_reopen(p_taken_by uuid[], p_staff uuid) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  c     record;
  v_n   int := 0;
  v_out jsonb := '[]'::jsonb;
begin
  for c in
    select x.id, x.so_line_id, x.qty_open, l.line_no, l.sku, s.so_number, s.status, t.so_number as taken_by
    from public.so_backorder_close x
    join public.so_line l on l.id = x.so_line_id
    join public.so s on s.id = l.so_id
    join public.so t on t.id = x.taken_by_so_id
    where x.taken_by_so_id = any(coalesce(p_taken_by, '{}'::uuid[])) and x.reopened_at is null
    order by s.so_number, l.line_no
  loop
    if c.status <> 'confirmed' then
      raise exception 'Backorder line % of % (taken over by %) cannot be reopened — that order is now % — nothing was saved', c.line_no, c.so_number, c.taken_by, c.status;
    end if;
    perform pg_advisory_xact_lock(hashtext('so_reserve:' || cp.id::text)) from public.so_line cp where cp.id = c.so_line_id or cp.combo_line_id = c.so_line_id;
    if exists (select 1 from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id where (cp.id = c.so_line_id or cp.combo_line_id = c.so_line_id) and r.released_at is null) then
      raise exception 'Backorder line % of % already has an open reservation — it cannot be reopened — nothing was saved', c.line_no, c.so_number;
    end if;
    update public.so_backorder_close set reopened_at = now(), reopened_by = p_staff, updated_by = p_staff where id = c.id and reopened_at is null;
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)                                               -- asm-2b2(묶음 4): 장부가 콤보 줄이면 예약은 구성품 줄에(콤보 수 × combo_qty) · 보통 줄은 그대로
    select cp.id, c.qty_open * coalesce(cp.combo_qty, 1), 'backorder', null from public.so_line cp
     where (cp.id = c.so_line_id and not exists (select 1 from public.so_line k2 where k2.combo_line_id = cp.id)) or cp.combo_line_id = c.so_line_id;
    v_n := v_n + 1;
    v_out := v_out || jsonb_build_object('so_number', c.so_number, 'line_no', c.line_no, 'sku', c.sku, 'qty_open', c.qty_open, 'taken_by', c.taken_by);
  end loop;
  return jsonb_build_object('lines_reopened', v_n, 'lines', v_out);
end;
$$;

-- ═══ 7) so_backorder_list 재발행 — 원본 20260924153856_so_backorder_free_owed.sql · 콤보 줄 하나로(qty = 콤보 수 · components) · 콤보 가용 = min(구성품 가용 ÷ (combo_qty × pack_factor)) · arrived = 구성품 입고 사건 ∧ 통째 1 개 이상 가용 · 구성품 SKU 로도 찾기 ═══
create or replace function public.so_backorder_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['customer_id','supplier_id','brand_id','sku','product_id','location_id','state','end_kind','order_from','order_to','ended_from','ended_to','arrived','notified','owed','limit','offset'];
  v_bad    text;
  v_state  text := coalesce(nullif(f->>'state', ''), 'all');
  v_limit  int  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 200), 1), 1000);
  v_offset int  := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_rows   jsonb;
  v_total  int;
  v_open   int;
  v_ended  int;
  v_open_owed int;                                 -- 열린 무상 백오더(우리가 줄 것) 수
  v_avail  jsonb := '{}'::jsonb;                   -- "warehouse_id:stock_pid" → available_ea (창고마다 so_available_many 한 번)
  v_pids   uuid[];
  w        record;
begin
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if v_state not in ('open', 'ended', 'all') then raise exception 'state must be open, ended or all'; end if;

  -- 낱개 제품 묶음(가용 계산용) — stable 함수라 임시 표를 쓰지 않는다(INSERT 금지) · 같은 합집합을 아래 bo 가 다시 읽는다
  select array_agg(distinct x.stock_pid) into v_pids
  from (
    select coalesce(p.parent_product_id, p.id) as stock_pid
    from public.so_reserve r join public.so_line l on l.id = r.so_line_id join public.product p on p.id = l.product_id
    where r.kind = 'backorder' and r.released_at is null
    union
    select coalesce(p.parent_product_id, p.id)
    from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.product p on p.id = l.product_id
    where c.reopened_at is null
    union                                                                                                       -- asm-2b2: 장부가 콤보 줄에 설 때 그 구성품의 재고 키(열린 콤보 백오더의 예약은 구성품 줄에 있어 첫 갈래가 이미 담는다)
    select coalesce(p.parent_product_id, p.id)
    from public.so_backorder_close c join public.so_line cp on cp.combo_line_id = c.so_line_id join public.product p on p.id = cp.product_id
    where c.reopened_at is null
  ) x;

  -- 가용 — 활성 창고마다 so_available_many 한 번(줄마다 부르지 않는다) · 이 목록의 낱개 제품 전부
  for w in select wh.id, wh.name from public.ref_warehouse wh where wh.is_active order by wh.name loop
    select coalesce(v_avail || jsonb_object_agg(w.id::text || ':' || m.stock_pid::text, m.available_ea), v_avail) into v_avail
    from public.so_available_many(v_pids, w.id) m;
  end loop;

  with bo as (
    select l.id as line_id, s.id as so_id, s.so_number, s.order_date, s.location_id, s.location_name, s.customer_id,
           l.product_id, coalesce(p.parent_product_id, p.id) as stock_pid, coalesce(pp.sku, p.sku) as base_sku, l.sku, l.product_name, l.pack_factor, l.qty_ordered,
           'open'::text as state, q.qty_open, q.since as backorder_since,
           null::text as end_kind, null::numeric as qty_taken, null::numeric as qty_unwanted, null::uuid as taken_by_so_id, null::timestamptz as ended_at, l.backorder_notified_at as notified_at,
           l.free_reason                                                                                          -- 판정 15·16: 무상 줄 = owed(우리가 줄 것)
    from (select distinct coalesce(cp.combo_line_id, cp.id) as line_id                                           -- asm-2b2(묶음 4): 수요 줄 — 예약은 구성품 줄에 있지만 목록은 콤보 줄 하나로(수량 = 콤보 수 · 구성품은 아래 components)
            from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id where r.kind = 'backorder' and r.released_at is null) d
    join public.so_line l on l.id = d.line_id
    cross join lateral (select min(floor(r.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, min(r.allocated_at) as since
                        from public.so_reserve r join public.so_line cp on cp.id = r.so_line_id
                        where (cp.id = l.id or cp.combo_line_id = l.id) and r.kind = 'backorder' and r.released_at is null) q
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    left join public.product pp on pp.id = p.parent_product_id
    union all
    select l.id, s.id, s.so_number, s.order_date, s.location_id, s.location_name, s.customer_id,
           l.product_id, coalesce(p.parent_product_id, p.id), coalesce(pp.sku, p.sku), l.sku, l.product_name, l.pack_factor, l.qty_ordered,
           'ended', c.qty_open,
           (select max(r2.allocated_at) from public.so_reserve r2 join public.so_line cp on cp.id = r2.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and r2.kind = 'backorder'),   -- asm-2b2: 콤보 줄의 예약은 구성품에
           c.end_kind, c.qty_taken, c.qty_unwanted, c.taken_by_so_id, c.ended_at, l.backorder_notified_at,
           l.free_reason
    from public.so_backorder_close c
    join public.so_line l on l.id = c.so_line_id
    join public.so s on s.id = l.so_id
    join public.product p on p.id = l.product_id
    left join public.product pp on pp.id = p.parent_product_id
    where c.reopened_at is null
  ),
  base as (
    select t.*,
           cu.name as customer_name,
           p.brand_id, p.brand_name,
           ps.supplier_id, su.name as supplier_name,
           ts.so_number as taken_by_so_number,
           (t.free_reason is not null) as owed,                                                                  -- 무상 줄 백오더 = 우리가 줄 것(판정 16 · 이어받기·만료 대상 아님)
           (public.ims_today() - t.order_date) as days_waiting,                                                  -- 기다린 날수(원래 주문일 기준 · 오래된 것을 매니저가 정리)
           cb.is_combo, cb.components,                                                                              -- asm-2b2: 콤보 줄 표시 · 구성품(sku · 이름 · combo_qty · base_sku)
           -- 입고됨(판정 6·7): 백오더가 생긴 뒤 그 창고에 po_in 또는 다른 창고에서 온 transfer_in(출발 줄이 있고 출발 창고 ≠ 도착 창고 · IN_TRANSIT 제외) · 조정·반품·조립 제외
           -- asm-2b2(⬜ 알림): 콤보는 「어느 구성품이든 자격 있는 입고가 있었다 ∧ 지금 통째 콤보가 1 개 이상 가용」 — 입고 사건이 있어야 하고(판정 6 · 반품 · 조정으로 생긴 가용은 세지 않는다) 반쪽 콤보로는 알리지 않는다(묶음 4)
           case when cb.is_combo then cb.arrived_any and coalesce(cb.avail_here, 0) >= 1 else exists (
             select 1 from public.inv_ledger g
             where g.sku = t.base_sku and g.warehouse = t.location_name and g.qty_delta > 0
               and g.occurred_on >= (t.backorder_since at time zone 'America/Toronto')::date
               and (g.event_type = 'po_in'
                    or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
                        and exists (select 1 from public.inv_ledger o
                                    where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                                      and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
           ) end as arrived,
           case when cb.is_combo then cb.avail_here else (v_avail->>(t.location_id::text || ':' || t.stock_pid::text))::numeric end as available_here,   -- asm-2b2: 콤보 가용 = min(구성품 가용 ÷ (combo_qty × pack_factor))
           case when cb.is_combo then cb.avail_other else (select jsonb_object_agg(wh.name, (v_avail->>(wh.id::text || ':' || t.stock_pid::text))::numeric)
              from public.ref_warehouse wh where wh.is_active and wh.id is distinct from t.location_id) end as available_other
    from bo t
    cross join lateral (                                                                                            -- asm-2b2: 콤보 줄의 구성품 · 콤보 단위 가용(이 창고 · 다른 창고) · 구성품 입고 사건
      select exists (select 1 from public.so_line cp where cp.combo_line_id = t.line_id) as is_combo,
             (select jsonb_agg(jsonb_build_object('sku', cp.sku, 'product_name', cp.product_name, 'combo_qty', cp.combo_qty, 'base_sku', coalesce(cpp.sku, cp2.sku)) order by cp.line_no)
                from public.so_line cp join public.product cp2 on cp2.id = cp.product_id left join public.product cpp on cpp.id = cp2.parent_product_id where cp.combo_line_id = t.line_id) as components,
             (select min(floor(coalesce((v_avail->>(t.location_id::text || ':' || coalesce(cp2.parent_product_id, cp2.id)::text))::numeric, 0) / (cp.combo_qty * cp.pack_factor)))
                from public.so_line cp join public.product cp2 on cp2.id = cp.product_id where cp.combo_line_id = t.line_id) as avail_here,
             (select jsonb_object_agg(wh.name, (select min(floor(coalesce((v_avail->>(wh.id::text || ':' || coalesce(cp2.parent_product_id, cp2.id)::text))::numeric, 0) / (cp.combo_qty * cp.pack_factor)))
                                                  from public.so_line cp join public.product cp2 on cp2.id = cp.product_id where cp.combo_line_id = t.line_id))
                from public.ref_warehouse wh where wh.is_active and wh.id is distinct from t.location_id) as avail_other,
             exists (select 1 from public.so_line cp join public.product cp2 on cp2.id = cp.product_id left join public.product cpp on cpp.id = cp2.parent_product_id
                       join public.inv_ledger g on g.sku = coalesce(cpp.sku, cp2.sku) and g.warehouse = t.location_name and g.qty_delta > 0
                                                 and g.occurred_on >= (t.backorder_since at time zone 'America/Toronto')::date
                                                 and (g.event_type = 'po_in'
                                                      or (g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT'
                                                          and exists (select 1 from public.inv_ledger o where o.doc_number = g.doc_number and o.sku = g.sku and o.event_type = 'transfer_out'
                                                                        and o.warehouse <> 'IN_TRANSIT' and o.warehouse <> g.warehouse)))
                      where cp.combo_line_id = t.line_id) as arrived_any
    ) cb
    join public.customer cu on cu.id = t.customer_id
    join public.product p on p.id = t.product_id
    left join public.product_supplier ps on ps.product_id = t.product_id and ps.is_default and ps.is_active
    left join public.supplier su on su.id = ps.supplier_id
    left join public.so ts on ts.id = t.taken_by_so_id
  ),
  filtered as (
    select * from base b
    where (f->>'customer_id' is null or b.customer_id = (f->>'customer_id')::uuid)
      and (f->>'supplier_id' is null or (f->>'supplier_id' = 'none' and b.supplier_id is null) or (f->>'supplier_id' <> 'none' and b.supplier_id = (f->>'supplier_id')::uuid))
      and (f->>'brand_id'    is null or b.brand_id = (f->>'brand_id')::uuid)
      and (f->>'sku'         is null or b.sku ilike (f->>'sku') || '%' or b.base_sku ilike (f->>'sku') || '%'
           or exists (select 1 from jsonb_array_elements(coalesce(b.components, '[]'::jsonb)) cj where cj->>'sku' ilike (f->>'sku') || '%' or cj->>'base_sku' ilike (f->>'sku') || '%'))   -- asm-2b2: 구성품 SKU 로도 콤보 백오더를 찾는다
      and (f->>'product_id'  is null or b.product_id = (f->>'product_id')::uuid)
      and (f->>'location_id' is null or b.location_id = (f->>'location_id')::uuid)
      and (v_state = 'all' or b.state = v_state)
      and (f->>'end_kind'    is null or b.end_kind = f->>'end_kind')
      and (f->>'order_from'  is null or b.order_date >= (f->>'order_from')::date)
      and (f->>'order_to'    is null or b.order_date <= (f->>'order_to')::date)
      and (f->>'ended_from'  is null or (b.ended_at at time zone 'America/Toronto')::date >= (f->>'ended_from')::date)
      and (f->>'ended_to'    is null or (b.ended_at at time zone 'America/Toronto')::date <= (f->>'ended_to')::date)
      and (f->>'arrived'     is null or b.arrived = (f->>'arrived')::boolean)
      and (f->>'notified'    is null or (b.notified_at is not null) = (f->>'notified')::boolean)
      and (f->>'owed'        is null or b.owed = (f->>'owed')::boolean)
  )
  select count(*), count(*) filter (where state = 'open'), count(*) filter (where state = 'ended'),
         count(*) filter (where state = 'open' and owed) as open_owed_n,
         coalesce((select jsonb_agg(jsonb_build_object(
             'so_id', x.so_id, 'so_number', x.so_number, 'order_date', x.order_date, 'line_id', x.line_id,
             'customer_id', x.customer_id, 'customer_name', x.customer_name,
             'product_id', x.product_id, 'sku', x.sku, 'base_sku', x.base_sku, 'product_name', x.product_name, 'pack_factor', x.pack_factor,
             'brand_id', x.brand_id, 'brand_name', x.brand_name, 'supplier_id', x.supplier_id, 'supplier_name', x.supplier_name,
             'location_id', x.location_id, 'location_name', x.location_name,
             'qty_ordered', x.qty_ordered, 'qty_open', x.qty_open, 'backorder_since', x.backorder_since,
             'state', x.state, 'end_kind', x.end_kind, 'qty_taken', x.qty_taken, 'qty_unwanted', x.qty_unwanted,
             'taken_by_so_id', x.taken_by_so_id, 'taken_by_so_number', x.taken_by_so_number, 'ended_at', x.ended_at,
             'notified_at', x.notified_at, 'notified_state', case when x.notified_at is not null then 'sent' else 'unknown_pre_ims' end,
             'free_reason', x.free_reason, 'owed', x.owed, 'days_waiting', x.days_waiting,
             'arrived', x.arrived, 'available_here', x.available_here, 'available_other', x.available_other,
             'is_combo', x.is_combo, 'components', x.components)                                                   -- asm-2b2: 콤보 줄 하나로 선다(qty = 콤보 수) · 구성품은 여기에
           order by x.customer_name, x.customer_id, x.base_sku, x.order_date, x.so_number, x.line_id)
           from (select * from filtered order by customer_name, customer_id, base_sku, order_date, so_number, line_id limit v_limit offset v_offset) x), '[]'::jsonb)
    into v_total, v_open, v_ended, v_open_owed, v_rows
  from filtered;

  return jsonb_build_object(
    'total', v_total, 'open', v_open, 'ended', v_ended, 'open_owed', v_open_owed, 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'notify_tracking', 'pre_ims — backorder_notified_at is not written yet (GAS sends arrival mail from Cin7); notified_state unknown_pre_ims is not "not sent"',
    'arrived_rule', 'po_in or transfer_in from another warehouse (same doc transfer_out at a different, non-IN_TRANSIT warehouse) at the order warehouse since the backorder was made; adjustments, credits, assemblies and arrivals without a departure leg do not count; a combo row is arrived when any component had such an arrival and at least one whole combo is available at the order warehouse',
    'rows', v_rows);
end;
$$;

-- ═══ 8) so_cancel 재발행 — 원본 20260924145105_so_backorder_ledger.sql · 취소 장부(cancelled)를 수요 줄 단위로(목록 밖 함수 — G 훑기에서 찾았다) ═══
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
                            'backorder_lines_recorded', v_bo, 'superseded_lines', v_taken, 'reopen_superseded', p_reopen_superseded, 'reopened', v_reopen, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 9) so_tax_preview 재발행 — 원본 20261002141516_surcharge_2a.sql · 줄 목록은 그대로(합계 불변) + 표시 셋(combo · combo_line_id · combo_sku) + combo_components(includes) ═══
create or replace function public.so_tax_preview(p_so_id uuid, p_on date default null, p_rule_id uuid default null, p_basis text default 'ordered') returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_on     date := coalesce(p_on, public.ims_today());
  v_pick   jsonb;
  v_rate   numeric;
  v_rule   text;
  v_source text;
  v_active boolean;                                           -- 세금 ② — 오더에 굳은 규칙이 비활성이 됐나
  v_lines  jsonb;  v_lines_tax numeric;  v_lines_amt numeric;
  v_chg    jsonb;  v_chg_tax numeric;    v_chg_amt numeric;
  v_od_amt numeric := 0;  v_od_tax numeric := 0;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;  v_sc_rate numeric;                      -- surcharge-2a(묶음 3 · 4): 줄마다 surcharge 합 · 그 세금 · surcharge 에 매길 세율
  v_warn   jsonb := '[]'::jsonb;
begin
  if p_basis not in ('ordered', 'shipped') then raise exception 'p_basis must be ordered or shipped'; end if;   -- ⓐ1 이견 4 — 인보이스는 보낸 수량(qty_shipped) 기준 · 초안·확정은 주문 수량
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found'; end if;

  if p_rule_id is not null then
    select r.name, r.rate_pct into v_rule, v_rate from public.ref_tax_rule r where r.id = p_rule_id and r.is_active and r.direction = 'sale';
    if v_rule is null then raise exception 'Tax rule % is not an active selling rule', p_rule_id; end if;
    v_source := 'explicit';
    v_pick := jsonb_build_object('rule_id', p_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on);
  elsif v_so.tax_rule_id is not null then                                              -- 세금 ② — 오더에 고른 규칙을 먼저(배송지에서 고른 것 ship_to · 사람이 정한 것 manual · 판정 8)
    select r.name, r.rate_pct, r.is_active into v_rule, v_rate, v_active from public.ref_tax_rule r where r.id = v_so.tax_rule_id;
    v_source := case when v_so.tax_rule_manual then 'manual' else 'ship_to' end;
    v_pick := jsonb_build_object('rule_id', v_so.tax_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on, 'manual', v_so.tax_rule_manual);
    if not v_active then v_warn := '["tax_rule_inactive"]'::jsonb; end if;
  else                                                                                 -- 규칙이 없는 초안(배송지 모름) — 지금 배송지로 다시 골라 보고 경고를 그대로 낸다
    v_pick := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, v_on, 'sale');
    v_rate := (v_pick->>'rate_pct')::numeric;  v_rule := v_pick->>'rule';
    v_source := 'ship_to';
    v_warn := coalesce(v_pick->'warnings', '[]'::jsonb);
  end if;

  v_sc_rate := v_rate;                                                                 -- ⭐ 36-e 76 — 회계사가 「surcharge 에 세금이 안 붙는다」 하면 이 줄 하나를 0 으로(surcharge 세금의 유일한 자리 · 묶음 4)
  select coalesce(jsonb_agg(jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'amount', a.amt, 'tax', public.so_tax_amount(a.amt, v_rate), 'free', l.free_reason is not null,
                                              'line_id', l.id, 'product_id', l.product_id, 'product_name', l.product_name, 'unit', l.unit, 'pack_factor', l.pack_factor,
                                              'qty', a.qty, 'qty_ordered', l.qty_ordered, 'qty_shipped', l.qty_shipped, 'unit_price', l.unit_price, 'list_price', l.list_price,
                                              'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override,
                                              'surcharge_label', l.surcharge_label, 'surcharge_unit', a.sc_unit, 'surcharge_total', s.sc_amt, 'surcharge_tax', public.so_tax_amount(s.sc_amt, v_sc_rate),   -- surcharge-2a(묶음 4): 줄마다 따로 반올림
                                              'combo', exists (select 1 from public.so_line cp where cp.combo_line_id = l.id), 'combo_line_id', l.combo_line_id, 'combo_sku', (select cp.sku from public.so_line cp where cp.id = l.combo_line_id),   -- asm-2b2(묶음 5): 줄 목록은 그대로(구성품 줄은 0 원 · 합계 불변) · 문서 창구(so_invoice_issue · so_proforma)가 이 표시로 구성품 줄을 뺀다
                                              'combo_components', (select jsonb_agg(jsonb_build_object('so_line_id', cp.id, 'product_id', cp.product_id, 'sku', cp.sku, 'description', cp.product_name, 'unit', cp.unit, 'qty_per_combo', cp.combo_qty, 'qty', a.qty * cp.combo_qty) order by cp.line_no) from public.so_line cp where cp.combo_line_id = l.id)) order by l.line_no), '[]'::jsonb),   -- 「includes …」 — 이 기준(basis)의 콤보 수 × 구성품 수
         coalesce(sum(public.so_tax_amount(a.amt, v_rate)), 0), coalesce(sum(a.amt), 0),
         coalesce(sum(s.sc_amt), 0), coalesce(sum(public.so_tax_amount(s.sc_amt, v_sc_rate)), 0)
    into v_lines, v_lines_tax, v_lines_amt, v_sc_amt, v_sc_tax
  from public.so_line l
  cross join lateral (select case when p_basis = 'shipped' then l.qty_shipped else l.qty_ordered end as qty,
                             case when p_basis = 'shipped' then round(l.qty_shipped * l.unit_price, 2) else public.so_line_total(l) end as amt,   -- ⓐ1: 보낸 수량 기준은 round(qty_shipped × unit_price, 2)(so_line_total 과 같은 식 · 수량만 다르다)
                             public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount) as sc_unit) a                      -- surcharge-2a(묶음 1 · 2): 개당(센트) · 수량은 물건값(amt)과 같은 것
  cross join lateral (select public.so_line_surcharge_total(a.sc_unit, a.qty) as sc_amt) s
  where l.so_id = p_so_id;

  if coalesce(v_so.order_discount_pct, 0) > 0 then                                  -- 오더 전체 할인은 제품 줄 합계에 한 번(D6 · 운임 제외) · 세금은 그 줄에 따로(판정 3 · SO-10842 −23.12)
    v_od_amt := -round(v_lines_amt * v_so.order_discount_pct / 100, 2);
    v_od_tax := public.so_tax_amount(v_od_amt, v_rate);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', c.line_no, 'name', c.name, 'amount', c.amount, 'tax', public.so_tax_amount(c.amount, v_rate),
                                              'charge_id', c.id, 'description', c.description, 'account_id', c.account_id, 'account_code', c.account_code) order by c.line_no), '[]'::jsonb),
         coalesce(sum(public.so_tax_amount(c.amount, v_rate)), 0), coalesce(sum(c.amount), 0)
    into v_chg, v_chg_tax, v_chg_amt
  from public.so_charge c where c.so_id = p_so_id;                                  -- 운임도 배송지 주의 규칙 · 줄마다(판정 6)

  return jsonb_build_object(
    'so_number', v_so.so_number, 'on', v_on, 'basis', p_basis, 'source', v_source, 'rule', v_pick,
    'lines', v_lines, 'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'amount', v_od_amt, 'tax', v_od_tax), 'charges', v_chg,
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'lines_tax', v_lines_tax, 'order_discount_amount', v_od_amt, 'order_discount_tax', v_od_tax,
                                 'charges_amount', v_chg_amt, 'charges_tax', v_chg_tax,
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                                     -- surcharge-2a(묶음 3): 물건값(lines_amount)과 따로 · 오더 할인 기준 밖
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt,
                                 'tax', case when v_rate is null then null else v_lines_tax + v_od_tax + v_chg_tax + v_sc_tax end,
                                 'total', case when v_rate is null then null else v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt + v_lines_tax + v_od_tax + v_chg_tax + v_sc_tax end),
    'warnings', v_warn);
end;
$$;

-- ═══ 10) so_invoice_issue 재발행 — 원본 20261002144956_surcharge_2b.sql · 구성품 줄은 송장에 넣지 않는다 · 콤보 줄 combo_components 굳힘 ═══
create or replace function public.so_invoice_issue(p_so_ids uuid[], p_staff uuid, p_issued_on date default null) returns jsonb
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_on       date := coalesce(p_issued_on, public.ims_today());
  v_n        int;
  v_cnt      int;
  v_bad      text;
  v_first    public.so%rowtype;
  v_so       public.so%rowtype;
  v_pt       public.ref_payment_term%rowtype;
  v_inv      public.so_invoice%rowtype;
  v_io       public.so_invoice_order%rowtype;
  v_pick     jsonb;
  v_prev     jsonb;
  v_rule_id  uuid;
  v_changed  boolean;
  v_rule     text;
  v_rate     numeric;
  v_ln       int := 0;
  v_lines_amt numeric := 0;  v_od_amt numeric := 0;  v_chg_amt numeric := 0;  v_tax numeric := 0;
  v_o_lines  numeric;  v_o_od numeric;  v_o_chg numeric;  v_o_tax numeric;
  v_sc_amt   numeric := 0;  v_o_sc numeric;  v_has_sc boolean;  v_sc_code text;  v_sc_acct public.ref_account%rowtype;   -- surcharge-2b(묶음 5 · 6)
  v_orders   jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
  e          jsonb;
  -- ⓑ2 자동 붙이기
  v_total    numeric;
  v_deposit  numeric := 0;
  v_balance  numeric := 0;
  v_avail    numeric;
  v_recv     numeric;
  v_left     numeric;
  v_take     numeric;
  v_applied  jsonb := '[]'::jsonb;
  v_a        public.so_payment_alloc%rowtype;
  pay        record;
  -- ⓒ2 크레딧부터(8-e · 판정 5)
  v_credit   numeric := 0;
  v_ca       public.so_credit_alloc%rowtype;
  cr         record;
begin
  if p_staff is null then raise exception 'so_invoice_issue needs the acting staff id — nothing was saved'; end if;
  if v_on > public.ims_today() then raise exception 'Invoice date % is in the future — nothing was saved', v_on; end if;
  v_cnt := coalesce(array_length(p_so_ids, 1), 0);
  if v_cnt = 0 then raise exception 'An invoice needs at least one order — nothing was saved'; end if;
  select count(distinct x) into v_n from unnest(p_so_ids) x;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;

  -- 잠금(번호 순) · 존재 · 상태 · 이미 담김 · 청구처 · 통화
  perform s.id from public.so s where s.id = any(p_so_ids) order by s.so_number for update;
  select count(*) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n <> v_cnt then raise exception 'Order not found — nothing was saved'; end if;
  select string_agg(s.so_number || ' (' || s.status || ')', ', ' order by s.so_number) into v_bad
  from public.so s where s.id = any(p_so_ids) and (s.status <> 'shipped' or s.shipped_at is null);
  if v_bad is not null then raise exception 'Only shipped orders can be invoiced — % — nothing was saved', v_bad; end if;
  select string_agg(s.so_number || ' is on invoice ' || i.invoice_number, ', ' order by s.so_number) into v_bad
  from public.so_invoice_order o join public.so s on s.id = o.so_id join public.so_invoice i on i.id = o.invoice_id
  where o.so_id = any(p_so_ids) and o.cancelled_at is null;
  if v_bad is not null then raise exception 'Order already invoiced — % — cancel that invoice first — nothing was saved', v_bad; end if;
  select string_agg(s.so_number, ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.bill_to_customer_id is null;
  if v_bad is not null then raise exception 'Order % has no bill-to customer — nothing was saved', v_bad; end if;
  select count(distinct s.bill_to_customer_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One invoice bills one customer — these orders have different bill-to customers, split them — nothing was saved'; end if;
  select count(distinct s.currency_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One invoice has one currency — these orders have different currencies, split them — nothing was saved'; end if;

  select * into v_first from public.so s where s.id = any(p_so_ids) order by s.so_number limit 1;
  perform 1 from public.customer c where c.id = v_first.bill_to_customer_id for update;   -- ⓑ2: 청구처 손님 행 잠금(잔액 검사 직렬화 · so_payment_* 창구와 같은 자물쇠)

  -- 결제조건 · 기한(판정 10)
  if v_first.payment_term_id is not null then
    select * into v_pt from public.ref_payment_term t where t.id = v_first.payment_term_id;
  end if;
  if v_pt.id is null then
    v_warn := v_warn || array['payment_term_missing', 'due_date_unknown'];
  elsif v_pt.net_days is null then
    v_warn := array_append(v_warn, 'due_date_unknown');
  end if;
  if coalesce(v_pt.is_split, false) then v_warn := array_append(v_warn, 'split_terms'); end if;
  if (select count(distinct coalesce(s.payment_term_id::text, '')) from public.so s where s.id = any(p_so_ids)) > 1 then v_warn := array_append(v_warn, 'payment_term_differs'); end if;
  if exists (select 1 from public.so s where s.id = any(p_so_ids)
              and (s.bill_to_name, s.bill_to_line1, s.bill_to_line2, s.bill_to_city, s.bill_to_state_province, s.bill_to_postal_code, s.bill_to_country)
                  is distinct from (v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country)) then
    v_warn := array_append(v_warn, 'bill_to_differs');
  end if;

  -- surcharge 계정(surcharge-2b · 묶음 6) — 담긴 오더에 보낸 surcharge 줄이 있으면 ⭐ 머리 insert(번호를 당긴다) 앞에서 계정을 잡는다 · 비었거나 · 없거나 · 꺼졌으면 surcharge 있는 발행만 막는다 · 없는 발행은 지금처럼
  select exists (select 1 from public.so_line l where l.so_id = any(p_so_ids) and l.surcharge_label is not null and l.qty_shipped > 0) into v_has_sc;
  if v_has_sc then
    select nullif(k.value, '') into v_sc_code from public.inv_config k where k.key = 'so_surcharge_account_code';
    if v_sc_code is null then raise exception 'Surcharge account is not set — set inv_config so_surcharge_account_code (e.g. _94_) before invoicing an order with a surcharge — nothing was saved'; end if;
    select * into v_sc_acct from public.ref_account a where a.code = v_sc_code;
    if v_sc_acct.id is null then raise exception 'Surcharge account % (inv_config so_surcharge_account_code) is not in the chart of accounts — nothing was saved', v_sc_code; end if;
    if not v_sc_acct.is_active then raise exception 'Surcharge account % (%) is inactive — pick an active account in inv_config so_surcharge_account_code — nothing was saved', v_sc_acct.code, v_sc_acct.name; end if;
  end if;

  -- 머리(합계는 0 으로 넣고 오더를 돌며 채운다 · CHECK 셋은 0 에서도 맞다)
  insert into public.so_invoice (bill_to_customer_id, bill_to_name, bill_to_line1, bill_to_line2, bill_to_city, bill_to_state_province, bill_to_postal_code, bill_to_country,
                                 issued_on, issued_by, payment_term_id, payment_term_name, due_on, currency_id, currency_code, updated_by)
  values (v_first.bill_to_customer_id, v_first.bill_to_name, v_first.bill_to_line1, v_first.bill_to_line2, v_first.bill_to_city, v_first.bill_to_state_province, v_first.bill_to_postal_code, v_first.bill_to_country,
          v_on, p_staff, v_pt.id, coalesce(v_pt.name, v_first.payment_term_name), case when v_pt.net_days is not null then v_on + v_pt.net_days end, v_first.currency_id, v_first.currency_code, p_staff)
  returning * into v_inv;

  -- 오더마다 — 규칙 · 금액(식 한 곳 · 보낸 수량) · 담긴 오더 줄 · 줄 사본 · 상태 전이
  for v_so in select * from public.so s where s.id = any(p_so_ids) order by s.so_number loop
    if v_so.tax_rule_manual then
      v_rule_id := v_so.tax_rule_id;
    else
      v_pick := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, v_on, 'sale');
      v_rule_id := (v_pick->>'rule_id')::uuid;
    end if;
    if v_rule_id is null then
      raise exception 'Order % has no tax rule for its ship-to address on % — pick a tax rule on the order — nothing was saved', v_so.so_number, v_on;
    end if;
    v_changed := v_rule_id is distinct from v_so.tax_rule_id;
    v_prev := public.so_tax_preview(v_so.id, v_on, v_rule_id, 'shipped');          -- explicit 규칙 · 활성 sale 아니면 이 함수가 거부한다
    v_rule := v_prev->'rule'->>'rule';  v_rate := (v_prev->'rule'->>'rate_pct')::numeric;
    v_o_lines := (v_prev->'totals'->>'lines_amount')::numeric;  v_o_od := (v_prev->'totals'->>'order_discount_amount')::numeric;
    v_o_chg   := (v_prev->'totals'->>'charges_amount')::numeric;  v_o_tax := (v_prev->'totals'->>'tax')::numeric;
    v_o_sc    := coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);                                             -- surcharge-2b: 이 오더 몫 · tax 는 2a 부터 surcharge 세금을 이미 품는다
    if v_o_lines + v_o_od + v_o_chg = 0 and not exists (select 1 from public.so_line l where l.so_id = v_so.id and l.qty_shipped > 0) then
      raise exception 'Order % shipped nothing — there is nothing to invoice — nothing was saved', v_so.so_number;
    end if;

    insert into public.so_invoice_order (invoice_id, so_id, so_number, customer_id,
                                         ship_to_company, ship_to_contact, ship_to_phone, ship_to_line1, ship_to_line2, ship_to_city, ship_to_state_province, ship_to_postal_code, ship_to_country,
                                         tax_rule_id, tax_rule, rate_pct, tax_source, draft_rule_changed,
                                         lines_amount, order_discount_pct, order_discount_amount, charges_amount, surcharge_amount, taxable_amount, tax_amount, total, updated_by)
    values (v_inv.id, v_so.id, v_so.so_number, v_so.customer_id,
            v_so.ship_to_company, v_so.ship_to_contact, v_so.ship_to_phone, v_so.ship_to_line1, v_so.ship_to_line2, v_so.ship_to_city, v_so.ship_to_state_province, v_so.ship_to_postal_code, v_so.ship_to_country,
            v_rule_id, v_rule, v_rate, case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, v_changed,
            v_o_lines, v_so.order_discount_pct, v_o_od, v_o_chg, v_o_sc, v_o_lines + v_o_od + v_o_chg + v_o_sc, v_o_tax, v_o_lines + v_o_od + v_o_chg + v_o_sc + v_o_tax, p_staff)
    returning * into v_io;

    for e in select x from jsonb_array_elements(v_prev->'lines') x loop                     -- 제품 줄(보낸 수량 > 0 만 · 안 나간 줄은 종이에 없다)
      if (e->>'qty')::numeric > 0 and nullif(e->>'combo_line_id', '') is null then                  -- asm-2b2(묶음 5): 구성품 줄은 종이에 없다 · 콤보 줄은 product 줄(qty = 나간 콤보 수) + 「includes …」 를 combo_components 에 굳힌다(so_line 이 뒤에 바뀌어도 그대로)
        v_ln := v_ln + 1;
        insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, unit, pack_factor, qty, list_price, discount_pct, discount_source, unit_price, amount, tax_amount, account_id, account_code, updated_by, combo_components)
        values (v_inv.id, v_io.id, v_ln, 'product', (e->>'line_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
                (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, e->>'discount_source', (e->>'unit_price')::numeric, (e->>'amount')::numeric, (e->>'tax')::numeric,
                v_so.sale_account_id, v_so.sale_account_code, p_staff, nullif(e->'combo_components', 'null'::jsonb));
        if coalesce((e->>'surcharge_total')::numeric, 0) > 0 then                        -- surcharge-2b(묶음 5): 그 상품 줄 바로 뒤 · 값은 so_tax_preview 줄 객체에서(2a 계산 한 곳 · 다시 세지 않는다) · 계정 = inv_config so_surcharge_account_code
          v_ln := v_ln + 1;
          insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_line_id, sku, description, qty, unit_price, amount, tax_amount, account_id, account_code, updated_by)
          values (v_inv.id, v_io.id, v_ln, 'surcharge', (e->>'line_id')::uuid, e->>'sku', e->>'surcharge_label', (e->>'qty')::numeric, (e->>'surcharge_unit')::numeric, (e->>'surcharge_total')::numeric, (e->>'surcharge_tax')::numeric,
                  v_sc_acct.id, v_sc_acct.code, p_staff);
        end if;
      end if;
    end loop;
    if v_o_od <> 0 then                                                                    -- 오더 전체 할인 줄 하나(D6 · 음수 · 세금 따로 · §16 판정 3)
      v_ln := v_ln + 1;
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, description, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'order_discount', format('Order discount %s%%', v_so.order_discount_pct), v_o_od, (v_prev->'order_discount'->>'tax')::numeric, v_so.sale_account_id, v_so.sale_account_code, p_staff);
    end if;
    for e in select x from jsonb_array_elements(v_prev->'charges') x loop                   -- 운임·서비스 줄 전부(0 도 · 무료 배송 흔적 · 1-p)
      v_ln := v_ln + 1;
      insert into public.so_invoice_line (invoice_id, invoice_order_id, line_no, kind, so_charge_id, description, amount, tax_amount, account_id, account_code, updated_by)
      values (v_inv.id, v_io.id, v_ln, 'charge', (e->>'charge_id')::uuid, e->>'name' || coalesce(' — ' || (e->>'description'), ''), (e->>'amount')::numeric, (e->>'tax')::numeric,
              (e->>'account_id')::uuid, e->>'account_code', p_staff);
    end loop;

    v_lines_amt := v_lines_amt + v_o_lines;  v_od_amt := v_od_amt + v_o_od;  v_chg_amt := v_chg_amt + v_o_chg;  v_tax := v_tax + v_o_tax;  v_sc_amt := v_sc_amt + v_o_sc;   -- surcharge-2b
    if v_changed then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    if coalesce(v_prev->'warnings', '[]'::jsonb) ? 'tax_rule_inactive' then v_warn := array_append(v_warn, 'tax_rule_inactive:' || v_so.so_number); end if;

    update public.so set status = 'fulfilled', invoiced_at = now(), closed_at = now(), updated_by = p_staff where id = v_so.id and status = 'shipped';   -- ⓑ2 판정 1: 문지기 짝 shipped→fulfilled · 끝 상태 closed_at 짝(so_closed_at_ck)
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Order % was not invoiced — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'tax_rule', v_rule, 'rate_pct', v_rate,
                                               'tax_source', case when v_so.tax_rule_manual then 'manual' else 'ship_to' end, 'draft_rule_changed', v_changed, 'totals', v_prev->'totals');
  end loop;

  -- 합계를 먼저 굳힌다(so_invoice_remaining 이 total 을 본다) · 잔액 항은 아직 0
  v_total := v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt + v_tax;                                                                           -- surcharge-2b
  update public.so_invoice set lines_amount = v_lines_amt, order_discount_amount = v_od_amt, charges_amount = v_chg_amt, surcharge_amount = v_sc_amt,
                               taxable_amount = v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt, tax_amount = v_tax, total = v_total, amount_due = v_total, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  -- ⓑ2 ① 담긴 오더를 대상으로 한 선결제(판정 4 · auto_deposit) — 받은 날 순 · 한도는 so_payment_alloc_add(인보이스 남은 금액 · 결제 남은 금액 · 받아 둔 돈)
  v_left := public.so_invoice_remaining(v_inv.id);
  for pay in
    select p.id, p.paid_on, p.method, p.reference,
           public.so_payment_remaining(p.id) as remaining
      from public.so_payment p
     where p.customer_id = v_inv.bill_to_customer_id and p.currency_id = v_inv.currency_id and p.status = 'active' and p.kind = 'payment'
       and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = any(p_so_ids))
     order by p.paid_on, p.created_at, p.id
  loop
    exit when v_left <= 0;
    if pay.remaining <= 0 then continue; end if;
    select b.received into v_recv from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id;
    v_take := least(pay.remaining, v_left, coalesce(v_recv, 0));
    if v_take <= 0 then continue; end if;
    v_a := public.so_payment_alloc_add(pay.id, v_inv.id, v_take, 'auto_deposit', p_staff);
    v_deposit := v_deposit + v_a.amount;  v_left := v_left - v_a.amount;
    v_applied := v_applied || jsonb_build_object('alloc_id', v_a.id, 'payment_id', pay.id, 'source', 'auto_deposit', 'amount', v_a.amount, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference);
  end loop;

  -- ⓒ2 ② 크레딧(진 빚 · 8-e 「크레딧부터」 · 판정 5) — issued 크레딧을 발행일 순으로 인보이스만큼만(auto) · so_credit_alloc_add
  if v_left > 0 then
    for cr in
      select c.id, c.credit_number, c.issued_on, public.so_credit_remaining(c.id) as remaining                                            -- so-credit-read-1 C1
        from public.so_credit c
       where c.customer_id = v_inv.bill_to_customer_id and c.currency_id = v_inv.currency_id and c.status = 'issued'
       order by c.issued_on, c.created_at, c.id
    loop
      exit when v_left <= 0;
      if cr.remaining <= 0 then continue; end if;
      v_take := least(cr.remaining, v_left);
      v_ca := public.so_credit_alloc_add(cr.id, v_inv.id, v_take, 'auto', p_staff);
      v_credit := v_credit + v_ca.amount;  v_left := v_left - v_ca.amount;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_ca.id, 'credit_id', cr.id, 'credit_number', cr.credit_number, 'source', 'auto_credit', 'amount', v_ca.amount, 'issued_on', cr.issued_on);
    end loop;
  end if;

  -- ⓑ2 ③ 손님의 받아 둔 돈(판정 5 · auto_balance) — 다른 오더 예약분 제외(received − reserved_deposit · so_payment_is_reserved) · 인보이스만큼만 · 받은 날 순 · ⓒ2: 크레딧은 위 ② 에서 썼으니 여기는 받아 둔 돈만(available 이 아니라 received − reserved)
  if v_left > 0 then
    select greatest(b.received - b.reserved_deposit, 0) into v_avail from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id;
    v_avail := coalesce(v_avail, 0);
    for pay in
      select p.id, p.paid_on, p.method, p.reference,
             public.so_payment_remaining(p.id) as remaining
        from public.so_payment p
       where p.customer_id = v_inv.bill_to_customer_id and p.currency_id = v_inv.currency_id and p.status = 'active' and p.kind = 'payment'
         and not public.so_payment_is_reserved(p.id)
       order by p.paid_on, p.created_at, p.id
    loop
      exit when v_left <= 0 or v_avail <= 0;
      if pay.remaining <= 0 then continue; end if;
      v_take := least(pay.remaining, v_left, v_avail);
      if v_take <= 0 then continue; end if;
      v_a := public.so_payment_alloc_add(pay.id, v_inv.id, v_take, 'auto_balance', p_staff);
      v_balance := v_balance + v_a.amount;  v_left := v_left - v_a.amount;  v_avail := v_avail - v_a.amount;
      v_applied := v_applied || jsonb_build_object('alloc_id', v_a.id, 'payment_id', pay.id, 'source', 'auto_balance', 'amount', v_a.amount, 'paid_on', pay.paid_on, 'method', pay.method, 'reference', pay.reference);
    end loop;
  end if;

  -- 종이에 찍히는 값을 굳힌다 — 받은 금액(deposit_applied) · 이전 잔액(balance_forward = −(크레딧 ② + 받아 둔 돈 ③) · 0 이하 · 봤는데 없으면 0 · 한 줄 8-c) · credit_applied(② 몫 · 회계 근거 · ⬜7) · 보내실 금액(amount_due · CHECK so_invoice_due_ck)
  update public.so_invoice set deposit_applied = v_deposit, credit_applied = v_credit, balance_forward = -(v_credit + v_balance), amount_due = v_total - v_deposit - v_credit - v_balance, updated_by = p_staff
  where id = v_inv.id returning * into v_inv;

  return jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'issued_on', v_on, 'due_on', v_inv.due_on,
                            'bill_to_customer_id', v_inv.bill_to_customer_id, 'bill_to_name', v_inv.bill_to_name, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code,
                            'orders', v_orders, 'lines', v_ln,
                            'totals', jsonb_build_object('lines_amount', v_inv.lines_amount, 'order_discount_amount', v_inv.order_discount_amount, 'charges_amount', v_inv.charges_amount, 'surcharge_amount', v_inv.surcharge_amount,
                                                         'taxable_amount', v_inv.taxable_amount, 'tax_amount', v_inv.tax_amount, 'total', v_inv.total,
                                                         'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward, 'amount_due', v_inv.amount_due,
                                                         'remaining', public.so_invoice_remaining(v_inv.id)),
                            'applied', v_applied,
                            'customer_balance', (select to_jsonb(b) from public.so_customer_balance(v_inv.bill_to_customer_id) b where b.currency_id = v_inv.currency_id),
                            'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 11) so_proforma 재발행 — 원본 20261002141516_surcharge_2a.sql · 손님 문서라 구성품 줄 제외(G 훑기에서 찾았다 · 묶음 5) ═══
create or replace function public.so_proforma(p_so_ids uuid[]) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_on       date := public.ims_today();
  v_n        int;
  v_cnt      int;
  v_bad      text;
  v_first    public.so%rowtype;
  v_so       public.so%rowtype;
  v_cust     uuid;
  v_prev     jsonb;
  v_orders   jsonb := '[]'::jsonb;
  v_deposits jsonb := '[]'::jsonb;
  v_lines_amt numeric := 0;  v_od_amt numeric := 0;  v_chg_amt numeric := 0;  v_tax numeric := 0;  v_tax_missing boolean := false;
  v_sc_amt numeric := 0;                                                                   -- surcharge-2a
  v_received numeric := 0;
  v_warn     text[] := '{}';
  v_tw       text[];
  v_bal      jsonb;
begin
  v_cnt := coalesce(array_length(p_so_ids, 1), 0);
  if v_cnt = 0 then raise exception 'A pro forma needs at least one order'; end if;
  select count(distinct x) into v_n from unnest(p_so_ids) x;
  if v_n <> v_cnt then raise exception 'The same order is listed twice'; end if;
  select count(*) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n <> v_cnt then raise exception 'Order not found'; end if;
  select string_agg(s.so_number || ' (' || s.status || ')', ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.status in ('fulfilled', 'cancelled');
  if v_bad is not null then raise exception 'A pro forma is for open orders only — % — a finished order has its invoice', v_bad; end if;
  select string_agg(s.so_number || ' is on invoice ' || i.invoice_number, ', ' order by s.so_number) into v_bad
  from public.so_invoice_order o join public.so s on s.id = o.so_id join public.so_invoice i on i.id = o.invoice_id where o.so_id = any(p_so_ids) and o.cancelled_at is null;
  if v_bad is not null then raise exception 'Order already invoiced — % — print the invoice instead', v_bad; end if;
  select count(distinct coalesce(s.bill_to_customer_id, s.customer_id)) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One pro forma bills one customer — these orders have different bill-to customers'; end if;
  select count(distinct s.currency_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One pro forma has one currency — these orders have different currencies'; end if;
  select * into v_first from public.so s where s.id = any(p_so_ids) order by s.so_number limit 1;
  v_cust := coalesce(v_first.bill_to_customer_id, v_first.customer_id);

  -- 오더마다 — 오늘 기준 예상 세금(so_tax_preview · 오더 규칙 · basis ordered: 발행 전 오더의 qty_removed 는 늘 0 · 0-11) · 규칙 없으면 세금 없이 경고
  for v_so in select * from public.so s where s.id = any(p_so_ids) order by s.so_number loop
    v_prev := public.so_tax_preview(v_so.id, v_on, null, 'ordered');
    v_lines_amt := v_lines_amt + (v_prev->'totals'->>'lines_amount')::numeric;
    v_od_amt    := v_od_amt + (v_prev->'totals'->>'order_discount_amount')::numeric;
    v_chg_amt   := v_chg_amt + (v_prev->'totals'->>'charges_amount')::numeric;
    v_sc_amt    := v_sc_amt + coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);   -- surcharge-2a(세금은 v_prev 의 tax 에 이미 들어 있다 · 묶음 4)
    if v_prev->'totals'->>'tax' is null then v_tax_missing := true; v_warn := array_append(v_warn, 'tax_rule_missing:' || v_so.so_number);
    else v_tax := v_tax + (v_prev->'totals'->>'tax')::numeric; end if;
    select array_agg(v_so.so_number || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_prev->'warnings', '[]'::jsonb)) as t(w);
    v_warn := v_warn || coalesce(v_tw, '{}');
    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'status', v_so.status, 'order_date', v_so.order_date, 'ref', v_so.ref,
                                               'ship_to', jsonb_build_object('company', v_so.ship_to_company, 'contact', v_so.ship_to_contact, 'line1', v_so.ship_to_line1, 'line2', v_so.ship_to_line2,
                                                                             'city', v_so.ship_to_city, 'state_province', v_so.ship_to_state_province, 'postal_code', v_so.ship_to_postal_code, 'country', v_so.ship_to_country),
                                               'tax_rule', v_prev->'rule'->>'rule', 'rate_pct', v_prev->'rule'->'rate_pct', 'tax_source', v_prev->>'source',
                                               'lines', (select coalesce(jsonb_agg(x order by (x->>'line_no')::int), '[]'::jsonb) from jsonb_array_elements(v_prev->'lines') x where nullif(x->>'combo_line_id', '') is null),   -- asm-2b2(묶음 5): 손님 문서 — 구성품 줄은 빼고 콤보 줄의 combo_components(includes)만
                                               'order_discount', v_prev->'order_discount', 'charges', v_prev->'charges', 'totals', v_prev->'totals');
  end loop;

  -- 받은 금액 = 이 오더들을 대상으로 한 활성 선결제의 남은 금액(⬜9 · 대상이 다른 오더에도 걸린 결제는 남은 금액 전부를 보인다 — 짐작 그대로 · 정본에 적는다)
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', z.id, 'paid_on', z.paid_on, 'method', z.method, 'reference', z.reference, 'amount', z.amount, 'remaining', z.remaining,
                                               'targets', (select jsonb_agg(s2.so_number order by s2.so_number) from public.so_payment_order o2 join public.so s2 on s2.id = o2.so_id where o2.payment_id = z.id)) order by z.paid_on, z.created_at), '[]'::jsonb),
         coalesce(sum(z.remaining), 0)
    into v_deposits, v_received
  from (select p.id, p.paid_on, p.method, p.reference, p.amount, p.created_at,
               public.so_payment_remaining(p.id) as remaining
          from public.so_payment p
         where p.customer_id = v_cust and p.currency_id = v_first.currency_id and p.status = 'active' and p.kind = 'payment'
           and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = any(p_so_ids))) z
  where z.remaining > 0;
  select to_jsonb(b) into v_bal from public.so_customer_balance(v_cust) b where b.currency_id = v_first.currency_id;

  return jsonb_build_object(
    'document', 'PRO FORMA', 'note', 'This is not an invoice', 'invoice_number', null, 'as_of', v_on,
    'customer_id', v_cust, 'bill_to_name', v_first.bill_to_name, 'currency_code', v_first.currency_code,
    'orders', v_orders,
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'charges_amount', v_chg_amt, 'surcharge_amount', v_sc_amt,   -- surcharge-2a(묶음 3)
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt,
                                 'tax', case when v_tax_missing then null else v_tax end,
                                 'total', case when v_tax_missing then null else v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt + v_tax end,
                                 'received', v_received,
                                 'balance_due', case when v_tax_missing then null else v_lines_amt + v_od_amt + v_chg_amt + v_sc_amt + v_tax - v_received end),
    'deposits', v_deposits,
    'customer_balance', v_bal,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 12) so_credit_prepare 재발행 — 원본 20261002144956_surcharge_2b.sql · 콤보 인보이스 줄 = 반품 단위 · 구성품마다 restock_bin_default ═══
create or replace function public.so_credit_prepare(p_invoice_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with inv as (
    select i.*, cu.name as customer_name, public.ims_today() as today,
           (select s.location_id from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = i.id order by o.so_number limit 1) as wh_id   -- 발행 창구 :996 과 같은 줄(원판매 첫 오더의 창고)
    from public.so_invoice i left join public.customer cu on cu.id = i.bill_to_customer_id
    where i.id = p_invoice_id
  ),
  cfg as (
    select (select nullif(k.value, '')::int     from public.inv_config k where k.key = 'so_credit_restock_fee_days')         as fee_days,
           (select nullif(k.value, '')::numeric from public.inv_config k where k.key = 'so_credit_restock_fee_pct')          as fee_pct,
           (select nullif(k.value, '')          from public.inv_config k where k.key = 'so_credit_restock_fee_account_code') as fee_account_code
  )
  select jsonb_build_object(
    'invoice', jsonb_build_object('id', inv.id, 'invoice_number', inv.invoice_number, 'status', inv.status, 'creditable', (inv.status = 'issued'), 'issued_on', inv.issued_on,
                                  'days_since_invoice', inv.today - inv.issued_on, 'customer_id', inv.bill_to_customer_id, 'customer_name', inv.customer_name, 'bill_to_name', inv.bill_to_name,
                                  'currency_id', inv.currency_id, 'currency_code', inv.currency_code, 'total', inv.total, 'remaining', public.so_invoice_remaining(inv.id)),
    'warehouse', (select jsonb_build_object('warehouse_id', w.id, 'warehouse_name', w.name, 'is_active', w.is_active) from public.ref_warehouse w where w.id = inv.wh_id),
    'lines', (select coalesce(jsonb_agg(jsonb_build_object(
                'so_invoice_line_id', l.id, 'line_no', l.line_no, 'kind', l.kind, 'sku', l.sku, 'description', l.description, 'unit', l.unit, 'pack_factor', l.pack_factor,
                'qty_sold', l.qty,
                -- ⚠️ 복사 식(0-5): so_credit_issue 20260925012354:1055~1056 의 「이미 반품」과 글자까지 같아야 창구가 거부하지 않는다 · ⬜ so_credit_line_returned(so_invoice_line_id) 류 함수로 떼고 발행 창구와 함께 부른다(다음 차수)
                'qty_credited', case when l.kind = 'product' then (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,
                'qty_returnable', case when l.kind = 'product' then l.qty - (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,
                'amount', l.amount,
                -- charge 줄의 「이미 반품」은 금액(발행 창구 :1099~1103 의 v_already 와 같은 뜻)
                'amount_credited', case when l.kind in ('charge', 'surcharge') then (select coalesce(sum(cl.amount), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_invoice_line_id = l.id and c.status = 'issued') end,   -- surcharge-2b: surcharge 줄은 보이기만(자동 · 손으로 못 보낸다)
                'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'rate_pct', io.rate_pct, 'tax_rule', io.tax_rule, 'tax_amount', l.tax_amount, 'account_code', l.account_code,
                'product_id', sl.product_id, 'stock_product_id', coalesce(pr.parent_product_id, pr.id), 'stock_sku', coalesce(pp.sku, pr.sku),
                -- 되돌려 놓을 칸 기본값 — 발행 창구 :1077 과 같은 길(ims_last_bin(낱개 제품, 창고) · ④a1 뒤로 보관용 아님 먼저 · 없으면 null → 사람이 고르거나 안 돌아옴으로)
                'restock_bin_default', case when l.kind = 'product' and l.combo_components is null and inv.wh_id is not null and pr.id is not null
                                            then public.ims_last_bin(array[coalesce(pr.parent_product_id, pr.id)], inv.wh_id) -> coalesce(pr.parent_product_id, pr.id)::text end,
                -- asm-2b2(묶음 7 · 판정 245): 콤보 인보이스 줄 = 반품 단위(qty 는 콤보 수) · 구성품마다 돌아가는 칸 기본(ims_last_bin · 낱개 제품 · 그 창고) — 보통 줄은 null
                'combo_components', (select jsonb_agg(cj || jsonb_build_object('restock_bin_default', case when inv.wh_id is not null and cpr.id is not null then public.ims_last_bin(array[coalesce(cpr.parent_product_id, cpr.id)], inv.wh_id) -> coalesce(cpr.parent_product_id, cpr.id)::text end) order by cj->>'sku')
                                       from jsonb_array_elements(l.combo_components) cj left join public.product cpr on cpr.id = nullif(cj->>'product_id', '')::uuid))
              order by l.line_no), '[]'::jsonb)
              from public.so_invoice_line l
              join public.so_invoice_order io on io.id = l.invoice_order_id
              left join public.so_line sl on sl.id = l.so_line_id
              left join public.product pr on pr.id = sl.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              where l.invoice_id = inv.id and l.kind in ('product', 'charge', 'surcharge')),
    'restock_fee', jsonb_build_object('days', cfg.fee_days, 'pct', cfg.fee_pct, 'account_code', cfg.fee_account_code,
                                      'days_since_invoice', inv.today - inv.issued_on,
                                      'applies', (cfg.fee_days is not null and inv.today - inv.issued_on > cfg.fee_days),
                                      'note', 'notice only — the preview so_credit_issue(p, false) proposes the amount (fee_suggested); the account must be picked when account_code is null'),
    'already_credited', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'reason', c.reason, 'total', c.total, 'remaining', public.so_credit_remaining(c.id)) order by c.credit_number), '[]'::jsonb)
                         from public.so_credit c where c.invoice_id = inv.id),
    'vocab', jsonb_build_object('reasons', '["customer_return","damaged","billing_error","other"]'::jsonb,
                                'not_restocked_reasons', '["damaged","b_grade","not_returned","other"]'::jsonb,
                                'line_kinds', '["product","freight","tax","other","restocking_fee"]'::jsonb)
  )
  from inv, cfg;
$$;

-- ═══ 13) so_credit_issue 재발행 — 원본 20261002144956_surcharge_2b.sql · 콤보 크레딧 줄 + 구성품 크레딧 줄(금액 0 · 제 칸 또는 사유 · components[] · 줄 수준 기본값) · 구성품 하나만의 상품 줄 거부 ═══
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

  -- 둘째 바퀴 — Restocking fee(판정 4·5·7 · 0-8): 기본 −round(Σ제품 × pct/100, 2) · 계정 = 지정 → 설정 → 거부 · 세율 = 첫 제품 줄(섞이면 경고) · 세금도 음수
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
      if v_amount is null then v_amount := -round(v_product_amt * coalesce(nullif(x->>'pct', '')::numeric, v_fee_pct, 0) / 100, 2); end if;
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
    v_fee_sugg := jsonb_build_object('days_since_invoice', v_on - v_origin_on, 'pct', v_fee_pct, 'amount', -round(v_product_amt * coalesce(v_fee_pct, 0) / 100, 2), 'account_code', v_fee_acct_code);
  end if;
  if v_ln = 0 then raise exception 'A credit note needs at least one line — nothing was saved'; end if;

  if not p_commit then
    return jsonb_build_object('committed', false, 'issued_on', v_on, 'customer_id', v_cust, 'currency_code', v_cur.code, 'warehouse_id', v_w.id, 'warehouse_name', v_w.name,
                              'origin', case when v_cin7 then jsonb_build_object('cin7_invoice_number', v_cin7_inv, 'cin7_order_number', v_cin7_ord, 'cin7_invoice_date', v_cin7_date, 'tax_rule', v_rule.name, 'rate_pct', v_rule.rate_pct)
                                             else jsonb_build_object('invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'issued_on', v_inv.issued_on) end,
                              'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_lines_amt, 'fee_amount', v_fee_amt, 'surcharge_amount', v_sc_amt, 'tax_amount', v_tax_amt, 'total', v_lines_amt + v_fee_amt + v_sc_amt + v_tax_amt, 'restock_lines', v_restock_n),
                              'fee_suggested', v_fee_sugg, 'ledger', null, 'warnings', to_jsonb(v_warn));
  end if;

  insert into public.so_credit (customer_id, currency_id, currency_code, invoice_id, cin7_invoice_number, cin7_order_number, cin7_invoice_date, origin_invoice_on, reason, note,
                                warehouse_id, warehouse_name, tax_rule_id, tax_rule, rate_pct, issued_on, issued_by, lines_amount, fee_amount, surcharge_amount, tax_amount, total, created_by, updated_by)
  values (v_cust, v_cur.id, v_cur.code, v_inv.id, v_cin7_inv, v_cin7_ord, v_cin7_date, v_origin_on, v_reason, nullif(trim(p->>'note'), ''),
          v_w.id, v_w.name, v_rule.id, v_rule.name, v_rule.rate_pct, v_on, v_staff, v_lines_amt, v_fee_amt, v_sc_amt, v_tax_amt, v_lines_amt + v_fee_amt + v_sc_amt + v_tax_amt, v_staff, v_staff)
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
                            'lines', v_lines, 'totals', jsonb_build_object('lines_amount', v_cr.lines_amount, 'fee_amount', v_cr.fee_amount, 'surcharge_amount', v_cr.surcharge_amount, 'tax_amount', v_cr.tax_amount, 'total', v_cr.total, 'restock_lines', v_restock_n),
                            'fee_suggested', v_fee_sugg, 'ledger', v_ledger, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 14) so_reprice 재발행 — 원본 20260923232500_so_deal_rpc.sql · 구성품 줄 제외(kept · combo_component) ═══
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
  if v_so.order_discount_source is distinct from 'manual' then
    select * into od from public.so_order_discount(p_so_id);
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id,
                         order_discount_source = case when od.pct is null then null else 'deal' end,
                         reprice_suggested_at = null, updated_by = v_staff
    where id = p_so_id and status = 'draft' returning * into v_so;
  else
    update public.so set reprice_suggested_at = null, updated_by = v_staff
    where id = p_so_id and status = 'draft' returning * into v_so;
  end if;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order was not saved — it may have been changed by someone else just now — nothing was saved';
  end if;

  return jsonb_build_object(
    'so_number', v_so.so_number, 'lines', v_rows, 'changed_lines', v_changed,
    'order_discount', jsonb_build_object(
      'old_pct', v_old_pct, 'old_source', v_old_src, 'old_deal_id', v_old_deal,
      'new_pct', v_so.order_discount_pct, 'new_source', v_so.order_discount_source, 'new_deal_id', v_so.order_discount_deal_id,
      'kept', v_old_src is not distinct from 'manual',
      'changed', v_so.order_discount_pct is distinct from v_old_pct or v_so.order_discount_deal_id is distinct from v_old_deal));
end;
$$;

-- ═══ 15) so_line_requote 재발행 — 원본 20260924202425_so_finalize_a2.sql · 구성품 줄 거부 ═══
create or replace function public.so_line_requote(p_line_id uuid, p_qty numeric, p_set_qty boolean default true) returns public.so_line
  language plpgsql volatile security invoker
  set search_path = public, pg_temp
as $$
declare
  v_line public.so_line%rowtype;
  v_so   public.so%rowtype;
  q      record;
begin
  select * into v_line from public.so_line where id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was saved';
  end if;
  if v_line.combo_line_id is not null then                                                                         -- asm-2b2(묶음 2): 구성품 줄은 값이 없다 — 견적하면 unit_price 가 null 이 되어 so_line_combo_values_ck 에 걸린다 · 소리 나게 거부
    raise exception 'Line % (%) is a combo component — it carries no price of its own; quote the combo line — nothing was saved', v_line.line_no, v_line.sku;
  end if;
  select * into v_so from public.so where id = v_line.so_id;
  select * into q from public.so_line_quote(v_so, v_line.product_id, p_qty);
  update public.so_line set
    qty_ordered     = case when p_set_qty then p_qty else qty_ordered end,   -- ⓐ2 이견 3: false 면 견적만(뺀 몫 · 판정 5 「주문 12 · 뺐다 12」는 qty_ordered 에 남는다)
    discount_pct    = q.discount_pct,
    unit_price      = case when list_price is null then null else list_price * (1 - q.discount_pct / 100) end,
    discount_source = q.discount_source,
    deal_line_id    = q.deal_line_id,
    updated_by      = public.so_current_staff()
  where id = p_line_id
  returning * into v_line;
  return v_line;
end;
$$;

-- ═══ 16) so_merge 재발행 — 원본 20261005201634_asm_2b1_combo_warehouse_path.sql · 2b1 의 거부를 푼다 · 콤보 줄끼리(열쇠 + 구성품 모양) · 구성품 다시 매달기(끝에 · 저장된 combo_qty) · 짝 표 · merged 장부 수요 줄 단위 ═══
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
      'unconfirmed_at', null, 'unconfirmed_by', null, 'carrier', null, 'tracking_number', null, 'reprice_suggested_at', null,
      'created_at', now(), 'created_by', v_staff, 'updated_at', now(), 'updated_by', v_staff));
  select * into v_new from public.so where id = v_id;
  if v_old.order_discount_source = 'deal' then                                       -- 판정 7: source deal 이면 합친 날로 §13 자동 재계산 · manual 은 그대로
    select * into od from public.so_order_discount(v_id);
    update public.so set order_discount_pct = od.pct, order_discount_deal_id = od.deal_id, order_discount_source = case when od.pct is null then null else 'deal' end, updated_by = v_staff where id = v_id;
  end if;

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

-- ═══ 17) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_invoice_line' and column_name = 'combo_components') <> 1 then v_bad := v_bad || ' invoice-column'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_credit_line' and column_name in ('combo_credit_line_id', 'combo_qty', 'combo_components')) <> 3 then v_bad := v_bad || ' credit-columns'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'wms_order_finalize' and column_name = 'put_back') <> 1 then v_bad := v_bad || ' finalize-column'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.so_credit_line'::regclass and conname in ('so_credit_line_restock_ck', 'so_credit_line_combo_pair_ck', 'so_credit_line_combo_child_ck', 'so_credit_line_combo_parent_ck', 'so_credit_line_combo_self_ck')) <> 5 then v_bad := v_bad || ' credit-checks'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.so_invoice_line'::regclass and conname = 'so_invoice_line_combo_ck') <> 1 then v_bad := v_bad || ' invoice-check'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_finalize', 'so_backorder_proceed', 'so_backorder_sweep', 'so_backorder_supersede', 'so_backorder_reopen', 'so_backorder_list', 'so_cancel', 'so_tax_preview', 'so_invoice_issue', 'so_proforma', 'so_credit_prepare', 'so_credit_issue', 'so_reprice', 'so_line_requote', 'so_merge') and p.prosrc like '%asm-2b2%') <> 15 then v_bad := v_bad || ' reissues'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_finalize', 'so_backorder_proceed', 'so_backorder_sweep', 'so_backorder_supersede', 'so_backorder_reopen', 'so_backorder_list', 'so_cancel', 'so_tax_preview', 'so_invoice_issue', 'so_proforma', 'so_credit_prepare', 'so_credit_issue', 'so_reprice', 'so_line_requote', 'so_merge')) <> 15 then v_bad := v_bad || ' duplicate-signatures'; end if;
  if exists (select 1 from public.so_invoice_line where combo_components is not null) or exists (select 1 from public.so_credit_line where combo_credit_line_id is not null or combo_qty is not null or combo_components is not null) or exists (select 1 from public.wms_order_finalize where put_back is not null) then v_bad := v_bad || ' old-rows-touched'; end if;
  if has_function_privilege('authenticated', 'public.so_invoice_issue(uuid[], uuid, date)', 'execute') or has_function_privilege('authenticated', 'public.so_line_requote(uuid, numeric, boolean)', 'execute') or has_function_privilege('authenticated', 'public.so_backorder_supersede(uuid, uuid)', 'execute') or has_function_privilege('authenticated', 'public.so_backorder_reopen(uuid[], uuid)', 'execute') or has_function_privilege('authenticated', 'public.so_backorder_sweep()', 'execute') then v_bad := v_bad || ' inner-grants'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM246', message = format('STOP - asm-2b2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
