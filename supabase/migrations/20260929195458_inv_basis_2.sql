-- inv-basis-3 (⑱-2) — Off-invoice 한 길 · ⑯ 입고 순간 비용 얹기 · ㉓ 트랜스퍼 운임은 도착한 물건에만 · ㉔ ㉕ 지우기 결함 (판정 88 ⑧ · 92 · 93 ⓓ ⓔ · 94 · 95 · 97 · 2026-09-29)
--   ① 어휘 off_invoice(PO 입고 행에만 · 트랜스퍼 도착 차이 무접촉) — CHECK 넷 다시 + off_invoice 는 트랜스퍼에 없다(새 CHECK 하나) · 옛 over · off_po 행과 옛 창구는 그대로
--   ② po_receipt_confirm_by 재발행 — 더 온 것(인보이스 초과 · 인보이스에 없는 줄)은 off_invoice 한 행(놓인 칸 · 놓은 사람 · 판정 43) · 두 칸에 걸치면 막는다(판정 92) · ⑯ 원장 뒤 이 발주의 확정 비용을 inv_layer_post_charge 로 얹는다(오류는 charges.errors · 확정을 막지 않는다 · 판정 94)
--   ③ inv_post_receipt 재발행 — 자르기 상한이 off_invoice 행도 본다(over 와 같은 자리)
--   ④ 결정 창구 po_receipt_diff_settle_off_invoice(diff · resolution · unit_price? · note?) — accepted_free 0 · accepted_billed 단가(기본값 = 그 PO 줄 마지막 확정 인보이스 단가 · 없으면 PO 단가 · × PO 환율) · ⭐ 판정 99(2026-09-29 밤 · Caleb): rejected 없음 — 더 온 것은 이미 창고에 있다 · 돌려보내기(선반에서 빼기 · 공급처 크레딧)는 입고와 따로 · 원장 · 레이어는 형제 창구 inv_post_receipt_off_po → inv_layer_post_receipt_off_po 를 off_invoice 에도 연다(line_ref <diff>:offpo 그대로 · 수량 = received − expected)
--   ⑤ 창고 창구 — wms_recv_off_po 는 off_invoice 행을 만든다 · _putaway · _removed 는 두 어휘 · 옛 결정 창구 둘(settle_over · settle_off_po)과 reopen 은 새 어휘를 새 창구로 안내
--   ⑥ inv_layer_post_charge 재발행 — 문에 입고 확정자(receiving · wms_receiving_confirm · 확정 입고가 있는 발주에만 배분된 비용) · 트랜스퍼 갈래에서 :over: 레이어 제외(판정 95) · inv_layer_apply 의 같은 술어 둘도(재생성 = 라이브)
--   ⑦ wms_health_check 재발행 — off_invoice_undecided(151) 하나 · 판정 99: 161(off_invoice_rejected_on_shelf) 없음 — 거절이 없다 · 옛 off_po 의 160 은 그대로
--   ⑧ wms_recv_delete — 장부에 든 off-PO · off-invoice 가 있으면 거부(판정 97 ㉕) · po_receipt_delete — 차이 행이 있으면 날것 FK 대신 문장(판정 97 ㉔)
--   ⑨ 판정 100(inv-basis-6): 더 온 몫이 두 칸에 나뉘면 창고 Complete 에서 먼저 막는다 — 속 함수 po_receipt_over_bins(초과분이 놓인 칸 · 자르기 식 한 곳 · authenticated 회수) 를 wms_recv_complete(재발행 · PO 갈래에 검사 하나 · 트랜스퍼 무접촉) 와 po_receipt_confirm_by(안전띠 · 같은 속 함수) 가 부른다
--   ⑩ 판정 101(inv-basis-6): po_receipt_detail 재발행 — totals.over_lines · short_lines · warnings.over_receipt 를 lines[].expected(확정 인보이스 − 앞선 입고) 기준으로 · 키 · 모양 무변
--   ⚠️ UTC 이름 · 가드 첫 문장 · begin/commit 없음 · 부분 유니크 0 · 재발행 = 마지막 정의 바이트 그대로 + 바꾼 줄(원본: confirm_by 20260929190928 · inv_post_receipt · wms_recv_off_po 20260929010938 · off-PO 창구 넷 · settle_over · reopen 20260928025627 · post_charge · apply 20260929025719 · health 20260929014246 · wms_recv_delete 20260928014844 · po_receipt_delete 20260918163552)

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


-- ═══ 0) 준비 가드 — 초안 입고에 옛 어휘 off_po 행이 남아 있으면 멈춘다(스캔 창구가 새 어휘로 바뀌어 같은 물건이 두 행이 된다 · 지금 실측 0건) ═══
do $$
declare v_n int; v_txt text;
begin
  select count(*), string_agg(distinct r.receipt_number, ', ') into v_n, v_txt
    from public.po_receipt_diff d join public.po_receipt r on r.id = d.receipt_id
   where r.status = 'draft' and d.kind = 'off_po';
  if v_n > 0 then
    raise exception 'STOP - % off-PO row(s) still sit on draft receipt(s): %. Finish or delete those receipts under the old rule first, then apply this migration (inv-basis-3 · ruling 92). Nothing was changed.', v_n, v_txt;
  end if;
end $$;

-- ═══ 1) 어휘 — off_invoice(PO 입고 행에만) · CHECK 넷 다시 · 새 CHECK 하나 ═══
alter table public.po_receipt_diff drop constraint po_receipt_diff_kind_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_kind_ck check (kind in ('over', 'short', 'off_po', 'off_invoice'));
alter table public.po_receipt_diff drop constraint po_receipt_diff_off_po_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_off_po_ck check ((kind = 'off_po' or (kind = 'off_invoice' and po_line_id is null)) = (po_line_id is null and transfer_line_id is null));   -- off_po 는 줄이 없다 · off_invoice 는 줄이 있거나(인보이스 초과 · 인보이스에 없는 줄) 없거나(PO 밖 품목) · over · short 는 줄이 있다
alter table public.po_receipt_diff drop constraint po_receipt_diff_off_po_cols_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_off_po_cols_ck check (kind in ('off_po', 'off_invoice') or (bin_id is null and placed_by is null and placed_at is null and unit_price is null and removed_by is null and removed_at is null));
alter table public.po_receipt_diff drop constraint po_receipt_diff_resolution_kind_ck;
alter table public.po_receipt_diff add constraint po_receipt_diff_resolution_kind_ck check (resolution is null
  or (kind = 'short' and resolution in ('split_shipment', 'out_of_stock', 'lost_damaged', 'miscount', 'other', 'lost', 'returned'))
  or (kind = 'over' and resolution in ('free', 'billed', 'credited', 'sent_more', 'found'))
  or (kind = 'off_po' and resolution in ('accepted_free', 'accepted_billed', 'rejected'))
  or (kind = 'off_invoice' and resolution in ('accepted_free', 'accepted_billed')));   -- 판정 99: off_invoice 는 둘 — 거절 없음(옛 off_po 줄은 위 그대로)
alter table public.po_receipt_diff add constraint po_receipt_diff_off_invoice_po_ck check (kind <> 'off_invoice' or (po_id is not null and transfer_id is null));   -- inv-basis-3: off_invoice 는 PO 입고 행에만 — 트랜스퍼 도착 차이(over · short · sent_more · found · lost · returned)는 무접촉
comment on column public.po_receipt_diff.kind is 'over | short | off_po(옛 어휘 · 2026-09-29 까지의 행) | off_invoice(inv-basis-3 · 판정 88 ⑧ — PO 입고의 더 온 것 한 길: 확정 인보이스 초과 · 인보이스에 없는 줄 · PO 밖 품목 · po_line_id 는 있거나 없다 · CHECK off_po_ck · off_invoice_po_ck) · 트랜스퍼 도착 차이는 over · short 만';
comment on column public.po_receipt_diff.resolution is '닫은 이유 — short: split_shipment | out_of_stock | lost_damaged | miscount | other(메모 필수) · 트랜스퍼 short: lost | returned · over(옛 PO): free | billed | credited · 트랜스퍼 over: sent_more | found · off_po(옛): accepted_free | accepted_billed | rejected · off_invoice(inv-basis-3 · 판정 99): accepted_free | accepted_billed — 거절 없음(더 온 것은 이미 창고에 있다 · 돌려보내기는 입고와 따로) — kind 별 어휘는 CHECK po_receipt_diff_resolution_kind_ck. null = 열림';


