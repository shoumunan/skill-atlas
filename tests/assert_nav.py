"""校验 -atlasNavProbe 的输出。五项导航与深链此前没有任何自动化用例。"""
import json
import sys

d = json.load(open(sys.argv[1]))

expected_pages = ["library", "add", "tools", "updates", "settings"]
assert d["pages"] == expected_pages, f"侧栏顺序变了（⌘1–⌘5 会错位）：{d['pages']}"
assert d["titlesNonEmpty"], "有页面缺标题"
assert d["helpNonEmpty"], "有页面缺帮助文案"

r = d["routes"]
for link, page in [
    ("skillatlas://discover", "add"),
    ("skillatlas://supply", "updates"),
    ("skillatlas://inbox", "updates"),
    ("skillatlas://inbox/mount:demo:abc12345", "updates"),
    ("skillatlas://skill/demo", "library"),
]:
    assert r[link] == page, f"深链 {link} 应落到 {page}，实际 {r[link]}"

assert d["focusConsumed"], "inbox/<id> 应设置待定位条目"
assert d["badgeExcludesTidy"], "整理类事项必须可忽略（否则会永久占着徽标）"
