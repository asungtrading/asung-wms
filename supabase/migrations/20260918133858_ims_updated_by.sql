-- ─────────────────────────────────────────────────────────────
-- 동시 편집(덮어쓰기 알림) 1차 — 바닥: updated_by 칸 + ims_touch 트리거 (Asung-IMS · 2026-09-18)
--
-- 앞 차수: 20260918020000(등급 순서 · 152행 · 적용됨) · 20260918010000(ims_require_write 문장 하나) — 둘 다 고치지 않는다.
-- 리시빙 이관의 마지막 바닥 — 리시빙 표가 처음부터 이 규칙 위에 서야 하므로 리시빙 1번 차수보다 앞에 선다.
-- 이 파일은 표 29 에 칸 하나·인덱스 하나·트리거 갈아 끼우기만 한다. **RPC 는 고치지 않는다**(전수 분류는 회신 §5 · 어디까지 할지는 Caleb).
-- 지시서: ~/asung/prompts/ims-concurrent-edit-1.md · 검토 이견 1~9 · ⬜1~⬜7(회신)
--
-- ⭐⭐ 무엇이 문제인가 [Caleb 2026-09-17] 「간발의 차로 늦게 저장하는 사람에게, 누군가 이미 저장했고 그 값이 뭐다라고 보여 줄 수 있으면 좋겠다. 이름까지」
--   지금은 둘이 같은 것을 열어 놓고 각자 고치면 뒤가 조용히 이긴다. 막자는 게 아니다 — 최신 값을 보고 고친 사람이 이기는 것은 당연하다. 막을 것은 **낡은 값을 보고 고친 경우**다.
--   처방: 저장할 때 「내가 읽었을 때와 같은가」(updated_at)를 보고, 다르면 거부하고 **현재 값 + 마지막으로 고친 사람**을 보여 준다. 그 「사람」이 이 칸이다.
--   절반은 이미 서 있다 — ②-b(20260918000000~013000)의 0행 문장 「… may have been removed or changed by someone else just now」가 추측만 말하고 있다. 이 차수는 그 문장에 실물(누가 · 언제)을 채울 바닥이다.
--
-- ⭐ updated_by 는 서버가 채운다(3-a) — 화면이 주면 공개 anon key 로 아무 id 나 줄 수 있다(created_by 에서 이미 막은 자리 · §13-d).
--   auth.uid() → ims_staff.id 를 트리거가 유도한다 · nullable(기존 행 전부 null · service_role 적재는 auth.uid() 가 없다) · FK ims_staff(id) on delete no action + <표>_updated_by_idx(§5).
--
-- ⭐⭐ set_updated_at() 은 건드리지 않는다(3-b) — 20260911144606 에 하나뿐 · create or replace 로도 다시 만들지 마라(스킬 asung-po §2).
--   ⚠️ [실측 2026-09-18 · 전 마이그레이션 grep] set_updated_at() 을 쓰는 트리거는 **IMS 표 29 개뿐**이다 — wms_* 표에 붙은 것은 0. 지시서 3-b 의 「WMS 표까지 함께 쓴다」는 실물과 다르다(이견 1).
--      그래도 정의는 그대로 둔다 — 규약이고, 갈아 끼운 뒤 0 트리거가 남는 것이 사실이면 그것을 정본에 적는다(말만).
--   ⭐ 새 함수 ims_touch() 를 만들고 IMS 표 29 에서 <표>_set_updated_at 를 **drop** 하고 <표>_touch 를 만든다(⬜1 · 갈아 끼우기) — 표마다 트리거는 여전히 하나 · security definer(ims_staff 를 읽는다) · search_path 고정.
--      하나 더 붙이는 안을 버린 이유: 두 트리거가 둘 다 updated_at 을 쓰면 「어느 것이 이겼나」를 순서(이름 알파벳)로 알아야 하고, 표마다 트리거가 둘이 되어 규약 문구(트리거 하나)가 깨진다.
--
-- ⭐ 재적재가 updated_at 을 전부 움직인다(3-c) — (가) 그대로 둔다(⬜2). Cin7 값이 덮은 것은 사실이고 사람이 알아야 한다. updated_by 는 null = 「system」.
--   ⚠️ service_role 쓰기 경로 [실측 grep] 넷 — GAS 적재 셋(ImsRefLoad · ImsLoadProduct · ImsLoadProductSupplier · SUPABASE_IMS_SERVICE_KEY · upsert) + EF ims-staff-create(ims_staff insert 만).
--   (나)「auth.uid() null 이면 updated_at 을 안 건드린다」는 버린다 — 적재가 실제로 값을 바꿨을 때 그 사실이 사라지고, 트리거가 「누가 부르나」로 동작을 바꾸는 것은 새 규칙이다.
--
-- ⭐ 대상 표 29 — 기억이 아니라 실물(grep create table · 2026091*.sql · inv_doc_cost 는 원장 표라 제외). 권한 규약 ① 의 「표 28」은 하나 적다(po_receipt_line 을 세면 29 · 아래 목록).
--   마스터 8  ref_brand ref_category ref_unit ref_payment_term ref_account ref_currency ref_warehouse ref_bin
--   공급처 4  supplier supplier_address supplier_contact supplier_discount
--   제품 5    product_family product product_barcode product_bom product_supplier
--   거래 11   po po_line po_discount po_receipt_line po_invoice po_invoice_line po_invoice_discount po_charge po_charge_alloc po_payment po_payment_alloc
--   사용자 1  ims_staff
--   ⚠️ po_receipt_line 도 붙인다(⬜5) — 리시빙 1번 차수가 표를 다시 설계해도 「모든 IMS 표는 touch 트리거」 규칙 위에서 설계하는 편이 낫다. 새 표를 만들면 그 마이그레이션이 같은 두 줄을 넣는다.
--   ⚠️ 뷰(po_list 등)에는 칸을 붙이지 않는다 — 넷 다 이미 updated_at 을 내보낸다(⬜6 · 실물 확인).
--
-- 배포: Caleb · supabase db push --db-url "$(cat ~/.asung-testdb-url)"   (⚠️ 테스트 DB Asung-IMS · --db-url 이 보이면 테스트)
-- ─────────────────────────────────────────────────────────────

