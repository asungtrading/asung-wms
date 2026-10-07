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
-- 20261007171939_fr_1_freight_discount.sql — fr-1 (2026-10-07 · 회사 PC)
--   Caleb 「freight에 디스카운트를 적용할 수 있나? 실제 100불이 나왔고, 50% 운임 디스카운트를 줬고, 그래서 손님의 실제 부담은 50불이다」 · 「운임 매출과 운임 할인이 따로 보여지게 하면 좋겠어. B」
--   판정 352 운임 줄과 할인 줄을 따로(인보이스 Freight 100.00 / Freight discount −50.00 · fr-2) · 353 저장 = so_charge 에 할인 칸(amount ≥ 0 CHECK · 음수 거부 셋 그대로) · 354 세금 = 줄마다(운임 줄 세금 − 할인 줄 세금 · 각각 so_tax_amount) · 356 입력 = % 또는 금액 중 하나 · 100% = 무료 배송 · 금액 > 운임 막기 · 357 다른 할인과 무관(오더 할인 기준은 제품 줄만) · 358 할인 줄 계정 _6_(fr-2)
--   이 차수 = 오더 안: 칸 둘 + CHECK 셋 · 식 한 곳(so_charge_discount · so_charge_discount_check) · so_charge_set(인자 둘 · drop + create) · so_finalize(charges[] 열쇠 discount_pct · discount_amount · 경고 charge_added_beside_existing) · so_tax_preview(할인 줄 · 할인 세금 · 새 열쇠 · 기존 열쇠 뜻 그대로) · so_detail · so_totals_many(열 하나 · drop + create) · so_proforma
--   so_invoice_issue · 크레딧은 무접촉(fr-2 · fr-3) — 그 사이 할인이 걸린 운임으로 인보이스를 내지 못하게 so_invoice_order BEFORE INSERT 가드(fr-2 가 지운다)
--   재발행 여섯 = 마지막 정의 바이트 복사 + 더한 줄 · 바꾼 줄(줄 끝 -- fr-1) · 검증 supabase/tests/fr-1-verify.sql(무변 · 같음 · 판정 354 수 · 356 막기 · finalize 미리 보기 · 357-4 · 가드)
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록이 실물을 세어 어긋나면 전부 되돌린다

-- ═══ 1) so_charge 할인 칸 둘 + CHECK 셋(판정 353 · 356) ═══
alter table public.so_charge add column if not exists discount_pct numeric, add column if not exists discount_amount numeric;
alter table public.so_charge
  add constraint so_charge_discount_pair_ck   check (discount_pct is null or discount_amount is null),
  add constraint so_charge_discount_pct_ck    check (discount_pct is null or (discount_pct > 0 and discount_pct <= 100)),
  add constraint so_charge_discount_amount_ck check (discount_amount is null or (discount_amount > 0 and discount_amount <= amount));
comment on column public.so_charge.discount_pct    is '운임 할인 %(fr-1 판정 353 · 356 · 2026-10-07) — 0 < x ≤ 100 · 100 = 무료 배송 · 금액(discount_amount)과 둘 중 하나(so_charge_discount_pair_ck) · 할인액 = round(amount × pct / 100, 2) — 식은 so_charge_discount 한 곳 · 인보이스는 운임 줄과 할인 줄 두 줄로 펼친다(판정 352 · fr-2 · 계정 _6_ · 358)';
comment on column public.so_charge.discount_amount is '운임 할인 금액(fr-1 판정 353 · 356) — > 0 · ≤ amount(so_charge_discount_amount_ck · 운임을 줄여 할인이 더 커지면 so_charge_set · so_finalize 가 먼저 막는다) · % 와 둘 중 하나 · 세금은 할인 줄마다 따로 반올림(판정 354)';
comment on constraint so_charge_discount_pair_ck   on public.so_charge is 'fr-1 판정 356 — 한 줄에 % 또는 금액 하나만';
comment on constraint so_charge_discount_pct_ck    on public.so_charge is 'fr-1 판정 356 — 0 < % ≤ 100';
comment on constraint so_charge_discount_amount_ck on public.so_charge is 'fr-1 판정 356 — 0 < 금액 ≤ 운임';

-- ═══ 2) 식 한 곳 — 할인액 · 검사(so_charge_set · so_finalize · so_tax_preview · so_detail · so_totals_many 가 부른다) ═══
create function public.so_charge_discount(p_amount numeric, p_pct numeric, p_amt numeric) returns numeric
  language sql immutable
  set search_path = public, pg_temp
as $$
  select case when p_amt is not null then p_amt when p_pct is not null then round(coalesce(p_amount, 0) * p_pct / 100, 2) else 0 end;
$$;
revoke all on function public.so_charge_discount(numeric, numeric, numeric) from public, anon;
grant execute on function public.so_charge_discount(numeric, numeric, numeric) to authenticated;
comment on function public.so_charge_discount(numeric, numeric, numeric) is '⭐ 운임 할인액 식 한 곳(fr-1 판정 353 · 354 · 356) — 금액형이면 그 금액 · %형이면 round(운임 × % / 100, 2) · 둘 다 없으면 0 · 순 운임 = amount − 이 값 · 세금은 할인액에 so_tax_amount 를 따로(줄마다 반올림 · 판정 354) · 부르는 곳 so_charge_set · so_finalize · so_tax_preview · so_detail · so_totals_many · authenticated 허용(invoker 읽기 창구 so_detail · so_tax_preview 가 부른다)';
create function public.so_charge_discount_check(p_amount numeric, p_pct numeric, p_amt numeric) returns void
  language plpgsql immutable
  set search_path = public, pg_temp
as $$
begin
  if p_pct is not null and p_amt is not null then raise exception 'Give a discount %% or an amount, not both — nothing was saved'; end if;
  if p_pct is not null and not (p_pct > 0 and p_pct <= 100) then raise exception 'Discount %% must be above 0 and at most 100 — nothing was saved'; end if;
  if p_amt is not null and not (p_amt > 0) then raise exception 'The discount amount must be above 0 — nothing was saved'; end if;
  if p_amt is not null and p_amt > coalesce(p_amount, 0) then raise exception 'The discount cannot be more than the charge — nothing was saved'; end if;
end;
$$;
revoke all on function public.so_charge_discount_check(numeric, numeric, numeric) from public, anon, authenticated;
comment on function public.so_charge_discount_check(numeric, numeric, numeric) is '운임 할인 검사 한 곳(fr-1 판정 356) — 둘 다 · % 범위 · 금액 > 0 · 금액 ≤ 운임 · 문장은 화면 낱말(Discount % · amount · charge) · so_charge_set · so_finalize 가 부른다(so_finalize 는 「Order N: charge X: 」를 앞에 붙인다) · 속 함수(definer 창구 안에서만)';

-- ═══ 3) so_charge_set 재발행 — 마지막 정의 20260924175014 · 인자 둘(시그니처 바뀜 → drop + create + 권한 · comment) · 할인은 전체 모양(둘 다 null = 할인 없음) ═══
drop function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid);
create function public.so_charge_set(
  p_so_id       uuid,
  p_name        text,
  p_amount      numeric,
  p_charge_id   uuid default null,
  p_description text default null,
  p_tax_rule    text default null,
  p_account_id  uuid default null,
  p_discount_pct    numeric default null,                       -- fr-1 판정 353 · 356: 운임 할인 %(0 < x ≤ 100) — 금액과 둘 중 하나 · 둘 다 null = 할인 없음(고치기도 전체 모양)
  p_discount_amount numeric default null                        -- fr-1 판정 356: 운임 할인 금액(> 0 · ≤ 운임)
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_so     public.so%rowtype;
  v_name   text;
  v_acct   public.ref_account%rowtype;
  v_ch     public.so_charge%rowtype;
  v_next   int;
  v_warn   text[] := '{}';
  v_n      int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  v_name := nullif(trim(p_name), '');
  if v_name is null then
    raise exception 'A charge needs a name — nothing was saved';
  end if;
  if p_amount is null then
    raise exception 'A charge needs an amount — nothing was saved';
  end if;
  if p_amount < 0 then                                          -- ①c 판정(Caleb 2026-09-23) — 돌려줄 돈은 크레딧 노트(8-g) · CHECK so_charge_amount_ck 가 마지막 문
    raise exception 'A charge cannot be negative — use a credit note — nothing was saved';
  end if;
  perform public.so_charge_discount_check(p_amount, p_discount_pct, p_discount_amount);                              -- fr-1 판정 356: 한 곳의 검사(둘 다 · 0 · 100 초과 · 운임보다 큰 금액)
  if nullif(trim(p_tax_rule), '') is not null and nullif(trim(p_tax_rule), '') is distinct from v_so.tax_rule then   -- 세금 ② · 판정 8·9 — 운임 줄만 따로 바꾸는 길은 없다(조용히 무시하지 않고 거부)
    raise exception 'Freight and charges follow the order tax rule (%) — change it on the order, not on the charge — nothing was saved', coalesce(v_so.tax_rule, 'none yet');
  end if;

  if p_account_id is not null then
    select * into v_acct from public.ref_account where id = p_account_id;
    if not found then
      raise exception 'Account not found — nothing was saved';
    end if;
  end if;

  if p_charge_id is null then
    if p_account_id is null then
      select * into v_acct from public.ref_account where code = '_99_';          -- 기본 Freight Sales · 없으면 비우고 알린다(짐작 값을 박지 않는다)
      if not found then v_warn := array_append(v_warn, 'charge_account_unset'); end if;
    end if;
    select coalesce(max(line_no), 0) + 1 into v_next from public.so_charge where so_id = p_so_id;
    insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by, discount_pct, discount_amount)
    values (p_so_id, v_next, v_name, nullif(trim(p_description), ''), p_amount, v_so.tax_rule, v_acct.id, v_acct.code, v_staff, p_discount_pct, p_discount_amount)   -- 세금 ②: 오더 규칙을 기록 · fr-1 할인 칸 둘
    returning * into v_ch;
    return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'charge', to_jsonb(v_ch) || jsonb_build_object('discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount)), 'warnings', to_jsonb(v_warn));   -- fr-1: 할인액 · 순 운임
  end if;

  select * into v_ch from public.so_charge where id = p_charge_id and so_id = p_so_id;
  if not found then
    raise exception 'Charge not found on order % — nothing was saved', v_so.so_number;
  end if;
  update public.so_charge c set
    name         = v_name,
    description  = nullif(trim(p_description), ''),
    amount       = p_amount,
    discount_pct = p_discount_pct,  discount_amount = p_discount_amount,                               -- fr-1 판정 353: 고치기는 전체 모양(이름 · 설명 · 금액처럼) — 둘 다 null 이면 할인을 지운다
    tax_rule     = v_so.tax_rule,                             -- 세금 ②: 오더 규칙을 기록
    account_id   = case when p_account_id is not null then v_acct.id   else c.account_id end,
    account_code = case when p_account_id is not null then v_acct.code else c.account_code end,
    updated_by   = v_staff
  where c.id = p_charge_id
  returning * into v_ch;
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Charge was not saved — it may have been removed by someone else just now — nothing was saved';
  end if;
  return jsonb_build_object('action', 'updated', 'so_number', v_so.so_number, 'charge', to_jsonb(v_ch) || jsonb_build_object('discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount)), 'warnings', to_jsonb(v_warn));   -- fr-1
end;
$$;
revoke all on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric) from public, anon;
grant execute on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric) to authenticated;
comment on function public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric) is
  '⭐ SO 초안 운임·서비스 줄(①b·①c · 세금 ② · ⭐ fr-1 판정 353 · 356 재발행 2026-10-07) — definer · 첫 줄 ims_require_write(sales) · 초안만 · p_charge_id 없으면 새 줄(계정 기본 _99_ Freight Sales · 없으면 경고 charge_account_unset) · 있으면 고치기(이름 · 설명 · 금액 · 할인은 전체 모양 — 보낸 값이 최종 · 둘 다 null 이면 할인 없음) · p_discount_pct(0 < x ≤ 100 · 100 = 무료 배송) 또는 p_discount_amount(> 0 · ≤ 운임) 하나만 · 막기 문장 so_charge_discount_check · 음수 운임 거부(크레딧 노트) · 세금 규칙은 오더 것(따로 못 바꾼다 · 판정 8 · 9) · 반환 charge(to_jsonb + discount · net)';

