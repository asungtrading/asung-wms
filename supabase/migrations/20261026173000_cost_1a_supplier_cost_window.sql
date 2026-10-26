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

-- ═══ cost-1a — 공급처 단가(product_supplier.cost · fixed_cost)를 원가 열쇠 뒤로 ① 더하기만 (2026-10-26 · 판정 759 · 764 · 765 · deferred 339 · Caleb 「B」 · 「그분들은 못봐도 돼」 · 「B」) ═══
--   판정 759: 공급처 단가는 원가 열쇠(ims_can_view_cost · 판정 578)가 있을 때만 — 제품 화면 · 내보내기(exp-1 에서 끝) · DB 모두 · 판정 580 의 「purchasing ∨ master ∨ cost 면 읽기」 를 원가 칸에 대해 좁힌다
--   판정 764: 원가 열쇠를 아무에게도 새로 켜지 않는다(지금 단가를 읽고 열쇠가 없는 활성 직원 일곱은 가려져도 된다 · 필요하면 Staff 에서 켠다)
--   판정 765: 원가 열쇠 없는 직원이 PO 를 만들 때 줄 단가를 공급처 단가로 채우지 않는다(0 · 손으로) — 열쇠 있으면 지금처럼 Fixed → Latest
--   순서(cost-1 지시서 C): cost-1a(이 파일 · 더하기만 · grant 그대로 ⇒ 옛 화면도 그대로 돈다) → cost-1a2(product_update 두 문장) → 대화 Claude 가 화면 일곱을 새 길로 → Caleb 배포 · 화면 시험 → cost-1b(칸 grant 회수 · 파일만 먼저)
--   ① product_supplier_costs(ids | supplier | stats) — 새 창구 · definer · 열쇠 없으면 빈 결과(이견 7)
--   ② po_lines_paste 재발행 — invoker → definer(1b 뒤 invoker 는 cost 칸을 못 읽는다) · 문은 :27 ims_require_write('purchasing') 그대로(po.html 열쇠 = purchasing · po_line 쓰기 정책과 같다) · 765: 열쇠 없으면 단가 0 · 'none' · 'no_cost_permission — price 0, fill in by hand'(unit_price 는 not null · 이견 4) · pasted 는 열쇠와 무관
--   ③ price_formula_preview 재발행 — invoker → definer · 첫 줄 문 = 원가 열쇠(거부 · 'needs the cost permission' · 이견 6) · product_price 는 :36 ~ 37 이 purpose = 'sale' 만 모아 reference 등급(760)은 안 샌다
--   ④ po_receipt_latest_apply 재발행 — 반환 latest_updated 의 old_cost · new_cost 를 열쇠 없는 사람에게는 뺀다(receiving.html:217 이 그린다 · 이견 3) · 갱신 자체는 그대로 · _by 둘 · 셸 둘 무변
--   원본(DB md5 · 2026-10-26 테스트 DB): po_lines_paste = 20261022190351_pln_1_po_paste_price.sql(00ad0eadccab6d03bd4ebbe78fe79f76 · 156 줄) · price_formula_preview = 20261002012641_price_1_formula.sql(749a96f8c2a81bdf2107ec9edfc65be2 · 70 줄) · po_receipt_latest_apply = 20261022191756_lat_1_receipt_updates_latest.sql(1a70faf6e01e16c6497bf6be2381ba70 · 49 줄) — 바이트 + 바꾼 줄만(② 2 줄 바꿈 · 2 줄 더함 / ③ 1 줄 더함 / ④ 2 줄 바꿈 · 1 줄 더함)
--   무접촉: product_supplier 표 · 정책(product_supplier_select = purchasing ∨ master ∨ cost · rls-3b) · grant(1b 가 따로) · po_receipt_confirm_by · post_now_by · 셸 둘 · product_create_core · product_export(exp-1 · 이미 원가 열쇠) · stk_value_total · product_list · 새 표 · 칸 · 시퀀스 0 · 검증 supabase/tests/cost_1_check.sql
--   앞 조건: ims_can_view_cost 있음 · 창구 아직 없음 · 원본 셋 md5 그대로(다르면 멈춤 — 지시서를 다시)

