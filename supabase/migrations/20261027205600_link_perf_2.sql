-- link-perf-2 — shop_link_apply 를 나눠서(판정 829 · 2026-10-27 · 지시서 ~/asung/prompts/link-perf-2.md · 앞선 link-perf-1 20261027202614)
--   왜: asung run(2b81c902 · link 4,954 · 변형 8,379)에서 한 번에 apply 가 73.6 s — authenticated 시한 8 s 를 훌쩍 넘는다. 판정 829(Caleb 「A」): 화면이 수백 개씩 여러 번 부르고 진행을 보이며 · 중간에 멈추면 다시 눌러 남은 것부터 · 마지막 묶음이 run 을 applied 로(「Send all left」와 같은 꼴)
--   실측(테스트 DB · 2b81c902 · pg_temp 사본에 시계 · 2026-10-27 20:50 · rollback): 총 69.9 s = 반환 items 를 jsonb 로 줄마다 덧붙이기 16.7 s(O(n²)) + ① listing 18.3 s + ② shop_product 5.1 s + ④ hash update 4.9 s(셋 다 「is not distinct from」 둘 — 색인을 못 타 store 의 행 전부를 줄마다 훑는다 · 행이 늘수록 O(n²)) + ④ payload 14.9 s(줄마다 3 ms · 이건 그대로) + ③ 변형 8.6 s(변형마다 select 1 + update + insert) + 줄 update 1.1 s
--   고침(결과 한 글자도 같게 — 순서 · 판정 · 쓰는 칸 그대로):
--     · 묶음 인자 p_limit(null = 전부 · 옛 화면 호환): 「지금 차례인 줄」 = decision link · link_off 이고 이 판 뒤에 아직 안 적용된 줄(applied_at null 또는 planned_at 앞) 을 (handle, gid) 순으로 N 개만 · 남은 것이 0 이 되는 호출이 run 을 applied 로 · 반환에 remaining · done · total_* 을 더한다
--     · 「이 판에서」 = 새 칸 shop_link_item.applied_version(apply 가 run.version 을 적는다) — 계획을 다시 하면(version +1) 이어서 하던 호출은 version 검사로 막히고(그대로) · 새 version 으로 다시 누르면 처음부터(멱등 쓰기 · 옛 applied_version ≠ 지금 version 이라 「안 된 것」) — plan 은 손대지 않는다 · 시각(applied_at < planned_at)으로 가르지 않는 까닭: now() 는 트랜잭션 시작 시각이라 먼저 시작해 잠금을 늦게 잡은 plan 의 planned_at 이 그 사이 적용된 applied_at 보다 앞설 수 있다(시험 2회차 R7 에서 같은 트랜잭션의 now() 가 같아 드러남)
--     · 미리 보기(p_commit false)는 전체 숫자(묶음과 무관 · 지금처럼) + remaining(이어서 할 수 있는 수)
--     · ① listing 은 대상이 묶음 안에서 한 번뿐인 줄은 집합 네 문장(shop_listing 의 AFTER STATEMENT 재고 트리거가 문장마다 돌아 줄마다 하면 500 줄에 1.4 s) · 대상이 겹치는 줄(아래 ⚠)만 고리에서 순서대로 — 뒤의 것이 이긴다 · ② shop_product 는 줄마다 그대로(0.2 s / 500) · 술어는 family / product 두 갈래 등호(유니크 색인 store_fam_uk · store_prod_uk · target_ck 로 같은 뜻)
--     · ③ 변형 · ④ hash · 줄 applied_at 은 묶음 단위 집합 한 번(변형은 product 마다 마지막 줄이 이긴다 = 옛 고리의 「뒤의 update 가 덮음」 · payload 는 제 listing 만 읽어 다른 줄과 무관 · hash 는 대상마다 한 번 = 옛 고리의 마지막 셈과 같다)
--     · 반환 items 는 jsonb_agg 한 번(옛 판은 줄마다 || · 16.7 s)
--     · 두 직원이 같이 눌러도 run 행 for update 가 차례를 세운다 — 뒤의 호출은 앞의 묶음이 끝난 뒤 「남은 것」만 본다(같은 줄 두 번 없음) · 미리 보기도 같은 잠금(잠깐)
--   ⚠ 조사에서 드러난 것(이 차수 밖 · 보고에): asung run 에 같은 IMS family 를 가리키는 link 줄이 셋(8 · 4 · 4 상품 · 전부 partial_family 1 변형) — apply 뒤 family 의 gid 는 마지막 handle 의 것 · 나머지 상품은 Shopify 에 그대로 남는다(보낼 때 중복) · plan 이 막아야 할 것(dup_target)
--   실측(시험 5회차 · 2026-10-27 21:19 · tests/link_perf_2.sql): 옛 한 번에 69.5 ~ 78.3 s → 묶음 500 × 10 회 · 묶음 최대 2.4 ~ 2.8 s(변형 수에 비례 · payload 몫) · 합 18 ~ 23 s · 새 정의 한 번에(p_limit null) 16 ~ 24 s(REST 8 s 는 여전히 넘는다 — 화면은 묶음으로) · 미리 보기 0.2 s · 끝 상태 md5 같음(shop_product · shop_variant · shop_listing · 줄 · run)
--   바꾸지 않은 것: 문(ims_require_write) · 상태 · version · 스토어 검사 · 자기 검사(push 큐 수 무변) · 재고 트리거 그대로(563 · live 전 스토어는 큐 0 · 815) · shop_link_plan · push_batch · remaining · 화면(ss v4a 가 p_limit 없이 부르면 전부 — 8 s 안에 못 끝나는 건 그대로라 화면 차수에서 묶음으로 바꾼다)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261027205600_link_perf_2.sql && supabase migration repair --status applied 20261027205600 --db-url "$(cat ~/.asung-testdb-url)"
--   시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261027205600_link_perf_2.sql -f supabase/tests/link_perf_2.sql
do $$
begin
  if coalesce((select value from public.inv_config where key = 'db_role'), '') <> 'test' then
    raise exception using errcode = 'WM501', message = 'STOP - inv_config.db_role is not test - this migration runs on the Asung-IMS project only. Nothing was changed.';
  end if;
