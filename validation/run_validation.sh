#!/bin/bash
# The single entry point of the MATLAB-vs-C validation.
#
#   validation/run_validation.sh <command> [options]
#
# Commands
#   build         configure and build with validation/ registered (the top-level
#                 CMakeLists.txt is not edited)
#   layer <1..6>  run one layer; layers 2 and 4 share one comparator
#   references    regenerate the versioned MATLAB references of layers 1-4
#                 (validation/references/), after checking that the C and the
#                 MATLAB side define the same problem
#   report        gather every report under --output_dir into REPORT.md
#
# The problem: one input directory with everything the validation needs
#   --input=DIR          holds the C side, cuqdyn.xml, sacess.xml and data.txt,
#                        and problem.conf, which says where the MATLAB side is,
#                        relative to --matlab_repo (matlab_problem=EXAMPLES/LV,
#                        plus matlab_problem_name=X when that directory holds
#                        several define_problem_*.m). The directory name names
#                        the references and the outputs.
#   --problem=lv2|ap|sir|nfkb|all   the presets: --input=validation/input_validation/<name>
#                        (default: all)
#
# Locations (the two installations are always given explicitly)
#   --c_repo=DIR         REQUIRED: where cuqdyn-c is installed (the repository)
#   --matlab_repo=DIR    REQUIRED by references and layers 5 and 6: where
#                        CUQDyn1_Plus is installed
#   --meigo=DIR          MEIGO64 (default: $MEIGO64_PATH, then
#                        <c_repo>/CUQDyn/Matlab/MEIGO64-master)
#   --matlab=EXE         MATLAB executable (default: matlab on PATH)
#   --matlab_module=NAME environment module providing MATLAB, loaded when there
#                        is no executable (clusters)
#   --python=EXE         python3 with numpy (default: $PYTHON, then python3)
#   --env=FILE           sourced first: compilers, cmake, rust
#   --build_dir=DIR      default: <c_repo>/build/release-serial
#   --output_dir=DIR     default: validation/results; never versioned
#
# Run settings
#   --seeds=N            layer 6: seeds 1..N on both sides (default 10)
#   --seed_list="3 4"    layer 6: exactly these seeds
#   --side=c|matlab|report|all   layer 6: one half only (default all)
#   --base_seed=N        layer 5: launch k is seeded N + k (default 20260917)
#   --port=N             layer 5: TCP port on 127.0.0.1 (default: a free one)
#   --budget=N           eSS evaluations, for smoke runs (default: the sacess XML's;
#                        with references it ends up in the frozen files, so only
#                        for a trial run)
#   --part=layer1|problems|all   references: the golden vectors of layer 1, the
#                        per-problem references, or both (default all)
#   RECORD_LAYER3=1      references: also record a layer-3 search for a problem
#                        that has none yet (environment variable)
#   --sbatch             submit to SLURM, one job per problem (layers 5 and 6,
#                        references)
#   --sbatch_opts="..."  extra sbatch options (partition, time, memory)
#
# Examples (C=~/cuqdyn-c, M=~/CUQDyn1_Plus)
#   validation/run_validation.sh build --c_repo=$C
#   validation/run_validation.sh layer 1 --c_repo=$C
#   validation/run_validation.sh layer 5 --c_repo=$C --matlab_repo=$M --problem=lv2 --budget=300
#   validation/run_validation.sh layer 6 --c_repo=$C --matlab_repo=$M --problem=all --sbatch \
#       --matlab_module=MATLAB/2024b
#   validation/run_validation.sh layer 5 --c_repo=$C --matlab_repo=$M --input=$HOME/lc
#       (lc/ holds cuqdyn.xml, sacess.xml, data.txt and a problem.conf with
#        matlab_problem=EXAMPLES/LinearCascade, matlab_problem_name=LinearCascade)

set -euo pipefail

VALIDATION="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$VALIDATION/run_validation.sh"

usage() {
  sed -n '2,/^set -euo/p' "$SELF" | sed -e '$d' -e 's/^# \{0,1\}//'
}

COMMAND_LINE="$0 $*"

die() {
  echo "run_validation: $*" >&2
  exit 1
}

