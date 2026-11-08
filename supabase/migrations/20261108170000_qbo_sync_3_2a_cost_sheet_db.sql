-- supabase/migrations/20261108170000_qbo_sync_3_2a_cost_sheet_db.sql — qbo-sync-3-2a: 하루 원가 장 DB 앞 절반 (2026-11-08 밤 · 지시서 ~/asung/prompts/qbo-sync-3-2.md · 이견 1 ~ 16 답 전부 받음 · 정본 qbo-integration §15-h · so-module §105-a · 판정 1082 ~ 1085 · 1087 · 1090 · 1092 ~ 1103)
-- 3-2a = 표 셋 · inv_config 키 셋 · 상수 넷 · 기대값(22 칸) · 장 셈(차액) · 장 만들기(장 행만 · 일감은 3-2b) · 만들기 due(cron 몸) · 미리 보기 · 장 목록 · 보류 결정 · 월 검산 · grant
-- 3-2b(다음) = qbo_job kind cost_day · 몸(JE JSON) · claim / done / fail / unknown / retry 가지 · 차례(wait_job) · 재생성 hold · release · resolve(1101)
-- ⚠️ 번호: 다른 창의 mcp-conc-1 이 20261108160000 을 쓴다(먼저 적용) — 이 파일은 그 뒤 · 만들 때 schema_migrations 마지막 = 20261108150000(160000 미적용) 실측
--
-- 설계 요지(정본 §15-h ① ~ ⑦ + 이견 답):
--   · 경계 = 출처(inv_ledger.source = 'ims' 문서 + IMS 비용 문서 po_charge.charge_number) ∧ 날짜 바닥 qbo_cost_since(2026-10-31) − 제외(살린 트럭 TR-06396 ~ 06399 문서 전체 두 다리 · opening_fix 가족 line_ref 'adj:<inv_cost_adjust.id>' kind opening_fix) — 이견 2
--   · 트랜스퍼는 소진 줄로만(출발 = 보낸 창고 레이어 소진 · 도착 = IN_TRANSIT 레이어 소진 → 받는 창고) · 트랜스퍼 복사 carried 는 세지 않는다(③) · cost_moved 는 「자식 레이어 창고 계정 ↔ 제 계정」(같으면 0)
--   · 열쇠마다 **부호 있는 한 짝**(acct_a < acct_b 코드 순 · 양수 = 차 a / 대 b) — restock(+)과 취소 reversal(−)이 같은 CR 열쇠에서 상계(이견 7) · 음수면 차대 뒤집음이 저절로
--   · 센트 = 열쇠 · 짝마다 round(합, 2) × 100 · 0 은 버림 · 줄 = 「그 창고 #59 만 장마다 순액 한 줄 · 그 밖 계정 줄은 전부 열쇠 줄」(1097 · 이견 8) · Entity 는 열쇠가 아니다(1103 · 이견 15 · 인보이스 손님 = so_invoice_order.customer_id · CR = coalesce(store_customer_id, customer_id))
--   · 보낸 몫(1092) = qbo_cost_sent(장 · 창고 · 열쇠 종류 · 열쇠 · 짝 · 센트 · 원가 줄 id 없음) · 다음 장 = 기대(≤ D) − Σ보낸(sent · sending · unknown 장) · 앞에 아직 안 보낸 장 P 가 있으면 기대(≤ D) − 기대(≤ P)(만들 때 셈 · 이견 9)
--   · 보류(1096 입고 GINR · price_adjust · settlement_discount · 1099 문턱 조정) · 막음(lost 512 · 모르는 칸 · 창고 모름) · 제외(opening_fix · 살린 트럭) — 상태 넷 send · hold · block · excluded · block 이 하나라도 있으면 장을 만들지 않고 예외(문서 번호 · 칸을 글에 · 이견 16)
--   · 문턱 조정의 「보냄 / 안 보냄」 = qbo_cost_hold(이견 6) · 입고 · 원가 조정 보류는 결정을 받지 않는다(Bill · BillPayment 차수가 연다)
--   · 재생성 세대(1093 · ⬜1) = min(inv_layer_consume.id) 를 장에 적는다(inv_layer_apply 가 소진 표를 전부 지우고 다시 넣으므로 반드시 커진다 · 비교 · hold · release 는 3-2b)
--   · cron = 만들기만(⬜2) — supabase/ops/cron.sql 의 ims-qbo-cost-build(0 8 * * * UTC · select public.qbo_cost_sheet_build_due()) · 등록은 적용 뒤 Caleb · 보내기 cron 은 3-3 뒤 · 스위치 qbo_send_cost_enabled 는 키만(off)
--   · 새 표는 RLS + grant 0(창구만 · 선례 qbo_opening_review) · PK uuid(시퀀스 없음 · 이견 10) · 거래 표 FK 0(sent → sheet 만 cascade)
-- 하지 않는 것: qbo_job · qbo_txn 제약 · 몸 · claim · EF · QBO 호출 · 화면 · cron 등록 · inv_layer 계열 무접촉(인덱스도 안 더한다 — occurred_on 필터는 seq scan 85k 행 · 호출당 0.1 s 안쪽 실측)
-- ⚠️ 공개 레포 — 손님 · 공급처 상호 없음(문서 번호 · 금액 · 수만) · UI 글자는 영어
-- 검증 supabase/tests/qbo_sync_3_2a_check.sql(운영 메인 begin → rollback · 126,715.43 · 264 SO · 장 12 · 열쇠 56 · 1 센트 차액 · 1094 · 1096 · 1099 · 1103 · 살린 트럭 · opening_fix · 차례 P · 월 검산 · WHERE 정적 · 572) · 적용은 Caleb(psql -1 -f · migration repair) · supabase db push 금지
-- ⚠️ jsonb_build_object 안에 「--」 줄 주석을 두지 마라(so-detail-keys-1) — 이 파일의 주석은 문장 끝 · 제 줄에만

-- ═══════════════ ⓪ 바탕 확인 — 22 칸이 그대로인가 · 계정 여덟 · 새 표 · 새 키가 없는가 ═══════════════
do $$
declare v_bad text := ''; v_def text; v_list text[];
begin
  select pg_get_constraintdef(oid) into v_def from pg_constraint where conrelid = 'public.inv_layer'::regclass and conname = 'inv_layer_origin_ck';
  select array_agg(m[1] order by m[1]) into v_list from regexp_matches(coalesce(v_def, ''), '''([a-z_]+)''', 'g') m;
  if v_list is distinct from array['adjust_existing', 'adjust_new', 'assembly', 'baseline', 'creditnote', 'purchase', 'sale_shortfall', 'transfer'] then v_bad := v_bad || format(' · inv_layer origin 8 ≠ %s', v_list); end if;
  select pg_get_constraintdef(oid) into v_def from pg_constraint where conrelid = 'public.inv_layer_consume'::regclass and conname = 'inv_layer_consume_reason_ck';
  select array_agg(m[1] order by m[1]) into v_list from regexp_matches(coalesce(v_def, ''), '''([a-z_]+)''', 'g') m;
  if v_list is distinct from array['adjust_out', 'assembly_in', 'cost_late', 'cost_moved', 'lost', 'reversal', 'sale', 'transfer'] then v_bad := v_bad || format(' · inv_layer_consume reason 8 ≠ %s', v_list); end if;
  select pg_get_constraintdef(oid) into v_def from pg_constraint where conrelid = 'public.inv_layer_cost_add'::regclass and conname = 'inv_layer_cost_add_kind_ck';
  select array_agg(m[1] order by m[1]) into v_list from regexp_matches(coalesce(v_def, ''), '''([a-z_]+)''', 'g') m;
  if v_list is distinct from array['carried', 'landed', 'opening_fix', 'price_adjust', 'settlement_discount', 'transfer_freight'] then v_bad := v_bad || format(' · inv_layer_cost_add kind 6 ≠ %s', v_list); end if;
  if (select count(*) from public.ref_account where code in ('_58_', '_59_', '_1150040007_', '_1150040010_', '_1150040012_', '_134_', '_135_', '_136_') and is_active) <> 8 then v_bad := v_bad || ' · 계정 여덟(_58_ _59_ _1150040007_ _1150040010_ _1150040012_ _134_ _135_ _136_)이 활성으로 다 있지 않다'; end if;
  if (select count(*) from public.ref_warehouse where name in ('Asung Trading Inc.', 'Asung - Edmonton') and is_active) <> 2 then v_bad := v_bad || ' · 창고 둘(Asung Trading Inc. · Asung - Edmonton)이 활성으로 없다'; end if;
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name in ('qbo_cost_sheet', 'qbo_cost_sent', 'qbo_cost_hold')) then v_bad := v_bad || ' · 새 표가 이미 있다'; end if;
  if exists (select 1 from public.inv_config where key in ('qbo_send_cost_enabled', 'qbo_cost_adjust_hold_over', 'qbo_cost_since')) then v_bad := v_bad || ' · 새 inv_config 키가 이미 있다'; end if;
  if not exists (select 1 from public.inv_config where key = 'inv_adjust_default_account_code' and value = '_1150040010_') then v_bad := v_bad || ' · inv_adjust_default_account_code 가 _1150040010_ 이 아니다(3-1 미적용?)'; end if;
  if (select count(*) from pg_proc where pronamespace = 'public'::regnamespace and proname in ('inv_adjust_account', 'ims_today', 'qbo_key_gate', 'qbo_realm_of', 'ims_touch', 'doc_is_service')) <> 6 then v_bad := v_bad || ' · 도우미 여섯(inv_adjust_account ims_today qbo_key_gate qbo_realm_of ims_touch doc_is_service)이 다 있지 않다'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current state first — nothing was changed', v_bad; end if;
end $$;

