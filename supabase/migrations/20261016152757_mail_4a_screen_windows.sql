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
-- 20261016152757_mail_4a_screen_windows.sql — mail-4a (2026-10-16 · 회사 PC · Fable · mail-3 e6b7079 위에) · 메일 화면(mail-4b)이 부를 DB 창구 · 판정 516 · 517 · tick 실패 남기기
--   판정 507 · 514 · 516(Caleb 「manager이상」 — 514 의 세 단추 = ims_require_write('sales') + so_require_role('manager')) · 517(Caleb 「manager 이상」 — customer.backorder_mail 바꾸기 = manager 이상 · sales 는 보기만)
--   ① mail_outbox_resolve 재발행(20261016135346 바이트 + 권한 한 줄 → 두 줄) · 바깥 셋 comment · mail_can_resolve()(단추 칸 · 같은 판정)
--   ② customer_update 재발행(20261006131814_master_cs_par_1.sql:96 바이트 + backorder_mail 칸 · 값이 바뀔 때만 manager 이상 — blocks code manager_needed)
--   ③ mail_run_error(창고 · 날의 tick 실패 · 되돌아간 뒤에도 남는다 · 같은 창고 · 날은 한 줄 — attempts · last_at 만) · mail_backorder_tick 재발행(20261016133451 바이트 + 실패 줄 · 성공하면 풀림)
--   ④ 화면 읽기 창구(definer · 첫 줄 ims_can_view('sales')): mail_runs_list · mail_outbox_list · mail_outbox_detail · customer_backorder_mail · mail_settings
--   무접촉: 표 셋 · claim · mark · chat 창구 · preview · notice_state · list · ready · EF · cron
--   첫 문장 = supabase/ops/guard-test-only.sql 바이트 복사 · begin/commit 없음 · 끝 do 블록 · 검증 ~/asung/prompts/mail-4a-verify.sql

-- ═══ ① 판정 516 — 직원 처리 셋 = sales 쓰기 + manager 이상 ═══
create function public.mail_can_resolve() returns boolean
  language sql stable security definer
  set search_path = public, pg_temp
as $$
  select public.ims_can_write('sales')
     and coalesce(public.ims_role_rank((select s.role from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active)), 0) >= public.ims_role_rank('manager');
$$;
comment on function public.mail_can_resolve() is 'mail-4a 판정 516 — 이 직원이 「보냈는지 모르는 메일」 단추 셋(보냄으로 닫기 · 다시 보내기 · 취소)을 누를 수 있나: ims_can_write(sales) ∧ 역할 manager 이상(worker < manager < supervisor < admin). mail_outbox_resolve 의 문(ims_require_write + so_require_role)과 같은 판정 — 화면의 can_* 칸이 이것을 쓴다';
revoke all on function public.mail_can_resolve() from public, anon;
grant execute on function public.mail_can_resolve() to authenticated;

create or replace function public.mail_outbox_resolve(p_id uuid, p_action text, p_note text) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_o     public.mail_outbox%rowtype;
  v_staff uuid;
  v_to    text;
begin
  perform public.ims_require_write('sales', 'saved');                                                -- mail-4a 판정 516: sales 쓰기(admin · supervisor 는 perms 와 무관하게 통과)
  perform public.so_require_role('manager', 'saved');                                                -- mail-4a 판정 516: manager 이상(worker < manager < supervisor < admin)
  v_staff := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active);
  if nullif(btrim(coalesce(p_note, '')), '') is null then
    raise exception 'Say what you checked (a note is required) — nothing was saved';
  end if;
  select * into v_o from public.mail_outbox o where o.id = p_id for update;
  if not found then
    raise exception 'Mail % not found — nothing was saved', p_id;
  end if;
  if p_action = 'close_sent' then
    if v_o.status <> 'unknown' then raise exception 'Only a mail whose result is unknown can be closed as sent (this one is %) — nothing was saved', v_o.status; end if;
    v_to := 'sent';
    update public.mail_outbox set status = 'sent', sent_at = coalesce(v_o.claimed_at, now()) where id = p_id;
  elsif p_action = 'retry' then
    if v_o.status <> 'unknown' then raise exception 'Only a mail whose result is unknown can be sent again (this one is %) — a failed mail goes again with the next run by itself — nothing was saved', v_o.status; end if;
    v_to := 'queued';
    update public.mail_outbox set status = 'queued', next_attempt_at = now(), attempts = 0 where id = p_id;
  elsif p_action = 'cancel' then
    if v_o.status not in ('queued', 'unknown') then raise exception 'Only a queued mail or one whose result is unknown can be cancelled (this one is %) — nothing was saved', v_o.status; end if;
    v_to := 'cancelled';
    update public.mail_outbox set status = 'cancelled' where id = p_id;                            -- 줄 표지는 그대로 — 다음 회차에 다시 안 실린다(1c 상태 cancelled)
  else
    raise exception 'Unknown action % — nothing was saved', coalesce(p_action, 'null');
  end if;
  insert into public.mail_outbox_event (outbox_id, action, from_status, to_status, attempts, staff_id, note)
  values (p_id, p_action, v_o.status, v_to, v_o.attempts, v_staff, btrim(p_note));
  return jsonb_build_object('id', p_id, 'status', v_to);
end;
$$;
comment on function public.mail_outbox_close_sent(uuid, text) is 'mail-2a 판정 514 — 「보냈는지 모르는 메일」(unknown)을 보낸편지함에서 확인하고 보냄으로 닫는다: sent · sent_at = 그 시도의 claimed_at · 줄 표지 그대로(그 줄 알림 끝) · mail-4a 판정 516: sales 쓰기 + manager 이상 · 메모 필수';
comment on function public.mail_outbox_retry(uuid, text) is 'mail-2a 판정 514 — unknown 메일이 안 나간 것을 확인하고 같은 메일을 다시 큐에: queued · next_attempt_at = now() · 시도 수 0 · 줄 표지 그대로 · failed 는 안 된다(표지가 이미 풀려 다음 회차가 다시 싣는다) · mail-4a 판정 516: sales 쓰기 + manager 이상 · 메모 필수';
comment on function public.mail_outbox_cancel(uuid, text) is 'mail-2a 판정 514 — queued · unknown 메일을 취소(손님과 직접 연락함 등): cancelled · 줄 표지 그대로(그 줄 알림 끝 · 다음 회차에 다시 안 실림 · 상태 cancelled) · mail-4a 판정 516: sales 쓰기 + manager 이상 · 메모 필수';

