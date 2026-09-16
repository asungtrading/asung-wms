-- ─────────────────────────────────────────────────────────────
-- ⑤ PO 읽기 — 목록 뷰 po_list · 상세 RPC po_detail(p_po_id) · 곱 집계 po_mul (테스트 DB Asung-IMS · 2026-09-16)
--
-- 정본: docs/design/po-module.md §13(표 열하나 · 검증) · §11-e(할인 체인) · §11-f(비용 배분) · §10-j 3-a(1,000행 캡 · .range()) · 3-f(저장 확인)
-- 표: 20260916144201_po.sql(①차) · 20260916153313_po_invoice_charge_payment.sql(②차) — 이 파일은 표를 바꾸지 않는다(읽기만)
-- 지시서: ~/asung/prompts/po-read-view-rpc.md · 검토 이견 1~18(2026-09-16 · 전부 받음 · 6 은 goods 만 · PO-02001b 할인 줄은 복사됨)
--
-- ⭐ 왜 이렇게 나누나(Caleb 2026-09-16)
--   목록 = 뷰   PostgREST 로 표처럼 읽는다 — 기존 화면 헬퍼(imsPage 의 .range()+count:'exact' · imsQ 검색 · 정렬)가 그대로 듣는다(§10-j 3-a).
--               RPC 로 하면 1,000행 캡과 페이지네이션을 손으로 다시 짜야 한다.
--   상세 = RPC  한 번에 jsonb 하나 — ① 상세 한 번에 조회가 일고여덟 번 나간다 ② ⭐⭐ 계산 규칙(할인 체인 · 미지급 · 총액 대조)이 **한곳**에 있어야
--               화면마다 다시 짜다 어긋나지 않는다(§13 「적어 두지 않으면 화면마다 다르게 구현한다」가 이 자리).
--
-- ⭐ 선례(이 레포 · 2026-09-16 grep)
--   뷰   wms_order_pack_progress(20260806110000 · ⭐ with (security_invoker = true) · grant select) · inv_balance · inv_layer_open(revoke anon)
--   RPC  inv_stock_master(20260901194903 · returns jsonb · language sql stable security invoker · revoke public,anon · grant authenticated) · ims_is_admin(definer — 정책 재귀 방지용 · 여기 해당 없음)
--   집계 · text_pattern_ops · pg_trgm 선례 없음 — po_mul 이 첫 집계.
--
-- ⭐ 이름 — 모듈 접두어 po_(po_next_number 와 같다). ims_ 는 사용자·인프라(ims_staff · ims_is_admin) 전용(Caleb 2026-09-16 확정). 뷰에 _v 접미사를 붙이지 않는다(선례).
--
-- ⚠️ 보안 · 권한
--   뷰는 security_invoker = true — 호출자 권한으로 돌아 베이스 표 RLS 가 그대로 적용된다. 이것이 없으면 뷰는 소유자 권한으로 돌아
--   나중에 RLS 를 걸 때 구멍이 된다(inv_layer_open 주석). 지금은 전부 auth_all 이라 차이가 없지만 미리 막는다(선례 wms_order_pack_progress).
--   RPC 는 security invoker — 전부 auth_all 이라 우회할 것이 없고, definer 는 RLS 우회가 된다(필요할 때만 · ims_is_admin 은 정책 재귀 때문).
--   ⚠️⚠️ Supabase 기본 권한(default privileges)이 새 객체에 ALL 을 붙인다(2026-08-06 뷰에서 실측) ⇒ anon 회수를 **명시**한다. 함수 EXECUTE 도 PUBLIC 기본 부여라 명시 회수.
--
-- ⭐ 계산 규칙 — 여기가 화면들의 정본이다(§11-e · §11-f · §13)
--   할인 체인    차례로 **곱한다**(더하지 마라 · [실측 2026-09-16] 2,755.80 × 0.83 × 0.99 = 2,264.44 · 더하면 2,259.76 · 차이 4.68).
--               ⭐ 곱 집계 po_mul(numeric) 로 낸다 — exp(sum(ln(1-p/100))) 은 percent=100 에서 ln(0) 으로 터지고(CHECK 가 0~100 을 허용하니 실제로 가능) 부동소수 오차가 있다.
--                 po_mul 은 numeric 곱셈이라 정확하고 100 이면 인자 0 이 되어 factor 0. 할인 줄이 없으면 집계가 null → coalesce 1(PO-02002 가 그렇다 · join 이 행을 없애지 않는다).
--   라인 금액    round(qty_ea × unit_price, 2) — unit_price 가 numeric(18,7)이라 7자리까지 나온다. 돈은 2자리. 줄마다 반올림한 뒤 합한다(화면이 보여 주는 줄 합과 같다).
--               ⚠️ 원가 배분(할인을 줄로 내리는 잔돈 · 금액이 가장 큰 줄 · 동점 SKU 순)은 **만들기 차수** — 읽기는 합만 반올림한다.
--   인보이스     할인 체인은 **goods 줄에만** 곱한다 · charge(운임 등) · other(우리가 안 시킨 것) 줄에는 곱하지 않는다(Caleb 2026-09-16).
--               ⚠️ other 도 물건이라 곱해야 할 수 있지만 공급처가 할인을 적용했는지 우리가 모른다. total_amount(찍힌 값 · 정본)가 대조값으로 있으니
--                  잘못 계산하면 차이로 드러난다 — 실물이 나왔을 때 그 차이를 보고 정한다. 지금 짐작으로 정하지 않는다.
--               computed_total = round(goods 합 × 체인, 2) + goods 아닌 줄 합 · diff = total_amount − computed_total([실측] 2,446.80×0.8217 = 2,010.54 · +운임 187 = 2,197.54 · 근거 없는 총액을 넣자 −253.90 이 드러났다)
--   미지급       인보이스 = payable 줄 합(goods 는 체인 적용) − 충당 합 — ⚠️ 총액이 아니다 · 운임 줄(is_payable=false)이 빠진다([실측] 청구 2,197.54 vs 갚을 돈 2,010.54 · 미지급 0)
--               비용 = total_amount − 충당 합
--   비용 배분    po_charge_alloc.amount 는 **이미 박힌 값**(§11-f · 재계산 없음) — RPC 는 읽기만 한다. 배분 계산 함수(잔돈 · 금액이 가장 큰 발주 · 동점 발주번호 순)는 만들기 차수.
--   입고 진행    po_receipt_line 합 — po_line 에 received_qty 는 없다. ⚠️⚠️ 초과 입고는 합이 qty_ea 를 넘을 수 있고 remaining 이 음수가 된다 — 그대로 보여 준다(원장 합 ≠ 입고 줄 합 · 설계대로 · §13).
--
-- ⚠️ 검색·정렬 — 뷰 위에서 서버로 돈다(.order · .ilike). 인덱스는 안 듣는다(짐작) — 뷰가 조인·집계라 ilike 는 뷰 결과를 훑는다. 발주 수백 건까지 체감 없을 것으로 본다. 지금 행이 셋이라 잴 수 없다.
-- ⚠️ 숫자 — jsonb 의 numeric 은 JSON number 로 나간다(문자열 아님). 화면은 parseFloat 없이 쓴다. JS 는 double 이라 7자리 단가도 double — 돈 2자리에는 문제없다.
-- ⚠️ 없는 id — po_detail 은 SQL null 을 돌려준다(PostgREST 응답 본문 null). 화면은 data === null 로 「없다」를 가른다. 빈 객체가 아니다.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ✅ 적용·검증 2026-09-16(Caleb · 예상값 전부 일치 · b 의 253.90 만 어림 오차) → ⚠️ discount_factor 가 numeric 곱셈이라 소수 40자리로 나와
--    다음 파일(*_po_read_factor.sql)이 뷰·RPC 를 create or replace 로 round(…,6) 표시로 바꿨다. 이 파일은 DDL 그대로(적용된 마이그레이션은 고치지 않는다).
-- ─────────────────────────────────────────────────────────────

