-- supabase/tests/chg_fix_1_check.sql — chg-fix-1 검증 (2026-11-09 · 판정 1135 · asung-workflow §4 「시험 적용 장치」)
-- [운영 메인 · Asung-IMS] begin → (-v mig 면 \i) → 가짜 공급처 · 직원 · 청구서 여섯 · 레이어 하나 · landed 둘(DO 하나) → 집계 → rollback
--   Claude Code(시험 · 레포 루트): PGCONNECT_TIMEOUT=10 psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -v mig=supabase/migrations/20261109223500_chg_fix_1_po_charge_kind_lock.sql -f supabase/tests/chg_fix_1_check.sql
--   Caleb(확인 · 적용 뒤): 같은 명령에서 -v mig 만 뺀다 — 기대 OK 수는 EXPECT_OK(두 갈래 같다 · S0 한 검사만 갈래마다 다르게 본다)
--   ⚠️ 가짜 행만(ZZCHG1) — 실제 청구서는 읽기만(17038 은 md5 로 앞 · 안 · 뒤 대조) · 창구는 tf_charge_update 하나만 부른다(po_charge_confirm · po_doc_* · qbo_* 무접촉 — INSERT 는 status 트리거를 안 돌린다)
--   ⚠️ identity 는 max + 1 을 직접 넣는다(overriding system value) — 시퀀스를 당기지 않는다
\set ON_ERROR_STOP on
\pset pager off
\set EXPECT_OK 17

create temp table t_res (n serial, label text, got text, want text, ok boolean);
create function pg_temp.chk(p_label text, p_got text, p_want text) returns void language plpgsql as $$
begin
  insert into t_res (label, got, want, ok) values (p_label, p_got, p_want, p_got is not distinct from p_want);
end $$;

-- ── 기준(begin 앞 · 읽기만) ──
select (select md5(row_to_json(c)::text) from public.po_charge c where c.id = 'ef772208-b271-4ff3-bf4b-09e024f4ec89') as pre_17038,
       (select count(*) from public.po_charge) as pre_chg, (select count(*) from public.supplier) as pre_sup, (select count(*) from public.ims_staff) as pre_staff,
       (select count(*) from public.inv_layer) as pre_layer, (select count(*) from public.inv_layer_cost_add) as pre_adds,
       (select count(*) from pg_trigger where tgrelid = 'public.po_charge'::regclass and tgname = 'po_charge_kind_lock') as pre_trg,
       clock_timestamp() as t_begin \gset

begin;
set local lock_timeout = '3s';
\if :{?mig}
\echo '── 시험 적용(rollback 됨):' :mig
\i :mig
\endif
select clock_timestamp() as t_after_mig \gset

\if :{?mig}
select pg_temp.chk('S0(시험 갈래) begin 앞에는 트리거가 없었다', :'pre_trg', '0');
\else
select pg_temp.chk('S0(확인 갈래) begin 앞에 트리거가 이미 있다', :'pre_trg', '1');
\endif

-- ── 1 ~ 7: 가짜 행 + 검사(DO 하나 — 왕복 한 번) ──
do $$
declare
  c_confirmed constant text := 'Kind can only be changed on a draft charge — Reopen it, change Kind, then confirm again — nothing was saved';
  c_cancelled constant text := 'This charge is cancelled — Restore it first, then change Kind — nothing was saved';
  c_landed    constant text := 'This charge is already on stock cost (1 layer row(s)) — Kind cannot be changed; to correct it, enter an offsetting charge — nothing was saved';
  v_cad uuid := (select id from public.ref_currency where code = 'CAD');
  v_sup uuid; v_staff uuid; v_uid uuid := gen_random_uuid();
  v_draft uuid; v_conf uuid; v_canc uuid; v_dland uuid; v_cland uuid; v_tf uuid;
  v_lid bigint := (select coalesce(max(id), 0) + 1 from public.inv_layer); v_aid bigint := (select coalesce(max(id), 0) + 1 from public.inv_layer_cost_add);
  v_msg text; v_n int; v_txt text; v_out text := ''; v_j jsonb;
