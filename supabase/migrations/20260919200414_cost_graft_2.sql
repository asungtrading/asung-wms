-- ─────────────────────────────────────────────────────────────
-- 원가 이식 2차 — 비용이 레이어에 얹힌다 (Asung-IMS · 2026-09-19)
--   ① inv_layer_post_charge(charge_id)   ⭐⭐ 원가의 창구 둘째 — 확정된 비용 문서의 배분(po_charge_alloc · 발주 단위)을 그 발주의 IMS 입고 레이어에 금액 비율로 나눠 inv_layer_cost_add(kind='landed') 에 얹는다
--   ② po_charge_confirm(charge_id, confirm)  다시 냄(시그니처 무변 · create or replace) — 확정 때 게이트 ⑥ 환율 · 확정 뒤 ① 호출(같은 트랜잭션) · 반환 + cost · 되돌리기는 landed 가 얹혔으면 거부
--
-- ⚠️⚠️ create or replace 둘 · 표 변경 없음(kind 어휘 그대로 · 넷 다 landed). 선언 변수는 원문과 겹치지 않는 이름(v_cost · v_cur · v_base_cur — 원문 일곱은 v_doc·v_staff·v_chg·v_m·v_n·v_txt·v_warn).
-- 앞 차수: 20260919192236(원가 이식 1차 · inv_layer_post_receipt · cost_source po_line) · 20260918013000(po_charge_confirm 마지막 정의 · 여기서 복사) · 20260917150000(비용 표·RPC).
-- 정본: ledger-design §4단계 「B. 배분은 inv_layer_apply 에서」 배분 규칙 표(기준 unit_cost × qty · remaining 아님 · 끝수는 마지막 레이어 · 6자리) · 「D. 기준이 0 인 문서는 버린다 — 수량 비례로 하지 않는다」(Caleb 2026-09-10)
--       · po-module §11-f(비용 문서 · 배분은 박아 둔다) · 지시서 ~/asung/prompts/ims-cost-graft-2.md · ⬜1~9 는 회신에
--
-- ⭐ Caleb 판정 (2026-09-19): kind 넷(freight · duty · brokerage · other)을 **전부 landed** 로 얹는다 — other 는 「모르는 것」이 아니라 「넷으로 안 갈리는 진짜 수입 부대비」(중국 에이전트 수수료).
--   ⬜ 에이전트 수수료를 재고 원가에 넣는지는 확인 중 — 지금은 넣는다. inv_layer_cost_add.kind 는 늘리지 않는다 — 「관세가 얼마나 얹혔나」는 doc_number(비용 번호)로 po_charge.kind 를 거슬러 센다.
--   transfer_freight 은 창고간 운송비 — IMS 에 트랜스퍼 문서가 없어 오늘 안 건드린다.
--
-- ⚠️⚠️⚠️ 환율 방향 — po_charge.exchange_rate 는 **CAD per USD** 다(발주와 같은 뜻 · 화면 「CAD per USD」). amount(청구 통화) × exchange_rate = CAD. **곱한다 — 나누면 반값인데 에러가 안 난다.**
--   기준통화(CAD) 비용은 환율이 null 이어도 맞다 — 곱하지 않는다(적혀 있으면 무시하고 경고만).
--
-- ⭐⭐ 이견 1 — 그 발주의 입고 레이어는 **po_line 을 거쳐** 찾는다: inv_layer.line_ref = po_line.id::text and po_line.po_id = alloc.po_id and cost_source = 'po_line'.
--   레이어 doc_number 는 RCV 라 PO 번호로는 못 찾지만, line_ref 가 po_line_id(원장 키 규칙 · 이식 2차)라 발주 라인 표 하나만 거치면 된다 — 원장(raw.po_number)을 거치지 않는다.
--   po_receipt.po_id 를 거치는 길과 같은 집합이다(입고 줄은 그 발주의 라인에만 붙는다) — 검증 ⓪ 이 둘의 차집합 0 을 센다. 갈라진 문서(a·b)는 alloc 이 가리키는 그 문서의 라인만 잡는다(라인이 문서를 따라간다 · §11-c).
-- ⭐ 이견 2 — Cin7 레이어(cost_source='inv_cost')는 **섞이지 않는다**: line_ref 가 Cin7 CardID 이고 cost_source 필터가 거른다. 같은 물리 발주가 Cin7 에도 있었다면 그쪽 landed 는 inv_cost 가 따로 얹는다(shadow 두 세계).
-- ⭐ 이견 3 — line_ref = po_charge_alloc.id(배분 줄 · 문서×발주 유니크) · ref_number = 그 발주 번호(갈라진 뒤 · 「이 발주에 얹힌 비용」 조회 길) · occurred_on = po_charge.charge_date(청구서 날짜 · 표 주석 「원장 occurred_on 이 된다」 · 확정일이 아니다).
-- ⭐ 이견 4 — 멱등은 배분 줄 단위: 같은 (kind landed · doc_number 비용번호 · line_ref alloc.id) 행이 하나라도 있으면 그 배분 줄은 건너뛴다(already_posted). 유니크 (layer_id,kind,doc_number,line_ref,occurred_on)가 마지막 방어.
-- ⭐ 이견 5 — 기준 0(그 발주의 po_line 레이어 합 unit_cost×qty = 0)이면 **버리고 센다**(no_basis · 정본 D) · 레이어가 아예 없으면(IMS 입고 없음) 따로 센다(no_layers — 백필 ⬜7 의 창구). 수량 비례로 대신하지 않는다.
-- ⭐ 이견 6 — 음수 배분(정정)은 얹는다(음수 landed = 상쇄 · 표에 CHECK 없음 · 정본 「정정이 음수로 올 수 있다」) · 경고 negative_amount.
-- ⚠️⚠️ 이견 7 — **되돌리기(p_confirm=false)는 landed 가 얹혔으면 거부한다.** 원문에는 없던 게이트다(「그 밖은 건드리지 마라」의 예외 — 안 넣으면 되돌려 배분을 고치고 다시 확정해도 멱등이 건너뛰어 옛 금액이 남는다). 고치려면 상쇄 비용 문서로(append-only).
-- ⚠️⚠️ inv_layer_apply() 전량 재생성은 cost_add 를 전부 지우고 source='cin7' 만 되살린다 — 오늘 얹은 비용과 1차 레이어가 함께 사라진다. **IMS 판이 들어가기 전까지 돌리지 마라**(§13-f).
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① inv_layer_post_charge(p_charge_id) — ⭐⭐ 비용을 레이어에 얹는다 ═══
-- 읽는 것: 확정된 po_charge · 그 po_charge_alloc(발주별 금액 · 청구 통화) · 발주마다 IMS 입고 레이어(po_line 을 거쳐 · cost_source='po_line').
-- 나누는 것: 배분 줄 금액 × 환율(CAD) 을 그 발주 레이어들에 **unit_cost × qty 비율**로(정본 B) · 소수 6자리 · 끝수는 마지막 레이어(sku, line_ref, id 순의 마지막) — 합이 정확히 금액과 같다.
-- 넣는 것: inv_layer_cost_add — kind 'landed' · amount CAD · occurred_on charge_date · doc_number 비용 번호 · line_ref alloc.id · ref_number 발주 번호.
-- 세는 것: layers_touched · amount_posted_cad · no_basis(기준 0 · 버림) · no_layers(입고 없음 · 버림) · already_posted(멱등) — 버린 금액은 반환에 남아 Cin7 대조에서 「설명된 차이」가 된다(정본 D).
-- 막는 것(문장): 권한(purchasing) · 확정 아님 · base_currency 없음 · 기준통화 아닌데 환율 null·0 · 배분 줄 없음.
-- security invoker — inv_layer_cost_add 는 authenticated 에 insert 가 열려 있다(auth_all · delete/truncate 만 회수) · 읽는 표 전부 select 열림.
create or replace function public.inv_layer_post_charge(p_charge_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_version    constant text := 'inv_layer_post_charge@2026-09-19.1';
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
  v_po_number  text;
begin
  perform public.ims_require_write('purchasing', 'posted');

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

  -- 배분 줄마다(발주마다)
  for v_alloc in
    select a.id, a.po_id, a.amount, p.po_number
    from public.po_charge_alloc a join public.po p on p.id = a.po_id
    where a.po_charge_id = p_charge_id
    order by p.po_number
  loop
    v_po_number  := v_alloc.po_number;
    -- ⚠️⚠️⚠️ CAD per USD × 청구 통화 금액 = CAD. 곱한다.
    v_amount_cad := v_alloc.amount * v_factor;

    -- 멱등 — 이 비용·이 배분 줄로 이미 얹은 행이 있으면 건너뛴다(이견 4)
    if exists (select 1 from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number and ca.line_ref = v_alloc.id::text) then
      v_already := v_already + 1; v_already_amt := v_already_amt + v_amount_cad;
      v_allocs := v_allocs || jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'already_posted', 'layers', 0, 'posted_cad', 0);
      continue;
    end if;

    -- 그 발주의 IMS 입고 레이어 — po_line 을 거쳐(이견 1) · Cin7 레이어는 cost_source 로 갈린다(이견 2)
    select count(*), coalesce(sum(x.unit_cost * x.qty), 0)
      into v_n_layers, v_basis
    from public.inv_layer x
    join public.po_line pl on pl.id::text = x.line_ref
    where x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_alloc.po_id;

    if v_n_layers = 0 then
      v_no_layers := v_no_layers + 1; v_no_layers_amt := v_no_layers_amt + v_amount_cad;
      v_allocs := v_allocs || jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'no_layers', 'layers', 0, 'posted_cad', 0);
      continue;
    end if;
    if v_basis = 0 then
      -- 정본 D — 기준이 0 이면 버린다 · 수량 비례로 대신하지 않는다(Cin7 CostDistributionType='Cost' 와 방식이 갈린다)
      v_no_basis := v_no_basis + 1; v_no_basis_amt := v_no_basis_amt + v_amount_cad;
      v_allocs := v_allocs || jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                                 'status', 'no_basis', 'layers', v_n_layers, 'posted_cad', 0);
      continue;
    end if;

    -- 금액 비율(unit_cost × qty · 정본 B) · 6자리 · 끝수는 마지막 레이어
    v_given := 0; v_i := 0; v_lines := '[]'::jsonb;
    for v_lay in
      select x.id, x.sku, x.warehouse, x.line_ref, x.qty, x.unit_cost, x.unit_cost * x.qty as basis
      from public.inv_layer x
      join public.po_line pl on pl.id::text = x.line_ref
      where x.origin_type = 'purchase' and x.cost_source = 'po_line' and pl.po_id = v_alloc.po_id
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
      v_lines := v_lines || jsonb_build_object('layer_id', v_lay.id, 'sku', v_lay.sku, 'warehouse', v_lay.warehouse, 'po_line_id', v_lay.line_ref,
                                               'qty', v_lay.qty, 'unit_cost', v_lay.unit_cost, 'basis', v_lay.basis, 'share_cad', v_share);
    end loop;
    v_posted := v_posted + v_given;
    v_allocs := v_allocs || jsonb_build_object('alloc_id', v_alloc.id, 'po_id', v_alloc.po_id, 'po_number', v_po_number, 'amount', v_alloc.amount, 'amount_cad', v_amount_cad,
                                               'status', 'posted', 'layers', v_n_layers, 'basis', v_basis, 'posted_cad', v_given, 'lines', v_lines);
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
    'allocs', v_allocs, 'builder', c_version, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Charge % — a landed cost row with the same key already exists (%) — no cost was added', v_chg.charge_number, sqlerrm;
