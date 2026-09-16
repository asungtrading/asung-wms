-- ─────────────────────────────────────────────────────────────
-- ⑤ PO 읽기 — discount_factor 표시 자릿수 (테스트 DB Asung-IMS · 2026-09-16 · 20260916163806_po_read.sql 의 후속)
--
-- 앞 파일을 적용·검증한 뒤(Caleb · 예상값 전부 일치) 하나가 걸렸다:
--   ⚠️ discount_factor 가 0.8217000000000000000000000000000000000000 — numeric 곱셈(po_mul)이라 소수 40자리까지 나온다.
--      JSON 이 불필요하게 커지고 화면이 그대로 표시하면 보기 흉하다.
-- ⇒ 뷰 po_list 와 RPC po_detail 을 create or replace 로 다시 정의한다 — **표시용 factor 만 round(…, 6)**.
--   ⚠️⚠️ 금액(net_total · discount_amount · computed_total · payable_net · unpaid)은 **원래 factor 로 계산한 뒤 2자리로 반올림**한다.
--      표시용 factor 와 계산용 factor 를 섞지 않는다 — 6자리로 자른 값으로 곱하면 금액이 어긋날 수 있다.
--   [실측 2026-09-16] PO-02001b 309.00 × 0.8217 = 253.9053 → 253.91 (검토 Claude 의 예상값 253.90 은 뺄셈으로 어림한 것 · 곱 집계가 맞았다).
--
-- 왜 새 파일인가 — 마이그레이션은 적용되면 고치지 않는다(Caleb · ①차). 앞 파일의 create 는 or replace 가 아니라 그대로 다시 못 돈다.
--   뷰 재정의 선례: inv_balance_vs_cin7(세 파일에 걸쳐 create or replace). 앞 파일은 예상값 주석만 고쳤다(DDL 무변).
-- ⚠️ create or replace view 는 칸 이름·순서·타입이 같아야 한다 — round(numeric, 6) 은 numeric 그대로라 통과한다(PG 규칙).
--   create or replace 는 뷰·함수의 ACL 을 유지하지만 명시가 관례라 다시 건다(inv_stock_master 주석).
-- 나머지 정의(계산 규칙 · 주석 · 권한)는 앞 파일과 같다 — 근거는 그 파일 머리에.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ po_list — 발주 목록 뷰 (PostgREST 로 표처럼 읽는다) ═══
-- ⭐ security_invoker = true — 베이스 표 RLS 가 호출자 기준으로 적용된다(선례 wms_order_pack_progress).
-- 라인이 없는 초안도 행이 있다(left join · 합은 0 이지 null 이 아니다) · 할인 줄이 없으면 factor 1 · 갈라진 문서는 split_from_number · split_to_count 로 보인다.
create or replace view public.po_list
  with (security_invoker = true) as
with l as (                                   -- 라인 합
  select po_id,
         count(*)::int                                      as line_count,
         coalesce(sum(qty_ea), 0)                           as ordered_qty,
         coalesce(sum(round(qty_ea * unit_price, 2)), 0)    as subtotal      -- 줄마다 2자리 반올림 뒤 합
  from public.po_line
  group by po_id
),
r as (                                        -- 입고 합 (po_line 에 received_qty 가 없다 — 합으로)
  select pl.po_id, coalesce(sum(rl.qty_ea), 0) as received_qty
  from public.po_receipt_line rl
  join public.po_line pl on pl.id = rl.po_line_id
  group by pl.po_id
),
d as (                                        -- 할인 체인 (차례로 곱한다)
  select po_id, public.po_mul(1 - percent / 100) as factor
  from public.po_discount
  group by po_id
),
c as (                                        -- 붙은 비용 (박힌 배분 금액의 합 · 재계산 없음)
  select po_id, coalesce(sum(amount), 0) as charge_total
  from public.po_charge_alloc
  group by po_id
),
sp as (                                       -- 이 문서에서 갈라져 나간 문서 수 (역방향)
  select split_from_id as po_id, count(*)::int as split_to_count
  from public.po
  where split_from_id is not null
  group by split_from_id
)
select
  p.id,
  p.po_number,
  p.status,
  p.order_date,
  p.supplier_id,
  s.name                                                       as supplier_name,
  cur.code                                                     as currency_code,
  coalesce(l.line_count, 0)                                    as line_count,
  coalesce(l.ordered_qty, 0)                                   as ordered_qty,
  coalesce(r.received_qty, 0)                                  as received_qty,     -- ⚠️ 초과면 ordered 를 넘는다 · 비율은 화면이 낸다(0 나누기 · 초과 때문에 뷰에서 안 낸다)
  coalesce(l.subtotal, 0)                                      as subtotal,
  round(coalesce(d.factor, 1), 6)                              as discount_factor,  -- ⭐ 표시용 6자리(numeric 곱셈은 40자리까지 나온다 · 실측 2026-09-16) · 할인 줄 없음 = 1 · ⚠️ net_total 은 원래 factor 로
  round(coalesce(l.subtotal, 0) * coalesce(d.factor, 1), 2)    as net_total,
  coalesce(c.charge_total, 0)                                  as charge_total,
  sf.po_number                                                 as split_from_number,  -- 바로 앞 문서 (§11-c) · 모체는 null
  coalesce(sp.split_to_count, 0)                               as split_to_count,
  p.confirmed_at,
  p.closed_at,
  p.cancelled_at,
  p.note,
  p.created_at,
  p.updated_at
