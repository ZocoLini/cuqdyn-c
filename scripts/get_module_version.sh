#!/bin/bash
set -euo pipefail

MODULE_NAME=$1

tag=$(git describe --tags --match "$MODULE_NAME/v*" --abbrev=0 2>/dev/null || true)
commit=$(git rev-parse --short HEAD)

if [ -z "$tag" ]; then
  version="dev-$commit"
elif [ "$(git rev-list -n 1 "$tag")" = "$(git rev-parse HEAD)" ]; then
  version="${tag#"$MODULE_NAME/"}"
else
  version="${tag#"$MODULE_NAME/"}-dev-$commit"
fi

SHARED_PATHS=(
  CMakeLists.txt
  deps.cmake
  cmake
  toolchains
  deps
  scripts/build.sh
  scripts/get_module_version.sh
)

EXTRA_PATHS=()
if [ "$MODULE_NAME" = cuqdyn-c ]; then
  EXTRA_PATHS=(modules/cuqdyn-rs)
fi

git update-index -q --refresh || true
if [ -n "$(git status --porcelain -- "modules/$MODULE_NAME" "${SHARED_PATHS[@]}" ${EXTRA_PATHS[@]+"${EXTRA_PATHS[@]}"})" ]; then
  version="$version-dirty"
fi

echo "$version"
