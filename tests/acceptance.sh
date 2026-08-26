#!/bin/zsh
# Skill Atlas 验收入口。每个 WP 往这里加段，输出与金样比对（jq 归一化）。
set -euo pipefail
ROOT="${0:A:h:h}"
cd "$ROOT"

json_get() {
  python3 -c 'import json,sys; print(json.load(sys.stdin)'"$1"')'
}

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

# --- WP0 ---
VERSION_OUT=$("$ATLAS" --version)
echo "version: $VERSION_OUT"
[[ "$VERSION_OUT" == atlas* ]] || { echo "version 输出应以 atlas 开头" >&2; exit 1; }
HELP_RC=0
"$ATLAS" --help >/dev/null 2>&1 || HELP_RC=$?
[[ "$HELP_RC" == 0 ]] || { echo "--help 应退出 0，实际 $HELP_RC" >&2; exit 1; }
echo "WP0 acceptance OK"

# --- WP1 ---
FAKE=$(mktemp -d /tmp/atlas-wp1.XXXXXX)
cleanup() { rm -rf "$FAKE"; }
trap cleanup EXIT

mkdir -p "$FAKE/.skill-atlas/skills" "$FAKE/.claude/skills"
for name in alpha beta gamma; do
  dir="$FAKE/.skill-atlas/skills/$name"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" <<EOF
---
name: $name
description: $name helper for atlas CLI tests. Use when the user mentions $name.
---
# $name
EOF
done

python3 - "$FAKE" <<'PY'
import json, sys
root = sys.argv[1]
skills = {}
for name in ("alpha", "beta", "gamma"):
    skills[name] = {
        "directory": name,
        "enabled": {"claude": False},
        "repoOwner": "",
        "repoName": "",
        "repoBranch": "main",
        "installedAt": 1,
        "updatedAt": 1,
    }
with open(root + "/.skill-atlas/atlas.json", "w") as fh:
    json.dump({"version": 1, "skills": skills}, fh)
PY

export ATLAS_HOME="$FAKE"

LIST_JSON=$("$ATLAS" list --json)
echo "$LIST_JSON" | python3 -c '
import json,sys
doc=json.load(sys.stdin)
assert doc["ok"] is True
assert doc["code"]==0
assert doc["op"]=="list"
assert doc["error"] is None
skills=doc["data"]["skills"]
assert len(skills)==3, skills
assert {s["name"] for s in skills}=={"alpha","beta","gamma"}
for s in skills:
    assert "dir" in s and "desc" in s and "platforms" in s
    assert "claude" in s["platforms"]
print("list --json OK", "scanSeconds=", doc["data"].get("scanSeconds"))
'

# 占着锁 → enable 必须退出 6
printf '%s\n%s\n' "$$" "$(date +%s)" > "$FAKE/.skill-atlas/.lock"
LOCK_RC=0
"$ATLAS" enable alpha --platform claude --json >/tmp/atlas-lock.json || LOCK_RC=$?
rm -f "$FAKE/.skill-atlas/.lock"
[[ "$LOCK_RC" == 6 ]] || { echo "占锁时 enable 应退出 6，实际 $LOCK_RC" >&2; cat /tmp/atlas-lock.json; exit 1; }
echo "lock exit 6 OK"

"$ATLAS" enable alpha --platform claude --json >/tmp/atlas-en1.json
python3 - <<'PY'
import json
doc=json.load(open("/tmp/atlas-en1.json"))
assert doc["ok"] is True
assert doc["data"]["platforms"]["claude"] is True
print("enable JSON OK")
PY
[[ -L "$FAKE/.claude/skills/alpha" ]] || { echo "enable 后应有软链" >&2; ls -la "$FAKE/.claude/skills"; exit 1; }
python3 - "$FAKE" <<'PY'
import json,sys
cat=json.load(open(sys.argv[1]+"/.skill-atlas/atlas.json"))
assert cat["skills"]["alpha"]["enabled"]["claude"] is True
print("catalog enabled bit OK")
PY

"$ATLAS" enable beta --platform claude --json >/tmp/atlas-en2.json
OPLOG="$FAKE/.skill-atlas/oplog.jsonl"
[[ -f "$OPLOG" ]] || { echo "缺少 oplog.jsonl" >&2; exit 1; }
OP_COUNT=$(grep -c . "$OPLOG" || true)
[[ "$OP_COUNT" == 2 ]] || { echo "oplog 应有 2 行，实际 $OP_COUNT" >&2; cat "$OPLOG"; exit 1; }
echo "oplog +2 OK"

"$ATLAS" simulate "alpha helper" --json >/tmp/atlas-sim.json
python3 - <<'PY'
import json
doc=json.load(open("/tmp/atlas-sim.json"))
assert doc["ok"] is True
ranked=doc["data"]["ranked"]
assert ranked, doc
assert ranked[0]["name"]=="alpha"
print("simulate OK", ranked[0])
PY

echo "WP1 acceptance OK"
