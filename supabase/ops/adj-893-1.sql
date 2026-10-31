-- supabase/ops/adj-893-1.sql — 원장 ≠ Cin7 95 칸 정리: 문서 상쇄 먼저 → 남은 차이만 조정 (판정 893 · adj-893-1 · 2026-10-31)
-- [테스트 · Asung-IMS — Go live 뒤 IMS 메인 · 판정 617] ⚠️ 운영 asung-WMS 에 돌리지 않는다(가드가 막는다)
--
-- 무엇: Cin7 스냅샷 2026-10-30-compare(10-30 01:21 토론토 · 컷) 와 원장(컷 시점)이 어긋난 95 칸(inv_compare 10-30 unknown 109 − LAC793xx 14 · 892 로 끝남)을
--       Cin7 값에 맞춘다. 조정 = Cin7(컷) − 원장(컷) 을 **지금 잔고에 더한다**(컷 뒤 진짜 움직임은 지우지 않는다).
-- 순서(겹침 없이 · 지시서 §2):
--   ① 문서 상쇄 — 원인이 문서로 밝혀진 몫은 그 문서를 되돌린다(source manual · 원래 날짜 · seq · bin · event_type · 부호 반전 · ledger-fix-1(892) 과 같은 꼴):
--      a. 안 닫힌 VOID 조립 13 장(inv_voided_docs resolved_at null · FG-00160 … FG-00197 · 72 줄 · 순액 −452) — 접미어 :voided(스킬 「상쇄 접미어 규칙」 · FG-00140 선례 docs/sessions/2026-10-02-assembly-void-repeat.md §A-3) · resolved_at 기록
--      b. 판매 fulfilment 두 벌 — SO-17868(1724ca9c 13:29 / 826e8819 13:34 · 같은 13 줄 −54) · SO-18094(ac580d9d 10:39 / afea0c40 10:44 · 13 줄 −19) → 뒤 벌(created_at 늦은 TaskID) :reversal
--      c. TR-06125 토론토 bin '' transfer_out 5 줄(PAL · 14:07 · 13:37 의 C0110xx 줄과 이중) → :reversal
--      d. ST-01407 BAB39980 에드먼턴 adjust_existing −1(10-08 14:11 · 같은 날 SO-16806 이 같은 1 개를 뺌) → :reversal
--      e. TR-06397 Z010101 09:17 transfer_out 6 줄(LAC73891 · 73892 · 73893 · 74507 · 74508 · 74509 · 각 −3 · IN_TRANSIT 짝 없음 · Z010101 은 임시 자리) → :reversal · 08:12 A110603 다리는 그대로(tf-transit-1 이 문서로 연다)
--   ② 다시 세기 — ① 을 반영한 원장(컷) 과 Cin7(컷) 을 SKU × 창고 × bin 으로 다시 대조 → 남은 칸만 ③ · ④ 로
--   ③ 남은 음수 칸 — 결함 날짜 manual 줄(음수가 된 날 · seq 1 · event_type adjust_new · raw.line.UnitCost = Cin7 단가 — 재생성(inv_layer_apply_adjust · Cin7 축)이 그 칸을 읽는다)
--   ④ 나머지 — IMS 재고 조정 창구(inv_adjust_create → line_set(delta) → confirm) ADJ 두 장(토론토 · 에드먼턴) · reason count · 레이어 없는 칸은 unit_cost = Cin7 01:21 value ÷ qty
--      bin '' 칸은 KAN64261 에드먼턴 하나뿐 → EU060404 +1(Caleb (나)) · 다른 '' 칸이 남으면 MISMATCH
--   ⑤ 검산 — 95 칸 전부 Cin7 과 같음(SKU × 창고 · bin 따로) · 음수 0 · 손대지 않은 칸 무변 · IN_TRANSIT 무변 · TR-0639x 다리 무변 · Shopify 큐 · LAC 6 SKU bin · WEL04712
-- 안 하는 것: 레이어(inv_layer*)는 ③ 이 건드리지 않는다(④ 의 창구는 실시간처럼 레이어를 세운다) · 재생성 §H 는 A 차수 · TR-06396 ~ 06399 다리 · SO-20003 예약(스크립트 뒤 Caleb 이 Unconfirm → Confirm)
-- 꼴: 마이그레이션 아님 · 함수 아님 · 한 번 · begin/commit 없음(-1 이 한 트랜잭션) · 검산이 하나라도 어긋나면 raise → 전부 되돌아간다.
-- 실행(Caleb · 레포 뿌리에서):
--   미리보기(끝에 rollback · plan csv 만 남는다):
--     psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -v preview=1 -f supabase/ops/adj-893-1.sql > ~/adj-893-1-preview.log 2>&1; echo "exit=$?"
--     → /home/caleb/asung/prompts/adj-893-1-plan.csv (칸별 표 · \copy 는 클라이언트가 쓴다)
--   실행(commit):
--     psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/ops/adj-893-1.sql > ~/adj-893-1.log 2>&1; echo "exit=$?"
--   확인 실행(적용 뒤 · 쓰기 0 · 넣는 문장을 건너뛰고 검산만): -v check=1
-- 되돌리기(적용 뒤): delete from inv_ledger where source = 'manual' and raw ->> 'prompt' = 'adj-893-1';  update inv_voided_docs set resolved_at = null, resolution_note = null where resolution_note like 'adj-893-1%';
--   ④ 의 ADJ 두 장은 되돌리기 없음(판정 53) — 반대 ADJ 로 다시 조정한다. 레이어(④ 가 세운 것)는 §H 재생성이 다시 만든다.
-- 차례: ⓪ 이 DB 확인 → ⓪ 기준(컷 · 95 칸 · Cin7 bin) → ① 상쇄 → ② 다시 세기 → ③ 음수 manual → ④ ADJ → ⑤ 검산 → plan csv → 결과

-- ⓪ 이 DB 확인 (1/2) — supabase/ops/guard-test-only.sql 바이트 복사(md5 8a5ba670298eccd429a496d4f30c1c19 · 26 줄)
do $$
declare
  v_cron   int    := 0;
  v_marker text   := null;
  v_health bigint := 0;
  v_n      bigint;
  v_t      regclass;
begin
  if to_regclass('cron.job') is not null then
    execute 'select count(*) from cron.job where jobname in (''wms-poll-orders'', ''wms-auto-hold'')' into v_cron;
  end if;
  if to_regclass('public.inv_config') is not null then
    execute 'select value from public.inv_config where key = ''db_role''' into v_marker;
  end if;
  foreach v_t in array array[to_regclass('public.wms_health_runs'), to_regclass('wms_legacy.wms_health_runs')] loop
    if v_t is not null then
      execute format('select count(*) from %s', v_t) into v_n;
      v_health := v_health + coalesce(v_n, 0);
    end if;
  end loop;
  if v_cron > 0 or coalesce(v_marker, '') <> 'test' or v_health > 0 then
    raise exception using errcode = 'WM501',
      message = format('STOP - this looks like the production WMS database (cron wms jobs %s, inv_config.db_role %s, wms_health_runs rows %s). WMS-into-IMS migrations run on the test project only (so-module 24). Nothing was changed.',
                       v_cron, coalesce(v_marker, '<missing>'), v_health);
  end if;
end $$;

-- ⓪ 이 DB 확인 (2/2) — po_line(IMS 전용 표)
do $$ begin
  if to_regclass('public.po_line') is null then
    raise exception using errcode = 'WM501', message = 'STOP - not Asung-IMS: po_line missing - this is not the IMS project. Nothing was changed.';
  end if;
