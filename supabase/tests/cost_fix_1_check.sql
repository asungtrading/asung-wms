-- supabase/tests/cost_fix_1_check.sql — cost-fix-1 기초 경계 트랜스퍼 도착 레이어 원가 바로잡기 검증 (2026-11-01 · 판정 932)
-- [테스트 · Asung-IMS] 시험 적용 장치 — db_role = test 가드 → 기준(begin 앞: 함수 아홉 md5 · 행 수) → begin → (-v mig 면 \i + G0) → 가짜 직원 → 검사 → rollback → Z1
--   Claude Code(시험 · 레포 루트): MIG=supabase/migrations/20261101160000_cost_fix_1_opening_transfer_layer_cost.sql psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=$MIG -f supabase/tests/cost_fix_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다(MIG= 도 필요 없다) — 차이는 G0(시험만 · echo 줄 · t_res 밖)뿐 · 기대 OK 수는 같다
--   기대 OK: 37 · MISMATCH 0 · Z1 OK 한 줄 · 「begin ~ here」 10 초 안
--   쓰기: 가짜 직원 1(replica · cfx1-*) · 가짜 레이어 16(CFX1-* · 기초 3 · 뿌리 7 · 자식 2 · 쌍둥이 2 · 미끼 2) · 소비 4 · inv_cost 1 · inv_snapshot 1 · 사건(창구가 만든다) · 실물 뿌리 하나(R · DNL01595 TR-03975)에 얹기 — 전부 rollback · 실제 행 0 변경
--   REST 두 겹: ① L1 nowhere 정적 셈(새 창구 둘 · 재발행 셋 · WHERE 없는 update · delete 0) ② 새 창구 둘 · 위임 창구는 authenticated · anon EXECUTE 없음(S3) — 화면 · EF 호출 0 은 보고의 grep
--   재생성 생존: 가벼운 갈래 하나(F-R · flush_adds 직접 호출 · 임시 done 표) 는 여기 · 전량 inv_layer_apply() 는 cost_fix_1_regen_trial.sql(따로 · 90 초)
\set ON_ERROR_STOP on
\set EXPECT_OK 37
\pset pager off
select coalesce((select value from public.inv_config where key = 'db_role'), '(missing)') as db_role \gset
select (:'db_role' = 'test') as is_test \gset
\echo '── db_role' :db_role
\if :is_test
\else
\echo 'STOP — inv_config.db_role is not test — nothing was run'
\quit
\endif
-- ── 기준(begin 앞) ──
create temp table t_pre as
  select p.proname, md5(p.prosrc) as md5, p.proacl::text as acl, p.prosecdef, length(p.prosrc) as len
  from pg_proc p where p.pronamespace = 'public'::regnamespace
   and p.proname in ('inv_layer_apply', 'inv_layer_apply_flush_adds', 'inv_layer_post_cost_adjust', 'inv_cost_adjust_reverse', 'inv_layer_cost_add_settle', 'inv_layer_carry', 'inv_layer_value', 'inv_layer_fifo_take', 'inv_layer_apply_po_in',
                     'inv_layer_post_opening_fix', 'inv_cost_fix_opening_transfer');
select (select count(*) from t_pre where proname in ('inv_layer_post_opening_fix', 'inv_cost_fix_opening_transfer')) as fn_new0 \gset
select (select count(*) from public.inv_cost_adjust) as w_adj, (select count(*) from public.inv_layer) as w_layer, (select count(*) from public.inv_layer_cost_add) as w_add,
       (select count(*) from public.inv_layer_consume) as w_cons, (select count(*) from public.ims_staff) as w_staff, (select count(*) from public.inv_cost) as w_cost, (select count(*) from public.inv_snapshot) as w_snap \gset
\echo '── 기준: inv_cost_adjust' :w_adj '· inv_layer' :w_layer '· cost_add' :w_add '· consume' :w_cons '· staff' :w_staff '· inv_cost' :w_cost '· snapshot' :w_snap '· 새 함수 있음' :fn_new0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin0 \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\! sh -c 'head -26 "$MIG" | diff -q - supabase/ops/guard-test-only.sql >/dev/null && echo "G0 guard OK (first 26 lines = guard-test-only.sql)" || echo "G0 guard MISMATCH"'
\endif
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
declare v text;
begin
  execute p_sql into v;
  raise exception using errcode = 'P7777', message = coalesce(v, '(null)');
exception when sqlstate 'P7777' then return sqlerrm;
          when others then return 'ERR ' || sqlstate || ': ' || sqlerrm;
end $$;
-- WHERE 없는 update · delete 를 정적으로 센다(ar_2b_check 의 pg_temp.nowhere 그대로)
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
-- 레이어 값 한 줄(남은 수량 · 남은 가치 · 얹힌 합) — 자연키로 읽는다
create function pg_temp.lv(p_doc text, p_ref text, p_sku text, p_wh text) returns text language sql as $$
  select string_agg(v.remaining_qty::text || '/' || round(v.remaining_value, 4)::text || '/' || round(v.add_amount, 4)::text, ' | ' order by l.id)
    from public.inv_layer l cross join lateral public.inv_layer_value(l.id) v
   where l.doc_number = p_doc and l.line_ref = p_ref and l.sku = p_sku and l.warehouse = p_wh;
