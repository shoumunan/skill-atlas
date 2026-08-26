# Skill Atlas 2.0 · 融入 AI 工作流的优化方案（2026-08-26）

> 本文是战略论证。**可执行的完整实施方案（技术路线 + 数据契约 + 工作包 + 派发提示词）见 `PLAN.md`**，实施 agent 以 PLAN.md 为准。

一句话结论：Skill Atlas 的问题不是功能不够，而是**所有能力都朝着「人打开窗口」这一侧**，而技能的真实使用者是 agent、真实场景在终端会话里。方案的核心不是加页面，是把已经造好的引擎（安全扫描、触发模拟、描述处方、Hook 遥测、注册表）**换插座**：插到 agent 一侧和事件一侧。

---

## 0. 诊断：为什么它融不进 AI 使用场景（全部来自本机实测）

### 0.1 产品自己的历史已经证伪了「页面路线」

DESIGN.md 从 v7 到 v13 的演化轨迹：四个一级页 → 行动中心 + 协作工作台（v12）→ 塌缩到只剩「我的技能 / 设置」（v13）。每一轮重做都在回答同一个问题——「这个页面用户为什么要来」——而答案越来越诚实：**没有理由来**。「复制调用语 → 打开软件」这条核心桥，比用户在终端里直接打 `/hotspot` 慢；它是为一个不存在的用户设计的。

### 0.2 全量挂载是负资产，管理器在维护它而不是解决它

本机数据（2026-08-26）：

- 库内 134 个技能，108 个挂载到 Claude，name + description 合计 **约 2.8 万字符 ≈ 1.5–2 万 token**，**每个会话开场注入一次**。这是每天几十次会话都在交的隐形税。
- 使用高度集中：topic-daily 277 次、hotspot 56 次、docx 40 次——头部 10 个技能占掉大半使用量；**32 个技能从未被用过**；长尾大量 1–2 次。
- Profiles 功能已完整上线：能写 `skillOverrides` 到 `~/.claude/settings.json` 或项目级 `.claude/settings.local.json`（Profiles.swift），支持 off / user-invocable-only 两档排除和目录绑定。但本机 profiles.json 里 `bindings` 和 `activeAppliedKeys` 都是空的——**解决两万 token 税的完整机制已经建成，埋在设置→进阶的折叠组里，连作者自己都没用过一次**。
- 同样孤儿化的还有单技能沙箱试跑（Sandbox.swift + Store 里的完整流程）：代码全在、探针可跑，但界面上**没有任何一个按钮能到达它**。

### 0.3 遥测引擎造好了，连开发者自己都没启用

HookTelemetry.swift 是完成度很高的实现（PostToolUse 钩子、settings.json 备份、注入防护、永不阻塞），但本机 `~/.skill-atlas/hooks/` 是空的，`~/.claude/settings.json` 里没有 atlas 的钩子。使用统计仍靠事后扫 991 MB / 1200+ 个会话日志。**一个作者本人都不会顺手打开的功能，说明它放错了位置（设置深处的可选项），而不是没价值。**

### 0.4 挂载管道脆弱且已被现实击穿

本机 `~/.claude/skills` 和 `~/.agents/skills` 整个被另一个工具（mirasim）接管成软链，atlas 的挂载靠二级软链侥幸存活。路径级集成是别人一动就断的地基。

### 0.5 生态在 2026 年已经变了

- **Agent Skills 开放标准**（Anthropic，2025-12-18 发布）：30–40 个工具读同一份 SKILL.md、同一套目录（`~/.agents/skills` / 项目 `.agents/skills`）。
- **`npx skills`**（Vercel Labs）：add / find / list / update，支持 77+ agent，skills.sh 目录，免费。
- **同类 GUI 已成红海**：SkillDeck、至少三个不同作者的 Skills Manager、Electron 版 Skills Desktop（宣称 69 agent）——「中央库 + 软链到 N 个平台 + 开关矩阵」已经是商品化能力。
- Claude Code 原生已有 `/plugin marketplace`、项目级 `.claude/skills`、`disabledSkills`、`disable-model-invocation` 等管理原语。

**结论**：收纳 + 挂载不再是护城河。Skill Atlas 真正独有、且市场上没人做的资产是三样：**装前安全扫描 + diff 更新**、**会话日志级使用遥测**、**触发模拟与描述处方**。2.0 的全部投入应该压在把这三样接进真实工作流。

