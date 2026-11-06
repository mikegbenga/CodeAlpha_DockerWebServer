.PHONY: help build run test health logs stats stop restart crash-test clean up down monitor lint

help:            ## Show targets
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build:           ## Build the image
	./scripts/manage.sh build
run:             ## Run the container (docker run)
	./scripts/manage.sh run
test:            ## Run functional + security checks against the running container
	./scripts/manage.sh test
health:          ## Show health status and probe history
	./scripts/manage.sh health
logs:            ## Follow logs
	./scripts/manage.sh logs
stats:           ## CPU / memory snapshot
	./scripts/manage.sh stats
stop:            ## Graceful stop
	./scripts/manage.sh stop
restart:         ## Restart and wait for healthy
	./scripts/manage.sh restart
crash-test:      ## Kill the server and verify the restart policy
	./scripts/manage.sh crash-test
clean:           ## Remove container and image
	./scripts/manage.sh clean

up:              ## docker compose up (web only)
	docker compose up -d --build
monitor:         ## docker compose up with exporter + Prometheus
	docker compose --profile monitoring up -d --build
down:            ## docker compose down
	docker compose --profile monitoring down

lint:            ## Lint Dockerfile + shell scripts
	docker run --rm -i hadolint/hadolint < Dockerfile
	shellcheck scripts/*.sh
