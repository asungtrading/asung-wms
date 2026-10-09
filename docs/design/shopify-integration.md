# Shopify 연동 — 설계 정본

작성: 2026-10-08 · 회사 PC · 판정 362 ~ 381(원문 표는 `so-module.md` §53-a) · Caleb 이 판정 81 의 순서를 바꿔 1단계가 끝나기 전에 2단계 Shopify 연동 설계를 시작했다(「샤피파이와 ims를 인테그레이션 해서 … 먼저 만들어 놓고 싶어」 · `ims-principles.md` §6-c)
⚠️ 말하는 틀 — IMS 는 Cin7 없이 돈다(ims-principles 원칙 1). 이 설계의 주어는 IMS 와 Shopify 둘뿐이다. Cin7 은 「지금까지 상품을 Shopify 로 보내던 것」의 참고일 뿐이다(Caleb 「지금 설계에는 cin7을 개입시키지 말아줘」).
⚠️ 상태: **설계만** — 마이그레이션 · EF · 화면 없음. 만들기 순서는 매입 세금 → 할인 원가 → 상품 설명 칸 → Shopify(판정 381).

---

## 1. 스토어 (판정 362)

```
시험     시험 스토어 하나를 새로 만들어 시험한다 — Caleb 「시험 스토어는 하나로 충분해」
컷오버   실제 스토어 둘을 붙인다 — asung.ca(도매) · aonebeauty.com(매장 픽업 · 카드 결제)
설정     스토어는 IMS 안의 「설정 한 줄」 — 주소 · 열쇠 · 판매 티어 / 비교 티어 짝 · 브랜치 규칙(§4)
```

## 2. 오더 들어오기

### 2-a. 받는 길 (판정 363)
- 웹훅 + 주기적 확인을 함께 쓴다(웹훅이 빠져도 확인이 줍는다) · Shopify 오더 번호로 두 번 들어가지 않게 한다

### 2-b. 손님 찾기 4단계 (판정 364)
```
① Shopify 계정 번호로 이어진 손님 → 그 손님
② 이메일이 IMS 손님 하나에만 있다 → 그 손님 · 이때 계정 번호를 이어 둔다
③ 이메일이 여럿에 있다 → 「확인 필요」로 멈추고 직원이 고른다 · 고르면 이어 둔다
④ 없다 → 새 손님(스토어 티어) · 이어 둔다
```
- 근거 실측(테스트 DB · Caleb 2026-10-08): 활성 연락처 이메일 9,414 중 66 개가 손님 237 명에 겹친다 · 최대 18(herabeauty) · clorebeauty 14 · bswcanada 13 · bci 6 — 체인의 회계 · 구매 이메일
- Caleb 「체인매장도 각각의 스토어 어카운트를 지녀」 — 그래서 ① 이 첫째다

### 2-c. 브랜치 (판정 365)
```
asung.ca          손님의 기본 브랜치 · 비었으면 주소로 — AB · BC · SK → Edmonton · 나머지 → Toronto
aonebeauty.com    늘 Toronto
재고로 고르지 않는다   Caleb 「인벤토리로 하게 되면 오더도 갈라지고 복잡한게 너무 많아서」
다른 브랜치 요청   IMS 의 확정 되돌리기(supervisor) → 창고 변경 → 다시 확정 — ⬜ 이 장면은 끝에서 끝 시험을 아직 안 했다
```

### 2-d. 상품 (판정 366)
- SKU 글자 그대로 찾는다(Shopify SKU = 우리 SKU) · Shopify 에서 상품을 만들지 않는다 · 웹 세트 판매는 하나뿐
- 못 찾은 줄(없음 · 꺼짐 · 판매 안 함)이 있으면 자동 확정하지 않고 **초안 + 확인 필요**

### 2-e. 가격 (판정 367)
- Shopify 금액을 쓰되 정가 · 할인을 갈라 담는다 · IMS 계산과 다르면 경고
- Shopify 가격 · 손님 기본 할인 · 딜은 앱 「Wholesale All In One」 이 웹에 같은 규칙으로 건다(Caleb) · ⬜ 앱이 할인을 오더 데이터에 남기는 모양은 시험 스토어에서 확인

