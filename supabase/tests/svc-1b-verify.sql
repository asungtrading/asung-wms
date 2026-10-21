-- svc-1b-verify.sql — 서비스 길(channel service) · so_service_confirm · so_service_invoice · 늘 따로(판정 590 · 593 ~ 597):
--   ① 동일성(물건 오더 넷 — warehouse Ship & invoice · counter · pos · 같은 청구처 물건 오더 둘 한 장 — \i 앞 · 뒤 같은 재료 · I1) · ② 결함 판(S0 · 시험 전용) · ③ 새 길(N1 ~ N8) · ④ 안 나옴(N7) · 무접촉(G0 · G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021180840_svc_1b_service_channel.sql -f supabase/tests/svc-1b-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · I1 셋은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 수 − 2 · MISMATCH 0
--   가짜 재료는 전부 SVC1B(손님 · 제품 · 서비스 · 직원 넷: S sales manager · SV sales supervisor(so_unconfirm · 이 DB 는 supervisor > manager) · SW sales worker · W 없음) · 오더 번호는 so_create 가 당긴다(so_number_seq · so_invoice_number_seq 머리 → rollback 뒤 greatest)
--   ⚠️ 동일성의 각 경우는 pg_temp.scn 이 서브트랜잭션 안에서 재료를 만들고 끝까지 돌린 뒤 결과를 예외 메시지로 꺼내고 되감는다(쓰기 0) · 번호 · uuid · 시각 · 숫자 id 는 norm 으로 지운다

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021180840' \gset
select :n_applied as schema_migrations_rows_for_20261021180840;
select last_value as so_seq_last, is_called as so_seq_called from public.so_number_seq \gset
select last_value as inv_seq_last, is_called as inv_seq_called from public.so_invoice_number_seq \gset
select :so_seq_last as so_seq_head, :'so_seq_called' as so_called, (select max(substring(so_number from '[0-9]+')::bigint) from public.so) as so_max_head,
       :inv_seq_last as inv_seq_head, :'inv_seq_called' as inv_called, (select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$') as inv_max_head;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.norm(p text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''),
           '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g'),
           '"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+"', '"T"', 'g'),
           'SO-[0-9]{5,}', 'SO-#', 'g'),
           '("invoice_number": ")[0-9]+"', '\1#"', 'g'),
           '("[a-z_]*id"): [0-9]+', '\1: 0', 'g') $$;
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 오더 묶음의 자취(한 글) — 상태 · 시각 칸 · 인보이스(장 · 줄 종류 · 합계) · 원장 · 예약
create function pg_temp.trace(p_ids uuid[]) returns text language sql security definer as $$
  select 'so:' || coalesce((select string_agg(s.status || '|' || (s.shipped_at is not null) || '|' || (s.invoiced_at is not null) || '|' || (s.closed_at is not null) || '|' || (s.shipped_by is not null), ',' order by s.so_number) from public.so s where s.id = any(p_ids)), '-')
      || ' inv:' || coalesce((select string_agg(i.status || '|' || trim_scale(i.total) || '|' || trim_scale(i.tax_amount) || '|' || trim_scale(i.charges_amount) || '|' || (i.due_on - i.issued_on) || '|' || i.payment_term_name, ',' order by i.invoice_number)
                              from public.so_invoice i where i.id in (select o.invoice_id from public.so_invoice_order o where o.so_id = any(p_ids))), '-')
      || ' invl:' || coalesce((select string_agg(l.kind || '|' || coalesce(trim_scale(l.qty)::text, '-') || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount), ',' order by l.invoice_id, l.line_no)
                               from public.so_invoice_line l where l.invoice_id in (select o.invoice_id from public.so_invoice_order o where o.so_id = any(p_ids))), '-')
      || ' io:' || (select count(*) from public.so_invoice_order o where o.so_id = any(p_ids) and o.cancelled_at is null)
      || ' ledger:' || coalesce((select string_agg(l.doc_type || '|' || l.event_type || '|' || trim_scale(l.qty_delta), ',' order by l.id) from public.inv_ledger l where l.doc_number in (select s.so_number from public.so s where s.id = any(p_ids))), '-')
      || ' reserve:' || (select count(*) from public.so_reserve r join public.so_line x on x.id = r.so_line_id where x.so_id = any(p_ids) and r.released_at is null) $$;
