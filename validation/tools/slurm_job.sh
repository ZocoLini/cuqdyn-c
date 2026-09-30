#!/bin/bash
#SBATCH --time=24:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem=16G
#
# The SLURM job of run_validation.sh --sbatch: runs the command line it is
# given, which is run_validation.sh itself for one problem, with absolute
# paths. @TASK@ in an argument stands for the array task id (layer 6 runs one
# MATLAB seed per task). Resources are overridden with --sbatch_opts="...".

set -euo pipefail

if [ -n "${MATLAB_MODULE:-}" ]; then
  module load "$MATLAB_MODULE"
fi

args=()
for arg in "$@"; do
  args+=("${arg//@TASK@/${SLURM_ARRAY_TASK_ID:-}}")
done
exec "${args[@]}"
