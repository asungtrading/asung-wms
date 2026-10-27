-- supabase/tests/wsp_1_check.sql — wsp-1 IMS WMS 동시 작업 작은 구멍 넷(a · b · c · d) 검증 (2026-10-27)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀(asung-workflow §4) — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 함수 md5 · 권한 · 중복 라벨 수)
--   → begin → (-v mig 면 \i) → 꼴(인덱스 · 함수 · 권한) · 정적(잠금 순서) · 가짜 재료(WSP · SO-00000wsp* · WSP-T*) 로 기능 · 회귀 한 바퀴 → rollback → 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027144202_wsp_1_wms_concurrency.sql -f supabase/tests/wsp_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 시험(-v mig) 43 · 확인(적용 뒤 · -v mig 없음) 42 — M1(새 함수 md5 ≠ 기준 md5)은 「적용 전 기준」 이 있어야 성립해 시험 갈래에서만 돈다
--   적용 전 마른 실행(-v mig 없음)은 a · b · c · d 의 새 동작 검사가 MISMATCH(아직 옛 함수 · 인덱스 없음 — 정상)
--   쓰기 0 — 가짜 재료는 rollback · 문서 번호를 당기지 않는다(so_number · transfer_number 를 직접 준다 · 기본값 so_next_number · inv_transfer_next_number 안 돎)
--   ⚠️ identity id(wms_pick_tasks · wms_pick_task_lines · wms_waves · wms_rollback_log · wms_rollback_archive)는 당긴다 — 틈만 남는다(사람이 읽는 번호 아님)
--   ⚠️ 동시성 자체(두 세션)는 돌리지 않는다 — 잠금 순서 · 잠근 뒤 재확인은 정적 검사(S*)로 · 차례 두 번은 기능 검사로
\set ON_ERROR_STOP on
\if :{?mig}
\set EXPECT_OK 43
\else
\set EXPECT_OK 42
\endif
\pset pager off
-- 기준(begin 앞 · 잠금 없음)
select (select count(*) from public.wms_pick_tasks) as n_pt, (select count(*) from public.wms_pick_task_lines) as n_ptl,
       (select count(*) from public.wms_waves) as n_wv, (select count(*) from public.wms_rollback_log) as n_rbl,
       (select count(*) from public.wms_pack_tasks) as n_pk,
       (select count(*) from public.so) as n_so, (select count(*) from public.inv_transfer) as n_tf, (select count(*) from public.ims_staff) as n_staff,
       (select count(*) from public.so where so_number like 'SO-00000wsp%') + (select count(*) from public.inv_transfer where transfer_number like 'WSP-%') as n_wsp0,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('so_release_to_wms', 'tf_release', 'wms_wave_create', 'wms_rollback_batch')) as fn_md5_0,
       (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('so_release_to_wms', 'tf_release', 'wms_wave_create', 'wms_rollback_batch')) as fn_acl_0,
       (select count(*) from (select 1 from public.wms_pick_tasks where order_id is not null group by order_id, batch_label having count(*) > 1) d)
     + (select count(*) from (select 1 from public.wms_pick_tasks where transfer_id is not null group by transfer_id, batch_label having count(*) > 1) d) as n_dup0,
       (select count(*) from pg_class where oid in (to_regclass('public.uq_picktasks_order_label'), to_regclass('public.uq_picktasks_transfer_label'))) as n_idx0,
       'W-' || to_char(public.ims_today(), 'MMDD') || '-' as wv_pfx,
       (select coalesce(max(substring(w.label from '^W-' || to_char(public.ims_today(), 'MMDD') || '-([0-9]+)$')::int), 0) from public.wms_waves w) as wv_n0
\gset
\echo '── 기준: pick_tasks' :n_pt '· waves' :n_wv '· rollback_log' :n_rbl '· so' :n_so '· transfer' :n_tf '· WSP rows' :n_wsp0 '· dup labels' :n_dup0 '· today waves' :wv_pfx :wv_n0
\echo '── fn md5:' :fn_md5_0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
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
-- 문서 줄 전부를 배치 하나로(화면의 p_batches 꼴)
create function pg_temp.one_batch(p_doc uuid) returns jsonb language sql as $$
  select jsonb_build_array(jsonb_build_object('line_ids', jsonb_agg(l.line_id order by l.line_no))) from public.wms_order_doc_line l where l.doc_id = p_doc and l.qty_target > 0