$$;

-- ── S) 구조 ──
select pg_temp.chk('S1 inv_cost_adjust 자연키 칸 넷', (select string_agg(column_name, ',' order by column_name) from information_schema.columns where table_schema = 'public' and table_name = 'inv_cost_adjust' and column_name like 'layer_%'), 'layer_doc_number,layer_line_ref,layer_sku,layer_warehouse');
select pg_temp.chk('S2 CHECK 넷: kind opening_fix · target layer · pair 에 layer 넷 · opening_fix ⇒ layer · cost_add kind opening_fix',
  (select (pg_get_constraintdef(oid) like '%opening_fix%')::text from pg_constraint where conname = 'inv_cost_adjust_kind_ck')
  || (select (pg_get_constraintdef(oid) like '%''layer''%')::text from pg_constraint where conname = 'inv_cost_adjust_target_ck')
  || (select (pg_get_constraintdef(oid) like '%layer_warehouse IS NOT NULL%')::text from pg_constraint where conname = 'inv_cost_adjust_target_pair_ck')
  || (select count(*)::text from pg_constraint where conname = 'inv_cost_adjust_opening_fix_ck')
  || (select (pg_get_constraintdef(oid) like '%opening_fix%')::text from pg_constraint where conname = 'inv_layer_cost_add_kind_ck'), 'truetruetrue1true');
select pg_temp.chk('S3 새 창구 둘 · 위임 창구: definer · authenticated · anon EXECUTE 없음 · service_role 있음',
  (select string_agg(p.proname || ':' || p.prosecdef::text || ':' || (not has_function_privilege('authenticated', p.oid, 'execute'))::text || ':' || (not has_function_privilege('anon', p.oid, 'execute'))::text || ':' || has_function_privilege('service_role', p.oid, 'execute')::text, ' · ' order by p.proname)
     from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('inv_layer_post_opening_fix', 'inv_cost_fix_opening_transfer', 'inv_layer_post_cost_adjust')),
  'inv_cost_fix_opening_transfer:true:true:true:true · inv_layer_post_cost_adjust:true:true:true:true · inv_layer_post_opening_fix:true:true:true:true');
select pg_temp.chk('S4 무접촉 여섯(settle · carry · value · fifo_take · apply 본체 · apply_po_in) prosrc md5 = begin 앞',
  (select count(*)::text from t_pre t join pg_proc p on p.pronamespace = 'public'::regnamespace and p.proname = t.proname and md5(p.prosrc) = t.md5
    where t.proname in ('inv_layer_cost_add_settle', 'inv_layer_carry', 'inv_layer_value', 'inv_layer_fifo_take', 'inv_layer_apply', 'inv_layer_apply_po_in')), '6');
select pg_temp.chk('S5 재발행 셋: 본문에 cost-fix-1 표식 · 위임 · layer 갈래 · 자연키 복사',
  (select (prosrc like '%return public.inv_layer_post_opening_fix(p_adjust_id, p_on);%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_layer_post_cost_adjust')
  || (select (prosrc like '%if v_adj.target_type = ''layer'' then%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_layer_apply_flush_adds')
  || (select (prosrc like '%v_j.layer_doc_number, v_j.layer_line_ref, v_j.layer_sku, v_j.layer_warehouse, -v_j.amount_cad%')::text from pg_proc where pronamespace = 'public'::regnamespace and proname = 'inv_cost_adjust_reverse'), 'truetruetrue');
select pg_temp.chk('S6 reverse ACL 원래대로(authenticated 있음 · anon 없음) · definer', (select has_function_privilege('authenticated', p.oid, 'execute')::text || (not has_function_privilege('anon', p.oid, 'execute'))::text || p.prosecdef::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'inv_cost_adjust_reverse'), 'truetruetrue');
select pg_temp.chk('L1 nowhere: 새 둘 · 재발행 셋 WHERE 없는 update · delete 0(함수마다 「이름 0」)',
  (select string_agg(proname || ' ' || pg_temp.nowhere(prosrc)::text, ' · ' order by proname) from pg_proc where pronamespace = 'public'::regnamespace
    and proname in ('inv_layer_post_opening_fix', 'inv_cost_fix_opening_transfer', 'inv_layer_post_cost_adjust', 'inv_layer_apply_flush_adds', 'inv_cost_adjust_reverse')),
  'inv_cost_adjust_reverse 0 · inv_cost_fix_opening_transfer 0 · inv_layer_apply_flush_adds 0 · inv_layer_post_cost_adjust 0 · inv_layer_post_opening_fix 0');
select pg_temp.chk('L0 scanner self-test', pg_temp.nowhere('update t set a = 1;')::text || pg_temp.nowhere('update t set a = 1 where b = 2;')::text || pg_temp.nowhere('delete from t;')::text, '101');

-- ── C) CHECK 동작 ──
select pg_temp.chk('C1 opening_fix 는 layer 대상만(po_line 이면 거부)', left(pg_temp.try($q$insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number) values ('opening_fix', 'po_line', gen_random_uuid(), 1, 'x', 'X') returning id::text$q$), 9), 'ERR 23514');
select pg_temp.chk('C2 layer 대상은 자연키 넷 모두(셋이면 거부)', left(pg_temp.try($q$insert into public.inv_cost_adjust (kind, target_type, layer_doc_number, layer_line_ref, layer_sku, amount_cad, source_type, source_number) values ('opening_fix', 'layer', 'D', 'L', 'S', 1, 'x', 'X') returning id::text$q$), 9), 'ERR 23514');
select pg_temp.chk('C3 po_line 대상에 자연키를 실으면 거부(pair)', left(pg_temp.try($q$insert into public.inv_cost_adjust (kind, target_type, po_line_id, layer_doc_number, layer_line_ref, layer_sku, layer_warehouse, amount_cad, source_type, source_number) values ('price_adjust', 'po_line', gen_random_uuid(), 'D', 'L', 'S', 'W', 1, 'x', 'X') returning id::text$q$), 9), 'ERR 23514');

