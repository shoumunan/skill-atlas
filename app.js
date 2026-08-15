const icons = {
  atlas: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5.5 6.5 12 3l6.5 3.5v11L12 21l-6.5-3.5z"/><path d="m5.5 6.5 6.5 3.6 6.5-3.6M12 10.1V21"/></svg>`,
  overview: `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="3" width="7" height="7" rx="2"/><rect x="14" y="3" width="7" height="7" rx="2"/><rect x="3" y="14" width="7" height="7" rx="2"/><rect x="14" y="14" width="7" height="7" rx="2"/></svg>`,
  library: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 19.5V5a2 2 0 0 1 2-2h4v17H6.5A2.5 2.5 0 0 0 4 22v-2.5Z"/><path d="M10 5h8a2 2 0 0 1 2 2v13h-8a2 2 0 0 0-2 2V5Z"/></svg>`,
  guide: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a6 6 0 0 0-3.5 10.9c.9.7 1.5 1.4 1.5 2.6h4c0-1.2.6-1.9 1.5-2.6A6 6 0 0 0 12 3Z"/><path d="M10 20h4M10 17h4"/></svg>`,
  health: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="m8 12 2.5 2.5L16.5 8.5"/></svg>`,
  search: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/></svg>`,
  refresh: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M20 11a8 8 0 1 0-2.3 5.7"/><path d="M20 4v7h-7"/></svg>`,
  star: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 3 2.8 5.7 6.2.9-4.5 4.4 1.1 6.2-5.6-3-5.6 3 1.1-6.2L3 9.6l6.2-.9z"/></svg>`,
  copy: `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="8" y="8" width="11" height="11" rx="2"/><path d="M16 8V5a2 2 0 0 0-2-2H5a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h3"/></svg>`,
  folder: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M3 6a2 2 0 0 1 2-2h5l2 3h7a2 2 0 0 1 2 2v9a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2z"/></svg>`,
  arrow: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m9 18 6-6-6-6"/></svg>`,
  spark: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m12 2 1.7 5.3L19 9l-5.3 1.7L12 16l-1.7-5.3L5 9l5.3-1.7z"/><path d="m19 16 .8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z"/></svg>`,
  lock: `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="5" y="10" width="14" height="10" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/></svg>`,
};

/* Per-category glyph and tint, System Settings style: white glyph on a solid
   tinted squircle. Tints come from the Apple system palette. */
