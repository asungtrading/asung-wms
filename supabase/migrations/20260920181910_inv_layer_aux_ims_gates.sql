-- ─────────────────────────────────────────────────────────────
-- 보조 함수 넷에 IMS 문을 낸다 — 창구는 만들지 않고 센다 (Asung-IMS · 2026-09-20)
--   ① inv_layer_apply_transfer_in   다시 냄 — ⭐ 원본 20260909235347:50~185(다섯 판 중 마지막 · grep 실측) · 더한 것: IMS 문(원장 행 읽은 직후)
--   ② inv_layer_apply_adjust        다시 냄 — 원본 20260909201223:63~160 · 같은 문
--   ③ inv_layer_apply_assemble      다시 냄 — 원본 20260909231134:107~189 · 같은 문(앵커는 「not found or event_type <> 'assemble_in'」 줄)
--   ④ inv_layer_apply_credit        다시 냄 — 원본 20260909231134:194~285 · 같은 문(앵커는 「… <> 'credit_in'」 줄)
--   ⑤ inv_layer_apply               다시 냄 — ⭐ 원본 20260920171930:570~1004(마지막 판 · grep 실측 · 20260920142635 → 171930) · 더한 것: 루프 첫머리 IMS 문(사건 종류별로 세고 continue) ·
--                                   *_unpaired 두 집계에서 ims 제외 · 반환 ims.skipped_by_event
--   ⚠️ 전부 create or replace · 시그니처 무변(out 인자도 무변 — 아래 「가) 나)」). 표 변경 없음 · 창구 없음.
--
-- ⭐ Caleb 판정 (2026-09-20): 「문만 낸다 — 창구는 만들지 않는다.」 po_in 때는 창구(inv_layer_post_receipt)가 있어 문을 내고 대신 불렀다. 나머지 넷은 그 창구가 아직 없다(트랜스퍼 모듈도 IMS 재고조정도 없다).
--   쓰지 않을 창구를 미리 만들면 맞는지 검증할 표본이 없다. 대신 **몇 건을 지나쳤는지 센다** — 조용히 지나가면 「IMS 트랜스퍼가 재고에 안 잡힌다」를 아무도 모른다. 0 이 아니면 창구를 만들 때가 됐다는 신호다.
-- ⭐ 왜 문이 필요한가 [실측 2026-09-20]: inv_layer_apply 루프에 source 필터가 없다 ⇒ IMS 원장 줄이 보조 함수로 간다 ⇒ inv_cost 에 없으니 unknown/평균 경로 ⇒ unit_cost 0 레이어가 **만들어진다**(po_in 실측 rcv_unknown 0→2).
--   사라지는 것보다 나쁘다 — 0 은 합계에 섞이고 그 행이 키 자리를 차지해 창구가 생겨도 멱등이 건너뛴다. 지금은 IMS 가 po_in 만 내서(source ims 4행 · 전부 po_in) 안 터질 뿐이다.
-- ⭐ 가) 나) (⬜1) — **나)** 본체가 가른다. out 인자를 더하면(가) create or replace 가 못 덮어 drop 이 필요하고 본체의 select * into 넷을 다시 맞춰야 한다 — 바뀐 줄이 늘고 얻는 것은 같은 숫자다.
--   나)는 본체 루프 첫머리에서 po_in·sale_out 이 아닌 행만 PK 조회 한 번으로 source 를 보고, IMS 면 사건 종류별로 세고 continue — 보조 함수를 부르지도 않는다. 원문 루프 select 는 그대로(더한 줄만).
--   그래도 보조 넷에 문을 **둔다**(Caleb) — 방어는 함수 자신에게 있어야 한다. 직접 호출 길은 오늘 inv_layer_apply 와 transfer_in 의 자기 재귀(IN_TRANSIT leg)뿐이지만(레포 grep 실측 · ts/js/html 0), 백필·수리 SQL 이 생길 수 있다.
--   ⚠️ 보조의 문은 po_in 과 같은 모양(조용히 return)이다 — 세는 것은 본체 하나가 한다(두 곳이 세면 같은 사건이 두 번 잡힌다).
-- ⭐ 두 leg (⬜4) — 본체가 transfer_out · manual_reversal · assemble_out 도 IMS 면 센다. out 은 대응 in 이 처리하므로 in 만 막아도 레이어는 안 서지만, transfer_out_unpaired · assembly_out_unpaired 「0 이어야 한다(생기면 신호)」가 IMS out 으로 오염된다
--   ⇒ 그 두 집계에서도 source <> 'ims' 를 더했다(add-only). IMS out leg 는 ims.skipped_by_event 한 곳에서만 보인다.
-- ⚠️ sale_out 에는 문이 없다(⬜6 실측 · 20260920142635 회신) — 소진은 출처를 안 보는 한 원장 FIFO 가 맞다. IMS 가 판매를 내는 날 그대로 소진된다.
--
-- 정본: ledger-design 4부 「✅ 해소 — inv_layer_apply() 에 IMS 판」 「미래의 같은 사고 — 보조 함수 넷」 · 「이식이 남긴 것」 ⬜⬜ · 지시서 ~/asung/prompts/ims-aux-gates.md · ⬜1~5 는 회신에
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① inv_layer_apply_transfer_in — 원본 20260909235347:50~185 + IMS 문 ═══
create or replace function inv_layer_apply_transfer_in(p_ledger_id bigint, p_until date,
                                                       out o_layers int, out o_rows int, out o_short int,
                                                       out o_orphan int, out o_net_zero int,
                                                       out o_unknown int, out o_unknown_qty numeric, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         inv_ledger%rowtype;
  v_out_wh  text;
  v_out     record;
  v_out_net numeric;
  v_in_net  numeric;
  v_it      record;
  v_rows int; v_short int; v_layers int; v_taken numeric; v_orphan int; v_nz int; v_unk int; v_unkq numeric; v_proc int;
  v_missing numeric;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_orphan := 0; o_net_zero := 0; o_unknown := 0; o_unknown_qty := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  -- ⭐⭐ IMS 문 (2026-09-20 · po_in 문 20260920142635 의 형제) — 이 줄은 우리 것이다. Cin7 방식으로 만들지 않는다.
  -- 왜: inv_cost 에는 IMS 사건이 없다(Cin7 을 거치지 않았다) ⇒ 아래 unknown/평균 경로로 빠져 unit_cost 0 레이어가 선다(po_in 실측 rcv_unknown 0→2 와 같은 사고).
  --     수량은 맞고 금액만 0 이라 조용하고, 그 행이 키 자리를 차지해 나중에 창구가 생겨도 멱등이 「이미 있다」로 건너뛴다 — 복구도 막힌다.
  -- ⚠️ 지금 IMS 는 po_in 만 낸다. 이 문은 transfer_in(두 leg 다 IMS) 을(를) 내기 시작하는 날을 위한 것이다 — 그날 창구를 만들어 여기서 부르면 된다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
  --    세는 것은 본체(inv_layer_apply · ims.skipped_by_event)가 한다 — 본체는 이 함수를 부르기 전에 source 로 가른다. 이 문은 직접 호출(백필·수리 · transfer_in 의 자기 재귀)을 위한 방어다.
  if r.source = 'ims' then
    return;
  end if;

  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'tr_in' and d.doc_number = r.doc_number and d.sku = r.sku
                and d.warehouse = r.warehouse and d.day = r.occurred_on) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse, day) values ('tr_in', r.doc_number, r.sku, r.warehouse, r.occurred_on);
  o_processed := 1;

  -- ⓪ 창고 in 인데 같은 (doc, sku) 의 IN_TRANSIT in 이 아직 안 처리됐으면 그것부터 (같은 날 id 순서 무관)
  if r.warehouse <> 'IN_TRANSIT' then
    for v_it in
      select id from inv_ledger i
        where i.doc_number = r.doc_number and i.sku = r.sku and i.warehouse = 'IN_TRANSIT' and i.event_type = 'transfer_in'
          and i.occurred_on <= r.occurred_on and (p_until is null or i.occurred_on <= p_until)
          and not exists (select 1 from inv_layer_apply_done d
                            where d.kind = 'tr_in' and d.doc_number = i.doc_number and d.sku = i.sku
                              and d.warehouse = 'IN_TRANSIT' and d.day = i.occurred_on)
        order by i.occurred_on, i.id
    loop
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_unk, v_unkq, v_proc from inv_layer_apply_transfer_in(v_it.id, p_until);
      o_layers := o_layers + v_layers; o_rows := o_rows + v_rows; o_short := o_short + v_short;
      o_orphan := o_orphan + v_orphan; o_net_zero := o_net_zero + v_nz;
      o_unknown := o_unknown + v_unk; o_unknown_qty := o_unknown_qty + v_unkq;
    end loop;
  end if;

  -- ⓪′ in leg 순액 — ⭐ 그 날짜만 (중복 방지 키와 같은 범위) · 0 이하면 상쇄로 소멸한 키
  select sum(qty_delta) into v_in_net
    from inv_ledger
    where doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse and event_type = 'transfer_in'
      and occurred_on = r.occurred_on
      and (p_until is null or occurred_on <= p_until);
  if v_in_net is null or v_in_net <= 0 then
    o_net_zero := o_net_zero + 1;
    return;
  end if;

  -- ① 대응 out leg 의 창고 — ⭐ 같은 날짜의 out 만 (leg 쌍은 같은 날 안에서 완결 · 헤더)
  if r.warehouse = 'IN_TRANSIT' then
    select warehouse into v_out_wh
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse <> 'IN_TRANSIT'
        and event_type in ('transfer_out', 'manual_reversal')
        and occurred_on = r.occurred_on
        and (p_until is null or occurred_on <= p_until)
      order by id
      limit 1;
  else
    v_out_wh := 'IN_TRANSIT';
  end if;

  -- ② out leg 의 키 순액 × −1 — ⭐ 같은 날짜만
  if v_out_wh is not null then
    select -sum(qty_delta) into v_out_net
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = v_out_wh
        and event_type in ('transfer_out', 'manual_reversal')
        and occurred_on = r.occurred_on
        and (p_until is null or occurred_on <= p_until);
    select doc_type, line_ref, event_type, occurred_on into v_out
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = v_out_wh and event_type = 'transfer_out'
        and occurred_on = r.occurred_on
        and (p_until is null or occurred_on <= p_until)
      order by id
      limit 1;
  end if;

  if v_out_wh is null or v_out_net is null or v_out_net <= 0 or v_out is null then
    -- C-3 그 날짜에 대응 out **행 자체** 없음(방어 경로) — unknown 도착 레이어 · transfer_orphan_in
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'transfer', r.doc_number, r.line_ref, null,
            r.occurred_on, false, v_in_net, 0, 'unknown');
    o_layers := o_layers + 1;
    o_orphan := o_orphan + 1;
    return;
  end if;

  -- ④ out 키 기록 — ⭐ 날짜 포함 (main 의 unpaired 집계와 같은 키)
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse, day) values ('tr_out', r.doc_number, r.sku, v_out_wh, r.occurred_on)
    on conflict do nothing;

  -- ②③ 출발 FIFO 소진 + 소진한 레이어마다 도착 레이어 (parent_layer 복사)
  --    출발이 IN_TRANSIT 이면 같은 문서의 레이어만 (p_doc_scope = r.doc_number · 20260909233729) · 실제 창고 출발은 전체 FIFO (null)
  select * into v_rows, v_short, v_layers, v_taken
    from inv_layer_fifo_take(r.sku, v_out_wh, v_out_net,
                             v_out.doc_type, r.doc_number, v_out.line_ref, v_out.event_type, v_out.occurred_on,
                             'transfer', r.warehouse,
                             case when v_out_wh = 'IN_TRANSIT' then r.doc_number else null end);
  o_rows := o_rows + v_rows; o_layers := o_layers + v_layers;

  -- 부족분 — 기초 이전 출발(IN_TRANSIT 출발 · 쌍1 이 원장에 없음 · ⚠️ 문서 단위 판정)만 도착 창고에 원가 미상 레이어 (20260909190145).
  --    그 외 부족(창고 출발 · 쌍1 이 있는 IN_TRANSIT 부족 = 전파된 것)은 종전대로 short.
  v_missing := v_out_net - coalesce(v_taken, 0);
  if v_missing > 0 then
    if v_out_wh = 'IN_TRANSIT'
       and not exists (select 1 from inv_ledger i
                         where i.doc_number = r.doc_number and i.sku = r.sku and i.warehouse = 'IN_TRANSIT'
                           and i.event_type = 'transfer_in'
                           and (p_until is null or i.occurred_on <= p_until)) then
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'transfer', r.doc_number, r.line_ref, null,
              r.occurred_on, false, v_missing, 0, 'unknown');
      o_layers := o_layers + 1;
      o_unknown := o_unknown + 1;
      o_unknown_qty := o_unknown_qty + v_missing;
    else
      o_short := o_short + 1;
    end if;
  end if;
