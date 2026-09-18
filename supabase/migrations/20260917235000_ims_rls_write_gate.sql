-- ─────────────────────────────────────────────────────────────
-- 표별 RLS — 읽기는 열어 두고 쓰기만 조인다 (Asung-IMS) · 2026-09-17 밤
--
-- 정본: docs/design/po-module.md §5(마스터·관계·거래 표 규약 — ⚠️ 「RLS auth_all」 문장이 이 차수로 바뀐다 · 회신의 갱신 목록) · §10-h
-- 앞 차수: 20260917230000_ims_staff_roles.sql (커밋 5b4e4c7 · 판정 함수 여섯). 이 파일은 그중 ims_can_write(text) 를 표에 붙인다.
-- 자리: 리시빙 여덟 차수의 ②번. 새 함수 없음 · 새 표 없음 · 트리거 없음 · 데이터 무접촉.
--
-- ⭐ 설계 [Caleb 2026-09-17]
--   읽기(select)  authenticated 전부 · using (true) — 그대로 열어 둔다. 화면들이 서로 참조한다(리시빙이 product·product_barcode 를,
--                 발주가 supplier·ref_currency 를 읽는다). anon 은 이미 전부 회수돼 있어 로그인 안 한 사람은 아무것도 못 본다.
--   쓰기(insert·update·delete)  ims_can_write('<묶음>') — 묶음은 perms 화면 값 넷을 그대로 따른다:
--                 master      ref_ 여덟 · supplier 계열 넷 · product 계열 다섯               (17)
--                 purchasing  po · po_line · po_discount · po_invoice·_line·_discount · po_charge·_alloc · po_payment·_alloc   (10)
--                 receiving   po_receipt_line                                                   (1)
--                 staff       ims_staff — ⚠️ 이미 걸려 있다(ims_is_admin · 20260915141105) · 이 파일은 건드리지 않는다
--   ⚠️ inv_doc_cost(20260910…)는 날짜만 같은 원장(운영) 표 — IMS 모듈이 아니다 · 무접촉.
--
-- ⭐ 정책 이름 = <표>_<동사> (select · insert · update · delete). 한 정책은 한 명령(또는 ALL)만 가지므로 「write」 하나로 셋을 묶을 수 없다.
--   pg_policies 에서 표별로 정렬돼 읽히고, grep 'create policy <표>_' 로 한 표의 정책이 전부 잡힌다.
-- ⭐ 판정 호출은 (select public.ims_can_write('…')) 로 감싼다 — 문장당 한 번 평가(initplan). 감싸지 않으면 행마다 함수가 돌아
--   po_lines_paste 같은 다건 insert 에서 ims_staff 조회가 행 수만큼 반복된다(Supabase 권고 패턴 · auth.uid() 와 같은 이유).
--
-- ═══ DELETE — 표마다 다르다 (실물: grep 'revoke delete\|revoke truncate' 2026091*.sql) ═══
--   마스터 11        ref_brand · ref_category · ref_unit · ref_payment_term · ref_account · ref_currency · ref_warehouse · ref_bin · supplier · product_family · product
--                    → revoke delete, truncate 가 이미 걸려 있다(권한 자체가 없다). delete 정책을 만들지 않는다(정책 3개).
--   관계 표 6        supplier_address · supplier_contact · supplier_discount · product_barcode · product_bom · product_supplier
--                    → truncate 만 회수 · delete 는 열려 있다(§5 관계 표 예외 「잘못 넣은 바코드·구성품은 지운다」) → <표>_delete = master 쓰기 권한(정책 4개).
--   거래 표 10 + 입고 1  po … po_payment_alloc · po_receipt_line
--                    → truncate 만 회수 · delete 열려 있다 · ⚠️ 삭제 RPC 가 이것을 쓴다(전부 security invoker · 호출자 RLS 를 탄다) → <표>_delete 필수(정책 4개).
--                    ⚠️⚠️ for all 정책을 지우고 delete 정책을 빠뜨리면 에러 없이 0행이 돌아온다 — 아래 표에서 「delete 정책」열을 세어 확인할 것.
--
--   | 표                  | 묶음        | delete 지금       | delete 정책 | 지우는 RPC(전부 invoker)                                   |
--   |---------------------|-------------|-------------------|-------------|------------------------------------------------------------|
--   | ref_brand           | master      | 권한 없음(revoke) | 없음        | —                                                          |
--   | ref_category        | master      | 권한 없음         | 없음        | —                                                          |
--   | ref_unit            | master      | 권한 없음         | 없음        | —                                                          |
--   | ref_payment_term    | master      | 권한 없음         | 없음        | —                                                          |
--   | ref_account         | master      | 권한 없음         | 없음        | —                                                          |
--   | ref_currency        | master      | 권한 없음         | 없음        | —                                                          |
--   | ref_warehouse       | master      | 권한 없음         | 없음        | —                                                          |
--   | ref_bin             | master      | 권한 없음         | 없음        | —                                                          |
--   | supplier            | master      | 권한 없음         | 없음        | —                                                          |
--   | product_family      | master      | 권한 없음         | 없음        | —                                                          |
--   | product             | master      | 권한 없음         | 없음        | —                                                          |
--   | supplier_address    | master      | 열림(auth_all)    | master      | — (화면 PostgREST 직접)                                    |
--   | supplier_contact    | master      | 열림              | master      | —                                                          |
--   | supplier_discount   | master      | 열림              | master      | po_discount_delete(p_target='supplier') ⚠️ 구매 RPC 가 마스터를 지운다 |
--   | product_barcode     | master      | 열림              | master      | —                                                          |
--   | product_bom         | master      | 열림              | master      | —                                                          |
--   | product_supplier    | master      | 열림              | master      | —                                                          |
--   | po                  | purchasing  | 열림              | purchasing  | po_doc_delete('po')                                        |
--   | po_line             | purchasing  | 열림              | purchasing  | po_line_delete · (po 삭제 CASCADE)                         |
--   | po_discount         | purchasing  | 열림              | purchasing  | po_discount_delete('po') · (CASCADE)                       |
--   | po_invoice          | purchasing  | 열림              | purchasing  | po_doc_delete('invoice')                                   |
--   | po_invoice_line     | purchasing  | 열림              | purchasing  | po_invoice_line_delete · (CASCADE)                         |
--   | po_invoice_discount | purchasing  | 열림              | purchasing  | po_discount_delete('invoice') · (CASCADE)                  |
--   | po_charge           | purchasing  | 열림              | purchasing  | po_doc_delete('charge')                                    |
--   | po_charge_alloc     | purchasing  | 열림              | purchasing  | po_charge_alloc_delete · (CASCADE)                         |
--   | po_payment          | purchasing  | 열림              | purchasing  | po_doc_delete('payment')                                   |
--   | po_payment_alloc    | purchasing  | 열림              | purchasing  | po_payment_alloc_delete · (CASCADE)                        |
--   | po_receipt_line     | receiving   | 열림              | receiving   | — (완료 RPC 는 다음 차수 · 지금은 아무도 안 쓴다)          |
--   | ims_staff           | staff       | 권한 없음         | (기존 3)    | — 무접촉                                                   |
--   ⚠️ CASCADE 삭제(po → po_line 등)는 부모 delete 정책만 본다 — 자식의 delete 정책은 FK cascade 에 적용되지 않는다(Postgres 규칙). 그래도 자식 정책은 둔다(화면 직접 삭제 경로).
--
-- ═══ 함께 확인한 것 ═══
--   · security definer 인 **쓰기** 함수: 없다 — 2026091* 의 po_* 전부 security invoker(grep 'security (definer|invoker)' 전수 · 50개) · definer 는 ims_is_admin·ims_can_*·ims_access(판정 · 쓰기 없음)뿐.
--     ⇒ 게이트가 뚫리는 함수는 없다. ⚠️ 대신 반대 문제 — 아래 「이견」 ① (0행 삭제·갱신을 성공으로 답하는 RPC).
--   · 뷰 po_list · po_invoice_list · po_charge_list · po_payment_list · po_invoice_money · po_charge_money 전부 with (security_invoker = true) → select 정책(true)만 탄다 · 무영향.
--   · GAS 적재 ImsRefLoad.gs 는 SUPABASE_IMS_SERVICE_KEY(service_role) — RLS 를 안 탄다 · 확인함. ImsLoadProduct.gs·ImsLoadProductSupplier.gs 는 같은 프로젝트 속성을 쓰는 것으로 보이나 키 줄을 직접 보지는 않았다(짐작).
--   · EF ims-staff-create 는 service_role — 무영향 · ims_staff 는 어차피 무접촉.
--   · 시퀀스 po_number_seq USAGE(authenticated) 무접촉 · anon 회수 이미 됨(다시 하지 않는다).
--   · po_* 쓰기 RPC 가 마스터 표에 쓰는 곳: po_discount_save / po_discount_delete 의 p_target='supplier' 가 supplier_discount 를 insert/update/delete 한다 —
--     ⇒ 이 차수 뒤에는 'master' 쓰기 권한이 있어야 한다(purchasing 만으로는 insert 는 42501 에러 · delete 는 0행). 마스터를 고치는 일이니 맞는 방향이다 — 회신 이견 ②.
--
-- 되돌리기(필요하면 · 표마다): drop policy <표>_select/_insert/_update/_delete ; create policy auth_all on <표> for all to authenticated using (true) with check (true);
-- ─────────────────────────────────────────────────────────────

