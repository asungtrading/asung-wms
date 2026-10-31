-- tf-pallet-1 (2026-10-31 · 판정 897 · 898) — 트랜스퍼를 팔렛 단위로 받기 · 운송 정보 칸 셋
--
-- 판정 897(Caleb): 트랜스퍼는 한 장 그대로 · Fulfillment 가 만든 팔렛(wms_pallets · transfer_id)이 그 안에 기록 · 받는 쪽이 팔렛 단위로 받는다(팔렛별 자동 분할 기각).
-- 판정 898(Caleb): 트랜스퍼에 운송사 · 운송장 번호 · ETA 칸 셋(토론토 → 에드먼턴은 APPS 로 보낸다) · 쓰기 창구 하나 · confirmed ~ receiving 사이 언제든.
-- 정한 것(Caleb 2026-10-31 · tf-pallet-0 조사 이견 그대로 + tf-pallet-1 이견 1 ~ 7):
--   1 출발 뒤 얼림 — 트랜스퍼 팔렛 · 팔렛 줄은 트랜스퍼가 떠난 뒤(in_transit · receiving · received)에는 insert · update · delete 거부 · SO 팔렛은 얼리지 않는다(Freightcom 치수로 Finalized 뒤에도 더한다)
--   2 박스는 맨 위 팔렛으로 접는다 — 받기의 「팔렛」 = 맨 위 유닛 + 그 아래 박스 전부(wms_pallet_tree)
--   3 스캔은 id 로 — 바코드 값 PLT-<wms_pallets.id> · 사람이 읽는 글씨 <문서번호>-<label>(TRF-00002-P2) · 인쇄는 화면 차수
--   4 팔렛은 선택 — 맨 위 팔렛이 하나도 없는 트랜스퍼는 지금처럼 문서 단위로 받는다(pallet_id null 길은 결과 무변)
--   5 Finalize 검사는 wms_finalize ① 검사 단계(쓰기 전)에 — 기준 = wms_so_handoff picks × pack_factor(tf_depart 가 qty_sent 로 적는 그 수 · STABLE · 같은 트랜잭션) · 섞인 팔렛(다른 문서의 줄)도 거부
--   6 운임(inv_layer_post_charge 고리)은 문서가 닫힐 때 한 번 — 「마지막 팔렛 도착」 또는 「IN_TRANSIT 잔고 0(tf_settle 로 닫힘)」 중 먼저 오는 쪽(tf_freight_post · 배분 줄 단위 멱등) · 팔렛 없는 받기는 지금처럼 그 도착에서
--   7 상태 — 팔렛 받기는 모든 맨 위 팔렛에 확정 입고가 있거나 IN_TRANSIT 잔고가 0 이어야 received · 아니면 receiving 에 머문다 · qty_received 는 누적 · tf_wms_status 전이는 무변
-- 원장은 손대지 않는다 — inv_post_transfer_arrive 는 이미 입고마다 따로 쌓인다(line_ref 접미어 = 입고 번호 · 묶음 아홉 7).
-- 마지막 정의(파일 ↔ DB md5 일치 확인 2026-10-31): wms_recv_start · tf_receipt_detail · wms_recv_scan · wms_recv_count = transfer_3a · tf_arrive = transfer_4b · wms_finalize = transfer_2b · tf_settle = tf_transit_1(2026-10-31).
-- ⚠️ 컷오버 지우기(supabase/ops/cutover-delete.sql): po_receipt · wms_pallets 둘 다 D 묶음 · truncate 한 문장 — 따로 지운다면 po_receipt 먼저(po_receipt.pallet_id → wms_pallets).
-- ⚠️ ref_carrier 에 「APPS」 행이 없다(2026-10-31 select) — 오피스가 Settings → Carriers 에서 더한다(마이그레이션은 데이터를 넣지 않는다).

-- ═══ 1) 운송 정보 칸 셋(판정 898) + 쓰기 창구 ═══
alter table public.inv_transfer
  add column carrier_id      uuid references public.ref_carrier (id) on delete no action,
  add column tracking_number text,
  add column eta             date;
comment on column public.inv_transfer.carrier_id      is 'tf-pallet-1(판정 898) 운송사(ref_carrier · Freightcom 견적이 쓰는 그 표) · 쓰기는 inv_transfer_shipping_set 만';
comment on column public.inv_transfer.tracking_number is 'tf-pallet-1(판정 898) 운송장 · PRO · BOL 번호(글 · 200 자) · 쓰기는 inv_transfer_shipping_set 만';
comment on column public.inv_transfer.eta             is 'tf-pallet-1(판정 898) 예상 도착일 · 바뀐다 · 쓰기는 inv_transfer_shipping_set 만';
create index inv_transfer_carrier_id_idx on public.inv_transfer (carrier_id) where carrier_id is not null;

create function public.inv_transfer_shipping_set(p_transfer_id uuid, p_carrier_id uuid, p_tracking text, p_eta date) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_staff uuid; v_x public.inv_transfer%rowtype; v_c public.ref_carrier%rowtype; v_trk text; v_changed boolean;
begin
  -- ⭐ 첫 줄 — 트랜스퍼 문서 담당(transfer) · 보내는 창고(fulfillment · Finalize 때 적는다) · 받는 창고(wms_receiving) 셋 중 하나
  if not (public.ims_can_write('transfer') or public.ims_can_write('fulfillment') or public.ims_can_write('wms_receiving')) then
    raise exception 'You cannot change transfer shipping details — ask an admin for the ''transfer'' (or fulfillment / wms_receiving) permission — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  if not (public.ims_can_warehouse(v_x.from_warehouse_id) or public.ims_can_warehouse(v_x.to_warehouse_id)) then   -- 보내는 창고 · 받는 창고 직원 모두(묶음 아홉 6 의 짝)
    raise exception 'Transfer % is between warehouses you are not set up for — nothing was saved', v_x.transfer_number;
  end if;
  if v_x.status in ('received', 'cancelled') then
    raise exception 'Transfer % is % — shipping details can be changed only until it is received — nothing was saved', v_x.transfer_number, v_x.status;
  end if;
  if p_carrier_id is not null then
    select * into v_c from public.ref_carrier c where c.id = p_carrier_id;
    if not found then raise exception 'Carrier not found — pick one from the carrier list (Settings → Carriers) — nothing was saved'; end if;
    if not v_c.is_active then raise exception 'Carrier % is switched off — pick an active carrier — nothing was saved', v_c.name; end if;
  end if;
  v_trk := nullif(regexp_replace(trim(coalesce(p_tracking, '')), '\s+', ' ', 'g'), '');
  if length(v_trk) > 200 then raise exception 'Tracking number is too long (% characters · 200 max) — nothing was saved', length(v_trk); end if;
  v_changed := v_x.carrier_id is distinct from p_carrier_id or v_x.tracking_number is distinct from v_trk or v_x.eta is distinct from p_eta;
  if v_changed then
    update public.inv_transfer x set carrier_id = p_carrier_id, tracking_number = v_trk, eta = p_eta, updated_by = v_staff where x.id = p_transfer_id;
  end if;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', v_x.status,
                            'carrier_id', p_carrier_id, 'carrier', v_c.name, 'tracking_number', v_trk, 'eta', p_eta, 'changed', v_changed, 'updated_by', v_staff);
end $$;
comment on function public.inv_transfer_shipping_set(uuid, uuid, text, date) is 'tf-pallet-1(판정 898) — 트랜스퍼 운송 정보 셋(운송사 · 운송장 · ETA) 쓰기 창구 하나 · transfer | fulfillment | wms_receiving 쓰기 · 출발 또는 도착 창고 · received · cancelled 뒤 거부 · 빈 글 = 지움 · 팔렛 얼림과 다르다(ETA 는 바뀐다)';
revoke all on function public.inv_transfer_shipping_set(uuid, uuid, text, date) from public, anon;
grant execute on function public.inv_transfer_shipping_set(uuid, uuid, text, date) to authenticated;

-- ═══ 2) 입고 ↔ 팔렛 ═══
alter table public.po_receipt add column pallet_id bigint references public.wms_pallets (id) on delete restrict;
comment on column public.po_receipt.pallet_id is 'tf-pallet-1(판정 897) 팔렛 받기 — 이 입고가 받는 맨 위 팔렛(wms_pallets · 박스는 wms_pallet_tree 로 접힌다) · null = 문서 단위 받기(PO 입고는 늘 null) · 컷오버 지우기는 po_receipt 먼저';
create unique index po_receipt_transfer_pallet_uq on public.po_receipt (transfer_id, pallet_id) where pallet_id is not null and status <> 'cancelled';
alter table public.po_receipt add constraint po_receipt_pallet_transfer_ck check (pallet_id is null or transfer_id is not null);

-- ═══ 3) 도우미 — 뿌리 · 나무 · 팔렛 정보 ═══
create function public.wms_pallet_root(p_id bigint) returns bigint
language plpgsql stable set search_path = public, pg_temp as $$
declare v_id bigint := p_id; v_parent bigint; i int := 0;
begin
  loop
    select u.parent_id into v_parent from public.wms_pallets u where u.id = v_id;
    if not found then return null; end if;
    if v_parent is null then return v_id; end if;
    v_id := v_parent; i := i + 1;
    if i > 20 then raise exception 'Pallet % — nesting deeper than 20 (a loop?) — nothing was saved', p_id; end if;
  end loop;
end $$;
comment on function public.wms_pallet_root(bigint) is 'tf-pallet-1 — 유닛의 맨 위 팔렛 id(박스 → 부모를 타고) · 없으면 null';

create function public.wms_pallet_tree(p_root bigint) returns bigint[]
language sql stable set search_path = public, pg_temp as $$
  with recursive t as (select u.id from public.wms_pallets u where u.id = p_root
                       union all select c.id from public.wms_pallets c join t on c.parent_id = t.id)
  select coalesce(array_agg(t.id), '{}') from t;
