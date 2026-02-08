#
# GraphDB triplestore support via Docker.
# See https://graphdb.ontotext.com/
#
ifndef _MK_GRAPHDB_MK_
_MK_GRAPHDB_MK_ := 1

#$(info ---> .make/graphdb.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

#
# Auto-detect graphdb-* targets and enable GraphDB support.
# This allows `gmake graphdb-serve` to work even when EKG_VARIANT=oxigraph in .env.
#
ifneq ($(filter graphdb-%,$(MAKECMDGOALS)),)
USE_GRAPHDB := 1
EKG_VARIANT := graphdb
endif

#
# GraphDB support is disabled by default.
# Set USE_GRAPHDB=1 to enable GraphDB functionality.
#
ifeq ($(USE_GRAPHDB),1)

include $(MK_DIR)/triplestore-docker.mk
include $(MK_DIR)/dotenvage.mk
include $(MK_DIR)/rdf-http-load.mk

# Ensure DOTENVAGE_BIN is available.
# When dotenvage.mk is included early (before os.mk defines where-is-binary),
# DOTENVAGE_BIN may be empty. Fall back to a direct PATH lookup.
ifndef DOTENVAGE_BIN
DOTENVAGE_BIN := $(shell command -v dotenvage 2>/dev/null)
endif
ifndef DOTENVAGE_BIN
$(error dotenvage is not installed. Run: cargo binstall dotenvage)
endif

# Get EKG_AGE_KEY from dotenvage (it's filtered from dump for security)
# This reads it from .env.local or the key file
EKG_AGE_KEY ?= $(shell $(DOTENVAGE_BIN) get EKG_AGE_KEY 2>/dev/null)

GRAPHDB_PORT ?= 7200
GRAPHDB_IMAGE_NAME ?= graphdb-local
GRAPHDB_DOCKERFILE ?= $(GIT_ROOT)/Dockerfile.graphdb
GRAPHDB_REPO_NAME ?= ekg

# SPARQL endpoints for GraphDB.
# All endpoint URLs and auth keys come from dotenvage (.env files).
# Fallback defaults only apply when dotenvage hasn't set them.
EKG_SPARQL_HEALTH_ENDPOINT ?= http://localhost:$(GRAPHDB_PORT)/rest/repositories
EKG_SPARQL_QUERY_ENDPOINT ?= http://localhost:$(GRAPHDB_PORT)/repositories/$(GRAPHDB_REPO_NAME)
EKG_SPARQL_UPDATE_ENDPOINT ?= http://localhost:$(GRAPHDB_PORT)/repositories/$(GRAPHDB_REPO_NAME)/statements
EKG_SPARQL_STORE_ENDPOINT ?= http://localhost:$(GRAPHDB_PORT)/repositories/$(GRAPHDB_REPO_NAME)/rdf-graphs/service

# Container and volume names derived from triplestore-docker.mk
GRAPHDB_CONTAINER_NAME = $(TRIPLESTORE_CONTAINER_NAME)
GRAPHDB_VOLUME_NAME = $(TRIPLESTORE_VOLUME_NAME)

#
# Preflight check delegates to shared docker-daemon-check
#
.PHONY: graphdb-check
graphdb-check: docker-daemon-check

# Determine which environment to build for (local by default for development)
GRAPHDB_BUILD_ENV ?= local

# Stamp file tracks when the Docker image was last built.
# Make's dependency system rebuilds only when sources are newer.
# Stored in .tmp/ alongside other temporary build artifacts.
GRAPHDB_IMAGE_STAMP := $(GIT_ROOT)/.tmp/graphdb-image.stamp

# Files that affect the Docker image content
GRAPHDB_BUILD_SOURCES := \
	$(GRAPHDB_DOCKERFILE) \
	$(GIT_ROOT)/graphdb/repo-config.ttl \
	$(GIT_ROOT)/.env.$(GRAPHDB_BUILD_ENV).graphdb

