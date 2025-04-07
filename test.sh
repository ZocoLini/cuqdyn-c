#!/bin/bash

bash build.sh

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

TEST_BINS=(
  test_matlab
  test_sundials_ode
)

(
  cd build/tests || exit 1
  for test_bin in "${TEST_BINS[@]}"; do
    echo "Running $test_bin"
    ./"$test_bin"
    if [ $? -ne 0 ]; then
      echo "$test_bin failed"
      exit 1
    fi
  done

  echo "All tests passed"
)