-- ═══ ① ims_touch() — updated_at 은 지금 · updated_by 는 auth.uid() → ims_staff.id (없으면 null = system) ═══
-- returns trigger 라 PostgREST RPC 로 노출되지 않는다(set_updated_at 과 같다). security definer 인 이유: 쓰는 사람이 ims_staff 를 못 읽어도 트리거는 읽어야 한다(select 는 지금 열려 있지만 규칙이 바뀌어도 이 함수는 돌아야 한다).
create function public.ims_touch()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  new.updated_by := (select s.id from public.ims_staff s where s.auth_user_id = auth.uid());   -- auth.uid() 가 null(service_role 적재)이면 null
  return new;
end;
$$;
comment on function public.ims_touch() is 'IMS 표 공용 BEFORE UPDATE 트리거 — updated_at = now() · updated_by = auth.uid() → ims_staff.id (service_role 적재·EF 는 null = system). set_updated_at() 을 대신한다(IMS 표 29 · 2026-09-18 · 갈아 끼움) — set_updated_at() 정의는 그대로 둔다(규약 · 다시 만들지 마라). security definer · search_path 고정. 동시 편집 1차 바닥(지시서 ims-concurrent-edit-1)';
revoke all on function public.ims_touch() from public, anon;

-- ═══ ② 표 29 — updated_by 칸 · FK 인덱스 · 트리거 갈아 끼우기 ═══
-- 표 이름은 위 목록 그대로(실물 29). 한 표씩 네 문장 — 칸 · 인덱스 · 옛 트리거 drop · 새 트리거. do 블록 하나로 돌리되 목록은 여기 박아 둔다(기억으로 늘리지 마라).
do $$
declare
  t text;
begin
  foreach t in array array[
    'ref_brand','ref_category','ref_unit','ref_payment_term','ref_account','ref_currency','ref_warehouse','ref_bin',
    'supplier','supplier_address','supplier_contact','supplier_discount',
    'product_family','product','product_barcode','product_bom','product_supplier',
    'po','po_line','po_discount','po_receipt_line','po_invoice','po_invoice_line','po_invoice_discount','po_charge','po_charge_alloc','po_payment','po_payment_alloc',
    'ims_staff'
  ] loop
    execute format('alter table public.%I add column if not exists updated_by uuid references public.ims_staff (id) on delete no action', t);
    execute format('create index if not exists %I on public.%I (updated_by)', t || '_updated_by_idx', t);
    execute format('drop trigger if exists %I on public.%I', t || '_set_updated_at', t);
    execute format('create trigger %I before update on public.%I for each row execute function public.ims_touch()', t || '_touch', t);
    execute format('comment on column public.%I.updated_by is %L', t,
      '마지막으로 고친 사람 → ims_staff(id) · ims_touch 트리거가 auth.uid() 로 채운다(화면이 주지 않는다 · anon key 공개) · null = 아직 안 고쳤거나 service_role(적재·EF)이 고쳤다. 동시 편집 알림의 「누가」(2026-09-18)');
  end loop;
end $$;

-- ═══ ③ 표 29 전부 바뀌었는지 — 적용 직후 같은 트랜잭션 밖에서 Caleb 이 본다(아래 검증 ①) ═══


