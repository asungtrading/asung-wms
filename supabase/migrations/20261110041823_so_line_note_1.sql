-- supabase/migrations/20261110041823_so_line_note_1.sql — so-line-note-1: SO 손님용 줄 메모(따로 표 so_line_note) — 표 · 창구 · 나누기/합치기/Unconfirm 따라가기 · 붙여 넣기 · 문서 데이터 (2026-11-10 · 지시서 ~/asung/prompts/so-line-note-1.md · 이견 19 · 답 11-10)
-- 요청(동료 11-09 · Caleb): 「SO 오더 Line Item 에 Note」 — 손님에게 보여 주는 글 · Shopify 에서 내려온 오더의 줄에도 · 수정 · 삭제까지
-- 판정 1151 「나」: 손님용 줄 메모는 따로 작은 표(so_line_note) — so_line 을 건드리지 않아 so_line.updated_at 이 안 바뀐다 ⇒ 판정 434(Shopify 취소 → 자동 취소) · so_unconfirm 의 「손댐」 판단이 메모 때문에 바뀌지 않는다
--   사내 칸 so_line.comments 는 그대로 사내용(무상 other 의 까닭 · CHECK so_line_free_other_ck) — 이 차수부터 손님 문서에 안 찍힌다(지금 채워진 줄 0 / 7,420)
-- 새 것: 표 so_line_note(줄마다 하나 · 500 자 · 한 줄 꼴) · so_line_note_clean(굳히기) · so_line_note_join(「 / 」 잇기) · so_line_note_put(안쪽 한 곳 · 직원 실행 권한 없음) · 창구 so_line_note_set(p_line_id, p_note)
-- 재발행 여덟(몸 = DB prosrc 원본 2026-11-10 + 더한 줄 · 시그니처 · definer/invoker · volatility · search_path · acl 그대로 · create or replace · drop 없음):
--   so_split(일부만 간 줄 → 형제 새 줄에 복사) · so_merge(이은 메모 · 계획 note · 경고 line_note_too_long · 넘으면 거부) · so_unconfirm(형제 줄 메모를 원래 줄로) · so_lines_paste(줄 열쇠 note)
--   doc_data_so · doc_data_invoice · so_invoice_preview(줄 comment 원천 sl.comments → so_line_note.note · 열쇠 이름 comment 그대로) · so_detail(줄 열쇠 customer_note)
-- 무접촉: so_line · so 표 · so_line_add · so_line_update · so_combo_children_insert(이미 comments null · 지시서 정정 1) · doc_data_invoice_fmt · doc_field_catalog · doc_data_credit · 판(doc_template) · doc_setting · QBO · WMS · Shopify EF
-- ⚠️ 순서: 함수를 먼저 · 표는 끝에 — so_line 을 가리키는 FK 가 so_line 에 SHARE ROW EXCLUSIVE 를 잡는다(줄 쓰기가 기다린다) · 잡는 시간을 줄이려고 표를 맨 뒤에 둔다(plpgsql 몸은 늦게 묶인다)
-- 검증 supabase/tests/so_line_note_1_check.sql(begin → rollback · 가짜 행만) · 적용은 Caleb: psql -v ON_ERROR_STOP=1 -1 -c "set local lock_timeout = '5s'" -f <이 파일> && supabase migration repair --status applied … · supabase db push 금지
-- ⚠️ jsonb_build_object 안에 「--」 줄 주석을 새로 두지 않았다(so-detail-keys-1) — 더한 주석은 문장 끝 · 제 줄에만
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

-- ═══ 앞 검사 — 재발행 원본이 2026-11-10 에 읽은 DB prosrc 그대로인가(다른 창이 그 사이 고쳤으면 멈춘다) ═══
do $$
declare v_bad text := '';
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_split(uuid, text, jsonb, text, uuid)'::regprocedure) <> 'a8214b121c70c054943b318bec00c847' then v_bad := v_bad || ' so_split'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_merge(uuid[], boolean)'::regprocedure) <> 'fbbd2a426bb55f8a871ba7bdd5a8aa10' then v_bad := v_bad || ' so_merge'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_unconfirm(uuid)'::regprocedure) <> 'b1ac77b242fdc763fc349641f249bcff' then v_bad := v_bad || ' so_unconfirm'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_lines_paste(uuid, jsonb, boolean)'::regprocedure) <> 'ed9f56386f3eab17b0a05ecf2b6ab93a' then v_bad := v_bad || ' so_lines_paste'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) <> 'fe40d90b4930b9e0dbde0666074fb90d' then v_bad := v_bad || ' doc_data_so'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) <> '2fc7e887f8dd4ea2a842b8a5a710c4d9' then v_bad := v_bad || ' doc_data_invoice'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure) <> 'fe4974b74b20337919ff2ddc11c4f18e' then v_bad := v_bad || ' so_invoice_preview'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_detail(uuid)'::regprocedure) <> 'e56a3ce9c77617e72aaccd428d2285f3' then v_bad := v_bad || ' so_detail'; end if;
  if to_regclass('public.so_line_note') is not null then v_bad := v_bad || ' so_line_note_exists'; end if;
  if v_bad <> '' then raise exception 'so-line-note-1 pre-check failed (these functions changed since the migration was written — rebuild it from the current prosrc):%', v_bad; end if;
end $$;

-- ═══ ① 굳히기 · 잇기(표를 안 읽는다) ═══
create or replace function public.so_line_note_clean(p_note text)
 returns text
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select nullif(btrim(regexp_replace(coalesce(p_note, ''), '\s+', ' ', 'g')), '');
$function$;
revoke all on function public.so_line_note_clean(text) from public, anon, authenticated;
comment on function public.so_line_note_clean(text) is 'so-line-note-1 (2026-11-10 · 판정 1151) — 손님용 줄 메모를 한 줄로 굳힌다: 줄바꿈 · 탭 · 연속 공백 → 공백 하나 · 앞뒤 공백 뗌 · 빈 글 → null(판의 .cm 은 줄바꿈을 접는다 — 보이는 것 = 저장된 것) · 길이는 재지 않는다(so_line_note_put)';

create or replace function public.so_line_note_join(p_notes text[])
 returns text
 language sql
 immutable
 set search_path to 'public', 'pg_temp'
as $function$
  select string_agg(x.n, ' / ' order by x.first_ord)
  from (select t.n, min(t.ord) as first_ord from unnest(p_notes) with ordinality t(n, ord) where t.n is not null group by t.n) x;
$function$;
revoke all on function public.so_line_note_join(text[]) from public, anon, authenticated;
comment on function public.so_line_note_join(text[]) is 'so-line-note-1 (2026-11-10 · 이견 7) — 손님용 줄 메모 여럿을 하나로: null 을 빼고 · 같은 글은 한 번 · 처음 나온 순서대로 「 / 」 로 잇는다 · 하나도 없으면 null · 길이는 재지 않는다(부르는 곳 so_merge · so_unconfirm)';

-- ═══ ② 안쪽 한 곳 — so_line_note_put(직원이 직접 못 부른다 · 창구 · 붙여 넣기 · 합치기 · Unconfirm 이 부른다) ═══
create or replace function public.so_line_note_put(p_line_id uuid, p_note text, p_staff uuid)
 returns text
 language plpgsql
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_note text := public.so_line_note_clean(p_note);
  v_old  text;
  v_n    int;
begin
  if p_line_id is null then raise exception 'Order line not found — nothing was saved'; end if;
  if char_length(v_note) > 500 then
    raise exception 'The note to the customer would be % characters — the limit is 500 — shorten it first — nothing was saved', char_length(v_note);
  end if;
  select sn.note into v_old from public.so_line_note sn where sn.so_line_id = p_line_id;
  if v_note is not distinct from v_old then return 'unchanged'; end if;
  if v_note is null then
    delete from public.so_line_note sn where sn.so_line_id = p_line_id;
    return 'cleared';
  end if;
  update public.so_line_note sn set note = v_note, updated_by = p_staff where sn.so_line_id = p_line_id;
  get diagnostics v_n = row_count;
  if v_n = 0 then
    insert into public.so_line_note (so_line_id, note, created_by, updated_by) values (p_line_id, v_note, p_staff, p_staff);
  end if;
  return 'saved';
end;
$function$;
revoke all on function public.so_line_note_put(uuid, text, uuid) from public, anon, authenticated;
comment on function public.so_line_note_put(uuid, text, uuid) is 'so-line-note-1 (2026-11-10 · 판정 1151 · 이견 13) — 손님용 줄 메모 쓰기의 한 곳: 굳히기(so_line_note_clean) · 500 자 넘으면 거부(자르지 않는다) · 빈 글 = 행 삭제 · 같은 글이면 안 건드린다 · 반환 saved | cleared | unchanged · so_line · so 는 건드리지 않는다 · 권한 · 상태 문은 부르는 창구가 본다(직원 실행 권한 없음)';

-- ═══ ③ 창구 — so_line_note_set ═══
create or replace function public.so_line_note_set(p_line_id uuid, p_note text)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_staff  uuid;
  v_line   public.so_line%rowtype;
  v_so     public.so%rowtype;
  v_action text;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();

  select * into v_line from public.so_line sl where sl.id = p_line_id;
  if not found then
    raise exception 'Order line not found — nothing was saved';
  end if;
  select * into v_so from public.so o where o.id = v_line.so_id for share;                                     -- 합치기 · 취소와 겹치면 기다렸다가 닫힌 상태를 본다(행 값은 안 바꾼다)
  if v_so.status = 'cancelled' then
    raise exception 'Order % is % — a note to the customer cannot be changed on it — nothing was saved', v_so.so_number, case when v_so.closed_reason = 'merged' then 'merged into another order' else 'cancelled' end;
  end if;
  if v_line.combo_line_id is not null then
    raise exception 'Line % is a component of combo % (line %) — write the note on the combo line instead — nothing was saved', v_line.line_no,
      (select c.sku from public.so_line c where c.id = v_line.combo_line_id), (select c.line_no from public.so_line c where c.id = v_line.combo_line_id);
  end if;

  v_action := public.so_line_note_put(p_line_id, p_note, v_staff);
  return jsonb_build_object('so_number', v_so.so_number, 'line_no', v_line.line_no, 'line_id', v_line.id,
                            'customer_note', (select sn.note from public.so_line_note sn where sn.so_line_id = p_line_id), 'action', v_action);
end;
$function$;
revoke all on function public.so_line_note_set(uuid, text) from public, anon;
grant execute on function public.so_line_note_set(uuid, text) to authenticated;
comment on function public.so_line_note_set(uuid, text) is 'so-line-note-1 (2026-11-10 · 판정 1151) — 손님용 줄 메모 쓰기 · 고치기 · 지우기(빈 글 = 지움) · sales 쓰기 · draft ~ fulfilled 모두(인보이스 뒤 · 웹 오더 포함) · cancelled(합쳐져 닫힌 오더 포함) · 콤보 구성품 줄은 거부 · so_line · so 의 updated_at 은 안 바뀐다(판정 434 · Unconfirm 판단 보호) · 한 줄 꼴 500 자 · 반환 {so_number, line_no, line_id, customer_note, action saved | cleared | unchanged} · 문서의 줄 comment 가 이 글이다(인보이스 뒤 고치면 다시 찍을 때 바뀐다 · 보관 PDF 는 발행 때 글)';

-- ═══ 재발행 1/8 — so_split(DB prosrc 원본 md5 a8214b12 + 더한 줄) ═══
CREATE OR REPLACE FUNCTION public.so_split(p_so_id uuid, p_reason text, p_moves jsonb, p_target_status text, p_staff uuid)
 RETURNS so
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_so     public.so%rowtype;
  v_new    public.so%rowtype;
  v_base   text;
  v_max    text;
  v_num    text;
  v_id     uuid := gen_random_uuid();
  m        record;
  l        public.so_line%rowtype;
  v_next   int := 0;
  v_n      int;
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if p_reason not in ('stock_short','warehouse','preorder','manual','pick_short') then                       -- ③a′ 2026-09-24: pick_short(출하 차이 · so_ship) — CHECK so_split_reason_ck 와 같은 다섯
    raise exception 'split_reason % is not one of stock_short, warehouse, preorder, manual, pick_short — nothing was saved', p_reason;
  end if;
  if p_target_status not in ('draft','confirmed') then
    raise exception 'A split order can only be born draft or confirmed — nothing was saved';
  end if;
  if coalesce(jsonb_array_length(p_moves), 0) = 0 then
    raise exception 'Nothing to split off — nothing was saved';
  end if;

  -- 번호 — base(접미어를 뗀 것)로 잠그고 그 base 의 접미어 최댓값 다음 글자 하나(5-d · PO 20260924001820:278~370 과 같은 자리 · cancelled·merged 도 센다 — 글자는 다시 쓰지 않는다)
  v_base := regexp_replace(v_so.so_number, '[a-z]+$', '');
  perform pg_advisory_xact_lock(hashtext('so:' || v_base));
  select max(substring(s.so_number from length(v_base) + 1)) into v_max
  from public.so s where s.so_number ~ ('^' || v_base || '[a-z]$');
  if v_max is null then
    v_num := v_base || 'a';
  elsif v_max >= 'x' then
    raise exception 'Order % has been split too many times (last suffix %) — split it by hand — nothing was saved', v_so.so_number, v_max;
  else
    v_num := v_base || chr(ascii(v_max) + 1);
  end if;

  -- 머리 통째 복사(칸이 늘어도 따라온다) — draft 로 태어난다(문지기 · 이견 4) · 닫힘·창고·출하·되돌리기 흔적은 비운다 · 확정 흔적은 target 이 confirmed 일 때 아래 update 에서 물려받는다
  update public.so set order_discount_locked_at = coalesce(order_discount_locked_at, now()) where id = p_so_id;   -- dsc-3a 판정 312: 모체부터 잠근다(아래 줄 옮기기가 so_line 트리거를 깨운다)
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_so) || jsonb_build_object(
      'id', v_id, 'so_number', v_num, 'status', 'draft', 'order_discount_locked_at', coalesce(v_so.order_discount_locked_at, now()),
      'split_from_id', v_so.id, 'split_reason', p_reason,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null,
      'created_at', now(), 'created_by', p_staff, 'updated_at', now(), 'updated_by', p_staff));

  -- 줄 옮기기(모체 line_no 순 · 형제 line_no 1부터)
  for m in
    select (e->>'line_id')::uuid as line_id, (e->>'qty')::numeric as qty
    from jsonb_array_elements(p_moves) e
    join public.so_line x on x.id = (e->>'line_id')::uuid
    order by x.line_no
  loop
    select * into l from public.so_line where id = m.line_id and so_id = p_so_id;
    if not found then raise exception 'Line % is not on order % — nothing was saved', m.line_id, v_so.so_number; end if;
    if m.qty is null or m.qty <= 0 then raise exception 'Split quantity for line % must be positive — nothing was saved', l.line_no; end if;
    v_next := v_next + 1;
    if m.qty >= l.qty_ordered then
      update public.so_line set so_id = v_id, line_no = v_next, updated_by = p_staff where id = l.id;                       -- 통째 — 행이 간다(id 그대로)
    else
      update public.so_line set qty_ordered = qty_ordered - m.qty, updated_by = p_staff where id = l.id;                    -- 일부 — 원래 줄을 줄이고
      insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, qty_shipped,
                                  list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                  surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, split_from_line_id, updated_by, combo_line_id, combo_qty, price_set_by, price_set_at)
      values (v_id, v_next, l.product_id, l.sku, l.product_name, l.unit, l.pack_factor, m.qty, 0,
              l.list_price, l.discount_pct, l.unit_price, l.price_override, l.discount_source, l.deal_line_id, l.free_reason,
              l.surcharge_pct, l.surcharge_amount, l.surcharge_label, l.tax_rule, l.comments, l.id, p_staff, l.combo_line_id, l.combo_qty, l.price_set_by, l.price_set_at);   -- 형제에 새 줄 · 계보 · asm-2a: 콤보 매듭 두 칸도 · ln-1: 누가 정했나 두 칸도
      insert into public.so_line_note (so_line_id, note, created_by, updated_by)                                            -- so-line-note-1 판정 1151: 일부만 간 줄의 손님 메모는 형제의 새 줄에도(통째로 간 줄은 id 그대로라 메모가 따라간다)
      select nl.id, sn.note, p_staff, p_staff from public.so_line_note sn join public.so_line nl on nl.so_id = v_id and nl.line_no = v_next where sn.so_line_id = l.id;
    end if;
  end loop;
  -- asm-2a(판정 244 · 묶음 4): 일부만 간 콤보의 구성품 줄은 형제에 새로 선 콤보 줄에 다시 매단다(통째로 간 줄은 id 그대로라 매듭도 그대로) · 매듭 검사는 deferred 트리거라 문장 끝에 본다
  update public.so_line c set combo_line_id = n.id
    from public.so_line n
   where c.so_id = v_id and c.combo_line_id is not null and n.so_id = v_id and n.combo_line_id is null and n.split_from_line_id = c.combo_line_id;

  if p_target_status = 'confirmed' then
    update public.so set status = 'confirmed', confirmed_at = v_so.confirmed_at, confirmed_by = v_so.confirmed_by, updated_by = p_staff
    where id = v_id and status = 'draft';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not saved — nothing was saved', v_num; end if;
  end if;

  select * into v_new from public.so where id = v_id;
  return v_new;
