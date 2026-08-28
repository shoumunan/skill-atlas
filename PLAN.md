# Skill Atlas 2.1 · 完整实施方案（五名词工作台）

版本 2026-08-27。本文档是**派发给实施 agent 的唯一开工依据**。战略论证见 `ROADMAP.md`（2.1 版），视觉与交互规范以 `DESIGN.md` 为法律（v15 章优先）。2.0 的实施方案已归档 `docs/history/plan-2.0.md`——其中 **§4 数据契约（CLI 信封、退出码、文件格式、URL scheme）在 2.1 继续冻结有效**，本文只写增量，不重抄。发版号 **2.1.0**：引擎、CLI 命令面、数据文件格式全部向后兼容，只有 GUI 结构重排，semver 上就是 minor。

**给实施 agent 的三句话**：① 先读 §7 全局护栏，违反即返工；② 你的 WP 只做自己范围内的事，接口按 §4 契约走，不要顺手重构别人的区域；③ 每个 WP 的 DoD 在 §6 末尾，探针跑绿才算完。

---

## 1. 产品定义

### 1.1 一段话诊断

2.0 的引擎与 agent 通道全部达标（CLI 15 命令在线、瘦身后账单 7,723 tok ≤ 8,000、hook 已装、miss 检测在跑），但面板仍然没有存在理由：能力被塞进两页导航的缝隙里——供给藏在工具栏菜单、运维（本机实测 10 个挂载问题 + miss + 触发重叠）藏在设置折叠组、创作线藏在详情页深处；同时 LibraryView 里躺着约 380 行死代码、11 组重复入口、`skillOverrides` 有两个语义不一致的写者。2.1 的主题：**发地址**——五个名词（技能库 / 发现 / 供给 / 收件箱 / 创作）+ 设置，每页对应手册里的一条工作流，高频动作距启动 ≤2 次点击（DESIGN v15 入口层级表）；引擎不新造，只归位。

### 1.2 定位

技能供给与运维层（skill ops）。三 surface 模型继续有效：Agent surface（CLI + meta-skill + 深链）与 Ambient surface（hook + 通知 + 菜单栏）形态不变；Workbench 从「两页 + 堆填」重排为「五名词 + 设置」（六项侧栏、分两组）。

### 1.3 北极星指标

沿用 2.0 三个（每会话技能上下文成本 / miss 修复闭环时长 / agent 经由 atlas 的操作数），新增：

4. **收件箱周清零率**：新检出事项 7 天内被裁决（批准 / 修复 / 忽略均算，必须留 oplog 回执）的比例。

### 1.4 人物验收（DESIGN v15 章为准）

每周开一次面板的人 / 不打开窗口的人 / 半年后的自己 / 无障碍用户。

---

## 2. 结构变化

### 2.1 导航与文件

```
NavPage（Store.swift:8 起）：.library .discover .supply .inbox .studio .settings（⌘1–⌘6；侧栏分组：库=技能库/发现，运营=供给/收件箱/创作，底部=设置）
新增文件：
  app/SupplyView.swift   app/SupplyStore.swift
  app/InboxView.swift    app/InboxStore.swift
  app/StudioView.swift   app/StudioStore.swift
  app/DiscoverView.swift app/DiscoverStore.swift   # InstallView 升格（六阶段安装机保留为页内流程）
  core/Supply.swift      # 唯一的 skillOverrides 写入口（合并 ProfileWriter.apply 与 SlimPlanner.apply 的写路径）
  core/Inbox.swift       # 聚合器 + inbox-state.json 读写
  docs/handbook.md       # 手册（§5-H）
迁走/删除：
  MaintenanceView.swift 内容解散进 InboxView（文件最终删除）
  ProfileView.swift 的管理/应用 sheet 移入 SupplyView 语境
  SupplyChrome.swift 的 ProfileSwitcher/ContextBillChip 移居供给页
  LibraryView.swift 死视图 9 个（§6 WP0 点名）删除
  BeginnerLoop.swift 删除（StarterSkill/OpenHostButtons 若 Onboarding 仍引用则内联搬入 RootView）
```

