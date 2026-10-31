-- supabase/tests/tf_pallet_1_check.sql — tf-pallet-1(판정 897 · 898) 트랜스퍼 팔렛 단위 받기 · 운송 정보 셋 검증 (2026-10-31)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4 · wsp_1_check 와 같은 꼴) — 기준(begin 앞) → begin → (-v mig 면: 회귀 R0 를 옛 함수로 돌려 잡아 두고 savepoint 로 되감은 뒤 \i) → 꼴 · 기능 · 회귀 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261031210000_tf_pallet_1_receive_by_pallet.sql -f supabase/tests/tf_pallet_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — R0 · M1 둘(옛 함수가 있어야 성립)은 확인 갈래에 없다 ⇒ 확인 OK 수 = 시험 OK 수 − 2
--   쓰기 0 — 가짜 재료(TFP-…)는 rollback · transfer_number 는 직접 준다 · ⚠️ po_receipt_number_seq · identity(wms_pallets · wms_pick_tasks …)는 당긴다(틈만)
--   ⚠️ 테스트 DB = 운영 — 잠그는 것은 가짜 행뿐(inv_transfer · po_receipt · wms_pallets … 의 TFP 행) · 원장 · 레이어 표는 가짜 SKU 행을 넣고 읽을 뿐 오래 잡지 않는다(statement_timeout 120s · lock_timeout 3s)
\set ON_ERROR_STOP on
\pset pager off
\if :{?mig}
\set EXPECT_OK 70
\else
\set EXPECT_OK 68
\endif
-- ── 기준(begin 앞 · 잠금 없음) ──
select (select count(*) from public.inv_transfer) as n_tf, (select count(*) from public.inv_transfer_line) as n_tfl, (select count(*) from public.po_receipt) as n_rc,
       (select count(*) from public.wms_pallets) as n_pal, (select count(*) from public.wms_pallet_items) as n_pit, (select count(*) from public.inv_ledger) as n_led, (select count(*) from public.inv_layer) as n_lay,
       (select count(*) from public.ims_staff) as n_staff, (select count(*) from public.ref_carrier) as n_car, (select count(*) from public.po_charge) as n_chg,
       (select count(*) from public.inv_transfer where transfer_number like 'TFP-%') + (select count(*) from public.product where sku like 'TFP-%') as n_fake0,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('wms_recv_start', 'tf_receipt_detail', 'wms_recv_scan', 'wms_recv_count', 'tf_arrive', 'wms_finalize', 'tf_settle')) as fn_md5_0,
       (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('tf_receipt_detail', 'wms_recv_scan', 'wms_recv_count', 'tf_arrive', 'wms_finalize', 'tf_settle')) as fn_acl_0,
       (select coalesce(p.proacl::text, '-') || '/' || p.prosecdef from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_recv_start') as start_acl_0,
       (select string_agg(x.transfer_number || ':' || x.status, ' ' order by x.transfer_number) from public.inv_transfer x where x.transfer_number like 'TR-0639%') as tr_real_0
\gset
\echo '── 기준: transfer' :n_tf '· receipt' :n_rc '· pallets' :n_pal '· items' :n_pit '· ledger' :n_led '· layers' :n_lay '· staff' :n_staff '· carriers' :n_car '· charges' :n_chg '· fake' :n_fake0
\echo '── fn md5(전):' :fn_md5_0
\echo '── 실제 TR:' :tr_real_0

begin;
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
-- 예외가 나도 되감지 않고 글만 — 서브트랜잭션(run 은 블록 안 예외라 저절로 되감긴다)
create function pg_temp.err(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  return 'NOERR';
exception when others then
  return left(sqlerrm, 70);
end $$;
-- 예외 글이 p_prefix 로 시작하면 'starts: <prefix>' · 아니면 'got: <전체 글>'(실패 때 전문이 보인다) · 예외 없으면 NOERR
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
create function pg_temp.src(p_name text) returns text language sql as $$
  select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_name
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

-- ── 재료(replica · 가짜 번호): 창고 둘(토론토 → 에드먼턴) · 직원 넷 · 제품 둘 · 출발 창고 레이어(원가 10) · 운송사 둘 · 공급처 하나(기존 id · 비용 FK 용) ──
select id::text as wh1, name as wh1name from public.ref_warehouse where name = 'Asung Trading Inc.' \gset
select id::text as wh2, name as wh2name from public.ref_warehouse where name = 'Asung - Edmonton' \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select b.id::text as bin1, b.name as bin1name from public.ref_bin b where b.warehouse_id = :'wh1'::uuid and b.is_active and b.name <> '' order by b.name limit 1 \gset
select b.id::text as bin2, b.name as bin2name from public.ref_bin b where b.warehouse_id = :'wh2'::uuid and b.is_active and b.name <> '' order by b.name limit 1 \gset
select id::text as sup from public.supplier where is_active order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'tfp-a@test.invalid', 'TFP Admin', 'admin', '[]', '{}') returning auth_user_id::text as ua \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'tfp-w@test.invalid', 'TFP Receiver EDM', 'worker', '["wms_receiving"]', array[:'wh2'::uuid]) returning auth_user_id::text as uw \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'tfp-t@test.invalid', 'TFP Office', 'manager', '["transfer"]', '{}') returning auth_user_id::text as ut \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'tfp-n@test.invalid', 'TFP Nobody TOR', 'worker', '["picking"]', array[:'wh1'::uuid]) returning auth_user_id::text as un \gset
insert into public.product (sku, name, source) values ('TFP-1', 'TFP Product 1', 'manual') returning id::text as p1 \gset
insert into public.product (sku, name, source) values ('TFP-2', 'TFP Product 2', 'manual') returning id::text as p2 \gset
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) values
  ('TFP-1', :'wh1name', 'purchase', 'TFP-PO', 'tfp1', public.ims_today() - 30, true, 100, 10, 'inv_cost'),
  ('TFP-2', :'wh1name', 'purchase', 'TFP-PO', 'tfp2', public.ims_today() - 30, true, 100, 20, 'inv_cost');
insert into public.ref_carrier (name, kind, is_active) values ('TFP Carrier', 'carrier', true) returning id::text as car_on \gset
insert into public.ref_carrier (name, kind, is_active) values ('TFP Carrier Off', 'carrier', false) returning id::text as car_off \gset
set local session_replication_role = origin;
select set_config('tfp.wh1', :'wh1', true), set_config('tfp.wh1name', :'wh1name', true), set_config('tfp.wh2', :'wh2', true), set_config('tfp.p1', :'p1', true), set_config('tfp.p2', :'p2', true),
       set_config('tfp.bin1', :'bin1', true), set_config('tfp.bin1name', :'bin1name', true), set_config('tfp.bin2', :'bin2', true), set_config('tfp.cad', :'cad', true), set_config('tfp.sup', :'sup', true) \gset
select s.id::text as sa from public.ims_staff s where s.auth_user_id = :'ua'::uuid \gset
select set_config('tfp.sa', :'sa', true) \gset