-- ═══ po_mul — 곱 집계 (numeric · 할인 체인용) ═══
-- 내장 numeric_mul(numeric, numeric) 을 집계로 감쌌다. 초기값 1. 행이 없으면 null(집계 관례) — 쓰는 쪽이 coalesce(…, 1).
create aggregate public.po_mul(numeric) (
  sfunc    = numeric_mul,
  stype    = numeric,
  initcond = '1'
);
comment on aggregate public.po_mul(numeric) is '곱 집계 — 할인 체인(1 − percent/100 를 차례로 곱한다 · §11-e). exp(sum(ln)) 대신 쓴다: percent=100 에서 안 터지고 numeric 이라 오차가 없다. 행이 없으면 null → coalesce(…,1). 정본 po-module §13 · 2026-09-16';

-- ═══ po_list — 발주 목록 뷰 (PostgREST 로 표처럼 읽는다) ═══
-- ⭐ security_invoker = true — 베이스 표 RLS 가 호출자 기준으로 적용된다(선례 wms_order_pack_progress).
-- 라인이 없는 초안도 행이 있다(left join · 합은 0 이지 null 이 아니다) · 할인 줄이 없으면 factor 1 · 갈라진 문서는 split_from_number · split_to_count 로 보인다.
create view public.po_list
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
  coalesce(d.factor, 1)                                        as discount_factor,  -- 할인 줄 없음 = 1
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

comment on view public.po_list is '⑤ 발주 목록 — PostgREST 로 표처럼 읽는다(.range()+count:exact · .ilike · .order · §10-j 3-a). security_invoker=true 라 베이스 표 RLS 가 호출자 기준. subtotal = 줄마다 round(qty×단가,2) 합 · discount_factor = po_discount 를 차례로 곱한 것(po_mul · 없으면 1) · net_total = round(subtotal×factor,2) · charge_total = 박힌 배분 합 · received_qty = 입고 줄 합(초과면 ordered 를 넘는다 · 설계대로). ⚠️ 검색 인덱스는 안 듣는다(짐작 · 수백 건까지 무방). 정본 po-module §13 · 2026-09-16';