#
# Build the GraphDB Docker image (skips if image is up-to-date).
# The stamp file makes this a proper Make dependency: graphdb-serve
# depends on the stamp, the stamp depends on the build sources.
# Uses EKG_ENV build arg to determine which .env file to bake in.
#
$(GRAPHDB_IMAGE_STAMP): $(GRAPHDB_BUILD_SOURCES) | $(TMP_DIR) graphdb-check
	@printf "$(bold)Building GraphDB Docker image for $(GRAPHDB_BUILD_ENV)...$(normal)\n"
	$(DOCKER_CMD) build --load -t $(GRAPHDB_IMAGE_NAME) \
		--build-arg EKG_ENV=$(GRAPHDB_BUILD_ENV) \
		-f $(GRAPHDB_DOCKERFILE) $(GIT_ROOT)
	@touch $@

.PHONY: graphdb-build
graphdb-build: $(GRAPHDB_IMAGE_STAMP)

#
# Run GraphDB in a Docker container with a named volume.
# License and config are baked into image; EKG_AGE_KEY decrypts at runtime.
#
.PHONY: graphdb-serve
graphdb-serve: triplestore-volume-ensure $(GRAPHDB_IMAGE_STAMP)
	@printf "$(bold)Starting GraphDB on port $(GRAPHDB_PORT)...$(normal)\n"
	@printf "  Container: $(GRAPHDB_CONTAINER_NAME)\n"
	@printf "  Volume:    $(GRAPHDB_VOLUME_NAME)\n"
	@printf "  Instance:  $(TRIPLESTORE_INSTANCE)\n"
	@# Stop existing container if running
	@$(DOCKER_CMD) stop $(GRAPHDB_CONTAINER_NAME) 2>/dev/null || true
	@$(DOCKER_CMD) rm $(GRAPHDB_CONTAINER_NAME) 2>/dev/null || true
	@# Run new container - dotenvage inside decrypts .env files using EKG_AGE_KEY
	$(DOCKER_CMD) run \
		--name $(GRAPHDB_CONTAINER_NAME) \
		-p $(GRAPHDB_PORT):7200 \
		-v $(GRAPHDB_VOLUME_NAME):/opt/graphdb/data \
		-e EKG_AGE_KEY="$(EKG_AGE_KEY)" \
		$(GRAPHDB_IMAGE_NAME)

#
# Run GraphDB in background (detached mode)
# License and config are baked into image; EKG_AGE_KEY decrypts at runtime
#
.PHONY: graphdb-serve-detached
graphdb-serve-detached: triplestore-volume-ensure $(GRAPHDB_IMAGE_STAMP)
	@printf "$(bold)Starting GraphDB in background on port $(GRAPHDB_PORT)...$(normal)\n"
	@printf "  Container: $(GRAPHDB_CONTAINER_NAME)\n"
	@printf "  Volume:    $(GRAPHDB_VOLUME_NAME)\n"
	@printf "  Instance:  $(TRIPLESTORE_INSTANCE)\n"
	@# Stop existing container if running
	@$(DOCKER_CMD) stop $(GRAPHDB_CONTAINER_NAME) 2>/dev/null || true
	@$(DOCKER_CMD) rm $(GRAPHDB_CONTAINER_NAME) 2>/dev/null || true
	@# Run new container - dotenvage inside decrypts .env files using EKG_AGE_KEY
	$(DOCKER_CMD) run -d \
		--name $(GRAPHDB_CONTAINER_NAME) \
		-p $(GRAPHDB_PORT):7200 \
		-v $(GRAPHDB_VOLUME_NAME):/opt/graphdb/data \
		-e EKG_AGE_KEY="$(EKG_AGE_KEY)" \
		$(GRAPHDB_IMAGE_NAME)
	@printf "$(green)GraphDB started. Access at http://localhost:$(GRAPHDB_PORT)$(normal)\n"
	@printf "Use 'gmake graphdb-logs' to view logs\n"
	@printf "Use 'gmake graphdb-stop' to stop the container\n"

#
# View GraphDB logs
#
.PHONY: graphdb-logs
graphdb-logs:
	$(DOCKER_CMD) logs -f $(GRAPHDB_CONTAINER_NAME)

#
# Stop the GraphDB container
#
.PHONY: graphdb-stop
graphdb-stop:
	@printf "$(bold)Stopping GraphDB...$(normal)\n"
	@$(DOCKER_CMD) stop $(GRAPHDB_CONTAINER_NAME) 2>/dev/null || true
	@printf "$(green)GraphDB stopped$(normal)\n"

