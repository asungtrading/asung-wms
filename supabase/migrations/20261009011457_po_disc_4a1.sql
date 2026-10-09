-- ─────────────────────────────────────────────────────────────
-- 공급처 할인 → 재고 원가 ④-a1 — 인보이스의 조기 결제 할인 조건 · 충당마다 할인(정본) · discount_taken = Σ(트리거) · 결제 머리 · 충당의 직접 쓰기 닫기(문지기 + 문 플래그) (Asung-IMS · po-disc-4a1 · 2026-10-09)
--   정본(뒤에 적는다): so-module §53 판정 389 · 391 · 395(2026-10-08 · Caleb) · po-module §11-h 「조기 결제 할인 — 결제에서」 · po-disc-4 보고 이견 1 · 2 · 5 · 6 · 11
--   판정 389  조기 결제 할인은 인보이스 할인 체인이 아니라 결제의 Discount taken — 이 차수: 인보이스에 조건(% 또는 금액 · 기준 · 기한)만 적는다(po_invoice_early_*) · 결제조건에서 제안(po_invoice_create)
--   판정 391  결제 화면이 문서별 충당을 채운다 — 충당마다 할인(po_payment_alloc.discount_amount · 정본) · po_payment.discount_taken 은 Σ충당 할인(트리거가 적는다 · 뜻은 「결제 단위 합」 그대로라 읽는 곳 18 무변)
--   ④-a2(다음): 결제 저장 순간 원가 사건(inv_cost_adjust) · 되돌림 · 백필 — 이 차수는 사건을 만들지 않는다
--   이견 1  충당 금액은 PostgREST 직접이 아니라 창구(po_payment_alloc_set)다 — 닫는 칸은 po_payment.amount · discount_taken · po_payment_alloc.amount · discount_amount(+ 두 표의 직접 insert)
--   이견 2  칸 권한 revoke 는 일반 42501 만 낸다 → before 트리거 문지기 + 트랜잭션 플래그 po.payment_door(창구가 세운다 · inv.settled_adds 선례) · 문장은 「… through the payment window — nothing was saved」
--   이견 6  조건 칸 잠금 — 그 인보이스에 할인을 쓴 충당(discount_amount > 0)이 있으면 조건 수정 거부 · ⬜10 둘 다 비면 basis null(짝 CHECK)
--   이견 11 paid_on 은 열어 둔다 · po_payment_detail 경고 paid_on_after_discount_deadline
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 넷 — po_invoice_create(20261008170700:1117~1474 바이트 복사 + declare 5 · 제안 블록 · insert 칸 3 · 반환 키 1) · po_invoice_list(20261008170700:498~537 · 뒤에 여섯 칸) · po_payment_alloc_set(20260918013000:457~506 + 플래그) · po_payment_create(20260924001820:903~1010 + 옛 모양 호환 · 플래그 · 충당 할인) · po_payment_detail(20261008174126:662~724 + 칸 2 · 경고 1)
--   원칙 1: IMS 는 Cin7 없이 돈다 — 할인 조건의 재료는 IMS 결제조건 · IMS 인보이스
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

-- ═══ ① 인보이스의 조기 결제 할인 조건 — 칸 넷 · 짝 CHECK(⬜10) ═══
alter table public.po_invoice
  add column early_discount_pct    numeric,                                              -- 예 2.1 (% · 둘 중 하나)
  add column early_discount_amount numeric,                                              -- 금액으로 받을 때(문서 통화)
  add column early_discount_basis  text,                                                 -- pre_tax | with_tax · 조건이 있으면 not null
  add column early_discount_until  date,                                                 -- 이날까지 결제하면 · null = 기한 없음(결제조건에 일수가 없을 때 · 사람이 채운다)
  add constraint po_invoice_early_one_ck   check (early_discount_pct is null or early_discount_amount is null),
  add constraint po_invoice_early_pos_ck   check ((early_discount_pct is null or early_discount_pct > 0) and (early_discount_amount is null or early_discount_amount > 0)),
  add constraint po_invoice_early_basis_ck check ((early_discount_basis is not null) = (early_discount_pct is not null or early_discount_amount is not null)),
  add constraint po_invoice_early_val_ck   check (early_discount_basis is null or early_discount_basis in ('pre_tax', 'with_tax')),
  add constraint po_invoice_early_until_ck check (early_discount_until is null or early_discount_basis is not null);
comment on column public.po_invoice.early_discount_pct    is 'po-disc-4a1 ⭐ 조기 결제 할인 %(판정 389 · 391) — 금액과 둘 중 하나 · 결제조건(ref_payment_term.discount_percent)에서 po_invoice_create 가 제안 · 사람이 고친다(P&G 「2%19 Net30」 실제 2.1% · 13일) · 할인을 쓴 충당이 있으면 잠긴다(po_invoice_early_lock)';
comment on column public.po_invoice.early_discount_basis  is 'po-disc-4a1 ⭐ 할인 기준 — pre_tax(payable_taxable · 세금 전) | with_tax(payable_net · 세금 포함 · 판정 395 상품 몫만 원가) · 조건(% 또는 금액)이 있을 때만 not null';
comment on column public.po_invoice.early_discount_until  is 'po-disc-4a1 ⭐ 할인 기한(이날까지 결제) — invoice_date + discount_days 제안 · null = 기한 없음 · ⚠️ due_date(만기)와 다르다';

-- 식 한 곳 — 조건 · 기준 금액 · 결제일 → 할인 금액(문서 통화 · round 2) · 유효(결제일 ≤ 기한) · 뷰 po_invoice_list 와 po_invoice_early_discount 가 같이 부른다(SQL stable · 인라인)
create function public.po_early_discount_calc(p_pct numeric, p_amount numeric, p_basis text, p_until date, p_pre_tax numeric, p_with_tax numeric, p_on date default null)
  returns table (has_terms boolean, base_amount numeric, discount numeric, valid_on date, is_valid boolean, days_left int)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select (p_pct is not null or p_amount is not null)                                                                                    as has_terms,
         case p_basis when 'pre_tax' then p_pre_tax when 'with_tax' then p_with_tax end                                                 as base_amount,
         case when p_amount is not null then round(p_amount, 2)
              when p_pct is not null then round(coalesce(case p_basis when 'pre_tax' then p_pre_tax when 'with_tax' then p_with_tax end, 0) * p_pct / 100, 2)
              else 0 end                                                                                                                as discount,
         coalesce(p_on, public.ims_today())                                                                                             as valid_on,
         ((p_pct is not null or p_amount is not null) and (p_until is null or coalesce(p_on, public.ims_today()) <= p_until))           as is_valid,
         case when p_until is not null then (p_until - coalesce(p_on, public.ims_today())) end                                          as days_left