-- ─────────────────────────────────────────────────────────────
-- 검증 (Caleb · 테스트 DB · ⚠️ psql heredoc 한 덩어리 — SQL 도구는 문장마다 연결이 끊긴다(2026-09-17 실측 · set role 이 안 남는다) · 자리표시자 없음 · 실물 id)
-- ─────────────────────────────────────────────────────────────
-- psql "$(cat ~/.asung-testdb-url)" -v ON_ERROR_STOP=1 -P pager=off <<'SQL'
-- -- ① 칸·트리거가 실물로 섰는가
-- select count(*) as updated_by_cols                                   -- → 29
-- from information_schema.columns where table_schema='public' and column_name='updated_by';
-- select count(*) as touch_triggers                                    -- → 29
-- from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
-- where n.nspname='public' and not t.tgisinternal and t.tgname like '%\_touch';
-- select count(*) as set_updated_at_triggers_left                      -- → 0 (WMS 표는 원래 이 함수를 안 썼다 — 0 이 정상 · 0 이 아니면 어느 표인지 tgrelid::regclass 로 본다)
-- from pg_trigger t join pg_proc p on p.oid=t.tgfoid where not t.tgisinternal and p.proname='set_updated_at';
-- select t.tgname, t.tgrelid::regclass from pg_trigger t join pg_class c on c.oid=t.tgrelid
-- where not t.tgisinternal and c.relname like 'wms\_%' order by 2,1;        -- WMS 표의 트리거 목록 — 이 차수 전과 같아야 한다(무접촉)
-- select count(*) as set_updated_at_defs from pg_proc where proname='set_updated_at';   -- ④ → 1
-- select count(*) as ims_touch_defs from pg_proc where proname='ims_touch';             -- → 1
-- -- ② 사람이 고치면 updated_by 가 찍히는가 — Caleb 으로(auth 6cb8a5af-0a29-40fd-b225-96c2c7ad6bf7) · 트랜잭션 안에서 하고 되돌린다
-- begin;
-- set local role authenticated;
-- select set_config('request.jwt.claims', '{"sub":"6cb8a5af-0a29-40fd-b225-96c2c7ad6bf7","role":"authenticated"}', true);
-- update public.po set note = coalesce(note, '') where po_number = 'PO-02007'
--   returning po_number, updated_at, updated_by, (select name from public.ims_staff where id = updated_by) as updated_by_name;
--   -- 예상 1행 · updated_by = Caleb 의 ims_staff.id · updated_by_name 'Caleb …'(실물 이름) · updated_at = 지금
-- -- ③ 대조가 실제로 막는가 — 옛 updated_at 으로 조건을 걸면 0행 · 지금 값으로 걸면 1행
-- update public.po set note = coalesce(note, '') where po_number = 'PO-02007'
--   and updated_at = (select updated_at from public.po where po_number = 'PO-02007') - interval '1 second'
--   returning po_number;                                                 -- 예상 UPDATE 0
-- update public.po set note = coalesce(note, '') where po_number = 'PO-02007'
--   and updated_at = (select updated_at from public.po where po_number = 'PO-02007')
--   returning po_number, updated_at;                                     -- 예상 UPDATE 1 · updated_at 이 또 앞으로
-- rollback;                                                              -- PO-02007 은 그대로(note 무변 · updated_at·updated_by 도 되돌아간다)
-- -- ⑤ service_role 경로 모사 — auth.uid() 없이 고치면 updated_by 가 null 로 덮이는가(가)
-- begin;
-- update public.ref_brand set note = note where id = (select id from public.ref_brand order by name limit 1) returning name, updated_at, updated_by;   -- 예상 updated_by null(system)
-- rollback;
-- SQL
--
-- ims-ui.js(asung-ims)는 브라우저에서만 드러난다 — Caleb 이 볼 것 셋:
--   1. 화면 아홉이 seenAt 을 넘기기 전(다음 차수 전)에는 아무것도 달라지지 않는다 — invoices.html 머리 칸(Due date) 하나를 고쳐 「Saved」가 그대로 뜨는가.
--   2. 대화 Claude 가 한 화면에 seenAt 을 넘긴 뒤: 같은 인보이스를 탭 둘에 열고 A 에서 Due date 를 고친 다음 B 에서 다른 값으로 고친다 → B 에 「Not saved — <이름> changed this record at <토론토 시각> after you opened it …」가 뜨고 B 의 칸이 직전 값으로 돌아가는가(3-i 되돌리기).
--   3. B 를 새로 고쳐(현재 값을 읽고) 다시 고치면 저장되는가 — 「여전히 마지막이 이긴다」.