#
# Kill and remove the GraphDB container
#
.PHONY: graphdb-kill
graphdb-kill:
	@printf "$(bold)Killing GraphDB container...$(normal)\n"
	@$(DOCKER_CMD) kill $(GRAPHDB_CONTAINER_NAME) 2>/dev/null || true
	@$(DOCKER_CMD) rm $(GRAPHDB_CONTAINER_NAME) 2>/dev/null || true

#
# Delete the GraphDB Docker volume
#
.PHONY: graphdb-delete-database
graphdb-delete-database: graphdb-kill
	@$(DOCKER_CMD) volume rm $(GRAPHDB_VOLUME_NAME) 2>/dev/null \
		&& printf "$(green)GraphDB volume $(GRAPHDB_VOLUME_NAME) deleted$(normal)\n" \
		|| printf "No GraphDB volume $(GRAPHDB_VOLUME_NAME) to delete\n"

#
# Clean everything (stop container, delete volume, remove image stamp)
#
.PHONY: graphdb-clean
graphdb-clean: graphdb-kill graphdb-delete-database
	@rm -f $(GRAPHDB_IMAGE_STAMP)
	@printf "$(green)GraphDB cleaned$(normal)\n"

#
# Wait for GraphDB to be ready
#
.PHONY: graphdb-wait
graphdb-wait:
	@printf "Waiting for GraphDB to be ready...\n"
	@for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do \
		if curl -sf "http://localhost:$(GRAPHDB_PORT)/rest/repositories" >/dev/null 2>&1; then \
			echo "GraphDB is ready"; \
			exit 0; \
		fi; \
		echo "Waiting... ($$i/30)"; \
		sleep 2; \
	done; \
	echo "GraphDB failed to start"; \
	exit 1

#
# Check if repository exists
#
.PHONY: graphdb-repo-check
graphdb-repo-check:
	@if curl -sf "http://localhost:$(GRAPHDB_PORT)/rest/repositories/$(GRAPHDB_REPO_NAME)" >/dev/null 2>&1; then \
		echo "Repository $(GRAPHDB_REPO_NAME) exists"; \
	else \
		echo "Repository $(GRAPHDB_REPO_NAME) does not exist"; \
		exit 1; \
	fi

#
# Show GraphDB status
#
.PHONY: graphdb-status
graphdb-status:
	@if $(DOCKER_CMD) ps --filter "name=$(GRAPHDB_CONTAINER_NAME)" --format "{{.Names}}" | grep -q $(GRAPHDB_CONTAINER_NAME); then \
		echo "GraphDB container is running"; \
		echo "  Container:  $(GRAPHDB_CONTAINER_NAME)"; \
		echo "  Volume:     $(GRAPHDB_VOLUME_NAME)"; \
		echo "  Instance:   $(TRIPLESTORE_INSTANCE)"; \
		echo "  Port:       $(GRAPHDB_PORT)"; \
		echo "  URL:        http://localhost:$(GRAPHDB_PORT)"; \
		echo "  Repository: $(GRAPHDB_REPO_NAME)"; \
		echo "  SPARQL:     http://localhost:$(GRAPHDB_PORT)/repositories/$(GRAPHDB_REPO_NAME)"; \
	else \
		echo "GraphDB container is not running"; \
	fi

#
# HTTP load: loads to running GraphDB server via rdf-loader (incremental, hash-based)
# Delegates to pnpm exec rdf-loader which handles file discovery,
# content-hash change detection, parallel uploads, and SPARQL inlining.
# Requires server to be running.
#
.PHONY: graphdb-http-load
graphdb-http-load:
	@pnpm exec rdf-loader --graphdb load

.PHONY: graphdb-http-load-flags-delete
graphdb-http-load-flags-delete: rdf-http-load-flags-delete

.PHONY: graphdb-http-reload
graphdb-http-reload:
	@pnpm exec rdf-loader --graphdb load --force

#
# Bulk load alias (uses HTTP load since GraphDB doesn't have CLI bulk load)
#
.PHONY: graphdb-load
graphdb-load: graphdb-http-load

endif # USE_GRAPHDB

#$(info <--- .make/graphdb.mk)

endif # _MK_GRAPHDB_MK_
