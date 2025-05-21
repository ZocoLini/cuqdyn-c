#!/bin/bash

build-proyect() {
    VARIANT=$1

    if [ ! -d "build-$VARIANT/" ]; then
      mkdir "build-$VARIANT"
    elif [ "$2" = "rebuild" ]; then
      rm -rf "build-${VARIANT}/*"
    fi

    (
      cd "build-$VARIANT" || exit 1
      cmake -DCMAKE_TOOLCHAIN_FILE=../"$VARIANT"_toolchain.cmake ..
      make -j "$(nproc)"
    )
}

variants=(
  "serial"
  "mpi"
  "mpi2"
)

if [ "$1" = "rebuild" ]; then
    for variant in "${variants[@]}"; do
      build-proyect "$variant" "rebuild" &
    done
    wait
elif ! [ "$1" = "" ]; then
    if ! [[ ${variants[*]} =~ $1 ]]; then
        echo "$1 is not a valid variant. Please use one of the following: ${variants[*]} or rebuild"
        exit 1
    else
        build-proyect "$1"
    fi
else
  for variant in "${variants[@]}"; do
    build-proyect "$variant" &
  done
  wait
fi