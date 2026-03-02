#
# Common RDF HTTP loading support for SPARQL 1.1 Graph Store Protocol.
# Works with any compliant triplestore (Oxigraph, GraphDB, etc.)
#
# Requires EKG_SPARQL_* environment variables to be set (via dotenvage).
#
ifndef _MK_RDF_HTTP_LOAD_MK_
_MK_RDF_HTTP_LOAD_MK_ := 1

#$(info ---> .make/rdf-http-load.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

include $(MK_DIR)/rdf-files.mk
include $(MK_DIR)/curl.mk

# Build auth header for SPARQL requests (empty when EKG_SPARQL_AUTH_KEY is not set).
# Uses deferred expansion (=) so the value is resolved at recipe execution time.
SPARQL_AUTH_HEADER = $(if $(EKG_SPARQL_AUTH_KEY),-H "Authorization: Bearer $(EKG_SPARQL_AUTH_KEY)",)

# Environment for flag files - prevents cross-environment conflicts
# e.g., loading to production won't mark files as loaded for local
EKG_ENV ?= local
EKG_VARIANT ?= oxigraph

# Flag file suffix includes variant and environment to prevent conflicts
# e.g., .http-loaded.oxigraph.local.flag vs .http-loaded.oxigraph.production.flag
HTTP_LOAD_FLAG_SUFFIX := .http-loaded.$(EKG_VARIANT).$(EKG_ENV).flag

# HTTP load flags (HTTP-based, server must be running, supports parallel)
ONTOLOGY_FILES_HTTP_LOADED_FLAGS := $(ONTOLOGY_FILES:.ttl=$(HTTP_LOAD_FLAG_SUFFIX))
TTL_FILES_HTTP_LOADED_FLAGS := $(RDF_TTL_FILES:.ttl=$(HTTP_LOAD_FLAG_SUFFIX))
NT_FILES_HTTP_LOADED_FLAGS := $(RDF_NT_FILES:.nt=$(HTTP_LOAD_FLAG_SUFFIX))
# Combine all flags, removing duplicates (ontology files are also in TTL_FILES)
RDF_FILES_HTTP_LOADED_FLAGS := $(sort $(TTL_FILES_HTTP_LOADED_FLAGS) $(NT_FILES_HTTP_LOADED_FLAGS))
# All TTL flags that aren't ontology files
NON_ONTOLOGY_TTL_FLAGS := $(filter-out $(ONTOLOGY_FILES_HTTP_LOADED_FLAGS),$(TTL_FILES_HTTP_LOADED_FLAGS))

#
# HTTP load rules - load via HTTP PUT to running server
# Uses W3C SPARQL 1.1 Graph Store HTTP Protocol
# Supports parallel execution (use make -j)
# Static pattern rules to support dynamic flag suffix
#
# Note: The flag substitution removes the extension (.ttl or .nt), so:
#   file.ttl -> file$(HTTP_LOAD_FLAG_SUFFIX)
#   file.nt  -> file$(HTTP_LOAD_FLAG_SUFFIX)
# The prerequisite must add the extension back: %.ttl or %.nt
#
# Rule for ontology TTL files
$(ONTOLOGY_FILES_HTTP_LOADED_FLAGS): %$(HTTP_LOAD_FLAG_SUFFIX): %.ttl
	@file="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@@g')" && printf "HTTP loading RDF File $(green)$${file}$(normal)\n"
	@graph_name="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@file:///@g')" ; \
		$(CURL_BIN) -sf -X PUT -H "Content-Type: text/turtle" \
			$(SPARQL_AUTH_HEADER) \
			--data-binary @$< \
			"$(EKG_SPARQL_STORE_ENDPOINT)?graph=$${graph_name}" \
		|| { printf "$(red)ERROR: Failed to load $${file}. Is the SPARQL server running at $(EKG_SPARQL_HEALTH_ENDPOINT)?$(normal)\n" >&2; exit 1; }
	@touch $@

# Rule for non-ontology TTL files (use-case, static-dataset, etc.)
$(NON_ONTOLOGY_TTL_FLAGS): %$(HTTP_LOAD_FLAG_SUFFIX): %.ttl
	@file="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@@g')" && printf "HTTP loading RDF File $(green)$${file}$(normal)\n"
	@graph_name="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@file:///@g')" ; \
		$(CURL_BIN) -sf -X PUT -H "Content-Type: text/turtle" \
			$(SPARQL_AUTH_HEADER) \
			--data-binary @$< \
			"$(EKG_SPARQL_STORE_ENDPOINT)?graph=$${graph_name}" \
		|| { printf "$(red)ERROR: Failed to load $${file}. Is the SPARQL server running at $(EKG_SPARQL_HEALTH_ENDPOINT)?$(normal)\n" >&2; exit 1; }
	@touch $@