-- 트랜스퍼(줄 둘 · pack_factor 1) · 뽑고 팩한 상태(picking · pick 1 배치 완료 · pack 완료 · verified = 요청)
create function pg_temp.mk_tf(p_tag text, p_q1 numeric, p_q2 numeric) returns uuid language plpgsql as $$
declare v_x uuid; v_pt bigint; v_pk bigint; v_l1 uuid; v_l2 uuid; v_ptl bigint; v_sa uuid := current_setting('tfp.sa')::uuid;
begin
  execute 'set local session_replication_role = replica';
  insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, confirmed_at, at_wms_at, picking_at, created_by)
  values ('TFP-T' || p_tag, 'picking', current_setting('tfp.wh1')::uuid, current_setting('tfp.wh2')::uuid, now(), now(), now(), v_sa) returning id into v_x;
  insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (v_x, 1, current_setting('tfp.p1')::uuid, 'TFP-1', p_q1, 1) returning id into v_l1;
  if p_q2 > 0 then insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (v_x, 2, current_setting('tfp.p2')::uuid, 'TFP-2', p_q2, 1) returning id into v_l2; end if;
  insert into public.wms_pick_tasks (transfer_id, batch_label, status, completed_at, completed_by, assigned_to) values (v_x, 'A', 'completed', now(), v_sa, v_sa) returning id into v_pt;
  insert into public.wms_pack_tasks (transfer_id, pick_task_id, batch_label, status, completed_at, completed_by, assigned_to) values (v_x, v_pt, 'A', 'completed', now(), v_sa, v_sa) returning id into v_pk;
  insert into public.wms_pick_task_lines (pick_task_id, transfer_line_id, assigned_base, picked_base, status, picked_at, picked_by) values (v_pt, v_l1, p_q1, p_q1, 'picked', now(), v_sa) returning id into v_ptl;
  insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at) values (v_ptl, current_setting('tfp.bin1')::uuid, current_setting('tfp.bin1name'), p_q1, false, v_sa, now());
  insert into public.wms_pack_task_lines (pack_task_id, transfer_line_id, expected_base, verified_base, status, verified_at, verified_by) values (v_pk, v_l1, p_q1, p_q1, 'verified', now(), v_sa);
  if p_q2 > 0 then
    insert into public.wms_pick_task_lines (pick_task_id, transfer_line_id, assigned_base, picked_base, status, picked_at, picked_by) values (v_pt, v_l2, p_q2, p_q2, 'picked', now(), v_sa) returning id into v_ptl;
    insert into public.wms_pick_line_bins (pick_task_line_id, bin_id, bin, qty_base, planned, picked_by, picked_at) values (v_ptl, current_setting('tfp.bin1')::uuid, current_setting('tfp.bin1name'), p_q2, false, v_sa, now());
    insert into public.wms_pack_task_lines (pack_task_id, transfer_line_id, expected_base, verified_base, status, verified_at, verified_by) values (v_pk, v_l2, p_q2, p_q2, 'verified', now(), v_sa);
  end if;
  execute 'set local session_replication_role = origin';
  return v_x;
end $$;
create function pg_temp.line(p_tf uuid, p_no int) returns uuid language sql as $$ select l.id from public.inv_transfer_line l where l.transfer_id = p_tf and l.line_no = p_no $$;
create function pg_temp.pack_task(p_tf uuid) returns bigint language sql as $$ select k.id from public.wms_pack_tasks k where k.transfer_id = p_tf limit 1 $$;
-- 팔렛 · 박스 · 담긴 것은 화면과 같은 길(표 직접 insert · origin · 트리거 산다)
create function pg_temp.mk_unit(p_tf uuid, p_type text, p_label text, p_parent bigint) returns bigint language sql as $$
  insert into public.wms_pallets (transfer_id, unit_type, label, parent_id, status, created_by) values (p_tf, p_type, p_label, p_parent, 'building', current_setting('tfp.sa')::uuid) returning id
$$;
create function pg_temp.mk_item(p_unit bigint, p_tf uuid, p_no int, p_qty int) returns bigint language sql as $$
  insert into public.wms_pallet_items (pallet_id, transfer_id, transfer_line_id, pack_task_id, qty_base) values (p_unit, p_tf, pg_temp.line(p_tf, p_no), pg_temp.pack_task(p_tf), p_qty) returning id
$$;
-- 받기 한 바퀴의 손: 세고(scan) · 칸에 놓고(putaway · 모든 작업 줄) · Complete
create function pg_temp.putaway_all(p_rid uuid) returns int language plpgsql as $$
declare w record; n int := 0;
begin
  for w in select id from public.po_receipt_work where receipt_id = p_rid and bin_id is null loop
    perform public.wms_recv_putaway(w.id, current_setting('tfp.bin2')::uuid, true); n := n + 1;
  end loop;
  return n;
end $$;
-- 운임: 확정 비용 하나(CAD · freight)를 트랜스퍼에 배분(replica — 오피스 창구 tf_charge_* 대신 · 운임 창구 자체는 시험 대상 아님)
create function pg_temp.mk_charge(p_tf uuid, p_no text, p_amt numeric) returns uuid language plpgsql as $$
declare v_c uuid; v_sa uuid := current_setting('tfp.sa')::uuid;
begin
  execute 'set local session_replication_role = replica';
  insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status, created_by, confirmed_by, confirmed_at)
  values (current_setting('tfp.sup')::uuid, 'TFP-CH' || p_no, public.ims_today(), 'freight', current_setting('tfp.cad')::uuid, p_amt, 'confirmed', v_sa, v_sa, now()) returning id into v_c;
  insert into public.po_charge_alloc (po_charge_id, transfer_id, amount) values (v_c, p_tf, p_amt);
  execute 'set local session_replication_role = origin';
  return v_c;
end $$;
-- 회귀 요약(문서 단위 받기 · 옛 ↔ 새 같은 글): 상태 · 줄 qty · 차이 · 원장(문서) · 도착 반환에서 새 열쇠를 뺀 것
create function pg_temp.summary(p_tf uuid, p_arr jsonb) returns text language sql as $$
  select pg_temp.norm(
    'status=' || (select x.status || '/' || (x.received_at is not null)::text from public.inv_transfer x where x.id = p_tf)
    || ' lines=' || (select string_agg(l.line_no || ':' || trim_scale(l.qty_sent) || '/' || trim_scale(l.qty_received), ',' order by l.line_no) from public.inv_transfer_line l where l.transfer_id = p_tf)
    || ' diffs=' || coalesce((select string_agg(d.kind || ':' || trim_scale(d.expected_qty) || '/' || trim_scale(d.received_qty) || ':' || d.note, ',' order by d.transfer_line_id, d.kind) from public.po_receipt_diff d where d.transfer_id = p_tf), '-')
    || ' receipts=' || (select string_agg(r.status || ':' || coalesce(to_jsonb(r) ->> 'pallet_id', '-'), ',') from public.po_receipt r where r.transfer_id = p_tf)
    || ' ledger=' || (select string_agg(e.sku || '|' || e.warehouse || '|' || e.bin || '|' || trim_scale(e.qty_delta) || '|' || e.event_type || '|' || e.seq_hint || '|' || regexp_replace(e.line_ref, '^[0-9a-f-]{36}', '#'), ',' order by e.seq_hint, e.sku, e.warehouse, e.line_ref)
                      from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = (select x.transfer_number from public.inv_transfer x where x.id = p_tf))
    || ' layers=' || (select count(*) || '/' || trim_scale(coalesce(sum(y.qty), 0)) from public.inv_layer y where y.origin_type = 'transfer' and y.doc_number = (select x.transfer_number from public.inv_transfer x where x.id = p_tf))
    || ' arrived=' || (p_arr - array['final', 'pallet', 'pallet_count', 'pallets_done', 'in_transit_ea', 'ledger', 'receipt_id', 'receipt_number', 'received_by'])::text)
