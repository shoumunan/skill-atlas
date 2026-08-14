# Skill Atlas · 设计规范（v3，Liquid Glass 重做版）

本文档是 `native/swift/Theme.swift` 的唯一事实来源：代码里的每个令牌、每层材质、每条动效都应能在这里找到出处。截图验收样张见 `docs/screenshot-*.png`（三页 + 暗色 + 紧凑窗口）。

---

## ⓪ v7 信息架构重排（2026-08-14，与下文冲突以本章为准）

| # | 改动 | 细节 |
|---|------|------|
| 1 | 侧栏改文字导航 | 76pt 图标轨 → **176pt 文字列表**（参考 CC Switch）：顶部品牌行（应用图标 30 + 「Skill Atlas / 技能管理」）、四项行式导航（图标 14pt + 标签 + 右侧角标，高 34，选中 accent 13% 圆角矩形 + matchedGeometry），底部「CC Switch 数据只读」锁行。工具条标题簇左缘随之改为 **200pt**（12+176+12） |
| 2 | 「更新」不再是一级页 | 侧栏四项：**技能库 / 体检 / 指南 / 设置**（⌘1–⌘4）。可更新状态并入技能库：列表顶部出现**更新条**（accent 7% 底：n 个技能有新版本 · 重新检查 · 全部更新；点文字筛出可更新），行尾保留 ↓ 角标，详情管理区保留「更新到最新」。侧栏技能库行角标 = 可更新数 |
| 3 | 健康信号撤出列表 | 列表行不再放健康小黄灯（只保留「已停用」与更新角标）；筛选行的「健康」菜单改为「状态」（全部/可更新/已停用）。健康入口唯一收在**体检页**；详情页仅在真有问题时出现警示卡（含「到体检页查看全部问题」链接） |
| 4 | 「怎么用」改名「指南」 | 与技能库/体检/设置的二字名对齐。页面重排为「三步把技能用起来」主线（挑技能→复制调用语[活例子]→贴进 Agent）+ 右列 400pt（三个名词 / 装多了会怎样 + 去体检 CTA） |
| 5 | 体检页统一面板骨架 | 预算带全宽；左列「需要修复」「描述体检」（丢弃风险+截断+缩短建议三组并一）、右列 400pt「长期未用」「触发词重叠」。四面板共用 `DoctorPanel` 头（彩色图标章 22 + 标题 + 计数胶囊 + 一行副文案 + 右上角注） |
| 6 | 设置页系统设置化 | 居中 640 列四组：**外观**（界面样式 跟随系统/浅色/深色 = `AppearanceMode`，NSApp.appearance 全局生效并持久化；菜单栏快速搜索开关 = `MenuBarExtra(isInserted:)`；语言信息行）、**技能库**（库位置/扫描范围披露/重扫）、**从 CC Switch 迁移**（三节点机制图：CC Switch --复制--> 本库 --软链--> 四平台 + 无 CC Switch 用户说明 + 状态/迁入/撤销）、**应用**（版本/检查更新） |
| 7 | 安装入口显性化 | 工具条 `+` 圆钮 → **「+ 安装技能」强调色玻璃胶囊**（`accentGlass`：强调色纵向渐变 + 顶部内侧白光 + 镜面顶边 + 品牌色环境阴影）。主按钮（复制调用语/全部更新/迁入/去体检）统一走 `accentGlass` |
| 8 | 快捷键文案讲清两把钥匙 | 搜索胶囊徽标 ⌘K（窗口内聚焦）；页副文案与 .help 写明「随处按 ⌥⌘K 快速搜索」（全局菜单栏浮层）。搜索聚焦时 accent 描边 + 微光聚焦环 |
| 9 | L2 玻璃补底缘收暗 | GlassChrome 增加下沿 1pt 黑色渐变内描边（亮 .10 / 暗 .30），上缘受光、下缘收暗，玻璃有厚度 |
| 10 | 技能列表去斑马纹 | inset List（alternatesRowBackgrounds）不透明条纹像表格软件 → `ScrollViewReader + ScrollView + LazyVStack + panelScroll` 玻璃行：透明底、悬停 primary 4%、选中 accent 12% 圆角行 + accent 20% 发丝，L1 材质与 L0 环境光从行间透出；↑/↓ 与选中联动 `scrollTo` |
| 11 | 更新检查自触发循环修复 | `git fetch` 写 .git → FSEvents → rescan → 又 fetch 的死循环：检查全程 `pauseWatching`、后台自动检查 30 分钟节流（手动不限）、后台检查不再展示进度（只有手动「重新检查」露脸）；rescan 继承上一轮 updateAvailable 标记，pull 成功就地清标记 |
| 12 | 清理 CC Switch 副本 | 设置页迁移组新增「检查并清理…」（已迁移才出现）→ `CleanupSheet` 三段式：逐目录校验（已在本库 / SKILL.md 可读非空 / 启用平台挂载 resolve 后落在本库）→ 红字不可逆警告（进废纸篓、清空后无法恢复、撤销迁移失效、CC Switch 里显示缺失）→ 移入废纸篓并删除 migration.json。未通过校验的原样保留；`cc-switch.db` 永远不动。调试参数 `-atlasCleanup` |
| 13 | 首次治理快赢（需求清单 1/2） | 长期未用面板顶部「全部停用（n）」批量按钮 + `confirmationDialog`（可回收 token、不删文件、CC Switch 来源跳过；`disableAllStale` 全程只重扫一次）；技能库排序新增「最近使用」；设置页「扫描范围」从桩数据改为真实清单（本库 + CC Switch 源标只读 + 各平台根，软链标注 resolve 落点） |

