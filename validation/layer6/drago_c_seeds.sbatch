#!/bin/bash
#SBATCH --job-name=cuqdyn-layer6-c
#SBATCH --output=layer6_c_%x_%j.log
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#
# Layer 6, C side, on drago.csic.es: one model, N seeds, from the repo root.
#
#   sbatch --export=ALL,MODEL=lv2,NSEEDS=10 validation/layer6/drago_c_seeds.sbatch
#
# The environment that built the CLI must be exported (--export=ALL). Finished
# seeds are skipped, so a job can be re-launched.

set -euo pipefail

MODEL="${MODEL:?set MODEL=lv2|ap|sir|nfkb via --export}"
NSEEDS="${NSEEDS:-10}"

if [ -n "${SLURM_SUBMIT_DIR:-}" ]; then
  cd "$SLURM_SUBMIT_DIR"
else
  cd "$(dirname "${BASH_SOURCE[0]}")/../.."
fi

validation/layer6/run_c_seeds.sh "$MODEL" "$NSEEDS"
