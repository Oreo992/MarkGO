# 思库（SiKu）M2 思考室 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现思考室三幕制全流程——Agent 辩论团基于用户 vault 互相交锋、用户当裁判下判决，产出分歧地图 + 判决书并沉淀回 vault。

**Architecture:** 思考室是服务端的**会话状态机**（`forming → positions_ready ⇄ clashing → probing → awaiting_final → closing → closed`，任意后台步骤失败进 `failed`）。每次 Agent 调用都是无状态单发 `AgentRunner.run()`（复用 M1 防护：maxTurns/模型可换），输出用 `<TAG>…</TAG>` 标记包裹的 JSON/Markdown 由纯函数解析。辩论 Agent 只读 vault；**判决书由代码确定性拼装（不经任何 Agent）——"结论只含用户观点"的铁律在代码层保证**。会话 JSON 持久化在 `/data/sessions/`，前端轮询。设计依据：spec 第 6 节。

**Tech Stack:** 沿用 M1——Node/TS + Express 5 + Agent SDK、vitest + supertest、Vite vanilla TS。无新增运行时依赖。

## Global Constraints

- 沿用 M1 计划的全部全局约束（`2026-07-07-siku-m1.md`），特别是 SPIKE-NOTES.md 的成本防护：每次 Agent 调用带 maxTurns；本计划各调用上限——组队 15 / 立论 15 / 反驳 10 / 教练 5 / 分歧地图 12 / 索引登记 15
- 辩论 Agent 并发上限 `SIKU_THINK_CONCURRENCY`（默认 2，服务器内存 7.5G 有限）；思考室模型可用 `SIKU_THINK_MODEL` 覆盖（默认继承主模型）
- 交锋默认 2 轮封顶（`MAX_CLASH_ROUNDS = 2`），加时需显式 `force`（对应 spec"教练可延长"）
- 铁律落实：立论/反驳 prompt 必须含"只读，禁止写入任何文件""立场必须锚定库内真实页面并给出出处""前两轮禁止让步认输"；判决书文件内容只来自用户输入的文字
- 自动化测试一律注入假 AgentRunner；真实 Agent 调用只在线上验收出现
- 所有会话内容（议题/立论/判决）为简体中文语境，prompt 要求中文输出
- **M2 范围决策（显式简化，非遗漏）**：spec 的"点将"与"喊停某条战线"在 M2 通过插话文字表达（反驳 prompt 要求辩手认真回应用户插话，点名即点将）；"各方一句话终陈"并入分歧地图（记录员整理各方核心主张）。三者的专属交互控件留 M3。spec 的"过去的判决作为一方立场登场"由组队 prompt 的「过去的你」规则实现

---

### Task 1: 提示词与解析器 prompts.ts

**Files:**
- Create: `E:\SiKu\server\src\think\prompts.ts`
- Test: `E:\SiKu\server\test\think-prompts.test.ts`

**Interfaces:**
- Consumes: `Debater`/`Statement`/`ThinkingSession` 类型（Task 2 定义；本任务先在测试里用字面量，类型 import 自 `./session.js`——Task 1 与 Task 2 需一起完成编译，故本任务 Step 3 同时创建最小 `session.ts` 类型文件，Task 2 再补 Store）
- Produces（Task 3/4 依赖）:
  - 常量 `PANEL_MAX_TURNS=15, POSITION_MAX_TURNS=15, REBUTTAL_MAX_TURNS=10, PROBE_MAX_TURNS=5, MAP_MAX_TURNS=12, INDEX_MAX_TURNS=15`
  - `panelPrompt(topic: string): string`、`positionPrompt(topic: string, d: Debater): string`、`rebuttalPrompt(topic: string, self: Debater, all: Debater[], statements: Statement[], interjections: Interjection[], round: number): string`、`probePrompt(topic: string, verdictDraft: string, statements: Statement[]): string`、`mapPrompt(s: ThinkingSession): string`、`indexPrompt(paths: string[], topic: string): string`
  - `parsePanel(text: string): { debaters: Debater[]; tier: "light" | "heavy" }`（解析 `<PANEL>` JSON；1-4 个辩手，非法抛错）
  - `parseStatement(text: string, debater: string, round: number, kind: "position" | "rebuttal"): Statement`（解析 `<POSITION>`/`<REBUTTAL>` JSON）
  - `parseProbe(text: string): string`（`<PROBE>` 纯文本）、`parseMap(text: string): string`（`<MAP>` Markdown）
  - `renderVerdictDoc(s: ThinkingSession): string`、`renderMapDoc(s: ThinkingSession, mapMd: string): string`（含 OKF frontmatter `type: thinking-artifact`）

- [ ] **Step 1: 写失败测试**

`E:\SiKu\server\test\think-prompts.test.ts`：
```ts
import { describe, expect, it } from "vitest";
import * as P from "../src/think/prompts.js";
import type { ThinkingSession } from "../src/think/session.js";

const debater = { name: "增长派", stance: "先拉新", anchors: ["concepts/闭环.md"] };

describe("prompt 铁律", () => {
  it("立论 prompt 含只读与锚定要求，要求中文", () => {
    const p = P.positionPrompt("怎么打闭环", debater);
    for (const kw of ["只读", "禁止", "锚定", "简体中文", "<POSITION>"]) expect(p).toContain(kw);
  });
  it("前两轮反驳 prompt 含禁止让步；第三轮不含", () => {
    const args = ["怎么打闭环", debater, [debater], [], [], 0] as const;
    expect(P.rebuttalPrompt(args[0], args[1], args[2], args[3], args[4], 1)).toContain("禁止让步");
    expect(P.rebuttalPrompt(args[0], args[1], args[2], args[3], args[4], 2)).toContain("禁止让步");
    expect(P.rebuttalPrompt(args[0], args[1], args[2], args[3], args[4], 3)).not.toContain("禁止让步");
  });
  it("反驳 prompt 携带用户插话", () => {
    const p = P.rebuttalPrompt("题", debater, [debater], [],
      [{ text: "你们都没考虑成本", atRound: 1, at: "2026-07-07T00:00:00Z" }], 2);
    expect(p).toContain("你们都没考虑成本");
  });
});

describe("解析器", () => {
  it("parsePanel 提取最后一个 PANEL 块", () => {
    const out = `思考过程...\n<PANEL>{"debaters":[{"name":"甲","stance":"A","anchors":["concepts/x.md"]},{"name":"乙","stance":"B","anchors":[]}],"tier":"heavy"}</PANEL>`;
    const panel = P.parsePanel(out);
    expect(panel.debaters).toHaveLength(2);
    expect(panel.tier).toBe("heavy");
  });
  it("parsePanel 对缺失块/坏 JSON/空辩手抛错", () => {
    expect(() => P.parsePanel("没有块")).toThrow();
    expect(() => P.parsePanel("<PANEL>{bad}</PANEL>")).toThrow();
    expect(() => P.parsePanel('<PANEL>{"debaters":[],"tier":"light"}</PANEL>')).toThrow();
  });
  it("parseStatement 解析立论", () => {
    const st = P.parseStatement(
      '<POSITION>{"text":"论点正文","cites":["concepts/闭环.md"]}</POSITION>', "甲", 0, "position");
    expect(st).toEqual({ debater: "甲", round: 0, kind: "position", text: "论点正文", cites: ["concepts/闭环.md"] });
  });
  it("parseStatement 解析带 target 的反驳", () => {
    const st = P.parseStatement(
      '<REBUTTAL>{"target":"乙","text":"反驳","cites":[]}</REBUTTAL>', "甲", 1, "rebuttal");
    expect(st.target).toBe("乙");
  });
  it("parseProbe / parseMap 提取文本", () => {
    expect(P.parseProbe("<PROBE>你的理由呢？</PROBE>")).toBe("你的理由呢？");
    expect(P.parseMap("<MAP># 分歧地图\n- 甲 vs 乙</MAP>")).toContain("分歧地图");
  });
});

describe("成品渲染（确定性，无 Agent）", () => {
  const session: ThinkingSession = {
    id: "s1", topic: "怎么打闭环", tier: "heavy", phase: "closing",
    debaters: [debater], statements: [
      { debater: "增长派", round: 0, kind: "position", text: "先拉新", cites: ["concepts/闭环.md"] },
    ],
    interjections: [], clashRound: 1,
    verdictDraft: "草稿", probe: "为什么？", verdict: "我的最终判决：留存优先，因为我的场景复购是生死线。",
    createdAt: "2026-07-07T10:00:00.000Z", updatedAt: "2026-07-07T11:00:00.000Z",
  };
  it("判决书只含用户文字与元数据，含 OKF frontmatter", () => {
    const doc = P.renderVerdictDoc(session);
    expect(doc).toContain("type: thinking-artifact");
    expect(doc).toContain("我的最终判决：留存优先");
    expect(doc).not.toContain("先拉新（增长派立论）"); // 不掺入 Agent 论点正文
  });
  it("分歧地图文档含 frontmatter 与地图正文及引用", () => {
    const doc = P.renderMapDoc(session, "# 地图正文");
    expect(doc).toContain("type: thinking-artifact");
    expect(doc).toContain("# 地图正文");
    expect(doc).toContain("[[concepts/闭环.md]]");
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /e/SiKu/server && npx vitest run test/think-prompts.test.ts`
Expected: FAIL（找不到 `../src/think/prompts.js`）

