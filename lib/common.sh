# shellcheck shell=sh
# Helpers shared by every orchestra module. Sourced by bin/orchestra after
# ORCHESTRA_HOME is set. POSIX sh only: no arrays, no [[ ]], no bashisms.

# Exit codes are used by bin/orchestra and other modules, which shellcheck
# lints file by file.
# shellcheck disable=SC2034
ORCHESTRA_EXIT_OK=0
ORCHESTRA_EXIT_ERROR=1
ORCHESTRA_EXIT_USAGE=2
ORCHESTRA_EXIT_NOT_IMPLEMENTED=3

log_info() { printf 'orchestra: %s\n' "$*" >&2; }
log_warn() { printf 'orchestra: warning: %s\n' "$*" >&2; }

die() {
  printf 'orchestra: error: %s\n' "$*" >&2
  exit "$ORCHESTRA_EXIT_ERROR"
}

# not_implemented <name> — placeholder exit for skeleton functions.
not_implemented() {
  printf 'orchestra: %s is not implemented yet\n' "$1" >&2
  exit "$ORCHESTRA_EXIT_NOT_IMPLEMENTED"
}

# require_cmd <cmd>... — fail fast when a dependency is missing.
require_cmd() {
  for _cmd in "$@"; do
    command -v "$_cmd" >/dev/null 2>&1 || die "missing dependency: $_cmd"
  done
}

# orchestra_load <module>... — source lib/<module>.sh.
orchestra_load() {
  for _mod in "$@"; do
    # Module name is dynamic by design; each module is linted on its own.
    # shellcheck source=/dev/null
    . "$ORCHESTRA_HOME/lib/$_mod.sh"
  done
}

# project_root — top of the current git repo, or the working directory.
project_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# bus_dir — ephemeral per-project state (gitignored).
bus_dir() {
  printf '%s/.bus\n' "$(project_root)"
}
