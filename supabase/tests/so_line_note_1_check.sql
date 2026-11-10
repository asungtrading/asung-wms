-- so-line-note-1 검증 — supabase/migrations/20261110041823_so_line_note_1.sql (SO 손님용 줄 메모 so_line_note · 판정 1151 · 지시서 ~/asung/prompts/so-line-note-1.md §2 · asung-workflow §4 틀)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261110041823_so_line_note_1.sql -f supabase/tests/so_line_note_1_check.sql 2>&1 | tee /tmp/so_line_note_1.out
--   마른 실행(적용 전) · 확인(적용 뒤 · Caleb): 같은 명령에서 -v mig=… 만 뺀다 — 마른 실행은 1 · 4 · 6(과 2 · 5 · 7 · 9 · 10)이 FAIL 로 잡힌다(결함 재현) · 확인은 8a(옛 = 새)만 건너뛴다
--   ⚠️ 실제 행 무변: 가짜 오더 아홉(SO-9999990001 ~ 09 · 실제 오더의 복사 · 만든 시각 2001-01-01) · 가짜 인보이스 하나(9999999901 · 표에 직접 — 인보이스 번호 시퀀스 무접촉) · 창구는 가짜 id 로만 · 끝은 rollback
--   ⚠️ 합치기(so_merge 실행)가 so_number_seq 를 한 번 쓴다 — rollback 해도 번호 하나가 건너뛴다(Caleb 11-10 받아들임) · 마른 실행(표 없음)은 합치기를 돌리지 않아 번호를 안 쓴다
--   ⚠️ so_line 잠금: 시험 적용이 so_line_note 의 FK 를 만들며 so_line 에 SHARE ROW EXCLUSIVE 를 잡는다(줄 쓰기가 rollback 까지 기다린다) — lock_timeout 3 s · 표는 마이그레이션 맨 뒤 · 그 뒤는 문장 넷
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
-- ── 머리(읽기) — 복사 원본 셋 · 직원 신원 · 무접촉 함수 스냅샷 ──
select
  (select s.id::text from public.so s where s.status = 'confirmed' and s.intake = 'manual' and s.channel = 'warehouse' and s.split_from_id is null and s.coupon_id is null
     and (select count(distinct l.product_id) from public.so_line l where l.so_id = s.id and l.combo_line_id is null and l.free_reason is null and l.bgrade_bin_id is null and l.unit_price > 0 and not l.price_override
            and l.discount_source is distinct from 'manual' and l.discount_source is distinct from 'deal' and not exists (select 1 from public.so_line c where c.combo_line_id = l.id)) >= 3
   order by s.updated_at desc limit 1) as src,
  (select s.id::text from public.so s where s.intake = 'shopify' and s.status = 'confirmed' and exists (select 1 from public.so_line l where l.so_id = s.id and l.combo_line_id is null) order by s.updated_at desc limit 1) as srcw,
  (select i.id::text from public.so_invoice i where i.kind = 'sale' and i.status = 'issued' and (select count(*) from public.so_invoice_order o where o.invoice_id = i.id) = 1
     and (select count(*) from public.so_invoice_line l where l.invoice_id = i.id and l.kind = 'product') between 2 and 8
     and not exists (select 1 from public.so_invoice_order o join public.so_line sl on sl.so_id = o.so_id where o.invoice_id = i.id and (sl.combo_line_id is not null or sl.free_reason is not null))
   order by i.issued_on desc, i.invoice_number desc limit 1) as srci,
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff,
  (select st.id::text from public.ims_staff st where st.is_active and st.role = 'admin' and st.auth_user_id is not null order by st.created_at limit 1) as staff_id,
  coalesce((select st.auth_user_id::text from public.ims_staff st where st.is_active and st.role = 'worker' and not (st.perms ? 'sales') and st.auth_user_id is not null order by st.created_at limit 1), gen_random_uuid()::text) as nosales,
  (select c.name from public.ref_carrier c where c.is_active and c.kind <> 'carrier' order by c.name limit 1) as carrier,
  (select md5(string_agg(p.proname || ':' || md5(p.prosrc), '|' order by p.proname)) from pg_proc p where p.pronamespace = 'public'::regnamespace
     and p.proname in ('so_line_add', 'so_line_update', 'so_combo_children_insert', 'so_line_remove', 'so_lines_clear', 'doc_data', 'doc_data_invoice_fmt', 'doc_field_catalog', 'doc_data_credit', 'doc_data_ship_ready', 'so_invoice_issue', 'so_proforma')) as snap_fn,
  (to_regclass('public.so_line_note') is not null)::int as applied_head,
  (select last_value::text from public.so_number_seq) as seq_head \gset
select 'head: applied ' || :applied_head || ' · so_number_seq ' || :'seq_head' || ' · src ' || left(:'src', 8) || ' · srcw ' || left(:'srcw', 8) || ' · srci ' || left(:'srci', 8) || ' · staff ' || left(:'staff', 8);

begin;
set local lock_timeout = '3s';
select set_config('d.src', :'src', true), set_config('d.srcw', :'srcw', true), set_config('d.srci', :'srci', true), set_config('d.staff', :'staff', true), set_config('d.staff_id', :'staff_id', true),
       set_config('d.nosales', :'nosales', true), set_config('d.carrier', :'carrier', true), set_config('d.snap_fn', :'snap_fn', true), clock_timestamp() as t_begin \gset
create temp table t_ids (k text primary key, id uuid not null) on commit drop;
create temp table t_res (seq serial, tag text, ok boolean, detail text) on commit drop;
create temp table t_old (k text primary key, v text) on commit drop;

