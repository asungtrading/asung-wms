-- surcharge-4a — 관세 부가 요금 자동 붙이기: 그룹 표 · 상품 칸 · 줄이 들어올 때 채우기 (2026-10-02 UTC · 판정 227 (나) · 231 · 232 · surcharge-4 묶음 1 ~ 9 · so-module §36 · 앞 차수 2a bd5c71b · 2b 0a0bdc9)
--   판정 231  자동 붙이기는 ③ 상품에는 그룹 표시, 율은 한 곳 — 상품(SKU)에 「US Tariff」 같은 그룹 · % · 금액은 Settings 의 그룹 한 줄 · 그룹이 붙은 SKU 는 SO · POS 에 줄이 들어오는 순간 저절로(단위 = SKU + 시작 시점 · 옛 재고까지) · POS 는 (다) 자동
--   판정 232  스위치는 (가) 사람이 켠다(Sheet · Products 의 product_update op) · (다) 입고 확정 알림은 뒤에
--   묶음 1    그룹 표 so_surcharge_group — name(unique · 줄의 surcharge_label 로 복사) · % 또는 개당 금액 중 하나 · 켜짐/꺼짐 · 짝 · 범위 CHECK 는 so_line 과 같다 · 문장은 so_surcharge_check 한 곳
--   묶음 2    product.surcharge_group_id — 상품 하나 = 그룹 하나 · 고치기는 product_update op surcharge_group_set(master · old 대조 · 꺼진 그룹 막기 · 세트 막기 surcharge_on_set — SO 줄은 낱개)
--   묶음 3    줄이 들어오는 순간 채운다 — so_line_add · so_lines_paste(POS 스캔도 so_line_add) 의 insert 가 도우미 so_line_surcharge_defaults(상품, 무상?) 를 읽는다 · 무상 줄은 비움(판정 228) · 합치기 길(판정 229) · 옮기는 길(so_split · so_merge — 세 칸 복사) 무접촉
--   묶음 4·5  채운 뒤에는 보통 줄(출처 칸 없음 · 묶음 9) · 율을 바꾸거나 끄면 새로 들어오는 줄부터 — 이미 있는 초안 줄은 그대로 · 창구가 「그 이름 · 값을 가진 열린 초안 줄 N」 · 「이 그룹의 상품 N」을 알린다 · 꺼도 상품 포인터는 남는다(price_formula_in_use 와 같다)
--   묶음 6·7  손님 예외 없음 · 설정은 admin(ims_require_admin · 가격식 창구 모양 · 두 번 부르기)
--   읽기      뷰 so_surcharge_group_list(security_invoker · 그룹 + 상품 수 + 켜진 상품 수 + 열린 초안 줄 수 · 4b Settings 화면이 PostgREST 로 읽는다)
--   무접촉    so_detail · 계산 · 문서 함수(값이 줄에 있다) · so_split · so_merge · so_create · so_copy_customer · so_line_update · so_finalize · 적재 ImsLoadProduct.gs(명시 열 upsert · 이 칸을 보내지 않는다)
--
-- ① so_surcharge_group — IMS 규약 칸 · CHECK 넷(짝 · % > 0 · 금액 > 0 센트 · source manual) · unique(name) · ims_touch · select authenticated · 쓰기는 창구로만
-- ② product.surcharge_group_id — nullable FK · 인덱스 · 주석
-- ③ so_line_surcharge_defaults(p_product_id, p_free) stable — 켜진 그룹이 있고 무상이 아니면 (pct, amount, name) · 아니면 (null, null, null)
-- ④ so_surcharge_group_save(p_changes, p_commit, p_ack) definer admin — create {name, surcharge_pct|surcharge_amount, note} · update {id, set{…}, old{…}} · off {id} · on {id} · 최대 200
--    막기 code: op_unknown · group_unknown · name_missing · name_duplicate · field_duplicate_in_call · old_missing · changed_elsewhere · value_invalid(문장은 so_surcharge_check)
--    알리기 code: group_in_use:N(이 그룹을 가리키는 상품 수 · 값·이름 변경 · 끄기) · open_draft_lines:N(그 이름 · 값을 가진 열린 초안 줄 — 새 값으로 안 바뀐다 · 묶음 5)
-- ⑤ product_update 재발행(마지막 정의 20261002012641:739 바이트 그대로 + op surcharge_group_set — 선언 1 · op 목록 2 · 검사 블록 · 저장 2 · comment)
--    막기 code(새 op): old_missing · field_duplicate_in_call · changed_elsewhere(공용) · surcharge_on_set · surcharge_group_unknown · surcharge_group_inactive
-- ⑥ so_line_add 재발행(20260923232500:129) · ⑦ so_lines_paste 재발행(:272) — insert 에 세 칸 · 값은 ③ 에서
-- ⑧ 뷰 so_surcharge_group_list
--   검증: ~/asung/prompts/surcharge-4a-verify.sql (시험 적용 장치 · 테스트 DB · rollback · 시퀀스 setval · 시험 · 확인 두 갈래) · ⚠️ 운영 무접촉(컷오버 전 운영 적용 금지 · ims-principles)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 의 바이트 복사 — 운영에서는 멈춘다
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

-- ═══ ① 그룹 표 ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.so_surcharge_group (
  id                uuid primary key default gen_random_uuid(),
  is_active         boolean not null default true,
  source            text not null default 'manual',
  note              text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  updated_by        uuid references public.ims_staff (id) on delete no action,
  name              text not null,
  surcharge_pct     numeric,
  surcharge_amount  numeric,
  constraint so_surcharge_group_source_ck check (source = 'manual'),
  constraint so_surcharge_group_name_ck   check (name = trim(name) and name <> ''),
  constraint so_surcharge_group_name_key  unique (name),
  constraint so_surcharge_group_value_ck  check ((surcharge_pct is null) <> (surcharge_amount is null)),
  constraint so_surcharge_group_pct_ck    check (surcharge_pct is null or surcharge_pct > 0),
  constraint so_surcharge_group_amount_ck check (surcharge_amount is null or (surcharge_amount > 0 and surcharge_amount = round(surcharge_amount, 2)))
);
create index if not exists so_surcharge_group_updated_by_idx on public.so_surcharge_group (updated_by);
create trigger so_surcharge_group_touch before update on public.so_surcharge_group for each row execute function public.ims_touch();
alter table public.so_surcharge_group enable row level security;
create policy so_surcharge_group_select on public.so_surcharge_group for select to authenticated using (true);
revoke all on public.so_surcharge_group from public, anon, authenticated;
grant select on public.so_surcharge_group to authenticated;
comment on table public.so_surcharge_group is '⭐ 관세 부가 요금 그룹(surcharge-4a · 판정 231 · 묶음 1) — 이름(줄의 surcharge_label 로 복사된다 · unique · 창구가 대소문자를 접어 막는다) · % 또는 개당 금액 중 하나(CHECK · so_line 과 같은 범위 · 위 한계 없음) · 켜짐/꺼짐 · 상품은 product.surcharge_group_id 로 가리킨다 · 줄은 들어오는 순간 값을 복사하고 그 뒤 그룹과 무관(묶음 4 · 5) · 쓰기는 so_surcharge_group_save(admin)로만 · source 는 manual 하나';
comment on column public.so_surcharge_group.name is '줄에 찍힐 이름(예 US Tariff) — 그룹 이름을 바꿔도 이미 복사된 so_line.surcharge_label 은 그대로(문서는 얼린 값 · 창구가 open_draft_lines 로 알린다)';
comment on column public.so_surcharge_group.surcharge_pct is '%(할인 뒤 단가에 · 개당 = round(unit_price × %/100, 2) · so_line_surcharge_unit) · surcharge_amount 와 둘 중 하나 · > 0 · 위 한계 없음(Caleb 확인 · 100 초과는 줄 창구가 알린다)';
comment on column public.so_surcharge_group.surcharge_amount is '개당 금액(센트 두 자리 · > 0) · surcharge_pct 와 둘 중 하나';

-- ═══ ② 상품 칸 ═════════════════════════════════════════════════════════════════════════════════════════════════════════════
alter table public.product add column if not exists surcharge_group_id uuid references public.so_surcharge_group (id) on delete no action;
create index if not exists product_surcharge_group_idx on public.product (surcharge_group_id);
comment on column public.product.surcharge_group_id is '관세 부가 요금 그룹(surcharge-4a · 판정 231 · 232 · 묶음 2) — 상품 하나 = 그룹 하나 · 사람이 켠다(product_update op surcharge_group_set · master · 세트 금지 surcharge_on_set) · 켜진 그룹이면 so_line_add · so_lines_paste 가 줄에 세 칸을 복사한다(so_line_surcharge_defaults) · 그룹을 꺼도 포인터는 남는다(채우기는 is_active 를 본다) · 적재(ImsLoadProduct.gs)는 이 칸을 보내지 않는다';

-- ═══ ③ 채우기 도우미 — 한 곳(묶음 3) ═══════════════════════════════════════════════════════════════════════════════════════
create function public.so_line_surcharge_defaults(p_product_id uuid, p_free boolean)
  returns table (surcharge_pct numeric, surcharge_amount numeric, surcharge_label text)
  language sql stable
  set search_path = public, pg_temp
as $$
  select case when p_free then null else g.surcharge_pct end,
         case when p_free then null else g.surcharge_amount end,
         case when p_free then null else g.name end
  from public.product p
  left join public.so_surcharge_group g on g.id = p.surcharge_group_id and g.is_active
  where p.id = p_product_id;
$$;
revoke all on function public.so_line_surcharge_defaults(uuid, boolean) from public, anon;
grant execute on function public.so_line_surcharge_defaults(uuid, boolean) to authenticated;
comment on function public.so_line_surcharge_defaults(uuid, boolean) is '⭐ 줄이 들어올 때의 surcharge 세 칸(surcharge-4a · 묶음 3 · 한 곳) — 상품의 그룹이 켜져 있고 무상(p_free)이 아니면 (그룹 % · 금액 · 이름) · 아니면 (null · null · null) · so_line_add · so_lines_paste 의 insert 가 부른다 · 상품이 없으면 0 행(그 insert 는 0 행 — 창구가 먼저 상품을 확인하므로 안 생긴다) · 세트는 자기 그룹만 본다(부모 폴백 없음 · 세트에는 그룹을 못 단다)';

