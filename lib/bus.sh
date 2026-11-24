# shellcheck shell=sh
# Message layer: .bus/ mailbox of JSON files plus the append-only audit log.
#
# .bus/
#   tasks/<id>.json        task state (see schemas/task.schema.json)
#   specs/<id>.md          task spec handed to the agent
#   verdicts/<id>.json     reviewer output (schemas/verdict.schema.json)
#   escalations/<id>.md    inbox entries waiting for a human
#   log.jsonl              every transition and escalation, one JSON per line

# bus_init — create the .bus/ layout if missing.
bus_init() { not_implemented bus_init; }

# bus_write <kind> <id> — write stdin to .bus/<kind>/<id>.json atomically.
bus_write() { not_implemented bus_write; }

# bus_read <kind> <id> — print .bus/<kind>/<id>.json.
bus_read() { not_implemented bus_read; }

# bus_log <event-json> — append one event to .bus/log.jsonl with a timestamp.
bus_log() { not_implemented bus_log; }
