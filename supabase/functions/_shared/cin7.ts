// ============================================================
// ASUNG WMS — 공용 Cin7 HTTP 헬퍼 (_shared)
// hello(폴링)·receiving·product-images·inv-snapshot·inv-collect 다섯 Edge Function 이 함께 import 한다.
// 예전엔 429 백오프가 receiving 에만 있고 hello 는 즉시 throw 라 갈라져 있었다
// (2026-08-04 실사고: saleList 429 로 폴링 회차가 통째로 죽어 뒤 페이지 오더 미유입).
// ⚠️ 이 파일을 바꾸면 다섯 함수를 모두 재배포해야 런타임이 일치한다:
//    supabase functions deploy hello && supabase functions deploy receiving \
//      && supabase functions deploy product-images && supabase functions deploy inv-snapshot \
//      && supabase functions deploy inv-collect
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
  // ⚠️ 429 는 **Retry-After 를 읽어 그만큼 대기** 후 1회 재시도한다 (2026-08-19 개정 — 실측 근거):
  //    · [실측 2026-08-18 밤 GAS 프로브] 한도 = 60콜/60초(429 본문 명문) · 애플리케이션 키 단위 ·
  //      회복 실측 31초 · 응답 헤더 Retry-After: "60 Seconds". ⚠️ 200 응답에는 x-ratelimit-* 이
  //      오지 않는다 — 사전 제어 불가, 호출부의 회차당 캡이 유일한 예방책.
  //    · ~~종전 1.5s→3s·상한 2회(최대 4.5초)~~ 는 실측 회복 31초의 1/7 이라 **사실상 재시도가
  //      아니었다** — 4.5초 뒤에도 창은 여전히 닫혀 있어 그대로 재-429 였다.
  //    · 재시도는 **1회**(=최대 60초 대기 1번) — 두 번이면 120초로 EF 실행 시간 제약을 위협한다.
  //    소진되면 종전과 동일하게 status=429 를 실어 throw — **호출부 계약 불변**:
  //    · receiving: bin 이동 루프가 429 를 failed_moves 에 넣지 않고 회차를 끊는다 (rate_limited)
  //    · hello: saleList 페이지 순회가 throw 없이 조기 종료한다 (rate_limited + 끊긴 페이지 노출)
  //      (2026-08-04 SO-14100/14106 미유입 실사고 방지 — 이 계약을 바꾸지 말 것)
  for (let attempt = 0; ; attempt++) {
    const resp = await fetch(CIN7_BASE + path, {
      method, headers: cin7Headers(),
      body: body === undefined ? undefined : JSON.stringify(body),
    });
    if (resp.status === 429 && attempt < 1) {
      // Retry-After 실측 형태 = "60 Seconds" — parseInt 가 앞 숫자만 취한다. 없거나 파싱 실패면
      // 60초(서버가 60을 말하면 60을 지키는 것이 계약 — 실측 31초는 단발 관측이라 근거로 안 쓴다).
      // 상한 60초 — 서버가 더 큰 값을 말해도 EF 시간 제약 안에서 1회만 기다린다.
      const ra = parseInt(String(resp.headers.get("Retry-After") ?? ""), 10);
      await sleep(Math.min(Number.isFinite(ra) && ra > 0 ? ra : 60, 60) * 1000);
      continue;
    }
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
