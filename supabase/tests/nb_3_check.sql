-- nb-3 검증 — supabase/migrations/20261111071400_nb_3_stock_short_count_check.sql (Count & check · 판정 1176 · 지시서 ~/asung/prompts/nb-3.md §4 · asung-workflow §4 틀)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB · nb-2 는 DB 에 있는 것 위에서): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -X -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111071400_nb_3_stock_short_count_check.sql -f supabase/tests/nb_3_check.sql
--   마른 실행(적용 전) · 확인(적용 뒤 · Caleb): 같은 명령에서 -v mig=… 만 뺀다 — 기대 수는 파일 끝
--   ⚠️ 실제 행 무변: 재료는 전부 가짜 — 제품 'ZZNB3-…'(실제 낱개 제품 한 행의 복사) · 오더 번호 'SO-NB3-…'(so 행 없음 · 부족분 레이어의 doc_number 뿐) · 직원 다섯('nb3-…@test.invalid' · 가짜 auth uid) · 칸만 실제(EDM 진짜 칸 둘 · UNASSIGNED · 읽기만)
--      실제 「재고 없이 나갔다」 줄 · 유령 두 건(EZB70340 · ORS21020)은 건드리지 않는다 · 끝은 rollback
--   ⚠️ 조정 번호 시퀀스: 실행 갈래가 실제 창구 inv_adjust_create 로 ADJ 번호를 쓴다(미리 보기는 안 쓴다 — P1 이 본다) ⇒ rollback 뒤 끝에서 greatest(머리 값, 실제 최대 ADJ 번호)로 되돌린다
--   ⚠️ 잠금: 시험 적용이 so_stock_short_check 에 칸 · 제약을 더해 ACCESS EXCLUSIVE 를 rollback 까지 잡는다(그 동안 Action Centre 의 Sold without stock 목록 · Mark checked 가 기다린다 · 약 10 초) · lock_timeout 3 s
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
select w.id::text as wh, w.name as whname from public.ref_warehouse w where w.name = 'Asung - Edmonton' \gset
select
  (select w.id::text from public.ref_warehouse w where w.name = 'Asung Trading Inc.') as tor,
  (select p.id::text from public.product p where p.is_active and p.parent_product_id is null order by p.sku limit 1) as psrc,
  (select b.name from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active and not b.is_bgrade and b.name ~ '^E[A-Z][0-9]{6}$' order by b.name limit 1) as bin_a,
  (select b.name from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.is_active and not b.is_bgrade and b.name ~ '^E[A-Z][0-9]{6}$' order by b.name offset 1 limit 1) as bin_b,
  (select count(*) from public.ref_bin b where b.warehouse_id = :'wh'::uuid and b.name = 'UNASSIGNED' and b.is_active)::int as ua_head,
  (to_regprocedure('public.so_stock_short_count(text,text,jsonb,text,text,boolean)') is not null)::int as applied_head,
  (select last_value::text from public.inv_adjust_number_seq) as seq_head,
  (select count(*) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_layer)::text || '/' || (select count(*) from public.inv_adjust)::text || '/' || (select count(*) from public.so_stock_short_check)::text as real_head \gset
select 'head: applied ' || :applied_head || ' · UNASSIGNED at ' || :'whname' || ' ' || :ua_head || ' · adj seq ' || :'seq_head' || ' · ledger/layer/adjust/check ' || :'real_head' || ' · bins ' || :'bin_a' || ' ' || :'bin_b';

create temp table t_ids (k text primary key, id uuid not null);
create temp table t_res (seq serial, tag text, ok boolean, detail text);
create function pg_temp.id(p_k text) returns uuid language sql as $$ select t.id from t_ids t where t.k = p_k $$;
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 900)) $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 가짜 직원 신원(claims + role authenticated)으로 한 문장 — 예외는 'ERR <sqlstate>: <문장>' 글자로(그 문장의 쓰기는 되돌아간다)
create function pg_temp.asu(p_who text, p_sql text) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', pg_temp.id('u' || p_who)), true);
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
create function pg_temp.own(p_sql text) returns text language plpgsql as $$
declare v_n int;
begin
  execute p_sql;  get diagnostics v_n = row_count;
  return 'rows ' || v_n;
exception when others then
  return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
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
-- 재료 — 씨(다른 창고의 레이어 + 원장 · 최근 원가의 근거)
create function pg_temp.seed(p_sku text, p_wh text, p_bin text, p_qty numeric, p_unit numeric) returns void language plpgsql as $$
begin
  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (p_sku, p_wh, 'baseline', 'NB3-SEED', p_sku, null, public.ims_today() - 30, true, p_qty, p_unit, 'snapshot_value');
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
  values (public.ims_today() - 30, 1, p_sku, p_wh, p_bin, p_qty, 'po_in', 'purchase', 'NB3-SEED', p_sku || '|' || p_wh, 'manual');
end $$;
-- 재료 — 재고 없는 판매(실제 창구 inv_layer_post_sale 이 부족분 레이어를 세운다 + 원장 −q · nb_1_check 와 같은 꼴) · 창고는 EDM
create function pg_temp.sale(p_doc text, p_line text, p_sku text, p_bin text, p_qty numeric) returns void language plpgsql as $$
declare v jsonb;
begin
  v := public.inv_layer_post_sale(p_doc, p_line, p_sku, current_setting('d.whname'), p_qty, public.ims_today(), null);
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source, raw)
  values (public.ims_today(), 2, p_sku, current_setting('d.whname'), p_bin, -p_qty, 'sale_out', 'sale', p_doc, p_line, 'manual', jsonb_build_object('cost', v));
