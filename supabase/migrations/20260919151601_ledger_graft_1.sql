-- ─────────────────────────────────────────────────────────────
-- 원장 이식 1차 — 축을 잇는다 · IMS 잔고 뷰 · ims_last_bin 갈아 끼우기 (Asung-IMS · 2026-09-19)
--   ① ref_warehouse 'IN_TRANSIT'      원장의 합성 창고를 마스터에 한 줄(source='manual' · is_active=false) — 축이 끊기지 않게
--   ② inv_ledger.source + 'ims'        선 입고 확정이 사건을 보낼 자리 — 자리만 연다(사건을 넣는 함수는 다음 차수)
--   ③ ims_inv_balance                  ⭐⭐ 잔고 + IMS 열쇠(product_id · warehouse_id · bin_id) + 마지막 사건일 — inv_balance 위에 얹는다
--   ④ ims_ledger_unlinked              ⭐ 점검 — 원장이 쓰는 이름 중 마스터에 없는 것(kind = sku · warehouse · bin)
--   ⑤ ims_last_bin(uuid[], uuid)       ⭐⭐ 속을 원장으로 — 시그니처·반환 키 넷 무변(화면 무접촉)
--
-- 앞 차수: 20260918203805(확정 · 차이 큐 · 자동 분할). 원장 표(20260816000000~) · inv_balance(20260901163300) 무접촉 — 읽기만 한다.
-- 정본: ledger-design §2부 「테이블 다섯 개」·「운송 중 물량」 · §3부 「⭐ 대조의 시점 컷오프」(「원장이 말하는 재고」의 정의는 inv_balance 하나) ·
--       po-module §11-i(Last bin) · §11-j(사건은 원장 이식 때) · ims-principles 원칙 1·2 · 스킬 asung-inv-ledger 「조회할 때의 함정 둘」
-- 지시서: ~/asung/prompts/ims-ledger-graft-1.md · ⬜1~8 은 회신에
--
-- ⭐⭐ 이견 1 — 잔고를 **다시 정의하지 않는다.** 「기초선 + 그 뒤 원장」의 정본은 이미 inv_balance 뷰다(2026-09-01 · 기초선 키를 inv_config 에서
--   읽고 · source 를 가르지 않고 · full join · IN_TRANSIT·bin '' 을 그대로 낸다 — 지시서 §2-c 의 요구 전부가 그 정의에 이미 있다).
--   같은 식을 한 번 더 쓰면 정의가 둘이 된다 — 그 뷰가 만들어진 이유가 정확히 「정의가 세 곳에 흩어져 어느 것이 맞는지 알 수 없었다」였다.
--   ⇒ ③ 은 inv_balance 를 **읽어** IMS 열쇠와 마지막 사건일을 **붙여 내는** 뷰다. 잔고 숫자는 한 글자도 다시 계산하지 않는다.
-- ⭐ 이견 2 — 원장은 텍스트로 둔다(Caleb 1-b). 잇는 고리는 이름 셋: product.sku(유니크) · ref_warehouse.name(유니크) · ref_bin (warehouse_id, name)(유니크).
--   ⚠️ bin 은 창고 **안에서만** 유일하다(20260911165946 주석) ⇒ bin 조인은 반드시 warehouse 를 먼저 이어 (warehouse_id, name) 으로 건다. 이름만으로 걸면
--   두 창고에 같은 bin 이름이 생기는 날 조용히 두 배가 된다. 오늘 실측 「bin 1,611 전부 일치」는 이름 전역 대조였다 — ⑥ 검증이 (창고, 이름) 기준으로 다시 센다.
-- ⭐ 이견 3 — ims_last_bin 의 received_on 은 이제 **그 빈에서 그 SKU 의 마지막 사건일**(inv_ledger.occurred_on 최댓값)이다. 원장에 사건이 없고 기초선에만
--   있는 자리는 기초선 촬영일(taken_at · 토론토 날짜). 키 이름은 화면이 읽으므로 그대로 두되 뜻이 바뀐다 — 화면은 문자열로 찍기만 한다(receiving.html 521행).
-- ─────────────────────────────────────────────────────────────

