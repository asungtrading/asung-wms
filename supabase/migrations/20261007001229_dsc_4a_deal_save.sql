-- ─────────────────────────────────────────────────────────────
-- 딜 통째 저장 창구 so_deal_save · 딜 줄 끄기(is_active) · 딜 표 다섯 + product_tag + so_coupon 직접 쓰기 닫기 (Asung-IMS · dsc-4a · 2026-10-06)
--   정본(뒤에 적는다): so-module 판정 330 ~ 335 · 338 · 340(dsc-4a 지시서 A · 2026-10-06 저녁) · §13-e ⬜5 뒤집기(딜 · 태그 쓰기 = 창구만)
--   판정 330  딜 줄은 지우지 않는다 · 끈다 — so_deal_line.is_active · 꺼진 줄은 후보에서 line_inactive 로 진다 · 「오더 딜에 줄이 없어야」 문지기는 켜진 줄만 · so_deal_line_changed_u WHEN 에 is_active
--   판정 331  딜의 판 = so_deal.updated_at — 화면은 읽은 글자를 그대로 p_old 로 되돌린다 · 다르면 changed_elsewhere · 기존 딜인데 없으면 old_missing · 자식을 고치면 창구가 머리도 건드려 판을 올린다
--   판정 332  대상 태그가 어느 제품에도 없으면 허용 + 알림 tag_unused(ack) · 대소문자만 다른 태그는 막는다 tag_case_conflict(product_tag · 다른 딜 대상 · 같은 호출) · 소문자로 바꾸지 않는다(btrim 만)
--   판정 333  so_deal_changed_u WHEN 에 coupon_required(켜면 자동 후보에서 빠진다 — 열린 오더에 표시) · 이름 · 메모는 여전히 표시 안 함
--   판정 334  쿠폰 딜을 끄거나 coupon_required 를 끌 때 쓰지 않은 쿠폰은 그대로 두고 알린다 deal_off_with_coupons{n}(ack)
--   판정 335  닫는 권한 = 일곱 표(so_deal · so_deal_tier · so_deal_line · so_deal_target · so_deal_customer_rule · product_tag · so_coupon) anon 전부 회수 · authenticated SELECT 만 · so_coupon_key public · anon 실행권 회수 · 나머지 25개 표(inv_ · wms_)는 무접촉(판정 후보 341)
--   판정 338  통째 저장 때 행 트리거가 행 수만큼 열린 오더 표시를 도는 것은 둔다(두 번째부터는 이미 표시된 오더를 건너뛴다)
--   판정 340  짝짓기 열쇠 — 줄 = id(없으면 새 줄 · 덩이에 없는 기존 줄은 끈다) · 단계 = tier_no · 대상 · 손님 조건 = 내용 전체(자연키) · 쓰는 순서 지우기 → 고치기 → 넣기 · 단계 금액 맞바꾸기 · 줄 번호 맞바꾸기는 성공해야 한다(⬜3 deferrable 유니크 둘)
--   ⬜1(나)  미리 보기의 「표시될 열린 오더 수」= 실제로 쓰고 센 뒤 서브트랜잭션으로 되돌린다 — 표시 대상을 고르는 식은 so_deal_flag_open_orders 한 곳 · 트리거가 그대로 돈다 · 되돌아가지 않는 부작용 없음(이 표들은 시퀀스를 안 쓴다 · now() 는 트랜잭션 시각)
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 바이트 복사 · 파일 안 begin/commit 없음 · 재발행 둘은 마지막 정의 바이트 복사 + 바뀐 줄만(so_deal_candidates 20261006193419:143~210 · so_deal_order_level_guard 20261006201443:96~111) · 끝의 do 블록이 실물을 세어 어긋나면 전부 되돌린다
--   원칙 1: IMS 는 Cin7 없이 돈다 — cin7 출처 행을 창구가 고쳐도 source 는 그대로(⬜4 · 판정 339 는 아직) · 새 행은 manual
-- ─────────────────────────────────────────────────────────────
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

