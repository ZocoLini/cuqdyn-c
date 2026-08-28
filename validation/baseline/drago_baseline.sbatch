#!/bin/bash
#SBATCH --job-name=cuqdyn-baseline
#SBATCH --output=baseline_%x_%A_%a.log
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#
# MATLAB baseline generation on drago.cesga.es (user darope).
#
# Usage from the repo root on drago:
#
#   # Layers 3+4 for both models (two quick jobs):
#   sbatch --export=ALL,MODEL=lv2,LAYERS="[3 4]"  validation/baseline/drago_baseline.sbatch
#   sbatch --export=ALL,MODEL=nfkb,LAYERS="[3 4]" validation/baseline/drago_baseline.sbatch
#
#   # Layer 5, one seed per array task (NF-kB is the expensive one):
#   sbatch --array=1-10 --export=ALL,MODEL=lv2,LAYERS=5  validation/baseline/drago_baseline.sbatch
#   sbatch --array=1-20 --export=ALL,MODEL=nfkb,LAYERS=5 validation/baseline/drago_baseline.sbatch
#
# Each layer-5 array task writes its own seed_<k>/ directory, so tasks are
# independent and re-runnable; finished seeds are skipped.
#
# The MATLAB module name differs between CESGA machines; override with
#   --export=ALL,MODEL=...,MATLAB_MODULE=matlab/R2024a
# if the default does not resolve. Check with:  module spider matlab

set -euo pipefail

MODEL="${MODEL:?set MODEL=lv2 or MODEL=nfkb via --export}"
LAYERS="${LAYERS:-[3 4]}"
MATLAB_MODULE="${MATLAB_MODULE:-matlab}"

module load "$MATLAB_MODULE"

# Repo root = two levels up from this script's directory.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
    SEEDS="$SLURM_ARRAY_TASK_ID"
else
    SEEDS="1:10"
fi

echo "model=$MODEL layers=$LAYERS seeds=$SEEDS"

matlab -batch "gen_baseline('$MODEL', $LAYERS, $SEEDS)"

echo "Done. Exports under validation/baseline/matlab/$MODEL/"
echo "Pack for the C-side colleagues with:"
echo "  tar czf baseline_${MODEL}.tar.gz -C $SCRIPT_DIR/matlab $MODEL"
