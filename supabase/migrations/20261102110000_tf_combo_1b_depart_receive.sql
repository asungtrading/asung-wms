-- ─────────────────────────────────────────────────────────────
-- tf-combo-1b — 트랜스퍼 콤보 줄 ② 창고 · 출발 · 받기 · 정산 (Asung-IMS · 2026-11-02 · 판정 953 ② · 954 · 955 · 957 · tf-combo-1 §0 이견 답 1 (가) · 2 (가) · 3 · 4)
--   ⚠️ tf-combo-1a(20261102100000) 위에서만 — combo_line_id 칸이 없으면 첫 문장이 멈춘다 · 적용 순서 1a → 1b(같은 날)
--   든 것:
--     1) wms_so_handoff 트랜스퍼 갈래(이견 1 (가) · 판정 953 ② = 판정 246 의 트랜스퍼 판 · so_finalize :750 ~ 775 의 cut 꼴) — 콤보마다 통째 콤보 수 = min ⌊구성품 ship ÷ combo_qty⌋ · 넘는 구성품 pick 은 그 줄 picks 의 마지막 칸부터 덜어낸다
--        → put_back[{transfer_number, combo_sku, combo_line_no, line_id, line_no, sku, bin, qty}] · combos[{line_id, line_no, sku, target, ship, short}] · shorts 는 구성품 줄로(combo_sku 꼬리표) · 판매 오더 갈래 · 반환 모양 무변(so_finalize 가 자른다)
--        ⇒ wms_finalize 의 팔렛 검사(Σpicks)와 tf_depart(qty_sent · 원장)가 같은 picks 를 읽는다 — 반쪽 콤보의 구성품은 팔렛에서도 내려야 Finalize 가 선다(에드먼턴에 over 로 가지 않는다)
--     2) tf_depart — 콤보 줄의 qty_sent 는 비워 둔다(이견 2 (가) · 읽을 때 min ⌊구성품 qty_sent ÷ combo_qty⌋) · put_back 을 wms_order_finalize.put_back(transfer_id 행 · wms_finalize 가 이 호출 전에 넣는다)에 · 반환 lines 에 콤보 줄(combo true · sent · short) · put_back · combos
--     3) po_receipt_work_save_by(속 · wms_recv_count · scan 둘 다 이것을 부른다 · 이견 3) — 콤보 줄 id 로 세기 거부(판정 954) · putaway 는 work_id · complete 는 receipt_id 라 올 수 없다
--     4) tf_receipt_detail — lines 에서 콤보 줄 제외 · 구성품 줄에 combo_line_id · combo_qty · combo_sku · combo_barcodes(이견 4 · 판정 887 꼴) · 새 combos[{line_id, line_no, sku, qty, qty_sent, qty_received, components, barcodes}]
--     5) tf_arrive — 콤보 줄은 도착 · 차이 · qty_received 의 주체가 아니다(루프에서 제외 · 판정 954 · 957) · tf_settle — 콤보 줄 정산 거부(957) · tf_over_decide — 콤보 줄 차이 결정 거부(안전띠 · sent_more · found 둘 다)
--     6) inv_transfer_detail — 줄에 is_combo · combo_line_id · combo_qty · combo_sku · components · 콤보 줄의 qty_sent · qty_received 는 셈(min ⌊…⌋) · 콤보 줄의 qty_lost · qty_returned · qty_extra · carried 는 null(판정 955 · 957 · 「—」)
--   재발행(마지막 정의 · DB prosrc md5 대조 뒤 바이트 복사 · 바뀐 줄만 · 줄 끝 「tf-combo-1b」): wms_so_handoff(20260928234815 transfer_1b2) · tf_depart(20260929003624 transfer_2) · po_receipt_work_save_by(20261020153535 rcv_1b)
--        tf_receipt_detail · tf_arrive · tf_settle(20261031210000 tf_pallet_1) · tf_over_decide(20260929014246 transfer_3b) · inv_transfer_detail(20261021131845 rls_3b)
--   손대지 않는 것: wms_finalize(팔렛 검사는 handoff picks 를 그대로 읽는다) · inv_post_transfer_depart · inv_post_transfer_arrive · 레이어 셋 · 운임(tf_freight_post) · carried · 취소 · Unconfirm · wms_recv_scan · count · putaway · complete(셸) · stk_availability · pur_stock(콤보 줄 qty_sent 가 null 이라 intr 0)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 화면 무접촉
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

-- ═══ 0) 1a 가 먼저 — 칸이 없으면 멈춘다 ═══
do $$ begin
  if not exists (select 1 from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'inv_transfer_line' and c.column_name = 'combo_line_id') then
    raise exception 'tf-combo-1b needs tf-combo-1a (20261102100000_tf_combo_1a_lines.sql) applied first — inv_transfer_line.combo_line_id is missing. Nothing was changed.';
  end if;
end $$;

-- ═══ 1) wms_so_handoff 재발행 — 원본 20260928234815_transfer_1b2.sql:898 ~ 950 바이트 복사(DB md5 3b768087…) + 트랜스퍼 콤보 블록 · 반환 열쇠 둘 · comment ═══
create or replace function public.wms_so_handoff(p_so_id uuid) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_doc    public.wms_order_doc%rowtype;
  v_all    boolean;
  l        record;  b record;
  v_ship   numeric;  v_sum numeric;  v_cut numeric;
  v_bins   jsonb;  v_picks jsonb := '[]'::jsonb;  v_shorts jsonb := '[]'::jsonb;  v_units jsonb;
  v_nodim  int;
  i        int;
  cb record;  kk record;  v_whole numeric;  v_q numeric;  v_put_back jsonb := '[]'::jsonb;  v_combos jsonb := '[]'::jsonb;   -- tf-combo-1b(판정 953 ②)
