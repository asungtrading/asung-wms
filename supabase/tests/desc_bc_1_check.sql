-- supabase/tests/desc_bc_1_check.sql — desc-bc-1 상품 · 제품군 설명 맨 끝 「(Barcode: …)」 덩이 지우기 (2026-10-30 · 판정 891)
-- [테스트 · Asung-IMS] 시험 적용 장치 틀 — 기준(begin 앞 · 잠금 없음: 실제 행 수 · 고친 설명 수 · 열린 큐 · 함수 md5) → begin → (-v mig 면 \i) → A(수 · 짝 · 남은 덩이 0) · B(표본 글 대조) · C(뷰) · D(payload) · E(큐) · F(무접촉 md5 · 문지기 살아 있음 · 임시 함수 안 남음) → rollback → Z1 실제 행 무변
--   Claude Code(시험): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261030203600_desc_bc_1_strip_barcode_tail.sql -f supabase/tests/desc_bc_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다
--   기대 OK: 두 갈래 같다(검사는 전부 「적용 뒤 상태」 를 본다) · Z 는 t_res 밖 한 줄씩
--   ⚠️ 잠금 규칙: begin ~ rollback 10 초 안(끝에 begin_to_rollback) · -v mig 갈래는 안에서 update 두 문장(실측 3.1 초 · 미리 셈 2.7 초는 잠금 없음) + 검사(A8 은 1/16 표본 — 전수 vis 는 16k 행에 11 초라 잠금 창을 넘긴다 · 확인 갈래는 전수) · lock_timeout 3s
--   ⚠️ 수는 2026-10-30 실측(product 16,133 · family 953 · 가운데 덩이 13 · 1 · 빈 결과 1,246 · 75) — 그 뒤 IMS 에서 설명을 고치거나 제품을 재적재하면 A 의 수가 어긋날 수 있다(그때는 MISMATCH 의 got 를 읽는다)
\set ON_ERROR_STOP on
\set EXPECT_OK 28
\if :{?mig}
\set a8_filter 'and hashtext(x.sku) % 16 = 0'
\set a8_name 'A8 ⭐ 보이는 글 보존(시험 갈래 = 1/16 표본 · 잠금 창 — 전수는 적용 뒤 확인 갈래 · 조사 때 전수 0/0): 고친 행마다 vis(cin7 원문) = vis(새 글) + 「(Barcode…)」 하나 — 어긋난 행 0 / 0'
\else
\set a8_filter ''
\set a8_name 'A8 ⭐ 보이는 글 보존(전수): 고친 행마다 vis(cin7 원문) = vis(새 글) + 「(Barcode…)」 하나 — 어긋난 행 0 / 0'
\endif
\pset pager off
select (select count(*) from public.product) as n_prod0, (select count(*) from public.product_family) as n_fam0,
       (select count(*) from public.product where description_html is not null) as pe0, (select count(*) from public.product_family where description_html is not null) as fe0,
       (select count(*) from public.shop_push_queue) as n_q0, (select count(*) from public.shop_push_queue where done_at is null) as n_qopen0,
       (select max(updated_at)::text from public.product) as pu0,
       (select id::text from public.shop_store where code = 'test') as test_sid,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_update') as pu_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_description_guard') as gd_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload') as pp_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_add') as qa_md5_0,
       (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_html_forbidden') as hf_md5_0 \gset
\set caleb f6f5044e-a974-44c7-a4b2-d28309cf3b89
\echo '── 기준: product' :n_prod0 '· family' :n_fam0 '· 고친 설명 product' :pe0 '· family' :fe0 '· 열린 큐' :n_qopen0
begin;
set local lock_timeout = '3s';
select clock_timestamp() as t_begin \gset
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif

-- ── 도우미 ──
create temp table t_res (n serial, name text, ok boolean, got text, want text);
create function pg_temp.chk(p_name text, p_got text, p_want text) returns void language sql security definer as $$
  insert into t_res(name, ok, got, want) values (p_name, p_got is not distinct from p_want, p_got, p_want);
$$;
create function pg_temp.vis(p text) returns text language sql immutable as $$ select regexp_replace(p, '<[^>]*>|&nbsp;|\s', '', 'gi') $$;
create function pg_temp.tl(p text, n int) returns text language sql immutable as $$ select regexp_replace(right(p, n), E'[\\r\\n]', '⏎', 'g') $$;
create function pg_temp.ends(p text, w text) returns text language sql immutable as $$ select case when p is null then '(null)' when right(p, length(w)) = w then 'ends' else 'tail=' || pg_temp.tl(p, length(w) + 12) end $$;   -- 끝이 w 로 끝나는가(길이 세지 않게)

-- ── A) 수 · 짝 · 남은 덩이 ──
select pg_temp.chk('A1 고친 설명(Caleb · description_html not null): product 16133 / family 953',
  (select count(*) from public.product where description_html is not null and description_edited_by = :'caleb'::uuid)::text || ' / ' ||
  (select count(*) from public.product_family where description_html is not null and description_edited_by = :'caleb'::uuid)::text, '16133 / 953');
