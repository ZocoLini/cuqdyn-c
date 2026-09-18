#!/bin/bash
#SBATCH --job-name=cuqdyn-layer5
#SBATCH --output=layer5_%x_%j.log
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#
# Layer 5 on drago.csic.es: both processes on one node, from the repo root.
#
#   sbatch --export=ALL,MODEL=lv2 validation/layer5/drago_layer5.sbatch
#
# The environment that built pipeline_meigo must be exported (--export=ALL);
# override the MATLAB module with MATLAB_MODULE=... if it is not MATLAB/2024b.

set -euo pipefail

MODEL="${MODEL:?set MODEL=lv2|ap|sir|nfkb via --export}"
MATLAB_MODULE="${MATLAB_MODULE:-MATLAB/2024b}"
module load "$MATLAB_MODULE"

if [ -n "${SLURM_SUBMIT_DIR:-}" ]; then
  cd "$SLURM_SUBMIT_DIR"
else
  cd "$(dirname "${BASH_SOURCE[0]}")/../.."
fi

validation/layer5/run_layer5.sh "$MODEL" "${PORT:-45602}" "${BASE_SEED:-20260917}"
