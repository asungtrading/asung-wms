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
-- ═══ ldfix-1c2 — 공급처 켜짐 표식 supplier.is_active_source(판정 683) + 기본 공급처 재계산 함수(판정 682 · 미룬 317) (2026-10-24) ═══
--   ① supplier.is_active_source text — null(아무도 안 정함) · cin7 · ims(IMS 창구가 켜거나 껐다 · 적재가 몇 번 지나가도 남는다 · 적재는 ims 행의 is_active 를 IMS 값으로 싣는다 — 판정 680 의 updated_by 기준을 이 칸으로)
--   ② product_supplier_default_recalc(p_product_ids uuid[] default null) — po-module §3-g 「is_default 재계산 — 끄고 나서 켠다」 ① 끄기(줄 · 공급처 비활성 · manual 보호 없음) → ② 켜기(기본 없는 제품 · 활성 공급처 줄만 · 동점 · 날짜 없음은 비워 둠 · manual 줄 있는 제품은 건드리지 않음)
--      null 이면 전체 · 반환 {turned_off, turned_on, multi_default_products, scope} · 멱등(둘째 실행은 0) · definer · 권한 service_role 만(적재 REST rpc · 판정 615) · supplier_update 는 소유자로 부른다
--   ③ supplier_update 재발행 — 원본 20261005164835_master_cs_3.sql 668 ~ 945 행 바이트 그대로 · 바뀐 줄 2 + 더한 줄 2(선언 · is_active 갈래 is_active_source='ims' + 재계산 대상 모음 · commit 끝 그 공급처 제품만 재계산 · 반환에 default_recalc) · 옛 본문 md5 d63f61daa31bbab66147ffab2bacbe4c → 새 6e26a069b0567783cdb77bd086f9e410 · 서명 같음 · ACL · comment 유지
--   ④ 채우기 — source=cin7 이면서 updated_by 가 있는 5 곳(Airalo · ALLDAY LOCKS · Energizer Canada · P&G · US Supplier = 판정 680 이 지키던 범위)에 'ims' · ⚠️ supplier_touch 를 채우기 문장 앞뒤로만 끈다(updated_by · updated_at 보존 — 672 목록에서 빠지지 않게 · 같은 트랜잭션 · 잠금은 ① 의 ACCESS EXCLUSIVE 안) · 바뀐 행이 5 가 아니면 멈춤
--   ⑤ 착지 — 칸 · CHECK · 함수 ACL · supplier_update 새 md5 · 채우기 5(updated_by 그대로) · 트리거 다시 켜짐(tgenabled O) · 기본 둘 이상 0
--   적재 코드(ImsLoadSupplier.gs · ImsLoadProductSupplier.gs)는 같은 차수가 고친다 · 새 표 · 시퀀스 0 · 화면 무변(suppliers.html 은 반환의 committed · blocks · unacked 만 읽는다)

-- ═══ 1) 칸 — 판정 683 ═══
alter table public.supplier add column if not exists is_active_source text;
alter table public.supplier drop constraint if exists supplier_is_active_source_ck;
alter table public.supplier add constraint supplier_is_active_source_ck check (is_active_source is null or is_active_source in ('cin7', 'ims'));
comment on column public.supplier.is_active_source is '⭐ 판정 683(ldfix-1c2 · 2026-10-24) — 이 공급처의 켜짐(is_active)을 누가 정했나: ims(창구 supplier_update 가 켜거나 껐다 · 적재 ImsLoadSupplier.gs 는 이 행의 is_active 를 IMS 값으로 싣는다 · 몇 번 적재해도 남는다) · cin7(쓰지 않음 · 자리만) · null(아무도 안 정함 — Cin7 값을 따른다) · 채우기 5 곳(2026-10-24 · updated_by 있던 cin7 행) · sellable_source 와 같은 꼴';

