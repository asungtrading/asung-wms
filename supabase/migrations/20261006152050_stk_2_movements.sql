-- ─────────────────────────────────────────────────────────────
-- 재고 움직임 읽기 창구 stk_movements — 한 제품 × 한 브랜치의 사건 · 누적 잔고 · 문서 링크 (Asung-IMS · stk-2 · 2026-10-06)
--   정본(뒤에 적는다): so-module §46 — 판정 257(화면 하나 · 상세 = 사진 · Bins · Movements) · 258 · 268(문 = 로그인 + 활성 직원) · 259(stk_) · 262(원가 없음) · 263(누적 잔고는 날짜별 마지막 줄에만 — 창구는 값과 is_day_end 를 주고 화면이 가린다)
--                      · 269 doc_href 는 창구가 만든다 · 크레딧은 doc_id 만(so-credits.html ?id= 는 stk-3 에서 · 그 뒤 창구 한 줄) · 270 상쇄 줄은 합치지 않는다 · is_reversal · line_ref 반환 · 271 쪽 없음 · 상한 2,000 · 넘으면 「Narrow the date range」 거부(p_max · 시험용 · 2,000 초과는 2,000 으로 자른다) · 272 움직임 이력에는 가상 창고 IN_TRANSIT 의 중간 두 줄을 보이지 않는다(출발 브랜치의 나감 · 도착 브랜치의 들어옴은 보인다) · 운송 중 수량은 stk_availability 의 in_transit 칸(도착 브랜치)이 보인다 · 중간 줄을 따로 보는 일은 미룬 112
--                      · stk-2 이견 1 ~ 10(전부 채택) · stk-0 실측(인덱스 (sku, warehouse, occurred_on) · seq_hint 1 유입 · 2 유출 · 상쇄 접미어 :reversal · :voided · :binfix · manual_reversal)
--   반환(시간 오름차순 · 첫 줄 = opening): occurred_on · seq_hint · event_type · doc_type · doc_number · source · bin · qty_in · qty_out · balance_after · is_day_end · is_reversal · line_ref · doc_id · doc_screen · doc_href
--     opening 줄 = 기초(inv_config.baseline_snapshot_key 스냅샷의 그 sku × 창고 합 · 없으면 0 · 날짜 = 스냅샷 날짜(토론토)) · p_from 이 있으면 날짜 = greatest(p_from − 1, 기초 날짜) · 값 = 기초 + Σ(occurred_on < p_from)
--     qty_in · qty_out 은 qty_delta 부호로(상쇄 줄은 event_type 과 부호가 반대다) · balance_after = 모든 줄에 값 · is_day_end = 그 날짜의 마지막 줄 · 정렬 (occurred_on, seq_hint, id)
--     doc_id · doc_screen · doc_href 는 source = 'ims' 일 때만 번호로 IMS 문서를 찾아 — sale → so.html?so=<번호> · transfer → TRF 는 transfers.html?id= · MV 는 stock-moves.html?id= · purchase → receiving.html?id= · adjustment → stock-adjustments.html?id= · creditnote → doc_id 만(판정 269) · cin7 · manual 은 셋 다 null
--   문 · 보안 = stk_bins 모양(definer · 로그인 + 활성 직원 · authenticated execute) · 창고는 활성만(IN_TRANSIT · Production Facility 거부) · 제품이 없으면 거부 · 사건 0 이면 opening 한 줄 · 거르기는 그룹 열(sku · warehouse 이름)로 인덱스를 탄다
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 표 · 행 · 정책 · 다른 함수 무접촉 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
-- ─────────────────────────────────────────────────────────────
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

-- ═══ 1) stk_movements ═══
create function public.stk_movements(
  p_product_id   uuid,
  p_warehouse_id uuid,
  p_from         date default null,
  p_to           date default null,
  p_max          int  default 2000
) returns table (
  occurred_on date, seq_hint smallint, event_type text, doc_type text, doc_number text, source text, bin text,
  qty_in numeric, qty_out numeric, balance_after numeric, is_day_end boolean, is_reversal boolean, line_ref text,
  doc_id uuid, doc_screen text, doc_href text
)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_sku       text;
  v_wh        text;
  v_key       text;
  v_base_on   date;
  v_base_qty  numeric;
  v_open_on   date;
  v_open_qty  numeric;
  v_max       int := least(greatest(coalesce(p_max, 2000), 1), 2000);
  v_n         int;