-- ═══ ② 판정 507 · 517 — customer_update 재발행(원본 20261006131814_master_cs_par_1.sql:96) ═══
create or replace function public.customer_update(p_changes jsonb, p_commit boolean default false, p_ack text[] default '{}')
  returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_staff    uuid;
  v_master   boolean;
  v_mgr_ok   boolean;                                                              -- mail-4a 판정 517: manager 이상인가
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_changes  jsonb := '[]'::jsonb;
  v_reviewed uuid[] := '{}';
  v_money    text[] := array['price_tier', 'discount_pct', 'payment_term_id', 'currency_id', 'ar_account_id', 'sale_account_id', 'default_bill_to_customer_id', 'invoice_split_by_store', 'is_active'];   -- 판정 241(cs-3): 켜기 · 끄기도 master 만 · 판정 254(cs-par-1): is_bill_parent 는 뺐다(받은 값을 비춰 둘 뿐 · 적재가 매번 덮는다)
  v_general  text[] := array['name', 'display_name', 'note', 'tax_rule', 'default_location_id', 'default_carrier', 'tax_number', 'tags', 'is_legal_entity', 'default_ship_to_customer_id'];   -- 판정 252(cs-par-1): parent_id 는 v_struct 로
  v_struct   text[] := array['parent_id'];   -- cs-par-1 판정 252(이견 5) — 문은 master(돈 칸과 같은 문) · 저장은 reviewed · open_so_keep_old 경고 없이(오더에 복사되는 조건이 아니다)
  v_mgr      text[] := array['backorder_mail'];   -- mail-4a 판정 507 · 517: 백오더 알림 받기 — 값이 바뀔 때만 manager 이상(sales 는 보기만 · 판정 237 의 일반 칸 = sales 의 예외)
  v_afields  text[] := array['type', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country', 'label'];
  v_cfields  text[] := array['name', 'phone', 'mobile_phone', 'fax', 'email', 'website', 'job_title', 'include_in_email', 'marketing_consent'];
  v_n        int;
  v_i        int := 0;
  v_c        jsonb;
  v_op       text;
  v_field    text;
  v_cid      uuid;
  v_key      text;
  v_cust     public.customer%rowtype;
  v_cur      text;
  v_new      text;
  v_num      numeric;
  v_seen     text[] := '{}';
  v_touched  uuid[] := '{}';
  v_money_ok uuid[] := '{}';
  v_addr_ch  uuid[] := '{}';
  v_tier     public.ref_price_tier%rowtype;
  v_term     public.ref_payment_term%rowtype;
  v_curr     public.ref_currency%rowtype;
  v_acct     public.ref_account%rowtype;
  v_wh       public.ref_warehouse%rowtype;
  v_other    public.customer%rowtype;
  v_a        public.customer_address%rowtype;
  v_ct       public.customer_contact%rowtype;
  v_vals     jsonb;
  v_olds     jsonb;
  v_f        text;
  v_folded   text;
  v_n_act    int;
  v_n_off    int;
  v_matches  jsonb;
  v_open_so  int;
  v_open_inv int;
  v_inv_due  numeric;
  v_bal      numeric;
  v_kids     int;
  v_consent  text;
  v_keys     text[];
  v_unacked  text[];
  v_rid      uuid;
  v_newdef   text[] := '{}';   -- 이 호출이 새 기본을 세우는 자리 — <customer_id>:<type>(주소) · <customer_id>(연락처) — 그 자리의 옛 기본을 끄는 op 는 알리지 않는다
begin
  -- ⭐ 문(판정 237) — sales 또는 master 쓰기 · 문장은 ims_require_write 모양(2a 와 같다)
  if not (public.ims_can_write('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  v_mgr_ok := coalesce(public.ims_role_rank((select s.role from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active)), 0) >= public.ims_role_rank('manager');   -- mail-4a 판정 517
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- ① 모양
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then raise exception 'p_changes must be a JSON array of changes — nothing was saved'; end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 1000 then raise exception 'Too many changes in one call (% — the limit is 1,000) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_op := v_c->>'op';
    if v_op is null or v_op not in ('set', 'address_add', 'address_set', 'address_off', 'address_default', 'contact_add', 'contact_set', 'contact_off', 'contact_default') then
      raise exception 'Unknown op % — one of set · address_add · address_set · address_off · address_default · contact_add · contact_set · contact_off · contact_default — nothing was saved', coalesce(v_op, '(blank)');
    end if;
    if v_op = 'address_add' and coalesce((v_c->'values'->>'is_default_for_type')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '') || ':' || btrim(coalesce(v_c->'values'->>'type', ''))); end if;
    if v_op = 'address_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '') || ':' || coalesce((select a.type from public.customer_address a where a.id = nullif(v_c->>'address_id', '')::uuid), '')); end if;
    if v_op = 'contact_add' and coalesce((v_c->'values'->>'is_default')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '')); end if;
    if v_op = 'contact_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'customer_id', '')); end if;
  end loop;

  -- ② 검사 — 줄마다(현재 값은 지금 읽는다 · 저장은 ③에서 같은 순서로)
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op';
    v_field := nullif(btrim(v_c->>'field'), '');
    v_cid := nullif(v_c->>'customer_id', '')::uuid;
    v_key := coalesce(v_cid::text, '(blank)');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'customer_id', v_cid, 'op', v_op, 'field', v_field, 'applied', false);
    select * into v_cust from public.customer c where c.id = v_cid;
    if v_cid is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':customer_unknown', 'customer_id', v_cid, 'code', 'customer_unknown', 'message', format('Change %s: the customer does not exist — nothing was saved', v_i));
      continue;
    end if;
    v_touched := array_append(v_touched, v_cid);

    -- ── set ──
    if v_op = 'set' then
      if v_field is null or not (v_field = any(v_general) or v_field = any(v_money) or v_field = any(v_struct) or v_field = any(v_mgr)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(blank)'), 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: field %s cannot be changed here — nothing was saved', v_cust.name, coalesce(v_field, '(blank)')));
        continue;
      end if;
      if (v_key || ':' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s %s is changed twice in this call — keep one — nothing was saved', v_cust.name, v_field));
        continue;
      end if;
      v_seen := array_append(v_seen, v_key || ':' || v_field);
      if (v_field = any(v_money) or v_field = any(v_struct)) and not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_field, 'customer_id', v_cid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change %s of %s — nothing was saved', v_field, v_cust.name));
        continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s %s: the old value the screen saw is missing — nothing was saved', v_cust.name, v_field));
        continue;
      end if;
      v_cur := case v_field
        when 'name' then v_cust.name when 'display_name' then v_cust.display_name when 'note' then v_cust.note when 'tax_rule' then v_cust.tax_rule
        when 'default_location_id' then v_cust.default_location_id::text when 'default_carrier' then v_cust.default_carrier when 'tax_number' then v_cust.tax_number when 'tags' then v_cust.tags
        when 'is_legal_entity' then v_cust.is_legal_entity::text when 'parent_id' then v_cust.parent_id::text when 'default_ship_to_customer_id' then v_cust.default_ship_to_customer_id::text when 'is_active' then v_cust.is_active::text
        when 'price_tier' then v_cust.price_tier when 'discount_pct' then v_cust.discount_pct::text when 'payment_term_id' then v_cust.payment_term_id::text when 'currency_id' then v_cust.currency_id::text
        when 'ar_account_id' then v_cust.ar_account_id::text when 'sale_account_id' then v_cust.sale_account_id::text when 'default_bill_to_customer_id' then v_cust.default_bill_to_customer_id::text
        when 'invoice_split_by_store' then v_cust.invoice_split_by_store::text when 'backorder_mail' then v_cust.backorder_mail::text end;
      if (case when v_field = 'discount_pct' then (v_cur::numeric is distinct from nullif(v_c->>'old', '')::numeric)
               when v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store', 'backorder_mail') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean)
               else (v_cur is distinct from nullif(v_c->>'old', '')) end) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of %s (now "%s") — check again — nothing was saved', v_field, v_cust.name, coalesce(v_cur, '')));
        continue;
      end if;
      v_new := nullif(btrim(v_c->>'value'), '');
      -- 값 검사(바꾸는 칸만 · 옛 값은 보지 않는다)
      if v_field = 'name' then
        if v_new is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'customer_id', v_cid, 'code', 'name_missing', 'message', format('%s cannot have an empty name — nothing was saved', v_cust.name));
        else
          v_folded := lower(regexp_replace(v_new, '\s+', ' ', 'g'));
          select count(*) filter (where c.is_active), count(*) filter (where not c.is_active),
                 coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'is_active', c.is_active) order by c.is_active desc, c.created_at) filter (where c.rn <= 5), '[]'::jsonb)
            into v_n_act, v_n_off, v_matches
            from (select c0.*, row_number() over (order by c0.is_active desc, c0.created_at) as rn from public.customer c0 where c0.id <> v_cid and lower(regexp_replace(btrim(c0.name), '\s+', ' ', 'g')) = v_folded) c;
          if v_n_act > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':name_exists', 'customer_id', v_cid, 'code', 'name_exists', 'matches', v_matches, 'message', format('%s active customer(s) already have the name "%s" — is this really the same name? Confirm to rename anyway', v_n_act, v_new));
          elsif v_n_off > 0 then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':name_matches_inactive', 'customer_id', v_cid, 'code', 'name_matches_inactive', 'matches', v_matches, 'message', format('%s inactive customer(s) have the name "%s" — confirm to rename anyway', v_n_off, v_new));
          end if;
        end if;
      elsif v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store', 'backorder_mail') then
        if v_new is null or v_new not in ('true', 'false') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_field, 'customer_id', v_cid, 'code', 'value_invalid', 'message', format('%s %s must be true or false — nothing was saved', v_cust.name, v_field));
        elsif v_field = 'is_active' and v_new = 'false' then
          -- 끄기 — 알리기 넷(판정 B-4) · so_create 가 새 오더를 막는 것은 기존 동작
          select count(*) into v_open_so from public.so s where s.customer_id = v_cid and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed');
          select count(*), coalesce(sum(public.so_invoice_remaining(i.id)), 0) into v_open_inv, v_inv_due from public.so_invoice i where i.bill_to_customer_id = v_cid and i.status = 'issued' and public.so_invoice_remaining(i.id) > 0;
          select coalesce(sum(b.available), 0) + coalesce(sum(b.owed_credit), 0) into v_bal from public.so_customer_balance(v_cid) b;
          select count(*) into v_kids from public.customer k where k.is_active and k.id <> v_cid and (k.parent_id = v_cid or k.default_ship_to_customer_id = v_cid or k.default_bill_to_customer_id = v_cid);
          if v_open_so > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_so', 'customer_id', v_cid, 'code', 'inactive_open_so', 'count', v_open_so, 'message', format('%s has %s open order(s) — they keep running; new orders will be refused once the customer is inactive. Confirm to deactivate', v_cust.name, v_open_so)); end if;
          if v_open_inv > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_invoice', 'customer_id', v_cid, 'code', 'inactive_open_invoice', 'count', v_open_inv, 'amount', v_inv_due, 'message', format('%s has %s unpaid invoice(s) (%s due) — confirm to deactivate', v_cust.name, v_open_inv, v_inv_due)); end if;
          if v_bal <> 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_balance', 'customer_id', v_cid, 'code', 'inactive_balance', 'amount', v_bal, 'message', format('%s has a balance (available + credit = %s) — confirm to deactivate', v_cust.name, v_bal)); end if;
          if v_kids > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_children', 'customer_id', v_cid, 'code', 'inactive_children', 'count', v_kids, 'message', format('%s active customer(s) point at %s as parent, ship-to or bill-to — confirm to deactivate', v_kids, v_cust.name)); end if;
        elsif v_field = 'is_active' and v_new = 'true' then
          v_folded := lower(regexp_replace(btrim(v_cust.name), '\s+', ' ', 'g'));
          select count(*), coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) order by c.created_at), '[]'::jsonb) into v_n_act, v_matches
            from public.customer c where c.id <> v_cid and c.is_active and lower(regexp_replace(btrim(c.name), '\s+', ' ', 'g')) = v_folded;
          if v_n_act > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':name_exists', 'customer_id', v_cid, 'code', 'name_exists', 'matches', v_matches, 'message', format('%s active customer(s) already have the name "%s" — confirm to reactivate anyway', v_n_act, v_cust.name)); end if;
        end if;
      elsif v_field = 'discount_pct' then
        if v_new is null or v_new !~ '^[0-9]+(\.[0-9]+)?$' or v_new::numeric > 100 then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid', 'customer_id', v_cid, 'code', 'discount_invalid', 'message', format('%s: discount_pct must be a number from 0 to 100 (got %s) — nothing was saved', v_cust.name, coalesce(v_new, '(blank)')));
        end if;
      elsif v_field = 'price_tier' then
        select * into v_tier from public.ref_price_tier t where t.name = v_new and t.is_active and t.purpose = 'sale';
        if v_new is null or not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':tier_invalid', 'customer_id', v_cid, 'code', 'tier_invalid', 'message', format('%s: price tier %s does not exist, is inactive or is not a sale tier — nothing was saved', v_cust.name, coalesce(v_new, '(blank)')));
        elsif v_cust.currency_id is not null and v_tier.currency_id <> v_cust.currency_id then
          v_warns := v_warns || jsonb_build_object('key', v_key || ':tier_currency_mismatch', 'customer_id', v_cid, 'code', 'tier_currency_mismatch', 'message', format('Price tier %s is not in the currency of %s (%s) — order prices will not match', v_tier.name, v_cust.name, v_cust.currency_code));
        end if;
      elsif v_field = 'payment_term_id' then
        select * into v_term from public.ref_payment_term t where t.id = v_new::uuid and t.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':payment_term_invalid', 'customer_id', v_cid, 'code', 'payment_term_invalid', 'message', format('%s: the payment term does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field = 'currency_id' then
        select * into v_curr from public.ref_currency r where r.id = v_new::uuid and r.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_invalid', 'customer_id', v_cid, 'code', 'currency_invalid', 'message', format('%s: the currency does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field in ('ar_account_id', 'sale_account_id') then
        select * into v_acct from public.ref_account a where a.id = v_new::uuid and a.is_active;
        if v_new is null or not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || replace(v_field, '_id', '_invalid'), 'customer_id', v_cid, 'code', replace(v_field, '_id', '_invalid'), 'message', format('%s: the account does not exist or is inactive — nothing was saved', v_cust.name)); end if;
      elsif v_field = 'default_location_id' then
        if v_new is not null and not exists (select 1 from public.ref_warehouse w where w.id = v_new::uuid and w.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':warehouse_unknown', 'customer_id', v_cid, 'code', 'warehouse_unknown', 'message', format('%s: the default warehouse does not exist or is inactive — nothing was saved', v_cust.name));
        end if;
      elsif v_field = 'parent_id' then
        if v_new is not null then
          select * into v_other from public.customer c where c.id = v_new::uuid and c.is_active;
          if v_new::uuid = v_cid then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_self', 'customer_id', v_cid, 'code', 'parent_self', 'message', format('%s cannot be its own parent — nothing was saved', v_cust.name));
          elsif not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_unknown', 'customer_id', v_cid, 'code', 'parent_unknown', 'message', format('%s: the parent customer does not exist or is inactive — nothing was saved', v_cust.name));
          elsif v_other.parent_id is not null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_has_parent', 'customer_id', v_cid, 'code', 'parent_has_parent', 'message', format('%s already has a parent — a customer tree is one level deep — nothing was saved', v_other.name));
          elsif exists (select 1 from public.customer k where k.parent_id = v_cid) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':parent_has_parent', 'customer_id', v_cid, 'code', 'parent_has_parent', 'message', format('%s has children of its own — a customer tree is one level deep — nothing was saved', v_cust.name)); end if;
        end if;
        -- cs-par-1 규칙 4(이견 3 · 7) — 부모를 비우거나 바꿀 때: 같은 호출이 그 옛 부모를 청구처로 다시 보내면 막는다 · 청구처가 옛 부모인데 이 호출이 청구처를 안 바꾸면 트리거(customer_parent_guard)가 null 로 돌린다고 알린다(ack)
        if v_cust.parent_id is not null and v_new is distinct from v_cust.parent_id::text then
          if exists (select 1 from jsonb_array_elements(p_changes) z where z->>'op' = 'set' and nullif(btrim(z->>'field'), '') = 'default_bill_to_customer_id' and nullif(z->>'customer_id', '')::uuid = v_cid and nullif(btrim(z->>'value'), '') = v_cust.parent_id::text) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':bill_to_is_old_parent', 'customer_id', v_cid, 'code', 'bill_to_is_old_parent', 'message', format('%s: the bill-to customer in this call is the parent being removed — pick another bill-to or leave it blank — nothing was saved', v_cust.name));
          elsif v_cust.default_bill_to_customer_id = v_cust.parent_id and not exists (select 1 from jsonb_array_elements(p_changes) z where z->>'op' = 'set' and nullif(btrim(z->>'field'), '') = 'default_bill_to_customer_id' and nullif(z->>'customer_id', '')::uuid = v_cid) then
            v_warns := v_warns || jsonb_build_object('key', v_key || ':bill_to_reset_with_parent', 'customer_id', v_cid, 'code', 'bill_to_reset_with_parent', 'message', format('%s is billed to its parent — removing or changing the parent resets the bill-to to the customer itself. Confirm', v_cust.name));
          end if;
        end if;
      elsif v_field in ('default_ship_to_customer_id', 'default_bill_to_customer_id') then
        -- cs-par-1 규칙 2(이견 6 · 판정 255) — 자기 자신은 null 하나로 표기한다 · 보내면 막는다(CHECK customer_bill_to_not_self_ck · customer_ship_to_not_self_ck 가 모든 길에서 같은 것을 막는다)
        if v_new is not null and v_new::uuid = v_cid then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || case when v_field = 'default_ship_to_customer_id' then 'ship_to_self' else 'bill_to_self' end, 'customer_id', v_cid, 'code', case when v_field = 'default_ship_to_customer_id' then 'ship_to_self' else 'bill_to_self' end, 'message', format('%s cannot be its own %s customer — leave it blank (blank means the customer itself) — nothing was saved', v_cust.name, case when v_field = 'default_ship_to_customer_id' then 'ship-to' else 'bill-to' end));
        end if;
        if v_new is not null and not exists (select 1 from public.customer c where c.id = v_new::uuid and c.is_active) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':' || case when v_field = 'default_ship_to_customer_id' then 'ship_to_unknown' else 'bill_to_unknown' end, 'customer_id', v_cid, 'code', case when v_field = 'default_ship_to_customer_id' then 'ship_to_unknown' else 'bill_to_unknown' end, 'message', format('%s: that customer does not exist or is inactive — nothing was saved', v_cust.name));
        end if;
      end if;
      if v_field = 'backorder_mail' and not v_mgr_ok and v_new is distinct from v_cur then   -- mail-4a 판정 517: 값이 바뀔 때만(같은 값이 실려 와도 막지 않는다)
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':manager_needed:' || v_field, 'customer_id', v_cid, 'code', 'manager_needed', 'message', format('Only a manager or above can turn backorder alerts %s for %s — nothing was saved', case when v_new = 'true' then 'on' else 'off' end, v_cust.name));
      end if;
      if v_field = any(v_money) then v_money_ok := array_append(v_money_ok, v_cid); end if;

    -- ── 주소 op ──
    elsif v_op like 'address_%' then
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      v_olds := coalesce(v_c->'olds', '{}'::jsonb);
      if v_op = 'address_add' then
        v_f := nullif(btrim(v_vals->>'type'), '');
        if v_f is null or v_f not in ('Billing', 'Business', 'Shipping') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_type_invalid:' || v_i, 'customer_id', v_cid, 'code', 'address_type_invalid', 'message', format('%s: address type must be Billing, Business or Shipping (got %s) — nothing was saved', v_cust.name, coalesce(v_f, '(blank)')));
        end if;
        if nullif(btrim(coalesce(v_vals->>'line1', '') || coalesce(v_vals->>'city', '') || coalesce(v_vals->>'postal_code', '')), '') is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_empty:' || v_i, 'customer_id', v_cid, 'code', 'address_empty', 'message', format('%s: the new address has no street, city or postal code — nothing was saved', v_cust.name));
        end if;
      else
        select * into v_a from public.customer_address a where a.id = nullif(v_c->>'address_id', '')::uuid and a.customer_id = v_cid;
        if not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_unknown:' || v_i, 'customer_id', v_cid, 'code', 'address_unknown', 'message', format('%s: that address is not on this customer — nothing was saved', v_cust.name));
          continue;
        end if;
        if (v_key || ':address:' || v_a.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:address:' || v_a.id::text, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same address is changed twice in this call — nothing was saved', v_cust.name));
          continue;
        end if;
        v_seen := array_append(v_seen, v_key || ':address:' || v_a.id::text);
        if v_op = 'address_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_afields)) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:address.' || v_f, 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: address field %s cannot be changed here — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            if not (v_olds ? v_f) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:address.' || v_f, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s: address %s — the old value the screen saw is missing — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            v_cur := case v_f when 'type' then v_a.type when 'line1' then v_a.line1 when 'line2' then v_a.line2 when 'city' then v_a.city when 'state_province' then v_a.state_province when 'postal_code' then v_a.postal_code when 'country' then v_a.country else v_a.label end;
            if v_cur is distinct from nullif(v_olds->>v_f, '') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:address.' || v_f, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the address %s of %s (now "%s") — check again — nothing was saved', v_f, v_cust.name, coalesce(v_cur, '')));
            end if;
            if v_f = 'type' and nullif(btrim(v_vals->>'type'), '') not in ('Billing', 'Business', 'Shipping') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_type_invalid:' || v_i, 'customer_id', v_cid, 'code', 'address_type_invalid', 'message', format('%s: address type must be Billing, Business or Shipping — nothing was saved', v_cust.name));
            end if;
          end loop;
        elsif v_op = 'address_off' then
          if not v_a.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'customer_id', v_cid, 'code', 'address_inactive', 'message', format('%s: that address is already off — nothing was saved', v_cust.name));
          elsif v_a.is_default_for_type and not ((v_key || ':' || v_a.type) = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':address_default_off:' || v_a.type, 'customer_id', v_cid, 'code', 'address_default_off', 'message', format('%s: this is the default %s address — switching it off leaves no default %s address (orders will warn). Confirm', v_cust.name, v_a.type, v_a.type)); end if;
        elsif v_op = 'address_default' then
          if not v_a.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'customer_id', v_cid, 'code', 'address_inactive', 'message', format('%s: an inactive address cannot be the default — switch it on first — nothing was saved', v_cust.name)); end if;
        end if;
      end if;
      v_addr_ch := array_append(v_addr_ch, v_cid);

    -- ── 연락처 op ──
    else
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      v_olds := coalesce(v_c->'olds', '{}'::jsonb);
      if v_op = 'contact_add' then
        if nullif(btrim(coalesce(v_vals->>'name', '') || coalesce(v_vals->>'phone', '') || coalesce(v_vals->>'mobile_phone', '') || coalesce(v_vals->>'email', '')), '') is null then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_empty:' || v_i, 'customer_id', v_cid, 'code', 'contact_empty', 'message', format('%s: the new contact has no name, phone or email — nothing was saved', v_cust.name));
        end if;
        v_consent := nullif(btrim(v_vals->>'marketing_consent'), '');
        if v_consent is not null and v_consent not in ('0', '1', '2', '3') then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':consent_invalid:' || v_i, 'customer_id', v_cid, 'code', 'consent_invalid', 'message', format('%s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — got %s — nothing was saved', v_cust.name, v_consent));
        end if;
      else
        select * into v_ct from public.customer_contact k where k.id = nullif(v_c->>'contact_id', '')::uuid and k.customer_id = v_cid;
        if not found then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_unknown:' || v_i, 'customer_id', v_cid, 'code', 'contact_unknown', 'message', format('%s: that contact is not on this customer — nothing was saved', v_cust.name));
          continue;
        end if;
        if (v_key || ':contact:' || v_ct.id::text) = any(v_seen) then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:contact:' || v_ct.id::text, 'customer_id', v_cid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same contact is changed twice in this call — nothing was saved', v_cust.name));
          continue;
        end if;
        v_seen := array_append(v_seen, v_key || ':contact:' || v_ct.id::text);
        if v_op = 'contact_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_cfields)) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:contact.' || v_f, 'customer_id', v_cid, 'code', 'field_unknown', 'message', format('%s: contact field %s cannot be changed here — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            if not (v_olds ? v_f) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:contact.' || v_f, 'customer_id', v_cid, 'code', 'old_missing', 'message', format('%s: contact %s — the old value the screen saw is missing — nothing was saved', v_cust.name, v_f)); continue;
            end if;
            v_cur := case v_f when 'name' then v_ct.name when 'phone' then v_ct.phone when 'mobile_phone' then v_ct.mobile_phone when 'fax' then v_ct.fax when 'email' then v_ct.email when 'website' then v_ct.website when 'job_title' then v_ct.job_title
                              when 'include_in_email' then v_ct.include_in_email::text else case v_ct.marketing_consent when true then '2' when false then '3' else null end end;
            if (case when v_f = 'include_in_email' then (v_cur::boolean is distinct from nullif(v_olds->>v_f, '')::boolean)
                     when v_f = 'marketing_consent' then (v_cur is distinct from (case nullif(v_olds->>v_f, '') when '2' then '2' when '3' then '3' else null end))
                     else (v_cur is distinct from nullif(v_olds->>v_f, '')) end) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:contact.' || v_f, 'customer_id', v_cid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the contact %s of %s (now "%s") — check again — nothing was saved', v_f, v_cust.name, coalesce(v_cur, '')));
            end if;
            if v_f = 'marketing_consent' and nullif(btrim(v_vals->>v_f), '') is not null and nullif(btrim(v_vals->>v_f), '') not in ('0', '1', '2', '3') then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':consent_invalid:' || v_i, 'customer_id', v_cid, 'code', 'consent_invalid', 'message', format('%s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — nothing was saved', v_cust.name));
            end if;
          end loop;
        elsif v_op = 'contact_off' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'customer_id', v_cid, 'code', 'contact_inactive', 'message', format('%s: that contact is already off — nothing was saved', v_cust.name));
          elsif v_ct.is_default and not (v_key = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':contact_default_off', 'customer_id', v_cid, 'code', 'contact_default_off', 'message', format('%s: this is the default contact — switching it off leaves no default contact. Confirm', v_cust.name)); end if;
        elsif v_op = 'contact_default' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'customer_id', v_cid, 'code', 'contact_inactive', 'message', format('%s: an inactive contact cannot be the default — switch it on first — nothing was saved', v_cust.name)); end if;
        end if;
      end if;
    end if;
  end loop;

  -- 열린 오더 알리기 — 돈 칸 · 주소를 바꾸는 손님마다(열린 SO 는 복사해 굳힌 값 그대로 · master-cs-0 §C)
  for v_cid in select distinct u from unnest(v_money_ok || v_addr_ch) as u loop
    select count(*), max(c.name) into v_open_so, v_cur from public.so s join public.customer c on c.id = s.customer_id where s.customer_id = v_cid and s.status in ('draft', 'confirmed', 'at_wms', 'picking', 'packed');
    if v_open_so > 0 then
      v_warns := v_warns || jsonb_build_object('key', v_cid::text || ':open_so_keep_old', 'customer_id', v_cid, 'code', 'open_so_keep_old', 'count', v_open_so, 'message', format('%s has %s open order(s) — they keep the old terms and addresses; only new orders get the change. Confirm', v_cur, v_open_so));
    end if;
  end loop;

  -- ③ 판정
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns, 'reviewed_now', '[]'::jsonb,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ④ 저장 — 줄 순서대로 · 손님 행 잠금 · 한 트랜잭션 · 23505 는 문장으로
  begin
    perform 1 from public.customer c where c.id = any(v_touched) for update;
    v_i := 0;
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_cid := (v_c->>'customer_id')::uuid;
      v_new := nullif(btrim(v_c->>'value'), '');
      v_vals := coalesce(v_c->'values', '{}'::jsonb);
      if v_op = 'set' then
        case v_field
          when 'name' then update public.customer set name = v_new, updated_by = v_staff where id = v_cid;
          when 'display_name' then update public.customer set display_name = v_new, updated_by = v_staff where id = v_cid;
          when 'note' then update public.customer set note = v_new, updated_by = v_staff where id = v_cid;
          when 'tax_rule' then update public.customer set tax_rule = v_new, updated_by = v_staff where id = v_cid;
          when 'default_location_id' then update public.customer set default_location_id = v_new::uuid, default_location_name = (select w.name from public.ref_warehouse w where w.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'default_carrier' then update public.customer set default_carrier = v_new, updated_by = v_staff where id = v_cid;
          when 'tax_number' then update public.customer set tax_number = v_new, updated_by = v_staff where id = v_cid;
          when 'tags' then update public.customer set tags = v_new, updated_by = v_staff where id = v_cid;
          when 'is_legal_entity' then update public.customer set is_legal_entity = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'parent_id' then update public.customer set parent_id = v_new::uuid, parent_source = case when v_new is null then null else 'ims' end, updated_by = v_staff where id = v_cid;   -- 판정 253(cs-par-1): 창구가 세우거나 바꾸면 ims · 비우면 null
          when 'default_ship_to_customer_id' then update public.customer set default_ship_to_customer_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'is_active' then update public.customer set is_active = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'price_tier' then update public.customer set price_tier = v_new, updated_by = v_staff where id = v_cid;
          when 'discount_pct' then update public.customer set discount_pct = v_new::numeric, updated_by = v_staff where id = v_cid;
          when 'payment_term_id' then update public.customer set payment_term_id = v_new::uuid, payment_term_name = (select t.name from public.ref_payment_term t where t.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'currency_id' then update public.customer set currency_id = v_new::uuid, currency_code = (select r.code from public.ref_currency r where r.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'ar_account_id' then update public.customer set ar_account_id = v_new::uuid, ar_account_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'sale_account_id' then update public.customer set sale_account_id = v_new::uuid, sale_account_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_cid;
          when 'default_bill_to_customer_id' then update public.customer set default_bill_to_customer_id = v_new::uuid, updated_by = v_staff where id = v_cid;
          when 'invoice_split_by_store' then update public.customer set invoice_split_by_store = v_new::boolean, updated_by = v_staff where id = v_cid;
          when 'backorder_mail' then update public.customer set backorder_mail = v_new::boolean, updated_by = v_staff where id = v_cid;   -- mail-4a 판정 507 · 517(누가 · 언제 = updated_by · updated_at — 다른 칸과 같다)
        end case;
        -- 판정 240 — 돈 칸을 master 가 바꾸면 확인 · 처음 확인만 남긴다
        if v_field = any(v_money) then
          update public.customer set reviewed_by = v_staff, reviewed_at = now() where id = v_cid and reviewed_at is null returning id into v_rid;
          if v_rid is not null then v_reviewed := array_append(v_reviewed, v_rid); v_rid := null; end if;
        end if;
      elsif v_op = 'address_add' then
        v_f := btrim(v_vals->>'type');
        if coalesce((v_vals->>'is_default_for_type')::boolean, false) then
          update public.customer_address set is_default_for_type = false, updated_by = v_staff where customer_id = v_cid and type = v_f and is_default_for_type;
        end if;
        insert into public.customer_address (customer_id, source, updated_by, type, is_default_for_type, label, line1, line2, city, state_province, postal_code, country)
        values (v_cid, 'manual', v_staff, v_f, coalesce((v_vals->>'is_default_for_type')::boolean, false), nullif(btrim(v_vals->>'label'), ''), nullif(btrim(v_vals->>'line1'), ''), nullif(btrim(v_vals->>'line2'), ''),
                nullif(btrim(v_vals->>'city'), ''), nullif(btrim(v_vals->>'state_province'), ''), nullif(btrim(v_vals->>'postal_code'), ''), nullif(btrim(v_vals->>'country'), ''))
        returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'address_set' then
        update public.customer_address a set
          type = case when v_vals ? 'type' then btrim(v_vals->>'type') else a.type end,
          line1 = case when v_vals ? 'line1' then nullif(btrim(v_vals->>'line1'), '') else a.line1 end,
          line2 = case when v_vals ? 'line2' then nullif(btrim(v_vals->>'line2'), '') else a.line2 end,
          city = case when v_vals ? 'city' then nullif(btrim(v_vals->>'city'), '') else a.city end,
          state_province = case when v_vals ? 'state_province' then nullif(btrim(v_vals->>'state_province'), '') else a.state_province end,
          postal_code = case when v_vals ? 'postal_code' then nullif(btrim(v_vals->>'postal_code'), '') else a.postal_code end,
          country = case when v_vals ? 'country' then nullif(btrim(v_vals->>'country'), '') else a.country end,
          label = case when v_vals ? 'label' then nullif(btrim(v_vals->>'label'), '') else a.label end,
          updated_by = v_staff
        where a.id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_off' then
        update public.customer_address set is_active = false, is_default_for_type = false, updated_by = v_staff where id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_default' then
        select * into v_a from public.customer_address a where a.id = (v_c->>'address_id')::uuid;
        update public.customer_address a set is_default_for_type = (a.id = v_a.id), updated_by = v_staff where a.customer_id = v_cid and a.type = v_a.type and a.is_active and (a.is_default_for_type or a.id = v_a.id);
      elsif v_op = 'contact_add' then
        v_consent := nullif(btrim(v_vals->>'marketing_consent'), '');
        if coalesce((v_vals->>'is_default')::boolean, false) then
          update public.customer_contact set is_default = false, updated_by = v_staff where customer_id = v_cid and is_default;
        end if;
        insert into public.customer_contact (customer_id, source, updated_by, name, phone, mobile_phone, fax, email, website, job_title, include_in_email, marketing_consent, is_default)
        values (v_cid, 'manual', v_staff, nullif(btrim(v_vals->>'name'), ''), nullif(btrim(v_vals->>'phone'), ''), nullif(btrim(v_vals->>'mobile_phone'), ''), nullif(btrim(v_vals->>'fax'), ''), nullif(btrim(v_vals->>'email'), ''),
                nullif(btrim(v_vals->>'website'), ''), nullif(btrim(v_vals->>'job_title'), ''), coalesce((v_vals->>'include_in_email')::boolean, false),
                case v_consent when '2' then true when '3' then false else null end, coalesce((v_vals->>'is_default')::boolean, false))
        returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'contact_set' then
        update public.customer_contact k set
          name = case when v_vals ? 'name' then nullif(btrim(v_vals->>'name'), '') else k.name end,
          phone = case when v_vals ? 'phone' then nullif(btrim(v_vals->>'phone'), '') else k.phone end,
          mobile_phone = case when v_vals ? 'mobile_phone' then nullif(btrim(v_vals->>'mobile_phone'), '') else k.mobile_phone end,
          fax = case when v_vals ? 'fax' then nullif(btrim(v_vals->>'fax'), '') else k.fax end,
          email = case when v_vals ? 'email' then nullif(btrim(v_vals->>'email'), '') else k.email end,
          website = case when v_vals ? 'website' then nullif(btrim(v_vals->>'website'), '') else k.website end,
          job_title = case when v_vals ? 'job_title' then nullif(btrim(v_vals->>'job_title'), '') else k.job_title end,
          include_in_email = case when v_vals ? 'include_in_email' then coalesce((v_vals->>'include_in_email')::boolean, false) else k.include_in_email end,
          marketing_consent = case when v_vals ? 'marketing_consent' then (case nullif(btrim(v_vals->>'marketing_consent'), '') when '2' then true when '3' then false else null end) else k.marketing_consent end,
          updated_by = v_staff
        where k.id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_off' then
        update public.customer_contact set is_active = false, is_default = false, updated_by = v_staff where id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_default' then
        update public.customer_contact k set is_default = (k.id = (v_c->>'contact_id')::uuid), updated_by = v_staff where k.customer_id = v_cid and k.is_active and (k.is_default or k.id = (v_c->>'contact_id')::uuid);
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'Two defaults would remain for one customer (%) — set one default per address type and one default contact — nothing was saved', coalesce(sqlerrm, '');
  end;

  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'reviewed_now', to_jsonb(v_reviewed));
end;
$$;

-- ═══ ③ tick 실패 남기기(mail-3 이견 3) ═══
create table public.mail_run_error (
  id              bigint generated always as identity primary key,
  kind            text not null,
  location_id     uuid not null references public.ref_warehouse(id),
  run_on          date not null,
  first_at        timestamptz not null,
  last_at         timestamptz not null,
  attempts        int not null default 1,
  message         text not null,
  resolved_at     timestamptz,
  resolved_run_id uuid references public.mail_run(id),
  constraint mail_run_error_kind_ck     check (kind in ('backorder_ready')),
  constraint mail_run_error_attempts_ck check (attempts >= 1),
  constraint mail_run_error_resolved_ck check ((resolved_run_id is null) or (resolved_at is not null))
);
create unique index mail_run_error_open_uq on public.mail_run_error (kind, location_id, run_on) where resolved_at is null;
comment on table public.mail_run_error is 'mail-4a(mail-3 이견 3) — 창고 회차가 tick 안에서 실패해 되돌아간 기록(되돌아간 뒤에도 남는다 · cron 기록은 성공으로 남기 때문). 같은 창고 · 같은 날 · 풀리지 않은 것은 한 줄 — 다시 실패하면 attempts + 1 · last_at · message(마지막 것)만. 그날 그 창고 회차가 서면 resolved_at · resolved_run_id. 쓰기는 tick 만 · 읽기는 mail_runs_list';
alter table public.mail_run_error enable row level security;
revoke all on public.mail_run_error from anon, authenticated;

create or replace function public.mail_backorder_tick(p_now timestamptz default now()) returns jsonb
  language plpgsql volatile security definer
  set search_path = public, pg_temp
as $$
declare
  v_sched jsonb;
  v_wh    text;
  v_e     jsonb;
  v_local timestamp;
  v_run   uuid;
  v_pick  jsonb;
  v_from  text := (select c.value from public.inv_config c where c.key = 'mail_backorder_from');
  v_name  text := (select c.value from public.inv_config c where c.key = 'mail_backorder_from_name');
  v_reply text := nullif((select c.value from public.inv_config c where c.key = 'mail_backorder_reply_to'), '');
  v_mails int;
  v_lines int;
  v_runs  jsonb := '[]'::jsonb;
  v_err   text;
begin
  -- ⚠️ 꺼져 있으면 회차 · 줄 표지를 쌓지 않는다(보내지도 않은 줄이 「알림 받음」 이 된다)
  if coalesce((select c.value from public.inv_config c where c.key = 'mail_enabled'), 'off') <> 'on' then
    return jsonb_build_object('enabled', false, 'as_of', p_now, 'runs', v_runs);
  end if;
  v_sched := coalesce((select c.value::jsonb from public.inv_config c where c.key = 'mail_backorder_schedule'), '{}'::jsonb);
  for v_wh, v_e in select x.key, x.value from jsonb_each(v_sched) x order by x.key loop
    continue when not exists (select 1 from public.ref_warehouse w where w.id = v_wh::uuid and w.is_active);      -- mail-1a 이견 10: 비활성 창고는 건너뜀
    v_local := p_now at time zone (v_e->>'tz');
    continue when coalesce(public.mail_backorder_next_slot(v_wh::uuid, v_e, p_now), 'infinity') > p_now;   -- mail-1c: 503 · 512 견주기를 속 함수 하나로(미리 보기의 next_run_at 과 같은 규칙) · 요일 ∈ days · 시 ≥ hour · 그날 회차 없음
    begin                                                                                           -- 이견 4: 창고마다 서브트랜잭션 — 실패하면 이 창고의 회차 · 메일 · 줄 표지 전부 되돌림
      v_run := null;
      insert into public.mail_run (kind, location_id, run_on, started_at, params)
      values ('backorder_ready', v_wh::uuid, v_local::date, p_now,
              jsonb_build_object('schedule', v_e, 'min_fill_pct', (select c.value from public.inv_config c where c.key = 'mail_backorder_min_fill_pct'),
                                 'from', v_from, 'from_name', v_name, 'reply_to', v_reply))
      on conflict (kind, location_id, run_on) do nothing
      returning id into v_run;
      continue when v_run is null;
      v_pick := public.mail_backorder_pick(v_wh::uuid, p_now);
      insert into public.mail_outbox (kind, category, status, from_address, from_name, reply_to, to_address, payload, customer_id, location_id, run_id, next_attempt_at, dedupe_key)
      select 'backorder_ready', 'transactional', 'queued', v_from, v_name, v_reply, m->>'to',
             jsonb_build_object('customer_id', m->'customer_id', 'customer_name', m->'customer_name', 'location_id', v_pick->'location_id', 'location_name', v_pick->'location_name',
                                'as_of', p_now, 'lines', m->'lines'),
             (m->>'customer_id')::uuid, v_wh::uuid, v_run, p_now, 'bo:' || v_run || ':' || (m->>'customer_id')
      from jsonb_array_elements(v_pick->'mails') m;
      get diagnostics v_mails = row_count;
      insert into public.mail_backorder_line (outbox_id, so_line_id, basis, qty_open, can_fill_units, available_units)   -- 줄마다 한 번 — 유니크(so_line_id where released_at is null)에 걸리면 이 창고 회차 전체가 실패
      select o.id, (l->>'line_id')::uuid, l->>'basis', (l->>'qty_open')::numeric, (l->>'can_fill_units')::numeric, (l->>'available_units')::numeric
      from jsonb_array_elements(v_pick->'mails') m
      join public.mail_outbox o on o.dedupe_key = 'bo:' || v_run || ':' || (m->>'customer_id')
      cross join lateral jsonb_array_elements(m->'lines') l;
      get diagnostics v_lines = row_count;
      update public.mail_run
         set mails = v_mails, lines = v_lines,
             no_email = coalesce((select jsonb_agg(jsonb_build_object('customer_id', s->'customer_id', 'reason', s->'reason', 'lines', jsonb_array_length(s->'lines')) order by s->>'customer_id')
                                  from jsonb_array_elements(v_pick->'skipped') s), '[]'::jsonb),
             params = params || jsonb_build_object('since', v_pick->'since')
       where id = v_run;
      v_runs := v_runs || jsonb_build_object('location_id', v_wh, 'status', 'ran', 'run_id', v_run, 'run_on', v_local::date, 'mails', v_mails, 'lines', v_lines,
                                             'skipped', jsonb_array_length(v_pick->'skipped'));
      update public.mail_run_error set resolved_at = p_now, resolved_run_id = v_run                    -- mail-4a: 그 창고 · 그날 회차가 섰다 → 앞선 실패 풀림
       where kind = 'backorder_ready' and location_id = v_wh::uuid and run_on = v_local::date and resolved_at is null;
    exception when others then
      get stacked diagnostics v_err = message_text;
      raise warning 'mail_backorder_tick: warehouse % failed and was rolled back — %', v_wh, v_err;
      insert into public.mail_run_error (kind, location_id, run_on, first_at, last_at, message)          -- mail-4a(mail-3 이견 3): 되돌아간 뒤에도 남는다 · 같은 창고 · 날은 한 줄
      values ('backorder_ready', v_wh::uuid, v_local::date, p_now, p_now, left(coalesce(v_err, 'failed'), 2000))
      on conflict (kind, location_id, run_on) where resolved_at is null
      do update set attempts = public.mail_run_error.attempts + 1, last_at = excluded.last_at, message = excluded.message;
      v_runs := v_runs || jsonb_build_object('location_id', v_wh, 'status', 'failed', 'error', v_err);
    end;
  end loop;
  return jsonb_build_object('enabled', true, 'as_of', p_now, 'runs', v_runs);
end;
$$;

-- ═══ ④ 화면 읽기 창구(sales 보기) ═══
create function public.mail_runs_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['location_id', 'from', 'to', 'problems', 'limit', 'offset'];
  v_bad    text;
  v_prob   boolean;
  v_limit  int;
  v_offset int;
  v_out    jsonb;
begin
  if not public.ims_can_view('sales') then raise exception 'Backorders needs the sales permission — nothing was read'; end if;
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  v_prob   := coalesce(nullif(f->>'problems', '')::boolean, false);
  v_limit  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 50), 1), 500);
  v_offset := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  with r as (
    select r.*, w.name as location_name,
           coalesce((select jsonb_object_agg(x.status, x.n) from (select o.status, count(*) as n from public.mail_outbox o where o.run_id = r.id group by o.status) x), '{}'::jsonb) as by_status,
           coalesce((select jsonb_object_agg(x.reason, x.n) from (select e->>'reason' as reason, count(*) as n from jsonb_array_elements(r.no_email) e group by 1) x), '{}'::jsonb) as skipped,
           (select jsonb_build_object('attempts', e.attempts, 'first_at', e.first_at, 'last_at', e.last_at, 'message', e.message, 'resolved_at', e.resolved_at)
              from public.mail_run_error e where e.kind = r.kind and e.location_id = r.location_id and e.run_on = r.run_on order by e.last_at desc limit 1) as tick_error
    from public.mail_run r join public.ref_warehouse w on w.id = r.location_id
    where (f->>'location_id' is null or r.location_id = (f->>'location_id')::uuid)
      and (f->>'from' is null or r.run_on >= (f->>'from')::date) and (f->>'to' is null or r.run_on <= (f->>'to')::date)
  ),
  flt as (
    select * from r
    where not v_prob or coalesce((by_status->>'failed')::int, 0) > 0 or coalesce((by_status->>'unknown')::int, 0) > 0 or chat_error is not null or tick_error is not null
  ),
  te as (
    select e.*, w.name as location_name from public.mail_run_error e join public.ref_warehouse w on w.id = e.location_id
    where (f->>'location_id' is null or e.location_id = (f->>'location_id')::uuid)
      and (f->>'from' is null or e.run_on >= (f->>'from')::date) and (f->>'to' is null or e.run_on <= (f->>'to')::date)
      and (not v_prob or e.resolved_at is null)
  )
  select jsonb_build_object(
    'total', (select count(*) from flt), 'limit', v_limit, 'offset', v_offset, 'filters', f,
    'runs', coalesce((select jsonb_agg(jsonb_build_object(
        'run_id', x.id, 'kind', x.kind, 'location_id', x.location_id, 'location_name', x.location_name, 'run_on', x.run_on, 'started_at', x.started_at, 'mails', x.mails, 'lines', x.lines,
        'sent', coalesce((x.by_status->>'sent')::int, 0), 'failed', coalesce((x.by_status->>'failed')::int, 0), 'unknown', coalesce((x.by_status->>'unknown')::int, 0),
        'queued', coalesce((x.by_status->>'queued')::int, 0) + coalesce((x.by_status->>'sending')::int, 0), 'cancelled', coalesce((x.by_status->>'cancelled')::int, 0),
        'skipped', x.skipped, 'chat_posted_at', x.chat_posted_at, 'chat_error', x.chat_error, 'chat_attempts', x.chat_attempts, 'tick_error', x.tick_error)
      order by x.started_at desc, x.id) from (select * from flt order by started_at desc, id limit v_limit offset v_offset) x), '[]'::jsonb),
    'tick_errors', coalesce((select jsonb_agg(jsonb_build_object(
        'id', t.id, 'kind', t.kind, 'location_id', t.location_id, 'location_name', t.location_name, 'run_on', t.run_on, 'first_at', t.first_at, 'last_at', t.last_at,
        'attempts', t.attempts, 'message', t.message, 'resolved_at', t.resolved_at, 'resolved_run_id', t.resolved_run_id) order by t.last_at desc, t.id)
      from (select * from te order by last_at desc, id limit 100) t), '[]'::jsonb))
  into v_out;
  return v_out;
