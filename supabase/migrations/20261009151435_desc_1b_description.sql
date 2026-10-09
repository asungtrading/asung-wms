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

-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════
-- desc-1b — 상품 설명 칸(판정 381 · 401 · 402 · 2026-10-09)
--   ① product · product_family 에 description_html · description_edited_at · description_edited_by + 짝 CHECK
--      ⭐ null = Cin7 원문(cin7_description)을 따른다 · 실제 값 = coalesce(description_html, cin7_description) · '' = 일부러 비움 · 복사 · 백필 없음(desc-1 이견 2)
--   ② 설정 표 ref_embed_host — 허락 iframe host 한 줄씩(판정 402 · 쓰기 창구 없음 · Caleb 의 SQL 로 더하고 뺀다 · ref_region_alias 선례)
--   ③ 판별 함수 ims_html_forbidden(html) — 고쳐 쓰지 않고 걸린 코드 목록만 · 거르기는 화면(DOMPurify)
--   ④ 문지기 product_description_guard — 창구(ims.description_door = '1')가 아닌 쓰기는 설명 칸 셋을 되돌린다(적재가 어떻게 보내든 IMS 설명이 안 지워진다 · raise 아님)
--   ⑤ product_update 재발행 — op 둘 description_set · description_follow_cin7(sku | family_sku · old · blocks)
--   ⑥ 뷰 둘 product_description(화면 · Shopify 보내기는 이것만) · product_description_edited(솎아내기)
--   적용: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f <이 파일> && supabase migration repair --status applied <버전> --db-url "$(cat ~/.asung-testdb-url)"
-- ═══════════════════════════════════════════════════════════════════════════════════════════════════════════════

-- ═══ 1) 칸 셋 × 2 + 짝 CHECK ═══
alter table public.product
  add column if not exists description_edited_at timestamptz,
  add column if not exists description_edited_by uuid references public.ims_staff (id) on delete no action,
  add column if not exists description_html      text;
create index if not exists product_description_edited_by_idx on public.product (description_edited_by);
alter table public.product add constraint product_description_pair_ck
  check ((description_html is null) = (description_edited_at is null) and (description_edited_at is null) = (description_edited_by is null));
comment on column public.product.description_html is
  'desc-1b 판정 381 · 401: IMS 의 상품 설명(HTML) · ⭐ null = Cin7 원문 cin7_description 을 따른다(실제 값은 coalesce(description_html, cin7_description) — 뷰 product_description 이 그것) · '''' = 일부러 비움 · 쓰기는 product_update op description_set · description_follow_cin7 만(문지기 product_description_guard) · 저장은 원문 그대로(거르기는 화면 · 판정 402 거름은 ims_html_forbidden 이 창구에서 막는다)';
comment on column public.product.description_edited_at is 'desc-1b 판정 401: IMS 에서 설명을 고친 시각 · null = 안 고쳤다(Cin7 을 따른다) · 셋이 함께 null 이거나 함께 채워진다(product_description_pair_ck)';
comment on column public.product.description_edited_by is 'desc-1b 판정 401: IMS 에서 설명을 고친 사람 → ims_staff(id) · product_update 의 v_staff';

alter table public.product_family
  add column if not exists description_edited_at timestamptz,
  add column if not exists description_edited_by uuid references public.ims_staff (id) on delete no action,
  add column if not exists description_html      text;
create index if not exists product_family_description_edited_by_idx on public.product_family (description_edited_by);
alter table public.product_family add constraint product_family_description_pair_ck
  check ((description_html is null) = (description_edited_at is null) and (description_edited_at is null) = (description_edited_by is null));
comment on column public.product_family.description_html is
  'desc-1b 판정 381 · 401: family 의 설명(HTML) · ⭐ null = Cin7 원문 cin7_description 을 따른다(실제 값은 coalesce — 뷰 product_description) · '''' = 일부러 비움 · 쓰기는 product_update op description_set · description_follow_cin7(family_sku) 만(문지기 product_family_description_guard)';