---

## ① 本次重做修掉的问题清单

| # | 问题 | 修法 |
|---|------|------|
| 1 | 左上角交通灯按钮与侧栏图层重叠 | 窗口顶部划出 44pt 全宽工具条区，左侧 84pt 只留 L0 背景给交通灯；空 `NSToolbar` + `unifiedCompact` 把交通灯下移到工具条视觉中线；侧栏 rail 从工具条之下才开始 |
| 2 | 顶部搜索框与底部推荐输入框重复设计 | 技能库只有顶部搜索胶囊；推荐输入是总览页主角（点名调用格式在输入旁 `.help`） |
| 3 | 字号 11 档失控（10/10.5/11/11.5/12/12.5/13/14.5/15.5/19/27…） | 收敛为 8 档字阶（见 ③），写进 `Theme.Fonts`，全应用禁止其他字号 |
| 4 | 间距无网格，7/9/11/13/14 随手写 | 4pt 网格：只允许 4/8/12/16/20/24/32（`Theme.Space`）；列表行内边距固定 水平12/垂直10 |
| 5 | 玻璃层级错误：内容面板也是玻璃，玻璃叠玻璃 | 三层材质体系（见 ④）：玻璃只给 chrome（侧栏、工具条控件、指南页胶囊）；列表、统计、详情全部换成安静的 L1 内容表面 |
| 6 | 无镜面高光，材质是「一层白纱」没有光源感 | L2 玻璃增加 1pt 镜面顶边（白 .85→透明的渐变描边，只亮上缘）+ 顶部内侧径向白光，几何上缘受光、下缘收暗 |
| 7 | 阴影单一（一层大投影） | 环境阴影（black .10 r18 y10，大而软）与接触阴影（black .18 r2 y1，小而实）分离；L1 用更轻的 black .06 r14 y8 |
| 8 | 无入场/切换/悬停动效 | 启动时工具条→侧栏→内容 0.05s 错峰上浮 12pt 淡入（只播一次）；切页 `.opacity + .offset(y:10)` 转场；行/tile hover 上浮（scale 1.01 + 阴影加深） |
| 9 | 导航选中硬切 | 侧栏选中胶囊用 `matchedGeometryEffect` 在项间滑动；收藏分段的选中滑块同理 |
| 10 | 统计数字静态 | 指标数字 `.contentTransition(.numericText())`，重新扫描时刷新按钮图标旋转 |
| 11 | 图标质感弱（纯色块） | 分类图标：实色连续圆角方块（半径=尺寸 30%）+ 顶部镜面高光渐变 + 白 .35 发丝 + tint 投影 |
| 12 | 工具栏无秩序（标题/搜索/按钮挤在 ZStack 里互相盖） | 44pt 工具条固定秩序：交通灯区(84) → 页标题(17) → Spacer → 搜索胶囊(300，仅技能库) → 刷新圆钮 → 「更新于 HH:mm」caption |

---

## ② 官方设计原则依据

