"""三语翻译完整性闸。

漏翻是静默失败：界面会安静地掉回中文，没人会收到任何报错。之前一次就积了
243 条。口径要跟源码实际一致——除了 L()/LF()，还有 SettingsRow(title:subtitle:)
这类把裸字符串收进去再内部 L() 的包装视图。
"""
import re
import sys
from pathlib import Path

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("native")

keys = set()
for f in (root / "swift").rglob("*.swift"):
    text = f.read_text(encoding="utf-8")
    for pattern in (
        r'\bLF?\(\s*"((?:[^"\\]|\\.)*)"',
        r'\b(?:title|subtitle|hint|note|label|text)\s*:\s*"((?:[^"\\]|\\.)*)"',
        r'\brule:\s*"((?:[^"\\]|\\.)*)"',
    ):
        for m in re.finditer(pattern, text):
            keys.add(m.group(1))
keys = {k for k in keys if k.strip() and re.search(r"[一-鿿]", k)}

failed = False
for lang in ("en", "ja", "ko"):
    path = root / "resources" / f"{lang}.lproj" / "Localizable.strings"
    table, dupes = {}, []
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r'^"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;', line)
        if not m:
            continue
        if m.group(1) in table:
            dupes.append(m.group(1))
        table[m.group(1)] = m.group(2)

    missing = sorted(k for k in keys if k not in table)
    if missing:
        failed = True
        print(f"{lang} 缺 {len(missing)} 条翻译，前 10 条：", file=sys.stderr)
        for k in missing[:10]:
            print(f"  {k}", file=sys.stderr)
    if dupes:
        failed = True
        print(f"{lang} 有重复键 {sorted(set(dupes))}（Foundation 只取最后一条，前面的静默失效）", file=sys.stderr)
    # 英译里混进中文说明没翻干净（脚本文件名等专有名词除外）
    if lang == "en":
        cn = [k for k, v in table.items()
              if k in keys and re.search(r"[一-鿿]", v) and ".command" not in v]
        if cn:
            failed = True
            print(f"en 有 {len(cn)} 条译文仍含中文：{cn[:5]}", file=sys.stderr)

if failed:
    sys.exit(1)
print(f"i18n: {len(keys)} 条界面字符串，en/ja/ko 全覆盖")