### 2-f. 세금 (판정 368)
- IMS 가 계산한다(줄마다 · so-module §16) · Shopify 세금과 다르면 경고 · Caleb 「샤피파이도 줄마다 계산해」

### 2-g. 운임 (판정 369)
```
asung.ca          운임 없이 내려온다 · 출고 때 IMS 에서 넣는다
aonebeauty.com    손님이 낸 배송비를 확정 값으로 — Ship & invoice 가 고치지 않는다
무료 배송          「운임 + 운임 할인 100%」로 담는다(so-module §52 운임 할인)
                  ⚠️ 그러려면 Shopify 의 「$50 이상 Free」 배송 요금 줄을 「무료 배송 자동 할인」으로 바꿔야 한다 — 지금은 요금 조건 방식이라 원래 운임이 데이터에 없다
                  Caleb 「다로 하자」 · Shopify 에서 고치는 법은 대화 Claude 가 단계별로 알려 준다(앱 할인과 겹침 확인 포함 · so-module 미룬 148)
```

### 2-h. 결제 (판정 370)
- AONE 카드 결제는 「이미 받은 돈」으로 읽는다 · Shopify 가 수수료를 떼고 묶어 입금한 것을 맞추는 일은 회계(QBO 때) · 환불도 읽는다

### 2-i. 상태 (판정 371)
- 깨끗하면 저절로 확정 · 재고 없는 줄은 확정이 백오더로 저절로 갈라낸다(되돌리고 나누고 다시 확정할 일이 없다)

### 2-j. Shopify 에서 취소 (판정 372)
- Release 전이고 IMS 에서 손대지 않았으면 IMS 도 저절로 취소 · 아니면 Action Center 알림
- 웹 오더는 원칙상 고치지 않는다 — Caleb 「오더 변경은 원칙적으로 불가 · 캔슬하고 다시 넣거나 추가오더」

---

## 3. 나가는 쪽 — 상품 · 재고

### 3-a. 칸의 주인 (판정 373)
```
IMS           제목 · 설명 · 사진(변형별 사진 지정) · Vendor · Type · 태그 · SKU · 바코드 · 무게 · 가격 · 비교가 · 위치별 재고 · Active/Draft · 품절 판매 · 변형 구조
Shopify(사람)  Collections · 메타필드 · SEO · Shopify Category · Theme · 판매 채널 퍼블리시
```
- Caleb 「샤피파이에서 직접 고치는 것은 거의 없어」

### 3-b. 상품 모양 · 사진 (판정 374)
- Shopify 상품 하나 = IMS family 하나(옵션 · 변형)
- family 에 「웹 대표 사진」 칸 — 고르지 않으면 첫 변형의 대표 사진
- 변형마다 그 변형의 대표 사진을 지정해 올린다(지금은 변형 사진이 비어 손으로 지정 중)

### 3-c. 보냄 · 퍼블리시 (판정 375)
- 상품마다 스토어별 「이 스토어로 보냄」 표시를 직원이 켠다
- **퍼블리시(웹에 보이기)는 Shopify 에서 사람이** — Caleb 정정 「listed, unlisted는 … 샤피파이로 제품을 보냈냐 안보냈냐 아닌가?」(보냄 ≠ 보임)

### 3-d. 재고 올리기 (판정 376)
- 바뀐 SKU 는 즉시 + 하루 몇 번 전체 맞추기 · 위치별(Shopify 위치 Edmonton · Toronto)
- Shopify 의 **Available** 에 맞춘다 — On hand 로 올리면 웹 오더가 두 번 빠진다 · ⬜ 시험 스토어에서 숫자 대조

### 3-e. 상품 정보 올리기 (판정 377)
- 바뀌면 즉시 + 새벽 전체 맞추기 · IMS 가 주인인 칸은 새벽에 IMS 값으로 되돌아간다