end;
$function$;

-- ═══ 재발행 2/8 — so_merge(DB prosrc 원본 md5 fbbd2a42 + 더한 줄) ═══
CREATE OR REPLACE FUNCTION public.so_merge(p_so_ids uuid[], p_commit boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_head_fields constant text[] := array['ship_to_company','ship_to_contact','ship_to_phone','ship_to_line1','ship_to_line2','ship_to_city','ship_to_state_province','ship_to_postal_code','ship_to_country',
                                         'bill_to_customer_id','bill_to_name','bill_to_line1','bill_to_line2','bill_to_city','bill_to_state_province','bill_to_postal_code','bill_to_country',
                                         'payment_term_id','payment_term_name','price_tier','price_tier_id','tax_rule','tax_rule_id','tax_rule_manual','discount_pct',
                                         'order_discount_pct','order_discount_source','order_discount_deal_id','required_by','ref','comments','intake',
                                         'carrier','tracking_number','shipping_notes','ar_account_code','sale_account_code'];
  v_staff   uuid;
  v_ids     uuid[];
  v_n       int;
  v_today   date := public.ims_today();
  v_old     public.so%rowtype;                       -- 가장 오래된 원본 = 머리(⬜2)
  v_head    public.so%rowtype;                       -- 미리 보기용 가상 머리(order_date = 오늘)
  v_new     public.so%rowtype;
  v_cust    public.customer%rowtype;
  v_numbers text;
  v_any_confirmed boolean;
  v_diffs   jsonb; v_plan jsonb; v_calc_in jsonb; v_hint jsonb; v_pay jsonb; v_sib jsonb; v_sup jsonb; v_charges jsonb;
  v_warn    text[] := '{}';
  v_note    text;
  v_id      uuid;
  v_line_id uuid;
  v_cnt     int;
  v_bo      int := 0; v_reopened int := 0; v_released int := 0; v_moved int := 0; v_lines_n int := 0;
  v_combos  jsonb := '[]'::jsonb;  v_comp_n int := 0;                 -- asm-2b2(묶음 2 · 3): 콤보 줄끼리 합친다(열쇠 + 구성품 모양) · 합친 콤보 줄 아래 구성품을 다시 매단다(합친 콤보 수 × combo_qty · 저장된 combo_qty 로 · 정의가 바뀐 콤보는 열쇠가 갈라 따로 둔다)
  r record;
  e jsonb;
  v_cps jsonb := '[]'::jsonb;  v_best_cp uuid;  v_best_pct numeric := -1;  v_cp_pct numeric;   -- dsc-3b 판정 324 — 원본 쿠폰 가운데 큰 쪽
  od record;
  v_bo_msg  text;                                    -- bo-1d 판정 484: 열린 백오더 오더 거부 문장
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄 — sales 묶음
  v_staff := public.so_current_staff();

  -- ── 대상 검사 ──
  select array_agg(distinct x) into v_ids from unnest(p_so_ids) x where x is not null;
  if coalesce(array_length(p_so_ids, 1), 0) <> coalesce(array_length(v_ids, 1), 0) then raise exception 'The same order is listed twice — nothing was saved'; end if;
  if coalesce(array_length(v_ids, 1), 0) < 2 then raise exception 'A merge needs at least two orders — nothing was saved'; end if;
  perform 1 from public.so s where s.id = any(v_ids) order by s.id for update;
  get diagnostics v_n = row_count;
  if v_n <> array_length(v_ids, 1) then raise exception 'Order not found — nothing was saved'; end if;
  for r in select s.* from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number loop
    if r.status not in ('draft', 'confirmed') then
      raise exception 'Order % is % — only draft or confirmed orders still in IMS can be merged — nothing was saved', r.so_number,
        r.status || case when r.status = 'cancelled' and r.closed_reason = 'merged' then ' (already merged into ' || coalesce((select m.so_number from public.so m where m.id = r.merged_into_id), '?') || ')'
                         when r.status in ('at_wms', 'picking', 'packed') then ' (it is with the warehouse — merge is only possible before release)'
                         else '' end;
    end if;
    if r.channel <> 'warehouse' then raise exception 'Order % is a % order — only warehouse orders can be merged — nothing was saved', r.so_number, r.channel; end if;
  end loop;
  if (select count(distinct s.customer_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders belong to different customers — nothing was saved'; end if;
  if (select count(distinct coalesce(s.location_id::text, '(none)')) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are for different warehouses — change the warehouse first — nothing was saved'; end if;
  if (select count(distinct s.currency_id) from public.so s where s.id = any(v_ids)) > 1 then raise exception 'These orders are in different currencies — nothing was saved'; end if;
  -- bo-1d 판정 484: 열린 백오더 예약이 있는 오더는 합치지 않는다(합치면 같은 제품 줄 수량이 더해져 확정 때의 이어받기를 건너뛴다 · 백오더의 길은 진행 · 이어받기 · 만료 · 취소) · 콤보 줄이면 구성품 줄의 예약(was_backorder 와 같은 모양) · 미리 보기도 같은 거부 · 프리오더 · 보류 · 할당은 막지 않는다
  select format('Order %s has open backorder lines (%s) — a backorder is not merged: proceed it when stock arrives, or confirm the new order so it takes the backorder over — nothing was saved',
                b.so_number, b.skus || case when b.n > 5 then ' and ' || (b.n - 5)::text || ' more' else '' end)
    into v_bo_msg
  from (select s.so_number, s.order_date, count(*) as n, string_agg(d.sku, ', ' order by d.line_no) filter (where d.rn <= 5) as skus
        from public.so s
        join (select l.so_id, l.line_no, l.sku, row_number() over (partition by l.so_id order by l.line_no) as rn
              from public.so_line l
              where l.combo_line_id is null
                and exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id
                            where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'backorder')) d on d.so_id = s.id
        where s.id = any(v_ids)
        group by s.id, s.so_number, s.order_date
        order by s.order_date, s.so_number limit 1) b;
  if v_bo_msg is not null then raise exception '%', v_bo_msg; end if;
  select c.* into v_cust from public.customer c where c.id = (select s.customer_id from public.so s where s.id = v_ids[1]);
  if not v_cust.is_active then raise exception 'Customer % is inactive — nothing was saved', v_cust.name; end if;
  v_any_confirmed := exists (select 1 from public.so s where s.id = any(v_ids) and s.status = 'confirmed');
  if v_any_confirmed then perform public.so_require_role('manager', 'saved'); end if;   -- 판정 5 · R5: 확정 오더의 재고를 푸는 순간 선을 넘는다

  select s.* into v_old from public.so s where s.id = any(v_ids) order by s.order_date, s.so_number limit 1;
  select string_agg(s.so_number, ', ' order by s.order_date, s.so_number) into v_numbers from public.so s where s.id = any(v_ids);

  -- ── 머리 차이(판정 2·7 · 막지 않는다) ──
  select coalesce(jsonb_agg(jsonb_build_object('field', d.f, 'values', d.vals) order by d.f), '[]'::jsonb) into v_diffs
  from (select f, jsonb_agg(jsonb_build_object('so_number', s.so_number, 'value', to_jsonb(s)->f) order by s.order_date, s.so_number) as vals
        from public.so s cross join unnest(c_head_fields) f
        where s.id = any(v_ids)
        group by f having count(distinct coalesce(to_jsonb(s)->f, 'null'::jsonb)) > 1) d;

  -- ── 줄 계획(판정 4 · 고침 ①: 열쇠 = 제품 · 단가 · 정가 · 할인 % · 무상 사유 · override · 부가 셋 — tax_rule 은 열쇠 밖 · 전부 합친 오더 규칙) ──
  with src as (
    select l.*, s.so_number, dense_rank() over (order by s.order_date, s.so_number) as ord,
           (select sn.note from public.so_line_note sn where sn.so_line_id = l.id) as note,
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'preorder')  as was_preorder,    -- asm-2b2: 콤보 줄의 예약은 구성품에
           exists (select 1 from public.so_reserve rs join public.so_line cp on cp.id = rs.so_line_id where (cp.id = l.id or cp.combo_line_id = l.id) and rs.released_at is null and rs.kind = 'backorder') as was_backorder,
           (l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, v_today)) as deal_ended,
           (select string_agg(cp.sku || ':' || trim_scale(cp.combo_qty)::text, ',' order by cp.sku) from public.so_line cp where cp.combo_line_id = l.id) as combo_sig   -- asm-2b2: 콤보 줄의 구성품 모양(열쇠에 든다 · 보통 줄은 null)
    from public.so_line l join public.so s on s.id = l.so_id
    where s.id = any(v_ids) and l.combo_line_id is null                                                                                  -- asm-2b2: 구성품 줄은 계획에 들지 않는다(콤보 줄을 따라 다시 선다)
  ), grp as (
    select product_id, unit_price, list_price, discount_pct, free_reason, price_override, surcharge_pct, surcharge_amount, surcharge_label, combo_sig, discount_source, deal_line_id,   -- mrg-1 판정 548: 출처 · 딜도 열쇠(다르면 따로 줄)
           min(ord * 100000 + line_no) as first_pos, sum(qty_ordered) as qty, count(*) as n, (array_agg(id order by ord, line_no))[1] as first_line_id,
           (array_agg(sku order by ord, line_no))[1] as sku, (array_agg(product_name order by ord, line_no))[1] as product_name,
           (array_agg(unit order by ord, line_no))[1] as unit, (array_agg(pack_factor order by ord, line_no))[1] as pack_factor,
           (array_agg(comments order by ord, line_no) filter (where comments is not null))[1] as comments,
           public.so_line_note_join(array_agg(note order by ord, line_no)) as note,
           (array_agg(price_set_by order by ord, line_no) filter (where price_set_by is not null))[1] as price_set_by,   -- ln-1 판정 546: 첫 원본의 setter(값이 있는 것 가운데 첫째)
           (array_agg(price_set_at order by ord, line_no) filter (where price_set_by is not null))[1] as price_set_at,
           bool_or(was_preorder) as was_preorder, bool_or(was_backorder) as was_backorder, bool_or(deal_ended) as deal_ended,
           jsonb_agg(jsonb_build_object('so_number', so_number, 'line_no', line_no, 'line_id', id, 'qty', qty_ordered, 'discount_source', discount_source, 'deal_line_id', deal_line_id,
                                        'was_preorder', was_preorder, 'was_backorder', was_backorder) order by ord, line_no) as sources
    from src
    group by 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
  ), numbered as (
    select g.*, row_number() over (order by g.first_pos) as line_no,
           count(*) over (partition by g.product_id) as n_same_product,
           first_value(g.unit_price)     over (partition by g.product_id order by g.first_pos) as p_unit_price,
           first_value(g.list_price)     over (partition by g.product_id order by g.first_pos) as p_list_price,
           first_value(g.discount_pct)   over (partition by g.product_id order by g.first_pos) as p_discount_pct,
           first_value(g.free_reason)    over (partition by g.product_id order by g.first_pos) as p_free_reason,
           first_value(g.price_override) over (partition by g.product_id order by g.first_pos) as p_override,
           first_value(g.surcharge_label) over (partition by g.product_id order by g.first_pos) as p_surcharge_label,
           first_value(g.combo_sig)      over (partition by g.product_id order by g.first_pos) as p_combo_sig,
           first_value(g.discount_source) over (partition by g.product_id order by g.first_pos) as p_discount_source,   -- mrg-1
           first_value(g.deal_line_id)   over (partition by g.product_id order by g.first_pos) as p_deal_line_id
    from grp g
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'line_no', x.line_no, 'product_id', x.product_id, 'sku', x.sku, 'product_name', x.product_name, 'unit', x.unit, 'pack_factor', x.pack_factor,
           'qty', x.qty, 'list_price', x.list_price, 'discount_pct', x.discount_pct, 'unit_price', x.unit_price, 'price_override', x.price_override, 'free_reason', x.free_reason,
           'discount_source', x.discount_source, 'deal_line_id', x.deal_line_id,                                                                                    -- mrg-1 판정 548: 원본의 「왜 이 할인」 그대로(customer · deal · set · shopify · manual · 덮어쓴 줄은 null) — 옛 식은 할인 % 가 있는 시스템 줄을 manual 로 바꿨다
           'surcharge_pct', x.surcharge_pct, 'surcharge_amount', x.surcharge_amount, 'surcharge_label', x.surcharge_label, 'comments', x.comments, 'note', x.note,
           'price_set_by', x.price_set_by, 'price_set_at', x.price_set_at,                                                                                      -- ln-1
           'source_lines', x.n, 'sources', x.sources, 'was_preorder', x.was_preorder, 'was_backorder', x.was_backorder, 'deal_ended', x.deal_ended,
           'is_combo', x.combo_sig is not null, 'combo_sig', x.combo_sig, 'first_line_id', x.first_line_id,                                              -- asm-2b2
           'kept_apart', (x.n_same_product > 1),
           'differs_in', case when x.n_same_product > 1 then
              (select coalesce(jsonb_agg(k), '[]'::jsonb) from unnest(array[
                 case when x.unit_price is distinct from x.p_unit_price then 'unit_price' end,
                 case when x.list_price is distinct from x.p_list_price then 'list_price' end,
                 case when x.discount_pct is distinct from x.p_discount_pct then 'discount_pct' end,
                 case when x.free_reason is distinct from x.p_free_reason then 'free_reason' end,
                 case when x.price_override is distinct from x.p_override then 'price_override' end,
                 case when x.surcharge_label is distinct from x.p_surcharge_label then 'surcharge' end,
                 case when x.combo_sig is distinct from x.p_combo_sig then 'combo_definition' end,
                 case when x.discount_source is distinct from x.p_discount_source then 'discount_source' end,                                                   -- mrg-1
                 case when x.deal_line_id is distinct from x.p_deal_line_id then 'deal' end]) k where k is not null)
              else '[]'::jsonb end) order by x.line_no), '[]'::jsonb)
    into v_plan
  from numbered x;
  v_lines_n := coalesce(jsonb_array_length(v_plan), 0);

  -- ── 판정 4 보완 ①: 가상 머리(가장 오래된 원본 + 오늘) 로 다시 견적 ──
  v_head := v_old;
  v_head.order_date := v_today;
  select coalesce(jsonb_agg(jsonb_build_object('line_no', p->'line_no', 'product_id', p->'product_id', 'sku', p->'sku', 'qty', p->'qty', 'unit_price', p->'unit_price', 'discount_pct', p->'discount_pct',
                                               'discount_source', p->'discount_source', 'free_reason', p->'free_reason', 'price_override', p->'price_override')), '[]'::jsonb)
    into v_calc_in from jsonb_array_elements(v_plan) p;
  v_hint := public.so_merge_requote_calc(v_head, v_calc_in);

  -- ── 선결제 대상(옮긴다 · 조사 ③ unique (payment_id, so_id)) ──
  select coalesce(jsonb_agg(jsonb_build_object('payment_id', x.id, 'amount', x.amount, 'method', x.method, 'paid_on', x.paid_on, 'targets', x.targets) order by x.paid_on, x.id), '[]'::jsonb) into v_pay
  from (select p.id, p.amount, p.method, p.paid_on, jsonb_agg(s.so_number order by s.so_number) as targets
        from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active' join public.so s on s.id = o.so_id
        where o.so_id = any(v_ids) group by p.id, p.amount, p.method, p.paid_on) x;

  -- ── 판정 1 로 이어받기에서 빠질 형제(원본의 split 자손 중 열린 백오더가 있는 confirmed 오더) ──
  with recursive d as (
    select s.id, 0 as depth, array[s.id] as path from public.so s where s.id = any(v_ids)
    union all
    select c.id, d.depth + 1, d.path || c.id from d join public.so c on c.split_from_id = d.id where d.depth < 50 and not (c.id = any(d.path))
  )
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'status', s.status, 'split_reason', s.split_reason,
           'open_backorder_lines', (select count(*) from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null)) order by s.so_number), '[]'::jsonb)
    into v_sib
  from d join public.so s on s.id = d.id
  where d.depth > 0 and not (s.id = any(v_ids)) and s.status = 'confirmed'
    and exists (select 1 from public.so_reserve rs join public.so_line l on l.id = rs.so_line_id where l.so_id = s.id and rs.kind = 'backorder' and rs.released_at is null);

  -- ── 원본이 확정 때 이어받은 남의 백오더 줄(⬜4 · 0-7: confirmed 이고 열린 예약이 없는 줄만 다시 연다 · 나머지는 닫힌 채 + 경고) ──
  select coalesce(jsonb_agg(jsonb_build_object('close_id', c.id, 'so_number', s.so_number, 'line_no', l.line_no, 'sku', l.sku, 'qty_open', c.qty_open, 'qty_taken', c.qty_taken, 'qty_unwanted', c.qty_unwanted,
           'taken_by', t.so_number, 'target_status', s.status,
           'reopenable', (s.status = 'confirmed' and not exists (select 1 from public.so_reserve rs where rs.so_line_id = l.id and rs.released_at is null))) order by s.so_number, l.line_no), '[]'::jsonb)
    into v_sup
  from public.so_backorder_close c join public.so_line l on l.id = c.so_line_id join public.so s on s.id = l.so_id join public.so t on t.id = c.taken_by_so_id
  where c.taken_by_so_id = any(v_ids) and c.reopened_at is null and c.end_kind = 'superseded';

  -- ── 운임(판정 8: 옮기지 않는다 · 다시 계산한다) ──
  select coalesce(jsonb_agg(jsonb_build_object('so_number', s.so_number, 'line_no', c.line_no, 'name', c.name, 'amount', c.amount) order by s.so_number, c.line_no), '[]'::jsonb) into v_charges
  from public.so_charge c join public.so s on s.id = c.so_id where c.so_id = any(v_ids);

  -- ── 경고(막지 않는다) ──
  if jsonb_array_length(v_diffs) > 0 then v_warn := array_append(v_warn, 'head_differs'); end if;
  if jsonb_array_length(v_charges) > 0 then v_warn := array_append(v_warn, 'charges_not_merged'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'was_preorder')::boolean) then v_warn := array_append(v_warn, 'preorder_lines_need_reflag'); end if;
  if exists (select 1 from jsonb_array_elements(v_plan) p where (p->>'deal_ended')::boolean) then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if exists (select 1 from jsonb_array_elements(v_sup) x where not (x->>'reopenable')::boolean) then v_warn := array_append(v_warn, 'superseded_not_reopenable'); end if;
  if v_old.order_date <> v_today and v_lines_n > 0 then v_warn := array_append(v_warn, 'reprice_suggested'); end if;   -- §13 판정 3: 주문일이 바뀌면 줄은 그대로 + 표시 + 경고
  if exists (select 1 from jsonb_array_elements(v_plan) p where char_length(p->>'note') > 500) then v_warn := array_append(v_warn, 'line_note_too_long'); end if;
  if jsonb_array_length(v_sib) > 0 then v_warn := array_append(v_warn, 'backorder_siblings_stay_open'); end if;      -- 판정 1 · 0-1 대가

  if not p_commit then
    return jsonb_build_object('committed', false, 'orders', to_jsonb(string_to_array(v_numbers, ', ')), 'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today,
                              'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'charges', v_charges,
                              'needs_manager', v_any_confirmed, 'warnings', to_jsonb(v_warn));
  end if;

  -- so-line-note-1 판정 1151(이견 7): 합친 줄의 손님 메모 = 원본 메모를 오더 순서대로 「 / 」 로 이은 것 · 500 자를 넘으면 자르지 않고 거부(쓰기 전)
  if exists (select 1 from jsonb_array_elements(v_plan) p where char_length(p->>'note') > 500) then
    raise exception 'The notes to the customer on % would be longer than 500 characters once joined — shorten them on the original orders first — nothing was saved',
      (select string_agg(p->>'sku', ', ' order by (p->>'line_no')::int) from jsonb_array_elements(v_plan) p where char_length(p->>'note') > 500);
  end if;

  -- ── 실행 ① 새 오더(머리 통째 복사 · 위 주석의 칸 표) ──
  v_id := gen_random_uuid();
  v_note := 'Merged from ' || v_numbers;
  insert into public.so
  select * from jsonb_populate_record(null::public.so,
    to_jsonb(v_old) || jsonb_build_object(
      'id', v_id, 'so_number', public.so_next_number(), 'status', 'draft', 'order_date', v_today, 'ref', null,
      'comments', case when v_old.comments is null then v_note else v_old.comments || E'\n' || v_note end,
      'split_from_id', null, 'split_reason', null,
      'merged_into_id', null, 'closed_reason', null, 'closed_note', null, 'closed_at', null, 'cancelled_by', null,
      'confirmed_at', null, 'confirmed_by', null, 'at_wms_at', null, 'at_wms_by', null, 'shipped_at', null, 'shipped_by', null, 'invoiced_at', null,
      'unconfirmed_at', null, 'unconfirmed_by', null, 'carrier', null, 'carrier_id', null, 'tracking_number', null,   -- ful-1c: carrier_id 도 비운다(합친 뒤 Ship & invoice 에서 고른다)
      'reprice_suggested_at', null, 'order_discount_locked_at', null,
      'created_at', now(), 'created_by', v_staff, 'updated_at', now(), 'updated_by', v_staff));
  select * into v_new from public.so where id = v_id;
  perform public.so_order_discount_apply(v_id, v_staff);                             -- 판정 7 · dsc-3a 판정 308 · 312: 새 머리는 잠기지 않는다 · manual 은 helper 가 그대로 · 줄이 들어오며 so_line 트리거가 금액 단계로 다시 고른다

  -- ── 실행 ② 줄(계획 그대로 · tax_rule = 합친 오더 규칙 · 짝 표) ──
  for e in select p from jsonb_array_elements(v_plan) p order by (p->>'line_no')::int loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by, price_set_by, price_set_at)
    values (v_id, (e->>'line_no')::int, (e->>'product_id')::uuid, e->>'sku', e->>'product_name', e->>'unit', (e->>'pack_factor')::numeric, (e->>'qty')::numeric,
            (e->>'list_price')::numeric, (e->>'discount_pct')::numeric, (e->>'unit_price')::numeric, (e->>'price_override')::boolean, e->>'discount_source', (e->>'deal_line_id')::uuid, e->>'free_reason',   -- mrg-1: 딜 연결도 그대로(짝 CHECK so_line_deal_line_pair_ck)
            (e->>'surcharge_pct')::numeric, (e->>'surcharge_amount')::numeric, e->>'surcharge_label', v_new.tax_rule, e->>'comments', v_staff, (e->>'price_set_by')::uuid, (e->>'price_set_at')::timestamptz)   -- ln-1
    returning id into v_line_id;
    if e->>'note' is not null then perform public.so_line_note_put(v_line_id, e->>'note', v_staff); end if;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select v_line_id, (x->>'line_id')::uuid, v_staff from jsonb_array_elements(e->'sources') x;
    if (e->>'is_combo')::boolean then v_combos := v_combos || jsonb_build_object('line_id', v_line_id, 'first_line_id', e->'first_line_id', 'qty', e->'qty', 'sources', e->'sources'); end if;
  end loop;
  -- asm-2b2(묶음 2): 합친 콤보 줄마다 구성품을 다시 매단다 — 첫 원본 콤보 줄의 구성품(저장된 combo_qty · 정의를 다시 읽지 않는다) · 수량 = 합친 콤보 수 × combo_qty · 값 0 · 줄 번호는 끝에(so_line_add 와 같은 자리) · 짝 표에 원본 구성품 줄도
  for e in select p from jsonb_array_elements(v_combos) p loop
    insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered, list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason,
                                surcharge_pct, surcharge_amount, surcharge_label, tax_rule, comments, updated_by, combo_line_id, combo_qty)
    select v_id, (select coalesce(max(n.line_no), 0) from public.so_line n where n.so_id = v_id) + row_number() over (order by cp.line_no), cp.product_id, cp.sku, cp.product_name, cp.unit, cp.pack_factor, (e->>'qty')::numeric * cp.combo_qty,
           null, null, 0, false, null, null, null, null, null, null, v_new.tax_rule, null, v_staff, (e->>'line_id')::uuid, cp.combo_qty
    from public.so_line cp where cp.combo_line_id = (e->>'first_line_id')::uuid;
    get diagnostics v_cnt = row_count;  v_comp_n := v_comp_n + v_cnt;
    insert into public.so_line_merge_source (line_id, from_line_id, created_by)
    select n.id, sc.id, v_staff
    from public.so_line n join jsonb_array_elements(e->'sources') sx on true join public.so_line sc on sc.combo_line_id = (sx->>'line_id')::uuid and sc.product_id = n.product_id
    where n.so_id = v_id and n.combo_line_id = (e->>'line_id')::uuid;
  end loop;
  if v_old.order_date <> v_today and v_lines_n > 0 then
    update public.so set reprice_suggested_at = now(), updated_by = v_staff where id = v_id;
  end if;
  -- dsc-3b 판정 324: 원본들의 쿠폰 가운데 helper 로 골라 본 % 가 큰 쪽만 새 머리에(같으면 오래된 원본 것) · 나머지는 뗀 채 남는다(원본은 merged 라 가족 판정에 안 걸린다)
  for r in select s.coupon_id, s.so_number, s.created_at from public.so s where s.id = any(v_ids) and s.coupon_id is not null order by s.created_at, s.so_number loop
    update public.so set coupon_id = r.coupon_id where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select case when s.order_discount_source = 'coupon' then s.order_discount_pct else -1 end into v_cp_pct from public.so s where s.id = v_id;
    v_cps := v_cps || jsonb_build_object('so_number', r.so_number, 'code', (select c.code from public.so_coupon c where c.id = r.coupon_id),
                                         'pct', (select public.so_coupon_pct(c, s) from public.so_coupon c, public.so s where c.id = r.coupon_id and s.id = v_id), 'won_pct', nullif(v_cp_pct, -1));
    if v_cp_pct > v_best_pct then v_best_pct := v_cp_pct; v_best_cp := r.coupon_id; end if;
  end loop;
  if v_cps <> '[]'::jsonb then
    update public.so set coupon_id = case when v_best_pct > -1 then v_best_cp else null end where id = v_id;
    perform public.so_order_discount_apply(v_id, v_staff, true);
    select coalesce(jsonb_agg(c || jsonb_build_object('kept', (select s.coupon_id from public.so s where s.id = v_id) = (select x.id from public.so_coupon x where x.code = c->>'code'))), '[]'::jsonb) into v_cps from jsonb_array_elements(v_cps) c;
  end if;

  -- ── 실행 ③ 원본의 열린 백오더 줄 → 장부 merged + 예약 closed(0-4) · asm-2b2: 수요 줄 단위(콤보 줄은 구성품 예약을 콤보 수로 · 장부는 콤보 줄에 · 구성품 예약 함께 닫힘) ──
  for r in
    select x.id as so_line_id, q.qty_open, q.ids as reserve_ids
    from public.so_line x
    cross join lateral (select min(floor(res.qty_allocated / coalesce(cp.combo_qty, 1))) as qty_open, array_agg(res.id) as ids
                        from public.so_reserve res join public.so_line cp on cp.id = res.so_line_id
                        where (cp.id = x.id or cp.combo_line_id = x.id) and res.released_at is null and res.kind = 'backorder') q
    where x.so_id = any(v_ids) and x.combo_line_id is null and q.qty_open is not null
  loop
    perform public.so_backorder_record(r.so_line_id, 'merged', r.qty_open, 0, 0, null, null, v_staff, 'Merged into ' || v_new.so_number);
    update public.so_reserve set released_at = now(), released_by = v_staff, released_reason = 'closed', updated_by = v_staff where id = any(r.reserve_ids);
    v_bo := v_bo + 1;
  end loop;

  -- ── 실행 ④ 원본이 이어받은 남의 줄 다시 열기(⬜4 · confirmed 이고 열린 예약 없는 줄만 · so_backorder_reopen 과 같은 모양) ──
  for r in select (x->>'close_id')::uuid as close_id, (x->>'reopenable')::boolean as ok from jsonb_array_elements(v_sup) x loop
    if r.ok then
      update public.so_backorder_close set reopened_at = now(), reopened_by = v_staff, updated_by = v_staff where id = r.close_id and reopened_at is null;
      insert into public.so_reserve (so_line_id, qty_allocated, kind, allocated_by)
      select c.so_line_id, c.qty_open, 'backorder', null from public.so_backorder_close c where c.id = r.close_id;
      v_reopened := v_reopened + 1;
    end if;
  end loop;

  -- ── 실행 ⑤ 원본의 남은 열린 예약(allocated · preorder · hold) 풀기 → released(트리거가 reason 을 넣는다 · ⬜5) ──
  update public.so_reserve res set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x where x.id = res.so_line_id and res.released_at is null and x.so_id = any(v_ids);
  get diagnostics v_released = row_count;

  -- ── 실행 ⑥ 원본 닫기(한 문장 · so_merge_reason_ck 양방향 · so_closed_at_ck) ──
  update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = v_id, closed_at = now(), closed_note = 'Merged into ' || v_new.so_number, cancelled_by = v_staff, updated_by = v_staff
  where id = any(v_ids) and status in ('draft', 'confirmed');
  get diagnostics v_cnt = row_count;
  if v_cnt <> array_length(v_ids, 1) then
    raise exception 'Not every order could be merged — one may have been changed by someone else just now — nothing was saved';
  end if;

  -- ── 실행 ⑦ 선결제 대상 옮기기(원본 행은 기록으로 · 합친 오더 행 하나) ──
  insert into public.so_payment_order (payment_id, so_id, created_by)
  select distinct o.payment_id, v_id, v_staff
  from public.so_payment_order o join public.so_payment p on p.id = o.payment_id and p.status = 'active'
  where o.so_id = any(v_ids)
  on conflict on constraint so_payment_order_uq do nothing;
  get diagnostics v_moved = row_count;

  return jsonb_build_object('committed', true, 'so_id', v_id, 'so_number', v_new.so_number, 'status', 'draft', 'orders', to_jsonb(string_to_array(v_numbers, ', ')),
                            'head_from', v_old.so_number, 'head_diffs', v_diffs, 'order_date', v_today, 'lines', v_plan, 'lines_count', v_lines_n, 'requote', v_hint,
                            'payments_moved', v_moved, 'payments_to_move', v_pay, 'backorder_siblings', v_sib, 'superseded', v_sup, 'superseded_reopened', v_reopened,
                            'backorder_lines_recorded', v_bo, 'reserves_released', v_released, 'charges', v_charges, 'component_lines', v_comp_n, 'coupons', v_cps, 'warnings', to_jsonb(v_warn));   -- asm-2b2: 다시 매단 구성품 줄 수
