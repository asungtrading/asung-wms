-- cogs-1 첫 차수(판정 109 · 2026-09-30) — 재생성 inv_layer_apply 가 얹기 셋(불러온 landed · transfer_freight · IMS 비용)을 루프 뒤가 아니라 **날짜 사건으로 제자리**에 넣는다 · 숫자 무변
--   ① 새 속 함수 inv_layer_apply_flush_adds(p_day · p_until · p_acc) — 원문의 얹기 블록 셋을 바이트 그대로 옮기고 「그날까지 · 아직 안 얹은 것 · 대상 레이어가 이미 선 것」 술어만 더했다(누적 반환 jsonb · 판정 31 회수)
--   ② inv_layer_apply 재발행(원본 20260929195458:1273 ~ 1870 바이트 그대로 + 바꾼 줄) — 루프 select 에 occurred_on · seq_hint 를 더하고 날짜 경계(날이 바뀔 때 · 그날 첫 유출 앞 · 루프 끝)에서 쏟기를 부른다 · 같은 날 = 들어옴 → 얹기 → 나감
--      음수 가드 둘은 루프 앞으로(원천 표만 읽는다 · 같은 판정) · orphan · no_basis · unvisited · 금액 합 · 반환 45칸 + ims{} 는 이름 · 뜻 · 값 무변 · ④ carry 한 바퀴는 끝에 그대로(판정 110 · 107 은 둘째 차수)
--   ⚠️ 이 차수는 숫자를 바꾸지 않는다 — 얹는 금액 · 대상 레이어 · occurred_on · doc_number · line_ref · ref_number 가 옛 판과 같다(검증 = 옛 재생성 정규형 = 새 재생성 정규형 · ~/asung/prompts/cogs-2-verify.sql) · 소진 식은 그대로(둘째 차수 판정 105 ~ 108 · 110 · 111)
--   ⚠️ 시험 적용 실측(2026-09-30 · 테스트 DB 읽기): (가) 저널 날짜 < 마지막 도착 인 transfer_freight 묶음 0/5 · (나) charge_date < 마지막 IMS 입고 인 확정 비용 0/4 · (다) 비용 날짜 < 입고일 인 landed 1,854/1,857 행(기다렸다 얹는다 · 4키 + occurred_on 한 줄 · 한 키 = 레이어 하나 실측) — 결과가 바뀌는 자리 0
--   UTC 이름 · 가드 첫 문장 · begin/commit 없음 · 부분 유니크 0 · 시퀀스 무접촉

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


-- ═══ 1) inv_layer_apply_flush_adds — 얹기 셋을 「그날까지」 제자리에 · 재생성 본체가 날짜 경계마다 부른다(판정 109) ═══
--   p_day = 이 경계의 날(그날까지의 얹기만 · null = p_until 까지 전부 · 루프 끝) · p_until = 재생성 as-of(원문 그대로) · p_acc = 누적 반환(키 = 원문 카운터 이름 · 본체가 마지막에 옮겨 담는다)
--   무엇이 「아직」인가 — ① landed: 4키 + occurred_on 의 cost_add 행이 없고 대상 purchase 레이어가 이미 선 것(레이어가 뒤에 서면 그때 첫 경계에서 · 실측 1,854/1,857 행이 비용 날짜 < 입고일)
--                      ② transfer_freight: 문서 단위(원문과 같이 · done kind cogs_fr) · 그 문서의 저널 묶음과 도착 in 행이 p_day 뒤에 더 없을 때(기준 = 도착 레이어 전부 = 원문과 같은 집합 · 실측 5문서 전부 도착 뒤 저널 · 저널이 여러 날이면 마지막 날에 함께 · 실측 0)
--                      ③ IMS 비용: charge_date ≤ p_day 이고 배분된 발주 · 트랜스퍼의 레이어가 선 것(원문 exists 둘 그대로 · done kind cogs_chg) · 창구 inv_layer_post_charge 그대로 · 배분 줄 단위 멱등은 창구 안(실시간 판정 94 와 같은 손)
--   ⚠️ 숫자 무변 — 얹는 금액 · 대상 레이어 · occurred_on · doc_number · line_ref · ref_number 는 원문과 같다 · 바뀌는 것은 「언제 넣나」뿐(다음 차수가 소진 단가에 얹힌 몫을 넣을 때 이 자리가 근거다)
--   ⚠️ 음수 가드 둘(landed · transfer_freight)은 본체가 루프 앞에서 한 번 건다(원문 문장 그대로 · 원천 표만 읽으므로 자리가 바뀌어도 같은 판정) · 건너뛴 비용(skip)은 날짜와 함께 담아 본체가 원문 순서(charge_date · charge_number · id)로 잇는다
create or replace function public.inv_layer_apply_flush_adds(p_day date, p_until date, p_acc jsonb) returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_landed_rows int := 0;
  v_doc         record;
  v_grp         record;
  v_fr_n        int;
  v_fr_basis    numeric;
  v_fr_rows     int := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
  v_rows        int;
  v_ims_j       jsonb;
  v_ims_chg     record;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_chg_skip    jsonb := '[]'::jsonb;                                                     -- [{d charge_date · e 원문 skip 항목}] — 본체가 원문 순서로 잇는다
