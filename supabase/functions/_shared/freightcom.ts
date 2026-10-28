// ============================================================
// ASUNG IMS — Freightcom 순수 함수 (fc-1b · 2026-10-28 · 판정 835 ~ 845) — DB · 네트워크 없음 · deno test 로 시험한다(freightcom/freightcom_test.ts · fixtures = Caleb PC 프로브 원문)
//   실측(2026-10-28 · B): GET /services → 배열 [{id, carrier_name, service_name}] · POST /rate → 202 {request_id} · GET /rate/{id} → {status:{done,total,complete}, rates:[…]}
//   rates[] 원소: service_id · carrier_name · service_name · base{value,currency} · surcharges[{type, amount{value,currency}}] · taxes[…] · total · transit_time_days · valid_until{year,month,day}
//   금액 value = 센트 정수 글자(짐작 → fixtures 전부 total = base + Σsurcharge + Σtax 로 맞는다 · ratesConsistent) · DB 쪽 판정은 fc_quote_save(fc_money_cents · totals_mismatch)
//   services 고르기: 상자 = ref_carrier_fc_name(켜진 운송사의 Freightcom 이름 전부 · fc-1b3 판정 847)과 같은 서비스만 · 팔렛 = services 없이(전부 · LTL 운송사는 표에 아직 없다 — 응답의 carrier_name 이 표와 짝이 없으면 고를 수 없을 뿐)
//   freight_class: 팔렛마다 POST /freight-class/calculate {box: measurements} → "70" 류 글자 → pallets[i].freight_class
// ============================================================
export type FcService = { id: string; carrier_name: string; service_name: string };
export type Measurements = { weight: { unit: string; value: number }; cuboid: { unit: string; l: number; w: number; h: number } };
export type RateRequest = { details: { packaging_type: "package" | "pallet"; packaging_properties: Record<string, unknown>; [k: string]: unknown } };
export type RateStatus = { done: boolean; complete: number; total: number };

export const QUOTE_WAIT_MS = 25_000;          // 한 호출 안에서 기다리는 최대(상자 3 초 · 팔렛 10 ~ 16 초 실측 · EF 한도 안)
export const POLL_INTERVAL_MS = 1_500;
export const SERVICES_CACHE_MS = 10 * 60_000; // /services 48 KB · 10 분 메모리 캐시
export const FC_ACTIONS = ["quote", "quote_poll", "services", "status"] as const;
export type EnvGet = (k: string) => string | undefined;

// fc-1b4 판정 848: 계정마다 비밀값 FREIGHTCOM_API_KEY_<계정>(계정 = ref_warehouse.freightcom_account · 대문자 영숫자 2~10) · 옛 이름 FREIGHTCOM_API_KEY 로 넘어가지 않는다(다른 계정으로 조용히 견적이 나가는 일을 막는다)
export const ACCOUNT_RE = /^[A-Z0-9]{2,10}$/;
export function secretNameFor(account: string): string {
  const a = String(account ?? "").trim();
  if (!ACCOUNT_RE.test(a)) throw new Error(`Freightcom account "${a}" is not a valid key (2–10 upper-case letters or digits · Settings → Warehouses)`);
  return "FREIGHTCOM_API_KEY_" + a;
}
export function apiKeyFor(env: EnvGet, account: string): string {
  return (env(secretNameFor(account)) ?? "").trim();
}
export function noAccountSentence(warehouse: string | null, account: string): string {
  return `${warehouse ? "Warehouse " + warehouse : "This warehouse"} has no Freightcom connection — the secret ${secretNameFor(account)} is not set on this project (ask Caleb) — nothing was saved`;
}
export const servicesCacheKey = (account: string) => "services:" + account.trim().toUpperCase();

const norm = (s: unknown) => String(s ?? "").trim().toLowerCase().replace(/\s+/g, " ");

// /services 응답은 배열 그대로(실측) · 문서 꼴 {services:[…]} 도 받아 준다
export function parseServices(body: unknown): FcService[] {
  const arr = Array.isArray(body) ? body : Array.isArray((body as { services?: unknown })?.services) ? (body as { services: unknown[] }).services : null;
  if (!arr) throw new Error("Freightcom /services did not return a list");
  return arr.filter((s): s is FcService => !!s && typeof (s as FcService).id === "string" && typeof (s as FcService).carrier_name === "string")
            .map((s) => ({ id: s.id, carrier_name: s.carrier_name, service_name: String(s.service_name ?? "") }));
}

// 운송사 이름(ref_carrier_fc_name 의 이름들 · fc-1b3)으로 서비스 id 고르기 — 대소문자 · 앞뒤 공백 무시 · 「Purolator」 는 「Purolator Courier」 와 다른 운송사(실측 /services 에 둘 다 있다)
export function pickServices(services: FcService[], carrierNames: string[]): { ids: string[]; matched: string[]; unmatched: string[] } {
  const want = new Map(carrierNames.map((n) => [norm(n), n]));
  const ids: string[] = [], matched = new Set<string>();
  for (const s of services) { const k = norm(s.carrier_name); if (want.has(k)) { ids.push(s.id); matched.add(k); } }
  const unmatched = [...want.entries()].filter(([k]) => !matched.has(k)).map(([, n]) => n);
  return { ids: [...new Set(ids)].sort(), matched: [...matched].map((k) => want.get(k) as string).sort(), unmatched: unmatched.sort() };
}

