#!/bin/zsh
# 打开本仓库里的 Skill Atlas.app。web 面板已删除。
set -e
APP_DIR="${0:A:h}"
if [ -d "$APP_DIR/Skill Atlas.app" ]; then
  open "$APP_DIR/Skill Atlas.app"
elif [ -d "/Applications/Skill Atlas.app" ]; then
  open "/Applications/Skill Atlas.app"
else
  echo "找不到 Skill Atlas.app。先跑 ./构建原生应用.command" >&2
  exit 1
fi
