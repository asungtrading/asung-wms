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
-- supabase/ops/shop-price-sync.sql — Shopify 판매가 · 비교가를 IMS 값으로 한 번에 맞추기 (2026-11-02 · 판정 958 · 967 · shop-price-sync-1)
-- [테스트 · Asung-IMS = IMS 메인(판정 617)] 위 가드(guard-test-only.sql 바이트 복사)가 운영 asung-WMS 를 막는다.
--   왜: 잇기 Apply(10-30 22:43)가 「지금 payload hash」를 shop_product.last_hash 로 심어 한 번도 보낸 적 없는 상품(last_pushed_at null · last_status pending)이
--       Shopify 와 달라도 매일 skipped_same_hash 로 건너뛰어졌다(§0 조사 · 150 대상 전부 hash 같음 · 가격은 link 뒤 안 바뀜).
--   길(Caleb 답 1): shop_product.last_hash 를 null 로 지우고 창구 shop_queue_add(reason price_sync)로 큐에 → 다음 분 cron 42 ims-shop-drain 이 보낸다
--       (EF pushOne 은 last_hash = payload hash 일 때만 건너뛴다) · 묶음 · 쉼 = cron 의 분당 20 건 · throttle 저지선 500 · 40 s 한도 그대로 · 실패는 큐 result/error 에.
--   뺌(Caleb 답 2 · 3): 설명이 빈 대상 5(aone EZB69435FAM · EZB69876FAM / asung EZB69435FAM · EZB69876FAM · BS24510 — EF 가 "" 를 보내 Shopify 설명이 지워진다 · deferred 402)
--       · aone BAB47766 · BAB47050(비교가만 다름 · 화면 영향 없음) ⇒ 목록 안 SKU 라도 그 대상(family)은 통째로 뺀다.
--   사용(실행은 Caleb):
--     dry-run(기본 · 쓰기 0):   psql "$(cat ~/.asung-testdb-url)" -f supabase/ops/shop-price-sync.sql
--     첫 한 개(aone DGR75112): psql "$(cat ~/.asung-testdb-url)" -v commit=1 -v scope=first -f supabase/ops/shop-price-sync.sql   → Shopify 화면 확인(13.39 · 사진 · 다른 칸)
--     나머지 전부:              psql "$(cat ~/.asung-testdb-url)" -v commit=1 -v scope=rest  -f supabase/ops/shop-price-sync.sql
--     확인(보낸 뒤 · 쓰기 0):   psql "$(cat ~/.asung-testdb-url)" -v check=1 -f supabase/ops/shop-price-sync.sql
--     scope 는 first(기본) | rest(first 를 뺀 나머지) | all · commit 을 안 주면 어느 scope 든 dry-run.
--   멱등: last_hash 가 이미 null 이고 열린 큐 줄이 있는 대상은 건너뛴다(창구가 not exists 로 지킨다) · 두 번 돌리면 updated 0 · queued 0.
--   되돌리기: last_hash 는 EF 가 보낸 뒤 다시 쓴다 — 되돌릴 것은 큐 줄뿐(update shop_push_queue set done_at = now(), result = 'error', error = 'cancelled' where reason = 'price_sync' and done_at is null).
--   잠금: 쓰기는 shop_product 행 150 update + 큐 insert 150 — 한 문장씩 ms 단위 · lock_timeout 3 s.
\set ON_ERROR_STOP on
\pset pager off
\if :{?commit}
\else
\set commit 0
\endif
\if :{?scope}
\else
\set scope first
\endif
\if :{?check}
\else
\set check 0
\endif
set lock_timeout = '3s';
set statement_timeout = '25s';
select (:commit::int = 1) as do_commit, (:check::int = 1) as do_check, (:'scope' in ('first', 'rest', 'all')) as scope_ok \gset
\if :scope_ok
\else
\echo 'STOP — scope must be first | rest | all'
\q
\endif
\echo '── mode' :commit '(1 = commit) · scope' :scope '· check' :check