-- 동일성 한 경우 — 재료를 만들고 끝까지 돌린 뒤 되감는다 · 결과 = {ret, trace} (uuid · 번호 · 시각은 norm 으로 지운다)
create function pg_temp.scn(p_code text, p_claims text, p_cust uuid, p_pid uuid, p_wh uuid, p_bin text, p_rule uuid, p_rule_name text) returns jsonb language plpgsql as $$
declare v_so uuid; v_so2 uuid; v_l uuid; v_l2 uuid; v_x jsonb; v_ret jsonb; v_ids uuid[];
begin
  begin
    perform set_config('request.jwt.claims', p_claims, true);
    if p_code = 'A' or p_code = 'D' then
      v_x := public.so_create(p_cust, 'warehouse', 'manual', p_wh, 'svc-1b ident ' || p_code);  v_so := (v_x->>'id')::uuid;
      v_x := public.so_line_add(v_so, p_pid, 5, 9.00, null, null, null, false);  v_l := (v_x->'line'->>'id')::uuid;
      execute 'set local session_replication_role = replica';
      update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
      execute 'set local session_replication_role = origin';
      v_x := public.so_confirm(v_so, null, false, true);
      v_ids := array[v_so];
      if p_code = 'D' then
        v_x := public.so_create(p_cust, 'warehouse', 'manual', p_wh, 'svc-1b ident D2');  v_so2 := (v_x->>'id')::uuid;
        v_x := public.so_line_add(v_so2, p_pid, 2, 9.00, null, null, null, false);  v_l2 := (v_x->'line'->>'id')::uuid;
        execute 'set local session_replication_role = replica';
        update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so2;
        execute 'set local session_replication_role = origin';
        v_x := public.so_confirm(v_so2, null, false, true);
        v_ids := array[v_so, v_so2];
      end if;
      execute 'set local session_replication_role = replica';
      update public.so set status = 'packed' where id = any(v_ids) and status = 'confirmed';
      execute 'set local session_replication_role = origin';
      if p_code = 'A' then
        v_ret := public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', v_so, 'picks', jsonb_build_array(jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', 5)))), true, null);
      else
        v_ret := public.so_finalize(jsonb_build_array(jsonb_build_object('so_id', v_so, 'picks', jsonb_build_array(jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', 5))),
                                                      jsonb_build_object('so_id', v_so2, 'picks', jsonb_build_array(jsonb_build_object('line_id', v_l2, 'bin', p_bin, 'qty', 2)))), true, null);
      end if;
    elsif p_code = 'B' then
      v_x := public.so_create(p_cust, 'counter', 'manual', p_wh, 'svc-1b ident B');  v_so := (v_x->>'id')::uuid;
      v_x := public.so_line_add(v_so, p_pid, 3, 9.00, null, null, null, false);  v_l := (v_x->'line'->>'id')::uuid;
      execute 'set local session_replication_role = replica';
      update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
      execute 'set local session_replication_role = origin';
      v_x := public.so_pos_confirm(v_so);
      v_ret := public.so_counter_ship(v_so, jsonb_build_array(jsonb_build_object('line_id', v_l, 'bin', p_bin, 'qty', 3)), true);
      v_ids := array[v_so];
    else
      v_x := public.so_create(p_cust, 'pos', 'pos', p_wh, 'svc-1b ident C');  v_so := (v_x->>'id')::uuid;
      v_x := public.so_line_add(v_so, p_pid, 2, 9.00, null, null, null, false);
      execute 'set local session_replication_role = replica';
      update public.so set tax_rule_id = p_rule, tax_rule = p_rule_name, tax_rule_manual = true where id = v_so;
      execute 'set local session_replication_role = origin';
      v_x := public.so_pos_confirm(v_so);
      v_ret := public.so_pos_finish(v_so, true);
      v_ids := array[v_so];
    end if;
    raise exception using errcode = 'P7777', message = jsonb_build_object('ret', v_ret, 'trace', pg_temp.trace(v_ids))::text;
  exception when sqlstate 'P7777' then
    return sqlerrm::jsonb;
  when others then
    return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
  end;
end $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'ck_service=' || ((select pg_get_constraintdef(oid) from pg_constraint where conrelid = 'public.so'::regclass and conname = 'so_channel_ck') ~ '''service''')::text
      || ' confirm_fn=' || (to_regprocedure('public.so_service_confirm(uuid)') is not null)::text
      || ' invoice_fn=' || (to_regprocedure('public.so_service_invoice(uuid, date, boolean)') is not null)::text
      || ' guard_pair=' || (select (p.prosrc ~ '''pos'', ''counter'', ''service''')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_status_guard')
      || ' issue_alone=' || (select (p.prosrc ~ 'invoiced on its own')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_invoice_issue')
      || ' line_add_refuse=' || (select (p.prosrc ~ 'service lines only')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_line_add')
      || ' paste_refuse=' || (select (p.prosrc ~ 'service lines only')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_lines_paste')
      || ' gate_branch=' || (select (p.prosrc ~ 'unconfirm it first')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'so_charge_gate')
      || ' pos_refuse=' || (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_pos_confirm', 'so_pos_reopen') and p.prosrc ~ 'is a service order')::text $$;
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'so=' || (select count(*) || '/' || md5(string_agg(s.id::text || s.status || s.channel || coalesce(s.shipped_at::text, '-') || coalesce(s.invoiced_at::text, '-'), ',' order by s.id)) from public.so s join public.customer c on c.id = s.customer_id where c.name <> 'SVC1B Customer')
      || ' inv=' || (select count(*) || '/' || md5(coalesce(string_agg(i.id::text || i.status || i.total, ',' order by i.id), '')) from public.so_invoice i where i.bill_to_customer_id not in (select id from public.customer where name = 'SVC1B Customer'))
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where sku not like 'SVC1B-%')
      || ' charges=' || (select count(*) from public.so_charge c join public.so s on s.id = c.so_id join public.customer cu on cu.id = s.customer_id where cu.name <> 'SVC1B Customer')
      || ' fns=' || (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
                     and p.proname in ('so_confirm', 'so_unconfirm', 'so_confirm_precheck', 'so_ship', 'so_pos_complete', 'so_pos_finish', 'so_counter_ship', 'so_finalize', 'so_invoice_cancel', 'so_cancel', 'so_charge_set', 'so_charge_remove', 'so_merge', 'so_divide', 'so_release_to_wms', 'so_backorder_overview', 'so_pos_open_list', 'so_tax_preview')) $$;

\echo '── M0) 가짜 직원 넷(S sales manager · SV sales supervisor · SW sales worker · W 없음) · 손님(기본 브랜치 · CAD · Net 30) · 제품 + 칸 재고 50 · 서비스 0.45 · 세율 · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1b-s@test.invalid', 'SVC1B S', 'manager', '["ims","sales"]', '{}') returning auth_user_id::text as s_uid, id::text as s_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1b-sw@test.invalid', 'SVC1B SW', 'worker', '["ims","sales"]', '{}') returning auth_user_id::text as sw_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1b-w@test.invalid', 'SVC1B W', 'worker', '[]', '{}') returning auth_user_id::text as w_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'svc1b-sv@test.invalid', 'SVC1B SV', 'supervisor', '["ims","sales"]', '{}') returning auth_user_id::text as sv_uid \gset
\set s  '{"sub":"' :s_uid  '","role":"authenticated"}'
\set sw '{"sub":"' :sw_uid '","role":"authenticated"}'
\set w  '{"sub":"' :w_uid  '","role":"authenticated"}'
\set sv '{"sub":"' :sv_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.name as bina from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
select rt.name as tier_name from public.ref_price_tier rt where rt.purpose = 'sale' and rt.is_active order by rt.name limit 1 \gset
select id::text as r13, name as r13_name, rate_pct as r13_rate from public.ref_tax_rule where name = 'HST ON (Sale)' and is_active \gset
select id::text as pt30, name as pt30_name from public.ref_payment_term where is_active and net_days = 30 and not coalesce(is_split, false) order by name limit 1 \gset
set local session_replication_role = replica;
insert into public.customer (name, source, price_tier, default_location_id, discount_pct, currency_id, payment_term_id, payment_term_name) values ('SVC1B Customer', 'manual', :'tier_name', :'wh'::uuid, 0, :'cad'::uuid, :'pt30'::uuid, :'pt30_name') returning id::text as cust \gset
insert into public.product (sku, name, source) values ('SVC1B-P', 'SVC1B Product', 'manual') returning id::text as pid \gset
insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source) values (public.ims_today() - 3, 1, 'SVC1B-P', :'whname', :'bina', 50, 'po_in', 'purchase', 'PO-SVC1B', 'svc1b-1', 'manual');
insert into public.ref_service (name, unit_price) values ('SVC1B Prep service', 0.45) returning id::text as svc \gset
set local session_replication_role = origin;
select pg_temp.real_rows() as real_before, pg_temp.gate_state() as gate_before \gset
select pg_temp.chk(format('M0 staff ×4 · customer (branch %s · %s) · product SVC1B-P stock 50 in %s · service 0.45 · tax %s %s%% · snapshots taken', :'whname', :'pt30_name', :'bina', :'r13_name', trim_scale(:'r13_rate'::numeric)),
  :'s_uid' <> '' and :'sv_uid' <> '' and :'cust' <> '' and :'pid' <> '' and :'svc' <> '' and :'r13' <> '' and :'pt30' <> '' and :'real_before' <> '', 'see M0');

create temp table t_ident (phase text, c text, ret text, trace text);
create function pg_temp.ident(p_phase text, p_claims text, p_cust uuid, p_pid uuid, p_wh uuid, p_bin text, p_rule uuid, p_rule_name text) returns int language plpgsql as $$
declare v jsonb; c record; v_n int := 0;
begin
  for c in select * from (values ('A', 'A warehouse: create · line 5 @9 · confirm · packed · Ship & invoice'), ('B', 'B counter: create · line 3 · pos confirm · counter ship + invoice'), ('C', 'C pos: create · line 2 · pos confirm · finish'), ('D', 'D bundle: two warehouse orders → so_finalize → one invoice')) t(code, name) loop
    v := pg_temp.scn(c.code, p_claims, p_cust, p_pid, p_wh, p_bin, p_rule, p_rule_name);
    insert into t_ident values (p_phase, c.name, pg_temp.norm(coalesce((v->'ret')::text, v->>'err')), pg_temp.norm(v->>'trace'));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — channel service 는 so_create 가 거부(길 셋) · 비용 줄만 있는 오더 확정은 「has no lines」 · 새 창구 둘 없음'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''service'', ''manual'', null, ''svc-1b S0'')::text', :'cust')) as s0_create \gset
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''svc-1b S0 charges only'')::text', :'cust', :'wh')) as s0_w \gset
reset role;
select coalesce(pg_temp.j(:'s0_w')->>'id', '00000000-0000-0000-0000-000000000000') as s0_so \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'s0_so'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 1200, p_service_id => %L::uuid)::text', :'s0_so', :'svc')) as s0_ch \gset
select pg_temp.as_user(:'s', format('select public.so_confirm(%L::uuid, null, false, true)::text', :'s0_so')) as s0_conf \gset
reset role;
select pg_temp.chk('S0 before the trial: so_create service refused (not one of warehouse, pos, counter) · a warehouse order with only a 540 service line cannot be confirmed (has no lines) · no service functions · not in schema_migrations',
  :'s0_create' like 'ERR%' and :'s0_create' like '%not one of warehouse, pos, counter —%' and :'s0_ch' not like 'ERR%' and (pg_temp.j(:'s0_ch')->'charge'->>'amount')::numeric = 540
  and :'s0_conf' like 'ERR%' and :'s0_conf' like '%has no lines%'
  and :'gate_before' = 'ck_service=false confirm_fn=false invoice_fn=false guard_pair=false issue_alone=false line_add_refuse=false paste_refuse=false gate_branch=false pos_refuse=0' and :n_applied = 0,
  format('create %s | charge %s | confirm %s | gate %s', left(:'s0_create', 160), left(:'s0_ch', 120), left(:'s0_conf', 160), :'gate_before'));
