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

-- ============================================================
-- desc-bc-1 — 상품 · 제품군 설명 맨 끝의 「(Barcode: …)」 덩이를 일괄로 지운다 (2026-10-30 · 판정 891 · 지시서 ~/asung/prompts/desc-bc-1.md)
--   [테스트 · Asung-IMS] 시험(Claude Code · rollback): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261030203600_desc_bc_1_strip_barcode_tail.sql -f supabase/tests/desc_bc_1_check.sql
--   적용(Caleb · ⏰ 오늘 밤 Apply links 앞): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261030203600_desc_bc_1_strip_barcode_tail.sql && supabase migration repair --status applied 20261030203600 --db-url "$(cat ~/.asung-testdb-url)"
--   확인(Caleb · 적용 뒤): 시험 명령에서 -v mig 만 뺀다 · IMS Products 에서 AMB23457 · AMB23457FAM 설명 끝에 바코드 줄이 없는지 눈으로
--   왜(판정 891): Cin7 원문 설명 끝에 붙은 「(Barcode: 850004234570, …)」 줄은 제품군에서 변형을 빼거나 끄면 틀린 채 남는다(AMB23457FAM — 꺼진 AMB23483 의 바코드) · 바코드는 product_barcode 가 정본이라 설명에 둘 까닭이 없다
--   무엇(데이터만 · 스키마 · 함수 재발행 없음):
--     1) 세션 임시 함수 pg_temp.desc_bc_strip(text) — 설명의 ⭐ 맨 끝 덩이 하나만 지운다(Caleb 「맨 밑에 있는」)
--        · 덩이 = 「(Barcode」로 열어 「)」로 닫는 괄호(대소문자 무시 · Barcode: · Barcodes: · Barcode; · 콜론 없음 · 안의 &nbsp; · <br> · <span> 허용 — 괄호 안은 ( ) 만 아니면 무엇이든 · Caleb 「(Barcode 시작해서 ) 로 닫는 것」)
--        · 안 닫힌 덩이(실측 10 행 · 「(Barcode: 829534407464,</p>」)는 「(Barcode」 뒤 끝까지 보이는 글이 숫자 · 쉼표 · 마침표뿐일 때만 같은 덩이로 본다
--        · 덩이 뒤에 보이는 글이 있으면(가운데 덩이 · 실측 상품 13 · 제품군 1 — BS* 의 「#2266」 · ASSHBUJOLIE 의 「PALMA: 2」) 그 행은 안 건드린다
--        · 지운 뒤 정리: 덩이 바로 앞 빈칸 · &nbsp; · <br> · <!-- --> 를 떼고 → 비게 된 껍데기(<p> <span> <strong> <u> <li> <ul> … 최대 4 겹)를 앞뒤 짝 맞춰 벗기고 → 글 끝의 빈 문단(<p>&nbsp;</p> · <p><br></p>) · <br> · 빈칸을 뗀다
--        · 증명(시험 A): 바뀐 행마다 「보이는 글(태그 · &nbsp; · 빈칸 뺀 것)」 이 결과 + 덩이 하나와 정확히 같다(접두 일치 · 지운 보이는 글이 (Barcode…) 하나) · 멱등(두 번째는 0 행) · 빈 <ul></ul> 안 생김
--     2) 미리 셈(temp 표 · 잠금 없음 · 실측 2.7 초) → 문 ims.description_door 를 트랜잭션 지역으로 열고 product · product_family 각 한 문장 update(실측 3.0 초 · 0.1 초) → 문 되돌림
--        · 쓰는 값: description_html = coalesce(description_html, cin7_description) 에서 덩이만 뺀 글 · description_edited_at = now()(한 트랜잭션 = 한 시각 = 되돌리기 표식) · description_edited_by = Caleb(Seungchill Chang · ims_staff f6f5044e-a974-44c7-a4b2-d28309cf3b89)
--        · 바뀐 것이 없는 행(덩이 없음 · 가운데 덩이)은 쓰지 않는다 → 두 번째 실행은 0 행(멱등)
--        · 실측(2026-10-30 · 테스트 = 운영과 같은 수): product 16,133 · product_family 953 바뀜(Caleb 실측 16,143 · 953 가운데 가운데 덩이 13 · 1 제외 + 콜론 없는 꼴 3 · 1 포함)
--        · ⭐ 결과가 빈 글('')이 되는 행 — product 1,246 · product_family 75(설명이 바코드 줄뿐이었다) → '' = 「일부러 비움」(desc-1b 규약) 으로 쓴다
--        · ⭐ 결과에 ims_html_forbidden 이 걸리는 행 — product 98 · product_family 6(DES* · iframe_host:www.powr.io — Cin7 원문에 이미 든 iframe) → 그대로 쓴다(창구는 막지만 이 글은 원문 그대로 · 화면 DOMPurify · EF 가 보여 줄 때 거른다 · 창구에서 고치려면 ref_embed_host 에 powr.io 를 더하거나 iframe 을 빼야 한다)
--     3) 큐: product · product_family 의 AFTER STATEMENT 트리거(shop_queue_trigger)가 켜진 listing 대상만 shop_push_queue 에 넣는다 — 지금 켜진 listing 은 죽은 test 스토어(is_active false · live false) 5 줄뿐 → 실측 3 줄 · 이 블록이 그 줄(이 트랜잭션 · 일하지 않는 스토어 · reason product/product_family)만 지운다(asung · aone 은 listing 0 → 줄 0 · Apply links 가 심을 last_hash 는 이미 새 설명의 hash)
--   ⚠️ 이 글들은 이제 「IMS 가 고친 설명」(description_html not null · product_description_edited 에 17,086 행) — 다음 제품 재적재가 cin7_description 을 바꿔도 보이는 설명은 바뀌지 않는다(문지기 · Caleb 이해 · 컷오버 뒤 IMS 가 정본)
--   ⚠️ 부수: product.updated_at 이 16,133 행에서 now() 로 · updated_by 는 null(ims_touch — psql 은 auth.uid() 없음) · product_family 도 같다
--   되돌리기(전부 · Caleb psql · 한 트랜잭션 — 이 차수 전에는 IMS 가 고친 설명이 0 행이라 「Caleb · 이 시각」 이 곧 이 차수의 행이다 · = description_follow_cin7 과 같은 결과):
--     begin; select set_config('ims.description_door', '1', true);
--     update public.product        set description_html = null, description_edited_at = null, description_edited_by = null where description_edited_by = 'f6f5044e-a974-44c7-a4b2-d28309cf3b89' and description_edited_at = '<raise notice 의 edited_at>';
--     update public.product_family set description_html = null, description_edited_at = null, description_edited_by = null where description_edited_by = 'f6f5044e-a974-44c7-a4b2-d28309cf3b89' and description_edited_at = '<raise notice 의 edited_at>';
--     commit;
--   무접촉: product_update · product_description_guard · 뷰 product_description · product_description_edited · shop_product_payload · shop_queue_add · shop_queue_trigger · ims_html_forbidden(모두 읽기만 · 재발행 없음 — 시험 F md5)
-- ============================================================

-- ═══ 1) 도우미 — 세션 임시 함수(DB 에 남지 않는다) ═══
create function pg_temp.desc_bc_strip(p text) returns text
  language plpgsql immutable
