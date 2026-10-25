# 10. 용어집

<!-- words as the screens show them · meanings shortened from chapters 0-8 · no new facts -->

단어는 화면에 보이는 글자 그대로 싣습니다. 두 화면이 같은 것을 다른 글자로 보이면 한 줄에 둘 다 씁니다.

<a id="gloss-general"></a>
## 공통
<!-- screen: none -->
<!-- who: all -->

| 화면 글자 | 뜻 | 자세히 |
|---|---|---|
| admin | 네 역할 중 가장 높다. 모든 브랜치에서 일한다. | [역할과 권한](00-getting-started.md#start-roles-keys) |
| before IMS | IMS 이전부터 있던 줄. | [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master) |
| Branch | 토론토 또는 에드먼턴. worker · manager 는 일부 브랜치에서만 일할 수 있다. | [역할과 권한](00-getting-started.md#start-roles-keys) |
| Build tag | 로고 옆 작은 회색 글 — 그 화면의 버전. | [build 표시](00-getting-started.md#start-build-tag) |
| CSV | 스프레드시트 파일. 필터를 따른다. | [검색 · 필터 · 페이지 · CSV](00-getting-started.md#start-search-filter) |
| IMS · WMS · POS (modes) | 세 모드 — 오피스 일 · 창고 일 · 계산대. | [모드: IMS · WMS · POS](00-getting-started.md#start-modes) |
| Key (none · read · write) | IMS 의 한 영역을 여는 권한: none 은 화면 없음 · read 는 보기만 · write 는 일하기. | [역할과 권한](00-getting-started.md#start-roles-keys) |
| Key names (sales, master …) | 권한 이름 목록은 역할과 권한에 있다. | [역할과 권한](00-getting-started.md#start-roles-keys) |
| manager | worker 위의 역할. 어떤 단추는 매니저 이상만 된다. | [역할과 권한](00-getting-started.md#start-roles-keys) |
| supervisor | manager 위의 역할. 모든 브랜치에서 일한다. | [역할과 권한](00-getting-started.md#start-roles-keys) |
| Toronto time | IMS 는 토론토 시각을 쓴다 — 오늘은 토론토의 오늘. | [날짜와 시각](00-getting-started.md#start-dates-times) |
| worker | 네 역할 중 첫째. | [역할과 권한](00-getting-started.md#start-roles-keys) |

<a id="gloss-sales"></a>
## 판매
<!-- screen: none -->
<!-- who: sales, office -->

| 화면 글자 | 뜻 | 자세히 |
|---|---|---|
| Backordered | 아무것도 확보하지 못함. 라인이 백오더 오더로 간다. | [오더 확정](01-sales.md#sales-confirm) |
| Bill to | 인보이스를 받는 고객. | [고객 찾기 · 더하기](01-sales.md#sales-customers) |
| Cancelled | 출고 없이 닫힘. 합친 오더에는 "merged". | [상태의 뜻](01-sales.md#sales-statuses) |
| Confirmed | 확정됨 — 다음은 창고로 보내기. | [상태의 뜻](01-sales.md#sales-statuses) |
| Counter | 계산대에서 건네는 오더 — 매니저 이상이 만든다. | [새 판매 오더](01-sales.md#sales-new-order) |
| Credit note | 인보이스에 대해 고객에게 돈을 돌려준다. | [크레딧 노트](01-sales.md#sales-credits) |
| Draft | 오피스가 오더를 쓰는 중. | [상태의 뜻](01-sales.md#sales-statuses) |
| Draft — reprice suggested (filter) | 만든 뒤 딜이 바뀐 초안. | [상태의 뜻](01-sales.md#sales-statuses) |
| Expired | 처음 오더 날짜에서 90일 동안 아무도 진행하지 않았다. | [백오더](01-sales.md#sales-backorders) |
| Finalized (badge) / Finalized — waiting for the office (filter) | 준비됨 — 오피스가 Ship & invoice 를 해야 한다. | [상태의 뜻](01-sales.md#sales-statuses) |
| Fulfilled | 끝남. | [상태의 뜻](01-sales.md#sales-statuses) |
| Held for orders | 인보이스가 나올 때까지 오더에 잡아 둔 선수금. | [고객 결제와 선수금](01-sales.md#sales-payments) |
| Hold | 오더의 확보 재고를 다른 오더에 풀고 오더를 기다리게 한다 — 오더 전체만, 라인 하나는 안 된다. | [창고로 보내기](01-sales.md#sales-release) |
| Invoice | 같은 청구처의 오더 여럿이 한 인보이스에 들 수 있다. | [판매 인보이스](01-sales.md#sales-invoices) |
| Invoice cancelled (sales) / Shipped (warehouse) | 출고됐지만 인보이스가 취소됨 — 인보이스를 다시 발행한다. | [상태의 뜻](01-sales.md#sales-statuses) |
| Money on account | 아직 붙지 않은 고객 결제. 다음 인보이스에 저절로 붙는다. | [고객 결제와 선수금](01-sales.md#sales-payments) |
| On hold | 보류로 확정됨. 아무것도 확보하지 않는다. | [오더 확정](01-sales.md#sales-confirm) |
| Open (filter) | 끝나지 않은 오더 모두. | [상태의 뜻](01-sales.md#sales-statuses) |
| Partly reserved | 라인 일부가 확보됨. 나머지는 백오더 오더로. | [오더 확정](01-sales.md#sales-confirm) |
| POS (tag) | POS 에서 한 판매. | [상태의 뜻](05-pos.md#pos-statuses) |
| Preorder | 라인이 선주문 오더로 간다. 진행하거나 취소할 때까지 기다린다. | [오더 확정](01-sales.md#sales-confirm) |
| Proceed | 지금 있는 백오더 재고를 확보한다(매니저 이상). | [백오더](01-sales.md#sales-backorders) |
| Recall from WMS | 창고에서 오더를 되돌려 받는다. | [오더 되돌리기](01-sales.md#sales-undo) |
| Release to WMS | 확정된 오더를 창고로 보낸다. | [창고로 보내기](01-sales.md#sales-release) |
| Released to WMS (badge) / With warehouse (filter) | 창고로 보냄 — 창고 매니저를 기다림. | [상태의 뜻](01-sales.md#sales-statuses) |
| reprice | 가격이 낡았을 수 있다 — 오더를 열고 Reprice. | [할인 · 딜 · 추가 요금](01-sales.md#sales-discounts-deals) |
| Reserved | 라인 전체가 확보됨. | [오더 확정](01-sales.md#sales-confirm) |
| Service | 물건 없이 따로 청구하는 서비스. | [새 판매 오더](01-sales.md#sales-new-order) |
| Set parent | 이 고객을 본사의 매장으로 만든다. | [고객 찾기 · 더하기](01-sales.md#sales-customers) |
| Ship & invoice | Finalized 오더를 출고하고 인보이스를 발행한다. | [Ship & invoice(출고 + 인보이스)](01-sales.md#sales-ship-invoice) |
| Shopify | 웹 오더. | [웹 오더](01-sales.md#sales-web-orders) |
| split | 다른 오더에서 쪼개져 나온 오더. | [상태의 뜻](01-sales.md#sales-statuses) |
| unpaid · partly paid · paid · overdue Nd | 오더가 얼마나 결제됐는지 보이는 꼬리표. | [고객 결제와 선수금](01-sales.md#sales-payments) |
| Waiting for pickup | 아직 가져가지 않은 픽업 오더. | [픽업 오더와 추적번호](01-sales.md#sales-pickup) |
| Working (badge) / With warehouse (filter) | 창고가 픽하거나 포장하는 중. | [상태의 뜻](01-sales.md#sales-statuses) |

<a id="gloss-purchasing"></a>
## 구매
<!-- screen: none -->
<!-- who: office, accounting -->

| 화면 글자 | 뜻 | 자세히 |
|---|---|---|
| Cancelled | 취소됨. | [상태의 뜻](02-purchasing.md#purch-statuses) |
| Completed | 끝남. | [상태의 뜻](02-purchasing.md#purch-statuses) |
| Credit due only | 아직 다 쓰지 않은 공급처 크레딧. | [공급처 크레딧](02-purchasing.md#purch-credits) |
| Draft | 오피스가 PO 를 쓰는 중. | [상태의 뜻](02-purchasing.md#purch-statuses) |
| Draft · Confirmed (invoices, credits, charges, receipts) | 쓰는 중 · 확정됨. | [상태의 뜻](02-purchasing.md#purch-statuses) |
| Not fully allocated | PO 에 아직 다 나누지 않은 비용. | [운임 · 관세 · 그 밖의 비용](02-purchasing.md#purch-charges) |
| Ordered | 확정됨 — 공급처가 보내기를 기다림. | [상태의 뜻](02-purchasing.md#purch-statuses) |
| PO | 공급처에 내는 구매 오더. | [PO 시작하기](02-purchasing.md#purch-new-po) |
| Post now | 이미 세고 bin 에 넣은 것을 지금 재고로 — 나머지는 나중에 센다. | [오피스 입고](02-purchasing.md#purch-receipts) |
| Purchasable | 이 공급처에서 아직 사는지. | [공급처 찾기 · 더하기](02-purchasing.md#purch-suppliers) |
| Received | 모두 도착 — 오피스가 마무리한다. | [상태의 뜻](02-purchasing.md#purch-statuses) |
| Receiving | 일부 도착 — 나머지는 오는 중. | [상태의 뜻](02-purchasing.md#purch-statuses) |
| Spread by amount | 비용을 오더 금액 비율로 PO 에 나눈다. | [운임 · 관세 · 그 밖의 비용](02-purchasing.md#purch-charges) |

<a id="gloss-stock"></a>
## 재고 · 제품
<!-- screen: none -->
<!-- who: office, manager -->

| 화면 글자 | 뜻 | 자세히 |
|---|---|---|
| Adjustment | 재고 장부를 선반의 실제에 맞춘다. | [재고 조정](03-inventory.md#stock-adjustments) |
| Allocated | 확정된 판매 오더에 확보된 것. | [재고 찾기(Stock Availability)](03-inventory.md#stock-availability) |
| at warehouse (office) / Released to WMS (warehouse) | 창고로 보냄 — Split & Waves 를 기다림. | [상태의 뜻](03-inventory.md#stock-statuses) |
| Available | 지금 팔 수 있는 것. | [재고 찾기(Stock Availability)](03-inventory.md#stock-availability) |
| B-grade | 포장이 상한 물건 — B급 bin 에 있고 POS 에서만 B급 가격으로 판다. | [B급 재고](03-inventory.md#stock-bgrade) |
| cancelled (transfer) | 취소됨. | [상태의 뜻](03-inventory.md#stock-statuses) |
| Combo | 서로 다른 제품으로 된 SKU 하나 — 재고는 구성품이 가진다. | [새 제품 · 세트 · 콤보 만들기](03-inventory.md#stock-new-product) |
| confirmed (transfer) | 보내는 창고의 재고가 잡혀 있다. | [상태의 뜻](03-inventory.md#stock-statuses) |
| draft (transfer) | 쓰는 중. | [상태의 뜻](03-inventory.md#stock-statuses) |
| Draft · Confirmed (adjustments, bin moves) | 쓰는 중 · 확정됨. | [상태의 뜻](03-inventory.md#stock-statuses) |
| Family | 한 물건의 변형인 제품들. | [패밀리](03-inventory.md#stock-families) |
| Fixed cost | 제품의 고정 공급가. | [새 제품 · 세트 · 콤보 만들기](03-inventory.md#stock-new-product) |
| In transit | 다른 브랜치에서 오는 중. | [재고 찾기(Stock Availability)](03-inventory.md#stock-availability) |
| in transit (office) / In transit (warehouse) | 보내는 창고를 떠났다. | [상태의 뜻](03-inventory.md#stock-statuses) |
| On hand | 이 브랜치 선반에 있는 것. | [재고 찾기(Stock Availability)](03-inventory.md#stock-availability) |
| On order | 확정된 PO 에 있고 아직 안 받은 것. | [재고 찾기(Stock Availability)](03-inventory.md#stock-availability) |
| On sale | 지금 딜이 걸린 제품. | [재고 찾기(Stock Availability)](03-inventory.md#stock-availability) |
| picking (office) / Working (warehouse) | 창고가 작업 중. | [상태의 뜻](03-inventory.md#stock-statuses) |
| received (office) / Received (warehouse) | 도착했다. | [상태의 뜻](03-inventory.md#stock-statuses) |
| receiving (office) / Receiving (warehouse) | 받는 창고가 세는 중. | [상태의 뜻](03-inventory.md#stock-statuses) |
| Set | 같은 제품의 케이스 · 팩 — 재고는 낱개로 센다. | [새 제품 · 세트 · 콤보 만들기](03-inventory.md#stock-new-product) |
| Set discount | 세트의 할인. | [가격 · 할인 · 쿠폰](05-pos.md#pos-prices) |
| Settle in transit | 도착하지 않은 것을 닫는다: Lost 또는 Returned to sender. | [창고 간 트랜스퍼](03-inventory.md#stock-transfers) |
| Transfer | 재고를 한 창고에서 다른 창고로 옮긴다. | [창고 간 트랜스퍼](03-inventory.md#stock-transfers) |
| Transfer res. | 다른 브랜치로 갈 트랜스퍼에 잡아 둔 것. | [재고 찾기(Stock Availability)](03-inventory.md#stock-availability) |
| Zero stock | 재고 · 확보 · 주문이 모두 없는 제품도 보인다. | [재고 찾기(Stock Availability)](03-inventory.md#stock-availability) |

<a id="gloss-warehouse"></a>
## 창고
<!-- screen: none -->
<!-- who: warehouse -->

| 화면 글자 | 뜻 | 자세히 |
|---|---|---|
| batch | 픽 작업 한 덩이 — 큰 오더는 여러 batch 로 나뉜다. | [오더를 묶음과 웨이브로 나누기](04-wms.md#wms-waves) |
| Complete as incomplete | 적게 끝낸다 — 나머지는 백오더가 된다. | [물건이 모자랄 때](04-wms.md#wms-pick-short) |
| Confirm receipt | 이것을 해야 재고가 된다(입고 확정 권한이 있는 매니저 이상). | [풋어웨이(제자리에 넣기)](04-wms.md#wms-putaway) |
| Discrepancy | 작업자별 실수를 보이는 WMS Admin 탭 — ✓ Resolved 로 닫는다. | [WMS Admin](04-wms.md#wms-admin) |
| Finalized | 창고 끝 — 오피스가 Ship & invoice 할 차례. | [상태의 뜻(창고)](04-wms.md#wms-statuses) |
| Fulfillment | 상자 · 팔레트에 담는다. | [상자 · 팔레트에 담기(Fulfillment)](04-wms.md#wms-fulfillment) |
| Hold (later) | 진행을 저장하고 batch 를 대기 목록으로 돌린다. | [오더 픽하기](04-wms.md#wms-picking) |
| I scanned twice | 수량은 맞고 한 개를 두 번 찍었다 — 누구의 실수로도 세지 않는다. | [뽑은 오더 검수(Packing)](04-wms.md#wms-packing) |
| Not enough stock | 선반에 정말 모자란다고 알린다. | [물건이 모자랄 때](04-wms.md#wms-pick-short) |
| off-invoice | 인보이스보다 많이 옴 — 넣어 두고 오피스가 정한다. | [PO · 트랜스퍼 받기](04-wms.md#wms-receiving) |
| Packing | 뽑은 오더를 검수한다. | [뽑은 오더 검수(Packing)](04-wms.md#wms-packing) |
| pick list | batch 의 종이 — 바코드로 그 batch 를 연다. | [WMS 에 들어가기](04-wms.md#wms-start) |
| Put away | 받은 물건을 bin 에 넣는다. | [풋어웨이(제자리에 넣기)](04-wms.md#wms-putaway) |
| Released to WMS | Split & Waves 를 기다림. | [상태의 뜻(창고)](04-wms.md#wms-statuses) |
| Shipped (warehouse) / Invoice cancelled (sales) | 같은 상태: 물건은 나갔고, 인보이스가 취소돼 다시 발행해야 한다. | [상태의 뜻(창고)](04-wms.md#wms-statuses) |
| Split & Waves | 보낸 오더를 픽 작업으로 만드는 창고 매니저 화면. | [오더를 묶음과 웨이브로 나누기](04-wms.md#wms-waves) |
| Staging | → [설정](#gloss-settings) | [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master) |
| wave | 작은 오더를 묶은 한 번의 픽. | [오더를 묶음과 웨이브로 나누기](04-wms.md#wms-waves) |
| Working | 픽 · 검수 · 포장 중. | [상태의 뜻(창고)](04-wms.md#wms-statuses) |

<a id="gloss-pos"></a>
## POS(계산대)
<!-- screen: none -->
<!-- who: sales -->

| 화면 글자 | 뜻 | 자세히 |
|---|---|---|
| B-grade | → [재고 · 제품](#gloss-stock) | [B급 재고](03-inventory.md#stock-bgrade) |
| confirmed (POS) | 금액이 정해지고 물건이 확보됨. | [상태의 뜻](05-pos.md#pos-statuses) |
| draft (POS) | 스캔하는 중. 물건 · 가격 · 쿠폰을 바꿀 수 있다. | [상태의 뜻](05-pos.md#pos-statuses) |
| Final sale | B급 — 반품 · 환불 없음. | [B급 팔기](05-pos.md#pos-bgrade) |
| Finish | 물건을 건네고 인보이스를 한 번에 발행. | [끝내고 인보이스 인쇄하기](05-pos.md#pos-finish) |
| fulfilled (POS) | 끝남 — 물건을 건넸고 인보이스 발행. | [상태의 뜻](05-pos.md#pos-statuses) |
| Paid in full | 낼 돈이 남지 않음. | [끝내고 인보이스 인쇄하기](05-pos.md#pos-finish) |
| Park | 확정된 판매를 옆에 둔다 — 이 매장에 열린 채 남는다. | [판매를 잠시 두고 다시 잡기](05-pos.md#pos-park) |
| Reopen to change items | 확정된 판매를 draft 로 — 받은 결제는 남는다. | [결제 받기](05-pos.md#pos-pay) |
| Still owed | 남은 돈 — 인보이스에 남는다. | [끝내고 인보이스 인쇄하기](05-pos.md#pos-finish) |

<a id="gloss-settings"></a>
## 설정
<!-- screen: none -->
<!-- who: manager, admin -->

| 화면 글자 | 뜻 | 자세히 |
|---|---|---|
| Amount tiers | 오더 할인의 합계 단계와 %. | [할인 규칙과 딜](07-settings.md#set-deals) |
| Carrier | Ship & invoice 에서 고른다 — 종류가 메일 · 송장을 정한다. | [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master) |
| Coupon | 한 오더 할인에 대해 한 고객에게 주는 코드 — 한 번만. | [쿠폰](07-settings.md#set-coupons) |
| Coupon required | 쿠폰 코드가 있는 오더만 이 할인을 받는다. | [할인 규칙과 딜](07-settings.md#set-deals) |
| Deal | Discount Rules 의 라인 할인 또는 오더 할인. | [할인 규칙과 딜](07-settings.md#set-deals) |
| Layout | 문서 모양 — 한 버전을 쓴다. | [문서](07-settings.md#set-documents) |
| Line discount | 어떤 제품에 몇 % 할인. | [할인 규칙과 딜](07-settings.md#set-deals) |
| Order discount | 정한 금액부터 오더 전체에 몇 % 할인. | [할인 규칙과 딜](07-settings.md#set-deals) |
| Payment Term | 기한까지 날 수와 조기 결제 할인. | [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master) |
| Price tier | 라인의 보통 가격이 나오는 곳 — 그다음 가장 좋은 할인. | [라인 넣기](01-sales.md#sales-add-lines) |
| Service (list) | 서비스 오더에 수량 × 단가로 청구. | [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master) |
| Staging | 선반이 아닌 도크 · 받는 자리. | [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master) |
| Start date (Google Drive) | 이 날짜부터의 문서는 Drive 용 사본이 남는다. | [Google Drive](07-settings.md#set-drive) |
| Surcharge group | 관세처럼 어떤 제품에 낱개마다 붙는 요금. | [Surcharge 그룹](07-settings.md#set-surcharge) |
| Use this version | 그 양식 버전을 인쇄용으로 쓴다. | [문서](07-settings.md#set-documents) |

<!-- rulings: 709, 713, 714, 715, 718, 720, 721, 723, 724, 725, 732, 739, 740, 742 -->
