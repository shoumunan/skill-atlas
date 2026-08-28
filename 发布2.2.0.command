#!/bin/zsh
# Skill Atlas 2.2.0 发版：构建 → 校验版本 → DMG。
# 推送、打 tag、上传 Release、写 appcast 由本脚本末尾提示的命令手动执行（外发动作要人确认）。
set -euo pipefail
APP_DIR="${0:A:h}"
cd "$APP_DIR"

VERSION="2.2.0"
TAG="v$VERSION"

echo "== 构建 =="
"$APP_DIR/构建原生应用.command"

BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_DIR/Skill Atlas.app/Contents/Info.plist")
if [[ "$BUILT" != "$VERSION" ]]; then
  echo "构建出来的版本是 $BUILT，期望 $VERSION" >&2
  exit 1
fi
"$APP_DIR/Skill Atlas.app/Contents/MacOS/atlas" --version
# 手册必须随包（应用内帮助读它）
[[ -f "$APP_DIR/Skill Atlas.app/Contents/Resources/handbook.md" ]] || { echo "handbook.md 未打进包" >&2; exit 1; }

echo "== 验收 =="
zsh "$APP_DIR/tests/acceptance.sh"

echo "== 打包 DMG =="
"$APP_DIR/打包DMG.command"
DMG="$APP_DIR/dist/Skill Atlas-$VERSION.dmg"
ls -lh "$DMG"

cat <<TIP

== 本地产物就绪。以下是外发步骤（确认后手动执行）==
  git push -u origin v2.1-dev
  git checkout main && git merge --ff-only v2.1-dev && git push
  git tag $TAG && git push origin $TAG
  gh release create $TAG "\$DMG" --title "Skill Atlas $VERSION" --notes-file <(cat)
  # 取 Release 资产摘要后写回 appcast.json 的 sha256：
  gh release view $TAG --json assets --jq '.assets[] | select(.name|endswith(".dmg")) | .digest'
TIP
