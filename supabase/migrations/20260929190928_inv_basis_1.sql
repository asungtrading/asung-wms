-- 20260929190928_inv_basis_1.sql — inv-basis-2 · ⑱-1 인보이스 확정 = PO 분할 · 입고 기준 = 확정 인보이스 · 인보이스 없으면 입고 불가 (Asung-IMS · 2026-09-29)
--   판정 88(po-module §11-i 2978 블록 원문 ①~⑧) · 92(오피스가 인보이스를 확정해 내려보내야 창고 작업이 시작된다 · 예외 없음) · 93 ⓐⓑⓒⓙⓛ · 96(PO 를 넘는 인보이스는 거부 · PO 를 먼저 고친다)
--   ① po_invoice_confirm 재발행(20260918003000:620 · md5 7a6ff0e2 바이트 그대로 + 확정 갈래: 발주마다 가르기 · 막는 것 셋 · Reopen 되붙임 · 반환에 split · reattached)
--   ② po_receipt_confirm_by 재발행(20260929010938:900 · md5 b3c04242 · 인보이스 없으면 거부 · 기준 = 확정 인보이스 − 앞선 입고 · ⓒ 분할 블록 → 닫기만 · split 키는 null)
--   ③ po_receipt_create_by 재발행(20260926213035:88 · md5 ed5269ae · 인보이스 없으면 거부 — wms_recv_start 의 새 입고도 여기를 지난다)
--   ④ 뷰 po_list 재발행(20260916210000:554 · 앞 36 칸 무변 · 끝에 has_confirmed_invoice · confirmed_invoiced_qty) ⑤ po_receipt_detail 재발행(20260928025627:1096 · md5 5143c59a · lines[].expected 더함 · over 기준 인보이스)
--   ⑥ po.split_by_invoice_id(형제를 만든 인보이스 · Reopen 되붙임의 열쇠) ⑦ po_uninvoiced_lines 는 무변(만들기 가드 · 초안 포함 — 두 초안이 같은 줄을 겹쳐 청구하지 않게) · comment 만
--   ⚠️ 준비(Caleb · 적용 전): 확정 인보이스 없는 PO 의 열린 입고(RCV-00029 · PO-02002)를 옛 규칙으로 끝내거나(놓고 Confirm) 지운다 — ⚠️ RCV-00029 에는 받아들인 off-PO(ABE10612 5 · 원장 · 레이어 542614)가 있어 지우면 재생성이 그 레이어를 잃는다(2026-09-29 시험 적용 실측) → 끝내는 쪽 · 아래 준비 가드가 0 이 아니면 적용을 멈춘다 · 검증 ~/asung/prompts/inv-basis-2-verify.sql
--   이름 · 인자 · 반환 모양 무변(create or replace · grant · comment 가 남는다) · 트랜스퍼 입고(tf_arrive)는 이 파일에 없다 — 무변은 tr-3a · tr-4b 확인 검증으로

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