begin
  select * into v_doc from public.wms_order_doc d where d.doc_id = p_so_id;        -- tr-1b1: 공용 목록(판정 71)
  if not found then raise exception 'Order not found'; end if;
  select coalesce(v.all_packed, false) into v_all from public.wms_order_pack_progress v where v.order_id = p_so_id;
  for l in
    select x.line_id as id, x.line_no, x.sku, x.pack_factor, x.qty_target as target,
           coalesce((select sum(kl.verified_base) from public.wms_pack_task_lines kl join public.wms_pack_tasks k on k.id = kl.pack_task_id
                     where coalesce(kl.order_line_id, kl.transfer_line_id) = x.line_id and k.status = 'completed'), 0) as verified_ea,
           coalesce((select jsonb_agg(jsonb_build_object('bin', g.bin, 'units', g.units) order by g.first_id)
                     from (select pb.bin, min(pb.id) as first_id, floor(sum(pb.qty_base) / x.pack_factor) as units
                           from public.wms_pick_line_bins pb join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id join public.wms_pick_tasks t on t.id = pl.pick_task_id
                           where coalesce(pl.order_line_id, pl.transfer_line_id) = x.line_id and not pb.planned and t.status = 'completed' group by pb.bin) g), '[]'::jsonb) as bins
    from public.wms_order_doc_line x where x.doc_id = p_so_id order by x.line_no
  loop
    select coalesce(sum((e->>'units')::numeric), 0) into v_sum from jsonb_array_elements(l.bins) e;
    v_ship := least(v_sum, floor(l.verified_ea / l.pack_factor), l.target);
    if v_ship < 0 then v_ship := 0; end if;
    v_cut := v_sum - v_ship;  v_bins := l.bins;
    i := jsonb_array_length(v_bins) - 1;
    while v_cut > 0 and i >= 0 loop                              -- 마지막 칸부터 줄인다(⬜6)
      v_bins := jsonb_set(v_bins, array[i::text, 'units'], to_jsonb(greatest((v_bins->i->>'units')::numeric - v_cut, 0)));
      v_cut := v_cut - least(v_cut, (l.bins->i->>'units')::numeric);  i := i - 1;
    end loop;
    v_picks := v_picks || coalesce((select jsonb_agg(jsonb_build_object('line_id', l.id, 'bin', e->>'bin', 'qty', (e->>'units')::numeric)) from jsonb_array_elements(v_bins) e where (e->>'units')::numeric > 0), '[]'::jsonb);
    if v_ship < l.target then
      v_shorts := v_shorts || jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'target', l.target, 'ship', v_ship);
    end if;
  end loop;
  -- ⭐ tf-combo-1b(판정 953 ② = 판정 246 의 트랜스퍼 판 · 이견 1 (가)): 트랜스퍼 문서면 콤보 줄마다 통째 콤보 수 = min ⌊구성품 ship ÷ combo_qty⌋(콤보 수량 상한) · 어느 구성품의 pick 이 whole × combo_qty 를 넘으면 넘는 몫을 그 줄 picks 의 마지막 칸부터 덜어낸다(so_finalize :750 ~ 775 의 cut 꼴)
  --   덜어낸 것 = put_back(실물만 선반으로 · 장부는 출발 때 이 picks 로만 빠진다) · wms_finalize 의 팔렛 검사(Σpicks)와 tf_depart(qty_sent · 원장)가 모두 이 picks 를 읽는다 ⇒ 반쪽 콤보의 구성품은 팔렛에서도 내려야 Finalize 가 선다 · shorts 는 구성품 줄로(combo_sku 꼬리표) · 판매 오더 갈래는 무변(so_finalize 가 자르고 put_back 을 적는다)
  if v_doc.doc_kind = 'transfer' then
    for cb in select p.id, p.line_no, p.sku, p.qty as target from public.inv_transfer_line p
               where p.transfer_id = p_so_id and exists (select 1 from public.inv_transfer_line k where k.combo_line_id = p.id) order by p.line_no loop
      select min(floor(coalesce((select sum((e->>'qty')::numeric) from jsonb_array_elements(v_picks) e where (e->>'line_id')::uuid = k.id), 0) / k.combo_qty)) into v_whole
        from public.inv_transfer_line k where k.combo_line_id = cb.id;
      v_whole := least(coalesce(v_whole, 0), cb.target);
      for kk in select k.id, k.line_no, k.sku, k.combo_qty, k.qty as target from public.inv_transfer_line k where k.combo_line_id = cb.id order by k.line_no loop
        select coalesce(sum((e->>'qty')::numeric), 0) - v_whole * kk.combo_qty into v_cut from jsonb_array_elements(v_picks) e where (e->>'line_id')::uuid = kk.id;
        i := jsonb_array_length(v_picks) - 1;
        while v_cut > 0 and i >= 0 loop                              -- 마지막 칸부터(위 ⬜6 과 같은 방향)
          if (v_picks->i->>'line_id')::uuid = kk.id and (v_picks->i->>'qty')::numeric > 0 then
            v_q := least(v_cut, (v_picks->i->>'qty')::numeric);
            v_put_back := v_put_back || jsonb_build_object('transfer_number', v_doc.doc_number, 'combo_sku', cb.sku, 'combo_line_no', cb.line_no, 'line_id', kk.id, 'line_no', kk.line_no, 'sku', kk.sku, 'bin', coalesce(v_picks->i->>'bin', ''), 'qty', v_q);
            v_picks := jsonb_set(v_picks, array[i::text, 'qty'], to_jsonb((v_picks->i->>'qty')::numeric - v_q));
            v_cut := v_cut - v_q;
          end if;
          i := i - 1;
        end loop;
        v_ship := v_whole * kk.combo_qty;
        select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_shorts from jsonb_array_elements(v_shorts) with ordinality t(e, o) where (e->>'line_id')::uuid <> kk.id;
        if v_ship < kk.target then
          v_shorts := v_shorts || jsonb_build_object('line_id', kk.id, 'line_no', kk.line_no, 'sku', kk.sku, 'target', kk.target, 'ship', v_ship, 'combo_sku', cb.sku, 'combo_line_no', cb.line_no);
        end if;
      end loop;
      v_combos := v_combos || jsonb_build_object('line_id', cb.id, 'line_no', cb.line_no, 'sku', cb.sku, 'target', cb.target, 'ship', v_whole, 'short', cb.target - v_whole);
    end loop;
    if jsonb_array_length(v_combos) > 0 then
      select coalesce(jsonb_agg(e order by o), '[]'::jsonb) into v_picks from jsonb_array_elements(v_picks) with ordinality t(e, o) where (e->>'qty')::numeric > 0;
      select coalesce(jsonb_agg(e order by (e->>'line_no')::int), '[]'::jsonb) into v_shorts from jsonb_array_elements(v_shorts) e;
    end if;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('unit_id', u.id, 'unit_type', u.unit_type, 'label', u.label, 'parent_unit_id', u.parent_id, 'status', u.status,
           'length_in', u.length_in, 'width_in', u.width_in, 'height_in', u.height_in, 'weight_lb', u.weight_lb, 'height_note', u.height_note, 'weight_note', u.weight_note,
           'items', coalesce((select jsonb_agg(jsonb_build_object('line_id', it.order_line_id, 'qty', round(it.qty / sl.pack_factor, 4), 'qty_base', it.qty) order by sl.line_no)
                              from (select coalesce(pi.order_line_id, pi.transfer_line_id) as order_line_id, sum(pi.qty_base) as qty from public.wms_pallet_items pi where pi.pallet_id = u.id and coalesce(pi.order_id, pi.transfer_id) = p_so_id group by 1) it
                              join public.wms_order_doc_line sl on sl.line_id = it.order_line_id), '[]'::jsonb)) order by u.parent_id nulls first, u.id), '[]'::jsonb),
         count(*) filter (where u.length_in is null or u.width_in is null or u.height_in is null or u.weight_lb is null)
    into v_units, v_nodim
  from public.wms_pallets u
  where coalesce(u.order_id, u.transfer_id) = p_so_id or u.parent_id in (select p2.id from public.wms_pallets p2 where coalesce(p2.order_id, p2.transfer_id) = p_so_id);
  return jsonb_build_object('so_id', v_doc.doc_id, 'so_number', v_doc.doc_number, 'status', v_doc.status, 'all_packed', v_all,
                            'picks', v_picks, 'units', v_units, 'shorts', v_shorts, 'units_without_dims', coalesce(v_nodim, 0))
         || case when v_doc.doc_kind = 'transfer' then jsonb_build_object('put_back', v_put_back, 'combos', v_combos) else '{}'::jsonb end;   -- tf-combo-1b: 트랜스퍼만 열쇠 둘 더(판매 반환 모양 무변)
end;
$$;
comment on function public.wms_so_handoff(uuid) is '⑤-2b 인계(⬜6 · ⬜7 · 판정 16) — WMS 가 SO 에 넘기는 것을 읽는 창구(stable · invoker · authenticated) · picks [{line_id, bin, qty}] 는 so_finalize 입력 글자 그대로(판매 단위 · 세트 줄은 정수 세트 · 완료된 픽의 실제 칸 wms_pick_line_bins planned=false) · 인계 = least(Σ 칸 단위, floor(verified/pack), 목표) · 마지막 칸부터 줄인다 · over_pick 은 반납(밖) · units(팔렛·박스 · 치수 in·lb · items) · shorts(목표 아래 줄 → so_ship 의 pick_short 형제) · so_finalize 가 picks 를 안 받으면 이것을 쓴다 · ⭐ tf-combo-1b(판정 953 ②): 트랜스퍼 문서면 콤보마다 통째 콤보 수만 picks 에 남기고(넘는 구성품은 마지막 칸부터) put_back[] · combos[] 를 더한다 — wms_finalize 팔렛 검사 · tf_depart 가 같은 picks 를 읽는다 · 판매 갈래 무변';

