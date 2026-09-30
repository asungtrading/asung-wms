-- cogs-2 둘째 차수(판정 105 ~ 108 · 110 · 111 · 113 · 114 · 2026-09-30) — 빠질 때 얹힌 몫까지 · 얹힐 때 셋으로 나누기 · 식은 한 함수에
--   ① inv_layer_value(레이어) — 남은 수량 · 남은 가치(= 단가 × 처음 수량 + Σ얹힌 − Σ나간) · 한 병 원가(남은 가치 ÷ 남은 수량) · 처음 한 병(full_unit) — 뷰 · 소진 · 평균 다섯 · 최근 둘 · 크레딧 취소가 이것만 부른다(판정 111)
--   ② inv_layer_fifo_take — 소진 단가 · 금액 = 한 병 원가 · 레이어를 비우면 남은 가치 전부(끝수 없음) · 자식(트랜스퍼) 레이어는 부모 goods 단가 그대로 + 선 순간 inv_layer_carry(판정 105 · 106 · 110)
--   ③ inv_layer_cost_add_settle(얹기 줄) — 얹히는 순간 셋으로: 남은 몫 → 그 레이어 · 옮겨 간 몫 → 자식 carried(재귀) + 부모 cost_moved · 팔리거나 빠진 몫 → cost_late(수량 0 · 금액만 · split_basis 에 근거 · 판정 107 · 108 · 113) · ⭐ 판정 118 문 셋(같은 트랜잭션 xmin · 트랜잭션 안 한 번 · 이미 쓴 줄) — 열어 두되 함수 안에서 멱등
--      inv_layer_post_charge · 재생성 속 함수의 불러온 landed · transfer_freight · inv_layer_carry 가 새로 든 얹기 줄마다 부른다(얹기 줄이 새로 들어갔을 때만 · on conflict do nothing · 부분 유니크 없음)
--   ④ inv_layer_carry — 「IMS 트랜스퍼만」 문을 연다(불러온 축 TR- 자식도 · 판정 110) · 비춘 행마다 settle
--   ⑤ inv_layer_post_charge(charge · p_on · p_alloc) — 얹기 줄 날짜 = 얹히는 순간의 토론토 날짜(ims_today · 판정 114) · 배분 줄에 posted_on · posted_ledger_id 를 남긴다(재생성이 같은 자리 · 같은 날 안의 앞뒤까지 재현하는 근거) · 재생성은 p_on · p_alloc 으로 부른다
--   ⑥ inv_layer_apply_flush_adds(day · until · before_id · acc) · inv_layer_apply — IMS 비용은 배분 줄 단위로 posted_on 자리(줄 id 트리거 · 같은 날 안의 앞뒤) · posted_on 없는 옛 배분 줄은 첫 차수 규칙(charge_date · 레이어가 선 뒤) · 불러온 landed · transfer_freight 는 첫 차수 자리 그대로(판정 115-1)
--   ⑦ 그릇 — inv_layer_consume.split_basis(jsonb) · CHECK qty > 0 or (reason in (cost_late, cost_moved) and qty = 0) · reason +2 · po_charge_alloc.posted_on · posted_ledger_id(+ 기존 IMS 얹기 5행의 배분 줄 셋 백필: 얹기 줄 created_at 의 토론토 날짜 · 그때의 원장 최대 id)
--   ⚠️ 합격(판정 113-6): 모든 레이어 「단가 × 처음 + Σ얹힌 − Σ나간 − 남은 가치 = 0」 · 수량 0 레이어의 남은 가치 0 · 실시간 = 재생성 · 얹힌 것 없는 레이어 무변 — 검증 ~/asung/prompts/cogs-3-verify.sql · 판정 112: 이 차수는 재생성을 커밋하지 않는다
--   UTC 이름 · 가드 첫 문장 · begin/commit 없음 · 부분 유니크 0 · 시퀀스 무접촉 · 시그니처가 바뀐 둘(post_charge · flush_adds)은 drop 뒤 create

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


-- ═══ 1) 그릇 — 소진 표 나눌 근거 칸 · CHECK 둘 · 배분 줄 확정 순간 둘 · 옛 IMS 얹기의 배분 줄 백필 ═══
alter table public.inv_layer_consume add column if not exists split_basis jsonb;
comment on column public.inv_layer_consume.split_basis is 'cogs-2(판정 108 · 113-3) — 늦게 온 비용을 나눈 근거(cost_late · cost_moved 줄에만 · 나머지 null): kind · add_amount · layer_qty · used_qty · sold_qty · ratio · items[{doc_type doc_number line_ref reason occurred_on qty share}] / moved_qty · children[{doc_number line_ref warehouse qty share}] — 회계사가 오더별 배분이라고 답하면 이것으로 나눠 붙인다';
alter table public.inv_layer_consume drop constraint inv_layer_consume_qty_ck;
alter table public.inv_layer_consume add constraint inv_layer_consume_qty_ck check (qty > 0 or (reason in ('cost_late', 'cost_moved') and qty = 0));   -- cogs-2(판정 113-1): 나간 몫 줄만 수량 0
alter table public.inv_layer_consume drop constraint inv_layer_consume_reason_ck;
alter table public.inv_layer_consume add constraint inv_layer_consume_reason_ck check (reason in ('sale', 'transfer', 'adjust_out', 'assembly_in', 'reversal', 'lost', 'cost_late', 'cost_moved'));   -- cogs-2: cost_late = 팔리거나 빠진 몫 · cost_moved = 트랜스퍼로 옮겨 간 몫(자식 carried 와 같은 돈 · 매출원가 아님)
alter table public.po_charge_alloc add column if not exists posted_on date, add column if not exists posted_ledger_id bigint;
comment on column public.po_charge_alloc.posted_on is 'cogs-2(판정 114) — 이 배분 줄이 실제로 레이어에 얹힌 토론토 날짜(비용 확정 · 입고 확정 · 도착 순간) · 얹기 줄 · 나간 몫 줄의 occurred_on 과 같다 · null = 아직 안 얹힘(재생성은 첫 차수 규칙 charge_date)';
comment on column public.po_charge_alloc.posted_ledger_id is 'cogs-2(판정 114) — 얹히는 순간의 원장 최대 id · 재생성이 같은 날 안에서 이 id 뒤 · 앞을 가른다(실시간이 남긴 근거 · 17-f (가) 모양)';
with s as (
  select ca.line_ref::uuid as alloc_id, min(ca.created_at) as t
    from public.inv_layer_cost_add ca
   where ca.kind = 'landed' and ca.ref_number is not null and ca.line_ref ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
   group by ca.line_ref)
update public.po_charge_alloc a
   set posted_on = (s.t at time zone 'America/Toronto')::date,
       posted_ledger_id = (select max(g.id) from public.inv_ledger g where g.created_at <= s.t)
  from s where a.id = s.alloc_id and a.posted_on is null;


-- ═══ 2) 한 함수 — inv_layer_value(레이어): 남은 수량 · 남은 가치 · 한 병 원가 · 처음 한 병(판정 106 · 111) ═══
--   남은 가치 = unit_cost × qty + Σcost_add.amount − Σconsume.amount(수량 0 줄 포함) · 한 병 원가 = 남은 가치 ÷ 남은 수량(6자리 · 남은 수량 0 이면 null)
--   full_unit = (unit_cost × qty + Σ얹힌) ÷ qty — 「최근 원가」(layer_recent · 소진 무관 · 다 나간 레이어에도 값이 있다) · 아무것도 안 나갔으면 한 병 원가와 같다
--   ⚠️ 판정 31 은 재생성 계열의 회수다 — 이 함수는 화면 미리보기(inv_adjust_eval · invoker · authenticated)가 부르므로 authenticated 에 execute 를 준다(뷰 inv_layer_open 이 이미 같은 값을 authenticated 에 보인다)
create or replace function public.inv_layer_value(p_layer_id bigint)
  returns table(qty numeric, add_amount numeric, used_qty numeric, used_amount numeric, remaining_qty numeric, remaining_value numeric, unit_cost numeric, full_unit numeric)
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select l.qty, coalesce(a.s, 0), coalesce(c.q, 0), coalesce(c.a, 0),
         l.qty - coalesce(c.q, 0),
         l.unit_cost * l.qty + coalesce(a.s, 0) - coalesce(c.a, 0),
         case when l.qty - coalesce(c.q, 0) > 0 then round((l.unit_cost * l.qty + coalesce(a.s, 0) - coalesce(c.a, 0)) / (l.qty - coalesce(c.q, 0)), 6) end,
         round((l.unit_cost * l.qty + coalesce(a.s, 0)) / l.qty, 6)
    from public.inv_layer l
    left join lateral (select sum(x.amount) as s from public.inv_layer_cost_add x where x.layer_id = l.id) a on true
    left join lateral (select sum(k.qty) as q, sum(k.amount) as a from public.inv_layer_consume k where k.layer_id = l.id) c on true
   where l.id = p_layer_id
$$;
comment on function public.inv_layer_value(bigint) is '⭐ cogs-2(판정 106 · 111) 원가 레이어의 식 하나 — 남은 수량 · 남은 가치(단가 × 처음 + Σ얹힌 − Σ나간) · 한 병 원가(남은 가치 ÷ 남은 수량) · 처음 한 병(full_unit · 최근 원가) — 뷰 inv_layer_open · inv_layer_fifo_take · layer_avg 다섯 곳 · layer_recent 두 곳 · so_credit_cancel 이 이것만 부른다(스스로 계산하는 자리 0)';
revoke all on function public.inv_layer_value(bigint) from public, anon;
grant execute on function public.inv_layer_value(bigint) to authenticated;


-- ═══ 3) 뷰 inv_layer_open — 같은 칸 · remaining_cost = 남은 가치(한 함수) · total_cost 뜻 그대로(단가 × 수량 + Σ얹힌 · 나간 몫 포함) ═══
create or replace view public.inv_layer_open as
select l.*,
       l.unit_cost * l.qty + v.add_amount as total_cost,
       v.remaining_qty                     as remaining_qty,
       round(v.remaining_value, 6)         as remaining_cost
  from public.inv_layer l cross join lateral public.inv_layer_value(l.id) v
 where v.remaining_qty > 0;