-- ═══ 1) so_deal_line.is_active(판정 330) ═══
alter table public.so_deal_line add column if not exists is_active boolean not null default true;
comment on column public.so_deal_line.is_active is '켜짐(dsc-4a · 판정 330) — 딜 줄은 지우지 않는다(so_line.deal_line_id 가 가리킨다 · 기록) · 창구 so_deal_save 가 덩이에 없는 기존 줄을 끈다 · 꺼진 줄은 so_deal_candidates 에서 line_inactive 로 진다 · 꺼진 줄도 line_no 를 쥔다(unique (deal_id, line_no)) · 오더 딜 문지기는 켜진 줄만 센다';

-- 1b) so_deal_candidates 재발행 — 마지막 정의 20261006193419:143~210(DB md5 bd9c8b9e 일치) · 바뀐 줄 둘: cand 에 l.is_active as line_active · judged 에 line_inactive(inactive 다음)
create or replace function public.so_deal_candidates(p_product_id uuid, p_customer_id uuid, p_tier_id uuid, p_qty_ea numeric, p_on date)
  returns table (deal_id uuid, deal_name text, line_id uuid, line_no int, pct numeric, min_qty_mode text, min_qty numeric, status text, reason text)
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
#variable_conflict use_column
begin
  return query
  with p as (                                                                              -- 제품 쪽 판정 대상 = 줄의 제품 + (세트면) 그 낱개
    select pr.id, pr.brand_id, pr.category_id,
           (select min(s.pack_factor) from public.product s where s.parent_product_id = pr.id and s.is_active and s.pack_factor is not null) as case_qty
    from public.product pr where pr.id = p_product_id
    union all
    select b.id, b.brand_id, b.category_id,
           (select min(s.pack_factor) from public.product s where s.parent_product_id = b.id and s.is_active and s.pack_factor is not null)
    from public.product pr join public.product b on b.id = pr.parent_product_id where pr.id = p_product_id
  ),
  hit as (                                                                                 -- 대상 줄이 제품(또는 낱개)에 맞나
    select t.line_id, t.kind
    from public.so_deal_target t
    where exists (select 1 from p
                   where (t.target = 'product'  and t.product_id  = p.id)
                      or (t.target = 'brand'    and t.brand_id    = p.brand_id)
                      or (t.target = 'category' and t.category_id = p.category_id)
                      or (t.target = 'tag'      and exists (select 1 from public.product_tag pt where pt.product_id = p.id and pt.tag = t.tag)))
  ),
  cand as (                                                                                -- 후보 = 제품 쪽 걸기에 맞는 딜 줄만(판정 300)
    select l.id as line_id, l.deal_id, l.line_no, l.pct, l.min_qty_mode, l.min_qty, d.name as deal_name, d.is_active, d.kind, d.date_from, d.date_to,
           l.is_active as line_active,                                                                                    -- dsc-4a 판정 330: 꺼진 줄
           exists (select 1 from hit h where h.line_id = l.id and h.kind = 'exclude') as excluded_product,
           (select max(case_qty) from p) as case_qty                                                                         -- case 모드의 한 케이스 = 낱개의 켜진 세트 중 최소 계수(세트 줄이면 그 낱개 기준 · 낱개 EA 로 비교)
    from public.so_deal_line l
    join public.so_deal d on d.id = l.deal_id
    where not d.is_order_level and exists (select 1 from hit h where h.line_id = l.id and h.kind = 'include')
  ),
  cust as (                                                                                -- 손님 쪽 판정은 딜마다 한 번(줄마다가 아니라) · 빼기 맞음 / 전체 판정
    select d.deal_id,
           exists (select 1 from public.so_deal_customer_rule x where x.deal_id = d.deal_id and x.kind = 'exclude'
                    and case x.target when 'customer' then x.customer_id = p_customer_id
                                      when 'branch'   then x.warehouse_id = (select cu.default_location_id from public.customer cu where cu.id = p_customer_id)
                                      when 'tier'     then x.tier_id = p_tier_id end) as excluded,
           public.so_deal_customer_ok(d.deal_id, p_customer_id, p_tier_id) as ok
    from (select distinct c.deal_id from cand c) d
  ),
  judged as (
    select c.*,
           case
             when not c.is_active then 'inactive'
             when not c.line_active then 'line_inactive'                                                                   -- dsc-4a 판정 330
             when c.kind <> 'pct' then 'kind_not_pct'
             when c.date_from is not null and c.date_from > p_on then 'period_before'
             when c.date_to   is not null and c.date_to   < p_on then 'period_after'
             when c.excluded_product then 'excluded_product'
             when k.excluded then 'customer_excluded'
             when not k.ok then 'customer_not_matched'
             when c.min_qty_mode = 'qty'  and coalesce(p_qty_ea, 0) < c.min_qty then 'below_min_qty'
             when c.min_qty_mode = 'case' and (c.case_qty is null or coalesce(p_qty_ea, 0) < c.case_qty) then 'below_min_qty'
             else null
           end as fail
    from cand c join cust k on k.deal_id = c.deal_id
  ),
  ranked as (
    select j.*, row_number() over (partition by (j.fail is null) order by j.pct desc, j.deal_id, j.line_no) as rn from judged j
  )
  select r.deal_id, r.deal_name, r.line_id, r.line_no, r.pct, r.min_qty_mode, r.min_qty,
         case when r.fail is null and r.rn = 1 then 'won' else 'lost' end as status,
         case when r.fail is null and r.rn = 1 then 'won' when r.fail is null then 'lower_pct' else r.fail end as reason
  from ranked r
  order by (r.fail is null and r.rn = 1) desc, r.pct desc, r.deal_id, r.line_no;
