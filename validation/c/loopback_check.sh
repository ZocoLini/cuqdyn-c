#!/bin/bash
# Layer-5 plumbing test without MATLAB: the CLI with the optimiser replaced by
# a loopback that returns a fixed theta. Checks that the run completes and the
# results file carries one parameter per model parameter.
#
#   loopback_check.sh <pipeline_meigo> <cuqdyn.xml> <sacess.xml> <data> <out_dir> "<theta>"

set -euo pipefail

BIN=$1
CONF=$2
ESS=$3
DATA=$4
OUT=$5
THETA=$6

mkdir -p "$OUT"
CUQDYN_MEIGO_LOOPBACK_THETA="$THETA" CUQDYN_MEIGO_LOOPBACK_EVALS=2 CUQDYN_MEIGO_TRACE_DIR="$OUT" \
  "$BIN" solve -c "$CONF" -s "$ESS" -d "$DATA" -o "$OUT/" >"$OUT/run.log" 2>&1

test -f "$OUT/cuqdyn-results.txt"
N_THETA=$(echo "$THETA" | wc -w)
N_PARAMS=$(awk '/^\[Params\]$/ { getline; print; exit }' "$OUT/cuqdyn-results.txt")
[ "$N_PARAMS" = "$N_THETA" ] || {
  echo "Params section has $N_PARAMS entries, expected $N_THETA" >&2
  exit 1
}
N_LAUNCH=$(find "$OUT" -maxdepth 1 -name 'theta_*.txt' | wc -l)
M=$(awk '/^\[Times\]$/ { getline; print; exit }' "$OUT/cuqdyn-results.txt")
[ "$N_LAUNCH" = "$M" ] || {
  echo "$N_LAUNCH launches traced, expected m=$M" >&2
  exit 1
}
echo "loopback ok: $N_LAUNCH launches, $N_PARAMS parameters"