end $$;
create function pg_temp.led(p_sku text, p_bin text) returns numeric language sql as $$
  select coalesce(sum(l.qty_delta), 0) from public.inv_ledger l where l.sku = p_sku and l.warehouse = current_setting('d.whname') and l.bin = p_bin $$;
-- 상태 한 줄 — 레이어 남은 수량 · 남은 가치 · 장부 수량(EDM)
create function pg_temp.st(p_sku text) returns text language sql as $$
  select format('lay %s val %s led %s',
    (select coalesce(sum(v.remaining_qty), 0) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = current_setting('d.whname'))::numeric(18,2),
    (select coalesce(sum(v.remaining_value), 0) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = current_setting('d.whname'))::numeric(18,2),
    (select coalesce(sum(e.qty_delta), 0) from public.inv_ledger e where e.sku = p_sku and e.warehouse = current_setting('d.whname'))::numeric(18,2)) $$;
-- 확인 기록 한 줄(칸 adjust_number 는 적용 전에 없을 수 있어 to_jsonb 로 읽는다)
create function pg_temp.chk(p_sku text) returns text language sql as $$
  select coalesce(string_agg(format('%s:%s:%s:%s', k.doc_number, k.source, coalesce(to_jsonb(k)->>'adjust_number', '-'), coalesce(k.note, '-')), ' / ' order by k.doc_number), 'none')
    from public.so_stock_short_check k where k.sku = p_sku and k.warehouse = current_setting('d.whname') $$;
-- 창구 부르기(직원 신원) — 읽기 · Count
create function pg_temp.vw(p_who text, p_sku text) returns text language sql as $$
  select pg_temp.asu(p_who, format('select public.so_stock_short_count_view(%L, %L)::text', p_sku, current_setting('d.whname'))) $$;
create function pg_temp.cnt(p_who text, p_sku text, p_counts jsonb, p_seen text, p_note text, p_commit boolean) returns text language sql as $$
  select pg_temp.asu(p_who, format('select public.so_stock_short_count(%L, %L, %L::jsonb, %L, %L, %L)::text', p_sku, current_setting('d.whname'), p_counts, p_seen, p_note, p_commit)) $$;
-- 가짜 SKU 가 남긴 조정 문서 수(미리 보기 임시 행 포함 — 0 이어야 한다) · 번호 시퀀스
create function pg_temp.adjn(p_sku text) returns int language sql as $$
  select count(*)::int from public.inv_adjust a where exists (select 1 from public.inv_adjust_line l where l.adjust_id = a.id and l.sku = p_sku) or a.adjust_number like 'PREVIEW-%' $$;

begin;
set local lock_timeout = '3s';
select set_config('d.wh', :'wh', true), set_config('d.whname', :'whname', true), set_config('d.tor', :'tor', true), set_config('d.psrc', :'psrc', true), set_config('d.bin_a', :'bin_a', true), set_config('d.bin_b', :'bin_b', true),
       set_config('d.real_head', :'real_head', true), clock_timestamp() as t_begin \gset