-- ═══ 4) so_finalize 재발행 — 마지막 정의 20261006000805:73 · charges[] 열쇠 discount_pct · discount_amount(없으면 그대로 · "" 지움) · 검사 한 곳 · 미리 보기에 discount · net · 경고 charge_added_beside_existing ═══
create or replace function public.so_finalize(p_orders jsonb, p_commit boolean default true, p_shipped_on date default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_reasons  constant text[] := array['customer_removed', 'not_wanted', 'other'];
  v_staff    uuid;
  v_on       date;
  v_n        int;  v_cnt int;
  v_bad      text;
  e          jsonb;  x jsonb;
  v_so       public.so%rowtype;
  v_l        public.so_line%rowtype;
  v_c        public.customer%rowtype;
  v_acct     public.ref_account%rowtype;
  v_ch       public.so_charge%rowtype;
  q          record;
  v_qty      numeric;  v_remaining numeric;  v_new_unit numeric;
  v_reason   text;  v_key text;  k text;
  v_next     int;
  v_removed  jsonb;  v_repriced jsonb;  v_charges jsonb;  v_ship jsonb;  v_iss jsonb;
  v_surcharges jsonb;  v_spct numeric;  v_samt numeric;  v_slbl text;                 -- surcharge-2a(판정 230)
  v_orders   jsonb := '[]'::jsonb;
  v_groups   jsonb := '{}'::jsonb;
  v_invoices jsonb := '[]'::jsonb;
  v_ids      uuid[];
  v_warn     text[] := '{}';
  v_tw       text[];
  v_dp       numeric;  v_da numeric;                                                   -- fr-1 판정 353 · 356: 운임 할인(열쇠 없으면 그대로 · '' 이면 지움)
  v_rm       jsonb;  v_pk jsonb;  v_pb jsonb;  v_put_back jsonb := '[]'::jsonb;  v_ord int;  v_cut numeric;  i int;  cb record;  kk record;   -- asm-2b2(판정 246 · 묶음 3 · 4): 콤보 단위 removed(펼친 목록 v_rm) · 구성품 픽을 통째 콤보로 줄이기(v_pk · put_back) — 별칭은 cp · p2 · z · t2(declare 변수와 다르게)
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — 판정 8: 마무리는 오더 담당(sales)부터 · 역할 문 없음(R5 의 예외)
  v_staff := public.so_current_staff();
  v_on := coalesce(p_shipped_on, public.ims_today());
  if v_on > public.ims_today() then raise exception 'Ship date % is in the future — nothing was saved', v_on; end if;
  if p_orders is null or jsonb_typeof(p_orders) <> 'array' or jsonb_array_length(p_orders) = 0 then
    raise exception 'p_orders must be a JSON array of orders — nothing was saved';
  end if;
  if exists (select 1 from jsonb_array_elements(p_orders) t where jsonb_typeof(t) <> 'object' or nullif(t->>'so_id', '') is null) then
    raise exception 'Every order needs a so_id — nothing was saved';
  end if;
  select count(*), count(distinct t->>'so_id') into v_cnt, v_n from jsonb_array_elements(p_orders) t;
  if v_n <> v_cnt then raise exception 'The same order is listed twice — nothing was saved'; end if;
  -- ⑤-2b(판정 16 · ⬜7): picks 가 없으면 WMS 인계(wms_so_handoff)의 picks 를 쓴다(있으면 그대로 — 오피스가 고칠 길)
  select jsonb_agg(case when t.e ? 'picks' then t.e else t.e || jsonb_build_object('picks', (public.wms_so_handoff((t.e->>'so_id')::uuid))->'picks') end order by t.ord) into p_orders from jsonb_array_elements(p_orders) with ordinality t(e, ord);

  -- ① 검사 — 오더마다(잠금) · 하나라도 막히면 전체 거부 · 오더 번호로 말한다
  v_ord := -1;
  for e in select t from jsonb_array_elements(p_orders) t loop
    v_ord := v_ord + 1;                                                                 -- asm-2b2: 줄인 picks · 펼친 removed 를 이 자리에 되적는다(②~⑤ 가 읽는다)
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid for update;
    if not found then raise exception 'Order % not found — nothing was saved', e->>'so_id'; end if;
    if v_so.status <> 'packed' then
      raise exception 'Order % is % — only a packed order (warehouse work finished) can be finalized here — nothing was saved', v_so.so_number, v_so.status;
    end if;
    if v_so.bill_to_customer_id is null then raise exception 'Order % has no bill-to customer — nothing was saved', v_so.so_number; end if;
    -- 뺀 몫(판정 5) — 모양 · 줄 · 수량 · 사유 · 중복
    if e ? 'removed' and jsonb_typeof(e->'removed') not in ('array', 'null') then
      raise exception 'Order %: removed must be an array of {line_id, qty, reason, note} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: removed line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      if v_l.combo_line_id is not null then                                                                                                    -- asm-2b2(묶음 3): 뺀 몫은 콤보 줄에만 · 구성품은 따라간다
        raise exception 'Order %: line % is a component of combo % (line %) — remove from the combo line instead — nothing was saved', v_so.so_number, v_l.line_no,
          (select p2.sku from public.so_line p2 where p2.id = v_l.combo_line_id), (select p2.line_no from public.so_line p2 where p2.id = v_l.combo_line_id);
      end if;
      if v_l.qty_removed > 0 then raise exception 'Order % line % already has a removed quantity — nothing was saved', v_so.so_number, v_l.line_no; end if;
      v_qty := case when (x->>'qty') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (x->>'qty')::numeric else null end;
      if v_qty is null or v_qty <= 0 then raise exception 'Order % line %: removed qty must be a positive number — nothing was saved', v_so.so_number, v_l.line_no; end if;
      if v_qty > v_l.qty_ordered then raise exception 'Order % line %: cannot remove % — only % ordered — nothing was saved', v_so.so_number, v_l.line_no, v_qty, v_l.qty_ordered; end if;
      v_reason := nullif(trim(x->>'reason'), '');
      if v_reason is null or v_reason <> all (c_reasons) then
        raise exception 'Order % line %: removed reason must be one of customer_removed, not_wanted, other — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
      if v_reason = 'other' and nullif(trim(x->>'note'), '') is null then
        raise exception 'Order % line %: reason other needs a note — nothing was saved', v_so.so_number, v_l.line_no;
      end if;
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line is removed twice — nothing was saved', v_so.so_number;
    end if;
    -- asm-2b2(묶음 3): 뺀 몫을 펼친다 — 콤보 줄 removed n ⇒ 구성품 줄 removed = n × combo_qty(같은 사유 · 메모 · derived true) · 아래 검사 · ③ · ④ 가 전부 이 목록(v_rm)을 본다
    select coalesce(jsonb_agg(jsonb_build_object('line_id', z.line_id, 'qty', z.qty, 'reason', z.reason, 'note', z.note, 'derived', z.derived)), '[]'::jsonb) into v_rm
    from (select (t2->>'line_id')::uuid as line_id, (t2->>'qty')::numeric as qty, nullif(trim(t2->>'reason'), '') as reason, nullif(trim(t2->>'note'), '') as note, false as derived
            from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t2
          union all
          select cp.id, (t2->>'qty')::numeric * cp.combo_qty, nullif(trim(t2->>'reason'), ''), nullif(trim(t2->>'note'), ''), true
            from jsonb_array_elements(coalesce(nullif(e->'removed', 'null'::jsonb), '[]'::jsonb)) t2 join public.so_line cp on cp.combo_line_id = (t2->>'line_id')::uuid) z;
    -- 판정 9 — 모든 줄을 다 뺐다 → 거부 + 길
    if not exists (select 1 from public.so_line l
                   left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
                   where l.so_id = v_so.id and l.qty_ordered - coalesce(rm.q, 0) > 0) then
      raise exception 'Order % — every line was removed, there is nothing to ship: roll the order back in WMS, then cancel it (so_unconfirm / so_cancel) — nothing was saved', v_so.so_number;
    end if;
    -- 픽 — 모양 · 줄 · 수량 · 목표 초과(칸은 실행 때 so_ship 이 본다)
    if e->'picks' is null or jsonb_typeof(e->'picks') <> 'array' or jsonb_array_length(e->'picks') = 0 then
      raise exception 'Order %: picks must be a JSON array of {line_id, bin, qty} — nothing was saved', v_so.so_number;
    end if;
    if exists (select 1 from jsonb_array_elements(e->'picks') t where nullif(t->>'line_id', '') is null or (t->>'qty') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$' or (t->>'qty')::numeric <= 0) then
      raise exception 'Order %: every pick needs a line_id and a positive qty — nothing was saved', v_so.so_number;
    end if;
    select string_agg(distinct t->>'line_id', ', ') into v_bad from jsonb_array_elements(e->'picks') t
    where not exists (select 1 from public.so_line l where l.id = (t->>'line_id')::uuid and l.so_id = v_so.id);
    if v_bad is not null then raise exception 'Order %: pick line % is not on this order — nothing was saved', v_so.so_number, v_bad; end if;
    select string_agg(distinct l.line_no::text, ', ') into v_bad from jsonb_array_elements(e->'picks') t join public.so_line l on l.id = (t->>'line_id')::uuid
    where l.so_id = v_so.id and exists (select 1 from public.so_line cp where cp.combo_line_id = l.id);                                           -- asm-2b2: 콤보 줄에는 픽이 없다(so_ship 과 같은 문장 · 미리 보기에서도 걸린다)
    if v_bad is not null then raise exception 'Order %: pick line % is a combo line — pick its component lines instead — nothing was saved', v_so.so_number, v_bad; end if;
    -- asm-2b2(판정 246 · 묶음 4): 콤보 줄마다 whole = least(남은 콤보 수, min(구성품 픽 ÷ combo_qty)) · 어느 구성품 픽이 whole × combo_qty 를 넘으면 넘는 몫을 그 줄 picks 의 마지막 칸부터 덜어낸다(wms_so_handoff 의 cut 모양)
    --   덜어낸 것은 put_back(SKU · 칸 · 수량 — 실물만 제자리에 · 장부는 출고 때 빠지므로 닿지 않는다) · 줄인 picks 를 so_ship 에 넘긴다(so_ship 의 반쪽 거부는 안전망으로 그대로) · 보통 줄의 과다 픽은 아래에서 여전히 거부
    v_pk := e->'picks';  v_pb := '[]'::jsonb;
    for cb in
      select p2.id, p2.line_no, p2.sku,
             least(p2.qty_ordered - coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_rm) t2 where (t2->>'line_id')::uuid = p2.id), 0),
                   (select min(floor(coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_pk) t2 where (t2->>'line_id')::uuid = cp.id), 0) / cp.combo_qty)) from public.so_line cp where cp.combo_line_id = p2.id)) as whole
      from public.so_line p2 where p2.so_id = v_so.id and exists (select 1 from public.so_line cp where cp.combo_line_id = p2.id) order by p2.line_no
    loop
      for kk in select cp.id, cp.sku, cp.combo_qty from public.so_line cp where cp.combo_line_id = cb.id order by cp.line_no loop
        v_cut := coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(v_pk) t2 where (t2->>'line_id')::uuid = kk.id), 0) - greatest(cb.whole, 0) * kk.combo_qty;
        i := jsonb_array_length(v_pk) - 1;
        while v_cut > 0 and i >= 0 loop
          if (v_pk->i->>'line_id')::uuid = kk.id and (v_pk->i->>'qty')::numeric > 0 then
            v_qty := least(v_cut, (v_pk->i->>'qty')::numeric);
            v_pb := v_pb || jsonb_build_object('so_number', v_so.so_number, 'combo_sku', cb.sku, 'combo_line_no', cb.line_no, 'line_id', kk.id, 'sku', kk.sku, 'bin', coalesce(v_pk->i->>'bin', ''), 'qty', v_qty);
            v_pk := jsonb_set(v_pk, array[i::text, 'qty'], to_jsonb((v_pk->i->>'qty')::numeric - v_qty));
            v_cut := v_cut - v_qty;
          end if;
          i := i - 1;
        end loop;
      end loop;
    end loop;
    select coalesce(jsonb_agg(t2), '[]'::jsonb) into v_pk from jsonb_array_elements(v_pk) t2 where (t2->>'qty')::numeric > 0;                     -- 0 이 된 픽은 뺀다(so_ship 은 양수만 받는다)
    v_put_back := v_put_back || v_pb;
    p_orders := jsonb_set(jsonb_set(jsonb_set(p_orders, array[v_ord::text, 'picks'], v_pk), array[v_ord::text, 'removed_expanded'], v_rm), array[v_ord::text, 'put_back'], v_pb);
    select string_agg(format('line %s picked %s but %s to ship', l.line_no, pk.q, l.qty_ordered - coalesce(rm.q, 0)), '; ' order by l.line_no) into v_bad
    from public.so_line l
    join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_pk) t where (t->>'line_id')::uuid = l.id) pk on true
    left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
    where l.so_id = v_so.id and l.combo_line_id is null and pk.q > l.qty_ordered - coalesce(rm.q, 0);                                           -- asm-2b2: 구성품 줄은 위에서 줄였다 · 보통 줄은 그대로 거부
    if v_bad is not null then raise exception 'Order %: over-pick — % — over-pick goes back to its bin — nothing was saved', v_so.so_number, v_bad; end if;
    -- 운임(판정 4 · so_charge_set 의 규칙)
    if e ? 'charges' and jsonb_typeof(e->'charges') not in ('array', 'null') then
      raise exception 'Order %: charges must be an array of {charge_id, name, amount, description, account_id} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      if nullif(trim(x->>'name'), '') is null then raise exception 'Order %: a charge needs a name — nothing was saved', v_so.so_number; end if;
      if (x->>'amount') !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then raise exception 'Order %: charge % needs an amount — nothing was saved', v_so.so_number, trim(x->>'name'); end if;
      if (x->>'amount')::numeric < 0 then raise exception 'Order %: a charge cannot be negative — use a credit note — nothing was saved', v_so.so_number; end if;
      if nullif(x->>'charge_id', '') is not null and not exists (select 1 from public.so_charge c where c.id = (x->>'charge_id')::uuid and c.so_id = v_so.id) then
        raise exception 'Order %: charge % is not on this order — nothing was saved', v_so.so_number, x->>'charge_id';
      end if;
      if (x ? 'discount_pct' and nullif(x->>'discount_pct', '') is not null and (x->>'discount_pct') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$')
         or (x ? 'discount_amount' and nullif(x->>'discount_amount', '') is not null and (x->>'discount_amount') !~ '^\s*[0-9]+(\.[0-9]+)?\s*$') then
        raise exception 'Order %: charge % discount needs a number — nothing was saved', v_so.so_number, trim(x->>'name');                       -- fr-1 판정 356
      end if;
      select * into v_ch from public.so_charge c where c.id = nullif(x->>'charge_id', '')::uuid;                                                   -- fr-1: 기존 줄의 할인(열쇠 없으면 그대로) · 새 줄이면 빈 행
      begin
        perform public.so_charge_discount_check((x->>'amount')::numeric,
                                                case when x ? 'discount_pct'    then nullif(x->>'discount_pct', '')::numeric    else v_ch.discount_pct    end,
                                                case when x ? 'discount_amount' then nullif(x->>'discount_amount', '')::numeric else v_ch.discount_amount end);   -- fr-1 판정 356: 한 곳의 검사 — 운임을 줄여 금액형 할인이 더 커져도 여기서 막힌다
      exception when others then
        raise exception 'Order %: charge %: %', v_so.so_number, trim(x->>'name'), sqlerrm;
      end;
      if nullif(x->>'account_id', '') is not null and not exists (select 1 from public.ref_account a where a.id = (x->>'account_id')::uuid) then
        raise exception 'Order %: account % not found — nothing was saved', v_so.so_number, x->>'account_id';
      end if;
    end loop;
    -- 부가 요금(판정 230 · surcharge-2a) — 운임과 같은 자리 · 모양 · 줄 · 짝·범위·무상(so_surcharge_check · so_line_update 와 한 곳) · 중복
    if e ? 'surcharges' and jsonb_typeof(e->'surcharges') not in ('array', 'null') then
      raise exception 'Order %: surcharges must be an array of {line_id, surcharge_pct, surcharge_amount, surcharge_label} — nothing was saved', v_so.so_number;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = nullif(x->>'line_id', '')::uuid and l.so_id = v_so.id;
      if not found then raise exception 'Order %: surcharge line % is not on this order — nothing was saved', v_so.so_number, coalesce(x->>'line_id', '?'); end if;
      v_spct := case when x ? 'surcharge_pct'    then nullif(x->>'surcharge_pct', '')::numeric    else v_l.surcharge_pct end;
      v_samt := case when x ? 'surcharge_amount' then nullif(x->>'surcharge_amount', '')::numeric else v_l.surcharge_amount end;
      v_slbl := case when x ? 'surcharge_label'  then nullif(trim(x->>'surcharge_label'), '')     else v_l.surcharge_label end;
      perform public.so_surcharge_check(v_spct, v_samt, v_slbl, v_l.free_reason);
    end loop;
    if (select count(*) - count(distinct t->>'line_id') from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t) > 0 then
      raise exception 'Order %: the same line has two surcharge changes — nothing was saved', v_so.so_number;
    end if;
  end loop;

  -- ②~⑤ 오더마다(주어진 순서) — 실행이면 쓰고 미리 보기면 계산만
  for e in select t from jsonb_array_elements(p_orders) t loop
    select * into v_so from public.so s where s.id = (e->>'so_id')::uuid;
    v_removed := '[]'::jsonb;  v_repriced := '[]'::jsonb;  v_charges := '[]'::jsonb;
    v_surcharges := '[]'::jsonb;                                                       -- surcharge-2a
    v_rm := coalesce(e->'removed_expanded', '[]'::jsonb);                               -- asm-2b2: ① 이 펼친 뺀 몫(구성품 derived 포함) · e->'picks' 는 줄인 picks

    -- ② 택배사 · 추적번호 · 배송 메모(열쇠가 온 것만) · 운임 줄(새로 · 또는 charge_id 로 고침 · 세금은 오더 규칙 · 기본 계정 _99_)
    if p_commit and (e ? 'carrier' or e ? 'tracking_number' or e ? 'shipping_notes') then
      update public.so s set
        carrier         = case when e ? 'carrier'         then nullif(trim(e->>'carrier'), '')         else s.carrier end,
        tracking_number = case when e ? 'tracking_number' then nullif(trim(e->>'tracking_number'), '') else s.tracking_number end,
        shipping_notes  = case when e ? 'shipping_notes'  then nullif(trim(e->>'shipping_notes'), '')  else s.shipping_notes end,
        updated_by      = v_staff
      where s.id = v_so.id;
    end if;
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'charges', 'null'::jsonb), '[]'::jsonb)) t loop
      v_acct := null;
      if nullif(x->>'account_id', '') is not null then
        select * into v_acct from public.ref_account a where a.id = (x->>'account_id')::uuid;
      elsif nullif(x->>'charge_id', '') is null then
        select * into v_acct from public.ref_account a where a.code = '_99_';                      -- 기본 Freight Sales · 없으면 비우고 알린다(so_charge_set 과 같다)
        if not found then v_warn := array_append(v_warn, 'charge_account_unset:' || v_so.so_number); end if;
      end if;
      select * into v_ch from public.so_charge c where c.id = nullif(x->>'charge_id', '')::uuid;                                                   -- fr-1: 할인 — 열쇠 없으면 기존 그대로 · '' 이면 지움 · 새 줄이면 없음
      v_dp := case when x ? 'discount_pct'    then nullif(x->>'discount_pct', '')::numeric    else v_ch.discount_pct    end;
      v_da := case when x ? 'discount_amount' then nullif(x->>'discount_amount', '')::numeric else v_ch.discount_amount end;
      if nullif(x->>'charge_id', '') is null and exists (select 1 from public.so_charge c where c.so_id = v_so.id) and not (('charge_added_beside_existing:' || v_so.so_number) = any(v_warn)) then
        v_warn := array_append(v_warn, 'charge_added_beside_existing:' || v_so.so_number);                                                       -- fr-1(freight-0 틈): 운임이 이미 있는데 charge_id 없는 새 운임 — 막지 않고 알린다(견적 줄을 고치는 길은 charge_id)
      end if;
      if p_commit then
        if nullif(x->>'charge_id', '') is null then
          select coalesce(max(c.line_no), 0) + 1 into v_next from public.so_charge c where c.so_id = v_so.id;
          insert into public.so_charge (so_id, line_no, name, description, amount, tax_rule, account_id, account_code, updated_by, discount_pct, discount_amount)
          values (v_so.id, v_next, trim(x->>'name'), nullif(trim(x->>'description'), ''), (x->>'amount')::numeric, v_so.tax_rule, v_acct.id, v_acct.code, v_staff, v_dp, v_da)   -- fr-1
          returning * into v_ch;
        else
          update public.so_charge c set
            name = trim(x->>'name'), description = nullif(trim(x->>'description'), ''), amount = (x->>'amount')::numeric, tax_rule = v_so.tax_rule, discount_pct = v_dp, discount_amount = v_da,   -- fr-1
            account_id = case when v_acct.id is not null then v_acct.id else c.account_id end, account_code = case when v_acct.id is not null then v_acct.code else c.account_code end, updated_by = v_staff
          where c.id = (x->>'charge_id')::uuid returning * into v_ch;
        end if;
        v_charges := v_charges || jsonb_build_object('charge_id', v_ch.id, 'line_no', v_ch.line_no, 'name', v_ch.name, 'amount', v_ch.amount, 'tax_rule', v_ch.tax_rule, 'account_code', v_ch.account_code,
                                                     'discount_pct', v_ch.discount_pct, 'discount_amount', v_ch.discount_amount, 'discount', public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount), 'net', v_ch.amount - public.so_charge_discount(v_ch.amount, v_ch.discount_pct, v_ch.discount_amount));   -- fr-1
      else
        v_charges := v_charges || jsonb_build_object('charge_id', nullif(x->>'charge_id', ''), 'name', trim(x->>'name'), 'amount', (x->>'amount')::numeric, 'tax_rule', v_so.tax_rule, 'account_code', v_acct.code, 'preview', true,
                                                     'discount_pct', v_dp, 'discount_amount', v_da, 'discount', public.so_charge_discount((x->>'amount')::numeric, v_dp, v_da), 'net', (x->>'amount')::numeric - public.so_charge_discount((x->>'amount')::numeric, v_dp, v_da));   -- fr-1
      end if;
    end loop;

    -- ②′ 부가 요금(판정 230 · surcharge-2a) — so_line_update 와 같은 패치 모양(열쇠가 온 칸만 · '' 은 비움) · 실행이면 쓰고 미리 보기면 old → new 만 · ③ 다시 견적 앞(%형은 저장값이 아니라 계산 때 단가를 읽는다)
    for x in select t from jsonb_array_elements(coalesce(nullif(e->'surcharges', 'null'::jsonb), '[]'::jsonb)) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_spct := case when x ? 'surcharge_pct'    then nullif(x->>'surcharge_pct', '')::numeric    else v_l.surcharge_pct end;
      v_samt := case when x ? 'surcharge_amount' then nullif(x->>'surcharge_amount', '')::numeric else v_l.surcharge_amount end;
      v_slbl := case when x ? 'surcharge_label'  then nullif(trim(x->>'surcharge_label'), '')     else v_l.surcharge_label end;
      if p_commit then
        update public.so_line set surcharge_pct = v_spct, surcharge_amount = v_samt, surcharge_label = v_slbl, updated_by = v_staff where id = v_l.id;
      end if;
      v_surcharges := v_surcharges || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku,
                                                         'old', jsonb_build_object('surcharge_pct', v_l.surcharge_pct, 'surcharge_amount', v_l.surcharge_amount, 'surcharge_label', v_l.surcharge_label),
                                                         'new', jsonb_build_object('surcharge_pct', v_spct, 'surcharge_amount', v_samt, 'surcharge_label', v_slbl),
                                                         'surcharge_unit', public.so_line_surcharge_unit(v_l.unit_price, v_spct, v_samt));
      if v_spct is not null and v_spct > 100 then v_warn := array_append(v_warn, 'surcharge_pct_over_100:' || v_so.so_number || ':' || v_l.line_no); end if;
    end loop;

    -- ③ 뺀 몫(판정 5) + 시스템 줄 다시 견적(판정 6 · 할인만 · 남은 수량 > 0 · 사람이 정한 줄은 그대로)
    for x in select t from jsonb_array_elements(v_rm) t loop
      select * into v_l from public.so_line l where l.id = (x->>'line_id')::uuid;
      v_qty := (x->>'qty')::numeric;  v_remaining := v_l.qty_ordered - v_qty;
      if p_commit then
        update public.so_line set qty_removed = v_qty, removed_reason = nullif(trim(x->>'reason'), ''), removed_note = nullif(trim(x->>'note'), ''), removed_at = now(), removed_by = v_staff, updated_by = v_staff
        where id = v_l.id;
      end if;
      v_removed := v_removed || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty_ordered', v_l.qty_ordered, 'qty_removed', v_qty, 'remaining', v_remaining,
                                                   'reason', nullif(trim(x->>'reason'), ''), 'free', v_l.free_reason is not null, 'derived', (x->>'derived')::boolean);
      if v_remaining > 0 and not (x->>'derived')::boolean and not v_l.price_override and v_l.discount_source is distinct from 'manual' then   -- asm-2b2: 구성품 줄은 다시 견적하지 않는다(값 0 · so_line_requote 가 거부한다)
        select * into q from public.so_line_quote(v_so, v_l.product_id, v_remaining);
        v_new_unit := case when v_l.list_price is null then null else v_l.list_price * (1 - q.discount_pct / 100) end;
        if p_commit then perform public.so_line_requote(v_l.id, v_remaining, false); end if;
        v_repriced := v_repriced || jsonb_build_object('line_id', v_l.id, 'line_no', v_l.line_no, 'sku', v_l.sku, 'qty', v_remaining,
                                                       'old_unit_price', v_l.unit_price, 'new_unit_price', v_new_unit, 'old_discount_pct', v_l.discount_pct, 'new_discount_pct', q.discount_pct,
                                                       'old_discount_source', v_l.discount_source, 'new_discount_source', q.discount_source, 'changed', v_new_unit is distinct from v_l.unit_price);
      end if;
    end loop;

    -- ④ 출고(so_ship · 목표 = 주문 − 뺀 것 · 그 아래 차이만 pick_short 판정 7) — 미리 보기는 줄별 계산만(칸 검사·원장은 실행 때)
    if p_commit then
      v_ship := public.so_ship(v_so.id, e->'picks', v_staff, v_on);
      select array_agg(v_so.so_number || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_ship->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
      select jsonb_set(v_ship, '{lines}', coalesce(jsonb_agg(case when p2.sku is null then t2.x else t2.x || jsonb_build_object('combo_sku', p2.sku) end order by t2.ord), '[]'::jsonb)) into v_ship   -- asm-2b2: 구성품 줄에 combo_sku(콤보 줄의 combo true 는 so_ship 이 준다)
      from jsonb_array_elements(v_ship->'lines') with ordinality t2(x, ord) left join public.so_line cp on cp.id = (t2.x->>'line_id')::uuid left join public.so_line p2 on p2.id = cp.combo_line_id;
      if jsonb_array_length(coalesce(e->'put_back', '[]'::jsonb)) > 0 then                                                                           -- asm-2b2(⬜6): 되돌려 놓을 것을 창고 마무리 행에 남긴다(창고가 제자리에 놓는다 · 원장은 닿지 않는다) · 행이 없으면 반환만 + 경고
        update public.wms_order_finalize f set put_back = e->'put_back' where f.order_id = v_so.id;
        get diagnostics v_n = row_count;
        if v_n = 0 then v_warn := array_append(v_warn, 'put_back_unrecorded:' || v_so.so_number); end if;
      end if;
    else
      select jsonb_build_object('preview', true,
               'lines', coalesce(jsonb_agg((jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'sku', l.sku, 'ordered', l.qty_ordered, 'removed', coalesce(rm.q, 0), 'to_ship', l.qty_ordered - coalesce(rm.q, 0),
                                                              'picked', coalesce(pk.q, 0), 'short', l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0))
                                           || case when cm.is_combo then '{"combo": true}'::jsonb else '{}'::jsonb end || case when p2.sku is null then '{}'::jsonb else jsonb_build_object('combo_sku', p2.sku) end) order by l.line_no), '[]'::jsonb),   -- asm-2b2: 콤보 줄 picked = 통째 콤보 수 · 구성품 줄에 combo_sku · 보통 오더의 모양은 그대로
               'backorder_lines', count(*) filter (where l.qty_ordered - coalesce(rm.q, 0) - coalesce(pk.q, 0) > 0))
        into v_ship
      from public.so_line l
      left join public.so_line p2 on p2.id = l.combo_line_id
      cross join lateral (select exists (select 1 from public.so_line cp where cp.combo_line_id = l.id) as is_combo) cm
      left join lateral (select case when cm.is_combo then (select min(floor(coalesce((select sum((t2->>'qty')::numeric) from jsonb_array_elements(e->'picks') t2 where (t2->>'line_id')::uuid = cp.id), 0) / cp.combo_qty)) from public.so_line cp where cp.combo_line_id = l.id)
                                     else (select sum((t->>'qty')::numeric) from jsonb_array_elements(e->'picks') t where (t->>'line_id')::uuid = l.id) end as q) pk on true
      left join lateral (select sum((t->>'qty')::numeric) as q from jsonb_array_elements(v_rm) t where (t->>'line_id')::uuid = l.id) rm on true
      where l.so_id = v_so.id;
    end if;

    -- ⑤ 묶음 열쇠(판정 2) — 청구처 · 청구처 설정이 켜졌으면 오더의 손님(매장) · invoice_group 이 오면 그것(청구처 안에서 · 직원이 바꾼 묶음)
    select * into v_c from public.customer c where c.id = v_so.bill_to_customer_id;
    v_key := v_so.bill_to_customer_id::text || '|' || coalesce(nullif(trim(e->>'invoice_group'), ''), case when coalesce(v_c.invoice_split_by_store, false) then 'store:' || v_so.customer_id::text else '' end);
    v_groups := jsonb_set(v_groups, array[v_key], coalesce(v_groups->v_key, '[]'::jsonb) || to_jsonb(v_so.id));
    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'invoice_group', v_key, 'removed', v_removed, 'repriced', v_repriced, 'charges', v_charges, 'surcharges', v_surcharges, 'ship', v_ship, 'put_back', coalesce(e->'put_back', '[]'::jsonb));   -- asm-2b2: 오더마다 put_back
  end loop;

  -- ⑥ 발행 — 묶음마다 한 장(so_invoice_issue · 발행일 = 오늘 ims_today · §16 판정 5) · 미리 보기는 몇 장 · 어느 오더
  for k in select t.key_txt from jsonb_object_keys(v_groups) as t(key_txt) order by t.key_txt loop   -- 별칭은 변수 이름(x · e · k)과 다르게
    select array_agg(t.v::uuid) into v_ids from jsonb_array_elements_text(v_groups->k) as t(v);
    if p_commit then
      v_iss := public.so_invoice_issue(v_ids, v_staff, null);
      select array_agg((v_iss->>'invoice_number') || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_iss->'warnings', '[]'::jsonb)) as t(w);
      v_warn := v_warn || coalesce(v_tw, '{}');
      v_invoices := v_invoices || jsonb_build_object('group', k, 'invoice_id', v_iss->'invoice_id', 'invoice_number', v_iss->'invoice_number', 'issued_on', v_iss->'issued_on', 'due_on', v_iss->'due_on',
                                                     'orders', (select jsonb_agg(o->>'so_number') from jsonb_array_elements(v_iss->'orders') o), 'totals', v_iss->'totals', 'warnings', v_iss->'warnings');
    else
      v_invoices := v_invoices || jsonb_build_object('group', k, 'preview', true, 'orders', (select jsonb_agg(s.so_number order by s.so_number) from public.so s where s.id = any(v_ids)), 'order_count', array_length(v_ids, 1));
    end if;
  end loop;

  return jsonb_build_object('committed', p_commit, 'shipped_on', v_on, 'orders', v_orders, 'invoices', v_invoices, 'invoice_count', jsonb_array_length(v_invoices), 'put_back', v_put_back, 'warnings', to_jsonb(v_warn));   -- asm-2b2(판정 246): put_back — 미리 보기 · 실행 둘 다 · 화면이 「Put back」 목록으로 그린다