from public.po p
join public.supplier     s   on s.id   = p.supplier_id
join public.ref_currency cur on cur.id = p.currency_id
left join l  on l.po_id  = p.id
left join r  on r.po_id  = p.id
left join d  on d.po_id  = p.id
left join c  on c.po_id  = p.id
left join public.po sf on sf.id = p.split_from_id
left join sp on sp.po_id = p.id;

comment on view public.po_list is '⑤ 발주 목록 — PostgREST 로 표처럼 읽는다(.range()+count:exact · .ilike · .order · §10-j 3-a). security_invoker=true 라 베이스 표 RLS 가 호출자 기준. subtotal = 줄마다 round(qty×단가,2) 합 · discount_factor = po_discount 를 차례로 곱한 것(po_mul · 없으면 1 · 표시용 6자리 — 금액은 원래 factor 로 계산) · net_total = round(subtotal×factor,2) · charge_total = 박힌 배분 합 · received_qty = 입고 줄 합(초과면 ordered 를 넘는다 · 설계대로). ⚠️ 검색 인덱스는 안 듣는다(짐작 · 수백 건까지 무방). 정본 po-module §13 · 2026-09-16';

-- ⚠️ 기본 권한이 anon 에도 붙는다 — 명시 회수. PostgREST 가 읽으려면 authenticated 에 select 가 있어야 한다(없으면 permission denied · 목록이 빈다).
revoke all on public.po_list from anon;
grant select on public.po_list to authenticated;