-- ── 가짜 직원(purchasing 열쇠) · 가짜 가족 ──
insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (gen_random_uuid(), 'cfx1-p@test.invalid', 'CFX1 P', 'manager', '["purchasing"]', '{}') returning auth_user_id::text as p_uid \gset
\set p '{"sub":"' :p_uid '","role":"authenticated"}'
select set_config('request.jwt.claims', :'p', true) as staff_claims_set \gset
select public.ims_today() as today \gset
select max(id) as maxled from public.inv_ledger \gset
-- 기초(토론토 둘 → 가중 3.0 · EDM 하나 9 는 other_wh 가 먼저라 안 쓰인다) · B 는 EDM 기초만 1.25 · C 는 inv_cost 7 · D 는 compare 2 · E 는 아무것도 없음
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) values
  ('CFX1-A', 'Asung Trading Inc.', 'baseline', 'CFX1-BASE', 'b1', null, '2026-08-20', true, 5, 2.5, 'snapshot_value'),
  ('CFX1-A', 'Asung Trading Inc.', 'baseline', 'CFX1-BASE', 'b2', null, '2026-08-20', true, 5, 3.5, 'snapshot_value'),
  ('CFX1-A', 'Asung - Edmonton',   'baseline', 'CFX1-BASE', 'b3', null, '2026-08-20', true, 1, 9,   'snapshot_value'),
  ('CFX1-B', 'Asung - Edmonton',   'baseline', 'CFX1-BASE', 'b4', null, '2026-08-20', true, 4, 1.25, 'snapshot_value');
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) values
  ('CFX1-A', 'Asung - Edmonton', 'transfer', 'TR-CFX1', 'cfx1-a', null, '2026-08-26', false, 10, 0, 'unknown') returning id as ra \gset
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) values
  ('CFX1-A', 'IN_TRANSIT', 'transfer', 'TR-CFX2', 'cfx2-a', :ra, '2026-09-10', false, 4, 0, 'parent_layer') returning id as ca \gset
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) values
  ('CFX1-A', 'Asung - Edmonton', 'transfer', 'TR-CFX2', 'cfx2-a-arrive', :ca, '2026-09-12', false, 4, 0, 'parent_layer') returning id as ga \gset
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) values
  ('CFX1-B', 'Asung - Edmonton', 'transfer', 'TR-CFX1', 'cfx1-b', null, '2026-08-26', false, 6, 0, 'unknown'),
  ('CFX1-C', 'Asung - Edmonton', 'transfer', 'TR-CFX1', 'cfx1-c', null, '2026-08-26', false, 2, 0, 'unknown'),
  ('CFX1-D', 'Asung - Edmonton', 'transfer', 'TR-CFX1', 'cfx1-d', null, '2026-08-26', false, 3, 0, 'unknown'),
  ('CFX1-E', 'Asung - Edmonton', 'transfer', 'TR-CFX1', 'cfx1-e', null, '2026-08-26', false, 1, 0, 'unknown'),
  ('CFX1-F', 'Asung - Edmonton', 'transfer', 'TR-CFX1', 'cfx1-f', null, '2026-08-26', false, 2, 0, 'unknown'),     -- 쌍둥이(같은 자연키 둘)
  ('CFX1-F', 'Asung - Edmonton', 'transfer', 'TR-CFX1', 'cfx1-f', null, '2026-08-26', false, 2, 0, 'unknown'),
  ('CFX1-G', 'Asung - Edmonton', 'transfer', 'TR-CFX1', 'cfx1-g', null, '2026-08-26', false, 5, 0, 'unknown'),
  ('CFX1-A', 'Asung - Edmonton', 'transfer', 'TR-OTHER', 'oth-a', null, '2026-08-26', false, 7, 0, 'unknown');       -- 미끼: p_docs 밖
insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source) values
  ('CFX1-F', 'Asung Trading Inc.', 'baseline', 'CFX1-BASE', 'b5', null, '2026-08-20', true, 1, 4, 'snapshot_value'),
  ('CFX1-G', 'Asung Trading Inc.', 'baseline', 'CFX1-BASE', 'b6', null, '2026-08-20', true, 1, 5, 'snapshot_value');
