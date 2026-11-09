-- supabase/migrations/20261109223500_chg_fix_1_po_charge_kind_lock.sql — chg-fix-1: 청구서(po_charge) Kind 는 draft 에서만 바꾼다 (2026-11-09 토론토 · 판정 1135 = (a))
-- 대상: [테스트 · Asung-IMS = IMS 메인(617)] — psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f 로 적용 + supabase migration repair --status applied 20261109223500 · supabase db push 금지
-- 왜: PO 청구서 머리는 charges.html saveHead 가 PostgREST 로 직접 쓴다(authenticated · kind 포함 23 칸 UPDATE · 정책은 ims_can_write('purchasing') 하나) — kind 를 지키는 것이 없어
--     확정 · 원가 얹힌 청구서도 API 로 kind 가 바뀌었다 → 하루 원가 장(qbo_cost_expected 의 대변 = qbo_cost_charge_account(pc.kind))과 보낸 Bill 계정이 갈라진다.
--     동료 리포트(2026-11-09): 청구서 17038 을 freight 로 잘못 넣음(맞는 것 brokerage · draft) — 화면이 Kind 칸을 열고(chg kind v1) 이 트리거가 draft 밖을 막는다. 이 파일은 그 행을 바꾸지 않는다.
-- 만드는 것: 함수 public.po_charge_kind_lock()(트리거 몸 · security definer · 쓰기 0) + 트리거 po_charge_kind_lock(BEFORE UPDATE OF kind · FOR EACH ROW) — 그 밖 무변
--   규칙(kind 가 실제로 바뀔 때만 · 같은 값 update 는 통과 · 판정은 old 로 — 같은 문장이 status 나 번호를 함께 바꿔도 old 기준):
--     ① old.status = cancelled                       → 거부(Restore 먼저)
--     ② 이 청구서의 landed 얹기가 있다(어느 상태든) → 거부(상쇄 청구서로 — Reopen 도 같은 까닭으로 거부되므로 「Reopen 하라」 로 보내지 않는다 · §0 이견 4)
--     ③ old.status <> draft(= confirmed)             → 거부(Reopen → Kind → 다시 확정 · 보낸 Bill 은 Reopen 때 bill_delete_manual · 다시 확정하면 새 kind 계정으로 새 Bill)
--     ④ 그 밖(draft · landed 0)                      → 통과
--   landed 를 찾는 식 = po_charge_confirm 의 Reopen 검사와 같은 식(inv_layer_cost_add.kind = 'landed' and doc_number = 청구서 번호 · §0 이견 3) — 두 곳이 같은 답을 낸다
--   security definer 인 까닭(§0 이견 1): inv_layer_cost_add 읽기 정책은 ims_can_view_cost() — invoker 면 원가 열쇠 없는 구매 직원에게 landed 가 0 행으로 보여 ② 가 조용히 꺼진다
--   트랜스퍼 운임도 같은 표를 쓴다 — tf_charge_update 는 draft 에서만 쓰므로 걸리지 않는다(kind 를 늘 SET 에 넣어 트리거는 돌지만 ④)
--   적재(session_replication_role = replica)는 보통 트리거가 돌지 않아 저절로 비켜 간다 — 레포 안에 po_charge 를 쓰는 적재는 없다(2026-11-09 grep)
-- ⚠️ 한계 — 머리 칸 전체 잠금이 아니다(deferred 139): authenticated 는 status 칸도 REST 로 직접 쓸 수 있어 「status 를 draft 로 PATCH → kind → status 되돌리기」 로 ③ 을 돌아갈 수 있다.
--     그 길에서도 원가가 얹힌 청구서는 ② 가 막는다. status 직접 쓰기를 닫는 것은 139 의 일이다.
-- 하지 않는 것: po_doc_delete · po_doc_cancel · po_charge_confirm · tf_charge_* · qbo_* 무접촉 · 새 표 0 · FK 0 · 행 0(17038 포함) · EF · 화면 · cron 무변
-- 검증 supabase/tests/chg_fix_1_check.sql(운영 메인 begin → rollback · 가짜 행만) · 적용은 Caleb

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