begin
  insert into public.supplier (name, payment_term_name, account_payable_code) values ('ZZCHG1 Fake Supplier', 'Net 30', '2000') returning id into v_sup;
  insert into public.ims_staff (auth_user_id, email, name, role, perms, warehouse_access) values (v_uid, 'zzchg1-buyer@test.invalid', 'ZZCHG1 Buyer', 'manager', '["purchasing","transfer"]', '{}') returning id into v_staff;
  insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount) values (v_sup, 'ZZCHG1-DRAFT', public.ims_today() - 30, 'freight', v_cad, 10) returning id into v_draft;
  insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status, confirmed_by, confirmed_at) values (v_sup, 'ZZCHG1-CONF', public.ims_today() - 30, 'freight', v_cad, 10, 'confirmed', v_staff, now()) returning id into v_conf;
  insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status, cancelled_by, cancelled_at) values (v_sup, 'ZZCHG1-CANC', public.ims_today() - 30, 'freight', v_cad, 10, 'cancelled', v_staff, now()) returning id into v_canc;
  insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount) values (v_sup, 'ZZCHG1-DLAND', public.ims_today() - 30, 'freight', v_cad, 10) returning id into v_dland;
  insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount, status, confirmed_by, confirmed_at) values (v_sup, 'ZZCHG1-CLAND', public.ims_today() - 30, 'freight', v_cad, 10, 'confirmed', v_staff, now()) returning id into v_cland;
  insert into public.po_charge (supplier_id, charge_number, charge_date, kind, currency_id, total_amount) values (v_sup, 'ZZCHG1-TF', public.ims_today() - 30, 'freight', v_cad, 10) returning id into v_tf;
  insert into public.inv_layer (id, sku, warehouse, origin_type, doc_number, line_ref, received_on, age_known, qty, unit_cost, cost_source) overriding system value
    values (v_lid, 'ZZCHG1-SKU', 'ZZCHG1', 'purchase', 'ZZCHG1-PO', 'ZZCHG1-line', public.ims_today() - 30, true, 1, 1, 'manual');
  insert into public.inv_layer_cost_add (id, layer_id, kind, amount, occurred_on, doc_number, line_ref) overriding system value
    values (v_aid, v_lid, 'landed', 1, public.ims_today() - 30, 'ZZCHG1-DLAND', 'ZZCHG1-a1'), (v_aid + 1, v_lid, 'landed', 1, public.ims_today() - 30, 'ZZCHG1-CLAND', 'ZZCHG1-a2');

  -- 1 · 2 draft
  update public.po_charge set kind = 'brokerage' where id = v_draft;
  perform pg_temp.chk('1 draft freight → brokerage 통과 · 값 바뀜', (select kind from public.po_charge where id = v_draft), 'brokerage');
  update public.po_charge set kind = 'brokerage' where id = v_draft;
  get diagnostics v_n = row_count;
  perform pg_temp.chk('2 draft 같은 값 brokerage → brokerage 통과(1 행)', v_n::text || ' ' || (select kind from public.po_charge where id = v_draft), '1 brokerage');

  -- 3 confirmed
  v_msg := 'no error'; begin update public.po_charge set kind = 'duty' where id = v_conf; exception when others then v_msg := sqlstate || ' ' || sqlerrm; end;
  perform pg_temp.chk('3a confirmed → 거부 · P0001 · 문구 일치 · 값 그대로', v_msg || ' / ' || (select kind from public.po_charge where id = v_conf), 'P0001 ' || c_confirmed || ' / freight');
  update public.po_charge set note = 'ZZCHG1 note', kind = 'freight' where id = v_conf;
  perform pg_temp.chk('3b confirmed 의 다른 칸(note) + 같은 kind update 는 통과', (select note || ' ' || kind || ' ' || status from public.po_charge where id = v_conf), 'ZZCHG1 note freight confirmed');
  v_msg := 'no error'; begin update public.po_charge set status = 'draft', kind = 'duty' where id = v_conf; exception when others then v_msg := sqlerrm; end;
  perform pg_temp.chk('3c confirmed 를 한 문장에서 draft 로 돌리며 kind 바꾸기 → 거부(old 기준)', v_msg || ' / ' || (select status || ' ' || kind from public.po_charge where id = v_conf), c_confirmed || ' / confirmed freight');

  -- 4 cancelled
  v_msg := 'no error'; begin update public.po_charge set kind = 'duty' where id = v_canc; exception when others then v_msg := sqlstate || ' ' || sqlerrm; end;
  perform pg_temp.chk('4 cancelled → 거부 · 문구 일치', v_msg || ' / ' || (select kind from public.po_charge where id = v_canc), 'P0001 ' || c_cancelled || ' / freight');

  -- 5 landed
  v_msg := 'no error'; begin update public.po_charge set kind = 'duty' where id = v_dland; exception when others then v_msg := sqlstate || ' ' || sqlerrm; end;
  perform pg_temp.chk('5a draft + landed → 거부 · 문구 일치', v_msg || ' / ' || (select kind from public.po_charge where id = v_dland), 'P0001 ' || c_landed || ' / freight');
  v_msg := 'no error'; begin update public.po_charge set kind = 'duty' where id = v_cland; exception when others then v_msg := sqlerrm; end;
  perform pg_temp.chk('5b confirmed + landed → 상쇄 청구서 문구(Reopen 으로 보내지 않는다)', v_msg, c_landed);
  v_msg := 'no error'; begin update public.po_charge set kind = 'duty', charge_number = 'ZZCHG1-RENAMED' where id = v_dland; exception when others then v_msg := sqlerrm; end;
  perform pg_temp.chk('5c 같은 문장에서 번호를 바꿔도 old 번호로 landed 를 본다', v_msg, c_landed);

  -- 6 · 7 가짜 직원(authenticated · purchasing + transfer · 원가 열쇠 없음) — 결과는 변수로 받아 reset role 뒤에 적는다
  perform set_config('request.jwt.claims', jsonb_build_object('sub', v_uid, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
  v_out := v_out || 'can_write ' || public.ims_can_write('purchasing')::text || ' · cost ' || public.ims_can_view_cost()::text
                 || ' · landed seen ' || (select count(*) from public.inv_layer_cost_add ca where ca.doc_number like 'ZZCHG1-%')::text;
  begin update public.po_charge set kind = 'duty' where id = v_draft; get diagnostics v_n = row_count; v_out := v_out || ' | 7-1 rows ' || v_n::text || ' ' || (select kind from public.po_charge where id = v_draft);
  exception when others then v_out := v_out || ' | 7-1 ERR ' || sqlerrm; end;
  begin update public.po_charge set kind = 'duty' where id = v_conf; v_out := v_out || ' | 7-3 no error';
  exception when others then v_out := v_out || ' | 7-3 ' || sqlstate || ' ' || sqlerrm; end;
  begin update public.po_charge set kind = 'duty' where id = v_dland; v_out := v_out || ' | 7-5 no error';
  exception when others then v_out := v_out || ' | 7-5 ' || sqlerrm; end;
  begin update public.po_charge set note = 'ZZCHG1 staff note' where id = v_conf; get diagnostics v_n = row_count; v_out := v_out || ' | 7-note rows ' || v_n::text;
  exception when others then v_out := v_out || ' | 7-note ERR ' || sqlerrm; end;
  begin v_j := public.tf_charge_update(v_tf, jsonb_build_object('kind', 'brokerage')); v_txt := (v_j ->> 'kind') || ' ' || (v_j ->> 'status');
  exception when others then v_txt := 'ERR ' || sqlerrm; end;
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
  perform pg_temp.chk('7 가짜 직원(원가 열쇠 없음 · landed 0 행으로 보임)으로 REST 꼴 update: draft 통과 · confirmed 거부 · draft + landed 거부(definer) · note 통과',
    v_out, 'can_write true · cost false · landed seen 0 | 7-1 rows 1 duty | 7-3 P0001 ' || c_confirmed || ' | 7-5 ' || c_landed || ' | 7-note rows 1');
  perform pg_temp.chk('6 tf_charge_update 로 draft 트랜스퍼 운임 kind 바꾸기 → 통과(회귀)', v_txt || ' ' || (select kind from public.po_charge where id = v_tf), 'brokerage draft brokerage');
end $$;

-- ── 8 · G(정적) ──
select pg_temp.chk('8 17038 행이 begin 앞과 같다(md5 · 읽기만)', (select md5(row_to_json(c)::text) from public.po_charge c where c.id = 'ef772208-b271-4ff3-bf4b-09e024f4ec89'), :'pre_17038');
select pg_temp.chk('G1 트리거 정의 · 켜짐', (select pg_get_triggerdef(t.oid) || ' ' || t.tgenabled::text from pg_trigger t where t.tgrelid = 'public.po_charge'::regclass and t.tgname = 'po_charge_kind_lock'),
  'CREATE TRIGGER po_charge_kind_lock BEFORE UPDATE OF kind ON public.po_charge FOR EACH ROW EXECUTE FUNCTION po_charge_kind_lock() O');
select pg_temp.chk('G2 함수 하나 · definer · search_path · ACL(postgres 만)', (select count(*)::text || ' ' || bool_and(p.prosecdef)::text || ' ' || min(p.proconfig::text) || ' ' || min(p.proacl::text) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_charge_kind_lock'),
  '1 true {"search_path=public, pg_temp"} {postgres=X/postgres}');
select pg_temp.chk('G3 REST 겹 ① 새 함수 몸에 update · delete · insert · truncate 없음(주석 뺀 몸)',
  (select count(*)::text from regexp_matches(regexp_replace((select p.prosrc from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname = 'po_charge_kind_lock'), '--[^\n]*', '', 'g'), '\m(update|delete|insert|truncate)\M', 'gi')), '0');
select pg_temp.chk('G4 기존 트리거 넷 그대로 · 가짜 행 수(청구서 +6 · 공급처 +1 · 직원 +1 · 레이어 +1 · 얹기 +2)',
  (select string_agg(tgname, ',' order by tgname) from pg_trigger where tgrelid = 'public.po_charge'::regclass and not tgisinternal and tgname <> 'po_charge_kind_lock')
  || ' ' || ((select count(*) from public.po_charge) - :pre_chg)::text || ' ' || ((select count(*) from public.supplier) - :pre_sup)::text || ' ' || ((select count(*) from public.ims_staff) - :pre_staff)::text
  || ' ' || ((select count(*) from public.inv_layer) - :pre_layer)::text || ' ' || ((select count(*) from public.inv_layer_cost_add) - :pre_adds)::text,
  'po_charge_drive_shortcut,po_charge_qbo_job,po_charge_tax_rule_pair,po_charge_touch 6 1 1 1 2');

-- ── Z(rollback 앞) ──
\echo '── 결과(가짜 행은 rollback) ──'
select case when ok then 'OK   ' else 'FAIL ' end || label || case when ok then '' else format(' — got %s · want %s', coalesce(got, '(null)'), coalesce(want, '(null)')) end as line from t_res order by n;
select count(*) filter (where ok) as ok, count(*) filter (where not ok) as fail, count(*) as total, :EXPECT_OK as expect_ok,
       round(extract(epoch from clock_timestamp() - :'t_begin'::timestamptz)::numeric, 2) as begin_to_rollback_s, round(extract(epoch from clock_timestamp() - :'t_after_mig'::timestamptz)::numeric, 2) as after_mig_to_rollback_s from t_res;
rollback;
select (select md5(row_to_json(c)::text) from public.po_charge c where c.id = 'ef772208-b271-4ff3-bf4b-09e024f4ec89') = :'pre_17038'
   and (select count(*) from public.po_charge) = :pre_chg and (select count(*) from public.supplier) = :pre_sup and (select count(*) from public.ims_staff) = :pre_staff
   and (select count(*) from public.inv_layer) = :pre_layer and (select count(*) from public.inv_layer_cost_add) = :pre_adds
   and (select count(*) from pg_trigger where tgrelid = 'public.po_charge'::regclass and tgname = 'po_charge_kind_lock') = :pre_trg as rolled_back_clean;
