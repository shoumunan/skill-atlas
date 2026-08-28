# Skill Atlas 2.0 · 完整实施方案（设计 + 技术路线 + 工作包）

版本 2026-08-26。本文档是**派发给实施 agent 的唯一开工依据**：每个工作包（WP）自带范围、改动文件、实现要点、验收命令和开工提示词。战略论证见 `ROADMAP.md`（不必读也能施工）；视觉与交互规范以 `DESIGN.md` 为法律，本文只做增量。

**给实施 agent 的三句话**：① 先读 §7 全局护栏，那是禁令，违反即返工；② 你的 WP 只做自己范围内的事，接口按 §4 数据契约走，不要顺手重构别人的区域；③ 完成定义（DoD）在 §6 每个 WP 末尾，探针跑绿才算完。

---

## 1. 产品定义

### 1.1 一段话诊断

本机实测（2026-08-26）：134 个技能、108 个挂 Claude，每个会话开场注入约 2.8 万字符（≈1.5–2 万 token）技能清单；32 个技能从未被用过；真正解决这笔税的 Profiles、实时遥测 Hook、单技能沙箱**全部已建成但没有入口或没人用**。产品把「人打开窗口」当前提，而技能的真实操作者是 agent、真实场景在终端会话里。2.0 的主题：**换插座**——把已有引擎接到 agent 一侧和事件一侧；GUI 保留并继续按 DESIGN.md 的质量标准演进（同类竞品的设计不满足本项目要求，功能重叠不是问题）。

### 1.2 定位与三个 surface

**技能供给与运维层（skill ops）**，三个 surface 取代「页面」作为组织单位：

| Surface | 载体 | 职责 |
|---|---|---|
| Agent surface（新增） | `atlas` CLI + meta-skill + URL scheme | agent 在会话内搜/装/停/诊断/沉淀；人只做审批 |
| Ambient surface（升级） | Hook 遥测 + 系统通知 + 菜单栏 ⌥⌘K | 有事主动找人：miss、安全命中、可更新 |
| Workbench surface（收缩） | 主窗口（保持 v13 两页导航，永不加页） | 审批台 + 调优台 + 盘点台 |

### 1.3 北极星指标与测量口径

1. **每会话技能上下文成本**（token）：`ContextDoctor` 估算口径（CJK×0.7 + 其他/4 + 每技能 15 开销），目标：主力场景 ↓60%（2 万 → 8 千内）。
2. **miss 修复闭环**：检出「有对口技能未触发」→ 处方 → 再命中的周期；数据源 usage-index + oplog。
3. **agent 经由 atlas 完成的操作数**：oplog 中 `actor:"cli"` 的条数。

### 1.4 人物验收（沿用 DESIGN.md 风格，新增一条）

- 既有人物（第一次使用的人 / 遇到问题的人 / 技能很多的人 / 无障碍用户）全部保留。
- **新增「不打开窗口的人」**：一整周不开主窗口，技能照常被搜、被装（关键级安全命中除外）、被修、被沉淀。

---

## 2. 总体架构

### 2.1 目标结构（native/）

```
native/
  Package.swift            # 3 个 target（见 ADR-1）
  swift/
    core/                  # AtlasCore：纯 Foundation，禁 import SwiftUI/AppKit
      Atlas.swift Scanner.swift SecurityScan.swift TriggerLab.swift
      Doctor.swift DescriptionRx.swift Usage.swift HookTelemetry.swift
      Profiles.swift Registry.swift Sandbox.swift Installer.swift
      CoreModels.swift     # 从 Models.swift 拆出的数据结构（无 Color）
      L10nCore.swift       # L()/LF() + bundle 逻辑（Foundation 版）
      Oplog.swift AtlasLock.swift PendingReview.swift MissDetect.swift  # 新增
    cli/                   # atlas 可执行
      main.swift Commands/*.swift JSONOut.swift
    app/                   # SkillAtlas.app（现有其余文件全部搬入）
      Store.swift RootView.swift LibraryView.swift … Theme.swift
      ModelsUI.swift       # Categories 颜色映射等 UI 元数据
```

### 2.2 数据流（新增部分加粗）

```
终端会话(agent) ──调用──▶ atlas CLI ──flock──▶ ~/.skill-atlas/*（库、catalog、软链）
      ▲                      │写 oplog.jsonl
      │meta-skill 教路       │关键级安全命中 → pending-reviews/<token>.json
      │                      └─deep link: skillatlas://review/<token> ─▶ App 审阅 sheet
Claude/Codex 转录 ──UsageIndexer 回扫──▶ usage-index(v4, 含首轮 prompt)
PostToolUse hook ──追加──▶ usage-events.jsonl（实时主源，回扫降为回填）
usage + TriggerLab ──▶ MissDetect ──▶ 系统通知/维护区 ──▶ DescriptionRx 处方
App(FSEvents) 观察一切外部改动 ──▶ rescan 自愈
```