do $$
declare v_bad text := '';
begin
  if to_regprocedure('public.ims_can_view_cost()') is null then v_bad := v_bad || ' ims_can_view_cost'; end if;
  if to_regprocedure('public.product_supplier_costs(uuid[], uuid, boolean)') is not null then v_bad := v_bad || ' product_supplier_costs_already_there'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') is distinct from '00ad0eadccab6d03bd4ebbe78fe79f76' then v_bad := v_bad || ' po_lines_paste_not_pln_1'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'price_formula_preview') is distinct from '749a96f8c2a81bdf2107ec9edfc65be2' then v_bad := v_bad || ' price_formula_preview_not_price_1'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_latest_apply') is distinct from '1a70faf6e01e16c6497bf6be2381ba70' then v_bad := v_bad || ' po_receipt_latest_apply_not_lat_1'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM512', message = format('STOP - cost-1a needs%s - nothing was changed', v_bad); end if;
end $$;

-- ═══ ① 원가 읽기 창구 — product_supplier_costs(ids | supplier | stats) · 유일한 cost · fixed_cost 읽기 길 ═══
create function public.product_supplier_costs(p_product_ids uuid[] default null, p_supplier_id uuid default null, p_stats boolean default false) returns jsonb
language plpgsql stable security definer set search_path = public, pg_temp as $$
-- cost-1a 판정 759 · 764: 공급처 단가(cost = Latest · fixed_cost = Fixed)를 주는 유일한 읽기 길 — 원가 열쇠(ims_can_view_cost · 판정 578)가 없으면 거부가 아니라 빈 결과 {has_key:false, rows:[]}
--   (화면이 원가 아닌 읽기 옆에 한 번 더 불러 칸만 채운다 · has_key 로 열쇠도 안다 — ims_can_view_cost 를 따로 안 불러도 된다)
--   갈래 ⓐ 제품 id 목록(≤ 1,000 · 넘으면 거부 · p_supplier_id 로 더 좁힐 수 있다) — products · product-sheet · purchasing 의 한 제품 · 한 쪽
--   갈래 ⓑ 공급처 하나(p_product_ids 없이) — 그 공급처의 줄 전부(꺼진 줄도 · is_active 를 함께 준다 · 최대 796 실측 2026-09-20) — po.html 줄 고르기 · supplier-products 목록
--   갈래 ⓒ p_stats — 공급처별 통계(켜진 줄만 · n · n_default · n_no_price · last_supplied · p_supplier_id 로 하나만) — supplier-products.html loadStats(:138) 의 12,721 행 루프 대신
--       n_no_price = coalesce(cost, 0) = 0 and coalesce(fixed_cost, 0) = 0 (화면의 Number(null) === 0 과 같은 뜻)
--   jsonb 한 행이라 PostgREST 1,000 행 캡과 무관 · 1b 뒤에는 이 길만 cost · fixed_cost 를 낸다(authenticated 의 칸 grant 회수)
declare
  v_rows jsonb;
begin
  if not public.ims_can_view_cost() then
    return jsonb_build_object('has_key', false, 'rows', '[]'::jsonb);
  end if;
  if p_stats then
    select coalesce(jsonb_agg(jsonb_build_object('supplier_id', x.supplier_id, 'n', x.n, 'n_default', x.n_default, 'n_no_price', x.n_no_price, 'last_supplied', x.last_supplied) order by x.supplier_id), '[]'::jsonb)
      into v_rows
      from (select ps.supplier_id, count(*) as n, count(*) filter (where ps.is_default) as n_default,
                   count(*) filter (where coalesce(ps.cost, 0) = 0 and coalesce(ps.fixed_cost, 0) = 0) as n_no_price,
                   max(ps.last_supplied) as last_supplied
              from public.product_supplier ps
             where ps.is_active and (p_supplier_id is null or ps.supplier_id = p_supplier_id)
             group by ps.supplier_id) x;
    return jsonb_build_object('has_key', true, 'stats', v_rows, 'rows', '[]'::jsonb);
  end if;
  if p_product_ids is null and p_supplier_id is null then
    raise exception 'Give product ids or a supplier — nothing was read';
  end if;
  if cardinality(p_product_ids) > 1000 then
    raise exception 'Too many products in one call (% — the limit is 1000) — split the list', cardinality(p_product_ids);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('product_id', ps.product_id, 'supplier_id', ps.supplier_id, 'cost', ps.cost, 'fixed_cost', ps.fixed_cost, 'is_active', ps.is_active) order by ps.product_id, ps.supplier_id), '[]'::jsonb)
    into v_rows
    from public.product_supplier ps
   where (p_product_ids is null or ps.product_id = any(p_product_ids))
     and (p_supplier_id is null or ps.supplier_id = p_supplier_id);
  return jsonb_build_object('has_key', true, 'rows', v_rows);
