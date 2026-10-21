#!/usr/bin/env bash
# Start the whole EMR single-sign-on stack at once, as host processes.
#
# There is now a containerised alternative that needs no host MariaDB, no host
# bench and no per-app `npm run dev`:
#     docker compose up -d        # see DOCKER.md
# The two cannot run at the same time — they want the same ports. Pick one.

# Idempotent: anything already listening on its port is left alone.
# Logs for the host processes go to ./.run-logs/.
set -u

EMR="/home/amir/code/EMR"
LOGS="$EMR/.run-logs"
mkdir -p "$LOGS"

# True when something is already listening on the given TCP port.
port_up() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# start_if_free <port> <name> <dir> <command> <logfile>
start_if_free() {
  local port="$1" name="$2" dir="$3" cmd="$4" log="$5"
  if port_up "$port"; then
    echo "  [$name] already up on :$port — skipping"
  else
    echo "  [$name] starting on :$port  (log: $log)"
    ( cd "$dir" && nohup bash -lc "$cmd" >"$log" 2>&1 & )
  fi
}

echo "== Docker stacks =="
echo "  [AuthService] up (:4000)"
( cd "$EMR/Aerem_Auth_Service" && docker compose up -d >/dev/null )
echo "  [New EMR] up (emr_node :8000 + Basecamp :3001)"
( cd "$EMR/new--emr" && docker compose -f docker-compose.dev.yml up -d >/dev/null )

echo "== Host processes =="
start_if_free 8002 "Frappe demo bench" "$EMR/demo-bench"              "bench start"   "$LOGS/demo-bench.log"
start_if_free 5001 "DC backend"        "$EMR/DC/EMR_Catalog_Backend" "npm start"     "$LOGS/dc-backend.log"
start_if_free 3000 "CRM frontend"      "$EMR/CRM/crm-frontend"       "npm run dev"   "$LOGS/crm.log"
start_if_free 3003 "PD frontend"       "$EMR/PD/Basecamp_Frontend"   "npm run dev"   "$LOGS/pd.log"
start_if_free 3002 "DC web frontend"   "$EMR/DC/digital-catalog/apps/web" "npm run dev" "$LOGS/dc-web.log"

cat <<EOF

== Started. Give it ~30-60s, then open: ==
  AuthService admin  http://localhost:4000/admin
  Frappe desk        http://demo.localhost:8002
  New EMR            http://localhost:3001
  Digital catalog    http://localhost:3002
  CRM                http://localhost:3000
  PD                 http://localhost:3003

Backends: emr_node :8000, DC catalog :5001.
Host logs: $LOGS/   (tail -f any of them to watch startup)
EOF
