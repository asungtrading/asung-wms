-- rcv-3-verify.sql — 열린 short 가 있으면 확정이 PO 를 열어 둔다 · short 사유가 닫기를 정한다 · PO-02055 다시 열기(판정 598 ~ 601):
--   ① 동일성(옛 길 넷 A ~ D — 다 받음 · off-invoice · Post now · a 로 갈린 PO — \i 앞 · 뒤 같은 재료 · I1) · short 길 E 의 다른 점은 둘뿐(I2) · ② 결함 판(S0 · 시험 전용) · ③ 새 길(N1 ~ N6) · ④ 데이터(D1) · 무접촉(G1 · Z1)
--   시험 적용(Claude Code): cd ~/asung/asung-wms && psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261021171531_rcv_3_short_keeps_po_open.sql -f supabase/tests/rcv-3-verify.sql
--   확인(Caleb · 적용된 DB):  같은 명령에서 -v mig=… 만 뺀다 — 시험 갈래 S0 · G0 · I1 · I2 넷은 확인 갈래에 없다 · 확인 갈래는 P0c 하나 더 ⇒ 기대 OK = 시험 OK 수 − 3 · MISMATCH 0
--   가짜 재료는 전부 RCV3-/PO-797xx/RCV-797xx · 가짜 직원 둘(O receiving + purchasing · W 없음) · ⚠️ PO-02055 는 D1 의 단언만(새 입고를 시작하지 않는다 — 실제 PO 에 행이 생긴다)
--   번호 시퀀스 po_receipt_number_seq(N1 의 po_receipt_create)는 머리에서 읽고 rollback 뒤 greatest(실제 최대, 머리)
--   ⚠️ 동일성의 각 경우는 pg_temp.scn 이 서브트랜잭션 안에서 재료를 만들고 끝까지 돌린 뒤 결과를 예외 메시지로 꺼내고 되감는다(쓰기 0)

\echo '── db_role · schema_migrations · 시퀀스 머리'
select (select value from public.inv_config where key = 'db_role') as db_role;
select count(*) as n_applied from supabase_migrations.schema_migrations where version = '20261021171531' \gset
select :n_applied as schema_migrations_rows_for_20261021171531;
select last_value as rcv_seq_last, is_called as rcv_seq_called from public.po_receipt_number_seq \gset
select :rcv_seq_last as po_receipt_number_seq_head, :'rcv_seq_called' as rcv_called_head, (select max(substring(receipt_number from '[0-9]+')::bigint) from public.po_receipt where receipt_number ~ '^RCV-[0-9]+$' and receipt_number not like 'RCV-797%') as rcv_max_head;

begin;
set local statement_timeout = '600s';

\echo '── 도우미'
create function pg_temp.chk(p_tag text, p_ok boolean, p_detail text) returns text
  language sql security definer as $$ select case when p_ok then 'OK ' || p_tag else 'MISMATCH (' || p_tag || '): ' || coalesce(p_detail, '(null)') end $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
