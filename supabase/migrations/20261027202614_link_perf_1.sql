-- link-perf-1 — shop_link_plan 이 실제 스토어(asung · 5,079 상품 · 8,869 변형)에서 31 s(authenticated 시한 8 s 초과 · 「canceling statement due to statement timeout」) → 집합 한 번 + 색인 하나로 (2026-10-27 · 판정 555 ~ 558 · 562 · 815 · 지시서 ~/asung/prompts/link-perf-1.md)
--   실측(테스트 DB · 2b81c902 · pg_temp 복사본에 시계를 꽂아): 총 30.3 s = ① 변형마다 IMS 제품 찾기 19.0 s(정확히 못 찾은 448 변형마다 lower(sku) 로 product 18,744 행 전체 훑기 — 색인이 upper(sku) 뿐) + ② 같은 SKU 둘 8.1 s(줄마다 t_link_sku 8,869 행 훑기) + 나머지 3 s(모양 0.5 · 이어진 것 0.6 · 사진 0.8 · 줄마다 update 1.0)
--   고침(안 ① 빠르게 · 결과 한 글자도 같게 — 고리와 판정 순서는 그대로 두고 비싼 조회만 집합으로):
--     · t_link_var: 변형 ↔ IMS 제품 짝을 한 문장으로(정확히 = product.sku · 없으면 lower(sku) 가 같은 것 가운데 order by sku limit 1 — 옛 판과 같은 고르기) · (item_id, ord) 색인 · with ordinality 로 변형 순서 보존
--     · t_link_dup: 두 번 이상 나온 SKU 집합을 한 번 · 줄마다는 = any(v_skus) 로 작은 표만 본다
--     · 사진: exists + count 두 번 → t_link_img(제품 · family 단위 활성 사진 수를 한 문장으로) 에서 읽기(0 이면 no_ims_images · 같은 조건)
--     · t_link_itm: 줄마다 셈하던 family 모양 · Shopify 옵션 이름을 집합으로(같은 식 · 같은 순서) · 표시 inactive · discontinued 는 t_link_var 의 칸으로(조회 0) · ⑤ 는 이 스토어에 shop_product · shop_variant 가 하나도 없으면 건너뛴다(네 조회가 전부 거짓 — 결과 같음)
--     · 모양 ④: 첫 제품의 family · parent · sellable 을 t_link_var 에서(옛 판은 product 를 다시 읽었다) · 이어진 것 ⑤: 「is not distinct from」 둘 → family / product 두 갈래(유니크 색인 · target_ck 로 같은 뜻 · apply 뒤 shop_product 가 5 천 행일 때 다시 느려지는 함정 막기)
--     · 판정은 t_link_res 에 모아 update … from 한 번(줄마다 5,079 번 → 1 번 · 같은 칸 · 같은 updated_by · ims_touch 는 행마다 그대로)
--     · 색인 product_sku_lower_idx (lower(sku), sku): plan · apply 의 lower(sku) 되찾기가 색인을 탄다(18,744 행 · 만들기 ≪ 1 s · 이 마이그레이션 안에서 짧게 잠근다)
--   바꾸지 않은 것: 시그니처 · 문(ims_require_write) · 상태 검사 · 판정 규칙 · 순서(handle, gid) · version +1 · 반환 모양 · shop_link_apply(무접촉 · 판정 815) · 화면(ss v4 그대로 — rpc shop_link_plan 한 번)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261027202614_link_perf_1.sql && supabase migration repair --status applied 20261027202614 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027202614_link_perf_1.sql -f supabase/tests/link_perf_1.sql
do $$
begin
  if coalesce((select value from public.inv_config where key = 'db_role'), '') <> 'test' then
    raise exception using errcode = 'WM501', message = 'STOP - inv_config.db_role is not test - this migration runs on the Asung-IMS project only. Nothing was changed.';
  end if;
end $$;

-- ═══ 1) 색인 — lower(sku) 되찾기(plan · apply 둘 다 쓴다 · upper 색인은 있었고 lower 는 없었다) ═══
create index if not exists product_sku_lower_idx on public.product (lower(sku), sku);
comment on index public.product_sku_lower_idx is 'link-perf-1: shop_link_plan · shop_link_apply 의 「대소문자만 다른 SKU」 되찾기(lower(p.sku) = lower(x) order by p.sku limit 1) — 없으면 변형마다 전체 훑기(실측 448 회 = 19 s)';

