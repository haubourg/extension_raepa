#!/usr/bin/env bash

GNUGETOPT="getopt"
if [[ "$OSTYPE" =~ FreeBSD* ]] || [[ "$OSTYPE" =~ darwin* ]]; then
  GNUGETOPT="/usr/local/bin/getopt"
elif [[ "$OSTYPE" =~ openbsd* ]]; then
  GNUGETOPT="gnugetopt"
fi

# Exit on error
set -e

usage() {
cat << EOF
Usage: $0 [options]

-p|--pgservice       PG service to connect to the database.
-s|--srid            PostGIS SRID. Default to 2154 (Lambert93)
-d|--drop-schema     Drop schema (cascaded) if it exists
EOF
}

ARGS=$(${GNUGETOPT} -o p:s:d -l "pgservice:,srid:,drop-schema" -- "$@");
if [[ $? -ne 0 ]]
then
  usage
  exit 1
fi

eval set -- "$ARGS";

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Default values
SRID=2154
DROPSCHEMA=0

while true; do
  case "$1" in
    -p|--pgservice)
      shift
      if [[ -n "$1" ]]
      then
        PGSERVICE=$1
        shift
      fi
      ;;
    -s|--srid)
      shift;
      if [[ -n "$1" ]]; then
        SRID=$1
        shift;
      fi
      ;;
    -d|--drop-schema)
      DROPSCHEMA=1
      shift;
      ;;
    --)
      shift
      break
      ;;
  esac
done

if [[ -z $PGSERVICE ]]
then
  echo "Error: no PG service provided; either use -p or set the PGSERVICE environment variable."
  exit 1
fi

if [[ "$DROPSCHEMA" -eq 1 ]]; then
	psql service=${PGSERVICE} -v ON_ERROR_STOP=1 \
         -c "DROP SCHEMA IF EXISTS raepa CASCADE"
fi

# create the raepa schema
psql service=$PGSERVICE -v ON_ERROR_STOP=1 -c "CREATE SCHEMA IF NOT EXISTS raepa"

# add the raepa columns
psql service=$PGSERVICE -v ON_ERROR_STOP=1 -v SRID=$SRID -f ${DIR}/raepa_columns.sql

# re-create the QWAT views, for the new raepa columns to be taken into account
QWAT_REPO="$(git rev-parse --show-toplevel)"
PGSERVICE=${PGSERVICE} SRID=${SRID} ${QWAT_REPO}/ordinary_data/views/rewrite_views.sh

# create the raepa views
PGSERVICE=${PGSERVICE} SRID=${SRID} ${DIR}/insert_views.sh

exit 0