end;
$$;
comment on function public.mail_runs_list(jsonb) is 'mail-4a — 메일 화면의 회차 목록(sales 보기). 거르기 location_id · from · to(run_on) · problems(failed · unknown · chat_error · tick 오류가 있는 회차만 · tick_errors 는 풀리지 않은 것만) · limit(1 ~ 500 · 50) · offset. 반환 {total, runs[{run_id, kind, location_id, location_name, run_on, started_at, mails, lines, sent, failed, unknown, queued(sending 포함), cancelled, skipped{reason: 수}, chat_posted_at, chat_error, chat_attempts, tick_error}], tick_errors[…]} — 실패한 창고는 회차 행이 없으므로 tick_errors 로 따로';
revoke all on function public.mail_runs_list(jsonb) from public, anon;
grant execute on function public.mail_runs_list(jsonb) to authenticated;

create function public.mail_outbox_list(p_filters jsonb default '{}'::jsonb) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  f        jsonb := coalesce(p_filters, '{}'::jsonb);
  c_keys   constant text[] := array['status', 'location_id', 'customer_id', 'from', 'to', 'run_id', 'limit', 'offset'];
  v_bad    text;
  v_limit  int;
  v_offset int;
  v_can    boolean;
  v_out    jsonb;
begin
  if not public.ims_can_view('sales') then raise exception 'Backorders needs the sales permission — nothing was read'; end if;
  if jsonb_typeof(f) <> 'object' then raise exception 'p_filters must be a JSON object'; end if;
  select k into v_bad from jsonb_object_keys(f) k where k <> all (c_keys) limit 1;
  if v_bad is not null then raise exception 'Unknown filter %', v_bad; end if;
  if f->>'status' is not null and f->>'status' not in ('queued', 'sending', 'sent', 'failed', 'unknown', 'cancelled') then raise exception 'status must be queued, sending, sent, failed, unknown or cancelled'; end if;
  v_limit  := least(greatest(coalesce(nullif(f->>'limit', '')::int, 100), 1), 500);
  v_offset := greatest(coalesce(nullif(f->>'offset', '')::int, 0), 0);
  v_can    := public.mail_can_resolve();
  with o as (
    select o.*, w.name as location_name, c.name as customer_name
    from public.mail_outbox o
    left join public.ref_warehouse w on w.id = o.location_id
    left join public.customer c on c.id = o.customer_id
    where (f->>'status' is null or o.status = f->>'status')
      and (f->>'location_id' is null or o.location_id = (f->>'location_id')::uuid)
      and (f->>'customer_id' is null or o.customer_id = (f->>'customer_id')::uuid)
      and (f->>'run_id' is null or o.run_id = (f->>'run_id')::uuid)
      and (f->>'from' is null or (o.created_at at time zone 'America/Toronto')::date >= (f->>'from')::date)
      and (f->>'to' is null or (o.created_at at time zone 'America/Toronto')::date <= (f->>'to')::date)
  )
  select jsonb_build_object('total', (select count(*) from o), 'limit', v_limit, 'offset', v_offset, 'filters', f, 'can_resolve', v_can,
    'mails', coalesce((select jsonb_agg(jsonb_build_object(
        'id', x.id, 'kind', x.kind, 'status', x.status, 'to_address', x.to_address, 'original_to', x.original_to, 'subject', x.subject, 'attempts', x.attempts, 'last_error', x.last_error,
        'created_at', x.created_at, 'sent_at', x.sent_at, 'customer_id', x.customer_id, 'customer_name', coalesce(x.customer_name, x.payload->>'customer_name'), 'location_name', x.location_name,
        'so_numbers', (select coalesce(jsonb_agg(distinct l->>'so_number'), '[]'::jsonb) from jsonb_array_elements(coalesce(x.payload->'lines', '[]'::jsonb)) l),
        'line_count', jsonb_array_length(coalesce(x.payload->'lines', '[]'::jsonb)), 'run_id', x.run_id,
        'can_close_sent', v_can and x.status = 'unknown', 'can_retry', v_can and x.status = 'unknown', 'can_cancel', v_can and x.status in ('queued', 'unknown'))
      order by x.created_at desc, x.id) from (select * from o order by created_at desc, id limit v_limit offset v_offset) x), '[]'::jsonb))
  into v_out;
  return v_out;