-- ═══ 2) inv_post_receipt — 20260929010938:1133 바이트 그대로 + 1줄(자르기 상한이 off_invoice 도 본다) ═══
create or replace function public.inv_post_receipt(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker                                              -- 이견 3 — definer 가 필요한 표가 없다
set search_path = public, pg_temp
as $$
declare
  c_version   constant text := 'inv_post_receipt@2026-09-19.1';   -- raw.poster 에 박는다 — 배분 규칙이 바뀌면 올릴 것
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_wh        text;
  v_existing  int;
  v_baseline  date;
  v_alloc     jsonb;
  v_lines     jsonb;
  v_rows      int := 0;
  v_counted   numeric := 0;
  v_posted    numeric := 0;
  v_excess    numeric := 0;
  v_warn      text[] := '{}';
  v_layers    jsonb;                                              -- 원가 레이어 결과(원가 이식 1차 · 2026-09-19)
  b           record;
begin

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was posted to the ledger', p_receipt_id; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — its ledger is inv_post_transfer_arrive — nothing was posted to the ledger', v_r.receipt_number; end if;   -- tr-3a(트랜스퍼를 막는 한 줄만)
  if v_r.status <> 'confirmed' or v_r.confirmed_at is null then
    raise exception 'Receipt % is % — the ledger takes confirmed receipts only — nothing was posted to the ledger', v_r.receipt_number, v_r.status;
  end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;

  -- 2. 멱등 — 이미 기표된 입고는 다시 쓰지 않는다(터지지 않고 말한다 · ⬜5)
  select count(*) into v_existing
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.doc_number = v_r.receipt_number and l.source = 'ims'
    and l.line_ref not like '%:offpo';                                                          -- ⑤-6c1 off-PO 행(<diff>:offpo · 확정과 독립 · 확정 전에도 선다)은 「이미 기표됨」의 근거가 아니다
  if v_existing > 0 then
    -- ⭐ 원가 이식 1차(2026-09-19) — 원장은 이미 있어도 레이어는 없을 수 있다(이식 전에 확정된 RCV-00005·00006 · 백필 ⬜7).
    --   레이어 쪽도 같은 멱등 규칙(4키가 있으면 안 만든다)이라, 다시 부르면 빠진 레이어만 선다. 원장은 한 행도 다시 쓰지 않는다.
    v_layers := public.inv_layer_post_receipt(p_receipt_id);
    return jsonb_build_object('receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0,
                              'qty_counted', null, 'qty_posted', null, 'qty_excess', null, 'lines', '[]'::jsonb,
                              'layers', v_layers, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 6. 날짜 경고 — 기초선보다 이르면 · 미래면 (막지 않는다 · ⬜7)
  select (max(s.taken_at) at time zone 'America/Toronto')::date into v_baseline
  from public.inv_snapshot s
  where s.snapshot_key = (select c.value from public.inv_config c where c.key = 'baseline_snapshot_key');
  if v_baseline is not null and v_r.received_on < v_baseline then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- 3·4. 기준과 배분 — 한 번의 SQL 로 계산해 jsonb 배열에 담는다(그 뒤 루프는 넣고 더하기만 한다)
  with ln as (
    select l.po_line_id, sum(l.qty_ea) as counted, d.kind as diff_kind,
           case when d.kind is not null then d.expected_qty else sum(l.qty_ea) end as basis,     -- ⭐ 이견 1 — 기록용 기준: 차이 행(over·short)이 있으면 ⓑ 가 얼린 값 · 없으면 센 것
           case when d.kind in ('over', 'off_invoice') then d.expected_qty else sum(l.qty_ea) end as cap        -- 깎기 상한: over(옛) · off_invoice(inv-basis-3 · 인보이스 초과)만 자른다 · posted 는 이것만 본다(검증 ⑤ 정정 — basis 와 갈랐다)
    from public.po_receipt_line l
    left join public.po_receipt_diff d on d.receipt_id = l.receipt_id and d.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id
    group by l.po_line_id, d.kind, d.expected_qty
  ),
  alloc as (
    select l.id as receipt_line_id, l.po_line_id, l.bin_id, rb.name as bin, l.qty_ea, l.received_by, l.note,
           pl.line_no, pl.product_id, pl.unit_price, pr.sku,
           ln.counted, ln.basis, ln.cap, ln.diff_kind,
           least(l.qty_ea, greatest(ln.cap - coalesce(sum(l.qty_ea) over (partition by l.po_line_id order by l.qty_ea desc, rb.name, l.id
                                                                                  rows between unbounded preceding and 1 preceding), 0), 0)) as posted   -- ⭐ ⬜2 — 큰 빈부터 채우고 바닥나는 줄에서 자른다
    from public.po_receipt_line l
    join public.ref_bin  rb on rb.id = l.bin_id
    join public.po_line  pl on pl.id = l.po_line_id
    join public.product  pr on pr.id = pl.product_id
    join ln on ln.po_line_id = l.po_line_id
    where l.receipt_id = p_receipt_id
  )
  select coalesce(jsonb_agg(to_jsonb(a) order by a.line_no, a.qty_ea desc, a.bin, a.receipt_line_id), '[]'::jsonb) into v_alloc from alloc a;

  -- 5. 기표 — posted > 0 인 줄만 행이 된다
  for b in
    select * from jsonb_to_recordset(v_alloc) as t(
      receipt_line_id uuid, po_line_id uuid, bin_id uuid, bin text, qty_ea numeric, received_by uuid, note text,
      line_no int, product_id uuid, unit_price numeric, sku text, counted numeric, basis numeric, diff_kind text, posted numeric)
    order by line_no, qty_ea desc, bin
  loop
    if b.posted <= 0 then continue; end if;
    insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
    values (
      v_r.received_on, 1, b.sku, v_wh, b.bin, b.posted, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, b.po_line_id::text, null, 'ims',          -- line_ref = po_line_id(라인 id · Caleb 실측 확정)
      jsonb_build_object(
        'kind', 'po_in', 'poster', c_version,
        'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'receipt_line_id', b.receipt_line_id,
        'po_id', v_po.id, 'po_number', v_po.po_number,                                   -- 갈라진 뒤의 번호(ⓓ 뒤에 불린다 · §11-j)
        'po_line_id', b.po_line_id, 'line_no', b.line_no, 'product_id', b.product_id, 'sku', b.sku,
        'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', b.bin_id, 'bin', b.bin,
        'received_on', v_r.received_on, 'received_by', b.received_by, 'confirmed_by', v_r.confirmed_by, 'confirmed_at', v_r.confirmed_at,
        'line', jsonb_build_object('counted', b.counted, 'basis', b.basis, 'posted', least(b.counted, b.basis), 'excess', greatest(b.counted - b.basis, 0), 'diff_kind', b.diff_kind),
        'this_bin', jsonb_build_object('counted', b.qty_ea, 'posted', b.posted, 'trimmed', b.qty_ea - b.posted),
        'bins', (select jsonb_agg(jsonb_build_object('bin', t2.bin, 'counted', t2.qty_ea, 'posted', t2.posted, 'trimmed', t2.qty_ea - t2.posted) order by t2.qty_ea desc, t2.bin)
                 from jsonb_to_recordset(v_alloc) as t2(po_line_id uuid, bin text, qty_ea numeric, posted numeric) where t2.po_line_id = b.po_line_id),
        'trim_rule', 'fill bins by qty desc, then bin name; cut where the cap runs out; cap = po_receipt_diff.expected_qty when over, else counted (nothing to cut); basis (recorded) = expected_qty whenever a diff row exists, else counted',
        'unit_price', b.unit_price, 'currency_id', v_po.currency_id, 'exchange_rate', v_po.exchange_rate,
        'note', b.note));
    v_rows := v_rows + 1;
    v_posted := v_posted + b.posted;
  end loop;

  -- 라인 요약(0 으로 깎인 줄도 bins[] 에 남는다)
  select coalesce(jsonb_agg(jsonb_build_object(
           'po_line_id', t.po_line_id, 'line_no', t.line_no, 'sku', t.sku, 'counted', t.counted, 'basis', t.basis,
           'posted', t.posted, 'excess', greatest(t.counted - t.basis, 0), 'diff_kind', t.diff_kind, 'bins', t.bins) order by t.line_no), '[]'::jsonb),
         coalesce(sum(t.counted), 0), coalesce(sum(greatest(t.counted - t.basis, 0)), 0)
    into v_lines, v_counted, v_excess
  from (
    select a.po_line_id, min(a.line_no) as line_no, min(a.sku) as sku, min(a.counted) as counted, min(a.basis) as basis, min(a.diff_kind) as diff_kind,
           sum(a.posted) as posted,
           jsonb_agg(jsonb_build_object('bin', a.bin, 'counted', a.qty_ea, 'posted', a.posted, 'trimmed', a.qty_ea - a.posted) order by a.qty_ea desc, a.bin) as bins
    from jsonb_to_recordset(v_alloc) as a(po_line_id uuid, line_no int, sku text, bin text, qty_ea numeric, counted numeric, basis numeric, diff_kind text, posted numeric)
    group by a.po_line_id
  ) t;

  -- ⭐ 원가 레이어 — 원장 행을 만든 바로 그 수량으로(같은 트랜잭션 · 원장 사건과 함께 서거나 함께 죽는다 · 원가 이식 1차 2026-09-19).
  --   두 번 계산하지 않는다 — inv_layer_post_receipt 가 방금 넣은 inv_ledger 행(source='ims' · 이 RCV)을 읽어 라인 단위로 접는다.
  v_layers := public.inv_layer_post_receipt(p_receipt_id);

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number,
    'already_posted', false, 'existing_rows', 0,
    'rows_posted', v_rows, 'qty_counted', v_counted, 'qty_posted', v_posted, 'qty_excess', v_excess,
    'lines', v_lines, 'layers', v_layers, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Receipt % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', v_r.receipt_number, sqlerrm;
end;
$$;


-- ═══ 2b) 속 함수 po_receipt_over_bins — 판정 100(inv-basis-6): 한 줄의 초과분이 놓인 칸(자르기 = 원장 창구와 같은 식 · 큰 칸부터 · 칸 이름 · id) · 창고 Complete 와 오피스 확정이 같은 식을 부른다(복사 0) ═══
create function public.po_receipt_over_bins(p_receipt_id uuid, p_po_line_id uuid, p_expected numeric)
  returns table(bins int, bin_id uuid, placed_by uuid, bins_txt text)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select count(distinct t.bin_id)::int, min(t.bin_id::text)::uuid, min(t.putaway_by::text)::uuid,
         string_agg(t.bin || ' ' || (t.cum - greatest(t.cum - t.qty_ea, greatest(p_expected, 0))) || ' EA', ', ' order by t.bin)
    from (select w.bin_id, w.qty_ea, w.putaway_by, rb.name as bin, sum(w.qty_ea) over (order by w.qty_ea desc, rb.name, w.id) as cum
            from public.po_receipt_work w join public.ref_bin rb on rb.id = w.bin_id
           where w.receipt_id = p_receipt_id and w.po_line_id = p_po_line_id) t
   where t.cum > greatest(p_expected, 0);
$$;
comment on function public.po_receipt_over_bins(uuid, uuid, numeric) is '판정 100(inv-basis-6 · 2026-09-29) — 한 PO 줄의 초과분(센 것 − 기준)이 놓인 칸: 칸 있는 작업 줄을 큰 칸부터(qty desc · 칸 이름 · id) 누적해 기준을 넘는 칸들 · bins = 그 칸 수(0 = 초과분이 칸 없는 줄에만 · 1 = 한 칸 · 2+ = 나뉨) · bin_id · placed_by = 그중 하나(한 칸일 때 그 칸) · bins_txt = 「칸 n EA, …」 문장용. 원장 창구 inv_post_receipt 의 자르기와 같은 식. wms_recv_complete(창고 Complete · 먼저 막는다)와 po_receipt_confirm_by(오피스 확정 · 안전띠)가 부른다 — 둘 다 definer 라 소유자로 돈다 · 화면은 부르지 않는다(authenticated 회수)';
revoke all on function public.po_receipt_over_bins(uuid, uuid, numeric) from public, anon, authenticated;

-- ═══ 3) po_receipt_confirm_by — 20260929190928:270 바이트 그대로 + 선언 7줄 · ⓑ 더 온 것 = off_invoice(칸 기록 · 두 칸 거부 = 속 함수 po_receipt_over_bins · 판정 100) · ⓕ 비용 얹기 · 반환 charges ═══
create or replace function public.po_receipt_confirm_by(p_staff uuid, p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security definer                                              -- ⭐ 이견 1 — po·po_line·po_discount(purchasing RLS)에 쓴다. 권한은 첫머리 ims_require_write('receiving') 가 묻는다
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_r         public.po_receipt%rowtype;
  v_po        public.po%rowtype;
  v_pl        public.po_line%rowtype;
  v_base      text;
  v_max       text;
  v_a_num     text;
  v_b_num     text;
  v_b_id      uuid;
  v_n         int;
  v_free_txt  text;
  v_free_n    int;
  v_work_n    int;
  v_lines_n   int := 0;
  v_over      int := 0;
  v_short     int := 0;
  v_rem_total numeric := 0;
  v_reduced   int := 0;
  v_moved     int := 0;
  v_cleared   text[] := '{}';
  v_warn      text[] := '{}';
  v_rows      jsonb := '[]'::jsonb;
  v_now       timestamptz := now();
  v_ledger    jsonb;                                           -- ⓔ 원장 창구의 반환(원장 이식 2차 · 2026-09-19)
  v_cur       text;                                            -- ⑥ 환율 게이트(원가 이식 1차 · 2026-09-19) — 발주 통화 코드
  v_base_cur  text;                                            -- ⑥ 기준통화 코드 · ⚠️ v_base(접미사를 뗀 PO 번호 · 잠금·채번)와 다른 것 — 이름을 같이 쓰면 채번이 CADa 가 된다(2026-09-19 실사고)
  x           record;
  v_ob_n      int;                                             -- inv-basis-3: 초과분이 놓인 칸 수 · 칸 · 놓은 사람 · 문장용
  v_ob_bin    uuid;
  v_ob_by     uuid;
  v_ob_txt    text;
  v_cj        jsonb;                                           -- inv-basis-3 · 판정 94(⑯): 입고 순간 비용 얹기의 반환 · 얹은 것 · 오류
  v_cpost     jsonb := '[]'::jsonb;
  v_cerr      jsonb := '[]'::jsonb;
begin
  if p_staff is null then raise exception 'po_receipt_confirm_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — it is confirmed by the warehouse Complete, not here — nothing was saved', v_r.receipt_number; end if;   -- tr-3a 판정 70(트랜스퍼를 막는 한 줄만)
  -- ① 이미 확정·취소
  if v_r.confirmed_at is not null or v_r.status = 'confirmed' then
    raise exception 'Receipt % was already confirmed on % — nothing was saved', v_r.receipt_number, to_char(v_r.confirmed_at, 'YYYY-MM-DD');
  end if;
  if v_r.status <> 'draft' then
    raise exception 'Receipt % is % — only a draft receipt can be confirmed — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  -- ⭐ 잠금 — PO 단위(형제 채번·분할·닫기 · 키는 접미사를 뗀 base) + 라인 단위(작업 줄 RPC 들과 같은 키 · 세는 중인 손을 줄 세운다)
  v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('po:' || v_base));
  for x in select pl.id from public.po_line pl where pl.po_id = v_po.id loop
    perform pg_advisory_xact_lock(hashtext('po_receipt_work:' || v_r.id::text || ':' || x.id::text));
  end loop;
  -- ④ 잠금 뒤 다시 본다 — 그 사이 닫혔거나 취소됐을 수 있다
  select * into v_po from public.po where id = v_r.po_id;
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — a receipt can be confirmed only on a confirmed order — nothing was saved', v_po.po_number, v_po.status;
  end if;
  -- inv-basis-2 · 판정 88 ③ · 92 — 확정 인보이스가 없는 PO 는 받지 않는다(입고 문에서 이미 막지만, 옛 초안 · 직접 호출도 여기서 한 번 더)
  if not exists (select 1 from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id join public.po_line pl on pl.id = il.po_line_id
                  where pl.po_id = v_po.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed') then
    raise exception 'PO % has no confirmed invoice — the office confirms the supplier invoice first (Purchase Invoices), then the receipt can be confirmed — nothing was saved', v_po.po_number;
  end if;
  select * into v_r from public.po_receipt where id = p_receipt_id;                     -- 잠금 뒤 다시(남이 사이에 확정했을 수 있다)
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % was changed by someone else just now (% ) — reload and try again — nothing was saved', v_r.receipt_number, v_r.status;
  end if;

  -- ③ 작업 줄이 없다
  select count(*) into v_work_n from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  if v_work_n = 0 then
    raise exception 'Receipt % has nothing counted — count at least one line before confirming, or delete the receipt — nothing was saved', v_r.receipt_number;
  end if;
  -- ②⭐⭐ 빈 없는 줄 — 라인·수량을 문장에 · 빠져나갈 길을 함께
  select count(*), string_agg(format('line %s (%s) %s EA', t.line_no, t.sku, t.qty_ea), ', ' order by t.line_no)
    into v_free_n, v_free_txt
  from (select pl.line_no, pr.sku, w.qty_ea
          from public.po_receipt_work w join public.po_line pl on pl.id = w.po_line_id join public.product pr on pr.id = pl.product_id
         where w.receipt_id = p_receipt_id and w.bin_id is null) t;
  if v_free_n > 0 then
    raise exception 'Receipt % cannot be confirmed — % row(s) still have no bin: %. Put them away first, or lower the count to what you actually placed — the rest stays on the order — nothing was saved',
      v_r.receipt_number, v_free_n, v_free_txt;
  end if;
  -- ⑤ 더 막는 것 — 빈이 그 사이 다른 창고 것·비활성으로 바뀌었나(배정 때 봤지만 확정은 장부에 닿는다 · 한 번 더)
  select count(*) into v_n
  from public.po_receipt_work w join public.ref_bin b on b.id = w.bin_id
  where w.receipt_id = p_receipt_id and (b.warehouse_id <> v_r.warehouse_id or not b.is_active);
  if v_n > 0 then
    raise exception 'Receipt % has % row(s) in a bin that is inactive or not in this receipt''s warehouse — move them to another bin first — nothing was saved', v_r.receipt_number, v_n;
  end if;
  if v_r.received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 발주인데 환율이 없거나 0 이면 **확정 자체를 거부**한다(Caleb 2026-09-19 · 원가가 조용히 틀리는 것보다 낫다 · 정본 「0 금지」).
  --   기준통화는 inv_config.base_currency(박지 않는다) · 발주 통화는 po.currency_id → ref_currency.code.
  --   ⚠️ po.exchange_rate 는 **CAD per USD** 다(Cin7 「CAD units per USD」 · 화면 칸 「CAD per USD」) — unit_price × exchange_rate = CAD. 곱한다 · 나누지 않는다.
  --   문장이 어디서 고치는지 말한다 — 발주 머리의 「Exchange rate (CAD per USD)」 칸 · 확정 뒤에도 열려 있다(po.html HEAD_ALWAYS).
  select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — nothing was saved'; end if;
  if v_cur is distinct from v_base_cur and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
    raise exception 'PO % is in % but has no % per % exchange rate — stock cost cannot be worked out without it. Enter the rate in the order header ("Exchange rate" · it stays open after confirming) and confirm again — nothing was saved',
      v_po.po_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
  end if;

  -- ═══ ⓐ 작업 줄 → 입고 줄 (1:1 · received_on 은 묶음의 것 · received_by 는 놓은 사람 → 센 사람 → 확정한 사람 · 초과분도 그대로) ═══
  insert into public.po_receipt_line (po_line_id, received_on, received_by, bin_id, qty_ea, note, receipt_id)
  select w.po_line_id, v_r.received_on, coalesce(w.putaway_by, w.counted_by, v_staff), w.bin_id, w.qty_ea, w.note, v_r.id
  from public.po_receipt_work w
  where w.receipt_id = p_receipt_id
  order by w.po_line_id, w.created_at;
  get diagnostics v_lines_n = row_count;
  if v_lines_n <> v_work_n then
    raise exception 'Receipt %: % work row(s) but % receipt line(s) were written — nothing was saved', v_r.receipt_number, v_work_n, v_lines_n;
  end if;

  -- ═══ ⓑ 차이 — over · short · 안 센 라인은 short(received 0) · ⭐ inv-basis-2 · 판정 88 ② · 93 ⓑ: 기준 = 확정 인보이스 goods 합(크레딧 · 초안 제외) − 앞선 입고 합(PO 수량이 아니다) ═══
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pl.qty_ea as ordered,
           coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                      where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0)
             - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as expected,
           coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as counted
    from public.po_line pl join public.product pr on pr.id = pl.product_id
    where pl.po_id = v_po.id
    order by pl.line_no
  loop
    if x.counted > x.expected then
      -- ⭐ inv-basis-3 · 판정 88 ⑧ · 93 ⓓ: 더 온 것(인보이스 초과 · 인보이스에 없는 줄)은 off_invoice 한 행 — 창고가 놓은 칸을 행에 남긴다(판정 43 · 어느 칸에 얼마).
      --   초과분이 놓인 칸 = 원장 창구 inv_post_receipt 와 같은 자르기(큰 칸부터 · 칸 이름 · 상한 = 기준)로 정한다 · 두 칸에 걸치면 막는다(판정 92 · off-PO 와 같이 한 물건 한 칸 · 나눠 놓기 없음).
      select b.bins, b.bin_id, b.placed_by, b.bins_txt into v_ob_n, v_ob_bin, v_ob_by, v_ob_txt
        from public.po_receipt_over_bins(p_receipt_id, x.po_line_id, x.expected) b;   -- 판정 100: 자르기 식은 속 함수 한 곳 — 창고 Complete 가 먼저 막고 여기는 안전띠(칸 0 = 칸 없는 줄은 위 ② 가 먼저 막는다)
      if coalesce(v_ob_n, 0) <> 1 then
        raise exception 'Line % (%) on %: % EA more than the confirmed invoice (% counted · % invoiced) sit in more than one bin (%) — move the extra into one bin, or lower the count, so the office can decide it as one off-invoice item — nothing was saved',
          x.line_no, x.sku, v_r.receipt_number, x.counted - greatest(x.expected, 0), x.counted, greatest(x.expected, 0), coalesce(v_ob_txt, '?');
      end if;
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty, note, bin_id, placed_by, placed_at, updated_by)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, 'off_invoice', greatest(x.expected, 0), x.counted,
              'off-invoice (receipt confirm) — more than the confirmed invoice · decision pending', v_ob_bin, coalesce(v_ob_by, v_staff), v_now, v_staff);
      v_over := v_over + 1;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'off_invoice', 'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    elsif x.counted <> x.expected then
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, 'short', greatest(x.expected, 0), x.counted);
      v_short := v_short + 1;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'short', 'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    end if;
    if x.expected - x.counted > 0 then v_rem_total := v_rem_total + (x.expected - x.counted); end if;
  end loop;

  -- ═══ ⓒ 닫기 — inv-basis-2 · 판정 88 ⑤ ⑥: 입고 확정은 더 이상 가르지 않는다(가르는 자리는 인보이스 확정 · po_invoice_confirm) · 덜 받은 몫은 short 차이로 남고 크레딧은 오피스 단추 · PO 는 닫힌다(입고 종료 · §11-b) ═══
  v_a_num := v_po.po_number;
  update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
  v_warn := array_append(v_warn, 'po_closed');
  if v_over > 0 then v_warn := array_append(v_warn, 'over_receipt'); v_warn := array_append(v_warn, 'off_invoice'); end if;   -- inv-basis-3: 옛 경고 이름은 모양 무변 · 새 어휘도 함께
  if v_short > 0 then v_warn := array_append(v_warn, 'short_receipt'); end if;

  -- ═══ ⓓ 묶음 confirmed (맨 뒤 — 어디서 터져도 아무것도 안 남는다) ═══
  update public.po_receipt set status = 'confirmed', confirmed_at = v_now, confirmed_by = v_staff
   where id = p_receipt_id and status = 'draft' and confirmed_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not saved — it may have been changed by someone else just now — nothing was saved', v_r.receipt_number; end if;

  -- ═══ ⓔ 원장 — 창구를 부른다 (원장 이식 2차 · 2026-09-19 · ⬜1) ═══
  -- ⭐ 같은 트랜잭션 — 원장이 실패하면 확정도 실패한다(재고에 안 잡힐 거면 확정도 하면 안 된다). inv_ledger 에 직접 쓰지 않는다(원칙 2 · §11-j).
  -- ⭐ 자리가 ⓓ 뒤인 이유 셋: ① 창구는 「확정된 입고」만 받는다(status=confirmed 를 스스로 확인 — 직접 호출로 초안이 장부에 닿는 길을 막는다)
  --   ② raw 의 po_number 는 갈라진 뒤의 번호여야 한다(§11-j) — ⓒ 가 끝나야 안다 ③ 기준은 po_line.qty_ea 가 아니라 ⓑ 가 얼려 둔 po_receipt_diff.expected_qty 에서
  --   읽으므로(§2 의 함정 — ⓒ 가 qty_ea 를 줄인다) ⓒ 뒤라도 어긋나지 않는다. 기준을 「미리 잡아 두는」 그릇이 그 표다.
  v_ledger := public.inv_post_receipt(p_receipt_id);
  if coalesce((v_ledger->>'qty_excess')::numeric, 0) > 0 then v_warn := array_append(v_warn, 'ledger_trimmed_to_basis'); end if;
  if (v_ledger->'warnings') ? 'received_on_before_baseline' then v_warn := array_append(v_warn, 'received_on_before_baseline'); end if;

  -- ═══ ⓕ inv-basis-3 · 판정 94(⑯): 입고 전에 확정해 둔 이 발주의 비용은 지금 원가에 얹는다 — 배분 줄 단위 멱등(창구가 건너뛴다) · 오류는 경고로 모아 돌려준다(확정을 막지 않는다 · tf_arrive 판정 78 모양) ═══
  for x in select distinct c.id, c.charge_number from public.po_charge c join public.po_charge_alloc a on a.po_charge_id = c.id
            where a.po_id = v_po.id and c.status = 'confirmed' and c.confirmed_at is not null
              and not exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = c.charge_number and ca.line_ref = a.id::text)
            order by c.charge_number loop
    begin
      v_cj := public.inv_layer_post_charge(x.id);
      v_cpost := v_cpost || jsonb_build_object('charge_id', x.id, 'charge_number', x.charge_number, 'layers_touched', v_cj -> 'layers_touched', 'amount_posted_cad', v_cj -> 'amount_posted_cad', 'warnings', v_cj -> 'warnings');
    exception when others then
      v_cerr := v_cerr || jsonb_build_object('charge_id', x.id, 'charge_number', x.charge_number, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  if jsonb_array_length(v_cerr) > 0 then v_warn := array_append(v_warn, 'charge_errors'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', 'closed', 'closed_at', v_now),
    'split', null,                                               -- inv-basis-2: 입고 확정은 가르지 않는다(키는 모양 무변 · 값은 늘 null · 덜 받은 몫은 diffs.short)
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'charges', jsonb_build_object('posted', v_cpost, 'errors', v_cerr),   -- inv-basis-3 · 판정 94(⑯): 이 발주의 확정 비용을 입고 순간 얹은 결과
    'warnings', to_jsonb(v_warn));
end;
$$;


-- ═══ 4) 원장 · 레이어 창구(off-PO) — 20260928025627:138 · :230 바이트 그대로 + off_invoice 를 연다(수량 = received − expected · 옛 off_po 행은 expected 0 이라 그대로) ═══
create or replace function public.inv_layer_post_receipt_off_po(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_layer_post_receipt_off_po@2026-09-29.1';   -- inv-basis-3: off_invoice 행도
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_wh       text;
  v_sku      text;
  v_ref      text;
  v_qty      numeric;
  v_recv_on  date;
  v_rows     int;
  v_unit     numeric;
  v_src      text;
  v_cur      text;
  v_base     text;
  v_factor   numeric;
  v_layer_id bigint;
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — no cost layer was created', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — no cost layer was created', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  if v_d.kind not in ('off_po', 'off_invoice') or v_d.resolved_at is null or v_d.resolution not in ('accepted_free', 'accepted_billed') then   -- inv-basis-3: off_invoice 도 같은 창구(line_ref <diff>:offpo 그대로)
    raise exception 'Off-PO % on % is not accepted (free or billed) — no cost layer was created', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  v_ref := v_d.id::text || ':offpo';

  -- off-PO 원장 행을 접는다(한 차이 · 한 SKU · 한 창고 · 한 칸 ⇒ 레이어 하나)
  select sum(l.qty_delta), min(l.occurred_on), count(*)::int into v_qty, v_recv_on, v_rows
  from public.inv_ledger l
  where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in'
    and l.doc_number = v_r.receipt_number and l.line_ref = v_ref and l.sku = v_sku and l.warehouse = v_wh and l.qty_delta > 0;
  if coalesce(v_rows, 0) = 0 then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', 0, 'layers_created', 0, 'layers_existing', 0, 'qty', 0, 'builder', c_version, 'warnings', '["no_ledger_rows_for_off_po"]'::jsonb);
  end if;

  -- 멱등 — 같은 4키(purchase · RCV · <diff>:offpo · sku · warehouse)의 레이어가 있으면 건너뛴다
  if exists (select 1 from public.inv_layer y
              where y.origin_type = 'purchase' and y.doc_number = v_r.receipt_number and y.line_ref = v_ref and y.sku = v_sku and y.warehouse = v_wh) then
    return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'resolution', v_d.resolution,
                              'ledger_rows', v_rows, 'layers_created', 0, 'layers_existing', 1, 'qty', v_qty, 'builder', c_version, 'warnings', '[]'::jsonb);
  end if;

  if v_d.resolution = 'accepted_free' then
    v_unit := 0; v_src := 'free';                                                                         -- ⭐ 낸 돈이 없다 — 진짜 0(unknown 아님 · over 선례)
  else
    -- ⭐ 사람이 입력한 단가(PO 통화) × 그 PO 의 환율(CAD per USD · 곱한다 · 기준통화면 ×1) — inv_layer_post_receipt 와 같은 식
    if v_d.unit_price is null or v_d.unit_price <= 0 then
      raise exception 'Off-PO % on % is billed but has no unit price — no cost layer was created', coalesce(v_sku, '?'), v_r.receipt_number;
    end if;
    select * into v_po from public.po where id = v_r.po_id;
    select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
    select k.value into v_base from public.inv_config k where k.key = 'base_currency';
    if v_base is null then raise exception 'inv_config.base_currency is not set — cannot tell which orders need an exchange rate — no cost layer was created'; end if;
    if v_cur is distinct from v_base then
      if v_po.exchange_rate is null or v_po.exchange_rate <= 0 then
        raise exception 'PO % is in % but has no % per % exchange rate — the off-PO cost cannot be worked out without it. Enter the rate in the order header and decide again — no cost layer was created',
          v_po.po_number, coalesce(v_cur, '?'), v_base, coalesce(v_cur, '?');
      end if;
      v_factor := v_po.exchange_rate;
    else
      v_factor := 1;
    end if;
    v_unit := v_d.unit_price * v_factor; v_src := 'manual';
  end if;

  insert into public.inv_layer (sku, warehouse, origin_type, doc_number, line_ref, parent_layer_id, received_on, age_known, qty, unit_cost, cost_source)
  values (v_sku, v_wh, 'purchase', v_r.receipt_number, v_ref, null, v_recv_on, true, v_qty, v_unit, v_src)
  returning id into v_layer_id;

  return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'warehouse', v_wh, 'resolution', v_d.resolution,
                            'ledger_rows', v_rows, 'layers_created', 1, 'layers_existing', 0, 'layer_id', v_layer_id,
                            'qty', v_qty, 'unit_price', v_d.unit_price, 'currency', v_cur, 'fx_rate', case when v_cur is distinct from v_base then v_factor end,
                            'unit_cost', v_unit, 'cost_source', v_src, 'cost_total_cad', v_qty * v_unit, 'received_on', v_recv_on,
                            'builder', c_version, 'warnings', '[]'::jsonb);
