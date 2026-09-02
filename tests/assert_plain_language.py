#!/usr/bin/env python3
"""界面文案不许出现旧黑话。

页面按用户的处境命名（技能库 / 添加技能 / 软件 / 更新 / 设置），界面上
不许再说「收件箱」「供给页」「发现页」「创作页」。i18n 闸只查翻译是否齐，
查不出这个。

只扫用户看得见的字符串（L("…") / LF("…") / title: "…" 这类），不扫注释：
注释里写「原供给页」是有用的历史说明，不该被误杀。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
APP = ROOT / "native" / "swift" / "app"

# 词 -> 现在该说什么
BANNED = {
    "收件箱": "更新",
    "供给页": "更新",
    "发现页": "添加技能",
    "创作页": "添加技能里的「自己做一个」",
}

# 用户可见字符串的取词口径，和 assert_i18n.py 保持一致
PATTERNS = [
    re.compile(r'\bLF?\(\s*"((?:[^"\\]|\\.)*)"'),
    re.compile(r'(?:title|subtitle|hint|note|label|text|caption|body|rule):\s*"((?:[^"\\]|\\.)*)"'),
]


def strip_comments(source: str) -> str:
    """去掉 // 行注释；字符串里出现 // 的情况这里不会碰到（我们只取双引号内容）。"""
    out = []
    for line in source.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("//"):
            continue
        out.append(line)
    return "\n".join(out)


def main() -> int:
    hits = []
    for path in sorted(APP.glob("*.swift")):
        source = strip_comments(path.read_text(encoding="utf-8"))
        for lineno, line in enumerate(source.splitlines(), 1):
            for pattern in PATTERNS:
                for text in pattern.findall(line):
                    for word, better in BANNED.items():
                        if word in text:
                            hits.append((path.name, lineno, word, better, text.strip()))

    if hits:
        print(f"界面文案里还有 {len(hits)} 处旧黑话：")
        for name, lineno, word, better, text in hits:
            print(f'  {name}:{lineno} 「{word}」→ 应该说「{better}」')
            print(f"      {text[:70]}")
        return 1

    print("文案闸：界面上没有旧黑话")
    return 0


if __name__ == "__main__":
    sys.exit(main())
