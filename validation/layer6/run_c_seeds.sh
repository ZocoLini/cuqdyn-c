#!/bin/bash
# Layer-6 C side: run the CLI once per seed, fixing SACESS_SEED so each run
# is reproducible. No MATLAB needed.
#
#   validation/layer6/run_c_seeds.sh lv2  10
#   validation/layer6/run_c_seeds.sh nfkb 20
#
# Results land in validation/layer6/c/<model>/seed_<k>/cuqdyn-results.txt,
# which is what compare_baseline.py consumes. Picks the first serial build
# under build/ by default; override with CLI=path/to/cli.

set -euo pipefail

MODEL="${1:?usage: run_c_seeds.sh lv2|ap|sir|nfkb [n_seeds]}"
NSEEDS="${2:-10}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATION="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO="$(cd "$VALIDATION/.." && pwd)"
CONFIGS="$VALIDATION/common/configs"
CLI="${CLI:-}"
if [ -z "$CLI" ]; then
  for candidate in release-serial debug-serial; do
    [ -x "$REPO/build/$candidate/modules/cli/cli" ] &&
      CLI="$REPO/build/$candidate/modules/cli/cli" && break
  done
fi

case "$MODEL" in
lv2)
  # example-files budget is 2000 evaluations; MATLAB's gen_baseline.m uses 2e4.
  CONF="$REPO/example-files/lv2-partobs/cuqdyn-fim.xml"
  ESS="$CONFIGS/lv2_ess_serial_2e4.xml"
  DATA="$REPO/example-files/lv2-partobs/data.txt"
  ;;
ap)
  # In common/configs until promoted to example-files.
  CONF="$CONFIGS/ap_partobs_cuqdyn_config.xml"
  ESS="$CONFIGS/ap_partobs_ess_serial_config.xml"
  DATA="$CONFIGS/ap_partobs_paper_data.txt"
  ;;
sir)
  # example-files budget is 1000 evaluations; MATLAB's gen_baseline.m uses 2e4.
  CONF="$REPO/example-files/sir/cuqdyn-fim.xml"
  ESS="$CONFIGS/sir_ess_serial_2e4.xml"
  DATA="$REPO/example-files/sir/data.txt"
  ;;
nfkb)
  # Full-precision sigmas + the MATLAB-matched 2e4 budget.
  CONF="$CONFIGS/nfkb_cuqdyn_fullsigma.xml"
  ESS="$CONFIGS/nfkb_ess_serial_2e4.xml"
  DATA="$REPO/example-files/nfkb/data.txt"
  ;;
*)
  echo "Unknown model '$MODEL' (use lv2, ap, sir or nfkb)" >&2
  exit 1
  ;;
esac

if [ -z "$CLI" ] || [ ! -x "$CLI" ]; then
  echo "cli not found under build/ - build first (scripts/build.sh serial) or set CLI=" >&2
  exit 1
fi

OUTROOT="$SCRIPT_DIR/c/$MODEL"
mkdir -p "$OUTROOT"

for ((s = 1; s <= NSEEDS; s++)); do
  OUT="$OUTROOT/seed_$s"
  if [ -f "$OUT/cuqdyn-results.txt" ]; then
    echo "seed $s already done, skipping"
    continue
  fi
  mkdir -p "$OUT"
  echo "=== seed $s / $NSEEDS ==="
  # Wall clock per seed, so the C and MATLAB sides can be compared on cost as
  # well as on results. gen_baseline.m writes the same file on its side.
  START=$(date +%s.%N)
  SACESS_SEED="$s" "$CLI" solve -c "$CONF" -s "$ESS" -d "$DATA" -o "$OUT/" \
    >"$OUT/run.log" 2>&1 || {
    echo "seed $s FAILED - see $OUT/run.log" >&2
    exit 1
  }
  awk -v a="$START" -v b="$(date +%s.%N)" 'BEGIN{printf "seconds %.3f\n", b-a}' \
    >"$OUT/timing.txt"
  echo "    $(cat "$OUT/timing.txt")"
done

echo "All $NSEEDS seeds done under $OUTROOT"
echo "Compare with: python3 $SCRIPT_DIR/compare_baseline.py $MODEL"