-- ═══ 2) tf_depart 재발행 — 원본 20260929003624_transfer_2.sql:192 ~ 216 바이트 복사(DB md5 8f5e7783…) + 콤보 줄 제외 · put_back · 반환(create or replace · revoke 는 남는다) ═══
create or replace function public.tf_depart(p_transfer_id uuid, p_staff uuid) returns jsonb
  language plpgsql volatile
  set search_path = public, pg_temp
as $$
declare v_x public.inv_transfer%rowtype; v_h jsonb; v_on date; v_ledger jsonb; v_lines jsonb; v_pb int := 0;   -- tf-combo-1b
begin
  select * into v_x from public.inv_transfer x where x.id = p_transfer_id for update;
  if not found then raise exception 'Transfer not found — nothing was saved'; end if;
  if v_x.status <> 'picking' then raise exception 'Transfer % is % — only a transfer in warehouse work (picking) can depart — nothing was saved', v_x.transfer_number, v_x.status; end if;
  v_on := public.ims_today();
  v_h := public.wms_so_handoff(p_transfer_id);                                             -- picks = Σ실제 칸(팩 회복 포함 · 팩 verified · 요청 상한) · shorts = 덜 뽑은 줄 — 판매 인계와 같은 셈
  if coalesce(jsonb_array_length(v_h -> 'picks'), 0) = 0 then raise exception 'Transfer % has no picked quantity — nothing departs — nothing was saved', v_x.transfer_number; end if;
  -- 판정 74 — 줄마다 보낸 수량 = 뽑은 만큼(판매 단위) · 모자란 몫은 이 문서에서 닫힌다(백오더 · 새 문서 없음 · 더 보낼 것은 오피스가 새 트랜스퍼)
  update public.inv_transfer_line l set qty_sent = coalesce(s.q, 0), updated_by = p_staff
    from (select l2.id, (select sum((e ->> 'qty')::numeric) from jsonb_array_elements(v_h -> 'picks') e where (e ->> 'line_id')::uuid = l2.id) as q
            from public.inv_transfer_line l2 where l2.transfer_id = p_transfer_id
             and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = l2.id)) s   -- tf-combo-1b(판정 955 · 이견 2 (가)): 콤보 줄의 qty_sent 는 비워 둔다 — 읽을 때 min ⌊구성품 qty_sent ÷ combo_qty⌋(inv_transfer_detail · tf_receipt_detail) · stk_availability · pur_stock 의 운송 중 셈에 콤보 pid 가 끼지 않는다
   where s.id = l.id;
  if jsonb_array_length(coalesce(v_h -> 'put_back', '[]'::jsonb)) > 0 then                 -- tf-combo-1b(판정 953 ②): 되돌려 놓을 것을 창고 마무리 행에(so_finalize 와 같은 자리 · wms_finalize 가 이 호출 전에 행을 넣는다 · 원장 · 칸 행은 닿지 않는다)
    update public.wms_order_finalize f set put_back = v_h -> 'put_back' where f.transfer_id = p_transfer_id;
    get diagnostics v_pb = row_count;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'requested', l.qty, 'sent', coalesce(l.qty_sent, cs.sent), 'short', l.qty - coalesce(l.qty_sent, cs.sent),
                                               'combo', (cs.n > 0), 'combo_line_id', l.combo_line_id, 'combo_qty', l.combo_qty, 'combo_sku', (select p.sku from public.inv_transfer_line p where p.id = l.combo_line_id)) order by l.line_no), '[]'::jsonb)
    into v_lines from public.inv_transfer_line l
    left join lateral (select count(*) as n, min(floor(k.qty_sent / k.combo_qty)) as sent from public.inv_transfer_line k where k.combo_line_id = l.id) cs on true   -- tf-combo-1b: 콤보 줄의 보낸 수 = min ⌊구성품 ÷ combo_qty⌋(저장하지 않는다)
   where l.transfer_id = p_transfer_id;
  perform public.tf_wms_status(p_transfer_id, 'in_transit', p_staff);                     -- 출발 = 상태 손 하나(departed_at/by 도 거기서) · 예약(so_available_many 의 talloc)은 이 순간 빠진다
  v_ledger := public.inv_post_transfer_depart(p_transfer_id, v_h -> 'picks', v_on);         -- 원장 · 레이어 · 같은 트랜잭션(실패하면 마무리도 안 된다)
  return jsonb_build_object('transfer_id', v_x.id, 'transfer_number', v_x.transfer_number, 'status', 'in_transit', 'departed_on', v_on, 'departed_by', p_staff,
                            'lines', v_lines, 'shorts', v_h -> 'shorts', 'ledger', v_ledger,
                            'put_back', coalesce(v_h -> 'put_back', '[]'::jsonb), 'combos', coalesce(v_h -> 'combos', '[]'::jsonb), 'put_back_recorded', (v_pb > 0));   -- tf-combo-1b(판정 953 ②): 화면이 「Put back」 목록을 그린다 · wms_finalize 의 departed 에 실린다
end;
$$;
comment on function public.tf_depart(uuid, uuid) is 'tr-2(판정 65 · 74 · 묶음 5) — 창고 마무리(wms_finalize)가 트랜스퍼에 부르는 출발 손: 보낸 수량(줄 · 판매 단위) → in_transit(departed_at/by) → 원장 · 레이어 · 되돌리기 없음 · 직원에게는 회수(판정 31) · tf-combo-1b(판정 953 ② · 955): handoff 가 자른 picks 로 — 콤보 줄 qty_sent 는 비워 두고(읽을 때 셈) put_back 은 wms_order_finalize.put_back 에 · 반환 lines(combo · combo_sku) · put_back · combos · put_back_recorded';

-- ═══ 3) po_receipt_work_save_by 재발행 — 원본 20261020153535_rcv_1b_post_now.sql:1123 ~ 1234 바이트 복사(DB md5 5db6a7d0…) + 콤보 줄 거부 셋 줄 ═══
create or replace function public.po_receipt_work_save_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_receipt_id   uuid,
  p_po_line_id   uuid,
  p_qty_ea       numeric,                           -- ⭐ 그 라인의 센 수량(총량 · 낱개) · 0 = 센 것 없음
  p_count_method text default null                  -- 'scanned' | 'manual' | null
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_r      public.po_receipt%rowtype;
  v_pl     public.po_line%rowtype;
  v_tl     public.inv_transfer_line%rowtype;         -- tr-3a: 트랜스퍼 줄(receipt.transfer_id 가 있으면 p_po_line_id 는 트랜스퍼 줄 id)
  v_line_no int; v_expected numeric; v_is_tf boolean := false;
  v_sku    text;
  v_alloc  numeric;
  v_free   public.po_receipt_work%rowtype;    -- 빈 없는 줄(있으면)
  v_free_n int;
  v_rest   numeric;
  v_n      int;
  v_action text;
  v_id     uuid;
  v_now    timestamptz := now();
  v_posted numeric;                           -- rcv-1b(가드 ⑤): 이 라인의 먼저 반영 합
