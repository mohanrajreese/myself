#!/usr/bin/env bash
# Applies every migration to a throwaway local PostgreSQL cluster and runs the
# RLS checks. Needs PostgreSQL server binaries (initdb, pg_ctl) and psql.
# Usage: bash supabase/tests/run_local.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
bin="$(dirname "$(command -v initdb || ls /usr/lib/postgresql/*/bin/initdb | tail -n 1)")"
work="$(mktemp -d)"
port=54329
run() { if [ "$(id -u)" = 0 ]; then su postgres -c "$*"; else bash -c "$*"; fi; }

[ "$(id -u)" = 0 ] && chown postgres "$work"
trap 'run "$bin/pg_ctl -D $work/data -m immediate stop" >/dev/null 2>&1 || true; rm -rf "$work"' EXIT

run "$bin/initdb -D $work/data -U postgres -A trust" >/dev/null
run "$bin/pg_ctl -D $work/data -o '-p $port -c listen_addresses=localhost -k $work' -w start" >/dev/null

psql_() { psql -h localhost -p "$port" -U postgres -v ON_ERROR_STOP=1 -q "$@"; }
psql_ -f "$here/local/00_supabase_shim.sql"
for migration in "$here"/../migrations/*.sql; do
  psql_ -f "$migration"
done
psql_ -f "$here/rls_checks.sql" 2>&1 | grep -E "ok -|FAILED|ERROR|ALL CHECKS"
