-- supabase/migrations/20261108150000_qbo_sync_3_1_account_currency.sql — qbo-sync-3-1: 원가 · 공급처 줄기 첫 차수 = 데이터 바로잡기 (2026-11-08 밤 · 지시서 ~/asung/prompts/qbo-sync-3-1.md · 이견 1 ~ 10 답 · 판정 1087 · 1088 · 1090 · ⭐ 1091 · deferred 499 · so-module §104 · qbo-integration §15-a · §15-e ①)
-- ⭐ 판정 1091(Caleb 2026-11-08 밤 「정본을 뒤집더라도 ㄱ으로」): ref_account.currency_code text null 을 더한다 · null = 기준 통화(inv_config base_currency = CAD) · 채움 _109_ USD · _212_ USD · _203_ KRW · FK 없음(KRW 가 ref_currency 에 없다)
--    ⚠️ po-module §11-h(3369 행 근처) 「계좌에 통화 칸」 기각(결제 계좌 · 「통화는 공급처에서 내려온다 · 같은 사실이 두 곳」)을 **뒤집는다** — A/P · A/R 통제 계정의 통화는 QBO 가 계정 자체에 박아 둔 사실(계정 하나 = 통화 하나)이지 공급처에서 내려오는 값이 아니고, 막기는 바로 그 두 사실의 어긋남을 잡는 일이다.
--    은행 · 결제 계좌의 통화를 채우거나 쓰는 것은 이 차수 밖(1081 차수) · qbo_entity Account detail 은 238 행 모두 null(CurrencyRef 없음 · 실측) 이라 거울에 기댈 수 없다.
-- A. 판정 1087 — 조정 기본 계정: inv_config inv_adjust_default_account_code = _1150040010_(Inventory Discrepancy · 실재 · 활성 · qbo_link 1150040010 짝) · 해석 함수 inv_adjust_account(adj) → (account_id · account_code · is_default) — inv_adjust.account_code 가 있으면 그것 · 비면 기본 · 늘어남 · 줄어듦 같은 계정
--    확정 41 건(10-31 ~ 11-06 · account_code 모두 null · draft 4 도 null)에는 값을 써 넣지 않는다(이견 1 · 「비우면 기본」 이 판정의 뜻 · 기본을 바꾸면 모두 따라온다) · 다음 차수(하루 원가 장)가 이 함수만 읽는다 · ⚠️ 조정 계정을 고를 길은 아직 어디에도 없다(창구 셋이 account 를 안 받음 · 화면 0 줄 · RLS select 만) — 보고 · 새 deferred 후보
--    판정 572(ims_config_set): 계정 코드 키는 앱에서 못 바꾼다 — 새 키 다섯도 같다(ims_config_set 은 「편집 목록에 없는 기존 키」 를 전부 「a migration or psql changes this」 로 거부) · Settings 화면 노출 없음
-- B. 판정 1088 — 공급처 A/P 통화: ① CAD 공급처 11 곳(활성 8 · 비활성 3 · 실측 2026-11-08)의 account_payable _109_(A/P USD) → _62_(A/P) · 수가 11 이 아니면 멈춤 · USD 공급처 184 는 모두 _109_(어긋남 0)
--    ② 기본값을 통화별로(이견 4): supplier_default_account_payable_code_cad = _62_ · _usd = _109_ · 옛 키 supplier_default_account_payable_code(_109_) 는 값 무변 폴백 · KRW 키 없음(ref_currency 는 CAD · USD 둘뿐 → KRW 공급처를 만들 수 없다) · supplier_create 는 통화 블록을 계정 블록 앞으로
--    ③ 막기(이견 5): deferrable initially deferred constraint trigger(선례 so_line_combo_parent_ck) — supplier_update · customer_update 가 바뀐 칸마다 UPDATE 를 따로 날리므로 즉시 트리거면 「통화 → 계정」 순서로 보내도 첫 UPDATE 에서 막힌다 · 지연이면 한 트랜잭션(= 한 저장) 안에서 함께 바꾸면 통과 · 트리거는 NEW 가 아니라 지금 행을 다시 읽는다(한 트랜잭션의 묵은 사건) · 통화 null 또는 계정 null 이면 비교할 것이 없어 통과(지금 0 행)
--       거부 글(빠져나오는 길 같은 줄 · ims_account_currency_msg 한 곳): 「Supplier X: payable account _109_ is in USD but the supplier currency is CAD — change the currency and the account together in one save, or pick a CAD payable account — nothing was saved」
--       창구 넷(supplier_create · supplier_update · customer_create · customer_update)의 글자 추론 warn(ref_account.name ilike '%USD%' · 「Confirm to create anyway」)은 같은 규칙(currency_code 기준)의 **block** 으로 — Confirm 해도 트리거가 막으니 경고는 거짓말이 된다 · update 둘은 「이 호출이 끝난 뒤의 짝」 을 공급처 · 손님마다 한 번 본다
-- C. deferred 499 — 손님 A/R 통화(1088 과 같은 방식): USD 손님 3(so 0 건 · 시험 손님 하나 포함 · 이견 7 「셋 그대로」)의 ar_account _61_(A/R) → _212_(A/R USD · 실재 · 활성 · qbo_link 212 짝) · 수가 3 이 아니면 멈춤 · customer_default_ar_account_code_cad = _61_ · _usd = _212_ · 옛 키(_61_) 폴백 · 막기 = 트리거 customer_account_currency_ck + 창구 block
--    ⬜3 답(이견 8): qbo_refund_block 은 so_payment.currency_code <> base_currency 를 본다(A/R 계정을 보지 않는다) → 이 고침으로 USD 환불 failed 는 **풀리지 않는다** · 블록은 안 고친다(지시) · qbo_refund_purchase_head 는 손님 ar_account_code 를 읽으므로 블록이 풀리는 날 _212_ 가 간다
-- D. 하지 않는 것: QBO 쓰기 · EF · cron · 화면 0 · product.inventory_account_code = _58_ 1 행(보고만) · 공급처 결제 계좌(1081) · 하루 원가 장(1082 ~)
-- ⚠️ 공개 레포 — 이 파일 · 시험 · 보고에 손님 · 공급처 상호를 적지 않는다(id · 수만) · 적재(ImsLoadSupplier)는 Cin7 AccountPayable 을 그대로 쓰므로 다시 돌리면 그 11 행이 트리거에 거부된다(Cin7 수집은 멈춤 · 보고만 · 이견 6)
-- 데이터 고침의 updated_by: ims_touch 는 auth.uid() 가 null(psql)이면 updated_by 를 null 로 덮는다 → 11 + 3 행 고치는 동안 touch 트리거를 잠시 끄고 updated_at 만 손으로(직원이 손댄 표식 updated_by 를 지우지 않으려고 · 적재가 그 표식을 읽는다)
-- 몸 = DB prosrc 원본(2026-11-08 · supplier_create 286f12f3 · supplier_update 6e26a069 · customer_create d3164444 · customer_update 609b22f2 · ⓪ 이 md5 를 확인하고 다르면 멈춤) + 끼운 줄([qbo-sync-3-1] 표시) · 시그니처 · definer · volatility · search_path · acl 그대로(create or replace · drop 없음)
-- 검증 supabase/tests/qbo_sync_3_1_check.sql(운영 메인 begin → rollback · 데이터 11 · 3 · 막기 거부 · 함께 바꾸면 통과 · 기본값 통화별 · 조정 해석 45 · WHERE 정적 · 572 거부) · 적용은 Caleb(psql -1 -f · migration repair) · supabase db push 금지
-- ⚠️ jsonb_build_object 안에 「--」 줄 주석을 두지 마라(so-detail-keys-1) — 이 파일의 끼운 주석은 문장 끝 · 제 줄에만

-- ═══════════════ ⓪ 바탕 확인 — 네 창구의 몸이 이 파일을 지은 그 몸인가 · 대상 행 수가 실측과 같은가 ═══════════════
do $$
declare v_bad text := '';
  v_want jsonb := '{"supplier_create":"286f12f3666dd98936b89aa53507abcf","supplier_update":"6e26a069b0567783cdb77bd086f9e410","customer_create":"d3164444053eb4017f98a2bb6cd19b27","customer_update":"609b22f22fd09864acd2d0268fdfe4d7"}'::jsonb;
  r record; v_n int;
begin
  for r in select p.proname, md5(p.prosrc) as m from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('supplier_create', 'supplier_update', 'customer_create', 'customer_update') loop
    if r.m <> (v_want->>r.proname) then v_bad := v_bad || format(' · %s %s(기대 %s)', r.proname, left(r.m, 8), left(v_want->>r.proname, 8)); end if;
  end loop;
  if (select count(*) from pg_proc p where p.pronamespace = 'public'::regnamespace and p.proname in ('supplier_create', 'supplier_update', 'customer_create', 'customer_update')) <> 4 then v_bad := v_bad || ' · 창구 넷이 아니다'; end if;
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'ref_account' and column_name = 'currency_code') then v_bad := v_bad || ' · ref_account.currency_code 가 이미 있다'; end if;
  if exists (select 1 from public.inv_config where key in ('inv_adjust_default_account_code', 'supplier_default_account_payable_code_cad', 'supplier_default_account_payable_code_usd', 'customer_default_ar_account_code_cad', 'customer_default_ar_account_code_usd')) then v_bad := v_bad || ' · 새 inv_config 키가 이미 있다'; end if;
  if (select count(*) from public.ref_currency where is_active) <> 2 or (select string_agg(code, ',' order by code) from public.ref_currency where is_active) <> 'CAD,USD' then v_bad := v_bad || ' · ref_currency 가 CAD · USD 둘이 아니다(KRW 키 판단이 바뀐다)'; end if;
  if (select count(*) from public.ref_account where code in ('_62_', '_109_', '_61_', '_212_', '_1150040010_', '_203_') and is_active) <> 6 then v_bad := v_bad || ' · 계정 여섯(_62_ _109_ _61_ _212_ _1150040010_ _203_)이 활성으로 다 있지 않다'; end if;
  if coalesce((select value from public.inv_config where key = 'base_currency'), '') <> 'CAD' then v_bad := v_bad || ' · base_currency 가 CAD 가 아니다'; end if;
  if v_bad <> '' then raise exception '⓪ DB differs from what this migration was built on:% — rebuild from the current bodies first — nothing was changed', v_bad; end if;
end $$;

-- ═══════════════ ① ref_account.currency_code (판정 1091) ═══════════════
alter table public.ref_account add column currency_code text;
alter table public.ref_account add constraint ref_account_currency_code_ck check (currency_code is null or currency_code ~ '^[A-Z]{3}$');
comment on column public.ref_account.currency_code is '[qbo-sync-3-1 · 판정 1091] 계정의 통화(ISO 세 글자) · null = 기준 통화(inv_config base_currency · CAD) · A/P · A/R 통제 계정만 채운다(_109_ USD · _212_ USD · _203_ KRW) · FK 없음(KRW 가 ref_currency 에 없다) · 공급처 · 손님 저장 때 「계정 통화 = 공급처 · 손님 통화」 를 트리거가 본다(ims_account_currency) · ⚠️ 은행 · 결제 계좌의 통화는 여기 채우지 않는다(1081 차수 몫 · po-module 11-h 기각을 1091 이 A/P · A/R 에 한해 뒤집음)';
do $$
declare v_n int;
begin
  update public.ref_account set currency_code = case code when '_109_' then 'USD' when '_212_' then 'USD' when '_203_' then 'KRW' end where code in ('_109_', '_212_', '_203_');
  get diagnostics v_n = row_count;
  if v_n <> 3 then raise exception '① ref_account currency fill touched % rows (expected 3: _109_ · _212_ · _203_) — nothing was changed', v_n; end if;
end $$;

