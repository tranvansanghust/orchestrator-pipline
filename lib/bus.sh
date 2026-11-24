# shellcheck shell=sh
# Message layer: .bus/ holds every piece of runtime state as files, so a run
# can stop and resume, and a human can inspect it.
#
# .bus/
#   tasks/<id>.json        task state (schemas/task.schema.json)
#   tasks/<id>/            prompts, feedback, setup/review logs
#   agents/<id>.*          agent run log, pid, exit code
#   verify/<id>.json       VERIFY report; verify/<id>/ check logs
#   review/<id>/round-<n>/ context pack, verdicts, decision
#   escalations/<id>.md    inbox entries waiting for a human
#   frozen.json            hashes of the approved design
#   traceability.status.json  FR status computed from task states
#   log.jsonl              every transition and escalation, one JSON per line
#   stop                   present = stop after the current step

# bus_init — create the .bus/ layout if missing.
bus_init() {
  _bd=$(bus_dir)
  mkdir -p "$_bd/tasks" "$_bd/agents" "$_bd/verify" "$_bd/review" "$_bd/escalations"
  [ -f "$_bd/log.jsonl" ] || : >"$_bd/log.jsonl"
}

# bus_lock <name> — take a named lock (.bus/locks/<name>), waiting while
# another live process holds it. A lock whose holder died is taken over.
bus_lock() {
  _ld=$(bus_dir)/locks/$1
  mkdir -p "$(bus_dir)/locks"
  # The pid of this (sub)shell; $$ would be the top-level script in every
  # subshell.
  _me=$(exec sh -c 'echo $PPID')
  while ! mkdir "$_ld" 2>/dev/null; do
    _holder=$(cat "$_ld/pid" 2>/dev/null || true)
    if [ -n "$_holder" ] && ! kill -0 "$_holder" 2>/dev/null; then
      rm -rf "$_ld"
      continue
    fi
    sleep 1
  done
  printf '%s\n' "$_me" >"$_ld/pid"
}

# bus_unlock <name>
bus_unlock() { rm -rf "$(bus_dir)/locks/$1"; }

# bus_log <json-object> — append one event to .bus/log.jsonl with a timestamp.
bus_log() {
  mkdir -p "$(bus_dir)"
  printf '%s\n' "$1" | jq -c --arg ts "$(now_iso)" '{ts: $ts} + .' >>"$(bus_dir)/log.jsonl"
}
