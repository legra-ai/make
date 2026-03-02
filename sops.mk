ifndef _MK_SOPS_MK_
_MK_SOPS_MK_ := 1

#$(info ---> .make/sops.mk)

#
# SOPS support is disabled by default.
# Set USE_SOPS=1 to enable SOPS functionality.
# We are migrating to dotenvage for secrets management.
#
ifeq ($(USE_SOPS),1)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

include $(MK_DIR)/os.mk
include $(MK_DIR)/brew.mk
include $(MK_DIR)/make.mk
include $(MK_DIR)/sops-generate.mk
-include $(GIT_ROOT)/.sops-variables.mk

SOPS_VERSION_EXPECTED := 3.12.1
SOPS_INSTALL := 1
ifndef SOPS_KEYS_ORG
SOPS_KEYS_ORG := ekgf
endif
SOPS_KEYS_DIR := $(GIT_ROOT)/.sops/$(SOPS_KEYS_ORG)
SOPS_KEYS_FILE := $(SOPS_KEYS_DIR)/keys.json

SOPS_BIN := $(call where-is-binary,sops)
ifndef SOPS_BIN
$(warning SOPS_BIN not found, install Mozilla sops)
endif
#$(info SOPS_BIN=$(SOPS_BIN))

ifdef SOPS_BIN
SOPS_VERSION := $(shell if readlink $(SOPS_BIN) | grep -q $(SOPS_VERSION_EXPECTED) ; then echo $(SOPS_VERSION_EXPECTED) ; else $(SOPS_BIN) --version 2>/dev/null | head -n1 | cut -d\  -f2 ; fi)
$(info sops version is $(SOPS_VERSION), using keys file $(SOPS_KEYS_FILE))
endif

SOPS_EXEC := $(TMP_DIR)/sops-exec-$(SOPS_KEYS_ORG).sh

.PHONY: sops-check
ifndef SOPS_VERSION
sops-check: sops-install
else
ifneq ($(SOPS_VERSION),$(SOPS_VERSION_EXPECTED))
$(info SOPS_VERSION ($(SOPS_VERSION)) is not equal to SOPS_VERSION_EXPECTED ($(SOPS_VERSION_EXPECTED)))
sops-check: sops-upgrade
else
#$(info SOPS_VERSION is equal to SOPS_VERSION_EXPECTED)
SOPS_INSTALL := 0
sops-check:
	@echo Using Mozilla Sops ${SOPS_VERSION}
endif
endif

.PHONY: sops-edit
sops-edit: sops-check
	$(SOPS_BIN) $(SOPS_KEYS_FILE) ; rc=$$? ; \
	if ((rc != 200)) ; then \
		echo "Sops edit failed with rc=$$rc" ; \
		exit $$rc ; \
	fi

.PHONY: sops-shell
sops-shell: sops-check
	set -x ; $(SOPS_BIN) exec-env $(SOPS_KEYS_FILE) '$(CURRENT_INTERACTIVE_SHELL) -l'

.PHONY: _sops-log-if-upgrade-needed
ifneq ($(SOPS_VERSION),$(SOPS_VERSION_EXPECTED))
_sops-log-if-upgrade-needed:
	@echo "Mozilla Sops expected version [$(SOPS_VERSION_EXPECTED)] is not the actual version [$(SOPS_VERSION)]"
else
_sops-log-if-upgrade-needed:
endif

.PHONY: sops-install
ifeq ($(SOPS_INSTALL),0)
sops-install:
else
ifdef BREW_BIN
sops-install: sops-install-via-brew
	@echo "sops-install done"
else
sops-install:
	@echo "HomeBrew not found, you'll have to install Mozilla sops yourself"
	@exit 1
endif
endif

.PHONY: sops-upgrade
ifdef BREW_BIN
sops-upgrade: _sops-log-if-upgrade-needed sops-upgrade-via-brew
else
sops-upgrade:
	@echo "Upgrade Mozilla sops to version $(SOPS_VERSION_EXPECTED)"
	exit 1
endif

.PHONY: sops-install-via-brew
sops-install-via-brew: brew-check
	@echo "Mozilla Sops is not installed, installing it now"
	$(BREW_BIN) install sops
	@echo "Mozilla Sops should be installed now"

.PHONY: sops-install-via-choco
sops-install-via-choco:
	@echo "Mozilla Sops is not installed, installing it now"
	ls -al /Users/runner/hostedtoolcache/sops || true
	choco upgrade chocolatey
	choco install sops --version $(SOPS_VERSION_EXPECTED)
	@echo "Mozilla Sops should be installed now"

.PHONY: sops-upgrade-via-brew
sops-upgrade-via-brew: _sops-log-if-upgrade-needed brew-check
	$(BREW_BIN) upgrade sops

#.INTERMEDIATE: $(TMP_DIR)/exec-with-sops.sh
SOPS_GENERATE_EXEC_SCRIPT := 0
ifdef SOPS_KEYS_FILE
ifdef SOPS_KEYS_ORG
SOPS_GENERATE_EXEC_SCRIPT := 1
endif
endif

dollar := \$$
quote := \"
nl := \\\n

ifeq ($(SOPS_GENERATE_EXEC_SCRIPT),1)
$(SOPS_EXEC):
	echo '#!/bin/bash' > $@
	echo "export SOPS_REQUIRED=0" >> $@
	echo "exec $(SOPS_BIN) exec-env $(SOPS_KEYS_FILE) $(quote)$(dollar)*$(quote)" >> $@
	chmod u+x $@
else
$(SOPS_EXEC):
	@echo "ERROR: Cannot generate $@ because SOPS_KEYS_FILE or SOPS_KEYS_ORG are not set"
	exit 1
endif
ifeq ($(findstring undefine,$(.FEATURES)),undefine)
ifeq ($(IS_MAKE_4),1)
undefine SOPS_GENERATE_EXEC_SCRIPT
endif
endif

.PHONY: sops-exec
sops-exec: $(SOPS_EXEC)
	@echo "SOPS_EXEC is $(SOPS_EXEC)"

ifeq ($(SOPS_REQUIRED),1)
rubbish := $(shell $(MAKE) --no-print-directory SOPS_REQUIRED=0 sops-exec >/dev/null 2>&1 ; rc=$$? ; exit $${rc})
ifeq ($(rubbish),1)
$(error Could not generate $(SOPS_EXEC))
endif
endif

endif # USE_SOPS

#$(info <--- .make/sops.mk)

endif # _MK_SOPS_MK_