# ---------------------------------------------------------------- options --

COMMAND=${1:-}
[ -n "$COMMAND" ] || {
  usage
  exit 1
}
shift
LAYER=""
if [ "$COMMAND" = layer ]; then
  LAYER=${1:-}
  case "$LAYER" in
  1 | 2 | 3 | 4 | 5 | 6) shift ;;
  *) die "layer needs a number from 1 to 6" ;;
  esac
fi

C_REPO=""
MATLAB_REPO=""
MEIGO=""
MATLAB_EXE=""
MATLAB_MODULE=""
ENV_FILE=""
PYTHON="${PYTHON:-python3}"
BUILD_DIR=""
OUTPUT_DIR=""
PROBLEM=""
INPUT=""
SEEDS=10
SEED_LIST=""
SIDE=all
BASE_SEED=20260917
PORT=""
BUDGET=""
PART=all
SBATCH=0
SBATCH_OPTS=""
PASS_THROUGH=()

for arg in "$@"; do
  case "$arg" in
  --c_repo=*) C_REPO="$(cd "${arg#*=}" 2>/dev/null && pwd)" || die "--c_repo: no such directory: ${arg#*=}" ;;
  --matlab_repo=*) MATLAB_REPO="${arg#*=}" ;;
  --meigo=*) MEIGO="${arg#*=}" ;;
  --matlab=*) MATLAB_EXE="${arg#*=}" ;;
  --matlab_module=*) MATLAB_MODULE="${arg#*=}" ;;
  --env=*) ENV_FILE="${arg#*=}" ;;
  --python=*) PYTHON="${arg#*=}" ;;
  --build_dir=*) BUILD_DIR="${arg#*=}" ;;
  --output_dir=*) OUTPUT_DIR="${arg#*=}" ;;
  --problem=*) PROBLEM="${arg#*=}" ;;
  --input=*) INPUT="${arg#*=}" ;;
  --seeds=*) SEEDS="${arg#*=}" ;;
  --seed_list=*) SEED_LIST="${arg#*=}" ;;
  --side=*) SIDE="${arg#*=}" ;;
  --base_seed=*) BASE_SEED="${arg#*=}" ;;
  --port=*) PORT="${arg#*=}" ;;
  --budget=*) BUDGET="${arg#*=}" ;;
  --part=*) PART="${arg#*=}" ;;
  --sbatch) SBATCH=1 ;;
  --sbatch_opts=*) SBATCH_OPTS="${arg#*=}" ;;
  -h | --help)
    usage
    exit 0
    ;;
  *) die "unknown option $arg (see --help)" ;;
  esac
  # What a SLURM job needs to run the same command for one problem.
  case "$arg" in
  --sbatch | --sbatch_opts=* | --problem=* | --seed_list=* | --side=* | --port=* | --part=*) ;;
  *) PASS_THROUGH+=("$arg") ;;
  esac
done

if [ -n "$ENV_FILE" ]; then
  [ -f "$ENV_FILE" ] || die "--env file not found: $ENV_FILE"
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