create function pg_temp.norm(p text) returns text language sql immutable as $$
  select regexp_replace(regexp_replace(regexp_replace(coalesce(p, ''), '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '#', 'g'), '"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.+-]+"', '"T"', 'g'), '("[a-z_]*id"): [0-9]+', '\1: 0', 'g') $$;   -- uuid · 시각 · 번호 id(layer_id 등)는 실행마다 다르다
create function pg_temp.as_user(p_claims text, p_sql text) returns text language plpgsql as $$
declare v text;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute p_sql into v;
  return coalesce(v, '(null)');
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 입고 한 장의 장부 자취 + 그 PO 묶음의 상태(한 글)
create function pg_temp.trace(p_rcv text, p_po text) returns text language sql security definer as $$
  select 'ledger:' || coalesce((select string_agg(l.sku || '|' || l.bin || '|' || trim_scale(l.qty_delta) || '|' || l.event_type || '|' || regexp_replace(l.line_ref, '^[0-9a-f-]{36}', '#'), ',' order by l.id) from public.inv_ledger l where l.doc_number = p_rcv), '-')
      || ' layers:' || coalesce((select string_agg(y.sku || '|' || trim_scale(y.qty) || '|' || trim_scale(y.unit_cost) || '|' || y.cost_source || '|' || regexp_replace(y.line_ref, '^[0-9a-f-]{36}', '#'), ',' order by y.id) from public.inv_layer y where y.doc_number = p_rcv), '-')
      || ' diffs:' || coalesce((select string_agg(d.kind || '|' || trim_scale(d.expected_qty) || '|' || trim_scale(d.received_qty) || '|' || coalesce(d.resolution, '-'), ',' order by d.created_at, d.kind) from public.po_receipt_diff d join public.po_receipt r on r.id = d.receipt_id where r.receipt_number = p_rcv), '-')
      || ' po:' || coalesce((select string_agg(x.po_number || '|' || x.status || '|' || (x.closed_at is not null), ',' order by x.po_number) from public.po x where x.po_number = p_po or x.po_number like p_po || '%'), '-')
      || ' rcv:' || coalesce((select r.status from public.po_receipt r where r.receipt_number = p_rcv), '-') $$;
-- 시나리오 하나 — 재료를 만들고 끝까지 돌린 뒤 되감는다 · 결과 = {ret, trace}
create function pg_temp.scn(p_code text, p_claims text, p_st uuid, p_sup uuid, p_wh uuid, p_bin uuid, p_cad uuid, p_d0 date) returns jsonb language plpgsql as $$
declare v_pid uuid; v_po uuid; v_l uuid; v_i uuid; v_r uuid; v_w jsonb; v_wid uuid; v_ret jsonb; v_x jsonb;
        v_pon text := 'PO-797' || p_code; v_rn text := 'RCV-797' || p_code; v_sku text := 'RCV3-P' || p_code;
        v_po_qty numeric := 600; v_inv_qty numeric := 600; v_count numeric;
begin
  begin
    perform set_config('request.jwt.claims', p_claims, true);
    execute 'set local session_replication_role = replica';
    insert into public.product (sku, name, source) values (v_sku, 'RCV3 ' || p_code, 'manual') returning id into v_pid;
    insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at) values (v_pon, 'confirmed', p_sup, p_cad, null, p_d0, p_wh, now()) returning id into v_po;
    insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (v_po, 1, v_pid, v_po_qty, 2.00) returning id into v_l;
    if p_code = '13' then v_inv_qty := 400; end if;                                                         -- D: 인보이스가 적다 → 확정하면 a 로 갈린다
    insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at)
      values (p_sup, 'RCV3-I' || p_code, p_d0, p_cad, null, v_inv_qty * 2.5, case when p_code = '13' then 'draft' else 'confirmed' end, 'invoice', case when p_code = '13' then null else now() end) returning id into v_i;
    insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (v_i, 1, 'goods', v_l, v_inv_qty, 2.50, true);
    execute 'set local session_replication_role = origin';
    if p_code = '13' then
      v_x := public.po_invoice_confirm(v_i, true);                                                          -- 갈라짐: PO-79713(400) + PO-79713a(200)
    end if;
    execute 'set local session_replication_role = replica';
    insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by) values (v_rn, v_po, p_wh, p_d0, 'draft', p_st) returning id into v_r;
    execute 'set local session_replication_role = origin';
    v_count := case p_code when '11' then 650 when '13' then 400 when '14' then 400 else 600 end;        -- B 더 옴 · D 갈라진 뒤 400 · E 덜 옴
    v_w := public.po_receipt_work_save(v_r, v_l, v_count, 'manual');
    v_wid := (v_w->>'work_id')::uuid;
    if p_code = '12' then                                                                                  -- C: 100 을 칸에 쪼개 먼저 반영 · 나머지 500 은 확정 때
      v_x := public.po_receipt_work_split(v_wid, 100, p_bin);
      v_x := public.po_receipt_post_now(v_r, (select jsonb_agg(w.id) from public.po_receipt_work w where w.receipt_id = v_r and w.bin_id = p_bin), true);
    end if;
    for v_wid in select w.id from public.po_receipt_work w where w.receipt_id = v_r and w.bin_id is null loop v_x := public.po_receipt_work_putaway(v_wid, p_bin, true); end loop;
    v_ret := public.po_receipt_confirm(v_r);
    raise exception using errcode = 'P7777', message = jsonb_build_object('ret', v_ret, 'trace', pg_temp.trace(v_rn, v_pon))::text;
  exception when sqlstate 'P7777' then
    return sqlerrm::jsonb;
  when others then
    return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
  end;
end $$;
create function pg_temp.strip_po(p jsonb) returns jsonb language sql immutable as $$
  select (p - 'warnings') || jsonb_build_object('po', ((p->'po') - 'kept_open' - 'remaining_ea' - 'outlook'), 'warnings', (select coalesce(jsonb_agg(w order by w), '[]'::jsonb) from jsonb_array_elements_text(p->'warnings') w where w not in ('po_closed', 'po_kept_open'))) $$;