end $$;
comment on function public.so_deal_candidates(uuid, uuid, uuid, numeric, date) is '⭐ 딜 후보 전부(dsc-2 · 판정 300 · 287 · dsc-4a 재발행 판정 330) — 제품(세트면 그 낱개까지) 쪽 걸기에 맞는 딜 줄만 후보 · 줄마다 status won|lost · reason inactive → line_inactive(꺼진 줄 · dsc-4a) → kind_not_pct → period_before/period_after → excluded_product → customer_excluded → customer_not_matched(판정 299 AND) → below_min_qty → lower_pct → won · 수량은 낱개 EA(판정 279 · 세트 줄은 qty × pack_factor 를 부르는 쪽이 곱한다 · case 모드 = 낱개의 켜진 세트 중 최소 계수) · 기간은 p_on(오더 날짜 · D7) · 티어 = 오더 so.price_tier_id · so_deal_best 는 이 결과의 won 한 줄 · so_quote_preview 가 목록을 그대로 보인다 · definer';

-- 1c) so_deal_order_level_guard 재발행 — 마지막 정의 20261006201443:96~111(DB md5 b70ab0fd 일치) · 바뀐 줄 하나: 켜진 줄만 센다(판정 330)
create or replace function public.so_deal_order_level_guard() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if new.is_order_level and not old.is_order_level
     and exists (select 1 from public.so_deal_line l where l.deal_id = new.id and l.is_active) then                         -- dsc-4a 판정 330: 꺼진 줄은 세지 않는다
    raise exception 'Deal % has lines — remove them before making it an order-level deal — nothing was saved', new.name;
  end if;
  if not new.is_order_level and old.is_order_level
     and exists (select 1 from public.so_deal_tier t where t.deal_id = new.id) then                                              -- dsc-3a 판정 309: 단계가 있는 딜은 오더 딜을 끌 수 없다
    raise exception 'Deal % has amount tiers — remove them before turning off order-level — nothing was saved', new.name;
  end if;
  return new;