$$;
comment on function public.wms_pallet_tree(bigint) is 'tf-pallet-1(정한 것 2) — 맨 위 팔렛 + 그 아래 박스 전부의 id 배열(받기의 「팔렛」)';

create function public.tf_pallet_info(p_pallet_id bigint) returns jsonb
language sql stable set search_path = public, pg_temp as $$
  select jsonb_build_object('pallet_id', u.id, 'code', 'PLT-' || u.id::text, 'label', u.label, 'unit_type', u.unit_type,
                            'display', x.transfer_number || '-' || coalesce(u.label, u.id::text),
                            'transfer_id', x.id, 'transfer_number', x.transfer_number,
                            'index', (select count(*) from public.wms_pallets u2 where u2.transfer_id = u.transfer_id and u2.parent_id is null
                                        and (coalesce(substring(u2.label from '^[PB](\d+)$')::int, 2147483647), u2.id) <= (coalesce(substring(u.label from '^[PB](\d+)$')::int, 2147483647), u.id)),
                            'count', (select count(*) from public.wms_pallets u3 where u3.transfer_id = u.transfer_id and u3.parent_id is null))
  from public.wms_pallets u join public.inv_transfer x on x.id = u.transfer_id
  where u.id = p_pallet_id and u.parent_id is null;
$$;
comment on function public.tf_pallet_info(bigint) is 'tf-pallet-1(정한 것 3) — 맨 위 트랜스퍼 팔렛 하나의 {pallet_id, code PLT-<id>, label, display <번호>-<label>, index, count} · 박스 · 판매 팔렛이면 null';
revoke all on function public.wms_pallet_root(bigint), public.wms_pallet_tree(bigint), public.tf_pallet_info(bigint) from public, anon;
grant execute on function public.wms_pallet_root(bigint), public.wms_pallet_tree(bigint), public.tf_pallet_info(bigint) to authenticated;

-- ═══ 4) 얼림(정한 것 1 · 이견 2) — 떠난 트랜스퍼의 팔렛 · 담긴 것은 손대지 못한다 ═══
create function public.wms_pallet_frozen_check(p_transfer_id uuid, p_what text) returns void
language plpgsql stable set search_path = public, pg_temp as $$
declare v_x record;
begin
  if p_transfer_id is null then return; end if;
  select x.transfer_number, x.status into v_x from public.inv_transfer x where x.id = p_transfer_id;
  if found and v_x.status in ('in_transit', 'receiving', 'received') then
    raise exception 'Transfer % has left the warehouse (%) — its pallets and what is on them are frozen; % cannot change — nothing was saved', v_x.transfer_number, v_x.status, p_what;
  end if;
end $$;
create function public.wms_pallet_freeze() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare v_old uuid; v_new uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    v_old := coalesce(old.transfer_id, (select u.transfer_id from public.wms_pallets u where u.id = public.wms_pallet_root(old.parent_id)));
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new := coalesce(new.transfer_id, (select u.transfer_id from public.wms_pallets u where u.id = public.wms_pallet_root(new.parent_id)));
  end if;
  perform public.wms_pallet_frozen_check(v_old, 'a pallet or box');
  if v_new is distinct from v_old then perform public.wms_pallet_frozen_check(v_new, 'a pallet or box'); end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
create function public.wms_pallet_item_freeze() returns trigger
language plpgsql set search_path = public, pg_temp as $$
declare v_old uuid; v_new uuid;
begin
  if tg_op in ('UPDATE', 'DELETE') then
    v_old := coalesce(old.transfer_id, (select u.transfer_id from public.wms_pallets u where u.id = public.wms_pallet_root(old.pallet_id)));
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    v_new := coalesce(new.transfer_id, (select u.transfer_id from public.wms_pallets u where u.id = public.wms_pallet_root(new.pallet_id)));
  end if;
  perform public.wms_pallet_frozen_check(v_old, 'what is on it');
  if v_new is distinct from v_old then perform public.wms_pallet_frozen_check(v_new, 'what is on it'); end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end $$;
comment on function public.wms_pallet_freeze()      is 'tf-pallet-1(정한 것 1) — 트랜스퍼 팔렛 · 박스(자기 transfer_id 또는 뿌리 팔렛의)는 트랜스퍼가 떠난 뒤(in_transit · receiving · received) insert · update · delete 거부 · 판매 팔렛 무접촉 · 되돌리기(wms_rollback)는 떠나기 전만 돌아 부딪치지 않는다';
comment on function public.wms_pallet_item_freeze() is 'tf-pallet-1(정한 것 1) — 팔렛에 담긴 것의 같은 얼림(자기 transfer_id 또는 담긴 팔렛의 뿌리) · 컷오버 truncate 는 행 트리거를 깨우지 않는다';
create trigger wms_pallet_freeze before insert or update or delete on public.wms_pallets for each row execute function public.wms_pallet_freeze();
create trigger wms_pallet_item_freeze before insert or update or delete on public.wms_pallet_items for each row execute function public.wms_pallet_item_freeze();

-- ═══ 5) wms_finalize — ① 검사에 더한다(트랜스퍼): 내 줄이 남의 팔렛에 → 늘 거부 · 맨 위 팔렛이 있으면 남의 줄이 내 팔렛에 거부 + 팔렛 합 = 보낼 수량(handoff picks × pack_factor) ═══
--    transfer_2b 마지막 정의 그대로 + 표시한 블록만 더함(security definer · grant · comment 는 create or replace 로 남는다)
create or replace function public.wms_finalize(p_so_ids uuid[]) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_staff uuid;  v_id uuid;  v_doc public.wms_order_doc%rowtype;  v_all boolean;  v_bad text;
  v_placed boolean;  v_units int;  v_nodim int;  v_type text;
  v_out jsonb := '[]'::jsonb;  v_warn text[] := '{}';  v_dep jsonb;
  v_tops bigint[];  v_tree bigint[];  v_h jsonb;                                  -- tf-pallet-1