### 2.2 数据流增量

```
doctor/security/usage/miss/updates/pending-reviews ──▶ core/Inbox.aggregate() ──▶ InboxItem[]
                                                          │ 裁决/忽略 ──▶ inbox-state.json + oplog
系统通知 / 菜单栏「有事」──▶ skillatlas://inbox/<id> ──▶ InboxView 定位条目
SlimDraftSheet / TierSegment / ProfileApply ──▶ core/Supply.write() ──▶ skillOverrides（唯一写者）
```

---

## 3. 技术路线决策记录（ADR，编号接 2.0）

### ADR-9 六项封顶，页面准入 = 手册工作流

**决定**：侧栏固定六项、分两组（库：技能库 / 发现；运营：供给 / 收件箱 / 创作；底部：设置）。任何新能力先回答「属于 docs/handbook.md 哪条工作流的哪一步」，答不出就不做界面，最多做 CLI 子命令。配套铁律：**高频动作距启动 ≤2 次点击；折叠组只许藏解释，不许藏动作**（DESIGN v15 入口层级表逐项验收）。
**理由**：v13「永不加页」防的是页面蔓延，但把真实能力逼进了缝隙；准入标准从「页面数量」换成「工作流可写性」，同时防蔓延与堆填。「发现」独立成页学自 skills-manager 的界面分布——安装/发现是它的一级入口（InstallSkills 独立 view），不是库页的一个按钮。
**被否**：回到两页（能力无地址，本轮病根）；按引擎开页（引擎是实现单位不是用户名词）；发现塞进技能库做 tab（「我有的」与「我没有的」杂糅，正是本轮主诉）。

### ADR-10 收件箱 = 渲染时聚合，不建新采集面

**决定**：`core/Inbox.aggregate()` 在扫描后把九类事项（待审批 / 安全关键 / 安全警告 / 挂载失效 / miss / 可更新 / 触发重叠 / 介绍超长 / Rx 回访）映射为统一 `InboxItem`；唯一新增持久化是 `inbox-state.json`（裁决与忽略记录）。不建数据库、不建后台队列。
**理由**：九类数据源全部已存在（Doctor / SecurityScan / PendingReviews / MissDetect / UpdateChecker / RxFollowup），缺的是统一出口；聚合是纯函数，可探针。
**坑**：条目 id 必须内容寻址（kind + target + 内容摘要），否则重扫后忽略记录失配；已裁决条目消失要有回执，不能默默蒸发。

### ADR-11 skillOverrides 单写者

**决定**：新建 `core/Supply.swift` 作为唯一写入口；`ProfileWriter.apply` 与 `SlimPlanner.apply` 的写 settings 路径全部改为调用它（读与算不动）。备份、坏 JSON 拒写、只动自己的键、meta-skill 永不排除四条纪律在此集中执行。
**理由**：两个写者语义已经分叉（profile 只能给全体非成员一个排除档，slim 是逐技能三档），继续分叉必出脏写；供给页要做逐技能改档，必须先有单写者。
**被否**：在 UI 层协调两个写者（治标）；把 profile 机制废掉只留 slim（场景包对「新项目配供给」工作流仍是正确抽象）。

### ADR-12 CLI 冻结面不动

**决定**：2.1 不改任何既有命令的名字、参数、信封、退出码；meta-skill 文案仅作勘误（「WP5 之后」已删，本次已改 `MetaSkill.swift:78`）。供给页 / 收件箱的 GUI 语义映射到既有 `profile / slim / enable / disable / doctor / review` 之上。允许的增量只有一个可选项：`atlas doctor --inbox-json`（输出 InboxItem 数组，给探针与未来菜单栏用），放 WP-I 末尾，做不完可砍。
**理由**：agent 是一等用户，CLI 是它的 ABI；面板重排是 GUI 的事，不许波及会话侧。

### ADR-13 供给页的项目范围 P0 只做绑定，不做扫描