end $$;

-- ═══ 1) 칸 하나 — 어느 판(version)에서 적용됐나 · 옛 시그니처를 내린다(같은 이름에 인자 수만 다른 둘이 남으면 PostgREST 가 고르지 못한다) ═══
alter table public.shop_link_item add column applied_version int;
comment on column public.shop_link_item.applied_version is 'link-perf-2(판정 829): 이 줄이 적용된 판의 shop_link_run.version — 「지금 차례」 = link · link_off 이고 applied_version 이 run.version 과 다른 줄 · 계획을 다시 하면 version 이 올라 전부 다시 차례가 된다(멱등)';
update public.shop_link_item i set applied_version = r.version from public.shop_link_run r where r.id = i.run_id and i.applied_at is not null;   -- 이미 적용된 run 의 줄(test 스토어 둘) — 그 run 의 지금 version
drop function if exists public.shop_link_apply(uuid, boolean, int);

-- ═══ 2) shop_link_apply(run, commit, version, limit) — 묶음 · 이어서 · 집합 ═══
create function public.shop_link_apply(p_run_id uuid, p_commit boolean default false, p_run_version int default null, p_limit int default null) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_run      public.shop_link_run%rowtype;
  v_s        public.shop_store%rowtype;
  it         record;
  v_q0       bigint;  v_q1 bigint;
  v_tot_link int;  v_tot_off int;  v_tot_var int;  v_skipped int;
  v_linked   int := 0;  v_off int := 0;  v_variants int := 0;  v_hash_n int := 0;  v_n int := 0;
  v_remain0  int;  v_remain1 int;
  v_list     jsonb;
  v_fams     uuid[];  v_pids uuid[];
  v_missing  text;
  v_now      timestamptz := now();