-- ── 도우미(시험 적용 앞에 — 표 잠금 뒤 문장 수를 줄인다) ──
create function pg_temp.id(p_k text) returns uuid language sql as $$ select t.id from t_ids t where t.k = p_k $$;
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 600)) $$;
create function pg_temp.j(p text) returns jsonb language sql as $$ select case when left(p, 1) in ('{', '[') then p::jsonb end $$;
-- 직원 신원(claims + role authenticated)으로 한 문장 — 예외는 'ERR <sqlstate>: <문장>' 글자로(그 문장의 쓰기는 되돌아간다)
create function pg_temp.asu(p_sql text, p_sub text default null) returns text language plpgsql as $$
declare v_out text;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', coalesce(p_sub, current_setting('d.staff'))), true);
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
-- 손님 메모 읽기(표가 없으면 null — 마른 실행이 FAIL 로 끝나게)
create function pg_temp.note_of(p_line uuid) returns text language plpgsql as $$
declare v text;
begin
  if to_regclass('public.so_line_note') is null then return null; end if;
  execute 'select sn.note from public.so_line_note sn where sn.so_line_id = $1' into v using p_line;
  return v;
end $$;
-- 행 복사(생성 칸 제외 · 칸이 늘어도 따라온다)
create function pg_temp.cp(p_tbl regclass, p_row jsonb) returns void language plpgsql as $$
declare v_cols text;
begin
  select string_agg(quote_ident(a.attname), ', ' order by a.attnum) into v_cols from pg_attribute a where a.attrelid = p_tbl and a.attnum > 0 and not a.attisdropped and a.attgenerated = '';
  execute format('insert into %s (%s) select %s from jsonb_populate_record(null::%s, $1)', p_tbl, v_cols, v_cols, p_tbl) using p_row;
end $$;
-- 열쇠를 깊이와 상관없이 뗀다(시각 · 새 열쇠)
create function pg_temp.wo(p jsonb, p_keys text[]) returns jsonb language sql as $$
  select case jsonb_typeof(p)
    when 'object' then (select coalesce(jsonb_object_agg(e.key, pg_temp.wo(e.value, p_keys)), '{}'::jsonb) from jsonb_each(p) e where not (e.key = any (p_keys)))
    when 'array' then (select coalesce(jsonb_agg(pg_temp.wo(e.value, p_keys) order by e.ord), '[]'::jsonb) from jsonb_array_elements(p) with ordinality e(value, ord))
    else p end $$;
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
-- 부르는 글(옛 · 새 같은 글)
create function pg_temp.q(p_k text) returns text language sql as $$
  select case p_k
    when 'so_c'  then format('select public.doc_data(''sales_order'', %L)::text', jsonb_build_object('so_id', pg_temp.id('C')))
    when 'inv_f' then format('select public.doc_data(''final_invoice'', %L)::text', jsonb_build_object('invoice_id', pg_temp.id('FI')))
    when 'det_c' then format('select public.so_detail(%L)::text', pg_temp.id('C'))
    when 'pv_p'  then format('select public.so_invoice_preview(%L, null)::text', jsonb_build_array(jsonb_build_object('so_id', pg_temp.id('P'), 'carrier', current_setting('d.carrier'),
                        'picks', (select jsonb_agg(jsonb_build_object('line_id', l.id, 'bin', 'ZZ-NOTE', 'qty', l.qty_ordered) order by l.line_no) from public.so_line l where l.so_id = pg_temp.id('P')))))
  end $$;
create function pg_temp.qset(p_line uuid, p_note text) returns text language sql as $$ select format('select public.so_line_note_set(%L, %L)::text', p_line, p_note) $$;
create function pg_temp.qpaste(p_so uuid, p_lines jsonb, p_commit boolean) returns text language sql as $$ select format('select public.so_lines_paste(%L, %L, %L)::text', p_so, p_lines, p_commit) $$;
-- 손댐 스냅샷(가짜 오더의 so · so_line 행 통째)
create function pg_temp.snap(p_so uuid[], p_lines_of uuid[]) returns text language sql as $$
  select md5(coalesce(string_agg(t.x, '|' order by t.x), '')) from (
    select 'so:' || md5(to_jsonb(s)::text) as x from public.so s where s.id = any (p_so)
    union all select 'sl:' || l.id || ':' || md5(to_jsonb(l)::text) from public.so_line l where l.so_id = any (p_lines_of)) t $$;
-- 실물(복사 원본) 스냅샷
create function pg_temp.real_snap() returns text language sql as $$
  select md5(coalesce(string_agg(t.x, '|' order by t.x), '')) from (
    select 'so:' || md5(to_jsonb(s)::text) as x from public.so s where s.id in (current_setting('d.src')::uuid, current_setting('d.srcw')::uuid) or s.id in (select o.so_id from public.so_invoice_order o where o.invoice_id = current_setting('d.srci')::uuid)
    union all select 'sl:' || l.id || md5(to_jsonb(l)::text) from public.so_line l where l.so_id in (current_setting('d.src')::uuid, current_setting('d.srcw')::uuid) or l.so_id in (select o.so_id from public.so_invoice_order o where o.invoice_id = current_setting('d.srci')::uuid)
    union all select 'iv:' || md5(to_jsonb(i)::text) from public.so_invoice i where i.id = current_setting('d.srci')::uuid
    union all select 'il:' || l.id || md5(to_jsonb(l)::text) from public.so_invoice_line l where l.invoice_id = current_setting('d.srci')::uuid) t $$;