-- 소비: 뿌리 A 판매 2 · 뿌리 A → 자식 4(transfer) · 자식 → 손자 4 · 손자 판매 1 ⇒ 뿌리 남음 4 · 자식 0 · 손자 3
insert into public.inv_layer_consume (layer_id, doc_type, doc_number, line_ref, event_type, occurred_on, qty, unit_cost, amount, reason) values
  (:ra, 'sale', 'SO-CFX1', 'l1', 'sale_out', '2026-09-01', 2, 0, 0, 'sale'),
  (:ra, 'transfer', 'TR-CFX2', 'cfx2-a', 'transfer_out', '2026-09-10', 4, 0, 0, 'transfer'),
  (:ca, 'transfer', 'TR-CFX2', 'cfx2-a', 'transfer_out', '2026-09-12', 4, 0, 0, 'transfer'),
  (:ga, 'sale', 'SO-CFX2', 'l1', 'sale_out', '2026-09-20', 1, 0, 0, 'sale');
insert into public.inv_cost (doc_type, doc_number, line_ref, sku, warehouse, bin, occurred_on, cost_kind, qty, amount, unit_cost, collector, refreshed_at) values
  ('purchase', 'PO-CFX1', 'cfx-po-1', 'CFX1-C', 'Asung Trading Inc.', '', '2026-07-01', 'goods', 10, 70, 7, 'cfx1-test', now());
insert into public.inv_snapshot (snapshot_key, taken_at, sku, warehouse, bin, qty, value) values ('cfx1-compare', now(), 'CFX1-D', 'Asung Trading Inc.', 'X', 10, 20);

-- ── F) 기능 ──
select public.inv_cost_fix_opening_transfer(array['TR-CFX1'], null, 'cfx1-compare', true) as dry \gset
select pg_temp.chk('F1 dry: 본 레이어 8(A ~ G · F 쌍둥이 둘 · 미끼 TR-OTHER 제외) · posted 0 · no_unit_cost 1(E) · 합 30 + 7.5 + 14 + 6 + 16(F 둘) + 25(G) = 98.5 · 쓰기 0',
  (:'dry'::jsonb ->> 'layers_seen') || ' ' || (:'dry'::jsonb ->> 'posted') || ' ' || (:'dry'::jsonb ->> 'skipped_no_unit_cost') || ' ' || (:'dry'::jsonb ->> 'amount_total_cad') || ' ' || (select count(*) from public.inv_cost_adjust where kind = 'opening_fix')::text, '8 0 1 98.500000 0');
select pg_temp.chk('F2 dry 갈래: A baseline_other_wh 3.0 · B baseline_same_wh 1.25 · C inv_cost_recent 7 · D compare_snapshot 2',
  (select string_agg((e ->> 'sku') || ':' || (e ->> 'basis') || ':' || (e ->> 'unit_cost'), ' · ' order by e ->> 'sku') from jsonb_array_elements(:'dry'::jsonb -> 'lines') e where e ->> 'sku' in ('CFX1-A', 'CFX1-B', 'CFX1-C', 'CFX1-D')),
  'CFX1-A:baseline_other_wh:3.000000 · CFX1-B:baseline_same_wh:1.250000 · CFX1-C:inv_cost_recent:7.000000 · CFX1-D:compare_snapshot:2.000000');
-- 실제 얹기 — F 쌍둥이는 「2 레이어」 예외로 전체가 되돌아가므로 먼저 빼고(p_skus) 쌍둥이는 F5 에서 따로 본다
select public.inv_cost_fix_opening_transfer(array['TR-CFX1'], array['CFX1-A', 'CFX1-B', 'CFX1-C', 'CFX1-D', 'CFX1-E'], 'cfx1-compare', false) as ap \gset
select pg_temp.chk('F3 apply: posted 4 · no_unit_cost 1 · 합 57.5 · 나간 9(뿌리 A cost_late 6 + 손자 cost_late 3) · 남은 48.5',
  (:'ap'::jsonb ->> 'posted') || ' ' || (:'ap'::jsonb ->> 'skipped_no_unit_cost') || ' ' || (:'ap'::jsonb ->> 'amount_total_cad') || ' ' || (:'ap'::jsonb ->> 'gone_cad') || ' ' || (:'ap'::jsonb ->> 'remaining_cad'), '4 1 57.500000 9.000000 48.500000');
select pg_temp.chk('F4 by_basis 합', (select string_agg(t.k || '=' || t.v, ' · ' order by t.k) from jsonb_each_text(:'ap'::jsonb -> 'by_basis') as t(k, v)), 'baseline_other_wh=30.000000 · baseline_same_wh=7.500000 · compare_snapshot=6.000000 · inv_cost_recent=14.000000');
select pg_temp.chk('F5 쌍둥이 F: 사건은 서지만 얹기가 「names 2 layers」 로 거부 · 전체 되돌아감(opening_fix 사건 여전히 4)',
  left(pg_temp.try($q$select public.inv_cost_fix_opening_transfer(array['TR-CFX1'], array['CFX1-F'], 'cfx1-compare', false)::text$q$), 9) || ' ' || (select count(*) from public.inv_cost_adjust where kind = 'opening_fix')::text, 'ERR P0001 4');
