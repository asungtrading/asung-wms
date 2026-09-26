-- ⑤-1 WMS 표 — IMS 안의 WMS 표를 세운다 (2026-09-26 UTC · 토론토 2026-09-26 오후)
-- 정본 so-module §24(판정 1′ · 3 · 4 · 6 · 13 · 14 · 15 · ⬜1~⬜14) · 지시서 ~/asung/prompts/wms-5-1.md · 판정 회신 wms-5-1-rulings.md
-- 대상: [테스트 · Asung-IMS] 만 — psql -v ON_ERROR_STOP=1 -1 -f 로 적용(파일 안에 begin/commit 없음) · 시험 적용 + 검증 ~/asung/prompts/wms-5-1-verify.sql(-v mig)
-- ⛔⛔ 절대 조건(Caleb 2026-09-26): 운영 WMS(asung-WMS · wms.asung.ca)는 어떤 경우에도 멈추면 안 된다.
--     첫 문장 = 운영 가드(판정 13 · 원본 supabase/ops/guard-test-only.sql 의 글자를 그대로 복사 · 검증 G0 이 같음을 잰다).
--     흔적 셋 중 하나라도 있으면 WM501 로 멈춘다(OR · fail-closed): cron.job 에 wms-poll-orders/wms-auto-hold · inv_config.db_role <> 'test' · wms_health_runs 행 > 0
-- 하는 일(§1 순서):
--   0. 가드
--   1. 옛 wms_ 26 표 + 뷰 1 + 함수 13 → 스키마 wms_legacy(판정 3 · 15 · 행째 · 지우지 않는다 · identity 시퀀스·제약·인덱스·정책은 표를 따라간다)
--      revoke usage on schema wms_legacy from anon, authenticated(PostgREST 노출 스키마는 public·graphql_public — 선례 reload_backup)
--   2. public 에 ② 13 + wms_worker_mistakes 를 IMS 모양으로(⬜2 PK bigint identity 유지 · ① 을 가리키는 칸만 uuid · 사람 칸 전부 ims_staff.id · 판정 4)
--      FK: so · so_line · po_receipt · ims_staff · ref_warehouse 는 restrict(⬜3) · wms_reports·wms_rollback_log 의 order_id 는 set null 유지 · ② 끼리는 운영 값 그대로(cascade 7 · no action)
--      복사 칸(⬜4): pallet_items.order_sku·product_name 없앰 · rollback_log·archive·reports·mistakes 의 order_number 류는 「그때의 기록」으로 남김
--      쓰기 규칙 auth_all 그대로(판정 6) · rollback_archive 는 append-only 둘(insert · select)
--   3. 뷰 wms_order_pack_progress 를 새 표 위에 같은 이름·같은 칸(order_id uuid)·security_invoker(⬜12)
--   4. comment on — 표마다 한 줄
-- ⚠️ 이 차수가 정하지 않고 넘긴 것(보고에 적었다): wms_task_holds.task_kind 에서 'receipt'·source 'partial' 을 뺐다(receipt 는 ① · task_id bigint 가 po_receipt uuid 를 못 든다 · ⑤-3 에서 판정) ·
--    wms_drop_locations·wms_zone_sequence 의 warehouse text → warehouse_id uuid(ref_warehouse) · wms_zone_sequence 23행은 wms_legacy 에서 ⑤-4 때 옮겨 심는다
-- ⚠️ 운영 함수 이름 13 은 ⑤-2 가 public 에 새로 세운다 — 그때까지 rpc/wms_* 는 404(깨끗한 실패) · so_status_guard 짝(at_wms · picking · packed)도 ⑤-2
-- ⚠️ 번호 시퀀스(so · 인보이스 · 크레딧)는 이 파일이 건드리지 않는다 · 창구를 부르지 않는다

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

-- ═══ 1) 옛 wms_ 26 표 + 뷰 1 + 함수 13 → wms_legacy (판정 3 · 15) ═══
create schema if not exists wms_legacy;
revoke usage on schema wms_legacy from anon, authenticated;
comment on schema wms_legacy is '⑤-1 (2026-09-26) — 운영 WMS 표·뷰·함수의 복사본을 행째 보관(so-module §24 판정 3·15). PostgREST 에 노출되지 않는다 · IMS 는 이 스키마를 읽지 않는다 · 컷오버 이월 재료';

