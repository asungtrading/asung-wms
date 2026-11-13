# 7. Settings(설정)

<!-- sections 1-11 written (manual-7a · 7b) · sections follow the work of admins and managers -->
<!-- out of this chapter: what each key opens -> chapter 0 Roles and keys · B-grade stock -> chapter 3 -->

<a id="set-start"></a>
## Settings 에 있는 것
<!-- screen: ims-auth.js · BUILD nav v19 ; settings.html · BUILD 2026-11-11 · set v18 ; system-check.html · BUILD 2026-10-24 · sc v2 -->
<!-- who: manager, admin -->

**무엇인가**
**Settings ▾** 에는 IMS 의 다른 곳이 쓰는 목록과 스위치가 있습니다: 직원 · 브랜드 · bin · 운송사 · 창고 · 딜 · 문서 양식 · 운임 견적 · QuickBooks 연결. 웹 가게는 **Integrations ▾** › **Shopify Stores** 에 있습니다. 대부분은 보기만 하고, 몇 사람만 바꿉니다.

**누가 무엇을 바꾸나**

| 화면 | 보려면 | 바꾸려면 |
|---|---|---|
| **Settings** — 목록(**Warehouse** 포함) | `master` 권한 | `master` 권한 write |
| **Settings** — Shipping quotes · Carrier pickups | `master` 권한 | `master` 권한 write |
| **Settings** — Backorder emails · Documents · Google Drive | `master` 권한 | 부분마다 다름 — 그 절을 본다 |
| **Settings** — QuickBooks | `master` 권한 | admin 만 |
| **Surcharge Groups** | `master` 권한 | admin 만 |
| **Staff** | `staff` 권한 | `staff` 권한 write · 나보다 낮은 역할의 사람만 |
| **Discount Rules** | `master` 권한 | `master` 권한 write |
| **Settings** — QuickBooks matching(Supplier invoice lines 포함) | `master` 권한과 QuickBooks 권한(`qbo`) | QuickBooks 권한 write |
| **Shopify Stores** | `shopify` 권한 | `shopify` 권한 write — 연결 확인 · 잇기 · 보내기 · 가게 더하기 · 고치기 · 짝 맞추기는 admin |
| **System Check** | 권한 없이 | — 보여 주기만 한다 |