end;
$function$;

-- ═══ 재발행 3/8 — so_unconfirm(DB prosrc 원본 md5 b1ac77b2 + 더한 줄) ═══
CREATE OR REPLACE FUNCTION public.so_unconfirm(p_so_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff   uuid;
  v_so      public.so%rowtype;
  s         public.so%rowtype;
  l         public.so_line%rowtype;
  v_next    int;
  v_merged  text[] := '{}';
  v_moved   int := 0;  v_added int := 0;  v_released int := 0;
  v_reopen  jsonb;                                              -- ③b: 이 확정이 이어받아 닫은 남의 백오더 줄
  v_n       int;
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  perform public.so_require_role('manager', 'saved');          -- ⭐ 둘째 줄 — manager 이상(R9 · 판정 883 · 전에는 supervisor)
  v_staff := public.so_current_staff();

  select * into v_so from public.so where id = p_so_id for update;
  if not found then raise exception 'Order not found — nothing was saved'; end if;
  if not public.ims_can_warehouse(v_so.location_id) then                             -- ⭐ 셋째 — unconf-1 판정 883: 자기 창고 오더만(supervisor · admin · Location 빈 manager 는 늘 통과 · 오더를 읽은 뒤 · 상태 검사 앞)
    raise exception 'Order % is in % — you can unconfirm only orders of your locations (ask a supervisor) — nothing was saved', v_so.so_number, coalesce(v_so.location_name, '(no location)');
  end if;
  if v_so.status <> 'confirmed' then
    raise exception 'Order % is % — only a confirmed order still in IMS can be unconfirmed (if it went to the warehouse, roll it back in WMS first) — nothing was saved', v_so.so_number, v_so.status;
  end if;
  if v_so.split_from_id is not null and v_so.confirmed_at is not null
     and exists (select 1 from public.so m where m.id = v_so.split_from_id and m.confirmed_at = v_so.confirmed_at) then
    raise exception 'Order % was itself split off at confirmation — unconfirm the original order % instead — nothing was saved',
      v_so.so_number, (select m.so_number from public.so m where m.id = v_so.split_from_id);
  end if;

  perform pg_advisory_xact_lock(hashtext('so:' || regexp_replace(v_so.so_number, '[a-z]+$', '')));

  -- ⭐ 사슬로 판정한다 — 시각에만 기대지 않는다(2026-09-24 결함 고침: 한 트랜잭션에서 so_divide 로 난 형제의 created_at 이 confirmed_at 과 같았다)
  if exists (select 1 from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason = 'manual') then
    raise exception 'Order % has a hand-made split order (%) — unconfirm is not possible while it is open (cancel or merge it first) — nothing was saved',
      v_so.so_number, (select string_agg(x.so_number, ', ' order by x.so_number) from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason = 'manual');
  end if;

  -- 형제 검사(자기 행만 보는 것이 아니라 여기서 다른 행을 본다 — RPC 의 일 · 6-g′) · ⭐ 열린 자식만(cancelled = 앞선 되돌리기로 merged 된 것·취소된 것은 무시 · 2026-09-24 결함 고침)
  for s in select * from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason in ('stock_short','preorder') order by x.so_number loop
    if s.created_at is distinct from v_so.confirmed_at then
      raise exception 'Order % was split again after confirmation (%) — unconfirm only undoes the split made at confirmation — nothing was saved', v_so.so_number, s.so_number;
    end if;
    if s.status <> 'confirmed' then
      raise exception 'Split order % is % — it must still be confirmed and in IMS to merge it back — nothing was saved', s.so_number, s.status;
    end if;
    if exists (select 1 from public.so y where y.split_from_id = s.id) then
      raise exception 'Split order % has itself been split again (%) — unconfirm is not possible — nothing was saved',
        s.so_number, (select string_agg(y.so_number, ', ' order by y.so_number) from public.so y where y.split_from_id = s.id);
    end if;
    if s.updated_at is distinct from s.created_at
       or exists (select 1 from public.so_line x where x.so_id = s.id and x.updated_at is distinct from s.created_at)
       or exists (select 1 from public.so_reserve r join public.so_line x on x.id = r.so_line_id where x.so_id = s.id and r.released_at is null and r.updated_at is distinct from s.created_at)   -- 열린 예약만 · 풀린 이력은 무시(2026-09-24 결함 고침 — 돌아온 줄이 옛 풀림을 달고 온다)
       or exists (select 1 from public.so_charge ch where ch.so_id = s.id) then
      raise exception 'Split order % was changed after the split — unconfirm is only possible while the split orders are untouched — nothing was saved', s.so_number;
    end if;
  end loop;

  -- ③b 판정 5·⬜8: 이 확정이 이어받아 닫은 남의 백오더 줄을 다시 연다 — 대상 백오더 오더가 끝 상태(만료·취소)면 거부(판정 11) · 쓰기 전에 먼저(거부면 아무것도 안 쓴다)
  v_reopen := public.so_backorder_reopen(array[p_so_id], v_staff);

  -- 예약 전부 풀기 — 원래(allocated · hold · backorder · preorder) + 형제(backorder · preorder) · 지우지 않는다(5-f)
  update public.so_reserve r set released_at = now(), released_by = v_staff, updated_by = v_staff
  from public.so_line x
  where x.id = r.so_line_id and r.released_at is null
    and (x.so_id = p_so_id or x.so_id in (select id from public.so where split_from_id = p_so_id and status <> 'cancelled' and split_reason in ('stock_short','preorder')));
  get diagnostics v_released = row_count;

  -- 형제 줄 도로 합치기 · 형제 닫기
  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;
  for s in select * from public.so x where x.split_from_id = p_so_id and x.status <> 'cancelled' and x.split_reason in ('stock_short','preorder') order by x.so_number loop
    for l in select * from public.so_line x where x.so_id = s.id order by x.line_no loop
      if l.split_from_line_id is not null then
        update public.so_line set qty_ordered = qty_ordered + l.qty_ordered, updated_by = v_staff
        where id = l.split_from_line_id and so_id = p_so_id;
        get diagnostics v_n = row_count;
        if v_n <> 1 then raise exception 'Line % of % has lost its original line — nothing was saved', l.line_no, s.so_number; end if;
        if exists (select 1 from public.so_line_note sn where sn.so_line_id = l.id) then                                  -- so-line-note-1(이견 5): 형제 줄의 손님 메모를 원래 줄로 — 원래 줄이 비었으면 옮기고 · 다르면 「 / 」 로 잇는다(500 자 넘으면 거부)
          perform public.so_line_note_put(l.split_from_line_id, public.so_line_note_join(array[(select sn.note from public.so_line_note sn where sn.so_line_id = l.split_from_line_id), (select sn.note from public.so_line_note sn where sn.so_line_id = l.id)]), v_staff);
        end if;
        v_added := v_added + 1;                                  -- 형제 줄 행은 이력으로 남는다(합계는 merged 문서를 뺀다)
      else
        v_next := v_next + 1;
        update public.so_line set so_id = p_so_id, line_no = v_next, updated_by = v_staff where id = l.id;
        v_moved := v_moved + 1;
      end if;
    end loop;
    update public.so set status = 'cancelled', closed_reason = 'merged', merged_into_id = p_so_id, closed_at = now(),
                         closed_note = format('Unconfirmed with %s', v_so.so_number), cancelled_by = v_staff, updated_by = v_staff
    where id = s.id and status = 'confirmed';
    get diagnostics v_n = row_count;
    if v_n <> 1 then raise exception 'Split order % was not merged back — it may have been changed by someone else just now — nothing was saved', s.so_number; end if;
    v_merged := array_append(v_merged, s.so_number);
  end loop;

  -- 원래 → draft · 되돌리기 기록 · 확정 흔적 비움(다시 확정하면 새로 찍힌다)
  update public.so set status = 'draft', confirmed_at = null, confirmed_by = null, unconfirmed_at = now(), unconfirmed_by = v_staff, updated_by = v_staff
  where id = p_so_id and status = 'confirmed';
  get diagnostics v_n = row_count;
  if v_n <> 1 then raise exception 'Order % was not unconfirmed — it may have been changed by someone else just now — nothing was saved', v_so.so_number; end if;

  return jsonb_build_object('so_number', v_so.so_number, 'status', 'draft', 'merged', to_jsonb(v_merged),
                            'lines_moved_back', v_moved, 'lines_added_back', v_added, 'reserves_released', v_released,
                            'backorders_reopened', v_reopen, 'coupon_restored', to_jsonb(public.so_coupon_release(array[p_so_id], v_staff)));   -- dsc-3b 판정 321: 가족에 confirmed 이상이 없으면 되살림
end;
$function$;

-- ═══ 재발행 4/8 — so_lines_paste(DB prosrc 원본 md5 ed9f5638 + 더한 줄) ═══
CREATE OR REPLACE FUNCTION public.so_lines_paste(p_so_id uuid, p_lines jsonb, p_commit boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c_limit    constant int := 500;
  v_staff    uuid;
  v_so       public.so%rowtype;
  v_n        int;
  v_next     int;
  r          record;
  v_sku      text;
  v_qty      numeric;
  v_pid uuid;  v_psku text;  v_pname text;  v_pactive boolean;  v_uom text;  v_unit_id uuid;  v_pack numeric;
  v_verdict  text;
  v_msgs     text[];
  v_dup_of   int;
  v_idx      int;
  i          int;
  -- 제품별로 모은 것(입력 순 · 첫 줄 번호가 대표)
  a_pid uuid[] := '{}';  a_n int[] := '{}';  a_qty numeric[] := '{}';  a_sku text[] := '{}';  a_name text[] := '{}';  a_unit text[] := '{}';  a_pack numeric[] := '{}';
  q          record;
  v_list numeric;  v_disc numeric;  v_unit numeric;  v_src text;  v_dsrc text;  v_deal uuid;
  v_match    public.so_line%rowtype;
  v_others   int;
  v_line_no  int;
  v_inserted boolean;  v_updated boolean;
  v_rows     jsonb := '[]'::jsonb;
  n_ok int := 0;  n_noprice int := 0;  n_merged int := 0;  n_ask int := 0;  n_dup int := 0;  n_nf int := 0;  n_inactive int := 0;  n_bad int := 0;  n_ins int := 0;  n_upd int := 0;
  v_combo    boolean;  v_ncomp int;  v_new_id uuid;                 -- asm-2a(판정 244 · 묶음 2): 콤보 SKU 면 콤보 줄 + 구성품 줄(미리 보기도 줄 번호를 같이 센다)
  v_psell boolean;  v_pparent uuid;  v_conv jsonb;  v_bid uuid;  v_bsku text;  v_bname text;  v_bactive boolean;  v_buom text;  v_bunit uuid;  v_bpack numeric;  v_bsell boolean;  n_conv int := 0;  n_ns int := 0;   -- dsc-1 판정 281 · 293
  v_price numeric;  v_has_price boolean;  a_price numeric[] := '{}';  v_res jsonb;  n_badp int := 0;  n_freep int := 0;  n_setp int := 0;  n_priced int := 0;   -- ln-1 판정 532 · 545: 줄마다 가격(선택) · 가격 묶음은 so_line_add 로
  v_note text;  v_note_old text;  a_note text[] := '{}';  n_badn int := 0;   -- so-line-note-1 판정 1151: 줄마다 손님 메모(선택 · 열쇠 note)
begin
  perform public.ims_require_write('sales', 'saved');          -- ⭐ 첫 줄
  v_staff := public.so_current_staff();
  v_so := public.so_require_draft(p_so_id, 'saved');
  if v_so.channel = 'service' then                                                                                -- svc-1b 판정 590: 서비스 오더는 서비스 줄만(상품 줄 없음)
    raise exception 'Order % is a service order — it takes service lines only (Add a service), not products — nothing was saved', v_so.so_number;
  end if;

  v_n := coalesce(jsonb_array_length(p_lines), 0);
  if v_n > c_limit then
    return jsonb_build_object(
      'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', false,
      'summary', jsonb_build_object('total', v_n, 'ok', 0, 'no_price', 0, 'merged', 0, 'ask', 0, 'duplicate', 0, 'not_found', 0, 'inactive', 0, 'bad_qty', 0,
                                    'converted', 0, 'not_sellable', 0, 'bad_price', 0, 'free_price', 0, 'set_price_refused', 0, 'priced', 0, 'bad_note', 0,
                                    'inserted', 0, 'updated', 0, 'too_many', true, 'limit', c_limit,
                                    'message', format('Too many lines (%s) — up to %s lines per paste. Nothing was saved.', v_n, c_limit)),
      'lines', '[]'::jsonb);
  end if;

  select coalesce(max(line_no), 0) into v_next from public.so_line where so_id = p_so_id;

  -- 1) 입력 → 제품 · 같은 제품은 첫 줄에 수량을 모은다
  for r in
    select t.ord::int as n, t.e->>'sku' as sku_raw, t.e->>'qty' as qty_raw, t.e->>'price' as price_raw, t.e->>'note' as note_raw   -- ln-1 · so-line-note-1
    from jsonb_array_elements(coalesce(p_lines, '[]'::jsonb)) with ordinality as t(e, ord)
    order by t.ord
  loop
    v_pid := null; v_psku := null; v_pname := null; v_pactive := null; v_uom := null; v_unit_id := null; v_pack := null;
    v_verdict := null; v_msgs := '{}'; v_dup_of := null; v_idx := null;
    v_conv := null;
    v_price := null; v_has_price := nullif(btrim(coalesce(r.price_raw, '')), '') is not null;                                              -- ln-1 판정 545: 없거나 빈 글자 = 원래 가격
    v_note := public.so_line_note_clean(r.note_raw);                                                                                            -- so-line-note-1: 한 줄로 굳힌다(빈칸 = 없음)

    -- SKU 다듬기 — 앞뒤 공백(비분리 공백 포함)만 · po_lines_paste 와 같은 정규식(바이트 그대로)
    v_sku := nullif(regexp_replace(coalesce(r.sku_raw, ''), '^[\s ]+|[\s ]+$', '', 'g'), '');
    -- 수량 — 숫자만
    v_qty := case when r.qty_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.qty_raw::numeric else null end;

    if v_sku is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'empty_sku');
    else
      select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor into v_pid, v_psku, v_pname, v_pactive, v_uom, v_unit_id, v_pack
      from public.product p where p.sku = v_sku;                                  -- 유니크 인덱스
      if v_pid is null then
        select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor into v_pid, v_psku, v_pname, v_pactive, v_uom, v_unit_id, v_pack
        from public.product p where upper(p.sku) = upper(v_sku) limit 1;         -- 폴백 · 못 찾은 줄에만
        if v_pid is not null then v_msgs := array_append(v_msgs, 'case_fixed'); end if;
      end if;
    end if;

    if v_verdict is null and v_pid is null then
      v_verdict := 'not_found'; v_msgs := array_append(v_msgs, 'sku_not_in_product');
    end if;
    if v_verdict is null and v_pactive is false then
      v_verdict := 'inactive'; v_msgs := array_append(v_msgs, 'inactive_product — not added');
    end if;
    if v_verdict is null and (v_qty is null or v_qty <= 0) then
      v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, 'qty_must_be_positive_number');
    end if;
    -- ln-1 판정 532 · 545: 가격 — 숫자만(수량과 같은 꼴 · 자리 수 한도 없음 = so_line_add) · 음수 · 글자 → bad_price · 0 → free_price(무상 줄은 사유가 필요하다 — Add line)
    if v_verdict is null and v_has_price then
      v_price := case when r.price_raw ~ '^\s*-?[0-9]+(\.[0-9]+)?\s*$' then r.price_raw::numeric else null end;
      if v_price is null or v_price < 0 then
        v_verdict := 'bad_price'; v_msgs := array_append(v_msgs, 'price_must_be_a_non_negative_number — not added');
      elsif v_price = 0 then
        v_verdict := 'free_price'; v_msgs := array_append(v_msgs, 'free lines: use Add line (a price of 0 needs a free-goods reason) — not added');
      end if;
    end if;
    if v_verdict is null and char_length(v_note) > 500 then                                                                                   -- so-line-note-1: 자르지 않는다
      v_verdict := 'bad_note'; v_msgs := array_append(v_msgs, format('note_is_%s_characters — the limit is 500 — not added', char_length(v_note)));
    end if;
    -- dsc-1 판정 281 · 293 — 안 파는 세트는 낱개 × pack_factor 로 바꾼다(꼬리표 converted · duplicate 묶기 앞이라 같은 낱개 줄과 합쳐진다) · 안 파는 낱개(바뀐 것도)는 not_sellable · 콤보는 바꿀 낱개가 없어 not_sellable
    if v_verdict is null then
      select p.sellable, p.parent_product_id into v_psell, v_pparent from public.product p where p.id = v_pid;
      if v_pparent is not null and not v_psell and v_has_price then                                                                        -- ln-1 판정 292: 바꾸는 길에 손 단가 금지(세트 단가를 낱개에 쓰면 pack_factor 배 틀린다)
        v_verdict := 'set_price_refused'; v_msgs := array_append(v_msgs, format('set_%s_is_not_sold_as_a_set — paste the base SKU %s with its own price — not added', v_psku, coalesce((select x.sku from public.product x where x.id = v_pparent), '?')));
      elsif v_pparent is not null and not v_psell then
        select p.id, p.sku, p.name, p.is_active, p.uom_name, p.unit_id, p.pack_factor, p.sellable into v_bid, v_bsku, v_bname, v_bactive, v_buom, v_bunit, v_bpack, v_bsell from public.product p where p.id = v_pparent;
        if v_bid is null or not v_bactive then
          v_verdict := 'inactive'; v_msgs := array_append(v_msgs, format('set_%s_not_sold_as_set_and_base_%s_inactive — not added', v_psku, coalesce(v_bsku, '?')));
        elsif v_pack is null or v_pack <= 0 then
          v_verdict := 'bad_qty'; v_msgs := array_append(v_msgs, format('set_%s_has_no_pack_factor — not added', v_psku));
        else
          v_conv := jsonb_build_object('set_sku', v_psku, 'set_qty', v_qty, 'pack_factor', v_pack, 'base_sku', v_bsku, 'base_qty', v_qty * v_pack);
          v_msgs := array_append(v_msgs, format('converted_from_set_%s_x%s — %s × %s', v_psku, v_qty, v_bsku, v_qty * v_pack));
          v_qty := v_qty * v_pack;
          v_pid := v_bid; v_psku := v_bsku; v_pname := v_bname; v_pactive := v_bactive; v_uom := v_buom; v_unit_id := v_bunit; v_pack := v_bpack; v_psell := v_bsell;
        end if;
      end if;
      if v_verdict is null and not v_psell then
        v_verdict := 'not_sellable'; v_msgs := array_append(v_msgs, format('%s_not_for_sale — turn on Sellable in Products first — not added', v_psku));
      end if;
      if v_verdict is null and v_conv is not null then n_conv := n_conv + 1; end if;        -- 바뀌었다가 거부된 줄(바뀐 낱개가 안 팜)은 converted 수에 안 센다 · 꼬리표는 남아 「왜 거부됐나」를 보인다
    end if;

    if v_verdict is null then
      select s.i into v_idx from generate_subscripts(a_pid, 1) s(i) where a_pid[s.i] = v_pid and a_price[s.i] is not distinct from v_price limit 1;   -- ln-1: 묶기 열쇠 = (제품, 가격)
      if v_idx is not null then
        v_dup_of := a_n[v_idx];
        a_qty[v_idx] := a_qty[v_idx] + v_qty;
        if a_note[v_idx] is null then a_note[v_idx] := v_note;                                                                                -- so-line-note-1: 같은 SKU 가 둘이면 첫 메모
        elsif v_note is not null and v_note <> a_note[v_idx] then v_msgs := array_append(v_msgs, 'note_not_saved — this SKU already has a note on an earlier pasted line');
        end if;
        v_verdict := 'duplicate';
        v_msgs := array_append(v_msgs, format('merged_into_paste_line_%s — quantities added', v_dup_of));
      elsif exists (select 1 from generate_subscripts(a_pid, 1) s(i) where a_pid[s.i] = v_pid) then                                                   -- ln-1: 같은 제품이 다른 가격으로 이미 이 붙여넣기에 있다 → 둘째부터 ask(미리 보기 = 저장)
        v_verdict := 'ask'; n_ask := n_ask + 1;
        v_msgs := array_append(v_msgs, 'same_sku_pasted_at_different_prices — paste one price per SKU or add separately — not added');
      else
        a_pid := array_append(a_pid, v_pid);  a_n := array_append(a_n, r.n);  a_qty := array_append(a_qty, v_qty);  a_price := array_append(a_price, v_price);
        a_sku := array_append(a_sku, v_psku);  a_name := array_append(a_name, v_pname);
        a_unit := array_append(a_unit, coalesce((select u.name from public.ref_unit u where u.id = v_unit_id), v_uom));
        a_pack := array_append(a_pack, v_pack);
        a_note := array_append(a_note, v_note);
      end if;
    end if;

    case v_verdict
      when 'not_found' then n_nf := n_nf + 1;
      when 'inactive'  then n_inactive := n_inactive + 1;
      when 'bad_qty'   then n_bad := n_bad + 1;
      when 'duplicate' then n_dup := n_dup + 1;
      when 'not_sellable' then n_ns := n_ns + 1;                   -- dsc-1
      when 'bad_price' then n_badp := n_badp + 1;                   -- ln-1
      when 'free_price' then n_freep := n_freep + 1;
      when 'set_price_refused' then n_setp := n_setp + 1;
      when 'bad_note' then n_badn := n_badn + 1;                   -- so-line-note-1
      else null;
    end case;

    v_rows := v_rows || jsonb_build_object(
      'n', r.n, 'input_sku', r.sku_raw, 'input_qty', r.qty_raw, 'input_price', r.price_raw, 'price', v_price, 'note', v_note,   -- ln-1 · so-line-note-1
      'verdict', v_verdict,                                      -- null = 2) 에서 정해진다
      'product_id', v_pid, 'sku', v_psku, 'product_name', v_pname, 'product_active', v_pactive,
      'qty', v_qty, 'line_no', null, 'inserted', false, 'updated', false,
      'converted', v_conv,                                        -- dsc-1 판정 293: 꼬리표(판정은 그대로 ok · merged · ask · no_price 로 끝난다)
      'message', array_to_string(v_msgs, ' · '));
  end loop;

  -- 2) 제품별 — 가격(수량 포함) · 기존 줄과 대조(판정 2) · 넣기(결과는 그 제품의 첫 입력 줄에 적는다)
  for i in 1 .. coalesce(array_length(a_pid, 1), 0) loop
    select * into q from public.so_line_quote(v_so, a_pid[i], a_qty[i]);
    v_list := q.list_price;  v_disc := q.discount_pct;  v_unit := q.unit_price;  v_src := q.price_source;  v_dsrc := q.discount_source;  v_deal := q.deal_line_id;
    v_line_no := null; v_inserted := false; v_updated := false; v_msgs := '{}';
    v_combo := public.so_combo_is(a_pid[i]);
    v_ncomp := case when v_combo then (select count(*) from public.product_bom b where b.parent_product_id = a_pid[i] and b.is_active) else 0 end;

    -- ln-1 판정 532 · 545: 가격 묶음 — ① 시스템 줄 합치기를 건너뛴다 · 사람이 정한 줄 가운데 같은 단가 → 수량만 · 같은 제품의 다른 줄(시스템 줄 · 같은 가격이어도)이 있으면 ask · 없으면 so_line_add(p_force_new) 가 새 줄
    if a_price[i] is not null then
      v_disc := null; v_dsrc := null; v_deal := null; v_unit := a_price[i]; v_src := 'paste';                                                   -- 반환 줄: 정가는 견적의 list(so_line_add 가 넣는 것과 같다) · 할인 없음 · 단가 = 그 가격
      n_priced := n_priced + 1;
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and (l.price_override or l.discount_source is not distinct from 'manual') and l.unit_price = a_price[i]
        and l.bgrade_bin_id is null                                                                                                                         -- bgr-1c 판정 635: B급 줄에 붙여 넣지 않는다
      order by l.line_no limit 1;
      if found then
        v_verdict := 'merged'; v_line_no := v_match.line_no;
        v_msgs := array_append(v_msgs, format('added_to_line_%s — same price you set', v_match.line_no));
        if p_commit then
          update public.so_line set qty_ordered = qty_ordered + a_qty[i], updated_by = v_staff where id = v_match.id;
          if v_combo then perform public.so_combo_children_sync(v_match.id, v_staff); end if;
          v_updated := true; n_upd := n_upd + 1;
        end if;
        n_merged := n_merged + 1;
      else
        select count(*) into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and l.bgrade_bin_id is null;
        if v_others > 0 then
          v_verdict := 'ask';
          v_msgs := array_append(v_msgs, 'same_sku_already_on_this_order_at_another_price — pasted prices are final: change that line or add separately (so_line_add p_force_new)');
          n_ask := n_ask + 1;
        else
          v_verdict := 'ok'; n_ok := n_ok + 1;
          v_next := v_next + 1; v_line_no := v_next;
          v_next := v_next + v_ncomp;                                                                                                            -- 구성품 줄이 뒤따르는 번호(so_line_add 도 max + 1 · 구성품은 그 뒤)
          if p_commit then
            v_res := public.so_line_add(p_so_id, a_pid[i], a_qty[i], a_price[i], null, null, null, true);                                       -- 값 · surcharge · 콤보 구성품 · price_set_by 가 한 곳에서 난다
            v_new_id := (v_res->'line'->>'id')::uuid;
            if (v_res->'line'->>'line_no')::int <> v_line_no then raise exception 'Paste line %: line number mismatch (preview % · saved %) — nothing was saved', a_n[i], v_line_no, v_res->'line'->>'line_no'; end if;
            v_inserted := true; n_ins := n_ins + 1;
          end if;
        end if;
      end if;
    else
    -- ① 같은 제품의 시스템 줄 — 제품만으로 합치고 합친 수량으로 다시 견적
    select * into v_match from public.so_line l
    where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and not l.price_override and l.discount_source is distinct from 'manual'   -- asm-2a: 구성품 줄에는 합치지 않는다
    order by l.line_no limit 1;
    if found then
      v_verdict := 'merged'; v_line_no := v_match.line_no;
      v_msgs := array_append(v_msgs, format('added_to_line_%s — requoted at %s', v_match.line_no, v_match.qty_ordered + a_qty[i]));
      if p_commit then
        perform public.so_line_requote(v_match.id, v_match.qty_ordered + a_qty[i]);
        if v_combo then perform public.so_combo_children_sync(v_match.id, v_staff); end if;                                 -- asm-2a(묶음 3)
        v_updated := true; n_upd := n_upd + 1;
      end if;
      n_merged := n_merged + 1;
    else
      -- ② 사람이 정한 줄 — 단가가 같으면 수량만 · 다르면 ask
      select * into v_match from public.so_line l
      where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and l.unit_price is not distinct from v_unit                            -- asm-2a
        and l.bgrade_bin_id is null                                                                                                                         -- bgr-1c
      order by l.line_no limit 1;
      if found then
        v_verdict := 'merged'; v_line_no := v_match.line_no;
        v_msgs := array_append(v_msgs, format('added_to_line_%s', v_match.line_no));
        if p_commit then
          update public.so_line set qty_ordered = qty_ordered + a_qty[i], updated_by = v_staff where id = v_match.id;
          if v_combo then perform public.so_combo_children_sync(v_match.id, v_staff); end if;                               -- asm-2a(묶음 3)
          v_updated := true; n_upd := n_upd + 1;
        end if;
        n_merged := n_merged + 1;
      else
        select count(*) into v_others from public.so_line l where l.so_id = p_so_id and l.product_id = a_pid[i] and l.combo_line_id is null and l.bgrade_bin_id is null;                 -- asm-2a: 구성품 줄은 「같은 SKU」가 아니다
        if v_others > 0 then
          v_verdict := 'ask';
          v_msgs := array_append(v_msgs, 'same_sku_at_different_price — use so_line_add to merge into that line or add separately (p_force_new)');
          n_ask := n_ask + 1;
        else
          if v_unit is null then
            v_verdict := 'no_price'; n_noprice := n_noprice + 1;
            v_msgs := array_append(v_msgs, 'no_price_for_this_tier — saved without a price; confirm will refuse until it has one');
          else
            v_verdict := 'ok'; n_ok := n_ok + 1;
          end if;
          if v_deal is not null and public.so_deal_line_ended(v_deal, public.ims_today()) then v_msgs := array_append(v_msgs, 'deal_ended_before_line_added'); end if;
          v_next := v_next + 1; v_line_no := v_next;
          v_next := v_next + v_ncomp;                                                                                                -- asm-2a: 구성품 줄이 뒤따르는 번호(미리 보기 · 저장 같게)
          if p_commit then
            insert into public.so_line (so_id, line_no, product_id, sku, product_name, unit, pack_factor, qty_ordered,
                                        list_price, discount_pct, unit_price, price_override, discount_source, deal_line_id, free_reason, tax_rule, comments, updated_by,
                                        surcharge_pct, surcharge_amount, surcharge_label)                                                                          -- surcharge-4a(묶음 3): 붙여 넣기도 같은 도우미(무상 줄은 이 길에 없다)
            select p_so_id, v_line_no, a_pid[i], a_sku[i], a_name[i], a_unit[i], coalesce(a_pack[i], 1), a_qty[i],
                    v_list, v_disc, v_unit, false, v_dsrc, v_deal, null, v_so.tax_rule, null, v_staff,
                    d.surcharge_pct, d.surcharge_amount, d.surcharge_label
            from public.so_line_surcharge_defaults(a_pid[i], false) d
            returning id into v_new_id;
            if v_combo then perform public.so_combo_children_insert((select l from public.so_line l where l.id = v_new_id), v_staff); end if;   -- asm-2a(묶음 2)
            v_inserted := true; n_ins := n_ins + 1;
          end if;
        end if;
      end if;
    end if;
    end if;                                                                                                                                       -- ln-1: 가격 묶음 / 가격 없는 묶음

    -- so-line-note-1 판정 1151(이견 14): 손님 메모 — 새 줄은 저장 · 기존 줄에 합쳐졌으면 그 줄에 메모가 없을 때만 저장 · 다른 글이 있으면 그대로 두고 알린다(미리 보기도 같은 판정)
    if a_note[i] is not null and v_line_no is not null then
      select sn.note into v_note_old from public.so_line_note sn join public.so_line nl on nl.id = sn.so_line_id where nl.so_id = p_so_id and nl.line_no = v_line_no;
      if v_note_old is not null and v_note_old <> a_note[i] then
        v_msgs := array_append(v_msgs, format('note_not_saved — line %s already has a note (change it on that line)', v_line_no));
      elsif p_commit and v_note_old is null then
        perform public.so_line_note_put((select nl.id from public.so_line nl where nl.so_id = p_so_id and nl.line_no = v_line_no), a_note[i], v_staff);
      end if;
    end if;

    v_rows := coalesce((
      select jsonb_agg(
               case when (e->>'n')::int = a_n[i]
                    then e || jsonb_build_object('verdict', v_verdict, 'qty', a_qty[i], 'list_price', v_list, 'discount_pct', v_disc, 'discount_source', v_dsrc,
                                                 'unit_price', v_unit, 'price_source', v_src, 'line_no', v_line_no,
                                                 'inserted', v_inserted, 'updated', v_updated, 'note', a_note[i], 'message', array_to_string(v_msgs, ' · '), 'combo', v_combo, 'components', v_ncomp)   -- asm-2a
                    else e end
               order by (e->>'n')::int)
      from jsonb_array_elements(v_rows) e), '[]'::jsonb);
  end loop;

  return jsonb_build_object(
    'so_id', p_so_id, 'so_number', v_so.so_number, 'committed', p_commit,
    'summary', jsonb_build_object('total', v_n, 'ok', n_ok, 'no_price', n_noprice, 'merged', n_merged, 'ask', n_ask, 'duplicate', n_dup,
                                  'not_found', n_nf, 'inactive', n_inactive, 'bad_qty', n_bad,
                                  'converted', n_conv, 'not_sellable', n_ns, 'bad_price', n_badp, 'free_price', n_freep, 'set_price_refused', n_setp, 'priced', n_priced, 'bad_note', n_badn,   -- ln-1 · so-line-note-1
                                  'inserted', n_ins, 'updated', n_upd, 'too_many', false, 'limit', c_limit, 'message', null),
    'lines', v_rows);
