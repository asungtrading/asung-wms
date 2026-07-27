# WMS Edge Function

로컬: `~/asung-wms/supabase/functions/hello/index.ts` (Deno/TypeScript). 배포: `supabase functions deploy hello`. 현재 연습 함수명 `hello` 재활용 중.

## 공통 헬퍼 (1·2·3단계 공유)

```typescript
const CIN7_BASE = "https://inventory.dearsystems.com/ExternalApi/v2";

function cin7Headers(): HeadersInit {
  return {
    "api-auth-accountid": Deno.env.get("CIN7_ACCOUNT_ID") ?? "",
    "api-auth-applicationkey": Deno.env.get("CIN7_APPLICATION_KEY") ?? "",
    "Content-Type": "application/json",
  };
}
function normWarehouse(loc: string): string {
  return /edmonton/i.test(loc || "") ? "edmonton" : "toronto";
}
async function sbSelect(path: string): Promise<any[]> {  // Supabase REST 조회
  const url = (Deno.env.get("SUPABASE_URL") ?? "") + "/rest/v1/" + path;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resp = await fetch(url, { headers: { apikey: key, Authorization: "Bearer " + key } });
  if (!resp.ok) throw new Error("Supabase " + resp.status + ": " + (await resp.text()).slice(0,300));
  return await resp.json();
}
```
⚠️ `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY`는 Edge Function에 자동 주입(별도 secrets 등록 불필요, GAS용과 별개).

## assembleLine() — 라인 정규화+조립 (2단계, 순수함수. 3단계·프론트 재사용)

라인 하나를 받아: ①스냅샷 조회(order_sku 기준) ②정규화(base_sku·factor는 스냅샷에서, `required_base=ordered_qty×factor`) ③**bin 조회는 base_sku 기준**(재고는 낱개=base로 쌓임) ④flags 계산. 반환: order_sku, base_sku, is_variant, ordered_qty, factor, required_base, product_name, is_selling, available_total, bins[{bin,zone,available}], flags[].

```typescript
async function assembleLine(ln: any, warehouse: string) {
  const orderSku = (ln.SKU ?? "").trim();
  const orderedQty = Number(ln.Quantity) || 0;
  const snap = await sbSelect("wms_sku_snapshot?sku=eq." + encodeURIComponent(orderSku) + "&limit=1");
  const s = snap[0] ?? null;
  const baseSku = s?.base_sku ?? orderSku;
  const factor  = s?.factor ?? 1;
  const requiredBase = orderedQty * factor;
  const bins = await sbSelect(
    "wms_sku_bins?sku=eq." + encodeURIComponent(baseSku) +   // ⚠️ base_sku 로 조회
    "&warehouse=eq." + warehouse + "&is_current=eq.true&order=available.desc");
  const flags: string[] = [];
  if (!s) flags.push("no_snapshot");
  if (s && s.is_selling === false) flags.push("not_sellable");
  if (bins.length === 0) flags.push("no_bin");
  const totalAvail = bins.reduce((sum, b) => sum + (Number(b.available)||0), 0);
  if (bins.length > 0 && totalAvail < requiredBase) flags.push("short_stock");
  return { order_sku: orderSku, base_sku: baseSku, is_variant: s?.is_variant ?? false,
    ordered_qty: orderedQty, factor, required_base: requiredBase,
    product_name: s?.product_name ?? ln.Name ?? "(스냅샷 없음)", is_selling: s?.is_selling ?? null,
    available_total: totalAvail, bins: bins.map(b => ({bin:b.bin,zone:b.zone,available:Number(b.available)||0})),
    flags };
}
```

## 1·2단계 흐름 (검증 완료, 저장 안 함)

특정 오더(SO-13284) 하나로 파이프라인 검증:
1. `saleList?Limit=5&Search={orderNo}` → OrderNumber 매칭으로 SaleID
2. `/sale?ID={saleId}` 상세 → `AdditionalAttributes.AdditionalAttribute1` 확인 + `Location`(→normWarehouse) + `Order.Lines`
3. 각 라인 `assembleLine()` → JSON 응답

