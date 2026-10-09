-- desc-1b-verify.sql — 상품 설명 칸(판정 381 · 401 · 402): 칸 셋 × 2 · ref_embed_host · ims_html_forbidden · 문지기 · product_update op 둘 · 뷰 둘 (Asung-IMS · 테스트)
--   기대: 시험 갈래(-v mig) OK 35 · 확인 갈래 OK 33(= 35 − 시험 전용 2: G0a · G0b) · MISMATCH 0 · 확인 갈래 전용 줄(\else)은 없다 · 2회차 통과(1회차: T1d 트리거 비트 · T3a 검사 순서 · T3b 한 트랜잭션 now() · T3f/T7c definer 도우미가 RLS 를 못 본다 — 전부 기대 쪽 고침 · DB 는 맞았다)
--   시험 적용(Claude Code): set -o pipefail; psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261009151435_desc_1b_description.sql -f supabase/tests/desc-1b-verify.sql > /tmp/desc-1b.out 2>&1; echo exit=$?
--   확인(Caleb · 적용된 DB): 같은 명령에서 -v mig=… 만 뺀다
--   재료는 가짜만(DESC1B-* 상품 넷 · family 하나 · 직원 둘) · 실제 행은 읽기만(T2b 의 실측 4 상품은 sku 를 읽어 보일 뿐) · 끝은 rollback · 시퀀스 없음(uuid 표)
\set ON_ERROR_STOP on
\pset pager off
\pset format unaligned
\pset tuples_only on
select count(*)::text as real_edited_head from public.product where false \gset

begin;
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
create temp table t_res (n text, ok boolean, got text, want text);
create function pg_temp.chk(p_n text, p_got text, p_want text) returns void language plpgsql security definer as $$
begin
  insert into t_res values (p_n, p_got is not distinct from p_want, p_got, p_want);
  raise notice '% % (got % · want %)', case when p_got is not distinct from p_want then 'OK' else 'MISMATCH' end, p_n, coalesce(p_got, '<null>'), coalesce(p_want, '<null>');
end $$;
create function pg_temp.err(p_sql text) returns text language plpgsql security definer as $$
begin
  execute p_sql; return 'no-error';
exception when others then return sqlstate || ' ' || sqlerrm;
end $$;

-- ═══ G0(시험 전용) — 재발행 원본이 DB 의 마지막 정의인가 · 적용 뒤 md5 가 바뀌었는가 ═══
\if :{?mig}
select pg_temp.chk('G0a product_update prosrc after trial ≠ original bf05913e… (reissued)', (select (md5(p.prosrc) <> 'bf05913e925e23061988e515614f4705')::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname = 'product_update'), 'true');
select pg_temp.chk('G0b trial branch marker', 'trial', 'trial');
\endif

-- ═══ T1 — 칸 · CHECK · 표 · 함수 · 트리거 · 뷰 · 시작값 ═══
select pg_temp.chk('T1a description columns: product 3 · product_family 3 (html text · edited_at timestamptz · edited_by uuid)',
  (select string_agg(table_name || '.' || column_name || ':' || data_type, ',' order by table_name, column_name) from information_schema.columns where table_schema = 'public' and table_name in ('product', 'product_family') and column_name like 'description%'),
  'product.description_edited_at:timestamp with time zone,product.description_edited_by:uuid,product.description_html:text,product_family.description_edited_at:timestamp with time zone,product_family.description_edited_by:uuid,product_family.description_html:text');
select pg_temp.chk('T1b pair CHECK 2 · ref_embed_host 5 iframe rows · kind_ck · host_ck · uk · function · guard triggers 2 · views 2',
  (select count(*) from pg_constraint where conname in ('product_description_pair_ck', 'product_family_description_pair_ck') and contype = 'c')::text || '/' ||
  (select count(*) from public.ref_embed_host where kind = 'iframe' and is_active)::text || '/' ||
  (select count(*) from pg_constraint where conrelid = 'public.ref_embed_host'::regclass and conname in ('ref_embed_host_kind_ck', 'ref_embed_host_host_ck', 'ref_embed_host_kind_host_uk'))::text || '/' ||
  (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('ims_html_forbidden', 'product_description_guard'))::text || '/' ||
  (select string_agg(t.tgname, ',' order by t.tgname) from pg_trigger t where not t.tgisinternal and t.tgname like '%description_guard') || '/' ||
  (select count(*) from pg_views v where v.schemaname = 'public' and v.viewname in ('product_description', 'product_description_edited'))::text,
  '2/5/3/2/product_description_guard,product_family_description_guard/2');