select pg_temp.chk('F6 레이어 값(남은 수량/남은 가치/얹힌): 뿌리 A 4/12/30 · 자식 0/0/12 · 손자 3/9/12 · B 6/7.5/7.5 · C 2/14/14 · D 3/6/6 · E 1/0/0',
  pg_temp.lv('TR-CFX1', 'cfx1-a', 'CFX1-A', 'Asung - Edmonton') || ' ; ' || pg_temp.lv('TR-CFX2', 'cfx2-a', 'CFX1-A', 'IN_TRANSIT') || ' ; ' || pg_temp.lv('TR-CFX2', 'cfx2-a-arrive', 'CFX1-A', 'Asung - Edmonton')
  || ' ; ' || pg_temp.lv('TR-CFX1', 'cfx1-b', 'CFX1-B', 'Asung - Edmonton') || ' ; ' || pg_temp.lv('TR-CFX1', 'cfx1-c', 'CFX1-C', 'Asung - Edmonton') || ' ; ' || pg_temp.lv('TR-CFX1', 'cfx1-d', 'CFX1-D', 'Asung - Edmonton') || ' ; ' || pg_temp.lv('TR-CFX1', 'cfx1-e', 'CFX1-E', 'Asung - Edmonton'),
  '4/12.0000/30.0000 ; 0/0.0000/12.0000 ; 3/9.0000/12.0000 ; 6/7.5000/7.5000 ; 2/14.0000/14.0000 ; 3/6.0000/6.0000 ; 1/0.0000/0.0000');
select pg_temp.chk('F7 뿌리 A 의 소비 줄: cost_late 6(kind opening_fix · sold 2/10) · cost_moved 12(moved 4) · 손자 cost_late 3(kind carried · line_ref adj:) · 자식(IN_TRANSIT) 은 cost_moved 한 줄(carried 12 가 손자로 다 옮겨 감)',
  (select string_agg(k.reason || ':' || k.amount::text || ':' || coalesce(k.split_basis ->> 'kind', '') || ':' || (k.line_ref like 'adj:%')::text, ' · ' order by k.reason) from public.inv_layer_consume k where k.layer_id = :ra and k.qty = 0)
  || ' ; ' || (select string_agg(k.reason || ':' || k.amount::text || ':' || coalesce(k.split_basis ->> 'kind', '') || ':' || (k.line_ref like 'adj:%')::text, ' · ' order by k.reason) from public.inv_layer_consume k where k.layer_id = :ga and k.qty = 0)
  || ' ; ' || (select count(*) from public.inv_layer_consume k where k.layer_id = :ca and k.qty = 0)::text,
  'cost_late:6.000000:opening_fix:true · cost_moved:12.000000:opening_fix:true ; cost_late:3.000000:carried:true ; 1');
select pg_temp.chk('F8 사건 행: 4 posted · target layer · kind opening_fix · source_type opening_fix · posted_on 오늘 · posted_ledger_id = 원장 max · note 에 갈래',
  (select count(*)::text || ' ' || bool_and(target_type = 'layer' and kind = 'opening_fix' and source_type = 'opening_fix' and status = 'posted' and posted_on = :'today'::date and posted_ledger_id = :maxled and note like '% (baseline_%' or note like '% (inv_cost_%' or note like '% (compare_%')::text
     from public.inv_cost_adjust where kind = 'opening_fix'), '4 true');
select pg_temp.chk('F9 얹기 줄: 뿌리 넷 opening_fix · 자식 둘 carried(ref_number layer:<부모>:<부모 kind> — 자식 …:opening_fix · 손자 …:carried) · doc_number = TR-CFX1 · line_ref adj:<id>',
  (select string_agg(kind || ':' || count::text, ' · ' order by kind) from (select ca.kind, count(*) from public.inv_layer_cost_add ca join public.inv_layer l on l.id = ca.layer_id where l.sku like 'CFX1-%' group by 1) t)
  || ' ' || (select bool_and(ca.doc_number = 'TR-CFX1' and ca.line_ref like 'adj:%' and (ca.kind <> 'carried' or ca.ref_number like 'layer:%:opening_fix' or ca.ref_number like 'layer:%:carried'))::text from public.inv_layer_cost_add ca join public.inv_layer l on l.id = ca.layer_id where l.sku like 'CFX1-%'),
  'carried:2 · opening_fix:4 true');
-- 멱등
select public.inv_cost_fix_opening_transfer(array['TR-CFX1'], array['CFX1-A', 'CFX1-B', 'CFX1-C', 'CFX1-D', 'CFX1-E'], 'cfx1-compare', false) as ap2 \gset
select pg_temp.chk('F10 두 번째 적용: posted 0 · already_fixed 4 · no_unit_cost 1 · 얹기 줄 수 그대로 6',
  (:'ap2'::jsonb ->> 'posted') || ' ' || (:'ap2'::jsonb ->> 'skipped_already_fixed') || ' ' || (:'ap2'::jsonb ->> 'skipped_no_unit_cost') || ' ' || (select count(*) from public.inv_layer_cost_add ca join public.inv_layer l on l.id = ca.layer_id where l.sku like 'CFX1-%')::text, '0 4 1 6');
