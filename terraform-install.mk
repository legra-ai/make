ifndef _MK_TERRAFORM_INSTALL_MK_
_MK_TERRAFORM_INSTALL_MK_ := 1

#$(info ---> .make/terraform-install.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

#
# Terraform support is disabled by default.
# Set USE_TERRAFORM=1 to enable Terraform functionality.
#
ifeq ($(USE_TERRAFORM),1)

include $(MK_DIR)/os.mk
include $(MK_DIR)/curl.mk
include $(MK_DIR)/brew.mk

TERRAFORM_BIN := $(call where-is-binary,terraform)

ifdef TERRAFORM_BIN
TERRAFORM_VERSION := $(shell $(TERRAFORM_BIN) --version 2>/dev/null | head -n1 | cut -dv -f2)
endif
TERRAFORM_VERSION_EXPECTED := 1.14.6
ifeq ($(TERRAFORM_VERSION),$(TERRAFORM_VERSION_EXPECTED))
TERRAFORM_CHECKED := 1
else
TERRAFORM_CHECKED := 0
ifdef TERRAFORM_BIN
$(info terraform version $(TERRAFORM_VERSION) does not match expected version $(TERRAFORM_VERSION_EXPECTED))
else
$(info terraform not installed)
$(info terraform $(TERRAFORM_VERSION_EXPECTED) has not been installed (we found $(TERRAFORM_VERSION)))
endif
endif

.PHONY: terraform-check
ifdef TERRAFORM_BIN
terraform-check:
else
terraform-check:
	@echo "Install terraform by issuing the command $(MAKE) terraform-install"
	exit 1
endif

.PHONY: _terraform-install-info
_terraform-install-info:
	@echo "Installing Terraform $(TERRAFORM_VERSION_EXPECTED):"

.PHONY: terraform-install-itself
terraform-install-itself: _terraform-install-info brew-check
	@$(BREW_BIN) tap hashicorp/tap
	@$(BREW_BIN) install hashicorp/tap/terraform
	if command -v terraform >/dev/null 2>&1 ; then \
		echo "terraform is installed"; \
	else \
		echo "terraform is installed but not in your PATH yet"; \
		exit 1; \
	fi

.PHONY: terraform-install
terraform-install: terraform-install-itself tflint-install

endif # USE_TERRAFORM

#$(info <--- .make/terraform-install.mk)

endif # _MK_TERRAFORM_INSTALL_MK_
