-- ─────────────────────────────────────────────────────────────
-- 매입 가격 이력 뷰 — po_price_history · po_price_history_skipped (Asung-IMS · 2026-09-20)
--   ① po_price_history          ⭐ 한 줄 = 확정 인보이스의 goods 줄 하나 = 「이 SKU 를 이 공급처에서 이날 실제로 얼마에 샀나」(할인 반영 · 인보이스 통화 · 발주 환율로 CAD 참고값)
--   ② po_price_history_skipped  ⚠️ 확정 인보이스 줄 중 ① 에 안 나오는 것과 그 이유(not_payable · zero_price · not_ordered · charge · negative_qty) — 조용히 빠지면 「산 적 없다」로 읽힌다
--   표 변경 없음 · RPC 없음(뷰 + PostgREST 필터 — 계산이 없다) · security_invoker(권한은 밑의 표가 정한다 · po_list·po_invoice_list 선례)
--
-- ⭐ Caleb 판정 (2026-09-20 · 말 그대로): 「특정 SKU 의 구매가를 한눈에 볼 수 있는 게 제일 좋아」 · 「인보이스는 공급처가 제공하는 실제 가격이 들어있는 문서야 … 당연히 인보이스가 가져와야 해.
--   그런데 해당 인보이스에 적용된 디스카운트도 볼 수 있어야 제대로 된 확인이 될 것 같아」 · 「USD 를 기본으로 보여주는 게 맞아. 구매처가 캐나다면 CAD 만」
--
-- 왜 인보이스가 출처인가 — 발주(po_line.unit_price)는 **우리가 적은 값**이고 인보이스는 **공급처가 준 실제 값**이다. 결제도 인보이스로 한다. 입고는 수량의 사실이지 가격의 사실이 아니다
--   (⚠️ 공짜로 더 온 물건을 가격으로 세면 latest 가 0 이 되거나 왜곡된다). product_supplier.cost/fixed_cost(latest/fixed)는 Cin7 이 채워 온 값이고 IMS 는 아직 갱신하지 않는다
--   [실측 2026-09-20 · product_supplier 에 쓰는 함수 0 · AMP41103 last_supplied 2026-08-05 그대로] — 컷오버 뒤 그 칸을 갱신할 재료가 이 뷰다.
-- 왜 goods 만인가 — 할인 체인은 goods 줄에만 곱한다(po_invoice_money · 정본 §11-e · Caleb 2026-09-16). charge(운임)는 가격이 아니고, other(우리가 안 시킨 것)는 po_line 이 없어 SKU 를 모른다.
-- 왜 is_payable 을 거르나 — [Caleb] ⓐ 우리가 쓸 물건이 인보이스에 섞여 온다(돈은 내지만 판매용 매입과 조건이 다르다) ⓑ 공짜로 보내 준다. 둘 다 **가격이 아니다.** 거르지 않으면 ⓑ 가 0 으로 이력에 박힌다.
-- 왜 unit_price 0 · qty_ea ≤ 0 도 거르나(지시서엔 없던 것 · 이견) — 0 은 「가격」으로 읽힌다(샘플·공짜) · 음수 수량은 정정 줄이다(표 주석 「정정 줄이 음수로 올 수 있다」). 둘 다 ② 에 이유와 함께 남긴다.
-- 왜 factor 를 po_invoice_money 에서 읽나 — 할인 체인(po_mul · 차례로 곱한다 · 17%×1% = 0.8217, 18% 가 아니다)의 정본이 그 뷰다. 여기 다시 적으면 같은 규칙이 두 곳에 살고 한쪽만 고치면 갈라진다.
--   po_invoice_money 는 문서 전체를 집계한다(calc 가 두 번 참조돼 materialize) — 지금 인보이스 수십 장이라 ms 다. 느려지면 고칠 곳은 po_invoice_money 하나(인덱스·물질화)이고 두 번째 식이 아니다. 검증 ⑦ 이 잰다.
-- 왜 discount_label 인가 — 계수 0.8217 은 사람이 못 읽는다. 「Trade 17% · Damage 1%」(seq 순 · 체인 차례가 곱해지는 차례다)여야 「이 가격에 무엇이 걸렸나」가 보인다. 할인 줄이 없으면 null(factor 1).
-- 통화 · 환율 — 인보이스 통화가 기준이다. 기준통화(inv_config.base_currency)면 is_base_currency=true · exchange_rate null · net_unit_cad = net_unit(같은 숫자를 두 번 그리지 않는다).
--   외화면 환율은 ① 인보이스 환율 → ② 그 줄 발주의 환율(⚠️ 발주 통화 = 인보이스 통화일 때만 — 통화가 다르면 남의 환율이다) → ③ null. exchange_rate_source 가 어느 것인지 말한다.
--   ⚠️⚠️ 환율이 없으면 net_unit_cad 는 **null** 이다 — 0 으로 채우지 않는다(0 은 가격으로 읽힌다). [실측] 5 인보이스 중 셋이 발주 환율도 없다. 진짜 맞는 것은 결제 환율(MTFX)인데 어디에도 없다(정본 ⬜).
-- ⚠️ 1센트 — 정상이다. 문서 총액은 round(goods_sum × factor, 2) 로 한 번 끊고, 이 뷰의 net_unit 은 줄마다 6자리로 끊는다 ⇒ Σ round(net_unit × qty, 2) 가 문서 총액과 0.01 다를 수 있다
--   [실측 AMP-778812 · 2,010.54 vs 2,010.53]. 가격 이력은 **단가**를 보는 자리라 문제가 아니다. ⚠️⚠️ 이 값을 원가에 쓰게 되면 그때는 레이어 배분 방식(6자리 · 끝수는 마지막 줄)을 따라 맞춘다.
-- ⚠️ 크레딧(doc_kind 'credit')은 이번 판에 **안 들어간다** — 표시만(has_credit · credit_numbers). 수량 크레딧(제품·개수가 붙는다)과 가격 크레딧(차액만 온다)이 갈리는데 실물이 1건(cancelled)뿐이라 표본 없이 설계하지 않는다.
-- 세트(entered_pack_factor)는 다루지 않는다 — [Caleb] 「실제로 우리는 세트로 주문하지 않아」 · 23행 전부 null.
--
-- 정본: po-module §11-e(할인 · 체인 · goods 만) · §11-g(인보이스 · 줄이 po_line 을 가리킨다 · is_payable · total_amount 는 대조값) · 지시서 ~/asung/prompts/ims-price-history.md · ⬜1~7 은 회신에
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① po_price_history — 한 줄 = 확정 인보이스의 매입 단가 하나 ═══
create or replace view public.po_price_history
  with (security_invoker = true) as