-- ═══ ① ref_warehouse — IN_TRANSIT ═══
-- 트랜스퍼가 출발 창고에서 빠져 도착 창고에 들기까지 머무는 자리. 실물 창고가 아니다. 원장의 4행 구조(출발 bin → IN_TRANSIT → IN_TRANSIT → 도착 bin)가
-- 이 이름을 쓴다(inv_ledger.warehouse 주석 · inv-collect 31행: IN_TRANSIT 행은 bin=''). ⭐ 문자열은 원장 그대로 — 다르면 안 이어진다.
-- source='manual' — ref_warehouse_source_ck (cin7|manual) 에 이미 있다. cin7_id null(Cin7 창고가 아니다) · is_active false(고를 수 있는 창고가 아니다) · is_default false.
-- ⚠️ 다시 돌려도 안전: on conflict (name) do nothing. ⚠️ Cin7 재적재(ImsRefLoad.gs ims_loadWarehouse_)는 Cin7 행만 on_conflict=name merge-duplicates 로 upsert 한다 —
--   지우지도 비활성화하지도 않는다 ⇒ 이 행은 살아남는다(회신 ⬜1).
insert into public.ref_warehouse (cin7_id, name, is_active, is_default, source, note)
values (null, 'IN_TRANSIT', false, false, 'manual',
        '원장의 합성 창고 — 트랜스퍼가 출발 창고에서 빠져 도착 창고에 들기까지 머무는 자리. 실물 창고가 아니다. 원장의 4행 구조(출발 bin → IN_TRANSIT → IN_TRANSIT → 도착 bin)가 이 이름을 쓴다(inv_ledger.warehouse · IN_TRANSIT 행은 bin 없음). Cin7 에 없다(cin7_id null · source manual). 화면에서 고르는 창고가 아니다(is_active false). 2026-09-19 원장 이식 1차')
on conflict (name) do nothing;

comment on table public.ref_warehouse is 'Cin7 ref/location 의 ParentID 없는 행 대응 · PO 모듈 Settings 마스터(캐시 아님 · 우리 키 id · cin7_id 는 매핑) · name 이 inv_ledger.warehouse·wms_orders.location 과 잇는 고리 · ⭐ IN_TRANSIT 은 원장의 합성 창고 — 2026-09-19 원장 이식 1차에 source=manual · is_active=false 로 한 줄 담았다(축이 끊기지 않게 · Cin7 재적재는 Cin7 행만 upsert 하므로 남는다) · 2026-09-11 신설';

-- ═══ ② inv_ledger.source — + 'ims' ═══
-- 지금 (cin7|wms|manual) → (cin7|wms|manual|ims). ⭐ 섞이지 않는 것이 값이다 — Cin7 이 수집한 것과 IMS 가 만든 것이 source 로 갈린다.
-- ⚠️ 제약 이름은 실물(inv_ledger_source_check · 20260816000000 → 20260824140345 에서 한 번 다시 걸었다) 그대로 — drop 하고 다시 건다.
-- ⚠️ 사건을 넣는 함수는 이 차수에 없다 — 자리만 연다(§11-j · 회신 ⬜8). wms 는 쓴 적이 없지만(실측 0행) 이 차수는 빼지 않는다 — 어휘를 줄이는 것은 별건.
alter table public.inv_ledger drop constraint inv_ledger_source_check;
alter table public.inv_ledger add constraint inv_ledger_source_check
  check (source in ('cin7', 'wms', 'manual', 'ims'));
comment on column public.inv_ledger.source is 'cin7 = inv-collect 가 Cin7 문서에서 수집 · manual = 사람이 넣은 정정(상쇄) · ims = IMS 모듈이 낸 사건(2026-09-19 자리 개방 · 첫 사용은 선 입고 확정 · 다음 차수) · wms = 예약(쓴 적 없음). ⚠️ 잔고를 셀 때 source 로 거르지 마라 — 상쇄가 사라진다(스킬 「조회할 때의 함정 둘」)';