select pg_temp.chk('A2 짝 CHECK 위반 0(html · edited_at · edited_by 셋이 함께) · Caleb 이 아닌 고친 설명 0',
  (select count(*) from public.product where (description_html is null) <> (description_edited_at is null) or (description_edited_at is null) <> (description_edited_by is null))::text || '/' ||
  (select count(*) from public.product_family where (description_html is null) <> (description_edited_at is null) or (description_edited_at is null) <> (description_edited_by is null))::text || '/' ||
  (select count(*) from public.product where description_html is not null and description_edited_by is distinct from :'caleb'::uuid)::text || '/' ||
  (select count(*) from public.product_family where description_html is not null and description_edited_by is distinct from :'caleb'::uuid)::text, '0/0/0/0');
select pg_temp.chk('A3 edited_at 은 한 시각(되돌리기 표식): distinct 1 / 1 · 두 표 같은 시각',
  (select count(distinct description_edited_at) from public.product where description_edited_by = :'caleb'::uuid)::text || ' / ' ||
  (select count(distinct description_edited_at) from public.product_family where description_edited_by = :'caleb'::uuid)::text || ' / ' ||
  ((select min(description_edited_at) from public.product where description_edited_by = :'caleb'::uuid) = (select min(description_edited_at) from public.product_family where description_edited_by = :'caleb'::uuid))::text, '1 / 1 / true');
select pg_temp.chk('A4 ⭐ 맨 끝 덩이가 남은 행 0(닫힌 덩이 뒤 태그 · 빈칸뿐): product / family',
  (select count(*) from public.product where coalesce(description_html, cin7_description) ~* '\(\s*barcodes?\s*[:;]?[^()]*\)(\s|&nbsp;|<[^>]*>)*$')::text || ' / ' ||
  (select count(*) from public.product_family where coalesce(description_html, cin7_description) ~* '\(\s*barcodes?\s*[:;]?[^()]*\)(\s|&nbsp;|<[^>]*>)*$')::text, '0 / 0');
select pg_temp.chk('A5 고친 글 안에 「(Barcode」 가 남은 행 0 · 안 닫힌 꼴도 0',
  (select count(*) from public.product where description_html ~* '\(\s*barcodes?\y')::text || '/' || (select count(*) from public.product_family where description_html ~* '\(\s*barcodes?\y')::text, '0/0');
select pg_temp.chk('A6 아직 덩이가 있는 행 = 가운데 덩이 14 뿐(안 건드림 · description_html null): product 13 / family 1 · SKU 목록',
  (select count(*) from public.product where coalesce(description_html, cin7_description) ~* '\(\s*barcodes?\y')::text || ' / ' ||
  (select count(*) from public.product_family where coalesce(description_html, cin7_description) ~* '\(\s*barcodes?\y')::text || ' / ' ||
  (select string_agg(sku, ' ' order by sku) from public.product where coalesce(description_html, cin7_description) ~* '\(\s*barcodes?\y' and description_html is null) || ' / ' ||
  (select string_agg(sku, ' ' order by sku) from public.product_family where coalesce(description_html, cin7_description) ~* '\(\s*barcodes?\y' and description_html is null),
  '13 / 1 / ASSHBUJOLIE1B27S ASSHBUJOLIE1B30S BS02266 BS02266-12 BS04702-12 BS14702 BS2017BLA BS2017BLA-12 BS2207 BS2207-12 BS2240BLA BS2240BLA-12 BS49287P / BS04702FAM');