end;
$$;

-- ═══ 5) so_tax_preview 재발행 — 마지막 정의 20261006000805:884 · 운임 줄마다 할인 · 할인 세금(판정 354) · charge_discounts 줄 목록 · totals 새 열쇠 셋 · taxable · tax · total 은 할인을 뺀 값(뜻 그대로 「오더의 세금 · 합계」) ═══
create or replace function public.so_tax_preview(p_so_id uuid, p_on date default null, p_rule_id uuid default null, p_basis text default 'ordered') returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so     public.so%rowtype;
  v_on     date := coalesce(p_on, public.ims_today());
  v_pick   jsonb;
  v_rate   numeric;
  v_rule   text;
  v_source text;
  v_active boolean;                                           -- 세금 ② — 오더에 굳은 규칙이 비활성이 됐나
  v_lines  jsonb;  v_lines_tax numeric;  v_lines_amt numeric;
  v_chg    jsonb;  v_chg_tax numeric;    v_chg_amt numeric;
  v_chd    jsonb;  v_chd_tax numeric := 0;  v_chd_amt numeric := 0;                   -- fr-1 판정 352 · 354: 운임 할인 줄(따로) · 할인 세금(줄마다 반올림) · 할인 합
  v_od_amt numeric := 0;  v_od_tax numeric := 0;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;  v_sc_rate numeric;                      -- surcharge-2a(묶음 3 · 4): 줄마다 surcharge 합 · 그 세금 · surcharge 에 매길 세율
  v_warn   jsonb := '[]'::jsonb;
