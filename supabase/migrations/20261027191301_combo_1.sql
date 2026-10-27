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

-- ─────────────────────────────────────────────────────────────
-- combo-1 — 「콤보는 New combo 에서만」 서버 쪽 (Asung-IMS · 2026-10-27 · 판정 810 · 817 ~ 825 · so-module §44 뒤에 적는다)
--   계기: 2026-10-27 Caleb — 재고 13 · 이력 있는 낱개 ABC59138 에 「Make combo」 → 서버는 parent_stock 을 알리기만 했다(막지 않음)
--         「기존 sku 를 이용해서 콤보를 만드는 것은 문제가 있어보여」 · 「콤보 페이지가 있어야 하지 않나?」
--   근거(combo-0 실측 · 테스트 DB 2026-10-27): product_bom 에 쓰는 함수는 product_bom_set 하나(asm-1 20261005192944 · md5 5095ab16…) · authenticated 의 insert 권한 없음 · 정책 select 하나
--         · 적재 ipr_loadBom_(docs/probes/ImsLoadProduct.gs:933 ~ 1005)는 service_role REST upsert — 창구를 거치지 않으므로 막기는 창구에만(표 트리거 아님)
--         · 켜진 콤보 17(cin7 15 · manual 2) · Release 0 · 부모에 이력 있는 콤보 12 · 잔고 ≠ 0 인 콤보 1(UNF18155) — 이미 콤보인 것은 그대로 고친다
--   든 것:
--     ① 도우미 product_bom_check_lines(p_parent_id, p_parent_sku, p_lines, p_blocks, p_warns, p_keys) → {blocks, warns, keys, new}
--        — asm-1 :98 ~ 150(구성품 목록 검사 고리)을 바이트 그대로 옮겼다 · 바뀐 줄 하나 = component_is_parent(:121)가 부모 id 가 없으면(새 SKU) 글자로 견준다
--        · product_bom_set 과 product_combo_create 가 함께 부른다 · 문 없음 · 실행권은 owner 뿐(겉 창구 둘이 문을 든다 · pset-1 product_set_check 선례)
--     ② product_bom_set 재발행 — 바꾼 것 셋: (a) ② 고리 → 도우미 호출 (b) 새 막기 parent_not_combo(판정 817 · 819: 켜진 줄 0 인 SKU 에 줄을 주면 막는다 — 풀린 콤보도 같다)
--        (c) 알림 cin7_combo 삭제(판정 825) · 그 밖의 줄 0(declare 에 v_chk 한 줄 · create → create or replace) · Release(빈 목록)는 그대로
--     ③ product_combo_create(p_item, p_lines, p_commit, p_ack) — 새 SKU 와 구성품을 한 트랜잭션에(판정 818) · 문 ims_require_write('master')
--        · 받지 않는 칸(판정 821): sets · suppliers · family(family_id · family_sku · family · options) → 막기 combo_no_sets · combo_no_suppliers · combo_no_family
--        · 낱개 검사 = product_create_core(p_family_ctx null) 의 막기 22 · 알리기 12 에서 supplier_missing 을 뺀 것 · 구성품 검사 = 도우미(막기 · component_is_set) · 구성품 0 = components_missing
--        · 저장 = core commit → committed false 면 그대로 돌려주고 bom 안 넣음 · 아니면 같은 트랜잭션에서 product_bom insert(source manual · is_active · updated_by)
--        · ack 열쇠 = core 꼴 <SKU>:<code> 와 도우미 꼴 combo:<SKU>:<code>[:<구성품>] 의 합집합(두 창구와 같은 꼴 · 접두가 달라 겹치지 않는다)
--     ④ product_combo_list(p_q, p_only_active, p_include_released, p_limit, p_offset) — invoker · stable · 콤보 부모 한 쪽(구성품 수 · 요약 · released · total)
--        · 검색 = 부모 sku · name ilike 또는 켜진 구성품의 sku · name ilike · limit ≤ 1,000 · released = 줄이 있었는데 전부 꺼짐
--   ⚠️ 표 · 정책 · 권한 무접촉(product_bom 닫힌 채) · product_create · product_create_core · product_list 무접촉(md5 로 확인) · 데이터 0 행 · 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음
--   시험: supabase/tests/combo_1_check.sql(-v mig 로 시험 · 적용 뒤 -v mig 없이 확인)
-- ─────────────────────────────────────────────────────────────