-- ═══════════════ ① inv_config 키 셋 (판정 1098 · 1099 · 이견 2 · 14 · 572: 앱에서 못 바꾼다 — 편집 목록 밖 기존 키는 ims_config_set 이 거부) ═══════════════
insert into public.inv_config (key, value, note) values
  ('qbo_send_cost_enabled', 'off', '[qbo-sync-3-2a · 판정 1098] 하루 원가 장 **자동 보내기** 스위치(on | off) — 3-3 의 보내기 cron 이 읽는다(이 차수에는 읽는 곳 없음 · 만들기 cron ims-qbo-cost-build 는 이 값과 무관하게 돈다) · 손 Send 는 막지 않는다(971 꼴 · qbo_send_enabled 와 같은 뜻) · 바꾸기는 psql(572) · 2026-11-08'),
  ('qbo_cost_adjust_hold_over', '1000', '[qbo-sync-3-2a · 판정 1099] 재고 조정 한 건(ADJ 문서 · 들어옴 · 나감 절대값 합 · CAD)이 이 값을 넘으면 하루 원가 장에서 「보류」 — 사람이 qbo_cost_hold_decide 로 보냄 / 안 보냄을 고르기 전에는 안 나간다 · write-off 를 가르는 칸은 503 차수 · 바꾸기는 마이그레이션 · psql(572) · 2026-11-08'),
  ('qbo_cost_since', '2026-10-31', '[qbo-sync-3-2a · 판정 1090 · 이견 2] 하루 원가 장이 세는 사건의 날짜 바닥(이 날 포함) — 출처 경계(inv_ledger.source = ims · IMS 비용 문서)의 두 번째 벽 · 조정은 10-31 부터 · 판매는 11-02 부터 저절로(첫 IMS 출고) · 살린 트럭 출발(10-26 · ims 행 있음)을 거른다 · 바꾸기는 마이그레이션(572) · 2026-11-08');
do $$
begin
  execute format('comment on table public.inv_config is %L', coalesce(obj_description('public.inv_config'::regclass, 'pg_class'), '') || ' · [qbo-sync-3-2a] 키 셋 더함: qbo_send_cost_enabled(off · 1098) · qbo_cost_adjust_hold_over(1000 · 1099) · qbo_cost_since(2026-10-31 · 1090) — 모두 572 거부 목록(psql 만)');
end $$;

-- ═══════════════ ② 상수 넷 — 창고 코드 · 제외 문서 · 비용 종류 → 계정 · 레이어의 장 창고 (이견 14: inv_config 가 아니라 함수 — 판이 남는다) ═══════════════
create function public.qbo_cost_wh_code(p_warehouse text) returns text
  language sql immutable
as $$
  select case p_warehouse when 'Asung Trading Inc.' then 'TOR' when 'Asung - Edmonton' then 'EDM' end;
$$;
comment on function public.qbo_cost_wh_code(text) is '[qbo-sync-3-2a · 판정 1102] 창고 이름 → 하루 원가 장 코드(TOR · EDM · 그 밖 null · IN_TRANSIT 은 장이 아니라 계정 #1150040007) — DocNumber COGS-YYYYMMDD-<코드> · 창고가 늘면 마이그레이션';

create function public.qbo_cost_wh_name(p_code text) returns text
  language sql immutable
as $$
  select case p_code when 'TOR' then 'Asung Trading Inc.' when 'EDM' then 'Asung - Edmonton' end;
$$;
comment on function public.qbo_cost_wh_name(text) is '[qbo-sync-3-2a] 장 코드 → 창고 이름(qbo_cost_wh_code 의 반대)';

create function public.qbo_cost_excluded_docs() returns text[]
  language sql immutable
as $$
  select array['TR-06396', 'TR-06397', 'TR-06398', 'TR-06399'];
$$;
comment on function public.qbo_cost_excluded_docs() is '[qbo-sync-3-2a · 판정 1085 · 1090 · 이견 2] 하루 원가 장이 보내지 않는 문서(두 다리 모두) — 살린 트럭 넷: 출발 분개가 QBO 에 없고(Cin7 시절) IMS 원장에도 ims 행이 있어 출처 규칙만으로는 출발(10-26 · 15,173.57)이 들어온다 · 도착(11-04 · 05 · 15,158.90)을 보내면 In Transit −15,159 · 제외 칸으로 월 검산에 보인다';

create function public.qbo_cost_charge_account(p_charge_kind text) returns text
  language sql immutable
as $$
  select case p_charge_kind when 'duty' then '_134_' when 'brokerage' then '_135_' when 'freight' then '_136_' end;
$$;
comment on function public.qbo_cost_charge_account(text) is '[qbo-sync-3-2a · 판정 1089 · 1100] 비용 문서 종류(po_charge.kind) → 원가 계정 — duty #134 Duty - COS · brokerage #135 Brokerage - COS · freight #136 Freight - COS · 모르면 null(장은 막는다) · 트랜스퍼 운임도 같은 규칙(1100 · 종류 없으면 #136)';

create function public.qbo_cost_layer_wh(p_warehouse text, p_doc_number text) returns text
  language sql stable security definer set search_path = public, pg_temp
as $$
  select case when p_warehouse = 'IN_TRANSIT'
              then (select public.qbo_cost_wh_code(w.name) from public.inv_transfer t join public.ref_warehouse w on w.id = t.from_warehouse_id where t.transfer_number = p_doc_number)
              else public.qbo_cost_wh_code(p_warehouse) end;
$$;
comment on function public.qbo_cost_layer_wh(text, text) is '[qbo-sync-3-2a · §15-h ⑤] 레이어가 속하는 장의 창고 코드 — 보통은 레이어 창고 · IN_TRANSIT 레이어(운송 중)는 그 트랜스퍼를 보낸 창고의 장(얹기 · 늦은 원가가 운송 중 레이어에 닿을 때 · 계정은 #1150040007) · 모르면 null(막음)';

-- ═══════════════ ③ 표 셋 — 장 · 보낸 몫 · 보류 결정 (RLS · grant 0 · PK uuid · 거래 표 FK 0) ═══════════════
create table public.qbo_cost_sheet (
  id                 uuid primary key default gen_random_uuid(),
  realm_id           text not null,
  sheet_date         date not null,
  wh                 text not null check (wh in ('TOR', 'EDM')),
  kind               text not null default 'day' check (kind in ('day', 'rebuild')),
  doc_number         text not null,
  state              text not null default 'pending' check (state in ('pending', 'hold', 'sending', 'sent', 'failed', 'unknown', 'empty', 'void')),
  hold_reason        text,
  job_id             uuid,
  qbo_id             text,
  epoch              bigint not null,
  built_at           timestamptz not null default now(),
  built_keys         int not null default 0,
  built_lines        int not null default 0,
  built_hold_keys    int not null default 0,
  built_debit_cents  bigint not null default 0,
  sent_at            timestamptz,
  resolved_at        timestamptz,
  resolved_by        uuid,
  note               text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  updated_by         uuid,
  constraint qbo_cost_sheet_day_uq unique (realm_id, sheet_date, wh, kind),
  constraint qbo_cost_sheet_doc_uq unique (realm_id, doc_number),
  constraint qbo_cost_sheet_sent_ck check ((state = 'sent') = (sent_at is not null) and (state <> 'sent' or qbo_id is not null)),
  constraint qbo_cost_sheet_hold_ck check (state <> 'hold' or hold_reason is not null),
  constraint qbo_cost_sheet_doc_ck check (doc_number ~ '^COGS-[0-9]{8}-(TOR|EDM)(-R)?$')
);
comment on table public.qbo_cost_sheet is '[qbo-sync-3-2a · 판정 1082 · 1092 · 1093 · 1098 · 1102] 하루 원가 장 — 하루 · 창고(TOR · EDM) 하나 · kind day(평소) | rebuild(재생성 뒤 「IMS cost rebuild」 한 장 · 3-2b) · state pending(만듦 · 일감 전 · 3-2a 는 여기까지) → sending → sent | failed | unknown · hold(재생성 세대 다름 · 3-2b) · empty(claim 때 줄 0 · 자동) · void(resolve not_in_qbo · 1101) · doc_number COGS-YYYYMMDD-TOR|EDM(-R) · epoch = min(inv_layer_consume.id)(재생성 감지 · 다르면 hold) · built_* = 만들 때의 셈(열쇠 · 줄 · 보류 열쇠 · 차변 센트 — 미리 보기는 지금 셈) · 줄은 claim 때 qbo_cost_sent 에 박힌다 · 거래 표 FK 0 · RLS · grant 0(창구만)';
create index qbo_cost_sheet_wh_idx on public.qbo_cost_sheet (realm_id, wh, sheet_date);
alter table public.qbo_cost_sheet enable row level security;
revoke all on table public.qbo_cost_sheet from public, anon, authenticated, service_role;
create trigger qbo_cost_sheet_touch before update on public.qbo_cost_sheet for each row execute function public.ims_touch();

create table public.qbo_cost_sent (
  id          uuid primary key default gen_random_uuid(),
  sheet_id    uuid not null references public.qbo_cost_sheet(id) on delete cascade,
  realm_id    text not null,
  wh          text not null check (wh in ('TOR', 'EDM')),
  key_kind    text not null,
  doc_key     text not null,
  acct_a      text not null,
  acct_b      text not null,
  cents       bigint not null check (cents <> 0),
  created_at  timestamptz not null default now(),
  constraint qbo_cost_sent_pair_ck check (acct_a < acct_b),
  constraint qbo_cost_sent_uq unique (sheet_id, wh, key_kind, doc_key, acct_a, acct_b)
);
comment on table public.qbo_cost_sent is '[qbo-sync-3-2a · 판정 1092 · 이견 7 · 15] 보낸 몫 — 장마다 · 창고 · 열쇠 종류(SO · CR · ADJ · TRF · CHG · RCV · CADJ · FG) · 열쇠(문서 번호) · 계정 짝(acct_a < acct_b 코드 순) · **센트**(양수 = 차 a / 대 b) · 원가 줄 id 없음(재생성에 견딘다) · 손님 없음(Entity 는 열쇠가 아니다) · 장의 state 를 따른다(sent · sending · unknown 장의 줄만 「보낸 몫」 · fail 이면 지운다 · 3-2b) · 다음 장 = 기대 − Σ이 표';
create index qbo_cost_sent_key_idx on public.qbo_cost_sent (realm_id, wh, key_kind, doc_key);
alter table public.qbo_cost_sent enable row level security;
revoke all on table public.qbo_cost_sent from public, anon, authenticated, service_role;