-- ═══ A. master — 마스터 11 (delete 권한 없음 → 정책 3) ═══════════════════════════════════════════════

drop policy if exists auth_all on public.ref_brand; drop policy if exists ref_brand_select on public.ref_brand; drop policy if exists ref_brand_insert on public.ref_brand; drop policy if exists ref_brand_update on public.ref_brand;
create policy ref_brand_select on public.ref_brand for select to authenticated using (true);
create policy ref_brand_insert on public.ref_brand for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_brand_update on public.ref_brand for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.ref_category; drop policy if exists ref_category_select on public.ref_category; drop policy if exists ref_category_insert on public.ref_category; drop policy if exists ref_category_update on public.ref_category;
create policy ref_category_select on public.ref_category for select to authenticated using (true);
create policy ref_category_insert on public.ref_category for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_category_update on public.ref_category for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.ref_unit; drop policy if exists ref_unit_select on public.ref_unit; drop policy if exists ref_unit_insert on public.ref_unit; drop policy if exists ref_unit_update on public.ref_unit;
create policy ref_unit_select on public.ref_unit for select to authenticated using (true);
create policy ref_unit_insert on public.ref_unit for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_unit_update on public.ref_unit for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.ref_payment_term; drop policy if exists ref_payment_term_select on public.ref_payment_term; drop policy if exists ref_payment_term_insert on public.ref_payment_term; drop policy if exists ref_payment_term_update on public.ref_payment_term;
create policy ref_payment_term_select on public.ref_payment_term for select to authenticated using (true);
create policy ref_payment_term_insert on public.ref_payment_term for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_payment_term_update on public.ref_payment_term for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.ref_account; drop policy if exists ref_account_select on public.ref_account; drop policy if exists ref_account_insert on public.ref_account; drop policy if exists ref_account_update on public.ref_account;
create policy ref_account_select on public.ref_account for select to authenticated using (true);
create policy ref_account_insert on public.ref_account for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_account_update on public.ref_account for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.ref_currency; drop policy if exists ref_currency_select on public.ref_currency; drop policy if exists ref_currency_insert on public.ref_currency; drop policy if exists ref_currency_update on public.ref_currency;
create policy ref_currency_select on public.ref_currency for select to authenticated using (true);
create policy ref_currency_insert on public.ref_currency for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_currency_update on public.ref_currency for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.ref_warehouse; drop policy if exists ref_warehouse_select on public.ref_warehouse; drop policy if exists ref_warehouse_insert on public.ref_warehouse; drop policy if exists ref_warehouse_update on public.ref_warehouse;
create policy ref_warehouse_select on public.ref_warehouse for select to authenticated using (true);
create policy ref_warehouse_insert on public.ref_warehouse for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_warehouse_update on public.ref_warehouse for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.ref_bin; drop policy if exists ref_bin_select on public.ref_bin; drop policy if exists ref_bin_insert on public.ref_bin; drop policy if exists ref_bin_update on public.ref_bin;
create policy ref_bin_select on public.ref_bin for select to authenticated using (true);
create policy ref_bin_insert on public.ref_bin for insert to authenticated with check ((select public.ims_can_write('master')));
create policy ref_bin_update on public.ref_bin for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.supplier; drop policy if exists supplier_select on public.supplier; drop policy if exists supplier_insert on public.supplier; drop policy if exists supplier_update on public.supplier;
create policy supplier_select on public.supplier for select to authenticated using (true);
create policy supplier_insert on public.supplier for insert to authenticated with check ((select public.ims_can_write('master')));
create policy supplier_update on public.supplier for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.product_family; drop policy if exists product_family_select on public.product_family; drop policy if exists product_family_insert on public.product_family; drop policy if exists product_family_update on public.product_family;
create policy product_family_select on public.product_family for select to authenticated using (true);
create policy product_family_insert on public.product_family for insert to authenticated with check ((select public.ims_can_write('master')));
create policy product_family_update on public.product_family for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.product; drop policy if exists product_select on public.product; drop policy if exists product_insert on public.product; drop policy if exists product_update on public.product;
create policy product_select on public.product for select to authenticated using (true);
create policy product_insert on public.product for insert to authenticated with check ((select public.ims_can_write('master')));
create policy product_update on public.product for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));