-- ═══════════════ ② inv_config 키 다섯 (1087 · 1088 · 499 · 판정 572: 앱에서 못 바꾼다 · 마이그레이션 · psql 만) ═══════════════
insert into public.inv_config (key, value, note) values
  ('inv_adjust_default_account_code', '_1150040010_', '[qbo-sync-3-1 · 판정 1087] 재고 조정의 맞은편 계정 기본 — inv_adjust.account_code 가 비면 이것(늘어남 · 줄어듦 같은 계정) · ref_account.code 를 가리킨다(FK 없음 — key-value 표) · _1150040010_ Inventory Discrepancy(COGS) · 읽는 곳 = inv_adjust_account(adj) 한 곳 · 바꾸기는 마이그레이션(572) · 2026-11-08'),
  ('supplier_default_account_payable_code_cad', '_62_', '[qbo-sync-3-1 · 판정 1088] 새 CAD 공급처의 A/P 계정 기본 — supplier_create 가 통화를 먼저 정하고 supplier_default_account_payable_code_<통화 소문자> 를 읽는다 · 없으면 옛 키 supplier_default_account_payable_code 폴백 · _62_ Accounts Payable (A/P) · 2026-11-08'),
  ('supplier_default_account_payable_code_usd', '_109_', '[qbo-sync-3-1 · 판정 1088] 새 USD 공급처의 A/P 계정 기본 — _109_ Accounts Payable (A/P) - USD · KRW 키는 없다(ref_currency 에 KRW 없음) · 2026-11-08'),
  ('customer_default_ar_account_code_cad', '_61_', '[qbo-sync-3-1 · deferred 499 · 판정 1088] 새 CAD 손님의 A/R 계정 기본 — customer_create 가 customer_default_ar_account_code_<통화 소문자> 를 읽는다 · 없으면 옛 키 customer_default_ar_account_code 폴백 · _61_ Accounts Receivable (A/R) · 2026-11-08'),
  ('customer_default_ar_account_code_usd', '_212_', '[qbo-sync-3-1 · deferred 499 · 판정 1088] 새 USD 손님의 A/R 계정 기본 — _212_ Accounts Receivable (A/R) - USD · 2026-11-08');
do $$
begin
  execute format('comment on table public.inv_config is %L', coalesce(obj_description('public.inv_config'::regclass, 'pg_class'), '') || ' · [qbo-sync-3-1] 계정 키 다섯 더함: inv_adjust_default_account_code(1087) · supplier_default_account_payable_code_cad · _usd(1088 · 옛 키는 폴백) · customer_default_ar_account_code_cad · _usd(499) — 모두 572 거부 목록(편집 목록 밖 기존 키 = 「a migration or psql changes this」)');
end $$;

-- ═══════════════ ③ 도우미 둘 — 계정의 통화 · 거부 글 한 곳 ═══════════════
create or replace function public.ims_account_currency(p_account_id uuid)
  returns text
  language sql stable security invoker
  set search_path = public, pg_temp
as $$
  select coalesce(a.currency_code, coalesce(nullif(btrim((select c.value from public.inv_config c where c.key = 'base_currency')), ''), 'CAD'))
  from public.ref_account a where a.id = p_account_id;
$$;
comment on function public.ims_account_currency(uuid) is '[qbo-sync-3-1 · 판정 1091] 계정의 통화 — ref_account.currency_code · null 이면 기준 통화(inv_config base_currency · 없으면 CAD) · 계정이 없으면 null · 공급처 · 손님 저장의 「계정 통화 = 통화」 검사(트리거 둘 · 창구 넷)가 이것 하나를 읽는다';

create or replace function public.ims_account_currency_msg(p_kind text, p_name text, p_account_label text, p_account_code text, p_account_currency text, p_currency text)
  returns text
  language sql immutable
  set search_path = public, pg_temp
as $$
  select format('%s %s: %s account %s is in %s but the %s currency is %s — change the currency and the account together in one save, or pick a %s %s account — nothing was saved',
                p_kind, coalesce(p_name, '?'), p_account_label, coalesce(p_account_code, '?'), coalesce(p_account_currency, '?'), lower(p_kind), coalesce(p_currency, '?'), coalesce(p_currency, '?'), p_account_label);
$$;
comment on function public.ims_account_currency_msg(text, text, text, text, text, text) is '[qbo-sync-3-1 · 판정 1088] 「계정 통화 ≠ 통화」 거부 글 한 곳 — 빠져나오는 길을 같은 줄에(통화와 계정을 한 번의 저장에서 함께 · 또는 그 통화의 계정을 고르기) · 트리거 둘과 창구 넷이 같은 글을 낸다 · p_kind = Supplier | Customer · p_account_label = payable | receivable';

-- ═══════════════ ④ 데이터 고침 — 공급처 11 · 손님 3 (touch 트리거를 잠시 끄고 updated_at 만 손으로) ═══════════════
alter table public.supplier disable trigger supplier_touch;
alter table public.customer disable trigger customer_touch;
do $$
declare v_n int; v_cad uuid; v_usd uuid; v_62 public.ref_account%rowtype; v_212 public.ref_account%rowtype; v_109 public.ref_account%rowtype; v_61 public.ref_account%rowtype;
begin
  select id into v_cad from public.ref_currency where code = 'CAD';
  select id into v_usd from public.ref_currency where code = 'USD';
  select * into v_62  from public.ref_account where code = '_62_';
  select * into v_212 from public.ref_account where code = '_212_';
  select * into v_109 from public.ref_account where code = '_109_';
  select * into v_61  from public.ref_account where code = '_61_';
  -- 1088 ①: CAD 공급처의 A/P _109_ → _62_ (활성 · 비활성 모두 · 실측 11)
  select count(*) into v_n from public.supplier s where s.currency_id = v_cad and s.account_payable_code = '_109_';
  if v_n <> 11 then raise exception '④ CAD suppliers with payable account _109_ = % (this migration was built on 11) — nothing was changed', v_n; end if;
  update public.supplier s set account_payable_id = v_62.id, account_payable_code = v_62.code, updated_at = now() where s.currency_id = v_cad and s.account_payable_code = '_109_';
  get diagnostics v_n = row_count;
  if v_n <> 11 then raise exception '④ supplier fix touched % rows (expected 11) — nothing was changed', v_n; end if;
  -- 499: USD 손님의 A/R _61_ → _212_ (실측 3 · 시험 손님 포함)
  select count(*) into v_n from public.customer c where c.currency_id = v_usd and c.ar_account_code = '_61_';
  if v_n <> 3 then raise exception '④ USD customers with receivable account _61_ = % (this migration was built on 3) — nothing was changed', v_n; end if;
  update public.customer c set ar_account_id = v_212.id, ar_account_code = v_212.code, updated_at = now() where c.currency_id = v_usd and c.ar_account_code = '_61_';
  get diagnostics v_n = row_count;
  if v_n <> 3 then raise exception '④ customer fix touched % rows (expected 3) — nothing was changed', v_n; end if;
  -- 고친 뒤 어긋남 0 — 트리거는 바뀌는 행만 보므로 남은 어긋남이 있으면 여기서 드러나야 한다
  select count(*) into v_n from public.supplier s join public.ref_currency r on r.id = s.currency_id where s.account_payable_id is not null and public.ims_account_currency(s.account_payable_id) <> r.code;
  if v_n <> 0 then raise exception '④ after the fix % supplier(s) still have a payable account in another currency — nothing was changed', v_n; end if;
  select count(*) into v_n from public.customer c where c.ar_account_id is not null and public.ims_account_currency(c.ar_account_id) <> coalesce((select r.code from public.ref_currency r where r.id = c.currency_id), c.currency_code);
  if v_n <> 0 then raise exception '④ after the fix % customer(s) still have a receivable account in another currency — nothing was changed', v_n; end if;
end $$;
alter table public.supplier enable trigger supplier_touch;
alter table public.customer enable trigger customer_touch;

-- ═══════════════ ⑤ 막기 — deferred constraint trigger 둘 (어느 길로 와도: 적재 REST · 창구 · 화면) ═══════════════
create or replace function public.supplier_account_currency_check()
  returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare v_s public.supplier%rowtype; v_cur text; v_acur text;
begin
  -- deferred 라 트랜잭션 끝에 돈다 — 한 트랜잭션 안의 묵은 사건(통화만 바꾼 UPDATE 뒤 계정을 바꾼 UPDATE)이 올 수 있다 ⇒ 지금 행을 다시 읽어 판정한다(없으면 볼 것이 없다)
  select * into v_s from public.supplier s where s.id = new.id;
  if not found or v_s.currency_id is null or v_s.account_payable_id is null then return null; end if;
  select r.code into v_cur from public.ref_currency r where r.id = v_s.currency_id;
  v_acur := public.ims_account_currency(v_s.account_payable_id);
  if v_cur is null or v_acur is null or v_cur = v_acur then return null; end if;
  raise exception using errcode = 'P0001', message = public.ims_account_currency_msg('Supplier', v_s.name, 'payable', v_s.account_payable_code, v_acur, v_cur);
end $$;
comment on function public.supplier_account_currency_check() is '[qbo-sync-3-1 · 판정 1088 · 1091] 트리거 supplier_account_currency_ck 의 몸 — 공급처 통화 ≠ A/P 계정 통화(ims_account_currency)면 거부 · deferred 라 지금 행을 다시 읽는다(한 저장에서 통화와 계정을 함께 바꾸면 통과) · 통화 또는 계정이 null 이면 통과 · 거부 글 = ims_account_currency_msg';
create constraint trigger supplier_account_currency_ck
  after insert or update of currency_id, account_payable_id, account_payable_code on public.supplier
  deferrable initially deferred for each row execute function public.supplier_account_currency_check();

create or replace function public.customer_account_currency_check()
  returns trigger
  language plpgsql
  set search_path = public, pg_temp
as $$
declare v_c public.customer%rowtype; v_cur text; v_acur text;
begin
  select * into v_c from public.customer c where c.id = new.id;
  if not found or v_c.ar_account_id is null then return null; end if;
  v_cur := coalesce((select r.code from public.ref_currency r where r.id = v_c.currency_id), nullif(btrim(coalesce(v_c.currency_code, '')), ''));
  v_acur := public.ims_account_currency(v_c.ar_account_id);
  if v_cur is null or v_acur is null or v_cur = v_acur then return null; end if;
  raise exception using errcode = 'P0001', message = public.ims_account_currency_msg('Customer', v_c.name, 'receivable', v_c.ar_account_code, v_acur, v_cur);
end $$;
comment on function public.customer_account_currency_check() is '[qbo-sync-3-1 · deferred 499 · 판정 1088 · 1091] 트리거 customer_account_currency_ck 의 몸 — 손님 통화(currency_id → ref_currency.code · 없으면 currency_code) ≠ A/R 계정 통화면 거부 · deferred · 지금 행을 다시 읽는다 · 통화 또는 A/R 계정이 null 이면 통과 · 거부 글 = ims_account_currency_msg';
create constraint trigger customer_account_currency_ck
  after insert or update of currency_id, currency_code, ar_account_id, ar_account_code on public.customer
  deferrable initially deferred for each row execute function public.customer_account_currency_check();

-- ═══════════════ ⑥-0 조정 계정 해석 (판정 1087) — 다음 차수(하루 원가 장)가 읽는 한 곳 ═══════════════
create or replace function public.inv_adjust_account(p_adjust_id uuid)
  returns table (account_id uuid, account_code text, is_default boolean)
  language plpgsql stable security invoker
  set search_path = public, pg_temp
as $$
declare v_a public.inv_adjust%rowtype; v_cfg text; v_id uuid;
begin
  select * into v_a from public.inv_adjust a where a.id = p_adjust_id;
  if not found then raise exception 'Adjustment % does not exist (or you cannot read it) — nothing was read', p_adjust_id; end if;
  if v_a.account_id is not null then
    return query select v_a.account_id, v_a.account_code, false;   -- 직원이 고른 계정(inv_adjust_account_ck: id 와 code 는 함께)
    return;
  end if;
  select nullif(btrim(c.value), '') into v_cfg from public.inv_config c where c.key = 'inv_adjust_default_account_code';
  if v_cfg is null then raise exception 'The default adjustment account is not set up (inv_config inv_adjust_default_account_code) — a migration sets it — nothing was read'; end if;
  select a.id into v_id from public.ref_account a where a.code = v_cfg and a.is_active;
  if v_id is null then raise exception 'The default adjustment account % does not exist or is inactive (inv_config inv_adjust_default_account_code) — nothing was read', v_cfg; end if;
  return query select v_id, v_cfg, true;
end $$;
comment on function public.inv_adjust_account(uuid) is '[qbo-sync-3-1 · 판정 1087] 재고 조정이 보낼 맞은편 계정 — inv_adjust.account_id · account_code 가 있으면 그것(is_default false) · 비면 inv_config inv_adjust_default_account_code(_1150040010_ Inventory Discrepancy · is_default true · 늘어남 · 줄어듦 같은 계정) · 확정 41 건은 값을 써 넣지 않고 이 함수가 기본을 준다 · 하루 원가 장(1082 ~) 이 조정 줄의 계정을 여기서만 읽는다 · invoker(inv_adjust RLS 그대로)';