end;
$$;
comment on function public.so_deal_order_level_guard() is 'so_deal BEFORE UPDATE — 켜진 줄이 있는 딜에 is_order_level 을 켜면 거부(이견 6 의 반대쪽 문 · dsc-4a 판정 330: 꺼진 줄은 세지 않는다) · dsc-3a: 단계(so_deal_tier)가 있는 딜에서 is_order_level 을 끄면 거부(판정 309) · insert 는 줄 · 단계가 있을 수 없어 보지 않는다';

-- 1d) so_deal_line_changed_u — WHEN 에 is_active(판정 330) · 함수 so_deal_part_changed 는 그대로(줄의 deal_id 로 딜을 찾는다)
drop trigger if exists so_deal_line_changed_u on public.so_deal_line;
create trigger so_deal_line_changed_u  after update on public.so_deal_line for each row
  when ((old.deal_id, old.pct, old.min_qty_mode, old.min_qty, old.is_active) is distinct from (new.deal_id, new.pct, new.min_qty_mode, new.min_qty, new.is_active)) execute function public.so_deal_part_changed();

-- ═══ 2) so_deal_changed_u — WHEN 에 coupon_required(판정 333) · 함수 so_deal_changed 는 그대로(옛 기간 · 새 기간을 켜짐으로만 가른다 — 그 칸을 볼 필요가 없다) ═══
drop trigger if exists so_deal_changed_u on public.so_deal;
create trigger so_deal_changed_u after update on public.so_deal
  for each row when ((old.is_active, old.date_from, old.date_to, old.is_order_level, old.kind, old.coupon_required) is distinct from (new.is_active, new.date_from, new.date_to, new.is_order_level, new.kind, new.coupon_required))
  execute function public.so_deal_changed();
comment on function public.so_deal_changed() is 'so_deal AFTER INSERT · DELETE · UPDATE(WHEN is_active · date_from · date_to · is_order_level · kind · coupon_required(dsc-4a 판정 333) 가 바뀔 때) — 옛 기간(켜져 있었으면) 과 새 기간(켜져 있으면)의 열린 오더에 다시 매기기 권함(dsc-3a · 판정 313) · 적재 upsert 가 값을 안 바꾸면 WHEN 이 걸러 아무 오더도 안 건드린다 · 이름 · 메모는 표시하지 않는다';

-- ═══ 3) 유니크 둘을 deferrable 로(⬜3 · 판정 340 — 단계 금액 맞바꾸기 · 줄 번호 맞바꾸기는 성공해야 한다) · 창구 안에서 set constraints … deferred → 쓰기 끝에 all immediate ═══
alter table public.so_deal_tier drop constraint so_deal_tier_amount_uq;
alter table public.so_deal_tier add constraint so_deal_tier_amount_uq unique (deal_id, min_amount) deferrable initially immediate;
alter table public.so_deal_line drop constraint so_deal_line_deal_line_no_key;
alter table public.so_deal_line add constraint so_deal_line_deal_line_no_key unique (deal_id, line_no) deferrable initially immediate;

