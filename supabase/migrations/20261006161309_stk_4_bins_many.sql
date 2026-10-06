-- ─────────────────────────────────────────────────────────────
-- 가용 목록의 bin 칸 stk_bins_many · 움직임의 크레딧 링크 (Asung-IMS · stk-4 · 2026-10-06)
--   정본(뒤에 적는다): so-module §46 — 판정 273(목록의 bin 칸 · 새 창구 stk_bins_many · 한 쪽 최대 500 제품 · 화면은 쪽마다 한 번 · stk_availability 무접촉) · 274(so-credits.html 은 ?cr=<번호> 로 열린다 — imsParam("cr") → gotoCr · 판정 269 의 「?id= 가 생기면」을 이것으로 바꾼다)
--                      · 275(배열 — null · 중복 제거 → 500 초과 거부 · 0 이면 빈 결과(문은 먼저) · 모르는 id 는 줄 없음) · 276(반환은 줄 그대로 product_id · bin_id · bin · bin_zone · bin_is_active · qty · 정렬 product_id, qty desc, bin, bin_id) · stk-4 이견 1 ~ 9(전부 채택)
--   Caleb 2026-10-06 「메인 stock availability에 bin location도 보이게 해줄 수 있어?」 · bin 으로 검색은 이번에 넣지 않는다
--   ① stk_bins_many(p_product_ids uuid[], p_warehouse_id uuid) — 문 · 보안 = stk_bins(definer · 로그인 + 활성 직원 · 활성 창고만) · 배열을 sku 배열로 바꿔 뷰의 그룹 열(sku · 창고 이름)로 거른다(인덱스 밀어넣기 · 실측 100 sku 56 ms · 500 sku 72 ms) · 0 줄은 뺀다 · bin 없는 창고 단위 줄은 bin = '' 한 줄 · 비활성 bin 도 보이되 bin_is_active 로(실물 비활성 bin 재고 0)
--   ② stk_movements 재발행 — 마지막 정의 20261006152050(DB prosrc md5 5a47eb05… 와 일치) · 바뀐 것 = creditnote 의 doc_screen 한 줄 더함 · doc_href 의 cr= 갈래 한 줄 · 주석 · comment(diff 는 보고에) · 시그니처 · grant 그대로
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · stk_availability · stk_bins · inv_available_base 무접촉 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
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

-- ═══ 1) stk_bins_many — 한 쪽의 bin 을 한 번에(판정 273 · 275 · 276) ═══
create function public.stk_bins_many(p_product_ids uuid[], p_warehouse_id uuid)
  returns table (product_id uuid, bin_id uuid, bin text, bin_zone text, bin_is_active boolean, qty numeric)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_wh    text;
  v_pids  uuid[];
  v_skus  text[];
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was read'; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = p_warehouse_id and w.is_active;
  if v_wh is null then raise exception 'Warehouse not found or inactive — pick an active branch'; end if;
  -- 판정 275 — null · 중복 제거 → 500 초과 거부 · 0 이면 빈 결과 · 모르는 id 는 줄 없음
  select coalesce(array_agg(distinct u.pid), '{}'::uuid[]) into v_pids from unnest(coalesce(p_product_ids, '{}'::uuid[])) as u(pid) where u.pid is not null;
  if cardinality(v_pids) > 500 then raise exception 'Too many products (% · the limit is 500) — ask for one page at a time', cardinality(v_pids); end if;
  if cardinality(v_pids) = 0 then return; end if;
  -- 뷰는 sku · warehouse(이름)로 걸러야 inv_ledger (sku, warehouse) 인덱스로 내려간다(stk_bins 와 같은 식 · stk-1 교훈)
  select array_agg(p.sku) into v_skus from public.product p where p.id = any(v_pids);
  if v_skus is null then return; end if;
  return query
  select b.product_id, b.bin_id, b.bin, b.bin_zone, b.bin_is_active, b.qty
  from public.ims_inv_balance b
  where b.warehouse = v_wh and b.sku = any(v_skus) and b.qty <> 0                       -- product_id = any(...) 를 겹치면 계획이 뷰 전체를 센다(stk-4 1회차 100 → 310 ms · 500 → 1,335 ms) · sku 는 유니크라 sku 조건만으로 같은 집합
  order by b.product_id, b.qty desc, b.bin, b.bin_id;
end;
$$;
revoke all on function public.stk_bins_many(uuid[], uuid) from public, anon;
grant execute on function public.stk_bins_many(uuid[], uuid) to authenticated;
comment on function public.stk_bins_many(uuid[], uuid) is
  '⭐ 가용 목록 한 쪽의 bin 을 한 번에(stk-4 · 판정 273 · 275 · 276 · 2026-10-06) — p_product_ids(null · 중복 제거 → 500 초과 거부 · 0 이면 빈 결과 · 모르는 id 는 줄 없음) × 활성 창고 → (product_id · bin_id · bin · bin_zone · bin_is_active · qty) · 식은 stk_bins 와 같다(ims_inv_balance 를 sku · 창고 이름으로 걸러 인덱스로 · qty ≠ 0 만 · bin 없는 창고 단위 줄은 bin = '''' · bin_id null · 비활성 bin 도 보이되 bin_is_active) · 정렬 product_id, qty desc, bin, bin_id · 화면은 쪽마다 한 번(사진과 같은 모양 · 수량 많은 bin 3 + N · 결과에 없는 제품 = 재고 0 · bin '''' = (no bin)) · 문 = 로그인 + 활성 직원 · definer · 원가 없음(판정 262) · 실측 100 sku 56 ms · 500 sku 72 ms';
