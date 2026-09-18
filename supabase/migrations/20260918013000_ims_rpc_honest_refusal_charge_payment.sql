-- ─────────────────────────────────────────────────────────────
-- 쓰기 RPC 가 막혔을 때 정직하게 답한다 — ③/③ 비용·결제 계열 (Asung-IMS) · 2026-09-17 밤
--
-- 앞 차수: 20260918000000(①/③ 발주 · 도우미 신설) · 20260918003000(②/③ 인보이스·할인) · 20260918010000(도우미 문장 하나로). 전부 적용됨 — 고치지 않는다.
-- 같은 처방: ① 첫머리 perform ims_require_write('purchasing', 'saved'|'deleted') — 문장은 도우미(새 판)가 만든다 · 함수는 부르기만
--            ② delete 뒤 get diagnostics row_count · update 뒤 row_count 또는 returning 뒤 if not found — 0행이면 「… was not saved|deleted — it may have been removed or changed by someone else just now — nothing was …」
-- 이 파일의 아홉(전부 purchasing 한 묶음): po_charge_create · po_charge_alloc_add · po_charge_alloc_update · po_charge_alloc_delete · po_charge_alloc_spread · po_charge_confirm ·
--   po_payment_create · po_payment_alloc_set · po_payment_alloc_delete
--   본문은 원본(20260917150000 · 20260917190000)에서 **바이트 그대로** 옮기고 아래 줄만 더했다(스크립트로 이어 붙임 · 회신에 diff 첨부).
--   아홉 정의 전부 머리를 `create` → `create or replace` 로 바꿨다(원본은 replace 없이 만들어졌다) · 인자 무변 ⇒ 덧씌워진다 · grant·comment 유지.
--
-- 함수별로 더한 것
--   po_charge_create          perform (insert 만 · 미리 보기 p_commit=false 도 막는다 — ①/③ 이견 3 과 같은 이유)
--   po_charge_alloc_add       perform (insert 만)
--   po_charge_alloc_update    perform + update row_count
--   po_charge_alloc_delete    perform('deleted') + delete row_count
--   po_charge_alloc_spread    perform + 루프 안 update 마다 row_count (발주 번호로 어느 줄인지 말한다)
--   po_charge_confirm         perform + update 2곳 0행 검사 (v_doc 를 미리 든다 — returning 이 v_chg 를 null 로 덮는다)
--   po_payment_create         perform (insert 만 · p_commit=false 도 막는다)
--   po_payment_alloc_set      perform + update 갈래 row_count (insert 갈래는 그대로)
--   po_payment_alloc_delete   perform('deleted') + delete row_count
-- ─────────────────────────────────────────────────────────────

