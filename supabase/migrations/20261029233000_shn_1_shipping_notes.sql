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
-- shn-1 — Shipping notes 를 Ship & invoice 전까지 고치는 창구 so_shipping_notes_set (2026-10-29 · 판정 880 · 동료 피드백 3 「shipping note는 새 오더를 만들때는 적을 수 있는데, 그 이후에는 수정이 안되는 것 같아」 · 조사 fb-1029-0)
--   무엇이 났나: so.shipping_notes(20260923133042:107)를 쓰는 길은 so_header_update(ful_1c 20261013230000:141 · so_require_draft :173 · update 의 status = 'draft' :329 — 초안만)와
--     so_finalize(ful_1a 20261013170000:869 · Ship & invoice 창 — 화면은 비어 있지 않을 때만 보낸다) 둘뿐 — 확정 뒤 Ship & invoice 전까지는 고칠 길이 없었다
--   판정 880(Caleb 「finalized 상태까지 수정이 가능했으면 좋겠어」): ① 고칠 수 있는 상태 = draft · confirmed · at_wms · picking · packed(화면 「Finalized」) — shipped · fulfilled · cancelled 는 거부
--     ② 문 = sales 쓰기(so_header_update 와 같은 문) ③ 창고 종이(픽리스트 · 패킹)에 싣는 것은 이 차수 밖 — 지금처럼 so.html 에서만 보인다 ④ 비우기 됨(빈 글 → null)
--   길이 한도 2000 — so_header_update · so_finalize 에 이 칸 한도가 없다(trim 뒤 nullif 만) · 테스트 DB 실물 최장 23 자(2026-10-29)
--   상태 문지기(so_status_guard)는 같은 상태의 update 를 통과시킨다 · so 의 다른 BEFORE UPDATE 트리거(so_bgrade_header_guard · so_reprice_flag_draft_only)는 칸이 달라 돌지 않는다 · so_first_confirmed 는 찍힌 값을 건드리지 않으면 지난다 · so_touch(ims_touch)가 updated_at · updated_by 를 남긴다
--   ⚠️ 알고 간다: 확정 때 갈라진 오더(split)의 notes 를 고치면 updated_at 이 움직여 원래 오더의 Unconfirm 이 「was changed after the split」로 막힌다(so_unconfirm dsc_3b 20261006204146:520) — 합치면 갈라진 오더의 notes 가 사라지므로 막는 쪽이 맞다
--   화면(asung-ims so.html · 대화 Claude): sb.rpc("so_shipping_notes_set", { p_so_id, p_text: 글 또는 "", p_old: 지금 so.shipping_notes 또는 null }) · error.message 를 그대로 보인다 · 성공이면 다시 읽는다
--   새 표 없음 · 데이터 무접촉(새 함수 하나 · comment 하나) · so 행은 창구가 불릴 때 shipping_notes 한 칸만 바뀐다
--   ⚠️ 적용은 Caleb: psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -1 -f supabase/migrations/20261029233000_shn_1_shipping_notes.sql && supabase migration repair --status applied 20261029233000 --db-url "$(cat ~/.asung-testdb-url)" — db push 금지
--   시험: supabase/tests/shn_1_check.sql(-v mig · begin → rollback · T1~T6) · 둘째 겹 = 적용 뒤 Caleb 이 so.html 새 판에서 confirmed · Finalized 오더의 Shipping notes 를 한 번씩 고친다(REST)

-- ═══ 0) 새 창구는 아직 없어야 ═══
do $$
begin
  if exists (select 1 from pg_proc where pronamespace = 'public'::regnamespace and proname = 'so_shipping_notes_set') then
    raise exception using errcode = 'IM880', message = 'STOP - not the expected state: so_shipping_notes_set(already there) - re-read before re-issuing - nothing was changed';
  end if;
end $$;

-- ═══ 1) 창구 so_shipping_notes_set — 꼴 · 보안은 customer_default_carrier_set(cdc-1 20261029230000) 그대로 · 문 = sales 쓰기 ═══
create function public.so_shipping_notes_set(p_so_id uuid, p_text text, p_old text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare v_so public.so%rowtype;  v_new text := nullif(btrim(p_text), '');  v_n int;
begin
  perform public.ims_require_write('sales');
  select * into v_so from public.so s where s.id = p_so_id for update;
  if not found then raise exception 'Order % not found — nothing was saved', p_so_id; end if;
  if v_so.status not in ('draft', 'confirmed', 'at_wms', 'picking', 'packed') then                                                       -- 880 ①: Ship & invoice 전까지만
    raise exception '%', case v_so.status
      when 'shipped'   then format('Order %s has already shipped — shipping notes can no longer be changed — nothing was saved', v_so.so_number)
      when 'fulfilled' then format('Order %s has already been shipped and invoiced — shipping notes can no longer be changed — nothing was saved', v_so.so_number)
      when 'cancelled' then format('Order %s is cancelled — shipping notes can no longer be changed — nothing was saved', v_so.so_number)
      else format('Order %s is %s — shipping notes can no longer be changed — nothing was saved', v_so.so_number, v_so.status) end;
  end if;
  if nullif(btrim(v_so.shipping_notes), '') is distinct from nullif(btrim(p_old), '') then                                              -- 화면이 본 값(p_old)과 지금 값이 다르면 거부 — 동시 편집 · 빈 글 = null
    raise exception 'Someone changed the shipping notes on order % just now — reload the order and try again — nothing was saved', v_so.so_number;
  end if;
  if v_so.shipping_notes is not distinct from v_new then                                                                                  -- 같은 값 — 쓰지 않는다(touch 도 안 돈다)
    return jsonb_build_object('so_id', p_so_id, 'changed', false, 'shipping_notes', v_so.shipping_notes);
  end if;
  if length(v_new) > 2000 then
    raise exception 'Shipping notes are % characters long — the limit is 2000 — nothing was saved', length(v_new);
  end if;
  update public.so s set shipping_notes = v_new where s.id = p_so_id and s.status = v_so.status;                                         -- 이 칸 하나만 · updated_at · updated_by 는 so_touch(ims_touch)
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not saved — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;
  return jsonb_build_object('so_id', p_so_id, 'changed', true, 'shipping_notes', v_new);
end;
$$;
revoke all on function public.so_shipping_notes_set(uuid, text, text) from public, anon, service_role;
grant execute on function public.so_shipping_notes_set(uuid, text, text) to authenticated;
comment on function public.so_shipping_notes_set(uuid, text, text) is 'shn-1 판정 880: Shipping notes 고치기(sales 쓰기 · draft · confirmed · at_wms · picking · packed 만 — shipped · fulfilled · cancelled 거부) — 저장 = btrim · 빈 글 → null · 2000 자 한도 · p_old = 화면이 본 shipping_notes(btrim 뒤 빈 글 = null 로 견주어 다르면 거부) · 같은 값이면 changed false · 이 칸 하나만 update(status · 다른 칸 무변) · 반환 {so_id, changed, shipping_notes}';