-- ═══════════════ ⑥ 창구 넷 — DB prosrc 원본(pg_get_functiondef · 2026-11-08) + 끼운 줄 · 시그니처 · definer · search_path · acl 그대로(create or replace) ═══════════════

CREATE OR REPLACE FUNCTION public.supplier_create(p_supplier jsonb, p_commit boolean DEFAULT false, p_ack text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff    uuid;
  v_master   boolean;
  v_blocks   jsonb := '[]'::jsonb;
  v_warns    jsonb := '[]'::jsonb;
  v_defaults text[] := '{}';
  v_name     text;
  v_folded   text;
  v_money    text[] := array['currency_id', 'payment_term_id', 'account_payable_id', 'tax_rule', 'discounts'];
  v_given    text[];
  v_term     public.ref_payment_term%rowtype;
  v_cur      public.ref_currency%rowtype;
  v_acct     public.ref_account%rowtype;
  v_tax      text;
  v_cfg      text;
  v_a        jsonb;
  v_c        jsonb;
  v_d        jsonb;
  v_i        int;
  v_n_cdef   int := 0;
  v_pct      numeric;
  v_sid      uuid;
  v_rid      uuid;
  v_addr_ids jsonb := '[]'::jsonb;
  v_cont_ids jsonb := '[]'::jsonb;
  v_keys     text[];
  v_unacked  text[];
  v_sim      jsonb;
begin
  if not (public.ims_can_write('purchasing') or public.ims_can_write('master')) then
    raise exception 'You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if p_supplier is null or jsonb_typeof(p_supplier) <> 'object' then raise exception 'p_supplier must be a JSON object — nothing was saved'; end if;
  if p_supplier ? 'addresses' and jsonb_typeof(p_supplier->'addresses') <> 'array' then raise exception 'addresses must be a JSON array — nothing was saved'; end if;
  if p_supplier ? 'contacts'  and jsonb_typeof(p_supplier->'contacts')  <> 'array' then raise exception 'contacts must be a JSON array — nothing was saved'; end if;
  if p_supplier ? 'discounts' and jsonb_typeof(p_supplier->'discounts') <> 'array' then raise exception 'discounts must be a JSON array — nothing was saved'; end if;

  -- 이름(판정 238 · 공급처는 막는다 · 꺼진 것 포함 · 「(Supplier)」 를 뗀 이름이 같으면 알리기)
  v_name := nullif(btrim(p_supplier->>'name'), '');
  if v_name is null then
    v_blocks := v_blocks || jsonb_build_object('key', 'name_missing', 'code', 'name_missing', 'message', 'The supplier has no name — nothing was saved');
  else
    v_folded := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
    if exists (select 1 from public.supplier s where lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = v_folded) then
      v_blocks := v_blocks || jsonb_build_object('key', 'name_exists', 'code', 'name_exists', 'message', format('A supplier named "%s" already exists (%s) — the name is the key (Cin7 refers to suppliers by name) — reactivate or rename that one instead — nothing was saved', v_name,
        (select string_agg(s.name || case when s.is_active then '' else ' · inactive' end, '; ') from public.supplier s where lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = v_folded)));
    else
      select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'name', s.name, 'is_active', s.is_active) order by s.name), '[]'::jsonb) into v_sim from public.supplier s
       where regexp_replace(lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')), '\s*\(supplier\)$', '') = regexp_replace(v_folded, '\s*\(supplier\)$', '');
      if jsonb_array_length(v_sim) > 0 then
        v_warns := v_warns || jsonb_build_object('key', 'name_similar', 'code', 'name_similar', 'matches', v_sim, 'message', format('%s supplier(s) have almost the same name (%s) — is this the same company? Confirm to create anyway', jsonb_array_length(v_sim), (select string_agg(m->>'name', '; ') from jsonb_array_elements(v_sim) m)));
      end if;
    end if;
  end if;

  -- 돈 칸(master 만 · 아니면 기본값)
  select coalesce(array_agg(k order by k), '{}') into v_given from unnest(v_money) as k where p_supplier ? k and p_supplier->k <> 'null'::jsonb;
  if cardinality(v_given) > 0 and not v_master then
    v_blocks := v_blocks || jsonb_build_object('key', 'money_field_not_allowed', 'code', 'money_field_not_allowed', 'message', format('Only a master user can set %s on a new supplier — leave them out and the defaults apply — nothing was saved', array_to_string(v_given, ', ')));
  end if;
  if 'payment_term_id' = any(v_given) and v_master then
    select * into v_term from public.ref_payment_term t where t.id = (p_supplier->>'payment_term_id')::uuid and t.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'payment_term_invalid', 'code', 'payment_term_invalid', 'message', 'The payment term does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'supplier_default_payment_term';
    select * into v_term from public.ref_payment_term t where t.name = v_cfg and t.is_active;
    if v_cfg is null or not found then v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:payment_term', 'code', 'default_missing', 'message', format('The default payment term is not set up (inv_config supplier_default_payment_term = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'payment_term'); end if;
  end if;
  -- [qbo-sync-3-1 · 판정 1088] 통화를 먼저 정한다 — A/P 기본 계정이 통화별이라서(옛 순서: 계정 → 통화)
  if 'currency_id' = any(v_given) and v_master then
    select * into v_cur from public.ref_currency c where c.id = (p_supplier->>'currency_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'currency_invalid', 'code', 'currency_invalid', 'message', 'The currency does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'supplier_default_currency_code';
    select * into v_cur from public.ref_currency c where c.code = v_cfg and c.is_active;
    if v_cfg is null or not found then v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:currency', 'code', 'default_missing', 'message', format('The default currency is not set up (inv_config supplier_default_currency_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'currency'); end if;
  end if;
  if 'account_payable_id' = any(v_given) and v_master then
    select * into v_acct from public.ref_account a where a.id = (p_supplier->>'account_payable_id')::uuid and a.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'account_invalid', 'code', 'account_invalid', 'message', 'The payable account does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'supplier_default_account_payable_code_' || lower(v_cur.code);   -- [qbo-sync-3-1 · 1088] 통화별 기본(_cad · _usd) · 통화가 안 섰으면 null 키 → 폴백
    if v_cfg is null then select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'supplier_default_account_payable_code'; end if;   -- 옛 키 = 폴백(값 무변)
    select * into v_acct from public.ref_account a where a.code = v_cfg and a.is_active;
    if v_cfg is null or not found then v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:account_payable', 'code', 'default_missing', 'message', format('The default payable account is not set up (inv_config supplier_default_account_payable_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'account_payable'); end if;
  end if;
  if 'tax_rule' = any(v_given) and v_master then
    v_tax := nullif(btrim(p_supplier->>'tax_rule'), '');
  else
    select nullif(k.value, '') into v_tax from public.inv_config k where k.key = 'supplier_default_tax_rule';
    if v_tax is not null then v_defaults := array_append(v_defaults, 'tax_rule'); end if;           -- 세금 규칙은 원문 칸 · 비어도 막지 않는다(po_create 가 tax_rule_unset 알림)
  end if;
  if v_cur.id is not null and v_acct.id is not null and public.ims_account_currency(v_acct.id) <> v_cur.code then   -- [qbo-sync-3-1 · 판정 1088 · 1091] 계정 통화(ref_account.currency_code · null = 기준 통화) ≠ 공급처 통화 → 막기(옛 글자 추론 warn 「Confirm to create anyway」 는 거짓말이 된다 — 트리거가 막는다)
    v_blocks := v_blocks || jsonb_build_object('key', 'currency_account_mismatch', 'code', 'currency_account_mismatch', 'message', public.ims_account_currency_msg('Supplier', coalesce(v_name, '(new)'), 'payable', v_acct.code, public.ims_account_currency(v_acct.id), v_cur.code));
  end if;
  -- 할인(master 만 · 체인 순서 = 배열 순서)
  v_i := 0;
  for v_d in select x from jsonb_array_elements(coalesce(p_supplier->'discounts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_pct := case when (v_d->>'percent') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (v_d->>'percent')::numeric end;
    if nullif(btrim(v_d->>'name'), '') is null or v_pct is null or v_pct > 100 then
      v_blocks := v_blocks || jsonb_build_object('key', 'discount_invalid:' || v_i, 'code', 'discount_invalid', 'message', format('Discount %s needs a name and a percent from 0 to 100 — nothing was saved', v_i));
    end if;
  end loop;
  -- 일반 칸 값
  if nullif(btrim(p_supplier->>'is_purchasable'), '') is not null and btrim(p_supplier->>'is_purchasable') not in ('true', 'false') then
    v_blocks := v_blocks || jsonb_build_object('key', 'value_invalid:is_purchasable', 'code', 'value_invalid', 'message', 'is_purchasable must be true, false or null (not decided) — nothing was saved');
  end if;
  -- 주소 · 연락처
  v_i := 0;
  for v_a in select x from jsonb_array_elements(coalesce(p_supplier->'addresses', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    if nullif(btrim(coalesce(v_a->>'line1', '') || coalesce(v_a->>'city', '') || coalesce(v_a->>'postal_code', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'address_empty:' || v_i, 'code', 'address_empty', 'message', format('Address %s has no street, city or postal code — nothing was saved', v_i));
    end if;
  end loop;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_supplier->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    if nullif(btrim(coalesce(v_c->>'name', '') || coalesce(v_c->>'phone', '') || coalesce(v_c->>'mobile_phone', '') || coalesce(v_c->>'email', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'contact_empty:' || v_i, 'code', 'contact_empty', 'message', format('Contact %s has no name, phone or email — nothing was saved', v_i));
    end if;
    if coalesce((v_c->>'is_default')::boolean, false) then v_n_cdef := v_n_cdef + 1; end if;
  end loop;
  if v_n_cdef > 1 then v_blocks := v_blocks || jsonb_build_object('key', 'contact_default_many', 'code', 'contact_default_many', 'message', 'More than one contact is marked default — only one per supplier — nothing was saved'); end if;

  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'supplier_id', null, 'name', v_name, 'defaults_used', to_jsonb(v_defaults), 'address_ids', '[]'::jsonb, 'contact_ids', '[]'::jsonb,
                              'blocks', v_blocks, 'warnings', v_warns, 'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  begin
    insert into public.supplier (name, note, source, is_active, created_by, updated_by, payment_term_id, payment_term_name, account_payable_id, account_payable_code, currency_id, tax_rule, is_purchasable, is_discontinued, discontinued_on)
    values (v_name, nullif(btrim(p_supplier->>'note'), ''), 'manual', true, v_staff, v_staff, v_term.id, v_term.name, v_acct.id, v_acct.code, v_cur.id, v_tax,
            nullif(btrim(p_supplier->>'is_purchasable'), '')::boolean, coalesce((p_supplier->>'is_discontinued')::boolean, false),
            case when coalesce((p_supplier->>'is_discontinued')::boolean, false) then coalesce(nullif(p_supplier->>'discontinued_on', '')::date, public.ims_today()) end)
    returning id into v_sid;
  exception when unique_violation then
    raise exception 'Someone just created a supplier named "%" — check again — nothing was saved', v_name;
  end;
  v_i := 0;
  for v_d in select x from jsonb_array_elements(coalesce(p_supplier->'discounts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    insert into public.supplier_discount (supplier_id, name, percent, seq, source, updated_by) values (v_sid, btrim(v_d->>'name'), (v_d->>'percent')::numeric, v_i, 'manual', v_staff);
  end loop;
  for v_a in select x from jsonb_array_elements(coalesce(p_supplier->'addresses', '[]'::jsonb)) as x loop
    insert into public.supplier_address (supplier_id, source, updated_by, type, line1, line2, city, state_province, postal_code, country)
    values (v_sid, 'manual', v_staff, nullif(btrim(v_a->>'type'), ''), nullif(btrim(v_a->>'line1'), ''), nullif(btrim(v_a->>'line2'), ''), nullif(btrim(v_a->>'city'), ''), nullif(btrim(v_a->>'state_province'), ''), nullif(btrim(v_a->>'postal_code'), ''), nullif(btrim(v_a->>'country'), ''))
    returning id into v_rid;
    v_addr_ids := v_addr_ids || to_jsonb(v_rid);
  end loop;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_supplier->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    insert into public.supplier_contact (supplier_id, source, updated_by, name, phone, mobile_phone, fax, email, website, is_default)
    values (v_sid, 'manual', v_staff, nullif(btrim(v_c->>'name'), ''), nullif(btrim(v_c->>'phone'), ''), nullif(btrim(v_c->>'mobile_phone'), ''), nullif(btrim(v_c->>'fax'), ''), nullif(btrim(v_c->>'email'), ''), nullif(btrim(v_c->>'website'), ''),
            case when v_n_cdef = 1 then coalesce((v_c->>'is_default')::boolean, false) else v_i = 1 end)
    returning id into v_rid;
    v_cont_ids := v_cont_ids || to_jsonb(v_rid);
  end loop;
  return jsonb_build_object('committed', true, 'supplier_id', v_sid, 'name', v_name, 'defaults_used', to_jsonb(v_defaults), 'address_ids', v_addr_ids, 'contact_ids', v_cont_ids, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.supplier_update(p_changes jsonb, p_commit boolean DEFAULT false, p_ack text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff   uuid;
  v_master  boolean;
  v_blocks  jsonb := '[]'::jsonb;
  v_warns   jsonb := '[]'::jsonb;
  v_changes jsonb := '[]'::jsonb;
  v_recalc  uuid[] := '{}';   v_recalc_out jsonb := null;   -- ldfix-1c2 · 판정 682 · 683: 켜고 끈 공급처 → 그 제품들의 기본 공급처 재계산
  v_money   text[] := array['currency_id', 'payment_term_id', 'account_payable_id', 'tax_rule', 'is_active'];
  v_general text[] := array['name', 'note', 'is_purchasable', 'is_discontinued', 'discontinued_on'];
  v_afields text[] := array['type', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country'];
  v_cfields text[] := array['name', 'phone', 'mobile_phone', 'fax', 'email', 'website'];
  v_mops    text[] := array['discount_add', 'discount_set', 'discount_off'];
  v_n       int;
  v_i       int := 0;
  v_eff_cur text;   v_eff_acct uuid;   -- [qbo-sync-3-1] 이 호출이 끝난 뒤의 (통화 · A/P 계정) 짝
  v_c       jsonb;
  v_op      text;
  v_field   text;
  v_sid     uuid;
  v_key     text;
  v_sup     public.supplier%rowtype;
  v_cur     text;
  v_new     text;
  v_seen    text[] := '{}';
  v_touched uuid[] := '{}';
  v_money_s uuid[] := '{}';
  v_a       public.supplier_address%rowtype;
  v_ct      public.supplier_contact%rowtype;
  v_dsc     public.supplier_discount%rowtype;
  v_vals    jsonb;
  v_olds    jsonb;
  v_f       text;
  v_folded  text;
  v_open_po int;
  v_open_inv int;
  v_prods   int;
  v_forms   int;
  v_pct     numeric;
  v_keys    text[];
  v_unacked text[];
  v_rid     uuid;
  v_newdef  text[] := '{}';
begin
  if not (public.ims_can_write('purchasing') or public.ims_can_write('master')) then
    raise exception 'You cannot change purchasing data — ask an admin to add the ''purchasing'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;
  if p_changes is null or jsonb_typeof(p_changes) <> 'array' then raise exception 'p_changes must be a JSON array of changes — nothing was saved'; end if;
  v_n := jsonb_array_length(p_changes);
  if v_n = 0 then raise exception 'No changes given — nothing was saved'; end if;
  if v_n > 1000 then raise exception 'Too many changes in one call (% — the limit is 1,000) — nothing was saved', v_n; end if;
  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_op := v_c->>'op';
    if v_op is null or v_op not in ('set', 'discount_add', 'discount_set', 'discount_off', 'address_add', 'address_set', 'address_off', 'contact_add', 'contact_set', 'contact_off', 'contact_default') then
      raise exception 'Unknown op % — one of set · discount_add · discount_set · discount_off · address_add · address_set · address_off · contact_add · contact_set · contact_off · contact_default — nothing was saved', coalesce(v_op, '(blank)');
    end if;
    if v_op = 'contact_add' and coalesce((v_c->'values'->>'is_default')::boolean, false) then v_newdef := array_append(v_newdef, coalesce(v_c->>'supplier_id', '')); end if;
    if v_op = 'contact_default' then v_newdef := array_append(v_newdef, coalesce(v_c->>'supplier_id', '')); end if;
  end loop;

  for v_c in select x from jsonb_array_elements(p_changes) as x loop
    v_i := v_i + 1;
    v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_sid := nullif(v_c->>'supplier_id', '')::uuid; v_key := coalesce(v_sid::text, '(blank)');
    v_changes := v_changes || jsonb_build_object('i', v_i, 'supplier_id', v_sid, 'op', v_op, 'field', v_field, 'applied', false);
    select * into v_sup from public.supplier s where s.id = v_sid;
    if v_sid is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', v_key || ':supplier_unknown', 'supplier_id', v_sid, 'code', 'supplier_unknown', 'message', format('Change %s: the supplier does not exist — nothing was saved', v_i)); continue;
    end if;
    v_touched := array_append(v_touched, v_sid);
    v_vals := coalesce(v_c->'values', '{}'::jsonb); v_olds := coalesce(v_c->'olds', '{}'::jsonb);

    if v_op = 'set' then
      if v_field is null or not (v_field = any(v_general) or v_field = any(v_money)) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:' || coalesce(v_field, '(blank)'), 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: field %s cannot be changed here — nothing was saved', v_sup.name, coalesce(v_field, '(blank)'))); continue;
      end if;
      if (v_key || ':' || v_field) = any(v_seen) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:' || v_field, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s %s is changed twice in this call — keep one — nothing was saved', v_sup.name, v_field)); continue;
      end if;
      v_seen := array_append(v_seen, v_key || ':' || v_field);
      if v_field = any(v_money) and not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_field, 'supplier_id', v_sid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change %s of %s — nothing was saved', v_field, v_sup.name)); continue;
      end if;
      if not (v_c ? 'old') then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:' || v_field, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s %s: the old value the screen saw is missing — nothing was saved', v_sup.name, v_field)); continue;
      end if;
      v_cur := case v_field when 'name' then v_sup.name when 'note' then v_sup.note when 'is_purchasable' then v_sup.is_purchasable::text when 'is_discontinued' then v_sup.is_discontinued::text when 'discontinued_on' then v_sup.discontinued_on::text
                            when 'currency_id' then v_sup.currency_id::text when 'payment_term_id' then v_sup.payment_term_id::text when 'account_payable_id' then v_sup.account_payable_id::text when 'tax_rule' then v_sup.tax_rule when 'is_active' then v_sup.is_active::text end;
      if (case when v_field in ('is_purchasable', 'is_discontinued', 'is_active') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean) else (v_cur is distinct from nullif(v_c->>'old', '')) end) then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:' || v_field, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed %s of %s (now "%s") — check again — nothing was saved', v_field, v_sup.name, coalesce(v_cur, ''))); continue;
      end if;
      v_new := nullif(btrim(v_c->>'value'), '');
      if v_field = 'name' then
        if v_new is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_missing', 'supplier_id', v_sid, 'code', 'name_missing', 'message', format('%s cannot have an empty name — nothing was saved', v_sup.name));
        else
          v_folded := lower(regexp_replace(v_new, '\s+', ' ', 'g'));
          if exists (select 1 from public.supplier s where s.id <> v_sid and lower(regexp_replace(btrim(s.name), '\s+', ' ', 'g')) = v_folded) then
            v_blocks := v_blocks || jsonb_build_object('key', v_key || ':name_exists', 'supplier_id', v_sid, 'code', 'name_exists', 'message', format('A supplier named "%s" already exists — the name is the key — nothing was saved', v_new));
          end if;
          v_warns := v_warns || jsonb_build_object('key', v_key || ':rename_sync_cin7', 'supplier_id', v_sid, 'code', 'rename_sync_cin7', 'message', format('Renaming %s to "%s": Cin7 refers to suppliers by name — rename it in Cin7 too (Cin7 first while both systems run). Confirm', v_sup.name, v_new));
        end if;
      elsif v_field in ('is_discontinued', 'is_active') then
        if v_new is null or v_new not in ('true', 'false') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:' || v_field, 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s %s must be true or false — nothing was saved', v_sup.name, v_field));
        elsif v_field = 'is_active' and v_new = 'false' then
          select count(*) into v_open_po from public.po p where p.supplier_id = v_sid and p.status in ('draft', 'confirmed');
          select count(*) into v_open_inv from public.po_invoice i where i.supplier_id = v_sid and i.status in ('draft', 'confirmed') and i.total_amount > coalesce((select sum(l.amount) from public.po_payment_alloc l where l.po_invoice_id = i.id), 0);
          select count(*) into v_prods from public.product_supplier ps where ps.supplier_id = v_sid and ps.is_active;
          select count(*) into v_forms from public.price_formula f where f.supplier_id = v_sid;
          if v_open_po > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_po', 'supplier_id', v_sid, 'code', 'inactive_open_po', 'count', v_open_po, 'message', format('%s has %s open purchase order(s) — they keep running. Confirm to deactivate', v_sup.name, v_open_po)); end if;
          if v_open_inv > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_open_invoice', 'supplier_id', v_sid, 'code', 'inactive_open_invoice', 'count', v_open_inv, 'message', format('%s has %s supplier invoice(s) not fully paid — confirm to deactivate', v_sup.name, v_open_inv)); end if;
          if v_prods > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_products', 'supplier_id', v_sid, 'code', 'inactive_products', 'count', v_prods, 'message', format('%s is linked to %s product(s) (supplier lines stay) — confirm to deactivate', v_sup.name, v_prods)); end if;
          if v_forms > 0 then v_warns := v_warns || jsonb_build_object('key', v_key || ':inactive_formulas', 'supplier_id', v_sid, 'code', 'inactive_formulas', 'count', v_forms, 'message', format('%s has %s price formula(s) — confirm to deactivate', v_sup.name, v_forms)); end if;
        end if;
      elsif v_field = 'is_purchasable' then
        if v_new is not null and v_new not in ('true', 'false') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:is_purchasable', 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s: is_purchasable must be true, false or empty (not decided) — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'discontinued_on' then
        if v_new is not null and v_new !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':value_invalid:discontinued_on', 'supplier_id', v_sid, 'code', 'value_invalid', 'message', format('%s: discontinued_on must be a date (YYYY-MM-DD) or empty — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'payment_term_id' then
        if v_new is null or not exists (select 1 from public.ref_payment_term t where t.id = v_new::uuid and t.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':payment_term_invalid', 'supplier_id', v_sid, 'code', 'payment_term_invalid', 'message', format('%s: the payment term does not exist or is inactive — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'account_payable_id' then
        if v_new is null or not exists (select 1 from public.ref_account a where a.id = v_new::uuid and a.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':account_invalid', 'supplier_id', v_sid, 'code', 'account_invalid', 'message', format('%s: the payable account does not exist or is inactive — nothing was saved', v_sup.name)); end if;
      elsif v_field = 'currency_id' then
        if v_new is null or not exists (select 1 from public.ref_currency r where r.id = v_new::uuid and r.is_active) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':currency_invalid', 'supplier_id', v_sid, 'code', 'currency_invalid', 'message', format('%s: the currency does not exist or is inactive — nothing was saved', v_sup.name));
        end if;   -- [qbo-sync-3-1] 글자 추론 warn(ref_account.name ilike USD) 은 뗐다 — 짝 검사는 아래 공급처마다 한 번(통화 칸 기준 · block)
      end if;
      if v_field = any(v_money) and v_field <> 'is_active' then v_money_s := array_append(v_money_s, v_sid); end if;

    elsif v_op = any(v_mops) then
      if not v_master then
        v_blocks := v_blocks || jsonb_build_object('key', v_key || ':money_field_not_allowed:' || v_op, 'supplier_id', v_sid, 'code', 'money_field_not_allowed', 'message', format('Only a master user can change the discounts of %s — nothing was saved', v_sup.name)); continue;
      end if;
      if v_op = 'discount_add' then
        v_pct := case when (v_vals->>'percent') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (v_vals->>'percent')::numeric end;
        if nullif(btrim(v_vals->>'name'), '') is null or v_pct is null or v_pct > 100 then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid:' || v_i, 'supplier_id', v_sid, 'code', 'discount_invalid', 'message', format('%s: a discount needs a name and a percent from 0 to 100 — nothing was saved', v_sup.name)); end if;
      else
        select * into v_dsc from public.supplier_discount d where d.id = nullif(v_c->>'discount_id', '')::uuid and d.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'discount_unknown', 'message', format('%s: that discount line is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':discount:' || v_dsc.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:discount:' || v_dsc.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same discount line is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':discount:' || v_dsc.id::text);
        if v_op = 'discount_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if v_f not in ('name', 'percent') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:discount.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: discount field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:discount.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: discount %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            if (case when v_f = 'percent' then (v_dsc.percent is distinct from nullif(v_olds->>v_f, '')::numeric) else (v_dsc.name is distinct from nullif(v_olds->>v_f, '')) end) then
              v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:discount.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the discount %s of %s — check again — nothing was saved', v_f, v_sup.name));
            end if;
          end loop;
          if v_vals ? 'percent' and not ((v_vals->>'percent') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' and (v_vals->>'percent')::numeric <= 100) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_invalid:' || v_i, 'supplier_id', v_sid, 'code', 'discount_invalid', 'message', format('%s: percent must be 0 to 100 — nothing was saved', v_sup.name)); end if;
        elsif v_op = 'discount_off' and not v_dsc.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':discount_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'discount_inactive', 'message', format('%s: that discount line is already off — nothing was saved', v_sup.name));
        end if;
      end if;
      v_money_s := array_append(v_money_s, v_sid);

    elsif v_op like 'address_%' then
      if v_op = 'address_add' then
        if nullif(btrim(coalesce(v_vals->>'line1', '') || coalesce(v_vals->>'city', '') || coalesce(v_vals->>'postal_code', '')), '') is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_empty:' || v_i, 'supplier_id', v_sid, 'code', 'address_empty', 'message', format('%s: the new address has no street, city or postal code — nothing was saved', v_sup.name)); end if;
      else
        select * into v_a from public.supplier_address a where a.id = nullif(v_c->>'address_id', '')::uuid and a.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'address_unknown', 'message', format('%s: that address is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':address:' || v_a.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:address:' || v_a.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same address is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':address:' || v_a.id::text);
        if v_op = 'address_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_afields)) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:address.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: address field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:address.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: address %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            v_cur := case v_f when 'type' then v_a.type when 'line1' then v_a.line1 when 'line2' then v_a.line2 when 'city' then v_a.city when 'state_province' then v_a.state_province when 'postal_code' then v_a.postal_code else v_a.country end;
            if v_cur is distinct from nullif(v_olds->>v_f, '') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:address.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the address %s of %s (now "%s") — check again — nothing was saved', v_f, v_sup.name, coalesce(v_cur, ''))); end if;
          end loop;
        elsif v_op = 'address_off' and not v_a.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':address_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'address_inactive', 'message', format('%s: that address is already off — nothing was saved', v_sup.name));
        end if;
      end if;

    else
      if v_op = 'contact_add' then
        if nullif(btrim(coalesce(v_vals->>'name', '') || coalesce(v_vals->>'phone', '') || coalesce(v_vals->>'mobile_phone', '') || coalesce(v_vals->>'email', '')), '') is null then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_empty:' || v_i, 'supplier_id', v_sid, 'code', 'contact_empty', 'message', format('%s: the new contact has no name, phone or email — nothing was saved', v_sup.name)); end if;
      else
        select * into v_ct from public.supplier_contact k where k.id = nullif(v_c->>'contact_id', '')::uuid and k.supplier_id = v_sid;
        if not found then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_unknown:' || v_i, 'supplier_id', v_sid, 'code', 'contact_unknown', 'message', format('%s: that contact is not on this supplier — nothing was saved', v_sup.name)); continue; end if;
        if (v_key || ':contact:' || v_ct.id::text) = any(v_seen) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_duplicate_in_call:contact:' || v_ct.id::text, 'supplier_id', v_sid, 'code', 'field_duplicate_in_call', 'message', format('%s: the same contact is changed twice in this call — nothing was saved', v_sup.name)); continue; end if;
        v_seen := array_append(v_seen, v_key || ':contact:' || v_ct.id::text);
        if v_op = 'contact_set' then
          for v_f in select x from jsonb_object_keys(v_vals) as x loop
            if not (v_f = any(v_cfields)) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':field_unknown:contact.' || v_f, 'supplier_id', v_sid, 'code', 'field_unknown', 'message', format('%s: contact field %s cannot be changed here — nothing was saved', v_sup.name, v_f)); continue; end if;
            if not (v_olds ? v_f) then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':old_missing:contact.' || v_f, 'supplier_id', v_sid, 'code', 'old_missing', 'message', format('%s: contact %s — the old value the screen saw is missing — nothing was saved', v_sup.name, v_f)); continue; end if;
            v_cur := case v_f when 'name' then v_ct.name when 'phone' then v_ct.phone when 'mobile_phone' then v_ct.mobile_phone when 'fax' then v_ct.fax when 'email' then v_ct.email else v_ct.website end;
            if v_cur is distinct from nullif(v_olds->>v_f, '') then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':changed_elsewhere:contact.' || v_f, 'supplier_id', v_sid, 'code', 'changed_elsewhere', 'message', format('Someone just changed the contact %s of %s (now "%s") — check again — nothing was saved', v_f, v_sup.name, coalesce(v_cur, ''))); end if;
          end loop;
        elsif v_op = 'contact_off' then
          if not v_ct.is_active then v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'contact_inactive', 'message', format('%s: that contact is already off — nothing was saved', v_sup.name));
          elsif v_ct.is_default and not (v_key = any(v_newdef)) then v_warns := v_warns || jsonb_build_object('key', v_key || ':contact_default_off', 'supplier_id', v_sid, 'code', 'contact_default_off', 'message', format('%s: this is the default contact — switching it off leaves no default (po_create will warn contact_unset). Confirm', v_sup.name)); end if;
        elsif v_op = 'contact_default' and not v_ct.is_active then
          v_blocks := v_blocks || jsonb_build_object('key', v_key || ':contact_inactive:' || v_i, 'supplier_id', v_sid, 'code', 'contact_inactive', 'message', format('%s: an inactive contact cannot be the default — switch it on first — nothing was saved', v_sup.name));
        end if;
      end if;
    end if;
  end loop;

  -- [qbo-sync-3-1 · 판정 1088 · 1091] 공급처마다 이 호출이 끝난 뒤의 (통화 · A/P 계정) 짝을 본다 — 둘을 한 호출(한 저장)로 함께 바꾸면 통과 · 창구 밖 길은 deferred 트리거 supplier_account_currency_ck 가 같은 규칙으로 막는다
  for v_sid in select distinct u from unnest(v_money_s) as u loop
    select * into v_sup from public.supplier s where s.id = v_sid;
    select nullif(btrim(x->>'value'), '')::uuid into v_eff_acct from jsonb_array_elements(p_changes) x where x->>'op' = 'set' and x->>'field' = 'account_payable_id' and x->>'supplier_id' = v_sid::text limit 1;
    if not found then v_eff_acct := v_sup.account_payable_id; end if;
    select r.code into v_eff_cur from public.ref_currency r where r.id = (select nullif(btrim(x->>'value'), '')::uuid from jsonb_array_elements(p_changes) x where x->>'op' = 'set' and x->>'field' = 'currency_id' and x->>'supplier_id' = v_sid::text limit 1);
    if not found then select r.code into v_eff_cur from public.ref_currency r where r.id = v_sup.currency_id; end if;
    if v_eff_cur is not null and v_eff_acct is not null and public.ims_account_currency(v_eff_acct) <> v_eff_cur then
      v_blocks := v_blocks || jsonb_build_object('key', v_sid::text || ':currency_account_mismatch', 'supplier_id', v_sid, 'code', 'currency_account_mismatch',
        'message', public.ims_account_currency_msg('Supplier', v_sup.name, 'payable', coalesce((select a.code from public.ref_account a where a.id = v_eff_acct), '?'), public.ims_account_currency(v_eff_acct), v_eff_cur));
    end if;
  end loop;
  for v_sid in select distinct u from unnest(v_money_s) as u loop
    select count(*), max(s.name) into v_open_po, v_cur from public.po p join public.supplier s on s.id = p.supplier_id where p.supplier_id = v_sid and p.status in ('draft', 'confirmed');
    if v_open_po > 0 then v_warns := v_warns || jsonb_build_object('key', v_sid::text || ':open_po_keep_old', 'supplier_id', v_sid, 'code', 'open_po_keep_old', 'count', v_open_po, 'message', format('%s has %s open purchase order(s) — they keep the old terms; only new orders get the change. Confirm', v_cur, v_open_po)); end if;
  end loop;

  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'changes', v_changes, 'blocks', v_blocks, 'warnings', v_warns, 'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  begin
    perform 1 from public.supplier s where s.id = any(v_touched) for update;
    v_i := 0;
    for v_c in select x from jsonb_array_elements(p_changes) as x loop
      v_i := v_i + 1;
      v_op := v_c->>'op'; v_field := nullif(btrim(v_c->>'field'), ''); v_sid := (v_c->>'supplier_id')::uuid; v_new := nullif(btrim(v_c->>'value'), ''); v_vals := coalesce(v_c->'values', '{}'::jsonb);
      if v_op = 'set' then
        case v_field
          when 'name' then update public.supplier set name = v_new, updated_by = v_staff where id = v_sid;
          when 'note' then update public.supplier set note = v_new, updated_by = v_staff where id = v_sid;
          when 'is_purchasable' then update public.supplier set is_purchasable = v_new::boolean, updated_by = v_staff where id = v_sid;
          when 'is_discontinued' then update public.supplier set is_discontinued = v_new::boolean, discontinued_on = case when v_new::boolean then coalesce(discontinued_on, public.ims_today()) else null end, updated_by = v_staff where id = v_sid;
          when 'discontinued_on' then update public.supplier set discontinued_on = v_new::date, updated_by = v_staff where id = v_sid;
          when 'currency_id' then update public.supplier set currency_id = v_new::uuid, updated_by = v_staff where id = v_sid;
          when 'payment_term_id' then update public.supplier set payment_term_id = v_new::uuid, payment_term_name = (select t.name from public.ref_payment_term t where t.id = v_new::uuid), updated_by = v_staff where id = v_sid;
          when 'account_payable_id' then update public.supplier set account_payable_id = v_new::uuid, account_payable_code = (select a.code from public.ref_account a where a.id = v_new::uuid), updated_by = v_staff where id = v_sid;
          when 'tax_rule' then update public.supplier set tax_rule = v_new, updated_by = v_staff where id = v_sid;
          when 'is_active' then update public.supplier set is_active = v_new::boolean, is_active_source = 'ims', updated_by = v_staff where id = v_sid; v_recalc := array_append(v_recalc, v_sid);   -- ldfix-1c2 · 판정 683: IMS 가 켜고 끈 표식(적재가 지킨다) · 682: 재계산 대상
        end case;
      elsif v_op = 'discount_add' then
        insert into public.supplier_discount (supplier_id, name, percent, seq, source, updated_by)
        values (v_sid, btrim(v_vals->>'name'), (v_vals->>'percent')::numeric, (select coalesce(max(d.seq), 0) + 1 from public.supplier_discount d where d.supplier_id = v_sid), 'manual', v_staff) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'discount_set' then
        update public.supplier_discount d set name = case when v_vals ? 'name' then btrim(v_vals->>'name') else d.name end, percent = case when v_vals ? 'percent' then (v_vals->>'percent')::numeric else d.percent end, updated_by = v_staff where d.id = (v_c->>'discount_id')::uuid;
      elsif v_op = 'discount_off' then
        update public.supplier_discount set is_active = false, updated_by = v_staff where id = (v_c->>'discount_id')::uuid;
      elsif v_op = 'address_add' then
        insert into public.supplier_address (supplier_id, source, updated_by, type, line1, line2, city, state_province, postal_code, country)
        values (v_sid, 'manual', v_staff, nullif(btrim(v_vals->>'type'), ''), nullif(btrim(v_vals->>'line1'), ''), nullif(btrim(v_vals->>'line2'), ''), nullif(btrim(v_vals->>'city'), ''), nullif(btrim(v_vals->>'state_province'), ''), nullif(btrim(v_vals->>'postal_code'), ''), nullif(btrim(v_vals->>'country'), '')) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'address_set' then
        update public.supplier_address a set
          type = case when v_vals ? 'type' then nullif(btrim(v_vals->>'type'), '') else a.type end, line1 = case when v_vals ? 'line1' then nullif(btrim(v_vals->>'line1'), '') else a.line1 end, line2 = case when v_vals ? 'line2' then nullif(btrim(v_vals->>'line2'), '') else a.line2 end,
          city = case when v_vals ? 'city' then nullif(btrim(v_vals->>'city'), '') else a.city end, state_province = case when v_vals ? 'state_province' then nullif(btrim(v_vals->>'state_province'), '') else a.state_province end,
          postal_code = case when v_vals ? 'postal_code' then nullif(btrim(v_vals->>'postal_code'), '') else a.postal_code end, country = case when v_vals ? 'country' then nullif(btrim(v_vals->>'country'), '') else a.country end, updated_by = v_staff
        where a.id = (v_c->>'address_id')::uuid;
      elsif v_op = 'address_off' then
        update public.supplier_address set is_active = false, updated_by = v_staff where id = (v_c->>'address_id')::uuid;
      elsif v_op = 'contact_add' then
        if coalesce((v_vals->>'is_default')::boolean, false) then update public.supplier_contact set is_default = false, updated_by = v_staff where supplier_id = v_sid and is_default; end if;
        insert into public.supplier_contact (supplier_id, source, updated_by, name, phone, mobile_phone, fax, email, website, is_default)
        values (v_sid, 'manual', v_staff, nullif(btrim(v_vals->>'name'), ''), nullif(btrim(v_vals->>'phone'), ''), nullif(btrim(v_vals->>'mobile_phone'), ''), nullif(btrim(v_vals->>'fax'), ''), nullif(btrim(v_vals->>'email'), ''), nullif(btrim(v_vals->>'website'), ''), coalesce((v_vals->>'is_default')::boolean, false)) returning id into v_rid;
        v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'id'], to_jsonb(v_rid)); v_rid := null;
      elsif v_op = 'contact_set' then
        update public.supplier_contact k set
          name = case when v_vals ? 'name' then nullif(btrim(v_vals->>'name'), '') else k.name end, phone = case when v_vals ? 'phone' then nullif(btrim(v_vals->>'phone'), '') else k.phone end, mobile_phone = case when v_vals ? 'mobile_phone' then nullif(btrim(v_vals->>'mobile_phone'), '') else k.mobile_phone end,
          fax = case when v_vals ? 'fax' then nullif(btrim(v_vals->>'fax'), '') else k.fax end, email = case when v_vals ? 'email' then nullif(btrim(v_vals->>'email'), '') else k.email end, website = case when v_vals ? 'website' then nullif(btrim(v_vals->>'website'), '') else k.website end, updated_by = v_staff
        where k.id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_off' then
        update public.supplier_contact set is_active = false, is_default = false, updated_by = v_staff where id = (v_c->>'contact_id')::uuid;
      elsif v_op = 'contact_default' then
        update public.supplier_contact k set is_default = (k.id = (v_c->>'contact_id')::uuid), updated_by = v_staff where k.supplier_id = v_sid and k.is_active and (k.is_default or k.id = (v_c->>'contact_id')::uuid);
      end if;
      v_changes := jsonb_set(v_changes, array[(v_i - 1)::text, 'applied'], 'true'::jsonb);
    end loop;
  exception when unique_violation then
    raise exception 'A name or default would collide (%) — check the supplier name and keep one default contact — nothing was saved', coalesce(sqlerrm, '');
  end;
  if cardinality(v_recalc) > 0 then v_recalc_out := public.product_supplier_default_recalc(array(select distinct ps.product_id from public.product_supplier ps where ps.supplier_id = any(v_recalc))); end if;   -- ldfix-1c2 · 판정 682: 그 공급처의 제품만(§3-g ① 끄기 → ② 켜기)
  return jsonb_build_object('committed', true, 'changes', v_changes, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb, 'default_recalc', v_recalc_out);
