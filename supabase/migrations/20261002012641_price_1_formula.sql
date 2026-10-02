-- price-1 — 가격식 DB: 공급처 식 · 환율 한 곳 · 티어 규칙 · 계산 함수 · 미리 보기 · 저장 창구(admin) · product_update price_set 손질 (2026-10-02 UTC · 판정 215 ~ 223 · 가격식 묶음 1 ~ 8 · price-1 묶음 1 ~ 8 · so-module §35-a · po-module §3-h 「가격식 — 정한 것」)
--   판정 222  Wholesale = Latest cost × 환율(USD 1.4 · CAD 1) × 운임·기타 × (1 + 관세 %) ÷ 마진 → 끝자리 올림(217) → 나머지 티어(219) · 원산지 통화는 하지 않는다 · 적용할 상품은 Preview 에서 고른다
--   판정 223  식은 공급처마다 이름 붙인 식 여럿 · 하나가 기본 · 식을 걸면 상품의 공급처 줄에 어느 식인지 남는다(product_supplier.price_formula_id)
--   묶음 1    price_formula — 공급처 FK · name(공급처 안 unique · 창구가 대소문자 · 공백을 접어 막는다) · is_default(공급처당 켜진 기본 하나 — 부분 유니크 없음 · 창구가 지킨다) · currency CAD|USD · freight > 0 · duty_pct 0 ≤ d < 100 · margin 0 < m ≤ 1 · endings ⊆ {9 … 99} 비지 않음
--   묶음 2    price_fx — 통화마다 CAD 환율 하나(CAD 1 · USD 1.4) · 창구 price_fx_save 는 USD 만 바꾼다 · ⬜ 안 셋 중 「새 작은 표」: FK · CHECK · ims_touch 가 붙고 admin 창구로 닫기 쉽다 · ref_currency 는 적재(ImsRefLoad)가 쓰는 표라 칸을 섞지 않는다 · inv_config 는 글자 값이라 숫자 CHECK · FK 가 없다
--   묶음 3    product_supplier.price_formula_id — 마지막으로 건 식 · nullable · FK · 인덱스 · 트리거 price_formula_supplier_lock(IM223) 이 다른 공급처의 식을 막는다(⬜ 창구 + 트리거 — 그 칸이 SET 에 들어올 때만 돈다 · 적재 ImsLoadProductSupplier.gs 는 이 칸을 보내지 않는다 · docs/probes 291 ~ 292행)
--   묶음 4    price_tier_rule — sale 티어마다 op(mul|div) · factor · Wholesale(code 1)은 넣지 않는다(식이 낸다 · 기준 티어는 칸이 아니다) · seed Franchise ×1 · AONE ÷0.6 · Regular CAD ×1.05 · USWholesale USD ÷1.25(판정 219 · USD 티어도 환율로 다시 나누지 않는다 — Caleb 원문 · 실물 9.19 → 7.39)
--   묶음 5    계산은 price_formula_calc(p_formula, p_cost) 한 곳 — 식 id 또는 통째 식 → 끝자리 올림 → 티어 → 끝자리 올림 · 도착 원가 · GP · 저장 없음 · Preview · New products · 다시 걸기가 모두 이것을 쓴다
--             ⬜ 반올림: 계산 중에는 반올림하지 않고(numeric) 끝자리 올림만 · 반환의 landed · wholesale_raw · gp_pct 는 4 자리 · 가격은 센트 두 자리 그대로
--   묶음 6    product_update price_set 에 선택 칸 formula(id 또는 통째) — 창구가 그 상품 · 그 식의 공급처 줄의 지금 Latest 로 다시 계산해 그 티어 값과 numeric 등호면 source formula + price_formula_id 채움 · 다르면 manual + 알리기 formula_mismatch · 통째 식이면 id 가 없어 price_formula_id 는 null + 알리기 formula_unsaved(⬜) · 세트에 formula 는 막기 formula_on_set · 저장 직전 재검사(판정 176)가 같은 검사를 다시 돌려 저장 때 Latest 로 판정
--   묶음 7    식 · 환율 · 티어 규칙 저장 = admin 만(ims_require_admin — ⬜ ims_require_write 와 같은 한 줄 함수 하나) · 읽기는 로그인한 모두 · 식을 걸어 가격을 저장하는 것은 product_update 의 master 열쇠 그대로
--   함수      price_round_up(p_value, p_endings) immutable · price_formula_calc(p_formula, p_cost) stable · price_formula_preview(p_formula, p_skus) stable(최대 1,000) · price_formula_save · price_fx_save · price_tier_rule_save(p_changes, p_commit, p_ack) definer(두 번 부르기 · 막기 · 알리기 · product_update 모양)
--   막기 code  price_formula_save: formula_unknown · formula_inactive · supplier_unknown · name_missing · name_duplicate · field_duplicate_in_call · formula_invalid · old_missing · changed_elsewhere · op_unknown
--             price_fx_save: currency_unknown · fx_cad_fixed · rate_not_positive · old_missing · changed_elsewhere · field_duplicate_in_call
--             price_tier_rule_save: tier_invalid · tier_rule_wholesale · op_invalid · factor_not_positive · old_missing · changed_elsewhere · field_duplicate_in_call
--             price_formula_calc(반환 blocks): formula_invalid · formula_unknown · formula_inactive · fx_missing · no_cost / product_update price_set: formula_on_set · formula_invalid
--   알리기 code price_formula_save: default_off · formula_in_use / price_fx_save: fx_big_change / product_update price_set: formula_mismatch · formula_unsaved
--   미리 보기 flags: unknown_sku · set_skipped · no_supplier_link · no_cost · currency_differs · manual_price · big_change
--   재발행    product_update — 20261001152712 본문 바이트 그대로 + price_set 의 formula 칸(검사 · 저장 · 선언 여섯 줄) + 머리 · comment 의 op 설명 · formula 칸 없는 줄은 옛 동작 그대로(검증 R 절 jsonb 등호)
--   검증: ~/asung/prompts/price-1-verify.sql (시험 적용 장치 · 테스트 DB · rollback) · ⚠️ 운영 무접촉
--   ⚠️ 첫 문장은 supabase/ops/guard-test-only.sql 의 바이트 복사 — 운영에서는 멈춘다(컷오버 전 운영 적용 금지 · ims-principles)

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

-- ═══ ① admin 문 — 한 줄 함수(ims_require_write 와 같은 자리 · 묶음 7) ═══════════════════════════════════════════════════════
create or replace function public.ims_require_admin(p_what text) returns void
  language plpgsql stable
  set search_path = public, pg_temp
as $$
begin
  if public.ims_is_admin() then
    return;
  end if;
  raise exception 'Only an admin can change % — nothing was saved', p_what;
end;
$$;
revoke all on function public.ims_require_admin(text) from public, anon;
grant execute on function public.ims_require_admin(text) to authenticated;
comment on function public.ims_require_admin(text) is '⭐ admin 문(price-1 · 묶음 7) — ims_is_admin() 이 아니면 raise · 식 · 환율 · 티어 규칙 창구의 첫 줄 · ims_require_write 와 같은 모양';