abspath() {
  # Relative paths are relative to where the script was called from.
  case "$1" in
  /*) echo "$1" ;;
  *) echo "$PWD/$1" ;;
  esac
}

# The two installations are never guessed: every command says where the C
# repository is, and the ones that run MATLAB where CUQDyn1_Plus is.
case "$COMMAND" in
-h | --help | help) ;;
*) [ -n "$C_REPO" ] || die "--c_repo=DIR is required: the directory where cuqdyn-c is installed" ;;
esac
[ -z "$MATLAB_REPO" ] || MATLAB_REPO="$(abspath "$MATLAB_REPO")"
[ -z "$INPUT" ] || INPUT="$(abspath "${INPUT%/}")"
if [ -z "$MEIGO" ]; then
  MEIGO="${MEIGO64_PATH:-$C_REPO/CUQDyn/Matlab/MEIGO64-master}"
fi
MEIGO="$(abspath "$MEIGO")"
[ -n "$BUILD_DIR" ] || BUILD_DIR="$C_REPO/build/release-serial"
BUILD_DIR="$(abspath "$BUILD_DIR")"
[ -n "$OUTPUT_DIR" ] || OUTPUT_DIR="$VALIDATION/results"
OUTPUT_DIR="$(abspath "$OUTPUT_DIR")"
BIN="$BUILD_DIR/validation"
CLI="$BUILD_DIR/modules/cli/cli"

# ------------------------------------------------------------------ helpers --

find_matlab() {
  # Sets MATLAB_EXE or returns 1. A module is only loaded when there is no
  # executable, so a MATLAB on PATH always wins.
  if [ -n "$MATLAB_EXE" ] && command -v "$MATLAB_EXE" >/dev/null 2>&1; then
    return 0
  fi
  if command -v matlab >/dev/null 2>&1; then
    MATLAB_EXE=matlab
    return 0
  fi
  if [ -n "$MATLAB_MODULE" ] && type module >/dev/null 2>&1; then
    module load "$MATLAB_MODULE" || return 1
    if command -v matlab >/dev/null 2>&1; then
      MATLAB_EXE=matlab
      return 0
    fi
  fi
  return 1
}

need_matlab() {
  [ -n "$MATLAB_REPO" ] || die "--matlab_repo=DIR is required: the directory where CUQDyn1_Plus is installed"
  [ -d "$MATLAB_REPO/src" ] || die "no CUQDyn1_Plus in $MATLAB_REPO (expected $MATLAB_REPO/src)"
  find_matlab || die "MATLAB not found: put it on PATH, or pass --matlab=EXE or --matlab_module=NAME"
}

run_matlab() {
  # run_matlab <dir to cd into> <statement> <log file>
  "$MATLAB_EXE" -batch "cd('$1'); $2" >"$3" 2>&1
}

need_binary() {
  [ -x "$1" ] || die "$(basename "$1") not built in $BUILD_DIR - run: $SELF build"
}

free_port() {
  "$PYTHON" -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])'
}

# A problem is one input directory: the three C files next to a problem.conf
# that says where the MATLAB side lives. select_problem reads it into six
# values, as absolute paths.
P_NAME="" P_CUQDYN="" P_SACESS="" P_DATA="" P_MATLAB="" P_MATLAB_NAME=""

select_problem() {
  local dir="$1" key value conf
  [ -d "$dir" ] || die "no such input directory: $dir"
  P_NAME="$(basename "$dir")"
  P_CUQDYN="$dir/cuqdyn.xml" P_SACESS="$dir/sacess.xml" P_DATA="$dir/data.txt"
  P_MATLAB="" P_MATLAB_NAME=""
  conf="$dir/problem.conf"
  [ -f "$conf" ] || die "$P_NAME: no problem.conf in $dir"
  while IFS='=' read -r key value; do
    case "$key" in
    matlab_problem)
      case "$value" in
      /*) P_MATLAB="$value" ;;
      *) [ -z "$MATLAB_REPO" ] || P_MATLAB="$MATLAB_REPO/$value" ;;
      esac
      ;;
    matlab_problem_name) P_MATLAB_NAME="$value" ;;
    '' | \#*) ;;
    *) die "$conf: unknown key $key" ;;
    esac
  done <"$conf"
}

check_c_files() {
  local f
  for f in "$P_CUQDYN" "$P_SACESS" "$P_DATA"; do
    [ -f "$f" ] || die "$P_NAME: file not found: $f"
  done
}

# write_settings <dir>: the hand-over to MATLAB and the comparators, plus, with
# --budget, a copy of the sacess XML carrying that budget (P_SACESS then points
# to the copy, so both sides get the same number).
#
# The SLURM tasks of one campaign share the directory and write the same
# content, so both files are written aside and moved into place: a reader never
# sees half a file. Failures are fatal by hand, because the layer functions run
# where "set -e" is off (run_layer || status=1).
write_settings() {
  local dir="$1" tmp
  mkdir -p "$dir"
  check_c_files
  tmp="$dir/.tmp.$$.${SLURM_ARRAY_TASK_ID:-0}"
  if [ -n "$BUDGET" ]; then
    "$PYTHON" "$VALIDATION/tools/problem_info.py" --set-budget "$BUDGET" "$P_SACESS" "$tmp.xml" ||
      die "$P_NAME: cannot set the budget in $P_SACESS"
    mv "$tmp.xml" "$dir/sacess.xml"
    P_SACESS="$dir/sacess.xml"
  fi
  "$PYTHON" "$VALIDATION/tools/problem_info.py" "$P_CUQDYN" "$P_SACESS" "$P_DATA" "$P_NAME" \
    >"$tmp.txt" || die "$P_NAME: cannot read the C side of the problem"
  {
    [ -z "$P_MATLAB" ] || echo "matlab_problem $P_MATLAB"
    [ -z "$P_MATLAB_NAME" ] || echo "matlab_problem_name $P_MATLAB_NAME"
    echo "matlab_repo $MATLAB_REPO"
    echo "meigo $MEIGO"
  } >>"$tmp.txt"
  mv "$tmp.txt" "$dir/settings.txt"
}

# write_run_info <dir>: everything needed to launch the same run again.
write_run_info() {
  local dir="$1" commit tmp
  commit="$(git -C "$C_REPO" rev-parse HEAD 2>/dev/null || echo unknown)"
  if [ -n "$(git -C "$C_REPO" status --porcelain --untracked-files=no 2>/dev/null)" ]; then
    commit="$commit (with uncommitted changes)"
  fi
  tmp="$dir/.run_info.$$.${SLURM_ARRAY_TASK_ID:-0}"
  {
    echo "command $COMMAND_LINE"
    echo "date $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host $(hostname)"
    echo "commit $commit"
    echo "matlab ${MATLAB_EXE:+$(command -v "$MATLAB_EXE")}"
    echo "layer5_base_seed $BASE_SEED"
    echo "layer5_local_solver ${CUQDYN_L5_LOCAL_SOLVER:-dhc}"
    echo "layer6_seeds ${SEED_LIST:-1..$SEEDS}"
  } >"$tmp"
  mv "$tmp" "$dir/run_info.txt"
}

need_matlab_problem() {
  [ -n "$P_MATLAB" ] || die "$P_NAME: problem.conf needs matlab_problem= (and --matlab_repo=DIR when it is relative)"
  [ -d "$P_MATLAB" ] || die "$P_NAME: MATLAB problem directory not found: $P_MATLAB"
}

problem_list() {
  # The input directories to loop over: --input, or the presets --problem names.
  local p
  if [ -n "$INPUT" ]; then
    echo "$INPUT"
  elif [ -z "$PROBLEM" ] || [ "$PROBLEM" = all ]; then
    for p in "$VALIDATION"/input_validation/*/; do
      echo "${p%/}"
    done
  else
    for p in $(echo "$PROBLEM" | tr ',' ' '); do
      echo "$VALIDATION/input_validation/$p"
    done
  fi
}