end;
$function$;

CREATE OR REPLACE FUNCTION public.customer_create(p_customer jsonb, p_commit boolean DEFAULT false, p_ack text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_staff     uuid;
  v_master    boolean;
  v_blocks    jsonb := '[]'::jsonb;
  v_warns     jsonb := '[]'::jsonb;
  v_defaults  text[] := '{}';
  v_name      text;
  v_folded    text;
  v_matches   jsonb;
  v_n_active  int;
  v_n_off     int;
  v_money     text[] := array['price_tier', 'discount_pct', 'payment_term_id', 'currency_id', 'ar_account_id', 'sale_account_id', 'default_bill_to_customer_id', 'invoice_split_by_store'];   -- 판정 254(cs-par-1): is_bill_parent 는 받지 않는다(보내도 무시 · 늘 false)
  v_given     text[];
  v_k         text;
  v_tier      public.ref_price_tier%rowtype;
  v_term      public.ref_payment_term%rowtype;
  v_cur       public.ref_currency%rowtype;
  v_ar        public.ref_account%rowtype;
  v_sale      public.ref_account%rowtype;
  v_wh        public.ref_warehouse%rowtype;
  v_parent    public.customer%rowtype;
  v_other     public.customer%rowtype;
  v_disc      numeric;
  v_cfg       text;
  v_a         jsonb;
  v_c         jsonb;
  v_i         int;
  v_type      text;
  v_def_types text[] := '{}';
  v_has_ship  boolean := false;
  v_has_bill  boolean := false;
  v_n_cdef    int := 0;
  v_consent   boolean;
  v_consent_t text;
  v_cid       uuid;
  v_aid       uuid;
  v_addr_ids  jsonb := '[]'::jsonb;
  v_cont_ids  jsonb := '[]'::jsonb;
  v_keys      text[];
  v_unacked   text[];
  v_first_def_by_type jsonb := '{}'::jsonb;
begin
  -- ⭐ 문(판정 237) — sales 또는 master 쓰기 · 문장은 ims_require_write 와 같은 모양(sales 를 이름한다)
  if not (public.ims_can_write('sales') or public.ims_can_write('master')) then
    raise exception 'You cannot change sales data — ask an admin to add the ''sales'' permission — nothing was saved';
  end if;
  v_master := public.ims_can_write('master');
  select s.id into v_staff from public.ims_staff s where s.auth_user_id = auth.uid() and s.is_active;
  if v_staff is null then raise exception 'No active staff record for this login — nothing was saved'; end if;

  -- ① 모양
  if p_customer is null or jsonb_typeof(p_customer) <> 'object' then
    raise exception 'p_customer must be a JSON object — nothing was saved';
  end if;
  if p_customer ? 'addresses' and jsonb_typeof(p_customer->'addresses') <> 'array' then raise exception 'addresses must be a JSON array — nothing was saved'; end if;
  if p_customer ? 'contacts'  and jsonb_typeof(p_customer->'contacts')  <> 'array' then raise exception 'contacts must be a JSON array — nothing was saved'; end if;

  -- ② 이름 · 같은 이름(판정 238)
  v_name := nullif(btrim(p_customer->>'name'), '');
  if v_name is null then
    v_blocks := v_blocks || jsonb_build_object('key', 'name_missing', 'code', 'name_missing', 'message', 'The customer has no name — nothing was saved');
  else
    v_folded := lower(regexp_replace(v_name, '\s+', ' ', 'g'));
    select count(*) filter (where c.is_active), count(*) filter (where not c.is_active),
           coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'is_active', c.is_active, 'city', (select a.city from public.customer_address a where a.customer_id = c.id and a.is_active order by (a.type = 'Shipping') desc, a.is_default_for_type desc, a.created_at limit 1))
                              order by c.is_active desc, c.created_at) filter (where c.rn <= 5), '[]'::jsonb)
      into v_n_active, v_n_off, v_matches
      from (select c0.*, row_number() over (order by c0.is_active desc, c0.created_at) as rn from public.customer c0 where lower(regexp_replace(btrim(c0.name), '\s+', ' ', 'g')) = v_folded) c;
    if v_n_active > 0 then
      v_warns := v_warns || jsonb_build_object('key', 'name_exists', 'code', 'name_exists', 'matches', v_matches,
        'message', format('%s active customer(s) already have this name (%s) — is this really a new customer? Confirm to create it anyway', v_n_active, (select string_agg(coalesce(m->>'name', '') || coalesce(' · ' || (m->>'city'), ''), '; ') from jsonb_array_elements(v_matches) m where (m->>'is_active')::boolean)));
    elsif v_n_off > 0 then
      v_warns := v_warns || jsonb_build_object('key', 'name_matches_inactive', 'code', 'name_matches_inactive', 'matches', v_matches,
        'message', format('%s inactive customer(s) have this name — reactivating one may be better than a new row. Confirm to create a new customer', v_n_off));
    end if;
  end if;

  -- ③ 돈 칸(판정 237 · 239) — 요청에 든 돈 칸 목록
  select coalesce(array_agg(k order by k), '{}') into v_given from unnest(v_money) as k where p_customer ? k and p_customer->k <> 'null'::jsonb;
  if cardinality(v_given) > 0 and not v_master then
    v_blocks := v_blocks || jsonb_build_object('key', 'money_field_not_allowed', 'code', 'money_field_not_allowed',
      'message', format('Only a master user can set %s on a new customer — leave them out and the defaults apply (a master user reviews them later) — nothing was saved', array_to_string(v_given, ', ')));
  end if;

  -- 티어
  if 'price_tier' = any(v_given) and v_master then
    select * into v_tier from public.ref_price_tier t where t.name = btrim(p_customer->>'price_tier') and t.is_active and t.purpose = 'sale';
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'tier_invalid', 'code', 'tier_invalid', 'message', format('Price tier %s does not exist, is inactive or is not a sale tier — nothing was saved', p_customer->>'price_tier')); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_price_tier';
    select * into v_tier from public.ref_price_tier t where t.name = v_cfg and t.is_active and t.purpose = 'sale';
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:price_tier', 'code', 'default_missing', 'message', format('The default price tier is not set up (inv_config customer_default_price_tier = %s) — ask a master user to fix the default or to create this customer — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'price_tier'); end if;
  end if;
  -- 할인
  if 'discount_pct' = any(v_given) and v_master then
    v_disc := case when (p_customer->>'discount_pct') ~ '^\s*[0-9]+(\.[0-9]+)?\s*$' then (p_customer->>'discount_pct')::numeric end;
    if v_disc is null or v_disc > 100 then v_blocks := v_blocks || jsonb_build_object('key', 'discount_invalid', 'code', 'discount_invalid', 'message', format('discount_pct must be a number from 0 to 100 (got %s) — nothing was saved', p_customer->>'discount_pct')); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_discount_pct';
    v_disc := case when v_cfg ~ '^[0-9]+(\.[0-9]+)?$' and v_cfg::numeric <= 100 then v_cfg::numeric end;
    if v_disc is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:discount_pct', 'code', 'default_missing', 'message', format('The default discount is not set up (inv_config customer_default_discount_pct = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'discount_pct'); end if;
  end if;
  -- 결제조건
  if 'payment_term_id' = any(v_given) and v_master then
    select * into v_term from public.ref_payment_term t where t.id = (p_customer->>'payment_term_id')::uuid and t.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'payment_term_invalid', 'code', 'payment_term_invalid', 'message', 'The payment term does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_payment_term';
    select * into v_term from public.ref_payment_term t where t.name = v_cfg and t.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:payment_term', 'code', 'default_missing', 'message', format('The default payment term is not set up (inv_config customer_default_payment_term = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'payment_term'); end if;
  end if;
  -- 통화
  if 'currency_id' = any(v_given) and v_master then
    select * into v_cur from public.ref_currency c where c.id = (p_customer->>'currency_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'currency_invalid', 'code', 'currency_invalid', 'message', 'The currency does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_currency_code';
    select * into v_cur from public.ref_currency c where c.code = v_cfg and c.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:currency', 'code', 'default_missing', 'message', format('The default currency is not set up (inv_config customer_default_currency_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'currency'); end if;
  end if;
  -- 계정 둘
  if 'ar_account_id' = any(v_given) and v_master then
    select * into v_ar from public.ref_account a where a.id = (p_customer->>'ar_account_id')::uuid and a.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'ar_account_invalid', 'code', 'ar_account_invalid', 'message', 'The receivable account does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_ar_account_code_' || lower(v_cur.code);   -- [qbo-sync-3-1 · deferred 499 · 1088] 통화별 기본(_cad · _usd) · 통화가 안 섰으면 null 키 → 폴백
    if v_cfg is null then select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_ar_account_code'; end if;   -- 옛 키 = 폴백(값 무변)
    select * into v_ar from public.ref_account a where a.code = v_cfg and a.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:ar_account', 'code', 'default_missing', 'message', format('The default receivable account is not set up (inv_config customer_default_ar_account_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'ar_account'); end if;
  end if;
  if 'sale_account_id' = any(v_given) and v_master then
    select * into v_sale from public.ref_account a where a.id = (p_customer->>'sale_account_id')::uuid and a.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'sale_account_invalid', 'code', 'sale_account_invalid', 'message', 'The sales account does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_sale_account_code';
    select * into v_sale from public.ref_account a where a.code = v_cfg and a.is_active;
    if v_cfg is null or not found then
      v_blocks := v_blocks || jsonb_build_object('key', 'default_missing:sale_account', 'code', 'default_missing', 'message', format('The default sales account is not set up (inv_config customer_default_sale_account_code = %s) — ask a master user — nothing was saved', coalesce(v_cfg, '(empty)')));
    else v_defaults := array_append(v_defaults, 'sale_account'); end if;
  end if;
  if v_cur.id is not null and v_ar.id is not null and public.ims_account_currency(v_ar.id) <> v_cur.code then   -- [qbo-sync-3-1 · deferred 499 · 판정 1088 · 1091] A/R 계정 통화 ≠ 손님 통화 → 막기(트리거 customer_account_currency_ck 와 같은 규칙)
    v_blocks := v_blocks || jsonb_build_object('key', 'currency_account_mismatch', 'code', 'currency_account_mismatch', 'message', public.ims_account_currency_msg('Customer', coalesce(v_name, '(new)'), 'receivable', v_ar.code, public.ims_account_currency(v_ar.id), v_cur.code));
  end if;
  if v_tier.id is not null and v_cur.id is not null and v_tier.currency_id <> v_cur.id then
    v_warns := v_warns || jsonb_build_object('key', 'tier_currency_mismatch', 'code', 'tier_currency_mismatch', 'message', format('Price tier %s is not in the customer currency %s — order prices will not match the currency', v_tier.name, v_cur.code));
  end if;
  -- 청구 구조(master 만 · 값 검사)
  if 'default_bill_to_customer_id' = any(v_given) and v_master then
    select * into v_other from public.customer c where c.id = (p_customer->>'default_bill_to_customer_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'bill_to_unknown', 'code', 'bill_to_unknown', 'message', 'The bill-to customer does not exist or is inactive — nothing was saved'); end if;
  end if;

  -- ④ 일반 칸(누구나) — 창고 · 부모 · 배송 손님
  if nullif(p_customer->>'default_location_id', '') is not null then
    select * into v_wh from public.ref_warehouse w where w.id = (p_customer->>'default_location_id')::uuid and w.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'warehouse_unknown', 'code', 'warehouse_unknown', 'message', 'The default warehouse does not exist or is inactive — nothing was saved'); end if;
  else
    select nullif(k.value, '') into v_cfg from public.inv_config k where k.key = 'customer_default_location_name';
    select * into v_wh from public.ref_warehouse w where w.name = v_cfg and w.is_active;       -- 비었거나 없으면 창고 없이 만든다(돈 칸이 아니다 · 오더가 창고를 고른다)
    if v_wh.id is not null then v_defaults := array_append(v_defaults, 'default_location'); end if;
  end if;
  if nullif(p_customer->>'parent_id', '') is not null then
    if not v_master then v_blocks := v_blocks || jsonb_build_object('key', 'money_field_not_allowed:parent_id', 'code', 'money_field_not_allowed', 'message', 'Only a master user can set parent_id on a new customer — leave it out and link the store afterwards — nothing was saved'); end if;   -- 판정 252(cs-par-1)
    select * into v_parent from public.customer c where c.id = (p_customer->>'parent_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'parent_unknown', 'code', 'parent_unknown', 'message', 'The parent customer does not exist or is inactive — nothing was saved');
    elsif v_parent.parent_id is not null then v_blocks := v_blocks || jsonb_build_object('key', 'parent_has_parent', 'code', 'parent_has_parent', 'message', format('%s already has a parent — a customer tree is one level deep — nothing was saved', v_parent.name)); end if;
  end if;
  if nullif(p_customer->>'default_ship_to_customer_id', '') is not null then
    select * into v_other from public.customer c where c.id = (p_customer->>'default_ship_to_customer_id')::uuid and c.is_active;
    if not found then v_blocks := v_blocks || jsonb_build_object('key', 'ship_to_unknown', 'code', 'ship_to_unknown', 'message', 'The ship-to customer does not exist or is inactive — nothing was saved'); end if;
  end if;

  -- ⑤ 주소 — type 어휘 · 빈 줄 · type 별 기본 하나(표시 없으면 그 type 의 첫 줄)
  v_i := 0;
  for v_a in select x from jsonb_array_elements(coalesce(p_customer->'addresses', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_type := nullif(btrim(v_a->>'type'), '');
    if v_type is null or v_type not in ('Billing', 'Business', 'Shipping') then
      v_blocks := v_blocks || jsonb_build_object('key', 'address_type_invalid:' || v_i, 'code', 'address_type_invalid', 'message', format('Address %s: type must be Billing, Business or Shipping (got %s) — nothing was saved', v_i, coalesce(v_type, '(blank)')));
      continue;
    end if;
    if nullif(btrim(coalesce(v_a->>'line1', '') || coalesce(v_a->>'city', '') || coalesce(v_a->>'postal_code', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'address_empty:' || v_i, 'code', 'address_empty', 'message', format('Address %s (%s) has no street, city or postal code — nothing was saved', v_i, v_type));
    end if;
    if v_type = 'Shipping' then v_has_ship := true; end if;
    if v_type = 'Billing' then v_has_bill := true; end if;
    if coalesce((v_a->>'is_default_for_type')::boolean, false) then
      if v_type = any(v_def_types) then
        v_blocks := v_blocks || jsonb_build_object('key', 'address_default_many:' || v_type, 'code', 'address_default_many', 'message', format('More than one %s address is marked default — only one per type — nothing was saved', v_type));
      else v_def_types := v_def_types || v_type; end if;
    end if;
    if not (v_first_def_by_type ? v_type) then v_first_def_by_type := v_first_def_by_type || jsonb_build_object(v_type, v_i); end if;
  end loop;
  if not v_has_ship then
    v_warns := v_warns || jsonb_build_object('key', 'shipping_address_missing', 'code', 'shipping_address_missing', 'message', 'No shipping address — every order for this customer will ask for one (ship_to_empty). Confirm to create the customer without it');
  end if;
  if not v_has_bill then
    v_warns := v_warns || jsonb_build_object('key', 'billing_address_missing', 'code', 'billing_address_missing', 'message', 'No billing address — every order for this customer will warn bill_to_empty until one is added. Confirm to create the customer without it');
  end if;

  -- ⑥ 연락처 — 빈 줄 · 동의 숫자 · 기본 하나(표시 없으면 첫 줄)
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_customer->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    if nullif(btrim(coalesce(v_c->>'name', '') || coalesce(v_c->>'phone', '') || coalesce(v_c->>'mobile_phone', '') || coalesce(v_c->>'email', '')), '') is null then
      v_blocks := v_blocks || jsonb_build_object('key', 'contact_empty:' || v_i, 'code', 'contact_empty', 'message', format('Contact %s has no name, phone or email — nothing was saved', v_i));
    end if;
    v_consent_t := nullif(btrim(v_c->>'marketing_consent'), '');
    if v_consent_t is not null and v_consent_t not in ('0', '1', '2', '3') then
      v_blocks := v_blocks || jsonb_build_object('key', 'consent_invalid:' || v_i, 'code', 'consent_invalid', 'message', format('Contact %s: marketing_consent must be 0 or 1 (unknown), 2 (opt in) or 3 (opt out) — got %s — nothing was saved', v_i, v_consent_t));
    end if;
    if coalesce((v_c->>'is_default')::boolean, false) then v_n_cdef := v_n_cdef + 1; end if;
  end loop;
  if v_n_cdef > 1 then
    v_blocks := v_blocks || jsonb_build_object('key', 'contact_default_many', 'code', 'contact_default_many', 'message', 'More than one contact is marked default — only one per customer — nothing was saved');
  end if;

  -- ⑦ 판정 — 막기 있음 → 저장 안 함 · 검사만 → 반환 · 확인 안 받은 경고 → 저장 안 함(판정 176 모양)
  select coalesce(array_agg(w->>'key'), '{}') into v_keys from jsonb_array_elements(v_warns) as w;
  select coalesce(array_agg(k order by k), '{}') into v_unacked from unnest(v_keys) as k where not (k = any(coalesce(p_ack, '{}')));
  if jsonb_array_length(v_blocks) > 0 or not p_commit or cardinality(v_unacked) > 0 then
    return jsonb_build_object('committed', false, 'customer_id', null, 'name', v_name, 'review_required', not v_master, 'defaults_used', to_jsonb(v_defaults),
                              'address_ids', '[]'::jsonb, 'contact_ids', '[]'::jsonb, 'blocks', v_blocks, 'warnings', v_warns,
                              'unacked', case when jsonb_array_length(v_blocks) > 0 or not p_commit then '[]'::jsonb else to_jsonb(v_unacked) end);
  end if;

  -- ⑧ 저장 — 손님 → 주소 → 연락처 · 한 트랜잭션 · source manual · cin7_id null · created_by · master 면 reviewed 즉시(판정 240)
  insert into public.customer (name, display_name, note, source, is_active, created_by, updated_by,
                               currency_id, currency_code, payment_term_id, payment_term_name, discount_pct, price_tier, tax_rule,
                               default_location_id, default_location_name, ar_account_id, ar_account_code, sale_account_id, sale_account_code,
                               parent_id, parent_source, is_legal_entity, default_ship_to_customer_id, default_bill_to_customer_id, default_carrier, tax_number, tags, invoice_split_by_store,
                               backorder_mail,                                                                                            -- aone-bo-1 판정 949
                               reviewed_by, reviewed_at)
  values (v_name, nullif(btrim(p_customer->>'display_name'), ''), nullif(btrim(p_customer->>'note'), ''), 'manual', true, v_staff, v_staff,
          v_cur.id, v_cur.code, v_term.id, v_term.name, v_disc, v_tier.name, nullif(btrim(p_customer->>'tax_rule'), ''),
          v_wh.id, v_wh.name, v_ar.id, v_ar.code, v_sale.id, v_sale.code,
          nullif(p_customer->>'parent_id', '')::uuid,
          case when nullif(p_customer->>'parent_id', '') is not null then 'ims' end,   -- 판정 253 · 254(cs-par-1): parent_source(부모를 주면 ims) · is_bill_parent 는 기본값 false 로 둔다
          coalesce((p_customer->>'is_legal_entity')::boolean, false),
          nullif(p_customer->>'default_ship_to_customer_id', '')::uuid,
          case when v_master then nullif(p_customer->>'default_bill_to_customer_id', '')::uuid end,
          nullif(btrim(p_customer->>'default_carrier'), ''), nullif(btrim(p_customer->>'tax_number'), ''), nullif(btrim(p_customer->>'tags'), ''),
          case when v_master then coalesce((p_customer->>'invoice_split_by_store')::boolean, false) else false end,
          coalesce((p_customer->>'backorder_mail')::boolean, true),                                                                       -- aone-bo-1 판정 949: 없으면 칸 기본값과 같은 true
          case when v_master then v_staff end, case when v_master then now() end)
  returning id into v_cid;
  v_i := 0;
  for v_a in select x from jsonb_array_elements(coalesce(p_customer->'addresses', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_type := btrim(v_a->>'type');
    insert into public.customer_address (customer_id, source, updated_by, type, is_default_for_type, label, line1, line2, city, state_province, postal_code, country)
    values (v_cid, 'manual', v_staff, v_type,
            case when v_type = any(v_def_types) then coalesce((v_a->>'is_default_for_type')::boolean, false) else (v_first_def_by_type->>v_type)::int = v_i end,
            nullif(btrim(v_a->>'label'), ''), nullif(btrim(v_a->>'line1'), ''), nullif(btrim(v_a->>'line2'), ''), nullif(btrim(v_a->>'city'), ''),
            nullif(btrim(v_a->>'state_province'), ''), nullif(btrim(v_a->>'postal_code'), ''), nullif(btrim(v_a->>'country'), ''))
    returning id into v_aid;
    v_addr_ids := v_addr_ids || to_jsonb(v_aid);
  end loop;
  v_i := 0;
  for v_c in select x from jsonb_array_elements(coalesce(p_customer->'contacts', '[]'::jsonb)) as x loop
    v_i := v_i + 1;
    v_consent_t := nullif(btrim(v_c->>'marketing_consent'), '');
    v_consent := case v_consent_t when '2' then true when '3' then false else null end;      -- asung-so ⚠️ 2 Opt in · 3 Opt out · 0 · 1 · 없음 = Unknown
    insert into public.customer_contact (customer_id, source, updated_by, name, phone, mobile_phone, fax, email, website, job_title, include_in_email, marketing_consent, is_default)
    values (v_cid, 'manual', v_staff, nullif(btrim(v_c->>'name'), ''), nullif(btrim(v_c->>'phone'), ''), nullif(btrim(v_c->>'mobile_phone'), ''), nullif(btrim(v_c->>'fax'), ''),
            nullif(btrim(v_c->>'email'), ''), nullif(btrim(v_c->>'website'), ''), nullif(btrim(v_c->>'job_title'), ''), coalesce((v_c->>'include_in_email')::boolean, false), v_consent,
            case when v_n_cdef = 1 then coalesce((v_c->>'is_default')::boolean, false) else v_i = 1 end)
    returning id into v_aid;
    v_cont_ids := v_cont_ids || to_jsonb(v_aid);
  end loop;

  return jsonb_build_object('committed', true, 'customer_id', v_cid, 'name', v_name, 'review_required', not v_master, 'defaults_used', to_jsonb(v_defaults),
                            'address_ids', v_addr_ids, 'contact_ids', v_cont_ids, 'blocks', '[]'::jsonb, 'warnings', v_warns, 'unacked', '[]'::jsonb);
end;
$function$;

CREATE OR REPLACE FUNCTION public.customer_update(p_changes jsonb, p_commit boolean DEFAULT false, p_ack text[] DEFAULT '{}'::text[])
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_mgr      text[] := array['backorder_mail', 'final_invoice_mail'];   -- mail-4a 판정 507 · 517: 백오더 알림 받기 — 값이 바뀔 때만 manager 이상(sales 는 보기만 · 판정 237 의 일반 칸 = sales 의 예외) · doc-3a 판정 529: 최종 인보이스 자동 메일도 같은 결
  v_afields  text[] := array['type', 'line1', 'line2', 'city', 'state_province', 'postal_code', 'country', 'label', 'residential', 'tailgate_required', 'threshold_delivery'];   -- fc-1a 판정 839 · 840: 배송 조건 셋
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
  v_eff_cur  text;   v_eff_acct uuid;   -- [qbo-sync-3-1] 이 호출이 끝난 뒤의 (통화 · A/R 계정) 짝
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
        when 'invoice_split_by_store' then v_cust.invoice_split_by_store::text when 'backorder_mail' then v_cust.backorder_mail::text when 'final_invoice_mail' then v_cust.final_invoice_mail::text end;   -- doc-3a
      if (case when v_field = 'discount_pct' then (v_cur::numeric is distinct from nullif(v_c->>'old', '')::numeric)
               when v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store', 'backorder_mail', 'final_invoice_mail') then (v_cur::boolean is distinct from nullif(v_c->>'old', '')::boolean)   -- doc-3a
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
      elsif v_field in ('is_legal_entity', 'is_active', 'invoice_split_by_store', 'backorder_mail', 'final_invoice_mail') then   -- doc-3a
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
      if v_field in ('backorder_mail', 'final_invoice_mail') and not v_mgr_ok and v_new is distinct from v_cur then   -- doc-3a 판정 529: 같은 결   -- mail-4a 판정 517: 값이 바뀔 때만(같은 값이 실려 와도 막지 않는다)
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
            v_cur := case v_f when 'type' then v_a.type when 'line1' then v_a.line1 when 'line2' then v_a.line2 when 'city' then v_a.city when 'state_province' then v_a.state_province when 'postal_code' then v_a.postal_code when 'country' then v_a.country when 'residential' then v_a.residential::text when 'tailgate_required' then v_a.tailgate_required::text when 'threshold_delivery' then v_a.threshold_delivery::text else v_a.label end;   -- fc-1a: boolean 은 true/false 글자
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

  -- [qbo-sync-3-1 · deferred 499 · 판정 1088 · 1091] 손님마다 이 호출이 끝난 뒤의 (통화 · A/R 계정) 짝을 본다 — 둘을 한 호출(한 저장)로 함께 바꾸면 통과 · 창구 밖 길은 deferred 트리거 customer_account_currency_ck 가 같은 규칙으로 막는다
  for v_cid in select distinct u from unnest(v_money_ok) as u loop
    select * into v_cust from public.customer c where c.id = v_cid;
    select nullif(btrim(x->>'value'), '')::uuid into v_eff_acct from jsonb_array_elements(p_changes) x where x->>'op' = 'set' and x->>'field' = 'ar_account_id' and x->>'customer_id' = v_cid::text limit 1;
    if not found then v_eff_acct := v_cust.ar_account_id; end if;
    select r.code into v_eff_cur from public.ref_currency r where r.id = (select nullif(btrim(x->>'value'), '')::uuid from jsonb_array_elements(p_changes) x where x->>'op' = 'set' and x->>'field' = 'currency_id' and x->>'customer_id' = v_cid::text limit 1);
    if not found then v_eff_cur := coalesce((select r.code from public.ref_currency r where r.id = v_cust.currency_id), v_cust.currency_code); end if;
    if v_eff_cur is not null and v_eff_acct is not null and public.ims_account_currency(v_eff_acct) <> v_eff_cur then
      v_blocks := v_blocks || jsonb_build_object('key', v_cid::text || ':currency_account_mismatch', 'customer_id', v_cid, 'code', 'currency_account_mismatch',
        'message', public.ims_account_currency_msg('Customer', v_cust.name, 'receivable', coalesce((select a.code from public.ref_account a where a.id = v_eff_acct), '?'), public.ims_account_currency(v_eff_acct), v_eff_cur));
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
          when 'parent_id' then update public.customer set parent_id = v_new::uuid, parent_source = 'ims', updated_by = v_staff where id = v_cid;   -- 판정 253 · 678(ldfix-1a2 · 2026-10-24): 창구가 세우거나 바꾸거나 떼면 모두 ims — 뗀 것도 「IMS 가 부모 없음으로 정했다」 는 표식(적재 2단계가 건너뛴다) · 옛 줄은 비울 때 null(256 옛 뜻)
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
          when 'final_invoice_mail' then update public.customer set final_invoice_mail = v_new::boolean, updated_by = v_staff where id = v_cid;   -- doc-3a 판정 529(같은 결)
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
        insert into public.customer_address (customer_id, source, updated_by, type, is_default_for_type, label, line1, line2, city, state_province, postal_code, country, residential, tailgate_required, threshold_delivery)
        values (v_cid, 'manual', v_staff, v_f, coalesce((v_vals->>'is_default_for_type')::boolean, false), nullif(btrim(v_vals->>'label'), ''), nullif(btrim(v_vals->>'line1'), ''), nullif(btrim(v_vals->>'line2'), ''),
                nullif(btrim(v_vals->>'city'), ''), nullif(btrim(v_vals->>'state_province'), ''), nullif(btrim(v_vals->>'postal_code'), ''), nullif(btrim(v_vals->>'country'), ''),
                nullif(btrim(v_vals->>'residential'), '')::boolean, coalesce(nullif(btrim(v_vals->>'tailgate_required'), '')::boolean, false), coalesce(nullif(btrim(v_vals->>'threshold_delivery'), '')::boolean, false))   -- fc-1a 판정 839 · 840
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
          residential = case when v_vals ? 'residential' then nullif(btrim(v_vals->>'residential'), '')::boolean else a.residential end,                                   -- fc-1a 판정 839: null = 기본 규칙(회사 → 상업지 · 사람 → 주거지)
          tailgate_required = case when v_vals ? 'tailgate_required' then coalesce(nullif(btrim(v_vals->>'tailgate_required'), '')::boolean, false) else a.tailgate_required end,   -- fc-1a 판정 840
          threshold_delivery = case when v_vals ? 'threshold_delivery' then coalesce(nullif(btrim(v_vals->>'threshold_delivery'), '')::boolean, false) else a.threshold_delivery end,   -- fc-1a 판정 840
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
$function$;

-- ═══════════════ ⑦ 권한 · comment ═══════════════
revoke all on function public.ims_account_currency(uuid), public.ims_account_currency_msg(text, text, text, text, text, text), public.inv_adjust_account(uuid) from public, anon;
grant execute on function public.ims_account_currency(uuid), public.ims_account_currency_msg(text, text, text, text, text, text), public.inv_adjust_account(uuid) to authenticated, service_role;
revoke all on function public.supplier_account_currency_check(), public.customer_account_currency_check() from public, anon, authenticated, service_role;   -- 트리거 몸은 시스템이 부른다(선례 qbo_job_on_refund_insert)
do $$
begin
  execute format('comment on function public.supplier_create(jsonb, boolean, text[]) is %L', coalesce(obj_description('public.supplier_create(jsonb, boolean, text[])'::regprocedure, 'pg_proc'), '')
    || ' · [2026-11-08 · qbo-sync-3-1 · 판정 1088 · 1091] 통화 블록을 계정 블록 앞으로 · A/P 기본은 통화별 키 supplier_default_account_payable_code_<통화 소문자>(없으면 옛 키 폴백) · 글자 추론 warn currency_account_mismatch 는 같은 code 의 block 으로(ims_account_currency · ims_account_currency_msg) — 트리거 supplier_account_currency_ck 가 마지막 벽');
  execute format('comment on function public.supplier_update(jsonb, boolean, text[]) is %L', coalesce(obj_description('public.supplier_update(jsonb, boolean, text[])'::regprocedure, 'pg_proc'), '')
    || ' · [2026-11-08 · qbo-sync-3-1 · 판정 1088 · 1091] 글자 추론 warn 을 뗐다 · 공급처마다 「이 호출이 끝난 뒤의 (통화 · A/P 계정)」 짝이 어긋나면 block currency_account_mismatch(통화와 계정을 한 호출로 함께 바꾸면 통과) — 트리거 supplier_account_currency_ck(deferred) 가 마지막 벽');
  execute format('comment on function public.customer_create(jsonb, boolean, text[]) is %L', coalesce(obj_description('public.customer_create(jsonb, boolean, text[])'::regprocedure, 'pg_proc'), '')
    || ' · [2026-11-08 · qbo-sync-3-1 · deferred 499 · 판정 1088 · 1091] A/R 기본은 통화별 키 customer_default_ar_account_code_<통화 소문자>(없으면 옛 키 폴백) · A/R 계정 통화 ≠ 손님 통화면 block currency_account_mismatch — 트리거 customer_account_currency_ck 가 마지막 벽');
  execute format('comment on function public.customer_update(jsonb, boolean, text[]) is %L', coalesce(obj_description('public.customer_update(jsonb, boolean, text[])'::regprocedure, 'pg_proc'), '')
    || ' · [2026-11-08 · qbo-sync-3-1 · deferred 499 · 판정 1088 · 1091] 손님마다 「이 호출이 끝난 뒤의 (통화 · A/R 계정)」 짝이 어긋나면 block currency_account_mismatch(함께 바꾸면 통과) — 트리거 customer_account_currency_ck(deferred) 가 마지막 벽');
  execute format('comment on table public.supplier is %L', coalesce(obj_description('public.supplier'::regclass, 'pg_class'), '') || ' · [qbo-sync-3-1 · 1088] CAD 공급처 11 의 account_payable _109_ → _62_ · 트리거 supplier_account_currency_ck(deferred): A/P 계정 통화 = 공급처 통화');
  execute format('comment on table public.customer is %L', coalesce(obj_description('public.customer'::regclass, 'pg_class'), '') || ' · [qbo-sync-3-1 · deferred 499] USD 손님 3 의 ar_account _61_ → _212_ · 트리거 customer_account_currency_ck(deferred): A/R 계정 통화 = 손님 통화');
end $$;