end;
$$;
comment on function public.mail_outbox_list(jsonb) is 'mail-4a — 메일 화면의 메일 목록(sales 보기). 거르기 status · location_id · customer_id · run_id · from · to(만든 날 · 토론토) · limit(1 ~ 500 · 100) · offset. 행마다 can_close_sent · can_retry(unknown) · can_cancel(queued · unknown) = 상태 ∧ mail_can_resolve()(판정 516) — 화면이 판정을 다시 짜지 않는다';
revoke all on function public.mail_outbox_list(jsonb) from public, anon;
grant execute on function public.mail_outbox_list(jsonb) to authenticated;

create function public.mail_outbox_detail(p_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_o   public.mail_outbox%rowtype;
  v_can boolean;
begin
  if not public.ims_can_view('sales') then raise exception 'Backorders needs the sales permission — nothing was read'; end if;
  select * into v_o from public.mail_outbox o where o.id = p_id;
  if not found then raise exception 'Mail % not found', p_id; end if;
  v_can := public.mail_can_resolve();
  return jsonb_build_object(
    'id', v_o.id, 'kind', v_o.kind, 'category', v_o.category, 'status', v_o.status, 'from_address', v_o.from_address, 'from_name', v_o.from_name, 'reply_to', v_o.reply_to,
    'to_address', v_o.to_address, 'original_to', v_o.original_to, 'subject', v_o.subject, 'body_text', v_o.body_text, 'body_html', v_o.body_html, 'payload', v_o.payload,
    'attempts', v_o.attempts, 'next_attempt_at', v_o.next_attempt_at, 'last_error', v_o.last_error, 'claimed_at', v_o.claimed_at, 'sent_at', v_o.sent_at,
    'provider_message_id', v_o.provider_message_id, 'created_at', v_o.created_at, 'customer_id', v_o.customer_id,
    'customer_name', coalesce((select c.name from public.customer c where c.id = v_o.customer_id), v_o.payload->>'customer_name'),
    'location_id', v_o.location_id, 'location_name', (select w.name from public.ref_warehouse w where w.id = v_o.location_id), 'run_id', v_o.run_id,
    'can_close_sent', v_can and v_o.status = 'unknown', 'can_retry', v_can and v_o.status = 'unknown', 'can_cancel', v_can and v_o.status in ('queued', 'unknown'),
    'lines', coalesce((select jsonb_agg(jsonb_build_object(
        'line_id', b.so_line_id, 'so_number', pl->>'so_number', 'line_no', (pl->>'line_no')::int, 'sku', pl->>'sku', 'product_name', pl->>'product_name',
        'qty_open', b.qty_open, 'can_fill_units', b.can_fill_units, 'available_units', b.available_units, 'basis', b.basis, 'released_at', b.released_at,
        'notice_state', (select n.notified_state from public.so_backorder_notice_state(array[b.so_line_id]) n))
      order by pl->>'so_number', (pl->>'line_no')::int)
      from public.mail_backorder_line b
      left join lateral (select l from jsonb_array_elements(coalesce(v_o.payload->'lines', '[]'::jsonb)) l where (l->>'line_id')::uuid = b.so_line_id limit 1) p(pl) on true
      where b.outbox_id = v_o.id), '[]'::jsonb),
    'events', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'action', e.action, 'from_status', e.from_status, 'to_status', e.to_status, 'attempts', e.attempts,
                                                            'staff_name', s.name, 'note', e.note) order by e.at, e.id)
      from public.mail_outbox_event e left join public.ims_staff s on s.id = e.staff_id where e.outbox_id = v_o.id), '[]'::jsonb));