$$;
revoke all on function public.po_early_discount_calc(numeric, numeric, text, date, numeric, numeric, date) from public, anon;
grant execute on function public.po_early_discount_calc(numeric, numeric, text, date, numeric, numeric, date) to authenticated;
comment on function public.po_early_discount_calc(numeric, numeric, text, date, numeric, numeric, date) is 'po-disc-4a1 ⭐ 조기 결제 할인 식 한 곳 — 금액이 있으면 그 금액 · % 면 기준(pre_tax = payable_taxable · with_tax = payable_net) × % ÷ 100 · round 2(문서 통화) · is_valid = 조건 있음 ∧ (기한 없음 ∨ 결제일 ≤ 기한) · p_on 없으면 ims_today · 뷰 po_invoice_list(오늘) · po_invoice_early_discount(결제일) · ④-a2 결제 창구가 부른다';

create function public.po_invoice_early_discount(p_invoice_id uuid, p_on date default null)
  returns table (invoice_id uuid, invoice_number text, doc_kind text, pct numeric, amount numeric, basis text, until_date date,
                 has_terms boolean, base_amount numeric, discount numeric, valid_on date, is_valid boolean, days_left int)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select i.id, i.invoice_number, i.doc_kind, i.early_discount_pct, i.early_discount_amount, i.early_discount_basis, i.early_discount_until,
         c.has_terms, c.base_amount, c.discount, c.valid_on, c.is_valid, c.days_left
  from public.po_invoice i
  join public.po_invoice_money m on m.id = i.id
  cross join lateral public.po_early_discount_calc(case when i.doc_kind = 'invoice' then i.early_discount_pct end, case when i.doc_kind = 'invoice' then i.early_discount_amount end,
                                                   i.early_discount_basis, i.early_discount_until, m.payable_taxable, m.payable_net, p_on) c
  where i.id = p_invoice_id
$$;
revoke all on function public.po_invoice_early_discount(uuid, date) from public, anon;
grant execute on function public.po_invoice_early_discount(uuid, date) to authenticated;
comment on function public.po_invoice_early_discount(uuid, date) is 'po-disc-4a1 ⭐ 인보이스 한 장의 조기 결제 할인(결제일 p_on 기준 · 없으면 오늘) — 조건 칸 넷 + po_early_discount_calc(기준 금액은 po_invoice_money) · 크레딧은 조건 없음으로 본다 · 화면 「To pay」(④-b) · 결제 창구(④-a2)의 재료';

-- 잠금(이견 6) — 할인을 쓴 충당이 있으면 조건 칸을 못 고친다(되돌린 뒤에) · 초안 · 확정 구분 없음(초안에는 충당이 없다)
create function public.po_invoice_early_lock() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_n int; v_txt text;
begin
  if new.early_discount_pct is distinct from old.early_discount_pct or new.early_discount_amount is distinct from old.early_discount_amount
     or new.early_discount_basis is distinct from old.early_discount_basis or new.early_discount_until is distinct from old.early_discount_until then
    select count(*), string_agg(coalesce(p.reference, p.paid_on::text) || ' (' || a.discount_amount::text || ')', ', ' order by p.paid_on)
      into v_n, v_txt
      from public.po_payment_alloc a join public.po_payment p on p.id = a.po_payment_id
     where a.po_invoice_id = old.id and a.discount_amount > 0;
    if v_n > 0 then
      raise exception 'Invoice % — a payment already took its early-payment discount (%) — reverse that payment''s discount first, then change the terms — nothing was saved', old.invoice_number, v_txt;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.po_invoice_early_lock() from public, anon, authenticated;
create trigger po_invoice_early_lock before update of early_discount_pct, early_discount_amount, early_discount_basis, early_discount_until on public.po_invoice
  for each row execute function public.po_invoice_early_lock();

-- ═══ ② 충당마다 할인 — po_payment_alloc.discount_amount(정본 · 이견 5) · 백필(실물 7건 전부 충당 하나 → discount_taken 그대로) · ⚠️ 문지기보다 먼저 ═══
alter table public.po_payment_alloc
  add column discount_amount numeric not null default 0,                                 -- 이 문서에서 받은 할인(결제 통화 = 문서 통화) · ≥ 0
  add constraint po_payment_alloc_discount_ck check (discount_amount >= 0);
comment on column public.po_payment_alloc.discount_amount is 'po-disc-4a1 ⭐ 이 충당(문서)에서 받은 할인 — 정본(판정 391 문서별 충당) · po_payment.discount_taken 은 이 칸의 Σ(트리거 po_payment_alloc_discount_sync) · 검산 Σ충당 amount = 결제 amount + Σdiscount_amount 그대로 · 쓰기는 창구(po_payment_create · ④-b 할인 고치기)만 — 직접 update 는 문지기가 막는다 · ④-a2 가 이 칸으로 원가 사건을 만든다';
update public.po_payment_alloc a
   set discount_amount = p.discount_taken
  from public.po_payment p
 where p.id = a.po_payment_id and p.discount_taken > 0
   and (select count(*) from public.po_payment_alloc b where b.po_payment_id = p.id) = 1;
do $$
declare v_bad text;
begin
  select string_agg(coalesce(p.reference, p.id::text) || ' ' || p.discount_taken::text || ' vs Σ ' || coalesce(s.sum_d, 0)::text, ', ') into v_bad
    from public.po_payment p left join (select po_payment_id, sum(discount_amount) as sum_d from public.po_payment_alloc group by po_payment_id) s on s.po_payment_id = p.id
   where p.discount_taken is distinct from coalesce(s.sum_d, 0);
  if v_bad is not null then
    raise exception using errcode = 'IM394', message = format('STOP - po-disc-4a1 backfill: payments whose discount_taken is not the sum of allocation discounts (several allocations with a discount): %s - split the discount by hand first - nothing was changed', v_bad);
  end if;
end $$;

-- Σ 동기 — 충당 할인이 바뀌면 결제 머리의 discount_taken 을 Σ 로(문지기 플래그를 스스로 세우고 되돌린다) · 지우기(결제 삭제 CASCADE)는 머리가 이미 없어 0 행
create function public.po_payment_alloc_discount_sync() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_pid uuid; v_sum numeric; v_prev text;
begin
  v_prev := current_setting('po.payment_door', true);
  perform set_config('po.payment_door', '1', true);
  foreach v_pid in array array_remove(array[case when tg_op <> 'INSERT' then old.po_payment_id end, case when tg_op <> 'DELETE' then new.po_payment_id end], null) loop
    select coalesce(sum(a.discount_amount), 0) into v_sum from public.po_payment_alloc a where a.po_payment_id = v_pid;
    update public.po_payment p set discount_taken = v_sum where p.id = v_pid and p.discount_taken is distinct from v_sum;
  end loop;
  perform set_config('po.payment_door', coalesce(v_prev, ''), true);
  return null;
end;
$$;
revoke all on function public.po_payment_alloc_discount_sync() from public, anon, authenticated;
create trigger po_payment_alloc_discount_sync after insert or update of discount_amount, po_payment_id or delete on public.po_payment_alloc
  for each row execute function public.po_payment_alloc_discount_sync();

