#!/bin/bash
# Layer 5, one model: the C pipeline with MATLAB's MEIGO, then the MATLAB
# pipeline, then the lock-step comparison.
#
#   validation/layer5/run_layer5.sh lv2 [port] [base_seed]
#
# Needs pipeline_meigo built (scripts/build.sh serial release with
# add_subdirectory(validation) in the root CMakeLists) and MATLAB on PATH.
# Outputs: layer5/c/<model>/ (results + traces), layer5/matlab/<model>/ (the
# MATLAB artefacts + traces), layer5/report_<model>.md.

set -euo pipefail

MODEL=${1:?usage: run_layer5.sh lv2|ap|sir|nfkb [port] [base_seed]}
PORT=${2:-45602}
SEED=${3:-20260917}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$(cd "$VALIDATION/.." && pwd)"
CONFIGS="$VALIDATION/common/configs"

case "$MODEL" in
lv2)
  CONF="$REPO/example-files/lv2-partobs/cuqdyn-fim.xml"
  ESS="$CONFIGS/lv2_ess_serial_2e4.xml"
  DATA="$REPO/example-files/lv2-partobs/data.txt"
  ;;
ap)
  CONF="$CONFIGS/ap_partobs_cuqdyn_config.xml"
  ESS="$CONFIGS/ap_partobs_ess_serial_config.xml"
  DATA="$CONFIGS/ap_partobs_paper_data.txt"
  ;;
sir)
  CONF="$REPO/example-files/sir/cuqdyn-fim.xml"
  ESS="$CONFIGS/sir_ess_serial_2e4.xml"
  DATA="$REPO/example-files/sir/data.txt"
  ;;
nfkb)
  CONF="$CONFIGS/nfkb_cuqdyn_fullsigma.xml"
  ESS="$CONFIGS/nfkb_ess_serial_2e4.xml"
  DATA="$REPO/example-files/nfkb/data.txt"
  ;;
*)
  echo "Unknown model '$MODEL' (use lv2, ap, sir or nfkb)" >&2
  exit 1
  ;;
esac

BIN="${PIPELINE_MEIGO:-}"
if [ -z "$BIN" ]; then
  for candidate in release-serial debug-serial asan-serial; do
    [ -x "$REPO/build/$candidate/validation/pipeline_meigo" ] &&
      BIN="$REPO/build/$candidate/validation/pipeline_meigo" && break
  done
fi
if [ -z "$BIN" ] || [ ! -x "$BIN" ]; then
  echo "pipeline_meigo not found under build/ - build validation first or set PIPELINE_MEIGO=" >&2
  exit 1
fi

OUT_C="$SCRIPT_DIR/c/$MODEL"
OUT_M="$SCRIPT_DIR/matlab/$MODEL"
rm -rf "$OUT_C" "$OUT_M"
mkdir -p "$OUT_C" "$OUT_M"

echo "=== $MODEL: C pipeline, MEIGO served by MATLAB (port $PORT, base seed $SEED) ==="
CUQDYN_MEIGO_PORT="$PORT" CUQDYN_MEIGO_TRACE_DIR="$OUT_C" \
  "$BIN" solve -c "$CONF" -s "$ESS" -d "$DATA" -o "$OUT_C/" >"$OUT_C/run.log" 2>&1 &
C_PID=$!
sleep 2
matlab -batch "cd('$SCRIPT_DIR/matlab'); meigo_server('$MODEL', $PORT, $SEED, '$OUT_C')" \
  >"$OUT_C/meigo_server.log" 2>&1 || {
  echo "meigo_server failed - see $OUT_C/meigo_server.log" >&2
  kill "$C_PID" 2>/dev/null || true
  exit 1
}
wait "$C_PID" || {
  echo "pipeline_meigo failed - see $OUT_C/run.log" >&2
  exit 1
}

echo "=== $MODEL: MATLAB pipeline, same seeds ==="
matlab -batch "cd('$SCRIPT_DIR/matlab'); run_pipeline_cvodes('$MODEL', $SEED, '$OUT_M')" \
  >"$OUT_M/run.log" 2>&1 || {
  echo "run_pipeline_cvodes failed - see $OUT_M/run.log" >&2
  exit 1
}

echo "=== $MODEL: comparison ==="
"${PYTHON:-python3}" "$SCRIPT_DIR/compare_lockstep.py" "$MODEL"
