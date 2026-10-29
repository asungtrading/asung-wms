-- so-del-1 (2026-10-28 · 판정 865 · 지시서 ~/asung/prompts/so-del-1.md · pos-reopen-1 이견 5 · 6) — 한 번이라도 확정됐던 판매는 Delete draft 로 지우지 못한다 · 결제가 붙은 초안도 읽을 수 있는 글로 거부
--   왜: pos-reopen-1(0d6c12b)이 줄의 풀린 예약 이력을 줄과 함께 지우자 so_delete 의 「이력 있음 → so_cancel」 거부(so_reserve 행으로 판단)가 Reopen → 줄 전부 ✕ → Delete draft 에서 비켜 갔다(시험 C3) —
--       확정은 재고를 잡았던 순간이므로 그 판매가 있었다는 흔적을 남긴다 · 없애려면 매니저의 Cancel(so_cancel · 취소 기록) [판정 865 · Caleb 「B」 · 기각 A = 받아들인다]
--   실물(코드 + 테스트 DB): so.confirmed_at 은 so_pos_reopen · so_unconfirm 이 null 로 비운다 → 「확정된 적 있음」 을 들고 있는 칸이 없다 · unconfirmed_at 은 so_unconfirm 만 찍고(warehouse 3) so_pos_reopen 은 안 찍는다(POS draft 12 는 예약 이력으로만 안다)
--   ① 새 칸 so.first_confirmed_at timestamptz — 처음 확정된 시각 · 한 번 찍히면 바뀌지 않는다
--   ② 트리거 so_first_confirmed(BEFORE UPDATE · 행) — draft → confirmed 로 바뀌는 순간 비어 있으면 coalesce(new.confirmed_at, now()) 로 찍는다 · 찍힌 값을 바꾸거나 비우면 거부
--      [Claude Code 판단 · 대화 Claude 안(확정 창구 셋이 coalesce 로 찍는다)과 다르다]: 확정은 전부 status draft → confirmed 한 전이로 지나간다(so_status_guard 가 insert 는 draft 만 받는다 · so_split 형제도 insert 뒤 update) —
--        트리거 하나가 so_confirm(약 300 행) · so_pos_confirm · so_service_confirm · 앞으로의 확정 창구를 전부 덮고 셋은 무접촉 · 되돌리기(so_pos_reopen · so_unconfirm)는 칸을 모르므로 못 지운다 · 바꾸기 거부가 마지막 방어
--   ③ 채우기(session_replication_role replica · updated_at · updated_by 무접촉 — so_unconfirm 이 형제의 updated_at = created_at 을 검사한다) — least(confirmed_at, 그 오더 so_reserve 의 가장 이른 allocated_at, unconfirmed_at)
--      테스트 DB 2026-10-28: confirmed_at 있음 122(그중 8 은 다시 확정이라 예약 allocated_at 이 더 이르다 → least) + 초안의 예약 이력 15(POS 12 · warehouse 3 — warehouse 3 은 unconfirmed_at 도 있다) = 137 · 흔적 없는 초안 아님 1(SO-25082 cancelled voided · 초안에서 취소 · null 그대로)
--      ⚠️ pos-reopen-1 적용(2026-10-28 밤) 뒤 이미 줄을 다 지워 이력이 사라진 초안은 알 길이 없다 — 적용 ~ 이 차수 사이가 짧아(같은 밤) 없다고 본다(짐작 · 실물 SO-25237 은 이력 8 행 그대로)
--   ④ so_delete 재발행(원본 20260924022449:387 ~ 416 바이트 + 더한 줄) — 판단 순서: draft 인가 → ⭐ first_confirmed_at 있으면 거부(865) → 예약 이력(원문 그대로 · 이제 뒤의 방어) → ⭐ so_payment_order 가 가리키면 거부(이견 6 · 23503 대신 읽을 수 있는 글 · 상태 무관) → 지우기
--      결제가 붙은 「한 번도 확정 안 된」 초안은 실제로 생긴다 — so_payment_add(target_so_ids)는 초안 상태를 묻지 않는다(pos_pay_1 R3 가 warehouse 초안에 결제를 붙였다 · 선결제) · 테스트 DB 지금은 0(결제 붙은 초안 4 는 전부 이력 있음)
--      다음 할 일 = so_cancel(manager · draft 도 받는다 · so_payment_order 는 남고 돈은 손님 잔액으로 — 끝 상태라 reserved_deposit 에서 풀린다 · rollback 재현 SO-25169)
--   ⚠️ 무접촉: so_cancel · so_pos_reopen · so_unconfirm · so_confirm · so_pos_confirm · so_service_confirm · so_line_remove · so_lines_clear(끝 do 블록이 prosrc md5 단언) · 정책 · 다른 트리거 변화 없음 · so 표 select 는 표 단위 grant(authenticated=r)라 새 칸이 그대로 보인다(so_detail 의 to_jsonb(s) 에 실려 화면이 쓸 수 있다)
--   컷오버 날 지우기(cutover-delete): so 는 d6 truncate 목록 — 칸 하나 더해도 순서 · 지문 식 변화 없음
--   원본 md5(DB prosrc · 2026-10-28 테스트 DB · 파일 본문과 일치): so_delete a98f03969aba10e19fa0972897a87505
--     무접촉: so_cancel 818b2dd98a8c6159af4701d1de11e1fb · so_pos_reopen a4cbbc54bab27e288795bb997f62aef5 · so_unconfirm b9b48b92b7445a84abcdb5aa1b254b28 · so_confirm e426c9f51d297ad2650a0c8e8aa76a9e · so_pos_confirm 2a20a8abad4d4a5dcb509d64a15b77b4 · so_service_confirm 4d9ee80ecefbf07f7edf47abae4e9151 · so_line_remove b69af1efb47676f7d5bc9f27635c3332 · so_lines_clear a753a16e09a7731fa475442d7337ff68
--   검증: supabase/tests/so_del_1.sql(시험 적용 begin → rollback · C3 재현 → 거부 · 미확정 초안 OK · Reopen → 다시 Confirm → Reopen 표시 그대로 · warehouse 길 · 결제 붙은 초안 · so_cancel 통과 · 채우기 · updated_at 무접촉 · 표시 바꾸기 거부 · 시퀀스 되돌림)
--   적용(Caleb): psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f supabase/migrations/20261029020000_so_del_1.sql && supabase migration repair --status applied 20261029020000 --db-url "$(cat ~/.asung-testdb-url)"

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

