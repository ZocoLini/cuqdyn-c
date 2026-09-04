#!/bin/bash
set -euo pipefail

# Validates the MPI implementation of the algorithm through its defining
# invariant: with a fixed SACESS_SEED the result must not depend on the
# process count. sacess reseeds its RNG on every solver invocation, so each
# LOO refit is deterministic no matter which rank runs it - np=1 and np=k
# must produce the same cuqdyn-results.txt.
#
#   scripts/test-mpi.sh [build_dir]
#
# build_dir defaults to the first of build/release-mpi, build/debug-mpi.
# Exercises the partially observed lv2 case (m-1 = 30 time points, so the
# process counts 2, 3 and 5 divide it and 4 does not). Four checks:
#
#   1. np=1 runs and produces a result            (baseline)
#   2. np=2 and np=5 reproduce np=1 exactly       (sharding invariance)
#   3. np=4 aborts with the divisibility message  (guard works, no hang)
#   4. every run is wrapped in a timeout          (a deadlock fails, not hangs)

if [ -t 1 ]; then
  YELLOW=$'\033[0;33m'
  RED=$'\033[0;31m'
  GREEN=$'\033[0;32m'
  NC=$'\033[0m'
else
  YELLOW="" RED="" GREEN="" NC=""
fi

if [ -d "/home/cesga" ]; then
  module load cesga/2025 gcc/system openmpi/5.0.7 rust/1.88.0
fi

BUILD_DIR="${1:-}"
if [ -z "$BUILD_DIR" ]; then
  for candidate in build/release-mpi build/debug-mpi; do
    [ -x "$candidate/modules/cli/cli" ] && BUILD_DIR=$candidate && break
  done
fi
if [ -z "$BUILD_DIR" ] || [ ! -x "$BUILD_DIR/modules/cli/cli" ]; then
  echo "${RED}No MPI build found. Run 'scripts/build.sh mpi' first.${NC}"
  exit 1
fi

CLI="$BUILD_DIR/modules/cli/cli"
MODEL_DIR=example-files/lv2-partobs
WORK="$BUILD_DIR/mpi-invariance"
TIMEOUT=${MPI_TEST_TIMEOUT:-900}

# The serial sacess config on every run: under -DMPI each rank runs its own
# serial eSS over its shard, so the cooperative settings of sacess-mpi.xml
# play no role in what is being tested here.
CONF="$MODEL_DIR/cuqdyn-fim.xml"
ESS="$MODEL_DIR/sacess-serial.xml"
DATA="$MODEL_DIR/data.txt"

MPIFLAGS=(--oversubscribe)
[ "$(id -u)" = 0 ] && MPIFLAGS+=(--allow-run-as-root)

export SACESS_SEED=1

rm -rf "$WORK"
mkdir -p "$WORK"

run_np() {
  local np=$1 out="$WORK/np$1"
  mkdir -p "$out"
  timeout "$TIMEOUT" mpirun "${MPIFLAGS[@]}" -np "$np" \
    "$CLI" solve -c "$CONF" -s "$ESS" -d "$DATA" -o "$out/" \
    >"$out/run.log" 2>&1
}

status=0

echo "${YELLOW}==> np=1 (reference)${NC}"
if run_np 1 && [ -f "$WORK/np1/cuqdyn-results.txt" ]; then
  echo "    ok"
else
  echo "${RED}    FAIL: np=1 did not produce a result (see $WORK/np1/run.log)${NC}"
  exit 1
fi

for np in 2 5; do
  echo "${YELLOW}==> np=$np (must reproduce np=1)${NC}"
  if ! run_np "$np"; then
    echo "${RED}    FAIL: run errored or timed out (see $WORK/np$np/run.log)${NC}"
    status=1
    continue
  fi
  if diff -q "$WORK/np1/cuqdyn-results.txt" "$WORK/np$np/cuqdyn-results.txt" >/dev/null; then
    echo "    ok: byte-identical to np=1"
  else
    echo "${RED}    FAIL: result differs from np=1${NC}"
    diff "$WORK/np1/cuqdyn-results.txt" "$WORK/np$np/cuqdyn-results.txt" | head -10
    status=1
  fi
done

echo "${YELLOW}==> np=4 (4 does not divide 30: must abort cleanly)${NC}"
if run_np 4; then
  echo "${RED}    FAIL: np=4 exited 0, the divisibility guard did not fire${NC}"
  status=1
elif grep -q "do not divide" "$WORK/np4/run.log"; then
  echo "    ok: aborted with the divisibility message"
else
  echo "${RED}    FAIL: np=4 failed without the expected message (deadlock/timeout?)${NC}"
  tail -5 "$WORK/np4/run.log"
  status=1
fi

echo ""
if [ "$status" = 0 ]; then
  echo "${GREEN}MPI invariance suite passed${NC}"
else
  echo "${RED}MPI invariance suite FAILED${NC}"
fi
exit "$status"
