-- hist-3c-check.sql — 당월 출처(bq_current) sale 칸 바로잡기(판정 667) 전후 확인 · ⚠️ 읽기만(begin transaction read only → rollback · commit 없음)
-- 어디서: [테스트 · Asung-IMS] 만 · psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -P pager=off -f docs/probes/hist-3c-check.sql
-- 두 번 쓴다: ① 기준 = 다시 적재 전(2026-10-23 Claude Code) ② 확인 = ilhRedoCurrentSales → ilhLoadSales 뒤(Caleb · 같은 명령) · 두 출력을 나란히 견준다
--   다시 적재 사이에 트랜잭션이 없다(Apps Script 가 REST 로 쓴다) ⇒ 「전과 같다」 는 값의 지문(md5)으로 — C1 의 fingerprint 가 두 출력에서 같아야 한다
--   read only 에서는 create function pg_temp.* · create temp table 이 둘 다 막힌다(실측 2026-10-23) ⇒ 판정은 select 의 case 로 'OK <tag>' / 'MISMATCH <tag>: expected … actual …' 글자를 찍는다
--   별칭: hist_so 와 hist_so_line 은 둘 다 total 칸이 있다 — 조인한 곳은 모든 칸에 표 별칭(42702 방지)
-- 기대(기준 실행 · 2026-10-23 읽기 실측): OK 0 · MISMATCH 3(C3a 61,823 · C3b 61,823 · C4 2,621 — 결함 재현) · C1 10,110 오더 · 206,910 줄 · C2 3,224 · 66,305 · C5 주인 풀림 2,929 · 제품 못 풀림 170 줄 · C6 2,994,402.65 · 336,459.93
-- 기대(확인 실행): OK 3 · MISMATCH 0 · C1 지문 = 기준과 같다 · C2 는 늘 수 있다(새 인보이스 · 판정 659) · C5 풀림은 줄면 안 된다 · C6 은 새 오더 몫만큼만 는다
begin transaction read only;
select 'hist-3c-check' tag, to_char(now() at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI:SS') run_at, current_setting('transaction_read_only') read_only;

-- C1 확정 출처 무변 — 오더 수 · 줄 수 · 지문(concat_ws 는 null 안전 · string_agg 가 줄을 조용히 버리지 않는다)
select 'C1 bq_confirmed' tag, count(distinct h.id) orders, count(l.id) lines,
       md5(string_agg(concat_ws('|', h.order_number, l.seq, l.sku, l.quantity, l.sale, l.total, l.unit_price, l.tax), ',' order by h.order_number, l.seq)) fingerprint
  from public.hist_so h join public.hist_so_line l on l.hist_so_id = h.id
 where h.source = 'bq_confirmed';

-- C2 당월 출처 — 오더 수 · 줄 수 · 지문(참고 · 다시 적재 뒤에는 달라져야 한다)
select 'C2 bq_current' tag, count(distinct h.id) orders, count(l.id) lines,
       md5(string_agg(concat_ws('|', h.order_number, l.seq, l.sku, l.quantity, l.sale, l.total, l.unit_price, l.tax), ',' order by h.order_number, l.seq)) fingerprint
  from public.hist_so h join public.hist_so_line l on l.hist_so_id = h.id
 where h.source = 'bq_current';

-- C3 당월 출처 줄 — sale = total · unit_price = total ÷ quantity(둘 다 0 이어야 한다 · 기준 실행에서는 MISMATCH = 결함 재현)
with c as (
  select count(*) filter (where l.sale is distinct from l.total) n_sale,
         count(*) filter (where l.quantity <> 0 and l.unit_price is distinct from round(l.total / l.quantity, 6)) n_unit
    from public.hist_so h join public.hist_so_line l on l.hist_so_id = h.id
   where h.source = 'bq_current')
select case when c.n_sale = 0 then 'OK C3a bq_current lines sale = total' else 'MISMATCH C3a bq_current lines sale <> total: expected 0 actual ' || c.n_sale end result from c
union all
select case when c.n_unit = 0 then 'OK C3b bq_current lines unit_price = total / quantity' else 'MISMATCH C3b bq_current lines unit_price <> total / quantity: expected 0 actual ' || c.n_unit end from c;

-- C4 hist_so 전부 — sale_total = total(0 이어야 한다 · 기준 실행에서는 bq_current 쪽 MISMATCH)
with c as (
  select count(*) filter (where h.sale_total is distinct from h.total) n_all,
         count(*) filter (where h.sale_total is distinct from h.total and h.source = 'bq_current') n_curr,
         count(*) filter (where h.sale_total is distinct from h.total and h.source = 'bq_confirmed') n_conf
    from public.hist_so h)
select case when c.n_all = 0 then 'OK C4 hist_so sale_total = total' else 'MISMATCH C4 hist_so sale_total <> total: expected 0 actual ' || c.n_all || ' (bq_current ' || c.n_curr || ' · bq_confirmed ' || c.n_conf || ')' end result from c;

-- C5 당월 출처 주인 풀림 · 제품 풀림(다시 적재로 줄면 안 된다 · 늘 수는 있다)
select 'C5 bq_current resolve' tag, count(*) orders, count(h.customer_id) owner_resolved, count(*) - count(h.customer_id) owner_unresolved,
       (select count(*) from public.hist_so h2 join public.hist_so_line l on l.hist_so_id = h2.id where h2.source = 'bq_current' and l.product_id is not null) product_resolved_lines,
       (select count(*) from public.hist_so h2 join public.hist_so_line l on l.hist_so_id = h2.id where h2.source = 'bq_current' and l.product_id is null) product_unresolved_lines
  from public.hist_so h
 where h.source = 'bq_current';

-- C6 당월 출처 tax · total 무변(새 오더가 늘면 그만큼만) · sale_sum 은 다시 적재 뒤 total_sum 과 같아져야 한다
select 'C6 bq_current sums' tag, sum(h.total) total_sum, sum(h.tax_total) tax_sum, sum(h.sale_total) sale_sum,
       (select sum(l.total) from public.hist_so h2 join public.hist_so_line l on l.hist_so_id = h2.id where h2.source = 'bq_current') line_total_sum,
       (select sum(l.tax) from public.hist_so h2 join public.hist_so_line l on l.hist_so_id = h2.id where h2.source = 'bq_current') line_tax_sum
  from public.hist_so h
 where h.source = 'bq_current';
rollback;
