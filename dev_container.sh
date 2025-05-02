#!/bin/bash

if [ "$1" == "rebuild" ]; then
    rm -rf dev-container
fi

if [ ! -d "dev-container" ]; then
    if ! singularity build --sandbox dev-container/ containers/dev-container.def; then
        echo "Error building the dev-container."
        exit 1
    fi
fi

singularity shell dev-container/