select pg_temp.chk('A7 빈 결과(일부러 비움 ''''): product 1246 / family 75',
  (select count(*) from public.product where description_html = '')::text || ' / ' || (select count(*) from public.product_family where description_html = '')::text, '1246 / 75');
select pg_temp.chk(:'a8_name',
  (select count(*) from (select pg_temp.vis(x.cin7_description) vs, pg_temp.vis(x.description_html) vr from public.product x where x.description_html is not null :a8_filter) z where not (left(vs, length(vr)) = vr and substring(vs from length(vr) + 1) ~* '^\(barcodes?[:;]?[^()]*\)?$'))::text || ' / ' ||
  (select count(*) from (select pg_temp.vis(x.cin7_description) vs, pg_temp.vis(x.description_html) vr from public.product_family x where x.description_html is not null :a8_filter) z where not (left(vs, length(vr)) = vr and substring(vs from length(vr) + 1) ~* '^\(barcodes?[:;]?[^()]*\)?$'))::text, '0 / 0');
select pg_temp.chk('A9 끝 쓰레기 0: 고친 글이 빈칸 · &nbsp; · <br> · 빈 <p></p> · 여는 태그로 끝나는 행 · 새로 생긴 빈 <ul></ul>',
  (select count(*) from public.product where description_html ~* '(\s|&nbsp;|<br\s*/?>|<p>\s*</p>|<(p|span|li|ul)(\s[^>]*)?>)$')::text || '/' ||
  (select count(*) from public.product_family where description_html ~* '(\s|&nbsp;|<br\s*/?>|<p>\s*</p>|<(p|span|li|ul)(\s[^>]*)?>)$')::text || '/' ||
  (select count(*) from public.product where description_html ~* '<(ul|ol)>\s*</\1>' and cin7_description !~* '<(ul|ol)>\s*</\1>')::text, '0/0/0');

-- ── B) 표본 글 대조(꼴마다) ──
select pg_temp.chk('B1 AMB23457(계기 · 앞 <p>): 끝 = …</ul> · barcode 없음 · is_edited',
  pg_temp.ends((select description_html from public.product where sku = 'AMB23457'), E'<li>Rinse well and pat face and body dry.</li>\n</ul>') || ' | ' || ((select description_html from public.product where sku = 'AMB23457') !~* 'barcode')::text,
  'ends | true');
select pg_temp.chk('B2 AMB23457FAM(제품군 · 줄바꿈 \\r\\n): 끝 = …</ul> · 꺼진 AMB23483 바코드 850004234822 없음',
  pg_temp.ends((select description_html from public.product_family where sku = 'AMB23457FAM'), E'<li>Rinse well and pat face and body dry.</li>\r\n</ul>') || ' | ' || ((select description_html from public.product_family where sku = 'AMB23457FAM') !~ '850004234822')::text,
  'ends | true');
select pg_temp.chk('B3 ANN00220(같은 문단 글 뒤 빈칸): 전체 = <p>4 Color Assorted Rake Comb Dozen</p>',
  (select description_html from public.product where sku = 'ANN00220'), '<p>4 Color Assorted Rake Comb Dozen</p>');
select pg_temp.chk('B4 ADA00008(덩이뿐 「(Barcode: )」): 결과 '''' (일부러 비움)',
  (select '[' || description_html || ']' from public.product where sku = 'ADA00008'), '[]');
select pg_temp.chk('B5 ADG68563(안 닫힘 「(Barcode: …, …</p>」): 끝 = …every time.</p>',
  pg_temp.ends((select description_html from public.product where sku = 'ADG68563'), 'shiny and manageable locs every time.</p>'), 'ends');
