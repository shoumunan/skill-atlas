# Skill Atlas · 技能图谱

本地 AI 技能管理器：扫描散落技能、从 CC Switch 迁入、安装 / 卸载 / 更新、跨平台软链同步。替代 CC Switch 的技能管理，不是仪表盘。

**管理边界：Skill Atlas 管自己的库，CC Switch 原数据不动。** 禁止写入 `~/.cc-switch/cc-switch.db` 和 `~/.cc-switch/skills/`。

**目录对标 CC Switch，全部在一个文件夹：**

```
~/.skill-atlas/
  atlas.json          # 元数据
  skills/             # 技能源目录（平台软链指向这里）
  skill-backups/      # 卸载前备份，最近 20 个
  migration.json      # 回滚清单
```

首次启动若 Application Support 里还有旧 `atlas.json`，会一次性搬进来。迁入用 `cp -c` 克隆到本库，再改软链；不删 CC Switch 原文件。

**纯原生 macOS 应用**（14+）：Swift + SwiftUI，`NavigationSplitView` + 系统侧栏 / 工具栏。进程内读 SQLite 与文件系统，不内嵌网页。

## 扫描

扫描 `~/.skill-atlas/skills`、`~/.cc-switch/skills`（只读，仅未迁完时）、以及本机存在的 `~/.claude/skills`（resolve 后可能是 `~/.mirasim/skills`）、`~/.codex/skills`、`~/.grok/skills`、`~/.workbuddy/skills`、`~/.openclaw/skills`、`~/.<gemini|opencode|hermes>/skills`。按 `resolvingSymlinksInPath` 去重。平台目录**始终**扫描——已从 CC Switch 迁移完成的用户后来手动装的散装技能也会被发现（供收编）。

## 使用

双击 `Skill Atlas.app`。首次打开会扫描；若有尚未迁完的 CC Switch 技能，弹出迁移对话框（可跳过）。