begin
  perform public.ims_require_write('fulfillment', 'saved');            -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  if p_so_ids is null or cardinality(p_so_ids) = 0 then raise exception 'No orders given — nothing was saved'; end if;
  -- tr-2b 판정 84: 판매 오더와 트랜스퍼는 한 번에 마무리하지 않는다(한 작업대 · 한 팔렛에 섞이지 않게 · 화면이 옛 판이어도 여기서 막는다) — 다른 검사보다 먼저(상태 · 팩 완료와 무관하게 거부)
  if (select count(distinct d.doc_kind) from public.wms_order_doc d where d.doc_id = any(p_so_ids)) > 1 then
    raise exception 'A sale and a transfer cannot be finalized together — finalize them separately — nothing was saved';
  end if;
  -- ① 검사 전부(잠금 · 하나라도 막히면 전체 거부)
  foreach v_id in array p_so_ids loop
    perform 1 from public.so s where s.id = v_id for update;                      -- 판정 72: 판매 오더 행 잠금은 남긴다(판정 71 「공용 목록만 읽는다」의 예외 · 트랜스퍼 행 잠금은 ②-2)
    perform 1 from public.inv_transfer x where x.id = v_id for update;             -- tr-1b2: 트랜스퍼 행 잠금(판정 72-3 의 짝 · 문서 id 는 둘 중 하나에만 맞는다)
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    if not found then raise exception 'Order not found (%) — nothing was saved', v_id; end if;
    if not public.ims_can_warehouse(v_doc.warehouse_id) then          -- ⭐ 둘째
      raise exception 'Order % is at another warehouse — you are not set up for it — nothing was saved', v_doc.doc_number;
    end if;
    if v_doc.status <> 'picking' then
      raise exception 'Order % is % — only an order in warehouse work (picking) can be finalized — nothing was saved', v_doc.doc_number, v_doc.status;
    end if;
    select coalesce(v.all_packed, false) into v_all from public.wms_order_pack_progress v where v.order_id = v_id;
    if not coalesce(v_all, false) then
      raise exception 'Order % — not every batch is picked and packed yet (%) — nothing was saved', v_doc.doc_number,
        coalesce((select v.packs_done || '/' || v.pick_batches || ' packed' from public.wms_order_pack_progress v where v.order_id = v_id), 'no pick tasks');
    end if;
    select string_agg(format('line %s: %s on pallets but %s packed', sl.line_no, pi.q, coalesce(pk.q, 0)), '; ' order by sl.line_no) into v_bad
    from (select coalesce(order_line_id, transfer_line_id) as order_line_id, sum(qty_base) as q from public.wms_pallet_items where coalesce(order_id, transfer_id) = v_id group by 1) pi
    join public.wms_order_doc_line sl on sl.line_id = pi.order_line_id
    left join (select coalesce(kl.order_line_id, kl.transfer_line_id) as order_line_id, sum(kl.verified_base) as q from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id where coalesce(k.order_id, k.transfer_id) = v_id and k.status = 'completed' group by 1) pk on pk.order_line_id = pi.order_line_id
    where pi.q > coalesce(pk.q, 0);
    if v_bad is not null then raise exception 'Order % — more on pallets than was packed (%) — nothing was saved', v_doc.doc_number, v_bad; end if;
    -- ⭐ tf-pallet-1(판정 897 · 이견 3 · 4): 받는 쪽이 팔렛 단위로 받으므로 트랜스퍼의 팔렛은 그 문서를 정확히 담아야 한다
    if v_doc.doc_kind = 'transfer' then
      select coalesce(array_agg(u.id), '{}') into v_tops from public.wms_pallets u where u.transfer_id = v_id and u.parent_id is null;
      select coalesce(array_agg(t), '{}') into v_tree from unnest(v_tops) r, unnest(public.wms_pallet_tree(r)) t;
      -- (가) 섞임 ① — 이 트랜스퍼의 줄이 다른 문서의 팔렛에(자기 팔렛이 없어도 본다 — 한 덩이로 떠나면 그 팔렛의 문서가 받을 때 남의 물건이 된다)
      select string_agg(format('line %s (%s)', sl.line_no, sl.sku), ', ' order by sl.line_no) into v_bad
      from (select distinct pi.transfer_line_id from public.wms_pallet_items pi where pi.transfer_id = v_id and not (pi.pallet_id = any(v_tree))) q
      join public.wms_order_doc_line sl on sl.line_id = q.transfer_line_id;
      if v_bad is not null then
        raise exception 'Transfer % — on a pallet of another document: % — one transfer per pallet; move them onto this transfer''s own pallets — nothing was saved', v_doc.doc_number, v_bad;
      end if;
      if cardinality(v_tops) > 0 then
        -- (가) 섞임 ② — 이 트랜스퍼의 팔렛(박스 포함)에 다른 문서의 줄
        select string_agg(distinct coalesce(d.doc_number, '?'), ', ') into v_bad
        from public.wms_pallet_items pi left join public.wms_order_doc d on d.doc_id = coalesce(pi.order_id, pi.transfer_id)
        where pi.pallet_id = any(v_tree) and coalesce(pi.order_id, pi.transfer_id) is distinct from v_id;
        if v_bad is not null then
          raise exception 'Transfer % — its pallets also carry goods of another document (%) — one transfer per pallet; move those items off first — nothing was saved', v_doc.doc_number, v_bad;
        end if;
        -- (나) 팔렛 합 = 보낼 수량 — 줄마다 Σqty_base(나무) = Σhandoff picks × pack_factor(tf_depart 가 qty_sent 로 적는 그 수 · STABLE · 이 트랜잭션에 쓰기 없음)
        v_h := public.wms_so_handoff(v_id);
        select string_agg(format('line %s (%s): %s on pallets · %s to send', q.line_no, q.sku, q.pal, q.snd), '; ' order by q.line_no) into v_bad
        from (select sl.line_no, sl.sku,
                     coalesce((select sum(pi.qty_base) from public.wms_pallet_items pi where pi.pallet_id = any(v_tree) and pi.transfer_line_id = sl.line_id), 0) as pal,
                     coalesce((select sum((e ->> 'qty')::numeric) from jsonb_array_elements(v_h -> 'picks') e where (e ->> 'line_id')::uuid = sl.line_id), 0) * sl.pack_factor as snd
                from public.wms_order_doc_line sl where sl.doc_id = v_id) q
        where q.pal <> q.snd;
        if v_bad is not null then
          raise exception 'Transfer % — the pallets do not match what is being sent (%) — put everything on pallets, or remove all pallets to send it as one lot — nothing was saved', v_doc.doc_number, v_bad;
        end if;
      end if;
    end if;
  end loop;
  -- ② 기록 + 전이
  foreach v_id in array p_so_ids loop
    select * into v_doc from public.wms_order_doc d where d.doc_id = v_id;        -- tr-1b1: 공용 목록(판정 71)
    v_placed := exists (select 1 from public.wms_pallet_items pi where coalesce(pi.order_id, pi.transfer_id) = v_id);
    select count(*), count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null) into v_units, v_nodim
    from public.wms_pallets u where coalesce(u.order_id, u.transfer_id) = v_id or u.parent_id in (select p2.id from public.wms_pallets p2 where coalesce(p2.order_id, p2.transfer_id) = v_id);
    v_type := case when v_placed then 'packing_list' else 'direct' end;
    if v_nodim > 0 then v_warn := array_append(v_warn, format('units_without_dims:%s:%s', v_doc.doc_number, v_nodim)); end if;
    insert into public.wms_order_finalize (order_id, transfer_id, fulfillment_type, finalized_by, finalized_at, units, units_without_dims)
    values (case when v_doc.doc_kind = 'so' then v_id end, case when v_doc.doc_kind = 'transfer' then v_id end, v_type, v_staff, now(), v_units, v_nodim);
    if v_doc.doc_kind = 'so' then
      perform public.wms_doc_status(v_doc.doc_kind, v_id, 'packed', v_staff);       -- 판매: packed(출고 · 원장은 오피스 so_finalize → so_ship)
      v_dep := null;
    else
      v_dep := public.tf_depart(v_id, v_staff);                                     -- tr-2 판정 65: 트랜스퍼는 창고 마무리 순간 출발 — 같은 트랜잭션에 보낸 수량 · 원장 · 레이어 · in_transit
    end if;
    v_out := v_out || (jsonb_build_object('so_id', v_id, 'so_number', v_doc.doc_number, 'fulfillment_type', v_type, 'units', v_units, 'units_without_dims', v_nodim,
                                          'shorts', (public.wms_so_handoff(v_id))->'shorts')
                       || case when v_dep is null then '{}'::jsonb else jsonb_build_object('departed', v_dep) end);   -- 판매 반환 모양 무변 · 트랜스퍼만 departed 를 더한다(괄호 = 객체를 먼저 합친 뒤 배열에 한 원소로)
  end loop;
  return jsonb_build_object('finalized', v_out, 'count', jsonb_array_length(v_out), 'warnings', to_jsonb(v_warn));
end $$;

-- ═══ 6) wms_recv_start(p_po_id, p_pallet_id) — 팔렛이 있는 트랜스퍼는 팔렛마다 입고 하나 ═══
--    옛 (uuid) 하나를 지우고 (uuid, bigint default null) 로 — 둘 다 두면 PostgREST 의 {p_po_id} 호출이 「function is not unique」
drop function public.wms_recv_start(uuid);
create function public.wms_recv_start(p_po_id uuid, p_pallet_id bigint default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_staff uuid; v_po public.po%rowtype; v_r public.po_receipt%rowtype; v_out jsonb; v_x public.inv_transfer%rowtype; v_whn text;
        v_tops int; v_root bigint; v_u public.wms_pallets%rowtype; v_pal jsonb; v_from_box boolean := false;   -- tf-pallet-1
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_po from public.po p where p.id = p_po_id;
  if not found then
    -- tr-3a 판정 66: 문서 id 가 트랜스퍼면 도착 창고의 입고 초안(PO 갈래는 아래 그대로) · in_transit(첫 시작) 또는 receiving(초안이 이미 있다) · 도착 창고 권한
    select * into v_x from public.inv_transfer x where x.id = p_po_id;
    if not found then raise exception 'PO not found — nothing was saved'; end if;
    if not public.ims_can_warehouse(v_x.to_warehouse_id) then
      raise exception 'Transfer % arrives at another warehouse — you are not set up for it — nothing was saved', v_x.transfer_number;
    end if;
    if v_x.status not in ('in_transit', 'receiving') then
      raise exception 'Transfer % is % — receiving can start only once it has left the sending warehouse (in transit) — nothing was saved', v_x.transfer_number, v_x.status;
    end if;
    -- ⭐ tf-pallet-1(판정 897): 맨 위 팔렛이 있으면 팔렛 단위로만 · 없으면 문서 단위(지금 그대로)
    select count(*) into v_tops from public.wms_pallets u where u.transfer_id = v_x.id and u.parent_id is null;
    if v_tops > 0 and p_pallet_id is null then
      raise exception 'Transfer % is packed on % pallet(s) — scan a pallet label (PLT-…) to receive it pallet by pallet — nothing was saved', v_x.transfer_number, v_tops;
    end if;
    if p_pallet_id is not null then
      if v_tops = 0 then raise exception 'Transfer % has no pallets — receive it as one lot (start without a pallet) — nothing was saved', v_x.transfer_number; end if;
      v_root := public.wms_pallet_root(p_pallet_id);
      if v_root is null then raise exception 'Pallet PLT-% not found — nothing was saved', p_pallet_id; end if;
      v_from_box := v_root <> p_pallet_id;
      select * into v_u from public.wms_pallets u where u.id = v_root;
      if v_u.transfer_id is distinct from v_x.id then
        raise exception 'Pallet PLT-% is not on transfer % (it belongs to %) — nothing was saved', p_pallet_id, v_x.transfer_number,
          coalesce((select x2.transfer_number from public.inv_transfer x2 where x2.id = v_u.transfer_id), (select 'sales order ' || s.so_number from public.so s where s.id = v_u.order_id), 'another document');
      end if;
      v_pal := public.tf_pallet_info(v_root);
      select * into v_r from public.po_receipt r where r.transfer_id = v_x.id and r.pallet_id = v_root and r.status = 'draft' order by r.created_at limit 1;
      if found then
        return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', null, 'po_number', null, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number,
                                  'warehouse_id', v_r.warehouse_id, 'received_on', v_r.received_on, 'existing', true,
                                  'held', exists (select 1 from public.wms_task_holds h where h.receipt_id = v_r.id and h.resumed_at is null),
                                  'pallet', v_pal, 'resolved_from_box', v_from_box);
      end if;
      perform pg_advisory_xact_lock(hashtext('po_receipt:' || v_x.id::text || ':' || v_root::text));      -- 팔렛당 초안 하나(문서당 하나의 열쇠에 팔렛을 붙였다)
      if exists (select 1 from public.po_receipt r where r.transfer_id = v_x.id and r.pallet_id = v_root and r.status = 'confirmed') then
        raise exception 'Pallet % of transfer % was already received (%) — nothing was saved', v_pal ->> 'display', v_x.transfer_number,
          (select r.receipt_number from public.po_receipt r where r.transfer_id = v_x.id and r.pallet_id = v_root and r.status = 'confirmed' order by r.confirmed_at desc limit 1);
      end if;
      if exists (select 1 from public.po_receipt r where r.transfer_id = v_x.id and r.pallet_id = v_root and r.status = 'draft') then
        raise exception 'Pallet % already has an open receipt — continue that one — nothing was saved', v_pal ->> 'display';
      end if;
      select w.name into v_whn from public.ref_warehouse w where w.id = v_x.to_warehouse_id and w.is_active;
      if v_whn is null then raise exception 'Warehouse of transfer % not found or inactive — nothing was saved', v_x.transfer_number; end if;
      insert into public.po_receipt (po_id, transfer_id, pallet_id, warehouse_id, received_on, status, created_by)
      values (null, v_x.id, v_root, v_x.to_warehouse_id, public.ims_today(), 'draft', v_staff) returning * into v_r;
      return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', null, 'po_number', null, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number,
                                'warehouse_id', v_r.warehouse_id, 'warehouse_name', v_whn, 'received_on', v_r.received_on, 'created_by', v_staff, 'warnings', '[]'::jsonb, 'existing', false, 'held', false,
                                'pallet', v_pal, 'resolved_from_box', v_from_box);
    end if;
    select * into v_r from public.po_receipt r where r.transfer_id = v_x.id and r.status = 'draft' order by r.created_at limit 1;
    if found then
      return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', null, 'po_number', null, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number,
                                'warehouse_id', v_r.warehouse_id, 'received_on', v_r.received_on, 'existing', true,
                                'held', exists (select 1 from public.wms_task_holds h where h.receipt_id = v_r.id and h.resumed_at is null));
    end if;
    perform pg_advisory_xact_lock(hashtext('po_receipt:' || v_x.id::text));                          -- 문서당 초안 하나(규칙 29 · po_receipt_create_by 와 같은 손)
    if exists (select 1 from public.po_receipt r where r.transfer_id = v_x.id and r.status = 'draft') then
      raise exception 'Transfer % already has an open receipt — continue that one — nothing was saved', v_x.transfer_number;
    end if;
    select w.name into v_whn from public.ref_warehouse w where w.id = v_x.to_warehouse_id and w.is_active;
    if v_whn is null then raise exception 'Warehouse of transfer % not found or inactive — nothing was saved', v_x.transfer_number; end if;
    insert into public.po_receipt (po_id, transfer_id, warehouse_id, received_on, status, created_by)
    values (null, v_x.id, v_x.to_warehouse_id, public.ims_today(), 'draft', v_staff) returning * into v_r;
    return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', null, 'po_number', null, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number,
                              'warehouse_id', v_r.warehouse_id, 'warehouse_name', v_whn, 'received_on', v_r.received_on, 'created_by', v_staff, 'warnings', '[]'::jsonb, 'existing', false, 'held', false);
  end if;
  if p_pallet_id is not null then raise exception 'PO % is not received by pallet — start without a pallet — nothing was saved', v_po.po_number; end if;   -- tf-pallet-1
  if v_po.ship_to_warehouse_id is not null and not public.ims_can_warehouse(v_po.ship_to_warehouse_id) then
    raise exception 'PO % ships to another warehouse — you are not set up for it — nothing was saved', v_po.po_number;
  end if;
  select * into v_r from public.po_receipt r where r.po_id = p_po_id and r.status = 'draft' order by r.created_at limit 1;
  if found then
    return jsonb_build_object('id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status, 'po_id', v_po.id, 'po_number', v_po.po_number,
                              'warehouse_id', v_r.warehouse_id, 'received_on', v_r.received_on, 'existing', true,
                              'held', exists (select 1 from public.wms_task_holds h where h.receipt_id = v_r.id and h.resumed_at is null));
  end if;
  v_out := public.po_receipt_create_by(v_staff, p_po_id, public.ims_today(), null);
  return v_out || jsonb_build_object('existing', false, 'held', false);