end $$;
revoke all on function public.product_supplier_costs(uuid[], uuid, boolean) from public, anon, service_role;
grant execute on function public.product_supplier_costs(uuid[], uuid, boolean) to authenticated;
comment on function public.product_supplier_costs(uuid[], uuid, boolean) is 'cost-1a 판정 759 · 764 — 공급처 단가(cost · fixed_cost)의 유일한 읽기 길: 원가 열쇠(ims_can_view_cost) 없으면 {has_key:false, rows:[]} · 갈래 = 제품 id 목록(≤ 1,000) | 공급처 하나 | p_stats(공급처별 통계) · jsonb 한 행 · authenticated 만';

-- ═══ ② po_lines_paste 재발행 — 원본 pln-1 바이트 + declare 1 줄 + 문 뒤 1 줄 + :99 읽기 1 줄 + :111 분기 1 줄 · invoker → definer(search_path 고정) ═══
CREATE OR REPLACE FUNCTION public.po_lines_paste(p_po_id uuid, p_lines jsonb, p_commit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_cost_key   boolean;                                                                                        -- cost-1a 판정 765
begin
  perform public.ims_require_write('purchasing', 'saved');     -- ②-b
  v_cost_key := public.ims_can_view_cost();                                                                   -- cost-1a 판정 764 · 765: 원가 열쇠(ims_can_view_cost · 판정 578) — 없으면 공급처 단가를 읽지도 제안하지도 않는다

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
          select case when v_cost_key then ps.fixed_cost end, case when v_cost_key then ps.cost end, ps.supplier_sku, ps.is_active, true   -- cost-1a 판정 765: 열쇠 없으면 단가는 읽지 않는다(null)
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
            elsif not v_cost_key then v_price := 0; v_src := 'none'; v_msgs := array_append(v_msgs, 'no_cost_permission — price 0, fill in by hand');   -- cost-1a 판정 765: 원가 열쇠 없음 = 제안 없음(줄은 선다 · unit_price 는 not null 이라 0)
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
$function$;

-- ═══ ③ price_formula_preview 재발행 — 원본 price-1 바이트 + 첫 줄 문 1 줄 · invoker → definer ═══
CREATE OR REPLACE FUNCTION public.price_formula_preview(p_formula jsonb, p_skus text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_base    jsonb;
  v_sup     uuid;
  v_cur     uuid;
  v_rows    jsonb := '[]'::jsonb;
  v_sku     text;
  p         public.product%rowtype;
  v_link    record;
  v_calc    jsonb;
  v_curr    jsonb;
  v_chg     jsonb;
  v_flags   jsonb;
  v_wold    numeric;
  v_wnew    numeric;
begin
  if not public.ims_can_view_cost() then raise exception 'Price formula preview needs the cost permission — ask an admin to switch it on in Staff — nothing was read'; end if;   -- cost-1a 판정 759 · 764: 첫 줄 문 — 식은 원가로 값을 셈하므로 결과에서 원가를 거꾸로 알 수 있다 · definer 로 바꾸며(1b 뒤 invoker 는 cost 칸을 못 읽는다) 문이 섰다
  if p_skus is null or cardinality(p_skus) = 0 then
    raise exception 'No SKUs given';
  end if;
  if cardinality(p_skus) > 1000 then
    raise exception 'Too many SKUs in one preview (% — the limit is 1000) — split the list', cardinality(p_skus);
  end if;
  v_base := public.price_formula_calc(p_formula, null);
  if coalesce(jsonb_typeof(v_base->'formula'), 'null') = 'null' then
    return jsonb_build_object('formula', null, 'blocks', v_base->'blocks', 'rows', '[]'::jsonb);
  end if;
  v_sup := (v_base->'formula'->>'supplier_id')::uuid;
  v_cur := (v_base->'formula'->>'currency_id')::uuid;
  foreach v_sku in array p_skus loop
    v_flags := '[]'::jsonb; v_calc := null; v_curr := null; v_chg := null; v_link := null; p := null;
    select * into p from public.product x where x.sku = v_sku and x.is_active;
    if p.id is null then
      v_rows := v_rows || jsonb_build_object('sku', v_sku, 'product_id', null, 'is_set', null, 'cost', null, 'row_currency', null, 'formula_id_now', null, 'calc', null, 'current', null, 'changes', null, 'flags', jsonb_build_array('unknown_sku'));
      continue;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('tier_id', t.id, 'code', t.code, 'price', pp.price, 'source', pp.source) order by t.code), '[]'::jsonb) into v_curr
      from public.product_price pp join public.ref_price_tier t on t.id = pp.tier_id where pp.product_id = p.id and pp.is_active and t.is_active and t.purpose = 'sale';
    if p.parent_product_id is not null then
      v_rows := v_rows || jsonb_build_object('sku', v_sku, 'product_id', p.id, 'is_set', true, 'cost', null, 'row_currency', null, 'formula_id_now', null, 'calc', null, 'current', v_curr, 'changes', null, 'flags', jsonb_build_array('set_skipped'));
      continue;
    end if;
    select ps.cost, ps.currency_id, ps.price_formula_id into v_link from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = v_sup and ps.is_active;
    if not found then
      v_flags := v_flags || '"no_supplier_link"'::jsonb;
    end if;
    if v_link.currency_id is not null and v_link.currency_id <> v_cur then
      v_flags := v_flags || '"currency_differs"'::jsonb;
    end if;
    if found and (v_link.cost is null or v_link.cost <= 0) then
      v_flags := v_flags || '"no_cost"'::jsonb;
    end if;
    v_calc := public.price_formula_calc(p_formula, v_link.cost);
    if exists (select 1 from jsonb_array_elements(v_curr) c where c->>'source' = 'manual') then
      v_flags := v_flags || '"manual_price"'::jsonb;
    end if;
    select coalesce(jsonb_agg(jsonb_build_object('tier_id', t->>'tier_id', 'code', (t->>'code')::int, 'old', (c->>'price')::numeric, 'new', (t->>'price')::numeric,
                                                 'pct', case when (c->>'price')::numeric > 0 then round(((t->>'price')::numeric - (c->>'price')::numeric) / (c->>'price')::numeric * 100, 2) end) order by (t->>'code')::int), '[]'::jsonb)
      into v_chg
      from jsonb_array_elements(coalesce(v_calc->'tiers', '[]'::jsonb)) t left join jsonb_array_elements(v_curr) c on c->>'tier_id' = t->>'tier_id';
    select (c->>'price')::numeric into v_wold from jsonb_array_elements(v_curr) c where (c->>'code')::int = 1;
    v_wnew := (v_calc->>'wholesale')::numeric;
    if v_wold is not null and v_wold > 0 and v_wnew is not null and abs(v_wnew - v_wold) / v_wold > 0.10 then
      v_flags := v_flags || '"big_change"'::jsonb;
    end if;
    v_rows := v_rows || jsonb_build_object('sku', v_sku, 'product_id', p.id, 'is_set', false, 'cost', v_link.cost, 'row_currency', v_link.currency_id, 'formula_id_now', v_link.price_formula_id,
                                           'calc', v_calc, 'current', v_curr, 'changes', v_chg, 'flags', v_flags);
  end loop;
  return jsonb_build_object('formula', v_base->'formula', 'blocks', '[]'::jsonb, 'rows', v_rows);