-- ═══ ⑤ 닫기(이견 1 · 2) — 문지기 둘 · 플래그 po.payment_door = '1' 인 트랜잭션(창구)만 지난다 · 지우기는 창구가 이미 전부(po_doc_delete · po_payment_alloc_delete) ═══
create function public.po_payment_guard() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if coalesce(current_setting('po.payment_door', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    raise exception 'A payment is created through the payment window (Pay · po_payment_create), not by inserting a row — nothing was saved';
  end if;
  if new.amount is distinct from old.amount or new.discount_taken is distinct from old.discount_taken then
    raise exception 'Paid (% → %) and Discount taken (% → %) on payment % are changed through the payment window (Pay · Adjust discount), not by editing the field — nothing was saved',
      old.amount, new.amount, old.discount_taken, new.discount_taken, coalesce(old.reference, old.id::text);
  end if;
  return new;
end;
$$;
revoke all on function public.po_payment_guard() from public, anon, authenticated;
create trigger po_payment_guard before insert or update on public.po_payment for each row execute function public.po_payment_guard();

create function public.po_payment_alloc_guard() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if coalesce(current_setting('po.payment_door', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    raise exception 'A document is put on a payment through the payment window (Pay · Add a document), not by inserting a row — nothing was saved';
  end if;
  if new.amount is distinct from old.amount or new.discount_amount is distinct from old.discount_amount then
    raise exception 'The amount (% → %) and discount (% → %) on this allocation line are changed through the payment window (On this payment · Adjust discount), not by editing the field — nothing was saved',
      old.amount, new.amount, old.discount_amount, new.discount_amount;
  end if;
  return new;
end;
$$;
revoke all on function public.po_payment_alloc_guard() from public, anon, authenticated;
create trigger po_payment_alloc_guard before insert or update on public.po_payment_alloc for each row execute function public.po_payment_alloc_guard();

-- ═══ ③ po_invoice_create 재발행 — 마지막 정의 20261008170700:1117~1474(DB md5 74f6853c · 검증 G0) 바이트 복사 + declare 1줄 · 제안 블록 · insert 칸 3 · 반환 키 1 ═══
create or replace function public.po_invoice_create(
  p_doc_kind              text,                       -- 'invoice' | 'credit'
  p_invoice_number        text    default null,       -- 인보이스: 필수(공급처 번호) · 크레딧: 안 주면 자동(우리 번호) · 주면 그대로
  p_po_id                 uuid    default null,       -- 인보이스: 필수 · 크레딧: 머리 원천 둘째 · 크레딧 번호의 축(credit_po_id)
  p_credit_for_invoice_id uuid    default null,       -- 크레딧만 · 있으면 줄 자동 채우기(차이) · 그 인보이스의 발주가 하나면 그것이 번호의 축
  p_supplier_id           uuid    default null,       -- 크레딧 머리 원천 셋째(조정 크레딧 · CN-<연도>-<n>)
  p_invoice_date          date    default null,       -- 안 주면 오늘 · 조정 번호의 연도
  p_due_date              date    default null,
  p_total_amount          numeric default null,       -- 찍힌 총액 · 안 주면 0 + 경고
  p_copy_discounts        boolean default true,       -- 인보이스만
  p_commit                boolean default false,      -- false = 미리 보기
  p_line_qty              jsonb   default null        -- ⭐ 새 · 인보이스만 · { "<po_line_id>": <qty_ea> } · null 이면 미청구 수량 전부(지금 그대로) · 키에 없는 라인·0 은 줄 없음('skipped')
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff        uuid;
  v_num          text;
  v_num_src      text;
  v_kind_label   text;
  v_po           public.po%rowtype;
  v_for          public.po_invoice%rowtype;
  v_sup          public.supplier%rowtype;
  v_source       text;
  v_supplier_id  uuid;  v_currency_id uuid;  v_rate numeric;  v_pt_id uuid;  v_pt_name text;
  v_tax_id       uuid;  v_tax_name text;                                                                       -- po-tax-1 · 머리 규칙(원천과 같은 순서)
  v_sup_name     text;  v_cur_code text;
  v_credit_po_id uuid;  v_credit_po_number text;  v_po_n int;
  v_exists       int;
  v_inv_id       uuid;
  v_warn         text[] := '{}';
  v_lines        jsonb  := '[]'::jsonb;
  v_discs        jsonb  := '[]'::jsonb;
  v_n            int := 0;
  v_ins          int := 0;
  v_ok           int := 0;
  v_skip         int := 0;
  v_disc_n       int := 0;
  r              record;
  v_verdict      text;
  v_qty          numeric;
  v_req          numeric;
  v_full         boolean;
  v_msgs         text[];
  -- ⭐ p_line_qty
  v_use_qty      boolean := false;
  v_req_total    numeric;
  v_bad_n        int;
  v_bad_txt      text;
  v_keep_n       int;
  -- po-disc-4a1(판정 389 · 391): 결제조건에서 조기 결제 할인 조건을 제안한다 — % · 기한(invoice_date + discount_days) · 기준 pre_tax · 사람이 고친다
  v_ed           record;  v_ed_pct numeric;  v_ed_until date;  v_ed_basis text;  v_ed_j jsonb;
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  if p_doc_kind not in ('invoice', 'credit') then
    raise exception 'p_doc_kind must be ''invoice'' or ''credit'' — nothing was saved';
  end if;
  v_kind_label := case p_doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_num := nullif(regexp_replace(coalesce(p_invoice_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if p_doc_kind = 'invoice' and v_num is null then
    raise exception 'Invoice number is required — it is the supplier''s number — nothing was saved';
  end if;

  -- ⭐ p_line_qty 는 인보이스만 — 크레딧에 주면 거부(조용히 무시하면 화면 실수를 덮는다)
  if p_line_qty is not null then
    if p_doc_kind <> 'invoice' then
      raise exception 'p_line_qty is for invoices only — a credit note is filled from invoice minus received — nothing was saved';
    end if;
    if jsonb_typeof(p_line_qty) <> 'object' then
      raise exception 'p_line_qty must be a JSON object { "<po_line_id>": qty } — nothing was saved';
    end if;
    v_use_qty := true;
  end if;

  -- ── 머리의 원천 (210000 그대로) ──
  if p_doc_kind = 'invoice' then
    if p_po_id is null then
      raise exception 'An invoice starts from a PO — p_po_id is required — nothing was saved';
    end if;
    if p_credit_for_invoice_id is not null then
      raise exception 'p_credit_for_invoice_id is for credit notes only — nothing was saved';
    end if;
  end if;

  if p_credit_for_invoice_id is not null then
    select * into v_for from public.po_invoice where id = p_credit_for_invoice_id;
    if not found then
      raise exception 'Invoice % not found (credit_for) — nothing was saved', p_credit_for_invoice_id;
    end if;
    if v_for.doc_kind <> 'invoice' then
      raise exception 'Credit note cannot be for another credit note (%) — nothing was saved', v_for.invoice_number;
    end if;
    v_supplier_id := v_for.supplier_id; v_currency_id := v_for.currency_id; v_rate := v_for.exchange_rate;
    v_pt_id := v_for.payment_term_id;   v_pt_name := v_for.payment_term_name;   v_source := 'invoice';
    v_tax_id := v_for.tax_rule_id;      v_tax_name := v_for.tax_rule;                                           -- po-tax-1
  end if;

  if p_po_id is not null then
    select * into v_po from public.po where id = p_po_id;
    if not found then
      raise exception 'PO % not found — nothing was saved', p_po_id;
    end if;
    if v_source is null then
      v_supplier_id := v_po.supplier_id; v_currency_id := v_po.currency_id; v_rate := v_po.exchange_rate;
      v_pt_id := v_po.payment_term_id;   v_pt_name := v_po.payment_term_name;   v_source := 'po';
      v_tax_id := v_po.tax_rule_id;      v_tax_name := v_po.tax_rule;                                           -- po-tax-1
    elsif v_po.supplier_id <> v_supplier_id then
      raise exception 'PO % belongs to a different supplier than invoice % — nothing was saved', v_po.po_number, v_for.invoice_number;
    elsif v_po.tax_rule_id is not null and v_tax_id is not null and v_po.tax_rule_id <> v_tax_id then
      v_warn := array_append(v_warn, 'tax_rule_differs_between_pos');                                           -- po-tax-1 · 크레딧 축 PO 의 규칙 ≠ credit_for 인보이스의 규칙
    end if;
  end if;

  if v_source is null then
    if p_supplier_id is null then
      raise exception 'A credit note needs one of: p_credit_for_invoice_id, p_po_id or p_supplier_id — nothing was saved';
    end if;
    select * into v_sup from public.supplier where id = p_supplier_id;
    if not found then
      raise exception 'Supplier % not found — nothing was saved', p_supplier_id;
    end if;
    v_supplier_id := v_sup.id; v_pt_id := v_sup.payment_term_id; v_pt_name := v_sup.payment_term_name; v_source := 'supplier';
    v_currency_id := v_sup.currency_id;
    if v_sup.tax_rule is not null then                                                                          -- po-tax-1 · 공급처 이름 → id(활성 purchase · 못 풀면 null + 경고)
      select r.id, r.name into v_tax_id, v_tax_name from public.ref_tax_rule r where r.name = v_sup.tax_rule and r.direction = 'purchase' and r.is_active;
      if v_tax_id is null then v_warn := array_append(v_warn, 'tax_rule_unknown:' || v_sup.tax_rule); end if;
    end if;
    if v_currency_id is null then
      select c.id into v_currency_id from public.ref_currency c join public.inv_config k on k.key = 'base_currency' and k.value = c.code;
      if v_currency_id is null then
        raise exception 'Supplier has no currency and inv_config.base_currency does not point at a ref_currency row — nothing was saved';
      end if;
      v_warn := array_append(v_warn, 'currency_defaulted');
    end if;
  end if;

  select s.name into v_sup_name from public.supplier s where s.id = v_supplier_id;
  select c.code into v_cur_code from public.ref_currency c where c.id = v_currency_id;

  -- ── po-disc-4a1 · 조기 결제 할인 조건 제안 — 인보이스만 · 결제조건(ref_payment_term.discount_percent · discount_days) · 제안일 뿐(P&G 「2%19 Net30」 실제 2.1% · 13일) ──
  if p_doc_kind = 'invoice' and v_pt_id is not null then
    select t.name, t.discount_percent, t.discount_days into v_ed from public.ref_payment_term t where t.id = v_pt_id;
    if found and v_ed.discount_percent is not null and v_ed.discount_percent > 0 then
      v_ed_pct   := v_ed.discount_percent;
      v_ed_basis := 'pre_tax';
      v_ed_until := case when v_ed.discount_days is not null then coalesce(p_invoice_date, public.ims_today()) + v_ed.discount_days end;
      if v_ed_until is null then v_warn := array_append(v_warn, 'early_discount_no_deadline'); end if;
      v_ed_j := jsonb_build_object('pct', v_ed_pct, 'basis', v_ed_basis, 'until', v_ed_until, 'term_name', v_ed.name, 'discount_days', v_ed.discount_days);
    end if;
  end if;

  -- ── ⭐ p_line_qty 검사 넷 — 저장 전에 · 미리 보기에서도 같은 판정 ──
  if v_use_qty then
    -- ③ 그 PO 의 라인이 아닌 키(uuid 가 아닌 키도 여기서 걸린다 — ::uuid 가 invalid_text_representation 을 낸다 · 아래 exception 절이 읽을 문장으로)
    select count(*), string_agg(k.key, ', ' order by k.key) into v_bad_n, v_bad_txt
    from jsonb_each_text(p_line_qty) k
    where not exists (select 1 from public.po_line l where l.id = k.key::uuid and l.po_id = p_po_id);
    if v_bad_n > 0 then
      raise exception 'p_line_qty has % key(s) that are not lines of PO % (%) — nothing was saved', v_bad_n, v_po.po_number, v_bad_txt;
    end if;
    -- ② 숫자 아님 · 음수  ① 미청구 초과  — 라인 번호·SKU·수량을 문장에
    for r in
      select u.line_no, u.sku, u.remaining_qty, k.value as raw
      from jsonb_each_text(p_line_qty) k
      join public.po_uninvoiced_lines(p_po_id) u on u.po_line_id = k.key::uuid
      order by u.line_no
    loop
      if r.raw is null then continue; end if;                                   -- null 값 = 0 과 같다(줄 없음)
      if r.raw !~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then
        raise exception 'Line % (%) of PO %: requested quantity "%" is not a number — nothing was saved', r.line_no, r.sku, v_po.po_number, r.raw;
      end if;
      v_req := r.raw::numeric;
      if v_req < 0 then
        raise exception 'Line % (%) of PO %: requested quantity % is negative — nothing was saved', r.line_no, r.sku, v_po.po_number, v_req;
      end if;
      if v_req > r.remaining_qty then
        -- ⚠️ 넘겨 받으면 다음 장의 remaining 이 음수가 되고 초과 입고의 음수와 같은 모양이라 사후 구별이 안 된다(§11-b · po_line_update 와 같은 이유)
        raise exception 'Line % (%) of PO %: requested % EA but only % EA remain uninvoiced — nothing was saved', r.line_no, r.sku, v_po.po_number, v_req, r.remaining_qty;
      end if;
    end loop;
    -- ④ 남길 줄이 하나도 없다(전부 0·null) — 줄 0개 인보이스는 확정이 어차피 막는다 · 만들기에서 막아 못 쓰는 문서를 안 남긴다
    select count(*) into v_keep_n
    from jsonb_each_text(p_line_qty) k
    where k.value is not null and k.value ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' and k.value::numeric > 0;
    if v_keep_n = 0 then
      raise exception 'p_line_qty leaves no line to invoice on PO % — give at least one quantity above 0 — nothing was saved', v_po.po_number;
    end if;
    select coalesce(sum(k.value::numeric), 0) into v_req_total
    from jsonb_each_text(p_line_qty) k
    where k.value is not null and k.value ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$';
  end if;

  -- ── ⭐ 크레딧 — 번호의 축(credit_po_id)과 번호 (210000 그대로) ──
  if p_doc_kind = 'credit' then
    if p_po_id is not null then
      v_credit_po_id := v_po.id;
    elsif p_credit_for_invoice_id is not null then
      select count(distinct pl.po_id), (array_agg(distinct pl.po_id))[1] into v_po_n, v_credit_po_id
      from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id
      where il.po_invoice_id = p_credit_for_invoice_id;
      if coalesce(v_po_n, 0) > 1 then
        v_credit_po_id := null;
        v_warn := array_append(v_warn, 'credit_po_ambiguous');
      end if;
    end if;
    if v_credit_po_id is not null then
      select po_number into v_credit_po_number from public.po where id = v_credit_po_id;
    end if;

    if v_num is null then
      v_num := public.po_credit_next_number(v_credit_po_id, extract(year from coalesce(p_invoice_date, public.ims_today()))::int);
      v_num_src := case when v_credit_po_id is not null then 'auto_po' else 'auto_year' end;
      if not p_commit then v_warn := array_append(v_warn, 'number_is_provisional'); end if;
    else
      v_num_src := 'given';
      v_warn := array_append(v_warn, 'credit_number_manual');
    end if;
  else
    v_num_src := 'given';
  end if;

  -- ── 번호 중복 — 미리 보기는 경고 · commit 은 읽을 문장으로 거부 (그대로) ──
  select count(*) into v_exists from public.po_invoice
   where supplier_id = v_supplier_id and doc_kind = p_doc_kind and invoice_number = v_num;
  if v_exists > 0 then
    if p_commit then
      raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, v_sup_name;
    end if;
    v_warn := array_append(v_warn, 'invoice_number_exists');
  end if;
  if p_total_amount is null then v_warn := array_append(v_warn, 'total_amount_missing'); end if;
  if v_tax_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;                          -- po-tax-1 · 머리 규칙 없음(세금 0 으로 계산된다 · 초안에서 고른다)
  if p_doc_kind = 'credit' and p_due_date is not null then v_warn := array_append(v_warn, 'due_date_on_credit'); end if;

  -- ── commit: 머리 한 행 (그대로) ──
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then
      raise exception 'No active staff record for this login — nothing was saved';
    end if;
    insert into public.po_invoice (supplier_id, doc_kind, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name,
                                   currency_id, exchange_rate, total_amount, status, created_by, credit_for_invoice_id, credit_po_id, tax_rule_id, tax_rule,
                                   early_discount_pct, early_discount_basis, early_discount_until)   -- po-disc-4a1
    values (v_supplier_id, p_doc_kind, v_num, coalesce(p_invoice_date, public.ims_today()), p_due_date, v_pt_id, v_pt_name,
            v_currency_id, v_rate, coalesce(p_total_amount, 0), 'draft', v_staff, p_credit_for_invoice_id, v_credit_po_id, v_tax_id, v_tax_name,   -- po-tax-1
            v_ed_pct, v_ed_basis, v_ed_until)   -- po-disc-4a1 · 제안값(없으면 null 셋)
    returning id into v_inv_id;
  end if;

  -- ── 줄 ──
  if p_doc_kind = 'invoice' then
    -- ⭐ 바뀐 블록 — p_line_qty 가 있으면 키에 있는 라인만 그 수량으로 · 없으면 미청구 수량 전부(그대로)
    for r in
      select u.*,
             case when v_use_qty then (select nullif(regexp_replace(k.value, '\s', '', 'g'), '')::numeric
                                         from jsonb_each_text(p_line_qty) k where k.key::uuid = u.po_line_id) end as requested_qty,
             case when v_use_qty then (p_line_qty ? u.po_line_id::text) end as in_keys
      from public.po_uninvoiced_lines(p_po_id) u
    loop
      v_n := v_n + 1; v_msgs := '{}'; v_qty := null; v_full := false;
      v_req := case when v_use_qty and coalesce(r.in_keys, false) then coalesce(r.requested_qty, 0) end;   -- 준 값(null 값은 0)
      if r.remaining_qty <= 0 then
        -- 청구할 것이 없다 — 사실이 더 세다(키에 있고 0 이든 없든 · 0 초과는 위 ① 이 이미 막았다)
        v_verdict := 'fully_invoiced';
        v_msgs := array_append(v_msgs, case when r.remaining_qty < 0 then 'over-invoiced — check earlier invoices' else 'nothing left to invoice' end);
      elsif v_use_qty and coalesce(v_req, 0) = 0 then
        -- ⭐ 이번 인보이스에 안 실렸다(키에 없음 · 0 · null) — 줄 없음 · lines[] 에는 담는다
        v_verdict := 'skipped'; v_skip := v_skip + 1;
        v_msgs := array_append(v_msgs, case when coalesce(r.in_keys, false) then 'requested 0 — not on this invoice' else 'not in p_line_qty — not on this invoice' end);
      else
        v_verdict := 'ok'; v_ok := v_ok + 1;
        v_qty := case when v_use_qty then v_req else r.remaining_qty end;
        v_full := (v_qty = r.qty_ea);                                          -- 단위 칸 넷은 주문 수량과 같을 때만(그대로)
        if r.invoiced_qty > 0 then v_msgs := array_append(v_msgs, format('%s already invoiced on other invoice(s) — remaining %s', r.invoiced_qty, r.remaining_qty)); end if;
        if v_use_qty and v_qty < r.remaining_qty then v_msgs := array_append(v_msgs, format('requested %s of %s remaining', v_qty, r.remaining_qty)); end if;
        if not v_full then v_msgs := array_append(v_msgs, 'partial — entered unit reset to EA'); end if;
        if p_commit then
          v_ins := v_ins + 1;
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable,
                                              entered_unit_product_id, entered_qty, entered_pack_factor, tax_rule_id)
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true,
                  case when v_full then r.entered_unit_product_id end,
                  case when v_full then r.entered_qty end,
                  case when v_full then r.entered_pack_factor end,
                  (select pl.tax_rule_id from public.po_line pl where pl.id = r.po_line_id));                   -- po-tax-1 · PO 줄 예외 규칙을 물려받는다(null = 머리) · 짝 트리거가 이름을 채운다
        end if;
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', v_po.po_number, 'po_line_no', r.line_no, 'sku', r.sku,
        'qty_ordered', r.qty_ea, 'invoiced_qty', r.invoiced_qty, 'remaining_qty', r.remaining_qty,
        'requested_qty', v_req,                                                                   -- ⭐ 새 · 준 값(안 줬으면 null)
        'qty_ea', v_qty, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
        'line_no', case when v_verdict = 'ok' then (case when p_commit then v_ins else v_ok end) end,
        'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
    end loop;
    if v_ok = 0 then v_warn := array_append(v_warn, 'no_uninvoiced_lines'); end if;       -- p_line_qty 가 있으면 ④ 가 먼저 막아 여기 안 온다

    if p_copy_discounts then
      for r in select d.seq, d.name, d.percent, d.supplier_discount_id from public.po_discount d where d.po_id = p_po_id order by d.seq loop
        v_disc_n := v_disc_n + 1;
        if p_commit then
          insert into public.po_invoice_discount (po_invoice_id, seq, name, percent, supplier_discount_id)
          values (v_inv_id, r.seq, r.name, r.percent, r.supplier_discount_id);
        end if;
        v_discs := v_discs || jsonb_build_object('seq', r.seq, 'name', r.name, 'percent', r.percent, 'supplier_discount_id', r.supplier_discount_id, 'inserted', p_commit);
      end loop;
      if v_disc_n > 0 then v_warn := array_append(v_warn, 'discounts_copied_from_po'); end if;
    end if;

  elsif p_credit_for_invoice_id is not null then
    -- 크레딧 (210000 그대로)
    for r in
      select il.po_line_id, il.qty_ea as invoice_qty, il.unit_price, pl.line_no as po_line_no, x.po_number, pr.sku, il.tax_rule_id,
             coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = il.po_line_id), 0) as received_qty,
             (select count(distinct x2.po_invoice_id) from public.po_invoice_line x2 join public.po_invoice i2 on i2.id = x2.po_invoice_id
               where x2.po_line_id = il.po_line_id and x2.line_kind = 'goods' and i2.doc_kind = 'invoice' and i2.status <> 'cancelled'
                 and i2.id <> p_credit_for_invoice_id)::int as other_invoices
      from public.po_invoice_line il
      join public.po_line pl on pl.id = il.po_line_id
      join public.po x on x.id = pl.po_id
      join public.product pr on pr.id = pl.product_id
      where il.po_invoice_id = p_credit_for_invoice_id and il.line_kind = 'goods'
      order by il.line_no
    loop
      v_n := v_n + 1; v_msgs := '{}'; v_qty := r.invoice_qty - r.received_qty;
      if r.other_invoices > 0 then v_msgs := array_append(v_msgs, format('line_has_other_invoices (%s) — difference may belong to another invoice', r.other_invoices)); end if;
      if v_qty > 0 then
        v_verdict := 'ok'; v_ok := v_ok + 1;
        if p_commit then
          v_ins := v_ins + 1;
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable, tax_rule_id)
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true, r.tax_rule_id);           -- po-tax-1 · 인보이스 줄 규칙 그대로
        end if;
      elsif v_qty = 0 then
        v_verdict := 'no_difference'; v_msgs := array_append(v_msgs, 'invoiced = received');
      else
        v_verdict := 'over_received'; v_msgs := array_append(v_msgs, 'received more than invoiced — not a credit (§11-i difference)');
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', r.po_number, 'po_line_no', r.po_line_no, 'sku', r.sku,
        'invoice_qty', r.invoice_qty, 'received_qty', r.received_qty, 'diff_qty', v_qty,
        'qty_ea', case when v_verdict = 'ok' then v_qty end, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
        'line_no', case when v_verdict = 'ok' then (case when p_commit then v_ins else v_ok end) end,
        'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
    end loop;
    if v_ok = 0 then v_warn := array_append(v_warn, 'no_qty_difference'); end if;
  end if;

  return jsonb_build_object(
    'committed', p_commit, 'id', v_inv_id, 'doc_kind', p_doc_kind,
    'invoice_number', v_num, 'number_source', v_num_src,
    'credit_po_id', v_credit_po_id, 'credit_po_number', v_credit_po_number,
    'header_source', v_source,
    'supplier_id', v_supplier_id, 'supplier_name', v_sup_name, 'currency_id', v_currency_id, 'currency_code', v_cur_code,
    'payment_term_name', v_pt_name, 'total_amount', coalesce(p_total_amount, 0),
    'early_discount_suggested', v_ed_j,                                                                        -- po-disc-4a1 · {pct, basis, until, term_name, discount_days} | null
    'tax_rule_id', v_tax_id, 'tax_rule', v_tax_name,                                                            -- po-tax-1
    'line_count', case when p_commit then v_ins else v_ok end,
    'skipped_count', v_skip,                                                      -- ⭐ 새 · 이번에 뺀 라인 수(p_line_qty 없으면 0)
    'requested_total', v_req_total,                                               -- ⭐ 새 · 준 수량의 합(p_line_qty 없으면 null)
    'lines', v_lines,
    'discounts', v_discs, 'discounts_copied', v_disc_n,
    'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, coalesce(v_sup_name, 'this supplier');
  when invalid_text_representation then
    -- p_line_qty 의 키가 uuid 모양이 아니다(k.key::uuid) — 읽을 문장으로
    raise exception 'p_line_qty keys must be po_line_id uuids — one of them is not (%) — nothing was saved', sqlerrm;
end;
$$;

-- ═══ ④ po_invoice_list 재발행 — 마지막 정의 20261008170700:498~537(viewdef md5 3401ace3 · 검증 G0) · 뒤에 여섯 칸 · 옵션 · 권한 유지 ═══
create or replace view public.po_invoice_list
  with (security_invoker = true) as
with pos as (
  select il.po_invoice_id,
         count(distinct pl.po_id)::int                                   as po_count,
         string_agg(distinct x.po_number, ' ' order by x.po_number)      as po_numbers
  from public.po_invoice_line il
  join public.po_line pl on pl.id = il.po_line_id
  join public.po x on x.id = pl.po_id
  group by il.po_invoice_id
)
select
  i.id, i.doc_kind, i.invoice_number, i.invoice_date, i.due_date, i.status,
  i.supplier_id, s.name as supplier_name,
  i.currency_id, cur.code as currency_code, i.exchange_rate,
  i.payment_term_name,
  i.total_amount,
  round(m.factor, 6)      as discount_factor,
  m.computed_total, m.diff, m.payable_net,
  m.alloc_total,
  m.credit_total, m.unpaid, m.remaining,
  m.line_count,
  coalesce(pos.po_count, 0) as po_count,
  pos.po_numbers,
  i.credit_for_invoice_id, f.invoice_number as credit_for_number,
  i.confirmed_at, i.cancelled_at, i.note, i.created_at, i.updated_at,
  -- ── 새 3칸 (2026-09-16 저녁) ──
  i.supplier_ref_number,                              -- 공급처가 보내온 크레딧 노트 번호(참조) · 검색 .or 에 한 항 더
  i.credit_po_id,                                     -- 번호를 낸 발주(채번의 축)
  cp.po_number as credit_po_number,
  -- ── po-tax-1 · 뒤에 더한 네 칸 ──
  i.tax_rule_id, i.tax_rule,
  m.taxable_amount, m.tax_amount,
  -- ── po-disc-4a1 · 뒤에 더한 여섯 칸 ──
  i.early_discount_pct, i.early_discount_amount, i.early_discount_basis, i.early_discount_until,
  ed.discount as early_discount_value,                -- 조건으로 계산한 할인(문서 통화 · round 2 · 조건 없으면 0) — 식은 po_early_discount_calc 한 곳
  ed.is_valid as early_discount_valid_today           -- 오늘(토론토) 기준 아직 받을 수 있나(조건 없으면 false)
from public.po_invoice i
join public.po_invoice_money m on m.id = i.id
join public.supplier s on s.id = i.supplier_id
join public.ref_currency cur on cur.id = i.currency_id
left join public.po_invoice f on f.id = i.credit_for_invoice_id
left join public.po cp on cp.id = i.credit_po_id
left join pos on pos.po_invoice_id = i.id
cross join lateral public.po_early_discount_calc(case when i.doc_kind = 'invoice' then i.early_discount_pct end, case when i.doc_kind = 'invoice' then i.early_discount_amount end,
                                                 i.early_discount_basis, i.early_discount_until, m.payable_taxable, m.payable_net, null) ed;   -- po-disc-4a1
comment on view public.po_invoice_list is '⑤ 인보이스·크레딧 목록 — PostgREST 로 표처럼(§10-j 3-a). 돈은 po_invoice_money(식 없음) · po_numbers = 줄이 가리키는 발주 번호 모음(검색) · credit_for_number · supplier_ref_number · credit_po_id · credit_po_number. ⭐ [po-tax-1 2026-10-08] 뒤에 네 칸 tax_rule_id · tax_rule(머리 규칙) · taxable_amount(세금 전 계산값) · tax_amount(계산한 세금 · 규칙 모르면 null) — computed_total · diff · payable_net 은 이제 세금 포함. ⭐ [po-disc-4a1 2026-10-09] 뒤에 여섯 칸 early_discount_pct · early_discount_amount · early_discount_basis · early_discount_until(조건 칸 그대로) · early_discount_value(조건으로 계산한 할인 · po_early_discount_calc) · early_discount_valid_today(오늘 기준 유효). security_invoker. 정본 po-module §13-h · §11-g · §11-h';

-- ═══ ⑥ po_payment_alloc_set 재발행 — 마지막 정의 20260918013000:457~506(DB md5 94c873da · 검증 G0) 바이트 복사 + 플래그 3줄 ═══
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
  v_prev   text;                                                -- po-disc-4a1: 문지기 플래그(po.payment_door) 전 값
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

  v_prev := current_setting('po.payment_door', true);  perform set_config('po.payment_door', '1', true);   -- po-disc-4a1: 이 창구의 쓰기만 문지기를 지난다
  if v_id is not null then
    update public.po_payment_alloc set amount = p_amount, note = coalesce(p_note, note) where id = v_id;
    get diagnostics v_n = row_count;                            -- ②-b
    if v_n = 0 then raise exception 'Allocation line % on payment % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_id, coalesce(v_pay.reference, p_payment_id::text); end if;
  else
    insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note)
    values (p_payment_id, case when p_kind = 'invoice' then p_target_id end, case when p_kind = 'charge' then p_target_id end, p_amount, p_note)
    returning id into v_id;
  end if;

  perform set_config('po.payment_door', coalesce(v_prev, ''), true);                                        -- po-disc-4a1
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

-- ═══ ⑥-b po_payment_create 재발행 — 마지막 정의 20260924001820:903~1010(DB md5 77dfdde7 · 검증 G0) 바이트 복사 + declare 2 · 옛 모양 호환 블록 · 플래그 2 · 충당 할인 칸 · 반환 allocs[].discount ═══
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
  v_prev       text;                                           -- po-disc-4a1: 문지기 플래그 전 값
  v_adisc      numeric;                                        -- po-disc-4a1: 충당 줄의 할인(옛 모양 p_discount_taken → 대상 하나에)
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
                                               'doc_total', t.doc_total, 'doc_paid_before', t.doc_paid, 'doc_unpaid_before', t.doc_unpaid, 'amount', v_amt, 'note', v_note, 'inserted', p_commit,
                                               'discount', case when v_disc > 0 then v_disc else 0 end);   -- po-disc-4a1 · 이 문서의 할인(대상 하나일 때 p_discount_taken 그대로 · 둘 이상이면 위에서 거부)
  end loop;

  -- ── po-disc-4a1(판정 391 · 이견 1) · 옛 모양 호환 — 할인은 문서별(충당 칸)이 정본 · p_discount_taken 은 대상이 하나일 때만 그 문서에 · 둘 이상이면 거부 · 원소의 discount 열쇠는 ④-a2 부터(조용히 지나치지 않는다) ──
  if exists (select 1 from jsonb_array_elements(coalesce(p_targets, '[]'::jsonb)) e where e ? 'discount') then
    raise exception 'A discount per document (p_targets[].discount) arrives with the next payment-window update — for now give the discount once as p_discount_taken on a payment with one document — nothing was saved';
  end if;
  if v_disc > 0 and jsonb_array_length(v_allocs) > 1 then
    raise exception 'Say which document the discount of % belongs to — a payment that settles % documents cannot carry one discount for all of them; pay the discounted document on its own payment — nothing was saved', v_disc, jsonb_array_length(v_allocs);
  end if;
  v_adisc := case when v_disc > 0 then v_disc else 0 end;

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
    v_prev := current_setting('po.payment_door', true);  perform set_config('po.payment_door', '1', true);   -- po-disc-4a1: 이 창구의 쓰기만 문지기를 지난다
    insert into public.po_payment (paid_on, amount, currency_id, account_id, reference, discount_taken, paid_by, note)
    values (coalesce(p_paid_on, public.ims_today()), p_amount, p_currency_id, p_account_id, p_reference, v_disc, v_staff, p_note)
    returning id into v_pay_id;
    for r in select * from jsonb_array_elements(v_allocs) loop
      insert into public.po_payment_alloc (po_payment_id, po_invoice_id, po_charge_id, amount, note, discount_amount)   -- po-disc-4a1 · 충당 할인(정본 · Σ 트리거가 discount_taken 을 맞춘다)
      values (v_pay_id,
              case when r->>'kind' = 'invoice' then (r->>'id')::uuid end,
              case when r->>'kind' = 'charge'  then (r->>'id')::uuid end,
              (r->>'amount')::numeric, r->>'note', v_adisc);
    end loop;
    perform set_config('po.payment_door', coalesce(v_prev, ''), true);                                       -- po-disc-4a1
  end if;

  return jsonb_build_object(
    'committed', p_commit, 'payment_id', v_pay_id, 'paid_on', coalesce(p_paid_on, public.ims_today()),
    'amount', p_amount, 'discount_taken', v_disc, 'currency_id', p_currency_id, 'currency_code', v_cur_code,
    'supplier_id', v_sup_id, 'supplier_name', v_sup_name,
    'account_code', v_acc_code, 'account_name', v_acc_name,
    'alloc_sum', v_sum, 'gap', v_gap, 'allocs', v_allocs, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑦ po_payment_detail 재발행 — 마지막 정의 20261008174126:662~724(DB md5 612d5faa · 검증 G0) · allocs[].discount_amount · early_discount_until · money.discount_sum · 경고 paid_on_after_discount_deadline ═══
create or replace function public.po_payment_detail(p_payment_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with p as (
  select * from public.po_payment where id = p_payment_id
),
al as (
  select pa.id as alloc_id, pa.amount, pa.note, pa.discount_amount, i.early_discount_until,                                                -- po-disc-4a1 · 충당 할인 · 그 인보이스의 할인 기한
         case when pa.po_charge_id is not null then 'charge' else 'invoice' end                  as target_kind,
         coalesce(pa.po_invoice_id, pa.po_charge_id)                                             as target_id,
         coalesce(i.invoice_number, c.charge_number)                                             as target_number,
         coalesce(i.status, c.status)                                                            as target_status,
         coalesce(i.supplier_id, c.supplier_id)                                                  as supplier_id,
         s.name                                                                                  as supplier_name,
         coalesce(i.currency_id, c.currency_id)                                                  as doc_currency_id,
         cur.code                                                                                as currency_code,
         case when pa.po_charge_id is not null then cm.total_with_tax else im.payable_net end    as doc_total,        -- 인보이스 payable_net · 비용 total_with_tax(po-tax-2 · 세금 포함)
         case when pa.po_charge_id is not null then cm.paid         else im.alloc_total end      as doc_paid_total,   -- 그 문서에 붙은 모든 결제의 충당 합
         case when pa.po_charge_id is not null then cm.unpaid       else im.unpaid end           as doc_unpaid
  from public.po_payment_alloc pa
  left join public.po_invoice i on i.id = pa.po_invoice_id
  left join public.po_invoice_money im on im.id = pa.po_invoice_id
  left join public.po_charge c on c.id = pa.po_charge_id
  left join public.po_charge_money cm on cm.id = pa.po_charge_id
  left join public.supplier s on s.id = coalesce(i.supplier_id, c.supplier_id)
  left join public.ref_currency cur on cur.id = coalesce(i.currency_id, c.currency_id)
  where pa.po_payment_id = p_payment_id
),
m as (
  select p.amount, p.discount_taken, coalesce((select sum(amount) from al), 0) as alloc_sum, coalesce((select sum(discount_amount) from al), 0) as discount_sum,   -- po-disc-4a1
         p.amount + p.discount_taken - coalesce((select sum(amount) from al), 0) as gap
  from p
)
select case when not exists (select 1 from p) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', p.id, 'paid_on', p.paid_on, 'amount', p.amount, 'discount_taken', p.discount_taken,
      'currency_id', p.currency_id, 'currency_code', cur.code, 'exchange_rate', p.exchange_rate,
      'account_id', p.account_id, 'account_code', acc.code, 'account_name', acc.name,
      'reference', p.reference, 'paid_by', p.paid_by, 'paid_by_name', st.name, 'note', p.note, 'created_at', p.created_at, 'updated_at', p.updated_at)
    from p
    join public.ref_currency cur on cur.id = p.currency_id
    left join public.ref_account acc on acc.id = p.account_id
    left join public.ims_staff st on st.id = p.paid_by
  ),
  'money', (select jsonb_build_object('amount', m.amount, 'discount_taken', m.discount_taken, 'alloc_sum', m.alloc_sum, 'gap', m.gap, 'discount_sum', m.discount_sum) from m),   -- po-disc-4a1
  'allocs', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'target_kind', target_kind, 'target_id', target_id, 'target_number', target_number, 'target_status', target_status,
                                        'supplier_id', supplier_id, 'supplier_name', supplier_name, 'currency_code', currency_code, 'amount', amount, 'note', note, 'discount_amount', discount_amount, 'early_discount_until', early_discount_until,   -- po-disc-4a1
                                        'doc_total', doc_total, 'doc_paid_total', doc_paid_total, 'doc_unpaid', doc_unpaid)
                     order by target_kind, target_number)
    from al), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when m.gap <> 0 then 'gap_not_zero' end,
        case when not exists (select 1 from al) then 'no_allocs' end,
        case when exists (select 1 from al where al.doc_currency_id <> p.currency_id) then 'mixed_currency' end,
        case when exists (select 1 from al where al.target_status <> 'confirmed') then 'alloc_on_unconfirmed_doc' end,
        case when (select count(distinct supplier_id) from al) > 1 then 'mixed_supplier' end,
        case when exists (select 1 from al where al.discount_amount > 0 and al.early_discount_until is not null and al.early_discount_until < p.paid_on) then 'paid_on_after_discount_deadline' end   -- po-disc-4a1(이견 11): 기한 뒤 결제인데 할인을 받았다 — 사건은 그대로 · 사람이 본다
      ], null)) as w
      from p cross join m) t
  )
) end;
$$;