export function distinctCarriers(services: FcService[]): string[] {
  return [...new Set(services.map((s) => s.carrier_name.trim()))].filter((s) => s !== "").sort((a, b) => a.localeCompare(b));
}

// 팔렛 payload 의 measurements 목록(freight-class 계산 입력) — 상자면 빈 배열
export function palletBoxes(req: RateRequest): Measurements[] {
  if (req.details.packaging_type !== "pallet") return [];
  const pallets = (req.details.packaging_properties as { pallets?: { measurements: Measurements }[] }).pallets ?? [];
  return pallets.map((p) => p.measurements);
}

// freight_class 를 팔렛마다 끼운다(새 객체 · 원본 무변) · 수가 다르면 멈춘다
export function attachFreightClass(req: RateRequest, classes: string[]): RateRequest {
  const copy = JSON.parse(JSON.stringify(req)) as RateRequest;
  if (copy.details.packaging_type !== "pallet") return copy;
  const pallets = (copy.details.packaging_properties as { pallets: Record<string, unknown>[] }).pallets ?? [];
  if (pallets.length !== classes.length) throw new Error(`freight class count ${classes.length} does not match pallets ${pallets.length}`);
  pallets.forEach((p, i) => { p.freight_class = classes[i]; });
  return copy;
}

export function freightClassOf(body: unknown): string {
  const v = (body as { freight_class?: unknown })?.freight_class;
  if (v === undefined || v === null || String(v).trim() === "") throw new Error("Freightcom /freight-class/calculate returned no freight_class");
  return String(v).trim();
}

// POST /rate 의 몸 — 상자 = services 명시 · 팔렛 = services 없이(전부)
export function rateBody(req: RateRequest, serviceIds: string[] | null): Record<string, unknown> {
  return serviceIds && serviceIds.length > 0 ? { services: serviceIds, details: req.details } : { details: req.details };
}

export function requestIdOf(body: unknown): string {
  const id = (body as { request_id?: unknown })?.request_id;
  if (typeof id !== "string" || id.trim() === "") throw new Error("Freightcom /rate returned no request_id");
  return id.trim();
}

export function rateStatus(body: unknown): RateStatus {
  const st = (body as { status?: { done?: unknown; complete?: unknown; total?: unknown } })?.status ?? {};
  return { done: st.done === true, complete: Number(st.complete ?? 0) || 0, total: Number(st.total ?? 0) || 0 };
}

// 다시 묻기 끝 판정 — done 이면 끝 · 아니면 시한 안에서만 계속
export function shouldKeepPolling(st: RateStatus, startedAt: number, now: number, waitMs = QUOTE_WAIT_MS): boolean {
  return !st.done && now - startedAt < waitMs;
}

// 센트 정수 글자 → 정수(짐작 확인용 · DB 는 fc_money_cents 로 따로 센다)
export function cents(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const raw = typeof v === "object" ? (v as { value?: unknown }).value : v;
  if (raw === null || raw === undefined || String(raw).trim() === "") return null;
  const n = Number(String(raw).trim());
  return Number.isFinite(n) ? Math.round(n) : null;
}
export type RateLine = { service_id: string; carrier_name: string; base: number | null; surcharges: number; taxes: number; total: number | null; consistent: boolean };
export function rateLines(body: unknown): RateLine[] {
  const rates = ((body as { rates?: unknown[] })?.rates ?? []) as Record<string, unknown>[];
  return rates.map((r) => {
    const sum = (k: string) => ((r[k] as { amount?: unknown }[] | undefined) ?? []).reduce((a, x) => a + (cents(x.amount) ?? 0), 0);
    const base = cents(r.base), total = cents(r.total), surcharges = sum("surcharges"), taxes = sum("taxes");
    return { service_id: String(r.service_id ?? ""), carrier_name: String(r.carrier_name ?? ""), base, surcharges, taxes, total, consistent: base !== null && total !== null && base + surcharges + taxes === total };
  });
}

// 오류 문장 — 토큰 · 열쇠 글자는 어디에도 넣지 않는다 · 몸은 400 자까지
export function fcErrorSentence(action: string, status: number, body: unknown): string {
  const text = typeof body === "string" ? body : JSON.stringify(body ?? "");
  const hint = status === 401 ? " — FREIGHTCOM_API_KEY is wrong or expired (the test link lasts a week · ask Caleb to set it again)" : status === 404 ? " — path or request_id unknown" : "";
  return `Freightcom ${action} failed (HTTP ${status})${hint}: ${text.replace(/"?(api[_-]?key|authorization|token)"?\s*[:=]\s*"?[^",\s]+/gi, "$1:***").slice(0, 400)}`;
}
