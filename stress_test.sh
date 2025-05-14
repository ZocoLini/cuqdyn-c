#!/bin/bash
set -e
set -u

VARIANT="$1"
TIMES=$2

for (( i = 0; i < "$TIMES"; i++ )); do
    bash test.sh "$VARIANT"
done

echo "Stress test completed successfully for variant: $VARIANT"