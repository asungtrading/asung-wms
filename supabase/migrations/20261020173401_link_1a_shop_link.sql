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

-- ═══ link-1a — 기존 Shopify 상품을 SKU 로 잇기: 판 · 판정 · 실행 · 묶음 보내기 (2026-10-20 · 판정 420 실행 · 555 ~ 563 · shop-link-0 조사 · link-1a 이견 1 ~ 10 · 정본 so-module §67) ═══
--   왜: 새로 만들기 / 고치기는 shop_product.shopify_product_gid 하나로 갈린다(EF index.ts 177 · 217 · shopify-product.ts 63) — gid 없이 보냄을 켜면 productSet 이 같은 SKU 의 상품을 새로 만든다(중복) · 변형 gid 가 없으면 변형이 지워지고 다시 생긴다
--   표 둘: shop_link_run(판 · 스토어 · 상태 · version) · shop_link_item(Shopify 상품 하나 = 한 줄 · 원자료 칸은 1b EF 가 bulk 읽기로 채운다 · 판정 칸은 shop_link_plan 이 채운다)
--   창구 넷: shop_link_plan(run) → shop_link_apply(run, commit, version) → shop_link_push_batch(store, filter, commit, limit) · shop_link_remaining(store) — 문은 전부 ims_require_write('shopify')
--   실행 순서(이견 3): ① shop_listing(link 는 켬 · link_off 는 끔) → ② shop_product(gid · handle · status) → ③ shop_variant(변형 gid · inventory_item_gid) → ④ 그 순간의 shop_product_payload hash 를 last_hash 에(555 · 첫 drain · 새벽이 건너뛴다) · 큐는 넣지 않는다(자기 검사) · 재고 트리거는 그대로(563)
--   「아직 안 보냄」 = gid 있음 + last_pushed_at null(이견 4 · 새 칸 없음) · push_batch 가 last_hash 를 비우고 shop_queue_add 로 큐에(한 곳 · 200 줄 기본)
--   1b 몫(이 차수 아님): bulk 읽기 · JSONL → shop_link_item 원자료 · 판정 559(EF 가 사진 0 장이면 files 키 · 변형 file 을 뺀다) · 결함 Product/0(첫 실패 때 upsert 안 함 + 제약) — 여기서는 plan 이 Product/0 행을 「안 이어진 것」으로 본다
--   판정 562(ARCHIVED 도 link_off) · 563(재고 트리거 그대로) — 2026-10-20 Caleb · 다음 판정 번호 564

-- ═══ 1) 표 둘 ═══
create table public.shop_link_run (
  id                  uuid primary key default gen_random_uuid(),
  store_id            uuid not null references public.shop_store(id),
  status              text not null default 'reading',
  version             int  not null default 0,                                              -- plan 마다 +1 · apply 는 사람이 본 version 만 받는다(이견 7)
  bulk_operation_gid  text,
  started_at          timestamptz not null default now(),
  started_by          uuid references public.ims_staff(id),
  read_at             timestamptz,
  item_count          int,
  planned_at          timestamptz,
  applied_at          timestamptz,
  applied_by          uuid references public.ims_staff(id),
  note                text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  updated_by          uuid references public.ims_staff(id),
  constraint shop_link_run_status_ck check (status in ('reading', 'read', 'planned', 'applied', 'cancelled')),
  constraint shop_link_run_bulk_ck   check (bulk_operation_gid is null or bulk_operation_gid ~ '^gid://shopify/BulkOperation/[0-9]+$')
);
create index shop_link_run_store_idx on public.shop_link_run (store_id, started_at desc);
create trigger shop_link_run_touch before update on public.shop_link_run for each row execute function public.ims_touch();
comment on table public.shop_link_run is 'link-1a(판정 420 · 555 ~ 563) — 기존 Shopify 상품 잇기의 「판」 한 번: 스토어 하나 · status reading(1b 가 bulk 시작) → read(JSONL 적재 끝) → planned(shop_link_plan) → applied(shop_link_apply) | cancelled · version 은 plan 마다 +1 · apply 는 사람이 본 version 만';

