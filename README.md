# Skill Atlas · 技能图谱

本地 macOS 应用，统一管理你的 AI 技能（Claude Code / Codex / Gemini / Grok / WorkBuddy / OpenClaw 等平台的 skills）：扫描、安装、更新、跨平台挂载，不用再手动翻目录、拉软链。

**只管自己的库，不碰别的工具。** 数据都在 `~/.skill-atlas/`；如果你在用 CC Switch，它的数据库和目录不会被修改或删除，只读迁移一份进来即可。

## 功能

- **技能库**：搜索、分类、平台挂载开关、一键复制调用语
- **体检**：挂载异常、触发词冲突、描述被截断、长期未用、上下文预算——健康问题集中在一页看
- **装前安全扫描**：`curl | sh`、隐藏 Unicode、硬编码密钥这类风险装前拦截，已装技能也会定期复查
- **更新先看 diff**：没有静默更新，本地改过的内容不会被覆盖，随时能回滚
- **指南**：新手三步上手，讲清技能怎么被 Agent 用到，含实时试触发
- **技能收编**：把散落在 `~/.claude/skills` 等目录里的技能一键收进库里统一管理
- **应用内自动更新**

## 下载

从 [Releases](https://github.com/shoumunan/skill-atlas/releases) 下载最新 DMG。要求 macOS 14+、Apple 芯片；未做 Apple 公证，首次打开需右键 →「打开」绕过 Gatekeeper。

## 从源码构建

```
./构建原生应用.command
```

产出 `Skill Atlas.app`（纯 Swift + SwiftUI，不内嵌网页）。参与开发见 [CONTRIBUTING.md](CONTRIBUTING.md)，视觉设计规范见 [DESIGN.md](DESIGN.md)。