end;
$$;

-- ═══ ② inv_layer_apply_adjust — 원본 20260909201223:63~160 + IMS 문 ═══
create or replace function inv_layer_apply_adjust(p_ledger_id bigint, p_until date,
                                                  out o_layers int, out o_rows int, out o_short int,
                                                  out o_unknown int, out o_new_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r        inv_ledger%rowtype;
  v_kind   text;
  v_net    numeric;
  v_unit   numeric;
  v_src    text;
  v_rem    numeric;      -- 남은 레이어 합
  v_remval numeric;      -- 남은 레이어 × 단가 합
  v_wq     numeric;      -- adjust_new: UnitCost 있는 양수 행의 qty 합
  v_wv     numeric;      -- adjust_new: qty × UnitCost 합
  v_rows int; v_short int; v_layers int; v_taken numeric;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_unknown := 0; o_new_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  -- ⭐⭐ IMS 문 (2026-09-20 · po_in 문 20260920142635 의 형제) — 이 줄은 우리 것이다. Cin7 방식으로 만들지 않는다.
  -- 왜: inv_cost 에는 IMS 사건이 없다(Cin7 을 거치지 않았다) ⇒ 아래 unknown/평균 경로로 빠져 unit_cost 0 레이어가 선다(po_in 실측 rcv_unknown 0→2 와 같은 사고).
  --     수량은 맞고 금액만 0 이라 조용하고, 그 행이 키 자리를 차지해 나중에 창구가 생겨도 멱등이 「이미 있다」로 건너뛴다 — 복구도 막힌다.
  -- ⚠️ 지금 IMS 는 po_in 만 낸다. 이 문은 adjust_existing·adjust_new(IMS 재고조정) 을(를) 내기 시작하는 날을 위한 것이다 — 그날 창구를 만들어 여기서 부르면 된다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
  --    세는 것은 본체(inv_layer_apply · ims.skipped_by_event)가 한다 — 본체는 이 함수를 부르기 전에 source 로 가른다. 이 문은 직접 호출(백필·수리 · transfer_in 의 자기 재귀)을 위한 방어다.
  if r.source = 'ims' then
    return;
  end if;
  v_kind := case r.event_type when 'adjust_existing' then 'adj_ex' when 'adjust_new' then 'adj_new' end;
  if v_kind is null then return; end if;

  -- 처리한 키는 건너뛴다 (doc, sku, wh · event_type 별)
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = v_kind and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values (v_kind, r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 키 순액 (source 무관 · line_ref 키 제외 · p_until 안)
  select sum(qty_delta) into v_net
    from inv_ledger
    where event_type = r.event_type and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);

  if r.event_type = 'adjust_existing' then
    if v_net > 0 then
      -- A-1 증가 — 남은 레이어 가중평균 (직접 계산)
      select coalesce(sum(rem), 0), coalesce(sum(rem * unit_cost), 0) into v_rem, v_remval
        from (select x.unit_cost,
                     x.qty - coalesce((select sum(c.qty) from inv_layer_consume c where c.layer_id = x.id), 0) as rem
                from inv_layer x where x.sku = r.sku and x.warehouse = r.warehouse) t
        where rem > 0;
      if v_rem > 0 then
        v_unit := round(v_remval / v_rem, 6); v_src := 'layer_avg';
      else
        v_unit := 0; v_src := 'unknown'; o_unknown := o_unknown + 1;   -- A-2 방어 · 표본 대기
      end if;
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'adjust_existing', r.doc_number, r.line_ref, null,
              r.occurred_on, true, v_net, v_unit, v_src);
      o_layers := o_layers + 1;
    elsif v_net < 0 then
      -- A-3 감소 — FIFO 소진 · reason 'adjust_out' · 부족은 short (원가 미상 레이어 없음)
      select * into v_rows, v_short, v_layers, v_taken
        from inv_layer_fifo_take(r.sku, r.warehouse, -v_net,
                                 r.doc_type, r.doc_number, r.line_ref, r.event_type, r.occurred_on, 'adjust_out', null);
      o_rows := o_rows + v_rows; o_short := o_short + v_short;
    end if;
    -- v_net = 0: 아무것도 하지 않는다 (실측 0건 — 헤더)
    return;
  end if;

  -- B. adjust_new
  if v_net is null or v_net <= 0 then
    o_new_net_zero := o_new_net_zero + 1;   -- 상쇄로 소멸
    return;
  end if;
  select coalesce(sum(qty_delta), 0),
         coalesce(sum(qty_delta * (raw -> 'line' ->> 'UnitCost')::numeric), 0)
    into v_wq, v_wv
    from inv_ledger
    where event_type = 'adjust_new' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until)
      and qty_delta > 0
      and (raw -> 'line' ->> 'UnitCost') ~ '^-?[0-9]+(\.[0-9]+)?$';   -- 읽을 수 있는 값만
  if v_wq > 0 then
    v_unit := round(v_wv / v_wq, 6); v_src := 'cin7_unitcost';       -- 0 이면 0 으로 쌓는다 (프로모션 무상 재고 · 정상)
    -- UnitCost 가드 (헤더) — 읽었는데 음수면 거부. 0 은 통과 · 읽을 수 없으면 아래 unknown 경로.
    if v_unit < 0 then
      raise exception 'adjust_new UnitCost (qty-weighted) is negative for % / % / %: % — refusing to build layer (typo in Cin7? inspect raw.line.UnitCost)',
        r.doc_number, r.sku, r.warehouse, v_unit;
    end if;
  else
    v_unit := 0; v_src := 'unknown'; o_unknown := o_unknown + 1;
  end if;
  insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                         received_on, age_known, qty, unit_cost, cost_source)
  values (r.sku, r.warehouse, 'adjust_new', r.doc_number, r.line_ref, null,
          r.occurred_on, true, v_net, v_unit, v_src);
  o_layers := o_layers + 1;
