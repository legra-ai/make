#
# Load all the RDF files in this repo into OxiGraph
#
# Two loading strategies:
# - bulk-load: Kills server, loads directly via CLI (faster for initial/full loads)
# - http-load: Loads via HTTP to running server (for incremental updates, supports parallel)
#
ifndef _MK_OXIGRAPH_LOAD_MK_
_MK_OXIGRAPH_LOAD_MK_ := 1

#$(info ---> .make/oxigraph-load.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

#
# Auto-detect oxigraph-* targets and enable OxiGraph support.
# This allows `gmake oxigraph-http-load` to work even when EKG_VARIANT=graphdb in .env.
#
ifneq ($(filter oxigraph-%,$(MAKECMDGOALS)),)
USE_OXIGRAPH := 1
EKG_VARIANT := oxigraph
endif

ifeq ($(USE_OXIGRAPH),1)

include $(MK_DIR)/oxigraph.mk
include $(MK_DIR)/rdf-http-load.mk

# SPARQL endpoints for Oxigraph.
# All endpoint URLs and auth keys come from dotenvage (.env files).
# Fallback defaults only apply when dotenvage hasn't set them.
EKG_SPARQL_HEALTH_ENDPOINT ?= http://localhost:$(OXIGRAPH_PORT)/
EKG_SPARQL_QUERY_ENDPOINT ?= http://localhost:$(OXIGRAPH_PORT)/query
EKG_SPARQL_UPDATE_ENDPOINT ?= http://localhost:$(OXIGRAPH_PORT)/update
EKG_SPARQL_STORE_ENDPOINT ?= http://localhost:$(OXIGRAPH_PORT)/store

# Environment for flag files - prevents cross-environment conflicts
EKG_ENV ?= local

# Environment for flag files - prevents cross-environment conflicts
# (moved up so it's available to both Docker and native paths)

# ---------------------------------------------------------------------------
# Bulk loading requires native binary mode (direct CLI access to RocksDB).
# In Docker mode, use HTTP loading instead.
# ---------------------------------------------------------------------------
ifneq ($(OXIGRAPH_DOCKER),1)

# Bulk load flag suffix includes variant and environment
BULK_LOAD_FLAG_SUFFIX := .bulk-loaded.$(EKG_VARIANT).$(EKG_ENV).flag

# Bulk load flags (CLI-based, requires server to be stopped)
ONTOLOGY_FILES_BULK_LOADED_FLAGS := $(ONTOLOGY_FILES:.ttl=$(BULK_LOAD_FLAG_SUFFIX))
TTL_FILES_BULK_LOADED_FLAGS := $(RDF_TTL_FILES:.ttl=$(BULK_LOAD_FLAG_SUFFIX))
NT_FILES_BULK_LOADED_FLAGS := $(RDF_NT_FILES:.nt=$(BULK_LOAD_FLAG_SUFFIX))
RDF_FILES_BULK_LOADED_FLAGS := $(TTL_FILES_BULK_LOADED_FLAGS) $(NT_FILES_BULK_LOADED_FLAGS)

#
# Bulk load rules - load directly to database files via CLI
# Server must be stopped (oxigraph-kill is a dependency)
# Static pattern rules to support dynamic flag suffix
#
$(filter %.ttl$(BULK_LOAD_FLAG_SUFFIX),$(ONTOLOGY_FILES_BULK_LOADED_FLAGS) $(TTL_FILES_BULK_LOADED_FLAGS)): %$(BULK_LOAD_FLAG_SUFFIX): %
	@file="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@@g')" && printf "Bulk loading RDF File $(green)$${file}$(normal)\n"
	@graph_name="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@file:///@g')" ; \
		ulimit -n 10240 && $(OXIGRAPH_BIN) load --location $(OXIGRAPH_LOCATION) --file $< --graph $${graph_name} 2>&1 | { grep -v "If you plan to run a read-heavy workload" || true; }
	@touch $@

$(NT_FILES_BULK_LOADED_FLAGS): %$(BULK_LOAD_FLAG_SUFFIX): %
	@file="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@@g')" && printf "Bulk loading RDF File $(green)$${file}$(normal)\n"
	@graph_name="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@file:///@g')" ; \
		ulimit -n 10240 && $(OXIGRAPH_BIN) load --location $(OXIGRAPH_LOCATION) --file $< --graph $${graph_name} 2>&1 | { grep -v "If you plan to run a read-heavy workload" || true; }
	@touch $@

#
# Dump all content of the OxiGraph database (stored in .oxigraph) to a temporary file called oxigraph-everything.trig
# in TriG format
#
#.INTERMEDIATE: $(TMP_DIR)/oxigraph-everything.trig
$(TMP_DIR)/oxigraph-everything.trig: oxigraph-check
	@ulimit -n 10240 && $(OXIGRAPH_BIN) dump --location $(OXIGRAPH_LOCATION) --format trig --file $@