begin
  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — cogs-1: 그날까지 · 아직 안 얹은 것 · 대상 레이어가 선 것만(집합 연산 한 번은 그대로) ═══
  insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
  select x.id, 'landed',
         sum(c.amount),          -- ⭐ bin 이 여럿이면 합산 (실측 0건 · 방어)
         c.occurred_on,          -- ⚠️ 날짜별로 별개 행 (통관·freight·관세)
         c.doc_number, c.line_ref,
         null                    -- PO landed 는 인보이스 번호가 오지 않는다 (헤더)
    from inv_cost c
    join inv_layer x
      on  x.origin_type = 'purchase'
      and x.doc_number  = c.doc_number
      and x.line_ref    = c.line_ref
      and x.sku         = c.sku
      and x.warehouse   = c.warehouse
    where c.cost_kind = 'landed'
      and (p_until is null or c.occurred_on <= p_until)
      and (p_day is null or c.occurred_on <= p_day)                                                                                                        -- cogs-1(판정 109): 그날까지의 비용만
      and not exists (select 1 from inv_layer_cost_add ca where ca.layer_id = x.id and ca.kind = 'landed' and ca.doc_number = c.doc_number and ca.line_ref = c.line_ref and ca.occurred_on = c.occurred_on)   -- cogs-1: 아직 안 얹은 것만(inv_layer_cost_add_uq 와 같은 키)
    group by x.id, c.occurred_on, c.doc_number, c.line_ref;
  get diagnostics v_landed_rows = row_count;

  -- ═══ 트랜스퍼 운송비 → inv_layer_cost_add (kind='transfer_freight' · 2026-09-10 · 헤더 B) — landed 와 같은 자리 ═══
  -- 문서 단위 루프 — 배분 기준(도착 레이어 원가 합)은 문서에 딸린 레이어로 정해지므로 문서마다 한 번 계산한다
  for v_doc in
    select doc_number, sum(amount) as amount     -- amount: no_basis 로 떨어질 때 합산할 문서 금액 (p_until 범위)
      from inv_doc_cost
      where doc_type = 'transfer' and kind = 'transfer_freight'
        and (p_until is null or occurred_on <= p_until)
      group by doc_number
      having (p_day is null or max(occurred_on) <= p_day)                                                                                                 -- cogs-1: 저널 묶음이 그날까지 다 온 문서만
      order by doc_number
  loop
    if exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_fr' and d.doc_number = v_doc.doc_number and d.sku = '' and d.warehouse = '') then continue; end if;   -- cogs-1: 이미 처리한 문서
    if p_day is not null and exists (select 1 from inv_ledger g where g.event_type = 'transfer_in' and g.warehouse <> 'IN_TRANSIT' and g.doc_number = v_doc.doc_number
                                        and g.occurred_on > p_day and (p_until is null or g.occurred_on <= p_until)) then continue; end if;                -- cogs-1: 도착이 더 남은 문서는 기다린다(기준 = 도착 레이어 전부 · 원문과 같은 집합)
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_fr', v_doc.doc_number, '', '');
    -- B-1 대상 = 도착 창고 레이어만 (IN_TRANSIT 제외) · B-2 기준 = unit_cost × qty (remaining 아님)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_fr_n, v_fr_basis
      from inv_layer x
      where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT';
    if v_fr_n = 0 then
      v_fr_orphan := v_fr_orphan + 1;          -- 대응 레이어 없음 (0 이 아니면 신호)
      continue;
    end if;
    if v_fr_basis <= 0 then
      v_fr_nobasis := v_fr_nobasis + 1;        -- 원가 미상(unknown · unit_cost 0) 레이어만 있는 문서 — 0 으로 나누지 않는다
      v_fr_nobasis_amt := v_fr_nobasis_amt + v_doc.amount;   -- ⚠️ 버린 운송비 금액 — Cin7 대조에서 설명된 차이의 크기 (헤더)
      continue;
    end if;

    -- 날짜별 한 묶음 — cost_add 유니크 키에 ref_number 가 없으므로 같은 날 인보이스가 둘이면 합산 1행 (헤더 B-3)
    for v_grp in
      select occurred_on, sum(amount) as amount, count(*) as n,
             string_agg(distinct ref_number, ',' order by ref_number) as ref_number
        from inv_doc_cost
        where doc_type = 'transfer' and kind = 'transfer_freight' and doc_number = v_doc.doc_number
          and (p_until is null or occurred_on <= p_until)
        group by occurred_on
        order by occurred_on
    loop
      if v_grp.n > 1 then v_fr_multi := v_fr_multi + 1; end if;
      -- B-2 배분: share = round(문서금액 × 레이어원가 / 합, 6) · 마지막 레이어(id 순) = 문서금액 − 앞선 share 합 (remainder on last)
      insert into inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      select t.id, 'transfer_freight',
             case when t.rn = t.cnt
                  then v_grp.amount - coalesce(sum(t.share) over (order by t.rn rows between unbounded preceding and 1 preceding), 0)
                  else t.share end,
             v_grp.occurred_on, v_doc.doc_number, t.line_ref, v_grp.ref_number
        from (select x.id, x.line_ref,
                     round(v_grp.amount * (x.unit_cost * x.qty) / v_fr_basis, 6) as share,
                     row_number() over (order by x.id) as rn,
                     count(*) over () as cnt
                from inv_layer x
                where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT') t;
      get diagnostics v_rows = row_count;
      v_fr_rows := v_fr_rows + v_rows;
    end loop;
    v_fr_docs := v_fr_docs + 1;
  end loop;

  -- ═══ IMS 비용 → inv_layer_cost_add (kind='landed' · 2026-09-20) — landed·운송비와 같은 층 · 창구 inv_layer_post_charge 에 넘긴다 ═══
  -- tr-4(2026-09-29): 비용 문서의 배분 줄이 트랜스퍼를 가리키면 그 문서의 도착 레이어에 얹는다 — 같은 창구 · 같은 규칙(판정 67 · 77 · 묶음 일곱) · 아래 exists 둘에 트랜스퍼 갈래를 더했다.
  -- 왜 여기(날짜 경계)인가(cogs-1 · 판정 109): 옛 판은 「비용은 금액만 얹어 FIFO 소진에 영향이 없다」며 끝에 두었다 — 다음 차수가 소진 단가에 얹힌 몫을 넣으면 그 전제가 깨지므로 지금 자리부터 옮긴다(입고 레이어는 루프 안 — 본체).
  -- 왜 레이어에서 훑나(Caleb 판정 2026-09-20): 비용은 원장에 사건을 남기지 않아(금액만 얹는다) 원장으로 훑을 수 없다. 레이어가 없으면 얹을 곳도 없으니 부를 이유가 없다.
  --   길: inv_layer(cost_source='po_line').line_ref = po_line.id::text → po_line.po_id = po_charge_alloc.po_id → po_charge_alloc.po_charge_id = po_charge.id (confirmed).
  --   비용 문서 단위로 한 번(한 비용이 여러 발주에 배분된다 — exists 로 접는다) · 순서 고정.
  -- 왜 창구에 넘기나: 배분 규칙(환율 · unit_cost×qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등)이 창구 안에 있다 — 두 곳에 살게 하지 않는다.
  -- p_until: 창구는 occurred_on = po_charge.charge_date 로 얹는다 — 그래서 charge_date <= p_until 로 고른다(as-of 재생성).
  -- 방문하지 않은 확정 비용(배분된 발주 어디에도 IMS 레이어가 없는 것 — 예: 환율이 없어 입고를 건너뛴 발주)은 따로 센다(charges_unvisited · 금액 CAD)
  --   — 「버린 금액」의 그림이 빠지지 않게. Cin7 대조에서 이 금액만큼은 설명된 차이다(정본 D 의 freight_no_basis_amount 와 같은 구실).
  for v_ims_chg in
    select c.id, c.charge_number, c.charge_date
      from po_charge c
      where c.status = 'confirmed' and c.confirmed_at is not null
        and (p_until is null or c.charge_date <= p_until)
        and (p_day is null or c.charge_date <= p_day)                                                                                                     -- cogs-1(판정 109): 그날까지의 비용만
        and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = c.id::text and d.sku = '' and d.warehouse = '')   -- cogs-1: 이미 부른 비용은 다시 안 부른다
        and (exists (select 1
                      from po_charge_alloc a
                      join po_line  pl on pl.po_id = a.po_id
                      join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                      where a.po_charge_id = c.id)
             or exists (select 1                                                         -- tr-4: 트랜스퍼 배분 — 도착 레이어(origin transfer · TRF-n · 도착 창고 · :settle: 제외)가 선 것
                          from po_charge_alloc a
                          join inv_transfer t on t.id = a.transfer_id
                          join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%'   -- inv-basis-3(판정 95 ㉓): 창구와 같은 술어 — :over: 레이어는 운임의 자리가 아니다
                          where a.po_charge_id = c.id))
      order by c.charge_date, c.charge_number, c.id       -- ⚠️ 순서 고정 · charge_number 는 (supplier_id, charge_number) 유니크라 id 까지 건다
  loop
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_chg', v_ims_chg.id::text, '', '');
    begin
      v_ims_j := inv_layer_post_charge(v_ims_chg.id);
      v_ims_chg_n            := v_ims_chg_n + 1;
      v_ims_chg_rows         := v_ims_chg_rows         + coalesce((v_ims_j->>'layers_touched')::int, 0);
      v_ims_chg_amt          := v_ims_chg_amt          + coalesce((v_ims_j->>'amount_posted_cad')::numeric, 0);
      v_ims_chg_nobasis_amt  := v_ims_chg_nobasis_amt  + coalesce((v_ims_j->>'no_basis_amount_cad')::numeric, 0);    -- 기준 0 이라 버린 금액(정본 D)
      v_ims_chg_nolayers_amt := v_ims_chg_nolayers_amt + coalesce((v_ims_j->>'no_layers_amount_cad')::numeric, 0);   -- 배분 줄 중 레이어 없는 발주로 간 금액
      v_ims_chg_already      := v_ims_chg_already      + coalesce((v_ims_j->>'already_posted_allocs')::int, 0);      -- cost_add 를 지운 뒤라 0 이어야 한다(생기면 신호)
    exception when others then
      v_ims_chg_skipped := v_ims_chg_skipped + 1;
      v_chg_skip := v_chg_skip || jsonb_build_object('d', v_ims_chg.charge_date, 'e', jsonb_build_object('kind', 'charge', 'number', v_ims_chg.charge_number, 'id', v_ims_chg.id, 'sqlstate', sqlstate, 'error', sqlerrm));   -- cogs-1: 원문 항목 그대로 + 날짜(본체가 원문 순서로 잇는다)
    end;
  end loop;

  return jsonb_build_object(
    'landed_rows',      coalesce((p_acc ->> 'landed_rows')::int, 0)          + v_landed_rows,
    'fr_rows',          coalesce((p_acc ->> 'fr_rows')::int, 0)              + v_fr_rows,
    'fr_docs',          coalesce((p_acc ->> 'fr_docs')::int, 0)              + v_fr_docs,
    'fr_nobasis',       coalesce((p_acc ->> 'fr_nobasis')::int, 0)           + v_fr_nobasis,
    'fr_nobasis_amt',   coalesce((p_acc ->> 'fr_nobasis_amt')::numeric, 0)   + v_fr_nobasis_amt,
    'fr_orphan',        coalesce((p_acc ->> 'fr_orphan')::int, 0)            + v_fr_orphan,
    'fr_multi',         coalesce((p_acc ->> 'fr_multi')::int, 0)             + v_fr_multi,
    'chg_n',            coalesce((p_acc ->> 'chg_n')::int, 0)                + v_ims_chg_n,
    'chg_rows',         coalesce((p_acc ->> 'chg_rows')::int, 0)             + v_ims_chg_rows,
    'chg_amt',          coalesce((p_acc ->> 'chg_amt')::numeric, 0)          + v_ims_chg_amt,
    'chg_nobasis_amt',  coalesce((p_acc ->> 'chg_nobasis_amt')::numeric, 0)  + v_ims_chg_nobasis_amt,
    'chg_nolayers_amt', coalesce((p_acc ->> 'chg_nolayers_amt')::numeric, 0) + v_ims_chg_nolayers_amt,
    'chg_already',      coalesce((p_acc ->> 'chg_already')::int, 0)          + v_ims_chg_already,
    'chg_skipped',      coalesce((p_acc ->> 'chg_skipped')::int, 0)          + v_ims_chg_skipped,
    'chg_skip',         coalesce(p_acc -> 'chg_skip', '[]'::jsonb)           || v_chg_skip);
