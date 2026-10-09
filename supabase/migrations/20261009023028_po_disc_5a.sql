-- ─────────────────────────────────────────────────────────────
-- 공급처 할인 → 재고 원가 ⑤-a — 가격 크레딧 → 원가(판정 400): 크레딧 goods 줄마다 credit_reason(not_received | price_difference) · 제안 식 한 곳 · 확정 때 price_difference 줄마다 원가 사건(kind price_adjust · source_type po_credit · 환율 = 핀 가중) · 다시 열기 · 취소는 되돌림 · 복구는 다시 만들기 (Asung-IMS · po-disc-5a · 2026-10-09)
--   정본(뒤에 적는다): so-module §53 판정 392 · 396 · 398 · 399 · 400(2026-10-08 · Caleb) · po-module §11-g 「크레딧 노트」
--   판정 400  Not received(안 온 물건 · 원가 무변) / Price difference(받은 물건의 원가를 낮춘다) — 시스템이 제안(자동 채운 줄 = not_received · 사람이 더한 줄 = 남은 「청구 − 입고 − 이미 not_received 로 확정한 크레딧」 기준) · 직원이 초안에서 바꾼다 · 확정 때 goods 줄마다 not null
--   ⬜1 걸치는 줄 — 초안은 경고 credit_line_spans_both · 확정은 거부(not_received qty > 남은 안 온 수량 → 「split the line」) · 자동으로 줄을 나누지 않는다
--   ⬜2 환율 = 핀(po_receipt_cost)의 환율 — 핀 여럿 · 환율 다르면 레이어 수량 가중 + 경고 credit_fx_mixed · 핀 없음(입고 0)이면 po_invoice_line_cost 출처 + 경고 credit_fx_unpinned(비기준통화만)
--   ⬜3 가격 차액 수량 > 받은 수량 — 경고 price_credit_qty_above_received 만(입고 전 가격 크레딧은 정상 흐름 · 레이어 없으면 pending → 입고 확정 ⓖ)
--   ⬜6 원가 몫 = qty × unit_price × 크레딧 자신의 할인 체인(po_invoice_discount_factor) · 세금 전 · round 2(문서 통화)
--   이견 1  po_invoice_confirm · po_doc_cancel 을 security definer 로(문은 첫 줄 그대로) — 속 함수(po_credit_cost_events · po_credit_cost_reverse)를 부른다
--   이견 2  취소는 되돌림 · 복구가 confirmed 로 돌아오면 사건을 다시 만든다 · 이견 3  사건 단위 = 크레딧 줄(source_id = 줄 id · source_number = 크레딧 번호)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 여섯 — po_invoice_create(20261009011457:199~ · 자동 줄 reason) · po_invoice_line_add(20261008170700:1544~1615) · po_invoice_line_update(1618~1688) · po_invoice_detail(824~965) · po_invoice_confirm(20260930021142:37~246) · po_doc_cancel(20261008234826:381~606)
--   원칙 1: IMS 는 Cin7 없이 돈다 — 원가 사건의 재료는 IMS 크레딧 · IMS 핀
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

-- ═══ ① 칸 credit_reason — 크레딧 goods 줄만(다른 행을 보는 조건이라 트리거) · 값 CHECK ═══
alter table public.po_invoice_line
  add column credit_reason text,
  add constraint po_invoice_line_credit_reason_ck check (credit_reason is null or credit_reason in ('not_received', 'price_difference'));
comment on column public.po_invoice_line.credit_reason is 'po-disc-5a ⭐ 크레딧 goods 줄의 뜻(판정 400 · 2026-10-09) — not_received(안 온 물건 · 원가 무변) | price_difference(받은 물건의 원가를 낮춘다 · 확정 때 PO 줄 사건 price_adjust) · 인보이스 줄 · goods 아닌 줄은 null(트리거 po_invoice_line_credit_reason_guard) · 제안 po_credit_reason_suggest · 확정 때 goods 줄마다 not null(po_invoice_confirm 거부) · 초안에서만 고친다(po_invoice_line_add · _update)';
create function public.po_invoice_line_credit_reason_guard() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare v_kind text;
begin
  if new.credit_reason is null then return new; end if;
  select i.doc_kind into v_kind from public.po_invoice i where i.id = new.po_invoice_id;
  if v_kind is distinct from 'credit' or new.line_kind <> 'goods' then
    raise exception 'credit_reason belongs to goods lines of a credit note only (line % is % on a% document) — nothing was saved', new.line_no, new.line_kind, case when v_kind = 'credit' then ' credit' else 'n invoice' end;
  end if;
  return new;
end;
$$;
revoke all on function public.po_invoice_line_credit_reason_guard() from public, anon, authenticated;
create trigger po_invoice_line_credit_reason_guard before insert or update of credit_reason, line_kind, po_invoice_id on public.po_invoice_line for each row execute function public.po_invoice_line_credit_reason_guard();

-- ═══ ② 제안 식 한 곳 — 남은 안 온 수량 = Σ확정 인보이스 goods 청구 − Σ입고 − Σ(확정 크레딧 + 이 크레딧의 다른 줄)의 not_received · 제안 = 남은 수량이 줄의 절반 이상이면 not_received · 아니면 price_difference · 걸침 = 0 < 남은 < qty ═══
create function public.po_credit_reason_suggest(p_credit_id uuid, p_po_line_id uuid, p_qty numeric, p_exclude_line_id uuid default null)
  returns table (suggested text, billed_qty numeric, received_qty numeric, credited_not_received_qty numeric, not_received_left numeric, spans_both boolean)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with b as (
    select coalesce((select sum(il.qty_ea) from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                      where il.po_line_id = p_po_line_id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'), 0) as billed,
           coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = p_po_line_id), 0) as received,
           coalesce((select sum(cl.qty_ea) from public.po_invoice_line cl join public.po_invoice c on c.id = cl.po_invoice_id
                      where cl.po_line_id = p_po_line_id and cl.line_kind = 'goods' and c.doc_kind = 'credit' and cl.credit_reason = 'not_received'
                        and (c.status = 'confirmed' or c.id = p_credit_id) and c.status <> 'cancelled'
                        and (p_exclude_line_id is null or cl.id <> p_exclude_line_id)), 0) as credited
  ), l as (
    select b.*, greatest(b.billed - b.received - b.credited, 0) as left_qty from b
  )
  select case when coalesce(p_qty, 0) <= 0 then null
              when l.left_qty >= coalesce(p_qty, 0) / 2 then 'not_received' else 'price_difference' end as suggested,
         l.billed, l.received, l.credited, l.left_qty,
         (coalesce(p_qty, 0) > 0 and l.left_qty > 0 and l.left_qty < p_qty) as spans_both
  from l
$$;
revoke all on function public.po_credit_reason_suggest(uuid, uuid, numeric, uuid) from public, anon;
grant execute on function public.po_credit_reason_suggest(uuid, uuid, numeric, uuid) to authenticated;
comment on function public.po_credit_reason_suggest(uuid, uuid, numeric, uuid) is 'po-disc-5a ⭐ 크레딧 줄 뜻 제안 식 한 곳(판정 400) — 남은 안 온 수량 = Σ확정 인보이스 goods 청구 − Σ입고 − Σ(확정 크레딧 · 이 크레딧의 다른 줄)의 not_received(p_exclude_line_id 는 자기 줄) · 제안 = 남은 ≥ qty/2 → not_received · 아니면 price_difference · spans_both = 0 < 남은 < qty(⬜1 초안 경고 · 확정은 po_invoice_confirm 이 not_received 줄에 거부) · po_invoice_line_add · po_invoice_detail · po_invoice_confirm 이 부른다';

-- ═══ ④ 속 함수 — 크레딧의 price_difference goods 줄마다 원가 사건(kind price_adjust · target po_line · source_type po_credit · source_id 줄 · 환율 = 핀 가중) · p_post 면 곧바로 얹는다(레이어 없으면 pending · 399 거부는 예외 = 확정 전체 안 저장) ═══
create function public.po_credit_cost_events(p_credit_id uuid, p_post boolean default true) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare
  c_version  constant text := 'po_credit_cost_events@2026-10-09.1';
  v_c        public.po_invoice%rowtype;
  v_cur      text;  v_base text;
  v_factor   numeric;
  v_staff    uuid;
  v_l        record;
  v_px       record;
  v_lc       record;
  v_fx       numeric;  v_fx_src text;
  v_amt      numeric;
  v_recv     numeric;
  v_id       uuid;
  v_j        jsonb;
  v_events   jsonb := '[]'::jsonb;
  v_warn     text[] := '{}';
