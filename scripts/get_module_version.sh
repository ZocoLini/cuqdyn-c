#!/bin/bash
set -euo pipefail

git fetch --tags

MODULE_NAME=$1

branch=$(git rev-parse --abbrev-ref HEAD)
version=$(git tag --sort=-creatordate | grep "^$MODULE_NAME/" | head -n 1 | sed -E 's:.*/(v[0-9]+\.[0-9]+\.[0-9]+):\1:')

if [ "$branch" = "main" ]; then
    echo "$version"
else
    if [ -n "$version" ]; then
        echo "dev-$version-$branch"
    else
        echo "dev"
    fi
fi