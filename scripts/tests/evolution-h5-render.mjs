#!/usr/bin/env node
// EVO-054: 手机端 H5（app.js）执行级渲染测试。
//
// 为什么需要它：app.js 是一千多行的真实 UI 逻辑，此前只有 `appJS.contains("…")`
// 之类的字符串断言——把键名写对、但条件写反/分支写错，仍然只能靠人在真机上看。
// 这里用最小 DOM stub 在 node 里跑真实 app.js：注入 fixture 快照 → 走真实 fetch
// 回调 → 真实 refresh()/render() → 断言渲染进 DOM 的文字与 hidden 状态。
//
// 覆盖（每轮三个场景）：
//   A 完整 evolution       → 卡片可见 + 各行的真实文案/百分比/日期格式
//   B 点刷新后 evolution 消失 → 卡片与各行必须重新隐藏（防残留）
//   C evolution 在但漏斗/指标为空 → 仅这两行隐藏（EVO-053 的边界条件）
//
// 局限（有意）：stub 不解析 innerHTML，元素按 id 自动创建，所以这里测的是
// 「渲染逻辑与文案」，不测「骨架里是否有这个 id」——后者由 evolution-ui-assert.sh
// 的 marker 探针与 H5 骨架测试覆盖。
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const appJSPath = path.join(repoRoot, "Sources/TapgoCore/Resources/PhoneRemote/app.js");
const fixturePath = path.join(repoRoot, "evolution/h5-fixtures/evolution-state.json");

const appJS = fs.readFileSync(appJSPath, "utf8");
const fixture = JSON.parse(fs.readFileSync(fixturePath, "utf8"));

// ---------- 断言 ----------
let passed = 0;
let failed = 0;
const queue = [];
function check(label, ok, detail) {
  if (ok) {
    passed += 1;
    process.stdout.write(`  ✓ ${label}\n`);
  } else {
    failed += 1;
    process.stdout.write(`  ✗ ${label}${detail ? " — " + detail : ""}\n`);
  }
}
function checkEqual(label, actual, expected) {
  check(label, actual === expected, `期望 ${JSON.stringify(expected)}，实际 ${JSON.stringify(actual)}`);
}
function checkContains(label, haystack, needle) {
  check(label, typeof haystack === "string" && haystack.includes(needle),
    `期望包含 ${JSON.stringify(needle)}，实际 ${JSON.stringify(haystack)}`);
}

// ---------- 最小 DOM stub ----------
// hiddenByDefault 与真骨架一致：这些 id 在 HTML 里带 hidden 属性。
const HIDDEN_BY_DEFAULT = new Set([
  "evolutionCard", "evolutionMetrics", "evolutionRollback",
  "evolutionMaintenance", "evolutionFunnel",
]);

function makeElement(tag = "div") {
  const el = {
    tagName: String(tag).toUpperCase(),
    id: "", className: "", innerHTML: "", textContent: "", value: "", src: "", alt: "",
    hidden: false, disabled: false, loading: "", scrollTop: 0, scrollHeight: 0,
    dataset: {}, style: {}, children: [], handlers: {},
    classList: { add() {}, remove() {}, toggle() {}, contains() { return false; } },
    addEventListener(type, fn) { (el.handlers[type] ||= []).push(fn); },
    removeEventListener() {},
    dispatchEvent() { return true; },
    setAttribute() {}, getAttribute() { return null; }, removeAttribute() {},
    append(...nodes) { el.children.push(...nodes); },
    appendChild(node) { el.children.push(node); return node; },
    insertBefore(node) { el.children.push(node); return node; },
    removeChild() {}, remove() {},
    replaceChildren(...nodes) { el.children = nodes; },
    querySelector() { return null; }, querySelectorAll() { return []; },
    closest() { return null; }, focus() {}, blur() {}, click() {},
    getBoundingClientRect() { return { left: 0, top: 0, width: 100, height: 100 }; },
  };
  return el;
}

function makeDocument(registry) {
  const doc = {
    title: "",
    documentElement: makeElement("html"),
    body: makeElement("body"),
    getElementById(id) {
      if (!registry.has(id)) {
        const el = makeElement("div");
        el.id = id;
        el.hidden = HIDDEN_BY_DEFAULT.has(id);
        registry.set(id, el);
      }
      return registry.get(id);
    },
    createElement: (tag) => makeElement(tag),
    querySelector: () => null,
    querySelectorAll: () => [],
    addEventListener() {}, removeEventListener() {},
  };
  return doc;
}