with base as (
  select k.value as code from public.inv_config k where k.key = 'base_currency'
),
disc as (                                                                           -- 사람이 읽는 할인 문장 · seq 순(곱해지는 차례) · 계수는 po_invoice_money 가 정본(여기서 다시 곱하지 않는다)
  select d.po_invoice_id,
         string_agg(d.name || ' ' || case when d.percent = trunc(d.percent) then trunc(d.percent)::text else rtrim(d.percent::text, '0') end || '%', ' · ' order by d.seq) as discount_label,   -- 17 → 「17%」 · 17.5 → 「17.5%」(to_char FM 은 정수 끝에 '.' 을 남길 수 있어 안 쓴다)
         count(*)::int as discount_count
  from public.po_invoice_discount d
  group by d.po_invoice_id
),
cr as (                                                                             -- 이 인보이스에 걸린 크레딧(취소 제외) — 표시만 · 값은 이번 판에 안 섞는다
  select c.credit_for_invoice_id as invoice_id,
         count(*)::int as credit_count,
         string_agg(c.invoice_number, ' · ' order by c.invoice_date, c.invoice_number) as credit_numbers
  from public.po_invoice c
  where c.doc_kind = 'credit' and c.status <> 'cancelled' and c.credit_for_invoice_id is not null
  group by c.credit_for_invoice_id
)
select
  pr.id                                   as product_id,
  pr.sku,
  pr.name                                 as product_name,
  i.supplier_id,
  s.name                                  as supplier_name,
  i.id                                    as invoice_id,
  i.invoice_number,                                                                 -- 공급처가 준 번호(우리 채번 아님) — supplier_ref_number 는 크레딧 전용 칸이라 여기 없다
  i.invoice_date,
  x.id                                    as po_id,
  x.po_number,
  il.id                                   as invoice_line_id,
  il.qty_ea                               as qty,
  il.unit_price                           as gross_unit,                            -- 인보이스에 적힌 값(할인 전 · 인보이스 통화)
  m.factor,                                                                         -- 할인 계수(원래 자릿수 · 1 이면 할인 없음) · 정본 po_invoice_money
  round(il.unit_price * m.factor, 6)      as net_unit,                              -- ⭐ 실제 매입 단가(할인 반영 · 인보이스 통화)
  dc.discount_label,                                                                -- 「Trade 17% · Damage 1%」 · 없으면 null
  coalesce(dc.discount_count, 0)          as discount_count,
  cur.code                                as currency_code,                         -- 인보이스 통화 = 이 줄의 기준
  (cur.code is not distinct from b.code)  as is_base_currency,                      -- 기준통화면 화면이 CAD 를 따로 그리지 않는다
  case when cur.code is not distinct from b.code then null
       when i.exchange_rate is not null and i.exchange_rate > 0 then i.exchange_rate
       when x.currency_id = i.currency_id and x.exchange_rate is not null and x.exchange_rate > 0 then x.exchange_rate
       end                                as exchange_rate,                         -- CAD per 통화 · 곱한다(원가 레이어와 같은 방향)
  case when cur.code is not distinct from b.code then null
       when i.exchange_rate is not null and i.exchange_rate > 0 then 'invoice'
       when x.currency_id = i.currency_id and x.exchange_rate is not null and x.exchange_rate > 0 then 'po'
       end                                as exchange_rate_source,                  -- invoice · po · null(환율 없음)
  case when cur.code is not distinct from b.code then round(il.unit_price * m.factor, 6)
       when i.exchange_rate is not null and i.exchange_rate > 0 then round(il.unit_price * m.factor * i.exchange_rate, 6)
       when x.currency_id = i.currency_id and x.exchange_rate is not null and x.exchange_rate > 0 then round(il.unit_price * m.factor * x.exchange_rate, 6)
       end                                as net_unit_cad,                          -- ⚠️ 환율 없으면 null — 0 으로 채우지 않는다
  (cr.credit_count is not null)           as has_credit,                            -- 취소되지 않은 크레딧이 걸려 있다 — 「정정이 붙어 있다」 표시만
  coalesce(cr.credit_count, 0)            as credit_count,
  cr.credit_numbers,
  i.confirmed_at
