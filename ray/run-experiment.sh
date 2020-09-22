#!/bin/bash


ITERATIONS=${1:-32}
INVOCATIONS=${2:-32}

PSQL_EXEC="psql"

if [ "$ITERATIONS" -lt 1 ]; then
  echo "Iterations must be greater or equal to 1."
  exit 1
fi

if [ "$INVOCATIONS" -lt 1 ]; then
  echo "Invocations must be greater or equal to 1."
  exit 1
fi

echo "Running ray with $ITERATIONS iterations and $INVOCATIONS invocations"

echo "Setup database for experiment:"

$PSQL_EXEC --quiet -v iterations="$ITERATIONS" \
                   -v invocations="$INVOCATIONS" \
                   -f ray-preparation.sql >> /dev/null

echo -e "\n\n======================\n| Run PL/SQL version |\n======================\n"

$PSQL_EXEC -v iterations="$ITERATIONS" \
           -v invocations="$INVOCATIONS" \
           -f ray-pl.sql

echo -e "\n\n======================\n| Run translation    |\n======================\n"

$PSQL_EXEC -v iterations="$ITERATIONS" \
           -v invocations="$INVOCATIONS" \
           -v MODE=RECURSIVE \
           -f ray-tr.sql

