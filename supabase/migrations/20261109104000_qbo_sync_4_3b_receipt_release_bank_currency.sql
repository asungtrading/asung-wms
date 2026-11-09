-- supabase/migrations/20261109104000_qbo_sync_4_3b_receipt_release_bank_currency.sql — qbo-sync-4-3b: 입고 보류 풀기 · 원가 장 CADJ 계정 · 은행 계좌 통화 · 결제 통화 막기 (2026-11-09 · 지시서 ~/asung/prompts/qbo-sync-4-3.md E · F · §0 이견 1 · 14 · 15 · 정본 so-module §108-a 판정 1119 ~ 1122 · qbo-integration §15-l)
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261109104000 --yes · supabase db push 금지 · ⚠️ po_payment 트리거 생성 · ref_account 갱신 — 토론토 08:30 전 또는 17:00 뒤
-- E(1119 · 1120 · 1121): qbo_cost_expected 재발행 — RCV(purchase 레이어) hold → send(무조건 · 날짜 = received_on) · CADJ 대 계정 GINR · price_adjust send · settlement_discount hold(4-5) · 그 밖 22 칸 규칙 무변 · 「모르는 원가 칸이면 막는다」 그대로
--   · 이미 built 된 장(TOR 11-05 · 11-06 pending)은 줄이 claim 때 굳으므로(§15-j ⬜2) 새 셈을 따른다 · epoch(inv_layer_consume) 무변 → 재생성 hold 없음 · Release 불필요 · built_hold_keys(1 · 2)는 만들 때 수 — 낡은 표시(화면 안내 거리)
--   · 차례(1120): TOR 은 11-02 ~ 11-04 를 먼저 보내고 11-05 부터(RCV-00117 950.00 · RCV-00121 12,039.53 이 그 장에 든다) · EDM 은 다
-- F(1122): ref_account.currency_code = USD — 확정 2(4-1 R4: _106_ BMO USD CHEQUING · _138_ MTFX USD) + 이름으로 4(_141_ TD USD CHEQUING · _144_ BMO USD Mastercard · _145_ Cash on hand_USD · _204_ WISE USD · ⚠️ 짐작 = 이름 · qbo_entity Account detail 이 비어 QBO 통화를 못 셌다 · 빼려면 아래 c_usd 목록에서) · 결제 통화 ≠ 계좌 통화면 po_payment 저장 거부(지연 제약 트리거 · 1091 꼴 · 계정 없으면 통과) · 기존 결제 4(USD 셋 _138_ · CAD 하나 _104_)는 안 걸린다(적용 안에서 센다)
-- 하지 않는 것: 1124(섞인 공급처 결제 거부) · 1123(결제 환율) · 1125(BillPayment void) = 4-5 · EF · 화면 · cron 무변 · 새 표 0 · FK 0
-- 재발행 하나(원본 = DB prosrc · 2026-11-09): qbo_cost_expected 13a88caf — 끼운 줄만(RCV 넷 · CADJ 넷) · ACL 그대로(service_role)
-- 검증 supabase/tests/qbo_sync_4_3b_check.sql(운영 메인 begin → rollback · 가짜 재료만 · 실제 RCV 두 줄은 읽기만) · 적용은 Caleb

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

-- ═══════════════ ⓪ 재발행 원본 가드 — qbo_cost_expected md5 · 3-1 통화 칸 · 아직 미적용 ═══════════════
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected') is distinct from '13a88caf9f6dfd667c0665c61cab2e38' then v_bad := v_bad || ' qbo_cost_expected'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'qbo_cost_expected') <> 1 then v_bad := v_bad || ' (qbo_cost_expected is not unique)'; end if;
  if to_regprocedure('public.ims_account_currency(uuid)') is null or to_regprocedure('public.ims_account_currency_msg(text, text, text, text, text, text)') is null
     or not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ref_account' and column_name = 'currency_code') then v_bad := v_bad || ' (3-1 missing)'; end if;
  if exists (select 1 from pg_trigger where tgname = 'po_payment_account_currency_ck') or to_regprocedure('public.po_payment_account_currency_check()') is not null then v_bad := v_bad || ' (4-3b already applied?)'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══════════════ ① E — qbo_cost_expected 재발행(DB prosrc 그대로 + 끼운 줄 · 서명 · definer · search_path · ACL 그대로) ═══════════════
