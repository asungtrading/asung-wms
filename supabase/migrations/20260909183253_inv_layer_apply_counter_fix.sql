-- 원가 레이어 사건 적재 — transfer 카운터 거짓 신호 수정 (2026-09-09)
--
-- 20260909174046 의 inv_layer_apply_transfer_in · inv_layer_apply 를 덮어쓴다(그 파일은 테스트 DB 에 이미 적용돼 손대지 않는다).
-- 로직은 그대로고 **카운터를 올리는 자리**만 바꾼다 — 레이어 결과는 변하지 않는다.
--
-- ═══ 문제 — 카운터 둘이 평상시에 138 을 낸다 ═══
--  [실측 2026-09-09 테스트 DB · select inv_layer_apply()]  transfer_orphan_in 138 · transfer_out_unpaired 138  ⚠️ 둘 다 0 이어야 한다.
--  ⭐ 레이어는 정확하다 — origin_type='transfer' 2,641개 전부 cost_source='parent_layer' · unknown 0건.
--  ⇒ orphan 레이어를 하나도 만들지 않았는데 카운터만 138 을 센다.
--
--  [실측 TR-04175]
--    source |   event_type    |     warehouse      | occurred_on | rows |  net  | suffix
--    manual | manual_reversal | Asung Trading Inc. | 2026-08-21  |   57 |  1255 |      0
--    cin7   | transfer_in     | IN_TRANSIT         | 2026-08-21  |  195 |  2502 |      0
--    manual | transfer_in     | IN_TRANSIT         | 2026-08-21  |  138 | -1247 |    138
--    cin7   | transfer_out    | Asung Trading Inc. | 2026-08-21  |  252 | -3757 |      0
--    manual | transfer_out    | Asung Trading Inc. | 2026-08-21  |  138 |  1247 |    138
--    cin7   | transfer_in     | Asung - Edmonton   | 2026-09-02  |   57 |  1255 |      0
--    cin7   | transfer_out    | IN_TRANSIT         | 2026-09-02  |   57 | -1255 |      0
--  ⭐ 키 순액은 정확히 짝이다 — 8/21 IN_TRANSIT in leg +2,502 − 1,247 = +1,255 · 토론토 out leg −3,757 + 1,247 + 1,255 = −1,255.
--  ⇒ 계산은 맞고 카운터를 올리는 자리가 잘못됐다.
--
-- ═══ 원인 (코드 확인 · 로컬 재현 2026-09-09) ═══
--  · 종전 orphan 분기는 `o_orphan := 1` 을 **레이어를 만들었든 안 만들었든** 올렸다. 레이어는 in leg 순액(v_in_net) > 0 일 때만
--    만들어지므로, 「orphan 138 · unknown 0」은 **in leg 순액 ≤ 0 인 키 138개가 그 분기를 탔다**는 뜻이다(코드로 증명된다).
--  · 종전 unpaired 쿼리는 「tr_out 마크 없는 out 키」를 전부 셌다. 순액 ≤ 0 인 out 키(상쇄로 소멸)는 정상 경로를 타지 않아 마크가
--    없으므로 **거짓 신호**로 세어졌다(manual transfer_out 138행의 짝).
--  · ⚠️ 같은 키에 cin7 행과 상쇄 행이 함께 있으면 첫 행이 키를 처리하고 나머지는 dedup 으로 빠지므로 「상쇄 행 하나하나가 orphan 을
--    올린다」는 서술은 정확하지 않다 — 로컬 재현: TR-04175 모양(cin7 in · manual in · 새 in 같은 키)은 orphan 0 · unpaired 0,
--    **상쇄만 남아 순액 0 인 키**는 orphan 1 · unpaired 1 (레이어 0). 원인은 「행」이 아니라 「순액 ≤ 0 인 키」다.
--
-- ═══ 판정 기준 — 카운터는 「실제로 그 일이 일어났을 때만」 센다 ═══
--  ⭐ transfer_orphan_in = **orphan 도착 레이어(cost_source='unknown')를 실제로 만든 횟수**. 「대응 out 을 못 찾았다」만으로 세지 않는다.
--  ⭐ transfer_out_unpaired = **순액 > 0 인데 처리되지 않고 남은 out leg 키**. 순액 ≤ 0 인 out 키(상쇄로 소멸)는 제외.
--  ⭐ 새 카운터 transfer_keys_net_zero = 「상쇄로 소멸해 처리할 것이 없던 in 키」 수 — 평상시 값이 있어도 무해한 정보 카운터
--     (sale_keys_fully_reversed 와 같은 성격).
--
--  ⚠️⚠️ **상쇄 행은 부호가 반대다.** manual transfer_in 은 음수 · manual transfer_out 은 양수다(정상과 반대). ⇒ 키 순액이 0 이하인
--  leg 는 **처리할 것이 없는 것**이고 orphan 도 short 도 아니다 — 조용히 건너뛰고 transfer_keys_net_zero 로만 센다.
--  ⚠️ [사고 2026-09-09] 이것을 orphan 으로 세어 transfer_orphan_in 이 평상시에 138(= manual transfer_in 행 수)을 냈다.
--  ⭐ **그러면 「0 이 아니면 신호」라는 설계가 죽는다** — 스킬 「기준선 3을 외운다」와 같은 실패 모양이다. 기준선을 외우게 만들지 말 것.
--  📌 레이어 자체는 정확했다 — transfer 레이어 2,641개 전부 parent_layer · unknown 0건.
--
-- 반환 jsonb 추가: transfer_keys_net_zero. 나머지 키는 20260909174046 과 같다.