-- ═══ 2) 기본 공급처 재계산 — 판정 682 · 미룬 317 · po-module §3-g ① ② 그대로 ═══
create or replace function public.product_supplier_default_recalc(p_product_ids uuid[] default null) returns jsonb
language plpgsql volatile security definer set search_path = public, pg_temp as $$
-- ldfix-1c2: 기본 공급처(product_supplier.is_default) 재계산 — ① 자격을 잃은 기본을 끈다(줄이 비활성 · 공급처가 비활성 · manual 보호 없음) ② 기본이 없는 제품에만 켠다(활성 공급처의 활성 줄 · 가장 최근 공급 · 동점 · 날짜 없음은 비워 둔다 · manual 줄이 있는 제품은 건드리지 않는다)
--   p_product_ids null = 전체(적재 끝 · 12,738 줄) · 아니면 그 제품만(supplier_update 가 켜고 끈 공급처의 제품) · 멱등 · ims_touch 가 updated_by 를 비운다(적재 결)
declare
  v_off int := 0;  v_on int := 0;  v_multi int := 0;
begin
  -- ① 자격을 잃은 것을 끈다 (줄이 비활성 · 공급처가 비활성) — manual 보호 없음
  update public.product_supplier ps
     set is_default = false
    from public.supplier s
   where s.id = ps.supplier_id
     and ps.is_default
     and (not ps.is_active or not s.is_active)
     and (p_product_ids is null or ps.product_id = any(p_product_ids));
  get diagnostics v_off = row_count;
  -- ② 기본이 없는 제품에만 켠다 (활성 공급처 줄만 후보 · 동점·날짜없음은 비워 두고 센다 · manual 줄이 있는 제품은 건드리지 않는다)
  with cand as (
    select ps.id, ps.product_id, ps.last_supplied,
           count(*) over (partition by ps.product_id) as n,
           rank()   over (partition by ps.product_id order by ps.last_supplied desc nulls last) as rk,
           count(*) over (partition by ps.product_id, ps.last_supplied) as tie
      from public.product_supplier ps
      join public.supplier s on s.id = ps.supplier_id
     where ps.is_active and s.is_active
       and (p_product_ids is null or ps.product_id = any(p_product_ids))
       and not exists (select 1 from public.product_supplier m where m.product_id = ps.product_id and m.source = 'manual')
       and not exists (select 1 from public.product_supplier d where d.product_id = ps.product_id and d.is_default)
  )
  update public.product_supplier ps
     set is_default = true
    from cand
   where ps.id = cand.id and cand.rk = 1
     and (cand.n = 1 or (cand.last_supplied is not null and cand.tie = 1));
  get diagnostics v_on = row_count;
  select count(*) into v_multi
    from (select d.product_id from public.product_supplier d where d.is_default and (p_product_ids is null or d.product_id = any(p_product_ids)) group by d.product_id having count(*) > 1) x;
  return jsonb_build_object('turned_off', v_off, 'turned_on', v_on, 'multi_default_products', v_multi,
                            'scope', case when p_product_ids is null then 'all' else cardinality(p_product_ids)::text || ' products' end);
end $$;
revoke all on function public.product_supplier_default_recalc(uuid[]) from public, anon, authenticated;
grant execute on function public.product_supplier_default_recalc(uuid[]) to service_role;
comment on function public.product_supplier_default_recalc(uuid[]) is 'ldfix-1c2 · 판정 682 · 미룬 317 — 기본 공급처 재계산(po-module §3-g ① 끄기 → ② 켜기 · 멱등) · p_product_ids null = 전체 · 반환 {turned_off, turned_on, multi_default_products, scope} · 부르는 곳 = 적재 끝(ImsLoadSupplier.gs · ImsLoadProductSupplier.gs · service_role rpc) · supplier_update 의 is_active 갈래(그 공급처 제품만 · 소유자로) · definer · 권한 service_role 만';