- 侧栏（文字导航）：技能库 / 体检 / 指南 / 设置（⌘1–⌘4）
- 指南（教学页，v1.5.0 重做）：单面板六节 + 顶部锚点条——上手（三步跑通）/ 关系（概念关系图：你 → Agent 应用 → Agent → Skill 与 MCP，SwiftUI 原生绘制，点一层看它是什么）/ 机制（开会话注入清单、命中才读正文，及由此推出的预算与截断）/ 排查（四级证据 + 六步清单 + **页内实时试触发**，当场输入一句话看谁抢答）/ SKILL.md（真实骨架 + 自己写一个 + 快捷键 + 常见问题）/ 本机数据（与体检页同源的三个数）。举例全部从你自己的库里动态取，取不到就不举例
- 窗口内 `⌘K` 聚焦搜索（任务别名：搜「做个PPT」能命中 pptx），`⌘R` 重新扫描，`⌘N` 安装
- 任何应用里 `⌥⌘K` 呼出菜单栏快速搜索，回车复制调用语（设置页可关掉菜单栏图标）
- 平台 logo 彩色芯片（Claude Code / Codex / Gemini / Grok / WorkBuddy / OpenClaw）：点亮/置灰，单击切换挂载。OpenClaw 标是自绘「三道爪痕」glyph（规避官方商标），装前安全扫描与后台复扫对该平台技能同样生效——ClawHub 恶意技能事件后的本地防线
- 本地直装收编：散装在 `~/.claude/skills` 等平台目录里的技能（来源「本地安装」）始终会被扫描到（含已迁移用户后装的）。有散装技能时列表顶部出现**收编条**——「n 个本地技能可收进本库」+「全部收编」（确认后批量执行）；也可在详情页「管理」区或右键单个「收进 Skill Atlas 库」。收编 = 拷入本库、原散装目录替换成指向库的软链、按它原本所在的平台写启用位，收编后平台 logo 开关解锁。实体在平台目录之外（软链指开发目录）的收编前有断开提醒；安装 sheet 选到平台目录 / CC Switch 源里的文件夹会被拦下改道（走收编 / 迁移）。不写 CC Switch 迁移回滚清单，反向操作走常规卸载
- 更新审阅与补丁保护（三期 G1，v1.5.0 起）：有新版本时列表顶部出现更新条（重新检查 ⌘U / 审阅并更新 ⇧⌘U），侧栏技能库行角标 = 可更新数。**没有不经审阅的更新**——单个更新弹 diff 审阅页（上游 stat + SKILL.md 全文 diff + 本地改动警示），批量更新弹逐技能折叠审阅；确认后每个技能先快照到 `skill-backups/` 再 `git pull --ff-only`；本地改过的技能先把改动导出成补丁存 `skill-patches/`，更新后 `git apply --check` 通过才重放、绝不留冲突标记（重放不干净时保持纯上游版并明示），批量更新时本地改过的默认跳过、只能去详情页单独审阅；详情页可一键回滚到最近备份（回滚前会再拍一张快照，回滚本身可回滚）
- 体检：挂载异常、描述体检（丢弃风险/截断/缩短建议）、触发词重叠、长期未用（行内单个停用 +「全部停用」批量治理）、上下文预算——健康信号只在这一页
- 设置：界面样式（跟随系统/浅色/深色）、语言（跟随系统/简中/English/日本語/한국어，切换即时生效，技能内容保持原文）、菜单栏开关、库位置与扫描范围、**本地技能收编**（散装计数 + 全部收编，人人可见）、CC Switch 迁移机制图（只对有 CC Switch 数据的用户显示）、应用内自动更新。侧栏底部信任锚点分场景：CC 用户见「CC Switch 数据只读」，纯本地用户见「收编前不动你的文件」
- 清理 CC Switch 副本（迁移后回收磁盘）：逐目录校验「已在本库 + SKILL.md 可读 + 挂载指向本库」，未通过的保留；确认不可逆警告后移入废纸篓，`cc-switch.db` 永远不动，清理后「撤销迁移」失效
- 触发模拟（二期 F1）：菜单栏 ⌥⌘K 切「试触发」，输入打算说的话看谁会抢答（名次 + 命中词 + 丢弃风险/埋深标记）；体检页新增「触发词埋太深」检查（250 字符可见窗口口径）
- 描述开药（三期 G2，v1.5.0 起）：体检页「埋深/会被截断/建议缩短」行尾有「开药」——生成改写稿（**只重排句子不增删一字**：含「」触发词的句子前置进 250 字符可见窗，能力句仍居首）；处方 sheet 里前后对照（250 字符可见线肉眼可辨）+「疗效试触发」同一句话改前/改后各排第几；采纳即写回 SKILL.md frontmatter（CC Switch 只读来源禁写；git 技能算本地改动、更新时受 G1 补丁保护）。机器改不动的诚实说改不动，给「复制 Claude 改写指令」（Trigger Triad 模板）逃生门
- Hook 实时遥测（三期 G5，v1.5.0 起）：设置页「Hook 实时遥测」一键接入——在 `~/.claude/settings.json` 注册 PostToolUse(Skill) hook（写入前原文备份到 `~/.skill-atlas/settings-backups/`，只增删自己的条目，settings 不是合法 JSON 时拒写），Skill 工具每次调用追加一行事件到 `~/.skill-atlas/usage-events.jsonl`（hook 脚本永远 exit 0 不阻塞）；App 把事件口径并进使用统计——grep 漏计的补会话数、最近使用取较新者，长期未用/丢弃模拟不再冤枉正在用的技能
- 一键发起（二期 F2）：详情页「发起会话」或 ⌥⌘K 回车——填主题 → 自动建 projects/<体裁>/<日期_主题>/ → Terminal 在正确目录起 claude 会话（⌥回车=仅复制；首次需允许控制 Terminal）
- 装前安全扫描（二期 F3）：安装时静态扫描动态上下文命令、curl|sh、Base64 藏命令、隐藏 Unicode、全权 allowed-tools、硬编码密钥、外链清单；关键级强制审阅页展示命中行原文；已装技能后台复扫，结果在体检页与详情页。（v1.6.0 修：`allowed-tools: *` 这种裸星号全权声明此前完全漏报；隐藏 Unicode 不再把 ZWJ 组合 emoji 与 UTF-8 BOM 误判成 critical）
- 注册表发现（三期 G6-lite，v1.6.0 起）：安装 sheet 里一条可折叠的「不知道装什么？搜公开注册表」——搜 skills.sh，选中**只是把 `https://github.com/<owner>/<repo>` 填进上面的输入框**，之后完全走既有的 parse → clone → detect → 装前扫描 → 勾选管线。刻意不做路径解析：注册表的 id 第三段是 SKILL.md 的 name 而非仓库子目录（实测约两成推不出路径），完整版得靠多级启发式猜路径、还要把第三方字符串拼进文件系统路径；降级版零新增解析、零新增穿越面，唯一路径入口仍是硬限 `github.com` 的 `parse()`。非 GitHub 来源（smithery.ai 等）在列表里直接置灰。搜索词会发往第三方服务，界面明写，可用 `-atlasRegistryEnabled NO` 关闭
- 产出回链（二期 F4）：生产技能详情页「最近产出」列最近 5 次成稿目录，点击打开、悬停可用同主题重跑
- 素材投递箱（二期 F5）：把文件拖进主窗口任意位置——按文件名/类型匹配技能（自运营数据→somd、研报 PDF→research-index、成稿→to-xhs），确认后带路径发起会话
- 生产链路（二期 F6）：详情页展示上游/下游/依赖（hotspot→to-voiceover→to-xhs），点击跳转，不自动编排
- 分组视图（二期 F7）：列表「分组」菜单按套件（cheat/dbs/xiaohongshu…）或类别折叠 143 个平铺项，纯逻辑分组不动目录
- 多机同步（二期 F8）：设置页把 ~/.skill-atlas/ 一键 git 化（init/快照提交/状态），远端与 push 在终端做；换机 clone 后重新扫描即重建挂载。`.gitignore` 每次扫描/提交前幂等补齐（settings 备份、事件日志、沙箱、Profile 快照一律不入库——它们含用户 env 与使用行为）
- 场景 Profile（三期 G8，v1.6.0 起）：设置页「场景 Profile」→ 管理场景 → 勾选「这个场景真正要用的技能」。落地走 Claude Code 自己的 `skillOverrides`（用户级/项目级级联）：非成员写成 `user-invocable-only`（仍可 `/技能名` 手动调用，只是不进模型的自动匹配清单）或 `off`。两种作用域——「设为默认」写 `~/.claude/settings.json` 管所有会话；「绑定到目录」写 `<项目>/.claude/settings.local.json`，**App 关掉照样生效**，解决「在 Jung8 目录开会话别出现基金技能」。写盘前必过确认页（列出摘出/保留/重名冲突/你自己设过的覆盖），原文按来源分域备份到 `settings-backups/<来源>/`；撤销只删本 App 写过且值未被改动的键，绝不把键设成 `on`（那也是一条覆盖，会压住你在 `/skills` 里的选择）。只对 Claude Code 生效，界面直说
- 单技能试跑（三期 G3，v1.6.0 起）：详情页「单技能试跑…」——用 `CLAUDE_CONFIG_DIR` 把配置根重定位到 `~/.skill-atlas/sandbox/<技能>-<时间戳>/config`，里面只放这一个技能的 clonefile 副本（**不是软链**，试跑里改它不会碰到库里的原件）并关掉内置技能，`CLAUDE_SECURESTORAGE_CONFIG_DIR=''` 保住钥匙串登录态不用重新登录。确认页把「不隔离什么」摊开：**它不是安全沙箱**，会话里的命令仍以你本人身份运行、能读写整机、能联网，也共用你的额度；权限询问保持开启。不自动清扫（正在跑的会话不会告诉 App 它还活着），设置页手动一键移入废纸篓
- 卸载：右键或详情页；可选只卸挂载或连库内目录进废纸篓
- `⌘E` 导出 Markdown 技能清单