comment on column public.product_family.description_edited_at is 'desc-1b 판정 401: IMS 에서 설명을 고친 시각 · null = 안 고쳤다 · 셋이 함께 null 이거나 함께 채워진다(product_family_description_pair_ck)';
comment on column public.product_family.description_edited_by is 'desc-1b 판정 401: IMS 에서 설명을 고친 사람 → ims_staff(id)';

-- ═══ 2) 설정 표 ref_embed_host — 허락 출처 한 줄씩(판정 402) · 쓰기 창구 없음(Caleb 의 SQL · ref_region_alias 선례) ═══
create table public.ref_embed_host (
  id          uuid primary key default gen_random_uuid(),
  kind        text not null,                                   -- iframe · img(img 는 「모든 출처」라 지금은 행 없음 · 나중을 위한 자리)
  host        text not null,                                   -- ⭐ lower(trim(원문)) · 정확 일치(접미사 아님)
  is_active   boolean not null default true,
  note        text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff (id) on delete no action,
  constraint ref_embed_host_kind_ck check (kind in ('iframe', 'img')),
  constraint ref_embed_host_host_ck check (host <> '' and host = lower(btrim(host))),
  constraint ref_embed_host_kind_host_uk unique (kind, host)
);
create index ref_embed_host_updated_by_idx on public.ref_embed_host (updated_by);
create trigger ref_embed_host_touch before update on public.ref_embed_host for each row execute function public.ims_touch();
alter table public.ref_embed_host enable row level security;
create policy ref_embed_host_select on public.ref_embed_host for select to authenticated using (true);
revoke all on public.ref_embed_host from anon;
revoke insert, update, delete, truncate on public.ref_embed_host from authenticated;
comment on table public.ref_embed_host is
  'desc-1b 판정 402: 설명 HTML 에 허락하는 삽입 출처 — 한 줄 = (kind, host) · host 는 lower · 정확 일치 · ims_html_forbidden 이 iframe src 의 host 를 여기와 대조한다 · 화면(DOMPurify)도 같은 표를 읽는다 · 쓰기 창구 없음 — 더하고 빼는 것은 SQL 한 줄(insert · is_active=false) · 2026-10-09 시작값 iframe 다섯(실측 www.youtube.com 156/9 · www.facebook.com 10/1 · www.powr.io 227/12 는 허락 안 함)';
insert into public.ref_embed_host (kind, host, note) values
  ('iframe', 'www.youtube.com',          '판정 402 · 실측 상품 156 / family 9'),
  ('iframe', 'youtube.com',              '판정 402'),
  ('iframe', 'www.youtube-nocookie.com', '판정 402'),
  ('iframe', 'www.facebook.com',         '판정 402 · 실측 상품 10 / family 1'),
  ('iframe', 'facebook.com',             '판정 402');

-- ═══ 3) 판별 함수 — 고쳐 쓰지 않는다 · 걸린 코드 목록만(없으면 빈 배열) ═══
create function public.ims_html_forbidden(p_html text) returns text[]
  language plpgsql stable
  set search_path = public, pg_temp
as $$
declare
  v_codes text[] := '{}';
  v_tag   text;
  v_m     text[];
  v_host  text;
