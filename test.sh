#!/bin/bash

(
  cd build || exit 1
  ctest
)