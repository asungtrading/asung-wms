// ============================================================
// ASUNG IMS — _shared/mcp-manual.ts: Claude 커넥터 매뉴얼 도구 둘(manual_search · manual_read)의 순수 처리 (mcp-more-1 · 2026-11-13 · 판정 1211 · DB 20261113021500 mcp_manual_gate)
//   원고: GitHub main 의 docs/manual(en · ko) — IMS 화면 매뉴얼 help.html:93 과 같은 주소 · 장 목록도 같은 식(README Contents 표에서 링크가 걸린 장만)
//   ⚠️ 문은 여기 없다 — _shared/mcp.ts 의 callTool 이 rpc/mcp_manual_gate(사용자 토큰)를 먼저 부르고 ok 일 때만 이 파일의 run 을 부른다(Claude 열쇠를 끄면 매뉴얼도 거절 · 921)
//   ⚠️ 읽는 주소는 MANUAL_RAW + README.md · MANUAL_RAW + <lang>/<NN-이름>.md 뿐 — README 에서 읽은 파일 이름은 꼴(^\d\d-[a-z0-9-]+$)을 지킨 것만(README 가 잘못돼도 다른 주소를 읽지 않는다)
//   절 = <a id="area-task"></a> 줄부터 다음 앵커 줄 앞까지(docs/manual/README.md Anchors) · 숨은 주석 <!-- … -->(screen · rulings · SCREENSHOT · 그 밖)은 전부 뺀다 · who 만 칸으로(배열) · 장 머리(첫 앵커 앞)는 절이 아니다(장 제목만 쓴다)
//   캐시: 인스턴스 메모리 · 언어마다 · MANUAL_CACHE_MS(5 분 — raw 의 max-age=300 과 같은 크기 ⇒ 원고 push 뒤 최대 ≈ 10 분 늦는다 · Caleb 2026-11-12 받아들임) · 실패는 담지 않는다
//   실패: 하나라도 못 읽으면(상한 MANUAL_TIMEOUT_MS · 재시도 없음 · 200 아님 · 절 0) ManualUnavailable — 일부만 읽고 「없다」 고 답하지 않는다
//   찾기: 질문 → 낱말(흔한 말 빼고 · 가벼운 어미 떼기) · 점수 = 앵커 6 · 제목 5 · 본문 횟수(상한 5) + 맞은 낱말 4 씩 + 다 맞으면 6 · 한글 낱말은 포함 여부 · 후보 MANUAL_MAX_HITS · 0 건이면 목차(앵커 · 제목)
// ============================================================
export const MANUAL_RAW = "https://raw.githubusercontent.com/asungtrading/asung-wms/main/docs/manual/";
export const MANUAL_HELP_URL = "https://ims.asung.ca/help.html";
export const MANUAL_TIMEOUT_MS = 6_000;
export const MANUAL_CACHE_MS = 300_000;
export const MANUAL_MAX_HITS = 8;
export const MANUAL_QUERY_MAX = 200;
export const MANUAL_SNIPPET = 200;
export const MANUAL_UNAVAILABLE = "The IMS manual cannot be read right now — open the ? help on the IMS screen instead, or try again in a few minutes.";
export class ManualUnavailable extends Error {
  code = "manual_unavailable";
  detail: string;                                                                                     // 기록 · warn 용(파일 이름 · 상태) — Claude 에게는 MANUAL_UNAVAILABLE 만
  constructor(detail: string) { super(MANUAL_UNAVAILABLE); this.name = "ManualUnavailable"; this.detail = detail; }
}

export type Lang = "en" | "ko";
export type Section = { anchor: string; file: string; chapter: string; title: string; who: string[]; body: string };
export type Manual = { lang: Lang; files: string[]; sections: Section[] };
export type ManualDeps = { fetch: (url: string, init: RequestInit) => Promise<Response>; now: () => number };

