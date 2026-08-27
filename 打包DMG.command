#!/bin/zsh
# 打包分发 DMG：先跑构建脚本（release + ad-hoc 签名），再用 hdiutil 装盘。
# 产物：dist/Skill Atlas-<版本>.dmg（含应用 + /Applications 软链 + 安装说明）
set -e
APP_DIR="${0:A:h}"
APP_BUNDLE="$APP_DIR/Skill Atlas.app"

"$APP_DIR/构建原生应用.command"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$APP_BUNDLE/Contents/Info.plist")
DIST="$APP_DIR/dist"
STAGE=$(mktemp -d /tmp/skill-atlas-dmg.XXXXXX)
DMG="$DIST/Skill Atlas-$VERSION.dmg"

mkdir -p "$DIST"
rm -f "$DMG"

cp -R "$APP_BUNDLE" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/安装说明.txt" <<'EOF'
Skill Atlas 安装说明
====================

1. 安装：把「Skill Atlas.app」拖进旁边的「Applications」文件夹。

2. 首次打开：在应用程序里对 Skill Atlas 点右键 →「打开」，再点「打开」确认。
   （应用未经 Apple 公证，直接双击会被 Gatekeeper 拦下；右键打开只需要做这一次。）

3. 系统要求：macOS 14（Sonoma）或更新版本，Apple 芯片。

4. 菜单栏：安装后菜单栏常驻搜索，⌥⌘K 呼出，回车复制调用语。

5. 首次打开：若发现还没收进来的 CC Switch 技能，会弹出迁移对话框（可跳过）。
   原文件保留，随时可撤销。不改 CC Switch 的数据库和原目录。

6. 数据目录就是 ~/.skill-atlas/（和 CC Switch 一样一个文件夹）：
   atlas.json、skills/、skill-backups/、migration.json。
   绝不写入 ~/.cc-switch/cc-switch.db 或 ~/.cc-switch/skills。

7. 侧栏：我的技能 / 设置（⌘1–⌘2）。
   点开技能即可同步到软件、复制调用语。挡住使用的问题写在详情顶部；整理建议在设置 → 维护。
   ⌥⌘K 呼出菜单栏，回车复制调用语。
   设置页可切换界面语言（简中/English/日本語/한국어）与深浅色。

8. 命令行：应用包内 Contents/MacOS/atlas。Agent 用它搜、装、启停、诊断。
   关键级安全命中会给出 skillatlas:// 链接，在窗口里批准后再重跑同一条 install。
EOF

hdiutil create -volname "Skill Atlas $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "已生成：$DMG（$(du -h "$DMG" | cut -f1 | tr -d ' ')）"

# 发布助手。sha256 必须用 GitHub Release 资产的 digest，不能用本地 DMG：
# gh 上传后文件名空格变点，体积也可能差几个字节，本地哈希会让应用内更新直接失败。
LOCAL_SHA=$(shasum -a 256 "$DMG" | cut -d' ' -f1)
ASSET="Skill.Atlas-$VERSION.dmg"
echo ""
echo "―― 发布顺序 ――"
echo "1. 上传 DMG 到 GitHub Release（tag v$VERSION）"
echo "2. 用仓库里的 GitHub digest 写 appcast（不要用下面的本地哈希）："
echo "   gh release view v$VERSION --json assets --jq '.assets[] | select(.name|endswith(\".dmg\")) | .digest'"
echo "3. download 指向 https://github.com/shoumunan/skill-atlas/releases/latest"
echo "4. 推送 appcast 到 main"
echo "本地 DMG sha256（仅供对照，不要写进 appcast）：$LOCAL_SHA"
