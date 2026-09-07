#!/bin/bash
set -euo pipefail

if [ -t 1 ]; then
  YELLOW=$'\033[0;33m'
  RED=$'\033[0;31m'
  NC=$'\033[0m'
else
  YELLOW=""
  RED=""
  NC=""
fi

VARIANTS=(serial mpi)
BUILD_TYPE=debug
REBUILD=0
TARGETS=()

usage() {
  cat <<EOF
Usage: scripts/build.sh [variant...] [debug|release] [rebuild]

  variant   ${VARIANTS[*]}, defaults to all of them
  debug     no optimisation, debug symbols, assertions on. The default
  release   optimised, assertions off
  rebuild   discard the existing build directory first

Builds land in build/<type>-<variant>, for instance build/debug-serial.
EOF
}

for arg in "$@"; do
  case "$arg" in
  debug | release) BUILD_TYPE=$arg ;;
  rebuild) REBUILD=1 ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    # shellcheck disable=SC2076
    if [[ " ${VARIANTS[*]} " =~ " $arg " ]]; then
      TARGETS+=("$arg")
    else
      echo "${RED}Unknown argument: $arg${NC}"
      usage
      exit 1
    fi
    ;;
  esac
done

[ ${#TARGETS[@]} -eq 0 ] && TARGETS=("${VARIANTS[@]}")

# The toolchains hardcode -O3 in CMAKE_C_FLAGS, and cmake emits the per-config
# flags after those, so -O0 here wins on the command line. -UNDEBUG keeps
# assertions alive whatever the toolchain said.
if [ "$BUILD_TYPE" = debug ]; then
  CMAKE_TYPE_ARGS=(
    -DCMAKE_BUILD_TYPE=Debug
    -DCMAKE_C_FLAGS_DEBUG="-O0 -g -UNDEBUG"
    -DCMAKE_CXX_FLAGS_DEBUG="-O0 -g -UNDEBUG"
    -DCMAKE_Fortran_FLAGS_DEBUG="-O0 -g"
  )
  echo ""
  echo "${YELLOW}Building in DEBUG: no optimisation, debug symbols, assertions on.${NC}"
  echo "${YELLOW}Runs will be markedly slower. Use 'scripts/build.sh release' for an${NC}"
  echo "${YELLOW}optimised build.${NC}"
  echo ""
else
  CMAKE_TYPE_ARGS=(-DCMAKE_BUILD_TYPE=Release)
fi

# One directory per build type and variant, so switching between debug and
# release does not throw the other one away.
build_variant() {
  local variant=$1
  local dir="build/$BUILD_TYPE-$variant"

  if [ "$REBUILD" = 1 ]; then
    rm -rf "$dir"
  fi
  mkdir -p "$dir"

  (
    cd "$dir" || exit 1
    if [ ! -f CMakeCache.txt ] || [ ! -f Makefile ]; then
      cmake -DCMAKE_TOOLCHAIN_FILE=../../toolchains/"$variant"_toolchain.cmake \
        "${CMAKE_TYPE_ARGS[@]}" ../..
    fi
    make -j "$(nproc)"
  )
}

export CI_JOB_ID=1
export CI_JOB_STARTED_AT=1

if [ -d "/home/cesga" ]; then
  module load cesga/2025 gcc/system openmpi/5.0.7 rust/1.88.0
fi

pids=()
for variant in "${TARGETS[@]}"; do
  build_variant "$variant" &
  pids+=($!)
done

status=0
for pid in "${pids[@]}"; do
  wait "$pid" || status=1
done

exit "$status"