// 用真实 app.js 跑一个上下文；payloads 按顺序供给连续 fetch（最后一次复用）。
function loadApp(payloads) {
  const registry = new Map();
  const documentStub = makeDocument(registry);
  let call = 0;
  const fetchStub = async () => {
    const payload = payloads[Math.min(call, payloads.length - 1)];
    call += 1;
    const text = JSON.stringify(payload);
    return { ok: true, status: 200, text: async () => text, json: async () => payload };
  };
  const sandbox = {
    document: documentStub,
    location: { pathname: "/r/fixture-token/", search: "", href: "http://127.0.0.1/r/fixture-token/" },
    localStorage: { getItem: () => null, setItem() {}, removeItem() {} },
    navigator: { userAgent: "node-h5-render-test", maxTouchPoints: 0 },
    fetch: fetchStub,
    URL, URLSearchParams, Blob,
    setTimeout, clearTimeout, setInterval: () => 0, clearInterval() {},
    requestAnimationFrame: () => 0, cancelAnimationFrame() {},
    matchMedia: () => ({ matches: false, addEventListener() {}, removeEventListener() {} }),
    addEventListener() {}, removeEventListener() {},
    confirm: () => true, alert() {}, console,
  };
  sandbox.window = sandbox;
  sandbox.__TAPGO_REMOTE__ = { root: "/r/fixture-token/", version: "test" };
  const context = vm.createContext(sandbox);
  vm.runInContext(appJS, context, { filename: appJSPath });
  const el = (id) => documentStub.getElementById(id);
  const clickRefresh = () => {
    const handler = (el("app").handlers.click || [])[0];
    if (!handler) return false;
    handler({ target: { closest: () => ({ dataset: { action: "refresh" } }) } });
    return true;
  };
  return { el, clickRefresh, payloadCalls: () => call };
}

const settle = async () => {
  for (let i = 0; i < 12; i += 1) await new Promise((resolve) => setTimeout(resolve, 0));
};

// ---------- 场景 A：完整 evolution ----------
async function scenarioFull() {
  process.stdout.write("[A] 完整 evolution → 卡片与各行渲染\n");
  const ctx = loadApp([fixture]);
  await settle();

  checkEqual("卡片可见", ctx.el("evolutionCard").hidden, false);
  checkEqual("卡片状态徽标", ctx.el("evolutionCard").dataset.status, "running");
  checkEqual("阶段文案（含进度与中文标签）", ctx.el("evolutionPhase").textContent, "7/9 三机部署");
  checkEqual("进度条宽度", ctx.el("evolutionBar").style.width, "78%");
  checkEqual("元信息（版本/benchmark/model/backlog）", ctx.el("evolutionMeta").textContent,
    "v0.5.999 · benchmark 100/100 · model 88/100 · backlog 3");
  checkEqual("下一项", ctx.el("evolutionNext").textContent, "下一项：EVO-999 下一项");

  const metrics = ctx.el("evolutionMetrics");
  checkEqual("指标行可见", metrics.hidden, false);
  checkContains("指标：周期 p95 分钟换算", metrics.textContent, "周期 p95 19m");
  checkContains("指标：MTTR 小时换算", metrics.textContent, "MTTR 24.0h");
  checkContains("指标：单轮时长", metrics.textContent, "单轮 8m");
  checkContains("指标：tokens", metrics.textContent, "tokens 12000");
  checkContains("指标：成本两位小数", metrics.textContent, "$1.25");
  checkContains("指标：本机 App 落后", metrics.textContent, "本机 App 落后 0.5.299");
  checkEqual("指标行漂移标记", metrics.dataset.stale, "yes");

  const funnel = ctx.el("evolutionFunnel");
  checkEqual("漏斗行可见", funnel.hidden, false);
  checkEqual("漏斗行文案（嵌套形状 + 百分比）", funnel.textContent,
    "反馈漏斗：drafts 2/5 · 注册 6 · 发布 5 · 转化 83%");

  const rollback = ctx.el("evolutionRollback");
  checkEqual("回滚行可见", rollback.hidden, false);
  checkEqual("回滚行文案", rollback.textContent, "回滚演练：PASS v0.5.307 · 2026-09-13 01:00:00");
  checkEqual("回滚行状态", rollback.dataset.state, "pass");

  const maintenance = ctx.el("evolutionMaintenance");
  checkEqual("维护行可见", maintenance.hidden, false);
  checkEqual("维护行文案", maintenance.textContent, "月度维护：PASS · 2026-09-13 02:00:00");
  checkEqual("维护行状态", maintenance.dataset.state, "pass");
}

