# CodeAlpha_DockerWebServer — Web Server using Docker

**CodeAlpha DevOps Internship · Task 4** — Michael Gbenga Abajemito (Student ID: CA/DF1/326280)

A production-style **NGINX web server running in Docker**. It is non-root, read-only and resource-limited, and it
checks its own health. It ships with a lifecycle CLI, a self-healing crash test, JSON logs and Prometheus monitoring.

```
 browser ──► :8080 ──► ┌──────────────── codealpha-web (nginx-unprivileged:alpine, uid 101) ─────────────┐
                       │  /            static site          HEALTHCHECK → /healthz every 15s             │
                       │  /healthz     JSON health probe    restart: unless-stopped                      │
                       │  /nginx_status stub_status ───────►│ read-only FS · cap_drop ALL · 128 MB / 0.5 CPU │
                       └──────────────────────────────────┬─────────────────────────────────────────────┘
                                                          │ (profile: monitoring)
                              nginx-prometheus-exporter :9113 ──► Prometheus :9090 (+ alert rules)
```

## How each requirement is covered

| Requirement | Where |
|---|---|
| Docker containerization basics | [`Dockerfile`](Dockerfile): pinned base, OCI labels, `nginx -t` at build time, non-root, `HEALTHCHECK`, `STOPSIGNAL` |
| Deploy & manage a web server in containers | [`docker-compose.yml`](docker-compose.yml) and [`scripts/manage.sh`](scripts/manage.sh) (`docker run` with the same hardening flags) |
| Container lifecycle & commands | `manage.sh build/run/start/stop/restart/pause/unpause/rm/clean`, explained in [docs/LIFECYCLE.md](docs/LIFECYCLE.md) |
| Monitor health & troubleshoot | Health checks, `manage.sh health/stats/logs/events`, [`health-monitor.sh`](scripts/health-monitor.sh) watchdog, Prometheus + alerts, [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) |
| Deployment best practices | Read-only rootfs, dropped capabilities, no-new-privileges, limits, log rotation, security headers, rate limiting, CI with hadolint + Trivy ([`.github/workflows/docker-ci.yml`](.github/workflows/docker-ci.yml)) |

## Quick start

```bash
# Option A: docker compose
docker compose up -d --build
open http://localhost:8080

# Option B: plain docker via the lifecycle script
./scripts/manage.sh build
./scripts/manage.sh run        # waits until the container reports healthy
./scripts/manage.sh test       # 8 functional + security checks
./scripts/manage.sh crash-test # stops the server and checks the restart policy brings it back

# With monitoring (exporter + Prometheus on :9090)
docker compose --profile monitoring up -d --build
```

On Windows, run the scripts from **Git Bash** or **WSL**, or use the `docker compose` commands directly in PowerShell.

## Endpoints

| Path | Purpose |
|---|---|
| `/` | Static site (shows live health from the browser) |
| `/healthz` | `{"status":"ok","server":"nginx"}`, used by Docker `HEALTHCHECK` |
| `/nginx_status` | NGINX `stub_status` (private networks only) for the Prometheus exporter |
| anything else | Custom 404 page; hidden files such as `/.env` and `/.git` are blocked |

## Project layout

```
├── Dockerfile
├── docker-compose.yml
├── nginx/nginx.conf            JSON logs, gzip, temp paths in /tmp, rate-limit zone
├── nginx/conf.d/site.conf      server block, security headers, /healthz, /nginx_status, caching
├── site/                       index, 404, 50x, assets
├── scripts/manage.sh           lifecycle + test CLI
├── scripts/health-monitor.sh   watchdog with auto-restart
├── monitoring/                 prometheus.yml + alerts.yml
├── docs/LIFECYCLE.md           container lifecycle & commands
├── docs/TROUBLESHOOTING.md     runbook
└── .github/workflows/          CI: hadolint, shellcheck, build, run, test, crash-test, Trivy
```

## License
MIT