end;
$$;
comment on function public.mail_outbox_detail(uuid) is 'mail-4a — 메일 한 통(sales 보기): 칸 전부 + body_text · body_html(⚠️ 화면은 sandbox iframe 으로만 보인다) · payload · lines(줄 표지 · 그때 값 · 지금 notice_state) · events(이력 — 누가 · 언제 · 무엇 · 메모) · can_close_sent · can_retry · can_cancel(판정 516)';
revoke all on function public.mail_outbox_detail(uuid) from public, anon;
grant execute on function public.mail_outbox_detail(uuid) to authenticated;

create function public.customer_backorder_mail(p_customer_id uuid) returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
declare
  v_on boolean;
begin
  if not public.ims_can_view('sales') then raise exception 'Customers needs the sales permission — nothing was read'; end if;
  select c.backorder_mail into v_on from public.customer c where c.id = p_customer_id;
  if not found then raise exception 'Customer % not found', p_customer_id; end if;
  return jsonb_build_object('customer_id', p_customer_id, 'backorder_mail', v_on,
    'can_edit', (public.ims_can_write('sales') or public.ims_can_write('master'))
                and coalesce(public.ims_role_rank((select s.role from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active)), 0) >= public.ims_role_rank('manager'));
end;
$$;
comment on function public.customer_backorder_mail(uuid) is 'mail-4a 판정 507 · 517 — 손님 화면의 「백오더 알림 받기」 상자: 지금 값 · can_edit(customer_update 의 문 ∧ manager 이상 — 판정 517 과 같은 판정) · 바꾸기는 customer_update(field backorder_mail)';
revoke all on function public.customer_backorder_mail(uuid) from public, anon;
grant execute on function public.customer_backorder_mail(uuid) to authenticated;

