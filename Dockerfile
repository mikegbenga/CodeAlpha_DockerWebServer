# syntax=docker/dockerfile:1.7
# CodeAlpha DevOps Task 4 — Web server using Docker
# Non-root NGINX (UID 101) listening on 8080, with a built-in health check.

FROM nginxinc/nginx-unprivileged:1.27-alpine

ARG BUILD_DATE=unknown
ARG VCS_REF=unknown

LABEL org.opencontainers.image.title="codealpha-docker-webserver" \
      org.opencontainers.image.description="Hardened NGINX web server - CodeAlpha DevOps Task 4" \
      org.opencontainers.image.authors="Michael Gbenga Abajemito" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.licenses="MIT"

# Replace the stock configuration with ours
USER 0
RUN rm -f /etc/nginx/conf.d/default.conf
COPY --chown=nginx:nginx nginx/nginx.conf      /etc/nginx/nginx.conf
COPY --chown=nginx:nginx nginx/conf.d/         /etc/nginx/conf.d/
COPY --chown=nginx:nginx site/                 /usr/share/nginx/html/
# Fail the build early if the config is invalid
RUN nginx -t
USER 101

EXPOSE 8080
STOPSIGNAL SIGQUIT

HEALTHCHECK --interval=15s --timeout=3s --start-period=5s --retries=3 \
  CMD ["wget", "-q", "--spider", "http://127.0.0.1:8080/healthz"]

CMD ["nginx", "-g", "daemon off;"]
