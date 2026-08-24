-- inv_compare_run 로컬 기능 테스트 (2026-08-24 · ⑥ shadow 대조)
--
-- 실행 (로컬 supabase — 프로덕션 금지):
--   supabase db reset
--   psql "postgresql://postgres:postgres@127.0.0.1:54322/postgres" -f supabase/tests/inv_compare_run_test.sql
--
-- 전체가 한 트랜잭션이고 마지막에 ROLLBACK — 로컬 DB 에 아무것도 남기지 않는다.
-- 전부 통과하면 마지막 NOTICE 가 "ALL 6 TESTS PASSED".

begin;

do $test$
declare
  res jsonb;
  n int; t text; d numeric;
begin
  -- ── 셋업: 기준선(-initial) + 오늘 compare 스냅샷 + 원장 사건 ──
  insert into inv_snapshot (snapshot_key, taken_at, sku, warehouse, bin, qty) values
    ('2026-08-20-initial', now() - interval '4 days', 'SKU-X', 'Asung Trading Inc.', 'A01', 60),
    ('2026-08-20-initial', now() - interval '4 days', 'SKU-X', 'Asung Trading Inc.', 'A02', 40),  -- bin 접기 → 100
    ('2026-08-20-initial', now() - interval '4 days', 'SKU-Y', 'Asung Trading Inc.', 'B01', 50),
    ('2026-08-20-initial', now() - interval '4 days', 'SKU-Z', 'Asung - Edmonton',   'E01', 10);
  insert into inv_snapshot (snapshot_key, taken_at, sku, warehouse, bin, qty) values
    ('2026-08-24-compare', now(), 'SKU-X', 'Asung Trading Inc.', 'A01', 90),   -- 원장 100-10=90 → match
    ('2026-08-24-compare', now(), 'SKU-Y', 'Asung Trading Inc.', 'B01', 50),   -- 무사건 → match
    ('2026-08-24-compare', now(), 'SKU-Z', 'Asung - Edmonton',   'E01', 15),   -- 원장 10 → unknown(diff -5)
    ('2026-08-24-compare', now(), 'SKU-N', 'Asung Trading Inc.', 'C01', 7);    -- 원장에 없음 → unknown(diff -7)
  insert into inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, line_ref, source)
  values (current_date, 2, 'SKU-X', 'Asung Trading Inc.', '', -10, 'sale_out',    'sale',     'SO-TEST-1', 'T1:P1', 'cin7'),
         (current_date, 1, 'SKU-T', 'IN_TRANSIT',         '',   5, 'transfer_in', 'transfer', 'TR-TEST-1', 'P2',    'cin7');

  -- ── ⓐ 본 실행: verdict 분포·기록 행 ─────────────────────────────────
  res := inv_compare_run('2026-08-24-compare');
  if res->>'ok' <> 'true' then raise exception 'FAIL a1: %', res; end if;
  if (res->>'compared_pairs')::int <> 4 then raise exception 'FAIL a2: pairs=%', res->>'compared_pairs'; end if;
  if (res->>'match')::int <> 2 then raise exception 'FAIL a3: match=%', res->>'match'; end if;
  if (res->>'explained')::int <> 1 then raise exception 'FAIL a4: explained=%', res->>'explained'; end if;
  if (res->>'unknown')::int <> 2 then raise exception 'FAIL a5: unknown=%', res->>'unknown'; end if;
  if res->>'baseline_key' <> '2026-08-20-initial' then raise exception 'FAIL a6: baseline=%', res->>'baseline_key'; end if;
  raise notice 'PASS a — verdict 분포 (pairs 4 · match 2 · explained 1 · unknown 2)';

  -- ── ⓑ inv_compare 에는 diff≠0 만 (match 행 없음) + generated diff 검증 ──
  select count(*) into n from inv_compare where checked_on = current_date;
  if n <> 3 then raise exception 'FAIL b1: rows=% (want 3 — Z,N unknown + IN_TRANSIT explained)', n; end if;
  select count(*) into n from inv_compare where checked_on = current_date and verdict = 'match';
  if n <> 0 then raise exception 'FAIL b2: match rows written'; end if;
  select diff into d from inv_compare where checked_on = current_date and sku = 'SKU-Z';
  if d <> -5 then raise exception 'FAIL b3: SKU-Z diff=% (want -5 = ledger 10 - cin7 15)', d; end if;
  select verdict||'/'||coalesce(note,'') into t from inv_compare
   where checked_on = current_date and warehouse = 'IN_TRANSIT';
  if t not like 'explained/IN_TRANSIT synthetic%' then raise exception 'FAIL b4: %', t; end if;
  raise notice 'PASS b — diff≠0 만 기록 · generated diff · IN_TRANSIT explained+note';

  -- ── ⓒ runs 기록: 카운트·샘플·cursors ──────────────────────────────
  select count(*) into n from inv_compare_runs where snapshot_key = '2026-08-24-compare';
  if n <> 1 then raise exception 'FAIL c1: runs=%', n; end if;
  select jsonb_array_length(unknown_sample) into n from inv_compare_runs
   where snapshot_key = '2026-08-24-compare' order by id desc limit 1;
  if n <> 2 then raise exception 'FAIL c2: sample=%', n; end if;
  -- cursors 는 jsonb 객체(빈 sync_state 면 {}) — null 이면 실패
  select count(*) into n from inv_compare_runs
   where snapshot_key = '2026-08-24-compare' and cursors is not null;
  if n <> 1 then raise exception 'FAIL c3: cursors null'; end if;
  raise notice 'PASS c — runs 1행 · unknown_sample 2 · cursors 기록';

  -- ── ⓓ 같은 날 재실행 멱등 (delete 후 재삽입 — 행 수 불변·runs 는 누적) ──
  res := inv_compare_run('2026-08-24-compare');
  if res->>'ok' <> 'true' then raise exception 'FAIL d1: %', res; end if;
  select count(*) into n from inv_compare where checked_on = current_date;
  if n <> 3 then raise exception 'FAIL d2: rerun rows=% (want 3 — no dup)', n; end if;
  select count(*) into n from inv_compare_runs where snapshot_key = '2026-08-24-compare';
  if n <> 2 then raise exception 'FAIL d3: runs=% (want 2)', n; end if;
  raise notice 'PASS d — 재실행 멱등 (compare 3행 유지 · runs 누적)';

  -- ── ⓔ 가드: 없는 스냅샷 키 → 기록만 남기고 ok:false ─────────────────
  res := inv_compare_run('2026-01-01-compare');
  if res->>'ok' <> 'false' then raise exception 'FAIL e1: %', res; end if;
  select note into t from inv_compare_runs where snapshot_key = '2026-01-01-compare';
  if t not like 'no snapshot rows%' then raise exception 'FAIL e2: %', t; end if;
  raise notice 'PASS e — 스냅샷 없음 가드 (오탐 0 · 기록만)';

  -- ── ⓕ 보존 정리: 14일 지난 compare 는 삭제 · -initial 불가침 ─────────
  insert into inv_snapshot (snapshot_key, taken_at, sku, warehouse, bin, qty)
  values ('2026-08-01-compare', now() - interval '20 days', 'SKU-OLD', 'Asung Trading Inc.', '', 1),
         ('2026-07-01-initial', now() - interval '50 days', 'SKU-OLD', 'Asung Trading Inc.', '', 1);
  res := inv_compare_run('2026-08-24-compare');
  select count(*) into n from inv_snapshot where snapshot_key = '2026-08-01-compare';
  if n <> 0 then raise exception 'FAIL f1: old compare snapshot not reaped'; end if;
  select count(*) into n from inv_snapshot where snapshot_key = '2026-07-01-initial';
  if n <> 1 then raise exception 'FAIL f2: -initial snapshot was DELETED — 불가침 위반'; end if;
  -- ⚠️ 부수 확인: 낡은 -initial 이 하나 더 생겨도 기준선은 "최신 taken_at" 을 쓴다
  if res->>'baseline_key' <> '2026-08-20-initial' then raise exception 'FAIL f3: baseline=%', res->>'baseline_key'; end if;
  raise notice 'PASS f — 14일 reap · -initial 불가침 · 최신 기준선 선택';

  raise notice '════ ALL 6 TESTS PASSED ════';
end
$test$;

rollback;