end;
$$;
comment on function public.inv_layer_post_charge(uuid) is '⭐⭐ 원가의 창구 둘째(원가 이식 2차 · 2026-09-19) — 확정된 비용 문서(po_charge)의 배분 줄(po_charge_alloc · 발주 단위 · 박아 둔 금액)을 그 발주의 IMS 입고 레이어(inv_layer.line_ref = po_line.id · cost_source po_line)에 unit_cost×qty 비율로 나눠 inv_layer_cost_add(kind landed)에 얹는다. kind 넷(freight·duty·brokerage·other) 전부 landed(Caleb) — 비용 종류는 doc_number(비용 번호)로 po_charge.kind 를 거슬러 센다. amount CAD(⚠️ CAD per USD · 곱한다 · 기준통화면 ×1) · occurred_on charge_date · line_ref alloc.id · ref_number 발주 번호 · 6자리 · 끝수는 마지막 레이어. 버림(정본 D): 기준 0 → no_basis · 레이어 없음 → no_layers — 금액을 반환에 남긴다(Cin7 대조의 설명된 차이). 멱등: 배분 줄 단위(already_posted). 거부(문장): 권한(purchasing) · 확정 아님 · 환율 없음 · 배분 줄 없음. ⚠️ inv_layer_apply() 재생성이 이 행을 지우고 되살리지 않는다(§13-f). security invoker · append-only';
revoke all on function public.inv_layer_post_charge(uuid) from public, anon;
grant execute on function public.inv_layer_post_charge(uuid) to authenticated;

