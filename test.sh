#!/bin/bash

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

      exit 0 # Disabling the cli test

      CLI_TEST_DIR="$BUILD_DIR/cli-test"

      rm -r "$CLI_TEST_DIR"
      mkdir "$CLI_TEST_DIR"

      cp "$BUILD_DIR/modules/cli/cli" "$CLI_TEST_DIR"
      cp -r "$BUILD_DIR/tests/data" "$CLI_TEST_DIR"
      cp plot.py "$CLI_TEST_DIR"

      if [ ! "$variant" = "serial" ]; then
        (
          cd "$CLI_TEST_DIR" || exit 1
          mpirun -np 6 --use-hwthread-cpus ./cli solve -c data/lotka_volterra_cuqdyn_config.xml \
            -s "data/lotka_volterra_ess_mpi_config_nl2sol.dn2gb.xml" \
            -d data/lotka_volterra_paper_data.txt \
            -o "data/output"
        )
      else
        (
          cd "$CLI_TEST_DIR" || exit 1
          ./cli solve -c data/lotka_volterra_cuqdyn_config.xml \
            -s "data/lotka_volterra_ess_serial_config_nl2sol.dn2gb.xml" \
            -d data/lotka_volterra_paper_data.txt \
            -o "data/output"
        )
      fi

      .venv/bin/python plot.py "$CLI_TEST_DIR/data/output/cuqdyn-results.txt"
}

if [ ! -d ".venv" ]; then
    if ! python3 -m venv .venv; then
        echo "Error creating python virtual environment. Install python3-venv."
        exit 1
    fi
    source .venv/bin/activate
    pip install --upgrade pip
fi

.venv/bin/pip install matplotlib

variants=(
  "serial"
  "mpi"
  "mpi2"
)

for variant in "${variants[@]}"; do
  execute_variant "$variant" &
done

wait