-- ═══ B. master — 관계 표 6 (delete 열림 → 정책 4) ═══════════════════════════════════════════════════

drop policy if exists auth_all on public.supplier_address; drop policy if exists supplier_address_select on public.supplier_address; drop policy if exists supplier_address_insert on public.supplier_address; drop policy if exists supplier_address_update on public.supplier_address; drop policy if exists supplier_address_delete on public.supplier_address;
create policy supplier_address_select on public.supplier_address for select to authenticated using (true);
create policy supplier_address_insert on public.supplier_address for insert to authenticated with check ((select public.ims_can_write('master')));
create policy supplier_address_update on public.supplier_address for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy supplier_address_delete on public.supplier_address for delete to authenticated using ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.supplier_contact; drop policy if exists supplier_contact_select on public.supplier_contact; drop policy if exists supplier_contact_insert on public.supplier_contact; drop policy if exists supplier_contact_update on public.supplier_contact; drop policy if exists supplier_contact_delete on public.supplier_contact;
create policy supplier_contact_select on public.supplier_contact for select to authenticated using (true);
create policy supplier_contact_insert on public.supplier_contact for insert to authenticated with check ((select public.ims_can_write('master')));
create policy supplier_contact_update on public.supplier_contact for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy supplier_contact_delete on public.supplier_contact for delete to authenticated using ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.supplier_discount; drop policy if exists supplier_discount_select on public.supplier_discount; drop policy if exists supplier_discount_insert on public.supplier_discount; drop policy if exists supplier_discount_update on public.supplier_discount; drop policy if exists supplier_discount_delete on public.supplier_discount;
create policy supplier_discount_select on public.supplier_discount for select to authenticated using (true);
create policy supplier_discount_insert on public.supplier_discount for insert to authenticated with check ((select public.ims_can_write('master')));
create policy supplier_discount_update on public.supplier_discount for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy supplier_discount_delete on public.supplier_discount for delete to authenticated using ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.product_barcode; drop policy if exists product_barcode_select on public.product_barcode; drop policy if exists product_barcode_insert on public.product_barcode; drop policy if exists product_barcode_update on public.product_barcode; drop policy if exists product_barcode_delete on public.product_barcode;
create policy product_barcode_select on public.product_barcode for select to authenticated using (true);
create policy product_barcode_insert on public.product_barcode for insert to authenticated with check ((select public.ims_can_write('master')));
create policy product_barcode_update on public.product_barcode for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy product_barcode_delete on public.product_barcode for delete to authenticated using ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.product_bom; drop policy if exists product_bom_select on public.product_bom; drop policy if exists product_bom_insert on public.product_bom; drop policy if exists product_bom_update on public.product_bom; drop policy if exists product_bom_delete on public.product_bom;
create policy product_bom_select on public.product_bom for select to authenticated using (true);
create policy product_bom_insert on public.product_bom for insert to authenticated with check ((select public.ims_can_write('master')));
create policy product_bom_update on public.product_bom for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy product_bom_delete on public.product_bom for delete to authenticated using ((select public.ims_can_write('master')));

