-- layer-fix-1-regen.sql — 레이어 재생성(reload §H 의 운영판) · deferred 403 · 2026-10-31
--
-- [Asung-IMS · fazgmyvzzhqybtvtktyg · 지금의 메인] 에서 psql 로만:
--   시험(끝에 rollback · Claude):  psql "$(cat ~/.asung-testdb-url)" -v mode=trial -f supabase/ops/layer-fix-1-regen.sql
--   실행(끝에 commit · Caleb):     psql "$(cat ~/.asung-testdb-url)" -v mode=apply -f supabase/ops/layer-fix-1-regen.sql
--   mode 를 안 주면 trial 이다. 두 모드는 마지막 한 줄(commit / rollback)만 다르다.
--
-- 전제: 마이그레이션 20261031200000_layer_fix_1_po_in_net 이 적용돼 있다(아래 가드가 prosrc md5 로 확인한다 · 아니면 멈춤).
--
-- reload §H 와 다른 점(2026-10-31 Caleb 결정 · 이견 2 · 3):
--   · truncate + seed_baseline 을 하지 않는다 — inv_layer_apply() 가 스스로 consume · cost_add 전부와 baseline 아닌 레이어를 delete 한다.
--     기초선(2026-08-20-initial · 13,830 레이어 · 1,909,097)이 그대로인지 머리에서 검산한다. truncate 의 ACCESS EXCLUSIVE 가 없어 읽기는 끊기지 않는다.
--   · 운영 중이라 쓰기만 막는다 — 네 표를 EXCLUSIVE 로 잠근다(읽기 통과 · 포스터는 대기). lock_timeout 30s — 끊기면(교착 · 긴 포스터) 그냥 다시 돌린다.
--     포스터(PostgREST · authenticator)는 lock_timeout 8s 라 그 동안의 쓰기는 「lock timeout」 오류로 돌아간다 — 다시 하면 된다. 끝에 대기자를 pg_stat_activity 로 찍는다.
--   · 끝에 §I 검산 — 기대와 어긋나면 raise → 두 모드 다 자동 롤백.
\set ON_ERROR_STOP on
\timing on
\if :{?mode}
\else
\set mode trial
\endif
\echo mode = :mode

begin;
set local lock_timeout = '30s';
set local statement_timeout = 0;

-- ⛔ 창 가드 — po_line 은 IMS 전용 표. 없으면 이 창은 옛 asung-WMS 다.
do $$ begin
  if not exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'po_line') then
    raise exception 'not Asung-IMS: po_line missing — wrong project';
  end if;
end $$;

-- 가드 ① 함수 판 — layer-fix-1 의 inv_layer_apply_po_in 인가 (20261031200000 본문 md5)
do $$ declare v text; begin
  select md5(prosrc) into v from pg_proc where proname = 'inv_layer_apply_po_in';
  if v is distinct from '5627335f80c846b6f1588af3e70c6cfb' then
    raise exception 'inv_layer_apply_po_in is not the layer-fix-1 version (md5 %) — apply migration 20261031200000 first', v;
  end if;
end $$;

-- 가드 ② 기초선 무변 — truncate + seed 를 생략하는 근거
do $$ declare v_key text; v_l int; v_lq numeric; v_s int; v_sq numeric; begin
  select value into v_key from inv_config where key = 'baseline_snapshot_key';
  if v_key is distinct from '2026-08-20-initial' then raise exception 'baseline_snapshot_key is % (expected 2026-08-20-initial)', v_key; end if;
  select count(*), sum(qty) into v_l, v_lq from inv_layer where origin_type = 'baseline';
  select count(*), sum(qty) into v_s, v_sq from (select sku, warehouse, sum(qty) qty from inv_snapshot where snapshot_key = v_key and qty > 0 group by 1, 2) s;
  if v_l <> v_s or v_lq <> v_sq then
    raise exception 'baseline layers (% rows · %) <> snapshot % (% keys · %) — do not skip truncate+seed; use reload §H as written', v_l, v_lq, v_key, v_s, v_sq;
  end if;
  raise notice 'baseline ok: % layers · qty % = snapshot %', v_l, v_lq, v_key;
