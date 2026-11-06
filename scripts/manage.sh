#!/usr/bin/env bash
# Container lifecycle manager for the CodeAlpha web server (plain docker CLI).
#
#   ./scripts/manage.sh <command>
#
# Lifecycle:   build | run | start | stop | restart | pause | unpause | rm | clean
# Operations:  status | health | logs | stats | inspect | exec | top | events
# Testing:     test  | crash-test
set -euo pipefail

IMAGE="${IMAGE:-codealpha/webserver}"
TAG="${TAG:-latest}"
NAME="${NAME:-codealpha-web}"
HOST_PORT="${HOST_PORT:-8080}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

c_blue='\033[1;34m'; c_green='\033[1;32m'; c_red='\033[1;31m'; c_off='\033[0m'
say()  { printf "${c_blue}==>${c_off} %s\n" "$*"; }
ok()   { printf "${c_green}✔${c_off} %s\n" "$*"; }
fail() { printf "${c_red}✖${c_off} %s\n" "$*" >&2; exit 1; }

exists()  { docker container inspect "$NAME" >/dev/null 2>&1; }
running() { [ "$(docker container inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" = "true" ]; }

wait_healthy() {
  say "Waiting for $NAME to become healthy…"
  for _ in $(seq 1 30); do
    state=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$NAME" 2>/dev/null || echo missing)
    case "$state" in
      healthy)   ok "healthy"; return 0 ;;
      unhealthy) docker logs --tail 30 "$NAME"; fail "container is unhealthy" ;;
    esac
    sleep 1
  done
  fail "timed out waiting for health (last state: $state)"
}

cmd_build() {
  say "Building $IMAGE:$TAG"
  docker build \
    --build-arg BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --build-arg VCS_REF="$(git -C "$ROOT" rev-parse --short HEAD 2>/dev/null || echo local)" \
    -t "$IMAGE:$TAG" "$ROOT"
  docker image ls "$IMAGE:$TAG"
}

cmd_run() {
  exists && fail "$NAME already exists. Use 'restart' or 'rm' first."
  say "Running $NAME on http://localhost:$HOST_PORT"
  docker run -d \
    --name "$NAME" \
    -p "$HOST_PORT:8080" \
    --restart unless-stopped \
    --read-only --tmpfs /tmp:size=16m \
    --cap-drop ALL --security-opt no-new-privileges:true \
    --memory 128m --cpus 0.5 \
    --log-opt max-size=10m --log-opt max-file=3 \
    "$IMAGE:$TAG" >/dev/null
  wait_healthy
}

cmd_start()   { docker start "$NAME" >/dev/null && wait_healthy; }
cmd_stop()    { say "Graceful stop (SIGQUIT, 10s timeout)"; docker stop -t 10 "$NAME"; }
cmd_restart() { docker restart "$NAME" >/dev/null && wait_healthy; }
cmd_pause()   { docker pause "$NAME" && ok "paused (processes frozen)"; }
cmd_unpause() { docker unpause "$NAME" && ok "resumed"; }
cmd_rm()      { if docker rm -f "$NAME" >/dev/null 2>&1; then ok "removed $NAME"; else ok "$NAME not present"; fi; }
cmd_clean()   { cmd_rm; docker image rm "$IMAGE:$TAG" 2>/dev/null || true; docker image prune -f >/dev/null; ok "cleaned"; }

cmd_status() {
  docker ps -a --filter "name=^/${NAME}$" \
    --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.RunningFor}}'
  exists && docker inspect -f 'Restarts: {{.RestartCount}}  OOMKilled: {{.State.OOMKilled}}  ExitCode: {{.State.ExitCode}}' "$NAME"
}

cmd_health() {
  exists || fail "$NAME does not exist"
  docker inspect -f '{{.State.Health.Status}} (failing streak: {{.State.Health.FailingStreak}})' "$NAME"
  say "Last probe results"
  docker inspect -f '{{range .State.Health.Log}}{{.Start.Format "15:04:05"}}  exit={{.ExitCode}}  {{.Output}}{{"\n"}}{{end}}' "$NAME" | tail -5
  say "HTTP check"
  curl -fsS "http://localhost:$HOST_PORT/healthz" && echo
}

cmd_logs()    { docker logs -f --tail "${LINES:-50}" "$NAME"; }
cmd_stats()   { docker stats --no-stream "$NAME"; }
cmd_inspect() { docker inspect "$NAME" | ${JQ:-cat}; }
cmd_exec()    { docker exec -it "$NAME" sh; }
cmd_top()     { docker top "$NAME"; }
cmd_events()  { docker events --filter "container=$NAME"; }

cmd_test() {
  running || fail "$NAME is not running"
  local base="http://localhost:$HOST_PORT" pass=0 total=0
  check() { # url expected_status description
    total=$((total+1))
    code=$(curl -s -o /dev/null -w '%{http_code}' "$base$1")
    if [ "$code" = "$2" ]; then ok "$3 ($1 → $code)"; pass=$((pass+1)); else printf "${c_red}✖${c_off} %s (%s → %s, wanted %s)\n" "$3" "$1" "$code" "$2"; fi
  }
  check /                 200 "home page"
  check /healthz          200 "health endpoint"
  check /assets/style.css 200 "static asset"
  check /missing-page     404 "custom 404"
  check /.env             404 "hidden files blocked"
  total=$((total+1))
  if curl -sI "$base/" | grep -qi '^x-frame-options: DENY'; then ok "security headers"; pass=$((pass+1)); else echo "✖ security headers"; fi
  total=$((total+1))
  if docker exec "$NAME" sh -c 'touch /usr/share/nginx/html/x' 2>/dev/null; then echo "✖ root fs is writable"; else ok "read-only root filesystem"; pass=$((pass+1)); fi
  total=$((total+1))
  if [ "$(docker exec "$NAME" id -u)" != "0" ]; then ok "runs as non-root (uid $(docker exec "$NAME" id -u))"; pass=$((pass+1)); else echo "✖ running as root"; fi
  echo
  if [ "$pass" = "$total" ]; then ok "$pass/$total checks passed"; else fail "$pass/$total checks passed"; fi
}

cmd_crash_test() {
  running || fail "$NAME is not running"
  local before; before=$(docker inspect -f '{{.RestartCount}}' "$NAME")
  say "Stopping the NGINX master process (PID 1) from inside the container to simulate a crash…"
  # PID 1 ignores SIGKILL sent from inside its own namespace, so ask nginx itself to exit.
  docker exec "$NAME" nginx -s stop || true
  sleep 3
  local after; after=$(docker inspect -f '{{.RestartCount}}' "$NAME")
  if [ "$after" -gt "$before" ]; then ok "restart policy recovered the container (restarts: $before → $after)"; else fail "container was not restarted"; fi
  wait_healthy
}

usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

case "${1:-}" in
  build|run|start|stop|restart|pause|unpause|rm|clean|status|health|logs|stats|inspect|exec|top|events|test)
    "cmd_$1" ;;
  crash-test) cmd_crash_test ;;
  *) usage; exit 1 ;;
esac