\echo '── I0) 동일성 — 옛 판으로 네 경우(되감김)'
select pg_temp.ident('old', :'s', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name') as old_n \gset
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: untouched functions same md5 · real rows unchanged', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));
\echo '── I1) 동일성 — 새 판으로 같은 네 경우 · 비교'
select pg_temp.ident('new', :'s', :'cust'::uuid, :'pid'::uuid, :'wh'::uuid, :'bina', :'r13'::uuid, :'r13_name') as new_n \gset
select count(*) as n_cases, count(*) filter (where o.ret = n.ret and o.trace = n.trace) as same, count(*) filter (where o.ret like 'ERR%' or o.ret like '%"err"%') as n_err,
       coalesce(string_agg(o.c || ': ' || left(o.ret, 300) || ' ≠ ' || left(n.ret, 300) || ' // ' || o.trace || ' ≠ ' || n.trace, ' || ') filter (where o.ret <> n.ret or o.trace <> n.trace), '-') as diff_detail,
       coalesce(string_agg(o.c || ': ' || o.trace, ' || ' order by o.c), '-') as traces
  from t_ident o join t_ident n on n.c = o.c and n.phase = 'new' where o.phase = 'old' \gset
select pg_temp.chk(format('I1 old paths A ~ D (warehouse Ship & invoice · counter · pos · two orders one invoice): %s of %s cases same return and same trace (status · shipped/invoiced/closed · invoice totals · lines · ledger · reserves) · none errored', :same, :n_cases),
  :n_cases = 4 and :same = 4 and :n_err = 0, format('diff %s | traces %s', :'diff_detail', :'traces'));
\else
select pg_temp.chk('P0c confirm run: migration 20261021180840 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() = 'ck_service=true confirm_fn=true invoice_fn=true guard_pair=true issue_alone=true line_add_refuse=true paste_refuse=true gate_branch=true pos_refuse=2') as landed \gset
\if :landed
\echo '── G1) 실물'
select pg_temp.chk('G1 CHECK service · so_service_confirm · so_service_invoice (authenticated yes · anon no · definer) · guard pair · issue alone · line_add/paste refuse · gate branch · pos refuse ×2',
  pg_temp.gate_state() = 'ck_service=true confirm_fn=true invoice_fn=true guard_pair=true issue_alone=true line_add_refuse=true paste_refuse=true gate_branch=true pos_refuse=2'
  and has_function_privilege('authenticated', 'public.so_service_confirm(uuid)', 'execute') and not has_function_privilege('anon', 'public.so_service_confirm(uuid)', 'execute')
  and has_function_privilege('authenticated', 'public.so_service_invoice(uuid, date, boolean)', 'execute') and not has_function_privilege('anon', 'public.so_service_invoice(uuid, date, boolean)', 'execute')
  and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_service_confirm', 'so_service_invoice') and p.prosecdef) = 2, pg_temp.gate_state());

\echo '── N1) 서비스 오더 — 만들기(창고 안 줌 → 손님 기본 브랜치 · channel service · intake manual · SO 번호) → 서비스 줄 1200 × 0.45 = 540 → 확정(SW sales worker · 역할 문 없음) → 미리 보기 → 발행 → 인보이스 한 장 540 + 13% = 610.20 · Due = 발행일 + 30 · fulfilled · 원장 · 예약 · WMS 0'
set local role authenticated;
select pg_temp.as_user(:'sw', format('select public.so_create(%L::uuid, ''service'', ''manual'', null, ''svc-1b N1'')::text', :'cust')) as n1_create \gset
reset role;
select coalesce(pg_temp.j(:'n1_create')->>'id', '00000000-0000-0000-0000-000000000000') as so1, coalesce(pg_temp.j(:'n1_create')->>'so_number', '?') as so1_no \gset
set local role authenticated;
select pg_temp.as_user(:'sw', format('select public.so_service_confirm(%L::uuid)::text', :'so1')) as n1_conf0 \gset
select pg_temp.as_user(:'sw', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 1200, p_service_id => %L::uuid)::text', :'so1', :'svc')) as n1_ch \gset
select pg_temp.as_user(:'sw', format('select public.so_service_confirm(%L::uuid)::text', :'so1')) as n1_conf1 \gset
reset role;
select coalesce(pg_temp.j(:'n1_ch')->'charge'->>'id', '00000000-0000-0000-0000-000000000000') as ch1 \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'so1'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'sw', format('select public.so_service_confirm(%L::uuid)::text', :'so1')) as n1_conf \gset
select pg_temp.as_user(:'sw', format('select public.so_service_invoice(%L::uuid, null, false)::text', :'so1')) as n1_prev \gset
select pg_temp.as_user(:'sw', format('select public.so_service_invoice(%L::uuid, null, true)::text', :'so1')) as n1_inv \gset
reset role;
select coalesce(pg_temp.j(:'n1_inv')->>'invoice_id', '00000000-0000-0000-0000-000000000000') as inv1 \gset
select (select s.status || '|' || s.channel || '|' || s.intake || '|' || (s.location_id = :'wh'::uuid) || '|' || (s.shipped_at is not null) || '|' || (s.shipped_by::text = :'sw_uid' or s.shipped_by is not null) || '|' || (s.invoiced_at is not null) || '|' || (s.closed_at is not null) from public.so s where s.id = :'so1'::uuid) as n1_so,
       (select i.status || '|' || trim_scale(i.charges_amount) || '|' || trim_scale(i.tax_amount) || '|' || trim_scale(i.total) || '|' || (i.due_on - i.issued_on) || '|' || i.payment_term_name from public.so_invoice i where i.id = :'inv1'::uuid) as n1_i,
       (select string_agg(l.kind || '|' || trim_scale(l.amount) || '|' || trim_scale(l.tax_amount) || '|' || (l.so_charge_id = :'ch1'::uuid), ',' order by l.line_no) from public.so_invoice_line l where l.invoice_id = :'inv1'::uuid) as n1_il,
       (select count(*) from public.inv_ledger l where l.doc_number = :'so1_no') as n1_ledger,
       (select count(*) from public.so_reserve r join public.so_line x on x.id = r.so_line_id where x.so_id = :'so1'::uuid) as n1_res,
       (select count(*) from public.so_line where so_id = :'so1'::uuid) as n1_lines \gset
select pg_temp.chk(format('N1 service order %s: created with branch = customer default · channel service · intake manual · confirm before any line refused · 540 service line · confirm before tax refused · confirm OK (so_confirm shape · committed · services 1/540 · totals) · preview 610.20 due +30 · invoice OK · so %s · invoice %s · lines %s · ledger %s · reserves %s · product lines %s', :'so1_no', :'n1_so', :'n1_i', :'n1_il', :n1_ledger, :n1_res, :n1_lines),
  :'n1_create' not like 'ERR%' and pg_temp.j(:'n1_create')->>'channel' = 'service' and pg_temp.j(:'n1_create')->>'location_id' = :'wh' and :'so1_no' ~ '^SO-[0-9]{5}$'
  and :'n1_conf0' like 'ERR%' and :'n1_conf0' like '%has no service lines%'
  and :'n1_ch' not like 'ERR%' and (pg_temp.j(:'n1_ch')->'charge'->>'amount')::numeric = 540
  and :'n1_conf1' like 'ERR%' and :'n1_conf1' like '%has no tax rule%'
  and :'n1_conf' not like 'ERR%' and pg_temp.j(:'n1_conf')->>'status' = 'confirmed' and pg_temp.j(:'n1_conf')->>'committed' = 'true' and (pg_temp.j(:'n1_conf')->'services'->>'amount')::numeric = 540 and pg_temp.j(:'n1_conf') ? 'lines' and pg_temp.j(:'n1_conf') ? 'warnings'
  and :'n1_prev' not like 'ERR%' and pg_temp.j(:'n1_prev')->>'committed' = 'false' and (pg_temp.j(:'n1_prev')->'estimate'->>'total')::numeric = 610.20 and (pg_temp.j(:'n1_prev')->>'due_on')::date = public.ims_today() + 30
  and :'n1_inv' not like 'ERR%' and pg_temp.j(:'n1_inv')->>'committed' = 'true' and pg_temp.j(:'n1_inv')->>'status' = 'fulfilled' and (pg_temp.j(:'n1_inv')->'totals'->>'total')::numeric = 610.20 and (pg_temp.j(:'n1_inv')->>'due_on')::date = public.ims_today() + 30
  and :'n1_so' = 'fulfilled|service|manual|true|true|true|true|true' and :'n1_i' = format('issued|540|70.2|610.2|30|%s', :'pt30_name') and :'n1_il' = 'charge|540|70.2|true'
  and :n1_ledger = 0 and :n1_res = 0 and :n1_lines = 0 and (select count(*) from public.so_invoice_order o where o.so_id = :'so1'::uuid and o.cancelled_at is null) = 1,
  format('create %s | conf0 %s | ch %s | conf1 %s | conf %s | prev %s | inv %s', left(:'n1_create', 200), left(:'n1_conf0', 120), left(:'n1_ch', 120), left(:'n1_conf1', 120), left(:'n1_conf', 400), left(:'n1_prev', 400), left(:'n1_inv', 400)));

\echo '── N2) 확정 뒤 서비스 줄 고치기 · 지우기 거부 → 확정 풀기(so_unconfirm · SV supervisor · S manager · SW worker 거부 — ims_role_rank: supervisor > manager) → draft → 1000 으로 고침 → 다시 확정 → 발행 450 + 58.50 = 508.50'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''service'', ''manual'', null, ''svc-1b N2'')::text', :'cust')) as n2_create \gset
reset role;
select coalesce(pg_temp.j(:'n2_create')->>'id', '00000000-0000-0000-0000-000000000000') as so2 \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'so2'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 1200, p_service_id => %L::uuid)::text', :'so2', :'svc')) as n2_ch \gset
reset role;
select coalesce(pg_temp.j(:'n2_ch')->'charge'->>'id', '00000000-0000-0000-0000-000000000000') as ch2 \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_service_confirm(%L::uuid)::text', :'so2')) as n2_conf \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_charge_id => %L::uuid, p_qty => 1000, p_service_id => %L::uuid)::text', :'so2', :'ch2', :'svc')) as n2_edit_refused \gset
select pg_temp.as_user(:'s', format('select public.so_charge_remove(%L::uuid)::text', :'ch2')) as n2_rm_refused \gset
select pg_temp.as_user(:'sw', format('select public.so_unconfirm(%L::uuid)::text', :'so2')) as n2_unc_sw \gset
select pg_temp.as_user(:'s', format('select public.so_unconfirm(%L::uuid)::text', :'so2')) as n2_unc_s \gset
select pg_temp.as_user(:'sv', format('select public.so_unconfirm(%L::uuid)::text', :'so2')) as n2_unc \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_charge_id => %L::uuid, p_qty => 1000, p_service_id => %L::uuid)::text', :'so2', :'ch2', :'svc')) as n2_edit \gset
select pg_temp.as_user(:'s', format('select public.so_service_confirm(%L::uuid)::text', :'so2')) as n2_conf2 \gset
select pg_temp.as_user(:'s', format('select public.so_service_invoice(%L::uuid, null, true)::text', :'so2')) as n2_inv \gset
reset role;
select pg_temp.chk('N2 after confirm: edit refused (unconfirm it first) · remove refused · unconfirm by SW (worker) and S (manager) refused (supervisor or above) · unconfirm by SV → draft (merged 0 · released 0) · edit to 1000 → 450 · confirm again · invoice 508.50',
  :'n2_conf' not like 'ERR%' and :'n2_edit_refused' like 'ERR%' and :'n2_edit_refused' like '%unconfirm it first%' and :'n2_rm_refused' like 'ERR%' and :'n2_rm_refused' like '%unconfirm it first%'
  and :'n2_unc_sw' like 'ERR%' and :'n2_unc_sw' like '%supervisor or above%' and :'n2_unc_s' like 'ERR%' and :'n2_unc_s' like '%supervisor or above%'
  and :'n2_unc' not like 'ERR%' and pg_temp.j(:'n2_unc')->>'status' = 'draft' and pg_temp.j(:'n2_unc')->'merged' = '[]'::jsonb and (pg_temp.j(:'n2_unc')->>'reserves_released')::int = 0
  and :'n2_edit' not like 'ERR%' and (pg_temp.j(:'n2_edit')->'charge'->>'amount')::numeric = 450
  and :'n2_conf2' not like 'ERR%' and :'n2_inv' not like 'ERR%' and (pg_temp.j(:'n2_inv')->'totals'->>'total')::numeric = 508.50 and (select status from public.so where id = :'so2'::uuid) = 'fulfilled',
  format('conf %s | edit_r %s | rm_r %s | unc_sw %s | unc_s %s | unc %s | edit %s | conf2 %s | inv %s', left(:'n2_conf', 100), left(:'n2_edit_refused', 160), left(:'n2_rm_refused', 160), left(:'n2_unc_sw', 160), left(:'n2_unc_s', 160), left(:'n2_unc', 200), left(:'n2_edit', 120), left(:'n2_conf2', 100), left(:'n2_inv', 200)));