-- ═══ 무접촉 증거(적용 전 md5 · 권한 · 행 수) ═══
create temp table combo1_before as
select (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set') as md5_bom_set,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core') as md5_core,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create') as md5_create,
       (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list') as md5_list,
       (select count(*) from public.product_bom) as n_bom, (select count(*) from public.product_bom where is_active) as n_bom_act,
       (select count(*) from public.product) as n_product;

-- ═══ ① 도우미 product_bom_check_lines — asm-1 :98 ~ 150 바이트 그대로(바뀐 줄 1 = :121 component_is_parent · 새 SKU 는 글자로) · 문 없음 · owner 만 실행 ═══
create function public.product_bom_check_lines(p_parent_id uuid, p_parent_sku text, p_lines jsonb, p_blocks jsonb default '[]'::jsonb, p_warns jsonb default '[]'::jsonb, p_keys text[] default '{}') returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_blocks   jsonb := coalesce(p_blocks, '[]'::jsonb);
  v_warns    jsonb := coalesce(p_warns, '[]'::jsonb);
  v_keys     text[] := coalesce(p_keys, '{}');
  v_par      public.product%rowtype;             -- 부모(고치기 · id 로) · 새 SKU(New combo)면 비어 있다 — 그때 「부모 = 구성품」 은 글자로 견준다
  v_comp     public.product%rowtype;
  v_key      text := 'combo:' || coalesce(trim(p_parent_sku), '');
  v_e        jsonb;
  v_sku      text;
  v_qtxt     text;
  v_qty      numeric;
  v_seen     uuid[] := '{}';
  v_new      jsonb := '[]'::jsonb;            -- 검사를 지난 줄 [{component_id, sku, qty}]
  v_n        int := 0;
begin
  if p_parent_id is not null then
    select * into v_par from public.product p where p.id = p_parent_id;
  end if;

  if p_lines is null or jsonb_typeof(p_lines) <> 'array' then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid', 'sku', coalesce(v_par.sku, trim(p_parent_sku)), 'code', 'lines_invalid', 'message', 'Components must be a list of {sku, qty} — nothing was saved');
  else
    for v_e in select x from jsonb_array_elements(p_lines) x loop
      v_n := v_n + 1;
      if jsonb_typeof(v_e) <> 'object' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid:' || v_n, 'sku', coalesce(v_par.sku, ''), 'code', 'lines_invalid', 'message', format('Component %s is not {sku, qty} — nothing was saved', v_n));
        continue;
      end if;
      v_sku := nullif(trim(v_e->>'sku'), '');
      v_qtxt := trim(coalesce(v_e->>'qty', ''));
      if v_sku is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_unknown:' || v_n, 'sku', '', 'code', 'component_unknown', 'message', format('Component %s has no SKU — nothing was saved', v_n));
        continue;
      end if;
      select * into v_comp from public.product p where p.sku = v_sku;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_unknown:' || v_sku, 'sku', v_sku, 'code', 'component_unknown', 'message', format('Component %s does not exist — nothing was saved', v_sku));
        continue;
      end if;
      if not v_comp.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_inactive:' || v_sku, 'sku', v_sku, 'code', 'component_inactive', 'message', format('Component %s is inactive — nothing was saved', v_sku));
      end if;
      if (v_par.id is not null and v_comp.id = v_par.id) or (v_par.id is null and v_comp.sku = trim(p_parent_sku)) then   -- combo-1: 부모 id 가 없으면(New combo 의 새 SKU) 글자로 견준다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_is_parent:' || v_sku, 'sku', v_sku, 'code', 'component_is_parent', 'message', format('Combo %s cannot contain itself — nothing was saved', v_sku));
      end if;
      if exists (select 1 from public.product_bom b where b.parent_product_id = v_comp.id and b.is_active) then           -- 묶음 1: 콤보 안의 콤보
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_is_combo:' || v_sku, 'sku', v_sku, 'code', 'component_is_combo', 'message', format('Component %s is itself a combo — a combo cannot contain a combo — nothing was saved', v_sku));
      end if;
      if v_comp.id = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_duplicate_in_call:' || v_sku, 'sku', v_sku, 'code', 'component_duplicate_in_call', 'message', format('Component %s is listed twice — give it once with the total qty — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := array_append(v_seen, v_comp.id);
      if v_qtxt !~ '^[0-9]+(\.[0-9]+)?$' then                                                                    -- 글자 검사 먼저 — SQL 의 or 는 짧게 끊지 않아 'abc'::numeric 이 먼저 터진다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':quantity_invalid:' || v_sku, 'sku', v_sku, 'code', 'quantity_invalid', 'message', format('Component %s needs a qty above 0 (got "%s") — nothing was saved', v_sku, v_qtxt));
        continue;
      end if;
      if v_qtxt::numeric <= 0 then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':quantity_invalid:' || v_sku, 'sku', v_sku, 'code', 'quantity_invalid', 'message', format('Component %s needs a qty above 0 (got "%s") — nothing was saved', v_sku, v_qtxt));
        continue;
      end if;
      v_qty := round(v_qtxt::numeric, 6);
      if v_comp.parent_product_id is not null then                                                                  -- ⬜ 세트를 구성품으로 — 막지 않는다 · 알린다(오더 길이 coalesce(parent, id) × pack_factor 로 낱개로 접는다)
        v_warns := v_warns || jsonb_build_object('key', v_key || ':component_is_set:' || v_sku, 'sku', v_sku, 'code', 'component_is_set', 'message', format('Component %s is a set (pack of %s) — the order will take %s × %s singles of its base product', v_sku, coalesce(v_comp.pack_factor::text, '?'), v_qty, coalesce(v_comp.pack_factor::text, '?')));
        v_keys := array_append(v_keys, v_key || ':component_is_set:' || v_sku);
      end if;
      v_new := v_new || jsonb_build_object('component_id', v_comp.id, 'sku', v_comp.sku, 'qty', v_qty);
    end loop;
    if jsonb_array_length(v_new) = 1 and jsonb_array_length(v_blocks) = 0 then                                   -- ⬜ 정본 「구성품 2 개 이상」(po-module 504 · 511) — IMS 만들기에도 건다
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':component_single', 'sku', coalesce(v_par.sku, ''), 'code', 'component_single', 'message', format('A combo needs at least two components (%s has one) — one component with a qty is a set, not a combo — nothing was saved', coalesce(v_par.sku, trim(p_parent_sku))));
    end if;
  end if;
  return jsonb_build_object('blocks', v_blocks, 'warns', v_warns, 'keys', to_jsonb(v_keys), 'new', v_new);
