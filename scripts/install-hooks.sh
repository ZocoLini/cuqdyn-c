#!/bin/bash
set -euo pipefail

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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$SCRIPT_DIR/.."

cd "$WORKSPACE_ROOT" || {
  echo "${RED}Unable to change to workspace root: $WORKSPACE_ROOT${NC}"
  exit 1
}

if [ ! -d .githooks ]; then
  echo "${RED}.githooks/ not found${NC}"
  exit 1
fi

git config core.hooksPath .githooks
chmod +x .githooks/*

echo ""
echo "${GREEN}Hooks enabled: core.hooksPath -> .githooks${NC}"
echo "  The staged files are formatted before every commit, push and more."
echo "  Run the hooks by hand at any time with: .githooks/<script>.sh"
echo ""

# Nothing to install by hand: the container image carries every formatter, and
# the hook reaches for it on its own whenever one is missing locally.
echo "${YELLOW}Start the project container and the hook will use its formatters:${NC}"
echo "  docker compose up -d"
echo ""