end;
$function$;

-- ═══ ④ po_receipt_latest_apply 재발행 — 원본 lat-1 바이트 + declare 1 줄 + 반환 2 줄 ═══
CREATE OR REPLACE FUNCTION public.po_receipt_latest_apply(p_receipt_id uuid, p_post_id uuid, p_staff uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- 판정 626 · 627: 값 = 그 PO 줄을 청구한 마지막 확정 인보이스 줄의 단가(할인 전 · 인보이스 통화) · 날짜 = 입고의 received_on · fixed_cost 는 안 건드린다
--   고치지 않는 줄: 확정 인보이스 줄 없음 · 단가 0(무상) · 받은 수량 0 · 연결 없음(latest_no_link) · 통화 다름(latest_currency_mismatch) · 더 새 공급일이 이미 있음(latest_older_skipped) · 같은 값(unchanged · 조용히)
--   꺼진 연결은 고친다(값은 사실) · 세트 줄(제품에 parent)은 낱개 단가(÷ pack_factor)로 낱개 행에(latest_set_converted) · 같은 날 둘이면 나중 확정이 이긴다(>= 로 덮는다)
declare
  v_r   public.po_receipt%rowtype;  v_po public.po%rowtype;
  v_upd jsonb := '[]'::jsonb;  v_skip jsonb := '[]'::jsonb;  v_warn text[] := '{}';
  x record;  v_ps record;  v_cur uuid;  v_target uuid;  v_unit numeric;  v_tsku text;
  v_strip text[] := case when public.ims_can_view_cost() then '{}'::text[] else '{old_cost,new_cost}'::text[] end;   -- cost-1a 판정 759 · 764: 부르는 사람(auth.uid · 입고 확정 · 먼저 반영 화면)에게 원가 열쇠가 없으면 반환 latest_updated 의 old_cost · new_cost 를 뺀다(갱신은 그대로 · sku · last_supplied 는 남는다) · receiving.html:217 이 보는 자리
begin
  select * into v_r from public.po_receipt where id = p_receipt_id;
  if not found then raise exception 'Receipt % not found — nothing was saved', p_receipt_id; end if;
  select * into v_po from public.po where id = v_r.po_id;
  if not found then raise exception 'PO of receipt % not found — nothing was saved', v_r.receipt_number; end if;
  for x in
    select pl.id as po_line_id, pl.line_no, pl.product_id, pr.sku, pr.parent_product_id, pr.pack_factor, sum(l.qty_ea) as qty,
           iv.unit_price as gross, iv.currency_id as inv_cur, iv.invoice_number
    from public.po_receipt_line l
    join public.po_line pl on pl.id = l.po_line_id
    join public.product pr on pr.id = pl.product_id
    left join lateral (select il.unit_price, i.currency_id, i.invoice_number
                         from public.po_invoice_line il join public.po_invoice i on i.id = il.po_invoice_id
                        where il.po_line_id = pl.id and il.line_kind = 'goods' and i.doc_kind = 'invoice' and i.status = 'confirmed' and il.is_payable and il.qty_ea > 0
                        order by i.confirmed_at desc nulls last, i.invoice_number desc limit 1) iv on true
    where l.receipt_id = p_receipt_id and (p_post_id is null or l.post_id = p_post_id)
    group by pl.id, pl.line_no, pl.product_id, pr.sku, pr.parent_product_id, pr.pack_factor, iv.unit_price, iv.currency_id, iv.invoice_number
    order by pl.line_no
  loop
    if coalesce(x.qty, 0) <= 0 then v_skip := v_skip || jsonb_build_object('sku', x.sku, 'reason', 'zero_qty'); continue; end if;
    if x.gross is null then v_skip := v_skip || jsonb_build_object('sku', x.sku, 'reason', 'no_confirmed_invoice_line'); continue; end if;
    if x.gross <= 0 then v_skip := v_skip || jsonb_build_object('sku', x.sku, 'reason', 'free'); continue; end if;
    v_target := x.product_id; v_unit := x.gross; v_tsku := x.sku;
    if x.parent_product_id is not null and coalesce(x.pack_factor, 0) > 0 then                       -- 세트로 주문한 줄 — 낱개 행 · 낱개 단가
      v_target := x.parent_product_id; v_unit := round(x.gross / x.pack_factor, 7);
      select p.sku into v_tsku from public.product p where p.id = v_target;
      v_warn := array_append(v_warn, 'latest_set_converted:' || x.sku);
    end if;
    select ps.id, ps.cost, ps.fixed_cost, ps.last_supplied, ps.is_active, coalesce(ps.currency_id, s.currency_id) as cur
      into v_ps from public.product_supplier ps join public.supplier s on s.id = ps.supplier_id where ps.product_id = v_target and ps.supplier_id = v_po.supplier_id;
    if not found then v_warn := array_append(v_warn, 'latest_no_link:' || v_tsku); v_skip := v_skip || jsonb_build_object('sku', v_tsku, 'reason', 'no_link'); continue; end if;
    if v_ps.cur is distinct from x.inv_cur then v_warn := array_append(v_warn, 'latest_currency_mismatch:' || v_tsku); v_skip := v_skip || jsonb_build_object('sku', v_tsku, 'reason', 'currency_mismatch'); continue; end if;
    if v_ps.last_supplied is not null and v_ps.last_supplied > v_r.received_on then v_warn := array_append(v_warn, 'latest_older_skipped:' || v_tsku); v_skip := v_skip || jsonb_build_object('sku', v_tsku, 'reason', 'newer_supply_exists', 'last_supplied', v_ps.last_supplied); continue; end if;
    if v_ps.cost is not distinct from v_unit and v_ps.last_supplied is not distinct from v_r.received_on then v_skip := v_skip || jsonb_build_object('sku', v_tsku, 'reason', 'unchanged'); continue; end if;
    update public.product_supplier set cost = v_unit, last_supplied = v_r.received_on, updated_by = p_staff where id = v_ps.id;
    v_upd := v_upd || (jsonb_build_object('sku', v_tsku, 'product_id', v_target, 'supplier_id', v_po.supplier_id, 'supplier', (select s.name from public.supplier s where s.id = v_po.supplier_id),
                                         'old_cost', v_ps.cost, 'new_cost', v_unit, 'old_last_supplied', v_ps.last_supplied, 'new_last_supplied', v_r.received_on,
                                         'invoice_number', x.invoice_number, 'link_active', v_ps.is_active, 'po_line_no', x.line_no) - v_strip);   -- cost-1a 판정 759: 열쇠 없으면 old_cost · new_cost 가 빠진다
  end loop;
  return jsonb_build_object('updated', v_upd, 'skipped', v_skip, 'warnings', to_jsonb(v_warn));
end $function$;

-- ═══ 착지 — 창구 1 · 재발행 셋 md5 · definer · ACL 그대로(create or replace 는 acl 을 지킨다) · 새 표 · 뷰 · 시퀀스 0 ═══
do $$
declare v_bad text := '';  v_n int;
begin
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_lines_paste') <> 'ce2b79dec5b2a1bc7d5555a611b35acb' then v_bad := v_bad || ' paste_body'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'price_formula_preview') <> 'f77403f8b55aed98e9bbdd77651637e9' then v_bad := v_bad || ' preview_body'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_receipt_latest_apply') <> 'f4b70da785eebb1ccd15bf4a92f81ffa' then v_bad := v_bad || ' latest_apply_body'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_lines_paste', 'price_formula_preview', 'po_receipt_latest_apply', 'product_supplier_costs');
  if v_n <> 4 then v_bad := v_bad || format(' overloads_%s', v_n); end if;
  if (select string_agg(p.proname || ':' || coalesce(p.proacl::text, '-') || ':' || p.prosecdef::text || ':' || p.provolatile::text || ':' || coalesce(array_to_string(p.proconfig, ','), '-'), ' ' order by p.proname)
        from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('po_lines_paste', 'price_formula_preview', 'po_receipt_latest_apply', 'product_supplier_costs'))
     <> 'po_lines_paste:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}:true:v:search_path=public, pg_temp po_receipt_latest_apply:{postgres=X/postgres}:true:v:search_path=public, pg_temp price_formula_preview:{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}:true:s:search_path=public, pg_temp product_supplier_costs:{postgres=X/postgres,authenticated=X/postgres}:true:s:search_path=public, pg_temp'
     then v_bad := v_bad || ' acl_or_security'; end if;
  if has_function_privilege('anon', 'public.product_supplier_costs(uuid[], uuid, boolean)', 'execute') or has_function_privilege('service_role', 'public.product_supplier_costs(uuid[], uuid, boolean)', 'execute') then v_bad := v_bad || ' window_acl'; end if;
  if (select relacl::text from pg_class where oid = 'public.product_supplier'::regclass) <> '{postgres=arwdDxtm/postgres,authenticated=rxtm/postgres,service_role=arwdDxtm/postgres}' then v_bad := v_bad || ' table_acl_changed(1b_is_separate)'; end if;
  if v_bad <> '' then raise exception 'cost-1a landing check failed:%', v_bad; end if;
end $$;