select id::text as adj_a from public.inv_cost_adjust where kind = 'opening_fix' and layer_sku = 'CFX1-A' \gset
select pg_temp.chk('F11 같은 사건을 다시 얹기(위임 · 실시간) → already_posted · 0 줄', (select (public.inv_layer_post_cost_adjust(:'adj_a'::uuid)) ->> 'status'), 'already_posted');
select pg_temp.chk('F12 재생성 호출(p_on) 로도 already_posted(얹기 줄이 있으니)', (select (public.inv_layer_post_cost_adjust(:'adj_a'::uuid, :'today'::date)) ->> 'status'), 'already_posted');
set local session_replication_role = replica;   -- po_line 은 컷오버 뒤 0 행 — FK 트리거를 건너뛰고 미끼 po_line 사건 하나(되돌아간다)
insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, source_type, source_number, status) values ('price_adjust', 'po_line', gen_random_uuid(), 1, 'cfx1-test', 'CFX1-PO', 'pending') returning id::text as adj_po \gset
set local session_replication_role = origin;
select pg_temp.chk('F14 opening_fix 창구에 po_line 대상 → 「layer targets only」 거부', left(pg_temp.try(format($q$select (public.inv_layer_post_opening_fix(%L::uuid))::text$q$, :'adj_po')), 9) || ' ' || (pg_temp.try(format($q$select (public.inv_layer_post_opening_fix(%L::uuid))::text$q$, :'adj_po')) like '%layer targets only%')::text, 'ERR P0001 true');
-- 되돌림
select public.inv_cost_adjust_reverse(:'adj_a'::uuid, 'cfx1 test reversal') as rv \gset
select pg_temp.chk('F15 되돌림 A: status posted · 반대 부호 −30 · target layer · 자연키 복사됨',
  (:'rv'::jsonb ->> 'status') || ' ' || (:'rv'::jsonb ->> 'amount_cad') || ' ' || (select target_type || ':' || layer_doc_number || ':' || layer_line_ref || ':' || layer_sku || ':' || layer_warehouse from public.inv_cost_adjust where id = (:'rv'::jsonb ->> 'reversal_id')::uuid),
  'posted -30.000000 layer:TR-CFX1:cfx1-a:CFX1-A:Asung - Edmonton');
select pg_temp.chk('F16 되돌린 뒤 값: 뿌리 A 4/0/0 · 자식 0/0/0 · 손자 3/0/0(얹기 전과 같다) · B 는 그대로 6/7.5/7.5',
  pg_temp.lv('TR-CFX1', 'cfx1-a', 'CFX1-A', 'Asung - Edmonton') || ' ; ' || pg_temp.lv('TR-CFX2', 'cfx2-a', 'CFX1-A', 'IN_TRANSIT') || ' ; ' || pg_temp.lv('TR-CFX2', 'cfx2-a-arrive', 'CFX1-A', 'Asung - Edmonton') || ' ; ' || pg_temp.lv('TR-CFX1', 'cfx1-b', 'CFX1-B', 'Asung - Edmonton'),
  '4/0.0000/0.0000 ; 0/0.0000/0.0000 ; 3/0.0000/0.0000 ; 6/7.5000/7.5000');
select pg_temp.chk('F17 되돌림의 되돌림 거부 · 두 번 되돌림 거부', left(pg_temp.try(format($q$select public.inv_cost_adjust_reverse(%L::uuid)::text$q$, :'rv'::jsonb ->> 'reversal_id')), 9) || ' ' || left(pg_temp.try(format($q$select public.inv_cost_adjust_reverse(%L::uuid)::text$q$, :'adj_a')), 9), 'ERR P0001 ERR P0001');
select public.inv_cost_fix_opening_transfer(array['TR-CFX1'], array['CFX1-A', 'CFX1-B'], 'cfx1-compare', false) as ap3 \gset
select pg_temp.chk('F18 되돌린 뒤 다시 적용: A 만 다시 posted 1 · B already 1 · 뿌리 A 4/12/… 로 돌아온다 · 나간 9 · 남은 21',
  (:'ap3'::jsonb ->> 'posted') || ' ' || (:'ap3'::jsonb ->> 'skipped_already_fixed') || ' ' || (:'ap3'::jsonb ->> 'gone_cad') || ' ' || (:'ap3'::jsonb ->> 'remaining_cad') || ' ' || split_part(pg_temp.lv('TR-CFX1', 'cfx1-a', 'CFX1-A', 'Asung - Edmonton'), '/', 2), '1 1 9.000000 21.000000 12.0000');
-- 음수 가드 · 없는 레이어
insert into public.inv_cost_adjust (kind, target_type, layer_doc_number, layer_line_ref, layer_sku, layer_warehouse, amount_cad, source_type, source_number, status) values ('opening_fix', 'layer', 'TR-CFX1', 'cfx1-b', 'CFX1-B', 'Asung - Edmonton', -1000, 'cfx1-test', 'TR-CFX1', 'pending') returning id::text as adj_neg \gset
select pg_temp.chk('F19 원가보다 큰 음수 → 거부(credit larger)', (pg_temp.try(format($q$select public.inv_layer_post_cost_adjust(%L::uuid)::text$q$, :'adj_neg')) like 'ERR P0001%credit larger%')::text, 'true');
insert into public.inv_cost_adjust (kind, target_type, layer_doc_number, layer_line_ref, layer_sku, layer_warehouse, amount_cad, source_type, source_number, status) values ('opening_fix', 'layer', 'TR-NONE', 'none', 'CFX1-Z', 'Asung - Edmonton', 5, 'cfx1-test', 'TR-NONE', 'pending') returning id::text as adj_none \gset
select pg_temp.chk('F20 없는 레이어 → no_layers · pending 그대로', (select (public.inv_layer_post_cost_adjust(:'adj_none'::uuid)) ->> 'status') || ' ' || (select status from public.inv_cost_adjust where id = :'adj_none'::uuid), 'no_layers pending');

