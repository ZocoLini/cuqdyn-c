#!/bin/bash
set -e

execute_variant() {
  variant="$1"

  BUILD_DIR="build-$variant"

  if [ ! -d "$BUILD_DIR/" ]; then
    exit 0
  fi

  rm -rf "$BUILD_DIR/tests/data/*"
  cp -r tests/data/* "$BUILD_DIR/tests/data/"

  (
    cd "$BUILD_DIR" || exit 1
    ctest
  )

}

variants=(
  "serial"
  "mpi"
  "mpi2"
)

for variant in "${variants[@]}"; do
  execute_variant "$variant" &
done

wait