end;
$$;
comment on function public.inv_layer_post_receipt_off_po(uuid) is '⭐ 원가의 창구 · off-PO(⑤-6c1 · 2026-09-27) — 받아들인 off-PO 의 원장 행(RCV · line_ref <diff_id>:offpo · sku · warehouse)을 접어 inv_layer 한 행. accepted_free → unit_cost 0 · cost_source free. accepted_billed → po_receipt_diff.unit_price(PO 통화 · 사람 입력) × po.exchange_rate(CAD per USD · 곱한다 · 기준통화면 ×1) · cost_source manual. 멱등: 4키 레이어가 있으면 건너뛴다 · 원장 행이 없으면 경고만. inv_layer_apply() 재생성이 raw.diff_id 로 이 창구를 다시 부른다(ims_offpo). ⚠️ 입고의 확정을 요구하지 않는다(off-PO 결정은 확정과 독립 · 판정 43). ⚠️ inv_layer_post_charge 는 이 레이어(line_ref 접미어)에 landed 를 얹지 않는다. security invoker · append-only · inv-basis-3(2026-09-29): off_invoice 행(판정 88 ⑧)도 같은 창구 · 같은 line_ref 접미어 :offpo(열쇠는 diff id)';
revoke all on function public.inv_layer_post_receipt_off_po(uuid) from public, anon;
grant execute on function public.inv_layer_post_receipt_off_po(uuid) to authenticated;

create or replace function public.inv_post_receipt_off_po(p_diff_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'inv_post_receipt_off_po@2026-09-29.1';   -- inv-basis-3: off_invoice 행도 · 수량 = received − expected
  v_d        public.po_receipt_diff%rowtype;
  v_r        public.po_receipt%rowtype;
  v_po       public.po%rowtype;
  v_wh       text;
  v_sku      text;
  v_bin      text;
  v_ref      text;
  v_existing int;
  v_layer    jsonb;
  v_qty      numeric;                                                                                -- inv-basis-3: 장부에 넣는 수량 = received − expected(off_po 는 expected 0)
begin
  perform public.ims_require_write('receiving', 'posted');

  select * into v_d from public.po_receipt_diff where id = p_diff_id;
  if not found then raise exception 'Difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if not found then raise exception 'Receipt of difference % not found — nothing was posted to the ledger', p_diff_id; end if;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  if v_d.kind not in ('off_po', 'off_invoice') then
    raise exception 'Difference on % is a "%" line — only off-PO / off-invoice items are posted here (over → inv_post_receipt_over) — nothing was posted to the ledger', v_r.receipt_number, v_d.kind;
  end if;
  v_qty := v_d.received_qty - v_d.expected_qty;
  if v_d.resolved_at is null or v_d.resolution not in ('accepted_free', 'accepted_billed') then
    raise exception 'Off-PO % on % is not accepted (free or billed) — decide it first (po_receipt_diff_settle_off_po) — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if v_d.bin_id is null or v_d.placed_at is null then
    raise exception 'Off-PO % on % is not on a shelf yet — the warehouse puts it away first — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if v_qty <= 0 then raise exception 'Off-PO % on % has quantity % — nothing was posted to the ledger', coalesce(v_sku, '?'), v_r.receipt_number, v_qty; end if;
  select * into v_po from public.po where id = v_r.po_id;
  select w.name into v_wh from public.ref_warehouse w where w.id = v_r.warehouse_id;
  if v_wh is null then raise exception 'Warehouse of receipt % not found — nothing was posted to the ledger', v_r.receipt_number; end if;
  select b.name into v_bin from public.ref_bin b where b.id = v_d.bin_id;
  v_ref := v_d.id::text || ':offpo';                                                                  -- ⭐ 라인이 없다 — diff_id 가 열쇠 · 접미어로 유니크 7키 · 레이어 4키가 갈린다(:over 선례)

  -- 멱등 — 이미 행이 있으면 다시 쓰지 않는다 · 레이어만 다시(백필)
  select count(*) into v_existing from public.inv_ledger l
   where l.doc_type = 'purchase' and l.source = 'ims' and l.event_type = 'po_in' and l.doc_number = v_r.receipt_number and l.line_ref = v_ref;
  if v_existing > 0 then
    v_layer := public.inv_layer_post_receipt_off_po(p_diff_id);
    return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                              'already_posted', true, 'existing_rows', v_existing, 'rows_posted', 0, 'qty_posted', 0, 'bin', v_bin, 'layer', v_layer, 'warnings', '["already_posted"]'::jsonb);
  end if;

  -- 한 행 — 한 제품 · 한 칸 · occurred_on = 문서의 received_on(같은 배로 왔다 · 결정한 날이 아니다 · 일곱 묶음 4) · seq 1(유입)
  insert into public.inv_ledger (occurred_on, seq_hint, sku, warehouse, bin, qty_delta, event_type, doc_type, doc_number, doc_task_id, line_ref, amount, source, raw)
  values (
    v_r.received_on, 1, v_sku, v_wh, v_bin, v_qty, 'po_in', 'purchase', v_r.receipt_number, v_r.id::text, v_ref, null, 'ims',
    jsonb_build_object(
      'kind', case v_d.kind when 'off_invoice' then 'po_off_invoice' else 'po_off_po' end, 'poster', c_version,
      'diff_id', v_d.id, 'resolution', v_d.resolution, 'resolution_note', v_d.resolution_note, 'decided_by', v_d.resolved_by, 'decided_at', v_d.resolved_at,
      'unit_price', v_d.unit_price, 'currency_id', v_po.currency_id, 'exchange_rate', v_po.exchange_rate,
      'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'receipt_status', v_r.status, 'po_id', v_po.id, 'po_number', v_po.po_number,
      'product_id', v_d.product_id, 'sku', v_sku,
      'warehouse_id', v_r.warehouse_id, 'warehouse', v_wh, 'bin_id', v_d.bin_id, 'bin', v_bin, 'placed_by', v_d.placed_by, 'placed_at', v_d.placed_at,
      'received_on', v_r.received_on, 'qty', v_qty, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty,
      'cost_rule', case v_d.resolution when 'accepted_free' then 'free — unit_cost 0 (nothing was paid)' else 'billed — unit_price typed from the invoice (PO currency) × po.exchange_rate' end));

  -- ⭐ 레이어 — 같은 트랜잭션(함께 서거나 함께 죽는다)
  v_layer := public.inv_layer_post_receipt_off_po(p_diff_id);

  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_po.po_number, 'sku', v_sku,
                            'already_posted', false, 'existing_rows', 0, 'rows_posted', 1, 'qty_posted', v_qty, 'bin', v_bin, 'occurred_on', v_r.received_on,
                            'layer', v_layer, 'warnings', '[]'::jsonb);
exception
  when unique_violation then
    raise exception 'Off-PO % on % — a ledger row with the same key already exists (%) — nothing was posted to the ledger', p_diff_id, coalesce(v_r.receipt_number, '?'), sqlerrm;
end;
$$;
comment on function public.inv_post_receipt_off_po(uuid) is '⭐ 원장의 창구 · off-PO(⑤-6c1 · 2026-09-27 · 판정 43) — 받아들인 off-PO(accepted_free · accepted_billed · 놓은 칸 있음)를 inv_ledger 에 po_in 한 행으로 넣는다: doc_type purchase · doc_number RCV · doc_task_id receipt id · line_ref <diff_id>:offpo(라인이 없어 diff 가 열쇠) · bin = 놓은 칸 · qty = received_qty · occurred_on = po_receipt.received_on(같은 배 · 일곱 묶음 4) · seq_hint 1 · source ims · raw.kind po_off_po(raw.diff_id = 재생성 열쇠). 끝에 inv_layer_post_receipt_off_po 를 같은 트랜잭션으로. 멱등: 행이 있으면 already_posted · 레이어만 다시. ⚠️ 입고의 확정을 요구하지 않는다(확정과 독립 · 확정은 po_line 기준이라 이 행을 모른다). 거부(문장): 권한(receiving) · 없는 차이 · off_po 아님 · 안 받아들임 · 선반에 없음 · 수량 0. security invoker · append-only · inv-basis-3(2026-09-29): off_invoice 행(판정 88 ⑧)도 같은 창구 · 수량 = received − expected · raw.kind po_off_invoice';
revoke all on function public.inv_post_receipt_off_po(uuid) from public, anon;
grant execute on function public.inv_post_receipt_off_po(uuid) to authenticated;


-- ═══ 5) 창고 창구 — wms_recv_complete(20260929010938:831 바이트 그대로 + 선언 3 · PO 갈래 두 칸 검사 · 판정 100 · 트랜스퍼 갈래 무접촉) · wms_recv_off_po(20260929010938:869 · 3줄) · _putaway(두 어휘) · _removed(20260928025627:73 · :106 · 옛 off_po 만 — 판정 99: off_invoice 는 거절이 없어 뺄 것이 없다 · 문장으로 거부) ═══
create or replace function public.wms_recv_complete(p_receipt_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_c public.wms_receipt_complete%rowtype; v_open int; v_arr jsonb; v_ob_n int; v_ob_txt text; x record;   -- 판정 100: 초과분이 놓인 칸 수 · 문장 · 줄 루프
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_r from public.po_receipt r where r.id = p_receipt_id;
  if not found then raise exception 'Receipt not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_r.warehouse_id) then
    raise exception 'Receipt % is at another warehouse — you are not set up for it — nothing was saved', v_r.receipt_number;
  end if;
  if v_r.status <> 'draft' then raise exception 'Receipt % is already % — nothing to complete — nothing was saved', v_r.receipt_number, v_r.status; end if;
  if exists (select 1 from public.wms_receipt_complete c where c.receipt_id = p_receipt_id and c.completed) then
    raise exception 'Receipt % is already completed in the warehouse — nothing was saved', v_r.receipt_number;
  end if;
  if not exists (select 1 from public.po_receipt_work w where w.receipt_id = p_receipt_id) then
    raise exception 'Receipt % has nothing counted — count at least one line before completing — nothing was saved', v_r.receipt_number;
  end if;
  select count(*) into v_open from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.bin_id is null;
  if v_r.transfer_id is not null and v_open > 0 then                                      -- tr-3a 판정 66 · 70: 트랜스퍼는 Complete 가 곧 도착(칸에 들어온다) — 칸 없는 줄이 있으면 받지 않는다
    raise exception 'Receipt % — % counted row(s) still have no bin; put them away first (a transfer arrives into its bins at Complete) — nothing was saved', v_r.receipt_number, v_open;
  end if;
  if v_r.transfer_id is null then                                                             -- 판정 100(inv-basis-6): PO 입고 — 더 온 몫이 두 칸에 나뉘면 여기서 먼저 막는다(입고가 열려 있을 때 창고가 한 칸으로 옮긴다 · 오피스 확정의 같은 검사는 안전띠)
    for x in                                                                                  --   기준 = 확정 인보이스 − 앞선 입고(po_receipt_confirm_by ⓑ 와 같은 식) · 칸 0(초과분이 칸 없는 줄에만)은 지금처럼 지나간다(lines_without_bin 경고 · 확정이 「still have no bin」 으로 막는다)
      select pl.id as po_line_id, pl.line_no, pr.sku,
             coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                        where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0)
               - coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as expected,
             coalesce((select sum(w.qty_ea) from public.po_receipt_work w where w.receipt_id = p_receipt_id and w.po_line_id = pl.id), 0) as counted
      from public.po_line pl join public.product pr on pr.id = pl.product_id
      where pl.po_id = v_r.po_id
      order by pl.line_no
    loop
      if x.counted > x.expected then
        select b.bins, b.bins_txt into v_ob_n, v_ob_txt from public.po_receipt_over_bins(p_receipt_id, x.po_line_id, x.expected) b;
        if coalesce(v_ob_n, 0) > 1 then
          raise exception 'Line % (%) on %: % EA more than the confirmed invoice (% counted · % invoiced) sit in more than one bin (%) — move the extra into one bin before Complete, or lower the count — nothing was saved',
            x.line_no, x.sku, v_r.receipt_number, x.counted - greatest(x.expected, 0), x.counted, greatest(x.expected, 0), coalesce(v_ob_txt, '?');
        end if;
      end if;
    end loop;
  end if;
  update public.wms_task_holds set resumed_at = now(), resumed_by = v_staff where receipt_id = p_receipt_id and resumed_at is null;   -- 열린 보류가 있으면 Complete 가 닫는다(운영 finishReceipt 와 같다)
  insert into public.wms_receipt_complete as c (receipt_id, completed, completed_by, completed_at)
  values (p_receipt_id, true, v_staff, now())
  on conflict (receipt_id) do update set completed = true, completed_by = v_staff, completed_at = now()
  returning * into v_c;
  if v_r.transfer_id is not null then v_arr := public.tf_arrive(p_receipt_id, v_staff); end if;   -- tr-3a 판정 66 · 68 · 70: 같은 트랜잭션에 도착 — 입고 줄 · 차이 기록 · 원장 · 레이어 · received · 입고 확정(오피스 확정 없음)
  return jsonb_build_object('receipt_id', p_receipt_id, 'receipt_number', v_r.receipt_number, 'completed', true, 'completed_by', v_c.completed_by, 'completed_at', v_c.completed_at,
                            'lines_without_bin', v_open, 'warnings', case when v_open > 0 then jsonb_build_array('lines_without_bin') else '[]'::jsonb end)
         || case when v_arr is null then '{}'::jsonb else jsonb_build_object('arrived', v_arr) end;   -- PO 반환 모양 무변 · 트랜스퍼만 arrived 를 더한다
end;
$$;
comment on function public.wms_recv_complete(uuid) is '⑤-3b 창고 Complete(판정 28 · 30) · tr-3a 판정 66 · 70: 트랜스퍼는 Complete = 도착(tf_arrive · 칸 없는 줄 거부) · inv-basis-6 판정 100: PO 입고는 더 온 몫(센 것 − 확정 인보이스 + 앞선 입고)이 두 칸에 나뉘면 여기서 거부 — 입고가 열려 있을 때 창고가 한 칸으로 옮긴다(같은 검사가 po_receipt_confirm_by 에 안전띠로 남는다 · 식은 po_receipt_over_bins 한 곳) · 칸 없는 줄만 있는 초과는 지금처럼 Complete + lines_without_bin 경고 · 반환 모양 무변';

