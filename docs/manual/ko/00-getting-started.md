# 0. 시작하기

이 장은 IMS 를 쓰는 모든 사람 — 매니저 · 관리자 · 회계 · 오피스 · 영업 · 창고 — 을 위한 것입니다.
다른 장보다 먼저 한 번 읽어 주세요. 절마다 짧습니다.

화면의 글자(단추 · 칸 · 상태)는 화면 그대로 영어로 적고, 뜻을 한국어로 붙였습니다.

- [IMS 란](#start-what-is-ims)
- [로그인](#start-sign-in)
- [모드: IMS · WMS · POS](#start-modes)
- [메뉴](#start-menu)
- [목록과 상세](#start-list-detail)
- [검색 · 필터 · 페이지 · CSV](#start-search-filter)
- [역할과 권한](#start-roles-keys)
- [날짜와 시각](#start-dates-times)
- [build 표시](#start-build-tag)
- [도움 받기](#start-getting-help)

<a id="start-what-is-ims"></a>
## IMS 란
<!-- screen: none -->
<!-- who: all -->

**무엇인가**
IMS 는 Asung 이 직접 만든 시스템입니다. 판매 · 구매 · 재고 · 창고가 한 곳에 있습니다.
판매 오더, 그 오더가 잡는 재고, 인보이스, 결제가 모두 IMS 안에 있고 서로 이어져 있습니다.

**무엇이 들어 있나**
- **Sales**(판매) — 고객, 판매 오더, 인보이스, 고객 결제, 크레딧 노트, 백오더, 웹 오더
- **Purchasing**(구매) — PO, 공급처 인보이스와 크레딧, 비용 문서, 공급처 결제, 입고
- **Inventory**(재고) — 브랜치별 재고, 제품, 재고 조정, 창고 간 이동, bin 이동
- **WMS**(창고) — 창고 화면: 픽킹, 패킹, fulfillment, 리시빙, bin 이동
- **POS** — 고객 계정이 있는 고객에게 파는 계산대 화면([POS](05-pos.md#pos-start))

**알아 둘 것**
- 한 가지 일은 한 곳에서 일어납니다. 창고가 오더를 끝내면 오피스가 바로 봅니다. 손으로 옮겨 적을 것이 없습니다.
- 보이는 숫자는 지금 숫자입니다. 숫자가 이상해 보이면 매니저에게 알려 주세요 — [도움 받기](#start-getting-help).

<a id="start-sign-in"></a>
## 로그인
<!-- screen: index.html · BUILD 2026-09-30 · door v1 ; ims-auth.js · BUILD nav v10 -->
<!-- who: all -->

**무엇인가**
회사 이메일과 비밀번호로 들어갑니다. 계정은 매니저나 IMS 관리자가 먼저 만들어 줍니다. 스스로 만들 수는 없습니다.

**언제**
컴퓨터나 태블릿에서 IMS 를 처음 열 때입니다. 그 뒤에는 **Sign Out**(로그아웃)을 누르기 전까지 그 기기가 기억합니다.

**어떻게**
1. 웹 브라우저로 IMS 를 엽니다. Asung 로고가 있는 **Sign In** 카드가 보입니다.
2. **Email** 칸에 회사 이메일을 적습니다.
3. **Password** 칸에 비밀번호를 적습니다.
4. **Sign In** 을 누릅니다(Enter 도 됩니다).
5. IMS 가 내 첫 화면을 엽니다. 어느 화면인지는 하는 일에 따라 다릅니다 — [모드](#start-modes).

**비밀번호를 잊었을 때**
1. **Sign In** 카드의 **Email** 칸에 이메일을 먼저 적습니다.
2. **Forgot your password?** 를 누릅니다.
3. "A reset link has been sent to your email. Please check your inbox."(재설정 링크를 메일로 보냈다)가 나옵니다.
4. 메일을 열고 링크를 누릅니다. IMS 가 열리며 "Set your new password to continue."(새 비밀번호를 정하라)가 나옵니다.
5. **Set password** 를 누르고 새 비밀번호를 두 번 적은 뒤 **Change** 를 누릅니다.
6. "Password changed. Opening…" 이 나오고 내 첫 화면으로 갑니다.

**비밀번호 바꾸기**
1. 어느 IMS 화면이든 오른쪽 위의 **Change Password** 를 누릅니다.
2. **New password** 와 **Confirm new password** 에 새 비밀번호를 두 번 적습니다. 6 글자 이상이어야 합니다.
3. **Change** 를 누릅니다. "Password changed successfully." 가 나옵니다.

**나올 수 있는 글**

| 글 | 뜻 | 할 일 |
|---|---|---|
| Sign-in failed: check your email or password. | 이메일이나 비밀번호가 틀렸다 | 다시 하거나 **Forgot your password?** |
| This account is not registered. Please contact your administrator. | 이 이메일에 IMS 계정이 없다 | 매니저에게 묻는다 |
| This account is inactive. | 계정이 꺼져 있다 | 매니저에게 묻는다 |
| No screens are open to your account yet. Please contact your administrator. | 들어오기는 했지만 받은 화면이 아직 없다 | 매니저에게 권한(key)을 부탁한다 — [역할과 권한](#start-roles-keys) |
| You don't have access to this screen. Please contact your administrator. | 권한이 없는 화면을 열었다 · IMS 가 로그아웃시킨다 | 다시 로그인해 메뉴로 간다 · 그 화면이 필요하면 매니저에게 |

**조심할 것**
- 권한이 없는 화면을 열면 로그아웃되는 화면이 있습니다. 누가 보내 준 링크를 열 때 자주 생깁니다. 다시 로그인하면 내 화면은 그대로 있습니다.
- 여럿이 쓰는 태블릿에서는 일이 끝나면 **Sign Out** 을 누릅니다. 다음 사람이 자기 이름으로 들어올 수 있습니다.

<!-- SCREENSHOT: start-sign-in-1 · Sign In 카드(로고 · Email · Password · Sign In · Forgot your password?) -->

<a id="start-modes"></a>
## 모드: IMS · WMS · POS
<!-- screen: ims-auth.js · BUILD nav v10 ; dashboard.html · BUILD 2026-09-30 · db v1 -->
<!-- who: all -->

**무엇인가**
IMS 에는 모드가 셋 있습니다. 모드마다 한 가지 일을 위한 화면 묶음입니다.

| 모드 | 무엇을 하나 | 첫 화면 |
|---|---|---|
| **IMS** | 오피스 일: 판매 · 구매 · 재고 · 설정 | **Overview** |
| **WMS** | 창고 일: 픽킹 · 패킹 · 리시빙 | 내가 쓸 수 있는 첫 창고 화면 |
| **POS** | 계산대([POS](05-pos.md#pos-start)) | **POS** |

**어떻게**
1. 왼쪽 위 Asung 로고 옆을 봅니다. 모드 단추 **IMS** · **WMS** · **POS** 가 있습니다.
2. 모드를 누르면 그 모드의 첫 화면으로 갑니다. 지금 있는 모드에는 표시가 됩니다.
3. Asung 로고를 누르면 지금 모드의 첫 화면으로 돌아갑니다.

**알아 둘 것**
- 내가 쓸 수 있는 모드만 보입니다. 하나뿐이면 모드 단추가 아예 없습니다.
- 로그인하면 IMS · WMS · POS 순서로 내가 가진 첫 모드가 열립니다.
- **Overview** 는 IMS 의 첫 화면입니다. 지금은 "Overview — coming soon"(곧 생긴다)이라고 나옵니다.

<a id="start-menu"></a>
## 메뉴
<!-- screen: ims-auth.js · BUILD nav v10 -->
<!-- who: all -->

**무엇인가**
IMS 모드에서는 메뉴가 화면 맨 위에 한 줄로 있습니다. 단어를 누르면 화면 목록이 펼쳐집니다.

| 메뉴 | 들어 있는 화면 |
|---|---|
| **Purchasing ▾**(구매) | Purchase Orders · Purchase Invoices & Credits · Charges · Supplier Payments · Purchase Receipts · Suppliers · Reorder Planner |
| **Sales ▾**(판매) | Sales Orders · Web Orders · Sales Invoices · Customer Payments · Credit Notes · Backorders · Customers |
| **Inventory ▾**(재고) | Stock Availability · Products · Product Sheet · Families · Stock Adjustments · B-grade Stock · Transfers · Bin Moves (office) |
| **Action Centre** | 화면 하나 — 펼쳐지지 않고 바로 열린다([Action Centre](06-action-centre.md#action-start)) |
| **Settings ▾**(설정) | Settings · Surcharge Groups · Staff · Discount Rules · Shopify Stores · System Check |

**어떻게**
1. 메뉴 단어를 누릅니다. 예: **Sales ▾**
2. 원하는 화면을 누릅니다. 예: **Sales Orders**

**탭 줄**
**Purchasing** 과 **Sales** 의 문서 화면에서는 메뉴 아래에 탭이 한 줄 더 있습니다. 같은 메뉴의 다른 문서 화면들입니다. 옆 화면으로 한 번에 건너갈 때 씁니다 — 예: **Sales Orders** 에서 **Sales Invoices** 로.

**메뉴나 화면이 안 보이는 까닭**
권한이 있는 화면만 보입니다. 메뉴 단어는 그 안에 내가 볼 수 있는 화면이 하나라도 있을 때만 섭니다. 고장이 아니라 정상입니다 — [역할과 권한](#start-roles-keys).

**WMS 모드에서는**
창고 화면이 탭으로 보이고, **☰ Menu** 단추에도 같은 화면이 있습니다.
WMS 화면에서는 **☰ Menu** 맨 끝에 **Manual** 이 있습니다.

<a id="start-list-detail"></a>
## 목록과 상세
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 ; customers.html · BUILD 2026-10-23 · cs v6 -->
<!-- who: all -->

**무엇인가**
많은 화면 — 예: **Sales Orders** · **Sales Invoices** · **Customer Payments** · **Credit Notes** · **Customers** · **Discount Rules** — 이 두 가지 모양으로 움직입니다.

1. **넓은 목록.** 화면을 열면 큰 목록이 화면 전체를 채웁니다. 찾고 고를 때 씁니다.
2. **목록과 상세.** 한 줄을 고르면 화면이 나뉩니다. 왼쪽에 좁은 목록이 남고, 고른 것이 오른쪽에 열립니다.

**어떻게**
1. 화면을 엽니다. 넓은 목록이 보입니다.
2. 한 줄을 누릅니다. 오른쪽에 상세가 열리고 왼쪽에 좁은 목록이 남습니다.
3. 좁은 목록의 다른 줄을 누르면 그것이 열립니다.
4. 상세 위쪽의 **☰ List** 를 누르면 좁은 목록을 접거나 폅니다. 자리가 더 필요할 때 접습니다.
5. **‹ All orders**(다른 화면에서는 **‹ All invoices** · **‹ All payments** · **‹ All credit notes** · **‹ All customers** · **‹ All deals**)를 누르면 넓은 목록으로 돌아갑니다.

**알아 둘 것**
- 화면 사이의 링크는 바로 그것을 엽니다. 예: 오더에 있는 인보이스 번호를 누르면 **Sales Invoices** 에서 그 인보이스가 열립니다.
- 링크를 열었는데 "That sales order is gone — it was deleted, or the link is old."(지워졌거나 오래된 링크)가 나오면, 목록으로 돌아가 다시 찾습니다.
- **Backorders** · **Web Orders** 처럼 목록 하나뿐이고 나뉘지 않는 화면도 있습니다. 화면마다의 모양은 각 장에서 설명합니다.

<!-- SCREENSHOT: start-list-detail-1 · Sales Orders 나뉜 모양: 왼쪽 좁은 목록 · 오른쪽 오더 하나 · ☰ List 와 ‹ All orders 표시 -->

<a id="start-search-filter"></a>
## 검색 · 필터 · 페이지 · CSV
<!-- screen: so.html · BUILD 2026-10-22 · so csv v3 -->
<!-- who: all -->

**무엇인가**
넓은 목록마다 위에 줄이 하나 있습니다. 검색칸, 필터, **Clear**(지우기) 단추, 그리고 많은 화면에 **↓ CSV** 단추가 있습니다.

**검색하는 법**
1. 검색칸을 누릅니다. 칸 안의 회색 글이 무엇을 찾는지 알려 줍니다. **Sales Orders** 에서는 "SO number · invoice number · customer · reference" 입니다.
2. 찾는 것의 일부를 적습니다. 예: `99001` 또는 고객 이름 일부
3. 적기를 멈추면 잠시 뒤 목록이 저절로 바뀝니다.

**거르는 법**
1. 필터에서 값을 고릅니다. 예: 상태 · 날짜 범위 · 결제 상태
2. 목록에는 모든 필터와 검색에 함께 맞는 줄만 남습니다.
3. **Clear** 를 누르면 필터와 검색이 모두 지워집니다.

**페이지**
- 목록은 한 번에 한 페이지씩 보입니다. 아래 줄이 지금 몇 번째 줄들을 보고 있는지 알려 줍니다.
- **→** 는 다음 페이지, **←** 는 앞 페이지입니다. 왼쪽 좁은 목록도 같습니다.
- 창 안의 작은 찾기 목록 — 예: 넣을 고객이나 제품을 찾을 때 — 은 처음 맞는 것들만 보입니다. "Showing the first matches — type more to narrow."(또는 "Showing the first 60 — type more to narrow.")가 보이면 검색칸에 더 적습니다.

**↓ CSV**
1. 필터와 검색을 원하는 대로 맞춥니다.
2. 넓은 목록의 **↓ CSV** 를 누릅니다.
3. 스프레드시트 파일이 내려받아집니다. 필터에 맞는 줄이 **모두** 들어 있습니다 — 화면의 한 페이지만이 아닙니다.

**조심할 것**
- CSV 는 필터를 따릅니다. 파일이 짧아 보이면 먼저 필터를 봅니다.
- 상세에도 CSV 단추가 따로 있는 화면이 있습니다(예: 오더의 **↓ Lines CSV**). 그것은 그 문서 하나만 내려받습니다. 그 화면의 장에서 설명합니다.

<a id="start-roles-keys"></a>
## 역할과 권한
<!-- screen: staff.html · BUILD 2026-10-20 · st v3a ; stock.html · BUILD 2026-10-23 · stk filt v1 -->
<!-- who: all -->

**무엇인가**
IMS 에서 무엇을 보고 할 수 있는지는 둘이 정합니다: **역할**과 **권한**.
둘 다 매니저가 **Staff** 화면에서 정합니다. 모든 화면 오른쪽 위에 내 이름과 역할이 보입니다.

**역할**
역할은 넷입니다. 낮은 것부터 **worker** · **manager** · **supervisor** · **admin**.
높은 역할일수록 더 많이 할 수 있습니다. 매니저 이상만 쓸 수 있는 단추도 있습니다. 이 매뉴얼에서 「매니저에게 물어라」는 나보다 높은 역할인 사람을 뜻합니다.

**권한**
권한 하나가 IMS 의 한 구역을 엽니다. 권한마다 세 단계가 있습니다.

| 단계 | 할 수 있는 것 |
|---|---|
| **none** | 그 화면이 보이지 않는다 |
| **read** | 화면은 보이지만 아무것도 바꿀 수 없다 |
| **write** | 화면이 보이고 그 안에서 일할 수 있다 |

권한과 **Staff** 화면에 나오는 설명:

| 권한 | 여는 것 |
|---|---|
| `sales` | Sales orders, customer addresses and contacts — 판매 오더 · 고객 주소와 연락처 · 그리고 인보이스 · 결제 · 크레딧 · 백오더 · 웹 오더 · 고객 · POS · [Action Centre](06-action-centre.md#action-start) |
| `purchasing` | Purchase orders, invoices, charges, payments — PO · 공급처 인보이스 · 비용 문서 · 결제 · 그리고 Reorder Planner |
| `receiving` | Receiving and putaway — 오피스의 **Purchase Receipts** 화면 |
| `master` | Settings, suppliers, products, families, supplier products, prices, product tags, deals — 설정 · 공급처 · 제품 · 가격 · 딜 |
| `staff` | Adding and editing people (below your own rank) — 나보다 낮은 사람을 더하고 고치기 |
| `transfer` | Transfers — warehouse to warehouse — 창고 간 이동 |
| `cost` | Inventory cost — stock value, layer values, unit costs — 재고 원가 |
| `picking` · `packing` · `fulfillment` · `wms_receiving` · `stock_move` | 같은 이름의 창고 화면 |

매니저 이상만 받을 수 있는 권한이 있습니다: `shopify` · `wms_manage` · `wms_receiving_confirm` · `stock_adjust`. `doc_template`(문서 양식) 권한은 supervisor 와 admin 몫입니다. 몇몇 권한은 매니저가 그 사람에게 켜 주기 전까지 누구에게나 꺼져 있습니다.

**예**
- `cost` 권한이 없는 사람은 **Stock Availability** 에 **Value**(원가 금액) 칸이 보이지 않습니다. 칸이 아예 없습니다([재고 찾기](03-inventory.md#stock-availability)).
- `sales` 가 **read** 인 사람은 판매 오더를 열 수 있지만, 고치는 단추가 없습니다.
- **Stock Availability** 와 **System Check** 는 권한이 필요 없습니다. 로그인한 사람이면 누구나 봅니다.

**브랜치**
worker 와 manager 는 일부 브랜치에서만 일하도록 정해질 수 있습니다. supervisor 와 admin 은 모든 브랜치에서 일합니다.

**조심할 것**
- 필요한 화면이나 단추가 없으면 고장이 아니라 권한 문제입니다. 매니저에게 권한을 부탁합니다.
- 내 권한은 내가 바꿀 수 없습니다.

<a id="start-dates-times"></a>
## 날짜와 시각
<!-- screen: none -->
<!-- who: all -->

**무엇인가**
IMS 는 토론토 시각으로 시간을 셉니다. 화면에 보이는 모든 시각 — 만든 때 · 바꾼 때 · 보낸 때 — 은 토론토 시각입니다.
IMS 의 「오늘」은 토론토의 오늘입니다. 오늘 발행한 인보이스는 토론토 날짜를 받습니다.

**에드먼튼 직원**
- 에드먼튼은 토론토보다 2 시간 늦습니다. IMS 에 15:00 으로 보이면 에드먼튼은 13:00 입니다.
- 에드먼튼 밤 22:00 이 넘으면 토론토는 이미 다음 날입니다. 그때 한 일은 다음 날 날짜를 받습니다. 늦은 인보이스 · 늦은 입고 때 기억해 두세요.

**시각 없는 날짜**
시각이 없는 날짜(예: 기한 · 오더 날짜)는 그냥 날짜입니다. 시간대에 따라 바뀌지 않습니다.

<a id="start-build-tag"></a>
## build 표시
<!-- screen: ims-auth.js · BUILD nav v10 -->
<!-- who: all -->

**무엇인가**
화면마다 위쪽 로고 옆에 작은 회색 글이 있습니다. 그 화면의 버전을 알려 주는 **build 표시**입니다.
둘이 있습니다.
- 화면 자신의 표시. 예: `2026-10-22 · so csv v3`
- 메뉴의 표시. 예: `nav v10`

**언제**
문제를 알릴 때마다.

**어떻게**
1. 위쪽의 작은 회색 글을 봅니다.
2. 두 표시를 모두 메시지에 적거나, 위쪽이 나오게 화면 전체를 찍습니다.
3. 무엇을 눌렀는지, 무엇을 기대했는지, 무엇이 일어났는지를 덧붙입니다.

**왜**
build 표시가 있으면 어느 버전을 쓰고 있었는지 바로 압니다. 표시가 붙은 알림은 훨씬 빨리 고쳐집니다.

<!-- SCREENSHOT: start-build-tag-1 · 한 화면의 윗줄 · build 표시 두 개 -->

<a id="start-getting-help"></a>
## 도움 받기
<!-- screen: none -->
<!-- who: all -->

**화면에서**
1. 어느 IMS 화면이든 오른쪽 위의 **Manual** 을 누릅니다. 이 매뉴얼이 새 탭에 열려서 하던 일을 잃지 않습니다.
2. **English** 나 **한국어** 를 누릅니다. 고른 언어는 IMS 가 기억합니다.
3. 왼쪽 목차에서 장과 절을 고르거나, **Find a section**(절 찾기)에 적습니다.
- WMS 화면에서는 **☰ Menu** 를 열고 맨 끝의 **Manual** 을 누릅니다.
- 화면마다 **?** 단추가 곧 생깁니다. 누르면 그 화면의 절이 바로 열립니다.

**이 매뉴얼에서**
장마다 한 구역을 다룹니다. 장과 절은 왼쪽 목차에 있습니다.
1 장은 [판매](01-sales.md)입니다.
이 매뉴얼은 IMS 가 어떻게 움직이는지를 적었습니다. IMS 가 매뉴얼과 다르게 움직이면, 그것이 알려야 할 문제입니다.

**누구에게 묻나**
1. 먼저 매니저에게
2. 매니저가 풀지 못하면 매니저가 IMS 관리자에게

**무엇을 보내나**
- 화면 이름과 build 표시 둘([build 표시](#start-build-tag))
- 다루던 오더 · 인보이스 등의 번호(예: `SO-99001`)
- 무엇을 눌렀는지, 무엇을 기대했는지, 대신 무엇이 일어났는지

<!-- rulings: 149, 153, 158, 160, 163, 169, 242, 567, 578, 709, 710, 712, 713, 714, 715, 725, 731 -->