---

## 1. 重定位：从「技能收纳柜」到「技能供给与运维层」

用户不需要「管理技能的 App」，需要的是四个时刻各有一个动作：

| 时刻 | 用户真实需求 | 现状 | 2.0 |
|---|---|---|---|
| 装的时候 | 把关：安全、重复、触发冲突 | ✅ 已做（GUI 内） | 保持，扩到 CLI/agent 通道 |
| 用的时候 | **不用管**：对的技能在对的项目自动在场 | ❌ 全量灌 124 个 | 按项目/场景供给 |
| 出问题时 | **被告知**：触发失灵→一键修 | 引擎在，藏在设置→维护 | 事件驱动，主动找人 |
| 创作时 | 快速沉淀→验证触发→看产出 | 分散、无入口 | 工作台闭环 |

三个 surface，取代「页面」这个组织单位：

1. **Agent surface（新增，最重要）**：`atlas` CLI + 一个 meta-skill。agent 是一等用户——搜索、安装、启停、上报，都由会话里的 agent 直接调用，GUI 只在需要人批准时弹出。
2. **Ambient surface（升级）**：hook 事件 + 菜单栏 + 系统通知。App 的存在感来自「有事找你」，不是「等你来逛」。
3. **Workbench surface（收缩）**：主窗口 = 审批台（安全审阅、更新 diff）+ 调优台（触发/描述/成本）+ 盘点台（列表）。保持 v13 的两页导航，**不再新增任何一级页面**。

北极星指标随之更换。不再是打开次数/停留，而是：

- 每会话技能上下文成本（token）
- 触发命中率与 miss 修复闭环时长
- agent 经由 atlas 完成的操作数（搜/装/停/沉淀）

---

## 2. P0-A · Agent 通道：让 agent 成为一等用户

**这是「融入 AI 使用场景」四个字的直译。** 不是把人拉到 App 里，是把 App 的能力送进会话里。

### 2.1 `atlas` CLI（native 仓库加一个 SwiftPM executable target）

复用现有 Store / SecurityScan / TriggerLab / Registry 逻辑，全部命令支持 `--json`：

```
atlas list [--enabled claude] [--json]     # 库存与挂载状态
atlas search <关键词>                       # 本地库 + skills.sh 注册表
atlas info <name>                          # 描述、触发词、使用统计、安全状态
atlas install <github-url|owner/repo>      # 走既有装前扫描；关键级命中 → 非 0 退出
                                           #  + 深链 skillatlas://review/<id> 唤起 GUI 审阅
atlas enable|disable <name> [-p claude]    # 即现有软链开关
atlas simulate "<一句话任务>"               # TriggerLab：谁会抢答、第几名、命中词
atlas doctor [--json]                      # 挂载失败/安全命中/重叠，机器可读
atlas profile apply <name> [--project .]   # 见 P0-B
atlas new <name> [--from-clipboard]        # 见 P1-B
```

安全边界：CLI 永远不绕过安全扫描；「已核对来源仍要安装」这类破防动作只存在于 GUI 审阅页。**agent 提议、人批准、库执行**。

实现注记：install 复用 `InstallerModel.parse` 的既有护栏（仅 https://github.com，注册表只填仓库地址不猜子路径——Registry.swift 头注里砍完整版的理由在 CLI 时代依然成立）；深链需要给 App 补 `CFBundleURLTypes`（现在没有任何 URL scheme）；`--json` 输出可以直接从二十来个 `-atlasXProbe` 无头探针改造而来，验收基建现成。

### 2.2 meta-skill「skill-atlas」（成本半天，收益最大的一步）

一个由 App 自动挂载到所有平台的技能，SKILL.md 教 agent：什么时候调 `atlas search`（用户要的能力库里可能有）、什么时候调 `atlas install`（用户明确要装）、什么时候调 `atlas simulate`（用户抱怨技能没触发）、什么时候调 `atlas new`（用户说「把这套流程沉淀下来」）。

发布当天，所有平台的所有会话就都「认识」Skill Atlas 了——这就是融入，零 UI 改动。

### 2.3 MCP server（后置，可选）

