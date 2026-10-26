# 8. 역할별 찾아보기

<!-- sections 1-7 written (manual-8) · a finder: each role lists its work and links to the section that explains it · no new facts here (ruling 739) -->

<a id="role-start"></a>
## 이 장을 쓰는 법
<!-- screen: none -->
<!-- who: all -->

아래 절마다 역할 하나입니다. 그 역할이 주로 하는 일과, 그 일을 설명하는 이 매뉴얼의 절을 모았습니다. 링크를 누르면 그 절로 갑니다.
이 첫 절의 일은 모두가 씁니다. 역할 절에서는 되풀이하지 않습니다.
궁금한 것은 [자주 묻는 질문](09-faq.md#faq-sign-in)을 봅니다.
화면 글자의 뜻은 [용어집](10-glossary.md#gloss-general)에 있습니다.

### 모두
- IMS 가 무엇인지 알기 → [IMS 란](00-getting-started.md#start-what-is-ims)
- 로그인 · 비밀번호 바꾸기 → [로그인](00-getting-started.md#start-sign-in)
- IMS · WMS · POS 사이 옮기기 → [모드: IMS · WMS · POS](00-getting-started.md#start-modes)
- 메뉴에서 화면 찾기 → [메뉴](00-getting-started.md#start-menu)
- 목록과 상세 쓰기 → [목록과 상세](00-getting-started.md#start-list-detail)
- 검색 · 필터 · 페이지 · CSV → [검색 · 필터 · 페이지 · CSV](00-getting-started.md#start-search-filter)
- 내 역할과 권한으로 할 수 있는 것 보기 → [역할과 권한](00-getting-started.md#start-roles-keys)
- 날짜와 시각 읽기 → [날짜와 시각](00-getting-started.md#start-dates-times)
- build 표시 찾기 → [build 표시](00-getting-started.md#start-build-tag)
- 도움 받기 → [도움 받기](00-getting-started.md#start-getting-help)
- 재고가 얼마나 · 어디 있는지 찾기 → [재고 찾기(Stock Availability)](03-inventory.md#stock-availability)
- IMS 가 나를 어떻게 보는지 보기(System Check) → [System Check](07-settings.md#set-system-check)

### 상태의 뜻
- 판매 오더 → [상태의 뜻](01-sales.md#sales-statuses)
- PO → [상태의 뜻](02-purchasing.md#purch-statuses)
- 트랜스퍼 · 조정 · bin 이동 → [상태의 뜻](03-inventory.md#stock-statuses)
- 창고 화면 → [상태의 뜻(창고)](04-wms.md#wms-statuses)
- POS 판매 → [상태의 뜻](05-pos.md#pos-statuses)

<a id="role-sales"></a>
## 판매
<!-- screen: none -->
<!-- who: sales -->

판매 일은 IMS 모드의 **Sales ▾** 와, 계산대의 POS 모드에서 합니다.
모두가 쓰는 일은 [이 장을 쓰는 법](#role-start)에 있습니다.

### 판매 오더
- 고객 찾기 · 더하기 → [고객 찾기 · 더하기](01-sales.md#sales-customers)
- 판매 오더 시작 → [새 판매 오더](01-sales.md#sales-new-order)
- 라인 넣기 → [라인 넣기](01-sales.md#sales-add-lines)
- 할인 · 딜 · 추가 요금이 어떻게 붙는지 보기 → [할인 · 딜 · 추가 요금](01-sales.md#sales-discounts-deals)
- 쿠폰 쓰기 → [쿠폰 쓰기](01-sales.md#sales-coupons)
- 오더 확정 → [오더 확정](01-sales.md#sales-confirm)
- 창고로 보내기 → [창고로 보내기](01-sales.md#sales-release)
- 오더 되돌리기 → [오더 되돌리기](01-sales.md#sales-undo)
- 오더 나누기 · 합치기 → [오더 나누기 · 합치기](01-sales.md#sales-divide-merge)
- 백오더 살피기 → [백오더](01-sales.md#sales-backorders)
- 오더 취소 → [오더 취소](01-sales.md#sales-cancel)

### POS(계산대)
- POS 시작 → [POS 시작하기](05-pos.md#pos-start)
- 판매 찍기 → [판매 찍기](05-pos.md#pos-sale)
- 가격 · 할인 바꾸기 · 쿠폰 쓰기 → [가격 · 할인 · 쿠폰](05-pos.md#pos-prices)
- B급 팔기 → [B급 팔기](05-pos.md#pos-bgrade)
- 결제 받기 → [결제 받기](05-pos.md#pos-pay)
- 끝내고 인보이스 인쇄 → [끝내고 인보이스 인쇄하기](05-pos.md#pos-finish)
- 판매를 잠시 두고 다시 잡기 → [판매를 잠시 두고 다시 잡기](05-pos.md#pos-park)
- 그날 계산대 결제 맞춰 보기 → [상태의 뜻](05-pos.md#pos-statuses)

### Action Centre
- Action Centre 열기 → [Action Centre 란](06-action-centre.md#action-start)
- 끝내지 않은 POS 판매 찾기 → [POS not finished(끝내지 않은 POS)](06-action-centre.md#action-pos)

**권한**: `sales` 권한([역할과 권한](00-getting-started.md#start-roles-keys))

<a id="role-office"></a>
## 오피스
<!-- screen: none -->
<!-- who: office -->

오피스 일은 IMS 모드의 **Sales ▾** · **Purchasing ▾** · **Inventory ▾** 에서 합니다.
모두가 쓰는 일은 [이 장을 쓰는 법](#role-start)에 있습니다.

### 판매
- 고객 찾기 · 더하기 → [고객 찾기 · 더하기](01-sales.md#sales-customers)
- 고객의 조건 · 청구처 · 본사 바꾸기 (master 권한 필요) → [고객 찾기 · 더하기](01-sales.md#sales-customers)
- 창고로 보내기 → [창고로 보내기](01-sales.md#sales-release)
- 오더 되돌리기 → [오더 되돌리기](01-sales.md#sales-undo)
- 오더 나누기 · 합치기 → [오더 나누기 · 합치기](01-sales.md#sales-divide-merge)
- 백오더 살피기 → [백오더](01-sales.md#sales-backorders)
- 운임 · 그 밖의 비용 넣기 → [운임과 그 밖의 비용](01-sales.md#sales-charges)
- 포장 뒤 비용 넣기 (master 권한 필요) → [운임과 그 밖의 비용](01-sales.md#sales-charges)
- 출고하고 인보이스 → [Ship & invoice(출고 + 인보이스)](01-sales.md#sales-ship-invoice)
- 픽업 오더 · 추적번호 → [픽업 오더와 추적번호](01-sales.md#sales-pickup)
- 문서 인쇄 · 메일 → [인쇄와 메일](01-sales.md#sales-print-email)
- 판매 인보이스 찾기 → [판매 인보이스](01-sales.md#sales-invoices)
- 고객 결제 · 선수금 넣기 → [고객 결제와 선수금](01-sales.md#sales-payments)
- 크레딧 노트 (발행은 매니저 이상) → [크레딧 노트](01-sales.md#sales-credits)
- 웹 오더 다루기 → [웹 오더](01-sales.md#sales-web-orders)
- 판매 CSV 내려받기 → [CSV 내려받기](01-sales.md#sales-csv)
- 제품 · 고객 · 공급처를 고른 칸으로 내보내기 → [검색 · 필터 · 페이지 · CSV](00-getting-started.md#start-search-filter)

### 구매
- 공급처 찾기 · 더하기 → [공급처 찾기 · 더하기](02-purchasing.md#purch-suppliers)
- 공급처 끄기 · 할인 정하기 (master 권한 필요) → [공급처 찾기 · 더하기](02-purchasing.md#purch-suppliers)
- 무엇을 주문할지 정하기 → [무엇을 주문할지 정하기(Reorder Planner)](02-purchasing.md#purch-reorder)
- PO 시작 → [PO 시작하기](02-purchasing.md#purch-new-po)
- 제품의 고정 공급가 바꾸기 (master · cost 권한 필요) → [PO 시작하기](02-purchasing.md#purch-new-po)
- PO 확정하고 보내기 → [PO 확정하고 보내기](02-purchasing.md#purch-confirm)
- 공급처 인보이스 넣기 → [공급처 인보이스 넣기](02-purchasing.md#purch-invoice)
- 공급처 서류 올리기 → [공급처 서류 올리기](02-purchasing.md#purch-documents)
- 운임 · 관세 · 그 밖의 비용 넣기 → [운임 · 관세 · 그 밖의 비용](02-purchasing.md#purch-charges)
- 오피스에서 입고 보기 → [오피스 입고](02-purchasing.md#purch-receipts)
- 공급처 크레딧 넣기 → [공급처 크레딧](02-purchasing.md#purch-credits)
- PO 취소 · 되살리기 · 지우기 → [취소 · 되살리기 · 지우기](02-purchasing.md#purch-undo)
- 구매 CSV 내려받기 → [CSV 내려받기](02-purchasing.md#purch-csv)

### 재고
- 제품 찾기 → [제품 찾기 · 고치기](03-inventory.md#stock-products)
- 제품 고치기 (master 권한 필요) → [제품 찾기 · 고치기](03-inventory.md#stock-products)
- 새 제품 · 세트 · 콤보 만들기 (master 권한 필요) → [새 제품 · 세트 · 콤보 만들기](03-inventory.md#stock-new-product)
- 패밀리 만들기 · 고치기 (master 권한 필요) → [패밀리](03-inventory.md#stock-families)
- 여러 제품을 한꺼번에 고치기 (master 권한 필요) → [여러 제품을 한꺼번에 고치기(Product Sheet)](03-inventory.md#stock-sheet)
- 제품 설명 쓰기 → [설명 · 사진 · 태그 · 웹 숍](03-inventory.md#stock-descriptions)
- 사진 · 태그 · 바코드 고치기 (master 권한 필요) → [설명 · 사진 · 태그 · 웹 숍](03-inventory.md#stock-descriptions)
- 다른 창고로 재고 보내기 → [창고 간 트랜스퍼](03-inventory.md#stock-transfers)
- 오피스에서 bin 사이 옮기기 → [오피스의 bin 이동](03-inventory.md#stock-bin-moves)
- 재고 CSV 내려받기 → [CSV 내려받기](03-inventory.md#stock-csv)

**권한**: 영역마다 권한 — `sales` · `purchasing` · `receiving` · `transfer` · `master`([역할과 권한](00-getting-started.md#start-roles-keys))

<a id="role-accounting"></a>
## 회계
<!-- screen: none -->
<!-- who: accounting -->

회계 일은 IMS 모드의 **Sales ▾** · **Purchasing ▾** 에서 합니다.
모두가 쓰는 일은 [이 장을 쓰는 법](#role-start)에 있습니다.

### 판매
- 판매 인보이스 찾기 → [판매 인보이스](01-sales.md#sales-invoices)
- 고객 결제 · 선수금 넣기 → [고객 결제와 선수금](01-sales.md#sales-payments)
- 크레딧 노트 (발행은 매니저 이상) → [크레딧 노트](01-sales.md#sales-credits)
- 그날 계산대 결제 맞춰 보기 → [상태의 뜻](05-pos.md#pos-statuses)
- 판매 CSV 내려받기 → [CSV 내려받기](01-sales.md#sales-csv)

### 구매
- 공급처 인보이스 넣기 → [공급처 인보이스 넣기](02-purchasing.md#purch-invoice)
- 공급처 서류 올리기 → [공급처 서류 올리기](02-purchasing.md#purch-documents)
- 운임 · 관세 · 그 밖의 비용 넣기 → [운임 · 관세 · 그 밖의 비용](02-purchasing.md#purch-charges)
- 공급처 크레딧 넣기 → [공급처 크레딧](02-purchasing.md#purch-credits)
- 공급처에 돈 내기 → [공급처 결제](02-purchasing.md#purch-payments)
- 구매 CSV 내려받기 → [CSV 내려받기](02-purchasing.md#purch-csv)

### 재고
- 재고 CSV 내려받기 → [CSV 내려받기](03-inventory.md#stock-csv)

### Action Centre
- 덜 받은 즉시 결제 인보이스 찾기 → [Unpaid at hand-over(건넸는데 덜 받음)](06-action-centre.md#action-unpaid)

**권한**: `sales` · `purchasing` 권한([역할과 권한](00-getting-started.md#start-roles-keys))

<a id="role-warehouse"></a>
## 창고
<!-- screen: none -->
<!-- who: warehouse -->

창고 일은 WMS 모드에서 합니다. WMS 화면에서는 **☰ Menu** 맨 끝에 **Manual** 이 있습니다([도움 받기](00-getting-started.md#start-getting-help)).
모두가 쓰는 일은 [이 장을 쓰는 법](#role-start)에 있습니다.

### 창고(WMS)
- WMS 에 들어가기 → [WMS 에 들어가기](04-wms.md#wms-start)
- 오더 픽하기 → [오더 픽하기](04-wms.md#wms-picking)
- 물건이 모자랄 때 → [물건이 모자랄 때](04-wms.md#wms-pick-short)
- 뽑은 오더 검수 → [뽑은 오더 검수(Packing)](04-wms.md#wms-packing)
- 상자 · 팔레트에 담기 → [상자 · 팔레트에 담기(Fulfillment)](04-wms.md#wms-fulfillment)
- PO · 트랜스퍼 받기 → [PO · 트랜스퍼 받기](04-wms.md#wms-receiving)
- 풋어웨이 → [풋어웨이(제자리에 넣기)](04-wms.md#wms-putaway)
- bin 사이 재고 옮기기 → [bin 사이 재고 옮기기](04-wms.md#wms-bin-moves)
- 재고 찾아보기 → [재고 찾아보기](04-wms.md#wms-stock-lookup)

### 재고와 판매
- 창고 간 트랜스퍼 살피기 → [창고 간 트랜스퍼](03-inventory.md#stock-transfers)
- 오피스에서 만든 bin 이동 → [오피스의 bin 이동](03-inventory.md#stock-bin-moves)
- 픽업 오더 건네기 → [픽업 오더와 추적번호](01-sales.md#sales-pickup)

**권한**: 창고 권한 — `picking` · `packing` · `fulfillment` · `wms_receiving` · `stock_move`([역할과 권한](00-getting-started.md#start-roles-keys))

<a id="role-manager"></a>
## 매니저
<!-- screen: none -->
<!-- who: manager -->

매니저는 다른 역할의 일도 합니다 — 그 절들을 봅니다. 이 목록은 매니저 이상만 하는 일입니다.
모두가 쓰는 일은 [이 장을 쓰는 법](#role-start)에 있습니다.

### 판매
- 고객의 백오더 · 인보이스 메일 켜기 · 끄기 → [고객 찾기 · 더하기](01-sales.md#sales-customers)
- counter 오더 만들기 → [새 판매 오더](01-sales.md#sales-new-order)
- 케이스 · 팩을 제 SKU 로 팔기 → [라인 넣기](01-sales.md#sales-add-lines)
- 오더 확정 → [오더 확정](01-sales.md#sales-confirm)
- counter 오더 확정 → [오더 확정](01-sales.md#sales-confirm)
- 오더 보류 → [창고로 보내기](01-sales.md#sales-release)
- counter 오더 되돌리기 → [오더 되돌리기](01-sales.md#sales-undo)
- 오더 나누기 → [오더 나누기 · 합치기](01-sales.md#sales-divide-merge)
- 오더 합치기 → [오더 나누기 · 합치기](01-sales.md#sales-divide-merge)
- 오더의 창고 바꾸기 → [오더 나누기 · 합치기](01-sales.md#sales-divide-merge)
- 백오더 진행 → [백오더](01-sales.md#sales-backorders)
- 놓친 판매 표시 → [백오더](01-sales.md#sales-backorders)
- 백오더 메일 확인 → [백오더](01-sales.md#sales-backorders)
- counter 오더 건네기 → [Ship & invoice(출고 + 인보이스)](01-sales.md#sales-ship-invoice)
- 포장된 오더에서 물건 빼기 → [Ship & invoice(출고 + 인보이스)](01-sales.md#sales-ship-invoice)
- 인보이스 취소 · 다시 발행 → [판매 인보이스](01-sales.md#sales-invoices)
- 고객 결제 환불 · 무효 → [고객 결제와 선수금](01-sales.md#sales-payments)
- 크레딧 노트 발행 → [크레딧 노트](01-sales.md#sales-credits)
- 기다리는 웹 오더 바로 처리 → [웹 오더](01-sales.md#sales-web-orders)
- 오더 취소 → [오더 취소](01-sales.md#sales-cancel)

### 재고
- 재고 조정 → [재고 조정](03-inventory.md#stock-adjustments)
- B급으로 옮기고 가격 정하기 → [B급 재고](03-inventory.md#stock-bgrade)

### 창고
- 오더를 묶음과 웨이브로 나누기 → [오더를 묶음과 웨이브로 나누기](04-wms.md#wms-waves)
- WMS Admin 에서 창고 살피기 → [WMS Admin](04-wms.md#wms-admin)
- 입고를 재고로 확정하기(입고 확정 권한) → [풋어웨이(제자리에 넣기)](04-wms.md#wms-putaway)

### Action Centre
- Action Centre 열기 → [Action Centre 란](06-action-centre.md#action-start)
- 재고 없이 나간 판매 확인 → [Sold without stock(재고 없이 나감)](06-action-centre.md#action-sold-short)
- 덜 받은 즉시 결제 인보이스 찾기 → [Unpaid at hand-over(건넸는데 덜 받음)](06-action-centre.md#action-unpaid)
- 끝내지 않은 POS 판매 찾기 → [POS not finished(끝내지 않은 POS)](06-action-centre.md#action-pos)
- counter 오더 훑어보기 → [Counter orders(counter 오더)](06-action-centre.md#action-counter)
- 새 고객 확인 → [New customers to review(확인할 새 고객)](06-action-centre.md#action-new-customers)

### 설정
- Settings 에서 누가 무엇을 바꾸나 보기 → [Settings 에 있는 것](07-settings.md#set-start)
- 직원 더하기 · 고치기 → [직원(Staff)](07-settings.md#set-staff)
- 목록 관리: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스 → [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master)
- 딜 · 오더 할인 만들기 → [할인 규칙과 딜](07-settings.md#set-deals)
- 쿠폰 발행 · 무효 → [쿠폰](07-settings.md#set-coupons)
- Shopify 가게 연결 확인 · 제품 잇기 · 보내기 → [Shopify 가게](07-settings.md#set-shopify)

**권한**: 매니저 이상 역할과 영역마다 권한([역할과 권한](00-getting-started.md#start-roles-keys))

<a id="role-admin"></a>
## 관리자(admin)
<!-- screen: none -->
<!-- who: admin -->

admin 은 매니저의 일도 합니다 — [매니저](#role-manager)를 봅니다. 이 목록은 admin 만 하는 일입니다.
모두가 쓰는 일은 [이 장을 쓰는 법](#role-start)에 있습니다.

### 설정
- Settings 에서 누가 무엇을 바꾸나 보기 → [Settings 에 있는 것](07-settings.md#set-start)
- Staff 에서 누구든 더하기 · 고치기 → [직원(Staff)](07-settings.md#set-staff)
- Surcharge 그룹 만들기 · 고치기 → [Surcharge 그룹](07-settings.md#set-surcharge)
- 회사 정보 · 문서 양식 정하기 → [문서](07-settings.md#set-documents)
- 백오더 메일 설정 → [백오더 메일(Backorder emails)](07-settings.md#set-mail)
- Google Drive 설정 → [Google Drive](07-settings.md#set-drive)
- Shopify 가게 더하기 · 위치 짝 맞추기 → [Shopify 가게](07-settings.md#set-shopify)

**권한**: admin 역할([역할과 권한](00-getting-started.md#start-roles-keys))

<!-- rulings: 709, 713, 714, 715, 719, 723, 725, 732, 737, 739, 759, 763 -->
