#
# Graph Studio Server (Anzo) triplestore support via Docker.
# See https://docs.cambridgesemantics.com/anzo/
#
ifndef _MK_GRAPHSTUDIO_MK_
_MK_GRAPHSTUDIO_MK_ := 1

#$(info ---> .make/graphstudio.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

#
# Auto-detect graphstudio-* targets and enable Graph Studio support.
# This allows `gmake graphstudio-serve` to work even when EKG_VARIANT=oxigraph in .env.
#
ifneq ($(filter graphstudio-%,$(MAKECMDGOALS)),)
USE_GRAPHSTUDIO := 1
EKG_VARIANT := graphstudio
endif

#
# Graph Studio support is disabled by default.
# Set USE_GRAPHSTUDIO=1 to enable Graph Studio functionality.
#
ifeq ($(USE_GRAPHSTUDIO),1)

include $(MK_DIR)/triplestore-docker.mk
include $(MK_DIR)/dotenvage.mk
include $(MK_DIR)/rdf-http-load.mk

# Ensure DOTENVAGE_BIN is available.
ifndef DOTENVAGE_BIN
DOTENVAGE_BIN := $(shell command -v dotenvage 2>/dev/null)
endif
ifndef DOTENVAGE_BIN
$(error dotenvage is not installed. Run: cargo binstall dotenvage)
endif

# Get EKG_AGE_KEY from dotenvage (it's filtered from dump for security)
EKG_AGE_KEY ?= $(shell $(DOTENVAGE_BIN) get EKG_AGE_KEY 2>/dev/null)

GRAPHSTUDIO_PORT ?= 8443
GRAPHSTUDIO_IMAGE_NAME ?= graphstudio-local
GRAPHSTUDIO_DOCKERFILE ?= $(GIT_ROOT)/Dockerfile.graphstudio

# SPARQL endpoints for Graph Studio.
# All endpoint URLs and auth keys come from dotenvage (.env files).
# Fallback defaults only apply when dotenvage hasn't set them.
EKG_SPARQL_HEALTH_ENDPOINT ?= http://localhost:$(GRAPHSTUDIO_PORT)/anzo/status
EKG_SPARQL_QUERY_ENDPOINT ?= http://localhost:$(GRAPHSTUDIO_PORT)/sparql
EKG_SPARQL_UPDATE_ENDPOINT ?= http://localhost:$(GRAPHSTUDIO_PORT)/sparql
EKG_SPARQL_STORE_ENDPOINT ?= http://localhost:$(GRAPHSTUDIO_PORT)/sparql

# Container and volume names derived from triplestore-docker.mk
GRAPHSTUDIO_CONTAINER_NAME = $(TRIPLESTORE_CONTAINER_NAME)
GRAPHSTUDIO_VOLUME_NAME = $(TRIPLESTORE_VOLUME_NAME)

#
# Preflight check delegates to shared docker-daemon-check
#
.PHONY: graphstudio-check
graphstudio-check: docker-daemon-check

# Determine which environment to build for (local by default for development)
GRAPHSTUDIO_BUILD_ENV ?= local

# Stamp file tracks when the Docker image was last built.
GRAPHSTUDIO_IMAGE_STAMP := $(GIT_ROOT)/.tmp/graphstudio-image.stamp

# Files that affect the Docker image content
GRAPHSTUDIO_BUILD_SOURCES := \
	$(GRAPHSTUDIO_DOCKERFILE) \
	$(GIT_ROOT)/graphstudio/response.varfile \
	$(GIT_ROOT)/.env.$(GRAPHSTUDIO_BUILD_ENV).graphstudio

