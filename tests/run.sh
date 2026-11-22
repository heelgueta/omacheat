#!/bin/bash
# Runs all Omacheat tests. Needs node, jq and lua.
cd "$(dirname "$0")" || exit 1
rc=0
echo "== Omacheat.js =="; node test-js.js || rc=1
echo; echo "== bin/omacheat-apply =="; ./test-apply.sh || rc=1
exit $rc
