#!/bin/bash

if [ ! -d "build/" ]; then
    bash build.sh
fi

(
  cd build || exit 1
  ctest
)