-- ── 가짜 재료 — 제품 열 · 직원 다섯 · 판매 ──
do $$
declare c_mark constant timestamptz := '2001-01-01 00:00:00+00'; v_prod jsonb; v_id uuid; k text; v_a text := current_setting('d.bin_a'); v_wh uuid := current_setting('d.wh')::uuid; v_tor uuid := current_setting('d.tor')::uuid;
begin
  execute 'set local session_replication_role = replica';
  select to_jsonb(p) into v_prod from public.product p where p.id = current_setting('d.psrc')::uuid;
  foreach k in array array['1', '2', '3', '4', '5', '6', '6B', '7', '8', '9'] loop
    v_id := gen_random_uuid();
    insert into t_ids values ('p' || k, v_id);
    perform pg_temp.cp('public.product', v_prod || jsonb_build_object('id', v_id, 'sku', 'ZZNB3-' || k, 'name', 'nb-3 test ' || k, 'cin7_id', null, 'parent_product_id', null, 'is_active', true, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  execute 'set local session_replication_role = origin';
  -- 직원: OK 매니저 + stock_adjust + EDM(원가 열쇠 없음) · COST 같은데 원가 열쇠 · NOKEY 매니저 · stock_adjust 없음(sales 는 있다 = Mark checked 는 된다) · WKEY worker + stock_adjust · TOR 매니저 + stock_adjust · 토론토만
  for k in select unnest(array['OK', 'COST', 'NOKEY', 'WKEY', 'TOR']) loop
    v_id := gen_random_uuid();
    insert into t_ids values ('u' || k, v_id);
    insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access)
    values (v_id, 'nb3-' || lower(k) || '@test.invalid', 'nb-3 ' || k, case when k = 'WKEY' then 'worker' else 'manager' end,
            case k when 'OK' then '["ims","sales","stock_adjust"]' when 'COST' then '["ims","sales","stock_adjust","cost"]' when 'NOKEY' then '["ims","sales","receiving"]' when 'WKEY' then '["ims","sales","stock_adjust"]' else '["ims","sales","stock_adjust"]' end::jsonb,
            array[case when k = 'TOR' then v_tor else v_wh end]);
  end loop;
  perform pg_temp.seed('ZZNB3-2', 'Asung Trading Inc.', 'NB3BIN', 1, 6.00);        -- 2: 다른 창고 원가 6.00(nb-1 순서의 근거)
  perform pg_temp.sale('SO-NB3-1', 'l1', 'ZZNB3-1', v_a, 1);                       -- 1: 칸 A −1
  perform pg_temp.sale('SO-NB3-2', 'l1', 'ZZNB3-2', v_a, 1);                       -- 2: 칸 A −1 · 실물 3
  perform pg_temp.sale('SO-NB3-3', 'l1', 'ZZNB3-3', 'UNASSIGNED', 1);              -- 3: UNASSIGNED −1 · 실물은 칸 B 에 2(B 는 이 SKU 의 칸 행이 아니다)
  perform pg_temp.sale('SO-NB3-4a', 'l1', 'ZZNB3-4', v_a, 1);                      -- 4: 오더 둘
  perform pg_temp.sale('SO-NB3-4b', 'l1', 'ZZNB3-4', v_a, 1);
  perform pg_temp.sale('SO-NB3-5', 'l1', 'ZZNB3-5', v_a, 1);                       -- 5: 재고 없이 1 판매 뒤 장부가 이미 0 으로 돌아와 있다(다른 길로 +1)
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
  values (public.ims_today(), 1, 'ZZNB3-5', current_setting('d.whname'), v_a, 1, 'adjust_existing', 'adjustment', 'NB3-TEST', '5', 'manual'),
         (public.ims_today(), 1, 'ZZNB3-6B', current_setting('d.whname'), v_a, 1, 'adjust_existing', 'adjustment', 'NB3-TEST', '6B', 'manual');
  perform pg_temp.sale('SO-NB3-6', 'l1', 'ZZNB3-6', v_a, 1);                       -- 6: 권한(조정 갈래)
  perform pg_temp.sale('SO-NB3-6B', 'l1', 'ZZNB3-6B', v_a, 1);                     -- 6B: 권한(장부가 맞아 확인만 하는 갈래 — 바깥 문만 지킨다)
  perform pg_temp.sale('SO-NB3-7a', 'l1', 'ZZNB3-7', v_a, 1);                      -- 7: 경합
  perform pg_temp.sale('SO-NB3-8a', 'l1', 'ZZNB3-8', '', 1);                       -- 8: 옛 칸 없음 행 −1 + 칸 A −1
  perform pg_temp.sale('SO-NB3-8b', 'l1', 'ZZNB3-8', v_a, 1);
  perform pg_temp.sale('SO-NB3-9', 'l1', 'ZZNB3-9', v_a, 1);                       -- 9: 한 오더에 같은 SKU 두 줄(둘째 줄은 run 안에서 — 원가 창구가 거부하는 것을 본다)
end $$;

\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

create function pg_temp.run() returns void language plpgsql as $$
declare
  A text := current_setting('d.bin_a');  B text := current_setting('d.bin_b');  v_wh text := current_setting('d.whname');
  r text; r2 text; r3 text; r4 text; r5 text; v jsonb; v2 jsonb; s text; v_adj text; v_seq0 bigint; v_seq1 bigint; v_n int;
  c_keys constant text[] := array['layer_id','doc_number','sku','warehouse','qty','received_on','cost_source','unit_cost','unknown','so_id','channel','so_status','customer_id','customer_name','check_id','checked_at','checked_by','checked_by_name','note'];
begin
  select last_value into v_seq0 from public.inv_adjust_number_seq;

  -- ── R1 읽기 ──
  r := pg_temp.vw('OK', 'ZZNB3-1');  v := pg_temp.j(r);
  perform pg_temp.res('R1a 읽기(시나리오 1 의 줄): 칸 A 장부 −1 · picked 0 · 셀 수 있음 · 꼭 세야 함 · 확인 안 된 줄 1(SO-NB3-1 · 1) · 메울 몫 1 · seen 있음 · can_count true · 원가 값 칸 없음',
    jsonb_array_length(v->'bins') = 1 and v->'bins'->0->>'bin' = A and (v->'bins'->0->>'ledger')::numeric = -1 and (v->'bins'->0->>'picked')::numeric = 0 and (v->'bins'->0->>'countable')::boolean and (v->'bins'->0->>'must_count')::boolean
    and jsonb_array_length(v->'shorts') = 1 and v->'shorts'->0->>'doc_number' = 'SO-NB3-1' and (v->'shorts'->0->>'qty')::numeric = 1 and (v->>'fill_room')::numeric = 1 and length(v->>'seen') = 32
    and (v->>'can_count')::boolean and r not like '%unit_cost%', left(r, 600));
  r2 := pg_temp.vw('NOKEY', 'ZZNB3-1');  r3 := pg_temp.vw('WKEY', 'ZZNB3-1');  r4 := pg_temp.vw('TOR', 'ZZNB3-1');
  perform pg_temp.res('R1b 읽기는 sales 보기면 된다 · can_count 는 stock_adjust 없는 매니저 false · 열쇠 있는 worker false · 다른 창고 매니저 false · 같은 seen',
    (pg_temp.j(r2)->>'can_count')::boolean = false and (pg_temp.j(r3)->>'can_count')::boolean = false and (pg_temp.j(r4)->>'can_count')::boolean = false and pg_temp.j(r2)->>'seen' = v->>'seen',
    left(r2, 120) || ' ‖ ' || left(r3, 120) || ' ‖ ' || left(r4, 120));

  -- ── 시나리오 1 — 평범: A −1 · 실물 0 ⇒ Count A=0 ──
  s := v->>'seen';
  r := pg_temp.cnt('OK', 'ZZNB3-1', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), null, null, false);  v2 := pg_temp.j(r);
  select last_value into v_seq1 from public.inv_adjust_number_seq;
  perform pg_temp.res('P1 미리 보기(시나리오 1): adjust_and_check · 줄 delta +1 · 메움 1 · 새 레이어 0 · 갈래 filled · 아무것도 안 남는다(조정 문서 0 · 임시 행 0 · 확인 기록 0 · 원장 그대로 · ADJ 번호 시퀀스 그대로)',
    (v2->>'committed')::boolean = false and v2->>'action' = 'adjust_and_check' and jsonb_array_length(v2->'lines') = 1 and (v2->'lines'->0->>'delta')::numeric = 1 and (v2->'lines'->0->>'fill_qty')::numeric = 1
    and (v2->'lines'->0->>'layer_qty')::numeric = 0 and v2->'lines'->0->>'cost_branch' = 'filled' and (v2->>'can_commit')::boolean and v2->>'adjust_number' is null and v2->>'seen' = s
    and pg_temp.adjn('ZZNB3-1') = 0 and pg_temp.chk('ZZNB3-1') = 'none' and pg_temp.led('ZZNB3-1', A) = -1 and v_seq1 = v_seq0,
    left(r, 500) || ' ‖ adj docs ' || pg_temp.adjn('ZZNB3-1') || ' · seq ' || v_seq0 || ' → ' || v_seq1);
  r := pg_temp.cnt('OK', 'ZZNB3-1', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);  v2 := pg_temp.j(r);  v_adj := v2->>'adjust_number';
  perform pg_temp.res('S1 시나리오 1(A −1 · 실물 0 ⇒ Count A=0): ADJ 확정 +1 · 메움 1(새 레이어 0) · 레이어 0 · 장부 0 · 줄 확인됨(source count · 그 ADJ 번호) · 원장 raw.cost.fill_qty 1 · 사유 count',
    (v2->>'committed')::boolean and v_adj like 'ADJ-%' and pg_temp.st('ZZNB3-1') = 'lay 0.00 val 0.00 led 0.00' and pg_temp.chk('ZZNB3-1') = 'SO-NB3-1:count:' || v_adj || ':counted — ' || v_adj
    and (select a.status = 'confirmed' and a.note like 'Count & check — ZZNB3-1 — SO-NB3-1%' from public.inv_adjust a where a.adjust_number = v_adj)
    and (select count(*) = 1 and bool_and(e.qty_delta = 1 and (e.raw->'cost'->>'fill_qty')::numeric = 1 and e.raw->'line'->>'reason' = 'count' and e.raw->'line'->>'mode' = 'set' and e.bin = A) from public.inv_ledger e where e.doc_number = v_adj)
    and (v2->>'checked_count')::int = 1,
    left(r, 260) || ' ‖ ' || pg_temp.st('ZZNB3-1') || ' ‖ ' || pg_temp.chk('ZZNB3-1'));
  r := pg_temp.cnt('OK', 'ZZNB3-1', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  perform pg_temp.res('S1b 이미 확인된 뒤 다시 Count: 거부 「no unchecked sold-without-stock line」 — 확인 안 된 줄이 없으면 이 창구로 재고를 못 바꾼다', r like 'ERR %no unchecked sold-without-stock line for ZZNB3-1%nothing was saved', left(r, 200));

  -- ── 시나리오 2 — 실물 3 ⇒ A=3 · +4 · 메움 1 · 새 레이어 3(원가 nb-1 순서 = 다른 창고 6.00) · 원가 문 ──
  s := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-2'))->>'seen';
  r  := pg_temp.cnt('COST', 'ZZNB3-2', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 3)), null, null, false);  v := pg_temp.j(r);
  r2 := pg_temp.cnt('OK', 'ZZNB3-2', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 3)), null, null, false);    v2 := pg_temp.j(r2);
  perform pg_temp.res('P2 미리 보기 원가 문(eval 과 같은 문): 원가 열쇠 있는 매니저는 새 레이어 단가 6.00 · 출처 토론토 · 없는 매니저는 수량 · 갈래는 같고 돈 칸 null',
    (v->'lines'->0->>'delta')::numeric = 4 and (v->'lines'->0->>'fill_qty')::numeric = 1 and (v->'lines'->0->>'layer_qty')::numeric = 3 and v->'lines'->0->>'cost_branch' = 'layer_recent_other_wh'
    and (v->'lines'->0->>'layer_unit_cost')::numeric = 6 and v->'lines'->0->'cost_from'->>'warehouse' = 'Asung Trading Inc.'
    and (v2->'lines'->0->>'fill_qty')::numeric = 1 and (v2->'lines'->0->>'layer_qty')::numeric = 3 and v2->'lines'->0->>'cost_branch' = 'layer_recent_other_wh'
    and v2->'lines'->0->>'layer_unit_cost' is null and coalesce(jsonb_typeof(v2->'lines'->0->'cost_from'), 'null') = 'null',
    left(coalesce((v->'lines'->0)::text, r), 420) || ' ‖ no-cost ' || coalesce(v2->'lines'->0->>'layer_unit_cost', 'null'));
  r := pg_temp.cnt('OK', 'ZZNB3-2', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 3)), s, 'found 3 on the shelf', true);  v2 := pg_temp.j(r);  v_adj := v2->>'adjust_number';
  perform pg_temp.res('S2 시나리오 2(A −1 · 실물 3 ⇒ Count A=3): ADJ +4 · 메움 1 · 새 레이어 3 @6.00(가치 18) · 장부 3 = 레이어 3 · 줄 확인됨 · 메모는 사람이 쓴 것',
    v_adj like 'ADJ-%' and pg_temp.st('ZZNB3-2') = 'lay 3.00 val 18.00 led 3.00' and pg_temp.chk('ZZNB3-2') = 'SO-NB3-2:count:' || v_adj || ':found 3 on the shelf'
    and (select bool_and(e.qty_delta = 4 and (e.raw->'cost'->>'fill_qty')::numeric = 1 and (e.raw->'cost'->>'layer_qty')::numeric = 3) from public.inv_ledger e where e.doc_number = v_adj),
    left(r, 200) || ' ‖ ' || pg_temp.st('ZZNB3-2') || ' ‖ ' || pg_temp.chk('ZZNB3-2'));

  -- ── 시나리오 3 — UNASSIGNED −1 · 실물은 칸 B 에 2(⬜2: B 는 이 SKU 의 칸 행이 아니다) ──
  v := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-3'));  s := v->>'seen';
  r2 := pg_temp.cnt('OK', 'ZZNB3-3', jsonb_build_array(jsonb_build_object('bin', B, 'qty', 2)), s, null, true);
  r := pg_temp.cnt('OK', 'ZZNB3-3', jsonb_build_array(jsonb_build_object('bin', 'UNASSIGNED', 'qty', 0), jsonb_build_object('bin', B, 'qty', 2)), s, null, true);  v2 := pg_temp.j(r);  v_adj := v2->>'adjust_number';
  perform pg_temp.res('S3 시나리오 3(UNASSIGNED −1 · 실물은 B 에 2): 읽기에 kind unassigned · UNASSIGNED 를 빼고 B 만 세면 거부(「Count bin UNASSIGNED too」) · UNASSIGNED=0 · B=2 ⇒ 한 ADJ 두 줄 · UNASSIGNED 0 · B 2 · 메움 1 + 새 레이어 2 · 레이어 2 = 장부 2',
    v->'bins'->0->>'kind' = 'unassigned' and r2 like 'ERR %Count bin UNASSIGNED too%nothing was saved'
    and v_adj like 'ADJ-%' and pg_temp.led('ZZNB3-3', 'UNASSIGNED') = 0 and pg_temp.led('ZZNB3-3', B) = 2 and pg_temp.st('ZZNB3-3') like 'lay 2.00 val % led 2.00'
    and (select count(*) = 2 and sum((e.raw->'cost'->>'fill_qty')::numeric) = 1 and sum((e.raw->'cost'->>'layer_qty')::numeric) = 2 from public.inv_ledger e where e.doc_number = v_adj)
    and pg_temp.chk('ZZNB3-3') like 'SO-NB3-3:count:' || v_adj || ':%',
    left(r2, 140) || ' ‖ ' || left(r, 160) || ' ‖ UA ' || pg_temp.led('ZZNB3-3', 'UNASSIGNED') || ' · B ' || pg_temp.led('ZZNB3-3', B) || ' ‖ ' || pg_temp.st('ZZNB3-3'));

  -- ── 시나리오 4 — 같은 SKU × 창고에 확인 안 된 줄 둘 ──
  v := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-4'));  s := v->>'seen';
  r := pg_temp.cnt('OK', 'ZZNB3-4', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);  v2 := pg_temp.j(r);  v_adj := v2->>'adjust_number';
  perform pg_temp.res('S4 시나리오 4(오더 둘 · A −2): 읽기에 줄 2 · Count 한 번에 둘 다 확인(같은 ADJ 번호) · ADJ 하나 +2 · 메움 2 · 레이어 0 · 장부 0',
    jsonb_array_length(v->'shorts') = 2 and (v2->>'checked_count')::int = 2 and pg_temp.st('ZZNB3-4') = 'lay 0.00 val 0.00 led 0.00'
    and pg_temp.chk('ZZNB3-4') = format('SO-NB3-4a:count:%s:counted — %s / SO-NB3-4b:count:%s:counted — %s', v_adj, v_adj, v_adj, v_adj)
    and (select count(*) = 1 and bool_and((e.raw->'cost'->>'fill_qty')::numeric = 2) from public.inv_ledger e where e.doc_number = v_adj),
    left(r, 200) || ' ‖ ' || pg_temp.chk('ZZNB3-4'));

  -- ── 시나리오 5 — 세어 보니 장부와 같다 ⇒ 조정 없음 · 확인만 ──
  select last_value into v_seq0 from public.inv_adjust_number_seq;
  s := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-5'))->>'seen';
  r2 := pg_temp.cnt('OK', 'ZZNB3-5', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), null, null, false);
  r := pg_temp.cnt('OK', 'ZZNB3-5', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);  v2 := pg_temp.j(r);
  select last_value into v_seq1 from public.inv_adjust_number_seq;
  perform pg_temp.res('S5 시나리오 5(장부 맞음): 미리 보기 · 실행 둘 다 check_only · 조정 문서 0 · ADJ 번호 시퀀스 그대로 · 원장 그대로 · 확인 기록 source count · adjust_number null · 메모 「counted — matches」',
    pg_temp.j(r2)->>'action' = 'check_only' and v2->>'action' = 'check_only' and (v2->>'committed')::boolean and v2->>'adjust_number' is null and pg_temp.adjn('ZZNB3-5') = 0 and v_seq1 = v_seq0
    and pg_temp.led('ZZNB3-5', A) = 0 and pg_temp.chk('ZZNB3-5') = 'SO-NB3-5:count:-:counted — matches',
    left(r, 220) || ' ‖ ' || pg_temp.chk('ZZNB3-5') || ' · seq ' || v_seq0 || ' → ' || v_seq1);

  -- ── 시나리오 6 — 권한(판정 1176) ──
  s := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-6'))->>'seen';
  r  := pg_temp.cnt('NOKEY', 'ZZNB3-6', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  r2 := pg_temp.cnt('WKEY',  'ZZNB3-6', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  r3 := pg_temp.cnt('TOR',   'ZZNB3-6', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  r4 := pg_temp.cnt('NOKEY', 'ZZNB3-6', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), null, null, false);
  perform pg_temp.res('S6a 시나리오 6(조정 갈래): stock_adjust 없는 매니저 거부 · stock_adjust 있는 worker 거부 · 다른 창고 매니저 거부(another warehouse) · 미리 보기도 거부 · 아무것도 안 남음',
    r like 'ERR %needs the stock_adjust key%' and r2 like 'ERR %needs the stock_adjust key%' and r3 like 'ERR %another warehouse%' and r4 like 'ERR %needs the stock_adjust key%'
    and pg_temp.adjn('ZZNB3-6') = 0 and pg_temp.chk('ZZNB3-6') = 'none' and pg_temp.led('ZZNB3-6', A) = -1,
    left(r, 110) || ' ‖ ' || left(r2, 60) || ' ‖ ' || left(r3, 110) || ' ‖ ' || left(r4, 60));
  s := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-6B'))->>'seen';
  r  := pg_temp.cnt('NOKEY', 'ZZNB3-6B', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  r2 := pg_temp.cnt('WKEY',  'ZZNB3-6B', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  r3 := pg_temp.cnt('TOR',   'ZZNB3-6B', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  perform pg_temp.res('S6b 시나리오 6(장부가 맞아 확인만 하는 갈래 — 안쪽 조정 창구가 안 불리므로 바깥 문만 지킨다): 셋 다 거부 · 확인 기록 0',
    r like 'ERR %needs the stock_adjust key%' and r2 like 'ERR %needs the stock_adjust key%' and r3 like 'ERR %another warehouse%' and pg_temp.chk('ZZNB3-6B') = 'none',
    left(r, 110) || ' ‖ ' || left(r2, 110) || ' ‖ ' || left(r3, 110) || ' ‖ ' || pg_temp.chk('ZZNB3-6B'));
  r  := pg_temp.asu('NOKEY', format('select public.so_stock_short_confirm(%L, %L, %L, %L)::text', 'SO-NB3-6', 'ZZNB3-6', v_wh, 'looked'));
  r2 := pg_temp.cnt('OK', 'ZZNB3-6B', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  perform pg_temp.res('S6c 열쇠 없는 매니저의 Mark checked(so_stock_short_confirm)는 지금 그대로 됨(source manual · adjust_number 없음 · 재고 그대로) · 셋 다 맞는 매니저의 Count 는 됨',
    r like '{%' and pg_temp.chk('ZZNB3-6') = 'SO-NB3-6:manual:-:looked' and pg_temp.led('ZZNB3-6', A) = -1 and pg_temp.j(r2)->>'action' = 'check_only' and pg_temp.chk('ZZNB3-6B') like 'SO-NB3-6B:count:%',
    left(r, 140) || ' ‖ ' || pg_temp.chk('ZZNB3-6') || ' ‖ ' || pg_temp.chk('ZZNB3-6B'));

  -- ── 시나리오 7 — 경합: 미리 보기 뒤 그 SKU 가 또 팔림 ──
  s := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-7'))->>'seen';
  r4 := pg_temp.cnt('OK', 'ZZNB3-7', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), null, null, true);
  perform pg_temp.sale('SO-NB3-7b', 'l1', 'ZZNB3-7', A, 1);
  r := pg_temp.cnt('OK', 'ZZNB3-7', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  v_n := pg_temp.adjn('ZZNB3-7');  r5 := pg_temp.chk('ZZNB3-7');
  r2 := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-7'))->>'seen';
  r3 := pg_temp.cnt('OK', 'ZZNB3-7', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), r2, null, true);
  perform pg_temp.res('S7 시나리오 7(경합): seen 없이 실행 거부 · 미리 보기 뒤 또 팔리면 옛 seen 으로 실행 거부(「changed since you looked」) · 아무것도 안 남음(조정 0 · 확인 0 · 장부 −2) · 새로 읽은 seen 으로는 됨(둘 다 확인)',
    r4 like 'ERR %changed since you looked%nothing was saved' and r like 'ERR %changed since you looked%nothing was saved' and v_n = 0 and r5 = 'none' and r2 <> s
    and (pg_temp.j(r3)->>'checked_count')::int = 2 and pg_temp.st('ZZNB3-7') = 'lay 0.00 val 0.00 led 0.00',
    left(r, 150) || ' ‖ after reject: adj ' || v_n || ' · checks ' || r5 || ' ‖ ' || left(r3, 120) || ' ‖ ' || pg_temp.st('ZZNB3-7'));

  -- ── ⬜1 옛 칸 없음 행 — 보여 주기만 ──
  r := pg_temp.vw('OK', 'ZZNB3-8');  v := pg_temp.j(r);  s := v->>'seen';
  r2 := pg_temp.cnt('OK', 'ZZNB3-8', jsonb_build_array(jsonb_build_object('bin', '', 'qty', 0), jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  r3 := pg_temp.cnt('OK', 'ZZNB3-8', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  perform pg_temp.res('Q1 ⬜1 옛 칸 없음 행: 읽기에 kind no_bin · countable false · must_count false · 「Old row without a bin — fixed separately」 · 칸 없음을 세려 하면 거부 · A 만 세면 됨(오더 둘 확인) · 칸 없음 −1 은 그대로 · 반환 no_bin_qty −1',
    (select count(*) = 1 and bool_and((x->>'countable')::boolean = false and (x->>'must_count')::boolean = false and x->>'why_not' = 'Old row without a bin — fixed separately' and (x->>'ledger')::numeric = -1)
       from jsonb_array_elements(v->'bins') x where x->>'kind' = 'no_bin')
    and r2 like 'ERR %is not an active bin at%nothing was saved' and (pg_temp.j(r3)->>'checked_count')::int = 2 and (pg_temp.j(r3)->>'no_bin_qty')::numeric = -1
    and pg_temp.led('ZZNB3-8', '') = -1 and pg_temp.led('ZZNB3-8', A) = 0,
    left(coalesce((v->'bins')::text, r), 380) || ' ‖ ' || left(r2, 110) || ' ‖ ' || left(r3, 90) || ' ‖ no-bin ' || pg_temp.led('ZZNB3-8', ''));

  -- ── ⬜5 한 오더에 같은 SKU 두 줄 ──
  r2 := pg_temp.own(format('select pg_temp.sale(%L, %L, %L, %L, 1)', 'SO-NB3-9', 'l2', 'ZZNB3-9', A));
  v := pg_temp.j(pg_temp.vw('OK', 'ZZNB3-9'));  s := v->>'seen';
  r := pg_temp.cnt('OK', 'ZZNB3-9', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), s, null, true);
  perform pg_temp.res('Q5 ⬜5 한 오더에 같은 SKU 두 줄: 원가 창구(inv_layer_post_sale)가 같은 (오더 · SKU · 창고)의 둘째 부족분 레이어를 거부한다 ⇒ 열쇠 하나 = 레이어 하나 · 읽기에 한 줄(layers 1) · Count 뒤 확인 기록 하나 · 확인 안 된 레이어 0',
    r2 like 'ERR %A shortfall layer for ZZNB3-9 %already exists%'
    and jsonb_array_length(v->'shorts') = 1 and (v->'shorts'->0->>'qty')::numeric = 1 and (v->'shorts'->0->>'layers')::int = 1 and (pg_temp.j(r)->>'checked_count')::int = 1
    and (select count(*) from public.so_stock_short_check k where k.sku = 'ZZNB3-9') = 1
    and (select count(*) from public.inv_layer y where y.origin_type = 'sale_shortfall' and y.sku = 'ZZNB3-9'
          and not exists (select 1 from public.so_stock_short_check k where k.doc_number = y.doc_number and k.sku = y.sku and k.warehouse = y.warehouse)) = 0,
    left(r2, 150) || ' ‖ ' || left(coalesce((v->'shorts')::text, '-'), 200) || ' ‖ ' || left(r, 120));

  -- ── 입력 거부 ──
  r  := pg_temp.cnt('OK', 'ZZNB3-6', '[]'::jsonb, 'x', null, true);
  r2 := pg_temp.cnt('OK', 'ZZNB3-6', jsonb_build_array(jsonb_build_object('bin', A, 'qty', -1)), 'x', null, true);
  r3 := pg_temp.cnt('OK', 'ZZNB3-6', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0), jsonb_build_object('bin', A, 'qty', 1)), 'x', null, true);
  r4 := pg_temp.cnt('OK', 'ZZNB3-NONE', jsonb_build_array(jsonb_build_object('bin', A, 'qty', 0)), 'x', null, true);
  perform pg_temp.res('I 입력 거부: 빈 개수 · 음수 · 같은 칸 두 번 · 없는 SKU — 넷 다 「nothing was saved」',
    r like 'ERR %at least one bin%nothing was saved' and r2 like 'ERR %must be a number 0 or more%nothing was saved' and r3 like 'ERR %counted twice%nothing was saved' and r4 like 'ERR %not found%nothing was saved',
    left(r, 100) || ' ‖ ' || left(r2, 110) || ' ‖ ' || left(r3, 90) || ' ‖ ' || left(r4, 90));

  -- ── R3 목록 ──
  r := pg_temp.asu('OK', format('select public.so_stock_short_list(%L::jsonb)::text', jsonb_build_object('warehouse', v_wh)));  v := pg_temp.j(r);
  select x into v2 from jsonb_array_elements(v->'checked') x where x->>'doc_number' = 'SO-NB3-1';
  perform pg_temp.res('R3 목록: 확인된 줄에 adjust_number · check_source — Count 줄은 그 ADJ 번호 · count / Mark checked 줄은 null · manual / 조정 없이 확인만은 null · count · 옛 칸 19 개는 전부 그대로(지운 칸 0)',
    v2->>'adjust_number' like 'ADJ-%' and v2->>'check_source' = 'count'
    and (select x ? 'adjust_number' and x->>'adjust_number' is null and x->>'check_source' = 'manual' from jsonb_array_elements(v->'checked') x where x->>'doc_number' = 'SO-NB3-6')
    and (select x->>'adjust_number' is null and x->>'check_source' = 'count' from jsonb_array_elements(v->'checked') x where x->>'doc_number' = 'SO-NB3-5')
    and (select bool_and(v2 ? kk) from unnest(c_keys) kk)
    and (select count(*) from jsonb_array_elements(v->'unchecked') x where x->>'sku' like 'ZZNB3-%') = 0,
    left(coalesce(v2::text, r), 500));

  -- ── 표 제약 ──
  r  := pg_temp.own(format('insert into public.so_stock_short_check (doc_number, sku, warehouse, checked_by, source, adjust_number) values (%L, %L, %L, %L, %L, %L)', 'SO-NB3-X1', 'ZZNB3-1', v_wh, (select s2.id from public.ims_staff s2 where s2.auth_user_id = pg_temp.id('uOK')), 'manual', v_adj));
  r2 := pg_temp.own(format('insert into public.so_stock_short_check (doc_number, sku, warehouse, checked_by, source, adjust_number) values (%L, %L, %L, %L, %L, %L)', 'SO-NB3-X2', 'ZZNB3-1', v_wh, (select s2.id from public.ims_staff s2 where s2.auth_user_id = pg_temp.id('uOK')), 'count', 'ADJ-NOPE'));
  r3 := pg_temp.own(format('insert into public.so_stock_short_check (doc_number, sku, warehouse, checked_by, source) values (%L, %L, %L, %L, %L)', 'SO-NB3-X3', 'ZZNB3-1', v_wh, (select s2.id from public.ims_staff s2 where s2.auth_user_id = pg_temp.id('uOK')), 'other'));
  perform pg_temp.res('T 표 제약: Mark checked(manual)에 ADJ 번호를 달면 거부 · 없는 ADJ 번호 거부(FK) · 모르는 source 거부',
    r like 'ERR 23514%so_stock_short_check_adjust_ck%' and r2 like 'ERR 23503%' and r3 like 'ERR 23514%so_stock_short_check_source_ck%', left(r, 120) || ' ‖ ' || left(r2, 120) || ' ‖ ' || left(r3, 120));

  -- ── 정적 · 권한 ──
  perform pg_temp.res('N nowhere 정적: 새 함수 셋 + 재발행 목록에 WHERE 없는 update · delete 0(스캐너 자기 시험 포함)',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text = '101'
    and (select count(*) = 4 and sum(pg_temp.nowhere(p.prosrc)) = 0 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_stock_short_count', 'so_stock_short_count_view', 'so_stock_short_count_state', 'so_stock_short_list')),
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'so_stock_short%'));
  perform pg_temp.res('A 권한: 창구 둘(count · count_view)은 authenticated 실행 · anon 없음 · 안 도우미(count_state)는 직원이 못 부른다 · 넷 다 definer · so_stock_short_confirm 의 몸은 그대로(md5)',
    (select count(*) = 3 and bool_and(p.prosecdef) and bool_and(not has_function_privilege('anon', p.oid, 'execute'))
            and bool_and(has_function_privilege('authenticated', p.oid, 'execute') = (p.proname <> 'so_stock_short_count_state'))
       from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_stock_short_count', 'so_stock_short_count_view', 'so_stock_short_count_state'))
    and has_function_privilege('authenticated', 'public.so_stock_short_list(jsonb)', 'execute') and not has_function_privilege('anon', 'public.so_stock_short_list(jsonb)', 'execute')
    and pg_temp.asu('OK', format('select public.so_stock_short_count_state(%L, %L)::text', pg_temp.id('p1'), current_setting('d.wh'))) like 'ERR 42501%'
    and (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_stock_short_confirm(text,text,text,text)'::regprocedure) = 'd2c148e7011616d8b875a8446aba7e41',
    (select string_agg(p.proname || ' ' || coalesce(p.proacl::text, '-') || ' definer ' || p.prosecdef, ' ‖ ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname like 'so_stock_short%')
    || ' ‖ confirm md5 ' || (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_stock_short_confirm(text,text,text,text)'::regprocedure));

  -- ── Z 실물 무접촉 ──
  perform pg_temp.res('Z 실물 무접촉: 가짜(ZZNB3 · NB3) 밖의 원장 · 레이어 · 조정 문서 · 확인 기록 수가 머리와 같다 · 임시(PREVIEW) 조정 행 0 · claims 비었음 · postgres',
    (select count(*) from public.inv_ledger e where e.sku not like 'ZZNB3-%')::text || '/' || (select count(*) from public.inv_layer y where y.sku not like 'ZZNB3-%')::text || '/'
      || (select count(*) from public.inv_adjust a where a.note is null or a.note not like 'Count & check — ZZNB3-%')::text || '/' || (select count(*) from public.so_stock_short_check k where k.sku not like 'ZZNB3-%')::text = current_setting('d.real_head')
    and (select count(*) from public.inv_adjust a where a.adjust_number like 'PREVIEW-%') = 0
    and coalesce(current_setting('request.jwt.claims', true), '') = '' and current_user = 'postgres',
    format('head %s · now %s/%s/%s/%s · user %s', current_setting('d.real_head'), (select count(*) from public.inv_ledger e where e.sku not like 'ZZNB3-%'), (select count(*) from public.inv_layer y where y.sku not like 'ZZNB3-%'),
           (select count(*) from public.inv_adjust a where a.note is null or a.note not like 'Count & check — ZZNB3-%'), (select count(*) from public.so_stock_short_check k where k.sku not like 'ZZNB3-%'), current_user));
end $$;
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · adj seq ' || :'seq_head' || ' → ' || (select last_value::text from public.inv_adjust_number_seq)
       || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
rollback;
-- 조정 번호 시퀀스 되돌림(시퀀스는 rollback 을 따르지 않는다): 머리 값과 실제 최대 ADJ 번호 중 큰 쪽 — 시험 중 실제 직원이 조정을 만들었어도 그 번호 아래로 내려가지 않는다
select 'adj seq restored → ' || setval('public.inv_adjust_number_seq', greatest(:'seq_head'::bigint, coalesce((select max(substring(a.adjust_number from 5)::bigint) from public.inv_adjust a where a.adjust_number ~ '^ADJ-[0-9]+$'), 0), 1))::text
       || ' (head ' || :'seq_head' || ')';
\pset tuples_only off
\pset format aligned
-- 기대: 시험(-v mig) OK 22 · FAIL 0 · 마른 실행(적용 전 · -v mig 없음) OK 1(Z) · FAIL 21(창구 · 칸이 없다 — 시나리오 1 포함) · 확인(적용 뒤 · -v mig 없음) OK 22 · FAIL 0
--       adj seq 는 시험 · 확인에서 +7(실행 갈래의 ADJ 일곱 — 1 · 2 · 3 · 4 · 7 · 8 · 9) 뒤 끝에서 머리 값으로 되돌아간다 · 미리 보기 · 확인만(5 · 6B) · 거부는 번호를 안 쓴다 · 시험 begin ~ 끝 약 11 초(2026-11-11 실측)
--       변이(2026-11-11): 조정 없이 확인만 하는 판(if false) → FAIL 10(P1 · S1 · P2 · S2 · S3 · S4 · S7 · Q1 · R3 · T) · 권한 문을 매니저만으로 둔 판(so_require_role) → FAIL 3(S6a · S6b · S6c)