end;
$function$;

-- ═══ 재발행 5/8 — doc_data_so(DB prosrc 원본 md5 fe40d90b + 더한 줄) ═══
CREATE OR REPLACE FUNCTION public.doc_data_so(p_so_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_so   public.so%rowtype;
  v_pf   jsonb;  v_o jsonb;  v_t jsonb;
  v_fmt  text := p_cfg->>'date_format';
  v_disp text := coalesce(p_cfg->>'unit_display', 'both');
  v_lines jsonb;  v_charges jsonb := '[]'::jsonb;  v_prepay jsonb;
  v_lines_tax numeric;  v_n int := 0;  v_x jsonb;  v_sc_code text := (select c.value from public.inv_config c where c.key = 'so_surcharge_account_code');
  v_chg_amt numeric;  v_chg_tax numeric;
begin
  select * into v_so from public.so s where s.id = p_so_id;
  if v_so.id is null then raise exception 'Order not found'; end if;
  v_pf := public.so_proforma(array[p_so_id]);
  v_o := v_pf->'orders'->0;  v_t := v_pf->'totals';
  select coalesce(jsonb_agg((jsonb_build_object('no', x.no::text, 'upc', public.doc_upc(sl.product_id), 'sku', coalesce(x.l->>'sku', ''), 'description', coalesce(x.l->>'product_name', ''), 'comment', coalesce((select sn.note from public.so_line_note sn where sn.so_line_id = sl.id), ''),
                                                'unit', coalesce(x.l->>'unit', ''), 'qty', public.doc_fmt_qty((x.l->>'qty')::numeric),   -- doc-hand-price-1: list_price · discount_pct 는 아래 doc_price_cells 가 준다
                                                'amount', public.doc_fmt_money((x.l->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((x.l->>'tax')::numeric), 'is_free', sl.free_reason is not null, 'no_price', sl.unit_price is null)
                             || public.doc_unit_prices(sl.unit_price, case when coalesce(public.so_line_manual(sl), false) then null else v_so.order_discount_pct end, v_disp)
                             || public.doc_price_cells((x.l->>'list_price')::numeric, (x.l->>'discount_pct')::numeric, sl.unit_price, coalesce(public.so_line_manual(sl), false), sl.free_reason is not null)) order by x.no), '[]'::jsonb),   -- doc-hand-price-1 판정 976: 손 가격 줄은 단가 칸에 손 가격 · 할인 빈칸(fmt 와 같은 식 · doc_price_cells)
         coalesce(sum((x.l->>'tax')::numeric), 0)
    into v_lines, v_lines_tax
  from (select l, row_number() over (order by (l->>'line_no')::int) as no from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l) x
  left join public.so_line sl on sl.id = (x.l->>'line_id')::uuid;
  -- charges = 운임(정가) · 운임 할인(음수) · 오더 할인(음수) · 줄 부가 요금 — so_tax_preview 가 센 값 그대로 · 순서 운임 → 할인 → 오더 할인 → 부가 요금
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charges', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_x->>'account_code', ''), 'description', coalesce(v_x->>'name', ''), 'comment', coalesce(v_x->>'description', ''),
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  for v_x in select c from jsonb_array_elements(coalesce(v_o->'charge_discounts', '[]'::jsonb)) c loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce((select c.value from public.inv_config c where c.key = 'so_freight_discount_account_code'), ''), 'description', coalesce(v_x->>'name', ''), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', public.doc_fmt_pct((v_x->>'discount_pct')::numeric), 'amount', public.doc_fmt_money((v_x->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'tax')::numeric));
  end loop;
  if coalesce((v_o->'order_discount'->>'amount')::numeric, 0) <> 0 then
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_so.sale_account_code, ''), 'description', format('Order discount %s%%', public.doc_fmt_qty((v_o->'order_discount'->>'pct')::numeric)), 'comment', '',
                                                 'qty', '', 'unit_price', '', 'discount_pct', '', 'amount', public.doc_fmt_money((v_o->'order_discount'->>'amount')::numeric), 'tax_amount', public.doc_fmt_money((v_o->'order_discount'->>'tax')::numeric));
  end if;
  for v_x in select l from jsonb_array_elements(coalesce(v_o->'lines', '[]'::jsonb)) l where coalesce((l->>'surcharge_total')::numeric, 0) > 0 order by (l->>'line_no')::int loop
    v_n := v_n + 1;
    v_charges := v_charges || jsonb_build_object('no', v_n::text, 'so_number', v_so.so_number, 'code', coalesce(v_sc_code, ''), 'description', coalesce(nullif(v_x->>'surcharge_label', ''), 'Surcharge') || ' (' || (v_x->>'sku') || ')', 'comment', '',
                                                 'qty', public.doc_fmt_qty((v_x->>'qty')::numeric), 'unit_price', public.doc_fmt_money((v_x->>'surcharge_unit')::numeric), 'discount_pct', '',
                                                 'amount', public.doc_fmt_money((v_x->>'surcharge_total')::numeric), 'tax_amount', public.doc_fmt_money((v_x->>'surcharge_tax')::numeric));
  end loop;
  v_chg_amt := coalesce((v_t->>'charges_amount')::numeric, 0) - coalesce((v_t->>'charges_discount_amount')::numeric, 0) + coalesce((v_t->>'order_discount_amount')::numeric, 0) + coalesce((v_t->>'surcharge_amount')::numeric, 0);
  v_chg_tax := case when v_t->>'tax' is null then null else (v_t->>'tax')::numeric - v_lines_tax end;
  select coalesce(jsonb_agg(jsonb_build_object('no', x.no::text, 'reference', coalesce(x.d->>'reference', ''), 'date', public.doc_fmt_date((x.d->>'paid_on')::date, v_fmt), 'method', public.doc_method_label(x.d->>'method'), 'amount', public.doc_fmt_money((x.d->>'remaining')::numeric)) order by x.no), '[]'::jsonb)
    into v_prepay
  from (select d, row_number() over () as no from jsonb_array_elements(coalesce(v_pf->'deposits', '[]'::jsonb)) d) x;
  return jsonb_build_object(
    'so', jsonb_build_object('number', v_so.so_number, 'date', public.doc_fmt_date(v_so.order_date, v_fmt), 'status', v_so.status, 'required_by', public.doc_fmt_date(v_so.required_by, v_fmt), 'terms', coalesce(v_so.payment_term_name, ''),
                             'reference', coalesce(v_so.ref, ''), 'currency', coalesce(v_so.currency_code, ''), 'memo', coalesce(v_so.comments, '')),
    'ship_to', jsonb_build_object('company', coalesce(v_so.ship_to_company, ''), 'contact', coalesce(v_so.ship_to_contact, ''), 'phone', coalesce(v_so.ship_to_phone, ''), 'line1', coalesce(v_so.ship_to_line1, ''), 'line2', coalesce(v_so.ship_to_line2, ''),
                                  'city', coalesce(v_so.ship_to_city, ''), 'state_province', coalesce(v_so.ship_to_state_province, ''), 'postal_code', coalesce(v_so.ship_to_postal_code, ''), 'country', coalesce(v_so.ship_to_country, '')),
    'lines', v_lines, 'charges', v_charges, 'prepayments', v_prepay,
    'totals', jsonb_build_object('lines_before_tax', public.doc_fmt_money((v_t->>'lines_amount')::numeric), 'lines_tax', public.doc_fmt_money(v_lines_tax), 'lines_total', public.doc_fmt_money((v_t->>'lines_amount')::numeric + v_lines_tax),
                                 'charges_before_tax', public.doc_fmt_money(v_chg_amt), 'charges_tax', public.doc_fmt_money(v_chg_tax), 'charges_total', public.doc_fmt_money(v_chg_amt + v_chg_tax),
                                 'order_discount', public.doc_fmt_money((v_t->>'order_discount_amount')::numeric), 'surcharge', public.doc_fmt_money((v_t->>'surcharge_amount')::numeric), 'charges_discount', public.doc_fmt_money(-(v_t->>'charges_discount_amount')::numeric),
                                 'before_tax', public.doc_fmt_money((v_t->>'taxable_amount')::numeric), 'tax', public.doc_fmt_money((v_t->>'tax')::numeric), 'total', public.doc_fmt_money((v_t->>'total')::numeric),
                                 'prepaid', public.doc_fmt_money_nz((v_t->>'received')::numeric), 'due_amount', public.doc_fmt_money((v_t->>'balance_due')::numeric)) || public.doc_qty_totals(v_o->'lines'))   -- doc-qty-1: totals 에 line_count · qty_total · qty_total_ea(so_proforma 의 줄 = 위 lines 와 같은 원천 · 구성품 줄 이미 뺌 · pack_factor 는 so_tax_preview 가 싣는다) · doc-1c 판정 528 ③ 의 결: 선결제 없으면 빈칸 · due 는 늘(아직 안 낸 오더)
    || public.doc_data_common('sales_order', p_cfg, jsonb_build_object('name', v_so.bill_to_name, 'line1', v_so.bill_to_line1, 'line2', v_so.bill_to_line2, 'city', v_so.bill_to_city, 'state_province', v_so.bill_to_state_province,
                                                                        'postal_code', v_so.bill_to_postal_code, 'country', v_so.bill_to_country) || public.doc_contact(coalesce(v_so.bill_to_customer_id, v_so.customer_id)));
end;
$function$;

-- ═══ 재발행 6/8 — doc_data_invoice(DB prosrc 원본 md5 2fc7e887 + 더한 줄) ═══
CREATE OR REPLACE FUNCTION public.doc_data_invoice(p_kind text, p_invoice_id uuid, p_cfg jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_inv public.so_invoice%rowtype;
  v_n   jsonb;
begin
  select * into v_inv from public.so_invoice i where i.id = p_invoice_id;
  if v_inv.id is null then raise exception 'Invoice not found'; end if;
  if v_inv.kind = 'opening' then raise exception 'Invoice % was carried forward from the previous system — the original is in QuickBooks. It cannot be printed or mailed from IMS', v_inv.invoice_number; end if;   -- ar-2 판정 785: doc_data 한 곳(화면 인쇄 · 미리 보기 · 서버 PDF · 메일 자리표 전부)
  v_n := jsonb_build_object(
    'header', jsonb_build_object('number', v_inv.invoice_number, 'issued_on', v_inv.issued_on, 'due_on', v_inv.due_on, 'payment_term_name', v_inv.payment_term_name, 'currency_code', v_inv.currency_code, 'memo', v_inv.note,
                                 'bill_to_customer_id', v_inv.bill_to_customer_id,
                                 'bill_to', jsonb_build_object('name', v_inv.bill_to_name, 'line1', v_inv.bill_to_line1, 'line2', v_inv.bill_to_line2, 'city', v_inv.bill_to_city, 'state_province', v_inv.bill_to_state_province, 'postal_code', v_inv.bill_to_postal_code, 'country', v_inv.bill_to_country)),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object(
                 'so_number', o.so_number, 'reference', s.ref, 'carrier', s.carrier, 'tracking', s.tracking_number, 'tax_rule', o.tax_rule, 'order_discount_pct', o.order_discount_pct,
                 'ship_to', jsonb_build_object('company', o.ship_to_company, 'contact', o.ship_to_contact, 'phone', o.ship_to_phone, 'line1', o.ship_to_line1, 'line2', o.ship_to_line2, 'city', o.ship_to_city, 'state_province', o.ship_to_state_province, 'postal_code', o.ship_to_postal_code, 'country', o.ship_to_country),
                 'lines', (select coalesce(jsonb_agg(jsonb_build_object('product_id', sl.product_id, 'sku', l.sku, 'description', l.description, 'comment', (select sn.note from public.so_line_note sn where sn.so_line_id = sl.id), 'unit', l.unit, 'qty', l.qty, 'pack_factor', l.pack_factor, 'list_price', l.list_price, 'discount_pct', l.discount_pct,
                                                                        'unit_price', l.unit_price, 'amount', l.amount, 'tax_amount', l.tax_amount, 'is_free', sl.free_reason is not null, 'no_price', l.unit_price is null, 'manual', coalesce(public.so_line_manual(sl), false), 'final_sale', coalesce(sl.bgrade_bin_id is not null, false)) order by l.line_no), '[]'::jsonb)
                           from public.so_invoice_line l left join public.so_line sl on sl.id = l.so_line_id where l.invoice_order_id = o.id and l.kind = 'product')) order by o.so_number), '[]'::jsonb)
               from public.so_invoice_order o join public.so s on s.id = o.so_id where o.invoice_id = v_inv.id),
    'charges', (select coalesce(jsonb_agg(jsonb_build_object('so_number', o.so_number, 'kind', l.kind, 'account_code', l.account_code, 'description', l.description, 'comment', case when l.kind = 'charge' then c.description end,
                                                             'qty', l.qty, 'unit_price', l.unit_price, 'discount_pct', l.discount_pct, 'amount', l.amount, 'tax_amount', l.tax_amount) order by o.so_number, l.line_no), '[]'::jsonb)
                from public.so_invoice_line l join public.so_invoice_order o on o.id = l.invoice_order_id left join public.so_charge c on c.id = l.so_charge_id
                where l.invoice_id = v_inv.id and l.kind <> 'product'),
    'payments', (select coalesce(jsonb_agg(jsonb_build_object('reference', p.reference, 'paid_on', p.paid_on, 'method', p.method, 'amount', a.amount) order by p.paid_on, p.created_at, a.created_at), '[]'::jsonb)
                 from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id
                 where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
    'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_number', c.credit_number, 'issued_on', c.issued_on, 'amount', a.amount,
                                                             'reference', case when c.invoice_id = v_inv.id then null else coalesce((select oi.invoice_number from public.so_invoice oi where oi.id = c.invoice_id), c.ref_invoice_number) end)
                                          order by c.issued_on, c.credit_number, a.created_at), '[]'::jsonb)
                from public.so_credit_alloc a join public.so_credit c on c.id = a.credit_id
                where a.invoice_id = v_inv.id and a.voided_at is null and c.status = 'issued'),                                                                           -- doc-cr-1 판정 864: 이 인보이스에 걸린 살아 있는 크레딧(so_invoice_list cred · so_invoice_remaining 과 같은 조건) · reference = 원 인보이스 번호(IMS invoice_number → Cin7 ref_invoice_number) · 자기 자신이면 null
    'totals', jsonb_build_object('order_discount', v_inv.order_discount_amount, 'surcharge', v_inv.surcharge_amount, 'taxable', v_inv.taxable_amount, 'tax', v_inv.tax_amount, 'total', v_inv.total,
                                 'deposit_applied', v_inv.deposit_applied, 'credit_applied', v_inv.credit_applied, 'balance_forward', v_inv.balance_forward,
                                 'paid', (select coalesce(sum(a.amount), 0) from public.so_payment_alloc a join public.so_payment p on p.id = a.payment_id where a.invoice_id = v_inv.id and a.voided_at is null and p.status = 'active' and p.kind = 'payment'),
                                 'amount_due', v_inv.amount_due,
                                 'remaining', public.so_invoice_remaining(v_inv.id)));                                                                                     -- doc-1c 판정 528 ①: 찍는 순간 지금 남은 금액(발행 때 종이 값 amount_due 는 doc-2 의 남긴 PDF 가 지킨다)
  return public.doc_data_invoice_fmt(p_kind, p_cfg, v_n);
