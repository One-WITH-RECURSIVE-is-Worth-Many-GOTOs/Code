#!/bin/bash


INVOCATIONS=${1:-4096}

PSQL_EXEC="psql"

if [ "$INVOCATIONS" -lt 1 ]; then
  echo "Invocations must be greater or equal to 1."
  exit 1
fi

echo "Running late with $INVOCATIONS invocations"

echo -e "\n\n======================\n| Run PL/SQL version |\n======================\n"

$PSQL_EXEC -v invocations="$INVOCATIONS" \
           -f late-pl.sql

echo -e "\n\n======================\n| Run translation    |\n======================\n"

$PSQL_EXEC -v invocations="$INVOCATIONS" \
           -v MODE=RECURSIVE \
           -f late-tr.sql