begin
  if p_staff is null then raise exception 'po_receipt_work_save_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  if p_qty_ea is null or p_qty_ea < 0 then raise exception 'p_qty_ea must be 0 or more — nothing was saved'; end if;
  if p_count_method is not null and p_count_method not in ('scanned', 'manual') then
    raise exception 'p_count_method must be scanned, manual or null — nothing was saved';
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — counts can be changed only while draft — nothing was saved', v_r.receipt_number, v_r.status;
  end if;
  if v_r.transfer_id is not null then                                          -- tr-3a 판정 66 · 74: 트랜스퍼 입고 — 기대 = 보낸 수량(qty_sent × pack_factor · 낱개)
    v_is_tf := true;
    select * into v_tl from public.inv_transfer_line where id = p_po_line_id;
    if not found then raise exception 'Transfer line % not found — nothing was saved', p_po_line_id; end if;
    if v_tl.transfer_id <> v_r.transfer_id then
      raise exception 'Transfer line % does not belong to the transfer of receipt % — nothing was saved', p_po_line_id, v_r.receipt_number;
    end if;
    if exists (select 1 from public.inv_transfer_line k where k.combo_line_id = v_tl.id) then                                   -- tf-combo-1b(판정 954 · 이견 3): 콤보 줄은 셀 수 없다 — 구성품 줄(for <콤보>)로 · wms_recv_count · scan 둘 다 여기로 온다
      raise exception 'Line % (%) is a combo line — count its component lines (for %) instead — nothing was saved', v_tl.line_no, v_tl.sku, v_tl.sku;
    end if;
    v_line_no := v_tl.line_no; v_expected := coalesce(v_tl.qty_sent, 0) * v_tl.pack_factor;
    select pr.sku into v_sku from public.product pr where pr.id = v_tl.product_id;
  else
  select * into v_pl from public.po_line where id = p_po_line_id;
  if not found then raise exception 'PO line % not found — nothing was saved', p_po_line_id; end if;
  if v_pl.po_id <> v_r.po_id then                                              -- 남의 PO 라인을 붙이지 못하게
    raise exception 'PO line % does not belong to the PO of receipt % — nothing was saved', p_po_line_id, v_r.receipt_number;
  end if;
  v_line_no := v_pl.line_no; v_expected := v_pl.qty_ea;
  select pr.sku into v_sku from public.product pr where pr.id = v_pl.product_id;
  end if;
  perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || p_po_line_id::text));   -- 이견 12 — 같은 라인의 동시 저장을 줄 세운다(빈 없는 줄 둘 방지)

  -- 배정 합(빈 붙은 줄들) · 빈 없는 줄
  select coalesce(sum(w.qty_ea), 0) into v_alloc from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is not null;
  select count(*) into v_free_n from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is null;
  if v_free_n > 1 then                                                          -- 불변식 ① 이 깨져 있다 — 자동으로 고치지 않고 알린다
    raise exception 'Line % of receipt % has % unassigned rows — this should not happen; fix the rows first — nothing was saved', v_line_no, v_r.receipt_number, v_free_n;
  end if;
  select * into v_free from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.bin_id is null;

  -- rcv-1b(가드 ⑤): 먼저 반영된 수량 아래로 못 내린다(반영 줄은 얼려 있어 배정 합에 들어 있다 — 글만 따로)
  select coalesce(sum(w.qty_ea), 0) into v_posted from public.po_receipt_work w where w.receipt_id = p_receipt_id and coalesce(w.po_line_id, w.transfer_line_id) = p_po_line_id and w.post_id is not null;
  if p_qty_ea < v_posted then
    raise exception 'Line % (%) of receipt %: % EA are already in stock from post-now — the count cannot go below that; change it with a stock adjustment (Adjustments) — nothing was saved',
      v_line_no, v_sku, v_r.receipt_number, v_posted;
  end if;
  -- ⬜2 나머지 = 센 수량 − 배정 합
  v_rest := p_qty_ea - v_alloc;
  if v_rest < 0 then
    raise exception 'Line % (%) of receipt %: counted % is less than the % already assigned to bins — reduce or remove the bin rows first — nothing was saved',
      v_line_no, v_sku, v_r.receipt_number, p_qty_ea, v_alloc;
  end if;

  if v_rest = 0 then
    if v_free.id is not null then
      delete from public.po_receipt_work where id = v_free.id;
      get diagnostics v_n = row_count;
      if v_n = 0 then raise exception 'Line % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_r.receipt_number; end if;
      v_action := 'deleted';
    else
      v_action := 'unchanged';                                                  -- 0 을 세었고 줄도 없다 — 쓸 것이 없다
    end if;
  elsif v_free.id is not null then
    update public.po_receipt_work
       set qty_ea = v_rest, count_method = coalesce(p_count_method, count_method), counted_by = v_staff, counted_at = v_now
     where id = v_free.id;
    get diagnostics v_n = row_count;
    if v_n = 0 then raise exception 'Line % of receipt % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_r.receipt_number; end if;
    v_id := v_free.id; v_action := 'updated';
  else
    insert into public.po_receipt_work (receipt_id, po_line_id, transfer_line_id, qty_ea, count_method, counted_by, counted_at)
    values (p_receipt_id, case when v_is_tf then null else p_po_line_id end, case when v_is_tf then p_po_line_id end, v_rest, p_count_method, v_staff, v_now)
    returning id into v_id;
    v_action := 'inserted';
  end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_line_id', p_po_line_id, 'line_no', v_line_no, 'sku', v_sku,
    'counted', p_qty_ea, 'allocated', v_alloc, 'unallocated', v_rest,
    'work_id', v_id, 'action', v_action, 'counted_by', v_staff, 'counted_at', v_now,
    'over_ordered', (p_qty_ea > v_expected));                                   -- 초과 신호(표시용 · 판정·큐는 2-b 확정 RPC · 트랜스퍼는 보낸 수량 기준)
end;
$$;

