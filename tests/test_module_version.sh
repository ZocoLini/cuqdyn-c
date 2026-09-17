#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT=$ROOT/scripts/get_module_version.sh

REPO=$(mktemp -d)
trap 'rm -rf "$REPO"' EXIT

FAILURES=0

version() { (cd "$REPO" && bash "$SCRIPT" "$1"); }

check() {
  local name=$1 expected=$2 actual=$3

  if [ "$expected" = "$actual" ]; then
    echo "ok       $name"
  else
    echo "FAILED   $name: expected '$expected', got '$actual'"
    FAILURES=$((FAILURES + 1))
  fi
}

check_all() {
  local name=$1 sacess=$2 cuqdyn=$3 cli=$4

  check "$name (sacess)" "$sacess" "$(version sacess)"
  check "$name (cuqdyn-c)" "$cuqdyn" "$(version cuqdyn-c)"
  check "$name (cli)" "$cli" "$(version cli)"
}

short() { (cd "$REPO" && git rev-parse --short HEAD); }

CLOCK=1700000000

commit() {
  CLOCK=$((CLOCK + 60))
  GIT_AUTHOR_DATE="@$CLOCK +0000" GIT_COMMITTER_DATE="@$CLOCK +0000" \
    git commit -q "$@"
}

tag() {
  CLOCK=$((CLOCK + 60))
  GIT_COMMITTER_DATE="@$CLOCK +0000" git tag "$@"
}

cd "$REPO"
git init -q .
git config user.email test@example.com
git config user.name "test"

mkdir -p modules/sacess modules/cuqdyn-c modules/cli modules/cuqdyn-rs
mkdir -p toolchains deps cmake scripts
for path in modules/sacess/src.c modules/cuqdyn-c/src.c modules/cli/src.c \
  modules/cuqdyn-rs/lib.rs toolchains/serial_toolchain.cmake deps/libfoo.a \
  cmake/module_version.cmake scripts/build.sh CMakeLists.txt deps.cmake; do
  echo "content" >"$path"
done
git add -A
commit -m "initial"
tag sacess/v1.0.0
tag cuqdyn-c/v2.0.0
tag cli/v3.0.0

echo "--- the tagged commit, nothing modified ---"
check_all "clean" v1.0.0 v2.0.0 v3.0.0

echo "--- a modified file belongs to one module only ---"
echo more >>modules/sacess/src.c
check_all "sacess modified" v1.0.0-dirty v2.0.0 v3.0.0
git checkout -q modules/sacess/src.c

echo "--- so does a file that was never added ---"
touch modules/cli/untracked.c
check_all "cli untracked" v1.0.0 v2.0.0 v3.0.0-dirty
rm modules/cli/untracked.c

echo "--- the rust library is built into cuqdyn-c, so it counts as its own ---"
echo more >>modules/cuqdyn-rs/lib.rs
check_all "cuqdyn-rs modified" v1.0.0 v2.0.0-dirty v3.0.0
git checkout -q modules/cuqdyn-rs/lib.rs

echo "--- what every module compiles against dirties every module ---"
for shared in toolchains/serial_toolchain.cmake deps/libfoo.a \
  cmake/module_version.cmake scripts/build.sh CMakeLists.txt deps.cmake; do
  echo more >>"$shared"
  check_all "$shared modified" v1.0.0-dirty v2.0.0-dirty v3.0.0-dirty
  git checkout -q "$shared"
done

echo "--- anything else dirties nobody ---"
echo more >NOTES.md
check_all "unrelated file" v1.0.0 v2.0.0 v3.0.0
rm NOTES.md

echo "--- off the tagged commit, the commit is named ---"
echo more >>modules/sacess/src.c
commit -am "second"
check_all "past the tag" "v1.0.0-dev-$(short)" "v2.0.0-dev-$(short)" "v3.0.0-dev-$(short)"

echo "--- and both marks can show up together ---"
echo more >>modules/sacess/src.c
check "past the tag and dirty" "v1.0.0-dev-$(short)-dirty" "$(version sacess)"
git checkout -q modules/sacess/src.c

echo "--- a module with no tag of its own has no release to name ---"
check "untagged module" "dev-$(short)" "$(version benches)"

echo "--- an annotated tag reads the same as a lightweight one ---"
tag -a sacess/v1.1.0 -m "release"
check "annotated tag" v1.1.0 "$(version sacess)"

echo "--- a tag on a branch that was never merged is not this build's ---"
git checkout -q -b unmerged
echo more >>modules/sacess/src.c
commit -am "on a branch"
tag sacess/v9.9.9
git checkout -q -
check "unreachable tag ignored" v1.1.0 "$(version sacess)"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All version cases passed."
else
  echo "$FAILURES version case(s) failed."
fi

exit $((FAILURES > 0))
