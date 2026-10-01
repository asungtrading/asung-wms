-- img-2 — Cin7 상품 사진을 IMS 저장소로 옮겨 오고 매일 따라가기 · 기록 · 큐 · 못 옮긴 것 · 감시 (2026-10-01 · 판정 195 ~ 197 · 193 · 194 · 188 · 132 · 139 · so-module §33-a · po-module §3-h · asung-wms 스킬 「상품 이미지 파이프라인」)
--   판정 195  병행 기간 내내 매일 따라간다 — 새로 붙거나 바뀐 Cin7 사진만 · IMS 에서 올린 사진(manual)은 건드리지 않는다 · 처음 한 번은 전부(나눠 돌리기)
--   판정 196  활성 상품만 · 비활성은 되살리면 다음 날 매일 회차가 가져온다
--   판정 197  5 MB 넘으면 건너뛰고 기록(skips too_large) · 첫 마른 실행(count) 숫자를 보고 많으면 다시 정한다
--   표 셋     ims_image_sync_runs(회차 기록 · mode count|scan|move · diag jsonb · 쿨다운 가드 · EF 가 90일 정리) · ims_image_sync_queue(scan 이 넣고 move 가 소비 — 큐가 곧 커서 · status pending|done|skipped|failed)
--             ims_image_sync_skips(못 옮긴 것 · 사유 type|too_large|download_failed|upload_failed|insert_failed · 되풀이 횟수는 트리거가 올린다 · upsert 키 cin7_attachment_id)
--   감시      ims_image_sync_health() — 마지막 성공 scan 이 48h 를 넘었거나 한 번도 없으면 행 하나(운영 image_sync_stale 모양 · IMS System Check 에 붙이는 것은 화면 차수) + 큐에 24h 넘게 pending 이 남아 있으면 행 하나
--   권한      셋 다 RLS · select 열림(System Check 가 읽는다) · 쓰기는 service_role(EF)만 — authenticated insert/update/delete revoke · anon 전부 revoke
--   EF        supabase/functions/ims-product-images(index.ts + sync_core.ts · deno test) · 테스트 프로젝트(fazgmyvzzhqybtvtktyg) 전용 · 시작 때 inv_config.db_role = test 확인 · cron 은 supabase/ops/cron.sql [테스트 · Asung-IMS] 절(처음에는 등록하지 않는다 · count 숫자 뒤)
--   검증: ~/asung/prompts/img-2-verify.sql (시험 적용 장치 · 테스트 DB · rollback) · EF 단위 시험 deno test supabase/functions/ims-product-images/sync_core_test.ts
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

-- ═══ ① 회차 기록 ═══════════════════════════════════════════════════════════════════════════════════════════════════
create table if not exists public.ims_image_sync_runs (
  id              bigint generated always as identity primary key,
  started_at      timestamptz not null default now(),
  finished_at     timestamptz,
  ok              boolean not null,
  mode            text not null,
  pages           integer not null default 0,
  products_seen   integer not null default 0,
  matched         integer not null default 0,
  new_attachments integer not null default 0,
  moved           integer not null default 0,
  turned_off      integer not null default 0,
  primary_moved   integer not null default 0,
  skipped         integer not null default 0,
  failed          integer not null default 0,
  error_note      text,
  diag            jsonb,
  constraint ims_image_sync_runs_mode_ck check (mode in ('count', 'scan', 'move'))
);
create index if not exists ims_image_sync_runs_started_idx on public.ims_image_sync_runs (started_at desc);
comment on table public.ims_image_sync_runs is 'ims-product-images EF 회차 기록(img-2 · 2026-10-01) — 세 역할: 관측(diag jsonb · EF 로그는 휘발) · 감시(ims_image_sync_health) · 쿨다운 가드(scan 20h · ok=true 만) · mode count = 세기만(아무것도 안 씀) · scan = 목록 전체 → 큐 · 끄기 · 대표 · move = 큐 소비 · 보존 90일은 EF 가 기록 직후 정리 · 쓰기는 EF(service_role)만';

-- ═══ ② 큐 — scan 이 넣고 move 가 소비(큐가 곧 커서) ═══════════════════════════════════════════════════════════════════
create table if not exists public.ims_image_sync_queue (
  cin7_attachment_id uuid primary key,
  product_id         uuid not null references public.product (id) on delete no action,
  sku                text not null,
  content_type       text not null,
  file_name          text,
  is_default         boolean not null default false,
  status             text not null default 'pending',
  attempts           integer not null default 0,
  byte_size          bigint,
  last_error         text,
  enqueued_at        timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  constraint ims_image_sync_queue_status_ck check (status in ('pending', 'done', 'skipped', 'failed')),
  constraint ims_image_sync_queue_type_ck   check (content_type in ('image/jpeg', 'image/png', 'image/webp'))
);
create index if not exists ims_image_sync_queue_status_idx on public.ims_image_sync_queue (status, enqueued_at);
create index if not exists ims_image_sync_queue_product_idx on public.ims_image_sync_queue (product_id);
comment on table public.ims_image_sync_queue is 'Cin7 첨부 옮기기 큐(img-2) — scan 회차가 「처음 보는 첨부」를 pending 으로 넣고(on_conflict ignore) move 회차가 enqueued_at 순으로 소비한다(내려받기 → 5 MB → 저장소 → product_image) · done | skipped(skips 표에 사유) | failed(다시 pending 으로 돌리면 재시도) · 큐가 곧 이어 달리기 커서 · 쓰기는 EF(service_role)만';