CREATE OR REPLACE FUNCTION public.qbo_cost_expected(p_until date, p_since date DEFAULT NULL::date, p_realm text DEFAULT NULL::text)
 RETURNS TABLE(wh_code text, key_kind text, doc_key text, acct_a text, acct_b text, cents bigint, raw_amount numeric, status text, reason text, entity_customer_id uuid, first_on date, last_on date, n_events integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_since   date := coalesce(p_since, (select nullif(btrim(c.value), '')::date from public.inv_config c where c.key = 'qbo_cost_since'));
  v_realm   text := coalesce(p_realm, (select c.realm_id from public.qbo_connection c where c.singleton));
  v_thr     numeric := coalesce((select nullif(btrim(c.value), '')::numeric from public.inv_config c where c.key = 'qbo_cost_adjust_hold_over'), 1000);
  v_adj_def text := (select nullif(btrim(c.value), '') from public.inv_config c where c.key = 'inv_adjust_default_account_code');
  v_excl    text[] := public.qbo_cost_excluded_docs();
  c_inv     constant text := '_59_';
  c_transit constant text := '_1150040007_';
  c_cogs    constant text := '_58_';
  c_ginr    constant text := '_1150040012_';
begin
  if p_until is null then raise exception 'p_until is required — nothing was read'; end if;
  if v_since is null then raise exception 'inv_config qbo_cost_since is not set — a migration sets it — nothing was read'; end if;
  if v_adj_def is null then raise exception 'inv_config inv_adjust_default_account_code is not set — a migration sets it — nothing was read'; end if;
  return query
  with scope as (select distinct g.doc_number as d from public.inv_ledger g where g.source = 'ims'),
  fix as (select 'adj:' || a.id::text as lr from public.inv_cost_adjust a where a.kind = 'opening_fix'),
  -- ── 소진 ──
  -- ⚠️ cons_raw 는 materialized — planner 가 이 필터를 4 행으로 짐작해 inv_layer 38k 행을 바깥에 두고 7k × 38k 를 돌렸다(실측 35 s) · 먼저 굳히면 소진 7k 행마다 PK 조회(0.3 s)
  cons_raw as materialized (
    select c.id as cid, c.layer_id as clid, c.doc_type as cdt, c.doc_number as cdoc, c.line_ref as clr, c.reason as crs, c.occurred_on as con, c.amount as camt, c.split_basis as csb,
           (c.doc_number = any (v_excl)) as is_excl, (c.line_ref in (select f.lr from fix f)) as is_fix
    from public.inv_layer_consume c
    where c.occurred_on between v_since and p_until
      and (c.doc_number in (select s.d from scope s) or c.doc_number = any (v_excl) or c.line_ref in (select f.lr from fix f)
           or (c.doc_type = 'cost' and exists (select 1 from public.po_charge pc where pc.charge_number = c.doc_number)))
  ),
  cons as (
    select c.cid, c.cdt, c.cdoc, c.clr, c.crs, c.con, c.camt, c.csb, c.is_excl, c.is_fix,
           l.id as lid, l.warehouse as lwh, case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode
    from cons_raw c join public.inv_layer l on l.id = c.clid
  ),
  ev_cons as (
    -- sale → SO · 차 #58 / 대 #59(창고)
    select x.lcode as e_wh, 'SO' as e_kind, x.cdoc as e_key, c_cogs as e_dr, x.lacct as e_cr, x.camt as e_amt, x.con as e_on,
           case when x.is_excl then 'excluded' when x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end as e_status,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end as e_reason
    from cons x where x.crs = 'sale'
    union all
    -- reversal(크레딧 취소) → CR · 차 #58 / 대 #59
    select x.lcode, 'CR', x.cdoc, c_cogs, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'reversal'
    union all
    -- adjust_out → ADJ · 차 조정 계정(inv_adjust_account · 1087) / 대 #59
    select x.lcode, 'ADJ', x.cdoc, aa.code, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null or aa.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when aa.code is null then 'adjustment ' || x.cdoc || ' not found (account unknown)' end
    from cons x left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = x.cdoc) aa on true
    where x.crs = 'adjust_out'
    union all
    -- transfer 출발(보낸 창고 레이어) → TRF · 차 In Transit / 대 #59
    select x.lcode, 'TRF', x.cdoc, c_transit, c_inv, x.camt, x.con,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'transfer' and x.lwh <> 'IN_TRANSIT'
    union all
    -- transfer 도착(IN_TRANSIT 레이어 소진 → 받는 창고의 장) → TRF · 차 #59 / 대 In Transit
    select tw.code, 'TRF', x.cdoc, c_inv, c_transit, x.camt, x.con,
           case when x.is_excl then 'excluded' when tw.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when tw.code is null then 'receiving warehouse unknown for transfer ' || x.cdoc end
    from cons x left join lateral (select public.qbo_cost_wh_code(w.name) as code from public.inv_transfer t join public.ref_warehouse w on w.id = t.to_warehouse_id where t.transfer_number = x.cdoc) tw on true
    where x.crs = 'transfer' and x.lwh = 'IN_TRANSIT'
    union all
    -- cost_late → items 로 나눈다: sale 몫 → SO · 차 #58(1084) / 대 #59 · adjust_out · lost 몫 → ADJ · 차 그 조정 계정(1095) / 대 #59 · 그 밖 → block
    select x.lcode,
           case when it->>'reason' = 'sale' then 'SO' when it->>'reason' in ('adjust_out', 'lost') then 'ADJ' else 'cost_late' end,
           coalesce(it->>'doc_number', x.cdoc),
           case when it->>'reason' = 'sale' then c_cogs when it->>'reason' in ('adjust_out', 'lost') then ia.code else null end,
           x.lacct,
           case when coalesce(sh.tot, 0) > 0 then x.camt * (it->>'share')::numeric / sh.tot else x.camt end,
           x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' when it->>'reason' = 'sale' then 'send' when it->>'reason' in ('adjust_out', 'lost') and ia.code is not null then 'send' else 'block' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text
                when it->>'reason' = 'sale' then null when it->>'reason' in ('adjust_out', 'lost') and ia.code is not null then null
                else 'late cost ' || x.cdoc || ' has an item of kind ' || coalesce(it->>'reason', '?') || ' — not mapped' end
    from cons x
    cross join lateral (select coalesce(sum((i->>'share')::numeric), 0) as tot from jsonb_array_elements(coalesce(x.csb->'items', '[]'::jsonb)) i) sh
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x.csb->'items') = 'array' and jsonb_array_length(x.csb->'items') > 0 then x.csb->'items' else '[{"reason":"no_items"}]'::jsonb end) it
    left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = it->>'doc_number' and it->>'reason' in ('adjust_out', 'lost')) ia on true
    where x.crs = 'cost_late'
    union all
    -- cost_moved → 자식(트랜스퍼) 레이어의 창고 계정 ↔ 제 계정 · 같으면 0(줄 없음) · 자식 창고가 둘이거나 없으면 block
    select x.lcode, case when x.cdt = 'cost' then 'CHG' else 'TRF' end, x.cdoc,
           case when ch.n = 1 then ch.acct else x.lacct end, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null or ch.n <> 1 then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when ch.n <> 1 then 'moved cost ' || x.cdoc || ' has ' || ch.n::text || ' child warehouses (expected 1)' end
    from cons x
    cross join lateral (select count(distinct y.warehouse) as n, min(case when y.warehouse = 'IN_TRANSIT' then c_transit else c_inv end) as acct from public.inv_layer y where y.parent_layer_id = x.lid and y.origin_type = 'transfer') ch
    where x.crs = 'cost_moved'
    union all
    -- assembly_in → FG · 같은 창고 #59 ↔ #59 = 0(줄 없음 · 값 차이는 아래 asm_check 가 막는다)
    select x.lcode, 'FG', x.cdoc, x.lacct, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'assembly_in'
    union all
    -- lost → 막음(deferred 512) · 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.crs, x.cdoc, x.lacct, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' else 'block' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.crs = 'lost' then 'consume reason lost on ' || x.cdoc || ' — meaning not decided (deferred 512)' else 'consume reason ' || x.crs || ' on ' || x.cdoc || ' — not in the 22 cells' end
    from cons x where x.crs not in ('sale', 'reversal', 'adjust_out', 'transfer', 'cost_late', 'cost_moved', 'assembly_in')
  ),
  -- ── 레이어(생김) ──
  lay as (
    select l.id as lid, l.origin_type as lor, l.doc_number as ldoc, l.received_on as lon, l.qty * l.unit_cost as lamt, l.warehouse as lwh,
           case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode, (l.doc_number = any (v_excl)) as is_excl
    from public.inv_layer l
    where l.origin_type not in ('baseline', 'transfer') and l.received_on between v_since and p_until
      and (l.doc_number in (select s.d from scope s) or l.doc_number = any (v_excl))
  ),
  ev_lay as (
    -- purchase(입고) → RCV · 차 #59 / 대 GINR · [4-3b · 판정 1119 · 1120] 보류를 푼다 — 무조건(그 Bill 이 QBO 에 갔는지와 무관) · 날짜 = 입고일(received_on) · Bill 이 늦으면 GINR 이 잠시 음수 = 「안 보낸 Bill 이 있다」 신호
    select x.lcode as e_wh, 'RCV' as e_kind, x.ldoc as e_key, x.lacct as e_dr, c_ginr as e_cr, x.lamt as e_amt, x.lon as e_on,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end as e_status,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end as e_reason
    from lay x where x.lor = 'purchase'
    union all
    -- creditnote(restock) → CR · 차 #59 / 대 #58
    select x.lcode, 'CR', x.ldoc, x.lacct, c_cogs, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'creditnote'
    union all
    -- adjust_new · adjust_existing → ADJ · 차 #59 / 대 조정 계정(1087)
    select x.lcode, 'ADJ', x.ldoc, x.lacct, aa.code, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null or aa.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when aa.code is null then 'adjustment ' || x.ldoc || ' not found (account unknown)' end
    from lay x left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = x.ldoc) aa on true
    where x.lor in ('adjust_new', 'adjust_existing')
    union all
    -- sale_shortfall → SO · 차 #59 / 대 조정 기본 계정(1094 · 판매 원가 줄은 그대로)
    select x.lcode, 'SO', x.ldoc, x.lacct, v_adj_def, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'sale_shortfall'
    union all
    -- assembly → FG · 같은 창고 #59 ↔ #59 = 0
    select x.lcode, 'FG', x.ldoc, x.lacct, x.lacct, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'assembly'
    union all
    -- 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.lor, x.ldoc, x.lacct, x.lacct, x.lamt, x.lon, 'block', 'layer origin ' || x.lor || ' on ' || x.ldoc || ' — not in the 22 cells'
    from lay x where x.lor not in ('purchase', 'creditnote', 'adjust_new', 'adjust_existing', 'sale_shortfall', 'assembly')
  ),
  -- 조립 값 검산 — 문서마다 Σ소진(assembly_in) ≠ Σ레이어(assembly) 면 막음(같은 창고 #59 ↔ #59 라 줄은 없지만 값이 새면 안 된다)
  asm_check as (
    select coalesce(a.e_wh, b.e_wh) as e_wh, 'FG' as e_kind, coalesce(a.e_key, b.e_key) as e_key, c_inv as e_dr, c_inv as e_cr, coalesce(a.s, 0) - coalesce(b.s, 0) as e_amt, coalesce(a.o, b.o) as e_on,
           'block' as e_status, 'assembly ' || coalesce(a.e_key, b.e_key) || ' consumes ' || coalesce(a.s, 0)::text || ' but the finished layer is worth ' || coalesce(b.s, 0)::text as e_reason
    from (select e.e_wh, e.e_key, sum(e.e_amt) as s, min(e.e_on) as o from ev_cons e where e.e_kind = 'FG' and e.e_status = 'send' group by 1, 2) a
    full join (select e.e_wh, e.e_key, sum(e.e_amt) as s, min(e.e_on) as o from ev_lay e where e.e_kind = 'FG' and e.e_status = 'send' group by 1, 2) b on b.e_wh = a.e_wh and b.e_key = a.e_key
    where abs(coalesce(a.s, 0) - coalesce(b.s, 0)) > 0.005
  ),
  -- ── 얹기 ──
  adds_raw as materialized (
    select a.id as aid, a.layer_id as alid, a.kind as akd, a.doc_number as adoc, a.line_ref as alr, a.occurred_on as aon, a.amount as aamt,
           (a.line_ref in (select f.lr from fix f)) as is_fix, (a.doc_number in (select s.d from scope s)) as in_scope
    from public.inv_layer_cost_add a
    where a.kind <> 'carried' and a.occurred_on between v_since and p_until
  ),
  adds as (
    select a.aid, a.akd, a.adoc, a.alr, a.aon, a.aamt, a.is_fix, a.in_scope,
           l.id as lid, l.warehouse as lwh, case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode,
           pc.kind as pckind, (pc.id is not null) as is_ims_charge, ca.source_number as ca_num
    from adds_raw a join public.inv_layer l on l.id = a.alid
    left join public.po_charge pc on a.akd = 'landed' and pc.charge_number = a.adoc
    left join public.inv_cost_adjust ca on a.akd in ('price_adjust', 'settlement_discount') and a.alr = 'adj:' || ca.id::text
  ),
  ev_add as (
    -- landed(IMS 비용 문서) → CHG · 차 #59(운송 중 레이어면 In Transit) / 대 비용 종류 계정(1089) · 날짜 = IMS 가 얹은 날(507) · Cin7 축 landed 는 범위 밖
    select x.lcode as e_wh, 'CHG' as e_kind, x.adoc as e_key, x.lacct as e_dr, public.qbo_cost_charge_account(x.pckind) as e_cr, x.aamt as e_amt, x.aon as e_on,
           case when x.is_fix then 'excluded' when x.lcode is null or public.qbo_cost_charge_account(x.pckind) is null then 'block' else 'send' end as e_status,
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when public.qbo_cost_charge_account(x.pckind) is null then 'charge ' || x.adoc || ' kind ' || coalesce(x.pckind, '?') || ' has no cost account (1089)' end as e_reason
    from adds x where x.akd = 'landed' and (x.is_ims_charge or x.is_fix)
    union all
    -- transfer_freight(Cin7 축 꼴 · 문서가 범위 안일 때만) → TRF · 차 #59 / In Transit / 대 #136(1100 · 종류 없음)
    select x.lcode, 'TRF', x.adoc, x.lacct, '_136_', x.aamt, x.aon,
           case when x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from adds x where x.akd = 'transfer_freight' and (x.in_scope or x.is_fix)
    union all
    -- price_adjust · settlement_discount(원가 조정 사건) → CADJ · [4-3b · 판정 1121] 대 계정 = GINR(#59 · #58 은 원가 장만 · VendorCredit 은 A/P ↔ GINR) · 가격 크레딧(price_adjust)은 보낸다 · 조기 결제 할인(settlement_discount)은 결제 차수(4-5)까지 보류
    select x.lcode, 'CADJ', coalesce(x.ca_num, x.alr), x.lacct, c_ginr, x.aamt, x.aon,
           case when x.is_fix then 'excluded' when x.lcode is null then 'block' when x.akd = 'price_adjust' then 'send' else 'hold' end,
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when x.akd = 'price_adjust' then null else 'early-payment discount — opens with the supplier payment round (4-5 · 1121)' end
    from adds x where x.akd in ('price_adjust', 'settlement_discount')
    union all
    -- opening_fix → 제외(932 · 1090) · 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.akd, x.adoc, x.lacct, x.lacct, x.aamt, x.aon,
           case when x.akd = 'opening_fix' or x.is_fix then 'excluded' else 'block' end,
           case when x.akd = 'opening_fix' or x.is_fix then 'opening_fix (1090)' else 'cost add kind ' || x.akd || ' on ' || x.adoc || ' — not in the 22 cells' end
    from adds x where x.akd not in ('landed', 'transfer_freight', 'price_adjust', 'settlement_discount')
  ),
  ev as (
    select * from ev_cons union all select * from ev_lay union all select * from asm_check union all select * from ev_add
  ),
  -- 문턱(1099): ADJ 문서마다 Σ|금액|(들어옴 · 나감) > 문턱이면 보류 · 결정 send → send · never → excluded
  adj_tot as (select e.e_key as k, sum(abs(e.e_amt)) as tot from ev e where e.e_kind = 'ADJ' and e.e_status = 'send' group by 1),
  ev2 as (
    select e.e_wh, e.e_kind, e.e_key, e.e_dr, e.e_cr, e.e_amt, e.e_on,
           case when e.e_kind = 'ADJ' and e.e_status = 'send' and t.tot > v_thr then
                  case h.decision when 'send' then 'send' when 'never' then 'excluded' else 'hold' end
                else e.e_status end as e_status,
           case when e.e_kind = 'ADJ' and e.e_status = 'send' and t.tot > v_thr then
                  case h.decision when 'send' then 'adjustment over threshold — decided: send' when 'never' then 'adjustment over threshold — decided: never send'
                       else 'adjustment ' || e.e_key || ' totals ' || round(t.tot, 2)::text || ' over the ' || v_thr::text || ' threshold — decide send / never first (1099)' end
                else e.e_reason end as e_reason
    from ev e
    left join adj_tot t on e.e_kind = 'ADJ' and t.k = e.e_key
    left join public.qbo_cost_hold h on v_realm is not null and h.realm_id = v_realm and h.key_kind = e.e_kind and h.doc_key = e.e_key
  ),
  agg as (
    select e.e_wh, e.e_kind, e.e_key,
           least(e.e_dr, coalesce(e.e_cr, e.e_dr)) as a, greatest(e.e_dr, coalesce(e.e_cr, e.e_dr)) as b,
           sum(case when e.e_dr = least(e.e_dr, coalesce(e.e_cr, e.e_dr)) then e.e_amt else -e.e_amt end) as raw,
           e.e_status, min(e.e_reason) as rs, min(e.e_on) as f_on, max(e.e_on) as l_on, count(*)::int as n,
           bool_or(e.e_cr is null) as cr_null
    from ev2 e
    group by e.e_wh, e.e_kind, e.e_key, least(e.e_dr, coalesce(e.e_cr, e.e_dr)), greatest(e.e_dr, coalesce(e.e_cr, e.e_dr)), e.e_status
  )
  select g.e_wh, g.e_kind, g.e_key, g.a, case when g.cr_null then null else g.b end, (round(g.raw, 2) * 100)::bigint, g.raw, g.e_status, g.rs,
         case when g.e_kind = 'SO' and c_cogs in (g.a, g.b) then (select io.customer_id from public.so_invoice_order io join public.so_invoice i on i.id = io.invoice_id where io.so_number = g.e_key and io.cancelled_at is null and i.status = 'issued' order by i.issued_on desc, i.created_at desc limit 1)
              when g.e_kind = 'CR' and c_cogs in (g.a, g.b) then (select coalesce(cr.store_customer_id, cr.customer_id) from public.so_credit cr where cr.credit_number = g.e_key) end,
         g.f_on, g.l_on, g.n
  from agg g
  where round(g.raw, 2) <> 0 or g.e_status = 'block'
  order by g.e_wh, g.e_kind, g.e_key, g.a, g.b;
end;
$function$
;
do $$
begin
  execute format('comment on function public.qbo_cost_expected(date, date, text) is %L', coalesce(obj_description('public.qbo_cost_expected(date, date, text)'::regprocedure, 'pg_proc'), '')
    || ' · [4-3b · 판정 1119 · 1120 · 1121] RCV(purchase 레이어) 보류를 푼다 — send · 날짜 = received_on(Bill 이 QBO 에 갔는지와 무관) · CADJ 대 계정 GINR · price_adjust send · settlement_discount 는 4-5 까지 hold');
end $$;

-- ═══════════════ ② F — USD 은행 · 결제 계좌 통화(1122) · 결제 통화 ≠ 계좌 통화면 거부(지연 제약 트리거 · 1091 꼴) ═══════════════
do $$
declare c_usd constant text[] := array['_106_', '_138_', '_141_', '_144_', '_145_', '_204_']; v_n int; v_missing text;
begin
  select string_agg(c, ', ') into v_missing from unnest(c_usd) c where not exists (select 1 from public.ref_account a where a.code = c);
  if v_missing is not null then raise exception '② ref_account code(s) % not found — nothing was changed', v_missing; end if;
  select count(*) into v_n from public.ref_account a where a.code = any (c_usd) and a.currency_code is not null and a.currency_code <> 'USD';
  if v_n <> 0 then raise exception '② % of the USD bank accounts already carry another currency — look first — nothing was changed', v_n; end if;
  update public.ref_account a set currency_code = 'USD', updated_at = now() where a.code = any (c_usd) and a.currency_code is null;
  get diagnostics v_n = row_count;
  if v_n <> array_length(c_usd, 1) then raise exception '② USD bank account update touched % rows (expected %) — nothing was changed', v_n, array_length(c_usd, 1); end if;
  -- 기존 결제가 걸리지 않는지 먼저(USD 셋 _138_ · CAD 하나 _104_ · 11-09 실측)
  select count(*) into v_n from public.po_payment p join public.ref_currency r on r.id = p.currency_id where p.account_id is not null and public.ims_account_currency(p.account_id) <> r.code;
  if v_n <> 0 then raise exception '② % existing supplier payment(s) are on a bank account of another currency — fix them before this migration — nothing was changed', v_n; end if;
end $$;

create function public.po_payment_account_currency_check() returns trigger
  language plpgsql set search_path = public, pg_temp
as $$
declare v_p public.po_payment%rowtype; v_cur text; v_acur text; v_code text;
begin
  -- deferred 라 트랜잭션 끝에 돈다 — 지금 행을 다시 읽어 판정한다(없으면 볼 것이 없다 · 계정 없는 결제는 통과 · po_payment_create 의 account_missing 경고 그대로)
  select * into v_p from public.po_payment p where p.id = new.id;
  if not found or v_p.account_id is null then return null; end if;
  select r.code into v_cur from public.ref_currency r where r.id = v_p.currency_id;
  select a.code, public.ims_account_currency(a.id) into v_code, v_acur from public.ref_account a where a.id = v_p.account_id;
  if v_cur is null or v_acur is null or v_cur = v_acur then return null; end if;
  raise exception using errcode = 'P0001', message = public.ims_account_currency_msg('Payment', coalesce(nullif(btrim(coalesce(v_p.reference, '')), ''), v_p.paid_on::text || ' ' || v_p.amount::text), 'bank', v_code, v_acur, v_cur);
end $$;
comment on function public.po_payment_account_currency_check() is '[qbo-sync-4-3b · 판정 1122 · 1091 꼴] 트리거 po_payment_account_currency_ck 의 몸 — 결제 통화 ≠ 지급 계좌 통화(ims_account_currency · null = CAD)면 거부 · deferred 라 지금 행을 다시 읽는다 · 계정이 없으면 통과 · 거부 글 = ims_account_currency_msg(Payment · 참조 또는 날짜 금액 · bank)';
create constraint trigger po_payment_account_currency_ck
  after insert or update of currency_id, account_id on public.po_payment
  deferrable initially deferred for each row execute function public.po_payment_account_currency_check();
revoke all on function public.po_payment_account_currency_check() from public, anon, authenticated, service_role;

do $$
begin
  execute format('comment on table public.ref_account is %L', coalesce(obj_description('public.ref_account'::regclass, 'pg_class'), '') || ' · [qbo-sync-4-3b · 1122] currency_code USD 를 은행 · 결제 계좌 여섯에(_106_ · _138_ 확정 · _141_ · _144_ · _145_ · _204_ 는 이름) — 트리거 po_payment_account_currency_ck 가 결제 통화와 맞춘다');
  execute format('comment on table public.po_payment is %L', coalesce(obj_description('public.po_payment'::regclass, 'pg_class'), '') || ' · [qbo-sync-4-3b · 1122] 트리거 po_payment_account_currency_ck(deferred): 지급 계좌 통화 = 결제 통화(계정 없으면 통과) · 1124 섞인 공급처 · 1123 환율은 4-5');
end $$;