-- ── F-R) 재생성 갈래 — flush_adds 를 직접 부른다(임시 done 표 · 다른 자리는 전부 done 으로 막아 이 사건들만 남긴다) ──
select public.inv_cost_fix_opening_transfer(array['TR-CFX1'], array['CFX1-G'], 'cfx1-compare', false) as apg \gset
select id::text as adj_g, posted_ledger_id::text as g_pid from public.inv_cost_adjust where kind = 'opening_fix' and layer_sku = 'CFX1-G' \gset
-- 재생성 상태 흉내: 이 사건의 얹기 줄 · 소비 줄을 지운다(재생성은 cost_add · consume 전부를 지우고 다시 쏟는다)
delete from public.inv_layer_cost_add where line_ref = 'adj:' || :'adj_g';
delete from public.inv_layer_consume where line_ref = 'adj:' || :'adj_g';
create temp table inv_layer_apply_done (kind text, doc_number text, sku text, warehouse text);
insert into inv_layer_apply_done select 'cogs_fr', doc_number, '', '' from (select distinct doc_number from public.inv_doc_cost where kind = 'transfer_freight') d;
insert into inv_layer_apply_done select 'cogs_chg', id::text, '', '' from public.po_charge_alloc;
insert into inv_layer_apply_done select 'cogs_adj', id::text, '', '' from public.inv_cost_adjust where id <> :'adj_g'::uuid;
select public.inv_layer_apply_flush_adds(:'today'::date, null, :g_pid::bigint, '{}'::jsonb) as fl0 \gset
select pg_temp.chk('F-R1 같은 날 · p_before_id = posted_ledger_id(아직 그 줄 앞) → 안 쏟는다(adj_n 0 · deferred 0) · done 없음',
  (:'fl0'::jsonb ->> 'adj_n') || ' ' || (:'fl0'::jsonb ->> 'adj_deferred') || ' ' || (select count(*) from inv_layer_apply_done where kind = 'cogs_adj' and doc_number = :'adj_g')::text, '0 0 0');
select public.inv_layer_apply_flush_adds(:'today'::date, null, :g_pid::bigint + 1, '{}'::jsonb) as fl1 \gset
select pg_temp.chk('F-R2 p_before_id 가 지나면 쏟는다: adj_n 1 · adj_rows 1 · adj_amt 25 · skipped 0 · deferred 0 · G 값 5/25/25 · done 1',
  (:'fl1'::jsonb ->> 'adj_n') || ' ' || (:'fl1'::jsonb ->> 'adj_rows') || ' ' || (:'fl1'::jsonb ->> 'adj_amt') || ' ' || (:'fl1'::jsonb ->> 'adj_skipped') || ' ' || (:'fl1'::jsonb ->> 'adj_deferred') || ' ' || pg_temp.lv('TR-CFX1', 'cfx1-g', 'CFX1-G', 'Asung - Edmonton') || ' ' || (select count(*) from inv_layer_apply_done where kind = 'cogs_adj' and doc_number = :'adj_g')::text,
  '1 1 25.000000 0 0 5/25.0000/25.0000 1');
select pg_temp.chk('F-R3 재생성 얹기 줄 = 실시간과 같은 키(layer · opening_fix · TR-CFX1 · adj:<id> · 오늘)', (select count(*)::text from public.inv_layer_cost_add ca where ca.line_ref = 'adj:' || :'adj_g' and ca.kind = 'opening_fix' and ca.doc_number = 'TR-CFX1' and ca.occurred_on = :'today'::date and ca.amount = 25), '1');
-- 레이어가 아직 없으면 미룬다: 얹기 줄을 다시 지우고 레이어도 지운 뒤 같은 날 쏟기 → deferred 1 · done 안 씀 · 마지막 쏟기(p_day null) → no_layers 로 센다
delete from public.inv_layer_cost_add where line_ref = 'adj:' || :'adj_g';
delete from public.inv_layer_consume where line_ref = 'adj:' || :'adj_g';
delete from inv_layer_apply_done where kind = 'cogs_adj' and doc_number = :'adj_g';
delete from public.inv_layer where sku = 'CFX1-G' and origin_type = 'transfer';
select public.inv_layer_apply_flush_adds(:'today'::date, null, :g_pid::bigint + 1, '{}'::jsonb) as fl2 \gset
select public.inv_layer_apply_flush_adds(null, null, null, '{}'::jsonb) as fl3 \gset
select pg_temp.chk('F-R4 레이어 없음: 날짜 경계 → adj_deferred 1 · adj_n 0 ; 마지막 쏟기(p_day null) → adj_n 1 · adj_nolayers 1 · 얹기 줄 0 · done 은 마지막 쏟기가 쓴 1',
  (:'fl2'::jsonb ->> 'adj_deferred') || ' ' || (:'fl2'::jsonb ->> 'adj_n') || ' ; ' || (:'fl3'::jsonb ->> 'adj_n') || ' ' || (:'fl3'::jsonb ->> 'adj_nolayers') || ' ' || (select count(*) from public.inv_layer_cost_add where line_ref = 'adj:' || :'adj_g')::text || ' ' || (select count(*) from inv_layer_apply_done where kind = 'cogs_adj' and doc_number = :'adj_g')::text, '1 0 ; 1 1 0 1');