### 2.3 CLI 的分发方式

`atlas` 二进制随 .app 打包在 `Contents/MacOS/atlas`。**meta-skill 由 App 生成时把绝对路径写死进 SKILL.md**（如 `/Applications/Skill Atlas.app/Contents/MacOS/atlas`），agent 零配置可用，不依赖 PATH。App 启动时检测自身路径变化则重新生成 meta-skill。人类用户可在设置里一键装 `~/.local/bin/atlas` 软链（可选）。自更新换装整个 .app，CLI 随之更新，软链路径不变。

---

## 3. 技术路线决策记录（ADR）

### ADR-1 三 target 拆分，swiftc 兜底路径同步改造

**决定**：`Package.swift` 改为 `AtlasCore`（library）+ `atlas`（executable）+ `SkillAtlas`（executable，依赖 FluidGradient）。`构建原生应用.command` 的 swiftc 兜底改为两次编译：app = `swift/app/*.swift swift/core/*.swift vendor/FluidGradient/...`；cli = `swift/cli/*.swift swift/core/*.swift`（均 `-swift-version 5 -target arm64-apple-macos14.0`）。
**理由**：12 个引擎文件今天就是纯 Foundation（已实测 grep），拆分阻力极小；CLI 与 App 共享同一套引擎代码，逻辑永不漂移。
**被否**：CLI 用 Go/Rust/Node 另写（逻辑双份必然漂移）；只做 App 内 XPC/AppleScript 接口（agent 侧不通用）。
**坑**：`Models.swift` 现在 import SwiftUI（分类颜色），必须拆成 `core/CoreModels.swift`（数据）+ `app/ModelsUI.swift`（颜色/图标映射）；`L10n.swift` 同理拆 `L10nCore.swift`；`Launcher.swift` 里的 `GitSync` 暂留 app 侧（CLI v1 不需要）。CI 加 grep 门禁：core/ 下出现 `import SwiftUI|AppKit` 即 fail。

### ADR-2 CLI 零第三方依赖，手写参数路由

**决定**：不引 swift-argument-parser，手写 ~150 行命令路由。
**理由**：swiftc 兜底路径是 `*.swift` 通配直编，无法解析 SPM 依赖；vendor 一份 argument-parser 体积和维护都不划算。CLI 命令面窄（十几个子命令），手写足够。
**被否**：swift-argument-parser（破坏兜底构建）；忽略兜底路径（release.yml 依赖它过 CI 的历史在案）。

### ADR-3 meta-skill 优先，MCP server 后置

**决定**：agent 集成第一步是一个由 App 自动生成并挂载到所有平台的技能 `skill-atlas`（教 agent 用 CLI），不先做 MCP server。
**理由**：meta-skill 半天工作量，发布即覆盖所有支持 Agent Skills 的平台；MCP server 要求用户逐平台配置，收益重叠度 90%。
**触发再评估**：当出现「无 shell 权限的宿主」成为主要场景时再做 MCP（stdio 包 CLI 即可）。
**规格**：description ≤120 字符（自己不交税）；frontmatter 带 `metadata: {managed-by: skill-atlas, version: <app版本>}`；catalog 记录加 Optional 字段 `managed: true`；Profiles 排除逻辑永远跳过它；UI 显示「固定」徽标不可停用（可卸载 App 时清理）。

### ADR-4 审批闭环 = pending-review 文件 + URL scheme + 内容寻址批准

**决定**：CLI 安装遇关键级安全命中：写 `pending-reviews/<token>.json` → 退出码 3 + stdout 输出深链 `skillatlas://review/<token>` 与人话指引 → 人在 App 审阅（复用既有强制审阅 UI）→ 批准写入 `approvals.json`（键 = sha256(repo@commit/技能子目录)，内容寻址）→ agent 重跑同一条 `atlas install` 命中批准放行。
**理由**：内容寻址使「上游偷偷改代码」自动失效批准；文件握手无需 IPC/守护进程；agent 的重试语义天然幂等。
**被否**：CLI 内交互式 y/N（agent 会代答，破坏「人批准」）；App 轮询队列自动装（人不在场）。
**依赖**：App 需注册 `CFBundleURLTypes`（scheme `skillatlas`，现在没有任何 URL scheme）。路由：`review/<token>`、`skill/<name>`、`profile/<name>`。

### ADR-5 状态一致性 = flock 互斥 + oplog + FSEvents 自愈

