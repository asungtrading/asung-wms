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
-- 20261007125617_dsc_4d_deal_flag_narrow.sql — dsc-4d (2026-10-07 · 회사 PC)
--   판정 346  줄 딜 변경의 열린 오더 표시를 「그 제품이 든 오더」로 좁힌다 — 창구 so_deal_save 안에서 센다(안 ①):
--             표시 = 「트리거가 이 저장에 찍었을 오더」 ∩ 「바꾸기 전에 걸리던 제품(저장 전 켜져 있었을 때만) ∪ 바꾼 뒤 걸리는 제품(저장 뒤 켜져 있을 때만) · so_deal_products · 세트 포함」
--             쓰기 전에 「전」 제품을 담고 · 쓰기 동안 트랜잭션 지역 설정 ims.deal_flag_door = 딜 id 로 트리거 둘(so_deal_changed · so_deal_part_changed)의 넓은 표시를 건너뛰게 하고 · 쓰기 뒤 「뒤」 제품을 더해
--             옛 기간 · 새 기간에 so_deal_flag_open_orders(…, 전 ∪ 뒤) 를 부른다 · 설정은 블록 안에서 비운다(ZZ990 되돌림은 설정도 되돌린다)
--             오더 딜(저장 전 · 뒤 어느 한쪽이라도)은 설정을 켜지 않아 트리거가 지금처럼 넓게 · 창구를 안 타는 쓰기(적재 · 직접 SQL)도 지금처럼 넓게(틀려도 소음 쪽)
--             손님 조건이 하나라도 바뀐 저장은 손님으로 거르지 않는다(판정 313) · 이름 · 메모 · 줄 번호만 바뀐 저장은 트리거처럼 안 찍는다
--   판정 347  deal_off_with_coupons 는 「쿠폰이 먹히던 상태(켜짐 ∧ coupon_required ∧ 오더 딜 — so_coupon_check 가 보는 셋) → 안 먹히는 상태」로 넘어가는 저장에서만 · 기간은 보지 않는다(지시대로)
--   c         line_no_targets 는 화면이 그 줄에 대상을 하나도 안 보냈을 때만 — 보냈는데 막혀서(tag_case_conflict · target_value_invalid · *_unknown · duplicate) 빠진 줄에는 내지 않는다
--   d         min_qty_invalid 문구 둘을 화면 낱말로(At least · None · Full case) — code · key 그대로
--   재발행: so_deal_save = 20261007003838:962~1595 바이트 복사 + 더한 줄(바꾼 줄 넷: line_no_targets 조건 둘 · 347 조건 · min_qty 문구 둘) · so_deal_changed = 20261006201443:255~268 + 한 줄 · so_deal_part_changed = 20261006201443:275~295 + 한 줄
--   무접촉: so_deal_products · so_deal_flag_open_orders · 트리거 정의(WHEN) · 화면 · tag_unused 갈래 · so_deal_list · so_deal_detail
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
--   검증: supabase/tests/dsc-4d-verify.sql

-- ═══ 1) so_deal_changed · so_deal_part_changed 재발행 — 「이 딜은 창구가 찍는다」 설정이면 건너뛴다 · 권한: 트리거 함수는 아무도 못 부른다(authenticated 가 열려 있었다 — 함께 회수) ═══
create or replace function public.so_deal_changed() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if current_setting('ims.deal_flag_door', true) = (case when tg_op = 'DELETE' then old.id else new.id end)::text then return null; end if;   -- dsc-4d 판정 346: 이 딜은 so_deal_save 가 제품까지 보고 직접 찍는다(설정은 창구가 쓰기 동안만 켠다) · 다른 딜 · 창구 밖 쓰기는 지금처럼 넓게
  if tg_op = 'DELETE' then
    if old.is_active then perform public.so_deal_flag_open_orders(old.id, old.date_from, old.date_to, false); end if;    -- 딜이 사라지면 손님 조건도 없다 — 기간만
    return null;
  end if;
  if tg_op = 'UPDATE' and old.is_active then perform public.so_deal_flag_open_orders(old.id, old.date_from, old.date_to, true); end if;   -- 옛 기간(끄거나 기간을 줄였을 때 그 안의 오더)
  if new.is_active then perform public.so_deal_flag_open_orders(new.id, new.date_from, new.date_to, true); end if;                         -- 새 기간
  return null;
end;
$$;
revoke all on function public.so_deal_changed() from public, anon, authenticated;
comment on function public.so_deal_changed() is 'so_deal AFTER INSERT · DELETE · UPDATE(WHEN is_active · date_from · date_to · is_order_level · kind · coupon_required(dsc-4a 판정 333) 가 바뀔 때) — 옛 기간(켜져 있었으면) 과 새 기간(켜져 있으면)의 열린 오더에 다시 매기기 권함(dsc-3a · 판정 313) · 적재 upsert 가 값을 안 바꾸면 WHEN 이 걸러 아무 오더도 안 건드린다 · 이름 · 메모는 표시하지 않는다 · ⭐ dsc-4d 판정 346: 트랜잭션 지역 설정 ims.deal_flag_door 가 이 행의 딜 id 면 건너뛴다(so_deal_save 가 쓰기 동안 켜고 제품까지 보고 직접 찍는다) · 창구 밖 쓰기(적재 · 직접 SQL)는 설정이 없어 지금처럼 넓게';
create or replace function public.so_deal_part_changed() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
declare
  v_ids uuid[];
  d     public.so_deal%rowtype;
  v_cust boolean := tg_table_name <> 'so_deal_customer_rule';                                                      -- 판정 313: 손님 조건 표가 바뀌면 기간만 보고 전부
begin
  if tg_table_name = 'so_deal_target' then
    select array_agg(distinct l.deal_id) into v_ids from public.so_deal_line l
     where l.id in (case when tg_op <> 'INSERT' then old.line_id end, case when tg_op <> 'DELETE' then new.line_id end);
  else
    select array_agg(distinct x) into v_ids from unnest(array[case when tg_op <> 'INSERT' then old.deal_id end, case when tg_op <> 'DELETE' then new.deal_id end]) x where x is not null;
  end if;
  for d in select * from public.so_deal where id = any (coalesce(v_ids, '{}')) and is_active loop
    if current_setting('ims.deal_flag_door', true) = d.id::text then continue; end if;                                 -- dsc-4d 판정 346: 이 딜은 so_deal_save 가 제품까지 보고 직접 찍는다 · 다른 딜 id 면 그대로
    perform public.so_deal_flag_open_orders(d.id, d.date_from, d.date_to, v_cust);
  end loop;
  return null;
end;
$$;
revoke all on function public.so_deal_part_changed() from public, anon, authenticated;
comment on function public.so_deal_part_changed() is 'so_deal_tier · so_deal_line · so_deal_target · so_deal_customer_rule AFTER INSERT · DELETE · UPDATE(WHEN 뜻 있는 칸) — 그 딜(옛 · 새 deal_id · target 은 줄을 거쳐)이 켜져 있으면 열린 오더에 다시 매기기 권함(dsc-3a · 판정 313) · 손님 조건 표의 변경은 손님 조건을 보지 않는다(빠진 손님을 놓치지 않게) · ⭐ dsc-4d 판정 346: 트랜잭션 지역 설정 ims.deal_flag_door 가 그 딜 id 면 그 딜만 건너뛴다(so_deal_save 가 제품까지 보고 직접 찍는다) · 다른 딜 · 창구 밖 쓰기는 지금처럼 넓게';

