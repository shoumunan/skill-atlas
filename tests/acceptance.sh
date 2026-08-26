#!/bin/zsh
# Skill Atlas 验收入口。每个 WP 往这里加段，输出与金样比对（jq 归一化）。
# WP0：atlas --version/--help 能跑，未知命令退出 2。完整命令面（list/enable/…）
# 是 WP1 的事——这里不写 WP1 的验收段，避免验收脚本跑在 WP1 代码前面。
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

find_atlas() {
  local candidates=(
    "Skill Atlas.app/Contents/MacOS/atlas"
    "native/.build/release/atlas"
    "native/.build/debug/atlas"
  )
  local path
  for path in "${candidates[@]}"; do
    if [[ -x "$ROOT/$path" ]]; then
      print -- "$ROOT/$path"
      return 0
    fi
  done
  return 1
}

ATLAS=$(find_atlas) || {
  echo "找不到 atlas 二进制。先 swift build -c release --product atlas，或跑 ./构建原生应用.command" >&2
  exit 1
}
echo "using: $ATLAS"

VERSION_OUT=$("$ATLAS" --version)
echo "version: $VERSION_OUT"
[[ "$VERSION_OUT" == atlas* ]] || {
  echo "version 输出应以 atlas 开头，实际：$VERSION_OUT" >&2
  exit 1
}

HELP_RC=0
"$ATLAS" --help >/dev/null 2>&1 || HELP_RC=$?
[[ "$HELP_RC" == 0 ]] || {
  echo "--help 应退出 0，实际 $HELP_RC" >&2
  exit 1
}

UNKNOWN_RC=0
"$ATLAS" definitely-not-a-command >/dev/null 2>&1 || UNKNOWN_RC=$?
[[ "$UNKNOWN_RC" == 2 ]] || {
  echo "未知命令应退出 2，实际 $UNKNOWN_RC" >&2
  exit 1
}

echo "WP0 acceptance OK"
