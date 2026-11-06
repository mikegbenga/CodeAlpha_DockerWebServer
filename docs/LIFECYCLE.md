# Container lifecycle & commands

```
           docker create / run
 (image) ───────────────────────►  created ──start──► running ◄──unpause── paused
                                                         │  ▲      pause ───►
                                                   stop/kill │ restart / restart-policy
                                                         ▼  │
                                                       exited ──rm──► (gone)
```

| Stage | Command (raw Docker) | `manage.sh` | What happens |
|---|---|---|---|
| Build | `docker build -t codealpha/webserver .` | `build` | Layers are cached; `nginx -t` fails the build if the config is broken |
| Create + start | `docker run -d --name codealpha-web -p 8080:8080 …` | `run` | Starts the container with hardening flags, then waits for `healthy` |
| Inspect state | `docker ps -a`, `docker inspect codealpha-web` | `status`, `inspect` | Status, restart count, OOMKilled, exit code |
| Health | `docker inspect -f '{{json .State.Health}}' codealpha-web` | `health` | `starting → healthy / unhealthy`, last 5 probe results |
| Logs | `docker logs -f --tail 50 codealpha-web` | `logs` | JSON access log on stdout, errors on stderr |
| Resources | `docker stats --no-stream codealpha-web` | `stats` | CPU %, memory against the 128 MiB limit, network I/O |
| Processes | `docker top codealpha-web` | `top` | NGINX master (PID 1) + workers |
| Shell | `docker exec -it codealpha-web sh` | `exec` | Debug inside the container |
| Pause | `docker pause` / `docker unpause` | `pause` / `unpause` | Freezes processes (cgroup freezer); the port stays bound |
| Stop | `docker stop -t 10 codealpha-web` | `stop` | Sends `SIGQUIT` (graceful NGINX shutdown), then SIGKILL after 10 s |
| Restart | `docker restart codealpha-web` | `restart` | stop + start |
| Remove | `docker rm -f codealpha-web` | `rm` | Deletes the container (the image stays) |
| Clean | `docker image rm …; docker image prune -f` | `clean` | Removes the image and dangling layers |
| Events | `docker events --filter container=codealpha-web` | `events` | Live stream of start/die/health_status events |

## Restart policies

| Policy | Behaviour |
|---|---|
| `no` | Never restart (the default) |
| `on-failure[:N]` | Restart only on a non-zero exit, optionally up to N times |
| `always` | Always restart, even after a manual stop once the daemon restarts |
| **`unless-stopped`** (used here) | Like `always`, but stays stopped after a manual `docker stop` |

`./scripts/manage.sh crash-test` stops PID 1 from inside the container. You'll see the `RestartCount` go up
and the health go back to `healthy`.

## Health check

```dockerfile
HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "--spider", "http://127.0.0.1:8080/healthz"]
```
* `start-period`: failures in the first 5 s don't count.
* After 3 consecutive failures the state becomes `unhealthy`. Compose `depends_on: condition: service_healthy`
  holds back the exporter until then. Note that Docker alone does **not** restart unhealthy containers;
  `scripts/health-monitor.sh` (or an orchestrator such as Swarm or Kubernetes) handles that.