-- ═══ ⑧ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice' and column_name like 'early\_discount\_%') <> 4 then v_bad := v_bad || ' po_invoice-columns'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_payment_alloc' and column_name = 'discount_amount') <> 1 then v_bad := v_bad || ' alloc-column'; end if;
  if (select count(*) from pg_constraint where conrelid = 'public.po_invoice'::regclass and conname like 'po_invoice_early_%') <> 5 then v_bad := v_bad || ' early-checks'; end if;
  if (select count(*) from pg_trigger where not tgisinternal and tgname in ('po_invoice_early_lock', 'po_payment_guard', 'po_payment_alloc_guard', 'po_payment_alloc_discount_sync')) <> 4 then v_bad := v_bad || ' triggers'; end if;
  foreach v_t in array array['public.po_early_discount_calc(numeric, numeric, text, date, numeric, numeric, date)', 'public.po_invoice_early_discount(uuid, date)'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  foreach v_t in array array['public.po_invoice_early_lock()', 'public.po_payment_alloc_discount_sync()', 'public.po_payment_guard()', 'public.po_payment_alloc_guard()'] loop
    if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice_list') <> 44 then v_bad := v_bad || ' po_invoice_list(columns)'; end if;
  if has_table_privilege('anon', 'public.po_invoice_list', 'select') or not has_table_privilege('authenticated', 'public.po_invoice_list', 'select') then v_bad := v_bad || ' po_invoice_list(grants)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_invoice_create', 'po_payment_create', 'po_payment_alloc_set', 'po_payment_detail') and p.prosrc like '%po-disc-4a1%') <> 4 then v_bad := v_bad || ' reissued-four'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('po_payment_alloc_delete', 'po_doc_delete', 'po_payment_target_check', 'inv_layer_post_cost_adjust', 'inv_cost_adjust_reverse', 'po_receipt_confirm_by') and p.prosrc like '%po-disc-4a1%') <> 0 then v_bad := v_bad || ' untouched-functions-touched'; end if;
  if md5(pg_get_viewdef('public.po_invoice_money'::regclass)) <> '08f428cbc4a0534df0eaa08ade03aa38' or md5(pg_get_viewdef('public.po_charge_money'::regclass)) <> 'd6c4df0854de8f3e515286ff6d82b1f2' then v_bad := v_bad || ' money-views-changed'; end if;
  if exists (select 1 from public.po_payment p left join (select po_payment_id, sum(discount_amount) as s from public.po_payment_alloc group by po_payment_id) q on q.po_payment_id = p.id where p.discount_taken is distinct from coalesce(q.s, 0)) then v_bad := v_bad || ' discount-sum'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM395', message = format('STOP - po-disc-4a1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