-- ═══ 4) tf_receipt_detail 재발행 — 원본 20261031210000_tf_pallet_1_receive_by_pallet.sql:346 ~ 389 바이트 복사(DB md5 3dc7a30d…) + 콤보 줄 제외 · 구성품 꼬리표 · combo_barcodes · combos ═══
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
                         'combo_line_id', q.combo_line_id, 'combo_qty', q.combo_qty, 'combo_sku', q.combo_sku,                                                                        -- tf-combo-1b(판정 954): 구성품 줄 「for <콤보>」 · 보통 줄은 null
                         'combo_barcodes', coalesce((select jsonb_agg(b.barcode order by b.is_primary desc, b.barcode) from public.inv_transfer_line c join public.product_barcode b on b.product_id = c.product_id and b.is_active where c.id = q.combo_line_id), '[]'::jsonb),   -- tf-combo-1b(이견 4 · 판정 887 꼴): 박스 바코드 한 번 = 구성품 줄마다 combo_qty × pack_factor
                         'sent_ea', coalesce(q.qty_sent, 0) * q.pack_factor, 'pallet_ea', case when v_tree is null then null else q.expected_ea end, 'received_elsewhere', q.received_elsewhere,   -- tf-pallet-1
                         'counted', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = q.id), 0),
                         'allocated', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = q.id and w.bin_id is not null), 0),
                         'placed', coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = q.id and w.putaway_done), 0),
                         'received_here', coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.receipt_id = r.id and l.transfer_line_id = q.id), 0),
                         'work', coalesce((select jsonb_agg(jsonb_build_object('id', w.id, 'qty_ea', w.qty_ea, 'bin_id', w.bin_id, 'bin', b.name, 'zone', b.zone, 'putaway_done', w.putaway_done, 'count_method', w.count_method,
                                                                               'counted_by', w.counted_by, 'counted_at', w.counted_at, 'putaway_by', w.putaway_by, 'putaway_at', w.putaway_at) order by w.bin_id nulls first, w.created_at)
                                            from public.po_receipt_work w left join public.ref_bin b on b.id = w.bin_id where w.receipt_id = r.id and w.transfer_line_id = q.id), '[]'::jsonb))
                       order by q.line_no), '[]'::jsonb)
                  from (select tl.*, p.name as product_name, (select c.sku from public.inv_transfer_line c where c.id = tl.combo_line_id) as combo_sku,                                -- tf-combo-1b
                               case when v_tree is null then coalesce(tl.qty_sent, 0) * tl.pack_factor                                                              -- 문서 단위: 보낸 수량(판정 74)
                                    else coalesce((select sum(pi.qty_base) from public.wms_pallet_items pi where pi.pallet_id = any(v_tree) and pi.transfer_line_id = tl.id), 0) end as expected_ea,   -- 팔렛 몫
                               coalesce((select sum(l.qty_ea) from public.po_receipt_line l join public.po_receipt r2 on r2.id = l.receipt_id
                                          where l.transfer_line_id = tl.id and r2.id <> r.id and r2.status = 'confirmed'), 0) as received_elsewhere
                          from public.inv_transfer_line tl join public.product p on p.id = tl.product_id where tl.transfer_id = x.id
                           and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = tl.id)) q                                                                  -- tf-combo-1b(판정 954): 콤보 줄은 받기 목록에 없다 — 구성품 줄만
                 where v_tree is null or q.expected_ea > 0
                    or exists (select 1 from public.po_receipt_work w where w.receipt_id = r.id and w.transfer_line_id = q.id)),            -- 팔렛 받기: 팔렛 줄 + 이 입고에 센 줄(안전띠)
      'combos', (select coalesce(jsonb_agg(jsonb_build_object('line_id', p.id, 'line_no', p.line_no, 'product_id', p.product_id, 'sku', p.sku, 'product_name', pp.name, 'qty', p.qty,   -- tf-combo-1b(판정 954 · 이견 2): 콤보 줄 요약(세지 않는다 · 화면 「Combo ○○ — n of m」 재료) · qty_sent · qty_received 는 min ⌊구성품 ÷ combo_qty⌋
                         'qty_sent', (select case when bool_or(k.qty_sent is not null) then min(floor(coalesce(k.qty_sent, 0) / k.combo_qty)) end from public.inv_transfer_line k where k.combo_line_id = p.id),
                         'qty_received', (select case when bool_or(k.qty_received is not null) then min(floor(coalesce(k.qty_received, 0) / k.combo_qty)) end from public.inv_transfer_line k where k.combo_line_id = p.id),
                         'components', (select count(*) from public.inv_transfer_line k where k.combo_line_id = p.id),
                         'barcodes', coalesce((select jsonb_agg(b.barcode order by b.is_primary desc, b.barcode) from public.product_barcode b where b.product_id = p.product_id and b.is_active), '[]'::jsonb)) order by p.line_no), '[]'::jsonb)
                  from public.inv_transfer_line p join public.product pp on pp.id = p.product_id
                 where p.transfer_id = x.id and exists (select 1 from public.inv_transfer_line k where k.combo_line_id = p.id)),
      'diffs', (select coalesce(jsonb_agg(jsonb_build_object('id', d.id, 'kind', d.kind, 'transfer_line_id', d.transfer_line_id, 'sku', pr.sku, 'expected_qty', d.expected_qty, 'received_qty', d.received_qty, 'diff_qty', d.received_qty - d.expected_qty,
                                                              'note', d.note, 'resolved_at', d.resolved_at, 'resolution', d.resolution) order by d.created_at), '[]'::jsonb)
                  from public.po_receipt_diff d join public.product pr on pr.id = d.product_id where d.receipt_id = r.id),
      'wms', public.wms_recv_state(r.id))
      from public.po_receipt r join public.inv_transfer x on x.id = r.transfer_id
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = r.warehouse_id
      left join public.ref_carrier c on c.id = x.carrier_id
     where r.id = p_receipt_id);
end $$;
comment on function public.tf_receipt_detail(uuid) is 'tr-3a 트랜스퍼 입고 상세(po_receipt_detail 모양) · tf-pallet-1(판정 897): pallet_id 가 있으면 그 팔렛(박스 포함)의 줄만 · expected_ea = 팔렛 몫 · sent_ea = 줄 전체 · received_elsewhere = 다른 확정 입고에서 받은 합 · header.pallet · pallet_count · 운송 정보 셋(판정 898) · tf-combo-1b(판정 954): lines 에 콤보 줄 없음 · 구성품 줄에 combo_line_id · combo_qty · combo_sku · combo_barcodes · combos[{line_id, line_no, sku, qty, qty_sent, qty_received, components, barcodes}]';

-- ═══ 5) tf_arrive 재발행 — 원본 tf_pallet_1:474 ~ 573 바이트 복사(DB md5 c2da4e95…) + 루프에서 콤보 줄 제외 한 줄 ═══
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
        from public.inv_transfer_line tl where tl.transfer_id = v_x.id
         and not exists (select 1 from public.inv_transfer_line k where k.combo_line_id = tl.id)) q                                              -- tf-combo-1b(판정 954 · 957): 콤보 줄은 도착 · 차이 · qty_received 의 주체가 아니다(구성품 줄이 든다 · 읽을 때 min ⌊…⌋)
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
comment on function public.tf_arrive(uuid, uuid) is 'tr-3a(판정 66 · 68 · 70 · 74) 도착 — wms_recv_complete 만 부른다 · tf-pallet-1(판정 897): pallet_id 가 있으면 기대 = 그 팔렛(박스 포함)의 몫 · qty_received 누적 · 모든 맨 위 팔렛 확정 또는 IN_TRANSIT 잔고 0 이면 received(아니면 receiving) · 운임(tf_freight_post)은 그때 한 번 · pallet_id null 은 옛 결과 그대로 · tf-combo-1b(판정 954 · 957): 콤보 줄(구성품이 달린 줄)은 루프 밖 — 차이 · qty_received 없음';

-- ═══ 6) tf_settle 재발행 — 원본 tf_pallet_1:575 ~ 672 바이트 복사(DB md5 2fc6259e…) + 콤보 줄 거부 · c_version ═══
create or replace function public.tf_settle(p_transfer_id uuid, p_lines jsonb) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare c_version constant text := 'tf_settle@2026-11-02.1';   -- tf-combo-1b(판정 957): 콤보 줄 거부 한 줄   -- tf-pallet-1(판정 897 · 이견 5): 끝에 닫힘 블록(IN_TRANSIT 0 ∧ receiving → received · 운임 한 번) · tf-transit-1(판정 896): 잔고 셈에 ims 아닌 줄을 더했다(아래 v_rem)
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
    if exists (select 1 from public.inv_transfer_line k where k.combo_line_id = v_l.id) then                                                    -- tf-combo-1b(판정 957): 정산은 구성품 줄에서만
      raise exception 'Line % of transfer % is a combo line (%) — settle its component lines instead — nothing was saved', v_l.line_no, v_x.transfer_number, v_l.sku;
    end if;
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