\echo '── N3) 거부 넷 — 상품 줄 넣기(so_line_add · so_lines_paste) · 서비스 줄 0 확정 · 금액 0 확정 · 물건 오더는 so_service_confirm 거부'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''service'', ''manual'', null, ''svc-1b N3'')::text', :'cust')) as n3_create \gset
reset role;
select coalesce(pg_temp.j(:'n3_create')->>'id', '00000000-0000-0000-0000-000000000000') as so3 \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'so3'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_line_add(%L::uuid, %L::uuid, 1, 9.00, null, null, null, false)::text', :'so3', :'pid')) as n3_line \gset
select pg_temp.as_user(:'s', format('select public.so_lines_paste(%L::uuid, %L::jsonb, true)::text', :'so3', '[{"sku":"SVC1B-P","qty":1}]')) as n3_paste \gset
select pg_temp.as_user(:'s', format('select public.so_service_confirm(%L::uuid)::text', :'so3')) as n3_conf0 \gset
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 10, p_unit_price => 0, p_service_id => %L::uuid)::text', :'so3', :'svc')) as n3_ch0 \gset
select pg_temp.as_user(:'s', format('select public.so_service_confirm(%L::uuid)::text', :'so3')) as n3_conf_zero \gset
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''svc-1b N3 w'')::text', :'cust', :'wh')) as n3_w \gset
reset role;
select coalesce(pg_temp.j(:'n3_w')->>'id', '00000000-0000-0000-0000-000000000000') as so3w \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_service_confirm(%L::uuid)::text', :'so3w')) as n3_w_conf \gset
select pg_temp.as_user(:'s', format('select public.so_service_invoice(%L::uuid, null, false)::text', :'so3w')) as n3_w_inv \gset
reset role;
select pg_temp.chk('N3 product line refused (service lines only) · paste refused · confirm with no service line refused · 10 × 0 line saved but confirm refused (total 0) · warehouse order: so_service_confirm → use so_confirm · so_service_invoice → use so_finalize · nothing changed (so3 draft · 0 product lines)',
  :'n3_line' like 'ERR%' and :'n3_line' like '%service lines only%' and :'n3_paste' like 'ERR%' and :'n3_paste' like '%service lines only%'
  and :'n3_conf0' like 'ERR%' and :'n3_conf0' like '%has no service lines%' and :'n3_ch0' not like 'ERR%' and :'n3_conf_zero' like 'ERR%' and :'n3_conf_zero' like '%needs an amount above 0%'
  and :'n3_w_conf' like 'ERR%' and :'n3_w_conf' like '%confirm it with so_confirm%' and :'n3_w_inv' like 'ERR%' and :'n3_w_inv' like '%invoice it with so_finalize%'
  and (select status || '|' || (select count(*) from public.so_line where so_id = :'so3'::uuid) from public.so where id = :'so3'::uuid) = 'draft|0',
  format('line %s | paste %s | conf0 %s | ch0 %s | zero %s | w_conf %s | w_inv %s', left(:'n3_line', 140), left(:'n3_paste', 140), left(:'n3_conf0', 120), left(:'n3_ch0', 100), left(:'n3_conf_zero', 140), left(:'n3_w_conf', 140), left(:'n3_w_inv', 140)));