-- ═══ 3) supplier_update 재발행 — 바뀐 줄 2 · 더한 줄 2 ═══
create or replace function public.supplier_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff   uuid;
  v_master  boolean;
  v_blocks  jsonb := '[]'::jsonb;
  v_warns   jsonb := '[]'::jsonb;
  v_changes jsonb := '[]'::jsonb;
  v_recalc  uuid[] := '{}';   v_recalc_out jsonb := null;   -- ldfix-1c2 · 판정 682 · 683: 켜고 끈 공급처 → 그 제품들의 기본 공급처 재계산
  v_money   text[] := array['currency_id', 'payment_term_id', 'account_payable_id', 'tax_rule', 'is_active'];
  v_general text[] := array['name', 'note', 'is_purchasable', 'is_discontinued', 'discontinued_on'];
  v_afields text[] := array['type', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country'];
  v_cfields text[] := array['name', 'phone', 'mobile_phone', 'fax', 'email', 'website'];
  v_mops    text[] := array['discount_add', 'discount_set', 'discount_off'];
  v_n       int;
  v_i       int := 0;
  v_c       jsonb;
  v_op      text;
  v_field   text;
  v_sid     uuid;
  v_key     text;
  v_sup     public.supplier%rowtype;
  v_cur     text;
  v_new     text;
  v_seen    text[] := '{}';
  v_touched uuid[] := '{}';
  v_money_s uuid[] := '{}';
  v_a       public.supplier_address%rowtype;
  v_ct      public.supplier_contact%rowtype;
  v_dsc     public.supplier_discount%rowtype;
  v_vals    jsonb;
  v_olds    jsonb;
  v_f       text;
  v_folded  text;
  v_open_po int;
  v_open_inv int;
  v_prods   int;
  v_forms   int;
  v_pct     numeric;
  v_keys    text[];
  v_unacked text[];
  v_rid     uuid;
  v_newdef  text[] := '{}';
begin
  if not (public.ims_can_write('purchasing') or public.ims_can_write('master')) then
    raise exception 'You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then raise exception 'p_changes must be a JSON array of changes — nothing was saved'; end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 1000 then raise exception 'Too many changes in one call (% — the limit is 1,000) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_op := v_c->>'op';
    if v_op is null or v_op not in ('set', 'discount_add', 'discount_set', 'discount_off', 'address_add', 'address_set', 'address_off', 'contact_add', 'contact_set', 'contact_off', 'contact_default') then
      raise exception 'Unknown op % — one of set · discount_add · discount_set · discount_off · address_add · address_set · address_off · contact_add · contact_set · contact_off · contact_default — nothing was saved', coalesce(v_op, '(blank)');
    end if;
    if v_op = 'contact_add' and coalesce((v_c->'values'->>'is_default')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'supplier_id', '')); end if;
    if v_op = 'contact_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'supplier_id', '')); end if;
  end loop;

  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_sid := nullif(v_c->>'supplier_id', '')::uuid; v_key := coalesce(v_sid::text, '(blank)');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'supplier_id', v_sid, 'op', v_op, 'field', v_field, 'applied', false);
    select * into v_sup from public.supplier s where s.id = v_sid;
    if v_sid is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':supplier_unknown', 'supplier_id', v_sid, 'code', 'supplier_unknown', 'message', format('Change %s: the supplier does not exist — nothing was saved', v_i)); continue;
    end if;
    v_touched := array_append(v_touched, v_sid);
    v_vals := coalesce(v_c->'values', '{}'::jsonb); v_olds := coalesce(v_c->'olds', '{}'::jsonb);

    if v_op = 'set' then
      if v_field is null or not (v_field = any(v_general) or v_field = any(v_money)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(blank)'), 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: field %s cannot be changed here — nothing was saved', v_sup.name, coalesce(v_field, '(blank)'))); continue;
      end if;
      if (v_key || ':' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s %s is changed twice in this call — keep one — nothing was saved', v_sup.name, v_field)); continue;
      end if;
      v_seen := array_append(v_seen, v_key || ':' || v_field);
      if v_field = any(v_money) and not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_field, 'supplier_id', v_sid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change %s of %s — nothing was saved', v_field, v_sup.name)); continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s %s: the old value the screen saw is missing — nothing was saved', v_sup.name, v_field)); continue;
      end if;
      v_cur := case v_field when 'name' then v_sup.name when 'note' then v_sup.note when 'is_purchasable' then v_sup.is_purchasable::text when 'is_discontinued' then v_sup.is_discontinued::text when 'discontinued_on' then v_sup.discontinued_on::text
                            when 'currency_id' then v_sup.currency_id::text when 'payment_term_id' then v_sup.payment_term_id::text when 'account_payable_id' then v_sup.account_payable_id::text when 'tax_rule' then v_sup.tax_rule when 'is_active' then v_sup.is_active::text end;
      if (case when v_field in ('is_purchasable', 'is_discontinued', 'is_active') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean) else (v_cur is distinct from nullif(v_c->>'old', '')) end) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of %s (now "%s") — check again — nothing was saved', v_field, v_sup.name, coalesce(v_cur, ''))); continue;
      end if;
      v_new := nullif(btrim(v_c->>'value'), '');
      if v_field = 'name' then
        if v_new is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'supplier_id', v_sid, 'code', 'name_missing', 'message', format('%s cannot have an empty name — nothing was saved', v_sup.name));
        else
          v_folded := lower(regexp_replace(v_new, '\s+', ' ', 'g'));
          if exists (select 1 from public.supplier s where s.id <> v_sid and lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = v_folded) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_exists', 'supplier_id', v_sid, 'code', 'name_exists', 'message', format('A supplier named "%s" already exists — the name is the key — nothing was saved', v_new));
          end if;
          v_warns := v_warns || jsonb_build_object('key', v_key || ':rename_sync_cin7', 'supplier_id', v_sid, 'code', 'rename_sync_cin7', 'message', format('Renaming %s to "%s": Cin7 refers to suppliers by name — rename it in Cin7 too (Cin7 first while both systems run). Confirm', v_sup.name, v_new));
        end if;
      elsif v_field in ('is_discontinued', 'is_active') then
        if v_new is null or v_new not in ('true', 'false') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_field, 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s %s must be true or false — nothing was saved', v_sup.name, v_field));
        elsif v_field = 'is_active' and v_new = 'false' then
          select count(*) into v_open_po from public.po p where p.supplier_id = v_sid and p.status in ('draft', 'confirmed');
          select count(*) into v_open_inv from public.po_invoice i where i.supplier_id = v_sid and i.status in ('draft', 'confirmed') and i.total_amount > coalesce((select sum(l.amount) from public.po_payment_alloc l where l.po_invoice_id = i.id), 0);
          select count(*) into v_prods from public.product_supplier ps where ps.supplier_id = v_sid and ps.is_active;
          select count(*) into v_forms from public.price_formula f where f.supplier_id = v_sid;
          if v_open_po > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_po', 'supplier_id', v_sid, 'code', 'inactive_open_po', 'count', v_open_po, 'message', format('%s has %s open purchase order(s) — they keep running. Confirm to deactivate', v_sup.name, v_open_po)); end if;
          if v_open_inv > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_invoice', 'supplier_id', v_sid, 'code', 'inactive_open_invoice', 'count', v_open_inv, 'message', format('%s has %s supplier invoice(s) not fully paid — confirm to deactivate', v_sup.name, v_open_inv)); end if;
          if v_prods > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_products', 'supplier_id', v_sid, 'code', 'inactive_products', 'count', v_prods, 'message', format('%s is linked to %s product(s) (supplier lines stay) — confirm to deactivate', v_sup.name, v_prods)); end if;
          if v_forms > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_formulas', 'supplier_id', v_sid, 'code', 'inactive_formulas', 'count', v_forms, 'message', format('%s has %s price formula(s) — confirm to deactivate', v_sup.name, v_forms)); end if;
        end if;
      elsif v_field = 'is_purchasable' then
        if v_new is not null and v_new not in ('true', 'false') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_purchasable', 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s: is_purchasable must be true, false or empty (not decided) — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'discontinued_on' then
        if v_new is not null and v_new !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:discontinued_on', 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s: discontinued_on must be a date (YYYY-MM-DD) or empty — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'payment_term_id' then
        if v_new is null or not exists (select 1 from public.ref_payment_term t where t.id = v_new::uuid and t.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':payment_term_invalid', 'supplier_id', v_sid, 'code', 'payment_term_invalid', 'message', format('%s: the payment term does not exist or is inactive — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'account_payable_id' then
        if v_new is null or not exists (select 1 from public.ref_account a where a.id = v_new::uuid and a.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':account_invalid', 'supplier_id', v_sid, 'code', 'account_invalid', 'message', format('%s: the payable account does not exist or is inactive — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'currency_id' then
        if v_new is null or not exists (select 1 from public.ref_currency r where r.id = v_new::uuid and r.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_invalid', 'supplier_id', v_sid, 'code', 'currency_invalid', 'message', format('%s: the currency does not exist or is inactive — nothing was saved', v_sup.name));
        elsif ((select r.code from public.ref_currency r where r.id = v_new::uuid) = 'USD') <> (coalesce((select a.name from public.ref_account a where a.id = v_sup.account_payable_id), '') ilike '%USD%') then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':currency_account_mismatch', 'supplier_id', v_sid, 'code', 'currency_account_mismatch', 'message', format('%s: the payable account %s may not match the new currency — check it. Confirm', v_sup.name, coalesce(v_sup.account_payable_code, '?')));
        end if;
      end if;
      if v_field = any(v_money) and v_field <> 'is_active' then v_money_s := array_append(v_money_s, v_sid); end if;

    elsif v_op = any(v_mops) then
      if not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_op, 'supplier_id', v_sid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change the discounts of %s — nothing was saved', v_sup.name)); continue;
      end if;
      if v_op = 'discount_add' then
        v_pct := case when (v_vals->>'percent') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (v_vals->>'percent')::numeric end;
        if nullif(btrim(v_vals->>'name'), '') is null or v_pct is null or v_pct > 100 then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid:' || v_i, 'supplier_id', v_sid, 'code', 'discount_invalid', 'message', format('%s: a discount needs a name and a percent from 0 to 100 — nothing was saved', v_sup.name)); end if;
      else
        select * into v_dsc from public.supplier_discount d where d.id = nullif(v_c->>'discount_id', '')::uuid and d.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'discount_unknown', 'message', format('%s: that discount line is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':discount:' || v_dsc.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:discount:' || v_dsc.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same discount line is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':discount:' || v_dsc.id::text);
        if v_op = 'discount_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if v_f not in ('name', 'percent') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:discount.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: discount field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:discount.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: discount %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            if (case when v_f = 'percent' then (v_dsc.percent is distinct from nullif(v_olds->>v_f, '')::numeric) else (v_dsc.name is distinct from nullif(v_olds->>v_f, '')) end) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:discount.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the discount %s of %s — check again — nothing was saved', v_f, v_sup.name));
            end if;
          end loop;
          if v_vals ? 'percent' and not ((v_vals->>'percent') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' and (v_vals->>'percent')::numeric <= 100) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid:' || v_i, 'supplier_id', v_sid, 'code', 'discount_invalid', 'message', format('%s: percent must be 0 to 100 — nothing was saved', v_sup.name)); end if;
        elsif v_op = 'discount_off' and not v_dsc.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'discount_inactive', 'message', format('%s: that discount line is already off — nothing was saved', v_sup.name));
        end if;
      end if;
      v_money_s := array_append(v_money_s, v_sid);

    elsif v_op like 'address_%' then
      if v_op = 'address_add' then
        if nullif(btrim(coalesce(v_vals->>'line1', '') || coalesce(v_vals->>'city', '') || coalesce(v_vals->>'postal_code', '')), '') is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_empty:' || v_i, 'supplier_id', v_sid, 'code', 'address_empty', 'message', format('%s: the new address has no street, city or postal code — nothing was saved', v_sup.name)); end if;
      else
        select * into v_a from public.supplier_address a where a.id = nullif(v_c->>'address_id', '')::uuid and a.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'address_unknown', 'message', format('%s: that address is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':address:' || v_a.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:address:' || v_a.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same address is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':address:' || v_a.id::text);
        if v_op = 'address_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_afields)) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:address.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: address field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:address.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: address %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            v_cur := case v_f when 'type' then v_a.type when 'line1' then v_a.line1 when 'line2' then v_a.line2 when 'city' then v_a.city when 'state_province' then v_a.state_province when 'postal_code' then v_a.postal_code else v_a.country end;
            if v_cur is distinct from nullif(v_olds->>v_f, '') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:address.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the address %s of %s (now "%s") — check again — nothing was saved', v_f, v_sup.name, coalesce(v_cur, ''))); end if;
          end loop;
        elsif v_op = 'address_off' and not v_a.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'address_inactive', 'message', format('%s: that address is already off — nothing was saved', v_sup.name));
        end if;
      end if;

    else
      if v_op = 'contact_add' then
        if nullif(btrim(coalesce(v_vals->>'name', '') || coalesce(v_vals->>'phone', '') || coalesce(v_vals->>'mobile_phone', '') || coalesce(v_vals->>'email', '')), '') is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_empty:' || v_i, 'supplier_id', v_sid, 'code', 'contact_empty', 'message', format('%s: the new contact has no name, phone or email — nothing was saved', v_sup.name)); end if;
      else
        select * into v_ct from public.supplier_contact k where k.id = nullif(v_c->>'contact_id', '')::uuid and k.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'contact_unknown', 'message', format('%s: that contact is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':contact:' || v_ct.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:contact:' || v_ct.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same contact is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':contact:' || v_ct.id::text);
        if v_op = 'contact_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_cfields)) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:contact.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: contact field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:contact.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: contact %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            v_cur := case v_f when 'name' then v_ct.name when 'phone' then v_ct.phone when 'mobile_phone' then v_ct.mobile_phone when 'fax' then v_ct.fax when 'email' then v_ct.email else v_ct.website end;
            if v_cur is distinct from nullif(v_olds->>v_f, '') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:contact.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the contact %s of %s (now "%s") — check again — nothing was saved', v_f, v_sup.name, coalesce(v_cur, ''))); end if;
          end loop;
        elsif v_op = 'contact_off' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'contact_inactive', 'message', format('%s: that contact is already off — nothing was saved', v_sup.name));
          elsif v_ct.is_default and not (v_key = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':contact_default_off', 'supplier_id', v_sid, 'code', 'contact_default_off', 'message', format('%s: this is the default contact — switching it off leaves no default (po_create will warn contact_unset). Confirm', v_sup.name)); end if;
        elsif v_op = 'contact_default' and not v_ct.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'contact_inactive', 'message', format('%s: an inactive contact cannot be the default — switch it on first — nothing was saved', v_sup.name));
        end if;
      end if;
    end if;
  end loop;

  for v_sid in select distinct u from unnest(v_money_s) as u loop
    select count(*), max(s.name) into v_open_po, v_cur from public.po p join public.supplier s on s.id = p.supplier_id where p.supplier_id = v_sid and p.status in ('draft', 'confirmed');
    if v_open_po > 0 then v_warns := v_warns || jsonb_build_object('key', v_sid::text || ':open_po_keep_old', 'supplier_id', v_sid, 'code', 'open_po_keep_old', 'count', v_open_po, 'message', format('%s has %s open purchase order(s) — they keep the old terms; only new orders get the change. Confirm', v_cur, v_open_po)); end if;
  end loop;

  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  begin
    perform 1 from public.supplier s where s.id = any(v_touched) for update;
    v_i := 0;
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_sid := (v_c->>'supplier_id')::uuid; v_new := nullif(btrim(v_c->>'value'), ''); v_vals := coalesce(v_c->'values', '{}'::jsonb);
      if v_op = 'set' then
        case v_field
          when 'name' then update public.supplier set name = v_new, updated_by = v_staff where id = v_sid;
          when 'note' then update public.supplier set note = v_new, updated_by = v_staff where id = v_sid;
          when 'is_purchasable' then update public.supplier set is_purchasable = v_new::boolean, updated_by = v_staff where id = v_sid;
          when 'is_discontinued' then update public.supplier set is_discontinued = v_new::boolean, discontinued_on = case when v_new::boolean then coalesce(discontinued_on, public.ims_today()) else null end, updated_by = v_staff where id = v_sid;
          when 'discontinued_on' then update public.supplier set discontinued_on = v_new::date, updated_by = v_staff where id = v_sid;
          when 'currency_id' then update public.supplier set currency_id = v_new::uuid, updated_by = v_staff where id = v_sid;
          when 'payment_term_id' then update public.supplier set payment_term_id = v_new::uuid, payment_term_name = (select t.name from public.ref_payment_term t where t.id = v_new::uuid), updated_by = v_staff where id = v_sid;
          when 'account_payable_id' then update public.supplier set account_payable_id = v_new::uuid, account_payable_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_sid;
          when 'tax_rule' then update public.supplier set tax_rule = v_new, updated_by = v_staff where id = v_sid;
          when 'is_active' then update public.supplier set is_active = v_new::boolean, is_active_source = 'ims', updated_by = v_staff where id = v_sid; v_recalc := array_append(v_recalc, v_sid);   -- ldfix-1c2 · 판정 683: IMS 가 켜고 끈 표식(적재가 지킨다) · 682: 재계산 대상
        end case;
      elsif v_op = 'discount_add' then
        insert into public.supplier_discount (supplier_id, name, percent, seq, source, updated_by)
        values (v_sid, btrim(v_vals->>'name'), (v_vals->>'percent')::numeric, (select coalesce(max(d.seq), 0) + 1 from public.supplier_discount d where d.supplier_id = v_sid), 'manual', v_staff) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'discount_set' then
        update public.supplier_discount d set name = case when v_vals ? 'name' then btrim(v_vals->>'name') else d.name end, percent = case when v_vals ? 'percent' then (v_vals->>'percent')::numeric else d.percent end, updated_by = v_staff where d.id = (v_c->>'discount_id')::uuid;
      elsif v_op = 'discount_off' then
        update public.supplier_discount set is_active = false, updated_by = v_staff where id = (v_c->>'discount_id')::uuid;
      elsif v_op = 'address_add' then
        insert into public.supplier_address (supplier_id, source, updated_by, type, line1, line2, city, state_province, postal_code, country)
        values (v_sid, 'manual', v_staff, nullif(btrim(v_vals->>'type'), ''), nullif(btrim(v_vals->>'line1'), ''), nullif(btrim(v_vals->>'line2'), ''), nullif(btrim(v_vals->>'city'), ''), nullif(btrim(v_vals->>'state_province'), ''), nullif(btrim(v_vals->>'postal_code'), ''), nullif(btrim(v_vals->>'country'), '')) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'address_set' then
        update public.supplier_address a set
          type = case when v_vals ? 'type' then nullif(btrim(v_vals->>'type'), '') else a.type end, line1 = case when v_vals ? 'line1' then nullif(btrim(v_vals->>'line1'), '') else a.line1 end, line2 = case when v_vals ? 'line2' then nullif(btrim(v_vals->>'line2'), '') else a.line2 end,
          city = case when v_vals ? 'city' then nullif(btrim(v_vals->>'city'), '') else a.city end, state_province = case when v_vals ? 'state_province' then nullif(btrim(v_vals->>'state_province'), '') else a.state_province end,
          postal_code = case when v_vals ? 'postal_code' then nullif(btrim(v_vals->>'postal_code'), '') else a.postal_code end, country = case when v_vals ? 'country' then nullif(btrim(v_vals->>'country'), '') else a.country end, updated_by = v_staff
        where a.id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_off' then
        update public.supplier_address set is_active = false, updated_by = v_staff where id = (v_c->>'address_id')::uuid;
      elsif v_op = 'contact_add' then
        if coalesce((v_vals->>'is_default')::boolean, false) then update public.supplier_contact set is_default = false, updated_by = v_staff where supplier_id = v_sid and is_default; end if;
        insert into public.supplier_contact (supplier_id, source, updated_by, name, phone, mobile_phone, fax, email, website, is_default)
        values (v_sid, 'manual', v_staff, nullif(btrim(v_vals->>'name'), ''), nullif(btrim(v_vals->>'phone'), ''), nullif(btrim(v_vals->>'mobile_phone'), ''), nullif(btrim(v_vals->>'fax'), ''), nullif(btrim(v_vals->>'email'), ''), nullif(btrim(v_vals->>'website'), ''), coalesce((v_vals->>'is_default')::boolean, false)) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'contact_set' then
        update public.supplier_contact k set
          name = case when v_vals ? 'name' then nullif(btrim(v_vals->>'name'), '') else k.name end, phone = case when v_vals ? 'phone' then nullif(btrim(v_vals->>'phone'), '') else k.phone end, mobile_phone = case when v_vals ? 'mobile_phone' then nullif(btrim(v_vals->>'mobile_phone'), '') else k.mobile_phone end,
          fax = case when v_vals ? 'fax' then nullif(btrim(v_vals->>'fax'), '') else k.fax end, email = case when v_vals ? 'email' then nullif(btrim(v_vals->>'email'), '') else k.email end, website = case when v_vals ? 'website' then nullif(btrim(v_vals->>'website'), '') else k.website end, updated_by = v_staff
        where k.id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_off' then
        update public.supplier_contact set is_active = false, is_default = false, updated_by = v_staff where id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_default' then
        update public.supplier_contact k set is_default = (k.id = (v_c->>'contact_id')::uuid), updated_by = v_staff where k.supplier_id = v_sid and k.is_active and (k.is_default or k.id = (v_c->>'contact_id')::uuid);
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'A name or default would collide (%) — check the supplier name and keep one default contact — nothing was saved', coalesce(sqlerrm, '');
  end;
  if cardinality(v_recalc) > 0 then v_recalc_out := public.product_supplier_default_recalc(array(select distinct ps.product_id from public.product_supplier ps where ps.supplier_id = any(v_recalc))); end if;   -- ldfix-1c2 · 판정 682: 그 공급처의 제품만(§3-g ① 끄기 → ② 켜기)
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'default_recalc', v_recalc_out);
end;
$$;