begin
  -- 문(판정 268) — 로그인 + 활성 직원 · 열쇠는 보지 않는다(판정 258)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if v_wh is null then raise exception 'Warehouse not found or inactive — pick an active branch'; end if;
  select p.sku into v_sku from public.product p where p.id = p_product_id;
  if v_sku is null then raise exception 'Product not found — nothing was read'; end if;
  if p_from is not null and p_to is not null and p_from > p_to then raise exception 'The date range is reversed (from % · to %) — nothing was read', p_from, p_to; end if;

  -- 기초 — inv_balance 와 같은 자리에서 읽는다(baseline_snapshot_key · 그 sku × 창고의 bin 합 · 날짜는 스냅샷 시각의 토론토 날짜)
  select k.value into v_key from public.inv_config k where k.key = 'baseline_snapshot_key';
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_base_on from public.inv_snapshot s where s.snapshot_key = v_key;
  select coalesce(sum(s.qty), 0) into v_base_qty from public.inv_snapshot s where s.snapshot_key = v_key and s.sku = v_sku and s.warehouse = v_wh;
  if p_from is null then
    v_open_on := v_base_on; v_open_qty := v_base_qty;
  else
    v_open_on := greatest(p_from - 1, v_base_on);
    select v_base_qty + coalesce(sum(l.qty_delta), 0) into v_open_qty from public.inv_ledger l where l.sku = v_sku and l.warehouse = v_wh and l.occurred_on < p_from;
  end if;

  -- 상한(판정 271) — 쪽 없이 전부 · 넘으면 날짜 범위를 좁히라고 거부
  select count(*) into v_n from public.inv_ledger l where l.sku = v_sku and l.warehouse = v_wh and (p_from is null or l.occurred_on >= p_from) and (p_to is null or l.occurred_on <= p_to);
  if v_n > v_max then raise exception 'Too many movements (% · the limit is %) — narrow the date range', v_n, v_max; end if;

  return query
  with ev as (
    select l.id, l.occurred_on, l.seq_hint, l.event_type, l.doc_type, l.doc_number, l.source, l.bin, l.qty_delta, l.line_ref
    from public.inv_ledger l
    where l.sku = v_sku and l.warehouse = v_wh and (p_from is null or l.occurred_on >= p_from) and (p_to is null or l.occurred_on <= p_to)
  ),
  rows_all as (
    select v_open_on as occurred_on, 0::int as ord, 0::bigint as id, null::smallint as seq_hint, 'opening'::text as event_type, null::text as doc_type, null::text as doc_number, null::text as source, null::text as bin,
           v_open_qty as delta, null::numeric as qty_in, null::numeric as qty_out, false as is_reversal, null::text as line_ref
    union all
    select e.occurred_on, coalesce(e.seq_hint, 9)::int, e.id, e.seq_hint, e.event_type, e.doc_type, e.doc_number, e.source, e.bin,
           e.qty_delta, greatest(e.qty_delta, 0), greatest(-e.qty_delta, 0),
           (e.event_type = 'manual_reversal' or e.line_ref like '%:reversal%' or e.line_ref like '%:voided%' or e.line_ref like '%:binfix%'), e.line_ref
    from ev e
  ),
  linked as (                                                                            -- 판정 269 — source = 'ims' 일 때만 번호로 IMS 문서를 찾는다 · 번호 열은 전부 유니크
    select r.*,
           case when r.source = 'ims' then
             case r.doc_type
               when 'sale'       then (select s.id from public.so s where s.so_number = r.doc_number)
               when 'transfer'   then coalesce((select t.id from public.inv_transfer t where t.transfer_number = r.doc_number), (select m.id from public.inv_move m where m.move_number = r.doc_number))
               when 'purchase'   then (select rc.id from public.po_receipt rc where rc.receipt_number = r.doc_number)
               when 'adjustment' then (select a.id from public.inv_adjust a where a.adjust_number = r.doc_number)
               when 'creditnote' then (select c.id from public.so_credit c where c.credit_number = r.doc_number)
             end
           end as doc_id,
           case when r.source = 'ims' then
             case r.doc_type
               when 'sale'       then 'so.html'
               when 'transfer'   then case when exists (select 1 from public.inv_transfer t where t.transfer_number = r.doc_number) then 'transfers.html'
                                           when exists (select 1 from public.inv_move m where m.move_number = r.doc_number) then 'stock-moves.html' end
               when 'purchase'   then 'receiving.html'
               when 'adjustment' then 'stock-adjustments.html'
             end                                                                         -- creditnote: 화면이 ?id= 를 받을 때까지 null(판정 269)
           end as doc_screen
    from rows_all r
  ),
  acc as (
    select k.*,
           sum(k.delta) over (order by k.occurred_on, k.ord, k.id rows unbounded preceding) as balance_after,
           row_number() over (partition by k.occurred_on order by k.ord desc, k.id desc) = 1 as is_day_end
    from linked k
  )
  select a.occurred_on, a.seq_hint, a.event_type, a.doc_type, a.doc_number, a.source, a.bin,
         a.qty_in, a.qty_out, a.balance_after, a.is_day_end, a.is_reversal, a.line_ref,
         a.doc_id,
         case when a.doc_id is not null then a.doc_screen end,
         case when a.doc_id is not null and a.doc_screen is not null then
           a.doc_screen || '?' || case when a.doc_screen = 'so.html' then 'so=' || a.doc_number else 'id=' || a.doc_id::text end
         end
  from acc a
  order by a.occurred_on, a.ord, a.id;