create or replace function public.wms_recv_off_po(p_receipt_id uuid, p_product_id uuid, p_qty_ea numeric) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_r public.po_receipt%rowtype; v_p public.product%rowtype; v_d public.po_receipt_diff%rowtype; v_new boolean := false;
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;   -- so_current_staff 는 authenticated 회수 · 원본 셸 방식(§5 ②)
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  v_r := public.wms_recv_gate(p_receipt_id);
  if v_r.status <> 'draft' then raise exception 'Receipt % is % — off-PO items can be added only while draft — nothing was saved', v_r.receipt_number, v_r.status; end if;
  if v_r.transfer_id is not null then raise exception 'Receipt % is a transfer arrival — items that were not sent are settled in the in-transit settlement (next step), not as off-PO — nothing was saved', v_r.receipt_number; end if;   -- tr-3a: 초과 · 모르는 물건은 tr-3b
  if p_qty_ea is null or p_qty_ea <= 0 then raise exception 'Off-PO quantity must be more than 0 — nothing was saved'; end if;
  select * into v_p from public.product p where p.id = p_product_id;
  if not found then raise exception 'Product not found — nothing was saved'; end if;
  if exists (select 1 from public.po_line l where l.po_id = v_r.po_id and l.product_id = p_product_id) then
    raise exception 'Product % is on this PO — count it on its line, not as off-PO — nothing was saved', v_p.sku;
  end if;
  select * into v_d from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.kind = 'off_invoice' and d.product_id = p_product_id and d.resolved_at is null;   -- inv-basis-3 · 판정 88 ⑧: PO 밖 품목도 off_invoice 한 길
  if found then
    update public.po_receipt_diff set received_qty = received_qty + p_qty_ea, updated_by = v_staff where id = v_d.id returning * into v_d;
  else
    insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty, note, updated_by)
    values (p_receipt_id, v_r.po_id, null, p_product_id, 'off_invoice', 0, p_qty_ea, 'off-invoice (WMS receiving · not on the PO) — decision pending', v_staff) returning * into v_d;
    v_new := true;
  end if;
  return jsonb_build_object('diff_id', v_d.id, 'receipt_number', v_r.receipt_number, 'sku', v_p.sku, 'product_id', p_product_id, 'kind', 'off_invoice', 'received_qty', v_d.received_qty, 'added', p_qty_ea, 'created', v_new, 'declared_by', v_staff);
end;
$$;

create or replace function public.wms_recv_off_po_putaway(p_diff_id uuid, p_bin_id uuid, p_done boolean default true) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_d public.po_receipt_diff%rowtype; v_r public.po_receipt%rowtype; v_b public.ref_bin%rowtype; v_sku text; v_now timestamptz := now();
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_d from public.po_receipt_diff d where d.id = p_diff_id for update;
  if not found then raise exception 'Off-PO item not found — nothing was saved'; end if;
  if v_d.kind not in ('off_po', 'off_invoice') then raise exception 'This difference is a "%" line, not an off-PO / off-invoice item — nothing was saved', v_d.kind; end if;   -- inv-basis-3
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  if v_d.resolved_at is not null then
    raise exception 'Off-PO % was already decided as "%" by the office — its bin can no longer be changed here — nothing was saved', coalesce(v_sku, '?'), v_d.resolution;
  end if;
  v_r := public.wms_recv_gate(v_d.receipt_id);                 -- 창고 · 창고 Complete 잠금(작업 줄과 같은 규칙)
  v_b := public.po_receipt_bin_check(v_r.id, p_bin_id);        -- 그 입고의 창고 · 활성
  update public.po_receipt_diff
     set bin_id = p_bin_id,
         placed_by = case when coalesce(p_done, true) then v_staff else null end,
         placed_at = case when coalesce(p_done, true) then v_now else null end,
         updated_by = v_staff
   where id = p_diff_id;
  return jsonb_build_object('diff_id', p_diff_id, 'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'qty', v_d.received_qty,
                            'bin_id', v_b.id, 'bin', v_b.name, 'zone', v_b.zone, 'placed', coalesce(p_done, true),
                            'placed_by', case when coalesce(p_done, true) then v_staff end, 'placed_at', case when coalesce(p_done, true) then v_now end);
end;
$$;