**决定**：所有写库操作（CLI 与 App 共用）包在 `~/.skill-atlas/.lock` 文件锁里（O_EXCL + pid，>120s 且 pid 已死视为陈锁可抢，CLI 等待 5s 后退出码 6）；每次变更追加 `oplog.jsonl`；App 靠既有 FSEvents → rescan 感知外部改动，不做推送通道。
**理由**：两个写者（App、CLI）一个真源（文件系统），锁 + 重扫已充分；守护进程/socket 是过度设计。
**被否**：SQLite（134 个技能量级 JSON 足够，且 atlas.json 向后兼容纪律已建立）；XPC。

### ADR-6 miss 检测走转录回扫，不新增数据采集面

**决定**：UsageIndexer 升 v4：每个 Claude/Codex 会话额外提取**首轮用户消息前 500 字符**存入 usage-index；MissDetect 对近 7 天会话跑 `TriggerLab.simulate(firstPrompt)`，第一名得分 ≥θ、已挂载、可被模型触发、且不在该会话已用技能集合 → 计一次 miss；同一技能 ≥2 次才进周报（噪音地板）。
**理由**：转录本来就在本机、UsageIndexer 基建现成；不需要新 hook、不扩大采集面（500 字符上限、纯本地、gitignore 已覆盖）。
**诚实边界**：「模型考虑过但没选」不可观测；miss 定义收窄为「应触发而未触发」。user-invocable-only 的技能 miss 文案改为「可以用 /名字 调用」。
**参数**：`MissRules { minScore, minOccurrences = 2, windowDays = 7, digestCap = 3 }` 集中一处，夹具调参。

### ADR-7 供给三档：机制验证优先，物理软链兜底

**决定**：三档 = 完整挂载 / 仅用户可调（描述不进清单）/ 不挂载。「仅用户可调」的实现按顺序验证：
1. **首选** `skillOverrides`（Profiles.swift 已在写，键值 `"user-invocable-only"`/`"off"`）——WP3 第 0 项任务是用沙箱基建写探针实证当前 Claude Code 真的认这个键（隔离 `CLAUDE_CONFIG_DIR` + 两个假技能 + `claude --print` 问技能清单，断言被 off 的不在）。
2. **兜底** 若失效：向 SKILL.md frontmatter 写 `disable-model-invocation: true`（Agent Skills 标准字段，DescriptionRx.writeBack 的 YAML 写回基建现成），写前走 SkillBackup 快照。
项目级供给 = `<project>/.claude/skills/` 物理软链集合（原生机制，必然有效）+ 项目 `settings.local.json` 覆盖（既有 ProfileWriter 能力）。
**理由**：全局瘦身必须能「移除全局层的描述税」，纯加法的项目目录做不到，所以两条腿。
**诚实边界**：skillOverrides 只影响 Claude；Codex 供给靠软链集合差异，二期调研其项目级机制。

### ADR-8 明确不做（本期）

守护进程 / 常驻 HTTP 服务（App 已常驻 + 文件真源足够）；SQLite；MCP server（见 ADR-3）；技能内容的 LLM 生成（`atlas new` 只做 scaffold + 交给宿主 agent 写内容——LLM 就在旁边，不要在 App 里再塞一个）；跨机实时同步（GitSync 手动路线维持）。

---

## 4. 数据契约（跨 WP 接口，先于实现冻结）

### 4.1 CLI 通用约定

- 全局参数：`--json`（机器模式：stdout 恰好一个 JSON 对象，人话与进度全走 stderr）；`ATLAS_HOME` 环境变量覆盖 `~/.skill-atlas`（探针/测试用，等价 App 的 `-atlasHome`）。
- **退出码总表**：0 成功；1 一般错误；2 参数/用法错误；3 需要人工审批（安全）；4 网络/git 失败；5 冲突（同名/占位）；6 库被锁；7 目标不存在。
- `--json` 信封：`{"ok":bool,"code":int,"op":"<子命令>","data":{…},"error":{"message":"…","hint":"…"}|null}`。
- 子命令与 data 载荷（v1 冻结面）：