create table public.qbo_cost_hold (
  realm_id    text not null,
  key_kind    text not null,
  doc_key     text not null,
  decision    text not null check (decision in ('send', 'never')),
  note        text not null,
  decided_by  uuid,
  decided_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  updated_by  uuid,
  primary key (realm_id, key_kind, doc_key)
);
comment on table public.qbo_cost_hold is '[qbo-sync-3-2a · 판정 1099 · 이견 6] 문턱(qbo_cost_adjust_hold_over)을 넘은 재고 조정의 사람 결정 — send(이 열쇠를 보통 줄로 보낸다) | never(보내지 않는다 · 월 검산 제외 칸) · note 필수 · 입고(1096) · price_adjust · settlement_discount 보류는 결정을 받지 않는다(Bill · BillPayment 차수가 연다) · 창구 qbo_cost_hold_decide(열쇠 qbo) · RLS · grant 0';
alter table public.qbo_cost_hold enable row level security;
revoke all on table public.qbo_cost_hold from public, anon, authenticated, service_role;
create trigger qbo_cost_hold_touch before update on public.qbo_cost_hold for each row execute function public.ims_touch();

-- ═══════════════ ④ 기대값 — 22 칸을 SQL 로 (§15-h ① 표 · 판정 1084 · 1085 · 1087 · 1089 · 1094 ~ 1096 · 1099 · 1100 · 512) ═══════════════
-- 돌려주는 것 = 창고 · 열쇠 종류 · 열쇠 · 짝(acct_a < acct_b) · 센트(부호) · 원금(부호 · 반올림 전) · 상태(send | hold | block | excluded) · 까닭 · Entity 손님(IMS id · #58 짝의 SO · CR 만) · 첫 · 마지막 사건 날 · 사건 수
-- 0 센트 줄은 버린다(block 은 남긴다 — 막는 까닭을 보여야 한다) · 날짜 = 사건의 날짜(소진 occurred_on · 레이어 received_on · 얹기 occurred_on) · p_since 가 null 이면 qbo_cost_since
create function public.qbo_cost_expected(p_until date, p_since date default null, p_realm text default null)
  returns table (wh_code text, key_kind text, doc_key text, acct_a text, acct_b text, cents bigint, raw_amount numeric, status text, reason text, entity_customer_id uuid, first_on date, last_on date, n_events int)
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare
  v_since   date := coalesce(p_since, (select nullif(btrim(c.value), '')::date from public.inv_config c where c.key = 'qbo_cost_since'));
  v_realm   text := coalesce(p_realm, (select c.realm_id from public.qbo_connection c where c.singleton));
  v_thr     numeric := coalesce((select nullif(btrim(c.value), '')::numeric from public.inv_config c where c.key = 'qbo_cost_adjust_hold_over'), 1000);
  v_adj_def text := (select nullif(btrim(c.value), '') from public.inv_config c where c.key = 'inv_adjust_default_account_code');
  v_excl    text[] := public.qbo_cost_excluded_docs();
  c_inv     constant text := '_59_';
  c_transit constant text := '_1150040007_';
  c_cogs    constant text := '_58_';
  c_ginr    constant text := '_1150040012_';
begin
  if p_until is null then raise exception 'p_until is required — nothing was read'; end if;
  if v_since is null then raise exception 'inv_config qbo_cost_since is not set — a migration sets it — nothing was read'; end if;
  if v_adj_def is null then raise exception 'inv_config inv_adjust_default_account_code is not set — a migration sets it — nothing was read'; end if;
  return query
  with scope as (select distinct g.doc_number as d from public.inv_ledger g where g.source = 'ims'),
  fix as (select 'adj:' || a.id::text as lr from public.inv_cost_adjust a where a.kind = 'opening_fix'),
  -- ── 소진 ──
  -- ⚠️ cons_raw 는 materialized — planner 가 이 필터를 4 행으로 짐작해 inv_layer 38k 행을 바깥에 두고 7k × 38k 를 돌렸다(실측 35 s) · 먼저 굳히면 소진 7k 행마다 PK 조회(0.3 s)
  cons_raw as materialized (
    select c.id as cid, c.layer_id as clid, c.doc_type as cdt, c.doc_number as cdoc, c.line_ref as clr, c.reason as crs, c.occurred_on as con, c.amount as camt, c.split_basis as csb,
           (c.doc_number = any (v_excl)) as is_excl, (c.line_ref in (select f.lr from fix f)) as is_fix
    from public.inv_layer_consume c
    where c.occurred_on between v_since and p_until
      and (c.doc_number in (select s.d from scope s) or c.doc_number = any (v_excl) or c.line_ref in (select f.lr from fix f)
           or (c.doc_type = 'cost' and exists (select 1 from public.po_charge pc where pc.charge_number = c.doc_number)))
  ),
  cons as (
    select c.cid, c.cdt, c.cdoc, c.clr, c.crs, c.con, c.camt, c.csb, c.is_excl, c.is_fix,
           l.id as lid, l.warehouse as lwh, case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode
    from cons_raw c join public.inv_layer l on l.id = c.clid
  ),
  ev_cons as (
    -- sale → SO · 차 #58 / 대 #59(창고)
    select x.lcode as e_wh, 'SO' as e_kind, x.cdoc as e_key, c_cogs as e_dr, x.lacct as e_cr, x.camt as e_amt, x.con as e_on,
           case when x.is_excl then 'excluded' when x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end as e_status,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end as e_reason
    from cons x where x.crs = 'sale'
    union all
    -- reversal(크레딧 취소) → CR · 차 #58 / 대 #59
    select x.lcode, 'CR', x.cdoc, c_cogs, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'reversal'
    union all
    -- adjust_out → ADJ · 차 조정 계정(inv_adjust_account · 1087) / 대 #59
    select x.lcode, 'ADJ', x.cdoc, aa.code, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null or aa.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when aa.code is null then 'adjustment ' || x.cdoc || ' not found (account unknown)' end
    from cons x left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = x.cdoc) aa on true
    where x.crs = 'adjust_out'
    union all
    -- transfer 출발(보낸 창고 레이어) → TRF · 차 In Transit / 대 #59
    select x.lcode, 'TRF', x.cdoc, c_transit, c_inv, x.camt, x.con,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'transfer' and x.lwh <> 'IN_TRANSIT'
    union all
    -- transfer 도착(IN_TRANSIT 레이어 소진 → 받는 창고의 장) → TRF · 차 #59 / 대 In Transit
    select tw.code, 'TRF', x.cdoc, c_inv, c_transit, x.camt, x.con,
           case when x.is_excl then 'excluded' when tw.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when tw.code is null then 'receiving warehouse unknown for transfer ' || x.cdoc end
    from cons x left join lateral (select public.qbo_cost_wh_code(w.name) as code from public.inv_transfer t join public.ref_warehouse w on w.id = t.to_warehouse_id where t.transfer_number = x.cdoc) tw on true
    where x.crs = 'transfer' and x.lwh = 'IN_TRANSIT'
    union all
    -- cost_late → items 로 나눈다: sale 몫 → SO · 차 #58(1084) / 대 #59 · adjust_out · lost 몫 → ADJ · 차 그 조정 계정(1095) / 대 #59 · 그 밖 → block
    select x.lcode,
           case when it->>'reason' = 'sale' then 'SO' when it->>'reason' in ('adjust_out', 'lost') then 'ADJ' else 'cost_late' end,
           coalesce(it->>'doc_number', x.cdoc),
           case when it->>'reason' = 'sale' then c_cogs when it->>'reason' in ('adjust_out', 'lost') then ia.code else null end,
           x.lacct,
           case when coalesce(sh.tot, 0) > 0 then x.camt * (it->>'share')::numeric / sh.tot else x.camt end,
           x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' when it->>'reason' = 'sale' then 'send' when it->>'reason' in ('adjust_out', 'lost') and ia.code is not null then 'send' else 'block' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text
                when it->>'reason' = 'sale' then null when it->>'reason' in ('adjust_out', 'lost') and ia.code is not null then null
                else 'late cost ' || x.cdoc || ' has an item of kind ' || coalesce(it->>'reason', '?') || ' — not mapped' end
    from cons x
    cross join lateral (select coalesce(sum((i->>'share')::numeric), 0) as tot from jsonb_array_elements(coalesce(x.csb->'items', '[]'::jsonb)) i) sh
    cross join lateral jsonb_array_elements(case when jsonb_typeof(x.csb->'items') = 'array' and jsonb_array_length(x.csb->'items') > 0 then x.csb->'items' else '[{"reason":"no_items"}]'::jsonb end) it
    left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = it->>'doc_number' and it->>'reason' in ('adjust_out', 'lost')) ia on true
    where x.crs = 'cost_late'
    union all
    -- cost_moved → 자식(트랜스퍼) 레이어의 창고 계정 ↔ 제 계정 · 같으면 0(줄 없음) · 자식 창고가 둘이거나 없으면 block
    select x.lcode, case when x.cdt = 'cost' then 'CHG' else 'TRF' end, x.cdoc,
           case when ch.n = 1 then ch.acct else x.lacct end, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null or ch.n <> 1 then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when ch.n <> 1 then 'moved cost ' || x.cdoc || ' has ' || ch.n::text || ' child warehouses (expected 1)' end
    from cons x
    cross join lateral (select count(distinct y.warehouse) as n, min(case when y.warehouse = 'IN_TRANSIT' then c_transit else c_inv end) as acct from public.inv_layer y where y.parent_layer_id = x.lid and y.origin_type = 'transfer') ch
    where x.crs = 'cost_moved'
    union all
    -- assembly_in → FG · 같은 창고 #59 ↔ #59 = 0(줄 없음 · 값 차이는 아래 asm_check 가 막는다)
    select x.lcode, 'FG', x.cdoc, x.lacct, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from cons x where x.crs = 'assembly_in'
    union all
    -- lost → 막음(deferred 512) · 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.crs, x.cdoc, x.lacct, x.lacct, x.camt, x.con,
           case when x.is_excl or x.is_fix then 'excluded' else 'block' end,
           case when x.is_excl then 'revived truck (1085)' when x.is_fix then 'opening_fix (1090)' when x.crs = 'lost' then 'consume reason lost on ' || x.cdoc || ' — meaning not decided (deferred 512)' else 'consume reason ' || x.crs || ' on ' || x.cdoc || ' — not in the 22 cells' end
    from cons x where x.crs not in ('sale', 'reversal', 'adjust_out', 'transfer', 'cost_late', 'cost_moved', 'assembly_in')
  ),
  -- ── 레이어(생김) ──
  lay as (
    select l.id as lid, l.origin_type as lor, l.doc_number as ldoc, l.received_on as lon, l.qty * l.unit_cost as lamt, l.warehouse as lwh,
           case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode, (l.doc_number = any (v_excl)) as is_excl
    from public.inv_layer l
    where l.origin_type not in ('baseline', 'transfer') and l.received_on between v_since and p_until
      and (l.doc_number in (select s.d from scope s) or l.doc_number = any (v_excl))
  ),
  ev_lay as (
    -- purchase(입고) → RCV · 차 #59 / 대 GINR · 보류(1096 · Bill 차수가 연다)
    select x.lcode as e_wh, 'RCV' as e_kind, x.ldoc as e_key, x.lacct as e_dr, c_ginr as e_cr, x.lamt as e_amt, x.lon as e_on,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'hold' end as e_status,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text else 'receipt — opens with the supplier bill round (1096)' end as e_reason
    from lay x where x.lor = 'purchase'
    union all
    -- creditnote(restock) → CR · 차 #59 / 대 #58
    select x.lcode, 'CR', x.ldoc, x.lacct, c_cogs, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'creditnote'
    union all
    -- adjust_new · adjust_existing → ADJ · 차 #59 / 대 조정 계정(1087)
    select x.lcode, 'ADJ', x.ldoc, x.lacct, aa.code, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null or aa.code is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when aa.code is null then 'adjustment ' || x.ldoc || ' not found (account unknown)' end
    from lay x left join lateral (select y.account_code as code from public.inv_adjust a cross join lateral public.inv_adjust_account(a.id) y where a.adjust_number = x.ldoc) aa on true
    where x.lor in ('adjust_new', 'adjust_existing')
    union all
    -- sale_shortfall → SO · 차 #59 / 대 조정 기본 계정(1094 · 판매 원가 줄은 그대로)
    select x.lcode, 'SO', x.ldoc, x.lacct, v_adj_def, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'sale_shortfall'
    union all
    -- assembly → FG · 같은 창고 #59 ↔ #59 = 0
    select x.lcode, 'FG', x.ldoc, x.lacct, x.lacct, x.lamt, x.lon,
           case when x.is_excl then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_excl then 'revived truck (1085)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from lay x where x.lor = 'assembly'
    union all
    -- 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.lor, x.ldoc, x.lacct, x.lacct, x.lamt, x.lon, 'block', 'layer origin ' || x.lor || ' on ' || x.ldoc || ' — not in the 22 cells'
    from lay x where x.lor not in ('purchase', 'creditnote', 'adjust_new', 'adjust_existing', 'sale_shortfall', 'assembly')
  ),
  -- 조립 값 검산 — 문서마다 Σ소진(assembly_in) ≠ Σ레이어(assembly) 면 막음(같은 창고 #59 ↔ #59 라 줄은 없지만 값이 새면 안 된다)
  asm_check as (
    select coalesce(a.e_wh, b.e_wh) as e_wh, 'FG' as e_kind, coalesce(a.e_key, b.e_key) as e_key, c_inv as e_dr, c_inv as e_cr, coalesce(a.s, 0) - coalesce(b.s, 0) as e_amt, coalesce(a.o, b.o) as e_on,
           'block' as e_status, 'assembly ' || coalesce(a.e_key, b.e_key) || ' consumes ' || coalesce(a.s, 0)::text || ' but the finished layer is worth ' || coalesce(b.s, 0)::text as e_reason
    from (select e.e_wh, e.e_key, sum(e.e_amt) as s, min(e.e_on) as o from ev_cons e where e.e_kind = 'FG' and e.e_status = 'send' group by 1, 2) a
    full join (select e.e_wh, e.e_key, sum(e.e_amt) as s, min(e.e_on) as o from ev_lay e where e.e_kind = 'FG' and e.e_status = 'send' group by 1, 2) b on b.e_wh = a.e_wh and b.e_key = a.e_key
    where abs(coalesce(a.s, 0) - coalesce(b.s, 0)) > 0.005
  ),
  -- ── 얹기 ──
  adds_raw as materialized (
    select a.id as aid, a.layer_id as alid, a.kind as akd, a.doc_number as adoc, a.line_ref as alr, a.occurred_on as aon, a.amount as aamt,
           (a.line_ref in (select f.lr from fix f)) as is_fix, (a.doc_number in (select s.d from scope s)) as in_scope
    from public.inv_layer_cost_add a
    where a.kind <> 'carried' and a.occurred_on between v_since and p_until
  ),
  adds as (
    select a.aid, a.akd, a.adoc, a.alr, a.aon, a.aamt, a.is_fix, a.in_scope,
           l.id as lid, l.warehouse as lwh, case when l.warehouse = 'IN_TRANSIT' then c_transit else c_inv end as lacct, public.qbo_cost_layer_wh(l.warehouse, l.doc_number) as lcode,
           pc.kind as pckind, (pc.id is not null) as is_ims_charge, ca.source_number as ca_num
    from adds_raw a join public.inv_layer l on l.id = a.alid
    left join public.po_charge pc on a.akd = 'landed' and pc.charge_number = a.adoc
    left join public.inv_cost_adjust ca on a.akd in ('price_adjust', 'settlement_discount') and a.alr = 'adj:' || ca.id::text
  ),
  ev_add as (
    -- landed(IMS 비용 문서) → CHG · 차 #59(운송 중 레이어면 In Transit) / 대 비용 종류 계정(1089) · 날짜 = IMS 가 얹은 날(507) · Cin7 축 landed 는 범위 밖
    select x.lcode as e_wh, 'CHG' as e_kind, x.adoc as e_key, x.lacct as e_dr, public.qbo_cost_charge_account(x.pckind) as e_cr, x.aamt as e_amt, x.aon as e_on,
           case when x.is_fix then 'excluded' when x.lcode is null or public.qbo_cost_charge_account(x.pckind) is null then 'block' else 'send' end as e_status,
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text when public.qbo_cost_charge_account(x.pckind) is null then 'charge ' || x.adoc || ' kind ' || coalesce(x.pckind, '?') || ' has no cost account (1089)' end as e_reason
    from adds x where x.akd = 'landed' and (x.is_ims_charge or x.is_fix)
    union all
    -- transfer_freight(Cin7 축 꼴 · 문서가 범위 안일 때만) → TRF · 차 #59 / In Transit / 대 #136(1100 · 종류 없음)
    select x.lcode, 'TRF', x.adoc, x.lacct, '_136_', x.aamt, x.aon,
           case when x.is_fix then 'excluded' when x.lcode is null then 'block' else 'send' end,
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text end
    from adds x where x.akd = 'transfer_freight' and (x.in_scope or x.is_fix)
    union all
    -- price_adjust · settlement_discount(원가 조정 사건) → CADJ · 보류(1080 · 1081 차수) · 대 계정 미정(null)
    select x.lcode, 'CADJ', coalesce(x.ca_num, x.alr), x.lacct, null, x.aamt, x.aon,
           case when x.is_fix then 'excluded' when x.lcode is null then 'block' else 'hold' end,
           case when x.is_fix then 'opening_fix (1090)' when x.lcode is null then 'warehouse unknown for layer ' || x.lid::text else 'cost adjustment (' || x.akd || ') — opens with the supplier bill / payment round (1080 · 1081)' end
    from adds x where x.akd in ('price_adjust', 'settlement_discount')
    union all
    -- opening_fix → 제외(932 · 1090) · 그 밖(제약이 넓어진 칸) → 막음
    select coalesce(x.lcode, 'TOR'), x.akd, x.adoc, x.lacct, x.lacct, x.aamt, x.aon,
           case when x.akd = 'opening_fix' or x.is_fix then 'excluded' else 'block' end,
           case when x.akd = 'opening_fix' or x.is_fix then 'opening_fix (1090)' else 'cost add kind ' || x.akd || ' on ' || x.adoc || ' — not in the 22 cells' end
    from adds x where x.akd not in ('landed', 'transfer_freight', 'price_adjust', 'settlement_discount')
  ),
  ev as (
    select * from ev_cons union all select * from ev_lay union all select * from asm_check union all select * from ev_add
  ),
  -- 문턱(1099): ADJ 문서마다 Σ|금액|(들어옴 · 나감) > 문턱이면 보류 · 결정 send → send · never → excluded
  adj_tot as (select e.e_key as k, sum(abs(e.e_amt)) as tot from ev e where e.e_kind = 'ADJ' and e.e_status = 'send' group by 1),
  ev2 as (
    select e.e_wh, e.e_kind, e.e_key, e.e_dr, e.e_cr, e.e_amt, e.e_on,
           case when e.e_kind = 'ADJ' and e.e_status = 'send' and t.tot > v_thr then
                  case h.decision when 'send' then 'send' when 'never' then 'excluded' else 'hold' end
                else e.e_status end as e_status,
           case when e.e_kind = 'ADJ' and e.e_status = 'send' and t.tot > v_thr then
                  case h.decision when 'send' then 'adjustment over threshold — decided: send' when 'never' then 'adjustment over threshold — decided: never send'
                       else 'adjustment ' || e.e_key || ' totals ' || round(t.tot, 2)::text || ' over the ' || v_thr::text || ' threshold — decide send / never first (1099)' end
                else e.e_reason end as e_reason
    from ev e
    left join adj_tot t on e.e_kind = 'ADJ' and t.k = e.e_key
    left join public.qbo_cost_hold h on v_realm is not null and h.realm_id = v_realm and h.key_kind = e.e_kind and h.doc_key = e.e_key
  ),
  agg as (
    select e.e_wh, e.e_kind, e.e_key,
           least(e.e_dr, coalesce(e.e_cr, e.e_dr)) as a, greatest(e.e_dr, coalesce(e.e_cr, e.e_dr)) as b,
           sum(case when e.e_dr = least(e.e_dr, coalesce(e.e_cr, e.e_dr)) then e.e_amt else -e.e_amt end) as raw,
           e.e_status, min(e.e_reason) as rs, min(e.e_on) as f_on, max(e.e_on) as l_on, count(*)::int as n,
           bool_or(e.e_cr is null) as cr_null
    from ev2 e
    group by e.e_wh, e.e_kind, e.e_key, least(e.e_dr, coalesce(e.e_cr, e.e_dr)), greatest(e.e_dr, coalesce(e.e_cr, e.e_dr)), e.e_status
  )
  select g.e_wh, g.e_kind, g.e_key, g.a, case when g.cr_null then null else g.b end, (round(g.raw, 2) * 100)::bigint, g.raw, g.e_status, g.rs,
         case when g.e_kind = 'SO' and c_cogs in (g.a, g.b) then (select io.customer_id from public.so_invoice_order io join public.so_invoice i on i.id = io.invoice_id where io.so_number = g.e_key and io.cancelled_at is null and i.status = 'issued' order by i.issued_on desc, i.created_at desc limit 1)
              when g.e_kind = 'CR' and c_cogs in (g.a, g.b) then (select coalesce(cr.store_customer_id, cr.customer_id) from public.so_credit cr where cr.credit_number = g.e_key) end,
         g.f_on, g.l_on, g.n
  from agg g
  where round(g.raw, 2) <> 0 or g.e_status = 'block'
  order by g.e_wh, g.e_kind, g.e_key, g.a, g.b;
end;
$$;
comment on function public.qbo_cost_expected(date, date, text) is '[qbo-sync-3-2a · §15-h ① ~ ③ · 판정 1084 · 1085 · 1087 · 1089 · 1090 · 1094 ~ 1096 · 1099 · 1100 · 512] 하루 원가 장의 기대값 — 날짜 p_since(null = qbo_cost_since) ~ p_until 의 IMS 원가 사건을 22 칸으로 매겨 창고 · 열쇠 종류(SO CR ADJ TRF CHG RCV CADJ FG) · 열쇠 · 계정 짝(acct_a < acct_b) · 센트(양수 = 차 a / 대 b) · 상태(send | hold | block | excluded) · 까닭 · Entity 손님(#58 짝의 SO · CR) 으로 돌려준다 · 경계 = 출처(inv_ledger source ims · po_charge) ∧ 날짜 바닥 · 제외 = 살린 트럭 두 다리 · opening_fix 가족 · 트랜스퍼는 소진 줄로만(복사 carried 안 셈) · 0 센트 줄은 버림(block 은 남김) · 모르는 칸 = block(장은 안 선다) · service · definer(원가 표 RLS 뒤) · grant 0';

-- ═══════════════ ⑤ 장 셈 — 기대 − 보낸 몫 = 차액 (판정 1092 · 이견 9: 앞에 아직 안 보낸 장 P 가 있으면 기대(≤ D) − 기대(≤ P)) ═══════════════
-- 돌려주는 것 = 열쇠마다 기대 센트 · 보낸 합(또는 P 바탕) · 차액 · 처음 보낸 장 날짜 · 상태 · 까닭 · Entity(IMS 손님 · QBO Customer 번호) · 줄 설명(열쇠 + 「(adj. of YYYY-MM-DD)」) · baseline(sent | pending:<P 날짜> | none)
create function public.qbo_cost_sheet_calc(p_date date, p_wh text, p_realm text default null)
  returns table (key_kind text, doc_key text, acct_a text, acct_b text, expected_cents bigint, sent_cents bigint, diff_cents bigint, first_sent_on date, status text, reason text,
                 entity_customer_id uuid, entity_qbo_id text, label text, baseline text)
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_realm text := coalesce(p_realm, (select c.realm_id from public.qbo_connection c where c.singleton)); v_p date; v_base text;
begin
  if p_date is null or p_wh is null or p_wh not in ('TOR', 'EDM') then raise exception 'p_date and p_wh (TOR | EDM) are required — nothing was read'; end if;
  if v_realm is null then raise exception 'QuickBooks is not connected — connect it in Settings → QuickBooks first — nothing was read'; end if;
  select max(s.sheet_date) into v_p from public.qbo_cost_sheet s where s.realm_id = v_realm and s.wh = p_wh and s.kind = 'day' and s.sheet_date < p_date and s.state in ('pending', 'hold', 'failed');
  v_base := case when v_p is not null then 'pending:' || v_p::text else case when exists (select 1 from public.qbo_cost_sent t where t.realm_id = v_realm and t.wh = p_wh) then 'sent' else 'none' end end;
  return query
  with exp_now as (select * from public.qbo_cost_expected(p_date, null, v_realm) e where e.wh_code = p_wh),
  base as (
    select e.key_kind as k, e.doc_key as d, e.acct_a as a, e.acct_b as b, e.cents as c, null::date as f
    from public.qbo_cost_expected(coalesce(v_p, date '1900-01-01'), null, v_realm) e where v_p is not null and e.wh_code = p_wh and e.status = 'send'
    union all
    select t.key_kind, t.doc_key, t.acct_a, t.acct_b, sum(t.cents)::bigint, min(s.sheet_date)
    from public.qbo_cost_sent t join public.qbo_cost_sheet s on s.id = t.sheet_id
    where v_p is null and t.realm_id = v_realm and t.wh = p_wh and s.state in ('sent', 'sending', 'unknown')
    group by t.key_kind, t.doc_key, t.acct_a, t.acct_b
  ),
  keys as (
    select coalesce(e.key_kind, b.k) as k, coalesce(e.doc_key, b.d) as d, coalesce(e.acct_a, b.a) as a, coalesce(e.acct_b, b.b) as b2,
           coalesce(e.cents, 0) as ec, coalesce(b.c, 0) as sc, b.f, coalesce(e.status, 'send') as st, e.reason as rs, e.entity_customer_id as cust
    from exp_now e full join base b on b.k = e.key_kind and b.d = e.doc_key and b.a = e.acct_a and b.b is not distinct from e.acct_b
  )
  select x.k, x.d, x.a, x.b2, x.ec, x.sc, case when x.st = 'send' then x.ec - x.sc else x.ec end, x.f, x.st, x.rs, x.cust,
         (select l.qbo_id from public.qbo_link l where x.cust is not null and l.realm_id = v_realm and l.ims_kind = 'customer' and l.ims_id = x.cust::text),
         x.d || case when x.st = 'send' and x.sc <> 0 and x.f is not null then ' (adj. of ' || x.f::text || ')' else '' end,
         v_base
  from keys x
  where x.st <> 'send' or x.ec - x.sc <> 0
  order by x.k, x.d, x.a, x.b2;
end;
$$;
comment on function public.qbo_cost_sheet_calc(date, text, text) is '[qbo-sync-3-2a · 판정 1092 · 1097 · 1103 · 이견 9] 날 D · 창고의 장 셈 — 기대(≤ D) − 보낸 몫(sent · sending · unknown 장의 qbo_cost_sent 합) = 차액 · 앞에 아직 안 보낸 장 P(pending · hold · failed)가 있으면 기대(≤ D) − 기대(≤ P)(P 가 보내질 때 그 몫이 나간다 · baseline pending:<P>) · 0 차액 send 줄은 안 돌려준다 · hold · block · excluded 줄은 기대값 그대로 돌려준다(미리 보기 · 월 검산) · label = 열쇠 + 「(adj. of 처음 보낸 날)」(이미 보낸 열쇠의 차액) · Entity = 인보이스 · 크레딧 노트 손님의 qbo_link · service · definer · grant 0 · 3-2b 의 몸(JE)이 이것을 읽는다';

-- ═══════════════ ⑥ 장 만들기 — 장 행만 (일감 · 줄은 3-2b) ═══════════════
create function public.qbo_cost_sheet_build(p_date date, p_wh text, p_realm text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := coalesce(p_realm, (select c.realm_id from public.qbo_connection c where c.singleton)); v_since date := (select nullif(btrim(c.value), '')::date from public.inv_config c where c.key = 'qbo_cost_since');
        v_s public.qbo_cost_sheet%rowtype; v_blocks text; v_n_block int; v_keys int; v_lines int; v_holds int; v_debit bigint; v_epoch bigint; v_doc text; v_id uuid;
begin
  if p_date is null or p_wh is null or p_wh not in ('TOR', 'EDM') then raise exception 'p_date and p_wh (TOR | EDM) are required — nothing was saved'; end if;
  if v_realm is null then raise exception 'QuickBooks is not connected — connect it in Settings → QuickBooks first — nothing was saved'; end if;
  if p_date >= public.ims_today() then raise exception 'Cost day % is not closed yet (today in Toronto is %) — a sheet is built the next day — nothing was saved', p_date, public.ims_today(); end if;
  if p_date < v_since then raise exception 'Cost day % is before the sync start % (inv_config qbo_cost_since) — nothing was saved', p_date, v_since; end if;
  select * into v_s from public.qbo_cost_sheet s where s.realm_id = v_realm and s.sheet_date = p_date and s.wh = p_wh and s.kind = 'day';
  if v_s.id is not null then
    return jsonb_build_object('built', false, 'existing', true, 'sheet_id', v_s.id, 'doc_number', v_s.doc_number, 'state', v_s.state, 'date', p_date, 'wh', p_wh);
  end if;
  -- 막힌 칸이 하나라도 있으면 장을 만들지 않는다(1 ~ 5 개를 글에 · 이견 16)
  select count(*), string_agg(left(x.reason, 160), ' · ' order by x.doc_key) filter (where x.rn <= 5) into v_n_block, v_blocks
  from (select c.doc_key, c.reason, row_number() over (order by c.doc_key) as rn from public.qbo_cost_sheet_calc(p_date, p_wh, v_realm) c where c.status = 'block') x;
  if v_n_block > 0 then raise exception 'Cost day % %: % event(s) cannot be mapped to a QuickBooks line — fix or decide them first: % — nothing was saved', p_date, p_wh, v_n_block, v_blocks; end if;
  select count(*) filter (where c.status = 'send' and c.diff_cents <> 0), count(distinct c.doc_key) filter (where c.status = 'send' and c.diff_cents <> 0), count(distinct c.doc_key) filter (where c.status = 'hold'),
         coalesce(sum(abs(c.diff_cents)) filter (where c.status = 'send' and c.diff_cents <> 0), 0)
    into v_lines, v_keys, v_holds, v_debit
  from public.qbo_cost_sheet_calc(p_date, p_wh, v_realm) c;
  if v_lines = 0 then
    return jsonb_build_object('built', false, 'existing', false, 'reason', 'nothing to send', 'hold_keys', v_holds, 'date', p_date, 'wh', p_wh);
  end if;
  select coalesce(min(c.id), 0) into v_epoch from public.inv_layer_consume c;
  v_doc := 'COGS-' || to_char(p_date, 'YYYYMMDD') || '-' || p_wh;
  insert into public.qbo_cost_sheet (realm_id, sheet_date, wh, kind, doc_number, state, epoch, built_keys, built_lines, built_hold_keys, built_debit_cents)
  values (v_realm, p_date, p_wh, 'day', v_doc, 'pending', v_epoch, v_keys, v_lines, v_holds, v_debit) returning id into v_id;
  return jsonb_build_object('built', true, 'existing', false, 'sheet_id', v_id, 'doc_number', v_doc, 'state', 'pending', 'date', p_date, 'wh', p_wh, 'keys', v_keys, 'lines', v_lines, 'hold_keys', v_holds, 'debit_cents', v_debit, 'epoch', v_epoch);
end;
$$;
comment on function public.qbo_cost_sheet_build(date, text, text) is '[qbo-sync-3-2a · 판정 1082 · 1093 · 1098 · 이견 9 · 16] 날 D · 창고의 장 행을 만든다(일감 · 줄은 3-2b) — 닫힌 날만(D < ims_today) · qbo_cost_since 뒤만 · 이미 있으면 그대로(existing) · 막힌 칸이 있으면 예외(문서 번호 · 칸 1 ~ 5 개) · 보낼 차액 줄이 0 이면 장 없음(nothing to send · 보류만 있는 날도 장 없음) · epoch = min(inv_layer_consume.id) · built_* = 만들 때 셈 · service · definer · grant 0(cron · qbo_cost_build_now 가 부른다)';

create function public.qbo_cost_sheet_build_due(p_realm text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_realm text := coalesce(p_realm, (select c.realm_id from public.qbo_connection c where c.singleton)); v_since date := (select nullif(btrim(c.value), '')::date from public.inv_config c where c.key = 'qbo_cost_since');
        v_to date := public.ims_today() - 1; v_wh text; v_from date; v_d date; v_r jsonb; v_built jsonb := '[]'::jsonb; v_err jsonb := '[]'::jsonb; v_scanned int := 0;
begin
  if v_realm is null then return jsonb_build_object('skipped', 'QuickBooks is not connected', 'built', v_built, 'errors', v_err, 'days_scanned', 0); end if;
  if v_since is null then return jsonb_build_object('skipped', 'inv_config qbo_cost_since is not set', 'built', v_built, 'errors', v_err, 'days_scanned', 0); end if;
  foreach v_wh in array array['TOR', 'EDM'] loop
    select coalesce(max(s.sheet_date) + 1, v_since) into v_from from public.qbo_cost_sheet s where s.realm_id = v_realm and s.wh = v_wh and s.kind = 'day';
    v_d := v_from;
    while v_d <= v_to loop
      v_scanned := v_scanned + 1;
      begin
        v_r := public.qbo_cost_sheet_build(v_d, v_wh, v_realm);
        if (v_r->>'built')::boolean then v_built := v_built || (v_r - 'existing'); end if;
      exception when others then
        v_err := v_err || jsonb_build_object('date', v_d, 'wh', v_wh, 'error', left(sqlerrm, 1000));
        exit;                                                                                                   -- 막힌 날 뒤는 이 창고에서 더 가지 않는다(차례 · 다음 회차가 다시 본다)
      end;
      v_d := v_d + 1;
    end loop;
  end loop;
  return jsonb_build_object('realm_id', v_realm, 'to', v_to, 'days_scanned', v_scanned, 'built', v_built, 'errors', v_err);
end;
$$;
comment on function public.qbo_cost_sheet_build_due(text) is '[qbo-sync-3-2a · 판정 1098 · ⬜2] 밀린 장을 전부 만든다 — 창고마다 (마지막 장 날 + 1 · 없으면 qbo_cost_since) ~ 어제(토론토) · 날마다 qbo_cost_sheet_build · 막힌 날(예외)에서 그 창고는 멈추고 errors 에 적는다(다음 회차가 다시 본다) · 연결 없으면 skipped · cron ims-qbo-cost-build(0 8 * * * UTC · supabase/ops/cron.sql · 등록은 Caleb)가 부른다 · 스위치 qbo_send_cost_enabled 와 무관(DB 만 쓴다) · grant 0(cron = postgres · 사람은 qbo_cost_build_now)';

create function public.qbo_cost_build_now() returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true);
begin
  return public.qbo_cost_sheet_build_due(null) || jsonb_build_object('by_staff', v_staff);
end;
$$;
comment on function public.qbo_cost_build_now() is '[qbo-sync-3-2a] 사람이 지금 밀린 장을 만든다(열쇠 qbo 쓰기) — qbo_cost_sheet_build_due 그대로 · 화면(3-4) 「Build sheets」';

-- ═══════════════ ⑦ 미리 보기 · 장 목록 (열쇠 qbo:read · 판정 1092 ⑦ · 1097 줄 모양 · 1103 Entity) ═══════════════
-- je_lines = 1097 · 이견 8 의 줄 모양 미리 보기: 열쇠마다 #59 아닌 계정 줄 + 그 창고 #59 는 장마다 순액 한 줄(줄 반올림의 합) — 3-2b 의 몸이 같은 규칙으로 JSON 을 짓는다
create function public.qbo_cost_preview(p_date date, p_wh text) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_s public.qbo_cost_sheet%rowtype; v_lines jsonb; v_err text; v_je jsonb; v_holds jsonb; v_ex jsonb; v_blocks jsonb; v_dr bigint := 0; v_cr bigint := 0; v_inv bigint; v_n int := 0; v_base text;
begin
  if p_date is null or p_wh is null or p_wh not in ('TOR', 'EDM') then raise exception 'date and warehouse (TOR | EDM) are required — nothing was read'; end if;
  select * into v_s from public.qbo_cost_sheet s where s.realm_id = v_realm and s.sheet_date = p_date and s.wh = p_wh and s.kind = 'day';
  begin
    with c as (select * from public.qbo_cost_sheet_calc(p_date, p_wh, v_realm))
    select coalesce(jsonb_agg(to_jsonb(c) - 'baseline' order by c.key_kind, c.doc_key, c.acct_a) filter (where c.status = 'send'), '[]'::jsonb),
           coalesce(jsonb_agg(to_jsonb(c) - 'baseline' order by c.key_kind, c.doc_key, c.acct_a) filter (where c.status = 'hold'), '[]'::jsonb),
           coalesce(jsonb_agg(to_jsonb(c) - 'baseline' order by c.key_kind, c.doc_key, c.acct_a) filter (where c.status = 'excluded'), '[]'::jsonb),
           coalesce(jsonb_agg(to_jsonb(c) - 'baseline' order by c.key_kind, c.doc_key, c.acct_a) filter (where c.status = 'block'), '[]'::jsonb),
           min(c.baseline)
      into v_lines, v_holds, v_ex, v_blocks, v_base
    from c;
    -- 줄 모양(1097): 열쇠 줄 = #59 아닌 계정 · 부호 = 그 계정이 차변이면 + · #59 는 순액 한 줄
    with c as (select * from public.qbo_cost_sheet_calc(p_date, p_wh, v_realm) x where x.status = 'send' and x.diff_cents <> 0),
    k as (
      select c.label, c.key_kind, c.doc_key, c.entity_qbo_id, c.acct_a as acct, c.diff_cents as signed from c where c.acct_a <> '_59_'
      union all
      select c.label, c.key_kind, c.doc_key, c.entity_qbo_id, c.acct_b, -c.diff_cents from c where c.acct_b <> '_59_'
    ),
    inv as (select coalesce(sum(case when c.acct_a = '_59_' then c.diff_cents else 0 end) + sum(case when c.acct_b = '_59_' then -c.diff_cents else 0 end), 0) as s from c)
    select coalesce(jsonb_agg(jsonb_build_object('account_code', k.acct, 'posting', case when k.signed > 0 then 'Debit' else 'Credit' end, 'cents', abs(k.signed), 'description', k.label, 'key_kind', k.key_kind, 'doc_key', k.doc_key, 'entity_qbo_id', k.entity_qbo_id) order by k.key_kind, k.doc_key, k.acct), '[]'::jsonb),
           coalesce(sum(k.signed) filter (where k.signed > 0), 0), coalesce(-sum(k.signed) filter (where k.signed < 0), 0), (select s from inv), count(*)::int
      into v_je, v_dr, v_cr, v_inv, v_n
    from k;
    if v_inv <> 0 then
      v_je := v_je || jsonb_build_object('account_code', '_59_', 'posting', case when v_inv > 0 then 'Debit' else 'Credit' end, 'cents', abs(v_inv), 'description', 'Inventory ' || p_wh, 'key_kind', null, 'doc_key', null, 'entity_qbo_id', null);
      if v_inv > 0 then v_dr := v_dr + v_inv; else v_cr := v_cr - v_inv; end if;
      v_n := v_n + 1;
    end if;
  exception when others then
    v_err := left(sqlerrm, 2000); v_lines := null; v_je := null;
  end;
  return jsonb_build_object(
    'date', p_date, 'wh', p_wh, 'doc_number', 'COGS-' || to_char(p_date, 'YYYYMMDD') || '-' || p_wh,
    'sheet', case when v_s.id is null then null else jsonb_build_object('id', v_s.id, 'state', v_s.state, 'hold_reason', v_s.hold_reason, 'job_id', v_s.job_id, 'qbo_id', v_s.qbo_id, 'epoch', v_s.epoch, 'built_at', v_s.built_at, 'built_keys', v_s.built_keys, 'built_lines', v_s.built_lines, 'built_hold_keys', v_s.built_hold_keys, 'built_debit_cents', v_s.built_debit_cents, 'sent_at', v_s.sent_at, 'note', v_s.note) end,
    'epoch_now', (select min(c.id) from public.inv_layer_consume c),
    'baseline', v_base,
    'keys', v_lines, 'holds', v_holds, 'excluded', v_ex, 'blocks', v_blocks, 'error', v_err,
    'je_lines', v_je, 'je_line_count', v_n, 'debit_cents', v_dr, 'credit_cents', v_cr, 'balanced', (v_dr = v_cr),
    'preview_only', true);
end;
$$;
comment on function public.qbo_cost_preview(date, text) is '[qbo-sync-3-2a · 판정 1092 ⑦ · 1097 · 1099 · 1103 · 이견 8 · 9 · 16] 날 · 창고의 장 미리 보기(열쇠 qbo 또는 qbo:read) — sheet(있으면 · 만들 때 셈) · keys(지금 셈 · 열쇠마다 기대 · 보낸 합 · 차액 · 처음 보낸 날 · Entity) · holds(보류 열쇠 · 까닭) · excluded · blocks · error(막힌 칸이면 글) · je_lines(1097 줄 모양: 열쇠마다 #59 아닌 계정 줄 + 그 창고 #59 순액 한 줄 · 차대 합 · balanced) · QBO 호출 0 · 아무것도 쓰지 않는다';

create function public.qbo_cost_sheet_list(p_from date default null, p_to date default null, p_wh text default null, p_state text default null) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of();
begin
  if p_wh is not null and p_wh not in ('TOR', 'EDM') then raise exception 'warehouse must be TOR or EDM (got %) — nothing was read', p_wh; end if;
  if p_state is not null and p_state not in ('pending', 'hold', 'sending', 'sent', 'failed', 'unknown', 'empty', 'void', 'open') then raise exception 'state must be one of pending, hold, sending, sent, failed, unknown, empty, void, open (got %) — nothing was read', p_state; end if;
  return jsonb_build_object('from', p_from, 'to', p_to, 'wh', p_wh, 'state', p_state,
    'counts', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) from (select s.state, count(*) as n from public.qbo_cost_sheet s where s.realm_id = v_realm group by s.state) x),
    'since', (select c.value from public.inv_config c where c.key = 'qbo_cost_since'),
    'send_enabled', (select c.value from public.inv_config c where c.key = 'qbo_send_cost_enabled'),
    'epoch_now', (select min(c.id) from public.inv_layer_consume c),
    'rows', coalesce((select jsonb_agg(to_jsonb(s) - 'realm_id' order by s.sheet_date desc, s.wh, s.kind) from public.qbo_cost_sheet s
                       where s.realm_id = v_realm and (p_from is null or s.sheet_date >= p_from) and (p_to is null or s.sheet_date <= p_to) and (p_wh is null or s.wh = p_wh)
                         and (p_state is null or (p_state = 'open' and s.state not in ('sent', 'empty', 'void')) or s.state = p_state)), '[]'::jsonb));