create or replace function public.wms_recv_off_po_removed(p_diff_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_staff uuid; v_d public.po_receipt_diff%rowtype; v_r public.po_receipt%rowtype; v_sku text; v_bin text; v_now timestamptz := now();
begin
  perform public.ims_require_write('wms_receiving', 'saved');   -- ⭐ 첫 줄
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_d from public.po_receipt_diff d where d.id = p_diff_id for update;
  if not found then raise exception 'Off-PO item not found — nothing was saved'; end if;
  if v_d.kind not in ('off_po', 'off_invoice') then raise exception 'This difference is a "%" line, not an off-PO / off-invoice item — nothing was saved', v_d.kind; end if;   -- inv-basis-3
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select * into v_r from public.po_receipt r where r.id = v_d.receipt_id;
  if v_d.kind = 'off_invoice' then   -- 판정 99: off-invoice 는 거절이 없다 — 더 온 것은 이미 창고에 있고 돌려보내기는 입고와 따로
    raise exception 'Off-invoice % on % is never rejected (an extra that arrived is already in the warehouse) — there is nothing to take off the shelf here; a return to the supplier is done separately — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if not public.ims_can_warehouse(v_r.warehouse_id) then          -- Complete 잠금은 안 본다 — 거절된 물건은 입고가 닫힌 뒤에도 뺀다
    raise exception 'Receipt % is at another warehouse — you are not set up for it — nothing was saved', v_r.receipt_number;
  end if;
  if v_d.resolution is distinct from 'rejected' then
    raise exception 'Off-PO % is % — only a rejected item is taken off the shelf — nothing was saved', coalesce(v_sku, '?'), coalesce('decided as "' || v_d.resolution || '"', 'not decided yet');
  end if;
  if v_d.bin_id is null then raise exception 'Off-PO % was never put on a shelf — there is nothing to take off — nothing was saved', coalesce(v_sku, '?'); end if;
  if v_d.removed_at is not null then raise exception 'Off-PO % was already taken off the shelf on % — nothing was saved', coalesce(v_sku, '?'), to_char(v_d.removed_at at time zone 'America/Toronto', 'YYYY-MM-DD'); end if;
  select b.name into v_bin from public.ref_bin b where b.id = v_d.bin_id;
  update public.po_receipt_diff set removed_by = v_staff, removed_at = v_now, updated_by = v_staff where id = p_diff_id;
  return jsonb_build_object('diff_id', p_diff_id, 'receipt_number', v_r.receipt_number, 'sku', v_sku, 'qty', v_d.received_qty - v_d.expected_qty, 'bin', v_bin, 'removed_by', v_staff, 'removed_at', v_now);   -- inv-basis-3: 뺀 수량 = 초과분(off_po 는 expected 0)
end;
$$;


-- ═══ 6) 결정 창구 po_receipt_diff_settle_off_invoice — settle_off_po(20260928025627:310) 를 새 이름으로 · 바뀐 것: 어휘 · 기본 단가(판정 93 ⓓ) · 수량 = received − expected · 옛 어휘는 옛 창구로 안내 ═══
create function public.po_receipt_diff_settle_off_invoice(p_diff_id uuid, p_resolution text, p_unit_price numeric default null, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_name    text;
  v_d       public.po_receipt_diff%rowtype;
  v_r       public.po_receipt%rowtype;
  v_po      public.po%rowtype;
  v_note    text;
  v_n       int;
  v_open    int;
  v_now     timestamptz := now();
  v_sku     text;
  v_bin     text;
  v_cur     text;
  v_base    text;
  v_post    jsonb;
  v_price   numeric;                                                                                  -- inv-basis-3 · 판정 93 ⓓ: 입력 단가 · 없으면 기본값
  v_psrc    text;
  v_qty     numeric;                                                                                  -- 초과분 = received − expected(PO 밖 품목은 expected 0)
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id, s.name into v_staff, v_name from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- 어휘 둘 — accepted_free(받는다 · 원가 0) · accepted_billed(받는다 · 단가) · ⭐ 판정 99: rejected 없음 — 더 온 것은 이미 창고에 있다 · 돌려보내기는 입고와 따로
  if p_resolution is null or p_resolution not in ('accepted_free', 'accepted_billed') then
    raise exception 'Decision "%" is not one of accepted_free, accepted_billed — an extra that arrived is already in the warehouse; a return to the supplier is done separately, not here — nothing was saved', coalesce(p_resolution, '(empty)');
  end if;
  v_note := nullif(btrim(p_note), '');

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;                              -- 잠금 — 같은 물건을 두 사람이 동시에 정하지 않게(재고가 두 번 들어가면 안 된다)
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select b.name into v_bin from public.ref_bin b where b.id = v_d.bin_id;

  if v_d.kind <> 'off_invoice' then
    raise exception 'This difference on % is a "%" line — only off-invoice items are decided here. A short difference is settled with po_receipt_diff_resolve, an old over difference with po_receipt_diff_settle_over, an old off-PO item with po_receipt_diff_settle_off_po — nothing was saved',
      v_r.receipt_number, v_d.kind;
  end if;
  v_qty := v_d.received_qty - v_d.expected_qty;
  if v_d.resolved_at is not null then
    raise exception 'Off-invoice % on % was already decided as "%" by % on %. % — nothing was saved',
      coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution,
      coalesce((select s.name from public.ims_staff s where s.id = v_d.resolved_by), '?'),
      to_char(v_d.resolved_at at time zone 'America/Toronto', 'YYYY-MM-DD'),
      'The stock is already on the ledger so it cannot be decided twice';   -- 판정 99: 결정은 둘 다 받는 것 — 정해진 행은 늘 장부에 있다
  end if;
  if v_qty <= 0 then raise exception 'Off-invoice % on % has quantity % — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number, v_qty; end if;
  if p_resolution like 'accepted%' and (v_d.bin_id is null or v_d.placed_at is null) then
    raise exception 'Off-invoice % on % is not on a shelf yet — the warehouse puts it away first, then it can be accepted (the ledger needs the bin) — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if p_resolution = 'accepted_billed' then
    v_price := p_unit_price; v_psrc := 'entered';
    if v_price is null and v_d.po_line_id is not null then                                                 -- 판정 93 ⓓ: 기본값 = 그 PO 줄의 마지막 확정 인보이스 단가 · 없으면 PO 단가(PO 밖 품목은 기본값이 없다 — 입력 필수)
      select il.unit_price into v_price from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
       where il.po_line_id = v_d.po_line_id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'
       order by i.confirmed_at desc nulls last, i.created_at desc, il.line_no desc limit 1;
      v_psrc := 'last_confirmed_invoice';
      if v_price is null then select pl.unit_price into v_price from public.po_line pl where pl.id = v_d.po_line_id; v_psrc := 'po_line'; end if;
    end if;
    if v_price is null or v_price <= 0 then
      raise exception 'Accepting off-invoice % on % as billed needs the unit price (in the order currency, more than 0) — there is no invoice or order line price to default to — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number;
    end if;
    select * into v_po from public.po where id = v_r.po_id;
    select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
    select k.value into v_base from public.inv_config k where k.key = 'base_currency';
    if v_cur is distinct from v_base and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
      raise exception 'PO % is in % but has no % per % exchange rate — the off-PO cost cannot be worked out without it. Enter the rate in the order header and decide again — nothing was saved',
        v_po.po_number, coalesce(v_cur, '?'), coalesce(v_base, '?'), coalesce(v_cur, '?');
    end if;
  elsif p_unit_price is not null then
    raise exception 'A unit price goes only with accepted_billed — nothing was saved';
  end if;

  update public.po_receipt_diff
     set resolution = p_resolution, resolution_note = v_note, unit_price = case when p_resolution = 'accepted_billed' then v_price end,
         resolved_by = v_staff, resolved_at = v_now, updated_by = v_staff
   where id = p_diff_id and resolved_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Off-invoice % on % was not saved — it may have been decided by someone else just now — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number; end if;

  -- ⭐ 받는다 → 재고: 창구가 원장(한 행 · 놓은 칸)과 레이어(free 0 · billed 입력 단가 × 환율)를 넣는다 — 거부하면 결정도 함께 되돌아간다
  if p_resolution like 'accepted%' then
    v_post := public.inv_post_receipt_off_po(p_diff_id);
  end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  return jsonb_build_object(
    'diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number, 'receipt_status', v_r.status,
    'kind', v_d.kind, 'sku', v_sku, 'product_id', v_d.product_id, 'po_line_id', v_d.po_line_id, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty, 'qty', v_qty, 'bin_id', v_d.bin_id, 'bin', v_bin, 'placed_by', v_d.placed_by, 'placed_at', v_d.placed_at,
    'resolution', p_resolution, 'resolution_note', v_note, 'unit_price', case when p_resolution = 'accepted_billed' then v_price end, 'unit_price_source', case when p_resolution = 'accepted_billed' then v_psrc end,
    'resolved_by', v_staff, 'resolved_by_name', v_name, 'resolved_at', v_now,
    'qty_added', coalesce(v_post->'qty_posted', '0'::jsonb), 'unit_cost', v_post->'layer'->'unit_cost', 'cost_source', v_post->'layer'->>'cost_source', 'layer_id', v_post->'layer'->'layer_id',
    'ledger', v_post,
    'open_diffs_left', v_open);   -- 판정 99: remove_from_bin 키 없음(거절이 없다)
end;
$$;
comment on function public.po_receipt_diff_settle_off_invoice(uuid, text, numeric, text) is 'inv-basis-3 ⭐ off-invoice 결정(판정 88 ⑧ · 93 ⓓ · 2026-09-29) — 더 온 것 한 길(확정 인보이스 초과 · 인보이스에 없는 줄 · PO 밖 품목)을 오피스 Purchase Receipts 에서 한 번에: accepted_free(받는다 · 원가 0) · accepted_billed(받는다 · 단가 = 입력값 · 없으면 그 PO 줄의 마지막 확정 인보이스 단가 · 없으면 PO 단가 · PO 밖 품목은 입력 필수 · CAD = × po.exchange_rate) · ⭐ 판정 99(2026-09-29 밤): rejected 없음 — 더 온 것은 이미 창고에 있다 · 돌려보내기(선반에서 빼기 · 공급처 크레딧)는 입고와 따로 · 반환에 remove_from_bin 없음. 수량 = received − expected. accepted 면 같은 트랜잭션으로 inv_post_receipt_off_po(원장 한 행 · 놓은 칸) → inv_layer_post_receipt_off_po(레이어 · line_ref <diff>:offpo). 막는 것(문장): 권한(receiving) · 어휘 밖(rejected 포함 — 문장이 「따로 한다」고 말한다) · 없는 차이 · off_invoice 아님(옛 over → settle_over · 옛 off_po → settle_off_po) · 이미 결정 · 수량 0 · 선반에 없음 · billed 인데 단가 없음/≤0 · 환율 없음 · 단가를 accepted_billed 아닌 데 줌 · 남이 사이에 결정. 받은 뒤 되돌리기 없음(po_receipt_diff_reopen 이 거부). security invoker · 잠금 for update';
revoke all on function public.po_receipt_diff_settle_off_invoice(uuid, text, numeric, text) from public, anon;
grant execute on function public.po_receipt_diff_settle_off_invoice(uuid, text, numeric, text) to authenticated;


-- ═══ 7) 옛 결정 창구 둘 · reopen — 마지막 정의(20260928025627:310 · :408 · :558) 바이트 그대로 + 새 어휘 안내 1줄씩(옛 kind 행에만 돈다 — 그대로) ═══
create or replace function public.po_receipt_diff_settle_off_po(p_diff_id uuid, p_resolution text, p_unit_price numeric default null, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_name    text;
  v_d       public.po_receipt_diff%rowtype;
  v_r       public.po_receipt%rowtype;
  v_po      public.po%rowtype;
  v_note    text;
  v_n       int;
  v_open    int;
  v_now     timestamptz := now();
  v_sku     text;
  v_bin     text;
  v_cur     text;
  v_base    text;
  v_post    jsonb;
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id, s.name into v_staff, v_name from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- 어휘 셋 — accepted_free(받는다 · 원가 0) · accepted_billed(받는다 · 인보이스 단가) · rejected(장부 없음 · 선반에서 뺀다)
  if p_resolution is null or p_resolution not in ('accepted_free', 'accepted_billed', 'rejected') then
    raise exception 'Decision "%" is not one of accepted_free, accepted_billed, rejected — nothing was saved', coalesce(p_resolution, '(empty)');
  end if;
  v_note := nullif(btrim(p_note), '');

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;                              -- 잠금 — 같은 물건을 두 사람이 동시에 정하지 않게(재고가 두 번 들어가면 안 된다)
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select b.name into v_bin from public.ref_bin b where b.id = v_d.bin_id;

  if v_d.kind <> 'off_po' then
    raise exception 'This difference on % is a "%" line — only old off-PO items are decided here. An off-invoice item (2026-09-29 rule) is decided with po_receipt_diff_settle_off_invoice, a short difference with po_receipt_diff_resolve, an old over difference with po_receipt_diff_settle_over — nothing was saved',   -- inv-basis-3
      v_r.receipt_number, v_d.kind;
  end if;
  if v_d.resolved_at is not null then
    raise exception 'Off-PO % on % was already decided as "%" by % on %. % — nothing was saved',
      coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution,
      coalesce((select s.name from public.ims_staff s where s.id = v_d.resolved_by), '?'),
      to_char(v_d.resolved_at at time zone 'America/Toronto', 'YYYY-MM-DD'),
      case when v_d.resolution like 'accepted%' then 'The stock is already on the ledger so it cannot be decided twice' else 'Reopen it first if that was wrong' end;
  end if;
  if v_d.received_qty <= 0 then raise exception 'Off-PO % on % has quantity % — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number, v_d.received_qty; end if;
  if p_resolution like 'accepted%' and (v_d.bin_id is null or v_d.placed_at is null) then
    raise exception 'Off-PO % on % is not on a shelf yet — the warehouse puts it away first, then it can be accepted (the ledger needs the bin) — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number;
  end if;
  if p_resolution = 'accepted_billed' then
    if p_unit_price is null or p_unit_price <= 0 then
      raise exception 'Accepting off-PO % on % as billed needs the unit price from the invoice (in the order currency, more than 0) — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number;
    end if;
    select * into v_po from public.po where id = v_r.po_id;
    select c.code into v_cur  from public.ref_currency c where c.id = v_po.currency_id;
    select k.value into v_base from public.inv_config k where k.key = 'base_currency';
    if v_cur is distinct from v_base and (v_po.exchange_rate is null or v_po.exchange_rate <= 0) then
      raise exception 'PO % is in % but has no % per % exchange rate — the off-PO cost cannot be worked out without it. Enter the rate in the order header and decide again — nothing was saved',
        v_po.po_number, coalesce(v_cur, '?'), coalesce(v_base, '?'), coalesce(v_cur, '?');
    end if;
  elsif p_unit_price is not null then
    raise exception 'A unit price goes only with accepted_billed — nothing was saved';
  end if;

  update public.po_receipt_diff
     set resolution = p_resolution, resolution_note = v_note, unit_price = case when p_resolution = 'accepted_billed' then p_unit_price end,
         resolved_by = v_staff, resolved_at = v_now, updated_by = v_staff
   where id = p_diff_id and resolved_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Off-PO % on % was not saved — it may have been decided by someone else just now — nothing was saved', coalesce(v_sku, '?'), v_r.receipt_number; end if;

  -- ⭐ 받는다 → 재고: 창구가 원장(한 행 · 놓은 칸)과 레이어(free 0 · billed 입력 단가 × 환율)를 넣는다 — 거부하면 결정도 함께 되돌아간다
  if p_resolution like 'accepted%' then
    v_post := public.inv_post_receipt_off_po(p_diff_id);
  end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  return jsonb_build_object(
    'diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number, 'receipt_status', v_r.status,
    'kind', v_d.kind, 'sku', v_sku, 'product_id', v_d.product_id, 'qty', v_d.received_qty, 'bin_id', v_d.bin_id, 'bin', v_bin, 'placed_by', v_d.placed_by, 'placed_at', v_d.placed_at,
    'resolution', p_resolution, 'resolution_note', v_note, 'unit_price', case when p_resolution = 'accepted_billed' then p_unit_price end,
    'resolved_by', v_staff, 'resolved_by_name', v_name, 'resolved_at', v_now,
    'qty_added', coalesce(v_post->'qty_posted', '0'::jsonb), 'unit_cost', v_post->'layer'->'unit_cost', 'cost_source', v_post->'layer'->>'cost_source', 'layer_id', v_post->'layer'->'layer_id',
    'ledger', v_post,
    'remove_from_bin', case when p_resolution = 'rejected' and v_d.bin_id is not null then jsonb_build_object('bin', v_bin, 'qty', v_d.received_qty, 'placed_by', v_d.placed_by) end,
    'open_diffs_left', v_open);
end;
$$;

create or replace function public.po_receipt_diff_settle_over(p_diff_id uuid, p_resolution text, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_name    text;
  v_d       public.po_receipt_diff%rowtype;
  v_r       public.po_receipt%rowtype;
  v_note    text;
  v_n       int;
  v_open    int;
  v_now     timestamptz := now();
  v_sku     text;
  v_line_no int;
  v_fam     jsonb;
  v_post    jsonb;
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id, s.name into v_staff, v_name from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- 이유 셋 — free(공짜 · 원가 0) · billed(추가 청구 · 발주 단가) · credited(다음에 깎아 줌 · 발주 단가). returned 는 없다(거의 없다 · 생기면 그때).
  if p_resolution is null or p_resolution not in ('free', 'billed', 'credited') then
    raise exception 'Reason "%" is not one of free, billed, credited — nothing was saved', coalesce(p_resolution, '(empty)');
  end if;
  v_note := nullif(btrim(p_note), '');

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;                              -- 잠금 — 같은 차이를 두 사람이 동시에 닫지 않게(재고가 두 번 들어가면 안 된다)
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  select pr.sku into v_sku from public.product pr where pr.id = v_d.product_id;
  select pl.line_no into v_line_no from public.po_line pl where pl.id = v_d.po_line_id;

  -- ① over 만 — short 는 _resolve 가 닫는다 · off_po 는 형제 함수 po_receipt_diff_settle_off_po 가 정한다(⑤-6c1)
  if v_d.kind <> 'over' then
    raise exception 'Line % (%) on % is a "%" difference — only old over differences are settled here. An off-invoice item (2026-09-29 rule) is decided with po_receipt_diff_settle_off_invoice, a short difference with po_receipt_diff_resolve, an old off-PO item with po_receipt_diff_settle_off_po — nothing was saved',   -- inv-basis-3
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.kind;
  end if;
  -- ② 이미 닫힘 — 누가 무엇으로 언제 · ⚠️ over 는 reopen 이 없다(재고가 움직였다)
  if v_d.resolved_at is not null then
    raise exception 'Line % (%) on % was already settled as "%" by % on % and the extra is already in stock — it cannot be settled twice — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.resolution,
      coalesce((select s.name from public.ims_staff s where s.id = v_d.resolved_by), '?'),
      to_char(v_d.resolved_at at time zone 'America/Toronto', 'YYYY-MM-DD');
  end if;
  if v_d.received_qty - v_d.expected_qty <= 0 then
    raise exception 'Line % (%) on % says over but received % is not above expected % — nothing was saved',
      coalesce(v_line_no::text, '?'), coalesce(v_sku, '?'), v_r.receipt_number, v_d.received_qty, v_d.expected_qty;
  end if;

  update public.po_receipt_diff
     set resolution = p_resolution, resolution_note = v_note, resolved_by = v_staff, resolved_at = v_now
   where id = p_diff_id and resolved_at is null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Line % on % was not saved — it may have been settled by someone else just now — nothing was saved', coalesce(v_line_no::text, '?'), v_r.receipt_number; end if;

  -- ⭐ 재고 — 창구가 원장(초과분만 · 빈 별)과 레이어(free 0 · 그 밖은 기준 레이어 값)를 넣는다. 원가 규칙은 창구 안에 산다 — 여기서는 부르기만.
  v_post := public.inv_post_receipt_over(p_diff_id);

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members)
    into v_fam
  from public.po_family_lines(v_d.po_id) f where f.product_id = v_d.product_id;

  return jsonb_build_object(
    'diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number,
    'kind', v_d.kind, 'sku', v_sku, 'line_no', v_line_no, 'expected_qty', v_d.expected_qty, 'received_qty', v_d.received_qty,
    'resolution', p_resolution, 'resolution_note', v_note, 'resolved_by', v_staff, 'resolved_by_name', v_name, 'resolved_at', v_now,
    'qty_added', v_post->'qty_posted', 'unit_cost', v_post->'layer'->'unit_cost', 'cost_source', v_post->'layer'->>'cost_source', 'layer_id', v_post->'layer'->'layer_id',
    'ledger', v_post,
    'family', v_fam,
    'open_diffs_left', v_open);
end;
$$;

create or replace function public.po_receipt_diff_reopen(p_diff_id uuid, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_d     public.po_receipt_diff%rowtype;
  v_r     public.po_receipt%rowtype;
  v_n     int;
  v_open  int;
  v_note  text;
begin
  perform public.ims_require_write('receiving', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_d from public.po_receipt_diff where id = p_diff_id for update;
  if not found then raise exception 'Difference % not found — nothing was saved', p_diff_id; end if;
  select * into v_r from public.po_receipt where id = v_d.receipt_id;
  if v_d.resolved_at is null then
    raise exception 'This difference on % is not settled — there is nothing to reopen — nothing was saved', v_r.receipt_number;
  end if;
  -- ⭐ 2026-09-20 over 닫기 — over 는 닫히는 순간 초과분이 원장·레이어에 들어갔다(재고가 움직였다). 세 칸만 비우면 재고는 남고 기록만 사라진다.
  --   원장은 append-only 라 되돌리려면 반대 사건(상쇄)을 남기는 별도 길이 필요하다 — 아직 없다. 그래서 거부하고 무엇을 해야 하는지 말한다.
  if v_d.kind = 'over' then
    raise exception 'Line on % was settled as "%" and the extra % went into stock — it cannot be reopened, because the stock entry is already on the ledger (append-only). To undo it an offsetting stock entry is needed, which is not built yet — nothing was saved',
      v_r.receipt_number, v_d.resolution, v_d.received_qty - v_d.expected_qty;
  end if;
  -- ⑤-6c1 off-PO — accepted(free · billed)는 받는 순간 원장 · 레이어에 들어갔다(일곱 묶음 6 · 받은 뒤 되돌리기 없음) · 옛 off_po 의 rejected 는 장부에 아무것도 없어 되돌릴 수 있다 · 판정 99: off_invoice 는 결정이 둘 다 받는 것이라 되돌릴 길이 없다
  if v_d.kind in ('off_po', 'off_invoice') and v_d.resolution like 'accepted%' then   -- inv-basis-3: off_invoice 도 받은 뒤 되돌리기 없음(판정 99 뒤 off_invoice 는 이 갈래뿐)
    raise exception 'Off-PO item on % was accepted as "%" and % went into stock — it cannot be reopened, because the stock entry is already on the ledger (append-only). To undo it an offsetting stock entry is needed, which is not built yet — nothing was saved',
      v_r.receipt_number, v_d.resolution, v_d.received_qty - v_d.expected_qty;   -- inv-basis-3: 장부에 든 수량 = 초과분(off_po 는 expected 0)
  end if;
  if v_d.kind = 'off_po' and v_d.resolution = 'rejected' and v_d.removed_at is not null then   -- inv-basis-3 · 판정 92: 선반에서 뺀 뒤에는 되돌리지 않는다(CHECK removed_ck 의 날것 오류 대신 문장) · 판정 99: 옛 off_po 만(off_invoice 는 거절이 없다)
    raise exception 'Off-PO item on % was rejected and already taken off the shelf on % — it cannot be reopened; if it is back, the warehouse scans it again as a new item — nothing was saved',
      v_r.receipt_number, to_char(v_d.removed_at at time zone 'America/Toronto', 'YYYY-MM-DD');
  end if;

  v_note := nullif(btrim(p_note), '');
  update public.po_receipt_diff
     set resolution = null, resolved_by = null, resolved_at = null,
         resolution_note = case when v_note is null then resolution_note
                                else 'reopened: ' || v_note || coalesce(' | was: ' || resolution || coalesce(' — ' || resolution_note, ''), '') end
   where id = p_diff_id and resolved_at is not null;
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Difference on % was not saved — it may have been reopened by someone else just now — nothing was saved', v_r.receipt_number; end if;

  select count(*) into v_open from public.po_receipt_diff d where d.receipt_id = v_d.receipt_id and d.resolved_at is null;
  return jsonb_build_object('diff_id', v_d.id, 'receipt_id', v_d.receipt_id, 'receipt_number', v_r.receipt_number, 'kind', v_d.kind,
                            'was_resolution', v_d.resolution, 'was_resolved_by', v_d.resolved_by, 'was_resolved_at', v_d.resolved_at,
                            'reopened_by', v_staff, 'open_diffs_left', v_open);
end;
$$;


-- ═══ 8) inv_layer_post_charge — 20260929025719:183 바이트 그대로 + 문 2줄(판정 94 ⑯) · :over: 제외 2줄(판정 95 ㉓) · 주석 ═══
create or replace function public.inv_layer_post_charge(p_charge_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_charge@2026-09-29.3';   -- inv-basis-3: 입고 확정자의 문(판정 94 ⑯) · 트랜스퍼 :over: 레이어 제외(판정 95 ㉓)   -- tr-4: 트랜스퍼 배분 갈래(판정 67 · 77 · 묶음 일곱) · tr-4b: 얹은 뒤 자식 레이어로 따라가기(판정 79) · 도착 창구의 문(판정 78)
  v_chg        public.po_charge%rowtype;
  v_cur        text;
  v_base_cur   text;
  v_factor     numeric;                -- 청구 통화 → CAD 계수. 기준통화면 1 · 아니면 po_charge.exchange_rate(CAD per 통화)
  v_alloc      record;
  v_lay        record;
  v_basis      numeric;
  v_n_layers   int;
  v_amount_cad numeric;
  v_share      numeric;
  v_given      numeric;
  v_i          int;
  v_touched    int := 0;
  v_posted     numeric := 0;
  v_no_basis   int := 0;  v_no_basis_amt numeric := 0;
  v_no_layers  int := 0;  v_no_layers_amt numeric := 0;
  v_already    int := 0;  v_already_amt numeric := 0;
  v_allocs     jsonb := '[]'::jsonb;
  v_lines      jsonb;
  v_warn       text[] := '{}';
  v_po_number  text;                   -- 발주 번호 · 트랜스퍼 배분이면 트랜스퍼 번호(cost_add.ref_number)
  v_ref        jsonb;
  v_carried    int := 0;               -- tr-4b: 얹은 레이어의 IMS 자식(운송 중 · 도착 창고)으로 따라간 행 수(inv_layer_carry)                  -- tr-4: 배분 줄 반환에 더하는 키(트랜스퍼면 transfer_id · transfer_number · 발주면 빈 객체 — 발주 반환 모양 무변)
begin
  -- 문 — 구매 열쇠(발주 비용 · 지금까지와 같다) · tr-4: transfer 열쇠는 발주 배분이 하나도 없는 비용만(트랜스퍼 운임 · 묶음 일곱 3)
  if not public.ims_can_write('purchasing') then
    if not ((public.ims_can_write('transfer') or public.ims_can_write('wms_receiving')) and not exists (select 1 from public.po_charge_alloc a where a.po_charge_id = p_charge_id and a.po_id is not null))   -- tr-4b(판정 78): 도착 창구(wms_receiving)가 도착 순간 트랜스퍼 운임을 얹는다
       and not ((public.ims_can_write('receiving') or public.ims_can_write('wms_receiving_confirm'))
                and not exists (select 1 from public.po_charge_alloc a where a.po_charge_id = p_charge_id and a.po_id is not null and not exists (select 1 from public.po_receipt r where r.po_id = a.po_id and r.status = 'confirmed'))) then   -- inv-basis-3(판정 94 ⑯): 입고 확정자(receiving · wms_receiving_confirm)는 확정 입고가 있는 발주에만 배분된 비용을 얹는다(po_receipt_confirm_by 가 입고 순간 부른다)
      perform public.ims_require_write('purchasing', 'posted');
    end if;
  end if;

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — no cost was added', p_charge_id; end if;
  if v_chg.status <> 'confirmed' or v_chg.confirmed_at is null then
    raise exception 'Charge % is % — cost is added for confirmed charges only — no cost was added', v_chg.charge_number, v_chg.status;
  end if;

  -- 통화 · 환율 (confirm 이 먼저 막지만 직접 호출·백필 경로도 여기서 막는다)
  select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
  select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
  if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which charges need an exchange rate — no cost was added'; end if;
  if v_cur is distinct from v_base_cur then
    if v_chg.exchange_rate is null or v_chg.exchange_rate <= 0 then
      raise exception 'Charge % is in % but has no % per % exchange rate — the cost cannot be put on stock without it. Enter the rate on the charge and confirm again — no cost was added',
        v_chg.charge_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
    end if;
    -- ⚠️⚠️⚠️ po_charge.exchange_rate 는 CAD per USD 다 — amount(USD) × exchange_rate = CAD. 곱한다. 나누면 반값인데 에러가 안 난다.
    v_factor := v_chg.exchange_rate;
  else
    v_factor := 1;                                                                                          -- 기준통화(CAD) — 곱하지 않는다
    if v_chg.exchange_rate is not null and v_chg.exchange_rate <> 1 then v_warn := array_append(v_warn, 'exchange_rate_ignored_base_currency'); end if;
  end if;
  if v_chg.total_amount < 0 then v_warn := array_append(v_warn, 'negative_amount'); end if;

  if not exists (select 1 from public.po_charge_alloc a where a.po_charge_id = p_charge_id) then
    raise exception 'Charge % has no allocation lines — nothing to put on cost — no cost was added', v_chg.charge_number;
  end if;

  -- 배분 줄마다(발주 또는 트랜스퍼 — 정확히 하나 · tr-4)
  for v_alloc in
    select a.id, a.po_id, a.amount, p.po_number, a.transfer_id, t.transfer_number
    from public.po_charge_alloc a left join public.po p on p.id = a.po_id left join public.inv_transfer t on t.id = a.transfer_id
    where a.po_charge_id = p_charge_id
    order by p.po_number, t.transfer_number
  loop
    v_po_number  := coalesce(v_alloc.po_number, v_alloc.transfer_number);
    if v_alloc.transfer_id is not null and v_alloc.transfer_number is null then                                    -- tr-4: 이 로그인이 못 보는 트랜스퍼(RLS) — 조용히 0 을 얹지 않는다 · transfer 열쇠(또는 그 창고 열쇠)로
      raise exception 'Charge % is allocated to a transfer this login cannot see — the transfer key (or a warehouse key for that transfer) is needed — no cost was added', v_chg.charge_number;
    end if;
    v_ref        := case when v_alloc.transfer_id is not null then jsonb_build_object('transfer_id', v_alloc.transfer_id, 'transfer_number', v_alloc.transfer_number) else '{}'::jsonb end;
    -- ⚠️⚠️⚠️ CAD per USD × 청구 통화 금액 = CAD. 곱한다.
    v_amount_cad := v_alloc.amount * v_factor;

    -- 멱등 — 이 비용·이 배분 줄로 이미 얹은 행이 있으면 건너뛴다(이견 4)
    if exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number and ca.line_ref = v_alloc.id::text) then
      v_already := v_already + 1; v_already_amt := v_already_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'already_posted', 'layers', 0, 'posted_cad', 0) || v_ref);
      continue;
    end if;

    -- 그 발주의 IMS 입고 레이어 — po_line 을 거쳐(이견 1) · 불러온 레이어는 cost_source 로 갈린다(이견 2)
    -- tr-4 트랜스퍼: 그 문서의 도착 레이어(origin transfer · doc_number TRF-n · 도착 창고 — leg 4 · sent_more over_4) · return(:settle: · 출발 창고) 제외 · found 는 조정 문서 레이어라 안 걸린다 · lost 는 레이어가 없다(판정 77 — 도착한 물건이 전부 떠안는다)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0)
      into v_n_layers, v_basis
    from public.inv_layer x
    left join public.po_line pl on pl.id::text = x.line_ref
    where (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_alloc.po_id)
       or (v_alloc.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_alloc.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%');   -- inv-basis-3(판정 95 ㉓): 더 온 몫(sent_more · :over:) 레이어에는 운임 없음 — 도착한 물건에만

    if v_n_layers = 0 then
      v_no_layers := v_no_layers + 1; v_no_layers_amt := v_no_layers_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'no_layers', 'layers', 0, 'posted_cad', 0) || v_ref);
      continue;
    end if;
    if v_basis = 0 then
      -- 정본 D — 기준이 0 이면 버린다 · 수량 비례로 대신하지 않는다(Cin7 CostDistributionType='Cost' 와 방식이 갈린다)
      v_no_basis := v_no_basis + 1; v_no_basis_amt := v_no_basis_amt + v_amount_cad;
      v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'no_basis', 'layers', v_n_layers, 'posted_cad', 0) || v_ref);
      continue;
    end if;

    -- 금액 비율(unit_cost × qty · 정본 B) · 6자리 · 끝수는 마지막 레이어
    v_given := 0; v_i := 0; v_lines := '[]'::jsonb;
    for v_lay in
      select x.id, x.sku, x.warehouse, x.line_ref, x.qty, x.unit_cost, x.unit_cost * x.qty as basis
      from public.inv_layer x
      left join public.po_line pl on pl.id::text = x.line_ref
      where (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_alloc.po_id)
         or (v_alloc.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_alloc.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')   -- inv-basis-3(판정 95 ㉓)
      order by x.sku, x.line_ref, x.id
    loop
      v_i := v_i + 1;
      if v_i = v_n_layers then
        v_share := v_amount_cad - v_given;                                                                -- 마지막 레이어에 잔액 — 합이 정확히 금액과 같다
      else
        v_share := round(v_amount_cad * v_lay.basis / v_basis, 6);
      end if;
      v_given := v_given + v_share;
      insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
      values (v_lay.id, 'landed', v_share, v_chg.charge_date, v_chg.charge_number, v_alloc.id::text, v_po_number);
      v_touched := v_touched + 1;
      v_carried := v_carried + public.inv_layer_carry(v_lay.id);                                            -- tr-4b: 이미 떠난 몫(IMS 자식)에도 한 병당 비율로(판정 79 · 재생성과 같은 규칙)
      v_lines := v_lines || jsonb_build_object('layer_id', v_lay.id, 'sku', v_lay.sku, 'warehouse', v_lay.warehouse, 'po_line_id', v_lay.line_ref,
                                               'qty', v_lay.qty, 'unit_cost', v_lay.unit_cost, 'basis', v_lay.basis, 'share_cad', v_share);
    end loop;
    v_posted := v_posted + v_given;
    v_allocs := v_allocs || (jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_alloc.po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                               'status', 'posted', 'layers', v_n_layers, 'basis', v_basis, 'posted_cad', v_given, 'lines', v_lines) || v_ref);
  end loop;

  return jsonb_build_object(
    'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'charge_kind', v_chg.kind, 'cost_add_kind', 'landed', 'charge_date', v_chg.charge_date,
    'currency', v_cur, 'base_currency', v_base_cur,
    'fx_rate', case when v_cur is distinct from v_base_cur then v_chg.exchange_rate else null end,
    'fx_direction', case when v_cur is distinct from v_base_cur then v_base_cur || ' per ' || coalesce(v_cur, '?') || ' — amount × rate'
                         else v_base_cur || ' — base currency, no conversion (× 1)' end,
    'amount_total', v_chg.total_amount, 'amount_total_cad', v_chg.total_amount * v_factor,
    'layers_touched', v_touched, 'amount_posted_cad', v_posted,
    'no_basis_allocs', v_no_basis, 'no_basis_amount_cad', v_no_basis_amt,
    'no_layers_allocs', v_no_layers, 'no_layers_amount_cad', v_no_layers_amt,
    'already_posted_allocs', v_already, 'already_posted_amount_cad', v_already_amt,
    'allocs', v_allocs, 'builder', c_version, 'warnings', to_jsonb(v_warn))
    || case when v_carried > 0 then jsonb_build_object('carried_rows', v_carried) else '{}'::jsonb end;   -- tr-4b: 따라간 행이 있을 때만 키(발주 반환 모양 무변)
