# shellcheck shell=sh
# Adapter: Kilo.
# TODO: verify Kilo has a non-interactive mode and a reliable "done" signal
# before adding it to any pool. If it only has a TUI, adapter_wait must
# parse pane output — keep that parsing inside this file.

adapter_spawn() { not_implemented "kilo: adapter_spawn"; }
adapter_dispatch() { not_implemented "kilo: adapter_dispatch"; }
adapter_wait() { not_implemented "kilo: adapter_wait"; }
adapter_capability() { not_implemented "kilo: adapter_capability"; }