end;
$$;
comment on function public.qbo_cost_sheet_list(date, date, text, text) is '[qbo-sync-3-2a] 장 목록(열쇠 qbo · qbo:read) — 날짜 · 창고 · 상태(open = sent · empty · void 아닌 것) 로 거른 qbo_cost_sheet 행 + 상태별 수 + since · 스위치 · epoch_now · 화면(3-4) Cost days';

-- ═══════════════ ⑧ 보류 결정 (판정 1099 · 이견 6) ═══════════════
create function public.qbo_cost_hold_decide(p_key_kind text, p_key text, p_decision text, p_note text default null) returns jsonb
  language plpgsql volatile security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(true); v_realm text := public.qbo_realm_of(); v_n int;
begin
  if p_key_kind is distinct from 'ADJ' then raise exception 'Only an inventory adjustment (ADJ) held over the threshold takes a decision — receipts and cost adjustments open with the supplier bill round — nothing was saved'; end if;
  if nullif(btrim(coalesce(p_key, '')), '') is null then raise exception 'The adjustment number is required — nothing was saved'; end if;
  if p_decision is null then
    delete from public.qbo_cost_hold h where h.realm_id = v_realm and h.key_kind = 'ADJ' and h.doc_key = btrim(p_key);
    get diagnostics v_n = row_count;
    return jsonb_build_object('key_kind', 'ADJ', 'doc_key', btrim(p_key), 'decision', null, 'removed', v_n);
  end if;
  if p_decision not in ('send', 'never') then raise exception 'decision must be send or never (got %) — nothing was saved', p_decision; end if;
  if nullif(btrim(coalesce(p_note, '')), '') is null then raise exception 'Say why (a note is required for a hold decision) — nothing was saved'; end if;
  if not exists (select 1 from public.inv_adjust a where a.adjust_number = btrim(p_key)) then raise exception 'Adjustment % does not exist — nothing was saved', btrim(p_key); end if;
  if exists (select 1 from public.qbo_cost_sent t where t.realm_id = v_realm and t.key_kind = 'ADJ' and t.doc_key = btrim(p_key)) and p_decision = 'never' then
    raise exception 'Adjustment % already went to QuickBooks in part — it cannot be marked never (the next sheet would not reverse it) — nothing was saved', btrim(p_key);
  end if;
  insert into public.qbo_cost_hold (realm_id, key_kind, doc_key, decision, note, decided_by, updated_by)
  values (v_realm, 'ADJ', btrim(p_key), p_decision, btrim(p_note), v_staff, v_staff)
  on conflict (realm_id, key_kind, doc_key) do update set decision = excluded.decision, note = excluded.note, decided_by = excluded.decided_by, decided_at = now(), updated_by = excluded.updated_by;
  return jsonb_build_object('key_kind', 'ADJ', 'doc_key', btrim(p_key), 'decision', p_decision, 'by_staff', v_staff);