from public.po_invoice_line il
join public.po_invoice       i   on i.id  = il.po_invoice_id
join public.po_invoice_money m   on m.id  = i.id
join public.po_line          pl  on pl.id = il.po_line_id
join public.po               x   on x.id  = pl.po_id
join public.product          pr  on pr.id = pl.product_id
join public.supplier         s   on s.id  = i.supplier_id
join public.ref_currency     cur on cur.id = i.currency_id
left join base b   on true
left join disc dc  on dc.po_invoice_id = i.id
left join cr       on cr.invoice_id = i.id
where i.doc_kind = 'invoice'
  and i.status   = 'confirmed'
  and il.line_kind = 'goods'                                                        -- 할인은 goods 에만 · charge/other 는 가격이 아니다
  and il.is_payable                                                                 -- ⓐ 우리 쓸 것 · ⓑ 공짜 — 둘 다 가격이 아니다
  and il.unit_price > 0                                                             -- 0 은 가격으로 읽힌다(샘플)
  and il.qty_ea > 0;                                                                -- 음수는 정정 줄

comment on view public.po_price_history is '⭐ 매입 가격 이력(2026-09-20) — 한 줄 = 확정 인보이스(doc_kind invoice · confirmed)의 goods·payable 줄 하나 = 「이 SKU 를 이 공급처에서 이날 실제로 얼마에 샀나」. 출처는 인보이스(공급처가 준 실제 값 · 발주는 우리가 적은 값 · 입고는 수량의 사실). net_unit = round(unit_price × factor, 6) · factor 는 po_invoice_money(할인 체인 정본 · 차례로 곱한다) · discount_label 은 「Trade 17% · Damage 1%」(seq 순). 통화는 인보이스 통화가 기준 · 기준통화면 is_base_currency=true · 환율 null · net_unit_cad = net_unit. 외화 환율은 인보이스 → 같은 통화의 발주 → null(exchange_rate_source) · ⚠️ 환율 없으면 net_unit_cad 는 null(0 아님). 거름: goods 아님 · is_payable=false(우리 쓸 것·공짜) · unit_price 0 · qty_ea ≤ 0 — 빠진 줄은 po_price_history_skipped 에 이유와 함께. 크레딧은 이번 판에 안 섞는다 — has_credit·credit_numbers 로 표시만. ⚠️ 1센트: Σ round(net_unit×qty,2) ≠ 문서 총액이 정상(끊는 횟수 차이 · AMP-778812 2,010.53 vs 2,010.54) — 원가에 쓰게 되면 레이어 배분 방식으로 맞춘다. 세트 환산 없음(세트로 주문하지 않는다). SKU 하나는 PostgREST 필터(?sku=eq.…&order=invoice_date.desc) · 전체 조회는 1,000행 상한 주의. security_invoker. 정본 po-module §11-e·§11-g';

