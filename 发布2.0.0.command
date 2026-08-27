#!/bin/zsh
# Skill Atlas 2.0.0 发版：构建 → DMG → 合 main → 推送 → tag → GitHub Release → appcast。
set -euo pipefail
APP_DIR="${0:A:h}"
cd "$APP_DIR"

VERSION="2.0.0"
TAG="v$VERSION"
NOTES='2.0：agent 用 atlas CLI 搜、装、启停、诊断、账单、场景和沉淀。关键级安全命中要人在窗口批准。技能清单可以按使用次数瘦身。维护区会指出该触发却没触发的技能。

系统要求：macOS 14+，Apple 芯片。未公证，首次打开请右键 → 打开。'

echo "== 构建 =="
"$APP_DIR/构建原生应用.command"

BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_DIR/Skill Atlas.app/Contents/Info.plist")
if [[ "$BUILT" != "$VERSION" ]]; then
  echo "构建出来的版本是 $BUILT，期望 $VERSION" >&2
  exit 1
fi
"$APP_DIR/Skill Atlas.app/Contents/MacOS/atlas" --version

echo "== 打包 DMG =="
"$APP_DIR/打包DMG.command"
DMG="$APP_DIR/dist/Skill Atlas-$VERSION.dmg"
ASSET="Skill.Atlas-$VERSION.dmg"

write_appcast() {
  python3 - <<PY
import json
from pathlib import Path
p = Path("$APP_DIR/appcast.json")
p.write_text(json.dumps({
    "version": "$VERSION",
    "notes": "v$VERSION：agent 用 atlas CLI 搜、装、启停、诊断；关键级安装要人批准；技能清单可按使用次数瘦身。",
    "download": "https://github.com/shoumunan/skill-atlas/releases/latest",
    "dmg": "https://github.com/shoumunan/skill-atlas/releases/download/$TAG/$ASSET",
    "sha256": "$1",
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("appcast sha256 = $1")
PY
}

echo "== 完成构建与 DMG =="
ls -lh "$DMG"
echo "接下来由发版流程提交、推送、打 tag、上传 Release、写 appcast。"
