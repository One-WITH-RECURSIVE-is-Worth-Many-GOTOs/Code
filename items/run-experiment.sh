#!/bin/bash


INVOCATIONS=${2:-12}

PSQL_EXEC="psql"

if [ "$INVOCATIONS" -lt 1 ]; then
  echo "Invocations must be greater or equal to 1."
  exit 1
fi

echo "Running items with hierarchy depth of $ITERATIONS"

echo "Setup database for experiment:"

$PSQL_EXEC --quiet -v iterations="$ITERATIONS" \
                   -v invocations="$INVOCATIONS" \
                   -f items-preparation.sql >> /dev/null

echo -e "\n\n======================\n| Run PL/SQL version |\n======================\n"

$PSQL_EXEC -v iterations="$ITERATIONS" \
           -v invocations="$INVOCATIONS" \
           -f items-pl.sql

echo -e "\n\n======================\n| Run translation    |\n======================\n"

$PSQL_EXEC -v iterations="$ITERATIONS" \
           -v invocations="$INVOCATIONS" \
           -v MODE=RECURSIVE \
           -f items-tr.sql