begin
  select * into v_c from public.po_invoice where id = p_credit_id;
  if not found or v_c.doc_kind <> 'credit' then raise exception 'Credit note % not found — no cost was changed', p_credit_id; end if;
  if exists (select 1 from public.inv_cost_adjust j join public.po_invoice_line cl on cl.id = j.source_id
              where j.source_type = 'po_credit' and cl.po_invoice_id = p_credit_id and not exists (select 1 from public.inv_cost_adjust r where r.reverses_id = j.id)) then
    raise exception 'Credit note % already has cost events — they are reversed on Reopen or Cancel, not re-made — no cost was changed', v_c.invoice_number;
  end if;
  select c.code into v_cur from public.ref_currency c where c.id = v_c.currency_id;
  select k.value into v_base from public.inv_config k where k.key = 'base_currency';
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  v_factor := public.po_invoice_discount_factor(p_credit_id);                                                    -- ⬜6 크레딧 자신의 체인만
  for v_l in
    select cl.id, cl.line_no, cl.po_line_id, cl.qty_ea, cl.unit_price, pr.sku, x.po_number
      from public.po_invoice_line cl join public.po_line pl on pl.id = cl.po_line_id join public.product pr on pr.id = pl.product_id join public.po x on x.id = pl.po_id
     where cl.po_invoice_id = p_credit_id and cl.line_kind = 'goods' and cl.credit_reason = 'price_difference' and cl.is_payable and cl.qty_ea > 0 and cl.unit_price > 0
     order by cl.line_no
  loop
    v_amt := round(v_l.qty_ea * v_l.unit_price * v_factor, 2);
    if v_amt = 0 then continue; end if;
    -- ⬜2 환율: 핀(그 PO 줄의 레이어를 세운 환율) · 레이어 수량 가중 · 섞이면 경고 · 핀 없으면 줄의 출처(크레딧 → 같은 통화 PO) + 경고(비기준통화만)
    select count(*) as n, count(distinct coalesce(k.exchange_rate, 1)) as n_fx, sum(y.qty) as q, sum(coalesce(k.exchange_rate, 1) * y.qty) / nullif(sum(y.qty), 0) as fx, min(k.exchange_rate_source) as src
      into v_px
      from public.po_receipt_cost k join public.po_receipt r on r.id = k.receipt_id join public.inv_layer y on y.doc_number = r.receipt_number and y.line_ref = k.po_line_id::text and y.origin_type = 'purchase'
     where k.po_line_id = v_l.po_line_id;
    if v_cur is not distinct from v_base then
      v_fx := null; v_fx_src := null;
    elsif coalesce(v_px.n, 0) > 0 then
      v_fx := v_px.fx; v_fx_src := 'pinned';
      if v_px.n_fx > 1 then v_warn := array_append(v_warn, 'credit_fx_mixed:' || v_l.line_no); end if;
    else
      select c.exchange_rate, c.exchange_rate_source, c.net_unit_cad into v_lc from public.po_invoice_line_cost(v_l.id) c;
      if v_lc.net_unit_cad is null then
        raise exception 'Credit note % line % (%) is in % but no exchange rate is known (no receipt yet, none on the credit note or the PO) — enter the rate on the credit note first — nothing was saved', v_c.invoice_number, v_l.line_no, v_l.sku, coalesce(v_cur, '?');
      end if;
      v_fx := v_lc.exchange_rate; v_fx_src := v_lc.exchange_rate_source;
      v_warn := array_append(v_warn, 'credit_fx_unpinned:' || v_l.line_no);
    end if;
    select coalesce(sum(rl.qty_ea), 0) into v_recv from public.po_receipt_line rl where rl.po_line_id = v_l.po_line_id;
    if v_l.qty_ea > v_recv then v_warn := array_append(v_warn, 'price_credit_qty_above_received:' || v_l.line_no); end if;      -- ⬜3 경고만
    insert into public.inv_cost_adjust (kind, target_type, po_line_id, amount_cad, amount_doc, currency_id, exchange_rate, source_type, source_id, source_number, note, created_by, updated_by)
    values ('price_adjust', 'po_line', v_l.po_line_id, -v_amt * coalesce(v_fx, 1), -v_amt, v_c.currency_id, v_fx, 'po_credit', v_l.id, v_c.invoice_number,
            format('price difference credit %s line %s (%s · %s × %s × chain %s · fx %s)', v_c.invoice_number, v_l.line_no, v_l.sku, v_l.qty_ea, v_l.unit_price, v_factor, coalesce(v_fx_src, 'base')), v_staff, v_staff)
    returning id into v_id;
    v_j := null;
    if p_post then v_j := public.inv_layer_post_cost_adjust(v_id); end if;                                       -- 판정 391 · 399 거부는 예외로 올라간다
    v_events := v_events || jsonb_build_object('id', v_id, 'line_no', v_l.line_no, 'po_line_id', v_l.po_line_id, 'po_number', v_l.po_number, 'sku', v_l.sku, 'qty', v_l.qty_ea,
                                               'amount_doc', -v_amt, 'exchange_rate', v_fx, 'exchange_rate_source', v_fx_src, 'amount_cad', -v_amt * coalesce(v_fx, 1), 'received_qty', v_recv,
                                               'status', coalesce(v_j ->> 'status', 'pending'), 'layers', coalesce((v_j ->> 'layers')::int, 0), 'posted_cad', coalesce((v_j ->> 'posted_cad')::numeric, 0));
  end loop;
  return jsonb_build_object('credit_id', p_credit_id, 'credit_number', v_c.invoice_number, 'currency', v_cur, 'factor', v_factor, 'events', v_events, 'event_count', jsonb_array_length(v_events),
                            'posted', p_post, 'warnings', to_jsonb(v_warn), 'builder', c_version);
end;
$$;
revoke all on function public.po_credit_cost_events(uuid, boolean) from public, anon, authenticated;
comment on function public.po_credit_cost_events(uuid, boolean) is 'po-disc-5a ⭐ 크레딧 확정 · 복구의 원가 사건(판정 400 · 392 · 399) — price_difference goods 줄(payable · qty > 0 · 단가 > 0)마다 사건 하나(kind price_adjust · target po_line · source_type po_credit · source_id 줄 · source_number 크레딧 번호) · 몫 = round(qty × 단가 × 크레딧 체인, 2) · 환율 = 핀 가중(섞이면 credit_fx_mixed · 핀 없으면 po_invoice_line_cost + credit_fx_unpinned · 없으면 거부) · qty > 입고 수량이면 price_credit_qty_above_received · 되돌리지 않은 사건이 있으면 거부 · p_post 면 inv_layer_post_cost_adjust(no_layers = pending · 399 거부는 예외) · 부르는 곳 po_invoice_confirm(확정) · po_doc_cancel(복구 → confirmed)';

create function public.po_credit_cost_reverse(p_credit_id uuid, p_note text default null) returns jsonb
language plpgsql
volatile
security definer
set search_path = public, pg_temp
as $$
declare x record; v_r jsonb; v_list jsonb := '[]'::jsonb; v_n int := 0;
begin
  for x in select j.id, j.status from public.inv_cost_adjust j join public.po_invoice_line cl on cl.id = j.source_id
            where j.source_type = 'po_credit' and cl.po_invoice_id = p_credit_id
              and not exists (select 1 from public.inv_cost_adjust r where r.reverses_id = j.id)
            order by cl.line_no, j.created_at, j.id loop
    v_r := public.inv_cost_adjust_reverse(x.id, p_note);
    v_n := v_n + 1;
    v_list := v_list || jsonb_build_object('reverses_id', x.id, 'reversal_id', v_r ->> 'reversal_id', 'was', x.status, 'status', v_r ->> 'status', 'amount_cad', v_r -> 'amount_cad');
  end loop;
  return jsonb_build_object('credit_id', p_credit_id, 'reversed', v_n, 'events', v_list);
end;
$$;
revoke all on function public.po_credit_cost_reverse(uuid, text) from public, anon, authenticated;
comment on function public.po_credit_cost_reverse(uuid, text) is 'po-disc-5a ⭐ 크레딧의 원가 사건(되돌리지 않은 것)을 inv_cost_adjust_reverse 로 되돌린다 — po_invoice_confirm(다시 열기) · po_doc_cancel(취소)이 상태를 바꾸기 전에 부른다(같은 트랜잭션 · posted → 반대 부호 곧바로 · pending → 둘 다 pending)';


-- ═══ ③-a po_invoice_create 재발행 — 마지막 정의 20261009011457:199~(DB md5 eced8864 · 검증 G0) 바이트 복사 + 자동 크레딧 줄 credit_reason not_received · lines[].credit_reason ═══
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
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable, tax_rule_id, credit_reason)   -- po-disc-5a(판정 400): 자동 채운 줄 = not_received
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true, r.tax_rule_id, 'not_received');   -- po-tax-1 · 인보이스 줄 규칙 그대로 · po-disc-5a
        end if;
      elsif v_qty = 0 then
        v_verdict := 'no_difference'; v_msgs := array_append(v_msgs, 'invoiced = received');
      else
        v_verdict := 'over_received'; v_msgs := array_append(v_msgs, 'received more than invoiced — not a credit (§11-i difference)');
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', r.po_number, 'po_line_no', r.po_line_no, 'sku', r.sku,
        'invoice_qty', r.invoice_qty, 'received_qty', r.received_qty, 'diff_qty', v_qty,
        'credit_reason', case when v_verdict = 'ok' then 'not_received' end,                      -- po-disc-5a · 자동 줄의 뜻(사람이 초안에서 바꾼다)
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

