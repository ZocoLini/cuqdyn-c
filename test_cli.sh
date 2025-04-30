#!/bin/bash

CLI_TEST_DIR=build/cli-test

rm -r "$CLI_TEST_DIR"
mkdir "$CLI_TEST_DIR"

cp build/modules/cli/cli "$CLI_TEST_DIR"
cp -r build/tests/data "$CLI_TEST_DIR"
cp plot.py "$CLI_TEST_DIR"

(
  cd "$CLI_TEST_DIR" || exit 1
  ./cli solve -c data/lotka_volterra_cuqdyn_config.xml \
    -s data/lotka_volterra_ess_config.xml \
    -d data/lotka_volterra_paper_data.txt \
    -o data/output \
    -f 0
  python3 plot.py test/test_data/cli_test_output.txt
)