end $$;
comment on function public.wms_recv_start(uuid, bigint) is 'wms-5-3a 시작(PO 당 열린 초안 하나) · tr-3a 트랜스퍼 갈래 · tf-pallet-1(판정 897): 맨 위 팔렛이 있는 트랜스퍼는 p_pallet_id(PLT-<id> 의 id · 박스 id 는 뿌리 팔렛으로) 필수 · 팔렛마다 초안 하나 · 받은 팔렛 다시 시작 거부 · 다른 팔렛은 동시에 열린다 · 팔렛 없는 트랜스퍼 · PO 는 그대로';
revoke all on function public.wms_recv_start(uuid, bigint) from public, anon;
grant execute on function public.wms_recv_start(uuid, bigint) to authenticated;

-- ═══ 7) tf_receipt_detail — 팔렛 받기면 그 팔렛(박스 포함)의 줄만 · 기대 = 팔렛 몫 · 다른 입고에서 이미 받은 수량 · 운송 정보 ═══
create or replace function public.tf_receipt_detail(p_receipt_id uuid) returns jsonb
language plpgsql stable set search_path = public, pg_temp as $$
declare v_r public.po_receipt%rowtype; v_tree bigint[]; v_pal jsonb; v_tops int;
begin
  select * into v_r from public.po_receipt r where r.id = p_receipt_id and r.transfer_id is not null;
  if not found then return null; end if;
  select count(*) into v_tops from public.wms_pallets u where u.transfer_id = v_r.transfer_id and u.parent_id is null;
  if v_r.pallet_id is not null then v_tree := public.wms_pallet_tree(v_r.pallet_id); v_pal := public.tf_pallet_info(v_r.pallet_id); end if;
  return (
    select jsonb_build_object(
      'header', jsonb_build_object('id', r.id, 'receipt_number', r.receipt_number, 'status', r.status, 'received_on', r.received_on, 'transfer_id', x.id, 'transfer_number', x.transfer_number, 'transfer_status', x.status,
                                   'from_warehouse_id', x.from_warehouse_id, 'from_warehouse', fw.name, 'warehouse_id', r.warehouse_id, 'warehouse_name', tw.name, 'departed_at', x.departed_at, 'received_at', x.received_at,
                                   'confirmed_at', r.confirmed_at, 'created_at', r.created_at, 'note', r.note,
                                   'pallet', v_pal, 'pallet_count', v_tops,                                                                     -- tf-pallet-1: 팔렛 받기면 {pallet_id, code, label, display, index, count} · 아니면 null
                                   'carrier_id', x.carrier_id, 'carrier', c.name, 'tracking_number', x.tracking_number, 'eta', x.eta),      -- 판정 898
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', q.id, 'line_no', q.line_no, 'product_id', q.product_id, 'sku', q.sku, 'product_name', q.product_name, 'pack_factor', q.pack_factor,
                         'qty', q.qty, 'qty_sent', q.qty_sent, 'qty_received', q.qty_received, 'expected_ea', q.expected_ea,
                         'sent_ea', coalesce(q.qty_sent, 0) * q.pack_factor, 'pallet_ea', case when v_tree is null then null else q.expected_ea end, 'received_elsewhere', q.received_elsewhere,   -- tf-pallet-1
                         'counted', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = q.id), 0),
                         'allocated', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = q.id and w.bin_id is not null), 0),
                         'placed', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = q.id and w.putaway_done), 0),
                         'received_here', coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.receipt_id = r.id and l.transfer_line_id = q.id), 0),
                         'work', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'qty_ea', w.qty_ea, 'bin_id', w.bin_id, 'bin', b.name, 'zone', b.zone, 'putaway_done', w.putaway_done, 'count_method', w.count_method,
                                                                               'counted_by', w.counted_by, 'counted_at', w.counted_at, 'putaway_by', w.putaway_by, 'putaway_at', w.putaway_at) order by w.bin_id nulls first, w.created_at)
                                            from public.po_receipt_work w left join public.ref_bin b on b.id = w.bin_id where w.receipt_id = r.id and w.transfer_line_id = q.id), '[]'::jsonb))
                       order by q.line_no), '[]'::jsonb)
                  from (select tl.*, p.name as product_name,
                               case when v_tree is null then coalesce(tl.qty_sent, 0) * tl.pack_factor                                                              -- 문서 단위: 보낸 수량(판정 74)
                                    else coalesce((select sum(pi.qty_base) from public.wms_pallet_items pi where pi.pallet_id = any(v_tree) and pi.transfer_line_id = tl.id), 0) end as expected_ea,   -- 팔렛 몫
                               coalesce((select sum(l.qty_ea) from public.po_receipt_line l join public.po_receipt r2 on r2.id = l.receipt_id
                                          where l.transfer_line_id = tl.id and r2.id <> r.id and r2.status = 'confirmed'), 0) as received_elsewhere
                          from public.inv_transfer_line tl join public.product p on p.id = tl.product_id where tl.transfer_id = x.id) q
                 where v_tree is null or q.expected_ea > 0
                    or exists (select 1 from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = q.id)),            -- 팔렛 받기: 팔렛 줄 + 이 입고에 센 줄(안전띠)
      'diffs', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'transfer_line_id', d.transfer_line_id, 'sku', pr.sku, 'expected_qty', d.expected_qty, 'received_qty', d.received_qty, 'diff_qty', d.received_qty - d.expected_qty,
                                                              'note', d.note, 'resolved_at', d.resolved_at, 'resolution', d.resolution) order by d.created_at), '[]'::jsonb)
                  from public.po_receipt_diff d join public.product pr on pr.id = d.product_id where d.receipt_id = r.id),
      'wms', public.wms_recv_state(r.id))
      from public.po_receipt r join public.inv_transfer x on x.id = r.transfer_id
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = r.warehouse_id
      left join public.ref_carrier c on c.id = x.carrier_id
     where r.id = p_receipt_id);
end $$;
comment on function public.tf_receipt_detail(uuid) is 'tr-3a 트랜스퍼 입고 상세(po_receipt_detail 모양) · tf-pallet-1(판정 897): pallet_id 가 있으면 그 팔렛(박스 포함)의 줄만 · expected_ea = 팔렛 몫 · sent_ea = 줄 전체 · received_elsewhere = 다른 확정 입고에서 받은 합 · header.pallet · pallet_count · 운송 정보 셋(판정 898)';