alter view public.wms_order_pack_progress set schema wms_legacy;

alter table public.wms_discrepancies        set schema wms_legacy;
alter table public.wms_drop_locations       set schema wms_legacy;
alter table public.wms_health_runs          set schema wms_legacy;
alter table public.wms_image_sync_runs      set schema wms_legacy;
alter table public.wms_order_lines          set schema wms_legacy;
alter table public.wms_orders               set schema wms_legacy;
alter table public.wms_pack_task_lines      set schema wms_legacy;
alter table public.wms_pack_tasks           set schema wms_legacy;
alter table public.wms_pallet_items         set schema wms_legacy;
alter table public.wms_pallets              set schema wms_legacy;
alter table public.wms_pick_task_lines      set schema wms_legacy;
alter table public.wms_pick_tasks           set schema wms_legacy;
alter table public.wms_polled_sales         set schema wms_legacy;
alter table public.wms_receipt_lines        set schema wms_legacy;
alter table public.wms_receipt_stage_events set schema wms_legacy;
alter table public.wms_receipts             set schema wms_legacy;
alter table public.wms_refresh_requests     set schema wms_legacy;
alter table public.wms_reports              set schema wms_legacy;
alter table public.wms_rollback_archive     set schema wms_legacy;
alter table public.wms_rollback_log         set schema wms_legacy;
alter table public.wms_sku_bins             set schema wms_legacy;
alter table public.wms_sku_snapshot         set schema wms_legacy;
alter table public.wms_staff                set schema wms_legacy;
alter table public.wms_task_holds           set schema wms_legacy;
alter table public.wms_waves                set schema wms_legacy;
alter table public.wms_zone_sequence        set schema wms_legacy;

-- 함수 13(판정 15) — 시그니처는 테스트 DB pg_proc 실측(2026-09-26) · ⑤-2 가 같은 이름을 public 에 새로 세운다
alter function public.wms_auto_hold()                                                       set schema wms_legacy;
alter function public.wms_can_manage_staff()                                                set schema wms_legacy;
alter function public.wms_complete_pack(bigint, jsonb, jsonb, jsonb, jsonb, jsonb, text)    set schema wms_legacy;
alter function public.wms_complete_pick(jsonb, bigint, bigint, jsonb, jsonb, jsonb, text)   set schema wms_legacy;
alter function public.wms_health_check()                                                    set schema wms_legacy;
alter function public.wms_health_snapshot()                                                 set schema wms_legacy;
alter function public.wms_hold_pack(bigint, jsonb, text)                                    set schema wms_legacy;
alter function public.wms_hold_pick(jsonb, bigint, bigint, text)                            set schema wms_legacy;
alter function public.wms_is_admin()                                                        set schema wms_legacy;
alter function public.wms_pause_receipt(bigint, text)                                       set schema wms_legacy;
alter function public.wms_reap_stale_claims()                                               set schema wms_legacy;
alter function public.wms_resume_hold(text, bigint)                                         set schema wms_legacy;
alter function public.wms_warehouse_bins(text)                                              set schema wms_legacy;

-- ═══ 2) public 에 ② 13 + wms_worker_mistakes — IMS 모양 ═══
-- 공통: id bigint identity(⬜2 · 옛 표와 같은 ALWAYS/BY DEFAULT) · 사람 칸 uuid → ims_staff(id) restrict(판정 4) · order_id uuid → so(id) · order_line_id uuid → so_line(id) · receipt_id uuid → po_receipt(id)

create table public.wms_waves (
  id            bigint generated always as identity primary key,
  label         text not null unique,
  warehouse_id  uuid not null references public.ref_warehouse (id) on delete restrict,
  status        text not null default 'pending',
  assigned_to   uuid references public.ims_staff (id) on delete restrict,
  created_by    uuid references public.ims_staff (id) on delete restrict,
  created_at    timestamptz not null default now(),
  started_at    timestamptz,
  heartbeat_at  timestamptz,
  completed_at  timestamptz,
  held_by       uuid references public.ims_staff (id) on delete restrict,
  session_id    text
);
create index idx_waves_status on public.wms_waves (status);