as $$
declare
  m text[]; h text; t text; tag text; r text; i int;
begin
  if p is null then return null; end if;
  -- ① 마지막 닫힌 덩이 「(Barcode … )」 — 괄호 안은 ( ) 만 아니면 무엇이든(태그 · &nbsp; 포함)
  m := regexp_match(p, '^(.*)(\(\s*barcodes?\s*[:;]?[^()]*\))(.*)$', 'is');
  if m is not null then
    h := m[1]; t := m[3];
    if regexp_replace(t, '<[^>]*>|&nbsp;|\s', '', 'gi') <> '' then return p; end if;             -- 뒤에 보이는 글 = 가운데 덩이 → 안 건드림
  else
    -- ② 안 닫힌 덩이 — 「(Barcode」 뒤 끝까지 보이는 글이 숫자 · 쉼표 · 마침표뿐일 때만
    m := regexp_match(p, '^(.*)(\(\s*barcodes?\s*[:;]?[^()]*)$', 'is');
    if m is null or regexp_replace(m[2], '<[^>]*>|&nbsp;|\s', '', 'gi') !~* '^\(barcodes?[:;]?[0-9,.]*$' then return p; end if;
    h := m[1]; t := regexp_replace(m[2], '^.*?((?:</[a-z]+\s*>\s*)*)$', '\1', 'is');             -- 덩이 끝에 섞인 닫는 태그(</p> 등)는 남긴다
    if t = m[2] then t := ''; end if;
  end if;
  -- ③ 덩이 바로 앞 구분자 떼기 → 비게 된 껍데기를 앞뒤 짝 맞춰 벗기기(최대 4 겹)
  h := regexp_replace(h, '(\s|&nbsp;|<br\s*/?>|<!--([^-]|-[^-])*-->)+$', '', 'i');
  for i in 1..4 loop
    tag := (regexp_match(h, '<(p|span|div|strong|b|em|u|li|ul|ol|font|h[1-6])(\s[^>]*)?>\s*$', 'i'))[1];
    exit when tag is null or t !~* ('^\s*</' || tag || '\s*>');
    h := regexp_replace(h, '<' || tag || '(\s[^>]*)?>\s*$', '', 'i');
    t := regexp_replace(t, '^\s*</' || tag || '\s*>', '', 'i');
    h := regexp_replace(h, '(\s|&nbsp;|<br\s*/?>|<!--([^-]|-[^-])*-->)+$', '', 'i');
  end loop;
  r := h || t;
  -- ④ 글 끝의 빈 문단 · <br> · 주석 · 빈칸 떼기(덩이 뒤에 원래 있던 빈 문단도 — 끝 쓰레기)
  r := regexp_replace(r, '(\s|&nbsp;|<br\s*/?>|<!--([^-]|-[^-])*-->|<p(\s[^>]*)?>(\s|&nbsp;|<br\s*/?>|<!--([^-]|-[^-])*-->)*</p>)+$', '', 'i');
  return r;
end $$;

-- ═══ 2) 미리 셈 — 잠금 없음 · 바뀌는 행만 남긴다 ═══
create temp table desc_bc_new on commit drop as
select 'product'::text as kind, p.id, coalesce(p.description_html, p.cin7_description) as src, pg_temp.desc_bc_strip(coalesce(p.description_html, p.cin7_description)) as r
  from public.product p where coalesce(p.description_html, p.cin7_description) ~* '\(\s*barcodes?\y'