-- ═══════════════ ⓪ 전제 가드 — 아직 미적용 · 기대는 칸 · 제약 ═══════════════
do $$
declare v_bad text := '';
begin
  if exists (select 1 from pg_trigger where tgrelid = 'public.po_charge'::regclass and tgname = 'po_charge_kind_lock') then v_bad := v_bad || ' (trigger po_charge_kind_lock already exists)'; end if;
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'po_charge_kind_lock') then v_bad := v_bad || ' (function po_charge_kind_lock already exists)'; end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.po_charge'::regclass and conname = 'po_charge_status_ck' and pg_get_constraintdef(oid) like '%draft%confirmed%cancelled%') then v_bad := v_bad || ' (po_charge_status_ck is not draft · confirmed · cancelled)'; end if;
  if (select count(*) from information_schema.columns where table_schema = 'public' and table_name = 'inv_layer_cost_add' and column_name in ('kind', 'doc_number')) <> 2 then v_bad := v_bad || ' (inv_layer_cost_add.kind · doc_number missing)'; end if;
  if v_bad <> '' then raise exception 'chg-fix-1 precondition failed:% — nothing was changed', v_bad; end if;
end $$;

-- ═══════════════ ① 트리거 몸 ═══════════════
create function public.po_charge_kind_lock() returns trigger
  language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_n bigint;
begin
  if new.kind is not distinct from old.kind then return new; end if;
  if old.status = 'cancelled' then
    raise exception using errcode = 'P0001', message = 'This charge is cancelled — Restore it first, then change Kind — nothing was saved';
  end if;
  select count(*) into v_n from public.inv_layer_cost_add ca where ca.kind = 'landed' and ca.doc_number = old.charge_number;
  if v_n > 0 then
    raise exception using errcode = 'P0001', message = format('This charge is already on stock cost (%s layer row(s)) — Kind cannot be changed; to correct it, enter an offsetting charge — nothing was saved', v_n);
  end if;
  if old.status <> 'draft' then
    raise exception using errcode = 'P0001', message = 'Kind can only be changed on a draft charge — Reopen it, change Kind, then confirm again — nothing was saved';
  end if;
  return new;
end $$;
comment on function public.po_charge_kind_lock() is '[chg-fix-1 · 판정 1135] 트리거 po_charge_kind_lock 의 몸 — po_charge.kind 는 draft 이고 landed 얹기가 없을 때만 바뀐다(cancelled → Restore 먼저 · landed 있음 → 상쇄 청구서 · confirmed → Reopen). definer = 원가 열쇠 없는 직원에게도 landed 가 보이게. 쓰기 없음. 머리 칸 전체 잠금은 아니다(deferred 139).';
revoke all on function public.po_charge_kind_lock() from public, anon, authenticated, service_role;

-- ═══════════════ ② 트리거 ═══════════════
create trigger po_charge_kind_lock
  before update of kind on public.po_charge
  for each row execute function public.po_charge_kind_lock();

-- ═══════════════ ③ 착지 ═══════════════
do $$
declare v_bad text := ''; v_def text; v_p record;
begin
  select pg_get_triggerdef(t.oid) into v_def from pg_trigger t where t.tgrelid = 'public.po_charge'::regclass and t.tgname = 'po_charge_kind_lock' and t.tgenabled = 'O';
  if v_def is distinct from 'CREATE TRIGGER po_charge_kind_lock BEFORE UPDATE OF kind ON public.po_charge FOR EACH ROW EXECUTE FUNCTION po_charge_kind_lock()' then v_bad := v_bad || format(' (trigger definition: %s)', coalesce(v_def, '<missing>')); end if;
  select p.prosecdef, p.proconfig::text as cfg, p.proacl::text as acl, count(*) over () as n into v_p from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_charge_kind_lock';
  if v_p.n is distinct from 1 or not v_p.prosecdef or v_p.cfg is distinct from '{"search_path=public, pg_temp"}' or v_p.acl is distinct from '{postgres=X/postgres}' then
    v_bad := v_bad || format(' (function: n %s · definer %s · config %s · acl %s)', v_p.n, v_p.prosecdef::text, v_p.cfg, v_p.acl);
  end if;
  if v_bad <> '' then raise exception 'chg-fix-1 landing check failed:% — nothing was changed', v_bad; end if;
end $$;
