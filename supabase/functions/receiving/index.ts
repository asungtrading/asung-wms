// ============================================================
// ASUNG WMS — Edge Function: receiving (v2)
// ------------------------------------------------------------
// 액션:
//   ?action=pos                → 리시빙 준비된 PO (Status=INVOICED+RECEIVING 조회, Invoice First 는 클라이언트 검사)
//   ?action=pos&search=...     → PO 검색 (동일 필터)
//   ?action=po&id=&type=       → PO 상세 + 라인 정규화(스냅샷 조인)
//                                ⚠️ 기대치(expected_base)는 2026-08-05 부터 **인보이스 라인** 기준 —
//                                   라인 집합은 Order.Lines 유지 + 수량만 덮어쓰기. 인보이스 없으면 오더 폴백.
//   ?action=transfers          → IN TRANSIT 트랜스퍼 (입고 대기)
//   ?action=transfer&id=       → 트랜스퍼 상세 + 라인 정규화
//   ?action=apply&receipt_id=N          → Apply 계획(dry-run) 반환 — 아무것도 안 씀
//   ?action=apply&receipt_id=N&commit=1 → 실제 Cin7 쓰기 실행
//
// 검증된 쓰기 (2026-07-23 실측):
//   [PO]  POST /purchase/stock — TaskID + Lines[{Date,SKU,Quantity,LocationID(bin GUID),Received}]
//         DRAFT 생성 확인. ⚠️ 선행조건: 인보이스 authorize (아니면 400 'Invoice First').
//         Authorize = 빈 Lines 재요청 (⚠️ 이 단계만 미실측 — 실패 시 DRAFT 는 남음, Cin7 화면 수동 Authorize 안내).
//         2026-07-31: 트랜스퍼 보호 장치 이식 — 청크 이중 가드·exported_base 체크포인트(의미: "문서에 실은 양")·
//         실패 수집/격리. ⚠️⚠️ authorize 는 1회뿐 → **모든 bin 그룹이 문서에 실린 회차에만 한 번** 시도(게이트).
//   [TR]  POST /stockTransfer — From/To 는 bin GUID (이름은 400), 즉시 COMPLETED 가능,
//         같은 창고 bin↔bin 은 InTransitAccount 불필요. (TR-03236 실측)
//         트랜스퍼 완료 = PUT 원 TR COMPLETED (기본 To bin 착지) → bin 그룹별 미니 트랜스퍼로 재배치.
//         ⚠️⚠️ 완료 PUT 의 TransferQuantity 변경은 **무시된다** (2026-07-28 TR-03267 실측 — 아래 applyCommit 주석).
//         → 완료 수량 = 보낸 수량 확정 / 실물 차이는 discrepancy 큐 / bin 이동은 min(received, expected) 캡.
// ============================================================

// Cin7 HTTP 레이어는 hello(폴링)와 공용 — 429 백오프·에러 구조화가 한 곳에서 관리된다 (2026-08-04 공용화).
// ⚠️ _shared/cin7.ts 를 바꾸면 hello 도 함께 재배포할 것 (파일 상단 주석 참조).
import { cin7, cin7ErrInfo, cin7Get, sleep } from "../_shared/cin7.ts";

const CORS: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function normWarehouse(loc: string): string {
  return /edmonton/i.test(loc || "") ? "edmonton" : "toronto";
}
// (cin7/cin7Get/cin7ErrInfo/sleep 은 ../_shared/cin7.ts 에서 import — 상단 주석 참조.
//  429 백오프 1.5s→3s 상한 2회, 소진 시 err.status=429 throw, 에러에 status/body 구조화 — 동작 불변.)

// ── 목적지 bin 의 SKU 보유량 되읽기 (checkpoint repair 판정용, 2026-07-31 — TR-03144) ──
// GET /ref/productavailability 는 (SKU × Location × Bin) 행 단위로 OnHand 를 준다 (cin7-api 스킬 product.md).
// · **OnHand 로 판정한다 (Available 아님)** — Available 은 판매 배정(Allocated) 차감값이라, 이미 도착한 재고가
//   그 사이 오더에 배정되면 "도착했는데 미도착" 으로 오판한다. 물리 도착의 근거는 OnHand.
// · Sku 파라미터의 일치 방식(정확/전방)이 미확정이라 **응답 행을 클라이언트 측에서 정확 일치로 다시 거른다**
//   (SKU 정확 일치 + 창고 normWarehouse 일치 + Bin trim/대문자 정확 일치) — 다른 SKU·다른 bin 오염 방지.
// · 반환 null = **판정 불가** (조회 실패·응답 잘림) — 호출부는 실패로 남긴다(오판이 미이동보다 나쁘다).
async function binOnHand(warehouse: string, binName: string, sku: string): Promise<number | null> {
  try {
    const d = await cin7Get("/ref/productavailability?Sku=" + encodeURIComponent(sku) + "&Limit=1000");
    const rows = (d.ProductAvailabilityList || []) as any[];
    if (Number(d.Total || 0) > rows.length) return null;   // 잘림 — 전체를 못 봤으면 판정하지 않는다
    const binKey = String(binName || "").trim().toUpperCase();
    const skuKey = String(sku || "").trim().toUpperCase();
    let sum = 0;
    for (const r of rows) {
      if (String(r.SKU || "").trim().toUpperCase() !== skuKey) continue;
      if (normWarehouse(String(r.Location || "")) !== normWarehouse(warehouse)) continue;
      if (String(r.Bin || "").trim().toUpperCase() !== binKey) continue;
      sum += Number(r.OnHand || 0);
    }
    return sum;
  } catch { return null; }
}

