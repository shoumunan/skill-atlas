#!/bin/zsh
set -e
APP_DIR="${0:A:h}"
APP_BUNDLE="$APP_DIR/Skill Atlas.app"
BIN="$APP_BUNDLE/Contents/MacOS/SkillAtlas"
CLI="$APP_BUNDLE/Contents/MacOS/atlas"

mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
if [[ -d "$APP_DIR/native/SkillAtlas.iconset" ]]; then
  # 新版 macOS 会拒绝部分由 Pillow 生成但实际可读的 iconset。
  # 仓库里已有验证过的 ICNS，重建时不应因图标重生成失败而中断。
  iconutil -c icns "$APP_DIR/native/SkillAtlas.iconset" -o "$APP_DIR/native/SkillAtlas.icns" || \
    echo "图标集重生成未通过，继续使用仓库内的 SkillAtlas.icns"
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

SWIFTC_COMMON=(
  -O -parse-as-library
  -swift-version 5
  -target arm64-apple-macos14.0
  -package-name SkillAtlas
)

compile_app_swiftc() {
  CLANG_MODULE_CACHE_PATH="/tmp/skill-atlas-clang-cache" xcrun swiftc "${SWIFTC_COMMON[@]}" \
    "$APP_DIR"/native/swift/core/*.swift \
    "$APP_DIR"/native/swift/app/*.swift \
    "$APP_DIR"/native/vendor/FluidGradient/Sources/FluidGradient/*.swift \
    -o "$BIN"
}

compile_cli_swiftc() {
  CLANG_MODULE_CACHE_PATH="/tmp/skill-atlas-clang-cache" xcrun swiftc "${SWIFTC_COMMON[@]}" \
    "$APP_DIR"/native/swift/core/*.swift \
    "$APP_DIR"/native/swift/cli/*.swift \
    "$APP_DIR"/native/swift/cli/Commands/*.swift \
    -o "$CLI"
}

# 首选 SwiftPM（需要完整 Xcode；首次构建需联网拉取 FluidGradient）。
# 本机若仅装 Command Line Tools，SwiftPM 无法启动（PlatformPath 报错），
# 自动回退为 swiftc + native/vendor/FluidGradient 源码合并编译，产物一致。
#
# -swift-version 5：和 Package.swift 的 swift-tools-version:5.9 对齐。
# 不锁版本时，部分 CI 镜像的 swiftc 默认按 Swift 6 语义做 actor 隔离检查，
# SwiftPM 路径里只是警告的 MainActor 越界访问在这里会变成硬错误。
cd "$APP_DIR/native"
if swift build -c release --product SkillAtlas && swift build -c release --product atlas; then
  echo "构建方式：SwiftPM"
  cp "$APP_DIR/native/.build/release/SkillAtlas" "$BIN"
  cp "$APP_DIR/native/.build/release/atlas" "$CLI"
else
  echo "构建方式：swiftc + vendor（SwiftPM 在纯 CLT 环境不可用）"
  compile_app_swiftc
  compile_cli_swiftc
fi
chmod +x "$BIN" "$CLI"
codesign --force --deep --sign - "$APP_BUNDLE" >/dev/null
echo "已生成：$APP_BUNDLE"
echo "CLI：$CLI"
"$CLI" --version
