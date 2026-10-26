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

-- ═══ tagn-1 — 태그 이름만 주는 창구 하나: product_tag_names() (2026-10-26 · 판정 772 · deferred 340) ═══
--   왜: Settings → Discount Rules 가 다른 메뉴보다 확실히 느리게 열린다(Caleb 실측 2026-10-26) — discount-rules.html 이 product_tag 63,515 줄을 1,000 줄씩 64 번 차례로 읽고(15 MB) 다 받은 뒤에야 규칙 목록을 그린다 · 필요한 것은 서로 다른 태그 1,193 개뿐
--       products.html 의 loadTagNames(Edit 를 처음 열 때)도 같은 꼴 — product_tag 전부 + so_deal_target(target = 'tag') 의 tag 를 합쳐 서로 다른 이름(딜이 먼저 쓰는 태그도 같은 철자로 · pr v4c)
--   판정 772 「B」: DB 에 태그 이름만 주는 창구 하나 + 화면(discount-rules 는 규칙 목록을 기준 목록보다 먼저 그린다 · products 는 창구로) — 화면은 이 파일 밖(대화 Claude)
--   product_tag_names() returns jsonb — ["AOS", "ASS", …] 글자 배열 한 행(PostgREST 1,000 행 캡 · 1,193 > 1,000)
--     = product_tag 의 서로 다른 tag ∪ so_deal_target(target = 'tag') 의 서로 다른 tag · 빈 값 · null 제외
--     정렬 = collate "en-x-icu"(ICU) — 화면이 쓰는 String.localeCompare 와 같은 ICU 순서(실측 2026-10-26: 테스트 DB 1,193 개를 node 22 의 localeCompare 로 정렬한 것과 자리 0 차이 · "C" 는 1,184 자리 다름) · 대소문자 구별 그대로(「Tags are case-sensitive」 · 소문자 a 가 대문자 A 앞)
--     stable · security invoker(두 표의 select 정책이 authenticated 에게 using (true) 라 definer 가 필요 없다 · 원가 · 개인정보 없음) · authenticated 만 실행 · anon · public · service_role 없음
--   색인: product_tag_tag_idx · so_deal_target_tag_idx 가 이미 있다(so_deal 2026-09-23) — 새 색인 없음
--   새 표 · 칸 · 시퀀스 0 · 쓰기 0 · 무접촉: product_tag · so_deal_target(표 · 정책 · 트리거) · 화면 · 검증 supabase/tests/tagn_1_check.sql

do $$
declare v_bad text := '';
begin
  if to_regclass('public.product_tag') is null then v_bad := v_bad || ' product_tag'; end if;
  if to_regclass('public.so_deal_target') is null then v_bad := v_bad || ' so_deal_target'; end if;
  if not exists (select 1 from pg_collation where collname = 'en-x-icu') then v_bad := v_bad || ' collation en-x-icu'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM511', message = format('STOP - tagn-1 needs%s - nothing was changed', v_bad); end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_tag_names') then
    raise exception using errcode = 'IM511', message = 'STOP - product_tag_names already exists (applied?) - nothing was changed';
  end if;
end $$;

create function public.product_tag_names() returns jsonb
language sql stable security invoker set search_path = public, pg_temp as $$
  select coalesce(jsonb_agg(u.tag order by u.tag collate "en-x-icu"), '[]'::jsonb)
  from (
    select t.tag from public.product_tag t
    union
    select d.tag from public.so_deal_target d where d.target = 'tag'
  ) u
  where u.tag is not null and u.tag <> ''
$$;
revoke all on function public.product_tag_names() from public, anon, service_role;
grant execute on function public.product_tag_names() to authenticated;
comment on function public.product_tag_names() is 'tagn-1 판정 772 — 태그 이름 목록 한 행: ["AOS", …] = product_tag 의 서로 다른 tag ∪ so_deal_target(target = tag) 의 서로 다른 tag(빈 값 · null 제외) · 정렬 collate en-x-icu(화면 localeCompare 와 같은 ICU 순서 · 대소문자 구별) · stable · invoker(두 표 select 정책 using true) · authenticated 만 · discount-rules.html 기준표 · products.html loadTagNames 가 product_tag 63,515 줄 대신 이것을 읽는다';
