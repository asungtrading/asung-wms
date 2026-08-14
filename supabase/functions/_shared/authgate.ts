// ============================================================
// ASUNG WMS — 공용 서버측 권한 게이트 (_shared)
// hello(hold_recheck)·receiving 이 함께 import 한다.
// ------------------------------------------------------------
// 배경(2026-08-13): 레포가 PUBLIC 이라 anon 키는 공개다 — 클라이언트 게이트(admin.html 의
// 3중 게이트 등)는 anon 키 직호출로 우회된다(규칙 8 각주 실측). 서버측 검증은 hold_recheck
// (hello)와 staff-create 에 거의 같은 코드가 두 벌 복제돼 있었다 — 세 번째 복제 대신 추출.
// (staff-create 는 동작 중이라 이번엔 무접촉 — authgate 로의 교체는 별건.)
//
// ⚠️ 이 파일을 바꾸면 import 하는 함수를 모두 재배포해야 런타임이 일치한다:
//    supabase functions deploy hello && supabase functions deploy receiving
//    (각 함수는 배포 시점의 번들을 계속 쓴다 — _shared/cin7.ts 와 같은 규칙)
// ⚠️⚠️ hello 의 "폴링 경로"(?commit=1)에는 절대 걸지 말 것 — pg_cron(wms-poll-orders)이
//    Bearer 접두어 없는 anon 키로 부르고 hello 는 verify_jwt=false 다(config.toml).
//    전역 진입부에 넣으면 5분마다 실패해 오더 유입이 전면 중단된다. 게이트는 action 스코프에만.
// ============================================================

export type Staff = {
  email: string;
  name: string;
  role: string;
  perms: string[];
  active: boolean;
};

// 호출자 검증: Bearer 토큰 → /auth/v1/user → wms_staff 조회.
// null = 로그인 실패(토큰 없음·무효·이메일 없음·wms_staff 에 행 없음) → 호출부는 401.
// ⚠️ anon 키 자체는 /auth/v1/user 에서 유저가 안 나온다 → null (이것이 게이트의 핵심).
// ⚠️ 이메일 매칭은 **원문 그대로 정확일치** — wms-auth.js(:170)가 user.email 을 raw 로
//    .eq 조회하는 것과 같은 불변식이다. 여기서 lowercase 를 하면 mixed-case 행으로
//    로그인되는 계정이 게이트에서만 막히는 회귀가 생긴다(staff-create 는 "생성 시점" 정규화라 별개).
// ⚠️ wms_staff 조회는 service_role(자동주입) — RLS 우회는 서버사이드 정상 경로다(규칙 8).
//    조회 자체가 실패(네트워크·5xx)하면 throw → 호출부 최상위 catch 가 500 = fail-closed.
export async function verifyCaller(req: Request): Promise<Staff | null> {
  const tok = (req.headers.get("authorization") || "").replace(/^Bearer\s+/i, "");
  if (!tok) return null;
  const sbUrl = Deno.env.get("SUPABASE_URL") ?? "";
  const uResp = await fetch(sbUrl + "/auth/v1/user", {
    headers: { apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "", Authorization: "Bearer " + tok },
  });
  if (!uResp.ok) return null;
  const email = String((await uResp.json())?.email || "");
  if (!email) return null;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const sResp = await fetch(
    sbUrl + "/rest/v1/wms_staff?email=eq." + encodeURIComponent(email) + "&select=name,role,perms,active&limit=1",
    { headers: { apikey: svc, Authorization: "Bearer " + svc } },
  );
  if (!sResp.ok) throw new Error("authgate wms_staff lookup " + sResp.status + ": " + (await sResp.text()).slice(0, 300));
  const s = (await sResp.json())[0];
  if (!s) return null;
  return {
    email,
    name: String(s.name || ""),
    role: String(s.role || ""),
    perms: Array.isArray(s.perms) ? s.perms : [],
    // wms-auth.js(:173)와 같은 판정 — active===false 만 차단(null/미설정 행은 통과).
    // 여기서 s.active===true 로 좁히면 로그인되는 계정이 게이트에서만 막힐 수 있다.
    active: s.active !== false,
  };
}

// "신중한 조작" 권한 — receiving Apply·hold_recheck(보류 해제)가 공유한다
// (2026-08-12 사용자 결정: 기존 perms 'apply' 키 재사용).
// ⚠️⚠️ role==='admin' || 를 빠뜨리지 말 것 — [실측 2026-08-13] Caleb 의 perms 는
//    ["split","admin","staff"] 로 'apply' 가 없고 role='admin' 으로만 통과한다.
//    perms 만 보면 admin 이 막힌다(규칙 16: admin 역할은 항상 전부, perms 는 매니저 세부권한).
export function hasApply(s: Staff): boolean {
  return s.role === "admin" || s.perms.includes("apply");
}