end;
$$;
comment on function public.qbo_cost_hold_decide(text, text, text, text) is '[qbo-sync-3-2a · 판정 1099 · 이견 6] 문턱을 넘은 재고 조정(ADJ)의 결정(열쇠 qbo 쓰기) — send(보통 줄로 보낸다) | never(보내지 않는다 · 월 검산 제외 칸) | null(결정 지움 → 다시 보류) · note 필수 · 이미 일부 보낸 조정은 never 불가 · 입고 · 원가 조정 보류는 받지 않는다(Bill · BillPayment 차수)';

create function public.qbo_cost_hold_list() returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of();
begin
  return jsonb_build_object('threshold', (select c.value from public.inv_config c where c.key = 'qbo_cost_adjust_hold_over'),
    'holds', coalesce((select jsonb_agg(jsonb_build_object('wh', e.wh_code, 'key_kind', e.key_kind, 'doc_key', e.doc_key, 'acct_a', e.acct_a, 'acct_b', e.acct_b, 'cents', e.cents, 'reason', e.reason, 'first_on', e.first_on, 'last_on', e.last_on, 'takes_decision', e.key_kind = 'ADJ') order by e.first_on, e.doc_key, e.acct_a)
                        from public.qbo_cost_expected(public.ims_today(), null, v_realm) e where e.status = 'hold'), '[]'::jsonb),
    'decisions', coalesce((select jsonb_agg(jsonb_build_object('key_kind', h.key_kind, 'doc_key', h.doc_key, 'decision', h.decision, 'note', h.note, 'decided_at', h.decided_at, 'by_name', (select s.name from public.ims_staff s where s.id = h.decided_by)) order by h.decided_at desc)
                            from public.qbo_cost_hold h where h.realm_id = v_realm), '[]'::jsonb));