-- ═══ 4) so_deal_save — 딜 통째 저장 창구(판정 330 ~ 334 · 340 · 두 번 부르기 · old 대조 · product_update · product_bom_set 모양) ═══
create function public.so_deal_save(p_deal jsonb, p_old jsonb default null, p_commit boolean default false, p_ack text[] default '{}')
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
  else
    for v_r in
      select * from (values ('name', to_jsonb(d.name), to_jsonb(v_name)), ('is_active', to_jsonb(d.is_active), to_jsonb(v_active)), ('date_from', to_jsonb(d.date_from), to_jsonb(v_from)), ('date_to', to_jsonb(d.date_to), to_jsonb(v_to)),
                           ('is_order_level', to_jsonb(d.is_order_level), to_jsonb(v_order)), ('kind', to_jsonb(d.kind), to_jsonb(v_kind)), ('coupon_required', to_jsonb(d.coupon_required), to_jsonb(v_coupon)), ('note', to_jsonb(d.note), to_jsonb(v_note))) as f(field, oldv, newv)
    loop
      if v_r.oldv is distinct from v_r.newv then
        v_changes := v_changes || jsonb_build_object('part', 'head', 'action', 'changed', 'field', v_r.field, 'old', v_r.oldv, 'new', v_r.newv);
        v_head_changed := true;
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
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_qty_invalid:' || v_ln, 'code', 'min_qty_invalid', 'message', format('Line %s: min_qty must be above 0 when min_qty_mode is qty (got "%s") — nothing was saved', v_ln, coalesce(v_txt, '')));
            continue;
          end if;
          v_mq := v_txt::numeric;
        else
          if v_txt is not null then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':min_qty_invalid:' || v_ln, 'code', 'min_qty_invalid', 'message', format('Line %s: min_qty must be empty when min_qty_mode is %s — nothing was saved', v_ln, v_mode));
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
        for v_t in select x from jsonb_array_elements(v_e->'targets') x loop
          v_changes := v_changes || jsonb_build_object('part', 'target', 'action', 'added', 'line_id', null, 'line_no', (v_e->>'line_no')::int, 'kind', v_t->>'kind', 'target', v_t->>'target', 'value', v_t->>'value');
        end loop;
        if jsonb_array_length(v_e->'targets') = 0 then
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
          end loop;
          if jsonb_array_length(v_e->'targets') = 0 then
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
    end loop;
  end if;
  if cardinality(v_unused) > 0 then
    v_warns := v_warns || jsonb_build_object('key', v_key || ':tag_unused', 'code', 'tag_unused', 'tags', to_jsonb(v_unused), 'message', format('No product carries the tag(s) %s yet — the deal saves, but matches nothing on them until products get the tag', array_to_string(v_unused, ', ')));
    v_keys := array_append(v_keys, v_key || ':tag_unused');
  end if;
  if not v_create and ((d.is_active and not v_active) or (d.coupon_required and not v_coupon)) then                   -- 판정 334
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
  begin
    set constraints public.so_deal_tier_amount_uq, public.so_deal_line_deal_line_no_key deferred;
    if v_create then
      insert into public.so_deal (name, is_active, source, note, updated_by, date_from, date_to, is_order_level, kind, coupon_required)
      values (v_name, false, 'manual', v_note, v_staff, v_from, v_to, v_order, v_kind, v_coupon) returning id into v_id;                 -- 꺼진 채 만들고 끝에 켠다(손님 조건이 들어간 뒤 표시 트리거가 돌게)
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
revoke all on function public.so_deal_save(jsonb, jsonb, boolean, text[]) from public, anon;
grant execute on function public.so_deal_save(jsonb, jsonb, boolean, text[]) to authenticated;
comment on function public.so_deal_save(jsonb, jsonb, boolean, text[]) is
  '⭐ 딜 통째 저장 창구(dsc-4a · 판정 285 · 330 ~ 334 · 340 · 2026-10-06) — security definer · 첫 줄 ims_require_write(master). p_deal = 딜 하나 {id(null = 만들기) · name · is_active · date_from · date_to · is_order_level · kind(pct) · coupon_required · note · tiers[{tier_no, min_amount, pct, note}] · lines[{id(null = 새 줄), line_no, pct, min_qty_mode, min_qty, note, targets[{kind, target, tag|brand_id|product_id|category_id, note}]}] · rules[{kind, target, customer_id|warehouse_id|tier_id, note}]} · 없는 열쇠 = 그대로(만들기면 기본값) · 읽기 전용 칸(cin7_id · source · created_at · updated_at · updated_by · coupon_code · deal_id · line_id)은 지나친다 · 모르는 열쇠는 field_unknown. p_old = 화면이 읽은 updated_at 글자({updated_at} 또는 글자 하나) — 다르면 changed_elsewhere · 기존 딜인데 없으면 old_missing(판정 331). 짝(판정 340): 줄 = id(덩이에 없는 기존 줄은 끈다 · is_active false 로 돌아온 줄도 같다 · 꺼진 줄도 line_no 를 쥔다) · 단계 = tier_no(없으면 지움) · 대상 · 손님 조건 = 내용 전체(없으면 지움 · 줄의 targets 열쇠가 없으면 그대로). 검사만(p_commit false) → 저장(p_commit true + p_ack) · 막기 하나면 아무것도 안 바뀐다 · 미리 보기도 실제로 쓰고 표시 수를 센 뒤 되돌린다(open_orders_to_flag · ⬜1 나). blocks: deal_unknown · old_missing · changed_elsewhere · field_unknown · name_missing · value_invalid · kind_invalid · dates_invalid · tiers_invalid · tier_no_invalid · min_amount_invalid · pct_invalid · tier_no_duplicate · tier_amount_duplicate · lines_invalid · line_unknown · line_duplicate_in_call · line_no_invalid · min_qty_mode_invalid · min_qty_invalid · line_no_duplicate · targets_invalid · target_value_invalid · tag_case_conflict · brand_unknown · product_unknown · category_unknown · target_duplicate_in_call · rules_invalid · rule_value_invalid · customer_unknown · warehouse_unknown · tier_unknown · rule_duplicate_in_call · line_on_order_deal · lines_block_order_level_on · tier_on_line_deal · tiers_block_order_level_off · no_change. warnings(ack): open_orders_flagged{n} · line_off_with_order_lines{n} · tag_unused{tags} · deal_off_with_coupons{n} · line_no_targets. changes[{part head|tier|line|target|rule · action added|changed|removed|turned_off|turned_on|unchanged · …}] 는 미리 보기 · 쓰기 같다. 반환 {committed · deal_id · updated_at(다음 저장의 p_old) · changes · blocks · warnings · unacked · open_orders_to_flag}. 새 행은 source manual · 고친 행의 source 는 그대로(판정 339 는 아직). 자식만 바뀌어도 머리 updated_at 이 오른다(판정 331)';