end;
$$;
revoke all on function public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[]) from public, anon, authenticated, service_role;
comment on function public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[]) is
  'combo-1(2026-10-27 · 판정 818) — 콤보 구성품 목록 검사 고리(asm-1 product_bom_set :98 ~ 150 바이트 그대로 · component_is_parent 만 새 SKU 글자도 본다) · product_bom_set 과 product_combo_create 가 함께 쓴다 · p_parent_id 가 null 이면 새 SKU(p_parent_sku) · p_blocks · p_warns · p_keys 는 부르는 쪽이 모은 것(이어 붙여 돌려준다) → {blocks, warns, keys, new[{component_id, sku, qty}]} · 문 없음 — 겉 창구가 든다 · owner 만 실행';

-- ═══ ② product_bom_set 재발행 — asm-1 :41 ~ 243 바이트 그대로 + 바꾼 것 셋(도우미 호출 · parent_not_combo · cin7_combo 삭제) ═══

create or replace function public.product_bom_set(p_parent_sku text, p_lines jsonb, p_old jsonb default null, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_par      public.product%rowtype;
  v_comp     public.product%rowtype;
  v_key      text;
  v_e        jsonb;
  v_sku      text;
  v_qtxt     text;
  v_qty      numeric;
  v_seen     uuid[] := '{}';
  v_new      jsonb := '[]'::jsonb;            -- 검사를 지난 줄 [{component_id, sku, qty}]
  v_n        int := 0;
  v_cur_txt  text;                             -- 지금 켜진 줄 「sku|수량,…」(sku 순)
  v_old_txt  text;                             -- p_old 를 같은 모양으로
  v_new_txt  text;
  v_cur_n    int := 0;
  v_cin7_n   int := 0;
  v_cnt      bigint;
  v_stock    numeric;
  v_r        record;
  v_added    int := 0;  v_changed int := 0;  v_removed int := 0;  v_kept int := 0;
  v_chk      jsonb;                            -- combo-1: 도우미 product_bom_check_lines 의 반환
begin
  perform public.ims_require_write('master', 'saved');                                                              -- ⭐ 유일한 문 — 첫 줄(판정 140 · product_update 와 같다)
  v_staff := public.so_current_staff();
  v_key := 'combo:' || coalesce(trim(p_parent_sku), '');

  -- ① 부모
  if nullif(trim(p_parent_sku), '') is null then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', p_parent_sku, 'code', 'parent_unknown', 'message', 'Combo SKU is missing — nothing was saved');
  else
    select * into v_par from public.product p where p.sku = trim(p_parent_sku);
    if not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', trim(p_parent_sku), 'code', 'parent_unknown', 'message', format('SKU %s does not exist — nothing was saved', trim(p_parent_sku)));
    else
      if not v_par.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_inactive', 'sku', v_par.sku, 'code', 'parent_inactive', 'message', format('SKU %s is inactive — turn it on before making it a combo — nothing was saved', v_par.sku));
      end if;
      if v_par.parent_product_id is not null then                                                                   -- ⬜ 세트는 콤보가 못 된다 — 세트는 한 상품의 묶음 단위(pack_factor)라 구성품을 두 번 세게 된다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_is_set', 'sku', v_par.sku, 'code', 'parent_is_set', 'message', format('SKU %s is a set (pack of %s) — a set cannot also be a combo — nothing was saved', v_par.sku, coalesce(v_par.pack_factor::text, '?')));
      end if;
      select count(*) into v_cnt from public.product_bom b where b.component_product_id = v_par.id and b.is_active;
      if v_cnt > 0 then                                                                                             -- 묶음 1: 콤보 안에 콤보는 안 된다 — 다른 콤보의 구성품인 상품은 콤보가 못 된다
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_is_component', 'sku', v_par.sku, 'code', 'parent_is_component', 'message', format('SKU %s is a component of %s other combo(s) — a combo cannot contain a combo — nothing was saved', v_par.sku, v_cnt));
      end if;
    end if;
  end if;

  -- ② 구성품 목록(전체) — 모양 · 하나씩 · combo-1: 도우미 product_bom_check_lines(product_combo_create 와 함께 쓴다 · 본문은 asm-1 :98 ~ 150 그대로)
  v_chk := public.product_bom_check_lines(v_par.id, p_parent_sku, p_lines, v_blocks, v_warns, v_keys);
  v_blocks := v_chk->'blocks';  v_warns := v_chk->'warns';  v_new := v_chk->'new';
  select coalesce(array_agg(x), '{}') into v_keys from jsonb_array_elements_text(v_chk->'keys') as x;

  if v_par.id is null then
    return jsonb_build_object('committed', false, 'parent_sku', trim(p_parent_sku), 'parent_id', null, 'changes', '[]'::jsonb, 'components', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', '[]'::jsonb);
  end if;

  -- ③ 지금 줄 · 옛 목록 대조(화면이 본 것과 같은가) · 바뀐 것이 있는가
  select count(*), count(*) filter (where b.source = 'cin7'),
         coalesce(string_agg(c.sku || '|' || round(b.quantity, 6)::text, ',' order by c.sku), '')
    into v_cur_n, v_cin7_n, v_cur_txt
    from public.product_bom b join public.product c on c.id = b.component_product_id
   where b.parent_product_id = v_par.id and b.is_active;
  if v_cur_n = 0 and jsonb_typeof(p_lines) = 'array' and jsonb_array_length(p_lines) > 0 then                         -- combo-1 판정 817 · 819: 콤보가 아니던 SKU(풀린 콤보 포함)에 줄을 주면 이유를 묻지 않고 막는다 — 콤보는 Combos → New combo 에서만 태어난다
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_not_combo', 'sku', v_par.sku, 'code', 'parent_not_combo', 'message', format('%s is not a combo — make a new combo SKU in Combos → New combo — nothing was saved', v_par.sku));
  end if;
  select coalesce(string_agg(x->>'sku' || '|' || round((x->>'qty')::numeric, 6)::text, ',' order by x->>'sku'), '') into v_new_txt from jsonb_array_elements(v_new) x;
  if p_old is null then
    if v_cur_n > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'sku', v_par.sku, 'code', 'old_missing', 'message', format('Combo %s: the component list the screen saw is missing — reload and try again — nothing was saved', v_par.sku));
    end if;
  elsif jsonb_typeof(p_old) <> 'array' then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'sku', v_par.sku, 'code', 'old_missing', 'message', format('Combo %s: the old component list must be a list of {sku, qty} — nothing was saved', v_par.sku));
  else
    begin
      select coalesce(string_agg(trim(x->>'sku') || '|' || round((x->>'qty')::numeric, 6)::text, ',' order by trim(x->>'sku')), '') into v_old_txt from jsonb_array_elements(p_old) x;
    exception when others then
      v_old_txt := '<unreadable>';
    end;
    if v_old_txt <> v_cur_txt then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'sku', v_par.sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the components of %s (now %s) — check again — nothing was saved', v_par.sku, case when v_cur_txt = '' then '(none)' else replace(v_cur_txt, '|', ' × ') end));
    end if;
  end if;
  if jsonb_array_length(v_blocks) = 0 and v_new_txt = v_cur_txt then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':no_change', 'sku', v_par.sku, 'code', 'no_change', 'message', format('Combo %s already has exactly these components — nothing to change — nothing was saved', v_par.sku));
  end if;

  -- ④ 알리기(ack) — 열린 오더 · 부모 장부(cin7_combo 는 combo-1 에서 뺐다)
  select count(distinct l.so_id) into v_cnt from public.so_line l join public.so s on s.id = l.so_id where l.product_id = v_par.id and s.status not in ('fulfilled', 'cancelled');
  if v_cnt > 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':open_orders', 'sku', v_par.sku, 'code', 'open_orders', 'message', format('%s open order(s) carry combo %s — they keep the components they were made with', v_cnt, v_par.sku));
    v_keys := array_append(v_keys, v_key || ':open_orders');
  end if;
  select coalesce(sum(b.qty), 0) into v_stock from public.ims_inv_balance b where b.product_id = v_par.id;
  if v_stock <> 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':parent_stock', 'sku', v_par.sku, 'code', 'parent_stock', 'message', format('Combo %s has %s in the books — combos are not kept in stock (they are made when an order ships) — adjust it out', v_par.sku, round(v_stock)));
    v_keys := array_append(v_keys, v_key || ':parent_stock');
  end if;
  -- combo-1 판정 825: 알림 cin7_combo 삭제(Cin7 을 주체로 쓰지 않는다 · 적재는 manual 줄을 보내지 않는다 — ImsLoadProduct.gs ipr_loadBom_ :939 · :958)

  -- ⑤ 변경 목록(미리 보기에도 준다)
  for v_r in
    select coalesce(n.sku, c.sku) as sku, n.qty as new_qty, case when b.is_active then b.quantity end as old_qty, n.component_id as new_id, b.component_product_id as old_id
      from (select (x->>'component_id')::uuid as component_id, x->>'sku' as sku, (x->>'qty')::numeric as qty from jsonb_array_elements(v_new) x) n
      full join (select b.* from public.product_bom b where b.parent_product_id = v_par.id and b.is_active) b on b.component_product_id = n.component_id
      left join public.product c on c.id = b.component_product_id
     order by 1
  loop
    if v_r.old_id is null then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'added', 'qty', v_r.new_qty, 'old_qty', null); v_added := v_added + 1;
    elsif v_r.new_id is null then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'removed', 'qty', null, 'old_qty', v_r.old_qty); v_removed := v_removed + 1;
    elsif v_r.new_qty <> v_r.old_qty then v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'changed', 'qty', v_r.new_qty, 'old_qty', v_r.old_qty); v_changed := v_changed + 1;
    else v_changes := v_changes || jsonb_build_object('sku', v_r.sku, 'action', 'unchanged', 'qty', v_r.new_qty, 'old_qty', v_r.old_qty); v_kept := v_kept + 1;
    end if;
  end loop;

  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'parent_sku', v_par.sku, 'parent_id', v_par.id, 'changes', v_changes,
                              'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb) from public.product_bom b join public.product c on c.id = b.component_product_id where b.parent_product_id = v_par.id and b.is_active),
                              'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ⑥ 저장 — 옛 줄과 새 목록을 견줘 더하기 · 수량 바꾸기 · 되살리기 · 끄기(지우지 않는다) · 손댄 줄은 source manual(판정 132 · prod-5 「IMS 가 고친 칸」 줄기)
  for v_r in select (x->>'component_id')::uuid as component_id, (x->>'qty')::numeric as qty from jsonb_array_elements(v_new) x loop
    update public.product_bom b
       set quantity = v_r.qty, is_active = true, source = 'manual', updated_by = v_staff
     where b.parent_product_id = v_par.id and b.component_product_id = v_r.component_id
       and (not b.is_active or b.quantity <> v_r.qty);                                                                   -- 그대로인 줄은 건드리지 않는다(cin7 표시도 그대로)
    if not found and not exists (select 1 from public.product_bom b where b.parent_product_id = v_par.id and b.component_product_id = v_r.component_id) then
      insert into public.product_bom (parent_product_id, component_product_id, quantity, source, is_active, updated_by)
      values (v_par.id, v_r.component_id, v_r.qty, 'manual', true, v_staff);
    end if;
  end loop;
  update public.product_bom b
     set is_active = false, source = 'manual', updated_by = v_staff
   where b.parent_product_id = v_par.id and b.is_active
     and not (b.component_product_id = any(coalesce((select array_agg((x->>'component_id')::uuid) from jsonb_array_elements(v_new) x), '{}'::uuid[])));

  return jsonb_build_object('committed', true, 'parent_sku', v_par.sku, 'parent_id', v_par.id, 'changes', v_changes,
                            'added', v_added, 'changed', v_changed, 'removed', v_removed, 'unchanged', v_kept,
                            'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb) from public.product_bom b join public.product c on c.id = b.component_product_id where b.parent_product_id = v_par.id and b.is_active),
                            'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.product_bom_set(text, jsonb, jsonb, boolean, text[]) from public, anon;
grant execute on function public.product_bom_set(text, jsonb, jsonb, boolean, text[]) to authenticated;
comment on function public.product_bom_set(text, jsonb, jsonb, boolean, text[]) is
  'asm-1(판정 244 · asm 묶음 1) · combo-1(판정 817 · 819 · 825): change the components of an existing combo — the whole component list [{sku, qty}] for one combo SKU · a SKU that is not a combo (0 active rows · released ones too) is refused with parent_not_combo — new combos are born only in product_combo_create · p_old = the list the screen saw (changed_elsewhere when it differs) · preview with p_commit=false, save with true · blocks: parent_unknown · parent_inactive · parent_is_set · parent_is_component · parent_not_combo · lines_invalid · component_unknown · component_inactive · component_is_parent · component_is_combo · component_duplicate_in_call · quantity_invalid · component_single · old_missing · changed_elsewhere · no_change · warnings (ack keys combo:<sku>:<code>): component_is_set · open_orders · parent_stock · empty list = release (rows turned off, never deleted · cannot be undone) · touched rows become source manual · master only';

-- ═══ ③ product_combo_create — 새 콤보 = 새 SKU + 구성품을 한 트랜잭션에(판정 818 · 821) ═══
create function public.product_combo_create(p_item jsonb, p_lines jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_sku      text;
  v_key      text;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_keys     text[] := '{}';
  v_unacked  text[] := '{}';
  v_chk      jsonb;
  v_core     jsonb;
  v_new      jsonb := '[]'::jsonb;            -- 도우미를 지난 구성품 [{component_id, sku, qty}]
  v_w        jsonb;
  v_x        jsonb;
  v_pid      uuid;
  v_r        record;
  v_n        int := 0;
  v_preview  jsonb;
begin
  perform public.ims_require_write('master', 'saved');                                                              -- ⭐ 유일한 문 — 첫 줄(판정 140 · product_create · product_bom_set 과 같다)
  v_staff := public.so_current_staff();
  if p_item is null or jsonb_typeof(p_item) <> 'object' then
    raise exception 'p_item must be a JSON object {sku, name, brand_id, category_id, unit_id, barcodes[], prices[{tier_id, price}]} — nothing was saved';
  end if;
  v_sku := trim(coalesce(p_item->>'sku', ''));
  v_key := 'combo:' || v_sku;

  -- ① 받지 않는 칸(판정 821) — 세트(콤보는 재고가 없다 · product_set_add 도 parent_is_combo 로 막는다) · 공급처(콤보는 사 오지 않는다) · 가족(콤보는 변형이 아니다)
  v_x := p_item->'sets';
  if v_x is not null and jsonb_typeof(v_x) <> 'null' and not (jsonb_typeof(v_x) = 'array' and jsonb_array_length(v_x) = 0) then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':combo_no_sets', 'sku', v_sku, 'code', 'combo_no_sets', 'message', format('Combo %s cannot have sets — a combo has no stock of its own — nothing was saved', v_sku));
  end if;
  v_x := p_item->'suppliers';
  if v_x is not null and jsonb_typeof(v_x) <> 'null' and not (jsonb_typeof(v_x) = 'array' and jsonb_array_length(v_x) = 0) then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':combo_no_suppliers', 'sku', v_sku, 'code', 'combo_no_suppliers', 'message', format('Combo %s cannot have suppliers — a combo is not bought, its components are — nothing was saved', v_sku));
  end if;
  if nullif(trim(coalesce(p_item->>'family_id', '')), '') is not null or nullif(trim(coalesce(p_item->>'family_sku', '')), '') is not null
     or (p_item->'family' is not null and jsonb_typeof(p_item->'family') <> 'null')
     or (p_item->'options' is not null and jsonb_typeof(p_item->'options') <> 'null' and not (jsonb_typeof(p_item->'options') = 'array' and jsonb_array_length(p_item->'options') = 0)) then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':combo_no_family', 'sku', v_sku, 'code', 'combo_no_family', 'message', format('Combo %s cannot be a family variant — leave family and options out — nothing was saved', v_sku));
  end if;

  -- ② 구성품 — 도우미(부모 id 없음 · 새 SKU 글자) · 막기 · component_is_set 알림 · 구성품 0 은 막는다(구성품 없는 SKU 가 생기면 콤보가 아니라 낱개다)
  v_chk := public.product_bom_check_lines(null, v_sku, p_lines, v_blocks, v_warns, v_keys);
  v_blocks := v_chk->'blocks';  v_warns := v_chk->'warns';  v_new := v_chk->'new';
  select coalesce(array_agg(x), '{}') into v_keys from jsonb_array_elements_text(v_chk->'keys') as x;
  if jsonb_array_length(v_new) = 0 and jsonb_array_length(v_blocks) = 0 then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':components_missing', 'sku', v_sku, 'code', 'components_missing', 'message', format('Combo %s needs at least two components — nothing was saved', v_sku));
  end if;
  v_preview := (select coalesce(jsonb_agg(jsonb_build_object('sku', x->>'sku', 'qty', (x->>'qty')::numeric) order by x->>'sku'), '[]'::jsonb) from jsonb_array_elements(v_new) x);

  -- ③ 낱개 검사 — product_create_core 미리 보기(p_family_ctx null · prod-3 와 같은 규칙) · 알림에서 supplier_missing 을 뺀다(판정 821)
  v_core := public.product_create_core(jsonb_build_array(p_item), null, false, '{}');
  v_blocks := v_blocks || coalesce(v_core->'blocks', '[]'::jsonb);
  for v_w in select x from jsonb_array_elements(coalesce(v_core->'warnings', '[]'::jsonb)) as x loop
    if v_w->>'code' = 'supplier_missing' then continue; end if;
    v_warns := v_warns || v_w;
    v_keys := array_append(v_keys, v_w->>'key');
  end loop;

  -- ④ 판정 — 막기 있음 → 저장 안 함 · 검사만 → 반환 · 확인 안 받은 경고 → 저장 안 함(판정 176 · product_create · product_bom_set 과 같은 꼴)
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'sku', v_sku, 'product_id', null, 'items', '[]'::jsonb, 'components', v_preview,
                              'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ⑤ 저장 — 낱개(core · 바코드 · 가격 · 한 트랜잭션 · 23505 는 core 가 문장으로) → 구성품 줄 · 둘 다 되거나 둘 다 안 된다(판정 818)
  v_core := public.product_create_core(jsonb_build_array(p_item), null, true, coalesce(p_ack, '{}') || (v_sku || ':supplier_missing'));   -- core 의 supplier_missing 은 콤보에 뜻이 없다 — 여기서만 확인된 것으로 친다
  if not coalesce((v_core->>'committed')::boolean, false) then                                                      -- 저장 직전 재검사에서 막혔다(있을 수 없지만 — 있으면 그대로 돌려주고 bom 은 넣지 않는다)
    return v_core || jsonb_build_object('sku', v_sku, 'product_id', null, 'components', v_preview);
  end if;
  v_pid := (v_core->'items'->0->>'product_id')::uuid;
  for v_r in select (x->>'component_id')::uuid as component_id, (x->>'qty')::numeric as qty from jsonb_array_elements(v_new) x loop
    insert into public.product_bom (parent_product_id, component_product_id, quantity, source, is_active, updated_by)
    values (v_pid, v_r.component_id, v_r.qty, 'manual', true, v_staff);
    v_n := v_n + 1;
  end loop;
  return jsonb_build_object('committed', true, 'sku', v_sku, 'product_id', v_pid, 'items', v_core->'items', 'added', v_n,
                            'components', (select coalesce(jsonb_agg(jsonb_build_object('sku', c.sku, 'qty', b.quantity) order by c.sku), '[]'::jsonb) from public.product_bom b join public.product c on c.id = b.component_product_id where b.parent_product_id = v_pid and b.is_active),
                            'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.product_combo_create(jsonb, jsonb, boolean, text[]) from public, anon, service_role;
grant execute on function public.product_combo_create(jsonb, jsonb, boolean, text[]) to authenticated;
comment on function public.product_combo_create(jsonb, jsonb, boolean, text[]) is
  'combo-1(2026-10-27 · 판정 810 · 817 · 818 · 821) — New combo: a new combo SKU and its components in one transaction (both or neither) · p_item {sku, name, brand_id, category_id, unit_id, barcodes[], prices[{tier_id, price}], weight, weight_unit, note} (sets · suppliers · family/options are refused: combo_no_sets · combo_no_suppliers · combo_no_family) · p_lines = the whole component list [{sku, qty}] (2 or more · components_missing · component_single) · single-product checks = product_create_core (blocks 22 · warnings minus supplier_missing) · component checks = product_bom_check_lines (shared with product_bom_set) · preview with p_commit=false, save with true · ack keys <sku>:<code> (product) and combo:<sku>:<code>[:<component>] (components) · master only · the only way a combo is born (product_bom_set refuses parent_not_combo)';

-- ═══ ④ product_combo_list — Combos 화면의 넓은 목록 한 쪽(invoker · RLS 가 거른다) ═══
create function public.product_combo_list(p_q text default null, p_only_active boolean default true, p_include_released boolean default false, p_limit int default 200, p_offset int default 0)
returns table (id uuid, sku text, name text, is_active boolean, component_count int, components text, released boolean, total bigint)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
declare
  v_q      text := nullif(btrim(p_q), '');
  v_limit  int  := least(greatest(coalesce(p_limit, 200), 1), 1000);
  v_offset int  := greatest(coalesce(p_offset, 0), 0);
begin
  return query
  with par as (
    select b.parent_product_id as pid,
           (count(*) filter (where b.is_active))::int as n_act,
           string_agg(c.sku || ' × ' || trim_scale(b.quantity)::text, ', ' order by c.sku) filter (where b.is_active) as comps,
           bool_or(b.is_active and (v_q is null or c.sku ilike '%' || v_q || '%' or c.name ilike '%' || v_q || '%')) as comp_hit
      from public.product_bom b join public.product c on c.id = b.component_product_id
     group by b.parent_product_id)
  select p.id, p.sku, p.name, p.is_active, par.n_act, coalesce(par.comps, ''), par.n_act = 0, count(*) over () as total
    from par join public.product p on p.id = par.pid
   where (par.n_act > 0 or p_include_released)
     and (not p_only_active or p.is_active)
     and (v_q is null or p.sku ilike '%' || v_q || '%' or p.name ilike '%' || v_q || '%' or par.comp_hit)
   order by p.sku, p.id
   limit v_limit offset v_offset;
end $$;
revoke all on function public.product_combo_list(text, boolean, boolean, int, int) from public, anon, service_role;
grant execute on function public.product_combo_list(text, boolean, boolean, int, int) to authenticated;
comment on function public.product_combo_list(text, boolean, boolean, int, int) is
  'combo-1(2026-10-27 · 판정 810 · 822) — one page of combo parents for the Combos screen · row = product that has component rows: id · sku · name · is_active · component_count (active rows) · components ("SKU × qty, …") · released (rows exist but none active · shown only with p_include_released) · total (window) · p_q matches the combo sku/name or an active component sku/name · p_only_active = parent product on · limit ≤ 1000 · invoker (RLS) · authenticated';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int; v_b record; v_src text;
begin
  select * into v_b from combo1_before;
  if v_b.md5_bom_set <> '5095ab16f3e72f6222dab75775294d0e' then v_bad := v_bad || ' bom_set_before_not_asm1'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create_core') is distinct from v_b.md5_core
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_create') is distinct from v_b.md5_create
     or (select md5(p.prosrc) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_list') is distinct from v_b.md5_list then v_bad := v_bad || ' core_create_list_changed'; end if;
  if to_regprocedure('public.product_bom_check_lines(uuid, text, jsonb, jsonb, jsonb, text[])') is null or to_regprocedure('public.product_combo_create(jsonb, jsonb, boolean, text[])') is null
     or to_regprocedure('public.product_combo_list(text, boolean, boolean, int, int)') is null or to_regprocedure('public.product_bom_set(text, jsonb, jsonb, boolean, text[])') is null then v_bad := v_bad || ' functions_missing'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('product_bom_check_lines', 'product_combo_create', 'product_combo_list', 'product_bom_set');
  if v_n <> 4 then v_bad := v_bad || format(' overloads_%s_of_4', v_n); end if;
  if coalesce((select p.proacl::text from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_check_lines'), '-') <> '{postgres=X/postgres}' then v_bad := v_bad || ' helper_acl'; end if;
  if not has_function_privilege('authenticated', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute') or has_function_privilege('anon', 'public.product_combo_create(jsonb, jsonb, boolean, text[])', 'execute')
     or not has_function_privilege('authenticated', 'public.product_combo_list(text, boolean, boolean, int, int)', 'execute') or has_function_privilege('anon', 'public.product_combo_list(text, boolean, boolean, int, int)', 'execute')
     or not has_function_privilege('authenticated', 'public.product_bom_set(text, jsonb, jsonb, boolean, text[])', 'execute') or has_function_privilege('anon', 'public.product_bom_set(text, jsonb, jsonb, boolean, text[])', 'execute') then v_bad := v_bad || ' window_acl'; end if;
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_bom_set';
  if v_src !~ 'code., .parent_not_combo' or v_src ~ 'code., .cin7_combo' or v_src !~ 'public\.product_bom_check_lines\(' or v_src ~ 'for v_e in select x from jsonb_array_elements\(p_lines\)' then v_bad := v_bad || ' bom_set_body'; end if;
  select p.prosrc into v_src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_create';
  if v_src !~ 'public\.product_bom_check_lines\(' or v_src !~ 'public\.product_create_core\(' or v_src !~ 'supplier_missing' or v_src !~ 'insert into public\.product_bom' then v_bad := v_bad || ' combo_create_body'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prosecdef and p.proconfig::text ~ 'search_path=public, pg_temp' and p.proname in ('product_bom_check_lines', 'product_combo_create', 'product_bom_set');
  if v_n <> 3 then v_bad := v_bad || format(' definer_%s_of_3', v_n); end if;
  if (select p.prosecdef from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'product_combo_list') then v_bad := v_bad || ' list_not_invoker'; end if;
  if has_table_privilege('authenticated', 'public.product_bom', 'insert') or has_table_privilege('authenticated', 'public.product_bom', 'update') or has_table_privilege('authenticated', 'public.product_bom', 'delete') then v_bad := v_bad || ' product_bom-opened'; end if;
  if (select count(*) from pg_policies where schemaname = 'public' and tablename = 'product_bom') <> 1 then v_bad := v_bad || ' policies'; end if;
  if (select count(*) from public.product_bom) <> v_b.n_bom or (select count(*) from public.product_bom where is_active) <> v_b.n_bom_act or (select count(*) from public.product) <> v_b.n_product then v_bad := v_bad || ' data_changed'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM817', message = format('STOP - combo-1 did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
drop table combo1_before;
