// ============================================================
// ASUNG WMS — 공용 Cin7 HTTP 헬퍼 (_shared)
// hello(폴링)·receiving·product-images·inv-snapshot 네 Edge Function 이 함께 import 한다.
// 예전엔 429 백오프가 receiving 에만 있고 hello 는 즉시 throw 라 갈라져 있었다
// (2026-08-04 실사고: saleList 429 로 폴링 회차가 통째로 죽어 뒤 페이지 오더 미유입).
// ⚠️ 이 파일을 바꾸면 네 함수를 모두 재배포해야 런타임이 일치한다:
//    supabase functions deploy hello && supabase functions deploy receiving \
//      && supabase functions deploy product-images && supabase functions deploy inv-snapshot
//    (각 함수는 배포 시점의 번들을 계속 쓴다 — 일부만 배포하면 조용히 갈라진다)
// ============================================================

export const CIN7_BASE = "https://inventory.dearsystems.com/ExternalApi/v2";

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

export function cin7Headers(): HeadersInit {
  return {
    "api-auth-accountid": Deno.env.get("CIN7_ACCOUNT_ID") ?? "",
    "api-auth-applicationkey": Deno.env.get("CIN7_APPLICATION_KEY") ?? "",
    "Content-Type": "application/json",
  };
}

export async function cin7(method: string, path: string, body?: unknown): Promise<any> {
  // ⚠️ 429 는 백오프(1.5s → 3s) 후 재시도한다(상한 2회). 소진되면 status=429 를 실어 throw —
  //    호출부가 429 를 구분해 "회차 조기 종료" 를 택할 수 있게 한다:
  //    · receiving: bin 이동 루프가 429 를 failed_moves 에 넣지 않고 회차를 끊는다 (rate_limited)
  //    · hello: saleList 페이지 순회가 throw 없이 조기 종료한다 (rate_limited + 끊긴 페이지 노출)
  for (let attempt = 0; ; attempt++) {
    const resp = await fetch(CIN7_BASE + path, {
      method, headers: cin7Headers(),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (resp.status === 429 && attempt < 2) { await sleep(1500 * (attempt + 1)); continue; }
    const text = await resp.text();
    if (!resp.ok) {
      // ⚠️ status/body 를 Error 에 실어 보낸다 — 호출부가 "계속 진행" 을 택할 때(bin 이동 루프) 사람이 읽을
      //    실패 사유(Cin7 `Exception` 문자열)를 구조화해 수집해야 한다. 메시지 문자열 파싱은 취약하다.
      const err: any = new Error("Cin7 " + method + " " + path.split("?")[0] + " -> " + resp.status + ": " + text.slice(0, 400) +
        (method !== "GET" && body !== undefined ? " | SENT: " + JSON.stringify(body).slice(0, 600) : ""));
      err.status = resp.status; err.body = text;
      throw err;
    }
    return text ? JSON.parse(text) : {};
  }
}
export const cin7Get = (path: string) => cin7("GET", path);

// Cin7 에러 바디에서 사람이 바로 원인을 아는 문장만 뽑는다.
// 실측 400 형태: {"ErrorCode":..,"Exception":"Available quantity for product (SKU: AS97745 …) is 0.0000000000, cannot transfer 2"}
// 배열로 오는 경우도 있어 둘 다 처리하고, JSON 이 아니면 원문을 자른다.
export function cin7ErrInfo(e: any): { http_status: number | null; cin7_error: string } {
  const status = Number(e && e.status) || null;
  const raw = String((e && e.body) || (e && e.message) || e || "");
  let msg = "";
  try {
    const j = JSON.parse(raw);
    const pick = (o: any) => String((o && (o.Exception || o.ExceptionMessage || o.Message || o.Error)) || "").trim();
    msg = Array.isArray(j) ? j.map(pick).filter(Boolean).join(" · ") : pick(j);
  } catch { /* JSON 아님 — 원문 폴백 */ }
  if (!msg) msg = raw;
  return { http_status: status, cin7_error: msg.slice(0, 300) };
}