-- ═══ 5) 직접 쓰기 닫기(판정 335) — 정책 drop + 권한 revoke(prod-2 20261001123000:115~118 모양) · anon 전부 회수(20260923224900:422 모양) · so_coupon_key 실행권 ═══
drop policy if exists so_deal_insert               on public.so_deal;
drop policy if exists so_deal_update               on public.so_deal;
drop policy if exists so_deal_tier_insert          on public.so_deal_tier;
drop policy if exists so_deal_tier_update          on public.so_deal_tier;
drop policy if exists so_deal_tier_delete          on public.so_deal_tier;
drop policy if exists so_deal_line_insert          on public.so_deal_line;
drop policy if exists so_deal_line_update          on public.so_deal_line;
drop policy if exists so_deal_line_delete          on public.so_deal_line;
drop policy if exists so_deal_target_insert        on public.so_deal_target;
drop policy if exists so_deal_target_update        on public.so_deal_target;
drop policy if exists so_deal_target_delete        on public.so_deal_target;
drop policy if exists so_deal_customer_rule_insert on public.so_deal_customer_rule;
drop policy if exists so_deal_customer_rule_update on public.so_deal_customer_rule;
drop policy if exists so_deal_customer_rule_delete on public.so_deal_customer_rule;
revoke insert, update, delete, truncate on public.so_deal, public.so_deal_tier, public.so_deal_line, public.so_deal_target, public.so_deal_customer_rule, public.product_tag, public.so_coupon from authenticated;
revoke all on public.so_deal, public.so_deal_tier, public.so_deal_line, public.so_deal_target, public.so_deal_customer_rule, public.product_tag, public.so_coupon from anon;
revoke all on function public.so_coupon_key(text) from public, anon;
grant execute on function public.so_coupon_key(text) to authenticated;
comment on table public.so_deal is '⭐ SO 딜(할인 규칙 ②-0a · D1·D2 · dsc-2 · 3a · 3b · 4a) — 딜 = 이름 · 기간 · 켜짐 · 줄(so_deal_line · % · 걸기·빼기 · 몇 개 이상) 또는 오더 전체 딜(is_order_level · 금액 단계 so_deal_tier) · 손님 조건 so_deal_customer_rule · 쿠폰 딜 coupon_required(so_coupon). 기간 판정은 so.order_date(D7). SO 모듈 소유 마스터(9-b) · ⚠️ 쓰기는 창구만 — so_deal_save(master · dsc-4a 판정 285 · 335 · §13-e ⬜5 뒤집음) · 표는 읽기 RLS 만 · 정본 docs/design/so-module.md §13 · §47 ~ §49';
comment on table public.so_deal_line is '딜 줄(②-0a · dsc-2 · dsc-4a) — % · 몇 개 이상(none | qty N | case) · 걸기 · 빼기는 so_deal_target · is_active(판정 330 · 지우지 않는다 — so_line.deal_line_id 가 가리킨다 · 꺼진 줄도 line_no 를 쥔다) · unique (deal_id, line_no) 는 deferrable(창구 안 번호 맞바꾸기 · 판정 340) · ⚠️ 쓰기는 창구만 — so_deal_save(master · 판정 335) · 읽기 RLS 만';
comment on table public.so_deal_target is '딜 줄의 걸기 · 빼기(②-0a · dsc-2 · dsc-4a) — kind include | exclude · target tag | brand | product | category · 값 칸은 종류마다 하나 · 유니크 7칸 nulls not distinct(자연키 = 창구의 짝 · 판정 340) · 태그는 글자 그대로(대소문자만 다른 태그는 창구가 막는다 tag_case_conflict · 판정 332) · ⚠️ 쓰기는 창구만 — so_deal_save(master · 판정 335) · 읽기 RLS 만';
comment on table public.so_deal_tier is '⭐ 오더 전체 딜의 금액 단계(dsc-3a · 판정 282 · 309 · dsc-4a) — 한 프로모션 = 딜 하나 · 단계 = 행 · 기준 금액 = 줄 할인 뒤 제품 줄 합계(so_lines_total) · 걸리는 단계 중 가장 큰 pct(so_order_discount) · min_amount 0 = 조건 없음 · is_order_level 딜에만(so_deal_tier_order_level_guard) · unique (deal_id, min_amount) 는 deferrable(창구 안 금액 맞바꾸기 · 판정 340) · ⚠️ 쓰기는 창구만 — so_deal_save(master · 판정 335 · 짝 = tier_no) · 읽기 RLS 만';
comment on table public.so_deal_customer_rule is '⭐ 딜의 손님 조건(dsc-2 · 판정 278 · 299 · dsc-4a) — 딜 단위 · kind include | exclude · target customer | branch | tier · 값 칸은 종류마다 따로 · 판정 = 빼기 하나라도 맞으면 뺀다 · 걸기는 같은 종류 안 OR · 다른 종류끼리 AND · 걸기 줄 없으면 전체 · 식은 so_deal_customer_ok 한 곳 · 손님 그룹은 칸을 아직 두지 않는다 · ⚠️ 쓰기는 창구만 — so_deal_save(master · 판정 335 · 짝 = 내용 전체 · 판정 340) · 읽기 RLS 만';

