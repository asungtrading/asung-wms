-- ─────────────────────────────────────────────────────────────
-- ⑤ 발주 · 인보이스 · 크레딧을 무효로 만드는 길 — 취소(po_doc_cancel) · 삭제(po_doc_delete) (테스트 DB Asung-IMS · 2026-09-17)
--   po · po_invoice 에 cancelled_by       누가 취소했나(confirmed_by 와 같은 결) — 지금은 화면이 PostgREST 로 status 만 바꿔 아무도 안 남았다
--   po_doc_cancel(p_target, p_id, p_cancel)  취소 · 되돌리기(p_cancel=false · po_invoice_confirm 의 p_confirm 선례) — 다른 행을 봐서 막고 · 붙어 있는 것을 **이름으로** 말한다
--   po_doc_delete(p_target, p_id)            삭제 — 한 번도 확정되지 않은 것만 · 크레딧은 못 지운다 · 딸려 가는 줄은 CASCADE · 밖에서 가리키는 것은 FK 가 막지만 **사람이 읽을 문장으로** 먼저 막는다
--
-- 정본: docs/design/po-module.md §5(거래 표 규약 「DELETE 막지 않는다 — 초안은 지울 수 있어야 한다 · 확정 뒤는 취소로 물러난다」) · §11-b · §11-c(취소는 사람이 한다 · 크레딧 번호) · §11-g(확정 = 장부) · §13 · §13-f ⬜⬜ 「무효로 만들기」 · §13-h(채번은 행을 읽는다)
-- 앞 정의: 20260916210000(po_invoice_create · po_invoice_list · po_invoice_detail · po_list · po_credit_next_number — ⚠️ 이 파일은 그것들을 **바꾸지 않는다**) · 20260916200000(po_invoice_confirm — ⭐ Reopen 의 결제 검사가 선례) ·
--          20260916181719(po_line_delete — 「막는 것은 DB 가 막는다 · FK 가 막지만 읽을 수 있는 말로 먼저」 선례)
-- 지시서: ~/asung/prompts/po-void-delete.md · 검토 이견 1~14(2026-09-17) → po-void-delete-fix.md 로 **이견 5 뒤집음(크레딧 삭제 전면 금지) · 이견 2 좁힘(발주도 confirmed_at 이 있으면 안 지운다)** · 나머지 열둘 그대로
-- 표 변경: cancelled_by 두 칸(이견 12) — 나머지는 새 함수 둘(create · or replace 불필요)
-- ❌ 이번 범위 밖 — 비용 문서 · 결제의 취소·삭제(다음 차수 · p_target 에 'charge' · 'payment' 를 더하면 같은 두 함수가 받는다)
--
-- ⭐⭐ 지운다 / 취소한다 — 경계 (이견 1·2·3 · fix 1·2)
--   지운다   **한 번도 확정되지 않은 것.** 흔적을 남길 이유가 없다 — 시험 문서가 쌓이는 자리(Caleb 2026-09-17 「테스트 오더를 계속 만들 텐데 하나씩 지우거나 취소를 해야 한다」)
--   취소한다  **한 번이라도 확정된 것.** cancelled 로 남긴다 — 계산(국면·미지급·건수)에서는 빠지고(190000) · 채번에서는 센다(210000)
--   ⭐ 규칙은 하나다 — **한 번이라도 확정된 문서(confirmed_at not null)는 지워지지 않는다.** 판정 축은 status 가 아니라 confirmed_at 칸이다(취소는 confirmed_at 을 안 건드리므로 cancelled 여도 확정 이력이 남아 있다).
--     인보이스·크레딧  확정 = 「공급처 문서를 우리 장부에 받아들였다」(§11-g). 장부에 들어간 것은 취소가 끝이다
--     발주             확정 = 「보낼 수량과 라인이 정해졌다」 — 회계 장부는 아니지만 **공급사에 나간 문서**다(§11-c 「공급처가 레퍼런스로 쓸 수는 있어도」).
--                     ⚠️ 확정된 발주에서 밖을 가리키는 것이 하나도 없다 = 물건도 인보이스도 아직 안 왔다 = §11-c 「안 온다고 판명되면 그 문서를 취소한다」— **취소의 전형**이다. 가장 기록으로 남겨야 할 문서라 지우지 않는다(Caleb 판정 · fix 2)
--                     「번호가 시퀀스라 다시 쓰이지 않는다」는 재사용 위험이 없다는 뜻이지 이력을 지워도 된다는 뜻이 아니다
--     cancelled 지우기  확정된 적 없는 cancelled(draft → cancelled)만 — 발주·인보이스 같다(이견 3). 확정된 적 있는 cancelled 는 「was confirmed on … — cancel it instead」로 거부
--   ⭐⭐ 크레딧은 **삭제 전면 금지** — status·confirmed_at 무관 · 남는 길은 취소뿐(fix 1 · 아래)
--   ⚠️ 취소는 draft 도 받는다(이견 4) — 초안은 지우는 것이 보통이지만 「받았지만 받아들이지 않은 공급처 인보이스」를 기록으로 남기려는 실물이 있을 수 있다. 거부하면 그 길이 없다. warnings cancelled_from_draft 로 알린다
--   📌 시험 데이터 청소 — 확정을 거친 시험 문서(PO-02005 · 02008 이 그럴 수 있다 · 짐작)는 화면에서 안 지워진다. 결함이 아니다 — 테스트 DB 청소는 Caleb 이 SQL 로 직접 한다. 그 편의를 위해 운영에서 확정 문서가 지워지는 문을 열지 않는다(Caleb 판정)
--
-- ⭐⭐ 크레딧은 지우지 않는다 — 왜 (fix 1 · Caleb 판정 2026-09-17)
--   po_credit_next_number(210000)는 시퀀스가 아니라 **po_invoice 의 invoice_number 행을 읽어**(doc_kind='credit' · 접두어 CN-<po> / CN-<연도>-) 「최대 꼬리 + 1」을 낸다. 행이 없어지면 그 번호가 축의 마지막이었을 때 다음 크레딧이 같은 번호를 받는다.
--   취소된 것까지 세기로 한 근거가 **「공급처에 이미 알려 준 번호가 다른 문서를 가리키면 안 된다」**(§13-h)였다. 「알려 준다」가 IMS 의 confirm 앞인지 뒤인지는 정본 어디에도 없다 — 확인되지 않은 것 위에 채번 규칙을 얹지 않는다.
--   초안만 지우게 해도 확정 → Reopen(결제만 없으면 열린 정상 경로 · confirmed_at 이 지워진다) → 삭제, 클릭 둘로 공급처에 나간 번호가 되풀이된다. 뒷문이 있으면 근거가 무너진다.
--   저울 — 한쪽은 지저분함(시험 크레딧이 cancelled 로 남는다 · 테스트 DB 뿐이고 Caleb 이 SQL 로 치운다 · 운영에서는 남는 쪽이 옳다), 다른 쪽은 복구 불가. ⇒ **크레딧 행은 po_doc_delete 가 무조건 거부한다.** 거부 문장은 「초안이 아니다」가 아니라 「크레딧은 지우지 않는다 — 취소하라」로(사람이 무엇을 해야 하는지 안다)
--   📌 사람이 준 번호(CN-AMP-778812-1 · 공급처 번호)도 같이 막는다 — 종류로 하나의 규칙. 예외를 두면 화면도 설명도 갈린다
--
-- ⭐ 되돌리기(p_cancel=false · 이견 6) — cancelled → **취소 직전 상태로**(confirmed_at 이 있으면 confirmed · 없으면 draft) · 취소는 confirmed_at/by 를 건드리지 않는다(po_list order_phase 가 그 값을 본다 · 190000)
--   이유 ① 실수로 취소한 확정 인보이스를 되살릴 길이 없으면 같은 번호를 다시 못 넣는다(유니크 (supplier, doc_kind, number)에 cancelled 행이 걸린다) — 취소가 곧 삭제가 된다(Caleb 확인)
--        ② draft 로 내리지 않는다 — cancelled 문서는 줄·할인을 못 고치므로(줄 RPC 는 draft 만) 취소 전 상태가 그대로 남아 있다. 확정 검사(줄 0 · credit_for)는 그때 통과한 그대로다. Reopen(→ draft)과는 뜻이 다르다
--   크레딧을 되살릴 때 credit_for 인보이스가 cancelled 면 warnings credit_for_cancelled(막지 않는다 — 읽기 쪽 warnings 관례 §5)
--
-- ⭐ 무엇을 막나 (이견 7·8·9·10)
--   인보이스·크레딧 취소   결제 충당(alloc_total > 0) ⇒ 거부 — ⭐ po_invoice_confirm Reopen 과 **같은 문장·같은 선**에 결제 참조번호·금액을 이름으로(「WIRE-20260916-01 2010.54」) · 크레딧이면 「이미 쓴 크레딧」이 이 검사에 든다(alloc 이 크레딧을 가리킨다 = 썼다 · §11-h)
--                          ⭐ 인보이스에 취소 안 된 크레딧이 붙어 있다(credit_for) ⇒ **거부**(이견 7) — 붙은 크레딧의 돈은 「그 인보이스의 미지급을 줄이는」 것으로만 계산된다(po_invoice_money · remaining 은 credit_for 가 있으면 null).
--                             인보이스가 취소되면 그 크레딧은 어느 합에도 안 들어 30.90 이 허공에 뜬다. 함께 취소하면 사람이 넣은 공급처 문서를 시스템이 조용히 없앤다(§11-c 「취소는 사람이 한다」와 반대) ⇒ 먼저 치우게 한다. 📌 실물 AMP-778812 는 결제가 먼저 막는다
--                          ⚠️ Reopen 은 붙은 크레딧을 **경고**만 한다(has_attached_credits) — 문서가 살아 있으니 크레딧의 뜻이 남는다. 취소는 문서가 죽으니 다르다
--                          크레딧 취소 · credit_for 인보이스에 결제가 있다 ⇒ **경고**(credit_for_invoice_has_payments · 이견 8) + 그 인보이스의 unpaid 전후를 준다 — 크레딧이 없어지면 미지급이 그만큼 되살아나는 것은 사실이고 결함이 아니다(Reopen 도 자기 alloc 만 본다 · 같은 선)
--   발주 취소              closed ⇒ 거부(입고 종료) · 입고 줄이 하나라도 있다 ⇒ 거부(입고는 사건 · po_line_delete 와 같은 선) — 받은 발주를 취소하면 사건과 문서가 어긋난다(이견 9)
--                          인보이스·크레딧 줄이 가리킨다 · 비용이 배분돼 있다 · 크레딧이 번호를 이 발주에서 냈다 · 갈라진 자식이 있다 ⇒ **경고만**(has_invoices · has_charges · has_numbered_credits · has_split_children) + attached{} 에 이름을 준다(이견 10)
--                             — 「안 온다고 판명되면 그 문서를 취소한다」(§11-c)가 실무다. 공급처가 이미 청구했어도 안 오면 취소하고 크레딧을 받는다. 순서를 강요하면 실물을 못 넣는다
--   발주 삭제              ⭐ confirmed_at 검사가 **맨 앞** — 확정된 적 있으면 확정 시각을 넣어 거부. 그 뒤 밖에서 가리키는 다섯 = 전부 FK no action 이라 DB 가 어차피 막는다(3-ⓑ 조사) — RPC 는 **이름을 붙여 읽을 문장으로** 바꾼다:
--                          입고 줄(po_receipt_line → po_line) · 인보이스·크레딧 줄(po_invoice_line.po_line_id) · 비용 배분(po_charge_alloc.po_id) · 자식(po.split_from_id) · 번호를 낸 크레딧(po_invoice.credit_po_id)
--                          딸려 가는 둘 = CASCADE(po_line · po_discount) — 문서의 것이라 위험한 자리가 아니다(§5 「문서 → 소유 줄에만」)
--   인보이스·크레딧 삭제   ⭐ 크레딧 ⇒ 무조건 거부(맨 앞) · 인보이스는 confirmed_at 있으면 거부. 그 뒤 밖에서 가리키는 둘 = FK no action — 결제 충당(po_payment_alloc.po_invoice_id) · 이 인보이스를 가리키는 크레딧(credit_for · **취소된 것도** — FK 는 상태를 안 본다) ⇒ 이름으로 거부
--                          딸려 가는 둘 = CASCADE(po_invoice_line · po_invoice_discount) — 지운 수를 결과에 준다
--   📌 세 거부 문장이 같은 모양이다 — 「<문서> <번호> was confirmed on <날짜> — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted」 · 크레딧은 「cannot be deleted — cancel it instead; …」
--
-- ⭐ RPC 둘 · 문서 종류는 인자(이견 11) — po_doc_cancel / po_doc_delete · p_target 'po' | 'invoice'(po_discount_save 선례 · 인보이스와 크레딧은 한 표라 doc_kind 는 행에서 읽는다)
--   취소와 삭제를 한 함수에 합치지 않는다 — 결과가 다르고(남는다/없어진다) 화면의 확인 문구도 다르다. 경계가 이 파일의 주제인데 인자 하나로 갈리면 흐려진다
--   PostgREST 로 안 되는 이유(§13) — 둘 다 **다른 행**(입고 줄 · 결제 · 크레딧 · 자식)을 저장 전에 봐야 한다. 지금 화면의 Cancel PO(PostgREST 한 칸)는 이 RPC 로 옮긴다 — 입고가 붙은 발주를 취소하는 길이 지금은 열려 있다
--
-- ⭐ 관례(181719 · 200000 그대로) — plpgsql · volatile · security invoker · set search_path · 예외는 「… — nothing was saved」(취소) / 「… — nothing was deleted」(삭제) · array_append(⚠️ text[] || 리터럴 금지 · 13-e ①) ·
--   취소한 사람은 auth.uid() → ims_staff.id 서버 유도(po_create 관례) · 삭제는 아무것도 안 남기므로 staff 를 안 본다(po_line_delete 선례 · RLS auth_all 이 로그인을 요구한다) · revoke public/anon + grant authenticated
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① cancelled_by — po · po_invoice (이견 12) ═══
-- confirmed_by 는 있는데 cancelled_by 가 없어 「누가 취소했나」가 안 남았다. 취소가 RPC 로 오는 이번에 함께 세운다. 되돌리면 비운다(cancelled_at 과 같이).
alter table public.po
  add column if not exists cancelled_by uuid references public.ims_staff (id) on delete no action;