create table public.wms_pick_tasks (
  id            bigint generated always as identity primary key,
  order_id      uuid not null references public.so (id) on delete restrict,
  batch_label   text,
  assigned_to   uuid references public.ims_staff (id) on delete restrict,
  status        text not null default 'pending',
  created_at    timestamptz default now(),
  started_at    timestamptz,
  completed_at  timestamptz,
  drop_location text,
  created_by    uuid references public.ims_staff (id) on delete restrict,
  heartbeat_at  timestamptz,
  work_started  boolean not null default false,
  wave_id       bigint references public.wms_waves (id),
  tote_no       integer,
  held_by       uuid references public.ims_staff (id) on delete restrict,
  completed_by  uuid references public.ims_staff (id) on delete restrict,
  session_id    text,
  constraint wms_pick_tasks_status_check check (status in ('pending', 'in_progress', 'completed'))
);
create index idx_picktasks_assignee on public.wms_pick_tasks (assigned_to);
create index idx_picktasks_lease    on public.wms_pick_tasks (status, heartbeat_at) where status = 'in_progress';
create index idx_picktasks_order    on public.wms_pick_tasks (order_id);
create index idx_picktasks_wave     on public.wms_pick_tasks (wave_id) where wave_id is not null;

create table public.wms_pick_task_lines (
  id                  bigint generated always as identity primary key,
  pick_task_id        bigint not null references public.wms_pick_tasks (id) on delete cascade,
  order_line_id       uuid not null references public.so_line (id) on delete restrict,
  assigned_base       numeric not null,
  picked_base         numeric not null default 0,
  status              text not null default 'pending',
  verification_method text,
  created_at          timestamptz default now(),
  picked_at           timestamptz,
  picked_by           uuid references public.ims_staff (id) on delete restrict,
  constraint wms_pick_task_lines_status_check check (status in ('pending', 'in_progress', 'picked', 'short')),
  constraint wms_pick_task_lines_verification_method_check check (verification_method in ('scanned_variant', 'scanned_base', 'manual'))
);
create index idx_pticklines_orderline on public.wms_pick_task_lines (order_line_id);
create index idx_pticklines_task      on public.wms_pick_task_lines (pick_task_id);

create table public.wms_pack_tasks (
  id            bigint generated always as identity primary key,
  order_id      uuid not null references public.so (id) on delete restrict,
  pick_task_id  bigint not null references public.wms_pick_tasks (id),
  batch_label   text,
  assigned_to   uuid references public.ims_staff (id) on delete restrict,
  status        text not null default 'pending',
  created_at    timestamptz default now(),
  started_at    timestamptz,
  completed_at  timestamptz,
  heartbeat_at  timestamptz,
  work_started  boolean not null default false,
  held_by       uuid references public.ims_staff (id) on delete restrict,
  completed_by  uuid references public.ims_staff (id) on delete restrict,
  session_id    text,
  constraint wms_pack_tasks_status_check check (status in ('pending', 'in_progress', 'completed'))
);
create index        idx_packtasks_lease on public.wms_pack_tasks (status, heartbeat_at) where status = 'in_progress';
create index        idx_packtasks_order on public.wms_pack_tasks (order_id);
create unique index uq_packtasks_pick   on public.wms_pack_tasks (pick_task_id);

create table public.wms_pack_task_lines (
  id                  bigint generated always as identity primary key,
  pack_task_id        bigint not null references public.wms_pack_tasks (id) on delete cascade,
  order_line_id       uuid not null references public.so_line (id) on delete restrict,
  expected_base       numeric not null,
  verified_base       numeric not null default 0,
  status              text not null default 'pending',
  verification_method text,
  created_at          timestamptz default now(),
  verified_at         timestamptz,
  verified_by         uuid references public.ims_staff (id) on delete restrict,
  constraint wms_pack_task_lines_status_check check (status in ('pending', 'in_progress', 'verified', 'mismatch')),
  constraint wms_pack_task_lines_verification_method_check check (verification_method in ('scanned_variant', 'scanned_base', 'manual'))
);
create index idx_packlines_task on public.wms_pack_task_lines (pack_task_id);