-- ═══ 2) so_deal_save 재발행 — 마지막 정의 20261007003838:962~1595(DB md5 799b2def · 검증 G0 대조) · 판정 346 · 347 · c · d ═══
create or replace function public.so_deal_save(p_deal jsonb, p_old jsonb default null, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  c_uuid    constant text   := '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$';
  c_num     constant text   := '^-?[0-9]+(\.[0-9]+)?$';
  c_int     constant text   := '^[0-9]+$';
  c_date    constant text   := '^[0-9]{4}-[0-9]{2}-[0-9]{2}$';
  c_head    constant text[] := array['id', 'name', 'is_active', 'date_from', 'date_to', 'is_order_level', 'kind', 'coupon_required', 'note', 'tiers', 'lines', 'rules'];
  c_skip    constant text[] := array['cin7_id', 'source', 'created_at', 'updated_at', 'updated_by', 'coupon_code', 'deal_id', 'line_id'];   -- 화면이 읽은 행을 그대로 돌려보내도 되게 — 읽기 전용 칸은 지나친다
  c_tier    constant text[] := array['id', 'tier_no', 'min_amount', 'pct', 'note'];
  c_line    constant text[] := array['id', 'line_no', 'pct', 'min_qty_mode', 'min_qty', 'note', 'is_active', 'targets'];
  c_target  constant text[] := array['id', 'kind', 'target', 'tag', 'brand_id', 'product_id', 'category_id', 'note'];
  c_rule    constant text[] := array['id', 'kind', 'target', 'customer_id', 'warehouse_id', 'tier_id', 'note'];
  v_staff   uuid;
  v_blocks  jsonb := '[]'::jsonb;
  v_warns   jsonb := '[]'::jsonb;
  v_changes jsonb := '[]'::jsonb;
  v_keys    text[] := '{}';
  v_unacked text[] := '{}';
  v_key     text;
  v_id      uuid;
  v_create  boolean;
  d         public.so_deal%rowtype;
  v_k       text;
  v_txt     text;
  v_e       jsonb;
  v_t       jsonb;
  v_i       int;
  v_j       int;
  v_name    text;  v_active boolean;  v_from date;  v_to date;  v_order boolean;  v_kind text;  v_coupon boolean;  v_note text;
  v_bool    boolean;
  v_head_changed  boolean := false;
  v_child_changed boolean := false;
  v_tiers_given boolean := false;  v_lines_given boolean := false;  v_rules_given boolean := false;
  v_tiers   jsonb := '[]'::jsonb;
  v_lines   jsonb := '[]'::jsonb;
  v_rules   jsonb := '[]'::jsonb;
  v_targets jsonb;
  v_tags    text[] := '{}';
  v_seen    text[] := '{}';
  v_seen_l  text[] := '{}';
  v_amts    numeric[] := '{}';
  v_line_ids uuid[] := '{}';
  v_line_nos int[] := '{}';
  v_nk      text;
  v_val     text;
  v_r       record;
  v_cnt     bigint;
  v_cur_lines int := 0;
  v_cur_tiers int := 0;
  v_off_so  bigint := 0;
  v_off_n   int := 0;
  v_unused  text[] := '{}';
  v_coupons bigint := 0;
  v_f0      bigint;  v_f1 bigint;  v_flagged int := 0;
  v_rolled  boolean := false;
  v_idmap   jsonb := '{}'::jsonb;
  v_lid     uuid;
  v_new_updated timestamptz;
  v_tn int;  v_amt numeric;  v_pct numeric;  v_ln int;  v_mode text;  v_mq numeric;
  v_act     text;
  v_oldv    jsonb;
  v_nsent   int[] := '{}';                                                                                          -- dsc-4d c: 줄마다 화면이 보낸 대상 수(막혀서 빠진 것과 가른다)
  v_flag_head boolean := false;  v_flag_child boolean := false;  v_rules_changed boolean := false;                  -- dsc-4d 판정 346: 트리거 WHEN 과 같은 뜻의 「표시할 변경」 · 손님 조건이 바뀌었나(판정 313)
  v_narrow  boolean;  v_old_on boolean;  v_new_on boolean;  v_cust boolean;  v_pb uuid[];  v_pa uuid[];               -- dsc-4d 판정 346: 양쪽 다 줄 딜인가 · 저장 전 · 뒤 켜짐 · 손님으로 거르나 · 전 · 뒤 제품
begin
  perform public.ims_require_write('master', 'saved');                                                              -- ⭐ 유일한 문 — 첫 줄(판정 140 · 285)
  v_staff := public.so_current_staff();

  -- ① 모양 · 머리 잠금 · 판 대조(판정 331)
  if p_deal is null or jsonb_typeof(p_deal) <> 'object' then
    raise exception 'p_deal must be a JSON object — nothing was saved';
  end if;
  v_txt := nullif(trim(coalesce(p_deal->>'id', '')), '');
  v_create := v_txt is null;
  v_key := 'deal:' || coalesce(v_txt, 'new');
  if not v_create then
    if v_txt !~ c_uuid then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':deal_unknown', 'code', 'deal_unknown', 'message', format('Deal id "%s" is not a valid id — nothing was saved', v_txt));
    else
      v_id := v_txt::uuid;
      select * into d from public.so_deal where id = v_id for update;
      if not found then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':deal_unknown', 'code', 'deal_unknown', 'message', format('Deal %s does not exist — nothing was saved', v_id));
      end if;
    end if;
    if jsonb_array_length(v_blocks) > 0 then
      return jsonb_build_object('committed', false, 'deal_id', null, 'updated_at', null, 'changes', '[]'::jsonb, 'blocks', v_blocks, 'warnings', '[]'::jsonb, 'unacked', '[]'::jsonb, 'open_orders_to_flag', 0);
    end if;
    v_txt := case when jsonb_typeof(p_old) = 'string' then p_old #>> '{}' when jsonb_typeof(p_old) = 'object' then p_old->>'updated_at' else null end;
    if nullif(trim(coalesce(v_txt, '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Deal %s: the version the screen saw (updated_at) is missing — reload and try again — nothing was saved', d.name));
    else
      begin
        if v_txt::timestamptz <> d.updated_at then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed deal %s (now %s) — check again — nothing was saved', d.name, to_json(d.updated_at)::text), 'updated_at', to_jsonb(d.updated_at));
        end if;
      exception when others then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('Deal %s: the version the screen saw ("%s") is not a timestamp — reload and try again — nothing was saved', d.name, v_txt));
      end;
    end if;
  end if;
  for v_k in select jsonb_object_keys(p_deal) loop
    if not (v_k = any(c_head)) and not (v_k = any(c_skip)) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on the deal — nothing was saved', v_k));
    end if;
  end loop;

  -- ② 머리 칸 — 있는 열쇠만 바뀐다(없는 열쇠 = 그대로 · 만들기면 기본값)
  v_name := case when p_deal ? 'name' then nullif(btrim(coalesce(p_deal->>'name', '')), '') else d.name end;
  if v_name is null then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'code', 'name_missing', 'message', 'A deal needs a name — nothing was saved');
  end if;
  foreach v_k in array array['is_active', 'is_order_level', 'coupon_required'] loop
    if p_deal ? v_k then
      v_txt := lower(trim(coalesce(p_deal->>v_k, '')));
      if v_txt not in ('true', 'false') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_k, 'code', 'value_invalid', 'message', format('%s must be true or false (got "%s") — nothing was saved', v_k, coalesce(p_deal->>v_k, '')));
        v_bool := null;
      else
        v_bool := v_txt = 'true';
      end if;
    else
      v_bool := null;
    end if;
    case v_k
      when 'is_active'       then v_active := coalesce(v_bool, d.is_active, true);
      when 'is_order_level'  then v_order  := coalesce(v_bool, d.is_order_level, false);
      when 'coupon_required' then v_coupon := coalesce(v_bool, d.coupon_required, false);
    end case;
  end loop;
  v_kind := case when p_deal ? 'kind' then nullif(trim(coalesce(p_deal->>'kind', '')), '') else coalesce(d.kind, 'pct') end;
  if v_kind is distinct from 'pct' then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':kind_invalid', 'code', 'kind_invalid', 'message', format('Deal kind must be pct (got "%s") — nothing was saved', coalesce(v_kind, '')));
  end if;
  v_note := case when p_deal ? 'note' then nullif(trim(coalesce(p_deal->>'note', '')), '') else d.note end;
  v_from := d.date_from;  v_to := d.date_to;
  foreach v_k in array array['date_from', 'date_to'] loop
    if p_deal ? v_k then
      v_txt := nullif(trim(coalesce(p_deal->>v_k, '')), '');
      if v_txt is not null and v_txt !~ c_date then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':dates_invalid:' || v_k, 'code', 'dates_invalid', 'message', format('%s must be a date YYYY-MM-DD (got "%s") — nothing was saved', v_k, v_txt));
      else
        begin
          if v_k = 'date_from' then v_from := v_txt::date; else v_to := v_txt::date; end if;
        exception when others then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':dates_invalid:' || v_k, 'code', 'dates_invalid', 'message', format('%s is not a real date (got "%s") — nothing was saved', v_k, v_txt));
        end;
      end if;
    end if;
  end loop;
  if v_from is not null and v_to is not null and v_from > v_to then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':dates_invalid', 'code', 'dates_invalid', 'message', format('date_from %s is after date_to %s — nothing was saved', v_from, v_to));
  end if;
  if v_create then
    v_changes := v_changes || jsonb_build_object('part', 'head', 'action', 'added', 'name', v_name, 'is_active', v_active, 'is_order_level', v_order, 'coupon_required', v_coupon, 'date_from', v_from, 'date_to', v_to);
    v_head_changed := true;
    v_flag_head := true;                                                                                            -- dsc-4d 판정 346: 만들기 = 켜기(so_deal_changed 가 찍었을 자리)
  else
    for v_r in
      select * from (values ('name', to_jsonb(d.name), to_jsonb(v_name)), ('is_active', to_jsonb(d.is_active), to_jsonb(v_active)), ('date_from', to_jsonb(d.date_from), to_jsonb(v_from)), ('date_to', to_jsonb(d.date_to), to_jsonb(v_to)),
                           ('is_order_level', to_jsonb(d.is_order_level), to_jsonb(v_order)), ('kind', to_jsonb(d.kind), to_jsonb(v_kind)), ('coupon_required', to_jsonb(d.coupon_required), to_jsonb(v_coupon)), ('note', to_jsonb(d.note), to_jsonb(v_note))) as f(field, oldv, newv)
    loop
      if v_r.oldv is distinct from v_r.newv then
        v_changes := v_changes || jsonb_build_object('part', 'head', 'action', 'changed', 'field', v_r.field, 'old', v_r.oldv, 'new', v_r.newv);
        v_head_changed := true;
        if v_r.field in ('is_active', 'date_from', 'date_to', 'is_order_level', 'kind', 'coupon_required') then v_flag_head := true; end if;   -- dsc-4d 판정 346: so_deal_changed_u 의 WHEN 과 같은 칸
      end if;
    end loop;
    if not v_head_changed then v_changes := v_changes || jsonb_build_object('part', 'head', 'action', 'unchanged'); end if;
    select count(*) into v_cur_lines from public.so_deal_line l where l.deal_id = v_id and l.is_active;
    select count(*) into v_cur_tiers from public.so_deal_tier t where t.deal_id = v_id;
  end if;

  -- ③ 단계(짝 = tier_no · 판정 340)
  if p_deal ? 'tiers' then
    if jsonb_typeof(p_deal->'tiers') <> 'array' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tiers_invalid', 'code', 'tiers_invalid', 'message', 'tiers must be a list of {tier_no, min_amount, pct} — nothing was saved');
    else
      v_tiers_given := true;
      v_i := 0;
      for v_e in select x from jsonb_array_elements(p_deal->'tiers') x loop
        v_i := v_i + 1;
        if jsonb_typeof(v_e) <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tiers_invalid:' || v_i, 'code', 'tiers_invalid', 'message', format('Tier %s is not {tier_no, min_amount, pct} — nothing was saved', v_i));
          continue;
        end if;
        for v_k in select jsonb_object_keys(v_e) loop
          if not (v_k = any(c_tier)) and not (v_k = any(c_skip)) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:tier.' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on tier %s — nothing was saved', v_k, v_i));
          end if;
        end loop;
        v_txt := trim(coalesce(v_e->>'tier_no', ''));
        if v_txt !~ c_int or v_txt::int < 1 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_no_invalid:' || v_i, 'code', 'tier_no_invalid', 'message', format('Tier %s: tier_no must be a whole number from 1 (got "%s") — nothing was saved', v_i, v_txt));
          continue;
        end if;
        v_tn := v_txt::int;
        v_txt := coalesce(nullif(trim(coalesce(v_e->>'min_amount', '')), ''), '0');
        if v_txt !~ c_num or v_txt::numeric < 0 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_amount_invalid:' || v_tn, 'code', 'min_amount_invalid', 'message', format('Tier %s: min_amount must be 0 or more (got "%s") — nothing was saved', v_tn, v_txt));
          continue;
        end if;
        v_amt := v_txt::numeric;
        v_txt := trim(coalesce(v_e->>'pct', ''));
        if v_txt !~ c_num or not (v_txt::numeric > 0 and v_txt::numeric < 100) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':pct_invalid:tier.' || v_tn, 'code', 'pct_invalid', 'message', format('Tier %s: pct must be above 0 and below 100 (got "%s") — nothing was saved', v_tn, v_txt));
          continue;
        end if;
        v_pct := v_txt::numeric;
        if ('T|' || v_tn) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_no_duplicate:' || v_tn, 'code', 'tier_no_duplicate', 'message', format('Tier number %s appears twice — nothing was saved', v_tn));
          continue;
        end if;
        if v_amt = any(v_amts) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_amount_duplicate:' || v_tn, 'code', 'tier_amount_duplicate', 'message', format('Two tiers start at the same amount %s — nothing was saved', v_amt));
          continue;
        end if;
        v_seen := v_seen || ('T|' || v_tn);  v_amts := v_amts || v_amt;
        v_tiers := v_tiers || jsonb_build_object('tier_no', v_tn, 'min_amount', v_amt, 'pct', v_pct, 'note', nullif(trim(coalesce(v_e->>'note', '')), ''));
      end loop;
    end if;
  end if;

  -- ④ 줄(짝 = id · 판정 340 · 없는 id = 새 줄 · is_active false 로 보낸 줄은 덩이에 없는 것과 같다) + 대상(짝 = 내용 전체)
  if p_deal ? 'lines' then
    if jsonb_typeof(p_deal->'lines') <> 'array' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid', 'code', 'lines_invalid', 'message', 'lines must be a list of {id, line_no, pct, min_qty_mode, min_qty, targets[]} — nothing was saved');
    else
      v_lines_given := true;
      v_i := 0;
      for v_e in select x from jsonb_array_elements(p_deal->'lines') x loop
        v_i := v_i + 1;
        if jsonb_typeof(v_e) <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_invalid:' || v_i, 'code', 'lines_invalid', 'message', format('Line %s is not {line_no, pct, …} — nothing was saved', v_i));
          continue;
        end if;
        if lower(trim(coalesce(v_e->>'is_active', 'true'))) = 'false' then continue; end if;                            -- 꺼진 채 돌아온 줄 = 덩이에 없는 줄(그대로 꺼져 있거나 꺼진다)
        for v_k in select jsonb_object_keys(v_e) loop
          if not (v_k = any(c_line)) and not (v_k = any(c_skip)) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:line.' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on line %s — nothing was saved', v_k, v_i));
          end if;
        end loop;
        v_lid := null;
        v_txt := nullif(trim(coalesce(v_e->>'id', '')), '');
        if v_txt is not null then
          if v_txt !~ c_uuid or v_create or not exists (select 1 from public.so_deal_line l where l.id = v_txt::uuid and l.deal_id = v_id) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_unknown:' || v_i, 'code', 'line_unknown', 'message', format('Line %s: id "%s" is not a line of this deal — nothing was saved', v_i, v_txt));
            continue;
          end if;
          v_lid := v_txt::uuid;
          if v_lid = any(v_line_ids) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_duplicate_in_call:' || v_i, 'code', 'line_duplicate_in_call', 'message', format('Line id %s appears twice — nothing was saved', v_lid));
            continue;
          end if;
        end if;
        v_txt := trim(coalesce(v_e->>'line_no', ''));
        if v_txt !~ c_int or v_txt::int < 1 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_no_invalid:' || v_i, 'code', 'line_no_invalid', 'message', format('Line %s: line_no must be a whole number from 1 (got "%s") — nothing was saved', v_i, v_txt));
          continue;
        end if;
        v_ln := v_txt::int;
        v_txt := trim(coalesce(v_e->>'pct', ''));
        if v_txt !~ c_num or not (v_txt::numeric > 0 and v_txt::numeric < 100) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':pct_invalid:line.' || v_ln, 'code', 'pct_invalid', 'message', format('Line %s: pct must be above 0 and below 100 (got "%s") — nothing was saved', v_ln, v_txt));
          continue;
        end if;
        v_pct := v_txt::numeric;
        v_mode := coalesce(nullif(trim(coalesce(v_e->>'min_qty_mode', '')), ''), 'none');
        if v_mode not in ('none', 'qty', 'case') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_qty_mode_invalid:' || v_ln, 'code', 'min_qty_mode_invalid', 'message', format('Line %s: min_qty_mode must be none, qty or case (got "%s") — nothing was saved', v_ln, v_mode));
          continue;
        end if;
        v_txt := nullif(trim(coalesce(v_e->>'min_qty', '')), '');
        if v_mode = 'qty' then
          if v_txt is null or v_txt !~ c_num or v_txt::numeric <= 0 then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_qty_invalid:' || v_ln, 'code', 'min_qty_invalid', 'message', case when v_txt is null then format('Line %s: "At least" needs a quantity above 0 — nothing was saved', v_ln) else format('Line %s: "At least" needs a quantity above 0 (got "%s") — nothing was saved', v_ln, v_txt) end);   -- dsc-4d d: 화면 낱말(At least)
            continue;
          end if;
          v_mq := v_txt::numeric;
        else
          if v_txt is not null then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_qty_invalid:' || v_ln, 'code', 'min_qty_invalid', 'message', format('Line %s: a quantity is only used with "At least" (this line is "%s") — nothing was saved', v_ln, case v_mode when 'none' then 'None' else 'Full case' end));   -- dsc-4d d: 화면 낱말(None · Full case)
            continue;
          end if;
          v_mq := null;
        end if;
        if v_ln = any(v_line_nos) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_no_duplicate:' || v_ln, 'code', 'line_no_duplicate', 'message', format('Line number %s appears twice — nothing was saved', v_ln));
          continue;
        end if;
        v_line_nos := v_line_nos || v_ln;
        if v_lid is not null then v_line_ids := v_line_ids || v_lid; end if;
        -- 대상 — targets 열쇠가 없으면(기존 줄) 그대로 · 있으면 내용 전체가 최종 모양 · 새 줄은 빈 목록
        v_targets := null;
        if v_e ? 'targets' then
          if jsonb_typeof(v_e->'targets') <> 'array' then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':targets_invalid:' || v_ln, 'code', 'targets_invalid', 'message', format('Line %s: targets must be a list — nothing was saved', v_ln));
            continue;
          end if;
          v_targets := '[]'::jsonb;  v_seen_l := '{}';  v_j := 0;
          v_nsent[v_i] := jsonb_array_length(v_e->'targets');                                                        -- dsc-4d c: 화면이 보낸 수(막힌 대상도 센다)
          for v_t in select x from jsonb_array_elements(v_e->'targets') x loop
            v_j := v_j + 1;
            if jsonb_typeof(v_t) <> 'object' then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_value_invalid:' || v_ln || '.' || v_j, 'code', 'target_value_invalid', 'message', format('Line %s target %s is not {kind, target, value} — nothing was saved', v_ln, v_j));
              continue;
            end if;
            for v_k in select jsonb_object_keys(v_t) loop
              if not (v_k = any(c_target)) and not (v_k = any(c_skip)) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:target.' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on line %s target %s — nothing was saved', v_k, v_ln, v_j));
              end if;
            end loop;
            v_val := null;
            if coalesce(v_t->>'kind', '') not in ('include', 'exclude') or coalesce(v_t->>'target', '') not in ('tag', 'brand', 'product', 'category') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_value_invalid:' || v_ln || '.' || v_j, 'code', 'target_value_invalid', 'message', format('Line %s target %s: kind must be include|exclude and target tag|brand|product|category (got "%s" · "%s") — nothing was saved', v_ln, v_j, coalesce(v_t->>'kind', ''), coalesce(v_t->>'target', '')));
              continue;
            end if;
            -- 값 칸은 target 에 맞는 하나만(나머지는 비어 있어야) — so_deal_target_value_ck 를 어휘로
            if (nullif(trim(coalesce(v_t->>'tag', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'brand_id', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'product_id', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'category_id', '')), '') is not null)::int <> 1
               or nullif(trim(coalesce(v_t->>(case v_t->>'target' when 'tag' then 'tag' else (v_t->>'target') || '_id' end), '')), '') is null then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_value_invalid:' || v_ln || '.' || v_j, 'code', 'target_value_invalid', 'message', format('Line %s target %s: a %s target needs exactly its %s value — nothing was saved', v_ln, v_j, v_t->>'target', case v_t->>'target' when 'tag' then 'tag' else (v_t->>'target') || '_id' end));
              continue;
            end if;
            if v_t->>'target' = 'tag' then
              v_val := btrim(v_t->>'tag');
              if exists (select 1 from public.product_tag pt where lower(pt.tag) = lower(v_val) and pt.tag <> v_val) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_case_conflict:' || v_ln || '.' || v_j, 'code', 'tag_case_conflict', 'message', format('Line %s: tag "%s" differs only by case from a product tag "%s" — use the existing spelling — nothing was saved', v_ln, v_val, (select min(pt.tag) from public.product_tag pt where lower(pt.tag) = lower(v_val) and pt.tag <> v_val)));
                continue;
              end if;
              if exists (select 1 from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id where l.deal_id is distinct from v_id and lower(x.tag) = lower(v_val) and x.tag <> v_val) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_case_conflict:' || v_ln || '.' || v_j, 'code', 'tag_case_conflict', 'message', format('Line %s: tag "%s" differs only by case from a tag another deal uses ("%s") — use the same spelling — nothing was saved', v_ln, v_val, (select min(x.tag) from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id where l.deal_id is distinct from v_id and lower(x.tag) = lower(v_val) and x.tag <> v_val)));
                continue;
              end if;
              if exists (select 1 from unnest(v_tags) g where lower(g) = lower(v_val) and g <> v_val) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_case_conflict:' || v_ln || '.' || v_j, 'code', 'tag_case_conflict', 'message', format('Line %s: tag "%s" differs only by case from another tag in this deal — use one spelling — nothing was saved', v_ln, v_val));
                continue;
              end if;
              v_tags := v_tags || v_val;
              if not exists (select 1 from public.product_tag pt where pt.tag = v_val) and not (v_val = any(v_unused)) then v_unused := v_unused || v_val; end if;
            else
              v_val := trim(v_t->>((v_t->>'target') || '_id'));
              if v_val !~ c_uuid
                 or (v_t->>'target' = 'brand'    and not exists (select 1 from public.ref_brand b    where b.id = v_val::uuid))
                 or (v_t->>'target' = 'product'  and not exists (select 1 from public.product p     where p.id = v_val::uuid))
                 or (v_t->>'target' = 'category' and not exists (select 1 from public.ref_category c where c.id = v_val::uuid)) then
                v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || (v_t->>'target') || '_unknown:' || v_ln || '.' || v_j, 'code', (v_t->>'target') || '_unknown', 'message', format('Line %s target %s: %s "%s" does not exist — nothing was saved', v_ln, v_j, v_t->>'target', v_val));
                continue;
              end if;
            end if;
            v_nk := (v_t->>'kind') || '|' || (v_t->>'target') || '|' || v_val;
            if v_nk = any(v_seen_l) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':target_duplicate_in_call:' || v_ln || '.' || v_j, 'code', 'target_duplicate_in_call', 'message', format('Line %s: target %s %s "%s" appears twice — nothing was saved', v_ln, v_t->>'kind', v_t->>'target', v_val));
              continue;
            end if;
            v_seen_l := v_seen_l || v_nk;
            v_targets := v_targets || jsonb_build_object('kind', v_t->>'kind', 'target', v_t->>'target', 'value', v_val, 'nk', v_nk, 'note', nullif(trim(coalesce(v_t->>'note', '')), ''));
          end loop;
        elsif v_lid is null then
          v_targets := '[]'::jsonb;
          v_nsent[v_i] := 0;                                                                                          -- dsc-4d c: 새 줄에 targets 열쇠가 없다 = 하나도 안 보냈다
        end if;
        v_lines := v_lines || jsonb_build_object('idx', v_i, 'id', v_lid, 'line_no', v_ln, 'pct', v_pct, 'min_qty_mode', v_mode, 'min_qty', v_mq, 'note', nullif(trim(coalesce(v_e->>'note', '')), ''), 'targets', v_targets);
      end loop;
    end if;
  end if;

  -- ⑤ 손님 조건(짝 = 내용 전체 · 판정 340)
  if p_deal ? 'rules' then
    if jsonb_typeof(p_deal->'rules') <> 'array' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rules_invalid', 'code', 'rules_invalid', 'message', 'rules must be a list of {kind, target, value} — nothing was saved');
    else
      v_rules_given := true;  v_seen_l := '{}';  v_i := 0;
      for v_t in select x from jsonb_array_elements(p_deal->'rules') x loop
        v_i := v_i + 1;
        if jsonb_typeof(v_t) <> 'object' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rule_value_invalid:' || v_i, 'code', 'rule_value_invalid', 'message', format('Customer rule %s is not {kind, target, value} — nothing was saved', v_i));
          continue;
        end if;
        for v_k in select jsonb_object_keys(v_t) loop
          if not (v_k = any(c_rule)) and not (v_k = any(c_skip)) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:rule.' || v_k, 'code', 'field_unknown', 'message', format('Unknown field "%s" on customer rule %s — nothing was saved', v_k, v_i));
          end if;
        end loop;
        if coalesce(v_t->>'kind', '') not in ('include', 'exclude') or coalesce(v_t->>'target', '') not in ('customer', 'branch', 'tier') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rule_value_invalid:' || v_i, 'code', 'rule_value_invalid', 'message', format('Customer rule %s: kind must be include|exclude and target customer|branch|tier (got "%s" · "%s") — nothing was saved', v_i, coalesce(v_t->>'kind', ''), coalesce(v_t->>'target', '')));
          continue;
        end if;
        v_k := case v_t->>'target' when 'customer' then 'customer_id' when 'branch' then 'warehouse_id' else 'tier_id' end;
        if (nullif(trim(coalesce(v_t->>'customer_id', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'warehouse_id', '')), '') is not null)::int + (nullif(trim(coalesce(v_t->>'tier_id', '')), '') is not null)::int <> 1
           or nullif(trim(coalesce(v_t->>v_k, '')), '') is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rule_value_invalid:' || v_i, 'code', 'rule_value_invalid', 'message', format('Customer rule %s: a %s rule needs exactly its %s value — nothing was saved', v_i, v_t->>'target', v_k));
          continue;
        end if;
        v_val := trim(v_t->>v_k);
        if v_val !~ c_uuid
           or (v_k = 'customer_id'  and not exists (select 1 from public.customer c       where c.id = v_val::uuid))
           or (v_k = 'warehouse_id' and not exists (select 1 from public.ref_warehouse w  where w.id = v_val::uuid))
           or (v_k = 'tier_id'      and not exists (select 1 from public.ref_price_tier t where t.id = v_val::uuid)) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || replace(v_k, '_id', '') || '_unknown:' || v_i, 'code', replace(v_k, '_id', '') || '_unknown', 'message', format('Customer rule %s: %s "%s" does not exist — nothing was saved', v_i, replace(v_k, '_id', ''), v_val));
          continue;
        end if;
        v_nk := (v_t->>'kind') || '|' || (v_t->>'target') || '|' || v_val;
        if v_nk = any(v_seen_l) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rule_duplicate_in_call:' || v_i, 'code', 'rule_duplicate_in_call', 'message', format('Customer rule %s %s "%s" appears twice — nothing was saved', v_t->>'kind', v_t->>'target', v_val));
          continue;
        end if;
        v_seen_l := v_seen_l || v_nk;
        v_rules := v_rules || jsonb_build_object('kind', v_t->>'kind', 'target', v_t->>'target', 'value', v_val, 'nk', v_nk, 'note', nullif(trim(coalesce(v_t->>'note', '')), ''));
      end loop;
    end if;
  end if;

  -- ⑥ 최종 모양의 문지기(트리거 셋을 어휘로 · 판정 309 · 330)
  if v_order then
    if v_lines_given and jsonb_array_length(v_lines) > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_on_order_deal', 'code', 'line_on_order_deal', 'message', 'An order-level deal has no lines (its amount tiers are the discount) — remove the lines or turn off order-level — nothing was saved');
    elsif not v_lines_given and v_cur_lines > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':lines_block_order_level_on', 'code', 'lines_block_order_level_on', 'message', format('Deal %s has %s active line(s) — turn them off before making it an order-level deal — nothing was saved', v_name, v_cur_lines));
    end if;
  else
    if v_tiers_given and jsonb_array_length(v_tiers) > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_on_line_deal', 'code', 'tier_on_line_deal', 'message', 'Amount tiers belong to an order-level deal — remove the tiers or turn on order-level — nothing was saved');
    elsif not v_tiers_given and v_cur_tiers > 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tiers_block_order_level_off', 'code', 'tiers_block_order_level_off', 'message', format('Deal %s has %s amount tier(s) — remove them before turning off order-level — nothing was saved', v_name, v_cur_tiers));
    end if;
  end if;
  if v_lines_given and not v_create then                                                                             -- 꺼진 줄(이 저장이 끄는 줄 포함)도 번호를 쥔다 — 최종 모양에서 겹치면 막는다
    for v_r in select l.line_no from public.so_deal_line l where l.deal_id = v_id and not (l.id = any(v_line_ids)) and l.line_no = any(v_line_nos) loop
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':line_no_duplicate:' || v_r.line_no, 'code', 'line_no_duplicate', 'message', format('Line number %s is held by a turned-off line — give the new line another number — nothing was saved', v_r.line_no));
    end loop;
  end if;

  -- ⑦ 변경 목록(미리 보기 · 쓰기 같다) · 알리기
  if v_tiers_given then
    for v_r in
      select coalesce(n.tier_no, c.tier_no) as tier_no, n.min_amount as new_amt, n.pct as new_pct, n.note as new_note, c.min_amount as old_amt, c.pct as old_pct, c.note as old_note, n.tier_no is not null as in_new, c.id is not null as in_cur
        from (select (x->>'tier_no')::int as tier_no, (x->>'min_amount')::numeric as min_amount, (x->>'pct')::numeric as pct, x->>'note' as note from jsonb_array_elements(v_tiers) x) n
        full join (select t.* from public.so_deal_tier t where t.deal_id = v_id) c on c.tier_no = n.tier_no
       order by 1
    loop
      v_act := case when not v_r.in_cur then 'added' when not v_r.in_new then 'removed' when v_r.new_amt <> v_r.old_amt or v_r.new_pct <> v_r.old_pct or v_r.new_note is distinct from v_r.old_note then 'changed' else 'unchanged' end;
      v_changes := v_changes || jsonb_build_object('part', 'tier', 'action', v_act, 'tier_no', v_r.tier_no, 'old', case when v_r.in_cur then jsonb_build_object('min_amount', v_r.old_amt, 'pct', v_r.old_pct) end, 'new', case when v_r.in_new then jsonb_build_object('min_amount', v_r.new_amt, 'pct', v_r.new_pct) end);
      if v_act <> 'unchanged' then v_child_changed := true; end if;
    end loop;
  end if;
  if v_lines_given then
    for v_e in select x from jsonb_array_elements(v_lines) x order by (x->>'line_no')::int loop
      v_lid := (v_e->>'id')::uuid;
      if v_lid is null then
        v_changes := v_changes || jsonb_build_object('part', 'line', 'action', 'added', 'line_id', null, 'line_no', (v_e->>'line_no')::int, 'new', v_e - 'targets' - 'idx');
        v_child_changed := true;
        v_flag_child := true;                                                                                       -- dsc-4d 판정 346: 줄 insert = so_deal_line_changed_id
        for v_t in select x from jsonb_array_elements(v_e->'targets') x loop
          v_changes := v_changes || jsonb_build_object('part', 'target', 'action', 'added', 'line_id', null, 'line_no', (v_e->>'line_no')::int, 'kind', v_t->>'kind', 'target', v_t->>'target', 'value', v_t->>'value');
        end loop;
        if v_nsent[(v_e->>'idx')::int] = 0 then                                                                     -- dsc-4d c: 화면이 하나도 안 보냈을 때만(막혀서 빠진 줄은 아니다)
          v_warns := v_warns || jsonb_build_object('key', v_key || ':line_no_targets:' || (v_e->>'line_no'), 'code', 'line_no_targets', 'message', format('Line %s has no targets — it will match no product until a target is added', v_e->>'line_no'));
          v_keys := array_append(v_keys, v_key || ':line_no_targets:' || (v_e->>'line_no'));
        end if;
      else
        select * into v_r from public.so_deal_line l where l.id = v_lid;
        v_act := case when not v_r.is_active then 'turned_on'
                      when v_r.line_no <> (v_e->>'line_no')::int or v_r.pct <> (v_e->>'pct')::numeric or v_r.min_qty_mode <> (v_e->>'min_qty_mode') or v_r.min_qty is distinct from (v_e->>'min_qty')::numeric or v_r.note is distinct from (v_e->>'note') then 'changed'
                      else 'unchanged' end;
        v_changes := v_changes || jsonb_build_object('part', 'line', 'action', v_act, 'line_id', v_lid, 'line_no', (v_e->>'line_no')::int,
                                                     'old', jsonb_build_object('line_no', v_r.line_no, 'pct', v_r.pct, 'min_qty_mode', v_r.min_qty_mode, 'min_qty', v_r.min_qty, 'note', v_r.note, 'is_active', v_r.is_active), 'new', v_e - 'targets' - 'idx');
        if v_act <> 'unchanged' then v_child_changed := true; end if;
        if v_act = 'turned_on' or (v_act = 'changed' and (v_r.pct <> (v_e->>'pct')::numeric or v_r.min_qty_mode <> (v_e->>'min_qty_mode') or v_r.min_qty is distinct from (v_e->>'min_qty')::numeric)) then v_flag_child := true; end if;   -- dsc-4d 판정 346: so_deal_line_changed_u 의 WHEN 칸(line_no · note 는 아니다)
        if v_e ? 'targets' and jsonb_typeof(v_e->'targets') = 'array' then
          for v_r in
            select coalesce(n.nk, c.nk) as nk, coalesce(n.kind, c.kind) as kind, coalesce(n.target, c.target) as target, coalesce(n.value, c.value) as value, n.nk is not null as in_new, c.nk is not null as in_cur
              from (select x->>'nk' as nk, x->>'kind' as kind, x->>'target' as target, x->>'value' as value from jsonb_array_elements(v_e->'targets') x) n
              full join (select x.kind || '|' || x.target || '|' || coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text) as nk, x.kind, x.target, coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text) as value
                           from public.so_deal_target x where x.line_id = v_lid) c on c.nk = n.nk
             order by 1
          loop
            v_act := case when not v_r.in_cur then 'added' when not v_r.in_new then 'removed' else 'unchanged' end;
            v_changes := v_changes || jsonb_build_object('part', 'target', 'action', v_act, 'line_id', v_lid, 'line_no', (v_e->>'line_no')::int, 'kind', v_r.kind, 'target', v_r.target, 'value', v_r.value);
            if v_act <> 'unchanged' then v_child_changed := true; end if;
            if v_act <> 'unchanged' then v_flag_child := true; end if;                                              -- dsc-4d 판정 346: 대상 insert · delete
          end loop;
          if v_nsent[(v_e->>'idx')::int] = 0 then                                                                   -- dsc-4d c: 같다
            v_warns := v_warns || jsonb_build_object('key', v_key || ':line_no_targets:' || (v_e->>'line_no'), 'code', 'line_no_targets', 'message', format('Line %s has no targets — it will match no product until a target is added', v_e->>'line_no'));
            v_keys := array_append(v_keys, v_key || ':line_no_targets:' || (v_e->>'line_no'));
          end if;
        end if;
      end if;
    end loop;
    if not v_create then
      for v_r in select l.id, l.line_no, (select count(*) from public.so_line s where s.deal_line_id = l.id) as so_lines from public.so_deal_line l where l.deal_id = v_id and l.is_active and not (l.id = any(v_line_ids)) order by l.line_no loop
        v_changes := v_changes || jsonb_build_object('part', 'line', 'action', 'turned_off', 'line_id', v_r.id, 'line_no', v_r.line_no, 'so_lines', v_r.so_lines);
        v_child_changed := true;  v_off_n := v_off_n + 1;  v_off_so := v_off_so + v_r.so_lines;
        v_flag_child := true;                                                                                       -- dsc-4d 판정 346: 줄 끄기 = is_active 변경
      end loop;
      if v_off_so > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':line_off_with_order_lines', 'code', 'line_off_with_order_lines', 'n', v_off_so, 'message', format('%s order line(s) got their discount from the %s line(s) being turned off — they keep what they have; the lines stay on record', v_off_so, v_off_n));
        v_keys := array_append(v_keys, v_key || ':line_off_with_order_lines');
      end if;
    end if;
  end if;
  if v_rules_given then
    for v_r in
      select coalesce(n.nk, c.nk) as nk, coalesce(n.kind, c.kind) as kind, coalesce(n.target, c.target) as target, coalesce(n.value, c.value) as value, n.nk is not null as in_new, c.nk is not null as in_cur
        from (select x->>'nk' as nk, x->>'kind' as kind, x->>'target' as target, x->>'value' as value from jsonb_array_elements(v_rules) x) n
        full join (select x.kind || '|' || x.target || '|' || coalesce(x.customer_id::text, x.warehouse_id::text, x.tier_id::text) as nk, x.kind, x.target, coalesce(x.customer_id::text, x.warehouse_id::text, x.tier_id::text) as value
                     from public.so_deal_customer_rule x where x.deal_id = v_id) c on c.nk = n.nk
       order by 1
    loop
      v_act := case when not v_r.in_cur then 'added' when not v_r.in_new then 'removed' else 'unchanged' end;
      v_changes := v_changes || jsonb_build_object('part', 'rule', 'action', v_act, 'kind', v_r.kind, 'target', v_r.target, 'value', v_r.value);
      if v_act <> 'unchanged' then v_child_changed := true; end if;
      if v_act <> 'unchanged' then v_flag_child := true;  v_rules_changed := not v_create; end if;                 -- dsc-4d 판정 346 · 313: 손님 조건이 바뀐 저장은 손님으로 거르지 않는다(만들기는 켜기 전에 들어가므로 트리거와 같이 거른다)
    end loop;
  end if;
  if not v_create and v_rules_given then                                                                           -- dsc-4b 판정 343: 걸기 조건이 1 이상이다가 0 이 되면 「모든 손님」 — 묻는다(만들기는 해당 없음)
    select count(*) into v_cnt from public.so_deal_customer_rule x where x.deal_id = v_id and x.kind = 'include';
    if v_cnt > 0 and not exists (select 1 from jsonb_array_elements(v_rules) y where y->>'kind' = 'include') then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':rules_open_to_all', 'code', 'rules_open_to_all', 'n_before', v_cnt, 'message', format('This save removes all %s include rule(s) — deal %s will apply to every customer', v_cnt, v_name));
      v_keys := array_append(v_keys, v_key || ':rules_open_to_all');
    end if;
  end if;
  if cardinality(v_unused) > 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':tag_unused', 'code', 'tag_unused', 'tags', to_jsonb(v_unused), 'message', format('No product carries the tag(s) %s yet — the deal saves, but matches nothing on them until products get the tag', array_to_string(v_unused, ', ')));
    v_keys := array_append(v_keys, v_key || ':tag_unused');
  end if;
  if not v_create and (d.is_active and d.coupon_required and d.is_order_level) and not (v_active and v_coupon and v_order) then   -- 판정 334 · dsc-4d 판정 347: 쿠폰이 먹히던 상태(켜짐 ∧ coupon_required ∧ 오더 딜 = so_coupon_check 의 조건) → 안 먹히는 상태로 넘어가는 저장에서만
    select count(*) into v_coupons from public.so_coupon c where c.deal_id = v_id and c.used_so_id is null and c.voided_at is null;
    if v_coupons > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':deal_off_with_coupons', 'code', 'deal_off_with_coupons', 'n', v_coupons, 'message', format('%s unused coupon(s) are issued on deal %s — they stop working while the deal is off or not a coupon deal; they are not voided', v_coupons, d.name));
      v_keys := array_append(v_keys, v_key || ':deal_off_with_coupons');
    end if;
  end if;
  if jsonb_array_length(v_blocks) = 0 and not v_head_changed and not v_child_changed then
    v_blocks := v_blocks || jsonb_build_object('key', v_key || ':no_change', 'code', 'no_change', 'message', format('Deal %s already looks exactly like this — nothing to change — nothing was saved', v_name));
  end if;
  if jsonb_array_length(v_blocks) > 0 then
    return jsonb_build_object('committed', false, 'deal_id', v_id, 'updated_at', to_jsonb(d.updated_at), 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'open_orders_to_flag', 0);
  end if;

  -- ⑧ 쓰기 — 서브트랜잭션: 미리 보기(p_commit false)와 ack 안 된 저장은 쓰고 센 뒤 되돌린다(⬜1 나 · 표시 수는 트리거가 실제로 센 값)
  --    순서(판정 340 · 문지기): 자식 지우기 · 줄 끄기 → 머리 → 단계 · 줄 고치기 · 넣기 → 대상 · 손님 조건 넣기 → 제약 즉시 검사 → (만들기) 켜기 → (자식만) 머리 판 올리기
  select count(*) into v_f0 from public.so s where s.reprice_suggested_at = now();
  v_narrow := not v_order and (v_create or not d.is_order_level);                                                  -- dsc-4d 판정 346: 저장 전 · 뒤 둘 다 줄 딜일 때만 창구가 센다(오더 딜이 끼면 트리거가 지금처럼 넓게)
  v_old_on := not v_create and d.is_active;  v_new_on := v_active;  v_cust := not v_rules_changed;                  -- 전은 저장 전 켜져 있었을 때만 · 뒤는 저장 뒤 켜져 있을 때만 · 손님 조건이 바뀌면 거르지 않는다(판정 313)
  if v_narrow and v_old_on then select coalesce(array_agg(distinct p.product_id), '{}') into v_pb from public.so_deal_products(v_id) p; else v_pb := '{}'; end if;   -- 전 제품(세트 포함 · 쓰기 전에 센다 · null 이면 「전부」가 되므로 빈 배열로)
  begin
    if v_narrow and not v_create then perform set_config('ims.deal_flag_door', v_id::text, true); end if;           -- dsc-4d 판정 346: 「이 딜은 창구가 찍는다」 — so_deal_changed · so_deal_part_changed 가 이 딜의 넓은 표시를 건너뛴다(트랜잭션 지역 · 블록 끝에 비운다)
    set constraints public.so_deal_tier_amount_uq, public.so_deal_line_deal_line_no_key deferred;
    if v_create then
      insert into public.so_deal (name, is_active, source, note, updated_by, date_from, date_to, is_order_level, kind, coupon_required)
      values (v_name, false, 'manual', v_note, v_staff, v_from, v_to, v_order, v_kind, v_coupon) returning id into v_id;                 -- 꺼진 채 만들고 끝에 켠다(손님 조건이 들어간 뒤 표시 트리거가 돌게)
      if v_narrow then perform set_config('ims.deal_flag_door', v_id::text, true); end if;                             -- dsc-4d 판정 346: 만들기는 id 가 지금 생긴다
    else
      if v_rules_given then
        delete from public.so_deal_customer_rule x where x.deal_id = v_id
           and not ((x.kind || '|' || x.target || '|' || coalesce(x.customer_id::text, x.warehouse_id::text, x.tier_id::text)) = any(coalesce((select array_agg(y->>'nk') from jsonb_array_elements(v_rules) y), '{}'::text[])));
      end if;
      if v_lines_given then
        for v_e in select x from jsonb_array_elements(v_lines) x where (x->>'id') is not null and jsonb_typeof(x->'targets') = 'array' loop
          delete from public.so_deal_target x where x.line_id = (v_e->>'id')::uuid
             and not ((x.kind || '|' || x.target || '|' || coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text)) = any(coalesce((select array_agg(y->>'nk') from jsonb_array_elements(v_e->'targets') y), '{}'::text[])));
        end loop;
        update public.so_deal_line l set is_active = false, updated_by = v_staff where l.deal_id = v_id and l.is_active and not (l.id = any(v_line_ids));
      end if;
      if v_tiers_given then
        delete from public.so_deal_tier t where t.deal_id = v_id and not (t.tier_no = any(coalesce((select array_agg((y->>'tier_no')::int) from jsonb_array_elements(v_tiers) y), '{}'::int[])));
      end if;
      if v_head_changed then
        update public.so_deal set name = v_name, is_active = v_active, date_from = v_from, date_to = v_to, is_order_level = v_order, kind = v_kind, coupon_required = v_coupon, note = v_note, updated_by = v_staff where id = v_id;
      end if;
    end if;
    if v_tiers_given then
      for v_e in select x from jsonb_array_elements(v_tiers) x loop
        update public.so_deal_tier t set min_amount = (v_e->>'min_amount')::numeric, pct = (v_e->>'pct')::numeric, note = v_e->>'note', updated_by = v_staff
         where t.deal_id = v_id and t.tier_no = (v_e->>'tier_no')::int
           and (t.min_amount <> (v_e->>'min_amount')::numeric or t.pct <> (v_e->>'pct')::numeric or t.note is distinct from (v_e->>'note'));
        if not found and not exists (select 1 from public.so_deal_tier t where t.deal_id = v_id and t.tier_no = (v_e->>'tier_no')::int) then
          insert into public.so_deal_tier (deal_id, tier_no, min_amount, pct, note, source, updated_by) values (v_id, (v_e->>'tier_no')::int, (v_e->>'min_amount')::numeric, (v_e->>'pct')::numeric, v_e->>'note', 'manual', v_staff);
        end if;
      end loop;
    end if;
    if v_lines_given then
      for v_e in select x from jsonb_array_elements(v_lines) x loop
        if (v_e->>'id') is not null then
          v_lid := (v_e->>'id')::uuid;
          update public.so_deal_line l set line_no = (v_e->>'line_no')::int, pct = (v_e->>'pct')::numeric, min_qty_mode = v_e->>'min_qty_mode', min_qty = (v_e->>'min_qty')::numeric, note = v_e->>'note', is_active = true, updated_by = v_staff
           where l.id = v_lid
             and (not l.is_active or l.line_no <> (v_e->>'line_no')::int or l.pct <> (v_e->>'pct')::numeric or l.min_qty_mode <> (v_e->>'min_qty_mode') or l.min_qty is distinct from (v_e->>'min_qty')::numeric or l.note is distinct from (v_e->>'note'));
        else
          insert into public.so_deal_line (deal_id, line_no, pct, min_qty_mode, min_qty, note, source, updated_by)
          values (v_id, (v_e->>'line_no')::int, (v_e->>'pct')::numeric, v_e->>'min_qty_mode', (v_e->>'min_qty')::numeric, v_e->>'note', 'manual', v_staff) returning id into v_lid;
        end if;
        if jsonb_typeof(v_e->'targets') = 'array' then
          for v_t in select x from jsonb_array_elements(v_e->'targets') x loop
            if not exists (select 1 from public.so_deal_target x where x.line_id = v_lid and (x.kind || '|' || x.target || '|' || coalesce(x.tag, x.brand_id::text, x.product_id::text, x.category_id::text)) = (v_t->>'nk')) then
              insert into public.so_deal_target (line_id, kind, target, tag, brand_id, product_id, category_id, note, source, updated_by)
              values (v_lid, v_t->>'kind', v_t->>'target',
                      case when v_t->>'target' = 'tag' then v_t->>'value' end,
                      case when v_t->>'target' = 'brand' then (v_t->>'value')::uuid end,
                      case when v_t->>'target' = 'product' then (v_t->>'value')::uuid end,
                      case when v_t->>'target' = 'category' then (v_t->>'value')::uuid end,
                      v_t->>'note', 'manual', v_staff);
            end if;
          end loop;
        end if;
      end loop;
    end if;
    if v_rules_given then
      for v_t in select x from jsonb_array_elements(v_rules) x loop
        if not exists (select 1 from public.so_deal_customer_rule x where x.deal_id = v_id and (x.kind || '|' || x.target || '|' || coalesce(x.customer_id::text, x.warehouse_id::text, x.tier_id::text)) = (v_t->>'nk')) then
          insert into public.so_deal_customer_rule (deal_id, kind, target, customer_id, warehouse_id, tier_id, note, source, updated_by)
          values (v_id, v_t->>'kind', v_t->>'target',
                  case when v_t->>'target' = 'customer' then (v_t->>'value')::uuid end,
                  case when v_t->>'target' = 'branch'   then (v_t->>'value')::uuid end,
                  case when v_t->>'target' = 'tier'     then (v_t->>'value')::uuid end,
                  v_t->>'note', 'manual', v_staff);
        end if;
      end loop;
    end if;
    set constraints all immediate;                                                                                  -- 맞바꾸기가 끝난 최종 모양을 지금 검사(어긋나면 23505 — 어휘 검사가 놓친 것)
    if v_create and v_active then
      update public.so_deal set is_active = true, updated_by = v_staff where id = v_id;
    elsif not v_create and v_child_changed and not v_head_changed then
      update public.so_deal set updated_by = v_staff where id = v_id;                                                -- 판정 331: 자식이 바뀌면 머리 판도 오른다(ims_touch)
    end if;
    if v_narrow then                                                                                                -- dsc-4d 판정 346: 창구가 직접 찍는다 = 「트리거가 찍었을 오더」 ∩ 「전 ∪ 뒤 제품이 든 오더」
      if v_new_on then select coalesce(array_agg(distinct p.product_id), '{}') into v_pa from public.so_deal_products(v_id) p; else v_pa := '{}'; end if;   -- 뒤 제품(쓰기 뒤 · 켜져 있을 때만)
      select coalesce(array_agg(distinct x), '{}') into v_pb from unnest(v_pb || v_pa) x;                           -- 전 ∪ 뒤(한 집합 · 기간이 옮겨 가며 대상도 바뀌면 소음 쪽)
      if v_flag_head or v_flag_child then                                                                           -- 트리거 WHEN 과 같은 뜻(이름 · 메모 · 줄 번호만 바뀐 저장은 트리거도 안 찍는다)
        if v_old_on then perform public.so_deal_flag_open_orders(v_id, d.date_from, d.date_to, v_cust, v_pb); end if;   -- 옛 기간(so_deal_changed 의 「옛 기간(켜져 있었으면)」)
        if v_new_on then perform public.so_deal_flag_open_orders(v_id, v_from, v_to, v_cust, v_pb); end if;             -- 새 기간(「새 기간(켜져 있으면)」)
      end if;
      perform set_config('ims.deal_flag_door', '', true);                                                           -- 블록 안에서 비운다 — 같은 트랜잭션의 뒤 쓰기(다른 호출 · 직접 SQL)는 트리거가 넓게 찍는다 · ZZ990 되돌림은 설정도 되돌린다(검증 N9)
    end if;
    select s.updated_at into v_new_updated from public.so_deal s where s.id = v_id;
    select count(*) into v_f1 from public.so s where s.reprice_suggested_at = now();
    v_flagged := v_f1 - v_f0;
    if v_flagged > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':open_orders_flagged', 'code', 'open_orders_flagged', 'n', v_flagged, 'message', format('%s open order(s) will be marked "reprice suggested" by this change', v_flagged));
      v_keys := array_append(v_keys, v_key || ':open_orders_flagged');
    end if;
    select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
    if not p_commit or cardinality(v_unacked) > 0 then
      raise exception using errcode = 'ZZ990', message = 'preview-rollback';
    end if;
  exception when sqlstate 'ZZ990' then
    v_rolled := true;
  end;

  if v_rolled then
    return jsonb_build_object('committed', false, 'deal_id', case when v_create then null else v_id end, 'updated_at', case when v_create then null else to_jsonb(d.updated_at) end,
                              'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', case when not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end, 'open_orders_to_flag', v_flagged);
  end if;
  return jsonb_build_object('committed', true, 'deal_id', v_id, 'updated_at', to_jsonb(v_new_updated), 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'open_orders_to_flag', v_flagged);