end;
$function$;

-- ═══ 재발행 7/8 — so_invoice_preview(DB prosrc 원본 md5 fe4974b7 + 더한 줄) ═══
CREATE OR REPLACE FUNCTION public.so_invoice_preview(p_orders jsonb, p_shipped_on date DEFAULT NULL::date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_pf      jsonb;
  v_on      date := public.ims_today();                                                  -- 발행일 = 마무리한 날(so_finalize → so_invoice_issue(…, null) · ⓐ1) · p_shipped_on 은 출고일일 뿐
  v_g       jsonb;  v_o jsonb;  e jsonb;  x jsonb;
  v_ids     uuid[];
  v_first   public.so%rowtype;  v_so public.so%rowtype;  v_pt public.ref_payment_term%rowtype;
  v_rule_id uuid;  v_prev jsonb;  v_over jsonb;
  v_sc_code text := (select nullif(k.value, '') from public.inv_config k where k.key = 'so_surcharge_account_code');
  v_fd_code text := (select nullif(k.value, '') from public.inv_config k where k.key = 'so_freight_discount_account_code');
  v_orders  jsonb;  v_lines jsonb;  v_charges jsonb;  v_pay jsonb;  v_plan jsonb;  v_docs jsonb := '[]'::jsonb;  v_warn text[];
  v_lines_amt numeric;  v_od_amt numeric;  v_chg_amt numeric;  v_chd_amt numeric;  v_sc_amt numeric;  v_tax numeric;  v_total numeric;
  v_o_od numeric;
begin
  v_pf := public.so_finalize(p_orders, false, p_shipped_on);                             -- 검사 · 묶음 · 수량 · 다시 매긴 단가 · 운임 · 부가 요금 — 쓰지 않는다(p_commit false) · 문은 so_finalize 의 것(sales)
  for v_g in select g from jsonb_array_elements(v_pf->'invoices') g loop
    select array_agg((o->>'so_id')::uuid) into v_ids from jsonb_array_elements(v_pf->'orders') o where o->>'invoice_group' = v_g->>'group';
    select * into v_first from public.so s where s.id = any(v_ids) order by s.so_number limit 1;
    v_pt := null;
    if v_first.payment_term_id is not null then select * into v_pt from public.ref_payment_term t where t.id = v_first.payment_term_id; end if;
    v_orders := '[]'::jsonb;  v_charges := '[]'::jsonb;  v_warn := '{}';
    v_lines_amt := 0;  v_od_amt := 0;  v_chg_amt := 0;  v_chd_amt := 0;  v_sc_amt := 0;  v_tax := 0;
    for v_so in select * from public.so s where s.id = any(v_ids) order by s.so_number loop
      select o into v_o from jsonb_array_elements(v_pf->'orders') o where (o->>'so_id')::uuid = v_so.id;
      -- p_over: 보낼 수량(ship.lines picked) · 다시 매긴 단가(repriced) · 부가 요금(surcharges new) · 운임(charges — 마무리 화면이 고친 · 더한 것)
      select coalesce(jsonb_object_agg(z.line_id, z.o), '{}'::jsonb) into v_over
      from (select l->>'line_id' as line_id,
                   jsonb_build_object('qty', (l->>'picked')::numeric)
                   || coalesce((select jsonb_build_object('unit_price', r->'new_unit_price', 'discount_pct', r->'new_discount_pct', 'discount_source', r->'new_discount_source')
                                from jsonb_array_elements(coalesce(v_o->'repriced', '[]'::jsonb)) r where r->>'line_id' = l->>'line_id'), '{}'::jsonb)
                   || coalesce((select s->'new' from jsonb_array_elements(coalesce(v_o->'surcharges', '[]'::jsonb)) s where s->>'line_id' = l->>'line_id'), '{}'::jsonb) as o
            from jsonb_array_elements(coalesce(v_o->'ship'->'lines', '[]'::jsonb)) l) z;
      select pe into x from jsonb_array_elements(p_orders) pe where pe->>'so_id' = v_so.id::text;                                                     -- 입력(마무리 화면이 보낸 그대로) — description 은 so_finalize 미리 보기 항목에 없어 입력에서 짝(같은 순서)으로 가져온다
      v_over := jsonb_build_object('lines', v_over,
                                   'charges', (select coalesce(jsonb_agg(jsonb_build_object('charge_id', cc.c->'charge_id', 'name', cc.c->>'name', 'description', nullif(trim(ii.i->>'description'), ''), 'amount', cc.c->'amount',
                                                                                             'discount_pct', cc.c->'discount_pct', 'discount_amount', cc.c->'discount_amount', 'account_code', cc.c->'account_code') order by cc.ord), '[]'::jsonb)
                                               from jsonb_array_elements(coalesce(v_o->'charges', '[]'::jsonb)) with ordinality cc(c, ord)
                                               left join jsonb_array_elements(coalesce(nullif(x->'charges', 'null'::jsonb), '[]'::jsonb)) with ordinality ii(i, ord) on ii.ord = cc.ord));
      v_rule_id := public.so_invoice_rule_pick(v_so, v_on);
      v_prev := public.so_tax_preview(v_so.id, v_on, v_rule_id, 'shipped', v_over);
      v_o_od := (v_prev->'totals'->>'order_discount_amount')::numeric;
      -- 제품 줄(보낸 수량 > 0 · 구성품 줄 제외) · 그 뒤 surcharge 줄 · 오더 할인 줄 · 운임 줄 + 할인 줄 — so_invoice_issue 148 ~ 180 과 같은 순서
      select coalesce(jsonb_agg(jsonb_build_object('product_id', l->'product_id', 'sku', l->>'sku', 'description', l->>'product_name', 'comment', (select sn.note from public.so_line_note sn where sn.so_line_id = sl.id), 'unit', l->>'unit', 'qty', (l->>'qty')::numeric, 'pack_factor', (l->>'pack_factor')::numeric,
                                                   'list_price', (l->>'list_price')::numeric, 'discount_pct', (l->>'discount_pct')::numeric, 'unit_price', (l->>'unit_price')::numeric, 'amount', (l->>'amount')::numeric, 'tax_amount', (l->>'tax')::numeric,
                                                   'is_free', sl.free_reason is not null, 'no_price', (l->>'unit_price') is null, 'manual', coalesce((l->>'manual')::boolean, false)) order by (l->>'line_no')::int), '[]'::jsonb)
        into v_lines
      from jsonb_array_elements(v_prev->'lines') l left join public.so_line sl on sl.id = (l->>'line_id')::uuid
      where (l->>'qty')::numeric > 0 and nullif(l->>'combo_line_id', '') is null;
      v_charges := v_charges || coalesce((select jsonb_agg(jsonb_build_object('so_number', v_so.so_number, 'kind', 'surcharge', 'account_code', v_sc_code, 'description', l->>'surcharge_label', 'comment', '',
                                                                                'qty', (l->>'qty')::numeric, 'unit_price', (l->>'surcharge_unit')::numeric, 'discount_pct', null, 'amount', (l->>'surcharge_total')::numeric, 'tax_amount', (l->>'surcharge_tax')::numeric) order by (l->>'line_no')::int)
                                          from jsonb_array_elements(v_prev->'lines') l where (l->>'qty')::numeric > 0 and nullif(l->>'combo_line_id', '') is null and coalesce((l->>'surcharge_total')::numeric, 0) > 0), '[]'::jsonb);
      if v_o_od <> 0 then
        v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'order_discount', 'account_code', v_so.sale_account_code, 'description', format('Order discount %s%%', v_so.order_discount_pct), 'comment', '',
                                                     'qty', null, 'unit_price', null, 'discount_pct', null, 'amount', v_o_od, 'tax_amount', (v_prev->'order_discount'->>'tax')::numeric);
      end if;
      for e in select c from jsonb_array_elements(v_prev->'charges') c loop
        v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'charge', 'account_code', e->>'account_code', 'description', (e->>'name') || coalesce(' — ' || (e->>'description'), ''), 'comment', coalesce(e->>'description', ''),
                                                     'qty', null, 'unit_price', null, 'discount_pct', null, 'amount', (e->>'amount')::numeric, 'tax_amount', (e->>'tax')::numeric);
        if coalesce((e->>'discount')::numeric, 0) > 0 then
          v_charges := v_charges || jsonb_build_object('so_number', v_so.so_number, 'kind', 'charge_discount', 'account_code', v_fd_code, 'comment', '',
                                                       'description', (e->>'name') || ' discount' || case when nullif(e->>'discount_pct', '') is not null then format(' %s%%', trim_scale((e->>'discount_pct')::numeric)) else '' end,
                                                       'qty', null, 'unit_price', null, 'discount_pct', nullif(e->>'discount_pct', '')::numeric, 'amount', -(e->>'discount')::numeric, 'tax_amount', -coalesce((e->>'discount_tax')::numeric, 0));
        end if;
      end loop;
      v_orders := v_orders || jsonb_build_object('so_number', v_so.so_number, 'reference', v_so.ref, 'carrier', coalesce((select rc.name from public.ref_carrier rc where rc.id = nullif(v_o->>'_carrier_id', '')::uuid), case when (v_o->>'_carrier_touch')::boolean then null else v_so.carrier end),
                                                 'tracking', case when (v_o->>'_tracking_touch')::boolean then nullif(array_to_string(array(select jsonb_array_elements_text(v_o->'_tracking')), ', '), '') else v_so.tracking_number end,
                                                 'tax_rule', v_prev->'rule'->>'rule', 'order_discount_pct', v_so.order_discount_pct,
                                                 'ship_to', jsonb_build_object('company', v_so.ship_to_company, 'contact', v_so.ship_to_contact, 'phone', v_so.ship_to_phone, 'line1', v_so.ship_to_line1, 'line2', v_so.ship_to_line2,
                                                                               'city', v_so.ship_to_city, 'state_province', v_so.ship_to_state_province, 'postal_code', v_so.ship_to_postal_code, 'country', v_so.ship_to_country),
                                                 'lines', v_lines);
      v_lines_amt := v_lines_amt + (v_prev->'totals'->>'lines_amount')::numeric;  v_od_amt := v_od_amt + v_o_od;
      v_chg_amt := v_chg_amt + (v_prev->'totals'->>'charges_amount')::numeric;  v_chd_amt := v_chd_amt + coalesce((v_prev->'totals'->>'charges_discount_amount')::numeric, 0);
      v_sc_amt := v_sc_amt + coalesce((v_prev->'totals'->>'surcharge_amount')::numeric, 0);  v_tax := v_tax + (v_prev->'totals'->>'tax')::numeric;
      if v_rule_id is distinct from v_so.tax_rule_id then v_warn := array_append(v_warn, 'draft_rule_changed:' || v_so.so_number); end if;
    end loop;
    v_total := v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt + v_tax;
    v_plan := public.so_invoice_apply_plan(v_first.bill_to_customer_id, v_first.currency_id, v_ids, v_total);
    select coalesce(jsonb_agg(jsonb_build_object('reference', s->'reference', 'paid_on', s->'paid_on', 'method', s->>'method', 'amount', (s->>'amount')::numeric) order by (s->>'paid_on')::date, (s->>'created_at')::timestamptz, ord), '[]'::jsonb)
      into v_pay from jsonb_array_elements(v_plan->'steps') with ordinality t(s, ord) where s->>'step' in ('auto_deposit', 'auto_balance');
    v_docs := v_docs || jsonb_build_object(
      'group', v_g->>'group', 'so_ids', to_jsonb(v_ids),
      'header', jsonb_build_object('number', null, 'issued_on', v_on, 'due_on', case when v_pt.net_days is not null then v_on + v_pt.net_days end, 'payment_term_name', coalesce(v_pt.name, v_first.payment_term_name),
                                   'currency_code', v_first.currency_code, 'memo', '', 'bill_to_customer_id', v_first.bill_to_customer_id,
                                   'bill_to', jsonb_build_object('name', v_first.bill_to_name, 'line1', v_first.bill_to_line1, 'line2', v_first.bill_to_line2, 'city', v_first.bill_to_city, 'state_province', v_first.bill_to_state_province, 'postal_code', v_first.bill_to_postal_code, 'country', v_first.bill_to_country)),
      'orders', v_orders, 'charges', v_charges, 'payments', v_pay,
      'totals', jsonb_build_object('order_discount', v_od_amt, 'surcharge', v_sc_amt, 'taxable', v_lines_amt + v_od_amt + v_chg_amt - v_chd_amt + v_sc_amt, 'tax', v_tax, 'total', v_total,
                                   'deposit_applied', (v_plan->>'deposit')::numeric, 'credit_applied', (v_plan->>'credit')::numeric, 'balance_forward', -((v_plan->>'credit')::numeric + (v_plan->>'balance')::numeric),
                                   'paid', (v_plan->>'deposit')::numeric + (v_plan->>'balance')::numeric, 'amount_due', v_total - (v_plan->>'deposit')::numeric - (v_plan->>'credit')::numeric - (v_plan->>'balance')::numeric),
      'plan', v_plan, 'warnings', to_jsonb(v_warn), 'calc_at', now());
  end loop;
  return jsonb_build_object('issued_on', v_on, 'shipped_on', v_pf->>'shipped_on', 'docs', v_docs, 'finalize_warnings', v_pf->'warnings', 'put_back', v_pf->'put_back');
