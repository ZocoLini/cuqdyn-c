#!/bin/bash
set -euo pipefail
shopt -s nullglob

# Local convenience: runs the ctest suite of every build scripts/build.sh made,
# or only of those whose name starts with $1

status=0
ran=0

for dir in build/"${1:-}"*/; do
  [ -f "$dir/CTestTestfile.cmake" ] || continue
  echo "==> ${dir%/}"
  ran=1
  ctest --test-dir "$dir" --timeout 1800 --output-on-failure || status=1
done

if [ "$ran" = 0 ]; then
  echo "Nothing built yet. Run scripts/build.sh first."
fi

exit "$status"