**决定**：项目范围的数据源 = `profiles.json` 的 bindings + 手动添加的项目目录（新 Optional 字段 `projects:[{path, addedAt}]`）；页面展示绑定的场景包、最近一次应用回执、打开 `settings.local.json` 所在目录。**不扫描**项目内 `.claude/skills`。
**理由**：项目目录扫描牵动 Scanner 与数据模型（audit 确认现在完全不存在），是 P2 的事；P0 先把「给新项目配供给」工作流走通，靠 `atlas profile apply --project` 的既有机制。
**诚实边界**：档位只影响 Claude；Codex 项目机制维持 2.0 未决。

### ADR-14 AppStore 只准瘦不准胖

**决定**：三个新页各建自己的 `@Observable` store（SupplyStore / InboxStore / StudioStore），依赖 AppStore 提供的扫描结果与动作入口；`Store.swift` 不再新增成员，迁出维护区相关状态后行数必须下降。
**理由**：2,115 行 90 成员的上帝对象是每次重构的阻力来源；这次趁页面重排把边界立起来，但不做大爆炸拆分（风险不成比例）。

### ADR-15 市场只是发现层，信任只来自本地扫描

**决定**：多源市场接入统一走 `SourceAdapter` 协议（`core/Sources.swift`）：每个源提供 `search(query)` 与 `featured()`，结果携带 `installRef`（github-repo / zip-slug / webpage 三型）。安装一律汇入既有管线（clone 或 zip 解包 → SecurityScan → 关键级审批 → 入库）；市场侧的「已审核 / 评分 / 企业认证」只作展示元数据，**不减免任何一道本地门**。默认源集：skills.sh（现有）、SkillHub（腾讯，新）、用户自加的 Claude 原生 marketplace.json 仓库、anthropics/skills 官方精选。SEO 型目录站不接。
**理由**：实测 SkillHub 上腾讯官方的 tencent-docs 包内就有 20KB `setup.sh`——恰是本地扫描的目标类；市场审核口径不可审计，评分可刷。发现与信任解耦后，加一个源的成本 = 一个适配器文件。
**被否**：只接单一聚合器（单点依赖，且 skills.sh 覆盖不了国服企业技能）；信任市场审核跳过扫描（见上）；自建技能目录（运营成本，非本产品差异化）。

### ADR-16 zip 安装通道与归档寻址审批

**决定**：`Installer` 增加 zip 分支：下载（跟随 302 至对象存储）→ 临时目录落盘 → 计算 sha256 → 解包（**防 zip-slip：拒绝 `../`、绝对路径、符号链接条目**）→ detect → SecurityScan → 关键级写 pending-review，**审批键 = sha256(archive)**（与 repo@commit 同一内容寻址语义：换版本即失效）→ clonefile 入库。catalog 记录增 Optional 字段 `sourceKind` 与 `sourceVersion`。更新检查 = 轮询源 API 的 version 字段，新版本下载后本地 diff，复用 UpdateReviewSheet。
**坑**：SkillHub 下载 302 到 `*.myqcloud.com`（腾讯 COS），网络白名单要写两条域且都挂在来源开关下；zip 无 commit 历史，回滚全靠既有 SkillBackup 快照；`requires_api_key` 标签必须装前展示，不许装完才发现要注册账号。

---

## 4. 数据契约（先冻结再施工）

### 4.1 InboxItem（core/Inbox.swift）

```json
{
  "id": "security:fund-tools:9f3a…",      // kind:target:sha256(摘要)[0..8]，重扫稳定
  "kind": "approval|security_critical|security_warning|mount|miss|update|overlap|overlong|rx",
  "severity": 0,                            // 0 挡住使用 / 1 建议处理 / 2 整理
  "skill": "fund-tools",                  // 可空（approval 用 token）
  "title": "一句话事实",
  "detail": "四要素：发生了什么/影响什么/建议怎么做/按钮去哪",
  "actions": ["approve|open_diff|prescribe|slim|toggle|reveal|ignore"],
  "deepLink": "skillatlas://inbox/security:fund-tools:9f3a…"
}
```