alter table public.po_invoice
  add column if not exists cancelled_by uuid references public.ims_staff (id) on delete no action;

comment on column public.po.cancelled_by         is '취소한 사람 → ims_staff(id) · po_doc_cancel 이 auth.uid() 로 유도해 넣는다 · 되돌리면(p_cancel=false) cancelled_at 과 함께 비운다. 2026-09-17';
comment on column public.po_invoice.cancelled_by is '취소한 사람 → ims_staff(id) · po_doc_cancel 이 auth.uid() 로 유도해 넣는다 · 되돌리면 cancelled_at 과 함께 비운다. 인보이스·크레딧 공용. 2026-09-17';

-- ═══ ② po_doc_cancel(p_target, p_id, p_cancel) — 취소 · 되돌리기 ═══
-- POST /rest/v1/rpc/po_doc_cancel
--   발주 취소     {"p_target":"po","p_id":"<po.id>"}                              → { target:'po', id, po_number, status:'cancelled', cancelled_at, confirmed_at, restored:false, attached:{invoices, charges, numbered_credits, split_children}, warnings[] }
--   발주 되돌리기 {"p_target":"po","p_id":"<po.id>","p_cancel":false}             → status 'confirmed'(confirmed_at 있으면) | 'draft' · restored:true
--   인보이스·크레딧 취소 {"p_target":"invoice","p_id":"<po_invoice.id>"}          → { target:'invoice', id, doc_kind, invoice_number, status, cancelled_at, confirmed_at, restored, credit_for:{invoice_id, invoice_number, unpaid_before, unpaid_after}|null, warnings[] }
--   warnings: has_invoices · has_charges · has_numbered_credits · has_split_children(발주) · cancelled_from_draft · credit_for_invoice_has_payments · credit_for_cancelled(되돌리기)
create function public.po_doc_cancel(
  p_target text,                          -- 'po' | 'invoice'(인보이스·크레딧 한 표 · doc_kind 는 행에서)
  p_id     uuid,
  p_cancel boolean default true           -- false = 되돌리기(cancelled → 취소 직전 상태)
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff        uuid;
  v_po           public.po%rowtype;
  v_inv          public.po_invoice%rowtype;
  v_for          public.po_invoice%rowtype;
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
begin
  if p_target not in ('po', 'invoice') then
    raise exception 'p_target must be po or invoice — nothing was saved';
  end if;
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;

  -- ══════════ 발주 ══════════
  if p_target = 'po' then
    select * into v_po from public.po where id = p_id;
    if not found then raise exception 'PO % not found — nothing was saved', p_id; end if;

    if p_cancel then
      if v_po.status = 'cancelled' then
        raise exception 'PO % is already cancelled — nothing was saved', v_po.po_number;
      end if;
      if v_po.status = 'closed' then
        raise exception 'PO % is closed (receiving finished) — a closed order cannot be cancelled — nothing was saved', v_po.po_number;
      end if;
      -- ⭐ 막는 것 하나 — 입고 줄(사건). po_line_delete 와 같은 선
      select count(*), coalesce(sum(rl.qty_ea), 0) into v_recv_n, v_recv_qty
      from public.po_receipt_line rl join public.po_line pl on pl.id = rl.po_line_id
      where pl.po_id = p_id;
      if v_recv_n > 0 then
        raise exception 'PO % has % receipt line(s) (% EA received) — a received order cannot be cancelled; receipts are events — nothing was saved',
          v_po.po_number, v_recv_n, v_recv_qty;
      end if;

      -- 경고만 — 붙어 있는 것을 이름으로(취소 안 된 것만)
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
    else
      if v_po.status <> 'cancelled' then
        raise exception 'PO % is % — only a cancelled order can be restored — nothing was saved', v_po.po_number, v_po.status;
      end if;
      -- 취소 직전 상태로 — 취소는 confirmed_at 을 안 건드렸다
      v_new_status := case when v_po.confirmed_at is not null then 'confirmed' else 'draft' end;
      update public.po set status = v_new_status, cancelled_at = null, cancelled_by = null
      where id = p_id returning * into v_po;
    end if;

    return jsonb_build_object(
      'target', 'po', 'id', v_po.id, 'po_number', v_po.po_number, 'status', v_po.status,
      'cancelled_at', v_po.cancelled_at, 'confirmed_at', v_po.confirmed_at, 'restored', not p_cancel,
      'attached', jsonb_build_object('invoices', v_inv_txt, 'charges', v_chg_txt, 'numbered_credits', v_cred_txt, 'split_children', v_split_txt),
      'warnings', to_jsonb(v_warn));
  end if;

  -- ══════════ 인보이스 · 크레딧 ══════════
  select * into v_inv from public.po_invoice where id = p_id;
  if not found then raise exception 'Invoice % not found — nothing was saved', p_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;
  select * into v_m from public.po_invoice_money where id = p_id;

  if p_cancel then
    if v_inv.status = 'cancelled' then
      raise exception '% % is already cancelled — nothing was saved', v_label, v_inv.invoice_number;
    end if;
    -- ⭐ Reopen(po_invoice_confirm p_confirm=false)과 같은 선 — 결제 충당이 붙었으면 거부 · 참조번호와 금액을 이름으로. 크레딧이면 「이미 썼다」가 여기 든다
    if v_m.alloc_total > 0 then
      select string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_txt
      from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id
      where pa.po_invoice_id = p_id;
      raise exception '% % has payments applied (%) — cannot cancel while paid/used; remove the payment allocation first — nothing was saved',
        v_label, v_inv.invoice_number, v_txt;
    end if;
    -- ⭐ 인보이스에 취소 안 된 크레딧이 붙어 있으면 거부(이견 7) — 크레딧의 돈이 허공에 뜬다 · 함께 취소하지 않는다(취소는 사람이 한다)
    select count(*), string_agg(c.invoice_number, ', ' order by c.invoice_number) into v_n, v_txt
    from public.po_invoice c where c.credit_for_invoice_id = p_id and c.status <> 'cancelled';
    if v_n > 0 then
      raise exception 'Invoice % has % credit note(s) attached (%) — cancel or detach those first — nothing was saved',
        v_inv.invoice_number, v_n, v_txt;
    end if;
    -- 크레딧이 인보이스에 붙어 있다 — 그 인보이스의 미지급이 되살아난다(사실 · 경고)
    if v_inv.doc_kind = 'credit' and v_inv.credit_for_invoice_id is not null then
      select * into v_m2 from public.po_invoice_money where id = v_inv.credit_for_invoice_id;
      v_unpaid_before := v_m2.unpaid;
      if v_m2.alloc_total > 0 then v_warn := array_append(v_warn, 'credit_for_invoice_has_payments'); end if;
    end if;
    if v_inv.status = 'draft' then v_warn := array_append(v_warn, 'cancelled_from_draft'); end if;   -- 초안은 지우는 것이 보통(이견 4) · 크레딧 초안은 지울 수 없으니 이 길로 온다

    update public.po_invoice set status = 'cancelled', cancelled_at = now(), cancelled_by = v_staff
    where id = p_id returning * into v_inv;

    if v_inv.doc_kind = 'credit' and v_inv.credit_for_invoice_id is not null then
      select unpaid into v_unpaid_after from public.po_invoice_money where id = v_inv.credit_for_invoice_id;
    end if;
  else
    if v_inv.status <> 'cancelled' then
      raise exception '% % is % — only a cancelled document can be restored — nothing was saved', v_label, v_inv.invoice_number, v_inv.status;
    end if;
    -- 취소 직전 상태로(이견 6) — cancelled 문서는 줄·할인을 못 고쳤으므로 확정 때의 검사가 그대로 유효하다
    v_new_status := case when v_inv.confirmed_at is not null then 'confirmed' else 'draft' end;
    if v_inv.credit_for_invoice_id is not null then
      select * into v_for from public.po_invoice where id = v_inv.credit_for_invoice_id;
      if v_for.status = 'cancelled' then v_warn := array_append(v_warn, 'credit_for_cancelled'); end if;
    end if;
    update public.po_invoice set status = v_new_status, cancelled_at = null, cancelled_by = null
    where id = p_id returning * into v_inv;
  end if;

  return jsonb_build_object(
    'target', 'invoice', 'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status', v_inv.status,
    'cancelled_at', v_inv.cancelled_at, 'confirmed_at', v_inv.confirmed_at, 'restored', not p_cancel,
    'credit_for', case when v_inv.credit_for_invoice_id is not null then
        jsonb_build_object('invoice_id', v_inv.credit_for_invoice_id,
                           'invoice_number', (select f.invoice_number from public.po_invoice f where f.id = v_inv.credit_for_invoice_id),
                           'unpaid_before', v_unpaid_before, 'unpaid_after', v_unpaid_after) end,
    'warnings', to_jsonb(v_warn));
end;
$$;
comment on function public.po_doc_cancel(text, uuid, boolean) is '⑤ 취소 · 되돌리기(p_cancel=false) — 발주(p_target po) · 인보이스·크레딧(p_target invoice). 발주: closed · 입고 줄 있음 ⇒ 거부 · 인보이스/비용/번호 낸 크레딧/자식은 경고 + attached{} 에 이름. 인보이스·크레딧: 결제 충당 ⇒ 거부(Reopen 과 같은 선 · 참조번호를 이름으로 · 크레딧이면 「썼다」) · 취소 안 된 크레딧이 붙은 인보이스 ⇒ 거부(먼저 치운다) · 크레딧이 붙은 인보이스에 결제가 있으면 경고 + unpaid 전후. 되돌리기는 취소 직전 상태로(confirmed_at 있으면 confirmed) — 취소는 confirmed_at 을 안 건드린다. cancelled_by 는 auth.uid() 유도. ⭐ 크레딧은 지울 수 없으므로 무효로 만드는 길은 이것 하나다. 정본 po-module §5 · §11-c · §11-g · §13-f · 2026-09-17';

revoke all on function public.po_doc_cancel(text, uuid, boolean) from public, anon;
grant execute on function public.po_doc_cancel(text, uuid, boolean) to authenticated;

-- ═══ ③ po_doc_delete(p_target, p_id) — 삭제 (한 번도 확정되지 않은 것만 · 크레딧은 못 지운다) ═══
-- POST /rest/v1/rpc/po_doc_delete
--   발주      {"p_target":"po","p_id":"<po.id>"}              → { deleted:true, target:'po', id, po_number, status_before, lines_deleted, discounts_deleted }
--   인보이스  {"p_target":"invoice","p_id":"<po_invoice.id>"} → { deleted:true, target:'invoice', id, doc_kind:'invoice', invoice_number, status_before, lines_deleted, discounts_deleted }
--   크레딧    같은 호출 → 예외 「Credit note … cannot be deleted — cancel it instead; …」(status·confirmed_at 무관)
create function public.po_doc_delete(
  p_target text,                          -- 'po' | 'invoice'
  p_id     uuid
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_po        public.po%rowtype;
  v_inv       public.po_invoice%rowtype;
  v_label     text;
  v_n         int;
  v_txt       text;
  v_lines     int;
  v_discs     int;
begin
  if p_target not in ('po', 'invoice') then
    raise exception 'p_target must be po or invoice — nothing was deleted';
  end if;

  -- ══════════ 발주 ══════════
  if p_target = 'po' then
    select * into v_po from public.po where id = p_id;
    if not found then raise exception 'PO % not found — nothing was deleted', p_id; end if;

    -- ⭐ 경계(fix 2) — 판정 축은 status 가 아니라 confirmed_at. 한 번이라도 확정된 발주는 공급사에 나간 문서다 — 취소로 남긴다(closed 는 confirmed_at 이 있고 입고 줄도 있어 아래 둘 중 하나가 막는다)
    if v_po.confirmed_at is not null then
      raise exception 'PO % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
        v_po.po_number, to_char(v_po.confirmed_at, 'YYYY-MM-DD');
    end if;

    -- ⭐ 밖에서 가리키는 다섯 — FK(no action)가 어차피 막지만 이름을 붙여 읽을 문장으로 먼저(po_line_delete 선례)
    select count(*) into v_n
    from public.po_receipt_line rl join public.po_line pl on pl.id = rl.po_line_id where pl.po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % receipt line(s) — a received order cannot be deleted; receipts are events — nothing was deleted', v_po.po_number, v_n;
    end if;

    select count(distinct i.id), string_agg(distinct i.invoice_number, ', ' order by i.invoice_number) into v_n, v_txt
    from public.po_invoice_line il join public.po_line pl on pl.id = il.po_line_id join public.po_invoice i on i.id = il.po_invoice_id
    where pl.po_id = p_id;                                      -- ⚠️ 취소된 문서도 — FK 는 상태를 안 본다
    if v_n > 0 then
      raise exception 'PO % is referenced by % invoice/credit document(s) (%) — remove those lines or delete those documents first — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(c.charge_number, ', ' order by c.charge_number) into v_n, v_txt
    from public.po_charge_alloc a join public.po_charge c on c.id = a.po_charge_id where a.po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % charge allocation(s) (%) — remove the allocation first — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(c.po_number, ', ' order by c.po_number) into v_n, v_txt
    from public.po c where c.split_from_id = p_id;
    if v_n > 0 then
      raise exception 'PO % has % split document(s) (%) pointing at it — the chain would break — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    select count(*), string_agg(k.invoice_number, ', ' order by k.invoice_number) into v_n, v_txt
    from public.po_invoice k where k.credit_po_id = p_id;
    if v_n > 0 then
      raise exception 'PO % numbered % credit note(s) (%) — their number rests on this PO — nothing was deleted', v_po.po_number, v_n, v_txt;
    end if;

    -- 딸려 가는 둘(CASCADE) — 수만 알린다
    select count(*) into v_lines from public.po_line     where po_id = p_id;
    select count(*) into v_discs from public.po_discount where po_id = p_id;
    delete from public.po where id = p_id;

    return jsonb_build_object(
      'deleted', true, 'target', 'po', 'id', v_po.id, 'po_number', v_po.po_number, 'status_before', v_po.status,
      'lines_deleted', v_lines, 'discounts_deleted', v_discs);
  end if;

  -- ══════════ 인보이스 · 크레딧 ══════════
  select * into v_inv from public.po_invoice where id = p_id;
  if not found then raise exception 'Invoice % not found — nothing was deleted', p_id; end if;
  v_label := case v_inv.doc_kind when 'invoice' then 'Invoice' else 'Credit note' end;

  -- ⭐⭐ 크레딧은 지우지 않는다(fix 1) — 맨 앞. 채번이 행을 읽으므로(po_credit_next_number · 최대 꼬리 + 1) 지우면 공급처에 알려 준 번호가 다른 문서에 다시 붙을 수 있다. 남는 길은 취소뿐
  if v_inv.doc_kind = 'credit' then
    raise exception 'Credit note % cannot be deleted — cancel it instead; its number must never be reused by another credit note — nothing was deleted', v_inv.invoice_number;
  end if;

  -- ⭐ 경계(이견 1) — 판정 축은 confirmed_at. 한 번이라도 확정된 인보이스는 장부에 들어갔다 — 취소가 끝
  if v_inv.confirmed_at is not null then
    raise exception '% % was confirmed on % — cancel it instead; only a document that was never confirmed can be deleted — nothing was deleted',
      v_label, v_inv.invoice_number, to_char(v_inv.confirmed_at, 'YYYY-MM-DD');
  end if;

  -- ⭐ 밖에서 가리키는 둘 — FK(no action) · 이름으로
  select count(*), string_agg(pm.reference || ' ' || pa.amount::text, ', ' order by pm.paid_on, pm.reference) into v_n, v_txt
  from public.po_payment_alloc pa join public.po_payment pm on pm.id = pa.po_payment_id where pa.po_invoice_id = p_id;
  if v_n > 0 then
    raise exception '% % has payments applied (%) — remove the payment allocation first — nothing was deleted', v_label, v_inv.invoice_number, v_txt;
  end if;

  select count(*), string_agg(c.invoice_number, ', ' order by c.invoice_number) into v_n, v_txt
  from public.po_invoice c where c.credit_for_invoice_id = p_id;   -- ⚠️ 취소된 크레딧도 — FK 는 상태를 안 본다
  if v_n > 0 then
    raise exception 'Invoice % has % credit note(s) pointing at it (%) — cancel and detach those first — nothing was deleted', v_inv.invoice_number, v_n, v_txt;
  end if;

  -- 딸려 가는 둘(CASCADE)
  select count(*) into v_lines from public.po_invoice_line     where po_invoice_id = p_id;
  select count(*) into v_discs from public.po_invoice_discount where po_invoice_id = p_id;
  delete from public.po_invoice where id = p_id;

  return jsonb_build_object(
    'deleted', true, 'target', 'invoice', 'id', v_inv.id, 'doc_kind', v_inv.doc_kind, 'invoice_number', v_inv.invoice_number, 'status_before', v_inv.status,
    'lines_deleted', v_lines, 'discounts_deleted', v_discs);
end;
$$;
comment on function public.po_doc_delete(text, uuid) is '⑤ 삭제 — 한 번도 확정되지 않은 것만(판정 축은 status 가 아니라 confirmed_at · 취소는 confirmed_at 을 안 건드린다). 발주(p_target po): confirmed_at 있으면 확정 시각을 넣어 거부(공급사에 나간 문서 · 취소로 남긴다) · 입고 줄/인보이스·크레딧 줄/비용 배분/자식(split_from)/번호 낸 크레딧(credit_po_id)이 하나라도 가리키면 이름을 붙여 거부(FK no action 이 어차피 막는다) · 라인·할인은 CASCADE. 인보이스(p_target invoice): ⭐ 크레딧은 무조건 거부(채번이 행을 읽어 번호가 되풀이된다 — 취소만) · confirmed_at 있으면 거부 · 결제 충당/이 인보이스를 가리키는 크레딧(취소된 것 포함)이 있으면 거부 · 줄·할인 CASCADE. 정본 po-module §5 · §11-c · §11-g · §13-f · §13-h · 2026-09-17';

revoke all on function public.po_doc_delete(text, uuid) from public, anon;
grant execute on function public.po_doc_delete(text, uuid) to authenticated;


-- ─────────────────────────────────────────────────────────────
-- 화면(asung-ims · 대화 Claude)이 부르는 모양 — supabase-js v2 · 예외는 error.message 로 온다(HTTP 400) · 화면은 그 문장을 그대로 띄운다
-- ─────────────────────────────────────────────────────────────
--   po.html
--     Cancel PO      const { data, error } = await sb.rpc("po_doc_cancel", { p_target: "po", p_id: h.id });                   // 지금의 PostgREST update({status:"cancelled"}) 를 이것으로 바꾼다
--                    data.warnings 에 has_invoices · has_charges · has_numbered_credits · has_split_children — data.attached.invoices 등에 번호 문자열('AMP-778812, …' · 없으면 null)
--     Restore        await sb.rpc("po_doc_cancel", { p_target: "po", p_id: h.id, p_cancel: false });                          // cancelled 문서에만 보이는 버튼 · data.status 가 confirmed 또는 draft
--     Delete PO      await sb.rpc("po_doc_delete", { p_target: "po", p_id: h.id });                                          // confirmed_at 이 null 인 문서(draft · 확정 안 거친 cancelled)에만 · 확인 문구에 라인 수를 쓰려면 po_detail 의 lines.length
--                    성공 뒤 목록으로 돌아간다(상세가 사라졌다) · data.lines_deleted · data.discounts_deleted
--   invoices.html
--     Cancel         await sb.rpc("po_doc_cancel", { p_target: "invoice", p_id: h.id });                                      // draft · confirmed 둘 다 · 크레딧이면 data.credit_for.unpaid_before/after 로 「AMP-778812 balance −30.90 → 0.00」
--     Restore        await sb.rpc("po_doc_cancel", { p_target: "invoice", p_id: h.id, p_cancel: false });                     // cancelled 에만 · 돌아가는 상태는 data.status
--     Delete         await sb.rpc("po_doc_delete", { p_target: "invoice", p_id: h.id });                                      // ⭐ 인보이스(doc_kind='invoice')이고 confirmed_at 이 null 일 때만 보인다 · 크레딧에는 Delete 버튼이 없다(취소만)
--   버튼 노출 규칙(뒷단이 어차피 막는다 · 화면은 안 될 것을 안 보이게만): Delete = confirmed_at null 이고 크레딧이 아닌 것 · Cancel = cancelled 아닌 것 · Restore = cancelled 만
--   ⚠️ 삭제 뒤 po_list · po_invoice_list 는 그 행이 없다 — 되읽기(imsSaved)가 아니라 목록으로 이동

-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 테스트 DB · 지시서 fix §5 · 예상값은 지시서 1-⓪ 실물(2026-09-17 SQL 확인)에서 — 검토 Claude 는 SQL 을 돌리지 않았다)
--   ⚠️ po_doc_cancel 은 auth.uid() 를 보므로 psql 에서는 request.jwt.claims 를 심는다(§10-h) — po_doc_delete 는 그냥 된다
--   ⚠️ 먼저: select po_number, status, confirmed_at, cancelled_at from po where po_number in ('PO-02005','PO-02008');   → ④ 의 갈림
-- ─────────────────────────────────────────────────────────────
-- ⓪ 적용 뒤
--   \d po          → cancelled_by uuid(FK ims_staff)      \d po_invoice → cancelled_by uuid
--   \df po_doc_*   → po_doc_cancel(text, uuid, boolean) · po_doc_delete(text, uuid)
-- ① CN-AMP-778812-1 삭제 시도(confirmed 크레딧 · 사람이 준 번호)
--   select po_doc_delete('invoice', (select id from po_invoice where invoice_number='CN-AMP-778812-1'));
--   예상  예외 「Credit note CN-AMP-778812-1 cannot be deleted — cancel it instead; its number must never be reused by another credit note — nothing was deleted」
--         (⭐ 취소해 놓고 다시 시도해도 같은 문장 — 크레딧은 상태 무관)
-- ② CN-AMP-778812-1 취소(jwt 심고 · alloc 0 · credit_for AMP-778812 는 결제 2,010.54)
--   select jsonb_pretty(po_doc_cancel('invoice', (select id from po_invoice where invoice_number='CN-AMP-778812-1')));
--   예상  status 'cancelled' · cancelled_at 지금 · confirmed_at 그대로 · restored false · cancelled_by = 내 ims_staff.id ·
--         credit_for { invoice_number 'AMP-778812', unpaid_before -30.90, unpaid_after 0.00 } · warnings ['credit_for_invoice_has_payments']
--         select unpaid, credit_total from po_invoice_money where id=(select id from po_invoice where invoice_number='AMP-778812');  → 0.00 · 0 (취소된 크레딧은 빠진다 · 190000)
--         select credit_count from po_list where po_number='PO-02001a';  → 0
--   되돌리기  select po_doc_cancel('invoice', <같은 id>, false) ->> 'status';  → 'confirmed' (confirmed_at 이 있었다) · unpaid 다시 −30.90
-- ③ PO-02009 삭제(draft · 라인 0 · 아무것도 안 붙음 · confirmed_at null — draft 이므로 · 짐작이 아니라 status 정의상)
--   select jsonb_pretty(po_doc_delete('po', (select id from po where po_number='PO-02009')));
--   예상  deleted true · po_number 'PO-02009' · status_before 'draft' · lines_deleted 0 · discounts_deleted 0
--         select count(*) from po where po_number='PO-02009';  → 0
-- ④ PO-02005 삭제(cancelled · 라인 13 · ⭐ [실측 Caleb 2026-09-17] PO-02005·02008 둘 다 status='cancelled' · confirmed_at is null — 확정을 거치지 않았다)
--   select jsonb_pretty(po_doc_delete('po', (select id from po where po_number='PO-02005')));
--   예상  deleted true · po_number 'PO-02005' · status_before 'cancelled' · lines_deleted 13 · discounts_deleted = po_discount 행수(0 짐작) — 밖에서 가리키는 것이 없다고 읽었다(짐작 · 있으면 다섯 거부 문장 중 하나)
--         PO-02008 도 같은 모양으로 지워진다
--   📌 거부를 보고 싶으면 PO-02001a(closed · confirmed_at 있음 · 짐작) → 「PO PO-02001a was confirmed on … — cancel it instead; …」(confirmed_at 검사가 입고 줄 검사보다 앞)
--      PO-02002(confirmed) → 같은 모양의 문장 · 취소해도 confirmed_at 이 남아 같은 문장
-- ⑤ PO-02002 인보이스 삭제(draft · confirmed_at null · 4줄 · 결제 없음 · 가리키는 크레딧 없음)
--   select jsonb_pretty(po_doc_delete('invoice', (select id from po_invoice where invoice_number='PO-02002' and doc_kind='invoice')));
--   예상  deleted true · doc_kind 'invoice' · status_before 'draft' · lines_deleted 4 · discounts_deleted = po_invoice_discount 행수(HoC 할인 복사 0 짐작) · ⭐ number_returned · next_credit_number 칸 없음(키 7개)
--         select po_number, invoice_count, invoice_phase, doc_numbers from po_list where po_number='PO-02002';  → invoice_count 0 · invoice_phase 'none' · doc_numbers 에 'PO-02002' 없음(비용 10039192310530 은 남음)
-- ⑥ AMP-778812 취소 시도(confirmed · 결제 2,010.54 · 크레딧 1장)
--   select po_doc_cancel('invoice', (select id from po_invoice where invoice_number='AMP-778812' and doc_kind='invoice'));
--   예상  예외 「Invoice AMP-778812 has payments applied (WIRE-20260916-01 2010.54) — cannot cancel while paid/used; remove the payment allocation first — nothing was saved」
--         (결제 검사가 크레딧 검사보다 앞 — Reopen 과 같은 순서. 결제를 떼면 그다음은 「Invoice AMP-778812 has 1 credit note(s) attached (CN-AMP-778812-1) — cancel or detach those first — nothing was saved」 · ② 로 크레딧을 취소해 두었으면 그 검사는 지나간다)
--         select status from po_invoice where invoice_number='AMP-778812';  → confirmed (무변)
--   삭제 시도  select po_doc_delete('invoice', <같은 id>);  → 「Invoice AMP-778812 was confirmed on 2026-09-16 — cancel it instead; …」(confirmed_at 검사가 결제·크레딧 검사보다 앞)
-- ⑦ 발주 취소·되돌리기(jwt 심고) — PO-02007(confirmed · 13라인 · 아무것도 안 붙음)
--   select po_doc_cancel('po', <id>) → status 'cancelled' · attached 전부 null · warnings [] · cancelled_by = 내 ims_staff.id
--   select po_doc_cancel('po', <id>, false) → status 'confirmed' (confirmed_at 이 있었다) · cancelled_at null · cancelled_by null
--   PO-02001a 취소 시도 → 「PO PO-02001a is closed (receiving finished) — a closed order cannot be cancelled — nothing was saved」
--   PO-02001b 가 입고 줄 없이 confirmed 면 취소된다 · attached.numbered_credits 는 null(CN-AMP-778812-1 은 credit_po_id 가 null)
