#!/usr/bin/env bash
# Lightweight health watchdog: polls container health + HTTP status, logs to
# a file and restarts the container after N consecutive failures.
#
#   ./scripts/health-monitor.sh            # foreground
#   INTERVAL=10 MAX_FAILS=3 ./scripts/health-monitor.sh &
set -uo pipefail

NAME="${NAME:-codealpha-web}"
URL="${URL:-http://localhost:${HOST_PORT:-8080}/healthz}"
INTERVAL="${INTERVAL:-10}"
MAX_FAILS="${MAX_FAILS:-3}"
LOG="${LOG:-./health-monitor.log}"

fails=0
log() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

log "monitor started for $NAME ($URL every ${INTERVAL}s, restart after $MAX_FAILS failures)"
while true; do
  docker_state=$(docker inspect -f '{{.State.Status}}/{{if .State.Health}}{{.State.Health.Status}}{{else}}n/a{{end}}' "$NAME" 2>/dev/null || echo "missing/n/a")
  http_code=$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$URL" || echo 000)
  mem=$(docker stats --no-stream --format '{{.MemUsage}} cpu={{.CPUPerc}}' "$NAME" 2>/dev/null || echo "-")

  if [ "$http_code" = "200" ] && [[ "$docker_state" == running/healthy* ]]; then
    [ "$fails" -gt 0 ] && log "RECOVERED state=$docker_state http=$http_code"
    fails=0
    log "OK state=$docker_state http=$http_code $mem"
  else
    fails=$((fails+1))
    log "FAIL ($fails/$MAX_FAILS) state=$docker_state http=$http_code"
    if [ "$fails" -ge "$MAX_FAILS" ]; then
      log "ACTION restarting $NAME; last logs:"
      docker logs --tail 20 "$NAME" 2>&1 | sed 's/^/    /' | tee -a "$LOG"
      docker restart "$NAME" >/dev/null 2>&1 || log "restart failed"
      fails=0
    fi
  fi
  sleep "$INTERVAL"
done