-- ═══ 7) tf_over_decide 재발행 — 원본 20260929014246_transfer_3b.sql:230 ~ 307 바이트 복사(DB md5 e6aa7ed4…) + 콤보 줄 거부 · c_version(create or replace · comment · grant 는 남는다) ═══
create or replace function public.tf_over_decide(p_diff_id uuid, p_choice text, p_from_bin uuid default null, p_note text default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare c_version constant text := 'tf_over_decide@2026-11-02.1';   -- tf-combo-1b: 콤보 줄 거부 한 줄
        v_staff uuid; v_d public.po_receipt_diff%rowtype; v_x public.inv_transfer%rowtype; v_l public.inv_transfer_line%rowtype; v_r public.po_receipt%rowtype; v_fw text; v_tw text; v_on date; v_n numeric; v_base text; v_pid uuid;
        v_fbin public.ref_bin%rowtype; v_tbin public.ref_bin%rowtype; v_shelf numeric; v_lref text; v_cost jsonb; v_hdr jsonb; v_adj jsonb; v_adj_id uuid; v_line jsonb; v_conf jsonb; v_warn text[] := '{}'; v_cnt int;
begin
  if not public.ims_can_adjust() then raise exception 'You cannot decide an over-receipt — this needs the stock_adjust key (admin, or a supervisor or manager with the key switched on) — nothing was saved'; end if;   -- ⭐ 첫 줄 문(판정 76)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if p_choice not in ('sent_more', 'found') then raise exception 'p_choice must be sent_more (the sending warehouse sent more) or found (the receiving warehouse found them) — nothing was saved'; end if;
  select * into v_d from public.po_receipt_diff d where d.id = p_diff_id for update;
  if not found then raise exception 'Difference row not found — nothing was saved'; end if;
  if v_d.kind <> 'over' or v_d.transfer_id is null or v_d.transfer_line_id is null then raise exception 'Difference row % is not a transfer over-receipt — nothing was saved', p_diff_id; end if;
  if v_d.resolved_at is not null then raise exception 'This over-receipt was already decided (%) on % — nothing was saved', v_d.resolution, to_char(v_d.resolved_at, 'YYYY-MM-DD'); end if;
  select * into v_x from public.inv_transfer x where x.id = v_d.transfer_id for update;
  select * into v_l from public.inv_transfer_line l where l.id = v_d.transfer_line_id;
  if exists (select 1 from public.inv_transfer_line k where k.combo_line_id = v_l.id) then                                                      -- tf-combo-1b(판정 954 안전띠): 콤보 줄엔 차이가 생기지 않지만 왔다면 재고로 만들지 않는다(found = 콤보 pid 유령 재고 · sent_more = 콤보 pid 원장)
    raise exception 'Transfer % line % (%) is a combo line — an over-receipt cannot be decided on a combo; its component lines carry the stock — nothing was saved', v_x.transfer_number, v_l.line_no, v_l.sku;
  end if;
  select * into v_r from public.po_receipt r where r.id = v_d.receipt_id;
  select w.name into v_fw from public.ref_warehouse w where w.id = v_x.from_warehouse_id;
  select w.name into v_tw from public.ref_warehouse w where w.id = v_x.to_warehouse_id;
  v_n := v_d.received_qty - v_d.expected_qty;
  if v_n <= 0 then raise exception 'Difference row % has no extra units — nothing was saved', p_diff_id; end if;
  select coalesce(pp.id, pr.id), coalesce(pp.sku, pr.sku) into v_pid, v_base from public.product pr left join public.product pp on pp.id = pr.parent_product_id where pr.id = v_l.product_id;
  v_on := public.ims_today();
  -- 도착 칸 = 입고 때 놓은 칸 가운데 가장 많이 놓은 칸(입고 줄) · 없으면 작업 줄
  select b.* into v_tbin from public.po_receipt_line l join public.ref_bin b on b.id = l.bin_id where l.receipt_id = v_d.receipt_id and l.transfer_line_id = v_l.id order by l.qty_ea desc, b.name limit 1;
  if v_tbin.id is null then select b.* into v_tbin from public.po_receipt_work w join public.ref_bin b on b.id = w.bin_id where w.receipt_id = v_d.receipt_id and w.transfer_line_id = v_l.id order by w.qty_ea desc, b.name limit 1; end if;
  if v_tbin.id is null then raise exception 'Transfer % line %: no bin was recorded at arrival — nothing was saved', v_x.transfer_number, v_l.line_no; end if;
  if p_choice = 'sent_more' then
    if not public.ims_can_warehouse(v_x.from_warehouse_id) then raise exception 'Transfer % leaves from a warehouse you are not set up for — nothing was saved', v_x.transfer_number; end if;
    -- 출발 칸 = 고른 칸 · 기본 = 픽 계획 칸(그 줄의 첫 계획 칸)
    if p_from_bin is not null then select * into v_fbin from public.ref_bin b where b.id = p_from_bin;
    else select b.* into v_fbin from public.wms_pick_line_bins pb join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id join public.ref_bin b on b.id = pb.bin_id
          where pl.transfer_line_id = v_l.id and pb.planned order by pb.id limit 1; end if;
    if v_fbin.id is null or v_fbin.warehouse_id <> v_x.from_warehouse_id or not v_fbin.is_active then raise exception 'Transfer %: pick a bin at % the extra units came from (no planned bin to default to, or the bin is not there) — nothing was saved', v_x.transfer_number, v_fw; end if;
    -- 출발 칸 선반 기대량(장부 − P)을 넘으면 거부(판정 76 · 실제로 거기 있었던 것만 보낼 수 있다)
    v_shelf := public.inv_adjust_ledger(v_fw, v_fbin.name, v_base) - public.inv_adjust_picked(v_x.from_warehouse_id, v_fbin.id, v_pid);
    if v_shelf < v_n then raise exception 'Transfer %: bin % at % is expected to hold only % EA (ledger minus picked) — it cannot have sent % more; pick another bin or decide found — nothing was saved', v_x.transfer_number, v_fbin.name, v_fw, v_shelf, v_n; end if;
    v_lref := v_l.id::text || ':over:' || v_d.id::text;
    v_cost := public.inv_layer_post_transfer_settle(v_x.transfer_number, v_lref, v_base, v_n, 'sent_more', v_tw, v_on, v_fw, null);
    v_hdr := jsonb_build_object('transfer_number', v_x.transfer_number, 'from_warehouse_id', v_x.from_warehouse_id, 'from_warehouse', v_fw, 'to_warehouse_id', v_x.to_warehouse_id, 'to_warehouse', v_tw,
                                'receipt_number', v_r.receipt_number, 'diff_id', v_d.id, 'decision', 'sent_more', 'decided_on', v_on, 'decided_by', v_staff, 'note', nullif(trim(p_note), ''));
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw) values
      (v_on, 2, v_base, v_fw, v_fbin.name, -v_n, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
       jsonb_build_object('kind', 'transfer', 'leg', 'over_1', 'poster', c_version, 'header', v_hdr, 'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'base_sku', v_base, 'pack_factor', v_l.pack_factor, 'bin', v_fbin.name, 'qty_ea', v_n),
         'rule', format('transfer %s → %s over-receipt decided sent_more: −%s EA at %s / %s (the extra was really sent · shelf expectation %s)', v_fw, v_tw, v_n, v_fw, v_fbin.name, v_shelf), 'cost', v_cost)),
      (v_on, 1, v_base, 'IN_TRANSIT', '', v_n, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
       jsonb_build_object('kind', 'transfer', 'leg', 'over_2', 'poster', c_version, 'header', v_hdr, 'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'base_sku', v_base, 'qty_ea', v_n),
         'rule', format('transfer %s → %s over-receipt: +%s EA through IN_TRANSIT (same day · net 0 · cost layers go straight to the receiving warehouse)', v_fw, v_tw, v_n), 'cost', v_cost)),
      (v_on, 2, v_base, 'IN_TRANSIT', '', -v_n, 'transfer_out', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
       jsonb_build_object('kind', 'transfer', 'leg', 'over_3', 'poster', c_version, 'header', v_hdr, 'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'base_sku', v_base, 'qty_ea', v_n),
         'rule', format('transfer %s → %s over-receipt: −%s EA out of IN_TRANSIT (same day · net 0)', v_fw, v_tw, v_n), 'cost', v_cost)),
      (v_on, 1, v_base, v_tw, v_tbin.name, v_n, 'transfer_in', 'transfer', v_x.transfer_number, v_x.id::text, v_lref, null, 'ims',
       jsonb_build_object('kind', 'transfer', 'leg', 'over_4', 'poster', c_version, 'header', v_hdr, 'line', jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'product_id', v_l.product_id, 'sku', v_l.sku, 'base_sku', v_base, 'pack_factor', v_l.pack_factor, 'bin_id', v_tbin.id, 'bin', v_tbin.name, 'qty_ea', v_n),
         'rule', format('transfer %s → %s over-receipt decided sent_more: +%s EA into %s / %s (the bin the arrival was put in)', v_fw, v_tw, v_n, v_tw, v_tbin.name), 'cost', v_cost));
    update public.inv_transfer_line set qty_extra = qty_extra + v_n / v_l.pack_factor, updated_by = v_staff where id = v_l.id;   -- 더 보낸 몫은 별 칸(qty_sent · qty_received 는 요청 상한 CHECK 그대로 · 원장 · 차이 행이 사실을 든다)
    update public.po_receipt_diff set resolution = 'sent_more', resolved_by = v_staff, resolved_at = now(), updated_by = v_staff,
           resolution_note = format('sent_more: %s EA from %s / %s into %s / %s%s', v_n, v_fw, v_fbin.name, v_tw, v_tbin.name, coalesce(' · ' || nullif(trim(p_note), ''), '')) where id = v_d.id;
    return jsonb_build_object('diff_id', v_d.id, 'transfer_number', v_x.transfer_number, 'decision', 'sent_more', 'qty_ea', v_n, 'from_bin', v_fbin.name, 'to_bin', v_tbin.name, 'shelf_expected_before', v_shelf,
                              'ledger_rows', 4, 'cost', v_cost, 'decided_by', v_staff, 'decided_on', v_on, 'warnings', to_jsonb(v_warn), 'poster', c_version);
  else
    if not public.ims_can_warehouse(v_x.to_warehouse_id) then raise exception 'Transfer % arrives at a warehouse you are not set up for — nothing was saved', v_x.transfer_number; end if;
    -- 도착 창고 조정 문서(조정 창구를 부르기만 · 원가 · 문 · 번호는 조정 규칙 그대로)
    v_adj := public.inv_adjust_create(v_x.to_warehouse_id, format('%s over-receipt · found at arrival (receipt %s)', v_x.transfer_number, v_r.receipt_number), null);
    v_adj_id := (v_adj ->> 'id')::uuid;
    v_line := public.inv_adjust_line_set(v_adj_id, jsonb_build_object('product_id', v_pid, 'bin_id', v_tbin.id, 'mode', 'delta', 'qty', v_n, 'reason', 'found', 'note', format('%s over · found at arrival%s', v_x.transfer_number, coalesce(' · ' || nullif(trim(p_note), ''), ''))));
    v_conf := public.inv_adjust_confirm(v_adj_id);
    if (v_conf -> 'ledger' -> 'keys' -> (v_line ->> 'line_id') ->> 'cost_source') = 'unknown' then v_warn := array_append(v_warn, 'unit_cost_unknown_zero'); end if;   -- 판정 56: 도착 창고에 이 SKU 레이어가 없으면 0 원가(화면이 말한다)
    update public.po_receipt_diff set resolution = 'found', resolved_by = v_staff, resolved_at = now(), updated_by = v_staff,
           resolution_note = format('found: %s EA at %s / %s · %s%s', v_n, v_tw, v_tbin.name, v_adj ->> 'adjust_number', coalesce(' · ' || nullif(trim(p_note), ''), '')) where id = v_d.id;
    return jsonb_build_object('diff_id', v_d.id, 'transfer_number', v_x.transfer_number, 'decision', 'found', 'qty_ea', v_n, 'to_bin', v_tbin.name, 'adjust_id', v_adj_id, 'adjust_number', v_adj ->> 'adjust_number',
                              'adjust', v_conf, 'decided_by', v_staff, 'decided_on', v_on, 'warnings', to_jsonb(v_warn), 'poster', c_version);
  end if;