排序：severity 升序 → kind 固定序（approval 最先）→ 检出时间。`digestCap` 等阈值沿用 MissRules，不另立一套。

### 4.2 inbox-state.json（~/.skill-atlas/）

```json
{ "version": 1,
  "decisions": { "<id>": { "action": "approved|fixed|ignored", "at": 1724740000 } } }
```

新字段一律 Optional（护栏 §7-1 同款血泪史）。忽略的条目在同 id 复现时不再进队列，但 kind=security_critical 永不因忽略而消失（安全不许静音）。

### 4.3 URL scheme 增量

既有 `review/<token>`、`skill/<name>`、`profile/<name>` 不动；新增 `inbox`（打开页）、`inbox/<id>`（定位条目）、`supply`、`supply/<scope>`（scope = 平台名或项目路径 base64）、`discover`。`-atlasPage` 启动参数同步支持 `discover|supply|inbox|studio`。

### 4.4 core/Supply 写接口（语义约定）

单入口接受「逐技能三档 map + 来源（slim 草案 / 场景包应用 / 单技能改档）+ 目标 scope（用户级 / 项目级）」，内部完成：备份 → 合并写 → 回执（前后 token 数）→ oplog。任何调用方不得自行拼 settings JSON。

---

## 5. 功能规格摘要

**S. 供给页**：左 `ScopeRail`（visiblePlatforms 内的平台 + 项目列表 + 添加项目）；右侧按 scope 展示：账单头（ContextBillChip 迁居于此，含估算标注）、场景包 `PresetChip` 行（✓/部分计数/一键应用与撤下，走 Supply 单写者）、三档分组列表（core / 仅用户可调 / off，行内 `TierSegment` 逐技能改档）、「瘦身草案」入口（SlimDraftSheet 原样复用，应用后 `ReceiptLine` 报前后数字）。非 Claude 平台的 scope 只有挂载二态与批量开关，档位控件显示「不适用」。
**I. 收件箱**：ADR-10 聚合；v12 行动中心骨架（主任务卡四要素 + 纵向「接下来」+ 完成绿反馈 + 清零态）；侧栏徽标 = 未裁决数；九类条目的动作分别接既有机制（ApprovalSheet、UpdateReviewSheet、PrescriptionSheet、TierSegment、Finder reveal）；设置 → 通知的三个开关语义不变，通知点击深链进条目。技能库的 `UpdatesBanner` 与 `PendingReviewChip` 移除，可更新与待审只在收件箱与侧栏徽标出现。
**L. 技能库**：死代码清除后，行角标升级为 `TierDots`（点按切换挂载，Claude 列半亮表达中间档）；详情页按 DESIGN v15 重排 CTA（档位与挂载控件上移，复制调用语降次级）；`UsageSection` 与 `TrendMiniSection` 合并为一个「使用」区（hook 为主源、转录回扫补历史，2.0 的合并优先级翻转在此落地）；多选（NSTableView allowsMultipleSelection）+ 批量启停/收藏/停用。
**D. 创作页**：纵向步进四步——① scaffold（`atlas new` 的 GUI 面，含 --from-clipboard）→ ② 沙箱试跑（复活 requestSandbox 流程，展示 Sandbox.swift 四条注意事项）→ ③ 触发验证（TriggerTrySection 复用，目标「说哪句话能唤到它」排第一）→ ④ 两周回访（RxFollowup 对比卡）。PrescriptionSheet 从这里与收件箱两处可达。
**M. 发现页（导入与多源发现）**：InstallView 升格为一级「发现」页。上部**导入区**三合一（安装 URL / 本地目录收编 / CC Switch 迁移入口），下部**发现区**：聚合搜索框 + 来源筛选 chips + 两张榜单（SkillHub score 榜、skills.sh installs 榜）+ `SourceBadge` / `RequiresKeyChip` + 去重（GitHub 仓库地址归一后同仓库只展示一条，徽标合并）；选中候选后进入既有六阶段安装流程（含装前扫描与审阅）。⌘N 落到本页。CLI：`atlas search --remote [--source skillssh|skillhub|all]`；meta-skill 增补「用户要从市场找技能 → `atlas search <词> --remote`」。设置增来源开关组（`atlasRegistryEnabled` 保持总闸）。SkillHub 端点（2026-08-27 实测，无鉴权；适配器必须容错，接口变更时降级为「打开网页」）：列表/搜索 `GET https://api.skillhub.cn/api/skills?page&pageSize&sortBy=score&order=desc&search=<q>`（响应 `{code,data:{skills:[…]}}`，字段含 name / description_zh / namespace.canonicalName / publisher{verified,certifiedName} / source(enterprise|community) / score / downloads / version / labels.requires_api_key / upstream_url）；分类 `GET /api/v1/categories`；下载 `GET /api/v1/download?slug=<urlencoded @handle/slug>` → 302 至版本固化 COS zip；详情网页 `https://skillhub.cn/skills/<handle>/<slug>`（含评测报告 tab，深链打开不复刻）。
**H. 手册**：`docs/handbook.md` 三段式（你是谁 / 三条工作流 / 边界），规格见 ROADMAP §5；应用内「帮助」sheet 与手册同构（读打包进 Resources 的同一份 markdown，ReaderSheet 渲染）；README 重写为「一句话 + 四名词 + 手册链接 + 下载」；关于页与 onboarding 链到手册。
**Z. 卫生**：`dist/Skill Atlas-3.0.0.dmg` 幽灵工件进废纸篓（2026-08-14 旧版本号纪元遗留，版本口径已重置，纯卫生清理）；`.lody/` 进 .gitignore；docs 里 1.3.0 时代截图重拍四路新样张；`发布1.7.0.command` 删除；`docs/index.html` 落地页文案对齐四名词。