**SO-13284 검증결과**(edmonton): 3라인 DEL11336/DEL12355/DEL45022 전부 factor1 base, bin EZ01Pallet04 zone Z, available 17/9/12, is_selling true, flags 전부 빈배열, total_required_base=28.

## 3단계 (완료 · 검증됨, 2026-07-18)

import 파이프라인 완성. 흐름: saleList AUTHORISED 50건 폴링 → `SKIP_PICKED`(CombinedPickingStatus='PICKED' 스킵) → 각 `/sale` 상세 `AdditionalAttribute1='2.Release to WMS'`만 → dedup(`cin7_sale_id` 있으면 스킵) → `assembleLine()` 정규화 → `needsReview`(라인 flag 있으면 true) → **`?commit=1`일 때만 저장**(기본 dry-run 안전장치). `wms_orders` insert(return=representation로 id 회수) → `wms_order_lines` insert, 라인 실패 시 헤더 롤백.
- 검증: dry-run SO-13284만 would_insert, commit 후 inserted 1, 재실행 skipped 1(already_exists) = dedup 작동. 라인 base_sku·factor·req_base·bin·zone·is_selling 저장 확인.
- `wms_orders.needs_review` 컬럼 추가됨.
- ⬜ 남은 것: 폴링 스케줄(자동 import 크론). 현재 수동 호출.

## 확대 폴링 + 자동 스케줄러 (2026-07-21, LIVE)

**확대 폴링**(3단계 위에 얹음): saleList AUTHORISED **페이지네이션**(POLL_LIMIT 100 × POLL_MAX_PAGES 3 = 300 스캔), `SKIP_PICKED`, **상세조회 전 dedup**(`existingSaleIds()`: cin7_sale_id in.(...) 청크 50), `MAX_DETAIL` 60캡(detail_capped 플래그), DETAIL_DELAY_MS 250. dry-run 진단필드: `pages_scanned·candidates·after_skip_picked·already_exists·fresh_candidates·detail_fetched·detail_capped·would_insert`.
- ⚠️ **이 필드들이 응답에 없으면 옛날(50건 1페이지) 버전이 배포된 것.** `supabase functions download hello`로 받은 소스가 stale일 수 있으니, 확대판(POLL_MAX_PAGES 상수 존재)으로 덮어쓴 뒤 deploy. 배포 전 `Select-String -Path ...\hello\index.ts -Pattern "POLL_MAX_PAGES"`로 확인.

**자동 스케줄러**(`wms_schedule_polling.sql`): pg_cron + pg_net. 잡 `wms-poll-orders` `*/5 * * * *` → 함수 `?commit=1` anon Bearer 호출. 검증: `select * from cron.job;` / 실행이력 `cron.job_run_details`(succeeded) / 응답 `net._http_response`(status_code 200).
- ⚠️ **net._http_response가 null로 남을 수 있음**(pg_net 타임아웃 ~5초 초과, 상세조회 여럿 돌 때). **저장은 됐을 수 있으니 진실은 `wms_orders.imported_at`으로 확인.**
- ⚠️ **Cin7 병행운영**: 유입 전 상태변경→유입안됨(정상), Cin7에서 PICKED→SKIP_PICKED 제외("안 들어온다" 최빈원인), **유입 후 변경→WMS 모름**(dedup, 재조회 안 함 — 병행 테스트 위험, 자동감지 백로그).

## 호출 (테스트) — bash + curl
```bash
ANON="<anon public key>"
BASE="https://gftpcnkxbdjzzfvzwcfl.supabase.co/functions/v1"

# dry-run (저장 안 함)
curl -s "$BASE/hello" -H "Authorization: Bearer $ANON" | jq .

# 저장까지: ?commit=1
curl -s "$BASE/hello?commit=1" -H "Authorization: Bearer $ANON" | jq .
```
⚠️ 이전 기록의 PowerShell 예시(`Invoke-RestMethod`)는 낡았다 — 개발환경은 WSL2 Ubuntu + bash. 여기선 진짜 curl 이라 `-H` 정상 동작.

## Edge Function `receiving` (2026-07-23, hello 와 별개 함수)