-- ═══ ③ ims_inv_balance — ⭐⭐ 잔고 + IMS 열쇠 + 마지막 사건일 ═══
-- 한 행 = inv_balance 의 한 행(sku × warehouse × bin) 그대로 — 행이 늘거나 줄지 않는다(전부 left join · 아래 ⑥ 검증 ③-c 가 행 수를 대조한다).
-- 잔고 셋(baseline_qty · delta_qty · qty)은 inv_balance 값 그대로(다시 계산하지 않는다 — 이견 1).
-- 붙이는 것:
--   product_id · warehouse_id · bin_id · bin_zone · bin_is_active   IMS 열쇠 — ⚠️ 전부 바깥 조인. 안 이어지면 null 이고 행은 남는다(FINAL-SALE 이 그 실물).
--   last_event_on    그 자리(sku·warehouse·bin)의 원장 마지막 사건일(occurred_on 최댓값) · 사건이 없으면 null
--   last_seen_on     ⭐ ims_last_bin 의 축 — last_event_on · 없으면 기초선 촬영일(taken_at 토론토 날짜 · 기초선에만 있는 자리)
--   event_rows       그 자리의 원장 행 수(0 = 기초선에만 있다)
-- ⚠️ 잔고 0 인 행도 낸다 — 「0 이 된 자리」와 「한 번도 없던 자리」는 다른 사실이고, ims_last_bin 의 2순위가 그것을 본다(회신 ⬜2).
-- ⚠️ IN_TRANSIT · bin '' 그대로 낸다(inv_balance 가 이미 그렇다) — 거르는 것은 부르는 쪽 일. bin '' 은 ref_bin 에 걸지 않는다(b.bin <> '' 가드).
-- ⚠️ bin 조인은 (warehouse_id, name) — 이름만으로 걸지 않는다(이견 2). 창고가 안 이어지면 bin 도 안 이어진다(맞다 — 그 창고의 bin 이 없다).
-- security_invoker — IMS 뷰 관례(po_list · po_receipt_list). inv_balance 자체는 소유자 뷰라 그 안쪽은 종전과 같다.
create view public.ims_inv_balance
  with (security_invoker = true) as
with baseline as (
  select value as k from public.inv_config where key = 'baseline_snapshot_key'   -- ⚠️ 키를 박지 않는다 — inv_balance 와 같은 자리에서 읽는다
),
baseline_at as (
  select (max(s.taken_at) at time zone 'America/Toronto')::date as taken_on
  from public.inv_snapshot s, baseline b
  where s.snapshot_key = b.k
),
last_ev as (
  select l.sku, l.warehouse, coalesce(l.bin, '') as bin,
         max(l.occurred_on) as last_event_on,
         count(*)::bigint   as event_rows
  from public.inv_ledger l                       -- ⚠️ source 조건 없음(함정 1)
  group by 1, 2, 3
)
select
  b.sku, b.warehouse, b.bin,
  b.baseline_qty, b.delta_qty, b.qty,
  p.id           as product_id,
  w.id           as warehouse_id,
  rb.id          as bin_id,
  rb.zone        as bin_zone,
  rb.is_active   as bin_is_active,
  le.last_event_on,
  coalesce(le.last_event_on, ba.taken_on) as last_seen_on,
  coalesce(le.event_rows, 0)              as event_rows
from public.inv_balance b
cross join baseline_at ba
left join last_ev le               on le.sku = b.sku and le.warehouse = b.warehouse and le.bin = b.bin
left join public.product       p   on p.sku  = b.sku
left join public.ref_warehouse w   on w.name = b.warehouse
left join public.ref_bin       rb  on rb.warehouse_id = w.id and rb.name = b.bin and b.bin <> '';

