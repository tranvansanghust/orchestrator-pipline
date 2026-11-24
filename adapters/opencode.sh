# shellcheck shell=sh
# Adapter: OpenCode (`opencode run`, headless). Primary executor; also drives
# GLM-4.6 and DeepSeek models via the `model` field of the agent config.

adapter_spawn() { not_implemented "opencode: adapter_spawn"; }
adapter_dispatch() { not_implemented "opencode: adapter_dispatch"; }
adapter_wait() { not_implemented "opencode: adapter_wait"; }
adapter_capability() { not_implemented "opencode: adapter_capability"; }