drop table inv_layer_apply_done;

-- ── R) 실물 뿌리 하나 — DNL01595 TR-03975(qty 3 · 뿌리 남음 1 · 깊이 2 자식 열림) · 단가 = 토론토 기초 가중 · 가족 남은 가치 = 단가 × 가족 남은 수량 · 나간 = 단가 × (3 − 가족 남은) ──
select round(sum(l.unit_cost * l.qty) / sum(l.qty), 6)::text as r_unit from public.inv_layer l where l.origin_type = 'baseline' and l.sku = 'DNL01595' and l.warehouse = 'Asung Trading Inc.' \gset
create temp table r_fam as
with recursive fam as (
  select id from public.inv_layer where doc_number = 'TR-03975' and sku = 'DNL01595' and parent_layer_id is null and origin_type = 'transfer'
  union all select c.id from public.inv_layer c join fam f on c.parent_layer_id = f.id)
select fam.id from fam;
select (select sum(v.remaining_qty) from r_fam cross join lateral public.inv_layer_value(r_fam.id) v) as r_rem,
       (select count(*) from r_fam) as r_n,
       (select sum(v.remaining_value) from r_fam cross join lateral public.inv_layer_value(r_fam.id) v) as r_val0 \gset
select public.inv_cost_fix_opening_transfer(array['TR-03975'], array['DNL01595'], '2026-10-30-compare', false) as apr \gset
select pg_temp.chk('R1 실물 DNL01595: 얹기 전 가족 가치 0 · 가족 레이어 ≥ 3 · posted 1 · 갈래 baseline_other_wh · 단가 = 토론토 기초 가중',
  round(:r_val0::numeric, 4)::text || ' ' || (:r_n >= 3)::text || ' ' || (:'apr'::jsonb ->> 'posted') || ' ' || (select (e ->> 'basis') || ' ' || (e ->> 'unit_cost') from jsonb_array_elements(:'apr'::jsonb -> 'lines') e limit 1), '0.0000 true 1 baseline_other_wh ' || :'r_unit');
select pg_temp.chk('R2 실물: 가족 남은 가치 = 단가 × 가족 남은 수량(0.01 안) · 나간 = 단가 × (3 − 남은)(0.01 안) · 뿌리 + 자식 중 0 원 열린 레이어 0',
  (abs((select sum(v.remaining_value) from r_fam cross join lateral public.inv_layer_value(r_fam.id) v) - :'r_unit'::numeric * :r_rem) < 0.01)::text
  || ' ' || (abs((:'apr'::jsonb ->> 'gone_cad')::numeric - :'r_unit'::numeric * (3 - :r_rem)) < 0.01)::text
  || ' ' || (select count(*) from r_fam cross join lateral public.inv_layer_value(r_fam.id) v where v.remaining_qty > 0 and v.remaining_value = 0)::text, 'true true 0');
select pg_temp.chk('R3 실물: 다른 뿌리(TR-03975 · 03976) 는 무접촉 — 얹기 줄 있는 뿌리 1 · unknown 뿌리 259 그대로',
  (select count(distinct l.id)::text from public.inv_layer l join public.inv_layer_cost_add ca on ca.layer_id = l.id where l.doc_number in ('TR-03975', 'TR-03976')) || ' ' || (select count(*)::text from public.inv_layer where doc_number in ('TR-03975', 'TR-03976') and cost_source = 'unknown'), '1 259');

-- ── 결과 ──
select clock_timestamp() - :'t_begin0'::timestamptz as begin_to_now \gset
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || left(coalesce(got, '(null)'), 400) || ' want=' || left(coalesce(want, '(null)'), 400) end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
\echo '── begin ~ here:' :begin_to_now
rollback;
select case when (select count(*) from public.inv_cost_adjust) = :w_adj and (select count(*) from public.inv_layer) = :w_layer and (select count(*) from public.inv_layer_cost_add) = :w_add
            and (select count(*) from public.inv_layer_consume) = :w_cons and (select count(*) from public.ims_staff) = :w_staff and (select count(*) from public.inv_cost) = :w_cost and (select count(*) from public.inv_snapshot) = :w_snap
            and (select count(*) from public.ims_staff where email like 'cfx1-%') = 0 and (select count(*) from public.inv_layer where sku like 'CFX1-%') = 0
            and (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('inv_layer_post_opening_fix', 'inv_cost_fix_opening_transfer')) = :fn_new0
       then 'Z1 OK real rows unchanged (inv_cost_adjust · inv_layer · cost_add · consume · staff · inv_cost · snapshot · no cfx1 rows) · new fn presence = begin 앞' else 'Z1 FAIL' end as z1;