-- ── 가짜 행(트리거 없이 · 실제 오더의 복사 · 만든 시각 = 2001-01-01 표지) ──
do $$
declare
  c_mark  constant timestamptz := '2001-01-01 00:00:00+00';
  v_src   jsonb;  v_w jsonb;  v_inv jsonb;  v_o jsonb;  v_fso jsonb;
  v_staff uuid := current_setting('d.staff_id')::uuid;
  k text;  i int := 0;  n int;  v_id uuid;  v_l record;
  c_null  constant jsonb := jsonb_build_object('split_from_id', null, 'split_reason', null, 'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
                                               'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null, 'unconfirmed_at', null, 'unconfirmed_by', null, 'coupon_id', null);
  c_line  constant jsonb := jsonb_build_object('qty_ordered', 10, 'qty_shipped', 0, 'qty_removed', 0, 'removed_reason', null, 'removed_note', null, 'removed_at', null, 'removed_by', null,
                                               'split_from_line_id', null, 'comments', null, 'backorder_notified_at', null, 'created_at', c_mark, 'updated_at', c_mark);
begin
  execute 'set local session_replication_role = replica';
  select to_jsonb(s) into v_src from public.so s where s.id = current_setting('d.src')::uuid;
  foreach k in array array['A', 'B', 'C', 'U', 'M1', 'M2', 'P'] loop
    i := i + 1;  v_id := gen_random_uuid();
    insert into t_ids values (k, v_id);
    perform pg_temp.cp('public.so', v_src || c_null || jsonb_build_object('id', v_id, 'so_number', 'SO-99999900' || lpad(i::text, 2, '0'),
      'status', case when k in ('A', 'M1', 'M2') then 'draft' when k = 'P' then 'packed' else 'confirmed' end,
      'confirmed_at', case when k in ('A', 'M1', 'M2') then null else now() end, 'confirmed_by', case when k in ('A', 'M1', 'M2') then null else v_staff end,
      'created_at', c_mark, 'updated_at', c_mark));
    n := 0;
    for v_l in
      select x.* from (select distinct on (l.product_id) l.* from public.so_line l
                       where l.so_id = current_setting('d.src')::uuid and l.combo_line_id is null and l.free_reason is null and l.bgrade_bin_id is null and l.unit_price > 0 and not l.price_override
                         and l.discount_source is distinct from 'manual' and l.discount_source is distinct from 'deal' and not exists (select 1 from public.so_line c where c.combo_line_id = l.id)
                       order by l.product_id, l.line_no) x
      order by x.line_no limit 3
    loop
      n := n + 1;
      continue when k = 'A' and n = 3;                                          -- A 는 두 줄(셋째 SKU 는 붙여 넣기로 들어온다)
      v_id := gen_random_uuid();
      insert into t_ids values (k || '.' || n, v_id);
      perform pg_temp.cp('public.so_line', to_jsonb(v_l) || c_line || jsonb_build_object('id', v_id, 'so_id', pg_temp.id(k), 'line_no', n));
    end loop;
  end loop;
  -- C.2 = 무상 other 줄(사내 까닭 INTERNAL-ONLY — 문서에 나오면 안 된다)
  update public.so_line set free_reason = 'other', unit_price = 0, discount_pct = null, discount_source = null, deal_line_id = null, surcharge_pct = null, surcharge_amount = null, surcharge_label = null, comments = 'INTERNAL-ONLY'
   where id = pg_temp.id('C.2');
  -- A.c = A.2 에 매단 가짜 구성품 줄
  v_id := gen_random_uuid();
  insert into t_ids values ('A.c', v_id);
  perform pg_temp.cp('public.so_line', (select to_jsonb(l) from public.so_line l where l.id = pg_temp.id('A.2')) || jsonb_build_object('id', v_id, 'line_no', 9, 'combo_line_id', pg_temp.id('A.2'), 'combo_qty', 1, 'unit_price', 0,
    'list_price', null, 'discount_pct', null, 'discount_source', null, 'deal_line_id', null, 'price_override', false, 'surcharge_pct', null, 'surcharge_amount', null, 'surcharge_label', null, 'price_set_by', null, 'price_set_at', null, 'free_reason', null));
  -- W = 웹 오더(intake shopify) 복사 · 한 줄
  select to_jsonb(s) into v_w from public.so s where s.id = current_setting('d.srcw')::uuid;
  v_id := gen_random_uuid();  insert into t_ids values ('W', v_id);
  perform pg_temp.cp('public.so', v_w || c_null || jsonb_build_object('id', v_id, 'so_number', 'SO-9999990008', 'status', 'confirmed', 'created_at', c_mark, 'updated_at', c_mark));
  v_id := gen_random_uuid();  insert into t_ids values ('W.1', v_id);
  perform pg_temp.cp('public.so_line', (select to_jsonb(l) from public.so_line l where l.so_id = current_setting('d.srcw')::uuid and l.combo_line_id is null order by l.line_no limit 1) || c_line || jsonb_build_object('id', v_id, 'so_id', pg_temp.id('W'), 'line_no', 1));
  -- F = 인보이스가 선 오더(fulfilled) 복사 + 가짜 인보이스 9999999901(표에 직접 · 번호 시퀀스 무접촉)
  select to_jsonb(iv) into v_inv from public.so_invoice iv where iv.id = current_setting('d.srci')::uuid;
  select to_jsonb(o) into v_o from public.so_invoice_order o where o.invoice_id = current_setting('d.srci')::uuid;
  select to_jsonb(s) into v_fso from public.so s where s.id = (v_o->>'so_id')::uuid;
  v_id := gen_random_uuid();  insert into t_ids values ('F', v_id);
  perform pg_temp.cp('public.so', v_fso || jsonb_build_object('id', v_id, 'so_number', 'SO-9999990009', 'split_from_id', null, 'split_reason', null, 'coupon_id', null, 'created_at', c_mark, 'updated_at', c_mark));
  for v_l in select l.* from public.so_line l where l.so_id = (v_o->>'so_id')::uuid order by l.line_no loop
    v_id := gen_random_uuid();  insert into t_ids values ('Fm.' || v_l.id, v_id);
    perform pg_temp.cp('public.so_line', to_jsonb(v_l) || jsonb_build_object('id', v_id, 'so_id', pg_temp.id('F'), 'split_from_line_id', null, 'comments', null, 'created_at', c_mark, 'updated_at', c_mark));
  end loop;
  insert into t_ids values ('FI', gen_random_uuid()), ('FO', gen_random_uuid());
  perform pg_temp.cp('public.so_invoice', v_inv || jsonb_build_object('id', pg_temp.id('FI'), 'invoice_number', '9999999901'));
  perform pg_temp.cp('public.so_invoice_order', v_o || jsonb_build_object('id', pg_temp.id('FO'), 'invoice_id', pg_temp.id('FI'), 'so_id', pg_temp.id('F')));
  n := 0;
  for v_l in select l.* from public.so_invoice_line l where l.invoice_id = current_setting('d.srci')::uuid order by l.line_no loop
    perform pg_temp.cp('public.so_invoice_line', to_jsonb(v_l) || jsonb_build_object('id', gen_random_uuid(), 'invoice_id', pg_temp.id('FI'), 'invoice_order_id', pg_temp.id('FO'),
      'so_line_id', case when v_l.so_line_id is not null then pg_temp.id('Fm.' || v_l.so_line_id) end));
    if v_l.kind = 'product' then
      n := n + 1;
      if n <= 2 then insert into t_ids values ('F.' || n, pg_temp.id('Fm.' || v_l.so_line_id)); end if;
    end if;
  end loop;
  update public.so_line set comments = 'INTERNAL-ONLY' where id = pg_temp.id('F.2');
  execute 'set local session_replication_role = origin';
end $$;

\if :{?mig}
-- ── O 시험에서만: 적용 전 옛 출력(메모 없는 가짜 문서 넷) ──
insert into t_old select x.k, pg_temp.asu(pg_temp.q(x.k)) from unnest(array['so_c', 'inv_f', 'det_c', 'pv_p']) x(k);
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 검증(한 문장) ──
create function pg_temp.run() returns void language plpgsql as $$
declare
  v_has  boolean := to_regclass('public.so_line_note') is not null;
  v_st   uuid := current_setting('d.staff_id')::uuid;
  a1 uuid := pg_temp.id('A.1');  a2 uuid := pg_temp.id('A.2');  ac uuid := pg_temp.id('A.c');
  b1 uuid := pg_temp.id('B.1');  w1 uuid := pg_temp.id('W.1');  f1 uuid := pg_temp.id('F.1');  f2 uuid := pg_temp.id('F.2');
  c1 uuid := pg_temp.id('C.1');  c2 uuid := pg_temp.id('C.2');  c3 uuid := pg_temp.id('C.3');
  u1 uuid := pg_temp.id('U.1');  u2 uuid := pg_temp.id('U.2');  u3 uuid := pg_temp.id('U.3');  p1 uuid := pg_temp.id('P.1');
  v_sku1 text;  v_sku2 text;  v_sku3 text;
  r text;  r2 text;  r3 text;  r4 text;  r5 text;  r6 text;  d jsonb;  v_k text;  v_ok boolean;  v_det text;  v_state text;
  v_snap0 text;  v_real0 text;  v_sib uuid;  v_n1 uuid;  v_n2 uuid;  v_n3 uuid;  v_cnt int;
begin
  select l.sku into v_sku1 from public.so_line l where l.id = c1;
  select l.sku into v_sku2 from public.so_line l where l.id = c2;
  select l.sku into v_sku3 from public.so_line l where l.id = c3;
  v_real0 := pg_temp.real_snap();
  v_snap0 := pg_temp.snap(array[pg_temp.id('A'), pg_temp.id('W'), pg_temp.id('F')], array[pg_temp.id('A'), pg_temp.id('W'), pg_temp.id('F'), pg_temp.id('B')]);

  -- 8a 회귀(시험에서만): 옛 출력 = 새 출력(메모를 쓰기 전 · 시각 · 새 열쇠만 떼고 · 옛 문서에 찍히던 사내 글 INTERNAL-ONLY 만 빈칸으로)
  if exists (select 1 from t_old) then
    v_ok := true;  v_det := '';
    for v_k in select o.k from t_old o order by o.k loop
      r := (select o.v from t_old o where o.k = v_k);  r2 := pg_temp.asu(pg_temp.q(v_k));
      if left(r, 3) = 'ERR' or left(r2, 3) = 'ERR'
         or pg_temp.wo(pg_temp.j(case when v_k in ('so_c', 'inv_f') then replace(r, '"INTERNAL-ONLY"', '""') else r end), array['printed_at', 'calc_at']) is distinct from pg_temp.wo(pg_temp.j(r2), array['printed_at', 'calc_at', 'customer_note']) then
        v_ok := false;  v_det := v_det || v_k || ': old ' || left(r, 200) || ' · new ' || left(r2, 200) || ' ; ';
      end if;
    end loop;
    perform pg_temp.res('8a 회귀: 문서 데이터 · so_detail · so_invoice_preview 의 다른 열쇠 무변(옛 = 새 · sales_order · final_invoice · so_detail · preview)', v_ok and (select count(*) from t_old) = 4, v_det);
  end if;

  -- 1 쓰기 · 고치기 · 지우기 · 길이
  r := pg_temp.asu(pg_temp.qset(a1, E'  Hello \n\t  world  '));
  perform pg_temp.res('1a 쓰기(draft · 한 줄로 굳힘)', pg_temp.j(r)->>'action' = 'saved' and pg_temp.j(r)->>'customer_note' = 'Hello world' and pg_temp.j(r)->>'line_id' = a1::text and pg_temp.note_of(a1) = 'Hello world', r);
  r := pg_temp.asu(pg_temp.qset(a1, 'Changed'));  r2 := pg_temp.asu(pg_temp.qset(a1, ' Changed '));
  perform pg_temp.res('1b 고치기 · 같은 글은 unchanged', pg_temp.j(r)->>'action' = 'saved' and pg_temp.j(r2)->>'action' = 'unchanged' and pg_temp.note_of(a1) = 'Changed', r || ' / ' || r2);
  r := pg_temp.asu(pg_temp.qset(a1, E'  \n '));
  perform pg_temp.res('1c 지우기(빈칸 → 행 없음)', pg_temp.j(r)->>'action' = 'cleared' and pg_temp.j(r)->'customer_note' = 'null'::jsonb and pg_temp.note_of(a1) is null, r);
  r := pg_temp.asu(pg_temp.qset(a1, repeat('x', 501)));  r2 := pg_temp.asu(pg_temp.qset(a1, repeat('x', 500)));  r3 := pg_temp.asu(pg_temp.qset(a1, null));
  perform pg_temp.res('1d 길이 상한(501 거부 · 500 통과) · null = 지움', r like 'ERR %limit is 500%' and pg_temp.j(r2)->>'action' = 'saved' and pg_temp.j(r3)->>'action' = 'cleared' and pg_temp.note_of(a1) is null, left(r, 200) || ' / ' || left(r2, 60) || ' / ' || r3);

  -- 2 상태별
  v_ok := true;  v_det := '';
  foreach v_state in array array['confirmed', 'at_wms', 'picking', 'packed', 'shipped', 'fulfilled'] loop
    execute 'set local session_replication_role = replica';
    update public.so set status = v_state, closed_at = case when v_state = 'fulfilled' then now() end where id = pg_temp.id('B');
    execute 'set local session_replication_role = origin';
    r := pg_temp.asu(pg_temp.qset(b1, 'st ' || v_state));
    v_ok := v_ok and coalesce(pg_temp.j(r)->>'action' = 'saved' and pg_temp.note_of(b1) = 'st ' || v_state, false);
    v_det := v_det || v_state || ' ' || left(r, 90) || ' ; ';
  end loop;
  perform pg_temp.res('2a 상태별 허용: confirmed · at_wms · picking · packed · shipped · fulfilled', v_ok, v_det);
  execute 'set local session_replication_role = replica';
  update public.so set status = 'cancelled', closed_reason = 'voided', closed_at = now() where id = pg_temp.id('B');
  execute 'set local session_replication_role = origin';
  r := pg_temp.asu(pg_temp.qset(b1, 'after cancel'));
  perform pg_temp.res('2b cancelled 거부(메모 그대로)', r like 'ERR %is cancelled%nothing was saved%' and pg_temp.note_of(b1) = 'st fulfilled', r);
  r := pg_temp.asu(pg_temp.qset(w1, 'web note'));  r2 := pg_temp.asu(pg_temp.qset(f1, 'DOC-NOTE-F'));
  perform pg_temp.res('2c 웹 오더(intake shopify) · 인보이스 뒤(fulfilled + 인보이스) 허용',
    pg_temp.j(r)->>'action' = 'saved' and pg_temp.j(r2)->>'action' = 'saved' and (select s.intake from public.so s where s.id = pg_temp.id('W')) = 'shopify' and pg_temp.note_of(w1) = 'web note' and pg_temp.note_of(f1) = 'DOC-NOTE-F', r || ' / ' || r2);
  r := pg_temp.asu(pg_temp.qset(ac, 'x'));  r2 := pg_temp.asu(pg_temp.qset(gen_random_uuid(), 'x'));
  perform pg_temp.res('2d 콤보 구성품 줄 거부 · 없는 줄 거부', r like 'ERR %component of combo%' and r2 like 'ERR %Order line not found%' and pg_temp.note_of(ac) is null, r || ' / ' || r2);

  -- 3 so_line · so 무변(판정 434 · Unconfirm 판단 보호)
  perform pg_temp.res('3 so · so_line 행 무변: 메모 쓰기 · 고치기 · 지우기 뒤 가짜 오더 A · W · F 의 so 행과 A · W · F · B 의 so_line 행이 그대로(updated_at 포함)',
    pg_temp.snap(array[pg_temp.id('A'), pg_temp.id('W'), pg_temp.id('F')], array[pg_temp.id('A'), pg_temp.id('W'), pg_temp.id('F'), pg_temp.id('B')]) = v_snap0
    and (select count(*) from public.so_line l where l.so_id in (pg_temp.id('A'), pg_temp.id('W'), pg_temp.id('F'), pg_temp.id('B')) and l.updated_at <> '2001-01-01 00:00:00+00') = 0, 'snap');

  -- 4 문서
  perform pg_temp.asu(pg_temp.qset(c1, 'DOC-NOTE-C'));
  r := pg_temp.asu(pg_temp.q('so_c'));  d := pg_temp.j(r);
  perform pg_temp.res('4a doc_data sales_order: 줄 comment = 손님 메모 · 사내 comments(무상 other 줄 INTERNAL-ONLY)는 안 나온다',
    (select count(*) from jsonb_path_query(d, 'strict $.**.lines[*]') x where x->>'sku' = v_sku1 and x->>'comment' = 'DOC-NOTE-C') = 1
    and (select count(*) from jsonb_path_query(d, 'strict $.**.lines[*]') x where x->>'sku' = v_sku2 and x->>'comment' = '') = 1
    and r not like '%INTERNAL-ONLY%' and (select count(*) from jsonb_path_query(d, 'strict $.**.lines[*]') x) = 3,
    left(r, 100) || ' … comments ' || coalesce((select string_agg(coalesce(x->>'sku', '?') || '=' || coalesce(x->>'comment', '(null)'), ', ') from jsonb_path_query(d, 'strict $.**.lines[*]') x), '(no lines)'));
  r := pg_temp.asu(pg_temp.q('inv_f'));  d := pg_temp.j(r);
  perform pg_temp.res('4b doc_data final_invoice(가짜 인보이스 9999999901): 줄 comment = 손님 메모 · 사내 comments 는 안 나온다',
    (select count(*) from jsonb_path_query(d, 'strict $.**.lines[*]') x where x->>'comment' = 'DOC-NOTE-F') = 1
    and (select count(*) from jsonb_path_query(d, 'strict $.**.lines[*]') x where x->>'comment' <> '' and x->>'comment' <> 'DOC-NOTE-F') = 0
    and r not like '%INTERNAL-ONLY%' and (select count(*) from jsonb_path_query(d, 'strict $.**.lines[*]') x) >= 2,
    left(r, 100) || ' … comments ' || coalesce((select string_agg(coalesce(x->>'sku', '?') || '=' || coalesce(x->>'comment', '(null)'), ', ') from jsonb_path_query(d, 'strict $.**.lines[*]') x), '(no lines)'));
  perform pg_temp.asu(pg_temp.qset(p1, 'DOC-NOTE-P'));
  r := pg_temp.asu(pg_temp.q('pv_p'));  d := pg_temp.j(r);
  perform pg_temp.res('4c so_invoice_preview(가짜 packed 오더): 줄 comment = 손님 메모 · 본문에 sl.comments 없음',
    (select count(*) from jsonb_path_query(d, 'strict $.**.lines[*]') x where x->>'comment' = 'DOC-NOTE-P') = 1
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('doc_data_so', 'doc_data_invoice', 'so_invoice_preview') and p.prosrc !~ 'sl\.comments' and p.prosrc ~ 'so_line_note') = 3,
    left(r, 300));

  -- 10 so_detail(화면이 읽는 길)
  r := pg_temp.asu(pg_temp.q('det_c'));  d := pg_temp.j(r);
  perform pg_temp.res('10 so_detail 줄 열쇠 customer_note: 메모 있는 줄 = 글 · 없는 줄 = null(열쇠는 있다) · 사내 comments 는 그대로',
    (select count(*) from jsonb_array_elements(d->'lines') x where x->>'id' = c1::text and x->>'customer_note' = 'DOC-NOTE-C') = 1
    and (select count(*) from jsonb_array_elements(d->'lines') x where x->>'id' = c2::text and x ? 'customer_note' and x->'customer_note' = 'null'::jsonb and x->>'comments' = 'INTERNAL-ONLY') = 1, left(r, 200));

  -- 5 나누기 · Unconfirm · 합치기
  begin
    perform pg_temp.asu(pg_temp.qset(c3, 'WHOLE'));
    perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('d.staff')), true);
    v_sib := (public.so_split(pg_temp.id('C'), 'manual', jsonb_build_array(jsonb_build_object('line_id', c1, 'qty', 4), jsonb_build_object('line_id', c3, 'qty', 10)), 'draft', v_st)).id;
    perform set_config('request.jwt.claims', '', true);
    select l.id into v_n1 from public.so_line l where l.so_id = v_sib and l.split_from_line_id = c1;
    perform pg_temp.res('5a 나누기(so_split): 일부만 간 줄의 메모는 형제 새 줄에 복사 · 원래 줄에도 남음 · 통째로 간 줄은 메모가 따라감',
      v_n1 is not null and pg_temp.note_of(v_n1) = 'DOC-NOTE-C' and pg_temp.note_of(c1) = 'DOC-NOTE-C' and (select l.so_id from public.so_line l where l.id = c3) = v_sib and pg_temp.note_of(c3) = 'WHOLE',
      format('new %s=%s · c1=%s · c3=%s', v_n1, pg_temp.note_of(v_n1), pg_temp.note_of(c1), pg_temp.note_of(c3)));
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    perform pg_temp.res('5a 나누기(so_split)', false, 'EXC ' || sqlstate || ': ' || sqlerrm);
  end;
  begin
    perform pg_temp.asu(pg_temp.qset(u1, 'P1'));  perform pg_temp.asu(pg_temp.qset(u2, 'P2'));
    perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', current_setting('d.staff')), true);
    v_sib := (public.so_split(pg_temp.id('U'), 'stock_short', jsonb_build_array(jsonb_build_object('line_id', u1, 'qty', 4), jsonb_build_object('line_id', u2, 'qty', 4), jsonb_build_object('line_id', u3, 'qty', 4)), 'confirmed', v_st)).id;
    perform set_config('request.jwt.claims', '', true);
    select l.id into v_n1 from public.so_line l where l.so_id = v_sib and l.split_from_line_id = u1;
    select l.id into v_n2 from public.so_line l where l.so_id = v_sib and l.split_from_line_id = u2;
    select l.id into v_n3 from public.so_line l where l.so_id = v_sib and l.split_from_line_id = u3;
    r := pg_temp.asu(pg_temp.qset(v_n1, 'S1'));  r2 := pg_temp.asu(pg_temp.qset(u2, ''));  r3 := pg_temp.asu(pg_temp.qset(v_n3, 'S3'));
    r4 := pg_temp.asu(format('select public.so_unconfirm(%L)::text', pg_temp.id('U')));
    perform pg_temp.res('5b Unconfirm: 형제 메모를 손대도 막히지 않는다(1151) · 원래 줄이 비었으면 형제 것을 옮김 · 둘 다 있고 다르면 「 / 」 로 이음',
      pg_temp.j(r4)->>'status' = 'draft' and pg_temp.note_of(u1) = 'P1 / S1' and pg_temp.note_of(u2) = 'P2' and pg_temp.note_of(u3) = 'S3',
      format('unconfirm %s · u1=%s · u2=%s · u3=%s · sets %s / %s / %s', left(r4, 200), pg_temp.note_of(u1), pg_temp.note_of(u2), pg_temp.note_of(u3), left(r, 40), left(r2, 40), left(r3, 40)));
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    perform pg_temp.res('5b Unconfirm', false, 'EXC ' || sqlstate || ': ' || sqlerrm);
  end;
  if v_has then
    perform pg_temp.asu(pg_temp.qset(pg_temp.id('M1.1'), repeat('a', 300)));  perform pg_temp.asu(pg_temp.qset(pg_temp.id('M2.1'), repeat('b', 300)));
    perform pg_temp.asu(pg_temp.qset(pg_temp.id('M1.2'), 'Same'));  perform pg_temp.asu(pg_temp.qset(pg_temp.id('M2.2'), 'Same'));  perform pg_temp.asu(pg_temp.qset(pg_temp.id('M2.3'), 'Only2'));
    r := pg_temp.asu(format('select public.so_merge(array[%L, %L]::uuid[], false)::text', pg_temp.id('M1'), pg_temp.id('M2')));  d := pg_temp.j(r);
    r2 := pg_temp.asu(format('select public.so_merge(array[%L, %L]::uuid[], true)::text', pg_temp.id('M1'), pg_temp.id('M2')));
    perform pg_temp.res('5c 합치기 미리 보기: 줄 계획 note(이은 글 · 같은 글은 한 번 · 한쪽만 있으면 그 글) · 500 자 넘으면 경고 line_note_too_long · 실행은 거부',
      (d->'warnings') ? 'line_note_too_long' and (select count(*) from jsonb_array_elements(d->'lines') x where x->>'sku' = v_sku1 and x->>'note' = repeat('a', 300) || ' / ' || repeat('b', 300)) = 1
      and (select count(*) from jsonb_array_elements(d->'lines') x where x->>'sku' = v_sku2 and x->>'note' = 'Same') = 1 and (select count(*) from jsonb_array_elements(d->'lines') x where x->>'sku' = v_sku3 and x->>'note' = 'Only2') = 1
      and r2 like 'ERR %longer than 500 characters%nothing was saved%' and (select s.status from public.so s where s.id = pg_temp.id('M1')) = 'draft',
      'warnings ' || coalesce(d->>'warnings', left(r, 200)) || ' · commit ' || left(r2, 200));
    perform pg_temp.asu(pg_temp.qset(pg_temp.id('M1.1'), 'A-note'));  perform pg_temp.asu(pg_temp.qset(pg_temp.id('M2.1'), 'B-note'));
    r := pg_temp.asu(format('select public.so_merge(array[%L, %L]::uuid[], true)::text', pg_temp.id('M1'), pg_temp.id('M2')));
    select ms.line_id into v_n1 from public.so_line_merge_source ms where ms.from_line_id = pg_temp.id('M1.1');
    select ms.line_id into v_n2 from public.so_line_merge_source ms where ms.from_line_id = pg_temp.id('M1.2');
    select ms.line_id into v_n3 from public.so_line_merge_source ms where ms.from_line_id = pg_temp.id('M2.3');
    r2 := pg_temp.asu(pg_temp.qset(pg_temp.id('M1.1'), 'late'));
    perform pg_temp.res('5d 합치기 실행: 합친 줄의 메모 = 오더 순서대로 「 / 」 · 원본 메모는 남음 · 합쳐져 닫힌 원본은 메모 거부(merged)',
      v_n1 is not null and pg_temp.note_of(v_n1) = 'A-note / B-note' and pg_temp.note_of(v_n2) = 'Same' and pg_temp.note_of(v_n3) = 'Only2' and pg_temp.note_of(pg_temp.id('M1.1')) = 'A-note'
      and r2 like 'ERR %merged into another order%nothing was saved%',
      format('merge %s · n1=%s · n2=%s · n3=%s · late %s', left(r, 160), pg_temp.note_of(v_n1), pg_temp.note_of(v_n2), pg_temp.note_of(v_n3), left(r2, 160)));
  else
    perform pg_temp.res('5c 합치기 미리 보기', false, 'so_line_note 없음(적용 전) — 합치기는 돌리지 않았다(SO 번호 무접촉)');
    perform pg_temp.res('5d 합치기 실행', false, 'so_line_note 없음(적용 전) — 합치기는 돌리지 않았다(SO 번호 무접촉)');
  end if;

  -- 6 Add a line(so_lines_paste 의 줄 열쇠 note)
  r := pg_temp.asu(pg_temp.qpaste(pg_temp.id('A'), jsonb_build_array(jsonb_build_object('sku', v_sku3, 'qty', 1, 'note', E' Gift \n wrap ')), false));  d := pg_temp.j(r);
  perform pg_temp.res('6a 붙여 넣기 미리 보기: 줄에 굳힌 note · 아무것도 안 넣음',
    d->'lines'->0->>'note' = 'Gift wrap' and d->'lines'->0->>'verdict' in ('ok', 'no_price') and (d->>'committed')::boolean = false and (select count(*) from public.so_line l where l.so_id = pg_temp.id('A')) = 3, left(r, 300));
  r := pg_temp.asu(pg_temp.qpaste(pg_temp.id('A'), jsonb_build_array(jsonb_build_object('sku', v_sku3, 'qty', 1, 'note', 'Gift wrap'), jsonb_build_object('sku', v_sku1, 'qty', 1, 'note', 'Second')), true));  d := pg_temp.j(r);
  select l.id into v_n1 from public.so_line l where l.so_id = pg_temp.id('A') and l.sku = v_sku3 and l.combo_line_id is null;
  perform pg_temp.res('6b 붙여 넣기 저장: 새 값 줄의 메모가 저장됨 · 기존 줄에 합쳐진 줄은 메모가 없었으면 저장',
    v_n1 is not null and pg_temp.note_of(v_n1) = 'Gift wrap' and d->'lines'->1->>'verdict' = 'merged' and pg_temp.note_of(a1) = 'Second' and (d->'summary'->>'inserted')::int = 1,
    format('new %s=%s · a1=%s · %s', v_n1, pg_temp.note_of(v_n1), pg_temp.note_of(a1), left(r, 300)));
  r := pg_temp.asu(pg_temp.qpaste(pg_temp.id('A'), jsonb_build_array(jsonb_build_object('sku', v_sku1, 'qty', 1, 'note', 'Other')), true));  d := pg_temp.j(r);
  r2 := pg_temp.asu(pg_temp.qpaste(pg_temp.id('A'), jsonb_build_array(jsonb_build_object('sku', v_sku3, 'qty', 1, 'note', repeat('y', 501))), false));
  perform pg_temp.res('6c 붙여 넣기: 다른 메모가 있는 줄에 합쳐지면 기존 메모를 두고 알림(note_not_saved) · 501 자는 bad_note(안 넣음)',
    d->'lines'->0->>'message' like '%note_not_saved%' and pg_temp.note_of(a1) = 'Second' and pg_temp.j(r2)->'lines'->0->>'verdict' = 'bad_note' and (pg_temp.j(r2)->'summary'->>'bad_note')::int = 1,
    left(r, 250) || ' / ' || left(r2, 250));

  -- 7 권한
  r  := pg_temp.asu(pg_temp.qset(a2, 'nope'), current_setting('d.nosales'));
  r2 := pg_temp.asu(format('insert into public.so_line_note (so_line_id, note) values (%L, ''x'') returning ''done''', a2));
  r3 := pg_temp.asu(format('update public.so_line_note set note = ''x'' where so_line_id = %L returning ''done''', w1));
  r4 := pg_temp.asu(format('delete from public.so_line_note where so_line_id = %L returning ''done''', w1));
  r5 := pg_temp.asu(format('select public.so_line_note_put(%L, ''x'', null)', a2));
  r6 := pg_temp.asu('select count(*)::text from public.so_line_note');
  perform pg_temp.res('7 권한: sales 쓰기 없는 직원 거부 · 표 직접 insert · update · delete 거부(42501) · 안쪽 so_line_note_put 직접 호출 거부 · 읽기는 됨',
    r like 'ERR %cannot change sales data%' and r2 like 'ERR 42501%' and r3 like 'ERR 42501%' and r4 like 'ERR 42501%' and r5 like 'ERR 42501%' and r6 ~ '^[0-9]+$' and pg_temp.note_of(a2) is null and pg_temp.note_of(w1) = 'web note',
    left(r, 120) || ' / ' || left(r2, 80) || ' / ' || left(r3, 80) || ' / ' || left(r4, 80) || ' / ' || left(r5, 80) || ' / ' || left(r6, 80));

  -- 8b 회귀: 사내 comments(so_line_update) 무변 · 무접촉 함수 그대로
  r := pg_temp.asu(format('select public.so_line_update(%L, %L)::text', a1, jsonb_build_object('comments', 'internal x')));
  perform pg_temp.res('8b 회귀: so_line_update 의 사내 comments 는 그대로 so_line 에 · 손님 메모 무변 · 무접촉 함수 열둘(so_line_add · so_line_update · so_combo_children_insert · doc_data · fmt · catalog · credit …) md5 머리와 같다',
    left(r, 3) <> 'ERR' and (select l.comments from public.so_line l where l.id = a1) = 'internal x' and pg_temp.note_of(a1) = 'Second'
    and (select md5(string_agg(p.proname || ':' || md5(p.prosrc), '|' order by p.proname)) from pg_proc p where p.pronamespace = 'public'::regnamespace
           and p.proname in ('so_line_add', 'so_line_update', 'so_combo_children_insert', 'so_line_remove', 'so_lines_clear', 'doc_data', 'doc_data_invoice_fmt', 'doc_field_catalog', 'doc_data_credit', 'doc_data_ship_ready', 'so_invoice_issue', 'so_proforma')) = current_setting('d.snap_fn'),
    left(r, 200));

  -- 9 REST 두 겹 ① 정적: 새 창구의 update · delete 는 깊이 0 WHERE
  perform pg_temp.res('9 REST ①: 스캐너 자기 시험 1011110 · so_line_note_put · so_line_note_set 의 WHERE 없는 update · delete 0',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('update t set a = (select 1 from u where u.x = 1);')::text
      || pg_temp.nowhere('with c as (select 1) update t set a = 1 from c;')::text || pg_temp.nowhere('delete from t;')::text || pg_temp.nowhere('if x then update t set a = 1; end if;')::text || pg_temp.nowhere('v := ''update t set a = 1'';')::text = '1011110'
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_line_note_put', 'so_line_note_set')) = 2
    and (select coalesce(sum(pg_temp.nowhere(p.prosrc)), -1) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_line_note_put', 'so_line_note_set')) = 0,
    (select coalesce(string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' '), '(창구 없음)') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_line_note_put', 'so_line_note_set')));

  -- Z 실물 무접촉
  v_cnt := 0;
  if v_has then execute 'select count(*) from public.so_line_note sn join public.so_line l on l.id = sn.so_line_id where l.created_at not in (''2001-01-01 00:00:00+00'', now())' into v_cnt; end if;
  perform pg_temp.res('Z 실물 무접촉: 복사 원본(so · so_line · so_invoice · so_invoice_line) 그대로 · 이 트랜잭션이 손댄 so · so_line · so_invoice 는 전부 가짜(만든 시각 2001-01-01 표지 또는 지금) · 실제 줄에 붙은 메모 0 · claims 비었음',
    pg_temp.real_snap() = v_real0
    and (select count(*) from public.so s where s.updated_at = now() and s.created_at not in ('2001-01-01 00:00:00+00', now())) = 0
    and (select count(*) from public.so_line l where l.updated_at = now() and l.created_at not in ('2001-01-01 00:00:00+00', now())) = 0
    and (select count(*) from public.so_invoice i where i.updated_at = now()) = 0
    and v_cnt = 0 and coalesce(current_setting('request.jwt.claims', true), '') = '' and current_user = 'postgres',
    format('real %s · notes on real lines %s · user %s', pg_temp.real_snap() = v_real0, v_cnt, current_user));
end $$;
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · so_number_seq ' || :'seq_head' || ' → ' || (select last_value::text from public.so_number_seq)
       || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
\pset tuples_only off
\pset format aligned
rollback;
-- 기대: 시험(-v mig) OK 25 · FAIL 0 · 마른 실행(적용 전 · -v mig 없음) OK 2(3 · Z) · FAIL 22(1 · 2 · 4 · 5 · 6 · 7 · 8b · 9 · 10 — 8a 는 건너뜀) · 확인(적용 뒤 · -v mig 없음) OK 24 · FAIL 0(8a 건너뜀)
