# shellcheck shell=sh
# Adapter: zcode.
# TODO: verify zcode has a non-interactive mode and a reliable "done" signal
# before adding it to any pool. If it only has a TUI, adapter_wait must
# parse pane output — keep that parsing inside this file.

adapter_spawn() { not_implemented "zcode: adapter_spawn"; }
adapter_dispatch() { not_implemented "zcode: adapter_dispatch"; }
adapter_wait() { not_implemented "zcode: adapter_wait"; }
adapter_capability() { not_implemented "zcode: adapter_capability"; }