-- ═══ ② 표 셋 — price_formula · price_fx · price_tier_rule (IMS 규약 칸 · ims_touch · select 열림 · 쓰기는 창구로만) ══════════════
create table if not exists public.price_formula (
  id            uuid primary key default gen_random_uuid(),
  is_active     boolean not null default true,
  source        text not null default 'manual',
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  supplier_id   uuid not null references public.supplier (id) on delete no action,
  name          text not null,
  is_default    boolean not null default false,
  currency_id   uuid not null references public.ref_currency (id) on delete no action,
  freight       numeric(18,7) not null,
  duty_pct      numeric(9,4) not null default 0,
  margin        numeric(9,6) not null,
  endings       smallint[] not null,
  constraint price_formula_source_ck   check (source = 'manual'),
  constraint price_formula_name_ck     check (name = trim(name) and name <> ''),
  constraint price_formula_freight_ck  check (freight > 0),
  constraint price_formula_duty_ck     check (duty_pct >= 0 and duty_pct < 100),
  constraint price_formula_margin_ck   check (margin > 0 and margin <= 1),
  constraint price_formula_endings_ck  check (cardinality(endings) >= 1 and endings <@ array[9, 19, 29, 39, 49, 59, 69, 79, 89, 99]::smallint[]),
  constraint price_formula_name_key    unique (supplier_id, name)
);
create index if not exists price_formula_supplier_idx on public.price_formula (supplier_id);
create trigger price_formula_touch before update on public.price_formula for each row execute function public.ims_touch();
alter table public.price_formula enable row level security;
create policy price_formula_select on public.price_formula for select to authenticated using (true);
revoke all on public.price_formula from public, anon, authenticated;
grant select on public.price_formula to authenticated;
comment on table public.price_formula is '⭐ 공급처 가격식(price-1 · 판정 216 · 217 · 222 · 223) — 공급처마다 이름 붙인 식 여럿 · 하나가 기본(is_default · 창구가 지킨다 · 부분 유니크 없음) · Wholesale = Latest cost × 환율(price_fx · currency_id) × freight × (1 + duty_pct/100) ÷ margin → 끝자리 올림(endings · price_round_up) → 티어(price_tier_rule) · 쓰기는 price_formula_save(admin)로만 · 꺼진 식은 기본이 될 수 없다 · 이름 unique 는 꺼진 것도 포함 · 되살리기 = on · source 는 manual 하나(IMS 가 만든 것뿐)';
comment on column public.price_formula.endings is '끝자리 체크(센트 · 판정 217) — {9, 19, …, 99} 의 부분집합 · 비지 않음 · 창구가 중복 없이 오름차순으로 넣는다 · 묶음 단추 .49 · .99 / .x9 all 은 화면';
comment on column public.price_formula.currency_id is 'Latest cost 의 통화(CAD 또는 USD · 창구 검사 · 원산지 통화 없음 — 판정 222) · 처음 값은 그 공급처의 통화 · 환율은 price_fx 에서 읽는다';

create table if not exists public.price_fx (
  currency_id   uuid primary key references public.ref_currency (id) on delete no action,
  rate          numeric(18,7) not null,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  constraint price_fx_rate_ck check (rate > 0)
);
create trigger price_fx_touch before update on public.price_fx for each row execute function public.ims_touch();
alter table public.price_fx enable row level security;
create policy price_fx_select on public.price_fx for select to authenticated using (true);
revoke all on public.price_fx from public, anon, authenticated;
grant select on public.price_fx to authenticated;
comment on table public.price_fx is '⭐ 환율 한 곳(price-1 · 묶음 2) — 통화 → CAD 곱수 · CAD 1(창구가 못 바꾼다 · fx_cad_fixed) · USD 1.4 · 환율이 바뀌면 식마다 안 고치고 여기 하나 · 대가: 공급처마다 다른 환율은 못 쓴다 · 쓰기는 price_fx_save(admin)로만';
insert into public.price_fx (currency_id, rate, note)
select c.id, case c.code when 'CAD' then 1 else 1.4 end, case c.code when 'CAD' then '기준 통화 — 늘 1' else 'USD → CAD 계획 환율(판정 222 · Caleb 1.4)' end
  from public.ref_currency c where c.code in ('CAD', 'USD')
on conflict (currency_id) do nothing;

create table if not exists public.price_tier_rule (
  tier_id       uuid primary key references public.ref_price_tier (id) on delete no action,
  op            text not null,
  factor        numeric(18,7) not null,
  note          text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  updated_by    uuid references public.ims_staff (id) on delete no action,
  constraint price_tier_rule_op_ck     check (op in ('mul', 'div')),
  constraint price_tier_rule_factor_ck check (factor > 0)
);
create trigger price_tier_rule_touch before update on public.price_tier_rule for each row execute function public.ims_touch();
alter table public.price_tier_rule enable row level security;
create policy price_tier_rule_select on public.price_tier_rule for select to authenticated using (true);
revoke all on public.price_tier_rule from public, anon, authenticated;
grant select on public.price_tier_rule to authenticated;
comment on table public.price_tier_rule is '⭐ 티어 규칙 — 모든 공급처에 한 벌(price-1 · 판정 219 · Settings) · 기준은 언제나 Wholesale(code 1 · 규칙 줄을 두지 않는다 · 식이 낸다) · 티어 = price_round_up(Wholesale ×|÷ factor, 식의 endings) · 규칙이 없는 sale 티어는 식이 채우지 않는다 · 쓰기는 price_tier_rule_save(admin)로만';
insert into public.price_tier_rule (tier_id, op, factor, note)
select t.id, x.op, x.factor, '판정 219 seed'
  from (values (2, 'mul', 1::numeric), (3, 'div', 0.6), (4, 'mul', 1.05), (7, 'div', 1.25)) as x(code, op, factor)
  join public.ref_price_tier t on t.code = x.code
on conflict (tier_id) do nothing;

-- ═══ ③ product_supplier.price_formula_id — 상품이 자기 식을 기억(묶음 3 · 판정 223) + 트리거 IM223 ══════════════════════════════
alter table public.product_supplier add column if not exists price_formula_id uuid references public.price_formula (id) on delete no action;
create index if not exists product_supplier_price_formula_idx on public.product_supplier (price_formula_id);
comment on column public.product_supplier.price_formula_id is '마지막으로 건 가격식(price-1 · 판정 223) · product_update price_set 이 formula 로 저장될 때 채운다 · 사람이 뒤에 가격을 고쳐도 남는다(「이 식을 쓴 상품」 거르기) · 다른 공급처의 식은 트리거 price_formula_supplier_lock(IM223)이 막는다 · 적재는 이 칸을 보내지 않는다';
create or replace function public.price_formula_supplier_lock() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if new.price_formula_id is not null and not exists (select 1 from public.price_formula f where f.id = new.price_formula_id and f.supplier_id = new.supplier_id) then
    raise exception using errcode = 'IM223', message = format('Price formula %s does not belong to this supplier line — nothing was saved', new.price_formula_id);
  end if;
  return new;