-- ═══ 준비 가드(판정 92) — 확정 인보이스 없는 PO 의 열린 입고가 남아 있으면 적용을 멈춘다(마이그레이션은 지우지 않는다 · 사람이 Purchase Receipts 또는 WMS Admin · Receiving 에서 지운다) ═══
do $$
declare v_n int; v_txt text;
begin
  select count(*), string_agg(r.receipt_number || ' (' || p.po_number || ')', ', ' order by r.receipt_number) into v_n, v_txt
  from public.po_receipt r join public.po p on p.id = r.po_id
  where r.status = 'draft'
    and not exists (select 1 from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id join public.po_line pl on pl.id = il.po_line_id
                     where pl.po_id = p.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed');
  if v_n > 0 then
    raise exception 'STOP - % open receipt(s) sit on a PO without a confirmed invoice: %. Finish them under the old rule first (put away and Confirm in Purchase Receipts), or delete them (WMS Admin > Receiving > Delete) only if no off-PO item on them was accepted into the books, then apply this migration (ruling 88 (3) and 92). Nothing was changed.', v_n, v_txt;
  end if;
end $$;

-- ═══ ⑥ po.split_by_invoice_id — 이 형제를 만든 인보이스(확정 순간 분할) · Reopen 되붙임의 열쇠 · 입고 확정이 만들던 옛 형제(PO-02001b · 02011b)는 null ═══
alter table public.po add column if not exists split_by_invoice_id uuid references public.po_invoice (id) on delete set null;
create index if not exists po_split_by_invoice_idx on public.po (split_by_invoice_id) where split_by_invoice_id is not null;
comment on column public.po.split_by_invoice_id is 'inv-basis-2(판정 88 ⑤) — 이 문서를 갈라낸 인보이스(확정 순간) · Reopen(po_invoice_confirm p_confirm=false)이 이 값으로 형제를 찾아 되붙인다 · 옛 입고 분할 형제는 null';

-- ═══ ① po_invoice_confirm — 마지막 정의 바이트 그대로 + 확정 갈래 · Reopen 되붙임 ═══
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
             or exists (select 1 from public.po_line l where l.po_id = v_s.id and l.updated_at > l.created_at) then
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

-- ═══ ② po_receipt_confirm_by — 마지막 정의(tr-3a) 바이트 그대로 + 인보이스 문 · 기준 · 닫기만 ═══
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
    if x.counted <> x.expected then
      insert into public.po_receipt_diff (receipt_id, po_id, po_line_id, product_id, kind, expected_qty, received_qty)
      values (v_r.id, v_po.id, x.po_line_id, x.product_id, case when x.counted > x.expected then 'over' else 'short' end, greatest(x.expected, 0), x.counted);
      if x.counted > x.expected then v_over := v_over + 1; else v_short := v_short + 1; end if;
      v_rows := v_rows || jsonb_build_object('line_no', x.line_no, 'sku', x.sku, 'kind', case when x.counted > x.expected then 'over' else 'short' end,
                                             'expected_qty', greatest(x.expected, 0), 'received_qty', x.counted);
    end if;
    if x.expected - x.counted > 0 then v_rem_total := v_rem_total + (x.expected - x.counted); end if;
  end loop;

  -- ═══ ⓒ 닫기 — inv-basis-2 · 판정 88 ⑤ ⑥: 입고 확정은 더 이상 가르지 않는다(가르는 자리는 인보이스 확정 · po_invoice_confirm) · 덜 받은 몫은 short 차이로 남고 크레딧은 오피스 단추 · PO 는 닫힌다(입고 종료 · §11-b) ═══
  v_a_num := v_po.po_number;
  update public.po set status = 'closed', closed_at = v_now where id = v_po.id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n = 0 then raise exception 'PO % was not saved — it may have been changed by someone else just now — nothing was saved', v_po.po_number; end if;
  v_warn := array_append(v_warn, 'po_closed');
  if v_over > 0 then v_warn := array_append(v_warn, 'over_receipt'); end if;
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

  return jsonb_build_object(
    'receipt_id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', 'confirmed', 'confirmed_at', v_now, 'confirmed_by', v_staff,
    'receipt_lines_created', v_lines_n,
    'po', jsonb_build_object('id', v_po.id, 'number_before', v_po.po_number, 'number_after', v_a_num, 'status', 'closed', 'closed_at', v_now),
    'split', null,                                               -- inv-basis-2: 입고 확정은 가르지 않는다(키는 모양 무변 · 값은 늘 null · 덜 받은 몫은 diffs.short)
    'diffs', jsonb_build_object('over', v_over, 'short', v_short, 'rows', v_rows),
    'entered_units_cleared_lines', to_jsonb(v_cleared),
    'ledger', v_ledger,                                          -- ⭐ 원장 결과(rows_posted · qty_posted · qty_excess · lines[]) — 화면이 「재고에 들어갔다」를 말할 수 있게
    'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ③ po_receipt_create_by — 마지막 정의 바이트 그대로 + 인보이스 문 ═══
create or replace function public.po_receipt_create_by(
  p_staff        uuid,                              -- ⑤-3a 속: 부른 셸이 확인한 사람(판정 7) · 문은 셸에
  p_po_id        uuid,
  p_received_on  date default public.ims_today(),
  p_warehouse_id uuid default null                  -- po.ship_to_warehouse_id 가 null 일 때만 쓴다
) returns jsonb
language plpgsql
volatile
security definer                                   -- ⑤-3a: po_receipt* 의 RLS 가 receiving 을 요구한다 · 창고 사람은 셸의 문을 지나 여기로 · 표는 소유자로 쓴다
set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_po     public.po%rowtype;
  v_open   text;
  v_wh     uuid;
  v_whn    text;
  v_r      public.po_receipt%rowtype;
  v_warn   text[] := '{}';
begin
  if p_staff is null then raise exception 'po_receipt_create_by needs the acting staff id — nothing was saved'; end if;
  v_staff := p_staff;

  -- 만든 사람 — 서버 유도(po_create 선례 · 화면이 주지 않는다)

  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  -- ⬜3 confirmed 만 — draft(공급처에 안 갔다) · closed(입고 종료 · 남은 수량은 갈라진 문서로) · cancelled(안 온다)
  if v_po.status <> 'confirmed' then
    raise exception 'PO % is % — receiving can start only on a confirmed order% — nothing was saved',
      v_po.po_number, v_po.status,
      case v_po.status when 'closed' then ' (receiving is finished on this document; the remainder, if any, moved to the split document)'
                       when 'draft'  then ' (confirm it first)'
                       else '' end;
  end if;
  -- inv-basis-2 · 판정 88 ③ · 92 — 확정 인보이스가 붙은 PO 만 받는다(오피스 New receipt · 창고 wms_recv_start 둘 다 여기를 지난다)
  if not exists (select 1 from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id join public.po_line pl on pl.id = il.po_line_id
                  where pl.po_id = v_po.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed') then
    raise exception 'PO % has no confirmed invoice — the office confirms the supplier invoice first (Purchase Invoices), then receiving can start — nothing was saved', v_po.po_number;
  end if;
  -- ⭐⭐ PO 당 draft 하나 — 부분 유니크 대신 여기서(규칙 29) · 기존 번호를 문장에
  perform pg_advisory_xact_lock(hashtext('po_receipt:' || p_po_id::text));           -- 이견 12 — 둘이 동시에 열면 뒤 것이 앞 것을 본다(권한 불필요 · 트랜잭션 끝에 풀림)
  select r.receipt_number into v_open from public.po_receipt r where r.po_id = p_po_id and r.status = 'draft' order by r.created_at limit 1;
  if v_open is not null then
    raise exception 'PO % already has an open receipt (%) — continue that one or delete it first — nothing was saved', v_po.po_number, v_open;
  end if;
  -- 창고 — PO 의 배송지 · 없으면 인자 · 그것도 없으면 거부(빈은 창고의 것 · ims_last_bin 의 축)
  v_wh := coalesce(v_po.ship_to_warehouse_id, p_warehouse_id);
  if v_wh is null then
    raise exception 'PO % has no ship-to warehouse — pass p_warehouse_id — nothing was saved', v_po.po_number;
  end if;
  if v_po.ship_to_warehouse_id is null then v_warn := array_append(v_warn, 'warehouse_from_parameter'); end if;
  select w.name into v_whn from public.ref_warehouse w where w.id = v_wh and w.is_active;
  if v_whn is null then raise exception 'Warehouse % not found or inactive — nothing was saved', v_wh; end if;
  if p_received_on is not null and p_received_on > public.ims_today() then v_warn := array_append(v_warn, 'received_on_in_future'); end if;

  insert into public.po_receipt (po_id, warehouse_id, received_on, status, created_by)
  values (p_po_id, v_wh, coalesce(p_received_on, public.ims_today()), 'draft', v_staff)
  returning * into v_r;

  return jsonb_build_object(
    'id', v_r.id, 'receipt_number', v_r.receipt_number, 'status', v_r.status,
    'po_id', v_po.id, 'po_number', v_po.po_number,
    'warehouse_id', v_wh, 'warehouse_name', v_whn, 'received_on', v_r.received_on,
    'created_by', v_staff, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ④ 뷰 po_list — 마지막 정의 바이트 그대로 + cinv CTE · 끝 두 칸 ═══
create or replace view public.po_list
  with (security_invoker = true) as
with l as (
  select po_id,
         count(*)::int                                      as line_count,
         coalesce(sum(qty_ea), 0)                           as ordered_qty,
         coalesce(sum(round(qty_ea * unit_price, 2)), 0)    as subtotal
  from public.po_line
  group by po_id
),
r as (
  select pl.po_id, coalesce(sum(rl.qty_ea), 0) as received_qty
  from public.po_receipt_line rl
  join public.po_line pl on pl.id = rl.po_line_id
  group by pl.po_id
),
d as (
  select po_id, public.po_mul(1 - percent / 100) as factor
  from public.po_discount
  group by po_id
),
c as (
  select po_id, coalesce(sum(amount), 0) as charge_total
  from public.po_charge_alloc
  group by po_id
),
sp as (
  select split_from_id as po_id, count(*)::int as split_to_count
  from public.po
  where split_from_id is not null
  group by split_from_id
),
il as (
  select x.po_invoice_id, pl.po_id,
         coalesce(sum(x.qty_ea)                          filter (where x.line_kind = 'goods'), 0) as goods_qty,
         coalesce(sum(round(x.qty_ea * x.unit_price, 2)) filter (where x.line_kind = 'goods'), 0) as goods_amount
  from public.po_invoice_line x
  join public.po_line pl on pl.id = x.po_line_id
  group by x.po_invoice_id, pl.po_id
),
inv as (
  select x.po_id,
         count(*)::int                        as invoice_count,
         coalesce(sum(x.goods_qty), 0)        as invoiced_qty,
         coalesce(sum(x.goods_amount), 0)     as invoiced_total,
         coalesce(sum(m.alloc_total), 0)      as paid,
         coalesce(sum(m.unpaid), 0)           as unpaid
  from il x
  join public.po_invoice i on i.id = x.po_invoice_id
  join public.po_invoice_money m on m.id = i.id
  where i.doc_kind = 'invoice' and i.status <> 'cancelled'
  group by x.po_id
),
cred as (                                     -- 걸린 크레딧(줄 · credit_for) — ⚠️ credit_po_id 는 채번의 축이라 여기 안 센다(po_detail credits[] 와 같은 집합)
  select po_id, count(*)::int as credit_count
  from (
    select x.po_id, x.po_invoice_id as credit_id
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    where k.doc_kind = 'credit' and k.status <> 'cancelled'
    union
    select x.po_id, k.id
    from public.po_invoice k
    join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.doc_kind = 'credit' and k.status <> 'cancelled'
  ) u
  group by po_id
),
chg as (
  select a.po_id,
         count(*)::int                 as charge_count,
         coalesce(sum(m.paid), 0)      as paid,
         coalesce(sum(m.unpaid), 0)    as unpaid
  from public.po_charge_alloc a
  join public.po_charge c on c.id = a.po_charge_id
  join public.po_charge_money m on m.id = c.id
  where c.status <> 'cancelled'
  group by a.po_id
),
cinv as (                                     -- inv-basis-2 · 판정 88 ③: 확정 goods 인보이스 합(크레딧 · 초안 제외) — 입고 목록(오피스 · 창고)이 거르는 재료
  select pl.po_id, coalesce(sum(x.qty_ea), 0) as confirmed_invoiced_qty
  from public.po_invoice_line x
  join public.po_invoice i on i.id = x.po_invoice_id
  join public.po_line pl on pl.id = x.po_line_id
  where x.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed'
  group by pl.po_id
),
nums as (                                     -- 검색용 문서 번호 모음(취소 포함) · ⭐ [2026-09-16 저녁] + 공급처 참조 번호 · 번호를 낸 발주 경로(줄 없는 크레딧도 그 발주에서 찾힌다)
  select po_id, string_agg(distinct num, ' ' order by num) as doc_numbers
  from (
    select x.po_id, k.invoice_number as num
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    union
    select x.po_id, k.invoice_number
    from public.po_invoice k join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.doc_kind = 'credit'
    union
    select x.po_id, k.supplier_ref_number
    from il x join public.po_invoice k on k.id = x.po_invoice_id
    where k.supplier_ref_number is not null
    union
    select x.po_id, k.supplier_ref_number
    from public.po_invoice k join il x on x.po_invoice_id = k.credit_for_invoice_id
    where k.supplier_ref_number is not null
    union
    select k.credit_po_id, k.invoice_number
    from public.po_invoice k where k.credit_po_id is not null
    union
    select k.credit_po_id, k.supplier_ref_number
    from public.po_invoice k where k.credit_po_id is not null and k.supplier_ref_number is not null
    union
    select a.po_id, c.charge_number
    from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id
  ) u
  group by po_id
)
select
  p.id,
  p.po_number,
  p.status,
  p.order_date,
  p.supplier_id,
  s.name                                                       as supplier_name,
  cur.code                                                     as currency_code,
  coalesce(l.line_count, 0)                                    as line_count,
  coalesce(l.ordered_qty, 0)                                   as ordered_qty,
  coalesce(r.received_qty, 0)                                  as received_qty,
  coalesce(l.subtotal, 0)                                      as subtotal,
  round(coalesce(d.factor, 1), 6)                              as discount_factor,
  round(coalesce(l.subtotal, 0) * coalesce(d.factor, 1), 2)    as net_total,
  coalesce(c.charge_total, 0)                                  as charge_total,
  sf.po_number                                                 as split_from_number,
  coalesce(sp.split_to_count, 0)                               as split_to_count,
  p.confirmed_at,
  p.closed_at,
  p.cancelled_at,
  p.note,
  p.created_at,
  p.updated_at,
  p.required_by,
  coalesce(inv.invoice_count, 0)                               as invoice_count,
  coalesce(inv.invoiced_qty, 0)                                as invoiced_qty,
  coalesce(inv.invoiced_total, 0)                              as invoiced_total,
  coalesce(cred.credit_count, 0)                               as credit_count,
  coalesce(chg.charge_count, 0)                                as charge_count,
  coalesce(inv.paid, 0) + coalesce(chg.paid, 0)                as paid_total,
  coalesce(inv.unpaid, 0) + coalesce(chg.unpaid, 0)            as unpaid_total,
  nums.doc_numbers,
  case when coalesce(l.line_count, 0) = 0                                                   then 'none'
       when p.status = 'draft' or (p.status = 'cancelled' and p.confirmed_at is null)       then 'partial'
       else 'done' end                                         as order_phase,
  case when coalesce(inv.invoiced_qty, 0) = 0                                               then 'none'
       when inv.invoiced_qty < coalesce(l.ordered_qty, 0)                                   then 'partial'
       else 'done' end                                         as invoice_phase,
  case when coalesce(r.received_qty, 0) = 0                                                 then 'none'
       when r.received_qty < coalesce(l.ordered_qty, 0)                                     then 'partial'
       else 'done' end                                         as receipt_phase,
  case when coalesce(chg.charge_count, 0) = 0                                               then 'none'
       else 'done' end                                         as charge_phase,
  case when coalesce(inv.invoice_count, 0) + coalesce(chg.charge_count, 0) = 0              then 'none'
       when coalesce(inv.unpaid, 0) + coalesce(chg.unpaid, 0) > 0
            then case when coalesce(inv.paid, 0) + coalesce(chg.paid, 0) > 0 then 'partial' else 'none' end
       else 'done' end                                         as payment_phase,
  (cinv.po_id is not null)                                     as has_confirmed_invoice,     -- inv-basis-2 · 끝에 더한 두 칸(앞 36 칸 무변)
  coalesce(cinv.confirmed_invoiced_qty, 0)                     as confirmed_invoiced_qty
from public.po p
join public.supplier     s   on s.id   = p.supplier_id
join public.ref_currency cur on cur.id = p.currency_id
left join l    on l.po_id    = p.id
left join r    on r.po_id    = p.id
left join d    on d.po_id    = p.id
left join c    on c.po_id    = p.id
left join public.po sf on sf.id = p.split_from_id
left join sp   on sp.po_id   = p.id
left join inv  on inv.po_id  = p.id
left join cred on cred.po_id = p.id
left join chg  on chg.po_id  = p.id
left join nums on nums.po_id = p.id
left join cinv on cinv.po_id = p.id;

-- ═══ ⑤ po_receipt_detail — 마지막 정의 바이트 그대로 + expected · over 기준 ═══
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
      'over_lines', count(*) filter (where l.counted > l.ordered - l.received_before),
      'short_lines', count(*) filter (where l.counted < l.ordered - l.received_before),
      'open_diffs', (select count(*) from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null))
    from lines l
  ),
  'warnings', (
    select coalesce(jsonb_agg(v), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when (select p.status from r join public.po p on p.id = r.po_id) <> 'confirmed' and (select status from r) = 'draft' then 'po_not_confirmed' end,
        case when exists (select 1 from lines l where l.counted > l.ordered - l.received_before) then 'over_receipt' end,
        case when exists (select 1 from w x where x.bin_id is null) then 'unassigned_rows' end,
        case when not exists (select 1 from w) then 'nothing_counted' end,
        case when exists (select 1 from lines l where l.received_here <> l.counted) and (select status from r) = 'confirmed' then 'receipt_lines_differ_from_work' end,
        case when exists (select 1 from public.po_receipt_diff d where d.receipt_id = p_receipt_id and d.resolved_at is null) then 'open_diffs' end
      ], null)) as v) t
  )
) end;
$$;

-- ═══ ⑦ po_uninvoiced_lines — 무변 · 뜻만 적는다 ═══
comment on function public.po_uninvoiced_lines(uuid) is '⑤ 발주 라인의 미청구 수량 — remaining_qty = qty_ea − 취소 안 된 인보이스 goods 줄 합(⭐ 초안 포함 · 크레딧은 안 뺀다) · ⚠️ inv-basis-2(판정 88 ②): 이것은 **인보이스를 만들 때의 가드**(두 초안이 같은 줄을 겹쳐 청구하지 않게)라 초안을 센다 · **입고 기준**은 확정 인보이스만(po_receipt_confirm_by · po_receipt_detail.expected) — 두 정의가 다른 것은 뜻이 달라서다';