-- ── 대상 SKU(대화 Claude 대조 11-02 · 지시서 목록 그대로 · aone 296 · asung 156) ──
create temp table t_sku (store text, sku text);
insert into t_sku values
('aone', 'ABC59137'),
('aone', 'ABE55504'),
('aone', 'ADO10039'),
('aone', 'ADO10048'),
('aone', 'ADO10069'),
('aone', 'ADO10070'),
('aone', 'ADO10071'),
('aone', 'ADO10078'),
('aone', 'ADO10079'),
('aone', 'ADO10082'),
('aone', 'ADO10083'),
('aone', 'ADO10085'),
('aone', 'ADO10086'),
('aone', 'ADO10090'),
('aone', 'ADO10107'),
('aone', 'ADO10110'),
('aone', 'ADO10113'),
('aone', 'ADO10114'),
('aone', 'ADO10117'),
('aone', 'ADO10118'),
('aone', 'ADO10121'),
('aone', 'ADO10125'),
('aone', 'ADO10130'),
('aone', 'ADO10140'),
('aone', 'ADO10142'),
('aone', 'ADO10150'),
('aone', 'ADO10155'),
('aone', 'ADO10158'),
('aone', 'ADO10161'),
('aone', 'ADO10163'),
('aone', 'ADO10164'),
('aone', 'ADO10165'),
('aone', 'ADO10168'),
('aone', 'ADO10172'),
('aone', 'ADO10174'),
('aone', 'ADO10176'),
('aone', 'ADO10178'),
('aone', 'ADO10186'),
('aone', 'ADO10190'),
('aone', 'ADO10191'),
('aone', 'ADO10192'),
('aone', 'ADO10193'),
('aone', 'ADO10194'),
('aone', 'ADO10195'),
('aone', 'ADO10196'),
('aone', 'ADO10197'),
('aone', 'ADO10198'),
('aone', 'ADO10199'),
('aone', 'ADO10401'),
('aone', 'ADO10402'),
('aone', 'ADO10404'),
('aone', 'ADO10405'),
('aone', 'ADO10408'),
('aone', 'ADO10410'),
('aone', 'ADO10412'),
('aone', 'ADO10413'),
('aone', 'ADO10415'),
('aone', 'ADO10416'),
('aone', 'ADO10417'),
('aone', 'ADO10419'),
('aone', 'ADO10420'),
('aone', 'ADO10421'),
('aone', 'ADO10423'),
('aone', 'ADO10424'),
('aone', 'ADO10425'),
('aone', 'ADO10426'),
('aone', 'AES15404'),
('aone', 'AES68109'),
('aone', 'AIA03501'),
('aone', 'AIA03502'),
('aone', 'AIA03503'),
('aone', 'AIA03504'),
('aone', 'AIA03506'),
('aone', 'AIA03508'),
('aone', 'AIA03530'),
('aone', 'AIA03531'),
('aone', 'AIA03533'),
('aone', 'AIA03534'),
('aone', 'AIA03538'),
('aone', 'AIA03541'),
('aone', 'AMP41200'),
('aone', 'AND17285'),
('aone', 'AND17300'),
('aone', 'ARD70481'),
('aone', 'ARD70482'),
('aone', 'ARD70483'),
('aone', 'ARD70484'),
('aone', 'ARD75941'),
('aone', 'ARD75942'),
('aone', 'ARD75943'),
('aone', 'AS92881'),
('aone', 'AS92882'),
('aone', 'AS93125'),
('aone', 'AS93126'),
('aone', 'AS93800'),
('aone', 'BAB47050'),
('aone', 'BAB47766'),
('aone', 'BIG00094'),
('aone', 'BIG00095'),
('aone', 'BIG00096'),
('aone', 'BIG00097'),
('aone', 'BIG00098'),
('aone', 'BIG00100'),
('aone', 'BIG00101'),
('aone', 'BIG02001'),
('aone', 'BIG02002'),
('aone', 'BIG02003'),
('aone', 'BIG02004'),
('aone', 'BIG02005'),
('aone', 'BIG02006'),
('aone', 'BIG02007'),
('aone', 'BIG02008'),
('aone', 'BIG02009'),
('aone', 'BIG02011'),
('aone', 'BIG02012'),
('aone', 'BIG02013'),
('aone', 'BIG02014'),
('aone', 'BIG02015'),
('aone', 'BIG02016'),
('aone', 'BIG02017'),
('aone', 'BIG02018'),
('aone', 'BMA17210'),
('aone', 'BMA17310'),
('aone', 'BMA17410'),
('aone', 'BMA18310'),
('aone', 'BMA18710'),
('aone', 'BNB00303'),
('aone', 'BNB00305'),
('aone', 'BNB00315'),
('aone', 'BNB00316'),
('aone', 'BNB00416'),
('aone', 'BNB01503'),
('aone', 'BNB01507'),
('aone', 'BNB01514'),
('aone', 'BNB01618'),
('aone', 'BNB01633'),
('aone', 'BNB01634'),
('aone', 'BNB01635'),
('aone', 'BNB01636'),
('aone', 'BS24207'),
('aone', 'BS24208'),
('aone', 'BS2453'),
('aone', 'BSI81592'),
('aone', 'COC02075'),
('aone', 'CYG00151'),
('aone', 'CYG00152'),
('aone', 'CYG00153'),
('aone', 'CYG00154'),
('aone', 'CYG00155'),
('aone', 'CYG00156'),
('aone', 'CYG00181'),
('aone', 'CYG00182'),
('aone', 'CYG00183'),
('aone', 'DGR75112'),
('aone', 'DGR75163'),
('aone', 'DMI00016'),
('aone', 'DOR20002'),
('aone', 'EBI68637'),
('aone', 'EZB68714'),
('aone', 'EZB68715'),
('aone', 'EZB68728'),
('aone', 'EZB68729'),
('aone', 'EZB68730'),
('aone', 'EZB68731'),
('aone', 'EZB69435'),
('aone', 'EZB69436'),
('aone', 'EZB69437'),
('aone', 'EZB69438'),
('aone', 'EZB69443'),
('aone', 'EZB69656'),
('aone', 'EZB69657'),
('aone', 'EZB69672'),
('aone', 'EZB69683'),
('aone', 'EZB69684'),
('aone', 'EZB69685'),
('aone', 'EZB69686'),
('aone', 'EZB69687'),
('aone', 'EZB69688'),
('aone', 'EZB69689'),
('aone', 'EZB69690'),
('aone', 'EZB69691'),
('aone', 'EZB69692'),
('aone', 'EZB69693'),
('aone', 'EZB69726'),
('aone', 'EZB69727'),
('aone', 'EZB69728'),
('aone', 'EZB69731'),
('aone', 'EZB69732'),
('aone', 'EZB69876'),
('aone', 'EZB69877'),
('aone', 'EZB69878'),
('aone', 'EZB69881'),
('aone', 'EZB69883'),
('aone', 'EZB69884'),
('aone', 'EZB69885'),
('aone', 'EZB69961'),
('aone', 'EZB69962'),
('aone', 'EZB69963'),
('aone', 'EZB69964'),
('aone', 'EZB69965'),
('aone', 'EZB69966'),
('aone', 'EZB69967'),
('aone', 'EZB69968'),
('aone', 'EZB69969'),
('aone', 'EZB69970'),
('aone', 'EZB69971'),
('aone', 'EZB69972'),
('aone', 'EZB69973'),
('aone', 'EZB69974'),
('aone', 'EZB69975'),
('aone', 'EZB69976'),
('aone', 'EZB69977'),
('aone', 'EZB69978'),
('aone', 'EZB69979'),
('aone', 'EZB69980'),
('aone', 'EZB69981'),
('aone', 'EZB69982'),
('aone', 'EZB69984'),
('aone', 'EZB70047'),
('aone', 'EZB70048'),
('aone', 'EZB70049'),
('aone', 'EZB70050'),
('aone', 'EZB70090'),
('aone', 'EZB70141'),
('aone', 'EZB70143'),
('aone', 'EZB70144'),
('aone', 'EZB70145'),
('aone', 'EZB70170'),
('aone', 'EZB70249'),
('aone', 'EZB70251'),
('aone', 'EZB70351'),
('aone', 'EZB70352'),
('aone', 'EZB70353'),
('aone', 'EZB70354'),
('aone', 'EZB70355'),
('aone', 'EZB70368'),
('aone', 'EZB70369'),
('aone', 'EZB70370'),
('aone', 'EZB70371'),
('aone', 'EZB70372'),
('aone', 'EZB70422'),
('aone', 'EZB70423'),
('aone', 'EZB70424'),
('aone', 'EZB70425'),
('aone', 'EZB70426'),
('aone', 'GOT34145'),
('aone', 'GOT90929'),
('aone', 'LAC01813'),
('aone', 'LAC37420'),
('aone', 'LAC37421'),
('aone', 'LAC37422'),
('aone', 'LAC73891'),
('aone', 'LAC73892'),
('aone', 'LAC73893'),
('aone', 'LAC74507'),
('aone', 'LAC74508'),
('aone', 'LAC74509'),
('aone', 'LAC78400'),
('aone', 'LAC78416'),
('aone', 'LAC80488'),
('aone', 'LAC80534'),
('aone', 'MNT54344'),
('aone', 'ORS11092'),
('aone', 'PAL02370'),
('aone', 'PAL03313'),
('aone', 'PAL03511'),
('aone', 'PAL04008'),
('aone', 'PAL04158'),
('aone', 'PAL04170'),
('aone', 'PAL05355'),
('aone', 'SMI10137'),
('aone', 'SMI10220'),
('aone', 'SMI10221'),
('aone', 'SSU07380'),
('aone', 'SUN05089'),
('aone', 'SUN05123'),
('aone', 'SUN05124'),
('aone', 'SUN05142'),
('aone', 'SUN05181'),
('aone', 'SUN05182'),
('aone', 'SUN16362'),
('aone', 'SUN32201'),
('aone', 'SUN32203'),
('aone', 'SUN32204'),
('aone', 'SUN32205'),
('aone', 'SUN32206'),
('aone', 'SUN32207'),
('aone', 'SUN81053'),
('aone', 'SUN81071'),
('aone', 'SUN81072'),
('aone', 'TDI26515'),
('aone', 'TDI26516'),
('aone', 'WET56421'),
('aone', 'WET56424'),
('aone', 'WET56427'),
('aone', 'WET56430'),
('asung', 'AES15404'),
('asung', 'AES68109'),
('asung', 'AIA03501'),
('asung', 'AIA03502'),
('asung', 'AIA03503'),
('asung', 'AIA03504'),
('asung', 'AIA03506'),
('asung', 'AIA03508'),
('asung', 'AIA03530'),
('asung', 'AIA03531'),
('asung', 'AIA03533'),
('asung', 'AIA03534'),
('asung', 'AIA03538'),
('asung', 'AIA03539'),
('asung', 'AIA03541'),
('asung', 'AMP41200'),
('asung', 'ARD70481'),
('asung', 'ARD70482'),
('asung', 'ARD70483'),
('asung', 'ARD70484'),
('asung', 'ARD75941'),
('asung', 'ARD75942'),
('asung', 'ARD75943'),
('asung', 'BNB00303'),
('asung', 'BNB00305'),
('asung', 'BNB00315'),
('asung', 'BNB00316'),
('asung', 'BNB00416'),
('asung', 'BNB01503'),
('asung', 'BNB01507'),
('asung', 'BNB01514'),
('asung', 'BNB01618'),
('asung', 'BNB01633'),
('asung', 'BNB01634'),
('asung', 'BNB01635'),
('asung', 'BNB01636'),
('asung', 'BS2405AST'),
('asung', 'BS2405BLA'),
('asung', 'BS24506'),
('asung', 'BS24510'),
('asung', 'BS2453'),
('asung', 'COC02075'),
('asung', 'CYG00151'),
('asung', 'CYG00152'),
('asung', 'CYG00153'),
('asung', 'CYG00154'),
('asung', 'CYG00155'),
('asung', 'CYG00156'),
('asung', 'CYG00181'),
('asung', 'CYG00182'),
('asung', 'CYG00183'),
('asung', 'EZB68714'),
('asung', 'EZB68715'),
('asung', 'EZB68728'),
('asung', 'EZB68729'),
('asung', 'EZB68730'),
('asung', 'EZB68731'),
('asung', 'EZB69435'),
('asung', 'EZB69436'),
('asung', 'EZB69437'),
('asung', 'EZB69438'),
('asung', 'EZB69443'),
('asung', 'EZB69656'),
('asung', 'EZB69657'),
('asung', 'EZB69672'),
('asung', 'EZB69683'),
('asung', 'EZB69684'),
('asung', 'EZB69685'),
('asung', 'EZB69686'),
('asung', 'EZB69687'),
('asung', 'EZB69688'),
('asung', 'EZB69689'),
('asung', 'EZB69690'),
('asung', 'EZB69691'),
('asung', 'EZB69692'),
('asung', 'EZB69693'),
('asung', 'EZB69726'),
('asung', 'EZB69727'),
('asung', 'EZB69728'),
('asung', 'EZB69730'),
('asung', 'EZB69731'),
('asung', 'EZB69732'),
('asung', 'EZB69876'),
('asung', 'EZB69877'),
('asung', 'EZB69878'),
('asung', 'EZB69881'),
('asung', 'EZB69883'),
('asung', 'EZB69884'),
('asung', 'EZB69885'),
('asung', 'EZB69961'),
('asung', 'EZB69962'),
('asung', 'EZB69963'),
('asung', 'EZB69964'),
('asung', 'EZB69965'),
('asung', 'EZB69966'),
('asung', 'EZB69967'),
('asung', 'EZB69968'),
('asung', 'EZB69969'),
('asung', 'EZB69970'),
('asung', 'EZB69971'),
('asung', 'EZB69972'),
('asung', 'EZB69973'),
('asung', 'EZB69974'),
('asung', 'EZB69975'),
('asung', 'EZB69976'),
('asung', 'EZB69977'),
('asung', 'EZB69978'),
('asung', 'EZB69979'),
('asung', 'EZB69980'),
('asung', 'EZB69981'),
('asung', 'EZB69982'),
('asung', 'EZB69984'),
('asung', 'EZB70047'),
('asung', 'EZB70048'),
('asung', 'EZB70049'),
('asung', 'EZB70050'),
('asung', 'EZB70090'),
('asung', 'EZB70141'),
('asung', 'EZB70143'),
('asung', 'EZB70144'),
('asung', 'EZB70145'),
('asung', 'EZB70170'),
('asung', 'EZB70249'),
('asung', 'EZB70251'),
('asung', 'EZB70422'),
('asung', 'EZB70423'),
('asung', 'EZB70424'),
('asung', 'EZB70425'),
('asung', 'EZB70426'),
('asung', 'LAC01813'),
('asung', 'LAC37420'),
('asung', 'LAC37421'),
('asung', 'LAC37422'),
('asung', 'LAC73891'),
('asung', 'LAC73892'),
('asung', 'LAC73893'),
('asung', 'LAC74507'),
('asung', 'LAC74508'),
('asung', 'LAC74509'),
('asung', 'LAC78400'),
('asung', 'LAC80488'),
('asung', 'LAC80534'),
('asung', 'ORS11092'),
('asung', 'PAL02370'),
('asung', 'PAL02510'),
('asung', 'PAL03510'),
('asung', 'PAL03511'),
('asung', 'PAL04158'),
('asung', 'PAL04170'),
('asung', 'PAL05355'),
('asung', 'SUN32201'),
('asung', 'SUN32203'),
('asung', 'SUN32204'),
('asung', 'SUN32205'),
('asung', 'SUN32206'),
('asung', 'SUN32207');
-- 뺄 대상(Caleb 답 2 · 3) — SKU 또는 family SKU
create temp table t_excl (store text, sku text, why text);
insert into t_excl values
  ('aone',  'EZB69435FAM', 'description empty (deferred 402)'),
  ('aone',  'EZB69876FAM', 'description empty (deferred 402)'),
  ('asung', 'EZB69435FAM', 'description empty (deferred 402)'),
  ('asung', 'EZB69876FAM', 'description empty (deferred 402)'),
  ('asung', 'BS24510',     'description empty (deferred 402)'),
  ('aone',  'BAB47766',    'compare-at only (Caleb 11-02)'),
  ('aone',  'BAB47050',    'compare-at only (Caleb 11-02)');