create table public.shop_link_item (
  id                  uuid primary key default gen_random_uuid(),
  run_id              uuid not null references public.shop_link_run(id) on delete cascade,
  -- 원자료(1b EF 가 채운다 · service_role)
  shopify_product_gid text not null,
  handle              text,
  title               text,
  status              text,                                                                -- ACTIVE | DRAFT | ARCHIVED(Shopify 값 그대로)
  vendor              text,
  product_type        text,
  options             jsonb not null default '[]'::jsonb,                                  -- [{name, values[]}]
  variants            jsonb not null default '[]'::jsonb,                                  -- [{sku, variant_gid, inventory_item_gid, title, option_values[{name,value}], inventory_policy, position}]
  media               jsonb not null default '[]'::jsonb,                                  -- [{gid, url, alt}] 보고용(판정 560 · 잇지 않는다)
  -- 판정(shop_link_plan 이 채운다)
  decision            text,
  reasons             text[] not null default '{}',
  ims_family_id       uuid references public.product_family(id),
  ims_product_id      uuid references public.product(id),
  changes             jsonb not null default '{}'::jsonb,
  applied_at          timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  updated_by          uuid references public.ims_staff(id),
  constraint shop_link_item_gid_ck      check (shopify_product_gid ~ '^gid://shopify/Product/[0-9]+$'),
  constraint shop_link_item_decision_ck check (decision is null or decision in ('link', 'link_off', 'block', 'report')),
  constraint shop_link_item_target_ck   check (ims_family_id is null or ims_product_id is null),
  constraint shop_link_item_run_gid_uk  unique (run_id, shopify_product_gid)
);
create index shop_link_item_run_idx on public.shop_link_item (run_id, decision);
create trigger shop_link_item_touch before update on public.shop_link_item for each row execute function public.ims_touch();
comment on table public.shop_link_item is 'link-1a — 판의 한 줄 = Shopify 상품 하나 · 원자료 칸(shopify_product_gid · handle · title · status · vendor · product_type · options · variants · media)은 1b 가 · 판정 칸(decision link | link_off | block | report · reasons · ims_family_id | ims_product_id · changes · applied_at)은 shop_link_plan · shop_link_apply 가 쓴다';

