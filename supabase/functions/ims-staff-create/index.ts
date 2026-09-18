// ============================================================
// ASUNG IMS — ims-staff-create Edge Function (2026-09-15)
// ------------------------------------------------------------
// staff.html(asung-ims 레포)에서 사람을 한 번에 추가한다:
//   1) 부르는 사람을 확인한다 — ⭐ caller 의 JWT 로 rpc/ims_can_write('staff') 와 rpc/ims_can_manage(role) 을 부른다
//      (정책과 같은 판정 함수 · po-module §10-h · 2026-09-17 밤: admin 전용 → 「staff 쓰기 권한 + 자기보다 아래 등급만」 · 20260918020000)
//   2) service_role 로 Supabase Auth 계정을 만든다 (임시 비밀번호 · auto-confirm)
//   3) ims_staff 행을 만든다 — ⭐ auth_user_id = 방금 만든 Auth 계정의 id
//   4) 임시 비밀번호를 한 번만 돌려준다 (admin 이 본인에게 전달)
//
// 원본: supabase/functions/staff-create/index.ts (WMS · 2026-07-21) — 여기서 바뀐 여섯:
//   ① 표          wms_staff → ims_staff
//   ② caller 확인  email 로 표를 읽던 것 → caller JWT 로 rpc (ims_is_admin → 2026-09-17 ims_can_write('staff') + ims_can_manage(role))
//                 ⚠️ service_role 로 표를 직접 읽으면 auth.uid() 가 null 이라 그 함수를 못 쓰고
//                    정책과 EF 가 다른 판정 코드를 갖게 된다 — 그래서 rpc (§10-h 「하나뿐이다」)
//                 ⚠️ email 매칭의 대소문자 함정(WMS 규칙 8 각주)도 이 길에는 없다
//   ③ 활성 칸      active → is_active
//   ④ 역할        worker/manager/admin → worker/supervisor/manager/admin 넷(ims_staff_role_ck · 20260917230000 · 2026-09-17 넷으로) · warehouse_access 는 안 받는다(비움 = 전부 · 편집은 staff.html 몫) · 기본 manager
//   ⑤ 권한        'staff' 쓰기 권한자(admin·supervisor 기본 · manager 는 perms) · 만들 수 있는 등급은 자기보다 아래만(ims_can_manage · admin 은 전부) · perms 는 [] 로 만든다
//   ⑥ insert     auth_user_id(NOT NULL) 를 넣는다 — 원본에는 없던 단계
// 그대로 가져온 것: 서버측 권한 검사 · Auth 계정 롤백 · 중복 409 · 읽기 쉬운 임시 비밀번호 · CORS
// 덧붙인 것: 이메일은 소문자로 저장 · 중복 검사는 ilike · 롤백 실패 시 orphan id 를 응답에 싼다
//
// 배포 (Caleb · ⚠️ 대상은 Asung-IMS · 이름을 꼭 붙인다 — config.toml 블록 주석 참조):
//   cd ~/asung/asung-wms && supabase functions deploy ims-staff-create --project-ref fazgmyvzzhqybtvtktyg
// ⚠️ SUPABASE_URL · SUPABASE_SERVICE_ROLE_KEY · SUPABASE_ANON_KEY 는 프로젝트마다 자동 주입된다
//    (Supabase 문서 — IMS 에서 실측한 것은 아니다). service_role 은 이 안에만 있다 — 프론트에 두지 않는다.
// ============================================================

const CORS: HeadersInit = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

const SB_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// 헷갈리는 글자(0/O · 1/l/I)를 뺀 임시 비밀번호 — 원본과 같다
function tempPassword(): string {
  const set = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  const pick = (n: number) =>
    Array.from(crypto.getRandomValues(new Uint8Array(n)))
      .map((b) => set[b % set.length]).join("");
  return `Asung-${pick(4)}-${pick(4)}`;
}

