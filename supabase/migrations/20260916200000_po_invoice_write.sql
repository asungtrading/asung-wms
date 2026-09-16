-- ─────────────────────────────────────────────────────────────
-- ⑤ 인보이스 · 크레딧 만들기 + 할인 줄 편집 — 뒷단 (테스트 DB Asung-IMS · 2026-09-16 저녁)
--   po_uninvoiced_lines(po)                        발주 라인의 미청구 수량 (만들기·더하기·화면이 같이 쓴다)
--   po_invoice_create(kind, number, …, commit)     ⭐ 인보이스·크레딧 초안 — PO 라인을 미청구 수량으로 복사 · ⭐ 크레딧은 「인보이스 − 입고」 차이로 자동 채우기 · 미리 보기
--   po_invoice_add_po_lines(invoice, po, commit)   ⭐ 다른 PO 의 미청구 라인을 통째로 더한다(인보이스 하나가 발주 둘에 걸친다 · §11-g)
--   po_invoice_line_add / _update / _delete        줄 하나씩 (다른 PO 의 라인 하나 · 운임 줄 · is_payable · 단위 칸)
--   po_invoice_confirm(invoice, confirm)           ⭐ 확정 = 「공급처 문서를 우리 장부에 받아들였다」 · 되돌리기는 결제가 없을 때만
--   po_discount_save / po_discount_delete          ⭐⭐ 할인 줄 세 자리(supplier_discount · po_discount · po_invoice_discount)를 한 쌍으로
--   po_invoice_detail(invoice)                     인보이스 화면의 상세 RPC (돈은 po_invoice_money)
--   po_invoice_list                                인보이스·크레딧 목록 뷰 (PO 없는 조정 크레딧이 보이는 유일한 자리)
--
-- 정본: docs/design/po-module.md §11-e(할인 두 층) · §11-g(인보이스·크레딧 · 확정이 일으키는 셋) · §3-b D(supplier_discount · 마스터는 제안) · §11-i(인보이스가 대체로 먼저 온다) · §13 · §13-f
-- 앞 정의: 20260916190000(po_detail · po_create · po_invoice_money · po_charge_money — ⚠️ 이 파일은 그것들을 **바꾸지 않는다** · 읽기만) · 20260916181719(쓰기 RPC 넷 · 관례의 원천) · 20260916175003(크레딧 표)
-- 지시서: ~/asung/prompts/po-invoice-write.md · 검토 이견 1~18(2026-09-16 저녁 · 전부 받음 · 15 목록 뷰는 「빠뜨린 것」으로 범위에 들어옴)
-- ⚠️ 파일명 — 만든 시각은 19:37 인데 앞 파일이 190000 라 그 뒤에 서도록 200000 으로 붙였다. 표 변경 없음 · 새 객체만(create · or replace 불필요).
-- ❌ 이번 범위 밖 — 비용 문서 만들기·배분 · 결제 만들기(⚠️ 한 결제는 한 통화 · Caleb) · 원가 배분(금액 비례 · 잔돈 · SKU 순 — 원장 이식 차수 §11-j) · 입고·분할(PO 자동 닫힘)
--
-- ⭐⭐ 할인은 두 층이다 — 라인에 할인 칸은 없다 · 문서 위에 줄로 서서 차례로 곱한다(po_mul · 새 식 없음)
--   층 ① supplier_discount     「늘 주는 할인」 — 발주를 만들 때 po_create 가 po_discount 로 복사한다([실측] 지금 0행 · 구조는 있고 따라올 것이 없을 뿐)
--   층 ② po_discount           「이 발주의 할인」 — 따라온 것을 고치거나 · 없던 줄을 더한다(「이번 인보이스에 한해 10%」 · Caleb) · ⭐ 인보이스를 만들 때 po_invoice_discount 로 복사 제안된다(§11-e 「→ 표」)
--        po_invoice_discount   「이 인보이스의 할인」 — ⭐ 원가로 내려가는 정본(§11-g ①) · 크레딧에는 자동 복사 없음(공급처 문서에 적힌 대로)
--   📌 마스터는 제안이지 잠금이 아니다 — supplier_discount_id 가 「따라온 줄」(from supplier)과 「여기서 더한 줄」(added here)을 가른다(화면 Source 열)
--   ⭐ 세 자리를 RPC 한 쌍(po_discount_save · po_discount_delete · p_target 으로 가른다)으로 여는 이유(검토 이견 1):
--      ① seq 는 곱해지는 차례라 뜻이 있고 unique(문서, seq) — 안 주면 max+1 을 RPC 가 정한다(화면 세 곳이 각자 세면 어긋난다) · 지운 뒤 빈 seq 는 둔다(띄어 매기기 관례 · 순서만 뜻이 있다)
--      ② 상태 검사가 다른 행에 있다 — po_discount 는 closed·cancelled 발주를, po_invoice_discount 는 draft 아닌 인보이스를 막아야 한다(§5 「쓰기는 RPC 가 저장 전에 본다」)
--      ③ supplier_discount 삭제는 문서 줄이 FK(no action)로 가리키면 어차피 막힌다 — 사람이 읽을 문장으로 「비활성으로 내려라」
--
-- ⭐⭐ 인보이스 만들기 — PO 에서 시작한다(Caleb · Cin7 Invoice 탭 Copy 와 같은 흐름 · 전용 화면은 다음 차수 · 이번은 그 화면이 부를 것)
--   머리     공급처·통화·환율·결제조건은 **PO 에서** 따라온다(검토 이견 3) — PO 가 그날 값을 박아 뒀다. 공급처를 다시 읽으면 「PO 만든 뒤 바뀐 마스터」가 섞인다. due_date 는 사람이(34행 비어 있음 §10-k).
--   줄       ⭐ **미청구 수량**으로 채운다(검토 이견 4 · Caleb 「맞다」) = 주문 수량 − 취소 안 된 인보이스가 이미 청구한 수량(라인별) · 0 이하면 그 줄은 넣지 않는다.
--            입고 수량은 「인보이스가 대체로 먼저 온다」(§11-i)라 0 이 많아 못 쓴다 · 주문 수량은 둘째 인보이스([실물] PO-01010 한 PO 에 여러 장)에서 이중 청구가 된다.
--            단가는 po_line.unit_price(공급처 실제 단가는 사람이 고친다) · 단위 칸 넷은 수량이 주문 수량과 같을 때만 복사(일부면 entered_qty 가 틀린 값이 되므로 EA=null)
--   할인     ⭐ po_discount → po_invoice_discount 복사 제안(검토 이견 5 · §11-e 「→ 표」에 이미 있었다 · 지시서의 「미결」은 오기 · Caleb) · p_copy_discounts 로 끌 수 있다 · 크레딧은 복사 없음(§11-g 확정)
--            대가(공급처가 안 준 할인이 조용히 들어감)는 total_amount 대조가 잡는다(§13 실증 −253.90) · Ampro 는 늘 세 줄
--   총액     ⭐ 안 주면 **0** + warnings total_amount_missing(검토 이견 6) — 계산값을 넣으면 diff 가 0 이 되어 대조값의 뜻이 사라진다(찍힌 값이 없는데 맞는 것처럼 보인다). 0 이면 diff = −계산값이 크게 보여 「아직 안 넣었다」가 드러난다.
--   미리 보기 p_commit=false 가 기본(po_lines_paste 선례) — 만들지 않고 같은 모양으로 돌려준다 · 번호 중복은 미리 보기에서 invoice_number_exists 로 먼저 보이고 commit 에서는 읽을 문장으로 거부
--
-- ⭐⭐ 크레딧 자동 채우기(Caleb 「화면이 물어보고 누르면 차이만큼 줄이 채워진 초안 · 만드는 것은 사람 · 숫자를 손으로 옮기지 않는다」)
--   p_doc_kind='credit' + p_credit_for_invoice_id → 그 인보이스의 goods 줄마다 **차이 = 인보이스 수량 − 그 po_line 의 입고 합** · 차이 > 0 인 줄만 · 단가는 인보이스 줄 단가 · 단위 칸은 EA
--   ⚠️ 전제: 그 라인의 청구가 이 인보이스 한 장(문서 분할 덕에 대체로 참 · §11-e). 같은 라인을 다른 인보이스도 가리키면 그 줄에 line_has_other_invoices 경고.
--   차이가 하나도 없으면(검토 이견 8): 미리 보기는 줄마다 no_difference 를, commit 은 **빈 초안**을 만들고 warnings no_qty_difference — 화면은 차이가 있을 때만 물어보므로 여기 오는 일이 드물고, 왔다면 사람이 눌렀다.
--     거부하면 「수량 차이는 없지만 단가 차이로 받은 크레딧」 실물을 못 넣는다. 빈 초안은 지울 수 있다. [ⓓ③ 실측] AMP-778812 는 200/200 · 600/600 · 120/120 이라 이 경로를 탄다.
--   크레딧 머리의 원천 셋(검토 이견 9): credit_for 인보이스 → p_po_id → p_supplier_id(조정 크레딧 · 줄 비움 · 통화는 공급처 기본). 인보이스는 p_po_id 필수.
--   ⚠️ PO 도 인보이스도 안 가리키는 크레딧은 po_detail 어디에도 안 보인다 — po_invoice_list 가 받는다(그래서 목록 뷰가 이번 범위다).
--
-- ⭐⭐ 확정의 뜻(검토 이견 12·13 · Caleb 「그 구분이 정확하다」)
--   인보이스 확정 = **「공급처 문서를 우리 장부에 받아들였다」** — 금액·수량이 문서와 대조됐고 이제 미지급이 생기고 할인이 원가로 내려간다(원가 배분 자체는 원장 차수). draft = 입력 중(대조 전).
--   발주 Confirm(「보낼 수량과 라인이 정해졌다」 · 잠금 아님 · §11-b)과 다르다 — 인보이스는 **장부**다. 확정 뒤 줄·할인·총액을 고치면 이미 내려간 원가와 생긴 미지급이 소리 없이 바뀐다.
--   ⇒ 줄 RPC 셋·할인 RPC·PO 줄 더하기는 **draft 만** 받는다. 되돌리려면 po_invoice_confirm(…, false) — 결제 충당(alloc_total)이 붙었으면 거부.
--   확정 전 검사: 줄 0개 → 거부 · 크레딧이 인보이스 아닌 것/다른 공급처를 가리킴 → 거부 · total_amount 0 → 경고(샘플 인보이스 실물) · diff ≠ 0 → **경고만**(반올림 · other 할인 미결 · 정본은 찍힌 값 · Cin7 도 안 막는다)
--   취소는 지금처럼 PostgREST update(⬜ 결제 붙은 문서의 취소 거부는 결제 차수 RPC 가 대상 검사로 받는다)
--
-- ⭐ 관례(181719 그대로) — plpgsql · volatile · security invoker · 「nothing was saved」 예외 · array_append(⚠️ text[] || 리터럴 금지 · 13-e ①) · 다른 행을 봐야 하는 것은 저장 전에 · revoke public/anon
--   만든 사람·확정한 사람은 auth.uid() → ims_staff.id 서버 유도(po_create 관례) — commit·confirm 때만 본다(미리 보기는 psql 에서도 돈다)
-- ⚠️ 돈의 식은 여기 없다 — po_invoice_money(190000)가 정본. po_invoice_detail · po_invoice_list · po_invoice_confirm 은 그 뷰를 읽는다.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ po_uninvoiced_lines(p_po_id) — 발주 라인마다 주문 · 청구됨 · 미청구 · 입고 ═══
-- 만들기·더하기가 같은 규칙을 쓰고 화면도 「아직 청구 안 된 것」을 이걸로 본다. 전 라인을 돌려준다(remaining ≤ 0 포함) — 거르는 것은 부르는 쪽.
create function public.po_uninvoiced_lines(p_po_id uuid)
returns table (
  po_line_id uuid, line_no integer, product_id uuid, sku text, product_name text, supplier_sku text,
  qty_ea numeric, invoiced_qty numeric, remaining_qty numeric, received_qty numeric,
  unit_price numeric, entered_unit_product_id uuid, entered_qty numeric, entered_pack_factor numeric
)
language sql stable security invoker
set search_path = public, pg_temp
as $$
  select pl.id, pl.line_no, pl.product_id, pr.sku, pr.name, pl.supplier_sku,
         pl.qty_ea,
         coalesce(iv.q, 0)                 as invoiced_qty,        -- 취소 안 된 인보이스(doc_kind=invoice)의 goods 줄 합
         pl.qty_ea - coalesce(iv.q, 0)     as remaining_qty,       -- ⭐ 미청구 · 음수면 초과 청구(그대로 보인다)
         coalesce(rc.q, 0)                 as received_qty,
         pl.unit_price, pl.entered_unit_product_id, pl.entered_qty, pl.entered_pack_factor
  from public.po_line pl
  join public.product pr on pr.id = pl.product_id
  left join (select il.po_line_id, sum(il.qty_ea) as q
             from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
             where i.doc_kind = 'invoice' and i.status <> 'cancelled' and il.line_kind = 'goods'
             group by il.po_line_id) iv on iv.po_line_id = pl.id
  left join (select po_line_id, sum(qty_ea) as q from public.po_receipt_line group by po_line_id) rc on rc.po_line_id = pl.id
  where pl.po_id = p_po_id
  order by pl.line_no;