do $$ declare t text; begin
  foreach t in array array['shop_link_run', 'shop_link_item'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('create policy %I on public.%I for select to authenticated using (true)', t || '_select', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
    execute format('grant select on public.%I to authenticated', t);
  end loop;
end $$;

-- ═══ 2) 판정 shop_link_plan(run) — 판정 칸만 쓴다 · version +1 ═══
create function public.shop_link_plan(p_run_id uuid) returns jsonb
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
  create temp table if not exists t_link_sku (sku text, item_id uuid) on commit drop;
  truncate t_link_sku;
  insert into t_link_sku (sku, item_id)
  select nullif(trim(v->>'sku'), ''), i.id from public.shop_link_item i cross join lateral jsonb_array_elements(i.variants) v where i.run_id = p_run_id;

  for it in select * from public.shop_link_item i where i.run_id = p_run_id order by i.handle, i.shopify_product_gid loop
    v_n := v_n + 1;
    v_dec := 'link'; v_reasons := '{}'; v_fam := null; v_prod := null; v_changes := '{}'::jsonb;
    v_skus := '{}'; v_pids := '{}'; v_fams := '{}'; v_missing := '{}'; v_case := '{}';
    v_cnt := jsonb_array_length(it.variants);

    -- ① 변형마다 IMS 제품 찾기(정확히 · 대소문자만 다르면 sku_case 표시)
    for vr in select nullif(trim(v->>'sku'), '') as sku from jsonb_array_elements(it.variants) v loop
      if vr.sku is null then v_reasons := array_append(v_reasons, 'no_sku'); v_dec := 'block'; continue; end if;
      v_skus := array_append(v_skus, vr.sku);
      select * into v_p from public.product p where p.sku = vr.sku;
      if not found then
        select * into v_p from public.product p where lower(p.sku) = lower(vr.sku) order by p.sku limit 1;
        if found then v_case := array_append(v_case, vr.sku); end if;
      end if;
      if v_p.id is null then v_missing := array_append(v_missing, vr.sku); continue; end if;
      v_pids := array_append(v_pids, v_p.id);
      if v_p.family_id is not null and v_p.parent_product_id is null then v_fams := array_append(v_fams, v_p.family_id); else v_fams := array_append(v_fams, null); end if;
    end loop;
    if v_cnt = 0 then v_reasons := array_append(v_reasons, 'no_variants'); v_dec := 'block'; end if;

    -- ② 같은 SKU 둘(판 안 · 같은 상품 안도)
    if exists (select 1 from t_link_sku k where k.sku = any(v_skus) group by k.sku having count(*) > 1) then
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
    v_famshape := v_cnt > 1 or exists (select 1 from jsonb_array_elements(it.options) o where lower(trim(coalesce(o->>'name', ''))) not in ('', 'title'));
    if v_dec <> 'block' and v_dec <> 'report' and cardinality(v_pids) > 0 then
      if not v_famshape then
        select * into v_p from public.product p where p.id = v_pids[1];
        if v_p.family_id is not null and v_p.parent_product_id is null then
          v_reasons := array_append(v_reasons, 'shape_mismatch'); v_dec := 'block';                 -- Shopify 낱개 ↔ IMS family 구성원(556)
          v_changes := v_changes || jsonb_build_object('ims_family_sku', (select f.sku from public.product_family f where f.id = v_p.family_id));
        elsif v_p.parent_product_id is not null and not v_p.sellable then
          v_reasons := array_append(v_reasons, 'set_not_sellable'); v_dec := 'block';               -- 판정 404
        else
          v_prod := v_p.id;
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
          select coalesce(array_agg(lower(trim(o->>'name')) order by 1), '{}') into v_opt_sh from jsonb_array_elements(it.options) o;
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
    if v_dec in ('link') then
      select * into v_sp from public.shop_product sp where sp.store_id = v_run.store_id and sp.family_id is not distinct from v_fam and sp.product_id is not distinct from v_prod;
      if v_sp.id is not null and v_sp.shopify_product_gid <> 'gid://shopify/Product/0' then
        if v_sp.shopify_product_gid = it.shopify_product_gid then v_reasons := array_append(v_reasons, 'already_linked');
        else v_reasons := array_append(v_reasons, 'already_linked_other'); v_dec := 'block'; v_changes := v_changes || jsonb_build_object('linked_gid', v_sp.shopify_product_gid); end if;
      end if;
      if exists (select 1 from public.shop_product sp where sp.store_id = v_run.store_id and sp.shopify_product_gid = it.shopify_product_gid
                    and (sp.family_id is distinct from v_fam or sp.product_id is distinct from v_prod)) then
        v_reasons := array_append(v_reasons, 'gid_linked_elsewhere'); v_dec := 'block';
      end if;
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
      if exists (select 1 from public.product p where p.id = any(v_pids) and not p.is_active) then v_reasons := array_append(v_reasons, 'inactive'); end if;
      if exists (select 1 from public.product p where p.id = any(v_pids) and p.is_discontinued) then v_reasons := array_append(v_reasons, 'discontinued'); end if;
      if not exists (select 1 from public.product_image i join public.product p on p.id = i.product_id where i.is_active
                       and (p.id = v_prod or (v_fam is not null and p.family_id = v_fam and p.parent_product_id is null))) then
        v_reasons := array_append(v_reasons, 'no_ims_images');                                      -- 559: 보낼 때 사진 칸을 빼는 것은 EF(1b)
      end if;
      v_changes := v_changes || jsonb_build_object('images', jsonb_build_object('shopify', jsonb_array_length(it.media),
                     'ims', (select count(*) from public.product_image i join public.product p on p.id = i.product_id where i.is_active and (p.id = v_prod or (v_fam is not null and p.family_id = v_fam and p.parent_product_id is null)))));
      if coalesce(it.status, '') <> 'ACTIVE' then
        v_dec := 'link_off';
        v_reasons := array_append(v_reasons, case when it.status = 'DRAFT' then 'draft' when it.status = 'ARCHIVED' then 'archived' else 'status_unknown' end);
      end if;
    end if;
    if v_dec in ('block', 'report') then v_fam := null; v_prod := null; end if;

    update public.shop_link_item set decision = v_dec, reasons = v_reasons, ims_family_id = v_fam, ims_product_id = v_prod, changes = v_changes, updated_by = v_staff
     where id = it.id;
  end loop;

  update public.shop_link_run set status = 'planned', version = version + 1, planned_at = now(), item_count = v_n, updated_by = v_staff where id = p_run_id returning * into v_run;
  select jsonb_object_agg(d, n) into v_counts from (select decision as d, count(*) as n from public.shop_link_item where run_id = p_run_id group by 1) x;
  select jsonb_object_agg(r, n) into v_reason_counts from (select r, count(*) as n from public.shop_link_item i cross join unnest(i.reasons) r where i.run_id = p_run_id group by 1) x;
  return jsonb_build_object('run_id', p_run_id, 'store_code', v_s.code, 'version', v_run.version, 'items', v_n,
                            'counts', coalesce(v_counts, '{}'::jsonb), 'reasons', coalesce(v_reason_counts, '{}'::jsonb), 'planned_at', v_run.planned_at);
end;
$$;
revoke all on function public.shop_link_plan(uuid) from public, anon;
grant execute on function public.shop_link_plan(uuid) to authenticated, service_role;
comment on function public.shop_link_plan(uuid) is 'link-1a(판정 555 ~ 558 · 562) — 판의 줄마다 판정을 적는다(판정 칸만 · version +1): link(하나에 하나 · family 전부 · family 일부 = partial_family 557) · link_off(Shopify DRAFT · ARCHIVED 558 · 562) · block(no_sku · dup_sku · not_in_ims(변형 여럿) · shape_mismatch 556 · set_not_sellable · already_linked_other · gid_linked_elsewhere) · report(not_in_ims 변형 하나) · 표시 inactive · discontinued · option_name_diff · sku_case · no_ims_images(559) · already_linked(멱등) · Product/0 행은 안 이어진 것으로 본다';

-- ═══ 3) 실행 shop_link_apply(run, commit, version) — ① listing → ② shop_product → ③ shop_variant → ④ hash 심기 · 큐 없음 ═══
create function public.shop_link_apply(p_run_id uuid, p_commit boolean default false, p_run_version int default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_run      public.shop_link_run%rowtype;
  v_s        public.shop_store%rowtype;
  it         record;
  vr         record;
  v_q0       bigint;  v_q1 bigint;
  v_linked   int := 0;  v_off int := 0;  v_variants int := 0;  v_skipped int := 0;  v_hash_n int := 0;
  v_list     jsonb := '[]'::jsonb;
  v_pl       jsonb;
  v_pid      uuid;
  v_n        int;
  v_now      timestamptz := now();
begin
  perform public.ims_require_write('shopify', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_run from public.shop_link_run where id = p_run_id for update;
  if not found then raise exception 'Link run % not found — nothing was saved', p_run_id; end if;
  if v_run.status <> 'planned' then raise exception 'Link run % is % — only a planned run can be applied — nothing was saved', p_run_id, v_run.status; end if;
  if p_run_version is null or p_run_version <> v_run.version then
    raise exception 'The plan you looked at is version % but the run is now version % — plan again and look again — nothing was saved', coalesce(p_run_version::text, '(none)'), v_run.version;
  end if;
  select * into v_s from public.shop_store where id = v_run.store_id;
  if not v_s.is_active then raise exception 'Store "%" is switched off — nothing was saved', v_s.code; end if;
  select count(*) into v_q0 from public.shop_push_queue q where q.store_id = v_s.id and q.done_at is null;

  for it in select * from public.shop_link_item i where i.run_id = p_run_id order by i.handle, i.shopify_product_gid loop
    if it.decision not in ('link', 'link_off') then v_skipped := v_skipped + 1; continue; end if;
    v_list := v_list || jsonb_build_object('item_id', it.id, 'gid', it.shopify_product_gid, 'handle', it.handle, 'decision', it.decision,
                                           'family_id', it.ims_family_id, 'product_id', it.ims_product_id, 'variants', jsonb_array_length(it.variants), 'reasons', to_jsonb(it.reasons));
    if it.decision = 'link' then v_linked := v_linked + 1; else v_off := v_off + 1; end if;
    v_variants := v_variants + jsonb_array_length(it.variants);
    if not p_commit then continue; end if;

    -- ① listing(큐 없이) — link 는 켬 · link_off 는 끔(gid 만 · 558 · 562)
    if it.decision = 'link' then
      update public.shop_listing set is_on = true, turned_on_at = v_now, turned_on_by = v_staff, turned_off_at = null, turned_off_by = null, updated_by = v_staff
       where store_id = v_s.id and family_id is not distinct from it.ims_family_id and product_id is not distinct from it.ims_product_id and not is_on;
      if not found and not exists (select 1 from public.shop_listing l where l.store_id = v_s.id and l.family_id is not distinct from it.ims_family_id and l.product_id is not distinct from it.ims_product_id) then
        insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, updated_by) values (v_s.id, it.ims_family_id, it.ims_product_id, true, v_now, v_staff, v_staff);
      end if;
    else
      update public.shop_listing set is_on = false, turned_off_at = v_now, turned_off_by = v_staff, updated_by = v_staff
       where store_id = v_s.id and family_id is not distinct from it.ims_family_id and product_id is not distinct from it.ims_product_id and is_on;
      if not found and not exists (select 1 from public.shop_listing l where l.store_id = v_s.id and l.family_id is not distinct from it.ims_family_id and l.product_id is not distinct from it.ims_product_id) then
        insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, turned_off_at, turned_off_by, updated_by) values (v_s.id, it.ims_family_id, it.ims_product_id, false, v_now, v_staff, v_now, v_staff, v_staff);
      end if;
    end if;
    -- ② shop_product(같은 gid 면 last_pushed_at 은 그대로 · 새 gid · Product/0 자리표시면 비운다)
    update public.shop_product sp set shopify_product_gid = it.shopify_product_gid, handle = it.handle, shopify_status = it.status, last_status = 'pending', last_error = null,
           last_pushed_at = case when sp.shopify_product_gid = it.shopify_product_gid then sp.last_pushed_at end, updated_by = v_staff
     where sp.store_id = v_s.id and sp.family_id is not distinct from it.ims_family_id and sp.product_id is not distinct from it.ims_product_id;
    if not found then
      insert into public.shop_product (store_id, family_id, product_id, shopify_product_gid, handle, shopify_status, last_status, updated_by)
      values (v_s.id, it.ims_family_id, it.ims_product_id, it.shopify_product_gid, it.handle, it.status, 'pending', v_staff);
    end if;
    -- ③ shop_variant(변형마다 · SKU → 제품 · 대소문자만 다르면 lower 로)
    for vr in select nullif(trim(v->>'sku'), '') as sku, v->>'variant_gid' as vgid, nullif(v->>'inventory_item_gid', '') as igid from jsonb_array_elements(it.variants) v loop
      select p.id into v_pid from public.product p where p.sku = vr.sku;
      if v_pid is null then select p.id into v_pid from public.product p where lower(p.sku) = lower(vr.sku) order by p.sku limit 1; end if;
      if v_pid is null then raise exception 'Link run %: SKU % is not in IMS any more — plan again — nothing was saved', p_run_id, vr.sku; end if;
      update public.shop_variant set shopify_variant_gid = vr.vgid, inventory_item_gid = vr.igid, updated_by = v_staff where store_id = v_s.id and product_id = v_pid;
      if not found then insert into public.shop_variant (store_id, product_id, shopify_variant_gid, inventory_item_gid, updated_by) values (v_s.id, v_pid, vr.vgid, vr.igid, v_staff); end if;
    end loop;
    -- ④ hash — listing · gid 가 선 뒤의 payload(555 · 첫 drain · 새벽 맞추기가 skipped_same_hash)
    v_pl := public.shop_product_payload(v_s.id, it.ims_family_id, it.ims_product_id);
    update public.shop_product set last_hash = v_pl->>'hash' where store_id = v_s.id and family_id is not distinct from it.ims_family_id and product_id is not distinct from it.ims_product_id;
    v_hash_n := v_hash_n + 1;
    update public.shop_link_item set applied_at = v_now, updated_by = v_staff where id = it.id;
  end loop;

  if p_commit then
    select count(*) into v_q1 from public.shop_push_queue q where q.store_id = v_s.id and q.done_at is null;
    if v_q1 <> v_q0 then raise exception 'Link run %: a product push was queued while linking (% → %) — linking must not send — nothing was saved', p_run_id, v_q0, v_q1; end if;   -- 자기 검사(이견 3)
    update public.shop_link_run set status = 'applied', applied_at = v_now, applied_by = v_staff, updated_by = v_staff where id = p_run_id;
  end if;
  return jsonb_build_object('committed', p_commit, 'run_id', p_run_id, 'store_code', v_s.code, 'version', v_run.version,
                            'linked', v_linked, 'linked_off', v_off, 'skipped', v_skipped, 'variants', v_variants, 'hash_seeded', case when p_commit then v_hash_n else 0 end,
                            'push_queue_open', v_q0, 'stock_queue_open', (select count(*) from public.shop_stock_queue q where q.store_id = v_s.id and q.done_at is null),
                            'items', v_list);