-- ═══ 1) po_charge_create — 첫머리 권한 (insert 만) ═══
create or replace function public.po_charge_create(
  p_supplier_id   uuid,                        -- 경비처(CBSA · BBE · Showtime …) — 발주처가 아니다
  p_charge_number text,                        -- 청구서 번호 · unique (supplier_id, charge_number)
  p_charge_date   date,                        -- 안 주면 오늘
  p_kind          text,                        -- freight | duty | brokerage | other
  p_total_amount  numeric,                     -- ⭐ 필수 · 우리가 넣는 숫자(계산값이 없다) · 정정은 음수 가능
  p_currency_id   uuid    default null,        -- ⭐ 필수(null 이면 거부 · 폴백 없음 · 이견 5 뒤집음) — 청구서는 자기 통화로 오고 비용처는 건마다 통화가 다를 수 있어 마스터 값이 그 청구서의 통화라는 보장이 없다 · 틀려도 결제 단계까지 조용히 간다. default null 은 인자 순서(뒤에 default 가 있다) 때문이지 선택이라는 뜻이 아니다
  p_due_date      date    default null,
  p_description   text    default null,
  p_note          text    default null,
  p_po_ids        uuid[]  default '{}',        -- 처음 담을 발주(빈 배열 허용) · ⑥ 규칙으로 배분 제안
  p_commit        boolean default false        -- false = 미리 보기(넣지 않는다)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_sup       public.supplier%rowtype;
  v_num       text;
  v_cur       uuid;
  v_cur_code  text;
  v_exists    int;
  v_missing   int;
  v_chg_id    uuid;
  v_allocs    jsonb := '[]'::jsonb;
  v_sum       numeric := 0;
  v_base_sum  numeric := 0;
  v_n         int := 0;
  v_warn      text[] := '{}';
  r           record;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_sup from public.supplier where id = p_supplier_id;
  if not found then raise exception 'Supplier % not found — nothing was saved', p_supplier_id; end if;

  v_num := nullif(regexp_replace(coalesce(p_charge_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if v_num is null then raise exception 'Charge number is required — it is the supplier''s document number — nothing was saved'; end if;
  if p_kind is null or p_kind not in ('freight', 'duty', 'brokerage', 'other') then
    raise exception 'p_kind must be freight, duty, brokerage or other — nothing was saved';
  end if;
  if p_total_amount is null then raise exception 'Total amount is required — nothing was saved'; end if;

  -- 통화 — 사람이 고른다 · 폴백 없음(Caleb 2026-09-17 · 이견 5 뒤집음): 비용처는 건마다 통화가 다를 수 있어 공급처 마스터 값이 이 청구서의 통화라는 보장이 없고, 틀리면 결제 단계까지 조용히 간다
  if p_currency_id is null then raise exception 'Currency is required — nothing was saved'; end if;
  v_cur := p_currency_id;
  select c.code into v_cur_code from public.ref_currency c where c.id = v_cur;
  if v_cur_code is null then raise exception 'Currency % not found — nothing was saved', v_cur; end if;

  -- 번호 중복 — 미리 보기는 경고 · commit 은 읽을 문장으로 거부
  select count(*) into v_exists from public.po_charge where supplier_id = p_supplier_id and charge_number = v_num;
  if v_exists > 0 then
    if p_commit then raise exception 'Charge % already exists for % — nothing was saved', v_num, v_sup.name; end if;
    v_warn := array_append(v_warn, 'charge_number_exists');
  end if;
  if p_total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;

  -- 발주 존재 검사 — 제안 함수는 없는 id 를 조용히 빠뜨리므로 여기서 먼저
  select count(*) into v_missing from unnest(coalesce(p_po_ids, '{}'::uuid[])) u where not exists (select 1 from public.po x where x.id = u);
  if v_missing > 0 then raise exception '% of the given PO id(s) do not exist — nothing was saved', v_missing; end if;

  -- commit: 머리 한 행(만든 사람 서버 유도)
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
    insert into public.po_charge (supplier_id, charge_number, charge_date, due_date, kind, description, currency_id, total_amount, status, created_by, note)
    values (p_supplier_id, v_num, coalesce(p_charge_date, current_date), p_due_date, p_kind, p_description, v_cur, p_total_amount, 'draft', v_staff, p_note)
    returning id into v_chg_id;
  end if;

  -- 배분 제안(⑥ 규칙 한 곳) — 미리 보기는 계산만 · commit 은 박는다
  for r in select * from public.po_charge_alloc_propose(p_total_amount, p_po_ids) loop
    v_n := v_n + 1; v_sum := v_sum + r.amount; v_base_sum := v_base_sum + r.base_amount;
    if r.po_status = 'cancelled' and not ('alloc_on_cancelled_po' = any(v_warn)) then v_warn := array_append(v_warn, 'alloc_on_cancelled_po'); end if;
    if p_commit then
      insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (v_chg_id, r.po_id, r.amount);
    end if;
    v_allocs := v_allocs || jsonb_build_object('po_id', r.po_id, 'po_number', r.po_number, 'po_status', r.po_status, 'base_amount', r.base_amount, 'amount', r.amount, 'inserted', p_commit);
  end loop;
  if v_n > 0 and v_base_sum = 0 then v_warn := array_append(v_warn, 'no_base_amount'); end if;   -- 라인 금액이 전부 0 → 균등으로 나눴다

  return jsonb_build_object(
    'committed', p_commit, 'charge_id', v_chg_id, 'charge_number', v_num, 'charge_date', coalesce(p_charge_date, current_date), 'kind', p_kind,
    'supplier_id', p_supplier_id, 'supplier_name', v_sup.name, 'currency_id', v_cur, 'currency_code', v_cur_code,
    'total_amount', p_total_amount, 'alloc_sum', v_sum, 'unallocated', p_total_amount - v_sum,
    'allocs', v_allocs, 'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception 'Charge % already exists for % — nothing was saved', v_num, coalesce(v_sup.name, 'this supplier');
end;
$$;

-- ═══ 2) po_charge_alloc_add — 첫머리 권한 (insert 만) ═══
create or replace function public.po_charge_alloc_add(p_charge_id uuid, p_po_id uuid, p_amount numeric default 0) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_chg  public.po_charge%rowtype;
  v_po   public.po%rowtype;
  v_id   uuid;
  v_m    record;
  v_warn text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  if v_chg.status <> 'draft' then
    raise exception 'Charge % is % — allocations can be edited only while draft — nothing was saved', v_chg.charge_number, v_chg.status;
  end if;
  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  if exists (select 1 from public.po_charge_alloc where po_charge_id = p_charge_id and po_id = p_po_id) then
    raise exception 'PO % is already on charge % — edit that line instead — nothing was saved', v_po.po_number, v_chg.charge_number;
  end if;
  if v_po.status = 'cancelled' then v_warn := array_append(v_warn, 'alloc_on_cancelled_po'); end if;

  insert into public.po_charge_alloc (po_charge_id, po_id, amount) values (p_charge_id, p_po_id, coalesce(p_amount, 0)) returning id into v_id;
  select * into v_m from public.po_charge_money where id = p_charge_id;
  return jsonb_build_object('alloc_id', v_id, 'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'po_id', v_po.id, 'po_number', v_po.po_number, 'po_status', v_po.status,
                            'amount', coalesce(p_amount, 0), 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 3) po_charge_alloc_update — 첫머리 권한 + update 0행 검사 ═══
create or replace function public.po_charge_alloc_update(p_alloc_id uuid, p_amount numeric) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_n    int;                                                   -- ②-b: row_count
  v_al   public.po_charge_alloc%rowtype;
  v_chg  public.po_charge%rowtype;
  v_pon  text;
  v_m    record;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  if p_amount is null then raise exception 'p_amount is required — nothing was saved'; end if;
  select * into v_al from public.po_charge_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — nothing was saved', p_alloc_id; end if;
  select * into v_chg from public.po_charge where id = v_al.po_charge_id;
  if v_chg.status <> 'draft' then
    raise exception 'Charge % is % — allocations can be edited only while draft — nothing was saved', v_chg.charge_number, v_chg.status;
  end if;
  select po_number into v_pon from public.po where id = v_al.po_id;

  update public.po_charge_alloc set amount = p_amount where id = p_alloc_id;     -- ⭐ 이 한 줄만 — 나머지는 저절로 움직이지 않는다(④)
  get diagnostics v_n = row_count;                              -- ②-b
  if v_n = 0 then raise exception 'Allocation line % on charge % was not saved — it may have been removed or changed by someone else just now — nothing was saved', p_alloc_id, v_chg.charge_number; end if;
  select * into v_m from public.po_charge_money where id = v_chg.id;
  return jsonb_build_object('alloc_id', v_al.id, 'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'po_number', v_pon,
                            'amount_before', v_al.amount, 'amount', p_amount, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated);
end;
$$;

-- ═══ 4) po_charge_alloc_delete — 첫머리 권한 + delete 0행 검사 ═══
create or replace function public.po_charge_alloc_delete(p_alloc_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_n    int;                                                   -- ②-b: row_count
  v_al   public.po_charge_alloc%rowtype;
  v_chg  public.po_charge%rowtype;
  v_pon  text;
  v_m    record;
begin
  perform public.ims_require_write('purchasing', 'deleted');     -- ②-b

  select * into v_al from public.po_charge_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — nothing was deleted', p_alloc_id; end if;
  select * into v_chg from public.po_charge where id = v_al.po_charge_id;
  if v_chg.status <> 'draft' then
    raise exception 'Charge % is % — allocations can be edited only while draft — nothing was deleted', v_chg.charge_number, v_chg.status;
  end if;
  select po_number into v_pon from public.po where id = v_al.po_id;
  delete from public.po_charge_alloc where id = p_alloc_id;
  get diagnostics v_n = row_count;                              -- ②-b
  if v_n = 0 then raise exception 'Allocation line % on charge % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_alloc_id, v_chg.charge_number; end if;
  select * into v_m from public.po_charge_money where id = v_chg.id;
  return jsonb_build_object('deleted', true, 'alloc_id', v_al.id, 'charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'po_number', v_pon,
                            'amount_removed', v_al.amount, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated);
end;
$$;

-- ═══ 5) po_charge_alloc_spread — 첫머리 권한 + 루프 update 0행 검사 ═══
create or replace function public.po_charge_alloc_spread(p_charge_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_n    int;                                                   -- ②-b: row_count
  v_chg    public.po_charge%rowtype;
  v_ids    uuid[];
  v_m      record;
  v_out    jsonb := '[]'::jsonb;
  v_base   numeric := 0;
  v_warn   text[] := '{}';
  v_before numeric;
  v_alid   uuid;
  r        record;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_chg from public.po_charge where id = p_charge_id;
  if not found then raise exception 'Charge % not found — nothing was saved', p_charge_id; end if;
  if v_chg.status <> 'draft' then
    raise exception 'Charge % is % — allocations can be edited only while draft — nothing was saved', v_chg.charge_number, v_chg.status;
  end if;
  select array_agg(po_id) into v_ids from public.po_charge_alloc where po_charge_id = p_charge_id;
  if v_ids is null then
    raise exception 'Charge % has no allocation lines — add purchase orders first — nothing was saved', v_chg.charge_number;
  end if;

  for r in select * from public.po_charge_alloc_propose(v_chg.total_amount, v_ids) loop
    select id, amount into v_alid, v_before from public.po_charge_alloc where po_charge_id = p_charge_id and po_id = r.po_id;
    update public.po_charge_alloc set amount = r.amount where id = v_alid;
    get diagnostics v_n = row_count;                            -- ②-b
    if v_n = 0 then raise exception 'Allocation line for PO % on charge % was not saved — it may have been removed or changed by someone else just now — nothing was saved', r.po_number, v_chg.charge_number; end if;
    v_base := v_base + r.base_amount;
    v_out := v_out || jsonb_build_object('alloc_id', v_alid, 'po_id', r.po_id, 'po_number', r.po_number, 'base_amount', r.base_amount, 'amount_before', v_before, 'amount', r.amount);
  end loop;
  if v_base = 0 then v_warn := array_append(v_warn, 'no_base_amount'); end if;

  select * into v_m from public.po_charge_money where id = p_charge_id;
  return jsonb_build_object('charge_id', v_chg.id, 'charge_number', v_chg.charge_number, 'total_amount', v_chg.total_amount,
                            'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated, 'allocs', v_out, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 6) po_charge_confirm — 첫머리 권한 + update 2곳 0행 검사 ═══
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
    update public.po_charge set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
  else
    if v_chg.status <> 'confirmed' then raise exception 'Charge % is % — only a confirmed document can be reopened — nothing was saved', v_chg.charge_number, v_chg.status; end if;
    -- ⭐ po_invoice_confirm Reopen · po_doc_cancel 과 같은 선 — 결제 참조번호·금액을 이름으로
    if v_m.paid > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_charge_id = p_charge_id;
      raise exception 'Charge % has payments applied (%) — cannot reopen while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
    end if;
    update public.po_charge set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_charge_id returning * into v_chg;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
  end if;

  return jsonb_build_object(
    'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status, 'confirmed_at', v_chg.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'paid', v_m.paid, 'unpaid', v_m.unpaid, 'alloc_sum', v_m.alloc_sum, 'unallocated', v_m.unallocated),
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 7) po_payment_create — 첫머리 권한 (insert 만) ═══
create or replace function public.po_payment_create(
  p_supplier_id    uuid,                        -- 화면의 축(후보 문서·통화가 여기서 따라온다) · ⭐ 선택(이견 1·ⓑ) — 대상 문서의 공급처와 다르면 경고 mixed_supplier · 표에 칸이 없다(결제는 공급처를 안 담는다)
  p_paid_on        date,                        -- 안 주면 오늘
  p_amount         numeric,                     -- 실제로 낸 돈(결제 통화) · > 0(CHECK)
  p_currency_id    uuid,                        -- ⭐ 필수 · 결제 통화 = 대상 문서 전부의 통화(②)
  p_discount_taken numeric default 0,           -- ⑥ 사람이 선언 · ≥ 0(CHECK)
  p_account_id     uuid    default null,        -- 지정만(③) · 통화 검사 없음 · 안 고르면 경고
  p_reference      text    default null,
  p_note           text    default null,
  p_targets        jsonb   default null,        -- [ {kind, id, amount, note}, … ] · amount 없으면 미지급 전액 제안
  p_commit         boolean default false
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff      uuid;
  v_sup_id     uuid;
  v_sup_name   text;
  v_cur_code   text;
  v_acc_code   text;  v_acc_name text;
  v_pay_id     uuid;
  v_allocs     jsonb := '[]'::jsonb;
  v_sum        numeric := 0;
  v_gap        numeric;
  v_disc       numeric;
  v_warn       text[] := '{}';
  v_sups       uuid[] := '{}';
  v_seen       text[] := '{}';
  v_key        text;
  v_kind       text;  v_tid uuid;  v_amt numeric;  v_note text;
  t            record;
  r            jsonb;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  if p_amount is null then raise exception 'Amount is required — nothing was saved'; end if;
  if p_amount <= 0 then raise exception 'Amount must be above 0 (got %) — nothing was saved', p_amount; end if;
  if p_currency_id is null then raise exception 'Currency is required — nothing was saved'; end if;
  select c.code into v_cur_code from public.ref_currency c where c.id = p_currency_id;
  if v_cur_code is null then raise exception 'Currency % not found — nothing was saved', p_currency_id; end if;
  v_disc := coalesce(p_discount_taken, 0);
  if v_disc < 0 then raise exception 'Discount taken cannot be negative (got %) — nothing was saved', v_disc; end if;
  v_sup_id := p_supplier_id;
  if v_sup_id is not null then
    select s.name into v_sup_name from public.supplier s where s.id = v_sup_id;
    if v_sup_name is null then raise exception 'Supplier % not found — nothing was saved', v_sup_id; end if;
  end if;
  if p_account_id is not null then
    select a.code, a.name into v_acc_code, v_acc_name from public.ref_account a where a.id = p_account_id;
    if v_acc_code is null then raise exception 'Account % not found — nothing was saved', p_account_id; end if;
  else
    v_warn := array_append(v_warn, 'account_missing');
  end if;
  if p_targets is not null and jsonb_typeof(p_targets) <> 'array' then
    raise exception 'p_targets must be a JSON array [{kind, id, amount, note}] — nothing was saved';
  end if;

  -- ── 대상 문서 검사(한 곳 · po_payment_target_check) — 미리 보기도 같은 판정 ──
  for r in select * from jsonb_array_elements(coalesce(p_targets, '[]'::jsonb)) loop
    v_kind := r->>'kind';
    v_tid  := nullif(r->>'id', '')::uuid;
    v_amt  := nullif(r->>'amount', '')::numeric;
    v_note := r->>'note';
    if v_tid is null then raise exception 'p_targets[] needs an id on every element — nothing was saved'; end if;
    v_key := coalesce(v_kind, '?') || ':' || v_tid::text;
    if v_key = any(v_seen) then raise exception 'Document % appears twice in p_targets — nothing was saved', v_tid; end if;
    v_seen := array_append(v_seen, v_key);
    if v_amt is not null and v_amt <= 0 then
      raise exception 'p_targets[] amount must be above 0 or omitted (got % for %) — nothing was saved', v_amt, v_tid;
    end if;
    select * into t from public.po_payment_target_check(v_kind, v_tid, v_amt, p_currency_id, null);
    if v_amt is null then v_amt := t.doc_unpaid; end if;                          -- 미지급 전액 제안
    if v_amt <= 0 then
      raise exception '% % has nothing unpaid (%) — nothing to allocate — nothing was saved', case v_kind when 'invoice' then 'Invoice' else 'Charge' end, t.target_number, t.doc_unpaid;
    end if;
    v_sum := v_sum + v_amt;
    if not (t.supplier_id = any(v_sups)) then v_sups := array_append(v_sups, t.supplier_id); end if;
    v_allocs := v_allocs || jsonb_build_object('kind', v_kind, 'id', v_tid, 'number', t.target_number, 'supplier_name', t.supplier_name, 'currency_code', t.currency_code,
                                               'doc_total', t.doc_total, 'doc_paid_before', t.doc_paid, 'doc_unpaid_before', t.doc_unpaid, 'amount', v_amt, 'note', v_note, 'inserted', p_commit);
  end loop;

  -- 공급처 — 강제하지 않는다(이견 1 · ⓑ) · 둘 이상이거나 p_supplier_id 와 다르면 경고
  if cardinality(v_sups) > 1 or (v_sup_id is not null and cardinality(v_sups) = 1 and v_sups[1] <> v_sup_id) then
    v_warn := array_append(v_warn, 'mixed_supplier');
  end if;
  if v_sup_id is null and cardinality(v_sups) = 1 then
    v_sup_id := v_sups[1];
    select s.name into v_sup_name from public.supplier s where s.id = v_sup_id;
  end if;

  -- ⑤ 검산 — Σ충당 = amount + discount_taken · 거부(양쪽 다 우리가 넣는 숫자)
  v_gap := round(p_amount + v_disc - v_sum, 2);
  if v_gap <> 0 then
    raise exception 'Allocations % do not match amount % + discount % = % (gap %) — fix the amounts or the discount first — nothing was saved',
      v_sum, p_amount, v_disc, p_amount + v_disc, v_gap;
  end if;

  -- ── commit: 머리 한 행 + 충당 줄 ──
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference, discount_taken, paid_by, note)
    values (coalesce(p_paid_on, current_date), p_amount, p_currency_id, p_account_id, p_reference, v_disc, v_staff, p_note)
    returning id into v_pay_id;
    for r in select * from jsonb_array_elements(v_allocs) loop
      insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note)
      values (v_pay_id,
              case when r->>'kind' = 'invoice' then (r->>'id')::uuid end,
              case when r->>'kind' = 'charge'  then (r->>'id')::uuid end,
              (r->>'amount')::numeric, r->>'note');
    end loop;
  end if;

  return jsonb_build_object(
    'committed', p_commit, 'payment_id', v_pay_id, 'paid_on', coalesce(p_paid_on, current_date),
    'amount', p_amount, 'discount_taken', v_disc, 'currency_id', p_currency_id, 'currency_code', v_cur_code,
    'supplier_id', v_sup_id, 'supplier_name', v_sup_name,
    'account_code', v_acc_code, 'account_name', v_acc_name,
    'alloc_sum', v_sum, 'gap', v_gap, 'allocs', v_allocs, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 8) po_payment_alloc_set — 첫머리 권한 + update 갈래 0행 검사 ═══
create or replace function public.po_payment_alloc_set(p_payment_id uuid, p_kind text, p_target_id uuid, p_amount numeric, p_note text default null) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_n    int;                                                   -- ②-b: row_count
  v_pay    public.po_payment%rowtype;
  v_al     public.po_payment_alloc%rowtype;
  t        record;
  v_id     uuid;
  v_before numeric;
  v_sum    numeric;
  v_warn   text[] := '{}';
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_pay from public.po_payment where id = p_payment_id;
  if not found then raise exception 'Payment % not found — nothing was saved', p_payment_id; end if;
  if p_amount is null or p_amount <= 0 then
    raise exception 'p_amount must be above 0 (got %) — to remove the line use po_payment_alloc_delete — nothing was saved', p_amount;
  end if;
  if p_kind not in ('invoice', 'charge') then raise exception 'p_kind must be invoice or charge — nothing was saved'; end if;

  -- 이미 있는 줄인가 — unique (po_payment_id, po_invoice_id) · (po_payment_id, po_charge_id) 가 축(null 은 서로 다르게 취급되어 종류가 다르면 안 겹친다)
  select * into v_al from public.po_payment_alloc a
  where a.po_payment_id = p_payment_id
    and ((p_kind = 'invoice' and a.po_invoice_id = p_target_id) or (p_kind = 'charge' and a.po_charge_id = p_target_id));
  if found then v_id := v_al.id; v_before := v_al.amount; end if;

  -- 만들기와 같은 검사 — 고치는 줄의 지금 금액은 미지급에 되돌려 놓고 본다
  select * into t from public.po_payment_target_check(p_kind, p_target_id, p_amount, v_pay.currency_id, v_id);

  if v_id is not null then
    update public.po_payment_alloc set amount = p_amount, note = coalesce(p_note, note) where id = v_id;
    get diagnostics v_n = row_count;                            -- ②-b
    if v_n = 0 then raise exception 'Allocation line % on payment % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_id, coalesce(v_pay.reference, p_payment_id::text); end if;
  else
    insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note)
    values (p_payment_id, case when p_kind = 'invoice' then p_target_id end, case when p_kind = 'charge' then p_target_id end, p_amount, p_note)
    returning id into v_id;
  end if;

  select coalesce(sum(amount), 0) into v_sum from public.po_payment_alloc where po_payment_id = p_payment_id;
  if exists (select 1 from public.po_payment_alloc a
             left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id
             where a.po_payment_id = p_payment_id and coalesce(i.supplier_id, c.supplier_id) <> t.supplier_id) then
    v_warn := array_append(v_warn, 'mixed_supplier');
  end if;
  return jsonb_build_object('alloc_id', v_id, 'payment_id', p_payment_id, 'kind', p_kind, 'target_id', p_target_id, 'target_number', t.target_number,
                            'amount_before', v_before, 'amount', p_amount,
                            'alloc_sum', v_sum, 'gap', round(v_pay.amount + v_pay.discount_taken - v_sum, 2), 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 9) po_payment_alloc_delete — 첫머리 권한 + delete 0행 검사 ═══
create or replace function public.po_payment_alloc_delete(p_alloc_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_n    int;                                                   -- ②-b: row_count
  v_al   public.po_payment_alloc%rowtype;
  v_pay  public.po_payment%rowtype;
  v_num  text;
  v_sum  numeric;
begin
  perform public.ims_require_write('purchasing', 'deleted');     -- ②-b

  select * into v_al from public.po_payment_alloc where id = p_alloc_id;
  if not found then raise exception 'Allocation line % not found — nothing was deleted', p_alloc_id; end if;
  select * into v_pay from public.po_payment where id = v_al.po_payment_id;
  select coalesce(i.invoice_number, c.charge_number) into v_num
  from public.po_payment_alloc a left join public.po_invoice i on i.id = a.po_invoice_id left join public.po_charge c on c.id = a.po_charge_id
  where a.id = p_alloc_id;
  delete from public.po_payment_alloc where id = p_alloc_id;
  get diagnostics v_n = row_count;                              -- ②-b
  if v_n = 0 then raise exception 'Allocation line % on payment % was not deleted — it may have been removed or changed by someone else just now — nothing was deleted', p_alloc_id, coalesce(v_pay.reference, v_pay.id::text); end if;
  select coalesce(sum(amount), 0) into v_sum from public.po_payment_alloc where po_payment_id = v_pay.id;
  return jsonb_build_object('deleted', true, 'alloc_id', v_al.id, 'payment_id', v_pay.id,
                            'kind', case when v_al.po_charge_id is not null then 'charge' else 'invoice' end, 'target_number', v_num,
                            'amount_removed', v_al.amount, 'alloc_sum', v_sum, 'gap', round(v_pay.amount + v_pay.discount_taken - v_sum, 2));
end;
$$;

-- ═══ 검증 (Caleb · psql heredoc · 회신 §5) ═══
-- select proname, prosecdef from pg_proc where proname in ('po_charge_create','po_charge_alloc_add','po_charge_alloc_update','po_charge_alloc_delete','po_charge_alloc_spread','po_charge_confirm','po_payment_create','po_payment_alloc_set','po_payment_alloc_delete') order by 1;
--   → 9행 · 전부 prosecdef=false · 각 이름 1개
-- select proname, count(*) from pg_proc where proname like 'po\_%' group by 1 having count(*) > 1;   → 0행