-- out 컬럼이 늘어 replace 가 안 된다 — 옛 시그니처 drop
drop function if exists inv_layer_apply_transfer_in(bigint, date);

-- ── 보조 3: transfer_in 한 행 → 대응 out 을 먼저 소진하고 도착 레이어 생성 (C · 카운터 자리만 수정) ──
--   o_layers = 도착 레이어 수 · o_rows = consume 행 수 · o_short = 출발 부족 · o_orphan = unknown 도착 레이어를 실제로 만든 수 ·
--   o_net_zero = in leg 순액 ≤ 0 이라 처리할 것이 없던 키 수 · o_processed = 이 호출이 in 키를 처리했으면 1
create or replace function inv_layer_apply_transfer_in(p_ledger_id bigint, p_until date,
                                                       out o_layers int, out o_rows int, out o_short int,
                                                       out o_orphan int, out o_net_zero int, out o_processed int)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r         inv_ledger%rowtype;
  v_out_wh  text;
  v_out     record;          -- 대응 out 대표 행 (doc_type · line_ref · event_type · occurred_on)
  v_out_net numeric;
  v_in_net  numeric;
  v_it      record;          -- 먼저 처리할 IN_TRANSIT in 행 (⓪)
  v_rows int; v_short int; v_layers int; v_taken numeric; v_orphan int; v_nz int; v_proc int;