-- ═══ 0) 기대는 마지막 정의인가 · 칸 · 트리거가 아직 없는가 — 다르면 멈춘다 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') is distinct from 'a98f03969aba10e19fa0972897a87505' then v_bad := v_bad || ' so_delete'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') is distinct from 'a4cbbc54bab27e288795bb997f62aef5' then v_bad := v_bad || ' so_pos_reopen'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') is distinct from 'b9b48b92b7445a84abcdb5aa1b254b28' then v_bad := v_bad || ' so_unconfirm'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') is distinct from 'b69af1efb47676f7d5bc9f27635c3332' then v_bad := v_bad || ' so_line_remove(pos-reopen-1 not applied?)'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so' and column_name = 'first_confirmed_at') then v_bad := v_bad || ' (so.first_confirmed_at already exists)'; end if;
  if exists (select 1 from pg_trigger where tgrelid = 'public.so'::regclass and tgname = 'so_first_confirmed') then v_bad := v_bad || ' (trigger so_first_confirmed already exists)'; end if;
  if (select setting from pg_settings where name = 'session_replication_role') <> 'origin' then v_bad := v_bad || ' (session_replication_role is not origin)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM865', message = format('STOP - so-del-1 expects the last definitions as of 2026-10-28; these differ:%s - nothing was changed', v_bad); end if;
end $$;

-- ═══ ① so.first_confirmed_at — 처음 확정된 시각(판정 865 · 되돌려도 남는다) ═══
alter table public.so add column first_confirmed_at timestamptz;
comment on column public.so.first_confirmed_at is '⭐ 처음 확정(Confirm)된 시각 — 한 번 찍히면 바뀌지 않는다(트리거 so_first_confirmed · draft → confirmed 전이에서 비어 있으면 coalesce(confirmed_at, now()) · 바꾸기 · 비우기 거부) · so_pos_reopen · so_unconfirm 이 confirmed_at 을 비워도 이 칸은 남는다 · ⭐ so_delete 는 이 칸이 있으면 거부(판정 865 — 확정은 재고를 잡았던 순간 · 없애려면 매니저의 so_cancel) · 채우기(so-del-1 2026-10-28) = least(confirmed_at, 예약 이력의 가장 이른 allocated_at, unconfirmed_at) · 채우기 전에 이력이 지워진 초안은 null 일 수 있다';

