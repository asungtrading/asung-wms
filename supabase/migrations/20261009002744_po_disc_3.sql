-- ─────────────────────────────────────────────────────────────
-- 공급처 할인 → 재고 원가 ③ — 공통 원가 조정 장치: 사건 표 inv_cost_adjust · 창구 inv_layer_post_cost_adjust · 어휘(price_adjust · settlement_discount) · 입고 확정의 보류 얹기 · 재생성 갈래 · 되돌림 창구 (Asung-IMS · po-disc-3 · 2026-10-09)
--   정본(뒤에 적는다): so-module §53 판정 390 · 391 · 392 · 393 · 394(2026-10-08 · Caleb) · po-module §11-h 「재고에 남은 몫은 레이어 · 팔린 몫은 매출원가(늦은 비용 장치와 같은 모양 · 부호만 반대)」
--   판정 391  (다) 결제 할인은 결제 저장 순간 원가를 낮춘다 · 레이어가 없으면(pending) 입고 확정 때 저절로 — po_receipt_confirm_by ⓖ
--   판정 392  (나) 입고 뒤 바뀌는 단가는 공통 조정 장치로 — 이 차수는 장치만 · 부르는 쪽은 ④ po-disc-4(결제) · ⑤ po-disc-5(크레딧 · 환율 차액)
--   판정 393  비용 청구서에 받은 할인도 landed 를 낮춘다 — target charge_alloc(그 배분 줄이 landed 를 얹는 레이어 집합 · inv_layer_post_charge 와 같은 술어 두 벌)
--   판정 394  입고 뒤 환율 수정은 저절로 원가를 안 바꾼다 — 사건은 CAD 로 못 박아 들어온다(amount_cad · 부른 쪽이 핀 환율로 바꿔 넣는다) · 재생성은 posted_on · posted_ledger_id 자리에 같은 금액을 다시 얹는다
--   ⬜1 음수 가드 — 레이어마다 (단가 × 수량 + Σ얹기 + 이번 몫) < 0 이면 사건 전체 거부(「credit larger than the cost of the goods」) · 아무것도 안 얹는다
--   ⬜3 charge_alloc 대상 술어는 inv_layer_post_charge 의 것을 그대로 두 벌(함수로 빼지 않는다 — 재발행 크기 · 검증 A7 이 집합 같음을 증명)
--   ⬜4 열쇠 — 창구는 속 함수(authenticated 실행권 없음 · 안에서 purchasing | receiving | wms_receiving_confirm 을 묻는다) · 되돌림 창구는 purchasing · 입고 확정 길은 receiving(definer 안)
--   ⚠️ 이름 — inv_layer_post_adjust 는 재고 조정(adjust_new · adjust_existing) 레이어 창구가 이미 쓴다(20260928142722) · 이 창구는 inv_layer_post_cost_adjust
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 셋 — po_receipt_confirm_by(20260929195458:231~440 바이트 복사 + declare 3 · ⓖ 블록 · 반환 키 1) · inv_layer_apply_flush_adds(20260930161946:41~225 바이트 복사 + declare 2 · 갈래 1 · 반환 키 7) · inv_layer_apply(20260930161946:232~797 바이트 복사 + 자리 조회 넷 · 반환 키 1)
--   원칙 1: IMS 는 Cin7 없이 돈다 — 조정의 재료는 IMS 결제 · IMS 크레딧 · IMS 환율
-- ─────────────────────────────────────────────────────────────
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

-- ═══ ① inv_cost_adjust — 원가 조정 사건(한 행 = 「이 원가 대상에 이 금액(CAD · 부호 있음)을 얹어라」) · 비용의 po_charge_alloc 과 같은 자리 · 지우지 않는다(바로잡기는 되돌림 줄 · reverses_id) ═══
create table public.inv_cost_adjust (
  id                 uuid primary key default gen_random_uuid(),
  kind               text not null,                                                      -- price_adjust(나 · 입고 뒤 단가 차액) | settlement_discount(다 · 결제 할인)
  target_type        text not null,                                                      -- po_line | charge_alloc — 얹을 레이어를 고르는 길
  po_line_id         uuid references public.po_line (id) on delete no action,            -- target po_line: 그 PO 줄의 구매 레이어(origin purchase · cost_source po_line · line_ref = 줄 id · 입고 여럿이면 전부)
  po_charge_alloc_id uuid references public.po_charge_alloc (id) on delete no action,    -- target charge_alloc: 그 배분 줄이 landed 를 얹는 레이어 집합(판정 393)
  amount_cad         numeric not null,                                                   -- 부호 있음 · 할인 = 음수 · 0 아님
  amount_doc         numeric,                                                            -- 기록 — 문서 통화 금액(부른 쪽이 핀 환율로 CAD 로 바꿔 amount_cad 에 넣는다 · 판정 394)
  currency_id        uuid references public.ref_currency (id) on delete no action,
  exchange_rate      numeric,                                                            -- CAD per 통화 · 기준통화면 null
  source_type        text not null,                                                      -- 부른 문서 — po_payment_alloc(④) · po_credit(⑤) · fx_fix(⑤) · reversal(되돌림) · test(검증)
  source_id          uuid,
  source_number      text not null,                                                      -- 얹기 줄의 doc_number 가 된다(사람이 읽는 번호)
  reverses_id        uuid references public.inv_cost_adjust (id) on delete no action,    -- 되돌림 줄이 원래 사건을 가리킨다 · 한 번만(유니크)
  status             text not null default 'pending',                                    -- pending = 아직 안 얹혔다(대상 레이어 없음 · 판정 391) | posted
  posted_on          date,                                                               -- 실시간이 얹은 날(토론토) = 재생성 자리(비용과 같은 모양)
  posted_ledger_id   bigint,                                                             -- 얹힌 순간의 원장 최대 id(같은 날 안의 앞뒤)
  note               text,
  created_by         uuid references public.ims_staff (id) on delete no action,
  created_at         timestamptz not null default now(),
  updated_by         uuid references public.ims_staff (id) on delete no action,
  updated_at         timestamptz not null default now(),
  constraint inv_cost_adjust_kind_ck        check (kind in ('price_adjust', 'settlement_discount')),
  constraint inv_cost_adjust_target_ck      check (target_type in ('po_line', 'charge_alloc')),
  constraint inv_cost_adjust_target_pair_ck check (((target_type = 'po_line') = (po_line_id is not null)) and ((target_type = 'charge_alloc') = (po_charge_alloc_id is not null))),
  constraint inv_cost_adjust_amount_ck      check (amount_cad <> 0),
  constraint inv_cost_adjust_doc_pair_ck    check ((amount_doc is null) = (currency_id is null)),
  constraint inv_cost_adjust_status_ck      check (status in ('pending', 'posted')),
  constraint inv_cost_adjust_posted_pair_ck check ((status = 'posted') = (posted_on is not null)),
  constraint inv_cost_adjust_reverses_uq    unique (reverses_id)
);
create index inv_cost_adjust_po_line_idx   on public.inv_cost_adjust (po_line_id);
create index inv_cost_adjust_alloc_idx     on public.inv_cost_adjust (po_charge_alloc_id);
create index inv_cost_adjust_posted_on_idx on public.inv_cost_adjust (posted_on);
create trigger inv_cost_adjust_touch before update on public.inv_cost_adjust for each row execute function public.ims_touch();
alter table public.inv_cost_adjust enable row level security;
create policy inv_cost_adjust_select on public.inv_cost_adjust for select to authenticated using (true);
revoke all on public.inv_cost_adjust from public, anon;
revoke insert, update, delete, truncate, references, trigger on public.inv_cost_adjust from authenticated;   -- 기본 권한(pg_default_acl)이 전부 준다 — 읽기만 남긴다 · 쓰기는 창구(definer)만 · 지우지 않는다
grant select on public.inv_cost_adjust to authenticated;
comment on table public.inv_cost_adjust is 'po-disc-3 ⭐ 원가 조정 사건(판정 390 (나)·(다) · 391 · 393 · 394 · 2026-10-09) — 한 행 = 이 원가 대상(po_line 줄의 구매 레이어 | charge_alloc 배분 줄의 레이어 집합)에 amount_cad(부호 있음 · 할인 = 음수)를 얹어라 · 창구 inv_layer_post_cost_adjust 가 unit_cost×qty 비례로 inv_layer_cost_add(kind = 이 kind · line_ref adj:<id>) 를 넣고 줄마다 settle(남은 몫 = 레이어 · 팔린 몫 = cost_late · 옮겨 간 몫 = carried) · pending = 대상 레이어가 아직 없다(입고 확정 po_receipt_confirm_by ⓖ 가 저절로 얹는다 · 판정 391) · posted_on · posted_ledger_id = 실시간이 얹은 자리(재생성 inv_layer_apply_flush_adds 가 같은 자리에 같은 금액 · done kind cogs_adj) · 지우지 않는다 — 바로잡기는 되돌림 창구 inv_cost_adjust_reverse(반대 부호 · reverses_id · 한 번만) · 쓰기는 창구만(RLS select 만 · authenticated 는 읽기만) · 부르는 쪽: ④ po-disc-4 결제 할인 · ⑤ po-disc-5 크레딧 · 환율 차액';

