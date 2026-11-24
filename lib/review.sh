# shellcheck shell=sh
# REVIEW layer: headless `claude -p`, runs only after VERIFY is green.
# The reviewer is stateless; its context is rebuilt from artifacts each time:
#
#   fixed   : rubric.md + 09-review-brief.md + 02-architecture.md + conventions.md
#   dynamic : specs/<id> + dep contracts (api-spec) + diff + verify report
#   v2+     : previous verdict + requested fixes
#
# Cut order when over budget: conventions, dep contracts, diff, spec+test,
# brief, rubric (last). Diff and tests are never dropped.

# review_build_pack <task-id> — print the path of the assembled context pack.
review_build_pack() { not_implemented review_build_pack; }

# review_run <task-id> — run the reviewer, validate the verdict JSON, write
# .bus/verdicts/<task-id>.json and print ACCEPT|REJECT|ESCALATE.
review_run() { not_implemented review_run; }