exception
  when unique_violation then
    raise exception 'Charge % — a landed cost row with the same key already exists (%) — no cost was added', v_chg.charge_number, sqlerrm;
end;
$$;
comment on function public.inv_layer_post_charge(uuid) is 'IMS 비용(po_charge) → inv_layer_cost_add(landed): 배분 줄마다 — 발주면 그 발주의 입고 레이어 · 트랜스퍼면 그 문서의 도착 레이어(origin transfer · TRF-n · 도착 창고 · :settle: 제외 · inv-basis-3 판정 95: :over: 더 온 몫 제외)에 unit_cost × qty 비례 · 6자리 · 끝수는 마지막 · 기준 0 버림 · 배분 줄 단위 멱등 · tr-4b: 얹은 레이어의 IMS 자식으로 carried 를 내려보낸다(판정 79) · 문: 구매 열쇠 · transfer 또는 wms_receiving 열쇠는 발주 배분 없는 비용만(판정 78 도착 창구 · 2026-09-29) · inv-basis-3 판정 94: receiving 또는 wms_receiving_confirm 열쇠는 확정 입고가 있는 발주에만 배분된 비용(입고 확정 순간 po_receipt_confirm_by 가 부른다)';


-- ═══ 9) inv_layer_apply — 20260929025719:430 바이트 그대로 + :over: 제외 2줄(판정 95 ㉓ · 창구와 같은 식) · ⭐ revoke 다시(판정 31) ═══
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

  -- 날짜순 루프 — ⭐ 사건 9종 전부 (order by occurred_on, seq_hint, po_in 먼저, id · source 필터 없음 · ⭐ 2026-09-21: 같은 날 유입끼리는 po_in 을 맨 앞에 — seq_hint 는 유입·유출만 가른다. 근거는 이 파일 머리 주석)
  for r in
    select id, event_type
      from inv_ledger
      where event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal',
                           'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
        and (p_until is null or occurred_on <= p_until)
      order by occurred_on, seq_hint, case event_type when 'po_in' then 0 else 1 end, id
  loop
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
  -- tr-4(2026-09-29): 비용 문서의 배분 줄이 트랜스퍼를 가리키면 그 문서의 도착 레이어에 얹는다 — 같은 창구 · 같은 규칙(판정 67 · 77 · 묶음 일곱) · 아래 exists 둘에 트랜스퍼 갈래를 더했다.
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
revoke all on function public.inv_layer_apply(date) from public, anon, authenticated;   -- ⭐ 판정 31 — 재생성 계열은 사람이 psql(소유자)로만 · 재발행마다 같은 파일에 다시 적는다


-- ═══ 10) wms_health_check — 20260929014246:938 바이트 그대로 + CTE 하나 · 행 하나(151 off_invoice_undecided) · 판정 99: 161(off_invoice_rejected_on_shelf) 없음 — 거절이 없다 · 옛 off_po 의 150 · 160 그대로 ═══
create or replace function public.wms_health_check() returns table(sort integer, check_key text, category text, title text, hint text, fail_count bigint, sample jsonb)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  c_stale constant interval := interval '24 hours';   -- packed_not_finalized · long_hold
  c_claim constant interval := interval '8 hours';    -- stale_claim(근무 하루)
