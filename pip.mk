#
# All the python pip related stuff
#
ifndef _MK_PIP_MK_
_MK_PIP_MK_ := 1

#$(info ---> .make/pip.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

include $(MK_DIR)/os.mk
include $(MK_DIR)/python.mk

PIP_BIN := $(call where-is-binary,pip$(PYTHON_VERSION_EXPECTED_MAJOR_MINOR))
ifndef PIP_BIN
PIP_BIN := $(call where-is-binary,pip3)
endif

ifdef PIP_BIN
PIP_VERSION := $(shell $(PIP_BIN) --version 2>/dev/null | cut -d\  -f2)
endif
PIP_VERSION_EXPECTED := 26.0
ifeq ($(PIP_VERSION),$(PIP_VERSION_EXPECTED))
PIP_CHECKED := 1
else
PIP_CHECKED := 0
$(info pip3 version $(PIP_VERSION) does not match expected version $(PIP_VERSION_EXPECTED))
endif

.PHONY: pip-check
ifdef PIP_BIN
ifeq ($(PIP_CHECKED),1)
pip-check:
	@#echo "Using pip $(PIP_VERSION) ($(PIP_BIN))"
else
pip-check: python-install
endif
else
pip-check: python-install
endif

#$(info <--- .make/pip.mk)

endif # _MK_PIP_MK_
