-- ─────────────────────────────────────────────────────────────
-- ⑤ PO 만들기·편집 ①차 — 뒷단 RPC 넷 (테스트 DB Asung-IMS · 2026-09-16)
--   po_create(공급처 …)            초안 만들기 — 공급처 기본값 + supplier_discount 복사 (표 둘을 건드린다)
--   po_lines_paste(po, 줄들, commit) ⭐⭐ 붙여넣기 — SKU·수량 목록 → 미리 보기(판정만) / 넣기 · 같은 모양으로 돌려준다
--   po_line_update(line, patch)     라인 수정 — 「받은 것보다 적게」와 「closed 문서」를 막는다 (다른 행을 봐야 해서 RPC)
--   po_line_delete(line)            라인 삭제 — 입고·인보이스가 붙은 줄은 막는다
--
-- 정본: docs/design/po-module.md §11-b(생성·확정) · §11-c(분할) · §11-d(라인·단가) · §11-e(할인) · §13 · §5(거래 표 규약)
-- 표: 20260916144201_po.sql(po · po_line · po_discount) · 읽기: 20260916175003_po_credit.sql 의 po_detail(관례 기준 · 이 파일은 읽기 함수를 바꾸지 않는다)
-- 선례: wms_complete_pack(20260806150000 · plpgsql · volatile · security invoker · jsonb 인자 · 「nothing was saved」 예외 · 작업자는 서버 유도 · revoke public/anon)
-- 지시서: ~/asung/prompts/po-write-rpc.md · 검토 이견 1~18(2026-09-16 · 3 은 ②안 · 9 는 메시지에 다음 할 일 · 14 는 예외 대신 판정)
--
-- ⭐⭐ 확정의 뜻이 바뀌었다(Caleb 실측 2026-09-16 · 정본 §11-b 정정 · 별건)
--   정본은 확정을 「이제 고치지 않겠다는 문서 잠금」이라 적었으나 틀렸다 — 확정 뒤 수정은 **빈번하다**(수량 추가 · 공급사와 통화하다 세일 품목 추가 · 가격은 인보이스에서).
--   ⭐ 확정 = **「공급처에 보냈다」**. 그때부터 올 물건이 존재하고 입고 대상이 된다. 그뿐이다. draft 도 confirmed 도 라인을 더하고 고친다. 잠그지 않는다.
--   📌 경위: 「만드는 사람과 누르는 사람이 같으니 결재가 아니다」까지는 맞았고 거기서 잠금까지 끌어낸 것이 설계 대화의 비약이었다. §13 의 「⬜ 분할 함수 차수에 잠금 트리거」도 이 뜻으로 고친다(말만).
--   ⚠️ 그래도 막아야 하는 것 둘 — ① 입고가 붙은 라인의 수량을 **받은 것보다 적게** 줄이는 것(앞뒤가 안 맞는다) ② **closed(입고 종료)·cancelled** 문서를 고치는 것.
--   ⚠️⚠️ 「100 시켜 100 청구받고 90 만 온 것」은 라인 수정이 아니다 — 발주 100 · 입고 90 · 인보이스 100 · 크레딧 10개분, 네 문서가 각자 사실을 말한다.
--      수량 수정을 크레딧으로 자동 전환하는 장치는 만들지 않는다. 크레딧은 공급처가 보내오는 문서다(③차). 자동 채우기 초안은 인보이스·크레딧 만들기 차수(지시서 §7).
--
-- ⭐ 나누는 기준(Caleb 합의) — 일이 여럿이면 RPC · 한 가지면 PostgREST(화면이 imsSaved() 로 되읽는다 · §10-j 3-i).
--   RPC 로 감싼 것: po_create(표 둘) · po_lines_paste(여러 줄 + 판정) · ⭐ po_line_update/po_line_delete(다른 행 — 입고 줄·문서 상태 — 을 저장 전에 봐야 한다).
--   ⚠️ 왜 라인 수정·삭제만 RPC 인가(검토 이견 3 · ②안): 「받은 것보다 적게 줄였다」와 「초과 입고」는 둘 다 remaining 이 음수로 **같은 모양**이라 po_detail warnings 로는 구별이 안 된다(③안 기각).
--      화면이 막는 것은 막는 것이 아니다(anon key 공개 · ①안 기각). 트리거 없음 규약(①차)이라 남는 길은 RPC 다.
--   PostgREST 그대로: 머리 칸(note · 창고 · 주문일) · 할인 줄 하나 · 확정(status=confirmed · confirmed_at/by) · 취소 · 입고 줄(다음 차수) — 다른 행을 볼 일이 없다.
--
-- ⭐ 관례(po_detail · wms_complete_pack 과 같다) — language plpgsql · **volatile**(쓰기) · security invoker(전부 auth_all · 우회할 것 없음) · set search_path = public, pg_temp ·
--   jsonb 반환 · ⚠️ 쓰기 함수는 실패를 **예외**로 분명히 한다(읽기 po_detail 의 null 과 다르다) · 메시지는 「… — nothing was saved」 · revoke public/anon + grant authenticated.
--   ⭐ 만든 사람(created_by)은 파라미터가 아니라 **auth.uid() → ims_staff.id 서버 유도**(검토 이견 4 · 선례 wms_complete_pack 은 auth.email() → wms_staff · 우리는 §10-h 열쇠 auth_user_id).
--     화면이 me.id 를 주면 아무 id 를 줄 수 있다(anon key 공개). ①차의 「⬜ 기본값 함수」는 이것으로 닫힌다 — 생성 길이 po_create 하나다.
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS)
-- ⚠️ [정정 2026-09-16 · 첫 실행에서 실측] text[] 에 따옴표 리터럴을 || 로 붙이면 Postgres 가 「배열 || 배열」로 해석해 그 문자열을 배열 리터럴로 읽는다 —
--    ERROR: malformed array literal: "no_product_supplier_link_for_this_supplier — price 0, fill in by hand". format(...) 결과는 text 타입이라 통과했고 리터럴만 터졌다(그래서 판정에 따라 되고 안 됐다).
--    ⇒ 배열에 붙이는 곳 16군데 전부 array_append(배열, 요소)로 바꿨다(v_msgs · v_warn · v_seen_ids · v_seen_n). 문법 검사로는 안 잡히는 종류 — 실행해야 드러난다.
--    이 파일을 고쳐 **같은 파일을 다시 적용**했다(psql -f · 함수 넷이 전부 create or replace 라 되풀이 안전 · grant/comment 도 되풀이 안전). 별도 파일로 가지 않은 이유는 아래 판단.
--    📌 판단: ①차 규칙(「적용된 마이그레이션은 고치지 않는다」)의 뜻은 「DB 에 실제로 살았던 정의를 이력에 남긴다」인데, 이 정의는 적용은 됐으나 **한 번도 제대로 돌지 않았다** —
--       깨진 정의를 이력에 남길 가치가 없고, 같은 300행을 두 파일에 두면 다음 사람이 어느 쪽이 도는지 헤맨다. 「적용됐지만 첫 실행에서 깨진 함수」는 원본을 고치고 다시 적용한다(이 경우만의 예외 · 표 DDL 이었다면 새 파일).
-- ─────────────────────────────────────────────────────────────