end $$;

-- 잠금 — 쓰기만 막는다(EXCLUSIVE 는 ACCESS SHARE 와 안 부딪힌다 = 읽기 통과)
select clock_timestamp() as lock_wait_from \gset
lock table inv_ledger, inv_layer, inv_layer_consume, inv_layer_cost_add in exclusive mode;
select clock_timestamp() - :'lock_wait_from'::timestamptz as lock_waited;

-- 권한 — 창구(inv_layer_post_receipt · post_charge)가 receiving · purchasing 쓰기 권한을 본다(§H 그대로 · 트랜잭션 한정)
select set_config('request.jwt.claims',
  (select jsonb_build_object('sub', auth_user_id, 'role', 'authenticated')::text
     from ims_staff where email = 'caleb@asung.ca'), true);

-- ── 전(前) 값 ──
create temp table lf1_gap_before on commit drop as
  with layer as (select sku, warehouse, sum(remaining_qty) as layer_qty from inv_layer_open group by sku, warehouse),
       bal   as (select sku, warehouse, sum(qty) as bal_qty from inv_balance group by sku, warehouse)
  select coalesce(b.sku, l.sku) as sku, coalesce(b.warehouse, l.warehouse) as warehouse,
         coalesce(l.layer_qty, 0) as layer_qty, coalesce(b.bal_qty, 0) as bal_qty,
         coalesce(l.layer_qty, 0) - coalesce(b.bal_qty, 0) as gap
  from bal b full join layer l using (sku, warehouse)
  where coalesce(l.layer_qty, 0) <> coalesce(b.bal_qty, 0);
create temp table lf1_value_before on commit drop as
  select l.warehouse, round(sum(v.remaining_value), 2) as value, count(*) as layers
  from inv_layer l cross join lateral inv_layer_value(l.id) v where v.remaining_qty > 0 group by 1;
\echo --- BEFORE: §I ② (창고별 어긋난 칸)
select warehouse, count(*) as rows, sum(gap) as gap_sum, count(*) filter (where bal_qty < 0) as balance_negative from lf1_gap_before group by 1 order by 1;
\echo --- BEFORE: 평가액(창고별) · Kim & C PO-01361 몫
select * from lf1_value_before order by 1;
select 'PO-01361' as doc, round(sum(v.remaining_value), 2) as value, sum(v.remaining_qty) as qty from inv_layer l cross join lateral inv_layer_value(l.id) v where l.doc_number = 'PO-01361';
select (select count(*) from inv_layer) as inv_layer, (select count(*) from inv_layer_consume) as consume, (select count(*) from inv_layer_cost_add) as cost_add;

-- ── 재생성 ──
select clock_timestamp() as apply_from \gset
create temp table lf1_res on commit drop as select inv_layer_apply() as res;   -- psql 변수는 do $$ 안에서 안 풀린다 — 임시 표로 넘긴다
select clock_timestamp() - :'apply_from'::timestamptz as apply_elapsed;
\echo --- inv_layer_apply() 반환
select jsonb_pretty(res) from lf1_res;

-- ── 후(後) 값 ──
create temp table lf1_gap_after on commit drop as
  with layer as (select sku, warehouse, sum(remaining_qty) as layer_qty from inv_layer_open group by sku, warehouse),
       bal   as (select sku, warehouse, sum(qty) as bal_qty from inv_balance group by sku, warehouse)
  select coalesce(b.sku, l.sku) as sku, coalesce(b.warehouse, l.warehouse) as warehouse,
         coalesce(l.layer_qty, 0) as layer_qty, coalesce(b.bal_qty, 0) as bal_qty,
         coalesce(l.layer_qty, 0) - coalesce(b.bal_qty, 0) as gap
  from bal b full join layer l using (sku, warehouse)
  where coalesce(l.layer_qty, 0) <> coalesce(b.bal_qty, 0);