end;
$function$;

-- ═══ 재발행 8/8 — so_detail(DB prosrc 원본 md5 e56a3ce9 + 더한 줄) ═══
CREATE OR REPLACE FUNCTION public.so_detail(p_so_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_so       public.so%rowtype;
  v_cust     text;
  v_lines    jsonb;
  v_charges  jsonb;
  v_lines_n  int;  v_no_price int;  v_free int;  v_charges_n int;  v_deal_ended int;
  v_lines_total numeric;  v_charges_total numeric;  v_od_amt numeric;
  v_sc_amt numeric := 0;  v_sc_tax numeric := 0;                            -- surcharge-2a — so_tax_preview totals 에서 읽는다(식 한 곳 · basis 를 따라간다)
  v_chd    numeric := 0;                                                     -- fr-1 판정 352: 운임 할인 합 — so_tax_preview totals 에서(식 한 곳)
  v_warn     text[];
  v_tax      jsonb;  v_tw text[];                              -- 세금 ② — so_tax_preview
  v_basis    text;  v_inv jsonb;  v_inv_hist jsonb;  v_removed int;  v_qty_removed numeric;   -- ⓐ2 — 보낸 수량 기준 · 인보이스 · 뺀 몫
  v_bal      jsonb;                                            -- ⓑ2 — 청구처 손님 잔액(그 통화 행)
  v_rule     record;  v_rule_j jsonb;                          -- dsc-3a 판정 311 — manual 인데 규칙 쪽이 더 크면 경고
  v_cp       jsonb;                                            -- dsc-3b 판정 329 — 붙은 쿠폰
begin
  select * into v_so from public.so where id = p_so_id;
  if not found then
    raise exception 'Order not found';
  end if;
  select c.name into v_cust from public.customer c where c.id = v_so.customer_id;

  select coalesce(jsonb_agg(to_jsonb(l) || jsonb_build_object('manual', public.so_line_manual(l), 'price_set_by_name', (select s.name from public.ims_staff s where s.id = l.price_set_by), 'total', public.so_line_total(l),   -- ln-1 판정 546(price_set_by · price_set_at 은 to_jsonb(l) 에)
                                                              'no_price', l.unit_price is null, 'free', l.free_reason is not null, 'shipped_total', round(l.qty_shipped * l.unit_price, 2), 'removed', l.qty_removed > 0,
                                                              'surcharge_unit', public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), 'surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_ordered), 'shipped_surcharge_total', public.so_line_surcharge_total(public.so_line_surcharge_unit(l.unit_price, l.surcharge_pct, l.surcharge_amount), l.qty_shipped),   -- surcharge-2a(묶음 1 · 2 · total · shipped_total 과 같은 수량)
                                                              'qty_credited', (select coalesce(sum(cl.qty_returned), 0) from public.so_credit_line cl join public.so_credit c on c.id = cl.credit_id where cl.so_line_id = l.id and c.status = 'issued'),   -- ⓒ2
                                                              'deal_ended', l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date),
                                                              'is_combo', exists (select 1 from public.so_line c where c.combo_line_id = l.id),                                                           -- asm-2a(묶음 2 · 5): 콤보 줄 · 구성품 줄(combo_line_id · combo_qty 는 to_jsonb(l) 에 있다)
                                                              'bgrade_bin', (select rb.name from public.ref_bin rb where rb.id = l.bgrade_bin_id), 'is_bgrade_line', l.bgrade_bin_id is not null,   -- bgr-1c 판정 634 · 635: POS · so 화면의 B-grade 표시
                                                              'combo_sku', (select c.sku from public.so_line c where c.id = l.combo_line_id), 'customer_note', (select sn.note from public.so_line_note sn where sn.so_line_id = l.id)) order by l.line_no), '[]'::jsonb),
         count(*) filter (where l.combo_line_id is null), count(*) filter (where l.unit_price is null), count(*) filter (where l.free_reason is not null), public.so_lines_total(p_so_id),   -- dsc-3a 판정 310: 기준 금액 식 한 곳
         count(*) filter (where l.deal_line_id is not null and public.so_deal_line_ended(l.deal_line_id, (l.created_at at time zone 'America/Toronto')::date)),
         count(*) filter (where l.qty_removed > 0), coalesce(sum(l.qty_removed), 0)
    into v_lines, v_lines_n, v_no_price, v_free, v_lines_total, v_deal_ended, v_removed, v_qty_removed
  from public.so_line l where l.so_id = p_so_id;

  select coalesce(jsonb_agg(to_jsonb(c) || jsonb_build_object('discount', public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount), 'net', c.amount - public.so_charge_discount(c.amount, c.discount_pct, c.discount_amount)) order by c.line_no), '[]'::jsonb), count(*), coalesce(sum(c.amount), 0)   -- fr-1: 할인액 · 순 운임(식 한 곳)
    into v_charges, v_charges_n, v_charges_total
  from public.so_charge c where c.so_id = p_so_id;

  -- 오더 전체 할인(D6) — 제품 줄 합계에 한 번 · round 2(SO-10842 실물) · 운임은 기준에 없다
  -- od-1 판정 542 ~ 544: 오더 할인 금액은 so_tax_preview 가 센 값(손으로 정한 줄을 뺀 바탕 · 식 한 곳) — 아래 v_tax 뒤에서 읽는다(ordered · shipped 둘 다)

  -- 세금(세금 ② · 판정 8) — 오더에 고른 규칙(manual|ship_to)으로 줄마다 · 규칙 없으면 tax null + 경고 tax_rule_missing
  v_basis := case when v_so.status in ('shipped', 'fulfilled') then 'shipped' else 'ordered' end;   -- ⓐ2: 나간 뒤에는 보낸 수량이 금액(뺀 몫·pick_short 제외 · 인보이스가 정본 8-c) · ⓑ2: invoiced 값 없음(판정 1)
  v_tax := public.so_tax_preview(p_so_id, null, null, v_basis);
  v_od_amt := -coalesce((v_tax->'totals'->>'order_discount_amount')::numeric, 0);                                                                       -- od-1: 양수(so_detail 의 모양) · 식은 so_tax_preview 한 곳
  v_sc_amt := coalesce((v_tax->'totals'->>'surcharge_amount')::numeric, 0);  v_sc_tax := coalesce((v_tax->'totals'->>'surcharge_tax')::numeric, 0);   -- surcharge-2a(묶음 3 · 4)
  v_chd := coalesce((v_tax->'totals'->>'charges_discount_amount')::numeric, 0);                                                                          -- fr-1 판정 352(세금은 v_tax 의 tax 가 이미 뺐다 · 354)
  if v_basis = 'shipped' then
    v_lines_total := (v_tax->'totals'->>'lines_amount')::numeric;
  end if;
  select jsonb_build_object('invoice_id', i.id, 'invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'due_on', i.due_on, 'total', i.total,
                            'deposit_applied', i.deposit_applied, 'credit_applied', i.credit_applied, 'balance_forward', i.balance_forward, 'amount_due', i.amount_due,
                            'remaining', public.so_invoice_remaining(i.id), 'paid', i.total - public.so_invoice_remaining(i.id),
                            'credits', (select coalesce(jsonb_agg(jsonb_build_object('credit_id', c.id, 'credit_number', c.credit_number, 'status', c.status, 'issued_on', c.issued_on, 'total', c.total) order by c.credit_number), '[]'::jsonb) from public.so_credit c where c.invoice_id = i.id),
                            'credited_total', (select coalesce(sum(c.total), 0) from public.so_credit c where c.invoice_id = i.id and c.status = 'issued')) into v_inv
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id and o.cancelled_at is null;
  select coalesce(jsonb_agg(jsonb_build_object('invoice_number', i.invoice_number, 'status', i.status, 'issued_on', i.issued_on, 'cancelled_at', i.cancelled_at) order by i.invoice_number), '[]'::jsonb) into v_inv_hist
  from public.so_invoice_order o join public.so_invoice i on i.id = o.invoice_id where o.so_id = p_so_id;
  select to_jsonb(b) into v_bal from public.so_customer_balance(coalesce(v_so.bill_to_customer_id, v_so.customer_id)) b where b.currency_id = v_so.currency_id;   -- ⓑ2: 청구처의 그 통화 잔액(받아 둔 돈 · 예약 · available · 미수)

  v_warn := public.so_tier_warnings(v_so);
  if v_so.tax_rule_id is null then v_warn := array_append(v_warn, 'tax_rule_missing'); end if;
  if v_removed > 0 then v_warn := array_append(v_warn, 'lines_removed'); end if;
  select array_agg(t.v) into v_tw from jsonb_array_elements_text(coalesce(v_tax->'warnings', '[]'::jsonb)) as t(v);
  v_warn := v_warn || coalesce(v_tw, '{}');
  if v_lines_n = 0    then v_warn := array_append(v_warn, 'no_lines'); end if;
  if v_no_price > 0   then v_warn := array_append(v_warn, 'lines_without_price'); end if;
  if v_deal_ended > 0 then v_warn := array_append(v_warn, 'deal_ended_before_line_added'); end if;
  if v_so.reprice_suggested_at is not null then v_warn := array_append(v_warn, 'reprice_suggested'); end if;
  if v_so.status = 'draft' and v_so.order_discount_source = 'manual' then                                          -- dsc-3a 판정 282 · 311: manual(0 포함)은 그대로 + 규칙 쪽이 더 크면 경고
    select * into v_rule from public.so_order_discount(p_so_id);
    if coalesce(v_rule.pct, 0) > coalesce(v_so.order_discount_pct, 0) then
      v_warn := array_append(v_warn, 'order_discount_rule_now_better');
      v_rule_j := jsonb_build_object('rule_pct', v_rule.pct, 'rule_deal_id', v_rule.deal_id, 'manual_pct', v_so.order_discount_pct);
    end if;
  end if;

  v_cp := public.so_coupon_info(v_so);
  if v_cp is not null and v_cp->>'status' <> 'won' then v_warn := array_append(v_warn, 'coupon_not_used'); end if;   -- dsc-3b 판정 329

  return jsonb_build_object(
    'so', to_jsonb(v_so),
    'customer_name', v_cust,
    'lines', v_lines,
    'charges', v_charges,
    'totals', jsonb_build_object('basis', v_basis, 'lines', v_lines_n, 'combo_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and exists (select 1 from public.so_line c where c.combo_line_id = x.id)),
                                 'component_lines', (select count(*) from public.so_line x where x.so_id = p_so_id and x.combo_line_id is not null), 'lines_removed', v_removed, 'qty_removed', v_qty_removed, 'lines_total', v_lines_total, 'lines_without_price', v_no_price, 'free_lines', v_free,
                                 'order_discount_pct', v_so.order_discount_pct, 'order_discount_source', v_so.order_discount_source, 'order_discount_deal_id', v_so.order_discount_deal_id,
                                 'order_discount_amount', v_od_amt, 'lines_after_discount', v_lines_total - v_od_amt, 'discount_basis_amount', coalesce((v_tax->'totals'->>'discount_basis_amount')::numeric, 0),   -- od-1
                                 'charges', v_charges_n, 'charges_total', v_charges_total,
                                 'charges_discount_amount', v_chd, 'charges_net_total', v_charges_total - v_chd,                            -- fr-1 판정 352: charges_total 은 정가 합 그대로 · 새 열쇠
                                 'surcharge_amount', v_sc_amt, 'surcharge_tax', v_sc_tax,                                        -- surcharge-2a — 물건값 · 오더 할인 기준 밖(묶음 3)
                                 'order_total', v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt,                                    -- fr-1: 운임 할인을 뺀다
                                 'tax_rule', v_so.tax_rule, 'tax_rule_source', v_tax->>'source', 'tax', v_tax->'totals'->'tax',
                                 'order_total_with_tax', case when v_tax->'totals'->>'tax' is null then null else v_lines_total - v_od_amt + v_charges_total - v_chd + v_sc_amt + (v_tax->'totals'->>'tax')::numeric end),   -- fr-1
    'tax', v_tax,
    'invoice', v_inv,
    'invoice_history', v_inv_hist,
    'customer_balance', v_bal,
    'order_discount_rule', v_rule_j,
    'coupon', v_cp,
    'warnings', to_jsonb(v_warn));
