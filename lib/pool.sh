# shellcheck shell=sh
# Dynamic agent pool. Agents are declared statically in orchestra.config.json;
# the scheduler matches them to tasks by skill (no per-task override, no
# interactive pick — ADR-0006). Each agent is driven through its adapter
# (adapters/<adapter>.sh). Adapters share function names, so pool_call sources
# the adapter in a subshell to keep them isolated.

# pool_call <agent> <adapter-fn> [args...] — run one adapter function for the
# agent. The agent name is passed to the adapter as its first argument.
pool_call() {
  _agent=$1
  _fn=$2
  shift 2
  _adapter=$(agent_field "$_agent" '.adapter // empty')
  [ -n "$_adapter" ] || die "unknown agent: $_agent"
  _file=$ORCHESTRA_HOME/adapters/$_adapter.sh
  [ -f "$_file" ] || die "agent $_agent: no adapter $_adapter ($_file)"
  (
    # shellcheck source=/dev/null
    . "$_file"
    "adapter_$_fn" "$_agent" "$@"
  )
}

# pool_spawn <agent> — verify the agent's CLI is present and in the right mode.
pool_spawn() { pool_call "$1" spawn; }

# pool_skills <agent> — the agent's skills: the config list, or the adapter's
# defaults when the config omits them.
pool_skills() {
  _s=$(agent_field "$1" '.skills[]?')
  [ -n "$_s" ] && { printf '%s\n' "$_s"; return 0; }
  pool_call "$1" capability
}

# pool_agents_for_skill <skill> — names of agents advertising the skill.
# Always returns 0 (an empty answer is a valid answer under set -e).
pool_agents_for_skill() {
  _skill=$1
  config_get '.agents[].name' | while IFS= read -r _a; do
    if pool_skills "$_a" | grep -qx "$_skill"; then
      printf '%s\n' "$_a"
    fi
  done
}