const categoryMeta = {
  "基金与投研": {tint: "#34c759", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 20h16"/><path d="m5.5 15.5 4-5 3.5 3L18.5 6"/><path d="M18.5 10V6H14"/></svg>`},
  "社交内容": {tint: "#ff375f", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M21 11.5c0 3.6-4 6.5-9 6.5-1 0-2-.1-2.9-.4L4 19l1.5-3.1C4.1 14.7 3 13.2 3 11.5 3 7.9 7 5 12 5s9 2.9 9 6.5Z"/></svg>`},
  "演示与文档": {tint: "#ff9500", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M7 3h7l4 4v13a1 1 0 0 1-1 1H7a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z"/><path d="M14 3v4h4"/><path d="M9.5 12.5h5M9.5 16h5"/></svg>`},
  "网页与自动化": {tint: "#0a84ff", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17"/><path d="M12 3.5c2.6 2.3 4 5.2 4 8.5s-1.4 6.2-4 8.5c-2.6-2.3-4-5.2-4-8.5s1.4-6.2 4-8.5Z"/></svg>`},
  "视觉与设计": {tint: "#bf5af2", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="m4 20 1-4L16.5 4.5a2.1 2.1 0 0 1 3 3L8 19l-4 1Z"/><path d="m14.5 6.5 3 3"/></svg>`},
  "数据与研究": {tint: "#32ade6", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-4-4"/><path d="M8.5 13.5v-2.5M11 13.5v-5M13.5 13.5v-3.5"/></svg>`},
  "沟通与运营": {tint: "#5e5ce6", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 10v4a1 1 0 0 0 1 1h2l5 4V5L7 9H5a1 1 0 0 0-1 1Z"/><path d="M15.5 9.5a3.5 3.5 0 0 1 0 5M18 7a7 7 0 0 1 0 10"/></svg>`},
  "开发与工具": {tint: "#555a60", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="3" y="4.5" width="18" height="15" rx="2.5"/><path d="m7.5 9.5 3 2.75-3 2.75M13 15.5h4"/></svg>`},
  "思考与协作": {tint: "#a2845e", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3a6 6 0 0 0-3.5 10.9c.9.7 1.5 1.4 1.5 2.6h4c0-1.2.6-1.9 1.5-2.6A6 6 0 0 0 12 3Z"/><path d="M10 20h4"/></svg>`},
  "通用工具": {tint: "#8e8e93", icon: `<svg viewBox="0 0 24 24" aria-hidden="true"><rect x="4" y="8" width="16" height="11" rx="2"/><path d="M9 8V6.5A2.5 2.5 0 0 1 11.5 4h1A2.5 2.5 0 0 1 15 6.5V8"/><path d="M4 13h16"/></svg>`},
};
const catMeta = (category) => categoryMeta[category] || categoryMeta["通用工具"];
const catIcon = (category, size = "") => `<span class="skill-icon ${size}" style="--tint:${catMeta(category).tint}">${catMeta(category).icon}</span>`;

const state = {
  data: null,
  selectedName: null,
  search: "",
  category: "全部",
  platform: "全部",
  health: "全部",
  nav: "library",
  favorites: new Set(JSON.parse(localStorage.getItem("skill-atlas-favorites") || "[]")),
  favoritesOnly: false,
  recommender: "",
  recommendations: [],
};

const app = document.querySelector("#app");
const escapeHtml = (value = "") => String(value).replace(/[&<>'"]/g, (char) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", "'": "&#39;", '"': "&quot;",
}[char]));
const formatTime = (timestamp) => timestamp ? new Date(timestamp * 1000).toLocaleDateString("zh-CN", {year: "numeric", month: "2-digit", day: "2-digit"}) : "未知";
const healthLabel = {healthy: "健康", warning: "警告", error: "异常"};
const mountLabel = {ok: "已挂载", disabled: "未启用", missing: "缺失", broken: "断链", wrong: "目标错误", directory: "普通目录", unexpected: "未启用但存在"};
const navOrder = ["overview", "library", "guide", "health"];

if (/SkillAtlasNative/i.test(navigator.userAgent)) {
  document.documentElement.classList.add("is-native");
}

function captureView() {
  const search = document.querySelector("#global-search");
  const recommend = document.querySelector("#recommend-form input");
  return {
    list: document.querySelector(".skill-list")?.scrollTop ?? 0,
    inspector: document.querySelector(".inspector-scroll")?.scrollTop ?? 0,
    main: document.querySelector(".main")?.scrollTop ?? 0,
    searchFocus: document.activeElement === search,
    searchStart: search?.selectionStart ?? null,
    searchEnd: search?.selectionEnd ?? null,
    recommendFocus: document.activeElement === recommend,
  };
}

function restoreView(view, {resetMain = false, resetList = false, keepInspector = true} = {}) {
  const list = document.querySelector(".skill-list");
  const inspector = document.querySelector(".inspector-scroll");
  const main = document.querySelector(".main");
  const search = document.querySelector("#global-search");
  const recommend = document.querySelector("#recommend-form input");
  if (list && !resetList) list.scrollTop = view.list;
  if (inspector && keepInspector) inspector.scrollTop = view.inspector;
  if (main) main.scrollTop = resetMain ? 0 : view.main;
  if (search && view.searchFocus) {
    search.focus();
    if (view.searchStart != null) search.setSelectionRange(view.searchStart, view.searchEnd);
  }
  if (recommend && view.recommendFocus) recommend.focus();
  const selected = document.querySelector(`[data-name="${CSS.escape(state.selectedName || "")}"]`);
  selected?.classList.add("selected");
  requestAnimationFrame(() => selected?.scrollIntoView({block: "nearest"}));
}

async function loadData({keepSelection = true} = {}) {
  if (location.protocol === "file:") {
    app.innerHTML = `<main class="fatal launch-help"><div>${icons.atlas}</div><h1>请从 Skill Atlas.app 启动</h1><p>这个 HTML 文件只是应用内部页面，直接打开不会启动 CC Switch 数据服务。</p><p class="launch-path">返回文件夹，双击 <strong>Skill Atlas.app</strong></p></main>`;
    return;
  }
  setScanning(true);
  try {
    const response = await fetch(`/api/skills?t=${Date.now()}`);
    const payload = await response.json();
    if (!response.ok) throw new Error(payload.error || "扫描失败");
    state.data = payload;
    const existing = keepSelection && payload.skills.find((skill) => skill.name === state.selectedName);
    state.selectedName = existing?.name || payload.skills.find((skill) => skill.name === "fund-content-creative")?.name || payload.skills[0]?.name;
    render();
  } catch (error) {
    app.innerHTML = `<main class="fatal"><div>${icons.health}</div><h1>无法读取 CC Switch</h1><p>${escapeHtml(error.message)}</p><button class="button glass-control primary" data-action="retry">重试</button></main>`;
  } finally {
    setScanning(false);
  }
}

function setScanning(isScanning) {
  document.querySelectorAll("[data-action='refresh']").forEach((button) => {
    button.classList.toggle("is-spinning", isScanning);
    button.disabled = isScanning;
  });
}

function filteredSkills() {
  if (!state.data) return [];
  const query = state.search.trim().toLowerCase();
  return state.data.skills.filter((skill) => {
    if (query && !skill.searchText.includes(query)) return false;
    if (state.category !== "全部" && skill.category !== state.category) return false;
    if (state.health !== "全部" && skill.health !== state.health) return false;
    if (state.platform !== "全部" && !skill.platforms.includes(state.platform)) return false;
    if (state.favoritesOnly && !state.favorites.has(skill.name)) return false;
    return true;
  });
}

function render(opts = {}) {
  if (!state.data) return;
  const view = captureView();
  app.innerHTML = `<div class="app-shell">${renderHeader()}${renderSidebar()}<main class="main">${renderSurface()}</main></div>`;
  restoreView(view, opts);
  if (!document.documentElement.classList.contains("booted")) {
    setTimeout(() => document.documentElement.classList.add("booted"), 850);
  }
}

function renderHeader() {
  const titles = {overview: "总览", library: "技能库", guide: "调用指南", health: "健康检查"};
  return `<header class="topbar">
    <div class="page-title"><strong>${titles[state.nav] || "Skill Atlas"}</strong></div>
    <label class="global-search glass-control">${icons.search}<input id="global-search" value="${escapeHtml(state.search)}" placeholder="搜索技能、用途或你想完成的事" aria-label="搜索技能"/><kbd>⌘ K</kbd></label>
    <div class="toolbar-actions"><button class="button glass-control refresh" data-action="refresh">${icons.refresh}<span>重新扫描</span></button></div>
  </header>`;
}

function renderSidebar() {
  const navItems = [
    ["overview", "总览", icons.overview], ["library", "技能库", icons.library],
    ["guide", "调用指南", icons.guide], ["health", "健康检查", icons.health],
  ];
  const scannedAt = new Date(state.data.summary.scannedAt).toLocaleTimeString("zh-CN", {hour: "2-digit", minute: "2-digit"});
  return `<aside class="sidebar">
    <div class="titlebar-spacer" aria-hidden="true"></div>
    <div class="brand-row"><span class="brand-mark">${icons.atlas}</span><strong>Skill Atlas</strong></div>
    <nav>${navItems.map(([id, label, icon], index) => `<button class="nav-item ${state.nav === id ? "active" : ""}" data-nav="${id}" aria-current="${state.nav === id ? "page" : "false"}">${icon}<span>${label}</span><kbd class="nav-key">⌘${index + 1}</kbd></button>`).join("")}</nav>
    <div class="sidebar-foot"><div class="readonly-status">${icons.lock}<span><strong>只读连接正常</strong><small>CC Switch 是唯一数据源</small></span></div><p>扫描于 ${scannedAt}</p></div>
  </aside>`;
}

function renderSurface() {
  if (state.nav === "overview") return renderOverview();
  if (state.nav === "guide") return renderGuide();
  if (state.nav === "health") return renderHealthPage();
  return renderLibrary();
}

function renderStats() {
  const {summary} = state.data;
  const counts = summary.health;
  const total = counts.healthy + counts.warning + counts.error || 1;
  const segment = (type, count) => count ? `<i class="${type}" style="width:${Math.max(4, count / total * 100)}%" title="${healthLabel[type]} ${count} 个"></i>` : "";
  const legend = (type, count) => `<button class="legend" data-health-jump="${type}" title="在技能库中筛选${healthLabel[type]}项"><span class="status-dot ${type}"></span>${healthLabel[type]} ${count}</button>`;
  return `<section class="stats-band panel-glass">
    <div class="metric"><strong>${summary.total}</strong><span>技能总数</span><small>CC Switch 管理</small></div>
    <div class="metric"><strong>${summary.verified.codex}</strong><span>Codex 已挂载</span><small>启用 ${summary.enabled.codex}</small></div>
    <div class="metric"><strong>${summary.verified.claude}</strong><span>Claude 已挂载</span><small>启用 ${summary.enabled.claude}</small></div>
    <div class="health-summary">
      <div class="health-summary-title"><strong>健康状态</strong><span>${Math.round(counts.healthy / total * 100)}% 健康</span></div>
      <div class="health-bar">${segment("healthy", counts.healthy)}${segment("warning", counts.warning)}${segment("error", counts.error)}</div>
      <div class="health-legend">${legend("healthy", counts.healthy)}${legend("warning", counts.warning)}${legend("error", counts.error)}</div>
    </div>
  </section>`;
}

function renderLibrary() {
  const skills = filteredSkills();
  const selected = state.data.skills.find((skill) => skill.name === state.selectedName) || skills[0];
  const categories = ["全部", ...new Set(state.data.skills.map((skill) => skill.category))];
  return `${renderStats()}
    <section class="workbench">
      <div class="skill-browser panel-glass">
        <div class="browser-tabs"><div class="segmented"><button class="tab ${!state.favoritesOnly ? "active" : ""}" data-favorites="all">全部技能</button><button class="tab ${state.favoritesOnly ? "active" : ""}" data-favorites="only">我的收藏 <span>${state.favorites.size}</span></button></div><span class="result-count">${skills.length} 项</span></div>
        <div class="filters">
          ${selectControl("category", "类别", categories, state.category)}
          ${selectControl("platform", "平台", ["全部", "Codex", "Claude", "GrokBuild"], state.platform)}
          ${selectControl("health", "健康", ["全部", "healthy", "warning", "error"], state.health, healthLabel)}
          <button class="text-button" data-action="clear-filters">清除</button>
        </div>
        <div class="skill-list" role="listbox">${skills.length ? skills.map(renderSkillRow).join("") : renderEmpty()}</div>
      </div>
      <div class="inspector panel-glass">${selected ? renderInspector(selected) : renderEmpty()}</div>
    </section>
    ${renderRecommender()}`;
}

function selectControl(id, label, options, value, labels = {}) {
  return `<label class="select-control ${value !== "全部" ? "is-active" : ""}"><span>${label}</span><select data-filter="${id}" aria-label="${label}">${options.map((option) => `<option value="${escapeHtml(option)}" ${option === value ? "selected" : ""}>${escapeHtml(labels[option] || option)}</option>`).join("")}</select></label>`;
}

function renderSkillRow(skill) {
  const isSelected = skill.name === state.selectedName;
  const isFavorite = state.favorites.has(skill.name);
  const flag = skill.health !== "healthy" ? `<em class="row-flag ${skill.health}" title="${escapeHtml(skill.problems.join("；"))}">${healthLabel[skill.health]}</em>` : "";
  return `<div class="skill-row ${isSelected ? "selected" : ""}" data-name="${escapeHtml(skill.name)}" role="option" aria-selected="${isSelected}" tabindex="${isSelected ? "0" : "-1"}">
    ${catIcon(skill.category)}
    <span class="skill-name"><span class="name-line"><strong>${escapeHtml(skill.name)}</strong>${flag}</span><small>${escapeHtml(shortDescription(skill.description))}</small></span>
    <span class="skill-trailing"><button type="button" class="favorite-icon ${isFavorite ? "active" : ""}" data-favorite="${escapeHtml(skill.name)}" aria-label="${isFavorite ? "取消收藏" : "收藏"} ${escapeHtml(skill.name)}">${icons.star}</button></span>
  </div>`;
}

function shortDescription(description) {
  const clean = description.replace(/\s+/g, " ").replace(/^(Use this skill|Use when|当任务|用于)/i, "").trim();
  return clean.length > 60 ? `${clean.slice(0, 60)}…` : clean;
}

function renderInspector(skill) {
  const isFavorite = state.favorites.has(skill.name);
  const statusClass = skill.health;
  return `<div class="inspector-head">
      ${catIcon(skill.category, "large")}<div><h2>${escapeHtml(skill.name)}</h2><p>${escapeHtml(skill.category)} · ${escapeHtml(skill.repo)}</p></div>
      <button class="icon-text glass-control ${isFavorite ? "active" : ""}" data-favorite="${escapeHtml(skill.name)}" aria-label="${isFavorite ? "取消收藏" : "收藏"} ${escapeHtml(skill.name)}">${icons.star}<span>${isFavorite ? "已收藏" : "收藏"}</span></button>
    </div>
    <div class="inspector-scroll">
      <section class="detail-section"><h3>用途 <span>它能帮你做什么</span></h3><p>${escapeHtml(skill.description)}</p></section>
      <section class="detail-section"><h3>什么时候调用</h3><p>${escapeHtml(skill.whenToUse)}</p></section>
      <section class="detail-section"><h3>示例说法 <span>可直接复制后修改</span></h3>
        <div class="prompt-list">${skill.examplePrompts.map((prompt) => `<div class="prompt"><span>“${escapeHtml(prompt)}”</span><button title="复制示例" data-copy="${escapeHtml(prompt)}">${icons.copy}</button></div>`).join("")}</div>
      </section>
      <section class="detail-section"><h3>支持平台</h3><div class="tags">${skill.platforms.length ? skill.platforms.map((platform) => `<span>${escapeHtml(platform)}</span>`).join("") : "<span>尚未启用</span>"}</div></section>
      <section class="detail-duo">
        <div><h3>安装位置</h3><code class="path-well" title="${escapeHtml(skill.sourcePath)}">${escapeHtml(skill.sourcePath)}</code><button class="button glass-control compact" data-open="${escapeHtml(skill.sourcePath)}">${icons.folder}<span>打开目录</span></button></div>
        <div><h3>挂载状态</h3>${renderMount("Codex", skill.mounts.codex)}${renderMount("Claude", skill.mounts.claude)}</div>
      </section>
      <section class="health-note ${statusClass}"><span class="status-dot ${statusClass}"></span><div><strong>${healthLabel[statusClass]}${skill.problems.length ? ` · ${skill.problems.length} 项需关注` : " · 未发现问题"}</strong><p>${skill.problems.length ? escapeHtml(skill.problems.join("；")) : `SKILL.md 可读，启用的挂载均指向 CC Switch 源目录。最近更新 ${formatTime(skill.updatedAt)}。`}</p></div></section>
    </div>`;
}

function renderMount(label, mount) {
  const type = mount.status === "ok" ? "healthy" : mount.status === "disabled" ? "neutral" : "error";
  return `<div class="mount-line"><span class="status-dot ${type}"></span><span><b>${label}</b><small>${mountLabel[mount.status] || mount.status}</small></span></div>`;
}

function renderRecommender() {
  return `<section class="assistant">
    ${state.recommendations.length ? `<div class="recommend-results panel-glass">${state.recommendations.map((entry, index) => `<button data-name="${escapeHtml(entry.skill.name)}"><b>${index + 1}</b><span><strong>${escapeHtml(entry.skill.name)}</strong><small>${escapeHtml(entry.reason)}</small></span>${icons.arrow}</button>`).join("")}</div>` : ""}
    <form id="recommend-form" class="assistant-bar">
      <span class="assistant-mark">${icons.spark}</span>
      <input value="${escapeHtml(state.recommender)}" placeholder="描述你的任务，我来推荐技能，例如：分析上周基金视频数据，再整理成 PPT" aria-label="描述任务"/>
      <button class="assistant-send" type="submit" aria-label="推荐技能">${icons.arrow}</button>
    </form>
  </section>`;
}

function renderOverview() {
  const byCategory = [...new Set(state.data.skills.map((skill) => skill.category))].map((category) => ({category, count: state.data.skills.filter((skill) => skill.category === category).length})).sort((a, b) => b.count - a.count);
  const recent = [...state.data.skills].sort((a, b) => b.installedAt - a.installedAt).slice(0, 8);
  return `${renderStats()}
    <section class="overview-grid">
      <div class="panel panel-glass">
        <div class="panel-head"><div><h2>技能版图</h2><p>按用途归类，点进去就是技能库。</p></div></div>
        <div class="category-tiles">${byCategory.map((item) => `<button class="tile" data-category-jump="${escapeHtml(item.category)}">${catIcon(item.category, "small")}<span class="tile-name">${escapeHtml(item.category)}</span><b>${item.count}</b></button>`).join("")}</div>
      </div>
      <div class="panel panel-glass">
        <div class="panel-head"><div><h2>最近安装</h2><p>按 CC Switch 的安装时间。</p></div></div>
        <div class="recent-list">${recent.map((skill) => `<button data-name="${escapeHtml(skill.name)}">${catIcon(skill.category, "small")}<span><strong>${escapeHtml(skill.name)}</strong><small>${escapeHtml(skill.category)}</small></span><time>${formatTime(skill.installedAt)}</time></button>`).join("")}</div>
      </div>
    </section>
    ${renderRecommender()}`;
}

function renderGuide() {
  const categories = [...new Set(state.data.skills.map((skill) => skill.category))];
  return `<section class="page-intro"><div><h1>调用指南</h1><p>你不必记住 Skill 名称。先从“我要做什么”出发，再选择合适的能力。</p></div><button class="button glass-control" data-nav="library">进入技能库</button></section>
    <section class="guide-layout">
      <div class="panel panel-glass assistant-panel"><h2>描述你的任务，我来推荐</h2><p>直接说目标、素材和交付格式，越具体越准。</p>${renderRecommender()}</div>
      <div class="guide-rules panel panel-glass"><h2>三个简单原则</h2>
      <ol><li><b>直接说任务。</b><span>明确目标、素材、时间范围和交付格式，系统会自动判断是否需要 Skill。</span></li><li><b>需要时可以点名。</b><span>例如“请使用 weekly-video-data 更新本周周报”，适合你已经知道工具的情况。</span></li><li><b>一个任务可以组合多个。</b><span>先采数据、再分析、最后做 PPT，通常会依次调用不同 Skill。</span></li></ol></div>
    </section>
    <section class="category-index"><h2>按任务类型找</h2><div class="tile-grid">${categories.map((category) => { const examples = state.data.skills.filter((skill) => skill.category === category).slice(0, 3); return `<button class="tile tall" data-category-jump="${escapeHtml(category)}">${catIcon(category, "small")}<span><strong>${escapeHtml(category)}</strong><small>${examples.map((skill) => skill.name).join(" / ")}</small></span><b>${state.data.skills.filter((skill) => skill.category === category).length}</b></button>`; }).join("")}</div></section>`;
}

function renderHealthPage() {
  const issues = state.data.skills.filter((skill) => skill.health !== "healthy");
  return `<section class="page-intro"><div><h1>健康检查</h1><p>核对源目录、SKILL.md 和已启用的 Codex / Claude 软连接。本页不会自动修复。</p></div></section>
    ${renderStats()}
    <section class="panel-glass health-panel"><div class="panel-head"><div><h2>需要关注的项目</h2><p>${issues.length ? `共发现 ${issues.length} 个 Skill 存在警告或异常。` : "当前没有发现警告或异常。"}</p></div><span class="readonly-badge">只读检查</span></div>
      <div class="issue-table">${issues.length ? issues.map((skill) => `<button data-name="${escapeHtml(skill.name)}">${catIcon(skill.category)}<span><strong>${escapeHtml(skill.name)}</strong><small>${escapeHtml(skill.problems.join("；"))}</small></span><em class="row-flag ${skill.health}">${healthLabel[skill.health]}</em>${icons.arrow}</button>`).join("") : `<div class="all-good">${icons.health}<strong>所有已检查项目都正常</strong><p>CC Switch 源目录与已启用的挂载相符。</p></div>`}</div>
    </section><section class="safety-note"><strong>为什么这里只检查，不直接修复？</strong><p>CC Switch 是 Skill 的唯一管理源。启用、停用或重新挂载应继续在 CC Switch 完成，避免面板与数据库各改一份。</p></section>`;
}

function renderEmpty() {
  if (state.favoritesOnly && !state.search && state.category === "全部" && state.platform === "全部" && state.health === "全部") {
    return `<div class="empty">${icons.star}<strong>还没有收藏</strong><p>把光标移到列表条目上点星标，或打开详情后收藏常用 Skill。</p></div>`;
  }
  return `<div class="empty">${icons.search}<strong>没有找到匹配的 Skill</strong><p>试试更短的关键词，或清除筛选条件。</p></div>`;
}

function moveSelection(delta) {
  const skills = filteredSkills();
  if (!skills.length) return;
  const current = skills.findIndex((skill) => skill.name === state.selectedName);
  const next = skills[Math.min(skills.length - 1, Math.max(0, (current < 0 ? 0 : current) + delta))];
  if (!next || next.name === state.selectedName) return;
  state.selectedName = next.name;
  render({keepInspector: false});
  document.querySelector(`[data-name="${CSS.escape(next.name)}"]`)?.focus();
}

function recommend(query) {
  const normalized = query.trim().toLowerCase();
  if (!normalized) return [];
  const aliases = {
    "基金": ["fund", "基金", "投教", "投研"], "视频": ["video", "视频", "抖音", "bilibili"],
    "周报": ["weekly", "report", "周报"], "ppt": ["ppt", "slide", "deck", "演示"],
    "网页": ["browser", "web", "网页", "chrome", "playwright"], "图片": ["image", "视觉", "设计", "illustration"],
    "文案": ["copy", "writer", "文案", "写作", "human"], "数据": ["data", "analytics", "数据", "excel"],
    "邮件": ["email", "gmail", "outlook", "邮件"], "小红书": ["xiaohongshu", "小红书", "xhs"],
  };
  const tokens = normalized.split(/[\s，。；、,.;:：]+/).filter((token) => token.length > 1);
  for (const [key, values] of Object.entries(aliases)) if (normalized.includes(key)) tokens.push(...values);
  return state.data.skills.map((skill) => {
    let score = 0;
    const matches = [];
    for (const token of new Set(tokens)) {
      if (skill.name.toLowerCase().includes(token)) { score += 8; matches.push(token); }
      else if (skill.description.toLowerCase().includes(token)) { score += 4; matches.push(token); }
      else if (skill.category.toLowerCase().includes(token)) { score += 2; matches.push(token); }
    }
    if (skill.health === "healthy") score += .5;
    return {skill, score, reason: matches.length ? `匹配：${[...new Set(matches)].slice(0, 4).join("、")}` : skill.whenToUse};
  }).filter((item) => item.score > .5).sort((a, b) => b.score - a.score).slice(0, 5);
}

function selectSkill(name) {
  const same = state.selectedName === name && state.nav === "library";
  state.selectedName = name;
  state.nav = "library";
  render({keepInspector: same});
}

document.addEventListener("click", async (event) => {
  const nav = event.target.closest("[data-nav]");
  if (nav) { state.nav = nav.dataset.nav; render({resetMain: true}); return; }
  const favorite = event.target.closest("[data-favorite]");
  if (favorite) {
    event.preventDefault(); event.stopPropagation();
    const name = favorite.dataset.favorite;
    state.favorites.has(name) ? state.favorites.delete(name) : state.favorites.add(name);
    localStorage.setItem("skill-atlas-favorites", JSON.stringify([...state.favorites]));
    render();
    return;
  }
  const row = event.target.closest("[data-name]");
  if (row) { selectSkill(row.dataset.name); return; }
  if (event.target.closest("[data-action='refresh']") || event.target.closest("[data-action='retry']")) { await loadData(); return; }
  if (event.target.closest("[data-action='clear-filters']")) { state.category = state.platform = state.health = "全部"; state.search = ""; render({resetList: true}); return; }
  const favoritesTab = event.target.closest("[data-favorites]");
  if (favoritesTab) { state.favoritesOnly = favoritesTab.dataset.favorites === "only"; render({resetList: true}); return; }
  const healthJump = event.target.closest("[data-health-jump]");
  if (healthJump) { state.health = healthJump.dataset.healthJump; state.nav = "library"; render({resetMain: true, resetList: true}); return; }
  const categoryJump = event.target.closest("[data-category-jump]");
  if (categoryJump) { state.category = categoryJump.dataset.categoryJump; state.nav = "library"; render({resetMain: true, resetList: true}); return; }
  const copy = event.target.closest("[data-copy]");
  if (copy) {
    await navigator.clipboard.writeText(copy.dataset.copy);
    const old = copy.innerHTML; copy.innerHTML = `<span class="copy-done">已复制</span>`; setTimeout(() => copy.innerHTML = old, 1100); return;
  }
  const open = event.target.closest("[data-open]");
  if (open) {
    const response = await fetch(`/api/open-folder?path=${encodeURIComponent(open.dataset.open)}`, {method: "POST"});
    if (!response.ok) alert((await response.json()).error || "无法打开目录");
  }
});

document.addEventListener("input", (event) => {
  if (event.target.id === "global-search") {
    state.search = event.target.value;
    const browser = document.querySelector(".skill-list");
    if (state.nav !== "library") { state.nav = "library"; render(); return; }
    if (browser) {
      const skills = filteredSkills();
      browser.innerHTML = skills.length ? skills.map(renderSkillRow).join("") : renderEmpty();
      document.querySelector(".result-count").textContent = `${skills.length} 项`;
    }
  }
});

document.addEventListener("change", (event) => {
  const filter = event.target.dataset.filter;
  if (filter) { state[filter] = event.target.value; render({resetList: true}); }
});

document.addEventListener("submit", (event) => {
  if (event.target.id !== "recommend-form") return;
  event.preventDefault();
  state.recommender = event.target.querySelector("input").value;
  state.recommendations = recommend(state.recommender);
  render();
});

document.addEventListener("keydown", (event) => {
  if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
    event.preventDefault();
    document.querySelector("#global-search")?.focus();
    return;
  }
  if ((event.metaKey || event.ctrlKey) && "1234".includes(event.key)) {
    event.preventDefault();
    state.nav = navOrder[Number(event.key) - 1];
    render({resetMain: true});
    return;
  }
  if (event.key === "Escape") {
    if (state.search) {
      state.search = "";
      render({resetList: true});
    }
    document.activeElement?.blur?.();
    return;
  }
  const typing = event.target.matches("input, select, textarea");
  if (typing) return;
  if (state.nav === "library" && (event.key === "ArrowDown" || event.key === "j")) {
    event.preventDefault();
    moveSelection(1);
    return;
  }
  if (state.nav === "library" && (event.key === "ArrowUp" || event.key === "k")) {
    event.preventDefault();
    moveSelection(-1);
  }
});

loadData({keepSelection: false});
