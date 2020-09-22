#!/bin/bash


ITERATIONS=${1:-8}
INVOCATIONS=${2:-8}

PSQL_EXEC="psql"

if [ "$ITERATIONS" -lt 1 ]; then
  echo "Iterations must be greater or equal to 1."
  exit 1
fi

if [ "$INVOCATIONS" -lt 1 ]; then
  echo "Invocations must be greater or equal to 1."
  exit 1
fi

echo "Running sight with $ITERATIONS iterations and $INVOCATIONS invocations"

echo "Setup database for experiment:"

$PSQL_EXEC --quiet -v iterations="$ITERATIONS" \
                   -v invocations="$INVOCATIONS" \
                   -f sight-preparation.sql >> /dev/null

echo -e "\n\n======================\n| Run PL/SQL version |\n======================\n"

$PSQL_EXEC -v iterations="$ITERATIONS" \
           -v invocations="$INVOCATIONS" \
           -f sight-pl.sql

echo -e "\n\n======================\n| Run translation    |\n======================\n"

$PSQL_EXEC -v iterations="$ITERATIONS" \
           -v invocations="$INVOCATIONS" \
           -v MODE=RECURSIVE \
           -f sight-tr.sql