#
# Build the Graph Studio Docker image (skips if image is up-to-date).
#
$(GRAPHSTUDIO_IMAGE_STAMP): $(GRAPHSTUDIO_BUILD_SOURCES) | $(TMP_DIR) graphstudio-check
	@printf "$(bold)Building Graph Studio Docker image for $(GRAPHSTUDIO_BUILD_ENV)...$(normal)\n"
	$(DOCKER_CMD) build --load -t $(GRAPHSTUDIO_IMAGE_NAME) \
		--build-arg EKG_ENV=$(GRAPHSTUDIO_BUILD_ENV) \
		-f $(GRAPHSTUDIO_DOCKERFILE) $(GIT_ROOT)
	@touch $@

.PHONY: graphstudio-build
graphstudio-build: $(GRAPHSTUDIO_IMAGE_STAMP)

#
# Run Graph Studio in a Docker container with a named volume.
# License and config are baked into image; EKG_AGE_KEY decrypts at runtime.
#
.PHONY: graphstudio-serve
graphstudio-serve: triplestore-volume-ensure $(GRAPHSTUDIO_IMAGE_STAMP)
	@printf "$(bold)Starting Graph Studio on port $(GRAPHSTUDIO_PORT)...$(normal)\n"
	@printf "  Container: $(GRAPHSTUDIO_CONTAINER_NAME)\n"
	@printf "  Volume:    $(GRAPHSTUDIO_VOLUME_NAME)\n"
	@printf "  Instance:  $(TRIPLESTORE_INSTANCE)\n"
	@# Stop existing container if running
	@$(DOCKER_CMD) stop $(GRAPHSTUDIO_CONTAINER_NAME) 2>/dev/null || true
	@$(DOCKER_CMD) rm $(GRAPHSTUDIO_CONTAINER_NAME) 2>/dev/null || true
	@# Run new container - dotenvage inside decrypts .env files using EKG_AGE_KEY
	$(DOCKER_CMD) run \
		--name $(GRAPHSTUDIO_CONTAINER_NAME) \
		-p $(GRAPHSTUDIO_PORT):8080 \
		-v $(GRAPHSTUDIO_VOLUME_NAME):/opt/graphstudio-data \
		-e EKG_AGE_KEY="$(EKG_AGE_KEY)" \
		$(GRAPHSTUDIO_IMAGE_NAME)

#
# Run Graph Studio in background (detached mode)
#
.PHONY: graphstudio-serve-detached
graphstudio-serve-detached: triplestore-volume-ensure $(GRAPHSTUDIO_IMAGE_STAMP)
	@printf "$(bold)Starting Graph Studio in background on port $(GRAPHSTUDIO_PORT)...$(normal)\n"
	@printf "  Container: $(GRAPHSTUDIO_CONTAINER_NAME)\n"
	@printf "  Volume:    $(GRAPHSTUDIO_VOLUME_NAME)\n"
	@printf "  Instance:  $(TRIPLESTORE_INSTANCE)\n"
	@# Stop existing container if running
	@$(DOCKER_CMD) stop $(GRAPHSTUDIO_CONTAINER_NAME) 2>/dev/null || true
	@$(DOCKER_CMD) rm $(GRAPHSTUDIO_CONTAINER_NAME) 2>/dev/null || true
	@# Run new container
	$(DOCKER_CMD) run -d \
		--name $(GRAPHSTUDIO_CONTAINER_NAME) \
		-p $(GRAPHSTUDIO_PORT):8080 \
		-v $(GRAPHSTUDIO_VOLUME_NAME):/opt/graphstudio-data \
		-e EKG_AGE_KEY="$(EKG_AGE_KEY)" \
		$(GRAPHSTUDIO_IMAGE_NAME)
	@printf "$(green)Graph Studio started. Access at http://localhost:$(GRAPHSTUDIO_PORT)$(normal)\n"
	@printf "Use 'gmake graphstudio-logs' to view logs\n"
	@printf "Use 'gmake graphstudio-stop' to stop the container\n"

#
# View Graph Studio logs
#
.PHONY: graphstudio-logs
graphstudio-logs:
	$(DOCKER_CMD) logs -f $(GRAPHSTUDIO_CONTAINER_NAME)

