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

# config_validate — validate against schemas/config.schema.json and warn when
# the config's orchestra_version major differs from VERSION.
config_validate() { not_implemented config_validate; }
