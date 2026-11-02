-- supabase/tests/tf_combo_1b_check.sql — tf-combo-1b(판정 953 ② · 954 · 955 · 957) 트랜스퍼 콤보 줄 · 출발 put_back · 받기 · 정산 검증 (2026-11-02)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(tf_pallet_1_check 와 같은 꼴) — 기준(begin 앞) → begin → (-v mig1a · -v mig 면: 회귀 R0 를 옛 함수로 돌려 잡아 두고 savepoint 로 되감은 뒤 \i 1a → \i 1b) → 꼴 · 기능 · 회귀 → rollback → 실제 행 무변
--   Claude Code(시험 · 1a 위에서): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig1a=supabase/migrations/20261102100000_tf_combo_1a_lines.sql -v mig=supabase/migrations/20261102110000_tf_combo_1b_depart_receive.sql -f supabase/tests/tf_combo_1b_check.sql
--   Caleb(확인 · 둘 다 적용 뒤): 같은 명령에서 -v mig1a · -v mig 를 뺀다 — R0 · R1 · M1(옛 함수가 있어야 성립)은 확인 갈래에 없다 ⇒ 확인 OK 수 = 시험 OK 수 − 2
--   쓰기 0 — 가짜 재료(TFC- 상품 다섯 · BOM 넷 · 바코드 · 레이어 · 직원 둘 · 트랜스퍼 TFC-T0 ~ T2)는 rollback · transfer_number 는 직접 준다 · ⚠️ po_receipt_number_seq · identity(wms_pick_tasks · wms_pallets …)는 당긴다(틈만)
--   ⚠️ 테스트 DB = 운영 — 잠그는 것은 가짜 행뿐 · 원장 · 레이어 표는 가짜 SKU 행을 넣고 읽을 뿐 · statement_timeout 120s · lock_timeout 3s
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 31
\else
\set EXPECT_OK 29
\endif
-- ── 기준(begin 앞 · 잠금 없음) ──
select (select count(*) from public.inv_transfer) as n_tf, (select count(*) from public.inv_transfer_line) as n_tfl, (select count(*) from public.po_receipt) as n_rc,
       (select count(*) from public.wms_pallets) as n_pal, (select count(*) from public.inv_ledger) as n_led, (select count(*) from public.inv_layer) as n_lay, (select count(*) from public.ims_staff) as n_staff,
       (select count(*) from public.product where sku like 'TFC-%') + (select count(*) from public.inv_transfer where transfer_number like 'TFC-%') as n_fake0,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('wms_so_handoff', 'tf_depart', 'po_receipt_work_save_by', 'tf_receipt_detail', 'tf_arrive', 'tf_settle', 'tf_over_decide', 'inv_transfer_detail')) as fn_md5_0,
       (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || p.provolatile::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('wms_so_handoff', 'tf_depart', 'po_receipt_work_save_by', 'tf_receipt_detail', 'tf_arrive', 'tf_settle', 'tf_over_decide', 'inv_transfer_detail')) as fn_acl_0,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('wms_finalize', 'inv_post_transfer_depart', 'inv_post_transfer_arrive', 'wms_recv_scan', 'wms_recv_count', 'wms_recv_putaway', 'wms_recv_complete', 'tf_freight_post', 'so_finalize', 'so_ship', 'stk_availability', 'pur_stock')) as un_md5_0
\gset
\echo '── 기준: transfer' :n_tf '· lines' :n_tfl '· receipt' :n_rc '· pallets' :n_pal '· ledger' :n_led '· layers' :n_lay '· staff' :n_staff '· fake' :n_fake0
\echo '── fn md5(전):' :fn_md5_0

begin;
select clock_timestamp() as t_begin \gset
set local lock_timeout = '3s';
set local statement_timeout = '120s';
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.run(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.errp(p_sql text, p_prefix text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return 'NOERR';
exception when others then
  return case when p_prefix <> 'NOERR' and sqlerrm like p_prefix || '%' then 'starts: ' || p_prefix else 'got: ' || sqlerrm end;
end $$;
create function pg_temp.chkerr(p_name text, p_sql text, p_prefix text) returns void language sql as $$
  select pg_temp.chk(p_name, pg_temp.errp(p_sql, p_prefix), case when p_prefix = 'NOERR' then 'NOERR' else 'starts: ' || p_prefix end)
$$;
create function pg_temp.as_user(p_uid text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', p_uid, 'role', 'authenticated')::text, true)
$$;
create function pg_temp.norm(p text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
           '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g'),
           '"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+"', '"T"', 'g'),
           'RCV-[0-9]+', 'RCV-#', 'g'),
           '"(id|layer_id|ledger_id|receipt_line_id)": ?[0-9]+', '"\1": 0', 'g')
$$;