-- ═══ ④ 그룹 창구 — admin · 두 번 부르기(가격식 창구 모양) ═══════════════════════════════════════════════════════════════════
create function public.so_surcharge_group_save(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_plan     jsonb := '[]'::jsonb;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_key      text;
  v_g        public.so_surcharge_group%rowtype;
  v_name     text;
  v_pct      numeric;
  v_amt      numeric;
  v_note     text;
  v_seen     text[] := '{}';
  v_k        text;
  v_cur      text;
  v_oldt     text;
  v_bad      text;
  v_valchg   boolean;
  v_in_use   bigint;
  v_open     bigint;
  v_keys     text[];
  v_unacked  text[];
  v_id       uuid;
begin
  perform public.ims_require_admin('surcharge groups');                                         -- ⭐ 유일한 문 — 첫 줄(묶음 7)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  if jsonb_array_length(p_changes) > 200 then
    raise exception 'Too many changes in one call (% — the limit is 200) — nothing was saved', jsonb_array_length(p_changes);
  end if;

  -- ① 줄마다 막기 · 알리기 — 전부 모은다
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := coalesce(v_c->>'op', '');
    v_g := null;  v_valchg := false;
    if v_op not in ('create', 'update', 'off', 'on') then
      v_blocks := v_blocks || jsonb_build_object('key', v_i::text || ':op_unknown', 'code', 'op_unknown', 'message', format('Line %s: unknown op "%s" — create, update, off or on — nothing was saved', v_i, v_op));
      v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'id', null, 'applied', false);
      continue;
    end if;
    if v_op = 'create' then
      v_name := nullif(trim(coalesce(v_c->>'name', '')), '');
      v_key := coalesce(v_name, '(none)');
      v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'id', null, 'applied', false);
      if v_name is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'code', 'name_missing', 'message', format('Line %s: a surcharge group needs a name — nothing was saved', v_i));
        continue;
      end if;
      if ('N|' || lower(v_name)) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Group "%s" appears twice in this call — nothing was saved', v_name));
        continue;
      end if;
      v_seen := v_seen || ('N|' || lower(v_name));
      if exists (select 1 from public.so_surcharge_group g where lower(g.name) = lower(v_name)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_duplicate', 'code', 'name_duplicate', 'message', format('A surcharge group named "%s" already exists (active or off) — pick another name — nothing was saved', v_name));
        continue;
      end if;
      v_pct := nullif(v_c->>'surcharge_pct', '')::numeric;  v_amt := nullif(v_c->>'surcharge_amount', '')::numeric;
      begin
        perform public.so_surcharge_check(v_pct, v_amt, v_name, null);
      exception when others then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid', 'code', 'value_invalid', 'message', format('Group "%s": %s', v_name, sqlerrm));
        continue;
      end;
      v_plan := v_plan || jsonb_build_object('i', v_i, 'op', v_op, 'name', v_name, 'surcharge_pct', v_pct, 'surcharge_amount', v_amt, 'note', nullif(trim(coalesce(v_c->>'note', '')), ''));
      continue;
    end if;

    -- update · off · on — 있는 그룹
    v_key := coalesce(v_c->>'id', '?');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'id', v_c->>'id', 'applied', false);
    if coalesce(v_c->>'id', '') ~ '^[0-9a-fA-F-]{36}$' then
      select * into v_g from public.so_surcharge_group g where g.id = (v_c->>'id')::uuid;
    end if;
    if v_g.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':group_unknown', 'code', 'group_unknown', 'message', format('Line %s: that surcharge group does not exist — nothing was saved', v_i));
      continue;
    end if;
    if (v_g.id::text || '|op') = any(v_seen) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Group "%s" is changed twice in this call — nothing was saved', v_g.name));
      continue;
    end if;
    v_seen := v_seen || (v_g.id::text || '|op');
    select count(*) into v_in_use from public.product p where p.surcharge_group_id = v_g.id;
    select count(*) into v_open from public.so_line l join public.so s on s.id = l.so_id
     where s.status = 'draft' and l.surcharge_label = v_g.name and l.surcharge_pct is not distinct from v_g.surcharge_pct and l.surcharge_amount is not distinct from v_g.surcharge_amount;
    if v_op = 'off' then
      if v_in_use > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':group_in_use:' || v_in_use, 'code', 'group_in_use', 'message', format('%s product%s point at "%s" — they keep the pointer, new order lines stop getting the surcharge', v_in_use, case when v_in_use = 1 then '' else 's' end, v_g.name));
      end if;
      if v_open > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':open_draft_lines:' || v_open, 'code', 'open_draft_lines', 'message', format('%s open draft line%s carry "%s" at its current value — they keep it (clear them by hand if the tariff ended)', v_open, case when v_open = 1 then '' else 's' end, v_g.name));
      end if;
      v_plan := v_plan || jsonb_build_object('i', v_i, 'op', v_op, 'id', v_g.id);
      continue;
    end if;
    if v_op = 'on' then
      v_plan := v_plan || jsonb_build_object('i', v_i, 'op', v_op, 'id', v_g.id);
      continue;
    end if;
    -- update — set{name | surcharge_pct | surcharge_amount | note} · 바꾸는 칸마다 old
    if coalesce(jsonb_typeof(v_c->'set'), 'none') <> 'object' or (select count(*) from jsonb_object_keys(v_c->'set')) = 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid', 'code', 'value_invalid', 'message', format('Group "%s": update needs a "set" object with at least one field — nothing was saved', v_g.name));
      continue;
    end if;
    v_bad := null;
    for v_k in select k from jsonb_object_keys(v_c->'set') as k loop
      if v_k not in ('name', 'surcharge_pct', 'surcharge_amount', 'note') then
        v_bad := format('"%s" is not a field this window changes', v_k); exit;
      end if;
      if coalesce(jsonb_typeof(v_c->'old'), 'none') <> 'object' or not (v_c->'old' ? v_k) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_k, 'code', 'old_missing', 'message', format('Group "%s" %s: the old value the screen saw is missing — nothing was saved', v_g.name, v_k));
        v_bad := ''; exit;
      end if;
      v_cur := case v_k when 'name' then v_g.name when 'surcharge_pct' then v_g.surcharge_pct::text when 'surcharge_amount' then v_g.surcharge_amount::text else v_g.note end;
      v_oldt := nullif(v_c->'old'->>v_k, '');
      if v_k in ('surcharge_pct', 'surcharge_amount') and v_cur is not null and v_oldt ~ '^[0-9]+(\.[0-9]+)?$' and v_cur::numeric = v_oldt::numeric then
        null;
      elsif v_cur is distinct from v_oldt then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_k, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of group "%s" (now "%s") — check again — nothing was saved', v_k, v_g.name, coalesce(v_cur, '(none)')));
        v_bad := ''; exit;
      end if;
      if v_k in ('surcharge_pct', 'surcharge_amount', 'name') then v_valchg := true; end if;
    end loop;
    if v_bad = '' then continue; end if;
    if v_bad is not null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid', 'code', 'value_invalid', 'message', format('Group "%s": %s — nothing was saved', v_g.name, v_bad));
      continue;
    end if;
    v_name := case when v_c->'set' ? 'name' then nullif(trim(coalesce(v_c->'set'->>'name', '')), '') else v_g.name end;
    if v_name is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'code', 'name_missing', 'message', format('Group "%s": the name cannot be empty — nothing was saved', v_g.name));
      continue;
    end if;
    if exists (select 1 from public.so_surcharge_group g where g.id <> v_g.id and lower(g.name) = lower(v_name)) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_duplicate', 'code', 'name_duplicate', 'message', format('A surcharge group named "%s" already exists (active or off) — nothing was saved', v_name));
      continue;
    end if;
    v_pct := case when v_c->'set' ? 'surcharge_pct'    then nullif(v_c->'set'->>'surcharge_pct', '')::numeric    else v_g.surcharge_pct end;
    v_amt := case when v_c->'set' ? 'surcharge_amount' then nullif(v_c->'set'->>'surcharge_amount', '')::numeric else v_g.surcharge_amount end;
    begin
      perform public.so_surcharge_check(v_pct, v_amt, v_name, null);
    exception when others then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid', 'code', 'value_invalid', 'message', format('Group "%s": %s', v_g.name, sqlerrm));
      continue;
    end;
    if v_valchg and v_in_use > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':group_in_use:' || v_in_use, 'code', 'group_in_use', 'message', format('%s product%s point at "%s" — new order lines get the new value from now on', v_in_use, case when v_in_use = 1 then '' else 's' end, v_g.name));
    end if;
    if v_valchg and v_open > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':open_draft_lines:' || v_open, 'code', 'open_draft_lines', 'message', format('%s open draft line%s carry "%s" at the old value — they do not change (bundle 5)', v_open, case when v_open = 1 then '' else 's' end, v_g.name));
    end if;
    v_plan := v_plan || jsonb_build_object('i', v_i, 'op', v_op, 'id', v_g.id, 'name', v_name, 'surcharge_pct', v_pct, 'surcharge_amount', v_amt,
                                           'note', case when v_c->'set' ? 'note' then nullif(trim(coalesce(v_c->'set'->>'note', '')), '') else v_g.note end);
  end loop;

  -- ② 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ③ 저장 — 줄 순서대로 · 한 트랜잭션
  for v_c in select x from jsonb_array_elements(v_plan) as x loop
    v_op := v_c->>'op';
    if v_op = 'create' then
      insert into public.so_surcharge_group (name, surcharge_pct, surcharge_amount, note, updated_by)
      values (v_c->>'name', nullif(v_c->>'surcharge_pct', '')::numeric, nullif(v_c->>'surcharge_amount', '')::numeric, nullif(v_c->>'note', ''), v_staff)
      returning id into v_id;
      v_changes := jsonb_set(jsonb_set(v_changes, array[((v_c->>'i')::int - 1)::text, 'applied'], 'true'::jsonb), array[((v_c->>'i')::int - 1)::text, 'id'], to_jsonb(v_id::text));
      continue;
    end if;
    v_id := (v_c->>'id')::uuid;
    if v_op = 'update' then
      update public.so_surcharge_group set name = v_c->>'name', surcharge_pct = nullif(v_c->>'surcharge_pct', '')::numeric, surcharge_amount = nullif(v_c->>'surcharge_amount', '')::numeric, note = nullif(v_c->>'note', ''), updated_by = v_staff where id = v_id;
    elsif v_op = 'off' then
      update public.so_surcharge_group set is_active = false, updated_by = v_staff where id = v_id;
    elsif v_op = 'on' then
      update public.so_surcharge_group set is_active = true, updated_by = v_staff where id = v_id;
    end if;
    v_changes := jsonb_set(v_changes, array[((v_c->>'i')::int - 1)::text, 'applied'], 'true'::jsonb);
  end loop;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.so_surcharge_group_save(jsonb, boolean, text[]) from public, anon;
grant execute on function public.so_surcharge_group_save(jsonb, boolean, text[]) to authenticated;
comment on function public.so_surcharge_group_save(jsonb, boolean, text[]) is '⭐ 관세 부가 요금 그룹 저장 창구(surcharge-4a · 판정 231 · 묶음 1 · 5 · 7) — definer · 첫 줄 ims_require_admin · p_changes 최대 200 · op 넷: create {name, surcharge_pct | surcharge_amount, note} · update {id, set{name | surcharge_pct | surcharge_amount | note}, old{같은 열쇠}} · off {id} · on {id} · 두 번 부르기(p_commit false → 알리기 열쇠를 p_ack 로) · 막기 op_unknown · group_unknown · name_missing · name_duplicate(대소문자 접음 · 꺼진 것 포함) · field_duplicate_in_call · old_missing · changed_elsewhere · value_invalid(문장은 so_surcharge_check — 짝 · % > 0 · 금액 > 0 센트) · 알리기 group_in_use:N(이 그룹을 가리키는 상품) · open_draft_lines:N(그 이름 · 값을 가진 열린 초안 줄 — 바뀌지 않는다 · 묶음 5) · 끄기는 상품 포인터를 두고 채우기만 멈춘다 · 그룹 이름을 바꿔도 이미 복사된 줄 · 문서의 label 은 그대로';

-- ═══ ⑤ product_update 재발행 — 마지막 정의 20261002012641_price_1_formula.sql:739~1563 바이트 그대로 + op surcharge_group_set(선언 1 · op 목록 2 · 검사 블록 · 저장 2) ═══
create or replace function public.product_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_field    text;
  v_sku      text;
  v_key      text;
  v_val      jsonb;
  v_vtxt     text;
  v_old      jsonb;
  v_cur      text;
  p          public.product%rowtype;
  v_par      public.product%rowtype;
  v_fam      public.product_family%rowtype;
  v_brand    public.ref_brand%rowtype;
  v_cat      public.ref_category%rowtype;
  v_unit     public.ref_unit%rowtype;
  v_seen     text[] := '{}';          -- '<product id>|<field>' · family_head: 'F<family id>|<field>'
  v_newsku   text[] := '{}';          -- 이 호출이 짓는 SKU 전부(낱개 새 SKU · 따라 바뀌는 세트 SKU)
  v_seenopt  text[] := '{}';          -- '<family id>|<옵션 열쇠>'
  v_idmap    jsonb := '{}'::jsonb;    -- 검사 때 푼 SKU → product id · family SKU → family id (저장은 이 id 로 — 앞 줄이 SKU 를 바꿔도 뒤 줄은 화면이 본 옛 SKU 로 가리킨다 · ⬜2)
  v_axes     int;
  v_opts     text[];
  v_optkey   text;
  v_ex       record;
  v_set      record;
  v_num      numeric;
  v_cnt      bigint;
  v_cnt2     bigint;
  v_cnt3     bigint;
  v_cnt4     bigint;
  v_hn       text;
  v_hc       bigint;
  v_bc       text;                                                                             -- prod-4b: 바코드 · 가격 · 공급처 op
  v_tier     public.ref_price_tier%rowtype;
  v_sup      public.supplier%rowtype;
  v_row      record;
  v_calc     numeric;
  v_fol      bigint;
  v_stay     bigint;
  v_oldv     jsonb;
  v_img      record;                                                                           -- img-1: 사진 op
  v_ids      uuid[];
  v_path     text;
  v_keys     text[];
  v_unacked  text[];
  v_newname  text;
  v_fml      jsonb;                                                                            -- price-1: price_set 의 formula 재계산(price_formula_calc 반환)
  v_fver     jsonb := '{}'::jsonb;                                                             -- price-1: 줄 번호 → {source, formula_id, supplier_id} — 검사가 정하고 저장이 읽는다(저장 직전 재검사가 다시 정한다 · 판정 176)
  v_fcost    numeric;
  v_fsup     uuid;
  v_grp      public.so_surcharge_group%rowtype;                                                -- surcharge-4a: op surcharge_group_set
  v_fprice   numeric;
  v_src      text;
  v_fields   constant text[] := array['name', 'brand_id', 'category_id', 'unit_id', 'weight', 'weight_unit', 'note', 'is_discontinued', 'set_discount_pct', 'sku', 'is_active', 'pack_factor', 'parent_sku'];
  v_hfields  constant text[] := array['name', 'brand_id', 'category_id', 'unit_id', 'note', 'is_active', 'option1_name', 'option2_name', 'option3_name'];
  v_open_so  constant text[] := array['draft', 'confirmed', 'at_wms', 'picking', 'packed'];
  v_open_po  constant text[] := array['draft', 'confirmed'];