| 命令 | data 要点 |
|---|---|
| `atlas list [--platform p] [--json]` | `skills:[{name,dir,desc≤120,platforms:{claude:bool,…},origin,disabled,updateAvailable,usage:{sessions,last}}]` |
| `atlas search <q> [--remote]` | 本地库匹配 + `--remote` 追加 skills.sh（沿用 Registry.search 与其超时/置灰规则） |
| `atlas info <name>` | 全量单技能：描述、触发词、`bill` 字符/token、安全 findings 摘要、路径 |
| `atlas install <github-url\|owner/repo\|本地路径> [--platforms a,b]` | 成功：装了什么、挂到哪；code 3：`{reviewToken,reviewURL,findings:[…]}` |
| `atlas enable\|disable <name> [--platform p]` | 改后的 platforms 映射；缺 `--platform` = 按 PreferredPlatforms |
| `atlas simulate "<句子>"` | TriggerLab 前 8 名 `[{name,score,hits,risks}]` |
| `atlas doctor` | DoctorReport + 挂载失败 + 安全汇总 + 触发重叠 top |
| `atlas bill [--platform claude]` | `{total:{chars,tokens},perSkill:[{name,chars,tokens,tier}]}` |
| `atlas profile list\|show\|apply <name> [--project DIR]` | apply 返回写了哪个文件、排除了几个 |
| `atlas new <name> [--from-clipboard]` | scaffold 路径 + 下一步提示（含沙箱命令） |
| `atlas sandbox <name>` | materialize 后输出可复制的启动命令（不 AppleScript 开终端——agent 自己就在终端里） |
| `atlas review list` | pending-reviews 摘要（批准只能在 GUI） |
| `atlas paths` / `atlas version` | 诊断用 |

v1 **不提供** `uninstall` 与批量停用（破坏性，走 GUI）。

### 4.2 新增文件格式（都在 `~/.skill-atlas/`）

- `oplog.jsonl`：每行 `{"ts":unix,"actor":"cli"|"app","op":"install|enable|disable|profile-apply|rx-writeback|new|update|rollback","target":"<dir>","ok":bool,"detail":"…"}`。CLI 每次变更必写；App 在 Store 的动作入口写。轮转：>2 MB 时截半。
- `pending-reviews/<token>.json`：`{token, createdAt, source:{url,branch,commit}, candidates:[{dir,name,desc}], findings:[{severity,rule,file,line,excerpt}], requestedBy:"cli"}`；token = sha256(url+commit+dirs) 前 12 位十六进制。
- `approvals.json`：`{"version":1,"entries":{"<sha256(repo@commit/dir)>":{"approvedAt":ts}}}`。
- `usage-index.json` 版本 3→4：Claude/Codex 每会话新增 `"firstPrompt":"≤500字符"`。版本升级 = 全量重建（实测 3.7s，可接受）。
- `atlas.json`：新增字段一律 Optional（`managed:Bool?` 等）。**这是红线**，见 Atlas.swift:124-127 的数据毁灭警告。
- meta-skill：库内目录 `skill-atlas/SKILL.md`，App 每次启动校验（路径变化/版本变化→重生成）。

### 4.3 通知与 URL scheme

- scheme `skillatlas`，路由 `review/<token>`、`skill/<name>`、`profile/<name>`；Info.plist 加 `CFBundleURLTypes`；SwiftUI `onOpenURL` 进 Store 路由（复用 `-atlasSelect` 既有选中逻辑）。
- 通知走 `UNUserNotificationCenter`，类别：miss 周报（每周一次，≤digestCap 条）、安全复扫命中（即时）、可更新聚合（每日至多一次）。全部有设置开关，默认只开安全。

---

## 5. 功能规格摘要（细节见各 WP）

**A. Agent 通道**：§4.1 的 CLI 冻结面 + meta-skill（正文含：什么时候用哪个子命令、`--json` 契约、安全规则「凡 code 3 必须把 reviewURL 转告用户并停下等待，不得改用其他安装途径绕过」、两个完整示例对话）。
**B. 供给层**：Profile 从设置→进阶提为库页一等公民（工具栏 profile 切换菜单 + 当前生效名）；「瘦身草案」= 按 usage 自动分档（≥K 次会话或收藏 → 完整；用过但稀少 → 仅用户可调；90 天未用 → 建议停用），人工逐条确认后应用；上下文账单 chip 常驻工具栏（点击开草案 sheet）。
**C. 遥测与 miss**：Hook 首跑主动询问（一次性 sheet，列明只采 `{skill,ts,session}` 本地三元组）；hook 数据转正为主源（`mergeHookStats` 优先级翻转）；MissDetect 按 ADR-6；维护区新增「本周 miss」组，行动作 = 打开 PrescriptionSheet。
**D. 创作线**：`atlas new` scaffold（frontmatter 模板 + 触发三元组注释引导）→ 提示沙箱试跑命令 → 首次触发验证 `atlas simulate`；GUI 侧把孤儿沙箱接线（详情→更多设置→管理区加「沙箱试跑」按钮，复用 `requestSandbox` 既有流程）；DescriptionRx 写回后 oplog 记录，两周后维护区展示前后触发次数对比。
**E. GUI 运营页（详情重组）**：v13 阅读顺序不动（名称→同步开关→复制调用语/打开软件→警示→用途→何时→示例），「更多设置」内新增运营区块：触发趋势迷你图（hook 按周聚合，Swift Charts）、上下文成本（既有）、触发模拟入口、安全区（既有）。注意：**「最近产出」不做**——OutputLinker 已在历史重构中删除，不复活（P2 再议）。
**F. 卫生**：删 `server.py`/`app.js`/`styles.css`/`index.html`；`docs/acceptance.md` 标注为历史存档并挪 `docs/history/`；`docs/acceptance/budget.json` 删 `listingSoftCap`；`Skill` 的 mount 统一为 `[Platform: Mount]` 字典（清掉 claude/codex 特权字段与 Summary 冗余）；SelfUpdater 下载改落盘流式；`visiblePlatforms` 改设置项。