### 3-f. 상품 설명 (판정 381 · 401 · 402)
- IMS 자기 설명 칸(상품 · family) · 서식 편집기(굵게 · 제목 · 목록 · 링크 · 위험한 태그는 거른다)
- ~~처음 내용은 IMS 안의 cin7_description 에서 한 번 · 재적재도 이 칸을 채운다 · 그 뒤 IMS 가 주인~~ → [2026-10-09 · 판정 401 · desc-1b 9184853] **복사하지 않는다** — 값 = `coalesce(description_html, cin7_description)` · description_html null = Cin7 원문을 따른다(재적재가 바꾸면 저절로 따라감) · IMS 에서 한 번 고치면 IMS 가 주인(재적재가 안 건드린다 · 문지기 product_description_guard) · '' = 일부러 비움 · 고친 시각 · 사람이 남아 솎아내기(뷰 product_description_edited) · 되돌리기(op description_follow_cin7)
- ⭐ 보내기는 뷰 `product_description` 의 `html_effective` 만 읽는다 · 원문 칸을 직접 보내지 않는다
- ⭐ 거르기(판정 402)는 화면(asung-ims `ims-desc.js` · DOMPurify)과 **같은 규칙을 Shopify 보내기에서도** — 허락: 서식 · 표 · style= · 모든 출처 img · `ref_embed_host` 에 있는 host 의 iframe(유튜브 · 페이스북) / 거름: 그 밖의 iframe(POWR) · script · on…= · javascript: · object · embed · form · meta · link · base · 허락 출처는 표에서 읽는다(코드에 박지 않는다)
- DB 는 판별만(`ims_html_forbidden` · 창구가 저장을 막는다) · 원문(cin7_description)은 POWR 가 든 채 그대로 남는다 — 그래서 보내는 쪽이 반드시 거른다
- Caleb 「어서 세워야 해」 · 순서: 매입 세금 → 할인 원가 → 설명 칸 → Shopify

---

## 4. 오더 상태 · 문서

### 4-a. asung.ca (판정 378)
```
들어오는 순간     주인은 IMS
운송사 + 송장번호  넣는 순간 Shopify 에 「발송 + 송장번호」 — 손님에게 발송 메일은 Shopify 가 보낸다
Pickup · Delivery  운송사 칸의 두 항목(Delivery = 우리 차량) — 고르면 송장 없이 「발송됨」만 · 메일 없음
백오더            같은 Shopify 오더에 두 번째 발송
```

### 4-b. aonebeauty.com (판정 379)
```
Pickup 오더       운송사 Pickup 을 미리 채운다
Ship & invoice    누르는 순간 Shopify 「Ready for pickup」(손님 메일) — 서류까지 끝나 픽업 스테이션에 놓기 바로 전 (단추 이름 판정 382)
그 뒤             「Waiting for pickup」 칩 · 손님이 찾아가면 「Picked up」 단추(메일 없음)
안 찾아감          크레딧 노트(재고 복원 · 재입고 수수료는 그때 판단)
환불              직원이 Shopify 에서 하고 IMS 가 읽어 크레딧에 붙인다
```

### 4-c. 오더 문서 메일 (판정 380)
- asung.ca 직원은 오더 안에서 손님에게 최종 인보이스 · 결제 요청 · 패킹 리스트를 메일로 보낸다
- **IMS 오더 문서 메일 기능이 컷오버 전에 필요** — 인보이스 인쇄(so-module 미룬 127)가 먼저 · 미룬 147

---

## 5. ⬜ 열린 확인 거리 (시험 스토어에서)

```
① 앱(Wholesale All In One)이 할인을 오더 데이터에 남기는 모양(2-e)
② 무료 배송 자동 할인과 앱 할인의 겹침 · Shopify 설정 바꾸는 법(2-g · 대화 Claude)
③ Available 숫자 대조 — 위치별 · 웹 오더 직후(3-d)
④ 다른 브랜치로 바꾸기 장면 끝에서 끝(2-c)
⑤ 컷오버 뒤 앱 규칙(딜 · 손님 할인) 두 번 입력 — IMS 와 앱(so-module 미룬 149)
```

## 6. 갱신

- 새 판정은 so-module 의 그날 절에 원문 표 · 이 파일에는 주제별로 옮긴다(판정 번호를 단다)
- 이 문서와 so-module 표가 어긋나면 **판정 원문(so-module)이 맞다**
- [2026-10-09 · so-module §55] §3-f 를 판정 401 · 402 · desc-1b(9184853) 실물로 고침 — 복사 없음 · 보내기는 product_description 뷰만 · 거르기는 ims-desc.js 와 같은 규칙
