# shellcheck shell=sh
# Project config (orchestra.config.json): locate and read via jq.
# Every per-project difference comes through here or an adapter — the engine
# never hardcodes project knowledge.

# config_path — print the absolute path of the project config; fail if absent.
config_path() {
  _cfg=$(project_root)/orchestra.config.json
  [ -f "$_cfg" ] || die "no orchestra.config.json in $(project_root) (run: orchestra init)"
  printf '%s\n' "$_cfg"
}

# config_get <jq-args...> <jq-filter> — read from the config with jq -r.
# e.g. config_get '.profile'   config_get --arg n glm '.agents[]|select(.name==$n)'
config_get() {
  jq -r "$@" "$(config_path)"
}

# agent_field <name> <jq-path> — read one field of an agent entry.
# Caller supplies a null-safe path: agent_field glm '.model // empty',
# agent_field glm '.skills[]?'.
agent_field() {
  _name=$1
  _path=$2
  config_get --arg n "$_name" ".agents[] | select(.name == \$n) | $_path"
}

# brain_cmd <role> — command string for a brain role (planner, reviewer,
# confirmer). A role may be a string or {cmd, model}; the confirmer falls back
# to the reviewer when omitted.
brain_cmd() {
  # $r is a jq variable.
  # shellcheck disable=SC2016
  _bc=$(config_get --arg r "$1" '.brain[$r] // empty | if type == "object" then .cmd else . end')
  if [ -z "$_bc" ] && [ "$1" = confirmer ]; then
    _bc=$(brain_cmd reviewer)
  fi
  [ -n "$_bc" ] || die "brain.$1 is not set in orchestra.config.json"
  printf '%s\n' "$_bc"
}

# brain_model <role> — pinned model for the role, or empty.
brain_model() {
  # shellcheck disable=SC2016
  _bm=$(config_get --arg r "$1" '.brain[$r] // empty | if type == "object" then (.model // empty) else empty end')
  if [ -z "$_bm" ] && [ "$1" = confirmer ] && [ "$(config_get '.brain.confirmer // empty')" = "" ]; then
    _bm=$(brain_model reviewer)
  fi
  printf '%s\n' "$_bm"
}

# --- repos (ADR-0013) ----------------------------------------------------------
# The project directory is the repo named root; workspace mode adds the repos
# listed under .repos. Paths in plan.json are relative to the project directory.

# repo_names — root, then every configured repo.
repo_names() {
  config_get '"root", (.repos // {} | keys_unsorted[])'
}

# repo_path <name> — the repo's path relative to the project directory (root: .).
repo_path() {
  config_get --arg r "$1" 'if $r == "root" then "." else .repos[$r].path // empty end'
}

# repo_stack <name> <key> — one stack command of the repo, or empty.
repo_stack() {
  config_get --arg r "$1" --arg k "$2" \
    '(if $r == "root" then .stack else .repos[$r].stack end) // {} | .[$k] // empty'
}

# repo_of <path> — the repo that owns a project-relative path or glob: the
# configured repo whose path prefixes it, root otherwise.
repo_of() {
  config_get --arg p "$1" '
    [.repos // {} | to_entries[] | .value.path as $rp
      | select($p == $rp or ($p | startswith($rp + "/")))]
    | max_by(.value.path | length) | .key // "root"'
}

# _cfg_repos_check — workspace layout: every repo is its own git repository
# with a commit, gitignored by root, and no repo sits inside another.
_cfg_repos_check() {
  _crc_root=$(project_root)
  _crc_bad=0
  _crc_paths=$(config_get '.repos // {} | to_entries[] | "\(.key)\t\(.value.path)"')
  [ -n "$_crc_paths" ] || return 0
  _crc_tab=$(printf '\t')
  while IFS="$_crc_tab" read -r _crc_n _crc_p; do
    _crc_clash=$(config_get --arg n "$_crc_n" --arg p "$_crc_p/" '
      [.repos | to_entries[] | .value.path as $rp
        | select(.key != $n and ($p | startswith($rp + "/")))]
      | first.key // empty')
    if [ -n "$_crc_clash" ]; then
      printf 'repos.%s (%s) is inside repos.%s\n' "$_crc_n" "$_crc_p" "$_crc_clash" >&2
      _crc_bad=1
      continue
    fi
    _crc_dir=$_crc_root/$_crc_p
    if [ ! -d "$_crc_dir" ]; then
      printf 'repos.%s: %s does not exist\n' "$_crc_n" "$_crc_p" >&2
      _crc_bad=1
      continue
    fi
    _crc_top=$(git -C "$_crc_dir" rev-parse --show-toplevel 2>/dev/null) || _crc_top=
    if [ -z "$_crc_top" ] || [ "$(cd "$_crc_top" && pwd -P)" != "$(cd "$_crc_dir" && pwd -P)" ]; then
      printf 'repos.%s: %s is not the top of a git repository\n' "$_crc_n" "$_crc_p" >&2
      _crc_bad=1
      continue
    fi
    if ! git -C "$_crc_dir" rev-parse --verify -q HEAD >/dev/null 2>&1; then
      printf 'repos.%s: %s has no commit yet\n' "$_crc_n" "$_crc_p" >&2
      _crc_bad=1
    fi
    if git -C "$_crc_root" rev-parse --git-dir >/dev/null 2>&1 \
      && ! git -C "$_crc_root" check-ignore -q "$_crc_p/"; then
      printf 'repos.%s: add %s/ to the root .gitignore\n' "$_crc_n" "$_crc_p" >&2
      _crc_bad=1
    fi
  done <<EOF
$_crc_paths
EOF
  return "$_crc_bad"
}

# config_validate — validate against schemas/config.schema.json and the
# workspace layout (errors on stderr, return 1) and print a warning on stdout
# when the project's pinned orchestra_version has a different major than the
# engine.
config_validate() {
  _cvf=$(config_path)
  if command -v check-jsonschema >/dev/null 2>&1; then
    if ! _cve=$(check-jsonschema --schemafile "$ORCHESTRA_HOME/schemas/config.schema.json" "$_cvf" 2>&1); then
      printf 'does not match schemas/config.schema.json: %s\n' \
        "$(printf '%s' "$_cve" | grep -v '^Schema validation errors' | tail -n 2 | tr '\n' ' ')" >&2
      return 1
    fi
  else
    printf 'check-jsonschema not installed; config not validated\n'
  fi
  _cfg_repos_check || return 1
  _pin=$(config_get '.orchestra_version // ""')
  _eng=$(cat "$ORCHESTRA_HOME/VERSION")
  if [ -n "$_pin" ] && [ "${_pin%%.*}" != "${_eng%%.*}" ]; then
    printf 'project pinned to orchestra %s but the engine is %s (major differs; read CHANGELOG.md before running)\n' "$_pin" "$_eng"
  fi
  return 0
}
