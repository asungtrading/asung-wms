-- prod-2 — 상품의 문: SKU 잠금 트리거(변경 · 지우기) · 상품 계열 표 직접 쓰기 닫기 (2026-10-01 · 판정 136 · 140 · 141 · 174 · 175 · so-module §31-a · po-module §3-h)
--   판정 136  SKU 변경은 표 트리거로 막는다 — 원장(inv_ledger)이나 원가 레이어(inv_layer) 행이 하나라도 있는 상품은 어느 길로도 SKU 를 바꿀 수 없다 · 사건 없는 상품은 허용
--   판정 140  잠금 트리거 함수는 security definer — 잠금 검사가 호출자 권한과 상관없이 원장 · 레이어를 다 본다(invoker 면 RLS 로 0행 → 「붙은 것 없음」으로 샐 수 있다)
--   판정 141  상품 계열 표에 직접 쓰는 길을 닫고 창구만 연다 · 읽기는 그대로 · 적재(ImsRefLoad.gs ims_fetch_)는 service_role 이라 무관(S8 이 증명)
--   판정 175  원장 · 원가 레이어가 붙은 상품은 누구도 지울 수 없다(before delete · 같은 검사 · errcode IM175) · 사건 없는 상품은 지울 수 있다 · 물러나는 길은 is_active = false — FK 가 없어(sku 글자) 지우면 잔고가 소리 없이 주인을 잃는다
--   판정 174  트리거 함수에는 문(ims_require_write)을 두지 않는다 — ims_can_write 는 auth.uid() 로 직원을 찾아 service_role 적재는 늘 false 가 되고, 트리거는 update 마다 돈다 · 문은 창구(prod-3 · prod-4) 첫 줄에만
--   묶음 ①  닫기 = revoke insert·update·delete from authenticated + 쓰기 정책 drop(정책만 지우면 update·delete 가 「0행 · 에러 없음」으로 조용히 실패한다 · revoke 면 셋 다 42501) · select 정책 · grant 는 그대로
--   묶음 ②  함수 하나(product_sku_lock · TG_OP 로 가른다) · 트리거 둘 — product_sku_lock(before update of sku … when (old.sku is distinct from new.sku) · IM136) + product_delete_lock(before delete · when 없음 · IM175) · 글자 그대로 비교(BSMirror → BSMIRROR 도 거부 — 원장이 글자로 잇는다) · 영어 한 문장
--   묶음 ③  검사 대상 = inv_ledger.sku · inv_layer.sku(판정 136 그대로 · 기초 스냅샷 등 다른 sku 글자 표는 판정 거리 — 검증 I 절이 수를 찍는다)
--   묶음 ④  트리거 함수 execute 는 public · anon · authenticated 에서 회수(트리거 전용 · 실행 시점에는 EXECUTE 를 보지 않는다 — S7 이 증명)
--   묶음 ⑤  적재 무영향은 검증 S8 이 증명(service_role · insert … on conflict (sku) do update set sku = excluded.sku, … — PostgREST merge-duplicates 모양)
--   끝의 do 블록이 여덟 표의 실물(정책 1 · SELECT · 권한 셋 없음 · select 있음)과 트리거 둘(이름 · 시점 · 사건 · 활성)을 세어 어긋나면 전부 되돌린다
--   검증: ~/asung/prompts/prod-2-verify.sql (시험 적용 장치 · 테스트 DB · rollback)
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

-- ═══ A) 잠금 함수 — definer · 문 없음(판정 174) · 글자 그대로 비교 · 변경(IM136)과 지우기(IM175)를 TG_OP 로 가른다 ═══
create or replace function public.product_sku_lock() returns trigger
  language plpgsql security definer
  set search_path = public, pg_temp
as $$
begin
  if exists (select 1 from public.inv_ledger e where e.sku = old.sku)
     or exists (select 1 from public.inv_layer l where l.sku = old.sku) then
    if tg_op = 'DELETE' then
      raise exception using errcode = 'IM175',
        message = format('SKU %s has stock or cost history and cannot be deleted — make it inactive instead — nothing was saved', old.sku);
    end if;
    raise exception using errcode = 'IM136',
      message = format('SKU %s has stock or cost history and cannot be renamed — create a new product instead — nothing was saved', old.sku);
  end if;
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;
revoke all on function public.product_sku_lock() from public, anon, authenticated;
comment on function public.product_sku_lock() is
  '⭐ SKU 잠금 — rename and delete(판정 136 · 175 · 2026-10-01 prod-2) — inv_ledger.sku 또는 inv_layer.sku 에 old.sku 가 한 행이라도 있으면 거부(변경 IM136 · 지우기 IM175 · TG_OP 로 가른다 · 영어 한 문장 · 화면에 그대로) · 없으면 통과(만든 직후 오타 · 잘못 만든 상품 지우기) · 물러나는 길은 is_active = false. 트리거 둘(product_sku_lock before update of sku when · product_delete_lock before delete)이 이 함수 하나를 부른다. 글자 그대로 비교 — 대소문자 · 공백을 접지 않는다(원장이 글자로 잇는다 · BSMirror → BSMIRROR 도 거부). security definer(판정 140) — 호출자가 원장을 못 읽어도 검사는 다 본다. ⚠️ 문(ims_require_write) 없음(판정 174) — service_role 적재가 update 마다 죽지 않게 · 잠금은 누가 하든 같다 · 문은 창구 첫 줄에. 트리거 전용 — execute 회수(실행 시점에는 EXECUTE 를 보지 않는다)';

