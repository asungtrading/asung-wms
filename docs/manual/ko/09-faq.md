# 9. 자주 묻는 질문

<!-- questions gathered from chapters 0-8 (Watch out · Good to know · screen messages) · no new facts · real questions are added over time (ruling 740) -->

여기 없는 질문은 매니저에게 묻습니다. 실제로 받은 질문을 이 장에 더해 갑니다.

<a id="faq-sign-in"></a>
## 로그인 · 화면 · 권한
<!-- screen: none -->
<!-- who: all -->

### 왜 로그아웃됐나요?
권한이 없는 화면은 로그아웃시키기도 합니다 — 누가 보낸 화면 링크를 열 때 가장 흔합니다. 다시 로그인하면 내 화면은 그대로 있습니다([로그인](00-getting-started.md#start-sign-in)).

### 화면이나 단추가 왜 없나요?
고장이 아니라 권한입니다. 매니저에게 권한을 부탁합니다([역할과 권한](00-getting-started.md#start-roles-keys)).

### 비밀번호를 잊었어요.
로그인 화면에서 **Forgot your password?** 를 누릅니다. 다른 사람이 따로 할 일은 없습니다([로그인](00-getting-started.md#start-sign-in)).

### 내 권한을 내가 바꿀 수 있나요?
아니요. 나보다 높은 사람이 **Staff** 에서 바꿉니다([역할과 권한](00-getting-started.md#start-roles-keys) · [직원(Staff)](07-settings.md#set-staff)).

### CSV 가 왜 생각보다 짧나요?
CSV 는 필터를 따릅니다. 필터부터 확인합니다([검색 · 필터 · 페이지 · CSV](00-getting-started.md#start-search-filter)).

### 에드먼턴에서는 시각이 왜 2시간 다른가요?
IMS 는 토론토 시각으로 보입니다. 에드먼턴 22:00 이 지나면 토론토는 이미 다음 날입니다([날짜와 시각](00-getting-started.md#start-dates-times)).

### 문제가 생기면 무엇을 보내나요?
화면 이름과 build 표시 둘, 다루던 번호, 무엇을 했고 무엇이 일어났는지, 그리고 **System Check** 캡처([도움 받기](00-getting-started.md#start-getting-help)).

<a id="faq-sales"></a>
## 판매
<!-- screen: none -->
<!-- who: sales, office -->

### 같은 SKU 를 왜 또 못 넣나요?
"same SKU at another price — change that line instead"(같은 SKU 가 다른 가격으로 있다): 이미 있는 라인을 고칩니다([라인 넣기](01-sales.md#sales-add-lines)).

### 쿠폰이 왜 안 먹나요?
IMS 가 **not used** 와 까닭을 보입니다 — 예: 더 큰 할인이 이미 이김, 오더 날짜 전에 기한이 지남([쿠폰 쓰기](01-sales.md#sales-coupons)).

### Reprice 를 해도 오더 할인이 왜 안 바뀌나요?
오더를 나누거나 쪼개면 오더 할인은 처음 주문한 때의 값으로 고정됩니다([할인 · 딜 · 추가 요금](01-sales.md#sales-discounts-deals)).

### 창고에 간 오더는 왜 취소가 안 되나요?
먼저 회수하거나 창고에 돌려 달라고 한 뒤 취소합니다. **Cancel order…** 는 매니저 이상에게만 보입니다([오더 취소](01-sales.md#sales-cancel)).

### 오더를 왜 못 합치나요?
열린 백오더가 있는 오더는 합칠 수 없습니다. 백오더를 먼저 진행합니다([오더 나누기 · 합치기](01-sales.md#sales-divide-merge)).

### 고객에게 돈을 돌려주려면?
charge 로는 안 됩니다 — "A charge cannot be negative — money back is a credit note."(돌려주는 돈은 크레딧 노트)([운임과 그 밖의 비용](01-sales.md#sales-charges) · [크레딧 노트](01-sales.md#sales-credits)).

### 포장된 오더에서 고객이 물건을 빼요.
평소대로 Ship & invoice 를 하고, 매니저가 뺀 수량으로 크레딧 노트를 만들어 지금 그 bin 으로 되돌립니다([Ship & invoice(출고 + 인보이스)](01-sales.md#sales-ship-invoice)).

### 발행한 인보이스의 가격이 틀렸어요.
가격만 높았으면 사유 **Price adjustment** 로 크레딧 노트를 만듭니다 — 고객은 물건을 그대로 가집니다. 인보이스 전체가 틀렸으면 매니저 이상이 **Cancel invoice…** 와 **Reissue…** 를 합니다([크레딧 노트](01-sales.md#sales-credits) · [판매 인보이스](01-sales.md#sales-invoices)).

### 새 고객이 왜 Action Centre 에 뜨나요?
sales 가 만든 고객은 기본 조건으로 시작하고, 매니저가 확인합니다([New customers to review(확인할 새 고객)](06-action-centre.md#action-new-customers)).

<a id="faq-purchasing"></a>
## 구매
<!-- screen: none -->
<!-- who: office, accounting -->

### 공급처 결제를 되돌리려면?
결제에는 취소 상태가 없습니다. **Delete** 가 "the only way to undo one"(되돌리는 유일한 길)이고, 갚았던 것은 다시 갚을 것이 됩니다([공급처 결제](02-purchasing.md#purch-payments)).

### charge 의 Confirm 이 왜 거절되나요?
몫을 다 더한 값이 charge 와 같아질 때까지 Confirm 이 거절됩니다([운임 · 관세 · 그 밖의 비용](02-purchasing.md#purch-charges)).

### PO 를 보낸 뒤 라인을 바꿨어요.
**↓ PO CSV** 를 다시 내려받아 새 파일을 보냅니다([PO 확정하고 보내기](02-purchasing.md#purch-confirm)).

### 초안 PO 를 지웠어요. 번호를 다시 쓰나요?
아니요 — "The number … is not given to another order — it stays empty."(번호는 다른 오더에 주지 않고 비워 둔다)([PO 시작하기](02-purchasing.md#purch-new-po)).

### 서류가 왜 Google Drive 로 안 갔나요?
admin 이 Drive 를 켠 뒤, 거기 정한 시작 날짜부터만 갑니다([공급처 서류 올리기](02-purchasing.md#purch-documents) · [Google Drive](07-settings.md#set-drive)).

### 받은 물건은 언제 재고가 되나요?
[창고](#faq-warehouse) 를 봅니다.

<a id="faq-stock"></a>
## 재고 · 제품
<!-- screen: none -->
<!-- who: office, manager -->

### 재고 조정을 되돌리려면?
확정한 조정은 되돌리거나 지울 수 없습니다. 새 조정으로 고칩니다([재고 조정](03-inventory.md#stock-adjustments)).

### B급 재고는 왜 Available 에 없나요?
B급 재고는 **On hand** · **Available** 에서 빠지고 POS 에서만 팝니다([B급 재고](03-inventory.md#stock-bgrade)).

### Value 칸이 왜 안 보이나요?
`cost` 권한이 필요합니다. 없으면 칸이 아예 없습니다([역할과 권한](00-getting-started.md#start-roles-keys)).

### 세트를 왜 콤보로 못 만드나요?
세트는 콤보가 될 수 없고, 콤보는 세트를 가질 수 없습니다([새 제품 · 세트 · 콤보 만들기](03-inventory.md#stock-new-product)).

### SKU 가 왜 패밀리에서 빠졌나요?
다른 패밀리에 넣은 SKU 는 옛 패밀리에서 빠집니다 — 먼저 확인을 묻습니다([패밀리](03-inventory.md#stock-families)).

### 트랜스퍼가 보낸 것보다 덜 왔어요.
Stock adjustments 권한이 있는 사람이 **Settle in transit** 를 누르고 **Lost** 나 **Returned to sender** 를 고릅니다([창고 간 트랜스퍼](03-inventory.md#stock-transfers)).

### "Sold without stock" 은 무엇인가요?
장부보다 많이 나간 판매 — 물건은 있었고 숫자가 틀렸습니다. 선반을 세고 재고를 고친 뒤 매니저가 확인 표시를 합니다([Sold without stock(재고 없이 나감)](06-action-centre.md#action-sold-short)).

<a id="faq-warehouse"></a>
## 창고
<!-- screen: none -->
<!-- who: warehouse -->

### 선반에 정말 없어요.
**⚠ Not enough stock** 을 누릅니다. 알리지 않은 모자람은 내 실수로 셉니다([물건이 모자랄 때](04-wms.md#wms-pick-short)).

### "Pick complete" 가 왜 안 되나요?
모자란 라인이 있으면 안 됩니다 — "There are short lines. Press 'Complete as incomplete'."([물건이 모자랄 때](04-wms.md#wms-pick-short)).

### 둘이 같은 오더를 픽했어요.
픽 리스트를 보드에 돌려놓을 때는 내 화면의 배치도 닫습니다(**Hold (later)**)([오더 픽하기](04-wms.md#wms-picking)).

### 리시빙에서 "Unknown barcode" 가 나와요.
"Unknown barcode — ask the office to register the product": 제품이 아직 등록되지 않았습니다([PO · 트랜스퍼 받기](04-wms.md#wms-receiving)).

### bin 이름이 왜 거절되나요?
"… is not a bin at … — ask the office to add it"(그 창고에 없는 bin — 오피스에 더해 달라고 한다)([풋어웨이(제자리에 넣기)](04-wms.md#wms-putaway) · [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master)).

### 끝낸 입고를 다시 열려면?
**Complete** 뒤에는 매니저만 다시 엽니다([풋어웨이(제자리에 넣기)](04-wms.md#wms-putaway)).

### 받은 물건은 언제 재고가 되나요?
입고를 확정한 뒤에만 됩니다 — 리시빙 화면이나 **WMS Admin** 에서 입고 확정 권한이 있는 매니저 이상이, 또는 오피스의 **Purchase Receipts** 에서([풋어웨이(제자리에 넣기)](04-wms.md#wms-putaway) · [오피스 입고](02-purchasing.md#purch-receipts)).

### bin 사이로 왜 못 옮기나요?
Bin moves 권한이 필요하고, 사람마다 켭니다. 매니저에게 부탁합니다([bin 사이 재고 옮기기](04-wms.md#wms-bin-moves)).

<a id="faq-pos"></a>
## POS(계산대)
<!-- screen: none -->
<!-- who: sales -->

### 판매를 왜 시작 못 하나요?
"Pick this counter's store first (top left)."(먼저 왼쪽 위에서 매장을 고른다)([POS 시작하기](05-pos.md#pos-start)).

### 고객 계정이 없어요. 그래도 팔 수 있나요?
아니요. 고객 계정을 먼저 만들고 **Customer…** 를 누릅니다([판매 찍기](05-pos.md#pos-sale) · [고객 찾기 · 더하기](01-sales.md#sales-customers)).

### Confirm 이 왜 막히나요?
가격 없는 라인이 있거나 세금 규칙이 없습니다. 라인에 가격을 넣거나 경고 아래 **Tax rule** 을 고릅니다([판매 찍기](05-pos.md#pos-sale)).

### 가격을 왜 0 으로 못 하나요?
"The price must be above 0 — a free item needs a reason (Sales Orders screen)."(무상은 사유가 필요 — Sales Orders 화면)([가격 · 할인 · 쿠폰](05-pos.md#pos-prices)).

### 고객이 물건을 돌려주려 해요.
Finish 뒤에는 POS 에서 판매를 바꿀 수 없습니다. 반품은 크레딧 노트입니다. B급은 최종 판매입니다([끝내고 인보이스 인쇄하기](05-pos.md#pos-finish) · [크레딧 노트](01-sales.md#sales-credits)).

### 고객이 다 못 내요. 그래도 끝낼 수 있나요?
네. Finish 는 막지 않고, 남은 돈은 인보이스에 남습니다([끝내고 인보이스 인쇄하기](05-pos.md#pos-finish)).

### 끝내지 않은 판매는 어디 있나요?
**Parked and open at this store** 에 있습니다. 그날 끝내지 못한 것은 Action Centre 에도 나옵니다([판매를 잠시 두고 다시 잡기](05-pos.md#pos-park) · [POS not finished(끝내지 않은 POS)](06-action-centre.md#action-pos)).

### 계산대 하루 마감은?
현금 세기와 카드 단말기 마감은 IMS 밖에서 합니다. 그날 결제는 **Customer Payments** 와 **↓ CSV** 로 맞춰 봅니다([상태의 뜻](05-pos.md#pos-statuses)).

<a id="faq-settings"></a>
## 설정
<!-- screen: none -->
<!-- who: manager, admin -->

### 브랜드 이름을 왜 못 바꾸나요?
이름은 바꿀 수 없습니다. 옛것을 끄고 새로 만듭니다([목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](07-settings.md#set-master)).

### Staff 에서 이 사람을 왜 못 고치나요?
나보다 낮은 역할의 사람만 고칠 수 있고, 나 자신은 못 고칩니다([직원(Staff)](07-settings.md#set-staff)).

### 직원을 지우려면?
지우기는 없습니다. **Active** 를 끕니다([직원(Staff)](07-settings.md#set-staff)).

### 직원이 비밀번호를 잊었어요.
[로그인 · 화면 · 권한](#faq-sign-in) 를 봅니다.

### 문서가 왜 인쇄되지 않나요?
"This document cannot print until a layout is in use."(쓰는 양식이 없으면 인쇄되지 않는다)([문서](07-settings.md#set-documents)).

### 딜이 저장되지 않았어요 — 다른 사람이 저장했대요.
**Load the latest version** 을 누르고 다시 바꿉니다([할인 규칙과 딜](07-settings.md#set-deals)).

### 쿠폰의 마지막 날을 바꾸려면?
Void 하고 새로 발행합니다([쿠폰](07-settings.md#set-coupons)).

<!-- rulings: 42, 709, 713, 714, 715, 719, 723, 725, 732, 736, 737, 739, 740, 742 -->
