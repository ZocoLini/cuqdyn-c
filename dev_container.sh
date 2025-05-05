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

if [ ! -d ".venv" ]; then
    if ! python3 -m venv .venv; then
        echo "Error creating python virtual environment. Installing python3-venv."
        sudo apt install python3-venv
        python3 -m venv .venv
    fi
    source .venv/bin/activate
    pip install --upgrade pip
fi

singularity shell dev-container/