---

## 6. 工作包

依赖图：

```
WP0(手术准备) ──▶ WP-S(供给) ──▶ WP-L(技能库)
     │      └──▶ WP-I(收件箱)      │
     ├─────────▶ WP-D(创作) ───────┘
     └─────────▶ WP-M(导入与多源发现)
WP-H(手册) 依赖 S/I/D/M 定稿；WP-Z(卫生) 随时，截图部分最后
```

估算合计 19–24 agent 天，三四条泳道并行约 2 周。

### WP0 · 手术准备（0.5–1 天）【最先，阻塞一切】

**改动**：删除 LibraryView 九个死视图（AdoptBanner / FilterRow / FilterMenu / ViewMenu / SkillRowView / SkillContextMenu / CategoryChip / PlatformFilterStrip(PlatformIcon.swift) / HealthFlag(Theme.swift)，删前 grep 确认零引用）；NavPage 扩六项 + SidebarRail 两组六行 + ⌘1–6 + PageContainer 路由到四个空骨架页（EmptyStateBlock 占位；发现页骨架先挂既有 InstallSheet 入口）；URL scheme 与 `-atlasPage` 增量路由（§4.3）；侧栏徽标机制从「可更新数」改为「收件箱未裁决数」（暂读 doctor 汇总，WP-I 接真源）。
**验收**：全量编译零新警告；`git diff --stat` 显示 LibraryView 净减 ≥350 行；`-atlasPage discover|supply|inbox|studio` 各落对页；既有 `-atlasSelect` 探针不回归。
**开工提示词**：`读 PLAN.md §2.1、§6 WP0、§7 与 DESIGN.md v15 章。执行 WP0：死代码清除 + 六项两组导航壳。不实现任何页面内容，空态用 EmptyStateBlock。删除前逐个 grep 证明不可达，证据贴 PR 描述。`

### WP-S · 供给页（4–5 天）【依赖 WP0】

