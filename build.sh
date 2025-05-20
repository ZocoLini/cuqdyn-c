#!/bin/bash

build-proyect() {
    VARIANT=$1

    if [ ! -d "build-$VARIANT/" ]; then
      mkdir "build-$VARIANT"
    else
      rm -rf "build-${VARIANT}/*"
    fi

    (
      cd "build-$VARIANT" || exit 1
      cmake -DCMAKE_TOOLCHAIN_FILE=../"$VARIANT"_toolchain.cmake ..
    )
}

variants=(
  "serial"
  "mpi"
)

if [ "$1" = "rebuild" ]; then
    for variant in "${variants[@]}"; do
      build-proyect "$variant" &
    done
    wait
elif ! [ "$1" = "" ]; then
    if ! [[ ${variants[*]} =~ $1 ]]; then
        echo "$1 is not a valid variant. Please use one of the following: ${variants[*]} or rebuild"
        exit 1
    else
        build-proyect "$1"
        exit 0
    fi
fi
for variant in "${variants[@]}"; do
  if [ -d "build-$variant/" ]; then
    (
      cd "build-$variant" || exit 1
      make -j "$(nproc)"
    ) &
  fi
done

wait