select pg_temp.chk('T1c hosts sorted', (select string_agg(host, ',' order by host) from public.ref_embed_host where kind = 'iframe'), 'facebook.com,www.facebook.com,www.youtube-nocookie.com,www.youtube.com,youtube.com');
select pg_temp.chk('T1d BEFORE ROW trigger order on product: description_guard < sellable_default < sku_lock < touch (alphabetical)',
  (select string_agg(t.tgname, ',' order by t.tgname) from pg_trigger t where not t.tgisinternal and t.tgrelid = 'public.product'::regclass and (t.tgtype & 1) = 1 and (t.tgtype & 2) = 2 and (t.tgtype & 16) = 16),
  'product_description_guard,product_sellable_default,product_sku_lock,product_touch');
select pg_temp.chk('T1e host_ck: upper · spaces · blank refused (23514) · img kind accepted',
  left(pg_temp.err($q$insert into public.ref_embed_host (kind, host) values ('iframe', 'WWW.X.COM')$q$), 5) || '/' || left(pg_temp.err($q$insert into public.ref_embed_host (kind, host) values ('iframe', ' x.com')$q$), 5) || '/' || left(pg_temp.err($q$insert into public.ref_embed_host (kind, host) values ('video', 'x.com')$q$), 5),
  '23514/23514/23514');
savepoint s_t1;
insert into public.ref_embed_host (kind, host, note) values ('img', 'desc1b.test', 'verify');
select pg_temp.chk('T1f img row accepted · updated_by null (postgres · ims_touch) · then rolled back', (select count(*)::text || '/' || coalesce(updated_by::text, 'null') from public.ref_embed_host where host = 'desc1b.test' group by updated_by), '1/null');
rollback to savepoint s_t1;

-- ═══ T2 — ims_html_forbidden ═══
select pg_temp.chk('T2a allowed: youtube iframe · facebook iframe · img any host · formatting with style= · empty · null → {}',
  public.ims_html_forbidden('<p style="color:red"><b>Hi</b> <a href="https://x.com/a">link</a></p><iframe src="https://www.youtube.com/embed/abc" allowfullscreen></iframe><IFRAME SRC=''//www.facebook.com/plugins/video.php?x=1''></IFRAME><img src="https://i.ibb.co/x/y.jpg"><table><tr><td>1</td></tr></table><ul><li>a</li></ul><h2>T</h2>')::text
  || '/' || public.ims_html_forbidden('')::text || '/' || coalesce(public.ims_html_forbidden(null)::text, 'null'), '{}/{}/{}');
select pg_temp.chk('T2b script · onclick · javascript: · powr iframe · object · iframe without src · embed/form/meta/link/base — each named · sorted · distinct',
  public.ims_html_forbidden('<script>alert(1)</script>')::text || '/' || public.ims_html_forbidden('<div onclick="x()">a</div>')::text || '/' || public.ims_html_forbidden('<a href="javascript:void(0)">a</a>')::text || '/' ||
  public.ims_html_forbidden('<iframe src="https://www.powr.io/chat/u/abc#platform=bigcommerce&url=https://designessentials.com/x/"></iframe>')::text || '/' || public.ims_html_forbidden('<object data="x.swf"></object>')::text || '/' ||
  public.ims_html_forbidden('<iframe srcdoc="<b>x</b>"></iframe>')::text || '/' ||
  public.ims_html_forbidden('<EMBED src=a><form action=b><meta http-equiv=refresh><link rel=stylesheet href=c><base href=d><script src=e></script><script>x</script><p onmouseover = "y">')::text,
  '{script}/{event_attr}/{javascript_link}/{iframe_host:www.powr.io}/{object}/{iframe_no_src}/{base,embed,event_attr,form,link,meta,script}');
select pg_temp.chk('T2c youtube iframe + powr iframe together → only powr named · host case-insensitive · http and protocol-relative',
  public.ims_html_forbidden('<iframe src="https://www.youtube.com/embed/a"></iframe><iframe src="HTTP://WWW.POWR.IO/x"></iframe><iframe src=//Youtube.com/embed/b></iframe>')::text, '{iframe_host:www.powr.io}');
