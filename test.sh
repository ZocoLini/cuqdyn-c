#!/bin/bash

bash build.sh

if [ $? -ne 0 ]; then
    echo "Build failed"
    exit 1
fi

(
  cd build || exit 1
  ctest
)