-- ═══ 8) wms_recv_scan · wms_recv_count — 팔렛 받기에서 그 팔렛에 없는 줄 거부 ═══
create function public.tf_pallet_line_check(p_r public.po_receipt, p_line_id uuid) returns void
language plpgsql stable set search_path = public, pg_temp as $$
declare v_sku text;
begin
  if p_r.pallet_id is null then return; end if;
  if not exists (select 1 from public.wms_pallet_items pi where pi.pallet_id = any(public.wms_pallet_tree(p_r.pallet_id)) and pi.transfer_line_id = p_line_id and pi.qty_base > 0) then
    select tl.sku into v_sku from public.inv_transfer_line tl where tl.id = p_line_id;
    raise exception '% is not on pallet % — it is on another pallet of this transfer; receive it with that pallet — nothing was saved', coalesce(v_sku, 'This item'), (public.tf_pallet_info(p_r.pallet_id)) ->> 'display';
  end if;
end $$;
comment on function public.tf_pallet_line_check(public.po_receipt, uuid) is 'tf-pallet-1 — 팔렛 받기(po_receipt.pallet_id)에서 그 팔렛 나무에 없는 트랜스퍼 줄을 거부(scan · count) · 문서 단위 받기는 지나간다';
revoke all on function public.tf_pallet_line_check(public.po_receipt, uuid) from public, anon;
grant execute on function public.tf_pallet_line_check(public.po_receipt, uuid) to authenticated;

create or replace function public.wms_recv_count(p_receipt_id uuid, p_po_line_id uuid, p_total_ea numeric, p_seen_total numeric, p_count_method text default 'manual') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_total numeric;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  perform public.tf_pallet_line_check(v_r, p_po_line_id);                                                 -- tf-pallet-1: 팔렛 밖 줄 거부
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id;
  if p_seen_total is not null and v_total <> p_seen_total then
    raise exception 'Line total changed under you: you saw %, it is now % (someone else counted) — reload the line and try again — nothing was saved', p_seen_total, v_total;
  end if;
  if v_r.transfer_id is not null then perform public.tf_receiving_started(v_r.transfer_id, v_staff); end if;   -- tr-3a 판정 66: 첫 세기에 in_transit → receiving 저절로
  return public.po_receipt_work_save_by(v_staff, p_receipt_id, p_po_line_id, p_total_ea, p_count_method) || jsonb_build_object('total_before', v_total);
end $$;

create or replace function public.wms_recv_scan(p_receipt_id uuid, p_po_line_id uuid, p_delta_ea numeric, p_count_method text default 'scanned') returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_total numeric;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  if p_delta_ea is null or p_delta_ea = 0 then raise exception 'Scan delta must not be 0 — nothing was saved'; end if;
  perform public.tf_pallet_line_check(v_r, p_po_line_id);                                                 -- tf-pallet-1: 팔렛 밖 줄 거부
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));   -- 속과 같은 열쇠(재진입) · 읽기와 쓰기를 한 손에
  select coalesce(sum(w.qty_ea), 0) into v_total from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id;
  if v_total + p_delta_ea < 0 then raise exception 'Line total would go below 0 (now % · delta %) — nothing was saved', v_total, p_delta_ea; end if;
  if v_r.transfer_id is not null then perform public.tf_receiving_started(v_r.transfer_id, v_staff); end if;   -- tr-3a 판정 66: 첫 세기에 in_transit → receiving 저절로
  return public.po_receipt_work_save_by(v_staff, p_receipt_id, p_po_line_id, v_total + p_delta_ea, p_count_method) || jsonb_build_object('delta', p_delta_ea, 'total_before', v_total);
end $$;