#
# Stop the Graph Studio container
#
.PHONY: graphstudio-stop
graphstudio-stop:
	@printf "$(bold)Stopping Graph Studio...$(normal)\n"
	@$(DOCKER_CMD) stop $(GRAPHSTUDIO_CONTAINER_NAME) 2>/dev/null || true
	@printf "$(green)Graph Studio stopped$(normal)\n"

#
# Kill and remove the Graph Studio container
#
.PHONY: graphstudio-kill
graphstudio-kill:
	@printf "$(bold)Killing Graph Studio container...$(normal)\n"
	@$(DOCKER_CMD) kill $(GRAPHSTUDIO_CONTAINER_NAME) 2>/dev/null || true
	@$(DOCKER_CMD) rm $(GRAPHSTUDIO_CONTAINER_NAME) 2>/dev/null || true

#
# Delete the Graph Studio Docker volume
#
.PHONY: graphstudio-delete-database
graphstudio-delete-database: graphstudio-kill
	@$(DOCKER_CMD) volume rm $(GRAPHSTUDIO_VOLUME_NAME) 2>/dev/null \
		&& printf "$(green)Graph Studio volume $(GRAPHSTUDIO_VOLUME_NAME) deleted$(normal)\n" \
		|| printf "No Graph Studio volume $(GRAPHSTUDIO_VOLUME_NAME) to delete\n"

#
# Clean everything (stop container, delete volume, remove image stamp)
#
.PHONY: graphstudio-clean
graphstudio-clean: graphstudio-kill graphstudio-delete-database
	@rm -f $(GRAPHSTUDIO_IMAGE_STAMP)
	@printf "$(green)Graph Studio cleaned$(normal)\n"

#
# Wait for Graph Studio to be ready
#
.PHONY: graphstudio-wait
graphstudio-wait:
	@printf "Waiting for Graph Studio to be ready...\n"
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 43 44 45; do \
		if curl -sf "http://localhost:$(GRAPHSTUDIO_PORT)/anzo/status" >/dev/null 2>&1; then \
			echo "Graph Studio is ready"; \
			exit 0; \
		fi; \
		echo "Waiting... ($$i/45)"; \
		sleep 4; \
	done; \
	echo "Graph Studio failed to start"; \
	exit 1

#
# Show Graph Studio status
#
.PHONY: graphstudio-status
graphstudio-status:
	@if $(DOCKER_CMD) ps --filter "name=$(GRAPHSTUDIO_CONTAINER_NAME)" --format "{{.Names}}" | grep -q $(GRAPHSTUDIO_CONTAINER_NAME); then \
		echo "Graph Studio container is running"; \
		echo "  Container:  $(GRAPHSTUDIO_CONTAINER_NAME)"; \
		echo "  Volume:     $(GRAPHSTUDIO_VOLUME_NAME)"; \
		echo "  Instance:   $(TRIPLESTORE_INSTANCE)"; \
		echo "  Port:       $(GRAPHSTUDIO_PORT)"; \
		echo "  URL:        http://localhost:$(GRAPHSTUDIO_PORT)"; \
		echo "  SPARQL:     http://localhost:$(GRAPHSTUDIO_PORT)/sparql"; \
	else \
		echo "Graph Studio container is not running"; \
	fi

#
# HTTP load: loads to running Graph Studio server via rdf-loader (incremental, hash-based)
#
.PHONY: graphstudio-http-load
graphstudio-http-load:
	@pnpm exec rdf-loader --graphstudio load

.PHONY: graphstudio-http-load-flags-delete
graphstudio-http-load-flags-delete: rdf-http-load-flags-delete

.PHONY: graphstudio-http-reload
graphstudio-http-reload:
	@pnpm exec rdf-loader --graphstudio load --force

#
# Load alias (uses HTTP load)
#
.PHONY: graphstudio-load
graphstudio-load: graphstudio-http-load

endif # USE_GRAPHSTUDIO

#$(info <--- .make/graphstudio.mk)

endif # _MK_GRAPHSTUDIO_MK_
