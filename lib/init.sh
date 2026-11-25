# shellcheck shell=sh
# `orchestra init` — scaffold orchestra into any project directory:
#   1. detect the stack (package.json, pyproject.toml, go.mod, Cargo.toml)
#   2. copy templates/docs/ -> ./docs/
#   3. write orchestra.config.json, pre-filled with the detected stack; git
#      repos one or two levels down become `repos`, each with its own stack
#      (workspace, ADR-0013), and the directory is git-initialised if needed
#   4. copy plan.json and traceability.json skeletons
#   5. copy commands/ -> ./.claude/commands/
#   6. create .bus/ and add .bus/, .worktrees/ and each repo to .gitignore
# Existing files are never overwritten unless --force.

# _init_copy <src> <dst> — copy unless dst exists (and no --force).
_init_copy() {
  if [ -e "$2" ] && [ "$_force" != 1 ]; then
    printf '  skip    %s\n' "${2#"$_root"/}"
    _skipped=$((_skipped + 1))
    return 0
  fi
  mkdir -p "$(dirname "$2")"
  cp "$1" "$2"
  printf '  create  %s\n' "${2#"$_root"/}"
  _created=$((_created + 1))
}

# _init_stack_json <language> <test> <test_one> [typecheck] [build] [setup]
_init_stack_json() {
  jq -nc --arg l "$1" --arg t "$2" --arg o "$3" --arg tc "${4:-}" --arg b "${5:-}" --arg s "${6:-}" '
    {language: $l, test: $t, test_one: $o}
    + (if $tc != "" then {typecheck: $tc} else {} end)
    + (if $b != "" then {build: $b} else {} end)
    + (if $s != "" then {setup: $s} else {} end)'
}

# init_detect_stack [root] — print the config `stack` object for the project.
init_detect_stack() {
  _r=${1:-$(project_root)}
  if [ -f "$_r/package.json" ]; then
    _lang=javascript
    _tc=""
    if [ -f "$_r/tsconfig.json" ]; then
      _lang=typescript
      _tc="npx tsc --noEmit"
    fi
    _deps=$(jq -r '((.dependencies // {}) + (.devDependencies // {})) | keys[]' "$_r/package.json" 2>/dev/null || true)
    if printf '%s\n' "$_deps" | grep -qx vitest; then
      _one="npx vitest run {files}"
    elif printf '%s\n' "$_deps" | grep -qx jest; then
      _one="npx jest {files}"
    else
      _one="npm test -- {files}"
    fi
    _build=""
    if jq -e '.scripts.build' "$_r/package.json" >/dev/null 2>&1; then
      _build="npm run build"
    fi
    _setup="npm install"
    if [ -f "$_r/package-lock.json" ]; then _setup="npm ci"; fi
    _init_stack_json "$_lang" "npm test" "$_one" "$_tc" "$_build" "$_setup"
  elif [ -f "$_r/pyproject.toml" ] || [ -f "$_r/setup.py" ] || [ -f "$_r/requirements.txt" ]; then
    _setup=""
    if [ -f "$_r/requirements.txt" ]; then _setup="pip install -r requirements.txt"; fi
    _init_stack_json python "pytest" "pytest {files}" "" "" "$_setup"
  elif [ -f "$_r/go.mod" ]; then
    _init_stack_json go "go test ./..." "go test {files}" "go vet ./..." "go build ./..." "go mod download"
  elif [ -f "$_r/Cargo.toml" ]; then
    _init_stack_json rust "cargo test" "cargo test {files}" "cargo check" "cargo build" "cargo fetch"
  else
    _init_stack_json unknown "TODO: test command" "TODO: run these test files: {files}"
  fi
}

# init_detect_repos [root] — child git repos one or two levels down (ADR-0013),
# one project-relative path per line; a repo inside another one found here is
# left out. Submodules and worktrees (a .git file) are not repos of their own.
init_detect_repos() {
  _r=${1:-$(project_root)}
  _found=$(cd "$_r" && find . -mindepth 2 -maxdepth 3 -type d -name .git \
    -not -path './.worktrees/*' -not -path '*/node_modules/*' 2>/dev/null \
    | sed -e 's|^\./||' -e 's|/\.git$||' | LC_ALL=C sort)
  printf '%s\n' "$_found" | while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    _inside=0
    for _q in $_found; do
      case $_p in "$_q"/*) _inside=1 ;; esac
    done
    [ "$_inside" = 0 ] || continue
    if printf '%s\n' "$_p" | grep -Eqx '[A-Za-z0-9_][A-Za-z0-9_.-]*(/[A-Za-z0-9_][A-Za-z0-9_.-]*)*'; then
      printf '%s\n' "$_p"
    else
      log_warn "skipping repo $_p: rename it to letters, digits, . _ - to use it (repos[].path)"
    fi
  done
}

# _init_repos_json <root> <paths> — the config's `repos` object: one entry per
# path, named after it, with the stack detected in it.
_init_repos_json() {
  printf '%s\n' "$2" | while IFS= read -r _p; do
    [ -n "$_p" ] || continue
    _n=$(printf '%s' "$_p" | tr '[:upper:]/' '[:lower:]-' | sed -e 's/[^a-z0-9._-]/-/g' -e 's/^[^a-z0-9]*//')
    case $_n in "" | root) _n="repo-$_n" ;; esac
    jq -nc --arg n "$_n" --arg p "$_p" --argjson s "$(init_detect_stack "$1/$_p")" '{($n): {path: $p, stack: $s}}'
  done | jq -s 'add // {}'
}