create function public.mail_settings() returns jsonb
  language plpgsql stable security definer
  set search_path = public, pg_temp
as $$
begin
  if not (public.ims_can_view('sales') or public.ims_can_view('master')) then raise exception 'Mail settings need the sales or master permission — nothing was read'; end if;
  return (select coalesce(jsonb_agg(jsonb_build_object(
      'key', k.key, 'value', c.value, 'note', c.note, 'updated_at', c.updated_at, 'updated_by_name', s.name,
      'edit_level', case when k.key in ('mail_enabled', 'mail_redirect_to') then 'admin' else 'master' end,
      'can_edit', case when k.key in ('mail_enabled', 'mail_redirect_to') then public.ims_is_admin() else public.ims_can_write('master') end)
    order by k.ord), '[]'::jsonb)
    from unnest(public.ims_mail_config_keys()) with ordinality k(key, ord)
    left join public.inv_config c on c.key = k.key
    left join public.ims_staff s on s.id = c.updated_by);
end;
$$;
comment on function public.mail_settings() is 'mail-4a — 메일 설정 키 일곱의 지금 값 · 메모 · 마지막으로 바꾼 사람 · edit_level(admin: mail_enabled · mail_redirect_to · 나머지 master) · can_edit(inv_config_guard 와 같은 판정 — ims_is_admin · ims_can_write(master)) · 바꾸기는 inv_config 직접(guard 가 지킨다) · sales 또는 master 보기';
revoke all on function public.mail_settings() from public, anon;
grant execute on function public.mail_settings() to authenticated;