\echo '── N4) 늘 따로 — N1 인보이스 취소(S manager) → 오더 shipped · 같은 손님 물건 오더 shipped 와 한 장 → 거부 · 서비스 오더 둘(N1 + N2 취소) 한 장 → 거부 · 서비스 오더 하나(N1) 다시 발행 → 새 인보이스 · fulfilled'
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_invoice_cancel(%L::uuid, ''svc-1b N4'')::text', :'inv1')) as n4_cancel \gset
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''warehouse'', ''manual'', %L::uuid, ''svc-1b N4 w'')::text', :'cust', :'wh')) as n4_w \gset
reset role;
select coalesce(pg_temp.j(:'n4_w')->>'id', '00000000-0000-0000-0000-000000000000') as so4w \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_line_add(%L::uuid, %L::uuid, 1, 9.00, null, null, null, false)::text', :'so4w', :'pid')) as n4_wl \gset
reset role;
select coalesce(pg_temp.j(:'n4_wl')->'line'->>'id', '00000000-0000-0000-0000-000000000000') as so4wl \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'so4w'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_confirm(%L::uuid, null, false, true)::text', :'so4w')) as n4_wc \gset
reset role;
set local session_replication_role = replica;
update public.so set status = 'packed' where id = :'so4w'::uuid and status = 'confirmed';
set local session_replication_role = origin;
select public.so_ship(:'so4w'::uuid, jsonb_build_array(jsonb_build_object('line_id', :'so4wl', 'bin', :'bina', 'qty', 1)), :'s_id'::uuid, null)::text as n4_ws \gset
select (select status from public.so where id = :'so1'::uuid) as n4_s1, (select status from public.so where id = :'so4w'::uuid) as n4_s4 \gset
select pg_temp.as_user(:'s', format('select public.so_invoice_issue(array[%L::uuid, %L::uuid], %L::uuid, null)::text', :'so1', :'so4w', :'s_id')) as n4_mix \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_invoice_cancel(%L::uuid, ''svc-1b N4 b'')::text', pg_temp.j(:'n2_inv')->>'invoice_id')) as n4_cancel2 \gset
reset role;
select pg_temp.as_user(:'s', format('select public.so_invoice_issue(array[%L::uuid, %L::uuid], %L::uuid, null)::text', :'so1', :'so2', :'s_id')) as n4_two \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_service_invoice(%L::uuid, null, true)::text', :'so1')) as n4_again \gset
reset role;
select pg_temp.chk('N4 invoice cancelled → service order shipped · warehouse order shipped · one invoice for both refused (invoiced on its own) · two service orders refused · service order alone re-issued → new invoice · fulfilled · product order still shipped',
  :'n4_cancel' not like 'ERR%' and :'n4_s1' = 'shipped' and :'n4_wc' not like 'ERR%' and :'n4_ws' not like 'ERR%' and :'n4_s4' = 'shipped'
  and :'n4_mix' like 'ERR%' and :'n4_mix' like '%invoiced on its own%' and :'n4_cancel2' not like 'ERR%' and :'n4_two' like 'ERR%' and :'n4_two' like '%invoiced on its own%'
  and :'n4_again' not like 'ERR%' and pg_temp.j(:'n4_again')->>'invoice_id' <> :'inv1' and (pg_temp.j(:'n4_again')->'totals'->>'total')::numeric = 610.20
  and (select status from public.so where id = :'so1'::uuid) = 'fulfilled' and (select status from public.so where id = :'so4w'::uuid) = 'shipped'
  and (select count(*) from public.so_invoice_order o where o.so_id = :'so1'::uuid and o.cancelled_at is null) = 1,
  format('cancel %s | s1 %s | ws %s | s4 %s | mix %s | cancel2 %s | two %s | again %s', left(:'n4_cancel', 100), :'n4_s1', left(:'n4_ws', 100), :'n4_s4', left(:'n4_mix', 200), left(:'n4_cancel2', 80), left(:'n4_two', 200), left(:'n4_again', 200)));