권한 자체는 [역할과 권한](00-getting-started.md#start-roles-keys)을 봅니다.

**절**
- [직원](#set-staff)
- [목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스](#set-master)
- [운임 견적](#set-shipping-quotes) · [운송사 픽업](#set-carrier-pickups)
- [할인 규칙과 딜](#set-deals) · [쿠폰](#set-coupons)
- [Surcharge 그룹](#set-surcharge)
- [문서](#set-documents) · [백오더 메일](#set-mail) · [Google Drive](#set-drive)
- [Shopify 가게](#set-shopify)
- [QuickBooks — 연결](#set-qbo-connect) · [QuickBooks matching](#set-qbo-matching) · [QuickBooks matching — 공급처 인보이스 줄](#set-qbo-supplier-lines)
- [System Check](#set-system-check)

<a id="set-staff"></a>
## 직원(Staff)
<!-- screen: staff.html · BUILD 2026-10-29 · st v3c -->
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
   - 두 모드가 함께 쓰는 권한(예: `freight_booking`)은 WMS 아래에도 IMS 아래에도 보입니다. 같은 권한 하나입니다.
4. **Location** — 브랜치. 이 사람이 일하는 브랜치를 체크합니다. "None ticked = every warehouse."(체크가 없으면 모든 창고) manager · worker 에게만 효과가 있습니다. supervisor · admin 은 모든 브랜치에서 일합니다.
5. **Save** 를 누릅니다. **Revert** 는 바꾼 것을 버립니다.

**알아 둘 것**
- "There is no delete — inactive people keep their row."(지우기는 없다 — 비활성인 사람도 줄이 남는다) 로그인을 막으려면 **Active** 를 끕니다.
- **Access** 에서 모드 체크를 빼면 저장할 때 그 모드의 권한이 none 이 됩니다. 저장 전에 노란 글로 먼저 알립니다.
- `cost` 권한은 공급처 단가 · 가격 공식 · **↓ Export…** 의 원가 칸을 누가 보는지도 정합니다. 켜기 전에는 꺼져 있습니다. 그 사람은 화면을 새로 고친 뒤에 바뀐 것을 봅니다.
- 비밀번호를 잊은 경우 관리자가 따로 할 일은 없습니다. 그 사람이 로그인 화면에서 **Forgot your password?** 를 누릅니다([로그인](00-getting-started.md#start-sign-in)).

**조심할 것**
- 이메일이 로그인입니다. 보이기만 하고 바꾸지 않습니다.

<!-- SCREENSHOT: set-staff-1 · Role · Access · Location 이 보이는 Staff 의 한 사람 -->

<a id="set-master"></a>
## 목록: 브랜드 · 단위 · 결제 조건 · bin · 운송사 · 서비스
<!-- screen: settings.html · BUILD 2026-11-12 · set v18a ; ims-label.js · lbl v1b -->
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
| **Account** | 계정(코드로). **Currency** 는 "is set only on foreign-currency payable and receivable accounts — empty means CAD"(외화 미지급 · 미수 계정에만 있다 — 비면 CAD) | 보기만 |
| **Warehouse** | 브랜치 — "the shipping contact and Freightcom account are used for freight quotes"(출고 연락처와 Freightcom 계정을 운임 견적에 쓴다) | 출고 연락처 · Freightcom 계정 · 시간대 · 닫는 시각 고치기 |
| **Bin** | 브랜치마다 선반 자리 — "Thousands of bins — search for the one you need"(bin 이 수천 개 — 찾아서 쓴다) | 더하기 · 끄기 · 켜기 · B급 표시 · 라벨 인쇄 |
| **Carrier** | "Picked at Ship & invoice — the kind decides email and tracking"(Ship & invoice 에서 고른다 — 종류가 메일 · 송장을 정한다) | 더하기 · 고치기 |
| **Service** | "Billed on service orders as quantity × unit price — tax follows the order"(서비스 오더에 수량 × 단가로 · 세금은 오더를 따른다) | 더하기 · 고치기 |

Currency · Account 는 보기만 합니다. 창고는 여기서 더하지 않고, 창고 이름 · 주소도 여기서 바꾸지 않습니다 — **Edit** 는 주소를 보여 주기만 합니다: "The address is shown here only. Freightcom pickups use it — if a warehouse moves, tell an admin."(주소는 보이기만 · Freightcom 픽업이 쓴다 · 창고가 옮기면 관리자에게) 세금 규칙은 고객 · 오더에서 고르기만 하고 여기에 없습니다. 이것들을 바꿀 일이 생기면 IMS 관리자에게 말합니다.

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
  이 두 칸은 지금 공급처 인보이스(PO)에만 쓰입니다. 고객 인보이스에는 기한만 찍힙니다 — 고객 조기 결제 할인은 준비 중입니다.
- **Split** — "Paid in parts, e.g. 50% COD & 50% Net 30 — Net days is the later part"(나눠 낸다 — Net days 는 뒤의 몫)

**Unit**
"A set's unit is its pack number — a 12-pack set uses the unit 12."(세트의 단위는 팩 수 — 12 개들이 세트는 단위 12)

**Bin**
- **Warehouse** 를 고르고 **Name** 을 적습니다 — "use the spelling on the shelf label"(선반 라벨의 철자대로)
- **Staging** — "A staging spot (dock, receiving area), not a shelf"(선반이 아니라 도크 · 받는 자리)
- **Mark B-grade** 는 B급 bin 으로 만듭니다. "The bin must be empty in the books first."(먼저 장부에서 비어 있어야 한다) **Unmark B-grade** 는 보통 bin 으로 되돌립니다 — B급 재고를 먼저 옮깁니다([B급 재고](03-inventory.md#stock-bgrade)).
- **Print labels…** 는 bin 여러 개의 바코드 라벨을 한 번에 찍습니다([바코드 라벨 찍기](03-inventory.md#stock-labels)).

**Warehouse**
운임 견적 · 예약이 이 값을 씁니다. 창고 줄의 **Edit** 를 누릅니다(꺼진 창고에는 없음).
1. **Contact** · **Phone** · **Email** — "Sent to the carrier as the ship-from contact on freight quotes and bookings. A quote is refused without a 10-digit phone."(견적 · 예약 때 보내는 쪽 연락처로 운송사에 간다 · 10 자리 전화가 없으면 견적이 거부된다)
2. **Freightcom account** — 영문 · 숫자 2 ~ 10 자(예: TOR). "Quotes from this warehouse use the Freightcom account with this key. Empty = no Freightcom quotes from this warehouse."(이 창고의 견적은 이 이름의 Freightcom 계정으로 · 비면 이 창고에서 견적 없음) 바꾸기 전에 IMS 가 묻습니다.
3. **Time zone** — "Pickup times and carrier cutoffs at this warehouse are in this time zone."(이 창고의 픽업 시각 · 운송사 마감은 이 시간대로) Edmonton 은 **America/Regina** 를 씁니다. 바꾸기 전에 IMS 가 묻습니다.
4. **Closes at** — 창고 문 닫는 시각(24 시간). "A booking made after this moves the pickup to the next day, and a pickup window ends here."(이 뒤에 한 예약은 픽업이 다음 날로 · 픽업 시간대는 여기서 끝난다)
5. **Save** 를 누릅니다.
- 주소는 보이기만 하고 여기서 고치지 않습니다.

**Carrier**
1. **+ Add carrier** 를 누르거나, 줄의 **Edit** 를 누릅니다.
2. **Kind**: **Carrier — tracking number · shipping email**(운송사 — 송장 번호 · 출고 메일) · **Pickup — customer collects**(고객이 가져감) · **Delivery — our truck**(우리 트럭). "The kind cannot change — it decides what old orders did."(종류는 바꿀 수 없다 — 지난 오더가 그것으로 처리됐다)
3. 운송사면: **Shopify name**("exactly as in Shopify's carrier list" — Shopify 운송사 목록과 똑같이) · **Tracking link**("{number} is replaced by each tracking number" — {number} 자리에 송장 번호가 들어간다)
4. 운송사면: **Freightcom names** — "The carrier name as Freightcom sends it in quotes — one carrier can have several (case and spaces do not matter). A quote from a carrier with no name here cannot be picked. Each name belongs to one carrier only."(Freightcom 이 견적에 보내는 운송사 이름 · 한 운송사에 여럿 가능 · 대소문자 · 빈칸 무관 · 여기 이름이 없는 운송사의 견적은 고를 수 없다 · 이름 하나는 운송사 하나에만) 한 줄에 하나씩 적거나, 아래 칸에 이름 일부를 치고 **Add** 를 누릅니다.
5. **Active** 를 끄면 "not offered at Ship & invoice (old orders keep the name)"(Ship & invoice 에 나오지 않는다 · 지난 오더는 이름을 그대로 가진다). **Save** 를 누릅니다.

**Service**
1. **+ Add service** 를 누르거나, 줄의 **Edit** 를 누릅니다.
2. **Name** — "customers see this name on the invoice"(고객이 인보이스에서 보는 이름). 나중에 바꿀 수 없습니다.
3. **Unit price** — "Filled in when the service is picked on an order; staff can change it on the line."(오더에서 고르면 채워진다 — 라인에서 바꿀 수 있다) **Sales account** — 매출이 들어가는 계정
4. **Save** 를 누릅니다.

<!-- SCREENSHOT: set-master-1 · 왼쪽 목록과 Payment Term 이 열린 Settings -->

<a id="set-shipping-quotes"></a>
## 운임 견적(Shipping quotes)
<!-- screen: settings.html · BUILD 2026-11-11 · set v18 -->
<!-- who: manager, admin -->

**무엇인가**
**Settings** › **Shipping quotes** 는 Freightcom 운임 견적의 두 가지를 정합니다: 손님에게 붙이는 마크업, 그리고 어느 창고가 견적을 낼 수 있나. 견적 · 예약 자체는 [Freightcom — 견적 · 예약 · 라벨](04-wms.md#wms-freightcom)에 있습니다.

**누가**
**Settings** 를 여는 사람은 모두 봅니다. 마크업은 `master` 권한 write 가 바꿉니다. 아니면 "Only staff with master rights can change this."(master 쓰기 권한만 바꾼다)

**손님 마크업(Customer markup)**
- "The freight line on the invoice = the Freightcom price before tax × (1 + this %), rounded to the cent. The customer's tax is added once on top."(인보이스 운임 줄 = 세전 Freightcom 가격 × (1 + 이 %) · 센트로 반올림 · 손님 세금은 그 위에 한 번)
- 바꾸려면 % 를 적고(0 ~ 100 · 소수 둘째 자리까지) **Save** 를 누릅니다. IMS 가 먼저 묻습니다: "New quotes use it. Quotes already made keep their numbers."(새 견적부터 · 이미 낸 견적은 그대로)
- "Web orders already paid at checkout keep the freight the customer paid."(결제 때 운임을 이미 낸 웹 오더는 그 운임 그대로)

**창고(Warehouses)**
켜진 창고마다 Freightcom 계정과 상태가 보입니다:
- **connected** — 이 창고에서 견적을 낼 수 있습니다.
- **no key on the server yet** — 그 계정의 열쇠가 서버에 아직 없습니다. IMS 관리자에게 말합니다.
- **no Freightcom account** — 이 창고에서는 견적이 없습니다.
- **no phone — quotes are refused** — 전화가 없어 견적이 거부됩니다.
- **status not available to you** — 내 권한으로는 연결 상태를 못 읽습니다.

계정 · 전화 · 연락처는 **Warehouse** 에서 적습니다([목록](#set-master)).

**알아 둘 것**
- "Freightcom TEST environment — prices are not real."(Freightcom 시험 환경 — 가격이 진짜가 아니다)는 IMS 가 Freightcom 시험 쪽에 이어져 있을 때 보입니다.

<a id="set-carrier-pickups"></a>
## 운송사 픽업(Carrier pickups)
<!-- screen: settings.html · BUILD 2026-11-11 · set v18 -->
<!-- who: manager, admin -->

**무엇인가**
**Settings** › **Carrier pickups** 는 창고마다 "which carriers come on a regular run, and the cutoff for a same-day pickup"(어느 운송사가 정기로 오나 · 당일 픽업 마감은 몇 시인가)을 적어 둡니다. 운임 예약이 이것을 씁니다.

**누가**
**Settings** 를 여는 사람은 모두 봅니다. `master` 권한 write 가 바꿉니다. "Ask the warehouse lead for these."(값은 창고 책임자에게 묻는다)

**보이는 것**
켜진 창고마다 표 하나 — 그 창고의 시간대와 닫는 시각("closes …", 없으면 **not set**). **Change under Warehouse** 는 창고 목록을 엽니다. 운송사 하나가 한 줄입니다.
- **Regular pickup** — "the carrier already comes to this warehouse on its usual run, so a box booking just joins that run (no pickup time is sent). Not ticked — each booking asks the carrier to come, from the ready time until the warehouse closes. Pallets always ask for a pickup."(운송사가 원래 정기로 오므로 박스 예약은 그 길에 붙는다 · 픽업 시각을 보내지 않음 · 체크 안 함 = 예약마다 준비 시각부터 문 닫을 때까지 와 달라고 한다 · 팔렛은 늘 픽업을 부른다)
- **Cutoff** — "after this time (warehouse time) a booking made today is picked up the next day, and the carrier shows as "past cutoff" in the quotes. Empty = no cutoff known. When Freightcom sends the carrier's real cutoff, that comes first."(창고 시각으로 이 뒤에 한 오늘 예약은 다음 날 픽업 · 견적에 "past cutoff" 로 보인다 · 비면 마감 모름 · Freightcom 이 진짜 마감을 주면 그것이 먼저)
- **Note** — 예: "driver around 3 pm". **Updated** 에 마지막으로 바꾼 사람 · 날짜가 보입니다.

**어떻게**
1. **regular pickup** 을 체크하고, **Cutoff**(16:30 같은 시각)와 **Note** 를 적습니다.
2. 그 줄의 **Save** 를 누릅니다.
3. **Clear** 는 그 줄을 **not set** 으로 되돌립니다 — "no regular pickup, no cutoff"(정기 픽업 없음 · 마감 없음). IMS 가 먼저 묻습니다.

**알아 둘 것**
- "A carrier left as "not set" has no regular pickup and no cutoff."(not set 인 운송사는 정기 픽업도 마감도 없다)
- 마감이 창고 닫는 시각보다 늦으면 빨간 "after closing" 이 보입니다. 마감을 고치거나 **Warehouse** 에서 닫는 시각을 고칩니다.
- 종류가 **Carrier** 인 켜진 운송사만 나옵니다. **Carrier** 에서 더합니다([목록](#set-master)).

<!-- SCREENSHOT: set-carrier-pickups-1 · 운송사 · Regular pickup · Cutoff · Note 가 보이는 창고 하나 -->

<a id="set-deals"></a>
## 할인 규칙과 딜
<!-- screen: discount-rules.html · BUILD dr v4 ; ims-export.js · export v2 -->
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
- 딜의 **Products** 목록에서 세트는 접혀 있습니다. **▸ sets** 를 누르면 보입니다: "Sets get the same deal as their single (a set line counts its singles)"(세트는 낱개와 같은 딜을 받는다 · 세트 줄은 낱개로 센다)

**딜 내보내기**
- 넓은 목록의 **↓ Export rules…** 는 "one row for each discount line of the deals on this list now"(지금 목록에 있는 딜의 할인 줄마다 한 줄), **↓ Export products…** 는 "one row for each active product the deals on this list reach today"(그 딜이 오늘 닿는 켜진 제품마다 한 줄)입니다. 둘 다 지금 걸어 둔 거르기를 따릅니다.
- 딜 하나에서 **↓ Rule CSV…** 는 그 딜을 적힌 그대로, **↓ Products CSV…** 는 오늘 닿는 켜진 제품 전부를 받습니다(라인 할인만).
- 칸은 [↓ Export…](00-getting-started.md#start-search-filter)처럼 고릅니다.

**조심할 것**
- 내가 연 뒤에 다른 사람이 저장했으면 아무것도 저장되지 않습니다. **Load the latest version** 을 누르고 다시 바꿉니다.

<!-- SCREENSHOT: set-deals-1 · Lines · Minimum · Applies to 가 보이는 라인 할인 Edit -->

<a id="set-coupons"></a>
## 쿠폰
<!-- screen: discount-rules.html · BUILD dr v4 -->
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
<!-- screen: settings.html · BUILD 2026-11-12 · set v18a ; ims-doc.js -->
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
<!-- screen: settings.html · BUILD 2026-11-11 · set v18 -->
<!-- who: admin -->

**무엇인가**
**Settings** › **Backorder emails** 는 백오더 물건이 들어왔다고 고객에게 알리는 메일을 다룹니다.

**누가**
칸마다 누가 바꿀 수 있는지 보입니다: "Only an admin can change this." 또는 "Only a manager with the master permission can change this." 칸마다 마지막으로 바꾼 사람도 보입니다.

**어떻게**
1. **Emails** — **Turn on** · **Turn off**. 켜짐: "Runs start on the scheduled mornings and emails go out."(정한 아침마다 돌고 메일이 나간다) 꺼짐: "Emails that are already waiting stay waiting until this is on."(기다리는 메일은 켤 때까지 기다린다)
2. **Customer mail is live** — **Live**: "This database sends real customer mail."(실제 고객에게 메일을 보낸다) **Not live**: "every email must go to the Test mode address below (an @asung.ca address)."(모든 메일이 아래 Test mode 주소로 가야 한다 · @asung.ca 주소) **Make live** · **Make not live** 로 바꿉니다.
3. **Test mode — send every email to** — "every email — invoices, credit notes, orders and backorder emails — goes to it instead of the customer, and the customer's address goes in the subject."(인보이스 · 크레딧 노트 · 오더 · 백오더 메일 모두 고객 대신 이 주소로 · 고객 주소는 제목에) 실제 고객에게 보내려면 비웁니다. "It can be empty only while customer mail is live."(Customer mail 이 Live 일 때만 비울 수 있다)
4. **Sent from** — 고객이 보는 보낸 주소. 회사 메일함에 "Send mail as" 주소로 설정돼 있어야 합니다.
5. **Sender name** · **Replies go to**("Empty = replies go to the "sent from" address" — 비면 답장은 보낸 주소로)
6. **Schedule** — 브랜치마다 **Send for this branch** 와 요일 · 시각 · 시간대를 고르고 **Save schedule** 을 누릅니다.
7. **Part of a line that came in** — 백오더 수량의 몇 % 가 들어와야 메일을 보낼지. **Save** 를 누릅니다.

**알아 둘 것**
- "Each branch runs once on each checked morning at that hour in its own time."(브랜치마다 고른 아침, 그 시각에 한 번) "Holidays are not skipped."(공휴일도 건너뛰지 않는다)
- 구매 입고나 다른 브랜치에서 온 트랜스퍼는 % 에 셉니다. "Stock from returns, adjustments or counts is emailed only when the whole line can ship. Each line is emailed once."(반품 · 조정 · 실사로 생긴 재고는 라인 전체가 나갈 수 있을 때만 · 라인마다 한 번)

<a id="set-drive"></a>
## Google Drive
<!-- screen: settings.html · BUILD 2026-11-12 · set v18a -->
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
<!-- screen: shopify-stores.html · BUILD 2026-11-12 · ss v5b -->
<!-- who: admin, manager -->

**무엇인가**
**Shopify Stores**(**Integrations ▾** › **Shopify Stores**)는 IMS 를 웹 가게마다 잇습니다: 어느 가격을 보이나, 어느 창고가 재고를 보내나, 어느 제품이 이어져 있나.

**누가**
- `shopify` 권한 read: 보기만
- `shopify` 권한 write: **Check connection**, 제품 잇기와 보내기
- admin: **New store** · **Edit** · **Turn off** / **Turn on** · **Go live…** / **Stop live…** · 위치 짝 맞추기

**Live — admin 만**
웹 가게는 이미 Live 로 돌고 있습니다. IMS 관리자가 말하지 않으면 **Stop live…** · **Go live…** 를 누르지 마세요.
- **Live**: "IMS sends products and stock, takes orders and updates them in Shopify."(IMS 가 제품 · 재고를 보내고, 오더를 받고, Shopify 에서 오더를 갱신한다)
- **Not live**: "IMS only reads this store (Check connection · Link existing products) — nothing is written to Shopify and no orders are taken"(IMS 는 읽기만 · Shopify 에 아무것도 쓰지 않고 오더도 받지 않는다). 새 가게는 Not live 로 시작합니다.
- **Stop live…**: "IMS stops writing to this store and stops taking its orders. Waiting product updates stay in the queue and go out when it is live again."(쓰기와 오더 받기를 멈춘다 · 기다리던 제품 갱신은 줄에 남았다가 다시 Live 가 되면 나간다) Shopify 자체는 바뀌지 않습니다.
- **Go live…**: "From now on IMS writes to the real store: it sends stock for every product with send on (right away, as IMS has it now), sends product changes, takes new web orders and updates them in Shopify."(지금부터 실제 가게에 쓴다 — 보내기가 켜진 제품의 재고를 지금 IMS 값으로 바로 보내고, 제품 변경을 보내고, 새 웹 오더를 받고 갱신한다) **Read orders from** — 오더를 받기 시작할 날짜 · 시각을 토론토 시각으로 묻습니다. "Web orders placed before this time are not brought into IMS — handle any of those by hand in Shopify."(이 시각 전에 들어온 웹 오더는 IMS 로 오지 않는다 — Shopify 에서 손으로 처리) "Before going live: IMS stock is loaded and right · locations are paired (Check connection shows no warnings) · products are linked."(먼저: IMS 재고가 맞다 · 위치 짝이 있다 · 제품이 이어져 있다)
- 둘 다 **Check** 를 먼저 누르고, 그다음 **Stop live** 또는 **Go live** 를 누릅니다.
- **Turn off** 는 그 가게와 주고받기를 모두 멈추고 Live 도 끕니다. **Turn on** 뒤에도 **Go live…** 를 누르기 전까지 Not live 입니다.

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
3. **Apply links** 를 누릅니다. Live 가게면 "Stock is sent right away"(재고는 바로 보낸다), Not live 가게면 재고는 **Go live…** 때 한 번에 나갑니다. 제품 정보는 아직 보내지 않습니다.
   - "It goes 500 at a time … Keep this window open. If it stops, press Apply links again and it carries on from where it stopped."(500 개씩 간다 · 창을 열어 둔다 · 멈추면 Apply links 를 다시 누르면 멈춘 곳부터 잇는다) **Stop** 은 지금 묶음을 마치고 멈춥니다.
   - 막힌 줄은 까닭이 보입니다. 예: "several Shopify products point to one IMS item — make them one product in Shopify, then read again"(Shopify 제품 여럿이 IMS 하나를 가리킨다 — Shopify 에서 하나로 합치고 다시 읽는다). **Show lines** 에 겹치는 다른 Shopify 제품이 나오고, CSV 에도 있습니다.

**어떻게 — 제품 정보 보내기**
1. **Push linked products** 에서 **Show what is left** 를 누릅니다. 브랜드마다 남은 제품 수가 나옵니다.
2. 브랜드 하나의 **Send…** 를 누릅니다. Shopify 에서 몇 개를 확인합니다.
3. 맞으면 **Send all left (n)…** 를 누릅니다. Not live 가게에서는 **Send…** 가 흐립니다 — "sending starts only after Go live"(보내기는 Go live 뒤부터).
- "Sending pushes IMS product details (title, description, price, photos, tags, variants) to Shopify."(IMS 제품 정보 — 제목 · 설명 · 가격 · 사진 · 태그 · 옵션 — 를 보낸다) 몇 분에 걸쳐 Shopify 에 닿습니다.

**알아 둘 것**
- 제품을 가게에 켜는 것은 제품의 Shopify 카드에서 합니다([설명 · 사진 · 태그 · 웹 숍](03-inventory.md#stock-descriptions)).

<!-- SCREENSHOT: set-shopify-1 · Location pairs 와 Push linked products 가 보이는 가게 -->

<a id="set-qbo-connect"></a>
## QuickBooks — 연결
<!-- screen: settings.html · BUILD 2026-11-11 · set v18 -->
<!-- who: admin, accounting -->

**관리자 · 회계 담당용.** 대부분의 직원은 이 페이지를 쓸 일이 없습니다.

**무엇인가**
**Settings** › **QuickBooks** 는 IMS 와 QuickBooks Online 회사의 연결입니다. **Connected** 로 보이는 동안 IMS 가 인보이스 · 크레딧 노트 · 입금 · 크레딧 붙임 · 환불을 QuickBooks 로 보냅니다([QuickBooks](01-sales.md#sales-quickbooks)).

**누가**
**Settings** 를 여는 사람은 모두 상태를 봅니다. 연결 · 다시 연결 · 확인 · 끊기는 admin 만 합니다: "Only an IMS admin can connect or disconnect."(IMS admin 만 연결 · 끊기를 한다)

**메일이 왔을 때 — "[IMS] QuickBooks connection needs attention"**
QuickBooks 가 연결을 받지 않게 되면 IMS 가 IMS 관리자에게 메일을 한 번 보냅니다: "QuickBooks stopped accepting the IMS connection … Nothing is sent to QuickBooks until it is reconnected."(QuickBooks 가 연결을 받지 않는다 · 다시 연결할 때까지 아무것도 보내지 않는다) 페이지에는 **Reconnect needed** 와 **Last problem** 이 보입니다.
1. admin 이 **Settings** › **QuickBooks** 를 열고 **Reconnect** 를 누릅니다.
2. QuickBooks 회사의 관리자로 로그인하고 허락합니다. 이 페이지로 돌아옵니다.
3. "Just now: Connected to QuickBooks." 가 뜨고 상태가 **Connected** 가 됩니다.
다른 글이 뜨면 — 예: "The connect link expired or was already used. Press Connect again."(링크가 만료됐거나 이미 썼다 · Connect 를 다시 누른다) — 그 글대로 합니다.

**페이지에 보이는 것**
- **Company** — QuickBooks 회사 이름 · ID · **Production** 또는 **Sandbox (test company)**(시험 회사)
- **Connected by** — 누가 언제 연결했나
- **Approval good until** — "Each daily renewal moves it about 100 days ahead, so nothing needs doing while renewals work — press Reconnect only if the connection drops."(매일 갱신할 때마다 약 100 일 뒤로 밀린다 · 갱신이 도는 동안 할 일 없음 · 연결이 끊겼을 때만 Reconnect)
- **Check connection**(admin)은 지금 QuickBooks 에 물어봅니다: "QuickBooks answered — …"

**끊기(Disconnect) — 보내기가 모두 멈춘다**
**Disconnect** 는 IMS 를 QuickBooks 회사에서 로그아웃시킵니다. "Nothing can be sent to the books until someone connects again."(누가 다시 연결할 때까지 장부로 아무것도 못 보낸다) 문제를 고치려고 누르지 마세요 — **Reconnect** 를 씁니다.

**조심할 것**
- "The IMS stays tied to the first QuickBooks company it connects to, so records never point at the wrong books."(IMS 는 처음 연결한 QuickBooks 회사에 묶인다 — 기록이 다른 장부를 가리키지 않게) 다른 회사로 연결하면 거부됩니다: "That is a different QuickBooks company from the one this IMS is tied to. Nothing was saved." **Untie company** 는 회사 자체가 정말 바뀌었을 때만 씁니다.

<a id="set-qbo-matching"></a>
## QuickBooks matching(짝짓기)
<!-- screen: settings.html · BUILD 2026-11-11 · set v18 -->
<!-- who: accounting, admin -->

**관리자 · 회계 담당용.**

**무엇인가**
**Settings** › **QuickBooks matching** 은 "each IMS record that will later go to QuickBooks … to one QuickBooks record — automatically by account number, name or SKU, or by hand. Once tied, the tie holds even if a name changes later. Nothing is sent to QuickBooks from this page."(나중에 QuickBooks 로 갈 IMS 기록을 QuickBooks 기록 하나에 묶는다 — 계정 번호 · 이름 · SKU 로 자동으로, 또는 손으로 · 한 번 묶이면 이름이 바뀌어도 그대로 · 이 페이지에서는 QuickBooks 로 아무것도 보내지 않는다)

**누가**
- QuickBooks 권한(`qbo`)이 있어야 합니다: "This page needs the QuickBooks key. Ask an admin to switch it on for you in Staff."
- read 는 보기만, write 는 **Refresh list** · **Match automatically** · **Find…** · **Change…** · **Unlink** 를 합니다.
- QuickBooks 가 먼저 연결돼 있어야 합니다([QuickBooks — 연결](#set-qbo-connect)).

**무엇을 짝짓나**
종류마다 한 줄 — **IMS active** · **Matched** · **Not matched** · **In QuickBooks** · **List from QuickBooks**(마지막으로 읽은 때):

| Records | QuickBooks 쪽 | 어떻게 |
|---|---|---|
| **Accounts** | Account | 계정 번호로 |
| **Tax rules** | TaxCode | 이름으로 — 판매 · 구매 규칙이 QuickBooks 세금 코드 하나를 함께 쓴다 |
| **Payment terms** | Term | 이름으로 |
| **Payment methods** | PaymentMethod | 정해진 목록 — 카드 결제는 QuickBooks 방법 하나로, **Find…** 로 고른다 |
| **Customers** | Customer | 이름으로 |
| **Suppliers** | Vendor | 이름으로 |
| **Products** | Item | SKU 로 |
| **Freight, discount & account lines** | Item | 손으로 — Freight · Order discount · Surcharge · Freight discount · 계정 줄 |
| **Services** | Item | 손으로 |

**어떻게 — 새 기록 짝짓기**
1. 그 줄의 **Refresh list** 로 QuickBooks 의 최신 목록을 읽습니다.
2. **Match automatically** 를 누릅니다. "… matched now · … with no QuickBooks record · … need a choice"(지금 짝지음 · QuickBooks 에 없음 · 골라야 함)
3. **Review** 를 누릅니다. **To match** 에 남은 것이 나옵니다. 맞는 QuickBooks 기록 단추를 누르거나, **Find…** 로 이름 · SKU · ID 로 찾아 **Match** 를 누릅니다.
- **Matched** · **All** 은 나머지를 보입니다. **Change…** 는 다른 기록으로 바꾸고, **Unlink** 는 짝을 풉니다 — "Nothing changes in QuickBooks."(QuickBooks 는 바뀌지 않는다)
- "A record already tied to another IMS record cannot be picked until that one is unlinked."(다른 IMS 기록에 묶인 것은 그쪽을 풀기 전에는 못 고른다)

**보내기가 "… has no QuickBooks item" 으로 멈추면**
**Integrations ▾** › **QuickBooks** 에서 보내기가 실패합니다. 예: "IMS freight has no QuickBooks item — link "freight" to the Freight item under Settings → QuickBooks matching — nothing was sent"
1. **Settings** › **QuickBooks matching** 을 열고 **Freight, discount & account lines**(또는 **Services**)의 **Review** 를 누릅니다.
2. 메시지가 말한 줄을 찾아 **Find…** 를 누르고, QuickBooks 품목을 골라 **Match** 를 누릅니다.
3. **Integrations ▾** › **QuickBooks** 로 돌아가 실패한 줄의 **Retry** 를 누릅니다([QuickBooks](01-sales.md#sales-quickbooks)).
- 계정 줄은 `acct:` 뒤에 계정 코드로 보입니다 — 메시지와 같은 글입니다. 그 계정이 한 번 쓰인 뒤에야 목록에 나타납니다 — 판매 오더의 charge 줄, 크레딧 노트의 other · restocking fee 줄, 또는 IMS 이전부터 이월된 미리 받은 돈. 그 전에는 짝지을 것이 없습니다.

**알아 둘 것**
- **Products**: "To match" 에는 같은 SKU 의 QuickBooks 품목이 있는 제품만 나옵니다. 나머지는 "were never sold, so QuickBooks does not have them yet. The IMS will create them when they are first sent. Nothing to do for those."(팔린 적이 없어 QuickBooks 에 아직 없다 · 처음 보낼 때 IMS 가 만든다 · 할 일 없음) **Show them anyway** 로 볼 수 있습니다.
- "Card payments go to QuickBooks under one method — Visa, Mastercard and Amex are not told apart."(카드 결제는 QuickBooks 에 방법 하나로 간다 — Visa · Mastercard · Amex 를 가르지 않는다)

<!-- SCREENSHOT: set-qbo-matching-1 · Refresh list · Match automatically · Review 가 있는 종류 표 -->

<a id="set-qbo-supplier-lines"></a>
## QuickBooks matching — 공급처 인보이스 줄
<!-- screen: settings.html · BUILD 2026-11-11 · set v18 -->
<!-- who: accounting, admin -->

**무엇인가**
**Settings** › **QuickBooks matching** › **Supplier invoice lines** 는 IMS 가 공급처 인보이스를 Bill 로 보낼 때 **상품이 아닌 줄**이 갈 QuickBooks 계정을 정합니다. 둘입니다:
- **Charge lines** — 공급처가 자기 인보이스에 넣은 운임 · 취급비. 바로 비용으로 잡히고 상품 원가는 바꾸지 않습니다. 운송사 · 통관 청구서는 그대로 **Purchasing → Charges** 에서.
- **Other lines** — 상품도 charge 도 아닌 공급처 인보이스 줄.

둘 다 처음 값은 **_95_ Purchase Non Stock - COS** 입니다. 상품 줄은 늘 Goods invoiced not received 로 갑니다.

**누가**
- QuickBooks 권한(`qbo`) read: 보기만("Only staff with the QuickBooks (write) key can change these.")
- QuickBooks 권한 write: 바꾸고 **Save**

**어떻게**
1. **Settings** › **QuickBooks matching** 을 열고 **Supplier invoice lines** 를 찾습니다.
2. **Charge lines** 또는 **Other lines** 의 계정을 고르고 **Save** 를 누릅니다. "Saved — charge lines now go to …"(이제 그 계정으로 간다). 줄 아래에 마지막으로 바꾼 사람 · 때가 보입니다(없으면 "Not changed yet").

**알아 둘 것**
- 목록에는 켜져 있고 QuickBooks 에 짝지은 매출원가 · 비용 계정만 나옵니다. 이미 골라 둔 계정이 조건에서 벗어나면 "(current · not allowed)" 로 보입니다.
- 이 줄의 세금은 줄과 함께 보내므로 평소처럼 돌려받습니다.
- **not payable** 로 표시한 줄은 Bill 에서 빠집니다 — QuickBooks 의 미지급이 IMS 와 같아집니다([공급처 인보이스 넣기](02-purchasing.md#purch-invoice)).
- 바꾼 값은 그 뒤에 보내는 Bill 부터입니다. 이미 보낸 Bill 은 다시 보내지 않습니다.

<a id="set-system-check"></a>
## System Check
<!-- screen: system-check.html · BUILD 2026-10-26 · sc v2a -->
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

<!-- rulings: 150, 151, 166, 231, 232, 283, 330, 331, 332, 343, 493, 518, 521, 526, 534, 538, 555, 563, 564, 636, 668, 687, 692, 707, 708, 709, 713, 714, 715, 719, 720, 721, 722, 723, 725, 732, 738, 764, 777, 790, 791, 792, 811, 814, 815, 816, 830, 836, 847, 848, 852, 857, 859, 867, 868, 869, 870, 871, 872, 934, 945, 951, 961, 983, 1136 -->