begin
  if p_basis not in ('ordered', 'shipped') then raise exception 'p_basis must be ordered or shipped'; end if;   -- ⓐ1 이견 4 — 인보이스는 보낸 수량(qty_shipped) 기준 · 초안·확정은 주문 수량
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found'; end if;

  if p_rule_id is not null then
    select r.name, r.rate_pct into v_rule, v_rate from public.ref_tax_rule r where r.id = p_rule_id and r.is_active and r.direction = 'sale';
    if v_rule is null then raise exception 'Tax rule % is not an active selling rule', p_rule_id; end if;
    v_source := 'explicit';
    v_pick := jsonb_build_object('rule_id', p_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on);
  elsif v_so.tax_rule_id is not null then                                              -- 세금 ② — 오더에 고른 규칙을 먼저(배송지에서 고른 것 ship_to · 사람이 정한 것 manual · 판정 8)
    select r.name, r.rate_pct, r.is_active into v_rule, v_rate, v_active from public.ref_tax_rule r where r.id = v_so.tax_rule_id;
    v_source := case when v_so.tax_rule_manual then 'manual' else 'ship_to' end;
    v_pick := jsonb_build_object('rule_id', v_so.tax_rule_id, 'rule', v_rule, 'rate_pct', v_rate, 'on', v_on, 'manual', v_so.tax_rule_manual);
    if not v_active then v_warn := '["tax_rule_inactive"]'::jsonb; end if;
  else                                                                                 -- 규칙이 없는 초안(배송지 모름) — 지금 배송지로 다시 골라 보고 경고를 그대로 낸다
    v_pick := public.so_tax_rule_for(v_so.ship_to_country, v_so.ship_to_state_province, v_on, 'sale');
    v_rate := (v_pick->>'rate_pct')::numeric;  v_rule := v_pick->>'rule';
    v_source := 'ship_to';
    v_warn := coalesce(v_pick->'warnings', '[]'::jsonb);
  end if;

  v_sc_rate := v_rate;                                                                 -- ⭐ 36-e 76 — 회계사가 「surcharge 에 세금이 안 붙는다」 하면 이 줄 하나를 0 으로(surcharge 세금의 유일한 자리 · 묶음 4)
  select coalesce(jsonb_agg(jsonb_build_object('line_no', l.line_no, 'sku', l.sku, 'amount', a.amt, 'tax', public.so_tax_amount(a.amt, v_rate), 'free', l.free_reason is not null,
                                              'line_id', l.id, 'product_id', l.product_id, 'product_name', l.product_name, 'unit', l.unit, 'pack_factor', l.pack_factor,
                                              'qty', a.qty, 'qty_ordered', l.qty_ordered, 'qty_shipped', l.qty_shipped, 'unit_price', l.unit_price, 'list_price', l.list_price,
                                              'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override,
                                              'surcharge_label', l.surcharge_label, 'surcharge_unit', a.sc_unit, 'surcharge_total', s.sc_amt, 'surcharge_tax', public.so_tax_amount(s.sc_amt, v_sc_rate),   -- surcharge-2a(묶음 4): 줄마다 따로 반올림
                                              'combo', exists (select 1 from public.so_line cp where cp.combo_line_id = l.id), 'combo_line_id', l.combo_line_id, 'combo_sku', (select cp.sku from public.so_line cp where cp.id = l.combo_line_id),   -- asm-2b2(묶음 5): 줄 목록은 그대로(구성품 줄은 0 원 · 합계 불변) · 문서 창구(so_invoice_issue · so_proforma)가 이 표시로 구성품 줄을 뺀다
                                              'combo_components', (select jsonb_agg(jsonb_build_object('so_line_id', cp.id, 'product_id', cp.product_id, 'sku', cp.sku, 'description', cp.product_name, 'unit', cp.unit, 'qty_per_combo', cp.combo_qty, 'qty', a.qty * cp.combo_qty) order by cp.line_no) from public.so_line cp where cp.combo_line_id = l.id)) order by l.line_no), '[]'::jsonb),   -- 「includes …」 — 이 기준(basis)의 콤보 수 × 구성품 수
         coalesce(sum(public.so_tax_amount(a.amt, v_rate)), 0), coalesce(sum(a.amt), 0),
         coalesce(sum(s.sc_amt), 0), coalesce(sum(public.so_tax_amount(s.sc_amt, v_sc_rate)), 0)
    into v_lines, v_lines_tax, v_lines_amt, v_sc_amt, v_sc_tax
  from public.so_line l
  cross join lateral (select case when p_basis = 'shipped' then l.qty_shipped else l.qty_ordered end as qty,
                             case when p_basis = 'shipped' then round(l.qty_shipped * l.unit_price, 2) else public.so_line_total(l) end as amt,   -- ⓐ1: 보낸 수량 기준은 round(qty_shipped × unit_price, 2)(so_line_total 과 같은 식 · 수량만 다르다)
                             public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount) as sc_unit) a                      -- surcharge-2a(묶음 1 · 2): 개당(센트) · 수량은 물건값(amt)과 같은 것
  cross join lateral (select public.so_line_surcharge_total(a.sc_unit, a.qty) as sc_amt) s
  where l.so_id = p_so_id;

  if coalesce(v_so.order_discount_pct, 0) > 0 then                                  -- 오더 전체 할인은 제품 줄 합계에 한 번(D6 · 운임 제외) · 세금은 그 줄에 따로(판정 3 · SO-10842 −23.12)
    v_od_amt := -round(v_lines_amt * v_so.order_discount_pct / 100, 2);
    v_od_tax := public.so_tax_amount(v_od_amt, v_rate);
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('line_no', c.line_no, 'name', c.name, 'amount', c.amount, 'tax', public.so_tax_amount(c.amount, v_rate),
                                              'charge_id', c.id, 'description', c.description, 'account_id', c.account_id, 'account_code', c.account_code,
                                              'discount_pct', c.discount_pct, 'discount_amount', c.discount_amount, 'discount', dc.disc, 'discount_tax', public.so_tax_amount(dc.disc, v_rate), 'net', c.amount - dc.disc) order by c.line_no), '[]'::jsonb),   -- fr-1: 운임 줄은 정가 그대로(amount · tax) + 할인 칸
         coalesce(sum(public.so_tax_amount(c.amount, v_rate)), 0), coalesce(sum(c.amount), 0),
         coalesce(sum(dc.disc), 0), coalesce(sum(public.so_tax_amount(dc.disc, v_rate)), 0),                                                                      -- fr-1 판정 354: 할인 세금은 할인 줄마다 따로 반올림(174.26 · 13% · 50% → 22.65 − 11.33 = 11.32)
         coalesce(jsonb_agg(jsonb_build_object('kind', 'charge_discount', 'charge_id', c.id, 'line_no', c.line_no, 'name', c.name || ' discount', 'discount_pct', c.discount_pct, 'discount_amount', c.discount_amount,
                                               'amount', -dc.disc, 'tax', -public.so_tax_amount(dc.disc, v_rate)) order by c.line_no) filter (where dc.disc > 0), '[]'::jsonb)                        -- fr-1 판정 352: 할인 줄(인보이스가 두 줄로 펼칠 재료 · fr-2 · 계정은 inv_config so_freight_discount_account_code)
    into v_chg, v_chg_tax, v_chg_amt, v_chd_amt, v_chd_tax, v_chd
  from public.so_charge c
  cross join lateral (select public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount) as disc) dc                                                     -- fr-1: 할인액 식 한 곳
  where c.so_id = p_so_id;                                                           -- 운임도 배송지 주의 규칙 · 줄마다(판정 6)

  return jsonb_build_object(
    'so_number', v_so.so_number, 'on', v_on, 'basis', p_basis, 'source', v_source, 'rule', v_pick,
    'lines', v_lines, 'order_discount', jsonb_build_object('pct', v_so.order_discount_pct, 'amount', v_od_amt, 'tax', v_od_tax), 'charges', v_chg, 'charge_discounts', v_chd,   -- fr-1
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'lines_tax', v_lines_tax, 'order_discount_amount', v_od_amt, 'order_discount_tax', v_od_tax,
                                 'charges_amount', v_chg_amt, 'charges_tax', v_chg_tax,
                                 'charges_discount_amount', v_chd_amt, 'charges_discount_tax', v_chd_tax, 'charges_net_amount', v_chg_amt - v_chd_amt,   -- fr-1 판정 352 · 354: 새 열쇠(charges_amount 는 정가 합 그대로)
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                                     -- surcharge-2a(묶음 3): 물건값(lines_amount)과 따로 · 오더 할인 기준 밖
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt,                                                                          -- fr-1: 운임 할인을 뺀다
                                 'tax', case when v_rate is null then null else v_lines_tax + v_od_tax + v_chg_tax - v_chd_tax + v_sc_tax end,                                         -- fr-1 판정 354
                                 'total', case when v_rate is null then null else v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_lines_tax + v_od_tax + v_chg_tax - v_chd_tax + v_sc_tax end),   -- fr-1
    'warnings', v_warn);