end;
$$;
comment on function public.so_deal_save(jsonb, jsonb, boolean, text[]) is
  '⭐ 딜 통째 저장 창구(dsc-4a · 판정 285 · 330 ~ 334 · 340 · dsc-4b 판정 343 · ⭐ dsc-4d 판정 346 · 347 · 2026-10-07) — security definer · 첫 줄 ims_require_write(master). p_deal = 딜 하나 {id(null = 만들기) · name · is_active · date_from · date_to · is_order_level · kind(pct) · coupon_required · note · tiers[{tier_no, min_amount, pct, note}] · lines[{id(null = 새 줄), line_no, pct, min_qty_mode, min_qty, note, targets[{kind, target, tag|brand_id|product_id|category_id, note}]}] · rules[{kind, target, customer_id|warehouse_id|tier_id, note}]} · 계약(판정 343): 없는 열쇠 = 그대로(만들기면 기본값) · [] = 전부 지움(줄은 끔) · is_active false 로 돌아온 줄 = 없는 줄 · 읽기 전용 칸(cin7_id · source · created_at · updated_at · updated_by · coupon_code · deal_id · line_id · 자식 id)은 지나친다 · 모르는 열쇠는 field_unknown · so_deal_detail 의 deal 덩이를 그대로 되돌리면 no_change. p_old = 화면이 읽은 updated_at 글자({updated_at} 또는 글자 하나) — 다르면 changed_elsewhere · 기존 딜인데 없으면 old_missing(판정 331). 짝(판정 340): 줄 = id(덩이에 없는 기존 줄은 끈다 · 꺼진 줄도 line_no 를 쥔다 · 판정 342) · 단계 = tier_no · 대상 · 손님 조건 = 내용 전체. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 막기 하나면 아무것도 안 바뀐다 · 미리 보기도 실제로 쓰고 표시 수를 센 뒤 되돌린다(open_orders_to_flag). ⭐ 열린 오더 표시(판정 346): 줄 딜(저장 전 · 뒤 둘 다)은 창구가 센다 — 「트리거가 이 저장에 찍었을 오더」 ∩ 「전(저장 전 켜져 있었으면) ∪ 뒤(저장 뒤 켜져 있으면) 제품(so_deal_products · 세트 포함)이 든 오더」 · 쓰기 동안 ims.deal_flag_door 설정으로 트리거의 넓은 표시를 건너뛴다 · 오더 딜이 끼면 트리거가 지금처럼 넓게 · 손님 조건이 바뀐 저장은 손님으로 거르지 않는다(313). blocks: deal_unknown · old_missing · changed_elsewhere · field_unknown · name_missing · value_invalid · kind_invalid · dates_invalid · tiers_invalid · tier_no_invalid · min_amount_invalid · pct_invalid · tier_no_duplicate · tier_amount_duplicate · lines_invalid · line_unknown · line_duplicate_in_call · line_no_invalid · min_qty_mode_invalid · min_qty_invalid(dsc-4d 문구 = 화면 낱말 At least · None · Full case) · line_no_duplicate · targets_invalid · target_value_invalid · tag_case_conflict · brand_unknown · product_unknown · category_unknown · target_duplicate_in_call · rules_invalid · rule_value_invalid · customer_unknown · warehouse_unknown · tier_unknown · rule_duplicate_in_call · line_on_order_deal · lines_block_order_level_on · tier_on_line_deal · tiers_block_order_level_off · no_change. warnings(ack): open_orders_flagged{n} · line_off_with_order_lines{n} · tag_unused{tags} · deal_off_with_coupons{n}(dsc-4d 판정 347: 쿠폰이 먹히던 상태 = 켜짐 ∧ coupon_required ∧ 오더 딜 → 안 먹히는 상태로 넘어가는 저장에서만) · line_no_targets(dsc-4d c: 화면이 그 줄에 대상을 하나도 안 보냈을 때만) · rules_open_to_all{n_before}(dsc-4b 판정 343). changes[{part head|tier|line|target|rule · action added|changed|removed|turned_off|turned_on|unchanged}] 는 미리 보기 · 쓰기 같다. 반환 {committed · deal_id · updated_at(다음 저장의 p_old) · changes · blocks · warnings · unacked · open_orders_to_flag}. 새 행은 source manual · 고친 행의 source 는 그대로(판정 339 는 아직). 자식만 바뀌어도 머리 updated_at 이 오른다(판정 331)';