begin
  perform public.ims_require_write('master', 'saved');                                        -- ⭐ 유일한 문 — 첫 줄(판정 140)
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then
    raise exception 'No changes given — nothing was saved';
  end if;
  if v_n > 1000 then
    raise exception 'Too many changes in one call (% — the limit is 1000) — split the paste — nothing was saved', v_n;
  end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    if coalesce(v_c->>'op', '') not in ('set', 'family_join', 'family_leave', 'family_option', 'family_head_set',
                                         'barcode_add', 'barcode_off', 'barcode_primary', 'price_set', 'price_off', 'supplier_set', 'supplier_default', 'supplier_off',   -- prod-4b 여덟
                                         'image_add', 'image_off', 'image_primary', 'image_order',                                                                              -- img-1 넷
                                         'surcharge_group_set') then                                                                                                           -- surcharge-4a 하나
      raise exception 'Unknown op "%" — set, family_join, family_leave, family_option, family_head_set, barcode_add, barcode_off, barcode_primary, price_set, price_off, supplier_set, supplier_default, supplier_off, image_add, image_off, image_primary, image_order or surcharge_group_set — nothing was saved', coalesce(v_c->>'op', '(none)');
    end if;
  end loop;

  -- ② 줄마다 막기 · 알리기 — 전부 모은다(첫 막기에서 멈추지 않는다)
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_field := v_c->>'field';
    v_val := v_c->'value';
    v_vtxt := nullif(trim(coalesce(v_c->>'value', '')), '');
    v_old := v_c->'old';
    p := null; v_fam := null;

    if v_op = 'family_head_set' then
      -- ── family 머리 칸 ─────────────────────────────────────────────────────────────────────────────────
      v_sku := trim(coalesce(v_c->>'family_sku', ''));
      v_key := case when v_sku = '' then '(family)' else v_sku end;
      v_changes := v_changes || jsonb_build_object('i', v_i, 'sku', v_sku, 'op', v_op, 'field', v_field, 'applied', false);
      select * into v_fam from public.product_family f where f.sku = v_sku;
      if v_fam.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_unknown', 'sku', v_sku, 'code', 'family_unknown', 'message', format('Family %s does not exist — nothing was saved', v_sku));
        continue;
      end if;
      v_idmap := v_idmap || jsonb_build_object('F' || v_sku, v_fam.id);
      if v_field is null or not (v_field = any(v_hfields)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(none)'), 'sku', v_sku, 'code', 'field_unknown', 'message', format('Family %s: "%s" is not a field this window changes — nothing was saved', v_sku, coalesce(v_field, '(none)')));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'sku', v_sku, 'code', 'old_missing', 'message', format('Family %s %s: the old value the screen saw is missing — nothing was saved', v_sku, v_field));
        continue;
      end if;
      if ('F' || v_fam.id::text || '|' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Family %s %s is changed twice in this paste — nothing was saved', v_sku, v_field));
        continue;
      end if;
      v_seen := v_seen || ('F' || v_fam.id::text || '|' || v_field);
      v_cur := case v_field when 'name' then v_fam.name when 'brand_id' then v_fam.brand_id::text when 'category_id' then v_fam.category_id::text when 'unit_id' then v_fam.unit_id::text
                            when 'note' then v_fam.note when 'is_active' then v_fam.is_active::text when 'option1_name' then v_fam.option1_name when 'option2_name' then v_fam.option2_name else v_fam.option3_name end;
      if v_cur is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of family %s (now "%s") — check again — nothing was saved', v_field, v_sku, coalesce(v_cur, '')));
        continue;
      end if;
      if v_field = 'name' and v_vtxt is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'sku', v_sku, 'code', 'name_missing', 'message', format('Family %s cannot have an empty name — nothing was saved', v_sku));
      elsif v_field = 'brand_id' and v_vtxt is not null and not exists (select 1 from public.ref_brand b where b.id = v_vtxt::uuid and b.is_active) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':brand_unknown', 'sku', v_sku, 'code', 'brand_unknown', 'message', format('Family %s: the brand does not exist or is inactive — nothing was saved', v_sku));
      elsif v_field = 'category_id' and v_vtxt is not null and not exists (select 1 from public.ref_category c where c.id = v_vtxt::uuid and c.is_active) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':category_unknown', 'sku', v_sku, 'code', 'category_unknown', 'message', format('Family %s: the category does not exist or is inactive — nothing was saved', v_sku));
      elsif v_field = 'unit_id' and v_vtxt is not null and not exists (select 1 from public.ref_unit u where u.id = v_vtxt::uuid and u.is_active) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':unit_unknown', 'sku', v_sku, 'code', 'unit_unknown', 'message', format('Family %s: the unit does not exist or is inactive — nothing was saved', v_sku));
      elsif v_field = 'is_active' and jsonb_typeof(v_val) <> 'boolean' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_active', 'sku', v_sku, 'code', 'value_invalid', 'message', format('Family %s is_active must be true or false — nothing was saved', v_sku));
      elsif v_field = 'is_active' and not (v_val)::boolean then
        select count(*) into v_cnt from public.product x where x.family_id = v_fam.id and x.is_active;
        if v_cnt > 0 then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_variants_on', 'sku', v_sku, 'code', 'inactive_variants_on', 'message', format('Family %s still has %s active variant(s) — they stay active', v_sku, v_cnt));
        end if;
      elsif v_field like 'option%\_name' then
        if (v_cur is null) <> (v_vtxt is null) then                                          -- ⬜6: 축을 더하거나 빼는 것은 변형마다 값이 필요하다 — 이 차수는 이름 바꾸기만
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':axis_count_change:' || v_field, 'sku', v_sku, 'code', 'axis_count_change', 'message', format('Family %s: adding or removing an option axis is not done here (every variant needs a value) — rename only — nothing was saved', v_sku));
        elsif v_vtxt is not null then
          if not exists (select 1 from public.product_family f where f.is_active and v_vtxt in (f.option1_name, f.option2_name, f.option3_name)) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':option_name_unusual:' || v_vtxt, 'sku', v_sku, 'code', 'option_name_unusual', 'message', format('Option axis "%s" is not used by any active family yet — check the spelling (e.g. Color vs Colour)', v_vtxt));
          else
            select h.common_name, h.n_families into v_hn, v_hc from public.product_axis_case_hint(v_vtxt) h;
            if v_hn is not null then
              v_warns := v_warns || jsonb_build_object('key', v_key || ':option_name_case:' || v_vtxt, 'sku', v_sku, 'code', 'option_name_case', 'message', format('Option axis "%s" — %s active families spell it "%s" — use that spelling unless this is on purpose', v_vtxt, v_hc, v_hn));
            end if;
          end if;
        end if;
      end if;
      if v_field in ('brand_id', 'category_id', 'unit_id')                                     -- prod-4b 판정 191 · 192: 옛 머리 값과 같던 변형만 따라간다(null 끼리도 같다) · 수를 열쇠에(⬜5)
         and (v_vtxt is null or (v_field = 'brand_id' and exists (select 1 from public.ref_brand b where b.id = v_vtxt::uuid and b.is_active))
                              or (v_field = 'category_id' and exists (select 1 from public.ref_category c where c.id = v_vtxt::uuid and c.is_active))
                              or (v_field = 'unit_id' and exists (select 1 from public.ref_unit u where u.id = v_vtxt::uuid and u.is_active))) then
        select count(*) filter (where (case v_field when 'brand_id' then x.brand_id when 'category_id' then x.category_id else x.unit_id end) is not distinct from v_cur::uuid),
               count(*) filter (where (case v_field when 'brand_id' then x.brand_id when 'category_id' then x.category_id else x.unit_id end) is distinct from v_cur::uuid)
          into v_fol, v_stay from public.product x where x.family_id = v_fam.id;
        if v_fol > 0 then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':variants_follow:' || v_field || ':' || v_fol, 'sku', v_sku, 'code', 'variants_follow', 'message', format('Family %s: %s variant(s) that still carry the old %s will follow the family — %s with their own value stay as they are', v_sku, v_fol, replace(v_field, '_id', ''), v_stay));
        end if;
      end if;
      continue;
    end if;

    -- ── 상품 줄 공통: SKU 로 찾는다(이 호출이 SKU 를 바꾸는 줄이 있어도 다른 줄은 화면이 본 옛 SKU 로 가리킨다 · ⬜2) ─────────────
    v_sku := trim(coalesce(v_c->>'sku', ''));
    v_key := case when v_sku = '' then '(blank)' else v_sku end;
    v_changes := v_changes || jsonb_build_object('i', v_i, 'sku', v_sku, 'op', v_op, 'field', v_field, 'applied', false);
    select * into p from public.product x where x.sku = v_sku;
    if p.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_unknown', 'sku', v_sku, 'code', 'sku_unknown', 'message', format('SKU %s does not exist — nothing was saved', v_sku));
      continue;
    end if;
    v_idmap := v_idmap || jsonb_build_object('P' || v_sku, p.id);

    if v_op = 'set' then
      if v_field is null or not (v_field = any(v_fields)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(none)'), 'sku', v_sku, 'code', 'field_unknown', 'message', format('SKU %s: "%s" is not a field this window changes — nothing was saved', v_sku, coalesce(v_field, '(none)')));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s %s: the old value the screen saw is missing — nothing was saved', v_sku, v_field));
        continue;
      end if;
      if (p.id::text || '|' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s %s is changed twice in this paste — nothing was saved', v_sku, v_field));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|' || v_field);
      v_cur := case v_field
                 when 'name' then p.name when 'brand_id' then p.brand_id::text when 'category_id' then p.category_id::text when 'unit_id' then p.unit_id::text
                 when 'weight' then p.weight::text when 'weight_unit' then p.weight_unit when 'note' then p.note when 'is_discontinued' then p.is_discontinued::text
                 when 'set_discount_pct' then p.set_discount_pct::text when 'sku' then p.sku when 'is_active' then p.is_active::text when 'pack_factor' then p.pack_factor::text
                 when 'parent_sku' then (select x.sku from public.product x where x.id = p.parent_product_id) end;
      if v_cur is distinct from nullif(v_c->>'old', '') and not (v_field in ('weight', 'set_discount_pct', 'pack_factor') and v_cur is not null and nullif(v_c->>'old', '') is not null and v_cur::numeric = (v_c->>'old')::numeric) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of %s (now "%s") — check again — nothing was saved', v_field, v_sku, coalesce(v_cur, '')));
        continue;
      end if;

      case v_field
      when 'name' then
        if v_vtxt is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'sku', v_sku, 'code', 'name_missing', 'message', format('SKU %s cannot have an empty name — nothing was saved', v_sku));
        end if;
      when 'brand_id' then
        if v_vtxt is not null and not exists (select 1 from public.ref_brand b where b.id = v_vtxt::uuid and b.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':brand_unknown', 'sku', v_sku, 'code', 'brand_unknown', 'message', format('SKU %s: the brand does not exist or is inactive — nothing was saved', v_sku));
        end if;
      when 'category_id' then
        if v_vtxt is not null and not exists (select 1 from public.ref_category c where c.id = v_vtxt::uuid and c.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':category_unknown', 'sku', v_sku, 'code', 'category_unknown', 'message', format('SKU %s: the category does not exist or is inactive — nothing was saved', v_sku));
        end if;
      when 'unit_id' then
        if v_vtxt is not null and not exists (select 1 from public.ref_unit u where u.id = v_vtxt::uuid and u.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':unit_unknown', 'sku', v_sku, 'code', 'unit_unknown', 'message', format('SKU %s: the unit does not exist or is inactive — nothing was saved', v_sku));
        elsif p.parent_product_id is not null and v_vtxt is not null and (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) is distinct from p.pack_factor::int::text then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':set_unit_mismatch', 'sku', v_sku, 'code', 'set_unit_mismatch', 'message', format('Set %s: unit "%s" differs from its pack factor %s', v_sku, (select u.name from public.ref_unit u where u.id = v_vtxt::uuid), p.pack_factor::int));
        end if;
      when 'weight' then
        if v_vtxt is not null and (v_vtxt !~ '^[0-9]+(\.[0-9]+)?$') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':weight_invalid', 'sku', v_sku, 'code', 'weight_invalid', 'message', format('SKU %s: weight must be a number of 0 or more — nothing was saved', v_sku));
        end if;
      when 'is_discontinued' then
        if jsonb_typeof(v_val) <> 'boolean' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_discontinued', 'sku', v_sku, 'code', 'value_invalid', 'message', format('SKU %s is_discontinued must be true or false — nothing was saved', v_sku));
        end if;
      when 'set_discount_pct' then
        if p.parent_product_id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_a_set', 'sku', v_sku, 'code', 'not_a_set', 'message', format('SKU %s is not a set — the set discount belongs to sets only — nothing was saved', v_sku));
        elsif v_vtxt is not null and (v_vtxt !~ '^[0-9]+(\.[0-9]+)?$' or v_vtxt::numeric > 100) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_discount_invalid', 'sku', v_sku, 'code', 'set_discount_invalid', 'message', format('Set %s: the set discount must be between 0 and 100 — nothing was saved', v_sku));
        end if;
      when 'is_active' then
        if jsonb_typeof(v_val) <> 'boolean' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_active', 'sku', v_sku, 'code', 'value_invalid', 'message', format('SKU %s is_active must be true or false — nothing was saved', v_sku));
        elsif not (v_val)::boolean then                                                        -- 끄기 — 0 이 아닌 것만 알린다(판정 139 · ⬜4)
          select coalesce(sum(b.qty), 0) into v_num from public.ims_inv_balance b where b.sku = p.sku;
          select count(*) into v_cnt  from public.so_line l join public.so s on s.id = l.so_id where l.product_id = p.id and s.status = any(v_open_so);
          select count(*) into v_cnt2 from public.po_line l join public.po o on o.id = l.po_id where (l.product_id = p.id or l.entered_unit_product_id = p.id) and o.status = any(v_open_po);
          select count(*) into v_cnt3 from public.product x where x.parent_product_id = p.id and x.is_active;
          if v_num <> 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_stock', 'sku', v_sku, 'code', 'inactive_stock', 'message', format('SKU %s still has stock on hand (%s) — it stays in the ledger after it is turned off', v_sku, v_num));
          end if;
          if v_cnt > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_so', 'sku', v_sku, 'code', 'inactive_open_so', 'message', format('SKU %s is on %s open sales order line(s)', v_sku, v_cnt));
          end if;
          if v_cnt2 > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_po', 'sku', v_sku, 'code', 'inactive_open_po', 'message', format('SKU %s is on %s open purchase order line(s)', v_sku, v_cnt2));
          end if;
          if v_cnt3 > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_sets_on', 'sku', v_sku, 'code', 'inactive_sets_on', 'message', format('SKU %s has %s active set(s) — they are not turned off with it', v_sku, v_cnt3));
          end if;
        end if;
      when 'sku' then
        v_newname := v_vtxt;
        if p.parent_product_id is not null then                                                 -- 세트 SKU 는 창구가 짓는다(판정 177 · 189) — 부모나 계수를 바꾼다
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_sku_managed', 'sku', v_sku, 'code', 'set_sku_managed', 'message', format('Set %s: a set SKU is built from its parent SKU and pack factor — change the parent or the pack factor instead — nothing was saved', v_sku));
        elsif v_newname is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_space', 'sku', v_sku, 'code', 'sku_space', 'message', format('SKU %s: the new SKU is empty — nothing was saved', v_sku));
        else
          if v_newname ~ '\s' then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_space', 'sku', v_sku, 'code', 'sku_space', 'message', format('New SKU "%s" contains a space — nothing was saved', v_newname));
          end if;
          if v_newname ~ '[a-z]' then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_lowercase', 'sku', v_sku, 'code', 'sku_lowercase', 'message', format('New SKU %s has lowercase letters — use capitals — nothing was saved', v_newname));
          end if;
          if v_newname <> p.sku and exists (select 1 from public.product x where x.sku = v_newname) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_exists:' || v_newname, 'sku', v_sku, 'code', 'sku_exists', 'message', format('SKU %s already exists (active or inactive) — nothing was saved', v_newname));
          end if;
          if v_newname = any(v_newsku) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_duplicate_in_call:' || v_newname, 'sku', v_sku, 'code', 'sku_duplicate_in_call', 'message', format('SKU %s is produced twice in this paste — nothing was saved', v_newname));
          end if;
          v_newsku := v_newsku || v_newname;
          if exists (select 1 from public.inv_ledger e where e.sku = p.sku) or exists (select 1 from public.inv_layer l where l.sku = p.sku) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_locked', 'sku', v_sku, 'code', 'sku_locked', 'message', format('SKU %s has stock or cost history and cannot be renamed — create a new product instead — nothing was saved', v_sku));
          end if;
          -- 세트 따라 고침(판정 189) — 하나라도 기록이면 전체 막기 · 새 세트 SKU 가 이미 있으면 막기 · 이름은 그대로(알리기)
          v_cnt := 0;
          for v_set in select x.id, x.sku, x.pack_factor from public.product x where x.parent_product_id = p.id order by x.sku loop
            v_cnt := v_cnt + 1;
            if exists (select 1 from public.inv_ledger e where e.sku = v_set.sku) or exists (select 1 from public.inv_layer l where l.sku = v_set.sku) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_locked_set:' || v_set.sku, 'sku', v_sku, 'code', 'sku_locked_set', 'message', format('Set %s has stock or cost history — its parent SKU cannot be renamed — nothing was saved', v_set.sku));
            end if;
            if exists (select 1 from public.product x where x.sku = v_newname || '-' || v_set.pack_factor::int::text and x.id <> v_set.id) or (v_newname || '-' || v_set.pack_factor::int::text) = any(v_newsku) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_sku_exists:' || v_newname || '-' || v_set.pack_factor::int::text, 'sku', v_sku, 'code', 'set_sku_exists', 'message', format('Set SKU %s already exists — nothing was saved', v_newname || '-' || v_set.pack_factor::int::text));
            end if;
            v_newsku := v_newsku || (v_newname || '-' || v_set.pack_factor::int::text);
          end loop;
          if v_cnt > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':set_renamed', 'sku', v_sku, 'code', 'set_renamed', 'message', format('%s set SKU(s) of %s will be renamed to %s-<factor> too — their names are not changed', v_cnt, v_sku, v_newname));
          end if;
          if public.product_has_events(p.id, p.sku) and not exists (select 1 from public.inv_ledger e where e.sku = p.sku) and not exists (select 1 from public.inv_layer l where l.sku = p.sku) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':sku_open_lines', 'sku', v_sku, 'code', 'sku_open_lines', 'message', format('SKU %s is already on order or document lines — they keep pointing at the product, but printed line text still shows %s', v_sku, v_sku));
          end if;
        end if;
      when 'pack_factor' then
        if p.parent_product_id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_a_set', 'sku', v_sku, 'code', 'not_a_set', 'message', format('SKU %s is not a set — pack factor belongs to sets only — nothing was saved', v_sku));
        elsif v_vtxt is null or v_vtxt !~ '^[0-9]+$' or v_vtxt::numeric < 2 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_factor_invalid', 'sku', v_sku, 'code', 'set_factor_invalid', 'message', format('Set %s: the pack factor must be a whole number of 2 or more (got %s) — nothing was saved', v_sku, coalesce(v_vtxt, 'nothing')));
        else
          select * into v_par from public.product x where x.id = p.parent_product_id;
          if public.product_has_events(p.id, p.sku) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_locked', 'sku', v_sku, 'code', 'set_locked', 'message', format('Set %s already has stock, cost or document lines — its pack factor cannot change — make a new set instead — nothing was saved', v_sku));
          end if;
          v_newname := v_par.sku || '-' || v_vtxt::numeric::int::text;
          if exists (select 1 from public.product x where x.sku = v_newname and x.id <> p.id) or v_newname = any(v_newsku) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_sku_exists:' || v_newname, 'sku', v_sku, 'code', 'set_sku_exists', 'message', format('Set SKU %s already exists — nothing was saved', v_newname));
          end if;
          v_newsku := v_newsku || v_newname;
          if not exists (select 1 from public.ref_unit u where u.name = v_vtxt::numeric::int::text and u.is_active) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':set_unit_unknown', 'sku', v_sku, 'code', 'set_unit_unknown', 'message', format('Set %s: there is no unit named %s — the set keeps uom %s but no unit id', v_sku, v_vtxt::numeric::int, v_vtxt::numeric::int));
          end if;
        end if;
      when 'parent_sku' then
        if p.parent_product_id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_a_set', 'sku', v_sku, 'code', 'not_a_set', 'message', format('SKU %s is not a set — a parent belongs to sets only — nothing was saved', v_sku));
        else
          select * into v_par from public.product x where x.sku = v_vtxt;
          if v_par.id is null or not v_par.is_active then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'sku', v_sku, 'code', 'parent_unknown', 'message', format('Set %s: the new parent %s does not exist or is inactive — nothing was saved', v_sku, coalesce(v_vtxt, '(none)')));
          elsif v_par.parent_product_id is not null then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_not_single', 'sku', v_sku, 'code', 'parent_not_single', 'message', format('Set %s: the new parent %s is itself a set — a parent must be a single — nothing was saved', v_sku, v_par.sku));
          else
            if public.product_has_events(p.id, p.sku) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_locked', 'sku', v_sku, 'code', 'set_locked', 'message', format('Set %s already has stock, cost or document lines — its parent cannot change — make a new set instead — nothing was saved', v_sku));
            end if;
            v_newname := v_par.sku || '-' || p.pack_factor::int::text;
            if exists (select 1 from public.product x where x.sku = v_newname and x.id <> p.id) or v_newname = any(v_newsku) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_sku_exists:' || v_newname, 'sku', v_sku, 'code', 'set_sku_exists', 'message', format('Set SKU %s already exists — nothing was saved', v_newname));
            end if;
            v_newsku := v_newsku || v_newname;
          end if;
        end if;
      else null;
      end case;

    elsif v_op = 'family_join' then
      select * into v_fam from public.product_family f where f.sku = trim(coalesce(v_c->>'family_sku', ''));
      if v_fam.id is null or not v_fam.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_unknown', 'sku', v_sku, 'code', 'family_unknown', 'message', format('SKU %s: family %s does not exist or is inactive — nothing was saved', v_sku, coalesce(nullif(trim(v_c->>'family_sku'), ''), '(none)')));
        continue;
      end if;
      if p.parent_product_id is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':set_not_family_member', 'sku', v_sku, 'code', 'set_not_family_member', 'message', format('SKU %s is a set — sets follow their single and are not family members — nothing was saved', v_sku));
        continue;
      end if;
      if p.family_id is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':already_in_family', 'sku', v_sku, 'code', 'already_in_family', 'message', format('SKU %s is already in family %s — leave it first — nothing was saved', v_sku, (select f.sku from public.product_family f where f.id = p.family_id)));
        continue;
      end if;
      if (p.id::text || '|family') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:family', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s family membership is changed twice in this paste — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|family');
      v_axes := (v_fam.option1_name is not null)::int + (v_fam.option2_name is not null)::int + (v_fam.option3_name is not null)::int;
      select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_c->'options', '[]'::jsonb)) with ordinality as t(x, o);
      if cardinality(v_opts) <> v_axes or exists (select 1 from unnest(v_opts) o where o = '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_count', 'sku', v_sku, 'code', 'option_count', 'message', format('SKU %s needs %s option value(s) for family %s — got %s — nothing was saved', v_sku, v_axes, v_fam.sku, coalesce(nullif(array_to_string(v_opts, ' / '), ''), 'none')));
        continue;
      end if;
      v_optkey := lower(array_to_string(v_opts, '|'));
      if (v_fam.id::text || '|' || v_optkey) = any(v_seenopt) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_duplicate_in_call', 'sku', v_sku, 'code', 'option_duplicate_in_call', 'message', format('SKU %s repeats the option values %s already used in this paste for family %s — nothing was saved', v_sku, array_to_string(v_opts, ' / '), v_fam.sku));
      end if;
      v_seenopt := v_seenopt || (v_fam.id::text || '|' || v_optkey);
      select x.sku, x.is_active into v_ex from public.product x
       where x.family_id = v_fam.id and x.id <> p.id and lower(array_to_string((array[trim(x.option1_value), trim(x.option2_value), trim(x.option3_value)])[1:v_axes], '|')) = v_optkey
       order by x.is_active desc, x.sku limit 1;
      if found then
        if v_ex.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_exists', 'sku', v_sku, 'code', 'option_exists', 'message', format('Family %s already has %s as %s — nothing was saved', v_fam.sku, array_to_string(v_opts, ' / '), v_ex.sku));
        else
          v_warns := v_warns || jsonb_build_object('key', v_key || ':option_inactive_exists', 'sku', v_sku, 'code', 'option_inactive_exists', 'message', format('Family %s has an inactive variant %s with %s — reactivating it may be the right move', v_fam.sku, v_ex.sku, array_to_string(v_opts, ' / ')));
        end if;
      end if;

    elsif v_op = 'family_leave' then
      if p.family_id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_in_family', 'sku', v_sku, 'code', 'not_in_family', 'message', format('SKU %s is not in a family — nothing was saved', v_sku));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:family', 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s family_leave: the family the screen saw is missing — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|family') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:family', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s family membership is changed twice in this paste — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|family');
      v_cur := (select f.sku from public.product_family f where f.id = p.family_id);
      if v_cur is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:family', 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the family of %s (now %s) — check again — nothing was saved', v_sku, coalesce(v_cur, '')));
      end if;

    elsif v_op = 'family_option' then
      if p.family_id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':not_in_family', 'sku', v_sku, 'code', 'not_in_family', 'message', format('SKU %s is not in a family — nothing was saved', v_sku));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:options', 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s family_option: the old option values the screen saw are missing — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|options') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:options', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s option values are changed twice in this paste — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|options');
      select * into v_fam from public.product_family f where f.id = p.family_id;
      v_axes := (v_fam.option1_name is not null)::int + (v_fam.option2_name is not null)::int + (v_fam.option3_name is not null)::int;
      v_cur := array_to_string((array[p.option1_value, p.option2_value, p.option3_value])[1:v_axes], '|');
      if v_cur is distinct from (select string_agg(coalesce(t.x, ''), '|' order by t.o) from jsonb_array_elements_text(coalesce(v_c->'old', '[]'::jsonb)) with ordinality as t(x, o)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:options', 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the option values of %s (now %s) — check again — nothing was saved', v_sku, replace(coalesce(v_cur, ''), '|', ' / ')));
        continue;
      end if;
      select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_c->'options', '[]'::jsonb)) with ordinality as t(x, o);
      if cardinality(v_opts) <> v_axes or exists (select 1 from unnest(v_opts) o where o = '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_count', 'sku', v_sku, 'code', 'option_count', 'message', format('SKU %s needs %s option value(s) for family %s — got %s — nothing was saved', v_sku, v_axes, v_fam.sku, coalesce(nullif(array_to_string(v_opts, ' / '), ''), 'none')));
        continue;
      end if;
      v_optkey := lower(array_to_string(v_opts, '|'));
      if (v_fam.id::text || '|' || v_optkey) = any(v_seenopt) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_duplicate_in_call', 'sku', v_sku, 'code', 'option_duplicate_in_call', 'message', format('SKU %s repeats the option values %s already used in this paste for family %s — nothing was saved', v_sku, array_to_string(v_opts, ' / '), v_fam.sku));
      end if;
      v_seenopt := v_seenopt || (v_fam.id::text || '|' || v_optkey);
      select x.sku, x.is_active into v_ex from public.product x
       where x.family_id = v_fam.id and x.id <> p.id and lower(array_to_string((array[trim(x.option1_value), trim(x.option2_value), trim(x.option3_value)])[1:v_axes], '|')) = v_optkey
       order by x.is_active desc, x.sku limit 1;
      if found then
        if v_ex.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':option_exists', 'sku', v_sku, 'code', 'option_exists', 'message', format('Family %s already has %s as %s — nothing was saved', v_fam.sku, array_to_string(v_opts, ' / '), v_ex.sku));
        else
          v_warns := v_warns || jsonb_build_object('key', v_key || ':option_inactive_exists', 'sku', v_sku, 'code', 'option_inactive_exists', 'message', format('Family %s has an inactive variant %s with %s — reactivating it may be the right move', v_fam.sku, v_ex.sku, array_to_string(v_opts, ' / ')));
        end if;
      end if;

    -- ── prod-4b: 바코드(판정 179 · 188 · 138 — R2 는 안 본다) ───────────────────────────────────────────────────
    elsif v_op in ('barcode_add', 'barcode_off', 'barcode_primary') then
      v_bc := trim(coalesce(v_c->>'barcode', ''));
      if v_bc = '' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_empty', 'sku', v_sku, 'code', 'barcode_empty', 'message', format('SKU %s has an empty barcode — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|bc|' || v_bc) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_bc, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Barcode %s of %s is changed twice in this paste — nothing was saved', v_bc, v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|bc|' || v_bc);
      select pb.id, pb.is_active, pb.is_primary into v_row from public.product_barcode pb where pb.product_id = p.id and pb.barcode = v_bc;
      if v_op = 'barcode_add' then
        if v_row.id is not null and v_row.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_exists:' || v_bc, 'sku', v_sku, 'code', 'barcode_exists', 'message', format('Barcode %s is already on %s — nothing was saved', v_bc, v_sku));
        end if;
        if ('B|' || v_bc) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_duplicate_in_call:' || v_bc, 'sku', v_sku, 'code', 'barcode_duplicate_in_call', 'message', format('Barcode %s is added to two products in this paste — nothing was saved', v_bc));
        end if;
        v_seen := v_seen || ('B|' || v_bc);
        select x.sku, (x.is_active and pb.is_active) as active into v_ex
          from public.product_barcode pb join public.product x on x.id = pb.product_id
         where pb.barcode = v_bc and pb.product_id <> p.id order by (x.is_active and pb.is_active) desc, x.sku limit 1;
        if found then
          if v_ex.active then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_active_elsewhere:' || v_bc, 'sku', v_sku, 'code', 'barcode_active_elsewhere', 'message', format('Barcode %s already belongs to active product %s — a scan would pick the wrong product — nothing was saved', v_bc, v_ex.sku));
          else
            v_warns := v_warns || jsonb_build_object('key', v_key || ':barcode_inactive_elsewhere:' || v_bc, 'sku', v_sku, 'code', 'barcode_inactive_elsewhere', 'message', format('Barcode %s is also on inactive product %s', v_bc, v_ex.sku));
          end if;
        end if;
        if v_bc !~ '^[0-9]+$' or length(v_bc) not in (8, 12, 13, 14) then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':barcode_shape:' || v_bc, 'sku', v_sku, 'code', 'barcode_shape', 'message', format('Barcode %s is not 8, 12, 13 or 14 digits', v_bc));
        elsif length(v_bc) in (12, 13) and not public.product_gtin_ok(v_bc) then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':barcode_check_digit:' || v_bc, 'sku', v_sku, 'code', 'barcode_check_digit', 'message', format('Barcode %s fails the check digit — a typo is likely', v_bc));
        end if;
      else
        if v_row.id is null or not v_row.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':barcode_not_found:' || v_bc, 'sku', v_sku, 'code', 'barcode_not_found', 'message', format('SKU %s has no active barcode %s — nothing was saved', v_sku, v_bc));
          continue;
        end if;
        if v_op = 'barcode_off' then
          if v_row.is_primary then                                                               -- ⬜1: 대표를 끄면 대표 없음 — 올리지 않고 알린다
            v_warns := v_warns || jsonb_build_object('key', v_key || ':primary_off:' || v_bc, 'sku', v_sku, 'code', 'primary_off', 'message', format('Barcode %s is the primary barcode of %s — after it is turned off the product has no primary — pick another one', v_bc, v_sku));
          end if;
          if (select count(*) from public.product_barcode pb where pb.product_id = p.id and pb.is_active) = 1 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':barcode_missing', 'sku', v_sku, 'code', 'barcode_missing', 'message', format('SKU %s has no barcode — it cannot be scanned in picking, packing or receiving', v_sku));
          end if;
        end if;
      end if;

    -- ── prod-4b: 판매가(판정 178 · source manual ⬜2) ──────────────────────────────────────────────────────────
    elsif v_op in ('price_set', 'price_off') then
      select * into v_tier from public.ref_price_tier t where t.id = (v_c->>'tier_id')::uuid and t.is_active and t.purpose = 'sale';
      if v_c->>'tier_id' is null or v_tier.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_invalid', 'sku', v_sku, 'code', 'tier_invalid', 'message', format('SKU %s: a price tier is missing, inactive or not a sale tier — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|pr|' || v_tier.id::text) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_tier.code, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s price for tier %s is changed twice in this paste — nothing was saved', v_sku, v_tier.name));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|pr|' || v_tier.id::text);
      select pp.id, pp.is_active, pp.price into v_row from public.product_price pp where pp.product_id = p.id and pp.tier_id = v_tier.id;
      if v_op = 'price_set' then
        if (v_c->>'price') is null or (v_c->>'price') !~ '^[0-9]+(\.[0-9]+)?$' or (v_c->>'price')::numeric <= 0 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':price_not_positive:' || v_tier.code, 'sku', v_sku, 'code', 'price_not_positive', 'message', format('SKU %s: a price must be greater than 0 (leave the tier out for no price) — nothing was saved', v_sku));
          continue;
        end if;
        if v_row.id is not null and v_row.is_active then                                        -- 있는 켜진 줄 고치기 — old 필수 · 숫자 비교
          if not (v_c ? 'old') then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:price:' || v_tier.code, 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s price (%s): the old value the screen saw is missing — nothing was saved', v_sku, v_tier.name));
          elsif nullif(v_c->>'old', '') is null or (v_c->>'old') !~ '^[0-9]+(\.[0-9]+)?$' or v_row.price <> (v_c->>'old')::numeric then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:price:' || v_tier.code, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the %s price of %s (now %s) — check again — nothing was saved', v_tier.name, v_sku, v_row.price));
          end if;
        end if;
        if v_c ? 'formula' then                                                                 -- price-1(묶음 6 · 판정 222 · 223): 식 표시 → 그 식의 공급처 줄의 지금 Latest 로 다시 계산해 같을 때만 formula
          if p.parent_product_id is not null then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_on_set:' || v_tier.code, 'sku', v_sku, 'code', 'formula_on_set', 'message', format('Set %s: a price formula applies to singles only — sets take the calculated price or a fixed price — nothing was saved', v_sku));
            continue;
          end if;
          v_fml := public.price_formula_calc(v_c->'formula', null);
          if coalesce(jsonb_typeof(v_fml->'formula'), 'null') = 'null' then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_invalid:' || v_tier.code, 'sku', v_sku, 'code', 'formula_invalid', 'message', format('SKU %s: %s — nothing was saved', v_sku, coalesce(v_fml->'blocks'->0->>'message', 'the price formula is invalid')));
            continue;
          end if;
          v_fsup := (v_fml->'formula'->>'supplier_id')::uuid;
          v_fcost := null; v_fprice := null;
          select ps.cost into v_fcost from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = v_fsup and ps.is_active;
          if v_fcost is not null and v_fcost > 0 then
            v_fml := public.price_formula_calc(v_c->'formula', v_fcost);
            select (t->>'price')::numeric into v_fprice from jsonb_array_elements(coalesce(v_fml->'tiers', '[]'::jsonb)) as t where (t->>'tier_id')::uuid = v_tier.id;
          end if;
          if v_fprice is not null and v_fprice = (v_c->>'price')::numeric then
            v_fver := v_fver || jsonb_build_object(v_i::text, jsonb_build_object('source', 'formula', 'formula_id', v_fml->'formula'->>'id', 'supplier_id', v_fsup));
            if (v_fml->'formula'->>'id') is null then
              v_warns := v_warns || jsonb_build_object('key', v_key || ':formula_unsaved:' || v_tier.code, 'sku', v_sku, 'code', 'formula_unsaved', 'message', format('SKU %s %s: the price comes from a one-off formula that is not saved — it is stored as a formula price but the product will not remember which formula', v_sku, v_tier.name));
            end if;
          else
            v_warns := v_warns || jsonb_build_object('key', v_key || ':formula_mismatch:' || v_tier.code, 'sku', v_sku, 'code', 'formula_mismatch', 'message',
              format('SKU %s %s: %s is not what the formula gives now (%s from cost %s) — it will be saved as a manual price', v_sku, v_tier.name, (v_c->>'price')::numeric, coalesce(v_fprice::text, 'nothing'), coalesce(v_fcost::text, 'none')));
          end if;
        end if;
      else
        if v_row.id is null or not v_row.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':price_not_found:' || v_tier.code, 'sku', v_sku, 'code', 'price_not_found', 'message', format('SKU %s has no active %s price — nothing was saved', v_sku, v_tier.name));
          continue;
        end if;
        if not (v_c ? 'old') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:price:' || v_tier.code, 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s price (%s): the old value the screen saw is missing — nothing was saved', v_sku, v_tier.name));
          continue;
        elsif nullif(v_c->>'old', '') is null or (v_c->>'old') !~ '^[0-9]+(\.[0-9]+)?$' or v_row.price <> (v_c->>'old')::numeric then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:price:' || v_tier.code, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the %s price of %s (now %s) — check again — nothing was saved', v_tier.name, v_sku, v_row.price));
          continue;
        end if;
        if p.parent_product_id is not null then                                                 -- 세트 고정가 끄기 → 계산 가격으로(값까지)
          select round(pp.price * p.pack_factor * (1 - coalesce(p.set_discount_pct, 0) / 100), 2) into v_calc
            from public.product_price pp where pp.product_id = p.parent_product_id and pp.tier_id = v_tier.id and pp.is_active;
          v_warns := v_warns || jsonb_build_object('key', v_key || ':price_set_calc:' || v_tier.code, 'sku', v_sku, 'code', 'price_set_calc', 'message',
            case when v_calc is null then format('Set %s: without its fixed %s price it has no price at all — its single has no %s price to calculate from', v_sku, v_tier.name, v_tier.name)
                 else format('Set %s: without its fixed %s price it goes back to the calculated price %s (single price × %s%s)', v_sku, v_tier.name, v_calc, p.pack_factor::int, case when coalesce(p.set_discount_pct, 0) > 0 then format(' − %s%%', p.set_discount_pct) else '' end) end);
        elsif (select count(*) from public.product_price pp join public.ref_price_tier t on t.id = pp.tier_id where pp.product_id = p.id and pp.is_active and t.purpose = 'sale' and t.is_active) = 1 then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':price_missing', 'sku', v_sku, 'code', 'price_missing', 'message', format('SKU %s has no sale price — order lines will have no price', v_sku));
        end if;
      end if;

    -- ── prod-4b: 공급처(판정 178 · 세트는 알리기 ⬜3 · source manual ⬜2) ────────────────────────────────────────
    elsif v_op in ('supplier_set', 'supplier_default', 'supplier_off') then
      select * into v_sup from public.supplier s where s.id = (v_c->>'supplier_id')::uuid and s.is_active;
      if v_c->>'supplier_id' is null or v_sup.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':supplier_unknown', 'sku', v_sku, 'code', 'supplier_unknown', 'message', format('SKU %s: a supplier is missing, unknown or inactive — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|sp|' || v_sup.id::text) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_sup.name, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s supplier %s is changed twice in this paste — nothing was saved', v_sku, v_sup.name));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|sp|' || v_sup.id::text);
      select ps.id, ps.is_active, ps.is_default, ps.supplier_sku, ps.cost, ps.fixed_cost, ps.currency_id into v_row from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = v_sup.id;
      if v_op = 'supplier_set' then
        if v_c->>'currency_id' is not null and not exists (select 1 from public.ref_currency c where c.id = (v_c->>'currency_id')::uuid and c.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_unknown:' || v_sup.name, 'sku', v_sku, 'code', 'currency_unknown', 'message', format('SKU %s: a supplier currency does not exist or is inactive — nothing was saved', v_sku));
        end if;
        if (v_c ? 'cost' and v_c->>'cost' is not null and (v_c->>'cost') !~ '^[0-9]+(\.[0-9]+)?$') or (v_c ? 'fixed_cost' and v_c->>'fixed_cost' is not null and (v_c->>'fixed_cost') !~ '^[0-9]+(\.[0-9]+)?$') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_sup.name, 'sku', v_sku, 'code', 'value_invalid', 'message', format('SKU %s supplier %s: cost and fixed cost must be numbers of 0 or more — nothing was saved', v_sku, v_sup.name));
        end if;
        if p.parent_product_id is not null then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':set_supplier:' || v_sup.name, 'sku', v_sku, 'code', 'set_supplier', 'message', format('Set %s gets its own supplier %s — sets are normally bought as their single', v_sku, v_sup.name));
        end if;
        if v_row.id is not null and v_row.is_active then                                        -- 있는 켜진 줄 고치기 — 바꾸는 칸마다 old
          v_oldv := coalesce(v_c->'old', '{}'::jsonb);
          if jsonb_typeof(v_oldv) <> 'object' or (v_c ? 'supplier_sku' and not (v_oldv ? 'supplier_sku')) or (v_c ? 'cost' and not (v_oldv ? 'cost')) or (v_c ? 'fixed_cost' and not (v_oldv ? 'fixed_cost')) or (v_c ? 'currency_id' and not (v_oldv ? 'currency_id')) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:supplier:' || v_sup.name, 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s supplier %s: the old value the screen saw is missing for a field being changed — nothing was saved', v_sku, v_sup.name));
          elsif (v_c ? 'supplier_sku' and v_row.supplier_sku is distinct from nullif(v_oldv->>'supplier_sku', ''))
             or (v_c ? 'cost' and v_row.cost is distinct from nullif(v_oldv->>'cost', '')::numeric)
             or (v_c ? 'fixed_cost' and v_row.fixed_cost is distinct from nullif(v_oldv->>'fixed_cost', '')::numeric)
             or (v_c ? 'currency_id' and v_row.currency_id::text is distinct from nullif(v_oldv->>'currency_id', '')) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:supplier:' || v_sup.name, 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed supplier %s of %s (now sku %s · cost %s · fixed %s) — check again — nothing was saved', v_sup.name, v_sku, coalesce(v_row.supplier_sku, '-'), coalesce(v_row.cost::text, '-'), coalesce(v_row.fixed_cost::text, '-')));
          end if;
        end if;
      else
        if v_row.id is null or not v_row.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':supplier_not_found:' || v_sup.name, 'sku', v_sku, 'code', 'supplier_not_found', 'message', format('SKU %s has no active supplier %s — nothing was saved', v_sku, v_sup.name));
          continue;
        end if;
        if v_op = 'supplier_off' then
          if v_row.is_default then                                                               -- ⬜1: 기본을 끄면 기본 없음 — 올리지 않고 알린다
            v_warns := v_warns || jsonb_build_object('key', v_key || ':default_off:' || v_sup.name, 'sku', v_sku, 'code', 'default_off', 'message', format('%s is the default supplier of %s — after it is turned off the product has no default — pick another one', v_sup.name, v_sku));
          end if;
          if (select count(*) from public.product_supplier ps where ps.product_id = p.id and ps.is_active) = 1 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':supplier_missing', 'sku', v_sku, 'code', 'supplier_missing', 'message', format('SKU %s has no supplier — it will not appear as a purchase order candidate', v_sku));
          end if;
        end if;
      end if;

    -- ── surcharge-4a(판정 231 · 232 · 묶음 2): 상품의 관세 그룹 — {sku, group_id | null, old} · 그룹은 켜진 것만 · 세트는 막기(SO 줄은 낱개) · old 는 지금 그룹 id(없으면 빈 값) ──
    elsif v_op = 'surcharge_group_set' then
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:surcharge_group', 'sku', v_sku, 'code', 'old_missing', 'message', format('SKU %s surcharge group: the old value the screen saw is missing — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|surcharge_group') = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:surcharge_group', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s surcharge group is changed twice in this paste — nothing was saved', v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|surcharge_group');
      if p.surcharge_group_id::text is distinct from nullif(v_c->>'old', '') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:surcharge_group', 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the surcharge group of %s (now %s) — check again — nothing was saved', v_sku, coalesce((select g.name from public.so_surcharge_group g where g.id = p.surcharge_group_id), '(none)')));
        continue;
      end if;
      if p.parent_product_id is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':surcharge_on_set', 'sku', v_sku, 'code', 'surcharge_on_set', 'message', format('Set %s cannot carry a surcharge group — sales order lines are singles, put the group on the single — nothing was saved', v_sku));
        continue;
      end if;
      if nullif(v_c->>'group_id', '') is not null then
        v_grp := null;
        if (v_c->>'group_id') ~ '^[0-9a-fA-F-]{36}$' then select * into v_grp from public.so_surcharge_group g where g.id = (v_c->>'group_id')::uuid; end if;
        if v_grp.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':surcharge_group_unknown', 'sku', v_sku, 'code', 'surcharge_group_unknown', 'message', format('SKU %s: that surcharge group does not exist — nothing was saved', v_sku));
          continue;
        end if;
        if not v_grp.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':surcharge_group_inactive', 'sku', v_sku, 'code', 'surcharge_group_inactive', 'message', format('SKU %s: surcharge group "%s" is off — turn it on first or pick another — nothing was saved', v_sku, v_grp.name));
          continue;
        end if;
      end if;

    -- ── img-1: 사진(판정 193 · 188 모양 — 끄기 · 파일은 지우지 않는다 · 경로는 <상품 id>/… · 저장소에 실재해야 등록) ──────────
    elsif v_op = 'image_add' then
      v_path := trim(coalesce(v_c->>'storage_path', ''));
      if v_path = '' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_path_missing', 'sku', v_sku, 'code', 'image_path_missing', 'message', format('SKU %s: the image has no storage path — nothing was saved', v_sku));
        continue;
      end if;
      if ('I|' || v_path) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_path, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Image %s appears twice in this paste — nothing was saved', v_path));
        continue;
      end if;
      v_seen := v_seen || ('I|' || v_path);
      if left(v_path, 37) <> p.id::text || '/' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_path_mismatch:' || v_path, 'sku', v_sku, 'code', 'image_path_mismatch', 'message', format('Image %s is not stored under the folder of %s (%s/…) — nothing was saved', v_path, v_sku, p.id));
      end if;
      if coalesce(v_c->>'content_type', '') not in ('image/jpeg', 'image/png', 'image/webp') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_type_invalid:' || v_path, 'sku', v_sku, 'code', 'image_type_invalid', 'message', format('Image %s: only JPEG, PNG and WebP are accepted (got %s) — nothing was saved', v_path, coalesce(v_c->>'content_type', 'nothing')));
      end if;
      if not exists (select 1 from storage.objects o where o.bucket_id = 'product-images' and o.name = v_path) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_object_missing:' || v_path, 'sku', v_sku, 'code', 'image_object_missing', 'message', format('Image %s is not in the product-images bucket — upload it first — nothing was saved', v_path));
      end if;
      select i.id, i.is_active, i.product_id into v_img from public.product_image i where i.storage_path = v_path;
      if v_img.id is not null and (v_img.is_active or v_img.product_id <> p.id) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_exists:' || v_path, 'sku', v_sku, 'code', 'image_exists', 'message', format('Image %s is already registered — nothing was saved', v_path));
      end if;
      if v_c ? 'byte_size' and v_c->>'byte_size' is not null and ((v_c->>'byte_size') !~ '^[0-9]+$' or (v_c->>'byte_size')::bigint <= 0) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_path, 'sku', v_sku, 'code', 'value_invalid', 'message', format('Image %s: byte_size must be a whole number above 0 — nothing was saved', v_path));
      end if;

    elsif v_op in ('image_off', 'image_primary') then
      select i.id, i.is_active, i.is_primary into v_img from public.product_image i where i.product_id = p.id and i.id = nullif(trim(coalesce(v_c->>'image_id', '')), '')::uuid;
      if v_img.id is null or not v_img.is_active then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:' || coalesce(v_c->>'image_id', '(none)'), 'sku', v_sku, 'code', 'image_not_found', 'message', format('SKU %s has no active image %s — nothing was saved', v_sku, coalesce(v_c->>'image_id', '(none)')));
        continue;
      end if;
      if (p.id::text || '|img|' || v_img.id::text) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_img.id::text, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Image %s of %s is changed twice in this paste — nothing was saved', v_img.id, v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|img|' || v_img.id::text);
      if v_op = 'image_off' and v_img.is_primary then                                          -- prod-4b primary_off 와 같은 태도 — 올리지 않고 알린다
        v_warns := v_warns || jsonb_build_object('key', v_key || ':image_primary_off:' || v_img.id::text, 'sku', v_sku, 'code', 'image_primary_off', 'message', format('Image %s is the primary image of %s — after it is turned off the product has no primary image — pick another one', v_img.id, v_sku));
      end if;

    elsif v_op = 'image_order' then
      select coalesce(array_agg(nullif(trim(x), '')::uuid order by o), '{}') into v_ids from jsonb_array_elements_text(coalesce(v_c->'image_ids', '[]'::jsonb)) with ordinality as t(x, o);
      if cardinality(v_ids) = 0 then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:(none)', 'sku', v_sku, 'code', 'image_not_found', 'message', format('SKU %s: image_order needs at least one image id — nothing was saved', v_sku));
        continue;
      end if;
      if (select count(distinct u) from unnest(v_ids) u) <> cardinality(v_ids) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:order', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('SKU %s: image_order lists an image twice — nothing was saved', v_sku));
        continue;
      end if;
      if (select count(*) from public.product_image i where i.product_id = p.id and i.is_active and i.id = any(v_ids)) <> cardinality(v_ids) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':image_not_found:order', 'sku', v_sku, 'code', 'image_not_found', 'message', format('SKU %s: image_order names an image that is not an active image of this product — nothing was saved', v_sku));
      end if;
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 줄 순서대로 · 한 트랜잭션 · unique 23505 는 문장으로
  begin
    v_i := 0;
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op'; v_field := v_c->>'field'; v_val := v_c->'value'; v_vtxt := nullif(trim(coalesce(v_c->>'value', '')), '');
      if v_op = 'family_head_set' then
        select * into v_fam from public.product_family f where f.id = (v_idmap->>('F' || trim(coalesce(v_c->>'family_sku', ''))))::uuid;
        case v_field
        when 'name' then update public.product_family set name = v_vtxt where id = v_fam.id;
        when 'brand_id' then
          update public.product x set brand_id = v_vtxt::uuid, brand_name = (select b.name from public.ref_brand b where b.id = v_vtxt::uuid) where x.family_id = v_fam.id and x.brand_id is not distinct from v_fam.brand_id;   -- 판정 191
          update public.product_family set brand_id = v_vtxt::uuid, brand_name = (select b.name from public.ref_brand b where b.id = v_vtxt::uuid) where id = v_fam.id;
        when 'category_id' then
          update public.product x set category_id = v_vtxt::uuid, category_name = (select c.name from public.ref_category c where c.id = v_vtxt::uuid) where x.family_id = v_fam.id and x.category_id is not distinct from v_fam.category_id;   -- 판정 191
          update public.product_family set category_id = v_vtxt::uuid, category_name = (select c.name from public.ref_category c where c.id = v_vtxt::uuid) where id = v_fam.id;
        when 'unit_id' then
          update public.product x set unit_id = v_vtxt::uuid, uom_name = (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) where x.family_id = v_fam.id and x.unit_id is not distinct from v_fam.unit_id;   -- 판정 192
          update public.product_family set unit_id = v_vtxt::uuid, uom_name = (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) where id = v_fam.id;
        when 'note' then update public.product_family set note = v_vtxt where id = v_fam.id;
        when 'is_active' then update public.product_family set is_active = (v_val)::boolean where id = v_fam.id;
        when 'option1_name' then update public.product_family set option1_name = v_vtxt where id = v_fam.id;
        when 'option2_name' then update public.product_family set option2_name = v_vtxt where id = v_fam.id;
        when 'option3_name' then update public.product_family set option3_name = v_vtxt where id = v_fam.id;
        end case;
      else
        select * into p from public.product x where x.id = (v_idmap->>('P' || trim(coalesce(v_c->>'sku', ''))))::uuid;   -- 옛 SKU → id(⬜2)
        if v_op = 'set' then
          case v_field
          when 'name' then update public.product set name = v_vtxt where id = p.id;
          when 'brand_id' then update public.product set brand_id = v_vtxt::uuid, brand_name = (select b.name from public.ref_brand b where b.id = v_vtxt::uuid) where id = p.id;
          when 'category_id' then update public.product set category_id = v_vtxt::uuid, category_name = (select c.name from public.ref_category c where c.id = v_vtxt::uuid) where id = p.id;
          when 'unit_id' then update public.product set unit_id = v_vtxt::uuid, uom_name = (select u.name from public.ref_unit u where u.id = v_vtxt::uuid) where id = p.id;
          when 'weight' then update public.product set weight = v_vtxt::numeric where id = p.id;
          when 'weight_unit' then update public.product set weight_unit = v_vtxt where id = p.id;
          when 'note' then update public.product set note = v_vtxt where id = p.id;
          when 'is_discontinued' then update public.product set is_discontinued = (v_val)::boolean where id = p.id;
          when 'set_discount_pct' then update public.product set set_discount_pct = v_vtxt::numeric where id = p.id;
          when 'is_active' then update public.product set is_active = (v_val)::boolean where id = p.id;
          when 'sku' then
            update public.product set sku = v_vtxt where id = p.id;                           -- 트리거 product_sku_lock 이 마지막 문(IM136)
            update public.product x set sku = v_vtxt || '-' || x.pack_factor::int::text where x.parent_product_id = p.id;   -- 판정 189 · 이름은 그대로
          when 'pack_factor' then
            select * into v_par from public.product x where x.id = p.parent_product_id;
            update public.product set pack_factor = v_vtxt::numeric, sku = v_par.sku || '-' || v_vtxt::numeric::int::text, uom_name = v_vtxt::numeric::int::text,
                   unit_id = (select u.id from public.ref_unit u where u.name = v_vtxt::numeric::int::text and u.is_active) where id = p.id;
          when 'parent_sku' then
            select * into v_par from public.product x where x.sku = v_vtxt;
            update public.product set parent_product_id = v_par.id, sku = v_par.sku || '-' || p.pack_factor::int::text where id = p.id;
          end case;
        elsif v_op = 'family_join' then
          select * into v_fam from public.product_family f where f.sku = trim(v_c->>'family_sku');
          select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_c->'options', '[]'::jsonb)) with ordinality as t(x, o);
          update public.product set family_id = v_fam.id, option1_value = v_opts[1], option2_value = v_opts[2], option3_value = v_opts[3] where id = p.id;
        elsif v_op = 'family_leave' then
          update public.product set family_id = null, option1_value = null, option2_value = null, option3_value = null where id = p.id;
        elsif v_op = 'family_option' then
          select coalesce(array_agg(trim(t.x) order by t.o), '{}') into v_opts from jsonb_array_elements_text(coalesce(v_c->'options', '[]'::jsonb)) with ordinality as t(x, o);
          update public.product set option1_value = v_opts[1], option2_value = v_opts[2], option3_value = v_opts[3] where id = p.id;
        elsif v_op = 'barcode_add' then                                                        -- prod-4b: 꺼진 같은 줄이 있으면 켠다(행 수 그대로 · 판정 188) · 켜진 바코드가 없으면 대표
          v_bc := trim(v_c->>'barcode');
          if exists (select 1 from public.product_barcode pb where pb.product_id = p.id and pb.barcode = v_bc) then
            update public.product_barcode set is_active = true, source = 'manual', is_primary = (is_primary or not exists (select 1 from public.product_barcode q where q.product_id = p.id and q.is_active)) where product_id = p.id and barcode = v_bc;
          else
            insert into public.product_barcode (product_id, barcode, is_primary, source) values (p.id, v_bc, not exists (select 1 from public.product_barcode q where q.product_id = p.id and q.is_active), 'manual');
          end if;
        elsif v_op = 'barcode_off' then
          update public.product_barcode set is_active = false, is_primary = false, source = 'manual' where product_id = p.id and barcode = trim(v_c->>'barcode');
        elsif v_op = 'barcode_primary' then
          update public.product_barcode set is_primary = (barcode = trim(v_c->>'barcode')) where product_id = p.id and (is_primary or barcode = trim(v_c->>'barcode'));
        elsif v_op = 'price_set' then
          v_src := coalesce(v_fver->(v_i::text)->>'source', 'manual');                                                                   -- price-1: 검사가 정한 출처(formula 는 다시 계산해 같았을 때만 · 아니면 지금처럼 manual)
          if exists (select 1 from public.product_price pp where pp.product_id = p.id and pp.tier_id = (v_c->>'tier_id')::uuid) then
            update public.product_price set price = (v_c->>'price')::numeric, is_active = true, source = v_src, price_set_at = now(), price_set_by = v_staff, updated_by = v_staff where product_id = p.id and tier_id = (v_c->>'tier_id')::uuid;
          else
            insert into public.product_price (product_id, tier_id, price, source, price_set_by, updated_by) values (p.id, (v_c->>'tier_id')::uuid, (v_c->>'price')::numeric, v_src, v_staff, v_staff);
          end if;
          if v_src = 'formula' and (v_fver->(v_i::text)->>'formula_id') is not null then                                                 -- price-1(판정 223): 상품의 공급처 줄이 어느 식인지 기억(통째 식은 id 가 없다)
            update public.product_supplier set price_formula_id = (v_fver->(v_i::text)->>'formula_id')::uuid where product_id = p.id and supplier_id = (v_fver->(v_i::text)->>'supplier_id')::uuid and is_active;
          end if;
        elsif v_op = 'price_off' then
          update public.product_price set is_active = false, source = 'manual', updated_by = v_staff where product_id = p.id and tier_id = (v_c->>'tier_id')::uuid;
        elsif v_op = 'supplier_set' then
          if exists (select 1 from public.product_supplier ps where ps.product_id = p.id and ps.supplier_id = (v_c->>'supplier_id')::uuid) then
            update public.product_supplier set is_active = true, source = 'manual',
                   supplier_sku = case when v_c ? 'supplier_sku' then nullif(trim(v_c->>'supplier_sku'), '') else supplier_sku end,
                   cost         = case when v_c ? 'cost' then (v_c->>'cost')::numeric else cost end,
                   fixed_cost   = case when v_c ? 'fixed_cost' then (v_c->>'fixed_cost')::numeric else fixed_cost end,
                   currency_id  = case when v_c ? 'currency_id' then (v_c->>'currency_id')::uuid else currency_id end,
                   is_default   = is_default or not exists (select 1 from public.product_supplier q where q.product_id = p.id and q.is_active)
             where product_id = p.id and supplier_id = (v_c->>'supplier_id')::uuid;
          else
            insert into public.product_supplier (product_id, supplier_id, supplier_sku, cost, fixed_cost, currency_id, is_default, source)
            values (p.id, (v_c->>'supplier_id')::uuid, nullif(trim(v_c->>'supplier_sku'), ''), (v_c->>'cost')::numeric, (v_c->>'fixed_cost')::numeric, (v_c->>'currency_id')::uuid,
                    not exists (select 1 from public.product_supplier q where q.product_id = p.id and q.is_active), 'manual');
          end if;
        elsif v_op = 'supplier_default' then
          update public.product_supplier set is_default = (supplier_id = (v_c->>'supplier_id')::uuid) where product_id = p.id and (is_default or supplier_id = (v_c->>'supplier_id')::uuid);
        elsif v_op = 'supplier_off' then
          update public.product_supplier set is_active = false, is_default = false, source = 'manual' where product_id = p.id and supplier_id = (v_c->>'supplier_id')::uuid;
        elsif v_op = 'surcharge_group_set' then                                                -- surcharge-4a(묶음 2): 그룹 달기 · 떼기(null) — 줄에는 손대지 않는다(묶음 5 · 새로 들어오는 줄부터)
          update public.product set surcharge_group_id = nullif(v_c->>'group_id', '')::uuid where id = p.id;
        elsif v_op = 'image_add' then                                                          -- img-1: 첫 켜진 사진이면 대표 · primary:true 면 대표(다른 대표는 내린다) · 꺼진 같은 경로는 켠다
          v_path := trim(v_c->>'storage_path');
          if coalesce((v_c->>'primary')::boolean, false) then
            update public.product_image set is_primary = false where product_id = p.id and is_primary;
          end if;
          if exists (select 1 from public.product_image i where i.storage_path = v_path) then
            update public.product_image set is_active = true, source = 'manual', content_type = v_c->>'content_type', byte_size = (v_c->>'byte_size')::bigint, width = (v_c->>'width')::int, height = (v_c->>'height')::int,
                   file_name = nullif(trim(v_c->>'file_name'), ''), updated_by = v_staff,
                   is_primary = coalesce((v_c->>'primary')::boolean, false) or not exists (select 1 from public.product_image q where q.product_id = p.id and q.is_active)
             where storage_path = v_path;
          else
            insert into public.product_image (product_id, storage_path, content_type, byte_size, width, height, file_name, source, updated_by, is_primary, sort_order)
            values (p.id, v_path, v_c->>'content_type', (v_c->>'byte_size')::bigint, (v_c->>'width')::int, (v_c->>'height')::int, nullif(trim(v_c->>'file_name'), ''), 'manual', v_staff,
                    coalesce((v_c->>'primary')::boolean, false) or not exists (select 1 from public.product_image q where q.product_id = p.id and q.is_active),
                    coalesce((select max(q.sort_order) + 1 from public.product_image q where q.product_id = p.id), 1));
          end if;
        elsif v_op = 'image_off' then
          update public.product_image set is_active = false, is_primary = false, updated_by = v_staff where product_id = p.id and id = (v_c->>'image_id')::uuid;
        elsif v_op = 'image_primary' then
          update public.product_image set is_primary = (id = (v_c->>'image_id')::uuid), updated_by = v_staff where product_id = p.id and (is_primary or id = (v_c->>'image_id')::uuid);
        elsif v_op = 'image_order' then
          select coalesce(array_agg(nullif(trim(x), '')::uuid order by o), '{}') into v_ids from jsonb_array_elements_text(coalesce(v_c->'image_ids', '[]'::jsonb)) with ordinality as t(x, o);
          update public.product_image i set sort_order = u.o, updated_by = v_staff from unnest(v_ids) with ordinality as u(id, o) where i.id = u.id and i.product_id = p.id;
        end if;
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'Someone just created one of these SKUs (%) — check again — nothing was saved', coalesce(sqlerrm, '');
  end;

  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.product_update(jsonb, boolean, text[]) from public, anon;
