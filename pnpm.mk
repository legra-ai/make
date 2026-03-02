#
# All the npm/pnpm related stuff
#
ifndef _MK_PNPM_MK_
_MK_PNPM_MK_ := 1

#$(info ---> .make/pnpm.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

include $(MK_DIR)/os.mk
include $(MK_DIR)/curl.mk
include $(MK_DIR)/nodejs.mk

ifndef PNPM_HOME
export PNPM_HOME := $(HOME)/Library/pnpm
export PATH2 := $(PATH):$(PNPM_HOME)
export PATH := $(PATH2)
undefine PATH2
endif

NPM_BIN := $(call where-is-binary,npm)
NPX_BIN := $(call where-is-binary,npx)
PNPM_BIN := $(call where-is-binary,pnpm)
PNPM_CMD := $(NPM_BIN) pnpm

ifdef PNPM_BIN
PNPM_VERSION := $(shell $(PNPM_BIN) --version 2>/dev/null | cut -d\  -f2)
endif
PNPM_VERSION_EXPECTED := 10.30.3
ifeq ($(PNPM_VERSION),$(PNPM_VERSION_EXPECTED))
PNPM_CHECKED := 1
else
PNPM_CHECKED := 0
$(info pnpm version $(PNPM_VERSION) does not match expected version $(PNPM_VERSION_EXPECTED))
endif

.PHONY: pnpm-check
ifdef PNPM_BIN
ifeq ($(PNPM_CHECKED),1)
pnpm-check: _pnpm-check-info nodejs-check
	@#echo "Using pnpm $(PNPM_VERSION), with its config file $(GIT_ROOT)/package.json"
else
pnpm-check: pnpm-force-check
endif
else
pnpm-check: _pnpm-check-info nodejs-check
	@printf "$(red)pnpm is not installed, can't run this function, run $(MAKE) pnpm-install-itself$(normal)\n"
	exit 1
endif

.PHONY: pnpm-force-check
pnpm-force-check: _pnpm-check-info pnpm-install-itself-first
	@printf "$(green)checked pnpm $(PNPM_VERSION_EXPECTED)$(normal)\n"
	@printf " - PNPM_BIN=$(PNPM_BIN)\n"
	PNPM_VERSION_COMMAND_LINE=$$($(PNPM_BIN) --version 2>/dev/null | cut -d\  -f2) && printf "$(red)Detected pnpm version $${PNPM_VERSION_COMMAND_LINE} on the command line using \"$(PNPM_BIN) --version\"$(normal)\n"
	#$(NPX_BIN) install pnpm > /dev/null 2>&1 || true
	$(COREPACK_BIN) install --global pnpm@$(PNPM_VERSION_EXPECTED)
	@printf " - NPX_BIN=$(NPX_BIN)\n"
	PNPM_VERSION_COREPACK=$$(echo Y | $(NPX_BIN) pnpm --version 2>/dev/null | cut -d\  -f2) && printf "$(red)Detected pnpm version $${PNPM_VERSION_COREPACK} on the command line using \"$(NPX_BIN) pnpm --version\"$(normal)\n"

.PHONY: _pnpm-check-info
_pnpm-check-info:
	@printf "$(bold)Checking $(green)pnpm $(PNPM_VERSION_EXPECTED)$(normal):\n"

.PHONY: pnpm-install-itself-first
pnpm-install-itself-first: brew-check nodejs-check
	@printf "Installing $(bold)$(green)pnpm$(normal) (as configured in your package.json) with corepack:\n"
	$(COREPACK_BIN) install
	@printf "Upgrading $(bold)$(green)pnpm$(normal) (as configured in your package.json) with corepack:\n"
	$(COREPACK_BIN) up
	@printf "Installing $(bold)$(green)pnpm $(PNPM_VERSION_EXPECTED)$(normal) with corepack:\n"
	set -x ; $(COREPACK_BIN) install --global pnpm@$(PNPM_VERSION_EXPECTED)
	set -x ; $(COREPACK_BIN) prepare pnpm@$(PNPM_VERSION_EXPECTED) --activate
	set -x ; $(COREPACK_BIN) use pnpm@$(PNPM_VERSION_EXPECTED)
	# for some reason the command below causes a symlink error whereas executing the exact
	# same command in the shell does not
	# set -x ; $(COREPACK_BIN) enable
	@printf "Installed $(bold)$(green)pnpm $(PNPM_VERSION_EXPECTED)$(normal)\n"

.PHONY: pnpm-install-prerequisites
ifdef PNPM_BIN
pnpm-install-prerequisites: brew-check nodejs-check
	set -x ; $(PNPM_BIN) install -g node-gyp
else
pnpm-install-prerequisites:
endif

.PHONY: pnpm-install-itself
pnpm-install-itself: pnpm-install-itself-first pnpm-install-prerequisites

.PHONY: pnpm-clean
pnpm-clean:
	@echo "Cleaning pnpm"
	@rm -rf $(GIT_ROOT)/node_modules

.PHONY: pnpm-install
pnpm-install: pnpm-check
	cd $(GIT_ROOT) && $(PNPM_BIN) install

.PHONY: pnpm-upgrade-pnpm
pnpm-upgrade-pnpm: $(PNPM_BIN)
	# $(PNPM_BIN) add -g pnpm
	$(PNPM_BIN) self-update

.PHONY: pnpm-update
pnpm-update: pnpm-check pnpm-upgrade-pnpm
	cd $(GIT_ROOT) && rm -rf node_modules && rm -f pnpm-lock.yaml && $(PNPM_BIN) update

.PHONY: pnpm-run-dev
pnpm-run-dev: pnpm-check
	cd $(GIT_ROOT) && $(PNPM_BIN) run dev

#$(info <--- .make/pnpm.mk)

endif # _MK_PNPM_MK_
