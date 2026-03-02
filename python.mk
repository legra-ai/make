#
# All the python related stuff
#
ifndef _MK_PYTHON_MK_
_MK_PYTHON_MK_ := 1

#$(info ---> .make/python.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

include $(MK_DIR)/os.mk
include $(MK_DIR)/curl.mk
include $(MK_DIR)/brew.mk

PYTHON_VERSION_EXPECTED_MAJOR_MINOR := 3.14
PYTHON_VERSION_EXPECTED := $(PYTHON_VERSION_EXPECTED_MAJOR_MINOR).3

PYTHON_BIN := $(call where-is-binary,python$(PYTHON_VERSION_EXPECTED_MAJOR_MINOR))
ifndef PYTHON_BIN
PYTHON_BIN := $(call where-is-binary,python)
endif
ifndef PYTHON_BIN
PYTHON_BIN := $(call where-is-binary,python3)
endif

ifdef PYTHON_BIN
export PIPX_DEFAULT_PYTHON := $(PYTHON_BIN)
endif

#$(info PYTHON_BIN=$(PYTHON_BIN))

ifdef PYTHON_BIN
PYTHON_VERSION := $(shell $(PYTHON_BIN) --version 2>/dev/null | cut -d\  -f2)
endif
ifeq ($(PYTHON_VERSION),$(PYTHON_VERSION_EXPECTED))
PYTHON_CHECKED := 1
else
PYTHON_CHECKED := 0
$(info python version $(PYTHON_VERSION) does not match expected version $(PYTHON_VERSION_EXPECTED))
endif

.PHONY: python-check
ifdef PYTHON_BIN
ifeq ($(PYTHON_CHECKED),1)
python-check:
	@#echo "Using python $(PYTHON_VERSION)"
else
python-check: python-install
endif
else
python-check: python-install
endif

ifdef PYTHON_BIN
.INTERMEDIATE: $(TMP_DIR)/python
.INTERMEDIATE: $(TMP_DIR)/python3
$(TMP_DIR)/python:
	@echo "Creating symlink $@ to $(PYTHON_BIN)"
	ln -s $(PYTHON_BIN) $@
	chmod +x $@
$(TMP_DIR)/python3: $(TMP_DIR)/python
	@echo "Creating symlink $@ to $(PYTHON_BIN)"
	ln -s $(PYTHON_BIN) $@
	chmod +x $@
else
$(TMP_DIR)/python:
	@echo "ERROR: python $(PYTHON_VERSION_EXPECTED) not installed"
	exit 1
$(TMP_DIR)/python3:
	@echo "ERROR: python $(PYTHON_VERSION_EXPECTED) not installed"
	exit 1
endif

.PHONY: python-clean
python-clean:
	@echo "python-clean not implemented yet"

.PHONY: python-install
python-install: brew-check
	@printf "Installing $(bold)python $(PYTHON_VERSION_EXPECTED)$(normal) via brew:\n"
	@$(BREW_BIN) install python@$(PYTHON_VERSION_EXPECTED_MAJOR_MINOR)
	-@$(BREW_BIN) unlink python
	-@$(BREW_BIN) unlink python@$(PYTHON_VERSION_EXPECTED_MAJOR_MINOR)
	$(BREW_BIN) link --overwrite python-packaging
	@$(BREW_BIN) link --force python@$(PYTHON_VERSION_EXPECTED_MAJOR_MINOR)

.PHONY: python-update
python-update: python-check
	@echo "python-update not implemented yet"

#$(info <--- .make/python.mk)

endif # _MK_PYTHON_MK_
