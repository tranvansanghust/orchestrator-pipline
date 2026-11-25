#!/bin/sh
# Integration build: each repo's tests, run in that repo, on orchestra/run.
set -e
(cd api && sh test/count.sh)