$$;
-- 문서 단위 한 바퀴(회귀 R0 · R1 에 같은 손): 줄 1 = 4 보냄 4 받음 · 줄 2 = 2 보냄 1 받음(short 1) → finalize(출발) → 받기 → 요약
create function pg_temp.round_plain(p_tag text) returns text language plpgsql as $$
declare v_x uuid; v_rid uuid; v_arr jsonb; v_fin jsonb;
begin
  v_x := pg_temp.mk_tf(p_tag, 4, 2);
  perform pg_temp.as_user(current_setting('tfp.ua'));
  v_fin := public.wms_finalize(array[v_x]);
  perform pg_temp.as_user(current_setting('tfp.uw'));
  v_rid := (public.wms_recv_start(v_x) ->> 'id')::uuid;
  perform public.wms_recv_scan(v_rid, pg_temp.line(v_x, 1), 4);
  perform public.wms_recv_scan(v_rid, pg_temp.line(v_x, 2), 1);
  perform pg_temp.putaway_all(v_rid);
  v_arr := public.wms_recv_complete(v_rid) -> 'arrived';
  return pg_temp.summary(v_x, v_arr);
end $$;
select set_config('tfp.ua', :'ua', true), set_config('tfp.uw', :'uw', true), set_config('tfp.ut', :'ut', true), set_config('tfp.un', :'un', true) \gset

\if :{?mig}
-- ── R0 회귀 기준 — 옛 함수로 문서 단위 한 바퀴 → 글로 잡아 두고 savepoint 로 되감는다(같은 번호 TFP-T0 을 새 함수로 다시 돈다) ──
savepoint r0;
select pg_temp.round_plain('0') as r0 \gset
rollback to savepoint r0;
\echo '── R0(옛 함수):' :r0
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select pg_temp.as_user(:'ua');

-- ── F 꼴 ──
select pg_temp.chk('F1 inv_transfer: carrier_id uuid · tracking_number text · eta date',
  (select string_agg(c.column_name || ':' || c.data_type, ' ' order by c.column_name) from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'inv_transfer' and c.column_name in ('carrier_id', 'tracking_number', 'eta')),
  'carrier_id:uuid eta:date tracking_number:text');
select pg_temp.chk('F2 po_receipt.pallet_id bigint → wms_pallets · partial unique (transfer_id, pallet_id) · ck pallet needs transfer',
  (select c.data_type from information_schema.columns c where c.table_schema = 'public' and c.table_name = 'po_receipt' and c.column_name = 'pallet_id')
  || ' | ' || (select pg_get_indexdef(i.indexrelid) from pg_index i where i.indexrelid = to_regclass('public.po_receipt_transfer_pallet_uq'))
  || ' | ' || (select pg_get_constraintdef(oid) from pg_constraint where conname = 'po_receipt_pallet_transfer_ck'),
  'bigint | CREATE UNIQUE INDEX po_receipt_transfer_pallet_uq ON public.po_receipt USING btree (transfer_id, pallet_id) WHERE ((pallet_id IS NOT NULL) AND (status <> ''cancelled''::text)) | CHECK (((pallet_id IS NULL) OR (transfer_id IS NOT NULL)))');
select pg_temp.chk('F3 freeze triggers on wms_pallets · wms_pallet_items (before ins/upd/del · row)',
  (select string_agg(t.tgrelid::regclass::text || ':' || t.tgname || ':' || t.tgtype, ' ' order by t.tgname) from pg_trigger t where t.tgname in ('wms_pallet_freeze', 'wms_pallet_item_freeze')),
  'wms_pallets:wms_pallet_freeze:31 wms_pallet_items:wms_pallet_item_freeze:31');
select pg_temp.chk('F4 wms_recv_start: one definition (uuid, bigint default) · acl · definer as before',
  (select string_agg(pg_get_function_identity_arguments(p.oid) || ' = ' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef, ' ; ') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'wms_recv_start'),
  'p_po_id uuid, p_pallet_id bigint = ' || :'start_acl_0');
select pg_temp.chk('F5 six replaced functions: acl · definer unchanged',
  (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('tf_receipt_detail', 'wms_recv_scan', 'wms_recv_count', 'tf_arrive', 'wms_finalize', 'tf_settle')), :'fn_acl_0');
