#!/bin/bash

build-proyect() {
    VARIANT=$1

    if [ ! -d "build-$VARIANT/" ]; then
        mkdir "build-$VARIANT"
    fi

    rm -rf "build-${VARIANT}/*"

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
    build-proyect "mpi" &
    build-proyect "serial" &
    wait
else 
    if ! [[ ${variants[*]} =~ $1 ]]; then
        echo "$1 is not a valid variant. Please use one of the following: ${variants[*]} or rebuild"
        exit 1
    else
        build-proyect "$1"
        exit 0
    fi
fi

for variant in "${variants[@]}"; do
  if [ ! -d "build-$variant/" ]; then
    build-proyect "$variant" &
  fi
done

wait

for variant in "${variants[@]}"; do
  (
    cd "build-$variant" || exit 1
    make -j "$(nproc)"
    cp modules/cli/cli cli
  ) &
done