end;
$$;
revoke all on function public.shop_link_apply(uuid, boolean, int) from public, anon;
grant execute on function public.shop_link_apply(uuid, boolean, int) to authenticated, service_role;
comment on function public.shop_link_apply(uuid, boolean, integer) is 'link-1a(판정 555 · 558 · 562 · 563) — planned 판을 실행(사람이 본 version 만 · 미리 보기는 쓰기 0): link · link_off 줄마다 ① shop_listing(link 켬 · link_off 끔 · 큐 없음) ② shop_product(gid · handle · status · pending) ③ shop_variant(변형 gid · inventory_item_gid) ④ 그 순간의 shop_product_payload hash 를 last_hash 에(첫 drain · 새벽이 건너뛴다 · 보내기는 shop_link_push_batch 로 사람이 묶음씩) · 자기 검사 = 그 스토어 열린 push 큐 수 무변 · 재고 트리거는 그대로(563 · 켜진 변형 재고가 바로 IMS 값)';

-- ═══ 4) 묶음 보내기 shop_link_push_batch(store, filter, commit, limit) · 남은 수 shop_link_remaining(store) ═══
--   「이었지만 아직 안 보냄」 = shop_product.shopify_product_gid 있음 · last_pushed_at null(보내기 성공만 찍는다 · 건너뜀은 안 찍는다) · 켜진 listing
--   filter 열쇠: brand_id[] · category_id[] · tag[] · sku_like · kind(family | product) · 고른 것의 last_hash 를 비우고 shop_queue_add(한 곳)로 큐에 → drain 이 보낸다
create function public.shop_link_push_batch(p_store_id uuid, p_filter jsonb default '{}'::jsonb, p_commit boolean default false, p_limit int default 200) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff  uuid;
  v_s      public.shop_store%rowtype;
  v_brands uuid[];  v_cats uuid[];  v_tags text[];  v_like text;  v_kind text;
  v_fids   uuid[] := '{}';  v_pids uuid[] := '{}';
  v_items  jsonb;
  v_n      int := 0;  v_queued int := 0;  v_total int;