select pg_temp.chk('B6 ADO10039FAM(앞 <!-- x-tinymce/html --> 주석): 주석 문단째 사라짐 · 끝 = …extra shine</p>',
  pg_temp.ends((select description_html from public.product_family where sku = 'ADO10039FAM'), 'pastel customization or extra shine</p>') || ' | ' || ((select description_html from public.product_family where sku = 'ADO10039FAM') !~ 'tinymce')::text,
  'ends | true');
select pg_temp.chk('B7 VNA57991(안 &nbsp; · 뒤 빈 문단 <p>&nbsp;</p>): 빈 문단도 사라짐 · 끝 = …damaged hair.</p>',
  pg_temp.ends((select description_html from public.product where sku = 'VNA57991'), 'conditions dry, damaged hair.</p>'), 'ends');
select pg_temp.chk('B8 ASH60447-10(<p><span style> 안 · 안에 <br />): span 문단째 사라짐 · 끝 = …</ul>',
  pg_temp.ends((select description_html from public.product where sku = 'ASH60447-10'), E'roots before washing.</li>\n</ul>') || ' | ' || ((select description_html from public.product where sku = 'ASH60447-10') !~ 'font-size: 8px;">\s*$')::text,
  'ends | true');
select pg_temp.chk('B9 ADA33500(<span …><br />(Barcode)</span></p>): span 과 <br> 사라짐 · 끝 = </p> · barcode 없음',
  pg_temp.tl((select description_html from public.product where sku = 'ADA33500'), 4) || ' | ' || ((select description_html from public.product where sku = 'ADA33500') !~* 'barcode|<br />\s*</span></p>$')::text, '</p> | true');
select pg_temp.chk('B10 가운데 덩이 무변: ASSHBUJOLIE1B27S · BS04702FAM 은 description_html null(Cin7 따름) · 원문에 덩이 그대로',
  (select (description_html is null)::text || '/' || (cin7_description ~ '\(Barcode: 829534403718\)</p><p>PALMA: 2</p>')::text from public.product where sku = 'ASSHBUJOLIE1B27S') || ' ' ||
  (select (description_html is null)::text || '/' || (cin7_description ~ '#4702AST</p>')::text from public.product_family where sku = 'BS04702FAM'), 'true/true true/true');
select pg_temp.chk('B11 덩이 없는 행 무변: 설명에 barcode 가 없는 상품 가운데 고친 것 0(description_html not null 인 행은 전부 원문에 덩이가 있었다)',
  (select count(*) from public.product where description_html is not null and cin7_description !~* '\(\s*barcodes?\y')::text || '/' ||
  (select count(*) from public.product_family where description_html is not null and cin7_description !~* '\(\s*barcodes?\y')::text, '0/0');

-- ── C) 뷰 product_description ──
select pg_temp.chk('C1 뷰 html_effective = 새 글 · is_edited true · edited_by Caleb(AMB23457 · AMB23457FAM)',
  (select (html_effective = p.description_html)::text || '/' || is_edited::text || '/' || (edited_by = :'caleb'::uuid)::text from public.product_description d join public.product p on p.id = d.id where d.kind = 'product' and d.sku = 'AMB23457') || ' ' ||
  (select (html_effective = f.description_html)::text || '/' || is_edited::text || '/' || (edited_by = :'caleb'::uuid)::text from public.product_description d join public.product_family f on f.id = d.id where d.kind = 'family' and d.sku = 'AMB23457FAM'), 'true/true/true true/true/true');
select pg_temp.chk('C2 솎아내기 뷰 product_description_edited: 행 수 = 17086 · differs_from_cin7 전부 true',
  (select count(*)::text || '/' || count(*) filter (where differs_from_cin7)::text from public.product_description_edited), '17086/17086');