end;
$$;

-- ═══ ③ inv_layer_apply_assemble — 원본 20260909231134:107~189 + IMS 문 ═══
create or replace function inv_layer_apply_assemble(p_ledger_id bigint, p_until date,
                                                    out o_layers int, out o_rows int, out o_short int,
                                                    out o_partial int, out o_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r            inv_ledger%rowtype;
  v_in_net     numeric;
  v_fg_keys    int;
  v_part_keys  int := 0;
  v_partial    boolean := false;
  v_cost       numeric;
  p            record;
  v_rows int; v_short int; v_layers int; v_taken numeric;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_partial := 0; o_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found or r.event_type <> 'assemble_in' then return; end if;

  -- ⭐⭐ IMS 문 (2026-09-20 · po_in 문 20260920142635 의 형제) — 이 줄은 우리 것이다. Cin7 방식으로 만들지 않는다.
  -- 왜: inv_cost 에는 IMS 사건이 없다(Cin7 을 거치지 않았다) ⇒ 아래 unknown/평균 경로로 빠져 unit_cost 0 레이어가 선다(po_in 실측 rcv_unknown 0→2 와 같은 사고).
  --     수량은 맞고 금액만 0 이라 조용하고, 그 행이 키 자리를 차지해 나중에 창구가 생겨도 멱등이 「이미 있다」로 건너뛴다 — 복구도 막힌다.
  -- ⚠️ 지금 IMS 는 po_in 만 낸다. 이 문은 assemble_in(IMS 조립) 을(를) 내기 시작하는 날을 위한 것이다 — 그날 창구를 만들어 여기서 부르면 된다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
  --    세는 것은 본체(inv_layer_apply · ims.skipped_by_event)가 한다 — 본체는 이 함수를 부르기 전에 source 로 가른다. 이 문은 직접 호출(백필·수리 · transfer_in 의 자기 재귀)을 위한 방어다.
  if r.source = 'ims' then
    return;
  end if;

  -- 처리한 in 키는 건너뛴다 (doc, sku, wh · assemble_in 만)
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'asm_in' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('asm_in', r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 완제품 키 순액 (source 무관 · line_ref 키 제외 · p_until 안)
  select sum(qty_delta) into v_in_net
    from inv_ledger
    where event_type = 'assemble_in' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_in_net is null or v_in_net <= 0 then
    o_net_zero := 1;            -- A-4 전량 상쇄 · 부품도 건드리지 않는다
    return;
  end if;

  -- A-2 가드 — 한 문서에 완제품 키가 둘 이상이면 배분 근거가 없다
  select count(*) into v_fg_keys
    from (select sku, warehouse from inv_ledger
            where event_type = 'assemble_in' and doc_number = r.doc_number
              and (p_until is null or occurred_on <= p_until)
            group by sku, warehouse having sum(qty_delta) > 0) k;
  if v_fg_keys > 1 then
    raise exception 'assembly % has % finished-goods keys with positive net (expected 1) — cannot allocate parts cost, refusing to build layer',
      r.doc_number, v_fg_keys;
  end if;

  -- ①② 같은 문서의 부품 키 — 순액만큼 FIFO 소진 · reason 'assembly_in' · out 키 기록(뒤에 만나면 건너뛴다)
  for p in
    select sku, warehouse, -sum(qty_delta) as need, min(occurred_on) as occurred_on,
           (array_agg(line_ref order by (source = 'cin7') desc, id))[1] as line_ref
      from inv_ledger
      where event_type = 'assemble_out' and doc_number = r.doc_number
        and (p_until is null or occurred_on <= p_until)
      group by sku, warehouse
  loop
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('asm_out', r.doc_number, p.sku, p.warehouse)
      on conflict do nothing;
    if p.need <= 0 then continue; end if;      -- 상쇄로 소멸한 부품 키
    v_part_keys := v_part_keys + 1;
    select * into v_rows, v_short, v_layers, v_taken
      from inv_layer_fifo_take(p.sku, p.warehouse, p.need,
                               r.doc_type, r.doc_number, p.line_ref, 'assemble_out', p.occurred_on, 'assembly_in', null);
    o_rows := o_rows + v_rows; o_short := o_short + v_short;
    if v_short > 0 then v_partial := true; end if;   -- A-3 있는 만큼만 · 원가 미상 레이어 없음
  end loop;
  if v_part_keys = 0 then v_partial := true; end if;  -- 부품이 하나도 없다 (방어 · 실측 0건)

  -- ③ 소진 금액 합 → 완제품 레이어 (소진 기록에서 읽는다 · 전량 재생성이라 낡은 행이 없다)
  select coalesce(sum(amount), 0) into v_cost
    from inv_layer_consume
    where doc_type = r.doc_type and doc_number = r.doc_number and reason = 'assembly_in';
  insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                         received_on, age_known, qty, unit_cost, cost_source)
  values (r.sku, r.warehouse, 'assembly', r.doc_number, r.line_ref, null,
          r.occurred_on, true, v_in_net, round(v_cost / v_in_net, 6), 'assembly_sum');
  o_layers := 1;
  if v_partial then o_partial := 1; end if;
end;
$$;

-- ═══ ④ inv_layer_apply_credit — 원본 20260909231134:194~285 + IMS 문 ═══
create or replace function inv_layer_apply_credit(p_ledger_id bigint, p_until date,
                                                  out o_layers int, out o_traced int, out o_avg int,
                                                  out o_unknown int, out o_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         inv_ledger%rowtype;
  v_net     numeric;
  v_need    numeric;
  v_so      text;
  v_take    numeric;
  v_rem     numeric;
  v_remval  numeric;
  c         record;
begin
  o_layers := 0; o_traced := 0; o_avg := 0; o_unknown := 0; o_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found or r.event_type <> 'credit_in' then return; end if;

  -- ⭐⭐ IMS 문 (2026-09-20 · po_in 문 20260920142635 의 형제) — 이 줄은 우리 것이다. Cin7 방식으로 만들지 않는다.
  -- 왜: inv_cost 에는 IMS 사건이 없다(Cin7 을 거치지 않았다) ⇒ 아래 unknown/평균 경로로 빠져 unit_cost 0 레이어가 선다(po_in 실측 rcv_unknown 0→2 와 같은 사고).
  --     수량은 맞고 금액만 0 이라 조용하고, 그 행이 키 자리를 차지해 나중에 창구가 생겨도 멱등이 「이미 있다」로 건너뛴다 — 복구도 막힌다.
  -- ⚠️ 지금 IMS 는 po_in 만 낸다. 이 문은 credit_in(IMS 반품) 을(를) 내기 시작하는 날을 위한 것이다 — 그날 창구를 만들어 여기서 부르면 된다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
  --    세는 것은 본체(inv_layer_apply · ims.skipped_by_event)가 한다 — 본체는 이 함수를 부르기 전에 source 로 가른다. 이 문은 직접 호출(백필·수리 · transfer_in 의 자기 재귀)을 위한 방어다.
  if r.source = 'ims' then
    return;
  end if;

  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'credit' and d.doc_number = r.doc_number and d.sku = r.sku and d.warehouse = r.warehouse) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('credit', r.doc_number, r.sku, r.warehouse);
  o_processed := 1;

  -- 키 순액 (source 무관 · line_ref 키 제외 · p_until 안)
  select sum(qty_delta) into v_net
    from inv_ledger
    where event_type = 'credit_in' and doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse
      and (p_until is null or occurred_on <= p_until);
  if v_net is null or v_net <= 0 then
    o_net_zero := 1;
    return;
  end if;
  v_need := v_net;

  -- 갈래 ① — 원 판매(raw.header.order_number)가 소진한 레이어를 같은 단가로 되돌린다 (소비된 순서 · sku 로 매칭)
  v_so := r.raw -> 'header' ->> 'order_number';
  if v_so is not null then
    for c in
      select s.layer_id, s.unit_cost,
             s.qty - coalesce((select sum(x.qty) from inv_layer x
                                 where x.origin_type = 'creditnote' and x.cost_source = 'return_restore'
                                   and x.parent_layer_id = s.layer_id
                                   and x.doc_number in (select distinct e.doc_number from inv_ledger e
                                                          where e.event_type = 'credit_in'
                                                            and e.raw -> 'header' ->> 'order_number' = v_so)), 0) as avail
        from (select cs.layer_id, cs.unit_cost, sum(cs.qty) as qty, min(l.received_on) as received_on
                from inv_layer_consume cs join inv_layer l on l.id = cs.layer_id
                where cs.doc_type = 'sale' and cs.doc_number = v_so and cs.reason = 'sale' and l.sku = r.sku
                group by cs.layer_id, cs.unit_cost) s
        order by s.received_on, s.layer_id
    loop
      exit when v_need <= 0;
      if c.avail <= 0 then continue; end if;     -- 앞선 크레딧노트가 이미 되돌린 몫
      v_take := least(c.avail, v_need);
      insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                             received_on, age_known, qty, unit_cost, cost_source)
      values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, c.layer_id,
              r.occurred_on, true, v_take, c.unit_cost, 'return_restore');
      o_layers := o_layers + 1;
      o_traced := 1;
      v_need := v_need - v_take;
    end loop;
  end if;
  if v_need <= 0 then return; end if;

  -- 갈래 ② — 남은 레이어 가중평균 (adjust_existing A-1 과 같은 규칙 · 그 시점까지의 레이어만)
  select coalesce(sum(rem), 0), coalesce(sum(rem * unit_cost), 0) into v_rem, v_remval
    from (select x.unit_cost,
                 x.qty - coalesce((select sum(k.qty) from inv_layer_consume k where k.layer_id = x.id), 0) as rem
            from inv_layer x where x.sku = r.sku and x.warehouse = r.warehouse) t
    where rem > 0;
  if v_rem > 0 then
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, null,
            r.occurred_on, true, v_need, round(v_remval / v_rem, 6), 'layer_avg');
    o_avg := 1;
  else
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'creditnote', r.doc_number, r.line_ref, null,
            r.occurred_on, true, v_need, 0, 'unknown');
    o_avg := 1; o_unknown := 1;       -- ② 를 탔으나 근거가 없었다
  end if;
  o_layers := o_layers + 1;