### 5.7 设计增量（实施后并入 DESIGN.md 作 v14 章）

| 原语 | 职责 | 必备状态 |
|---|---|---|
| `ApprovalSheet` | 承接 agent 发起的安装审阅（复用安全审阅骨架 + 来源徽标「来自会话」） | 待审、已批准、已拒绝、来源失效(commit 变更) |
| `ContextBillChip` | 工具栏常驻账单数字 | 正常、超标(>1万tok 变琥珀)、计算中 |
| `ProfileSwitcher` | 工具栏 profile 菜单 | 无 profile、生效中、应用中、应用失败 |
| `SlimDraftSheet` | 瘦身草案逐条确认 | 草案、逐条覆写、应用中、完成回执 |
| `MissCard` | 维护区 miss 条目 | 新检出、已开处方、已修复(命中回升)、已忽略 |
| `TrendMini` | 详情页触发趋势 | 有数据、数据不足(<2周)、hook 未开启(引导) |
| 通知文案 | 一句话事实 + 一个动作，禁警报腔 | — |

全部沿用 Theme.swift 令牌：不新增字号/颜色/间距；一屏一个强调色主按钮的既有铁律不变；agent 来源操作在确认框与 oplog 视图带「会话」徽标。

---

## 6. 工作包（派发单元）

依赖图与泳道：

```
泳道A(基建):  WP0 ──▶ WP1 ──▶ WP2
泳道B(供给):  WP7a(Mount统一) ──▶ WP3 ──▶ WP6
泳道C(数据):  WP4 ──▶ WP5（WP5 的 CLI 子命令等 WP1 合入）
WP7b(其余卫生) 随时可做
```

三条泳道可并行；估算合计 19–26 agent 天，三泳道并行约 2 周。

---

### WP0 · 核心层拆分与构建改造（2–3 天）【阻塞一切，最先做】

**目标**：三 target 结构落地，两条构建路径全绿，CI 门禁上线。
**改动**：`native/Package.swift`（3 target）；`swift/` 按 §2.1 分目录搬文件；拆 `Models.swift` → `core/CoreModels.swift` + `app/ModelsUI.swift`；拆 `L10n.swift` → `core/L10nCore.swift`（L/LF/查表）+ `app/L10n.swift`（AppLanguage/界面）；`构建原生应用.command` swiftc 兜底改两次编译并把 `atlas` 拷入 `Contents/MacOS/`；`打包DMG.command` 无需改（打包整个 .app）；新增 `.github/workflows/ci.yml`（push/PR：xcode-select 16.2 → `swift build` 两 target → core 目录 `grep -L` UI 框架门禁 → 跑 `tests/acceptance.sh` 骨架）。
**要点**：搬文件用 `git mv` 保历史；`@Observable`（Observation 框架）允许留在 core（Foundation 同级）；`Launcher.swift` 拆开——AppleScript 部分留 app，`GitSync` 留 app；编译两路都要在**本机与 CI** 各过一次（release.yml 的 Xcode 16.2 / actor 隔离差异有历史教训，见构建脚本注释）。
**验收**：`swift build -c release` 产出两个二进制；`./构建原生应用.command` 在删掉 `.build` 后仍成功且 `Contents/MacOS/atlas --version` 有输出（临时硬码版本即可）；CI 绿。
**开工提示词**：`读 PLAN.md §2.1、§3 ADR-1/2、§6 WP0、§7。执行 WP0：三 target 拆分。不改任何业务逻辑，纯搬移+拆分+构建脚本。完成后跑验收命令并贴输出。`

### WP1 · atlas CLI v1（3–4 天）【依赖 WP0】

