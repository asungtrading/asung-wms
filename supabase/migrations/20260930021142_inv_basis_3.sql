-- inv-basis-8 — 판정 103: 인보이스 Reopen 의 「형제를 손댔다」 판정을 분할 순간과 비교 (Asung-IMS · 2026-09-29)
--   po_invoice_confirm 재발행 — 마지막 정의 20260929190928_inv_basis_1.sql:58(DB prosrc md5 c93b3337 와 같음) 바이트 그대로 + 한 줄:
--     형제 줄 검사 `l.updated_at > l.created_at` → `l.updated_at > v_s.created_at`
--     인보이스에서 통째로 뺀 줄은 새 줄이 아니라 원래 줄을 형제로 옮긴다(created_at = 원래 PO 에 넣은 시각 · updated_at = 분할 순간) — 아무도 안 건드려도 늘 「손댔다」여서 Reopen 이 막혔다(PO-02028a 실측)
--     분할 순간(형제 PO 의 created_at = 분할 트랜잭션의 now())과 비교하면 옮긴 줄 · 줄인 몫으로 새로 만든 줄은 통과하고, 분할 뒤 고친 줄은 여전히 막힌다(판정 88 ⑦ 그대로)
--   형제 머리 검사 `v_s.updated_at > v_s.created_at` 은 그대로(머리는 분할에서 새로 만든다)
--   이름 · 인자 · 반환 · grant · comment 무변(create or replace) · UTC 이름 · 가드 첫 문장 · begin/commit 없음 · 부분 유니크 0

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

-- ═══ po_invoice_confirm — 20260929190928:58 바이트 그대로 + 한 줄(판정 103) ═══
create or replace function public.po_invoice_confirm(
  p_invoice_id uuid,
  p_confirm    boolean default true
) returns jsonb
language plpgsql
volatile
security invoker
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
    update public.po_invoice set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_invoice_id returning * into v_inv;
    if not found then raise exception '% % was not saved — it may have been removed or changed by someone else just now — nothing was saved', v_label, v_num; end if;   -- ②-b
  else
    if v_inv.status <> 'confirmed' then raise exception '% % is % — only a confirmed document can be reopened — nothing was saved', v_label, v_inv.invoice_number, v_inv.status; end if;
    if v_m.alloc_total > 0 then
      raise exception '% % has payments applied (%) — cannot reopen while paid/used; remove the payment allocation first — nothing was saved', v_label, v_inv.invoice_number, v_m.alloc_total;
    end if;
    select count(*) into v_cred from public.po_invoice c where c.credit_for_invoice_id = p_invoice_id and c.status <> 'cancelled';
    if v_cred > 0 then v_warn := array_append(v_warn, 'has_attached_credits'); end if;
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
    'warnings', to_jsonb(v_warn));
end;
$$;