export const manualLang = (v: unknown): Lang => (String(v ?? "en").toLowerCase() === "ko" ? "ko" : "en");
export const manualUrl = (lang: Lang, anchor: string): string => `${MANUAL_HELP_URL}?lang=${lang}#${anchor}`;

// ── 원고 쪼개기 ──
// README Contents → 그 언어의 장 파일(순서 그대로 · 겹치면 한 번) — help.html hpLoad 와 같은 식
export function chapterFiles(readme: string, lang: Lang): string[] {
  const files: string[] = [];
  const re = new RegExp("\\]\\(" + lang + "\\/(\\d\\d-[a-z0-9-]+)\\.md\\)", "g");
  for (const m of String(readme).matchAll(re)) if (!files.includes(m[1])) files.push(m[1]);
  return files;
}
const ANCHOR_LINE = /^<a id="([a-z0-9-]+)"><\/a>\s*$/;
const stripComments = (s: string): string => s.replace(/<!--[\s\S]*?-->/g, "");
export function splitChapter(md: string, file: string): Section[] {
  const lines = String(md).replace(/\r\n?/g, "\n").split("\n");
  const h1 = lines.find((l) => /^# \S/.test(l));
  const chapter = h1 ? h1.replace(/^# /, "").trim() : file;
  const out: Section[] = [];
  let cur: { anchor: string; lines: string[] } | null = null;
  const flush = () => {
    if (!cur) return;
    const raw = cur.lines.join("\n");
    const whoM = raw.match(/<!--\s*who:\s*([^>]*?)\s*-->/);
    const who = whoM ? whoM[1].split(",").map((w) => w.trim().toLowerCase()).filter(Boolean) : [];
    const clean = stripComments(raw).split("\n");
    const ti = clean.findIndex((l) => /^##+ \S/.test(l));
    const title = ti >= 0 ? clean[ti].replace(/^##+ /, "").trim() : cur.anchor;
    if (ti >= 0) clean.splice(ti, 1);
    const body = clean.join("\n").replace(/[ \t]+\n/g, "\n").replace(/\n{3,}/g, "\n\n").trim();
    out.push({ anchor: cur.anchor, file, chapter, title, who, body });
  };
  for (const l of lines) {
    const m = l.match(ANCHOR_LINE);
    if (m) { flush(); cur = { anchor: m[1], lines: [] }; } else if (cur) cur.lines.push(l);
  }
  flush();
  return out;
}

// ── 원고 읽기 + 캐시 ──
const cache = new Map<Lang, { at: number; manual: Manual }>();
export const manualCacheClear = (): void => cache.clear();
export async function loadManual(d: ManualDeps, lang: Lang): Promise<Manual> {
  const hit = cache.get(lang);
  if (hit && d.now() - hit.at < MANUAL_CACHE_MS) return hit.manual;
  const signal = AbortSignal.timeout(MANUAL_TIMEOUT_MS);                                               // 상한은 묶음 전체(README + 장 전부)에 하나
  const get = async (path: string): Promise<string> => {
    let r: Response;
    try { r = await d.fetch(MANUAL_RAW + path, { method: "GET", signal }); }
    catch (e) { throw new ManualUnavailable(path + " — " + String((e as Error)?.name ?? "") + " " + String((e as Error)?.message ?? e).slice(0, 80)); }
    if (!r.ok) { try { await r.body?.cancel(); } catch { /* 버린다 */ } throw new ManualUnavailable(path + " — HTTP " + r.status); }
    try { return await r.text(); } catch (e) { throw new ManualUnavailable(path + " — body " + String((e as Error)?.message ?? e).slice(0, 80)); }
  };
  const files = chapterFiles(await get("README.md"), lang);
  if (!files.length) throw new ManualUnavailable("README.md — no chapters for " + lang);
  const texts = await Promise.all(files.map((f) => get(lang + "/" + f + ".md")));
  const sections = texts.flatMap((t, k) => splitChapter(t, files[k]));
  if (!sections.length) throw new ManualUnavailable("no sections for " + lang);
  const manual: Manual = { lang, files, sections };
  cache.set(lang, { at: d.now(), manual });
  return manual;
}

// ── 찾기 ──
const STOP = new Set(("a an the and or but if of to in on at by for with from into as is are was were be been do does did done can could should would will shall may might must have has had " +
  "i me my we our you your he she it its they them their this that these those there here what which who whom when where why how not no yes so than then too very just also about " +
  "ims please want need get got make use using").split(" "));
const isAscii = (s: string): boolean => /^[a-z0-9]+$/.test(s);
export function stem(w: string): string {
  if (!isAscii(w) || w.length < 4) return w;
  let s = w.replace(/(ing|ed|es|s)$/, (m) => (w.length - m.length >= 3 ? "" : m));
  if (s.length >= 4 && s[s.length - 1] === s[s.length - 2] && !/[aeiou]/.test(s[s.length - 1])) s = s.slice(0, -1);   // shipp → ship
  if (s.length >= 4 && s.endsWith("e")) s = s.slice(0, -1);                                            // finalize · finalized → finaliz
  return s;
}
export function tokenize(q: string): string[] {
  const out: string[] = [];
  for (const w of String(q).toLowerCase().slice(0, MANUAL_QUERY_MAX).split(/[^a-z0-9ㄱ-ㆎ가-힣]+/)) {
    if (!w || STOP.has(w) || (isAscii(w) && w.length < 2)) continue;
    const s = stem(w);
    if (!out.includes(s)) out.push(s);
  }
  return out;
}
const words = (s: string): string[] => s.toLowerCase().split(/[^a-z0-9ㄱ-ㆎ가-힣]+/).filter(Boolean);
// 낱말 하나가 토큰에 맞나 — 영문: 짧은 토큰(< 4)은 같아야 · 긴 토큰은 낱말이 그 줄기로 시작 · 한글: 포함
const wordHit = (w: string, t: string): boolean => (isAscii(t) ? (t.length < 4 ? w === t : w.startsWith(t)) : w.includes(t));
type Indexed = { s: Section; a: string[]; t: string[]; b: string[] };
const index = (s: Section): Indexed => ({ s, a: words(s.anchor), t: words(s.title), b: words(s.body) });
function score(x: Indexed, tokens: string[]): number {
  let total = 0, matched = 0;
  for (const t of tokens) {
    const inA = x.a.some((w) => wordHit(w, t)), inT = x.t.some((w) => wordHit(w, t));
    let c = 0; for (const w of x.b) if (wordHit(w, t)) { c++; if (c >= 5) break; }
    if (!inA && !inT && !c) continue;
    matched++; total += (inA ? 6 : 0) + (inT ? 5 : 0) + c + 4;
  }
  if (matched && matched === tokens.length) total += 6;
  return total;
}
export function snippet(body: string, tokens: string[]): string {
  const flat = body.replace(/\s+/g, " ").trim();
  if (flat.length <= MANUAL_SNIPPET) return flat;
  const low = flat.toLowerCase();
  let at = -1;
  for (const t of [...tokens].sort((p, q) => q.length - p.length)) {
    const re = isAscii(t) ? new RegExp("(^|[^a-z0-9])" + t + (t.length < 4 ? "($|[^a-z0-9])" : "")) : null;
    const i = re ? low.search(re) : low.indexOf(t);
    if (i >= 0) { at = i; break; }
  }
  let from = Math.max(0, at - 60);
  if (from > 0) { const sp = flat.indexOf(" ", from); if (sp >= 0 && sp < from + 30) from = sp + 1; }
  let to = Math.min(flat.length, from + MANUAL_SNIPPET);
  if (to < flat.length) { const sp = flat.lastIndexOf(" ", to); if (sp > from + 100) to = sp; }
  return (from > 0 ? "… " : "") + flat.slice(from, to) + (to < flat.length ? " …" : "");
}
const toc = (m: Manual) => m.sections.map((s) => ({ anchor: s.anchor, chapter: s.chapter, title: s.title }));
export function searchManual(m: Manual, query: string): Record<string, unknown> {
  const q = String(query ?? "").trim().slice(0, MANUAL_QUERY_MAX);
  const tokens = tokenize(q);
  const ranked = tokens.length ? m.sections.map((s, i) => ({ i, s, n: score(index(s), tokens) })).filter((x) => x.n > 0).sort((p, r) => r.n - p.n || p.i - r.i) : [];
  if (!ranked.length) {
    return { lang: m.lang, query: q, hits: [], note: "No section matched these words. Pick an anchor from 'contents' and call manual_read, or search again with other words (words that appear on the IMS screen work best; the manual language is '" + m.lang + "').", contents: toc(m) };
  }
  return { lang: m.lang, query: q, total_matches: ranked.length,
    hits: ranked.slice(0, MANUAL_MAX_HITS).map(({ s }) => ({ anchor: s.anchor, chapter: s.chapter, title: s.title, who: s.who, snippet: snippet(s.body, tokens), url: manualUrl(m.lang, s.anchor) })),
    note: "Excerpts only — call manual_read with the anchor for the full steps before answering." };
}

// ── 읽기 ──
function lev(a: string, b: string): number {
  let prev = Array.from({ length: b.length + 1 }, (_, j) => j);
  for (let i = 1; i <= a.length; i++) {
    const cur = [i];
    for (let j = 1; j <= b.length; j++) cur[j] = Math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
    prev = cur;
  }
  return prev[b.length];
}
export const cleanAnchor = (v: unknown): string => String(v ?? "").trim().toLowerCase().replace(/^.*#/, "").slice(0, 80);
export function similarAnchors(m: Manual, anchor: string, max = MANUAL_MAX_HITS): Section[] {
  const want = words(anchor);
  return m.sections.map((s, i) => {
    const a = words(s.anchor);
    const shared = want.filter((w) => a.includes(w)).length;
    const d = lev(anchor, s.anchor);
    return { s, i, n: shared * 10 + (s.anchor.includes(anchor) || (anchor.length >= 4 && anchor.includes(s.anchor)) ? 15 : 0) + Math.max(0, 8 - d) * 3 };
  }).filter((x) => x.n >= 10).sort((p, r) => r.n - p.n || p.i - r.i).slice(0, max).map((x) => x.s);
}
export function readManual(m: Manual, anchorIn: unknown): Record<string, unknown> {
  const anchor = cleanAnchor(anchorIn);
  const s = m.sections.find((x) => x.anchor === anchor);
  if (s) return { found: true, lang: m.lang, anchor: s.anchor, chapter: s.chapter, title: s.title, who: s.who, url: manualUrl(m.lang, s.anchor), body: s.body || "(This part of the manual is not written yet.)" };
  const c = similarAnchors(m, anchor);
  return { found: false, lang: m.lang, anchor, note: c.length ? "No section has this anchor. Similar anchors are in 'candidates' — call manual_read with one of them, or use manual_search." : "No section has this anchor and none is similar — use manual_search.",
    candidates: c.map((x) => ({ anchor: x.anchor, chapter: x.chapter, title: x.title })) };
}

// ── 도구의 run(문을 지난 뒤 _shared/mcp.ts 가 부른다) — JSON 글을 돌려준다 · 못 읽으면 ManualUnavailable 을 던진다 ──
export async function runManualSearch(a: Record<string, unknown>, d: ManualDeps): Promise<string> {
  return JSON.stringify(searchManual(await loadManual(d, manualLang(a.lang)), String(a.query ?? "")));
}
export async function runManualRead(a: Record<string, unknown>, d: ManualDeps): Promise<string> {
  return JSON.stringify(readManual(await loadManual(d, manualLang(a.lang)), a.anchor));
}
