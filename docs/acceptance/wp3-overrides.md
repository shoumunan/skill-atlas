# WP3 第 0 项：skillOverrides 有效性探针

日期：2026-08-26  
Claude Code：2.1.235（`/Users/shoumunan/.local/bin/claude`）

## 方法

隔离 `CLAUDE_CONFIG_DIR`，两个假技能 `alpha-ov` / `beta-ov`，`settings.json`：

```json
{
  "hasCompletedOnboarding": true,
  "disableBundledSkills": true,
  "skillOverrides": { "beta-ov": "off" }
}
```

分别 `claude --print` 问「能不能自动调用 alpha-ov / beta-ov」。

## 结论

**成立。** `alpha-ov` → `HAS_ALPHA`；`beta-ov` → `NO_BETA`。

因此 2.0 供给三档走 `skillOverrides` 主路线（`"user-invocable-only"` / `"off"`），不启用 ADR-7 的 frontmatter 兜底。

诚实边界：只对 Claude Code 生效。Codex 等平台的供给仍靠软链集合，二期调研。