begin
  o_layers := 0; o_rows := 0; o_short := 0; o_orphan := 0; o_net_zero := 0; o_processed := 0;
  select * into r from inv_ledger where id = p_ledger_id;
  if not found then return; end if;

  -- in 키 (doc, sku, 도착창고, 날짜) 중복 방지 — 같은 날 두 bin 으로 도착해도 한 번
  if exists (select 1 from inv_layer_apply_done d
              where d.kind = 'tr_in' and d.doc_number = r.doc_number and d.sku = r.sku
                and d.warehouse = r.warehouse and d.day = r.occurred_on) then
    return;
  end if;
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse, day) values ('tr_in', r.doc_number, r.sku, r.warehouse, r.occurred_on);
  o_processed := 1;

  -- ⓪ 창고 in 인데 같은 (doc, sku) 의 IN_TRANSIT in 이 아직 안 처리됐으면 그것부터 (C-2 · 같은 날 id 순서 무관)
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
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_proc from inv_layer_apply_transfer_in(v_it.id, p_until);
      o_layers := o_layers + v_layers; o_rows := o_rows + v_rows; o_short := o_short + v_short;
      o_orphan := o_orphan + v_orphan; o_net_zero := o_net_zero + v_nz;
    end loop;
  end if;

  -- ⓪′ in leg 순액 — 0 이하면 상쇄로 소멸한 키: 처리할 것이 없다 (orphan 도 short 도 아니다 · 조용히)
  select sum(qty_delta) into v_in_net
    from inv_ledger
    where doc_number = r.doc_number and sku = r.sku and warehouse = r.warehouse and event_type = 'transfer_in'
      and (p_until is null or occurred_on <= p_until);
  if v_in_net is null or v_in_net <= 0 then
    o_net_zero := o_net_zero + 1;
    return;
  end if;

  -- ① 대응 out leg 의 창고 — in 이 IN_TRANSIT 이면 창고 · in 이 창고면 IN_TRANSIT (같은 문서·날짜 우선)
  if r.warehouse = 'IN_TRANSIT' then
    select warehouse into v_out_wh
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse <> 'IN_TRANSIT'
        and event_type in ('transfer_out', 'manual_reversal')
        and (p_until is null or occurred_on <= p_until)
      order by (occurred_on = r.occurred_on) desc, occurred_on, id
      limit 1;
  else
    v_out_wh := 'IN_TRANSIT';
  end if;

  -- ② out leg 의 키 순액 × −1 (event_type 으로 leg 를 가른다 · source 무관 · 접미어·manual_reversal 자동 흡수)
  if v_out_wh is not null then
    select -sum(qty_delta) into v_out_net
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = v_out_wh
        and event_type in ('transfer_out', 'manual_reversal')
        and (p_until is null or occurred_on <= p_until);
    select doc_type, line_ref, event_type, occurred_on into v_out
      from inv_ledger
      where doc_number = r.doc_number and sku = r.sku and warehouse = v_out_wh and event_type = 'transfer_out'
        and (p_until is null or occurred_on <= p_until)
      order by (occurred_on = r.occurred_on) desc, id
      limit 1;
  end if;

  if v_out_wh is null or v_out_net is null or v_out_net <= 0 or v_out is null then
    -- C-3 대응 out 없음(방어 경로) — in 순액(> 0 보장)만큼 unknown 도착 레이어 · 예외 없음 · **만들었을 때만** orphan +1
    insert into inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id,
                           received_on, age_known, qty, unit_cost, cost_source)
    values (r.sku, r.warehouse, 'transfer', r.doc_number, r.line_ref, null,
            r.occurred_on, false, v_in_net, 0, 'unknown');
    o_layers := o_layers + 1;
    o_orphan := o_orphan + 1;
    return;
  end if;

  -- ④ out 키 기록 — 뒤에 그 out 행을 만나면 건너뛴다 · unpaired 집계에서 제외된다
  insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('tr_out', r.doc_number, r.sku, v_out_wh)
    on conflict do nothing;

  -- ②③ 출발 FIFO 소진 + 소진한 레이어마다 도착 레이어 (reason='transfer' · COGS 아님)
  select * into v_rows, v_short, v_layers, v_taken
    from inv_layer_fifo_take(r.sku, v_out_wh, v_out_net,
                             v_out.doc_type, r.doc_number, v_out.line_ref, v_out.event_type, v_out.occurred_on,
                             'transfer', r.warehouse);
  o_rows := o_rows + v_rows; o_short := o_short + v_short; o_layers := o_layers + v_layers;   -- ⓪ 중첩분에 더한다
end;
$$;

