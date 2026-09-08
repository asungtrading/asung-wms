-- 원가 레이어 — inv_layer · inv_layer_cost_add · inv_layer_consume · inv_layer_open (2026-09-08)
--
-- 배경 [조사 2026-09-08]: Cin7 은 원가 레이어를 주지 않는다. 지금 재고 187만 개 중 8/20 기초
-- 이후 입고분은 3.6% 뿐이고(칸으로는 369/13,757), 기초분은 어느 입고에서 왔는지 알 수 없다.
-- 기초 평가액은 inv_snapshot.value 에 bin 단위로 전 칸 존재한다
-- (13,844칸 · 총 $3,055,493 · 개당 $1.60).
--
-- 무엇을 하나: FIFO 원가 레이어의 **그릇**을 만든다.
--  · inv_layer          — 레이어 하나 = 한 창고에 들어온 한 덩어리(sku·warehouse·received_on·qty·unit_cost)
--  · inv_layer_cost_add — 레이어에 나중에 얹히는 원가(landed · transfer_freight)
--  · inv_layer_consume  — 레이어에서 빠져나간 수량(sale·transfer·adjust_out·assembly_in·reversal)
--  · inv_layer_open     — 잔량 > 0 인 레이어 + remaining_qty · total_cost · remaining_cost (뷰)
-- ⚠️ 아직 아무것도 쌓지 않는다. 이 마이그레이션은 그릇만 만든다.
--    레이어를 채우는 함수는 다음 단계다.
--
-- ⚠️⚠️ 불변 조건 — 레이어는 inv_ledger + inv_cost 로 전량 재생성 가능해야 한다.
--  손으로 만든 값을 넣지 않는다. 이것이 나중에 bin 층을 추가할 수 있는 유일한
--  근거다(지금은 창고 단위 · bin 은 line_ref 로 inv_cost 를 조인하면 입고 시점
--  값이 나온다).
--
-- ⚠️ inv_layer 에 유니크 제약을 일부러 걸지 않았다 — 자연키가 성립하지 않는다:
--  부분입고(같은 PO 라인이 두 회차로 정상 분할) · 트랜스퍼 분할(한 TR 이 여러
--  출발 레이어에 걸치면 도착에 여러 개가 정상 생성) · baseline 은 doc_number 가
--  null 이라 Postgres 유니크가 아예 안 걸린다. 제약을 걸면 정상을 막고 정작
--  이중 처리는 통과시킨다. ⇒ 이중 처리는 inv_layer_open 잔량 합계 vs
--  inv_balance 대조로 잡는다(원장이 수량 축의 채점자다).
--
-- ⭐ inv_layer_cost_add 는 반대로 유니크가 필수다 — 수집기가 같은 문서를 매일
--  다시 읽으므로 제약이 없으면 원가가 무한히 커진다(inv_cost 가 upsert 인 것과
--  같은 이유).
--
-- 컬럼 의미
--  · inv_layer.origin_type — 레이어가 생긴 사건(baseline·purchase·transfer·adjust_new·
--    adjust_existing·assembly·creditnote). cost_source — unit_cost 를 어디서 가져왔나
--    (inv_cost·snapshot_value·cin7_unitcost·layer_avg·assembly_sum·parent_layer).
--  · age_known — 기초 레이어는 received_on=2026-08-20 으로 FIFO 정렬은 맞게
--    하되 실제 입고일을 모른다. stock aging summary 는 age_known=false 를
--    「미상」으로 분리해야 한다. ⚠️ 8/20 이전 재고의 나이 소급은 설계 범위 밖이다
--    (현 시스템에서 별도로 본다).
--    ⚠️ default 를 일부러 두지 않았다 — 기초 13,844칸을 넣을 때 false 를 빠뜨리면
--    aging summary 가 통째로 틀리는데 그 실패가 눈에 보이지 않는다. 넣는 쪽이
--    매번 명시하게 한다(「모르면 비워둔다」).
--  · parent_layer_id — 트랜스퍼는 소비가 아니라 이동이다. 출발 레이어를 소비하고
--    도착 창고에 원가·received_on·age_known 을 복사한 레이어를 만든다.
--    IN_TRANSIT 은 원장과 동일하게 창고로 취급하므로(4행 구조) 사슬은
--    PO → IN_TRANSIT → 도착창고 3단이 된다. ⚠️ 8/20 이전 출발분은 leg 1·2 가
--    원장에 없어 parent 가 없다 — 기초와 같은 취급(원가 미상)이고 재기준선이 지운다.
--  · inv_layer_cost_add.kind — landed 는 PO 의 Service Invoice(통관·freight·관세)로
--    advanced-purchase 의 InventoryMovements 에서 온다. transfer_freight 는
--    창고간 트랜스퍼 운송비로 stockTransfer.ManualJournals 에서 오고
--    Debit='_59_'(재고) 만 대상이다 — '_95_' 는 손익이라 제외.
--    ⚠️ 두 종류 모두 occurred_on 이 인보이스 날짜라 입고일보다 앞설 수도 뒤설 수도
--    있다(실측: PO 8건은 앞 · PO-01198 은 뒤 · 트랜스퍼는 완료일 +1~2일).
--    ⚠️ 트랜스퍼 운송비는 개당 $0.26 = 재고 단가의 16% 규모다(실측 TR-03975
--    1,550개 $398.75) — PO landed(개당 0.2센트)와 자릿수가 다르다.
--    ⚠️ Service Invoice 한 장이 여러 문서에 쪼개진다(실측 B6880391 → TR-03531~34).
--    Cin7 이 문서 단위로 배분해 주므로 우리는 인보이스를 직접 읽지 않는다.
--  · inv_layer_consume.reason — 왜 빠졌나(sale·transfer·adjust_out·assembly_in·reversal).
--    unit_cost·amount 는 소비 시점 레이어 단가의 스냅샷이다.
--  · inv_layer_open.total_cost 는 **레이어 전체**의 원가(unit_cost×qty + 얹힌 원가)이고
--    이미 소비된 몫까지 포함한다. 재고 평가액에 쓸 값은 remaining_cost 다.
--    ⚠️ 둘을 혼동하면 평가액이 과대계상된다.
--
-- 조회 예시: select * from inv_layer_open order by sku, warehouse, received_on;