- [ ] **Step 3: 实现（含最小类型文件）**

`E:\SiKu\server\src\think\session.ts`（本任务只放类型；Store 在 Task 2 补入同文件）：
```ts
export type Phase =
  | "forming"
  | "positions_ready"
  | "clashing"
  | "probing"
  | "awaiting_final"
  | "closing"
  | "closed"
  | "failed";

export interface Debater {
  name: string;
  stance: string;
  anchors: string[];
}

export interface Statement {
  debater: string;
  round: number;
  kind: "position" | "rebuttal";
  target?: string;
  text: string;
  cites: string[];
}

export interface Interjection {
  text: string;
  atRound: number;
  at: string;
}

export interface ThinkingSession {
  id: string;
  topic: string;
  tier: "light" | "heavy";
  phase: Phase;
  debaters: Debater[];
  statements: Statement[];
  interjections: Interjection[];
  clashRound: number;
  verdictDraft?: string;
  probe?: string;
  verdict?: string;
  artifacts?: { mapPath: string; verdictPath: string };
  error?: string;
  createdAt: string;
  updatedAt: string;
}
```

`E:\SiKu\server\src\think\prompts.ts`：
```ts
// 思考室全部提示词与输出解析。纯函数，无 I/O。
// 铁律：辩论 Agent 只读 vault、观点必须锚定库内页面；判决书不经 Agent 拼装。
import type { Debater, Interjection, Statement, ThinkingSession } from "./session.js";

export const PANEL_MAX_TURNS = 15;
export const POSITION_MAX_TURNS = 15;
export const REBUTTAL_MAX_TURNS = 10;
export const PROBE_MAX_TURNS = 5;
export const MAP_MAX_TURNS = 12;
export const INDEX_MAX_TURNS = 15;

const READONLY = "你在本次任务中是只读角色：禁止写入、修改、删除任何文件。";

export function panelPrompt(topic: string): string {
  return (
    `${READONLY}\n用户要想清楚的议题：「${topic}」\n\n` +
    `请浏览这个知识库（从 wiki/index.md 与 wiki/hot.md 入手），为一场辩论组建 2-4 个立场互斥的辩手。` +
    `每个辩手的立场必须锚定库内真实存在的页面（给出 wiki 相对路径），库里没有依据的立场不许编造。` +
    `特别规则：若 wiki/thinking/ 中存在用户过往与本议题相关的判决书，必须组建一个名为「过去的你」的辩手，其立场取自该判决书并锚定它——让用户当年的结论接受今天的检验。` +
    `再按议题复杂度建议轻重分级：light（并排立论即可）或 heavy（值得多轮交锋）。\n\n` +
    `输出格式：最后一条消息以 <PANEL>{"debaters":[{"name":"...","stance":"...","anchors":["sources/x.md"]}],"tier":"light|heavy"}</PANEL> 结束，JSON 必须合法，全部内容用简体中文。`
  );
}

export function positionPrompt(topic: string, d: Debater): string {
  return (
    `${READONLY}\n你是辩手「${d.name}」，立场：${d.stance}。议题：「${topic}」\n\n` +
    `请阅读你的锚定页面（${d.anchors.join("、") || "自行在库内检索"}）及相关页面，写出 300-500 字的立论。` +
    `每个关键论点必须给出库内出处；库里没有的观点禁止编造。用简体中文。\n\n` +
    `输出格式：最后一条消息以 <POSITION>{"text":"立论正文","cites":["wiki相对路径"]}</POSITION> 结束，JSON 必须合法。`
  );
}

export function rebuttalPrompt(
  topic: string,
  self: Debater,
  all: Debater[],
  statements: Statement[],
  interjections: Interjection[],
  round: number
): string {
  const others = all.filter((d) => d.name !== self.name).map((d) => d.name);
  const transcript = statements
    .map((s) => `【${s.debater}·第${s.round}轮·${s.kind === "position" ? "立论" : `反驳${s.target ?? ""}`}】${s.text}`)
    .join("\n\n");
  const inter = interjections.length
    ? `\n\n用户（裁判）的插话，必须认真回应：\n${interjections.map((i) => `- ${i.text}`).join("\n")}`
    : "";
  const noConcede =
    round <= 2 ? "\n规则：本轮禁止让步认输、禁止表态同意对方——找出对方最薄弱的假设攻击它。" : "";
  return (
    `${READONLY}\n你是辩手「${self.name}」（立场：${self.stance}），议题：「${topic}」，现在是第 ${round} 轮交锋。\n\n` +
    `目前的辩论记录：\n${transcript}${inter}\n\n` +
    `请选择 ${others.join("/")} 中一方的最弱论点进行反驳，200-400 字；论据须锚定库内页面并给出出处，需要时可检索库内其他页面。${noConcede} 用简体中文。\n\n` +
    `输出格式：最后一条消息以 <REBUTTAL>{"target":"对方辩手名","text":"反驳正文","cites":["wiki相对路径"]}</REBUTTAL> 结束，JSON 必须合法。`
  );
}

export function probePrompt(topic: string, verdictDraft: string, statements: Statement[]): string {
  const digest = statements.map((s) => `【${s.debater}】${s.text.slice(0, 120)}`).join("\n");
  return (
    `你是这场辩论的教练（裁判长），从不给出自己的结论。议题：「${topic}」\n辩论摘要：\n${digest}\n\n` +
    `用户（最终裁判）的判决草稿：「${verdictDraft}」\n\n` +
    `你的唯一任务：检查这份判决是不是用户自己想清楚的。若它只是站队（如"我同意甲"）、理由空洞、或没有落到用户自己的场景，就提出一个最尖锐的追问逼用户说出自己的理由；若判决已经扎实，就问一个能让它更完整的问题。只输出一个问题，简体中文。\n\n` +
    `输出格式：最后一条消息以 <PROBE>你的问题</PROBE> 结束。`
  );
}

export function mapPrompt(s: ThinkingSession): string {
  const transcript = s.statements
    .map((t) => `【${t.debater}·第${t.round}轮】${t.text}（出处：${t.cites.join("、") || "无"}）`)
    .join("\n\n");
  const inter = s.interjections.map((i) => `- ${i.text}`).join("\n") || "（无）";
  return (
    `你是记录员。议题：「${s.topic}」。完整辩论记录：\n${transcript}\n\n用户插话：\n${inter}\n\n` +
    `请生成一份 Markdown「分歧地图」：各方核心主张、真正的交锋点（谁攻谁的哪个假设）、未决分歧、各方引用的库内页面（用 [[路径]] 格式）。` +
    `只整理辩论中出现过的内容，不添加你自己的观点或结论。简体中文。\n\n` +
    `输出格式：最后一条消息以 <MAP>markdown正文</MAP> 结束。`
  );
}

export function indexPrompt(paths: string[], topic: string): string {
  return (
    `请把以下新页面登记进 wiki/index.md（若有 Thinking 分区放入其中，否则新建），并在与议题「${topic}」相关的既有页面中酌情加入指向它们的 [[互链]]：\n` +
    paths.map((p) => `- wiki/${p}`).join("\n") +
    `\n只做索引与互链登记，不修改这些新页面的正文。完成后简述改动。简体中文。`
  );
}

function tagged(text: string, tag: string): string {
  const re = new RegExp(`<${tag}>([\\s\\S]*?)</${tag}>`, "g");
  let last: string | null = null;
  for (const m of text.matchAll(re)) last = m[1] ?? null;
  if (last === null) throw new Error(`输出缺少 <${tag}> 块`);
  return last.trim();
}

export function parsePanel(text: string): { debaters: Debater[]; tier: "light" | "heavy" } {
  const raw = JSON.parse(tagged(text, "PANEL")) as {
    debaters?: Debater[];
    tier?: string;
  };
  const debaters = (raw.debaters ?? []).filter((d) => d?.name && d?.stance);
  if (debaters.length < 1 || debaters.length > 4) throw new Error("辩手数量非法（需 1-4）");
  return {
    debaters: debaters.map((d) => ({ name: d.name, stance: d.stance, anchors: d.anchors ?? [] })),
    tier: raw.tier === "light" ? "light" : "heavy",
  };
}

export function parseStatement(
  text: string,
  debater: string,
  round: number,
  kind: "position" | "rebuttal"
): Statement {
  const tag = kind === "position" ? "POSITION" : "REBUTTAL";
  const raw = JSON.parse(tagged(text, tag)) as { target?: string; text?: string; cites?: string[] };
  if (!raw.text) throw new Error(`<${tag}> 缺少 text`);
  return {
    debater,
    round,
    kind,
    ...(raw.target ? { target: raw.target } : {}),
    text: raw.text,
    cites: raw.cites ?? [],
  };
}

export function parseProbe(text: string): string {
  return tagged(text, "PROBE");
}

export function parseMap(text: string): string {
  return tagged(text, "MAP");
}

function fm(title: string, s: ThinkingSession, extra: string[] = []): string {
  return [
    "---",
    "type: thinking-artifact",
    `title: ${JSON.stringify(title)}`,
    `topic: ${JSON.stringify(s.topic)}`,
    `session: ${s.id}`,
    `timestamp: ${s.updatedAt}`,
    ...extra,
    "---",
  ].join("\n");
}

// 判决书：正文只来自用户亲口所述（verdict / verdictDraft / 插话），不掺入任何 Agent 文字。
export function renderVerdictDoc(s: ThinkingSession): string {
  const inter = s.interjections.length
    ? `\n## 思考过程中我的插话\n\n${s.interjections.map((i) => `- ${i.text}`).join("\n")}\n`
    : "";
  return (
    `${fm(`判决书：${s.topic}`, s)}\n\n# 判决书：${s.topic}\n\n## 我的判决\n\n${s.verdict ?? ""}\n` +
    (s.verdictDraft && s.verdictDraft !== s.verdict
      ? `\n## 初稿（对照）\n\n${s.verdictDraft}\n`
      : "") +
    inter +
    `\n> 本文观点全部来自我本人；辩论各方论点见同期分歧地图。\n`
  );
}