end;
$function$;

-- ═══ 표 — so_line_note(맨 뒤 · 머리 주석 「순서」) ═══
create table public.so_line_note (
  so_line_id  uuid primary key references public.so_line (id) on delete cascade,      -- 줄마다 하나 · 줄이 지워지면 함께(초안의 ✕ · Clear lines)
  note        text not null,
  created_at  timestamptz not null default now(),
  created_by  uuid references public.ims_staff (id),
  updated_at  timestamptz not null default now(),
  updated_by  uuid references public.ims_staff (id),
  constraint so_line_note_len_ck    check (char_length(note) between 1 and 500),
  constraint so_line_note_shape_ck  check (note !~ '^ | $|  |[\t\n\r\f\v]')                -- 한 줄 꼴(so_line_note_clean 이 만든 그대로)
);
comment on table public.so_line_note is '⭐ SO 손님용 줄 메모(so-line-note-1 · 판정 1151 「나」) — 줄마다 하나 · 손님 문서(SO · PROFORMA · INVOICE)의 줄 comment 로 찍힌다 · so_line 과 따로 둔 까닭: 메모를 써도 so_line.updated_at 이 안 바뀌어 판정 434(Shopify 취소 자동 처리) · so_unconfirm 판단이 그대로다 · 사내 메모는 so_line.comments(문서에 안 나온다) · 쓰기는 창구 so_line_note_set(안쪽 so_line_note_put)로만';
create trigger so_line_note_touch before update on public.so_line_note for each row execute function public.ims_touch();
alter table public.so_line_note enable row level security;
create policy so_line_note_select on public.so_line_note for select to authenticated using (true);
revoke all on public.so_line_note from public, anon, authenticated;
grant select on public.so_line_note to authenticated;