-- ═══ ③-b po_invoice_line_add 재발행 — 마지막 정의 20261008170700:1544~1615(DB md5 2b0eed6c) 바이트 복사 + declare 1 · credit_reason 받기 · 제안 블록 · insert 칸 · 반환 키 3 ═══
create or replace function public.po_invoice_line_add(
  p_invoice_id uuid,
  p_line       jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_inv    public.po_invoice%rowtype;
  v_pl     public.po_line%rowtype;
  v_po     public.po%rowtype;
  v_kind   text;  v_pol uuid;  v_desc text;  v_qty numeric;  v_price numeric;  v_pay boolean;
  v_tax_id uuid;  v_tax_name text;                                                              -- po-tax-1 · 줄 예외 규칙(없으면 goods 는 PO 줄 규칙 · 그 밖 null = 머리)
  v_next   int;   v_cnt int;   v_dup int;
  v_row    public.po_invoice_line%rowtype;
  v_warn   text[] := '{}';
  v_reason text;  v_sug text;  v_left numeric;  v_spans boolean;                                 -- po-disc-5a · 크레딧 줄의 뜻 · 제안
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  if v_inv.status <> 'draft' then
    raise exception '% % is % — lines can be changed only while draft — nothing was saved',
      case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
  end if;
  if p_line is null or jsonb_typeof(p_line) <> 'object' then raise exception 'p_line must be a JSON object — nothing was saved'; end if;

  v_kind  := coalesce(nullif(p_line->>'line_kind', ''), 'goods');
  v_pol   := nullif(p_line->>'po_line_id', '')::uuid;
  v_desc  := nullif(p_line->>'description', '');
  v_qty   := nullif(p_line->>'qty_ea', '')::numeric;
  v_price := coalesce(nullif(p_line->>'unit_price', '')::numeric, 0);
  v_pay   := coalesce(nullif(p_line->>'is_payable', '')::boolean, true);
  v_tax_id   := nullif(p_line->>'tax_rule_id', '')::uuid;                                      -- po-tax-1
  v_tax_name := nullif(p_line->>'tax_rule', '');
  v_reason   := nullif(p_line->>'credit_reason', '');                                            -- po-disc-5a

  if v_kind not in ('goods', 'charge', 'other') then raise exception 'line_kind must be goods, charge or other — nothing was saved'; end if;
  if v_kind = 'goods' then
    if v_pol is null then raise exception 'A goods line must point at a PO line (po_line_id) — use line_kind charge/other with a description for anything else — nothing was saved'; end if;
    select * into v_pl from public.po_line where id = v_pol;
    if not found then raise exception 'PO line % not found — nothing was saved', v_pol; end if;
    select * into v_po from public.po where id = v_pl.po_id;
    if v_po.supplier_id <> v_inv.supplier_id then
      raise exception 'PO % belongs to a different supplier than % % — nothing was saved', v_po.po_number, lower(case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end), v_inv.invoice_number;
    end if;
    if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
    if v_qty is null then raise exception 'qty_ea is required for a goods line — nothing was saved'; end if;
    select count(*) into v_dup from public.po_invoice_line where po_invoice_id = p_invoice_id and po_line_id = v_pol;
    if v_dup > 0 then v_warn := array_append(v_warn, 'line_already_on_invoice'); end if;      -- 막지 않는다(부분 선적이 한 장에 두 줄로 올 수 있다 · 짐작) · 알린다
    if v_tax_id is null and v_tax_name is null then v_tax_id := v_pl.tax_rule_id; end if;     -- po-tax-1 · PO 줄 예외 규칙을 물려받는다(null = 머리)
    if v_po.tax_rule_id is not null and v_inv.tax_rule_id is not null and v_po.tax_rule_id <> v_inv.tax_rule_id then v_warn := array_append(v_warn, 'tax_rule_differs_between_pos'); end if;   -- po-tax-1
  else
    if v_desc is null then raise exception 'A % line needs a description — nothing was saved', v_kind; end if;
    v_qty := coalesce(v_qty, 1);
  end if;

  -- ── po-disc-5a(판정 400) · 크레딧 goods 줄의 뜻 — 주면 검사 · 안 주면 제안(po_credit_reason_suggest) · 걸치면 경고 ──
  if v_reason is not null and v_reason not in ('not_received', 'price_difference') then raise exception 'credit_reason must be not_received or price_difference (got %) — nothing was saved', v_reason; end if;
  if v_kind = 'goods' and v_inv.doc_kind = 'credit' then
    select suggested, not_received_left, spans_both into v_sug, v_left, v_spans from public.po_credit_reason_suggest(p_invoice_id, v_pol, v_qty, null);
    if v_reason is null then v_reason := v_sug; if v_reason is not null then v_warn := array_append(v_warn, 'credit_reason_suggested:' || v_reason); end if; end if;
    if v_spans then v_warn := array_append(v_warn, 'credit_line_spans_both'); end if;
  elsif v_reason is not null then
    raise exception 'credit_reason belongs to goods lines of a credit note only — nothing was saved';
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.po_invoice_line where po_invoice_id = p_invoice_id;

  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, description, qty_ea, unit_price, is_payable,
                                      entered_unit_product_id, entered_qty, entered_pack_factor, note, tax_rule_id, tax_rule, credit_reason)   -- po-disc-5a
  values (p_invoice_id, v_next, v_kind, case when v_kind = 'goods' then v_pol end, v_desc, v_qty, v_price, v_pay,
          nullif(p_line->>'entered_unit_product_id', '')::uuid, nullif(p_line->>'entered_qty', '')::numeric,
          nullif(p_line->>'entered_pack_factor', '')::numeric, nullif(p_line->>'note', ''), v_tax_id, v_tax_name, v_reason)   -- po-tax-1 · 짝 트리거가 다른 쪽을 채운다 · 활성 purchase 아니면 거부 · po-disc-5a credit_reason
  returning * into v_row;
  -- CHECK(target · unit_price >= 0 · entered_unit_ck)는 표가 지킨다 — 어기면 표의 예외가 그대로 올라간다

  select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = p_invoice_id;
  return jsonb_build_object('line', to_jsonb(v_row), 'line_count', v_cnt, 'invoice_number', v_inv.invoice_number,
                            'credit_reason_suggested', v_sug, 'credit_not_received_left', v_left, 'credit_spans_both', v_spans,   -- po-disc-5a
                            'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ③-c po_invoice_line_update 재발행 — 마지막 정의 20261008170700:1618~1688(DB md5 07409ac9) 바이트 복사 + declare 1 · credit_reason 받기 · 검사 · set · 반환 키 3 ═══
create or replace function public.po_invoice_line_update(
  p_line_id uuid,
  p_patch   jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_line_no int;                                                -- ②-b: 0행이면 v_row 가 null 로 덮이므로 번호를 미리 든다
  v_row   public.po_invoice_line%rowtype;
  v_inv   public.po_invoice%rowtype;
  v_pl    public.po_line%rowtype;
  v_po    public.po%rowtype;
  v_kind  text;  v_pol uuid;  v_desc text;  v_qty numeric;
  v_warn  text[] := '{}';
  v_reason text;  v_sug text;  v_left numeric;  v_spans boolean;                                 -- po-disc-5a
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select * into v_row from public.po_invoice_line where id = p_line_id;
  if not found then raise exception 'Invoice line % not found — nothing was saved', p_line_id; end if;
  v_line_no := v_row.line_no;
  select * into v_inv from public.po_invoice where id = v_row.po_invoice_id;
  if v_inv.status <> 'draft' then
    raise exception '% % is % — lines can be changed only while draft (confirmed = accepted into the books; reopen first) — nothing was saved',
      case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'p_patch must be a JSON object — nothing was saved'; end if;

  -- 새 값(patch 우선 · 없으면 기존) — CHECK 위반을 표의 예외 대신 읽을 문장으로 먼저 낸다
  v_kind := case when p_patch ? 'line_kind'   then coalesce(nullif(p_patch->>'line_kind', ''), 'goods') else v_row.line_kind end;
  v_pol  := case when p_patch ? 'po_line_id'  then nullif(p_patch->>'po_line_id', '')::uuid            else v_row.po_line_id end;
  v_desc := case when p_patch ? 'description' then nullif(p_patch->>'description', '')                 else v_row.description end;
  v_qty  := case when p_patch ? 'qty_ea'      then nullif(p_patch->>'qty_ea', '')::numeric             else v_row.qty_ea end;
  v_reason := case when p_patch ? 'credit_reason' then nullif(p_patch->>'credit_reason', '')     else v_row.credit_reason end;   -- po-disc-5a
  if v_kind not in ('goods', 'charge', 'other') then raise exception 'line_kind must be goods, charge or other — nothing was saved'; end if;
  if v_kind = 'goods' and v_pol is null then raise exception 'A goods line must point at a PO line (po_line_id) — nothing was saved'; end if;
  if v_kind <> 'goods' and v_desc is null then raise exception 'A % line needs a description — nothing was saved', v_kind; end if;
  if v_qty is null then raise exception 'qty_ea is required — nothing was saved'; end if;
  -- po-disc-5a(판정 400) · 크레딧 goods 줄의 뜻 — 값 검사 · 자리 검사 · 제안과 다르면 경고 · 걸치면 경고
  if v_reason is not null and v_reason not in ('not_received', 'price_difference') then raise exception 'credit_reason must be not_received or price_difference (got %) — nothing was saved', v_reason; end if;
  if v_reason is not null and (v_kind <> 'goods' or v_inv.doc_kind <> 'credit') then raise exception 'credit_reason belongs to goods lines of a credit note only — nothing was saved'; end if;
  if v_kind = 'goods' and v_inv.doc_kind = 'credit' then
    select suggested, not_received_left, spans_both into v_sug, v_left, v_spans from public.po_credit_reason_suggest(v_inv.id, v_pol, v_qty, p_line_id);
    if v_spans then v_warn := array_append(v_warn, 'credit_line_spans_both'); end if;
    if v_reason is not null and v_sug is not null and v_reason <> v_sug then v_warn := array_append(v_warn, 'credit_reason_differs_from_suggestion:' || v_sug); end if;
  end if;
  if v_kind = 'goods' and (p_patch ? 'po_line_id') and v_pol is distinct from v_row.po_line_id then
    select * into v_pl from public.po_line where id = v_pol;
    if not found then raise exception 'PO line % not found — nothing was saved', v_pol; end if;
    select * into v_po from public.po where id = v_pl.po_id;
    if v_po.supplier_id <> v_inv.supplier_id then
      raise exception 'PO % belongs to a different supplier than % — nothing was saved', v_po.po_number, v_inv.invoice_number;
    end if;
    if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;
  end if;

  update public.po_invoice_line set
    line_kind               = v_kind,
    po_line_id              = case when v_kind = 'goods' then v_pol else null end,                     -- goods 가 아니면 라인 참조를 비운다
    description             = v_desc,
    qty_ea                  = v_qty,
    unit_price              = case when p_patch ? 'unit_price'              then (p_patch->>'unit_price')::numeric                    else unit_price end,
    is_payable              = case when p_patch ? 'is_payable'              then coalesce((p_patch->>'is_payable')::boolean, true)     else is_payable end,
    entered_unit_product_id = case when p_patch ? 'entered_unit_product_id' then nullif(p_patch->>'entered_unit_product_id', '')::uuid  else entered_unit_product_id end,
    entered_qty             = case when p_patch ? 'entered_qty'             then nullif(p_patch->>'entered_qty', '')::numeric           else entered_qty end,
    entered_pack_factor     = case when p_patch ? 'entered_pack_factor'     then nullif(p_patch->>'entered_pack_factor', '')::numeric   else entered_pack_factor end,
    note                    = case when p_patch ? 'note'                    then nullif(p_patch->>'note', '')                           else note end,
    credit_reason           = v_reason,                                                                                               -- po-disc-5a
    tax_rule                = case when p_patch ? 'tax_rule'                then nullif(p_patch->>'tax_rule', '')                       else tax_rule end,       -- po-tax-1 · 이름(짝 트리거가 id · 활성 purchase 만) · "" = 머리로
    tax_rule_id             = case when p_patch ? 'tax_rule_id'             then nullif(p_patch->>'tax_rule_id', '')::uuid               else tax_rule_id end    -- po-tax-1 · id(둘 다 오면 id)
  where id = p_line_id
  returning * into v_row;
  if not found then                                             -- ②-b
    raise exception 'Line % of % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_line_no, v_inv.invoice_number;
  end if;

  return jsonb_build_object('line', to_jsonb(v_row), 'invoice_number', v_inv.invoice_number, 'status', v_inv.status,
                            'credit_reason_suggested', v_sug, 'credit_not_received_left', v_left, 'credit_spans_both', v_spans,   -- po-disc-5a
                            'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ③-d po_invoice_detail 재발행 — 마지막 정의 20261008170700:824~965(DB md5 7d3e9d86) 바이트 복사 + lines[] 네 키 · 경고 둘 · credit_cost_events[] ═══
create or replace function public.po_invoice_detail(p_invoice_id uuid) returns jsonb
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
with i as (
  select * from public.po_invoice where id = p_invoice_id
),
m as (
  select * from public.po_invoice_money where id = p_invoice_id
),
lines as (
  select il.*,
         pl.po_id, x.po_number, pl.line_no as po_line_no, pl.qty_ea as po_qty_ea, pl.unit_price as po_unit_price,
         pr.sku, pr.name as product_name, up.sku as entered_unit_sku,
         sg.suggested as credit_reason_suggested, sg.not_received_left as credit_not_received_left, sg.spans_both as credit_spans_both,   -- po-disc-5a · 크레딧 goods 줄만(아니면 null)
         round(il.qty_ea * il.unit_price, 2) as amount,
         tr.name as tax_rule_effective, tr.rate_pct,                                                     -- po-tax-1 · coalesce(줄, 머리)
         public.so_tax_amount(round(il.qty_ea * il.unit_price, 2), tr.rate_pct) as tax_amount,          -- po-tax-1 · 줄 세금(할인 줄은 묶음에서 뺀다 · money.tax_groups)
         case when il.po_line_id is not null
              then coalesce((select sum(rl.qty_ea) from public.po_receipt_line rl where rl.po_line_id = il.po_line_id), 0) end as received_qty,
         case when il.po_line_id is not null
              then coalesce((select sum(x2.qty_ea) from public.po_invoice_line x2 join public.po_invoice i2 on i2.id = x2.po_invoice_id
                              where x2.po_line_id = il.po_line_id and x2.line_kind = 'goods' and i2.doc_kind = 'invoice' and i2.status <> 'cancelled'
                                and i2.id <> p_invoice_id), 0) end as other_invoiced_qty
  from public.po_invoice_line il
  left join public.po_line pl on pl.id = il.po_line_id
  left join public.po x on x.id = pl.po_id
  left join public.product pr on pr.id = pl.product_id
  left join public.product up on up.id = il.entered_unit_product_id
  left join public.ref_tax_rule tr on tr.id = coalesce(il.tax_rule_id, (select tax_rule_id from i))
  left join lateral (select s.* from public.po_credit_reason_suggest(p_invoice_id, il.po_line_id, il.qty_ea, il.id) s where il.line_kind = 'goods' and (select doc_kind from i) = 'credit') sg on true   -- po-disc-5a
  where il.po_invoice_id = p_invoice_id
),
shares as (
  select l.po_id, l.po_number, x.status as po_status, count(*)::int as line_count,
         coalesce(sum(l.qty_ea) filter (where l.line_kind = 'goods'), 0) as qty_ea,
         coalesce(sum(l.amount), 0) as amount
  from lines l join public.po x on x.id = l.po_id
  where l.po_id is not null
  group by l.po_id, l.po_number, x.status
),
cred as (
  select c.id, c.invoice_number, c.invoice_date, c.status, c.total_amount, c.supplier_ref_number, cm.payable_net as credit_net, cm.alloc_total as used
  from public.po_invoice c join public.po_invoice_money cm on cm.id = c.id
  where c.credit_for_invoice_id = p_invoice_id
),
pay as (
  select pa.id as alloc_id, pa.amount as alloc_amount, pm.id as payment_id, pm.paid_on, pm.reference, pm.amount as payment_amount, pm.discount_taken,
         cur.code as currency_code, acc.code as account_code, acc.name as account_name, st.name as paid_by_name
  from public.po_payment_alloc pa
  join public.po_payment pm on pm.id = pa.po_payment_id
  join public.ref_currency cur on cur.id = pm.currency_id
  left join public.ref_account acc on acc.id = pm.account_id
  left join public.ims_staff st on st.id = pm.paid_by
  where pa.po_invoice_id = p_invoice_id
)
select case when not exists (select 1 from i) then null else jsonb_build_object(
  'header', (
    select jsonb_build_object(
      'id', i.id, 'doc_kind', i.doc_kind, 'invoice_number', i.invoice_number, 'invoice_date', i.invoice_date, 'due_date', i.due_date, 'status', i.status,
      'supplier_ref_number', i.supplier_ref_number,                                          -- ⭐ 새 · 공급처가 보내온 크레딧 노트 번호(참조) · PostgREST 로 고친다
      'credit_po_id', i.credit_po_id, 'credit_po_number', cp.po_number,                     -- ⭐ 새 · 번호를 낸 발주
      'supplier_id', i.supplier_id, 'supplier_name', s.name,
      'currency_id', i.currency_id, 'currency_code', cur.code, 'exchange_rate', i.exchange_rate,
      'payment_term_id', i.payment_term_id, 'payment_term_name', coalesce(i.payment_term_name, pt.name),
      'total_amount', i.total_amount,
      'tax_rule_id', i.tax_rule_id, 'tax_rule', i.tax_rule, 'rate_pct', m.rate_pct,          -- po-tax-1 · 머리 규칙(초안에서 PostgREST 로 이름을 고친다)
      'credit_for_invoice_id', i.credit_for_invoice_id, 'credit_for_number', f.invoice_number, 'credit_for_status', f.status,
      'created_by_name', cb.name, 'confirmed_by_name', fb.name,
      'confirmed_at', i.confirmed_at, 'cancelled_at', i.cancelled_at, 'note', i.note, 'created_at', i.created_at, 'updated_at', i.updated_at)
    from i
    cross join m
    join public.supplier s on s.id = i.supplier_id
    join public.ref_currency cur on cur.id = i.currency_id
    left join public.ref_payment_term pt on pt.id = i.payment_term_id
    left join public.po_invoice f on f.id = i.credit_for_invoice_id
    left join public.po cp on cp.id = i.credit_po_id
    left join public.ims_staff cb on cb.id = i.created_by
    left join public.ims_staff fb on fb.id = i.confirmed_by
  ),
  'money', (
    select jsonb_build_object(
      'line_count', m.line_count, 'goods_sum', m.goods_sum, 'other_sum', m.other_sum, 'goods_payable', m.goods_payable, 'other_payable', m.other_payable,
      'discount_factor', round(m.factor, 6),
      'computed_total', m.computed_total, 'diff', m.diff,
      'payable_net', m.payable_net,
      'alloc_total', m.alloc_total,
      'credit_total', m.credit_total, 'unpaid', m.unpaid, 'remaining', m.remaining,
      -- ── po-tax-1 · 세금(문서 통화 · 규칙 모르면 null + 경고 tax_rule_missing) ──
      'taxable_amount', m.taxable_amount, 'tax_amount', m.tax_amount,
      'payable_taxable', m.payable_taxable, 'payable_tax', m.payable_tax,
      'tax_rule_groups', m.tax_rule_groups,
      'tax_groups', coalesce((select jsonb_agg(jsonb_build_object('tax_rule_id', g.tax_rule_id, 'tax_rule', g.tax_rule, 'rate_pct', g.rate_pct, 'line_count', g.line_count,
                                                                  'taxable_amount', g.taxable_amount, 'discount_amount', g.discount_amount, 'lines_tax', g.lines_tax,
                                                                  'discount_tax', g.discount_tax, 'tax_amount', g.tax_amount, 'payable_taxable', g.payable_taxable, 'payable_tax', g.payable_tax)
                                               order by g.tax_rule nulls last)
                               from public.po_tax_group g where g.doc_kind = 'invoice' and g.doc_id = p_invoice_id), '[]'::jsonb))
    from m
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'line_kind', line_kind, 'po_line_id', po_line_id, 'po_id', po_id, 'po_number', po_number, 'po_line_no', po_line_no,
      'sku', sku, 'product_name', product_name, 'description', description,
      'qty_ea', qty_ea, 'entered_unit_sku', entered_unit_sku, 'entered_unit_product_id', entered_unit_product_id, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'is_payable', is_payable, 'note', note,
      'tax_rule_id', tax_rule_id, 'tax_rule', tax_rule, 'tax_rule_effective', tax_rule_effective, 'rate_pct', rate_pct, 'tax_amount', tax_amount,   -- po-tax-1 · 줄 규칙(null = 머리) · 적용 규칙 · 줄 세금
      'po_qty_ea', po_qty_ea, 'po_unit_price', po_unit_price,
      'received_qty', received_qty, 'other_invoiced_qty', other_invoiced_qty,
      'qty_diff', case when line_kind = 'goods' then qty_ea - received_qty end,
      'credit_reason', credit_reason, 'credit_reason_suggested', credit_reason_suggested, 'credit_not_received_left', credit_not_received_left, 'credit_spans_both', credit_spans_both)   -- po-disc-5a
      order by line_no)
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq, 'name', d.name, 'percent', d.percent, 'supplier_discount_id', d.supplier_discount_id, 'note', d.note) order by d.seq)
    from public.po_invoice_discount d where d.po_invoice_id = p_invoice_id), '[]'::jsonb),
  'po_shares', coalesce((
    select jsonb_agg(jsonb_build_object('po_id', po_id, 'po_number', po_number, 'po_status', po_status, 'line_count', line_count, 'qty_ea', qty_ea, 'amount', amount) order by po_number)
    from shares), '[]'::jsonb),
  'credits', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'credit_number', invoice_number, 'credit_date', invoice_date, 'status', status, 'total_amount', total_amount,
                                        'supplier_ref_number', supplier_ref_number,                                   -- ⭐ 새
                                        'credit_net', credit_net, 'used', used)
      order by invoice_date, invoice_number)
    from cred), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'payment_id', payment_id, 'paid_on', paid_on, 'reference', reference, 'alloc_amount', alloc_amount,
                                        'payment_amount', payment_amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
                                        'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb),
  'credit_cost_events', coalesce((                                                                                      -- po-disc-5a · 이 크레딧의 원가 사건(되돌림 포함)
    select jsonb_agg(jsonb_build_object('id', j.id, 'line_no', cl.line_no, 'po_line_id', j.po_line_id, 'amount_doc', j.amount_doc, 'amount_cad', j.amount_cad, 'status', j.status, 'posted_on', j.posted_on, 'reverses_id', j.reverses_id, 'source_type', j.source_type) order by cl.line_no, j.created_at)
    from public.inv_cost_adjust j join public.po_invoice_line cl on cl.id = coalesce((select o.source_id from public.inv_cost_adjust o where o.id = j.reverses_id), j.source_id)
    where cl.po_invoice_id = p_invoice_id and (j.source_type = 'po_credit' or exists (select 1 from public.inv_cost_adjust o where o.id = j.reverses_id and o.source_type = 'po_credit'))), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when i.doc_kind = 'credit' and i.credit_for_invoice_id is not null and m.alloc_total > 0 then 'attached_and_used' end,
        case when f.doc_kind = 'credit' then 'credit_for_is_credit' end,
        case when f.supplier_id is not null and f.supplier_id <> i.supplier_id then 'credit_for_other_supplier' end,
        case when i.total_amount = 0 then 'total_amount_zero' end,
        case when m.diff <> 0 then 'total_differs_from_lines' end,
        case when m.line_count = 0 then 'no_lines' end,
        case when m.tax_rule_missing then 'tax_rule_missing' end,                                -- po-tax-1 · 규칙 모르는 줄이 있다(세금 0 으로 더했다)
        case when i.doc_kind = 'credit' and i.status = 'draft' and exists (select 1 from lines l where l.line_kind = 'goods' and l.credit_reason is null) then 'credit_reason_missing' end,   -- po-disc-5a
        case when i.doc_kind = 'credit' and exists (select 1 from lines l where l.credit_spans_both) then 'credit_line_spans_both' end
      ], null)) as w
      from i cross join m left join public.po_invoice f on f.id = i.credit_for_invoice_id) t
  )
) end;
$$;

