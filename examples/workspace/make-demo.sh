#!/bin/sh
# make-demo.sh <dir> — build a runnable copy of this example: a workspace
# (root repo) holding two git repos, api/ and web/, seeded with a little code.
# Nested repos cannot be committed into the engine repo, hence this script.
set -eu
[ $# -eq 1 ] || { printf 'usage: %s <new-directory>\n' "$0" >&2; exit 2; }
[ ! -e "$1" ] || { printf '%s already exists\n' "$1" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)

commit() { git -C "$1" add -A && git -C "$1" -c user.name=demo -c user.email=demo@localhost commit -qm "$2"; }

mkdir -p "$1"
cd "$1"
for f in orchestra.config.json plan.json traceability.json e2e.sh; do cp "$here/$f" .; done
cp -R "$here/docs" docs
printf '.bus/\n.worktrees/\napi/\nweb/\n' > .gitignore

mkdir -p api/src api/data api/test web/src web/test
printf 'buy milk\n[x] book flights\nwrite tests\n' > api/data/todos.txt
printf '# API\n\nShell functions over data/todos.txt; one file per feature in src/.\n' > api/README.md
printf '# Web\n\nRendering in src/; reads the API from ../api/src/.\n' > web/README.md
: > api/test/.keep
: > web/test/.keep
for r in api web; do git -C "$r" init -q && commit "$r" "seed $r"; done
git init -q . && commit . "orchestra workspace"

printf 'Workspace ready in %s (root + api/ + web/).\n' "$(pwd)"
printf 'Next: cd %s && orchestra doctor && orchestra go\n' "$1"
