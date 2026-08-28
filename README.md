# Skill Atlas · 技能图谱

本地 macOS 应用：**帮你把技能管好，然后别烦你**。技能装了就能用；真出问题时到「检查」页看一眼。会话里的 agent 用 `atlas` 命令自己搜、装、诊断。装什么都先过一遍本地安全扫描。

数据在 `~/.skill-atlas/`。CC Switch 只读迁入，不改它的文件。

## 四个页面

- **技能库**：我有哪些技能。每行显示装在哪些软件里、用过多少次、占多少篇幅
- **添加技能**：装现成的（搜市场 / GitHub 链接 / 本地文件夹 / 收编散落的），或自己做一个
- **检查**：有什么要你处理。顶部一张卡说清「技能简介占多长、能不能少点」，下面只放四类真待办：等你确认 / 可能不安全 / 装了用不了 / 叫不动
- 设置：软件目录、通知、发现来源、进阶

怎么用：[使用手册](docs/handbook.md)（四条日常，每条带成功标志）。agent 不用读——元技能 `skill-atlas` 已挂到所有平台。

## 下载

从 [GitHub Releases](https://github.com/shoumunan/skill-atlas/releases/latest) 获取最新 DMG。要求 macOS 14+、Apple 芯片；未做 Apple 公证，首次打开需右键 →「打开」绕过 Gatekeeper。

## 从源码构建

```
./构建原生应用.command
```

产出 `Skill Atlas.app`（纯 Swift + SwiftUI），CLI 在 `Contents/MacOS/atlas`。参与开发见 [CONTRIBUTING.md](CONTRIBUTING.md)，视觉与交互规范见 [DESIGN.md](DESIGN.md)（v15 章），施工以 [PLAN.md](PLAN.md)（2.1）为准，验收跑 `tests/acceptance.sh`。