select pg_temp.chk('T2d not fooled by prose: "javascript: enabled" in text · "on sale = " in text · "<b>on</b>" → {}',
  public.ims_html_forbidden('<p>Notes on JavaScript: enabled. Items on sale = cheap. <b>on</b> and off</p>')::text, '{}');
select pg_temp.chk('T2e real cin7_description with object|embed|form|meta|link|base: product 4 · family 0 (2026-10-09 실측)',
  (select count(*) from public.product where cin7_description ~* '<(object|embed|form|meta|link|base)[[:space:]>/]')::text || '/' || (select count(*) from public.product_family where cin7_description ~* '<(object|embed|form|meta|link|base)[[:space:]>/]')::text, '4/0');
\echo '── T2e 실측 4 상품에서 걸리는 코드(sku · codes):'
select p.sku || ' · ' || public.ims_html_forbidden(p.cin7_description)::text from public.product p where p.cin7_description ~* '<(object|embed|form|meta|link|base)[[:space:]>/]' order by p.sku;
\echo '── 실측 전수: 걸리는 상품 · family 수(iframe powr 등 포함 · 참고만):'
select 'product ' || count(*) filter (where cardinality(public.ims_html_forbidden(cin7_description)) > 0) || ' / ' || count(*) filter (where cin7_description is not null) from public.product;
select 'family ' || count(*) filter (where cardinality(public.ims_html_forbidden(cin7_description)) > 0) || ' / ' || count(*) filter (where cin7_description is not null) from public.product_family;

-- ═══ 재료(postgres · 가짜) — 직원 둘(master · 없음) · 상품 넷 · family 하나 ═══
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'desc1b-master@test.invalid', 'DESC1B Master', 'manager', '["master"]'::jsonb) returning auth_user_id::text as m_uid \gset
insert into public.ims_staff (auth_user_id, email, name, role, perms) values (gen_random_uuid(), 'desc1b-none@test.invalid',   'DESC1B NoKeys', 'manager', '[]'::jsonb) returning auth_user_id::text as n_uid \gset
select s.id::text as m_sid from public.ims_staff s where s.email = 'desc1b-master@test.invalid' \gset
\set m_claims '{"sub":"' :m_uid '","role":"authenticated"}'
\set n_claims '{"sub":"' :n_uid '","role":"authenticated"}'
insert into public.product_family (sku, name, source, cin7_description) values ('DESC1B-FAM', 'DESC1B Family', 'manual', '<p>family cin7</p>') returning id::text as fam \gset
insert into public.product (sku, name, source, cin7_description, description_html, description_edited_at, description_edited_by)
  values ('DESC1B-P1', 'DESC1B P1', 'manual', '<p>cin7 one</p>', '<p>smuggled</p>', now(), :'m_sid'::uuid) returning id::text as p1 \gset
insert into public.product (sku, name, source, cin7_description) values ('DESC1B-P2', 'DESC1B P2', 'manual', '<p>cin7 two</p>') returning id::text as p2 \gset
insert into public.product (sku, name, source, cin7_description) values ('DESC1B-P3', 'DESC1B P3', 'manual', null) returning id::text as p3 \gset
insert into public.product (sku, name, source, cin7_description) values ('DESC1B-P4', 'DESC1B P4', 'manual', '<p>cin7 four</p>') returning id::text as p4 \gset
select pg_temp.chk('T5a INSERT without the door: smuggled description columns are null (guard) · cin7 kept', (select coalesce(description_html, 'null') || '/' || coalesce(description_edited_at::text, 'null') || '/' || coalesce(description_edited_by::text, 'null') || '/' || cin7_description from public.product where sku = 'DESC1B-P1'), 'null/null/null/<p>cin7 one</p>');
select pg_temp.chk('T5b pair CHECK: html only · edited_at only · by only refused (23514) even with the door open',
  left(pg_temp.err($q$select set_config('ims.description_door', '1', true); update public.product set description_html = 'x' where sku = 'DESC1B-P1'$q$), 5) || '/' ||
  left(pg_temp.err($q$select set_config('ims.description_door', '1', true); update public.product set description_edited_at = now() where sku = 'DESC1B-P1'$q$), 5) || '/' ||
  left(pg_temp.err($q$select set_config('ims.description_door', '1', true); update public.product set description_edited_by = '$q$ || :'m_sid' || $q$' where sku = 'DESC1B-P1'$q$), 5), '23514/23514/23514');
