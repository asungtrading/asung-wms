-- nb-2 검증 — supabase/migrations/20261111065910_nb_2_unassigned_bin_counter_bin_required.sql (칸 없는 판매 막기 · 판정 1172 ~ 1175 · 지시서 ~/asung/prompts/nb-2.md §5 · asung-workflow §4 틀)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111065910_nb_2_unassigned_bin_counter_bin_required.sql -f supabase/tests/nb_2_check.sql
--   마른 실행(적용 전) · 확인(적용 뒤 · Caleb): 같은 명령에서 -v mig=… 만 뺀다 — 마른 실행은 UNASSIGNED 칸이 없어 S1 · S3 · S4 · C1 · R3 · G · B 가 FAIL · 확인은 O1(옛 = 새)만 건너뛴다
--   ⚠️ 실제 행 무변: 가짜 제품 여섯(ZZNB2-A ~ E · ZZNB2-DS) · 가짜 오더 일곱(SO-99999912xx · 실제 pos 오더 머리의 복사 · 만든 시각 2001-01-01) · 가짜 트랜스퍼 하나(TR-99999912) · 끝은 rollback
--   ⚠️ 인보이스를 발행하지 않는다(번호 시퀀스 무접촉): 출고는 so_ship 을 직원 claims 로 직접(so_pos_finish · so_counter_ship 이 definer 안에서 부르는 자리와 같다) · so_counter_ship 실행 갈래는 거부되는 부름만
--      + 시험 트랜잭션 안에서 so_invoice_next_number 를 「거부」 몸으로 덮는다 — 첫 마른 실행(2026-11-11)에서 빈 칸 counter 실행이 통과해 발행까지 가 인보이스 시퀀스가 60404 → 60405 로 하나 나갔다(교훈 142 와 같은 구멍 · 그 뒤 이 막이를 넣었다)
--   ⚠️ 잠금: 시험 적용이 ref_bin 에 트리거를 달아 SHARE ROW EXCLUSIVE 를 rollback 까지 잡는다(칸 읽기는 안 막는다 · 칸 켜기 · 끄기 · 새 칸 넣기가 기다린다) · lock_timeout 3 s
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- ── 머리(읽기) — 복사 원본 · 직원 신원 · 진짜 칸 하나 ──
select w.id::text as wh, w.name as whname from public.ref_warehouse w where w.name = 'Asung - Edmonton' \gset
select
  (select s.id::text from public.so s join public.customer c on c.id = s.customer_id
    where s.channel = 'pos' and s.status = 'fulfilled' and s.location_id = :'wh'::uuid and c.is_active and s.tax_rule_id is not null and s.bill_to_customer_id is not null and s.coupon_id is null
      and exists (select 1 from public.so_line l join public.product p on p.id = l.product_id where l.so_id = s.id and p.is_active and p.parent_product_id is null and l.combo_line_id is null and l.bgrade_bin_id is null and l.unit_price > 0
                    and l.free_reason is null and not exists (select 1 from public.so_line k where k.combo_line_id = l.id))
    order by s.created_at desc limit 1) as src,
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff,
  (select st.id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff_id,
  (select b.name from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active and not b.is_bgrade and b.name ~ '^E[A-Z][0-9]{6}$' order by b.name limit 1) as bin_a,
  (select t.id::text from public.inv_transfer t join public.ref_warehouse fw on fw.id = t.from_warehouse_id where fw.name in ('Asung Trading Inc.', 'Asung - Edmonton')
    order by (t.from_warehouse_id = :'wh'::uuid) desc, t.created_at desc limit 1) as tr_src,   -- EDM 출발이 없으면 TOR 출발(가짜 SKU 는 어느 창고에도 칸이 없다)
  (select count(*) from public.ref_bin b where b.name = 'UNASSIGNED')::int as applied_head,
  (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) as seq_head \gset
select 'head: UNASSIGNED bins ' || :applied_head || ' · seq(so/inv) ' || :'seq_head' || ' · wh ' || :'whname' || ' · src ' || left(:'src', 8) || ' · staff ' || left(:'staff', 8) || ' · real bin ' || :'bin_a' || ' · transfer src ' || left(:'tr_src', 8);

-- ── 도우미(begin 앞 · 잠금 구간 밖) ──
create temp table t_ids (k text primary key, id uuid not null);
create temp table t_res (seq serial, tag text, ok boolean, detail text);
create temp table t_old (k text primary key, v text);
create function pg_temp.id(p_k text) returns uuid language sql as $$ select t.id from t_ids t where t.k = p_k $$;
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 700)) $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 직원 신원(claims + role authenticated)으로 한 문장 — 예외는 'ERR <sqlstate>: <문장>' 글자로(그 문장의 쓰기는 되돌아간다)
create function pg_temp.asu(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('d.staff')), true);
  execute 'set local role authenticated';
  execute p_sql into v_out;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return coalesce(v_out, '(null)');
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 직원 claims 만(주인 postgres 그대로) — definer 창구(so_pos_finish · so_counter_ship) 안에서 so_ship 이 불리는 자리와 같다
create function pg_temp.asp(p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('d.staff')), true);
  execute p_sql into v_out;
  perform set_config('request.jwt.claims', '', true);
  return coalesce(v_out, '(null)');
