# Troubleshooting runbook

Start with these three commands. They answer most questions:

```bash
./scripts/manage.sh status    # is it running? restart count? OOMKilled? exit code?
./scripts/manage.sh health    # health state + last probe outputs
docker logs --tail 50 codealpha-web
```

| Symptom | Likely cause | Fix |
|---|---|---|
| `Bind for 0.0.0.0:8080 failed: port is already allocated` | Another process or container is using 8080 | `HOST_PORT=8081 ./scripts/manage.sh run` or `docker ps --filter publish=8080` |
| Container exits right away, exit code 1 | Invalid NGINX config | `docker run --rm codealpha/webserver nginx -t`; the build also runs `nginx -t` |
| `mkdir() "/var/cache/nginx/…" failed (30: Read-only file system)` | A temp path isn't on the tmpfs | Keep the `*_temp_path /tmp/...` lines in `nginx.conf` and the `--tmpfs /tmp` mount |
| `bind() to 0.0.0.0:80 failed (13: Permission denied)` | A non-root user can't bind ports below 1024 | Listen on 8080 inside the container and map `-p 80:8080` |
| `socket() [::]:8080 failed (97: Address family not supported)` | The host has IPv6 disabled | Leave out the `listen [::]:8080` line (already left out here) |
| Health `starting` forever | The probe can't reach `/healthz` | `docker exec codealpha-web wget -qO- http://127.0.0.1:8080/healthz` |
| Health `unhealthy` | Server hung or overloaded | `manage.sh stats` (memory near the limit?), `docker logs`, then `manage.sh restart` |
| `OOMKilled: true` | Memory limit hit | Raise `--memory` / `deploy.resources.limits.memory`; check `worker_connections` |
| 403 on `/nginx_status` | Request comes from a public IP | Expected: only private ranges are allowed. Scrape from the compose network |
| Exporter shows `nginx_up 0` | The exporter started before the web server or is on another network | Both services must be on `frontend`, with `depends_on: service_healthy` |
| Changes to HTML don't show | The old image is still running | `./scripts/manage.sh rm && ./scripts/manage.sh build && ./scripts/manage.sh run` (or `docker compose up -d --build`) |
| Disk filling up | Container logs | Log rotation is set (`max-size 10m`, `max-file 3`); `docker system df` |

## Useful one-liners

```bash
docker inspect -f '{{.State.Health.Status}}' codealpha-web
docker inspect -f '{{range .State.Health.Log}}{{.ExitCode}} {{.Output}}{{end}}' codealpha-web
docker logs codealpha-web 2>&1 | grep '"status":5'          # 5xx responses from the JSON logs
docker exec codealpha-web nginx -T | less                     # full effective config
docker exec codealpha-web nginx -s reload                     # reload config without downtime
docker events --since 30m --filter container=codealpha-web    # what happened recently
```