begin
  if p_html is null or p_html = '' then return '{}'::text[]; end if;
  if p_html ~* '<script[[:space:]>/]'                   then v_codes := array_append(v_codes, 'script');          end if;
  if p_html ~* '<[^>]*[[:space:]]on[a-z]+[[:space:]]*='  then v_codes := array_append(v_codes, 'event_attr');      end if;   -- 태그 안의 on…=
  if p_html ~* '=[[:space:]]*["'']?[[:space:]]*javascript[[:space:]]*:' then v_codes := array_append(v_codes, 'javascript_link'); end if;   -- 속성 값의 javascript:
  foreach v_tag in array array['object', 'embed', 'form', 'meta', 'link', 'base'] loop                                             -- desc-1 이견 3(판정 402 의 뜻 안)
    if p_html ~* ('<' || v_tag || '[[:space:]>/]') then v_codes := array_append(v_codes, v_tag); end if;
  end loop;
  for v_m in select regexp_matches(p_html, '<iframe([[:space:]][^>]*)?>', 'gi') loop                                                 -- iframe 마다 src 의 host
    v_host := lower((regexp_match(coalesce(v_m[1], ''), 'src[[:space:]]*=[[:space:]]*["'']?[[:space:]]*(?:https?:)?//([^/"''>[:space:]?#]+)', 'i'))[1]);
    if v_host is null then
      v_codes := array_append(v_codes, 'iframe_no_src');
    elsif not exists (select 1 from public.ref_embed_host h where h.kind = 'iframe' and h.is_active and h.host = v_host) then
      v_codes := array_append(v_codes, 'iframe_host:' || v_host);
    end if;
  end loop;
  select coalesce(array_agg(distinct c order by c), '{}'::text[]) into v_codes from unnest(v_codes) as c;
  return v_codes;
end;
$$;
grant execute on function public.ims_html_forbidden(text) to authenticated;
comment on function public.ims_html_forbidden(text) is
  'desc-1b 판정 402: 설명 HTML 에 거름 대상이 들어 있으면 코드 목록(정렬 · 중복 없음)을 돌려준다 — script · event_attr(태그 안 on…=) · javascript_link · object · embed · form · meta · link · base · iframe_no_src · iframe_host:<host>(ref_embed_host kind iframe 켜진 행에 없는 host · lower 정확 일치) · 빈 배열 = 통과 · ⚠️ 판별만 한다 — HTML 을 고쳐 쓰지 않는다(거르기는 화면 DOMPurify) · 대소문자 무시 · 엔티티 인코딩(&lt;script&gt; 류) · 속성 값 안의 > 같은 우회는 잡지 않는다(받아들임 — 쓰는 사람은 master 직원이고 화면이 다시 거른다) · stable · authenticated 실행권(화면 미리 보기)';

-- ═══ 4) 문지기 — 창구가 아닌 쓰기는 설명 칸 셋을 되돌린다(raise 아님 · 적재를 깨지 않는다) ═══
--   ⭐ 적재(service_role · ImsLoadProduct.gs merge-duplicates)가 새 칸을 어떻게 보내든(안 보냄 · null · 값) IMS 설명이 지워지지 않는다 — 「payload 밖 칸 비움」 추정을 확정하지 않은 채 막는다(desc-1 이견 1 · SQL 1 은 0 행)
--   BEFORE ROW 트리거는 이름순 — product_description_guard < product_sellable_default < product_sku_lock < product_touch · 문지기가 먼저 되돌리고 그 뒤 touch 가 updated_at 을 찍는다(설명 칸이 되돌아가도 다른 칸이 바뀌었으면 touch 는 지금처럼 찍는다)
--   product_deal_hit_changed(AFTER UPDATE · statement · transition table)는 BEFORE 트리거가 끝난 행을 본다 — 설명 칸은 그 판정(brand · category · parent)에 안 들어 무관
--   INSERT: 셋을 null 로(새 행은 Cin7 을 따른다 · 창구 product_create 는 설명을 안 넣는다 · 적재가 값을 실어 보내도 null) — 문 없이 INSERT 로 들어온 설명은 IMS 에서 고친 것이 아니다
create function public.product_description_guard() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if coalesce(current_setting('ims.description_door', true), '') = '1' then return new; end if;
  if tg_op = 'INSERT' then
    new.description_html := null; new.description_edited_at := null; new.description_edited_by := null;
    return new;
  end if;
  new.description_html      := old.description_html;
  new.description_edited_at := old.description_edited_at;
  new.description_edited_by := old.description_edited_by;
  return new;