begin
  perform public.ims_require_write('shopify', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_s from public.shop_store where id = p_store_id;
  if v_s.id is null then raise exception 'Store % not found — nothing was saved', p_store_id; end if;
  if p_limit is null or p_limit < 1 or p_limit > 200 then raise exception 'p_limit must be 1 ~ 200 (the drain sends 20 a minute) — nothing was saved'; end if;
  if p_filter is not null and jsonb_typeof(p_filter) <> 'object' then raise exception 'p_filter must be a JSON object — nothing was saved'; end if;
  select array_agg((e)::uuid) into v_brands from jsonb_array_elements_text(coalesce(p_filter->'brand_id', '[]'::jsonb)) e;
  select array_agg((e)::uuid) into v_cats   from jsonb_array_elements_text(coalesce(p_filter->'category_id', '[]'::jsonb)) e;
  select array_agg(e) into v_tags           from jsonb_array_elements_text(coalesce(p_filter->'tag', '[]'::jsonb)) e;
  v_like := nullif(trim(coalesce(p_filter->>'sku_like', '')), '');
  v_kind := nullif(trim(coalesce(p_filter->>'kind', '')), '');
  if v_kind is not null and v_kind not in ('family', 'product') then raise exception 'p_filter.kind must be family or product — nothing was saved'; end if;

  create temp table if not exists t_link_push (family_id uuid, product_id uuid, kind text, sku text, name text, brand_id uuid, brand_name text, gid text) on commit drop;
  truncate t_link_push;
  insert into t_link_push
  select sp.family_id, sp.product_id, case when sp.family_id is not null then 'family' else 'product' end,
         coalesce(f.sku, p.sku), coalesce(f.name, p.name), coalesce(f.brand_id, p.brand_id), coalesce(f.brand_name, p.brand_name), sp.shopify_product_gid
    from public.shop_product sp
    join public.shop_listing l on l.store_id = sp.store_id and l.family_id is not distinct from sp.family_id and l.product_id is not distinct from sp.product_id and l.is_on
    left join public.product_family f on f.id = sp.family_id
    left join public.product p on p.id = sp.product_id
   where sp.store_id = p_store_id and sp.last_pushed_at is null and sp.shopify_product_gid <> 'gid://shopify/Product/0'
     and (v_kind is null or (v_kind = 'family') = (sp.family_id is not null))
     and (v_brands is null or coalesce(f.brand_id, p.brand_id) = any(v_brands))
     and (v_cats is null or coalesce(f.category_id, p.category_id) = any(v_cats))
     and (v_like is null or coalesce(f.sku, p.sku) ilike v_like)
     and (v_tags is null or exists (select 1 from public.product_tag t join public.product x on x.id = t.product_id
                                     where t.tag = any(v_tags) and (x.id = sp.product_id or (sp.family_id is not null and x.family_id = sp.family_id))))
   order by coalesce(f.sku, p.sku)
   limit p_limit;
  select count(*) into v_n from t_link_push;
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'sku', sku, 'name', name, 'brand_name', brand_name, 'gid', gid) order by sku), '[]'::jsonb) into v_items from t_link_push;
  select count(*) into v_total from public.shop_product sp join public.shop_listing l on l.store_id = sp.store_id and l.family_id is not distinct from sp.family_id and l.product_id is not distinct from sp.product_id and l.is_on
   where sp.store_id = p_store_id and sp.last_pushed_at is null and sp.shopify_product_gid <> 'gid://shopify/Product/0';

  if p_commit and v_n > 0 then
    select coalesce(array_agg(family_id), '{}') into v_fids from t_link_push where family_id is not null;
    select coalesce(array_agg(product_id), '{}') into v_pids from t_link_push where product_id is not null;
    update public.shop_product sp set last_hash = null, last_status = 'pending', updated_by = v_staff
     where sp.store_id = p_store_id and ((sp.family_id is not null and sp.family_id = any(v_fids)) or (sp.product_id is not null and sp.product_id = any(v_pids)));
    v_queued := public.shop_queue_add(v_fids, v_pids, 'link_push', p_store_id);                       -- 한 곳 · 열린 줄이 있으면 건너뛴다
  end if;
  return jsonb_build_object('committed', p_commit, 'store_code', v_s.code, 'picked', v_n, 'queued', v_queued, 'remaining_before', v_total,
                            'remaining_after', case when p_commit then v_total - v_n else v_total end, 'limit', p_limit, 'items', v_items);