comment on view public.ims_inv_balance is '⭐⭐ IMS 가 읽는 잔고 — inv_balance(「원장이 말하는 재고」의 정본 · 기초선 inv_config.baseline_snapshot_key + 그 뒤 원장 · source 안 가름) 한 행에 IMS 열쇠 product_id·warehouse_id·bin_id(·bin_zone·bin_is_active)와 last_event_on(그 자리 원장 마지막 사건일)·last_seen_on(사건 없으면 기초선 촬영일)·event_rows 를 붙여 낸다. 잔고는 다시 계산하지 않는다(정의가 둘이 되지 않게). 전부 바깥 조인 — 마스터에 없는 이름(FINAL-SALE)·IN_TRANSIT·bin 빈 문자열·잔고 0 전부 그대로 낸다(거르는 것은 부르는 쪽). bin 은 (warehouse_id, name) 으로 잇는다. security_invoker. 원장 이식 1차 2026-09-19 · 정본 ledger-design §3부 컷오프 절 · po-module §11-i';
revoke all on public.ims_inv_balance from anon;
grant select on public.ims_inv_balance to authenticated;

-- ═══ ④ ims_ledger_unlinked — ⭐ 점검: 안 이어지는 이름 ═══
-- 뷰 하나 · kind 로 가른다(회신 ⬜4) — 아침 점검 한 줄이 셋을 한 번에 센다. 오늘 기준선 sku 1(FINAL-SALE) · warehouse 0(① 뒤) · bin 0.
--   sku        product.sku 에 없는 원장 SKU(잔고 행을 SKU 로 접는다)
--   warehouse  ref_warehouse.name 에 없는 창고
--   bin        (warehouse_id, name) 으로 ref_bin 에 없는 bin — ⚠️ 창고가 이어진 행만(창고가 안 이어진 것은 warehouse 로 이미 셌다 — 두 번 세지 않는다) · bin '' 제외(「자리를 모른다」는 결손이 아니다)
-- 칸: kind · warehouse · name · balance_rows(잔고 행 수) · qty_sum(잔고 합) · last_seen_on(가장 최근) — 상쇄·별칭 SQL 의 재료.
create view public.ims_ledger_unlinked
  with (security_invoker = true) as
select 'sku'::text as kind, null::text as warehouse, v.sku as name,
       count(*)::bigint as balance_rows, sum(v.qty) as qty_sum, max(v.last_seen_on) as last_seen_on
from public.ims_inv_balance v
where v.product_id is null
group by v.sku
union all
select 'warehouse', v.warehouse, v.warehouse,
       count(*)::bigint, sum(v.qty), max(v.last_seen_on)
from public.ims_inv_balance v
where v.warehouse_id is null
group by v.warehouse
union all
select 'bin', v.warehouse, v.bin,
       count(*)::bigint, sum(v.qty), max(v.last_seen_on)
from public.ims_inv_balance v
where v.warehouse_id is not null and v.bin <> '' and v.bin_id is null
group by v.warehouse, v.bin;

comment on view public.ims_ledger_unlinked is '⭐ 점검 — 원장(잔고)이 쓰는 이름 중 IMS 마스터에 없는 것. kind = sku(product.sku 에 없음) · warehouse(ref_warehouse.name 에 없음) · bin((warehouse_id,name) 으로 ref_bin 에 없음 · 창고가 이어진 행만 · 빈 문자열 제외). 기준선 2026-09-19: sku 1(FINAL-SALE) · warehouse 0 · bin 0 — 늘면 누가 이름을 고친 것이다(원장은 텍스트 · 조인이 조용히 끊긴다). 아침 점검: select kind, count(*) from ims_ledger_unlinked group by 1 order by 1. security_invoker. 원장 이식 1차 2026-09-19';
revoke all on public.ims_ledger_unlinked from anon;
grant select on public.ims_ledger_unlinked to authenticated;

