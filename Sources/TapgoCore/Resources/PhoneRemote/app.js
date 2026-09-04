(() => {
  "use strict";

  const config = window.__TAPGO_REMOTE__ || {};
  const root = config.root || (location.pathname.endsWith("/") ? location.pathname : location.pathname + "/");
  const preview = new URLSearchParams(location.search).get("preview") === "1";
  const app = document.getElementById("app");
  const $ = (id) => document.getElementById(id);
  const state = {
    snapshot: null,
    lastJSON: "",
    failures: 0,
    mobileView: "home",
    expanded: new Set(),
    organizeBy: localStorage.getItem("tapgo-remote-organize") || "workspace",
    sortBy: localStorage.getItem("tapgo-remote-sort") || "updated",
    theme: localStorage.getItem("tapgo-remote-theme") || "system",
    busy: false,
    doubleClick: false,
    shotURL: null,
  };

  const mockState = {
    rev: 12,
    hostname: "Chenlaiyi 的 Mac",
    appVersion: "0.5.58",
    linkVersion: 3,
    activeId: "task-mobile",
    activeProjectId: "tapgo",
    model: "GLM-5.3",
    attachedCount: 0,
    control: { enabled: true, screenAllowed: true, accessibilityAllowed: true },
    projects: [
      { id: "tapgo", name: "TapgoAICoding", path: "/Users/chanlaiyi/TapgoAICoding", threadCount: 3, isLocal: true, lastActivityAt: Date.now() - 120000 },
      { id: "oct", name: "OctTapgo", path: "/Users/chanlaiyi/OctTapgo", threadCount: 2, isLocal: true, lastActivityAt: Date.now() - 86400000 },
      { id: "third", name: "Third", path: "/Users/chanlaiyi/Third", threadCount: 1, isLocal: false, lastActivityAt: Date.now() - 172800000 },
    ],
    threads: [
      { id: "task-mobile", title: "复刻 ZCode 移动端远程控制", updatedAt: Date.now() - 120000, turnCount: 3, busy: true, projectId: "tapgo" },
      { id: "task-login", title: "调整管理员登录界面", updatedAt: Date.now() - 5400000, turnCount: 8, busy: false, projectId: "tapgo" },
      { id: "task-update", title: "实现 GitHub 自动更新", updatedAt: Date.now() - 86400000, turnCount: 12, busy: false, projectId: "tapgo" },
      { id: "task-device", title: "净水器实时状态诊断", updatedAt: Date.now() - 90000000, turnCount: 7, busy: false, projectId: "oct" },
      { id: "task-version", title: "查询小程序和 App 当前版本", updatedAt: Date.now() - 160000000, turnCount: 4, busy: false, projectId: "oct" },
      { id: "task-finance", title: "流水与提现差异核对", updatedAt: Date.now() - 180000000, turnCount: 9, busy: false, projectId: "third" },
    ],
    transcript: [
      { id: "turn-1", user: "先完整复刻 ZCode 的 UI 和交互。", status: "completed", assistant: "", assistantHTML: "<p>已按 ZCode 的远程工作区结构整理桌面与移动端：桌面保持工作区侧栏和主会话，手机先进入任务首页，再进入聊天。</p>", userImageCount: 0, running: false },
      { id: "turn-2", user: "手机上要能切换项目、任务，也要能控制电脑。", status: "running", assistant: "", assistantHTML: "<p>项目、任务、聊天、附件和电脑控制都复用 Mac 端现有能力，旧二维码链接继续兼容。</p>", userImageCount: 0, running: true },
    ],
  };

  function applyTheme() {
    if (state.theme === "system") document.documentElement.removeAttribute("data-theme");
    else document.documentElement.setAttribute("data-theme", state.theme);
  }

  function cycleTheme() {
    state.theme = state.theme === "system" ? "light" : state.theme === "light" ? "dark" : "system";
    localStorage.setItem("tapgo-remote-theme", state.theme);
    applyTheme();
    toast(state.theme === "system" ? "主题：跟随系统" : state.theme === "light" ? "主题：浅色" : "主题：深色");
  }

  function buildShell() {
    app.innerHTML = `
      <div class="shell" id="shell" data-mobile-view="home">
        <aside class="sidebar" aria-label="工作区与任务">
          <div class="brand-row">
            <img class="app-icon" data-app-icon alt="Tapgo AICoding">
            <div class="brand-copy">
              <div class="brand-title">Tapgo AICoding</div>
              <div class="connection-line"><span class="status-dot" data-status-dot></span><span data-connection>正在连接</span></div>
            </div>
            <button class="icon-button theme-action" data-action="theme" aria-label="切换主题">主题</button>
          </div>
          <div class="sidebar-toolbar">
            <button class="ghost-button" data-action="new-active">新建任务</button>
            <button class="ghost-button" data-action="refresh">刷新</button>
          </div>
          <div class="sidebar-summary" id="desktopSummary">正在加载工作区…</div>
          <div class="workspace-list" id="desktopWorkspaces"></div>
        </aside>

        <section class="mobile-home" id="mobileHome" aria-label="远程工作区首页">
          <header class="mobile-home-header">
            <div class="mobile-home-title-row">
              <div class="brand-copy">
                <div class="mobile-home-title">远程工作区</div>
                <div class="mobile-connected" id="mobileConnected">正在连接 Mac…</div>
              </div>
              <button class="icon-button" data-action="theme" aria-label="切换主题">主题</button>
            </div>
          </header>
          <div class="mobile-home-scroll">
            <div class="notice-card">你正在通过手机远程访问这台 Mac。可以选择工作区和任务，或直接新建任务继续工作。</div>
            <div class="mobile-section-heading">
              <div>
                <div class="mobile-section-title">任务</div>
                <div class="mobile-section-summary" id="mobileSummary">正在加载…</div>
              </div>
              <div class="mobile-tools">
                <div class="segmented" aria-label="任务组织方式">
                  <button data-action="organize" data-value="workspace">工作区</button>
                  <button data-action="organize" data-value="timeline">时间</button>
                </div>
                <button class="icon-button" data-action="refresh">刷新</button>
              </div>
            </div>
            <div class="mobile-workspace-list" id="mobileWorkspaces"></div>
          </div>
        </section>

        <main class="main-view" id="mainView">
          <header class="chat-header">
            <button class="icon-button mobile-back" data-action="mobile-home">返回</button>
            <div class="chat-heading">
              <div class="chat-title" id="chatTitle">新建任务</div>
              <div class="chat-subtitle" id="chatSubtitle">等待工作区连接</div>
            </div>
            <div class="header-actions">
              <button class="icon-button theme-action" data-action="theme">主题</button>
              <button class="ghost-button control-action" data-action="control">电脑操作</button>
            </div>
          </header>
          <div class="chat-scroll" id="chatScroll">
            <div class="conversation" id="conversation"></div>
          </div>
        </main>

        <div class="composer-dock" id="composerDock">
          <div class="composer">
            <input class="hidden" type="file" id="fileInput" accept="image/*" multiple>
            <div class="attachment-strip hidden" id="attachmentStrip">
              <div class="attachment-thumbs" id="attachmentThumbs"></div>
              <span id="attachmentText"></span>
            </div>
            <textarea id="composerInput" rows="2" placeholder="提出后续修改要求" aria-label="消息输入"></textarea>
            <div class="composer-bar">
              <button class="icon-button" data-action="attach">添加</button>
              <button class="icon-button" data-action="control">电脑操作</button>
              <span class="busy-spinner hidden" id="busySpinner" aria-label="任务运行中"></span>
              <span class="composer-spacer"></span>
              <button class="icon-button model-button" data-action="model" id="modelButton">选择模型</button>
              <button class="primary-button send-button" data-action="send" id="sendButton" disabled>发送</button>
            </div>
          </div>
        </div>
      </div>
      <div class="overlay hidden" id="controlOverlay" role="dialog" aria-modal="true" aria-label="电脑操作"></div>
      <div class="sheet hidden" id="modelSheet" role="dialog" aria-modal="true" aria-label="选择模型"></div>
      <div class="toast hidden" id="toast" role="status"></div>`;

    document.querySelectorAll("[data-app-icon]").forEach((img) => { img.src = root + "assets/app-icon.png?v=" + config.version; });
    app.addEventListener("click", handleClick);
    $("composerInput").addEventListener("input", handleComposerInput);
    $("composerInput").addEventListener("keydown", handleComposerKeydown);
    $("fileInput").addEventListener("change", uploadFiles);
    $("controlOverlay").addEventListener("click", (event) => { if (event.target === $("controlOverlay")) closeControl(); });
    $("modelSheet").addEventListener("click", (event) => { if (event.target === $("modelSheet")) closeModelSheet(); });
  }

  function handleClick(event) {
    const target = event.target.closest("[data-action]");
    if (!target) return;
    const action = target.dataset.action;
    if (action === "theme") cycleTheme();
    else if (action === "refresh") refresh(true);
    else if (action === "mobile-home") showMobileHome();
    else if (action === "control") openControl();
    else if (action === "close-control") closeControl();
    else if (action === "model") openModelSheet();
    else if (action === "close-model") closeModelSheet();
    else if (action === "attach") $("fileInput").click();
    else if (action === "send") sendMessage();
    else if (action === "select-task") selectTask(target.dataset.id);
    else if (action === "new-task") newTask(target.dataset.projectId);
    else if (action === "new-active") newTask(state.snapshot?.activeProjectId || state.snapshot?.projects?.[0]?.id);
    else if (action === "toggle-workspace") toggleWorkspace(target.dataset.projectId);
    else if (action === "organize") setOrganize(target.dataset.value);
    else if (action === "screen") takeScreen();
    else if (action === "double") toggleDouble();
    else if (action === "control-key") control("key", { key: target.dataset.key });
    else if (action === "control-scroll") control("scroll", { dy: Number(target.dataset.delta) });
    else if (action === "control-type") typeToMac();
    else if (action === "control-command") runControlCommand(target.dataset.command);
  }

  function setConnection(kind, text) {
    document.querySelectorAll("[data-status-dot]").forEach((dot) => { dot.className = "status-dot " + kind; });
    document.querySelectorAll("[data-connection]").forEach((label) => { label.textContent = text; });
  }

  function ago(milliseconds) {
    const delta = Math.max(0, Date.now() - Number(milliseconds || 0));
    if (delta < 60000) return "刚刚";
    if (delta < 3600000) return Math.floor(delta / 60000) + " 分钟前";
    if (delta < 86400000) return Math.floor(delta / 3600000) + " 小时前";
    return Math.floor(delta / 86400000) + " 天前";
  }

  function taskStatus(thread) {
    if (thread.busy) return { key: "running", label: "运行中" };
    return { key: "completed", label: "已完成" };
  }

  function sortedThreads(threads) {
    return [...threads].sort((a, b) => Number(b.updatedAt || 0) - Number(a.updatedAt || 0));
  }

  function workspaceElement(project, threads, mobile) {
    const section = document.createElement("section");
    section.className = mobile ? "mobile-workspace" : "workspace-section";
    const open = state.expanded.has(project.id);

    const head = document.createElement("button");
    head.className = "workspace-head";
    head.dataset.action = "toggle-workspace";
    head.dataset.projectId = project.id;
    head.setAttribute("aria-expanded", String(open));
    const main = document.createElement("span");
    main.className = "workspace-main";
    const name = document.createElement("span");
    name.className = "workspace-name";
    name.textContent = project.name;
    const meta = document.createElement("span");
    meta.className = "workspace-meta";
    meta.textContent = (project.isLocal ? "本地" : "远程") + " · " + ago(project.lastActivityAt);
    main.append(name, meta);
    const count = document.createElement("span");
    count.className = "workspace-count";
    count.textContent = threads.length + " 个任务";
    head.append(main, count);
    section.appendChild(head);

    if (open) {
      const actions = document.createElement("div");
      actions.className = "workspace-actions";
      const add = document.createElement("button");
      add.className = "ghost-button";
      add.dataset.action = "new-task";
      add.dataset.projectId = project.id;
      add.textContent = "新建任务";
      actions.appendChild(add);
      section.appendChild(actions);

      const list = document.createElement("div");
      list.className = "task-list";
      if (!threads.length) {
        const empty = document.createElement("div");
        empty.className = "empty-state";
        empty.textContent = "这个工作区还没有任务";
        list.appendChild(empty);
      }
      sortedThreads(threads).forEach((thread) => list.appendChild(taskElement(thread, mobile)));
      section.appendChild(list);
    }
    return section;
  }

  function taskElement(thread, mobile) {
    const button = document.createElement("button");
    button.className = "task-row" + (thread.id === state.snapshot?.activeId ? " selected" : "");
    button.dataset.action = "select-task";
    button.dataset.id = thread.id;
    const copy = document.createElement("span");
    copy.className = "task-copy";
    const title = document.createElement("span");
    title.className = "task-title";
    title.textContent = thread.title || "未命名任务";
    const meta = document.createElement("span");
    meta.className = "task-meta";
    meta.textContent = (mobile ? activeProjectName(thread.projectId) + " · " : "") + ago(thread.updatedAt);
    copy.append(title, meta);
    const status = taskStatus(thread);
    const pill = document.createElement("span");
    pill.className = "status-pill " + status.key;
    pill.textContent = status.label;
    button.append(copy, pill);
    return button;
  }

  function activeProjectName(projectId) {
    return state.snapshot?.projects?.find((project) => project.id === projectId)?.name || "未分类";
  }

  function renderWorkspaces() {
    const snapshot = state.snapshot;
    if (!snapshot) return;
    const projects = snapshot.projects || [];
    const threads = snapshot.threads || [];
    $("desktopSummary").textContent = projects.length + " 个工作区 · " + threads.length + " 个任务";
    $("mobileSummary").textContent = threads.length + " 个任务 · " + projects.length + " 个工作区";
    $("mobileConnected").textContent = "已连接到 " + (snapshot.hostname || "Mac");

    const desktop = $("desktopWorkspaces");
    desktop.replaceChildren();
    projects.forEach((project) => desktop.appendChild(workspaceElement(project, threads.filter((thread) => thread.projectId === project.id), false)));

    const mobile = $("mobileWorkspaces");
    mobile.replaceChildren();
    if (!projects.length) {
      const empty = document.createElement("div");
      empty.className = "empty-state";
      empty.textContent = "暂无工作区，请先在 Mac 端添加项目。";
      mobile.appendChild(empty);
    } else if (state.organizeBy === "timeline") {
      const list = document.createElement("section");
      list.className = "mobile-workspace";
      const rows = document.createElement("div");
      rows.className = "task-list";
      sortedThreads(threads).forEach((thread) => rows.appendChild(taskElement(thread, true)));
      list.appendChild(rows);
      mobile.appendChild(list);
    } else {
      projects.forEach((project) => mobile.appendChild(workspaceElement(project, threads.filter((thread) => thread.projectId === project.id), true)));
    }
    document.querySelectorAll('[data-action="organize"]').forEach((button) => button.classList.toggle("active", button.dataset.value === state.organizeBy));
  }

  function renderConversation() {
    const snapshot = state.snapshot;
    if (!snapshot) return;
    const thread = snapshot.threads?.find((item) => item.id === snapshot.activeId);
    $("chatTitle").textContent = thread?.title || "新建任务";
    $("chatSubtitle").textContent = activeProjectName(thread?.projectId || snapshot.activeProjectId) + " · " + (snapshot.hostname || "Mac");
    $("modelButton").textContent = snapshot.model || "选择模型";
    document.title = (thread?.title || "远程工作区") + " · Tapgo";

    const conversation = $("conversation");
    conversation.replaceChildren();
    const turns = snapshot.transcript || [];
    if (!turns.length) {
      const greeting = document.createElement("div");
      greeting.className = "greeting";
      const inner = document.createElement("div");
      inner.className = "greeting-inner";
      const icon = document.createElement("img");
      icon.className = "app-icon";
      icon.src = root + "assets/app-icon.png?v=" + config.version;
      icon.alt = "Tapgo AICoding";
      const title = document.createElement("div");
      title.className = "greeting-title";
      const hour = new Date().getHours();
      title.textContent = hour < 11 ? "早上好" : hour < 13 ? "中午好" : hour < 18 ? "下午好" : "晚上好";
      const subtitle = document.createElement("div");
      subtitle.className = "greeting-subtitle";
      subtitle.textContent = "描述你想完成的任务，我会在这台 Mac 上继续工作。";
      inner.append(icon, title, subtitle);
      greeting.appendChild(inner);
      conversation.appendChild(greeting);
    }

    turns.forEach((turn) => {
      const group = document.createElement("article");
      group.className = "turn";
      if (turn.user) {
        const wrap = document.createElement("div");
        wrap.className = "user-message";
        const bubble = document.createElement("div");
        bubble.className = "user-bubble";
        bubble.textContent = turn.user;
        for (let index = 0; index < Number(turn.userImageCount || 0); index += 1) {
          const image = document.createElement("img");
          image.className = "message-image";
          image.loading = "lazy";
          image.alt = "附件图片";
          image.src = root + "img/" + encodeURIComponent(turn.id) + "/" + index;
          bubble.appendChild(image);
        }
        wrap.appendChild(bubble);
        group.appendChild(wrap);
      }
      if (turn.assistantHTML) {
        const answer = document.createElement("div");
        answer.className = "assistant-message";
        answer.innerHTML = turn.assistantHTML;
        group.appendChild(answer);
      }
      if (turn.running) {
        const label = document.createElement("span");
        label.className = "run-label pulse";
        label.textContent = turn.status === "awaitingApproval" ? "等待 Mac 上确认" : "正在工作";
        group.appendChild(label);
      } else if (turn.status === "failed" || turn.status === "interrupted") {
        const label = document.createElement("span");
        label.className = "error-label";
        label.textContent = turn.status === "failed" ? "任务失败" : "任务已中断";
        group.appendChild(label);
      }
      conversation.appendChild(group);
    });

    state.busy = Boolean(turns.at(-1)?.running);
    $("busySpinner").classList.toggle("hidden", !state.busy);
    $("sendButton").disabled = state.busy || !$("composerInput").value.trim();
    renderAttachments();
  }

  function render(snapshot) {
    const first = !state.snapshot;
    state.snapshot = snapshot;
    if (first) {
      const activeProject = snapshot.activeProjectId || snapshot.projects?.[0]?.id;
      if (activeProject) state.expanded.add(activeProject);
    }
    setConnection("online", "已连接 · " + (snapshot.hostname || "Mac"));
    renderWorkspaces();
    renderConversation();
  }

  function toggleWorkspace(projectId) {
    if (state.expanded.has(projectId)) state.expanded.delete(projectId);
    else state.expanded.add(projectId);
    renderWorkspaces();
  }

  function setOrganize(value) {
    if (value !== "workspace" && value !== "timeline") return;
    state.organizeBy = value;
    localStorage.setItem("tapgo-remote-organize", value);
    renderWorkspaces();
  }

  function showMobileHome() {
    state.mobileView = "home";
    $("shell").dataset.mobileView = "home";
    $("composerDock").classList.add("hidden");
  }

  function showChat() {
    state.mobileView = "chat";
    $("shell").dataset.mobileView = "chat";
    $("composerDock").classList.remove("hidden");
    requestAnimationFrame(() => { $("chatScroll").scrollTop = $("chatScroll").scrollHeight; });
  }

  async function request(path, options = {}) {
    if (preview) return { ok: true, json: async () => ({ ok: true }), blob: async () => new Blob() };
    const response = await fetch(root + path, options);
    if (!response.ok) {
      const error = new Error("HTTP " + response.status);
      error.status = response.status;
      error.response = response;
      throw error;
    }
    return response;
  }

  async function refresh(force = false) {
    if (preview) {
      render(mockState);
      return;
    }
    try {
      const response = await request("api/state", { cache: "no-store" });
      const text = await response.text();
      state.failures = 0;
      if (!force && text === state.lastJSON) return;
      state.lastJSON = text;
      render(JSON.parse(text));
    } catch (error) {
      state.failures += 1;
      setConnection("error", error.status === 403 ? "链接已失效" : "连接中断");
      if (!state.snapshot && state.failures >= 2) {
        $("desktopSummary").textContent = error.status === 403 ? "二维码已轮换，请重新扫码" : "无法连接 Mac，请检查网络";
        $("mobileSummary").textContent = $("desktopSummary").textContent;
      }
    }
  }

  async function selectTask(id) {
    if (!id) return;
    if (preview) {
      mockState.activeId = id;
      const selected = mockState.threads.find((thread) => thread.id === id);
      if (selected) mockState.activeProjectId = selected.projectId;
      render(mockState);
      showChat();
      return;
    }
    try {
      await request("api/select", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ threadId: id }) });
      state.lastJSON = "";
      showChat();
      await refresh(true);
    } catch { toast("切换任务失败，请稍后重试"); }
  }

  async function newTask(projectId) {
    if (!projectId) { toast("请先在 Mac 端添加工作区"); return; }
    if (preview) { toast("已创建新任务"); showChat(); return; }
    try {
      await request("api/new", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ projectId }) });
      state.lastJSON = "";
      showChat();
      await refresh(true);
    } catch { toast("新建任务失败，请稍后重试"); }
  }

  function handleComposerInput(event) {
    const input = event.currentTarget;
    input.style.height = "auto";
    input.style.height = Math.min(140, input.scrollHeight) + "px";
    $("sendButton").disabled = state.busy || !input.value.trim();
  }

  function handleComposerKeydown(event) {
    const mobile = window.matchMedia("(max-width: 767px)").matches;
    if (event.key !== "Enter" || event.isComposing) return;
    const submit = mobile ? (event.metaKey || event.ctrlKey) && !event.shiftKey : !event.shiftKey;
    if (submit) { event.preventDefault(); sendMessage(); }
  }

  async function sendMessage() {
    const input = $("composerInput");
    const text = input.value.trim();
    if (!text || state.busy) return;
    $("sendButton").disabled = true;
    if (preview) {
      toast("预览模式：消息交互正常");
      input.value = "";
      input.style.height = "auto";
      return;
    }
    try {
      await request("api/send", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ text }) });
      input.value = "";
      input.style.height = "auto";
      state.lastJSON = "";
      await refresh(true);
    } catch { toast("发送失败，请检查连接"); }
  }

  async function uploadFiles(event) {
    const files = [...(event.target.files || [])];
    event.target.value = "";
    if (!files.length) return;
    if (preview) { toast("预览模式：已选择 " + files.length + " 张图片"); return; }
    for (let index = 0; index < files.length; index += 1) {
      const file = files[index];
      $("attachmentStrip").classList.remove("hidden");
      $("attachmentText").textContent = "正在上传 " + (index + 1) + "/" + files.length;
      const dataURL = await new Promise((resolve) => {
        const reader = new FileReader();
        reader.onload = () => resolve(String(reader.result || ""));
        reader.onerror = () => resolve("");
        reader.readAsDataURL(file);
      });
      const data = dataURL.split(",")[1] || "";
      if (!data) continue;
      try {
        await request("api/attach", { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ name: file.name, data }) });
      } catch { toast(file.name + " 上传失败"); }
    }
    state.lastJSON = "";
    await refresh(true);
  }

  function renderAttachments() {
    const count = Number(state.snapshot?.attachedCount || 0);
    $("attachmentStrip").classList.toggle("hidden", count === 0);
    $("attachmentText").textContent = count ? "已添加 " + count + " 张图片" : "";
    const thumbs = $("attachmentThumbs");
    thumbs.replaceChildren();
    for (let index = 0; index < count; index += 1) {
      const image = document.createElement("img");
      image.className = "attachment-thumb";
      image.alt = "待发送附件";
      image.src = root + "pending/" + index;
      thumbs.appendChild(image);
    }
  }

  function openModelSheet() {
    const current = state.snapshot?.model || "当前模型";
    $("modelSheet").innerHTML = `<div class="sheet-card"><div class="sheet-title">选择模型</div><button class="model-row selected" type="button"></button><button class="ghost-button" data-action="close-model">关闭</button></div>`;
    $("modelSheet").querySelector(".model-row").textContent = current + " · 当前";
    $("modelSheet").classList.remove("hidden");
  }

  function closeModelSheet() { $("modelSheet").classList.add("hidden"); }

  function controlReady() {
    const controlState = state.snapshot?.control;
    return Boolean(controlState?.enabled && controlState?.accessibilityAllowed);
  }

  function screenReady() {
    const controlState = state.snapshot?.control;
    return Boolean(controlState?.enabled && controlState?.screenAllowed);
  }

  function controlBannerText() {
    const controlState = state.snapshot?.control;
    if (!controlState) return "当前 App 版本不支持电脑操作。";
    if (!controlState.enabled) return "Mac 端已关闭电脑操作，请在移动端远程控制窗口开启。";
    const missing = [];
    if (!controlState.screenAllowed) missing.push("屏幕录制");
    if (!controlState.accessibilityAllowed) missing.push("辅助功能");
    return missing.length ? "Mac 尚未授权：" + missing.join("、") + "。请在系统设置的隐私与安全性中授权 Tapgo AICoding。" : "";
  }

  function openControl() {
    const banner = controlBannerText();
    $("controlOverlay").innerHTML = `
      <section class="drawer">
        <header class="drawer-header"><div class="drawer-title">电脑操作</div><button class="icon-button" data-action="close-control">关闭</button></header>
        <div class="drawer-scroll">
          <div class="control-banner ${banner ? "" : "hidden"}" id="controlBanner"></div>
          <section class="control-card">
            <h2>屏幕</h2>
            <div class="control-row"><button class="primary-button" data-action="screen">截取屏幕</button><button class="ghost-button" data-action="double" id="doubleButton">双击模式：${state.doubleClick ? "开" : "关"}</button></div>
            <div class="screen-wrap"><img id="screenImage" alt="Mac 屏幕"><div class="screen-empty" id="screenEmpty">截取屏幕后，可以直接点按画面控制 Mac。</div></div>
            <div class="control-hint">点按画面会映射到 Mac 对应位置。双击模式仅影响下一次点按。</div>
          </section>
          <section class="control-card">
            <h2>滚动</h2>
            <div class="control-row"><button class="ghost-button" data-action="control-scroll" data-delta="-5">向上滚动</button><button class="ghost-button" data-action="control-scroll" data-delta="5">向下滚动</button></div>
          </section>
          <section class="control-card">
            <h2>键盘</h2>
            <textarea class="control-text" id="controlText" placeholder="输入要发送到 Mac 的文字"></textarea>
            <div class="control-row"><button class="primary-button" data-action="control-type">输入到 Mac</button></div>
            <div class="control-row"><button class="ghost-button" data-action="control-key" data-key="return">回车</button><button class="ghost-button" data-action="control-key" data-key="escape">Esc</button><button class="ghost-button" data-action="control-key" data-key="tab">Tab</button><button class="ghost-button" data-action="control-key" data-key="delete">删除</button></div>
            <div class="control-row"><button class="ghost-button" data-action="control-key" data-key="left">左</button><button class="ghost-button" data-action="control-key" data-key="up">上</button><button class="ghost-button" data-action="control-key" data-key="down">下</button><button class="ghost-button" data-action="control-key" data-key="right">右</button></div>
          </section>
          <section class="control-card">
            <h2>媒体</h2>
            <div class="control-row"><button class="ghost-button" data-action="control-key" data-key="volumeUp">音量增大</button><button class="ghost-button" data-action="control-key" data-key="volumeDown">音量减小</button><button class="ghost-button" data-action="control-key" data-key="mute">静音</button></div>
            <div class="control-row"><button class="ghost-button" data-action="control-key" data-key="brightnessUp">亮度增加</button><button class="ghost-button" data-action="control-key" data-key="brightnessDown">亮度降低</button><button class="ghost-button" data-action="control-key" data-key="playPause">播放暂停</button></div>
          </section>
          <section class="control-card">
            <h2>系统</h2>
            <div class="control-row"><button class="danger-button" data-action="control-command" data-command="lock">锁定 Mac</button><button class="danger-button" data-action="control-command" data-command="sleep">让 Mac 睡眠</button></div>
          </section>
        </div>
      </section>`;
    $("controlBanner").textContent = banner;
    $("controlOverlay").classList.remove("hidden");
    $("screenImage").addEventListener("click", clickScreen);
    $("controlOverlay").querySelectorAll("button:not([data-action='close-control'])").forEach((button) => {
      const allowed = button.dataset.action === "screen" ? screenReady() : controlReady();
      if (["double"].includes(button.dataset.action)) return;
      button.disabled = !allowed;
    });
  }

  function closeControl() { $("controlOverlay").classList.add("hidden"); }

  function toggleDouble() {
    state.doubleClick = !state.doubleClick;
    if ($("doubleButton")) $("doubleButton").textContent = "双击模式：" + (state.doubleClick ? "开" : "关");
  }

  async function control(endpoint, body) {
    if (preview) { toast("预览模式：电脑操作交互正常"); return true; }
    try {
      await request("api/ctrl/" + endpoint, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) });
      return true;
    } catch { toast("电脑操作失败，请检查 Mac 权限"); return false; }
  }

  async function takeScreen() {
    if (preview) { $("screenEmpty").textContent = "预览模式不读取真实 Mac 屏幕"; return; }
    try {
      const response = await request("api/ctrl/screen", { cache: "no-store" });
      const blob = await response.blob();
      if (state.shotURL) URL.revokeObjectURL(state.shotURL);
      state.shotURL = URL.createObjectURL(blob);
      $("screenImage").src = state.shotURL;
      $("screenImage").onload = () => $("screenEmpty").classList.add("hidden");
    } catch { $("screenEmpty").textContent = "截取屏幕失败，请检查 Mac 权限。"; }
  }

  async function clickScreen(event) {
    if (!controlReady() || !event.currentTarget.src) return;
    const rect = event.currentTarget.getBoundingClientRect();
    const x = (event.clientX - rect.left) / rect.width;
    const y = (event.clientY - rect.top) / rect.height;
    if (x < 0 || x > 1 || y < 0 || y > 1) return;
    if (await control("click", { x, y, double: state.doubleClick })) setTimeout(takeScreen, 600);
  }

  async function typeToMac() {
    const text = $("controlText")?.value || "";
    if (!text) return;
    if (await control("type", { text })) $("controlText").value = "";
  }

  async function runControlCommand(command) {
    const label = command === "sleep" ? "让 Mac 睡眠" : "锁定 Mac";
    if (confirm("确定要" + label + "吗？")) await control("cmd", { action: command });
  }

  let toastTimer = null;
  function toast(message) {
    const element = $("toast");
    element.textContent = message;
    element.classList.remove("hidden");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => element.classList.add("hidden"), 2200);
  }

  applyTheme();
  buildShell();
  if (window.matchMedia("(max-width: 767px)").matches) showMobileHome();
  else $("composerDock").classList.remove("hidden");
  refresh(true);
  if (!preview) setInterval(() => refresh(false), 2000);
})();