-- ═══ 2) shop_link_plan 재발행 — 같은 판정 · 집합 한 번 ═══
create or replace function public.shop_link_plan(p_run_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_run     public.shop_link_run%rowtype;
  v_s       public.shop_store%rowtype;
  it        record;
  vr        record;
  v_n       int := 0;
  v_dec     text;
  v_reasons text[];
  v_fam     uuid;
  v_prod    uuid;
  v_changes jsonb;
  v_skus    text[];
  v_pids    uuid[];
  v_fams    uuid[];
  v_missing text[];
  v_case    text[];
  v_members text[];
  v_to_add  text[];
  v_opt_sh  text[];
  v_opt_ims text[];
  v_p       public.product%rowtype;
  v_f       public.product_family%rowtype;
  v_sp      public.shop_product%rowtype;
  v_cnt     int;
  v_famshape boolean;
  v_counts  jsonb;
  v_reason_counts jsonb;
  v_img_n   int;
  v_p1_fam  uuid;
  v_p1_par  uuid;
  v_p1_sell boolean;
  v_any_inactive boolean;
  v_any_disc boolean;
  v_has_sp  boolean;
  v_has_sv  boolean;
begin
  perform public.ims_require_write('shopify', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_run from public.shop_link_run where id = p_run_id for update;
  if not found then raise exception 'Link run % not found — nothing was saved', p_run_id; end if;
  if v_run.status not in ('read', 'planned') then
    raise exception 'Link run % is % — a plan needs a run whose Shopify read has finished (read) and that is not applied yet — nothing was saved', p_run_id, v_run.status;
  end if;
  select * into v_s from public.shop_store where id = v_run.store_id;

  -- SKU 가 판 안에서 몇 번 나오나(같은 상품 안 둘 · 다른 상품에 또 하나 — 둘 다 dup) · 빈 SKU 는 세지 않는다
  -- link-perf-1: 변형 ↔ IMS 제품 짝을 집합 한 번으로(옛 판은 변형마다 select · 없으면 lower(sku) 전체 훑기 = 5,079 상품에서 19 s) · 같은 SKU 둘은 한 번 센다(옛 판은 줄마다 8,869 행 훑기 = 8 s) · 판정은 모았다가 한 번에 적는다
  create temp table if not exists t_link_var (item_id uuid, ord int, sku text, pid uuid, p_family_id uuid, p_parent uuid, p_sellable boolean, p_is_active boolean, p_is_discontinued boolean, case_diff boolean) on commit drop;
  truncate t_link_var;
  insert into t_link_var (item_id, ord, sku, pid, p_family_id, p_parent, p_sellable, p_is_active, p_is_discontinued, case_diff)
  select x.item_id, x.ord, x.sku, coalesce(pe.id, pl.id), coalesce(pe.family_id, pl.family_id), coalesce(pe.parent_product_id, pl.parent_product_id), coalesce(pe.sellable, pl.sellable), coalesce(pe.is_active, pl.is_active), coalesce(pe.is_discontinued, pl.is_discontinued), (pe.id is null and pl.id is not null)
    from (select i.id as item_id, v.ord, nullif(trim(v.val->>'sku'), '') as sku
            from public.shop_link_item i cross join lateral jsonb_array_elements(i.variants) with ordinality v(val, ord) where i.run_id = p_run_id) x
    left join public.product pe on pe.sku = x.sku                                                   -- 정확히
    left join lateral (select p.id, p.family_id, p.parent_product_id, p.sellable, p.is_active, p.is_discontinued from public.product p
                        where pe.id is null and x.sku is not null and lower(p.sku) = lower(x.sku) order by p.sku limit 1) pl on true;   -- 대소문자만 다르면(색인 product_sku_lower_idx)
  create index if not exists t_link_var_item_idx on t_link_var (item_id, ord);
  create temp table if not exists t_link_dup (sku text) on commit drop;
  truncate t_link_dup;
  insert into t_link_dup (sku) select v.sku from t_link_var v where v.sku is not null group by v.sku having count(*) > 1;
  create temp table if not exists t_link_res (item_id uuid, decision text, reasons text[], ims_family_id uuid, ims_product_id uuid, changes jsonb) on commit drop;
  truncate t_link_res;
  create temp table if not exists t_link_img (kind text, key uuid, n int) on commit drop;                 -- 사진 수(판정 559 표시용) — 제품(p · 그 제품의 활성 사진) · family(f · parent 없는 구성원의 활성 사진 합)
  truncate t_link_img;
  insert into t_link_img (kind, key, n)
  select 'p', p.id, count(i.id) from public.product p left join public.product_image i on i.product_id = p.id and i.is_active where p.id in (select v.pid from t_link_var v where v.pid is not null) group by p.id;
  insert into t_link_img (kind, key, n)
  select 'f', p.family_id, count(i.id) from public.product p left join public.product_image i on i.product_id = p.id and i.is_active where p.parent_product_id is null and p.family_id in (select v.p_family_id from t_link_var v where v.p_family_id is not null) group by p.family_id;
  create index if not exists t_link_img_idx on t_link_img (kind, key);
  create temp table if not exists t_link_itm (item_id uuid primary key, famshape boolean, opt_sh text[]) on commit drop;   -- 줄마다: Shopify 가 family 모양인가(변형 둘 이상 또는 Title 아닌 옵션) · 옵션 이름(옛 판과 같은 식 · 같은 순서)
  truncate t_link_itm;
  insert into t_link_itm (item_id, famshape, opt_sh)
  select i.id, jsonb_array_length(i.variants) > 1 or exists (select 1 from jsonb_array_elements(i.options) o where lower(trim(coalesce(o->>'name', ''))) not in ('', 'title')),
         (select coalesce(array_agg(lower(trim(o->>'name')) order by 1), '{}') from jsonb_array_elements(i.options) o)
    from public.shop_link_item i where i.run_id = p_run_id;
  analyze t_link_var; analyze t_link_dup; analyze t_link_img; analyze t_link_itm;
  v_has_sp := exists (select 1 from public.shop_product sp where sp.store_id = v_run.store_id);          -- ⑤ 의 네 조회는 이 스토어에 이어진 것이 하나도 없으면 전부 거짓 — 건너뛴다(결과 같음)
  v_has_sv := exists (select 1 from public.shop_variant sv where sv.store_id = v_run.store_id);

  for it in select i.*, m.famshape, m.opt_sh from public.shop_link_item i join t_link_itm m on m.item_id = i.id where i.run_id = p_run_id order by i.handle, i.shopify_product_gid loop
    v_n := v_n + 1;
    v_any_inactive := false; v_any_disc := false;
    v_dec := 'link'; v_reasons := '{}'; v_fam := null; v_prod := null; v_changes := '{}'::jsonb;
    v_skus := '{}'; v_pids := '{}'; v_fams := '{}'; v_missing := '{}'; v_case := '{}';
    v_cnt := jsonb_array_length(it.variants);

    -- ① 변형마다 IMS 제품 찾기(정확히 · 대소문자만 다르면 sku_case 표시)
    for vr in select v.sku, v.pid, v.p_family_id, v.p_parent, v.p_sellable, v.p_is_active, v.p_is_discontinued, v.case_diff from t_link_var v where v.item_id = it.id order by v.ord loop
      if vr.sku is null then v_reasons := array_append(v_reasons, 'no_sku'); v_dec := 'block'; continue; end if;
      v_skus := array_append(v_skus, vr.sku);
      if vr.case_diff then v_case := array_append(v_case, vr.sku); end if;
      if vr.pid is null then v_missing := array_append(v_missing, vr.sku); continue; end if;
      if cardinality(v_pids) = 0 then v_p1_fam := vr.p_family_id; v_p1_par := vr.p_parent; v_p1_sell := vr.p_sellable; end if;   -- = 옛 판의 product where id = v_pids[1]
      v_any_inactive := v_any_inactive or not vr.p_is_active; v_any_disc := v_any_disc or vr.p_is_discontinued;   -- = 옛 판의 exists(product where id = any(v_pids) and not is_active / is_discontinued)
      v_pids := array_append(v_pids, vr.pid);
      if vr.p_family_id is not null and vr.p_parent is null then v_fams := array_append(v_fams, vr.p_family_id); else v_fams := array_append(v_fams, null); end if;
    end loop;
    if v_cnt = 0 then v_reasons := array_append(v_reasons, 'no_variants'); v_dec := 'block'; end if;

    -- ② 같은 SKU 둘(판 안 · 같은 상품 안도)
    if exists (select 1 from t_link_dup d where d.sku = any(v_skus)) then
      v_reasons := array_append(v_reasons, 'dup_sku'); v_dec := 'block';
    end if;
    -- ③ IMS 에 없는 SKU — 변형 하나뿐이면 report(이을 것이 없다) · 여럿이면 block(이으면 그 변형이 지워진다)
    if cardinality(v_missing) > 0 then
      v_reasons := array_append(v_reasons, 'not_in_ims');
      v_changes := v_changes || jsonb_build_object('not_in_ims', to_jsonb(v_missing));
      v_dec := case when v_cnt = 1 then 'report' else 'block' end;
    end if;
    if cardinality(v_case) > 0 then v_reasons := array_append(v_reasons, 'sku_case'); v_changes := v_changes || jsonb_build_object('sku_case', to_jsonb(v_case)); end if;

    -- ④ 모양(판정 556 · 557) — 찾은 제품으로만 판단(없는 SKU 가 있으면 위에서 이미 막혔다) · Shopify 가 family 모양 = 변형 둘 이상 또는 Title 아닌 옵션이 있다(변형 하나뿐인 일부 family 도 557)
    v_famshape := it.famshape;
    if v_dec <> 'block' and v_dec <> 'report' and cardinality(v_pids) > 0 then
      if not v_famshape then
        if v_p1_fam is not null and v_p1_par is null then
          v_reasons := array_append(v_reasons, 'shape_mismatch'); v_dec := 'block';                 -- Shopify 낱개 ↔ IMS family 구성원(556)
          v_changes := v_changes || jsonb_build_object('ims_family_sku', (select f.sku from public.product_family f where f.id = v_p1_fam));
        elsif v_p1_par is not null and not v_p1_sell then
          v_reasons := array_append(v_reasons, 'set_not_sellable'); v_dec := 'block';               -- 판정 404
        else
          v_prod := v_pids[1];
        end if;
      else
        if (select count(distinct f) from unnest(v_fams) f) = 1 and v_fams[1] is not null and not exists (select 1 from unnest(v_fams) f where f is null) then
          v_fam := v_fams[1];
          select * into v_f from public.product_family f where f.id = v_fam;
          select coalesce(array_agg(p.sku order by p.sku), '{}') into v_members from public.product p where p.family_id = v_fam and p.parent_product_id is null;
          select coalesce(array_agg(m order by m), '{}') into v_to_add from unnest(v_members) m where not (m = any(v_skus)) and not exists (select 1 from unnest(v_case) c where lower(c) = lower(m));
          if cardinality(v_to_add) > 0 then                                                         -- 557: 일부만 — 잇고 보낼 때 더해진다
            v_reasons := array_append(v_reasons, 'partial_family');
            v_changes := v_changes || jsonb_build_object('variants_to_add', to_jsonb(v_to_add));
          end if;
          -- 옵션 이름 차이(표시만 · IMS 가 주인)
          v_opt_sh := it.opt_sh;
          select coalesce(array_agg(lower(trim(n)) order by 1), '{}') into v_opt_ims from unnest(array[v_f.option1_name, v_f.option2_name, v_f.option3_name]) n where n is not null;
          if v_opt_sh <> v_opt_ims then
            v_reasons := array_append(v_reasons, 'option_name_diff');
            v_changes := v_changes || jsonb_build_object('option_names', jsonb_build_object('shopify', to_jsonb(v_opt_sh), 'ims', to_jsonb(v_opt_ims)));
          end if;
        else
          v_reasons := array_append(v_reasons, 'shape_mismatch'); v_dec := 'block';                 -- 여러 변형인데 한 family 가 아니다(낱개 여럿 · 두 family · 세트 섞임)
        end if;
      end if;
    end if;

    -- ⑤ 이미 이어진 것(같은 gid 면 멱등 · 다른 gid 면 사람이 정한다) · Product/0 자리표시는 「안 이어진 것」
    if v_dec in ('link') and v_has_sp then
      v_sp := null;
      if v_fam is not null then select * into v_sp from public.shop_product sp where sp.store_id = v_run.store_id and sp.family_id = v_fam;        -- 유니크 (store_id, family_id) · 옛 「is not distinct from」 둘과 같다(target_ck)
      elsif v_prod is not null then select * into v_sp from public.shop_product sp where sp.store_id = v_run.store_id and sp.product_id = v_prod; end if;
      if v_sp.id is not null and v_sp.shopify_product_gid <> 'gid://shopify/Product/0' then
        if v_sp.shopify_product_gid = it.shopify_product_gid then v_reasons := array_append(v_reasons, 'already_linked');
        else v_reasons := array_append(v_reasons, 'already_linked_other'); v_dec := 'block'; v_changes := v_changes || jsonb_build_object('linked_gid', v_sp.shopify_product_gid); end if;
      end if;
      if exists (select 1 from public.shop_product sp where sp.store_id = v_run.store_id and sp.shopify_product_gid = it.shopify_product_gid
                    and (sp.family_id is distinct from v_fam or sp.product_id is distinct from v_prod)) then
        v_reasons := array_append(v_reasons, 'gid_linked_elsewhere'); v_dec := 'block';
      end if;
    end if;
    if v_dec in ('link') and v_has_sv then
      -- 변형 gid 가 다른 제품에 이미 · 또는 구성원에 다른 변형 gid 가 이미
      if exists (select 1 from jsonb_array_elements(it.variants) v join public.shop_variant sv on sv.store_id = v_run.store_id and sv.shopify_variant_gid = v->>'variant_gid'
                  join public.product p on p.id = sv.product_id where lower(p.sku) <> lower(coalesce(v->>'sku', ''))) then
        v_reasons := array_append(v_reasons, 'gid_linked_elsewhere'); v_dec := 'block';
      end if;
      if exists (select 1 from public.shop_variant sv join public.product p on p.id = sv.product_id
                  where sv.store_id = v_run.store_id and p.id = any(v_pids)
                    and not exists (select 1 from jsonb_array_elements(it.variants) v where v->>'variant_gid' = sv.shopify_variant_gid)) then
        v_reasons := array_append(v_reasons, 'already_linked_other'); v_dec := 'block';
      end if;
    end if;

    -- ⑥ 표시(link 에만 뜻) · Draft · ARCHIVED 는 link_off(558 · 562)
    if v_dec = 'link' then
      if v_any_inactive then v_reasons := array_append(v_reasons, 'inactive'); end if;
      if v_any_disc then v_reasons := array_append(v_reasons, 'discontinued'); end if;
      v_img_n := coalesce((select g.n from t_link_img g where g.kind = case when v_fam is not null then 'f' else 'p' end and g.key = coalesce(v_fam, v_prod)), 0);
      if v_img_n = 0 then
        v_reasons := array_append(v_reasons, 'no_ims_images');                                      -- 559: 보낼 때 사진 칸을 빼는 것은 EF(1b)
      end if;
      v_changes := v_changes || jsonb_build_object('images', jsonb_build_object('shopify', jsonb_array_length(it.media), 'ims', v_img_n));
      if coalesce(it.status, '') <> 'ACTIVE' then
        v_dec := 'link_off';
        v_reasons := array_append(v_reasons, case when it.status = 'DRAFT' then 'draft' when it.status = 'ARCHIVED' then 'archived' else 'status_unknown' end);
      end if;
    end if;
    if v_dec in ('block', 'report') then v_fam := null; v_prod := null; end if;

    insert into t_link_res (item_id, decision, reasons, ims_family_id, ims_product_id, changes) values (it.id, v_dec, v_reasons, v_fam, v_prod, v_changes);
  end loop;
  update public.shop_link_item i set decision = r.decision, reasons = r.reasons, ims_family_id = r.ims_family_id, ims_product_id = r.ims_product_id, changes = r.changes, updated_by = v_staff
    from t_link_res r where i.id = r.item_id;

  update public.shop_link_run set status = 'planned', version = version + 1, planned_at = now(), item_count = v_n, updated_by = v_staff where id = p_run_id returning * into v_run;
  select jsonb_object_agg(d, n) into v_counts from (select decision as d, count(*) as n from public.shop_link_item where run_id = p_run_id group by 1) x;
  select jsonb_object_agg(r, n) into v_reason_counts from (select r, count(*) as n from public.shop_link_item i cross join unnest(i.reasons) r where i.run_id = p_run_id group by 1) x;
  return jsonb_build_object('run_id', p_run_id, 'store_code', v_s.code, 'version', v_run.version, 'items', v_n,
                            'counts', coalesce(v_counts, '{}'::jsonb), 'reasons', coalesce(v_reason_counts, '{}'::jsonb), 'planned_at', v_run.planned_at);
end;

$$;
comment on function public.shop_link_plan(uuid) is 'link-1a(판정 555 ~ 558 · 562) — 판의 줄마다 판정을 적는다(판정 칸만 · version +1): link(하나에 하나 · family 전부 · family 일부 = partial_family 557) · link_off(Shopify DRAFT · ARCHIVED 558 · 562) · block(no_sku · dup_sku · not_in_ims(변형 여럿) · shape_mismatch 556 · set_not_sellable · already_linked_other · gid_linked_elsewhere) · report(not_in_ims 변형 하나) · 표시 inactive · discontinued · option_name_diff · sku_case · no_ims_images(559) · already_linked(멱등) · Product/0 행은 안 이어진 것으로 본다 · ⭐ link-perf-1(2026-10-27): 변형 ↔ 제품 짝 · 같은 SKU 집합 · 판정 쓰기를 집합 한 번으로(5,079 상품 31 s → 3 s 안 · 판정 한 글자도 같다 · 시험 supabase/tests/link_perf_1.sql)';