export function renderMapDoc(s: ThinkingSession, mapMd: string): string {
  const cites = [...new Set(s.statements.flatMap((t) => t.cites))];
  const citeList = cites.length
    ? `\n## 引用的库内页面\n\n${cites.map((c) => `- [[${c}]]`).join("\n")}\n`
    : "";
  return `${fm(`分歧地图：${s.topic}`, s)}\n\n${mapMd}\n${citeList}`;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /e/SiKu/server && npx vitest run test/think-prompts.test.ts`
Expected: PASS（9 个用例）

- [ ] **Step 5: Commit**

```bash
cd /e/SiKu && git add server/src/think server/test/think-prompts.test.ts && git commit -m "feat(think): prompts, parsers, artifact renderers with guardrails"
```

---

### Task 2: 会话存储 SessionStore

**Files:**
- Modify: `E:\SiKu\server\src\think\session.ts`（追加 Store，类型已在 Task 1 就位）
- Test: `E:\SiKu\server\test\think-session.test.ts`

**Interfaces:**
- Produces: `class SessionStore`——`constructor(dir: string)`、`blank(topic: string): ThinkingSession`（id=UUID、phase="forming"、tier="heavy"、时间戳就绪）、`save(s: ThinkingSession): Promise<void>`（刷新 updatedAt，临时文件+rename 原子写）、`get(id: string): Promise<ThinkingSession | null>`、`list(): Promise<ThinkingSession[]>`（createdAt 倒序）

- [ ] **Step 1: 写失败测试**

`E:\SiKu\server\test\think-session.test.ts`：
```ts
import { mkdtemp } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { beforeEach, describe, expect, it } from "vitest";
import { SessionStore } from "../src/think/session.js";

let store: SessionStore;

beforeEach(async () => {
  store = new SessionStore(await mkdtemp(join(tmpdir(), "siku-think-")));
});

describe("SessionStore", () => {
  it("blank 生成合法初始会话", () => {
    const s = store.blank("怎么打闭环");
    expect(s.topic).toBe("怎么打闭环");
    expect(s.phase).toBe("forming");
    expect(s.clashRound).toBe(0);
    expect(s.id).toMatch(/[0-9a-f-]{36}/);
  });

  it("save/get 往返一致，get 未知 id 返回 null", async () => {
    const s = store.blank("题");
    s.debaters = [{ name: "甲", stance: "A", anchors: [] }];
    await store.save(s);
    const back = await store.get(s.id);
    expect(back?.debaters[0]?.name).toBe("甲");
    expect(await store.get("no-such")).toBeNull();
  });

  it("save 刷新 updatedAt", async () => {
    const s = store.blank("题");
    const before = s.updatedAt;
    await new Promise((r) => setTimeout(r, 5));
    await store.save(s);
    expect(s.updatedAt >= before).toBe(true);
  });

  it("list 按 createdAt 倒序", async () => {
    const a = store.blank("早");
    await store.save(a);
    await new Promise((r) => setTimeout(r, 5));
    const b = store.blank("晚");
    await store.save(b);
    const all = await store.list();
    expect(all.map((x) => x.topic)).toEqual(["晚", "早"]);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /e/SiKu/server && npx vitest run test/think-session.test.ts`
Expected: FAIL（SessionStore 未导出）

- [ ] **Step 3: 在 session.ts 末尾追加 Store 实现**

在 `E:\SiKu\server\src\think\session.ts` 顶部加 import，末尾追加：
```ts
import { mkdir, readFile, readdir, rename, writeFile } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";
```
```ts
export class SessionStore {
  constructor(private dir: string) {}

  blank(topic: string): ThinkingSession {
    const now = new Date().toISOString();
    return {
      id: randomUUID(),
      topic,
      tier: "heavy",
      phase: "forming",
      debaters: [],
      statements: [],
      interjections: [],
      clashRound: 0,
      createdAt: now,
      updatedAt: now,
    };
  }

  async save(s: ThinkingSession): Promise<void> {
    s.updatedAt = new Date().toISOString();
    await mkdir(this.dir, { recursive: true });
    const tmp = join(this.dir, `.${s.id}.tmp`);
    await writeFile(tmp, JSON.stringify(s, null, 2), "utf8");
    await rename(tmp, join(this.dir, `${s.id}.json`));
  }

  async get(id: string): Promise<ThinkingSession | null> {
    try {
      return JSON.parse(await readFile(join(this.dir, `${id}.json`), "utf8")) as ThinkingSession;
    } catch {
      return null;
    }
  }

  async list(): Promise<ThinkingSession[]> {
    let names: string[];
    try {
      names = await readdir(this.dir);
    } catch {
      return [];
    }
    const all: ThinkingSession[] = [];
    for (const n of names.filter((n) => n.endsWith(".json"))) {
      const s = await this.get(n.replace(/\.json$/, ""));
      if (s) all.push(s);
    }
    return all.sort((a, b) => (a.createdAt < b.createdAt ? 1 : -1));
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /e/SiKu/server && npx vitest run test/think-session.test.ts`
Expected: PASS（4 个用例）

- [ ] **Step 5: Commit**

```bash
cd /e/SiKu && git add server/src/think/session.ts server/test/think-session.test.ts && git commit -m "feat(think): session store with atomic writes"
```

---

### Task 3: 编排引擎 ThinkEngine

**Files:**
- Create: `E:\SiKu\server\src\think\engine.ts`
- Test: `E:\SiKu\server\test\think-engine.test.ts`

**Interfaces:**
- Consumes: Task 1 prompts、Task 2 SessionStore、M1 的 `Vault`（`wikiDir`、`commit`）与 `AgentRunner`
- Produces: `class PhaseError extends Error`（routes 映射 409）；`class ThinkEngine`——`constructor(store: SessionStore, vault: Vault, agent: AgentRunner, concurrency?: number)`、`create(topic: string): Promise<ThinkingSession>`、`clash(id: string, force?: boolean): Promise<void>`、`interject(id: string, text: string): Promise<void>`、`verdict(id: string, draft: string): Promise<void>`、`finalize(id: string, text: string): Promise<void>`、`idle(id: string): Promise<void>`（测试用）；常量 `MAX_CLASH_ROUNDS = 2`
- 后台任务失败 → 会话 `phase="failed"` + `error`，链不中断后续会话

- [ ] **Step 1: 写失败测试**

`E:\SiKu\server\test\think-engine.test.ts`：
```ts
import { mkdtemp, readFile, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { beforeEach, describe, expect, it } from "vitest";
import { Vault } from "../src/vault.js";
import { SessionStore } from "../src/think/session.js";
import { ThinkEngine, PhaseError, MAX_CLASH_ROUNDS } from "../src/think/engine.js";
import type { AgentRunner } from "../src/agent-types.js";

const run = promisify(execFile);
let vault: Vault;
let store: SessionStore;

// 按 prompt 中的输出格式标记分流的假 Agent
function fakeRunner(log: string[] = []): AgentRunner {
  return {
    run: async (prompt: string) => {
      log.push(prompt);
      if (prompt.includes("<PANEL>"))
        return '<PANEL>{"debaters":[{"name":"甲","stance":"A","anchors":["concepts/x.md"]},{"name":"乙","stance":"B","anchors":[]}],"tier":"light"}</PANEL>';
      if (prompt.includes("<POSITION>"))
        return '<POSITION>{"text":"立论","cites":["concepts/x.md"]}</POSITION>';
      if (prompt.includes("<REBUTTAL>"))
        return '<REBUTTAL>{"target":"乙","text":"反驳","cites":[]}</REBUTTAL>';
      if (prompt.includes("<PROBE>")) return "<PROBE>你的理由？</PROBE>";
      if (prompt.includes("<MAP>")) return "<MAP># 地图</MAP>";
      return "索引登记完成";
    },
  };
}

beforeEach(async () => {
  const root = await mkdtemp(join(tmpdir(), "siku-eng-"));
  await run("git", ["init"], { cwd: root });
  await run("git", ["config", "user.email", "t@t"], { cwd: root });
  await run("git", ["config", "user.name", "t"], { cwd: root });
  await mkdir(join(root, "wiki"), { recursive: true });
  vault = new Vault(root);
  store = new SessionStore(await mkdtemp(join(tmpdir(), "siku-ses-")));
});

describe("ThinkEngine 全流程", () => {
  it("create→立论→判决→逼宫→定稿→成品落盘并提交", async () => {
    const log: string[] = [];
    const engine = new ThinkEngine(store, vault, fakeRunner(log), 2);
    const s = await engine.create("怎么打闭环");
    await engine.idle(s.id);

    let cur = (await store.get(s.id))!;
    expect(cur.phase).toBe("positions_ready");
    expect(cur.debaters).toHaveLength(2);
    expect(cur.statements.filter((t) => t.kind === "position")).toHaveLength(2);
    expect(cur.tier).toBe("light");

    await engine.verdict(s.id, "我同意甲");
    await engine.idle(s.id);
    cur = (await store.get(s.id))!;
    expect(cur.phase).toBe("awaiting_final");
    expect(cur.probe).toBe("你的理由？");

    await engine.finalize(s.id, "留存优先，因为复购是我的生死线。");
    await engine.idle(s.id);
    cur = (await store.get(s.id))!;
    expect(cur.phase).toBe("closed");
    const verdictDoc = await readFile(join(vault.wikiDir, cur.artifacts!.verdictPath), "utf8");
    expect(verdictDoc).toContain("留存优先");
    expect(verdictDoc).not.toContain("立论"); // Agent 文字不进判决书
    const mapDoc = await readFile(join(vault.wikiDir, cur.artifacts!.mapPath), "utf8");
    expect(mapDoc).toContain("# 地图");
    const { stdout } = await run("git", ["log", "--oneline"], { cwd: vault.root });
    expect(stdout).toContain("think:");
    expect(log.some((p) => p.includes("wiki/index.md"))).toBe(true); // 索引登记跑过
  });

  it("交锋：轮次递增、封顶后需 force、插话进入下一轮 prompt", async () => {
    const log: string[] = [];
    const engine = new ThinkEngine(store, vault, fakeRunner(log), 2);
    const s = await engine.create("题");
    await engine.idle(s.id);

    await engine.interject(s.id, "你们都没考虑成本");
    await engine.clash(s.id);
    await engine.idle(s.id);
    let cur = (await store.get(s.id))!;
    expect(cur.clashRound).toBe(1);
    expect(cur.statements.filter((t) => t.kind === "rebuttal")).toHaveLength(2);
    expect(log.some((p) => p.includes("你们都没考虑成本"))).toBe(true);

    await engine.clash(s.id);
    await engine.idle(s.id);
    cur = (await store.get(s.id))!;
    expect(cur.clashRound).toBe(MAX_CLASH_ROUNDS);

    await expect(engine.clash(s.id)).rejects.toThrow(PhaseError);
    await engine.clash(s.id, true); // 加时
    await engine.idle(s.id);
    expect((await store.get(s.id))!.clashRound).toBe(3);
  });

  it("错误相位操作抛 PhaseError；后台失败进 failed", async () => {
    const bad: AgentRunner = { run: async () => "没有任何标记块" };
    const engine = new ThinkEngine(store, vault, bad, 2);
    const s = await engine.create("题");
    await engine.idle(s.id);
    const cur = (await store.get(s.id))!;
    expect(cur.phase).toBe("failed");
    expect(cur.error).toContain("PANEL");
    await expect(engine.verdict(s.id, "x")).rejects.toThrow(PhaseError);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /e/SiKu/server && npx vitest run test/think-engine.test.ts`
Expected: FAIL（找不到 `../src/think/engine.js`）

- [ ] **Step 3: 实现 engine.ts**

`E:\SiKu\server\src\think\engine.ts`：
```ts
import { mkdir, writeFile } from "node:fs/promises";
import { join } from "node:path";
import type { Vault } from "../vault.js";
import type { AgentRunner } from "../agent-types.js";
import { SessionStore, type ThinkingSession } from "./session.js";
import * as P from "./prompts.js";

export const MAX_CLASH_ROUNDS = 2;

export class PhaseError extends Error {}

export class ThinkEngine {
  private chains = new Map<string, Promise<void>>();

  constructor(
    private store: SessionStore,
    private vault: Vault,
    private agent: AgentRunner,
    private concurrency = Number(process.env.SIKU_THINK_CONCURRENCY ?? 2)
  ) {}

  private model(): string | undefined {
    return process.env.SIKU_THINK_MODEL;
  }

  // 每个会话一条后台任务链；任一任务失败把会话置为 failed，链保持可用
  private enqueue(id: string, job: () => Promise<void>): void {
    const prev = this.chains.get(id) ?? Promise.resolve();
    this.chains.set(
      id,
      prev.then(job).catch(async (err) => {
        const s = await this.store.get(id);
        if (s) {
          s.phase = "failed";
          s.error = String(err);
          await this.store.save(s);
        }
      })
    );
  }

  idle(id: string): Promise<void> {
    return this.chains.get(id) ?? Promise.resolve();
  }

  private async mustGet(id: string): Promise<ThinkingSession> {
    const s = await this.store.get(id);
    if (!s) throw new PhaseError("会话不存在");
    return s;
  }

  private async expectPhase(id: string, ...phases: string[]): Promise<ThinkingSession> {
    const s = await this.mustGet(id);
    if (!phases.includes(s.phase)) throw new PhaseError(`当前阶段 ${s.phase} 不允许此操作`);
    return s;
  }

  async create(topic: string): Promise<ThinkingSession> {
    const s = this.store.blank(topic);
    await this.store.save(s);
    this.enqueue(s.id, () => this.runForming(s.id));
    return s;
  }

  private async runForming(id: string): Promise<void> {
    const s = await this.mustGet(id);
    const panel = P.parsePanel(
      await this.agent.run(P.panelPrompt(s.topic), {
        maxTurns: P.PANEL_MAX_TURNS,
        model: this.model(),
      })
    );
    s.debaters = panel.debaters;
    s.tier = panel.tier;
    await this.store.save(s);

    const positions = await mapLimit(s.debaters, this.concurrency, async (d) =>
      P.parseStatement(
        await this.agent.run(P.positionPrompt(s.topic, d), {
          maxTurns: P.POSITION_MAX_TURNS,
          model: this.model(),
        }),
        d.name,
        0,
        "position"
      )
    );
    s.statements.push(...positions);
    s.phase = "positions_ready";
    await this.store.save(s);
  }

  async clash(id: string, force = false): Promise<void> {
    const s = await this.expectPhase(id, "positions_ready");
    if (s.clashRound >= MAX_CLASH_ROUNDS && !force)
      throw new PhaseError(`默认交锋 ${MAX_CLASH_ROUNDS} 轮已用完，加时需确认`);
    s.phase = "clashing";
    await this.store.save(s);
    this.enqueue(id, () => this.runClash(id));
  }

  private async runClash(id: string): Promise<void> {
    const s = await this.mustGet(id);
    const round = s.clashRound + 1;
    const rebuttals = await mapLimit(s.debaters, this.concurrency, async (d) =>
      P.parseStatement(
        await this.agent.run(
          P.rebuttalPrompt(s.topic, d, s.debaters, s.statements, s.interjections, round),
          { maxTurns: P.REBUTTAL_MAX_TURNS, model: this.model() }
        ),
        d.name,
        round,
        "rebuttal"
      )
    );
    s.statements.push(...rebuttals);
    s.clashRound = round;
    s.phase = "positions_ready";
    await this.store.save(s);
  }

  async interject(id: string, text: string): Promise<void> {
    const s = await this.expectPhase(id, "positions_ready", "clashing");
    s.interjections.push({ text, atRound: s.clashRound, at: new Date().toISOString() });
    await this.store.save(s);
  }

  async verdict(id: string, draft: string): Promise<void> {
    const s = await this.expectPhase(id, "positions_ready");
    s.verdictDraft = draft;
    s.phase = "probing";
    await this.store.save(s);
    this.enqueue(id, () => this.runProbe(id));
  }

  private async runProbe(id: string): Promise<void> {
    const s = await this.mustGet(id);
    s.probe = P.parseProbe(
      await this.agent.run(P.probePrompt(s.topic, s.verdictDraft ?? "", s.statements), {
        maxTurns: P.PROBE_MAX_TURNS,
        model: this.model(),
      })
    );
    s.phase = "awaiting_final";
    await this.store.save(s);
  }

  async finalize(id: string, text: string): Promise<void> {
    const s = await this.expectPhase(id, "awaiting_final");
    s.verdict = text;
    s.phase = "closing";
    await this.store.save(s);
    this.enqueue(id, () => this.runClosing(id));
  }

  private async runClosing(id: string): Promise<void> {
    const s = await this.mustGet(id);
    const mapMd = P.parseMap(
      await this.agent.run(P.mapPrompt(s), { maxTurns: P.MAP_MAX_TURNS, model: this.model() })
    );
    const stamp = s.createdAt.slice(0, 10);
    const slug = s.topic.replace(/[^\p{L}\p{N}]+/gu, "-").slice(0, 30) || "会话";
    const mapPath = `thinking/${stamp}-${slug}-分歧地图.md`;
    const verdictPath = `thinking/${stamp}-${slug}-判决书.md`;
    await mkdir(join(this.vault.wikiDir, "thinking"), { recursive: true });
    await writeFile(join(this.vault.wikiDir, mapPath), P.renderMapDoc(s, mapMd), "utf8");
    await writeFile(join(this.vault.wikiDir, verdictPath), P.renderVerdictDoc(s), "utf8");
    await this.agent.run(P.indexPrompt([mapPath, verdictPath], s.topic), {
      maxTurns: P.INDEX_MAX_TURNS,
      model: this.model(),
    });
    await this.vault.commit(`think: ${s.topic}`);
    s.artifacts = { mapPath, verdictPath };
    s.phase = "closed";
    await this.store.save(s);
  }
}

async function mapLimit<T, R>(items: T[], limit: number, fn: (t: T) => Promise<R>): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const workers = Array.from({ length: Math.max(1, Math.min(limit, items.length)) }, async () => {
    while (next < items.length) {
      const idx = next++;
      results[idx] = await fn(items[idx]!);
    }
  });
  await Promise.all(workers);
  return results;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `cd /e/SiKu/server && npx vitest run test/think-engine.test.ts`
Expected: PASS（3 个用例）

- [ ] **Step 5: Commit**

```bash
cd /e/SiKu && git add server/src/think/engine.ts server/test/think-engine.test.ts && git commit -m "feat(think): session state machine engine with cost guards"
```

---

### Task 4: REST 路由与应用装配

**Files:**
- Create: `E:\SiKu\server\src\think\routes.ts`
- Modify: `E:\SiKu\server\src\app.ts`（AppDeps 增加 think 依赖并挂载路由）
- Modify: `E:\SiKu\server\src\index.ts`（构造 SessionStore/ThinkEngine）
- Modify: `E:\SiKu\server\test\app.test.ts`（beforeEach 增加 think 依赖）
- Test: `E:\SiKu\server\test\think-routes.test.ts`

**Interfaces:**
- Produces REST（全部在既有认证中间件之后）：`POST /api/think {topic}` → `{id}`；`GET /api/think` → 摘要数组 `{id,topic,phase,tier,clashRound,createdAt}`；`GET /api/think/:id` → 完整会话；`POST /api/think/:id/clash {force?}` → `{ok}`；`POST /api/think/:id/interject {text}`；`POST /api/think/:id/verdict {draft}`；`POST /api/think/:id/final {text}`。PhaseError → 409，未知 id → 404，空参数 → 400
- `createApp` 签名变更：`AppDeps` 增加 `thinkEngine: ThinkEngine; sessionStore: SessionStore`

- [ ] **Step 1: 写失败测试**

`E:\SiKu\server\test\think-routes.test.ts`：
```ts
import { mkdtemp, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { beforeAll, beforeEach, describe, expect, it } from "vitest";
import request from "supertest";
import type { Express } from "express";
import type { AgentRunner } from "../src/agent-types.js";

const run = promisify(execFile);
let app: Express;
let engineIdle: (id: string) => Promise<void>;

const fake: AgentRunner = {
  run: async (prompt: string) => {
    if (prompt.includes("<PANEL>"))
      return '<PANEL>{"debaters":[{"name":"甲","stance":"A","anchors":[]}],"tier":"light"}</PANEL>';
    if (prompt.includes("<POSITION>")) return '<POSITION>{"text":"立论","cites":[]}</POSITION>';
    if (prompt.includes("<PROBE>")) return "<PROBE>理由？</PROBE>";
    if (prompt.includes("<MAP>")) return "<MAP># 图</MAP>";
    return "ok";
  },
};

beforeAll(() => {
  process.env.SIKU_PASSWORD = "test-pass";
  process.env.SIKU_SECRET = "test-secret";
});

beforeEach(async () => {
  const { Vault } = await import("../src/vault.js");
  const { Feed } = await import("../src/feed.js");
  const { IngestQueue } = await import("../src/queue.js");
  const { SessionStore } = await import("../src/think/session.js");
  const { ThinkEngine } = await import("../src/think/engine.js");
  const { createApp } = await import("../src/app.js");
  const root = await mkdtemp(join(tmpdir(), "siku-tr-"));
  await run("git", ["init"], { cwd: root });
  await run("git", ["config", "user.email", "t@t"], { cwd: root });
  await run("git", ["config", "user.name", "t"], { cwd: root });
  await mkdir(join(root, "wiki"), { recursive: true });
  const vault = new Vault(root);
  const feed = new Feed(join(root, "..", `feed-${Date.now()}-${Math.random()}.jsonl`));
  const queue = new IngestQueue(vault, feed, fake);
  const sessionStore = new SessionStore(await mkdtemp(join(tmpdir(), "siku-trs-")));
  const thinkEngine = new ThinkEngine(sessionStore, vault, fake, 2);
  engineIdle = (id) => thinkEngine.idle(id);
  app = createApp({ vault, feed, queue, agent: fake, thinkEngine, sessionStore });
});

async function login() {
  const res = await request(app).post("/api/login").send({ password: "test-pass" });
  return res.headers["set-cookie"]![0]!;
}

describe("think 路由", () => {
  it("未登录 401", async () => {
    expect((await request(app).get("/api/think")).status).toBe(401);
  });

  it("开题→列表→详情→判决→定稿全流程", async () => {
    const cookie = await login();
    const created = await request(app).post("/api/think").set("Cookie", cookie).send({ topic: "怎么打闭环" });
    expect(created.status).toBe(200);
    const id = created.body.id as string;
    await engineIdle(id);

    const list = await request(app).get("/api/think").set("Cookie", cookie);
    expect(list.body[0].topic).toBe("怎么打闭环");
    expect(list.body[0].phase).toBe("positions_ready");

    await request(app).post(`/api/think/${id}/verdict`).set("Cookie", cookie).send({ draft: "同意甲" });
    await engineIdle(id);
    const probing = await request(app).get(`/api/think/${id}`).set("Cookie", cookie);
    expect(probing.body.phase).toBe("awaiting_final");

    await request(app).post(`/api/think/${id}/final`).set("Cookie", cookie).send({ text: "我的结论与理由" });
    await engineIdle(id);
    const done = await request(app).get(`/api/think/${id}`).set("Cookie", cookie);
    expect(done.body.phase).toBe("closed");
    expect(done.body.artifacts.verdictPath).toContain("判决书");
  });

  it("空议题 400、未知 id 404、错误相位 409", async () => {
    const cookie = await login();
    expect((await request(app).post("/api/think").set("Cookie", cookie).send({})).status).toBe(400);
    expect((await request(app).get("/api/think/nope").set("Cookie", cookie)).status).toBe(404);
    const created = await request(app).post("/api/think").set("Cookie", cookie).send({ topic: "题" });
    const id = created.body.id as string;
    await engineIdle(id);
    // positions_ready 阶段直接 final 是错误相位
    const res = await request(app).post(`/api/think/${id}/final`).set("Cookie", cookie).send({ text: "x" });
    expect(res.status).toBe(409);
  });
});
```

- [ ] **Step 2: 跑测试确认失败**

Run: `cd /e/SiKu/server && npx vitest run test/think-routes.test.ts`
Expected: FAIL（routes 不存在 / createApp 不认 thinkEngine）

- [ ] **Step 3: 实现 routes.ts 并装配 app/index**

`E:\SiKu\server\src\think\routes.ts`：
```ts
import { Router } from "express";
import type { SessionStore } from "./session.js";
import { PhaseError, type ThinkEngine } from "./engine.js";

export function thinkRoutes(engine: ThinkEngine, store: SessionStore): Router {
  const r = Router();

  const guard = (fn: () => Promise<void>) => async (res: import("express").Response) => {
    try {
      await fn();
      res.json({ ok: true });
    } catch (err) {
      if (err instanceof PhaseError) res.status(409).json({ error: err.message });
      else throw err;
    }
  };

  r.post("/", async (req, res) => {
    const topic = String(req.body?.topic ?? "").trim();
    if (!topic) {
      res.status(400).json({ error: "议题为空" });
      return;
    }
    const s = await engine.create(topic);
    res.json({ id: s.id });
  });

  r.get("/", async (_req, res) => {
    const all = await store.list();
    res.json(
      all.map((s) => ({
        id: s.id,
        topic: s.topic,
        phase: s.phase,
        tier: s.tier,
        clashRound: s.clashRound,
        createdAt: s.createdAt,
      }))
    );
  });

  r.get("/:id", async (req, res) => {
    const s = await store.get(req.params.id);
    if (s) res.json(s);
    else res.status(404).json({ error: "会话不存在" });
  });

  r.post("/:id/clash", async (req, res) => {
    await guard(() => engine.clash(req.params.id, Boolean(req.body?.force)))(res);
  });

  r.post("/:id/interject", async (req, res) => {
    const text = String(req.body?.text ?? "").trim();
    if (!text) {
      res.status(400).json({ error: "插话为空" });
      return;
    }
    await guard(() => engine.interject(req.params.id, text))(res);
  });

  r.post("/:id/verdict", async (req, res) => {
    const draft = String(req.body?.draft ?? "").trim();
    if (!draft) {
      res.status(400).json({ error: "判决草稿为空" });
      return;
    }
    await guard(() => engine.verdict(req.params.id, draft))(res);
  });

  r.post("/:id/final", async (req, res) => {
    const text = String(req.body?.text ?? "").trim();
    if (!text) {
      res.status(400).json({ error: "判决为空" });
      return;
    }
    await guard(() => engine.finalize(req.params.id, text))(res);
  });

  return r;
}
```

`app.ts` 修改（AppDeps 与挂载；两处）：
```ts
// import 区新增
import { thinkRoutes } from "./think/routes.js";
import type { ThinkEngine } from "./think/engine.js";
import type { SessionStore } from "./think/session.js";

// AppDeps 改为
export interface AppDeps {
  vault: Vault;
  feed: Feed;
  queue: IngestQueue;
  agent: AgentRunner;
  thinkEngine: ThinkEngine;
  sessionStore: SessionStore;
}

// createApp 解构改为 { vault, feed, queue, agent, thinkEngine, sessionStore }
// 在 app.get("/api/resolve", ...) 之后、return app 之前挂载：
app.use("/api/think", thinkRoutes(thinkEngine, sessionStore));
```

`index.ts` 修改（构造与注入）：
```ts
// import 区新增
import { SessionStore } from "./think/session.js";
import { ThinkEngine } from "./think/engine.js";

// queue 之后新增
const sessionStore = new SessionStore(process.env.SESSIONS_DIR ?? join(vaultRoot, "..", "sessions"));
const thinkEngine = new ThinkEngine(sessionStore, vault, agent);
const app = createApp({ vault, feed, queue, agent, thinkEngine, sessionStore });
```

`test/app.test.ts` 修改：beforeEach 中 import SessionStore/ThinkEngine（照 think-routes.test.ts 的写法），`createApp({ vault, feed, queue, agent, thinkEngine, sessionStore })`。

- [ ] **Step 4: 跑全部测试与类型检查**

Run: `cd /e/SiKu/server && npx vitest run && npx tsc --noEmit`
Expected: 全部 PASS（M1 21 + think-prompts 9 + think-session 4 + think-engine 3 + think-routes 3 = 40 个用例），tsc 无错误

- [ ] **Step 5: Commit**

```bash
cd /e/SiKu && git add server && git commit -m "feat(think): REST routes + app wiring"
```

---

### Task 5: 前端——公共 md 渲染抽取 + 思考室列表/开题

**Files:**
- Create: `E:\SiKu\web\src\md.ts`（从 library.ts 抽取 mdToSafeHtml）
- Create: `E:\SiKu\web\src\views\think.ts`（列表 + 开题）
- Modify: `E:\SiKu\web\src\views\library.ts`（改用 md.ts）
- Modify: `E:\SiKu\web\src\main.ts`、`E:\SiKu\web\index.html`（导航加"思考室"）、`E:\SiKu\web\src\style.css`

**Interfaces:**
- Produces: `mdToSafeHtml(md: string): Promise<string>`（marked + wikilink + DOMPurify）；路由 `#/think`（列表+开题）、`#/think/<id>`（Task 6 的会话视图，本任务先放"加载中"占位函数 `renderThinkSession` 的真实现由 Task 6 提供——本任务 main.ts 直接引 Task 6 的模块名 `./views/think-session.js`，Task 6 未完成前先创建仅含加载文案的最小实现）

- [ ] **Step 1: 抽取 md.ts 并改造 library.ts**

`E:\SiKu\web\src\md.ts`：
```ts
import { marked } from "marked";
import DOMPurify from "dompurify";
import { renderWikilinks } from "./wikilink.js";

// vault 内容可能含剪藏网页带入的恶意 HTML，渲染前一律消毒
export async function mdToSafeHtml(md: string): Promise<string> {
  return DOMPurify.sanitize(renderWikilinks(await marked.parse(md)));
}
```
`library.ts`：删除文件内的 `mdToSafeHtml` 定义与 `marked`/`DOMPurify`/`renderWikilinks` import，改为 `import { mdToSafeHtml } from "../md.js";`

- [ ] **Step 2: 思考室列表视图**

`E:\SiKu\web\src\views\think.ts`：
```ts
import { api, el } from "../api.js";

interface SessionSummary {
  id: string;
  topic: string;
  phase: string;
  tier: string;
  clashRound: number;
  createdAt: string;
}

export const PHASE_LABEL: Record<string, string> = {
  forming: "组队立论中",
  positions_ready: "立论完毕，等你出招",
  clashing: "交锋进行中",
  probing: "教练审视判决中",
  awaiting_final: "等你最终判决",
  closing: "记录员整理成品",
  closed: "已结案",
  failed: "失败",
};

export function renderThink(root: HTMLElement): void {
  const view = el(`
    <section class="think">
      <form class="open-topic">
        <textarea rows="3" placeholder="你要想清楚什么事？比如：我的产品怎么打成闭环？"></textarea>
        <button type="submit">开一场思考</button>
      </form>
      <h2>思考会话</h2>
      <ul class="sessions"></ul>
    </section>
  `);
  const form = view.querySelector("form")!;
  const textarea = view.querySelector("textarea")!;
  const list = view.querySelector(".sessions")!;

  form.addEventListener("submit", async (e) => {
    e.preventDefault();
    const topic = textarea.value.trim();
    if (!topic) return;
    const { id } = await api<{ id: string }>("think", { topic });
    location.hash = `#/think/${id}`;
  });

  void (async () => {
    const sessions = await api<SessionSummary[]>("think");
    if (sessions.length === 0) {
      list.append(el(`<li class="empty">还没有思考会话。抛出第一个议题吧。</li>`));
      return;
    }
    for (const s of sessions) {
      const li = el(
        `<li><a href="#/think/${s.id}"><span class="topic"></span><span class="phase">${PHASE_LABEL[s.phase] ?? s.phase}</span></a></li>`
      );
      (li.querySelector(".topic") as HTMLElement).textContent = s.topic;
      list.append(li);
    }
  })();

  root.append(view);
}
```

- [ ] **Step 3: 路由与导航**

`index.html` 导航加一项：`<a href="#/think">思考室</a>`（放在图书馆之后）。
`main.ts`：
```ts
import "./style.css";
import { renderLogin } from "./views/login.js";
import { renderInbox } from "./views/inbox.js";
import { renderLibrary } from "./views/library.js";
import { renderThink } from "./views/think.js";
import { renderThinkSession } from "./views/think-session.js";

const app = document.getElementById("app")!;

function route(): void {
  const hash = location.hash || "#/inbox";
  app.replaceChildren();
  if (hash.startsWith("#/login")) renderLogin(app);
  else if (hash.startsWith("#/library/page/"))
    renderLibrary(app, decodeURIComponent(hash.slice("#/library/page/".length)));
  else if (hash.startsWith("#/library")) renderLibrary(app);
  else if (hash.startsWith("#/think/")) renderThinkSession(app, hash.slice("#/think/".length));
  else if (hash.startsWith("#/think")) renderThink(app);
  else renderInbox(app);
}

window.addEventListener("hashchange", route);
route();
```
`views/think-session.ts` 最小占位（Task 6 覆盖）：
```ts
export function renderThinkSession(root: HTMLElement, id: string): void {
  root.textContent = `会话 ${id} 加载中……`;
}
```
`style.css` 追加：
```css
.open-topic textarea { margin-bottom: 0.5rem; }
.sessions { list-style: none; padding: 0; }
.sessions li a { display: flex; justify-content: space-between; gap: 1rem; border: 1px solid #e7e5e4; border-radius: 8px; background: #fff; padding: 0.8rem; margin-bottom: 0.5rem; color: inherit; text-decoration: none; }
.sessions .phase { color: #78716c; font-size: 0.85rem; white-space: nowrap; }
```

- [ ] **Step 4: 验证与提交**

Run: `cd /e/SiKu/web && npx vitest run && npm run build`
Expected: wikilink 3 用例通过，build 成功

```bash
cd /e/SiKu && git add web && git commit -m "feat(web): think list view + shared md renderer"
```

---

### Task 6: 前端——思考会话三幕视图

**Files:**
- Modify: `E:\SiKu\web\src\views\think-session.ts`（完整实现替换占位）
- Modify: `E:\SiKu\web\src\style.css`

**Interfaces:**
- Consumes: Task 4 REST、Task 5 `mdToSafeHtml`/`PHASE_LABEL`、`api`/`el`
- 行为：活动相位（forming/clashing/probing/closing）每 4 秒轮询；`positions_ready` 显示立场卡片 + 三个动作（交锋一轮/插话/下判决）；交锋记录按轮分组显示；`awaiting_final` 显示教练追问 + 定稿框；`closed` 内嵌渲染判决书与分歧地图（走既有 `/api/page`）；`failed` 显示错误

- [ ] **Step 1: 完整实现 think-session.ts**

```ts
import { api, el } from "../api.js";
import { mdToSafeHtml } from "../md.js";
import { PHASE_LABEL } from "./think.js";

interface Statement {
  debater: string;
  round: number;
  kind: "position" | "rebuttal";
  target?: string;
  text: string;
  cites: string[];
}
interface Session {
  id: string;
  topic: string;
  tier: string;
  phase: string;
  debaters: { name: string; stance: string; anchors: string[] }[];
  statements: Statement[];
  interjections: { text: string }[];
  clashRound: number;
  probe?: string;
  verdictDraft?: string;
  artifacts?: { mapPath: string; verdictPath: string };
  error?: string;
}

const ACTIVE = new Set(["forming", "clashing", "probing", "closing"]);
const MAX_ROUNDS = 2;

export function renderThinkSession(root: HTMLElement, id: string): void {
  let timer: number | undefined;
  const stop = () => timer && clearInterval(timer);
  window.addEventListener("hashchange", stop, { once: true });

  async function tick(): Promise<void> {
    const s = await api<Session>(`think/${id}`);
    await draw(s);
    if (!ACTIVE.has(s.phase)) stop();
  }

  async function draw(s: Session): Promise<void> {
    root.replaceChildren();
    const head = el(
      `<header class="ts-head"><a href="#/think">← 思考室</a><h1></h1><p class="status">${PHASE_LABEL[s.phase] ?? s.phase}${s.tier === "light" ? " · 轻议题" : ""}</p></header>`
    );
    (head.querySelector("h1") as HTMLElement).textContent = s.topic;
    root.append(head);

    if (s.phase === "failed") {
      const box = el(`<p class="error"></p>`);
      box.textContent = `出错了：${s.error ?? "未知错误"}。可回列表重开一场。`;
      root.append(box);
      return;
    }

    if (ACTIVE.has(s.phase)) root.append(el(`<p class="working">⏳ ${PHASE_LABEL[s.phase]}……页面会自动刷新</p>`));

    // 第一幕：立场卡片
    if (s.debaters.length) {
      const cards = el(`<div class="cards"></div>`);
      for (const d of s.debaters) {
        const pos = s.statements.find((t) => t.kind === "position" && t.debater === d.name);
        const card = el(
          `<article class="card"><h3></h3><p class="stance"></p><div class="body"></div><p class="cites"></p></article>`
        );
        (card.querySelector("h3") as HTMLElement).textContent = d.name;
        (card.querySelector(".stance") as HTMLElement).textContent = d.stance;
        if (pos) (card.querySelector(".body") as HTMLElement).innerHTML = await mdToSafeHtml(pos.text);
        (card.querySelector(".cites") as HTMLElement).innerHTML = pos
          ? await mdToSafeHtml(pos.cites.map((c) => `[[${c}]]`).join(" "))
          : "";
        cards.append(card);
      }
      root.append(cards);
    }

    // 第二幕：交锋流（按轮分组）
    const rebuttals = s.statements.filter((t) => t.kind === "rebuttal");
    if (rebuttals.length) {
      const clash = el(`<div class="clash"><h2>交锋</h2></div>`);
      for (let r = 1; r <= s.clashRound; r++) {
        const roundBox = el(`<div class="round"><h4>第 ${r} 轮</h4></div>`);
        for (const t of rebuttals.filter((x) => x.round === r)) {
          const item = el(`<div class="turn"><strong></strong><div class="body"></div></div>`);
          (item.querySelector("strong") as HTMLElement).textContent = `${t.debater} → ${t.target ?? ""}`;
          (item.querySelector(".body") as HTMLElement).innerHTML = await mdToSafeHtml(t.text);
          roundBox.append(item);
        }
        clash.append(roundBox);
      }
      root.append(clash);
    }

    // 动作区
    if (s.phase === "positions_ready") {
      const over = s.clashRound >= MAX_ROUNDS;
      const act = el(`
        <div class="actions">
          <button class="clash-btn">${over ? "加时一轮（已超默认轮数）" : `交锋第 ${s.clashRound + 1} 轮`}</button>
          <form class="interject"><input placeholder="插话——你的发言会被辩手们认真回应" /><button>插话</button></form>
          <form class="verdict"><textarea rows="4" placeholder="下判决：你的结论是什么？为什么？（教练会追问）"></textarea><button>提交判决</button></form>
        </div>
      `);
      act.querySelector(".clash-btn")!.addEventListener("click", async () => {
        await api(`think/${id}/clash`, { force: over });
        void restart();
      });
      act.querySelector(".interject")!.addEventListener("submit", async (e) => {
        e.preventDefault();
        const input = act.querySelector(".interject input") as HTMLInputElement;
        if (!input.value.trim()) return;
        await api(`think/${id}/interject`, { text: input.value.trim() });
        input.value = "";
        void restart();
      });
      act.querySelector(".verdict")!.addEventListener("submit", async (e) => {
        e.preventDefault();
        const ta = act.querySelector(".verdict textarea") as HTMLTextAreaElement;
        if (!ta.value.trim()) return;
        await api(`think/${id}/verdict`, { draft: ta.value.trim() });
        void restart();
      });
      root.append(act);
    }

    // 第三幕：教练追问 + 定稿
    if (s.phase === "awaiting_final") {
      const fin = el(`
        <div class="final">
          <blockquote class="probe"></blockquote>
          <form><textarea rows="6"></textarea><button>确认最终判决</button></form>
        </div>
      `);
      (fin.querySelector(".probe") as HTMLElement).textContent = `教练：${s.probe ?? ""}`;
      const ta = fin.querySelector("textarea")!;
      ta.value = s.verdictDraft ?? "";
      fin.querySelector("form")!.addEventListener("submit", async (e) => {
        e.preventDefault();
        if (!ta.value.trim()) return;
        await api(`think/${id}/final`, { text: ta.value.trim() });
        void restart();
      });
      root.append(fin);
    }

    // 结案：内嵌成品
    if (s.phase === "closed" && s.artifacts) {
      for (const [label, path] of [
        ["判决书", s.artifacts.verdictPath],
        ["分歧地图", s.artifacts.mapPath],
      ] as const) {
        const box = el(`<article class="page"><h2>${label}</h2><div class="body">加载中……</div></article>`);
        root.append(box);
        const md = await api<string>(`page?path=${encodeURIComponent(path)}`);
        (box.querySelector(".body") as HTMLElement).innerHTML = await mdToSafeHtml(md);
      }
    }
  }

  async function restart(): Promise<void> {
    stop();
    await tick();
    timer = window.setInterval(() => void tick(), 4000);
  }

  void restart();
}
```

- [ ] **Step 2: 样式追加**

`style.css` 追加：
```css
.ts-head h1 { margin: 0.4rem 0 0.2rem; font-size: 1.3rem; }
.ts-head .status { color: #78716c; margin: 0; }
.working { color: #92400e; }
.cards { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: 0.8rem; margin-top: 1rem; }
.card { border: 1px solid #e7e5e4; border-radius: 8px; background: #fff; padding: 0.9rem 1rem; }
.card h3 { margin: 0 0 0.2rem; }
.card .stance { color: #78716c; font-size: 0.85rem; margin: 0 0 0.5rem; }
.card .cites { font-size: 0.85rem; }
.clash .round { border-left: 3px solid #d6d3d1; padding-left: 0.9rem; margin: 0.8rem 0; }
.clash .turn { margin-bottom: 0.7rem; }
.actions { position: sticky; bottom: 0; background: #faf9f7; padding: 0.8rem 0; border-top: 1px solid #e7e5e4; margin-top: 1.2rem; display: flex; flex-direction: column; gap: 0.5rem; }
.actions .interject { display: flex; gap: 0.5rem; }
.actions .interject input { flex: 1; margin-bottom: 0; }
.final .probe { border-left: 3px solid #92400e; margin: 1rem 0; padding: 0.5rem 0.9rem; background: #fff; }
```

- [ ] **Step 3: 验证与提交**

Run: `cd /e/SiKu/web && npx vitest run && npm run build`
Expected: 测试通过，build 成功

```bash
cd /e/SiKu && git add web && git commit -m "feat(web): thinking room three-act session view"
```

---

### Task 7: 部署与线上真实会话验收

**Files:**
- Create: `E:\SiKu\docs\M2-ACCEPTANCE.md`

**Interfaces:**
- Consumes: 全部前序任务；服务器 106.53.161.193 `/opt/siku/`（tssh.sh 模式连接）
- Produces: 线上 https://know.jeffreyai.cloud 思考室可用；M2 验收记录

- [ ] **Step 1: 上传部署**

```bash
cd /e/SiKu && git archive -o /tmp/siku-code.tar.gz HEAD
pscp -batch -hostkey "SHA256:m8UzKMJyxAavcvUu/sDU8k8jxdg0mCqnBUbp36FiPnI" -pwfile <scratchpad>/.tpw /tmp/siku-code.tar.gz root@106.53.161.193:/tmp/
bash tssh.sh 'rm -rf /opt/siku/app && mkdir -p /opt/siku/app && tar xzf /tmp/siku-code.tar.gz -C /opt/siku/app && rm /tmp/siku-code.tar.gz && cd /opt/siku/app && nohup docker compose build > /tmp/siku-build.log 2>&1 & echo BUILD_LAUNCHED'
# 轮询 /tmp/siku-build.log 到 "Built"（短连接、后台轮询，遵守 SPIKE-NOTES 规则），然后：
bash tssh.sh 'cd /opt/siku/app && docker compose up -d && sleep 4 && docker ps --filter name=siku --format "{{.Names}} {{.Status}}"'
```
预期：容器 Up。注意 sessions 目录随卷自动落在 `/opt/siku/data/sessions/`。

- [ ] **Step 2: 线上冒烟（API 级，一场轻会话）**

服务器端 curl：登录 → `POST /api/think {"topic":"思库 M2 上线后我第一个该优化什么？"}` → 轮询 `GET /api/think/:id` 至 `positions_ready`（预计 2-5 分钟，真实 Agent 组队+立论）→ 核对 debaters 立场锚定了库内页面 → `POST verdict` → 轮询至 `awaiting_final`，核对教练追问是中文且针对草稿 → `POST final` → 轮询至 `closed` → `GET /api/page?path=<verdictPath>` 核对判决书只含用户文字。任何一步失败：读 `docker logs siku` + 会话 JSON 的 error 字段修复后重试。

- [ ] **Step 3: 用户真实验收（M2 关账条件）**

用户在 https://know.jeffreyai.cloud 思考室用**一个真实产品决策**跑完整流程（含至少一轮交锋和一次插话），确认：① 辩手观点确实来自他的库（引用可点开）；② 交锋有真交锋而非车轱辘话；③ 教练追问逼出了他自己的理由；④ 判决书全是他自己的观点。四条都点头，M2 关账。

- [ ] **Step 4: 写验收记录并提交**

`E:\SiKu\docs\M2-ACCEPTANCE.md`：记录冒烟数据（各阶段耗时、token 量级）、用户四条验收结论、发现的问题清单。
```bash
cd /e/SiKu && git add docs/M2-ACCEPTANCE.md && git commit -m "docs: M2 acceptance record"
```
