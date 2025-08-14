#!/bin/bash

if [ ! -d ./build-serial/benches ]; then
    echo "Error: serial benchmarks build directory not found."
    exit 1
fi

ISOLATED_CPUS_LIST="0-11"

(
    cd ./build-serial/benches || exit 1
    if [ -z "$1" ]; then
        for bench in bench_*; do
            taskset -c $ISOLATED_CPUS_LIST ./"$bench"
        done
    else
        taskset -c $ISOLATED_CPUS_LIST ./"$1"
    fi
)