-- ═══ ② 트리거 so_first_confirmed — 찍기 · 지키기 ═══
create function public.so_first_confirmed() returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
begin
  if old.first_confirmed_at is not null and new.first_confirmed_at is distinct from old.first_confirmed_at then
    raise exception 'Order % was first confirmed at % — that mark cannot be changed or cleared — nothing was saved', old.so_number, old.first_confirmed_at;
  end if;
  if new.status = 'confirmed' and old.status is distinct from 'confirmed' and new.first_confirmed_at is null then
    new.first_confirmed_at := coalesce(new.confirmed_at, now());
  end if;
  return new;
end;
$$;
comment on function public.so_first_confirmed() is 'so BEFORE UPDATE(행) — status 가 confirmed 로 바뀌는 순간 first_confirmed_at 이 비어 있으면 coalesce(new.confirmed_at, now()) 로 찍는다 · 찍힌 값을 바꾸거나 비우면 거부(so-del-1 · 판정 865) · 이름 순서: so_bgrade_header_guard → so_first_confirmed → so_reprice_flag_draft_only → so_status_guard → so_touch(전이가 거부되면 전부 되돌아간다)';
revoke all on function public.so_first_confirmed() from public, anon;
create trigger so_first_confirmed before update on public.so
  for each row execute function public.so_first_confirmed();

-- ═══ ③ 채우기 — replica(so_touch · 문지기를 지나지 않는다 · updated_at 무접촉) → 다시 origin ═══
set local session_replication_role = replica;
do $$
declare v_n int;
begin
  update public.so s set first_confirmed_at = x.first_at
  from (
    select s2.id, least(s2.confirmed_at, s2.unconfirmed_at, (select min(r.allocated_at) from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s2.id)) as first_at
    from public.so s2
  ) x
  where x.id = s.id and x.first_at is not null and s.first_confirmed_at is null;
  get diagnostics v_n = row_count;
  raise notice 'so-del-1 backfill: first_confirmed_at set on % order(s)', v_n;
end $$;
set local session_replication_role = origin;

-- ═══ ④ so_delete 재발행 — 원본 20260924022449_so_hold_cancel.sql:387 ~ 416 바이트 + 더한 줄(so-del-1 표시) ═══
create or replace function public.so_delete(p_so_id uuid) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_so        public.so%rowtype;
  v_lines     int;
  v_charges   int;
  v_reserves  int;
  v_n         int;
  v_pays      int := 0;                                         -- so-del-1 이견 6: 이 판매를 가리키는 결제(so_payment_order · 상태 무관)
begin
  perform public.ims_require_write('sales', 'deleted');        -- ⭐ 첫 줄
  perform public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'deleted');
  if v_so.first_confirmed_at is not null then                                                                                     -- so-del-1 판정 865: 한 번이라도 확정됐던 판매는 지우지 못한다 — Reopen · Unconfirm 뒤 줄을 다 지워도
    raise exception 'Order % was confirmed before — it cannot be deleted. Ask a manager to cancel it (so_cancel), which keeps a record — nothing was deleted', v_so.so_number;
  end if;

  select count(*) into v_reserves from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = p_so_id;
  if v_reserves > 0 then
    raise exception 'Order % has allocation history (it was confirmed before) — cancel it instead (so_cancel) — nothing was deleted', v_so.so_number;
  end if;
  select count(*) into v_pays from public.so_payment_order o where o.so_id = p_so_id;                                              -- so-del-1 이견 6: 23503(so_payment_order_so_id_fkey) 대신 읽을 수 있는 글
  if v_pays > 0 then
    raise exception 'Order % has % payment(s) tied to it — it cannot be deleted. Ask a manager to cancel it (so_cancel); the money stays on the customer''s balance — nothing was deleted', v_so.so_number, v_pays;
  end if;
  select count(*) into v_lines   from public.so_line   where so_id = p_so_id;
  select count(*) into v_charges from public.so_charge where so_id = p_so_id;

  delete from public.so where id = p_so_id and status = 'draft';
  get diagnostics v_n = row_count;
  if v_n <> 1 then
    raise exception 'Order % was not deleted — it may have been changed by someone else just now — nothing was deleted', v_so.so_number;
  end if;
  return jsonb_build_object('deleted', v_so.so_number, 'lines', v_lines, 'charges', v_charges);
