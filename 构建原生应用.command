#!/bin/zsh
set -e
APP_DIR="${0:A:h}"
APP_BUNDLE="$APP_DIR/Skill Atlas.app"
BIN="$APP_BUNDLE/Contents/MacOS/SkillAtlas"

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
if [[ -d "$APP_DIR/native/SkillAtlas.iconset" ]]; then
  iconutil -c icns "$APP_DIR/native/SkillAtlas.iconset" -o "$APP_DIR/native/SkillAtlas.icns"
fi
cp "$APP_DIR/native/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_DIR/native/SkillAtlas.icns" "$APP_BUNDLE/Contents/Resources/SkillAtlas.icns"
rm -rf "$APP_BUNDLE/Contents/Resources/logos"
mkdir -p "$APP_BUNDLE/Contents/Resources/logos"
cp "$APP_DIR"/native/Resources/logos/*.svg "$APP_BUNDLE/Contents/Resources/logos/"
# 栅格版品牌标（WorkBuddy 等 CoreSVG 渲染不了的 SVG 用 PNG 替身）
cp "$APP_DIR"/native/Resources/logos/*.png "$APP_BUNDLE/Contents/Resources/logos/" 2>/dev/null || true
# 多语言资源（en/ja/ko；中文是开发语言无需 lproj）
rm -rf "$APP_BUNDLE/Contents/Resources/"{en,ja,ko}.lproj
for lang in en ja ko; do
  if [ -d "$APP_DIR/native/resources/$lang.lproj" ]; then
    cp -R "$APP_DIR/native/resources/$lang.lproj" "$APP_BUNDLE/Contents/Resources/$lang.lproj"
  fi
done
# 纯原生版不再内嵌网页与 Python 服务
rm -rf "$APP_BUNDLE/Contents/Resources/dashboard"

# 首选 SwiftPM（需要完整 Xcode；首次构建需联网拉取 FluidGradient）。
# 本机若仅装 Command Line Tools，SwiftPM 无法启动（PlatformPath 报错），
# 自动回退为 swiftc + native/vendor/FluidGradient 源码合并编译，产物一致。
cd "$APP_DIR/native"
if swift build -c release 2>/dev/null; then
  echo "构建方式：SwiftPM"
  cp "$APP_DIR/native/.build/release/SkillAtlas" "$BIN"
else
  echo "构建方式：swiftc + vendor（SwiftPM 在纯 CLT 环境不可用）"
  CLANG_MODULE_CACHE_PATH="/tmp/skill-atlas-clang-cache" xcrun swiftc -O -parse-as-library \
    -target arm64-apple-macos14.0 \
    "$APP_DIR"/native/swift/*.swift \
    "$APP_DIR"/native/vendor/FluidGradient/Sources/FluidGradient/*.swift \
    -o "$BIN"
fi
chmod +x "$BIN"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
echo "已生成：$APP_BUNDLE"