\echo --- AFTER: §I ② (창고별)
select warehouse, count(*) as rows, sum(gap) as gap_sum, count(*) filter (where bal_qty < 0) as balance_negative from lf1_gap_after group by 1 order by 1;
\echo --- AFTER: 실제 창고에 남은 칸 (기대 = 허용 목록뿐)
select * from lf1_gap_after where warehouse <> 'IN_TRANSIT' order by warehouse, sku;
\echo --- AFTER: IN_TRANSIT 레이어가 선 문서 (기대 = TR-06396 ~ 06399 넷만 · TR-03975 · 03976 잔재는 IN_TRANSIT 「음수 잔고 259 칸」 이지 레이어가 아니다 — 시험 2026-10-31 실측)
select doc_number, count(*) as layers, sum(remaining_qty) as qty from inv_layer_open where warehouse = 'IN_TRANSIT' group by 1 order by 1;
\echo --- AFTER: 표본 — Kim & C 5 · LAC793xx 14 · 893 표본 5 (gap 기대 0 · 없으면 맞는 칸)
with cells(sku, warehouse) as (values
  ('AS91603','Asung Trading Inc.'),('AS93280','Asung Trading Inc.'),('AS93281','Asung Trading Inc.'),('AS93283','Asung Trading Inc.'),('AS93284','Asung Trading Inc.'),
  ('LAC79351','Asung Trading Inc.'),('LAC79352','Asung Trading Inc.'),('LAC79353','Asung Trading Inc.'),('LAC79354','Asung Trading Inc.'),('LAC79355','Asung Trading Inc.'),
  ('LAC79356','Asung Trading Inc.'),('LAC79357','Asung Trading Inc.'),('LAC79358','Asung Trading Inc.'),('LAC79359','Asung Trading Inc.'),('LAC79360','Asung Trading Inc.'),
  ('LAC79361','Asung Trading Inc.'),('LAC79362','Asung Trading Inc.'),('LAC79363','Asung Trading Inc.'),('LAC79364','Asung Trading Inc.'),
  ('UNF18054','Asung Trading Inc.'),('LAC73892','Asung Trading Inc.'),('AS91490','Asung Trading Inc.'),('PAL04165','Asung Trading Inc.'),('BAB39980','Asung - Edmonton'))
select c.sku, c.warehouse, b.gap as gap_before, coalesce(a.gap, 0) as gap_after
from cells c left join lf1_gap_before b using (sku, warehouse) left join lf1_gap_after a using (sku, warehouse) order by 2, 1;
\echo --- AFTER: PO-01361 · PO-01382 레이어 (기대: PO-01361 line_ref 에 접미어 없음 · AS91603 17280 레이어 없음 · LAC79351~64 레이어 없음)
select doc_number, sku, line_ref, qty, unit_cost, cost_source from inv_layer where doc_number in ('PO-01361') or (doc_number = 'PO-01382' and sku between 'LAC79351' and 'LAC79364') order by 1, 2, 3;
\echo --- AFTER: 평가액(창고별) 전 → 후 · Kim & C 몫
select coalesce(a.warehouse, b.warehouse) as warehouse, b.value as before, a.value as after, a.value - b.value as diff, b.layers as layers_before, a.layers as layers_after
from (select l.warehouse, round(sum(v.remaining_value), 2) as value, count(*) as layers from inv_layer l cross join lateral inv_layer_value(l.id) v where v.remaining_qty > 0 group by 1) a
full join lf1_value_before b using (warehouse) order by 1;
select 'PO-01361' as doc, round(sum(v.remaining_value), 2) as value_after, sum(v.remaining_qty) as qty_after from inv_layer l cross join lateral inv_layer_value(l.id) v where l.doc_number = 'PO-01361';
select (select count(*) from inv_layer) as inv_layer, (select count(*) from inv_layer_consume) as consume, (select count(*) from inv_layer_cost_add) as cost_add;
\echo --- 대기한 포스터 (우리 잠금을 기다리는 세션 · 기대 0)
select pid, usename, application_name, state, wait_event_type, wait_event, now() - xact_start as waiting, left(query, 90) as query
from pg_stat_activity where wait_event_type = 'Lock' and pid <> pg_backend_pid();