## 构建

修改 `native/swift/` 后双击 `构建原生应用.command`。脚本先试 SwiftPM，失败则 `xcrun swiftc` 回退（本机无完整 Xcode 时走这条）。产物 `Skill Atlas.app`。

调试参数：`-atlasPage library|doctor|guide|settings`（updates 已并入 library）、`-atlasAppearance dark|light`（优先于设置页的界面样式）、`-atlasWindow 1380x860`、`-atlasHome /path`、`-atlasSelect <技能名>`、`-atlasForceMigrate`、`-atlasCleanup`（打开清理向导）、`-atlasScanProbe <path>`（装前扫描结果落盘）、`-atlasTriggerProbe <话> -atlasProbeOut <path>`（触发预演落盘）、`-atlasLaunchProbe <技能> -atlasLaunchTopic <主题> -atlasProbeOut <path>`（发起器 dry-run，不开终端）、`-atlasOutputsProbe <技能> -atlasProbeOut <path>`（产出回链落盘）、`-atlasDropProbe <文件> -atlasProbeOut <path>`（投递规则匹配落盘）、`-atlasUpdateReviewProbe <技能> -atlasProbeOut <path>`（更新审阅落盘：上游 stat/diff + 本地改动清单）、`-atlasApplyUpdateProbe <技能> -atlasProbeOut <path>`（执行带保护更新：备份名/补丁路径/是否重放落盘）、`-atlasRollbackProbe <技能> -atlasProbeOut <path>`（回滚到最近备份并落盘结果）、`-atlasRxProbe <技能> -atlasProbeOut <path>`（描述开药处方落盘：改写稿/改法/前后埋深）、`-atlasRxApplyProbe <技能> -atlasProbeOut <path>`（出处方并写回 SKILL.md）、`-atlasHookProbe install|uninstall|status -atlasProbeOut <path>`（Hook 遥测装/卸/状态落盘）、`-atlasProfileProbe create|apply|bind|unbind [-atlasProfileName <名> -atlasProfileMembers <逗号分隔目录> -atlasProfileDir <目录>] -atlasProbeOut <path>`（场景 Profile 全链路落盘）、`-atlasSandboxProbe <技能> -atlasProbeOut <path>`（建试跑沙箱并落盘计划，不开终端）、`-atlasToggle claude`、`-atlasAppcastURL <地址>`（更新源覆盖，支持 file://）、`-atlasAutoUpdate 1`（启动即拉 appcast 并应用内换装，验收自更新链路）、`-atlasQuit YES`。