$(NT_FILES_HTTP_LOADED_FLAGS): %$(HTTP_LOAD_FLAG_SUFFIX): %.nt
	@file="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@@g')" && printf "HTTP loading RDF File $(green)$${file}$(normal)\n"
	@graph_name="$$(echo $< | $(SED_BIN) 's@$(GIT_ROOT)/@file:///@g')" ; \
		$(CURL_BIN) -sf -X PUT -H "Content-Type: application/n-triples" \
			$(SPARQL_AUTH_HEADER) \
			--data-binary @$< \
			"$(EKG_SPARQL_STORE_ENDPOINT)?graph=$${graph_name}" \
		|| { printf "$(red)ERROR: Failed to load $${file}. Is the SPARQL server running at $(EKG_SPARQL_HEALTH_ENDPOINT)?$(normal)\n" >&2; exit 1; }
	@touch $@

.PHONY: rdf-http-load-flags-delete
rdf-http-load-flags-delete:
	@rm -f $(ONTOLOGY_FILES_HTTP_LOADED_FLAGS) $(TTL_FILES_HTTP_LOADED_FLAGS) $(NT_FILES_HTTP_LOADED_FLAGS) >/dev/null 2>&1 || true

.PHONY: rdf-http-load-flags-delete-all
rdf-http-load-flags-delete-all:
	@find $(GIT_ROOT) -name "*.http-loaded.*.flag" -delete 2>/dev/null || true

#
# Check if SPARQL server is running
#
.PHONY: sparql-server-check
sparql-server-check:
	@if [ -z "$(EKG_SPARQL_HEALTH_ENDPOINT)" ]; then \
		printf "$(red)ERROR: EKG_SPARQL_HEALTH_ENDPOINT is not set. Configure it in .env files or environment$(normal)\n"; \
		exit 1; \
	fi
	@$(CURL_BIN) -sf "$(EKG_SPARQL_HEALTH_ENDPOINT)" >/dev/null 2>&1 \
		|| { printf "$(red)ERROR: SPARQL server is not running at $(EKG_SPARQL_HEALTH_ENDPOINT)$(normal)\n"; exit 1; }

#
# Internal target for HTTP loading files (called with parallelism)
#
.PHONY: _rdf-http-load-files
_rdf-http-load-files: $(ONTOLOGY_FILES_HTTP_LOADED_FLAGS) $(RDF_FILES_HTTP_LOADED_FLAGS)

#
# Load SPARQL query files (.rq) into the knowledge graph
# For each .rq file, finds the corresponding story.ttl and inserts the query
# content as sparql-story:sparql property
#
.PHONY: _rdf-http-load-sparql-queries
_rdf-http-load-sparql-queries:
	@find $(GIT_ROOT)/use-case -name "*.rq" -type f 2>/dev/null | while read rq_file; do \
		story_dir="$$(dirname "$$rq_file")" ; \
		story_ttl="$$story_dir/story.ttl" ; \
		if [ -f "$$story_ttl" ]; then \
			rq_filename="$$(basename "$$rq_file")" ; \
			rel_story="$$(echo "$$story_ttl" | $(SED_BIN) 's@$(GIT_ROOT)/@@g')" ; \
			graph_name="file:///$$rel_story" ; \
			rel_rq="$$(echo "$$rq_file" | $(SED_BIN) 's@$(GIT_ROOT)/@@g')" ; \
			printf "HTTP loading SPARQL query $(green)$$rel_rq$(normal)\n" ; \
			query_content="$$(cat "$$rq_file" | $(SED_BIN) 's/\\/\\\\/g' | $(SED_BIN) 's/"/\\"/g' | tr '\n' '\r' | $(SED_BIN) 's/\r/\\n/g')" ; \
			sparql_update="PREFIX sparql-story: <https://ekgf.org/ontology/story-impl-sparql#> DELETE { GRAPH <$$graph_name> { ?impl sparql-story:sparql ?oldSparql . } } INSERT { GRAPH <$$graph_name> { ?impl sparql-story:sparql \"\"\"$$query_content\"\"\" . } } WHERE { GRAPH <$$graph_name> { ?impl sparql-story:fileName \"$$rq_filename\" . OPTIONAL { ?impl sparql-story:sparql ?oldSparql . } } }" ; \
			$(CURL_BIN) -sf -X POST -H "Content-Type: application/sparql-update" \
				$(SPARQL_AUTH_HEADER) \
				--data-binary "$$sparql_update" \
				"$(EKG_SPARQL_UPDATE_ENDPOINT)" \
			|| { printf "$(red)ERROR: Failed to load SPARQL query $$rel_rq$(normal)\n" >&2; } ; \
		fi ; \
	done
	@printf "$(green)HTTP loaded all SPARQL query files$(normal)\n"

#$(info <--- .make/rdf-http-load.mk)

endif # _MK_RDF_HTTP_LOAD_MK_