-- ── 검산 — 어긋나면 raise → 자동 롤백 ──
do $$
declare v_n int; v_txt text; r jsonb;
begin
  select res into r from lf1_res;
  -- ⓐ skipped_by_event 여덟 키 전부 0 (IMS 가 온전하다는 증거 · §H)
  select string_agg(k || '=' || v, ', ') into v_txt from jsonb_each_text(r -> 'ims' -> 'skipped_by_event') e(k, v) where v::int <> 0;
  if v_txt is not null then raise exception 'MISMATCH ims.skipped_by_event not all zero: %', v_txt; end if;
  -- ⓑ Kim & C 5 · LAC793xx 14 · 893 표본 5 — 실제 창고 gap 0
  select count(*), string_agg(sku || ' ' || gap, ', ') into v_n, v_txt from lf1_gap_after
   where warehouse <> 'IN_TRANSIT' and sku in ('AS91603','AS93280','AS93281','AS93283','AS93284',
     'LAC79351','LAC79352','LAC79353','LAC79354','LAC79355','LAC79356','LAC79357','LAC79358','LAC79359','LAC79360','LAC79361','LAC79362','LAC79363','LAC79364',
     'UNF18054','LAC73892','AS91490','PAL04165','BAB39980');
  if v_n > 0 then raise exception 'MISMATCH target cells still open (%): %', v_n, v_txt; end if;
  -- ⓒ 실제 창고에 남은 칸은 허용 목록뿐 (목록 = 시험에서 까닭을 확인한 칸 · 비어 있으면 0 칸 기대)
  select count(*), string_agg(sku || '@' || warehouse || ' ' || gap, ', ') into v_n, v_txt
    from lf1_gap_after g
   where g.warehouse <> 'IN_TRANSIT'
     and not exists (select 1 from (values
           -- (sku, warehouse, gap) — layer-fix-1 시험 2026-10-31 에서 까닭이 확인된 잔재만. 비어 있다.
           ('', '', 0::numeric)
         ) ok(sku, warehouse, gap) where ok.sku = g.sku and ok.warehouse = g.warehouse and ok.gap = g.gap);
  if v_n > 0 then raise exception 'MISMATCH real-warehouse cells outside allowlist (%): %', v_n, v_txt; end if;
  -- ⓓ IN_TRANSIT 에 레이어가 선 문서는 TR-06396 ~ TR-06399(tf-transit-1 · 가는 중) 뿐 — 시험 실측 4 장 · 609 레이어
  select count(*), string_agg(doc_number, ', ') into v_n, v_txt
    from (select distinct doc_number from inv_layer_open where warehouse = 'IN_TRANSIT') d
   where doc_number not in ('TR-06396', 'TR-06397', 'TR-06398', 'TR-06399');
  if v_n > 0 then raise exception 'MISMATCH unexpected IN_TRANSIT layer docs (%): %', v_n, v_txt; end if;
  raise notice 'CHECK OK — short_events % · cost_unknown_layers % · credit_unknown_layers % · layers_created % · consume_rows % · transfer_layers_created % · elapsed_ms %',
    r ->> 'short_events', r ->> 'cost_unknown_layers', r ->> 'credit_unknown_layers', r ->> 'layers_created', r ->> 'consume_rows', r ->> 'transfer_layers_created', r ->> 'elapsed_ms';
end $$;

select :'mode' = 'apply' as is_apply \gset
\if :is_apply
\echo === COMMIT (mode=apply)
commit;
\else
\echo === ROLLBACK (mode=trial)
rollback;
\endif
