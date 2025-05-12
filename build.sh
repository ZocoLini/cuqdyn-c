#!/bin/bash

rm -rf build
mkdir build

(
  cd build || exit 1
  cmake -DCMAKE_TOOLCHAIN_FILE=toolchain.cmake ..
  make -j $(nproc)

  cp modules/cli/cli cli
)