end;
$$;
comment on function public.so_delete(uuid) is '⭐ SO 초안 지우기(①b · ②b 문장 갱신 · so-del-1 판정 865) — definer · 첫 줄 ims_require_write(sales, deleted) · 초안만 · ⭐ first_confirmed_at 이 있으면(한 번이라도 확정됐던 판매 · Reopen · Unconfirm 뒤 줄을 다 지워도) 거부 「Ask a manager to cancel it (so_cancel)」 · so_reserve 이력이 있으면 거부(뒤의 방어) · so_payment_order 가 가리키면(결제 · 취소된 것도 · 선결제) 거부 — 23503 대신 읽을 수 있는 글(이견 6) · 줄·운임은 cascade(거래 표 규약) · 번호는 되돌아오지 않는다(시퀀스)';

-- ═══ 끝) 착지 — 칸 · 트리거 · 채우기 정합 · so_delete 바뀜 · 무접촉 여덟 · acl ═══
do $$
declare v_bad text := ''; v_n int;
begin
  if not exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'so' and column_name = 'first_confirmed_at' and data_type = 'timestamp with time zone') then v_bad := v_bad || ' (column missing)'; end if;
  if not exists (select 1 from pg_trigger where tgrelid = 'public.so'::regclass and tgname = 'so_first_confirmed' and tgenabled = 'O') then v_bad := v_bad || ' (trigger missing)'; end if;
  if (select setting from pg_settings where name = 'session_replication_role') <> 'origin' then v_bad := v_bad || ' (session_replication_role not back to origin)'; end if;
  select count(*) into v_n from public.so s where s.first_confirmed_at is null and (s.confirmed_at is not null or s.unconfirmed_at is not null or exists (select 1 from public.so_reserve r join public.so_line l on l.id = r.so_line_id where l.so_id = s.id));
  if v_n > 0 then v_bad := v_bad || format(' (%s order(s) with a confirm trace but no first_confirmed_at)', v_n); end if;
  select count(*) into v_n from public.so s where s.first_confirmed_at is not null and s.confirmed_at is not null and s.first_confirmed_at > s.confirmed_at;
  if v_n > 0 then v_bad := v_bad || format(' (%s order(s) with first_confirmed_at after confirmed_at)', v_n); end if;
  select count(*) into v_n from public.so s where s.status not in ('draft', 'cancelled') and s.first_confirmed_at is null;
  if v_n > 0 then v_bad := v_bad || format(' (%s non-draft order(s) without first_confirmed_at)', v_n); end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') = 'a98f03969aba10e19fa0972897a87505' then v_bad := v_bad || ' so_delete(unchanged)'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_delete') <> 1 then v_bad := v_bad || ' (so_delete count <> 1)'; end if;
  if not has_function_privilege('authenticated', 'public.so_delete(uuid)', 'execute') or has_function_privilege('anon', 'public.so_delete(uuid)', 'execute') then v_bad := v_bad || ' so_delete(acl)'; end if;
  if has_function_privilege('anon', 'public.so_first_confirmed()', 'execute') then v_bad := v_bad || ' so_first_confirmed(acl anon)'; end if;
  if not has_column_privilege('authenticated', 'public.so', 'first_confirmed_at', 'select') then v_bad := v_bad || ' (authenticated cannot read first_confirmed_at)'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_cancel') is distinct from '818b2dd98a8c6159af4701d1de11e1fb' then v_bad := v_bad || ' so_cancel'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_reopen') is distinct from 'a4cbbc54bab27e288795bb997f62aef5' then v_bad := v_bad || ' so_pos_reopen'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_unconfirm') is distinct from 'b9b48b92b7445a84abcdb5aa1b254b28' then v_bad := v_bad || ' so_unconfirm'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_confirm') is distinct from 'e426c9f51d297ad2650a0c8e8aa76a9e' then v_bad := v_bad || ' so_confirm'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_pos_confirm') is distinct from '2a20a8abad4d4a5dcb509d64a15b77b4' then v_bad := v_bad || ' so_pos_confirm'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_service_confirm') is distinct from '4d9ee80ecefbf07f7edf47abae4e9151' then v_bad := v_bad || ' so_service_confirm'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_line_remove') is distinct from 'b69af1efb47676f7d5bc9f27635c3332' then v_bad := v_bad || ' so_line_remove'; end if;
  if (select md5(prosrc) from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_lines_clear') is distinct from 'a753a16e09a7731fa475442d7337ff68' then v_bad := v_bad || ' so_lines_clear'; end if;
  if (select count(*) from pg_trigger where tgrelid = 'public.so'::regclass and not tgisinternal) <> 5 then v_bad := v_bad || ' (so triggers <> 5)'; end if;
  if v_bad <> '' then raise exception using errcode = 'IM865', message = format('STOP - so-del-1 landing check failed:%s', v_bad); end if;
end $$;