-- ── main: 카운터 집계만 수정 (transfer_keys_net_zero 추가 · unpaired 는 순액 > 0 인 out 키만) ──
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
  v_c int; v_u int; v_rows int; v_short int; v_proc int; v_rev int; v_layers int; v_orphan int; v_nz int;
  v_po          int := 0;
  v_sale        int := 0;
  v_sale_keys   int := 0;
  v_sale_rev    int := 0;
  v_tr          int := 0;
  v_tr_layers   int := 0;
  v_tr_orphan   int := 0;
  v_tr_nz       int := 0;
  v_tr_unpaired int := 0;
  v_layers_po   int := 0;
  v_consume     int := 0;
  v_unknown     int := 0;
  v_shorts      int := 0;
  v_skipped     jsonb;
begin
  select count(*) into v_baseline from inv_layer where origin_type = 'baseline';
  if v_baseline = 0 then
    raise exception 'inv_layer has no baseline layers — run inv_layer_seed_baseline first';
  end if;

  -- 전량 재생성 — FK 순서: consume · cost_add 먼저, 그 다음 baseline 외 레이어
  delete from inv_layer_consume;
  delete from inv_layer_cost_add;
  delete from inv_layer where origin_type <> 'baseline';
  perform inv_layer_apply_reset_done();

  -- 날짜순 루프 — ⭐ order by occurred_on, seq_hint, id (같은 날은 유입 먼저) · ⚠️ source 필터 없음
  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, id
  loop
    if r.event_type = 'po_in' then
      select * into v_c, v_u from inv_layer_apply_po_in(r.id, p_until);
      v_po := v_po + 1; v_layers_po := v_layers_po + v_c; v_unknown := v_unknown + v_u;
    elsif r.event_type = 'sale_out' then
      select * into v_rows, v_short, v_proc, v_rev from inv_layer_apply_sale_out(r.id, p_until);
      v_sale := v_sale + 1; v_consume := v_consume + v_rows; v_shorts := v_shorts + v_short;
      v_sale_keys := v_sale_keys + v_proc; v_sale_rev := v_sale_rev + v_rev;
    elsif r.event_type = 'transfer_in' then
      select * into v_layers, v_rows, v_short, v_orphan, v_nz, v_proc from inv_layer_apply_transfer_in(r.id, p_until);
      v_tr := v_tr + 1; v_tr_layers := v_tr_layers + v_layers; v_consume := v_consume + v_rows;
      v_shorts := v_shorts + v_short; v_tr_orphan := v_tr_orphan + v_orphan; v_tr_nz := v_tr_nz + v_nz;
    else
      v_tr := v_tr + 1;   -- transfer_out · manual_reversal: out leg 는 대응 in 이 처리한다(C-2 ④)
    end if;
  end loop;

  -- 순액 > 0 인데 대응 in 없이 남은 out 키 — 0 이어야 한다(생기면 신호). 순액 ≤ 0(상쇄 소멸) 키는 제외.
  select count(*) into v_tr_unpaired
    from (select doc_number, sku, warehouse
            from inv_ledger
            where event_type in ('transfer_out', 'manual_reversal')
              and (p_until is null or occurred_on <= p_until)
            group by doc_number, sku, warehouse
            having -sum(qty_delta) > 0) o
    where not exists (select 1 from inv_layer_apply_done d
                        where d.kind = 'tr_out' and d.doc_number = o.doc_number and d.sku = o.sku and d.warehouse = o.warehouse);

  select coalesce(jsonb_object_agg(event_type, n), '{}'::jsonb) into v_skipped
    from (select event_type, count(*) as n
            from inv_ledger
            where event_type not in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal')
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
    'transfer_out_unpaired',     v_tr_unpaired,
    'skipped_by_type',           v_skipped,
    'layers_created',            v_layers_po,
    'consume_rows',              v_consume,
    'cost_unknown_layers',       v_unknown,
    'short_events',              v_shorts,
    'elapsed_ms',                round(extract(epoch from clock_timestamp() - v_t0) * 1000));
end;
$$;

revoke all on function inv_layer_apply_transfer_in(bigint, date) from public, anon, authenticated;
revoke all on function inv_layer_apply(date) from public, anon;
grant execute on function inv_layer_apply(date) to authenticated;