exception when unique_violation then
  raise exception 'Transfer % — a ledger row with the same key already exists (%) — nothing was saved', v_x.transfer_number, sqlerrm;
end;
$$;

-- ═══ 8) inv_transfer_detail 재발행 — 원본 20261021131845_rls_3b_cost_read_gate.sql:340 ~ 373 바이트 복사(DB md5 ec0df9ba…) + 콤보 칸 · 셈 · null ═══
CREATE OR REPLACE FUNCTION public.inv_transfer_detail(p_transfer_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER   -- rls-3b
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select case when not public.ims_can_view('transfer') then null::jsonb else (
    select jsonb_build_object(
      'header', to_jsonb(x) || jsonb_build_object('from_warehouse', fw.name, 'to_warehouse', tw.name, 'created_by_name', cb.name, 'confirmed_by_name', fb.name),
      'lines', (select coalesce(jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', p.name, 'qty', l.qty,
                                                              -- tf-combo-1b(판정 952 · 955 · 957 · 이견 2 (가)): 콤보 줄(cs.is_combo)의 qty_sent · qty_received 는 저장하지 않고 min ⌊구성품 ÷ combo_qty⌋ 로 셈 · qty_lost · qty_returned · qty_extra · carried 는 null(「—」) · 구성품 줄은 combo_line_id · combo_qty · combo_sku
                                                              'qty_sent', coalesce(l.qty_sent, cs.sent), 'short_sent', case when coalesce(l.qty_sent, cs.sent) is not null and coalesce(l.qty_sent, cs.sent) < l.qty then l.qty - coalesce(l.qty_sent, cs.sent) end,
                                                              'qty_received', coalesce(l.qty_received, cs.received), 'qty_lost', case when cs.is_combo then null else l.qty_lost end, 'qty_returned', case when cs.is_combo then null else l.qty_returned end, 'qty_extra', case when cs.is_combo then null else l.qty_extra end, 'pack_factor', l.pack_factor,
                                                              'is_combo', cs.is_combo, 'components', cs.n, 'combo_line_id', l.combo_line_id, 'combo_qty', l.combo_qty, 'combo_sku', (select c.sku from public.inv_transfer_line c where c.id = l.combo_line_id),
                                                              'qty_ea', l.qty * l.pack_factor, 'stock_product_id', coalesce(p.parent_product_id, p.id),
                                                              -- tr-4b(판정 79 · 화면 ⑥ 재료): 이 줄의 자식 레이어(line_ref = 줄 id 또는 줄 id:…)로 따라온 얹힌 원가(kind carried) — 운송 중 · 도착 창고 · 되돌린(출발 창고)
                                                              'carried', case when cs.is_combo then null else (select jsonb_build_object('in_transit', case when (select public.ims_can_view_cost()) then coalesce(sum(ca.amount) filter (where y.warehouse = 'IN_TRANSIT'), 0) end, 'arrived', case when (select public.ims_can_view_cost()) then coalesce(sum(ca.amount) filter (where y.warehouse = tw.name), 0) end,   /* rls-3b(판정 580): 얹힌 원가 금액은 열쇠로 */
                                                                                                    'returned', case when (select public.ims_can_view_cost()) then coalesce(sum(ca.amount) filter (where y.warehouse = fw.name), 0) end, 'total', case when (select public.ims_can_view_cost()) then coalesce(sum(ca.amount), 0) end)
                                                                            from public.inv_layer y join public.inv_layer_cost_add ca on ca.layer_id = y.id and ca.kind = 'carried'
                                                                           where y.origin_type = 'transfer' and y.doc_number = x.transfer_number and (y.line_ref = l.id::text or y.line_ref like l.id::text || ':%')) end) order by l.line_no), '[]'::jsonb)
                  from public.inv_transfer_line l join public.product p on p.id = l.product_id
                  left join lateral (select count(*) > 0 as is_combo, count(*) as n,                                                                                                   -- tf-combo-1b: 콤보 줄 요약(구성품 줄 수 · 셈한 보냄 · 받음)
                                            case when bool_or(k.qty_sent is not null) then min(floor(coalesce(k.qty_sent, 0) / k.combo_qty)) end as sent,
                                            case when bool_or(k.qty_received is not null) then min(floor(coalesce(k.qty_received, 0) / k.combo_qty)) end as received
                                       from public.inv_transfer_line k where k.combo_line_id = l.id) cs on true
                 where l.transfer_id = x.id),
      'shortage', case when x.status = 'draft' then public.inv_transfer_shortage(x.id) else '[]'::jsonb end,
      -- tr-4(판정 67 · 묶음 일곱 · 화면 ⑥ 재료): 이 트랜스퍼에 배분된 비용 문서 — 문서별 금액(자기 통화) · CAD(기준통화면 ×1 · 아니면 × exchange_rate · 취소 제외) · 레이어에 얹힌 금액(cost_add landed · 배분 줄 단위)
      'freight', (select jsonb_build_object(
                    'total_cad', coalesce(sum(case when c.status <> 'cancelled' then a.amount * case when cu.code is not distinct from k.value then 1 else coalesce(c.exchange_rate, 0) end end), 0),
                    'posted_cad', case when (select public.ims_can_view_cost()) then coalesce(sum(pc.posted), 0) end,   /* rls-3b(판정 580): 레이어에 얹힌 금액은 열쇠로 · total_cad(비용 문서의 돈)는 그대로 */
                    'charges', coalesce(jsonb_agg(jsonb_build_object('charge_id', c.id, 'charge_number', c.charge_number, 'supplier_id', c.supplier_id, 'supplier_name', s.name, 'kind', c.kind, 'status', c.status, 'charge_date', c.charge_date, 'due_date', c.due_date,
                                                                'currency_code', cu.code, 'exchange_rate', c.exchange_rate, 'total_amount', c.total_amount, 'tax_amount', c.tax_amount, 'total_with_tax', c.total_amount + c.tax_amount /* po-tax-2 · 세금 전 · 찍힌 세금 · 낼 돈 */, 'alloc_id', a.id, 'amount', a.amount, 'posted_cad', case when (select public.ims_can_view_cost()) then coalesce(pc.posted, 0) end, 'layers', coalesce(pc.n, 0), 'description', c.description) order by c.charge_date, c.charge_number), '[]'::jsonb))
                  from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id join public.supplier s on s.id = c.supplier_id join public.ref_currency cu on cu.id = c.currency_id
                  left join public.inv_config k on k.key = 'base_currency'
                  left join lateral (select sum(ca.amount) as posted, count(*) as n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text) pc on true
                  where a.transfer_id = x.id))
      from public.inv_transfer x
      join public.ref_warehouse fw on fw.id = x.from_warehouse_id join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      left join public.ims_staff cb on cb.id = x.created_by left join public.ims_staff fb on fb.id = x.confirmed_by
     where x.id = p_transfer_id) end;