end;
$$;
revoke all on function public.stk_movements(uuid, uuid, date, date, int) from public, anon;
grant execute on function public.stk_movements(uuid, uuid, date, date, int) to authenticated;
comment on function public.stk_movements(uuid, uuid, date, date, int) is
  '⭐ 재고 움직임(stk-2 · 판정 257 · 263 · 269 ~ 272 · 2026-10-06) — 한 제품 × 한 활성 브랜치의 원장 사건을 시간 순으로(occurred_on · seq_hint 1 유입 2 유출 · id) · 첫 줄 opening = 기초(baseline_snapshot_key 스냅샷의 sku × 창고 합 · 없으면 0 · 날짜 = 스냅샷 토론토 날짜) · p_from 이 있으면 opening 날짜 = greatest(p_from − 1, 기초 날짜) · 값 = 기초 + Σ(그 전) · p_to 포함 · qty_in · qty_out 은 qty_delta 부호(상쇄 줄은 event_type 과 반대) · balance_after 는 모든 줄 · is_day_end = 그 날짜의 마지막 줄(판정 263 — 화면은 그 줄에만 잔고를 보인다 · 하루 안 실제 순서는 알 수 없다) · is_reversal = line_ref :reversal · :voided · :binfix 또는 manual_reversal(합치지 않는다 · 판정 270) · line_ref 추적용 · 문서 링크(판정 269 · source ims 만 · 번호 유니크로 찾음): sale so.html?so=<번호> · transfer TRF transfers.html?id= · MV stock-moves.html?id= · purchase receiving.html?id= · adjustment stock-adjustments.html?id= · creditnote doc_id 만(so-credits.html ?id= 는 stk-3) · cin7 · manual 은 null · 쪽 없음 · 상한 2,000(p_max · 넘으면 Narrow the date range · 2,000 초과는 2,000) · IN_TRANSIT 의 중간 두 줄은 보이지 않는다 — 출발 브랜치의 나감 · 도착 브랜치의 들어옴만(판정 272 · 운송 중 수량은 stk_availability.in_transit · 중간 줄 따로 보기는 미룬 112) · 문 = 로그인 + 활성 직원 · 활성 창고 · 있는 제품 · definer · 원가(amount) 없음(판정 262)';

-- ═══ 2) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.stk_movements(uuid, uuid, date, date, int)') is null then v_bad := v_bad || ' function'; end if;
  if not (select p.prosecdef and p.provolatile = 's' from pg_proc p where p.oid = to_regprocedure('public.stk_movements(uuid, uuid, date, date, int)')) then v_bad := v_bad || ' definer/stable'; end if;
  if not has_function_privilege('authenticated', to_regprocedure('public.stk_movements(uuid, uuid, date, date, int)'), 'execute') or has_function_privilege('anon', to_regprocedure('public.stk_movements(uuid, uuid, date, date, int)'), 'execute') then v_bad := v_bad || ' grants'; end if;
  if pg_get_function_result(to_regprocedure('public.stk_movements(uuid, uuid, date, date, int)')) ~* '(amount|cost|price)' then v_bad := v_bad || ' cost_column'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM269', message = format('STOP - stk-2 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