revoke all on public.inv_layer_open from anon;


-- ═══ 4) inv_layer_cost_add_settle(얹기 줄) — 얹히는 순간 셋으로(판정 107 · 108 · 113 · 116) · 문 셋(판정 118) · 새로 든 얹기 줄마다 한 번 ═══
--   옮겨 간 몫: 이 레이어의 트랜스퍼 자식마다 amount × 자식 qty ÷ 부모 처음 qty(6자리 · inv_layer_carry 와 같은 식) → 자식 carried(같은 키 · on conflict do nothing) → 자식도 정산(재귀 · 손자까지) · 새로 든 것만 부모 cost_moved 로 나간다
--     (자식이 선 순간 carry 가 이미 비춘 몫은 그때 부모 소진 금액(한 병 원가)에 들어 있었다 — 두 번 세지 않는다)
--   팔리거나 빠진 몫: (나간 수량 − 자식으로 간 수량) ÷ 처음 수량 × amount · 레이어가 다 나갔으면 amount − 옮긴 몫(끝수가 수량 0 에 남지 않게) → cost_late 한 줄(수량 0 · 금액만 · split_basis 에 소진 기록마다 qty · share)
--   남은 몫: 얹기 줄이 레이어에 그대로 — 남은 가치가 저절로 그만큼 오른다
--   ⭐ 판정 116(Caleb 「좋아 A」): 나간 몫 줄 reason 은 둘 — cost_late(팔리거나 빠진 몫 = 매출원가) · cost_moved(트랜스퍼로 옮겨 간 몫 = 자식 carried 와 같은 돈 · 매출원가 아님) · 둘 다 수량 0 · split_basis
--   ⭐ 판정 118(Caleb 「A」 · 2026-09-30) 원문: inv_layer_cost_add_settle 은 authenticated 에 열어 두되 함수 안에서 멱등(이미 나간 몫 줄이 있으면 쓰지 않고 0) · 검증에 「두 번 부르면 두 번째 0 행」 · inv_layer_value(읽기만)는 열어 둔다 · 기각 B 막고 창구를 definer 로
--     + 대화 Claude 의 요구: 「이미 있으면 안 쓴다」만으로는 모자란다 — 얹을 때 나간 것이 0 인 레이어는 첫 호출이 아무것도 안 쓴다 · 그 뒤 판매가 운임을 품은 원가(판정 106)로 나간 다음 settle 을 다시 부르면 그 판매를 늦은 몫으로 두 번 센다 ⇒ 그 얹기 줄을 넣은 바로 그 트랜잭션 안에서만 · 한 번만
--   문 ① 같은 트랜잭션 — 얹기 줄의 xmin(넣은 (서브)트랜잭션 id)이 pg_xact_status 로 「in progress」여야 한다. 다른 세션의 진행 중 행은 이 트랜잭션에 보이지 않으므로, 보이는데 진행 중 = 지금 최상위 트랜잭션(서브트랜잭션 포함).
--        [PG 17.6 실측 2026-09-30] 직접 insert 한 행 · exception 블록(서브트랜잭션) 안에서 insert 한 행(xmin 이 최상위 xid 와 다르다) 둘 다 in progress · 옛 행은 committed · 아주 옛 행은 null(모른다 = 이 트랜잭션 아님)
--        ⚠️ now() · created_at 비교 금지(한 트랜잭션 안 now() 는 하나 · 판정 103 사고) · xid8 = 현재 최상위 xid 의 epoch × 2^32 + xmin(32비트) · 32비트 거리로 epoch 경계를 가른다(모듈러)
--   문 ② 이 트랜잭션에서 이미 정산한 얹기 줄 — 트랜잭션 지역 설정 inv.settled_adds(id 목록 · set_config(…, true)) · 서브트랜잭션이 되돌아가면 함께 되돌아간다(실측) · 얹을 때 나간 것이 0 이라 아무것도 안 썼어도 「정산했다」로 남는다(위 요구)
--   문 ③ 이미 쓴 나간 몫 줄 — 같은 레이어 · 같은 얹기 키(doc_number · line_ref · occurred_on · split_basis.kind)의 cost_late · cost_moved 가 있으면 0 · 자식 carried 는 not exists(on conflict) 그대로
--   세 문 다 예외가 아니라 0 을 돌려준다(재생성 · 창구가 멈추지 않는다) · 반환 rows_written(이 호출과 재귀가 쓴 행 수) · skipped(문에 걸린 이유 · 없으면 null)
--   부르는 쪽: inv_layer_post_charge · inv_layer_apply_flush_adds(불러온 landed · transfer_freight) · inv_layer_carry — 셋 다 얹기 줄을 넣은 같은 트랜잭션에서 곧바로 부른다
create or replace function public.inv_layer_cost_add_settle(p_add_id bigint) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_layer_cost_add_settle@2026-09-30.2';
  v_a         public.inv_layer_cost_add%rowtype;
  v_l         public.inv_layer%rowtype;
  v_xmin32    numeric;
  v_top       numeric;
  v_top32     numeric;
  v_epoch     numeric;
  v_status    text;
  v_list      text;
  v_used      numeric;
  v_child_qty numeric;
  v_sold_qty  numeric;
  v_sold_amt  numeric := 0;
  v_moved_amt numeric := 0;
  v_share     numeric;
  v_cid       bigint;
  v_n_carried int := 0;
  v_rows      int := 0;
  v_children  jsonb := '[]'::jsonb;
  v_items     jsonb;
  v_item_qty  numeric;
  v_sub       jsonb;
  ch          record;
begin
  select * into v_a from public.inv_layer_cost_add a where a.id = p_add_id;
  if not found then raise exception 'inv_layer_cost_add % not found — nothing was settled', p_add_id; end if;
  select a.xmin::text::numeric into v_xmin32 from public.inv_layer_cost_add a where a.id = p_add_id;   -- 넣은 (서브)트랜잭션 id(32비트)
  -- 문 ① 같은 트랜잭션(판정 118 + 요구)
  v_top   := pg_current_xact_id()::text::numeric;
  v_top32 := v_top - floor(v_top / 4294967296) * 4294967296;
  v_epoch := floor(v_top / 4294967296);
  if v_xmin32 - v_top32 > 2147483648 then v_epoch := v_epoch - 1; elsif v_xmin32 - v_top32 < -2147483648 then v_epoch := v_epoch + 1; end if;
  v_status := pg_xact_status(((v_epoch * 4294967296 + v_xmin32)::bigint)::text::xid8);
  if v_status is distinct from 'in progress' then
    return jsonb_build_object('add_id', p_add_id, 'rows_written', 0, 'skipped', 'not_this_transaction', 'xact_status', v_status, 'builder', c_version);
  end if;
  -- 문 ② 이 트랜잭션에서 이미 정산한 얹기 줄
  v_list := coalesce(current_setting('inv.settled_adds', true), '');
  if position(',' || p_add_id::text || ',' in ',' || v_list || ',') > 0 then
    return jsonb_build_object('add_id', p_add_id, 'rows_written', 0, 'skipped', 'already_settled_in_this_transaction', 'builder', c_version);
  end if;
  -- 문 ③ 이미 쓴 나간 몫 줄(같은 얹기 키)
  if exists (select 1 from public.inv_layer_consume k
              where k.layer_id = v_a.layer_id and k.reason in ('cost_late', 'cost_moved')
                and k.doc_number = v_a.doc_number and k.line_ref = v_a.line_ref and k.occurred_on = v_a.occurred_on and k.split_basis ->> 'kind' = v_a.kind) then
    return jsonb_build_object('add_id', p_add_id, 'rows_written', 0, 'skipped', 'already_written', 'builder', c_version);
  end if;
  perform set_config('inv.settled_adds', case when v_list = '' then p_add_id::text else v_list || ',' || p_add_id::text end, true);

  select * into v_l from public.inv_layer l where l.id = v_a.layer_id;
  if v_l.qty <= 0 then return jsonb_build_object('add_id', p_add_id, 'rows_written', 0, 'skipped', 'layer_qty_zero', 'builder', c_version); end if;

  -- ① 옮겨 간 몫 → 자식 carried(재귀 정산)
  for ch in select y.* from public.inv_layer y where y.parent_layer_id = v_l.id and y.origin_type = 'transfer' order by y.id loop
    v_share := round(v_a.amount * ch.qty / v_l.qty, 6);
    v_cid := null;
    insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
    values (ch.id, 'carried', v_share, v_a.occurred_on, v_a.doc_number, v_a.line_ref, 'layer:' || v_l.id::text || ':' || v_a.kind)
    on conflict on constraint inv_layer_cost_add_uq do nothing
    returning id into v_cid;
    if v_cid is null then continue; end if;
    v_n_carried := v_n_carried + 1;  v_rows := v_rows + 1;  v_moved_amt := v_moved_amt + v_share;
    v_children := v_children || jsonb_build_object('doc_number', ch.doc_number, 'line_ref', ch.line_ref, 'warehouse', ch.warehouse, 'qty', ch.qty, 'share', v_share);
    v_sub := public.inv_layer_cost_add_settle(v_cid);
    v_n_carried := v_n_carried + coalesce((v_sub ->> 'carried_rows')::int, 0);
    v_rows := v_rows + coalesce((v_sub ->> 'rows_written')::int, 0);
  end loop;

  -- ② 팔리거나 빠진 몫 → cost_late 한 줄
  select coalesce(sum(k.qty), 0) into v_used from public.inv_layer_consume k where k.layer_id = v_l.id;
  select coalesce(sum(y.qty), 0) into v_child_qty from public.inv_layer y where y.parent_layer_id = v_l.id and y.origin_type = 'transfer';
  v_sold_qty := greatest(v_used - v_child_qty, 0);
  if v_sold_qty > 0 then
    if v_l.qty - v_used <= 0 then v_sold_amt := v_a.amount - v_moved_amt;                        -- 판정 107: 다 나간 레이어도 이 길 · 수량 0 에 가치가 남지 않는다
    else v_sold_amt := round(v_a.amount * v_sold_qty / v_l.qty, 6); end if;
    select coalesce(jsonb_agg(jsonb_build_object('doc_type', k.doc_type, 'doc_number', k.doc_number, 'line_ref', k.line_ref, 'reason', k.reason, 'occurred_on', k.occurred_on,
                                                 'qty', k.qty, 'share', round(v_a.amount * k.qty / v_l.qty, 6)) order by k.occurred_on, k.id), '[]'::jsonb),
           coalesce(sum(k.qty), 0)
      into v_items, v_item_qty
      from public.inv_layer_consume k where k.layer_id = v_l.id and k.qty > 0 and k.reason <> 'transfer';
    if v_item_qty <> v_sold_qty then v_items := v_items || jsonb_build_object('reason', 'transfer_without_child', 'qty', v_sold_qty - v_item_qty); end if;
    if v_sold_amt <> 0 then
      insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason, split_basis)
      values (v_l.id, 'cost', v_a.doc_number, v_a.line_ref, 'cost_add', v_a.occurred_on, 0, 0, v_sold_amt, 'cost_late',
              jsonb_build_object('kind', v_a.kind, 'add_amount', v_a.amount, 'layer_qty', v_l.qty, 'used_qty', v_used, 'sold_qty', v_sold_qty,
                                 'ratio', round(v_sold_qty / v_l.qty, 6), 'items', v_items, 'builder', c_version));
      v_rows := v_rows + 1;
    end if;
  end if;
  if v_moved_amt <> 0 then
    insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason, split_basis)
    values (v_l.id, 'cost', v_a.doc_number, v_a.line_ref, 'cost_add', v_a.occurred_on, 0, 0, v_moved_amt, 'cost_moved',
            jsonb_build_object('kind', v_a.kind, 'add_amount', v_a.amount, 'layer_qty', v_l.qty, 'moved_qty', v_child_qty, 'children', v_children, 'builder', c_version));
    v_rows := v_rows + 1;
  end if;
  return jsonb_build_object('add_id', p_add_id, 'layer_id', v_l.id, 'kind', v_a.kind, 'amount', v_a.amount, 'used_qty', v_used, 'sold_qty', v_sold_qty,
                            'sold_amount', v_sold_amt, 'moved_amount', v_moved_amt, 'carried_rows', v_n_carried, 'rows_written', v_rows, 'skipped', null, 'builder', c_version);