-- ═══ 3) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := ''; v_t text; v_src text;
begin
  foreach v_t in array array['public.so_deal_save(jsonb, jsonb, boolean, text[])', 'public.so_deal_changed()', 'public.so_deal_part_changed()'] loop
    if to_regprocedure(v_t) is null then v_bad := v_bad || format(' %s(missing)', v_t); end if;
  end loop;
  foreach v_t in array array['public.so_deal_changed()', 'public.so_deal_part_changed()'] loop
    if has_function_privilege('authenticated', v_t, 'execute') or has_function_privilege('anon', v_t, 'execute') or has_function_privilege('public', v_t, 'execute') then v_bad := v_bad || format(' %s(open)', v_t); end if;
  end loop;
  if not has_function_privilege('authenticated', 'public.so_deal_save(jsonb, jsonb, boolean, text[])', 'execute') or has_function_privilege('anon', 'public.so_deal_save(jsonb, jsonb, boolean, text[])', 'execute') then v_bad := v_bad || ' so_deal_save(acl)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_save', 'so_deal_changed', 'so_deal_part_changed')) <> 3 then v_bad := v_bad || ' count'; end if;
  select p.prosrc into v_src from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_save';
  if v_src not like '%ims.deal_flag_door%' or v_src not like '%v_nsent%' or v_src not like '%"At least"%' or v_src not like '%d.coupon_required and d.is_order_level%' then v_bad := v_bad || ' so_deal_save(body)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_changed', 'so_deal_part_changed') and p.prosrc like '%ims.deal_flag_door%') <> 2 then v_bad := v_bad || ' triggers(body)'; end if;
  if (select count(*) from pg_trigger where not tgisinternal and tgrelid::regclass::text in ('so_deal', 'so_deal_tier', 'so_deal_line', 'so_deal_target', 'so_deal_customer_rule') and tgfoid in (select oid from pg_proc where proname in ('so_deal_changed', 'so_deal_part_changed')) and tgenabled <> 'D') <> 10 then v_bad := v_bad || ' triggers(attached)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('so_deal_products', 'so_deal_flag_open_orders', 'so_deal_list', 'so_deal_detail') and p.prosrc like '%dsc-4d%') <> 0 then v_bad := v_bad || ' untouched(touched)'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM346', message = format('STOP - dsc-4d did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