$$;
comment on function public.po_uninvoiced_lines(uuid) is '⑤ 발주 라인의 미청구 수량 — remaining_qty = qty_ea − 취소 안 된 인보이스 goods 줄 합(크레딧은 안 뺀다 · 진행도가 아니다). 인보이스 만들기·PO 줄 더하기가 이걸로 채우고 화면도 본다. 전 라인을 돌려준다. 정본 po-module §11-g · 2026-09-16';

-- ═══ po_invoice_create — 인보이스·크레딧 초안 (미리 보기 = 같은 모양) ═══
-- POST /rest/v1/rpc/po_invoice_create
--   인보이스  {"p_doc_kind":"invoice","p_invoice_number":"INV-1","p_po_id":"<uuid>","p_invoice_date":"2026-09-16","p_total_amount":586.92,"p_commit":true}
--   크레딧    {"p_doc_kind":"credit","p_invoice_number":"CN-1","p_credit_for_invoice_id":"<uuid>","p_commit":true}     ← 차이만큼 줄 자동
--             {"p_doc_kind":"credit","p_invoice_number":"CN-2","p_po_id":"<uuid>"} · {"…","p_supplier_id":"<uuid>"}       ← 조정 크레딧 · 줄 비움
-- → { committed, id, doc_kind, invoice_number, header_source('invoice'|'po'|'supplier'), supplier_id, supplier_name, currency_id, currency_code, payment_term_name, total_amount,
--     line_count, lines[], discounts[], discounts_copied, warnings[] }
--   lines[] 인보이스: { n, verdict('ok'|'fully_invoiced'), po_line_id, po_number, po_line_no, sku, qty_ordered, invoiced_qty, remaining_qty, qty_ea, unit_price, line_no, inserted, message }
--   lines[] 크레딧:   { n, verdict('ok'|'no_difference'|'over_received'), po_line_id, po_number, po_line_no, sku, invoice_qty, received_qty, diff_qty, qty_ea, unit_price, line_no, inserted, message }
--   warnings: total_amount_missing · invoice_number_exists(미리 보기만 · commit 은 거부) · discounts_copied_from_po · no_uninvoiced_lines · no_qty_difference · currency_defaulted · due_date_on_credit
create function public.po_invoice_create(
  p_doc_kind              text,                       -- 'invoice' | 'credit'
  p_invoice_number        text,                       -- 공급처가 준 번호 · 앞뒤 공백만 자른다
  p_po_id                 uuid    default null,       -- 인보이스: 필수 · 크레딧: 머리 원천 둘째
  p_credit_for_invoice_id uuid    default null,       -- 크레딧만 · 있으면 줄 자동 채우기(차이)
  p_supplier_id           uuid    default null,       -- 크레딧 머리 원천 셋째(조정 크레딧)
  p_invoice_date          date    default null,       -- 안 주면 오늘
  p_due_date              date    default null,       -- 사람이 넣는다(§10-k) · 크레딧은 없다
  p_total_amount          numeric default null,       -- ⭐ 찍힌 총액 · 안 주면 0 + 경고(계산값을 넣지 않는다)
  p_copy_discounts        boolean default true,       -- 인보이스만 · po_discount → po_invoice_discount 제안
  p_commit                boolean default false       -- false = 미리 보기(넣지 않는다)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff        uuid;
  v_num          text;
  v_kind_label   text;
  v_po           public.po%rowtype;
  v_for          public.po_invoice%rowtype;
  v_sup          public.supplier%rowtype;
  v_source       text;
  v_supplier_id  uuid;  v_currency_id uuid;  v_rate numeric;  v_pt_id uuid;  v_pt_name text;
  v_sup_name     text;  v_cur_code text;
  v_exists       int;
  v_inv_id       uuid;
  v_warn         text[] := '{}';
  v_lines        jsonb  := '[]'::jsonb;
  v_discs        jsonb  := '[]'::jsonb;
  v_n            int := 0;
  v_ins          int := 0;
  v_ok           int := 0;
  v_disc_n       int := 0;
  r              record;
  v_verdict      text;
  v_qty          numeric;
  v_full         boolean;
  v_msgs         text[];
  v_other        int;
begin
  if p_doc_kind not in ('invoice', 'credit') then
    raise exception 'p_doc_kind must be ''invoice'' or ''credit'' — nothing was saved';
  end if;
  v_kind_label := case p_doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  v_num := nullif(regexp_replace(coalesce(p_invoice_number, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
  if v_num is null then
    raise exception '% number is required — nothing was saved', v_kind_label;
  end if;

  -- ── 머리의 원천 (검토 이견 3·9) ──
  if p_doc_kind = 'invoice' then
    if p_po_id is null then
      raise exception 'An invoice starts from a PO — p_po_id is required — nothing was saved';
    end if;
    if p_credit_for_invoice_id is not null then
      raise exception 'p_credit_for_invoice_id is for credit notes only — nothing was saved';
    end if;
  end if;

  if p_credit_for_invoice_id is not null then                                   -- ① 크레딧 · 어느 인보이스에 대한 것 → 그 인보이스에서
    select * into v_for from public.po_invoice where id = p_credit_for_invoice_id;
    if not found then
      raise exception 'Invoice % not found (credit_for) — nothing was saved', p_credit_for_invoice_id;
    end if;
    if v_for.doc_kind <> 'invoice' then
      raise exception 'Credit note % cannot be for another credit note (%) — nothing was saved', v_num, v_for.invoice_number;
    end if;
    v_supplier_id := v_for.supplier_id; v_currency_id := v_for.currency_id; v_rate := v_for.exchange_rate;
    v_pt_id := v_for.payment_term_id;   v_pt_name := v_for.payment_term_name;   v_source := 'invoice';
  end if;

  if p_po_id is not null then                                                   -- ② PO 에서 (인보이스는 항상 여기)
    select * into v_po from public.po where id = p_po_id;
    if not found then
      raise exception 'PO % not found — nothing was saved', p_po_id;
    end if;
    if v_source is null then
      v_supplier_id := v_po.supplier_id; v_currency_id := v_po.currency_id; v_rate := v_po.exchange_rate;
      v_pt_id := v_po.payment_term_id;   v_pt_name := v_po.payment_term_name;   v_source := 'po';
    elsif v_po.supplier_id <> v_supplier_id then
      raise exception 'PO % belongs to a different supplier than invoice % — nothing was saved', v_po.po_number, v_for.invoice_number;
    end if;
  end if;

  if v_source is null then                                                      -- ③ 조정 크레딧 · 공급처에서 (줄 비움)
    if p_supplier_id is null then
      raise exception 'A credit note needs one of: p_credit_for_invoice_id, p_po_id or p_supplier_id — nothing was saved';
    end if;
    select * into v_sup from public.supplier where id = p_supplier_id;
    if not found then
      raise exception 'Supplier % not found — nothing was saved', p_supplier_id;
    end if;
    v_supplier_id := v_sup.id; v_pt_id := v_sup.payment_term_id; v_pt_name := v_sup.payment_term_name; v_source := 'supplier';
    v_currency_id := v_sup.currency_id;
    if v_currency_id is null then                                               -- po_create 와 같은 폴백(inv_config.base_currency)
      select c.id into v_currency_id from public.ref_currency c join public.inv_config k on k.key = 'base_currency' and k.value = c.code;
      if v_currency_id is null then
        raise exception 'Supplier has no currency and inv_config.base_currency does not point at a ref_currency row — nothing was saved';
      end if;
      v_warn := array_append(v_warn, 'currency_defaulted');
    end if;
  end if;

  select s.name into v_sup_name from public.supplier s where s.id = v_supplier_id;
  select c.code into v_cur_code from public.ref_currency c where c.id = v_currency_id;

  -- ── 번호 중복 — 미리 보기는 경고 · commit 은 읽을 문장으로 거부(unique (supplier_id, doc_kind, invoice_number)) ──
  select count(*) into v_exists from public.po_invoice
   where supplier_id = v_supplier_id and doc_kind = p_doc_kind and invoice_number = v_num;
  if v_exists > 0 then
    if p_commit then
      raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, v_sup_name;
    end if;
    v_warn := array_append(v_warn, 'invoice_number_exists');
  end if;
  if p_total_amount is null then v_warn := array_append(v_warn, 'total_amount_missing'); end if;
  if p_doc_kind = 'credit' and p_due_date is not null then v_warn := array_append(v_warn, 'due_date_on_credit'); end if;

  -- ── commit: 머리 한 행 (만든 사람은 서버 유도) ──
  if p_commit then
    select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
    if v_staff is null then
      raise exception 'No active staff record for this login — nothing was saved';
    end if;
    insert into public.po_invoice (supplier_id, doc_kind, invoice_number, invoice_date, due_date, payment_term_id, payment_term_name,
                                   currency_id, exchange_rate, total_amount, status, created_by, credit_for_invoice_id)
    values (v_supplier_id, p_doc_kind, v_num, coalesce(p_invoice_date, current_date), p_due_date, v_pt_id, v_pt_name,
            v_currency_id, v_rate, coalesce(p_total_amount, 0), 'draft', v_staff, p_credit_for_invoice_id)
    returning id into v_inv_id;
  end if;

  -- ── 줄 ──
  if p_doc_kind = 'invoice' then
    -- ⭐ 미청구 수량(검토 이견 4) · 단위 칸은 수량이 주문 수량과 같을 때만
    for r in select * from public.po_uninvoiced_lines(p_po_id) loop
      v_n := v_n + 1; v_msgs := '{}'; v_qty := null; v_full := false;
      if r.remaining_qty > 0 then
        v_verdict := 'ok'; v_qty := r.remaining_qty; v_full := (r.remaining_qty = r.qty_ea); v_ok := v_ok + 1;
        if r.invoiced_qty > 0 then v_msgs := array_append(v_msgs, format('%s already invoiced on other invoice(s) — remaining %s', r.invoiced_qty, r.remaining_qty)); end if;
        if not v_full then v_msgs := array_append(v_msgs, 'partial — entered unit reset to EA'); end if;
        if p_commit then
          v_ins := v_ins + 1;
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable,
                                              entered_unit_product_id, entered_qty, entered_pack_factor)
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true,
                  case when v_full then r.entered_unit_product_id end,
                  case when v_full then r.entered_qty end,
                  case when v_full then r.entered_pack_factor end);
        end if;
      else
        v_verdict := 'fully_invoiced';
        v_msgs := array_append(v_msgs, case when r.remaining_qty < 0 then 'over-invoiced — check earlier invoices' else 'nothing left to invoice' end);
      end if;
      v_lines := v_lines || jsonb_build_object(
        'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', v_po.po_number, 'po_line_no', r.line_no, 'sku', r.sku,
        'qty_ordered', r.qty_ea, 'invoiced_qty', r.invoiced_qty, 'remaining_qty', r.remaining_qty,
        'qty_ea', v_qty, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
        'line_no', case when v_verdict = 'ok' then (case when p_commit then v_ins else v_ok end) end,
        'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
    end loop;
    if v_ok = 0 then v_warn := array_append(v_warn, 'no_uninvoiced_lines'); end if;

    -- ⭐ 할인 복사 제안(검토 이견 5) — po_discount 그대로 · supplier_discount_id 를 남긴다(from supplier / added here 가 인보이스에서도 보인다)
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
    -- ⭐⭐ 크레딧 자동 채우기 — 차이 = 인보이스 goods 줄 수량 − 그 po_line 의 입고 합 · 차이 > 0 만 · 단가는 인보이스 줄 · 단위 EA
    for r in
      select il.po_line_id, il.qty_ea as invoice_qty, il.unit_price, pl.line_no as po_line_no, x.po_number, pr.sku,
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
          insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable)
          values (v_inv_id, v_ins, 'goods', r.po_line_id, v_qty, r.unit_price, true);
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
  -- (크레딧 · credit_for 없음 → 줄 비움 · 할인 복사 없음)

  return jsonb_build_object(
    'committed', p_commit, 'id', v_inv_id, 'doc_kind', p_doc_kind, 'invoice_number', v_num, 'header_source', v_source,
    'supplier_id', v_supplier_id, 'supplier_name', v_sup_name, 'currency_id', v_currency_id, 'currency_code', v_cur_code,
    'payment_term_name', v_pt_name, 'total_amount', coalesce(p_total_amount, 0),
    'line_count', case when p_commit then v_ins else v_ok end, 'lines', v_lines,
    'discounts', v_discs, 'discounts_copied', v_disc_n,
    'warnings', to_jsonb(v_warn));
exception
  when unique_violation then
    raise exception '% % already exists for % — nothing was saved', v_kind_label, v_num, coalesce(v_sup_name, 'this supplier');
end;
$$;
comment on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean) is '⑤ 인보이스·크레딧 초안 만들기(미리 보기 = 같은 모양 · p_commit). 머리는 credit_for 인보이스 → PO → 공급처 순으로 따라온다(그날 값 · 인보이스는 PO 필수). ⭐ 인보이스 줄 = PO 라인의 미청구 수량(주문 − 이미 청구) · 단가 po_line · 단위 칸은 전량일 때만 · po_discount 복사 제안(p_copy_discounts). ⭐ 크레딧(credit_for) 줄 = 인보이스 goods 수량 − 입고 합 > 0 인 것 · 차이 없으면 빈 초안 + no_qty_difference · 할인 복사 없음. total_amount 안 주면 0 + 경고(대조값을 계산값으로 채우지 않는다). 번호 중복은 미리 보기 경고 · commit 거부. created_by 서버 유도. 정본 po-module §11-e·g · §13-f · 2026-09-16';

-- ═══ po_invoice_add_po_lines — 다른 PO 의 미청구 라인을 통째로 더한다 (인보이스 · draft 만) ═══
-- POST /rest/v1/rpc/po_invoice_add_po_lines  {"p_invoice_id":"<uuid>","p_po_id":"<uuid>","p_commit":true}
-- → { committed, invoice_id, invoice_number, po_id, po_number, lines[](po_invoice_create 인보이스 모양), inserted, warnings[] }   warnings: currency_mismatch · no_uninvoiced_lines
create function public.po_invoice_add_po_lines(
  p_invoice_id uuid,
  p_po_id      uuid,
  p_commit     boolean default true
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_inv    public.po_invoice%rowtype;
  v_po     public.po%rowtype;
  v_next   int;
  v_n      int := 0;  v_ok int := 0;  v_ins int := 0;
  v_warn   text[] := '{}';
  v_lines  jsonb := '[]'::jsonb;
  v_msgs   text[];
  v_verdict text;  v_qty numeric;  v_full boolean;
  r        record;
begin
  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  if v_inv.doc_kind <> 'invoice' then
    raise exception 'Credit note % — PO lines are added to invoices only (add credit lines one by one) — nothing was saved', v_inv.invoice_number;
  end if;
  if v_inv.status <> 'draft' then
    raise exception 'Invoice % is % — lines can be changed only while draft (confirmed = accepted into the books) — nothing was saved', v_inv.invoice_number, v_inv.status;
  end if;
  select * into v_po from public.po where id = p_po_id;
  if not found then raise exception 'PO % not found — nothing was saved', p_po_id; end if;
  if v_po.supplier_id <> v_inv.supplier_id then
    raise exception 'PO % belongs to a different supplier than invoice % — nothing was saved', v_po.po_number, v_inv.invoice_number;
  end if;
  if v_po.currency_id <> v_inv.currency_id then v_warn := array_append(v_warn, 'currency_mismatch'); end if;

  select coalesce(max(line_no), 0) into v_next from public.po_invoice_line where po_invoice_id = p_invoice_id;

  for r in select * from public.po_uninvoiced_lines(p_po_id) loop
    v_n := v_n + 1; v_msgs := '{}'; v_qty := null; v_full := false;
    if r.remaining_qty > 0 then
      v_verdict := 'ok'; v_qty := r.remaining_qty; v_full := (r.remaining_qty = r.qty_ea); v_ok := v_ok + 1;
      if r.invoiced_qty > 0 then v_msgs := array_append(v_msgs, format('%s already invoiced — remaining %s', r.invoiced_qty, r.remaining_qty)); end if;
      if not v_full then v_msgs := array_append(v_msgs, 'partial — entered unit reset to EA'); end if;
      v_next := v_next + 1;
      if p_commit then
        v_ins := v_ins + 1;
        insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, qty_ea, unit_price, is_payable,
                                            entered_unit_product_id, entered_qty, entered_pack_factor)
        values (p_invoice_id, v_next, 'goods', r.po_line_id, v_qty, r.unit_price, true,
                case when v_full then r.entered_unit_product_id end, case when v_full then r.entered_qty end, case when v_full then r.entered_pack_factor end);
      end if;
    else
      v_verdict := 'fully_invoiced';
      v_msgs := array_append(v_msgs, case when r.remaining_qty < 0 then 'over-invoiced — check earlier invoices' else 'nothing left to invoice' end);
    end if;
    v_lines := v_lines || jsonb_build_object(
      'n', v_n, 'verdict', v_verdict, 'po_line_id', r.po_line_id, 'po_number', v_po.po_number, 'po_line_no', r.line_no, 'sku', r.sku,
      'qty_ordered', r.qty_ea, 'invoiced_qty', r.invoiced_qty, 'remaining_qty', r.remaining_qty,
      'qty_ea', v_qty, 'unit_price', case when v_verdict = 'ok' then r.unit_price end,
      'line_no', case when v_verdict = 'ok' then v_next end,
      'inserted', (p_commit and v_verdict = 'ok'), 'message', array_to_string(v_msgs, ' · '));
  end loop;
  if v_ok = 0 then v_warn := array_append(v_warn, 'no_uninvoiced_lines'); end if;

  return jsonb_build_object('committed', p_commit, 'invoice_id', p_invoice_id, 'invoice_number', v_inv.invoice_number,
                            'po_id', p_po_id, 'po_number', v_po.po_number, 'lines', v_lines, 'inserted', v_ins, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_invoice_add_po_lines(uuid, uuid, boolean) is '⑤ 인보이스에 다른 PO 의 미청구 라인을 통째로 더한다(인보이스 하나가 발주 둘에 걸친다 · §11-g). 인보이스만 · draft 만 · 같은 공급처만(다르면 거부) · 통화 다르면 경고. 규칙은 po_invoice_create 와 같다(po_uninvoiced_lines). 이미 다 청구된 PO 면 no_uninvoiced_lines. 2026-09-16';

-- ═══ po_invoice_line_add — 줄 하나 (다른 PO 의 라인 하나 · 운임 charge 줄 · 안 시킨 것 other) ═══
-- POST /rest/v1/rpc/po_invoice_line_add  {"p_invoice_id":"<uuid>","p_line":{"line_kind":"charge","description":"Freight","qty_ea":1,"unit_price":187,"is_payable":false}}
--   p_line 키: line_kind(기본 goods) · po_line_id(goods 필수) · description(goods 아니면 필수) · qty_ea(goods 필수 · 아니면 기본 1) · unit_price(기본 0) · is_payable(기본 true) ·
--              entered_unit_product_id · entered_qty · entered_pack_factor · note
-- → { line:{…행…}, line_count, invoice_number, warnings[] }   warnings: line_already_on_invoice · currency_mismatch
create function public.po_invoice_line_add(
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
  v_next   int;   v_cnt int;   v_dup int;
  v_row    public.po_invoice_line%rowtype;
  v_warn   text[] := '{}';
begin
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
  else
    if v_desc is null then raise exception 'A % line needs a description — nothing was saved', v_kind; end if;
    v_qty := coalesce(v_qty, 1);
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.po_invoice_line where po_invoice_id = p_invoice_id;

  insert into public.po_invoice_line (po_invoice_id, line_no, line_kind, po_line_id, description, qty_ea, unit_price, is_payable,
                                      entered_unit_product_id, entered_qty, entered_pack_factor, note)
  values (p_invoice_id, v_next, v_kind, case when v_kind = 'goods' then v_pol end, v_desc, v_qty, v_price, v_pay,
          nullif(p_line->>'entered_unit_product_id', '')::uuid, nullif(p_line->>'entered_qty', '')::numeric,
          nullif(p_line->>'entered_pack_factor', '')::numeric, nullif(p_line->>'note', ''))
  returning * into v_row;
  -- CHECK(target · unit_price >= 0 · entered_unit_ck)는 표가 지킨다 — 어기면 표의 예외가 그대로 올라간다

  select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = p_invoice_id;
  return jsonb_build_object('line', to_jsonb(v_row), 'line_count', v_cnt, 'invoice_number', v_inv.invoice_number, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_invoice_line_add(uuid, jsonb) is '⑤ 인보이스·크레딧 줄 하나 더하기 — draft 만. goods 는 po_line_id 필수 + 같은 공급처(다르면 거부 · 통화 다르면 경고) · charge/other 는 description 필수 · qty 기본 1. line_no = max+1. 같은 po_line 이 이미 있으면 경고만. 2026-09-16';

-- ═══ po_invoice_line_update — 줄 부분 갱신 (patch 에 있는 키만 · draft 만) ═══
-- POST /rest/v1/rpc/po_invoice_line_update  {"p_line_id":"<uuid>","p_patch":{"qty_ea":90,"is_payable":false}}
--   patch 키: line_kind · po_line_id · description · qty_ea · unit_price · is_payable · entered_unit_product_id · entered_qty · entered_pack_factor · note
-- → { line:{…행…}, invoice_number, status, warnings[] }
create function public.po_invoice_line_update(
  p_line_id uuid,
  p_patch   jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_row   public.po_invoice_line%rowtype;
  v_inv   public.po_invoice%rowtype;
  v_pl    public.po_line%rowtype;
  v_po    public.po%rowtype;
  v_kind  text;  v_pol uuid;  v_desc text;  v_qty numeric;
  v_warn  text[] := '{}';
begin
  select * into v_row from public.po_invoice_line where id = p_line_id;
  if not found then raise exception 'Invoice line % not found — nothing was saved', p_line_id; end if;
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
  if v_kind not in ('goods', 'charge', 'other') then raise exception 'line_kind must be goods, charge or other — nothing was saved'; end if;
  if v_kind = 'goods' and v_pol is null then raise exception 'A goods line must point at a PO line (po_line_id) — nothing was saved'; end if;
  if v_kind <> 'goods' and v_desc is null then raise exception 'A % line needs a description — nothing was saved', v_kind; end if;
  if v_qty is null then raise exception 'qty_ea is required — nothing was saved'; end if;
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
    note                    = case when p_patch ? 'note'                    then nullif(p_patch->>'note', '')                           else note end
  where id = p_line_id
  returning * into v_row;

  return jsonb_build_object('line', to_jsonb(v_row), 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_invoice_line_update(uuid, jsonb) is '⑤ 인보이스·크레딧 줄 부분 갱신(patch 키만) — draft 만(확정 = 장부 · 되돌리려면 po_invoice_confirm(…,false)). line_kind 를 바꾸면 po_line_id/description 정합을 같은 patch 안에서 본다(goods 아니면 라인 참조를 비운다). is_payable 은 여기서 켜고 끈다(운임 빼고 내는 실무 §13). 2026-09-16';

-- ═══ po_invoice_line_delete ═══
-- POST /rest/v1/rpc/po_invoice_line_delete  {"p_line_id":"<uuid>"}  → { deleted, invoice_id, invoice_number, line_no, line_count }
create function public.po_invoice_line_delete(p_line_id uuid) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_row public.po_invoice_line%rowtype;
  v_inv public.po_invoice%rowtype;
  v_cnt int;
begin
  select * into v_row from public.po_invoice_line where id = p_line_id;
  if not found then raise exception 'Invoice line % not found — nothing was deleted', p_line_id; end if;
  select * into v_inv from public.po_invoice where id = v_row.po_invoice_id;
  if v_inv.status <> 'draft' then
    raise exception '% % is % — lines can be deleted only while draft — nothing was deleted',
      case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
  end if;
  delete from public.po_invoice_line where id = p_line_id;
  select count(*) into v_cnt from public.po_invoice_line where po_invoice_id = v_inv.id;
  return jsonb_build_object('deleted', true, 'invoice_id', v_inv.id, 'invoice_number', v_inv.invoice_number, 'line_no', v_row.line_no, 'line_count', v_cnt);
end;
$$;
comment on function public.po_invoice_line_delete(uuid) is '⑤ 인보이스·크레딧 줄 삭제 — draft 만. 빈 line_no 는 둔다(unique 만 지킨다). 2026-09-16';

-- ═══ po_invoice_confirm — 확정 · 되돌리기 ═══
-- POST /rest/v1/rpc/po_invoice_confirm  {"p_invoice_id":"<uuid>","p_confirm":true}
-- → { id, doc_kind, invoice_number, status, confirmed_at, money:{ total_amount, computed_total, diff, payable_net, alloc_total, credit_total, unpaid, remaining }, warnings[] }
--   확정 warnings: total_amount_zero · total_differs_from_lines · 되돌리기 warnings: has_attached_credits
create function public.po_invoice_confirm(
  p_invoice_id uuid,
  p_confirm    boolean default true
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff uuid;
  v_inv   public.po_invoice%rowtype;
  v_for   public.po_invoice%rowtype;
  v_m     record;
  v_cnt   int;
  v_cred  int;
  v_warn  text[] := '{}';
  v_label text;
begin
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  select * into v_inv from public.po_invoice where id = p_invoice_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_invoice_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
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
    update public.po_invoice set status = 'confirmed', confirmed_by = v_staff, confirmed_at = now() where id = p_invoice_id returning * into v_inv;
  else
    if v_inv.status <> 'confirmed' then raise exception '% % is % — only a confirmed document can be reopened — nothing was saved', v_label, v_inv.invoice_number, v_inv.status; end if;
    if v_m.alloc_total > 0 then
      raise exception '% % has payments applied (%) — cannot reopen while paid/used; remove the payment allocation first — nothing was saved', v_label, v_inv.invoice_number, v_m.alloc_total;
    end if;
    select count(*) into v_cred from public.po_invoice c where c.credit_for_invoice_id = p_invoice_id and c.status <> 'cancelled';
    if v_cred > 0 then v_warn := array_append(v_warn, 'has_attached_credits'); end if;
    update public.po_invoice set status = 'draft', confirmed_by = null, confirmed_at = null where id = p_invoice_id returning * into v_inv;
  end if;

  return jsonb_build_object(
    'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status, 'confirmed_at', v_inv.confirmed_at,
    'money', jsonb_build_object('total_amount', v_m.total_amount, 'computed_total', v_m.computed_total, 'diff', v_m.diff, 'payable_net', v_m.payable_net,
                                'alloc_total', v_m.alloc_total, 'credit_total', v_m.credit_total, 'unpaid', v_m.unpaid, 'remaining', v_m.remaining),
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_invoice_confirm(uuid, boolean) is '⑤ 인보이스·크레딧 확정(p_confirm=true) — ⭐ 확정 = 「공급처 문서를 우리 장부에 받아들였다」(대조됐고 미지급이 생기고 할인이 원가로 내려간다 · 발주 Confirm 과 다르다). 거부: 줄 0개 · 크레딧이 크레딧/다른 공급처를 가리킴 · 이미 확정 · 취소됨. 경고만: total_amount 0 · diff ≠ 0(정본은 찍힌 값). confirmed_by 서버 유도. 되돌리기(false): 결제 충당(alloc_total)이 있으면 거부 · 붙은 크레딧이 있으면 경고 · draft 로. 돈은 po_invoice_money. 2026-09-16';

-- ═══ po_discount_save — 할인 줄 더하기·고치기 (세 자리 · p_target 으로 가른다) ═══
-- POST /rest/v1/rpc/po_discount_save
--   더하기  {"p_target":"invoice","p_target_id":"<po_invoice.id>","p_patch":{"name":"Special","percent":10}}                    ← seq 안 주면 max+1
--   고치기  {"p_target":"po","p_target_id":"<po.id>","p_id":"<po_discount.id>","p_patch":{"percent":15}}
--   순서    {"…","p_id":"<id>","p_patch":{"seq":5}}   (겹치면 읽을 문장으로 거부 — 띄어 매긴 빈 번호를 쓴다)
--   p_target: 'supplier'(supplier_discount · target_id = supplier.id · patch 에 is_active 도) · 'po'(po_discount) · 'invoice'(po_invoice_discount · 크레딧도 같은 표)
--   patch 키: name · percent · seq · supplier_discount_id(po·invoice 만 · 같은 공급처의 줄이어야 한다) · note · is_active(supplier 만)
-- → { target, target_id, row:{…행…}, created(boolean) }
create function public.po_discount_save(
  p_target    text,
  p_target_id uuid,
  p_patch     jsonb,
  p_id        uuid default null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_po        public.po%rowtype;
  v_inv       public.po_invoice%rowtype;
  v_sup_id    uuid;                 -- 문서의 공급처(supplier_discount_id 검증용)
  v_name      text;  v_pct numeric;  v_seq int;  v_src uuid;  v_note text;  v_active boolean;
  v_created   boolean := (p_id is null);
  v_row       jsonb;
  v_owner     uuid;
begin
  if p_target not in ('supplier', 'po', 'invoice') then raise exception 'p_target must be supplier, po or invoice — nothing was saved'; end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then raise exception 'p_patch must be a JSON object — nothing was saved'; end if;

  -- ── 대상 문서와 상태 (다른 행 · 저장 전에 본다) ──
  if p_target = 'supplier' then
    select id into v_sup_id from public.supplier where id = p_target_id;
    if v_sup_id is null then raise exception 'Supplier % not found — nothing was saved', p_target_id; end if;
  elsif p_target = 'po' then
    select * into v_po from public.po where id = p_target_id;
    if not found then raise exception 'PO % not found — nothing was saved', p_target_id; end if;
    if v_po.status in ('closed', 'cancelled') then
      raise exception 'PO % is % — discounts cannot be changed — nothing was saved', v_po.po_number, v_po.status;
    end if;
    v_sup_id := v_po.supplier_id;
  else
    select * into v_inv from public.po_invoice where id = p_target_id;
    if not found then raise exception 'Invoice % not found — nothing was saved', p_target_id; end if;
    if v_inv.status <> 'draft' then
      raise exception '% % is % — discounts can be changed only while draft (confirmed = accepted into the books; reopen first) — nothing was saved',
        case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
    end if;
    v_sup_id := v_inv.supplier_id;
  end if;

  -- ── 값 ──
  v_name   := nullif(p_patch->>'name', '');
  v_pct    := nullif(p_patch->>'percent', '')::numeric;
  v_seq    := nullif(p_patch->>'seq', '')::int;
  v_src    := nullif(p_patch->>'supplier_discount_id', '')::uuid;
  v_note   := nullif(p_patch->>'note', '');
  v_active := nullif(p_patch->>'is_active', '')::boolean;
  if v_pct is not null and (v_pct < 0 or v_pct > 100) then raise exception 'percent must be between 0 and 100 — nothing was saved'; end if;
  if v_seq is not null and v_seq < 1 then raise exception 'seq must be 1 or more — nothing was saved'; end if;
  if p_target <> 'supplier' and (p_patch ? 'supplier_discount_id') and v_src is not null then
    -- 제안의 원천은 같은 공급처의 줄이어야 한다(다른 공급처 줄을 가리키면 Source 열이 거짓말을 한다)
    if not exists (select 1 from public.supplier_discount d where d.id = v_src and d.supplier_id = v_sup_id) then
      raise exception 'supplier_discount % is not a discount line of this supplier — nothing was saved', v_src;
    end if;
  end if;

  if v_created then
    if v_name is null or v_pct is null then raise exception 'name and percent are required for a new discount line — nothing was saved'; end if;
  end if;

  -- ── 표마다 (정적 SQL 세 갈래 · seq 안 주면 max+1) ──
  if p_target = 'supplier' then
    if v_created then
      if v_seq is null then select coalesce(max(seq), 0) + 1 into v_seq from public.supplier_discount where supplier_id = p_target_id; end if;
      insert into public.supplier_discount (supplier_id, name, percent, seq, note, is_active, source)
      values (p_target_id, v_name, v_pct, v_seq, v_note, coalesce(v_active, true), 'manual')
      returning to_jsonb(supplier_discount.*) into v_row;
    else
      select supplier_id into v_owner from public.supplier_discount where id = p_id;
      if v_owner is null or v_owner <> p_target_id then raise exception 'Discount line % is not on this supplier — nothing was saved', p_id; end if;
      update public.supplier_discount set
        name      = coalesce(v_name, name),
        percent   = coalesce(v_pct, percent),
        seq       = coalesce(v_seq, seq),
        note      = case when p_patch ? 'note' then v_note else note end,
        is_active = coalesce(v_active, is_active)
      where id = p_id returning to_jsonb(supplier_discount.*) into v_row;
    end if;
  elsif p_target = 'po' then
    if v_created then
      if v_seq is null then select coalesce(max(seq), 0) + 1 into v_seq from public.po_discount where po_id = p_target_id; end if;
      insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id, note)
      values (p_target_id, v_seq, v_name, v_pct, v_src, v_note)
      returning to_jsonb(po_discount.*) into v_row;
    else
      select po_id into v_owner from public.po_discount where id = p_id;
      if v_owner is null or v_owner <> p_target_id then raise exception 'Discount line % is not on this PO — nothing was saved', p_id; end if;
      update public.po_discount set
        name                 = coalesce(v_name, name),
        percent              = coalesce(v_pct, percent),
        seq                  = coalesce(v_seq, seq),
        supplier_discount_id = case when p_patch ? 'supplier_discount_id' then v_src else supplier_discount_id end,
        note                 = case when p_patch ? 'note' then v_note else note end
      where id = p_id returning to_jsonb(po_discount.*) into v_row;
    end if;
  else
    if v_created then
      if v_seq is null then select coalesce(max(seq), 0) + 1 into v_seq from public.po_invoice_discount where po_invoice_id = p_target_id; end if;
      insert into public.po_invoice_discount (po_invoice_id, seq, name, percent, supplier_discount_id, note)
      values (p_target_id, v_seq, v_name, v_pct, v_src, v_note)
      returning to_jsonb(po_invoice_discount.*) into v_row;
    else
      select po_invoice_id into v_owner from public.po_invoice_discount where id = p_id;
      if v_owner is null or v_owner <> p_target_id then raise exception 'Discount line % is not on this invoice — nothing was saved', p_id; end if;
      update public.po_invoice_discount set
        name                 = coalesce(v_name, name),
        percent              = coalesce(v_pct, percent),
        seq                  = coalesce(v_seq, seq),
        supplier_discount_id = case when p_patch ? 'supplier_discount_id' then v_src else supplier_discount_id end,
        note                 = case when p_patch ? 'note' then v_note else note end
      where id = p_id returning to_jsonb(po_invoice_discount.*) into v_row;
    end if;
  end if;

  return jsonb_build_object('target', p_target, 'target_id', p_target_id, 'row', v_row, 'created', v_created);
exception
  when unique_violation then
    raise exception 'seq % is already used on this % — pick a free number (gaps are fine; order is what matters) — nothing was saved', v_seq, p_target;
end;
$$;
comment on function public.po_discount_save(text, uuid, jsonb, uuid) is '⑤ 할인 줄 더하기·고치기 — 세 자리를 p_target(supplier · po · invoice)으로 가른다(§11-e 두 층 · 마스터는 제안이지 잠금이 아니다). seq 안 주면 max+1(곱해지는 차례 · unique · 겹치면 읽을 문장) · 빈 seq 는 둔다. 저장 전에 보는 것: closed·cancelled 발주 거부 · draft 아닌 인보이스 거부 · supplier_discount_id 는 같은 공급처의 줄. supplier 는 source=manual. 2026-09-16';

-- ═══ po_discount_delete ═══
-- POST /rest/v1/rpc/po_discount_delete  {"p_target":"po","p_id":"<uuid>"}  → { deleted, target, id, seq, target_id }
create function public.po_discount_delete(
  p_target text,
  p_id     uuid
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_po    public.po%rowtype;
  v_inv   public.po_invoice%rowtype;
  v_seq   int;  v_owner uuid;  v_refs int;
begin
  if p_target not in ('supplier', 'po', 'invoice') then raise exception 'p_target must be supplier, po or invoice — nothing was deleted'; end if;

  if p_target = 'supplier' then
    select supplier_id, seq into v_owner, v_seq from public.supplier_discount where id = p_id;
    if v_owner is null then raise exception 'Supplier discount % not found — nothing was deleted', p_id; end if;
    select (select count(*) from public.po_discount where supplier_discount_id = p_id)
         + (select count(*) from public.po_invoice_discount where supplier_discount_id = p_id) into v_refs;
    if v_refs > 0 then
      -- FK(no action)가 어차피 막는다 — 마스터는 지우지 않고 내린다(§3-f 관례)
      raise exception 'Supplier discount is referenced by % document discount line(s) — deactivate it instead (is_active=false) — nothing was deleted', v_refs;
    end if;
    delete from public.supplier_discount where id = p_id;
  elsif p_target = 'po' then
    select po_id, seq into v_owner, v_seq from public.po_discount where id = p_id;
    if v_owner is null then raise exception 'PO discount % not found — nothing was deleted', p_id; end if;
    select * into v_po from public.po where id = v_owner;
    if v_po.status in ('closed', 'cancelled') then raise exception 'PO % is % — discounts cannot be deleted — nothing was deleted', v_po.po_number, v_po.status; end if;
    delete from public.po_discount where id = p_id;
  else
    select po_invoice_id, seq into v_owner, v_seq from public.po_invoice_discount where id = p_id;
    if v_owner is null then raise exception 'Invoice discount % not found — nothing was deleted', p_id; end if;
    select * into v_inv from public.po_invoice where id = v_owner;
    if v_inv.status <> 'draft' then
      raise exception '% % is % — discounts can be deleted only while draft — nothing was deleted',
        case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end, v_inv.invoice_number, v_inv.status;
    end if;
    delete from public.po_invoice_discount where id = p_id;
  end if;

  return jsonb_build_object('deleted', true, 'target', p_target, 'id', p_id, 'seq', v_seq, 'target_id', v_owner);
end;
$$;
comment on function public.po_discount_delete(text, uuid) is '⑤ 할인 줄 삭제 — supplier 줄은 문서가 가리키면 거부(「비활성으로 내려라」) · po 는 closed·cancelled 거부 · invoice 는 draft 만. 빈 seq 는 둔다. 2026-09-16';

-- ═══ 권한 — 함수 EXECUTE 는 PUBLIC 기본 부여 · 명시 회수 ═══
revoke all on function public.po_uninvoiced_lines(uuid)                                                          from public, anon;
revoke all on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean) from public, anon;
revoke all on function public.po_invoice_add_po_lines(uuid, uuid, boolean)                                        from public, anon;
revoke all on function public.po_invoice_line_add(uuid, jsonb)                                                   from public, anon;
revoke all on function public.po_invoice_line_update(uuid, jsonb)                                                from public, anon;
revoke all on function public.po_invoice_line_delete(uuid)                                                       from public, anon;
revoke all on function public.po_invoice_confirm(uuid, boolean)                                                  from public, anon;
revoke all on function public.po_discount_save(text, uuid, jsonb, uuid)                                          from public, anon;
revoke all on function public.po_discount_delete(text, uuid)                                                     from public, anon;
grant execute on function public.po_uninvoiced_lines(uuid)                                                          to authenticated;
grant execute on function public.po_invoice_create(text, text, uuid, uuid, uuid, date, date, numeric, boolean, boolean) to authenticated;
grant execute on function public.po_invoice_add_po_lines(uuid, uuid, boolean)                                        to authenticated;
grant execute on function public.po_invoice_line_add(uuid, jsonb)                                                   to authenticated;
grant execute on function public.po_invoice_line_update(uuid, jsonb)                                                to authenticated;
grant execute on function public.po_invoice_line_delete(uuid)                                                       to authenticated;
grant execute on function public.po_invoice_confirm(uuid, boolean)                                                  to authenticated;
grant execute on function public.po_discount_save(text, uuid, jsonb, uuid)                                          to authenticated;
grant execute on function public.po_discount_delete(text, uuid)                                                     to authenticated;

-- ═══ po_invoice_list — 인보이스·크레딧 목록 뷰 (PostgREST 로 표처럼 · 인보이스 화면의 목록 · PO 없는 조정 크레딧이 보이는 유일한 자리) ═══
-- 돈은 po_invoice_money 그대로(식 없음) · po_numbers 는 줄이 가리키는 발주 번호 모음(공백 구분 · .ilike 검색) · 크레딧은 credit_for_number 도.
create view public.po_invoice_list
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
  i.total_amount,                                    -- 찍힌 값 · 정본
  round(m.factor, 6)      as discount_factor,        -- 표시용 6자리
  m.computed_total, m.diff, m.payable_net,
  m.alloc_total,                                     -- 인보이스: paid · 크레딧: used
  m.credit_total, m.unpaid, m.remaining,
  m.line_count,
  coalesce(pos.po_count, 0) as po_count,
  pos.po_numbers,                                    -- 검색용 · 조정 크레딧은 null
  i.credit_for_invoice_id, f.invoice_number as credit_for_number,
  i.confirmed_at, i.cancelled_at, i.note, i.created_at, i.updated_at
from public.po_invoice i
join public.po_invoice_money m on m.id = i.id
join public.supplier s on s.id = i.supplier_id
join public.ref_currency cur on cur.id = i.currency_id
left join public.po_invoice f on f.id = i.credit_for_invoice_id
left join pos on pos.po_invoice_id = i.id;

comment on view public.po_invoice_list is '⑤ 인보이스·크레딧 목록 — PostgREST 로 표처럼(.range()+count:exact · .ilike · .order · §10-j 3-a). 돈은 po_invoice_money(식 없음 · unpaid 음수면 받을 돈 · 크레딧은 remaining) · po_numbers = 줄이 가리키는 발주 번호 모음(검색 · PO 없는 조정 크레딧은 null — 여기가 그 문서가 보이는 유일한 자리) · credit_for_number. security_invoker. 검색 인덱스는 안 듣는다(짐작). 정본 po-module §11-g · §13-f · 2026-09-16';

revoke all on public.po_invoice_list from anon;
grant select on public.po_invoice_list to authenticated;

-- ═══ po_invoice_detail(p_invoice_id) — 인보이스 화면의 상세 (한 장을 깊게 · po_detail 은 무변) ═══
-- POST /rest/v1/rpc/po_invoice_detail  {"p_invoice_id":"<uuid>"}  → jsonb 또는 null
--   header · money · lines[] · discounts[] · po_shares[] · credits[](인보이스에 붙은 크레딧) · payments[] · warnings[]
create function public.po_invoice_detail(p_invoice_id uuid) returns jsonb
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
         round(il.qty_ea * il.unit_price, 2) as amount,
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
cred as (                                     -- 이 인보이스에 붙은 크레딧(취소 포함 · status 로 보인다)
  select c.id, c.invoice_number, c.invoice_date, c.status, c.total_amount, cm.payable_net as credit_net, cm.alloc_total as used
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
      'supplier_id', i.supplier_id, 'supplier_name', s.name,
      'currency_id', i.currency_id, 'currency_code', cur.code, 'exchange_rate', i.exchange_rate,
      'payment_term_id', i.payment_term_id, 'payment_term_name', coalesce(i.payment_term_name, pt.name),
      'total_amount', i.total_amount,
      'credit_for_invoice_id', i.credit_for_invoice_id, 'credit_for_number', f.invoice_number, 'credit_for_status', f.status,
      'created_by_name', cb.name, 'confirmed_by_name', fb.name,
      'confirmed_at', i.confirmed_at, 'cancelled_at', i.cancelled_at, 'note', i.note, 'created_at', i.created_at, 'updated_at', i.updated_at)
    from i
    join public.supplier s on s.id = i.supplier_id
    join public.ref_currency cur on cur.id = i.currency_id
    left join public.ref_payment_term pt on pt.id = i.payment_term_id
    left join public.po_invoice f on f.id = i.credit_for_invoice_id
    left join public.ims_staff cb on cb.id = i.created_by
    left join public.ims_staff fb on fb.id = i.confirmed_by
  ),
  'money', (
    select jsonb_build_object(
      'line_count', m.line_count, 'goods_sum', m.goods_sum, 'other_sum', m.other_sum, 'goods_payable', m.goods_payable, 'other_payable', m.other_payable,
      'discount_factor', round(m.factor, 6),                              -- 표시용 · 금액은 뷰가 원래 factor 로 계산했다
      'computed_total', m.computed_total, 'diff', m.diff,
      'payable_net', m.payable_net,                                       -- 인보이스: 갚을 돈 · 크레딧: 뺄 돈(credit_net)
      'alloc_total', m.alloc_total,                                       -- 인보이스: paid · 크레딧: used
      'credit_total', m.credit_total, 'unpaid', m.unpaid, 'remaining', m.remaining)
    from m
  ),
  'lines', coalesce((
    select jsonb_agg(jsonb_build_object(
      'id', id, 'line_no', line_no, 'line_kind', line_kind, 'po_line_id', po_line_id, 'po_id', po_id, 'po_number', po_number, 'po_line_no', po_line_no,
      'sku', sku, 'product_name', product_name, 'description', description,
      'qty_ea', qty_ea, 'entered_unit_sku', entered_unit_sku, 'entered_unit_product_id', entered_unit_product_id, 'entered_qty', entered_qty, 'entered_pack_factor', entered_pack_factor,
      'unit_price', unit_price, 'amount', amount, 'is_payable', is_payable, 'note', note,
      'po_qty_ea', po_qty_ea, 'po_unit_price', po_unit_price,             -- 발주와 대조(단가 다르면 화면이 표시)
      'received_qty', received_qty, 'other_invoiced_qty', other_invoiced_qty,
      'qty_diff', case when line_kind = 'goods' then qty_ea - received_qty end)   -- ⭐ 「크레딧을 만드시겠습니까」의 근거 · > 0 이면 덜 받았다
      order by line_no)
    from lines), '[]'::jsonb),
  'discounts', coalesce((
    select jsonb_agg(jsonb_build_object('id', d.id, 'seq', d.seq, 'name', d.name, 'percent', d.percent, 'supplier_discount_id', d.supplier_discount_id, 'note', d.note) order by d.seq)
    from public.po_invoice_discount d where d.po_invoice_id = p_invoice_id), '[]'::jsonb),
  'po_shares', coalesce((
    select jsonb_agg(jsonb_build_object('po_id', po_id, 'po_number', po_number, 'po_status', po_status, 'line_count', line_count, 'qty_ea', qty_ea, 'amount', amount) order by po_number)
    from shares), '[]'::jsonb),
  'credits', coalesce((
    select jsonb_agg(jsonb_build_object('id', id, 'credit_number', invoice_number, 'credit_date', invoice_date, 'status', status, 'total_amount', total_amount, 'credit_net', credit_net, 'used', used)
      order by invoice_date, invoice_number)
    from cred), '[]'::jsonb),
  'payments', coalesce((
    select jsonb_agg(jsonb_build_object('alloc_id', alloc_id, 'payment_id', payment_id, 'paid_on', paid_on, 'reference', reference, 'alloc_amount', alloc_amount,
                                        'payment_amount', payment_amount, 'discount_taken', discount_taken, 'currency_code', currency_code,
                                        'account_code', account_code, 'account_name', account_name, 'paid_by_name', paid_by_name)
      order by paid_on, reference)
    from pay), '[]'::jsonb),
  'warnings', (
    select coalesce(jsonb_agg(w), '[]'::jsonb) from (
      select unnest(array_remove(array[
        case when i.doc_kind = 'credit' and i.credit_for_invoice_id is not null and m.alloc_total > 0 then 'attached_and_used' end,
        case when f.doc_kind = 'credit' then 'credit_for_is_credit' end,
        case when f.supplier_id is not null and f.supplier_id <> i.supplier_id then 'credit_for_other_supplier' end,
        case when i.total_amount = 0 then 'total_amount_zero' end,
        case when m.diff <> 0 then 'total_differs_from_lines' end,
        case when m.line_count = 0 then 'no_lines' end
      ], null)) as w
      from i cross join m left join public.po_invoice f on f.id = i.credit_for_invoice_id) t
  )
) end;
$$;
comment on function public.po_invoice_detail(uuid) is '⑤ 인보이스·크레딧 상세 — 한 장을 깊게(인보이스 화면 · po_detail 은 발주의 시선이라 줄을 안 담는다 · 검토 이견 14). header(편집용 id 포함) · money(po_invoice_money 그대로 · 식 없음) · lines[](발주 대조: po_qty_ea · po_unit_price · received_qty · other_invoiced_qty · qty_diff — 크레딧 제안의 근거) · discounts[] · po_shares[] · credits[](붙은 크레딧) · payments[] · warnings[](po_detail credits[].warnings 셋 + total_amount_zero · total_differs_from_lines · no_lines). 없는 id → null. 2026-09-16';

revoke all on function public.po_invoice_detail(uuid) from public, anon;
grant execute on function public.po_invoice_detail(uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 화면(asung-ims · 인보이스 전용 화면 · 다음 차수 · 대화 Claude)이 부르는 모양 — supabase-js v2
-- ─────────────────────────────────────────────────────────────
--   목록      sb.from("po_invoice_list").select("*",{count:"exact"}).or(`invoice_number.ilike.%q%,supplier_name.ilike.%q%,po_numbers.ilike.%q%`).order("invoice_date",{ascending:false}).range(a,b)
--             필터: .eq("supplier_id") → .gte/.lte("invoice_date") → .eq("doc_kind") → .eq("status") → 미지급 .gt("unpaid",0) · 쓸 수 있는 크레딧 .gt("remaining",0)
--   상세      sb.rpc("po_invoice_detail",{p_invoice_id:id})       // null 이면 없다 · lines[].qty_diff > 0 인 줄이 있으면 「크레딧을 만드시겠습니까」
--   PO 에서 만들기(미리 보기 → 넣기)
--             sb.rpc("po_invoice_create",{p_doc_kind:"invoice",p_invoice_number:n,p_po_id:poId,p_invoice_date:d,p_total_amount:t,p_commit:false})   // lines[] · discounts[] · warnings[]
--             같은 인자에 p_commit:true → data.id 로 인보이스 화면을 연다
--   크레딧 자동 채우기   sb.rpc("po_invoice_create",{p_doc_kind:"credit",p_invoice_number:n,p_credit_for_invoice_id:invId,p_commit:false})   // verdict ok 줄 = 차이 · 없으면 warnings no_qty_difference
--   조정 크레딧          sb.rpc("po_invoice_create",{p_doc_kind:"credit",p_invoice_number:n,p_supplier_id:sid,p_commit:true})               // 줄 비움 · 목록(po_invoice_list)에서만 보인다
--   다른 PO 통째로       sb.rpc("po_invoice_add_po_lines",{p_invoice_id:id,p_po_id:otherPoId,p_commit:false→true})
--   줄 하나              sb.rpc("po_invoice_line_add",{p_invoice_id:id,p_line:{line_kind:"goods",po_line_id:plId,qty_ea:12,unit_price:2.41}})
--                        sb.rpc("po_invoice_line_add",{p_invoice_id:id,p_line:{line_kind:"charge",description:"Freight",qty_ea:1,unit_price:187,is_payable:false}})
--   줄 수정·삭제         sb.rpc("po_invoice_line_update",{p_line_id:lid,p_patch:{qty_ea:90}}) · sb.rpc("po_invoice_line_delete",{p_line_id:lid})
--   확정·되돌리기        sb.rpc("po_invoice_confirm",{p_invoice_id:id}) · sb.rpc("po_invoice_confirm",{p_invoice_id:id,p_confirm:false})   // warnings 는 막은 것이 아니다 · 보여 준다
--   할인 줄(세 자리 같은 모양)
--             더하기  sb.rpc("po_discount_save",{p_target:"invoice",p_target_id:id,p_patch:{name:"Special",percent:10}})
--             고치기  sb.rpc("po_discount_save",{p_target:"po",p_target_id:poId,p_id:did,p_patch:{percent:15}})
--             지우기  sb.rpc("po_discount_delete",{p_target:"supplier",p_id:did})   // 문서가 가리키면 거부 → is_active=false 는 PostgREST update 로
--             Source 열: row.supplier_discount_id ? "from supplier" : "added here"(po.html 738 그대로)
--   머리 편집(PostgREST · 기존 길)  sb.from("po_invoice").update({invoice_number, invoice_date, due_date, total_amount, exchange_rate, note}).eq("id",id).select()
--             ⚠️ total_amount 는 찍힌 값 — 화면이 계산값을 채워 넣지 마라(대조값이 사라진다). 취소 update({status:"cancelled",cancelled_at}) 도 이 길.
--   ⚠️ 예외는 error.message(HTTP 400)로 온다 — 그 문장을 그대로 띄운다(§10-j 3-i). warnings 는 오류가 아니다.
--   ⚠️ 미청구 보기  sb.rpc("po_uninvoiced_lines",{p_po_id:poId})   // 발주 상세 「Make invoice」 버튼의 활성 조건(remaining_qty > 0 인 줄이 있나)
--
-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 테스트 DB · 예상값은 검토 Claude 계산 · SQL 스냅숏 2026-09-16 저녁 기준)
--   ⚠️ commit·confirm 은 auth.uid() 를 보므로 psql 에서는 request.jwt.claims 를 심어 돌린다(§10-h · 181719 검증 주석) — 미리 보기(p_commit=false)·detail·list 는 그냥 된다
-- ─────────────────────────────────────────────────────────────
-- ⓪ 적용 뒤
--   select proname from pg_proc where proname like 'po_invoice%' or proname like 'po_discount%' or proname = 'po_uninvoiced_lines' order by 1;   → 10개
--   select invoice_number, doc_kind, status, total_amount, computed_total, diff, unpaid, remaining, po_numbers, credit_for_number from po_invoice_list order by 1;
--   예상  AMP-778812 invoice confirmed 2197.54 · computed 2197.54 · diff 0.00 · unpaid −30.90 · remaining null · po_numbers 'PO-02001a' · credit_for null
--         CN-AMP-778812-1 credit confirmed(또는 draft) 30.90 · computed 30.90 · diff 0 · unpaid null · remaining null(붙은 크레딧) · po_numbers 'PO-02001a' · credit_for 'AMP-778812'
--   select * from po_uninvoiced_lines((select id from po where po_number='PO-02007'));   → 13행 · invoiced_qty 0 · remaining = qty_ea(12) · received 0
--   select * from po_uninvoiced_lines((select id from po where po_number='PO-02001a'));  → 3행 · remaining 0 (200/600/120 다 청구됨)
-- ① ⓓ① PO-02007 에서 인보이스 — 미리 보기
--   select jsonb_pretty(po_invoice_create('invoice', 'SON-TEST-1', (select id from po where po_number='PO-02007'), null, null, current_date, null, null, true, false));
--   예상  committed false · id null · header_source 'po' · supplier Strength of Nature · currency USD · payment_term_name 'Net 30' · total_amount 0 ·
--         line_count 13 · lines[] 13줄 전부 verdict ok · qty_ea 12 · unit_price = po_line 단가 · line_no 1~13 · inserted false ·
--         discounts [] · discounts_copied 0(PO-02007 에 po_discount 가 없으면) · warnings ['total_amount_missing']
--   넣기(로그인 또는 jwt 심고): 같은 인자에 p_commit true → id 있음 · inserted true
--   select invoice_number, status, total_amount, computed_total, diff, payable_net, unpaid, line_count from po_invoice_list where invoice_number='SON-TEST-1';
--   예상  draft · 0 · 586.92 · −586.92 · 586.92 · 586.92 · 13     ⭐ diff 가 크게 음수 = 「총액을 아직 안 넣었다」가 보인다(검토 이견 6)
--   select po_number, invoice_phase, invoice_count, invoiced_qty, payment_phase, unpaid_total from po_list where po_number='PO-02007';   → done · 1 · 156 · none · 586.92
--   select * from po_uninvoiced_lines((select id from po where po_number='PO-02007'));   → remaining 전부 0
--   select (po_invoice_add_po_lines((select id from po_invoice where invoice_number='SON-TEST-1'), (select id from po where po_number='PO-02007'), false)) -> 'warnings';   → ["no_uninvoiced_lines"]
--   같은 번호로 다시 미리 보기 → warnings 에 invoice_number_exists · commit → 예외 「Invoice SON-TEST-1 already exists for Strength of Nature …」
-- ② ⓓ② 할인 줄 — 확정 문서는 막힌다 · 새 문서에서 10%
--   select po_discount_save('invoice', (select id from po_invoice where invoice_number='AMP-778812'), '{"name":"Special","percent":10}');
--   예상  예외 「Invoice AMP-778812 is confirmed — discounts can be changed only while draft …」   ⭐ 확정 = 장부(검토 이견 12)
--   select po_invoice_confirm((select id from po_invoice where invoice_number='AMP-778812'), false);
--   예상  예외 「… has payments applied (2010.54) — cannot reopen …」
--   select po_discount_save('invoice', (select id from po_invoice where invoice_number='SON-TEST-1'), '{"name":"Special","percent":10}');
--   예상  created true · row.seq 1 · percent 10 · supplier_discount_id null(added here)
--   select discount_factor, payable_net, computed_total, diff, unpaid from po_invoice_list where invoice_number='SON-TEST-1';
--   예상  0.900000 · 528.23 · 528.23 · −528.23 · 528.23        (586.92 × 0.9 = 528.228 → 528.23)
--   update po_invoice set total_amount = 528.23 where invoice_number='SON-TEST-1';   → diff 0.00
--   select po_discount_save('invoice', (select id from po_invoice where invoice_number='SON-TEST-1'), '{"percent":12}', <위 row.id>);   → percent 12 · seq 그대로 1
--   select po_discount_save('invoice', (select id ...), '{"name":"Dup","percent":1,"seq":1}');   → 예외 「seq 1 is already used on this invoice — pick a free number …」
--   select po_discount_delete('invoice', <row.id>);   → deleted true · seq 1
--   select po_discount_save('po', (select id from po where po_number='PO-02001a'), '{"name":"X","percent":1}');   → 예외 「PO PO-02001a is closed — discounts cannot be changed …」
--   select po_discount_save('supplier', (select supplier_id from po where po_number='PO-02007'), '{"name":"Trade","percent":5}');   → created · seq 1 · source manual (확인 뒤 po_discount_delete('supplier', id) → deleted · 참조 없음)
-- ③ ⓓ③ 크레딧 자동 채우기 — AMP-778812 는 200/200 · 600/600 · 120/120
--   select jsonb_pretty(po_invoice_create('credit', 'CN-AMP-778812-2', null, (select id from po_invoice where invoice_number='AMP-778812'), null, null, null, null, true, false));
--   예상  header_source 'invoice' · Ampro · lines[] 3줄 전부 verdict no_difference · diff_qty 0 · qty_ea null · inserted false · line_count 0 · warnings ['no_qty_difference']
--         (charge 운임 187 줄은 goods 가 아니라 lines[] 에 안 나온다)
--   commit true → 빈 크레딧 draft 하나 · warnings ['no_qty_difference'] · po_invoice_list 에 CN-AMP-778812-2 credit draft · line_count 0 · remaining null(붙은 크레딧) · credit_for AMP-778812
--   po_detail(PO-02001a) -> 'credits' → 2행(기존 + 새것 · lines_for_this_po 0 · credit_net 0) · po_list PO-02001a credit_count 2 · unpaid_total 그대로 −30.90(credit_net 0)
--   select po_invoice_confirm(<새 크레딧 id>);   → 예외 「Credit note CN-AMP-778812-2 has no lines — nothing to accept …」
--   확인 뒤 지운다: delete from po_invoice where invoice_number='CN-AMP-778812-2';
-- ④ 확정 — SON-TEST-1 (total 528.23 로 맞춘 뒤 · 할인 줄 다시 넣은 상태라면 payable 528.23)
--   select jsonb_pretty(po_invoice_confirm((select id from po_invoice where invoice_number='SON-TEST-1')));
--   예상  status confirmed · money.diff 0.00 · warnings []   (total 을 0 으로 두고 확정하면 warnings ['total_amount_zero','total_differs_from_lines'] — 막지 않는다)
--   그 뒤 po_invoice_line_update(줄, '{"qty_ea":11}') → 예외 「Invoice SON-TEST-1 is confirmed — lines can be changed only while draft …」
--   po_invoice_confirm(id, false) → draft · warnings [] (결제 없음) → 다시 고칠 수 있다
-- ⑤ 상세 — select jsonb_pretty(po_invoice_detail((select id from po_invoice where invoice_number='AMP-778812')));
--   예상  header credit_for null · money.unpaid −30.90 · credit_total 30.90 · lines[] 4줄(goods 3 · qty_diff 0 · other_invoiced_qty 0 · charge 1 · qty_diff null) ·
--         discounts[] 2(Trade 17 · Damage 1) · po_shares [{PO-02001a · 3 · 920 · 2446.80}] · credits[] 1(CN-AMP-778812-1 · credit_net 30.90) · payments[] 1(WIRE-20260916-01 · 2010.54) · warnings []
-- ⑥ 줄 하나 — charge 줄 더하기 (SON-TEST-1 · draft 상태에서)
--   select po_invoice_line_add((select id from po_invoice where invoice_number='SON-TEST-1'), '{"line_kind":"charge","description":"Freight","unit_price":25,"is_payable":false}');
--   예상  line.line_no 14 · qty_ea 1 · is_payable false · line_count 14 → po_invoice_list computed_total = 528.23 + 25 = 553.23 · payable_net 528.23(운임 빠짐)
--   goods 줄에 po_line_id 없이 → 예외 「A goods line must point at a PO line …」 · charge 줄에 description 없이 → 예외 「A charge line needs a description …」
--   다른 공급처 PO 의 라인(PO-02001a 의 줄)을 goods 로 → 예외 「PO PO-02001a belongs to a different supplier …」
