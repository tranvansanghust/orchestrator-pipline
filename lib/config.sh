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

# config_validate — validate against schemas/config.schema.json and warn when
# the config's orchestra_version major differs from VERSION.
config_validate() { not_implemented config_validate; }