**目标**：§4.1 冻结面里除 `install/new/sandbox/profile` 外的全部只读与轻写命令 + 基建三件套（锁、oplog、JSON 信封）。
**改动**：`swift/cli/`（main + 命令路由 + JSONOut）；`core/AtlasLock.swift`、`core/Oplog.swift` 新建；`Store.swift` 的动作入口补 oplog 写入（App 侧）。
**要点**：手写参数路由（ADR-2）；所有输出人话默认中文（复用 L10nCore）；`enable/disable` 走既有 `SkillActions.setPlatform`（含占位目录报错语义，映射退出码 5）；扫描直接调 `SkillScanner.scan()`（无缓存态，CLI 每次冷扫，134 技能实测应 <1s，超了再谈缓存）；`simulate/doctor/bill` 是纯函数改包装。锁语义按 ADR-5。
**验收**：`tests/acceptance.sh` 新增 CLI 段：`ATLAS_HOME=$(mktemp -d)` 布置夹具库（3 个假技能 + 假平台根）→ `atlas list --json | jq` 断言结构 → `atlas enable x --platform claude` 后软链存在且 `atlas.json` enabled 位正确 → 并发两个 `atlas enable` 一个退出码 6 → oplog 行数 +2。
**开工提示词**：`读 PLAN.md §4.1、§3 ADR-2/5、§6 WP1、§7。实现 CLI v1 冻结面（不含 install/new/sandbox/profile）。--json 信封与退出码严格按 §4.1，写完先补 tests/acceptance.sh 再自测。`

### WP2 · 安装通道 + 审批闭环 + meta-skill（3 天）【依赖 WP1】

**目标**：`atlas install` 全流程（含 code 3 审批握手）、URL scheme、meta-skill 生成挂载。
**改动**：`core/PendingReview.swift`（token/读写/内容寻址批准）；`cli/Commands/Install.swift`（复用 `InstallerModel` 的 parse→clone→detect→scan→clonefile→链管线，剥离 sheet 状态）；`app/`：Info.plist 加 `CFBundleURLTypes`、`onOpenURL` 路由、审阅 sheet 接 pending-review 数据源、批准写 `approvals.json`；`core/MetaSkill.swift`（模板 + 生成 + 校验）；App 启动钩子挂载 meta-skill。
**要点**：install 的来源解析**只走** `InstallerModel.parse`（github.com 硬限制不放宽，Registry 只填仓库地址的纪律照旧）；批准键 = sha256(repo@commit/子目录)，clone 后先取 commit 再查批准；meta-skill 描述 ≤120 字符、正文按 §5A 四要素写、绝对路径生成时注入；catalog 加 Optional `managed` 字段（红线 §7-1）。
**验收**：夹具 A（干净技能）`atlas install file://…​.git` 直接装成功；夹具 B（复用既有恶意夹具，含 curl|sh）退出码 3 + pending-review 文件落盘 + `atlas review list` 可见；GUI 打开 `skillatlas://review/<token>` 弹审阅，批准后重跑同命令放行；改夹具 B 内容重新 commit 后批准失效（重新 code 3）；meta-skill 出现在所有平台根且 `atlas list` 里带 managed 标。
**开工提示词**：`读 PLAN.md §3 ADR-3/4、§4.2、§6 WP2、§7。实现安装通道与审批闭环。恶意夹具复用 DESIGN.md 第16条记载的验收夹具思路。URL scheme 与审阅 sheet 改动最小化，复用既有强制审阅 UI。`

### WP3 · 供给层转正（3–4 天）【依赖 WP7a；CLI 子命令部分依赖 WP1】

**目标**：两万 token 税砍到目标线的全部机制与 UI。
**第 0 项（先做，半天）**：skillOverrides 有效性探针——用 Sandbox 基建起隔离 `CLAUDE_CONFIG_DIR`，两个假技能 + `skillOverrides:{b:"off"}`，`claude --print` 问技能清单断言 b 不可见；把结论（成立/不成立+版本号）写进 `docs/acceptance/wp3-overrides.md`。不成立则启用 ADR-7 兜底路线（frontmatter 写 `disable-model-invocation`，走 SkillBackup 快照 + 可撤销）。
**改动**：`app/`：ProfileSwitcher 进工具栏、ContextBillChip、SlimDraftSheet（分档算法：常量集中 `SlimRules { coreMinSessions, staleDays = 90 }`）；Profiles UI 从设置→进阶移到库页入口（设置里留管理入口）；`cli/Commands/Profile.swift`、`Bill.swift`。
**要点**：瘦身应用走既有 ProfileWriter（备份/坏 JSON 拒写纪律照旧）；meta-skill 永不进排除集；账单口径 = ContextDoctor 现算法，UI 标「估算」。
**验收**：探针文档落盘;夹具库跑 `atlas bill --json` 总数正确;SlimDraft 应用后 `atlas bill` 总 token 下降且被排除技能 `/名字` 仍可调（沙箱实测一条）;真机（作者库）应用草案后账单 ≤8000 tok（**这是 2.0 的硬验收**）。
**开工提示词**：`读 PLAN.md §3 ADR-7、§5B、§6 WP3、§7。先做第0项探针并把结论写入 docs/acceptance/wp3-overrides.md，再按结论选主路线或兜底路线实现供给三档。UI 严格走 Theme 令牌，一屏一个强调主按钮。`

