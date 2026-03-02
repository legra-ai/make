ifndef _MK_NODEJS_MK_
_MK_NODEJS_MK_ := 1

#$(info ---> .make/nodejs.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

include $(MK_DIR)/os.mk
include $(MK_DIR)/brew.mk

NODEJS_BIN := $(call where-is-binary,node)

ifdef NODEJS_BIN
NODEJS_VERSION := $(shell $(NODEJS_BIN) --version 2>/dev/null | cut -d\  -f2 | cut -c2-)
endif
NODEJS_VERSION_EXPECTED := 24.13.0
NODEJS_MAIN_VERSION_EXPECTED := $(shell echo $(NODEJS_VERSION_EXPECTED) | cut -d. -f1)
ifeq ($(NODEJS_VERSION),$(NODEJS_VERSION_EXPECTED))
NODEJS_CHECKED := 1
else
NODEJS_CHECKED := 0
$(info NodeJS version $(NODEJS_VERSION) does not match expected version $(NODEJS_VERSION_EXPECTED))
endif

COREPACK_BIN := $(call where-is-binary,corepack)
ifndef COREPACK_BIN
NODEJS_CHECKED := 0
endif

.PHONY: nodejs-check
ifdef NODEJS_BIN
ifeq ($(NODEJS_CHECKED),1)
nodejs-check:
	@echo "Using NodeJS $(NODEJS_VERSION)"
else
nodejs-check: nodejs-install
endif
else
nodejs-check: nodejs-install
endif

ifdef NODEJS_BIN
.INTERMEDIATE: $(TMP_DIR)/node
$(TMP_DIR)/node:
	ln -s $(NODEJS_BIN) $@
	chmod +x $@
else
$(TMP_DIR)/node:
	@echo "ERROR: nodejs $(NODEJS_VERSION_EXPECTED) not installed"
	exit 1
endif

.PHONY: nodejs-install
nodejs-install: brew-check
	$(BREW_BIN) install --overwrite node@$(NODEJS_MAIN_VERSION_EXPECTED)
	$(BREW_BIN) unlink node@$(NODEJS_MAIN_VERSION_EXPECTED)
	$(BREW_BIN) link --force --overwrite node@$(NODEJS_MAIN_VERSION_EXPECTED)
	# We have to unlink pnpm here because otherwise corepack installation may fail
	#$(BREW_BIN) unlink pnpm
	$(BREW_BIN) install corepack

#$(info <--- .make/nodejs.mk)

endif # _MK_NODEJS_MK_