-- ═══ B) 트리거 — sku 칸 update · 값이 실제로 바뀔 때만 ═══════════════════════════════════════════════════
drop trigger if exists product_sku_lock on public.product;
create trigger product_sku_lock
  before update of sku on public.product
  for each row
  when (old.sku is distinct from new.sku)
  execute function public.product_sku_lock();

-- ═══ B′) 지우기 트리거 — 모든 delete 행 · when 없음(판정 175) · 같은 함수 ═══════════════════════════════════════
drop trigger if exists product_delete_lock on public.product;
create trigger product_delete_lock
  before delete on public.product
  for each row
  execute function public.product_sku_lock();

-- ═══ C) 닫기 — 여덟 표 · 쓰기 정책 drop + revoke insert·update·delete from authenticated · select 는 그대로(판정 141 · 묶음 ①) ═══
--   정책 이름은 20260917235000(다섯) · 20260923154749(ref_price_tier · product_price) · 20260923224900(product_tag) 원문 그대로 · 없는 것도 if exists
drop policy if exists product_family_insert   on public.product_family;
drop policy if exists product_family_update   on public.product_family;
drop policy if exists product_family_delete   on public.product_family;
revoke insert, update, delete on public.product_family from authenticated;

drop policy if exists product_insert          on public.product;
drop policy if exists product_update          on public.product;
drop policy if exists product_delete          on public.product;
revoke insert, update, delete on public.product from authenticated;

drop policy if exists product_barcode_insert  on public.product_barcode;
drop policy if exists product_barcode_update  on public.product_barcode;
drop policy if exists product_barcode_delete  on public.product_barcode;
revoke insert, update, delete on public.product_barcode from authenticated;

drop policy if exists product_bom_insert      on public.product_bom;
drop policy if exists product_bom_update      on public.product_bom;
drop policy if exists product_bom_delete      on public.product_bom;
revoke insert, update, delete on public.product_bom from authenticated;

drop policy if exists product_supplier_insert on public.product_supplier;
drop policy if exists product_supplier_update on public.product_supplier;
drop policy if exists product_supplier_delete on public.product_supplier;
revoke insert, update, delete on public.product_supplier from authenticated;

drop policy if exists product_price_insert    on public.product_price;
drop policy if exists product_price_update    on public.product_price;
drop policy if exists product_price_delete    on public.product_price;
revoke insert, update, delete on public.product_price from authenticated;

drop policy if exists product_tag_insert      on public.product_tag;
drop policy if exists product_tag_update      on public.product_tag;
drop policy if exists product_tag_delete      on public.product_tag;
revoke insert, update, delete on public.product_tag from authenticated;

drop policy if exists ref_price_tier_insert   on public.ref_price_tier;
drop policy if exists ref_price_tier_update   on public.ref_price_tier;
drop policy if exists ref_price_tier_delete   on public.ref_price_tier;
revoke insert, update, delete on public.ref_price_tier from authenticated;

-- ═══ D) 실물 확인 — 여덟 표마다 정책 1(SELECT · authenticated) · insert/update/delete 권한 없음 · select 있음 · 트리거 2(이름 · 시점 · 사건 · 활성) — 어긋나면 전부 되돌린다 ═══
do $$
declare
  v_t    text;
  v_bad  text := '';
  v_pol  int;
  v_sel  int;
begin
  foreach v_t in array array['product', 'product_family', 'product_barcode', 'product_bom', 'product_supplier', 'product_price', 'product_tag', 'ref_price_tier'] loop
    select count(*), count(*) filter (where cmd = 'SELECT' and roles = '{authenticated}'::name[])
      into v_pol, v_sel
      from pg_policies where schemaname = 'public' and tablename = v_t;
    if v_pol <> 1 or v_sel <> 1 then
      v_bad := v_bad || format(' %s(policies %s · select %s)', v_t, v_pol, v_sel);
    end if;
    if has_table_privilege('authenticated', format('public.%I', v_t), 'insert')
       or has_table_privilege('authenticated', format('public.%I', v_t), 'update')
       or has_table_privilege('authenticated', format('public.%I', v_t), 'delete')
       or has_any_column_privilege('authenticated', format('public.%I', v_t), 'update')
       or not has_table_privilege('authenticated', format('public.%I', v_t), 'select') then
      v_bad := v_bad || format(' %s(privileges)', v_t);
    end if;
  end loop;
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'public.product'::regclass and t.tgname = 'product_sku_lock' and t.tgenabled <> 'D'
         and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER product_sku_lock BEFORE UPDATE OF sku ON public.product FOR EACH ROW WHEN ((old.sku IS DISTINCT FROM new.sku)) EXECUTE FUNCTION %product_sku_lock()') <> 1 then
    v_bad := v_bad || ' product(trigger product_sku_lock)';
  end if;
  if (select count(*) from pg_trigger t
       where t.tgrelid = 'public.product'::regclass and t.tgname = 'product_delete_lock' and t.tgenabled <> 'D'
         and pg_get_triggerdef(t.oid) like 'CREATE TRIGGER product_delete_lock BEFORE DELETE ON public.product FOR EACH ROW EXECUTE FUNCTION %product_sku_lock()') <> 1 then
    v_bad := v_bad || ' product(trigger product_delete_lock)';
  end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM141',
      message = format('STOP - the product door is not closed as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