end;
$$;
revoke all on function public.shop_link_push_batch(uuid, jsonb, boolean, int) from public, anon;
grant execute on function public.shop_link_push_batch(uuid, jsonb, boolean, int) to authenticated, service_role;
comment on function public.shop_link_push_batch(uuid, jsonb, boolean, integer) is 'link-1a(판정 555) — 이었지만 아직 안 보낸 상품(gid 있음 · last_pushed_at null · 켜진 listing)을 filter(brand_id[] · category_id[] · tag[] · sku_like · kind)로 골라(sku 순 · limit ≤ 200) last_hash 를 비우고 shop_queue_add(reason link_push)로 큐에 → drain 이 보낸다 · 미리 보기는 쓰기 0 · 남은 수 remaining_before/after';

create function public.shop_link_remaining(p_store_id uuid) returns jsonb
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  with r as (
    select sp.family_id, sp.product_id, coalesce(f.brand_id, p.brand_id) as brand_id, coalesce(f.brand_name, p.brand_name, '(no brand)') as brand_name
      from public.shop_product sp
      join public.shop_listing l on l.store_id = sp.store_id and l.family_id is not distinct from sp.family_id and l.product_id is not distinct from sp.product_id and l.is_on
      left join public.product_family f on f.id = sp.family_id
      left join public.product p on p.id = sp.product_id
     where sp.store_id = p_store_id and sp.last_pushed_at is null and sp.shopify_product_gid <> 'gid://shopify/Product/0'
  )
  select jsonb_build_object('store_id', p_store_id, 'total', (select count(*) from r),
                            'families', (select count(*) from r where family_id is not null), 'products', (select count(*) from r where product_id is not null),
                            'by_brand', coalesce((select jsonb_agg(jsonb_build_object('brand_id', brand_id, 'brand_name', brand_name, 'remaining', n) order by n desc, brand_name)
                                                   from (select brand_id, brand_name, count(*) as n from r group by 1, 2) b), '[]'::jsonb))
