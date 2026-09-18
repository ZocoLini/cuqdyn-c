#!/bin/bash
#SBATCH --job-name=cuqdyn-baseline
#SBATCH --output=baseline_%x_%A_%a.log
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#
# MATLAB baseline generation on drago.csic.es (user darope).
#
# Usage from the repo root on drago:
#
#   # Layers 2 and 4 for one model (quick):
#   sbatch --export=ALL,MODEL=lv2,LAYERS="[2 4]"  validation/layer6/drago_baseline.sbatch
#   sbatch --export=ALL,MODEL=nfkb,LAYERS="[2 4]" validation/layer6/drago_baseline.sbatch
#
#   # Layer 6, one seed per array task (NF-kB is the expensive one):
#   sbatch --array=1-10 --export=ALL,MODEL=lv2,LAYERS=5  validation/layer6/drago_baseline.sbatch
#   sbatch --array=1-20 --export=ALL,MODEL=nfkb,LAYERS=5 validation/layer6/drago_baseline.sbatch
#
# MODEL is lv2, ap, sir or nfkb. Each layer-6 array task writes its own
# layer6/matlab/<model>/seed_<k>/ directory, so tasks are independent and
# re-runnable; finished seeds are skipped.
#
# The MATLAB module name differs between machines; override with
#   --export=ALL,MODEL=...,MATLAB_MODULE=MATLAB/2024a
# if the default does not resolve. Check with:  module spider MATLAB

set -euo pipefail

MODEL="${MODEL:?set MODEL=lv2|ap|sir|nfkb via --export}"
LAYERS="${LAYERS:-[2 4]}"
MATLAB_MODULE="${MATLAB_MODULE:-MATLAB/2024b}"

module load "$MATLAB_MODULE"

# Under sbatch the script runs from a spool COPY, so BASH_SOURCE points away
# from the repo; SLURM_SUBMIT_DIR (the directory sbatch was invoked from,
# i.e. the repo root) is the reliable anchor there. gen_baseline.m lives in
# validation/, one level above this script.
if [ -n "${SLURM_SUBMIT_DIR:-}" ]; then
  VALIDATION_DIR="$SLURM_SUBMIT_DIR/validation"
else
  VALIDATION_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$VALIDATION_DIR"

if [ -n "${SLURM_ARRAY_TASK_ID:-}" ]; then
  SEEDS="$SLURM_ARRAY_TASK_ID"
else
  SEEDS="1:10"
fi

echo "model=$MODEL layers=$LAYERS seeds=$SEEDS"

matlab -batch "gen_baseline('$MODEL', $LAYERS, $SEEDS)"

echo "Done. Exports under validation/layer2/matlab/$MODEL/, validation/layer4/matlab/$MODEL/"
echo "and validation/layer6/matlab/$MODEL/seed_*/ (whichever layers ran)."