grant execute on function public.product_update(jsonb, boolean, text[]) to authenticated;
comment on function public.product_update(jsonb, boolean, text[]) is
  '⭐ 상품 고치기 창구(판정 187 ~ 194 · 222 · 223 · 231 · 232 · 2026-10-01 prod-4a + 4b + img-1 + price-1 · 2026-10-02 surcharge-4a) — security definer · 첫 줄 ims_require_write(master). p_changes = 바꿀 것 목록(최대 1,000 줄) · 줄 = {sku, op, …, old} · op 열여덟: set(칸 하나 — name · brand_id · category_id · unit_id · weight · weight_unit · note · is_discontinued · set_discount_pct · sku · is_active · pack_factor · parent_sku) · family_join {sku, family_sku, options[]} · family_leave {sku, old} · family_option {sku, options[], old[]} · family_head_set {family_sku, field, value, old} · barcode_add/barcode_off/barcode_primary {sku, barcode} · price_set {sku, tier_id, price, old?, formula?(price-1)} · price_off {sku, tier_id, old} · supplier_set {sku, supplier_id, supplier_sku?, cost?, fixed_cost?, currency_id?, old{}?} · supplier_default/supplier_off {sku, supplier_id} · image_add {sku, storage_path, content_type, byte_size?, width?, height?, file_name?, primary?} · image_off/image_primary {sku, image_id} · image_order {sku, image_ids[]} · ⭐ surcharge_group_set {sku, group_id | null, old}(surcharge-4a · 묶음 2 — old = 지금 그룹 id(없으면 빈 값) · 켜진 그룹만(surcharge_group_unknown · surcharge_group_inactive) · 세트 금지 surcharge_on_set · 줄에는 손대지 않는다 — 새로 들어오는 줄부터). old = 화면이 본 옛 값 — 다르면 changed_elsewhere. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 저장 직전 재검사(판정 176) · 막기 하나면 아무것도 안 바뀐다. 바코드 · 판매가 · 공급처 · 사진 빼기는 끄기(판정 188) · IMS 가 손댄 줄은 source manual(판정 133). code 목록은 20261001143142 · 20261001145316 · 20261001152712 · 20261002012641 · 이 파일(surcharge-4a)의 머리';