-- ═══ ⑤ 실물 확인 — 어긋나면 전부 되돌린다 ═══
do $$
declare v_bad text := '';
begin
  if (select prosrc from pg_proc where oid = 'public.mail_outbox_resolve(uuid, text, text)'::regprocedure) !~ 'so_require_role\(''manager''' then v_bad := v_bad || ' resolve-role'; end if;
  if (select prosrc from pg_proc where oid = 'public.mail_outbox_resolve(uuid, text, text)'::regprocedure) ~ 'ims_require_admin' then v_bad := v_bad || ' resolve-admin-left'; end if;
  if (select prosrc from pg_proc where oid = 'public.customer_update(jsonb, boolean, text[])'::regprocedure) !~ 'manager_needed' then v_bad := v_bad || ' customer_update'; end if;
  if (select prosrc from pg_proc where oid = 'public.mail_backorder_tick(timestamptz)'::regprocedure) !~ 'mail_run_error' then v_bad := v_bad || ' tick'; end if;
  if to_regclass('public.mail_run_error') is null or not (select relrowsecurity from pg_class where oid = 'public.mail_run_error'::regclass)
     or exists (select 1 from information_schema.role_table_grants where table_schema = 'public' and table_name = 'mail_run_error' and grantee in ('anon', 'authenticated')) then v_bad := v_bad || ' error-table'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('mail_runs_list', 'mail_outbox_list', 'mail_outbox_detail', 'customer_backorder_mail', 'mail_settings', 'mail_can_resolve')
        and prosecdef and has_function_privilege('authenticated', oid, 'execute') and not has_function_privilege('anon', oid, 'execute')) <> 6 then v_bad := v_bad || ' windows'; end if;
  if v_bad <> '' then
    raise exception using errcode = 'IM518', message = format('STOP - mail-4a did not land as designed:%s - nothing was changed', v_bad);
  end if;
end $$;