-- ── SKU → 대상(family | 낱개) ──
create temp table t_tg as
select distinct t.store, s.id as store_id, p.family_id as fid, case when p.family_id is null then p.id end as pid,
       coalesce(f.sku, p.sku) as tsku, count(*) over (partition by t.store, coalesce(f.sku, p.sku)) as skus
  from t_sku t
  join public.product p on p.sku = t.sku
  join public.shop_store s on s.code = t.store
  left join public.product_family f on f.id = p.family_id;
alter table t_tg add column excl text, add column in_scope boolean;
update t_tg g set excl = e.why from t_excl e where e.store = g.store and (e.sku = g.tsku or e.sku in (select p.sku from public.product p where p.family_id = g.fid));
update t_tg g set in_scope = case :'scope' when 'first' then g.store = 'aone' and g.tsku = 'DGR75112' when 'rest' then not (g.store = 'aone' and g.tsku = 'DGR75112') else true end;

select count(*) as n_sku_listed, (select count(*) from t_sku t where not exists (select 1 from public.product p where p.sku = t.sku)) as n_sku_unknown from t_sku \gset
\echo '── SKU' :n_sku_listed '· product 에 없음' :n_sku_unknown
\if :do_check
\else
-- ── 상태(dry-run · 쓰기 0) ──
create temp table t_st as
select g.*, l.is_on, sp.id as sp_id, sp.last_hash, sp.last_pushed_at, sp.last_status,
       (public.shop_product_payload(g.store_id, g.fid, g.pid)) as pl,
       exists (select 1 from public.shop_push_queue q where q.store_id = g.store_id and q.done_at is null and q.family_id is not distinct from g.fid and q.product_id is not distinct from g.pid) as q_open
  from t_tg g
  left join public.shop_listing l on l.store_id = g.store_id and l.family_id is not distinct from g.fid and l.product_id is not distinct from g.pid
  left join public.shop_product sp on sp.store_id = g.store_id and sp.family_id is not distinct from g.fid and sp.product_id is not distinct from g.pid;