-- ═══ ⑥ so_line_add 재발행 — 마지막 정의 20260923232500_so_deal_rpc.sql:129~266 바이트 그대로 + insert 세 칸(도우미 ③) ═══
create or replace function public.so_line_add(
  p_so_id        uuid,
  p_product_id   uuid,
  p_qty          numeric,
  p_unit_price   numeric default null,      -- 주면 덮어쓰기(price_override) · 0 = 무상(free_reason 필수)
  p_discount_pct numeric default null,      -- 주면 손님 기본·딜 대신 이 할인(source manual · unit_price 와 함께 못 준다)
  p_free_reason  text    default null,
  p_comments     text    default null,
  p_force_new    boolean default false      -- ask 의 답 「따로 줄로」
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_so       public.so%rowtype;
  p          public.product%rowtype;
  v_unit_nm  text;
  q          record;
  v_list     numeric;  v_disc numeric;  v_unit numeric;  v_src text;  v_dsrc text;  v_deal uuid;
  v_override boolean := false;
  v_manual   boolean := false;                                  -- 들어오는 줄을 사람이 정했나(단가 또는 할인)
  v_reason   text;  v_comments text;
  v_match    public.so_line%rowtype;
  v_line     public.so_line%rowtype;
  v_others   jsonb;
  v_next     int;
  v_warn     text[] := '{}';
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  if p_qty is null or p_qty <= 0 then
    raise exception 'Quantity must be a positive number — nothing was saved';
  end if;
  select * into p from public.product where id = p_product_id;
  if not found then
    raise exception 'Product not found — nothing was saved';
  end if;
  if not p.is_active then                                       -- ⬜5 — 되묻지 않고 거부
    raise exception 'Product % is inactive — nothing was saved', p.sku;
  end if;
  v_unit_nm := coalesce((select u.name from public.ref_unit u where u.id = p.unit_id), p.uom_name);

  -- 가격 — 창구 + 할인 식 한 곳(수량 포함 · 딜)
  select * into q from public.so_line_quote(v_so, p.id, p_qty);
  v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;

  if p_discount_pct is not null and p_unit_price is not null then
    raise exception 'Give either a unit price or a discount, not both — nothing was saved';
  end if;
  if p_discount_pct is not null then                            -- 수동 할인 — 손님 기본·딜 대신(source manual · 다시 매기기가 건드리지 않는다)
    if p_discount_pct < 0 or p_discount_pct > 100 then
      raise exception 'discount_pct must be between 0 and 100 — nothing was saved';
    end if;
    v_disc := p_discount_pct;
    v_unit := case when v_list is null then null else v_list * (1 - v_disc / 100) end;
    v_dsrc := 'manual';  v_deal := null;  v_manual := true;
  end if;
  if p_unit_price is not null then                              -- 덮어쓰기 — list_price 는 남긴다(받았을 금액 · 판정 2) · discount_pct·출처는 뜻이 없어 null(짝 CHECK)
    if p_unit_price < 0 then
      raise exception 'Unit price cannot be negative — nothing was saved';
    end if;
    v_unit := p_unit_price;  v_override := true;  v_disc := null;  v_dsrc := null;  v_deal := null;  v_manual := true;
  end if;

  -- 무상(판정 2 · ⬜7) — CHECK 가 마지막 문이지만 여기서 사람이 읽는 말로 먼저
  v_reason   := nullif(trim(p_free_reason), '');
  v_comments := nullif(trim(p_comments), '');
  if v_unit is not distinct from 0 and v_reason is null then
    raise exception 'A free line (price 0) needs a reason — sample, promotion, replacement or other — nothing was saved';
  end if;
  if v_reason is not null and v_unit is distinct from 0 then
    raise exception 'A free-goods reason needs a unit price of 0 — nothing was saved';
  end if;
  if v_reason is not null and v_reason not in ('sample', 'promotion', 'replacement', 'other') then
    raise exception 'Free reason % is not one of sample, promotion, replacement, other — nothing was saved', v_reason;
  end if;
  if v_reason = 'other' and v_comments is null then
    raise exception 'Reason other needs a comment — nothing was saved';
  end if;

  -- 같은 SKU(판정 2) — ① 들어오는 줄이 시스템이면 같은 제품의 시스템 줄과 제품만으로 합치고 합친 수량으로 다시 견적
  --                    ② 그 밖은 단가 비교 · 같으면 합침(시스템 줄이면 다시 견적 · 사람이 정한 줄이면 수량만) · 다르면 ask · p_force_new 면 그냥 새 줄
  if not p_force_new then
    if not v_manual then
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = p.id and not l.price_override and l.discount_source is distinct from 'manual'
      order by l.line_no limit 1;
      if found then
        v_line := public.so_line_requote(v_match.id, v_match.qty_ordered + p_qty);
        if v_comments is not null then v_warn := array_append(v_warn, 'comments_not_merged'); end if;
        if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
        if v_line.deal_line_id is not null and public.so_deal_line_ended(v_line.deal_line_id, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
        return jsonb_build_object('action', 'merged', 'requoted', true, 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                                  'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn));
      end if;
    end if;
    select * into v_match from public.so_line l
    where l.so_id = p_so_id and l.product_id = p.id and l.unit_price is not distinct from v_unit
    order by l.line_no limit 1;
    if found then
      if not v_match.price_override and v_match.discount_source is distinct from 'manual' then
        v_line := public.so_line_requote(v_match.id, v_match.qty_ordered + p_qty);     -- 시스템 줄에 합쳐졌다 → 시스템 규칙(수량이 바뀌면 다시 견적)
      else
        update public.so_line set qty_ordered = qty_ordered + p_qty, updated_by = v_staff
        where id = v_match.id returning * into v_line;                                 -- 사람이 정한 줄 → 수량만
      end if;
      if v_comments is not null then v_warn := array_append(v_warn, 'comments_not_merged'); end if;
      if v_line.unit_price is null then v_warn := array_append(v_warn, 'no_price'); end if;
      return jsonb_build_object('action', 'merged', 'requoted', not v_line.price_override and v_line.discount_source is distinct from 'manual', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                                'total', public.so_line_total(v_line), 'warnings', to_jsonb(v_warn));
    end if;
    select jsonb_agg(jsonb_build_object('line_id', l.id, 'line_no', l.line_no, 'qty_ordered', l.qty_ordered,
                                        'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'discount_source', l.discount_source, 'price_override', l.price_override) order by l.line_no)
      into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = p.id;
    if v_others is not null then
      return jsonb_build_object('action', 'ask', 'so_number', v_so.so_number, 'product_id', p.id, 'sku', p.sku,
        'proposed', jsonb_build_object('qty_ordered', p_qty, 'list_price', v_list, 'discount_pct', v_disc, 'discount_source', v_dsrc, 'unit_price', v_unit, 'price_override', v_override),
        'existing', v_others,
        'message', 'Same SKU is already on this order at a different price — change that line (so_line_update) or add as a new line (p_force_new) — nothing was saved');
    end if;
  end if;

  select coalesce(max(line_no), 0) + 1 into v_next from public.so_line where so_id = p_so_id;
  insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                              list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by,
                              surcharge_pct, surcharge_amount, surcharge_label)                                                                                    -- surcharge-4a(묶음 3): 그 상품의 켜진 그룹 값 · 무상이면 비움(판정 228) · 합치기 길은 손대지 않는다(판정 229)
  select p_so_id, v_next, p.id, p.sku, p.name, v_unit_nm, coalesce(p.pack_factor, 1), p_qty,
          v_list, v_disc, v_unit, v_override, v_dsrc, v_deal, v_reason, v_so.tax_rule, v_comments, v_staff,
          d.surcharge_pct, d.surcharge_amount, d.surcharge_label
  from public.so_line_surcharge_defaults(p.id, v_reason is not null) d
  returning * into v_line;
  if v_unit is null then v_warn := array_append(v_warn, 'no_price'); end if;
  if v_deal is not null and public.so_deal_line_ended(v_deal, public.ims_today()) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;

  return jsonb_build_object('action', 'added', 'so_number', v_so.so_number, 'line', to_jsonb(v_line),
                            'total', public.so_line_total(v_line), 'price_source', v_src, 'warnings', to_jsonb(v_warn));
end;
$$;

-- ═══ ⑦ so_lines_paste 재발행 — 마지막 정의 20260923232500_so_deal_rpc.sql:272~464 바이트 그대로 + insert 세 칸(도우미 ③) ═══
create or replace function public.so_lines_paste(
  p_so_id  uuid,
  p_lines  jsonb,                          -- [{sku, qty}]
  p_commit boolean default false
) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_limit    constant int := 500;
  v_staff    uuid;
  v_so       public.so%rowtype;
  v_n        int;
  v_next     int;
  r          record;
  v_sku      text;
  v_qty      numeric;
  v_pid uuid;  v_psku text;  v_pname text;  v_pactive boolean;  v_uom text;  v_unit_id uuid;  v_pack numeric;
  v_verdict  text;
  v_msgs     text[];
  v_dup_of   int;
  v_idx      int;
  i          int;
  -- 제품별로 모은 것(입력 순 · 첫 줄 번호가 대표)
  a_pid uuid[] := '{}';  a_n int[] := '{}';  a_qty numeric[] := '{}';  a_sku text[] := '{}';  a_name text[] := '{}';  a_unit text[] := '{}';  a_pack numeric[] := '{}';
  q          record;
  v_list numeric;  v_disc numeric;  v_unit numeric;  v_src text;  v_dsrc text;  v_deal uuid;
  v_match    public.so_line%rowtype;
  v_others   int;
  v_line_no  int;
  v_inserted boolean;  v_updated boolean;
  v_rows     jsonb := '[]'::jsonb;
  n_ok int := 0;  n_noprice int := 0;  n_merged int := 0;  n_ask int := 0;  n_dup int := 0;  n_nf int := 0;  n_inactive int := 0;  n_bad int := 0;  n_ins int := 0;  n_upd int := 0;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');

  v_n := coalesce(jsonb_array_length(p_lines), 0);
  if v_n > c_limit then
    return jsonb_build_object(
      'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', false,
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'no_price', 0, 'merged', 0, 'ask', 0, 'duplicate', 0, 'not_found', 0, 'inactive', 0, 'bad_qty', 0,
                                    'inserted', 0, 'updated', 0, 'too_many', true, 'limit', c_limit,
                                    'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;

  -- 1) 입력 → 제품 · 같은 제품은 첫 줄에 수량을 모은다
  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null; v_uom := null; v_unit_id := null; v_pack := null;
    v_verdict := null; v_msgs := '{}'; v_dup_of := null; v_idx := null;

    -- SKU 다듬기 — 앞뒤 공백(비분리 공백 포함)만 · po_lines_paste 와 같은 정규식(바이트 그대로)
    v_sku := nullif(regexp_replace(coalesce(r.sku_raw, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
    -- 수량 — 숫자만
    v_qty := case when r.qty_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.qty_raw::numeric else null end;

    if v_sku is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'empty_sku');
    else
      select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor into v_pid, v_psku, v_pname, v_pactive, v_uom, v_unit_id, v_pack
      from public.product p where p.sku = v_sku;                                  -- 유니크 인덱스
      if v_pid is null then
        select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor into v_pid, v_psku, v_pname, v_pactive, v_uom, v_unit_id, v_pack
        from public.product p where upper(p.sku) = upper(v_sku) limit 1;         -- 폴백 · 못 찾은 줄에만
        if v_pid is not null then v_msgs := array_append(v_msgs, 'case_fixed'); end if;
      end if;
    end if;

    if v_verdict is null and v_pid is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'sku_not_in_product');
    end if;
    if v_verdict is null and v_pactive is false then
      v_verdict := 'inactive'; v_msgs := array_append(v_msgs, 'inactive_product — not added');
    end if;
    if v_verdict is null and (v_qty is null or v_qty <= 0) then
      v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, 'qty_must_be_positive_number');
    end if;

    if v_verdict is null then
      select s.i into v_idx from generate_subscripts(a_pid, 1) s(i) where a_pid[s.i] = v_pid limit 1;
      if v_idx is not null then
        v_dup_of := a_n[v_idx];
        a_qty[v_idx] := a_qty[v_idx] + v_qty;
        v_verdict := 'duplicate';
        v_msgs := array_append(v_msgs, format('merged_into_paste_line_%s — quantities added', v_dup_of));
      else
        a_pid := array_append(a_pid, v_pid);  a_n := array_append(a_n, r.n);  a_qty := array_append(a_qty, v_qty);
        a_sku := array_append(a_sku, v_psku);  a_name := array_append(a_name, v_pname);
        a_unit := array_append(a_unit, coalesce((select u.name from public.ref_unit u where u.id = v_unit_id), v_uom));
        a_pack := array_append(a_pack, v_pack);
      end if;
    end if;

    case v_verdict
      when 'not_found' then n_nf := n_nf + 1;
      when 'inactive'  then n_inactive := n_inactive + 1;
      when 'bad_qty'   then n_bad := n_bad + 1;
      when 'duplicate' then n_dup := n_dup + 1;
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw,
      'verdict', v_verdict,                                      -- null = 2) 에서 정해진다
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive,
      'qty', v_qty, 'line_no', null, 'inserted', false, 'updated', false,
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  -- 2) 제품별 — 가격(수량 포함) · 기존 줄과 대조(판정 2) · 넣기(결과는 그 제품의 첫 입력 줄에 적는다)
  for i in 1 .. coalesce(array_length(a_pid, 1), 0) loop
    select * into q from public.so_line_quote(v_so, a_pid[i], a_qty[i]);
    v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_line_no := null; v_inserted := false; v_updated := false; v_msgs := '{}';

    -- ① 같은 제품의 시스템 줄 — 제품만으로 합치고 합친 수량으로 다시 견적
    select * into v_match from public.so_line l
    where l.so_id = p_so_id and l.product_id = a_pid[i] and not l.price_override and l.discount_source is distinct from 'manual'
    order by l.line_no limit 1;
    if found then
      v_verdict := 'merged'; v_line_no := v_match.line_no;
      v_msgs := array_append(v_msgs, format('added_to_line_%s — requoted at %s', v_match.line_no, v_match.qty_ordered + a_qty[i]));
      if p_commit then
        perform public.so_line_requote(v_match.id, v_match.qty_ordered + a_qty[i]);
        v_updated := true; n_upd := n_upd + 1;
      end if;
      n_merged := n_merged + 1;
    else
      -- ② 사람이 정한 줄 — 단가가 같으면 수량만 · 다르면 ask
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = a_pid[i] and l.unit_price is not distinct from v_unit
      order by l.line_no limit 1;
      if found then
        v_verdict := 'merged'; v_line_no := v_match.line_no;
        v_msgs := array_append(v_msgs, format('added_to_line_%s', v_match.line_no));
        if p_commit then
          update public.so_line set qty_ordered = qty_ordered + a_qty[i], updated_by = v_staff where id = v_match.id;
          v_updated := true; n_upd := n_upd + 1;
        end if;
        n_merged := n_merged + 1;
      else
        select count(*) into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = a_pid[i];
        if v_others > 0 then
          v_verdict := 'ask';
          v_msgs := array_append(v_msgs, 'same_sku_at_different_price — use so_line_add to merge into that line or add separately (p_force_new)');
          n_ask := n_ask + 1;
        else
          if v_unit is null then
            v_verdict := 'no_price'; n_noprice := n_noprice + 1;
            v_msgs := array_append(v_msgs, 'no_price_for_this_tier — saved without a price; confirm will refuse until it has one');
          else
            v_verdict := 'ok'; n_ok := n_ok + 1;
          end if;
          if v_deal is not null and public.so_deal_line_ended(v_deal, public.ims_today()) then v_msgs := array_append(v_msgs, 'deal_ended_before_line_added'); end if;
          v_next := v_next + 1; v_line_no := v_next;
          if p_commit then
            insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                        list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by,
                                        surcharge_pct, surcharge_amount, surcharge_label)                                                                          -- surcharge-4a(묶음 3): 붙여 넣기도 같은 도우미(무상 줄은 이 길에 없다)
            select p_so_id, v_line_no, a_pid[i], a_sku[i], a_name[i], a_unit[i], coalesce(a_pack[i], 1), a_qty[i],
                    v_list, v_disc, v_unit, false, v_dsrc, v_deal, null, v_so.tax_rule, null, v_staff,
                    d.surcharge_pct, d.surcharge_amount, d.surcharge_label
            from public.so_line_surcharge_defaults(a_pid[i], false) d;
            v_inserted := true; n_ins := n_ins + 1;
          end if;
        end if;
      end if;
    end if;

    v_rows := coalesce((
      select jsonb_agg(
               case when (e->>'n')::int = a_n[i]
                    then e || jsonb_build_object('verdict', v_verdict, 'qty', a_qty[i], 'list_price', v_list, 'discount_pct', v_disc, 'discount_source', v_dsrc,
                                                 'unit_price', v_unit, 'price_source', v_src, 'line_no', v_line_no,
                                                 'inserted', v_inserted, 'updated', v_updated, 'message', array_to_string(v_msgs, ' · '))
                    else e end
               order by (e->>'n')::int)
      from jsonb_array_elements(v_rows) e), '[]'::jsonb);
  end loop;

  return jsonb_build_object(
    'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', p_commit,
    'summary', jsonb_build_object('total', v_n, 'ok', n_ok, 'no_price', n_noprice, 'merged', n_merged, 'ask', n_ask, 'duplicate', n_dup,
                                  'not_found', n_nf, 'inactive', n_inactive, 'bad_qty', n_bad,
                                  'inserted', n_ins, 'updated', n_upd, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_rows);
end;
$$;

-- ═══ ⑧ 읽기 — 그룹 목록(4b Settings 화면 · PostgREST) ═════════════════════════════════════════════════════════════════════════
create view public.so_surcharge_group_list
  with (security_invoker = true) as
select g.id, g.name, g.surcharge_pct, g.surcharge_amount, g.is_active, g.note, g.created_at, g.updated_at,
       (select s.name from public.ims_staff s where s.id = g.updated_by) as updated_by_name,
       (select count(*) from public.product p where p.surcharge_group_id = g.id)::int                      as product_count,
       (select count(*) from public.product p where p.surcharge_group_id = g.id and p.is_active)::int      as active_product_count,
       (select count(*) from public.so_line l join public.so s on s.id = l.so_id
         where s.status = 'draft' and l.surcharge_label = g.name and l.surcharge_pct is not distinct from g.surcharge_pct and l.surcharge_amount is not distinct from g.surcharge_amount)::int as open_draft_line_count
from public.so_surcharge_group g;
revoke all on public.so_surcharge_group_list from public, anon, authenticated;
grant select on public.so_surcharge_group_list to authenticated;
comment on view public.so_surcharge_group_list is '⭐ 관세 부가 요금 그룹 목록(surcharge-4a · 4b Settings 「Surcharge groups」가 읽는다) — 한 그룹 한 행 · security_invoker · product_count(이 그룹을 가리키는 상품 · 꺼진 상품 포함) · active_product_count · open_draft_line_count(그 이름 · 값을 가진 열린 초안 줄 — 율을 바꾸면 안 바뀌는 수 · 묶음 5 · 창구의 open_draft_lines 알리기와 같은 식) · 쓰기는 so_surcharge_group_save';
