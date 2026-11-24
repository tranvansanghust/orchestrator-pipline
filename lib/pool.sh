# shellcheck shell=sh
# Dynamic agent pool. Each agent from orchestra.config.json is driven through
# its adapter (adapters/<name>.sh). Adapters share function names, so every
# call sources the adapter inside a subshell to keep them isolated.

# pool_call <agent> <adapter-fn> [args...] — run one adapter function for
# the given agent in a subshell.
pool_call() { not_implemented pool_call; }

# pool_spawn <agent> — start (or reuse) the agent's pane.
pool_spawn() { not_implemented pool_spawn; }

# pool_agents_for_skill <skill> — print agent names advertising the skill.
pool_agents_for_skill() { not_implemented pool_agents_for_skill; }
