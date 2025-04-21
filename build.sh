#!/bin/bash

rm -rf build
mkdir build

(
  cd build || exit 1
  cmake -DCMAKE_BUILD_TYPE=Debug ..
  make
)