#!/bin/bash
set -euo pipefail

# Whatever scripts/build.sh has produced, rather than a hardcoded list.
run_suite() {
  local dir=$1

  (
    cd "$dir" || exit 1
    ctest --timeout 900
  )
}

status=0
ran=0
for dir in build/*/; do
  [ -f "$dir/CTestTestfile.cmake" ] || continue
  echo "==> ${dir%/}"
  ran=1
  run_suite "$dir" || status=1
done

if [ "$ran" = 0 ]; then
  echo "Nothing built yet. Run scripts/build.sh first."
fi

exit "$status"