exception when others then
  perform set_config('request.jwt.claims', '', true);
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 주인으로 한 문장(가드 시험) — 예외는 글자로
create function pg_temp.own(p_sql text) returns text language plpgsql as $$
declare v_n int;
begin
  execute p_sql;  get diagnostics v_n = row_count;
  return 'rows ' || v_n;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 행 복사(생성 칸 제외 · 칸이 늘어도 따라온다)
create function pg_temp.cp(p_tbl regclass, p_row jsonb) returns void language plpgsql as $$
declare v_cols text;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into v_cols from pg_attribute a where a.attrelid = p_tbl and a.attnum > 0 and not a.attisdropped and a.attgenerated = '' and a.attidentity = '';
  execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)', p_tbl, v_cols, v_cols, p_tbl) using p_row;
end $$;
-- safeupdate 정적 셈(ar_2b_check.sql 과 같은 스캐너 · 깊이 0 WHERE 없는 update · delete 수)
create function pg_temp.nowhere(p_src text) returns int language plpgsql as $$
declare v text; v_chunk text; v_prev text; v_verb text; v_n int := 0;
begin
  v := regexp_replace(p_src, '--[^\n]*', '', 'g');
  foreach v_chunk in array string_to_array(v, ';') loop
    v_verb := (regexp_match(v_chunk, '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*(update|delete|with)\M', 'i'))[1];
    if v_verb is null then continue; end if;
    v_chunk := substring(v_chunk from '(?:^|\mthen\M|\melse\M|\mloop\M|\mbegin\M)\s*((?:update|delete|with)\M.*)$');
    loop
      v_prev := v_chunk; v_chunk := regexp_replace(v_chunk, '\([^()]*\)', ' ', 'g');
      exit when v_chunk = v_prev;
    end loop;
    if lower(v_verb) = 'with' and v_chunk !~* '\m(update|delete)\M' then continue; end if;
    if v_chunk !~* '\mwhere\M' then v_n := v_n + 1; end if;
  end loop;
  return v_n;
end $$;
-- 계획 한 줄 요약: 첫 줄의 picks 를 'bin:qty:from' 으로 · 경고
create function pg_temp.plan(p_doc uuid) returns text language plpgsql as $$
declare v jsonb;
begin
  v := public.so_pick_plan(p_doc);
  return coalesce((select string_agg(format('%s:%s:%s', x->>'bin', trim_scale((x->>'qty')::numeric), x->>'from'), ',' order by o) from jsonb_array_elements(v->'picks') with ordinality t(x, o)), '') || ' | '
      || coalesce((select string_agg(w, ',' order by w) from jsonb_array_elements_text(v->'warnings') w), '') || ' | short ' || trim_scale((v->>'short_ea_total')::numeric);
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- 가짜 SKU 의 IMS 원장 합(이 창고 · 그 칸)
create function pg_temp.led(p_sku text, p_bin text) returns numeric language sql as $$
  select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.sku = p_sku and l.warehouse = current_setting('d.whname') and l.bin = p_bin and l.source = 'ims' $$;
-- 옛 = 새(O1): 실제 창고 오더 · 트랜스퍼 60 건의 계획 전체
create function pg_temp.real_plans() returns text language sql as $$
  select md5(string_agg(d.doc_id::text || public.so_pick_plan(d.doc_id)::text, '' order by d.doc_id)) || ' · docs ' || count(*) || ' · with no_bins ' || count(*) filter (where public.so_pick_plan(d.doc_id)::text like '%no_bins:%')
  from (select x.doc_id from public.wms_order_doc x where (x.doc_kind = 'transfer' or x.channel = 'warehouse') and x.warehouse_id is not null and x.created_at < now() - interval '1 day' order by x.created_at desc limit 60) d $$;

