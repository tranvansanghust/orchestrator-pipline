# shellcheck shell=sh
# Project config (orchestra.config.json): locate, validate and read via jq.
# Every per-project difference must come through here or an adapter —
# the engine never hardcodes project knowledge.

# config_path — print the absolute path of the project config; fail if absent.
config_path() { not_implemented config_path; }

# config_get <jq-filter> — print one value from the project config.
config_get() { not_implemented config_get; }

# config_validate — validate the config against schemas/config.schema.json
# and warn when its orchestra_version major differs from VERSION.
config_validate() { not_implemented config_validate; }
