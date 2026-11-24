# shellcheck shell=sh
# Phase-2 daemon: SCHEDULE -> SPAWN -> CODE -> VERIFY -> REVIEW -> MERGE,
# looping until the DAG is drained. Destructive actions (push, deploy,
# delete, migration) always stop at a gate.

# go_main [--profile P] — `orchestra go`: readiness check, freeze docs/,
# start the daemon.
go_main() { not_implemented go; }

# daemon_loop — the main execution loop.
daemon_loop() { not_implemented daemon_loop; }

# daemon_stop — `orchestra stop`: stop the daemon, leave state in .bus/.
daemon_stop() { not_implemented stop; }
