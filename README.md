# Skill Atlas · 技能图谱

本地 macOS 应用，把 Claude / Cursor / Codex / Gemini / Grok / WorkBuddy 的 skills 收到一个库：扫描、安装、更新、跨平台挂载。

数据在 `~/.skill-atlas/`。CC Switch 只读迁入，不改它的文件。

## 功能

- **技能库**：搜索、平台开关、复制调用语、打开软件
- **装前安全扫描**：`curl | sh`、隐藏 Unicode、硬编码密钥
- **更新先看 diff**：不静默覆盖，能回滚
- **收编**：把散落在 `~/.claude/skills` 等目录里的技能收进本库
- **维护**（设置里，默认折叠）：挂载失败、安全命中、闲置、触发词重叠
- **应用内更新**

## 下载

从 [Releases](https://github.com/shoumunan/skill-atlas/releases) 下载最新 DMG。要求 macOS 14+、Apple 芯片；未做 Apple 公证，首次打开需右键 →「打开」绕过 Gatekeeper。

## 从源码构建

```
./构建原生应用.command
```

产出 `Skill Atlas.app`（纯 Swift + SwiftUI）。参与开发见 [CONTRIBUTING.md](CONTRIBUTING.md)，视觉设计规范见 [DESIGN.md](DESIGN.md)。