end;
$$;
revoke all on function public.price_formula_supplier_lock() from public, anon, authenticated;
create trigger product_supplier_formula_lock before insert or update of price_formula_id on public.product_supplier for each row execute function public.price_formula_supplier_lock();

-- ═══ ④ 끝자리 올림 — price_round_up (판정 217 · immutable · numeric 만) ════════════════════════════════════════════════════════
-- 정의: 센트 끝이 p_endings 에 드는 값 가운데 p_value 이상인 가장 작은 값 · p_value 가 이미 맞으면 그대로(5.49 → 5.49) · 0 이하 · null · 빈 endings 는 null
-- 후보 두 줄이면 충분하다(증명): 후보 c = n + e/100(n 정수). n ≤ floor(v) − 1 이면 c ≤ floor(v) − 0.01 < v 라 후보가 아니다 · n ≥ floor(v) + 2 이면 floor(v) + 1 + e/100 (> v) 이 더 작은 후보다 ⇒ 최소는 n ∈ {floor(v), floor(v) + 1}
create or replace function public.price_round_up(p_value numeric, p_endings smallint[]) returns numeric
  language sql immutable
  set search_path = public, pg_temp
as $$
  select case when p_value is null or p_value <= 0 or p_endings is null or cardinality(p_endings) = 0 then null
              else (select round(min(x.c), 2) from (select floor(p_value) + e / 100.0 as c from unnest(p_endings) as e
                                           union all
                                           select floor(p_value) + 1 + e / 100.0 from unnest(p_endings) as e) as x where x.c >= p_value) end;
$$;
revoke all on function public.price_round_up(numeric, smallint[]) from public, anon;
grant execute on function public.price_round_up(numeric, smallint[]) to authenticated;
comment on function public.price_round_up(numeric, smallint[]) is '⭐ 끝자리 올림(price-1 · 판정 217) — 끝이 p_endings 에 드는 값 중 p_value 이상인 가장 작은 값 · 이미 맞으면 그대로 · 5.491 → 5.99(.49 · .99) · 9.995 → 10.49 · 0 이하 · null 은 null · numeric 만(float 금지) · 후보는 floor(v) 와 floor(v)+1 두 줄(증명은 마이그레이션 주석)';

-- ─── 통째 식의 범위 검사(calc · save 가 같이 쓴다 · 첫 틀린 칸의 문장 하나 · 맞으면 null) ───
create or replace function public.price_formula_check(p jsonb) returns text
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_n int;
begin
  if coalesce(p->>'supplier_id', '') !~ '^[0-9a-fA-F-]{36}$' or not exists (select 1 from public.supplier s where s.id = (p->>'supplier_id')::uuid) then return 'The supplier does not exist'; end if;
  if coalesce(p->>'currency_id', '') !~ '^[0-9a-fA-F-]{36}$' or not exists (select 1 from public.ref_currency c where c.id = (p->>'currency_id')::uuid and c.code in ('CAD', 'USD')) then return 'The cost currency must be CAD or USD'; end if;
  if coalesce(p->>'freight', '') !~ '^[0-9]+(\.[0-9]+)?$' or (p->>'freight')::numeric <= 0 then return 'Freight and other costs must be a multiplier greater than 0 (1 = none)'; end if;
  if p ? 'duty_pct' and (coalesce(p->>'duty_pct', '') !~ '^[0-9]+(\.[0-9]+)?$' or (p->>'duty_pct')::numeric >= 100) then return 'Duty % must be 0 or more and below 100'; end if;
  if coalesce(p->>'margin', '') !~ '^[0-9]+(\.[0-9]+)?$' or (p->>'margin')::numeric <= 0 or (p->>'margin')::numeric > 1 then return 'Margin must be above 0 and at most 1 (0.65 = 35% GP)'; end if;
  if coalesce(jsonb_typeof(p->'endings'), 'none') <> 'array' or jsonb_array_length(p->'endings') = 0 then return 'Pick at least one price ending'; end if;
  select count(*) into v_n from jsonb_array_elements_text(p->'endings') as x where x !~ '^[0-9]{1,2}$' or not (x::int = any(array[9, 19, 29, 39, 49, 59, 69, 79, 89, 99]));
  if v_n > 0 then return 'Price endings must be .09, .19, … .99'; end if;
  return null;
end;
$$;
revoke all on function public.price_formula_check(jsonb) from public, anon;
grant execute on function public.price_formula_check(jsonb) to authenticated;
comment on function public.price_formula_check(jsonb) is '통째 식의 범위 검사(price-1) — supplier · currency(CAD|USD) · freight > 0 · duty_pct 0 ≤ d < 100 · margin 0 < m ≤ 1 · endings ⊆ {9 … 99} · 첫 틀린 칸의 문장 하나 · 맞으면 null · price_formula_calc 와 price_formula_save 가 같이 쓴다';

-- ═══ ⑤ 계산 — price_formula_calc (묶음 5 · 판정 222 · 219 · stable · 저장 없음) ═════════════════════════════════════════════════
-- p_formula = {"id": …}(저장된 식) 또는 통째 {supplier_id, currency_id, freight, duty_pct, margin, endings[]}(화면이 「이번만」 고친 값) — 둘 다 같은 범위 검사
-- 반환 {formula{id, name, supplier_id, currency_id, currency, freight, duty_pct, margin, endings}, cost, rate, landed, wholesale_raw, wholesale, gp_pct, tiers[{tier_id, code, name, price}], blocks[]}
--   식이 틀리면 formula null + blocks · 원가가 null 이거나 0 이하면 formula 는 주고 가격은 null + blocks [no_cost]
create or replace function public.price_formula_calc(p_formula jsonb, p_cost numeric) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_f       public.price_formula%rowtype;
  v_id      uuid;
  v_name    text;
  v_sup     uuid;
  v_cur     uuid;
  v_code    text;
  v_fr      numeric;
  v_duty    numeric;
  v_mg      numeric;
  v_end     smallint[];
  v_rate    numeric;
  v_landed  numeric;
  v_wraw    numeric;
  v_w       numeric;
  v_tiers   jsonb := '[]'::jsonb;
  v_r       record;
  v_fobj    jsonb;
  v_bad     text;