create table public.wms_pallets (
  id            bigint generated always as identity primary key,
  status        text not null default 'building',
  weight_note   text,
  height_note   text,
  created_at    timestamptz default now(),
  completed_at  timestamptz,
  unit_type     text default 'pallet',
  order_id      uuid references public.so (id) on delete restrict,
  label         text,
  parent_id     bigint references public.wms_pallets (id),
  created_by    uuid references public.ims_staff (id) on delete restrict,
  constraint wms_pallets_status_check    check (status in ('building', 'completed')),
  constraint wms_pallets_unit_type_check check (unit_type in ('pallet', 'box'))
);

create table public.wms_pallet_items (
  id            bigint generated always as identity primary key,
  pallet_id     bigint not null references public.wms_pallets (id) on delete cascade,
  pack_task_id  bigint references public.wms_pack_tasks (id),
  order_id      uuid references public.so (id) on delete restrict,
  created_at    timestamptz default now(),
  order_line_id uuid references public.so_line (id) on delete restrict,
  qty_base      integer,
  from_drop     text
);
create index idx_palletitems_pallet on public.wms_pallet_items (pallet_id);

create table public.wms_task_holds (
  id          bigint generated always as identity primary key,
  task_kind   text not null,
  task_id     bigint not null,
  worker      uuid not null references public.ims_staff (id) on delete restrict,
  held_at     timestamptz not null default now(),
  resumed_at  timestamptz,
  resumed_by  uuid references public.ims_staff (id) on delete restrict,
  source      text not null default 'manual',
  constraint wms_task_holds_task_kind_check check (task_kind in ('pick', 'pack', 'wave')),
  constraint wms_task_holds_source_check    check (source in ('manual', 'auto'))
);

create table public.wms_rollback_log (
  id              bigint generated by default as identity primary key,
  order_id        uuid references public.so (id) on delete set null,
  order_number    text,
  action          text not null,
  from_stage      text,
  to_stage        text,
  performed_by    uuid references public.ims_staff (id) on delete restrict,
  note            text,
  created_at      timestamptz not null default now(),
  batch_label     text,
  original_worker uuid references public.ims_staff (id) on delete restrict
);
create index idx_rollback_created on public.wms_rollback_log (created_at desc);
create index idx_rollback_order   on public.wms_rollback_log (order_id);

create table public.wms_rollback_archive (
  id           bigint generated always as identity primary key,
  archived_at  timestamptz not null default now(),
  archived_by  uuid references public.ims_staff (id) on delete restrict,
  action       text not null,
  order_id     uuid,
  order_number text,
  batch_label  text,
  src_table    text not null,
  row_data     jsonb not null
);
create index idx_rb_archive_order on public.wms_rollback_archive (order_id);
create index idx_rb_archive_at    on public.wms_rollback_archive (archived_at);

create table public.wms_reports (
  id           bigint generated by default as identity primary key,
  order_id     uuid references public.so (id) on delete set null,
  order_number text,
  sku          text,
  kind         text not null,
  note         text,
  reported_by  uuid references public.ims_staff (id) on delete restrict,
  source       text,
  resolved_by  uuid references public.ims_staff (id) on delete restrict,
  resolved_at  timestamptz,
  created_at   timestamptz not null default now(),
  receipt_id   uuid references public.po_receipt (id) on delete set null,
  po_number    text
);
create index idx_reports_open  on public.wms_reports (created_at desc) where resolved_at is null;
create index idx_reports_order on public.wms_reports (order_id);
alter table public.wms_reports
  add constraint wms_reports_kind_check check (kind in (
    'wrong_location',    -- picker 전용
    'barcode_mismatch',  -- picker + packer + receiver
    'image_mismatch',    -- picker + packer + receiver (토글)
    'box_barcode'        -- receiver 전용
  ));

