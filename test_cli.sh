#!/bin/bash

CLI_TEST_DIR=build/cli-test

if [ ! -d "build/" ]; then
    bash build.sh
fi

if [ ! -d ".venv" ]; then
    if ! python3 -m venv .venv; then
        echo "Error creating python virtual environment. Installing python3-venv."
        sudo apt install python3-venv
        python3 -m venv .venv
    fi
    source .venv/bin/activate
    pip install --upgrade pip
fi

rm -r "$CLI_TEST_DIR"
mkdir "$CLI_TEST_DIR"

cp build/modules/cli/cli "$CLI_TEST_DIR"
cp -r build/tests/data "$CLI_TEST_DIR"
cp plot.py "$CLI_TEST_DIR"

(
  cd "$CLI_TEST_DIR" || exit 1
  ./cli solve -c data/lotka_volterra_cuqdyn_config.xml \
    -s data/lotka_volterra_ess_config_nl2sol.dn2gb.xml \
    -d data/lotka_volterra_paper_data.txt \
    -o data/output \
    -f 0
)

.venv/bin/pip install matplotlib
.venv/bin/python plot.py "$CLI_TEST_DIR/data/output/cuqdyn-results.txt"