end $$;

\if :{?preview}
\echo '[PREVIEW] preview=1 — 끝에 rollback · plan csv 만 남는다'
\endif
\if :{?check}
\echo '[CHECK] check=1 — ① · ③ · ④ 넣기는 건너뛴다 · 검산만(적용 뒤 확인 실행)'
\endif
set local lock_timeout = '3s';
set local statement_timeout = '120s';

create temp table t_res (n int generated always as identity, name text, ok boolean) on commit drop;
create function pg_temp.chk(p_name text, p_ok boolean) returns void language sql as $$ insert into t_res (name, ok) values (p_name, coalesce(p_ok, false)) $$;

-- ═══ ⓪ 기준 — 컷(스냅샷 2026-10-30-compare 의 taken_at) · 95 칸(inv_compare 10-30 unknown − LAC793xx) · Cin7 bin 값 · 원장(컷) bin 값 ═══
select to_char(r.taken_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"') as cut, r.ok as snap_ok
  from public.inv_snapshot_runs r where r.snapshot_key = '2026-10-30-compare' order by r.ran_at desc limit 1 \gset
\echo '⓪ 컷(UTC)' :cut '· 스냅샷 ok' :snap_ok

create temp table t_cells on commit drop as
select c.sku, c.warehouse, c.ledger_qty as cut_qty, c.cin7_qty
  from public.inv_compare c
 where c.checked_on = date '2026-10-30' and c.verdict = 'unknown' and c.sku !~ '^LAC793(5[1-9]|6[0-4])$';
create index on t_cells (sku, warehouse);
select count(*) as cells_n, coalesce(sum(cin7_qty - cut_qty), 0) as cells_diff, coalesce(sum(abs(cin7_qty - cut_qty)), 0) as cells_abs,
       count(*) filter (where cut_qty < 0) as cells_neg from t_cells \gset
\echo '⓪ 95 칸' :cells_n '· 합' :cells_diff '· 절대합' :cells_abs '· 음수' :cells_neg

-- Cin7(컷) bin 값 — 0 인 bin 줄은 스냅샷이 버린다(dropped_zero_nobin) ⇒ 없는 bin = 0
create temp table t_cin7 on commit drop as
select s.sku, s.warehouse, coalesce(s.bin, '') as bin, sum(s.qty) as qty, sum(s.value) as value
  from public.inv_snapshot s join t_cells c on c.sku = s.sku and c.warehouse = s.warehouse
 where s.snapshot_key = '2026-10-30-compare' group by 1, 2, 3;

-- 원장(컷) bin 값 — inv_balance_vs_cin7 와 같은 규칙: 기초 스냅샷 + (manual 이거나 occurred_on < 컷 날짜 이거나 created_at ≤ 컷) · ⚠️ 이 스크립트가 넣는 manual 줄은 뺀다(raw.prompt)
create temp table t_cfg on commit drop as select timestamptz :'cut' as cut;
create function pg_temp.in_cut(p_source text, p_occurred_on date, p_created_at timestamptz) returns boolean language sql stable as
$$ select p_source = 'manual' or p_occurred_on < date '2026-10-30' or p_created_at <= (select cut from t_cfg) $$;
create temp table t_cut on commit drop as
select u.sku, u.warehouse, u.bin, sum(u.qty) as qty
  from (select s.sku, s.warehouse, coalesce(s.bin, '') as bin, s.qty
          from public.inv_snapshot s join t_cells c on c.sku = s.sku and c.warehouse = s.warehouse
         where s.snapshot_key = (select value from public.inv_config where key = 'baseline_snapshot_key')
        union all
        select l.sku, l.warehouse, coalesce(l.bin, ''), l.qty_delta
          from public.inv_ledger l join t_cells c on c.sku = l.sku and c.warehouse = l.warehouse
         where pg_temp.in_cut(l.source, l.occurred_on, l.created_at) and coalesce(l.raw ->> 'prompt', '') <> 'adj-893-1') u
 group by 1, 2, 3;
select count(*) as cut_match
  from t_cells c join (select sku, warehouse, sum(qty) as qty from t_cut group by 1, 2) k on k.sku = c.sku and k.warehouse = c.warehouse and k.qty = c.cut_qty \gset
\echo '⓪ 원장(컷) 다시 센 값 = inv_compare.ledger_qty 인 칸' :cut_match '/' :cells_n

-- 기준값(전) — 손대지 않아야 하는 것들의 지문
select count(*) as pre_ledger from public.inv_ledger \gset
select count(*) as pre_queue from public.shop_stock_queue \gset
select coalesce(sum(qty), 0) as pre_transit from public.inv_balance where warehouse = 'IN_TRANSIT' \gset
select coalesce(md5(string_agg(b.sku || '|' || b.warehouse || '|' || b.bin || '|' || b.qty, ',' order by b.sku, b.warehouse, b.bin)), '(none)') as pre_other_md5
  from public.inv_balance b where b.qty <> 0 and b.warehouse <> 'IN_TRANSIT' and not exists (select 1 from t_cells c where c.sku = b.sku and c.warehouse = b.warehouse) \gset
select count(*) as pre_tr_cin7 from public.inv_ledger where doc_number in ('TR-06396', 'TR-06397', 'TR-06398', 'TR-06399') and source = 'cin7' \gset
select coalesce(md5(string_agg(r.id || '|' || r.qty_allocated || '|' || coalesce(r.released_at::text, ''), ',' order by r.id)), '(none)') as pre_reserve_md5 from public.so_reserve r \gset
select count(*) as pre_voided_open from public.inv_voided_docs where resolved_at is null and doc_type = 'assembly' \gset
select count(*) as pre_adj from public.inv_adjust where note like 'adj-893-1%' \gset
select coalesce(sum(qty), 0) as pre_kan from public.inv_balance where sku = 'KAN64261' and warehouse = 'Asung - Edmonton' and bin = 'EU060404' \gset

\o /dev/null
select pg_temp.chk('⓪ 스냅샷 2026-10-30-compare 회차 ok', :'snap_ok' = 't');
select pg_temp.chk('⓪ 95 칸 · 합 +581 · 절대합 683(미리보기 adj-893-0-preview.csv 와 같다)', :cells_n = 95 and :cells_diff = 581 and :cells_abs = 683);
select pg_temp.chk('⓪ 음수 칸 21(109 안)', :cells_neg = 21);
select pg_temp.chk('⓪ 원장(컷) bin 합 = inv_compare.ledger_qty — 95/95', :cut_match = :cells_n);
select pg_temp.chk('⓪ 안 닫힌 VOID 조립 13 장(check 모드는 0)', case when :{?check} then :pre_voided_open = 0 else :pre_voided_open = 13 end);
select pg_temp.chk('⓪ 이 스크립트의 ADJ 가 아직 없다(check 모드는 2)', case when :{?check} then :pre_adj = 2 else :pre_adj = 0 end);
\o
\if :{?check}
\else
-- 다시 돌리기 방지 — 이미 적용된 DB 에 실행 모드로 또 돌리면 ① · ③ 은 멱등(0 줄)이지만 ④ 가 ADJ 를 또 만들려다 창구에서 거부된다(아래 0 이하) · 여기서 먼저 멈춘다(확인은 -v check=1)
do $$ begin
  if (select count(*) from public.inv_adjust where note like 'adj-893-1%') > 0 then
    raise exception using errcode = 'WM503', message = 'adj-893-1 was already applied on this database (inv_adjust note adj-893-1 exists) - run with -v check=1 to verify. Nothing was changed.';
  end if;
end $$;
\endif

-- ═══ ① 문서 상쇄 — 후보 줄(원행 id) 과 꼬리표 ═══
create temp table t_rev on commit drop as
select e.id, e.doc_type, e.doc_number, e.event_type, e.sku, e.warehouse, coalesce(e.bin, '') as bin, e.line_ref, e.qty_delta, e.occurred_on, e.seq_hint, e.created_at,
       x.tag, x.suffix, x.rule, pg_temp.in_cut(e.source, e.occurred_on, e.created_at) as in_cut
  from public.inv_ledger e
  join (
    -- a. 안 닫힌 VOID 조립 13 장 — 문서째(머리 assemble_in + 구성품 assemble_out) · :voided(스킬 접미어 규칙 · FG-00140 선례)
    select l.id, 'void_fg' as tag, ':voided' as suffix,
           'assembly voided after collection: Cin7 VOIDed the assembly after the ledger had already collected it (inv_voided_docs open). reverse the ledger rows (append-only) — same pattern as FG-00140 (2026-09-29) / 7 docs (2026-10-02)' as rule
      from public.inv_ledger l join public.inv_voided_docs v on v.doc_type = l.doc_type and v.doc_number = l.doc_number
     where (v.resolved_at is null or v.resolution_note like 'adj-893-1%') and v.doc_type = 'assembly' and l.source = 'cin7'   -- check 모드(적용 뒤): 이 스크립트가 닫은 13 장을 다시 찾는다
    union all
    -- b. 판매 fulfilment 두 벌 — 뒤 벌(line_ref 의 TaskID 가 created_at 늦은 쪽) :reversal
    select l.id, 'sale_dup', ':reversal',
           'sale fulfilment collected twice under two TaskIDs (same 13 lines, same bins, same qty): the later-written set is reversed. SO-17868 1724ca9c 13:29 / 826e8819 13:34 · SO-18094 ac580d9d 10:39 / afea0c40 10:44 (2026-10-15 · 10-20 Toronto)'
      from public.inv_ledger l
      join (select doc_number, split_part(line_ref, ':', 1) as task, min(created_at) as first_at
              from public.inv_ledger where doc_number in ('SO-17868', 'SO-18094') and source = 'cin7' and event_type = 'sale_out' group by 1, 2) t
        on t.doc_number = l.doc_number and t.task = split_part(l.line_ref, ':', 1)
      join (select doc_number, max(first_at) as later_at from (select doc_number, split_part(line_ref, ':', 1) as task, min(created_at) as first_at
              from public.inv_ledger where doc_number in ('SO-17868', 'SO-18094') and source = 'cin7' and event_type = 'sale_out' group by 1, 2) q group by 1) m
        on m.doc_number = t.doc_number and m.later_at = t.first_at
     where l.source = 'cin7' and l.event_type = 'sale_out'
    union all
    -- c. TR-06125 토론토 bin '' transfer_out 5 줄(14:07) — 13:37 의 C0110xx 줄과 이중 · '' 쪽 :reversal(⑩-b 와 같은 모양)
    select l.id, 'tr06125_nobin', ':reversal',
           'transfer departure written twice for the same line: once with the bin (C0110xx, 13:37) and once with an empty bin (14:07). reverse the empty-bin set (bin-change double write, same as morning check 10-b)'
      from public.inv_ledger l
     where l.doc_number = 'TR-06125' and l.source = 'cin7' and l.event_type = 'transfer_out' and l.warehouse = 'Asung Trading Inc.' and coalesce(l.bin, '') = ''
    union all
    -- d. ST-01407 BAB39980 에드먼턴 −1(10-08 14:11) — 같은 날 SO-16806 이 같은 1 개를 뺐다 · Cin7 0 · 원장 −1
    select l.id, 'st01407', ':reversal',
           'Cin7 stock adjustment collected on top of the sale that already removed the same unit (SO-16806 2026-10-08): ledger −1 vs Cin7 0. reverse the adjustment row (Caleb 2026-10-31)'
      from public.inv_ledger l
     where l.doc_number = 'ST-01407' and l.source = 'cin7' and l.sku = 'BAB39980' and l.warehouse = 'Asung - Edmonton'
    union all
    -- e. TR-06397 Z010101 09:17 transfer_out 6 줄 — IN_TRANSIT 짝 없음 · 원장 순액 −18 = 6 × −3 · Cin7 Z010101 은 10-23 뒤 0 · Z010101 은 임시 자리(Caleb)
    select l.id, 'tr06397_z', ':reversal',
           'transfer departure written twice for the same line (bin change): 08:12 from A110603 (paired with IN_TRANSIT +3) and 09:17 from Z010101 (no IN_TRANSIT pair; Z010101 is a temporary spot and Cin7 shows 0 there since 10-23). reverse the Z010101 set only; the A110603 leg stays (tf-transit-1 opens TR-0639x as IMS in-transit documents)'
      from public.inv_ledger l
     where l.doc_number = 'TR-06397' and l.source = 'cin7' and l.event_type = 'transfer_out' and l.warehouse = 'Asung Trading Inc.' and l.bin = 'Z010101'
       and l.sku in ('LAC73891', 'LAC73892', 'LAC73893', 'LAC74507', 'LAC74508', 'LAC74509')
       and not exists (select 1 from public.inv_ledger o where o.doc_number = l.doc_number and o.source = 'cin7' and o.event_type = 'transfer_in' and o.warehouse = 'IN_TRANSIT' and o.line_ref = l.line_ref and o.sku = l.sku
                          and o.created_at between l.created_at - interval '2 minutes' and l.created_at + interval '2 minutes')   -- ⚠️ Z010101 에서 정말 나간 다른 30 SKU(IN_TRANSIT 짝 있음)는 잡지 않는다(리허설 1 회차에서 잡혔다)
  ) x on x.id = e.id;
create index on t_rev (sku, warehouse);

\echo '① 상쇄 후보 — 꼬리표별'
select tag, count(*) as rows_n, sum(qty_delta) as net, count(distinct doc_number) as docs, count(*) filter (where in_cut) as in_cut_n, min(occurred_on) as d_min, max(occurred_on) as d_max from t_rev group by tag order by tag;
\echo '① VOID 조립 13 장 — 장마다'
select doc_number, count(*) as rows_n, count(*) filter (where event_type = 'assemble_in') as heads, count(*) filter (where event_type = 'assemble_out') as parts, sum(qty_delta) as net, min(occurred_on) as on_date,
       to_char(min(created_at) at time zone 'America/Toronto', 'MM-DD HH24:MI') as collected_tor, bool_and(in_cut) as in_cut
  from t_rev where tag = 'void_fg' group by doc_number order by doc_number;
\echo '① 판매 두 벌 — 뒤 벌(상쇄할 쪽)'
select doc_number, split_part(line_ref, ':', 1) as task, count(*) as rows_n, sum(qty_delta) as net, to_char(min(created_at) at time zone 'America/Toronto', 'MM-DD HH24:MI') as written_tor from t_rev where tag = 'sale_dup' group by 1, 2 order by 1;

select count(*) as rev_n, coalesce(sum(qty_delta), 0) as rev_net, count(*) filter (where tag = 'void_fg') as rev_fg, count(*) filter (where tag = 'sale_dup') as rev_sale,
       count(*) filter (where tag = 'tr06125_nobin') as rev_tr25, count(*) filter (where tag = 'st01407') as rev_st, count(*) filter (where tag = 'tr06397_z') as rev_trz,
       count(distinct doc_number) filter (where tag = 'void_fg') as rev_fg_docs from t_rev \gset
select count(*) as rev_already from public.inv_ledger r join t_rev s on r.doc_number = s.doc_number and r.line_ref = s.line_ref || s.suffix and r.sku = s.sku and r.warehouse = s.warehouse and coalesce(r.bin, '') = s.bin and r.source = 'manual' \gset
select count(*) as rev_outside from t_rev s where not exists (select 1 from t_cells c where c.sku = s.sku and c.warehouse = s.warehouse) \gset
select count(*) as sale_pairs_bad
  from t_rev s where s.tag = 'sale_dup' and not exists (
    select 1 from public.inv_ledger o where o.doc_number = s.doc_number and o.source = 'cin7' and o.event_type = 'sale_out' and o.id <> s.id
       and split_part(o.line_ref, ':', 2) = split_part(s.line_ref, ':', 2) and o.sku = s.sku and coalesce(o.bin, '') = s.bin and o.qty_delta = s.qty_delta and o.created_at < s.created_at) \gset
select count(*) as tr25_pairs_bad
  from t_rev s where s.tag = 'tr06125_nobin' and not exists (
    select 1 from public.inv_ledger o where o.doc_number = s.doc_number and o.source = 'cin7' and o.event_type = 'transfer_out' and o.line_ref = s.line_ref and o.sku = s.sku and coalesce(o.bin, '') <> '' and o.qty_delta = s.qty_delta and o.created_at < s.created_at) \gset
select count(*) as trz_unpaired
  from t_rev s where s.tag = 'tr06397_z' and exists (
    select 1 from public.inv_ledger o where o.doc_number = s.doc_number and o.source = 'cin7' and o.event_type = 'transfer_in' and o.warehouse = 'IN_TRANSIT' and o.line_ref = s.line_ref and o.sku = s.sku
       and o.created_at between s.created_at - interval '2 minutes' and s.created_at + interval '2 minutes') \gset
\echo '① 후보' :rev_n '줄 · 순액' :rev_net '· 이미 상쇄된 줄' :rev_already '· 95 칸 밖 줄' :rev_outside

\o /dev/null
select pg_temp.chk('① 후보 110 줄 = VOID 72(13 장) + 판매 26 + TR-06125 5 + ST-01407 1 + TR-06397 6', :rev_n = 110 and :rev_fg = 72 and :rev_fg_docs = 13 and :rev_sale = 26 and :rev_tr25 = 5 and :rev_st = 1 and :rev_trz = 6);
select pg_temp.chk('① 후보 순액 −598(상쇄하면 +598)', :rev_net = -598);
select pg_temp.chk('① 아직 상쇄 없음(멱등 — check 모드는 110)', case when :{?check} then :rev_already = 110 else :rev_already = 0 end);
select pg_temp.chk('① 후보는 전부 95 칸 안(밖 0)', :rev_outside = 0);
select pg_temp.chk('① 판매 뒤 벌 26 줄마다 앞 벌에 같은 ProductID · bin · 수량의 짝이 있다', :sale_pairs_bad = 0);
select pg_temp.chk('① TR-06125 '''' 5 줄마다 같은 GUID 의 bin 있는 앞 줄이 있다', :tr25_pairs_bad = 0);
select pg_temp.chk('① TR-06397 Z010101 6 줄은 같은 시각 IN_TRANSIT 짝이 없다', :trz_unpaired = 0);
\o

-- ① 넣기 — ledger-fix-1(892) 과 같은 꼴 · 접미어는 꼬리표대로(:voided / :reversal)
\if :{?check}
select :rev_already as ins1_n, 0 as ins1_net \gset
\else
with ins as (
  insert into public.inv_ledger (doc_type, doc_number, source, event_type, sku, warehouse, bin, line_ref, qty_delta, occurred_on, seq_hint, raw)
  select s.doc_type, s.doc_number, 'manual', s.event_type, s.sku, s.warehouse, s.bin, s.line_ref || s.suffix, -s.qty_delta, s.occurred_on, s.seq_hint,
         jsonb_build_object(
           'rule', s.rule,
           'reason', format('adj-893-0 / adj-893-1 (2026-10-31): inv_compare 2026-10-30 unknown cell %s @ %s — ledger %s / cin7 %s. decision 893 (documents first, then adjust the rest)', s.sku, s.warehouse,
                            (select c.cut_qty from t_cells c where c.sku = s.sku and c.warehouse = s.warehouse), (select c.cin7_qty from t_cells c where c.sku = s.sku and c.warehouse = s.warehouse)),
           'tag', s.tag, 'original_line_ref', s.line_ref, 'original_id', s.id,
           'stale_written_at', to_char(s.created_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
           'in_cut', s.in_cut,
           'prompt', 'adj-893-1', 'decision', 893, 'by', 'caleb', 'at', to_char(public.ims_today(), 'YYYY-MM-DD'))
    from t_rev s
   where not exists (select 1 from public.inv_ledger r where r.doc_number = s.doc_number and r.line_ref = s.line_ref || s.suffix and r.sku = s.sku and r.warehouse = s.warehouse and coalesce(r.bin, '') = s.bin and r.source = 'manual')
  returning qty_delta)
select count(*) as ins1_n, coalesce(sum(qty_delta), 0) as ins1_net from ins \gset
update public.inv_voided_docs v set resolved_at = now(), resolution_note = format('adj-893-1 (decision 893, 2026-10-31): all %s cin7 rows reversed with :voided (source manual)', v.ledger_rows)
 where v.resolved_at is null and v.doc_type = 'assembly' and exists (select 1 from t_rev s where s.tag = 'void_fg' and s.doc_number = v.doc_number);
\endif
\echo '① 넣은 줄' :ins1_n '· 합' :ins1_net

-- ═══ ② 다시 세기 — ① 을 반영한 원장(컷) vs Cin7(컷) · SKU × 창고 × bin ═══
--   ⚠️ 컷 뒤에 수집된 원행(FG-00197 · 10-30 09:13 토론토)의 상쇄는 컷 값에 넣지 않는다(in_cut = false) — 그 둘은 지금 잔고에서 서로 지운다
create temp table t_rem on commit drop as
select coalesce(k.sku, c.sku) as sku, coalesce(k.warehouse, c.warehouse) as warehouse, coalesce(k.bin, c.bin) as bin,
       coalesce(k.qty, 0) as cut_qty, coalesce(f.fix1, 0) as fix1, coalesce(k.qty, 0) + coalesce(f.fix1, 0) as cut_fixed,
       coalesce(c.qty, 0) as cin7_qty, c.value as cin7_value,
       coalesce(c.qty, 0) - (coalesce(k.qty, 0) + coalesce(f.fix1, 0)) as diff
  from t_cut k
  full join t_cin7 c on c.sku = k.sku and c.warehouse = k.warehouse and c.bin = k.bin
  left join (select sku, warehouse, bin, sum(-qty_delta) as fix1 from t_rev where in_cut group by 1, 2, 3) f on f.sku = coalesce(k.sku, c.sku) and f.warehouse = coalesce(k.warehouse, c.warehouse) and f.bin = coalesce(k.bin, c.bin);
create index on t_rem (sku, warehouse);
select count(*) filter (where diff <> 0) as rem_cells, coalesce(sum(diff), 0) as rem_diff, count(*) filter (where diff <> 0 and cut_fixed < 0) as rem_neg,
       count(*) filter (where diff <> 0 and bin = '') as rem_nobin, count(distinct (sku, warehouse)) filter (where diff <> 0) as rem_skuwh,
       count(distinct (sku, warehouse)) filter (where diff = 0 and fix1 <> 0) as fixed_by_1 from t_rem \gset
select count(*) as rem_skuwh_fix1_only from (select sku, warehouse from t_rem group by 1, 2 having sum(diff) = 0 and sum(abs(fix1)) > 0) q \gset
\echo '② ① 뒤 남은 bin 칸' :rem_cells '(SKU × 창고' :rem_skuwh ') · 남은 합' :rem_diff '· 그중 컷 기준 음수' :rem_neg '· bin 없는 칸' :rem_nobin '· ① 만으로 끝난 SKU × 창고' :rem_skuwh_fix1_only
\echo '② 남은 칸 목록(bin)'
select sku, warehouse, bin, cut_qty, fix1, cut_fixed, cin7_qty, diff from t_rem where diff <> 0 order by warehouse desc, sku, bin;

-- ═══ ③ 남은 음수 칸 — 결함 날짜 manual 줄 ═══
--   날짜 = 그 bin 의 누적 잔고가 마지막으로 0 아래로 내려간 줄의 occurred_on(컷 규칙 안의 줄만 · occurred_on · seq_hint · id 순) · seq_hint 1(같은 날 유입 먼저)
--   원가 = Cin7(컷) 그 bin value ÷ qty → 없으면 레이어 가중평균(inv_layer_value) → 없으면 그 SKU 의 마지막 스냅샷(아무 창고 · qty > 0) value ÷ qty
--   event_type adjust_new + raw.line.UnitCost — 재생성(inv_layer_apply_adjust · Cin7 축 · source 무관 · adjust_new 는 raw.line.UnitCost 로 단가를 읽는다)이 이 줄을 원가 있는 레이어로 세운다
create temp table t_neg on commit drop as
with rows as (
  select l.sku, l.warehouse, coalesce(l.bin, '') as bin, l.occurred_on, l.seq_hint, l.id, l.qty_delta,
         sum(l.qty_delta) over (partition by l.sku, l.warehouse, coalesce(l.bin, '') order by l.occurred_on, l.seq_hint, l.id rows unbounded preceding)
           + coalesce((select sum(s.qty) from public.inv_snapshot s where s.snapshot_key = (select value from public.inv_config where key = 'baseline_snapshot_key') and s.sku = l.sku and s.warehouse = l.warehouse and coalesce(s.bin, '') = coalesce(l.bin, '')), 0) as running
    from public.inv_ledger l join t_rem r on r.sku = l.sku and r.warehouse = l.warehouse and r.bin = coalesce(l.bin, '') and r.diff <> 0 and r.cut_fixed < 0
   where pg_temp.in_cut(l.source, l.occurred_on, l.created_at) and coalesce(l.raw ->> 'prompt', '') <> 'adj-893-1'
     and not exists (select 1 from t_rev v where v.id = l.id)                                      -- ① 로 되돌린 원행은 없는 셈
), neg as (
  select sku, warehouse, bin, max(occurred_on) as defect_on
    from (select *, lag(running, 1, 0) over (partition by sku, warehouse, bin order by occurred_on, seq_hint, id) as prev_running from rows) q
   where running < 0 and prev_running >= 0 group by 1, 2, 3
)
select r.sku, r.warehouse, r.bin, r.cut_fixed, r.cin7_qty, r.diff as qty, coalesce(n.defect_on, date '2026-10-29') as defect_on, n.defect_on is not null as date_known,
       case when r.cin7_qty > 0 then round(r.cin7_value / r.cin7_qty, 6) end as cost_cin7,
       (select round(sum(v.remaining_value) / nullif(sum(v.remaining_qty), 0), 6) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = r.sku and y.warehouse = r.warehouse and v.remaining_qty > 0) as cost_layer,
       (select round(s.value / s.qty, 6) from public.inv_snapshot s where s.sku = r.sku and s.qty > 0 and s.value is not null order by s.taken_at desc limit 1) as cost_snap
  from t_rem r left join neg n on n.sku = r.sku and n.warehouse = r.warehouse and n.bin = r.bin
 where r.diff <> 0 and r.cut_fixed < 0;
alter table t_neg add column unit_cost numeric, add column cost_src text;
update t_neg set unit_cost = coalesce(cost_cin7, cost_layer, cost_snap),
                 cost_src = case when cost_cin7 is not null then 'cin7_value' when cost_layer is not null then 'layer_avg' when cost_snap is not null then 'last_snapshot' else 'unknown' end;
\echo '③ 음수 칸 — manual 줄'
select sku, warehouse, bin, cut_fixed, cin7_qty, qty, defect_on, date_known, unit_cost, cost_src from t_neg order by 1, 2, 3;
select count(*) as neg_n, coalesce(sum(qty), 0) as neg_qty, count(*) filter (where not date_known) as neg_nodate, count(*) filter (where unit_cost is null) as neg_nocost, count(*) filter (where bin = '') as neg_nobin from t_neg \gset
select count(*) as neg_already from public.inv_ledger r join t_neg s on r.doc_number = 'MANUAL-893-NEG' and r.sku = s.sku and r.warehouse = s.warehouse and coalesce(r.bin, '') = s.bin and r.source = 'manual' \gset

\o /dev/null
select pg_temp.chk('③ 음수 칸은 전부 날짜를 찾았다(못 찾은 칸 0)', :neg_nodate = 0);
select pg_temp.chk('③ 음수 칸은 전부 원가를 찾았다(없는 칸 0)', :neg_nocost = 0);
select pg_temp.chk('③ 음수 칸에 bin 없는 칸 0', :neg_nobin = 0);
select pg_temp.chk('③ 아직 안 넣음(멱등 — check 모드는 넣은 수)', case when :{?check} then :neg_already = :neg_n else :neg_already = 0 end);
\o

\if :{?check}
select :neg_already as ins3_n, 0 as ins3_qty \gset
\else
with ins as (
  insert into public.inv_ledger (doc_type, doc_number, source, event_type, sku, warehouse, bin, line_ref, qty_delta, occurred_on, seq_hint, amount, raw)
  select 'adjustment', 'MANUAL-893-NEG', 'manual', case when s.qty > 0 then 'adjust_new' else 'adjust_existing' end, s.sku, s.warehouse, s.bin,
         s.sku || '|' || s.warehouse || '|' || s.bin, s.qty, s.defect_on, case when s.qty > 0 then 1 else 2 end, round(s.qty * s.unit_cost, 6),
         jsonb_build_object(
           'rule', 'ledger cell went below zero on this date and Cin7 (snapshot 2026-10-30-compare, 01:21 Toronto) shows it at ' || s.cin7_qty || '; the cause was not found in any document (adj-893-0 cause unknown). manual row on the defect date so the layer rebuild leaves no gap (Caleb (b), 2026-10-31)',
           'reason', format('adj-893-1: cell %s @ %s bin %s — ledger(cut, after document reversals) %s / cin7 %s → %s', s.sku, s.warehouse, s.bin, s.cut_fixed, s.cin7_qty, s.qty),
           'line', jsonb_build_object('UnitCost', s.unit_cost, 'cost_source', s.cost_src),
           'prompt', 'adj-893-1', 'decision', 893, 'by', 'caleb', 'at', to_char(public.ims_today(), 'YYYY-MM-DD'))
    from t_neg s
   where not exists (select 1 from public.inv_ledger r where r.doc_number = 'MANUAL-893-NEG' and r.sku = s.sku and r.warehouse = s.warehouse and coalesce(r.bin, '') = s.bin and r.source = 'manual')
  returning qty_delta)
select count(*) as ins3_n, coalesce(sum(qty_delta), 0) as ins3_qty from ins \gset
\endif
\echo '③ 넣은 줄' :ins3_n '· 합' :ins3_qty

-- ═══ ④ 나머지 — IMS 재고 조정 창구 · ADJ 두 장(토론토 · 에드먼턴) · delta 모드 ═══
create temp table t_lines on commit drop as
select r.sku, r.warehouse, case when r.bin = '' and r.sku = 'KAN64261' and r.warehouse = 'Asung - Edmonton' and r.diff = 1 then 'EU060404' else r.bin end as bin,
       r.bin as bin_orig, r.diff as qty, r.cut_fixed, r.cin7_qty,
       case when r.diff > 0 and r.cin7_qty > 0 then round(r.cin7_value / r.cin7_qty, 6) end as cost_cin7,
       case when r.diff > 0 then (select round(sum(v.remaining_value) / nullif(sum(v.remaining_qty), 0), 6) from public.inv_layer y cross join lateral public.inv_layer_value(y.id) v where y.sku = r.sku and y.warehouse = r.warehouse and v.remaining_qty > 0) end as cost_layer,
       (select b.qty from public.inv_balance b where b.sku = r.sku and b.warehouse = r.warehouse and b.bin = r.bin)
         - coalesce((select sum(e.qty_delta) from public.inv_ledger e join public.inv_adjust a on a.adjust_number = e.doc_number
                      where e.source = 'ims' and e.doc_type = 'adjustment' and a.note like 'adj-893-1%' and e.sku = r.sku and e.warehouse = r.warehouse and coalesce(e.bin, '') = r.bin), 0) as now_qty   -- check 모드: 이 스크립트의 ADJ 가 들어가기 전 잔고
  from t_rem r
 where r.diff <> 0 and not exists (select 1 from t_neg n where n.sku = r.sku and n.warehouse = r.warehouse and n.bin = r.bin);
alter table t_lines add column unit_cost numeric, add column cost_src text;
update t_lines set unit_cost = case when qty > 0 and cost_layer is null then cost_cin7 end,                       -- 레이어 있으면 창구가 가중평균(layer_avg) · 없으면 Cin7 단가(manual)
                   cost_src = case when qty < 0 then 'fifo' when cost_layer is not null then 'layer_avg' when cost_cin7 is not null then 'cin7_value' else 'unknown' end;
\echo '④ ADJ 줄'
select warehouse, sku, bin, bin_orig, qty, cut_fixed, cin7_qty, now_qty, now_qty + qty as after_qty, unit_cost, cost_src from t_lines order by warehouse desc, sku, bin;
select count(*) as l_n, coalesce(sum(qty), 0) as l_qty, count(*) filter (where bin = '') as l_nobin, count(*) filter (where qty > 0 and cost_src = 'unknown') as l_unknown,
       count(*) filter (where now_qty + qty < 0) as l_below0, count(distinct warehouse) as l_wh, count(*) filter (where bin <> bin_orig) as l_rebinned from t_lines \gset
\echo '④ 줄' :l_n '· 합' :l_qty '· bin 없는 줄' :l_nobin '· 원가 unknown' :l_unknown '· 결과 음수' :l_below0 '· 창고' :l_wh '· bin 바꾼 줄(KAN64261)' :l_rebinned

\o /dev/null
select pg_temp.chk('④ bin 없는 줄 0(KAN64261 에드먼턴만 EU060404 로)', :l_nobin = 0 and :l_rebinned = 1);
select pg_temp.chk('④ 늘리는 줄에 원가 unknown 0', :l_unknown = 0);
select pg_temp.chk('④ 결과 음수 줄 0(창구가 거부한다)', :l_below0 = 0);
select pg_temp.chk('④ 창고 둘(토론토 · 에드먼턴)', :l_wh = 2);
\o

create temp table t_adj (warehouse text, adjust_id uuid, adjust_number text, lines int, result jsonb) on commit drop;
\if :{?check}
insert into t_adj select a.warehouse, a.id, a.adjust_number, (select count(*) from public.inv_adjust_line l where l.adjust_id = a.id), null from public.inv_adjust a where a.note like 'adj-893-1%';
\else
grant select on t_lines to authenticated;
grant insert on t_adj to authenticated;
set local role authenticated;
set local request.jwt.claims = '{"sub":"6cb8a5af-0a29-40fd-b225-96c2c7ad6bf7","role":"authenticated","email":"caleb@asung.ca"}';
set local request.jwt.claim.sub = '6cb8a5af-0a29-40fd-b225-96c2c7ad6bf7';
do $$
declare v_wh record; v_l record; v_a jsonb; v_id uuid; v_n int; v_c jsonb;
begin
  for v_wh in select w.id as warehouse_id, w.name from public.ref_warehouse w where exists (select 1 from t_lines l where l.warehouse = w.name) order by w.name desc loop
    v_a := public.inv_adjust_create(v_wh.warehouse_id, format('adj-893-1 · decision 893 · match Cin7 snapshot 2026-10-30 01:21 (Toronto) after document reversals · %s', v_wh.name));
    v_id := (v_a ->> 'id')::uuid; v_n := 0;
    for v_l in select * from t_lines l where l.warehouse = v_wh.name order by l.sku, l.bin loop
      perform public.inv_adjust_line_set(v_id, jsonb_strip_nulls(jsonb_build_object(
        'sku', v_l.sku, 'bin', v_l.bin, 'mode', 'delta', 'qty', v_l.qty::text, 'reason', 'count',
        'note', format('893: ledger(cut) %s → cin7 %s (%s)', v_l.cut_fixed, v_l.cin7_qty, v_l.cost_src),
        'unit_cost', case when v_l.unit_cost is not null then v_l.unit_cost::text end)));
      v_n := v_n + 1;
    end loop;
    v_c := public.inv_adjust_confirm(v_id);
    insert into t_adj values (v_wh.name, v_id, v_a ->> 'adjust_number', v_n, v_c);
  end loop;
end $$;
reset role;
\endif
\echo '④ ADJ'
select warehouse, adjust_number, lines, result -> 'ledger' ->> 'rows_posted' as rows_posted, result -> 'ledger' ->> 'qty_ea_posted' as qty_posted, result ->> 'posted_on' as posted_on from t_adj order by warehouse desc;

-- ═══ ⑤ 검산 ═══
select count(*) as adj_n, coalesce(sum(lines), 0) as adj_lines from t_adj \gset
select count(*) as adj_rows, coalesce(sum(qty_delta), 0) as adj_qty, count(*) filter (where raw -> 'cost' ->> 'cost_source' = 'unknown') as adj_unknown,
       count(*) filter (where (raw -> 'cost' ->> 'short')::int > 0) as adj_short
  from public.inv_ledger e where e.doc_type = 'adjustment' and e.source = 'ims' and e.doc_number in (select adjust_number from t_adj) \gset
select count(*) as adj_confirmed from public.inv_adjust a where a.id in (select adjust_id from t_adj) and a.status = 'confirmed' \gset

-- 최종 대조 — 원장(컷 · ① 중 in_cut 몫 + ③ + ④ 반영) vs Cin7(컷) · bin 단위 · SKU × 창고 단위
create temp table t_final on commit drop as
select coalesce(k.sku, c.sku) as sku, coalesce(k.warehouse, c.warehouse) as warehouse, coalesce(k.bin, c.bin) as bin, coalesce(k.qty, 0) as fixed_cut, coalesce(c.qty, 0) as cin7_qty
  from (select u.sku, u.warehouse, u.bin, sum(u.qty) as qty
          from (select sku, warehouse, bin, qty from t_cut
                union all select s.sku, s.warehouse, s.bin, -s.qty_delta from t_rev s where s.in_cut
                union all select e.sku, e.warehouse, coalesce(e.bin, ''), e.qty_delta from public.inv_ledger e where e.source = 'manual' and e.doc_number = 'MANUAL-893-NEG'
                union all select e.sku, e.warehouse, coalesce(e.bin, ''), e.qty_delta from public.inv_ledger e where e.source = 'ims' and e.doc_type = 'adjustment' and e.doc_number in (select adjust_number from t_adj)) u
         group by 1, 2, 3) k
  full join t_cin7 c on c.sku = k.sku and c.warehouse = k.warehouse and c.bin = k.bin;
select count(*) filter (where f <> c) as fin_bin_bad
  from (select sku, warehouse, case when sku = 'KAN64261' and warehouse = 'Asung - Edmonton' and bin in ('', 'EU060404') then '(nobin→EU060404)' else bin end as bin, sum(fixed_cut) f, sum(cin7_qty) c
          from t_final group by 1, 2, 3) q \gset
-- ↑ KAN64261 에드먼턴은 Cin7 bin '' 1 을 EU060404 에 넣는다(Caleb (나)) — 그 둘을 한 bin 으로 접어 비교
select count(*) as fin_cell_bad from (select sku, warehouse, sum(fixed_cut) f, sum(cin7_qty) c from t_final group by 1, 2 having sum(fixed_cut) <> sum(cin7_qty)) q \gset
select count(*) as fin_neg_now from public.inv_balance b join t_cells c on c.sku = b.sku and c.warehouse = b.warehouse where b.qty < 0 \gset
select count(*) as fin_neg_cut from t_final where fixed_cut < 0 \gset
select count(*) as post_ledger from public.inv_ledger \gset
select count(*) as post_queue from public.shop_stock_queue \gset
select count(distinct q.product_id) as queue_pids from public.shop_stock_queue q where q.id > (select coalesce(max(id), 0) from public.shop_stock_queue) - (:post_queue - :pre_queue) \gset
select coalesce(sum(qty), 0) as post_transit from public.inv_balance where warehouse = 'IN_TRANSIT' \gset
select coalesce(md5(string_agg(b.sku || '|' || b.warehouse || '|' || b.bin || '|' || b.qty, ',' order by b.sku, b.warehouse, b.bin)), '(none)') as post_other_md5
  from public.inv_balance b where b.qty <> 0 and b.warehouse <> 'IN_TRANSIT' and not exists (select 1 from t_cells c where c.sku = b.sku and c.warehouse = b.warehouse) \gset
select count(*) as post_tr_cin7 from public.inv_ledger where doc_number in ('TR-06396', 'TR-06397', 'TR-06398', 'TR-06399') and source = 'cin7' \gset
select count(*) as post_tr_manual from public.inv_ledger where doc_number in ('TR-06396', 'TR-06397', 'TR-06398', 'TR-06399') and source = 'manual' \gset
select coalesce(md5(string_agg(r.id || '|' || r.qty_allocated || '|' || coalesce(r.released_at::text, ''), ',' order by r.id)), '(none)') as post_reserve_md5 from public.so_reserve r \gset
select count(*) as post_voided_open from public.inv_voided_docs where resolved_at is null and doc_type = 'assembly' \gset
select count(*) as post_pairs
  from t_rev s join public.inv_ledger r
    on r.doc_number = s.doc_number and r.line_ref = s.line_ref || s.suffix and r.sku = s.sku and r.warehouse = s.warehouse and coalesce(r.bin, '') = s.bin
   and r.event_type = s.event_type and r.source = 'manual' and r.qty_delta = -s.qty_delta and r.occurred_on = s.occurred_on and r.seq_hint = s.seq_hint
   and r.raw ->> 'original_line_ref' = s.line_ref and (r.raw ->> 'original_id')::bigint = s.id and r.raw ->> 'prompt' = 'adj-893-1' \gset
select count(*) as lac_bad from (
  select b.sku, b.bin, sum(b.qty) q from public.inv_balance b where b.warehouse = 'Asung Trading Inc.' and b.sku in ('LAC73891', 'LAC73892', 'LAC73893', 'LAC74507', 'LAC74508', 'LAC74509') and b.bin in ('A110603', 'Z010101') group by 1, 2) q
 where q.q <> case when q.bin = 'Z010101' then 0 when q.sku = 'LAC73891' then 0 else 3 end \gset
select coalesce(sum(qty), 0) as wel_tor from public.inv_balance where sku = 'WEL04712' and warehouse = 'Asung Trading Inc.' \gset
select coalesce(sum(qty), 0) as post_kan from public.inv_balance where sku = 'KAN64261' and warehouse = 'Asung - Edmonton' and bin = 'EU060404' \gset

\echo '⑤ LAC 6 SKU bin 잔고(기대 A110603: 73891 0 · 나머지 3 · Z010101 0)'
select b.sku, b.bin, b.qty from public.inv_balance b where b.warehouse = 'Asung Trading Inc.' and b.sku in ('LAC73891', 'LAC73892', 'LAC73893', 'LAC74507', 'LAC74508', 'LAC74509') and b.bin in ('A110603', 'Z010101') order by 1, 2;
\echo '⑤ 95 칸 지금 잔고 vs Cin7(컷) — 차이는 컷 뒤 진짜 움직임(0 이 아니어도 정상 · 참고)'
select count(*) filter (where b.q <> c.cin7_qty) as cells_moved_since_cut from t_cells c join (select sku, warehouse, sum(qty) q from public.inv_balance group by 1, 2) b on b.sku = c.sku and b.warehouse = c.warehouse;
\echo '⑤ Shopify 큐에 선 줄' :post_queue '−' :pre_queue '· 제품' :queue_pids

\o /dev/null
select pg_temp.chk('① 넣은 줄 110(check 모드는 이미 있던 110) · 합 +598', :ins1_n = 110 and (case when :{?check} then true else :ins1_net = 598 end));
select pg_temp.chk('① 원행 110 줄 모두 선례 꼴의 짝이 하나씩(창고 · bin · 날짜 · seq · 부호 반전 · raw original_id)', :post_pairs = 110);
select pg_temp.chk('① inv_voided_docs 조립 열린 것 0(13 장 resolved)', :post_voided_open = 0);
select pg_temp.chk('③ 넣은 줄 = 음수 칸 수', :ins3_n = :neg_n and (case when :{?check} then true else :ins3_qty = :neg_qty end));
select pg_temp.chk('④ ADJ 두 장 confirmed · 줄 수 = 후보 줄 수 · 원장 ims 줄 수 = 줄 수 · 합 = 후보 합', :adj_n = 2 and :adj_confirmed = 2 and :adj_lines = :l_n and :adj_rows = :l_n and :adj_qty = :l_qty);
select pg_temp.chk('④ ADJ 늘리는 줄 원가 unknown 0 · 줄이는 줄 FIFO short 0', :adj_unknown = 0 and :adj_short = 0);
select pg_temp.chk('⑤ 95 칸 전부 Cin7(컷) 과 같다 — bin 단위(어긋난 bin 0)', :fin_bin_bad = 0);
select pg_temp.chk('⑤ 95 칸 전부 Cin7(컷) 과 같다 — SKU × 창고 단위(어긋난 칸 0)', :fin_cell_bad = 0);
select pg_temp.chk('⑤ 95 칸 컷 기준 음수 bin 0 · 지금 잔고 음수 칸 0', :fin_neg_cut = 0 and :fin_neg_now = 0);
select pg_temp.chk('⑤ 손대지 않은 칸(95 밖 · IN_TRANSIT 밖) 잔고 무변', :'pre_other_md5' = :'post_other_md5');
select pg_temp.chk('⑤ IN_TRANSIT 잔고 무변', :pre_transit = :post_transit);
select pg_temp.chk('⑤ TR-06396 ~ 06399 cin7 다리 무변 · manual 은 Z010101 6 줄뿐', :pre_tr_cin7 = :post_tr_cin7 and :post_tr_manual = 6);
select pg_temp.chk('⑤ LAC 6 SKU: A110603 0(73891) · 3(나머지) · Z010101 0', :lac_bad = 0);
select pg_temp.chk('⑤ WEL04712 토론토 0 · so_reserve 무변(SO-20003 은 Caleb 이 §4)', :wel_tor = 0 and :'pre_reserve_md5' = :'post_reserve_md5');
select pg_temp.chk('⑤ KAN64261 에드먼턴 EU060404 = 전 + 1(check 모드는 무변) · bin '''' 은 0', (case when :{?check} then :post_kan = :pre_kan else :post_kan = :pre_kan + 1 end) and (select coalesce(sum(qty), 0) from public.inv_balance where sku = 'KAN64261' and warehouse = 'Asung - Edmonton' and bin = '') = 0);
select pg_temp.chk('⑤ 원장 줄 수 = 전 + ① + ③ + ④(check 모드는 + 0)', case when :{?check} then :post_ledger = :pre_ledger else :post_ledger = :pre_ledger + :ins1_n + :ins3_n + :adj_rows end);
\o

-- ═══ plan csv — 칸별 표(Caleb 이 실행 전에 본다) ═══
create temp table t_plan on commit drop as
select f.sku, f.warehouse, f.bin,
       coalesce(k.qty, 0) as ledger_cut, f.cin7_qty as cin7,
       coalesce(r.fix1, 0) as fix1_docs,
       coalesce((select sum(qty_delta) from public.inv_ledger e where e.source = 'manual' and e.doc_number = 'MANUAL-893-NEG' and e.sku = f.sku and e.warehouse = f.warehouse and coalesce(e.bin, '') = f.bin), 0) as fix3_manual,
       coalesce((select sum(qty_delta) from public.inv_ledger e where e.source = 'ims' and e.doc_type = 'adjustment' and e.doc_number in (select adjust_number from t_adj) and e.sku = f.sku and e.warehouse = f.warehouse and coalesce(e.bin, '') = f.bin), 0) as fix4_adj,
       case when coalesce(r.fix1, 0) <> 0 then (select string_agg(distinct v.tag || ' ' || v.doc_number, ' ; ') from t_rev v where v.in_cut and v.sku = f.sku and v.warehouse = f.warehouse and v.bin = f.bin) end as fix1_docs_list,
       case when exists (select 1 from t_neg n where n.sku = f.sku and n.warehouse = f.warehouse and n.bin = f.bin) then 'manual_defect_date'
            when exists (select 1 from t_lines l where l.sku = f.sku and l.warehouse = f.warehouse and l.bin = f.bin and l.bin <> l.bin_orig) then 'adj (nobin → this bin)'
            when exists (select 1 from t_lines l where l.sku = f.sku and l.warehouse = f.warehouse and l.bin_orig = f.bin and l.bin <> l.bin_orig) then 'adj (moved to ' || (select l.bin from t_lines l where l.sku = f.sku and l.warehouse = f.warehouse and l.bin_orig = f.bin) || ')'
            when exists (select 1 from t_lines l where l.sku = f.sku and l.warehouse = f.warehouse and l.bin_orig = f.bin) then 'adj'
            when coalesce(r.fix1, 0) <> 0 then 'docs_only' else '(no change)' end as route,
       coalesce((select n.defect_on::text from t_neg n where n.sku = f.sku and n.warehouse = f.warehouse and n.bin = f.bin),
                (select (a.result ->> 'posted_on') from t_adj a join t_lines l on l.warehouse = a.warehouse where l.sku = f.sku and l.warehouse = f.warehouse and l.bin_orig = f.bin limit 1)) as fix_date,
       coalesce((select n.unit_cost::text || ' ' || n.cost_src from t_neg n where n.sku = f.sku and n.warehouse = f.warehouse and n.bin = f.bin),
                (select coalesce(l.unit_cost::text, '') || ' ' || l.cost_src from t_lines l where l.sku = f.sku and l.warehouse = f.warehouse and l.bin_orig = f.bin)) as cost,
       f.fixed_cut as after_cut, (select b.qty from public.inv_balance b where b.sku = f.sku and b.warehouse = f.warehouse and b.bin = f.bin) as now_after
  from t_final f
  left join t_cut k on k.sku = f.sku and k.warehouse = f.warehouse and k.bin = f.bin
  left join (select sku, warehouse, bin, sum(-qty_delta) as fix1 from t_rev where in_cut group by 1, 2, 3) r on r.sku = f.sku and r.warehouse = f.warehouse and r.bin = f.bin;
\copy (select * from t_plan order by warehouse desc, sku, bin) to '/home/caleb/asung/prompts/adj-893-1-plan.csv' csv header
\echo 'plan csv → /home/caleb/asung/prompts/adj-893-1-plan.csv'
\echo 'plan 합계 — route 별'
select route, count(*) as bins, sum(fix1_docs) as fix1, sum(fix3_manual) as fix3, sum(fix4_adj) as fix4, sum(cin7 - ledger_cut) as total_diff from t_plan group by route order by route;
select count(*) as bins, sum(fix1_docs) as fix1, sum(fix3_manual) as fix3, sum(fix4_adj) as fix4, sum(cin7 - ledger_cut) as total_diff, sum(abs(cin7 - ledger_cut)) as total_abs from t_plan;

-- ═══ 결과 ═══
\echo '⑤ 검산'
select n, case when ok then 'OK' else 'MISMATCH' end as verdict, name from t_res order by n;
select count(*) filter (where ok) as ok_n, count(*) filter (where not ok) as bad_n, count(*) as all_n from t_res \gset
\echo '⑤ OK' :ok_n '/' :all_n '· MISMATCH' :bad_n
\if :{?preview}
\echo '[PREVIEW] 끝 — rollback(아무것도 남지 않는다 · plan csv 만)'
rollback;
\else
do $$ begin
  if (select count(*) from t_res where not ok) > 0 then
    raise exception using errcode = 'WM502', message = format('adj-893-1: %s check(s) MISMATCH - nothing is kept (transaction rolls back)', (select count(*) from t_res where not ok));
  end if;
end $$;
\echo 'adj-893-1 끝 — 검산 전부 OK (다음: Caleb → SO-20003 Unconfirm → Confirm · Shopify 큐 확인)'
\endif