// service_role 호출 — Auth admin API 와 ims_staff 쓰기에만 쓴다
async function sbFetch(path: string, init: RequestInit = {}): Promise<Response> {
  return await fetch(SB_URL + path, {
    ...init,
    headers: {
      "apikey": SERVICE,
      "Authorization": "Bearer " + SERVICE,
      "Content-Type": "application/json",
      ...(init.headers || {}),
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json(405, { error: "POST only" });

  try {
    // ---- 1) 부르는 사람 확인 — caller JWT 로 판정 함수를 부른다(정책과 같은 함수 · service_role 로 표를 읽으면 auth.uid() 가 null) ----
    //   ⚠️ 이것이 없으면 anon key(공개 레포)만으로 아무나 계정을 만든다(규칙 8 실사고의 모양)
    //   ① ims_can_write('staff')     — 직원 관리 권한(admin·supervisor 기본 · manager 는 perms 'staff')
    //   ② ims_can_manage(role)       — 만들려는 등급이 자기보다 아래인가(admin 은 전부 · 같은 등급 false) — role 을 읽은 뒤에 본다
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json(401, { error: "Missing Authorization" });

    // caller JWT 로 boolean RPC 하나를 부른다 — 401 은 세션 만료 · 그 외 비정상은 502
    async function callerRpc(fn: string, args: Record<string, unknown>): Promise<boolean | Response> {
      const r = await fetch(SB_URL + "/rest/v1/rpc/" + fn, {
        method: "POST",
        headers: { "apikey": ANON, "Authorization": "Bearer " + jwt, "Content-Type": "application/json" },
        body: JSON.stringify(args),
      });
      if (r.status === 401) return json(401, { error: "Invalid session — sign in again" });
      if (!r.ok) return json(502, { error: "Permission check failed (" + fn + "): " + (await r.text()).slice(0, 200) });
      return (await r.json()) === true;
    }
    const canStaff = await callerRpc("ims_can_write", { p_screen: "staff" });
    if (canStaff instanceof Response) return canStaff;
    if (canStaff !== true) return json(403, { error: "Not allowed — you need the 'staff' permission to add people" });

    // ---- 2) 입력 검증 ---------------------------------------------------
    const body = await req.json().catch(() => ({}));
    const name = String(body.name || "").trim();
    const email = String(body.email || "").trim().toLowerCase();   // ⭐ 소문자로 저장
    const role = String(body.role || "manager");                    // ④ 기본 manager
    if (!name) return json(400, { error: "Name is required" });
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(400, { error: "Valid email is required" });
    if (!["worker", "supervisor", "manager", "admin"].includes(role)) return json(400, { error: "Bad role" });   // ④ ims_staff_role_ck 와 같은 넷

    // ---- 1-②) 만들 수 있는 등급인가 — 자기보다 아래만(같은 등급도 안 된다 · admin 은 전부) ----
    const canRole = await callerRpc("ims_can_manage", { p_target_role: role });
    if (canRole instanceof Response) return canRole;
    if (canRole !== true) return json(403, { error: "Not allowed — you can only add people below your own role (" + role + " is not below yours)" });

    // 중복 검사 — email UNIQUE 는 대소문자를 구분하므로 ilike 로 본다
    //   (LIKE 의 _ 는 한 글자 와일드카드라 john_doe 와 johnXdoe 가 겹칠 수 있다 — 막는 쪽 오류라 둔다)
    const dupResp = await sbFetch(
      `/rest/v1/ims_staff?email=ilike.${encodeURIComponent(email)}&select=id,name`,
    );
    const dups = dupResp.ok ? await dupResp.json() : [];
    if (dups.length) return json(409, { error: `Email already linked to staff "${dups[0].name}"` });

    // ---- 3) Auth 계정 만들기 ----------------------------------------------
    const password = tempPassword();
    const createResp = await sbFetch("/auth/v1/admin/users", {
      method: "POST",
      body: JSON.stringify({ email, password, email_confirm: true }),
    });
    if (!createResp.ok) {
      const t = await createResp.text();
      if (createResp.status === 422 || /already/i.test(t)) {
        // Auth 계정은 있는데 ims_staff 행이 없는 경우 — 연결 경로는 만들지 않는다(2026-09-15 합의).
        // 열쇠가 auth_user_id 라 「기존 행의 email 을 고쳐라」(WMS 안내)는 여기 맞지 않는다.
        return json(409, {
          error: "An Auth account with this email already exists but has no ims_staff row. " +
            "Copy its UID from Authentication → Users and insert the row by SQL — po-module §10-f ②-b.",
        });
      }
      return json(502, { error: "Auth create failed: " + t.slice(0, 200) });
    }
    const created = await createResp.json();
    if (!created?.id) return json(502, { error: "Auth create returned no id" });

    // ---- 4) ims_staff 행 만들기 — ⑥ auth_user_id 필수 -------------------------
    const insResp = await sbFetch("/rest/v1/ims_staff", {
      method: "POST",
      headers: { "Prefer": "return=representation" },
      body: JSON.stringify({
        auth_user_id: created.id, email, name, role, perms: [], is_active: true,
      }),
    });
    if (!insResp.ok) {
      const insErr = (await insResp.text()).slice(0, 200);
      // 롤백 — 안 지우면 로그인은 되는데 신원이 없는 유령 계정이 남는다
      const delResp = await sbFetch(`/auth/v1/admin/users/${created.id}`, { method: "DELETE" }).catch(() => null);
      if (!delResp || !delResp.ok) {
        // 롤백도 실패 — 사람이 대시보드에서 지울 수 있게 id 를 싼다
        return json(502, { error: "Staff insert failed AND rollback failed — delete this Auth user by hand: " + insErr, orphan_auth_user_id: created.id });
      }
      return json(502, { error: "Staff insert failed (Auth account rolled back): " + insErr });
    }
    const [staff] = await insResp.json();

    return json(200, { ok: true, staff, temp_password: password });
  } catch (e) {
    return json(500, { error: String((e as Error)?.message || e) });
  }
});