create table public.wms_drop_locations (
  id            bigint generated always as identity primary key,
  location_code text not null unique,
  name          text,
  warehouse_id  uuid references public.ref_warehouse (id) on delete restrict,
  active        boolean not null default true,
  created_at    timestamptz default now()
);

create table public.wms_zone_sequence (
  id             bigint generated always as identity primary key,
  warehouse_id   uuid not null references public.ref_warehouse (id) on delete restrict,
  zone           text not null,
  sequence_order integer not null,
  center_x       numeric,
  center_y       numeric,
  active         boolean not null default true,
  constraint wms_zone_sequence_warehouse_zone_key unique (warehouse_id, zone)
);

-- 작업자 실수 표(판정 14) — 옛 wms_discrepancies 의 좁힌 판 · reason 다섯 · recv_* 는 po_receipt_diff · stock_short 는 원장 sale_shortfall + so_stock_short_check(§20 판정 7)
create table public.wms_worker_mistakes (
  id             bigint generated always as identity primary key,
  order_id       uuid not null references public.so (id) on delete restrict,
  order_number   text not null,
  sku            text not null,
  ordered_base   numeric,
  actual_base    numeric,
  reason         text not null,
  cin7_corrected boolean not null default false,
  resolved_by    uuid references public.ims_staff (id) on delete restrict,
  resolved_at    timestamptz,
  created_at     timestamptz default now(),
  responsible    uuid references public.ims_staff (id) on delete restrict,
  source         text,
  declared_by    uuid references public.ims_staff (id) on delete restrict,
  pick_task_id   bigint,
  pack_task_id   bigint,
  voided_at      timestamptz,
  voided_by      uuid references public.ims_staff (id) on delete restrict,
  voided_reason  text,
  constraint wms_worker_mistakes_reason_check check (reason in (
    'short_pick',              -- 픽 완료 때 목표보다 적게(픽커)
    'short_after_pack',        -- 팩 완료 때 부족(픽커 귀속)
    'over_pick',               -- 픽커가 더 가져왔다(팩커가 가른다)
    'pack_scan_mistake',       -- 팩커가 두 번 스캔(선해소 · responsible null)
    'resolved_pack_recovery'   -- 팩 보충으로 해소된 픽 부족(롤백 때 short_pick 으로 되살린다 · 규칙 14)
  ))
);
create index idx_mistakes_unresolved on public.wms_worker_mistakes (cin7_corrected) where cin7_corrected = false;
create index idx_mistakes_order      on public.wms_worker_mistakes (order_id);

-- RLS · 정책 — auth_all 그대로(판정 6 · 알고 받아들인 대가) · rollback_archive 는 append-only 둘
alter table public.wms_waves            enable row level security;
alter table public.wms_pick_tasks       enable row level security;
alter table public.wms_pick_task_lines  enable row level security;
alter table public.wms_pack_tasks       enable row level security;
alter table public.wms_pack_task_lines  enable row level security;
alter table public.wms_pallets          enable row level security;
alter table public.wms_pallet_items     enable row level security;
alter table public.wms_task_holds       enable row level security;
alter table public.wms_rollback_log     enable row level security;
alter table public.wms_rollback_archive enable row level security;
alter table public.wms_reports          enable row level security;
alter table public.wms_drop_locations   enable row level security;
alter table public.wms_zone_sequence    enable row level security;
alter table public.wms_worker_mistakes  enable row level security;

create policy auth_all on public.wms_waves            for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_pick_tasks       for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_pick_task_lines  for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_pack_tasks       for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_pack_task_lines  for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_pallets          for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_pallet_items     for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_task_holds       for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_rollback_log     for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_reports          for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_drop_locations   for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_zone_sequence    for all to authenticated using (true) with check (true);
create policy auth_all on public.wms_worker_mistakes  for all to authenticated using (true) with check (true);
create policy rb_archive_insert on public.wms_rollback_archive for insert to authenticated with check (true);
create policy rb_archive_select on public.wms_rollback_archive for select to authenticated using (true);
revoke all on table public.wms_rollback_archive from anon, authenticated;
grant select, insert on table public.wms_rollback_archive to authenticated;