drop policy if exists auth_all on public.product_supplier; drop policy if exists product_supplier_select on public.product_supplier; drop policy if exists product_supplier_insert on public.product_supplier; drop policy if exists product_supplier_update on public.product_supplier; drop policy if exists product_supplier_delete on public.product_supplier;
create policy product_supplier_select on public.product_supplier for select to authenticated using (true);
create policy product_supplier_insert on public.product_supplier for insert to authenticated with check ((select public.ims_can_write('master')));
create policy product_supplier_update on public.product_supplier for update to authenticated using ((select public.ims_can_write('master'))) with check ((select public.ims_can_write('master')));
create policy product_supplier_delete on public.product_supplier for delete to authenticated using ((select public.ims_can_write('master')));

-- ═══ C. purchasing — 거래 표 10 (delete 열림 · 삭제 RPC 가 쓴다 → 정책 4) ═══════════════════════════

drop policy if exists auth_all on public.po; drop policy if exists po_select on public.po; drop policy if exists po_insert on public.po; drop policy if exists po_update on public.po; drop policy if exists po_delete on public.po;
create policy po_select on public.po for select to authenticated using (true);
create policy po_insert on public.po for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_update on public.po for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_delete on public.po for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_line; drop policy if exists po_line_select on public.po_line; drop policy if exists po_line_insert on public.po_line; drop policy if exists po_line_update on public.po_line; drop policy if exists po_line_delete on public.po_line;
create policy po_line_select on public.po_line for select to authenticated using (true);
create policy po_line_insert on public.po_line for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_line_update on public.po_line for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_line_delete on public.po_line for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_discount; drop policy if exists po_discount_select on public.po_discount; drop policy if exists po_discount_insert on public.po_discount; drop policy if exists po_discount_update on public.po_discount; drop policy if exists po_discount_delete on public.po_discount;
create policy po_discount_select on public.po_discount for select to authenticated using (true);
create policy po_discount_insert on public.po_discount for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_discount_update on public.po_discount for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_discount_delete on public.po_discount for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_invoice; drop policy if exists po_invoice_select on public.po_invoice; drop policy if exists po_invoice_insert on public.po_invoice; drop policy if exists po_invoice_update on public.po_invoice; drop policy if exists po_invoice_delete on public.po_invoice;
create policy po_invoice_select on public.po_invoice for select to authenticated using (true);
create policy po_invoice_insert on public.po_invoice for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_invoice_update on public.po_invoice for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_invoice_delete on public.po_invoice for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_invoice_line; drop policy if exists po_invoice_line_select on public.po_invoice_line; drop policy if exists po_invoice_line_insert on public.po_invoice_line; drop policy if exists po_invoice_line_update on public.po_invoice_line; drop policy if exists po_invoice_line_delete on public.po_invoice_line;
create policy po_invoice_line_select on public.po_invoice_line for select to authenticated using (true);
create policy po_invoice_line_insert on public.po_invoice_line for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_invoice_line_update on public.po_invoice_line for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_invoice_line_delete on public.po_invoice_line for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_invoice_discount; drop policy if exists po_invoice_discount_select on public.po_invoice_discount; drop policy if exists po_invoice_discount_insert on public.po_invoice_discount; drop policy if exists po_invoice_discount_update on public.po_invoice_discount; drop policy if exists po_invoice_discount_delete on public.po_invoice_discount;
create policy po_invoice_discount_select on public.po_invoice_discount for select to authenticated using (true);
create policy po_invoice_discount_insert on public.po_invoice_discount for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_invoice_discount_update on public.po_invoice_discount for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_invoice_discount_delete on public.po_invoice_discount for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_charge; drop policy if exists po_charge_select on public.po_charge; drop policy if exists po_charge_insert on public.po_charge; drop policy if exists po_charge_update on public.po_charge; drop policy if exists po_charge_delete on public.po_charge;
create policy po_charge_select on public.po_charge for select to authenticated using (true);
create policy po_charge_insert on public.po_charge for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_charge_update on public.po_charge for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_charge_delete on public.po_charge for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_charge_alloc; drop policy if exists po_charge_alloc_select on public.po_charge_alloc; drop policy if exists po_charge_alloc_insert on public.po_charge_alloc; drop policy if exists po_charge_alloc_update on public.po_charge_alloc; drop policy if exists po_charge_alloc_delete on public.po_charge_alloc;
create policy po_charge_alloc_select on public.po_charge_alloc for select to authenticated using (true);
create policy po_charge_alloc_insert on public.po_charge_alloc for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_charge_alloc_update on public.po_charge_alloc for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_charge_alloc_delete on public.po_charge_alloc for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_payment; drop policy if exists po_payment_select on public.po_payment; drop policy if exists po_payment_insert on public.po_payment; drop policy if exists po_payment_update on public.po_payment; drop policy if exists po_payment_delete on public.po_payment;
create policy po_payment_select on public.po_payment for select to authenticated using (true);
create policy po_payment_insert on public.po_payment for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_payment_update on public.po_payment for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_payment_delete on public.po_payment for delete to authenticated using ((select public.ims_can_write('purchasing')));

