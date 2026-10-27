// deno test supabase/functions/shopify/shopify_live_test.ts — Shopify · DB 무접촉 (shop-live-1 ① ~ ⑥ · _shared/shopify.ts 의 문 · 보관 토큰 · scope 출처 · 401 무재시도)
//   판정 811(읽기 길 is_active · 일하는 길 is_active and live) · 813(auth_mode stored_token · 비밀 없음 · 401 에 다시 받지 않음) · 815(큐 줄은 열어 둔다 wait)
import { getToken, isStoredToken, isWorking, missingScopes, queueGate, readGate, scopesOf, secretNames, shopifyGql, storedToken, storedTokenDeadSentence, workGate, type StoreRow } from "../_shared/shopify.ts";

function eq(actual: unknown, expected: unknown, msg: string) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  if (a !== b) throw new Error(msg + "\n  expected: " + b + "\n  got:      " + a);
}
const S = (over: Partial<StoreRow> = {}): StoreRow => ({ id: "s1", code: "aone", shop_domain: "aone-beauty-health.myshopify.com", secret_prefix: "SHOPIFY_AONE", is_active: true, live: false, auth_mode: "stored_token", label: "Aone", kind: "aone", ...over });

Deno.test("① 문 — readGate 는 is_active 만 · workGate 는 is_active and live · 막힌 문장은 사람 말 · isWorking", () => {
  eq(readGate(S()), null, "active · not live → read ok");
  eq(workGate(S())?.includes("is not live"), true, "active · not live → work blocked (not live)");
  eq(workGate(S())?.includes("Settings → Shopify Stores"), true, "tells where to go live");
  eq(readGate(S({ is_active: false, live: true }))?.includes("switched off"), true, "off → read blocked");
  eq(workGate(S({ is_active: false, live: true }))?.includes("switched off"), true, "off wins over live (switched off sentence)");
  eq(workGate(S({ live: true })), null, "active · live → work ok");
  eq([isWorking(S()), isWorking(S({ live: true })), isWorking(S({ is_active: false, live: true }))], [false, true, false], "isWorking");
});

Deno.test("② 큐 줄의 갈래(queueGate · 판정 815) — 없음 · 꺼짐 = error(닫는다) · live 전 = wait(열어 둔다) · 켜짐 = go", () => {
  eq(queueGate(undefined), "error", "missing store");
  eq(queueGate(null), "error", "null store");
  eq(queueGate(S({ is_active: false, live: true })), "error", "switched off → error (closed · as before)");
  eq(queueGate(S({ is_active: false, live: false })), "error", "off and not live → error");
  eq(queueGate(S()), "wait", "active · not live → wait");
  eq(queueGate(S({ live: true })), "go", "live → go");
});

Deno.test("③ 보관 토큰(storedToken · secretNames) — <PREFIX>_ACCESS_TOKEN 읽기만 · 공백 다듬기 · 없으면 비밀 이름 · 도구 이름을 든 문장 · 만료 없음", () => {
  eq(secretNames("SHOPIFY_AONE"), { id: "SHOPIFY_AONE_CLIENT_ID", secret: "SHOPIFY_AONE_CLIENT_SECRET", token: "SHOPIFY_AONE_ACCESS_TOKEN" }, "three names");
  eq(isStoredToken(S()), true, "stored_token");
  eq(isStoredToken(S({ auth_mode: "client_credentials" })), false, "client_credentials");
  const env = (k: string) => (k === "SHOPIFY_AONE_ACCESS_TOKEN" ? " shpat_abc " : undefined);
  const t = storedToken(S(), env);
  eq([t.token, t.scope, t.expiresAt === Number.MAX_SAFE_INTEGER], ["shpat_abc", "", true], "token trimmed · no scope · never expires");
  let err = "";
  try { storedToken(S(), () => undefined); } catch (e) { err = String((e as Error).message); }
  eq(err.includes("SHOPIFY_AONE_ACCESS_TOKEN is not set") && err.includes("tools/shopify-oauth-exchange.sh") && err.includes("aone-beauty-health.myshopify.com"), true, "missing → names the secret · the tool · the store: " + err);
  try { storedToken(S(), () => "   "); } catch (e) { err = String((e as Error).message); }
  eq(err.includes("is not set"), true, "blank counts as missing");
});