## 发布与自更新

更新源 = 本仓库主分支的 `appcast.json`（App 内置指向 `github.com/shoumunan/skill-atlas`）。发新版三步：

1. `打包DMG.command` 出 `dist/Skill Atlas-<版本>.dmg`——脚本末尾直接打印 sha256 和可粘贴的 appcast 片段
2. DMG 传到 GitHub Release（tag `v<版本>`；GitHub 会把资产文件名里的空格改成点）
3. 按脚本打印的片段改 `appcast.json`（`version` / `notes` / `dmg` 直链 / `sha256`）推到 main

**应用内自动更新（v1.5.0 起）**：旧版「检查更新」发现新版后，首选「自动更新」——`SelfUpdater` 下载 DMG（appcast 的 `dmg` 直链优先，缺省时查 GitHub Releases API 找 `.dmg` 资产）、sha256 校验（appcast 给了才校）、只读挂载并核对包内版本、拷到暂存目录去 quarantine（ad-hoc 签名 + 隔离位会被 Gatekeeper 拦启动）、退出后由 shell 助手备份旧包 → 换装 → 失败回滚 → 自动重启，日志在 `~/.skill-atlas/update.log`。「打开下载页」保留为手动逃生门；App Translocation 状态下拒绝自更并提示移入「应用程序」。

## 打包

双击 `打包DMG.command` → `dist/Skill Atlas-1.5.0.dmg`（版本号读自 Info.plist）。ad-hoc 签名，首次打开需右键 →「打开」绕过 Gatekeeper。macOS 14+、Apple 芯片。旧版 DMG 保留。

设计规范见 [`DESIGN.md`](DESIGN.md) ⑩。