begin
  if not public.ims_can_view('wms_manage') then                        -- ⭐ 첫 줄 문
    raise exception 'You cannot view WMS health — this needs the wms_manage screen — ask an admin';
  end if;
  return query
  with
  line_split as (
    select d.doc_number as so_number, l.line_no, l.sku,
           l.qty_target_ea as need_ea,
           sum(pl.assigned_base) as assigned_ea
      from public.wms_order_doc d
      join public.wms_order_doc_line l on l.doc_id = d.doc_id
      join public.wms_pick_task_lines pl on coalesce(pl.order_line_id, pl.transfer_line_id) = l.line_id
      join public.wms_pick_tasks t on t.id = pl.pick_task_id and coalesce(t.order_id, t.transfer_id) = d.doc_id
     where d.status in ('picking', 'packed')
     group by d.doc_number, l.line_no, l.sku, l.qty_target_ea
    having sum(pl.assigned_base) is distinct from l.qty_target_ea
  ),
  short_nd as (
    select d.doc_number as so_number, t.batch_label, l.sku, pl.assigned_base, pl.picked_base
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
     where pl.status = 'short'
       and not exists (select 1 from public.wms_worker_mistakes m
                        where coalesce(m.order_id, m.transfer_id) = d.doc_id and m.sku = l.sku and m.reason in ('short_pick', 'resolved_pack_recovery') and m.voided_at is null)
       and not exists (select 1 from public.wms_reports r                 -- ⑤-5c3: 「Not enough stock」 신고(판정 20 · 24-b 로 갈린 쪽)도 모자람을 설명한다 · resolved 무관
                        where coalesce(r.order_id, r.transfer_id) = d.doc_id and r.sku = l.sku and r.kind = 'stock_short')
  ),
  pick_over as (
    select d.doc_number as so_number, t.batch_label, l.sku, pl.assigned_base, pl.picked_base
      from public.wms_pick_task_lines pl
      join public.wms_pick_tasks t on t.id = pl.pick_task_id
      join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
      join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
     where pl.picked_base > pl.assigned_base
  ),
  fin_pair as (
    select d.doc_number as so_number, d.status, (coalesce(f.order_id, f.transfer_id) is not null) as has_finalize_row, f.finalized_at
      from public.wms_order_doc d
      left join public.wms_order_finalize f on coalesce(f.order_id, f.transfer_id) = d.doc_id
     where (d.status = 'packed' and coalesce(f.order_id, f.transfer_id) is null)
        or (coalesce(f.order_id, f.transfer_id) is not null and d.status in ('draft', 'confirmed', 'at_wms', 'picking', 'cancelled'))
  ),
  orphan_task as (
    select d.doc_number as so_number, d.status, count(t.id) as pick_tasks, string_agg(t.batch_label, ', ' order by t.batch_label) as batches
      from public.wms_order_doc d
      join public.wms_pick_tasks t on coalesce(t.order_id, t.transfer_id) = d.doc_id
     where d.status in ('draft', 'confirmed', 'at_wms', 'cancelled')
     group by d.doc_id, d.doc_number, d.status
  ),
  orphan_pack as (
    select k.id as pack_task_id, k.batch_label, d.doc_number as so_number, k.status as pack_status, t.status as pick_status
      from public.wms_pack_tasks k
      join public.wms_order_doc d on d.doc_id = coalesce(k.order_id, k.transfer_id)
      left join public.wms_pick_tasks t on t.id = k.pick_task_id
     where t.id is null or t.status is distinct from 'completed'
  ),
  wave_state as (
    select w.id, w.label, w.status,
           count(t.id) as member_batches,
           count(t.id) filter (where t.status = 'completed') as completed_batches
      from public.wms_waves w
      left join public.wms_pick_tasks t on t.wave_id = w.id
     group by w.id, w.label, w.status
    having count(t.id) = 0
        or (w.status = 'completed' and count(t.id) <> count(t.id) filter (where t.status = 'completed'))
        or (w.status <> 'completed' and count(t.id) > 0 and count(t.id) = count(t.id) filter (where t.status = 'completed'))
  ),
  hold_leak as (
    select h.id as hold_id, h.task_kind, h.task_id, h.worker, h.held_at,
           coalesce(p.status, k.status, w.status) as task_status,
           (coalesce(p.held_by, k.held_by, w.held_by) is not null) as task_held,
           h.rn as open_rank
      from (select th.*, row_number() over (partition by th.task_kind, th.task_id order by th.held_at desc) as rn
              from public.wms_task_holds th
             where th.resumed_at is null and th.task_kind in ('pick', 'pack', 'wave')) h
      left join public.wms_pick_tasks p on h.task_kind = 'pick' and p.id = h.task_id
      left join public.wms_pack_tasks k on h.task_kind = 'pack' and k.id = h.task_id
      left join public.wms_waves      w on h.task_kind = 'wave' and w.id = h.task_id
     where h.rn > 1                                                     -- 같은 과제에 열린 보류가 둘 = 닫기가 유실된 지문
        or (coalesce(p.id, k.id, w.id) is not null                      -- 지워진 과제(되돌리기)는 의도 · 표시 안 함
            and not (coalesce(p.status, k.status, w.status) = 'pending' and coalesce(p.held_by, k.held_by, w.held_by) is not null))
    union all                                                            -- ⑤-6b 입고 가지(판정 37 「receipt 는 ⑤-6」): 열린 보류가 draft 아닌 입고 · 창고 Complete 된 입고 · 한 입고에 둘
    select h.id, 'receipt'::text, null::bigint, h.worker, h.held_at,
           r.status, exists (select 1 from public.wms_receipt_complete c where c.receipt_id = r.id and c.completed), h.rn
      from (select th.*, row_number() over (partition by th.receipt_id order by th.held_at desc) as rn
              from public.wms_task_holds th
             where th.resumed_at is null and th.receipt_id is not null) h
      join public.po_receipt r on r.id = h.receipt_id
     where h.rn > 1
        or r.status <> 'draft'
        or exists (select 1 from public.wms_receipt_complete c where c.receipt_id = r.id and c.completed)
  ),
  recv_nc as (                                                           -- ⑤-6b 창고 Complete 뒤 24h 넘게 오피스 확정이 없다(여전히 draft) · tr-3a: 트랜스퍼 입고(po_id null)는 Complete = 확정이라 여기 안 든다(join po 가 거른다 · 판정 70)
    select r.receipt_number, p.po_number, c.completed_at, c.completed_by
      from public.wms_receipt_complete c
      join public.po_receipt r on r.id = c.receipt_id
      join public.po p on p.id = r.po_id
     where c.completed and r.status = 'draft' and c.completed_at < now() - c_stale
  ),
  recv_stale as (                                                        -- ⑤-6b 초안인데 작업 줄 0 · 만든 지 24h 넘음(열어 두고 아무것도 안 셈) · tr-3a: 트랜스퍼 입고도 든다(번호는 TRF)
    select r.receipt_number, coalesce(p.po_number, x.transfer_number) as po_number, r.created_at, r.created_by
      from public.po_receipt r
      left join public.po p on p.id = r.po_id
      left join public.inv_transfer x on x.id = r.transfer_id
     where r.status = 'draft' and r.created_at < now() - c_stale
       and not exists (select 1 from public.po_receipt_work w where w.receipt_id = r.id)
  ),
  offpo_und as (                                                         -- ⑤-6c1 off-PO 가 정해지지 않은 채 24h(판정 43 대가 — 선반에는 있고 장부에는 없다)
    select r.receipt_number, pr.sku, d.received_qty, (d.placed_at is not null) as on_shelf, b.name as bin, d.created_at
      from public.po_receipt_diff d
      join public.po_receipt r on r.id = d.receipt_id
      join public.product pr on pr.id = d.product_id
      left join public.ref_bin b on b.id = d.bin_id
     where d.kind = 'off_po' and d.resolved_at is null and d.created_at < now() - c_stale
  ),
  offpo_rej as (                                                         -- ⑤-6c1 거절됐는데 선반에서 뺐다는 확인이 없다 24h
    select r.receipt_number, pr.sku, d.received_qty, b.name as bin, d.resolved_at, d.resolved_by
      from public.po_receipt_diff d
      join public.po_receipt r on r.id = d.receipt_id
      join public.product pr on pr.id = d.product_id
      left join public.ref_bin b on b.id = d.bin_id
     where d.kind = 'off_po' and d.resolution = 'rejected' and d.bin_id is not null and d.removed_at is null and d.resolved_at < now() - c_stale
  ),
  offinv_und as (                                                        -- inv-basis-3 off-invoice(판정 88 ⑧)가 정해지지 않은 채 24h — 선반에는 있고 장부에는 없다
    select r.receipt_number, pr.sku, d.received_qty - d.expected_qty as extra_qty, (d.po_line_id is not null) as on_po_line, (d.placed_at is not null) as on_shelf, b.name as bin, d.created_at
      from public.po_receipt_diff d
      join public.po_receipt r on r.id = d.receipt_id
      join public.product pr on pr.id = d.product_id
      left join public.ref_bin b on b.id = d.bin_id
     where d.kind = 'off_invoice' and d.resolved_at is null and d.created_at < now() - c_stale
  ),
  picking_nt as (
    select d.doc_number as so_number, d.picking_at, d.picking_by
      from public.wms_order_doc d
     where d.status = 'picking' and not exists (select 1 from public.wms_pick_tasks t where coalesce(t.order_id, t.transfer_id) = d.doc_id)
  ),
  packed_nf as (
    select d.doc_number as so_number, v.pick_batches, v.packs_done, max(k.completed_at) as last_pack_at
      from public.wms_order_doc d
      join public.wms_order_pack_progress v on v.order_id = d.doc_id
      join public.wms_pack_tasks k on coalesce(k.order_id, k.transfer_id) = d.doc_id and k.status = 'completed'
     where d.status = 'picking' and v.all_packed
     group by d.doc_id, d.doc_number, v.pick_batches, v.packs_done
    having max(k.completed_at) < now() - c_stale
  ),
  stale_claim as (
    select 'pick' as kind, t.id as task_id, t.batch_label as label, t.assigned_to,
           greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) as last_activity
      from public.wms_pick_tasks t
      left join public.wms_pick_task_lines l on l.pick_task_id = t.id
     where t.status = 'in_progress' and t.wave_id is null
     group by t.id
    having greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) < now() - c_claim
    union all
    select 'pack', t.id, t.batch_label, t.assigned_to,
           greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at)
      from public.wms_pack_tasks t
      left join public.wms_pack_task_lines l on l.pack_task_id = t.id
     where t.status = 'in_progress'
     group by t.id
    having greatest(coalesce(max(l.verified_at), 'epoch'::timestamptz), coalesce(t.started_at, 'epoch'::timestamptz), coalesce(t.heartbeat_at, 'epoch'::timestamptz), t.created_at) < now() - c_claim
    union all
    select 'wave', w.id, w.label, w.assigned_to,
           greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(w.started_at, 'epoch'::timestamptz), coalesce(w.heartbeat_at, 'epoch'::timestamptz), w.created_at)
      from public.wms_waves w
      left join public.wms_pick_tasks t on t.wave_id = w.id
      left join public.wms_pick_task_lines l on l.pick_task_id = t.id
     where w.status = 'in_progress'
     group by w.id
    having greatest(coalesce(max(l.picked_at), 'epoch'::timestamptz), coalesce(w.started_at, 'epoch'::timestamptz), coalesce(w.heartbeat_at, 'epoch'::timestamptz), w.created_at) < now() - c_claim
  ),
  long_hold as (
    select h.id as hold_id, h.task_kind, h.task_id, h.worker, h.held_at, h.source
      from public.wms_task_holds h
     where h.resumed_at is null and h.task_kind in ('pick', 'pack', 'wave') and h.held_at < now() - c_stale
       and ((h.task_kind = 'pick' and exists (select 1 from public.wms_pick_tasks p where p.id = h.task_id))
         or (h.task_kind = 'pack' and exists (select 1 from public.wms_pack_tasks k where k.id = h.task_id))
         or (h.task_kind = 'wave' and exists (select 1 from public.wms_waves w where w.id = h.task_id)))
  ),
  adj_nl as (                                                            -- adj-a 2026-09-28 확정된 조정인데 원장 행이 없다(delta 0 줄뿐인 문서는 제외)
    select a.adjust_number, a.confirmed_at, a.warehouse
      from public.inv_adjust a
     where a.status = 'confirmed'
       and exists (select 1 from public.inv_adjust_line l where l.adjust_id = a.id and l.delta <> 0)
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'adjustment' and e.doc_number = a.adjust_number and e.source = 'ims')
  ),
  mv_nl as (                                                             -- trf-a 2026-09-28 확정된 칸 옮기기인데 원장 행이 없다
    select m.move_number, m.confirmed_at, m.warehouse
      from public.inv_move m
     where m.status = 'confirmed'
       and exists (select 1 from public.inv_move_line l where l.move_id = m.id)
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = m.move_number and e.source = 'ims')
  ),
  trf_nl as (                                                            -- tr-2 2026-09-28 떠난 트랜스퍼(in_transit 부터)인데 출발 원장 짝(출발 창고 transfer_out · IN_TRANSIT transfer_in)이 없다 — 창고 마무리 트랜잭션이 끊겼다
    select x.transfer_number, x.status, x.departed_at, fw.name as from_warehouse,
           (select count(*) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_out' and e.warehouse = fw.name) as out_rows,
           (select count(*) from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT') as transit_rows
      from public.inv_transfer x join public.ref_warehouse fw on fw.id = x.from_warehouse_id
     where x.status in ('in_transit', 'receiving', 'received') and x.departed_at is not null
       and (not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_out' and e.warehouse = fw.name)
            or not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in' and e.warehouse = 'IN_TRANSIT'))
  ),
  trf_rnl as (                                                           -- tr-3a 받은 트랜스퍼(received)인데 도착 원장(도착 창고 transfer_in · 그 입고)이 없다 — Complete 트랜잭션이 끊겼다
    select x.transfer_number, r.receipt_number, x.received_at, tw.name as to_warehouse
      from public.inv_transfer x join public.ref_warehouse tw on tw.id = x.to_warehouse_id
      join public.po_receipt r on r.transfer_id = x.id and r.status = 'confirmed'
     where x.status = 'received'
       and not exists (select 1 from public.inv_ledger e where e.doc_type = 'transfer' and e.doc_number = x.transfer_number and e.source = 'ims' and e.event_type = 'transfer_in'
                         and e.warehouse = tw.name and e.raw -> 'header' ->> 'receipt_number' = r.receipt_number)
  ),
  trf_old as (                                                           -- tr-3a 묶음 10 의 8: 떠난 지 30일이 넘었는데 운송 중에 남은 몫(IN_TRANSIT 잔고 > 0 · 다 못 받았거나 아직 안 받았다) — 매니저 정리(분실 / 되돌리기)
    select x.transfer_number, x.status, x.departed_at, s.remaining_ea
      from public.inv_transfer x
      join (select e.doc_number, sum(e.qty_delta) as remaining_ea from public.inv_ledger e where e.doc_type = 'transfer' and e.source = 'ims' and e.warehouse = 'IN_TRANSIT' group by e.doc_number) s on s.doc_number = x.transfer_number
     where x.departed_at < now() - interval '30 days' and s.remaining_ea > 0
  ),
  trf_over as (                                                          -- tr-3b 판정 76: 더 온 몫이 결정을 기다린다(over 차이 행 · 트랜스퍼 · 미결)
    select x.transfer_number, r.receipt_number, pr.sku, d.received_qty - d.expected_qty as over_ea, d.created_at
      from public.po_receipt_diff d join public.inv_transfer x on x.id = d.transfer_id join public.po_receipt r on r.id = d.receipt_id join public.product pr on pr.id = d.product_id
     where d.kind = 'over' and d.transfer_id is not null and d.resolved_at is null
  ),
  plan_short as (                                                        -- trf-a 열린 과제(pending · in_progress)의 계획 칸 합이 그 칸 장부보다 크다 — 피커가 빈 칸으로 간다(원인 무관 · 칸 옮기기 뒤 · 조정 뒤 · 낡은 계획)
    select s0.warehouse, s0.bin, s0.sku, s0.planned_ea, s0.ledger_ea, s0.batches
      from (select d.warehouse_name as warehouse, b.bin, coalesce(pp.sku, pr.sku) as sku, sum(b.qty_base) as planned_ea,
                   coalesce(max(v.qty), 0) as ledger_ea, string_agg(distinct t.batch_label, ', ') as batches
              from public.wms_pick_line_bins b
              join public.wms_pick_task_lines pl on pl.id = b.pick_task_line_id
              join public.wms_pick_tasks t on t.id = pl.pick_task_id
              join public.wms_order_doc d on d.doc_id = coalesce(t.order_id, t.transfer_id)
              join public.wms_order_doc_line l on l.line_id = coalesce(pl.order_line_id, pl.transfer_line_id)
              join public.product pr on pr.id = l.product_id
              left join public.product pp on pp.id = pr.parent_product_id
              left join public.inv_balance v on v.sku = coalesce(pp.sku, pr.sku) and v.warehouse = d.warehouse_name and v.bin = b.bin
             where b.planned and t.status in ('pending', 'in_progress')
             group by d.warehouse_name, b.bin, coalesce(pp.sku, pr.sku)) s0
     where s0.planned_ea > s0.ledger_ea
  ),
  bin_neg as (                                                           -- trf-a 칸 잔고가 음수 — 어디선가 실제와 다른 칸에서 뺐다(칸 없는 행 · 운송 중은 제외)
    select v.warehouse, v.bin, v.sku, v.qty
      from public.inv_balance v
     where v.qty < 0 and v.bin <> '' and v.warehouse in (select w.name from public.ref_warehouse w)
  ),
  last_rel as (
    select max(d.at_wms_at) as last_at,
           to_char(max(d.at_wms_at) at time zone 'America/Toronto', 'YYYY-MM-DD HH24:MI') as last_at_toronto,
           round(extract(epoch from (now() - max(d.at_wms_at))) / 60)::int as minutes_ago
      from public.wms_order_doc d
  )
  select 10, 'line_split_sum', 'critical', 'Line split sum',
    'For every line of an order in warehouse work (Working / Finalized) the batch assignments in base units must add up to (ordered - removed) x pack factor. A row here means a split lost or double-counted units. Lines that have no batch line at all are not listed here (see Working order without batches).',
    (select count(*) from line_split), (select jsonb_agg(t) from (select * from line_split limit 8) t)
  union all
  select 20, 'short_no_disc', 'warn', 'Short pick without a mistake row',
    'A pick line marked short with neither a short-pick mistake row nor a Not enough stock report for the same order and SKU (voided mistake rows do not count; a report explains the shortfall whether or not it is resolved) - the shortfall vanished silently. Match key: order + SKU; verify if unsure.',
    (select count(*) from short_nd), (select jsonb_agg(t) from (select * from short_nd limit 8) t)
  union all
  select 30, 'pick_over', 'warn', 'Picked exceeds assigned',
    'Picked base is greater than assigned at the pick level. Over-quantity should surface at pack (over-pick), not pick.',
    (select count(*) from pick_over), (select jsonb_agg(t) from (select * from pick_over limit 8) t)
  union all
  select 40, 'finalize_pair', 'critical', 'Finalized order without a finalize record (or the reverse)',
    'An order in Finalized (packed) must have exactly one finalize record, and a finalize record must not exist on an order that has not been finalized yet. A row means Finalize or Undo Finalize was interrupted - the office cannot fulfil it until the pair is repaired.',
    (select count(*) from fin_pair), (select jsonb_agg(t) from (select * from fin_pair limit 8) t)
  union all
  select 50, 'orphan_task', 'critical', 'Batches on an order that left warehouse work',
    'Pick batches exist for an order whose status is not Working or Finalized (the office recalled or cancelled it, or a rollback did not clean up). Pickers will see a red banner on these batches - undo the batches (Rollback tab).',
    (select count(*) from orphan_task), (select jsonb_agg(t) from (select * from orphan_task limit 8) t)
  union all
  select 60, 'orphan_pack', 'warn', 'Orphaned pack tasks',
    'A pack batch whose paired pick batch is missing or not completed. (An order can be Working overall while some of its batches pack - that is normal and not flagged.)',
    (select count(*) from orphan_pack), (select jsonb_agg(t) from (select * from orphan_pack limit 8) t)
  union all
  select 70, 'wave_state', 'warn', 'Wave consistency',
    'A wave with no member batches, a completed wave with unfinished batches, or a wave whose batches are all done but the wave never closed (an interrupted finish).',
    (select count(*) from wave_state), (select jsonb_agg(t) from (select * from wave_state limit 8) t)
  union all
  select 80, 'hold_leak', 'warn', 'Open hold vs batch state',
    'An open hold row (not resumed) whose batch is not pending-and-held, or two open rows on one batch - the resume close was lost, so its hold time will silently not be subtracted in Stats. Deleted batches (rollback) are intentionally not flagged. Receipt rows: an open hold on a receipt that is no longer a draft, or already completed in the warehouse, or two open holds on one receipt.',
    (select count(*) from hold_leak), (select jsonb_agg(t) from (select * from hold_leak limit 8) t)
  union all
  select 90, 'picking_no_tasks', 'critical', 'Working order without batches',
    'An order in Working (picking) with no pick batches at all. Split & Waves always creates the batches in the same transaction, and Undo Split returns the order to Released to WMS - a row here means an interrupted rollback. Roll it back or re-release it.',
    (select count(*) from picking_nt), (select jsonb_agg(t) from (select * from picking_nt limit 8) t)
  union all
  select 100, 'packed_not_finalized', 'warn', 'All batches packed but not finalized for 24h',
    'Every batch of the order is packed (it is on the Fulfillment board) but nobody finalized it for more than 24 hours after the last pack. The goods are sitting on the floor - finish the pallets and press Finalize.',
    (select count(*) from packed_nf), (select jsonb_agg(t) from (select * from packed_nf limit 8) t)
  union all
  select 110, 'stale_claim', 'warn', 'Batch claimed but silent for 8h',
    'A pick/pack batch or wave still in progress with no scan, start or heartbeat for more than 8 hours (last activity = latest of line scan time, started_at, heartbeat_at, created_at - the same rule as auto-hold). Auto-hold should have returned it to the pool after 10 minutes - a row here usually means the auto-hold job is not running. Release it from the Status tab.',
    (select count(*) from stale_claim), (select jsonb_agg(t) from (select * from stale_claim limit 8) t)
  union all
  select 120, 'long_hold', 'warn', 'Batch on hold for more than 24h',
    'A pick/pack batch or wave has been on hold (not resumed) for more than 24 hours. Someone started it and nobody finished it - resume it or roll the order back.',
    (select count(*) from long_hold), (select jsonb_agg(t) from (select * from long_hold limit 8) t)
  union all
  select 130, 'receipt_completed_not_confirmed', 'warn', 'Receipt completed in the warehouse but not confirmed for 24h',
    'The warehouse pressed Complete more than 24 hours ago and the office has not confirmed the receipt (it is still a draft) - the goods are in their bins but not in the books. Confirm it in Purchase Receipts, or reopen it if the count was wrong.',
    (select count(*) from recv_nc), (select jsonb_agg(t) from (select * from recv_nc limit 8) t)
  union all
  select 140, 'stale_receipt_draft', 'warn', 'Receipt draft with nothing counted for 24h',
    'A receipt was started more than 24 hours ago and nothing has been counted on it. Usually someone pressed Start and walked away - delete the empty draft (Receiving tab) or count the goods.',
    (select count(*) from recv_stale), (select jsonb_agg(t) from (select * from recv_stale limit 8) t)
  union all
  select 150, 'off_po_undecided', 'warn', 'Off-PO item waiting for a decision for 24h',
    'An item scanned at the dock that is not on the PO has been waiting more than 24 hours for the office to accept (free or billed) or reject it. Until then it sits on the shelf but not in the books - decide it in Purchase Receipts (the WMS Admin Receiving tab links there).',
    (select count(*) from offpo_und), (select jsonb_agg(t) from (select * from offpo_und limit 8) t)
  union all
  select 160, 'off_po_rejected_on_shelf', 'warn', 'Rejected off-PO item still on the shelf for 24h',
    'The office rejected an off-PO item more than 24 hours ago and nobody confirmed taking it off the shelf. Pickers may find stock that is not in the books - take it off and press Removed in the receiving screen.',
    (select count(*) from offpo_rej), (select jsonb_agg(t) from (select * from offpo_rej limit 8) t)
  union all
  select 151, 'off_invoice_undecided', 'warn', 'Off-invoice item waiting for a decision for 24h',
    'Goods received beyond the confirmed invoice (more than invoiced, an item the invoice does not have, or an item not on the PO) have been waiting more than 24 hours for the office to accept them (free or billed). Until then they sit on the shelf but not in the books - decide them in Purchase Receipts.',
    (select count(*) from offinv_und), (select jsonb_agg(t) from (select * from offinv_und limit 8) t)
  union all
  select 170, 'adjust_confirmed_no_ledger', 'critical', 'Confirmed stock adjustment without ledger rows',
    'A confirmed stock adjustment with a non-zero line has no ledger rows - the confirm transaction was interrupted between the document and the ledger. Stock is wrong until inv_post_adjust is run by the DB owner.',
    (select count(*) from adj_nl), (select jsonb_agg(t) from (select * from adj_nl limit 8) t)
  union all
  select 175, 'move_confirmed_no_ledger', 'critical', 'Confirmed bin move without ledger rows',
    'A confirmed bin move has no ledger rows - the confirm transaction was interrupted between the document and the ledger. Bin balances are wrong until inv_post_move is run by the DB owner.',
    (select count(*) from mv_nl), (select jsonb_agg(t) from (select * from mv_nl limit 8) t)
  union all
  select 178, 'transfer_departed_no_ledger', 'critical', 'Departed transfer without departure ledger rows',
    'A transfer that has left the warehouse (in transit or later) has no departure pair in the ledger (transfer_out at the from warehouse plus transfer_in at IN_TRANSIT) - the finalize transaction was interrupted between the document and the ledger. Stock at the from warehouse and in transit is wrong until inv_post_transfer_depart is run by the DB owner.',
    (select count(*) from trf_nl), (select jsonb_agg(t) from (select * from trf_nl limit 8) t)
  union all
  select 179, 'transfer_received_no_ledger', 'critical', 'Received transfer without arrival ledger rows',
    'A transfer marked received has a confirmed arrival receipt but no arrival rows in the ledger (transfer_in at the receiving warehouse for that receipt) - the Complete transaction was interrupted between the receipt and the ledger. Stock at the receiving warehouse and in transit is wrong until inv_post_transfer_arrive is run by the DB owner.',
    (select count(*) from trf_rnl), (select jsonb_agg(t) from (select * from trf_rnl limit 8) t)
  union all
  select 176, 'transfer_in_transit_30d', 'warn', 'Transfer stock still in transit after 30 days',
    'A transfer left the sending warehouse more than 30 days ago and part of it is still in transit (not received, or received short). Settle it: mark the missing units lost or return them to the sending warehouse (in-transit settlement).',
    (select count(*) from trf_old), (select jsonb_agg(t) from (select * from trf_old limit 8) t)
  union all
  select 177, 'transfer_over_undecided', 'warn', 'Transfer arrived with more than was sent - decision pending',
    'A transfer arrival counted more units than were sent; only the sent units arrived. Someone with the stock-adjust key must decide whether the sending warehouse sent more (move them across) or the receiving warehouse found them (stock adjustment).',
    (select count(*) from trf_over), (select jsonb_agg(t) from (select * from trf_over limit 8) t)
  union all
  select 180, 'planned_bin_short', 'warn', 'Pick plan points at a bin with less stock than planned',
    'Open pick tasks (waiting or in progress) plan more units from a bin than the ledger has there - the picker will find an empty or short bin. Usual causes: a bin move or an adjustment made after the batch was built, or a stale plan. Re-plan the batch or move the stock back.',
    (select count(*) from plan_short), (select jsonb_agg(t) from (select * from plan_short limit 8) t)
  union all
  select 185, 'bin_negative', 'warn', 'Bin balance below zero',
    'A bin reads a negative quantity in the ledger - units were deducted from a bin that did not have them (a pick recorded against the planned bin while the stock was elsewhere, or a move that was never recorded). Find the stock and fix it with a bin move or an adjustment.',
    (select count(*) from bin_neg), (select jsonb_agg(t) from (select * from bin_neg limit 8) t)
  union all
  select 200, 'last_release', 'info', 'Last release to WMS',
    'Newest Release to WMS from the office (Toronto time) - the signal that orders are still flowing into the warehouse. A long gap is normal when the office has nothing to release.',
    0::bigint, (select jsonb_build_object('last_at', last_at, 'last_at_toronto', last_at_toronto, 'minutes_ago', minutes_ago) from last_rel)
  order by 1;
end
$$;


-- ═══ 11) 지우기 둘 — wms_recv_delete(20260928014844:38 · 판정 97 ㉕) · po_receipt_delete(20260918163552:445 · 판정 97 ㉔) 바이트 그대로 + 거부 문장 ═══
create or replace function public.wms_recv_delete(p_receipt_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff uuid;  v_r public.po_receipt%rowtype;  v_pon text;  v_lines int;  v_n int;
  v_arch int := 0;  v_del_work int := 0;  v_del_diff int := 0;  v_del_holds int := 0;  v_del_complete int := 0;
begin
  perform public.ims_require_write('wms_manage', 'deleted');           -- ⭐ 첫 줄 — manager 이상(카탈로그 min_role)
  perform public.so_require_role('manager', 'deleted');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was deleted'; end if;
  select * into v_r from public.po_receipt r where r.id = p_receipt_id for update;
  if not found then raise exception 'Receipt not found — nothing was deleted'; end if;
  if not public.ims_can_warehouse(v_r.warehouse_id) then
    raise exception 'Receipt % is at another warehouse — you are not set up for it — nothing was deleted', v_r.receipt_number;
  end if;
  if v_r.status <> 'draft' or v_r.confirmed_at is not null then
    raise exception 'Receipt % is % — only a draft receipt can be deleted; a confirmed receipt has facts in the books — nothing was deleted', v_r.receipt_number, v_r.status;
  end if;
  select count(*) into v_lines from public.po_receipt_line l where l.receipt_id = p_receipt_id;
  if v_lines > 0 then
    raise exception 'Receipt % has % confirmed receipt line(s) — a receipt with facts in the books cannot be deleted — nothing was deleted', v_r.receipt_number, v_lines;
  end if;
  -- inv-basis-3 · 판정 97 ㉕: 받아들인 off-PO · off-invoice(장부에 든 것 — 결정 accepted_* 또는 그 차이의 원장 행)가 있으면 지우지 않는다
  select count(*) into v_n from public.po_receipt_diff d where d.receipt_id = p_receipt_id
     and (d.resolution like 'accepted%' or exists (select 1 from public.inv_ledger l where l.source = 'ims' and l.doc_type = 'purchase' and l.line_ref = d.id::text || ':offpo'));
  if v_n > 0 then
    raise exception 'Receipt % has % off-PO / off-invoice item(s) accepted into the books (stock and cost layers exist) — a receipt with facts in the books cannot be deleted; correct it with a stock adjustment instead — nothing was deleted', v_r.receipt_number, v_n;
  end if;
  select p.po_number into v_pon from public.po p where p.id = v_r.po_id;
  -- 아카이브(지우기 전 · 행 통째로) — 술어는 여기서 만든다(사람 입력 아님)
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'receipt_delete', null, v_r.receipt_number, v_pon, 'po_receipt',           format('id = %L', p_receipt_id));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'receipt_delete', null, v_r.receipt_number, v_pon, 'po_receipt_work',      format('receipt_id = %L', p_receipt_id));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'receipt_delete', null, v_r.receipt_number, v_pon, 'po_receipt_diff',      format('receipt_id = %L', p_receipt_id));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'receipt_delete', null, v_r.receipt_number, v_pon, 'wms_task_holds',       format('receipt_id = %L', p_receipt_id));
  v_arch := v_arch + public.wms_rb_archive(v_staff, 'receipt_delete', null, v_r.receipt_number, v_pon, 'wms_receipt_complete', format('receipt_id = %L', p_receipt_id));
  -- 지우기 — FK 순서(holds · complete 는 restrict · diff 는 no action · work 는 cascade · wms_reports.receipt_id 는 set null)
  delete from public.wms_task_holds where receipt_id = p_receipt_id;        get diagnostics v_del_holds = row_count;
  delete from public.wms_receipt_complete where receipt_id = p_receipt_id;  get diagnostics v_del_complete = row_count;
  delete from public.po_receipt_diff where receipt_id = p_receipt_id;       get diagnostics v_del_diff = row_count;
  select count(*) into v_del_work from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  delete from public.po_receipt where id = p_receipt_id;                    get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_r.receipt_number; end if;
  insert into public.wms_rollback_log (order_id, order_number, action, from_stage, to_stage, performed_by, batch_label)
  values (null, v_r.receipt_number, 'receipt_delete', 'draft', 'deleted', v_staff, v_pon);
  return jsonb_build_object('receipt_id', p_receipt_id, 'receipt_number', v_r.receipt_number, 'po_number', v_pon, 'deleted', true,
                            'archived', v_arch, 'deleted_rows', jsonb_build_object('work', v_del_work, 'diffs', v_del_diff, 'holds', v_del_holds, 'complete', v_del_complete),
                            'performed_by', v_staff);
