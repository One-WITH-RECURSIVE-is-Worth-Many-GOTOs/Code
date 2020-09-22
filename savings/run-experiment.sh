#!/bin/bash


INVOCATIONS=${1:-1024}

PSQL_EXEC="psql"

if [ "$INVOCATIONS" -lt 1 ]; then
  echo "Invocations must be greater or equal to 1."
  exit 1
fi

echo "Running savings with $INVOCATIONS invocations"

echo "Setup database for experiment:"

$PSQL_EXEC --quiet -v invocations="$INVOCATIONS" \
                   -f savings-preparation.sql >> /dev/null

echo -e "\n\n======================\n| Run PL/SQL version |\n======================\n"

$PSQL_EXEC -v invocations="$INVOCATIONS" \
           -f savings-pl.sql

echo -e "\n\n======================\n| Run translation    |\n======================\n"

$PSQL_EXEC -v invocations="$INVOCATIONS" \
           -v MODE=RECURSIVE \
           -f savings-tr.sql