-- ═══ po_detail(p_po_id) — 발주 상세 RPC (jsonb 하나 · 계산 규칙의 정본) ═══
-- POST /rest/v1/rpc/po_detail  body {"p_po_id": "<uuid>"}  → jsonb 또는 null(없는 id)
create or replace function public.po_detail(p_po_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with p as (
  select * from public.po where id = p_po_id
),
lines as (
  select pl.*,
         pr.sku,
         pr.name                                   as product_name,
         up.sku                                    as entered_unit_sku,
         coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = pl.id), 0) as received_qty,
         round(pl.qty_ea * pl.unit_price, 2)       as amount
  from public.po_line pl
  join public.product pr on pr.id = pl.product_id
  left join public.product up on up.id = pl.entered_unit_product_id
  where pl.po_id = p_po_id
),
disc as (
  select * from public.po_discount where po_id = p_po_id
),
tot as (
  select coalesce((select sum(amount) from lines), 0)                        as subtotal,
         coalesce((select public.po_mul(1 - percent / 100) from disc), 1)     as factor,
         coalesce((select sum(qty_ea) from lines), 0)                         as ordered_qty,
         coalesce((select sum(received_qty) from lines), 0)                   as received_qty,
         coalesce((select sum(amount) from public.po_charge_alloc where po_id = p_po_id), 0) as charge_total
),
rcpt as (
  select rl.*, pl.line_no, pr.sku, b.name as bin_name, w.name as warehouse_name, st.name as received_by_name
  from public.po_receipt_line rl
  join public.po_line pl on pl.id = rl.po_line_id
  join public.product pr on pr.id = pl.product_id
  join public.ref_bin b on b.id = rl.bin_id
  join public.ref_warehouse w on w.id = b.warehouse_id
  left join public.ims_staff st on st.id = rl.received_by
  where pl.po_id = p_po_id
),
inv_ids as (                                  -- 이 발주의 라인을 가리키는 인보이스 (줄 수준 · 머리에 PO 칸 없음)
  select distinct il.po_invoice_id
  from public.po_invoice_line il
  join public.po_line pl on pl.id = il.po_line_id
  where pl.po_id = p_po_id
),
inv as (
  select i.*,
         s.name   as supplier_name,
         cur.code as currency_code,
         (select count(*) from public.po_invoice_line x where x.po_invoice_id = i.id)::int as line_count,
         (select count(*) from public.po_invoice_line x join public.po_line pl on pl.id = x.po_line_id
           where x.po_invoice_id = i.id and pl.po_id = p_po_id)::int                       as lines_for_this_po,
         -- ⭐ 할인 체인은 goods 줄에만(Caleb 2026-09-16 · other 는 공급처가 할인했는지 모른다 · 차이로 드러나면 그때 정한다)
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = i.id and x.line_kind = 'goods')                          as goods_sum,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = i.id and x.line_kind <> 'goods')                         as other_sum,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = i.id and x.line_kind = 'goods' and x.is_payable)         as goods_payable,
         (select coalesce(sum(round(qty_ea * unit_price, 2)), 0) from public.po_invoice_line x
           where x.po_invoice_id = i.id and x.line_kind <> 'goods' and x.is_payable)        as other_payable,
         coalesce((select public.po_mul(1 - percent / 100) from public.po_invoice_discount dd
           where dd.po_invoice_id = i.id), 1)                                                as factor,
         (select coalesce(sum(amount), 0) from public.po_payment_alloc a where a.po_invoice_id = i.id) as paid
  from public.po_invoice i
  join public.supplier s on s.id = i.supplier_id
  join public.ref_currency cur on cur.id = i.currency_id
  where i.id in (select po_invoice_id from inv_ids)
),
chg as (
  select c.*, a.amount as alloc_amount, s.name as supplier_name, cur.code as currency_code,
         (select coalesce(sum(amount), 0) from public.po_payment_alloc pa where pa.po_charge_id = c.id) as paid
  from public.po_charge_alloc a
  join public.po_charge c on c.id = a.po_charge_id
  join public.supplier s on s.id = c.supplier_id
  join public.ref_currency cur on cur.id = c.currency_id
  where a.po_id = p_po_id
),
pay as (                                      -- 이 발주의 인보이스에 걸린 결제 + 이 발주에 배분된 비용 문서에 걸린 결제
  select pm.*, pa.amount as alloc_amount,
         case when pa.po_invoice_id is not null then 'invoice' else 'charge' end as target_kind,
         coalesce(i.invoice_number, c.charge_number)                             as target_number,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  left join public.po_invoice i on i.id = pa.po_invoice_id
  left join public.po_charge  c on c.id = pa.po_charge_id
  where pa.po_invoice_id in (select po_invoice_id from inv_ids)
     or pa.po_charge_id  in (select id from chg)
)
select case when not exists (select 1 from p) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', p.id, 'po_number', p.po_number, 'status', p.status, 'order_date', p.order_date,
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'currency_code', cur.code, 'exchange_rate', p.exchange_rate,
      'payment_term_name', coalesce(p.payment_term_name, pt.name),      -- 문서에 박힌 원문 우선 · 없으면 마스터 이름
      'ship_to_warehouse', w.name,
      'split_from_number', sf.po_number,
      'split_to', coalesce((select jsonb_agg(jsonb_build_object('id', x.id, 'po_number', x.po_number, 'status', x.status) order by x.po_number)
                             from public.po x where x.split_from_id = p.id), '[]'::jsonb),
      'created_by_name', cb.name, 'confirmed_by_name', fb.name,
      'confirmed_at', p.confirmed_at, 'closed_at', p.closed_at, 'cancelled_at', p.cancelled_at,
      'note', p.note, 'created_at', p.created_at, 'updated_at', p.updated_at)
    from p
    join public.supplier s on s.id = p.supplier_id
    join public.ref_currency cur on cur.id = p.currency_id
    left join public.ref_payment_term pt on pt.id = p.payment_term_id
    left join public.ref_warehouse w on w.id = p.ship_to_warehouse_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = p.created_by
    left join public.ims_staff fb on fb.id = p.confirmed_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'product_id', product_id, 'sku', sku, 'product_name', product_name,
      'supplier_sku', supplier_sku, 'qty_ea', qty_ea, 'received_qty', received_qty,
      'remaining_qty', qty_ea - received_qty,                          -- ⚠️ 초과면 음수 · 그대로(설계대로)
      'entered_unit_sku', entered_unit_sku, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'tax_rule', tax_rule, 'note', note) order by line_no)
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'seq', seq, 'name', name, 'percent', percent,
                                        'supplier_discount_id', supplier_discount_id, 'note', note) order by seq)
    from disc), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'subtotal', subtotal,
      'discount_factor', round(factor, 6),                              -- ⭐ 표시용 6자리 · 아래 금액은 원래 factor 로 계산한 뒤 2자리
      'discount_amount', round(subtotal - subtotal * factor, 2),
      'net_total', round(subtotal * factor, 2),
      'charge_total', charge_total,
      'ordered_qty', ordered_qty,
      'received_qty', received_qty)
    from tot
  ),
  'receipts', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'po_line_id', po_line_id, 'line_no', line_no, 'sku', sku,
      'received_on', received_on, 'received_by_name', received_by_name,
      'bin_name', bin_name, 'warehouse_name', warehouse_name, 'qty_ea', qty_ea, 'note', note)
      order by received_on, line_no, bin_name)
    from rcpt), '[]'::jsonb),
  'invoices', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'invoice_number', invoice_number, 'invoice_date', invoice_date, 'due_date', due_date, 'status', status,
      'supplier_name', supplier_name, 'currency_code', currency_code,
      'line_count', line_count, 'lines_for_this_po', lines_for_this_po,
      'discount_factor', round(factor, 6),                                                -- 표시용 · 계산은 원래 factor
      'total_amount', total_amount,                                                       -- 찍힌 값 · 정본
      'computed_total', round(goods_sum * factor, 2) + other_sum,                          -- 계산값 (goods 만 체인)
      'diff', total_amount - (round(goods_sum * factor, 2) + other_sum),                   -- ⭐ 대조 · 0 이 아니면 입력 오류·반올림·other 할인
      'payable_net', round(goods_payable * factor, 2) + other_payable,                     -- 갚을 돈 (is_payable 줄만)
      'paid', paid,
      'unpaid', (round(goods_payable * factor, 2) + other_payable) - paid)                 -- ⭐ 미지급 — 총액이 아니라 갚을 돈 기준
      order by invoice_date, invoice_number)
    from inv), '[]'::jsonb),
  'charges', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'charge_number', charge_number, 'kind', kind, 'description', description, 'charge_date', charge_date,
      'status', status, 'supplier_name', supplier_name, 'currency_code', currency_code,
      'total_amount', total_amount,
      'alloc_amount', alloc_amount,                                                        -- 이 발주에 박힌 배분 (재계산 없음)
      'paid', paid,
      'unpaid', total_amount - paid)                                                       -- 비용 문서 전체 기준
      order by charge_date, charge_number)
    from chg), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'paid_on', paid_on, 'reference', reference,
      'target_kind', target_kind, 'target_number', target_number, 'alloc_amount', alloc_amount,
      'amount', amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
      'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb)
) end;
$$;

