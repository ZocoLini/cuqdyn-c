# shellcheck shell=bash
# The colour palette and the container settings are read by the scripts that
# source this file, which shellcheck cannot see from here.
# shellcheck disable=SC2034

# Shared by the hooks in this directory. Source it, do not run it:
#
#   . "$(dirname "${BASH_SOURCE[0]}")/common.sh"
#
# It sets the colour palette, moves to the repository root, and defines the
# helpers both hooks need. Everything here is deliberately side-effect free
# beyond the cd, so a hook decides for itself what to print and when.

if [ -t 1 ]; then
  GREEN=$'\033[0;32m'
  YELLOW=$'\033[0;33m'
  RED=$'\033[0;31m'
  NC=$'\033[0m'
else
  GREEN=""
  YELLOW=""
  RED=""
  NC=""
fi

WORKSPACE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$WORKSPACE_ROOT" || {
  echo "${RED}Unable to change to workspace root: $WORKSPACE_ROOT${NC}"
  exit 1
}

VENDORED='^(modules/sacess|deps|CUQDyn|CUQDyn1_Plus)/'

# Every tracked file matching the extended regex $1, minus the vendored trees
owned() {
  git ls-files |
    { grep -vE "$VENDORED" || true; } |
    { grep -E "$1" || true; }
}

have() { command -v "$1" >/dev/null 2>&1; }

# The project container carries every formatter and linter the hooks need (see
# Dockerfile), and docker-compose mounts the repository at its working
# directory, so the same repo-relative paths work inside and outside.
CONTAINER=""
if have docker &&
  docker compose ps --status running --services 2>/dev/null | grep -qx cuqdyn_c; then
  CONTAINER="cuqdyn_c"
fi

DOCKER_HINT="Install it, or start the project container with 'docker compose up -d'."