来源：WWDC25 [Session 219「Meet Liquid Glass」](https://developer.apple.com/videos/play/wwdc2025/219/)、[Session 356「Get to know the new design system」](https://developer.apple.com/videos/play/wwdc2025/356/)、[Session 323「Build a SwiftUI app with the new design」](https://developer.apple.com/videos/play/wwdc2025/323/)、[HIG · Materials](https://developer.apple.com/design/human-interface-guidelines/materials)。

1. **玻璃只属于导航/控件层**：Liquid Glass 是浮在内容之上的 chrome 材质（侧栏、工具栏、悬浮控件）。内容层（列表、表格、详情、统计）用安静的标准表面，让内容「从玻璃下透出来」。玻璃不能采样玻璃，禁止玻璃叠玻璃。
2. **高光层（highlights）**：想象一个光源照在材质上，镜面高光随几何形状变化——顶部边缘亮、底部收暗；交互时从内部发光。
3. **阴影层（shadows）**：动态阴影把玻璃从背景上「托起」；环境阴影（大而软）与接触阴影（小而实）职责分离。
4. **同心圆角（concentricity）**：嵌套元素半径 = 父半径 − 内边距；胶囊形只给大号、需要突出的控件；桌面端高密度小控件用圆角矩形。
5. **内容层呼吸感**：行高与内边距加大、分组圆角加大，密度让位于层次。

> 本机 SDK 为 macOS 14.0（Xcode CLT / Swift 5.9），macOS 26 的 `.glassEffect()` 编译期与运行期均不可用，因此以上原则全部用手工图层近似实现（材质 + 渐变描边 + 双阴影），见 ④。

---

## ③ 设计令牌

### 字阶（8 档，SF Pro，中文自动回退苹方；禁止其他字号）

| 令牌 | 规格 | 用途 |
|------|------|------|
| `metric` | 28 semibold rounded + monospacedDigit | 统计大数字 |
| `pageTitle` | 17 semibold | 工具栏页标题、详情头名称 |
| `panelTitle` | 15 semibold | 面板标题、总览推荐区标题 |
| `rowTitle` | 13 semibold | 行/条目/tile 标题 |
| `body` | 13 regular，行距 +2 | 正文（用途、说明） |
| `callout` | 12 regular（强调 medium） | 次要正文、chips、控件文字 |
| `secondary` | 11 regular（区块小标题 11 medium） | 辅助信息、副行 |
| `caption` | 10 medium | 导航标签、徽标、时间戳 |
| `mono` | system 11 monospaced | 路径与代码，一律用它 |

### 间距（4pt 网格）

- 允许值：**4 / 8 / 12 / 16 / 20 / 24 / 32**
- 窗口内边距 12；面板间隙 12；面板内边距 16 或 20
- 列表行内边距：水平 12 / 垂直 8（行高约 44–48）
- 工具条区高 44，左侧交通灯留白 84（布局常量，不属间距网格）

### 圆角（嵌套递减）

| 元素 | 半径 |
|------|------|
| 侧栏 rail | 20 |
| 内容面板（L1） | 16 |
| tile | 12 |
| 列表行 | 10 |
| 小控件（筛选、按钮、chips） | 8 |
| 大控件（搜索、助手输入、刷新钮、导航选中） | 胶囊 / 圆 |
| 图标方块 | continuous，半径 = 尺寸 × 30% |
| 同心示例 | 分段容器 8 − 内缩 2 = 滑块 6 |

### 颜色

| 角色 | 值 |
|------|-----|
| 唯一强调色 | `#0A84FF` |
| 健康三色 | `#34C759` / `#FF9F0A` / `#FF453A` |
| 分类 tint | 沿用 `Categories.meta`，**只允许出现在图标 squircle 上** |
| 主文本 | 黑 .85（暗色：白 .85） |
| 次文本 | 黑 .55（暗色：白 .55） |
| 三级文本 | 黑 .35（暗色：白 .35） |
| 分隔发丝 | `Color.primary` 6% |
| 安静控件 | `Color.primary` 4% 填充 + 8% 发丝 |
| L0 环境光 blobs | sky `#9CC7F7` / periwinkle `#B4B8F2` / mint `#A9E3C6`（低饱和，只出现在 FluidGradient 层） |

除以上表格外禁止新增彩色。

**色彩收敛规则（强约束）**：

1. **每个分类色在一个视图里最多出现一次，且只出现在图标方块上。** 总览 tile、指南分类 cell、列表行、详情头部一律：彩色图标 squircle + 中性底（安静样式：primary 4% 填充 + 8% 发丝）+ 中性文字（主 .85 / 次 .55 / 三级 .35）。禁止把分类色重复用于 tile 底色、描边、计数或文字。
1a. **图标方块的密度规则**：分类色在密集列表里每行重复一次，总色量 = 行数 × 饱和度，降饱和度是唯一不牺牲分类识别的路径。
   - **密集重复场景**（技能列表行、健康页问题行、总览最近安装行、指南推荐结果行）：`CategoryIcon(style: .quiet)` —— 分类色 15% 淡底（暗色 24%，否则 glyph 会糊）+ 分类色本色 SF Symbol glyph，同尺寸同圆角，无投影无高光。
   - **单实例展示场景**（详情面板头部大图标、总览分类 tile、指南分类 cell）：保持 `.solid` 实色方块 + 白 glyph + 顶光，作为身份锚点。
2. **健康语义色只出现在状态徽标（警告/异常 chip、状态点）和严重度条上**，同一行内其余元素全部中性。
3. **强调蓝 `#0A84FF` 只用于四处**：导航选中、搜索聚焦环、主按钮（含助手输入的提交钮）、收藏选中（星标亮起用 accent，不用警告橙）。

---

## ④ 三层材质体系（Theme.swift 的核心）

### L0 背景

`NSVisualEffectView(underWindowBackground)` 采样桌面 → 叠 [FluidGradient](https://github.com/Cindori/FluidGradient)（MIT）低饱和流动渐变（speed 0.2、blur 0.75；亮色 opacity 0.35，暗色 0.22）→ 叠白纱（亮 .12 / 暗 .03）。这层给玻璃提供可折射的「活的」环境光影；交通灯直接落在这层上。

### L1 内容表面 `ContentSurface`

- `.regularMaterial` + 白 .45 提亮（暗色：白 .05）
- radius 16 continuous，白 .35 发丝描边 0.5pt（暗色 .10）
- 单层软阴影 black .06 r14 y8
- 用于：统计带、列表面板、详情面板、总览/指南/健康页的所有板块

### L2 玻璃 chrome `GlassChrome`

- `.ultraThinMaterial`
- 顶到底白色渐变纱 .35→.15（暗色 .12→.04）
- **镜面顶边**：1pt 描边 LinearGradient 白 .85→透明（35% 处消失，只亮上缘；暗色 .50）
- 白 .45 发丝整圈 0.5pt（暗色 .20）
- 双阴影：环境 black .10 r18 y10 + 接触 black .18 r2 y1
- 顶部内侧径向白光 .20（暗色 .10）
- **只用于**：侧栏 rail、工具条上的搜索胶囊与刷新圆钮、总览推荐输入胶囊。玻璃下方永远是 L0，绝不叠在 L1/L2 上。
- 可交互玻璃 hover：纱 +.08、阴影加深、scale 1.01 控件弹簧；按下 scale 0.97

---

## ⑤ 信息架构与页面框架

### 页面分工（v1.2.2 外壳回玻璃轨）

独立总览页已删除。侧栏五级图标轨：技能库 / 更新 / 体检 / 怎么用 / 设置。快捷键 ⌘1–⌘5。窗口是手工 L0/L1/L2 玻璃壳（hiddenTitleBar + 76pt 玻璃 rail + 44pt 工具条），**禁止** `NavigationSplitView`、系统 sidebar List、斑马纹 inset List。空库时内容区换为安装引导。完整功能地图见 ⑩。

### 工具栏页面标题（层级规则）

标题不允许是孤立的粗体词。页面身份簇 = **图标章（24pt，accent 12% 圆角方块 + accent 11pt SF Symbol）+ 标题 `rowTitle` + 活副文案 `caption`**（第三级文本色）。副文案随数据变化：总览「129 个技能 · 9 个分类」、技能库「129 个技能，⌘K 直接搜索」（筛选时改为「筛选出 n / 总数 项」）、健康「n 项需要关注 / 所有检查项都正常」。

### 页面框架（填满式）

macOS 原生应用的做法（Finder / 音乐）：每页内容区域 = 工具条以下到窗口底部 inset（12pt）之间，**主面板一律 `maxHeight: .infinity` 拉伸到底边线**，多个并排面板自然等高。留白只发生在面板内部（内容顶部对齐，面板下部是内部呼吸空间），不允许出现面板之间或页面底部的裸背景真空带。

- **技能库**：列表 + 详情两块 L1 面板填满；搜索在顶部工具条胶囊（含任务别名）
- **更新 / 体检 / 怎么用 / 设置**：各自 L1 面板拉伸填满
- **健康**：统计带 + 问题面板（弹性宽）/ 右列 440pt（触发词重叠、长期未用两面板纵向等分）拉伸填满 + 底部说明面板固定，间距 12pt
- 面板内容放不下面板高度时（小窗口），一律在**面板内部滚动**，禁止溢出面板圆角或把面板撑破底边线
- **面板内滚动区一律 `.panelScroll()`**（Theme.swift）：`scrollIndicators(.never)` 强制隐藏系统滚动条（`.hidden` 会被系统「始终显示滚动条」设置覆盖，常驻轨道会压在圆角玻璃面板边上）+ 底部 16pt 边缘渐隐做滚动暗示。禁止任何内容面板出现系统轨道式滚动条

> v3 曾试过「hug-content 浮岛构图」（面板贴合内容、把剩余空间留给背景），在真实窗口尺寸下产生大片真空带与不等高面板，已撤销，禁止回退。
> 调用指南页（v4）因静态文案信息效率低，v6 删除。

## ⑥ 组件规范

- **工具条（44pt，L0 上，纳入页面网格）**：交通灯区独占 0–100pt → 页面身份簇（图标章 + 标题 + 活副文案，见 ⑤ 标题层级规则；**左缘 = 100pt**，即窗口 inset 12 + 侧栏 76 + 面板间隙 12，与下方面板左边线严格同线）→ Spacer → 搜索胶囊（宽 300、高 32、玻璃、⌘K 徽标，仅技能库页）→ 刷新圆钮（32、玻璃）→ 「更新于 HH:mm」`caption`（**右侧组右缘 = 窗口宽 − 12**，与面板右边线同线）。**光学中线统一在 22pt**：内容在 44pt 条内自然居中；unifiedCompact 默认把交通灯中心放在 18.75pt，`WindowConfigurator.alignTrafficLights` 把三枚按钮下移到 22pt 与全员归零（窗口 resize 后重新应用）
- **侧栏 rail（宽 76、radius 20、玻璃）**：顶部品牌位加载应用包内 `SkillAtlas.icns`（回退 `NSApp.applicationIconImage`），按 1024/824 放大裁掉苹果网格自带的透明边距后铺满 36pt 连续圆角方块（radius 8）——与 Dock/访达永远同一套 artwork，禁止手绘替身；导航五项 60×52（技能库 / 更新 / 体检 / 怎么用 / 设置；SF Symbol 17pt + `caption` 标签），选中态 accent 14% 胶囊 `matchedGeometryEffect` 滑动；底部锁形 `.help`：「不修改 CC Switch 原数据；本应用只管理 ~/.skill-atlas 技能库」
- **统计带**：单个 L1 面板四格指标，内部 1pt 发丝分隔；数字 `metric`，标签 `secondary` medium，注脚 `caption`；健康格含三色占比条 + 可点图例
- **列表行（高约 48）**：图标方块 30（`.quiet` 淡底样式，见色彩密度规则）、标题 `rowTitle`、副行 `secondary`；状态点只在非健康时显示；hover 出星标；选中 accent 12%
- **筛选控件**：安静样式（primary 4% 填充 + 8% 发丝、radius 8、高 28），激活时换强调色 tint；绝不用玻璃
- **详情面板**：头部两行——名称行（图标 44 + 名称 `pageTitle` + 仓库名 + 收藏星图标钮 28）与动作行（分类 chip + 来源 chip + 「复制调用语」主按钮，accent 实底、成功变绿勾「已复制」1.2s）；区块间距 20、区块标题 `secondary` medium；示例说法 chips radius 10 + 复制按钮（对勾 `.symbolEffect(.replace)` 切换）；路径 `mono`；本地技能的「挂载状态」块替换为「安装方式」（Claude Code / Codex 本地安装）
- **列表行复制**：悬停或选中时在收藏星左侧出现复制小按钮（24×24，同星标样式），复制该技能调用语
- **使用情况块（详情页，v5）**：三列迷你指标（调用会话数 / 最近使用日期 / 平台分布「Claude n · Codex n」），数值 `calloutEmphasis` 等宽数字 + 标签 `caption`；索引进行中显示小号 ProgressView +「正在索引使用记录… n%」；无记录显示「未发现使用记录」二级文本。悬停 `.help` 展示索引口径（文件数/增量数/耗时）。**统计带不加第五格**——四格布局是上限，使用指标只落在详情页与健康页
- **长期未用面板（健康页右列，v5）**：与触发词重叠同款观察面板（右上「不计入健康」角标），行 = `.quiet` 图标 24 + 名称 `rowTitle` + 尾注 `caption`（「从未使用」/「上次 yyyy/MM/dd」），点击跳详情；空态绿勾「没有吃灰的技能」
- **阅读器 sheet（v5）**：680×640，`.regularMaterial`，头部（`.quiet` 图标 28 + 技能名 `panelTitle` +「SKILL.md 完整说明」`caption` + 打开目录钮 + 关闭钮 ⌘W/Esc）+ 发丝分隔 + `panelScroll` 正文。frontmatter 折叠为「Frontmatter · n 项」披露行（展开成键值表，键 `mono` 右对齐 110pt）；正文块级自解析（h1 18 bold / h2 15 semibold / h3 13 semibold、列表、代码块 `mono` + primary 5% 圆角底、分隔线），行内粗体/行内代码/链接交给系统 `AttributedString(markdown:)`；>200 KB 截断 + 警示条（scissors 图标 + 打开目录链接）
- **停用态（v6）**：列表行整体 0.55 透明度 + 尾部「已停用」安静 chip、排在列表尾部。Skill Atlas 库：停用 = 移入 `~/.skill-atlas/skills/.disabled/` 并去掉平台软链；本地直装仍移入所在根 `.disabled/`。CC Switch 未迁出的技能保持只读。
- **tile（总览，高 56、radius 12）**：安静中性底，唯一彩色是图标 squircle；总览 tile 副行 `secondary` 显示该分类最近 2 个技能名；网格自适应列宽（总览 min 210），窗口窄时自动降列数避免截断；hover 上浮
- **空态**：SF Symbol + 标题 + 说明 + 「清除筛选」按钮（accent 安静样式）
- **加载态**：shimmer 骨架（统计 4 格 + 10 行列表；渐变遮罩位移，灵感来自开源 [swiftui-shimmer](https://github.com/markiv/SwiftUI-Shimmer)）
- **致命错误**：居中 L1 卡片（警告符号 + `panelTitle` + `body` + 强调色重试胶囊）

---

## ⑦ 动效规范

| 动效 | 规格 |
|------|------|
| 标准弹簧 | `.spring(response: 0.35, dampingFraction: 0.8)`（入场、切页、数字、严重度条） |
| 控件弹簧 | `.spring(response: 0.28, dampingFraction: 0.85)`（hover、按下、选中滑动） |
| 启动入场 | 工具条→侧栏→内容依次 0.05s 错峰，上浮 12pt + 淡入，只播一次 |
| 页面切换 | `.transition(.opacity.combined(with: .offset(y: 10)))` |
| 导航/分段选中 | `matchedGeometryEffect` 胶囊滑动 |
| 统计数字 | `.contentTransition(.numericText())` |
| 重新扫描 | 刷新图标 `linear 0.9s repeatForever` 旋转，结束无动画归零 |
| 行/tile hover | scale 1.01 + 阴影加深（控件弹簧） |
| 收藏星 | `.symbolEffect(.bounce, value: favorite)` |
| 复制按钮 | `.contentTransition(.symbolEffect(.replace))` 图标↔对勾 |
| 健康页严重度条 | 出现时宽度 0→目标值，按行 0.04s 错峰 |
| 推荐结果 | `.opacity + .move(edge: .top)` 进出 |

仅使用 macOS 14 SDK 可用的 API（symbolEffect / contentTransition / spring 等）；不使用 macOS 15+ 的 `.symbolEffect(.wiggle)`、mesh gradient 等。

---

## ⑧ 使用统计与本地管理（v5）

### 使用判定规则（2026-08-13 实测定版，Usage.swift）

- 数据源：`~/.claude/projects/**/*.jsonl` + `~/.codex/sessions/**/*.jsonl`（本机合计 991 MB / 1170 文件）。
- 一次「使用」的证据 = 会话日志行出现 `skills/<已知目录名>` 路径引用；**同一会话同一技能只计 1 次**。
- **Claude**：任意行匹配即算（转录只出现真正用到的技能）；子代理转录在 `projects/<项目>/<会话UUID>/subagents/**`，与主转录**按「项目/会话UUID」归并为同一会话**——不归并会把多子代理任务的技能虚增数倍（实测 topic-daily 333→34）。
- **Codex**：只认 `"type":"custom_tool_call"` / `"type":"function_call"` 行——Codex 把**全量技能目录**内嵌进 developer 指令与 world_state，不过滤会把所有技能判成每个会话都用过。
- 时间取该文件内最后一次引用行的 `"timestamp"`（ISO8601），取不到回退文件 mtime。
- 性能红线：**不做逐行 JSON 解码**。mmap + 字节级搜索 `skills/`，只对命中行核对类型与时间戳；按（路径, mtime, size）增量缓存到 `~/.skill-atlas/usage-index.json`。实测首次全量 3.7s，之后全命中缓存 0.03s。索引在后台线程跑，UI 显示进度。

### 管理边界（v6）

- **CC Switch 原数据：严格只读**——不写 `~/.cc-switch/cc-switch.db`，不改 `~/.cc-switch/skills` 里的文件。迁出用 APFS clonefile 复制到 `~/.skill-atlas/skills/`，再把平台软链改指新库；回滚清单在 `~/.skill-atlas/migration.json`。
- **Skill Atlas 库：本应用管理**——平台开关 = 对 Claude（resolve 后可能是 `~/.mirasim/skills`）/ Codex / GrokBuild / Gemini / OpenCode / Hermes 建或删软链；停用 = 移入 `.disabled/`；安装目标 = 该库（保留 `.git`）；有 git 的技能可 `fetch` + `pull --ff-only`。
- **未迁入的本地直装**：仍允许停用/恢复（所在根的 `.disabled/`）。
- 停用/恢复/迁出期间暂停 FSEvents 监听（写完 1s 后恢复）。
- 目录自动刷新：FSEvents 监听扫描根 + Atlas 库 + CC Switch DB，事件 2s 防抖后 `rescan(keepSelection: true)`。

---

## ⑨ 无障碍

- **Reduce Motion（`\.accessibilityReduceMotion`）为真时**：入场/切页/hover 缩放/选中滑动/数字滚动/图标旋转/严重度条全部退化为直切；shimmer 停止位移改为 60% 静态透明度；FluidGradient speed 归 0（静态色斑）。
- **Reduce Transparency（`\.accessibilityReduceTransparency`）为真时**：L0 的 FluidGradient 与白纱层整体移除，退回系统 `underWindowBackground`（系统同时会自动把 NSVisualEffectView / Material 替换为不透明表面）。
- 文本对比：主文本 .85 黑/白透明度在两种外观下均满足正文对比需求；三级文本 .35 只用于非关键辅助信息。
- 全部交互控件带 `.help` 提示；键盘：⌘1–⌘3 切页、⌘K 聚焦搜索、⌘R 重新扫描、⌘N 安装、⌥⌘K 菜单栏搜索、↑/↓ 列表移动。

---

## ⑩ v1.2.2 产品规划（2026-08-14 定稿；与上文冲突以本章为准）

Reading this as: native macOS 14+ 技能管理器, 受众是装了一堆 Claude/Codex/Grok skills 的人, 语言是 Apple HIG / Tahoe Liquid Glass, 系统是 SwiftUI 官方控件。

Dials: VARIANCE 3（系统外壳可预测）/ MOTION 4 / DENSITY 7（管理器要密）。

定位：**替代 CC Switch 的技能管理**，不是仪表盘。CC Switch 仍是 All-in-One；本应用只接管 Skills。禁止写入 `~/.cc-switch/cc-switch.db` 与 `~/.cc-switch/skills/`。

### 10.1 功能地图

必须有：

1. **首次启动扫描 + 迁移弹窗**
   - 扫描：`~/.skill-atlas/skills`、`~/.cc-switch/skills`、`~/.claude/skills`（resolve 软链，本机可能是 `.mirasim/skills`）、`~/.codex/skills`、`~/.grok/skills`，以及 `~/.<gemini|opencode|hermes>/skills` 若存在。按 `resolvingSymlinksInPath` 去重。
   - 发现 CC Switch 源且尚未迁完 → **窗口模态 sheet**（不能点空白关掉；不能只靠角落入口）。列出数量、目标 `~/.skill-atlas/skills/`（APFS `cp -c` clonefile）、按 DB 启用位重建 Claude/Codex/GrokBuild 软链、写 `~/.skill-atlas/migration.json`。可点「跳过」。菜单与设置页「撤销迁移」。
   - 库内已有对应目录则跳过克隆，只补链；磁盘已迁完（有回滚清单且 CC 目录都在库内）则**不弹**，并同步 `migratedFromCCSwitch`。未迁的本地直装仍收入。
2. **安装**：GitHub URL 或本地文件夹。目标 `~/.skill-atlas/skills/`，再按勾选平台建软链。
3. **卸载**：确认后移走软链；可选把库内目录移入废纸篓（系统废纸篓即备份）。CC Switch 原目录永不删。未迁移的 CC Switch 技能不可卸。
4. **更新**：侧栏一级「更新」，角标 = 可更新数，页内醒目「全部更新」。有 repo 的 `git fetch` 对比 origin/branch，一键 `git pull --ff-only`，失败不强制。不许只藏在详情页。
5. **平台同步第一层**：列表每一行内 logo 点亮/置灰，**单击切换挂载**。详情头部同样是 logo 开关，不是文字 chip，不是折叠深处。
6. **平台真 logo**：见 10.4。筛选、统计、开关同一套。
7. **已有能力接入新壳**：使用统计、触发词重叠、长期未用、SKILL.md 阅读器、菜单栏 ⌥⌘K、应用自更新。不要丢。

独占 / 提效：

8. **上下文预算体检**（别人没做）：估算技能 description 列表是否会撑爆 Claude Code ~1% listing budget（约 40 个 × 260 字开始截断；最少用的 description 会被丢，技能静默失踪）。健康页预算带：按使用频率标哪些该停用 / 缩短描述 / 设 disable-model-invocation。
9. **描述过长警告**：>1 句或超 200 字，给出一条可复制的缩短建议（取首句，截到约 80 字）。不做空功能。

### 10.2 入口层级表

硬约束：复制调用语、开关平台、更新、卸载，从主界面 ≤2 次点击。

| 功能 | 一级 | 二级 | 右键 | 点击数 |
|---|---|---|---|---|
| 复制调用语 | 列表行悬停复制钮；菜单栏 ⌥⌘K 回车 | 详情头「复制调用语」 | ✓ | 1 |
| 看挂载 | 列表行 logo（0 次，始终可见） | 详情头 logo 行 | — | 0 |
| 开关平台 | **列表行单击 logo** | 详情头单击 logo | ✓ 平台子菜单 | **1** |
| 更新单个 | 侧栏更新 → 行内「更新」 | 详情管理区 | ✓ | 2 |
| 全部更新 | 侧栏更新 →「全部更新」 | — | — | 2 |
| 卸载 | 右键 → 卸载（确认） | 详情「卸载」 | ✓ | 2 |
| 安装 | 工具栏 + / ⌘N | 空态主按钮 | — | 1 |
| 停用/恢复 | 详情管理区 | 健康页长期未用行内 | ✓ | 2 |
| 迁移 | 首次启动模态 | 设置页 / 菜单「从 CC Switch 迁入」 | — | 0（自动） |
| 撤销迁移 | 设置页 / 菜单 | — | — | 2 |
| 预算体检 | 侧栏「健康」 | — | — | 1 |
| 扫描路径 | 侧栏「设置」 | — | — | 1 |
| 检查应用更新 | 设置页 | 菜单「检查更新…」 | — | 2 |
| 阅读 SKILL.md | 详情「查看完整说明」 | 右键 | ✓ | 2 |

### 10.3 每页区块排版（文字草图）

窗口：系统标题栏 + 统一工具栏。交通灯与工具栏垂直对齐。禁止自定义 76pt 窄轨叠红绿灯。禁止网页式四宫格仪表盘、重复分类网格、孤立粗体页标题。

```
┌─ ● ● ●  Skill Atlas ──── 🔍 搜索技能、用途或任务 ── [+] 安装  [↻] ─┐
│ 技能库     │  全部 | 收藏     类别▾  [C][O][G][Grok]  排序▾        │
│ 更新  (3)  │  ──────────────────────────────────────────────────  │
│ 健康  (1)  │  📄  hotspot     基金短视频…     [C][O][G]            │
│ 设置       │  📄  pptx        处理演示稿…     [C][ ][G]            │ 详情
│            │  📄  browser-use 打开网页…       [C][O][ ]            │ 头: logo开关
│ CC Switch  │                                                     │ 复制调用语
│ 只读       │                                                     │ 用途 / 管理
└────────────┴─────────────────────────────────────────────────────┘
```

**技能库（默认首页）**

```
[全部技能 | 我的收藏 n]     类别▾   平台 logo 筛选   健康▾   来源▾   排序▾   清除
────────────────────────────────────────────────────────────────────────
图标  名称                         简介（一行）          [C][O][G][…]  状态
      directory / 用途截断                               单击切换挂载
────────────────────────────────────────────────────────────────────────
右侧 inspector：
  大图标  名称                         [收藏]
          仓库
  [C] [O] [Gemini] [Grok] [OC] [He]     ← logo 开关，无文字 chip
                          [复制调用语]
  用途
  什么时候调用
  示例说法
  使用情况（会话 / 最近 / 平台）
  上下文成本（token 估算 + 过长则缩短建议）
  安装位置  [查看完整说明] [打开目录]
  管理：[停用] [卸载…]  （有更新时才出现更新钮；更新主入口在「更新」页）
```

**更新**

```
3 个技能可更新     对照上游 git，快进合并。     检查于 12:04   [检查更新]  [全部更新]
────────────────────────────────────────────────────────────────────────
图标  名称 / owner/repo     [C][O][G]     [更新]
…
▸ 已是最新 (n)
▸ 没有上游仓库 (n)
```

**健康**

```
技能清单的上下文预算          [200k | 1M]
████████████░░░░  ~token / 预算     超则说明最少用的描述会被丢
上架技能 145     描述丢弃风险 n     可回收 token n     约 40×260 字开始截断
────────────────────────────────────────────────────────────────────────
描述丢弃风险（按使用频率从低到高） │ 长期未用（行内停用）
描述过长（>1 句或 >200 字 + 缩短建议）│
需要修复（挂载/文件）              │ 触发词重叠
脚注：估算；不写 CC Switch。
```

**设置**

```
扫描路径（只读列表，resolve 后的真实路径）     [重新扫描]
从 CC Switch 迁移
  状态：未迁 / 已迁 n 个 / 已跳过
  将迁到 ~/.skill-atlas/skills/
  [迁入…] [撤销迁移]
  说明：不写 CC Switch 数据库与原目录。
应用
  版本 1.2.2     [检查更新…]
```

**首次启动迁移弹窗（模态，不可点窗外关掉）**

```
把技能收到一起
把 CC Switch 里的 N 个技能收到本应用统一管理，原文件保留，随时可撤销。
              [跳过]              [开始迁移]
```

不写 clonefile、json 路径、三层 HOME。目录布局对标 CC Switch，全部在 `~/.skill-atlas/`：`atlas.json`、`skills/`、`skill-backups/`（最近 20 个）、`migration.json`。

### 10.4 平台真 logo（v7 彩色芯片版，2026-08-14）

嵌入 `native/Resources/logos/`（LobeHub Icons，MIT，github.com/lobehub/lobe-icons）。**UI 只展示四个平台：Claude Code / Codex / Gemini / Grok**；OpenCode、Hermes 仅保留数据兼容（已有软链不动），不再出现在任何界面。

| 平台 | 资源 | 渲染 |
|---|---|---|
| Claude Code | `claude-color.svg` | 原色（品牌橙 #D97757） |
| Codex | `openai.svg` | 模板渲染，黑标随明暗反色 |
| Gemini | `googlegemini.svg` | 模板 + SwiftUI 渐变上色（#4285F4→#9B72CB→#D96570；NSImage 渲染不了 SVG 渐变 defs，`gemini-color.svg` 留档不用） |
| Grok | `xai.svg` | xAI 官方 X 标，模板渲染随明暗反色 |

**芯片样式（`PlatformLogo`）**：连续圆角方块（radius = 尺寸 30%）。点亮 = 品牌色淡底（亮 12% / 暗 20%）+ 品牌色发丝 + 原色 glyph；置灰 = 中性 4% 底 + 去饱和 glyph（模板 55% / 彩标 40% 透明度）。尺寸：列表行 18 / 筛选条 22 / 详情头 26。`label` 仍是 skills.platforms 的存储键（Claude/Codex/GrokBuild…），界面文案一律用 `displayName`。

状态：点亮 = 主文本 85%；置灰 = 三级文本。尺寸：列表 14pt，详情 18pt。筛选条、列表、详情、更新行共用 `PlatformLogo`。

### 10.5 上下文预算算法口径

- 单技能上架成本 = min(描述字符数, 1536)；token 估算 = CJK×0.7 + 其他/4 + 15（条目开销）
- 预算 = 窗口 token × 1%（200k → 2,000；1M → 10,000），档位用户可切
- 经验阈值：约 40 个技能 × 260 字开始截断；健康带展示「n 个上架 / 约 40 个开始截断」
- 丢弃模拟：按使用频率降序保留，累计超预算的（最少用的）标「描述有被丢弃风险」
- 可回收 = 长期未用技能的上架成本合计
- 描述 >1536 字符 → 「会被截断」
- 描述 >1 句或 >200 字 → 「建议缩短」+ 首句缩短建议（可复制）
- 全部标注「估算」

### 10.6 外壳（v1.2.2：回到玻璃轨）

v3 曾换成 `NavigationSplitView` + 系统 sidebar + 斑马纹 List，观感变成「系统设置」，已撤销。

- 窗口 `hiddenTitleBar`；空 `NSToolbar` + `unifiedCompact`；交通灯光学中线 22pt，左侧 84–100pt 留白，不与 76pt 玻璃侧栏重叠。
- L0：桌面模糊 + FluidGradient + 白纱。L2 玻璃只给 chrome（侧栏 rail、搜索胶囊、刷新/安装圆钮）。内容全部 L1 `ContentSurface`。
- 侧栏 76pt 图标轨：技能库 / 更新 / 体检 / 怎么用 / 设置；选中胶囊 `matchedGeometryEffect`。
- 44pt 工具条：身份簇 → Spacer → 搜索胶囊（仅技能库）→ + → 刷新 → 时间戳。
- 列表：`ScrollView` + `LazyVStack` + `panelScroll`（`.scrollIndicators(.never)`）。禁止 inset List 斑马纹。
- 「怎么用」页用库里的真实技能教调用，不是静态原则文案。不做 MCP 管理。
- 目录对标 CC Switch：全部在 `~/.skill-atlas/`，不再把元数据拆到 Application Support。

### 10.7 怎么用页的目的

CC Switch 只做开关。本页让不懂 Skill / MCP / Agent 的人真正用起来：三个词配库里的真实例子、可复制的调用语、当前技能卡片、用自己的使用数字接到体检页。

## 附：验收样张与调试参数

- `docs/screenshot-library.png` / `screenshot-updates.png` / `screenshot-doctor.png` / `screenshot-guide.png`（1380×860 亮色）
- `docs/screenshot-migrate.png`（迁移弹窗）、`screenshot-dark.png`（暗色）
- 调试参数：`-atlasPage library|updates|doctor|guide|settings`、`-atlasAppearance dark|light`、`-atlasWindow 1380x860`、`-atlasHome /path`、`-atlasSelect <技能名>`、`-atlasForceMigrate`、`-atlasMigrate` / `-atlasRollback`

### 应用图标（iconset 生成规则，v2）

- 母版由 `native/tools/render-icon.swift` 程序化生成（`preview` 出变体对比、`iconset` 打整套图）：1024 画布上内容板 **824×824 居中**（80.46%，Apple Big Sur+ 图标网格），圆角 22.4%，四周透明边距留给系统投影，**不烙印外部阴影**（保证不透明包围盒可客观验证：实测恰为 824×824）。
- 背景板多层光照：顶部天蓝→底部深蓝主渐变（#0A84FF 家族）+ 顶部中央柔和径向高光（模拟光源）+ 底缘 vignette 轻微加深 + 顶部内侧极细 specular 亮边（描边路径剪裁渐隐）。
- glyph 为三片玻璃卡片 Wallet 式堆叠（选型 A「后片收窄递进」，对比图 `docs/icon-variants.png`）：前片不透明白在下（宽 54% 板宽），后两片从上方探出、逐层缩小（0.92/0.84）且透明度递减（60%/30%），片间 black 11% 小 blur 投影制造景深；前片叠极淡白→冷白渐变避免死白，顶边细高光；整体光学居中上移 2.5%。所有形状 CoreGraphics 精确路径。
- Dock 有图标缓存：更新后 `touch "Skill Atlas.app" && killall Dock` 刷新。
