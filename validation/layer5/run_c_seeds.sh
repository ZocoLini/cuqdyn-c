#!/bin/bash
# Layer-5 C side: run the CLI once per seed, fixing SACESS_SEED so each run
# is reproducible. No MATLAB needed.
#
#   validation/layer5/run_c_seeds.sh lv2  10
#   validation/layer5/run_c_seeds.sh nfkb 20
#
# Results land in validation/layer5/c/<model>/seed_<k>/cuqdyn-results.txt,
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
        CONF="$REPO/example-files/lv2-partobs/cuqdyn-fim.xml"
        ESS="$REPO/example-files/lv2-partobs/sacess-serial.xml"
        DATA="$REPO/example-files/lv2-partobs/data.txt"
        ;;
    ap)
        # In common/configs until promoted to example-files.
        CONF="$CONFIGS/ap_partobs_cuqdyn_config.xml"
        ESS="$CONFIGS/ap_partobs_ess_serial_config.xml"
        DATA="$CONFIGS/ap_partobs_paper_data.txt"
        ;;
    sir)
        CONF="$REPO/example-files/sir/cuqdyn-fim.xml"
        ESS="$REPO/example-files/sir/sacess-serial.xml"
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
    SACESS_SEED="$s" "$CLI" solve -c "$CONF" -s "$ESS" -d "$DATA" -o "$OUT/" \
        > "$OUT/run.log" 2>&1 || {
        echo "seed $s FAILED - see $OUT/run.log" >&2
        exit 1
    }
done

echo "All $NSEEDS seeds done under $OUTROOT"
echo "Compare with: python3 $SCRIPT_DIR/compare_baseline.py $MODEL"