\echo '── N5) 열쇠 없는 W — 만들기 · 확정 · 발행 거부 · 문지기 — 서비스 오더를 at_wms 로 못 옮긴다 · so_release_to_wms 거부 · so_pos_confirm · so_pos_reopen 거부(새 문장)'
set local role authenticated;
select pg_temp.as_user(:'w', format('select public.so_create(%L::uuid, ''service'', ''manual'', null, ''svc-1b N5'')::text', :'cust')) as n5_w_create \gset
select pg_temp.as_user(:'w', format('select public.so_service_confirm(%L::uuid)::text', :'so3')) as n5_w_conf \gset
select pg_temp.as_user(:'w', format('select public.so_service_invoice(%L::uuid, null, true)::text', :'so2')) as n5_w_inv \gset
select pg_temp.as_user(:'s', format('select public.so_create(%L::uuid, ''service'', ''manual'', null, ''svc-1b N5 b'')::text', :'cust')) as n5_create \gset
reset role;
select coalesce(pg_temp.j(:'n5_create')->>'id', '00000000-0000-0000-0000-000000000000') as so5 \gset
set local session_replication_role = replica;
update public.so set tax_rule_id = :'r13'::uuid, tax_rule = :'r13_name', tax_rule_manual = true where id = :'so5'::uuid;
set local session_replication_role = origin;
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_charge_set(p_so_id => %L::uuid, p_name => null, p_amount => null, p_qty => 100, p_service_id => %L::uuid)::text', :'so5', :'svc')) as n5_ch \gset
select pg_temp.as_user(:'s', format('select public.so_pos_confirm(%L::uuid)::text', :'so5')) as n5_pos_conf \gset
select pg_temp.as_user(:'s', format('select public.so_service_confirm(%L::uuid)::text', :'so5')) as n5_conf \gset
select pg_temp.as_user(:'s', format('select public.so_pos_reopen(%L::uuid)::text', :'so5')) as n5_pos_reopen \gset
select pg_temp.as_user(:'s', format('select public.so_release_to_wms(array[%L::uuid])::text', :'so5')) as n5_release \gset
reset role;
select pg_temp.as_user(:'s', format('update public.so set status = ''at_wms'', at_wms_at = now() where id = %L::uuid returning status', :'so5')) as n5_guard_atwms \gset
select pg_temp.as_user(:'s', format('update public.so set status = ''packed'' where id = %L::uuid returning status', :'so5')) as n5_guard_packed \gset
select pg_temp.chk('N5 W: create · confirm · invoice refused (sales permission) · so_pos_confirm on a service order → use so_service_confirm · so_pos_reopen → use so_unconfirm · so_release_to_wms refused · direct status to at_wms / packed refused by the guard · so5 still confirmed',
  :'n5_w_create' like 'ERR%' and :'n5_w_conf' like 'ERR%' and :'n5_w_inv' like 'ERR%' and :'n5_ch' not like 'ERR%'
  and :'n5_pos_conf' like 'ERR%' and :'n5_pos_conf' like '%confirm it with so_service_confirm%' and :'n5_conf' not like 'ERR%'
  and :'n5_pos_reopen' like 'ERR%' and :'n5_pos_reopen' like '%use so_unconfirm%' and :'n5_release' like 'ERR%' and :'n5_release' like '%only warehouse orders are released%'
  and :'n5_guard_atwms' like 'ERR%' and :'n5_guard_atwms' like '%cannot move from confirmed to at_wms%' and :'n5_guard_packed' like 'ERR%' and :'n5_guard_packed' like '%cannot move from confirmed to packed%'
  and (select status from public.so where id = :'so5'::uuid) = 'confirmed',
  format('w %s / %s / %s | pos_conf %s | pos_reopen %s | release %s | guard %s / %s', left(:'n5_w_create', 80), left(:'n5_w_conf', 80), left(:'n5_w_inv', 80), left(:'n5_pos_conf', 140), left(:'n5_pos_reopen', 140), left(:'n5_release', 140), left(:'n5_guard_atwms', 140), left(:'n5_guard_packed', 140)));