### WP4 · 遥测转正 + miss 检测 + 通知（3–4 天）【依赖 WP0】

**目标**：hook 成为主数据源；miss 闭环第一版；通知管道。
**改动**：`app/` 首跑询问 sheet（一次性，文案列明三元组）；`Store.mergeHookStats` 优先级翻转（hook 主、grep 回填——注意现状是反的）；`core/Usage.swift` 升 v4（首轮 prompt 提取：mmap 后只对文件头部 ~50 行做最小 JSON 解码取第一条 user 消息，截 500 字符）；`core/MissDetect.swift`（ADR-6 规则）；`app/` 维护区「本周 miss」组 + MissCard + UNUserNotificationCenter 接入 + 设置开关组。
**要点**：usage-index 版本升级即全量重建，进度沿用既有后台索引 UI；miss 判定排除 user-invocable-only（换文案）与 disabled；通知默认只开安全类；App 常驻已有（关窗不退），登录项（SMAppService）做成设置项默认关。
**验收**：夹具转录（构造 3 个 jsonl：一个真 miss、一个已触发、一个低分）跑 `MissDetect` 探针输出恰好 1 条；hook 装上后真机新会话事件落 `usage-events.jsonl` 且详情页计数实时 +1；通知在系统设置可见且可关。
**开工提示词**：`读 PLAN.md §3 ADR-6、§5C、§6 WP4、§7。注意 mergeHookStats 现状是 grep 优先，要翻转。miss 夹具先行，阈值常量集中可调。首轮 prompt 只存 500 字符且必须确认 .gitignore 覆盖 usage-index。`

### WP5 · 创作线：atlas new + 沙箱接线 + Rx A/B（2–3 天）【依赖 WP1、WP4】

**目标**：想法 → 可触发技能 ≤5 分钟；孤儿沙箱复活。
**改动**：`cli/Commands/New.swift` + `Sandbox.swift` 包装（materialize + 打印命令，不开终端）；`core/` scaffold 模板（frontmatter 引导注释：触发三元组写法、描述 ≤200 字提醒）；`app/` 详情管理区补「沙箱试跑」按钮接 `requestSandbox` 既有流程（含 Sandbox.swift:51-56 四条注意事项原文展示）；Rx 写回事件进 oplog，维护区两周后展示前后触发对比卡。
**验收**：`atlas new demo-skill && atlas simulate "demo 场景句"` 排名第一；GUI 沙箱按钮出现且走完 materialize→终端命令流程；oplog 出现 rx-writeback 后维护区出现对比卡（夹具时间前移模拟两周）。
**开工提示词**：`读 PLAN.md §5D、§6 WP5、§7。沙箱是复活既有孤儿代码（Store.swift requestSandbox 一带），不要重写。atlas new 只 scaffold 不生成内容——内容交给宿主 agent。`

### WP6 · 详情运营页 + 工具栏整合（2–3 天）【依赖 WP3、WP4】

**目标**：详情页 = 单技能运营闭环；工具栏收纳 profile/账单两个新元素不破 v13 秩序。
**改动**：`app/LibraryView.swift` 详情「更多设置」内加运营区块（TrendMini 用 Swift Charts、触发模拟入口、成本行既有）；工具栏排布调整（DESIGN.md §10.2 点击数表不得回退）；ApprovalSheet 待审角标入口（有 pending 时才出现）。
**要点**：v13 首屏阅读顺序一个字不动；「最近产出」明确不做；宽窄窗/深浅色/Reduce Motion/CJK 长文案四路截图验收（DESIGN.md 惯例）。
**验收**：既有 `-atlasSelect` 探针链路不回归；新增区块在 hook 未开启时显示引导态而非空白；四路截图落 `docs/`。
**开工提示词**：`读 PLAN.md §5E、§5.7、§6 WP6、§7 与 DESIGN.md v13 章。运营区块全部进「更多设置」，首屏顺序不动，新原语按 §5.7 状态表实现，字号颜色只用 Theme 令牌。`

### WP7 · 卫生（a: Mount 统一先行 1 天；b: 其余 1 天）

