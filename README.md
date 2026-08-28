# Skill Atlas · 技能图谱

本地 macOS 应用：**技能的供给与运维层**。agent 在会话里用 `atlas` CLI 搜、装、诊断、沉淀技能；你每周开一次面板清收件箱、调供给。装什么都过本地安全扫描。

数据在 `~/.skill-atlas/`。CC Switch 只读迁入，不改它的文件。

## 五个名词

- **技能库**：库存、每技能的挂载与档位、使用统计、上下文成本
- **发现**：聚合搜市场（skills.sh 全球 + SkillHub 国服）、官方精选、GitHub 链接与本地导入、SkillHub zip 直装（安全解包）
- **供给**：哪个 AI、哪个项目带哪些技能进场；场景包、三档档位、瘦身草案、上下文账单
- **收件箱**：待审批、安全命中、挂载失败、miss、可更新排队裁决，清零有回执
- **创作**：建骨架 → 沙箱试跑 → 触发验证 → 命中回访，四步把流程沉淀成技能

怎么用：[使用手册](docs/handbook.md)（四条工作流，每条带完成证据）。agent 不用读——元技能 `skill-atlas` 已挂到所有平台。

## 下载

从 [GitHub Releases](https://github.com/shoumunan/skill-atlas/releases/latest) 获取最新 DMG。要求 macOS 14+、Apple 芯片；未做 Apple 公证，首次打开需右键 →「打开」绕过 Gatekeeper。

## 从源码构建

```
./构建原生应用.command
```

产出 `Skill Atlas.app`（纯 Swift + SwiftUI），CLI 在 `Contents/MacOS/atlas`。参与开发见 [CONTRIBUTING.md](CONTRIBUTING.md)，视觉与交互规范见 [DESIGN.md](DESIGN.md)（v15 章），施工以 [PLAN.md](PLAN.md)（2.1）为准，验收跑 `tests/acceptance.sh`。