end;
$$;
comment on function public.wms_recv_delete(uuid) is '⑤-6b 창고 쪽 입고 초안 삭제(운영 admin deleteReceipt 의 자리 · WMS Admin Receiving 탭 Delete) — 첫 줄 ims_require_write(wms_manage) · manager 이상 · ims_can_warehouse · draft 만(confirmed · cancelled 거부) · 확정 줄 있으면 거부 · 지우기 전에 po_receipt · po_receipt_work · po_receipt_diff · wms_task_holds · wms_receipt_complete 행을 wms_rollback_archive(action receipt_delete · order_number = RCV · batch_label = PO)에 통째로 · 그 뒤 삭제(FK 순서) · wms_rollback_log 한 줄(receipt_delete · draft → deleted) · 한 트랜잭션 · 오피스 문(receiving)은 안 부른다 · 창고 Complete 된 초안도 지운다(아카이브에 남는다) · 원장 무접촉(draft 라 사건이 없다) · inv-basis-3 판정 97 ㉕: 받아들인 off-PO · off-invoice(장부에 든 것)가 있으면 거부';
revoke all on function public.wms_recv_delete(uuid) from public, anon;
grant execute on function public.wms_recv_delete(uuid) to authenticated;

create or replace function public.po_receipt_delete(p_receipt_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_r     public.po_receipt%rowtype;
  v_pon   text;
  v_work  int;
  v_lines int;
  v_n     int;
begin
  perform public.ims_require_write('receiving', 'deleted');    -- §5 ②
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was deleted', p_receipt_id; end if;
  if v_r.confirmed_at is not null then                                            -- ⭐ 세 문서와 같은 문장 모양(20260917100000)
    raise exception 'Receipt % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
      v_r.receipt_number, to_char(v_r.confirmed_at, 'YYYY-MM-DD');
  end if;
  select count(*) into v_lines from public.po_receipt_line l where l.receipt_id = p_receipt_id;   -- FK no action 이 어차피 막는다 — 읽을 문장으로 먼저
  if v_lines > 0 then
    raise exception 'Receipt % has % confirmed receipt line(s) — a receipt with facts in the books cannot be deleted — nothing was deleted', v_r.receipt_number, v_lines;
  end if;
  -- inv-basis-3 · 판정 97 ㉔: 차이 행(창고가 스캔한 off-PO · off-invoice)이 있으면 날것 FK 오류 대신 문장 — 오피스 문은 그 행을 지우지 않는다(창고 문 wms_recv_delete 가 아카이브하고 지운다 · 장부에 든 것은 거기서도 거부)
  select count(*) into v_n from public.po_receipt_diff d where d.receipt_id = p_receipt_id;
  if v_n > 0 then
    raise exception 'Receipt % has % off-PO / off-invoice item(s) recorded by the warehouse — it cannot be deleted here; if none of them was accepted into the books, a manager deletes it from WMS Admin (Receiving > Delete), which keeps an archive of those items — nothing was deleted', v_r.receipt_number, v_n;
  end if;
  select po_number into v_pon from public.po p where p.id = v_r.po_id;
  select count(*) into v_work from public.po_receipt_work w where w.receipt_id = p_receipt_id;
  delete from public.po_receipt where id = p_receipt_id;                          -- 작업 줄은 cascade
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'Receipt % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', v_r.receipt_number; end if;
  return jsonb_build_object('deleted', true, 'id', v_r.id, 'receipt_number', v_r.receipt_number, 'po_number', v_pon, 'status_before', v_r.status, 'work_rows_deleted', v_work);
end;
$$;
comment on function public.po_receipt_delete(uuid) is '⑤ 입고 묶음 삭제(리시빙 2-a) — 판정 축은 confirmed_at(한 번이라도 확정된 것은 지우지 않는다 · 세 문서와 같은 문장 모양) · po_receipt_line 이 가리키면 이름으로 거부(FK no action 이 어차피 막는다) · 작업 줄은 cascade(work_rows_deleted). ⬜ 취소(cancelled)는 이 차수에 없다 — 확정 전 「그만둔다」는 삭제와 같은 뜻 · 확정 뒤 되돌림은 2-b/void 차수. 2026-09-18 · inv-basis-3 판정 97 ㉔: 차이 행이 있으면 문장으로 거부(창고 문으로 안내)';

-- ═══ 12) po_receipt_detail — 20260929190928:696 바이트 그대로 + 합계 셋(totals.over_lines · short_lines · warnings.over_receipt)만 lines[].expected 기준으로(판정 101 · inv-basis-6) · 키 · 모양 무변 ═══
create or replace function public.po_receipt_detail(p_receipt_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with r as (
  select * from public.po_receipt where id = p_receipt_id
),
w as (
  select k.*, b.name as bin, b.zone,
         (select s.name from public.ims_staff s where s.id = k.counted_by) as counted_by_name,     -- ⚠️ 별칭 — ims_staff 자기 칸과 헷갈리지 않게
         (select s.name from public.ims_staff s where s.id = k.putaway_by) as putaway_by_name,
         (select s.name from public.ims_staff s where s.id = k.updated_by) as updated_by_name
  from public.po_receipt_work k
  left join public.ref_bin b on b.id = k.bin_id
  where k.receipt_id = p_receipt_id
),
rl as (
  select l.*, b.name as bin, b.zone, pl.line_no,
         (select s.name from public.ims_staff s where s.id = l.received_by) as received_by_name
  from public.po_receipt_line l
  join public.po_line pl on pl.id = l.po_line_id
  left join public.ref_bin b on b.id = l.bin_id
  where l.receipt_id = p_receipt_id
),
lines as (
  select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pr.name as product_name, pl.supplier_sku, pl.qty_ea as ordered,
         pl.entered_unit_product_id, pl.entered_qty, pl.entered_pack_factor,
         coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                    where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0) as invoiced,
         coalesce((select sum(l.qty_ea) from public.po_receipt_line l where l.po_line_id = pl.id and (l.receipt_id is null or l.receipt_id <> p_receipt_id)), 0) as received_before,
         coalesce((select sum(y.qty_ea) from rl y where y.po_line_id = pl.id), 0) as received_here,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id), 0) as counted,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.bin_id is not null), 0) as allocated,
         coalesce((select sum(x.qty_ea) from w x where x.po_line_id = pl.id and x.putaway_done), 0) as placed
  from r
  join public.po_line pl on pl.po_id = r.po_id
  join public.product pr on pr.id = pl.product_id
),
fm as (                                                     -- 형제 문서 — 뿌리에서 내려온 전부 · 자기 자신 포함 · 분할이 없었으면 하나(차이 닫기 차수 2026-09-19)
  select * from public.po_family_members((select po_id from r))
),
fam as (                                                    -- 형제 합계 · 제품 단위 — ⭐ 계산은 DB 가 한다(화면이 형제를 찾아 더하지 않는다)
  select * from public.po_family_lines((select po_id from r))
)
select case when not exists (select 1 from r) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', r.id, 'receipt_number', r.receipt_number, 'status', r.status, 'received_on', r.received_on,
      'po_id', r.po_id, 'po_number', p.po_number, 'po_status', p.status, 'po_closed_at', p.closed_at,
      'po_split_from_number', sf.po_number,
      'po_split_to', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'po_number', c.po_number, 'status', c.status) order by c.po_number) from public.po c where c.split_from_id = p.id), '[]'::jsonb),
      'po_family', jsonb_build_object(                                                                      -- ⭐ 형제 문서 합계(문서 단위 · 2026-09-19) — 「12 중 12 · 다 받음」의 근거
        'root_number', (select m.po_number from fm m order by m.depth, m.po_number limit 1),
        'members', coalesce((select jsonb_agg(jsonb_build_object('id', m.po_id, 'po_number', m.po_number, 'status', m.status, 'closed_at', m.closed_at, 'is_this', m.is_self) order by m.po_number) from fm m), '[]'::jsonb),
        'ordered_total',  (select coalesce(sum(f.ordered_total), 0)  from fam f),
        'received_total', (select coalesce(sum(f.received_total), 0) from fam f),
        'still_owed',     (select coalesce(sum(f.still_owed), 0)     from fam f)),
      'supplier_id', p.supplier_id, 'supplier_name', s.name,
      'warehouse_id', r.warehouse_id, 'warehouse_name', wh.name,
      'created_by', r.created_by, 'created_by_name', cb.name,
      'confirmed_at', r.confirmed_at, 'confirmed_by_name', fb.name,
      'cancelled_at', r.cancelled_at, 'cancelled_by_name', xb.name,
      'note', r.note, 'created_at', r.created_at, 'updated_at', r.updated_at, 'updated_by_name', ub.name)
    from r
    join public.po p on p.id = r.po_id
    join public.supplier s on s.id = p.supplier_id
    join public.ref_warehouse wh on wh.id = r.warehouse_id
    left join public.po sf on sf.id = p.split_from_id
    left join public.ims_staff cb on cb.id = r.created_by
    left join public.ims_staff fb on fb.id = r.confirmed_by
    left join public.ims_staff xb on xb.id = r.cancelled_by
    left join public.ims_staff ub on ub.id = r.updated_by
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'po_line_id', l.po_line_id, 'line_no', l.line_no, 'product_id', l.product_id, 'sku', l.sku, 'product_name', l.product_name, 'supplier_sku', l.supplier_sku,
      'entered_unit_product_id', l.entered_unit_product_id, 'entered_qty', l.entered_qty, 'entered_pack_factor', l.entered_pack_factor,
      'ordered', l.ordered, 'invoiced', l.invoiced, 'received_before', l.received_before, 'received_here', l.received_here,
      'remaining', l.ordered - l.received_before,
      'expected', l.invoiced - l.received_before,                                                             -- inv-basis-2 · 판정 88 ②: 이 문서에서 받을 기준 = 확정 인보이스 − 앞선 입고(화면 ⑱-3 · ⑱-4 가 읽는다) · remaining 은 뜻 · 이름 그대로
      'counted', l.counted, 'allocated', l.allocated, 'unallocated', l.counted - l.allocated, 'placed', l.placed,
      'over', (l.counted > l.invoiced - l.received_before),                                                   -- inv-basis-2: over 도 같은 기준(화면은 diffs.kind 를 쓴다 · 이 키를 읽는 화면 0 · 2026-09-29 grep)
      'family', (select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members, 'fragments', f.fragments)
                 from fam f where f.product_id = l.product_id),                                              -- 형제 합계(제품 단위 · 2026-09-19) — 조각은 fragments[]
      'work', coalesce((
        select jsonb_agg(jsonb_build_object(
          'id', x.id, 'qty_ea', x.qty_ea, 'bin_id', x.bin_id, 'bin', x.bin, 'zone', x.zone, 'putaway_done', x.putaway_done,
          'count_method', x.count_method, 'counted_by', x.counted_by, 'counted_by_name', x.counted_by_name, 'counted_at', x.counted_at,
          'putaway_by', x.putaway_by, 'putaway_by_name', x.putaway_by_name, 'putaway_at', x.putaway_at,
          'note', x.note, 'updated_at', x.updated_at, 'updated_by_name', x.updated_by_name)
          order by x.bin_id nulls first, x.created_at)
        from w x where x.po_line_id = l.po_line_id), '[]'::jsonb))
      order by l.line_no)
    from lines l), '[]'::jsonb),
  'receipt_lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', y.id, 'po_line_id', y.po_line_id, 'line_no', y.line_no, 'qty_ea', y.qty_ea, 'bin_id', y.bin_id, 'bin', y.bin, 'zone', y.zone,
      'received_on', y.received_on, 'received_by', y.received_by, 'received_by_name', y.received_by_name, 'note', y.note, 'created_at', y.created_at)
      order by y.line_no, y.bin)
    from rl y), '[]'::jsonb),
  'diffs', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', d.id, 'kind', d.kind, 'po_line_id', d.po_line_id, 'line_no', pl.line_no, 'sku', pr.sku,
      'expected_qty', d.expected_qty, 'received_qty', d.received_qty, 'diff_qty', d.received_qty - d.expected_qty,
      'note', d.note, 'resolved_at', d.resolved_at, 'resolved_by', d.resolved_by, 'resolved_by_name', rb.name,      -- rb = 별칭 서브쿼리(ims_staff 자기 칸과 헷갈리지 않게)
      'resolution', d.resolution, 'resolution_note', d.resolution_note,                                              -- 닫은 이유(차이 닫기 차수 2026-09-19)
      'product_id', d.product_id, 'bin_id', d.bin_id, 'bin', db.name, 'placed_by', d.placed_by, 'placed_by_name', pb.name, 'placed_at', d.placed_at,   -- ⑤-6c1 off-PO 칸(off_po 아니면 null)
      'unit_price', d.unit_price, 'removed_by', d.removed_by, 'removed_by_name', rmb.name, 'removed_at', d.removed_at,
      'family', (select jsonb_build_object('ordered_total', f.ordered_total, 'received_total', f.received_total, 'still_owed', f.still_owed, 'members', f.members, 'fragments', f.fragments)
                 from fam f where f.product_id = d.product_id))                                              -- ⭐ 닫을 때 「결국 다 받았나」가 여기 있다
      order by pl.line_no)
    from public.po_receipt_diff d
    left join public.po_line pl on pl.id = d.po_line_id
    join public.product pr on pr.id = d.product_id
    left join public.ims_staff rb on rb.id = d.resolved_by
    left join public.ref_bin db on db.id = d.bin_id                                                          -- ⑤-6c1
    left join public.ims_staff pb on pb.id = d.placed_by
    left join public.ims_staff rmb on rmb.id = d.removed_by
    where d.receipt_id = p_receipt_id), '[]'::jsonb),
  'totals', (
    select jsonb_build_object(
      'lines', count(*), 'counted_lines', count(*) filter (where l.counted > 0),
      'ordered', coalesce(sum(l.ordered), 0), 'remaining', coalesce(sum(l.ordered - l.received_before), 0),
      'counted', coalesce(sum(l.counted), 0), 'allocated', coalesce(sum(l.allocated), 0), 'placed', coalesce(sum(l.placed), 0),
      'received_here', coalesce(sum(l.received_here), 0),
      'over_lines', count(*) filter (where l.counted > l.invoiced - l.received_before),                                       -- 판정 101(inv-basis-6): 기준 = lines[].expected
      'short_lines', count(*) filter (where l.counted < l.invoiced - l.received_before),                                      -- 판정 101
      'open_diffs', (select count(*) from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null))
    from lines l
  ),
  'warnings', (
    select coalesce(jsonb_agg(v), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select p.status from r join public.po p on p.id = r.po_id) <> 'confirmed' and (select status from r) = 'draft' then 'po_not_confirmed' end,
        case when exists (select 1 from lines l where l.counted > l.invoiced - l.received_before) then 'over_receipt' end,                -- 판정 101
        case when exists (select 1 from w x where x.bin_id is null) then 'unassigned_rows' end,
        case when not exists (select 1 from w) then 'nothing_counted' end,
        case when exists (select 1 from lines l where l.received_here <> l.counted) and (select status from r) = 'confirmed' then 'receipt_lines_differ_from_work' end,
        case when exists (select 1 from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null) then 'open_diffs' end
      ], null)) as v) t
  )
) end;
$$;
comment on function public.po_receipt_detail(uuid) is '⑤ 입고 상세 한 번(머리 · 줄 · 작업 줄 · 입고 줄 · 차이 · 합계 · 경고) · inv-basis-2: lines[].expected = 확정 인보이스 − 앞선 입고(판정 88 ②) · inv-basis-6 판정 101: totals.over_lines · short_lines · warnings.over_receipt 도 그 기준(remaining · totals.remaining 은 PO 수량 기준 그대로 · 이름 그대로) · 형제 합계는 po_family_* · security invoker';