$$;
create function pg_temp.src(p_name text) returns text language sql as $$
  select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = p_name
$$;

-- ── M 재료: 가짜 직원(admin · 모든 창고) · 손님 · 제품 · 창고 둘 ──
select id::text as wh1, name as wh1name from public.ref_warehouse where is_active order by name offset 0 limit 1 \gset
select id::text as wh2 from public.ref_warehouse where is_active order by name offset 1 limit 1 \gset
select id::text as cad from public.ref_currency where code = 'CAD' \gset
set local session_replication_role = replica;
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'wsp1@test.invalid', 'WSP Admin', 'admin', '["ims","sales","transfer","wms_manage"]', '{}')
  returning auth_user_id::text as uid \gset
insert into public.customer (name, source, currency_id) values ('WSP Customer', 'manual', :'cad'::uuid) returning id::text as cust \gset
insert into public.product (sku, name, source) values ('WSP-P1', 'WSP Product', 'manual') returning id::text as pid \gset
create function pg_temp.mk_so(p_tag text, p_status text, p_alloc boolean default false) returns uuid language plpgsql as $$
declare v_so uuid; v_l uuid;
begin
  insert into public.so (so_number, customer_id, channel, intake, status, currency_id, location_id, location_name, confirmed_at)
  values ('SO-00000wsp' || p_tag, current_setting('wsp.cust')::uuid, 'warehouse', 'manual', p_status, current_setting('wsp.cad')::uuid,
          current_setting('wsp.wh1')::uuid, current_setting('wsp.wh1name'), case when p_status <> 'draft' then now() end)
  returning id into v_so;
  insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (v_so, 1, current_setting('wsp.pid')::uuid, 'WSP-P1', 1, 3) returning id into v_l;
  insert into public.so_line (so_id, line_no, product_id, sku, pack_factor, qty_ordered) values (v_so, 2, current_setting('wsp.pid')::uuid, 'WSP-P1', 1, 2);
  if p_alloc then
    insert into public.so_reserve (so_line_id, qty_allocated, kind) select l.id, l.qty_ordered, 'allocated' from public.so_line l where l.so_id = v_so;
  end if;
  return v_so;
end $$;
create function pg_temp.mk_tf(p_tag text, p_status text) returns uuid language plpgsql as $$
declare v_x uuid;
begin
  insert into public.inv_transfer (transfer_number, status, from_warehouse_id, to_warehouse_id, confirmed_at)
  values ('WSP-T' || p_tag, p_status, current_setting('wsp.wh1')::uuid, current_setting('wsp.wh2')::uuid, case when p_status <> 'draft' then now() end)
  returning id into v_x;
  insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (v_x, 1, current_setting('wsp.pid')::uuid, 'WSP-P1', 4, 1);
  return v_x;
end $$;
select set_config('wsp.cust', :'cust', true), set_config('wsp.cad', :'cad', true), set_config('wsp.wh1', :'wh1', true), set_config('wsp.wh1name', :'wh1name', true), set_config('wsp.pid', :'pid', true), set_config('wsp.wh2', :'wh2', true) \gset
select pg_temp.mk_so('a', 'at_wms')::text as so_a, pg_temp.mk_so('z', 'at_wms')::text as so_z, pg_temp.mk_so('b', 'at_wms')::text as so_b,
       pg_temp.mk_so('r', 'confirmed', true)::text as so_r,
       pg_temp.mk_so('wa', 'at_wms')::text as so_w1, pg_temp.mk_so('wb', 'at_wms')::text as so_w2, pg_temp.mk_so('wc', 'at_wms')::text as so_w3,
       pg_temp.mk_tf('1', 'at_wms')::text as tf_1, pg_temp.mk_tf('2', 'confirmed')::text as tf_2, pg_temp.mk_tf('3', 'at_wms')::text as tf_3 \gset