$$;
revoke all on function public.shop_link_remaining(uuid) from public, anon;
grant execute on function public.shop_link_remaining(uuid) to authenticated, service_role;
comment on function public.shop_link_remaining(uuid) is 'link-1a(판정 555) — 스토어의 「이었지만 아직 안 보냄」 수(전체 · family · 낱개 · 브랜드별) = shop_product.shopify_product_gid 있음 · last_pushed_at null · 켜진 listing';
-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  if to_regclass('public.shop_link_run') is null or to_regclass('public.shop_link_item') is null then v_bad := v_bad || ' tables'; end if;
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('shop_link_plan', 'shop_link_apply', 'shop_link_push_batch', 'shop_link_remaining') and p.prosrc ~ 'link-1a|ims_require_write|last_pushed_at';
  if v_n <> 4 then v_bad := v_bad || format(' functions_%s_of_4', v_n); end if;
  if exists (select 1 from public.shop_product where shopify_product_gid = 'gid://shopify/Product/0') then v_bad := v_bad || ' product0_rows_exist'; end if;
  if (select count(*) from pg_policies where tablename in ('shop_link_run', 'shop_link_item') and cmd = 'SELECT') <> 2 then v_bad := v_bad || ' rls'; end if;
  if (select string_agg(privilege_type, ',' order by privilege_type) from information_schema.role_table_grants where table_name = 'shop_link_item' and grantee = 'authenticated') <> 'SELECT' then v_bad := v_bad || ' grants'; end if;
  if v_bad <> '' then raise exception 'link-1a landing check failed:%', v_bad; end if;
end $$;