\echo '── 대상(스토어별) — targets = Shopify 상품 수 · excluded 는 보내지 않는다 · same_hash = 지금대로면 건너뛰어질 것'
select store, count(*) as targets, sum(skus) as skus,
       count(*) filter (where excl is not null) as excluded,
       count(*) filter (where in_scope and excl is null) as to_send,
       count(*) filter (where in_scope and excl is null and last_hash = pl->>'hash') as same_hash,
       count(*) filter (where in_scope and excl is null and last_hash is null) as hash_null,
       count(*) filter (where in_scope and excl is null and q_open) as q_open,
       count(*) filter (where in_scope and excl is null and coalesce(is_on, false) = false) as listing_off,
       count(*) filter (where in_scope and excl is null and sp_id is null) as no_shop_product,
       count(*) filter (where in_scope and excl is null and jsonb_array_length(pl->'blocks') > 0) as blocked,
       count(*) filter (where in_scope and excl is null and coalesce(pl->>'description_html', '') = '') as desc_empty,
       count(*) filter (where in_scope and excl is null and last_pushed_at is not null) as pushed_before
  from t_st group by 1 order by 1;
\echo '── 뺀 대상'
select store, tsku, skus, excl from t_st where excl is not null order by 1, 2;
\echo '── 막힌 · 꺼진 · 설명 빈 대상(있으면 보내지 않는다)'
select store, tsku, case when coalesce(is_on, false) = false then 'listing_off' when sp_id is null then 'no_shop_product' when jsonb_array_length(pl->'blocks') > 0 then 'blocked: ' || (pl->'blocks')::text else 'desc_empty' end as why
  from t_st where in_scope and excl is null and (coalesce(is_on, false) = false or sp_id is null or jsonb_array_length(pl->'blocks') > 0 or coalesce(pl->>'description_html', '') = '') order by 1, 2;