end;
$$;
comment on function public.inv_layer_cost_add_settle(bigint) is '⭐ cogs-2(판정 107 · 108 · 113 · 116 · 118) 얹기 줄 정산 — 새로 든 inv_layer_cost_add 행 하나를 셋으로: 남은 몫(레이어에 그대로) · 옮겨 간 몫(자식 carried · 재귀 · 부모 cost_moved) · 팔리거나 빠진 몫(cost_late · 수량 0 · split_basis 근거) · 다 나간 레이어는 amount − 옮긴 몫 · ⭐ 판정 118 「authenticated 에 열어 두되 함수 안에서 멱등(이미 나간 몫 줄이 있으면 쓰지 않고 0)」 + 그 뜻을 지키는 문 셋: ① 그 얹기 줄을 넣은 지금 트랜잭션 안에서만(xmin 이 pg_xact_status in progress · 서브트랜잭션 포함 · now() 아님) ② 이 트랜잭션에서 한 번만(트랜잭션 지역 설정 inv.settled_adds) ③ 같은 얹기 키의 cost_late · cost_moved 가 있으면 0 · 셋 다 예외 없이 0(rows_written · skipped) · 부르는 쪽: inv_layer_post_charge · inv_layer_apply_flush_adds · inv_layer_carry';
revoke all on function public.inv_layer_cost_add_settle(bigint) from public, anon;
grant execute on function public.inv_layer_cost_add_settle(bigint) to authenticated;   -- 창구 inv_layer_post_charge(invoker · authenticated)가 부른다 — inv_layer_carry 와 같은 예외(판정 31) · 판정 118: 열어 두되 함수 안에서 멱등


-- ═══ 5) inv_layer_carry — 원본 20260929025719:52 재발행 · 「IMS 트랜스퍼(inv_transfer 에 있는 문서)만」 문을 연다(판정 110) · 비춘 행마다 settle ═══
create or replace function public.inv_layer_carry(p_layer_id bigint) returns int
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_y public.inv_layer%rowtype; v_p public.inv_layer%rowtype; v_n int := 0; v_cid bigint; v_a record; v_c record; v_sub jsonb;
begin
  select * into v_y from public.inv_layer y where y.id = p_layer_id;
  if not found then return 0; end if;
  -- ① 이 레이어가 트랜스퍼 자식이면(어느 축이든 · cogs-2 판정 110) 부모의 얹힌 행 중 아직 안 비춘 것을 한 병당 비율로(amount × 자식 처음 qty ÷ 부모 처음 qty · 6자리) · 새로 든 행마다 정산(자식에 이미 나간 것이 있으면 그 몫은 자식의 cost_late · 손자에는 carried)
  if v_y.origin_type = 'transfer' and v_y.parent_layer_id is not null then
    select * into v_p from public.inv_layer p where p.id = v_y.parent_layer_id;
    if found and v_p.qty > 0 then
      for v_a in select a.* from public.inv_layer_cost_add a where a.layer_id = v_p.id order by a.id loop
        v_cid := null;
        insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
        values (v_y.id, 'carried', round(v_a.amount * v_y.qty / v_p.qty, 6), v_a.occurred_on, v_a.doc_number, v_a.line_ref, 'layer:' || v_p.id::text || ':' || v_a.kind)
        on conflict on constraint inv_layer_cost_add_uq do nothing
        returning id into v_cid;
        if v_cid is null then continue; end if;
        v_n := v_n + 1;
        v_sub := public.inv_layer_cost_add_settle(v_cid);
        v_n := v_n + coalesce((v_sub ->> 'carried_rows')::int, 0);
      end loop;
    end if;
  end if;
  -- ② 이 레이어의 트랜스퍼 자식으로 내려간다(사슬 · 얹힌 행이 나중에 온 경우 = 이미 떠난 몫)
  for v_c in select c.id from public.inv_layer c where c.parent_layer_id = p_layer_id and c.origin_type = 'transfer' order by c.id loop
    v_n := v_n + public.inv_layer_carry(v_c.id);
  end loop;
  return v_n;
end;
$$;
revoke all on function public.inv_layer_carry(bigint) from public, anon;
grant execute on function public.inv_layer_carry(bigint) to authenticated;
comment on function public.inv_layer_carry(bigint) is 'tr-4b(판정 79) — 트랜스퍼 자식 레이어에 부모의 얹힌 원가(landed · transfer_freight · carried)를 한 병당 비율로 따라가게 한다 · ⭐ cogs-2(판정 110): IMS 만이 아니라 불러온 축(TR- · parent_layer) 자식에도 · 비춘 행마다 inv_layer_cost_add_settle(자식에 이미 나간 몫은 cost_late · 손자 carried) · 부르는 곳: inv_layer_fifo_take(자식이 선 순간) · 재생성 끝 검산 바퀴(0 이어야 한다) · 멱등 · authenticated 허용(판정 31 예외 · 창구가 부른다)';


-- ═══ 6) inv_layer_fifo_take — 원본 20260909233729:71 재발행 · 소진 단가 · 금액 = 한 병 원가(inv_layer_value) · 비우면 남은 가치 전부 · 자식이 선 순간 carry(판정 105 · 106 · 110) ═══
create or replace function inv_layer_fifo_take(p_sku text, p_wh text, p_need numeric,
                                               p_doc_type text, p_doc_number text, p_line_ref text,
                                               p_event_type text, p_occurred_on date, p_reason text,
                                               p_dest_wh text, p_doc_scope text default null,
                                               out o_rows int, out o_short int, out o_layers int, out o_taken numeric)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_need numeric := p_need;
  v_take numeric;
  v_unit numeric;
  v_amt  numeric;
  v_cid  bigint;
  l      record;
begin
  o_rows := 0; o_short := 0; o_layers := 0; o_taken := 0;
  if v_need is null or v_need <= 0 then return; end if;
  for l in
    select x.id, x.unit_cost, x.received_on, x.age_known,
           v.remaining_qty as remaining, v.remaining_value as remaining_value, v.unit_cost as unit_now   -- cogs-2(판정 106 · 111): 남은 수량 · 남은 가치 · 한 병 원가 = inv_layer_value 하나
      from inv_layer x cross join lateral inv_layer_value(x.id) v
      where x.sku = p_sku and x.warehouse = p_wh
        and (p_doc_scope is null or x.doc_number = p_doc_scope)     -- ⭐ IN_TRANSIT 출발만 문서 범위 (헤더)
      order by x.received_on, x.id          -- inv_layer_fifo_idx
  loop
    exit when v_need <= 0;
    if l.remaining <= 0 then continue; end if;
    v_take := least(l.remaining, v_need);
    v_unit := coalesce(l.unit_now, 0);
    v_amt  := case when v_take >= l.remaining then l.remaining_value else round(v_take * v_unit, 6) end;   -- 비우면 남은 가치 전부(끝수가 수량 0 에 남지 않는다 · 판정 106)
    insert into inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on,
                                   qty, unit_cost, amount, reason)
    values (l.id, p_doc_type, p_doc_number, p_line_ref, p_event_type, p_occurred_on,
            v_take, v_unit, v_amt, p_reason);
    o_rows := o_rows + 1;
    if p_dest_wh is not null then
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (p_sku, p_dest_wh, 'transfer', p_doc_number, p_line_ref, l.id,
              l.received_on, l.age_known, v_take, l.unit_cost, 'parent_layer')
      returning id into v_cid;
      o_layers := o_layers + 1;
      perform inv_layer_carry(v_cid);                                -- cogs-2(판정 110): 자식이 선 순간 부모의 얹힌 몫이 따라간다(어느 축이든 · 자식이 팔리기 전에) — 자식 unit_cost 는 부모 goods 그대로(얹힌 몫은 carried 로 · 두 번 세지 않는다)
    end if;
    o_taken := o_taken + v_take;
    v_need := v_need - v_take;
  end loop;
  if v_need > 0 then o_short := 1; end if;