union all
select 'family', f.id, coalesce(f.description_html, f.cin7_description), pg_temp.desc_bc_strip(coalesce(f.description_html, f.cin7_description))
  from public.product_family f where coalesce(f.description_html, f.cin7_description) ~* '\(\s*barcodes?\y';
delete from desc_bc_new where r is not distinct from src;

-- ═══ 3) 문 열고 두 문장 · 문 되돌림 · 죽은 스토어 큐 줄 정리 · 보고 ═══
do $$
declare
  v_staff  constant uuid := 'f6f5044e-a974-44c7-a4b2-d28309cf3b89';                               -- Caleb(Seungchill Chang)
  v_now    constant timestamptz := now();
  v_prev   text;
  v_p      int; v_f int; v_q int; v_pe int; v_fe int; v_pf int; v_ff int;
begin
  if not exists (select 1 from public.ims_staff s where s.id = v_staff and s.is_active) then
    raise exception 'desc-bc-1: ims_staff % (Caleb) is missing or inactive — nothing was changed', v_staff;
  end if;
  select count(*) filter (where kind = 'product' and r = ''), count(*) filter (where kind = 'family' and r = ''),
         count(*) filter (where kind = 'product' and public.ims_html_forbidden(r) <> '{}'), count(*) filter (where kind = 'family' and public.ims_html_forbidden(r) <> '{}')
    into v_pe, v_fe, v_pf, v_ff from desc_bc_new;
  v_prev := current_setting('ims.description_door', true);
  perform set_config('ims.description_door', '1', true);                                          -- 문지기 문(desc-1b · product_update 와 같은 표식 · 트랜잭션 지역)
  update public.product p
     set description_html = n.r, description_edited_at = v_now, description_edited_by = v_staff
    from desc_bc_new n where n.kind = 'product' and n.id = p.id;
  get diagnostics v_p = row_count;
  update public.product_family f
     set description_html = n.r, description_edited_at = v_now, description_edited_by = v_staff
    from desc_bc_new n where n.kind = 'family' and n.id = f.id;
  get diagnostics v_f = row_count;
  perform set_config('ims.description_door', coalesce(v_prev, ''), true);
  -- 큐: 위 두 문장이 만든 줄 가운데 일하지 않는 스토어(is_active and live 아님 · 죽은 test 스토어)의 것만 — 이 트랜잭션(queued_at = now()) · 열린 줄 · reason 둘
  delete from public.shop_push_queue q
   using public.shop_store s
   where s.id = q.store_id and not (s.is_active and s.live)
     and q.done_at is null and q.queued_at = v_now and q.reason in ('product', 'product_family');
  get diagnostics v_q = row_count;
  raise notice 'desc-bc-1: product % · product_family % rows — trailing (Barcode…) removed · edited_at % · edited_by % · empty results product % · family % · forbidden-html results product % · family % · dead-store queue rows removed %',
    v_p, v_f, v_now, v_staff, v_pe, v_fe, v_pf, v_ff, v_q;
end $$;