end;
$$;

-- ═══ 6) so_detail 재발행 — 마지막 정의 20261006204146:956 · charges 행에 discount · net · totals charges_discount_amount · charges_net_total · order_total 둘에서 할인을 뺀다 ═══
create or replace function public.so_detail(p_so_id uuid) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_so       public.so%rowtype;
  v_cust     text;
  v_lines    jsonb;
  v_charges  jsonb;
  v_lines_n  int;  v_no_price int;  v_free int;  v_charges_n int;  v_deal_ended int;
  v_lines_total numeric;  v_charges_total numeric;  v_od_amt numeric;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;                            -- surcharge-2a — so_tax_preview totals 에서 읽는다(식 한 곳 · basis 를 따라간다)
  v_chd    numeric := 0;                                                     -- fr-1 판정 352: 운임 할인 합 — so_tax_preview totals 에서(식 한 곳)
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
  v_bal      jsonb;                                            -- ⓑ2 — 청구처 손님 잔액(그 통화 행)
  v_rule     record;  v_rule_j jsonb;                          -- dsc-3a 판정 311 — manual 인데 규칙 쪽이 더 크면 경고
  v_cp       jsonb;                                            -- dsc-3b 판정 329 — 붙은 쿠폰
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('total', public.so_line_total(l), 'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'is_combo', exists (select 1 from public.so_line c where c.combo_line_id = l.id),                                                           -- asm-2a(묶음 2 · 5): 콤보 줄 · 구성품 줄(combo_line_id · combo_qty 는 to_jsonb(l) 에 있다)
                                                              'combo_sku', (select c.sku from public.so_line c where c.id = l.combo_line_id)) order by l.line_no), '[]'::jsonb),
         count(*) filter (where l.combo_line_id is null), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), public.so_lines_total(p_so_id),   -- dsc-3a 판정 310: 기준 금액 식 한 곳
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('discount', public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount), 'net', c.amount - public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount)) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)   -- fr-1: 할인액 · 순 운임(식 한 곳)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · ⓑ2: invoiced 값 없음(판정 1)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  v_sc_amt := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);  v_sc_tax := coalesce((v_tax->'totals'->>'surcharge_tax')::numeric, 0);   -- surcharge-2a(묶음 3 · 4)
  v_chd := coalesce((v_tax->'totals'->>'charges_discount_amount')::numeric, 0);                                                                          -- fr-1 판정 352(세금은 v_tax 의 tax 가 이미 뺐다 · 354)
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
    v_od_amt := case when v_so.order_discount_pct is null then 0 else round(v_lines_total * v_so.order_discount_pct / 100, 2) end;
  end if;
  select jsonb_build_object('invoice_id', i.id, 'invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'due_on', i.due_on, 'total', i.total,
                            'deposit_applied', i.deposit_applied, 'credit_applied', i.credit_applied, 'balance_forward', i.balance_forward, 'amount_due', i.amount_due,
                            'remaining', public.so_invoice_remaining(i.id), 'paid', i.total - public.so_invoice_remaining(i.id),
                            'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'total', c.total) order by c.credit_number), '[]'::jsonb) from public.so_credit c where c.invoice_id = i.id),
                            'credited_total', (select coalesce(sum(c.total), 0) from public.so_credit c where c.invoice_id = i.id and c.status = 'issued')) into v_inv
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id and o.cancelled_at is null;
  select coalesce(jsonb_agg(jsonb_build_object('invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'cancelled_at', i.cancelled_at) order by i.invoice_number), '[]'::jsonb) into v_inv_hist
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id;
  select to_jsonb(b) into v_bal from public.so_customer_balance(coalesce(v_so.bill_to_customer_id, v_so.customer_id)) b where b.currency_id = v_so.currency_id;   -- ⓑ2: 청구처의 그 통화 잔액(받아 둔 돈 · 예약 · available · 미수)

  v_warn := public.so_tier_warnings(v_so);
  if v_so.tax_rule_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;
  if v_removed > 0 then v_warn := array_append(v_warn, 'lines_removed'); end if;
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(coalesce(v_tax->'warnings', '[]'::jsonb)) as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if v_so.status = 'draft' and v_so.order_discount_source = 'manual' then                                          -- dsc-3a 판정 282 · 311: manual(0 포함)은 그대로 + 규칙 쪽이 더 크면 경고
    select * into v_rule from public.so_order_discount(p_so_id);
    if coalesce(v_rule.pct, 0) > coalesce(v_so.order_discount_pct, 0) then
      v_warn := array_append(v_warn, 'order_discount_rule_now_better');
      v_rule_j := jsonb_build_object('rule_pct', v_rule.pct, 'rule_deal_id', v_rule.deal_id, 'manual_pct', v_so.order_discount_pct);
    end if;
  end if;

  v_cp := public.so_coupon_info(v_so);
  if v_cp is not null and v_cp->>'status' <> 'won' then v_warn := array_append(v_warn, 'coupon_not_used'); end if;   -- dsc-3b 판정 329

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'combo_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and exists (select 1 from public.so_line c where c.combo_line_id = x.id)),
                                 'component_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and x.combo_line_id is not null), 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt,
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'charges_discount_amount', v_chd, 'charges_net_total', v_charges_total - v_chd,                            -- fr-1 판정 352: charges_total 은 정가 합 그대로 · 새 열쇠
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                        -- surcharge-2a — 물건값 · 오더 할인 기준 밖(묶음 3)
                                 'order_total', v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt,                                    -- fr-1: 운임 할인을 뺀다
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt + (v_tax->'totals'->>'tax')::numeric end),   -- fr-1
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'order_discount_rule', v_rule_j,
    'coupon', v_cp,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 7) so_totals_many 재발행 — 마지막 정의 20261007161321:35 · 열 charges_discount_amount(반환 모양이 바뀌어 drop + create + 권한) · so_detail 과 같은 식(검증 S 가 모든 오더에서 대조) ═══
drop function public.so_totals_many(uuid[]);
create function public.so_totals_many(p_so_ids uuid[])
  returns table (so_id uuid, basis text, lines_total numeric, order_discount_amount numeric, charges_total numeric, charges_discount_amount numeric, surcharge_amount numeric, tax numeric, order_total numeric, order_total_with_tax numeric)   -- fr-1: charges_discount_amount 열 하나(charges_total 뒤)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_ids uuid[];
  v_r   record;
  v_tax jsonb;
  v_lt  numeric;  v_od numeric;  v_chg numeric;  v_sc numeric;  v_t numeric;  v_b text;
  v_chd numeric;                                                                                                     -- fr-1 판정 352: 운임 할인 합(so_tax_preview totals · so_detail 과 같은 자리)
begin
  if p_so_ids is null then return; end if;
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;                            -- 중복 · null 은 센다 · 한 오더는 한 행
  if v_ids is null then return; end if;
  if cardinality(v_ids) > 200 then
    raise exception 'so_totals_many takes at most 200 order ids at a time (got %) — nothing was read', cardinality(v_ids);
  end if;
  for v_r in select s.id, s.status, s.order_discount_pct from public.so s where s.id = any (v_ids) order by s.id loop   -- RLS 가 숨긴 오더 · 없는 id 는 여기서 빠진다(행 없음)
    v_b   := case when v_r.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;                    -- so_detail: 나간 뒤에는 보낸 수량이 금액(ⓐ2)
    v_tax := public.so_tax_preview(v_r.id, null, null, v_b);                                                        -- so_detail 과 같은 호출(오늘 · 오더에 고른 규칙 · basis)
    v_lt  := case when v_b = 'shipped' then (v_tax->'totals'->>'lines_amount')::numeric else public.so_lines_total(v_r.id) end;   -- so_detail: ordered 는 so_lines_total(판정 310) · shipped 는 tax 의 lines_amount
    v_od  := case when v_r.order_discount_pct is null then 0 else round(v_lt * v_r.order_discount_pct / 100, 2) end;   -- so_detail: 오더 할인은 제품 줄 합계에 한 번 · round 2(D6)
    select coalesce(sum(c.amount), 0) into v_chg from public.so_charge c where c.so_id = v_r.id;                     -- so_detail: charges_total
    v_sc  := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);                                          -- so_detail: surcharge-2a — tax totals 에서
    v_chd := coalesce((v_tax->'totals'->>'charges_discount_amount')::numeric, 0);                                   -- fr-1: so_detail 과 같은 식
    v_t   := (v_tax->'totals'->>'tax')::numeric;                                                                    -- 세금 규칙 없으면 null
    so_id := v_r.id;  basis := v_b;  lines_total := v_lt;  order_discount_amount := v_od;  charges_total := v_chg;  charges_discount_amount := v_chd;  surcharge_amount := v_sc;  tax := v_t;   -- fr-1
    order_total := v_lt - v_od + v_chg - v_chd + v_sc;                                                                                      -- fr-1: 운임 할인을 뺀다
    order_total_with_tax := case when v_t is null then null else v_lt - v_od + v_chg - v_chd + v_sc + v_t end;                              -- fr-1
    return next;
  end loop;