-- ═══ ② 창구 inv_layer_post_cost_adjust(p_adjust_id · p_on) — 속 함수(authenticated 실행권 없음) · definer · 문 ═══
--   실시간(p_on null): status pending 만 · 얹은 뒤 posted · posted_on = ims_today · posted_ledger_id = 원장 최대 id · 재생성(p_on = posted_on): posted 사건만 · 이 사건의 얹기 줄이 없을 때만(멱등)
--   대상 레이어: po_line → origin purchase · cost_source po_line · line_ref = 줄 id · charge_alloc → inv_layer_post_charge 와 같은 술어(⬜3 · 두 벌)
--   비율 unit_cost × qty · 6자리 · 끝수는 마지막 줄 · 레이어 없음 → no_layers(pending 그대로 · 아무것도 안 얹는다) · 기준 0 → no_basis(같다)
--   ⬜1 음수 가드: 레이어마다 단가×수량 + Σ얹기 + 이번 몫 < 0 이면 사건 전체 거부
create function public.inv_layer_post_cost_adjust(p_adjust_id uuid, p_on date default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_cost_adjust@2026-10-09.1';
  v_j          public.inv_cost_adjust%rowtype;
  v_tr         record;                 -- charge_alloc 대상: 배분 줄의 po_id · transfer_id · transfer_number · po_number
  v_lay        record;
  v_n_layers   int;
  v_basis      numeric;
  v_share      numeric;
  v_given      numeric := 0;
  v_i          int := 0;
  v_aid        bigint;
  v_sub        jsonb;
  v_lines      jsonb := '[]'::jsonb;
  v_carried    int := 0;
  v_late_sold  numeric := 0;
  v_late_moved numeric := 0;
  v_ref        text;                   -- cost_add.ref_number — 발주 번호(트랜스퍼 배분이면 트랜스퍼 번호) · inv_layer_post_charge 와 같은 자리
  v_on         date := coalesce(p_on, public.ims_today());
  v_maxid      bigint;
begin
  -- 문(⬜4) — purchasing(결제 · 크레딧 · 되돌림 창구) · receiving | wms_receiving_confirm(입고 확정 길 · po_receipt_confirm_by ⓖ) · 재생성 로그인은 둘 다 가진다
  if not (public.ims_can_write('purchasing') or public.ims_can_write('receiving') or public.ims_can_write('wms_receiving_confirm')) then
    perform public.ims_require_write('purchasing', 'posted');
  end if;

  select * into v_j from public.inv_cost_adjust where id = p_adjust_id for update;
  if not found then raise exception 'Cost adjustment % not found — no cost was changed', p_adjust_id; end if;
  -- 멱등 — 실시간: 이미 posted 면 0 줄 · 재생성: posted 사건만 받고 이 사건의 얹기 줄이 이미 있으면 0 줄(같은 트랜잭션 재호출도 여기 걸린다)
  if p_on is null and v_j.status = 'posted' then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'already_posted', 'layers', 0, 'posted_cad', 0, 'posted_on', v_j.posted_on, 'builder', c_version);
  end if;
  if p_on is not null and v_j.status <> 'posted' then
    raise exception 'Cost adjustment % is still pending — regeneration replays posted adjustments only — no cost was changed', v_j.source_number;
  end if;
  if exists (select 1 from public.inv_layer_cost_add ca where ca.line_ref = 'adj:' || v_j.id::text) then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'already_posted', 'layers', 0, 'posted_cad', 0, 'posted_on', v_j.posted_on, 'builder', c_version);
  end if;

  -- 대상 — charge_alloc 이면 배분 줄의 발주 · 트랜스퍼(inv_layer_post_charge 가 읽는 것과 같은 것)
  if v_j.target_type = 'charge_alloc' then
    select a.po_id, a.transfer_id, t.transfer_number, p.po_number into v_tr
      from public.po_charge_alloc a left join public.inv_transfer t on t.id = a.transfer_id left join public.po p on p.id = a.po_id
     where a.id = v_j.po_charge_alloc_id;
    if not found then raise exception 'Cost adjustment %: allocation line % not found — no cost was changed', v_j.source_number, v_j.po_charge_alloc_id; end if;
    v_ref := coalesce(v_tr.po_number, v_tr.transfer_number);
  else
    select null::uuid as po_id, null::uuid as transfer_id, null::text as transfer_number, p.po_number into v_tr from public.po_line pl join public.po p on p.id = pl.po_id where pl.id = v_j.po_line_id;
    v_ref := v_tr.po_number;
  end if;

  -- 레이어 집합 · 기준 — po_line: 그 줄의 구매 레이어 · charge_alloc: ⬜3 inv_layer_post_charge 20260930144905 의 술어 그대로(발주 갈래 · 트랜스퍼 갈래 · :settle: · :over: 제외)
  select count(*), coalesce(sum(x.unit_cost * x.qty), 0) into v_n_layers, v_basis
    from public.inv_layer x
    left join public.po_line pl on pl.id::text = x.line_ref
   where (v_j.target_type = 'po_line' and x.origin_type = 'purchase' and x.cost_source = 'po_line' and x.line_ref = v_j.po_line_id::text)
      or (v_j.target_type = 'charge_alloc' and (
             (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_tr.po_id)
          or (v_tr.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_tr.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')));
  if v_n_layers = 0 then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'no_layers', 'layers', 0, 'basis', 0, 'posted_cad', 0, 'amount_cad', v_j.amount_cad, 'builder', c_version);
  end if;
  if v_basis = 0 then
    return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'no_basis', 'layers', v_n_layers, 'basis', 0, 'posted_cad', 0, 'amount_cad', v_j.amount_cad, 'builder', c_version);
  end if;

  -- 금액 비율(unit_cost × qty) · 6자리 · 끝수는 마지막 레이어 · ⬜1 음수 가드 · 줄마다 settle
  for v_lay in
    select x.id, x.sku, x.warehouse, x.doc_number, x.line_ref, x.qty, x.unit_cost, x.unit_cost * x.qty as basis,
           coalesce((select sum(ca.amount) from public.inv_layer_cost_add ca where ca.layer_id = x.id), 0) as adds
      from public.inv_layer x
      left join public.po_line pl on pl.id::text = x.line_ref
     where (v_j.target_type = 'po_line' and x.origin_type = 'purchase' and x.cost_source = 'po_line' and x.line_ref = v_j.po_line_id::text)
        or (v_j.target_type = 'charge_alloc' and (
               (x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_tr.po_id)
            or (v_tr.transfer_id is not null and x.origin_type = 'transfer' and x.doc_number = v_tr.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')))
     order by x.sku, x.line_ref, x.id
  loop
    v_i := v_i + 1;
    if v_i = v_n_layers then v_share := v_j.amount_cad - v_given;                        -- 마지막 레이어에 잔액 — 합이 정확히 사건 금액
    else v_share := round(v_j.amount_cad * v_lay.basis / v_basis, 6); end if;
    if v_lay.basis + v_lay.adds + v_share < 0 then                                        -- ⬜1: 물건의 원가보다 큰 크레딧 — 입력 오류일 가능성 · 사건 전체 거부(앞 레이어에 넣은 줄은 예외로 함께 되돌아간다)
      raise exception 'Cost adjustment % (% CAD) is a credit larger than the cost of the goods on layer % (% % · cost % + earlier adds % + this share %) — check the amount — no cost was changed',
        v_j.source_number, v_j.amount_cad, v_lay.id, v_lay.sku, v_lay.doc_number, v_lay.basis, v_lay.adds, v_share;
    end if;
    v_given := v_given + v_share;
    insert into public.inv_layer_cost_add (layer_id, kind, amount, occurred_on, doc_number, line_ref, ref_number)
    values (v_lay.id, v_j.kind, v_share, v_on, v_j.source_number, 'adj:' || v_j.id::text, v_ref)
    returning id into v_aid;
    v_sub := public.inv_layer_cost_add_settle(v_aid);                                     -- 남은 몫 · 옮겨 간 몫(자식 carried · ref_number layer:<부모>:<kind>) · 팔린 몫(cost_late · split_basis.kind = 이 kind)
    v_carried    := v_carried    + coalesce((v_sub ->> 'carried_rows')::int, 0);
    v_late_sold  := v_late_sold  + coalesce((v_sub ->> 'sold_amount')::numeric, 0);
    v_late_moved := v_late_moved + coalesce((v_sub ->> 'moved_amount')::numeric, 0);
    v_lines := v_lines || jsonb_build_object('layer_id', v_lay.id, 'sku', v_lay.sku, 'warehouse', v_lay.warehouse, 'doc_number', v_lay.doc_number, 'line_ref', v_lay.line_ref,
                                             'qty', v_lay.qty, 'unit_cost', v_lay.unit_cost, 'basis', v_lay.basis, 'share_cad', v_share, 'settle_rows', coalesce((v_sub ->> 'rows_written')::int, 0));
  end loop;

  if p_on is null then                                                                    -- 실시간: 자리를 남긴다(재생성이 같은 자리 · 같은 날 안의 앞뒤까지 재현 · 비용의 posted_on 과 같은 모양)
    select max(g.id) into v_maxid from public.inv_ledger g;
    update public.inv_cost_adjust set status = 'posted', posted_on = v_on, posted_ledger_id = v_maxid where id = v_j.id;
  end if;
  return jsonb_build_object('adjust_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'status', 'posted',
                            'layers', v_n_layers, 'basis', v_basis, 'amount_cad', v_j.amount_cad, 'posted_cad', v_given, 'posted_on', v_on, 'posted_ledger_id', v_maxid,
                            'late_sold_cad', v_late_sold, 'late_moved_cad', v_late_moved, 'carried_rows', v_carried, 'lines', v_lines, 'builder', c_version);
exception
  when unique_violation then
    raise exception 'Cost adjustment % — a cost row with the same key already exists (%) — no cost was changed', v_j.source_number, sqlerrm;
end;
$$;
revoke all on function public.inv_layer_post_cost_adjust(uuid, date) from public, anon, authenticated;   -- 속 함수 — 되돌림 창구 · 입고 확정 · 재생성(definer)이 부른다 · ④ ⑤ 의 창구도 definer 안에서
comment on function public.inv_layer_post_cost_adjust(uuid, date) is 'po-disc-3 ⭐ 원가 조정 사건 하나를 레이어에 얹는 속 함수(판정 391 · 393 · 394 · 2026-10-09) — 대상 레이어(po_line: 그 줄의 구매 레이어 · charge_alloc: inv_layer_post_charge 와 같은 술어)에 unit_cost×qty 비례(6자리 · 끝수 마지막) · inv_layer_cost_add(kind = 사건 kind · doc_number = source_number · line_ref adj:<id> · occurred_on = p_on 또는 ims_today) · 줄마다 inv_layer_cost_add_settle · 실시간(p_on null)은 pending 만 받아 posted + posted_on + posted_ledger_id · 재생성(p_on)은 posted 만 · 얹기 줄이 있으면 already_posted · 레이어 없음 no_layers(pending 그대로) · 기준 0 no_basis · ⬜1 레이어 단가×수량 + Σ얹기 + 몫 < 0 이면 전체 거부 · 문: purchasing | receiving | wms_receiving_confirm · authenticated 실행권 없음';

-- ═══ ③ 어휘 — inv_layer_cost_add.kind 에 price_adjust · settlement_discount ═══
--   §3 grep(마이그레이션 전수 + DB prosrc · 2026-10-09): kind = 'landed' 로 거르는 함수 — inv_transfer_detail · po_charge_confirm · tf_charge_confirm · tf_arrive · inv_layer_apply(inv_cost.cost_kind) · inv_layer_apply_flush_adds(멱등 검사) · po_receipt_confirm_by ⓕ(멱등 검사) · inv_layer_post_charge(멱등 검사)
--     — 전부 landed 만 고르므로 새 어휘는 섞이지 않는다 · 값 목록 ('landed', 'transfer_freight', 'carried') 는 이 CHECK 한 곳 · 뷰에서 kind 를 거르는 곳 0 · inv_layer_value · inv_layer_open 은 kind 와 무관하게 합친다(새 어휘 포함 — 맞다)
--   settle 은 kind 를 그대로 옮긴다(자식 carried 의 ref_number layer:<부모>:<kind> · cost_late split_basis.kind) — 본문 무변(검증 G0 md5)
alter table public.inv_layer_cost_add drop constraint inv_layer_cost_add_kind_ck;
alter table public.inv_layer_cost_add add constraint inv_layer_cost_add_kind_ck check (kind in ('landed', 'transfer_freight', 'carried', 'price_adjust', 'settlement_discount'));   -- po-disc-3: 원가 조정 사건의 두 어휘(음수 가능 · 부호 CHECK 는 원래 없다)

-- ═══ ④ po_receipt_confirm_by 재발행 — 마지막 정의 20260929195458:231~440(DB md5 1f0e0017 · 검증 G0) 바이트 복사 + declare 3 · ⓖ 블록 · 반환 키 하나(판정 391) ═══
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
  v_aj        jsonb;                                           -- po-disc-3 · 판정 391: 보류 원가 조정 얹기의 반환
  v_apost     jsonb := '[]'::jsonb;
  v_aerr      jsonb := '[]'::jsonb;
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

  -- ═══ ⓖ po-disc-3 · 판정 391: 레이어가 없어 보류됐던 원가 조정(이 PO 의 줄 · 이 PO 의 비용 배분 줄)을 지금 얹는다 — ⓕ 비용 뒤(둘 다 금액만 얹어 총액은 순서와 무관 · 재생성 쏟기도 비용 뒤) · 오류는 경고로(확정을 막지 않는다) ═══
  for x in select j.id, j.source_number from public.inv_cost_adjust j
            where j.status = 'pending'
              and ((j.target_type = 'po_line' and exists (select 1 from public.po_line pl where pl.id = j.po_line_id and pl.po_id = v_po.id))
                or (j.target_type = 'charge_alloc' and exists (select 1 from public.po_charge_alloc a where a.id = j.po_charge_alloc_id and a.po_id = v_po.id)))
            order by j.created_at, j.source_number, j.reverses_id nulls first, j.id loop                       -- 원래 사건 뒤에 그 되돌림(같은 트랜잭션은 created_at 이 같다)
    begin
      v_aj := public.inv_layer_post_cost_adjust(x.id);
      v_apost := v_apost || jsonb_build_object('adjust_id', x.id, 'source_number', x.source_number, 'status', v_aj ->> 'status', 'posted_cad', v_aj -> 'posted_cad', 'layers', v_aj -> 'layers');
    exception when others then
      v_aerr := v_aerr || jsonb_build_object('adjust_id', x.id, 'source_number', x.source_number, 'sqlstate', sqlstate, 'error', sqlerrm);
    end;
  end loop;
  if jsonb_array_length(v_aerr) > 0 then v_warn := array_append(v_warn, 'adjust_errors'); end if;

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', 'closed', 'closed_at', v_now),
    'split', null,                                               -- inv-basis-2: 입고 확정은 가르지 않는다(키는 모양 무변 · 값은 늘 null · 덜 받은 몫은 diffs.short)
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'charges', jsonb_build_object('posted', v_cpost, 'errors', v_cerr),   -- inv-basis-3 · 판정 94(⑯): 이 발주의 확정 비용을 입고 순간 얹은 결과
    'adjustments', jsonb_build_object('posted', v_apost, 'errors', v_aerr),   -- po-disc-3 · 판정 391: 보류 원가 조정을 입고 순간 얹은 결과
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑤-a inv_layer_apply_flush_adds 재발행 — 마지막 정의 20260930161946:41~225(DB md5 4099ee24 · 검증 G0) 바이트 복사 + declare 2 · IMS 원가 조정 갈래 · 반환 키 7 ═══
create or replace function public.inv_layer_apply_flush_adds(p_day date, p_until date, p_before_id bigint, p_acc jsonb) returns jsonb
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
  v_ids         bigint[];   v_id bigint;                                                  -- cogs-2: 새로 든 얹기 줄(on conflict do nothing 의 returning) → settle
  v_al          record;     v_chg_ids uuid[] := '{}';                                      -- cogs-2(판정 114): IMS 비용은 배분 줄 단위 · charges_posted 는 비용 문서 수(distinct)
  v_deferred    int := 0;                                                                 -- cogs-3(판정 119) 안전띠: 대상 레이어가 아직 없어 이번 경계에서 미룬 posted 배분 줄 수
  v_adj         record;                                                                  -- po-disc-3(판정 391 · 394): IMS 원가 조정 사건 — 비용 갈래와 같은 자리(posted_on · posted_ledger_id) · done kind cogs_adj
  v_adj_n int := 0;   v_adj_rows int := 0;   v_adj_amt numeric := 0;   v_adj_nolayers int := 0;   v_adj_skipped int := 0;   v_adj_deferred int := 0;   v_adj_skip jsonb := '[]'::jsonb;
begin
  -- ═══ PO landed → inv_layer_cost_add (2026-09-10 · 헤더) — cogs-1: 그날까지 · 아직 안 얹은 것 · 대상 레이어가 선 것만(집합 연산 한 번은 그대로) ═══
  with ins as (
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
    group by x.id, c.occurred_on, c.doc_number, c.line_ref
  on conflict on constraint inv_layer_cost_add_uq do nothing
  returning id)
  select coalesce(array_agg(ins.id order by ins.id), '{}') into v_ids from ins;
  v_landed_rows := coalesce(array_length(v_ids, 1), 0);
  foreach v_id in array v_ids loop perform inv_layer_cost_add_settle(v_id); end loop;                     -- cogs-2(판정 107): 새로 든 얹기 줄마다 셋으로(레이어가 이미 팔린 뒤 온 landed → cost_late · 자식 carried)

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
      with ins as (
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
                where x.origin_type = 'transfer' and x.doc_number = v_doc.doc_number and x.warehouse <> 'IN_TRANSIT') t
      on conflict on constraint inv_layer_cost_add_uq do nothing
      returning id)
      select coalesce(array_agg(ins.id order by ins.id), '{}') into v_ids from ins;
      v_rows := coalesce(array_length(v_ids, 1), 0);
      v_fr_rows := v_fr_rows + v_rows;
      foreach v_id in array v_ids loop perform inv_layer_cost_add_settle(v_id); end loop;                 -- cogs-2(판정 107): 도착 레이어가 이미 팔렸거나 다시 떠난 뒤 온 운임 → cost_late · cost_moved · 자식 carried
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
  -- p_until: cogs-2 — 얹기 줄 날짜 = posted_on(없으면 charge_date) — 그것이 p_until 안이면 고른다(as-of 재생성).
  -- 방문하지 않은 확정 비용(배분된 발주 어디에도 IMS 레이어가 없는 것 — 예: 환율이 없어 입고를 건너뛴 발주)은 따로 센다(charges_unvisited · 금액 CAD)
  --   — 「버린 금액」의 그림이 빠지지 않게. Cin7 대조에서 이 금액만큼은 설명된 차이다(정본 D 의 freight_no_basis_amount 와 같은 구실).
  -- ⭐ cogs-2(판정 114 · 115-1): 배분 줄 단위 · 자리 = 실시간이 남긴 posted_on(같은 날 안은 posted_ledger_id < p_before_id 인 것만 · 본체가 줄 id 로 부른다) · posted_on 없는 옛 배분 줄은 첫 차수 규칙(charge_date ≤ p_day · 그 배분 줄의 레이어가 선 뒤 · 얹기 줄 날짜 = charge_date)
  for v_al in
    select a.id as alloc_id, c.id as charge_id, c.charge_number, c.charge_date, a.posted_on, a.posted_ledger_id, a.po_id, a.transfer_id
      from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
      where c.status = 'confirmed' and c.confirmed_at is not null
        and (p_until is null or coalesce(a.posted_on, c.charge_date) <= p_until)
        and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')   -- 이미 부른 배분 줄
        and (
              (a.posted_on is not null                                                                                   -- ⓐ 실시간이 얹은 배분 줄: posted_on 자리 · 같은 날 안은 posted_ledger_id < p_before_id 인 것만
               and (p_day is null or a.posted_on < p_day or (a.posted_on = p_day and (p_before_id is null or coalesce(a.posted_ledger_id, -1) < p_before_id))))
           or (a.posted_on is null                                                                                       -- ⓑ 아직 안 얹힌 배분 줄(옛 것 · no_layers): 첫 차수 규칙 — charge_date ≤ p_day 이고 그 배분 줄의 레이어가 선 것 · 마지막 쏟기(p_day null)는 레이어가 없어도 넘겨 no_layers 로 센다
               and (p_day is null or c.charge_date <= p_day)
               and (p_day is null
                    or (a.po_id is not null and exists (select 1 from po_line pl join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = a.po_id))
                    or (a.transfer_id is not null and exists (select 1 from inv_transfer t join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%' where t.id = a.transfer_id))))   -- inv-basis-3(판정 95 ㉓): 창구와 같은 술어
            )
      order by coalesce(a.posted_on, c.charge_date), a.posted_ledger_id nulls first, c.charge_number, c.id, a.id
  loop
    if v_al.posted_on is not null and p_day is not null                                                                    -- cogs-3(판정 119) 안전띠: 실시간이 얹은 배분 줄인데 대상 레이어가 아직 없으면 done 을 쓰지 않고 다음 경계에서 다시 본다(마지막 쏟기 p_day null 은 창구에 넘겨 no_layers 로)
       and not ((v_al.po_id is not null and exists (select 1 from po_line pl join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = v_al.po_id))
             or (v_al.transfer_id is not null and exists (select 1 from inv_transfer t join inv_layer x on x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%' where t.id = v_al.transfer_id))) then
      v_deferred := v_deferred + 1;
      continue;
    end if;
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_chg', v_al.alloc_id::text, '', '');
    begin
      v_ims_j := inv_layer_post_charge(v_al.charge_id, coalesce(v_al.posted_on, v_al.charge_date), v_al.alloc_id);
      if not (v_al.charge_id = any (v_chg_ids)) then v_chg_ids := v_chg_ids || v_al.charge_id; v_ims_chg_n := v_ims_chg_n + 1; end if;
      v_ims_chg_rows         := v_ims_chg_rows         + coalesce((v_ims_j->>'layers_touched')::int, 0);
      v_ims_chg_amt          := v_ims_chg_amt          + coalesce((v_ims_j->>'amount_posted_cad')::numeric, 0);
      v_ims_chg_nobasis_amt  := v_ims_chg_nobasis_amt  + coalesce((v_ims_j->>'no_basis_amount_cad')::numeric, 0);    -- 기준 0 이라 버린 금액(정본 D)
      v_ims_chg_nolayers_amt := v_ims_chg_nolayers_amt + coalesce((v_ims_j->>'no_layers_amount_cad')::numeric, 0);   -- 배분 줄 중 레이어 없는 발주로 간 금액
      v_ims_chg_already      := v_ims_chg_already      + coalesce((v_ims_j->>'already_posted_allocs')::int, 0);      -- cost_add 를 지운 뒤라 0 이어야 한다(생기면 신호)
    exception when others then
      v_ims_chg_skipped := v_ims_chg_skipped + 1;
      v_chg_skip := v_chg_skip || jsonb_build_object('d', coalesce(v_al.posted_on, v_al.charge_date), 'e', jsonb_build_object('kind', 'charge', 'number', v_al.charge_number, 'id', v_al.charge_id, 'alloc_id', v_al.alloc_id, 'sqlstate', sqlstate, 'error', sqlerrm));
    end;
  end loop;

  -- ═══ IMS 원가 조정 → inv_layer_cost_add (po-disc-3 · 판정 391 · 394) — 비용 갈래와 같은 모양 · 자리 = posted_on · posted_ledger_id(같은 날 안은 < p_before_id) · done kind cogs_adj · pending(posted_on null)은 재생성이 얹지 않는다(입고 확정 사건이 그 자리 · 확정 순간 posted_on 이 적힌다) · 되돌림 줄도 자기 자리 ═══
  for v_adj in
    select j.id, j.source_number, j.posted_on, j.posted_ledger_id, j.target_type, j.po_line_id, j.po_charge_alloc_id
      from inv_cost_adjust j
      where j.status = 'posted' and j.posted_on is not null
        and (p_until is null or j.posted_on <= p_until)
        and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')
        and (p_day is null or j.posted_on < p_day or (j.posted_on = p_day and (p_before_id is null or coalesce(j.posted_ledger_id, -1) < p_before_id)))
      order by j.posted_on, j.posted_ledger_id nulls first, j.created_at, j.id
  loop
    if p_day is not null                                                                                                   -- cogs-3(판정 119) 안전띠와 같다: 대상 레이어가 아직 없으면 done 을 쓰지 않고 다음 경계로
       and not ((v_adj.target_type = 'po_line' and exists (select 1 from inv_layer x where x.origin_type = 'purchase' and x.cost_source = 'po_line' and x.line_ref = v_adj.po_line_id::text))
             or (v_adj.target_type = 'charge_alloc' and exists (select 1 from po_charge_alloc a left join inv_transfer t on t.id = a.transfer_id
                                                                 where a.id = v_adj.po_charge_alloc_id
                                                                   and ((a.po_id is not null and exists (select 1 from po_line pl join inv_layer x on x.line_ref = pl.id::text and x.origin_type = 'purchase' and x.cost_source = 'po_line' where pl.po_id = a.po_id))
                                                                     or (a.transfer_id is not null and exists (select 1 from inv_layer x where x.origin_type = 'transfer' and x.doc_number = t.transfer_number and x.warehouse <> 'IN_TRANSIT' and x.line_ref not like '%:settle:%' and x.line_ref not like '%:over:%')))))) then
      v_adj_deferred := v_adj_deferred + 1;
      continue;
    end if;
    insert into inv_layer_apply_done (kind, doc_number, sku, warehouse) values ('cogs_adj', v_adj.id::text, '', '');
    begin
      v_ims_j := inv_layer_post_cost_adjust(v_adj.id, v_adj.posted_on);
      v_adj_n := v_adj_n + 1;
      if v_ims_j ->> 'status' in ('no_layers', 'no_basis') then v_adj_nolayers := v_adj_nolayers + 1; end if;
      v_adj_rows := v_adj_rows + coalesce((v_ims_j ->> 'layers')::int, 0);
      v_adj_amt  := v_adj_amt  + coalesce((v_ims_j ->> 'posted_cad')::numeric, 0);
    exception when others then
      v_adj_skipped := v_adj_skipped + 1;
      v_adj_skip := v_adj_skip || jsonb_build_object('d', v_adj.posted_on, 'e', jsonb_build_object('kind', 'adjust', 'number', v_adj.source_number, 'id', v_adj.id, 'sqlstate', sqlstate, 'error', sqlerrm));
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
    'chg_deferred',     coalesce((p_acc ->> 'chg_deferred')::int, 0)         + v_deferred,                              -- cogs-3(판정 119)
    'chg_skip',         coalesce(p_acc -> 'chg_skip', '[]'::jsonb)           || v_chg_skip,
    'adj_n',            coalesce((p_acc ->> 'adj_n')::int, 0)                + v_adj_n,                                -- po-disc-3
    'adj_rows',         coalesce((p_acc ->> 'adj_rows')::int, 0)             + v_adj_rows,
    'adj_amt',          coalesce((p_acc ->> 'adj_amt')::numeric, 0)          + v_adj_amt,
    'adj_nolayers',     coalesce((p_acc ->> 'adj_nolayers')::int, 0)         + v_adj_nolayers,
    'adj_skipped',      coalesce((p_acc ->> 'adj_skipped')::int, 0)          + v_adj_skipped,
    'adj_deferred',     coalesce((p_acc ->> 'adj_deferred')::int, 0)         + v_adj_deferred,
    'adj_skip',         coalesce(p_acc -> 'adj_skip', '[]'::jsonb)           || v_adj_skip);
end;
$$;

-- ═══ ⑤-b inv_layer_apply 재발행 — 마지막 정의 20260930161946:232~797(DB md5 d9007dbe · 검증 G0) 바이트 복사 + 쏟기 자리 조회 넷(배분 줄 ∪ 조정 사건) · 반환 ims.adjusts 하나 ═══
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
  v_next_post_id bigint;                                                                  -- cogs-2(판정 114): 이날 실시간이 얹은 배분 줄 중 아직 안 부른 것의 가장 이른 원장 자리(posted_ledger_id) — 이 id 뒤 첫 줄 앞에서 쏟는다
  v_left        int;   v_ks smallint;   v_kr int;   v_ki bigint;   v_ims_chg_late int := 0;   -- cogs-3(판정 119): 아직 안 지난 「그날 id ≤ pid 줄」 수 · 그 줄들의 마지막 루프 키(seq_hint · po_in 먼저 · id) · 날 마감에서야 쏟은 배분 줄 수(0 이어야 한다)
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
    if v_add_day is not null and r.occurred_on > v_add_day then
      -- cogs-3(판정 119): 지난 날 마감 — 그날 아직 안 쏟은 posted 배분 줄을 pid 순으로(그날 줄은 다 지났다) · 트리거가 못 잡은 것(그 자리 뒤에 줄이 더 있었는데 못 잡은 것)은 late 로 센다(0 이어야 한다)
      while v_next_post_id is not null loop
        select g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id into v_ks, v_kr, v_ki from inv_ledger g          -- late 판정: 그날 id ≤ pid 줄의 마지막 루프 키 뒤에 줄이 더 있었으면 트리거가 못 잡은 것
          where g.occurred_on = v_add_day and g.id <= v_next_post_id and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in') and (p_until is null or g.occurred_on <= p_until)
          order by 1 desc, 2 desc, 3 desc limit 1;
        select count(*) into v_left from inv_ledger g
          where g.occurred_on = v_add_day and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in') and (p_until is null or g.occurred_on <= p_until)
            and (g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id) > (v_ks, v_kr, v_ki);
        if v_left > 0 then v_ims_chg_late := v_ims_chg_late + 1; end if;
        v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, v_next_post_id + 1, v_add_acc);
      select min(x.pid) into v_next_post_id from (                                                                                   -- po-disc-3: 비용 배분 줄과 원가 조정 사건의 자리를 함께 본다
        select a.posted_ledger_id as pid from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
          where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id > v_next_post_id
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')
        union all
        select j.posted_ledger_id from inv_cost_adjust j
          where j.status = 'posted' and j.posted_on = v_add_day and j.posted_ledger_id > v_next_post_id
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')) x;
      end loop;
      if not v_add_flushed then
        v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, null, v_add_acc);
      end if;
    end if;
    if r.occurred_on is distinct from v_add_day then
      v_add_day := r.occurred_on; v_add_flushed := false;
      select min(x.pid) into v_next_post_id from (                                                                                   -- cogs-2(판정 114) · po-disc-3: 이날 실시간이 얹은 배분 줄 · 원가 조정 사건의 자리
        select a.posted_ledger_id as pid from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
          where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id is not null
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')
        union all
        select j.posted_ledger_id from inv_cost_adjust j
          where j.status = 'posted' and j.posted_on = v_add_day and j.posted_ledger_id is not null
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')) x;
    end if;
    -- ⭐ cogs-3(판정 119): 쏟기 = 그날 id ≤ posted_ledger_id 인 원장 줄을 루프가 모두 지난 뒤 — 루프 순서(seq_hint · po_in 먼저 · id)가 어떻든. 지금 줄 r 앞에서 「아직 안 지난 그런 줄」 = 루프 키가 r 이상인 것(r 포함) · 같은 날 배분 줄이 여럿이면 pid 순으로 차례차례
    --   (옛 트리거 「r.id > pid 인 첫 줄 앞」은 id 순을 가정했다 — 09-29 의 뒤늦은 po_in(8951683 · 유입 맨 앞)이 TRF-00001 · TRF-00002 도착 줄보다 먼저 트리거를 당겨 운임 4줄 190.00 을 잃었다 · cogs-3c)
    --   같은 날 순서 증명: 소진하는 줄은 seq_hint 2 라 유입 전부 뒤에 id 순으로 온다 ⇒ id > pid 인 유출은 쏟기 뒤 · id > pid 인 유입(출발 소진 · 조립)은 쏟기 앞(판정 109 「들어옴 → 얹기 → 나감」 그대로 · 총액 같음)
    while v_next_post_id is not null loop
      select count(*) into v_left from inv_ledger g
        where g.occurred_on = v_add_day and g.id <= v_next_post_id
          and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in')
          and (p_until is null or g.occurred_on <= p_until)
          and (g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id) >= (r.seq_hint, case r.event_type when 'po_in' then 0 else 1 end, r.id);
      exit when v_left > 0;
      v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, v_next_post_id + 1, v_add_acc);
      select min(x.pid) into v_next_post_id from (                                                                                   -- po-disc-3: 비용 배분 줄과 원가 조정 사건의 자리를 함께 본다
        select a.posted_ledger_id as pid from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
          where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id > v_next_post_id
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')
        union all
        select j.posted_ledger_id from inv_cost_adjust j
          where j.status = 'posted' and j.posted_on = v_add_day and j.posted_ledger_id > v_next_post_id
            and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')) x;
    end loop;
    if r.seq_hint = 2 and not v_add_flushed then
      v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, r.id, v_add_acc);  v_add_flushed := true;   -- cogs-2: 그날 첫 유출 앞 — 이 줄 뒤에 얹힌 배분 줄(posted_ledger_id ≥ r.id)은 남긴다
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
  -- cogs-3(판정 119): 마지막 날 마감 — 남은 posted 배분 줄을 pid 순으로(late 판정은 날 마감과 같다)
  while v_next_post_id is not null loop
    select g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id into v_ks, v_kr, v_ki from inv_ledger g          -- late 판정: 그날 id ≤ pid 줄의 마지막 루프 키 뒤에 줄이 더 있었으면 트리거가 못 잡은 것
      where g.occurred_on = v_add_day and g.id <= v_next_post_id and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in') and (p_until is null or g.occurred_on <= p_until)
      order by 1 desc, 2 desc, 3 desc limit 1;
    select count(*) into v_left from inv_ledger g
      where g.occurred_on = v_add_day and g.event_type in ('po_in', 'sale_out', 'transfer_in', 'transfer_out', 'manual_reversal', 'adjust_existing', 'adjust_new', 'assemble_in', 'assemble_out', 'credit_in') and (p_until is null or g.occurred_on <= p_until)
        and (g.seq_hint, case g.event_type when 'po_in' then 0 else 1 end, g.id) > (v_ks, v_kr, v_ki);
    if v_left > 0 then v_ims_chg_late := v_ims_chg_late + 1; end if;
    v_add_acc := inv_layer_apply_flush_adds(v_add_day, p_until, v_next_post_id + 1, v_add_acc);
    select min(x.pid) into v_next_post_id from (                                                                                   -- po-disc-3: 비용 배분 줄과 원가 조정 사건의 자리를 함께 본다
      select a.posted_ledger_id as pid from po_charge_alloc a join po_charge c on c.id = a.po_charge_id
        where c.status = 'confirmed' and c.confirmed_at is not null and a.posted_on = v_add_day and a.posted_ledger_id > v_next_post_id
          and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_chg' and d.doc_number = a.id::text and d.sku = '' and d.warehouse = '')
      union all
      select j.posted_ledger_id from inv_cost_adjust j
        where j.status = 'posted' and j.posted_on = v_add_day and j.posted_ledger_id > v_next_post_id
          and not exists (select 1 from inv_layer_apply_done d where d.kind = 'cogs_adj' and d.doc_number = j.id::text and d.sku = '' and d.warehouse = '')) x;
  end loop;
  v_add_acc := inv_layer_apply_flush_adds(p_until, p_until, null, v_add_acc);                                    -- cogs-1: 마지막 쏟기 — 남은 것 전부(p_until 까지 · 대상이 끝내 없는 것은 아래 orphan · unvisited 신호 그대로)

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

  -- ═══ tr-4b(판정 79) 얹힌 원가 따라가기 — 마지막 한 바퀴 = 검산(cogs-2 · 판정 110) ═══
  -- cogs-2: 얹기는 루프 안 날짜 경계에서 제자리에 들고(첫 차수) 자식이 선 순간 fifo_take 가 carry 를 · 얹히는 순간 settle 이 자식 carried 를 낸다 ⇒ 이 바퀴는 남은 것이 없어야 한다(carried_rows 0 이 정상 · 0 이 아니면 신호).
  --   어느 축이든(불러온 축 TR- 자식도 · 판정 110) 트랜스퍼 자식을 id 순(부모 먼저)으로 한 번 더 돈다 · 멱등(같은 행은 다시 넣지 않는다).
  for v_ims_carry in
    select y.id from inv_layer y
     where y.origin_type = 'transfer' and y.parent_layer_id is not null
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
      'carried_rows',              v_ims_carry_rows,        -- ⭐ tr-4b(판정 79) 마지막 검산 바퀴가 넣은 따라간 행 수 — cogs-2: 0 이 정상(자식이 선 순간 · 얹히는 순간 이미 따라갔다) · 0 이 아니면 신호
      'carried_amount_cad',        v_ims_carry_amt,         -- kind carried 합
      'charge_allocs_late_boundary', v_ims_chg_late,        -- ⭐ cogs-3(판정 119) 트리거가 못 잡아 날 마감에서야 쏟은 posted 배분 줄 수 — 0 이어야 한다(0 이 아니면 세는 집합이 루프와 다르다)
      'charge_allocs_deferred',    coalesce((v_add_acc ->> 'chg_deferred')::int, 0),   -- ⭐ cogs-3(판정 119) 안전띠가 미룬 횟수 — 0 이어야 한다(0 이 아니면 쏟기 기준이 또 틀린 것)
      'adjusts', jsonb_build_object('posted', coalesce((v_add_acc ->> 'adj_n')::int, 0), 'rows', coalesce((v_add_acc ->> 'adj_rows')::int, 0), 'amount_cad', coalesce((v_add_acc ->> 'adj_amt')::numeric, 0),
                                 'no_layers', coalesce((v_add_acc ->> 'adj_nolayers')::int, 0), 'skipped', coalesce((v_add_acc ->> 'adj_skipped')::int, 0), 'deferred', coalesce((v_add_acc ->> 'adj_deferred')::int, 0),
                                 'skip_reasons', coalesce(v_add_acc -> 'adj_skip', '[]'::jsonb)),   -- ⭐ po-disc-3(판정 391 · 394) IMS 원가 조정 사건 — deferred · skipped 는 0 이어야 한다
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

-- ═══ ⑥ 되돌림 창구 inv_cost_adjust_reverse(p_adjust_id · p_note) — 반대 부호 사건(reverses_id) · 원래가 posted 면 곧바로 얹는다 · pending 이면 둘 다 pending(입고 확정이 둘 다 얹어 합 0) · 두 번 되돌리기 · 되돌림의 되돌림 거부 ═══
--   키가 원래와 다르다(line_ref adj:<새 id>) — settle 의 「already_written」(layer · doc_number · line_ref · occurred_on · kind)에 안 걸린다(검증 A9)
create function public.inv_cost_adjust_reverse(p_adjust_id uuid, p_note text default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_j     public.inv_cost_adjust%rowtype;
  v_new   uuid;
  v_post  jsonb;
begin
  perform public.ims_require_write('purchasing', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  select * into v_j from public.inv_cost_adjust where id = p_adjust_id for update;
  if not found then raise exception 'Cost adjustment % not found — nothing was saved', p_adjust_id; end if;
  if v_j.source_type = 'reversal' then
    raise exception 'Cost adjustment % (%) is itself a reversal — a reversal is not reversed; post a new adjustment instead — nothing was saved', v_j.source_number, v_j.id;
  end if;
  if exists (select 1 from public.inv_cost_adjust r where r.reverses_id = v_j.id) then
    raise exception 'Cost adjustment % (%) was already reversed — nothing was saved', v_j.source_number, v_j.id;
  end if;
  insert into public.inv_cost_adjust (kind, target_type, po_line_id, po_charge_alloc_id, amount_cad, amount_doc, currency_id, exchange_rate, source_type, source_id, source_number, reverses_id, status, note, created_by, updated_by)
  values (v_j.kind, v_j.target_type, v_j.po_line_id, v_j.po_charge_alloc_id, -v_j.amount_cad, -v_j.amount_doc, v_j.currency_id, v_j.exchange_rate, 'reversal', v_j.id, v_j.source_number, v_j.id, 'pending', p_note, v_staff, v_staff)
  returning id into v_new;
  if v_j.status = 'posted' then v_post := public.inv_layer_post_cost_adjust(v_new); end if;   -- 원래가 posted 면 지금 얹는다(같은 레이어 집합 · 반대 부호 · 자기 posted_on 자리)
  return jsonb_build_object('reversal_id', v_new, 'reverses_id', v_j.id, 'source_number', v_j.source_number, 'kind', v_j.kind, 'target_type', v_j.target_type, 'amount_cad', -v_j.amount_cad,
                            'status', case when v_j.status = 'posted' then coalesce(v_post ->> 'status', 'posted') else 'pending' end, 'posting', v_post);
end;
$$;
revoke all on function public.inv_cost_adjust_reverse(uuid, text) from public, anon;
grant execute on function public.inv_cost_adjust_reverse(uuid, text) to authenticated;
comment on function public.inv_cost_adjust_reverse(uuid, text) is 'po-disc-3 ⭐ 원가 조정 되돌림 창구(purchasing · 2026-10-09) — 같은 대상 · 반대 부호 · source_type reversal · reverses_id(유니크 — 한 번만) · 원래가 posted 면 곧바로 inv_layer_post_cost_adjust(자기 자리) · pending 이면 둘 다 pending(입고 확정이 둘 다 얹어 합 0) · 되돌림의 되돌림은 거부(새 사건을 올린다) · 원래 사건은 지우지 않는다';

-- ═══ ⑦ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text;
begin
  if to_regclass('public.inv_cost_adjust') is null then v_bad := v_bad || ' table'; end if;
  if not (select relrowsecurity from pg_class where oid = 'public.inv_cost_adjust'::regclass) then v_bad := v_bad || ' rls'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'inv_cost_adjust') <> 1 then v_bad := v_bad || ' policies'; end if;
  if has_table_privilege('authenticated', 'public.inv_cost_adjust', 'insert') or has_table_privilege('authenticated', 'public.inv_cost_adjust', 'update') or has_table_privilege('authenticated', 'public.inv_cost_adjust', 'delete')
     or not has_table_privilege('authenticated', 'public.inv_cost_adjust', 'select') then v_bad := v_bad || ' authenticated-privileges'; end if;
  if has_table_privilege('anon', 'public.inv_cost_adjust', 'select') or has_table_privilege('anon', 'public.inv_cost_adjust', 'insert') then v_bad := v_bad || ' anon-privileges'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.inv_cost_adjust'::regclass and tgname = 'inv_cost_adjust_touch') <> 1 then v_bad := v_bad || ' touch-trigger'; end if;
  v_t := 'public.inv_layer_post_cost_adjust(uuid, date)';
  if to_regprocedure(v_t) is null then v_bad := v_bad || ' window(missing)'; end if;
  if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || ' window(grants)'; end if;
  v_t := 'public.inv_cost_adjust_reverse(uuid, text)';
  if to_regprocedure(v_t) is null then v_bad := v_bad || ' reverse(missing)'; end if;
  if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || ' reverse(grants)'; end if;
  if (select pg_get_constraintdef(oid) from pg_constraint where conname = 'inv_layer_cost_add_kind_ck') not like '%settlement_discount%' then v_bad := v_bad || ' cost_add-kind-check'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'po_receipt_confirm_by' and p.prosrc like '%inv_layer_post_cost_adjust%' and p.prosrc like '%''adjustments'', jsonb_build_object%') <> 1 then v_bad := v_bad || ' po_receipt_confirm_by'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'inv_layer_apply_flush_adds' and p.prosrc like '%cogs_adj%' and p.prosrc like '%''adj_deferred''%') <> 1 then v_bad := v_bad || ' inv_layer_apply_flush_adds'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'inv_layer_apply' and (length(p.prosrc) - length(replace(p.prosrc, 'd.kind = ''cogs_adj''', ''))) / length('d.kind = ''cogs_adj''') = 4 and p.prosrc like '%''adjusts'', jsonb_build_object%') <> 1 then v_bad := v_bad || ' inv_layer_apply'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('inv_layer_cost_add_settle', 'inv_layer_post_charge', 'inv_layer_post_receipt', 'inv_layer_value', 'inv_layer_carry', 'inv_layer_post_adjust') and p.prosrc like '%po-disc-3%') <> 0 then v_bad := v_bad || ' untouched-functions-touched'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM393', message = format('STOP - po-disc-3 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