-- ═══ 3) 뷰 — 새 표 위에 같은 이름 · 같은 칸(order_id 만 uuid) · security_invoker (⬜12) ═══
create view public.wms_order_pack_progress
  with (security_invoker = true) as
select
  pt.order_id,
  count(pt.id)::int as pick_batches,
  (count(distinct pk.pick_task_id) filter (where pk.status = 'completed'))::int as packs_done,
  count(pt.id) > 0
    and count(pt.id) = count(distinct pk.pick_task_id) filter (where pk.status = 'completed')
    as all_packed
from public.wms_pick_tasks pt
left join public.wms_pack_tasks pk on pk.pick_task_id = pt.id
group by pt.order_id;
revoke all on public.wms_order_pack_progress from anon, authenticated;
grant select on public.wms_order_pack_progress to authenticated;

-- ═══ 4) comment on — 표마다 한 줄 ═══
comment on table public.wms_waves            is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — warehouse_id uuid(ref_warehouse) · 사람 칸 ims_staff.id · 옛 표는 wms_legacy';
comment on table public.wms_pick_tasks       is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — order_id uuid(so) · 사람 칸 ims_staff.id · 옛 표는 wms_legacy';
comment on table public.wms_pick_task_lines  is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — order_line_id uuid(so_line) · picked_by ims_staff.id · 옛 표는 wms_legacy';
comment on table public.wms_pack_tasks       is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — order_id uuid(so) · 사람 칸 ims_staff.id · 옛 표는 wms_legacy';
comment on table public.wms_pack_task_lines  is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — order_line_id uuid(so_line) · verified_by ims_staff.id · 옛 표는 wms_legacy';
comment on table public.wms_pallets          is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — order_id uuid(so) · created_by ims_staff.id · 옛 표는 wms_legacy';
comment on table public.wms_pallet_items     is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — order_id·order_line_id uuid · order_sku·product_name 없음(so_line·product 에서 읽는다) · 옛 표는 wms_legacy';
comment on table public.wms_task_holds       is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — worker·resumed_by ims_staff.id · task_kind 셋(receipt 는 ⑤-3 에서 판정) · source 둘 · 옛 표는 wms_legacy';
comment on table public.wms_rollback_log     is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — order_id uuid(so · set null) · 사람 칸 ims_staff.id · order_number 는 그때의 기록 · 옛 표는 wms_legacy';
comment on table public.wms_rollback_archive is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — archived_by ims_staff.id · order_id uuid(FK 없음 · 기록) · append-only(insert·select) · 옛 2,377행은 wms_legacy';
comment on table public.wms_reports          is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — order_id uuid(so · set null) · receipt_id uuid(po_receipt · set null) · 사람 칸 ims_staff.id · kind 넷 그대로 · 옛 표는 wms_legacy';
comment on table public.wms_drop_locations   is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — warehouse_id uuid(ref_warehouse) · 옛 표(0행)는 wms_legacy';
comment on table public.wms_zone_sequence    is '⑤-1 (so-module §24) · 운영 WMS 의 같은 이름 표와 다르다 — warehouse_id uuid(ref_warehouse) · 옛 23행은 wms_legacy(⑤-4 때 옮겨 심는다)';
comment on table public.wms_worker_mistakes  is '⑤-1 (so-module §24 판정 14) · 옛 wms_discrepancies 의 좁힌 판 — 작업자 실수 다섯만 · recv_* 는 po_receipt_diff · stock_short 는 원장 sale_shortfall(§20 판정 7) · cin7_corrected 는 「매니저가 정리했다」 뜻(이름은 화면 무접촉 · ⑤-5 판정) · 옛 표는 wms_legacy';
comment on view  public.wms_order_pack_progress is '⑤-1 (so-module §24 ⬜12) · 새 wms_pick_tasks·wms_pack_tasks 위에 같은 칸(order_id uuid) · fulfillment 보드의 관문 · 옛 뷰는 wms_legacy';