revoke all on public.po_price_history from anon;
grant select on public.po_price_history to authenticated;

-- ═══ ② po_price_history_skipped — 확정 인보이스 줄 중 ① 에 안 나오는 것과 이유 ═══
--   왜: 조용히 빠지면 「그 제품은 산 적 없다」로 읽힌다. goods 인데 빠진 줄(not_payable · zero_price · negative_qty)은 제품이 있으니 SKU 로 보이고,
--       other(우리가 안 시킨 것 · 정본 §11-e ⬜ 할인 적용 여부 보류)는 description 으로 보인다. charge(운임)도 세지만 「예상된 빠짐」이다 — 아침 점검은 charge 를 빼고 센다.
--   ⚠️ po_line_id 가 null 인 goods 줄은 CHECK po_invoice_line_target_ck 가 막는다 — 「po_line_id null 1건」은 charge 줄(운임 187)이다. 그래서 여기 no_po_line 이유는 없다.
create or replace view public.po_price_history_skipped
  with (security_invoker = true) as
select
  i.id              as invoice_id,
  i.invoice_number,
  i.invoice_date,
  i.supplier_id,
  s.name            as supplier_name,
  il.id             as invoice_line_id,
  il.line_no,
  il.line_kind,
  pr.id             as product_id,
  pr.sku,
  coalesce(pr.name, il.description) as label,
  il.qty_ea         as qty,
  il.unit_price     as gross_unit,
  il.is_payable,
  case when il.line_kind = 'charge'  then 'charge'         -- 운임 등 비용 줄 — 가격이 아니다(예상된 빠짐)
       when il.line_kind = 'other'   then 'not_ordered'    -- 우리가 안 시킨 것 · po_line 없음 · SKU 모름
       when not il.is_payable        then 'not_payable'    -- ⓐ 우리 쓸 것 · ⓑ 공짜
       when il.unit_price <= 0       then 'zero_price'     -- 샘플·공짜 — 0 은 가격이 아니다
       when il.qty_ea <= 0           then 'negative_qty'   -- 정정 줄
       end           as reason
from public.po_invoice_line il
join public.po_invoice   i  on i.id  = il.po_invoice_id
join public.supplier     s  on s.id  = i.supplier_id
left join public.po_line pl on pl.id = il.po_line_id
left join public.product pr on pr.id = pl.product_id
where i.doc_kind = 'invoice'
  and i.status   = 'confirmed'
  and not (il.line_kind = 'goods' and il.is_payable and il.unit_price > 0 and il.qty_ea > 0);   -- ⭐ ① 의 where 와 정확히 여집합 — 둘을 합치면 확정 인보이스의 모든 줄

comment on view public.po_price_history_skipped is '⚠️ 매입 가격 이력에서 빠진 줄(2026-09-20) — 확정 인보이스(doc_kind invoice)의 줄 중 po_price_history 조건의 여집합 · reason: charge(운임 · 예상된 빠짐) · not_ordered(other · 우리가 안 시킨 것 · SKU 모름) · not_payable(우리 쓸 것·공짜) · zero_price · negative_qty(정정 줄). 왜: 조용히 빠지면 「그 제품은 산 적 없다」로 읽힌다. 아침 점검 한 줄은 reason <> ''charge'' 만 센다. ⚠️ goods 인데 po_line_id 가 null 인 줄은 CHECK 가 막으므로 그 이유는 없다. security_invoker';

revoke all on public.po_price_history_skipped from anon;
grant select on public.po_price_history_skipped to authenticated;