-- ── D) Shopify payload(설명은 coalesce 를 직접 읽는다 — 새 글) ──
select pg_temp.chk('D1 payload description_html: 상품 AMB23457 · 제품군 AMB23457FAM 둘 다 barcode 없음 · 상품 쪽 = 새 글 그대로',
  ((public.shop_product_payload(:'test_sid'::uuid, null, (select id from public.product where sku = 'AMB23457'))->>'description_html') !~* 'barcode')::text || '/' ||
  ((public.shop_product_payload(:'test_sid'::uuid, (select id from public.product_family where sku = 'AMB23457FAM'), null)->>'description_html') !~* 'barcode')::text || '/' ||
  ((public.shop_product_payload(:'test_sid'::uuid, null, (select id from public.product where sku = 'AMB23457'))->>'description_html') = (select description_html from public.product where sku = 'AMB23457'))::text, 'true/true/true');

-- ── E) 큐 ──
select pg_temp.chk('E1 열린 상품 큐: 일하는(is_active and live) 스토어 0 · 전체 = begin 앞과 같다(죽은 스토어 줄은 마이그레이션이 지움)',
  (select count(*) from public.shop_push_queue q join public.shop_store s on s.id = q.store_id where q.done_at is null and s.is_active and s.live)::text || ' / ' ||
  (select count(*) from public.shop_push_queue where done_at is null)::text, '0 / ' || :'n_qopen0');

-- ── F) 무접촉 · 문지기 · 임시 함수 ──
select pg_temp.chk('F1 untouched(md5 begin 앞 = 지금): product_update · product_description_guard · shop_product_payload · shop_queue_add · ims_html_forbidden',
  (select md5(prosrc) = :'pu_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_update')::text || '/' ||
  (select md5(prosrc) = :'gd_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'product_description_guard')::text || '/' ||
  (select md5(prosrc) = :'pp_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_product_payload')::text || '/' ||
  (select md5(prosrc) = :'qa_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'shop_queue_add')::text || '/' ||
  (select md5(prosrc) = :'hf_md5_0' from pg_proc where pronamespace = 'public'::regnamespace and proname = 'ims_html_forbidden')::text, 'true/true/true/true/true');
select pg_temp.chk('F2 문지기 트리거 둘 살아 있음(enabled O) · 문은 닫혀 있다(ims.description_door 빈값)',
  (select string_agg(tgname || ':' || tgenabled::text, ',' order by tgname) from pg_trigger where tgname in ('product_description_guard', 'product_family_description_guard')) || ' | ' || coalesce(nullif(current_setting('ims.description_door', true), ''), '(off)'),
  'product_description_guard:O,product_family_description_guard:O | (off)');
update public.product set description_html = 'GUARD-TEST' where sku = 'AMB23457';                 -- 문 없이 쓰면 문지기가 되돌린다(rollback 됨)
select pg_temp.chk('F3 문 없이 쓴 설명은 문지기가 되돌린다(AMB23457 = 새 글 그대로 · GUARD-TEST 아님)',
  ((select description_html from public.product where sku = 'AMB23457') !~ 'GUARD-TEST')::text, 'true');
select pg_temp.chk('F4 public 에 desc_bc_strip 없음(임시 함수만) · ims_staff Caleb 켜짐',
  (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'desc_bc_strip')::text || '/' || (select is_active::text from public.ims_staff where id = :'caleb'::uuid), '0/true');

-- ── 결과 ──
select n, case when ok then 'OK' else 'MISMATCH' end as r, name, case when ok then '' else 'got=' || coalesce(got, '(null)') || ' want=' || coalesce(want, '(null)') end as detail from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as mismatch, :EXPECT_OK as expect_ok from t_res;
select clock_timestamp() - :'t_begin'::timestamptz as begin_to_rollback;
rollback;
select case when (select count(*) from public.product) = :n_prod0 and (select count(*) from public.product_family) = :n_fam0
            and (select count(*) from public.product where description_html is not null) = :pe0 and (select count(*) from public.product_family where description_html is not null) = :fe0
            and (select count(*) from public.shop_push_queue) = :n_q0 and (select count(*) from public.shop_push_queue where done_at is null) = :n_qopen0
            and (select max(updated_at)::text from public.product) = :'pu0'
       then 'Z1 OK real rows unchanged' else 'Z1 MISMATCH real rows changed' end as z1;