end;
$$;

-- ═══ ⑤ inv_layer_apply — 원본 20260920171930:570~1004 + 루프 첫머리 IMS 문 · unpaired 둘 ims 제외 · 반환 ims.skipped_by_event ═══
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
  v_doc         record;
  v_grp         record;
  v_fr_n        int;
  v_fr_basis    numeric;
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
  v_ims_chg     record;
  v_ims_rcv         int := 0;   v_ims_rcv_layers int := 0;   v_ims_rcv_exist int := 0;   v_ims_rcv_cost numeric := 0;   v_ims_rcv_skipped int := 0;
  v_ims_chg_n       int := 0;   v_ims_chg_rows   int := 0;   v_ims_chg_amt   numeric := 0;
  v_ims_chg_nobasis_amt  numeric := 0;   v_ims_chg_nolayers_amt numeric := 0;   v_ims_chg_already int := 0;   v_ims_chg_skipped int := 0;
  v_ims_chg_unvisited int := 0;   v_ims_chg_unvisited_amt numeric := 0;
  v_ims_skip    jsonb := '[]'::jsonb;
  -- IMS 초과분 (2026-09-20 · over 닫기) — 형제 창구 inv_layer_post_receipt_over 의 반환을 합친다
  v_ims_over    text;
  v_ims_over_n  int := 0;   v_ims_over_layers int := 0;   v_ims_over_skipped int := 0;
  -- IMS 문 · 보조 넷 (2026-09-20) — 창구가 아직 없는 IMS 사건을 사건 종류별로 센다(0 이 아니면 그 창구를 만들 때다). sale_out 은 없다(문 불필요).
  v_ims_gate    jsonb := '{"transfer_in": 0, "transfer_out": 0, "manual_reversal": 0, "adjust_existing": 0, "adjust_new": 0, "assemble_in": 0, "assemble_out": 0, "credit_in": 0}'::jsonb;
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

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, id · source 필터 없음)
  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, id
  loop
    -- ⭐⭐ IMS 문 · 보조 넷 (2026-09-20 · po_in 문의 형제 · Caleb 「문만 낸다 — 창구는 만들지 않는다」) — 창구가 아직 없는 IMS 사건은 보조 함수에 보내지 않고 사건 종류별로 센다.
    -- 왜 안 보내나: 보조 넷(transfer_in · adjust · assemble · credit)은 원가를 inv_cost / 레이어 평균에서 찾는다. IMS 사건은 거기 없어 unit_cost 0 · 'unknown' 레이어가 선다 — po_in 에서 실측된 사고(rcv_unknown 0→2)와 같다.
    -- 왜 창구를 지금 안 만드나: 트랜스퍼 모듈도 IMS 재고조정도 아직 없다 — 쓰지 않을 창구는 맞는지 검증할 표본이 없다. 그 사건을 내는 날 창구를 만들고 여기서 부른다(po_in 이 inv_layer_post_receipt 를 부르는 모양).
    -- 왜 세나: 조용히 지나가면 「IMS 트랜스퍼가 재고에 안 잡힌다」를 아무도 모른다. ims.skipped_by_event 가 0 이 아니면 창구를 만들 때가 됐다는 신호다.
    -- ⚠️ sale_out 은 세지도 막지도 않는다 — 소진은 출처를 안 보는 한 원장 FIFO 가 맞다(inv_layer_fifo_take). po_in 은 아래 분기가 창구로 처리한다.
    -- ⭐ 두 leg 다 막는다(⬜4) — transfer_out · manual_reversal · assemble_out 도 IMS 면 여기서 센다. out 은 대응 in 이 처리하므로 in 만 막아도 레이어는 안 서지만, 아래 *_unpaired 신호가 IMS 것으로 오염된다(그 집계에서도 ims 를 뺀다).
    -- 원문 루프 select(id, event_type)는 바꾸지 않는다 — po_in·sale_out 이 아닌 행만 PK 조회 한 번(po_in 은 아래 분기가 이미 조회한다).
    if r.event_type not in ('po_in', 'sale_out') then
      select source into v_ims_src from inv_ledger where id = r.id;
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
      select source, doc_task_id, doc_number into v_ims_src, v_ims_task, v_ims_docno from inv_ledger where id = r.id;   -- 루프 select 는 바꾸지 않는다(원문 무변) — PK 조회 한 번
      if v_ims_src = 'ims' and v_ims_task is not null
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
      select * into v_layers, v_rows, v_short, v_unk, v_nz, v_proc from inv_layer_apply_adjust(r.id, p_until);
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
      select * into v_layers, v_traced, v_avg, v_unk, v_nz, v_proc from inv_layer_apply_credit(r.id, p_until);
      v_cr := v_cr + 1; v_cr_layers := v_cr_layers + v_layers; v_cr_traced := v_cr_traced + v_traced;
      v_cr_avg := v_cr_avg + v_avg; v_cr_unk := v_cr_unk + v_unk; v_cr_nz := v_cr_nz + v_nz;
    else
      v_tr := v_tr + 1;   -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다
    end if;
  end loop;

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

  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — 레이어가 전부 만들어진 뒤 집합 연산 한 번 ═══
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
    group by x.id, c.occurred_on, c.doc_number, c.line_ref;
  get diagnostics v_landed_rows = row_count;
  select coalesce(sum(amount), 0) into v_landed_amt from inv_layer_cost_add where kind = 'landed';

  -- orphan — 대응 purchase 레이어가 없는 landed 키 (조인에서 조용히 빠지므로 따로 센다)
  select count(*) into v_landed_orph
    from (select distinct c.doc_number, c.line_ref, c.sku, c.warehouse
            from inv_cost c
            where c.cost_kind = 'landed' and (p_until is null or c.occurred_on <= p_until)) k
    where not exists (select 1 from inv_layer x
                        where x.origin_type = 'purchase' and x.doc_number = k.doc_number and x.line_ref = k.line_ref
                          and x.sku = k.sku and x.warehouse = k.warehouse);

  -- ═══ 트랜스퍼 운송비 → inv_layer_cost_add (kind='transfer_freight' · 2026-09-10 · 헤더 B) — landed 와 같은 자리 ═══
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

  -- 문서 단위 루프 — 배분 기준(도착 레이어 원가 합)은 문서에 딸린 레이어로 정해지므로 문서마다 한 번 계산한다
  for v_doc in
    select doc_number, sum(amount) as amount     -- amount: no_basis 로 떨어질 때 합산할 문서 금액 (p_until 범위)
      from inv_doc_cost
      where doc_type = 'transfer' and kind = 'transfer_freight'
        and (p_until is null or occurred_on <= p_until)
      group by doc_number
      order by doc_number
  loop
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
  select coalesce(sum(amount), 0) into v_fr_amt from inv_layer_cost_add where kind = 'transfer_freight';


  -- ═══ IMS 비용 → inv_layer_cost_add (kind='landed' · 2026-09-20) — landed·운송비와 같은 층 · 창구 inv_layer_post_charge 에 넘긴다 ═══
  -- 왜 여기(끝)인가: 비용은 수량이 아니라 금액만 얹는다 — FIFO 소진에 영향이 없어 Cin7 landed·운송비와 같은 자리다(입고 레이어는 루프 안 — 위).
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
        and exists (select 1
                      from po_charge_alloc a
                      join po_line  pl on pl.po_id = a.po_id
                      join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                      where a.po_charge_id = c.id)
      order by c.charge_date, c.charge_number, c.id       -- ⚠️ 순서 고정 · charge_number 는 (supplier_id, charge_number) 유니크라 id 까지 건다
  loop
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
      v_ims_skip := v_ims_skip || jsonb_build_object('kind', 'charge', 'number', v_ims_chg.charge_number, 'id', v_ims_chg.id, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  -- 방문하지 않은 확정 비용 — 위 exists 가 거른 것. 금액은 창구와 같은 규칙으로 CAD(기준통화면 ×1 · 아니면 × exchange_rate). ⚠️ 환율 null 인 외화 비용은 합에서 빠진다(확정 게이트 ⑥ 뒤엔 없다 · 건수에는 든다).
  select count(*), coalesce(sum(c.total_amount * case when cu.code is not distinct from k.value then 1 else c.exchange_rate end), 0)
    into v_ims_chg_unvisited, v_ims_chg_unvisited_amt
    from po_charge c
    join ref_currency cu on cu.id = c.currency_id
    left join inv_config k on k.key = 'base_currency'
    where c.status = 'confirmed' and c.confirmed_at is not null
      and (p_until is null or c.charge_date <= p_until)
      and not exists (select 1
                        from po_charge_alloc a
                        join po_line  pl on pl.po_id = a.po_id
                        join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line'
                        where a.po_charge_id = c.id);

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

revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
comment on function inv_layer_apply(date) is '⭐ 원가 레이어 전량 재생성(검산 도구 · 사람이 부를 때만 돈다 · cron 없음) — baseline 외 inv_layer · inv_layer_consume · inv_layer_cost_add 를 지우고 원장(inv_ledger · ⚠️ source 필터 없음 — cin7·manual·ims 전부)을 날짜순으로 다시 태운다. Cin7 줄은 inv_cost 로(보조 여섯), ⭐ IMS 줄(source ims)은 창구로 — 입고는 루프 안에서 inv_layer_post_receipt(입고 단위) · 초과분(:over)은 inv_layer_post_receipt_over(차이 단위) · 비용은 끝에서 inv_layer_post_charge. ⭐ [2026-09-20 보조 넷 문] 창구가 아직 없는 IMS 사건(transfer_in/out · manual_reversal · adjust_existing/new · assemble_in/out · credit_in)은 보조 함수에 보내지 않고 ims.skipped_by_event 에 종류별로 센다 — 0 이 아니면 그 창구를 만들 때다(0 원 레이어를 만들지 않는다) · sale_out 은 그대로 소진(한 원장 FIFO). 창구가 거부한 것은 멈추지 않고 건너뛰어 센다 — ims.receipts_skipped · over_skipped · charges_skipped · skip_reasons[]. 권한: 시작에서 receiving·purchasing 쓰기 권한을 본다(psql 은 request.jwt.claims). 반환 45칸 무변 + ims{} 중첩. 원본 20260910141553 → 20260920142635 → 20260920171930 → 20260920181910';
