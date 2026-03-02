#
# Support for dotenvage - a secrets management tool using age encryption.
# See https://crates.io/crates/dotenvage
#
# Can be installed via:
# - cargo install dotenvage
# - cargo binstall dotenvage
# - npm install -g dotenvage
#
ifndef _MK_DOTENVAGE_MK_
_MK_DOTENVAGE_MK_ := 1

#$(info ---> .make/dotenvage.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

include $(MK_DIR)/os.mk
include $(MK_DIR)/cargo.mk

DOTENVAGE_BIN := $(call where-is-binary,dotenvage)

# Fallback: when where-is-binary is not yet defined (e.g. dotenvage.mk is
# included before os.mk has been loaded), try a direct PATH lookup.
ifndef DOTENVAGE_BIN
DOTENVAGE_BIN := $(shell command -v dotenvage 2>/dev/null)
endif

ifdef DOTENVAGE_BIN
DOTENVAGE_VERSION := $(shell $(DOTENVAGE_BIN) --version 2>/dev/null | cut -d\  -f2)
endif

DOTENVAGE_VERSION_EXPECTED ?= 0.3.3

ifeq ($(DOTENVAGE_VERSION),$(DOTENVAGE_VERSION_EXPECTED))
DOTENVAGE_CHECKED := 1
else
DOTENVAGE_CHECKED := 0
ifneq ($(DOTENVAGE_VERSION),)
$(info dotenvage version $(DOTENVAGE_VERSION) does not match expected version $(DOTENVAGE_VERSION_EXPECTED))
endif
endif

.PHONY: dotenvage-check
ifdef DOTENVAGE_BIN
ifeq ($(DOTENVAGE_CHECKED),1)
dotenvage-check:
	@echo "Using dotenvage $(DOTENVAGE_VERSION)"
else
dotenvage-check: dotenvage-install
endif
else
dotenvage-check: dotenvage-install
endif

#
# Install dotenvage via cargo (preferred method).
# Uses cargo-binstall if available for faster installation,
# otherwise falls back to cargo install.
#
.PHONY: dotenvage-install
dotenvage-install: cargo-check
	@printf "$(bold)Installing dotenvage:$(normal)\n"
	@if command -v cargo-binstall >/dev/null 2>&1; then \
		echo "Installing via cargo-binstall..." ; \
		cargo binstall --no-confirm dotenvage ; \
	else \
		echo "Installing via cargo install..." ; \
		$(CARGO_BIN) +$(RUSTUP_TOOLCHAIN) install --locked dotenvage ; \
	fi

#
# Install dotenvage via cargo install (compile from source).
#
.PHONY: dotenvage-install-cargo
dotenvage-install-cargo: cargo-check
	@printf "$(bold)Installing dotenvage via cargo install:$(normal)\n"
	$(CARGO_BIN) +$(RUSTUP_TOOLCHAIN) install --locked dotenvage

#
# Install dotenvage via cargo-binstall (pre-built binary).
# Requires cargo-binstall to be installed.
#
.PHONY: dotenvage-install-binstall
dotenvage-install-binstall: cargo-check cargo-install-binstall
	@printf "$(bold)Installing dotenvage via cargo-binstall:$(normal)\n"
	cargo binstall --no-confirm dotenvage

#
# Install dotenvage via npm (alternative method).
#
.PHONY: dotenvage-install-npm
dotenvage-install-npm:
	@printf "$(bold)Installing dotenvage via npm:$(normal)\n"
	npm install -g dotenvage

#
# Load environment variables from .env files via dotenvage.
# Uses NODE_ENV to determine which file to load:
#   - NODE_ENV unset/development: .env, .env.local
#   - NODE_ENV=production: .env.production
#   - NODE_ENV=preview: .env.preview
#
# This enables the same Makefile targets to work locally and in CI
# by simply setting NODE_ENV appropriately.
#
ifdef DOTENVAGE_BIN
# Load all environment variables from dotenvage into Make variables
# (load regardless of version - version mismatch is just a warning)
$(eval $(shell $(DOTENVAGE_BIN) dump --make-eval 2>/dev/null))
endif

#
# Install cargo-binstall if not already installed.
#
CARGO_BINSTALL_BIN := $(call where-is-binary,cargo-binstall)

.PHONY: cargo-install-binstall
ifdef CARGO_BINSTALL_BIN
cargo-install-binstall:
	@#echo "cargo-binstall is already installed"
else
cargo-install-binstall: cargo-check
	@printf "$(bold)Installing cargo-binstall:$(normal)\n"
	$(CARGO_BIN) +$(RUSTUP_TOOLCHAIN) install --locked cargo-binstall
endif

#$(info <--- .make/dotenvage.mk)

endif # _MK_DOTENVAGE_MK_