end;
$$;
comment on function public.inv_layer_apply_flush_adds(date, date, jsonb) is
  '⭐ 재생성 속 함수(cogs-1 · 판정 109 · 2026-09-30) — inv_layer_apply 가 날짜 경계마다 부른다: 그날까지의 얹기 셋(불러온 landed · transfer_freight · IMS 비용 inv_layer_post_charge)을 아직 안 얹은 것만 · 대상 레이어가 선 것만 제자리에 넣고 누적 반환(jsonb)에 더한다 · 얹는 금액 · 대상 · 키는 옛 판과 같다(숫자 무변) · definer · 판정 31 회수(사람이 psql 로 inv_layer_apply 를 부를 때만 돈다)';
revoke all on function public.inv_layer_apply_flush_adds(date, date, jsonb) from public, anon, authenticated;   -- ⭐ 판정 31 — 재생성 계열


-- ═══ 2) inv_layer_apply 재발행 — 원본 20260929195458:1273 ~ 1870 바이트 그대로 + 바꾼 줄(cogs-1 표시) ═══
create or replace function inv_layer_apply(p_until date default null)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_t0          timestamptz := clock_timestamp();
  v_baseline    int;
  r             record;
  v_c int; v_u int; v_rows int; v_short int; v_proc int; v_rev int; v_layers int; v_orphan int; v_nz int; v_unk int; v_unkq numeric;
  v_partial int; v_traced int; v_avg int;
  v_po          int := 0;
  v_sale        int := 0;
  v_sale_keys   int := 0;
  v_sale_rev    int := 0;
  v_tr          int := 0;
  v_tr_layers   int := 0;
  v_tr_orphan   int := 0;
  v_tr_nz       int := 0;
  v_tr_unk      int := 0;
  v_tr_unkq     numeric := 0;
  v_tr_unpaired int := 0;
  v_adj         int := 0;
  v_adj_layers  int := 0;
  v_adj_rows    int := 0;
  v_adj_unk     int := 0;
  v_adj_new_nz  int := 0;
  v_asm         int := 0;
  v_asm_layers  int := 0;
  v_asm_rows    int := 0;
  v_asm_partial int := 0;
  v_asm_nz      int := 0;
  v_asm_unpaired int := 0;
  v_cr          int := 0;
  v_cr_layers   int := 0;
  v_cr_traced   int := 0;
  v_cr_avg      int := 0;
  v_cr_unk      int := 0;
  v_cr_nz       int := 0;
  v_layers_po   int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
  -- landed (2026-09-10)
  v_landed_rows int := 0;
  v_landed_amt  numeric := 0;
  v_landed_orph int := 0;
  v_neg         record;
  -- transfer_freight (2026-09-10)
  v_fr_rows     int := 0;
  v_fr_amt      numeric := 0;
  v_fr_docs     int := 0;
  v_fr_nobasis  int := 0;
  v_fr_nobasis_amt numeric := 0;
  v_fr_orphan   int := 0;
  v_fr_multi    int := 0;
  -- IMS (2026-09-20) — 창구 둘(inv_layer_post_receipt · inv_layer_post_charge)의 반환을 합친다. ⚠️ 원문 변수와 겹치지 않는 v_ims_ 접두어
  v_ims_src     text;
  v_ims_task    text;
  v_ims_docno   text;
  v_ims_j       jsonb;
  v_ims_rcv         int := 0;   v_ims_rcv_layers int := 0;   v_ims_rcv_exist int := 0;   v_ims_rcv_cost numeric := 0;   v_ims_rcv_skipped int := 0;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_ims_chg_unvisited int := 0;   v_ims_chg_unvisited_amt numeric := 0;
  v_ims_carry_rows int := 0;   v_ims_carry_amt numeric := 0;   v_ims_carry record;   -- tr-4b(판정 79): IMS 트랜스퍼 자식 레이어로 따라간 얹힌 원가(마지막 한 바퀴)
  v_ims_skip    jsonb := '[]'::jsonb;
  -- IMS 초과분 (2026-09-20 · over 닫기) — 형제 창구 inv_layer_post_receipt_over 의 반환을 합친다
  v_ims_over    text;
  v_ims_over_n  int := 0;   v_ims_over_layers int := 0;   v_ims_over_skipped int := 0;
  -- IMS off-PO (⑤-6c1 · 2026-09-27) — 형제 창구 inv_layer_post_receipt_off_po 의 반환을 합친다
  v_ims_offpo   text;
  v_ims_offpo_n int := 0;   v_ims_offpo_layers int := 0;   v_ims_offpo_skipped int := 0;
  v_ims_lref    text;                                                                     -- ⑤-6c1 — off-PO 행(<diff>:offpo)은 입고 단위 창구(ims_rcv)의 근거가 아니다(초안 입고에도 서는 행)
  -- IMS 문 · 보조 넷 (2026-09-20) — 창구가 아직 없는 IMS 사건을 사건 종류별로 센다(0 이 아니면 그 창구를 만들 때다). sale_out 은 없다(문 불필요).
  v_ims_gate    jsonb := '{"transfer_in": 0, "transfer_out": 0, "manual_reversal": 0, "adjust_existing": 0, "adjust_new": 0, "assemble_in": 0, "assemble_out": 0, "credit_in": 0}'::jsonb;
  v_ims_kind    text;                                                                     -- trf-a 2026-09-28 raw.kind — 'bin_move' = 같은 창고 칸 옮기기(레이어는 창고 단위라 할 일이 없다)
  v_bin_moves   int := 0;                                                                 -- trf-a 지나간 칸 옮기기 행 수(out · in 둘 다 센다 · 반환 ims.bin_moves_passed)
  v_ims_wh      text;                                                                     -- tr-2 2026-09-28 창고(IN_TRANSIT 갈래)
  v_ims_trd     int := 0;   v_ims_trd_layers int := 0;   v_ims_trd_rows int := 0;   v_ims_trd_short numeric := 0;   v_ims_trd_skipped int := 0;   v_ims_trd_out int := 0;   -- tr-2 출발 창구 inv_layer_apply_transfer_depart_ims 의 반환 합
  v_ims_tra     int := 0;   v_ims_tra_layers int := 0;   v_ims_tra_rows int := 0;   v_ims_tra_short numeric := 0;   v_ims_tra_skipped int := 0;                            -- tr-3a 도착 창구 inv_layer_apply_transfer_arrive_ims 의 반환 합
  v_ims_leg     text;                                                                     -- tr-3b raw.leg(lost · return_in · over_2 · over_4 갈래)
  v_ims_trs     int := 0;   v_ims_trs_layers int := 0;   v_ims_trs_rows int := 0;   v_ims_trs_short numeric := 0;   v_ims_trs_skipped int := 0;   v_ims_trs_pass int := 0;   -- tr-3b 정리 창구 inv_layer_apply_transfer_settle_ims 의 반환 합
  -- cogs-1(판정 109) 얹기 쏟기 — 날짜 경계 상태 · 누적 반환(속 함수 inv_layer_apply_flush_adds)
  v_add_day     date;
  v_add_flushed boolean := false;
  v_add_acc     jsonb := '{}'::jsonb;
  v_add_j       jsonb;
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  -- ⭐ IMS 권한 문 (2026-09-20) — 창구 둘은 ims_require_write(receiving · purchasing) 로 auth.uid() 의 권한을 본다.
  --   권한이 없으면 창구가 전부 예외를 던지고 아래 IMS 블록이 그것을 「건너뛰었다」로 세어 버린다 — 재생성이 조용히 반쪽(IMS 만 빠진 레이어 표)이 된다.
  --   그래서 지우기 전에 먼저 막는다. psql 에서는 request.jwt.claims 에 admin 의 sub 를 심고 돌린다(20260918133858 검증 주석 선례).
  if not (ims_can_write('receiving') and ims_can_write('purchasing')) then
    raise exception 'inv_layer_apply: the IMS cost windows (inv_layer_post_receipt · inv_layer_post_charge) need write permission on receiving and purchasing for this login (auth.uid() = %) — from psql, set request.jwt.claims to an admin''s sub first — nothing was rebuilt',
      coalesce(auth.uid()::text, '(null)');
  end if;
  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  -- cogs-1: 음수 가드 둘을 루프 앞으로(원문 문장 그대로 · 원천 표 inv_cost · inv_doc_cost 만 읽으므로 자리가 바뀌어도 같은 판정) — 얹기 자체는 속 함수가 날짜 경계마다 넣는다
  -- 가드: 키(4키 + occurred_on) 합이 음수면 예외 — inv_layer_cost_add 에는 amount CHECK 가 없어 이것이 유일한 방어다
  select c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on, sum(c.amount) as amt into v_neg
    from inv_cost c
    where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)
    group by c.doc_number, c.line_ref, c.sku, c.warehouse, c.occurred_on
    having sum(c.amount) < 0
    order by 1, 2, 5 limit 1;
  if found then
    raise exception 'inv_cost landed sum(amount) is negative for % / % / % / % @ %: % — refusing to add cost (revaluation offset? inspect inv_cost)',
      v_neg.doc_number, v_neg.line_ref, v_neg.sku, v_neg.warehouse, v_neg.occurred_on, v_neg.amt;
  end if;
  -- B-4 가드: 저널 행 금액이 음수면 예외 — inv_doc_cost 에도 inv_layer_cost_add 에도 amount CHECK 가 없어 이것이 유일한 방어다
  select d.doc_number, d.ref_number, d.occurred_on, d.amount into v_neg
    from inv_doc_cost d
    where d.doc_type = 'transfer' and d.kind = 'transfer_freight'
      and (p_until is null or d.occurred_on <= p_until)
      and d.amount < 0
    order by d.doc_number, d.occurred_on, d.ref_number limit 1;
  if found then
    raise exception 'inv_doc_cost transfer_freight amount is negative for % / invoice % @ %: % — refusing to distribute (correction? inspect inv_doc_cost)',
      v_neg.doc_number, coalesce(v_neg.ref_number, '(null)'), v_neg.occurred_on, v_neg.amount;
  end if;

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, po_in 먼저, id · source 필터 없음 · ⭐ 2026-09-21: 같은 날 유입끼리는 po_in 을 맨 앞에 — seq_hint 는 유입·유출만 가른다. 근거는 이 파일 머리 주석)
  for r in
    select id, event_type, occurred_on, seq_hint                                                            -- cogs-1: occurred_on · seq_hint 를 더했다(순서 · 행은 무변 · 쏟기 경계에 쓴다)
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, case event_type when 'po_in' then 0 else 1 end, id
  loop
    -- ⭐ cogs-1(판정 109) 얹기 쏟기 — 날짜 경계에서만: 날이 바뀌면 지난 날 것 · 그날 첫 유출(seq_hint 2) 앞 · 루프 끝(아래) ⇒ 같은 날 = 들어옴 → 얹기 → 나감 · 행마다 부르지 않는다
    if v_add_day is not null and r.occurred_on > v_add_day and not v_add_flushed then
      v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, v_add_acc);
    end if;
    if r.occurred_on is distinct from v_add_day then v_add_day := r.occurred_on; v_add_flushed := false; end if;
    if r.seq_hint = 2 and not v_add_flushed then
      v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, v_add_acc);  v_add_flushed := true;
    end if;
    -- ⭐⭐ IMS 문 · 보조 넷 (2026-09-20 · po_in 문의 형제 · Caleb 「문만 낸다 — 창구는 만들지 않는다」) — 창구가 아직 없는 IMS 사건은 보조 함수에 보내지 않고 사건 종류별로 센다.
    -- 왜 안 보내나: 보조 넷(transfer_in · adjust · assemble · credit)은 원가를 inv_cost / 레이어 평균에서 찾는다. IMS 사건은 거기 없어 unit_cost 0 · 'unknown' 레이어가 선다 — po_in 에서 실측된 사고(rcv_unknown 0→2)와 같다.
    -- 왜 창구를 지금 안 만드나: 트랜스퍼 모듈도 IMS 재고조정도 아직 없다 — 쓰지 않을 창구는 맞는지 검증할 표본이 없다. 그 사건을 내는 날 창구를 만들고 여기서 부른다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
    -- 왜 세나: 조용히 지나가면 「IMS 트랜스퍼가 재고에 안 잡힌다」를 아무도 모른다. ims.skipped_by_event 가 0 이 아니면 창구를 만들 때가 됐다는 신호다.
    -- ⚠️ sale_out 은 세지도 막지도 않는다 — 소진은 출처를 안 보는 한 원장 FIFO 가 맞다(inv_layer_fifo_take). po_in 은 아래 분기가 창구로 처리한다.
    -- ⭐ 두 leg 다 막는다(⬜4) — transfer_out · manual_reversal · assemble_out 도 IMS 면 여기서 센다. out 은 대응 in 이 처리하므로 in 만 막아도 레이어는 안 서지만, 아래 *_unpaired 신호가 IMS 것으로 오염된다(그 집계에서도 ims 를 뺀다).
    -- 원문 루프 select(id, event_type)는 바꾸지 않는다 — po_in·sale_out 이 아닌 행만 PK 조회 한 번(po_in 은 아래 분기가 이미 조회한다).
    if r.event_type not in ('po_in', 'sale_out', 'credit_in', 'adjust_existing', 'adjust_new') then   -- adj-a 2026-09-28: 조정 둘도 아래 갈래가 source 로 가른다(IMS → inv_layer_apply_adjust_ims) · ⓒ1 2026-09-25: credit_in 은 아래 갈래가 source 로 가른다(IMS → 창구 inv_layer_apply_credit_ims · 문에서 세지 않는다 · skipped_by_event.credit_in 은 늘 0)
      select source, raw ->> 'kind', warehouse, raw ->> 'leg' into v_ims_src, v_ims_kind, v_ims_wh, v_ims_leg from inv_ledger where id = r.id;   -- trf-a: kind 도 함께(조회 한 번 그대로) · tr-2: warehouse 도 · tr-3b: leg 도
      if v_ims_src = 'ims' and v_ims_kind = 'bin_move' and r.event_type in ('transfer_in', 'transfer_out') then   -- trf-a 2026-09-28 칸 옮기기(같은 창고 · inv_post_move) — 레이어는 (sku, warehouse) 단위라 할 일이 없다 · 세지 않고 지나간다(실시간 창구도 레이어를 부르지 않는다 = 같은 결과) · 창고 간 문서는 kind 가 다르다(뒤 차수의 갈래)
        v_bin_moves := v_bin_moves + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and v_ims_leg in ('lost', 'return_in', 'over_4') then   -- tr-3b 운송 중 정리(lost · return) · 더 온 몫(sent_more) → 창구(inv_layer_post_transfer_settle · 실시간과 같은 함수) · 행마다(line_ref 가 곧 키)
        begin
          v_ims_j := inv_layer_apply_transfer_settle_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_trs        := v_ims_trs + 1;
            v_ims_trs_layers := v_ims_trs_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_trs_rows   := v_ims_trs_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_trs_short  := v_ims_trs_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_trs_skipped := v_ims_trs_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_settle', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and v_ims_leg = 'over_2' then                  -- tr-3b 더 온 몫의 IN_TRANSIT in(같은 날 ±N · 레이어는 over_4 가 출발 창고에서 곧장 도착 창고로) — 세고 지나간다
        v_ims_trs_pass := v_ims_trs_pass + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_out' then     -- tr-2 2026-09-28 창고 간 트랜스퍼 출발 out(출발 창고) — IN_TRANSIT in 이 처리한다(불러온 축과 같은 결) · 세고 지나간다 · tr-3b: leg 3 · return_out · over_1 · over_3 도 여기
        v_ims_trd_out := v_ims_trd_out + 1;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_in' and v_ims_wh = 'IN_TRANSIT' then   -- tr-2 출발 IN_TRANSIT in → 창구(inv_layer_post_transfer_depart · 실시간과 같은 함수) · (doc, sku) 한 번 · 도착 창고 in 은 ④(지금은 문이 센다)
        begin
          v_ims_j := inv_layer_apply_transfer_depart_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_trd        := v_ims_trd + 1;
            v_ims_trd_layers := v_ims_trd_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_trd_rows   := v_ims_trd_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_trd_short  := v_ims_trd_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_trd_skipped := v_ims_trd_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_depart', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
      if v_ims_src = 'ims' and v_ims_kind = 'transfer' and r.event_type = 'transfer_in' and v_ims_wh <> 'IN_TRANSIT' then   -- tr-3a 도착 창고 in(leg 4) → 창구(inv_layer_post_transfer_arrive · IN_TRANSIT 문서 범위 FIFO · 실시간과 같은 함수) · (doc, receipt, sku) 한 번 · leg 3 out 은 위 out 갈래가 센다
        begin
          v_ims_j := inv_layer_apply_transfer_arrive_ims(r.id);
          if (v_ims_j ->> 'processed')::boolean then
            v_ims_tra        := v_ims_tra + 1;
            v_ims_tra_layers := v_ims_tra_layers + coalesce((v_ims_j ->> 'layers')::int, 0);
            v_ims_tra_rows   := v_ims_tra_rows   + coalesce((v_ims_j ->> 'consume_rows')::int, 0);
            v_ims_tra_short  := v_ims_tra_short  + coalesce((v_ims_j ->> 'short_qty')::numeric, 0);
          end if;
        exception when others then
          v_ims_tra_skipped := v_ims_tra_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'transfer_arrive', 'number', (select doc_number from inv_ledger where id = r.id), 'id', r.id, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
        continue;
      end if;
      if v_ims_src = 'ims' then
        v_ims_gate := jsonb_set(v_ims_gate, array[r.event_type], to_jsonb(coalesce((v_ims_gate ->> r.event_type)::int, 0) + 1));
        continue;
      end if;
    end if;
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers_po := v_layers_po + v_c; v_unknown := v_unknown + v_u;
      -- ⭐⭐ IMS 입고 (2026-09-20) — 보조 inv_layer_apply_po_in 은 source='ims' 면 문에서 돌아섰다(0·0). 이 줄의 레이어는 창구 inv_layer_post_receipt 가 만든다.
      -- 왜 여기(루프 안 · 날짜순)이고 끝이 아닌가: 입고 레이어는 **수량** 레이어다 — 뒤에 오는 sale_out·transfer_out 이 FIFO 로 이것을 소진한다.
      --   끝에서 만들면 루프 안의 소진이 이 레이어를 못 보고 short 로 떨어지거나 다른 레이어를 먹어, 실시간 기표(확정 때 창구가 만든 상태)와 재생성 결과가 갈라진다.
      --   비용(cost_add)은 수량이 아니라 금액만 얹으므로 끝(landed·운송비와 같은 층)에 둔다 — 아래 「IMS 비용」 블록.
      -- 왜 창구에 넘기나: 원가 규칙(환율 곱하기 · 기준까지만 · bin 접기)이 창구 안에 있다. 여기 다시 적으면 같은 규칙이 두 곳에 살고 한쪽만 고치면 조용히 갈라진다.
      -- 왜 원장에서 훑나: 이 함수의 일은 「원장에서 레이어를 다시 만드는 것」이다 — 원장에 없으면 레이어도 없다. p_until 도 그대로 걸린다(as-of).
      -- 왜 입고 단위(doc_task_id = po_receipt.id)로 한 번인가: 입고 하나가 원장에 bin 별 여러 줄을 남긴다. 창구는 입고 단위로 일하고 4키 멱등이라 두 번 불러도 안전하지만,
      --   세는 값이 겹치지 않게 done 표(kind 'ims_rcv')로 한 번만 부른다. 같은 입고의 원장 줄은 occurred_on 이 같아(received_on) p_until 경계에 걸쳐 갈라지지 않는다.
      -- 왜 건너뛰고 세나(멈추지 않나 · Caleb 판정 2026-09-20): 이 함수는 검산 도구다. 입고 한 건의 빈칸(환율)으로 검산 자체가 안 되면 도구가 못 쓰게 된다.
      --   건너뛰어도 틀린 값이 들어가지 않는다 — 0 원가 레이어를 만드는 것과 전혀 다르다. 환율을 채우고 다시 돌리면 그 자리에 제대로 선다. 선례: freight_no_basis(기준 0 이면 버리고 금액을 센다).
      --   ⚠️ 몇 건을 왜 건너뛰었는지 반환(ims.receipts_skipped · ims.skip_reasons)에 반드시 남긴다 — 조용히 지나가면 같은 사고의 재판이다.
      select source, doc_task_id, doc_number, line_ref into v_ims_src, v_ims_task, v_ims_docno, v_ims_lref from inv_ledger where id = r.id;   -- 루프 select 는 바꾸지 않는다(원문 무변) — PK 조회 한 번 · ⑤-6c1 line_ref 도
      if v_ims_src = 'ims' and v_ims_task is not null and v_ims_lref not like '%:offpo'                                  -- ⑤-6c1 off-PO 행으로는 inv_layer_post_receipt 를 부르지 않는다(초안 입고라 거부돼 헛 skip 이 남는다)
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_rcv' and d.doc_number = v_ims_task and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_rcv', v_ims_task, '', '');   -- 입고 단위 키 — sku·warehouse 는 not null 이라 빈 문자열
        begin
          v_ims_j := inv_layer_post_receipt(v_ims_task::uuid);
          v_ims_rcv        := v_ims_rcv + 1;
          v_ims_rcv_layers := v_ims_rcv_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
          v_ims_rcv_exist  := v_ims_rcv_exist  + coalesce((v_ims_j->>'layers_existing')::int, 0);   -- 지운 뒤라 0 이어야 한다(생기면 신호 — 다른 축이 같은 4키를 먼저 만들었다)
          v_ims_rcv_cost   := v_ims_rcv_cost   + coalesce((v_ims_j->>'cost_total_cad')::numeric, 0);
        exception when others then
          -- ⚠️ 서브트랜잭션 — 창구가 던진 것(환율 없음 · 확정 아님 · po_line 없음 · base_currency 없음)만 여기로 온다. 그 호출이 넣은 레이어는 서브트랜잭션이 되돌린다 — 이 입고의 레이어는 하나도 서지 않는다.
          v_ims_rcv_skipped := v_ims_rcv_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'receipt', 'number', v_ims_docno, 'id', v_ims_task, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS 초과분 (2026-09-20 · over 닫기) — line_ref 가 ':over' 인 po_in 행은 형제 창구 inv_layer_post_receipt_over(diff_id) 가 만든다(free → 0 · billed/credited → 기준 레이어의 unit_cost).
      --   왜 여기(루프 안): 수량 레이어라 뒤의 FIFO 소진이 봐야 한다(위 입고와 같은 이유). 기준 레이어가 먼저 서야 하는데, 초과분 행은 같은 날(received_on)·더 큰 id 라 (occurred_on, seq_hint, id) 순서에서 항상 뒤다.
      --   왜 diff 단위 한 번: 한 차이가 빈 별 여러 행을 남긴다 — done 표 kind 'ims_over'. 거부(기준 레이어 없음 등)는 건너뛰고 ims.over_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_over from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:over';
      if v_ims_over is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_over' and d.doc_number = v_ims_over and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_over', v_ims_over, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_over(v_ims_over::uuid);
          v_ims_over_n      := v_ims_over_n + 1;
          v_ims_over_layers := v_ims_over_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_over_skipped := v_ims_over_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'over', 'number', v_ims_docno, 'id', v_ims_over, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
      -- ⭐ IMS off-PO (⑤-6c1 · 2026-09-27) — line_ref 가 ':offpo' 인 po_in 행은 형제 창구 inv_layer_post_receipt_off_po(diff_id) 가 만든다(accepted_free → 0 · accepted_billed → diff.unit_price × 환율 · manual).
      --   왜 diff 단위 한 번: 한 차이 = 한 행 · 한 칸이지만 over 와 같은 모양으로 done 표 kind 'ims_offpo' · 거부는 건너뛰고 ims.offpo_skipped · skip_reasons 에 센다.
      select raw->>'diff_id' into v_ims_offpo from inv_ledger where id = r.id and source = 'ims' and line_ref like '%:offpo';
      if v_ims_offpo is not null
         and not exists (select 1 from inv_layer_apply_done d where d.kind = 'ims_offpo' and d.doc_number = v_ims_offpo and d.sku = '' and d.warehouse = '') then
        insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('ims_offpo', v_ims_offpo, '', '');
        begin
          v_ims_j := inv_layer_post_receipt_off_po(v_ims_offpo::uuid);
          v_ims_offpo_n      := v_ims_offpo_n + 1;
          v_ims_offpo_layers := v_ims_offpo_layers + coalesce((v_ims_j->>'layers_created')::int, 0);
        exception when others then
          v_ims_offpo_skipped := v_ims_offpo_skipped + 1;
          v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'off_po', 'number', v_ims_docno, 'id', v_ims_offpo, 'sqlstate', sqlstate, 'error', sqlerrm);
        end;
      end if;
    elsif r.event_type = 'sale_out' then
      select * into v_rows, v_short, v_proc, v_rev from inv_layer_apply_sale_out(r.id, p_until);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_sale_keys := v_sale_keys + v_proc; v_sale_rev := v_sale_rev + v_rev;
    elsif r.event_type = 'transfer_in' then
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan; v_tr_nz := v_tr_nz + v_nz;
      v_tr_unk := v_tr_unk + v_unk; v_tr_unkq := v_tr_unkq + v_unkq;
    elsif r.event_type in ('adjust_existing', 'adjust_new') then
      -- adj-a 2026-09-28: IMS 축(source ims)은 창구(inv_layer_post_adjust)로 · Cin7 축은 종전 inv_layer_apply_adjust — 같은 반환 모양(credit_in 갈래와 같은 식)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust_ims(r.id, p_until);
      else
        select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
      end if;
      v_adj := v_adj + 1; v_adj_layers := v_adj_layers + v_layers; v_adj_rows := v_adj_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_adj_unk := v_adj_unk + v_unk; v_adj_new_nz := v_adj_new_nz + v_nz;
    elsif r.event_type = 'assemble_in' then
      select * into v_layers, v_rows, v_short, v_partial, v_nz, v_proc from inv_layer_apply_assemble(r.id, p_until);
      v_asm := v_asm + 1; v_asm_layers := v_asm_layers + v_layers; v_asm_rows := v_asm_rows + v_rows;
      v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_asm_partial := v_asm_partial + v_partial; v_asm_nz := v_asm_nz + v_nz;
    elsif r.event_type = 'assemble_out' then
      v_asm := v_asm + 1;   -- 부품 out 은 대응 in 이 처리한다(A-2 ④) — 여기서는 세기만
    elsif r.event_type = 'credit_in' then
      -- ⓒ1 2026-09-25: IMS 축(source ims)은 창구(inv_layer_post_credit)로 · Cin7 축은 종전 inv_layer_apply_credit — 두 축이 같은 반환 모양(17-f · 실시간과 재생성이 같은 함수)
      select source into v_ims_src from inv_ledger where id = r.id;
      if v_ims_src = 'ims' then
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit_ims(r.id, p_until);
      else
        select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit(r.id, p_until);
      end if;
      v_cr := v_cr + 1; v_cr_layers := v_cr_layers + v_layers; v_cr_traced := v_cr_traced + v_traced;
      v_cr_avg := v_cr_avg + v_avg; v_cr_unk := v_cr_unk + v_unk; v_cr_nz := v_cr_nz + v_nz;
    else
      v_tr := v_tr + 1;   -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다
    end if;
  end loop;
  v_add_acc := inv_layer_apply_flush_adds(p_until, p_until, v_add_acc);                                    -- cogs-1: 마지막 쏟기 — 남은 것 전부(p_until 까지 · 대상이 끝내 없는 것은 아래 orphan · unvisited 신호 그대로)

  -- ⭐ 순액 > 0 인데 같은 날짜의 대응 in 이 처리하지 않은 out 키 — (doc, sku, wh, day) · 0 이어야 한다(생기면 신호)
  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse, occurred_on
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 IMS out leg 는 위 문이 세었다(ims.skipped_by_event) — 여기 섞이면 「생기면 신호」가 IMS 것으로 오염된다
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse, occurred_on
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku
                          and d.warehouse = o.warehouse and d.day = o.occurred_on);

  -- 순액 > 0 인데 대응 in 이 처리하지 않은 부품 out 키 — 0 이어야 한다(생기면 신호). 순액 ≤ 0(상쇄 소멸) 키는 제외.
  select count(*) into v_asm_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type = 'assemble_out'
              and source <> 'ims'                                                       -- ⭐ 2026-09-20 같은 이유
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'asm_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

  -- ═══ 얹기 셋의 집계 — 속 함수의 누적 반환을 원문 카운터로 옮겨 담는다(반환 키 · 뜻 무변 · 얹기 자체는 루프 안 날짜 경계에서 끝났다 · cogs-1) ═══
  v_landed_rows          := coalesce((v_add_acc ->> 'landed_rows')::int, 0);
  v_fr_rows              := coalesce((v_add_acc ->> 'fr_rows')::int, 0);
  v_fr_docs              := coalesce((v_add_acc ->> 'fr_docs')::int, 0);
  v_fr_nobasis           := coalesce((v_add_acc ->> 'fr_nobasis')::int, 0);
  v_fr_nobasis_amt       := coalesce((v_add_acc ->> 'fr_nobasis_amt')::numeric, 0);
  v_fr_orphan            := coalesce((v_add_acc ->> 'fr_orphan')::int, 0);
  v_fr_multi             := coalesce((v_add_acc ->> 'fr_multi')::int, 0);
  v_ims_chg_n            := coalesce((v_add_acc ->> 'chg_n')::int, 0);
  v_ims_chg_rows         := coalesce((v_add_acc ->> 'chg_rows')::int, 0);
  v_ims_chg_amt          := coalesce((v_add_acc ->> 'chg_amt')::numeric, 0);
  v_ims_chg_nobasis_amt  := coalesce((v_add_acc ->> 'chg_nobasis_amt')::numeric, 0);
  v_ims_chg_nolayers_amt := coalesce((v_add_acc ->> 'chg_nolayers_amt')::numeric, 0);
  v_ims_chg_already      := coalesce((v_add_acc ->> 'chg_already')::int, 0);
  v_ims_chg_skipped      := coalesce((v_add_acc ->> 'chg_skipped')::int, 0);
  select coalesce(jsonb_agg(s -> 'e' order by (s ->> 'd')::date, s -> 'e' ->> 'number', (s -> 'e' ->> 'id')::uuid), '[]'::jsonb) into v_add_j
    from jsonb_array_elements(coalesce(v_add_acc -> 'chg_skip', '[]'::jsonb)) s;                        -- 건너뛴 비용은 원문 순서(charge_date · charge_number · id)로 · 입고 skip 뒤에 잇는다(원문과 같은 자리)
  v_ims_skip := v_ims_skip || v_add_j;
  select coalesce(sum(amount), 0) into v_landed_amt from inv_layer_cost_add where kind = 'landed' and ref_number is null;   -- cogs-1: 옛 판은 이 합을 IMS 비용을 얹기 전에 읽어 실질 「불러온 landed 만」이었다 — 자리가 뒤로 가므로 그 뜻을 술어로 굳힌다(불러온 landed 는 ref_number 가 비어 있고 IMS 비용은 발주·트랜스퍼 번호가 든다 · 반환 landed_amount 무변)

  -- orphan — 대응 purchase 레이어가 없는 landed 키 (조인에서 조용히 빠지므로 따로 센다)
  select count(*) into v_landed_orph
    from (select distinct c.doc_number, c.line_ref, c.sku, c.warehouse
            from inv_cost c
            where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)) k
    where not exists (select 1 from inv_layer x
                        where x.origin_type = 'purchase' and x.doc_number = k.doc_number and x.line_ref = k.line_ref
                          and x.sku = k.sku and x.warehouse = k.warehouse);

  select coalesce(sum(amount), 0) into v_fr_amt from inv_layer_cost_add where kind = 'transfer_freight';


  -- 방문하지 않은 확정 비용 — 위 exists 가 거른 것. 금액은 창구와 같은 규칙으로 CAD(기준통화면 ×1 · 아니면 × exchange_rate). ⚠️ 환율 null 인 외화 비용은 합에서 빠진다(확정 게이트 ⑥ 뒤엔 없다 · 건수에는 든다).
  select count(*), coalesce(sum(c.total_amount * case when cu.code is not distinct from k.value then 1 else c.exchange_rate end), 0)
    into v_ims_chg_unvisited, v_ims_chg_unvisited_amt
    from po_charge c
    join ref_currency cu on cu.id = c.currency_id
    left join inv_config k on k.key = 'base_currency'
    where c.status = 'confirmed' and c.confirmed_at is not null
      and (p_until is null or c.charge_date <= p_until)
      and not (exists (select 1
                        from po_charge_alloc a
                        join po_line  pl on pl.po_id = a.po_id
                        join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                        where a.po_charge_id = c.id)
               or exists (select 1                                                       -- tr-4: 트랜스퍼 배분(위 루프와 같은 조건)
                            from po_charge_alloc a
                            join inv_transfer t on t.id = a.transfer_id
                            join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%'   -- inv-basis-3(판정 95 ㉓) — 위 루프와 같은 조건
                            where a.po_charge_id = c.id));

  -- ═══ tr-4b(판정 79) 얹힌 원가 따라가기 — 마지막 한 바퀴 ═══
  -- 왜 끝인가: 얹힌 행(불러온 landed · transfer_freight · IMS 비용)은 레이어를 다 세운 뒤 위 블록들이 넣는다 — 재생 중 창구가 부른 inv_layer_carry 는 부모에 아직 얹힌 것이 없어 0 이다.
  --   그래서 IMS 트랜스퍼의 자식 레이어(origin transfer · parent 있음 · 문서가 inv_transfer 에 있음)를 id 순(부모 먼저)으로 한 번 더 돈다 · 멱등(같은 행은 다시 넣지 않는다) — 실시간과 같은 결과.
  --   불러온 데이터 축의 트랜스퍼(문서가 inv_transfer 에 없다)는 건드리지 않는다.
  for v_ims_carry in
    select y.id from inv_layer y
     where y.origin_type = 'transfer' and y.parent_layer_id is not null and exists (select 1 from inv_transfer t where t.transfer_number = y.doc_number)
     order by y.id
  loop
    v_ims_carry_rows := v_ims_carry_rows + inv_layer_carry(v_ims_carry.id);
  end loop;
  select coalesce(sum(amount), 0) into v_ims_carry_amt from inv_layer_cost_add where kind = 'carried';

  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                                     'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
              and (p_until is null or occurred_on <= p_until)
            group by event_type) s;

  return jsonb_build_object(
    'until',                     p_until,
    'processed_po_in',           v_po,
    'processed_sale_out',        v_sale,
    'sale_keys_processed',       v_sale_keys,
    'sale_keys_fully_reversed',  v_sale_rev,
    'processed_transfer',        v_tr,
    'transfer_layers_created',   v_tr_layers,
    'transfer_orphan_in',        v_tr_orphan,
    'transfer_keys_net_zero',    v_tr_nz,
    'transfer_unknown_layers',   v_tr_unk,
    'transfer_unknown_qty',      v_tr_unkq,
    'transfer_out_unpaired',     v_tr_unpaired,
    'processed_adjust',          v_adj,
    'adjust_layers_created',     v_adj_layers,
    'adjust_consume_rows',       v_adj_rows,
    'adjust_unknown_layers',     v_adj_unk,
    'adjust_new_net_zero',       v_adj_new_nz,
    'processed_assembly',        v_asm,
    'assembly_layers_created',   v_asm_layers,
    'assembly_consume_rows',     v_asm_rows,
    'assembly_partial_cost',     v_asm_partial,
    'assembly_net_zero',         v_asm_nz,
    'assembly_out_unpaired',     v_asm_unpaired,
    'processed_credit',          v_cr,
    'credit_layers_created',     v_cr_layers,
    'credit_traced',             v_cr_traced,
    'credit_avg',                v_cr_avg,
    'credit_unknown_layers',     v_cr_unk,
    'credit_net_zero',           v_cr_nz,
    'landed_rows',               v_landed_rows,
    'landed_amount',             v_landed_amt,
    'landed_orphan',             v_landed_orph,
    'freight_rows',              v_fr_rows,
    'freight_amount',            v_fr_amt,
    'freight_docs',              v_fr_docs,
    'freight_no_basis',          v_fr_nobasis,
    'freight_no_basis_amount',   v_fr_nobasis_amt,
    'freight_orphan',            v_fr_orphan,
    'freight_multi_ref',         v_fr_multi,
    -- ⭐ IMS (2026-09-20) — 한 칸에 중첩한다. ⚠️ jsonb_build_object 는 인자 100개 한도(키 50) — 기존 45키에 평면으로 더하면 넘는다. 기존 45칸은 이름·뜻 무변.
    'ims', jsonb_build_object(
      'receipts_posted',           v_ims_rcv,               -- 창구가 레이어를 만든 입고 수
      'layers_created',            v_ims_rcv_layers,        -- 그 레이어 행 수(라인 단위 · bin 접힘)
      'layers_existing',           v_ims_rcv_exist,         -- 0 이어야 한다
      'layers_cost_cad',           v_ims_rcv_cost,          -- Σ qty × unit_cost(CAD)
      'receipts_skipped',          v_ims_rcv_skipped,       -- ⚠️ 창구가 거부해 건너뛴 입고 수 — skip_reasons 에 문장
      'charges_posted',            v_ims_chg_n,
      'charge_rows',               v_ims_chg_rows,          -- cost_add 행 수
      'charge_amount_cad',         v_ims_chg_amt,
      'charge_no_basis_amount_cad',  v_ims_chg_nobasis_amt,   -- 버린 금액(정본 D)
      'charge_no_layers_amount_cad', v_ims_chg_nolayers_amt,  -- 버린 금액(레이어 없는 발주)
      'charge_already_posted',     v_ims_chg_already,       -- 0 이어야 한다
      'charges_skipped',           v_ims_chg_skipped,       -- ⚠️ 창구가 거부해 건너뛴 비용 수
      'charges_unvisited',         v_ims_chg_unvisited,     -- 배분된 발주 어디에도 IMS 레이어가 없어 부르지 않은 확정 비용 수
      'charges_unvisited_amount_cad', v_ims_chg_unvisited_amt,  -- 그 금액 — 설명된 차이
      'over_posted',               v_ims_over_n,            -- ⭐ 2026-09-20 초과분(over 닫기) — 창구가 레이어를 만든 차이 수
      'over_layers',               v_ims_over_layers,
      'over_skipped',              v_ims_over_skipped,      -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'over'
      'offpo_posted',              v_ims_offpo_n,           -- ⭐ ⑤-6c1 off-PO — 창구가 레이어를 만든 차이 수
      'offpo_layers',              v_ims_offpo_layers,
      'offpo_skipped',             v_ims_offpo_skipped,     -- ⚠️ 창구가 거부해 건너뛴 차이 수 — skip_reasons kind 'off_po'
      'bin_moves_passed',          v_bin_moves,             -- ⭐ trf-a 2026-09-28 raw.kind bin_move 인 칸 옮기기 행 수 — 창구가 있으니 skipped_by_event 의 transfer 두 키에 안 잡힌다(0 이 정상)
      'transfer_departs_posted',   v_ims_trd,               -- ⭐ tr-2 2026-09-28 raw.kind transfer 출발(doc × sku 키) — 창구가 레이어를 만든 수
      'transfer_depart_layers',    v_ims_trd_layers,        -- IN_TRANSIT 레이어 수
      'transfer_depart_consume_rows', v_ims_trd_rows,       -- 출발 창고 소진 행 수
      'transfer_depart_short_qty', v_ims_trd_short,         -- 출발 창고 레이어가 모자란 EA(불러온 축과 같이 short · 레이어 없음)
      'transfer_departs_skipped',  v_ims_trd_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_depart'
      'transfer_out_passed',       v_ims_trd_out,           -- 출발 out 행 수(leg 1 · tr-3a 부터 도착 leg 3 IN_TRANSIT out 도 여기) — skipped_by_event.transfer_out 에 안 잡힌다
      'transfer_arrivals_posted',  v_ims_tra,               -- ⭐ tr-3a 도착(doc × receipt × sku 키) — 창구가 레이어를 만든 수
      'transfer_arrive_layers',    v_ims_tra_layers,        -- 도착 창고 레이어 수
      'transfer_arrive_consume_rows', v_ims_tra_rows,       -- IN_TRANSIT 소진 행 수(문서 범위)
      'transfer_arrive_short_qty', v_ims_tra_short,         -- IN_TRANSIT 문서 레이어가 모자란 EA(불러온 축과 같이 short)
      'transfer_arrivals_skipped', v_ims_tra_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_arrive'
      'transfer_settles_posted',   v_ims_trs,               -- ⭐ tr-3b 정리 · 더 온 몫(lost · return_in · over_4 행마다) — 창구가 소진 · 레이어를 만든 수
      'transfer_settle_layers',    v_ims_trs_layers,        -- 되돌린 · 더 보낸 몫의 레이어 수(lost 는 0)
      'transfer_settle_consume_rows', v_ims_trs_rows,       -- 소진 행 수
      'transfer_settle_short_qty', v_ims_trs_short,         -- 문서 레이어가 모자란 EA
      'transfer_settles_skipped',  v_ims_trs_skipped,       -- ⚠️ 창구가 거부해 건너뛴 수 — skip_reasons kind 'transfer_settle'
      'transfer_over_in_passed',   v_ims_trs_pass,          -- over_2 행 수(세고 지나감)
      'carried_rows',              v_ims_carry_rows,        -- ⭐ tr-4b(판정 79) 마지막 바퀴가 넣은 따라간 행 수(재생 중 창구가 넣은 것은 0 이라 = 전체)
      'carried_amount_cad',        v_ims_carry_amt,         -- kind carried 합
      'skipped_by_event',          v_ims_gate,              -- ⭐ 2026-09-20 창구가 아직 없어 보조 함수에 보내지 않은 IMS 사건 수(종류별 · 여덟 키 항상) — 0 이 아니면 그 사건의 창구를 만들 때다
      'skip_reasons',              v_ims_skip),             -- [{kind receipt|charge · number · id · sqlstate · error}] — 이유 문장 그대로
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;
comment on function inv_layer_apply(date) is '⭐ 원가 레이어 전량 재생성(검산 도구 · 사람이 부를 때만 돈다 · cron 없음) — baseline 외 inv_layer · inv_layer_consume · inv_layer_cost_add 를 지우고 원장(inv_ledger · ⚠️ source 필터 없음 — cin7·manual·ims 전부)을 날짜순으로 다시 태운다. Cin7 줄은 inv_cost 로(보조 여섯), ⭐ IMS 줄(source ims)은 창구로 — 입고는 루프 안에서 inv_layer_post_receipt(입고 단위) · 초과분(:over)은 inv_layer_post_receipt_over(차이 단위) · ⭐ [cogs-1 2026-09-30 · 판정 109] 얹기 셋(불러온 landed · transfer_freight · IMS 비용 inv_layer_post_charge)은 끝이 아니라 날짜 경계(날이 바뀔 때 · 그날 첫 유출 앞 · 루프 끝)에서 속 함수 inv_layer_apply_flush_adds 가 제자리에 넣는다(같은 날 = 들어옴 → 얹기 → 나감 · 얹는 금액 · 대상 · 키 무변 · carry 한 바퀴는 끝 그대로) · ⭐ [ⓒ1 2026-09-25] 반품(credit_in · source ims)은 inv_layer_apply_credit_ims → inv_layer_post_credit(실시간과 같은 함수 · raw.cost.remainder hint) · Cin7 축 credit_in 은 inv_layer_apply_credit 그대로. [2026-09-20 보조 넷 문] 창구가 아직 없는 IMS 사건은 보조 함수에 보내지 않고 ims.skipped_by_event 에 종류별로 센다 · sale_out 은 그대로 소진(한 원장 FIFO). 창구가 거부한 것은 멈추지 않고 건너뛰어 센다 — ims.receipts_skipped · over_skipped · charges_skipped · skip_reasons[]. 권한: 시작에서 receiving·purchasing 쓰기 권한을 본다(psql 은 request.jwt.claims). 반환 45칸 무변 + ims{} 중첩. 원본 20260910141553 → 20260920142635 → 20260920171930 → 20260920181910 → 20260921161933 → 20260925012354 → … → 20260929195458 → 20260930140801';
revoke all on function public.inv_layer_apply(date) from public, anon, authenticated;   -- ⭐ 판정 31 — 재생성 계열은 사람이 psql(소유자)로만 · 재발행마다 같은 파일에 다시 적는다