end;
$$;
revoke all on function inv_layer_fifo_take(text, text, numeric, text, text, text, text, date, text, text, text) from public, anon, authenticated;
comment on function inv_layer_fifo_take(text, text, numeric, text, text, text, text, date, text, text, text) is 'FIFO 소진(판매 · 조정 · 조립 · 트랜스퍼 · 분실 · 되돌림 한 손) · ⭐ cogs-2(판정 105 · 106): 소진 단가 · 금액 = 그 레이어의 지금 남은 가치 ÷ 남은 수량(inv_layer_value · 얹힌 몫 포함) · 레이어를 비우면 남은 가치 전부 · 판정 110: 도착 레이어(parent_layer · 부모 goods 단가)가 선 순간 inv_layer_carry · IN_TRANSIT 출발은 문서 범위(p_doc_scope) · 회수(판정 31)';



-- ═══ 7) inv_layer_post_charge — 원본 20260929195458:1108 ~ 1268 바이트 그대로 + 바꾼 줄(cogs-2 표시) · 시그니처가 바뀌어 drop 뒤 create(호출 셋 po_charge_confirm · tf_charge_confirm · tf_arrive · po_receipt_confirm_by ⓕ 는 한 인자 그대로 = 기본값) ═══
drop function if exists public.inv_layer_post_charge(uuid);
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
    left join public.po_line pl on pl.id::text = x.line_ref
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
      left join public.po_line pl on pl.id::text = x.line_ref
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
comment on function public.inv_layer_post_charge(uuid, date, uuid) is 'IMS 비용(po_charge) → inv_layer_cost_add(landed): 배분 줄마다 — 발주면 그 발주의 입고 레이어 · 트랜스퍼면 그 문서의 도착 레이어(origin transfer · TRF-n · 도착 창고 · :settle: 제외 · inv-basis-3 판정 95: :over: 더 온 몫 제외)에 unit_cost × qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등 · ⭐ cogs-2(판정 107 · 108 · 110 · 113 · 114): 얹기 줄 날짜 = 얹히는 순간의 토론토 날짜(p_on 없으면 ims_today · 청구서 날짜는 비용 문서에) · 새 얹기 줄마다 inv_layer_cost_add_settle(남은 몫 · 옮겨 간 몫 carried(어느 축이든) · 팔리거나 빠진 몫 cost_late) · 실시간(p_on null)은 배분 줄에 posted_on · posted_ledger_id 를 남긴다 · 재생성은 p_on = posted_on · p_alloc 으로 배분 줄 하나씩 · 문: 구매 열쇠 · transfer 또는 wms_receiving 열쇠는 발주 배분 없는 비용만(판정 78 도착 창구) · inv-basis-3 판정 94: receiving 또는 wms_receiving_confirm 열쇠는 확정 입고가 있는 발주에만 배분된 비용(입고 확정 순간 po_receipt_confirm_by 가 부른다)';
revoke all on function public.inv_layer_post_charge(uuid, date, uuid) from public, anon;
grant execute on function public.inv_layer_post_charge(uuid, date, uuid) to authenticated;



-- ═══ 8) inv_layer_apply_flush_adds — 첫 차수 20260930140801:44 ~ 209 바이트 그대로 + 바꾼 줄(cogs-2 표시) · 인자가 늘어 drop 뒤 create ═══
drop function if exists public.inv_layer_apply_flush_adds(date, date, jsonb);
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
    select a.id as alloc_id, c.id as charge_id, c.charge_number, c.charge_date, a.posted_on, a.posted_ledger_id
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
                    or (a.po_id is not null and exists (select 1 from po_line pl join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = a.po_id))
                    or (a.transfer_id is not null and exists (select 1 from inv_transfer t join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%' where t.id = a.transfer_id))))   -- inv-basis-3(판정 95 ㉓): 창구와 같은 술어
            )
      order by coalesce(a.posted_on, c.charge_date), a.posted_ledger_id nulls first, c.charge_number, c.id, a.id
  loop
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
    'chg_skip',         coalesce(p_acc -> 'chg_skip', '[]'::jsonb)           || v_chg_skip);
end;
$$;
comment on function public.inv_layer_apply_flush_adds(date, date, bigint, jsonb) is '⭐ 재생성 속 함수(cogs-1 판정 109 · cogs-2 판정 107 · 114 · 115) — inv_layer_apply 가 날짜 경계 · 줄 id 경계마다 부른다: 그날까지의 얹기 셋(불러온 landed · transfer_freight · IMS 비용)을 아직 안 얹은 것만 · 대상 레이어가 선 것만 제자리에 넣고 새로 든 줄마다 inv_layer_cost_add_settle · IMS 비용은 배분 줄 단위 posted_on 자리(같은 날 안은 posted_ledger_id < p_before_id) · posted_on 없는 옛 줄은 charge_date · 누적 반환(jsonb) · definer · 판정 31 회수';
revoke all on function public.inv_layer_apply_flush_adds(date, date, bigint, jsonb) from public, anon, authenticated;   -- ⭐ 판정 31 — 재생성 계열



-- ═══ 9) inv_layer_apply — 첫 차수 20260930140801:216 ~ 728 바이트 그대로 + 바꾼 줄(cogs-2 표시): 줄 id 트리거(판정 114) · 검산 carry 바퀴는 어느 축이든(판정 110) ═══
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
    if v_add_day is not null and r.occurred_on > v_add_day and not v_add_flushed then
      v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, null, v_add_acc);
    end if;
    if r.occurred_on is distinct from v_add_day then
      v_add_day := r.occurred_on; v_add_flushed := false;
      select min(a.posted_ledger_id) into v_next_post_id from po_charge_alloc a join po_charge c on c.id = a.po_charge_id            -- cogs-2(판정 114): 이날 실시간이 얹은 배분 줄의 자리
        where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id is not null
          and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '');
    end if;
    if v_next_post_id is not null and r.id > v_next_post_id then                                           -- cogs-2(판정 114): 실시간이 이 줄 앞에서 얹었다 — 같은 자리에서 쏟는다(같은 날 안의 앞뒤)
      v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, r.id, v_add_acc);
      select min(a.posted_ledger_id) into v_next_post_id from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
        where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id is not null
          and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '');
    end if;
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
                        join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
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
comment on function inv_layer_apply(date) is '⭐ 원가 레이어 전량 재생성(검산 도구 · 사람이 부를 때만 돈다 · cron 없음) — baseline 외 inv_layer · inv_layer_consume · inv_layer_cost_add 를 지우고 원장(inv_ledger · ⚠️ source 필터 없음 — cin7·manual·ims 전부)을 날짜순으로 다시 태운다. Cin7 줄은 inv_cost 로(보조 여섯), ⭐ IMS 줄(source ims)은 창구로 — 입고는 루프 안에서 inv_layer_post_receipt(입고 단위) · 초과분(:over)은 inv_layer_post_receipt_over(차이 단위) · ⭐ [cogs-1 판정 109] 얹기 셋(불러온 landed · transfer_freight · IMS 비용)은 날짜 경계에서 속 함수 inv_layer_apply_flush_adds 가 제자리에 · ⭐ [cogs-2 2026-09-30 · 판정 105 ~ 108 · 110 · 111 · 113 · 114] 소진 단가 = 남은 가치 ÷ 남은 수량(inv_layer_value 하나) · 얹히는 순간 셋으로(settle · cost_late · cost_moved · 자식 carried 어느 축이든) · IMS 비용은 배분 줄 단위로 실시간이 남긴 posted_on · posted_ledger_id 자리(줄 id 트리거 · 같은 날 안의 앞뒤) · 끝 carry 바퀴는 검산(0 이 정상) · ⭐ [ⓒ1] 반품(credit_in · source ims)은 inv_layer_apply_credit_ims → inv_layer_post_credit · Cin7 축 credit_in 은 inv_layer_apply_credit 그대로. 창구가 거부한 것은 건너뛰어 센다 — ims.receipts_skipped · over_skipped · charges_skipped · skip_reasons[]. 권한: 시작에서 receiving·purchasing 쓰기 권한을 본다(psql 은 request.jwt.claims). 반환 45칸 무변 + ims{} 중첩. 원본 20260910141553 → … → 20260929195458 → 20260930140801 → 20260930144905';
revoke all on function public.inv_layer_apply(date) from public, anon, authenticated;   -- ⭐ 판정 31 — 재생성 계열은 사람이 psql(소유자)로만 · 재발행마다 같은 파일에 다시 적는다