**改动**：`core/Supply.swift`（ADR-11 单写者，ProfileWriter/SlimPlanner 写路径改道）；`app/SupplyView.swift` + `SupplyStore.swift`（§5-S 布局）；`profiles.json` 加 Optional `projects` 字段（ADR-13）；SupplyChrome 元素迁居；技能库工具栏留只读账单数字点击跳转。
**要点**：档位写操作全部产出 `ReceiptLine`；场景包应用沿用 ProfileApplySheet 的确认语义；`atlas profile/slim` 的 CLI 行为不变（ADR-12），但底层同样改走 Supply 单写者；写前备份与坏 JSON 拒写纪律照旧。
**验收**：夹具库（ATLAS_HOME）跑「逐技能改档 → settings.json 只有本技能键变化 → 回执数字正确」；场景包应用/撤下幂等；两个旧写者的直写路径 `git grep` 为零；真机应用瘦身草案后 `atlas bill` 与页面数字一致。
**开工提示词**：`读 PLAN.md §3 ADR-11/13、§4.4、§5-S、§6 WP-S、§7 与 DESIGN.md v15。先做 core/Supply.swift 单写者并迁移两个旧写路径（读逻辑不动），再搭页面。TierSegment/PresetChip/ScopeRail 状态表按 DESIGN v15，令牌不越轨。`

### WP-I · 收件箱（3–4 天）【依赖 WP0】

**改动**：`core/Inbox.swift`（aggregate + state 读写，§4.1/4.2 契约）；`app/InboxView.swift` + `InboxStore.swift`（v12 骨架复用）；MaintenanceView 九组内容映射迁移后删除该文件；设置里维护组替换为「打开收件箱」一行；AtlasNotify 三类通知的点击路由改深链；UpdatesBanner / PendingReviewChip 从库页移除；侧栏徽标接真源。
**要点**：聚合是纯函数，先写探针再写 UI；security_critical 不可忽略（§4.2）；每条裁决 oplog + ReceiptLine；清零态展示上次清零时间（读 inbox-state 最新 decision 时间）。
**验收**：夹具构造九类各一条 → `Inbox.aggregate` 输出顺序与 id 稳定（跑两次 diff 为空）；忽略后复扫不再出现、critical 忽略无效；深链 `skillatlas://inbox/<id>` 滚动定位；通知点击落到条目；`atlas doctor` JSON 不回归。
**开工提示词**：`读 PLAN.md §3 ADR-10、§4.1/4.2/4.3、§5-I、§6 WP-I、§7 与 DESIGN.md v15/v12 章。先冻结 InboxItem 契约写聚合探针，再迁 MaintenanceView 内容。九类动作全部复用既有 sheet/机制，不新造修复流程。`

### WP-L · 技能库强化（3 天）【依赖 WP-S】

**改动**：SkillTable 行角标升级 `TierDots`（含 Claude 半亮态与点按改档，写走 Supply）；详情 CTA 重排（DESIGN v15 顺序）；Usage/TrendMini 合并 + `mergeHookStats` 优先级翻转（hook 主源）；NSTableView 多选 + 批量操作工具条；右键菜单对齐新动作集。
**验收**：四路截图；点按角标后软链与 catalog 与界面三方一致（探针）；批量停用走废纸篓纪律；合并后的使用区在 hook 无数据时显示回扫数据并标注来源。
**开工提示词**：`读 PLAN.md §5-L、§6 WP-L、§7 与 DESIGN.md v15。TierDots 状态表五态齐全，Claude 列才有半亮。详情首屏顺序按 v15 覆盖 v13。多选只做批量启停/收藏/停用，不做批量卸载（破坏性上限纪律）。`

### WP-D · 创作页（2–3 天）【依赖 WP0；步骤④依赖 WP-I 的 RxFollowup 迁移位】

**改动**：`app/StudioView.swift` + `StudioStore.swift` 四步进（§5-D）；scaffold 面调用 `atlas new` 同等 core 逻辑（不 shell 出去）；沙箱步骤接 `requestSandbox` 既有流程；PrescriptionSheet 双入口注册。
**验收**：「新想法 → simulate 排第一」全程 ≤5 分钟人工实测一遍并录屏归档 docs/acceptance/；沙箱目录出现且注意事项四条展示；步进态在中途退出后可恢复（读 scaffold 存在性判断步骤）。
**开工提示词**：`读 PLAN.md §5-D、§6 WP-D、§7。沙箱与 scaffold 都是复活既有代码（SkillSandbox/NewCommand 的 core 路径），不要重写。步进只有四步，禁止加第五步。`