#
# Show all content of the OxiGraph database (stored in .oxigraph) to stdout in TriG format
#
.PHONY: oxigraph-dump-trig
oxigraph-dump-trig: $(TMP_DIR)/oxigraph-everything.trig
	@cat -n $?

.PHONY: oxigraph-bulk-load-flags-delete
oxigraph-bulk-load-flags-delete:
	@rm -f $(ONTOLOGY_FILES_BULK_LOADED_FLAGS) $(TTL_FILES_BULK_LOADED_FLAGS) $(NT_FILES_BULK_LOADED_FLAGS) >/dev/null 2>&1 || true

.PHONY: oxigraph-bulk-load-flags-delete-all
oxigraph-bulk-load-flags-delete-all:
	@find $(GIT_ROOT) -name "*.bulk-loaded.*.flag" -delete 2>/dev/null || true

.PHONY: oxigraph-load-flags-delete
oxigraph-load-flags-delete: oxigraph-bulk-load-flags-delete oxigraph-http-load-flags-delete

.PHONY: oxigraph-load-flags-delete-all
oxigraph-load-flags-delete-all: oxigraph-bulk-load-flags-delete-all rdf-http-load-flags-delete-all

#
# Bulk load: kills server first, loads via CLI (fast, sequential)
#
.PHONY: oxigraph-bulk-load
oxigraph-bulk-load: oxigraph-kill $(ONTOLOGY_FILES_BULK_LOADED_FLAGS) $(RDF_FILES_BULK_LOADED_FLAGS)
	@printf "$(green)Bulk loaded all RDF files$(normal)\n"

else # OXIGRAPH_DOCKER == 1

# In Docker mode, bulk load is not available (no direct filesystem access).
# Provide stub targets that emit clear error messages.

.PHONY: oxigraph-bulk-load
oxigraph-bulk-load:
	@printf "$(red)Bulk load is not supported in Docker mode.$(normal)\n"
	@printf "Use 'gmake oxigraph-http-load' instead (requires server to be running).\n"
	@exit 1

.PHONY: oxigraph-dump-trig
oxigraph-dump-trig:
	@printf "$(red)Dump is not supported in Docker mode.$(normal)\n"
	@exit 1

.PHONY: oxigraph-bulk-load-flags-delete
oxigraph-bulk-load-flags-delete:
	@find $(GIT_ROOT) -name "*.bulk-loaded.*.flag" -delete 2>/dev/null || true

.PHONY: oxigraph-bulk-load-flags-delete-all
oxigraph-bulk-load-flags-delete-all:
	@find $(GIT_ROOT) -name "*.bulk-loaded.*.flag" -delete 2>/dev/null || true

.PHONY: oxigraph-load-flags-delete
oxigraph-load-flags-delete: oxigraph-bulk-load-flags-delete oxigraph-http-load-flags-delete

.PHONY: oxigraph-load-flags-delete-all
oxigraph-load-flags-delete-all: oxigraph-bulk-load-flags-delete-all rdf-http-load-flags-delete-all

endif # OXIGRAPH_DOCKER

# HTTP load flag deletion works in both native and Docker mode
.PHONY: oxigraph-http-load-flags-delete
oxigraph-http-load-flags-delete: rdf-http-load-flags-delete

#
# Check if OxiGraph server is running (delegates to shared sparql-server-check)
#
.PHONY: oxigraph-server-check
oxigraph-server-check: sparql-server-check

#
# HTTP load: loads to running server via rdf-loader (incremental, hash-based)
# Delegates to pnpm exec rdf-loader which handles file discovery,
# content-hash change detection, parallel uploads, and SPARQL inlining.
# Requires server to be running.
#
.PHONY: oxigraph-http-load
oxigraph-http-load:
	@pnpm exec rdf-loader --oxigraph load

#
# Convenience aliases
#
.PHONY: oxigraph-load
oxigraph-load: oxigraph-bulk-load

.PHONY: oxigraph-reload
oxigraph-reload: oxigraph-bulk-load-flags-delete oxigraph-bulk-load

.PHONY: oxigraph-http-reload
oxigraph-http-reload:
	@pnpm exec rdf-loader --oxigraph load --force

oxigraph-graph-names: $(RDF_FILES)
	@for file in $? ; do \
		graph_name="$$(echo $${file} | $(SED_BIN) 's@$(GIT_ROOT)/@file:///@g')" ; \
		echo "$${graph_name}" ; \
	done

endif # USE_OXIGRAPH

#$(info <--- .make/oxigraph-load.mk)

endif # _MK_OXIGRAPH_LOAD_MK_