-- ═══ 10-a) inv_layer_apply_adjust — 원본 20260920181910:175 ~ 281 바이트 그대로 + layer_avg 한 자리(판정 111) ═══
create or replace function inv_layer_apply_adjust(p_ledger_id bigint, p_until date,
                                                  out o_layers int, out o_rows int, out o_short int,
                                                  out o_unknown int, out o_new_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r        inv_ledger%rowtype;
  v_kind   text;
  v_net    numeric;
  v_unit   numeric;
  v_src    text;
  v_rem    numeric;      -- 남은 레이어 합
  v_remval numeric;      -- 남은 레이어 × 단가 합
  v_wq     numeric;      -- adjust_new: UnitCost 있는 양수 행의 qty 합
  v_wv     numeric;      -- adjust_new: qty × UnitCost 합
  v_rows int; v_short int; v_layers int; v_taken numeric;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_unknown := 0; o_new_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  -- ⭐⭐ IMS 문 (2026-09-20 · po_in 문 20260920142635 의 형제) — 이 줄은 우리 것이다. Cin7 방식으로 만들지 않는다.
  -- 왜: inv_cost 에는 IMS 사건이 없다(Cin7 을 거치지 않았다) ⇒ 아래 unknown/평균 경로로 빠져 unit_cost 0 레이어가 선다(po_in 실측 rcv_unknown 0→2 와 같은 사고).
  --     수량은 맞고 금액만 0 이라 조용하고, 그 행이 키 자리를 차지해 나중에 창구가 생겨도 멱등이 「이미 있다」로 건너뛴다 — 복구도 막힌다.
  -- ⚠️ 지금 IMS 는 po_in 만 낸다. 이 문은 adjust_existing·adjust_new(IMS 재고조정) 을(를) 내기 시작하는 날을 위한 것이다 — 그날 창구를 만들어 여기서 부르면 된다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
  --    세는 것은 본체(inv_layer_apply · ims.skipped_by_event)가 한다 — 본체는 이 함수를 부르기 전에 source 로 가른다. 이 문은 직접 호출(백필·수리 · transfer_in 의 자기 재귀)을 위한 방어다.
  if r.source = 'ims' then
    return;
  end if;
  v_kind := case r.event_type when 'adjust_existing' then 'adj_ex' when 'adjust_new' then 'adj_new' end;
  if v_kind is null then return; end if;

  -- 처리한 키는 건너뛴다 (doc, sku, wh · event_type 별)
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = v_kind and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values (v_kind, r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 키 순액 (source 무관 · line_ref 키 제외 · p_until 안)
  select sum(qty_delta) into v_net
    from inv_ledger
    where event_type = r.event_type and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);

  if r.event_type = 'adjust_existing' then
    if v_net > 0 then
      -- A-1 증가 — 남은 레이어 가중평균 (직접 계산)
      select coalesce(sum(v.remaining_qty), 0), coalesce(sum(v.remaining_value), 0) into v_rem, v_remval   -- cogs-2(판정 111): 남은 가치 ÷ 남은 수량(얹힌 몫 포함) · 식은 inv_layer_value 하나
        from inv_layer x cross join lateral inv_layer_value(x.id) v
        where x.sku = r.sku and x.warehouse = r.warehouse and v.remaining_qty > 0;
      if v_rem > 0 then
        v_unit := round(v_remval / v_rem, 6); v_src := 'layer_avg';
      else
        v_unit := 0; v_src := 'unknown'; o_unknown := o_unknown + 1;   -- A-2 방어 · 표본 대기
      end if;
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'adjust_existing', r.doc_number, r.line_ref, null,
              r.occurred_on, true, v_net, v_unit, v_src);
      o_layers := o_layers + 1;
    elsif v_net < 0 then
      -- A-3 감소 — FIFO 소진 · reason 'adjust_out' · 부족은 short (원가 미상 레이어 없음)
      select * into v_rows, v_short, v_layers, v_taken
        from inv_layer_fifo_take(r.sku, r.warehouse, -v_net,
                                 r.doc_type, r.doc_number, r.line_ref, r.event_type, r.occurred_on, 'adjust_out', null);
      o_rows := o_rows + v_rows; o_short := o_short + v_short;
    end if;
    -- v_net = 0: 아무것도 하지 않는다 (실측 0건 — 헤더)
    return;
  end if;

  -- B. adjust_new
  if v_net is null or v_net <= 0 then
    o_new_net_zero := o_new_net_zero + 1;   -- 상쇄로 소멸
    return;
  end if;
  select coalesce(sum(qty_delta), 0),
         coalesce(sum(qty_delta * (raw -> 'line' ->> 'UnitCost')::numeric), 0)
    into v_wq, v_wv
    from inv_ledger
    where event_type = 'adjust_new' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until)
      and qty_delta > 0
      and (raw -> 'line' ->> 'UnitCost') ~ '^-?[0-9]+(\.[0-9]+)?$';   -- 읽을 수 있는 값만
  if v_wq > 0 then
    v_unit := round(v_wv / v_wq, 6); v_src := 'cin7_unitcost';       -- 0 이면 0 으로 쌓는다 (프로모션 무상 재고 · 정상)
    -- UnitCost 가드 (헤더) — 읽었는데 음수면 거부. 0 은 통과 · 읽을 수 없으면 아래 unknown 경로.
    if v_unit < 0 then
      raise exception 'adjust_new UnitCost (qty-weighted) is negative for % / % / %: % — refusing to build layer (typo in Cin7? inspect raw.line.UnitCost)',
        r.doc_number, r.sku, r.warehouse, v_unit;
    end if;
  else
    v_unit := 0; v_src := 'unknown'; o_unknown := o_unknown + 1;
  end if;
  insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                         received_on, age_known, qty, unit_cost, cost_source)
  values (r.sku, r.warehouse, 'adjust_new', r.doc_number, r.line_ref, null,
          r.occurred_on, true, v_net, v_unit, v_src);
  o_layers := o_layers + 1;
end;
$$;
revoke all on function inv_layer_apply_adjust(bigint, date) from public, anon, authenticated;


-- ═══ 10-b) inv_layer_apply_credit — 원본 20260920181910:378 ~ 478 바이트 그대로 + layer_avg 한 자리(판정 111) · 갈래 ① 은 소진 행 단가를 되돌리므로 판정 106 을 저절로 따른다 ═══
create or replace function inv_layer_apply_credit(p_ledger_id bigint, p_until date,
                                                  out o_layers int, out o_traced int, out o_avg int,
                                                  out o_unknown int, out o_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         inv_ledger%rowtype;
  v_net     numeric;
  v_need    numeric;
  v_so      text;
  v_take    numeric;
  v_rem     numeric;
  v_remval  numeric;
  c         record;
begin
  o_layers := 0; o_traced := 0; o_avg := 0; o_unknown := 0; o_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found or r.event_type <> 'credit_in' then return; end if;

  -- ⭐⭐ IMS 문 (2026-09-20 · po_in 문 20260920142635 의 형제) — 이 줄은 우리 것이다. Cin7 방식으로 만들지 않는다.
  -- 왜: inv_cost 에는 IMS 사건이 없다(Cin7 을 거치지 않았다) ⇒ 아래 unknown/평균 경로로 빠져 unit_cost 0 레이어가 선다(po_in 실측 rcv_unknown 0→2 와 같은 사고).
  --     수량은 맞고 금액만 0 이라 조용하고, 그 행이 키 자리를 차지해 나중에 창구가 생겨도 멱등이 「이미 있다」로 건너뛴다 — 복구도 막힌다.
  -- ⚠️ 지금 IMS 는 po_in 만 낸다. 이 문은 credit_in(IMS 반품) 을(를) 내기 시작하는 날을 위한 것이다 — 그날 창구를 만들어 여기서 부르면 된다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
  --    세는 것은 본체(inv_layer_apply · ims.skipped_by_event)가 한다 — 본체는 이 함수를 부르기 전에 source 로 가른다. 이 문은 직접 호출(백필·수리 · transfer_in 의 자기 재귀)을 위한 방어다.
  if r.source = 'ims' then
    return;
  end if;

  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'credit' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('credit', r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 키 순액 (source 무관 · line_ref 키 제외 · p_until 안)
  select sum(qty_delta) into v_net
    from inv_ledger
    where event_type = 'credit_in' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_net is null or v_net <= 0 then
    o_net_zero := 1;
    return;
  end if;
  v_need := v_net;

  -- 갈래 ① — 원 판매(raw.header.order_number)가 소진한 레이어를 같은 단가로 되돌린다 (소비된 순서 · sku 로 매칭)
  v_so := r.raw -> 'header' ->> 'order_number';
  if v_so is not null then
    for c in
      select s.layer_id, s.unit_cost,
             s.qty - coalesce((select sum(x.qty) from inv_layer x
                                 where x.origin_type = 'creditnote' and x.cost_source = 'return_restore'
                                   and x.parent_layer_id = s.layer_id
                                   and x.doc_number in (select distinct e.doc_number from inv_ledger e
                                                          where e.event_type = 'credit_in'
                                                            and e.raw -> 'header' ->> 'order_number' = v_so)), 0) as avail
        from (select cs.layer_id, cs.unit_cost, sum(cs.qty) as qty, min(l.received_on) as received_on
                from inv_layer_consume cs join inv_layer l on l.id = cs.layer_id
                where cs.doc_type = 'sale' and cs.doc_number = v_so and cs.reason = 'sale' and l.sku = r.sku
                group by cs.layer_id, cs.unit_cost) s
        order by s.received_on, s.layer_id
    loop
      exit when v_need <= 0;
      if c.avail <= 0 then continue; end if;     -- 앞선 크레딧노트가 이미 되돌린 몫
      v_take := least(c.avail, v_need);
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, c.layer_id,
              r.occurred_on, true, v_take, c.unit_cost, 'return_restore');
      o_layers := o_layers + 1;
      o_traced := 1;
      v_need := v_need - v_take;
    end loop;
  end if;
  if v_need <= 0 then return; end if;

  -- 갈래 ② — 남은 레이어 가중평균 (adjust_existing A-1 과 같은 규칙 · 그 시점까지의 레이어만)
  select coalesce(sum(v.remaining_qty), 0), coalesce(sum(v.remaining_value), 0) into v_rem, v_remval       -- cogs-2(판정 111): 남은 가치 ÷ 남은 수량(얹힌 몫 포함) · 식은 inv_layer_value 하나
    from inv_layer x cross join lateral inv_layer_value(x.id) v
    where x.sku = r.sku and x.warehouse = r.warehouse and v.remaining_qty > 0;
  if v_rem > 0 then
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, null,
            r.occurred_on, true, v_need, round(v_remval / v_rem, 6), 'layer_avg');
    o_avg := 1;
  else
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, null,
            r.occurred_on, true, v_need, 0, 'unknown');
    o_avg := 1; o_unknown := 1;       -- ② 를 탔으나 근거가 없었다
  end if;
  o_layers := o_layers + 1;
