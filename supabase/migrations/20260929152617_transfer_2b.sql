-- 20260929152617_transfer_2b.sql — tr-2b(판정 84 ②): wms_finalize 가 판매 오더와 트랜스퍼가 섞인 목록을 거부한다 (Asung-IMS · 2026-09-29)
--   판정 84(Caleb): 판매 오더와 트랜스퍼는 Fulfillment 작업대에 함께 올릴 수 없다 — 화면(fu v1.2)이 막고, 화면이 옛 판으로 떠 있어도(GitHub Pages 캐시) 여기서 막는다
--   재발행 = wms_finalize 마지막 정의(20260929003624_transfer_2.sql:264 ~ 318 · DB prosrc md5 40dadb2eb9705c6cf1d1fb41b20f84e7 와 같음 · 2026-09-29 실측) 바이트 그대로 + 더한 줄 4(첫 줄 문 · 빈 목록 검사 뒤 · 다른 검사보다 먼저)
--   이름 · 인자 · 반환 모양 무변(create or replace 라 grant · comment 가 남는다) · 판정은 공용 목록 뷰 wms_order_doc.doc_kind(tr-1a:399 · 1b1:43) · 도착 창고가 다른 트랜스퍼 둘은 이 차수에서 다루지 않는다(⬜ 판정 거리)
--   검증: ~/asung/prompts/tf-2b-verify.sql(시험 적용 + 옛/새 대조) · 판매 한 바퀴 ~/asung/prompts/wms-round-verify.sql

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

-- ── wms_finalize ──
create or replace function public.wms_finalize(p_so_ids uuid[]) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_id uuid;  v_doc public.wms_order_doc%rowtype;  v_all boolean;  v_bad text;
  v_placed boolean;  v_units int;  v_nodim int;  v_type text;
  v_out jsonb := '[]'::jsonb;  v_warn text[] := '{}';  v_dep jsonb;
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
end;
$$;
