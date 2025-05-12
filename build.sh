#!/bin/bash

if [ "$1" = "rebuild" ] || [ ! -d "build/" ]; then
    rm -rf build
    mkdir build

    (
      cd build || exit 1
      cmake -DCMAKE_TOOLCHAIN_FILE=../toolchain.cmake -DCMAKE_BUILD_TYPE=Debug ..
    )
fi

(
  cd build || exit 1
  make -j "$(nproc)"
  cp modules/cli/cli cli
)