\echo '── N6) ④ 안 나옴 — 확정된 서비스 오더(so5 · 100 × 0.45)가 백오더 전체 · 수요 · POS 열린 목록 · WMS 공용 목록(at_wms 이상)에 없다 · 취소(draft → cancelled 공통 짝)는 된다'
set local role authenticated;
select pg_temp.as_user(:'s', 'select public.so_backorder_overview(''{}''::jsonb)::text') as n6_bo \gset
select pg_temp.as_user(:'s', 'select public.so_backorder_demand(''{}''::jsonb)::text') as n6_dem \gset
select pg_temp.as_user(:'s', format('select public.so_pos_open_list(%L::uuid)::text', :'wh')) as n6_pos \gset
reset role;
select (select count(*) from public.wms_order_doc d where d.doc_id = :'so5'::uuid and d.status not in ('draft', 'confirmed')) as n6_wms \gset
set local role authenticated;
select pg_temp.as_user(:'s', format('select public.so_cancel(%L::uuid, ''svc-1b N6'', null, true, false)::text', :'so3')) as n6_cancel \gset
reset role;
select pg_temp.chk('N6 service order absent from backorder overview · demand · pos open list · WMS doc list beyond confirmed · draft service order cancels (common pair)',
  :'n6_bo' not like 'ERR%' and position(:'so5' in :'n6_bo') = 0 and :'n6_dem' not like 'ERR%' and position(:'so5' in :'n6_dem') = 0 and :'n6_pos' not like 'ERR%' and position(:'so5' in :'n6_pos') = 0 and :n6_wms = 0
  and :'n6_cancel' not like 'ERR%' and (select status from public.so where id = :'so3'::uuid) = 'cancelled',
  format('bo %s | dem %s | pos %s | wms %s | cancel %s', left(:'n6_bo', 80), left(:'n6_dem', 80), left(:'n6_pos', 80), :n6_wms, left(:'n6_cancel', 160)));
\else
select pg_temp.chk('G1 ~ N6 skipped: svc-1b not landed', false, pg_temp.gate_state());
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real rows untouched (so · invoices · ledger · charges · untouched function md5)', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · 시퀀스 둘 되돌리기'
select (select count(*) from public.customer where name = 'SVC1B Customer') + (select count(*) from public.product where sku like 'SVC1B-%') + (select count(*) from public.ims_staff where email like 'svc1b-%') + (select count(*) from public.ref_service where name like 'SVC1B%') + (select count(*) from public.inv_ledger where sku like 'SVC1B-%') as fake_traces_left;
select setval('public.so_number_seq', greatest(coalesce((select max(substring(so_number from '[0-9]+')::bigint) from public.so), 0), :so_seq_last), :'so_seq_called'::boolean) as so_number_seq_reset_to;
select setval('public.so_invoice_number_seq', greatest(coalesce((select max(invoice_number::bigint) from public.so_invoice where invoice_number ~ '^[0-9]+$'), 0), :inv_seq_last), :'inv_seq_called'::boolean) as so_invoice_number_seq_reset_to;
select (select last_value || '|' || is_called from public.so_number_seq) as so_seq_after, (select last_value || '|' || is_called from public.so_invoice_number_seq) as inv_seq_after;