stdio 包一层 CLI 即可。等 CLI 被 meta-skill 路线验证后再决定，不先投入。

**验收（沿用 DESIGN.md 人物验收风格）**：在 Claude Code 里说「帮我找个能画甘特图的技能装上」，agent 通过 atlas 完成搜索→安装→扫描→挂载，全程不开 GUI；换一个带 `curl | sh` 的恶意夹具，安装被拦、GUI 弹审阅页。

---

## 3. P0-B · 按场景供给：解决两万 token 税

### 3.1 Profile 转正（机制已建成，缺的是入口和自动化）

Profiles.swift 已经能做的：写 `skillOverrides` 到用户级或项目级 settings、off / user-invocable-only 两档排除、目录绑定、写前备份与坏 JSON 拒写。要做的不是新功能，是三件转正的事：

- **从设置→进阶的折叠组里拿出来**，变成库页的一等公民：技能列表按 profile 视图切换，当前生效 profile 显示在工具栏。
- **自动建议**：按 usage 频率生成「常青核心集」（top-N 完整挂载）+「长尾转 user-invocable」草案，人工确认后一键应用。**大量长尾技能应该落在中间档**——`/名字` 仍可调用，但不再向每个会话交描述税。
- **CLI 暴露**：`atlas profile apply <name> --project .`，让 agent/脚本也能切场景。
- 限制要诚实：`skillOverrides` 机制只对 Claude 生效（Profiles.swift:15 已注明）；Codex 等平台的供给靠软链集合差异化，作为第二步。

### 3.2 上下文账单（10.5 节预算算法已有，换个用法）

- 技能详情与列表显示每技能 description 成本；库顶部一个数字：「当前每个 Claude 会话开场约花 N token 读技能清单」。
- 一键「瘦身方案」：长尾停用 + 超长描述接 DescriptionRx 缩写 + 建议转 user-invocable 档。目标写死在验收里：**主力场景会话技能区 token 下降 ≥60%**（本机即 2 万 → 8 千以内）。

### 3.3 安装时即时触发冲突检查

装新技能的 sheet 里直接跑 TriggerLab：「它会和 fund-hotspot-page-writer 抢『热点页面』这个词，第 2 名」。冲突治理从事后维护提前到进门那一刻。

---

## 4. P1-A · 事件驱动的存在感

### 4.1 Hook 遥测转正

- 首次启动/升级后**主动询问一次**是否开启（现在是设置深处的可选项，作者本人都没开）。装的就是现成的 PostToolUse(Skill) 钩子，另加 SessionStart 记会话开场。
- 实时事件替代 991 MB 日志全量扫描；JSONL 扫描降级为历史回填与 Codex 兜底。

### 4.2 Miss 检测（全市场没人做的闭环，你自己每天受益）

会话结束事件触发比对：用户请求文本 × TriggerLab 模拟第一名 × 实际触发记录。发现「有对口技能但没触发」→ 菜单栏/通知中心一条轻提示：「本周 3 次『做个 PPT』类任务，kami 在场却没接到 → 看处方」。点开即 DescriptionRx 一键改描述，改完下周自动汇报命中变化。

### 4.3 更新与安全走通知

技能上游有新版本（diff 摘要）、每周安全复扫命中、死链——全部通知化，不再等人开窗口。菜单栏图标只在「有事」时变化，遵守 macOS 的克制。

---

## 5. P1-B · 创作与调优工作台

作者自己的库里几十个「寿楠专用」技能、skill-creator 用了 12 次——**写技能、调触发**是真实高频场景，2.0 把它做成闭环：

- `atlas new` + 菜单栏「沉淀成技能」：从剪贴板/最近会话 scaffold SKILL.md（可选驱动 skill-creator），装完立刻 TriggerLab 验证「说哪句话能唤到它」。
- **把孤儿沙箱接进这条线**：Sandbox.swift 的单技能隔离试跑（独立 `CLAUDE_CONFIG_DIR` + `disableBundledSkills`）是给新技能做首跑验证的完美工具，现在却没有任何 UI 入口。`atlas new` 完成后的下一步就是「沙箱试跑」。
- 技能详情页重组为**运营页**：触发趋势（hook 数据）· 触发模拟 · 描述处方 · 上下文成本，一屏闭环。「复制调用语」降为次级动作。（注：早期的 OutputLinker「最近产出」已在历史重构中删除，本期不复活。）
- 改完描述自动记录前后触发率，形成 A/B 证据。