$function$;
comment on function public.inv_transfer_detail(uuid) is 'IMS 트랜스퍼 상세(header · lines · shortage) · tr-4: freight(total_cad · posted_cad · charges[]) · tr-4b: lines[].carried {in_transit · arrived · returned · total}(판정 79 · 화면 ⑥ 재료) · transfer 열쇠 없으면 null · tf-combo-1b(판정 952 · 955 · 957): lines[].is_combo · components · combo_line_id · combo_qty · combo_sku · 콤보 줄의 qty_sent · qty_received 는 min ⌊구성품 ÷ combo_qty⌋ 셈 · qty_lost · qty_returned · qty_extra · carried 는 null';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int; v_t text;
begin
  select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || p.provolatile::text, ' ' order by p.proname) into v_t from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('wms_so_handoff', 'tf_depart', 'po_receipt_work_save_by', 'tf_receipt_detail', 'tf_arrive', 'tf_settle', 'tf_over_decide', 'inv_transfer_detail');
  if v_t <> 'inv_transfer_detail={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}/trues po_receipt_work_save_by={postgres=X/postgres,service_role=X/postgres}/truev tf_arrive={postgres=X/postgres,service_role=X/postgres}/falsev tf_depart={postgres=X/postgres,service_role=X/postgres}/falsev tf_over_decide={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}/truev tf_receipt_detail={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}/falses tf_settle={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}/truev wms_so_handoff={postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}/falses'
    then v_bad := v_bad || format(' acl_or_kind_changed(%s)', v_t); end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and (
       (p.proname = 'wms_so_handoff' and p.prosrc like '%''put_back'', v_put_back, ''combos'', v_combos%' and p.prosrc like '%v_doc.doc_kind = ''transfer''%')
    or (p.proname = 'tf_depart' and p.prosrc like '%set put_back = v_h -> ''put_back''%' and p.prosrc like '%k.combo_line_id = l2.id%')
    or (p.proname = 'po_receipt_work_save_by' and p.prosrc like '%is a combo line — count its component lines%')
    or (p.proname = 'tf_receipt_detail' and p.prosrc like '%''combo_barcodes''%' and p.prosrc like '%''combos'', (select%')
    or (p.proname = 'tf_arrive' and p.prosrc like '%k.combo_line_id = tl.id%')
    or (p.proname = 'tf_settle' and p.prosrc like '%settle its component lines instead%' and p.prosrc like '%tf_settle@2026-11-02.1%')
    or (p.proname = 'tf_over_decide' and p.prosrc like '%an over-receipt cannot be decided on a combo%' and p.prosrc like '%tf_over_decide@2026-11-02.1%')
    or (p.proname = 'inv_transfer_detail' and p.prosrc like '%''is_combo'', cs.is_combo%' and p.prosrc like '%case when cs.is_combo then null else (select jsonb_build_object(''in_transit''%'));
  if v_n <> 8 then v_bad := v_bad || format(' patched_%s_of_8', v_n); end if;
  -- 무접촉(wms_finalize · 포스터 · 셸 · 가용)
  select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) into v_t from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('wms_finalize', 'inv_post_transfer_depart', 'inv_post_transfer_arrive', 'wms_recv_scan', 'wms_recv_count', 'wms_recv_putaway', 'wms_recv_complete', 'tf_freight_post', 'so_finalize', 'so_ship');
  if v_t <> 'inv_post_transfer_arrive=' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_post_transfer_arrive')
             || ' inv_post_transfer_depart=46764a1aaa9063df5cf58558678ab120 so_finalize=70d4711f91b1ff0b3bb7067864383124 so_ship=30b384f331b241cddbfb7d2fa6300a40 tf_freight_post=' || (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'tf_freight_post')
             || ' wms_finalize=326d31035ab8d89b6b435c6084697032 wms_recv_complete=2e16f224e63c1cfdabf4cfedc48f68fc wms_recv_count=980ad934972d2030d9c2a0450748a3bf wms_recv_putaway=f902f40e1db519e815484c6c269678ab wms_recv_scan=7b6f196f27f005f4c4880ecc2ee93ec3'
    then v_bad := v_bad || format(' untouched_changed(%s)', v_t); end if;
  if v_bad <> '' then raise exception 'tf-combo-1b landing check failed:%', v_bad; end if;
end $$;