begin
  if p_formula is null or jsonb_typeof(p_formula) <> 'object' then
    return jsonb_build_object('formula', null, 'blocks', jsonb_build_array(jsonb_build_object('code', 'formula_invalid', 'message', 'A price formula is needed — pass {"id": …} or the full formula')));
  end if;
  if p_formula ? 'id' then
    if coalesce(p_formula->>'id', '') !~ '^[0-9a-fA-F-]{36}$' then
      return jsonb_build_object('formula', null, 'blocks', jsonb_build_array(jsonb_build_object('code', 'formula_unknown', 'message', 'That price formula does not exist')));
    end if;
    select * into v_f from public.price_formula f where f.id = (p_formula->>'id')::uuid;
    if v_f.id is null then
      return jsonb_build_object('formula', null, 'blocks', jsonb_build_array(jsonb_build_object('code', 'formula_unknown', 'message', 'That price formula does not exist')));
    end if;
    if not v_f.is_active then
      return jsonb_build_object('formula', null, 'blocks', jsonb_build_array(jsonb_build_object('code', 'formula_inactive', 'message', format('Price formula "%s" is inactive — turn it on or pick another', v_f.name))));
    end if;
    v_id := v_f.id; v_name := v_f.name; v_sup := v_f.supplier_id; v_cur := v_f.currency_id; v_fr := v_f.freight; v_duty := v_f.duty_pct; v_mg := v_f.margin; v_end := v_f.endings;
  else
    v_bad := public.price_formula_check(p_formula);
    if v_bad is not null then
      return jsonb_build_object('formula', null, 'blocks', jsonb_build_array(jsonb_build_object('code', 'formula_invalid', 'message', v_bad)));
    end if;
    v_sup := (p_formula->>'supplier_id')::uuid; v_cur := (p_formula->>'currency_id')::uuid; v_fr := (p_formula->>'freight')::numeric; v_duty := coalesce((p_formula->>'duty_pct')::numeric, 0); v_mg := (p_formula->>'margin')::numeric;
    select array_agg(distinct x::smallint order by x::smallint) into v_end from jsonb_array_elements_text(p_formula->'endings') as x;
    v_name := nullif(trim(coalesce(p_formula->>'name', '')), '');
  end if;
  select c.code into v_code from public.ref_currency c where c.id = v_cur;
  v_fobj := jsonb_build_object('id', v_id, 'name', v_name, 'supplier_id', v_sup, 'currency_id', v_cur, 'currency', v_code, 'freight', v_fr, 'duty_pct', v_duty, 'margin', v_mg, 'endings', to_jsonb(v_end));
  select x.rate into v_rate from public.price_fx x where x.currency_id = v_cur;
  if v_rate is null then
    return jsonb_build_object('formula', v_fobj, 'blocks', jsonb_build_array(jsonb_build_object('code', 'fx_missing', 'message', format('No exchange rate for %s — set it in Settings', coalesce(v_code, '?')))));
  end if;
  if p_cost is null or p_cost <= 0 then
    return jsonb_build_object('formula', v_fobj, 'cost', p_cost, 'rate', v_rate, 'landed', null, 'wholesale_raw', null, 'wholesale', null, 'gp_pct', null, 'tiers', '[]'::jsonb,
                              'blocks', jsonb_build_array(jsonb_build_object('code', 'no_cost', 'message', 'No cost — nothing to calculate from')));
  end if;
  v_landed := p_cost * v_rate * v_fr * (1 + v_duty / 100);
  v_wraw   := v_landed / v_mg;
  v_w      := public.price_round_up(v_wraw, v_end);
  for v_r in select t.id, t.code, t.name, r.op, r.factor
               from public.ref_price_tier t left join public.price_tier_rule r on r.tier_id = t.id
              where t.is_active and t.purpose = 'sale' and (t.code = 1 or r.tier_id is not null)
              order by t.code loop
    v_tiers := v_tiers || jsonb_build_object('tier_id', v_r.id, 'code', v_r.code, 'name', v_r.name,
                 'price', case when v_r.code = 1 then v_w else public.price_round_up(case v_r.op when 'mul' then v_w * v_r.factor else v_w / v_r.factor end, v_end) end);
  end loop;
  return jsonb_build_object('formula', v_fobj, 'cost', p_cost, 'rate', v_rate, 'landed', round(v_landed, 4), 'wholesale_raw', round(v_wraw, 4), 'wholesale', v_w,
                            'gp_pct', round((v_w - v_landed) / v_w * 100, 4), 'tiers', v_tiers, 'blocks', '[]'::jsonb);
end;
$$;
revoke all on function public.price_formula_calc(jsonb, numeric) from public, anon;
grant execute on function public.price_formula_calc(jsonb, numeric) to authenticated;
comment on function public.price_formula_calc(jsonb, numeric) is '⭐ 가격식 계산 한 곳(price-1 · 묶음 5 · 판정 222 · 219 · 217) — p_formula = {"id"} 또는 통째 식 · landed = cost × price_fx.rate × freight × (1 + duty_pct/100) · wholesale = price_round_up(landed ÷ margin, endings) · 티어 = price_round_up(wholesale ×|÷ price_tier_rule.factor, endings) · gp_pct = (wholesale − landed) ÷ wholesale × 100 · 저장 없음 · 반환 blocks: formula_invalid · formula_unknown · formula_inactive · fx_missing · no_cost(원가 null · 0 이하 — formula 는 준다) · landed · wholesale_raw · gp_pct 는 4 자리 · 가격은 센트 그대로';

-- ═══ ⑥ 미리 보기 — price_formula_preview (판정 220 · 222 · 묶음 1 ~ 5 · stable · 저장 없음 · 최대 1,000 SKU · 입력 순서 1:1) ════════
-- 줄 = {sku, product_id, is_set, cost, row_currency, formula_id_now, calc, current[{tier_id, code, price, source}], changes[{tier_id, code, old, new, pct}], flags[]}
-- flags: unknown_sku(없거나 꺼진 상품 · 다른 칸 null) · set_skipped(세트 — 식 안 건다) · no_supplier_link(그 공급처 줄 없음 · 꺼짐 — 이때 no_cost 는 안 붙는다) · no_cost(줄은 있는데 Latest 가 null · 0) · currency_differs(식 통화 ≠ 줄 통화 · 알리기만) · manual_price(source manual 티어가 있다 — 화면은 체크를 끄고 시작) · big_change(Wholesale 10% 넘게)
create or replace function public.price_formula_preview(p_formula jsonb, p_skus text[]) returns jsonb
  language plpgsql stable
  set search_path = public, pg_temp
as $$
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
$$;
revoke all on function public.price_formula_preview(jsonb, text[]) from public, anon;
grant execute on function public.price_formula_preview(jsonb, text[]) to authenticated;
comment on function public.price_formula_preview(jsonb, text[]) is '⭐ 가격식 미리 보기(price-1 · 판정 220 · 222) — 식(id 또는 통째) × SKU 목록(최대 1,000 · 입력 순서 1:1) → 줄마다 cost(그 식의 공급처 줄 Latest) · row_currency · formula_id_now · calc(price_formula_calc) · current(켜진 sale 티어 가격 · source) · changes(old · new · pct) · flags(unknown_sku · set_skipped · no_supplier_link · no_cost · currency_differs · manual_price · big_change) · 저장 없음 — 저장은 product_update price_set 의 formula 칸으로';