-- ═══ 4) 채우기 — updated_by 있던 cin7 공급처 5 곳 → ims (supplier_touch 를 이 문장 앞뒤로만 끈다 · updated_by · updated_at 보존) ═══
alter table public.supplier disable trigger supplier_touch;
do $$
declare v_n int;
begin
  update public.supplier set is_active_source = 'ims' where source = 'cin7' and updated_by is not null and is_active_source is null;
  get diagnostics v_n = row_count;
  if v_n <> 5 then raise exception 'ldfix-1c2 backfill: expected 5 rows (cin7 suppliers touched in IMS), got % — nothing was changed', v_n; end if;
  raise notice 'ldfix-1c2 backfill: is_active_source = ims on 5 rows (Airalo · ALLDAY LOCKS · Energizer Canada · P&G · US Supplier · updated_by kept)';
end $$;
alter table public.supplier enable trigger supplier_touch;

-- ═══ 착지 ═══
do $$
declare v_ck text;  v_acl text;  v_md5 text;  v_n int;  v_tg char;  v_multi int;
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'supplier' and column_name = 'is_active_source') then raise exception 'ldfix-1c2 landing: column missing'; end if;
  select pg_get_constraintdef(oid) into v_ck from pg_constraint where conname = 'supplier_is_active_source_ck';
  if v_ck <> $q$CHECK (((is_active_source IS NULL) OR (is_active_source = ANY (ARRAY['cin7'::text, 'ims'::text]))))$q$ then raise exception 'ldfix-1c2 landing: CHECK is %', v_ck; end if;
  select proacl::text into v_acl from pg_proc where proname = 'product_supplier_default_recalc' and pronamespace = 'public'::regnamespace;
  if v_acl <> '{postgres=X/postgres,service_role=X/postgres}' then raise exception 'ldfix-1c2 landing: recalc ACL is %', v_acl; end if;
  if not (select prosecdef from pg_proc where proname = 'product_supplier_default_recalc') then raise exception 'ldfix-1c2 landing: recalc is not definer'; end if;
  select md5(prosrc) into v_md5 from pg_proc where proname = 'supplier_update' and pronamespace = 'public'::regnamespace;
  if v_md5 <> '6e26a069b0567783cdb77bd086f9e410' then raise exception 'ldfix-1c2 landing: supplier_update md5 % <> 6e26a069b0567783cdb77bd086f9e410', v_md5; end if;
  select count(*) into v_n from public.supplier where is_active_source = 'ims';
  if v_n <> 5 then raise exception 'ldfix-1c2 landing: ims rows %', v_n; end if;
  select count(*) into v_n from public.supplier where is_active_source = 'ims' and updated_by is null;
  if v_n <> 0 then raise exception 'ldfix-1c2 landing: backfill lost updated_by on % rows', v_n; end if;
  select tgenabled into v_tg from pg_trigger where tgname = 'supplier_touch' and tgrelid = 'public.supplier'::regclass;
  if v_tg <> 'O' then raise exception 'ldfix-1c2 landing: supplier_touch tgenabled = %', v_tg; end if;
  select count(*) into v_multi from (select product_id from public.product_supplier where is_default group by product_id having count(*) > 1) x;
  if v_multi <> 0 then raise exception 'ldfix-1c2 landing: % products with 2+ defaults', v_multi; end if;
  raise notice 'ldfix-1c2 landed: column + CHECK · recalc(service_role only · definer) · supplier_update md5 6e26a069 · backfill 5 (updated_by kept) · trigger on · multi-default 0';
end $$;