set local session_replication_role = origin;
select set_config('request.jwt.claims', json_build_object('sub', :'uid', 'role', 'authenticated')::text, true) \gset
select pg_temp.chk('M0 fake material: staff · customer · product · 7 SO · 3 transfers (WSP)',
  ((select count(*) from public.so where so_number like 'SO-00000wsp%') || '/' || (select count(*) from public.inv_transfer where transfer_number like 'WSP-T%'))::text, '7/3');

-- ── F 꼴: 유니크 둘(부분 아님 · 열 순서) · 함수 넷의 권한 · definer 무변 · 새 함수 없음 ──
select pg_temp.chk('F1 uq_picktasks_order_label = unique (order_id, batch_label) · not partial',
  (select pg_get_indexdef(i.indexrelid) || ' pred=' || coalesce(pg_get_expr(i.indpred, i.indrelid), 'none') from pg_index i where i.indexrelid = to_regclass('public.uq_picktasks_order_label')),
  'CREATE UNIQUE INDEX uq_picktasks_order_label ON public.wms_pick_tasks USING btree (order_id, batch_label) pred=none');
select pg_temp.chk('F2 uq_picktasks_transfer_label = unique (transfer_id, batch_label) · not partial',
  (select pg_get_indexdef(i.indexrelid) || ' pred=' || coalesce(pg_get_expr(i.indpred, i.indrelid), 'none') from pg_index i where i.indexrelid = to_regclass('public.uq_picktasks_transfer_label')),
  'CREATE UNIQUE INDEX uq_picktasks_transfer_label ON public.wms_pick_tasks USING btree (transfer_id, batch_label) pred=none');