-- ═══ ⑦ 저장 창구 셋 — admin · 두 번 부르기(p_commit · p_ack · 막기 · 알리기 · product_update 모양) ═══════════════════════════════
-- price_formula_save(p_changes[], p_commit, p_ack) — 줄 = {op, …}
--   create  {supplier_id, name, currency_id?(없으면 공급처 통화), freight, duty_pct?, margin, endings[], is_default?, note?} — 공급처에 켜진 기본이 없으면 저절로 기본 · is_default true 면 옛 기본을 내린다
--   update  {id, set{name? currency_id? freight? duty_pct? margin? endings[]? note?}, old{같은 열쇠}} — 열쇠마다 old 필수 · 지금 값과 다르면 changed_elsewhere · 숫자 · 통화 · 끝자리를 바꾸면 그 식을 기억한 상품 수를 알린다(formula_in_use)
--   default {id} — 켜진 식만 · 같은 공급처의 옛 기본은 내린다 / off {id} — 기본이던 식이면 default_off 알리기(기본 없음) · formula_in_use 알리기 / on {id} — 켠다(공급처에 기본이 없으면 기본)
create or replace function public.price_formula_save(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
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
  v_f        public.price_formula%rowtype;
  v_sup      public.supplier%rowtype;
  v_full     jsonb;
  v_bad      text;
  v_name     text;
  v_seen     text[] := '{}';
  v_k        text;
  v_cur      text;
  v_new      text;
  v_oldt     text;
  v_in_use   bigint;
  v_numeric  boolean;
  v_end      smallint[];
  v_keys     text[];
  v_unacked  text[];
  v_id       uuid;
  v_defsup   text[] := '{}';                                                                  -- 이 호출에서 기본이 된 공급처(두 번째 create 가 또 기본이 되지 않게)
  v_isdef    boolean;
begin
  perform public.ims_require_admin('price formulas');                                           -- ⭐ 유일한 문 — 첫 줄(묶음 7)
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
    v_f := null; v_sup := null; v_full := null; v_numeric := false;
    if v_op not in ('create', 'update', 'default', 'off', 'on') then
      v_blocks := v_blocks || jsonb_build_object('key', v_i::text || ':op_unknown', 'code', 'op_unknown', 'message', format('Line %s: unknown op "%s" — create, update, default, off or on — nothing was saved', v_i, v_op));
      v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'id', null, 'applied', false);
      continue;
    end if;
    if v_op = 'create' then
      v_name := nullif(trim(coalesce(v_c->>'name', '')), '');
      v_key := coalesce(v_c->>'supplier_id', '?') || ':' || coalesce(v_name, '(none)');
      v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'id', null, 'applied', false);
      if coalesce(v_c->>'supplier_id', '') ~ '^[0-9a-fA-F-]{36}$' then
        select * into v_sup from public.supplier s where s.id = (v_c->>'supplier_id')::uuid and s.is_active;
      end if;
      if v_sup.id is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':supplier_unknown', 'code', 'supplier_unknown', 'message', format('Line %s: the supplier does not exist or is inactive — nothing was saved', v_i));
        continue;
      end if;
      if v_name is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'code', 'name_missing', 'message', format('Line %s: a formula needs a name — nothing was saved', v_i));
        continue;
      end if;
      if (v_sup.id::text || '|' || lower(v_name)) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Formula "%s" for %s appears twice in this call — nothing was saved', v_name, v_sup.name));
        continue;
      end if;
      v_seen := v_seen || (v_sup.id::text || '|' || lower(v_name));
      if exists (select 1 from public.price_formula f where f.supplier_id = v_sup.id and lower(f.name) = lower(v_name)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_duplicate', 'code', 'name_duplicate', 'message', format('%s already has a formula named "%s" (active or inactive) — pick another name — nothing was saved', v_sup.name, v_name));
        continue;
      end if;
      v_full := jsonb_build_object('supplier_id', v_sup.id, 'currency_id', coalesce(v_c->>'currency_id', v_sup.currency_id::text), 'freight', v_c->>'freight', 'duty_pct', coalesce(v_c->>'duty_pct', '0'), 'margin', v_c->>'margin', 'endings', coalesce(v_c->'endings', '[]'::jsonb));
      v_bad := public.price_formula_check(v_full);
      if v_bad is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_invalid', 'code', 'formula_invalid', 'message', format('Formula "%s": %s — nothing was saved', v_name, v_bad));
        continue;
      end if;
      v_isdef := coalesce((v_c->>'is_default')::boolean, false)
                 or (not (v_sup.id::text = any(v_defsup)) and not exists (select 1 from public.price_formula f where f.supplier_id = v_sup.id and f.is_active and f.is_default));
      if v_isdef then v_defsup := v_defsup || v_sup.id::text; end if;
      v_plan := v_plan || jsonb_build_object('i', v_i, 'op', v_op, 'full', v_full || jsonb_build_object('name', v_name, 'note', v_c->>'note', 'is_default', v_isdef));
      continue;
    end if;

    -- update · default · off · on — 있는 식
    v_key := coalesce(v_c->>'id', '?');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'op', v_op, 'id', v_c->>'id', 'applied', false);
    if coalesce(v_c->>'id', '') ~ '^[0-9a-fA-F-]{36}$' then
      select * into v_f from public.price_formula f where f.id = (v_c->>'id')::uuid;
    end if;
    if v_f.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_unknown', 'code', 'formula_unknown', 'message', format('Line %s: that price formula does not exist — nothing was saved', v_i));
      continue;
    end if;
    if (v_f.id::text || '|op') = any(v_seen) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('Formula "%s" is changed twice in this call — nothing was saved', v_f.name));
      continue;
    end if;
    v_seen := v_seen || (v_f.id::text || '|op');
    select count(*) into v_in_use from public.product_supplier ps where ps.price_formula_id = v_f.id;
    if v_op = 'default' and not v_f.is_active then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_inactive', 'code', 'formula_inactive', 'message', format('Formula "%s" is inactive and cannot be the default — turn it on first — nothing was saved', v_f.name));
      continue;
    end if;
    if v_op = 'off' then
      if v_f.is_default and v_f.is_active then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':default_off', 'code', 'default_off', 'message', format('"%s" is the default formula of its supplier — after this the supplier has no default', v_f.name));
      end if;
      if v_in_use > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':formula_in_use:' || v_in_use, 'code', 'formula_in_use', 'message', format('%s product line%s remember "%s" as their last formula — they keep pointing at it', v_in_use, case when v_in_use = 1 then '' else 's' end, v_f.name));
      end if;
    end if;
    if v_op = 'update' then
      if coalesce(jsonb_typeof(v_c->'set'), 'none') <> 'object' or (select count(*) from jsonb_object_keys(v_c->'set')) = 0 then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_invalid', 'code', 'formula_invalid', 'message', format('Formula "%s": update needs a "set" object with at least one field — nothing was saved', v_f.name));
        continue;
      end if;
      v_bad := null;
      for v_k in select k from jsonb_object_keys(v_c->'set') as k loop
        if v_k not in ('name', 'currency_id', 'freight', 'duty_pct', 'margin', 'endings', 'note') then
          v_bad := format('"%s" is not a field this window changes', v_k); exit;
        end if;
        if coalesce(jsonb_typeof(v_c->'old'), 'none') <> 'object' or not (v_c->'old' ? v_k) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_k, 'code', 'old_missing', 'message', format('Formula "%s" %s: the old value the screen saw is missing — nothing was saved', v_f.name, v_k));
          v_bad := ''; exit;
        end if;
        v_cur := case v_k when 'name' then v_f.name when 'currency_id' then v_f.currency_id::text when 'freight' then v_f.freight::text when 'duty_pct' then v_f.duty_pct::text
                          when 'margin' then v_f.margin::text when 'note' then v_f.note else (select string_agg(e::text, ',' order by e) from unnest(v_f.endings) e) end;
        v_oldt := case when v_k = 'endings' then (select string_agg(e::text, ',' order by e::int) from jsonb_array_elements_text(case when jsonb_typeof(v_c->'old'->'endings') = 'array' then v_c->'old'->'endings' else '[]'::jsonb end) e)
                       else nullif(v_c->'old'->>v_k, '') end;
        if v_k in ('freight', 'duty_pct', 'margin') and v_cur is not null and v_oldt ~ '^[0-9]+(\.[0-9]+)?$' and v_cur::numeric = v_oldt::numeric then
          null;
        elsif v_cur is distinct from v_oldt then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_k, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of formula "%s" (now "%s") — check again — nothing was saved', v_k, v_f.name, coalesce(v_cur, '')));
          v_bad := ''; exit;
        end if;
        if v_k in ('currency_id', 'freight', 'duty_pct', 'margin', 'endings') then v_numeric := true; end if;
      end loop;
      if v_bad = '' then continue; end if;
      if v_bad is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_invalid', 'code', 'formula_invalid', 'message', format('Formula "%s": %s — nothing was saved', v_f.name, v_bad));
        continue;
      end if;
      v_name := coalesce(nullif(trim(coalesce(v_c->'set'->>'name', '')), ''), v_f.name);
      if v_c->'set' ? 'name' and nullif(trim(coalesce(v_c->'set'->>'name', '')), '') is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'code', 'name_missing', 'message', format('Formula "%s": the name cannot be empty — nothing was saved', v_f.name));
        continue;
      end if;
      if exists (select 1 from public.price_formula f where f.supplier_id = v_f.supplier_id and f.id <> v_f.id and lower(f.name) = lower(v_name)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_duplicate', 'code', 'name_duplicate', 'message', format('This supplier already has a formula named "%s" (active or inactive) — nothing was saved', v_name));
        continue;
      end if;
      v_full := jsonb_build_object('supplier_id', v_f.supplier_id, 'currency_id', coalesce(v_c->'set'->>'currency_id', v_f.currency_id::text), 'freight', coalesce(v_c->'set'->>'freight', v_f.freight::text),
                                   'duty_pct', coalesce(v_c->'set'->>'duty_pct', v_f.duty_pct::text), 'margin', coalesce(v_c->'set'->>'margin', v_f.margin::text),
                                   'endings', case when v_c->'set' ? 'endings' then v_c->'set'->'endings' else to_jsonb(v_f.endings) end);
      v_bad := public.price_formula_check(v_full);
      if v_bad is not null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':formula_invalid', 'code', 'formula_invalid', 'message', format('Formula "%s": %s — nothing was saved', v_f.name, v_bad));
        continue;
      end if;
      if v_numeric and v_in_use > 0 then
        v_warns := v_warns || jsonb_build_object('key', v_key || ':formula_in_use:' || v_in_use, 'code', 'formula_in_use', 'message', format('%s product line%s remember "%s" — their prices stay as they are until the formula is applied again', v_in_use, case when v_in_use = 1 then '' else 's' end, v_f.name));
      end if;
      v_plan := v_plan || jsonb_build_object('i', v_i, 'op', v_op, 'id', v_f.id, 'full', v_full || jsonb_build_object('name', v_name, 'note', case when v_c->'set' ? 'note' then v_c->'set'->>'note' else v_f.note end));
      continue;
    end if;
    v_plan := v_plan || jsonb_build_object('i', v_i, 'op', v_op, 'id', v_f.id, 'supplier_id', v_f.supplier_id);
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
      select array_agg(distinct x::smallint order by x::smallint) into v_end from jsonb_array_elements_text(v_c->'full'->'endings') as x;
      if (v_c->'full'->>'is_default')::boolean then
        update public.price_formula set is_default = false where supplier_id = (v_c->'full'->>'supplier_id')::uuid and is_default;
      end if;
      insert into public.price_formula (supplier_id, name, is_default, currency_id, freight, duty_pct, margin, endings, note, updated_by)
      values ((v_c->'full'->>'supplier_id')::uuid, v_c->'full'->>'name', (v_c->'full'->>'is_default')::boolean, (v_c->'full'->>'currency_id')::uuid, (v_c->'full'->>'freight')::numeric,
              (v_c->'full'->>'duty_pct')::numeric, (v_c->'full'->>'margin')::numeric, v_end, nullif(v_c->'full'->>'note', ''), v_staff)
      returning id into v_id;
      v_changes := jsonb_set(jsonb_set(v_changes, array[((v_c->>'i')::int - 1)::text, 'applied'], 'true'::jsonb), array[((v_c->>'i')::int - 1)::text, 'id'], to_jsonb(v_id::text));
      continue;
    end if;
    v_id := (v_c->>'id')::uuid;
    if v_op = 'update' then
      select array_agg(distinct x::smallint order by x::smallint) into v_end from jsonb_array_elements_text(v_c->'full'->'endings') as x;
      update public.price_formula set name = v_c->'full'->>'name', currency_id = (v_c->'full'->>'currency_id')::uuid, freight = (v_c->'full'->>'freight')::numeric, duty_pct = (v_c->'full'->>'duty_pct')::numeric,
             margin = (v_c->'full'->>'margin')::numeric, endings = v_end, note = nullif(v_c->'full'->>'note', '') where id = v_id;
    elsif v_op = 'default' then
      update public.price_formula set is_default = (id = v_id) where supplier_id = (v_c->>'supplier_id')::uuid and (is_default or id = v_id);
    elsif v_op = 'off' then
      update public.price_formula set is_active = false, is_default = false where id = v_id;
    elsif v_op = 'on' then
      update public.price_formula set is_active = true, is_default = not exists (select 1 from public.price_formula f where f.supplier_id = (v_c->>'supplier_id')::uuid and f.is_active and f.is_default) where id = v_id;
    end if;
    v_changes := jsonb_set(v_changes, array[((v_c->>'i')::int - 1)::text, 'applied'], 'true'::jsonb);
  end loop;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.price_formula_save(jsonb, boolean, text[]) from public, anon;