-- ── 재료: 창고 둘 · 칸 둘(토론토) · 칸 하나(에드먼턴) · 직원 둘 · 상품 다섯(TFC-C 콤보 = TFC-1 ~ 4 × 6 · pf 1) · BOM · 박스 바코드 · 출발 창고 레이어(원가 10) ──
select id::text as wh1, name as wh1name from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as wh2, name as wh2name from public.ref_warehouse where name = 'Asung - Edmonton' \gset
select b.id::text as bin1, b.name as bin1name from public.ref_bin b where b.warehouse_id = :'wh1'::uuid and b.is_active and b.name <> '' order by b.name limit 1 \gset
select b.id::text as bin1b, b.name as bin1bname from public.ref_bin b where b.warehouse_id = :'wh1'::uuid and b.is_active and b.name <> '' order by b.name offset 1 limit 1 \gset
select b.id::text as bin2, b.name as bin2name from public.ref_bin b where b.warehouse_id = :'wh2'::uuid and b.is_active and b.name <> '' order by b.name limit 1 \gset
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'tfc-a@test.invalid', 'TFC Admin', 'admin', '[]', '{}') returning auth_user_id::text as ua, id::text as sa \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'tfc-w@test.invalid', 'TFC Receiver EDM', 'worker', '["wms_receiving"]', array[:'wh2'::uuid]) returning auth_user_id::text as uw \gset
insert into public.product (sku, name, source) values ('TFC-C', 'TFC Combo', 'manual') returning id::text as pc \gset
insert into public.product (sku, name, source) values ('TFC-1', 'TFC Component 1', 'manual') returning id::text as p1 \gset
insert into public.product (sku, name, source) values ('TFC-2', 'TFC Component 2', 'manual') returning id::text as p2 \gset
insert into public.product (sku, name, source) values ('TFC-3', 'TFC Component 3', 'manual') returning id::text as p3 \gset
insert into public.product (sku, name, source) values ('TFC-4', 'TFC Component 4', 'manual') returning id::text as p4 \gset
insert into public.product_bom (parent_product_id, component_product_id, quantity, is_active, source) values (:'pc'::uuid, :'p1'::uuid, 6, true, 'manual'), (:'pc'::uuid, :'p2'::uuid, 6, true, 'manual'), (:'pc'::uuid, :'p3'::uuid, 6, true, 'manual'), (:'pc'::uuid, :'p4'::uuid, 6, true, 'manual');
insert into public.product_barcode (product_id, barcode, is_primary, is_active, source) values (:'pc'::uuid, 'TFC-BOX-1', true, true, 'manual'), (:'p1'::uuid, 'TFC-EA-1', true, true, 'manual');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('TFC-1', :'wh1name', 'purchase', 'TFC-PO', 'tfc1', public.ims_today() - 30, true, 100, 10, 'inv_cost'), ('TFC-2', :'wh1name', 'purchase', 'TFC-PO', 'tfc2', public.ims_today() - 30, true, 100, 10, 'inv_cost'),
  ('TFC-3', :'wh1name', 'purchase', 'TFC-PO', 'tfc3', public.ims_today() - 30, true, 100, 10, 'inv_cost'), ('TFC-4', :'wh1name', 'purchase', 'TFC-PO', 'tfc4', public.ims_today() - 30, true, 100, 10, 'inv_cost');
set local session_replication_role = origin;
select set_config('tfc.wh1', :'wh1', true), set_config('tfc.wh2', :'wh2', true), set_config('tfc.sa', :'sa', true), set_config('tfc.bin1', :'bin1', true), set_config('tfc.bin1name', :'bin1name', true),
       set_config('tfc.bin1b', :'bin1b', true), set_config('tfc.bin1bname', :'bin1bname', true), set_config('tfc.bin2', :'bin2', true),
       set_config('tfc.pc', :'pc', true), set_config('tfc.p1', :'p1', true), set_config('tfc.p2', :'p2', true), set_config('tfc.p3', :'p3', true), set_config('tfc.p4', :'p4', true) \gset

-- 픽 · 팩 뼈대(picking · 완료된 픽 1 배치 · 팩 완료) — 줄은 따로 넣는다
create function pg_temp.mk_tf(p_tag text) returns uuid language plpgsql as $$
declare v_x uuid; v_pt bigint; v_pk bigint; v_sa uuid := current_setting('tfc.sa')::uuid;
begin
  execute 'set local session_replication_role = replica';
  insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, confirmed_at, at_wms_at, picking_at, created_by)
  values ('TFC-T' || p_tag, 'picking', current_setting('tfc.wh1')::uuid, current_setting('tfc.wh2')::uuid, now(), now(), now(), v_sa) returning id into v_x;
  insert into public.wms_pick_tasks (transfer_id, batch_label, status, completed_at, completed_by, assigned_to) values (v_x, 'A', 'completed', now(), v_sa, v_sa) returning id into v_pt;
  insert into public.wms_pack_tasks (transfer_id, pick_task_id, batch_label, status, completed_at, completed_by, assigned_to) values (v_x, v_pt, 'A', 'completed', now(), v_sa, v_sa) returning id into v_pk;
  execute 'set local session_replication_role = origin';
  return v_x;
end $$;
-- 줄 하나(보통 · 또는 구성품(p_combo_of · combo_qty 6)) + 픽 줄(실제 칸 하나 또는 둘) + 팩 줄(verified = picked)
create function pg_temp.mk_line(p_tf uuid, p_no int, p_pid uuid, p_sku text, p_qty numeric, p_combo_of uuid, p_picked1 numeric, p_picked2 numeric) returns uuid language plpgsql as $$
declare v_l uuid; v_pt bigint; v_pk bigint; v_ptl bigint; v_sa uuid := current_setting('tfc.sa')::uuid;
begin
  execute 'set local session_replication_role = replica';
  select id into v_pt from public.wms_pick_tasks where transfer_id = p_tf limit 1;
  select id into v_pk from public.wms_pack_tasks where transfer_id = p_tf limit 1;
  if p_combo_of is null then                                                                 -- 보통 줄: 옛 칸만(R0 은 1a 전 · combo 칸이 없다)
    insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (p_tf, p_no, p_pid, p_sku, p_qty, 1) returning id into v_l;
  else                                                                                       -- 구성품 줄: 새 칸은 동적 SQL(\i 전 본문 검사에 걸리지 않게)
    execute 'insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor, combo_line_id, combo_qty) values ($1, $2, $3, $4, $5, 1, $6, 6) returning id'
      into v_l using p_tf, p_no, p_pid, p_sku, p_qty, p_combo_of;
  end if;
  if p_picked1 is not null then
    insert into public.wms_pick_task_lines (pick_task_id, transfer_line_id, assigned_base, picked_base, status, picked_at, picked_by) values (v_pt, v_l, p_qty, p_picked1 + coalesce(p_picked2, 0), 'picked', now(), v_sa) returning id into v_ptl;
    insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at) values (v_ptl, current_setting('tfc.bin1')::uuid, current_setting('tfc.bin1name'), p_picked1, false, v_sa, now());
    if coalesce(p_picked2, 0) > 0 then
      insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at) values (v_ptl, current_setting('tfc.bin1b')::uuid, current_setting('tfc.bin1bname'), p_picked2, false, v_sa, now());
    end if;
    insert into public.wms_pack_task_lines (pack_task_id, transfer_line_id, expected_base, verified_base, status, verified_at, verified_by) values (v_pk, v_l, p_qty, p_picked1 + coalesce(p_picked2, 0), 'verified', now(), v_sa);
  end if;
  execute 'set local session_replication_role = origin';
  return v_l;
