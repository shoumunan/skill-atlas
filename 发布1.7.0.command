#!/bin/zsh
# Skill Atlas 1.7.0 一键发版：构建 → DMG → 提交 → 推送 → GitHub Release → appcast。
set -euo pipefail
APP_DIR="${0:A:h}"
cd "$APP_DIR"

VERSION="1.7.0"
TAG="v$VERSION"
NOTES='侧栏收成「我的技能 / 设置」。检查和怎么用不再单独占一页；挡住使用的问题写在技能详情，整理建议收进设置里的维护。

系统要求：macOS 14+，Apple 芯片。未公证，首次打开请右键 → 打开。'

echo "== 删除已退役空壳 =="
rm -f native/swift/DoctorView.swift native/swift/GuideView.swift native/swift/GuideConceptMap.swift

echo "== 构建 =="
"$APP_DIR/构建原生应用.command"

BUILT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_DIR/Skill Atlas.app/Contents/Info.plist")
if [[ "$BUILT" != "$VERSION" ]]; then
  echo "构建出来的版本是 $BUILT，期望 $VERSION" >&2
  exit 1
fi

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
    "notes": "v$VERSION：侧栏收成「我的技能 / 设置」。检查和怎么用不再单独占一页；挡住使用的问题写在技能详情，整理建议收进设置里的维护。",
    "download": "https://github.com/shoumunan/skill-atlas/releases/latest",
    "dmg": "https://github.com/shoumunan/skill-atlas/releases/download/$TAG/$ASSET",
    "sha256": "$1",
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print("appcast sha256 = $1")
PY
}

echo "== git 提交源码 =="
git add -u
git add native/swift native/resources native/Info.plist DESIGN.md README.md docs appcast.json 打包DMG.command
git status --short
git commit -m "$(cat <<'EOF'
Release 1.7.0: collapse sidebar to My Skills and Settings.

Check and How-to are no longer top-level pages. Blocking issues
show on the skill inspector; maintenance lives under Settings.
EOF
)" || true

echo "== 推送 main =="
git push origin HEAD

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "本地已有 $TAG，不覆盖"
else
  git tag "$TAG"
fi
git push origin "$TAG" || true

echo "== GitHub Release =="
if gh release view "$TAG" >/dev/null 2>&1; then
  echo "Release $TAG 已存在，补传 DMG（若尚未上传）"
  gh release upload "$TAG" "$DMG" --clobber
else
  gh release create "$TAG" "$DMG" --title "Skill Atlas $VERSION" --notes "$NOTES"
fi

DIGEST=$(gh release view "$TAG" --json assets --jq '.assets[] | select(.name|endswith(".dmg")) | .digest' | sed 's/^sha256://')
if [[ -z "$DIGEST" ]]; then
  echo "拿不到 GitHub digest，中止写 appcast" >&2
  exit 1
fi
write_appcast "$DIGEST"
git add appcast.json
git commit -m "Point appcast at the GitHub Release asset digest." || true
git push origin HEAD

echo "== 完成 =="
gh release view "$TAG"
echo "sha256 $DIGEST"
echo "检查更新源：https://raw.githubusercontent.com/shoumunan/skill-atlas/main/appcast.json"
