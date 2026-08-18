#!/bin/bash

if [ -d ".venv" ]; then
  exit 0
fi

if ! python3 -m venv .venv; then
  echo "Error creating python virtual environment. Install python3-venv."
  exit 1
fi

# Created just above, so it cannot be followed at lint time.
# shellcheck source=/dev/null
source .venv/bin/activate
pip install --upgrade pip
pip install matplotlib