grant execute on function public.price_formula_save(jsonb, boolean, text[]) to authenticated;
comment on function public.price_formula_save(jsonb, boolean, text[]) is '⭐ 공급처 가격식 저장 창구(price-1 · 판정 223 · 묶음 7) — security definer · 첫 줄 ims_require_admin · p_changes = 줄 목록(최대 200) · op 다섯: create {supplier_id, name, currency_id?, freight, duty_pct?, margin, endings[], is_default?, note?} · update {id, set{…}, old{…}} · default {id} · off {id} · on {id} · 검사만(p_commit false) → 저장(p_commit true + p_ack) · 막기 하나면 아무것도 안 바뀐다 · 막기: op_unknown · supplier_unknown · name_missing · name_duplicate(대소문자 · 공백 접어 · 꺼진 것 포함) · field_duplicate_in_call · formula_invalid · formula_unknown · formula_inactive · old_missing · changed_elsewhere · 알리기: default_off · formula_in_use(N) · 공급처에 켜진 기본이 없으면 create · on 이 기본이 된다';

-- price_fx_save(p_changes[], p_commit, p_ack) — 줄 = {currency_id, rate, old} · CAD 는 못 바꾼다(fx_cad_fixed) · 10% 넘게 바꾸면 알리기 fx_big_change
create or replace function public.price_fx_save(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_i        int := 0;
  v_c        jsonb;
  v_key      text;
  v_code     text;
  v_rate     numeric;
  v_seen     text[] := '{}';
  v_keys     text[];
  v_unacked  text[];
begin
  perform public.ims_require_admin('exchange rates');                                            -- ⭐ 유일한 문 — 첫 줄(묶음 7)
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_key := coalesce(v_c->>'currency_id', '?');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'currency_id', v_c->>'currency_id', 'applied', false);
    v_code := null; v_rate := null;
    if coalesce(v_c->>'currency_id', '') ~ '^[0-9a-fA-F-]{36}$' then
      select c.code, x.rate into v_code, v_rate from public.ref_currency c join public.price_fx x on x.currency_id = c.id where c.id = (v_c->>'currency_id')::uuid;
    end if;
    if v_code is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_unknown', 'code', 'currency_unknown', 'message', format('Line %s: that currency has no exchange rate row — nothing was saved', v_i));
      continue;
    end if;
    if v_code = 'CAD' then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':fx_cad_fixed', 'code', 'fx_cad_fixed', 'message', 'CAD is the base currency — its rate is always 1 — nothing was saved');
      continue;
    end if;
    if v_key = any(v_seen) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('%s appears twice in this call — nothing was saved', v_code));
      continue;
    end if;
    v_seen := v_seen || v_key;
    if coalesce(v_c->>'rate', '') !~ '^[0-9]+(\.[0-9]+)?$' or (v_c->>'rate')::numeric <= 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':rate_not_positive', 'code', 'rate_not_positive', 'message', format('%s: the rate must be greater than 0 — nothing was saved', v_code));
      continue;
    end if;
    if not (v_c ? 'old') then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('%s: the old rate the screen saw is missing — nothing was saved', v_code));
      continue;
    end if;
    if coalesce(v_c->>'old', '') !~ '^[0-9]+(\.[0-9]+)?$' or v_rate <> (v_c->>'old')::numeric then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed the %s rate (now %s) — check again — nothing was saved', v_code, v_rate));
      continue;
    end if;
    if abs((v_c->>'rate')::numeric - v_rate) / v_rate > 0.10 then
      v_warns := v_warns || jsonb_build_object('key', v_key || ':fx_big_change', 'code', 'fx_big_change', 'message', format('%s rate changes by more than 10%% (%s → %s) — every new price from a %s formula moves with it', v_code, v_rate, (v_c->>'rate')::numeric, v_code));
    end if;
  end loop;
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    update public.price_fx set rate = (v_c->>'rate')::numeric where currency_id = (v_c->>'currency_id')::uuid;
    v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
  end loop;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.price_fx_save(jsonb, boolean, text[]) from public, anon;