**验收**：一个新想法 → 可被真实会话触发的技能 ≤ 5 分钟；一次真实 miss 被检测→处方→修复→再次命中，全程不超过两次点击进 GUI。

---

## 6. P2 · 分发与协同（按需启动）

- 与标准生态互认：优先写入 `~/.agents/skills` 标准目录（platform 专有目录作兼容层）；识别 `npx skills` 装的技能并可收编；Registry 之外补 marketplace/plugin 源。
- skill pack 导出（zip / git 仓库）分享给同事；GitSync 补完多机同步。
- 团队模式：公司场景的白名单技能包 + 统一安全策略（这条真实存在——somd / weekly-data / jiaming 都是团队工作流）。

---

## 7. 砍与降

- 「复制调用语 → 打开软件」保留但让位：详情页主 CTA 变为「装进当前项目 / 发起会话」。
- Launcher 的 AppleScript + Terminal 方案并入 CLI 或做成可配置（iTerm/Warp/Ghostty），不再是独立功能。
- 指南/教学内容维持现状，不再投入；BeginnerLoop 冻结。
- 低用量平台（gemini / workbuddy / hermes / opencode）维持数据层，界面不扩。
- **不再新增一级页面**——v13 的两页导航是终态，新能力全部长在 agent 通道、菜单栏、通知和技能详情里。
- 仓库卫生：删掉遗留 web 三件套（server.py / app.js / styles.css / index.html，构建脚本早已不打包）；docs/acceptance.md 还写着「3.0.0 验收报告」和五项侧栏（现实是 1.7.0 两项侧栏），要么更新要么撤下；acceptance/budget.json 里残留已被正式删除的 `listingSoftCap: 40`。
- 技术债：`Skill` 模型只有 claude/codex 两个结构化 Mount 字段，其余 7 平台是裸字符串——做 CLI `--json` 输出前先把 mount 状态统一成 per-platform 结构。

---

## 8. 设计规范增量（并入 DESIGN.md 作 v14 章）

- 新原语：`ApprovalSheet`（agent 发起的安装/授权请求，必须显示来源会话与请求原文）、`ContextBill`（上下文账单数字，口径 = 10.5 预算算法）、通知文案模板（一句话事实 + 一个动作，禁用警报腔）、菜单栏状态语言（安静/有事两态）。
- 操作来源可区分：agent 发起 vs 人发起，在历史与确认框里有来源徽标。
- 验收人物新增**「不打开窗口的人」**：一整周不开主窗口，技能照常被搜、被装、被修、被沉淀——这才是融入的终极验收。

---

## 9. 施工顺序

| 期 | 内容 | 估算 |
|---|---|---|
| P0-A | `atlas` CLI（复用现有引擎）+ meta-skill | 3–5 天 + 0.5 天 |
| P0-B | Profile 项目绑定 + 三档供给 + 上下文账单 + 装时冲突检查 | 3–4 天 |
| P1-A | Hook 转正 + miss 检测 + 通知化 | 3–4 天 |
| P1-B | 运营页重组 + `atlas new` 沉淀闭环 | 3 天 |
| P2 | 标准目录互认 / skill pack / 团队模式 | 按需 |

已知风险：

1. 平台技能目录被第三方接管（本机 `~/.claude/skills` → mirasim 已是现实）——挂载一律 resolve 真实落点，优先 `~/.agents/skills` 标准目录。
2. Claude Code 原生管理原语在快速演进（`/plugin marketplace`、`disabledSkills`）——atlas 的差异化必须钉死在安全、遥测、调优三件套上，凡是原生已做的（纯启停、纯安装）都走「兼容而非竞争」。
3. CLI 的破坏性操作（卸载、批量停用）保持 GUI 确认，防 agent 误操作放大。
4. Hook 转正后要翻转合并优先级：现在 `mergeHookStats` 是保守合并（grep 结果为零才用 hook 数），hook 成为主数据源后应反过来，JSONL 扫描只做历史回填。
5. 自更新下载目前把整个 DMG 逐字节读进内存（SelfUpdater.download），顺手改成落盘流式。