async function sb(method: string, path: string, body?: unknown, prefer?: string): Promise<any> {
  const url = (Deno.env.get("SUPABASE_URL") ?? "") + "/rest/v1/" + path;
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const resp = await fetch(url, {
    method,
    headers: { apikey: key, Authorization: "Bearer " + key, "Content-Type": "application/json", Prefer: prefer || "return=representation" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (!resp.ok) throw new Error("Supabase " + resp.status + ": " + (await resp.text()).slice(0, 300));
  const t = await resp.text();
  return t ? JSON.parse(t) : [];
}
const sbSelect = (path: string) => sb("GET", path);

function inList(vals: string[]): string {
  return vals.map((v) => '"' + String(v).replace(/"/g, '\\"') + '"').join(",");
}

const WH_NAME: Record<string, string> = { toronto: "Asung Trading Inc.", edmonton: "Asung - Edmonton" };

// ── Apply 청크 이중 가드 — 그룹 수 + 시간 예산, 먼저 걸리는 쪽에서 회차를 끊는다 (2026-07-31 v2) ──
// 실측 1차: TR-03144(327라인/100+그룹)·TR-02935(144그룹) 모두 30~40 그룹 부근에서 EF 실행시간 한도로 죽어
// `applied_at`·`apply_note` 가 **둘 다 null** 로 남았다(실패 목록조차 없음) → 상한 30 도입.
// 실측 2차(상한 30 배포 후, TR-03144): **여전히 첫 회차조차 완주하지 못했다** — exported_base 는
// 210→225→250 으로 전진하는데 apply_note 는 계속 null(회차 종료부 미도달). 실패 그룹도 Cin7 왕복+sleep 을
// 소비하므로 성공만으로는 회차 시간을 예측할 수 없고, 그룹 수만으로는 Cin7 응답이 느린 날 또 죽는다
// → **12 로 낮추고 시간 예산 가드를 추가**. 회차가 많아지는 것보다 완주하지 못하는 게 훨씬 나쁘다(기록이 안 남고,
// Stop 도 회차 경계에서만 동작하므로 듣지 않는다).
// 상한 도달은 예외가 아니라 **정상 종료**다: 응답 done:false + groups_remaining + stopped_by("groups"|"time"),
// apply_note 는 매 회차 갱신, applied_at 은 모든 그룹이 끝난 회차에만 찍는다. admin.html 이 자동으로 재호출한다.
const APPLY_MAX_GROUPS = 12;
// 시간 예산 — **요청 시작 시각(t0)** 부터 잰다(buildApplyPlan 의 DB·Cin7 조회, resume 아닌 회차의 PUT 포함 —
// EF 한도가 보는 것도 요청 전체이므로). 넘으면 **다음 그룹을 시작하지 않고** 정상 종료한다.
// ⚠️ 판정은 반드시 Cin7 POST **앞**(그룹 루프 머리)에서 — 반쯤 옮긴 그룹이 생기면 안 된다.
const APPLY_TIME_BUDGET_MS = 20000;

// ── 실패 그룹 처리 규칙 (2026-07-31 v3 — TR-03144 실측) ──
// 청크 v2 배포 후에도 진행이 멈췄다: 실패 그룹 **3건만으로 20초 예산을 전부 소진**했다(Cin7 400 응답이 느리고
// 한 그룹에 SKU 5~7개). 실패 그룹이 plan.groups 앞쪽에 있어 매 회차 그것들을 먼저 시도하고 끝났고,
// 남은 46개 미처리 그룹은 영구히 진행되지 못했다(groups_moved=0 → admin 무한루프 가드가 자동 반복도 중단).
// 실패 사유는 전부 "Available quantity … is 0" — 사람이 Cin7 재고를 고치기 전엔 재시도해도 영원히 실패한다.
//  ① 순서: 아직 시도하지 않은 그룹 먼저, 실패 이력 그룹은 뒤로(buildApplyPlan 이 fail_counts 로 정렬)
//     → 매 회차 실제 전진(groups_moved > 0)이 생겨 admin 자동 반복이 계속된다.
//  ② 격리: 같은 bin 이 연속 APPLY_QUARANTINE_FAILS 회 이상 실패하면 자동 재시도 대상에서 제외하고
//     permanently_failed 로 분류한다("N bin(s) need manual fixing in Cin7"). ⚠️ 영구 제외가 아니다 —
//     사람이 재고를 고친 뒤 admin 'Retry failed bins'(?retry_failed=1)를 누르면 카운트가 리셋돼 다시 시도한다.
//  ③ 실패 시간 상한: 한 회차에서 실패 이력 그룹 시도에 쓰는 시간 합을 APPLY_FAIL_BUDGET_MS 로 막는다
//     (전체 예산 20초의 일부만 실패에 허용 — 초과분은 다음 회차로).
//  연속 실패 카운트는 apply_note 의 `fail_counts:{"BIN":n}` 마커로 회차 간 이월한다(새 컬럼·테이블 없음 —
//  근거는 buildApplyPlan 의 파싱 주석). ⚠️ 400(재고 부족)은 재시도 가치가 없다 — cin7() 의 백오프 재시도는
//  429 전용이라 400 은 애초에 재시도되지 않는다(그대로 유지할 것).
//  ④ 목적지 되읽기 회복(checkpoint repair): "Available quantity … is 0" 400 에 한해 목적지 bin 을 되읽어
//     이미 도착해 있으면 완료로 간주한다 — 그룹 루프 catch 안의 주석 참조(TR-03144 실측 근거 포함).
const APPLY_FAIL_BUDGET_MS = 6000;
const APPLY_QUARANTINE_FAILS = 3;

// ── 청크 가드 공용 판정 (2026-07-31 — PO 경로 이식하며 트랜스퍼와 상수·판정을 한 곳으로) ──
// 반환 = 걸린 가드("groups"|"time"|"rate"|"fail_budget") 또는 null(계속 진행).
// ⚠️ 반드시 Cin7 POST **앞**(그룹 루프 머리)에서 호출한다 — 반쯤 쓴 그룹/문서를 만들지 않는다.
// 판정 순서는 기존 트랜스퍼 코드와 동일: (그룹 상한 ‖ 429 ‖ 시간 예산) → 실패 이력 그룹 시간 상한.
// "rate" 는 stopped_by 에 기록하지 않는다(응답의 rate_limited 필드가 따로 밝힌다) — 호출부가 거른다.
function chunkGuard(groupsAttempted: number, rateLimited: boolean, t0: number,
  prevFails: number, failSpentMs: number): "groups" | "time" | "rate" | "fail_budget" | null {
  if (groupsAttempted >= APPLY_MAX_GROUPS) return "groups";
  if (rateLimited) return "rate";
  if (Date.now() - t0 > APPLY_TIME_BUDGET_MS) return "time";
  if (prevFails > 0 && failSpentMs > APPLY_FAIL_BUDGET_MS) return "fail_budget";
  return null;
}

// ── bin 이름 → GUID (실측 검증: Cin7 쓰기 API 는 이름 거부, GUID 만 받음) ─────────
// ⚠️⚠️ 실사고 2026-07-28 (TR-02935, 첫 에드먼튼 Apply): `/ref/location` 은 **Total 2678 인데 Limit 500 에서 잘린다.**
//   반환된 500행의 내용 = 최상위 창고 2행 + **토론토 child-location 498행뿐, 에드먼튼 child 는 0행**(전부 뒤 페이지).
//   그래서 에드먼튼 bin GUID 조회가 **첫 호출부터 throw** → Apply 의 bin 이동이 한 건도 실행되지 않고
//   전 품목이 집결 bin EZ010101 에 남았다(수량이 정확히 맞는 라인까지 남은 것이 "첫 호출부터 throw" 의 증거).
//   ⚠️ 토론토도 안전하지 않았다: Bins[] 가 2047 개인데 child 는 498행만 들어오므로 앞쪽 밖의 토론토 bin 도 같은 실패를 낸다.
//   PO-01066·PO-00965 가 성공한 것은 그 bin 들이 우연히 앞 페이지에 있었기 때문일 뿐이다.
//
// ✅ 해결 (실측 확정): **최상위 창고 행(ParentID 없음)의 `Bins[]` 에 GUID 가 이미 전부 들어있다** — 페이지네이션 불필요.
//   · Asung - Edmonton   (623edcaa-5f18-4682-aae1-b9016d977c11) Bins[] = 628개
//   · Asung Trading Inc. (f1ca3946-5a4e-4da7-b68a-ce7d3500f0be) Bins[] = 2047개
//   · 원소 형태: {"ID":"5fb51e98-…","Name":"EA010101","IsDeprecated":false,"IsStaging":false}
//   · 실측 확인: EZ010101 → b997fb39-03ee-48fd-8979-18940e082490 · EG030102 → 07f87571-fccc-400f-857f-ab31096b8fe6
//   최상위 2행은 응답 앞머리에 오므로 Limit=500 한 번으로 충분하다(잘림은 child 행에서만 발생).
//
// ❌ **child-location 이름 매칭 경로는 제거했다.** 실측상 child 의 `Name` 은 bin 이름이 아니다
//   (예 "071164313169" — 바코드류). 즉 이 경로는 처음부터 매칭될 수 없었고, 남겨두면 "폴백이 있으니 괜찮다" 는
//   오해를 남긴다. bin GUID 의 유일한 출처는 최상위 창고 행의 Bins[] 다.
let _locCache: any[] | null = null;
async function locations(): Promise<any[]> {
  if (!_locCache) _locCache = (await cin7Get("/ref/location?Limit=500")).LocationList || [];
  return _locCache as any[];
}

// 창고별 bin 이름(대문자) → {id, name} 맵. 요청 내 1회만 만든다(_locCache 재사용).
// key 는 대문자 비교용이고 name 은 Cin7 원본 표기를 그대로 보존한다 — "EZ01Pallet05" 처럼 대소문자가 섞인 bin 이 있고,
// 이 이름이 putaway_bin·to_location_raw 비교(이미 제자리 스킵)·프린트에 그대로 쓰이므로 대문자로 바꿔 내보내면 안 된다.
const _binMaps: Record<string, Map<string, { id: string; name: string }>> = {};
async function binMap(warehouse: string): Promise<Map<string, { id: string; name: string }>> {
  const key = normWarehouse(warehouse);   // 'edmonton'/'toronto' 도, 'Asung - Edmonton' 같은 Cin7 이름도 받는다
  const hit = _binMaps[key];
  if (hit) return hit;
  const list = await locations();
  const tops = list.filter((l: any) => !l.ParentID);
  const wh = tops.find((l: any) => (l.Name || "").trim() === (WH_NAME[key] || "").trim())
    || tops.find((l: any) => normWarehouse(l.Name || "") === key);
  if (!wh) throw new Error("warehouse not found in /ref/location: " + warehouse);
  const m = new Map<string, { id: string; name: string }>();
  for (const b of (wh.Bins || []) as any[]) {
    if (b.IsDeprecated) continue;                       // 폐기된 bin 은 매칭 대상 아님
    const name = String(b.Name || "").trim();
    const k = name.toUpperCase();
    if (k && b.ID && !m.has(k)) m.set(k, { id: String(b.ID), name });
  }
  _binMaps[key] = m;
  return m;
}
async function binGuid(warehouse: string, binName: string): Promise<string> {
  const g = (await binMap(warehouse)).get(String(binName || "").trim().toUpperCase());
  if (!g) throw new Error("bin not found: " + binName + " @ " + warehouse);
  return g.id;
}
// GUID 를 못 찾아도 throw 하지 않는 버전 — Apply 는 그 라인만 스킵하고 나머지를 계속 쓴다.
// ⚠️ TR-02935 의 피해가 커진 직접 원인이 "bin 한 건 실패 → 전체 throw → receipt PATCH·discrepancy 까지 유실" 이었다.
async function tryBinGuid(warehouse: string, binName: string): Promise<{ guid: string | null; reason: string }> {
  try {
    return { guid: await binGuid(warehouse, binName), reason: "" };
  } catch (e) {
    return { guid: null, reason: String((e as Error).message || e).slice(0, 200) };
  }
}

// ── 스냅샷 배치 조인 (라인 정규화 공용) ─────────────────────
async function snapMap(skus: string[]): Promise<Record<string, any>> {
  const out: Record<string, any> = {};
  const uniq = [...new Set(skus.filter(Boolean))];
  for (let i = 0; i < uniq.length; i += 50) {
    const rows = await sbSelect(
      "wms_sku_snapshot?sku=in.(" + encodeURIComponent(inList(uniq.slice(i, i + 50))) + ")" +
      "&select=sku,base_sku,factor,is_variant,product_name,image_url,scannable_barcodes");
    rows.forEach((r: any) => { out[String(r.sku).toUpperCase()] = r; });
  }
  return out;
}
// expectedQty (2026-08-05): PO 경로가 인보이스 수량으로 기대치를 덮어쓸 때 넘긴다.
// ⚠️ 트랜스퍼는 절대 넘기지 않는다 — 트랜스퍼에는 인보이스가 없고, expected_base 는
//    bin 이동 캡 min(received, expected)의 근거다(규칙 20 트랜스퍼 예외). 안 넘기면 종전과 동일(qty).
function normLine(l: any, s: any, expectedQty?: number | null) {
  const orderSku = String(l.SKU || "").trim();
  const qty = Number(l.Quantity ?? l.TransferQuantity) || 0;
  const expQty = (expectedQty === undefined || expectedQty === null) ? qty : (Number(expectedQty) || 0);
  const factor = (s && Number(s.factor) > 0) ? Number(s.factor) : 1;
  return {
    cin7_po_line_id: l.ProductID || null,
    order_sku: orderSku,
    base_sku: s ? s.base_sku : orderSku,
    factor,
    expected_base: expQty * factor,
    ordered_qty: qty,
    product_name: (s && s.product_name) || l.Name || l.ProductName || "",
    image_url: (s && s.image_url) || "",
    scannable_barcodes: (s && s.scannable_barcodes) || [],
    no_snapshot: !s,
  };
}

// ── PO 목록: Status=INVOICED + RECEIVING (Invoice First 는 클라이언트 검사) ──────
// 2026-08-04 전환 — 왜 InvoiceStatus 서버 필터가 아니라 Status 인가 (실측, 전체 PO 1,129건):
//  · 종전 InvoiceStatus=PAID 조회는 창업 이후 지불을 마친 **모든** PO(877건)를 돌려주는데, 그중 리시빙
//    대상은 0건 — 전량 받아 클라이언트 필터로 버리고 있었다. PO 는 계속 쌓이므로 언젠가 페이지 상한
//    (Limit 1000 × 3페이지)에 닿고, **정렬이 PO 번호 오름차순이라 잘리는 쪽은 항상 최신 PO** 다 —
//    2026-07-28 PO-01081 누락과 같은 형태의 조용한 사고. 상한 증설은 시간을 살 뿐 근본 해결이 아니다.
//  · **Status 서버 필터는 동작한다**: Status=INVOICED → Total 73 · Status=RECEIVING → Total 5.
//    현재 리시빙 대상 8건은 전부 Status=INVOICED. RECEIVING(부분입고 진행중)은 규칙 20 의 유지 의도대로
//    함께 조회한다(실측상 5건 전부 StockReceivedStatus=AUTHORISED 라 지금은 클라이언트 필터에서 걸러진다).
//  · ⚠️ **여러 값 동시 요청은 불가** — `Status=INVOICED,RECEIVING` 도 `INVOICED|RECEIVING` 도 Total 0.
//    그래서 상태별 개별 조회 + ID dedup (호출 수는 종전 AUTHORISED/PAID 2회와 동일).
//  · ⚠️ **Type 서버 필터는 무시된다** (Simple/Advanced/Service Purchase 모두 무필터와 동일 결과) —
//    Service 제외는 계속 클라이언트에서 한다.
//  · **StockReceivedStatus 서버 필터는 사실 동작한다** (NOT AVAILABLE → Total 585. 2026-07-28 의 "무시된다"
//    는 `RestockReceivedStatus` 로 파라미터 **이름을 잘못 쓴** 실측이었다). 그래도 서버에 걸지 않는다 —
//    RECEIVING 5건이 전부 StockReceivedStatus=AUTHORISED 라 부분입고 유지 의도와 충돌한다.
const PO_STATUSES = ["INVOICED", "RECEIVING"];

// Invoice First 게이트 (규칙 20) — 서버 파라미터에서 클라이언트 값 비교로 이동 (2026-08-04).
// 좁히는 필터이므로 서버에서 빼도 안전하다(못 보던 게 생기는 게 아니라 더 보고 코드로 거르는 쪽).
// ⚠️ includes 가 아니라 **정확 값 비교** — 그 외 값(DRAFT 등 = 인보이스 미승인)은 제외하고,
//    루프가 값별 카운트를 모아 로그에 남긴다(예상 밖 값이 조용히 새지 않게).
// ⚠️⚠️ 이 상수는 **목록 필터와 Apply 게이트(applyCommit)가 공유**한다 (2026-08-06) — 따로 두면
//    한쪽만 고쳐져 "목록은 통과시키는데 게이트는 막는" 불일치가 된다. 값 근거: 인보이스 블록에는
//    Payments·Paid 필드가 따로 있어 결제 정보가 Status 와 분리돼 있다(2026-08-05 실측 — 블록 레벨
//    Status 실측은 AUTHORISED 만). 블록 레벨 PAID 는 미실측이며, 헤더 InvoiceStatus=PAID 가
//    실측된(PO-01081) 정상 후속 상태라 보험으로 포함한다 — 빼면 그 상태의 PO 가 전부 막힌다.
const PO_INVOICE_OK = new Set(["AUTHORISED", "PAID"]);

// ⚠️ 페이지 크기 — 조기 종료 조건(`items.length < PO_PAGE_LIMIT`)과 **반드시 같은 상수**를 써야 한다.
// 둘이 어긋나면(예: Limit=1000 인데 종료 조건이 100) 첫 페이지에서 무조건 루프가 끊긴다.
// Status 기반 전환 후 상태별 Total 은 73/5 수준이라 사실상 page1 한 번으로 끝나지만,
// **정렬이 오름차순(잘리면 최신 PO 부터 누락)이라는 사실은 그대로**이므로 Limit=1000 · 페이지 상한 ·
// truncated 진단(서버 Total 대비 실수신 행수 비교)을 유지한다.
const PO_PAGE_LIMIT = 1000;
const PO_MAX_PAGES = 3;

async function listOpenPOs(search: string): Promise<{ pos: any[]; scanned: Record<string, number>; totals: Record<string, number>; truncated: boolean }> {
  const byId = new Map<string, any>(); // dedup — PurchaseList 의 ID 기준 (두 조회에 같은 PO 가 들어올 수 있음)
  const scanned: Record<string, number> = {}; // 진단 — 상태별로 실제 가져온 행 수 (필터 전)
  const totals: Record<string, number> = {};  // 진단 — 상태별 서버 보고 Total (scanned 보다 크면 못 읽은 게 있다)
  let truncated = false;                      // 진단 — Total 만큼 못 읽은 상태가 있으면 true (페이지 상한 포함)
  const invoiceExcluded: Record<string, number> = {}; // Invoice First 클라이언트 검사에서 떨어진 InvoiceStatus 값별 카운트
  for (let si = 0; si < PO_STATUSES.length; si++) {
    if (si > 0) await sleep(250); // 조회 사이 간격 (Cin7 rate limit)
    const st0 = PO_STATUSES[si];
    scanned[st0] = 0;
    totals[st0] = 0;
    let page = 1;
    while (page <= PO_MAX_PAGES) {
      const q = "/purchaseList?Page=" + page + "&Limit=" + PO_PAGE_LIMIT + "&Status=" + encodeURIComponent(st0) +
        (search ? "&Search=" + encodeURIComponent(search) : "");
      const data = await cin7Get(q);
      const items = data.PurchaseList || [];
      scanned[st0] += items.length;
      totals[st0] = Number(data.Total || 0);
      for (const p of items) {
        // 아래 4개 제외조건은 Status 전환과 무관하게 유지 — 복합 상태("RECEIVED / CREDITED" 등)가 실재하므로 includes 검사.
        const st = String(p.Status || "").toUpperCase();
        if (st.includes("VOID") || st.includes("COMPLETED") || st.includes("CREDITED")) continue; // 끝난/취소 PO (복합상태 포함)
        if (st.includes("RECEIVED") && !st.includes("RECEIVING")) continue;                       // 이미 받은 PO (RECEIVING=부분입고 진행중은 유지)
        if (/service/i.test(String(p.Type || ""))) continue;                                     // Service 주문(운송·관세 등) 제외 — 물건 없음
        if (String(p.StockReceivedStatus || "").toUpperCase() === "AUTHORISED") continue;
        // Invoice First (규칙 20) — InvoiceStatus 는 이제 서버 파라미터가 아니라 여기서 검사한다.
        // 정확 값 비교(AUTHORISED/PAID 만 통과) — 그 외 값은 제외하고 카운트해 아래에서 로그.
        const inv = String(p.InvoiceStatus || "").trim().toUpperCase();
        if (!PO_INVOICE_OK.has(inv)) {
          const k = inv || "(empty)";
          invoiceExcluded[k] = (invoiceExcluded[k] || 0) + 1;
          continue;
        }
        const key = String(p.ID || "");
        if (byId.has(key)) continue;
        byId.set(key, {
          id: p.ID, po_number: p.OrderNumber || "", supplier: p.Supplier || "",
          status: p.Status || "", invoice_status: p.InvoiceStatus || "",
          type: p.Type || "Simple Purchase", order_date: p.OrderDate || null, source: "po",
        });
      }
      if (items.length < PO_PAGE_LIMIT) break;              // 마지막 페이지 (실측: INVOICED 73 · RECEIVING 5 → page1 로 끝)
      if (page === PO_MAX_PAGES) break;                     // 상한 도달 — 못 읽은 잔여는 아래 Total 비교가 잡는다
      page++; await sleep(300);
    }
    if (totals[st0] > scanned[st0]) truncated = true;       // Total 대비 덜 받았다 — 페이지 상한이든 응답 잘림이든
  }
  if (Object.keys(invoiceExcluded).length) {
    // Invoice First 에서 떨어진 PO 들 — DRAFT 등은 정상이지만, 예상 밖 값이 새로 나타나면 여기서 보인다.
    console.warn("[receiving pos] excluded by InvoiceStatus (Invoice First):", JSON.stringify(invoiceExcluded));
  }
  const out = [...byId.values()];
  out.sort((a, b) => String(b.order_date || "").localeCompare(String(a.order_date || "")));
  return { pos: out, scanned, totals, truncated };
}

// ── PO 상세 원본 — poDetail(라인 정규화)과 Apply 의 인보이스 게이트가 같은 소스를 쓴다 ──
// 실측 (2026-08-05 GAS 직접 호출, PO-01068): 상세 응답 안에 인보이스 블록이 이미 들어 있다 —
// `/purchase/invoice` 추가 호출 불필요.
//   · Simple   GET /purchase?ID=          → d.Invoice 는 **객체**
//   · Advanced GET /advanced-purchase?ID= → d.Invoice 는 **배열** (실측 len=1)
//   · 인보이스 라인 필드(양쪽 동일): SKU · Quantity · Price · Total · NonInventory
//   · AdditionalCharges 는 별도 배열 — Discount 류가 Lines 에 섞이지 않는다
//   · SKU 표기는 Order.Lines 와 동일
// ⚠️⚠️ GET /purchase/invoice 는 Advanced PO 에서 400 "deprecated and does not support Advanced
//    Purchase" (실측) — 종전 Apply 게이트가 이 엔드포인트라 Advanced Apply 가 오진 메시지로 막혔다.
// ── 엔드포인트 폴백 (2026-08-05, ⚠️ 현장 미검증) ──
// type 이 실제와 다르면(대표 사례: 마이그레이션 이전 receipt 은 cin7_type 이 NULL → Simple 간주 →
// Advanced PO 에 /purchase 를 쳐서 400) 반대 엔드포인트로 **1회만** 재시도한다.
//   · 400 만 폴백 대상 — 429 는 cin7() 백오프가 이미 소진된 상태(회차 조기 종료가 맞다)고,
//     404·5xx 는 타입 불일치의 신호가 아니다. 그대로 throw (기존 경로 불변).
//   · 반대쪽도 실패하면 **원래 에러**를 던진다 — 무한 재시도 없음.
//   · 폴백 성공은 반드시 console.warn — 조용히 넘기면 cin7_type 이 틀렸다는 사실 자체를 아무도 못 본다.
// 반환이 raw 응답에서 {data, resolvedType, fellBack} 으로 바뀌었다 — 폴백으로 확정된 타입을
// 호출부가 쓴다(poDetail 의 cin7_type 반환값 → receiver 가 receipt 생성 시 저장 /
// Apply 게이트 → 기존 receipt 의 cin7_type 교정 PATCH).
async function poRaw(id: string, type: string, ctx = ""): Promise<{ data: any; resolvedType: string; fellBack: boolean }> {
  const isAdv = /advanced/i.test(type || "");
  const primary = isAdv ? "/advanced-purchase" : "/purchase";
  const fallback = isAdv ? "/purchase" : "/advanced-purchase";
  let firstErr: unknown;
  try {
    const data = await cin7Get(primary + "?ID=" + encodeURIComponent(id));
    return { data, resolvedType: type || "Simple Purchase", fellBack: false };
  } catch (e) {
    if (cin7ErrInfo(e).http_status !== 400) throw e;   // 폴백은 400 전용
    firstErr = e;
  }
  try {
    const data = await cin7Get(fallback + "?ID=" + encodeURIComponent(id));
    console.warn("[receiving poRaw] " + ctx + ": " + primary + " -> 400, fell back to " + fallback +
      " OK (stored type was '" + (type || "NULL") + "')");
    return { data, resolvedType: isAdv ? "Simple Purchase" : "Advanced Purchase", fellBack: true };
  } catch (e2) {
    console.warn("[receiving poRaw] " + ctx + ": " + primary + " -> 400, fallback " + fallback +
      " also failed (" + String((e2 as Error).message).slice(0, 200) + ") - rethrowing the original 400");
    throw firstErr;
  }
}
// Simple(객체)/Advanced(배열)를 하나로 흡수하는 공용 접근자 — 타입 분기를 새로 만들지 않는다.
// ⚠️ Advanced 다중 인보이스(부분 출하)는 [0]만 본다 — 실측 len=1. 복수가 실측되면 그때 합산을 설계할 것.
function invoiceBlock(d: any): any {
  const b = Array.isArray(d && d.Invoice) ? d.Invoice[0] : (d && d.Invoice);
  return b || null;
}

// ── PO 상세 ─────────────────────────────────────────────────
// 기대치 = 인보이스 기준 (2026-08-05 전환 — 규칙 20 개정).
// 공장이 실제로 보내는 것은 authorize 된 인보이스 라인이다. 오더 기준 expected 는 차이 라인마다
// 가짜 recv_short/recv_over 를 만들었다(실측 PO-01068: Order 92줄 vs Invoice 77줄 · ORS11021 360→264).
// ⚠️ 라인 집합은 Order.Lines 를 유지하고 **수량만** 인보이스로 덮어쓴다 — 라인을 제거하면 그 SKU
//    스캔이 off-PO(needs_approval)로 빠져 매니저 승인 전까지 풋어웨이·Apply 가 막힌다(receiver.html).
//    인보이스에 없는 오더 라인 = expected 0 (공장 백오더 — short 아님, received 0 이면 discrepancy 도 없음).
async function poDetail(id: string, type: string): Promise<any> {
  const pr = await poRaw(id, type, "poDetail " + id);
  const d = pr.data;
  // 폴백 발동 = 목록(purchaseList)의 Type 이 실제와 달랐다는 뜻 — PO 번호까지 붙여 한 번 더 남긴다
  // (poRaw 의 warn 은 fetch 전이라 PO 번호를 모른다). 화면이 조용히 열리면 아무도 이 사실을 모른다.
  if (pr.fellBack) {
    console.warn("[receiving poDetail] " + (d.OrderNumber || id) + ": type corrected '" +
      (type || "NULL") + "' -> '" + pr.resolvedType + "' via endpoint fallback" +
      " - receiver stores the corrected type on receipt creation");
  }
  const rawLines: any[] = d.Lines || (d.Order && d.Order.Lines) || [];
  const location = d.Location || (d.Order && d.Order.Location) || "";

  const inv = invoiceBlock(d);
  const invLines: any[] = (inv && inv.Lines) || [];
  const invQty: Record<string, number> = {};   // SKU(대문자) → 인보이스 수량 합 (같은 SKU 복수 라인 병합)
  const invSku: Record<string, string> = {};   // 원본 표기 보존 — 인보이스-only 라인 추가 시 그대로 쓴다
  let nonInventorySkipped = 0;
  for (const il of invLines) {
    // NonInventory=true 제외 (사용자 결정 2026-08-05): 재고로 받지 않는 항목(수수료·서비스류)이라
    // 기대치에 넣으면 영영 미충족으로 남는다. AdditionalCharges 는 별도 배열이라 애초에 안 읽힌다.
    if (il && il.NonInventory === true) { nonInventorySkipped++; continue; }
    const sku = String((il && il.SKU) || "").trim();
    if (!sku) continue;
    const k = sku.toUpperCase();
    invQty[k] = (invQty[k] || 0) + (Number(il.Quantity) || 0);
    if (!invSku[k]) invSku[k] = sku;
  }
  // ⚠️ 폴백 — 인보이스 블록이 없거나 쓸 라인이 없으면 **오더 기준 유지 + 경고**.
  //    조용히 expected 0 으로 만들면 전 라인이 초과(recv_over)로 잡힌다. expected_source 로 표식.
  const useInvoice = Object.keys(invQty).length > 0;
  if (!useInvoice) {
    console.warn("[receiving po] " + (d.OrderNumber || id) + ": no usable invoice lines" +
      (invLines.length ? " (all NonInventory)" : (inv ? " (Invoice.Lines empty)" : " (no Invoice block)")) +
      " - expected falls back to ORDER quantities (expected_source=order)");
  }
  if (nonInventorySkipped) {
    console.warn("[receiving po] " + (d.OrderNumber || id) + ": " + nonInventorySkipped +
      " NonInventory invoice line(s) excluded from expected");
  }

  const orderSkus = rawLines.map((l) => String(l.SKU || "").trim());
  const extraSkus = useInvoice
    ? Object.keys(invSku).filter((k) => !orderSkus.some((s2) => s2.toUpperCase() === k)).map((k) => invSku[k])
    : [];
  const sm = await snapMap([...orderSkus, ...extraSkus]);

  // 수량 덮어쓰기 — 같은 SKU 가 오더에 두 줄이면 첫 줄이 인보이스 수량 전부를 갖는다(합산 이중 계상 방지).
  const used = new Set<string>();
  const lines = rawLines.map((l) => {
    const k = String(l.SKU || "").trim().toUpperCase();
    if (!useInvoice) return normLine(l, sm[k]);
    let q = 0;
    if (k && invQty[k] !== undefined && !used.has(k)) { q = invQty[k]; used.add(k); }
    return normLine(l, sm[k], q);
  });
  // 인보이스에만 있고 오더에 없는 SKU — 정상 기대 라인으로 추가한다 (is_off_po 아님: 공장이 청구한 물건이다).
  if (useInvoice) {
    for (const k of Object.keys(invQty)) {
      if (used.has(k)) continue;
      lines.push(normLine({ SKU: invSku[k], Quantity: invQty[k] }, sm[k], invQty[k]));
    }
  }

  return {
    id: d.ID || id, po_number: d.OrderNumber || "", supplier: d.Supplier || "",
    status: d.Status || "", location, warehouse: normWarehouse(location), source: "po",
    // 프론트가 wms_receipts 에 그대로 저장한다 (2026-08-05 마이그레이션):
    // expected_source = 기대치 기준 표식('order'|'invoice') / cin7_type = Apply 게이트의 엔드포인트 선택 근거.
    // ⚠️ resolvedType — 폴백이 발동했으면 교정된 타입이다(receiver.html 이 receipt 생성 시 이 값을 저장:
    //    po.cin7_type || p.type. 저장 안 되면 매번 폴백이 발동한다).
    expected_source: useInvoice ? "invoice" : "order",
    cin7_type: pr.resolvedType,
    invoice_status: (inv && inv.Status) || null,
    line_count: lines.length, total_expected_base: lines.reduce((s2, l) => s2 + l.expected_base, 0), lines,
  };
}

// ── 트랜스퍼 목록: IN TRANSIT (입고 대기) ───────────────────
async function listTransfers(): Promise<any[]> {
  const data = await cin7Get("/stockTransferList?Page=1&Limit=100&Status=" + encodeURIComponent("IN TRANSIT"));
  return (data.StockTransferList || []).map((t: any) => ({
    id: t.TaskID, po_number: t.Number || "", supplier: (t.FromLocation || "") + " -> " + (t.ToLocation || ""),
    status: t.Status || "", warehouse: normWarehouse(t.ToLocation || ""), source: "transfer",
    order_date: t.DepartureDate || null,
  }));
}

// ── 트랜스퍼 상세 ───────────────────────────────────────────
async function transferDetail(id: string): Promise<any> {
  const d = await cin7Get("/stockTransfer?TaskID=" + encodeURIComponent(id));
  const rawLines: any[] = d.Lines || [];
  const sm = await snapMap(rawLines.map((l) => String(l.SKU || "").trim()));
  const lines = rawLines.map((l) => normLine(l, sm[String(l.SKU || "").trim().toUpperCase()]));
  return {
    id: d.TaskID || id, po_number: d.Number || "", supplier: (d.FromLocation || "") + " -> " + (d.ToLocation || ""),
    status: d.Status || "", location: d.ToLocation || "", warehouse: normWarehouse(d.ToLocation || ""),
    source: "transfer", to_location_raw: d.ToLocation || "", to_guid: d.To || null,
    line_count: lines.length, total_expected_base: lines.reduce((s2, l) => s2 + l.expected_base, 0), lines,
  };
}

// ── Apply to Cin7 — 계획 수립 (dry-run 공용) ─────────────────
// resetFails = true (?retry_failed=1, admin 'Retry failed bins'): 연속 실패 카운트를 리셋하고
// 격리(permanently_failed)된 bin 도 다시 시도 대상에 넣는다 — 사람이 Cin7 재고를 고친 뒤의 명시적 재시도 경로.
async function buildApplyPlan(receiptId: number, resetFails = false) {
  const rcpts = await sbSelect("wms_receipts?id=eq." + receiptId);
  if (!rcpts.length) throw new Error("receipt not found: " + receiptId);
  const rcpt = rcpts[0];
  const src0 = rcpt.source_type || "po";
  // ── ⚠️ 실패한 bin 이동의 재시도 경로 (2026-07-28) ─────────────────────────────
  // 부분 성공에서도 receipt PATCH(`applied_at`)까지 도달하도록 바뀌었으므로(applyCommit 참조),
  // `applied_at` 만으로 막으면 **실패한 bin 을 영영 다시 못 옮긴다**. 실패분은 `exported_base` 가
  // 안 찍혀 있어 아래 `pending_base` 계산에서 자동으로 재시도 대상이 된다.
  // 게이트는 두 겹: ① apply_note 에 `failed_moves(N)` N>0 **또는 `groups_remaining(N)` N>0**(청크 미완 —
  //   applied_at 이 이미 찍힌 부분실패 receipt 의 재시도 회차가 다시 청크 상한에 걸린 corner case 를 막지 않기 위함)
  //   **또는 `permanently_failed(N)` N>0**(격리된 bin 만 남아 done:true 로 닫힌 receipt 의 명시적 재시도 진입로)
  //   ② 실제로 옮길 그룹이 남아 있음(트랜스퍼 절 끝에서 확인).
  // 없으면 종전대로 "already applied" 로 거부한다(이중 반영 방지 — 규칙 21).
  // ⚠️ 세 표식(`failed_moves(N):`·`groups_remaining(N):`·`permanently_failed(N):`)은 admin.html 과 공유하는
  //   계약 포맷이다 — 한쪽만 바꾸지 말 것.
  const noteStr = String(rcpt.apply_note || "");
  const failedNote = /failed_moves\((\d+)\)/.exec(noteStr);
  const remainNote = /groups_remaining\((\d+)\)/.exec(noteStr);
  const permNote = /permanently_failed\((\d+)\)/.exec(noteStr);
  // 2026-07-31: PO 경로에도 청크·실패 격리를 이식하면서 `src0 === "transfer"` 제한을 풀었다 —
  // PO 도 부분 실패/청크 미완이면 같은 마커로 재개한다(실패 라인은 exported_base 미기록 → pending 재대상).
  const retryFailed =
    ((!!failedNote && Number(failedNote[1]) > 0) || (!!remainNote && Number(remainNote[1]) > 0) ||
     (!!permNote && Number(permNote[1]) > 0));
  // ── bin 별 연속 실패 카운트 — apply_note 의 `fail_counts:{"BIN":n}` 마커 (2026-07-31 v3) ──
  // 새 컬럼을 두지 않는 이유: ① wms_receipt_lines 에 쓸 만한 기존 컬럼이 없다 — exported_base 는
  //   "Cin7 에 실제 반영된 양"이라는 사실 기록이라 불가침(규칙 30-4)이고 putaway_* 는 작업자 화면이 소유한다.
  //   ② 실패 이력의 단위가 receipt×bin 이라 apply_note(receipt 단위)와 맞고, 계약 마커 패턴이 이미 있다.
  // ⚠️ `failed_moves(N):` 뒤의 JSON 은 900자에서 **잘려** 파싱이 깨질 수 있다 — bin 목록의 근거로 쓰지 말 것.
  //   (이 컴팩트 마커가 따로 존재하는 이유다.) 마커가 손상돼도 빈 카운트로 폴백 — 순서 최적화만 잃고 동작은 안전.
  // resetFails(명시적 재시도)면 카운트를 비워 시작한다 — 전 그룹이 다시 "미시도" 취급.
  let failCounts: Record<string, number> = {};
  if (!resetFails) {
    const fc = /fail_counts:(\{[^{}]*\})/.exec(noteStr);
    if (fc) { try { failCounts = JSON.parse(fc[1]) || {}; } catch { failCounts = {}; } }
  }
  if (rcpt.applied_at && !retryFailed) throw new Error(rcpt.po_number + " already applied at " + rcpt.applied_at);
  if (rcpt.status !== "completed") throw new Error("receipt must be completed first (current: " + rcpt.status + ")");
  const lines = await sbSelect("wms_receipt_lines?receipt_id=eq." + receiptId + "&order=id");

  const src = src0;

  const target: any[] = [], skipped: any[] = [];
  for (const l of lines) {
    const qty = Number(l.received_base || 0);
    if (qty <= 0) continue;
    if (l.needs_approval) { skipped.push({ sku: l.order_sku, qty, reason: "off-PO awaiting approval" }); continue; }
    if (src === "po" && l.is_off_po) { skipped.push({ sku: l.order_sku, qty, reason: "off-PO (not on this PO - handle separately)" }); continue; }
    if (!l.putaway_bin) { skipped.push({ sku: l.order_sku, qty, reason: "no bin assigned" }); continue; }
    target.push(l);
  }
  if (!target.length) throw new Error("nothing applicable (all lines skipped)");

  const sm = await snapMap(target.map((l) => l.order_sku));
  // 같은 (SKU + bin) 은 Cin7 stock received 에서 중복 불가 → 미리 수량 합산해 하나로 병합
  const merged: Record<string, any> = {};
  for (const l of target) {
    const key = String(l.order_sku).toUpperCase() + "|" + String(l.putaway_bin).toUpperCase();
    // parts = 이 병합 그룹을 구성한 실제 receipt 라인들. exported_base 체크포인트(트랜스퍼)를 쓰려면 id 가 필요하다.
    const part = { id: l.id, received_base: Number(l.received_base || 0), exported_base: Number(l.exported_base || 0) };
    if (merged[key]) { merged[key].received_base += Number(l.received_base); merged[key].parts.push(part); }
    else merged[key] = { order_sku: l.order_sku, base_sku: l.base_sku, putaway_bin: l.putaway_bin, received_base: Number(l.received_base), parts: [part] };
  }
  const mergedLines = Object.values(merged);
  const planLines = mergedLines.map((l: any) => {
    const s = sm[String(l.order_sku).toUpperCase()];
    const factor = (s && Number(s.factor) > 0) ? Number(s.factor) : 1;
    const units = Number(l.received_base) / factor;
    if (!Number.isInteger(units)) throw new Error(l.order_sku + ": received " + l.received_base + " base units not divisible by factor " + factor);
    return {
      order_sku: l.order_sku, base_sku: l.base_sku, qty_units: units, qty_base: Number(l.received_base), bin: l.putaway_bin,
      parts: l.parts, exported_already: l.parts.reduce((n: number, p: any) => n + Number(p.exported_base || 0), 0),
    };
  });

  // ── 리시빙 차이(초과/부족/오프-PO) 를 SKU 단위로 집계 → discrepancy 큐용 ──
  // 정책: Cin7 엔 received 그대로 쓰고, 기대치(expected)와의 차이는 매니저가 Cin7 에서 수동 adjustment.
  const bySku: Record<string, any> = {};
  for (const l of lines) {
    const rb = Number(l.received_base || 0);
    if (rb <= 0 && !l.is_off_po) continue;
    const k = String(l.order_sku).toUpperCase();
    if (!bySku[k]) bySku[k] = { order_sku: l.order_sku, received: 0, expected: 0, off_po: !!l.is_off_po, needs_approval: !!l.needs_approval };
    bySku[k].received += rb;
    bySku[k].expected += Number(l.expected_base || 0);
    if (l.is_off_po) bySku[k].off_po = true;
  }
  const discrepancies: any[] = [];
  for (const k in bySku) {
    const r = bySku[k];
    if (r.off_po) {
      if (r.received > 0 && !r.needs_approval) discrepancies.push({ sku: r.order_sku, ordered_base: 0, actual_base: r.received, reason: "recv_off_po" });
    } else if (r.received > r.expected) {
      discrepancies.push({ sku: r.order_sku, ordered_base: r.expected, actual_base: r.received, reason: "recv_over" });
    } else if (r.received < r.expected) {
      discrepancies.push({ sku: r.order_sku, ordered_base: r.expected, actual_base: r.received, reason: "recv_short" });
    }
  }

  if (src === "po") {
    // ── PO 청크·재개 준비 (2026-07-31 — 트랜스퍼 보호 장치 이식, 규칙 21·27 R10) ──
    // ⚠️ exported_base 의 의미가 트랜스퍼와 다르다: 트랜스퍼 = "목적지 bin 으로 옮긴 양" /
    //    **PO = "Cin7 stock received 문서(DRAFT)에 실은 양"** — authorize 여부와 무관한 "문서에 올라갔다" 기록.
    // ⚠️ 라인 단위 all-or-nothing: exported_already 가 qty_base 에 못 미치면(체크포인트 PATCH 일부 실패 잔재)
    //    **전량**을 pending 으로 되돌린다 — 부분 수량 재전송은 factor 로 안 나눠떨어질 수 있고, PO stock received 는
    //    같은 (SKU+bin) 재전송을 400 "Cannot add duplicate value" 로 거부하므로(실측, cin7-api 스킬) 전량 재전송이
    //    조용히 이중 계상되는 일은 없다 — 중복이면 시끄럽게 실패해 사람이 본다.
    for (const p of planLines as any[]) {
      p.move_base = Number(p.qty_base);   // markExported 재사용용 — PO 는 캡 없음(received 그대로)
      p.pending_base = Number(p.exported_already || 0) >= Number(p.qty_base) ? 0 : Number(p.qty_base);
    }
    const groups: Record<string, any[]> = {};
    (planLines as any[]).filter((p) => Number(p.pending_base) > 0).forEach((p) => { (groups[p.bin] = groups[p.bin] || []).push(p); });
    const bins = Object.keys(groups);
    const failsOf = (b: string) => Number(failCounts[String(b).toUpperCase()] || 0);
    const quarantinedBins = bins.filter((b) => failsOf(b) >= APPLY_QUARANTINE_FAILS);
    const binsActive = bins.filter((b) => failsOf(b) < APPLY_QUARANTINE_FAILS);
    const alreadyExported = (planLines as any[]).filter((p) => Number(p.pending_base) <= 0).length;
    // 재시도 게이트 ② (트랜스퍼와 동일) — 마커는 남았는데 실제로 실을 그룹이 없으면 재개할 이유가 없다.
    if (rcpt.applied_at && retryFailed && !bins.length) {
      throw new Error(rcpt.po_number + " already applied at " + rcpt.applied_at +
        " - nothing left to retry (every line is already on the Cin7 stock received document)");
    }
    return {
      receipt: rcpt, source: "po",
      plan: {
        action: "PO stock received" + (retryFailed ? (resetFails
            ? " (RETRY — fail history cleared, previously failed bins are attempted again)"
            : " (RESUME — untried groups go first, previously failed bins last)") : ""),
        retry: retryFailed, retry_reset: resetFails,
        steps: [
          "1) Check invoice is AUTHORISED (Invoice First)",
          "2) POST /purchase/stock - one DRAFT document per bin: " + binsActive.length + " bin group(s)" +
            (alreadyExported ? " · " + alreadyExported + " line(s) already on the document, skipped" : "") +
            " · untried groups go first, previously failed bins last" +
            (binsActive.length > APPLY_MAX_GROUPS
              ? " · processed up to " + APPLY_MAX_GROUPS + " group(s) or ~" + (APPLY_TIME_BUDGET_MS / 1000) +
                "s per round, whichever comes first — the admin screen repeats Apply automatically (Stop is safe between rounds)"
              : ""),
          ...(quarantinedBins.length
            ? ["2b) EXCLUDED — " + quarantinedBins.length + " bin(s) failed " + APPLY_QUARANTINE_FAILS +
               "+ consecutive rounds and need manual fixing: " + quarantinedBins.join(", ") +
               " — fix the cause, then use 'Retry failed bins' to include them"]
            : []),
          "3) Authorize ONCE, only on the round where EVERY bin group is on the document — " +
            "if anything is pending, failed or skipped, the document stays DRAFT " +
            "(authorize is one-shot on a Simple PO; never authorize a partial document)",
        ],
        lines: planLines,
        // 그룹 순서 = 미시도 먼저, 실패 이력(연속 실패 수 오름차순) 뒤로 — 트랜스퍼 v3 와 동일한 근거.
        // 순서는 시도 순서일 뿐: "무엇을 실을지"는 매 회차 DB 재조회(pending_base>0)가 정한다(이중 전송 없음).
        groups: bins.map((b) => ({ bin: b, prev_fails: failsOf(b), lines: groups[b] }))
          .sort((a, b) => a.prev_fails - b.prev_fails),
        fail_counts: failCounts, quarantined_bins: quarantinedBins, quarantine_fails: APPLY_QUARANTINE_FAILS,
        skipped, discrepancies,
        chunk_size: APPLY_MAX_GROUPS, time_budget_ms: APPLY_TIME_BUDGET_MS,
        progress: {
          lines_total: lines.length,
          lines_exported: lines.filter((l: any) => Number(l.exported_base || 0) > 0).length,
        },
      },
    };
  }
  const det = await transferDetail(rcpt.cin7_purchase_id);
  const trStatus = String(det.status || "").toUpperCase();
  // ⚠️ 재개 경로 (2026-07-28, TR-02935): 예전 검증은 "IN TRANSIT 이어야 함" 뿐이라, 원 TR 은 COMPLETED 됐는데
  //   bin 이동이 중간에 throw 한 receipt 이 **영구히 큐에 갇혔다**(applied_at 도 null 이라 Applied 배지도 없음).
  //   → COMPLETED 도 받아들이고 ①PUT 을 건너뛰어 ②bin 이동부터 재개한다. 어느 쪽인지는 plan.mode 로 노출.
  if (trStatus !== "IN TRANSIT" && trStatus !== "COMPLETED") {
    throw new Error("transfer is " + det.status + " (expected IN TRANSIT for a new apply, or COMPLETED to resume bin moves)");
  }
  // retryFailed 면 PUT 은 이미 나갔으므로 TR 은 COMPLETED 다 — 방어적으로 둘 중 하나만 참이어도 resume 으로 간다.
  const mode = (trStatus === "COMPLETED" || retryFailed) ? "resume" : "new";

  // ⚠️ 실측(2026-07-25): 완료 시 재고 착지 지점은 트랜스퍼 헤더 To 에 따라 두 가지.
  //   (a) To = 창고 GUID        → bin 없이 창고에 떠 있음 (TR-03259 형, Cin7 재고화면 BIN 칸 공백)
  //   (b) To = 특정 bin GUID    → 그 bin 에 전량 (예 EZ010101 임시 집결 — 실제 보관자리 아님)
  //   두 경우 모두 From = det.to_guid 로 꺼내면 Cin7 이 알아서 처리(실측 200).
  //   landingBin 은 (b)에서 "이미 제자리" 스킵 판단용. to_location_raw 예: "Asung - Edmonton: EZ010101"
  // ⚠️⚠️ trim + undefined 방어 필수: (a) 는 콜론이 없어 split(":")[1] 이 undefined 이고,
  //   앞 공백(": EZ010101" → " EZ010101")이 남으면 "이미 제자리" 판정이 어긋나 From==To 이동을 쏴서 400 이 난다.
  const landingRaw = String(det.to_location_raw || "").trim();
  const ci = landingRaw.indexOf(":");
  const landingBin = ci >= 0 ? landingRaw.slice(ci + 1).trim() : "";   // (a) 창고만이면 ""
  // ⚠️ 잔량의 **위치 표현이 (a)/(b) 로 다르다.** 매니저가 Cin7 에서 찾아 제거하는 지점이라 틀리면 못 찾는다.
  //   (b) → 집결 bin 이름 / (a) → 창고명 + " (no bin)". to_location_raw 원문을 쓰는 게 가장 안전.
  const landingLabel = landingBin || ((landingRaw || WH_NAME[rcpt.warehouse] || "the warehouse") + " (no bin)");

  // ── ⚠️⚠️ bin 이동 수량 = min(received_base, expected_base) 캡 (2026-07-28 — 안 하면 400) ──
  // 완료 후 착지 지점에 실제로 앉는 건 **보낸 수량(expected)** 이다 (Cin7 이 완료 PUT 의 수량 변경을 무시하므로).
  //   · 초과 라인 → expected 만큼만 옮긴다. 초과분은 Cin7 에 **존재하지 않으므로** 옮기려 하면 400.
  //   · 부족 라인 → received 만큼 옮기고 `expected - received` 는 착지 지점에 남는다. **의도된 동작**
  //     (남은 수량 = 매니저가 Cin7 에서 제거해야 할 양이고, 남아 있다는 것 자체가 "미정리" 신호).
  //   · off-transfer(트랜스퍼에 없던 SKU) → expected 0 이라 자동으로 캡 0 → bin 이동 제외, discrepancy(recv_off_po) 로만 남긴다.
  const expBySku: Record<string, number> = {};
  const skuLabel: Record<string, string> = {};
  for (const l of lines) {
    const k = String(l.order_sku).toUpperCase();
    expBySku[k] = (expBySku[k] || 0) + Number(l.expected_base || 0);
    if (!skuLabel[k]) skuLabel[k] = l.order_sku;
  }
  const budget: Record<string, number> = {};
  for (const k in expBySku) budget[k] = expBySku[k];
  const excludedFromMove: any[] = [];
  const movedBySku: Record<string, number> = {};
  for (const p of planLines as any[]) {
    const k = String(p.order_sku).toUpperCase();
    const left = Math.max(0, Number(budget[k] || 0));
    const move = Math.min(Number(p.qty_base), left);
    budget[k] = left - move;
    p.move_base = move;                                            // Cin7 에 실제로 쏘는 수량 (캡됨)
    p.pending_base = Math.max(0, move - Number(p.exported_already || 0));  // 재개 시 남은 몫
    movedBySku[k] = (movedBySku[k] || 0) + move;
    if (move < Number(p.qty_base)) {
      excludedFromMove.push({
        sku: p.order_sku, bin: p.bin, received: Number(p.qty_base), moved: move, not_moved: Number(p.qty_base) - move,
        reason: expBySku[k] > 0 ? "over-received — the excess does not exist in Cin7" : "off-transfer SKU — Cin7 holds none of it",
      });
    }
  }
  // 착지 지점에 남는 잔량 = 보낸 수량 − 실제로 옮긴 수량 (부족 라인 + bin 없어 스킵된 라인 + 아예 못 받은 라인)
  const leftoverAtLanding: any[] = [];
  for (const k in expBySku) {
    const left = Number(expBySku[k]) - Number(movedBySku[k] || 0);
    if (left > 0) leftoverAtLanding.push({ sku: skuLabel[k], qty: left, where: landingLabel });
  }

  // pending_base 가 남은 라인만 이동 대상 (exported_base 가 이미 찬 라인은 재Apply 때 건너뛴다)
  const groups: Record<string, any[]> = {};
  (planLines as any[]).filter((p) => Number(p.pending_base) > 0).forEach((p) => { (groups[p.bin] = groups[p.bin] || []).push(p); });
  const moves = Object.keys(groups).filter((b) => !landingBin || b.toUpperCase() !== landingBin.toUpperCase());
  const alreadyExported = (planLines as any[]).filter((p) => Number(p.move_base) > 0 && Number(p.pending_base) <= 0).length;
  // ── 실패 이력 분류 (v3) — 정렬·격리의 근거. resetFails 면 failCounts 가 비어 전부 "미시도" 가 된다 ──
  const failsOf = (b: string) => Number(failCounts[String(b).toUpperCase()] || 0);
  const quarantinedBins = moves.filter((b) => failsOf(b) >= APPLY_QUARANTINE_FAILS);   // 자동 재시도 격리 대상
  const movesActive = moves.filter((b) => failsOf(b) < APPLY_QUARANTINE_FAILS);        // 이번 회차 실제 시도 대상

  // 재시도 게이트 ② — `failed_moves` 는 남아 있는데 실제로 옮길 게 없으면(전부 exported 됐거나 착지 bin 뿐)
  // 재개할 이유가 없다 → 종전 "already applied" 거부로 되돌린다.
  if (rcpt.applied_at && retryFailed && !moves.length) {
    throw new Error(rcpt.po_number + " already applied at " + rcpt.applied_at +
      " - the previously failed bin move(s) have nothing left to retry (all remaining quantity is already exported)");
  }

  return {
    receipt: rcpt, source: "transfer",
    plan: {
      action: "Transfer completion + bin placement" +
        (retryFailed ? (resetFails
            ? " (RETRY — fail history cleared, previously failed bins are attempted again)"
            : " (RESUME — untried groups go first, previously failed bins last)")
          : mode === "resume" ? " (RESUME — transfer already COMPLETED)" : ""),
      mode, retry: retryFailed, retry_reset: resetFails,
      steps: [
        mode === "resume"
          ? "1) SKIP — " + det.po_number + " is already COMPLETED in Cin7 (resuming bin moves only)"
          : "1) PUT " + det.po_number + " -> COMPLETED with the ORIGINAL sent quantities (Cin7 ignores quantity edits) — stock lands in " + landingLabel,
        "2) " + movesActive.length + " bin move(s), quantity capped at the sent qty (" + (movesActive.join(", ") || "none") + ")" +
          (landingBin && moves.length < Object.keys(groups).length ? " · already-in-place groups skipped" : "") +
          (alreadyExported ? " · " + alreadyExported + " line(s) already exported, skipped" : "") +
          " · untried groups go first, previously failed bins last" +
          (movesActive.length > APPLY_MAX_GROUPS
            ? " · processed up to " + APPLY_MAX_GROUPS + " group(s) or ~" + (APPLY_TIME_BUDGET_MS / 1000) +
              "s per round, whichever comes first — the admin screen repeats Apply automatically and shows progress (Stop is safe between rounds)"
            : ""),
        ...(quarantinedBins.length
          ? ["2b) EXCLUDED — " + quarantinedBins.length + " bin(s) failed " + APPLY_QUARANTINE_FAILS +
             "+ consecutive rounds and need manual fixing in Cin7: " + quarantinedBins.join(", ") +
             " — fix the stock, then use 'Retry failed bins' to include them"]
          : []),
        "3) " + leftoverAtLanding.length + " leftover line(s) stay in " + landingLabel +
          " — remove them in Cin7 with a manual stock adjustment (see the discrepancy queue)",
      ],
      transfer: {
        number: det.po_number, status: det.status, landing_bin: landingBin || null,
        landing_label: landingLabel, to_location_raw: landingRaw, to_guid: det.to_guid,
      },
      // ⚠️ 그룹 순서 = **미시도 먼저, 실패 이력(연속 실패 수 오름차순) 뒤로** (v3 핵심 — TR-03144 에서 실패 그룹이
      //   앞자리를 차지해 매 회차 20초를 소진, 46개 미처리 그룹이 영구히 진행되지 못했다). 안정 정렬이라
      //   같은 카운트끼리는 원래 순서 유지. 격리(3회+) bin 은 자연히 맨 뒤 — applyCommit 이 카운트로 제외한다.
      //   순서 변경은 이중 이동과 무관: "무엇을 옮길지"는 매 회차 DB 재조회(pending_base>0)가 정하고,
      //   성공 그룹만 exported_base 체크포인트가 찍혀 다음 회차에서 빠진다 — 순서는 시도 순서일 뿐이다.
      lines: planLines,
      groups: Object.keys(groups)
        .map((b) => ({ bin: b, prev_fails: failsOf(b), lines: groups[b] }))
        .sort((a, b) => a.prev_fails - b.prev_fails),
      fail_counts: failCounts, quarantined_bins: quarantinedBins, quarantine_fails: APPLY_QUARANTINE_FAILS,
      leftover_at_landing: leftoverAtLanding, excluded_from_move: excludedFromMove,
      skipped, discrepancies,
      // 청크 진행률 소스 — admin 은 캡 규칙을 JS 로 재계산하지 않고 이 값(+commit 응답 필드)을 그대로 표시한다.
      chunk_size: APPLY_MAX_GROUPS, time_budget_ms: APPLY_TIME_BUDGET_MS,
      progress: {
        lines_total: lines.length,
        lines_exported: lines.filter((l: any) => Number(l.exported_base || 0) > 0).length,
      },
    },
  };
}

// ── Apply to Cin7 — 실행 (commit) ───────────────────────────
// t0 = 요청 시작 시각(Deno.serve 핸들러 진입 직후) — APPLY_TIME_BUDGET_MS 의 기준점.
async function applyCommit(planWrap: any, appliedBy: string, t0: number) {
  const rcpt = planWrap.receipt, source = planWrap.source, plan = planWrap.plan;
  const whName = WH_NAME[rcpt.warehouse] || WH_NAME.toronto;
  const log: string[] = [];
  // bin GUID 를 못 찾은 라인 — 전체를 중단시키지 않고 여기 모아 응답·apply_note 로 노출한다 (TR-02935 교훈).
  const skippedBins: { sku: string; bin: string; reason: string }[] = [];
  // Cin7 이 거부한 bin 그룹(트랜스퍼 = bin 이동 / PO = stock received POST) — 수집만 하고 다음 그룹을 계속 진행한다.
  const failedMoves: { bin: string; skus: string[]; qty: number; http_status: number | null; cin7_error: string; fails: number }[] = [];
  // 연속 실패 카운트(bin 대문자 → n) — plan.fail_counts(직전 회차 apply_note 마커)에서 시작해 이번 회차 결과로 갱신,
  // 회차 끝에 fail_counts 마커로 되쓴다. 성공 = 삭제(연속 리셋) / 실패(429 제외) = +1 / 미시도 = 그대로 이월.
  const failCounts: Record<string, number> = Object.assign({}, (plan.fail_counts || {}) as Record<string, number>);
  // 연속 APPLY_QUARANTINE_FAILS 회 이상 실패해 이번 회차 시도에서 제외한 그룹 — 자동 재시도 격리(⚠️ 영구 제외 아님,
  // 'Retry failed bins'(retry_failed=1)가 카운트를 리셋해 다시 시도한다).
  const permanentlyFailed: { bin: string; skus: string[]; qty: number; fails: number }[] = [];
  let failSpentMs = 0;      // 이번 회차에 실패 이력 그룹 시도에 쓴 시간 합 (APPLY_FAIL_BUDGET_MS 상한)
  let movedBins = 0;        // 실제로 성공한 bin 그룹 수 (admin 알림의 "N moved / M failed")
  // 목적지 되읽기로 "이미 도착" 이 확인돼 exported_base 만 기록한 receipt 라인 수 (checkpoint repair — R10 측정용).
  // 청크 v3(회차 완주 보장) 이후에도 이 값이 계속 나오면 타임아웃 외의 다른 원인이 있다는 신호다.
  let checkpointRepaired = 0;
  // PO 전용 — 이번 회차의 authorize 결과: true=성공 / false=시도했으나 실패(WARN·DRAFT 유지) / null=시도 안 함
  // (미처리·실패·격리·스킵이 남아 보류했거나, 트랜스퍼 경로). ⚠️ authorize 는 Simple PO 에서 1회뿐이라
  // **모든 bin 그룹이 문서에 실린 회차에만, 회차당 한 번만** 시도한다 — 청크/실패가 남은 회차는 DRAFT 로 둔다.
  let authorized: boolean | null = null;
  // ── 청크 카운터 (APPLY_MAX_GROUPS — 규칙 30-2 해소) ──
  let groupsAttempted = 0;  // 이번 회차에 Cin7 POST 를 시도한 그룹 수(성공+실패) — 상한 판정 기준
  let groupsRemaining = 0;  // 상한/시간 예산/429 로 이번 회차에 손대지 않은 그룹 수 — done:false 판정 기준
  let linesMovedNew = 0;    // 이번 회차에 exported_base 가 0 → 양수 로 바뀐 receipt 라인 수 (진행률용)
  let rateLimited = false;  // 429 백오프 재시도(상한 2회)까지 소진 — 회차 조기 종료, 잔여는 다음 회차
  // 이번 회차를 끊은 가드 — apply_note·응답에 남긴다(다음에 상한을 조정할 때 어느 쪽이 걸렸는지가 근거).
  let stoppedBy: "groups" | "time" | "fail_budget" | null = null;

  // ⚠️ apply_note 는 이번 실행 로그로 **덮어써진다** → 재시도 실행임을 note 스스로 밝히게 한다
  //    (직전 부분 성공에서 이미 옮긴 그룹은 pending_base=0 이라 plan.groups 에 아예 없어 로그에 안 남는다).
  if (plan.retry) {
    log.push("RETRY of a partial apply from " + (rcpt.applied_at || "?") +
      " - re-attempting only the bin group(s) that failed then; groups already exported are skipped");
  }

  // ── ⓪ 리시빙 차이 → discrepancy 큐 (⚠️⚠️ Cin7 을 건드리기 **전에** 기록한다) ──
  // ⚠️ 2026-07-28 순서 역전: 예전엔 applyCommit **맨 마지막**이라 bin 이동이 throw 하면 차이 기록이 통째로 유실됐다
  //   (TR-02935 실사고 — 원 TR 은 COMPLETED 됐는데 discrepancy 도 applied_at 도 안 남아 보정 근거가 사라졌다).
  // ⚠️ 새 정책에서 이 큐는 **유일한 보정 지시서**다. 특히 트랜스퍼는 Cin7 이 완료 수량 변경을 무시하므로
  //   (아래 실측 주석) 매니저의 수동 stock adjustment 가 유일한 정정 경로다.
  // ⚠️ 그래서 여기서만 기존 방침("실패해도 Apply 성공 = WARN")을 **의도적으로 뒤집는다**:
  //   기록 실패 = Apply 중단. 기록 없이 재고를 옮기면 차이를 되찾을 방법이 없다.
  // on_conflict=receipt_id,sku + ignore-duplicates 라 재실행은 안전(중복 안 쌓임).
  const disc = (plan.discrepancies || []) as any[];
  if (disc.length) {
    const rows = disc.map((d) => ({
      order_id: null, order_number: rcpt.po_number, po_number: rcpt.po_number,
      receipt_id: rcpt.id, source: "receiving",
      sku: d.sku, ordered_base: d.ordered_base, actual_base: d.actual_base,
      reason: d.reason, responsible: rcpt.received_by || null, cin7_corrected: false,
    }));
    try {
      await sb("POST", "wms_discrepancies?on_conflict=receipt_id,sku", rows, "resolution=ignore-duplicates,return=minimal");
    } catch (e) {
      throw new Error("discrepancy log failed - NOTHING was written to Cin7 (the queue is the only correction record, " +
        "so we stop instead of moving stock without it). Detail: " + String((e as Error).message).slice(0, 200));
    }
    log.push(disc.length + " discrepancy(ies) logged for manager review (before any Cin7 write)");
  }

  if (source === "po") {
    // ── Invoice First 게이트 — PO 상세 응답의 Invoice 블록으로 확인 (2026-08-05 전환) ──
    // ⚠️ 종전 GET /purchase/invoice 는 Advanced PO 에서 400 "deprecated and does not support
    //    Advanced Purchase" (실측) — Advanced receipt 의 Apply 가 "Invoice not authorised" 오진
    //    메시지로 막혔다. 상세 응답의 invoiceBlock() 은 Simple/Advanced 공통. 호출 수는 동일(1 GET 대체).
    // ⚠️ 판정은 fail-closed (2026-08-06 사용자 결정 — 종전 fail-open 을 정정): 되돌릴 수 없는
    //    Cin7 쓰기 직전의 마지막 관문이므로 "확인 자체 실패"도 차단한다. 전환 조건이었던 관찰은
    //    끝났다 — 엔드포인트 폴백 배포(v30)로 400 경로가 닫혔고 그 코드로 PO-01076 Apply 성공.
    //    실질 적용 구간은 좁다(목록 필터가 미승인 PO 를 이미 제외 — 남는 것은 목록↔Apply 시간차에
    //    Cin7 쪽 인보이스가 변한 경우와 상태를 못 읽는 경우). 메시지는 아래 3분기 + 조회 실패 1분기
    //    — 첫 문장이 잘못된 처방을 주지 않게 유지할 것(폴백 작업에서 겪은 오진 메시지 문제).
    // cin7_type 없는 구형 receipt 은 /purchase 로 먼저 조회하되, 400 이면 poRaw 가 /advanced-purchase 로
    // 1회 폴백한다(⚠️ 현장 미검증 — 구형 NULL receipt 이 Advanced PO 인 경우가 위험 구간이었다).
    // 폴백 성공 시 cin7_type 을 교정 PATCH — 다음 Apply 부터 바로 맞는 엔드포인트를 친다.
    let det0: any;
    try {
      const pr = await poRaw(rcpt.cin7_purchase_id, rcpt.cin7_type || "",
        "apply receipt " + rcpt.id + " " + rcpt.po_number);
      if (pr.fellBack) {
        // ⚠️ 교정 기록 실패가 Apply 를 막으면 안 된다 — 부가 정보다(못 고쳐도 다음 회차에 폴백이 또 잡는다).
        try {
          await sb("PATCH", "wms_receipts?id=eq." + rcpt.id, { cin7_type: pr.resolvedType }, "return=minimal");
          log.push("cin7_type corrected to '" + pr.resolvedType + "' (endpoint fallback - was '" +
            (rcpt.cin7_type || "NULL") + "')");
        } catch (e2) {
          console.warn("[receiving apply] receipt " + rcpt.id + " " + rcpt.po_number +
            ": cin7_type correction PATCH failed (non-blocking): " + String((e2 as Error).message).slice(0, 200));
          log.push("WARN cin7_type correction failed (non-blocking) - fallback will fire again next apply");
        }
      }
      det0 = pr.data;
    } catch (e) {
      // ⚠️ 메시지 분리 (2026-08-05): 여기 도달 = PO 상세 **조회 자체**가 실패(폴백까지 포함) — 인보이스
      //    미승인이 원인이 아닐 수 있다. 종전엔 이 경우도 "Invoice not authorised - authorize ..." 로 나가
      //    잘못된 처방을 줬다. 차단 동작 자체는 종전과 동일하다(조회 실패 = Apply 중단, fail-open 아님).
      throw new Error("Invoice check failed - could not read the PO detail from Cin7, so the invoice status is unknown" +
        " (this may NOT be an authorisation problem). Detail: " + String((e as Error).message));
    }
    // fail-closed 3분기 — 통과 목록은 목록 필터와 같은 상수(PO_INVOICE_OK) 하나를 공유한다:
    // 두 곳이 갈라지면 "목록은 통과시키는데 게이트는 막는" 가장 찾기 어려운 종류의 불일치가 된다.
    const inv0 = invoiceBlock(det0);
    if (!inv0) {
      // ① 인보이스 블록 없음 = 이 PO 에 인보이스가 없다 (목록 통과 후 Cin7 쪽에서 void/삭제됐을 수 있다)
      throw new Error("No invoice on this PO - create and authorize the invoice in Cin7 first (Invoice First)." +
        " Detail: the PO detail response has no Invoice block (type '" + (rcpt.cin7_type || "unknown") +
        "', PO " + rcpt.po_number + ") - if Cin7 shows an invoice, report this as a data issue");
    }
    const st0v = String(inv0.Status || "").trim().toUpperCase();  // trim: 목록 필터와 동일 정규화
    if (!st0v) {
      // ② 블록은 있는데 Status 를 못 읽음 — 승인 문제가 아닐 수 있으니 처방을 주지 않는다
      throw new Error("Invoice status could not be read - Apply is blocked until it can be verified" +
        " (this may NOT be an authorisation problem). Detail: Invoice block exists but Status is " +
        JSON.stringify(inv0.Status ?? null) + " (type '" + (rcpt.cin7_type || "unknown") +
        "', PO " + rcpt.po_number + ")");
    }
    if (!PO_INVOICE_OK.has(st0v)) {
      // ③ 미승인 — 실제 상태값을 보여주고 Invoice First 처방
      throw new Error("Invoice not authorised - authorize the invoice in Cin7 first (Invoice First). Detail: invoice status is " + st0v);
    }
    log.push("invoice check: " + st0v);
    const now = new Date().toISOString().slice(0, 10) + "T00:00:00Z";  // 실측 성공 형식
    // ── bin 그룹 루프 (2026-07-31 — 트랜스퍼 보호 장치 이식: 청크 이중 가드·실패 수집·격리·체크포인트) ──
    // ⚠️ Cin7 stock received 는 한 문서(POST)에 bin 1개만(실측: 섞으면 400 'Lines is invalid') — 그대로.
    //    plan.groups 는 buildApplyPlan 이 pending 라인만 모아 "미시도 먼저, 실패 이력 뒤로" 정렬해 놓았다.
    // ⚠️ 예전의 "POST 하나 실패 = 전체 throw" 는 제거했다 — 청크 도입 후에는 이전 회차의 DRAFT 가 이미 Cin7 에
    //    있을 수 있어, throw 하면 기록(apply_note)이 끊기고 재개 근거가 사라진다(규칙 27 R10·R12 트랜스퍼와 동일).
    for (const g of (plan.groups || []) as any[]) {
      const postLines = g.lines.filter((p: any) => Number(p.pending_base) > 0);
      if (!postLines.length) { log.push("bin " + g.bin + ": already on the document - skip"); continue; }
      const binKey = String(g.bin).toUpperCase();
      const prevFails = Number(failCounts[binKey] || 0);
      // 격리 (트랜스퍼 v3 와 동일) — groups_remaining 에 세지 않으므로 격리만 남으면 done:true 로 닫힌다.
      // ⚠️ 영구 제외가 아니다 — 'Retry failed bins'(retry_failed=1)가 카운트를 리셋해 다시 시도한다.
      if (prevFails >= APPLY_QUARANTINE_FAILS) {
        permanentlyFailed.push({
          bin: g.bin, skus: postLines.map((p: any) => String(p.order_sku)),
          qty: postLines.reduce((n: number, p: any) => n + Math.round(Number(p.pending_base)), 0),
          fails: prevFails,
        });
        log.push("bin " + g.bin + ": QUARANTINED after " + prevFails + " consecutive failed round(s) - not auto-retried;" +
          " fix the cause and press 'Retry failed bins'");
        continue;
      }
      // 청크 이중 가드 — 공용 판정 chunkGuard(그룹 12 / 시간 20초 / 429 / 실패 6초, 트랜스퍼와 같은 상수·판정).
      // ⚠️ 반드시 Cin7 POST 앞 — 반쯤 쓴 문서를 만들지 않는다. 가드 도달 = 정상 종료(done:false 로 다음 회차).
      const guard = chunkGuard(groupsAttempted, rateLimited, t0, prevFails, failSpentMs);
      if (guard) {
        if (!stoppedBy && !rateLimited && guard !== "rate") stoppedBy = guard;
        groupsRemaining++; continue;
      }
      // bin GUID — 못 찾으면 그 그룹만 스킵(수량·시간 상한에 안 센다). 스킵이 있으면 아래에서 authorize 를 보류한다.
      const rg = await tryBinGuid(whName, g.bin);
      if (!rg.guid) {
        postLines.forEach((p: any) => skippedBins.push({ sku: p.order_sku, bin: g.bin, reason: rg.reason }));
        log.push("WARN bin " + g.bin + " skipped (" + postLines.length + " line(s)): " + rg.reason);
        continue;
      }
      const bodyLines = postLines.map((p: any) => ({
        Date: now, SKU: p.order_sku, Quantity: Math.round(Number(p.qty_units)),
        LocationID: rg.guid, Received: false,
      }));
      groupsAttempted++;   // 성공·실패 무관 — POST 시도 자체가 시간 예산을 먹는다(트랜스퍼와 동일)
      const tAttempt = Date.now();
      try {
        await cin7("POST", "/purchase/stock", { TaskID: rcpt.cin7_purchase_id, Status: "DRAFT", Lines: bodyLines });
      } catch (e) {
        if (prevFails > 0) failSpentMs += Date.now() - tAttempt;
        const info = cin7ErrInfo(e);
        // 429 는 실패가 아니라 "이번 회차는 여기까지" — failed_moves·실패 카운트에 넣지 않는다(트랜스퍼와 동일).
        if (info.http_status === 429) {
          rateLimited = true; groupsRemaining++;
          log.push("Cin7 rate limit (429) persisted after backoff retries - ending this round early; bin " +
            g.bin + " and the remaining group(s) will be retried next round");
          continue;
        }
        // ⚠️ 목적지 되읽기 회복(checkpoint repair)은 PO 에 이식하지 않는다 — PO 는 "bin 이동"이 아니라
        //    "입고 문서 작성"이라 되읽기의 의미가 다르다(백로그). 다만 그 잔여물(POST 성공 후 체크포인트 누락)의
        //    재전송은 400 "Cannot add duplicate value" 로 시끄럽게 거부되므로(실측) 조용한 이중 계상은 없다 —
        //    이 에러가 보이면 그 라인은 이미 DRAFT 에 있다는 뜻: Cin7 화면에서 확인 후 거기서 마무리한다.
        failCounts[binKey] = prevFails + 1;
        failedMoves.push({
          bin: g.bin,
          skus: postLines.map((p: any) => String(p.order_sku)),
          qty: postLines.reduce((n: number, p: any) => n + Math.round(Number(p.pending_base)), 0),
          http_status: info.http_status, cin7_error: info.cin7_error, fails: prevFails + 1,
        });
        log.push("WARN stock received POST -> bin " + g.bin + " FAILED (HTTP " + (info.http_status || "?") + "): " +
          info.cin7_error + " - " + postLines.map((p: any) => p.order_sku + " x" + Math.round(Number(p.qty_units))).join(", ") +
          " not on the document" +
          (/cannot add duplicate value/i.test(info.cin7_error)
            ? " (duplicate = this line is ALREADY on the DRAFT from an earlier round that died before checkpointing - verify in Cin7 and finish there)"
            : "; fix the cause and Apply again to retry this bin only"));
        await sleep(400);
        continue;   // ⚠️ throw 금지 — 남은 그룹을 계속 싣고 receipt PATCH 까지 반드시 도달한다.
      }
      if (prevFails > 0) { failSpentMs += Date.now() - tAttempt; delete failCounts[binKey]; }  // 성공 — 연속 실패 리셋
      movedBins++;
      log.push("stock received DRAFT — bin " + g.bin + ": " + bodyLines.length + " line(s)");
      // ── exported_base 체크포인트 — ⚠️ PO 에서의 의미 = "Cin7 stock received 문서에 실은 양" ──
      // (트랜스퍼의 "목적지 bin 으로 옮긴 양"과 다르다.) 재개 시 이 라인들은 pending 에서 빠져 재전송되지 않는다.
      // PATCH 실패는 트랜스퍼와 같이 WARN 만 — 재전송돼도 Cin7 이 duplicate 400 으로 거부한다(위 주석).
      for (const p of postLines) linesMovedNew += await markExported(p, log);
      await sleep(400);   // PO stock received 콜 간격은 300~400ms (규칙 21 — 트랜스퍼의 150ms 와 다름, 그대로 유지)
    }
    // 예전 "하나도 해석 안 되면 throw" 유지 — 단 "이번 회차가 GUID 스킵 말고 아무것도 안 했고, 이전 회차 진행도
    // 없는" 경우에만. Cin7 에 아무것도 없으니 throw 로 receipt 을 깨끗하게 큐에 남기는 게 맞다(bin 고쳐 재Apply).
    // 진행이 있었다면 절대 throw 하지 않는다 — 기록(apply_note)이 끊기면 재개 근거가 사라진다.
    if (!groupsAttempted && !groupsRemaining && !permanentlyFailed.length && skippedBins.length &&
        Number((plan.progress || {}).lines_exported || 0) === 0) {
      throw new Error("no bin GUID could be resolved - nothing was written to Cin7. " +
        skippedBins.map((s) => s.bin + ": " + s.reason).join(" | "));
    }
    log.push("this round: " + movedBins + " bin document(s) posted" +
      (skippedBins.length ? " · " + skippedBins.length + " line(s) skipped (no bin GUID)" : ""));
    // ── ⚠️⚠️ authorize 게이트 (PO 고유 — 가장 중요) ──
    // authorize 는 Simple PO 에서 **한 번뿐**이고 되돌릴 수 없다. 일부 bin 이 빠진 채 authorize 하면 빠진 수량을
    // Cin7 에서 API 로 채울 방법이 사라진다 → **모든 bin 그룹이 문서에 실렸을 때만, 마지막 회차에서 한 번만** 시도한다.
    // (기존 "스킵된 라인이 있으면 DRAFT 유지" 방침을 청크 경계·실패·격리까지 확장한 것.)
    // ⚠️ 회차마다 authorize 를 시도하지 않는다 — 이 게이트가 그 보증이다(미처리/실패/격리/스킵이 하나라도 있으면 보류).
    const skippedBinCount = new Set(skippedBins.map((s) => String(s.bin).toUpperCase())).size;
    const draftPendingBins = groupsRemaining + failedMoves.length + permanentlyFailed.length + skippedBinCount;
    if (draftPendingBins === 0) {
      try {
        await cin7("POST", "/purchase/stock", { TaskID: rcpt.cin7_purchase_id, Status: "AUTHORISED", Lines: [] });
        authorized = true;
        log.push("stock received AUTHORISED");
      } catch (e) {
        // authorize 실패 시 기존 방침 그대로: DRAFT 유지 + WARN(사람이 Cin7 화면에서 authorize).
        // 잔여 엣지: 직전 회차가 authorize 후 receipt PATCH 전에 죽었으면 여기서 재시도가 400 이 난다 —
        // 그 경우 문서는 이미 AUTHORISED 이므로 Cin7 에서 상태만 확인하면 된다.
        authorized = false;
        log.push("WARN auto-authorize failed - the document may already be AUTHORISED (check Cin7); " +
          "if it is still DRAFT, authorize in Cin7 UI. (" + String((e as Error).message).slice(0, 200) + ")");
      }
    } else {
      log.push("Cin7 document left as DRAFT - " + draftPendingBins + " bin(s) pending (" +
        [groupsRemaining ? groupsRemaining + " not yet processed" : "",
         failedMoves.length ? failedMoves.length + " failed" : "",
         permanentlyFailed.length ? permanentlyFailed.length + " quarantined" : "",
         skippedBinCount ? skippedBinCount + " no bin GUID" : ""].filter(Boolean).join(", ") +
        ") - NOT authorised; authorize runs automatically, exactly once, on the round where every bin is on the document." +
        " Do NOT authorize the partial document in Cin7 (authorize is one-shot on a Simple PO).");
    }
  } else {
    const det = await cin7Get("/stockTransfer?TaskID=" + encodeURIComponent(rcpt.cin7_purchase_id));
    const now = new Date().toISOString().slice(0, 10) + "T00:00:00Z";
    const landing = plan.transfer.landing_bin;
    const landingLabel = plan.transfer.landing_label || landing || "the warehouse";

    // ── 1) 원 TR 을 **원본(보낸) 수량 그대로** COMPLETED ──
    // ⚠️⚠️ 실물 수량 덮어쓰기(recvBySku → TransferQuantity 교체)는 **제거했다** (2026-07-28 실측, TR-03267 신규 IN TRANSIT):
    //   Cin7 은 완료 PUT 의 `TransferQuantity` 변경을 **조용히 무시한다.** SENT 에 변경값이 정확히 실려 나가고
    //   PUT 200 이 떨어지지만 되읽으면 원본 그대로다:
    //     · AS93113  원본 2 → 요청 4 → 저장 2  ❌
    //     · AS92700  원본 4 → 요청 2 → 저장 4  ❌
    //   **증가·감소 양방향 모두 무시.** 코드 버그가 아니라 API 제약이다(추정 이유: 창고간 트랜스퍼는 발송 시점에
    //   재고가 in-transit 계정으로 넘어가므로, 거기 없는 수량을 완료로 받을 수 없다).
    // ⚠️ 스킬의 "트랜스퍼 수량 초과 완료 허용(2026-07-25)" 은 **틀린 기록**이었다 — HTTP 200 만 보고 저장값을
    //   되읽지 않았고, PO stock received 의 초과 허용(이쪽은 사실)과 혼동됐다. PO 경로는 그대로 둔다.
    // → 정책(사용자 결정 2026-07-28): 완료 수량 = 보낸 수량 확정 · 실물 차이는 위 ⓪ discrepancy 에 명시(필수)
    //   · 매니저가 Cin7 에서 수동 stock adjustment 로 정리.
    if (plan.mode === "resume") {
      log.push("transfer " + (plan.transfer.number || det.Number || "") +
        " is already COMPLETED in Cin7 - PUT skipped, resuming bin moves (checkpoint resume)");
    } else {
      await cin7("PUT", "/stockTransfer", {
        TaskID: det.TaskID, Status: "COMPLETED",
        From: det.From, To: det.To,
        CostDistributionType: det.CostDistributionType || "Cost",
        InTransitAccount: det.InTransitAccount || undefined,
        DepartureDate: det.DepartureDate || now, CompletionDate: now,
        Reference: det.Reference || "", Lines: det.Lines || [],   // ⚠️ 원본 그대로 — 수량 변경은 무시된다(위 주석)
        SkipOrder: true,
      });
      log.push("transfer " + det.Number + " COMPLETED with the SENT quantities (Cin7 ignores quantity edits) - landed in " + landingLabel);
    }

    // ── 2) 착지 지점 → 실제 bin 으로 이동 (수량은 min(received, expected) 로 캡됨 — buildApplyPlan 참조) ──
    // From = det.To (창고 GUID 면 bin 없는 재고, 집결 bin GUID 면 그 bin) — 두 경우 다 실측 200.
    const fromGuid = det.To;
    // ⚠️ 여기서는 **절대 throw 하지 않는다** — 위 PUT 으로 Cin7 TR 이 이미 COMPLETED(되돌릴 수 없음)다.
    //    GUID 못 찾은 bin 은 스킵하고 남은 bin 은 계속 옮긴 뒤, 아래 receipt PATCH 까지 반드시 도달한다.
    //    (TR-02935: 첫 bin 에서 throw → TR 만 COMPLETED 되고 applied_at 은 null, discrepancy 도 유실됐다.)
    for (const g of plan.groups) {
      if (landing && String(g.bin).toUpperCase() === String(landing).toUpperCase()) {
        log.push("bin " + g.bin + ": already in place (landing bin) - skip"); continue;
      }
      const moveLines = g.lines.filter((p: any) => Number(p.pending_base) > 0);
      if (!moveLines.length) { log.push("bin " + g.bin + ": already exported - skip"); continue; }
      const binKey = String(g.bin).toUpperCase();
      const prevFails = Number(failCounts[binKey] || 0);
      // ── 격리 (v3): 연속 실패 상한에 도달한 bin 은 이번 회차 시도에서 제외한다 ──
      // ⚠️ groups_remaining 에 세지 않는다 — 세면 done:false 로 남아 admin 자동 반복이 영원히 안 끝난다.
      //   격리만 남으면 done:true 로 정상 종료(applied_at 찍힘)하고 admin 이 "N bin(s) need manual fixing" +
      //   'Retry failed bins' 를 보여준다. 격리 판정은 청크 가드보다 앞 — 가드에 걸린 회차에도 분류는 완결된다.
      if (prevFails >= APPLY_QUARANTINE_FAILS) {
        permanentlyFailed.push({
          bin: g.bin, skus: moveLines.map((p: any) => String(p.base_sku)),
          qty: moveLines.reduce((n: number, p: any) => n + Math.round(Number(p.pending_base)), 0),
          fails: prevFails,
        });
        log.push("bin " + g.bin + ": QUARANTINED after " + prevFails + " consecutive failed round(s) - not auto-retried;" +
          " fix the stock in Cin7 and press 'Retry failed bins'");
        continue;
      }
      // ── 청크 이중 가드: 그룹 수 상한 / 시간 예산 / 429 / 실패 시간 상한(v3) — 공용 판정 chunkGuard ──
      // ⚠️ 판정은 Cin7 POST **앞**(그룹 시작 전)에서만 — 반쯤 옮긴 그룹을 만들지 않는다.
      // 가드에 걸린 뒤의 그룹은 **아무것도 하지 않고** 남은 개수만 센다. exported_base 가 안 찍혀 있으므로
      // 다음 회차의 buildApplyPlan 이 DB 재조회로 자동으로 다시 집는다(재시도 경로와 같은 메커니즘 → 이중 이동 없음).
      // 429 는 rate_limited 필드가 따로 밝히므로 stopped_by 에는 넣지 않는다(guard === "rate" 제외).
      // 실패 시간 상한: 정렬상 실패 이력 그룹은 맨 뒤이므로, 걸리면 뒤에 남은 그룹도 전부 실패 이력 → 다음 회차로.
      const guard = chunkGuard(groupsAttempted, rateLimited, t0, prevFails, failSpentMs);
      if (guard) {
        if (!stoppedBy && !rateLimited && guard !== "rate") stoppedBy = guard;
        groupsRemaining++; continue;
      }
      const rg = await tryBinGuid(whName, g.bin);
      if (!rg.guid) {
        g.lines.forEach((p: any) => skippedBins.push({ sku: p.base_sku || p.order_sku, bin: g.bin, reason: rg.reason }));
        log.push("WARN bin move -> " + g.bin + " SKIPPED (" + g.lines.length + " line(s)): " + rg.reason +
          " - stock stays in " + landingLabel);
        continue;
      }
      const mini = {
        Status: "COMPLETED", From: fromGuid, To: rg.guid,
        CostDistributionType: "Cost",
        DepartureDate: now, CompletionDate: now,
        Reference: "WMS putaway " + rcpt.po_number,
        Lines: moveLines.map((p: any) => ({ SKU: p.base_sku, TransferQuantity: Math.round(Number(p.pending_base)) })),
        SkipOrder: true,
      };
      // ── ⚠️⚠️ 그룹 실패는 **수집만 하고 다음 그룹으로 넘어간다** (2026-07-28, TR-02935 재개 Apply) ──
      // 설계 의도: Cin7 쓰기는 되돌릴 수 없으므로 **되돌릴 수 없는 구간에서는 절대 throw 하지 않는다**(규칙 27 R12 의
      //   "쓰기 뒤" 방향, 여기서는 그 원칙을 bin 이동 루프 안까지 밀어 넣은 것).
      // 실측 사고: 344 라인 중 AS97745 한 건이 400 "Available quantity … is 0.0000000000, cannot transfer 2" 를 내며
      //   **첫 그룹에서 전체 루프를 중단** → 나머지 143 개 bin 이동이 통째로 실행되지 않았다.
      // ⚠️ 이 400 은 버그가 아니라 **정상적으로 발생하는 운영 상황**이다: 리시빙 완료(13:54)와 Apply 사이의 시차 동안
      //   그 재고가 판매 픽킹 등으로 이미 움직일 수 있다. 즉 "한 건 실패"를 전제로 설계해야 한다.
      // 재시도: 실패 그룹은 `exported_base` 를 찍지 않으므로, 사람이 Cin7 에서 재고를 바로잡고 다시 Apply 하면
      //   **실패분만** 재시도된다(buildApplyPlan 의 retryFailed 게이트 + pending_base).
      // ⚠️ 자동 보정은 하지 않는다 — 재고 조정은 사람 판단(규칙 27 R13).
      groupsAttempted++;   // 성공·실패 무관 — Cin7 POST 시도 자체가 시간 예산을 먹는다(실패도 왕복 1회)
      const tAttempt = Date.now();   // 실패 이력 그룹의 시도 시간을 failSpentMs 에 적산 (APPLY_FAIL_BUDGET_MS)
      let res: any;
      try {
        res = await cin7("POST", "/stockTransfer", mini);
      } catch (e) {
        if (prevFails > 0) failSpentMs += Date.now() - tAttempt;
        const info = cin7ErrInfo(e);
        // ⚠️ 429 는 실패가 아니라 "이번 회차는 여기까지" 다 — cin7() 의 백오프 재시도(상한 2회)까지 소진된 상태이므로
        //    이 그룹을 포함한 잔여를 다음 회차로 넘긴다. **failed_moves 에 넣지 않는다**(넣으면 부분실패 표식·재시도
        //    게이트가 어긋난다 — 429 그룹은 exported_base 미기록이라 다음 회차에 자연히 재시도된다).
        if (info.http_status === 429) {
          rateLimited = true; groupsRemaining++;
          log.push("Cin7 rate limit (429) persisted after backoff retries - ending this round early; bin " +
            g.bin + " and the remaining group(s) will be retried next round");
          continue;
        }
        // ── 목적지 되읽기 → 완료 간주 (checkpoint repair, 2026-07-31 — TR-03144 실측) ──
        // "Available quantity … is 0" 는 두 가지다: ① 진짜 재고 이탈(판매 픽킹 등 — 사람이 Cin7 에서 고칠 일)
        // ② **이전 회차가 Cin7 POST 와 markExported PATCH 사이에서 죽은 잔여물** — Cin7 에는 이미 옮겨졌는데
        //    체크포인트만 빠져, 다음 회차가 "안 옮긴 것" 으로 재시도 → 재고 없음 400 → 3회 뒤 격리됐다.
        //    (TR-03144 실측: 격리 10 bin/25 라인 **전부** 목표 bin 에 정확히 도착해 있었다. 죽은 회차 수와
        //     격리 bin 수가 거의 일치 — 청크 v3 로 근본 해소, 이 경로는 잔여물 정리 + 드문 엣지 대응이다.)
        // ② 는 목적지 bin 을 되읽어(규칙 27 R11 — 근거는 200 이 아니라 되읽은 값) ① 과 구분할 수 있다.
        // ⚠️ 조회는 이 400 패턴에만 — "Lines is invalid" 류는 성격이 달라 조회가 무의미하고 시간만 쓴다.
        // ⚠️ 오판이 미이동보다 나쁘다(잘못 완료 처리하면 사람이 알 수 없게 된다): 판정은 SKU 단위 ·
        //    이 트랜스퍼가 옮기려던 수량(pending_base) **이상** 비교(기존 재고가 있던 bin 은 더 많을 수 있다) ·
        //    조회 실패/응답 잘림/수량 부족이면 실패로 남긴다. 그룹 내 일부 라인만 확인되면 그 라인만
        //    exported_base 를 기록하고 그룹은 실패로 남긴다(전 라인 확인 = 그룹 완료).
        // ⚠️ 회차 완주가 최우선 — 이 조회도 Cin7 왕복이므로 시간 예산(20초/실패 6초) 안에서만 하고,
        //    부족하면 건너뛴다(그 라인은 실패로 남아 다음 회차에 자연히 재시도된다).
        let remaining = moveLines;
        if (/available quantity .*? is 0(?:\.0+)?\s*,/i.test(info.cin7_error)) {
          const tVerify = Date.now();
          const still: any[] = [];
          for (const p of moveLines) {
            if (Date.now() - t0 > APPLY_TIME_BUDGET_MS ||
                (prevFails > 0 && failSpentMs + (Date.now() - tVerify) > APPLY_FAIL_BUDGET_MS)) {
              still.push(p); continue;   // 예산 소진 — 판정하지 않고 실패로 (다음 회차로)
            }
            const need = Math.round(Number(p.pending_base));
            const onHand = await binOnHand(rcpt.warehouse, g.bin, p.base_sku);
            if (onHand !== null && onHand >= need) {
              log.push("bin " + g.bin + ": " + p.base_sku + " x" + need + " already at " + g.bin + " (" + onHand +
                " on hand) - treated as done, checkpoint repaired");
              const n = await markExported(p, log);   // 사실 기록 — 재고는 실제로 그 bin 에 있다(되읽음 확인)
              linesMovedNew += n; checkpointRepaired += n;
            } else {
              still.push(p);
            }
            await sleep(150);
          }
          if (prevFails > 0) failSpentMs += Date.now() - tVerify;
          remaining = still;
        }
        if (!remaining.length) {
          // 그룹 전 라인이 이미 목적지에 있다 — 실패가 아니라 완료다. 연속 실패 카운트도 리셋한다.
          delete failCounts[binKey];
          log.push("bin " + g.bin + ": all line(s) already at destination - group treated as done (no failure recorded)");
          await sleep(150);
          continue;
        }
        // 연속 실패 +1 — APPLY_QUARANTINE_FAILS 에 도달하면 다음 회차부터 격리된다. 429 는 위에서 이미 빠졌다
        // (429 를 세면 rate limit 가 실패로 둔갑해 멀쩡한 bin 이 격리된다).
        // failed_moves 는 **미확인 라인(remaining)만** 싣는다 — 확인된 라인은 exported_base 가 찍혀
        // 다음 회차 pending 에서 빠지므로, 여기 실으면 admin 표시·재시도 수량이 실제보다 부풀려진다.
        failCounts[binKey] = prevFails + 1;
        failedMoves.push({
          bin: g.bin,
          skus: remaining.map((p: any) => String(p.base_sku)),
          qty: remaining.reduce((n: number, p: any) => n + Math.round(Number(p.pending_base)), 0),
          http_status: info.http_status, cin7_error: info.cin7_error, fails: prevFails + 1,
        });
        log.push("WARN bin move -> " + g.bin + " FAILED (HTTP " + (info.http_status || "?") + "): " + info.cin7_error +
          " - " + remaining.map((p: any) => p.base_sku + " x" + Math.round(Number(p.pending_base))).join(", ") +
          " stays in " + landingLabel + "; fix the stock in Cin7 and Apply again to retry this bin only");
        await sleep(150);
        continue;   // ⚠️ throw 금지 — 남은 그룹을 계속 옮기고 receipt PATCH 까지 반드시 도달한다.
      }
      if (prevFails > 0) { failSpentMs += Date.now() - tAttempt; delete failCounts[binKey]; }  // 성공 — 연속 실패 리셋
      movedBins++;
      log.push("bin move -> " + g.bin + ": " + (res.Number || "ok") + " (" +
        moveLines.map((p: any) => p.base_sku + " x" + Math.round(Number(p.pending_base)) +
          (Number(p.pending_base) < Number(p.qty_base) ? " capped from " + Number(p.qty_base) : "")).join(", ") + ")");
      // ── exported_base 체크포인트 (규칙 27 R10 완화) ──
      // 이 bin 은 Cin7 에서 이미 옮겨졌다 → 재Apply 때 다시 쏘지 않도록 라인에 기록한다.
      // ⚠️ 되돌릴 수 없는 Cin7 쓰기 **뒤**라 PATCH 실패에도 throw 하지 않는다(규칙 21). 대신 WARN 으로 크게 남긴다 —
      //    체크포인트가 빠지면 재Apply 시 같은 bin 을 한 번 더 옮겨 재고가 이중으로 움직인다.
      for (const p of moveLines) linesMovedNew += await markExported(p, log);
      await sleep(150);
    }

    // 잔량(부족분·bin 없음·off-transfer)이 착지 지점에 남는다 — 의도된 동작이고, 매니저가 제거할 지점이다.
    // ⚠️ 어디에 남는지가 (a)창고(no bin) / (b)집결 bin 으로 다르므로 landingLabel 을 그대로 실어 보낸다.
    const lo = (plan.leftover_at_landing || []) as any[];
    if (lo.length) {
      log.push("LEFTOVER stays in " + landingLabel + " (remove in Cin7 with a manual stock adjustment): " +
        lo.map((x) => x.sku + " x" + x.qty).join(", "));
    }
    const ex = (plan.excluded_from_move || []) as any[];
    if (ex.length) {
      log.push("not moved (Cin7 holds none of it): " +
        ex.map((x) => x.sku + " " + x.not_moved + " of " + x.received + " - " + x.reason).join(" | "));
    }
  }

  // 스킵된 라인은 apply_note 에도 구조화해 남긴다 — Review/History 에서 나중에 추적 가능해야 한다.
  if (skippedBins.length) log.push("skipped_bins: " + JSON.stringify(skippedBins).slice(0, 800));
  // ⚠️ `failed_moves(N)` 는 **표식이자 재시도 게이트**다 — buildApplyPlan 이 apply_note 에서 이 패턴을 찾아
  //   applied_at 이 있어도 재개를 허용하고, admin History 의 CIN7 열이 N 을 읽어 "⚠ Applied (N bins failed)" 로 표시한다.
  //   포맷(`failed_moves(<정수>):`)을 바꾸려면 EF 의 정규식과 admin.html 양쪽을 같이 고칠 것.
  if (failedMoves.length) {
    log.push("failed_moves(" + failedMoves.length + "): " + JSON.stringify(failedMoves).slice(0, 900));
    log.push("PARTIAL — " + movedBins + " bin group(s) " + (source === "po" ? "posted" : "moved") + ", " +
      failedMoves.length + " failed. Fix the " + (source === "po" ? "cause" : "stock in Cin7") +
      ", then Apply again: only the failed bins are retried.");
  }
  // ⚠️ `permanently_failed(N):` 도 계약 마커다 — buildApplyPlan 재시도 게이트 + admin.html 이 같은 정규식을 읽는다.
  //   격리는 이 회차에 시도되지 않아 failed_moves 에 안 실리므로, 여기 따로 남겨야 재시도 진입로가 유지된다.
  if (permanentlyFailed.length) {
    log.push("permanently_failed(" + permanentlyFailed.length + "): " + permanentlyFailed.map((f) => f.bin).join(", ") +
      " - " + permanentlyFailed.length + " bin(s) need manual fixing in Cin7 (each failed " + APPLY_QUARANTINE_FAILS +
      "+ consecutive rounds, excluded from auto-retry). Fix the stock in Cin7, then press 'Retry failed bins'.");
  }
  // 회복 건수 표시 — 측정용이지 계약 마커가 아니다(EF·admin 어느 쪽도 파싱하지 않는다). R10 이 실제로 얼마나
  // 발생하는지의 자료: 청크 v3(회차 완주 보장) 이후에도 계속 나오면 타임아웃 외의 다른 원인이 있다는 신호다.
  if (checkpointRepaired) {
    log.push("checkpoint_repaired: " + checkpointRepaired + " line(s) - the stock was already at its destination bin " +
      "(an earlier round likely died between the Cin7 POST and the exported_base PATCH); exported_base recorded, nothing moved");
  }
  // 연속 실패 카운트 이월 — 다음 회차의 buildApplyPlan 이 이 마커로 정렬(실패 뒤로)·격리(3회+)를 판정한다.
  if (Object.keys(failCounts).length) log.push("fail_counts:" + JSON.stringify(failCounts));

  // ── 청크 판정 + 진행률 (2026-07-31 · PO 도 청크를 돈다 — 2026-07-31 이식 후 양쪽 공통) ──
  const done = groupsRemaining === 0;
  const prog = (plan.progress || {}) as any;
  const linesTotal = Number(prog.lines_total || 0);
  const linesMoved = Number(prog.lines_exported || 0) + linesMovedNew;   // 누적 (이전 회차 + 이번 회차)
  {
    const verb = source === "po" ? "posted" : "moved";
    log.push((done ? "ALL GROUPS DONE" : "CHUNK") + " - " + movedBins + " group(s) " + verb + " this round" +
      (failedMoves.length ? ", " + failedMoves.length + " failed" : "") +
      (permanentlyFailed.length ? " · " + permanentlyFailed.length + " bin(s) quarantined (need manual fixing)" : "") +
      (linesTotal ? " · " + linesMoved + "/" + linesTotal + " lines exported" : "") +
      (rateLimited ? " · ended early on Cin7 rate limit (429)" : ""));
    if (!done) {
      // ⚠️ `groups_remaining(N):` 은 `failed_moves(N):` 처럼 **계약 포맷**이다 — buildApplyPlan 의 재개 게이트와
      //    admin.html(Continue apply 버튼·History 표시)이 같은 정규식을 읽는다. 한쪽만 바꾸지 말 것.
      // stopped_by 를 note 에도 남긴다 — 다음에 상한(그룹 수·시간)을 조정할 때 어느 가드가 걸렸는지가 근거다.
      log.push("groups_remaining(" + groupsRemaining + "): stopped_by=" +
        (stoppedBy || (rateLimited ? "rate_limit" : "?")) +
        " (caps: " + APPLY_MAX_GROUPS + " group(s) / " + (APPLY_TIME_BUDGET_MS / 1000) + "s per round)" +
        " - press Apply again (the admin screen auto-continues) to " + (source === "po" ? "post" : "move") + " the rest");
    }
  }

  // ── 회차 종료부 — **가장 값싼 마지막 동작**이어야 하고 절대 죽지 않는다 (2026-07-31) ──
  // ⚠️ 여기서 Cin7 호출·무거운 재조회 금지. lines_moved 도 DB 재조회 없이
  //    "회차 시작 시점 exported 합(plan.progress) + 이번 회차 markExported 수" 로 이미 계산돼 있다.
  // ⚠️ 실패가 있어도 여기까지 온다 — receipt 이 큐에 갇히고 discrepancy 만 남는 상태(TR-02935)를 만들지 않는다.
  // ⚠️ apply_note 는 **매 회차** 갱신한다(타임아웃으로 죽어 아무 기록도 없던 R14 의 반대 방향 보증).
  //    `applied_at` 은 **모든 그룹이 끝난 회차에만** 찍는다 — 남은 그룹이 있는 receipt 은 Apply 목록에 남아야 한다.
  const patch: any = { status: "completed", apply_note: log.join(" | ") };
  if (done) { patch.applied_at = new Date().toISOString(); patch.applied_by = appliedBy || null; }
  let noteSaved = true;
  try {
    await sb("PATCH", "wms_receipts?id=eq." + rcpt.id, patch);
  } catch (e) {
    // ⚠️ note 갱신 실패에도 응답은 반환한다(WARN 만) — 기록을 못 남기는 것보다 응답조차 못 주는 게 나쁘다.
    //    done:true 였다면 applied_at 도 안 찍힌 상태 — 다음 Apply 가 DB 재조회(pending_base=0)로 같은 상태에
    //    수렴하고 PATCH 만 다시 시도하므로 이중 이동은 없다.
    noteSaved = false;
    log.push("WARN receipt patch (apply_note" + (done ? "/applied_at" : "") + ") FAILED - returning the response anyway: " +
      String((e as Error).message).slice(0, 200));
  }

  return {
    log, skipped_bins: skippedBins, failed_moves: failedMoves, moved_bins: movedBins,
    done, groups_total: groupsAttempted + groupsRemaining, groups_moved: movedBins,
    groups_remaining: groupsRemaining, lines_moved: linesMoved, lines_total: linesTotal,
    rate_limited: rateLimited, stopped_by: stoppedBy, note_saved: noteSaved,
    // v3 — groups_tried: 이번 회차에 Cin7 POST 를 시도한 그룹 수(성공+실패). admin 무한루프 가드가
    //   "이동 0 && 시도 0"(429 벽 등)일 때만 멈추도록 이 값을 본다 — 시도가 있었다면 실패 카운트가 전진해
    //   격리(연속 3회)로 반드시 수렴하므로 반복을 계속해도 된다.
    groups_tried: groupsAttempted, permanently_failed: permanentlyFailed, fail_counts: failCounts,
    checkpoint_repaired: checkpointRepaired,
    // PO 전용 — authorize 결과 (true 성공 / false 시도 실패 / null 보류·해당 없음). null+done:true 인 PO 응답은
    // "문서가 DRAFT 로 남았다"는 뜻이다(admin 이 안내 문구에 쓴다).
    authorized,
  };
}

// ── exported_base 체크포인트: 이 planLine 이 Cin7 으로 옮겨진 수량을 구성 receipt 라인에 기록 ──
// planLine 은 (order_sku + putaway_bin) 병합체라 여러 라인으로 쪼개질 수 있다 → move_base 를 parts 순서대로
// 각 라인의 received_base 한도까지 채운다. PATCH 는 절대값이라 재실행해도 같은 상태로 수렴(idempotent).
// 반환값 = exported_base 가 0 → 양수 로 바뀐 라인 수 (청크 진행률 lines_moved 용).
async function markExported(p: any, log: string[]): Promise<number> {
  let rem = Number(p.move_base || 0);
  let newly = 0;
  for (const part of (p.parts || []) as any[]) {
    const take = Math.min(Number(part.received_base || 0), Math.max(0, rem));
    rem -= take;
    const before = Number(part.exported_base || 0);
    try {
      await sb("PATCH", "wms_receipt_lines?id=eq." + part.id, { exported_base: take }, "return=minimal");
      part.exported_base = take;
      if (take > 0 && before <= 0) newly++;
    } catch (e) {
      log.push("WARN exported_base checkpoint failed for line " + part.id + " (" + p.order_sku + " x" + take +
        ") - a re-apply could move this bin twice: " + String((e as Error).message).slice(0, 120));
    }
  }
  return newly;
}

// ── 엔트리 ──────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const json = (body: unknown, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
  try {
    const url = new URL(req.url);
    const action = url.searchParams.get("action") || "pos";
    if (action === "pos") {
      // pos 배열은 그대로, scanned/totals/truncated 는 최상위 진단 필드로만 추가 (receiver.html 은 pos 만 읽는다)
      return json({ ok: true, ...(await listOpenPOs((url.searchParams.get("search") || "").trim())) });
    }
    if (action === "po") {
      const id = url.searchParams.get("id") || "";
      if (!id) return json({ ok: false, error: "id required" }, 400);
      return json({ ok: true, po: await poDetail(id, url.searchParams.get("type") || "Simple Purchase") });
    }
    if (action === "bins") {
      // ⚠️ binGuid 와 **같은 소스(최상위 창고 행의 Bins[])** 를 쓴다 — 예전 child-location 수집 경로는
      //    /ref/location Limit 잘림에 똑같이 걸려 에드먼튼 bin 이 통째로 빠졌다(실측 2026-07-28, 위 binMap 주석 참조).
      const wh = normWarehouse(url.searchParams.get("warehouse") || "toronto");
      const m = await binMap(wh);
      const bins = [...m.values()].map((v) => ({ bin: v.name, id: v.id }));  // 정렬은 receiver.html 의 sortBins 가 한다
      return json({ ok: true, warehouse: wh, bins });
    }
    if (action === "transfers") {
      return json({ ok: true, transfers: await listTransfers() });
    }
    if (action === "transfer") {
      const id = url.searchParams.get("id") || "";
      if (!id) return json({ ok: false, error: "id required" }, 400);
      return json({ ok: true, po: await transferDetail(id) });
    }
    if (action === "apply") {
      // 시간 예산(APPLY_TIME_BUDGET_MS)의 기준점 — buildApplyPlan(DB·Cin7 조회)부터 회차 시간에 포함시킨다.
      const t0 = Date.now();
      const rid = Number(url.searchParams.get("receipt_id") || 0);
      if (!rid) return json({ ok: false, error: "receipt_id required" }, 400);
      // retry_failed=1 (admin 'Retry failed bins') — 연속 실패 카운트 리셋 + 격리 해제 (v3, dry-run·commit 공통).
      // admin 은 이 플래그를 **첫 commit 회차에만** 붙인다 — 자동 반복 회차마다 붙이면 격리에 영영 도달하지 못한다.
      const resetFails = url.searchParams.get("retry_failed") === "1";
      const planWrap = await buildApplyPlan(rid, resetFails);
      if (url.searchParams.get("commit") !== "1") {
        return json({ ok: true, dry_run: true, source: planWrap.source, plan: planWrap.plan });
      }
      const appliedBy = url.searchParams.get("by") || "";
      const res = await applyCommit(planWrap, appliedBy, t0);
      // skipped_bins = bin GUID 를 못 찾아 Cin7 에 못 쓴 라인. 사유는 log 의 WARN 줄에도 있다(admin 이 alert 로 띄움).
      // failed_moves = Cin7 이 거부한 bin 이동 그룹(대개 "Available quantity … is 0"). ok:true 지만 **부분 성공**이다 —
      //   admin 이 `failed_moves.length > 0` 으로 판정해 다르게 표시하고, 재Apply 하면 실패분만 재시도된다.
      // done:false = 청크 이중 가드(그룹 수 APPLY_MAX_GROUPS / 시간 APPLY_TIME_BUDGET_MS — stopped_by 가 어느 쪽인지)
      //   또는 429 로 이번 회차에 못 옮긴 그룹이 남았다 — admin 이 자동으로 재호출한다.
      //   lines_moved/lines_total 은 receipt 라인 기준 누적 진행률(2026-07-31 부터 PO·트랜스퍼 공통).
      // note_saved:false = 종료부의 receipt PATCH(apply_note/applied_at) 실패 — 응답은 그래도 반환한다.
      // permanently_failed = 연속 3회+ 실패로 이번 회차 시도에서 제외(격리)된 bin 그룹 — "N bin(s) need manual
      //   fixing in Cin7". done 판정에 안 들어가므로 격리만 남으면 done:true 로 닫힌다(재시도는 retry_failed=1).
      // groups_tried = 이번 회차 Cin7 POST 시도 수(성공+실패) — admin 무한루프 가드용.
      // checkpoint_repaired = "Available quantity … is 0" 실패 그룹을 목적지 되읽기로 확인해 완료로 간주한
      //   receipt 라인 수 (이미 도착 — exported_base 만 기록, 재고는 안 옮김). R10 발생 빈도의 측정 자료.
      // authorized (PO 전용) = 이번 회차 authorize 결과: true 성공 / false 시도 실패(DRAFT 유지, WARN) /
      //   null 보류(미처리·실패·격리·스킵이 남아 authorize 를 안 함 — 문서는 DRAFT) 또는 트랜스퍼.
      return json({
        ok: true, dry_run: false, source: planWrap.source, log: res.log, skipped_bins: res.skipped_bins,
        failed_moves: res.failed_moves, moved_bins: res.moved_bins,
        done: res.done, groups_total: res.groups_total, groups_moved: res.groups_moved,
        groups_remaining: res.groups_remaining, lines_moved: res.lines_moved, lines_total: res.lines_total,
        rate_limited: res.rate_limited, stopped_by: res.stopped_by, note_saved: res.note_saved,
        groups_tried: res.groups_tried, permanently_failed: res.permanently_failed, fail_counts: res.fail_counts,
        checkpoint_repaired: res.checkpoint_repaired, authorized: res.authorized,
      });
    }
    return json({ ok: false, error: "unknown action" }, 400);
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message || e) }, 500);
  }
});