grant execute on function public.price_fx_save(jsonb, boolean, text[]) to authenticated;
comment on function public.price_fx_save(jsonb, boolean, text[]) is '⭐ 환율 저장 창구(price-1 · 묶음 2 · 7) — definer · 첫 줄 ims_require_admin · 줄 = {currency_id, rate, old} · CAD 는 못 바꾼다 · 막기: currency_unknown · fx_cad_fixed · field_duplicate_in_call · rate_not_positive · old_missing · changed_elsewhere · 알리기: fx_big_change(10% 넘게) · 두 번 부르기(p_commit · p_ack)';

-- price_tier_rule_save(p_changes[], p_commit, p_ack) — 줄 = {tier_id, op, factor, old{op, factor} | null(새 규칙)} · Wholesale(code 1)은 막기 · sale 티어만 · 없는 규칙은 새로(old 없이)
create or replace function public.price_tier_rule_save(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}') returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_blocks   jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_i        int := 0;
  v_c        jsonb;
  v_key      text;
  v_t        public.ref_price_tier%rowtype;
  v_r        public.price_tier_rule%rowtype;
  v_seen     text[] := '{}';
begin
  perform public.ims_require_admin('price tier rules');                                          -- ⭐ 유일한 문 — 첫 줄(묶음 7)
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' or jsonb_array_length(p_changes) = 0 then
    raise exception 'p_changes must be a JSON array of changes — nothing was saved';
  end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_key := coalesce(v_c->>'tier_id', '?');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'tier_id', v_c->>'tier_id', 'applied', false);
    v_t := null; v_r := null;
    if coalesce(v_c->>'tier_id', '') ~ '^[0-9a-fA-F-]{36}$' then
      select * into v_t from public.ref_price_tier t where t.id = (v_c->>'tier_id')::uuid and t.is_active and t.purpose = 'sale';
    end if;
    if v_t.id is null then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_invalid', 'code', 'tier_invalid', 'message', format('Line %s: the tier is missing, inactive or not a sale tier — nothing was saved', v_i));
      continue;
    end if;
    if v_t.code = 1 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_rule_wholesale', 'code', 'tier_rule_wholesale', 'message', 'Wholesale is the base tier — the supplier formula sets it, it has no rule — nothing was saved');
      continue;
    end if;
    if v_key = any(v_seen) then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call', 'code', 'field_duplicate_in_call', 'message', format('%s appears twice in this call — nothing was saved', v_t.name));
      continue;
    end if;
    v_seen := v_seen || v_key;
    if coalesce(v_c->>'op', '') not in ('mul', 'div') then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':op_invalid', 'code', 'op_invalid', 'message', format('%s: op must be mul (×) or div (÷) — nothing was saved', v_t.name));
      continue;
    end if;
    if coalesce(v_c->>'factor', '') !~ '^[0-9]+(\.[0-9]+)?$' or (v_c->>'factor')::numeric <= 0 then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':factor_not_positive', 'code', 'factor_not_positive', 'message', format('%s: the factor must be greater than 0 — nothing was saved', v_t.name));
      continue;
    end if;
    select * into v_r from public.price_tier_rule r where r.tier_id = v_t.id;
    if v_r.tier_id is not null then
      if coalesce(jsonb_typeof(v_c->'old'), 'none') <> 'object' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing', 'code', 'old_missing', 'message', format('%s: the old rule the screen saw is missing — nothing was saved', v_t.name));
        continue;
      end if;
      if v_c->'old'->>'op' is distinct from v_r.op or coalesce(v_c->'old'->>'factor', '') !~ '^[0-9]+(\.[0-9]+)?$' or (v_c->'old'->>'factor')::numeric <> v_r.factor then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere', 'code', 'changed_elsewhere', 'message', format('Someone just changed the %s rule (now %s %s) — check again — nothing was saved', v_t.name, case v_r.op when 'mul' then '×' else '÷' end, v_r.factor));
        continue;
      end if;
    end if;
  end loop;
  if jsonb_array_length(v_blocks) > 0 or not p_commit then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', '[]'::jsonb, 'unacked', '[]'::jsonb);
  end if;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    insert into public.price_tier_rule (tier_id, op, factor) values ((v_c->>'tier_id')::uuid, v_c->>'op', (v_c->>'factor')::numeric)
    on conflict (tier_id) do update set op = excluded.op, factor = excluded.factor;
    v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
  end loop;
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', '[]'::jsonb, 'unacked', '[]'::jsonb);
end;
$$;
revoke all on function public.price_tier_rule_save(jsonb, boolean, text[]) from public, anon;
grant execute on function public.price_tier_rule_save(jsonb, boolean, text[]) to authenticated;
comment on function public.price_tier_rule_save(jsonb, boolean, text[]) is '⭐ 티어 규칙 저장 창구(price-1 · 판정 219 · 묶음 7) — definer · 첫 줄 ims_require_admin · 줄 = {tier_id, op mul|div, factor, old{op, factor}}(규칙이 없던 sale 티어는 old 없이 새로) · 막기: tier_invalid · tier_rule_wholesale · field_duplicate_in_call · op_invalid · factor_not_positive · old_missing · changed_elsewhere · 알리기 없음 · 두 번 부르기(p_commit · p_ack)';
-- ═══ ⑧ product_update 재발행 — 20261001152712 본문 바이트 그대로 + price_set 의 formula 칸(선언 여섯 줄 · 검사 블록 · 저장 블록 · comment) ═══════════════
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
                                         'image_add', 'image_off', 'image_primary', 'image_order') then                                                                        -- img-1 넷
      raise exception 'Unknown op "%" — set, family_join, family_leave, family_option, family_head_set, barcode_add, barcode_off, barcode_primary, price_set, price_off, supplier_set, supplier_default, supplier_off, image_add, image_off, image_primary or image_order — nothing was saved', coalesce(v_c->>'op', '(none)');
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
  '⭐ 상품 고치기 창구(판정 187 ~ 194 · 222 · 223 · 2026-10-01 prod-4a + 4b + img-1 + price-1) — security definer · 첫 줄 ims_require_write(master). p_changes = 바꿀 것 목록(최대 1,000 줄) · 줄 = {sku, op, …, old} · op 열일곱: set(칸 하나 — name · brand_id · category_id · unit_id · weight · weight_unit · note · is_discontinued · set_discount_pct · sku · is_active · pack_factor · parent_sku) · family_join {sku, family_sku, options[]} · family_leave {sku, old} · family_option {sku, options[], old[]} · family_head_set {family_sku, field, value, old} · barcode_add/barcode_off/barcode_primary {sku, barcode} · price_set {sku, tier_id, price, old?, formula?(price-1 — {"id"} 또는 통째 식 · 창구가 그 식의 공급처 줄의 지금 Latest 로 다시 계산해 그 티어 값과 같을 때만 source formula + product_supplier.price_formula_id · 다르면 manual + 알리기 formula_mismatch · 통째 식은 id 가 없어 알리기 formula_unsaved · 세트에 formula 는 막기 formula_on_set · 식이 틀리면 막기 formula_invalid)} · price_off {sku, tier_id, old} · supplier_set {sku, supplier_id, supplier_sku?, cost?, fixed_cost?, currency_id?, old{}?} · supplier_default/supplier_off {sku, supplier_id} · image_add {sku, storage_path, content_type, byte_size?, width?, height?, file_name?, primary?} · image_off/image_primary {sku, image_id} · image_order {sku, image_ids[]}. old = 화면이 본 옛 값 — 다르면 changed_elsewhere. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 저장 직전 재검사(판정 176) · 막기 하나면 아무것도 안 바뀐다 · 줄 순서대로 · 이 호출의 다른 줄은 화면이 본 옛 SKU 로 가리킨다. 바코드 · 판매가 · 공급처 · 사진 빼기는 끄기(is_active false · 판정 188 · 사진 파일은 저장소에 남는다) · IMS 가 손댄 줄은 source manual(판정 133). family 머리의 브랜드 · 분류 · 단위는 옛 값과 같던 변형이 따라간다(판정 191 · 192 · variants_follow). SKU 를 바꾸면 세트 SKU 도(판정 189) · 세트 계수 · 부모는 사건 없을 때만(판정 137 ① · product_has_events) · is_active 끄기는 재고 · 열린 SO · PO 줄 · 켜진 세트 수를 알린다(판정 139). 사진은 화면이 product-images 상자의 <product id>/… 에 먼저 올리고 image_add 로 등록(저장소에 없으면 image_object_missing). code 목록은 20261001143142 · 20261001145316 · 20261001152712 · 이 파일(price-1)의 머리';


