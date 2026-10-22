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

-- ═══ pln-1 — PO 「Paste lines」 에 가격 칸 · po_lines_paste 재발행 (2026-10-22 · 판정 624 · Caleb 「SO 에 paste lines 에 가격을 어제 넣었잖아? 그것과 같은 방식으로 PO 에 넣어줘」) ═══
--   p_lines 의 줄 꼴 {sku, qty, price?} — price 는 선택 · 비우면 지금처럼 공급처 고정 단가 → 최근 단가 → 0 · 0 은 받는다(공급처 무상 줄) · 음수 · 숫자 아님은 그 줄만 bad_price(미리 보기에 사유 · 나머지 줄은 그대로).
--   붙인 가격 = 그 줄의 단가(Unit price · 할인 전 · PO 통화) — PO 의 문서 할인(공급처 할인 사슬)은 지금처럼 그 위에 걸린다(2.50 + 10% → 지불 2.25) · ⚠️ SO 의 「붙인 가격 = 최종」(532 · 542)과 다르다(판정 624).
--   연결 없음(no_link) · 꺼진 연결 줄에 붙인 가격이 있으면 그 값을 쓴다(사람이 값을 줬으니) · 판정 · 경고 글은 그대로(「pasted price used」) · product_supplier 의 cost · fixed_cost 는 안 바꾼다.
--   반환: 줄에 input_price · unit_price · price_source = 'pasted' | 'fixed' | 'latest' | 'none' · summary 에 bad_price 수 · 시그니처 · invoker · grant · comment 무변(create or replace).
--   원본 = 20260918000000_ims_rpc_honest_refusal_po.sql:198 (DB prosrc md5 698d9a56db8f590d386a02d495ac0e16 · 148 줄) + 더한 줄 · 바꾼 줄(가격 자리 열 곳) · 새 md5 00ad0eadccab6d03bd4ebbe78fe79f76
create or replace function public.po_lines_paste(
  p_po_id  uuid,
  p_lines  jsonb,                          -- [{sku, qty, price?}]   (pln-1: price 선택)
  p_commit boolean default false
) returns jsonb
language plpgsql
volatile
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
  v_praw       text;  v_pasted numeric;                                                                -- pln-1 판정 624: 붙인 가격(그 줄의 단가 · 할인 전) — 비면 null · 숫자(0 이상)면 pasted · 아니면 bad_price
  v_line_no    int;
  v_inserted   boolean;
  v_exists_no  int;
  v_seen_ids   uuid[] := '{}';
  v_seen_n     int[]  := '{}';
  v_dup_of     int;
  v_rows       jsonb := '[]'::jsonb;
  n_ok int := 0; n_nolink int := 0; n_nf int := 0; n_dup int := 0; n_ex int := 0; n_bad int := 0; n_ins int := 0;
  n_badp int := 0;                                                                                              -- pln-1
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b

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
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'no_link', 0, 'not_found', 0, 'duplicate', 0, 'exists', 0, 'bad_qty', 0, 'bad_price', 0, 'inserted', 0,
                                    'too_many', true, 'limit', c_limit,
                                    'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(line_no), 0) into v_next from public.po_line where po_id = p_po_id;

  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw, t.e->>'price' as price_raw                                      -- pln-1: price 는 선택
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null;
    v_fixed := null; v_cost := null; v_ssku := null; v_lactive := null; v_link_found := false;
    v_verdict := null; v_msgs := '{}'; v_price := null; v_src := null; v_line_no := null; v_inserted := false; v_dup_of := null; v_exists_no := null;
    v_praw := nullif(regexp_replace(coalesce(r.price_raw, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');                                            -- pln-1: 비우면 지금처럼(고정 → 최근 → 0)
    v_pasted := case when v_praw ~ '^[0-9]+(\.[0-9]+)?$' then v_praw::numeric else null end;                                                -- 0 은 받는다(공급처 무상 줄) · 음수 · 숫자 아님은 bad_price

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
        elsif v_praw is not null and v_pasted is null then                                                                                     -- pln-1 판정 624: 그 줄만 거부 · 나머지는 그대로
          v_verdict := 'bad_price'; v_msgs := array_append(v_msgs, 'price_must_be_zero_or_a_positive_number');
        else
          select ps.fixed_cost, ps.cost, ps.supplier_sku, ps.is_active, true
            into v_fixed, v_cost, v_ssku, v_lactive, v_link_found
          from public.product_supplier ps where ps.product_id = v_pid and ps.supplier_id = v_po.supplier_id;   -- (product_id, supplier_id) 유니크 인덱스
          if not coalesce(v_link_found, false) then
            v_verdict := 'no_link'; v_msgs := array_append(v_msgs, 'no_product_supplier_link_for_this_supplier — ' || case when v_pasted is null then 'price 0, fill in by hand' else 'pasted price used' end);   -- pln-1: 사람이 값을 줬으면 쓴다 · 경고는 그대로
            v_price := coalesce(v_pasted, 0); v_src := case when v_pasted is null then 'none' else 'pasted' end; v_ssku := null;
          elsif v_lactive is false then
            v_verdict := 'no_link'; v_msgs := array_append(v_msgs, 'link_inactive — ' || case when v_pasted is null then 'price not suggested (§3-f), fill in by hand' else 'pasted price used' end);   -- pln-1
            v_price := coalesce(v_pasted, 0); v_src := case when v_pasted is null then 'none' else 'pasted' end;
          else
            v_verdict := 'ok';
            if v_pasted is not null then v_price := v_pasted; v_src := 'pasted';                                                                -- pln-1 판정 624: 붙인 가격 = 그 줄 단가(할인 전) · product_supplier 는 안 바꾼다
            elsif coalesce(v_fixed, 0) > 0 then v_price := v_fixed; v_src := 'fixed';
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
      when 'bad_price' then n_badp := n_badp + 1;                                                                                             -- pln-1
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw, 'input_price', r.price_raw,                                                        -- pln-1
      'verdict', v_verdict,
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive,
      'unit_price', v_price, 'price_source', v_src, 'supplier_sku', v_ssku,
      'line_no', v_line_no, 'inserted', v_inserted,
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  return jsonb_build_object(
    'po_id', p_po_id, 'po_number', v_po.po_number, 'committed', p_commit,
    'summary', jsonb_build_object('total', v_n, 'ok', n_ok, 'no_link', n_nolink, 'not_found', n_nf, 'duplicate', n_dup, 'exists', n_ex, 'bad_qty', n_bad, 'bad_price', n_badp,   -- pln-1
                                  'inserted', n_ins, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_rows);
end;
$$;
comment on function public.po_lines_paste(uuid, jsonb, boolean) is '⑤ 붙여넣기 — SKU·수량(·가격) 목록을 받아 판정(ok · no_link · not_found · duplicate · exists · bad_qty · bad_price)하고 p_commit 이면 ok·no_link 만 po_line 에 넣는다(같은 모양으로 돌려준다). 열쇠는 우리 SKU(유니크 인덱스 · 대소문자 폴백) · 단가 = 붙인 가격(pln-1 판정 624 · 할인 전 · PO 통화 · 0 허용)이 있으면 그것 · 없으면 Fixed→Latest→0(경고) · 500 줄 캡은 예외가 아니라 판정 · 첫머리 ims_require_write(purchasing)';

-- ═══ 착지 — 몸 md5 · 오버로드 하나 · invoker 그대로 · ACL 무변 · 다른 PO 함수 무변 ═══
do $$
declare v_bad text := '';
begin
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') <> 1 then v_bad := v_bad || ' overloads'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') <> '00ad0eadccab6d03bd4ebbe78fe79f76' then v_bad := v_bad || ' body'; end if;
  if (select p.prosecdef or p.provolatile <> 'v' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') then v_bad := v_bad || ' not_invoker_volatile'; end if;
  if (select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' acl'; end if;
  if not has_function_privilege('authenticated', 'public.po_lines_paste(uuid, jsonb, boolean)', 'execute') or has_function_privilege('anon', 'public.po_lines_paste(uuid, jsonb, boolean)', 'execute') then v_bad := v_bad || ' acl2'; end if;
  if (select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') !~ 'bad_price' then v_bad := v_bad || ' text'; end if;
  if v_bad <> '' then raise exception 'pln-1 landing check failed:%', v_bad; end if;
end $$;