end;
$$;
revoke all on function inv_layer_apply_credit(bigint, date) from public, anon, authenticated;


-- ═══ 10-c) inv_layer_post_adjust — 원본 20260928142722:384 ~ 418 바이트 그대로 + layer_avg 한 자리(판정 111) · create or replace 로 ═══
create or replace function public.inv_layer_post_adjust(p_doc_number text, p_line_ref text, p_sku text, p_warehouse text, p_qty numeric, p_occurred_on date, p_unit_cost numeric, p_hint jsonb default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'inv_layer_post_adjust@2026-09-28.1';
        v_hint jsonb := case when p_hint is not null and jsonb_typeof(p_hint) = 'object' then p_hint else null end;
        v_unit numeric; v_src text; v_origin text; v_id bigint; v_rem numeric; v_remval numeric; v_rows int; v_short int; v_layers int; v_taken numeric; v_amt numeric;
begin
  if p_qty is null or p_qty = 0 then return jsonb_build_object('qty', p_qty, 'branch', 'none', 'builder', c_version); end if;
  if exists (select 1 from public.inv_layer y where y.origin_type in ('adjust_existing', 'adjust_new') and y.doc_number = p_doc_number and y.line_ref = p_line_ref)
     or exists (select 1 from public.inv_layer_consume c where c.doc_type = 'adjustment' and c.doc_number = p_doc_number and c.line_ref = p_line_ref) then
    raise exception 'Adjustment % line % was already costed — nothing was saved', p_doc_number, p_line_ref;
  end if;
  if p_qty < 0 then                                                                         -- − = FIFO 소진(Cin7 축 A-3 과 같은 reason adjust_out)
    select * into v_rows, v_short, v_layers, v_taken
      from public.inv_layer_fifo_take(p_sku, p_warehouse, -p_qty, 'adjustment', p_doc_number, p_line_ref, 'adjust_existing', p_occurred_on, 'adjust_out', null);
    select coalesce(sum(c.amount), 0) into v_amt from public.inv_layer_consume c where c.doc_type = 'adjustment' and c.doc_number = p_doc_number and c.line_ref = p_line_ref;
    return jsonb_build_object('qty', p_qty, 'branch', 'fifo', 'consume_rows', v_rows, 'layers', v_layers, 'taken', v_taken, 'short', v_short, 'amount', v_amt, 'builder', c_version);
  end if;
  if p_unit_cost is not null then                                                           -- + 단가 있음 = 새 재고(manual)
    v_unit := p_unit_cost; v_src := 'manual'; v_origin := 'adjust_new';
  elsif v_hint is not null and nullif(v_hint->>'unit_cost', '') is not null and (v_hint->>'cost_source') in ('layer_avg', 'unknown') then
    v_unit := (v_hint->>'unit_cost')::numeric; v_src := v_hint->>'cost_source'; v_origin := 'adjust_existing';   -- 재생성 hint = 실시간과 같은 값
  else                                                                                      -- + 단가 없음 = 남은 레이어 가중평균(없으면 unknown 0 · Cin7 A-1 · A-2 와 같다)
    select coalesce(sum(v.remaining_qty), 0), coalesce(sum(v.remaining_value), 0) into v_rem, v_remval     -- cogs-2(판정 111): 남은 가치 ÷ 남은 수량(얹힌 몫 포함) · 식은 inv_layer_value 하나
      from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = p_warehouse and v.remaining_qty > 0;
    if v_rem > 0 then v_unit := round(v_remval / v_rem, 6); v_src := 'layer_avg'; else v_unit := 0; v_src := 'unknown'; end if;
    v_origin := 'adjust_existing';
  end if;
  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (p_sku, p_warehouse, v_origin, p_doc_number, p_line_ref, null, p_occurred_on, true, p_qty, v_unit, v_src) returning id into v_id;
  return jsonb_build_object('qty', p_qty, 'branch', v_src, 'origin_type', v_origin, 'layer_id', v_id, 'unit_cost', v_unit, 'cost_source', v_src, 'amount', round(p_qty * v_unit, 6), 'reproduced', v_hint is not null, 'builder', c_version);
end;
$$;
revoke all on function public.inv_layer_post_adjust(text, text, text, text, numeric, date, numeric, jsonb) from public, anon, authenticated;


-- ═══ 10-d) inv_adjust_eval — 원본 20260928151948:112 ~ 141 바이트 그대로 + layer_avg 한 자리(판정 111) · grant 그대로(authenticated · 화면 미리보기) ═══
create or replace function public.inv_adjust_eval(p_adjust_id uuid)
  returns table(line_id uuid, line_no int, product_id uuid, sku text, bin_id uuid, bin text, mode text, qty_input numeric, reason text, reason_note text, unit_cost numeric,
                seen_ledger numeric, seen_picked numeric, ledger numeric, picked numeric, basis numeric, delta numeric, result numeric,
                cost_branch text, avg_unit_cost numeric, rejects text[])
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with h as (select a.warehouse, a.warehouse_id from public.inv_adjust a where a.id = p_adjust_id),
  x as materialized (                                                                     -- adj-a2(판정 54 B): 줄마다 장부 · P · avg · 칸을 한 번만 — 인라인된 식이 참조 자리마다 다시 돌던 것(≈13회/줄)을 막는다
    select l.*, public.inv_adjust_ledger(h.warehouse, l.bin, l.sku) as ledger, public.inv_adjust_picked(h.warehouse_id, l.bin_id, l.product_id) as picked,
           (select coalesce(sum(v.remaining_value) / nullif(sum(v.remaining_qty), 0), null)                   -- cogs-2(판정 111): 남은 가치 ÷ 남은 수량 · 식은 inv_layer_value 하나
              from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = l.sku and y.warehouse = h.warehouse and v.remaining_qty > 0) as avg_cost,
           (select b.is_active and b.warehouse_id = h.warehouse_id from public.ref_bin b where b.id = l.bin_id) as bin_ok
      from public.inv_adjust_line l, h where l.adjust_id = p_adjust_id
  ),
  y as (select x.*, x.ledger - x.picked as basis, case when x.mode = 'set' then x.qty_input - (x.ledger - x.picked) else x.qty_input end as d from x)
  select y.id, y.line_no, y.product_id, y.sku, y.bin_id, y.bin, y.mode, y.qty_input, y.reason, y.reason_note, y.unit_cost,
         y.seen_ledger, y.seen_picked, y.ledger, y.picked, y.basis, y.d, y.ledger + y.d,
         case when y.d > 0 and y.unit_cost is not null then 'manual' when y.d > 0 and y.avg_cost is not null then 'layer_avg'
              when y.d > 0 then 'unknown' when y.d < 0 then 'fifo' else 'none' end,
         round(y.avg_cost, 6),
         array_remove(array[
           case when y.ledger + y.d < 0 then format('line %s %s %s: result would be %s (below zero)', y.line_no, y.sku, y.bin, y.ledger + y.d) end,
           case when y.ledger <> y.seen_ledger then format('line %s %s %s: ledger changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_ledger, y.ledger) end,
           case when y.picked <> y.seen_picked then format('line %s %s %s: picked-not-shipped changed (you saw %s, it is now %s)', y.line_no, y.sku, y.bin, y.seen_picked, y.picked) end,
           case when not coalesce(y.bin_ok, false) then format('line %s: bin %s is inactive or not in this warehouse', y.line_no, y.bin) end
         ], null)
    from y order by y.line_no;
$$;
revoke all on function public.inv_adjust_eval(uuid) from public, anon;   grant execute on function public.inv_adjust_eval(uuid) to authenticated;


-- ═══ 10-e) inv_layer_post_credit — 원본 20260925012354:195 ~ 326 바이트 그대로 + ② 가중평균 · ③ 최근 원가 두 자리(판정 111) · create or replace 로 ═══
create or replace function public.inv_layer_post_credit(
  p_doc_number   text,        -- 크레딧 번호(CR-…)
  p_line_ref     text,        -- 첫 줄 id
  p_sku          text,        -- 낱개 SKU
  p_warehouse    text,        -- 반품을 받은 창고 이름
  p_qty          numeric,     -- EA
  p_occurred_on  date,
  p_origin_sale  text,        -- 원 판매 오더 번호(SO-…) · null 이면 갈래 ① 없음
  p_hint         jsonb default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_credit@2026-09-30.2';   -- cogs-2(판정 111): ② 가중평균 · ③ 최근 원가가 inv_layer_value 를 부른다(얹힌 몫 포함 · 식 한 곳) · 갈래 ① 은 소진 행 단가(판정 106 · 얹힌 몫 포함)를 그대로 되돌린다
  v_hint       jsonb := case when p_hint is not null and jsonb_typeof(p_hint) = 'object' then p_hint else null end;
  v_need       numeric := p_qty;
  v_take       numeric;
  v_traced_qty numeric := 0;
  v_traced_amt numeric := 0;
  v_traced_n   int := 0;
  v_layers     jsonb := '[]'::jsonb;
  v_unit       numeric;
  v_src        text;
  v_step       int;
  v_source     jsonb;
  v_rem        numeric;
  v_remval     numeric;
  v_layer_id   bigint;
  v_id         bigint;
  c            record;
  x            record;
begin
  if p_qty is null or p_qty <= 0 then
    return jsonb_build_object('sku', p_sku, 'warehouse', p_warehouse, 'qty', p_qty, 'traced_qty', 0, 'traced_layers', 0, 'remainder', null, 'layers', '[]'::jsonb, 'amount', 0, 'builder', c_version);
  end if;
  if exists (select 1 from public.inv_layer y where y.origin_type = 'creditnote' and y.doc_number = p_doc_number and y.sku = p_sku and y.warehouse = p_warehouse) then
    raise exception 'Credit layers for % / % on % already exist — this credit was already costed — nothing was saved', p_sku, p_warehouse, p_doc_number;
  end if;

  -- 갈래 ① — 원 판매(오더 번호)가 소진한 레이어를 같은 단가로 되돌린다(소비된 순서 · 앞선 크레딧이 되돌린 몫은 뺀다 · inv_layer_apply_credit 갈래 ① 과 같은 식)
  if p_origin_sale is not null then
    for c in
      select s.layer_id, s.unit_cost,
             s.qty - coalesce((select sum(x2.qty) from public.inv_layer x2
                                 where x2.origin_type = 'creditnote' and x2.cost_source = 'return_restore' and x2.parent_layer_id = s.layer_id
                                   and x2.doc_number in (select distinct e.doc_number from public.inv_ledger e
                                                           where e.event_type = 'credit_in' and e.raw -> 'header' ->> 'order_number' = p_origin_sale)), 0) as avail
        from (select cs.layer_id, cs.unit_cost, sum(cs.qty) as qty, min(l.received_on) as received_on
                from public.inv_layer_consume cs join public.inv_layer l on l.id = cs.layer_id
               where cs.doc_type = 'sale' and cs.doc_number = p_origin_sale and cs.reason = 'sale' and l.sku = p_sku
               group by cs.layer_id, cs.unit_cost) s
       order by s.received_on, s.layer_id
    loop
      exit when v_need <= 0;
      if c.avail <= 0 then continue; end if;
      v_take := least(c.avail, v_need);
      insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
      values (p_sku, p_warehouse, 'creditnote', p_doc_number, p_line_ref, c.layer_id, p_occurred_on, true, v_take, c.unit_cost, 'return_restore')
      returning id into v_id;
      v_layers := v_layers || jsonb_build_object('layer_id', v_id, 'qty', v_take, 'unit_cost', c.unit_cost, 'cost_source', 'return_restore', 'parent_layer_id', c.layer_id);
      v_traced_qty := v_traced_qty + v_take;  v_traced_amt := v_traced_amt + round(v_take * c.unit_cost, 6);  v_traced_n := v_traced_n + 1;
      v_need := v_need - v_take;
    end loop;
  end if;

  -- 나머지 — hint(재생성) 또는 ② → ③ → ④
  if v_need > 0 then
    if v_hint is not null then
      if nullif(v_hint->>'qty', '')::numeric is distinct from v_need then
        raise exception 'Credit remainder hint (%) does not match the untraced quantity (%) for % / % on % — the ledger raw is wrong, not this function — nothing was saved',
          v_hint->>'qty', v_need, p_sku, p_warehouse, p_doc_number;
      end if;
      v_unit := nullif(v_hint->>'unit_cost', '')::numeric;  v_src := coalesce(v_hint->>'cost_source', 'unknown');
      v_step := nullif(v_hint->>'step', '')::int;  v_source := v_hint->'source';
      if v_unit is null or v_unit < 0 or v_src not in ('layer_avg','layer_recent','layer_recent_other_wh','price_history','unknown') then
        raise exception 'Credit remainder hint for % / % on % has no usable unit_cost/cost_source (%) — the ledger raw is wrong, not this function — nothing was saved', p_sku, p_warehouse, p_doc_number, v_hint::text;
      end if;
    else
      -- ② 남은 레이어 가중평균(그 SKU×창고 · 지금 남은 것)
      select coalesce(sum(v.remaining_qty), 0), coalesce(sum(v.remaining_value), 0) into v_rem, v_remval   -- cogs-2(판정 111): 남은 가치 ÷ 남은 수량(얹힌 몫 포함) · 식은 inv_layer_value 하나
        from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v
       where y.sku = p_sku and y.warehouse = p_warehouse and v.remaining_qty > 0;
      if v_rem > 0 then
        v_unit := round(v_remval / v_rem, 6);  v_src := 'layer_avg';  v_step := 2;  v_source := jsonb_build_object('remaining_qty', v_rem, 'remaining_value', v_remval);
      else
        -- ③ 최근 원가(17-e · inv_layer_post_sale 과 같은 네 단계 · sale_shortfall 제외 · landed 포함)
        select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse,
               (select v.full_unit from public.inv_layer_value(y.id) v) as unit                                      -- cogs-2(판정 111): 처음 한 병(얹힌 몫 포함) · 식은 inv_layer_value 하나
          into x
          from public.inv_layer y where y.sku = p_sku and y.warehouse = p_warehouse and y.origin_type <> 'sale_shortfall'
         order by y.received_on desc, y.id desc limit 1;
        if found then
          v_unit := x.unit;  v_src := 'layer_recent';  v_step := 3;
          v_source := jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
        else
          select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse,
                 (select v.full_unit from public.inv_layer_value(y.id) v) as unit                                    -- cogs-2(판정 111)
            into x
            from public.inv_layer y where y.sku = p_sku and y.warehouse <> p_warehouse and y.origin_type <> 'sale_shortfall'
           order by y.received_on desc, y.id desc limit 1;
          if found then
            v_unit := x.unit;  v_src := 'layer_recent_other_wh';  v_step := 4;
            v_source := jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
          else
            select h.net_unit_cad, h.invoice_number, h.invoice_date, h.supplier_name into x
              from public.po_price_history h where h.sku = p_sku and h.net_unit_cad is not null
             order by h.invoice_date desc, h.invoice_number desc limit 1;
            if found then
              v_unit := x.net_unit_cad;  v_src := 'price_history';  v_step := 5;
              v_source := jsonb_build_object('invoice_number', x.invoice_number, 'invoice_date', x.invoice_date, 'supplier_name', x.supplier_name);
            else
              v_unit := 0;  v_src := 'unknown';  v_step := 6;  v_source := null;      -- ④ 모른다 — 0 · 표시가 남는다
            end if;
          end if;
        end if;
      end if;
    end if;
    insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
    values (p_sku, p_warehouse, 'creditnote', p_doc_number, p_line_ref, null, p_occurred_on, v_src = 'layer_avg', v_need, v_unit, v_src)
    returning id into v_layer_id;
    v_layers := v_layers || jsonb_build_object('layer_id', v_layer_id, 'qty', v_need, 'unit_cost', v_unit, 'cost_source', v_src, 'step', v_step);
  end if;

  return jsonb_build_object(
    'sku', p_sku, 'warehouse', p_warehouse, 'qty', p_qty, 'origin_sale', p_origin_sale,
    'traced_qty', v_traced_qty, 'traced_layers', v_traced_n, 'traced_amount', v_traced_amt,
    'remainder', case when v_need > 0 then jsonb_build_object('qty', v_need, 'unit_cost', v_unit, 'cost_source', v_src, 'step', v_step, 'source', v_source, 'layer_id', v_layer_id, 'amount', round(v_need * v_unit, 6), 'reproduced', v_hint is not null) end,
    'layers', v_layers, 'amount', v_traced_amt + coalesce(round(v_need * v_unit, 6), 0), 'builder', c_version);
end;
$$;
revoke all on function public.inv_layer_post_credit(text, text, text, text, numeric, date, text, jsonb) from public, anon, authenticated;


-- ═══ 10-f) inv_layer_post_sale — 원본 20260924141140:119 ~ 246 바이트 그대로 + 최근 원가 두 자리(판정 111) · create or replace 로 ═══
create or replace function public.inv_layer_post_sale(
  p_doc_number  text,
  p_line_ref    text,
  p_sku         text,
  p_warehouse   text,
  p_qty         numeric,
  p_occurred_on date,
  p_hint        jsonb default null
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_layer_post_sale@2026-09-30.2';   -- cogs-2(판정 111): 최근 원가 ①② 가 inv_layer_value.full_unit 을 부른다(식 한 곳) · FIFO 몫은 fifo_take 가 판정 106 으로
  v_hint      jsonb := case when p_hint is not null and jsonb_typeof(p_hint) = 'object' then p_hint else null end;
  v_hint_qty  numeric;
  v_fifo_need numeric;
  v_rows int;  v_short int;  v_layers int;  v_taken numeric;
  v_fifo_short numeric := 0;
  v_sf_qty    numeric := 0;
  v_unit      numeric;
  v_src       text;
  v_step      int;
  v_source    jsonb;
  v_layer_id  bigint;
  v_sf_amt    numeric := 0;
  v_cogs      numeric;
  x           record;
begin
  if p_qty is null or p_qty <= 0 then
    return jsonb_build_object('sku', p_sku, 'warehouse', p_warehouse, 'qty', p_qty, 'taken_fifo', 0, 'consume_rows', 0, 'fifo_short', 0, 'shortfall', null, 'cogs', 0, 'builder', c_version);
  end if;
  if exists (select 1 from public.inv_layer y
              where y.origin_type = 'sale_shortfall' and y.doc_number = p_doc_number and y.sku = p_sku and y.warehouse = p_warehouse) then
    raise exception 'A shortfall layer for % / % on % already exists — this sale was already costed — nothing was saved', p_sku, p_warehouse, p_doc_number;
  end if;

  v_hint_qty  := case when v_hint is not null then nullif(v_hint->>'qty', '')::numeric else null end;
  v_fifo_need := case when v_hint_qty is not null then p_qty - v_hint_qty else p_qty end;
  if v_fifo_need < 0 then
    raise exception 'Shortfall hint (%) is larger than the sale quantity (%) for % / % on % — the ledger raw is wrong, not this function — nothing was saved',
      v_hint_qty, p_qty, p_sku, p_warehouse, p_doc_number;
  end if;

  -- ① FIFO — 창고 단위 · 있는 레이어는 출처를 안 보고 꺼낸다(17-a)
  select * into v_rows, v_short, v_layers, v_taken
  from public.inv_layer_fifo_take(p_sku, p_warehouse, v_fifo_need, 'sale', p_doc_number, p_line_ref, 'sale_out', p_occurred_on, 'sale', null);
  v_rows := coalesce(v_rows, 0);  v_taken := coalesce(v_taken, 0);

  if v_hint is not null then
    v_sf_qty     := coalesce(v_hint_qty, 0);
    v_fifo_short := v_fifo_need - v_taken;                    -- 재생성이 실시간보다 덜 꺼냈다 — 채우지 않고 보인다(17-f · 재현이 어긋난 신호)
  else
    v_sf_qty     := p_qty - v_taken;
  end if;

  -- ② 부족분 — 최근 원가 레이어(17-d · 17-e)
  if v_sf_qty > 0 then
    if v_hint is not null then
      v_unit   := nullif(v_hint->>'unit_cost', '')::numeric;
      v_src    := coalesce(v_hint->>'cost_source', 'unknown');
      v_step   := nullif(v_hint->>'step', '')::int;
      v_source := v_hint->'source';
      if v_unit is null or v_unit < 0 or v_src not in ('layer_recent','layer_recent_other_wh','price_history','unknown') then
        raise exception 'Shortfall hint for % / % on % has no usable unit_cost/cost_source (%) — the ledger raw is wrong, not this function — nothing was saved', p_sku, p_warehouse, p_doc_number, v_hint::text;
      end if;
    else
      -- ① 같은 SKU×창고 · 마지막으로 세워진 레이어(소진 무관 · received_on desc, id desc) · sale_shortfall 제외
      select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse,
             (select v.full_unit from public.inv_layer_value(y.id) v) as unit                                        -- cogs-2(판정 111): 처음 한 병(얹힌 몫 포함) · 식은 inv_layer_value 하나
        into x
      from public.inv_layer y
      where y.sku = p_sku and y.warehouse = p_warehouse and y.origin_type <> 'sale_shortfall'
      order by y.received_on desc, y.id desc limit 1;
      if found then
        v_unit := x.unit;  v_src := 'layer_recent';  v_step := 1;
        v_source := jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
      else
        -- ② 다른 창고의 마지막 레이어
        select y.id, y.doc_number, y.line_ref, y.received_on, y.warehouse,
               (select v.full_unit from public.inv_layer_value(y.id) v) as unit                                      -- cogs-2(판정 111)
          into x
        from public.inv_layer y
        where y.sku = p_sku and y.warehouse <> p_warehouse and y.origin_type <> 'sale_shortfall'
        order by y.received_on desc, y.id desc limit 1;
        if found then
          v_unit := x.unit;  v_src := 'layer_recent_other_wh';  v_step := 2;
          v_source := jsonb_build_object('layer_id', x.id, 'doc_number', x.doc_number, 'line_ref', x.line_ref, 'received_on', x.received_on, 'warehouse', x.warehouse);
        else
          -- ③ 확정 인보이스 가격(po_price_history · CAD · 환율 없으면 null 이라 건너뛴다)
          select h.net_unit_cad, h.invoice_number, h.invoice_date, h.supplier_name into x
          from public.po_price_history h
          where h.sku = p_sku and h.net_unit_cad is not null
          order by h.invoice_date desc, h.invoice_number desc limit 1;
          if found then
            v_unit := x.net_unit_cad;  v_src := 'price_history';  v_step := 3;
            v_source := jsonb_build_object('invoice_number', x.invoice_number, 'invoice_date', x.invoice_date, 'supplier_name', x.supplier_name);
          else
            -- ④ 모른다 — 0 · 표시가 남는다(17-e ④ · 카운터는 반환 shortfall.step 4 로 센다)
            v_unit := 0;  v_src := 'unknown';  v_step := 4;  v_source := null;
          end if;
        end if;
      end if;
    end if;

    insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
    values (p_sku, p_warehouse, 'sale_shortfall', p_doc_number, p_line_ref, null, p_occurred_on, false, v_sf_qty, v_unit, v_src)
    returning id into v_layer_id;
    insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason)
    values (v_layer_id, 'sale', p_doc_number, p_line_ref, 'sale_out', p_occurred_on, v_sf_qty, v_unit, round(v_sf_qty * v_unit, 6), 'sale');
    v_sf_amt := round(v_sf_qty * v_unit, 6);
    v_rows := v_rows + 1;
  end if;

  select coalesce(sum(c.amount), 0) into v_cogs
  from public.inv_layer_consume c join public.inv_layer l on l.id = c.layer_id
  where c.doc_type = 'sale' and c.doc_number = p_doc_number and c.line_ref = p_line_ref and c.event_type = 'sale_out' and c.reason = 'sale'
    and l.sku = p_sku and l.warehouse = p_warehouse;

  return jsonb_build_object(
    'sku', p_sku, 'warehouse', p_warehouse, 'qty', p_qty,
    'taken_fifo', v_taken, 'consume_rows', v_rows, 'fifo_short', v_fifo_short,
    'shortfall', case when v_sf_qty > 0 then jsonb_build_object('qty', v_sf_qty, 'unit_cost', v_unit, 'cost_source', v_src, 'step', v_step, 'source', v_source,
                                                                'layer_id', v_layer_id, 'amount', v_sf_amt, 'reproduced', v_hint is not null)
                 else null end,
    'cogs', v_cogs, 'builder', c_version);