\echo '── 보낼 값 보기(scope first 면 DGR75112 · 그 밖엔 앞 5 줄)'
select st.store, st.tsku, v->>'sku' as sku, v->>'price' as price, v->>'compare_at_price' as compare_at, st.pl->>'status' as status, jsonb_array_length(st.pl->'variants') as variants, jsonb_array_length(st.pl->'files') as files
  from t_st st, jsonb_array_elements(st.pl->'variants') v where st.in_scope and st.excl is null order by 1, 2, 3 limit 5;

-- 보낼 대상 = scope 안 · 안 뺌 · listing 켜짐 · shop_product 있음 · blocks 0 · 설명 있음
create temp table t_go as select * from t_st where in_scope and excl is null and coalesce(is_on, false) and sp_id is not null and jsonb_array_length(pl->'blocks') = 0 and coalesce(pl->>'description_html', '') <> '';
select count(*) as n_go, count(*) filter (where last_hash is not null) as n_hash_to_clear, count(*) filter (where not q_open) as n_to_queue from t_go \gset
\echo '── 보낼 대상' :n_go '· last_hash 지울 것' :n_hash_to_clear '· 큐에 세울 것' :n_to_queue

\if :do_commit
begin;
update public.shop_product sp set last_hash = null
  from t_go g where sp.id = g.sp_id and sp.last_hash is not null;