end;
$$;
revoke all on function public.so_totals_many(uuid[]) from public, anon;
grant execute on function public.so_totals_many(uuid[]) to authenticated;
comment on function public.so_totals_many(uuid[]) is '오더 여럿의 totals 한 번에(so-tot-1 · fr-1 재발행 2026-10-07) — 행마다 so_detail(id).totals 의 basis · lines_total · order_discount_amount · charges_total · charges_discount_amount(fr-1) · surcharge_amount · tax · order_total · order_total_with_tax 와 같은 값(검증이 모든 오더에서 대조) · 같은 속 함수(so_lines_total · so_tax_preview)를 부른다 · 세금 규칙이 없는 오더는 tax · order_total_with_tax null · invoker · stable · RLS 그대로 · 중복 · null 은 빼고 센다 · 한 번에 200 개까지 · 목록 화면이 부른다';

-- ═══ 8) so_proforma 재발행 — 마지막 정의 20261006000805:1224 · so_tax_preview 를 따라(charges_discount_amount · charge_discounts · taxable · total · balance_due) ═══
create or replace function public.so_proforma(p_so_ids uuid[]) returns jsonb
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare
  v_on       date := public.ims_today();
  v_n        int;
  v_cnt      int;
  v_bad      text;
  v_first    public.so%rowtype;
  v_so       public.so%rowtype;
  v_cust     uuid;
  v_prev     jsonb;
  v_orders   jsonb := '[]'::jsonb;
  v_deposits jsonb := '[]'::jsonb;
  v_lines_amt numeric := 0;  v_od_amt numeric := 0;  v_chg_amt numeric := 0;  v_tax numeric := 0;  v_tax_missing boolean := false;
  v_sc_amt numeric := 0;                                                                   -- surcharge-2a
  v_chd_amt numeric := 0;                                                                  -- fr-1 판정 352: 운임 할인 합(so_tax_preview totals)
  v_received numeric := 0;
  v_warn     text[] := '{}';
  v_tw       text[];
  v_bal      jsonb;