-- ═══ ④⑤ po_invoice_confirm 재발행 — 마지막 정의 20260930021142:37~246(DB md5 f69b1962) 바이트 복사 + definer · declare 1 · 크레딧 확정 검사 블록(reason · ⬜1) · 사건 · 다시 열기 되돌림 · 반환 키 2 ═══
create or replace function public.po_invoice_confirm(
  p_invoice_id uuid,
  p_confirm    boolean default true
) returns jsonb
language plpgsql
volatile
security definer                                              -- po-disc-5a(이견 1): 속 함수 po_credit_cost_events · po_credit_cost_reverse 를 부른다 · 문은 첫 줄 ims_require_write('purchasing')
set search_path = public, pg_temp
as $$
declare
  v_num   text;                                                 -- ②-b: 0행 문장용 번호(returning 이 v_inv 를 null 로 덮는다)
  v_staff uuid;
  v_inv   public.po_invoice%rowtype;
  v_for   public.po_invoice%rowtype;
  v_m     record;
  v_cnt   int;
  v_cred  int;
  v_warn  text[] := '{}';
  v_label text;
  v_p     record;                                               -- inv-basis-2: 이 인보이스가 가리키는 발주(goods 줄 · 문서마다)
  v_po    public.po%rowtype;
  v_s     public.po%rowtype;                                    -- Reopen 되붙임: 이 확정이 만든 형제
  v_base  text;  v_max text;  v_b_num text;  v_b_id uuid;
  v_rem   int;   v_left numeric;  v_n int;  v_orig uuid;  v_orig_qty numeric;
  v_lines jsonb;  v_split jsonb := '[]'::jsonb;  v_reat jsonb := '[]'::jsonb;
  x       record;
  v_cev   jsonb;  v_crv jsonb;  v_sg record;                   -- po-disc-5a: 크레딧 원가 사건 · 되돌림 · 제안 식(⬜1 확정 거부)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_num := v_inv.invoice_number;
  select * into v_m from public.po_invoice_money where id = p_invoice_id;

  if p_confirm then
    if v_inv.status = 'confirmed' then raise exception '% % is already confirmed — nothing was saved', v_label, v_inv.invoice_number; end if;
    if v_inv.status = 'cancelled' then raise exception '% % is cancelled — a cancelled document cannot be confirmed — nothing was saved', v_label, v_inv.invoice_number; end if;
    select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = p_invoice_id;
    if v_cnt = 0 then raise exception '% % has no lines — nothing to accept into the books — nothing was saved', v_label, v_inv.invoice_number; end if;
    if v_inv.credit_for_invoice_id is not null then                       -- 다른 행의 사실 — po_detail credits[].warnings 와 같은 셋을 여기서는 막는다
      select * into v_for from public.po_invoice where id = v_inv.credit_for_invoice_id;
      if v_for.doc_kind <> 'invoice' then raise exception 'Credit note % points at another credit note (%) — nothing was saved', v_inv.invoice_number, v_for.invoice_number; end if;
      if v_for.supplier_id <> v_inv.supplier_id then raise exception 'Credit note % points at an invoice of a different supplier (%) — nothing was saved', v_inv.invoice_number, v_for.invoice_number; end if;
    end if;
    if v_inv.total_amount = 0 then v_warn := array_append(v_warn, 'total_amount_zero'); end if;                 -- 샘플 인보이스 실물 · 막지 않는다
    if v_m.diff <> 0 then v_warn := array_append(v_warn, 'total_differs_from_lines'); end if;                   -- 반올림 · other 할인 미결 · 정본은 찍힌 값 · 막지 않는다
    -- ═══ inv-basis-2 · 판정 88 ④ ⑤ · 92 · 96 — 인보이스 확정 = PO 분할: 발주마다 청구된 몫만 원래 번호에 남고, 덜 청구된 수량과 인보이스에 없는 줄은 형제(다음 글자 하나)로 ═══
    --   막는 것(판정 92 · 예외 없음): PO 가 confirmed 가 아님 · 그 PO 에 입고(초안이든 확정이든)가 있음 · 이 인보이스 줄이 PO 줄의 남은 수량(qty_ea − 다른 확정 인보이스 goods 합)을 넘음(판정 96)
    --   초안 인보이스는 아무 일 없음(이 갈래는 확정에만) · 크레딧은 갈라지지 않는다 · 비용 배분 · 크레딧 연결(credit_po_id)은 원래 번호에 남는다(판정 93 ⓛ) · 형제 = split_from_id 원래 PO · split_by_invoice_id 이 인보이스
    if v_inv.doc_kind = 'invoice' then
      for v_p in
        select distinct pl.po_id
        from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id
        where il.po_invoice_id = p_invoice_id and il.line_kind = 'goods'
        order by 1
      loop
        select * into v_po from public.po where id = v_p.po_id for update;
        v_base := regexp_replace(v_po.po_number, '[a-z]+$', '');
        perform pg_advisory_xact_lock(hashtext('po:' || v_base));                                              -- 형제 채번 · 입고 확정과 같은 열쇠
        if v_po.status <> 'confirmed' then
          raise exception 'PO % is % — an invoice can be confirmed only onto a confirmed order — nothing was saved', v_po.po_number, v_po.status;
        end if;
        if exists (select 1 from public.po_receipt r where r.po_id = v_po.id) then
          raise exception 'PO % already has a receipt — the warehouse has started on this order, so this invoice cannot be confirmed onto it; correct it with a credit note or an Off-invoice decision — nothing was saved', v_po.po_number;
        end if;
        v_rem := 0;
        for x in
          select pl.id, pl.line_no, pr.sku, pl.qty_ea,
                 coalesce((select sum(o.qty_ea) from public.po_invoice_line o join public.po_invoice oi on oi.id = o.po_invoice_id
                            where o.po_line_id = pl.id and o.line_kind = 'goods' and oi.doc_kind = 'invoice' and oi.status = 'confirmed' and oi.id <> p_invoice_id), 0) as billed_before,
                 coalesce((select sum(t.qty_ea) from public.po_invoice_line t where t.po_invoice_id = p_invoice_id and t.po_line_id = pl.id and t.line_kind = 'goods'), 0) as billed_here
          from public.po_line pl join public.product pr on pr.id = pl.product_id
          where pl.po_id = v_po.id
          order by pl.line_no
        loop
          if x.billed_here > x.qty_ea - x.billed_before then                                                  -- 판정 96
            raise exception 'Line % (%) of PO %: this invoice bills % EA but only % EA are left on the order line — raise the PO line first (Purchase Orders), then confirm the invoice — nothing was saved',
              x.line_no, x.sku, v_po.po_number, x.billed_here, x.qty_ea - x.billed_before;
          end if;
          if x.qty_ea - x.billed_before - x.billed_here > 0 then v_rem := v_rem + 1; end if;
        end loop;
        if v_rem > 0 then
          -- 번호 — base 의 접미 최댓값 다음 글자 하나(so_split 모양 · 옛 형제 a · b 뒤면 c) · 원래 번호는 그대로
          select max(substring(p.po_number from length(v_base) + 1)) into v_max
          from public.po p where p.po_number ~ ('^' || v_base || '[a-z]+$');
          if v_max is null then
            v_b_num := v_base || 'a';
          else
            if length(v_max) <> 1 or v_max >= 'y' then
              raise exception 'PO % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_po.po_number, v_max;
            end if;
            v_b_num := v_base || chr(ascii(v_max) + 1);
          end if;
          v_b_id := gen_random_uuid();
          insert into public.po
          select * from jsonb_populate_record(null::public.po,
            to_jsonb(v_po) || jsonb_build_object('id', v_b_id, 'po_number', v_b_num, 'status', 'confirmed', 'split_from_id', v_po.id, 'split_by_invoice_id', p_invoice_id,
                                                 'closed_at', null, 'cancelled_at', null, 'cancelled_by', null,
                                                 'created_at', now(), 'updated_at', now(), 'updated_by', v_staff));
          insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id, note)
          select v_b_id, d.seq, d.name, d.percent, d.supplier_discount_id, d.note from public.po_discount d where d.po_id = v_po.id;
          v_lines := '[]'::jsonb;
          for x in
            select pl.*, pr.sku,
                   coalesce((select sum(o.qty_ea) from public.po_invoice_line o join public.po_invoice oi on oi.id = o.po_invoice_id
                              where o.po_line_id = pl.id and o.line_kind = 'goods' and oi.doc_kind = 'invoice' and oi.status = 'confirmed' and oi.id <> p_invoice_id), 0) as billed_before,
                   coalesce((select sum(t.qty_ea) from public.po_invoice_line t where t.po_invoice_id = p_invoice_id and t.po_line_id = pl.id and t.line_kind = 'goods'), 0) as billed_here
            from public.po_line pl join public.product pr on pr.id = pl.product_id
            where pl.po_id = v_po.id
            order by pl.line_no
          loop
            v_left := x.qty_ea - x.billed_before - x.billed_here;
            if v_left <= 0 then continue; end if;                                                              -- 다 청구됐다 — 원래 번호에 그대로
            if x.billed_before + x.billed_here = 0 then
              update public.po_line set po_id = v_b_id, updated_by = v_staff where id = x.id and po_id = v_po.id;   -- 인보이스에 없는 줄 — 행을 통째로(id 그대로 · 초안 인보이스가 가리켜도 따라간다)
              get diagnostics v_n = row_count;
              if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
              v_lines := v_lines || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'moved', 'qty_ea', v_left);
            else
              update public.po_line set qty_ea = x.qty_ea - v_left, entered_unit_product_id = null, entered_qty = null, entered_pack_factor = null, updated_by = v_staff
               where id = x.id and qty_ea = x.qty_ea;                                                              -- 덜 청구된 줄 — 원래 줄은 청구된 만큼으로(입력 단위 셋은 비운다)
              get diagnostics v_n = row_count;
              if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
              insert into public.po_line
              select * from jsonb_populate_record(null::public.po_line,
                to_jsonb(x) - 'sku' - 'billed_before' - 'billed_here' || jsonb_build_object('id', gen_random_uuid(), 'po_id', v_b_id, 'qty_ea', v_left,
                                                                                            'entered_unit_product_id', null, 'entered_qty', null, 'entered_pack_factor', null,
                                                                                            'created_at', now(), 'updated_at', now(), 'updated_by', v_staff));
              v_lines := v_lines || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', 'reduced', 'qty_ea', v_left);
            end if;
          end loop;
          v_split := v_split || jsonb_build_object('po_id', v_po.id, 'po_number', v_po.po_number, 'new_po_id', v_b_id, 'new_number', v_b_num, 'lines', v_lines);
          v_warn := array_append(v_warn, 'po_split');
        end if;
      end loop;
    end if;
    -- ═══ po-disc-5a(판정 400 · ⬜1) · 크레딧 확정 — goods 줄마다 뜻이 있어야 한다 · not_received 줄이 남은 안 온 수량을 넘으면 거부(줄을 나눈다) ═══
    if v_inv.doc_kind = 'credit' then
      for x in select cl.id, cl.line_no, cl.qty_ea, cl.credit_reason, cl.po_line_id, pr.sku
                 from public.po_invoice_line cl join public.po_line pl on pl.id = cl.po_line_id join public.product pr on pr.id = pl.product_id
                where cl.po_invoice_id = p_invoice_id and cl.line_kind = 'goods' order by cl.line_no loop
        if x.credit_reason is null then
          raise exception 'Credit note %: line % (%) has no reason — mark each goods line Not received or Price difference first — nothing was saved', v_inv.invoice_number, x.line_no, x.sku;
        end if;
        if x.credit_reason = 'not_received' then
          select * into v_sg from public.po_credit_reason_suggest(p_invoice_id, x.po_line_id, x.qty_ea, x.id);
          if x.qty_ea > v_sg.not_received_left then
            raise exception 'Credit note %: line % (%) marks % EA as Not received but only % EA are still unreceived on that PO line (billed % · received % · already credited %) — split the line; the rest is a price difference — nothing was saved',
              v_inv.invoice_number, x.line_no, x.sku, x.qty_ea, v_sg.not_received_left, v_sg.billed_qty, v_sg.received_qty, v_sg.credited_not_received_qty;
          end if;
        end if;
      end loop;
    end if;
    update public.po_invoice set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_invoice_id returning * into v_inv;
    if not found then raise exception '% % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_label, v_num; end if;   -- ②-b
    if v_inv.doc_kind = 'credit' then                                                                           -- po-disc-5a(판정 392 · 400): price_difference 줄마다 원가 사건 · 곧바로 얹는다(레이어 없으면 pending · 399 거부는 예외 = 확정 전체 안 저장)
      v_cev := public.po_credit_cost_events(p_invoice_id, true);
      v_warn := v_warn || array(select jsonb_array_elements_text(v_cev -> 'warnings'));
    end if;
  else
    if v_inv.status <> 'confirmed' then raise exception '% % is % — only a confirmed document can be reopened — nothing was saved', v_label, v_inv.invoice_number, v_inv.status; end if;
    if v_m.alloc_total > 0 then
      raise exception '% % has payments applied (%) — cannot reopen while paid/used; remove the payment allocation first — nothing was saved', v_label, v_inv.invoice_number, v_m.alloc_total;
    end if;
    select count(*) into v_cred from public.po_invoice c where c.credit_for_invoice_id = p_invoice_id and c.status <> 'cancelled';
    if v_cred > 0 then v_warn := array_append(v_warn, 'has_attached_credits'); end if;
    if v_inv.doc_kind = 'credit' then v_crv := public.po_credit_cost_reverse(p_invoice_id, 'credit note ' || v_inv.invoice_number || ' reopened'); end if;   -- po-disc-5a: 다시 열기 = 사건 되돌림(결제 검사 뒤 · 같은 트랜잭션)
    -- ═══ inv-basis-2 · 판정 88 ⑦ — Reopen = 되붙임: 창고가 아직 손대지 않았을 때만(그 PO 에 입고 0 · 이 확정이 만든 형제가 그대로) · 형제의 줄을 원래 줄에 되돌리고 형제를 지운다(번호는 빈다 · 판정 55) ═══
    if v_inv.doc_kind = 'invoice' then
      for v_p in
        select distinct pl.po_id
        from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id
        where il.po_invoice_id = p_invoice_id and il.line_kind = 'goods'
        order by 1
      loop
        select * into v_po from public.po where id = v_p.po_id for update;
        perform pg_advisory_xact_lock(hashtext('po:' || regexp_replace(v_po.po_number, '[a-z]+$', '')));
        if exists (select 1 from public.po_receipt r where r.po_id = v_po.id) then
          raise exception 'The warehouse has started on PO % — Reopen is not possible; correct it with a credit note or an Off-invoice decision — nothing was saved', v_po.po_number;
        end if;
        if v_po.status <> 'confirmed' then
          raise exception 'PO % is % — Reopen is not possible on a closed or cancelled order; correct it with a credit note — nothing was saved', v_po.po_number, v_po.status;
        end if;
        for v_s in select * from public.po s where s.split_from_id = v_po.id and s.split_by_invoice_id = p_invoice_id order by s.po_number loop
          if v_s.status <> 'confirmed'
             or exists (select 1 from public.po_receipt r where r.po_id = v_s.id)
             or exists (select 1 from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id where pl.po_id = v_s.id)
             or exists (select 1 from public.po_charge_alloc a where a.po_id = v_s.id)
             or exists (select 1 from public.po_invoice k where k.credit_po_id = v_s.id)
             or exists (select 1 from public.po c where c.split_from_id = v_s.id)
             or v_s.updated_at > v_s.created_at
             or exists (select 1 from public.po_line l where l.po_id = v_s.id and l.updated_at > v_s.created_at) then   -- 판정 103(inv-basis-8): 형제가 생긴 순간과 비교 — 통째로 옮긴 줄은 created_at 이 원래 PO 의 것이라 자기 created_at 과 비교하면 늘 「손댔다」였다
            raise exception 'PO % (split off by this invoice) has been worked on since — Reopen is not possible; correct it with a credit note or an Off-invoice decision — nothing was saved', v_s.po_number;
          end if;
          v_lines := '[]'::jsonb;
          for x in select pl.* from public.po_line pl where pl.po_id = v_s.id order by pl.line_no loop
            select l.id, l.qty_ea into v_orig, v_orig_qty from public.po_line l where l.po_id = v_po.id and l.line_no = x.line_no;
            if v_orig is not null then
              update public.po_line set qty_ea = v_orig_qty + x.qty_ea, updated_by = v_staff where id = v_orig and qty_ea = v_orig_qty;   -- 줄였던 줄 — 되돌려 더한다
              get diagnostics v_n = row_count;
              if v_n = 0 then raise exception 'Line % of PO % was not saved — it may have been changed by someone else just now — nothing was saved', x.line_no, v_po.po_number; end if;
              delete from public.po_line where id = x.id;
              v_lines := v_lines || jsonb_build_object('line_no', x.line_no, 'kind', 'restored', 'qty_ea', x.qty_ea);
            else
              update public.po_line set po_id = v_po.id, updated_by = v_staff where id = x.id;                    -- 옮겼던 줄 — 행이 돌아온다
              v_lines := v_lines || jsonb_build_object('line_no', x.line_no, 'kind', 'moved_back', 'qty_ea', x.qty_ea);
            end if;
            v_orig := null; v_orig_qty := null;
          end loop;
          delete from public.po_discount where po_id = v_s.id;
          delete from public.po where id = v_s.id;
          v_reat := v_reat || jsonb_build_object('po_id', v_po.id, 'po_number', v_po.po_number, 'removed_po_id', v_s.id, 'removed_number', v_s.po_number, 'lines', v_lines);
          v_warn := array_append(v_warn, 'po_reattached');
        end loop;
      end loop;
    end if;
    update public.po_invoice set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_invoice_id returning * into v_inv;
    if not found then raise exception '% % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_label, v_num; end if;   -- ②-b
  end if;

  return jsonb_build_object(
    'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'confirmed_at', v_inv.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'computed_total', v_m.computed_total, 'diff', v_m.diff, 'payable_net', v_m.payable_net,
                                'alloc_total', v_m.alloc_total, 'credit_total', v_m.credit_total, 'unpaid', v_m.unpaid, 'remaining', v_m.remaining),
    'split', v_split, 'reattached', v_reat,                       -- inv-basis-2: 확정이 가른 것 · Reopen 이 되붙인 것(화면 ⑱-3 이 확인 문장에 쓴다 · 판매 반환 키는 그대로)
    'cost_events', v_cev, 'cost_reversed', v_crv,                 -- po-disc-5a · 크레딧 확정의 사건 · 다시 열기의 되돌림(인보이스는 null)
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑤ po_doc_cancel 재발행 — 마지막 정의 20261008234826:381~606(DB md5 118d64ac) 바이트 복사 + definer · declare 1 · 취소 되돌림 · 복구 사건(이견 2) · 반환 키 2 ═══
create or replace function public.po_doc_cancel(
  p_target text,                          -- 'po' | 'invoice' | 'charge' | 'payment'(거부)
  p_id     uuid,
  p_cancel boolean default true
) returns jsonb
language plpgsql
volatile
security definer                                              -- po-disc-5a(이견 1): 크레딧 갈래가 속 함수 po_credit_cost_reverse · po_credit_cost_events 를 부른다 · 문은 첫 줄 · 세 갈래의 RLS 정책은 전부 purchasing
set search_path = public, pg_temp
as $$
declare
  v_staff        uuid;
  v_crv          jsonb;  v_cev jsonb;                           -- po-disc-5a: 크레딧 취소의 되돌림 · 복구의 사건
  v_po           public.po%rowtype;
  v_inv          public.po_invoice%rowtype;
  v_for          public.po_invoice%rowtype;
   v_rp           record;                                 -- po-disc-2 판정 396: 입고가 있는 PO(이 인보이스의 goods 줄이 가리키는)
  v_chg          public.po_charge%rowtype;
  v_label        text;
  v_m            record;
  v_m2           record;
  v_recv_n       int;
  v_recv_qty     numeric;
  v_n            int;
  v_txt          text;
  v_inv_txt      text;
  v_chg_txt      text;
  v_cred_txt     text;
  v_split_txt    text;
  v_new_status   text;
  v_unpaid_before numeric;
  v_unpaid_after  numeric;
  v_warn         text[] := '{}';
  v_doc          text;                                          -- ②-b: 0행 문장용 문서 이름(rowtype 이 null 로 덮이기 전에 든다)
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

  if p_target not in ('po', 'invoice', 'charge', 'payment') then
    raise exception 'p_target must be po, invoice, charge or payment — nothing was saved';
  end if;
  -- ⭐ 결제는 상태가 없다(⑦) — 취소가 아니라 삭제
  if p_target = 'payment' then
    raise exception 'A payment has no cancelled state — delete it instead (po_doc_delete with p_target payment) — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;

  -- ══════════ 발주 (100000 그대로) ══════════
  if p_target = 'po' then
    select * into v_po from public.po where id = p_id;
    if not found then raise exception 'PO % not found — nothing was saved', p_id; end if;
    v_doc := 'PO ' || v_po.po_number;

    if p_cancel then
      if v_po.status = 'cancelled' then
        raise exception 'PO % is already cancelled — nothing was saved', v_po.po_number;
      end if;
      if v_po.status = 'closed' then
        raise exception 'PO % is closed (receiving finished) — a closed order cannot be cancelled — nothing was saved', v_po.po_number;
      end if;
      select count(*), coalesce(sum(rl.qty_ea), 0) into v_recv_n, v_recv_qty
      from public.po_receipt_line rl join public.po_line pl on pl.id = rl.po_line_id
      where pl.po_id = p_id;
      if v_recv_n > 0 then
        raise exception 'PO % has % receipt line(s) (% EA received) — a received order cannot be cancelled; receipts are events — nothing was saved',
          v_po.po_number, v_recv_n, v_recv_qty;
      end if;

      select string_agg(distinct i.invoice_number, ', ' order by i.invoice_number) into v_inv_txt
      from public.po_invoice_line il
      join public.po_line pl on pl.id = il.po_line_id
      join public.po_invoice i on i.id = il.po_invoice_id
      where pl.po_id = p_id and i.status <> 'cancelled';
      if v_inv_txt is not null then v_warn := array_append(v_warn, 'has_invoices'); end if;

      select string_agg(distinct c.charge_number, ', ' order by c.charge_number) into v_chg_txt
      from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id
      where a.po_id = p_id and c.status <> 'cancelled';
      if v_chg_txt is not null then v_warn := array_append(v_warn, 'has_charges'); end if;

      select string_agg(k.invoice_number, ', ' order by k.invoice_number) into v_cred_txt
      from public.po_invoice k where k.credit_po_id = p_id and k.status <> 'cancelled';
      if v_cred_txt is not null then v_warn := array_append(v_warn, 'has_numbered_credits'); end if;

      select string_agg(c.po_number, ', ' order by c.po_number) into v_split_txt
      from public.po c where c.split_from_id = p_id;
      if v_split_txt is not null then v_warn := array_append(v_warn, 'has_split_children'); end if;

      update public.po set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
      where id = p_id returning * into v_po;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    else
      if v_po.status <> 'cancelled' then
        raise exception 'PO % is % — only a cancelled order can be restored — nothing was saved', v_po.po_number, v_po.status;
      end if;
      v_new_status := case when v_po.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_po;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    end if;

    return jsonb_build_object(
      'target', 'po', 'id', v_po.id, 'po_number', v_po.po_number, 'status', v_po.status,
      'cancelled_at', v_po.cancelled_at, 'confirmed_at', v_po.confirmed_at, 'restored', not p_cancel,
      'attached', jsonb_build_object('invoices', v_inv_txt, 'charges', v_chg_txt, 'numbered_credits', v_cred_txt, 'split_children', v_split_txt),
      'warnings', to_jsonb(v_warn));
  end if;

  -- ══════════ 비용 문서 (150000 그대로) ══════════
  if p_target = 'charge' then
    select * into v_chg from public.po_charge where id = p_id;
    if not found then raise exception 'Charge % not found — nothing was saved', p_id; end if;
    v_doc := 'Charge ' || v_chg.charge_number;
    select * into v_m from public.po_charge_money where id = p_id;

    if p_cancel then
      if v_chg.status = 'cancelled' then
        raise exception 'Charge % is already cancelled — nothing was saved', v_chg.charge_number;
      end if;
      if v_m.paid > 0 then
        select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
        from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
        where pa.po_charge_id = p_id;
        raise exception 'Charge % has payments applied (%) — cannot cancel while paid; remove the payment allocation first — nothing was saved', v_chg.charge_number, v_txt;
      end if;
      select count(*), string_agg(x.po_number, ', ' order by x.po_number) into v_n, v_chg_txt
      from public.po_charge_alloc a join public.po x on x.id = a.po_id where a.po_charge_id = p_id;
      if v_n > 0 then v_warn := array_append(v_warn, 'has_allocs'); end if;
      if v_chg.status = 'draft' then v_warn := array_append(v_warn, 'cancelled_from_draft'); end if;

      update public.po_charge set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
      where id = p_id returning * into v_chg;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    else
      if v_chg.status <> 'cancelled' then
        raise exception 'Charge % is % — only a cancelled document can be restored — nothing was saved', v_chg.charge_number, v_chg.status;
      end if;
      v_new_status := case when v_chg.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po_charge set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_chg;
      if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;   -- ②-b
    end if;

    return jsonb_build_object(
      'target', 'charge', 'id', v_chg.id, 'charge_number', v_chg.charge_number, 'status', v_chg.status,
      'cancelled_at', v_chg.cancelled_at, 'confirmed_at', v_chg.confirmed_at, 'restored', not p_cancel,
      'attached', jsonb_build_object('pos', v_chg_txt),
      'warnings', to_jsonb(v_warn));
  end if;

  -- ══════════ 인보이스 · 크레딧 (100000 그대로) ══════════
  select * into v_inv from public.po_invoice where id = p_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_doc := v_label || ' ' || v_inv.invoice_number;
  select * into v_m from public.po_invoice_money where id = p_id;

  if p_cancel then
    if v_inv.status = 'cancelled' then
      raise exception '% % is already cancelled — nothing was saved', v_label, v_inv.invoice_number;
    end if;
    if v_m.alloc_total > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_invoice_id = p_id;
      raise exception '% % has payments applied (%) — cannot cancel while paid/used; remove the payment allocation first — nothing was saved',
        v_label, v_inv.invoice_number, v_txt;
    end if;
    select count(*), string_agg(c.invoice_number, ', ' order by c.invoice_number) into v_n, v_txt
    from public.po_invoice c where c.credit_for_invoice_id = p_id and c.status <> 'cancelled';
    if v_n > 0 then
      raise exception 'Invoice % has % credit note(s) attached (%) — cancel or detach those first — nothing was saved',
        v_inv.invoice_number, v_n, v_txt;
    end if;
    if v_inv.doc_kind = 'credit' and v_inv.credit_for_invoice_id is not null then
      select * into v_m2 from public.po_invoice_money where id = v_inv.credit_for_invoice_id;
      v_unpaid_before := v_m2.unpaid;
      if v_m2.alloc_total > 0 then v_warn := array_append(v_warn, 'credit_for_invoice_has_payments'); end if;
    end if;
    if v_inv.status = 'draft' then v_warn := array_append(v_warn, 'cancelled_from_draft'); end if;
    -- ═══ po-disc-2 · 판정 396 — 입고가 있는 인보이스는 취소를 막는다(다시 열기 po_invoice_confirm 과 같은 검사 · 이 인보이스의 goods 줄이 가리키는 PO 마다 · 크레딧으로 바로잡는다) ═══
    if v_inv.doc_kind = 'invoice' then
      for v_rp in
        select distinct p.id, p.po_number
        from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id join public.po p on p.id = pl.po_id
        where il.po_invoice_id = p_id and il.line_kind = 'goods'
        order by p.po_number
      loop
        if exists (select 1 from public.po_receipt r where r.po_id = v_rp.id) then
          raise exception 'The warehouse has received against PO % — a received invoice cannot be cancelled; correct it with a credit note — nothing was saved', v_rp.po_number;
        end if;
      end loop;
    end if;

    if v_inv.doc_kind = 'credit' and v_inv.status = 'confirmed' then v_crv := public.po_credit_cost_reverse(p_id, 'credit note ' || v_inv.invoice_number || ' cancelled'); end if;   -- po-disc-5a: 취소 전에 사건을 되돌린다(결제 검사 뒤 · 같은 트랜잭션)
    update public.po_invoice set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
    where id = p_id returning * into v_inv;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;     -- ②-b

    if v_inv.doc_kind = 'credit' and v_inv.credit_for_invoice_id is not null then
      select unpaid into v_unpaid_after from public.po_invoice_money where id = v_inv.credit_for_invoice_id;
    end if;
  else
    if v_inv.status <> 'cancelled' then
      raise exception '% % is % — only a cancelled document can be restored — nothing was saved', v_label, v_inv.invoice_number, v_inv.status;
    end if;
    v_new_status := case when v_inv.confirmed_at is not null then 'confirmed' else 'draft' end;
    if v_inv.credit_for_invoice_id is not null then
      select * into v_for from public.po_invoice where id = v_inv.credit_for_invoice_id;
      if v_for.status = 'cancelled' then v_warn := array_append(v_warn, 'credit_for_cancelled'); end if;
    end if;
    update public.po_invoice set status = v_new_status, cancelled_at = null, cancelled_by = null
    where id = p_id returning * into v_inv;
    if not found then raise exception '% was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_doc; end if;     -- ②-b
    if v_inv.doc_kind = 'credit' and v_new_status = 'confirmed' then                                       -- po-disc-5a(이견 2): 복구가 confirmed 로 돌아오면 사건을 다시 만든다
      v_cev := public.po_credit_cost_events(p_id, true);
      v_warn := v_warn || array(select jsonb_array_elements_text(v_cev -> 'warnings'));
    end if;
  end if;

  return jsonb_build_object(
    'target', 'invoice', 'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status,
    'cancelled_at', v_inv.cancelled_at, 'confirmed_at', v_inv.confirmed_at, 'restored', not p_cancel,
    'cost_reversed', v_crv, 'cost_events', v_cev,                                                           -- po-disc-5a
    'credit_for', case when v_inv.credit_for_invoice_id is not null then
        jsonb_build_object('invoice_id', v_inv.credit_for_invoice_id,
                           'invoice_number', (select f.invoice_number from public.po_invoice f where f.id = v_inv.credit_for_invoice_id),
                           'unpaid_before', v_unpaid_before, 'unpaid_after', v_unpaid_after) end,
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑧ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text;
begin
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'po_invoice_line' and column_name = 'credit_reason') <> 1 then v_bad := v_bad || ' column'; end if;
  if (select count(*) from pg_constraint where conname = 'po_invoice_line_credit_reason_ck') <> 1 then v_bad := v_bad || ' check'; end if;
  if (select count(*) from pg_trigger where not tgisinternal and tgname = 'po_invoice_line_credit_reason_guard') <> 1 then v_bad := v_bad || ' trigger'; end if;
  v_t := 'public.po_credit_reason_suggest(uuid, uuid, numeric, uuid)';
  if to_regprocedure(v_t) is null then v_bad := v_bad || ' suggest(missing)'; end if;
  if not has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || ' suggest(grants)'; end if;
  foreach v_t in array array['public.po_credit_cost_events(uuid, boolean)', 'public.po_credit_cost_reverse(uuid, text)', 'public.po_invoice_line_credit_reason_guard()'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
    if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(grants)', v_t); end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_invoice_create', 'po_invoice_line_add', 'po_invoice_line_update', 'po_invoice_detail', 'po_invoice_confirm', 'po_doc_cancel') and p.prosrc like '%po-disc-5a%') <> 6 then v_bad := v_bad || ' reissued-six'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_invoice_confirm', 'po_doc_cancel') and p.prosecdef) <> 2 then v_bad := v_bad || ' definer-two'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_invoice_line_delete', 'po_invoice_add_po_lines', 'inv_layer_post_cost_adjust', 'inv_cost_adjust_reverse', 'inv_layer_post_receipt', 'po_receipt_confirm_by', 'po_invoice_line_cost', 'po_invoice_discount_factor', 'po_detail') and p.prosrc like '%po-disc-5a%') <> 0 then v_bad := v_bad || ' untouched-functions-touched'; end if;
  if md5(pg_get_viewdef('public.po_invoice_money'::regclass)) <> '08f428cbc4a0534df0eaa08ade03aa38' then v_bad := v_bad || ' po_invoice_money-changed'; end if;
  if (select count(*) from public.inv_cost_adjust where source_type = 'po_credit') <> 0 then v_bad := v_bad || ' events-made-by-migration'; end if;
  if (select count(*) from public.po_invoice_line where credit_reason is not null) <> 0 then v_bad := v_bad || ' reason-backfilled'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM400', message = format('STOP - po-disc-5a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