// ---------- 场景 B：evolution 消失再回来 ----------
// 注意：evolution 为 null 时 renderEvolution 只把 card 置为 hidden 就返回，子行会
// 保留上一帧的 hidden=false/文案。这在真实 DOM 里是安全的——子行都在卡片子树内，
// 而 .evolution-card 无 author display 规则，[hidden] 由 UA 样式表生效，整棵子树不
// 渲染（见下面的 CSS 不变量断言）。所以这里断言用户可见语义（卡片隐藏）与
// 「数据回来时必须完整恢复」，而不是断言子行标志位（那会是假阳性）。
async function scenarioEvolutionGone() {
  process.stdout.write("[B] evolution 消失 → 卡片隐藏；数据回来 → 完整恢复\n");
  const withoutEvolution = { ...fixture, evolution: null };
  const ctx = loadApp([fixture, withoutEvolution, fixture]);
  await settle();
  checkEqual("首帧卡片可见", ctx.el("evolutionCard").hidden, false);
  checkEqual("首帧漏斗可见", ctx.el("evolutionFunnel").hidden, false);

  check("触发刷新按钮", ctx.clickRefresh(), "未捕获到 app 的 click 处理器");
  await settle();
  checkEqual("无 evolution 时卡片隐藏", ctx.el("evolutionCard").hidden, true);

  check("第二次刷新", ctx.clickRefresh(), "未捕获到 app 的 click 处理器");
  await settle();
  checkEqual("数据回来后卡片恢复", ctx.el("evolutionCard").hidden, false);
  checkEqual("数据回来后漏斗行恢复", ctx.el("evolutionFunnel").hidden, false);
  checkEqual("数据回来后漏斗文案正确", ctx.el("evolutionFunnel").textContent,
    "反馈漏斗：drafts 2/5 · 注册 6 · 发布 5 · 转化 83%");
  checkEqual("数据回来后指标行恢复", ctx.el("evolutionMetrics").hidden, false);
}

// ---------- 场景 C：漏斗/指标为空 ----------
async function scenarioEmptyRows() {
  process.stdout.write("[C] evolution 在但漏斗/指标为空 → 只隐藏这两行\n");
  const empty = JSON.parse(JSON.stringify(fixture));
  empty.evolution.funnel = {
    drafts: { total: 0, open: 0 },
    registered: { total: 0, shipped: 0 },
    conversion: {},
  };
  empty.evolution.metricsSummary = {};
  const ctx = loadApp([empty]);
  await settle();

  checkEqual("卡片仍可见", ctx.el("evolutionCard").hidden, false);
  checkEqual("空漏斗行隐藏", ctx.el("evolutionFunnel").hidden, true);
  checkEqual("空指标行隐藏", ctx.el("evolutionMetrics").hidden, true);
  checkEqual("回滚行不受影响", ctx.el("evolutionRollback").hidden, false);
}

// ---------- CSS 不变量：hidden 属性必须真的生效 ----------
// 上面的“卡片隐藏”依赖 [hidden] 的 UA 样式；一旦有人给这些选择器加上
// `display:`（例如为了布局改成 flex），空卡片/空行就会常驻可见。
function cssHiddenInvariant() {
  process.stdout.write("[D] CSS 不变量：hidden 行不得被 author display 覆盖\n");
  const cssPath = path.join(repoRoot, "Sources/TapgoCore/Resources/PhoneRemote/app.css");
  const css = fs.readFileSync(cssPath, "utf8");
  const guarded = ["evolution-card", "evolution-metrics", "evolution-rollback",
    "evolution-maintenance", "evolution-funnel"];
  const blocks = css.split("}");
  for (const name of guarded) {
    const offenders = blocks.filter((block) => {
      const open = block.indexOf("{");
      if (open < 0) return false;
      const selectors = block.slice(0, open).split(",").map((sel) => sel.trim());
      const targets = selectors.some((sel) => {
        const base = sel.replace(/\[[^\]]*\]/g, "").trim();
        return base === "." + name || base === "#" + name ||
          base.startsWith("." + name + " ") || base.startsWith("#" + name + " ");
      });
      if (!targets) return false;
      const body = block.slice(open + 1);
      return /(^|;)\s*display\s*:/.test(body);
    });
    check(`.${name} 无 author display 规则`, offenders.length === 0,
      offenders.length ? `命中 ${offenders.length} 处` : undefined);
  }
}

// ---------- 主流程 ----------
try {
  await scenarioFull();
  await scenarioEvolutionGone();
  await scenarioEmptyRows();
  cssHiddenInvariant();
} catch (error) {
  failed += 1;
  process.stdout.write(`  ✗ 未捕获异常：${error && error.stack ? error.stack : error}\n`);
}
process.stdout.write(`evolution-h5-render tests: ${passed} passed, ${failed} failed\n`);
process.exit(failed === 0 ? 0 : 1);