begin
  v_cnt := coalesce(array_length(p_so_ids, 1), 0);
  if v_cnt = 0 then raise exception 'A pro forma needs at least one order'; end if;
  select count(distinct x) into v_n from unnest(p_so_ids) x;
  if v_n <> v_cnt then raise exception 'The same order is listed twice'; end if;
  select count(*) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n <> v_cnt then raise exception 'Order not found'; end if;
  select string_agg(s.so_number || ' (' || s.status || ')', ', ' order by s.so_number) into v_bad from public.so s where s.id = any(p_so_ids) and s.status in ('fulfilled', 'cancelled');
  if v_bad is not null then raise exception 'A pro forma is for open orders only — % — a finished order has its invoice', v_bad; end if;
  select string_agg(s.so_number || ' is on invoice ' || i.invoice_number, ', ' order by s.so_number) into v_bad
  from public.so_invoice_order o join public.so s on s.id = o.so_id join public.so_invoice i on i.id = o.invoice_id where o.so_id = any(p_so_ids) and o.cancelled_at is null;
  if v_bad is not null then raise exception 'Order already invoiced — % — print the invoice instead', v_bad; end if;
  select count(distinct coalesce(s.bill_to_customer_id, s.customer_id)) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One pro forma bills one customer — these orders have different bill-to customers'; end if;
  select count(distinct s.currency_id) into v_n from public.so s where s.id = any(p_so_ids);
  if v_n > 1 then raise exception 'One pro forma has one currency — these orders have different currencies'; end if;
  select * into v_first from public.so s where s.id = any(p_so_ids) order by s.so_number limit 1;
  v_cust := coalesce(v_first.bill_to_customer_id, v_first.customer_id);

  -- 오더마다 — 오늘 기준 예상 세금(so_tax_preview · 오더 규칙 · basis ordered: 발행 전 오더의 qty_removed 는 늘 0 · 0-11) · 규칙 없으면 세금 없이 경고
  for v_so in select * from public.so s where s.id = any(p_so_ids) order by s.so_number loop
    v_prev := public.so_tax_preview(v_so.id, v_on, null, 'ordered');
    v_lines_amt := v_lines_amt + (v_prev->'totals'->>'lines_amount')::numeric;
    v_od_amt    := v_od_amt + (v_prev->'totals'->>'order_discount_amount')::numeric;
    v_chg_amt   := v_chg_amt + (v_prev->'totals'->>'charges_amount')::numeric;
    v_sc_amt    := v_sc_amt + coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);   -- surcharge-2a(세금은 v_prev 의 tax 에 이미 들어 있다 · 묶음 4)
    v_chd_amt   := v_chd_amt + coalesce((v_prev->'totals'->>'charges_discount_amount')::numeric, 0);   -- fr-1(할인 세금도 v_prev 의 tax 가 이미 뺐다 · 354)
    if v_prev->'totals'->>'tax' is null then v_tax_missing := true; v_warn := array_append(v_warn, 'tax_rule_missing:' || v_so.so_number);
    else v_tax := v_tax + (v_prev->'totals'->>'tax')::numeric; end if;
    select array_agg(v_so.so_number || ':' || t.w) into v_tw from jsonb_array_elements_text(coalesce(v_prev->'warnings', '[]'::jsonb)) as t(w);
    v_warn := v_warn || coalesce(v_tw, '{}');
    v_orders := v_orders || jsonb_build_object('so_id', v_so.id, 'so_number', v_so.so_number, 'status', v_so.status, 'order_date', v_so.order_date, 'ref', v_so.ref,
                                               'ship_to', jsonb_build_object('company', v_so.ship_to_company, 'contact', v_so.ship_to_contact, 'line1', v_so.ship_to_line1, 'line2', v_so.ship_to_line2,
                                                                             'city', v_so.ship_to_city, 'state_province', v_so.ship_to_state_province, 'postal_code', v_so.ship_to_postal_code, 'country', v_so.ship_to_country),
                                               'tax_rule', v_prev->'rule'->>'rule', 'rate_pct', v_prev->'rule'->'rate_pct', 'tax_source', v_prev->>'source',
                                               'lines', (select coalesce(jsonb_agg(x order by (x->>'line_no')::int), '[]'::jsonb) from jsonb_array_elements(v_prev->'lines') x where nullif(x->>'combo_line_id', '') is null),   -- asm-2b2(묶음 5): 손님 문서 — 구성품 줄은 빼고 콤보 줄의 combo_components(includes)만
                                               'order_discount', v_prev->'order_discount', 'charges', v_prev->'charges', 'charge_discounts', v_prev->'charge_discounts', 'totals', v_prev->'totals');   -- fr-1
  end loop;

  -- 받은 금액 = 이 오더들을 대상으로 한 활성 선결제의 남은 금액(⬜9 · 대상이 다른 오더에도 걸린 결제는 남은 금액 전부를 보인다 — 짐작 그대로 · 정본에 적는다)
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', z.id, 'paid_on', z.paid_on, 'method', z.method, 'reference', z.reference, 'amount', z.amount, 'remaining', z.remaining,
                                               'targets', (select jsonb_agg(s2.so_number order by s2.so_number) from public.so_payment_order o2 join public.so s2 on s2.id = o2.so_id where o2.payment_id = z.id)) order by z.paid_on, z.created_at), '[]'::jsonb),
         coalesce(sum(z.remaining), 0)
    into v_deposits, v_received
  from (select p.id, p.paid_on, p.method, p.reference, p.amount, p.created_at,
               public.so_payment_remaining(p.id) as remaining
          from public.so_payment p
         where p.customer_id = v_cust and p.currency_id = v_first.currency_id and p.status = 'active' and p.kind = 'payment'
           and exists (select 1 from public.so_payment_order o where o.payment_id = p.id and o.so_id = any(p_so_ids))) z
  where z.remaining > 0;
  select to_jsonb(b) into v_bal from public.so_customer_balance(v_cust) b where b.currency_id = v_first.currency_id;

  return jsonb_build_object(
    'document', 'PRO FORMA', 'note', 'This is not an invoice', 'invoice_number', null, 'as_of', v_on,
    'customer_id', v_cust, 'bill_to_name', v_first.bill_to_name, 'currency_code', v_first.currency_code,
    'orders', v_orders,
    'totals', jsonb_build_object('lines_amount', v_lines_amt, 'order_discount_amount', v_od_amt, 'charges_amount', v_chg_amt, 'charges_discount_amount', v_chd_amt, 'surcharge_amount', v_sc_amt,   -- surcharge-2a(묶음 3) · fr-1 운임 할인
                                 'taxable_amount', v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt,
                                 'tax', case when v_tax_missing then null else v_tax end,
                                 'total', case when v_tax_missing then null else v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_tax end,
                                 'received', v_received,
                                 'balance_due', case when v_tax_missing then null else v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_tax - v_received end),
    'deposits', v_deposits,
    'customer_balance', v_bal,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ 9) 발행 틈 가드 — so_invoice_issue 는 fr-2 까지 무접촉이라 할인 운임을 그대로 두 줄 없이 낼 수 있다 → so_invoice_order BEFORE INSERT 에서 막는다(fr-2 가 이 트리거 · 함수를 지운다) ═══