# -------------------------------------------------------------------- build --

cmd_build() {
  mkdir -p "$BUILD_DIR"
  # Configuring an existing build directory again only adds the hook.
  (
    cd "$BUILD_DIR"
    cmake -DCMAKE_TOOLCHAIN_FILE="$C_REPO/toolchains/serial_toolchain.cmake" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PROJECT_cuqdyn_INCLUDE="$VALIDATION/cmake/register.cmake" \
      "$C_REPO"
    make -j "$(nproc)"
  )
  echo "Built. Next: $SELF layer 1"
}

# ------------------------------------------------------------------- layers --

cmd_layer1() {
  local out="$OUTPUT_DIR/layer1"
  need_binary "$BIN/test_golden"
  mkdir -p "$out"
  "$BIN/test_golden" "$VALIDATION/references/golden.txt" 1e-9 | tee "$out/report.txt"
}

# The comparators exit with the number of failed checks, or 77 when the
# references they need are absent.
skip_or_status() {
  if [ "$1" = 77 ]; then
    echo "$P_NAME: no references - skipped; generate them with: $SELF references"
    return 0
  fi
  return "$1"
}

cmd_layer2_4() {
  local out="$OUTPUT_DIR/layer2_4/$P_NAME"
  need_binary "$BIN/test_baseline"
  check_c_files
  local rc=0
  mkdir -p "$out"
  "$BIN/test_baseline" "$VALIDATION" "$P_NAME" "$P_CUQDYN" "$P_DATA" | tee "$out/report.txt" || rc=$?
  skip_or_status "$rc"
}