-- ═══ ⑤ ims_last_bin(p_product_ids, p_warehouse_id) — ⭐⭐ 속을 원장으로 ═══
-- ⚠️⚠️ 시그니처 (uuid[], uuid) → jsonb · 반환 { "<product_id>": { bin_id, bin, zone, received_on } } 무변 — receiving.html 272행이 이 모양으로 부른다.
-- 종전 속(20260918161537): po_receipt_line 의 가장 최근 입고 줄. 새 속: ims_inv_balance —
--   1순위  지금 재고가 있는 자리(qty > 0) · 그중 마지막 사건이 최근인 것
--   2순위  없으면 마지막으로 있던 자리(qty ≤ 0 이지만 사건이 있었다 — 「0 이 된 자리」)
--   동률   qty 큰 것 → bin 이름(결정적이어야 두 번 불러 다른 답이 안 나온다)
--   (WMS 가 wms_sku_bins 에서 is_current desc, last_seen desc 로 하던 것과 같은 뜻 · 회신 ⬜5)
-- 후보에서 빼는 것: bin_id null(빈 문자열 · 마스터에 없는 bin · IN_TRANSIT 은 그 창고 자체가 p_warehouse_id 와 다르다) · 비활성 bin(물건을 거기 놓으라고 할 수 없다).
-- received_on = last_seen_on(그 빈에서 그 SKU 의 마지막 사건일 · 기초선에만 있으면 촬영일 — 이견 3). date → jsonb 문자열 'YYYY-MM-DD'(종전도 date 였다).
-- ⚠️ 원장은 낱개(base SKU)다 — 세트 product(parent_product_id 있음)의 id 로 물으면 키가 없다(원장에 그 SKU 가 없다). 화면은 po_line.product_id(낱개)를 넘긴다(종전과 같다).
-- create or replace · stable · security invoker · search_path 고정 그대로. grant·revoke 는 161537 의 것이 유지된다.
create or replace function public.ims_last_bin(p_product_ids uuid[], p_warehouse_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce(jsonb_object_agg(x.product_id::text,
           jsonb_build_object('bin_id', x.bin_id, 'bin', x.bin, 'zone', x.bin_zone, 'received_on', x.last_seen_on)), '{}'::jsonb)
  from (
    select distinct on (v.product_id)
           v.product_id, v.bin_id, v.bin, v.bin_zone, v.last_seen_on
    from public.ims_inv_balance v
    where v.product_id   = any(coalesce(p_product_ids, '{}'::uuid[]))
      and v.warehouse_id = p_warehouse_id
      and v.bin_id is not null            -- '' · 마스터에 없는 bin 은 후보 밖
      and v.bin_is_active                 -- 비활성 bin 에 놓으라고 하지 않는다
    order by v.product_id, (v.qty > 0) desc, v.last_seen_on desc, v.qty desc, v.bin
  ) x;
$$;
comment on function public.ims_last_bin(uuid[], uuid) is '⭐ 「그 제품이 그 창고에서 마지막으로 놓인 빈」 — 리시빙 풋어웨이의 Last bin 제안. ⭐ 속 = 원장(ims_inv_balance · 2026-09-19 원장 이식 1차 — 종전 po_receipt_line 속을 갈아 끼웠다 · 부르는 쪽 무접촉): 1순위 지금 재고가 있는 자리(qty>0 · 마지막 사건 최근순) → 2순위 마지막으로 있던 자리(qty≤0 · 사건 있음) · 동률 qty desc, bin. 후보 밖 = bin 빈 문자열 · 마스터에 없는 bin · 비활성 bin · IN_TRANSIT(창고가 다르다). received_on = 그 빈의 마지막 사건일(사건 없으면 기초선 촬영일). 시그니처 (uuid[], uuid) → jsonb · 반환 { "<product_id>": { bin_id, bin, zone, received_on } } 무변 · 없는 제품은 키 없음 · 빈 입력 {} · 단일 값이라 캡 밖 · security invoker · stable. ⚠️ wms_sku_bins 를 읽지 않는다(원칙 1). 정본 po-module §11-i(⬜ 갱신)';

-- ─────────────────────────────────────────────────────────────
-- 검증(회신 §4 · psql heredoc · Caleb 이 실행) 요지 — ① IN_TRANSIT 1행·재실행 중복 0 ② CHECK 넷 ③ 한 SKU 손 검산 + 창고 합 ④ null 열쇠 = sku 1·warehouse 0·bin 0
-- ⑤ ims_last_bin 키 넷·ANN05531 ⑥ 점검 뷰 기준선 ⑦ 기초선 taken_at ↔ 원장 첫 occurred_on 경계
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────