**a（泳道 B 前置）**：`Skill.mountClaude/mountCodex` → `mounts:[Platform:Mount]`；Summary 冗余字段合并；触及 Models/Scanner/Store/LibraryView/SkillTable 的机械替换；atlas.json 不动（它本来就是 per-platform 的 enabled 字典）。
**b**：删遗留 web 四件（先 `git rm`，README/Models 注释同步清理）；acceptance.md 挪 `docs/history/` 并加「历史存档，版本口径已重置」头注；budget.json 删 `listingSoftCap`；SelfUpdater 下载改 `URLSession.download(for:)` 落盘；`visiblePlatforms` 变设置项（默认现状 6 个）。
**验收**：a 后全量编译零警告新增、既有探针绿；b 后 `git grep server.py` 只剩 history。
**开工提示词**：`读 PLAN.md §6 WP7、§7。a 是纯机械重构，禁止顺手改语义；b 的删除全部 git rm 留历史。`

---

## 7. 全局护栏（每个实施 agent 必读的禁令）

1. **atlas.json 新字段必须 Optional**——否则老 catalog 解码失败会静默清空所有 enabled 位（Atlas.swift:124-127 的数据毁灭警告是血泪史）。
2. **永不写** `~/.cc-switch/`（DB 与 skills 目录只读是产品承诺）。
3. **破坏性操作只进废纸篓**，never `rm`；写 `~/.claude/settings.json` 系列必须：先备份（HookTelemetry.backup 分域机制）、坏 JSON 拒写、只动自己的键。
4. **UI 只用 Theme.swift 令牌**：不新增字号/颜色/间距/圆角；一屏一个强调色主按钮；不新增一级页面；破折号不进文案（仓库文案纪律）。
5. **i18n**：用户可见字符串一律 `L("中文原文")`，新增键补 en/ja/ko 三语行（`native/resources/*.lproj/Localizable.strings`，键=中文原文）；技能名/描述等用户内容保持原文。
6. **构建两路都要过**：SwiftPM 与 swiftc 兜底（`-swift-version 5`，注意 Xcode 16.2 与本地的 actor 隔离差异历史教训）；不引新第三方依赖（ADR-2）。
7. **网络面不扩大**：出网仅限 github.com clone、skills.sh 搜索（受 `atlasRegistryEnabled` 开关）、appcast/Release 自更新。CLI 不新增任何出网。
8. **hook 脚本永远 exit 0**；遥测数据永不出本机、gitignore 必须覆盖。
9. **探针命名沿用 `-atlasXxx`**（App）与 `ATLAS_HOME` 夹具（CLI）；每个 WP 的验收进 `tests/acceptance.sh`，输出与金样比对（jq 归一化），不再只留「输出文件当验收」。
10. **注释文化**：中文、写约束与病根，不写流水账；平台目录必须 `resolvedRoot()` 解析后再动（`~/.claude/skills` 被 mirasim 接管是本机现实）。
11. meta-skill 描述 ≤120 字符；任何新技能相关文案自己先过 ContextDoctor 口径。
12. 完成定义（每 WP 通用 DoD）：两路构建过 + 本 WP 验收命令绿 + 既有探针不回归 + i18n 补齐 + oplog 覆盖新写操作 + DESIGN.md v14 增量段落提交。

---

## 8. 里程碑

| 里程碑 | 内容 | 演示脚本 |
|---|---|---|
| M1（WP0+1） | agent 能读库、开关、诊断 | 在 Claude Code 里问「我有哪些做 PPT 的技能？哪个会触发？」→ agent 跑 list/simulate 答出 |
| M2（WP2+3） | 安装审批闭环 + 税砍到 8000 | 「装 anthropics/skills 的 xlsx」全流程；恶意夹具被拦到 GUI；账单数字达标 |
| M3（WP4+5） | miss 闭环 + 5 分钟沉淀 | 夹具 miss 通知 → 处方 → 再命中；atlas new 到 simulate 第一名 |
| M4（WP6+7） | 运营页 + 卫生收尾 | 四路截图 + 全量探针绿 → 发 2.0.0 |

## 9. 未决问题（实施中验证，不许拍脑袋）

1. skillOverrides 在当前 Claude Code 版本是否生效（WP3 第 0 项探针，结论落文档）。
2. Codex 有无项目级技能机制（WP3 调研，二期决定）。
3. CLI 冷扫 134 技能的真实耗时（WP1 实测，>1s 再加缓存）。
4. 菜单栏/登录项常驻策略（WP4 做成默认关的设置项，数据说话再改默认）。
5. meta-skill 在 Codex/Gemini 的措辞兼容（「运行命令」通用化，WP2 在两平台各实测一条）。