-- ═══ ⑨ 사실 확인 — 어긋나면 되돌린다(한 트랜잭션 · -1) ══════════════════════════════════════════════════════════════════════════
do $$
declare
  v_tables int; v_funcs int; v_pol int; v_trg int; v_fx int; v_rules int; v_col int; v_body boolean;
begin
  select count(*) into v_tables from information_schema.tables where table_schema = 'public' and table_name in ('price_formula', 'price_fx', 'price_tier_rule');
  select count(*) into v_funcs from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public'
    and p.proname in ('ims_require_admin', 'price_formula_supplier_lock', 'price_round_up', 'price_formula_check', 'price_formula_calc', 'price_formula_preview', 'price_formula_save', 'price_fx_save', 'price_tier_rule_save');
  select count(*) into v_pol from pg_policies where schemaname = 'public' and policyname in ('price_formula_select', 'price_fx_select', 'price_tier_rule_select');
  select count(*) into v_trg from pg_trigger where not tgisinternal and tgname in ('price_formula_touch', 'price_fx_touch', 'price_tier_rule_touch', 'product_supplier_formula_lock');
  select count(*) into v_fx from public.price_fx x join public.ref_currency c on c.id = x.currency_id where c.code in ('CAD', 'USD');
  select count(*) into v_rules from public.price_tier_rule r join public.ref_price_tier t on t.id = r.tier_id where t.code in (2, 3, 4, 7);
  select count(*) into v_col from information_schema.columns where table_schema = 'public' and table_name = 'product_supplier' and column_name = 'price_formula_id';
  select p.prosrc like '%formula_mismatch%' and p.prosrc like '%formula_on_set%' into v_body from pg_proc p where p.oid = to_regprocedure('public.product_update(jsonb,boolean,text[])');
  if v_tables <> 3 or v_funcs <> 9 or v_pol <> 3 or v_trg <> 4 or v_fx <> 2 or v_rules <> 4 or v_col <> 1 or not coalesce(v_body, false) then
    raise exception 'price-1 sanity failed — tables % (3) · functions % (9) · policies % (3) · triggers % (4) · fx rows % (2) · tier rules % (4) · column % (1) · product_update body % — nothing was applied',
      v_tables, v_funcs, v_pol, v_trg, v_fx, v_rules, v_col, coalesce(v_body, false);
  end if;
end $$;