begin;
set local lock_timeout = '3s';
select set_config('d.src', :'src', true), set_config('d.staff', :'staff', true), set_config('d.staff_id', :'staff_id', true), set_config('d.wh', :'wh', true), set_config('d.whname', :'whname', true),
       set_config('d.bin_a', :'bin_a', true), set_config('d.tr_src', :'tr_src', true), set_config('d.seq', :'seq_head', true), clock_timestamp() as t_begin \gset

-- ── 가짜 재료 — 제품 여섯 · 오더 일곱 · 트랜스퍼 하나 · 원장 바탕(B · C) ──
do $$
declare
  c_mark constant timestamptz := '2001-01-01 00:00:00+00';
  v_src jsonb;  v_line jsonb;  v_prod jsonb;  v_tr jsonb;  v_id uuid;  v_lid uuid;  k text;  i int := 0;  v_ch text;  v_sku text;
  c_null constant jsonb := jsonb_build_object('split_from_id', null, 'split_reason', null, 'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
                                              'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null, 'unconfirmed_at', null, 'unconfirmed_by', null, 'coupon_id', null,
                                              'status', 'confirmed', 'order_discount_pct', null, 'reprice_suggested_at', null);
begin
  execute 'set local session_replication_role = replica';
  select to_jsonb(s) into v_src from public.so s where s.id = current_setting('d.src')::uuid;
  select to_jsonb(l), to_jsonb(p) into v_line, v_prod from public.so_line l join public.product p on p.id = l.product_id
   where l.so_id = current_setting('d.src')::uuid and p.is_active and p.parent_product_id is null and l.combo_line_id is null and l.bgrade_bin_id is null and l.unit_price > 0 and l.free_reason is null
     and not exists (select 1 from public.so_line x where x.combo_line_id = l.id) order by l.line_no limit 1;
  -- 제품: A 칸 없음 · B 진짜 칸 0 · C 진짜 칸 0 + UNASSIGNED −1 · D 세트의 낱개(칸 없음) · DS 세트(12 EA) · E 칸 없음(counter · 창고 오더 · 트랜스퍼)
  foreach k in array array['A', 'B', 'C', 'D', 'E', 'DS'] loop
    v_id := gen_random_uuid();
    insert into t_ids values ('p' || k, v_id);
    perform pg_temp.cp('public.product', v_prod || jsonb_build_object('id', v_id, 'sku', 'ZZNB2-' || k, 'name', 'nb-2 test ' || k, 'cin7_id', null,
      'parent_product_id', case when k = 'DS' then pg_temp.id('pD') end, 'set_discount_pct', null, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  -- 오더: P1 pos A · P2 pos B · P3 pos DS · P4 pos A(다시) · P5 pos C · CT counter E · WH warehouse E
  foreach k in array array['P1', 'P2', 'P3', 'P4', 'P5', 'CT', 'WH'] loop
    i := i + 1;  v_id := gen_random_uuid();  v_lid := gen_random_uuid();
    insert into t_ids values (k, v_id), (k || '.1', v_lid);
    v_ch := case k when 'CT' then 'counter' when 'WH' then 'warehouse' else 'pos' end;
    v_sku := case k when 'P1' then 'A' when 'P2' then 'B' when 'P3' then 'DS' when 'P4' then 'A' when 'P5' then 'C' else 'E' end;
    perform pg_temp.cp('public.so', v_src || c_null || jsonb_build_object('id', v_id, 'so_number', 'SO-99999912' || lpad(i::text, 2, '0'), 'channel', v_ch,
      'intake', case when v_ch = 'pos' then 'pos' else 'manual' end, 'created_at', c_mark, 'updated_at', c_mark));
    perform pg_temp.cp('public.so_line', v_line || jsonb_build_object('id', v_lid, 'so_id', v_id, 'line_no', 1, 'product_id', pg_temp.id('p' || v_sku), 'sku', 'ZZNB2-' || v_sku,
      'pack_factor', case when v_sku = 'DS' then 12 else 1 end, 'qty_ordered', 1, 'qty_shipped', 0, 'qty_removed', 0, 'removed_reason', null, 'removed_note', null,
      'removed_at', null, 'removed_by', null, 'split_from_line_id', null, 'comments', null, 'backorder_notified_at', null, 'created_at', c_mark, 'updated_at', c_mark));
    insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by) values (v_lid, 1, 'allocated', current_setting('d.staff_id')::uuid);
  end loop;
  -- 트랜스퍼: 실제 머리의 복사 + 줄 하나(E)
  select to_jsonb(t) into v_tr from public.inv_transfer t where t.id = current_setting('d.tr_src')::uuid;
  v_id := gen_random_uuid();
  insert into t_ids values ('TR', v_id);
  perform pg_temp.cp('public.inv_transfer', v_tr || jsonb_build_object('id', v_id, 'transfer_number', 'TR-99999912', 'created_at', c_mark, 'updated_at', c_mark));
  insert into public.inv_transfer_line (transfer_id, line_no, product_id, sku, qty, pack_factor) values (v_id, 1, pg_temp.id('pE'), 'ZZNB2-E', 1, 1);
  -- 원장 바탕(source manual · 트리거 없이): B · C 는 진짜 칸에 +1 −1(열흘 전 = 잔고 0 행) · C 는 UNASSIGNED −1(오늘 = 가장 최근에 본 빈 칸)
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
  select public.ims_today() - 10, case when q > 0 then 1 else 2 end, 'ZZNB2-' || s, current_setting('d.whname'), current_setting('d.bin_a'), q, 'adjust_existing', 'adjustment', 'NB2-TEST', s || q::text, 'manual'
    from unnest(array['B', 'C']) s cross join unnest(array[1, -1]) q;
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
  values (public.ims_today(), 2, 'ZZNB2-C', current_setting('d.whname'), 'UNASSIGNED', -1, 'adjust_existing', 'adjustment', 'NB2-TEST', 'C-ua', 'manual');
  execute 'set local session_replication_role = origin';
  -- 발행 막기(이 트랜잭션에서만 · rollback 으로 사라진다 · 다른 세션은 옛 몸을 본다): 시험 중 어떤 길로도 인보이스 번호 시퀀스를 못 쓴다 — 마른 실행에서 빈 칸 counter 실행이 통과해 발행까지 가는 것을 여기서 멈춘다
  execute $f$create or replace function public.so_invoice_next_number() returns text language plpgsql as $b$ begin raise exception 'nb-2 test — no invoice may be issued in this test'; end $b$ $f$;
end $$;

\if :{?mig}
-- ── 시험에서만: 적용 전 옛 출력(O1) ──
insert into t_old values ('real', pg_temp.real_plans());
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 검증(한 문장) ──
create function pg_temp.run() returns void language plpgsql as $$
declare
  v_has  boolean := exists (select 1 from public.ref_bin b where b.warehouse_id = current_setting('d.wh')::uuid and b.name = 'UNASSIGNED' and b.is_active);
  v_wh   text := current_setting('d.whname');  v_a text := current_setting('d.bin_a');  v_stf text := current_setting('d.staff_id');
  r text;  r2 text;  r3 text;  r4 text;  r5 text;  v_led0 bigint;  v_n int;  v_ua uuid;
  v_ins constant text := $q$insert into public.ref_bin (name, warehouse_id, source, is_active, is_staging, is_bgrade, zone, note)
    select 'UNASSIGNED', w.id, 'manual', true, false, false, null, 'again' from public.ref_warehouse w where w.name in ('Asung Trading Inc.', 'Asung - Edmonton') and w.is_active
    on conflict (warehouse_id, name) do nothing$q$;
begin
  select count(*) into v_led0 from public.inv_ledger l where l.sku not like 'ZZNB2-%';
  select b.id into v_ua from public.ref_bin b where b.warehouse_id = current_setting('d.wh')::uuid and b.name = 'UNASSIGNED';

  -- B 칸 두 행 · 멱등
  r := case when v_has then pg_temp.own(v_ins) else 'not applied' end;
  perform pg_temp.res('B1 칸: 판매 창고 둘에 UNASSIGNED 한 행씩(활성 · manual · is_staging false · is_bgrade false · zone null) · 다른 창고 0 · 같은 넣기를 다시 돌려도 0 행 더해짐(멱등)',
    (select count(*) = 2 and count(*) filter (where b.is_active and b.source = 'manual' and not b.is_staging and not b.is_bgrade and b.zone is null and w.name in ('Asung Trading Inc.', 'Asung - Edmonton')) = 2
       from public.ref_bin b join public.ref_warehouse w on w.id = b.warehouse_id where upper(btrim(b.name)) = 'UNASSIGNED') and r = 'rows 0',
    r || ' · ' || coalesce((select string_agg(w.name || ' ' || b.source || ' active ' || b.is_active, ' / ' order by w.name) from public.ref_bin b join public.ref_warehouse w on w.id = b.warehouse_id where upper(btrim(b.name)) = 'UNASSIGNED'), 'no rows'));

  -- S1 시나리오 1 — pos · 칸 행 없는 SKU 1 판매 ⇒ UNASSIGNED −1 · 칸 없음 0
  r := pg_temp.plan(pg_temp.id('P1'));
  r2 := pg_temp.asp(format('select public.so_ship(%L, (public.so_pick_plan(%L))->''picks'', %L, null)::text', pg_temp.id('P1'), pg_temp.id('P1'), v_stf));
  perform pg_temp.res('S1 시나리오 1(pos · 칸 행 없는 SKU 1 판매): 계획 UNASSIGNED:1:unassigned · 경고 unassigned_bin(no_bins 아님) · 출고 뒤 원장 UNASSIGNED −1 · 칸 없음 0',
    r like 'UNASSIGNED:1:unassigned | %unassigned_bin:ZZNB2-A%' and r not like '%no_bins%' and r2 like '{%' and (pg_temp.j(r2)->>'shipped')::boolean
    and pg_temp.led('ZZNB2-A', 'UNASSIGNED') = -1 and pg_temp.led('ZZNB2-A', '') = 0,
    r || ' ‖ ' || left(r2, 160) || ' ‖ UNASSIGNED ' || pg_temp.led('ZZNB2-A', 'UNASSIGNED') || ' · no bin ' || pg_temp.led('ZZNB2-A', ''));

  -- S2 시나리오 2 — 후보 칸 A 에 0 ⇒ A −1(지금 그대로)
  r := pg_temp.plan(pg_temp.id('P2'));
  r2 := pg_temp.asp(format('select public.so_ship(%L, (public.so_pick_plan(%L))->''picks'', %L, null)::text', pg_temp.id('P2'), pg_temp.id('P2'), v_stf));
  perform pg_temp.res('S2 시나리오 2(pos · 진짜 칸에 0): 계획 그 칸:1:fallback · 출고 뒤 그 칸 −1 · UNASSIGNED 0 · 칸 없음 0(판정 1 · 고침 ① 그대로)',
    r like v_a || ':1:fallback | %' and r not like '%unassigned%' and r2 like '{%' and pg_temp.led('ZZNB2-B', v_a) = -1 and pg_temp.led('ZZNB2-B', 'UNASSIGNED') = 0 and pg_temp.led('ZZNB2-B', '') = 0,
    r || ' ‖ ' || left(r2, 120) || ' ‖ ' || v_a || ' ' || pg_temp.led('ZZNB2-B', v_a));

  -- S3 시나리오 3 — 세트 1(12 EA) · 칸 없음 ⇒ UNASSIGNED −12(낱개 SKU)
  r := pg_temp.plan(pg_temp.id('P3'));
  r2 := pg_temp.asp(format('select public.so_ship(%L, (public.so_pick_plan(%L))->''picks'', %L, null)::text', pg_temp.id('P3'), pg_temp.id('P3'), v_stf));
  perform pg_temp.res('S3 시나리오 3(pos · 세트 1 = 12 EA · 칸 없음): 계획 UNASSIGNED:1:unassigned · 원장은 낱개 SKU 로 UNASSIGNED −12 · 칸 없음 0',
    r like 'UNASSIGNED:1:unassigned | %unassigned_bin:ZZNB2-DS%' and r2 like '{%' and pg_temp.led('ZZNB2-D', 'UNASSIGNED') = -12 and pg_temp.led('ZZNB2-D', '') = 0,
    r || ' ‖ ' || left(r2, 120) || ' ‖ D UNASSIGNED ' || pg_temp.led('ZZNB2-D', 'UNASSIGNED') || ' · no bin ' || pg_temp.led('ZZNB2-D', ''));

  -- S4 시나리오 4 — 같은 SKU 를 다시 ⇒ 또 UNASSIGNED(−2)
  r := pg_temp.plan(pg_temp.id('P4'));
  r2 := pg_temp.asp(format('select public.so_ship(%L, (public.so_pick_plan(%L))->''picks'', %L, null)::text', pg_temp.id('P4'), pg_temp.id('P4'), v_stf));
  perform pg_temp.res('S4 시나리오 4(같은 SKU 를 다시 판매): 또 UNASSIGNED:1:unassigned(후보가 되어 fallback 으로 바뀌지 않는다) · 원장 UNASSIGNED −2',
    r like 'UNASSIGNED:1:unassigned | %' and r2 like '{%' and pg_temp.led('ZZNB2-A', 'UNASSIGNED') = -2 and pg_temp.led('ZZNB2-A', '') = 0,
    r || ' ‖ ' || left(r2, 120) || ' ‖ UNASSIGNED ' || pg_temp.led('ZZNB2-A', 'UNASSIGNED'));

  -- T5 판정 1175 — 진짜 칸 0(열흘 전) 이 UNASSIGNED −1(오늘) 보다 먼저
  r := pg_temp.plan(pg_temp.id('P5'));
  perform pg_temp.res('T5 판정 1175(진짜 칸 0 · UNASSIGNED −1 이 더 최근): 계획은 진짜 칸:1:fallback — UNASSIGNED 는 후보가 아니다',
    r like v_a || ':1:fallback | %' and r not like '%UNASSIGNED%', r);

  -- C1 counter — 계획 · 미리 보기가 UNASSIGNED 로 채운다
  r := pg_temp.plan(pg_temp.id('CT'));
  r2 := pg_temp.asu(format('select public.so_counter_ship(%L, null, false)::text', pg_temp.id('CT')));
  perform pg_temp.res('C1 counter(칸 행 없는 SKU): 계획 UNASSIGNED:1:unassigned · so_counter_ship 미리 보기(p_picks null)가 그 픽을 돌려준다',
    r like 'UNASSIGNED:1:unassigned | %unassigned_bin:ZZNB2-E%' and pg_temp.j(r2)->'picks'->0->>'bin' = 'UNASSIGNED' and (pg_temp.j(r2)->>'committed')::boolean = false,
    r || ' ‖ ' || left(coalesce((pg_temp.j(r2)->'picks')::text, r2), 200));

  -- R3 counter 빈칸 거부 — 미리 보기 · 실행
  r  := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, false)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', null, 'qty', 1))));
  r2 := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, false)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', '', 'qty', 1))));
  r3 := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, false)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', '   ', 'qty', 1))));
  r4 := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, false)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'qty', 1))));
  perform pg_temp.res('R3a counter 미리 보기: 칸 null · 빈 글 · 공백 · 열쇠 없음 넷 다 거부 「Pick a bin for line 1 (ZZNB2-E) — nothing was saved」',
    r like 'ERR %Pick a bin for line 1 (ZZNB2-E) — nothing was saved' and r2 = r and r3 = r and r4 = r, r || ' ‖ ' || left(r2, 90) || ' ‖ ' || left(r3, 90) || ' ‖ ' || left(r4, 90));
  r  := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, true)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', '', 'qty', 1))));
  r2 := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, true)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', '  ', 'qty', 1))));
  r3 := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, true)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', null, 'qty', 1))));
  perform pg_temp.res('R3b counter 실행: 빈 글 · 공백 · null 셋 다 거부(같은 문장) · 오더는 confirmed 그대로 · 원장 0 · 인보이스 0',
    r like 'ERR %Pick a bin for line 1 (ZZNB2-E) — nothing was saved' and r2 = r and r3 = r
    and (select s.status from public.so s where s.id = pg_temp.id('CT')) = 'confirmed' and (select count(*) from public.inv_ledger l where l.sku = 'ZZNB2-E') = 0
    and (select count(*) from public.so_invoice_order io where io.so_id = pg_temp.id('CT')) = 0,
    r || ' ‖ status ' || (select s.status from public.so s where s.id = pg_temp.id('CT')));
  -- R3c UNASSIGNED 는 허용 — 미리 보기 통과 · 실행 갈래도 R3 을 지난다(일부러 과다 픽 2 를 줘 so_ship 의 다른 거부에서 멈춘다 = 발행 없음) · so_ship 직접 출고 = UNASSIGNED −1
  r  := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, false)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', 'UNASSIGNED', 'qty', 1))));
  r2 := pg_temp.asu(format('select public.so_counter_ship(%L, %L::jsonb, true)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', 'UNASSIGNED', 'qty', 2))));
  r3 := pg_temp.asp(format('select public.so_ship(%L, %L::jsonb, %L, null)::text', pg_temp.id('CT'), jsonb_build_array(jsonb_build_object('line_id', pg_temp.id('CT.1'), 'bin', 'UNASSIGNED', 'qty', 1)), v_stf));
  perform pg_temp.res('R3c counter 가 UNASSIGNED 를 고르면 허용: 미리 보기 통과 · 실행 갈래는 R3 을 지나 so_ship 의 과다 픽 거부에서 멈춤(Pick a bin 아님) · 출고 뒤 원장 UNASSIGNED −1 · 칸 없음 0',
    (pg_temp.j(r)->>'committed')::boolean = false and pg_temp.j(r)->'picks'->0->>'bin' = 'UNASSIGNED' and r2 like 'ERR %picked 2 but 1 to ship%' and r2 not like '%Pick a bin%'
    and r3 like '{%' and pg_temp.led('ZZNB2-E', 'UNASSIGNED') = -1 and pg_temp.led('ZZNB2-E', '') = 0,
    left(r, 100) || ' ‖ ' || left(r2, 140) || ' ‖ ' || left(r3, 100) || ' ‖ UNASSIGNED ' || pg_temp.led('ZZNB2-E', 'UNASSIGNED'));

  -- W1 창고 오더 — 그대로(E 는 이제 UNASSIGNED −1 행이 있다 = 「UNASSIGNED 가 후보가 되지 않는다」 까지)
  r := pg_temp.plan(pg_temp.id('WH'));
  r2 := pg_temp.own(format('select public.wms_pick_task_build(%L, %L, array[%L]::uuid[], null, null, %L, public.so_pick_plan(%L))', pg_temp.id('WH'), 'SO-9999991207-1', pg_temp.id('WH.1'), v_stf, pg_temp.id('WH')));
  perform pg_temp.res('W1 판정 1174 창고 오더(같은 SKU · UNASSIGNED −1 행이 있어도): 계획 칸 없음 :1:none · 경고 no_bins · 과제의 계획 칸 행 0(픽커는 진짜 칸을 대야 한다)',
    r like ':1:none | %no_bins:ZZNB2-E%' and r not like '%UNASSIGNED%' and r2 not like 'ERR%'
    and (select count(*) from public.wms_pick_line_bins pb join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id where pl.order_line_id = pg_temp.id('WH.1')) = 0
    and (select count(*) from public.wms_pick_task_lines pl where pl.order_line_id = pg_temp.id('WH.1')) = 1,
    r || ' ‖ ' || r2 || ' ‖ planned rows ' || (select count(*) from public.wms_pick_line_bins pb join public.wms_pick_task_lines pl on pl.id = pb.pick_task_line_id where pl.order_line_id = pg_temp.id('WH.1')));

  -- W2 트랜스퍼 출발 계획 — 그대로
  r := pg_temp.plan(pg_temp.id('TR'));
  perform pg_temp.res('W2 판정 1174 트랜스퍼 출발(같은 SKU): 계획 칸 없음 :1:none · 경고 no_bins — UNASSIGNED 로 가지 않는다',
    r like ':1:none | %no_bins:ZZNB2-E%' and r not like '%UNASSIGNED%', r);

  -- O1 옛 = 새 — 실제 창고 오더 · 트랜스퍼 60 건의 계획(시험에서만)
  if exists (select 1 from t_old) then
    r := pg_temp.real_plans();
    perform pg_temp.res('O1 옛 = 새: 실제 창고 오더 · 트랜스퍼 60 건의 so_pick_plan 전체가 적용 앞뒤 같다(md5)', r = (select t.v from t_old t where t.k = 'real'), r || ' ≟ ' || (select t.v from t_old t where t.k = 'real'));
  end if;

  -- G 가드 — 끄기 · B급 · 지우기 · (이름 바꾸기는 ref_bin_name_lock) · 다른 칸은 그대로
  r  := pg_temp.own(format('update public.ref_bin set is_active = false where id = %L', v_ua));
  r2 := pg_temp.own(format('update public.ref_bin set is_bgrade = true where id = %L', v_ua));
  r3 := pg_temp.own(format('delete from public.ref_bin where id = %L', v_ua));
  r4 := pg_temp.own(format('update public.ref_bin set name = %L where id = %L', 'UNASSIGNED2', v_ua));
  r5 := pg_temp.asu(format('select public.ref_bin_bgrade_set(%L, true)::text', v_ua));
  perform pg_temp.res('G1 가드: UNASSIGNED 끄기 · B급 표시(직접 · 창구 ref_bin_bgrade_set) · 지우기 · 이름 바꾸기 다섯 다 거부 · 칸은 활성 · B급 아님 그대로',
    r like 'ERR %cannot be switched off or marked B-grade%' and r2 like 'ERR %cannot be switched off or marked B-grade%' and r3 like 'ERR %cannot be deleted%' and r4 like 'ERR IM538%' and r5 like 'ERR%'
    and (select b.is_active and not b.is_bgrade and b.name = 'UNASSIGNED' from public.ref_bin b where b.id = v_ua),
    left(r, 110) || ' ‖ ' || left(r2, 60) || ' ‖ ' || left(r3, 90) || ' ‖ ' || left(r4, 70) || ' ‖ ' || left(r5, 130));
  r  := pg_temp.own(format('update public.ref_bin set note = %L where id = %L', 'note can change', v_ua));
  r2 := pg_temp.own(format('update public.ref_bin set is_active = false where warehouse_id = %L and name = %L', current_setting('d.wh'), v_a));
  r3 := pg_temp.own(format('update public.ref_bin set is_active = true where warehouse_id = %L and name = %L', current_setting('d.wh'), v_a));
  perform pg_temp.res('G2 가드가 막지 않는 것: UNASSIGNED 의 note 고치기 · 다른 칸 끄기 · 다시 켜기(각 1 행)', r = 'rows 1' and r2 = 'rows 1' and r3 = 'rows 1', r || ' · ' || r2 || ' · ' || r3);

  -- R1 safeupdate 정적
  perform pg_temp.res('R1 safeupdate 정적: so_pick_plan · so_counter_ship · ref_bin_unassigned_guard 에 WHERE 없는 update · delete 0(스캐너 자기 시험 포함)',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text = '101'
    and (select coalesce(sum(pg_temp.nowhere(p.prosrc)), -1) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_pick_plan', 'so_counter_ship', 'ref_bin_unassigned_guard')) = 0,
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_pick_plan', 'so_counter_ship', 'ref_bin_unassigned_guard')));

  -- Z 실물 무접촉
  perform pg_temp.res('Z 실물 무접촉: 가짜 SKU 밖의 원장 행 수 그대로 · 이 트랜잭션이 손댄 so 는 전부 가짜(SO-99999912xx) · 인보이스 0 · 번호 시퀀스(so · 인보이스) 그대로 · claims 비었음 · 주인 postgres',
    (select count(*) from public.inv_ledger l where l.sku not like 'ZZNB2-%') = v_led0
    and (select count(*) from public.so s where s.updated_at = now() and s.so_number not like 'SO-99999912%') = 0
    and (select count(*) from public.so_invoice i where i.created_at = now()) = 0
    and (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq) = current_setting('d.seq')
    and coalesce(current_setting('request.jwt.claims', true), '') = '' and current_user = 'postgres',
    format('real ledger rows %s → %s · user %s', v_led0, (select count(*) from public.inv_ledger l where l.sku not like 'ZZNB2-%'), current_user));
end $$;
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · seq(so/inv) ' || :'seq_head' || ' → '
       || (select last_value::text from public.so_number_seq) || '/' || (select last_value::text from public.so_invoice_number_seq)
       || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
\pset tuples_only off
\pset format aligned
rollback;
-- 기대: 시험(-v mig) OK 17 · FAIL 0 · 마른 실행(적용 전 · -v mig 없음) OK 6(S2 · T5 · W1 · W2 · R1 · Z) · FAIL 10(B1 · S1 · S3 · S4 · C1 · R3a · R3b · R3c · G1 · G2 — UNASSIGNED 칸 · 거부 없음)
--       확인(적용 뒤 · -v mig 없음) OK 16 · FAIL 0(O1 은 시험에서만) · 시험 begin ~ 끝 약 10 초(2026-11-11 실측)
--       변이(2026-11-11): UNASSIGNED 를 후보에 넣은 판 → S4 · T5 · W1 FAIL · 채널 조건을 뺀 판 → W1 · W2 · O1 FAIL