### WP-M · 导入与多源发现（4–5 天）【依赖 WP0；与 S/I/D 并行】

**改动**：`core/Sources.swift`（SourceAdapter 协议 + skills.sh 适配器改造迁入 + SkillHub 适配器 + marketplace.json 适配器 + `-atlasSourceBase` 夹具注入点）；`core/Installer.swift` zip 分支（ADR-16 全流程，解包防线独立函数可探针）；`app/InstallView.swift` 升格为 `app/DiscoverView.swift` 发现页（导入区三合一 + 发现区，§5-M，六阶段安装机保留）；SettingsView 来源开关组；`cli/Commands/SearchCommand.swift` 加 `--source`；MetaSkill 文案增补；DESIGN v15 新原语 `SourceBadge` / `RequiresKeyChip`。
**要点**：Registry.swift 的「只填仓库地址不猜子路径」纪律对 GitHub 型源继续有效；zip 型源的临时目录用后即焚（defer 清理）；marketplace.json 仓库本身也是 GitHub clone，走既有网络面；官方精选 = anthropics/skills 的硬编码货架（无网络新增）；聚合搜索的源并发发起、超时各自降级，不许一个源卡死整个搜索。
**验收**：file:// 与本地 HTTP 夹具跑两适配器契约测试；恶意 zip 夹具（含 `curl | sh` 的 setup.sh）安装被拦进审阅、审批后放行、改包重签后审批失效；zip-slip 夹具（`../evil`、绝对路径、符号链接三型）全部拒装且报错人话；真机 SkillHub 搜「写作」出结果、企业条目带认证徽标、`requires_api_key` 条目装前有提示；关掉全部来源开关后抓包零出网（复用既有网络验收探针）；同一 GitHub 仓库双源出现时只展示一条。
**开工提示词**：`读 PLAN.md §3 ADR-15/16、§5-M、§6 WP-M、§7。先冻结 SourceAdapter 契约并写夹具，再做 SkillHub 适配器（端点与字段见 §5-M，接口容错降级为打开网页）。zip 解包防线先写探针再写实现。安装管线既有护栏一条不降，网络白名单只按 §7-19 扩。`

### WP-H · 手册与文档（1–2 天）【依赖 S/I/D/M 界面定稿】

**改动**：`docs/handbook.md`（ROADMAP §5 规格：你是谁 / 三条编号工作流带完成证据 / 边界）；帮助 sheet（ReaderSheet 渲染打包副本）；README 重写；onboarding 与关于页链接；meta-skill 文案复核（勘误已做，检查其余措辞与四名词一致）。
**验收**：手册四条工作流各由一名「没看过代码的读者」（另起无上下文 agent 会话模拟）照做走通并出完成证据；README 无失效链接与过期截图引用；应用内帮助与 handbook.md diff 为零（同一来源）。
**开工提示词**：`读 ROADMAP.md §5、PLAN.md §6 WP-H。手册每条工作流 = 编号步骤 + 完成证据 + 失败分支，datawhale 第 6 课的写法（适用人群前置、smoke test、边界诚实）。写完用无上下文 agent 实测。`

### WP-Z · 卫生（1 天，穿插；截图最后）

**改动**：§5-Z 全部；四路新样张替换 README/landing 引用。
**验收**：`git status` 干净、`.lody` 不再出现在未跟踪列表；landing 页四名词文案上线；废纸篓可见幽灵 DMG。
**开工提示词**：`读 PLAN.md §5-Z、§6 WP-Z、§7。删除全部进废纸篓或 git rm 留历史，截图按 DESIGN 四路惯例重拍。`

---

## 7. 全局护栏（每个实施 agent 必读的禁令）

2.0 护栏 1–12 条全部继承（atlas.json Optional / 永不写 ~/.cc-switch / 破坏性只进废纸篓 + settings 写前备份 / Theme 令牌与文案纪律 / i18n 四语 / 两路构建不引新依赖 / 网络面不扩大 / hook 永远 exit 0 / 探针命名 / 注释文化 + resolvedRoot / meta-skill 描述 ≤120 字 / 通用 DoD），另加：