drop policy if exists auth_all on public.po_payment_alloc; drop policy if exists po_payment_alloc_select on public.po_payment_alloc; drop policy if exists po_payment_alloc_insert on public.po_payment_alloc; drop policy if exists po_payment_alloc_update on public.po_payment_alloc; drop policy if exists po_payment_alloc_delete on public.po_payment_alloc;
create policy po_payment_alloc_select on public.po_payment_alloc for select to authenticated using (true);
create policy po_payment_alloc_insert on public.po_payment_alloc for insert to authenticated with check ((select public.ims_can_write('purchasing')));
create policy po_payment_alloc_update on public.po_payment_alloc for update to authenticated using ((select public.ims_can_write('purchasing'))) with check ((select public.ims_can_write('purchasing')));
create policy po_payment_alloc_delete on public.po_payment_alloc for delete to authenticated using ((select public.ims_can_write('purchasing')));

-- ═══ D. receiving — 입고 줄 1 (delete 열림 → 정책 4) ═══════════════════════════════════════════════
-- 왜 purchasing 이 아니라 receiving 인가: 쓰는 사람이 창고(worker · role 기본이 'receiving' 쓰기)다. purchasing 으로 묶으면
-- 창고 직원 전원에게 발주 편집 권한을 줘야 입고가 되고, 반대로 발주 담당은 입고 줄을 직접 고치면 안 된다(입고는 사건 · §11-i).
-- 읽기는 열려 있어 발주 화면의 received_qty(po_list · po_detail)는 그대로 나온다. 완료 RPC(다음 차수)는 invoker 로 이 정책을 탄다.