-- ═══ 9) tf_freight_post(문서가 닫힐 때 한 번 · 배분 줄 단위 멱등) · tf_arrive(팔렛 몫 · 누적 · 상태 · 운임 마지막) ═══
create function public.tf_freight_post(p_transfer_id uuid) returns jsonb
language plpgsql set search_path = public, pg_temp as $$
declare v_c record; v_fj jsonb; v_freight jsonb := '[]'::jsonb; v_ferr jsonb := '[]'::jsonb;
begin
  -- tr-4b(판정 78): 도착 전에 확정해 둔 트랜스퍼 운임은 도착 순간 저절로 원가에 얹는다 — 배분 줄이 아직 안 얹힌 확정 문서만(멱등 · 창구가 배분 줄 단위로 건너뛴다)
  --   ⚠️ 재고 움직임은 운임을 기다리지 않는다(판정 65) — 창구가 거부해도 도착은 된다 · 사유는 freight.errors 로
  --   tf-pallet-1(이견 5): 팔렛 받기는 문서가 닫힐 때(마지막 팔렛 도착 또는 IN_TRANSIT 잔고 0) 한 번 — 첫 팔렛에서 돌면 뒤 팔렛의 레이어는 영영 운임을 못 받는다
  for v_c in select distinct c.id, c.charge_number from public.po_charge c join public.po_charge_alloc a on a.po_charge_id = c.id
              where a.transfer_id = p_transfer_id and c.status = 'confirmed' and c.confirmed_at is not null
                and not exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text)
              order by c.charge_number loop
    begin
      v_fj := public.inv_layer_post_charge(v_c.id);
      v_freight := v_freight || jsonb_build_object('charge_id', v_c.id, 'charge_number', v_c.charge_number, 'layers_touched', v_fj -> 'layers_touched', 'amount_posted_cad', v_fj -> 'amount_posted_cad', 'warnings', v_fj -> 'warnings');
    exception when others then
      v_ferr := v_ferr || jsonb_build_object('charge_id', v_c.id, 'charge_number', v_c.charge_number, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('posted', v_freight, 'errors', v_ferr);
end $$;
comment on function public.tf_freight_post(uuid) is 'tf-pallet-1(이견 5 · tr-4b 판정 78 고리를 떼어냄) — 트랜스퍼의 확정 운임을 아직 안 얹힌 배분 줄만 레이어에(멱등) · 문서가 닫힐 때 한 번: tf_arrive(문서 단위 도착 · 마지막 팔렛) · tf_settle(IN_TRANSIT 잔고 0) · 직원에게는 회수';
revoke all on function public.tf_freight_post(uuid) from public, anon, authenticated;

create function public.tf_in_transit_ea(p_transfer_id uuid) returns numeric
language sql stable set search_path = public, pg_temp as $$
  select coalesce(sum(e.qty_delta), 0) from public.inv_ledger e join public.inv_transfer x on x.transfer_number = e.doc_number
   where x.id = p_transfer_id and e.doc_type = 'transfer' and e.warehouse = 'IN_TRANSIT';
$$;
comment on function public.tf_in_transit_ea(uuid) is 'tf-pallet-1 — 문서 전체의 IN_TRANSIT 잔고(EA · 모든 SKU · ims 아닌 줄 포함 — tf_settle 의 줄 잔고와 같은 범위) · 0 = 더 올 것이 없다(닫힘)';
revoke all on function public.tf_in_transit_ea(uuid) from public, anon;
grant execute on function public.tf_in_transit_ea(uuid) to authenticated;

create or replace function public.tf_arrive(p_receipt_id uuid, p_staff uuid) returns jsonb
language plpgsql set search_path = public, pg_temp as $$
declare v_r public.po_receipt%rowtype; v_x public.inv_transfer%rowtype; v_lines jsonb := '[]'::jsonb; v_ledger jsonb; v_n int; v_open int; v_over int := 0; v_short int := 0; v_posted numeric := 0; v_counted numeric := 0;
        v_l record; v_w record; v_rem numeric; v_take numeric; v_fr jsonb := jsonb_build_object('posted', '[]'::jsonb, 'errors', '[]'::jsonb);
        v_tree bigint[]; v_pal jsonb; v_tag text := ''; v_tops int; v_done int; v_transit numeric; v_final boolean;   -- tf-pallet-1
begin
  select * into v_r from public.po_receipt r where r.id = p_receipt_id for update;
  if not found then raise exception 'Receipt not found — nothing was saved'; end if;
  if v_r.transfer_id is null then raise exception 'Receipt % is a purchase receipt — nothing was saved', v_r.receipt_number; end if;
  if v_r.status <> 'draft' then raise exception 'Receipt % is already % — nothing was saved', v_r.receipt_number, v_r.status; end if;
  select * into v_x from public.inv_transfer x where x.id = v_r.transfer_id for update;
  if v_x.status not in ('in_transit', 'receiving') then raise exception 'Transfer % is % — only a transfer in transit can arrive — nothing was saved', v_x.transfer_number, v_x.status; end if;
  if v_r.pallet_id is not null then                                                                    -- tf-pallet-1(판정 897): 팔렛 받기 — 기대 = 그 팔렛(박스 포함)의 몫
    v_tree := public.wms_pallet_tree(v_r.pallet_id); v_pal := public.tf_pallet_info(v_r.pallet_id); v_tag := format(' (pallet %s)', v_pal ->> 'display');
  end if;
  select count(*) into v_open from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.bin_id is null;
  if v_open > 0 then raise exception 'Receipt % — % counted row(s) still have no bin; put them away first — nothing was saved', v_r.receipt_number, v_open; end if;
  if not exists (select 1 from public.po_receipt_work w where w.receipt_id = p_receipt_id) then raise exception 'Receipt % has nothing counted — nothing was saved', v_r.receipt_number; end if;
  -- 줄마다: 기대 = 보낸 수량(qty_sent × pack_factor · 판정 74) — 팔렛 받기는 팔렛 몫 · 받은 = Σ작업 줄 · 판정 68: 받은 > 기대 → 기대까지만 도착(큰 칸부터 채우고 바닥나는 줄에서 자른다 · inv_post_receipt 와 같은 규칙) · 넘는 몫은 over 기록 · 받은 < 기대 → 받은 만큼만 · 모자란 몫은 IN_TRANSIT 에 남고 short 기록
  for v_l in
    select * from (
      select tl.id, tl.line_no, tl.product_id, tl.sku, tl.pack_factor, tl.qty,
             case when v_tree is null then coalesce(tl.qty_sent, 0) * tl.pack_factor
                  else coalesce((select sum(pi.qty_base) from public.wms_pallet_items pi where pi.pallet_id = any(v_tree) and pi.transfer_line_id = tl.id), 0) end as expected_ea,
             coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.transfer_line_id = tl.id), 0) as counted_ea
        from public.inv_transfer_line tl where tl.transfer_id = v_x.id) q
     where v_tree is null or q.expected_ea > 0 or q.counted_ea > 0                                     -- 팔렛 받기: 팔렛 줄(+ 세어 버린 줄은 over 로 — scan 이 막지만 안전띠)
     order by q.line_no
  loop
    if v_l.counted_ea = 0 then
      if v_l.expected_ea > 0 then
        insert into public.po_receipt_diff (receipt_id, po_id, transfer_id, po_line_id, transfer_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
        values (p_receipt_id, null, v_x.id, null, v_l.id, v_l.product_id, 'short', v_l.expected_ea, 0, 'transfer arrival' || v_tag || ' — nothing received for this line (the sent units stay in transit)', p_staff);
        v_short := v_short + 1;
      end if;
      update public.inv_transfer_line set qty_received = coalesce(qty_received, 0), updated_by = p_staff where id = v_l.id;   -- 누적(이견 7) — 첫 도착이면 0(옛 동작과 같다)
      v_lines := v_lines || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'expected_ea', v_l.expected_ea, 'counted_ea', 0, 'posted_ea', 0, 'over_ea', 0, 'short_ea', v_l.expected_ea);
      continue;
    end if;
    v_rem := least(v_l.counted_ea, v_l.expected_ea);
    for v_w in select w.id, w.bin_id, w.qty_ea, rb.name as bin from public.po_receipt_work w join public.ref_bin rb on rb.id = w.bin_id where w.receipt_id = p_receipt_id and w.transfer_line_id = v_l.id order by w.qty_ea desc, rb.name, w.id loop
      v_take := least(v_w.qty_ea, greatest(v_rem, 0));
      if v_take > 0 then
        insert into public.po_receipt_line (po_line_id, transfer_line_id, received_on, received_by, bin_id, qty_ea, receipt_id)
        values (null, v_l.id, v_r.received_on, p_staff, v_w.bin_id, v_take, p_receipt_id);
      end if;
      v_rem := v_rem - v_take;
    end loop;
    if v_l.counted_ea > v_l.expected_ea then
      insert into public.po_receipt_diff (receipt_id, po_id, transfer_id, po_line_id, transfer_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
      values (p_receipt_id, null, v_x.id, null, v_l.id, v_l.product_id, 'over', v_l.expected_ea, v_l.counted_ea, 'transfer arrival' || v_tag || ' — more counted than was sent; only the sent units arrived, the extra is recorded for the in-transit settlement', p_staff);
      v_over := v_over + 1;
    elsif v_l.counted_ea < v_l.expected_ea then
      insert into public.po_receipt_diff (receipt_id, po_id, transfer_id, po_line_id, transfer_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
      values (p_receipt_id, null, v_x.id, null, v_l.id, v_l.product_id, 'short', v_l.expected_ea, v_l.counted_ea, 'transfer arrival' || v_tag || ' — fewer counted than were sent; the missing units stay in transit (in-transit settlement)', p_staff);
      v_short := v_short + 1;
    end if;
    update public.inv_transfer_line set qty_received = coalesce(qty_received, 0) + least(v_l.counted_ea, v_l.expected_ea) / v_l.pack_factor, updated_by = p_staff where id = v_l.id;   -- 누적(이견 7)
    v_posted := v_posted + least(v_l.counted_ea, v_l.expected_ea); v_counted := v_counted + v_l.counted_ea;
    v_lines := v_lines || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'expected_ea', v_l.expected_ea, 'counted_ea', v_l.counted_ea, 'posted_ea', least(v_l.counted_ea, v_l.expected_ea),
                                             'over_ea', greatest(v_l.counted_ea - v_l.expected_ea, 0), 'short_ea', greatest(v_l.expected_ea - v_l.counted_ea, 0));
  end loop;
  select count(*) into v_n from public.po_receipt_line l where l.receipt_id = p_receipt_id;
  if v_n = 0 then raise exception 'Receipt % — nothing of what was sent was received — nothing was saved', v_r.receipt_number; end if;
  if v_tree is null then
    -- 문서 단위(지금 그대로): 상태 손 — receiving → received(received_at/by) · 입고 확정(판정 70 · 오피스 확정 없음) · 원장 · 운임
    if v_x.status = 'in_transit' then perform public.tf_wms_status(v_x.id, 'receiving', p_staff); end if;
    perform public.tf_wms_status(v_x.id, 'received', p_staff);
    update public.po_receipt set status = 'confirmed', confirmed_by = p_staff, confirmed_at = now(), updated_by = p_staff where id = p_receipt_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Receipt % changed under you — nothing was saved', v_r.receipt_number; end if;
    v_ledger := public.inv_post_transfer_arrive(p_receipt_id);                              -- 원장 · 레이어 · 같은 트랜잭션(실패하면 Complete 도 안 된다)
    v_fr := public.tf_freight_post(v_x.id);
    v_final := true;
    select count(*) into v_tops from public.wms_pallets u where u.transfer_id = v_x.id and u.parent_id is null;   -- 0
    v_done := 0; v_transit := public.tf_in_transit_ea(v_x.id);
  else
    -- 팔렛 받기(판정 897 · 이견 7): receiving 에 머물다가 모든 맨 위 팔렛에 확정 입고가 있거나 IN_TRANSIT 잔고가 0 이면 received · 운임은 그때 한 번
    if v_x.status = 'in_transit' then perform public.tf_wms_status(v_x.id, 'receiving', p_staff); end if;
    update public.po_receipt set status = 'confirmed', confirmed_by = p_staff, confirmed_at = now(), updated_by = p_staff where id = p_receipt_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Receipt % changed under you — nothing was saved', v_r.receipt_number; end if;
    v_ledger := public.inv_post_transfer_arrive(p_receipt_id);                              -- 이 입고의 줄만(팔렛 몫) · line_ref 접미어 = 입고 번호
    select count(*), count(*) filter (where exists (select 1 from public.po_receipt r2 where r2.transfer_id = v_x.id and r2.pallet_id = u.id and r2.status = 'confirmed')) into v_tops, v_done
      from public.wms_pallets u where u.transfer_id = v_x.id and u.parent_id is null;
    v_transit := public.tf_in_transit_ea(v_x.id);
    v_final := (v_done >= v_tops) or (v_transit = 0);
    if v_final then
      perform public.tf_wms_status(v_x.id, 'received', p_staff);
      v_fr := public.tf_freight_post(v_x.id);
    end if;
  end if;
  return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', case when v_final then 'received' else 'receiving' end,
                            'received_on', v_r.received_on, 'received_by', p_staff, 'counted_ea', v_counted, 'posted_ea', v_posted, 'over_lines', v_over, 'short_lines', v_short, 'lines', v_lines, 'ledger', v_ledger,
                            'freight', v_fr,
                            'final', v_final, 'pallet', v_pal, 'pallet_count', v_tops, 'pallets_done', v_done, 'in_transit_ea', v_transit);   -- tf-pallet-1
end $$;
comment on function public.tf_arrive(uuid, uuid) is 'tr-3a(판정 66 · 68 · 70 · 74) 도착 — wms_recv_complete 만 부른다 · tf-pallet-1(판정 897): pallet_id 가 있으면 기대 = 그 팔렛(박스 포함)의 몫 · qty_received 누적 · 모든 맨 위 팔렛 확정 또는 IN_TRANSIT 잔고 0 이면 received(아니면 receiving) · 운임(tf_freight_post)은 그때 한 번 · pallet_id null 은 옛 결과 그대로';