-- ═══ 6) 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare
  v_t    text;
  v_bad  text := '';
  v_pol  int;
  v_sel  int;
  v_n    int;
begin
  foreach v_t in array array['so_deal', 'so_deal_tier', 'so_deal_line', 'so_deal_target', 'so_deal_customer_rule', 'product_tag', 'so_coupon'] loop
    select count(*), count(*) filter (where cmd = 'SELECT' and roles = '{authenticated}'::name[]) into v_pol, v_sel from pg_policies where schemaname = 'public' and tablename = v_t;
    if v_pol <> 1 or v_sel <> 1 then v_bad := v_bad || format(' %s(policies %s · select %s)', v_t, v_pol, v_sel); end if;
    if has_table_privilege('authenticated', format('public.%I', v_t), 'insert') or has_table_privilege('authenticated', format('public.%I', v_t), 'update')
       or has_table_privilege('authenticated', format('public.%I', v_t), 'delete') or has_table_privilege('authenticated', format('public.%I', v_t), 'truncate')
       or has_any_column_privilege('authenticated', format('public.%I', v_t), 'update') or not has_table_privilege('authenticated', format('public.%I', v_t), 'select') then
      v_bad := v_bad || format(' %s(authenticated privileges)', v_t);
    end if;
    if has_table_privilege('anon', format('public.%I', v_t), 'select') or has_table_privilege('anon', format('public.%I', v_t), 'insert') or has_table_privilege('anon', format('public.%I', v_t), 'update')
       or has_table_privilege('anon', format('public.%I', v_t), 'delete') or has_table_privilege('anon', format('public.%I', v_t), 'truncate') or has_table_privilege('anon', format('public.%I', v_t), 'references')
       or has_table_privilege('anon', format('public.%I', v_t), 'trigger') or has_any_column_privilege('anon', format('public.%I', v_t), 'select') then
      v_bad := v_bad || format(' %s(anon privileges)', v_t);
    end if;
    if not (select relrowsecurity from pg_class where oid = format('public.%I', v_t)::regclass) then v_bad := v_bad || format(' %s(rls off)', v_t); end if;
  end loop;
  if to_regprocedure('public.so_deal_save(jsonb, jsonb, boolean, text[])') is null then v_bad := v_bad || ' so_deal_save'; end if;
  if not has_function_privilege('authenticated', 'public.so_deal_save(jsonb, jsonb, boolean, text[])', 'execute') or has_function_privilege('anon', 'public.so_deal_save(jsonb, jsonb, boolean, text[])', 'execute') then v_bad := v_bad || ' so_deal_save(grants)'; end if;
  if not has_function_privilege('authenticated', 'public.so_coupon_key(text)', 'execute') or has_function_privilege('anon', 'public.so_coupon_key(text)', 'execute') then v_bad := v_bad || ' so_coupon_key(grants)'; end if;
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so_deal_line' and column_name = 'is_active') then v_bad := v_bad || ' so_deal_line.is_active'; end if;
  if (select count(*) from pg_constraint where conname in ('so_deal_tier_amount_uq', 'so_deal_line_deal_line_no_key') and condeferrable and not condeferred) <> 2 then v_bad := v_bad || ' deferrable-uniques'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_deal_line'::regclass and tgname = 'so_deal_line_changed_u' and pg_get_triggerdef(oid) like '%old.is_active IS DISTINCT FROM new.is_active%') <> 1 then v_bad := v_bad || ' so_deal_line_changed_u(when)'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so_deal'::regclass and tgname = 'so_deal_changed_u' and pg_get_triggerdef(oid) like '%old.coupon_required IS DISTINCT FROM new.coupon_required%') <> 1 then v_bad := v_bad || ' so_deal_changed_u(when)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_candidates' and p.prosrc like '%line_inactive%') <> 1 then v_bad := v_bad || ' so_deal_candidates(line_inactive)'; end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'so_deal_order_level_guard' and p.prosrc like '%l.is_active%') <> 1 then v_bad := v_bad || ' so_deal_order_level_guard(is_active)'; end if;
  -- 일곱 표에 쓰는 함수 가운데 invoker 이면서 authenticated 가 부를 수 있는 것 = 0(닫는 순간 직원에게 42501 이 될 길 · 판정 264 의 거울)
  select count(*) into v_n
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and not p.prosecdef and has_function_privilege('authenticated', p.oid, 'execute')
     and p.prosrc ~* '(insert\s+into|update|delete\s+from)\s+(public\.)?(so_deal|so_deal_tier|so_deal_line|so_deal_target|so_deal_customer_rule|product_tag|so_coupon)\M';
  if v_n <> 0 then v_bad := v_bad || format(' invoker-writers(%s)', v_n); end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM335', message = format('STOP - dsc-4a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