end $$;
-- 콤보 문서 한 장: 줄 1 콤보 TFC-C qty 2(픽 없음) · 줄 2 ~ 5 구성품 12 each(픽 TFC-1 8 + 4(두 칸) · TFC-2 12 · TFC-3 9 · TFC-4 12) · 줄 6 보통 TFC-1 5(픽 3)
create function pg_temp.mk_combo_tf(p_tag text) returns uuid language plpgsql as $$
declare v_x uuid; v_c uuid;
begin
  v_x := pg_temp.mk_tf(p_tag);
  v_c := pg_temp.mk_line(v_x, 1, current_setting('tfc.pc')::uuid, 'TFC-C', 2, null, null, null);
  perform pg_temp.mk_line(v_x, 2, current_setting('tfc.p1')::uuid, 'TFC-1', 12, v_c, 8, 4);
  perform pg_temp.mk_line(v_x, 3, current_setting('tfc.p2')::uuid, 'TFC-2', 12, v_c, 12, null);
  perform pg_temp.mk_line(v_x, 4, current_setting('tfc.p3')::uuid, 'TFC-3', 12, v_c, 9, null);
  perform pg_temp.mk_line(v_x, 5, current_setting('tfc.p4')::uuid, 'TFC-4', 12, v_c, 12, null);
  perform pg_temp.mk_line(v_x, 6, current_setting('tfc.p1')::uuid, 'TFC-1', 5, null, 3, null);
  return v_x;
end $$;
create function pg_temp.line(p_tf uuid, p_no int) returns uuid language sql as $$ select l.id from public.inv_transfer_line l where l.transfer_id = p_tf and l.line_no = p_no $$;
create function pg_temp.pack_task(p_tf uuid) returns bigint language sql as $$ select k.id from public.wms_pack_tasks k where k.transfer_id = p_tf limit 1 $$;
create function pg_temp.mk_unit(p_tf uuid, p_label text) returns bigint language sql as $$
  insert into public.wms_pallets (transfer_id, unit_type, label, status, created_by) values (p_tf, 'pallet', p_label, 'building', current_setting('tfc.sa')::uuid) returning id
$$;
create function pg_temp.mk_item(p_unit bigint, p_tf uuid, p_no int, p_qty numeric) returns bigint language sql as $$
  insert into public.wms_pallet_items (pallet_id, transfer_id, transfer_line_id, pack_task_id, qty_base) values (p_unit, p_tf, pg_temp.line(p_tf, p_no), pg_temp.pack_task(p_tf), p_qty) returning id
$$;
create function pg_temp.putaway_all(p_rid uuid) returns int language plpgsql as $$
declare w record; n int := 0;
begin
  for w in select id from public.po_receipt_work where receipt_id = p_rid and bin_id is null loop
    perform public.wms_recv_putaway(w.id, current_setting('tfc.bin2')::uuid, true); n := n + 1;
  end loop;
  return n;
end $$;
-- 줄 요약 line_no:sku:qty_sent/qty_received(null = -)
create function pg_temp.lines(p_tf uuid) returns text language sql as $$
  select string_agg(l.line_no || ':' || l.sku || ':' || coalesce(trim_scale(l.qty_sent)::text, '-') || '/' || coalesce(trim_scale(l.qty_received)::text, '-'), ',' order by l.line_no) from public.inv_transfer_line l where l.transfer_id = p_tf
$$;
-- 회귀 요약(보통 문서 한 바퀴 · 옛 ↔ 새 같은 글): handoff(새 열쇠 둘 뺌) · 출발 반환(새 열쇠 셋 뺌) · 줄 · 차이 · 원장 · 레이어 · 상세 줄(새 열쇠 다섯 뺌)
create function pg_temp.summary(p_tf uuid, p_h jsonb, p_fin jsonb) returns text language sql as $$
  select pg_temp.norm(
    'handoff=' || (p_h - array['put_back', 'combos'])::text
    || ' departed=' || jsonb_set((p_fin -> 'finalized' -> 0 -> 'departed') - array['put_back', 'combos', 'put_back_recorded'], '{lines}',
                                 (select jsonb_agg(l - array['combo', 'combo_qty', 'combo_sku', 'combo_line_id'] order by o) from jsonb_array_elements(p_fin -> 'finalized' -> 0 -> 'departed' -> 'lines') with ordinality t(l, o)))::text
    || ' status=' || (select x.status from public.inv_transfer x where x.id = p_tf)
    || ' lines=' || pg_temp.lines(p_tf)
    || ' diffs=' || coalesce((select string_agg(d.kind || ':' || trim_scale(d.expected_qty) || '/' || trim_scale(d.received_qty), ',' order by d.transfer_line_id, d.kind) from public.po_receipt_diff d where d.transfer_id = p_tf), '-')
    || ' ledger=' || (select string_agg(e.sku || '|' || e.warehouse || '|' || e.bin || '|' || trim_scale(e.qty_delta) || '|' || e.event_type || '|' || e.seq_hint, ',' order by e.seq_hint, e.sku, e.warehouse, e.bin, e.qty_delta)
                      from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = (select x.transfer_number from public.inv_transfer x where x.id = p_tf))
    || ' layers=' || (select count(*) || '/' || trim_scale(coalesce(sum(y.qty), 0)) from public.inv_layer y where y.origin_type = 'transfer' and y.doc_number = (select x.transfer_number from public.inv_transfer x where x.id = p_tf))
    || ' detail=' || (select string_agg((l - array['is_combo', 'components', 'combo_line_id', 'combo_qty', 'combo_sku'])::text, ',') from jsonb_array_elements(public.inv_transfer_detail(p_tf) -> 'lines') l))