select count(*) as cleared from t_go g join public.shop_product sp on sp.id = g.sp_id where sp.last_hash is null \gset
-- 창구 shop_queue_add — 낱개를 주면 그 family · 세트 자식도 덧붙이므로 family 대상은 fid 로 · 낱개는 pid 로 · 스토어마다 한 번
select coalesce(sum(public.shop_queue_add(
         (select array_agg(fid) from t_go x where x.store_id = s.store_id and x.fid is not null),
         (select array_agg(pid) from t_go x where x.store_id = s.store_id and x.pid is not null),
         'price_sync', s.store_id)), 0) as queued
  from (select distinct store_id from t_go) s \gset
\echo '── last_hash 지움' :cleared '· 큐에 세움' :queued '(예상' :n_to_queue '— 더 많으면 창구가 세트 자식 · family 를 덧붙인 것 · 그 줄은 skipped_same_hash 로 끝난다)'
\echo '── 큐 줄(price_sync · 열림)'
select s.code, count(*) as open_rows, min(q.queued_at) as queued_at from public.shop_push_queue q join public.shop_store s on s.id = q.store_id where q.reason = 'price_sync' and q.done_at is null group by 1 order by 1;
commit;
\echo '── commit — 다음 분 cron 42 ims-shop-drain 이 보낸다(분당 ≤ 20 건) · 확인은 -v check=1'
\else
\echo '── dry-run — 바꾼 것 없음 (보내려면 -v commit=1)'
\endif
\endif