drop policy if exists auth_all on public.po_receipt_line; drop policy if exists po_receipt_line_select on public.po_receipt_line; drop policy if exists po_receipt_line_insert on public.po_receipt_line; drop policy if exists po_receipt_line_update on public.po_receipt_line; drop policy if exists po_receipt_line_delete on public.po_receipt_line;
create policy po_receipt_line_select on public.po_receipt_line for select to authenticated using (true);
create policy po_receipt_line_insert on public.po_receipt_line for insert to authenticated with check ((select public.ims_can_write('receiving')));
create policy po_receipt_line_update on public.po_receipt_line for update to authenticated using ((select public.ims_can_write('receiving'))) with check ((select public.ims_can_write('receiving')));
create policy po_receipt_line_delete on public.po_receipt_line for delete to authenticated using ((select public.ims_can_write('receiving')));

-- ═══ 검증 (Caleb 실행 · 회신 §5 예상값) ═══
-- select tablename, count(*) from pg_policies where schemaname='public' and tablename !~ '^(wms_|inv_)' group by 1 order by 1;
--   → 마스터 11 = 3 · 관계 6 = 4 · 거래 10 = 4 · po_receipt_line = 4 · ims_staff = 3 (합 101 + 3)
-- select tablename, policyname, cmd from pg_policies where policyname = 'auth_all' and tablename !~ '^(wms_|inv_)';   → 0행