# init_project [--force] — run the steps above in the project root.
init_project() {
  _force=0
  while [ $# -gt 0 ]; do
    case $1 in
      --force) _force=1; shift ;;
      *)
        printf 'orchestra init: unknown option: %s\n' "$1" >&2
        exit "$ORCHESTRA_EXIT_USAGE"
        ;;
    esac
  done
  _root=$(project_root)
  _tpl=$ORCHESTRA_HOME/templates
  _created=0
  _skipped=0
  log_info "initialising orchestra in $_root"

  for _f in $(cd "$_tpl/docs" && find . -type f | sed 's|^\./||' | LC_ALL=C sort); do
    _init_copy "$_tpl/docs/$_f" "$_root/docs/$_f"
  done

  _cfg=$_root/orchestra.config.json
  if [ -e "$_cfg" ] && [ "$_force" != 1 ]; then
    printf '  skip    orchestra.config.json\n'
    _skipped=$((_skipped + 1))
  else
    _stack=$(init_detect_stack "$_root")
    _name=$(basename "$_root" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9._-]/-/g' -e 's/^[^a-z0-9]*//')
    [ -n "$_name" ] || _name=project
    _repos=$(_init_repos_json "$_root" "$(init_detect_repos "$_root")")
    jq --argjson s "$_stack" --arg p "$_name" --arg v "$(cat "$ORCHESTRA_HOME/VERSION")" \
      --argjson r "$_repos" \
      '.stack = $s | .project = $p | .orchestra_version = $v
       | if $r == {} then . else to_entries | map(., if .key == "stack" then {key: "repos", value: $r} else empty end) | from_entries end' \
      "$_tpl/orchestra.config.json" >"$_cfg"
    printf '  create  orchestra.config.json (stack: %s)\n' "$(printf '%s' "$_stack" | jq -r '.language')"
    printf '%s' "$_repos" | jq -r 'to_entries[] | "  repo    \(.value.path)/ as \(.key) (stack: \(.value.stack.language))"'
    _created=$((_created + 1))
  fi

  # Workspace (ADR-0013): the project directory is the root repo and ignores
  # the repos inside it.
  _wsp=$(jq -r '.repos // {} | .[].path' "$_cfg" 2>/dev/null || true)
  if [ -n "$_wsp" ] && ! git -C "$_root" rev-parse --git-dir >/dev/null 2>&1; then
    git -C "$_root" init -q || die "git init failed in $_root"
    printf '  init    git repository for the workspace (root)\n'
  fi

  _init_copy "$_tpl/plan.json" "$_root/plan.json"
  _init_copy "$_tpl/traceability.json" "$_root/traceability.json"
  for _c in "$ORCHESTRA_HOME"/commands/*.md; do
    _init_copy "$_c" "$_root/.claude/commands/$(basename "$_c")"
  done

  mkdir -p "$_root/.bus"
  for _ign in .bus/ .worktrees/ $(printf '%s\n' "$_wsp" | sed '/^$/d; s|$|/|'); do
    if ! grep -qxF "$_ign" "$_root/.gitignore" 2>/dev/null; then
      printf '%s\n' "$_ign" >>"$_root/.gitignore"
      printf '  update  .gitignore (+%s)\n' "$_ign"
    fi
  done

  printf '\n%s created, %s skipped.\n' "$_created" "$_skipped"
  if [ -n "$_wsp" ] && ! git -C "$_root" rev-parse --verify -q HEAD >/dev/null 2>&1; then
    printf 'Workspace with %s repo(s): commit the root repo first: git add -A && git commit -m "orchestra workspace"\n' \
      "$(printf '%s\n' "$_wsp" | grep -c .)"
  fi
  printf 'Next: fill docs/ with Claude Code (/prd ... /handoff), then run: orchestra go\n'
}