로컬 `supabase/functions/receiving/index.ts`. 배포 `supabase functions deploy receiving`. 브라우저 호출용 CORS 포함, anon Bearer.

**액션**:
- `?action=pos[&search=]` — 리시빙 준비 PO. **필터 4중**: purchaseList `InvoiceStatus=AUTHORISED`(서버 파라미터 — Invoice First) + Status 에 VOID/COMPLETED/CREDITED 포함 제외 + **Status 에 RECEIVED 포함 제외(단 RECEIVING 은 유지 — 부분입고 진행중)** + Type 에 Service 포함 제외(운송·관세 — 물건 없음) + StockReceivedStatus=AUTHORISED 제외. ⚠️ 상태는 "RECEIVED / CREDITED" 같은 복합 문자열이라 includes 로 검사(정확 일치는 새는 원인이었음).
- `?action=po&id=&type=` — Simple/Advanced 자동 분기(`/purchase` vs `/advanced-purchase`), Lines 위치 d.Lines || d.Order.Lines 양쪽 방어. 스냅샷 배치 조인(in.() 청크 50)으로 base_sku·factor·expected_base(=qty×factor)·이미지·scannable_barcodes 정규화.
- `?action=transfers` — stockTransferList Status='IN TRANSIT'. warehouse = normWarehouse(ToLocation).
- `?action=transfer&id=` — /stockTransfer 상세 + 동일 정규화. to_location_raw·to_guid(기본 착지 bin) 포함.
- `?action=apply&receipt_id=N` — **dry-run 계획**(아무것도 안 씀): 대상 라인(received>0 & 승인됨 & bin 있음), 스킵 사유(off-PO 미승인/승인됨이지만 PO에 없음/bin 없음), 수량 변환(received_base÷factor — 안 나눠떨어지면 에러), 단계 설명.
- `?action=apply&receipt_id=N&commit=1&by=이름` — 실제 쓰기 (아래).

**Apply commit 흐름**:
- 공통 가드: `applied_at` 있으면 거부(이중 방지), status=completed 만.
- **PO**: ①`/purchase/invoice` 로 인보이스 AUTHORISED/PAID 확인(아니면 에러 — Invoice First) ②POST /purchase/stock DRAFT — 라인마다 {Date(필수), SKU:order_sku, Quantity:received_base÷factor, LocationID:binGuid(창고,putaway_bin), Received:false} ③Authorize = {TaskID, Status:'AUTHORISED', Lines:[]} 재요청 — **미실측 단계**, 실패 시 WARN 로그만(DRAFT 남음 → Cin7 수동 Authorize).
- **트랜스퍼**: ①GET 원 TR ②PUT 전체 객체 그대로 + Status:'COMPLETED' + CompletionDate (전량 기본 To bin 착지) ③putaway_bin 그룹별 POST 미니 트랜스퍼 {From:원TR.To(GUID), To:binGuid(그룹bin), Lines:[{SKU:base_sku, TransferQuantity:qty_base}], Status:'COMPLETED', SkipOrder:true} — 기본 bin 그룹은 스킵. 콜 간 sleep 300.
- 성공 시 wms_receipts PATCH: applied_at/by/apply_note(로그 조인).

**binGuid(창고이름, bin이름)**: /ref/location Limit=500 → 창고 행의 Bins[] 또는 ParentID=창고 인 child-location 에서 이름 매칭 → GUID. 요청 내 캐시(_locCache). ⚠️ Cin7 쓰기 API 는 이름("창고: bin") 거부 — 반드시 GUID.

## receiving EF — 2026-07-24 실측 반영 업데이트

**action=bins** (신규): `?action=bins&warehouse=` → Cin7 `/ref/location` 에서 그 창고 전체 bin(빈 자리 포함) `[{bin,id}]`. 빈 지정 드롭다운 소스(신제품 새 자리). 창고 하위 Bins[] + ParentID=창고 child-location 둘 다 수집.

