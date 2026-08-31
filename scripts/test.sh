#!/bin/bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: scripts/test.sh [prefix...]

  prefix    only the build directories starting with it, e.g. 'asan' for
            build/asan-serial. Defaults to everything scripts/build.sh made.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
esac

PREFIXES=("$@")
[ ${#PREFIXES[@]} -eq 0 ] && PREFIXES=("")

# Whatever scripts/build.sh has produced, rather than a hardcoded list.
run_suite() {
  local dir=$1

  (
    cd "$dir" || exit 1
    # A sanitizer writes its report to the failing test's output, which ctest
    # swallows by default.
    ctest --timeout 1800 --output-on-failure
  )
}

status=0
ran=0
for prefix in "${PREFIXES[@]}"; do
  for dir in build/"$prefix"*/; do
    [ -f "$dir/CTestTestfile.cmake" ] || continue
    echo "==> ${dir%/}"
    ran=1
    run_suite "$dir" || status=1
  done
done

if [ "$ran" = 0 ]; then
  echo "Nothing built yet. Run scripts/build.sh first."
fi

exit "$status"
