# 7. Settings(설정)

<!-- sections 1-11 written (manual-7a · 7b) · sections follow the work of admins and managers -->
<!-- out of this chapter: what each key opens -> chapter 0 Roles and keys · B-grade stock -> chapter 3 -->

<a id="set-start"></a>
## Settings 에 있는 것
<!-- screen: ims-auth.js · BUILD nav v13 ; system-check.html · BUILD 2026-10-24 · sc v2 -->
<!-- who: manager, admin -->

**무엇인가**
**Settings ▾** 에는 IMS 의 다른 곳이 쓰는 목록과 스위치가 있습니다: 직원 · 브랜드 · bin · 운송사 · 딜 · 문서 양식 · 웹 가게. 대부분은 보기만 하고, 몇 사람만 바꿉니다.

**누가 무엇을 바꾸나**

| 화면 | 보려면 | 바꾸려면 |
|---|---|---|
| **Settings** — 목록 | `master` 권한 | `master` 권한 write |
| **Settings** — Backorder emails · Documents · Google Drive | `master` 권한 | 부분마다 다름 — 그 절을 본다 |
| **Surcharge Groups** | `master` 권한 | admin 만 |
| **Staff** | `staff` 권한 | `staff` 권한 write · 나보다 낮은 역할의 사람만 |
| **Discount Rules** | `master` 권한 | `master` 권한 write |
| **Shopify Stores** | `shopify` 권한 | `shopify` 권한 write — 연결 확인 · 잇기 · 보내기 · 가게 더하기 · 고치기 · 짝 맞추기는 admin |
| **System Check** | 권한 없이 | — 보여 주기만 한다 |