select set_config('ims.description_door', '', true);

-- ═══ T3 — description_set(master 직원 · authenticated) ═══
set local session_replication_role = replica;
update public.product set updated_at = now() - interval '1 hour' where sku like 'DESC1B-%';
set local session_replication_role = origin;
select updated_at::text as p1_upd0 from public.product where sku = 'DESC1B-P1' \gset
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P1', 'html', '<p><b>ims</b> one</p>', 'old', null)), false)::text as t3_pre \gset
select coalesce(description_html, 'null') as t3_pre_html from public.product where sku = 'DESC1B-P1' \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P1', 'html', '<p><b>ims</b> one</p>', 'old', null)), true)::text as t3_set \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P2', 'html', '<p>x</p><script>alert(1)</script><iframe src="https://www.powr.io/a"></iframe>', 'old', null)), true)::text as t3_bad \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P1', 'html', '<p>again</p>', 'old', '<p>stale</p>')), true)::text as t3_stale \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P2', 'old', null)), true)::text as t3_nohtml \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P2', 'html', '<p>a</p>', 'old', null), jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P2', 'html', '<p>b</p>', 'old', null)), true)::text as t3_dup \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P2', 'html', '<p>a</p>')), true)::text as t3_noold \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-NOPE', 'html', '<p>a</p>', 'old', null)), true)::text as t3_nosku \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P3', 'html', '', 'old', null)), true)::text as t3_blank \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P4', 'html', '<p>cin7 four</p>', 'old', null)), true)::text as t3_same \gset
reset role;
select pg_temp.chk('T3a p_commit false: committed false · no change · nothing saved', (:'t3_pre'::jsonb->>'committed') || '/' || (:'t3_pre'::jsonb->'blocks')::text || '/' || :'t3_pre_html', 'false/[]/null');
select pg_temp.chk('T3b commit: committed · applied · html · edited_at = now · edited_by = master staff · updated_at moved', (:'t3_set'::jsonb->>'committed') || '/' || (:'t3_set'::jsonb->'changes'->0->>'applied') || '/' ||
  (select description_html || '/' || (description_edited_at = now())::text || '/' || (description_edited_by = :'m_sid'::uuid)::text || '/' || (updated_at = now() and updated_at > :'p1_upd0'::timestamptz)::text || '/' || (updated_by = :'m_sid'::uuid)::text from public.product where sku = 'DESC1B-P1'), 'true/true/<p><b>ims</b> one</p>/true/true/true/true');
select pg_temp.chk('T3c forbidden html: blocks description_forbidden × 2 (script · iframe_host:www.powr.io) · keys · not saved', (:'t3_bad'::jsonb->>'committed') || '/' || (select string_agg(b->>'key' || '=' || (b->>'detail'), ',' order by b->>'key') from jsonb_array_elements(:'t3_bad'::jsonb->'blocks') b) || '/' || (select coalesce(description_html, 'null') from public.product where sku = 'DESC1B-P2'),
  'false/DESC1B-P2:description_forbidden:iframe_host:www.powr.io=iframe_host:www.powr.io,DESC1B-P2:description_forbidden:script=script/null');
select pg_temp.chk('T3d old mismatch → changed_elsewhere · html missing → html_missing · twice → field_duplicate_in_call · no old → old_missing · unknown sku → sku_unknown',
  (:'t3_stale'::jsonb->'blocks'->0->>'code') || '/' || (:'t3_nohtml'::jsonb->'blocks'->0->>'code') || '/' || (select string_agg(b->>'code', ',') from jsonb_array_elements(:'t3_dup'::jsonb->'blocks') b) || '/' || (:'t3_noold'::jsonb->'blocks'->0->>'code') || '/' || (:'t3_nosku'::jsonb->'blocks'->0->>'code'),
  'changed_elsewhere/html_missing/field_duplicate_in_call/old_missing/sku_unknown');