cmd_layer3() {
  local out="$OUTPUT_DIR/layer3/$P_NAME" evals="$VALIDATION/references/${P_NAME}_evals.txt"
  need_binary "$BIN/test_cost_replay"
  check_c_files
  if [ ! -f "$evals" ]; then
    echo "$P_NAME: no recorded search ($evals) - skipped; record one with: $SELF references"
    return 0
  fi
  local rc=0
  mkdir -p "$out"
  "$BIN/test_cost_replay" "$evals" "$P_CUQDYN" "$P_DATA" | tee "$out/report.txt" || rc=$?
  skip_or_status "$rc"
}

cmd_layer5() {
  local out="$OUTPUT_DIR/layer5/$P_NAME" port c_pid
  need_binary "$BIN/pipeline_meigo"
  need_matlab
  need_matlab_problem
  rm -rf "$out"
  mkdir -p "$out/c" "$out/matlab"
  write_settings "$out"
  write_run_info "$out"
  port="${PORT:-$(free_port)}"

  echo "=== $P_NAME: C pipeline, MEIGO served by MATLAB (port $port, base seed $BASE_SEED) ==="
  CUQDYN_MEIGO_PORT="$port" CUQDYN_MEIGO_TRACE_DIR="$out/c" \
    "$BIN/pipeline_meigo" solve -c "$P_CUQDYN" -s "$P_SACESS" -d "$P_DATA" -o "$out/c/" \
    >"$out/c/run.log" 2>&1 &
  c_pid=$!
  sleep 2
  run_matlab "$VALIDATION/matlab" \
    "meigo_server('$out/settings.txt', $port, $BASE_SEED, '$out/c')" "$out/c/meigo_server.log" || {
    kill "$c_pid" 2>/dev/null || true
    die "meigo_server failed - see $out/c/meigo_server.log"
  }
  wait "$c_pid" || die "pipeline_meigo failed - see $out/c/run.log"

  echo "=== $P_NAME: MATLAB pipeline, same seeds ==="
  run_matlab "$VALIDATION/matlab" \
    "run_pipeline_cvodes('$out/settings.txt', $BASE_SEED, '$out/matlab')" "$out/matlab/run.log" ||
    die "run_pipeline_cvodes failed - see $out/matlab/run.log"

  echo "=== $P_NAME: comparison ==="
  "$PYTHON" "$VALIDATION/tools/compare_lockstep.py" "$P_NAME" --c-dir "$out/c" \
    --matlab-dir "$out/matlab" --settings "$out/settings.txt" --report "$out/report.md"
}

cmd_layer6() {
  local out="$OUTPUT_DIR/layer6/$P_NAME" seeds seed start
  seeds="${SEED_LIST:-$(seq -s ' ' 1 "$SEEDS")}"
  mkdir -p "$out/c" "$out/matlab"
  write_settings "$out"
  write_run_info "$out"

  if [ "$SIDE" = all ] || [ "$SIDE" = c ]; then
    need_binary "$CLI"
    for seed in $seeds; do
      if [ -f "$out/c/seed_$seed/cuqdyn-results.txt" ]; then
        echo "$P_NAME: C seed $seed already done, skipping"
        continue
      fi
      mkdir -p "$out/c/seed_$seed"
      echo "=== $P_NAME: C seed $seed ==="
      # Wall clock per seed, so the two sides can be compared on cost as well
      # as on results. gen_baseline.m writes the same file on its side.
      start=$(date +%s.%N)
      SACESS_SEED="$seed" "$CLI" solve -c "$P_CUQDYN" -s "$P_SACESS" -d "$P_DATA" \
        -o "$out/c/seed_$seed/" >"$out/c/seed_$seed/run.log" 2>&1 ||
        die "C seed $seed failed - see $out/c/seed_$seed/run.log"
      awk -v a="$start" -v b="$(date +%s.%N)" 'BEGIN{printf "seconds %.3f\n", b-a}' \
        >"$out/c/seed_$seed/timing.txt"
    done
  fi

  if [ "$SIDE" = all ] || [ "$SIDE" = matlab ]; then
    need_matlab
    need_matlab_problem
    echo "=== $P_NAME: MATLAB seeds $seeds ==="
    run_matlab "$VALIDATION/matlab" \
      "gen_baseline('$out/settings.txt', 6, 'Seeds', [$seeds], 'OutDir', '$out/matlab')" \
      "$out/matlab/run_$(echo "$seeds" | tr ' ' '_').log" ||
      die "the MATLAB side failed - see $out/matlab/"
  fi

  if [ "$SIDE" = all ] || [ "$SIDE" = report ]; then
    "$PYTHON" "$VALIDATION/tools/compare_baseline.py" "$P_NAME" --c-dir "$out/c" \
      --matlab-dir "$out/matlab" --report "$out/report.md"
  fi
}

