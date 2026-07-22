// ============================================================
// ASUNG WMS - staff-create Edge Function (2026-07-21)
// ------------------------------------------------------------
// Creates a new staff member in ONE step from staff-admin.html:
//   1) verifies the CALLER (must be an active admin, or a manager
//      whose perms include "staff" — same rule as the screen)
//   2) creates the Supabase Auth account (email + temp password,
//      auto-confirmed) using the service key (server-side only)
//   3) inserts the matching wms_staff row (email = the link)
//   4) returns the temp password ONCE for the admin to hand over
//
// Deploy:  cd ~\asung-wms && supabase functions deploy staff-create
// Called from the browser with the logged-in user's JWT.
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

// readable temp password without ambiguous chars (0/O, 1/l/I)
function tempPassword(): string {
  const set = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
  const pick = (n: number) =>
    Array.from(crypto.getRandomValues(new Uint8Array(n)))
      .map((b) => set[b % set.length]).join("");
  return `Asung-${pick(4)}-${pick(4)}`;
}

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
    // ---- 1) identify + authorize the caller --------------------
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return json(401, { error: "Missing Authorization" });

    const uResp = await fetch(SB_URL + "/auth/v1/user", {
      headers: { "apikey": ANON, "Authorization": "Bearer " + jwt },
    });
    if (!uResp.ok) return json(401, { error: "Invalid session — sign in again" });
    const caller = await uResp.json();
    const callerEmail = String(caller?.email || "").toLowerCase();
    if (!callerEmail) return json(401, { error: "Session has no email" });

    const meResp = await sbFetch(
      `/rest/v1/wms_staff?email=eq.${encodeURIComponent(callerEmail)}&select=name,role,perms,active`,
    );
    const meRows = meResp.ok ? await meResp.json() : [];
    const meRow = meRows[0];
    const isAdmin = meRow?.active && meRow.role === "admin";
    const isStaffMgr = meRow?.active && meRow.role === "manager" &&
      Array.isArray(meRow.perms) && meRow.perms.includes("staff");
    if (!isAdmin && !isStaffMgr) {
      return json(403, { error: "Not allowed — staff management permission required" });
    }

    // ---- 2) validate input --------------------------------------
    const body = await req.json().catch(() => ({}));
    const name = String(body.name || "").trim();
    const email = String(body.email || "").trim().toLowerCase();
    const role = String(body.role || "worker");
    const wh = String(body.warehouse_access || "toronto");
    if (!name) return json(400, { error: "Name is required" });
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json(400, { error: "Valid email is required" });
    if (!["worker", "manager", "admin"].includes(role)) return json(400, { error: "Bad role" });
    if (!["toronto", "edmonton", "both"].includes(wh)) return json(400, { error: "Bad warehouse" });

    // duplicate link check (email is the login link — must be unique)
    const dupResp = await sbFetch(
      `/rest/v1/wms_staff?email=eq.${encodeURIComponent(email)}&select=id,name`,
    );
    const dups = dupResp.ok ? await dupResp.json() : [];
    if (dups.length) return json(409, { error: `Email already linked to staff "${dups[0].name}"` });

    // ---- 3) create the Auth account ------------------------------
    const password = tempPassword();
    const createResp = await sbFetch("/auth/v1/admin/users", {
      method: "POST",
      body: JSON.stringify({ email, password, email_confirm: true }),
    });
    if (!createResp.ok) {
      const t = await createResp.text();
      if (createResp.status === 422 || /already/i.test(t)) {
        return json(409, { error: "An Auth account with this email already exists. Link it by editing the email on an existing staff row instead." });
      }
      return json(502, { error: "Auth create failed: " + t.slice(0, 200) });
    }
    const created = await createResp.json();

    // ---- 4) insert the wms_staff row ------------------------------
    const insResp = await sbFetch("/rest/v1/wms_staff", {
      method: "POST",
      headers: { "Prefer": "return=representation" },
      body: JSON.stringify({ name, email, role, warehouse_access: wh, active: true }),
    });
    if (!insResp.ok) {
      // best-effort rollback so we don't leave an orphan Auth account
      if (created?.id) await sbFetch(`/auth/v1/admin/users/${created.id}`, { method: "DELETE" }).catch(() => {});
      return json(502, { error: "Staff insert failed: " + (await insResp.text()).slice(0, 200) });
    }
    const [staff] = await insResp.json();

    return json(200, { ok: true, staff, temp_password: password });
  } catch (e) {
    return json(500, { error: String((e as Error)?.message || e) });
  }
});
