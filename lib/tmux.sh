# shellcheck shell=sh
# tmux layout and signalling. Panes are addressed by stable names
# (e.g. orchestra:main.cockpit), never by drifting indexes.
#
#   cockpit (Claude TUI) | agent panes (spawned on demand)
#   ---------------------+-----------------------------------
#   agent panes          | watcher (log + escalation dashboard)

# tmux_open_cockpit — `orchestra design`: create/attach the session with the
# Claude TUI pane for phase 1.
tmux_open_cockpit() { not_implemented design; }

# tmux_pane_create <name> <command> — create a named pane running command.
tmux_pane_create() { not_implemented tmux_pane_create; }

# tmux_focus <name> — move the human's cursor to the named pane.
tmux_focus() { not_implemented tmux_focus; }

# tmux_signal <channel> / tmux_wait <channel> — wrappers over tmux wait-for.
tmux_signal() { not_implemented tmux_signal; }
tmux_wait() { not_implemented tmux_wait; }