run_layer() {
  case "$LAYER" in
  1) cmd_layer1 ;;
  2 | 4) cmd_layer2_4 ;;
  3) cmd_layer3 ;;
  5) cmd_layer5 ;;
  6) cmd_layer6 ;;
  esac
}

JOB_COMMAND=() JOB_TAG="" JOB_WHAT=""

# SLURM: the job runs this same script for one problem. Layer 6 becomes an
# array with one MATLAB seed per task, one job for the C seeds, and a report
# job that waits for both.
submit() {
  # submit <extra sbatch options...> -- <extra run_validation options...>
  local opts=() id log="%j"
  while [ "$1" != -- ]; do
    case "$1" in
    --array=*) log="%A_%a" ;;
    esac
    opts+=("$1")
    shift
  done
  shift
  mkdir -p "$OUTPUT_DIR/slurm"
  # shellcheck disable=SC2086
  id=$(sbatch --parsable --job-name="cuqdyn-$JOB_TAG-$JOB_WHAT" \
    --output="$OUTPUT_DIR/slurm/${JOB_TAG}_${JOB_WHAT}_$log.log" \
    --export=ALL,MATLAB_MODULE="$MATLAB_MODULE" $SBATCH_OPTS "${opts[@]}" \
    "$VALIDATION/tools/slurm_job.sh" "$SELF" "${JOB_COMMAND[@]}" "${PASS_THROUGH[@]}" \
    ${1:+"$@"})
  echo "$id"
}

submit_layer() {
  local preset="$1" sel=("--input=$1") a c r
  JOB_COMMAND=(layer "$LAYER") JOB_TAG="layer$LAYER" JOB_WHAT="$P_NAME"
  if [ "$LAYER" = 6 ]; then
    a=$(submit --array="1-$SEEDS" -- "${sel[@]}" --side=matlab --seed_list=@TASK@)
    c=$(submit -- "${sel[@]}" --side=c)
    r=$(submit --dependency="afterok:$a:$c" -- "${sel[@]}" --side=report)
    echo "$P_NAME: MATLAB seeds job $a (array), C seeds job $c, report job $r"
  else
    a=$(submit -- "${sel[@]}")
    echo "$P_NAME: job $a"
  fi
}

# --------------------------------------------------------------- references --

