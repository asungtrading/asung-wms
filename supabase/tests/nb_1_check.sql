-- nb-1 검증 — supabase/migrations/20261111064623_nb_1_adjust_fill_cost_order.sql (+ 조정의 원가 메우기 · 단가를 비운 + 조정의 원가 순서 · 판정 1170 · 1171 · 지시서 ~/asung/prompts/nb-1.md §5 · asung-workflow §4 틀)
--   시험 적용 + 검증(Claude Code · rollback · 메인 DB): cd ~/asung/asung-wms && set -o pipefail; PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261111064623_nb_1_adjust_fill_cost_order.sql -f supabase/tests/nb_1_check.sql
--   마른 실행(적용 전) · 확인(적용 뒤 · Caleb): 같은 명령에서 -v mig=… 만 뺀다 — 기대 수는 파일 끝
--   ⚠️ 실제 행 무변: 재료는 전부 가짜 — SKU 'NB1-…' · 문서 'SO-NB1-…' · 'ADJ-NB1-…' · 'NB1-SEED' · 조정 문서 줄의 product_id · bin_id 만 실제 것을 빌린다(FK · 읽기만) · 끝은 rollback
--   ⚠️ 번호 시퀀스 무접촉: 조정 번호는 손으로 준다(inv_adjust_next_number 를 부르지 않는다) · inv_layer · inv_ledger 의 identity 는 rollback 뒤에도 늘어난 채다(번호가 아니라 행 id)
--   ⚠️ 잠금: 시험 적용이 함수 셋(pg_proc 행)을 rollback 까지 잡는다 — 표 잠금 없음 · 가짜 SKU 원장 행이 shop_stock 큐 트리거를 지나지만 rollback · lock_timeout 3 s
--   ⚠️ 재생성(D)은 inv_layer_apply 전체가 아니라 그 갈래를 본뜬 것이다: 가짜 SKU 의 판매 · 조정 레이어를 지우고 원장 행을 (seq_hint, id) 순으로 — 판매는 inv_layer_post_sale(raw.cost.shortfall) · 조정은 실제 보조 inv_layer_apply_adjust_ims
\set ON_ERROR_STOP on
\pset format unaligned
\pset tuples_only on
select
  (select string_agg(q.id::text, ',') from (select p.id from public.product p where p.is_active order by p.sku limit 12) q) as pids,
  (select w.id::text from public.ref_warehouse w where w.name = 'Asung - Edmonton') as edm_id,
  (select b.id::text || '|' || b.name from public.ref_bin b join public.ref_warehouse w on w.id = b.warehouse_id where w.name = 'Asung - Edmonton' and b.is_active order by b.name limit 1) as bin1,
  (select b.id::text || '|' || b.name from public.ref_bin b join public.ref_warehouse w on w.id = b.warehouse_id where w.name = 'Asung - Edmonton' and b.is_active order by b.name offset 1 limit 1) as bin2,
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.auth_user_id is not null and st.role = 'supervisor' order by st.created_at limit 1) as u_cost,
  (select st.auth_user_id::text from public.ims_staff st where st.is_active and st.auth_user_id is not null and st.role not in ('admin', 'supervisor') and st.perms ? 'stock_adjust' and not (st.perms ? 'cost' or st.perms ? 'cost:read') order by st.created_at limit 1) as u_nocost,
  coalesce((select h.sku from public.po_price_history h where h.net_unit_cad is not null and not exists (select 1 from public.inv_layer y where y.sku = h.sku) order by h.sku limit 1), '') as ph_sku,
  (select count(*) from public.inv_ledger)::text || '/' || (select count(*) from public.inv_layer)::text || '/' || (select count(*) from public.inv_adjust)::text as real_head,
  (select coalesce(p.proacl::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_adjust_eval') as eval_acl,
  (to_regprocedure('public.inv_layer_recent_cost(text,text)') is not null)::int as applied_head,
  (select last_value::text from public.inv_adjust_number_seq) as seq_head,
  clock_timestamp()::text as t_begin \gset
select 'head: applied ' || :applied_head || ' · ledger/layer/adjust ' || :'real_head' || ' · adj seq ' || :'seq_head' || ' · cost staff ' || left(:'u_cost', 8) || ' · no-cost staff ' || left(:'u_nocost', 8) || ' · price-history-only sku ' || :'ph_sku';

create temp table t_res (seq serial, tag text, ok boolean, detail text);
create function pg_temp.res(p_tag text, p_ok boolean, p_detail text) returns void language sql as $$ insert into t_res (tag, ok, detail) values (p_tag, coalesce(p_ok, false), left(coalesce(p_detail, '(null)'), 900)) $$;
select set_config('d.pids', :'pids', false), set_config('d.edm_id', :'edm_id', false), set_config('d.bin1', :'bin1', false), set_config('d.bin2', :'bin2', false), set_config('d.u_cost', :'u_cost', false),
       set_config('d.u_nocost', :'u_nocost', false), set_config('d.ph_sku', :'ph_sku', false), set_config('d.real_head', :'real_head', false), set_config('d.eval_acl', :'eval_acl', false) \g /dev/null
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
-- 재료 — 씨 레이어(과거 날짜 · baseline) + 원장 +q
create function pg_temp.seed(p_sku text, p_wh text, p_bin text, p_qty numeric, p_unit numeric) returns void language plpgsql as $$
begin
  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (p_sku, p_wh, 'baseline', 'NB1-SEED', p_sku, null, public.ims_today() - 30, true, p_qty, p_unit, 'snapshot_value');
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
  values (public.ims_today() - 30, 1, p_sku, p_wh, p_bin, p_qty, 'po_in', 'purchase', 'NB1-SEED', p_sku || '|' || p_wh, 'manual');
end $$;
-- 재료 — 판매(실제 창구 inv_layer_post_sale + 원장 −q · raw.cost 에 결과 — inv_post_sale 이 싣는 자리)
create function pg_temp.sale(p_doc text, p_sku text, p_wh text, p_bin text, p_qty numeric) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  v := public.inv_layer_post_sale(p_doc, 'l1', p_sku, p_wh, p_qty, public.ims_today(), null);
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source, raw)
  values (public.ims_today(), 2, p_sku, p_wh, p_bin, -p_qty, 'sale_out', 'sale', p_doc, 'l1', 'manual', jsonb_build_object('cost', v));
  return v;
end $$;
-- 재료 — 조정 문서(가짜 번호 · 줄마다 다른 실제 product_id 를 빌린다 · sku 글자는 가짜) · p_post 면 confirmed 로 세우고 실제 원장 창구 inv_post_adjust 를 부른다
create function pg_temp.adj(p_tag text, p_wh text, p_post boolean, p_lines jsonb) returns jsonb language plpgsql as $$
declare v_id uuid := gen_random_uuid(); v_whid uuid; v_pids text[] := string_to_array(current_setting('d.pids'), ','); v_l jsonb; v_i int := 0; v_bin text;
begin
  select w.id into v_whid from public.ref_warehouse w where w.name = p_wh;
  insert into public.inv_adjust (id, adjust_number, status, warehouse_id, warehouse, note, posted_on, confirmed_at)
  values (v_id, 'ADJ-NB1-' || p_tag, case when p_post then 'confirmed' else 'draft' end, v_whid, p_wh, 'nb-1 check', case when p_post then public.ims_today() end, case when p_post then now() end);
  for v_l in select * from jsonb_array_elements(p_lines) loop
    v_i := v_i + 1;  v_bin := current_setting(case when coalesce(v_l->>'bin', '1') = '2' then 'd.bin2' else 'd.bin1' end);
    insert into public.inv_adjust_line (adjust_id, line_no, product_id, sku, bin_id, bin, mode, qty_input, reason, unit_cost, seen_ledger, seen_picked, delta)
    values (v_id, v_i, v_pids[v_i]::uuid, v_l->>'sku', split_part(v_bin, '|', 1)::uuid, split_part(v_bin, '|', 2), 'delta', (v_l->>'q')::numeric, 'count', nullif(v_l->>'cost', '')::numeric, 0, 0, case when p_post then (v_l->>'q')::numeric end);
  end loop;
  if p_post then return public.inv_post_adjust(v_id) || jsonb_build_object('id', v_id); end if;
  return jsonb_build_object('id', v_id);
end $$;
-- 상태 한 줄 — 레이어 남은 수량 · 남은 가치 · 장부 수량 · 조정 레이어들
create function pg_temp.st(p_sku text, p_wh text) returns text language sql as $$
  select format('lay %s val %s led %s adj[%s]',
    (select coalesce(sum(v.remaining_qty), 0) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = p_wh)::numeric(18,2),
    (select coalesce(sum(v.remaining_value), 0) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = p_sku and y.warehouse = p_wh)::numeric(18,2),
    (select coalesce(sum(e.qty_delta), 0) from public.inv_ledger e where e.sku = p_sku and e.warehouse = p_wh)::numeric(18,2),
    coalesce((select string_agg(format('%s %s@%s %s', y.origin_type, y.qty::numeric(18,2), y.unit_cost::numeric(18,2), y.cost_source), ', ' order by y.id) from public.inv_layer y
               where y.sku = p_sku and y.warehouse = p_wh and y.origin_type in ('adjust_existing', 'adjust_new')), '')) $$;
-- 가짜 SKU 의 레이어 · 소진 전부를 글 하나로(id · 시각 제외 · 정렬) — 재생성 비교
create function pg_temp.snap() returns text language sql as $$
  select md5(coalesce((select string_agg(format('L|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s', y.sku, y.warehouse, y.origin_type, y.doc_number, y.line_ref, y.received_on, y.age_known, y.qty, y.unit_cost, y.cost_source), E'\n'
                                  order by y.sku, y.warehouse, y.origin_type, y.doc_number, y.line_ref) from public.inv_layer y where y.sku like 'NB1-%'), '')
          || E'\n' || coalesce((select string_agg(format('C|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s', y.sku, y.warehouse, y.origin_type, y.doc_number, c.doc_type, c.doc_number, c.line_ref, c.event_type, c.occurred_on, c.qty, c.unit_cost, c.amount, c.reason), E'\n'
                                  order by y.sku, y.warehouse, y.origin_type, y.doc_number, c.doc_type, c.doc_number, c.line_ref, c.qty) from public.inv_layer_consume c join public.inv_layer y on y.id = c.layer_id where y.sku like 'NB1-%'), ''))
         || ' · layers ' || (select count(*) from public.inv_layer y where y.sku like 'NB1-%') || ' · consumes ' || (select count(*) from public.inv_layer_consume c join public.inv_layer y on y.id = c.layer_id where y.sku like 'NB1-%')
         || ' · value ' || (select coalesce(sum(v.remaining_value), 0)::numeric(18,6) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku like 'NB1-%') $$;
-- 직원 신원으로 eval 을 읽는다 — 줄 번호 → 줄(jsonb) · 예외는 {"err": …}
create function pg_temp.ev(p_uid text, p_adjust uuid) returns jsonb language plpgsql as $$
declare v jsonb;
begin
  perform set_config('request.jwt.claims', format('{"sub":"%s","role":"authenticated"}', p_uid), true);
  execute 'set local role authenticated';
  select jsonb_object_agg(e.line_no::text, to_jsonb(e)) into v from public.inv_adjust_eval(p_adjust) e;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return v;
exception when others then
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  return jsonb_build_object('err', sqlstate || ': ' || sqlerrm);
end $$;

create function pg_temp.run() returns void language plpgsql as $$
declare
  EDM constant text := 'Asung - Edmonton';  TOR constant text := 'Asung Trading Inc.';
  b1 text := split_part(current_setting('d.bin1'), '|', 2);  b2 text := split_part(current_setting('d.bin2'), '|', 2);
  v_applied boolean := to_regprocedure('public.inv_layer_recent_cost(text,text)') is not null;
  r jsonb; r2 jsonb; k jsonb; e1 jsonb; e2 jsonb; v_t text; v_s1 text; v_s2 text; v_row record; v_id uuid; v_n int; v_ph_unit numeric; v_ph_inv text; v_q jsonb;
begin
  execute 'set local lock_timeout = ''3s''';
  -- ── 재료: 씨 ──
  perform pg_temp.seed('NB1-A', TOR, 'NB1BIN', 2, 6.00);       -- A: EDM 에는 없다 · 다른 창고 원가 6.00
  perform pg_temp.seed('NB1-G', EDM, b1, 2, 4.00);             -- G: 칸 1 에 2
  perform pg_temp.seed('NB1-R2A', EDM, b1, 5, 4.00);           -- R2 ②: 남은 레이어 5 @4
  perform pg_temp.seed('NB1-R2B', EDM, b1, 1, 3.00);           -- R2 ③-1: 다 팔린 이 창고 레이어 @3
  perform pg_temp.seed('NB1-R2C', TOR, 'NB1BIN', 1, 6.50);     -- R2 ③-2: 다른 창고만 @6.5
  perform pg_temp.seed('NB1-Q1', EDM, b1, 1, 3.00);  perform pg_temp.seed('NB1-Q2', TOR, 'NB1BIN', 1, 6.50);
  perform pg_temp.seed('NB1-EA', TOR, 'NB1BIN', 2, 6.00);  perform pg_temp.seed('NB1-EC', EDM, b1, 5, 4.00);  perform pg_temp.seed('NB1-ED', TOR, 'NB1BIN', 1, 6.50);

  -- ── A: 재고 없이 1 판매 → +1 조정(단가 비움) ⇒ 레이어 남은 0 · 가치 0 · 조정 레이어 없음 ──
  r := pg_temp.sale('SO-NB1-A', 'NB1-A', EDM, '', 1);
  k := pg_temp.adj('A', EDM, true, '[{"sku":"NB1-A","q":1}]');
  v_t := pg_temp.st('NB1-A', EDM);
  perform pg_temp.res('A 재고 없이 1 판매 → +1 조정: 레이어 남은 0 · 가치 0 · 장부 0 · 조정 레이어 없음 · raw.cost.fill_qty 1 · 원장 amount 0',
    v_t = 'lay 0.00 val 0.00 led 0.00 adj[]' and r->'shortfall'->>'cost_source' = 'layer_recent_other_wh'
    and (select (e.raw->'cost'->>'fill_qty')::numeric = 1 and e.amount = 0 and e.event_type = 'adjust_existing' from public.inv_ledger e where e.doc_number = 'ADJ-NB1-A' and e.sku = 'NB1-A'),
    v_t || ' · sale ' || coalesce(r->'shortfall'->>'cost_source', '-') || ' · raw.cost ' || coalesce((select (e.raw->'cost')::text from public.inv_ledger e where e.doc_number = 'ADJ-NB1-A' and e.sku = 'NB1-A'), '-'));

  -- ── B · F: 재고 없이 2 판매 → +5 조정(단가 7.00) ⇒ 2 는 메움 · 3 은 7.00 레이어(메움 몫에는 단가가 안 쓰인다) ──
  perform pg_temp.sale('SO-NB1-B', 'NB1-B', EDM, '', 2);
  k := pg_temp.adj('B', EDM, true, '[{"sku":"NB1-B","q":5,"cost":"7.00"}]');
  v_t := pg_temp.st('NB1-B', EDM);
  perform pg_temp.res('B 재고 없이 2 판매 → +5 @7.00: 2 메움 · 3 은 7.00 레이어(가치 21) · 장부 3 = 레이어 3',
    v_t = 'lay 3.00 val 21.00 led 3.00 adj[adjust_new 3.00@7.00 manual]', v_t);
  perform pg_temp.res('F 단가를 넣은 + 조정도 메움 몫에는 그 단가가 안 쓰인다: 원장 amount 21(= 3 × 7 · 35 아님) · fill_qty 2 · layer_qty 3 · 원장 사건은 adjust_new 그대로',
    (select e.amount = 21 and (e.raw->'cost'->>'fill_qty')::numeric = 2 and (e.raw->'cost'->>'layer_qty')::numeric = 3 and e.event_type = 'adjust_new' from public.inv_ledger e where e.doc_number = 'ADJ-NB1-B' and e.sku = 'NB1-B'),
    (select format('amount %s · %s · %s', e.amount, e.event_type, e.raw->'cost') from public.inv_ledger e where e.doc_number = 'ADJ-NB1-B' and e.sku = 'NB1-B'));
  perform pg_temp.sale('SO-NB1-F2', 'NB1-F2', EDM, '', 1);
  k := pg_temp.adj('F2', EDM, true, '[{"sku":"NB1-F2","q":1,"cost":"9.99"}]');
  v_t := pg_temp.st('NB1-F2', EDM);
  perform pg_temp.res('F2 재고 없이 1 판매 → +1 @9.99: 전부 메움 — 레이어 없음 · 가치 0 · 원장 amount 0', v_t = 'lay 0.00 val 0.00 led 0.00 adj[]'
    and (select e.amount = 0 from public.inv_ledger e where e.doc_number = 'ADJ-NB1-F2' and e.sku = 'NB1-F2'), v_t);

  -- ── C: 재고 없이 1 판매 → +1 → 다시 +1 ⇒ 둘째는 메울 것이 없어 새 레이어 ──
  perform pg_temp.sale('SO-NB1-C', 'NB1-C', EDM, '', 1);
  k := pg_temp.adj('C1', EDM, true, '[{"sku":"NB1-C","q":1}]');
  v_t := pg_temp.st('NB1-C', EDM);
  k := pg_temp.adj('C2', EDM, true, '[{"sku":"NB1-C","q":1}]');
  perform pg_temp.res('C 재고 없이 1 판매 → +1 → 다시 +1: 첫째 메움(레이어 없음) · 둘째는 새 레이어 1(원가 모름 0) · 장부 1 = 레이어 1',
    v_t = 'lay 0.00 val 0.00 led 0.00 adj[]' and pg_temp.st('NB1-C', EDM) = 'lay 1.00 val 0.00 led 1.00 adj[adjust_existing 1.00@0.00 unknown]', v_t || ' → ' || pg_temp.st('NB1-C', EDM));

  -- ── E: 토론토의 부족분은 에드먼턴 조정이 메우지 않는다 ──
  perform pg_temp.sale('SO-NB1-E', 'NB1-E', TOR, '', 1);
  k := pg_temp.adj('E', EDM, true, '[{"sku":"NB1-E","q":1}]');
  perform pg_temp.res('E 창고 경계: 토론토에서 재고 없이 1 판매 → 에드먼턴 +1 ⇒ 에드먼턴에 새 레이어 1 · 토론토는 그대로(레이어 0 · 장부 −1)',
    pg_temp.st('NB1-E', EDM) like 'lay 1.00 val % led 1.00 adj[adjust_existing 1.00@%' and pg_temp.st('NB1-E', TOR) = 'lay 0.00 val 0.00 led -1.00 adj[]'
    and (select (e.raw->'cost'->>'fill_qty')::numeric = 0 from public.inv_ledger e where e.doc_number = 'ADJ-NB1-E'), pg_temp.st('NB1-E', EDM) || ' ‖ TOR ' || pg_temp.st('NB1-E', TOR));

  -- ── G: 칸 1 에 2 · 칸 2 에서 3 판매(FIFO 2 + 부족분 1) → 한 문서로 칸 1 −2 · 칸 2 +3 ⇒ 가치가 새로 서지 않는다(창고 합으로 본다) ──
  perform pg_temp.sale('SO-NB1-G', 'NB1-G', EDM, b2, 3);
  k := pg_temp.adj('G', EDM, true, '[{"sku":"NB1-G","q":-2,"bin":"1"},{"sku":"NB1-G","q":3,"bin":"2"}]');
  v_t := pg_temp.st('NB1-G', EDM);
  perform pg_temp.res('G 칸이 어긋난 채 팔린 것(칸 1 −2 · 칸 2 +3 한 문서): 레이어 0 · 가치 0 · 장부 0 · 조정 레이어 없음', v_t = 'lay 0.00 val 0.00 led 0.00 adj[]', v_t);

  -- ── H: 이미 유령인 자리(레이어 1 · 장부 0 — 지금 쌓인 두 건의 꼴) → +1 ⇒ 새 레이어 없이 장부만 1(유령이 실물이 된다) ──
  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values ('NB1-H', EDM, 'adjust_new', 'ADJ-NB1-H0', 'h0', null, public.ims_today() - 1, true, 1, 5.00, 'manual');
  k := pg_temp.adj('H', EDM, true, '[{"sku":"NB1-H","q":1,"cost":"8.00"}]');
  v_t := pg_temp.st('NB1-H', EDM);
  perform pg_temp.res('H 이미 유령인 자리(레이어 1 · 장부 0) → +1: 새 레이어 없음 · 레이어 1 = 장부 1 · 가치 5 그대로', v_t = 'lay 1.00 val 5.00 led 1.00 adj[adjust_new 1.00@5.00 manual]', v_t);

  -- ── R2: 단가 비움 · 메우고 남는 몫의 네 갈래 ──
  k := pg_temp.adj('R2A', EDM, true, '[{"sku":"NB1-R2A","q":2}]');
  perform pg_temp.res('R2-② 남은 레이어 가중평균: 5 @4 남음 → +2 는 layer_avg 4.00 · step 2', pg_temp.st('NB1-R2A', EDM) = 'lay 7.00 val 28.00 led 7.00 adj[adjust_existing 2.00@4.00 layer_avg]'
    and coalesce((select e.raw->'cost'->>'step' from public.inv_ledger e where e.doc_number = 'ADJ-NB1-R2A'), '2') = '2', pg_temp.st('NB1-R2A', EDM));
  perform pg_temp.sale('SO-NB1-R2B', 'NB1-R2B', EDM, b1, 1);
  k := pg_temp.adj('R2B', EDM, true, '[{"sku":"NB1-R2B","q":1}]');
  perform pg_temp.res('R2-③ 이 창고 최근 원가: 다 팔린 레이어 @3 → +1 은 layer_recent 3.00 · step 3 · 출처 = 그 레이어', pg_temp.st('NB1-R2B', EDM) = 'lay 1.00 val 3.00 led 1.00 adj[adjust_existing 1.00@3.00 layer_recent]'
    and (select e.raw->'cost'->>'step' = '3' and e.raw->'cost'->'source'->>'doc_number' = 'NB1-SEED' from public.inv_ledger e where e.doc_number = 'ADJ-NB1-R2B'),
    pg_temp.st('NB1-R2B', EDM) || ' · ' || coalesce((select (e.raw->'cost')::text from public.inv_ledger e where e.doc_number = 'ADJ-NB1-R2B'), '-'));
  k := pg_temp.adj('R2C', EDM, true, '[{"sku":"NB1-R2C","q":1}]');
  perform pg_temp.res('R2-③ 다른 창고 최근 원가: 토론토에만 @6.5 → 에드먼턴 +1 은 layer_recent_other_wh 6.50 · step 4', pg_temp.st('NB1-R2C', EDM) = 'lay 1.00 val 6.50 led 1.00 adj[adjust_existing 1.00@6.50 layer_recent_other_wh]'
    and (select e.raw->'cost'->>'step' = '4' and e.raw->'cost'->'source'->>'warehouse' = TOR from public.inv_ledger e where e.doc_number = 'ADJ-NB1-R2C'), pg_temp.st('NB1-R2C', EDM));
  k := pg_temp.adj('R2D', EDM, true, '[{"sku":"NB1-R2D","q":1}]');
  perform pg_temp.res('R2-④ 아무 근거 없음: unknown 0 · step 6', pg_temp.st('NB1-R2D', EDM) = 'lay 1.00 val 0.00 led 1.00 adj[adjust_existing 1.00@0.00 unknown]'
    and coalesce((select e.raw->'cost'->>'step' from public.inv_ledger e where e.doc_number = 'ADJ-NB1-R2D'), '-') = '6', pg_temp.st('NB1-R2D', EDM) || ' · step ' || coalesce((select e.raw->'cost'->>'step' from public.inv_ledger e where e.doc_number = 'ADJ-NB1-R2D'), '-'));
  -- R2-③ 발주 단가: 가짜 SKU 로는 인보이스를 세울 수 없다 ⇒ ⓐ 도우미를 레이어 없는 실제 SKU 로 읽기만(쓰기 없음) ⓑ 창구가 price_history hint 를 받아 그 값으로 세우는지
  select h.net_unit_cad, h.invoice_number into v_ph_unit, v_ph_inv from public.po_price_history h where h.sku = current_setting('d.ph_sku') and h.net_unit_cad is not null order by h.invoice_date desc, h.invoice_number desc limit 1;
  if v_applied and current_setting('d.ph_sku') <> '' then
    execute 'select to_jsonb(x) from public.inv_layer_recent_cost($1, $2) x' into v_q using current_setting('d.ph_sku'), EDM;
  end if;
  r := public.inv_layer_post_adjust('ADJ-NB1-PH', 'ph1', 'NB1-PH', EDM, 1, public.ims_today(), null, '{"unit_cost": 2.5, "cost_source": "price_history", "step": 5, "fill_qty": 0}'::jsonb);
  perform pg_temp.res('R2-③ 발주 단가: 도우미가 레이어 없는 실제 SKU(읽기만)에 price_history · 그 인보이스 단가 · step 3 을 낸다 · 창구는 price_history hint 를 그 값으로 세운다',
    v_q->>'cost_source' = 'price_history' and (v_q->>'unit_cost')::numeric = v_ph_unit and v_q->>'step' = '3' and v_q->'source'->>'invoice_number' = v_ph_inv
    and pg_temp.st('NB1-PH', EDM) like '%adj[adjust_existing 1.00@2.50 price_history]', coalesce(v_q::text, '(no helper)') || ' · ' || pg_temp.st('NB1-PH', EDM));
  -- 도우미 = 판매 함수(정본)의 부족분 블록: 같은 재료에서 도우미를 먼저 읽고 → 판매 함수가 부족분에 매긴 값 · 출처와 견준다(세 자리: 이 창고 · 다른 창고 · 모름)
  perform pg_temp.sale('SO-NB1-Q1a', 'NB1-Q1', EDM, b1, 1);
  if v_applied then
    execute 'select jsonb_build_object(''q1'', (select to_jsonb(x) from public.inv_layer_recent_cost(''NB1-Q1'', $1) x), ''q2'', (select to_jsonb(x) from public.inv_layer_recent_cost(''NB1-Q2'', $1) x), ''q3'', (select to_jsonb(x) from public.inv_layer_recent_cost(''NB1-Q3'', $1) x))' into v_q using EDM;
  else v_q := '{}'::jsonb; end if;
  r := jsonb_build_object('q1', pg_temp.sale('SO-NB1-Q1b', 'NB1-Q1', EDM, b1, 1)->'shortfall', 'q2', pg_temp.sale('SO-NB1-Q2', 'NB1-Q2', EDM, b1, 1)->'shortfall', 'q3', pg_temp.sale('SO-NB1-Q3', 'NB1-Q3', EDM, b1, 1)->'shortfall');
  perform pg_temp.res('R2 같은 식: 도우미 inv_layer_recent_cost = inv_layer_post_sale 의 부족분(단가 · 갈래 · step · 출처) — 이 창고 · 다른 창고 · 모름 세 자리',
    (select bool_and((v_q->x)->>'unit_cost' is not null and ((v_q->x)->>'unit_cost')::numeric = ((r->x)->>'unit_cost')::numeric and (v_q->x)->>'cost_source' = (r->x)->>'cost_source' and (v_q->x)->>'step' = (r->x)->>'step'
                     and (v_q->x)->'source' is not distinct from (r->x)->'source') from unnest(array['q1', 'q2', 'q3']) x)
    and r->'q1'->>'cost_source' = 'layer_recent' and r->'q2'->>'cost_source' = 'layer_recent_other_wh' and r->'q3'->>'cost_source' = 'unknown',
    'helper ' || left(v_q::text, 380) || ' ‖ sale ' || left(r::text, 380));

  -- ── R4: 읽기 창구(초안 문서 · 줄 일곱) — 원가 열쇠 있는 직원 / 없는 직원 ──
  perform pg_temp.sale('SO-NB1-EA', 'NB1-EA', EDM, '', 1);  perform pg_temp.sale('SO-NB1-EB', 'NB1-EB', EDM, '', 2);  perform pg_temp.sale('SO-NB1-EF', 'NB1-EF', EDM, '', 1);
  k := pg_temp.adj('EV', EDM, false, '[{"sku":"NB1-EA","q":1},{"sku":"NB1-EB","q":5,"cost":"7.00"},{"sku":"NB1-EC","q":2},{"sku":"NB1-ED","q":1},{"sku":"NB1-EE","q":1},{"sku":"NB1-EF","q":1},{"sku":"NB1-EF","q":1,"bin":"2"}]');
  v_id := (k->>'id')::uuid;
  e1 := pg_temp.ev(current_setting('d.u_cost'), v_id);  e2 := pg_temp.ev(current_setting('d.u_nocost'), v_id);
  perform pg_temp.res('R4a eval(원가 열쇠 있음): 줄마다 메움 수량 · 새 레이어 수량 · 갈래 · 단가 — 전부 메움 / 2 메움 + 3 manual 7 / layer_avg 4 / 다른 창고 6.5(출처 창고) / unknown 0 / 같은 SKU 두 줄은 앞 줄만 메움',
    (select string_agg(format('%s:%s/%s/%s/%s', n, (e1->n->>'fill_qty')::numeric(18,2), (e1->n->>'layer_qty')::numeric(18,2), e1->n->>'cost_branch', coalesce((e1->n->>'layer_unit_cost')::numeric(18,2)::text, '-')), ' ' order by n)
       from unnest(array['1','2','3','4','5','6','7']) n)
      = '1:1.00/0.00/filled/- 2:2.00/3.00/manual/7.00 3:0.00/2.00/layer_avg/4.00 4:0.00/1.00/layer_recent_other_wh/6.50 5:0.00/1.00/unknown/0.00 6:1.00/0.00/filled/- 7:0.00/1.00/unknown/0.00'
    and e1->'4'->'cost_from'->>'warehouse' = TOR and (e1->'3'->>'avg_unit_cost')::numeric = 4,
    coalesce(e1->>'err', (select string_agg(format('%s:%s/%s/%s/%s', n, e1->n->>'fill_qty', e1->n->>'layer_qty', e1->n->>'cost_branch', coalesce(e1->n->>'layer_unit_cost', '-')), ' ' order by n) from unnest(array['1','2','3','4','5','6','7']) n)));
  perform pg_temp.res('R4b eval(원가 열쇠 없음): 수량 · 갈래 이름은 같고 돈 칸(layer_unit_cost · cost_from · avg_unit_cost)은 전부 null',
    current_setting('d.u_nocost') <> '' and e2->>'err' is null
    and (select bool_and(e2->n->>'fill_qty' is not null and e2->n->>'fill_qty' = e1->n->>'fill_qty' and e2->n->>'layer_qty' = e1->n->>'layer_qty' and e2->n->>'cost_branch' = e1->n->>'cost_branch'
                         and e2->n->>'layer_unit_cost' is null and e2->n->>'avg_unit_cost' is null and coalesce(jsonb_typeof(e2->n->'cost_from'), 'null') = 'null') from unnest(array['1','2','3','4','5','6','7']) n),
    coalesce(e2->>'err', (select string_agg(format('%s:%s/%s/%s/%s/%s', n, e2->n->>'fill_qty', e2->n->>'layer_qty', e2->n->>'cost_branch', coalesce(e2->n->>'layer_unit_cost', '-'), coalesce(e2->n->>'avg_unit_cost', '-')), ' ' order by n) from unnest(array['1','2','3','4','5','6','7']) n)));
  -- 미리 보기 = 확정: 같은 문서를 confirmed 로 세워 실제 원장 창구로 올리고 줄마다 견준다
  update public.inv_adjust_line l set delta = l.qty_input where l.adjust_id = v_id;
  update public.inv_adjust a set status = 'confirmed', posted_on = public.ims_today(), confirmed_at = now() where a.id = v_id;
  r := public.inv_post_adjust(v_id);
  perform pg_temp.res('R4c 미리 보기 = 확정: eval 의 메움 · 새 레이어 수량 · 갈래 · 단가가 inv_post_adjust 가 실제로 세운 것(raw.cost)과 줄마다 같다',
    (select count(*) = 7 and bool_and((e.raw->'cost'->>'fill_qty')::numeric = (e1->(e.raw->'line'->>'line_no')->>'fill_qty')::numeric
                                     and (e.raw->'cost'->>'layer_qty')::numeric = (e1->(e.raw->'line'->>'line_no')->>'layer_qty')::numeric
                                     and e.raw->'cost'->>'branch' = e1->(e.raw->'line'->>'line_no')->>'cost_branch'
                                     and (e.raw->'cost'->>'unit_cost')::numeric is not distinct from (e1->(e.raw->'line'->>'line_no')->>'layer_unit_cost')::numeric)
       from public.inv_ledger e where e.doc_number = 'ADJ-NB1-EV'),
    (select string_agg(format('%s:%s/%s/%s/%s', e.raw->'line'->>'line_no', e.raw->'cost'->>'fill_qty', e.raw->'cost'->>'layer_qty', e.raw->'cost'->>'branch', coalesce(e.raw->'cost'->>'unit_cost', '-')), ' ' order by (e.raw->'line'->>'line_no')::int)
       from public.inv_ledger e where e.doc_number = 'ADJ-NB1-EV'));

  -- ── R5: 하루 원가 장 — 메움 몫은 아무것도 안 쓴다 · 판매 부족분(판정 1094)은 한 번 · 새 레이어 몫만 ADJ ──
  select jsonb_object_agg(x.doc_key, jsonb_build_object('amt', x.amt, 'n', x.n, 'st', x.st)) into r
    from (select q.doc_key, sum(abs(q.raw_amount)) as amt, count(*) as n, string_agg(distinct q.status, ',') as st
            from public.qbo_cost_expected(public.ims_today(), public.ims_today()) q where q.doc_key like '%NB1-%' and q.key_kind = 'ADJ' group by q.doc_key) x;
  perform pg_temp.res('R5 하루 원가 장: 전부 메운 조정(A · F2 · C1 · G 의 + 줄 · H)은 ADJ 칸에 안 나온다 · B 는 21(= 3 × 7 · 35 아님) · R2B 3 · R2C 6.5 · 모르는 칸(block) 없음',
    not (r ? 'ADJ-NB1-A') and not (r ? 'ADJ-NB1-F2') and not (r ? 'ADJ-NB1-C1') and not (r ? 'ADJ-NB1-H') and not (r ? 'ADJ-NB1-G')
    and (r->'ADJ-NB1-B'->>'amt')::numeric = 21 and (r->'ADJ-NB1-R2B'->>'amt')::numeric = 3 and (r->'ADJ-NB1-R2C'->>'amt')::numeric = 6.5
    and not exists (select 1 from public.qbo_cost_expected(public.ims_today(), public.ims_today()) q where q.doc_key like '%NB1-%' and q.status = 'block' and q.reason like '%not in the 22 cells%'),
    left(r::text, 700));
  perform pg_temp.res('R5b 판정 1094 한 번: 재고 없이 판 SO-NB1-A 의 「장부에 없던 재고」 6.00 은 판매 때 한 번만 · 그 뒤 + 조정이 같은 재고를 다시 적지 않는다(레이어 origin 별 합)',
    (select coalesce(sum(y.qty * y.unit_cost), 0) from public.inv_layer y where y.sku = 'NB1-A' and y.warehouse = EDM and y.origin_type = 'sale_shortfall') = 6
    and (select count(*) from public.inv_layer y where y.sku = 'NB1-A' and y.warehouse = EDM and y.origin_type <> 'sale_shortfall') = 0,
    (select string_agg(format('%s %s@%s', y.origin_type, y.qty, y.unit_cost), ', ' order by y.id) from public.inv_layer y where y.sku = 'NB1-A' and y.warehouse = EDM));

  -- ── D · R3: 재생성 — 가짜 SKU 의 판매 · 조정 레이어와 소진을 지우고 원장 순서(유입 먼저 · seq_hint, id)로 다시 세운다 ⇒ 실시간과 글자 하나까지 같다 ──
  v_s1 := pg_temp.snap();
  delete from public.inv_layer_consume c using public.inv_layer y where y.id = c.layer_id and y.sku like 'NB1-%';
  delete from public.inv_layer y where y.sku like 'NB1-%' and y.origin_type in ('sale_shortfall', 'adjust_existing', 'adjust_new') and y.doc_number not in ('ADJ-NB1-H0', 'ADJ-NB1-PH');
  if to_regclass('pg_temp.inv_layer_apply_done') is null then
    create temp table inv_layer_apply_done (kind text not null, doc_number text not null, sku text not null, warehouse text not null, day date not null default '0001-01-01', primary key (kind, doc_number, sku, warehouse, day)) on commit drop;
  end if;
  v_n := 0;
  for v_row in select e.* from public.inv_ledger e where e.sku like 'NB1-%' and e.doc_number <> 'NB1-SEED' order by e.occurred_on, e.seq_hint, e.id loop
    if v_row.event_type = 'sale_out' then
      perform public.inv_layer_post_sale(v_row.doc_number, v_row.line_ref, v_row.sku, v_row.warehouse, -v_row.qty_delta, v_row.occurred_on, v_row.raw->'cost'->'shortfall');
    else
      perform public.inv_layer_apply_adjust_ims(v_row.id, null);
    end if;
    v_n := v_n + 1;
  end loop;
  v_s2 := pg_temp.snap();
  perform pg_temp.res('D 재생성(hint): 가짜 SKU 의 레이어 · 소진 · 남은 가치가 실시간과 같다(유입 먼저 순서 · 조정이 판매보다 앞서 돈다)', v_s1 = v_s2 and v_n >= 30, format('before %s ‖ after %s ‖ replayed %s', v_s1, v_s2, v_n));
  -- 옛 행(열쇠 fill_qty 없는 hint)은 옛 결과 그대로: 레이어 남은 > 장부인 자리여도 메우지 않는다(다시 세지 않는다)
  r := public.inv_layer_post_adjust('ADJ-NB1-OLD', 'old1', 'NB1-H', EDM, 1, public.ims_today(), null, '{"qty": 1, "unit_cost": 5.5, "cost_source": "layer_avg", "branch": "layer_avg"}'::jsonb);
  perform pg_temp.res('R3 옛 hint(fill_qty 없음)는 옛 결과 그대로: 메우지 않고 layer_avg 5.50 레이어 1', r->>'cost_source' = 'layer_avg' and (r->>'unit_cost')::numeric = 5.5 and r ? 'layer_id' and coalesce((r->>'fill_qty')::numeric, 0) = 0, r::text);

  -- ── S: 정적 · 권한 ──
  perform pg_temp.res('S1 safeupdate 정적: inv_layer_post_adjust · inv_adjust_eval · inv_layer_recent_cost 에 WHERE 없는 update · delete 0(스캐너 자기 시험 포함)',
    pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text = '101'
    and (select coalesce(sum(pg_temp.nowhere(p.prosrc)), -1) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_adjust', 'inv_adjust_eval', 'inv_layer_recent_cost')) = 0,
    (select string_agg(p.proname || '=' || pg_temp.nowhere(p.prosrc), ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_adjust', 'inv_adjust_eval', 'inv_layer_recent_cost')));
  perform pg_temp.res('S2 권한: eval 의 ACL 이 적용 전과 같다(authenticated 실행 · anon 없음) · 새 도우미 · 창구는 직원이 못 부른다 · 셋 다 definer',
    (select coalesce(p.proacl::text, '-') from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_adjust_eval') = current_setting('d.eval_acl')
    and has_function_privilege('authenticated', 'public.inv_adjust_eval(uuid)', 'execute') and not has_function_privilege('anon', 'public.inv_adjust_eval(uuid)', 'execute')
    and v_applied and not has_function_privilege('authenticated', to_regprocedure('public.inv_layer_recent_cost(text,text)'), 'execute')
    and not has_function_privilege('authenticated', 'public.inv_layer_post_adjust(text, text, text, text, numeric, date, numeric, jsonb)', 'execute')
    and (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_adjust', 'inv_adjust_eval', 'inv_layer_recent_cost') and p.prosecdef) = 3,
    (select string_agg(p.proname || ' ' || coalesce(p.proacl::text, '-') || ' definer ' || p.prosecdef, ' ‖ ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_adjust', 'inv_adjust_eval', 'inv_layer_recent_cost')));

  -- ── Z: 실물 무접촉 ──
  perform pg_temp.res('Z 실물 무접촉: 가짜(NB1) 밖의 원장 · 레이어 · 조정 문서 수가 머리와 같다 · claims 비었음 · postgres',
    (select count(*) from public.inv_ledger e where e.sku not like 'NB1-%')::text || '/' || (select count(*) from public.inv_layer y where y.sku not like 'NB1-%')::text || '/' || (select count(*) from public.inv_adjust a where a.adjust_number not like 'ADJ-NB1-%')::text = current_setting('d.real_head')
    and coalesce(current_setting('request.jwt.claims', true), '') = '' and current_user = 'postgres',
    format('head %s · now %s/%s/%s · user %s', current_setting('d.real_head'), (select count(*) from public.inv_ledger e where e.sku not like 'NB1-%'), (select count(*) from public.inv_layer y where y.sku not like 'NB1-%'),
           (select count(*) from public.inv_adjust a where a.adjust_number not like 'ADJ-NB1-%'), current_user));
end $$;

begin;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select pg_temp.run();
select case when t.ok then 'OK ' || t.tag else 'FAIL (' || t.tag || '): ' || t.detail end from t_res t order by t.seq;
select 'OK ' || count(*) filter (where t.ok) || ' · FAIL ' || count(*) filter (where not t.ok) || ' · adj seq ' || :'seq_head' || ' → ' || (select last_value::text from public.inv_adjust_number_seq)
       || ' · begin ~ 끝 ' || (clock_timestamp() - :'t_begin'::timestamptz)::text from t_res t;
\pset tuples_only off
\pset format aligned
rollback;
-- 기대: 시험(-v mig) OK 24 · FAIL 0 · 마른 실행(적용 전 · -v mig 없음) OK 4(R2-② · R3 옛 hint · S1 · Z) · FAIL 20(A 가 결함 재현) · 확인(적용 뒤 · -v mig 없음) OK 24 · FAIL 0 · 변이: 메움 끔 FAIL 11 · 도우미 순서 바꿈 FAIL 4 · hint 무시 FAIL 2 · 시험 begin ~ 끝 ≈ 10 s