Deno.test("④ getToken — stored_token 은 fetch 0 · 비밀 없음은 던진다 · client_credentials 는 토큰 끝점 1 번(scope 글자) · 비밀 없음 문장", async () => {
  let calls = 0;
  const fetchFn = (_u: string, _i?: RequestInit) => { calls++; return Promise.resolve(new Response(JSON.stringify({ access_token: "cc_tok", scope: "write_products,read_locations", expires_in: 86399 }), { status: 200 })); };
  const st = S({ shop_domain: "live-test-a.myshopify.com" });
  const t1 = await getToken(st, true, (k) => (k.endsWith("_ACCESS_TOKEN") ? "shpat_x" : undefined), fetchFn);
  eq([t1.token, calls], ["shpat_x", 0], "stored token: no network");
  let err = "";
  try { await getToken(S({ shop_domain: "live-test-b.myshopify.com" }), true, () => undefined, fetchFn); } catch (e) { err = String((e as Error).message); }
  eq([err.includes("SHOPIFY_AONE_ACCESS_TOKEN is not set"), calls], [true, 0], "stored token missing: throws · no network");
  const cc = S({ shop_domain: "live-test-c.myshopify.com", auth_mode: "client_credentials", secret_prefix: "SHOPIFY_IMS" });
  const t2 = await getToken(cc, true, (k) => (k === "SHOPIFY_IMS_CLIENT_ID" ? "id" : k === "SHOPIFY_IMS_CLIENT_SECRET" ? "sec" : undefined), fetchFn);
  eq([t2.token, t2.scope, calls], ["cc_tok", "write_products,read_locations", 1], "client credentials: one token call · scope from the response");
  try { await getToken(S({ shop_domain: "live-test-d.myshopify.com", auth_mode: "client_credentials" }), true, () => undefined, fetchFn); } catch (e) { err = String((e as Error).message); }
  eq(err.includes("SHOPIFY_AONE_CLIENT_ID / SHOPIFY_AONE_CLIENT_SECRET are not set"), true, "client credentials missing: names both");
});

Deno.test("⑤ shopifyGql — 보관 토큰 401 · 403 에 다시 받지 않는다(fetch 1 번 · ok false · 사람 말) · client_credentials 401 은 한 번 새로 받는다(기존 그대로)", async () => {
  const log: string[] = [];
  const mk = (status: number, body: unknown) => new Response(JSON.stringify(body), { status });
  const fetch401 = (u: string, _i?: RequestInit) => { log.push(u.includes("/oauth/") ? "token" : "gql"); return Promise.resolve(mk(401, { errors: "[API] Invalid API key or access token" })); };
  const st = S({ shop_domain: "live-test-e.myshopify.com" });
  const r = await shopifyGql(st, "query { shop { name } }", {}, { env: (k) => (k.endsWith("_ACCESS_TOKEN") ? "shpat_dead" : undefined), fetchFn: fetch401 });
  eq([r.ok, r.status, r.attempts, r.tokenRefreshed, log], [false, 401, 1, false, ["gql"]], "stored token: one call · no refresh");
  eq(r.errors?.[0]?.message, storedTokenDeadSentence(401, st), "dead-token sentence");
  eq(storedTokenDeadSentence(403, st).includes("SHOPIFY_AONE_ACCESS_TOKEN") && storedTokenDeadSentence(403, st).includes("tools/shopify-oauth-exchange.sh"), true, "sentence names the secret and the tool");
  // client_credentials: gql 401 → token 끝점 한 번 더 → gql 다시(기존 동작)
  log.length = 0;
  let n = 0;
  const fetchCc = (u: string, _i?: RequestInit) => {
    if (u.includes("/oauth/")) { log.push("token"); return Promise.resolve(mk(200, { access_token: "t" + (++n), scope: "write_products", expires_in: 86399 })); }
    log.push("gql"); return Promise.resolve(log.filter((x) => x === "gql").length === 1 ? mk(401, {}) : mk(200, { data: { shop: { name: "x" } } }));
  };
  const cc = S({ shop_domain: "live-test-f.myshopify.com", auth_mode: "client_credentials" });
  const r2 = await shopifyGql(cc, "query { shop { name } }", {}, { env: (k) => (k.endsWith("_CLIENT_ID") ? "id" : k.endsWith("_CLIENT_SECRET") ? "sec" : undefined), fetchFn: fetchCc });
  eq([r2.ok, r2.attempts, r2.tokenRefreshed, log], [true, 2, true, ["token", "gql", "token", "gql"]], "client credentials: refreshed once and retried");
});

Deno.test("⑥ scope 출처(scopesOf · ping) — 토큰 응답 scope 가 있으면 token · 없으면 currentAppInstallation.accessScopes(installation) · 둘 다 없으면 none(전부 빠짐)", () => {
  const inst = { accessScopes: [{ handle: "write_products" }, { handle: "read_locations" }, { handle: " write_orders " }, { handle: "" }] };
  eq(scopesOf("write_products,read_locations", inst), { granted: "write_products,read_locations", source: "token" }, "token wins");
  eq(scopesOf("", inst), { granted: "write_products,read_locations,write_orders", source: "installation" }, "installation (trimmed · blanks dropped)");
  eq(scopesOf("", null), { granted: "", source: "none" }, "nothing");
  eq(scopesOf("", { accessScopes: null }), { granted: "", source: "none" }, "null list");
  eq(missingScopes(scopesOf("", inst).granted).length, 11 - 5, "missing computed from the installation list (write_products→read too · read_locations · write_orders→read too)");
});