end;
$$;
revoke all on function public.product_description_guard() from public, anon, authenticated;
comment on function public.product_description_guard() is
  'desc-1b 판정 381 · 401: product · product_family BEFORE INSERT OR UPDATE FOR EACH ROW — 트랜잭션 지역 설정 ims.description_door = ''1''(product_update 의 op 둘이 그 문장 앞뒤에서만 켜고 되돌린다 · po.payment_door 선례)이 아니면 description_html · description_edited_at · description_edited_by 를 old 로 되돌린다(INSERT 는 null) · raise 하지 않는다 — 적재(service_role)가 어떻게 보내든 IMS 설명이 안 지워진다 · 이름순으로 product_touch · product_sku_lock 보다 먼저 돈다';
create trigger product_description_guard        before insert or update on public.product        for each row execute function public.product_description_guard();
create trigger product_family_description_guard before insert or update on public.product_family for each row execute function public.product_description_guard();

-- ═══ 5) product_update 재발행 — 마지막 정의 20261007003838_dsc_4b_tags_deal_read.sql:39~957(prosrc md5 bf05913e925e23061988e515614f4705 · 915 줄) ═══
--   더한 것: declare 둘(v_prev · v_dkind) · ① op 둘 · ② 검사 갈래 하나(sku | family_sku 공통 · old · 중복 · changed_elsewhere · html_missing · description_forbidden:<code> · description_not_edited) · ④ 적용 갈래 하나(문지기 문을 그 문장 앞뒤에서만)
--   바꾼 줄: ① Unknown op 문장(op 이름 둘 추가) · comment — 그 밖의 줄은 원본 그대로(diff 로 대조)
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
  v_tag      text;                                                                             -- dsc-4b 판정 336: 태그 op
  v_tagseen  text[] := '{}';                                                                   -- dsc-4b: 이 호출이 붙이는 태그(대소문자 충돌 · 같은 호출)
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
  v_prev     text;                                                                            -- desc-1b: 문지기 문(ims.description_door) 이전 값
  v_dkind    text;                                                                            -- desc-1b: 설명 op 의 대상 종류 글자(SKU · Family)
  v_fcodes   text[];                                                                          -- desc-1b: ims_html_forbidden 반환
  v_fields   constant text[] := array['name', 'brand_id', 'category_id', 'unit_id', 'weight', 'weight_unit', 'note', 'is_discontinued', 'set_discount_pct', 'sku', 'is_active', 'pack_factor', 'parent_sku', 'sellable'];   -- dsc-1 판정 281-4 · 294: sellable(boolean · master · 끄기 경고 sellable_off_open_lines)
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
                                         'surcharge_group_set',                                                                                                                -- surcharge-4a 하나
                                         'description_set', 'description_follow_cin7',                                                                                    -- desc-1b 둘(판정 401 · 402)
                                         'tag_add', 'tag_off') then                                                                                                               -- dsc-4b 둘(판정 336)
      raise exception 'Unknown op "%" — set, family_join, family_leave, family_option, family_head_set, barcode_add, barcode_off, barcode_primary, price_set, price_off, supplier_set, supplier_default, supplier_off, image_add, image_off, image_primary, image_order, surcharge_group_set, tag_add, tag_off, description_set or description_follow_cin7 — nothing was saved', coalesce(v_c->>'op', '(none)');
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

    -- ── desc-1b: 설명(판정 381 · 401 · 402) — {sku | family_sku, html, old} · {sku | family_sku, old} · 대상은 둘 중 하나 · old = 화면이 본 description_html(null = Cin7 따름 · '' = 일부러 비움 · 그대로 비교) ──
    if v_op in ('description_set', 'description_follow_cin7') then
      if nullif(trim(coalesce(v_c->>'family_sku', '')), '') is not null then
        v_sku := trim(v_c->>'family_sku'); v_key := v_sku; v_dkind := 'Family';
        v_changes := v_changes || jsonb_build_object('i', v_i, 'sku', v_sku, 'op', v_op, 'field', 'description', 'applied', false);
        select * into v_fam from public.product_family f where f.sku = v_sku;
        if v_fam.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':family_unknown', 'sku', v_sku, 'code', 'family_unknown', 'message', format('Family %s does not exist — nothing was saved', v_sku));
          continue;
        end if;
        v_idmap := v_idmap || jsonb_build_object('F' || v_sku, v_fam.id);
        v_cur := v_fam.description_html; v_hn := 'F' || v_fam.id::text || '|description';
      else
        v_sku := trim(coalesce(v_c->>'sku', '')); v_key := case when v_sku = '' then '(blank)' else v_sku end; v_dkind := 'SKU';
        v_changes := v_changes || jsonb_build_object('i', v_i, 'sku', v_sku, 'op', v_op, 'field', 'description', 'applied', false);
        select * into p from public.product x where x.sku = v_sku;
        if p.id is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':sku_unknown', 'sku', v_sku, 'code', 'sku_unknown', 'message', format('SKU %s does not exist — nothing was saved', v_sku));
          continue;
        end if;
        v_idmap := v_idmap || jsonb_build_object('P' || v_sku, p.id);
        v_cur := p.description_html; v_hn := p.id::text || '|description';
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:description', 'sku', v_sku, 'code', 'old_missing', 'message', format('%s %s description: the old value the screen saw is missing — nothing was saved', v_dkind, v_sku));
        continue;
      end if;
      if v_hn = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:description', 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('%s %s description is changed twice in this paste — nothing was saved', v_dkind, v_sku));
        continue;
      end if;
      v_seen := v_seen || v_hn;
      if v_cur is distinct from (v_c->>'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:description', 'sku', v_sku, 'code', 'changed_elsewhere', 'message', format('Someone just changed the description of %s %s — check again — nothing was saved', v_dkind, v_sku));
        continue;
      end if;
      if v_op = 'description_set' then
        if not (v_c ? 'html') or jsonb_typeof(v_c->'html') <> 'string' then                     -- '' 는 된다(일부러 비움) · null · 없음은 막는다(비우려면 '' · Cin7 을 따르려면 description_follow_cin7)
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':html_missing', 'sku', v_sku, 'code', 'html_missing', 'message', format('%s %s: the description text is missing — send "" to leave it blank on purpose, or use Follow Cin7 — nothing was saved', v_dkind, v_sku));
          continue;
        end if;
        v_fcodes := public.ims_html_forbidden(v_c->>'html');                                      -- 판정 402: 판별만 · 코드마다 막기 하나(화면이 무엇이 걸렸는지 보인다)
        foreach v_tag in array v_fcodes loop
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':description_forbidden:' || v_tag, 'sku', v_sku, 'code', 'description_forbidden', 'detail', v_tag, 'message', format('%s %s: the description contains %s, which is not allowed (scripts, event handlers, javascript: links, object/embed/form/meta/link/base, and iframes from other sites) — remove it — nothing was saved', v_dkind, v_sku, v_tag));
        end loop;
      elsif v_cur is null then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':description_not_edited', 'sku', v_sku, 'code', 'description_not_edited', 'message', format('%s %s already follows the Cin7 description — there is nothing to undo — nothing was saved', v_dkind, v_sku));
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
                 when 'sellable' then p.sellable::text
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
      when 'sellable' then                                                                       -- dsc-1 판정 281-4 · 294
        if jsonb_typeof(v_val) <> 'boolean' then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:sellable', 'sku', v_sku, 'code', 'value_invalid', 'message', format('SKU %s sellable must be true or false — nothing was saved', v_sku));
        elsif not (v_val)::boolean then
          select count(*) into v_cnt from public.so_line l join public.so s on s.id = l.so_id where l.product_id = p.id and s.status = any(v_open_so);
          if v_cnt > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':sellable_off_open_lines', 'sku', v_sku, 'code', 'sellable_off_open_lines', 'count', v_cnt, 'message', format('SKU %s is on %s open order line(s) — they keep their prices; new lines will be refused once it is not for sale. Confirm to turn Sellable off', v_sku, v_cnt));
          end if;
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

    -- ── dsc-4b: 태그(판정 336 · 332 의 짝 — btrim 만 · 대소문자만 다른 태그는 막는다 · 떼기는 행 삭제) ──────────────────────────
    elsif v_op in ('tag_add', 'tag_off') then
      v_tag := btrim(coalesce(v_c->>'tag', ''));
      if v_tag = '' then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_empty', 'sku', v_sku, 'code', 'tag_empty', 'message', format('SKU %s has an empty tag — nothing was saved', v_sku));
        continue;
      end if;
      if (p.id::text || '|tag|' || lower(v_tag)) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_tag, 'sku', v_sku, 'code', 'field_duplicate_in_call', 'message', format('Tag %s of %s is changed twice in this paste — nothing was saved', v_tag, v_sku));
        continue;
      end if;
      v_seen := v_seen || (p.id::text || '|tag|' || lower(v_tag));
      if v_op = 'tag_add' then
        if exists (select 1 from public.product_tag pt where pt.product_id = p.id and pt.tag = v_tag) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_exists:' || v_tag, 'sku', v_sku, 'code', 'tag_exists', 'message', format('Tag %s is already on %s — nothing was saved', v_tag, v_sku));
          continue;
        end if;
        select min(pt.tag) into v_cur from public.product_tag pt where lower(pt.tag) = lower(v_tag) and pt.tag <> v_tag;                                          -- 판정 332 의 짝: 제품 태그 전체
        if v_cur is null then select min(x.tag) into v_cur from public.so_deal_target x where lower(x.tag) = lower(v_tag) and x.tag <> v_tag; end if;              -- 딜 대상
        if v_cur is null then select min(g) into v_cur from unnest(v_tagseen) g where lower(g) = lower(v_tag) and g <> v_tag; end if;                               -- 같은 호출
        if v_cur is not null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_case_conflict:' || v_tag, 'sku', v_sku, 'code', 'tag_case_conflict', 'message', format('Tag "%s" differs only by case from "%s" — use the existing spelling — nothing was saved', v_tag, v_cur));
          continue;
        end if;
        v_tagseen := v_tagseen || v_tag;
      else
        if not exists (select 1 from public.product_tag pt where pt.product_id = p.id and pt.tag = v_tag) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tag_not_found:' || v_tag, 'sku', v_sku, 'code', 'tag_not_found', 'message', format('SKU %s does not carry tag %s — nothing was saved', v_sku, v_tag));
          continue;
        end if;
        if (select count(*) from public.product_tag pt where pt.tag = v_tag) = 1 then                                                                               -- ⬜ 알리기: 켜진 딜의 켜진 줄이 이 태그로 걸고 · 떼면 이 태그의 제품이 0
          select string_agg(distinct d.name, ', ') into v_cur
            from public.so_deal_target x join public.so_deal_line l on l.id = x.line_id join public.so_deal d on d.id = l.deal_id
           where x.target = 'tag' and x.tag = v_tag and l.is_active and d.is_active;
          if v_cur is not null then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':tag_off_used_by_deal:' || v_tag, 'sku', v_sku, 'code', 'tag_off_used_by_deal', 'deals', v_cur, 'message', format('Tag %s is the last one of its kind and active deal(s) %s target it — after this they match nothing on this tag', v_tag, v_cur));
            v_keys := array_append(v_keys, v_key || ':tag_off_used_by_deal:' || v_tag);
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
      if v_op in ('description_set', 'description_follow_cin7') then                           -- desc-1b: 문지기 문은 이 문장 앞뒤에서만(po.payment_door 선례) · 아래 family_head_set/else 갈래는 이 op 를 모른다(상품 찾기만 헛돌고 아무것도 안 한다)
        v_prev := current_setting('ims.description_door', true);  perform set_config('ims.description_door', '1', true);
        if nullif(trim(coalesce(v_c->>'family_sku', '')), '') is not null then
          if v_op = 'description_set' then
            update public.product_family set description_html = v_c->>'html', description_edited_at = now(), description_edited_by = v_staff where id = (v_idmap->>('F' || trim(v_c->>'family_sku')))::uuid;
          else
            update public.product_family set description_html = null, description_edited_at = null, description_edited_by = null where id = (v_idmap->>('F' || trim(v_c->>'family_sku')))::uuid;
          end if;
        else
          if v_op = 'description_set' then
            update public.product set description_html = v_c->>'html', description_edited_at = now(), description_edited_by = v_staff where id = (v_idmap->>('P' || trim(coalesce(v_c->>'sku', ''))))::uuid;
          else
            update public.product set description_html = null, description_edited_at = null, description_edited_by = null where id = (v_idmap->>('P' || trim(coalesce(v_c->>'sku', ''))))::uuid;
          end if;
        end if;
        perform set_config('ims.description_door', coalesce(v_prev, ''), true);
      end if;
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
          when 'sellable' then update public.product set sellable = (v_val)::boolean, sellable_source = 'ims' where id = p.id;   -- dsc-1 판정 294: 창구가 바꾸면 ims
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
        elsif v_op = 'tag_add' then                                                            -- dsc-4b 판정 336: 태그는 행 하나 · 떼기는 삭제(관계 표 규약)
          insert into public.product_tag (product_id, tag, source, updated_by) values (p.id, btrim(v_c->>'tag'), 'manual', v_staff);
        elsif v_op = 'tag_off' then
          delete from public.product_tag where product_id = p.id and tag = btrim(v_c->>'tag');
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
comment on function public.product_update(jsonb, boolean, text[]) is
  '⭐ 상품 고치기 창구(판정 187 ~ 194 · 222 · 223 · 231 · 232 · 2026-10-01 prod-4a + 4b + img-1 + price-1 · 2026-10-02 surcharge-4a · 2026-10-06 dsc-1 판정 281-4 · 294 sellable · ⭐ 2026-10-06 dsc-4b 판정 336: 태그 op 둘) — security definer · 첫 줄 ims_require_write(master). p_changes = 바꿀 것 목록(최대 1,000 줄) · 줄 = {sku, op, …, old} · op 스물: set(칸 하나 — name · brand_id · category_id · unit_id · weight · weight_unit · note · is_discontinued · set_discount_pct · sku · is_active · pack_factor · parent_sku · sellable) · family_join {sku, family_sku, options[]} · family_leave {sku, old} · family_option {sku, options[], old[]} · family_head_set {family_sku, field, value, old} · barcode_add/barcode_off/barcode_primary {sku, barcode} · price_set {sku, tier_id, price, old?, formula?} · price_off {sku, tier_id, old} · supplier_set {sku, supplier_id, supplier_sku?, cost?, fixed_cost?, currency_id?, old{}?} · supplier_default/supplier_off {sku, supplier_id} · image_add {sku, storage_path, content_type, byte_size?, width?, height?, file_name?, primary?} · image_off/image_primary {sku, image_id} · image_order {sku, image_ids[]} · surcharge_group_set {sku, group_id | null, old} · ⭐ tag_add {sku, tag} · tag_off {sku, tag}(dsc-4b 판정 336 · 332 의 짝 — btrim 만 · 대소문자 바꾸지 않음 · 막기 tag_empty · tag_exists · tag_not_found · tag_case_conflict(제품 태그 전체 · 딜 대상 so_deal_target.tag · 같은 호출) · field_duplicate_in_call · 알리기 tag_off_used_by_deal{deals}(ack — 이 태그의 마지막 제품에서 떼는데 켜진 딜의 켜진 줄이 그 태그로 건다) · 떼기는 행 삭제(관계 표 규약) · 붙인 행은 source manual). old = 화면이 본 옛 값 — 다르면 changed_elsewhere. 검사만(p_commit false) → 저장(p_commit true + p_ack) · 저장 직전 재검사(판정 176) · 막기 하나면 아무것도 안 바뀐다. 바코드 · 판매가 · 공급처 · 사진 빼기는 끄기(판정 188) · IMS 가 손댄 줄은 source manual(판정 133). code 목록은 20261001143142 · 20261001145316 · 20261001152712 · 20261002012641 · 20261002155201 · 20261006183851 · 20261007003838(dsc-4b) · ⭐ 2026-10-09 desc-1b 판정 381 · 401 · 402: description_set {sku | family_sku, html, old} · description_follow_cin7 {sku | family_sku, old}(old = 화면이 본 description_html · null = Cin7 따름 · '''' = 일부러 비움 · 막기 html_missing · description_forbidden:<code>{detail}(ims_html_forbidden · 판별만) · description_not_edited · 적용은 문지기 문 ims.description_door 를 그 문장 앞뒤에서만 켠다 · edited_by = v_staff) · code 목록은 … 이 파일(desc-1b)의 머리';

-- ═══ 6) 뷰 둘 — security_invoker(베이스 표 RLS · anon 회수가 그대로) ═══
--   product_description — ⭐ 화면과 뒤의 Shopify 보내기는 이것만 읽는다(html_effective = coalesce · 원문 칸을 직접 그리지 않는다 · 거르기는 공통 js 한 곳)
create or replace view public.product_description
  with (security_invoker = true) as
  select 'product'::text as kind, p.id, p.sku, p.name, p.is_active,
         coalesce(p.description_html, p.cin7_description) as html_effective,
         (p.description_html is not null)                  as is_edited,
         p.description_edited_at                           as edited_at,
         p.description_edited_by                           as edited_by
    from public.product p
  union all
  select 'family'::text, f.id, f.sku, f.name, f.is_active,
         coalesce(f.description_html, f.cin7_description),
         (f.description_html is not null),
         f.description_edited_at,
         f.description_edited_by
    from public.product_family f;
revoke all on public.product_description from anon;
grant select on public.product_description to authenticated;
comment on view public.product_description is
  'desc-1b 판정 381 · 401: 상품 · family 의 실제 설명 — html_effective = coalesce(description_html, cin7_description) · is_edited = IMS 에서 고쳤다(null 이 아니다) · ⭐ 화면 · Shopify 보내기는 이 뷰만 읽고 원문 칸을 직접 그리지 않는다 · 거르기(DOMPurify · ref_embed_host)는 보여 줄 때 · security_invoker(로그인 필수 · anon 회수)';

--   product_description_edited — 솎아내기(판정 401): 고친 것만 · 본문 없이 · Cin7 원문과 다른가
create or replace view public.product_description_edited
  with (security_invoker = true) as
  select x.kind, x.id, x.sku, x.name, x.is_active, x.edited_at, x.edited_by,
         (select s.name from public.ims_staff s where s.id = x.edited_by) as edited_by_name,
         x.differs_from_cin7
    from (select 'product'::text as kind, p.id, p.sku, p.name, p.is_active, p.description_edited_at as edited_at, p.description_edited_by as edited_by,
                 (p.description_html is distinct from p.cin7_description) as differs_from_cin7
            from public.product p where p.description_html is not null
          union all
          select 'family'::text, f.id, f.sku, f.name, f.is_active, f.description_edited_at, f.description_edited_by,
                 (f.description_html is distinct from f.cin7_description)
            from public.product_family f where f.description_html is not null) x;
revoke all on public.product_description_edited from anon;
grant select on public.product_description_edited to authenticated;
comment on view public.product_description_edited is
  'desc-1b 판정 401 솎아내기: IMS 에서 설명을 고친 상품 · family 만(description_html not null) — 언제(edited_at) · 누가(edited_by · edited_by_name = ims_staff.name · 별칭 한정) · differs_from_cin7 = 고친 글이 Cin7 원문과 다른가 · 본문은 없다(product_description 에서) · 되돌리기는 product_update description_follow_cin7';