-- ⚠️ 기본 권한이 anon 에도 붙는다 — 명시 회수. PostgREST 가 읽으려면 authenticated 에 select 가 있어야 한다(없으면 permission denied · 목록이 빈다).
revoke all on public.po_list from anon;
grant select on public.po_list to authenticated;

-- ═══ po_detail(p_po_id) — 발주 상세 RPC (jsonb 하나 · 계산 규칙의 정본) ═══
-- POST /rest/v1/rpc/po_detail  body {"p_po_id": "<uuid>"}  → jsonb 또는 null(없는 id)
create function public.po_detail(p_po_id uuid) returns jsonb
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
      'discount_factor', factor,
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
      'discount_factor', factor,
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
-- 화면이 부르는 모양 (asung-ims · 화면 차수의 입력 · supabase-js v2)
-- ─────────────────────────────────────────────────────────────
--   목록  const { data, count, error } = await pg.run(
--           sb.from("po_list").select("*", { count: "exact" })
--             .ilike("po_number", `%${q}%`)                 // 또는 .or(`po_number.ilike.%${q}%,supplier_name.ilike.%${q}%`)
--             .eq("status", "confirmed")                    // 필터
--             .order("order_date", { ascending: false }).order("po_number"));
--         // imsPage 가 .range() 를 붙인다 · 1,000행 캡 안전(§10-j 3-a)
--   상세  const { data, error } = await sb.rpc("po_detail", { p_po_id: id });
--         // data === null 이면 없는 발주 · 아니면 data.header · data.lines[] · data.totals.net_total …
--         // 숫자는 JSON number — parseFloat 불필요
--   접두어 찾기(모체 번호로 갈라진 문서 전부)  sb.from("po_list").select("*").like("po_number", "PO-02001%").order("po_number")
--
-- ─────────────────────────────────────────────────────────────
-- 검증 (마이그레이션 후 Caleb 이 실행 — 지시서 §4 ⓒ · 예상값은 검토 Claude 가 정본 §13 의 실측에서 계산한 것 · 라인 단가는 못 봤다)
-- ─────────────────────────────────────────────────────────────
-- ① 목록
--   select po_number, status, line_count, ordered_qty, received_qty, subtotal, discount_factor, net_total, charge_total, split_from_number, split_to_count
--   from po_list order by po_number;
--   예상  PO-02001a  closed     3  920  920  2446.80  0.8217  2010.54   597.49  null       1
--         PO-02001b  confirmed  1  100    0   309.00  0.8217   253.91     0.00  PO-02001a  0   (할인 줄을 b 에 복사했다 · Caleb)  ⚠️ 253.90 은 뺄셈으로 어림한 것 — 309.00×0.8217=253.9053 → 253.91 (실측 2026-09-16 · 곱 집계가 맞았다)
--         PO-02002   confirmed  2    ?    0  7985.00  1       7985.00  1949.88  null       0   (? = 수량 못 봤다)
-- ② 상세 a
--   select jsonb_pretty(po_detail((select id from po where po_number = 'PO-02001a')));
--   예상  header.split_to = [{PO-02001b · confirmed}] · lines 3 (received 600·200·120 · remaining 0·0·0) · discounts 2
--         totals.subtotal 2446.80 · discount_factor 0.8217 · discount_amount 436.26 · net_total 2010.54 · charge_total 597.49
--         receipts 4행 (600 이 A010101 400 + A010102 200) · invoices 1 (AMP-778812 · total_amount 2197.54 · computed_total 2197.54 · diff 0.00 · payable_net 2010.54 · paid 2010.54 · unpaid 0.00 · lines_for_this_po 3)
--         charges 1 (CBSA 10039192310530 · alloc 597.49 · total 2547.37 · paid 2547.37 · unpaid 0.00)
--         payments 2 (WIRE-20260916-01 invoice 2010.54 · discount 0 / EFT-20260916-02 charge 2496.42 · discount 50.95)
-- ③ 상세 b
--   select jsonb_pretty(po_detail((select id from po where po_number = 'PO-02001b')));
--   예상  header.split_from_number PO-02001a · split_to [] · lines 1 (remaining 100) · discounts 2 · totals.net_total 253.91 · receipts [] · invoices [] · charges [] · payments []
-- ④ 없는 id
--   select po_detail(gen_random_uuid());        → null
-- ⑤ 권한
--   select grantee, privilege_type from information_schema.role_table_grants where table_name = 'po_list' order by 1,2;      → authenticated SELECT 만 (anon 없음)
--   select routine_name, grantee from information_schema.routine_privileges where routine_name in ('po_detail','po_mul') order by 1,2;
-- ⑥ 숫자 타입 (문자열이 아닌가)
--   select jsonb_typeof(po_detail((select id from po where po_number='PO-02001a')) -> 'totals' -> 'net_total');   → number