-- ═══ ③ 못 옮긴 것 — 되풀이 횟수는 트리거가 올린다 ══════════════════════════════════════════════════════════════════════
create table if not exists public.ims_image_sync_skips (
  cin7_attachment_id uuid primary key,
  product_id         uuid references public.product (id) on delete no action,
  sku                text not null,
  reason             text not null,
  content_type       text,
  byte_size          bigint,
  note               text,
  first_seen_at      timestamptz not null default now(),
  last_seen_at       timestamptz not null default now(),
  times              integer not null default 1,
  constraint ims_image_sync_skips_reason_ck check (reason in ('type', 'too_large', 'download_failed', 'upload_failed', 'insert_failed'))
);
create or replace function public.ims_image_sync_skips_bump() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  new.times := old.times + 1;
  new.first_seen_at := old.first_seen_at;
  new.last_seen_at := now();
  return new;
end;
$$;
revoke all on function public.ims_image_sync_skips_bump() from public, anon, authenticated;
create trigger ims_image_sync_skips_bump before update on public.ims_image_sync_skips for each row execute function public.ims_image_sync_skips_bump();
comment on table public.ims_image_sync_skips is '옮기지 못한 Cin7 첨부(img-2 · 판정 197) — type(JPEG · PNG · WebP 밖 · PDF 등) · too_large(5 MB 초과) · download_failed · upload_failed · insert_failed · EF 가 on_conflict 로 upsert 하면 트리거가 times 를 올리고 last_seen_at 을 찍는다(first_seen_at 은 그대로) · 쓰기는 EF(service_role)만';

-- ═══ ④ 권한 — select 열림 · 쓰기는 service_role 만 ═══════════════════════════════════════════════════════════════════
alter table public.ims_image_sync_runs  enable row level security;
alter table public.ims_image_sync_queue enable row level security;
alter table public.ims_image_sync_skips enable row level security;
create policy ims_image_sync_runs_select  on public.ims_image_sync_runs  for select to authenticated using (true);
create policy ims_image_sync_queue_select on public.ims_image_sync_queue for select to authenticated using (true);
create policy ims_image_sync_skips_select on public.ims_image_sync_skips for select to authenticated using (true);
revoke all on public.ims_image_sync_runs  from public, anon, authenticated;
revoke all on public.ims_image_sync_queue from public, anon, authenticated;
revoke all on public.ims_image_sync_skips from public, anon, authenticated;
grant select on public.ims_image_sync_runs, public.ims_image_sync_queue, public.ims_image_sync_skips to authenticated;

-- ═══ ⑤ 감시 — 마지막 성공 scan 48h 초과 또는 없음 · 24h 넘게 pending ═══════════════════════════════════════════════════
create or replace function public.ims_image_sync_health()
  returns table (check_key text, category text, title text, hint text, fail_count bigint, sample jsonb)
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  with last_scan as (
    select max(started_at) as last_ok_at, round(extract(epoch from (now() - max(started_at))) / 3600)::int as hours_ago
    from public.ims_image_sync_runs where ok and mode = 'scan'
  ),
  stuck as (
    select count(*) as n, min(enqueued_at) as oldest from public.ims_image_sync_queue where status = 'pending' and enqueued_at < now() - interval '24 hours'
  )
  select 'image_sync_stale', 'warn', 'Cin7 image sync stale',
         'Last successful ims-product-images scan is older than 48h, or it has never run. Check pg_cron ims-image-scan, the IMS_CRON_SECRET secret, and ims_image_sync_runs for the failing run''s error_note/diag.',
         (case when last_ok_at is null or last_ok_at < now() - interval '48 hours' then 1 else 0 end)::bigint,
         jsonb_build_object('last_ok_at', last_ok_at, 'hours_ago', hours_ago)
  from last_scan
  union all
  select 'image_queue_stuck', 'warn', 'Cin7 image queue not draining',
         'Attachments have waited in ims_image_sync_queue for more than 24h. Check pg_cron ims-image-move and ims_image_sync_runs (mode move).',
         n, jsonb_build_object('pending_over_24h', n, 'oldest', oldest)
  from stuck;
$$;
comment on function public.ims_image_sync_health() is 'img-2 감시 두 줄(운영 wms_health_check 의 image_sync_stale 모양) — image_sync_stale: 마지막 성공 scan 48h 초과 또는 한 번도 없음(후자도 warn 이 의도 — cron 등록을 잊어도 조용하지 않게) · image_queue_stuck: 24h 넘게 pending · fail_count 0 이면 정상 · IMS System Check 에 붙이는 것은 화면 차수 · invoker(표 select 열림)';
revoke all on function public.ims_image_sync_health() from public, anon;
grant execute on function public.ims_image_sync_health() to authenticated;

-- ═══ ⑥ 실물 확인 ═══════════════════════════════════════════════════════════════════════════════════════════════════
do $$
declare v_bad text := ''; v_t text;
begin
  foreach v_t in array array['ims_image_sync_runs', 'ims_image_sync_queue', 'ims_image_sync_skips'] loop
    if (select count(*) from pg_policies where schemaname = 'public' and tablename = v_t) <> 1
       or has_table_privilege('authenticated', format('public.%I', v_t), 'insert') or has_table_privilege('authenticated', format('public.%I', v_t), 'update') or has_table_privilege('authenticated', format('public.%I', v_t), 'delete')
       or not has_table_privilege('authenticated', format('public.%I', v_t), 'select') or has_table_privilege('anon', format('public.%I', v_t), 'select') then
      v_bad := v_bad || ' ' || v_t;
    end if;
  end loop;
  if (select count(*) from public.ims_image_sync_health()) <> 2 then v_bad := v_bad || ' health'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM195', message = format('STOP - img-2 is not in place as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