cmd_references() {
  local out sel a
  if [ "$SBATCH" = 1 ]; then
    JOB_COMMAND=(references) JOB_TAG=references
    if [ "$PART" != problems ]; then
      JOB_WHAT=layer1
      a=$(submit -- --part=layer1)
      echo "layer 1: job $a"
    fi
    [ "$PART" != layer1 ] || return 0
    while IFS= read -r preset; do
      select_problem "$preset"
      JOB_WHAT="$P_NAME"
      a=$(submit -- "--input=$preset" --part=problems)
      echo "$P_NAME: job $a"
    done < <(problem_list)
    return 0
  fi

  need_matlab
  mkdir -p "$OUTPUT_DIR/references"
  if [ "$PART" != problems ]; then
    echo "=== layer 1: golden vectors ==="
    run_matlab "$VALIDATION/matlab" "gen_golden('$VALIDATION/references/golden.txt', '$MATLAB_REPO')" \
      "$OUTPUT_DIR/references/layer1.log" || die "gen_golden failed - see $OUTPUT_DIR/references/layer1.log"
  fi
  [ "$PART" != layer1 ] || return 0
  while IFS= read -r preset; do
    select_problem "$preset"
    need_matlab_problem
    out="$OUTPUT_DIR/references/$P_NAME"
    write_settings "$out"
    # Both sides must describe the same problem before anything is frozen.
    echo "=== $P_NAME: do the C and the MATLAB side define the same problem? ==="
    run_matlab "$VALIDATION/matlab" \
      "n = check_problem('$out/settings.txt'); exit(min(n, 1))" "$out/check_problem.log" ||
      die "$P_NAME: the two sides differ - see $out/check_problem.log"
    grep -E '^  warning' "$out/check_problem.log" || true
    echo "=== $P_NAME: layers 2 and 4 (layer 4 is a full CUQDyn1_Plus run) ==="
    run_matlab "$VALIDATION/matlab" "gen_baseline('$out/settings.txt', [2 4])" "$out/layers_2_4.log" ||
      die "gen_baseline failed - see $out/layers_2_4.log"
    # Layer 3 replays one recorded search; it is kept for the problems that
    # already have one, a new problem gets it with RECORD_LAYER3=1.
    if [ -f "$VALIDATION/references/${P_NAME}_evals.txt" ] || [ "${RECORD_LAYER3:-0}" = 1 ]; then
      echo "=== $P_NAME: layer 3 (one recorded eSS search) ==="
      run_matlab "$VALIDATION/matlab" "gen_cost_replay('$out/settings.txt')" "$out/layer3.log" ||
        die "gen_cost_replay failed - see $out/layer3.log"
    fi
  done < <(problem_list)
  echo "References rewritten under $VALIDATION/references; review them with: git -C $C_REPO status --short validation"
}

# ------------------------------------------------------------------- report --

cmd_report() {
  local f out="$OUTPUT_DIR/REPORT.md"
  {
    echo "# cuqdyn-c validation report"
    echo
    echo "Generated $(date -u +%Y-%m-%dT%H:%MZ) from $OUTPUT_DIR"
    for f in "$OUTPUT_DIR"/layer1/report.txt "$OUTPUT_DIR"/layer2_4/*/report.txt \
      "$OUTPUT_DIR"/layer3/*/report.txt; do
      [ -f "$f" ] || continue
      echo
      echo "## ${f#"$OUTPUT_DIR"/}"
      echo
      echo '```'
      tail -n 12 "$f"
      echo '```'
    done
    for f in "$OUTPUT_DIR"/layer5/*/report.md "$OUTPUT_DIR"/layer6/*/report.md; do
      [ -f "$f" ] || continue
      echo
      echo "## ${f#"$OUTPUT_DIR"/}"
      echo
      # The per-launch tables stay in the layer's own report.
      grep -E '^(Launches|MATLAB:|C:  |Parameters in disagreement)|^\| (theta_hat|params_median|q_low|q_up|cov_p|std_y) ' "$f" || true
    done
  } >"$out"
  echo "Report written: $out"
}

# --------------------------------------------------------------------- main --

main() {
  case "$COMMAND" in
  build) cmd_build ;;
  references) cmd_references ;;
  report) cmd_report ;;
  layer)
    if [ "$LAYER" = 1 ]; then
      cmd_layer1
      exit 0
    fi
    status=0
    while IFS= read -r preset; do
      select_problem "$preset"
      if [ "$SBATCH" = 1 ]; then
        [ "$LAYER" -ge 5 ] || die "--sbatch is for layers 5 and 6; layers 1-4 take seconds"
        submit_layer "$preset"
      else
        run_layer || status=1
      fi
    done < <(problem_list)
    exit "$status"
    ;;
  -h | --help | help) usage ;;
  *) die "unknown command $COMMAND (see --help)" ;;
  esac
}

# A brace group is parsed whole: bash has read the exit before main starts, so
# editing this file while a job runs cannot break the job.
{
  main
  exit
}