권한 자체는 [역할과 권한](00-getting-started.md#start-roles-keys)을 봅니다.

**절**
- [직원](#set-staff)
- [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](#set-master)
- [할인 규칙과 딜](#set-deals) · [쿠폰](#set-coupons)
- [Surcharge 그룹](#set-surcharge)
- [문서](#set-documents) · [백오더 메일](#set-mail) · [Google Drive](#set-drive)
- [Shopify 가게](#set-shopify)
- [System Check](#set-system-check)

<a id="set-staff"></a>
## 직원(Staff)
<!-- screen: staff.html · BUILD 2026-10-20 · st v3a -->
<!-- who: manager, admin -->

**무엇인가**
**Staff**(**Settings ▾** › **Staff**)는 로그인할 수 있는 사람 모두를 보입니다: 이름 · 이메일 · 역할 · 권한 · 브랜치.

**누가**
`staff` 권한이 write 인 사람. "You can only create and edit people below your own rank."(나보다 낮은 역할의 사람만 만들고 고친다) admin 은 모두를 고칩니다.
- 권한이 없으면: "Read only — you need the 'staff' permission to change people."
- 나와 같거나 높은 사람: "Read only — this person is at or above your own rank."
- 나 자신: "Read only — you cannot edit your own record. Ask someone above you." admin 은 자기 이름 · 메모는 고치지만, 자기 역할 · 상태 · 권한 · 브랜치는 못 바꿉니다 — "you would lock yourself out"(스스로를 잠근다)

**어떻게 — 사람 더하기**
1. **+ Add staff** 를 누릅니다.
2. **Name** 과 **Email** 을 적습니다(예: Staff C, staff.c@example.com). "This becomes the login email."(로그인 이메일이 된다)
3. **Role** 을 고릅니다. 내 역할보다 낮은 것만 고를 수 있습니다.
4. **Create account** 를 누릅니다.
5. "Account created — hand these over once."(계정을 만들었다 — 한 번만 건넨다) **Copy** 를 눌러 이메일과 임시 비밀번호를 그 사람에게 줍니다. "This temporary password is shown only now. It cannot be retrieved later."(임시 비밀번호는 지금만 보인다 — 나중에 다시 볼 수 없다)
6. **Done** 을 누릅니다.

새 사람은 로그인한 뒤 **Change Password** 로 자기 비밀번호를 정합니다([로그인](00-getting-started.md#start-sign-in)).

**어떻게 — 사람 고치기**
1. 목록에서 그 사람을 누릅니다.
2. **Name** · **Role** · **Active** · **Note** 를 고칩니다.
3. **Access** — 권한:
   - **WMS** · **IMS** 중 하나나 둘을 체크하면 그 모드의 권한이 보입니다. "With none ticked every screen shows."(아무것도 체크하지 않으면 모든 화면이 보인다)
   - 권한마다 **none** · **read** · **write** 를 고릅니다.
4. **Location** — 브랜치. 이 사람이 일하는 브랜치를 체크합니다. "None ticked = every warehouse."(체크가 없으면 모든 창고) manager · worker 에게만 효과가 있습니다. supervisor · admin 은 모든 브랜치에서 일합니다.
5. **Save** 를 누릅니다. **Revert** 는 바꾼 것을 버립니다.

**알아 둘 것**
- "There is no delete — inactive people keep their row."(지우기는 없다 — 비활성인 사람도 줄이 남는다) 로그인을 막으려면 **Active** 를 끕니다.
- **Access** 에서 모드 체크를 빼면 저장할 때 그 모드의 권한이 none 이 됩니다. 저장 전에 노란 글로 먼저 알립니다.
- 비밀번호를 잊은 경우 관리자가 따로 할 일은 없습니다. 그 사람이 로그인 화면에서 **Forgot your password?** 를 누릅니다([로그인](00-getting-started.md#start-sign-in)).

**조심할 것**
- 이메일이 로그인입니다. 보이기만 하고 바꾸지 않습니다.

<!-- SCREENSHOT: set-staff-1 · Role · Access · Location 이 보이는 Staff 의 한 사람 -->

<a id="set-master"></a>
## 목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스
<!-- screen: settings.html · BUILD 2026-10-25 · set v8c -->
<!-- who: manager, admin -->

**무엇인가**
**Settings**(**Settings ▾** › **Settings**)는 왼쪽에 목록을 보입니다. 목록을 누르면 열립니다. `master` 권한이 있으면 보고, write 이면 바꿉니다.

**모든 목록**
- **Search** 는 이름(또는 코드)으로 찾습니다. **Active only** 는 꺼진 것을 숨깁니다.
- ← · → 로 페이지를 넘깁니다. 한 번에 100줄입니다.
- **Source** 는 그 줄이 어디서 왔는지 보입니다: "manual"(IMS 에서 만듦) · "before IMS"(IMS 이전부터)

**목록**

| 목록 | 무엇에 쓰나 | 할 수 있는 것 |
|---|---|---|
| **Brand** | 제품 브랜드 | 더하기 · 끄기 · 켜기 |
| **Category** | 제품 분류 | 더하기 · 끄기 · 켜기 |
| **Unit** | 단위 | 더하기 · 끄기 · 켜기 |
| **Currency** | 통화 | 보기만 |
| **Payment Term** | 고객 · 공급처의 결제 조건 | 더하기 · 끄기 · 켜기 |
| **Account** | 계정(코드로) | 보기만 |
| **Warehouse** | 브랜치 | 보기만 |
| **Bin** | 브랜치마다 선반 자리 — "Thousands of bins — search for the one you need"(bin 이 수천 개 — 찾아서 쓴다) | 더하기 · 끄기 · 켜기 · B급 표시 |
| **Carrier** | "Picked at Ship & invoice — the kind decides email and tracking"(Ship & invoice 에서 고른다 — 종류가 메일 · 송장을 정한다) | 더하기 · 고치기 |
| **Service** | "Billed on service orders as quantity × unit price — tax follows the order"(서비스 오더에 수량 × 단가로 · 세금은 오더를 따른다) | 더하기 · 고치기 |

Currency · Account · Warehouse 는 보기만 합니다. 세금 규칙은 고객 · 오더에서 고르기만 하고 여기에 없습니다. 이것들을 바꿀 일이 생기면 IMS 관리자에게 말합니다.

**어떻게 — 목록에 더하기**
1. 목록을 열고 **+ Add** 를 누릅니다(예: **+ Add brand**).
2. **Name** 을 적습니다. "It cannot be renamed later — check the spelling first."(나중에 이름을 바꿀 수 없다 — 철자를 먼저 본다)
3. 목록에 다른 칸이 있으면 채우고 **Add** 를 누릅니다.
- 같은 이름이 꺼진 채 있으면 IMS 가 알려 줍니다: **Active only** 를 풀고 찾아서 켭니다.

**어떻게 — 끄기**
1. 그 줄의 **Switch off** 를 누릅니다. "Nothing is deleted — records that already use it keep it."(지우지 않는다 — 이미 쓰는 기록은 그대로)
2. 다시 쓰려면 **Switch on** 을 누릅니다.

이름은 바꿀 수 없습니다. 이름을 바꾸려면 옛것을 끄고 새로 만듭니다.

**Payment Term**
- **Net days** — "Days until the invoice is due — 0 = due on the invoice date."(인보이스 기한까지 날 수 — 0 은 인보이스 날짜가 기한)
- **Discount days** · **Discount %** — 일찍 내면 주는 할인. 예: 2% 10 Net 30 이면 10일 · 2%. 둘 다 채우거나 둘 다 비웁니다.
- **Split** — "Paid in parts, e.g. 50% COD & 50% Net 30 — Net days is the later part"(나눠 낸다 — Net days 는 뒤의 몫)

**Unit**
"A set's unit is its pack number — a 12-pack set uses the unit 12."(세트의 단위는 팩 수 — 12 개들이 세트는 단위 12)

**Bin**
- **Warehouse** 를 고르고 **Name** 을 적습니다 — "use the spelling on the shelf label"(선반 라벨의 철자대로)
- **Staging** — "A staging spot (dock, receiving area), not a shelf"(선반이 아니라 도크 · 받는 자리)
- **Mark B-grade** 는 B급 bin 으로 만듭니다. "The bin must be empty in the books first."(먼저 장부에서 비어 있어야 한다) **Unmark B-grade** 는 보통 bin 으로 되돌립니다 — B급 재고를 먼저 옮깁니다([B급 재고](03-inventory.md#stock-bgrade)).

**Carrier**
1. **+ Add carrier** 를 누르거나, 줄의 **Edit** 를 누릅니다.
2. **Kind**: **Carrier — tracking number · shipping email**(운송사 — 송장 번호 · 출고 메일) · **Pickup — customer collects**(고객이 가져감) · **Delivery — our truck**(우리 트럭). "The kind cannot change — it decides what old orders did."(종류는 바꿀 수 없다 — 지난 오더가 그것으로 처리됐다)
3. 운송사면: **Shopify name**("exactly as in Shopify's carrier list" — Shopify 운송사 목록과 똑같이) · **Tracking link**("{number} is replaced by each tracking number" — {number} 자리에 송장 번호가 들어간다)
4. **Active** 를 끄면 "not offered at Ship & invoice (old orders keep the name)"(Ship & invoice 에 나오지 않는다 · 지난 오더는 이름을 그대로 가진다). **Save** 를 누릅니다.

**Service**
1. **+ Add service** 를 누르거나, 줄의 **Edit** 를 누릅니다.
2. **Name** — "customers see this name on the invoice"(고객이 인보이스에서 보는 이름). 나중에 바꿀 수 없습니다.
3. **Unit price** — "Filled in when the service is picked on an order; staff can change it on the line."(오더에서 고르면 채워진다 — 라인에서 바꿀 수 있다) **Sales account** — 매출이 들어가는 계정
4. **Save** 를 누릅니다.

<!-- SCREENSHOT: set-master-1 · 왼쪽 목록과 Payment Term 이 열린 Settings -->

<a id="set-deals"></a>
## 할인 규칙과 딜
<!-- screen: discount-rules.html · BUILD dr v3a -->
<!-- who: manager, admin -->

**무엇인가**
**Discount Rules**(**Settings ▾** › **Discount Rules**)에 딜이 있습니다. 딜은 **Line discount**(어떤 제품에 몇 % 할인) 아니면 **Order discount**(정한 금액부터 오더 전체에 몇 % 할인)입니다. 오더에서 할인들이 어떻게 만나는지는 [할인 · 딜 · 추가 요금](01-sales.md#sales-discounts-deals)에 있습니다. 이 절은 딜을 만드는 법입니다.

**누가**
`master` 권한이 있으면 딜을 봅니다. `master` 권한 write 이면 만들고 바꿉니다.

**어떻게 — 딜 찾기**
1. **Live (on · not ended)**(켜져 있고 끝나지 않음) · **Off or ended**(꺼졌거나 끝남) · **All**, 그리고 **Line discounts** · **Order discounts** 를 고릅니다.
2. **Search deal name** 에 적습니다. 딜을 누르면 열립니다.
3. **Price check…** 는 한 고객이 한 제품에 낼 값을 보입니다: **Customer** · **Product** · **Quantity** · **Order date** 를 고르고 **Check**. "Line discounts only — the biggest one wins."(라인 할인만 — 가장 큰 것이 이긴다)

**어떻게 — 라인 할인 만들기**
1. **+ New line discount** 를 누릅니다. **Name** 을 적고 **Active** 를 체크합니다.
2. **From** · **To** — "Empty dates = always on. Dates are checked against the order date."(날짜가 비면 늘 켜짐 — 날짜는 오더 날짜로 본다)
3. **Lines** 에서 **+ Add line** 을 누릅니다. **Discount (%)** 를 적습니다.
4. **Minimum**: **None** · **At least**(몇 개 이상) · **Full case**(케이스 단위)
5. 그 라인이 덮는 것을 더합니다: **Applies to** 또는 **Except**, 그다음 **Brand** · **Category** · **Tag** · **Product**, **Add**.
6. **Customers**(선택): **Only** 또는 **Not**, 그다음 **Customer** · **Branch** · **Price tier**, **Add**. "No customer rules — every active customer."(고객 규칙이 없으면 모든 활성 고객)
7. **Create deal** 을 누릅니다.

**예**
**Discount (%)** 30 · **Minimum** **At least** 6 · **Applies to** **Product** DEMO-001 인 라인. DEMO-001 을 6 개 이상 담은 라인은 30% 할인, 5 개면 이 딜로는 할인이 없습니다.

**어떻게 — 오더 할인 만들기**
1. **+ New order discount** 를 누릅니다. **Name** 을 적고 **Active** 를 체크하고 **From** · **To** 를 정합니다.
2. **Amount tiers** 에서 **+ Add tier** 를 누릅니다. **Order total from ($)**(오더 합계 몇 달러부터) · **Discount (%)** 를 적습니다. 큰 오더를 위한 단계를 더 넣을 수 있습니다.
3. 쿠폰이 있는 오더만 받게 하려면 **Coupon required** 를 체크합니다([쿠폰](#set-coupons)).
4. 필요하면 **Customers** 규칙을 더하고 **Create deal** 을 누릅니다.

**어떻게 — 바꾸기 · 끄기**
1. 딜을 열고 **Edit** 를 누릅니다. "Change what you need, then save once — the server checks everything first."(필요한 것을 바꾸고 한 번에 저장 — 서버가 먼저 모두 확인한다)
2. 라인 하나를 멈추려면 그 라인의 **Turn off** 를 누릅니다. "Lines that orders already used are turned off, not deleted."(오더가 쓴 라인은 지우지 않고 끈다)
3. 딜 전체를 멈추려면 **Active** 를 풉니다.
4. **Save** 를 누릅니다. IMS 가 **What changes**(바뀌는 것)를, 경고가 있으면 **Please confirm** 을 보입니다 — 그다음 **Save anyway**.

**알아 둘 것**
- **Paste lines…** 는 제품 여럿을 한 번에 넣습니다 — 한 줄에 하나: SKU · 할인 % · 최소 수량. 예: `DEMO-001  30%  6`. "Nothing is added until you check the list."(목록을 확인하기 전에는 아무것도 넣지 않는다)
- 고객 규칙: "Same kind = any of them · different kinds = all of them · a "Not" rule always wins."(같은 종류는 하나만 맞으면 · 다른 종류는 모두 맞아야 · Not 은 늘 이긴다)
- **Open orders using it** 은 이 딜이 닿는 열린 오더 수입니다. 바꾸면 그 초안들이 **Reprice** 를 권합니다([할인 · 딜 · 추가 요금](01-sales.md#sales-discounts-deals)).
- 딜은 지울 수 없습니다. 끕니다.

**조심할 것**
- 내가 연 뒤에 다른 사람이 저장했으면 아무것도 저장되지 않습니다. **Load the latest version** 을 누르고 다시 바꿉니다.

<!-- SCREENSHOT: set-deals-1 · Lines · Minimum · Applies to 가 보이는 라인 할인 Edit -->

<a id="set-coupons"></a>
## 쿠폰
<!-- screen: discount-rules.html · BUILD dr v3a -->
<!-- who: manager, admin -->

**무엇인가**
쿠폰은 한 오더 할인에 대해 한 고객에게 주는 코드입니다. "One code per customer · used once · on this deal only."(고객마다 코드 하나 · 한 번만 · 이 딜에서만) 오더에서 쿠폰을 쓰는 법은 [쿠폰 쓰기](01-sales.md#sales-coupons)에 있습니다.

**누가**
`master` 권한 write

**어떻게 — 쿠폰 발행**
1. **Coupon required** 가 체크된 **Order discount** 딜을 엽니다.
2. **Coupons** 에서 **Issue coupons** 를 누릅니다.
3. 고객 이름 일부를 적고 **Find** 를 누릅니다. 고객을 하나씩 눌러 더합니다.
4. **Expires on** — "empty = no limit · checked against the order date"(비면 기한 없음 · 오더 날짜로 본다)
5. **Code prefix** — 선택, 영문자 · 숫자 2~8 자
6. **Issue n coupons** 를 누릅니다. 목록에 고객마다 코드가 나옵니다. **Copy list** 로 복사해 코드를 보내고 **Done** 을 누릅니다.

**어떻게 — 쿠폰 무효(Void)**
1. 코드 옆의 **Void** 를 누릅니다. "It can never be used after this."(이후에는 절대 쓸 수 없다) 메모를 적어도 됩니다.
2. 초안 오더에 붙어 있던 쿠폰이면: "Voided. It was taken off … draft order(s)."(초안 오더 …개에서 뗐다)

**알아 둘 것**
- 머리에 **unused** · **used** · **voided** 수가 나옵니다.
- 쿠폰의 마지막 날을 바꾸려면 Void 하고 새로 발행합니다.

<!-- SCREENSHOT: set-coupons-1 · 고객을 고르고 Expires on 을 넣은 Issue coupons -->

<a id="set-surcharge"></a>
## Surcharge 그룹
<!-- screen: surcharge-groups.html · BUILD 2026-10-02 · sg v1 -->
<!-- who: admin -->

**무엇인가**
Surcharge 그룹은 어떤 제품에 낱개마다 붙는 추가 요금입니다 — 예: 관세. 켜진 그룹의 제품은 새 판매 오더 · POS 라인에 그 요금이 붙습니다.

**누가**
`master` 권한이 있으면 봅니다. 바꾸는 것은 admin 만.

**어떻게 — 그룹 만들기**
1. **New group** 을 누릅니다.
2. **Name** — "This name is printed on the order line and the invoice."(이 이름이 오더 라인과 인보이스에 찍힌다)
3. **Charge as**: **% of the unit price**(단가의 %) 또는 **$ per unit**(낱개마다 $), 그리고 금액
4. **Check** 를 누르고 **Save** 를 누릅니다.

**어떻게 — 제품을 그룹에 넣기**
제품에서 **Edit** 를 누르고 **Surcharge group** 을 고릅니다([제품 찾기 · 고치기](03-inventory.md#stock-products)).

**어떻게 — 그룹 끄기 · 켜기**
- **Turn off**: "New sales order and POS lines stop picking this surcharge up. Products stay in the group, so turning it back on brings it back. Lines already on draft orders keep what they have."(새 판매 오더 · POS 라인에는 붙지 않는다. 제품은 그룹에 남아 다시 켜면 돌아온다. 이미 초안 오더에 있는 라인은 그대로)
- **Turn on**: "New sales order and POS lines for the products in this group pick the surcharge up again from now on."(이제부터 이 그룹 제품의 새 라인에 다시 붙는다)

**알아 둘 것**
- 목록에 그룹마다 **Products**(제품 수)와 **Open draft lines**(그 요금이 붙은 열린 초안 라인)가 나옵니다.
- 오더 라인 하나에 손으로 요금을 붙일 수도 있습니다([할인 · 딜 · 추가 요금](01-sales.md#sales-discounts-deals)).

<a id="set-documents"></a>
## 문서
<!-- screen: settings.html · BUILD 2026-10-25 · set v8c ; ims-doc.js -->
<!-- who: admin -->

**무엇인가**
**Settings** › **Documents** 는 인보이스 · 크레딧 노트 · 판매 오더 · Ship Ready · 내부 영수증의 모양을 정합니다: 회사 정보 · 로고 · 양식(layout) · 글.

**누가**
- 회사 정보 · 로고 · 글과 칸: admin · supervisor · `master` 권한이 있는 사람
- 양식 — 올리기와 **Use this version**: admin, 또는 Document templates 권한이 있는 supervisor

**어떻게 — 회사 정보**
1. **Name** · **HST no.** · **Website** · 두 브랜치(**Label** · **Street** · **City · province · postal** · **Phone** · **Email**) · **Terms & conditions** · **Date format** 을 채웁니다.
2. **Save company details** 를 누릅니다. "Both branches print at the top of every document. A branch with no street is left out."(두 브랜치가 모든 문서 위에 찍힌다 — 주소가 없는 브랜치는 빠진다)
3. **Logo**: 2 MB 이하 PNG · JPEG 를 고르고 **Upload logo**. **Remove logo** 를 하면 회사 이름이 대신 찍힙니다.

**어떻게 — 양식 고르기**
1. **Document** 에서 문서 종류를 고릅니다.
2. **Layout in use** 에 지금 찍히는 버전과 버전 목록이 나옵니다.
3. 보려면 **Preview** 에 번호를 적고 **Preview the layout in use** 또는 **Preview the layout in the box** 를 누릅니다. "Uses a real document. Nothing is saved or sent."(실제 문서를 쓴다 — 저장도 발송도 하지 않는다)
4. **Passed** 인 버전에서 **Use this version** 을 누릅니다. "Documents already printed or sent do not change."(이미 찍었거나 보낸 문서는 바뀌지 않는다)

옛 양식으로 되돌리려면 그 옛 버전에서 **Use this version** 을 누릅니다. "Older versions are kept — nothing is deleted."(옛 버전은 남는다 — 지우지 않는다)

**어떻게 — 새 양식 버전 더하기**
1. 받은 양식 파일을 올리거나 칸에 붙여 넣습니다.
2. 무엇이 바뀌었는지 적고 **Check** 를 누릅니다. 받아들여지지 않은 것을 고칩니다.
3. **Save as new version** 을 누릅니다. "Saving does not change what prints until you press Use this version."(Use this version 을 누르기 전에는 찍히는 것이 바뀌지 않는다)

**어떻게 — 글과 칸**
1. **Title**, 그리고 스위치 **UPC column** · **Line comments** · **Account code on freight lines**
2. **Email subject** · **Email message** — 이 문서를 메일로 보낼 때의 제목과 본문. 보내는 걸음은 [인쇄와 메일](01-sales.md#sales-print-email)에 있습니다.
3. **Save wording & columns** 를 누릅니다.

**조심할 것**
- "This document cannot print until a layout is in use."(쓰는 양식이 없으면 그 문서는 인쇄되지 않는다)

<!-- SCREENSHOT: set-documents-1 · Layout in use · 버전 목록 · Preview 가 보이는 Documents -->

<a id="set-mail"></a>
## 백오더 메일(Backorder emails)
<!-- screen: settings.html · BUILD 2026-10-25 · set v8c -->
<!-- who: admin -->

**무엇인가**
**Settings** › **Backorder emails** 는 백오더 물건이 들어왔다고 고객에게 알리는 메일을 다룹니다.

**누가**
칸마다 누가 바꿀 수 있는지 보입니다: "Only an admin can change this." 또는 "Only a manager with the master permission can change this." 칸마다 마지막으로 바꾼 사람도 보입니다.

**어떻게**
1. **Emails** — **Turn on** · **Turn off**. 켜짐: "Runs start on the scheduled mornings and emails go out."(정한 아침마다 돌고 메일이 나간다) 꺼짐: "Emails that are already waiting stay waiting until this is on."(기다리는 메일은 켤 때까지 기다린다)
2. **Test mode — send every email to** — 여기에 주소가 있으면 모든 메일이 고객 대신 그 주소로 갑니다. 실제 고객에게 보내려면 비웁니다.
3. **Sent from** — 고객이 보는 보낸 주소. 회사 메일함에 "Send mail as" 주소로 설정돼 있어야 합니다.
4. **Sender name** · **Replies go to**("Empty = replies go to the "sent from" address" — 비면 답장은 보낸 주소로)
5. **Schedule** — 브랜치마다 **Send for this branch** 와 요일 · 시각 · 시간대를 고르고 **Save schedule** 을 누릅니다.
6. **Part of a line that came in** — 백오더 수량의 몇 % 가 들어와야 메일을 보낼지. **Save** 를 누릅니다.

**알아 둘 것**
- "Each branch runs once on each checked morning at that hour in its own time."(브랜치마다 고른 아침, 그 시각에 한 번) "Holidays are not skipped."(공휴일도 건너뛰지 않는다)
- 구매 입고나 다른 브랜치에서 온 트랜스퍼는 % 에 셉니다. "Stock from returns, adjustments or counts is emailed only when the whole line can ship. Each line is emailed once."(반품 · 조정 · 실사로 생긴 재고는 라인 전체가 나갈 수 있을 때만 · 라인마다 한 번)

<a id="set-drive"></a>
## Google Drive
<!-- screen: settings.html · BUILD 2026-10-25 · set v8c -->
<!-- who: admin -->

**무엇인가**
**Settings** › **Google Drive** 는 인보이스 · 크레딧 노트 · PO 서류의 보관 사본을 회사 공유 드라이브로 보냅니다([공급처 서류 올리기](02-purchasing.md#purch-documents)).

**누가**
admin 만 바꿉니다. 다른 사람에게는 "Only an admin can change this." 가 보입니다.

**어떻게**
1. **Start date** — 날짜를 고르고 **Save**. 이 날짜부터 발행한 인보이스 · 크레딧 노트는 "get a kept copy (the PDF as it looked when issued) and go to Drive"(발행 때 모습 그대로의 PDF 사본이 남고 Drive 로 간다). **Clear** 는 새 사본을 멈춥니다.
2. **Send to Drive** — **Turn on** · **Turn off**. 켜짐: "Waiting files go to the shared drive every minute."(기다리는 파일이 1분마다 간다) 꺼짐: 사본은 계속 생기고 기다립니다.
3. **Shared drive** — 공유 드라이브의 id 와 **Open in Drive**. "Change it only for a test drive."(시험 드라이브일 때만 바꾼다)

**Queue(대기열)**
종류마다 보낸 파일 수, 기다리는 수, 그리고 **Failed** 목록(파일 · 오류 · 시도 횟수)이 나옵니다.

**알아 둘 것**
- **Start date** 가 비면 Drive 용으로 아무것도 남기지 않고, 대기열에도 넣지 않습니다.
- 실패한 파일은 저절로 다시 시도합니다. 계속 실패하면 IMS 관리자에게 말합니다.
- **System Check** 에도 같은 요약이 나옵니다([System Check](#set-system-check)).

<!-- SCREENSHOT: set-drive-1 · Start date · Send to Drive · Queue 가 보이는 Google Drive -->

<a id="set-shopify"></a>
## Shopify 가게
<!-- screen: shopify-stores.html · BUILD 2026-10-20 · ss v3a -->
<!-- who: admin, manager -->

**무엇인가**
**Shopify Stores**(**Settings ▾** › **Shopify Stores**)는 IMS 를 웹 가게마다 잇습니다: 어느 가격을 보이나, 어느 창고가 재고를 보내나, 어느 제품이 이어져 있나.

**누가**
- `shopify` 권한 read: 보기만
- `shopify` 권한 write: **Check connection**, 제품 잇기와 보내기
- admin: **New store** · **Edit** · **Turn off** / **Turn on** · 위치 짝 맞추기

**어떻게 — 가게(admin)**
1. **New store** 를 누릅니다. **Code**("It cannot be changed later" — 나중에 못 바꾼다) · **Label** · **Shopify address** · **Price tier** · **Compare-at tier** 를 넣습니다.
2. **Sell when out of stock**: **Allow**(재고 0 이어도 주문 받음) 또는 **Don't allow**(재고 0 이면 멈춤)
3. **Send tags** 를 고르고, 따로 들은 것이 없으면 **Key name** 은 그대로 둡니다.
4. **Check** 를 누르고 **Save** 를 누릅니다.

**어떻게 — 연결 확인 · 위치 짝**
1. **Check connection** 을 누릅니다. **Shopify says** 에 그 가게의 위치가 나옵니다.
2. admin: Shopify 위치마다 IMS 창고를 고르고 **Pair** 를 누릅니다. "Stock for this location will come from that warehouse, and orders shipped from it will be marked shipped from this location."(이 위치의 재고는 그 창고에서 오고, 거기서 나간 오더는 이 위치에서 나간 것으로 표시된다)
3. **Unpair** 는 짝을 풉니다.

**어떻게 — 있는 제품 잇기(첫 보내기 전 한 번)**
1. **Link existing products** 에서 **Read products from Shopify** 를 누릅니다. "It only reads Shopify, nothing is changed there."(Shopify 를 읽기만 한다 — 거기서는 아무것도 바뀌지 않는다)
2. **Plan** 을 누릅니다. **Show lines** 는 Shopify 제품마다 결정을 보이고, **Download CSV** 는 전부를 받습니다.
3. **Apply links** 를 누릅니다. "Stock is sent right away."(재고는 바로 보낸다) 제품 정보는 아직 보내지 않습니다.

**어떻게 — 제품 정보 보내기**
1. **Push linked products** 에서 **Show what is left** 를 누릅니다. 브랜드마다 남은 제품 수가 나옵니다.
2. 브랜드 하나의 **Send…** 를 누릅니다. Shopify 에서 몇 개를 확인합니다.
3. 맞으면 **Send all left (n)…** 를 누릅니다.
- "Sending pushes IMS product details (title, description, price, photos, tags, variants) to Shopify."(IMS 제품 정보 — 제목 · 설명 · 가격 · 사진 · 태그 · 옵션 — 를 보낸다) 몇 분에 걸쳐 Shopify 에 닿습니다.

**알아 둘 것**
- 제품을 가게에 켜는 것은 제품의 Shopify 카드에서 합니다([설명 · 사진 · 태그 · 웹 숍](03-inventory.md#stock-descriptions)).

<!-- SCREENSHOT: set-shopify-1 · Location pairs 와 Push linked products 가 보이는 가게 -->

<a id="set-system-check"></a>
## System Check
<!-- screen: system-check.html · BUILD 2026-10-24 · sc v2 -->
<!-- who: all -->

**무엇인가**
**System Check**(**Settings ▾** › **System Check**)는 IMS 가 나를 어떻게 보는지 보여 줍니다. 누구나 엽니다.

**보이는 것**
- **Signed in as** — 내 이름 · 이메일 · 역할
- **Access** — 내 모드 · 권한(read · write) · 없는 권한 · 내 창고
- **Screens open to you** — 내가 열 수 있는 화면 모두(링크)
- **Google Drive** — 시작 날짜 · 켜짐/꺼짐 · 기다림 · 실패([Google Drive](#set-drive))
- **Database connection** — IMS 가 자료에 닿는지
- **Build** — 빌드 표시([build 표시](00-getting-started.md#start-build-tag))

**언제**
화면이나 단추가 없을 때, IMS 가 제대로 열리지 않을 때

**어떻게**
1. **System Check** 를 엽니다.
2. 페이지 전체를 캡처합니다.
3. 질문과 함께 보냅니다([도움 받기](00-getting-started.md#start-getting-help)).

<!-- rulings: 150, 151, 166, 231, 232, 283, 330, 331, 332, 343, 493, 518, 521, 526, 534, 538, 555, 563, 564, 636, 668, 687, 692, 707, 708, 709, 713, 714, 715, 719, 720, 721, 722, 723, 725, 732, 738 -->