comment on function public.po_detail(uuid) is '⑤ 발주 상세 — jsonb 하나(header · lines · discounts · totals · receipts · invoices · charges · payments). ⭐ 계산 규칙의 정본: 할인 체인은 po_mul 로 곱한다 · 라인 금액은 round(qty×단가,2) · 인보이스 체인은 goods 줄에만 · computed_total 과 찍힌 total_amount 의 diff 가 대조 · 미지급 = is_payable 줄 합(체인 적용) − 충당 합 · 비용 배분은 박힌 값 읽기만 · 입고는 줄 합(초과면 remaining 음수 · 설계대로). 없는 id → null. security invoker(전부 auth_all). 정본 po-module §13 · §11-e·f · 2026-09-16';

-- 함수 EXECUTE 는 PUBLIC 기본 부여 — 명시 회수 (ims_is_admin · inv_stock_master 관례)
revoke all on function public.po_detail(uuid) from public, anon;
grant execute on function public.po_detail(uuid) to authenticated;
revoke all on function public.po_mul(numeric) from public, anon;
grant execute on function public.po_mul(numeric) to authenticated;   -- 뷰·RPC 가 invoker 로 돌 때 호출자에게 실행 권한이 필요하다


-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb)
-- ─────────────────────────────────────────────────────────────
-- ① select po_number, discount_factor, net_total from po_list order by po_number;
--    예상  PO-02001a 0.821700 2010.54 · PO-02001b 0.821700 253.91 · PO-02002 1.000000 7985.00
--          (numeric round(…,6) 은 뒷자리 0 을 유지해 6자리로 보인다 · JS 에서는 0.8217)
-- ② select po_detail((select id from po where po_number='PO-02001a')) -> 'totals';
--    예상  discount_factor 0.821700 · discount_amount 436.26 · net_total 2010.54  ← 금액은 앞 실측과 같아야 한다(달라지면 표시용 factor 로 계산한 것)
-- ③ select (po_detail((select id from po where po_number='PO-02001a')) -> 'invoices' -> 0) ->> 'discount_factor';   → 0.821700