-- ═══ 10) tf_settle — 정리 뒤 IN_TRANSIT 잔고 0 이고 receiving 이면 닫는다(received · 운임 한 번) ═══
--    tf_transit_1(2026-10-31) 마지막 정의 그대로 + 끝의 닫힘 블록 · 반환 셋(closed · in_transit_ea · freight) · c_version
create or replace function public.tf_settle(p_transfer_id uuid, p_lines jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c_version constant text := 'tf_settle@2026-10-31.2';   -- tf-pallet-1(판정 897 · 이견 5): 끝에 닫힘 블록(IN_TRANSIT 0 ∧ receiving → received · 운임 한 번) · tf-transit-1(판정 896): 잔고 셈에 ims 아닌 줄을 더했다(아래 v_rem)
        v_staff uuid; v_x public.inv_transfer%rowtype; v_fw text; v_tw text; v_on date; v_e jsonb; v_l public.inv_transfer_line%rowtype; v_action text; v_qty numeric; v_bin public.ref_bin%rowtype;
        v_base text; v_rem numeric; v_sid uuid; v_lref text; v_cost jsonb; v_hdr jsonb; v_out jsonb := '[]'::jsonb; v_closed int := 0; v_d public.po_receipt_diff%rowtype; v_n int;
        v_lost_tot numeric := 0; v_ret_tot numeric := 0;
        v_transit numeric; v_doc_closed boolean := false; v_fr jsonb := jsonb_build_object('posted', '[]'::jsonb, 'errors', '[]'::jsonb);   -- tf-pallet-1
begin
  if not public.ims_can_adjust() then raise exception 'You cannot settle stock in transit — this needs the stock_adjust key (admin, or a supervisor or manager with the key switched on) — nothing was saved'; end if;   -- ⭐ 첫 줄 문(adj-1 판정 183 · 문서 종류와 무관하게 재고 손 하나)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;                 -- 문서 잠금 — 같은 문서 두 정리는 줄을 선다(잔고는 잠근 뒤 읽는다)
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  if v_x.status not in ('in_transit', 'receiving', 'received') then raise exception 'Transfer % is % — only stock that has left the sending warehouse can be settled — nothing was saved', v_x.transfer_number, v_x.status; end if;
  if p_lines is null or jsonb_typeof(p_lines) <> 'array' or jsonb_array_length(p_lines) = 0 then raise exception 'p_lines must be a JSON array of {line_id, action lost|return, qty, bin_id|bin (return)} — nothing was saved'; end if;
  select w.name into v_fw from public.ref_warehouse w where w.id = v_x.from_warehouse_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_x.to_warehouse_id;
  v_on := public.ims_today();
  for v_e in select * from jsonb_array_elements(p_lines) loop
    v_action := lower(trim(v_e ->> 'action'));
    if v_action not in ('lost', 'return') then raise exception 'action must be lost or return — nothing was saved'; end if;
    if (v_e ->> 'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (v_e ->> 'qty')::numeric <= 0 then raise exception 'qty must be a positive number of units (EA) — nothing was saved'; end if;
    v_qty := (v_e ->> 'qty')::numeric;
    select * into v_l from public.inv_transfer_line l where l.id = (v_e ->> 'line_id')::uuid and l.transfer_id = v_x.id;
    if not found then raise exception 'Line % is not on transfer % — nothing was saved', v_e ->> 'line_id', v_x.transfer_number; end if;
    -- 창고 권한 — lost 는 출발 또는 도착 어느 쪽 사람이든(분실은 양쪽이 안다) · return 은 출발 창고(물건이 그 칸으로 돌아온다)
    if v_action = 'return' then
      if not public.ims_can_warehouse(v_x.from_warehouse_id) then raise exception 'Transfer % returns to a warehouse you are not set up for — nothing was saved', v_x.transfer_number; end if;
      if nullif(v_e ->> 'bin_id', '') is not null then select * into v_bin from public.ref_bin b where b.id = (v_e ->> 'bin_id')::uuid;
      else select * into v_bin from public.ref_bin b where b.warehouse_id = v_x.from_warehouse_id and b.name = trim(v_e ->> 'bin'); end if;
      if not found or v_bin.warehouse_id <> v_x.from_warehouse_id or not v_bin.is_active or v_bin.name = '' then raise exception 'Bin % is not an active bin at % — nothing was saved', coalesce(v_e ->> 'bin', v_e ->> 'bin_id', '?'), v_fw; end if;
    else
      if not (public.ims_can_warehouse(v_x.from_warehouse_id) or public.ims_can_warehouse(v_x.to_warehouse_id)) then raise exception 'Transfer % is between warehouses you are not set up for — nothing was saved', v_x.transfer_number; end if;
      v_bin := null;
    end if;
    select coalesce(pp.sku, pr.sku) into v_base from public.product pr left join public.product pp on pp.id = pr.parent_product_id where pr.id = v_l.product_id;
    -- 최대 = 그 줄의 IN_TRANSIT 잔고(원장 · leg 2 + · leg 3 − · 앞선 정리 − · over_2/3 ±)
    select coalesce(sum(e.qty_delta), 0) into v_rem from public.inv_ledger e
     where e.doc_type = 'transfer' and e.doc_number = v_x.transfer_number and e.warehouse = 'IN_TRANSIT' and e.sku = v_base
       and ((e.source = 'ims' and (e.line_ref = v_l.id::text or e.line_ref like v_l.id::text || ':%'))
            or e.source <> 'ims');   -- tf-transit-1(판정 896 · 2026-10-31): 원장에서 연 문서(inv_transfer_open_in_transit)는 들어감 줄이 cin7(line_ref = ProductID)이라 같은 문서 · SKU 의 ims 아닌 줄도 잔고에 넣는다
    if v_rem <= 0 then raise exception 'Line % of transfer % has nothing in transit — nothing to settle — nothing was saved', v_l.line_no, v_x.transfer_number; end if;
    if v_qty > v_rem then raise exception 'Line % of transfer %: % in transit, cannot settle % — nothing was saved', v_l.line_no, v_x.transfer_number, v_rem, v_qty; end if;
    insert into public.inv_transfer_settle (transfer_id, transfer_line_id, action, qty_ea, bin_id, bin, note, settled_by)
    values (v_x.id, v_l.id, v_action, v_qty, v_bin.id, v_bin.name, nullif(trim(v_e ->> 'note'), ''), v_staff) returning id into v_sid;
    v_lref := v_l.id::text || ':settle:' || v_sid::text;
    v_cost := public.inv_layer_post_transfer_settle(v_x.transfer_number, v_lref, v_base, v_qty, v_action, v_fw, v_on, null, null);
    v_hdr := jsonb_build_object('transfer_number', v_x.transfer_number, 'from_warehouse_id', v_x.from_warehouse_id, 'from_warehouse', v_fw, 'to_warehouse_id', v_x.to_warehouse_id, 'to_warehouse', v_tw,
                                'settle_id', v_sid, 'action', v_action, 'settled_on', v_on, 'settled_by', v_staff, 'in_transit_before', v_rem, 'note', nullif(trim(v_e ->> 'note'), ''));
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (v_on, 2, v_base, 'IN_TRANSIT', '', -v_qty, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
            jsonb_build_object('kind', 'transfer', 'leg', case when v_action = 'lost' then 'lost' else 'return_out' end, 'poster', c_version, 'header', v_hdr,
              'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'base_sku', v_base, 'pack_factor', v_l.pack_factor, 'qty_ea', v_qty),
              'rule', case when v_action = 'lost' then format('transfer %s → %s lost in transit: −%s EA out of IN_TRANSIT · its cost share consumed (reason lost) · nothing arrives', v_fw, v_tw, v_qty)
                           else format('transfer %s → %s returned to sender: −%s EA out of IN_TRANSIT (goes back into %s / %s)', v_fw, v_tw, v_qty, v_fw, v_bin.name) end,
              'cost', v_cost));
    if v_action = 'return' then
      insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
      values (v_on, 1, v_base, v_fw, v_bin.name, v_qty, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
              jsonb_build_object('kind', 'transfer', 'leg', 'return_in', 'poster', c_version, 'header', v_hdr,
                'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'base_sku', v_base, 'pack_factor', v_l.pack_factor, 'bin_id', v_bin.id, 'bin', v_bin.name, 'qty_ea', v_qty),
                'rule', format('transfer %s → %s returned to sender: +%s EA into %s / %s (cost layers follow from the transit layers of this document)', v_fw, v_tw, v_qty, v_fw, v_bin.name),
                'cost', v_cost));
    end if;
    update public.inv_transfer_line set qty_lost = qty_lost + case when v_action = 'lost' then v_qty / v_l.pack_factor else 0 end, qty_returned = qty_returned + case when v_action = 'return' then v_qty / v_l.pack_factor else 0 end, updated_by = v_staff where id = v_l.id;
    if v_action = 'lost' then v_lost_tot := v_lost_tot + v_qty; else v_ret_tot := v_ret_tot + v_qty; end if;
    -- 짝: 모자람(short) 차이 행(있으면) — 줄의 잔고가 0 이 되면 닫는다(lost | returned · 둘 다면 lost · 메모에 둘 다)
    select * into v_d from public.po_receipt_diff d where d.transfer_line_id = v_l.id and d.kind = 'short' and d.resolved_at is null order by d.created_at limit 1;
    if found then
      update public.inv_transfer_settle set diff_id = v_d.id where id = v_sid;
      if v_rem - v_qty = 0 then
        update public.po_receipt_diff set resolution = case when (select coalesce(sum(s.qty_ea), 0) from public.inv_transfer_settle s where s.transfer_line_id = v_l.id and s.action = 'lost') > 0 then 'lost' else 'returned' end,
               resolved_by = v_staff, resolved_at = now(), updated_by = v_staff,
               resolution_note = format('settled in transit: lost %s EA · returned %s EA', (select coalesce(sum(s.qty_ea), 0) from public.inv_transfer_settle s where s.transfer_line_id = v_l.id and s.action = 'lost'), (select coalesce(sum(s.qty_ea), 0) from public.inv_transfer_settle s where s.transfer_line_id = v_l.id and s.action = 'return'))
         where id = v_d.id;
        v_closed := v_closed + 1;
      end if;
    end if;
    v_out := v_out || jsonb_build_object('settle_id', v_sid, 'line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'action', v_action, 'qty_ea', v_qty, 'bin', v_bin.name,
                                         'in_transit_before', v_rem, 'in_transit_after', v_rem - v_qty, 'diff_id', v_d.id, 'diff_closed', (v_d.id is not null and v_rem - v_qty = 0), 'cost', v_cost);
    v_d := null;
  end loop;
  -- ⭐ tf-pallet-1(이견 5 · Caleb 2026-10-31): 정리로 문서가 닫히면(IN_TRANSIT 잔고 0 ∧ 무엇인가 도착해 receiving) received 로 · 운임 배분 한 번(마지막 도착과 먼저 오는 쪽 · 멱등)
  --    in_transit 에서 전부 분실(아무것도 안 도착)은 지금처럼 in_transit 에 둔다(받기 화면 목록에 남는다 — 바꾸려면 따로 판정)
  v_transit := public.tf_in_transit_ea(v_x.id);
  if v_x.status = 'receiving' and v_transit = 0 then
    perform public.tf_wms_status(v_x.id, 'received', v_staff);
    v_fr := public.tf_freight_post(v_x.id);
    v_doc_closed := true;
  end if;
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', case when v_doc_closed then 'received' else v_x.status end, 'settled_on', v_on, 'settled_by', v_staff,
                            'lost_ea', v_lost_tot, 'returned_ea', v_ret_tot, 'diffs_closed', v_closed, 'lines', v_out, 'poster', c_version,
                            'closed', v_doc_closed, 'in_transit_ea', v_transit, 'freight', v_fr);   -- tf-pallet-1
exception when unique_violation then
  raise exception 'Transfer % — a ledger row with the same key already exists (%) — nothing was saved', v_x.transfer_number, sqlerrm;
end $$;

-- ═══ 11) 읽기 창구 둘 — tf_pallets(문서의 팔렛 목록) · tf_pallet_lookup(라벨 스캔) ═══
create function public.tf_pallets(p_transfer_id uuid) returns jsonb
language sql stable set search_path = public, pg_temp as $$
  select jsonb_build_object(
    'transfer_id', x.id, 'transfer_number', x.transfer_number, 'status', x.status,
    'from_warehouse_id', x.from_warehouse_id, 'from_warehouse', fw.name, 'to_warehouse_id', x.to_warehouse_id, 'to_warehouse', tw.name,
    'departed_at', x.departed_at, 'received_at', x.received_at,
    'shipping', jsonb_build_object('carrier_id', x.carrier_id, 'carrier', c.name, 'tracking_number', x.tracking_number, 'eta', x.eta),   -- 판정 898
    'in_transit_ea', public.tf_in_transit_ea(x.id),
    'pallet_count', (select count(*) from public.wms_pallets u where u.transfer_id = x.id and u.parent_id is null),
    'pallets_done', (select count(*) from public.wms_pallets u where u.transfer_id = x.id and u.parent_id is null
                       and exists (select 1 from public.po_receipt r where r.transfer_id = x.id and r.pallet_id = u.id and r.status = 'confirmed')),
    'pallets', (select coalesce(jsonb_agg(p.j order by (p.j ->> 'index')::int), '[]'::jsonb) from (
       select public.tf_pallet_info(u.id)
              || jsonb_build_object(
                   'status', case when exists (select 1 from public.po_receipt r where r.transfer_id = x.id and r.pallet_id = u.id and r.status = 'confirmed') then 'done'
                                  when exists (select 1 from public.po_receipt r where r.transfer_id = x.id and r.pallet_id = u.id and r.status = 'draft') then 'receiving'
                                  else 'waiting' end,
                   'receipt_id', (select r.id from public.po_receipt r where r.transfer_id = x.id and r.pallet_id = u.id and r.status <> 'cancelled' order by r.status = 'confirmed' desc, r.created_at desc limit 1),
                   'receipt_number', (select r.receipt_number from public.po_receipt r where r.transfer_id = x.id and r.pallet_id = u.id and r.status <> 'cancelled' order by r.status = 'confirmed' desc, r.created_at desc limit 1),
                   'received_at', (select r.confirmed_at from public.po_receipt r where r.transfer_id = x.id and r.pallet_id = u.id and r.status = 'confirmed' order by r.confirmed_at desc limit 1),
                   'length_in', u.length_in, 'width_in', u.width_in, 'height_in', u.height_in, 'weight_lb', u.weight_lb,
                   'boxes', (select coalesce(jsonb_agg(jsonb_build_object('pallet_id', b.id, 'code', 'PLT-' || b.id::text, 'label', b.label) order by b.id), '[]'::jsonb)
                               from public.wms_pallets b where b.id = any(public.wms_pallet_tree(u.id)) and b.id <> u.id),
                   'lines', (select coalesce(jsonb_agg(jsonb_build_object('transfer_line_id', g.line_id, 'line_no', tl.line_no, 'sku', tl.sku, 'name', pr.name, 'pack_factor', tl.pack_factor,
                                                                          'qty_ea', g.qty_ea, 'qty', round(g.qty_ea / tl.pack_factor, 4)) order by tl.line_no), '[]'::jsonb)
                               from (select pi.transfer_line_id as line_id, sum(pi.qty_base) as qty_ea from public.wms_pallet_items pi
                                      where pi.pallet_id = any(public.wms_pallet_tree(u.id)) and pi.transfer_line_id is not null group by 1) g
                               join public.inv_transfer_line tl on tl.id = g.line_id join public.product pr on pr.id = tl.product_id),
                   'qty_ea', (select coalesce(sum(pi.qty_base), 0) from public.wms_pallet_items pi where pi.pallet_id = any(public.wms_pallet_tree(u.id)))) as j
         from public.wms_pallets u where u.transfer_id = x.id and u.parent_id is null) p))
  from public.inv_transfer x
  join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
  left join public.ref_carrier c on c.id = x.carrier_id
  where x.id = p_transfer_id;