13. **六项封顶与入口深度**（ADR-9）：新能力先答「手册哪条工作流哪一步」，答不出不做界面；高频动作距启动 ≤2 次点击，折叠组不得藏动作。
14. **skillOverrides 唯一写者**（ADR-11）：除 core/Supply.swift 外 `git grep skillOverrides` 不得出现在任何写路径。
15. **两轴文案纪律**：界面与文档只说「挂载」（二态，所有平台）与「档位」（三态，仅 Claude），禁止第三种叫法混用。
16. **AppStore 冻结**（ADR-14）：Store.swift 不新增成员，新页面状态进各自 store；WP 结束时 Store.swift 行数只降不升。
17. **裁决必留痕**：收件箱每次裁决（含忽略）oplog + ReceiptLine；security_critical 不可忽略。
18. **CLI ABI 冻结**（ADR-12）：命令名/参数/信封/退出码不动；增量只允许 §3 点名的可选项（本轮新增豁免：`atlas search --source`，纯增参不破坏既有调用）。
19. **多源纪律**（ADR-15/16）：新市场源必须同时满足三关——公开只读 API、可匿名获取安装物、安装物可内容寻址——三关不齐只能做「打开网页」型源；接入只改 `core/Sources.swift` 一处。网络白名单在 2.0 §7-7 基础上仅扩两条：`api.skillhub.cn` 与其 302 目标 COS 域（均受来源开关控制，关闸即零出网）；其余任何域名照旧禁止。市场的评分、认证、审核标签一律只展示，不得作为跳过本地扫描或降低审批级别的依据。

## 8. 里程碑

| 里程碑 | 内容 | 演示脚本 |
|---|---|---|
| M1（WP0+S+I） | 四名词结构落地，运维有家 | 周一晨会演示：打开收件箱清掉真机 10 个挂载问题；供给页给一个新项目套场景包，回执报数字 |
| M2（+L+D+M） | 库、创作、发现闭环 | 点角标改档三方一致；新想法 5 分钟沉淀并 simulate 第一；搜「写作」从 SkillHub 装一个技能，全程走扫描与审阅 |
| M3（+H+Z） | 手册 + 卫生 → 发 2.1.0 | 无上下文 agent 照手册走通四条工作流；四路截图上 landing；tag v2.1.0（Info.plist 版本与 release.yml 校验同步） |

## 9. 未决问题（实施中验证，不许拍脑袋）

0. marketplace.json 解析器挪 P2（2026-08-28 实施注记）：市场仓库本质是 GitHub 仓库，粘贴链接经既有管线已可安装（detect 会扫出其中全部 SKILL.md），发现页已提供 anthropics/skills 官方货架；解析器只省一步浏览，优先级让位。SkillHub zip 直装（ADR-16）已落地并进验收（bsdtar 安全边界四类攻击实测：`..` 拒、绝对路径消毒、穿链拒、符号链接条目由解包后全树遍历整包拒收）。

1. 项目级 `.claude/skills` 扫描与展示（P2；牵动 Scanner 数据模型）。
2. Codex 的项目级供给机制（继承 2.0 未决）。
3. 菜单栏 palette 是否加「收件箱」第三模式（等 WP-I 落地后按使用数据决定，默认不加）。
4. `atlas doctor --inbox-json` 是否转正为 `atlas inbox`（等探针与菜单栏需求明确再说，先不占命令名）。
5. Usage/Trend 合并后，转录回扫的降级节奏（hook 数据满两周后是否停默认回扫）。
6. `-atlasSelect` 探针在无头启动下不重绘高亮与详情栏（2026-08-28 实测，2.0.0 同症；`-atlasAction` 探针证明选中状态已置位，交互会话正常；`-atlasSelectMany` 走 `refreshVisible()` 可正常重绘）。四路截图验收需要交互会话或先解此渲染怪癖；批量条截图已用 `-atlasSelectMany` 覆盖。