comment on function public.stk_bins(uuid, uuid) is
  '⭐ 제품 하나 × 창고 하나의 bin 별 잔고(stk-1 · 판정 257 · 2026-10-06) — ims_inv_balance 를 sku · 창고 이름으로 걸러(인덱스 밀어넣기 · 25 ms) 그대로(bin_id · bin · bin_zone · bin_is_active · qty · last_event_on) · bin 없는 줄(창고 단위 재고)은 bin = '''' · bin_id null 한 줄 · 0 줄은 뺀다 · 정렬 bin 이름 · 합 = stk_availability.on_hand · 문 = 로그인 + 활성 직원(판정 268) · definer · 원가 없음(판정 262) · ⭐ 목록 한 쪽은 stk_bins_many(stk-4 · 같은 식 · 제품 여럿 한 번에)';

-- ═══ 2) stk_movements 재발행 — 마지막 정의 20261006152050 · creditnote 링크(판정 274) ═══
create or replace function public.stk_movements(
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
               when 'creditnote' then 'so-credits.html'                                 -- stk-4 판정 274: so-credits.html 은 ?cr=<번호> 로 열린다(imsParam("cr") → gotoCr)
             end
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
           a.doc_screen || '?' || case when a.doc_screen = 'so.html' then 'so=' || a.doc_number when a.doc_screen = 'so-credits.html' then 'cr=' || a.doc_number else 'id=' || a.doc_id::text end   -- stk-4 판정 274
         end
  from acc a
  order by a.occurred_on, a.ord, a.id;
end;
$$;
revoke all on function public.stk_movements(uuid, uuid, date, date, int) from public, anon;
grant execute on function public.stk_movements(uuid, uuid, date, date, int) to authenticated;
comment on function public.stk_movements(uuid, uuid, date, date, int) is
  '⭐ 재고 움직임(stk-2 · 판정 257 · 263 · 269 ~ 272 · 2026-10-06 · stk-4 재발행 판정 274 — 크레딧 링크 so-credits.html?cr=<번호> · 원본 20261006152050) — 한 제품 × 한 활성 브랜치의 원장 사건을 시간 순으로(occurred_on · seq_hint 1 유입 2 유출 · id) · 첫 줄 opening = 기초(baseline_snapshot_key 스냅샷의 sku × 창고 합 · 없으면 0 · 날짜 = 스냅샷 토론토 날짜) · p_from 이 있으면 opening 날짜 = greatest(p_from − 1, 기초 날짜) · 값 = 기초 + Σ(그 전) · p_to 포함 · qty_in · qty_out 은 qty_delta 부호(상쇄 줄은 event_type 과 반대) · balance_after 는 모든 줄 · is_day_end = 그 날짜의 마지막 줄(판정 263 — 화면은 그 줄에만 잔고를 보인다 · 하루 안 실제 순서는 알 수 없다) · is_reversal = line_ref :reversal · :voided · :binfix 또는 manual_reversal(합치지 않는다 · 판정 270) · line_ref 추적용 · 문서 링크(판정 269 · source ims 만 · 번호 유니크로 찾음): sale so.html?so=<번호> · transfer TRF transfers.html?id= · MV stock-moves.html?id= · purchase receiving.html?id= · adjustment stock-adjustments.html?id= · creditnote so-credits.html?cr=<번호>(stk-4 · 판정 274 · 종전 doc_id 만) · cin7 · manual 은 null · 쪽 없음 · 상한 2,000(p_max · 넘으면 Narrow the date range · 2,000 초과는 2,000) · IN_TRANSIT 의 중간 두 줄은 보이지 않는다 — 출발 브랜치의 나감 · 도착 브랜치의 들어옴만(판정 272 · 운송 중 수량은 stk_availability.in_transit · 중간 줄 따로 보기는 미룬 112) · 문 = 로그인 + 활성 직원 · 활성 창고 · 있는 제품 · definer · 원가(amount) 없음(판정 262)';

-- ═══ 3) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_src text;
begin
  if to_regprocedure('public.stk_bins_many(uuid[], uuid)') is null or to_regprocedure('public.stk_movements(uuid, uuid, date, date, int)') is null then v_bad := v_bad || ' functions'; end if;
  if not (select bool_and(p.prosecdef and p.provolatile = 's' and has_function_privilege('authenticated', p.oid, 'execute') and not has_function_privilege('anon', p.oid, 'execute') and pg_get_function_result(p.oid) !~* '(amount|cost|price)')
            from pg_proc p where p.oid in (to_regprocedure('public.stk_bins_many(uuid[], uuid)'), to_regprocedure('public.stk_movements(uuid, uuid, date, date, int)'))) then v_bad := v_bad || ' definer/grants/cost'; end if;
  select p.prosrc into v_src from pg_proc p where p.oid = to_regprocedure('public.stk_movements(uuid, uuid, date, date, int)');
  if v_src not like '%when ''creditnote'' then ''so-credits.html''%' or v_src not like '%''cr='' || a.doc_number%' then v_bad := v_bad || ' stk_movements(credit link)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM273', message = format('STOP - stk-4 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
