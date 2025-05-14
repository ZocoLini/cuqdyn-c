#!/bin/bash

execute_variant() {
  variant="$1"

  BUILD_DIR="build-$variant"

      if [ ! -d "$BUILD_DIR/" ]; then
          bash build.sh "$variant"
      fi

      rm -rf "$BUILD_DIR/tests/data/*"
      cp -r tests/data/* "$BUILD_DIR/tests/data/"

      (
        cd "$BUILD_DIR" || exit 1
        ctest
      )

      CLI_TEST_DIR="$BUILD_DIR/cli-test"

      rm -r "$CLI_TEST_DIR"
      mkdir "$CLI_TEST_DIR"

      cp "$BUILD_DIR/modules/cli/cli" "$CLI_TEST_DIR"
      cp -r "$BUILD_DIR/tests/data" "$CLI_TEST_DIR"
      cp plot.py "$CLI_TEST_DIR"

      if [ "$variant" = "mpi" ]; then
        (
          cd "$CLI_TEST_DIR" || exit 1
          mpirun -np 6 --use-hwthread-cpus ./cli solve -c data/lotka_volterra_cuqdyn_config.xml \
            -s "data/lotka_volterra_ess_${variant}_config_nl2sol.dn2gb.xml" \
            -d data/lotka_volterra_paper_data.txt \
            -o "data/output" \
            -f 0
        )
      else
        (
          cd "$CLI_TEST_DIR" || exit 1
          ./cli solve -c data/lotka_volterra_cuqdyn_config.xml \
            -s "data/lotka_volterra_ess_${variant}_config_nl2sol.dn2gb.xml" \
            -d data/lotka_volterra_paper_data.txt \
            -o "data/output" \
            -f 0
        )
      fi

      .venv/bin/python plot.py "$CLI_TEST_DIR/data/output/cuqdyn-results.txt"
}

bash build.sh "$1"

if [ ! -d ".venv" ]; then
    if ! python3 -m venv .venv; then
        echo "Error creating python virtual environment. Installing python3-venv."
        sudo apt install python3-venv
        python3 -m venv .venv
    fi
    source .venv/bin/activate
    pip install --upgrade pip
fi

.venv/bin/pip install matplotlib

variants=(
  "serial"
  "mpi"
)

if [[ " ${variants[*]} " =~ " $1 " ]]; then
  execute_variant "$1"
  exit 0
fi

for variant in "${variants[@]}"; do
  execute_variant "$variant" &
done

wait