select pg_temp.chk('T3e blank on purpose: html '''' saved · edited · view html_effective '''' (not cin7) · same-as-cin7 text pins it (edited · differs false)',
  (select (description_html = '')::text || '/' || (description_edited_at is not null)::text from public.product where sku = 'DESC1B-P3') || '/' || (select coalesce(html_effective, 'null') || '|' || is_edited::text from public.product_description where sku = 'DESC1B-P3' and kind = 'product') || '/' ||
  (:'t3_same'::jsonb->>'committed') || '/' || (select is_edited::text || '|' || html_effective from public.product_description where sku = 'DESC1B-P4' and kind = 'product'), 'true/true/|true/true/true|<p>cin7 four</p>');
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
do $$ begin perform public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P2', 'html', '<p>a</p>', 'old', null)), true); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate || ' ' || sqlerrm, true); end $$;
select current_setting('app.out', true) as t3_nokey \gset
do $$ begin update public.product set description_html = 'x', description_edited_at = now(), description_edited_by = null where sku = 'DESC1B-P2'; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as t3_direct \gset
do $$ begin insert into public.ref_embed_host (kind, host) values ('iframe', 'evil.io'); perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as t3_hostins \gset
do $$ begin update public.ref_embed_host set is_active = false where host = 'youtube.com'; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as t3_hostupd \gset
select public.ims_html_forbidden('<script>x</script>')::text as t3_fn \gset
reset role;
select pg_temp.chk('T3f no master key: door refuses (P0001 You cannot change master data …) · direct update → 42501 · ref_embed_host insert/update → 42501 · ims_html_forbidden callable by authenticated',
  (:'t3_nokey' like 'P0001 You cannot change master data%')::text || '/' || left(:'t3_direct', 5) || '/' || left(:'t3_hostins', 5) || '/' || left(:'t3_hostupd', 5) || '/' || :'t3_fn', 'true/42501/42501/42501/{script}');

-- ═══ T4 — description_follow_cin7 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_follow_cin7', 'sku', 'DESC1B-P2', 'old', null)), true)::text as t4_none \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_follow_cin7', 'sku', 'DESC1B-P1', 'old', '<p><b>ims</b> one</p>')), false)::text as t4_pre \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_follow_cin7', 'sku', 'DESC1B-P1', 'old', '<p><b>ims</b> one</p>')), true)::text as t4_do \gset
reset role;
select pg_temp.chk('T4a follow on an unedited product → description_not_edited · preview does not change · commit: three null · view html_effective back to cin7 · is_edited false',
  (:'t4_none'::jsonb->'blocks'->0->>'code') || '/' || (:'t4_pre'::jsonb->>'committed') || '/' || (:'t4_do'::jsonb->>'committed') || '/' ||
  (select coalesce(description_html, 'null') || '|' || coalesce(description_edited_at::text, 'null') || '|' || coalesce(description_edited_by::text, 'null') from public.product where sku = 'DESC1B-P1') || '/' ||
  (select html_effective || '|' || is_edited::text from public.product_description where sku = 'DESC1B-P1' and kind = 'product'), 'description_not_edited/false/true/null|null|null/<p>cin7 one</p>|false');

-- ═══ T5 — 문지기(적재 흉내 · postgres · service_role) ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'sku', 'DESC1B-P2', 'html', '<p>ims two</p>', 'old', null)), true)::text as t5_set \gset
reset role;
select description_edited_at::text as p2_eat from public.product where sku = 'DESC1B-P2' \gset
update public.product set description_html = null, description_edited_at = null, description_edited_by = null, name = 'DESC1B P2 reloaded' where sku = 'DESC1B-P2';
select pg_temp.chk('T5c postgres update nulling the three (no door): kept · name changed · updated_at moved by touch', (select description_html || '/' || (description_edited_at::text = :'p2_eat')::text || '/' || (description_edited_by = :'m_sid'::uuid)::text || '/' || name from public.product where sku = 'DESC1B-P2'), '<p>ims two</p>/true/true/DESC1B P2 reloaded');
update public.product set description_html = '<p>other</p>', description_edited_at = now() - interval '1 day', description_edited_by = null where sku = 'DESC1B-P2';
select pg_temp.chk('T5d postgres update setting other values (no door): kept', (select description_html || '/' || (description_edited_at::text = :'p2_eat')::text from public.product where sku = 'DESC1B-P2'), '<p>ims two</p>/true');
set local role service_role;
update public.product set description_html = null, description_edited_at = null, description_edited_by = null where sku = 'DESC1B-P2';
insert into public.product (sku, name, source, cin7_description, description_html, description_edited_at, description_edited_by)
  values ('DESC1B-P2', 'DESC1B P2', 'cin7', '<p>cin7 two v2</p>', null, null, null)
  on conflict (sku) do update set cin7_description = excluded.cin7_description, description_html = excluded.description_html, description_edited_at = excluded.description_edited_at, description_edited_by = excluded.description_edited_by, source = excluded.source;
