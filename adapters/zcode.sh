# shellcheck shell=sh
# Adapter: ZCode (Z.ai) headless — `zcode -p <prompt> --cwd <dir> --json`.
# Run-to-exit. Verified against zcode 0.17.1 `--help`:
#   -p/--prompt runs a single prompt without the TUI; --mode defaults to yolo
#   for prompts; --workflow-mode defaults to disabled (passed explicitly so a
#   changed default cannot silently switch dynamic workflows on).
#
# Locating the CLI, in order:
#   ORCHESTRA_ZCODE_BIN   a command to run zcode (tests, custom installs)
#   zcode on PATH
#   the ZCode.app bundle (macOS): the app's Electron binary as Node, running
#   Contents/Resources/glm/zcode.cjs; override the bundle with ZCODE_APP.
# The model is chosen in ZCode's own settings; the agent's `model` field is
# not passed (zcode has no --model flag).

_zc_app() { printf '%s\n' "${ZCODE_APP:-/Applications/ZCode.app}"; }

# _zc_cmd — print the zcode invocation as a shell word list, or fail.
_zc_cmd() {
  if [ -n "${ORCHESTRA_ZCODE_BIN:-}" ]; then
    printf '%s\n' "$ORCHESTRA_ZCODE_BIN"
  elif command -v zcode >/dev/null 2>&1; then
    printf 'zcode\n'
  elif [ -x "$(_zc_app)/Contents/MacOS/ZCode" ] && [ -f "$(_zc_app)/Contents/Resources/glm/zcode.cjs" ]; then
    printf 'env ELECTRON_RUN_AS_NODE=1 "%s/Contents/MacOS/ZCode" "%s/Contents/Resources/glm/zcode.cjs"\n' "$(_zc_app)" "$(_zc_app)"
  else
    return 1
  fi
}

adapter_spawn() {
  # <agent> — the CLI must exist and answer `version`.
  _zc=$(_zc_cmd) || {
    log_warn "zcode not found (set ORCHESTRA_ZCODE_BIN, put zcode on PATH, or install ZCode.app)"
    return 1
  }
  eval "set -- $_zc"
  "$@" version >/dev/null 2>&1 || {
    log_warn "zcode did not answer 'version'"
    return 1
  }
}

adapter_dispatch() {
  # <agent> <task-id> <spec-file> <workdir>
  _task=$2
  _spec=$3
  _wd=$4
  _zc=$(_zc_cmd) || return 1
  eval "set -- $_zc"
  set -- "$@" -p "$(cat "$_spec")" --cwd "$_wd" --mode yolo --workflow-mode disabled --json --no-color
  run_to_exit_dispatch "$_task" "$_wd" "$@"
}

adapter_wait() {
  run_to_exit_wait "$2" "${3:-0}"
}

adapter_capability() {
  printf '%s\n' backend api frontend algo refactor
}