-- ═══ ② po_charge_confirm — 다시 냄 (20260918013000 269행~ 원문 복사 · 시그니처 무변 · 바뀐 곳 넷: declare 셋 · 게이트 ⑥ 환율(unallocated 검사 뒤 · update 앞) · 확정 뒤 ① 호출 · 되돌리기 landed 거부 · 반환 cost) ═══
create or replace function public.po_charge_confirm(p_charge_id uuid, p_confirm boolean default true) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_doc   text;                                                 -- ②-b: 0행 문장용(returning 이 v_chg 를 null 로 덮는다)
  v_staff uuid;
  v_chg   public.po_charge%rowtype;
  v_m     record;
  v_n     int;
  v_txt   text;
  v_warn  text[] := '{}';
  v_cost  jsonb;                                                -- 원가 창구의 반환(원가 이식 2차 · 2026-09-19)
  v_cur   text;                                                 -- ⑥ 환율 게이트 — 청구 통화 코드
  v_base_cur text;                                              -- ⑥ 기준통화 코드(inv_config.base_currency) · ⚠️ 원문에 같은 이름 없음 확인(2026-09-19 v_base 실사고)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  v_doc := 'Charge ' || v_chg.charge_number;
  select * into v_m from public.po_charge_money where id = p_charge_id;

  if p_confirm then
    if v_chg.status = 'confirmed' then raise exception 'Charge % is already confirmed — nothing was saved', v_chg.charge_number; end if;
    if v_chg.status = 'cancelled' then raise exception 'Charge % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_chg.charge_number; end if;
    select count(*) into v_n from public.po_charge_alloc where po_charge_id = p_charge_id;
    if v_n = 0 then raise exception 'Charge % has no allocation lines — nothing to put on cost — nothing was saved', v_chg.charge_number; end if;
    -- ⭐⭐ 거부(경고 아님) — 양쪽 다 우리가 넣는 숫자라 안 맞으면 덜 입력한 것(⑤)
    if v_m.unallocated <> 0 then
      raise exception 'Charge % is not fully allocated — total % · allocated % · unallocated % — fix the allocations (or press Spread) first — nothing was saved',
        v_chg.charge_number, v_m.total_amount, v_m.alloc_sum, v_m.unallocated;
    end if;
    if v_chg.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;
    if exists (select 1 from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = p_charge_id and x.status = 'cancelled') then
      v_warn := array_append(v_warn, 'alloc_on_cancelled_po');
    end if;
    -- ⑥ ⭐⭐ 환율 — 기준통화가 아닌 비용인데 환율이 없거나 0 이면 확정 거부(입고와 같은 이유 · 원가가 조용히 틀리는 것보다 낫다 · 원가 이식 2차 2026-09-19)
    --   ⚠️ po_charge.exchange_rate 는 CAD per USD 다 — amount × exchange_rate = CAD. 곱한다 · 나누지 않는다(계산은 inv_layer_post_charge 에서).
    select c.code into v_cur from public.ref_currency c where c.id = v_chg.currency_id;
    select k.value into v_base_cur from public.inv_config k where k.key = 'base_currency';
    if v_base_cur is null then raise exception 'inv_config.base_currency is not set — cannot tell which charges need an exchange rate — nothing was saved'; end if;
    if v_cur is distinct from v_base_cur and (v_chg.exchange_rate is null or v_chg.exchange_rate <= 0) then
      raise exception 'Charge % is in % but has no % per % exchange rate — the cost cannot be put on stock without it. Enter the rate on the charge ("Exchange rate") and confirm again — nothing was saved',
        v_chg.charge_number, coalesce(v_cur, '?'), v_base_cur, coalesce(v_cur, '?');
    end if;
    update public.po_charge set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    -- ⭐ 원가 — 같은 트랜잭션으로 레이어에 얹는다(원장 이식 2차의 ⓔ 와 같은 판단 · 원칙 2 「안에 있는 것끼리는 창구를 부른다」 · 하나가 실패하면 확정도 실패)
    v_cost := public.inv_layer_post_charge(p_charge_id);
    if coalesce((v_cost->>'no_layers_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_not_on_stock_no_receipt_yet'); end if;   -- 입고가 없는 발주 — 나중에 백필(inv_layer_post_charge 재호출)
    if coalesce((v_cost->>'no_basis_allocs')::int, 0) > 0 then v_warn := array_append(v_warn, 'cost_dropped_no_basis'); end if;                 -- 정본 D — 기준 0 은 버린다
  else
    if v_chg.status <> 'confirmed' then raise exception 'Charge % is % — only a confirmed document can be reopened — nothing was saved', v_chg.charge_number, v_chg.status; end if;
    -- ⭐ po_invoice_confirm Reopen · po_doc_cancel 과 같은 선 — 결제 참조번호·금액을 이름으로
    if v_m.paid > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_charge_id = p_charge_id;
      raise exception 'Charge % has payments applied (%) — cannot reopen while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
    end if;
    -- ⭐ [원가 이식 2차] landed 가 이미 레이어에 얹혔으면 되돌리지 않는다 — 원가는 append-only. 되돌려 배분을 고치고 다시 확정해도 멱등이 건너뛰어 옛 금액이 남는다.
    select count(*) into v_n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = v_chg.charge_number;
    if v_n > 0 then
      raise exception 'Charge % has already been added to stock cost (% layer row(s)) — it cannot be reopened; to correct it, enter an offsetting charge — nothing was saved', v_chg.charge_number, v_n;
    end if;
    update public.po_charge set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
  end if;

  return jsonb_build_object(
    'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status, 'confirmed_at', v_chg.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'paid', v_m.paid, 'unpaid', v_m.unpaid, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated),
    'cost', v_cost,                                                                              -- ⭐ 원가 결과(layers_touched · amount_posted_cad · no_layers · no_basis · allocs[]) · 되돌리기면 null
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_charge_confirm(uuid, boolean) is '⑤ 비용 확정(p_confirm=true) = 「이 배분으로 원가에 얹겠다」는 선언. 검사: 배분 0줄 ⇒ 거부 · ⭐ unallocated ≠ 0 ⇒ 거부 · ⭐ [원가 이식 2차 2026-09-19] 기준통화(inv_config.base_currency) 아닌 비용에 환율(CAD per USD)이 없거나 0 ⇒ 거부(어디서 고치는지 문장에) · total 0 ⇒ 경고 · 취소된 발주에 배분 ⇒ 경고. ⭐ 확정 뒤 같은 트랜잭션으로 inv_layer_post_charge 가 landed 를 얹는다(레이어 없는 발주·기준 0 은 버리고 센다 — 반환 cost) · 하나가 실패하면 확정도 실패. 되돌리기(false)는 결제 충당이 있으면 거부 · ⭐ landed 가 이미 얹혔으면 거부(append-only — 상쇄 비용 문서로 고친다). confirmed_by 서버 유도. 정본 po-module §11-f · ledger-design §4단계 B·D';
-- grant·revoke 는 20260917150000 의 것이 유지된다(create or replace).

-- ─────────────────────────────────────────────────────────────
-- 화면(charges.html · 대화 Claude)이 보는 모양
--   확정 거부  「Charge … is in USD but has no CAD per USD exchange rate — … Enter the rate on the charge …」 · 「… cost has already been added to stock layers — … offsetting charge …」(되돌리기)
--   확정 뒤    data.cost.layers_touched · amount_posted_cad · no_layers_allocs(⚠️ 입고가 아직 없는 발주 — 나중에 백필) · no_basis_allocs
--   백필       select inv_layer_post_charge('<charge id>') — 이미 확정된 비용(관세 10039192310530) · 배분 줄 단위 멱등이라 다시 불러도 한 벌
-- 검증(회신 §4 · psql heredoc · Caleb 이 실행 · 쓰는 것은 rollback) 요지 — ⓪ PO-02002·02001a 레이어 유무 · 750행 doc_number ① 확정 → landed 합 = 배분액 ② 금액 비율 손 검산 ③ doc_number = 비용 번호
--   ④ 기준 0 버림 ⑤ 멱등 ⑥ 환율 곱하기 ⑦ 권한 ⑧ 평가액 +배분액 ⑨ 롤백 뒤 무흔적
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ─────────────────────────────────────────────────────────────