create function public.so_invoice_order_freight_discount_guard() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if exists (select 1 from public.so_charge c where c.so_id = new.so_id and (c.discount_pct is not null or c.discount_amount is not null)) then
    raise exception 'Order % has a freight discount — invoicing a discounted freight line arrives with fr-2 (take the discount off the charge to invoice now) — nothing was saved', new.so_number;
  end if;
  return new;
end;
$$;
revoke all on function public.so_invoice_order_freight_discount_guard() from public, anon, authenticated;
comment on function public.so_invoice_order_freight_discount_guard() is 'fr-1 임시 가드(2026-10-07) — so_invoice_order BEFORE INSERT · 그 오더에 할인이 걸린 운임 줄이 있으면 발행을 거부한다(so_invoice_issue 가 아직 할인 줄을 펼치지 못해 운임 정가로 청구되고 세금만 순액이 되는 틈) · ⚠️ fr-2(인보이스 두 줄 펼치기)가 트리거와 함께 지운다 · 비용 = 발행 오더마다 인덱스 조회 하나(so_charge_so_idx)';
create trigger so_invoice_order_freight_discount_guard before insert on public.so_invoice_order for each row execute function public.so_invoice_order_freight_discount_guard();

-- ═══ 10) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text; v_src text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'so_charge' and column_name in ('discount_pct', 'discount_amount')) <> 2 then v_bad := v_bad || ' columns'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.so_charge'::regclass and conname in ('so_charge_discount_pair_ck', 'so_charge_discount_pct_ck', 'so_charge_discount_amount_ck', 'so_charge_amount_ck')) <> 4 then v_bad := v_bad || ' checks'; end if;
  foreach v_t in array array['public.so_charge_discount(numeric, numeric, numeric)', 'public.so_charge_discount_check(numeric, numeric, numeric)', 'public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)', 'public.so_finalize(jsonb, boolean, date)', 'public.so_tax_preview(uuid, date, uuid, text)', 'public.so_detail(uuid)', 'public.so_totals_many(uuid[])', 'public.so_proforma(uuid[])', 'public.so_invoice_order_freight_discount_guard()'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(anon)', v_t); end if;
  end loop;
  if to_regprocedure('public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid)') is not null then v_bad := v_bad || ' old_so_charge_set'; end if;
  foreach v_t in array array['public.so_charge_discount_check(numeric, numeric, numeric)', 'public.so_invoice_order_freight_discount_guard()'] loop
    if has_function_privilege('authenticated', v_t, 'execute') then v_bad := v_bad || format(' %s(authenticated)', v_t); end if;
  end loop;
  foreach v_t in array array['public.so_charge_set(uuid, text, numeric, uuid, text, text, uuid, numeric, numeric)', 'public.so_totals_many(uuid[])', 'public.so_detail(uuid)', 'public.so_tax_preview(uuid, date, uuid, text)', 'public.so_finalize(jsonb, boolean, date)', 'public.so_proforma(uuid[])', 'public.so_charge_discount(numeric, numeric, numeric)'] loop
    if not has_function_privilege('authenticated', v_t, 'execute') then v_bad := v_bad || format(' %s(no-authenticated)', v_t); end if;
  end loop;
  if pg_get_function_result('public.so_totals_many(uuid[])'::regprocedure) not like '%charges_discount_amount numeric%' then v_bad := v_bad || ' totals_many(result)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_charge_set', 'so_finalize', 'so_tax_preview', 'so_detail', 'so_totals_many', 'so_proforma') and p.prosrc like '%fr-1%') <> 6 then v_bad := v_bad || ' bodies'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_invoice_issue', 'so_credit_issue', 'so_credit_prepare', 'so_charge_remove', 'so_lines_total') and p.prosrc like '%fr-1%') <> 0 then v_bad := v_bad || ' untouched(touched)'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_invoice_order'::regclass and tgname = 'so_invoice_order_freight_discount_guard' and tgenabled <> 'D') <> 1 then v_bad := v_bad || ' guard(trigger)'; end if;
  if (select count(*) from public.so_charge where discount_pct is not null or discount_amount is not null) <> 0 then v_bad := v_bad || ' data(discounts already?)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM352', message = format('STOP - fr-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