select pg_temp.chk('F6 new functions: authenticated may call tf_pallets · tf_pallet_lookup · inv_transfer_shipping_set · tf_in_transit_ea · helpers ; not tf_freight_post',
  (select string_agg(p.proname || ':' || (coalesce(p.proacl::text, '') like '%authenticated=X%')::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('tf_pallets', 'tf_pallet_lookup', 'inv_transfer_shipping_set', 'tf_in_transit_ea', 'tf_freight_post', 'wms_pallet_tree', 'wms_pallet_root', 'tf_pallet_info', 'tf_pallet_line_check')),
  'inv_transfer_shipping_set:true tf_freight_post:false tf_in_transit_ea:true tf_pallet_info:true tf_pallet_line_check:true tf_pallet_lookup:true tf_pallets:true wms_pallet_root:true wms_pallet_tree:true');
select pg_temp.chk('F7 inv_transfer_shipping_set is security definer · tf_pallets stable not definer',
  (select string_agg(p.proname || ':' || p.prosecdef::text || p.provolatile::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_transfer_shipping_set', 'tf_pallets', 'tf_pallet_lookup')),
  'inv_transfer_shipping_set:truev tf_pallet_lookup:falses tf_pallets:falses');
\if :{?mig}
select pg_temp.chk('M1 seven functions changed vs baseline md5 (시험 갈래만)',
  ((select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('wms_recv_start', 'tf_receipt_detail', 'wms_recv_scan', 'wms_recv_count', 'tf_arrive', 'wms_finalize', 'tf_settle')) <> :'fn_md5_0')::text, 'true');
\endif
select pg_temp.chk('S1 wms_finalize: pallet checks sit in ① (before ② 기록) · compare to handoff picks',
  (position('the pallets do not match what is being sent' in pg_temp.src('wms_finalize')) between 1 and position('-- ② 기록 + 전이' in pg_temp.src('wms_finalize'))
   and pg_temp.src('wms_finalize') like '%v_h := public.wms_so_handoff(v_id);%')::text, 'true');
select pg_temp.chk('S5 wms_recv_start: PO branch refuses a pallet id (static)', (pg_temp.src('wms_recv_start') like '%is not received by pallet — start without a pallet%')::text, 'true');
select pg_temp.chk('S2 tf_arrive: freight only through tf_freight_post · settle closes with freight',
  ((select count(*) from regexp_matches(pg_temp.src('tf_arrive'), 'inv_layer_post_charge', 'g')) || '/' || (select count(*) from regexp_matches(pg_temp.src('tf_arrive'), 'tf_freight_post', 'g'))
   || '/' || (select count(*) from regexp_matches(pg_temp.src('tf_settle'), 'tf_freight_post', 'g'))), '0/2/1');
select pg_temp.chk('S3 real TR-0639x untouched: status same · shipping columns empty',
  (select string_agg(x.transfer_number || ':' || x.status || ':' || coalesce(x.carrier_id::text, '-') || coalesce(x.tracking_number, '-') || coalesce(x.eta::text, '-'), ' ' order by x.transfer_number) from public.inv_transfer x where x.transfer_number like 'TR-0639%'),
  (select string_agg(t || ':---', ' ') from unnest(string_to_array(:'tr_real_0', ' ')) t));
select pg_temp.chk('S4 tf_pallets on a real pallet-less transfer: 0 pallets · shipping nulls · in_transit > 0',
  (select (j ->> 'pallet_count') || '/' || (j -> 'pallets')::text || '/' || ((j -> 'shipping' ->> 'carrier') is null)::text || '/' || ((j ->> 'in_transit_ea')::numeric > 0)::text
     from public.tf_pallets((select x.id from public.inv_transfer x where x.transfer_number = 'TR-06398')) j), '0/[]/true/true');

-- ── R1 회귀 — 같은 손(TFP-T0 · 문서 단위)을 새 함수로 ──
select pg_temp.round_plain('0') as r1 \gset
\if :{?mig}
select pg_temp.chk('R1 plain (no-pallet) receiving: identical to old functions (status · qty · diffs · ledger · layers · arrived)', :'r1', :'r0');
\endif
select pg_temp.chk('R2 plain receiving: received · line qty 4/4 · 2/1 · one short · in_transit 1 · one receipt without pallet',
  (select x.status || ' ' || (select string_agg(l.line_no || ':' || trim_scale(l.qty_sent) || '/' || trim_scale(l.qty_received), ',' order by l.line_no) from public.inv_transfer_line l where l.transfer_id = x.id)
     || ' short=' || (select count(*) from public.po_receipt_diff d where d.transfer_id = x.id and d.kind = 'short') || ' transit=' || trim_scale(public.tf_in_transit_ea(x.id))
     || ' receipts=' || (select string_agg(r.status || ':' || coalesce(r.pallet_id::text, 'null'), ',') from public.po_receipt r where r.transfer_id = x.id)
   from public.inv_transfer x where x.transfer_number = 'TFP-T0'), 'received 1:4/4,2:2/1 short=1 transit=1 receipts=confirmed:null');
\echo '── R1(새 함수):' :r1
select pg_temp.as_user(:'ua');

-- ── P 팔렛 받기 한 바퀴 — TFP-T1: 줄 1 = 6 · 줄 2 = 3 · P1(줄 1 × 2) + 박스 B1 안의 줄 1 × 1 · P2(줄 1 × 3 · 줄 2 × 3) ──
select pg_temp.mk_tf('1', 6, 3)::text as t1 \gset
select pg_temp.mk_unit(:'t1'::uuid, 'pallet', 'P1', null)::text as p1 \gset
select pg_temp.mk_unit(:'t1'::uuid, 'box', 'B1', :'p1'::bigint)::text as b1 \gset
select pg_temp.mk_unit(:'t1'::uuid, 'pallet', 'P2', null)::text as p2 \gset
select pg_temp.mk_item(:'p1'::bigint, :'t1'::uuid, 1, 2), pg_temp.mk_item(:'b1'::bigint, :'t1'::uuid, 1, 1), pg_temp.mk_item(:'p2'::bigint, :'t1'::uuid, 1, 3);
select pg_temp.chkerr('P1 finalize refused while line 2 is not on any pallet (pallets ≠ sent)',
  format('select public.wms_finalize(array[%L::uuid])::text', :'t1'), 'Transfer TFP-T1 — the pallets do not match what is being sent (line 2 (TFP-2');
select pg_temp.chk('P1a transfer still picking · no finalize row (whole call rolled back)',
  (select x.status || '/' || (select count(*) from public.wms_order_finalize f where f.transfer_id = x.id) from public.inv_transfer x where x.id = :'t1'::uuid), 'picking/0');
select pg_temp.mk_item(:'p2'::bigint, :'t1'::uuid, 2, 3) as last_item \gset
-- 섞임: 다른 트랜스퍼(TFP-T4)의 줄을 T1 의 P2 에
select pg_temp.mk_tf('4', 2, 0)::text as t4 \gset
select pg_temp.mk_item(:'p2'::bigint, :'t4'::uuid, 1, 1)::text as mixed_item \gset
select pg_temp.chkerr('P2 finalize T1 refused: its pallet carries goods of TFP-T4',
  format('select public.wms_finalize(array[%L::uuid])::text', :'t1'), 'Transfer TFP-T1 — its pallets also carry goods of another document (TFP-T4)');
select pg_temp.chkerr('P2a finalize T4 (no pallets of its own) refused: its line is on a pallet of another document',
  format('select public.wms_finalize(array[%L::uuid])::text', :'t4'), 'Transfer TFP-T4 — on a pallet of another document: line 1 (TFP-1) — one transfer per pallet');
delete from public.wms_pallet_items where id = :'mixed_item'::bigint;
select pg_temp.chk('P2b T4 (no pallets of its own) finalizes as one lot',
  (select (j -> 'finalized' -> 0 -> 'departed' ->> 'status') from public.wms_finalize(array[:'t4'::uuid]) j), 'in_transit');
select public.wms_finalize(array[:'t1'::uuid]) as fin1 \gset
select pg_temp.chk('P3 finalize T1: departed · qty_sent 6/3 · IN_TRANSIT 9 · pallets 3 units',
  (select x.status || ' ' || (select string_agg(l.line_no || ':' || trim_scale(l.qty_sent), ',' order by l.line_no) from public.inv_transfer_line l where l.transfer_id = x.id)
     || ' transit=' || trim_scale(public.tf_in_transit_ea(x.id)) || ' units=' || (:'fin1'::jsonb -> 'finalized' -> 0 ->> 'units') from public.inv_transfer x where x.id = :'t1'::uuid), 'in_transit 1:6,2:3 transit=9 units=3');
-- 얼림(정한 것 1)
select pg_temp.chkerr('Z1 after departure: update pallet item refused',
  format('update public.wms_pallet_items set qty_base = 9 where id = %s returning id::text', :'last_item'), 'Transfer TFP-T1 has left the warehouse (in_transit) — its pallets and what is');
select pg_temp.chkerr('Z2 after departure: delete pallet item refused',
  format('delete from public.wms_pallet_items where id = %s returning id::text', :'last_item'), 'Transfer TFP-T1 has left the warehouse (in_transit) — its pallets and what is');
select pg_temp.chkerr('Z3 after departure: new pallet on the transfer refused',
  format('select pg_temp.mk_unit(%L::uuid, ''pallet'', ''P9'', null)::text', :'t1'), 'Transfer TFP-T1 has left the warehouse (in_transit) — its pallets and what is');
select pg_temp.chkerr('Z4 after departure: new box inside P1 refused (root resolved through parent)',
  format('select pg_temp.mk_unit(null, ''box'', ''B9'', %s)::text', :'p1'), 'Transfer TFP-T1 has left the warehouse (in_transit) — its pallets and what is');
select pg_temp.chkerr('Z5 after departure: delete the box B1 refused',
  format('delete from public.wms_pallets where id = %s returning id::text', :'b1'), 'Transfer TFP-T1 has left the warehouse (in_transit) — its pallets and what is');
select pg_temp.chkerr('Z6 after departure: pallet dims may NOT change either (frozen whole)',
  format('update public.wms_pallets set weight_note = ''x'' where id = %s returning id::text', :'p1'), 'Transfer TFP-T1 has left the warehouse (in_transit) — its pallets and what is');
-- 판매 팔렛은 얼리지 않는다 — packed 판매 오더에 팔렛 더하기 OK
set local session_replication_role = replica;
insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at, packed_at)
values ('SO-00000tfp', (select id from public.customer order by created_at limit 1), 'warehouse', 'manual', 'packed', :'cad'::uuid, :'wh1'::uuid, :'wh1name', now(), now()) returning id::text as so1 \gset
set local session_replication_role = origin;
select pg_temp.chkerr('Z7 sales-order pallet after Finalized: insert allowed (SO pallets not frozen)',
  format('insert into public.wms_pallets (order_id, unit_type, label, status, created_by) values (%L, ''pallet'', ''P1'', ''building'', %L) returning id::text', :'so1', :'sa'), 'NOERR');
-- 운송 정보(판정 898)
select pg_temp.as_user(:'ut');
select pg_temp.chk('H1 shipping_set by office (transfer key): carrier · tracking trimmed · eta · changed',
  (select (j ->> 'carrier') || '|' || (j ->> 'tracking_number') || '|' || (j ->> 'eta') || '|' || (j ->> 'changed') from public.inv_transfer_shipping_set(:'t1'::uuid, :'car_on'::uuid, '  PRO  123 456  ', '2026-11-05') j),
  'TFP Carrier|PRO 123 456|2026-11-05|true');
select pg_temp.chk('H1a same again: changed false · row holds the values',
  (select (j ->> 'changed') || '|' || (select coalesce(x.carrier_id::text = :'car_on', false)::text || x.tracking_number || x.eta from public.inv_transfer x where x.id = :'t1'::uuid) from public.inv_transfer_shipping_set(:'t1'::uuid, :'car_on'::uuid, 'PRO 123 456', '2026-11-05') j),
  'false|truePRO 123 4562026-11-05');
select pg_temp.chkerr('H2 inactive carrier refused',
  format('select public.inv_transfer_shipping_set(%L, %L, null, null)::text', :'t1', :'car_off'), 'Carrier TFP Carrier Off is switched off — pick an active carrier — nothing w');
select pg_temp.chkerr('H3 unknown carrier refused',
  format('select public.inv_transfer_shipping_set(%L, gen_random_uuid(), null, null)::text', :'t1'), 'Carrier not found — pick one from the carrier list (Settings → Carriers) — not');
select pg_temp.chkerr('H4 tracking > 200 chars refused',
  format('select public.inv_transfer_shipping_set(%L, null, repeat(''x'', 201), null)::text', :'t1'), 'Tracking number is too long (201 characters · 200 max) — nothing was saved');
select pg_temp.as_user(:'uw');
select pg_temp.chk('H5 receiving worker at the arrival warehouse (wms_receiving key) may set ETA · empty tracking = cleared',
  (select (j ->> 'eta') || '|' || coalesce(j ->> 'tracking_number', 'null') || '|' || (j ->> 'carrier') from public.inv_transfer_shipping_set(:'t1'::uuid, :'car_on'::uuid, '   ', '2026-11-06') j), '2026-11-06|null|TFP Carrier');
select pg_temp.as_user(:'un');
select pg_temp.chkerr('H6 worker with picking key only: refused',
  format('select public.inv_transfer_shipping_set(%L, null, null, null)::text', :'t1'), 'You cannot change transfer shipping details — ask an admin for the ''transfer''');
select pg_temp.as_user(:'uw');
-- 라벨 스캔(tf_pallet_lookup) — 받는 창고 직원
select pg_temp.chk('L1 lookup box label → root pallet P1 · waiting · 1/2 · reason null',
  (select (j ->> 'found') || '|' || (j ->> 'pallet_id') || '|' || (j ->> 'resolved_from_box') || '|' || (j ->> 'display') || '|' || (j ->> 'index') || '/' || (j ->> 'count') || '|' || (j ->> 'pallet_status') || '|' || coalesce(j ->> 'reason', 'null') || '|' || (j ->> 'my_warehouse')
     from public.tf_pallet_lookup('plt-' || :'b1') j), 'true|' || :'p1' || '|true|TFP-T1-P1|1/2|waiting|null|true');
select pg_temp.chk('L2 lookup junk → bad_code', (select (j ->> 'found') || '|' || (j ->> 'reason') from public.tf_pallet_lookup('SO-12345') j), 'false|bad_code');
select pg_temp.chk('L3 lookup unknown id → not_found', (select (j ->> 'found') || '|' || (j ->> 'reason') from public.tf_pallet_lookup('PLT-999999999') j), 'false|not_found');
select pg_temp.chk('L4 lookup a sales-order pallet → sales_order_pallet',
  (select (j ->> 'kind') || '|' || (j ->> 'reason') || '|' || (j ->> 'message') from public.tf_pallet_lookup('PLT-' || (select max(id) from public.wms_pallets where order_id = :'so1'::uuid)) j),
  'so|sales_order_pallet|PLT-' || (select max(id) from public.wms_pallets where order_id = :'so1'::uuid) || ' is a sales-order pallet (SO-00000tfp) — not a transfer');
select pg_temp.as_user(:'un');
select pg_temp.chk('L5 lookup from the sending warehouse worker → other_warehouse',
  (select (j ->> 'reason') || '|' || (j ->> 'my_warehouse') from public.tf_pallet_lookup('PLT-' || :'p2') j), 'other_warehouse|false');
select pg_temp.as_user(:'uw');
-- 시작
select pg_temp.chkerr('V1 start without a pallet on a palletized transfer: refused',
  format('select public.wms_recv_start(%L)::text', :'t1'), 'Transfer TFP-T1 is packed on 2 pallet(s) — scan a pallet label (PLT-…) to recei');
select pg_temp.chkerr('V2 start with a pallet of another document: refused',
  format('select public.wms_recv_start(%L, %s)::text', :'t1', (select max(id) from public.wms_pallets where order_id = :'so1'::uuid)), 'Pallet PLT-' || (select max(id) from public.wms_pallets where order_id = :'so1'::uuid) || ' is not on transfer TFP-T1 (it belongs to sales order SO-00000tfp)');
select pg_temp.chkerr('V3 start on a pallet-less transfer with a pallet id: refused',
  format('select public.wms_recv_start(%L, %s)::text', :'t4', :'p1'), 'Transfer TFP-T4 has no pallets — receive it as one lot (start without a pallet)');
-- V4(PO 에 팔렛 id) 는 뺐다 — 컷오버 뒤 po 표가 비어 있어 PO 입고를 만들 수 없다(창구 줄은 S5 정적 검사로)
select pg_temp.mk_charge(:'t1'::uuid, '1', 90)::text as ch1 \gset
select public.wms_recv_start(:'t1'::uuid, :'b1'::bigint) as st1 \gset
select :'st1'::jsonb ->> 'id' as r1 \gset
select pg_temp.chk('V5 start via the box label: receipt on root P1 · resolved_from_box · pallet 1/2',
  (:'st1'::jsonb ->> 'existing') || '|' || (:'st1'::jsonb ->> 'resolved_from_box') || '|' || (:'st1'::jsonb -> 'pallet' ->> 'display') || '|' || (:'st1'::jsonb -> 'pallet' ->> 'index') || '/' || (:'st1'::jsonb -> 'pallet' ->> 'count')
  || '|' || (select r.pallet_id::text from public.po_receipt r where r.id = :'r1'::uuid), 'false|true|TFP-T1-P1|1/2|' || :'p1');
select pg_temp.chk('V6 start P1 again → the same open receipt (existing)', (select (j ->> 'existing') || '|' || (j ->> 'id') from public.wms_recv_start(:'t1'::uuid, :'p1'::bigint) j), 'true|' || :'r1');
select public.wms_recv_start(:'t1'::uuid, :'p2'::bigint) as st2 \gset
select :'st2'::jsonb ->> 'id' as r2 \gset
select pg_temp.chk('V7 P2 opens at the same time (two drafts · different pallets)',
  (select count(*) || '/' || count(distinct pallet_id) from public.po_receipt r where r.transfer_id = :'t1'::uuid and r.status = 'draft'), '2/2');
-- 상세(P1): 줄 1 만 · 기대 3(2 + 박스 1) · 다른 데서 받은 0 · 머리 pallet · 운송 정보
select public.tf_receipt_detail(:'r1'::uuid) as d1 \gset
select pg_temp.chk('D1 detail P1: one line (1) · expected 3 · sent_ea 6 · received_elsewhere 0 · header.pallet P1 · pallet_count 2 · carrier/eta',
  (select string_agg((l ->> 'line_no') || ':' || (l ->> 'expected_ea') || '/' || (l ->> 'sent_ea') || '/' || (l ->> 'received_elsewhere') || '/' || (l ->> 'pallet_ea'), ',') from jsonb_array_elements(:'d1'::jsonb -> 'lines') l)
  || ' | ' || (:'d1'::jsonb -> 'header' -> 'pallet' ->> 'display') || ' ' || (:'d1'::jsonb -> 'header' ->> 'pallet_count') || ' ' || (:'d1'::jsonb -> 'header' ->> 'carrier') || ' ' || (:'d1'::jsonb -> 'header' ->> 'eta'),
  '1:3/6/0/3 | TFP-T1-P1 2 TFP Carrier 2026-11-06');
select pg_temp.chkerr('C1 scan line 2 on P1: refused (not on this pallet)',
  format('select public.wms_recv_scan(%L, %L, 1)::text', :'r1', pg_temp.line(:'t1'::uuid, 2)), 'TFP-2 is not on pallet TFP-T1-P1 — it is on another pallet of this transfer; r');
select pg_temp.chkerr('C2 count line 2 on P1: refused too',
  format('select public.wms_recv_count(%L, %L, 1, null)::text', :'r1', pg_temp.line(:'t1'::uuid, 2)), 'TFP-2 is not on pallet TFP-T1-P1 — it is on another pallet of this transfer; r');
select public.wms_recv_scan(:'r1'::uuid, pg_temp.line(:'t1'::uuid, 1), 3) as sc1 \gset
select pg_temp.chk('C3 scan line 1 ×3 on P1 ok · transfer → receiving', (:'sc1'::jsonb ->> 'counted') || '|' || (select status from public.inv_transfer where id = :'t1'::uuid), '3|receiving');
select pg_temp.putaway_all(:'r1'::uuid) as pa1 \gset
select public.wms_recv_complete(:'r1'::uuid) as cp1 \gset
select pg_temp.chk('A1 complete P1: arrived receiving · final false · 1/2 done · in_transit 6 · line 1 qty_received 3 · no diffs · freight NOT posted yet',
  (:'cp1'::jsonb -> 'arrived' ->> 'status') || '|' || (:'cp1'::jsonb -> 'arrived' ->> 'final') || '|' || (:'cp1'::jsonb -> 'arrived' ->> 'pallets_done') || '/' || (:'cp1'::jsonb -> 'arrived' ->> 'pallet_count') || '|' || (:'cp1'::jsonb -> 'arrived' ->> 'in_transit_ea')
  || '|' || (select status from public.inv_transfer where id = :'t1'::uuid)
  || '|' || (select string_agg(l.line_no || ':' || coalesce(trim_scale(l.qty_received)::text, 'null'), ',' order by l.line_no) from public.inv_transfer_line l where l.transfer_id = :'t1'::uuid)
  || '|diffs=' || (select count(*) from public.po_receipt_diff d where d.transfer_id = :'t1'::uuid)
  || '|cost_add=' || (select count(*) from public.inv_layer_cost_add ca where ca.doc_number = 'TFP-CH1') || '|freight=' || (:'cp1'::jsonb -> 'arrived' -> 'freight' -> 'posted')::text,
  'receiving|false|1/2|6|receiving|1:3,2:null|diffs=0|cost_add=0|freight=[]');
select pg_temp.chk('A2 ledger after P1: IN_TRANSIT −3 for TFP-1 with receipt suffix · Edmonton +3 · layers at Edmonton 3',
  (select string_agg(e.warehouse || ':' || trim_scale(e.qty_delta) || ':' || (e.line_ref like '%:RCV-%')::text, ',' order by e.warehouse, e.qty_delta) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = 'TFP-T1' and e.line_ref like '%:RCV-%')
  || ' | ' || (select trim_scale(coalesce(sum(y.qty), 0)) from public.inv_layer y where y.origin_type = 'transfer' and y.doc_number = 'TFP-T1' and y.warehouse = :'wh2name'),
  'Asung - Edmonton:3:true,IN_TRANSIT:-3:true | 3');
select pg_temp.chkerr('A3 start P1 again after it was received: refused',
  format('select public.wms_recv_start(%L, %s)::text', :'t1', :'p1'), 'Pallet TFP-T1-P1 of transfer TFP-T1 was already received (RCV-');
select pg_temp.chk('A4 lookup P1 now → already_received · done', (select (j ->> 'pallet_status') || '|' || (j ->> 'reason') from public.tf_pallet_lookup('PLT-' || :'p1') j), 'done|already_received');
select public.tf_receipt_detail(:'r2'::uuid) as d2 \gset
select pg_temp.chk('D2 detail P2: line 1 expected 3 · received_elsewhere 3 · line 2 expected 3',
  (select string_agg((l ->> 'line_no') || ':' || (l ->> 'expected_ea') || '/' || (l ->> 'received_elsewhere'), ',' order by (l ->> 'line_no')::int) from jsonb_array_elements(:'d2'::jsonb -> 'lines') l), '1:3/3,2:3/0');
select public.wms_recv_scan(:'r2'::uuid, pg_temp.line(:'t1'::uuid, 1), 3);
select public.wms_recv_scan(:'r2'::uuid, pg_temp.line(:'t1'::uuid, 2), 2);   -- 줄 2 는 1 모자람
select pg_temp.putaway_all(:'r2'::uuid) as pa2 \gset
select public.wms_recv_complete(:'r2'::uuid) as cp2 \gset
select pg_temp.chk('A5 complete P2 (last pallet): received · final · 2/2 · in_transit 1 (short) · qty_received 6/2 accumulated · one short diff with pallet tag · freight posted on arrival layers',
  (:'cp2'::jsonb -> 'arrived' ->> 'status') || '|' || (:'cp2'::jsonb -> 'arrived' ->> 'final') || '|' || (:'cp2'::jsonb -> 'arrived' ->> 'pallets_done') || '/' || (:'cp2'::jsonb -> 'arrived' ->> 'pallet_count') || '|' || (:'cp2'::jsonb -> 'arrived' ->> 'in_transit_ea')
  || '|' || (select status || ':' || (received_at is not null)::text from public.inv_transfer where id = :'t1'::uuid)
  || '|' || (select string_agg(l.line_no || ':' || trim_scale(l.qty_received), ',' order by l.line_no) from public.inv_transfer_line l where l.transfer_id = :'t1'::uuid)
  || '|' || (select string_agg(d.kind || ':' || trim_scale(d.expected_qty) || '/' || trim_scale(d.received_qty) || ':' || (d.note like 'transfer arrival (pallet TFP-T1-P2) — fewer%')::text, ',') from public.po_receipt_diff d where d.transfer_id = :'t1'::uuid)
  || '|cost_add=' || (select count(*) || '/' || trim_scale(sum(ca.amount)) from public.inv_layer_cost_add ca where ca.doc_number = 'TFP-CH1'),
  'received|true|2/2|1|received:true|1:6,2:2|short:3/2:true|cost_add=3/90');
select pg_temp.chk('A6 freight spread over all three arrival layers (P1 3 EA · P2 3 + 2 EA) — not only P1',
  (select string_agg(y.sku || ':' || trim_scale(y.qty) || ':' || trim_scale(ca.amount), ',' order by y.sku, y.qty, ca.amount) from public.inv_layer_cost_add ca join public.inv_layer y on y.id = ca.layer_id where ca.doc_number = 'TFP-CH1'),
  'TFP-1:3:27,TFP-1:3:27,TFP-2:2:36');
select pg_temp.chk('A7 tf_pallets after both: 2/2 done · statuses · lines of P1 (2 + box 1 = 3) · boxes [B1] · shipping',
  (select (j ->> 'pallets_done') || '/' || (j ->> 'pallet_count') || '|' || (select string_agg((p ->> 'display') || ':' || (p ->> 'status') || ':' || (p ->> 'qty_ea') || ':' || ((p ->> 'receipt_number') is not null)::text, ',' order by (p ->> 'index')::int) from jsonb_array_elements(j -> 'pallets') p)
     || '|' || (j -> 'pallets' -> 0 -> 'lines' -> 0 ->> 'qty_ea') || '|' || (j -> 'pallets' -> 0 -> 'boxes' -> 0 ->> 'label') || '|' || (j -> 'shipping' ->> 'carrier') || '|' || (j ->> 'in_transit_ea')
   from public.tf_pallets(:'t1'::uuid) j), '2/2|TFP-T1-P1:done:3:true,TFP-T1-P2:done:6:true|3|B1|TFP Carrier|1');
select pg_temp.as_user(:'ut');
select pg_temp.chkerr('H7 shipping_set after received: refused',
  format('select public.inv_transfer_shipping_set(%L, null, null, null)::text', :'t1'), 'Transfer TFP-T1 is received — shipping details can be changed only until it is');
select pg_temp.chk('H8 shipping_set on a draft of another status (T3 picking) is allowed · null carrier allowed',
  (select (j ->> 'changed') || '|' || coalesce(j ->> 'carrier', 'null') from public.inv_transfer_shipping_set((select id from public.inv_transfer where transfer_number = 'TFP-T4'), null, 'BOL 7', null) j), 'true|null');

-- ── S 늦은 팔렛 · 분실 정리로 닫힘 — TFP-T2: 줄 1 = 4 · P1(2) · P2(2) · P1 받고 P2 분실 → received · 운임이 P1 레이어에 ──
select pg_temp.as_user(:'ua');
select pg_temp.mk_tf('2', 4, 0)::text as t2 \gset
select pg_temp.mk_unit(:'t2'::uuid, 'pallet', 'P1', null)::text as q1 \gset
select pg_temp.mk_unit(:'t2'::uuid, 'pallet', 'P2', null)::text as q2 \gset
select pg_temp.mk_item(:'q1'::bigint, :'t2'::uuid, 1, 2), pg_temp.mk_item(:'q2'::bigint, :'t2'::uuid, 1, 2);
select public.wms_finalize(array[:'t2'::uuid]) as fin2 \gset
select pg_temp.mk_charge(:'t2'::uuid, '2', 40)::text as ch2 \gset
select pg_temp.as_user(:'uw');
select (public.wms_recv_start(:'t2'::uuid, :'q1'::bigint) ->> 'id') as r3 \gset
select public.wms_recv_scan(:'r3'::uuid, pg_temp.line(:'t2'::uuid, 1), 2);
select pg_temp.putaway_all(:'r3'::uuid);
select public.wms_recv_complete(:'r3'::uuid) as cp3 \gset
select pg_temp.chk('S5 T2 after P1: receiving · in_transit 2 · freight not posted',
  (select status from public.inv_transfer where id = :'t2'::uuid) || '|' || trim_scale(public.tf_in_transit_ea(:'t2'::uuid)) || '|' || (select count(*) from public.inv_layer_cost_add where doc_number = 'TFP-CH2'), 'receiving|2|0');
select pg_temp.as_user(:'ua');
select public.tf_settle(:'t2'::uuid, jsonb_build_array(jsonb_build_object('line_id', pg_temp.line(:'t2'::uuid, 1), 'action', 'lost', 'qty', 2))) as stl \gset
select pg_temp.chk('S6 settle P2 lost: closed · received · in_transit 0 · freight 40 on P1''s layer (2 EA)',
  (:'stl'::jsonb ->> 'closed') || '|' || (:'stl'::jsonb ->> 'status') || '|' || (:'stl'::jsonb ->> 'in_transit_ea') || '|' || (select status || ':' || (received_at is not null)::text from public.inv_transfer where id = :'t2'::uuid)
  || '|' || (select string_agg(y.sku || ':' || trim_scale(y.qty) || ':' || trim_scale(ca.amount), ',') from public.inv_layer_cost_add ca join public.inv_layer y on y.id = ca.layer_id where ca.doc_number = 'TFP-CH2')
  || '|' || (:'stl'::jsonb ->> 'poster'), 'true|received|0|received:true|TFP-1:2:40|tf_settle@2026-10-31.2');
select pg_temp.chk('S7 settle on a plain received transfer (T0 short 1 lost): no close flag · status received · poster new',
  (select (j ->> 'closed') || '|' || (j ->> 'status') || '|' || (j ->> 'in_transit_ea') from public.tf_settle((select id from public.inv_transfer where transfer_number = 'TFP-T0'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.line((select id from public.inv_transfer where transfer_number = 'TFP-T0'), 2), 'action', 'lost', 'qty', 1))) j), 'false|received|0');
select pg_temp.chk('S8 lookup P2 of T2 (lost · transfer received) → waiting · not_in_transit',
  (select (j ->> 'pallet_status') || '|' || (j ->> 'reason') from public.tf_pallet_lookup('PLT-' || :'q2') j), 'waiting|not_in_transit');

-- ── E 모서리: 팔렛 받기에서 over · 같은 SKU 두 팔렛 · pallet_id 유니크 · 박스만 있는 팔렛 ──
select pg_temp.mk_tf('3', 5, 0)::text as t3 \gset
select pg_temp.mk_unit(:'t3'::uuid, 'pallet', 'P1', null)::text as u1 \gset
select pg_temp.mk_unit(:'t3'::uuid, 'pallet', 'P2', null)::text as u2 \gset
select pg_temp.mk_unit(:'t3'::uuid, 'box', 'B1', :'u2'::bigint)::text as u2b \gset
select pg_temp.mk_item(:'u1'::bigint, :'t3'::uuid, 1, 2), pg_temp.mk_item(:'u2b'::bigint, :'t3'::uuid, 1, 3);
select public.wms_finalize(array[:'t3'::uuid]) as fin3 \gset
select pg_temp.as_user(:'uw');
select (public.wms_recv_start(:'t3'::uuid, :'u1'::bigint) ->> 'id') as r4 \gset
select public.wms_recv_scan(:'r4'::uuid, pg_temp.line(:'t3'::uuid, 1), 3);   -- 팔렛 몫 2 보다 1 많이
select pg_temp.putaway_all(:'r4'::uuid);
select public.wms_recv_complete(:'r4'::uuid) as cp4 \gset
select pg_temp.chk('E1 over on a pallet: posts the pallet share (2) · over diff 2/3 tagged with pallet · in_transit 3 · receiving',
  (:'cp4'::jsonb -> 'arrived' ->> 'posted_ea') || '|' || (select d.kind || ':' || trim_scale(d.expected_qty) || '/' || trim_scale(d.received_qty) || ':' || (d.note like '%(pallet TFP-T3-P1)%')::text from public.po_receipt_diff d where d.receipt_id = :'r4'::uuid)
  || '|' || trim_scale(public.tf_in_transit_ea(:'t3'::uuid)) || '|' || (select status from public.inv_transfer where id = :'t3'::uuid), '2|over:2/3:true|3|receiving');
select pg_temp.chkerr('E2 unique (transfer, pallet): a second draft for the same pallet is impossible',
  format('insert into public.po_receipt (transfer_id, pallet_id, warehouse_id, status, created_by) values (%L, %s, %L, ''draft'', %L) returning id::text', :'t3', :'u2', :'wh2', :'sa'), 'NOERR');   -- 첫 초안(P2 는 아직 안 열렸다) — 아래 E3 가 둘째를 막는지 본다
select pg_temp.chkerr('E3 unique (transfer, pallet): second row refused',
  format('insert into public.po_receipt (transfer_id, pallet_id, warehouse_id, status, created_by) values (%L, %s, %L, ''draft'', %L) returning id::text', :'t3', :'u2', :'wh2', :'sa'), 'duplicate key value violates unique constraint "po_receipt_transfer_pallet_uq"');
-- E4(ck 만) 는 F2 의 정의 검사로 갈음 — po_id 없이 넣으면 po_receipt_doc_ck 가 먼저 선다
select pg_temp.chk('E5 pallet whose goods sit only in its box: detail expected = box qty 3',
  (select string_agg((l ->> 'line_no') || ':' || (l ->> 'expected_ea'), ',') from jsonb_array_elements(public.tf_receipt_detail((select r.id from public.po_receipt r where r.transfer_id = :'t3'::uuid and r.pallet_id = :'u2'::bigint and r.status = 'draft')) -> 'lines') l), '1:3');
select pg_temp.chk('E6 tf_pallets T3: P1 done · P2 receiving (draft) · P2 boxes [B1]',
  (select string_agg((p ->> 'label') || ':' || (p ->> 'status') || ':' || coalesce(p -> 'boxes' -> 0 ->> 'label', ''), ',' order by (p ->> 'index')::int) from jsonb_array_elements(public.tf_pallets(:'t3'::uuid) -> 'pallets') p), 'P1:done:,P2:receiving:B1');

-- ── 화면이 부를 창구 꼴(보고용 출력 · 검사 아님) ──
\echo '── 창구 꼴: wms_recv_start(T1, box B1) →' :st1
select public.tf_pallet_lookup('PLT-' || :'p2')::text as lk \gset
\echo '── 창구 꼴: tf_pallet_lookup(''PLT-<P2>'') →' :lk
select public.tf_pallets(:'t1'::uuid)::text as tp \gset
\echo '── 창구 꼴: tf_pallets(T1) →' :tp
select (:'d2'::jsonb -> 'header')::text as d2h, (:'d2'::jsonb -> 'lines' -> 0)::text as d2l \gset
\echo '── 창구 꼴: tf_receipt_detail(R2).header →' :d2h
\echo '── 창구 꼴: tf_receipt_detail(R2).lines[0] →' :d2l
select (:'cp2'::jsonb -> 'arrived')::text as cp2a \gset
\echo '── 창구 꼴: wms_recv_complete(R2).arrived →' :cp2a
\echo '── 창구 꼴: tf_settle(T2, lost) →' :stl
-- ── 결과 ──
select pg_temp.chk('X1 fake rows present (rolled back below): 5 TFP transfers · 2 products · 2 carriers · 2 charges',
  (select count(*) from public.inv_transfer where transfer_number like 'TFP-T%') || '/' || (select count(*) from public.product where sku like 'TFP-%') || '/' || (select count(*) from public.ref_carrier where name like 'TFP %') || '/' || (select count(*) from public.po_charge where charge_number like 'TFP-CH%'), '5/2/2/2');
\echo '── 결과(OK · MISMATCH) ──'
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' | want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as n_ok, count(*) filter (where not ok) as n_bad, count(*) as n_all from t_res \gset
\echo '── OK' :n_ok '· MISMATCH' :n_bad '· 전체' :n_all '· 기대 OK' :EXPECT_OK
rollback;
-- ── 뒤: 실제 행 무변 ──
select (select count(*) from public.inv_transfer) = :n_tf and (select count(*) from public.inv_transfer_line) = :n_tfl and (select count(*) from public.po_receipt) = :n_rc
   and (select count(*) from public.wms_pallets) = :n_pal and (select count(*) from public.wms_pallet_items) = :n_pit and (select count(*) from public.inv_ledger) = :n_led and (select count(*) from public.inv_layer) = :n_lay
   and (select count(*) from public.ims_staff) = :n_staff and (select count(*) from public.ref_carrier) = :n_car and (select count(*) from public.po_charge) = :n_chg
   and (select count(*) from public.inv_transfer where transfer_number like 'TFP-%') + (select count(*) from public.product where sku like 'TFP-%') = :n_fake0 as rows_unchanged_after_rollback \gset
\echo '── rollback 뒤 실제 행 무변:' :rows_unchanged_after_rollback
select case when :n_bad = 0 and :n_ok = :EXPECT_OK and :'rows_unchanged_after_rollback' = 't' then 'PASS' else 'FAIL' end as verdict;