reset role;
select pg_temp.chk('T5e service_role: plain update nulling → kept · merge-duplicates-shaped upsert → cin7_description changed · source changed · description kept',
  (select description_html || '/' || (description_edited_at::text = :'p2_eat')::text || '/' || cin7_description || '/' || source from public.product where sku = 'DESC1B-P2'), '<p>ims two</p>/true/<p>cin7 two v2</p>/cin7');
set local role service_role;
insert into public.product (sku, name, source, cin7_description, description_html, description_edited_at, description_edited_by)
  values ('DESC1B-P5', 'DESC1B P5', 'cin7', '<p>cin7 five</p>', '<p>loaded</p>', now(), null)
  on conflict (sku) do update set cin7_description = excluded.cin7_description;
reset role;
select pg_temp.chk('T5f service_role insert carrying description values: nulls (guard INSERT branch) · pair CHECK not hit', (select coalesce(description_html, 'null') || '/' || coalesce(description_edited_at::text, 'null') from public.product where sku = 'DESC1B-P5'), 'null/null');
select pg_temp.chk('T5g the door is transaction-local and off again after the window: current_setting empty', coalesce(current_setting('ims.description_door', true), ''), '');

-- ═══ T6 — family 같은 갈래 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'family_sku', 'DESC1B-FAM', 'html', '<p>ims fam</p>', 'old', null)), true)::text as t6_set \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'family_sku', 'DESC1B-FAM', 'html', '<a href="javascript:x">a</a>', 'old', '<p>ims fam</p>')), true)::text as t6_bad \gset
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_set', 'family_sku', 'DESC1B-NOFAM', 'html', '<p>a</p>', 'old', null)), true)::text as t6_nofam \gset
reset role;
select pg_temp.chk('T6a family set: committed · three filled · changes.sku = family sku · field description · view kind family', (:'t6_set'::jsonb->>'committed') || '/' || (:'t6_set'::jsonb->'changes'->0->>'sku') || '/' || (:'t6_set'::jsonb->'changes'->0->>'field') || '/' ||
  (select description_html || '|' || (description_edited_by = :'m_sid'::uuid)::text from public.product_family where sku = 'DESC1B-FAM') || '/' || (select html_effective || '|' || is_edited::text from public.product_description where kind = 'family' and sku = 'DESC1B-FAM'), 'true/DESC1B-FAM/description/<p>ims fam</p>|true/<p>ims fam</p>|true');
select pg_temp.chk('T6b family forbidden → description_forbidden:javascript_link · unknown family → family_unknown', (:'t6_bad'::jsonb->'blocks'->0->>'key') || '/' || (:'t6_nofam'::jsonb->'blocks'->0->>'code'), 'DESC1B-FAM:description_forbidden:javascript_link/family_unknown');
update public.product_family set description_html = null, description_edited_at = null, description_edited_by = null where sku = 'DESC1B-FAM';
select pg_temp.chk('T6c family guard: postgres nulling → kept', (select description_html from public.product_family where sku = 'DESC1B-FAM'), '<p>ims fam</p>');
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'description_follow_cin7', 'family_sku', 'DESC1B-FAM', 'old', '<p>ims fam</p>')), true)::text as t6_follow \gset
reset role;
select pg_temp.chk('T6d family follow: three null · html_effective = family cin7', (:'t6_follow'::jsonb->>'committed') || '/' || (select coalesce(description_html, 'null') || '|' || coalesce(description_edited_at::text, 'null') from public.product_family where sku = 'DESC1B-FAM') || '/' || (select html_effective from public.product_description where kind = 'family' and sku = 'DESC1B-FAM'), 'true/null|null/<p>family cin7</p>');

