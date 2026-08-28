#!/bin/bash
# Layer-5 C side: run the CLI once per seed, fixing SACESS_SEED so each run
# is reproducible. No MATLAB needed.
#
#   validation/baseline/run_c_seeds.sh lv2  10
#   validation/baseline/run_c_seeds.sh nfkb 20
#
# Results land in validation/baseline/c/<model>/seed_<k>/cuqdyn-results.txt,
# which is what compare_baseline.py consumes. Uses build-serial by default;
# override with CLI=path/to/cli.

set -euo pipefail

MODEL="${1:?usage: run_c_seeds.sh lv2|ap|sir|nfkb [n_seeds]}"
NSEEDS="${2:-10}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
CLI="${CLI:-$REPO/build-serial/modules/cli/cli}"

case "$MODEL" in
    lv2)
        CONF="$REPO/example-files/lv2_partobs_cuqdyn_config.xml"
        ESS="$REPO/example-files/lv2_partobs_ess_serial_config.xml"
        DATA="$REPO/example-files/lv2_partobs_paper_data.txt"
        ;;
    ap)
        # Self-contained in validation/baseline until promoted to example-files.
        CONF="$SCRIPT_DIR/ap_partobs_cuqdyn_config.xml"
        ESS="$SCRIPT_DIR/ap_partobs_ess_serial_config.xml"
        DATA="$SCRIPT_DIR/ap_partobs_paper_data.txt"
        ;;
    sir)
        CONF="$REPO/example-files/sir_cuqdyn_config.xml"
        ESS="$REPO/example-files/sir_ess_serial_config.xml"
        DATA="$REPO/example-files/sir_paper_data.txt"
        ;;
    nfkb)
        # Full-precision sigmas + the MATLAB-matched 2e4 budget.
        CONF="$SCRIPT_DIR/nfkb_cuqdyn_fullsigma.xml"
        ESS="$SCRIPT_DIR/nfkb_ess_serial_2e4.xml"
        DATA="$REPO/example-files/nfkb_paper_data.txt"
        ;;
    *)
        echo "Unknown model '$MODEL' (use lv2, ap, sir or nfkb)" >&2
        exit 1
        ;;
esac

if [ ! -x "$CLI" ]; then
    echo "cli not found at $CLI - build first (scripts/build.sh serial) or set CLI=" >&2
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
    SACESS_SEED="$s" "$CLI" solve -c "$CONF" -s "$ESS" -d "$DATA" -o "$OUT/" \
        > "$OUT/run.log" 2>&1 || {
        echo "seed $s FAILED - see $OUT/run.log" >&2
        exit 1
    }
done

echo "All $NSEEDS seeds done under $OUTROOT"
echo "Compare with: python3 $SCRIPT_DIR/compare_baseline.py $MODEL"