**applyCommit PO 경로 — 실측 확정 형태**:
- Date = `YYYY-MM-DDT00:00:00Z` (자정, 밀리초 없이).
- ⚠️ **bin 별 분할 POST**: plan.lines 를 putaway_bin 으로 그룹핑 → bin 마다 별도 `POST /purchase/stock {Status:DRAFT, Lines:[...그 bin 라인만...]}` (콜 간 sleep 400). **한 문서에 여러 bin 섞으면 400 "Lines is invalid"** (실측 PO-00965).
- buildApplyPlan 이 같은 (SKU+bin) 라인 수량 합산 병합(중복 라인 400 방지).
- **Authorize = `POST` "/purchase/stock" {Status:'AUTHORISED', Lines:[]}** (PUT 은 405 — 실측). 실패 시 WARN(DRAFT 는 남음).
- 성공 시 wms_receipts PATCH: **status='completed'** + applied_at/by/apply_note.
- Invoice First: `/purchase/invoice` 로 AUTHORISED/PAID 선확인.

**진단 팁**: cin7() 실패 throw 에 `| SENT: {body}` 포함(디버깅용, 유지). Cin7 "Lines is invalid" 는 대개 (a)여러 bin 섞임 (b)같은 SKU+bin 중복 (c)PO 에 없는 SKU — SENT 로 격리. GAS `WmsPoStockWriteTest.gs` 의 `psMultiLineTest`(bin별 분할 검증)·`psAuthorizeTest`(PUT/POST 판별) 패턴 재사용.

**트랜스퍼(창고간) 미완**: applyCommit transfer 경로는 아직 같은창고 bin↔bin 기준. 실제 IN TRANSIT(TR-03259 등)은 warehouse→warehouse 라 워크플로 재설계 필요(규칙 21 참고).

## receiving EF — 트랜스퍼 경로 실측 반영 (2026-07-25)

**applyCommit transfer 경로 (확정형)**:
1. `GET /stockTransfer?TaskID=` 로 원본 확보 (Status 는 IN TRANSIT 이어야 함 — plan 단계에서 검증)
2. **실물 수량으로 덮어쓰기**: plan.lines 를 base_sku 기준 합산(`recvBySku`) → 원본 Lines 의 `TransferQuantity` 를 received 로 교체(없는 SKU 는 원본 유지). 몇 줄이 달랐는지 로그(`changed`).
3. `PUT /stockTransfer {TaskID, Status:'COMPLETED', From, To, CostDistributionType, InTransitAccount, DepartureDate, CompletionDate, Reference, Lines: putLines, SkipOrder:true}` — Date 는 `YYYY-MM-DDT00:00:00Z`.
4. **bin 이동**: `landingBin = to_location_raw.split(":")[1]` (창고만이면 "") → plan.groups 순회, `landing && g.bin===landing` 이면 스킵(이미 제자리), 나머지는 `POST /stockTransfer {Status:'COMPLETED', From: det.To, To: binGuid(wh,g.bin), Lines:[{SKU:base_sku, TransferQuantity:qty_base}], SkipOrder:true}` (sleep 300).
   - ⚠️ **From 은 항상 `det.To`**. 창고 GUID면 "bin 없는 재고"를, 집결 bin GUID면 그 bin 을 꺼냄 — 둘 다 실측 200.
5. receipt PATCH(status/applied_at/…) 후 **discrepancy 기록**(아래).

**discrepancy 기록 (PO·트랜스퍼 공통)**: buildApplyPlan 이 SKU 단위로 received vs expected 비교해 `plan.discrepancies[]`(reason `recv_over`/`recv_short`/`recv_off_po`) 생성 → applyCommit 마지막에 `POST wms_discrepancies?on_conflict=receipt_id,sku` + Prefer `resolution=ignore-duplicates,return=minimal`. `sb()` 헬퍼에 4번째 인자 `prefer` 추가함. 실패해도 Apply 는 성공(WARN 로그).

## 폴링 EF `hello` — Reference 저장 (2026-07-25)

`extractReference(d)` 추가: `d.CustomerReference` → 폴백 `d.Reference`. `wms_orders.reference` 로 저장, dry-run `would_insert` 에도 노출해 유입 확인 가능. ⚠️ **`wms_order_reference.sql`(컬럼 추가)을 배포보다 먼저** — 없으면 insert 400.