-- ═══ T7 — 솎아내기 뷰 ═══
select pg_temp.chk('T7a product_description_edited among fakes: P2 (differs true) · P3 blank (differs true) · P4 same as cin7 (differs false) · P1 · P5 · FAM not listed · edited_by_name = DESC1B Master',
  (select string_agg(sku || ':' || differs_from_cin7::text || ':' || edited_by_name, ',' order by sku) from public.product_description_edited where sku like 'DESC1B-%'), 'DESC1B-P2:true:DESC1B Master,DESC1B-P3:true:DESC1B Master,DESC1B-P4:false:DESC1B Master');
select pg_temp.chk('T7b product_description rows for fakes: 5 products + 1 family · columns', (select count(*)::text || '/' || string_agg(distinct kind, ',' order by kind) from public.product_description where sku like 'DESC1B-%') || '/' ||
  (select string_agg(column_name, ',' order by ordinal_position) from information_schema.columns where table_schema = 'public' and table_name = 'product_description'), '6/family,product/kind,id,sku,name,is_active,html_effective,is_edited,edited_at,edited_by');
set local role anon;
do $$ begin perform count(*) from public.product_description; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as t7_anon1 \gset
do $$ begin perform count(*) from public.product_description_edited; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as t7_anon2 \gset
do $$ begin perform count(*) from public.ref_embed_host; perform set_config('app.out', 'no-error', true); exception when others then perform set_config('app.out', sqlstate, true); end $$;
select current_setting('app.out', true) as t7_anon3 \gset
reset role;
set local role authenticated;
select set_config('request.jwt.claims', :'n_claims', true);
select count(*)::text as t7_auth from public.product_description_edited where sku like 'DESC1B-%' \gset
reset role;
select pg_temp.chk('T7c anon: views · ref_embed_host → 42501 · authenticated (no keys) reads the edited view', left(:'t7_anon1', 5) || '/' || left(:'t7_anon2', 5) || '/' || left(:'t7_anon3', 5) || '/' || :'t7_auth', '42501/42501/42501/3');

-- ═══ T8 — 기존 op 회귀 ═══
set local role authenticated;
select set_config('request.jwt.claims', :'m_claims', true);
select public.product_update(jsonb_build_array(jsonb_build_object('op', 'set', 'sku', 'DESC1B-P1', 'field', 'note', 'value', 'hello', 'old', null), jsonb_build_object('op', 'tag_add', 'sku', 'DESC1B-P1', 'tag', 'Desc1bTag'), jsonb_build_object('op', 'family_head_set', 'family_sku', 'DESC1B-FAM', 'field', 'note', 'value', 'fam note', 'old', null)), true)::text as t8 \gset
select pg_temp.err($q$select public.product_update(jsonb_build_array(jsonb_build_object('op', 'nonsense', 'sku', 'DESC1B-P1')), true)$q$) as t8_unknown \gset
reset role;
select pg_temp.chk('T8a set note · tag_add · family_head_set note still apply · description untouched · Unknown op sentence names the new ops', (:'t8'::jsonb->>'committed') || '/' || (select note || '|' || coalesce(description_html, 'null') from public.product where sku = 'DESC1B-P1') || '/' || (select count(*)::text from public.product_tag where product_id = :'p1'::uuid and tag = 'Desc1bTag') || '/' || (select note from public.product_family where sku = 'DESC1B-FAM') || '/' || (:'t8_unknown' like '%description_set or description_follow_cin7%')::text, 'true/hello|null/1/fam note/true');
select pg_temp.chk('T8b real rows untouched: no real product/family has description_html (fakes only) · guard function revoked from authenticated',
  (select count(*) from public.product where description_html is not null and sku not like 'DESC1B-%')::text || '/' || (select count(*) from public.product_family where description_html is not null and sku not like 'DESC1B-%')::text || '/' || (select has_function_privilege('authenticated', 'public.product_description_guard()', 'execute'))::text, '0/0/false');

-- ═══ 끝 ═══
select 'OK ' || count(*) filter (where ok) || ' · MISMATCH ' || count(*) filter (where not ok) as summary from t_res \gset
\echo '==' :summary
select 'MISMATCH ' || n || ' got=' || coalesce(got, '<null>') || ' want=' || coalesce(want, '<null>') from t_res where not ok;
rollback;