create function pg_temp.gate_state() returns text language sql security definer as $$
  select 'helper=' || (to_regprocedure('public.po_receipt_keep_open(uuid, uuid)') is not null)::text
      || ' confirm_by_kept_open=' || (select (p.prosrc ~ 'po_kept_open')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_confirm_by')
      || ' resolve_closes=' || (select (p.prosrc ~ 'po_receipt_keep_open')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_diff_resolve')
      || ' reopen_reopens=' || (select (p.prosrc ~ 'po_receipt_keep_open')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_diff_reopen')
      || ' create_by_old_wording=' || (select (p.prosrc ~ 'moved to the split document')::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_create_by') $$;
create function pg_temp.real_rows() returns text language sql security definer as $$
  select 'po=' || (select count(*) || '/' || md5(string_agg(x.po_number || ':' || x.status || ':' || coalesce(x.closed_at::text, '-'), ',' order by x.po_number)) from public.po x where x.po_number not like 'PO-797%' and x.po_number <> 'PO-02055')
      || ' ledger=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_ledger where sku not like 'RCV3-%')
      || ' layers=' || (select count(*) || '/' || coalesce(sum(id), 0) from public.inv_layer where sku not like 'RCV3-%')
      || ' diffs=' || (select count(*) || '/' || md5(string_agg(d.id::text || coalesce(d.resolution, '-') || coalesce(d.resolved_at::text, '-'), ',' order by d.id)) from public.po_receipt_diff d join public.product p on p.id = d.product_id where p.sku not like 'RCV3-%')
      || ' receipts=' || (select count(*) from public.po_receipt r join public.po x on x.id = r.po_id where x.po_number not like 'PO-797%')
      || ' fns=' || (select string_agg(p.proname || '=' || md5(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_receipt_confirm', 'wms_recv_confirm', 'wms_recv_start', 'po_receipt_create', 'po_receipt_post_now_by', 'po_receipt_detail', 'inv_post_receipt', 'po_doc_cancel', 'wms_recv_complete')) $$;

\echo '── M0) 가짜 직원 둘(O receiving + purchasing + master · W 없음) · 공급처 · 참조 · 스냅샷'
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rcv3-o@test.invalid', 'RCV3 O', 'manager', '["ims","receiving","purchasing","master"]', '{}') returning auth_user_id::text as o_uid, id::text as o_id \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'rcv3-w@test.invalid', 'RCV3 W', 'worker', '[]', '{}') returning auth_user_id::text as w_uid \gset
\set o '{"sub":"' :o_uid '","role":"authenticated"}'
\set w '{"sub":"' :w_uid '","role":"authenticated"}'
select id::text as cad from public.ref_currency where code = 'CAD' \gset
select (public.ims_today() - 2)::text as d0 \gset
select id::text as wh, name as whname from public.ref_warehouse where is_active order by name limit 1 \gset
select b.id::text as bina, b.name as binaname from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active order by b.name limit 1 \gset
set local session_replication_role = replica;
insert into public.supplier (name, payment_term_name, account_payable_code) values ('RCV3 Supplier', 'Net 30', '2000') returning id::text as sup \gset
set local session_replication_role = origin;
select pg_temp.real_rows() as real_before, pg_temp.gate_state() as gate_before \gset
select (select status || '|' || coalesce(closed_at::text, '-') from public.po where po_number = 'PO-02055') as po02055_before \gset
select pg_temp.chk(format('M0 staff ×2 · supplier · warehouse %s · bin %s · PO-02055 before = %s · snapshots taken', :'whname', :'binaname', :'po02055_before'), :'o_uid' <> '' and :'sup' <> '' and :'bina' <> '' and :'real_before' <> '', 'see M0');

create temp table t_ident (phase text, c text, ret text, trace text, raw text);
create function pg_temp.ident(p_phase text, p_claims text, p_st uuid, p_sup uuid, p_wh uuid, p_bin uuid, p_cad uuid, p_d0 date) returns int language plpgsql as $$
declare v jsonb; c record; v_n int := 0;
begin
  for c in select * from (values ('10', 'A full receive 600/600'), ('11', 'B off-invoice 650/600'), ('12', 'C post now 100 then confirm 500'), ('13', 'D invoice 400 of 600 → split a · receive 400'), ('14', 'E short 400/600')) t(code, name) loop
    v := pg_temp.scn(c.code, p_claims, p_st, p_sup, p_wh, p_bin, p_cad, p_d0);
    insert into t_ident values (p_phase, c.name, pg_temp.norm(coalesce(pg_temp.strip_po(v->'ret')::text, v->>'err')), v->>'trace', pg_temp.norm(coalesce((v->'ret')::text, v->>'err')));
    v_n := v_n + 1;
  end loop;
  return v_n;
end $$;

\if :{?mig}
\echo '── S0) 결함 판(시험 전용) — 옛 길 E: 400 만 받고 확정 → PO closed · 새 입고 거부(옛 문장 「split document」) · 도우미 없음'
select pg_temp.scn('14', :'o', :'o_id'::uuid, :'sup'::uuid, :'wh'::uuid, :'bina'::uuid, :'cad'::uuid, :'d0'::date) as s0 \gset
select pg_temp.chk('S0 before the trial: E (400 of 600) → PO-79714 closed · short 600/400 open · warnings ∋ po_closed · no helper · create_by still says "moved to the split document" · not in schema_migrations',
  pg_temp.j(:'s0')->>'trace' like '%po:PO-79714|closed|true%' and pg_temp.j(:'s0')->>'trace' like '%diffs:short|600|400|-%' and (pg_temp.j(:'s0')->'ret'->'warnings') ? 'po_closed'
  and :'gate_before' = 'helper=false confirm_by_kept_open=false resolve_closes=false reopen_reopens=false create_by_old_wording=true' and :n_applied = 0,
  format('s0 %s | gate %s', left(:'s0', 400), :'gate_before'));
\echo '── I0) 동일성 — 옛 판으로 다섯 시나리오(되감김)'
select pg_temp.ident('old', :'o', :'o_id'::uuid, :'sup'::uuid, :'wh'::uuid, :'bina'::uuid, :'cad'::uuid, :'d0'::date) as old_n \gset
\echo '── \i 시험 적용'
\i :mig
select pg_temp.chk('G0 after \i: other receipt functions unchanged · real rows unchanged (PO-02055 excluded — it is reopened by the migration)', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));
\echo '── I1 ~ I2) 동일성 — 새 판으로 같은 다섯 · 비교'
select pg_temp.ident('new', :'o', :'o_id'::uuid, :'sup'::uuid, :'wh'::uuid, :'bina'::uuid, :'cad'::uuid, :'d0'::date) as new_n \gset
select count(*) as n_cases, count(*) filter (where o.ret = n.ret) as same_ret, count(*) filter (where o.trace = n.trace) as same_trace,
       coalesce(string_agg(o.c, ' | ' order by o.c) filter (where o.ret <> n.ret or o.trace <> n.trace), '-') as diff_cases,
       coalesce(string_agg(o.c || ': ' || left(o.trace, 200) || ' ≠ ' || left(n.trace, 200), ' || ') filter (where o.trace <> n.trace), '-') || ' RET ' || coalesce(string_agg(o.c || ': ' || left(o.ret, 1500) || ' ≠ ' || left(n.ret, 1500), ' || ') filter (where o.ret <> n.ret), '-') as diff_detail
  from t_ident o join t_ident n on n.c = o.c and n.phase = 'new' where o.phase = 'old' \gset
select coalesce(max(o.trace), '-') as e_old_trace, coalesce(max(n.trace), '-') as e_new_trace, coalesce(max(o.raw), '{}') as e_old_raw, coalesce(max(n.raw), '{}') as e_new_raw from t_ident o join t_ident n on n.c = o.c and n.phase = 'new' where o.phase = 'old' and o.c like 'E %' \gset
select pg_temp.chk(format('I1 old paths A ~ D (full · off-invoice · post now · split a): %s of %s cases same return (po.kept_open/remaining/outlook and po_closed/po_kept_open warnings stripped · ids · times normalized) and same ledger · layers · diffs · PO status · receipt status — the only different case is E (po.status · closed_at)', :same_ret, :n_cases),
  :n_cases = 5 and :same_ret = 4 and :same_trace = 4 and :'diff_cases' = 'E short 400/600', format('same_ret %s | same_trace %s | diff %s | detail %s', :same_ret, :same_trace, :'diff_cases', :'diff_detail'));
select pg_temp.chk('I2 case E: old → PO closed + po_closed · new → PO confirmed (closed_at null) + po_kept_open · remaining_ea 200 · ledger · layers · short diff identical',
  :'e_old_trace' like '%po:PO-79714|closed|true rcv:confirmed' and :'e_new_trace' like '%po:PO-79714|confirmed|false rcv:confirmed'
  and split_part(:'e_old_trace', ' po:', 1) = split_part(:'e_new_trace', ' po:', 1)
  and (pg_temp.j(:'e_old_raw')->'warnings') ? 'po_closed' and not ((pg_temp.j(:'e_old_raw')->'warnings') ? 'po_kept_open')
  and (pg_temp.j(:'e_new_raw')->'warnings') ? 'po_kept_open' and not ((pg_temp.j(:'e_new_raw')->'warnings') ? 'po_closed')
  and pg_temp.j(:'e_new_raw')->'po'->>'status' = 'confirmed' and pg_temp.j(:'e_new_raw')->'po'->>'closed_at' is null and (pg_temp.j(:'e_new_raw')->'po'->>'remaining_ea')::numeric = 200
  and pg_temp.j(:'e_old_raw')->'po'->>'status' = 'closed',
  format('old %s | new %s | old po %s | new po %s', :'e_old_trace', :'e_new_trace', pg_temp.j(:'e_old_raw')->'po', pg_temp.j(:'e_new_raw')->'po'));
\else
select pg_temp.chk('P0c confirm run: migration 20261021171531 applied', :n_applied = 1, format('%s rows', :n_applied));
\endif

select (pg_temp.gate_state() = 'helper=true confirm_by_kept_open=true resolve_closes=true reopen_reopens=true create_by_old_wording=false') as landed \gset
\if :landed
\echo '── G1) 실물'
select pg_temp.chk('G1 helper · confirm_by kept_open · resolve closes · reopen reopens · create_by new wording · helper ACL (authenticated yes · anon no)',
  pg_temp.gate_state() = 'helper=true confirm_by_kept_open=true resolve_closes=true reopen_reopens=true create_by_old_wording=false'
  and has_function_privilege('authenticated', 'public.po_receipt_keep_open(uuid, uuid)', 'execute') and not has_function_privilege('anon', 'public.po_receipt_keep_open(uuid, uuid)', 'execute'), pg_temp.gate_state());

\echo '── N0) 재료(새 길) — PO-79720(600 · 인보이스 600) · PO-79721(600) · PO-79722(줄 둘 600 + 50) · PO-79723(줄 둘) · PO-79724(600)'
set local session_replication_role = replica;
insert into public.product (sku, name, source) values ('RCV3-PN', 'RCV3 N', 'manual') returning id::text as pn \gset
insert into public.product (sku, name, source) values ('RCV3-PM', 'RCV3 M', 'manual') returning id::text as pm \gset
create temp table t_po (code text, po_id uuid, l1 uuid, l2 uuid);
do $$
declare c text; v_po uuid; v_l1 uuid; v_l2 uuid; v_i uuid;
begin
  foreach c in array array['20', '21', '22', '23', '24'] loop
    insert into public.po (po_number, status, supplier_id, currency_id, exchange_rate, order_date, ship_to_warehouse_id, confirmed_at)
      values ('PO-797' || c, 'confirmed', (select id from public.supplier where name = 'RCV3 Supplier'), (select id from public.ref_currency where code = 'CAD'), null, public.ims_today() - 2, (select id from public.ref_warehouse where is_active order by name limit 1), now()) returning id into v_po;
    insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (v_po, 1, (select id from public.product where sku = 'RCV3-PN'), 600, 2.00) returning id into v_l1;
    insert into public.po_invoice (supplier_id, invoice_number, invoice_date, currency_id, exchange_rate, total_amount, status, doc_kind, confirmed_at)
      values ((select id from public.supplier where name = 'RCV3 Supplier'), 'RCV3-I' || c, public.ims_today() - 2, (select id from public.ref_currency where code = 'CAD'), null, 1500, 'confirmed', 'invoice', now()) returning id into v_i;
    insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (v_i, 1, 'goods', v_l1, 600, 2.50, true);
    v_l2 := null;
    if c in ('22', '23') then
      insert into public.po_line (po_id, line_no, product_id, qty_ea, unit_price) values (v_po, 2, (select id from public.product where sku = 'RCV3-PM'), 50, 4.00) returning id into v_l2;
      insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable) values (v_i, 2, 'goods', v_l2, 50, 4.00, true);
    end if;
    insert into t_po values (c, v_po, v_l1, v_l2);
  end loop;
end $$;
set local session_replication_role = origin;
grant all on t_po to authenticated;
select po_id::text as po20, l1::text as l20 from t_po where code = '20' \gset
select po_id::text as po21, l1::text as l21 from t_po where code = '21' \gset
select po_id::text as po22, l1::text as l22a, l2::text as l22b from t_po where code = '22' \gset
select po_id::text as po23, l1::text as l23a, l2::text as l23b from t_po where code = '23' \gset
select po_id::text as po24, l1::text as l24 from t_po where code = '24' \gset
-- 입고 하나: 만들고(명시 번호 · replica) · 세고 · 칸에 놓고 · 확정 → 반환
create function pg_temp.receive(p_claims text, p_rn text, p_po uuid, p_line uuid, p_qty numeric, p_line2 uuid default null, p_qty2 numeric default null) returns text language plpgsql as $$
declare v_r uuid; v_w uuid; v_x jsonb; v_ret jsonb;
begin
  perform set_config('request.jwt.claims', p_claims, true);
  execute 'set local session_replication_role = replica';
  insert into public.po_receipt (receipt_number, po_id, warehouse_id, received_on, status, created_by)
    values (p_rn, p_po, (select id from public.ref_warehouse where is_active order by name limit 1), public.ims_today() - 1, 'draft', (select id from public.ims_staff where email = 'rcv3-o@test.invalid')) returning id into v_r;
  execute 'set local session_replication_role = origin';
  if p_qty > 0 then v_x := public.po_receipt_work_save(v_r, p_line, p_qty, 'manual'); end if;
  if p_line2 is not null and p_qty2 > 0 then v_x := public.po_receipt_work_save(v_r, p_line2, p_qty2, 'manual'); end if;
  for v_w in select w.id from public.po_receipt_work w where w.receipt_id = v_r and w.bin_id is null loop
    v_x := public.po_receipt_work_putaway(v_w, (select b.id from public.ref_bin b where b.warehouse_id = (select id from public.ref_warehouse where is_active order by name limit 1) and b.is_active order by b.name limit 1), true);
  end loop;
  v_ret := public.po_receipt_confirm(v_r);
  return v_ret::text;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
create function pg_temp.po_state(p uuid) returns text language sql security definer as $$ select x.status || '|' || (x.closed_at is not null) from public.po x where x.id = p $$;
create function pg_temp.latest_short(p_line uuid) returns text language sql security definer as $$ select coalesce((select d.id::text from public.po_receipt_diff d where d.po_line_id = p_line and d.kind = 'short' order by d.created_at desc, d.id desc limit 1), '00000000-0000-0000-0000-000000000000') $$;

\echo '── N1) PO-79720: 400 받고 확정 → confirmed · po_kept_open · po_list 에 확정 인보이스 + confirmed(WMS 목록 조건) · 미리 보기(두 번째 초안 · 0 셈)는 remaining 200 pending · 두 번째 입고 200 → 확정 → closed · 첫 short 는 그대로(이력)'
select pg_temp.receive(:'o', 'RCV-79720', :'po20'::uuid, :'l20'::uuid, 400) as n1a \gset
select pg_temp.po_state(:'po20'::uuid) as n1_s1 \gset
select (select (has_confirmed_invoice::text || '|' || status) from public.po_list where id = :'po20'::uuid) as n1_list \gset
set local role authenticated;
select pg_temp.as_user(:'o', format('select public.po_receipt_create(%L::uuid, public.ims_today(), null)::text', :'po20')) as n1_r2 \gset
reset role;
select coalesce(pg_temp.j(:'n1_r2')->>'id', '00000000-0000-0000-0000-000000000000') as r2 \gset
select public.po_receipt_keep_open(:'po20'::uuid, :'r2'::uuid)::text as n1_prev \gset
set local role authenticated;
select pg_temp.as_user(:'o', format('select public.po_receipt_work_save(%L::uuid, %L::uuid, 200, ''manual'')::text', :'r2', :'l20')) as n1_sv \gset
select coalesce(pg_temp.j(:'n1_sv')->>'work_id', '00000000-0000-0000-0000-000000000000') as w2 \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_work_putaway(%L::uuid, %L::uuid, true)::text', :'w2', :'bina')) as n1_pa \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_confirm(%L::uuid)::text', :'r2')) as n1b \gset
reset role;
select pg_temp.chk('N1 partial then rest: first confirm → PO confirmed · warnings po_kept_open · po.kept_open true · remaining 200 · po_list true|confirmed (WMS list) · second receipt started · preview pending 200 stays_open · after 200 received → PO closed · po_closed · first short still open (history) · no new short',
  :'n1a' not like 'ERR%' and (pg_temp.j(:'n1a')->'warnings') ? 'po_kept_open' and pg_temp.j(:'n1a')->'po'->>'kept_open' = 'true' and (pg_temp.j(:'n1a')->'po'->>'remaining_ea')::numeric = 200
  and :'n1_s1' = 'confirmed|false' and :'n1_list' = 'true|confirmed'
  and :'n1_r2' not like 'ERR%' and pg_temp.j(:'n1_prev')->>'after_confirm' = 'stays_open' and (pg_temp.j(:'n1_prev')->>'remaining_ea')::numeric = 200 and pg_temp.j(:'n1_prev')->'lines'->0->>'state' = 'pending'
  and :'n1b' not like 'ERR%' and (pg_temp.j(:'n1b')->'warnings') ? 'po_closed' and pg_temp.po_state(:'po20'::uuid) = 'closed|true'
  and (select count(*) || '/' || count(*) filter (where resolved_at is null) from public.po_receipt_diff d where d.po_id = :'po20'::uuid and d.kind = 'short') = '1/1',
  format('n1a %s | s1 %s | list %s | r2 %s | prev %s | n1b %s | state %s | shorts %s', left(:'n1a', 200), :'n1_s1', :'n1_list', left(:'n1_r2', 200), left(:'n1_prev', 300), left(:'n1b', 300), pg_temp.po_state(:'po20'::uuid), (select count(*) || '/' || count(*) filter (where resolved_at is null) from public.po_receipt_diff d where d.po_id = :'po20'::uuid and d.kind = 'short')));

\echo '── N2) PO-79721: 400 받고 확정(열림) → short 를 out_of_stock → closed(po.closed_now) → 되돌리기 → confirmed(reopened_now) → split_shipment → 열린 채 · create_by 는 닫힌 PO 에 새 문장'
select pg_temp.receive(:'o', 'RCV-79721', :'po21'::uuid, :'l21'::uuid, 400) as n2a \gset
select pg_temp.latest_short(:'l21'::uuid) as d21 \gset
set local role authenticated;
select pg_temp.as_user(:'o', format('select public.po_receipt_diff_resolve(%L::uuid, ''out_of_stock'', null)::text', :'d21')) as n2_res \gset
select pg_temp.po_state(:'po21'::uuid) as n2_s1 \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_create(%L::uuid, public.ims_today(), null)::text', :'po21')) as n2_closed_create \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_diff_reopen(%L::uuid, ''still coming'')::text', :'d21')) as n2_re \gset
select pg_temp.po_state(:'po21'::uuid) as n2_s2 \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_diff_resolve(%L::uuid, ''split_shipment'', null)::text', :'d21')) as n2_split \gset
select pg_temp.po_state(:'po21'::uuid) as n2_s3 \gset
reset role;
select pg_temp.chk('N2 settle out_of_stock → PO closed (closed_now true) · closed PO refuses a new receipt with the new sentence · reopen the short → PO confirmed again (reopened_now true) · settle split_shipment → stays confirmed',
  :'n2a' not like 'ERR%' and :'n2_res' not like 'ERR%' and pg_temp.j(:'n2_res')->'po'->>'closed_now' = 'true' and :'n2_s1' = 'closed|true'
  and :'n2_closed_create' like 'ERR%' and :'n2_closed_create' like '%reopen that short difference%' and :'n2_closed_create' not like '%split document%'
  and :'n2_re' not like 'ERR%' and pg_temp.j(:'n2_re')->'po'->>'reopened_now' = 'true' and :'n2_s2' = 'confirmed|false'
  and :'n2_split' not like 'ERR%' and pg_temp.j(:'n2_split')->'po'->>'closed_now' = 'false' and pg_temp.j(:'n2_split')->'po'->>'kept_open' = 'true' and :'n2_s3' = 'confirmed|false',
  format('res %s | s1 %s | create %s | re %s | s2 %s | split %s | s3 %s', left(:'n2_res', 160), :'n2_s1', left(:'n2_closed_create', 200), left(:'n2_re', 160), :'n2_s2', left(:'n2_split', 160), :'n2_s3'));

\echo '── N3) PO-79722(줄 둘): 줄 1 전부 · 줄 2 0 → short 하나 → lost_damaged → closed · PO-79723(줄 둘 다 short): 하나 split_shipment · 하나 out_of_stock → 열린 채'
select pg_temp.receive(:'o', 'RCV-79722', :'po22'::uuid, :'l22a'::uuid, 600, :'l22b'::uuid, 0) as n3a \gset
select pg_temp.latest_short(:'l22b'::uuid) as d22 \gset
select pg_temp.receive(:'o', 'RCV-79723', :'po23'::uuid, :'l23a'::uuid, 100, :'l23b'::uuid, 10) as n3b \gset
select pg_temp.latest_short(:'l23a'::uuid) as d23a, pg_temp.latest_short(:'l23b'::uuid) as d23b \gset
set local role authenticated;
select pg_temp.as_user(:'o', format('select public.po_receipt_diff_resolve(%L::uuid, ''lost_damaged'', null)::text', :'d22')) as n3_res22 \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_diff_resolve(%L::uuid, ''split_shipment'', null)::text', :'d23a')) as n3_res23a \gset
select pg_temp.as_user(:'o', format('select public.po_receipt_diff_resolve(%L::uuid, ''out_of_stock'', null)::text', :'d23b')) as n3_res23b \gset
reset role;
select pg_temp.chk('N3 two lines: only line 2 short → lost_damaged → PO-79722 closed · both short → one split_shipment + one out_of_stock → PO-79723 stays confirmed (split keeps it open · remaining 500)',
  :'n3a' not like 'ERR%' and (pg_temp.j(:'n3a')->'diffs'->>'short')::int = 1 and :'n3_res22' not like 'ERR%' and pg_temp.po_state(:'po22'::uuid) = 'closed|true'
  and :'n3b' not like 'ERR%' and (pg_temp.j(:'n3b')->'diffs'->>'short')::int = 2 and :'n3_res23a' not like 'ERR%' and :'n3_res23b' not like 'ERR%'
  and pg_temp.po_state(:'po23'::uuid) = 'confirmed|false' and (pg_temp.j(:'n3_res23b')->'po'->>'remaining_ea')::numeric = 500 and pg_temp.j(:'n3_res23b')->'po'->>'kept_open' = 'true',
  format('22 n3a %s / %s → %s | 23 n3b %s / %s / %s → %s', left(:'n3a', 900), left(:'n3_res22', 120), pg_temp.po_state(:'po22'::uuid), left(:'n3b', 900), left(:'n3_res23a', 120), left(:'n3_res23b', 600), pg_temp.po_state(:'po23'::uuid)));

\echo '── N4) PO-79724: 400 → 확정(열림 · short 600/400) → 100 → 확정(새 short 200/100 · 열림 · 옛 short 는 이력) → 마지막 short 를 miscount → closed · 옛 short 는 열린 채(이력 · 닫기에 안 끼어든다)'
select pg_temp.receive(:'o', 'RCV-79724', :'po24'::uuid, :'l24'::uuid, 400) as n4a \gset
set local session_replication_role = replica;
update public.po_receipt_diff d set created_at = d.created_at - interval '1 hour' from public.po_receipt r where r.id = d.receipt_id and r.receipt_number = 'RCV-79724';   -- 같은 트랜잭션의 두 short 는 created_at 이 같다 → 첫 것을 앞으로
set local session_replication_role = origin;
select pg_temp.receive(:'o', 'RCV-79725', :'po24'::uuid, :'l24'::uuid, 100) as n4b \gset
select pg_temp.latest_short(:'l24'::uuid) as d24 \gset
select (select string_agg(trim_scale(d.expected_qty) || '/' || trim_scale(d.received_qty) || ':' || coalesce(d.resolution, '-'), ',' order by d.created_at) from public.po_receipt_diff d where d.po_line_id = :'l24'::uuid and d.kind = 'short') as n4_shorts0 \gset
set local role authenticated;
select pg_temp.as_user(:'o', format('select public.po_receipt_diff_resolve(%L::uuid, ''miscount'', null)::text', :'d24')) as n4_res \gset
reset role;
select (select string_agg(trim_scale(d.expected_qty) || '/' || trim_scale(d.received_qty) || ':' || coalesce(d.resolution, '-'), ',' order by d.created_at) from public.po_receipt_diff d where d.po_line_id = :'l24'::uuid and d.kind = 'short') as n4_shorts1 \gset
select pg_temp.chk('N4 400 then 100: both confirms keep the PO open (remaining 200 → 100) · shorts 600/400 then 200/100 · latest short settled miscount → PO closed (closed_now) · the older short stays open as history and does not keep the PO open',
  :'n4a' not like 'ERR%' and (pg_temp.j(:'n4a')->'po'->>'remaining_ea')::numeric = 200 and :'n4b' not like 'ERR%' and (pg_temp.j(:'n4b')->'po'->>'remaining_ea')::numeric = 100 and (pg_temp.j(:'n4b')->'warnings') ? 'po_kept_open'
  and :'n4_shorts0' = '600/400:-,200/100:-' and :'n4_res' not like 'ERR%' and pg_temp.j(:'n4_res')->'po'->>'closed_now' = 'true' and pg_temp.po_state(:'po24'::uuid) = 'closed|true' and :'n4_shorts1' = '600/400:-,200/100:miscount',
  format('n4a po %s | n4b po %s | shorts %s → %s | res %s | state %s', pg_temp.j(:'n4a')->'po', pg_temp.j(:'n4b')->'po', :'n4_shorts0', :'n4_shorts1', left(:'n4_res', 160), pg_temp.po_state(:'po24'::uuid)));

\echo '── N5) W(권한 없음): 도우미는 읽기(stable · 누구나 실행) · 정리 · 되돌리기는 거부'
set local role authenticated;
select pg_temp.as_user(:'w', format('select public.po_receipt_keep_open(%L::uuid, null)::text', :'po23')) as n5_prev \gset
select pg_temp.as_user(:'w', format('select public.po_receipt_diff_resolve(%L::uuid, ''out_of_stock'', null)::text', :'d23a')) as n5_res \gset
reset role;
select pg_temp.chk('N5 W: helper preview readable (keep_open true · remaining 500) · resolve refused · PO-79723 still confirmed',
  :'n5_prev' not like 'ERR%' and pg_temp.j(:'n5_prev')->>'keep_open' = 'true' and (pg_temp.j(:'n5_prev')->>'remaining_ea')::numeric = 500 and :'n5_res' like 'ERR%' and pg_temp.po_state(:'po23'::uuid) = 'confirmed|false',
  format('prev %s | res %s | state %s', :'n5_prev', left(:'n5_res', 160), pg_temp.po_state(:'po23'::uuid)));

\echo '── D1) PO-02055(실제 행 · 단언만): confirmed · closed_at null · 도우미 keep_open · remaining 1050 · 열린 short 3 · 입고 RCV-00046 그대로 · po_list 에 WMS 목록 조건(확정 인보이스 + confirmed)'
select (select status || '|' || coalesce(closed_at::text, '-') from public.po where po_number = 'PO-02055') as d1_state \gset
select public.po_receipt_keep_open((select id from public.po where po_number = 'PO-02055'), null)::text as d1_keep \gset
select (select has_confirmed_invoice::text || '|' || status || '|' || trim_scale(received_qty) || '/' || trim_scale(confirmed_invoiced_qty) from public.po_list where po_number = 'PO-02055') as d1_list \gset
select (select count(*) || '/' || count(*) filter (where resolved_at is null) from public.po_receipt_diff d join public.po x on x.id = d.po_id where x.po_number = 'PO-02055' and d.kind = 'short') as d1_shorts,
       (select string_agg(r.receipt_number || ':' || r.status, ',' order by r.receipt_number) from public.po_receipt r join public.po x on x.id = r.po_id where x.po_number = 'PO-02055') as d1_rcv \gset
select pg_temp.chk(format('D1 PO-02055: %s (before %s) · helper keep_open · remaining 1050 · open shorts %s · receipts %s · po_list %s', :'d1_state', :'po02055_before', :'d1_shorts', :'d1_rcv', :'d1_list'),
  :'d1_state' = 'confirmed|-' and (:'po02055_before' like 'closed|2%' or (:n_applied = 1 and :'po02055_before' = 'confirmed|-')) and pg_temp.j(:'d1_keep')->>'keep_open' = 'true' and (pg_temp.j(:'d1_keep')->>'remaining_ea')::numeric = 1050 and (pg_temp.j(:'d1_keep')->>'open_short_lines')::int = 3
  and :'d1_shorts' = '3/3' and :'d1_rcv' = 'RCV-00046:confirmed' and :'d1_list' = 'true|confirmed|240/1290', left(:'d1_keep', 400));
\else
select pg_temp.chk('G1 ~ D1 skipped: rcv-3 not landed', false, 'not landed — nothing to exercise');
\endif

\echo '── Z1) 실제 행 무접촉'
select pg_temp.chk('Z1 real rows untouched', pg_temp.real_rows() = :'real_before', format('before %s | after %s', :'real_before', pg_temp.real_rows()));

rollback;
\echo '── rollback 뒤 — 가짜 흔적 0 · po_receipt_number_seq 되돌리기'
select (select count(*) from public.po where po_number like 'PO-797%') + (select count(*) from public.product where sku like 'RCV3-%') + (select count(*) from public.ims_staff where email like 'rcv3-%') + (select count(*) from public.supplier where name = 'RCV3 Supplier') as fake_traces_left;
select setval('public.po_receipt_number_seq', greatest(coalesce((select max(substring(receipt_number from '[0-9]+')::bigint) from public.po_receipt where receipt_number ~ '^RCV-[0-9]+$' and receipt_number not like 'RCV-797%'), 0), :rcv_seq_last), :'rcv_seq_called'::boolean) as po_receipt_number_seq_reset_to;
select last_value as rcv_seq_last_after, is_called as rcv_seq_called_after from public.po_receipt_number_seq;