create table if not exists inv_layer (
  id              bigint generated always as identity primary key,
  sku             text not null,
  warehouse       text not null,
  origin_type     text not null,
  doc_number      text,
  line_ref        text,
  parent_layer_id bigint references inv_layer(id),
  received_on     date not null,
  age_known       boolean not null,
  qty             numeric not null,
  unit_cost       numeric not null,
  cost_source     text not null,
  created_at      timestamptz not null default now(),
  constraint inv_layer_qty_ck  check (qty > 0),
  constraint inv_layer_cost_ck check (unit_cost >= 0),
  constraint inv_layer_origin_ck check (origin_type in (
    'baseline','purchase','transfer','adjust_new',
    'adjust_existing','assembly','creditnote')),
  constraint inv_layer_source_ck check (cost_source in (
    'inv_cost','snapshot_value','cin7_unitcost',
    'layer_avg','assembly_sum','parent_layer'))
);

create index if not exists inv_layer_fifo_idx
  on inv_layer (sku, warehouse, received_on, id);
create index if not exists inv_layer_doc_idx
  on inv_layer (origin_type, doc_number);
create index if not exists inv_layer_parent_idx
  on inv_layer (parent_layer_id);

create table if not exists inv_layer_cost_add (
  id          bigint generated always as identity primary key,
  layer_id    bigint not null references inv_layer(id),
  kind        text not null,
  amount      numeric not null,
  occurred_on date not null,
  doc_number  text not null,
  line_ref    text not null,
  ref_number  text,
  created_at  timestamptz not null default now(),
  constraint inv_layer_cost_add_kind_ck check (kind in ('landed','transfer_freight')),
  constraint inv_layer_cost_add_uq
    unique (layer_id, kind, doc_number, line_ref, occurred_on)
);

create index if not exists inv_layer_cost_add_layer_idx
  on inv_layer_cost_add (layer_id);

create table if not exists inv_layer_consume (
  id          bigint generated always as identity primary key,
  layer_id    bigint not null references inv_layer(id),
  doc_type    text not null,
  doc_number  text not null,
  line_ref    text not null,
  event_type  text not null,
  occurred_on date not null,
  qty         numeric not null,
  unit_cost   numeric not null,
  amount      numeric not null,
  reason      text not null,
  created_at  timestamptz not null default now(),
  constraint inv_layer_consume_qty_ck check (qty > 0),
  constraint inv_layer_consume_reason_ck check (reason in (
    'sale','transfer','adjust_out','assembly_in','reversal'))
);

create index if not exists inv_layer_consume_layer_idx
  on inv_layer_consume (layer_id);
create index if not exists inv_layer_consume_doc_idx
  on inv_layer_consume (doc_type, doc_number);

create or replace view inv_layer_open as
select l.*,
       l.unit_cost * l.qty + coalesce(a.add_amt, 0) as total_cost,
       l.qty - coalesce(c.used, 0)                  as remaining_qty,
       round((l.unit_cost * l.qty + coalesce(a.add_amt, 0))
             / l.qty * (l.qty - coalesce(c.used, 0)), 6) as remaining_cost
from inv_layer l
left join (select layer_id, sum(qty) as used
           from inv_layer_consume group by 1) c on c.layer_id = l.id
left join (select layer_id, sum(amount) as add_amt
           from inv_layer_cost_add group by 1) a on a.layer_id = l.id
where l.qty - coalesce(c.used, 0) > 0;

alter table inv_layer enable row level security;
create policy auth_all on inv_layer for all to authenticated using (true) with check (true);
revoke all on inv_layer from anon;
revoke delete, truncate on inv_layer from authenticated;

alter table inv_layer_cost_add enable row level security;
create policy auth_all on inv_layer_cost_add for all to authenticated using (true) with check (true);
revoke all on inv_layer_cost_add from anon;
revoke delete, truncate on inv_layer_cost_add from authenticated;

alter table inv_layer_consume enable row level security;
create policy auth_all on inv_layer_consume for all to authenticated using (true) with check (true);
revoke all on inv_layer_consume from anon;
revoke delete, truncate on inv_layer_consume from authenticated;

-- 뷰는 소유자 권한으로 돈다(security_invoker 아님) — anon 에 열어두면 원본 테이블의 RLS·회수를
-- 우회해 원가가 노출된다(inv_balance 와 같은 처리).
revoke all on inv_layer_open from anon;