-- ═══ comment — 재발행 여덟은 옛 글 뒤에 덧(한 번만) ═══
do $$
declare r record;
begin
  for r in select * from (values
    ('public.so_split(uuid, text, jsonb, text, uuid)', '일부만 나눈 줄의 손님 메모(so_line_note)를 형제의 새 줄에 복사'),
    ('public.so_merge(uuid[], boolean)', '합친 줄의 손님 메모 = 원본 메모를 오더 순서대로 「 / 」 로 이음 · 줄 계획 note · 500 자 넘으면 경고 line_note_too_long · 실행 거부'),
    ('public.so_unconfirm(uuid)', '도로 합치는 형제 줄의 손님 메모를 원래 줄로(비었으면 옮김 · 다르면 「 / 」 로 이음)'),
    ('public.so_lines_paste(uuid, jsonb, boolean)', '줄마다 손님 메모(열쇠 note · 선택 · bad_note · note_not_saved)'),
    ('public.doc_data_so(uuid, jsonb)', '줄 comment 의 원천 = so_line_note.note(사내 so_line.comments 는 문서에 안 나온다)'),
    ('public.doc_data_invoice(text, uuid, jsonb)', '줄 comment 의 원천 = so_line_note.note(사내 so_line.comments 는 문서에 안 나온다)'),
    ('public.so_invoice_preview(jsonb, date)', '줄 comment 의 원천 = so_line_note.note(사내 so_line.comments 는 문서에 안 나온다)'),
    ('public.so_detail(uuid)', '줄 객체에 customer_note(손님 메모 · 없으면 null · 사내 메모는 comments 그대로)')
  ) t(sig, tag) loop
    if coalesce(obj_description(r.sig::regprocedure, 'pg_proc'), '') !~ 'so-line-note-1' then
      execute format('comment on function %s is %L', r.sig::regprocedure, coalesce(obj_description(r.sig::regprocedure, 'pg_proc') || ' · ', '') || '[so-line-note-1 2026-11-10 · 판정 1151] ' || r.tag);
    end if;
  end loop;
end $$;

-- ═══ 착지 검사 ═══
do $$
declare v_bad text := '';
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_split(uuid, text, jsonb, text, uuid)'::regprocedure) <> '50810923de2154cb89f3c2ae36b369a7' then v_bad := v_bad || ' so_split_md5'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_merge(uuid[], boolean)'::regprocedure) <> '7ceff318ad7f987bbaa68128bdad8e0c' then v_bad := v_bad || ' so_merge_md5'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_unconfirm(uuid)'::regprocedure) <> 'd40e1a881471843c3b969df56df1de5a' then v_bad := v_bad || ' so_unconfirm_md5'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_lines_paste(uuid, jsonb, boolean)'::regprocedure) <> '33df450f16926dc4338305bac6043afc' then v_bad := v_bad || ' so_lines_paste_md5'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure) <> '9615ef74cba9a8cb27a9491cc638bd19' then v_bad := v_bad || ' doc_data_so_md5'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure) <> 'cc658f428dda04b61798e69b0bf75a90' then v_bad := v_bad || ' doc_data_invoice_md5'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_invoice_preview(jsonb, date)'::regprocedure) <> '92d56249b202b261eab513f3896f8e3f' then v_bad := v_bad || ' so_invoice_preview_md5'; end if;
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'public.so_detail(uuid)'::regprocedure) <> '3f70f44258a647a2af9a4477847bf925' then v_bad := v_bad || ' so_detail_md5'; end if;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_split', 'so_merge', 'so_unconfirm', 'so_lines_paste', 'doc_data_so', 'doc_data_invoice', 'so_invoice_preview', 'so_detail', 'so_line_note_clean', 'so_line_note_join', 'so_line_note_put', 'so_line_note_set')) <> 12 then v_bad := v_bad || ' fn_count'; end if;
  -- 권한 · 머리 그대로(acl 은 create or replace 가 지킨다)
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.so_split(uuid, text, jsonb, text, uuid)'::regprocedure), '-') <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' split_acl'; end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.doc_data_so(uuid, jsonb)'::regprocedure), '-') <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' docso_acl'; end if;
  if coalesce((select p.proacl::text from pg_proc p where p.oid = 'public.doc_data_invoice(text, uuid, jsonb)'::regprocedure), '-') <> '{postgres=X/postgres,service_role=X/postgres}' then v_bad := v_bad || ' docinv_acl'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_merge', 'so_unconfirm', 'so_lines_paste', 'so_invoice_preview', 'so_detail', 'so_line_note_set')
             and coalesce(p.proacl::text, '-') <> '{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}') then v_bad := v_bad || ' window_acl'; end if;
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('so_line_note_clean', 'so_line_note_join', 'so_line_note_put')
             and coalesce(p.proacl::text, '-') <> '{postgres=X/postgres,service_role=X/postgres}') then v_bad := v_bad || ' inner_acl'; end if;
  if (select string_agg(p.proname || ':' || p.prosecdef::text || p.provolatile::text, ' ' order by p.proname) from pg_proc p where p.pronamespace = 'public'::regnamespace
        and p.proname in ('so_split', 'so_merge', 'so_unconfirm', 'so_lines_paste', 'doc_data_so', 'doc_data_invoice', 'so_invoice_preview', 'so_detail', 'so_line_note_clean', 'so_line_note_join', 'so_line_note_put', 'so_line_note_set'))
     <> 'doc_data_invoice:falses doc_data_so:falses so_detail:falses so_invoice_preview:falsev so_line_note_clean:falsei so_line_note_join:falsei so_line_note_put:falsev so_line_note_set:truev so_lines_paste:truev so_merge:truev so_split:falsev so_unconfirm:truev' then v_bad := v_bad || ' fn_head'; end if;
  -- 표: RLS 켜짐 · 읽기 정책 하나 · authenticated 는 SELECT 만 · anon 없음
  if not (select c.relrowsecurity from pg_class c where c.oid = 'public.so_line_note'::regclass) then v_bad := v_bad || ' rls_off'; end if;
  if (select count(*) from pg_policy pol where pol.polrelid = 'public.so_line_note'::regclass) <> 1 then v_bad := v_bad || ' policy_count'; end if;
  if not has_table_privilege('authenticated', 'public.so_line_note', 'select') or has_table_privilege('authenticated', 'public.so_line_note', 'insert') or has_table_privilege('authenticated', 'public.so_line_note', 'update')
     or has_table_privilege('authenticated', 'public.so_line_note', 'delete') or has_table_privilege('anon', 'public.so_line_note', 'select') then v_bad := v_bad || ' table_grant'; end if;
  -- 값 한 번: 굳히기 · 잇기
  if public.so_line_note_clean(E'  a \n\t b  ') is distinct from 'a b' or public.so_line_note_clean(E' \n ') is not null or public.so_line_note_clean(null) is not null then v_bad := v_bad || ' clean_val'; end if;
  if public.so_line_note_join(array['b', null, 'a', 'b']) is distinct from 'b / a' or public.so_line_note_join(array[null::text]) is not null or public.so_line_note_join('{}') is not null then v_bad := v_bad || ' join_val'; end if;
  -- 문서 셋에 사내 칸이 남지 않았다
  if exists (select 1 from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('doc_data_so', 'doc_data_invoice', 'so_invoice_preview') and (p.prosrc ~ 'sl\.comments' or p.prosrc !~ 'so_line_note')) then v_bad := v_bad || ' doc_source'; end if;
  if v_bad <> '' then raise exception 'so-line-note-1 landing check failed:%', v_bad; end if;
end $$;
