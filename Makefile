# Makefile for nzbgetvpn development

IMAGE_NAME ?= nzbgetvpn
CONTAINER_NAME ?= nzbgetvpn-dev

# Attempt to read PRIVOXY_PORT from .env file, default to 8118 if not found or .env is missing
# This ensures PRIVOXY_HOST_PORT aligns with the internal PRIVOXY_PORT set in .env
PRIVOXY_PORT_FROM_ENV := $(shell if [ -f .env ]; then grep '^PRIVOXY_PORT=' .env | cut -d= -f2; fi)
PRIVOXY_HOST_PORT ?= $(PRIVOXY_PORT_FROM_ENV)
PRIVOXY_HOST_PORT ?= 8118 # Fallback if not in .env or .env doesn't exist

.PHONY: all build test run logs stop clean help

all: help

help:
	@echo "nzbgetvpn Development Makefile"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Development targets:"
	@echo "  build              Build the Docker image locally"
	@echo "  test               Run basic tests on the built image"
	@echo "  run                Run container for testing (requires .env)"
	@echo "  logs               Follow container logs"
	@echo "  stop               Stop and remove container"
	@echo "  clean              Clean up containers and images"
	@echo ""
	@echo "For normal usage, see README.md Quick Start section"

build:
	@echo "Building Docker image: $(IMAGE_NAME)"
	docker build -t $(IMAGE_NAME) .

test: build
	@echo "Testing image: $(IMAGE_NAME)"
	@docker run --rm $(IMAGE_NAME) python3 --version
	@docker run --rm $(IMAGE_NAME) openvpn --version | head -1
	@docker run --rm $(IMAGE_NAME) wg --version
	@echo "✅ Basic tests passed"

run:
	@if [ ! -f .env ]; then \
		echo "❌ .env file not found. Copy .env.sample to .env and configure it first."; \
		exit 1; \
	fi
	@echo "Running development container: $(CONTAINER_NAME)"
	@mkdir -p config downloads
	docker run -d \
		--name $(CONTAINER_NAME) \
		--cap-add=NET_ADMIN \
		--device=/dev/net/tun \
		-p 6789:6789 \
		-p 8080:8080 \
		-v $(PWD)/config:/config \
		-v $(PWD)/downloads:/downloads \
		--env-file .env \
		$(IMAGE_NAME)
	@echo "✅ Container started. Access NZBGet at http://localhost:6789"

logs:
	@docker logs -f $(CONTAINER_NAME)

stop:
	@echo "Stopping container: $(CONTAINER_NAME)"
	@docker stop $(CONTAINER_NAME) 2>/dev/null || true
	@docker rm -f $(CONTAINER_NAME) 2>/dev/null || true

clean: stop
	@echo "Cleaning up..."
	@docker system prune -f
	@echo "✅ Cleanup complete"