select pg_temp.chk('F3 four functions: acl · security definer same as before',
  (select string_agg(p.proname || '=' || coalesce(p.proacl::text, '-') || '/' || p.prosecdef, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('so_release_to_wms', 'tf_release', 'wms_wave_create', 'wms_rollback_batch')), :'fn_acl_0');
select pg_temp.chk('F4 one definition each (no new overload)',
  (select string_agg(p.proname || ':' || count, ' ' order by p.proname) from (select proname, count(*)::text from pg_proc where pronamespace = 'public'::regnamespace
     and proname in ('so_release_to_wms', 'tf_release', 'wms_wave_create', 'wms_rollback_batch') group by proname) p),
  'so_release_to_wms:1 tf_release:1 wms_rollback_batch:1 wms_wave_create:1');
\if :{?mig}
select pg_temp.chk('M1 all four functions changed vs baseline md5 (시험 갈래만)',
  ((select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('so_release_to_wms', 'tf_release', 'wms_wave_create', 'wms_rollback_batch')) <> :'fn_md5_0')::text, 'true');
\endif

-- ── S 정적: 잠금이 검사 앞 · id 순 · 라벨 셈 앞 advisory · 잠근 뒤 재확인 ──
select pg_temp.chk('S1 so_release_to_wms: id-ordered lock before checks · check select is for update',
  (position('where s.id = any (p_so_ids) order by s.id for update' in pg_temp.src('so_release_to_wms')) between 1 and position('-- ① 검사 전부' in pg_temp.src('so_release_to_wms'))
   and pg_temp.src('so_release_to_wms') like '%select * into v_so from public.so s where s.id = v_id for update;%')::text, 'true');
select pg_temp.chk('S2 tf_release: id-ordered lock before checks · check select is for update',
  (position('where x.id = any (p_ids) order by x.id for update' in pg_temp.src('tf_release')) between 1 and position('-- ① 검사 전부' in pg_temp.src('tf_release'))
   and pg_temp.src('tf_release') like '%select * into v_x from public.inv_transfer x where x.id = v_id for update;%')::text, 'true');
select pg_temp.chk('S3 wms_wave_create: so then transfer locks in id order before the check loop',
  (position('from public.so s where s.id = any (p_so_ids) order by s.id for update' in pg_temp.src('wms_wave_create'))
     between 1 and position('from public.inv_transfer x where x.id = any (p_so_ids) order by x.id for update' in pg_temp.src('wms_wave_create'))
   and position('from public.inv_transfer x where x.id = any (p_so_ids) order by x.id for update' in pg_temp.src('wms_wave_create')) < position('-- ① 검사 전부' in pg_temp.src('wms_wave_create')))::text, 'true');
select pg_temp.chk('S4 wms_wave_create: advisory lock (date key) before the label count',
  (position('pg_advisory_xact_lock(hashtext(''wms_wave_label:'' || v_md))' in pg_temp.src('wms_wave_create'))
     between 1 and position('select coalesce(max(substring(w.label' in pg_temp.src('wms_wave_create')))::text, 'true');
select pg_temp.chk('S5 wms_rollback_batch: re-checks (pack gone · pick gone · nothing to reset) come after the row locks',
  (position('from public.inv_transfer x where x.id = v_so_id for update' in pg_temp.src('wms_rollback_batch'))
     between 1 and position('has no packing to undo' in pg_temp.src('wms_rollback_batch'))
   and position('has no packing to undo' in pg_temp.src('wms_rollback_batch')) < position('is gone — the order was already sent back' in pg_temp.src('wms_rollback_batch'))
   and position('is gone — the order was already sent back' in pg_temp.src('wms_rollback_batch')) < position('has no picking to reset' in pg_temp.src('wms_rollback_batch')))::text, 'true');

-- ── a 유니크 · Split 회귀 ──
select pg_temp.run(format('select (public.wms_batch_create(%L::uuid, %L::jsonb)->>''status'')', :'so_a', pg_temp.one_batch(:'so_a'::uuid))) as a_split \gset
select pg_temp.chk('A1 Split (wms_batch_create) SO a → picking · one task SO-00000wspa-1',
  :'a_split' || ' ' || (select string_agg(batch_label, ',') from public.wms_pick_tasks where order_id = :'so_a'::uuid), 'picking SO-00000wspa-1');
select pg_temp.chk('A2 second Split of the same order is refused (existing behaviour)',
  pg_temp.run(format('select public.wms_batch_create(%L::uuid, %L::jsonb)::text', :'so_a', pg_temp.one_batch(:'so_a'::uuid))),
  'ERR P0001: Order SO-00000wspa is picking — only orders released to the WMS can be batched — nothing was saved');
select pg_temp.chk('A3 direct insert of a second (order_id, batch_label) → 23505',
  left(pg_temp.run(format('insert into public.wms_pick_tasks (order_id, batch_label, status) values (%L::uuid, ''SO-00000wspa-1'', ''pending'') returning id::text', :'so_a')), 9), 'ERR 23505');
select pg_temp.run(format('select (public.wms_batch_create(%L::uuid, %L::jsonb)->>''status'')', :'tf_1', pg_temp.one_batch(:'tf_1'::uuid))) as a_tsplit \gset
select pg_temp.chk('A4 Split transfer WSP-T1 → picking · task WSP-T1-1',
  :'a_tsplit' || ' ' || (select string_agg(batch_label, ',') from public.wms_pick_tasks where transfer_id = :'tf_1'::uuid), 'picking WSP-T1-1');
select pg_temp.chk('A5 direct insert of a second (transfer_id, batch_label) → 23505',
  left(pg_temp.run(format('insert into public.wms_pick_tasks (transfer_id, batch_label, status) values (%L::uuid, ''WSP-T1-1'', ''pending'') returning id::text', :'tf_1')), 9), 'ERR 23505');
select pg_temp.chk('A6 sale and transfer rows with the same label text do not collide (null order_id / transfer_id are distinct)',
  pg_temp.run(format('with x as (insert into public.wms_pick_tasks (order_id, batch_label, status) values (%L::uuid, ''WSP-T1-1'', ''pending''), (%L::uuid, ''SO-00000wspa-1'', ''pending'') returning 1) select count(*)::text from x', :'so_b', :'so_b'))
  || ' ' || pg_temp.run(format('insert into public.wms_pick_tasks (transfer_id, batch_label, status) values (%L::uuid, ''SO-00000wspa-1'', ''pending'') returning ''1''', :'tf_1')), '2 1');
delete from public.wms_pick_tasks where order_id = :'so_b'::uuid or (transfer_id = :'tf_1'::uuid and batch_label = 'SO-00000wspa-1');
select pg_temp.run(format('select (public.wms_batch_create(%L::uuid, %L::jsonb)->>''status'')', :'so_z', pg_temp.one_batch(:'so_z'::uuid))) as z1 \gset
select pg_temp.run(format('select (public.wms_rollback(%L::uuid, ''split'')->>''status'')', :'so_z')) as z2 \gset
select pg_temp.run(format('select (public.wms_batch_create(%L::uuid, %L::jsonb)->>''status'')', :'so_z', pg_temp.one_batch(:'so_z'::uuid))) as z3 \gset
select pg_temp.chk('A7 Split → Undo split → Split again: same label stands again (delete then recreate)',
  :'z1' || '>' || :'z2' || '>' || :'z3' || ' ' || (select string_agg(batch_label, ',') from public.wms_pick_tasks where order_id = :'so_z'::uuid), 'picking>at_wms>picking SO-00000wspz-1');
select pg_temp.chk('A8 Undo split twice: second is refused (existing behaviour) — first Undo here',
  pg_temp.run(format('select (public.wms_rollback(%L::uuid, ''split'')->>''status'')', :'so_z')), 'at_wms');
select pg_temp.chk('A9 … second Undo split refused',
  pg_temp.run(format('select public.wms_rollback(%L::uuid, ''split'')::text', :'so_z')), 'ERR P0001: Order SO-00000wspz is at_wms — nothing to roll back here — nothing was saved');

-- ── b 배치 되돌리기 두 번 ──
-- 마른 실행(유니크 없음)에서는 A3 가 두 번째 행을 만든다 — 첫 과제를 집는다
select id::text as pt_b from public.wms_pick_tasks where order_id = :'so_a'::uuid order by id limit 1 \gset
update public.wms_pick_tasks set status = 'in_progress', assigned_to = (select id from public.ims_staff where auth_user_id = :'uid'::uuid), started_at = now(), heartbeat_at = now() where id = :'pt_b'::bigint;
select pg_temp.chk('B1 Reset Pick (batch) on an in-progress batch → ok',
  pg_temp.run(format('select (public.wms_rollback_batch(%s, ''pick'')->>''kind'')', :'pt_b')), 'pick');
select pg_temp.chk('B2 second Reset Pick on the same batch → refused (nothing to reset)',
  pg_temp.run(format('select public.wms_rollback_batch(%s, ''pick'')::text', :'pt_b')), 'ERR P0001: Batch SO-00000wspa-1 has no picking to reset — it was already reset — nothing was saved');
select pg_temp.chk('B3 rollback log: one pick row for that order',
  (select count(*)::text from public.wms_rollback_log where order_id = :'so_a'::uuid and action = 'pick'), '1');
update public.wms_pick_task_lines set picked_base = 1 where pick_task_id = :'pt_b'::bigint and id = (select min(id) from public.wms_pick_task_lines where pick_task_id = :'pt_b'::bigint);
select pg_temp.chk('B4 a held batch with progress (pending · picked_base > 0) can still be reset (screen button condition)',
  pg_temp.run(format('select (public.wms_rollback_batch(%s, ''pick'')->>''kind'')', :'pt_b')), 'pick');
update public.wms_pick_tasks set status = 'completed', completed_at = now() where id = :'pt_b'::bigint;
insert into public.wms_pack_tasks (order_id, pick_task_id, batch_label, status, started_at, heartbeat_at) values (:'so_a'::uuid, :'pt_b'::bigint, 'SO-00000wspa-1', 'in_progress', now(), now())
  returning id::text as pk_b \gset
select pg_temp.chk('B5 Undo Pack (batch) → ok',
  pg_temp.run(format('select (public.wms_rollback_batch(%s, ''pack'')->>''kind'')', :'pk_b')), 'pack');
select pg_temp.chk('B6 second Undo Pack on the same batch → refused · rollback log one pack row',
  left(pg_temp.run(format('select public.wms_rollback_batch(%s, ''pack'')::text', :'pk_b')), 19)
  || ' ' || (select count(*)::text from public.wms_rollback_log where order_id = :'so_a'::uuid and action = 'pack'), 'ERR P0001: Task not 1');

-- ── c Release · Recall (판매 · 트랜스퍼) ──
-- 창구 호출과 상태 읽기는 다른 문장으로(한 select 안의 하위 질의는 호출 전 스냅숏을 본다 · 1회차 MISMATCH 다섯의 원인)
select pg_temp.run(format('select (public.so_release_to_wms(array[%L::uuid])->>''count'')', :'so_r')) as c1 \gset
select pg_temp.chk('C1 Release SO r (confirmed · allocated) → at_wms', :'c1' || ' ' || (select status from public.so where id = :'so_r'::uuid), '1 at_wms');
select pg_temp.chk('C2 second Release refused (existing behaviour)',
  pg_temp.run(format('select public.so_release_to_wms(array[%L::uuid])::text', :'so_r')), 'ERR P0001: Order SO-00000wspr is at_wms — only confirmed orders can be released — nothing was saved');
select pg_temp.run(format('select (public.so_wms_recall(array[%L::uuid])->>''count'')', :'so_r')) as c3 \gset
select pg_temp.chk('C3 Recall SO r → confirmed', :'c3' || ' ' || (select status from public.so where id = :'so_r'::uuid), '1 confirmed');
select pg_temp.run(format('select (public.tf_release(array[%L::uuid])->>''count'')', :'tf_2')) as c4 \gset
select pg_temp.chk('C4 Release transfer WSP-T2 (confirmed) → at_wms', :'c4' || ' ' || (select status from public.inv_transfer where id = :'tf_2'::uuid), '1 at_wms');
select pg_temp.chk('C5 second transfer Release refused (existing behaviour)',
  pg_temp.run(format('select public.tf_release(array[%L::uuid])::text', :'tf_2')), 'ERR P0001: Transfer WSP-T2 is at_wms — only a confirmed transfer can be released to the warehouse — nothing was saved');
select pg_temp.run(format('select (public.tf_wms_recall(array[%L::uuid])->>''count'')', :'tf_2')) as c6 \gset
select pg_temp.chk('C6 Recall transfer WSP-T2 → confirmed', :'c6' || ' ' || (select status from public.inv_transfer where id = :'tf_2'::uuid), '1 confirmed');
select pg_temp.chk('C7 Release two orders in one call still works (pre-lock on many ids) · SO r again + listed twice refused',
  pg_temp.run(format('select (public.so_release_to_wms(array[%L::uuid])->>''count'')', :'so_r'))
  || ' ' || left(pg_temp.run(format('select public.tf_release(array[%L::uuid, %L::uuid])::text', :'tf_2', :'tf_2')), 37), '1 ERR P0001: A transfer is listed twice');

-- ── d Wave 둘 차례로 · 토트 순서 · 트랜스퍼 섞기 · Unwave ──
select pg_temp.run(format('select public.wms_wave_create(array[%L::uuid, %L::uuid])::text', :'so_w2', :'so_w1')) as wv1 \gset
select pg_temp.run(format('select public.wms_wave_create(array[%L::uuid, %L::uuid])::text', :'so_w3', :'tf_3')) as wv2 \gset
select pg_temp.chk('D1 two waves in a row today → labels n+1 · n+2',
  coalesce((:'wv1'::jsonb)->>'label', :'wv1') || ' ' || coalesce((:'wv2'::jsonb)->>'label', :'wv2'),
  :'wv_pfx' || (:wv_n0 + 1) || ' ' || :'wv_pfx' || (:wv_n0 + 2));
select pg_temp.chk('D2 tote numbers follow the given order (w2 = tote 1 · w1 = tote 2) — lock order is sorted, walk order is not',
  (select string_agg(t.batch_label || '#' || t.tote_no, ',' order by t.tote_no) from public.wms_pick_tasks t join public.wms_waves w on w.id = t.wave_id where w.label = :'wv_pfx' || (:wv_n0 + 1)),
  'SO-00000wspwb-1#1,SO-00000wspwa-1#2');
select pg_temp.chk('D3 wave with a sale and a transfer: both picking · totes 1 · 2',
  (select string_agg(t.batch_label || '#' || t.tote_no, ',' order by t.tote_no) from public.wms_pick_tasks t join public.wms_waves w on w.id = t.wave_id where w.label = :'wv_pfx' || (:wv_n0 + 2))
  || ' ' || (select status from public.so where id = :'so_w3'::uuid) || '/' || (select status from public.inv_transfer where id = :'tf_3'::uuid),
  'SO-00000wspwc-1#1,WSP-T3-1#2 picking/picking');
select pg_temp.chk('D4 an order already in a wave cannot go in another wave (existing behaviour)',
  pg_temp.run(format('select public.wms_wave_create(array[%L::uuid, %L::uuid])::text', :'so_w1', :'so_b')), 'ERR P0001: Order SO-00000wspwa is picking — only orders released to the WMS can go in a wave — nothing was saved');
select pg_temp.run(format('select (public.wms_unwave(%s)->>''back_to_at_wms'')', (:'wv1'::jsonb)->>'wave_id')) as d5 \gset
select pg_temp.chk('D5 Unwave wave 1 → both orders back to at_wms · tasks gone',
  :'d5' || ' ' || (select string_agg(status, ',' order by so_number) from public.so where id in (:'so_w1'::uuid, :'so_w2'::uuid))
  || ' ' || (select count(*)::text from public.wms_pick_tasks where order_id in (:'so_w1'::uuid, :'so_w2'::uuid)), '2 at_wms,at_wms 0');
select pg_temp.chk('D6 Unwave twice: second refused (existing behaviour)',
  pg_temp.run(format('select public.wms_unwave(%s)::text', (:'wv1'::jsonb)->>'wave_id')), 'ERR P0001: Wave not found — nothing was saved');
select pg_temp.chk('D7 a new wave after the unwave counts on (labels are not reused within the day while wave 2 stands)',
  coalesce((pg_temp.run(format('select public.wms_wave_create(array[%L::uuid, %L::uuid])::text', :'so_w1', :'so_w2'))::jsonb)->>'label', 'ERR'),
  :'wv_pfx' || (:wv_n0 + 3));
select pg_temp.chk('D8 one wave per label (wms_waves_label_key) — today WSP waves 2 rows · distinct labels',
  (select count(*) || '/' || count(distinct label) from public.wms_waves w where w.label like :'wv_pfx' || '%' and w.id in (select wave_id from public.wms_pick_tasks t join public.so s on s.id = t.order_id where s.so_number like 'SO-00000wsp%')),
  '2/2');

-- ── R 끝 정합: 중복 라벨 0 · WSP 과제 수 ──
select pg_temp.chk('R1 no duplicate (doc, batch_label) anywhere',
  ((select count(*) from (select 1 from public.wms_pick_tasks where order_id is not null group by order_id, batch_label having count(*) > 1) d)
 + (select count(*) from (select 1 from public.wms_pick_tasks where transfer_id is not null group by transfer_id, batch_label having count(*) > 1) d))::text, '0');
select pg_temp.chk('R2 WSP tasks now: a-1 · T1-1 · w1-1 · w2-1 · w3-1 · T3-1 (6)',
  (select count(*)::text from public.wms_pick_tasks t left join public.so s on s.id = t.order_id left join public.inv_transfer x on x.id = t.transfer_id
    where s.so_number like 'SO-00000wsp%' or x.transfer_number like 'WSP-%'), '6');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, got, want from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
\echo '── 실제 행 무변(rollback 뒤) — 전부 t 여야 한다'
select (select count(*) from public.wms_pick_tasks) = :n_pt as pick_tasks_same, (select count(*) from public.wms_pick_task_lines) = :n_ptl as pick_lines_same,
       (select count(*) from public.wms_waves) = :n_wv as waves_same, (select count(*) from public.wms_rollback_log) = :n_rbl as rb_log_same,
       (select count(*) from public.wms_pack_tasks) = :n_pk as pack_tasks_same,
       (select count(*) from public.so) = :n_so as so_same, (select count(*) from public.inv_transfer) = :n_tf as transfer_same, (select count(*) from public.ims_staff) = :n_staff as staff_same,
       (select count(*) from public.so where so_number like 'SO-00000wsp%') + (select count(*) from public.inv_transfer where transfer_number like 'WSP-%') = :n_wsp0 as wsp_rows_same,
       (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
          and p.proname in ('so_release_to_wms', 'tf_release', 'wms_wave_create', 'wms_rollback_batch')) = :'fn_md5_0' as fn_md5_same_as_before,
       (select count(*) from pg_class where oid in (to_regclass('public.uq_picktasks_order_label'), to_regclass('public.uq_picktasks_transfer_label'))) = :n_idx0 as indexes_same_as_before;