$$;
comment on function public.tf_pallets(uuid) is 'tf-pallet-1(판정 897 · 898) 읽기 — 트랜스퍼의 맨 위 팔렛마다 {pallet_id, code PLT-<id>, label, display, index, count, status waiting|receiving|done, receipt_id, lines[{transfer_line_id, sku, name, qty_ea}], boxes} + shipping{carrier, tracking_number, eta} + in_transit_ea · RLS 는 부르는 사람(inv_transfer select 정책) · 문서 없으면 null';
revoke all on function public.tf_pallets(uuid) from public, anon;
grant execute on function public.tf_pallets(uuid) to authenticated;

create function public.tf_pallet_lookup(p_code text) returns jsonb
language plpgsql stable set search_path = public, pg_temp as $$
declare v_id bigint; v_root bigint; v_u public.wms_pallets%rowtype; v_x public.inv_transfer%rowtype; v_tw text; v_info jsonb; v_reason text; v_pst text; v_r public.po_receipt%rowtype;
begin
  if p_code is null or upper(trim(p_code)) !~ '^(PLT-)?[0-9]{1,15}$' then
    return jsonb_build_object('found', false, 'code', p_code, 'reason', 'bad_code', 'message', 'Not a pallet label — a pallet label reads PLT-<number>');
  end if;
  v_id := substring(upper(trim(p_code)) from '[0-9]+')::bigint;
  v_root := public.wms_pallet_root(v_id);
  if v_root is null then return jsonb_build_object('found', false, 'code', 'PLT-' || v_id::text, 'pallet_id', v_id, 'reason', 'not_found', 'message', format('Pallet PLT-%s is not known', v_id)); end if;
  select * into v_u from public.wms_pallets u where u.id = v_root;
  if v_u.transfer_id is null then
    return jsonb_build_object('found', true, 'code', 'PLT-' || v_id::text, 'pallet_id', v_root, 'resolved_from_box', v_root <> v_id, 'kind', 'so', 'reason', 'sales_order_pallet',
                              'message', format('PLT-%s is a sales-order pallet (%s) — not a transfer', v_id, coalesce((select s.so_number from public.so s where s.id = v_u.order_id), '?')));
  end if;
  select * into v_x from public.inv_transfer x where x.id = v_u.transfer_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_x.to_warehouse_id;
  v_info := public.tf_pallet_info(v_root);
  select * into v_r from public.po_receipt r where r.transfer_id = v_x.id and r.pallet_id = v_root and r.status <> 'cancelled' order by r.status = 'confirmed' desc, r.created_at desc limit 1;
  v_pst := case when v_r.status = 'confirmed' then 'done' when v_r.status = 'draft' then 'receiving' else 'waiting' end;
  v_reason := case when not public.ims_can_warehouse(v_x.to_warehouse_id) then 'other_warehouse'
                   when v_pst = 'done' then 'already_received'
                   when v_x.status not in ('in_transit', 'receiving') then 'not_in_transit'
                   else null end;
  return jsonb_build_object('found', true, 'code', 'PLT-' || v_id::text, 'pallet_id', v_root, 'resolved_from_box', v_root <> v_id, 'kind', 'transfer',
                            'transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'transfer_status', v_x.status,
                            'to_warehouse_id', v_x.to_warehouse_id, 'to_warehouse', v_tw, 'my_warehouse', public.ims_can_warehouse(v_x.to_warehouse_id),
                            'pallet_status', v_pst, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number,
                            'label', v_info ->> 'label', 'display', v_info ->> 'display', 'index', (v_info ->> 'index')::int, 'count', (v_info ->> 'count')::int,
                            'reason', v_reason,
                            'message', case v_reason when 'other_warehouse' then format('Pallet %s arrives at %s — you are not set up for it', v_info ->> 'display', coalesce(v_tw, '?'))
                                                     when 'already_received' then format('Pallet %s was already received (%s)', v_info ->> 'display', v_r.receipt_number)
                                                     when 'not_in_transit' then format('Transfer %s is %s — it is not on its way', v_x.transfer_number, v_x.status)
                                                     else null end);
end $$;
comment on function public.tf_pallet_lookup(text) is 'tf-pallet-1(정한 것 3) 라벨 스캔 — PLT-<id>(또는 숫자만)를 받아 {found, pallet_id(뿌리 팔렛 · 박스면 resolved_from_box), kind so|transfer, transfer_id, transfer_number, transfer_status, to_warehouse, my_warehouse, pallet_status waiting|receiving|done, receipt_id, display, index, count, reason bad_code|not_found|sales_order_pallet|other_warehouse|already_received|not_in_transit|null, message} · 예외를 던지지 않는다(화면이 글을 그대로 보인다)';
revoke all on function public.tf_pallet_lookup(text) from public, anon;
grant execute on function public.tf_pallet_lookup(text) to authenticated;
