#!/bin/zsh
set -e
APP_DIR="${0:A:h}"
PORT="${SKILL_ATLAS_PORT:-4178}"

if ! curl -s "http://127.0.0.1:${PORT}/api/skills" >/dev/null 2>&1; then
  cd "$APP_DIR"
  /usr/bin/python3 server.py > /tmp/skill-atlas.log 2>&1 &
  for _ in {1..30}; do
    curl -s "http://127.0.0.1:${PORT}/api/skills" >/dev/null 2>&1 && break
    sleep 0.1
  done
fi

URL="http://127.0.0.1:${PORT}"
if [ -d "$APP_DIR/Skill Atlas.app" ]; then
  open "$APP_DIR/Skill Atlas.app"
elif [ -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" ]; then
  open -na "Google Chrome" --args --app="$URL" --new-window
else
  open "$URL"
fi
