# Skill Atlas 3.0.0 验收报告

日期：2026-08-14。应用目录：`/Users/shoumunan/Documents/Codex/2026-08-13/wo/outputs/skill-atlas/`。未做 git commit。

## 1. 外壳：玻璃轨回来了

v3 原型把窗口换成了系统 `NavigationSplitView` + sidebar List + 斑马纹 inset List（「系统设置」外观）。3.0.0 恢复手工 L0/L1/L2 壳，v3 功能嵌在里面：

- L0：桌面模糊 + FluidGradient + 白纱；`hiddenTitleBar`；交通灯光学中线 22pt，左侧约 100pt 留白，不与 76pt 玻璃侧栏重叠
- 76pt 玻璃 rail：图标 + caption，选中胶囊 `matchedGeometryEffect`
- 44pt 工具条：交通灯留白 → 页标题 → Spacer → 搜索胶囊（仅技能库）→ + → 刷新 → 时间戳
- 内容全部 L1 `ContentSurface`；列表 `ScrollView` + `LazyVStack` + `panelScroll`（`.scrollIndicators(.never)`），无斑马纹 List
- 玻璃只给 chrome（侧栏、搜索胶囊、安装/刷新圆钮）

侧栏五级：技能库（默认）/ 更新（角标=可更新数）/ 体检 / 怎么用 / 设置。独立总览页已删除。

## 2. 目录：对标 CC Switch，一个文件夹

```
~/.skill-atlas/
  atlas.json
  skills/
  skill-backups/    # 卸载前备份，最近 20 个
  migration.json
```

实测：`atlas.json` 在 `~/.skill-atlas/`。Application Support 不再作为主存储（旧 `atlas.json` 已不在）。

抽查：`~/.claude/skills/hotspot` 与 `~/.mirasim/skills/hotspot` 均指向 `/Users/shoumunan/.skill-atlas/skills/hotspot`。`~/.cc-switch/skills/hotspot` 仍在，未删、未写 CC Switch DB。

日常只认本库；未迁完才扫 CC Switch / 平台目录发现散落技能并弹迁移窗。迁移文案：「把 CC Switch 里的 N 个技能收到本应用统一管理，原文件保留，随时可撤销。」

## 3. 「怎么用」页

四块 L1 面板：30 秒三个词（Skill / Agent / MCP，配库里 hotspot 等真实例子）、可复制调用语、当前选中技能卡片（复制 + ⌥⌘K）、用 N/M 与约 40 个描述预算接到体检页。不管 MCP。

## 4. 功能层级

- 列表行内平台 logo 单击切换挂载
- 更新：侧栏一级 + 页内「全部更新」
- 卸载：右键 + 详情
- 安装：⌘N / 工具条 +
- 复制调用语：行内悬停 + 详情主按钮
- 首次启动：有未迁移的 CC Switch 技能就弹窗

## 5. 打包 3.0.0

| 文件 | 大小 |
|------|------|
| `dist/Skill Atlas-3.0.0.dmg` | **2.3M**（2,419,266 字节），2026-08-14 01:52 |
| 应用版本 | CFBundleShortVersionString **3.0.0** |

卷内：`Skill Atlas.app`、`Applications` 软链、`安装说明.txt`（`~/.skill-atlas/`、首次可迁、不改 CC Switch、⌥⌘K、五级侧栏、右键绕过 Gatekeeper）。

## 6. 截图（docs/）

- `screenshot-library.png` — 技能库全窗：玻璃侧栏 + L1 双栏，非系统设置风
- `screenshot-updates.png` — 更新（页内「全部更新」/折叠段）
- `screenshot-doctor.png` — 体检（预算 + 重叠 + 长期未用）
- `screenshot-guide.png` — 怎么用（四块 L1）
- `screenshot-migrate.png` — 迁移弹窗短文案
- `screenshot-dark.png` — 暗色技能库

## 7. 对照上一版精致感自检

| 项 | 结果 |
|----|------|
| 交通灯不与侧栏重叠 | 通过（hiddenTitleBar + 100pt 工具条留白 + alignTrafficLights 22pt） |
| 镜面顶边 | 通过（GlassChrome 1pt 顶缘高光） |
| 无斑马纹 List | 通过（ScrollView + LazyVStack + panelScroll） |
| 无系统 sidebar | 通过（76pt 手工 rail，非 NavigationSplitView） |