$$;
-- 보통 문서 한 바퀴(회귀 R0 · R1 에 같은 손): 줄 1 TFC-1 4 픽 4 · 줄 2 TFC-2 2 픽 1 → handoff → finalize(출발) → 받기(1 줄 4 · 2 줄 1) → 요약
create function pg_temp.round_plain(p_tag text) returns text language plpgsql as $$
declare v_x uuid; v_rid uuid; v_h jsonb; v_fin jsonb;
begin
  v_x := pg_temp.mk_tf(p_tag);
  perform pg_temp.mk_line(v_x, 1, current_setting('tfc.p1')::uuid, 'TFC-1', 4, null, 4, null);
  perform pg_temp.mk_line(v_x, 2, current_setting('tfc.p2')::uuid, 'TFC-2', 2, null, 1, null);
  perform pg_temp.as_user(current_setting('tfc.ua'));
  v_h := public.wms_so_handoff(v_x);
  v_fin := public.wms_finalize(array[v_x]);
  perform pg_temp.as_user(current_setting('tfc.uw'));
  v_rid := (public.wms_recv_start(v_x) ->> 'id')::uuid;
  perform public.wms_recv_scan(v_rid, pg_temp.line(v_x, 1), 4);
  perform public.wms_recv_scan(v_rid, pg_temp.line(v_x, 2), 1);
  perform pg_temp.putaway_all(v_rid);
  perform public.wms_recv_complete(v_rid);
  perform pg_temp.as_user(current_setting('tfc.ua'));
  return pg_temp.summary(v_x, v_h, v_fin);
end $$;
select set_config('tfc.ua', :'ua', true), set_config('tfc.uw', :'uw', true) \gset

\if :{?mig}
-- ── R0 회귀 기준 — 옛 함수로 보통 문서 한 바퀴 → 글로 잡아 두고 savepoint 로 되감는다(같은 번호 TFC-T0 을 새 함수로 다시 돈다) ──
savepoint r0;
select pg_temp.round_plain('0') as r0 \gset
rollback to savepoint r0;
\echo '── R0(옛 함수):' :r0
\echo '── 시험 적용(rollback 됨): 1a' :mig1a '→ 1b' :mig
\i :mig1a
\i :mig
\endif
select pg_temp.as_user(:'ua');

-- ── F 꼴 ──
select pg_temp.chk('F1 eight reissued functions: acl · definer · volatility unchanged',
  (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef || p.provolatile::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('wms_so_handoff', 'tf_depart', 'po_receipt_work_save_by', 'tf_receipt_detail', 'tf_arrive', 'tf_settle', 'tf_over_decide', 'inv_transfer_detail')), :'fn_acl_0');
select pg_temp.chk('F2 untouched twelve (wms_finalize · posters · recv shells · freight · so_finalize · so_ship · stk_availability · pur_stock) md5 same',
  (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('wms_finalize', 'inv_post_transfer_depart', 'inv_post_transfer_arrive', 'wms_recv_scan', 'wms_recv_count', 'wms_recv_putaway', 'wms_recv_complete', 'tf_freight_post', 'so_finalize', 'so_ship', 'stk_availability', 'pur_stock')), :'un_md5_0');
\if :{?mig}
select pg_temp.chk('M1 eight functions changed vs baseline md5 (시험 갈래만)',
  ((select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('wms_so_handoff', 'tf_depart', 'po_receipt_work_save_by', 'tf_receipt_detail', 'tf_arrive', 'tf_settle', 'tf_over_decide', 'inv_transfer_detail')) <> :'fn_md5_0')::text, 'true');