\if :do_check
-- ── 확인(쓰기 0): 큐 결과 · shop_product 갱신 ──
\echo '── price_sync 큐 결과'
select s.code, q.result, count(*) as rows, min(q.done_at) as first_done, max(q.done_at) as last_done
  from public.shop_push_queue q join public.shop_store s on s.id = q.store_id where q.reason = 'price_sync' group by 1, 2 order by 1, 2;
\echo '── 실패 · 열린 줄'
select s.code, coalesce(f.sku, p.sku) as tsku, q.result, left(q.error, 160) as error, q.queued_at, q.started_at
  from public.shop_push_queue q join public.shop_store s on s.id = q.store_id
  left join public.product_family f on f.id = q.family_id left join public.product p on p.id = q.product_id
 where q.reason = 'price_sync' and (q.result is distinct from 'ok') order by 1, 2;
\echo '── 대상 shop_product(스토어별) — pushed = last_pushed_at 이 오늘 이후 · hash_null = 아직 안 간 것'
select g.store, count(*) as targets, count(*) filter (where g.excl is not null) as excluded,
       count(*) filter (where g.excl is null and sp.last_pushed_at >= public.ims_today()::timestamptz) as pushed_today,
       count(*) filter (where g.excl is null and sp.last_hash is null) as hash_null,
       count(*) filter (where g.excl is null and sp.last_status = 'ok') as status_ok,
       count(*) filter (where g.excl is null and sp.last_status = 'error') as status_error,
       max(sp.last_pushed_at) as last_pushed
  from t_tg g left join public.shop_product sp on sp.store_id = g.store_id and sp.family_id is not distinct from g.fid and sp.product_id is not distinct from g.pid
 group by 1 order by 1;
\echo '── DGR75112(aone)'
select sp.last_status, sp.last_pushed_at, sp.last_hash is not null as has_hash, left(sp.last_error, 120) as last_error
  from public.shop_product sp join public.shop_store s on s.id = sp.store_id join public.product p on p.id = sp.product_id where s.code = 'aone' and p.sku = 'DGR75112';
\endif
