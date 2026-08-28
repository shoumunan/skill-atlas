#!/usr/bin/env python3
"""会改用户数据的调试探针，必须只认启动参数，不许读持久化 UserDefaults。

## 为什么

2.5 的一次截图会话里，App 在没有任何点击的情况下把 137 个技能写成了 off，
覆盖掉用户自己调了 60 条的 ~/.claude/settings.json。唯一能不经确认框就落盘的
路径是 `atlasProfileProbe` 那段——它 `UserDefaults.standard.string(forKey:)` 读，
而 UserDefaults 是**持久化**的：任何进程一句 `defaults write` 写进去，就会在
**下一次启动**静默触发，与写它的人早已失去时间上的关联。

启动参数（`LaunchArgs`，只读 CommandLine.arguments）没有这个问题：一次性、显式、
跟着那一次启动走。

这道闸静态检查源码，不需要跑起来——跑起来才发现，用户的配置已经被改了。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "native" / "swift" / "app"

# 这些探针会改用户的文件（写 settings.json、迁移、卸载、装技能、装 hook、回滚…）
MUTATING = {
    "atlasProfileProbe", "atlasProfileName", "atlasProfileMembers", "atlasProfileDir",
    "atlasApplyUpdateProbe", "atlasUninstallProbe", "atlasHookProbe", "atlasSandboxProbe",
    "atlasRollbackProbe", "atlasAction",
    "atlasInstallURL", "atlasInstallGo", "atlasInstallCodex",
    "atlasMigrate", "atlasRollback", "atlasShowMigrate",
}

PATTERN = re.compile(
    r'UserDefaults\.standard\.(?:string|bool|object|integer)\(forKey:\s*"(atlas\w+)"\)'
)


def main() -> int:
    hits = []
    for path in sorted(APP.glob("*.swift")):
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for key in PATTERN.findall(line):
                if key in MUTATING:
                    hits.append((path.name, lineno, key))

    if hits:
        print(f"{len(hits)} 处会改用户数据的探针在读持久化 UserDefaults：")
        for name, lineno, key in hits:
            print(f'  {name}:{lineno} 「{key}」→ 换成 LaunchArgs.value/flag("{key}")')
        print()
        print("持久化的键会在下一次启动静默触发，与设置它的动作失去时间关联。")
        return 1

    print(f"探针闸：{len(MUTATING)} 个会改数据的探针都只认启动参数")
    return 0


if __name__ == "__main__":
    sys.exit(main())