end;
$$;
comment on function public.qbo_cost_hold_list() is '[qbo-sync-3-2a · 판정 1096 · 1099] 지금 보류 중인 열쇠(오늘까지의 기대값 · 입고 RCV · 원가 조정 CADJ · 문턱 조정 ADJ)와 내린 결정 목록(열쇠 qbo · qbo:read)';

-- ═══════════════ ⑨ 월 검산 (판정 1086 · §15-h ⑦ · 이견 12: 뷰가 아니라 함수) ═══════════════
-- 등식(그달 · 창고): IMS 재고 금액 움직임(출처 경계 · 트랜스퍼 복사 carried 제외 · 재고 계정 #59 · #1150040007 쪽 합) = 보낸 장의 재고 쪽 + 보내는 중 + 아직 안 보낸 send + 보류 + 제외 + 반올림
-- 판매 원가 쪽: IMS 판매 원가(#58 쪽 합 · sale − restock + reversal + cost_late 판매 몫) ↔ 보낸 #58 · 503(출발점)은 섞지 않는다 · QBO 쪽은 첫 판에 사람이 기간 보고서와 맞댄다
create function public.qbo_cost_month(p_month date, p_wh text default null) returns jsonb
  language plpgsql stable security definer set search_path = public, pg_temp
as $$
declare v_staff uuid := public.qbo_key_gate(false); v_realm text := public.qbo_realm_of(); v_since date := (select nullif(btrim(c.value), '')::date from public.inv_config c where c.key = 'qbo_cost_since');
        v_from date; v_to date; r record; v_sent record; v_out jsonb;
begin
  if p_month is null then raise exception 'month is required — nothing was read'; end if;
  if p_wh is not null and p_wh not in ('TOR', 'EDM') then raise exception 'warehouse must be TOR or EDM (got %) — nothing was read', p_wh; end if;
  v_from := greatest(date_trunc('month', p_month)::date, v_since);
  v_to := (date_trunc('month', p_month) + interval '1 month - 1 day')::date;
  if v_from > v_to then return jsonb_build_object('month', to_char(p_month, 'YYYY-MM'), 'wh', p_wh, 'empty', true, 'reason', 'before qbo_cost_since ' || v_since::text); end if;
  select
    coalesce(sum(case when e.status <> 'block' then (case when e.acct_a in ('_59_', '_1150040007_') then e.raw_amount else 0 end) - (case when e.acct_b in ('_59_', '_1150040007_') then e.raw_amount else 0 end) end), 0) as ims_inv,
    coalesce(sum(case when e.status = 'send' then (case when e.acct_a in ('_59_', '_1150040007_') then e.cents else 0 end) - (case when e.acct_b in ('_59_', '_1150040007_') then e.cents else 0 end) end), 0) as send_inv_cents,
    coalesce(sum(case when e.status = 'send' then (case when e.acct_a in ('_59_', '_1150040007_') then e.raw_amount else 0 end) - (case when e.acct_b in ('_59_', '_1150040007_') then e.raw_amount else 0 end) end), 0) as send_inv_raw,
    coalesce(sum(case when e.status = 'hold' then (case when e.acct_a in ('_59_', '_1150040007_') then e.raw_amount else 0 end) - (case when e.acct_b in ('_59_', '_1150040007_') then e.raw_amount else 0 end) end), 0) as hold_inv,
    coalesce(sum(case when e.status = 'excluded' then (case when e.acct_a in ('_59_', '_1150040007_') then e.raw_amount else 0 end) - (case when e.acct_b in ('_59_', '_1150040007_') then e.raw_amount else 0 end) end), 0) as excl_inv,
    coalesce(sum(case when e.status = 'send' then (case when e.acct_a = '_58_' then e.raw_amount else 0 end) - (case when e.acct_b = '_58_' then e.raw_amount else 0 end) end), 0) as ims_cogs,
    coalesce(sum(case when e.status = 'send' then (case when e.acct_a = '_58_' then e.cents else 0 end) - (case when e.acct_b = '_58_' then e.cents else 0 end) end), 0) as send_cogs_cents,
    count(*) filter (where e.status = 'block') as n_block, count(distinct e.doc_key) filter (where e.status = 'send') as n_keys, count(distinct e.doc_key) filter (where e.status = 'hold') as n_hold,
    count(distinct e.doc_key) filter (where e.status = 'send' and e.key_kind = 'SO' and '_58_' in (e.acct_a, e.acct_b)) as n_so
    into r
  from public.qbo_cost_expected(v_to, v_from, v_realm) e where p_wh is null or e.wh_code = p_wh;
  select
    coalesce(sum(case when s.state = 'sent' then (case when t.acct_a in ('_59_', '_1150040007_') then t.cents else 0 end) - (case when t.acct_b in ('_59_', '_1150040007_') then t.cents else 0 end) end), 0) as sent_inv_cents,
    coalesce(sum(case when s.state in ('sending', 'unknown') then (case when t.acct_a in ('_59_', '_1150040007_') then t.cents else 0 end) - (case when t.acct_b in ('_59_', '_1150040007_') then t.cents else 0 end) end), 0) as inflight_inv_cents,
    coalesce(sum(case when s.state = 'sent' then (case when t.acct_a = '_58_' then t.cents else 0 end) - (case when t.acct_b = '_58_' then t.cents else 0 end) end), 0) as sent_cogs_cents,
    count(distinct s.id) filter (where s.state = 'sent') as n_sheets_sent
    into v_sent
  from public.qbo_cost_sent t join public.qbo_cost_sheet s on s.id = t.sheet_id
  where t.realm_id = v_realm and s.sheet_date between v_from and v_to and (p_wh is null or t.wh = p_wh);
  v_out := jsonb_build_object(
    'month', to_char(p_month, 'YYYY-MM'), 'wh', p_wh, 'from', v_from, 'to', v_to,
    'inventory', jsonb_build_object(
      'ims_delta', round(r.ims_inv, 2),
      'sent', round(v_sent.sent_inv_cents / 100.0, 2), 'in_flight', round(v_sent.inflight_inv_cents / 100.0, 2),
      'unsent', round((r.send_inv_cents - v_sent.sent_inv_cents - v_sent.inflight_inv_cents) / 100.0, 2),
      'hold', round(r.hold_inv, 2), 'excluded', round(r.excl_inv, 2),
      'rounding', round(r.send_inv_raw - r.send_inv_cents / 100.0, 2),
      'residual', round(r.ims_inv - (r.send_inv_raw + r.hold_inv + r.excl_inv), 2)),
    'cogs', jsonb_build_object('ims_cogs', round(r.ims_cogs, 2), 'sent', round(v_sent.sent_cogs_cents / 100.0, 2), 'unsent', round((r.send_cogs_cents - v_sent.sent_cogs_cents) / 100.0, 2), 'rounding', round(r.ims_cogs - r.send_cogs_cents / 100.0, 2), 'so_count', r.n_so),
    'counts', jsonb_build_object('send_keys', r.n_keys, 'hold_keys', r.n_hold, 'blocks', r.n_block, 'sheets_sent', v_sent.n_sheets_sent,
      'sheets', (select coalesce(jsonb_object_agg(x.state, x.n), '{}'::jsonb) from (select s.state, count(*) as n from public.qbo_cost_sheet s where s.realm_id = v_realm and s.sheet_date between v_from and v_to and (p_wh is null or s.wh = p_wh) group by s.state) x)),
    'note', 'inventory: ims_delta = sent + in_flight + unsent + hold + excluded + rounding (residual must be 0.00) · cogs: ims_cogs = sent + unsent + rounding · opening balance (deferred 503) is not in this view · late diffs sent in a later month show there');
  return v_out;
end;
$$;
comment on function public.qbo_cost_month(date, text) is '[qbo-sync-3-2a · 판정 1086 · §15-h ⑦ · 이견 12] 월 검산(열쇠 qbo · qbo:read) — 그달(qbo_cost_since 뒤) · 창고(null = 둘 다)의 IMS 재고 금액 움직임(재고 계정 쪽 합 · 출처 경계 · 트랜스퍼 복사 carried 제외) = 보낸 + 보내는 중 + 아직 안 보낸 + 보류 + 제외 + 반올림(residual 0.00 이어야) · 판매 원가 쪽 IMS #58 ↔ 보낸 #58 · 503(출발점)은 안 섞는다 · QBO 쪽은 첫 판에 사람이 기간 보고서와 맞댄다';

-- ═══════════════ ⑩ grant — 열쇠 창구 authenticated(+ service_role) · 속 함수 · cron 몸은 grant 0 ═══════════════
revoke all on function public.qbo_cost_wh_code(text), public.qbo_cost_wh_name(text), public.qbo_cost_excluded_docs(), public.qbo_cost_charge_account(text), public.qbo_cost_layer_wh(text, text),
  public.qbo_cost_expected(date, date, text), public.qbo_cost_sheet_calc(date, text, text), public.qbo_cost_sheet_build(date, text, text), public.qbo_cost_sheet_build_due(text),
  public.qbo_cost_build_now(), public.qbo_cost_preview(date, text), public.qbo_cost_sheet_list(date, date, text, text), public.qbo_cost_hold_decide(text, text, text, text), public.qbo_cost_hold_list(), public.qbo_cost_month(date, text)
  from public, anon, authenticated, service_role;
grant execute on function public.qbo_cost_wh_code(text), public.qbo_cost_wh_name(text), public.qbo_cost_excluded_docs(), public.qbo_cost_charge_account(text) to authenticated, service_role;   -- 상수 넷은 열어 둔다(화면 꼬리표)
grant execute on function public.qbo_cost_expected(date, date, text), public.qbo_cost_sheet_calc(date, text, text), public.qbo_cost_sheet_build(date, text, text), public.qbo_cost_layer_wh(text, text) to service_role;   -- 3-2b 의 claim · 몸(service) 이 부른다
grant execute on function public.qbo_cost_build_now(), public.qbo_cost_preview(date, text), public.qbo_cost_sheet_list(date, date, text, text), public.qbo_cost_hold_decide(text, text, text, text), public.qbo_cost_hold_list(), public.qbo_cost_month(date, text) to authenticated, service_role;