begin
  perform public.ims_require_write('shopify', 'saved');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  select * into v_run from public.shop_link_run where id = p_run_id for update;                      -- 차례(두 직원이 같이 눌러도 한 번에 하나 · 뒤의 호출은 앞의 묶음이 적힌 뒤 남은 것만 본다)
  if not found then raise exception 'Link run % not found — nothing was saved', p_run_id; end if;
  if v_run.status <> 'planned' then raise exception 'Link run % is % — only a planned run can be applied — nothing was saved', p_run_id, v_run.status; end if;
  if p_run_version is null or p_run_version <> v_run.version then
    raise exception 'The plan you looked at is version % but the run is now version % — plan again and look again — nothing was saved', coalesce(p_run_version::text, '(none)'), v_run.version;
  end if;
  if p_limit is not null and p_limit < 1 then raise exception 'p_limit must be null (everything) or 1 or more — nothing was saved'; end if;
  select * into v_s from public.shop_store where id = v_run.store_id;
  if not v_s.is_active then raise exception 'Store "%" is switched off — nothing was saved', v_s.code; end if;
  select count(*) into v_q0 from public.shop_push_queue q where q.store_id = v_s.id and q.done_at is null;

  -- 전체 숫자(묶음과 무관 · 미리 보기가 보여 주는 것)
  select count(*) filter (where i.decision = 'link'), count(*) filter (where i.decision = 'link_off'), count(*) filter (where i.decision not in ('link', 'link_off')),
         coalesce(sum(jsonb_array_length(i.variants)) filter (where i.decision in ('link', 'link_off')), 0),
         count(*) filter (where i.decision in ('link', 'link_off') and i.applied_version is distinct from v_run.version)
    into v_tot_link, v_tot_off, v_skipped, v_tot_var, v_remain0
    from public.shop_link_item i where i.run_id = p_run_id;

  -- 지금 차례인 줄: link · link_off 가운데 이 판(version)에서 아직 안 적용된 것 · (handle, gid) 순 · 미리 보기는 전부(숫자만 · 쓰기 0)
  create temp table if not exists t_link_todo (ord int primary key, id uuid, gid text, handle text, status text, decision text, family_id uuid, product_id uuid, variants jsonb, reasons text[], dup boolean) on commit drop;
  truncate t_link_todo;
  insert into t_link_todo (ord, id, gid, handle, status, decision, family_id, product_id, variants, reasons, dup)
  select x.ord, x.id, x.gid, x.handle, x.status, x.decision, x.family_id, x.product_id, x.variants, x.reasons,
         count(*) over (partition by coalesce(x.family_id, x.product_id)) > 1                      -- 같은 IMS 대상을 이 묶음 안에서 둘 이상이 가리킨다(순서가 뜻 · 줄마다)
    from (select row_number() over (order by i.handle, i.shopify_product_gid) as ord, i.id, i.shopify_product_gid as gid, i.handle, i.status, i.decision, i.ims_family_id as family_id, i.ims_product_id as product_id, i.variants, i.reasons
            from public.shop_link_item i
           where i.run_id = p_run_id and i.decision in ('link', 'link_off')
             and (not p_commit or i.applied_version is distinct from v_run.version)
           order by i.handle, i.shopify_product_gid
           limit (case when p_commit then p_limit end)) x;
  select count(*) into v_n from t_link_todo;
  select coalesce(jsonb_agg(jsonb_build_object('item_id', t.id, 'gid', t.gid, 'handle', t.handle, 'decision', t.decision, 'family_id', t.family_id, 'product_id', t.product_id,
                                               'variants', jsonb_array_length(t.variants), 'reasons', to_jsonb(t.reasons)) order by t.ord), '[]'::jsonb) into v_list from t_link_todo t;

  if p_commit then
    if exists (select 1 from t_link_todo t where t.family_id is null and t.product_id is null) then
      raise exception 'Link run %: a link row has no IMS target — plan again — nothing was saved', p_run_id;
    end if;
    -- ① listing(큐 없이) — link 는 켬 · link_off 는 끔(gid 만 · 558 · 562) · 대상이 이 묶음에서 한 번뿐인 줄은 집합 네 문장(AFTER STATEMENT 재고 트리거가 문장마다 돌아 줄마다 하면 500 줄에 1.4 s) · 대상이 겹치는 줄은 아래 고리에서 순서대로(뒤의 것이 이긴다 = 옛 고리) · 서로 다른 대상은 listing 행이 달라 순서가 뜻이 없다
    --   큐: 트리거는 문장마다 켜진 행의 구성원을 모아 shop_stock_queue_add(force) 한 번 — 묶음으로 모아도 같은 집합(한 제품이 두 대상에 들어가는 일은 plan 이 막는다 · family 구성원은 낱개로 못 잇는다 556) · live 전 스토어는 0 줄(815)
    update public.shop_listing l set is_on = true, turned_on_at = v_now, turned_on_by = v_staff, turned_off_at = null, turned_off_by = null, updated_by = v_staff
      from t_link_todo t where not t.dup and t.decision = 'link' and l.store_id = v_s.id and not l.is_on
       and ((t.family_id is not null and l.family_id = t.family_id) or (t.product_id is not null and l.product_id = t.product_id));
    insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, updated_by)
    select v_s.id, t.family_id, t.product_id, true, v_now, v_staff, v_staff from t_link_todo t
     where not t.dup and t.decision = 'link'
       and not exists (select 1 from public.shop_listing l where l.store_id = v_s.id and ((t.family_id is not null and l.family_id = t.family_id) or (t.product_id is not null and l.product_id = t.product_id)));
    update public.shop_listing l set is_on = false, turned_off_at = v_now, turned_off_by = v_staff, updated_by = v_staff
      from t_link_todo t where not t.dup and t.decision = 'link_off' and l.store_id = v_s.id and l.is_on
       and ((t.family_id is not null and l.family_id = t.family_id) or (t.product_id is not null and l.product_id = t.product_id));
    insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, turned_off_at, turned_off_by, updated_by)
    select v_s.id, t.family_id, t.product_id, false, v_now, v_staff, v_now, v_staff, v_staff from t_link_todo t
     where not t.dup and t.decision = 'link_off'
       and not exists (select 1 from public.shop_listing l where l.store_id = v_s.id and ((t.family_id is not null and l.family_id = t.family_id) or (t.product_id is not null and l.product_id = t.product_id)));

    for it in select * from t_link_todo t order by t.ord loop
      if it.decision = 'link' then v_linked := v_linked + 1; else v_off := v_off + 1; end if;
      v_variants := v_variants + jsonb_array_length(it.variants);
      -- ① 겹치는 대상만 줄마다(family / product 두 갈래 등호 · 유니크 색인)
      if not it.dup then null;
      elsif it.decision = 'link' then
        if it.family_id is not null then
          update public.shop_listing set is_on = true, turned_on_at = v_now, turned_on_by = v_staff, turned_off_at = null, turned_off_by = null, updated_by = v_staff
           where store_id = v_s.id and family_id = it.family_id and not is_on;
          if not found and not exists (select 1 from public.shop_listing l where l.store_id = v_s.id and l.family_id = it.family_id) then
            insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, updated_by) values (v_s.id, it.family_id, null, true, v_now, v_staff, v_staff);
          end if;
        else
          update public.shop_listing set is_on = true, turned_on_at = v_now, turned_on_by = v_staff, turned_off_at = null, turned_off_by = null, updated_by = v_staff
           where store_id = v_s.id and product_id = it.product_id and not is_on;
          if not found and not exists (select 1 from public.shop_listing l where l.store_id = v_s.id and l.product_id = it.product_id) then
            insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, updated_by) values (v_s.id, null, it.product_id, true, v_now, v_staff, v_staff);
          end if;
        end if;
      else
        if it.family_id is not null then
          update public.shop_listing set is_on = false, turned_off_at = v_now, turned_off_by = v_staff, updated_by = v_staff
           where store_id = v_s.id and family_id = it.family_id and is_on;
          if not found and not exists (select 1 from public.shop_listing l where l.store_id = v_s.id and l.family_id = it.family_id) then
            insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, turned_off_at, turned_off_by, updated_by) values (v_s.id, it.family_id, null, false, v_now, v_staff, v_now, v_staff, v_staff);
          end if;
        else
          update public.shop_listing set is_on = false, turned_off_at = v_now, turned_off_by = v_staff, updated_by = v_staff
           where store_id = v_s.id and product_id = it.product_id and is_on;
          if not found and not exists (select 1 from public.shop_listing l where l.store_id = v_s.id and l.product_id = it.product_id) then
            insert into public.shop_listing (store_id, family_id, product_id, is_on, turned_on_at, turned_on_by, turned_off_at, turned_off_by, updated_by) values (v_s.id, null, it.product_id, false, v_now, v_staff, v_now, v_staff, v_staff);
          end if;
        end if;
      end if;
      -- ② shop_product(같은 gid 면 last_pushed_at 은 그대로 · 새 gid 면 비운다)
      if it.family_id is not null then
        update public.shop_product sp set shopify_product_gid = it.gid, handle = it.handle, shopify_status = it.status, last_status = 'pending', last_error = null,
               last_pushed_at = case when sp.shopify_product_gid = it.gid then sp.last_pushed_at end, updated_by = v_staff
         where sp.store_id = v_s.id and sp.family_id = it.family_id;
      else
        update public.shop_product sp set shopify_product_gid = it.gid, handle = it.handle, shopify_status = it.status, last_status = 'pending', last_error = null,
               last_pushed_at = case when sp.shopify_product_gid = it.gid then sp.last_pushed_at end, updated_by = v_staff
         where sp.store_id = v_s.id and sp.product_id = it.product_id;
      end if;
      if not found then
        insert into public.shop_product (store_id, family_id, product_id, shopify_product_gid, handle, shopify_status, last_status, updated_by)
        values (v_s.id, it.family_id, it.product_id, it.gid, it.handle, it.status, 'pending', v_staff);
      end if;
    end loop;

    -- ③ shop_variant — 묶음의 변형 전부를 집합 한 번(SKU → 제품 · 정확히 · 없으면 lower(sku) 가 같은 것 가운데 order by sku limit 1 = 옛 고리와 같은 고르기 · 같은 제품이 둘이면 뒤의 줄이 이긴다 = 옛 고리)
    create temp table if not exists t_link_vv (ord int, vord int, sku text, vgid text, igid text, pid uuid) on commit drop;
    truncate t_link_vv;
    insert into t_link_vv (ord, vord, sku, vgid, igid, pid)
    select x.ord, x.vord, x.sku, x.vgid, x.igid, coalesce(pe.id, pl.id)
      from (select t.ord, v.ord as vord, nullif(trim(v.val->>'sku'), '') as sku, v.val->>'variant_gid' as vgid, nullif(v.val->>'inventory_item_gid', '') as igid
              from t_link_todo t cross join lateral jsonb_array_elements(t.variants) with ordinality v(val, ord)) x
      left join public.product pe on pe.sku = x.sku
      left join lateral (select p.id from public.product p where pe.id is null and x.sku is not null and lower(p.sku) = lower(x.sku) order by p.sku limit 1) pl on true;
    select v.sku into v_missing from t_link_vv v where v.pid is null order by v.ord, v.vord limit 1;
    if found then raise exception 'Link run %: SKU % is not in IMS any more — plan again — nothing was saved', p_run_id, v_missing; end if;
    update public.shop_variant sv set shopify_variant_gid = x.vgid, inventory_item_gid = x.igid, updated_by = v_staff
      from (select distinct on (v.pid) v.pid, v.vgid, v.igid from t_link_vv v order by v.pid, v.ord desc, v.vord desc) x
     where sv.store_id = v_s.id and sv.product_id = x.pid;
    insert into public.shop_variant (store_id, product_id, shopify_variant_gid, inventory_item_gid, updated_by)
    select v_s.id, x.pid, x.vgid, x.igid, v_staff
      from (select distinct on (v.pid) v.pid, v.vgid, v.igid from t_link_vv v order by v.pid, v.ord desc, v.vord desc) x
     where not exists (select 1 from public.shop_variant sv where sv.store_id = v_s.id and sv.product_id = x.pid);

    -- ④ hash — listing · gid 가 선 뒤의 payload(555 · 첫 drain · 새벽 맞추기가 skipped_same_hash) · 대상마다 한 번(payload 는 제 listing 만 읽는다)
    select coalesce(array_agg(distinct t.family_id), '{}'), coalesce(array_agg(distinct t.product_id), '{}') into v_fams, v_pids from t_link_todo t;
    update public.shop_product sp set last_hash = public.shop_product_payload(v_s.id, sp.family_id, null)->>'hash' where sp.store_id = v_s.id and sp.family_id = any(v_fams);
    get diagnostics v_hash_n = row_count;
    update public.shop_product sp set last_hash = public.shop_product_payload(v_s.id, null, sp.product_id)->>'hash' where sp.store_id = v_s.id and sp.product_id = any(v_pids);
    get diagnostics v_n = row_count;
    v_hash_n := v_hash_n + v_n;
    update public.shop_link_item i set applied_at = v_now, applied_version = v_run.version, updated_by = v_staff from t_link_todo t where i.id = t.id;

    select count(*) into v_q1 from public.shop_push_queue q where q.store_id = v_s.id and q.done_at is null;
    if v_q1 <> v_q0 then raise exception 'Link run %: a product push was queued while linking (% → %) — linking must not send — nothing was saved', p_run_id, v_q0, v_q1; end if;   -- 자기 검사(이견 3)
    select count(*) into v_remain1 from public.shop_link_item i where i.run_id = p_run_id and i.decision in ('link', 'link_off') and i.applied_version is distinct from v_run.version;
    if v_remain1 = 0 then
      update public.shop_link_run set status = 'applied', applied_at = v_now, applied_by = v_staff, updated_by = v_staff where id = p_run_id;
    end if;
  else
    v_linked := v_tot_link; v_off := v_tot_off; v_variants := v_tot_var; v_remain1 := v_remain0;
  end if;
  return jsonb_build_object('committed', p_commit, 'run_id', p_run_id, 'store_code', v_s.code, 'version', v_run.version, 'limit', p_limit,
                            'linked', v_linked, 'linked_off', v_off, 'skipped', v_skipped, 'variants', v_variants, 'hash_seeded', case when p_commit then v_hash_n else 0 end,
                            'total_linked', v_tot_link, 'total_linked_off', v_tot_off, 'total_variants', v_tot_var,
                            'remaining', v_remain1, 'done', (p_commit and v_remain1 = 0),
                            'push_queue_open', v_q0, 'stock_queue_open', (select count(*) from public.shop_stock_queue q where q.store_id = v_s.id and q.done_at is null),
                            'items', v_list);