end;
$$;
revoke all on function public.inv_layer_post_sale(text, text, text, text, numeric, date, jsonb) from public, anon, authenticated;


-- ═══ 10-g) so_credit_cancel — 원본 20260925012354:1194 ~ 1251 바이트 그대로 + reversal 소진 한 자리(판정 106) · create or replace 로 ═══
create or replace function public.so_credit_cancel(p_credit_id uuid, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_cr      public.so_credit%rowtype;
  v_note    text;
  v_n       int;
  v_alloc   int;
  v_sold    text;
  v_rows    int := 0;
  v_layers  int := 0;
  v_qty     numeric := 0;
  v_today   date := public.ims_today();
  g         record;
  y         record;
  v_val     numeric;  v_unit numeric;                              -- cogs-2(판정 106): 되돌리는 소진 = 그 레이어의 남은 가치 전부(inv_layer_value · 얹힌 몫 포함)
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄
  v_staff := public.so_current_staff();
  v_note := nullif(trim(p_note), '');
  if v_note is null then raise exception 'A cancel needs a reason (p_note) — nothing was saved'; end if;
  select * into v_cr from public.so_credit c where c.id = p_credit_id for update;
  if not found then raise exception 'Credit note not found — nothing was saved'; end if;
  if v_cr.status <> 'issued' then raise exception 'Credit note % is already % — nothing was saved', v_cr.credit_number, v_cr.status; end if;
  perform 1 from public.customer c where c.id = v_cr.customer_id for update;
  select count(*) into v_alloc from public.so_credit_alloc a where a.credit_id = v_cr.id and a.voided_at is null;
  if v_alloc > 0 then raise exception 'Credit note % has been applied (% allocation(s)) — detach it first — nothing was saved', v_cr.credit_number, v_alloc; end if;

  -- 원장: 돌아온 레이어(origin creditnote · doc = CR)가 하나라도 소진됐으면 거부
  select string_agg(l.sku || ' @' || l.warehouse, ', ') into v_sold
    from public.inv_layer l where l.origin_type = 'creditnote' and l.doc_number = v_cr.credit_number
     and exists (select 1 from public.inv_layer_consume k where k.layer_id = l.id);
  if v_sold is not null then
    raise exception 'Credit note % — the returned stock was already sold on (%) — it cannot be cancelled; use a stock adjustment and a new credit note instead — nothing was saved', v_cr.credit_number, v_sold;
  end if;

  -- 반대 사건 — 행마다 qty_delta 음수 · line_ref :reversal(유니크 키 · 재생성은 키 순액 ≤ 0 → net_zero) · 레이어는 reason reversal 로 전량 소진(실시간도 남은 것 0)
  for g in select * from public.inv_ledger l where l.doc_type = 'creditnote' and l.doc_number = v_cr.credit_number and l.source = 'ims' and l.event_type = 'credit_in' and l.qty_delta > 0 order by l.id loop
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_today, 2, g.sku, g.warehouse, g.bin, -g.qty_delta, 'credit_in', 'creditnote', g.doc_number, g.doc_task_id, g.line_ref || ':reversal', null, 'ims',
            jsonb_build_object('kind', 'credit_in_reversal', 'poster', 'so_credit_cancel@2026-09-25.1', 'header', g.raw -> 'header', 'reversal_of', g.id, 'credit_id', v_cr.id, 'cancel_note', v_note, 'cancelled_by', v_staff, 'cancelled_on', v_today));
    v_rows := v_rows + 1;  v_qty := v_qty + g.qty_delta;
  end loop;
  for y in select * from public.inv_layer l where l.origin_type = 'creditnote' and l.doc_number = v_cr.credit_number order by l.id loop
    select v.remaining_value, coalesce(v.unit_cost, 0) into v_val, v_unit from public.inv_layer_value(y.id) v;   -- cogs-2(판정 106): 소진 0 인 레이어라 남은 가치 = 처음 원가 + 얹힌 것 전부
    insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason)
    values (y.id, 'creditnote', v_cr.credit_number, y.line_ref || ':reversal', 'credit_in', v_today, y.qty, v_unit, v_val, 'reversal');
    v_layers := v_layers + 1;
  end loop;

  update public.so_credit set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff, cancel_note = v_note, updated_by = v_staff where id = v_cr.id and status = 'issued';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Credit note % was not cancelled — it may have been changed by someone else just now — nothing was saved', v_cr.credit_number; end if;
  return jsonb_build_object('credit_id', v_cr.id, 'credit_number', v_cr.credit_number, 'status', 'cancelled', 'note', v_note, 'cancelled_by', v_staff,
                            'ledger_rows_reversed', v_rows, 'qty_ea_reversed', v_qty, 'layers_reversed', v_layers);
end;
$$;
revoke all on function public.so_credit_cancel(uuid, text) from public, anon;
grant execute on function public.so_credit_cancel(uuid, text) to authenticated;