-- ═══ po_create — 초안 만들기 ═══
-- POST /rest/v1/rpc/po_create  {"p_supplier_id": "<uuid>", "p_warehouse_id": null, "p_order_date": null, "p_note": null}
-- → { id, po_number, status:'draft', currency_id, ship_to_warehouse_id, payment_term_name, discounts_copied, warnings:[…] }
create or replace function public.po_create(
  p_supplier_id  uuid,
  p_warehouse_id uuid default null,       -- 안 주면 ref_warehouse.is_default·is_active 가 정확히 하나일 때만 그것(검토 이견 6) · 아니면 null + warnings
  p_order_date   date default null,       -- 안 주면 오늘
  p_note         text default null
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_staff     uuid;
  v_sup       public.supplier%rowtype;
  v_cur       uuid;
  v_wh        uuid;
  v_wh_n      int;
  v_po_id     uuid;
  v_po_number text;
  v_disc      int := 0;
  v_warn      text[] := '{}';
begin
  -- 만든 사람 — 서버 유도(§10-h 열쇠 auth_user_id) · 행이 없으면 아무것도 안 쓴다
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then
    raise exception 'No active staff record for this login — nothing was saved';
  end if;

  select * into v_sup from public.supplier where id = p_supplier_id;
  if not found then
    raise exception 'Supplier % not found — nothing was saved', p_supplier_id;
  end if;
  -- ⚠️ 비활성·미판정 공급처는 막지 않는다(검토 이견 7) — 「발주처인가」의 판정은 화면의 정돈 규칙(§10-j 3-b) 한곳에. 여기서는 알리기만
  if not v_sup.is_active then v_warn := array_append(v_warn, 'supplier_inactive'); end if;
  if v_sup.is_purchasable is distinct from true then v_warn := array_append(v_warn, 'supplier_not_purchasable'); end if;

  -- 통화 — 공급처 기본통화 · 없으면 inv_config.base_currency(CAD · §4-④)(검토 이견 5) · 그것도 없으면 예외(po.currency_id 는 not null)
  v_cur := v_sup.currency_id;
  if v_cur is null then
    select c.id into v_cur
    from public.ref_currency c
    join public.inv_config k on k.key = 'base_currency' and k.value = c.code;
    if v_cur is null then
      raise exception 'Supplier has no currency and inv_config.base_currency does not point at a ref_currency row — nothing was saved';
    end if;
    v_warn := array_append(v_warn, 'currency_defaulted');
  end if;

  -- 창고 — 준 것 · 아니면 기본 창고가 정확히 하나일 때만(짐작으로 고르지 않는다)
  v_wh := p_warehouse_id;
  if v_wh is null then
    select count(*), (array_agg(w.id))[1] into v_wh_n, v_wh
    from public.ref_warehouse w where w.is_default and w.is_active;
    if coalesce(v_wh_n, 0) <> 1 then
      v_wh := null;
      v_warn := array_append(v_warn, 'warehouse_unset');
    end if;
  end if;

  -- ① po 한 행 — po_number 는 기본값 po_next_number() · 결제조건은 FK + 원문(그날의 조건 · §3-b 관례)
  insert into public.po (status, supplier_id, currency_id, payment_term_id, payment_term_name, ship_to_warehouse_id, order_date, created_by, note)
  values ('draft', p_supplier_id, v_cur, v_sup.payment_term_id, v_sup.payment_term_name, v_wh, coalesce(p_order_date, current_date), v_staff, p_note)
  returning id, po_number into v_po_id, v_po_number;

  -- ② ⭐ supplier_discount → po_discount 복사(예상 층 · §11-e · 활성만 · seq 그대로 · 원천 id 를 남긴다)
  --    ⚠️ 지금 supplier_discount 는 0행(§10-k)이라 아무것도 안 따라온다 — 구조는 둔다. 채우면 바로 듣는다(Caleb 2026-09-16)
  insert into public.po_discount (po_id, seq, name, percent, supplier_discount_id)
  select v_po_id, d.seq, d.name, d.percent, d.id
  from public.supplier_discount d
  where d.supplier_id = p_supplier_id and d.is_active
  order by d.seq;
  get diagnostics v_disc = row_count;

  return jsonb_build_object(
    'id', v_po_id, 'po_number', v_po_number, 'status', 'draft',
    'currency_id', v_cur, 'ship_to_warehouse_id', v_wh, 'payment_term_name', v_sup.payment_term_name,
    'discounts_copied', v_disc,
    'warnings', to_jsonb(v_warn));
end;
$$;

comment on function public.po_create(uuid, uuid, date, text) is '⑤ 발주 초안 만들기 — po 한 행(draft · po_number 기본값) + supplier_discount → po_discount 복사(예상 층). 공급처 기본통화·결제조건(FK+원문) 따라옴 · 통화 없으면 inv_config.base_currency · 창고 없으면 기본 창고가 정확히 하나일 때만. created_by 는 auth.uid() → ims_staff.id 서버 유도. 비활성·미판정 공급처는 warnings 로 알리고 막지 않는다. 실패는 예외(nothing was saved). 정본 po-module §11-b·e · §13 · 2026-09-16';

-- ═══ po_lines_paste — 붙여넣기 (미리 보기 / 넣기 · 같은 모양) ═══
-- POST /rest/v1/rpc/po_lines_paste  {"p_po_id": "<uuid>", "p_lines": [{"sku":"ABE50205","qty":10}, …], "p_commit": false}
-- → { po_id, po_number, committed,
--     summary: { total, ok, no_link, not_found, duplicate, exists, bad_qty, inserted, too_many, limit, message },
--     lines: [ { n, input_sku, input_qty, verdict, product_id, sku, product_name, product_active, unit_price, price_source, supplier_sku, line_no, inserted, message } ] }
--
-- ⭐ [Caleb 실측] 50줄 넘는 발주가 꽤 된다 — 하나씩 고르는 방식은 안 된다. 열쇠는 **우리 SKU**(공급처 SKU 는 다 갱신돼 있지 않고 SKU 를 안 두는 공급처도 있다) — 공급처 SKU 는 참고로만 담는다.
-- ⭐⭐ 미리 보기가 반드시 있다 — p_commit=false 면 넣지 않고 판정만. 근거: 50줄이 잘못 들어가면 하나씩 지워야 한다 · 데이터는 밖에서 온다(엑셀 · 옛 SKU · 공백 · 칸 밀림) ·
--    「이 공급처 제품이 아니다」가 마스터를 채우라는 신호가 된다. ⚠️ 미리 보기에서 고치게 만들지 않는다 — 원본을 고쳐 다시 붙인다(그래서 duplicate·exists 도 합치거나 더하지 않고 판정만 한다).
-- 판정:
--   ok         SKU 를 찾았고 이 공급처와 연결(product_supplier · 활성)이 있다 → 단가 Fixed>0 → Latest>0 → 0(§11-d · purchasing.html 285행과 같은 순서) · supplier_sku 를 연결에서
--   no_link    SKU 는 찾았는데 연결이 없거나 비활성 → 막지 않고 경고(Caleb) · 단가 0 · 사람이 채운다(단가 0 CHECK 없음 · 샘플 실물) · 비활성 연결은 §3-f 대로 단가를 제안하지 않는다(supplier_sku 는 참고로)
--   not_found  SKU 를 못 찾았다 → 넣지 않는다
--   duplicate  같은 SKU 가 앞줄에 이미 있다 → 넣지 않는다(합치지 않는다 · 검토 이견 8) · 메시지에 첫 줄 번호
--   exists     그 SKU 라인이 발주에 이미 있다 → 넣지 않는다(더하지 않는다 · 검토 이견 9) · 메시지에 「수량을 바꾸려면 그 라인을 고쳐라(po_line_update)」
--   bad_qty    수량이 0·음수·숫자 아님 → 넣지 않는다(qty_ea > 0 CHECK)
-- SKU 다듬기(검토 이견 12): 앞뒤 공백(비분리 공백 포함)만 자른다 · 정확히 찾는다(product.sku 유니크 인덱스) · 못 찾으면 대소문자 무시로 한 번 더(인덱스 없음 · 못 찾은 줄에만) → message case_fixed.
--   안쪽 공백·철자는 손대지 않는다 — SKU 정정은 적재 전에 끝났다(§3-f).
-- 한도(검토 이견 14 · Caleb): 500줄 — 넘으면 예외가 아니라 **판정**으로 돌려준다(summary.too_many · message) · 넣지도 않는다. 파일을 잘못 붙였을 때 사람이 무슨 일인지 알아야 한다.
-- 문서 상태: closed·cancelled 는 예외(§1 ②) · draft·confirmed 는 붙인다(확정 뒤 추가 허용 · 위 머리).
-- 수량은 낱개(EA)만 받는다 — 단위(CASE) 선택은 화면 라인 편집(entered_* 칸 · po_line_update)에서.
-- line_no: 기존 최대 + 1 부터 입력 순서대로(insertable 한 줄만 번호를 받는다) · 미리 보기도 같은 계산 — commit 때 다시 재니 사이에 누가 넣었으면 밀릴 수 있다(결과에 실제 번호가 온다).
-- commit=true 는 ok·no_link 만 넣고 나머지는 보고만 한다 — 사람이 미리 보기를 이미 봤다. 한 트랜잭션(도중 실패면 전부 취소).
create or replace function public.po_lines_paste(
  p_po_id  uuid,
  p_lines  jsonb,                          -- [{sku, qty}]
  p_commit boolean default false
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  c_limit      constant int := 500;
  v_po         public.po%rowtype;
  v_n          int;
  v_next       int;
  r            record;
  v_sku        text;
  v_qty        numeric;
  v_pid        uuid;  v_psku text;  v_pname text;  v_pactive boolean;
  v_fixed      numeric;  v_cost numeric;  v_ssku text;  v_lactive boolean;  v_link_found boolean;
  v_verdict    text;
  v_msgs       text[];
  v_price      numeric;
  v_src        text;
  v_line_no    int;
  v_inserted   boolean;
  v_exists_no  int;
  v_seen_ids   uuid[] := '{}';
  v_seen_n     int[]  := '{}';
  v_dup_of     int;
  v_rows       jsonb := '[]'::jsonb;
  n_ok int := 0; n_nolink int := 0; n_nf int := 0; n_dup int := 0; n_ex int := 0; n_bad int := 0; n_ins int := 0;
begin
  select * into v_po from public.po where id = p_po_id;
  if not found then
    raise exception 'PO % not found — nothing was saved', p_po_id;
  end if;
  if v_po.status in ('closed', 'cancelled') then
    raise exception 'PO % is % — lines cannot be added (closed = receiving finished) — nothing was saved', v_po.po_number, v_po.status;
  end if;

  v_n := coalesce(jsonb_array_length(p_lines), 0);
  if v_n > c_limit then
    -- ⭐ 예외가 아니라 판정 — 미리 보기 단계에서 걸리고 넣지도 않는다(Caleb)
    return jsonb_build_object(
      'po_id', p_po_id, 'po_number', v_po.po_number, 'committed', false,
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'no_link', 0, 'not_found', 0, 'duplicate', 0, 'exists', 0, 'bad_qty', 0, 'inserted', 0,
                                    'too_many', true, 'limit', c_limit,
                                    'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(line_no), 0) into v_next from public.po_line where po_id = p_po_id;

  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null;
    v_fixed := null; v_cost := null; v_ssku := null; v_lactive := null; v_link_found := false;
    v_verdict := null; v_msgs := '{}'; v_price := null; v_src := null; v_line_no := null; v_inserted := false; v_dup_of := null; v_exists_no := null;

    -- SKU 다듬기 — 앞뒤 공백(비분리 공백 포함)만
    v_sku := nullif(regexp_replace(coalesce(r.sku_raw, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
    -- 수량 — 숫자만
    v_qty := case when r.qty_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.qty_raw::numeric else null end;

    if v_sku is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'empty_sku');
    else
      select p.id, p.sku, p.name, p.is_active into v_pid, v_psku, v_pname, v_pactive
      from public.product p where p.sku = v_sku;                                  -- 유니크 인덱스
      if v_pid is null then
        select p.id, p.sku, p.name, p.is_active into v_pid, v_psku, v_pname, v_pactive
        from public.product p where upper(p.sku) = upper(v_sku) limit 1;         -- 폴백 · 인덱스 없음 · 못 찾은 줄에만
        if v_pid is not null then v_msgs := array_append(v_msgs, 'case_fixed'); end if;
      end if;
    end if;

    if v_verdict is null and v_pid is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'sku_not_in_product');
    end if;

    if v_verdict is null then
      if v_pactive is false then v_msgs := array_append(v_msgs, 'inactive_product'); end if;   -- 막지 않는다(제품은 감추지 않는다 · §10-j 3-b) · 알린다
      v_dup_of := (select v_seen_n[i] from generate_subscripts(v_seen_ids, 1) i where v_seen_ids[i] = v_pid limit 1);
      if v_dup_of is not null then
        v_verdict := 'duplicate';
        v_msgs := array_append(v_msgs, format('duplicate_of_paste_line_%s — fix the source and paste again', v_dup_of));
      else
        v_seen_ids := array_append(v_seen_ids, v_pid); v_seen_n := array_append(v_seen_n, r.n);
        select pl.line_no into v_exists_no from public.po_line pl where pl.po_id = p_po_id and pl.product_id = v_pid order by pl.line_no limit 1;
        if v_exists_no is not null then
          v_verdict := 'exists';
          v_msgs := array_append(v_msgs, format('already_on_line_%s — to change the quantity edit that line (po_line_update), not paste', v_exists_no));
        elsif v_qty is null or v_qty <= 0 then
          v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, 'qty_must_be_positive_number');
        else
          select ps.fixed_cost, ps.cost, ps.supplier_sku, ps.is_active, true
            into v_fixed, v_cost, v_ssku, v_lactive, v_link_found
          from public.product_supplier ps where ps.product_id = v_pid and ps.supplier_id = v_po.supplier_id;   -- (product_id, supplier_id) 유니크 인덱스
          if not coalesce(v_link_found, false) then
            v_verdict := 'no_link'; v_msgs := array_append(v_msgs, 'no_product_supplier_link_for_this_supplier — price 0, fill in by hand');
            v_price := 0; v_src := 'none'; v_ssku := null;
          elsif v_lactive is false then
            v_verdict := 'no_link'; v_msgs := array_append(v_msgs, 'link_inactive — price not suggested (§3-f), fill in by hand');
            v_price := 0; v_src := 'none';
          else
            v_verdict := 'ok';
            if coalesce(v_fixed, 0) > 0 then v_price := v_fixed; v_src := 'fixed';
            elsif coalesce(v_cost, 0) > 0 then v_price := v_cost; v_src := 'latest';
            else v_price := 0; v_src := 'none'; v_msgs := array_append(v_msgs, 'no_price — fixed and latest are both empty');
            end if;
          end if;
        end if;
      end if;
    end if;

    -- 넣을 수 있는 줄만 번호를 받는다
    if v_verdict in ('ok', 'no_link') then
      v_next := v_next + 1; v_line_no := v_next;
      if p_commit then
        insert into public.po_line (po_id, line_no, product_id, supplier_sku, qty_ea, unit_price)
        values (p_po_id, v_line_no, v_pid, v_ssku, v_qty, v_price);
        v_inserted := true; n_ins := n_ins + 1;
      end if;
    end if;

    case v_verdict
      when 'ok' then n_ok := n_ok + 1;
      when 'no_link' then n_nolink := n_nolink + 1;
      when 'not_found' then n_nf := n_nf + 1;
      when 'duplicate' then n_dup := n_dup + 1;
      when 'exists' then n_ex := n_ex + 1;
      when 'bad_qty' then n_bad := n_bad + 1;
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw,
      'verdict', v_verdict,
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive,
      'unit_price', v_price, 'price_source', v_src, 'supplier_sku', v_ssku,
      'line_no', v_line_no, 'inserted', v_inserted,
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  return jsonb_build_object(
    'po_id', p_po_id, 'po_number', v_po.po_number, 'committed', p_commit,
    'summary', jsonb_build_object('total', v_n, 'ok', n_ok, 'no_link', n_nolink, 'not_found', n_nf, 'duplicate', n_dup, 'exists', n_ex, 'bad_qty', n_bad,
                                  'inserted', n_ins, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_rows);
end;
$$;

comment on function public.po_lines_paste(uuid, jsonb, boolean) is '⑤ 붙여넣기 — SKU·수량 목록을 받아 판정(ok · no_link · not_found · duplicate · exists · bad_qty)하고 p_commit 이면 ok·no_link 만 po_line 에 넣는다(같은 모양으로 돌려준다). 열쇠는 우리 SKU(유니크 인덱스 · 대소문자 폴백) · 단가 Fixed→Latest→0 · 공급처 SKU 는 참고 · 합치거나 더하지 않는다(원본을 고쳐 다시 붙인다) · 500줄 한도는 판정(too_many) · closed·cancelled 는 예외. 정본 po-module §11-d · §13 · 2026-09-16';

-- ═══ po_line_update — 라인 수정 (막아야 하는 둘을 저장 전에 본다) ═══
-- POST /rest/v1/rpc/po_line_update  {"p_line_id": "<uuid>", "p_patch": {"qty_ea": 510}}     patch 키: qty_ea · unit_price · supplier_sku · tax_rule · note · entered_unit_product_id · entered_qty · entered_pack_factor
-- → { line: {…po_line 행…}, received_qty, po_number, status }
-- ⚠️ 왜 RPC 인가 — 「받은 것보다 적게」는 입고 줄(다른 표)을 봐야 하고, 사후 warnings 로는 초과 입고와 구별이 안 된다(머리 주석). 키가 없는 칸은 건드리지 않는다(부분 갱신 · PATCH 와 같은 뜻).
create or replace function public.po_line_update(
  p_line_id uuid,
  p_patch   jsonb
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_line   public.po_line%rowtype;
  v_po     public.po%rowtype;
  v_recv   numeric;
  v_qty    numeric;
begin
  select * into v_line from public.po_line where id = p_line_id;
  if not found then
    raise exception 'PO line % not found — nothing was saved', p_line_id;
  end if;
  select * into v_po from public.po where id = v_line.po_id;
  if v_po.status in ('closed', 'cancelled') then
    raise exception 'PO % is % — lines cannot be changed (closed = receiving finished) — nothing was saved', v_po.po_number, v_po.status;
  end if;
  if p_patch is null or jsonb_typeof(p_patch) <> 'object' then
    raise exception 'p_patch must be a JSON object — nothing was saved';
  end if;

  select coalesce(sum(qty_ea), 0) into v_recv from public.po_receipt_line where po_line_id = p_line_id;

  if p_patch ? 'qty_ea' then
    v_qty := (p_patch->>'qty_ea')::numeric;
    if v_qty is null or v_qty <= 0 then
      raise exception 'qty_ea must be a positive number — nothing was saved';
    end if;
    -- ⭐ 받은 것보다 적게 줄일 수 없다(§1 ①) — 100 시켜 90 온 것은 라인 수정이 아니라 입고 90 · 크레딧 10 이다
    if v_qty < v_recv then
      raise exception 'Line % of %: cannot set quantity to % — % already received. Quantity must be at least the received quantity. Nothing was saved',
        v_line.line_no, v_po.po_number, v_qty, v_recv;
    end if;
  end if;

  update public.po_line set
    qty_ea                  = case when p_patch ? 'qty_ea'                  then (p_patch->>'qty_ea')::numeric                 else qty_ea end,
    unit_price              = case when p_patch ? 'unit_price'              then (p_patch->>'unit_price')::numeric             else unit_price end,
    supplier_sku            = case when p_patch ? 'supplier_sku'            then nullif(p_patch->>'supplier_sku', '')          else supplier_sku end,
    tax_rule                = case when p_patch ? 'tax_rule'                then nullif(p_patch->>'tax_rule', '')              else tax_rule end,
    note                    = case when p_patch ? 'note'                    then nullif(p_patch->>'note', '')                  else note end,
    entered_unit_product_id = case when p_patch ? 'entered_unit_product_id' then nullif(p_patch->>'entered_unit_product_id', '')::uuid else entered_unit_product_id end,
    entered_qty             = case when p_patch ? 'entered_qty'             then nullif(p_patch->>'entered_qty', '')::numeric  else entered_qty end,
    entered_pack_factor     = case when p_patch ? 'entered_pack_factor'     then nullif(p_patch->>'entered_pack_factor', '')::numeric else entered_pack_factor end
  where id = p_line_id
  returning * into v_line;
  -- CHECK(qty_ea > 0 · unit_price >= 0 · entered_unit_ck)는 표가 그대로 지킨다 — 어기면 표의 예외가 그대로 올라간다

  return jsonb_build_object('line', to_jsonb(v_line), 'received_qty', v_recv, 'po_number', v_po.po_number, 'status', v_po.status);
end;
$$;

comment on function public.po_line_update(uuid, jsonb) is '⑤ 발주 라인 부분 갱신(patch 에 있는 키만) — closed·cancelled 문서는 거부 · qty_ea 를 입고 줄 합보다 적게는 거부(§1 · 「받은 것보다 적게」는 사후 warnings 로 초과 입고와 구별이 안 되어 RPC 로 막는다). 표 CHECK 는 그대로 지킨다. 갱신된 행을 돌려준다(되읽기 불필요). 정본 po-module §11-b·d · §13 · 2026-09-16';

-- ═══ po_line_delete — 라인 삭제 ═══
-- POST /rest/v1/rpc/po_line_delete  {"p_line_id": "<uuid>"}  → { deleted: true, po_id, po_number, line_no }
create or replace function public.po_line_delete(
  p_line_id uuid
) returns jsonb
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_line   public.po_line%rowtype;
  v_po     public.po%rowtype;
  v_recv   int;
  v_inv    int;
begin
  select * into v_line from public.po_line where id = p_line_id;
  if not found then
    raise exception 'PO line % not found — nothing was deleted', p_line_id;
  end if;
  select * into v_po from public.po where id = v_line.po_id;
  if v_po.status in ('closed', 'cancelled') then
    raise exception 'PO % is % — lines cannot be deleted — nothing was deleted', v_po.po_number, v_po.status;
  end if;
  select count(*) into v_recv from public.po_receipt_line where po_line_id = p_line_id;
  if v_recv > 0 then
    raise exception 'Line % of % has % receipt line(s) — a received line cannot be deleted (reduce nothing; receipts are events) — nothing was deleted', v_line.line_no, v_po.po_number, v_recv;
  end if;
  select count(*) into v_inv from public.po_invoice_line where po_line_id = p_line_id;
  if v_inv > 0 then
    -- FK(no action)가 어차피 막지만 사람이 읽을 수 있는 말로 먼저 막는다
    raise exception 'Line % of % is referenced by % invoice/credit line(s) — remove those first — nothing was deleted', v_line.line_no, v_po.po_number, v_inv;
  end if;

  delete from public.po_line where id = p_line_id;
  return jsonb_build_object('deleted', true, 'po_id', v_po.id, 'po_number', v_po.po_number, 'line_no', v_line.line_no);
end;
$$;

comment on function public.po_line_delete(uuid) is '⑤ 발주 라인 삭제 — closed·cancelled 문서 거부 · 입고 줄이 붙은 라인 거부(입고는 사건이다) · 인보이스·크레딧 줄이 가리키는 라인 거부(FK 가 막지만 읽을 수 있는 말로 먼저). 초안·확정 문서의 안 받은 라인만 지운다. 정본 po-module §11-b · §13 · 2026-09-16';

-- ═══ 권한 — 함수 EXECUTE 는 PUBLIC 기본 부여 · 명시 회수(선례) ═══
revoke all on function public.po_create(uuid, uuid, date, text)        from public, anon;
revoke all on function public.po_lines_paste(uuid, jsonb, boolean)     from public, anon;
revoke all on function public.po_line_update(uuid, jsonb)              from public, anon;
revoke all on function public.po_line_delete(uuid)                     from public, anon;
grant execute on function public.po_create(uuid, uuid, date, text)     to authenticated;
grant execute on function public.po_lines_paste(uuid, jsonb, boolean)  to authenticated;
grant execute on function public.po_line_update(uuid, jsonb)           to authenticated;
grant execute on function public.po_line_delete(uuid)                  to authenticated;

-- ─────────────────────────────────────────────────────────────
-- 화면(asung-ims · 대화 Claude)이 부르는 모양 — supabase-js v2
-- ─────────────────────────────────────────────────────────────
--   만들기   const { data, error } = await sb.rpc("po_create", { p_supplier_id: supplierId });          // data.id · data.po_number · data.warnings[]
--   미리보기 const { data } = await sb.rpc("po_lines_paste", { p_po_id: id, p_lines: rows, p_commit: false });   // rows = [{sku, qty}] · data.summary · data.lines[]
--   넣기     const { data } = await sb.rpc("po_lines_paste", { p_po_id: id, p_lines: rows, p_commit: true });    // 같은 모양 · lines[].inserted · line_no
--   라인수정 const { data, error } = await sb.rpc("po_line_update", { p_line_id: lineId, p_patch: { qty_ea: 510 } });   // error.message 가 「… nothing was saved」
--   라인삭제 const { data, error } = await sb.rpc("po_line_delete", { p_line_id: lineId });
--   그 밖(PostgREST 직접 · imsSaved 로 되읽기): sb.from("po").update({ status:"confirmed", confirmed_at: new Date().toISOString(), confirmed_by: me.id }).eq("id", id).select()
--     머리 note·창고·주문일 update · po_discount insert/update/delete · 취소 update({status:"cancelled", cancelled_at})
--   ⚠️ 예외는 supabase-js 에서 error.message 로 온다(HTTP 400 · PostgREST) — 화면은 그 문장을 그대로 띄운다.
--
-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 지시서 §4 ⓓ · 예상값은 검토 Claude 계산 · SQL 실측 2026-09-16 기준: PO-02002 = House of Cheatham · 라인 HBE00245 500 @ 8.20 · HBE05578 500 @ 7.77 ·
--        ABE50205↔HoC fixed 2.54 · cost 2.54 · supplier_sku 1-114-05-1200 · 활성 · AMP00405 는 Ampro 연결만 · base_currency CAD · 기본 창고 Asung Trading Inc. 하나)
-- ⚠️ psql 에서는 auth.uid() 가 null 이라 po_create·(created_by 유도)가 「No active staff record」로 실패한다 — po_create 는 화면(로그인)에서 검증하거나
--    psql 에서 request.jwt.claims 를 심어 돌린다(ims_staff 검증 때 쓴 방법 · §10-h). po_lines_paste · po_line_update · po_line_delete 는 auth 를 안 봐서 psql 로 된다.
-- ─────────────────────────────────────────────────────────────
-- ① 미리 보기 — PO-02002 에 다섯 줄
--   select jsonb_pretty(po_lines_paste((select id from po where po_number='PO-02002'),
--     '[{"sku":"ABE50205","qty":10},{"sku":"AMP00405","qty":5},{"sku":"ZZZ-TEST-404","qty":1},{"sku":" abe50205 ","qty":3},{"sku":"AMP00415","qty":0}]'::jsonb, false));
--   예상  summary total 5 · ok 1 · no_link 1 · not_found 1 · duplicate 1 · bad_qty 1 · inserted 0 · too_many false
--         n1 ABE50205  ok        unit_price 2.54 · price_source fixed · supplier_sku 1-114-05-1200 · line_no 3 · inserted false
--         n2 AMP00405  no_link   unit_price 0 · none · supplier_sku null · line_no 4 · message no_product_supplier_link…
--         n3 ZZZ-TEST-404 not_found · line_no null
--         n4 " abe50205 " duplicate · sku ABE50205 · message case_fixed · duplicate_of_paste_line_1 …
--         n5 AMP00415  bad_qty   · message qty_must_be_positive_number
--   ⚠️ 어느 줄도 들어가지 않았다: select count(*) from po_line pl join po p on p.id=pl.po_id where p.po_number='PO-02002';   → 2
-- ② 넣기 — 같은 다섯 줄 · p_commit true
--   예상  같은 판정 · inserted 2 · n1·n2 의 inserted true · line_no 3 · 4
--         select line_no, pr.sku, qty_ea, unit_price, supplier_sku from po_line pl join po p on p.id=pl.po_id join product pr on pr.id=pl.product_id where p.po_number='PO-02002' order by 1;
--         → 1 HBE00245 500 8.20 · 2 HBE05578 500 7.77 · 3 ABE50205 10 2.54 1-114-05-1200 · 4 AMP00405 5 0 null
--   다시 ① 을 돌리면 n1·n2 가 exists(already_on_line_3 / _4 …) 로 바뀐다
-- ③ 라인 수정
--   select po_line_update((select pl.id from po_line pl join po p on p.id=pl.po_id where p.po_number='PO-02002' and pl.line_no=1), '{"qty_ea": 510}');   → line.qty_ea 510 · received_qty 0
--   select po_line_update((select pl.id from po_line pl join po p on p.id=pl.po_id where p.po_number='PO-02001a' and pl.line_no=1), '{"qty_ea": 599}');
--         → 예외 「Line 1 of PO-02001a: cannot set quantity to 599 — 600 already received …」 (입고 600)
--   select po_line_update((… PO-02001a line 1 …), '{"note": "test"}');   → 예외 「PO PO-02001a is closed …」 (closed 문서)
-- ④ 라인 삭제
--   select po_line_delete((… PO-02001a line 1 …));       → 예외 「… has 2 receipt line(s) …」
--   select po_line_delete((… PO-02002 line 4 (AMP00405) …));   → deleted true · line_no 4 → 그리고 ② 의 line 3 ABE50205 는 남는다(검증 데이터 · 지우지 않는다)
-- ⑤ 한도 — 501줄
--   select (po_lines_paste((select id from po where po_number='PO-02002'), (select jsonb_agg(jsonb_build_object('sku','X','qty',1)) from generate_series(1,501)), true)) -> 'summary';
--         → too_many true · total 501 · inserted 0 · message Too many lines (501) … · 아무것도 안 들어간다
-- ⑥ 닫힌 문서 — po_lines_paste((… PO-02001a …), '[{"sku":"ABE50205","qty":1}]', false)   → 예외 「PO PO-02001a is closed …」
-- ⑦ po_create (화면에서 · 또는 JWT 심어서) — House of Cheatham
--   예상  po_number PO-02003 · status draft · currency_id = HoC 의 것 · ship_to_warehouse_id = Asung Trading Inc. · payment_term_name 'Net 30' · discounts_copied 0(supplier_discount 0행) · warnings [] (HoC 활성 · is_purchasable true 면 · 아니면 supplier_not_purchasable)
--   확인  select po_number, status, payment_term_name, created_by is not null from po where po_number='PO-02003';
-- ⑧ 권한
--   select routine_name, grantee from information_schema.routine_privileges where routine_name in ('po_create','po_lines_paste','po_line_update','po_line_delete') order by 1,2;   → authenticated 만