end;
$$;
revoke all on function public.shop_link_apply(uuid, boolean, int, int) from public, anon;
grant execute on function public.shop_link_apply(uuid, boolean, int, int) to authenticated, service_role;
comment on function public.shop_link_apply(uuid, boolean, integer, integer) is 'link-1a(판정 555 · 558 · 562 · 563) — planned 판을 실행(사람이 본 version 만 · 미리 보기는 쓰기 0): link · link_off 줄마다 ① shop_listing(link 켬 · link_off 끔 · 큐 없음) ② shop_product(gid · handle · status · pending) ③ shop_variant(변형 gid · inventory_item_gid) ④ 그 순간의 shop_product_payload hash 를 last_hash 에(첫 drain · 새벽이 건너뛴다 · 보내기는 shop_link_push_batch 로 사람이 묶음씩) · 자기 검사 = 그 스토어 열린 push 큐 수 무변 · 재고 트리거는 그대로(563) · ⭐ link-perf-2(판정 829 · 2026-10-27): p_limit 로 묶음(null = 전부) — 지금 차례 = link · link_off 가운데 이 판에서 아직 안 적용된 줄(applied_version ≠ run.version) (handle, gid) 순 · 반환 remaining · done · total_* · 남은 것이 0 이 되는 호출이 run 을 applied 로 · 계획을 다시 하면 version 검사가 막고 새 version 은 처음부터 · run 행 for update 가 차례 · ③ ④ 는 집합(5,079 상품 73.6 s → 묶음 500 이 3 s 안 · 결과 같다 · 시험 supabase/tests/link_perf_2.sql)';

