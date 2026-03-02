ifndef _MK_TFLINT_MK_
_MK_TFLINT_MK_ := 1

#$(info ---> .make/tflint.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

#
# TFLint support requires USE_TERRAFORM=1.
#
ifeq ($(USE_TERRAFORM),1)

include $(MK_DIR)/os.mk
include $(MK_DIR)/make.mk
include $(MK_DIR)/brew.mk

TFLINT_BIN := $(call where-is-binary,tflint)

ifdef TFLINT_BIN
TFLINT_VERSION := $(shell $(TFLINT_BIN) --version 2>/dev/null | head -n1 | cut -d\  -f3)
endif
# keep the line below in sync with version published at https://formulae.brew.sh/formula/tflint
TFLINT_VERSION_EXPECTED := 0.61.0
ifeq ($(TFLINT_VERSION),$(TFLINT_VERSION_EXPECTED))
TFLINT_CHECKED := 1
else
TFLINT_CHECKED := 0
ifeq ($(IS_MAKE_4),1)
undefine TFLINT_BIN
endif
ifdef TFLINT_BIN
$(info terraform lint, version $(TFLINT_VERSION), does not match expected version $(TFLINT_VERSION_EXPECTED))
else
$(info terraform lint $(TFLINT_VERSION_EXPECTED) has not been installed (we found $(TFLINT_VERSION)))
endif
endif

.PHONY: tflint-check
ifdef TFLINT_BIN
tflint-check:
else
tflint-check: tflint-install
endif

.PHONY: tflint-install
tflint-install: brew-check $(BREW_PACKAGES)
	@grep -q "^tflint $(TFLINT_VERSION_EXPECTED)$$" $(BREW_PACKAGES) 2>/dev/null || ( \
		printf "Installing $(bold)tflint $(TFLINT_VERSION_EXPECTED)$(normal) via brew:\n" ; \
		$(BREW_BIN) install --force tflint ; \
		$(BREW_BIN) unlink tflint ; \
		$(BREW_BIN) link --force tflint )

endif # USE_TERRAFORM

#$(info <--- .make/tflint.mk)

endif # _MK_TFLINT_MK_