\endif
select pg_temp.chk('S1 static: wms_so_handoff trims only in the transfer branch · tf_depart excludes combo lines from qty_sent · over_decide · settle refuse combos',
  (select (p.prosrc like '%if v_doc.doc_kind = ''transfer'' then%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_so_handoff')
  || '|' || (select (p.prosrc like '%k.combo_line_id = l2.id%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'tf_depart')
  || '|' || (select (p.prosrc like '%an over-receipt cannot be decided on a combo%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'tf_over_decide')
  || '|' || (select (p.prosrc like '%settle its component lines instead%')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'tf_settle'), 'true|true|true|true');

-- ── R1 회귀 — 보통 문서(TFC-T0)를 새 함수로 · 새 열쇠를 뺀 나머지는 옛 함수와 같은 글 ──
select pg_temp.round_plain('0') as r1 \gset
\if :{?mig}
select pg_temp.chk('R1 plain transfer round (handoff · departed · lines · diffs · ledger · layers · detail): identical to old functions once the new keys are removed', :'r1', :'r0');
\endif
select pg_temp.chk('R2 plain transfer: handoff put_back [] · combos [] · departed put_back [] · put_back_recorded false · received 4/4 · 2/1',
  (select (h -> 'put_back')::text || '|' || (h -> 'combos')::text from public.wms_so_handoff((select id from public.inv_transfer where transfer_number = 'TFC-T0')) h)
  || '|' || (select (j -> 'lines' -> 0 ->> 'is_combo') from public.inv_transfer_detail((select id from public.inv_transfer where transfer_number = 'TFC-T0')) j)
  || '|' || pg_temp.lines((select id from public.inv_transfer where transfer_number = 'TFC-T0')), '[]|[]|false|1:TFC-1:4/4,2:TFC-2:1/1');
\echo '── R1(새 함수):' :r1
select pg_temp.as_user(:'ua');

-- ── H 인계 · 출발(판정 953 ② · 955) — TFC-T1 ──
select pg_temp.mk_combo_tf('1')::text as t1 \gset
select public.wms_so_handoff(:'t1'::uuid) as h1 \gset
select pg_temp.chk('H1 handoff: whole combos = min(⌊12/6⌋, ⌊12/6⌋, ⌊9/6⌋, ⌊12/6⌋) = 1 → component picks cut to 6 each (TFC-1 from the last bin first: 4 then 2) · ordinary line keeps 3',
  (select string_agg((select l.line_no from public.inv_transfer_line l where l.id = (p ->> 'line_id')::uuid) || ':' || (p ->> 'bin') || ':' || (p ->> 'qty'), ',' order by (select l.line_no from public.inv_transfer_line l where l.id = (p ->> 'line_id')::uuid), p ->> 'bin') from jsonb_array_elements(:'h1'::jsonb -> 'picks') p),
  '2:' || :'bin1name' || ':6,3:' || :'bin1name' || ':6,4:' || :'bin1name' || ':6,5:' || :'bin1name' || ':6,6:' || :'bin1name' || ':3');
select pg_temp.chk('H2 handoff put_back: TFC-1 4 (2nd bin) + 2 (1st bin) · TFC-2 6 · TFC-3 3 · TFC-4 6 — 21 EA · all tagged combo TFC-C line 1',
  (select string_agg((p ->> 'sku') || ':' || (p ->> 'bin') || ':' || (p ->> 'qty') || ':' || (p ->> 'combo_sku') || (p ->> 'combo_line_no'), ',' order by (p ->> 'line_no')::int, (p ->> 'qty')::numeric) || '|' || sum((p ->> 'qty')::numeric) from jsonb_array_elements(:'h1'::jsonb -> 'put_back') p),
  'TFC-1:' || :'bin1name' || ':2:TFC-C1,TFC-1:' || :'bin1bname' || ':4:TFC-C1,TFC-2:' || :'bin1name' || ':6:TFC-C1,TFC-3:' || :'bin1name' || ':3:TFC-C1,TFC-4:' || :'bin1name' || ':6:TFC-C1|21');
select pg_temp.chk('H3 handoff combos [{TFC-C target 2 ship 1 short 1}] · shorts: four components 6/12 with combo_sku + ordinary 3/5 · sorted by line_no',
  (:'h1'::jsonb -> 'combos')::text || '|' || (select string_agg((s ->> 'line_no') || ':' || (s ->> 'sku') || ':' || (s ->> 'ship') || '/' || (s ->> 'target') || ':' || coalesce(s ->> 'combo_sku', '-'), ',') from jsonb_array_elements(:'h1'::jsonb -> 'shorts') s),
  '[{"sku": "TFC-C", "ship": 1, "short": 1, "target": 2, "line_id": "' || pg_temp.line(:'t1'::uuid, 1) || '", "line_no": 1}]|2:TFC-1:6/12:TFC-C,3:TFC-2:6/12:TFC-C,4:TFC-3:6/12:TFC-C,5:TFC-4:6/12:TFC-C,6:TFC-1:3/5:-');
-- 팔렛 상호작용(이견 1 (가)): 뽑은 그대로(반쪽 포함) 팔렛에 실으면 Finalize 가 막는다 → 되돌릴 몫을 내리면 선다
select pg_temp.mk_unit(:'t1'::uuid, 'P1')::text as u1 \gset
select pg_temp.mk_item(:'u1'::bigint, :'t1'::uuid, 2, 12), pg_temp.mk_item(:'u1'::bigint, :'t1'::uuid, 3, 12), pg_temp.mk_item(:'u1'::bigint, :'t1'::uuid, 4, 9), pg_temp.mk_item(:'u1'::bigint, :'t1'::uuid, 5, 12), pg_temp.mk_item(:'u1'::bigint, :'t1'::uuid, 6, 3);
select pg_temp.chkerr('H4 finalize with the half combo still on the pallet: refused (pallets ≠ what is being sent)',
  format('select public.wms_finalize(array[%L::uuid])::text', :'t1'), 'Transfer TFC-T1 — the pallets do not match what is being sent (line 2 (TFC-1): 12 on pallets · 6 to send; line 3 (TFC-2): 12 on pallets · 6 to send; line 4 (TFC-3): 9 on pallets · 6 to send; line 5 (TFC-4): 12 on pallets · 6 to send)');
update public.wms_pallet_items set qty_base = 6 where pallet_id = :'u1'::bigint and transfer_line_id in (pg_temp.line(:'t1'::uuid, 2), pg_temp.line(:'t1'::uuid, 3), pg_temp.line(:'t1'::uuid, 4), pg_temp.line(:'t1'::uuid, 5));   -- 되돌릴 몫을 팔렛에서 내렸다
select public.wms_finalize(array[:'t1'::uuid]) as fin1 \gset
select pg_temp.chk('F3 finalize: departed · combo line qty_sent stays null · components 6 · ordinary 3 · lines carry combo true/sent 1/short 1 · components combo_sku · put_back 5 · recorded',
  (:'fin1'::jsonb -> 'finalized' -> 0 -> 'departed' ->> 'status') || '|' || pg_temp.lines(:'t1'::uuid)
  || '|' || (select string_agg((l ->> 'line_no') || ':' || (l ->> 'combo') || ':' || (l ->> 'sent') || ':' || (l ->> 'short') || ':' || coalesce(l ->> 'combo_sku', '-'), ',' order by (l ->> 'line_no')::int) from jsonb_array_elements(:'fin1'::jsonb -> 'finalized' -> 0 -> 'departed' -> 'lines') l)
  || '|' || jsonb_array_length(:'fin1'::jsonb -> 'finalized' -> 0 -> 'departed' -> 'put_back') || '|' || (:'fin1'::jsonb -> 'finalized' -> 0 -> 'departed' ->> 'put_back_recorded')
  || '|' || (select jsonb_array_length(f.put_back) from public.wms_order_finalize f where f.transfer_id = :'t1'::uuid),
  'in_transit|1:TFC-C:-/-,2:TFC-1:6/-,3:TFC-2:6/-,4:TFC-3:6/-,5:TFC-4:6/-,6:TFC-1:3/-|1:true:1:1:-,2:false:6:6:TFC-C,3:false:6:6:TFC-C,4:false:6:6:TFC-C,5:false:6:6:TFC-C,6:false:3:2:-|5|true|5');
select pg_temp.chk('F4 ledger: no TFC-C row · transfer_out 27 EA (24 components + 3) · IN_TRANSIT per component line 6 · ordinary 3 · layers consumed 27 · finalize shorts = handoff shorts',
  (select count(*) from public.inv_ledger e where e.doc_number = 'TFC-T1' and e.sku = 'TFC-C') || '|' || (select trim_scale(-sum(e.qty_delta)) from public.inv_ledger e where e.doc_number = 'TFC-T1' and e.event_type = 'transfer_out')
  || '|' || (select string_agg(e.sku || ':' || trim_scale(e.qty_delta), ',' order by e.line_ref) from public.inv_ledger e where e.doc_number = 'TFC-T1' and e.warehouse = 'IN_TRANSIT')
  || '|' || (select trim_scale(coalesce(sum(c.qty), 0)) from public.inv_layer_consume c join public.inv_layer y on y.id = c.layer_id where y.doc_number = 'TFC-PO' and c.doc_number = 'TFC-T1')
  || '|' || ((:'fin1'::jsonb -> 'finalized' -> 0 -> 'shorts') = (:'h1'::jsonb -> 'shorts'))::text,
  '0|27|' || (select string_agg(s, ',' order by o) from (select pg_temp.line(:'t1'::uuid, n)::text as o, case when n = 6 then 'TFC-1:3' else 'TFC-' || (n - 1) || ':6' end as s from generate_series(2, 6) n) v) || '|27|true');
select pg_temp.chk('F5 stk_availability (Edmonton · in transit): TFC-1 9 (6 + 3) · TFC-C no phantom row (combo line qty_sent not stored)',
  (select coalesce(string_agg(a.sku || ':' || trim_scale(a.in_transit), ',' order by a.sku) filter (where a.sku = 'TFC-1'), '-') || '|' || count(*) filter (where a.sku = 'TFC-C' and a.in_transit <> 0) from public.stk_availability(:'wh2'::uuid, 'TFC-', null, null, true, 100, 0, false, null) a), 'TFC-1:9|0');
select public.inv_transfer_detail(:'t1'::uuid) as d1 \gset
select pg_temp.chk('D1 inv_transfer_detail after departure: combo line is_combo · components 4 · qty_sent 1 · short_sent 1 · qty_lost/returned/extra null · carried null · component combo_sku · ordinary plain',
  (select string_agg((l ->> 'line_no') || ':' || (l ->> 'is_combo') || ':' || (l ->> 'components') || ':' || coalesce(l ->> 'qty_sent', '-') || ':' || coalesce(l ->> 'short_sent', '-') || ':' || coalesce(l ->> 'qty_lost', 'null') || ':' || coalesce((l -> 'carried')::text, 'null') || ':' || coalesce(l ->> 'combo_sku', '-'), ',' order by (l ->> 'line_no')::int)
     from jsonb_array_elements(:'d1'::jsonb -> 'lines') l),
  '1:true:4:1:1:null:null:-,2:false:0:6:6:0:{"total": 0, "arrived": 0, "returned": 0, "in_transit": 0}:TFC-C,3:false:0:6:6:0:{"total": 0, "arrived": 0, "returned": 0, "in_transit": 0}:TFC-C,4:false:0:6:6:0:{"total": 0, "arrived": 0, "returned": 0, "in_transit": 0}:TFC-C,5:false:0:6:6:0:{"total": 0, "arrived": 0, "returned": 0, "in_transit": 0}:TFC-C,6:false:0:3:2:0:{"total": 0, "arrived": 0, "returned": 0, "in_transit": 0}:-');

-- ── C 받기(판정 954 · 957) — 에드먼턴 직원 ──
select pg_temp.as_user(:'uw');
-- 팔렛 P1 로 받는다(H4 재료 · 팔렛 몫 = 보낸 수량과 같다)
select (public.wms_recv_start(:'t1'::uuid, :'u1'::bigint) ->> 'id') as r1 \gset
select public.tf_receipt_detail(:'r1'::uuid) as rd1 \gset
select pg_temp.chk('C1 tf_receipt_detail: 5 lines (no combo line) · components carry combo_sku TFC-C · combo_qty 6 · combo_barcodes [TFC-BOX-1] · ordinary [] · expected_ea = sent',
  (select string_agg((l ->> 'line_no') || ':' || (l ->> 'sku') || ':' || coalesce(l ->> 'combo_sku', '-') || ':' || coalesce(l ->> 'combo_qty', '-') || ':' || (l -> 'combo_barcodes')::text || ':' || (l ->> 'expected_ea'), ',' order by (l ->> 'line_no')::int) from jsonb_array_elements(:'rd1'::jsonb -> 'lines') l),
  '2:TFC-1:TFC-C:6:["TFC-BOX-1"]:6,3:TFC-2:TFC-C:6:["TFC-BOX-1"]:6,4:TFC-3:TFC-C:6:["TFC-BOX-1"]:6,5:TFC-4:TFC-C:6:["TFC-BOX-1"]:6,6:TFC-1:-:-:[]:3');
select pg_temp.chk('C2 tf_receipt_detail combos: [{TFC-C qty 2 · qty_sent 1 · qty_received null · components 4 · barcodes [TFC-BOX-1]}]',
  (select string_agg((c ->> 'sku') || ':' || (c ->> 'qty') || ':' || (c ->> 'qty_sent') || ':' || coalesce(c ->> 'qty_received', 'null') || ':' || (c ->> 'components') || ':' || (c -> 'barcodes')::text, ',') from jsonb_array_elements(:'rd1'::jsonb -> 'combos') c), 'TFC-C:2:1:null:4:["TFC-BOX-1"]');
select pg_temp.chkerr('C3 scan on the combo line id (pallet receipt): refused — the pallet check speaks first (the combo line is on no pallet) · the combo refusal itself is C5 · C6 on T2',
  format('select public.wms_recv_scan(%L, %L, 6)::text', :'r1', pg_temp.line(:'t1'::uuid, 1)), 'TFC-C is not on pallet TFC-T1-P1');
select public.wms_recv_scan(:'r1'::uuid, pg_temp.line(:'t1'::uuid, 2), 6), public.wms_recv_scan(:'r1'::uuid, pg_temp.line(:'t1'::uuid, 3), 6), public.wms_recv_scan(:'r1'::uuid, pg_temp.line(:'t1'::uuid, 4), 6),
       public.wms_recv_scan(:'r1'::uuid, pg_temp.line(:'t1'::uuid, 5), 5), public.wms_recv_scan(:'r1'::uuid, pg_temp.line(:'t1'::uuid, 6), 3);   -- 구성품 넷(TFC-4 는 1 모자람) + 보통 3
select pg_temp.putaway_all(:'r1'::uuid) as pa1 \gset
select public.wms_recv_complete(:'r1'::uuid) as cp1 \gset
select pg_temp.chk('A1 complete: received · 5 lines arrived · one short diff (TFC-4 6/5) · combo line untouched (qty_received null) · in_transit 1 · no diff on the combo line',
  (:'cp1'::jsonb -> 'arrived' ->> 'status') || '|' || jsonb_array_length(:'cp1'::jsonb -> 'arrived' -> 'lines') || '|' || pg_temp.lines(:'t1'::uuid)
  || '|' || (select string_agg(d.kind || ':' || trim_scale(d.expected_qty) || '/' || trim_scale(d.received_qty) || ':' || (select l.line_no from public.inv_transfer_line l where l.id = d.transfer_line_id), ',') from public.po_receipt_diff d where d.transfer_id = :'t1'::uuid)
  || '|' || trim_scale(public.tf_in_transit_ea(:'t1'::uuid)),
  'received|5|1:TFC-C:-/-,2:TFC-1:6/6,3:TFC-2:6/6,4:TFC-3:6/6,5:TFC-4:6/5,6:TFC-1:3/3|short:6/5:5|1');
select pg_temp.chk('A2 Edmonton ledger: components + ordinary only · no TFC-C · 26 EA',
  (select count(*) || '|' || trim_scale(sum(e.qty_delta)) from public.inv_ledger e where e.doc_number = 'TFC-T1' and e.warehouse = :'wh2name') || '|' || (select count(*) from public.inv_ledger e where e.doc_number = 'TFC-T1' and e.sku = 'TFC-C'), '5|26|0');
select pg_temp.as_user(:'ua');
select pg_temp.chk('A3 tf_receipt_detail combos after arrival: qty_received = min ⌊received ÷ 6⌋ = 0 (TFC-4 5 < 6) · inv_transfer_detail combo line qty_received 0',
  (select (c ->> 'qty_sent') || '/' || (c ->> 'qty_received') from jsonb_array_elements(public.tf_receipt_detail(:'r1'::uuid) -> 'combos') c) || '|' || (select (l ->> 'qty_sent') || '/' || (l ->> 'qty_received') from jsonb_array_elements(public.inv_transfer_detail(:'t1'::uuid) -> 'lines') l where (l ->> 'line_no')::int = 1), '1/0|1/0');
-- 정산(판정 957) · 안전띠
select pg_temp.as_user(:'ua');
select pg_temp.chkerr('S2 settle on the combo line: refused', format('select public.tf_settle(%L, jsonb_build_array(jsonb_build_object(''line_id'', %L, ''action'', ''lost'', ''qty'', 1)))::text', :'t1', pg_temp.line(:'t1'::uuid, 1)),
  'Line 1 of transfer TFC-T1 is a combo line (TFC-C) — settle its component lines instead — nothing was saved');
select pg_temp.chk('S3 settle TFC-4 lost 1 on its component line: ok · diff closed · in_transit 0 · poster tf_settle@2026-11-02.1',
  (select (j ->> 'diffs_closed') || '|' || (j ->> 'in_transit_ea') || '|' || (j ->> 'poster') from public.tf_settle(:'t1'::uuid, jsonb_build_array(jsonb_build_object('line_id', pg_temp.line(:'t1'::uuid, 5), 'action', 'lost', 'qty', 1))) j), '1|0|tf_settle@2026-11-02.1');
set local session_replication_role = replica;
insert into public.po_receipt_diff (receipt_id, transfer_id, transfer_line_id, product_id, kind, expected_qty, received_qty, note) values (:'r1'::uuid, :'t1'::uuid, pg_temp.line(:'t1'::uuid, 1), :'pc'::uuid, 'over', 0, 1, 'fake over on a combo line (belt test)') returning id::text as dx \gset
set local session_replication_role = origin;
select pg_temp.chkerr('O1 tf_over_decide(found) on a fake over diff of the combo line: refused (belt)', format('select public.tf_over_decide(%L, ''found'')::text', :'dx'),
  'Transfer TFC-T1 line 1 (TFC-C) is a combo line — an over-receipt cannot be decided on a combo; its component lines carry the stock — nothing was saved');
select pg_temp.chkerr('O2 tf_over_decide(sent_more) on it: refused the same way', format('select public.tf_over_decide(%L, ''sent_more'')::text', :'dx'),
  'Transfer TFC-T1 line 1 (TFC-C) is a combo line — an over-receipt cannot be decided on a combo; its component lines carry the stock — nothing was saved');
select pg_temp.chk('D2 inv_transfer_detail after settle: combo line qty_lost null · TFC-4 line qty_lost 1 · combo qty_received 0',
  (select string_agg((l ->> 'line_no') || ':' || coalesce(trim_scale((l ->> 'qty_lost')::numeric)::text, 'null') || ':' || coalesce(trim_scale((l ->> 'qty_received')::numeric)::text, 'null'), ',' order by (l ->> 'line_no')::int) from jsonb_array_elements(public.inv_transfer_detail(:'t1'::uuid) -> 'lines') l where (l ->> 'line_no')::int in (1, 5)), '1:null:0,5:1:5');

-- ── W 통째 콤보가 다 있으면 자르지 않는다 · 콤보 없는 보통 줄만 짧아도 판정 74 그대로 — TFC-T2 ──
select pg_temp.mk_tf('2')::text as t2 \gset
select pg_temp.mk_line(:'t2'::uuid, 1, :'pc'::uuid, 'TFC-C', 1, null, null, null)::text as c2 \gset
select pg_temp.mk_line(:'t2'::uuid, 2, :'p1'::uuid, 'TFC-1', 6, :'c2'::uuid, 6, null), pg_temp.mk_line(:'t2'::uuid, 3, :'p2'::uuid, 'TFC-2', 6, :'c2'::uuid, 6, null), pg_temp.mk_line(:'t2'::uuid, 4, :'p3'::uuid, 'TFC-3', 6, :'c2'::uuid, 6, null), pg_temp.mk_line(:'t2'::uuid, 5, :'p4'::uuid, 'TFC-4', 6, :'c2'::uuid, 6, null);
select pg_temp.mk_line(:'t2'::uuid, 6, :'p2'::uuid, 'TFC-2', 4, null, 1, null);
select pg_temp.chk('W1 full combo picked: put_back [] · combos ship 1 · shorts only the ordinary line 1/4 (판정 74)',
  (select (h -> 'put_back')::text || '|' || (h -> 'combos' -> 0 ->> 'ship') || '|' || (select string_agg((s ->> 'line_no') || ':' || (s ->> 'ship') || '/' || (s ->> 'target'), ',') from jsonb_array_elements(h -> 'shorts') s) from public.wms_so_handoff(:'t2'::uuid) h), '[]|1|6:1/4');
select public.wms_finalize(array[:'t2'::uuid]) as fin2 \gset
select pg_temp.chk('W2 finalize T2: sent 6 each · ordinary 1 · put_back [] · put_back_recorded false · wms_order_finalize.put_back null',
  (:'fin2'::jsonb -> 'finalized' -> 0 -> 'departed' -> 'put_back')::text || '|' || (:'fin2'::jsonb -> 'finalized' -> 0 -> 'departed' ->> 'put_back_recorded') || '|' || pg_temp.lines(:'t2'::uuid) || '|' || (select coalesce(f.put_back::text, 'null') from public.wms_order_finalize f where f.transfer_id = :'t2'::uuid),
  '[]|false|1:TFC-C:-/-,2:TFC-1:6/-,3:TFC-2:6/-,4:TFC-3:6/-,5:TFC-4:6/-,6:TFC-2:1/-|null');
-- 문서 단위 받기(팔렛 없음)에서 콤보 줄 id 로 세기 거부(판정 954 · 이견 3 — po_receipt_work_save_by 한 곳)
select pg_temp.as_user(:'uw');
select (public.wms_recv_start(:'t2'::uuid) ->> 'id') as r2 \gset
select pg_temp.chkerr('C5 scan on the combo line id (doc-level receipt): refused by po_receipt_work_save_by', format('select public.wms_recv_scan(%L, %L, 6)::text', :'r2', pg_temp.line(:'t2'::uuid, 1)), 'Line 1 (TFC-C) is a combo line — count its component lines (for TFC-C) instead — nothing was saved');
select pg_temp.chkerr('C6 count on the combo line id: refused too', format('select public.wms_recv_count(%L, %L, 6, null)::text', :'r2', pg_temp.line(:'t2'::uuid, 1)), 'Line 1 (TFC-C) is a combo line — count its component lines (for TFC-C) instead — nothing was saved');
select pg_temp.chk('C7 component scan on T2 works · detail lines 5 · combos TFC-C qty_sent 1',
  (select j ->> 'counted' from public.wms_recv_scan(:'r2'::uuid, pg_temp.line(:'t2'::uuid, 2), 6) j) || '|' || (select jsonb_array_length(d -> 'lines') || '|' || (d -> 'combos' -> 0 ->> 'qty_sent') from public.tf_receipt_detail(:'r2'::uuid) d), '6|5|1');
select pg_temp.as_user(:'ua');

-- ── 화면이 쓸 창구 꼴(보고용 출력 · 검사 아님) ──
\echo '── 창구 꼴: wms_so_handoff(T1).put_back →' :h1
select (:'fin1'::jsonb -> 'finalized' -> 0 -> 'departed')::text as dep1 \gset
\echo '── 창구 꼴: wms_finalize(T1).finalized[0].departed →' :dep1
select (:'d1'::jsonb -> 'lines' -> 0)::text as d1c, (:'d1'::jsonb -> 'lines' -> 1)::text as d1k \gset
\echo '── 창구 꼴: inv_transfer_detail(T1).lines[0](콤보 줄) →' :d1c
\echo '── 창구 꼴: inv_transfer_detail(T1).lines[1](구성품 줄) →' :d1k
select (:'rd1'::jsonb -> 'lines' -> 0)::text as rd1k, (:'rd1'::jsonb -> 'combos')::text as rd1c \gset
\echo '── 창구 꼴: tf_receipt_detail(R1).lines[0](구성품 줄) →' :rd1k
\echo '── 창구 꼴: tf_receipt_detail(R1).combos →' :rd1c

select pg_temp.chk('X1 fake rows present (rolled back below): 3 TFC transfers · 5 products · 2 staff', (select count(*) from public.inv_transfer where transfer_number like 'TFC-T%') || '/' || (select count(*) from public.product where sku like 'TFC-%') || '/' || (select count(*) from public.ims_staff where email like 'tfc-%'), '3/5/2');
\echo '── 결과(OK · MISMATCH) ──'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' | want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
\echo '── OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
select (clock_timestamp() - :'t_begin'::timestamptz)::text as in_tx \gset
\echo '── begin ~ rollback:' :in_tx
rollback;
-- ── 뒤: 실제 행 무변 ──
select (select count(*) from public.inv_transfer) = :n_tf and (select count(*) from public.inv_transfer_line) = :n_tfl and (select count(*) from public.po_receipt) = :n_rc
   and (select count(*) from public.wms_pallets) = :n_pal and (select count(*) from public.inv_ledger) = :n_led and (select count(*) from public.inv_layer) = :n_lay and (select count(*) from public.ims_staff) = :n_staff
   and (select count(*) from public.product where sku like 'TFC-%') + (select count(*) from public.inv_transfer where transfer_number like 'TFC-%') = :n_fake0 as rows_unchanged_after_rollback \gset
\echo '── rollback 뒤 실제 행 무변:' :rows_unchanged_after_rollback
select case when :n_bad = 0 and :n_ok = :EXPECT_OK and :'rows_unchanged_after_rollback' = 't' then 'PASS' else 'FAIL' end as verdict;