-- ═══ 착지 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_n int;
begin
  select count(*) into v_n from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_link_apply';
  if v_n <> 1 then v_bad := v_bad || format(' shop_link_apply_count_%s', v_n); end if;
  if (select pg_get_function_identity_arguments(p.oid) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_link_apply') <> 'p_run_id uuid, p_commit boolean, p_run_version integer, p_limit integer' then v_bad := v_bad || ' signature'; end if;
  if not (select p.prosrc ~ 't_link_todo' and p.prosrc ~ 't_link_vv' and p.prosrc ~ 'applied_version' and p.prosrc !~ 'is not distinct from' from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'shop_link_apply') then v_bad := v_bad || ' body'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'shop_link_item' and column_name = 'applied_version') <> 1 then v_bad := v_bad || ' column'; end if;
  if exists (select 1 from public.shop_link_item i where i.applied_at is not null and i.applied_version is null) then v_bad := v_bad || ' backfill'; end if;
  if has_function_privilege('anon', 'public.shop_link_apply(uuid, boolean, int, int)', 'execute') or not has_function_privilege('authenticated', 'public.shop_link_apply(uuid, boolean, int, int)', 'execute') then v_bad := v_bad || ' grants'; end if;
  if v_bad <> '' then raise exception 'link-perf-2 landing check failed:%', v_bad; end if;
end $$;
