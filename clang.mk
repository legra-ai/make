ifndef _MK_CLANG_MK_
_MK_CLANG_MK_ := 1

#$(info ---> .make/clang.mk)

ifndef GIT_ROOT
GIT_ROOT := $(shell git rev-parse --show-toplevel 2>/dev/null)
endif
ifndef MK_DIR
MK_DIR := $(GIT_ROOT)/.make
endif

include $(MK_DIR)/os.mk
include $(MK_DIR)/git.mk
include $(MK_DIR)/os-tools-*.mk
include $(MK_DIR)/rustup.mk
include $(MK_DIR)/brew.mk
include $(MK_DIR)/curl.mk
include $(MK_DIR)/llvm.mk

CLANG_VERSION := $(shell clang --version 2>/dev/null | head -n1 | cut -d\  -f4)
ifdef CLANG_VERSION
#$(info CLANG_VERSION=$(CLANG_VERSION))
CLANG_MAIN_VERSION := $(shell echo $(CLANG_VERSION) | cut -d. -f1)
#$(info CLANG_MAIN_VERSION=$(CLANG_MAIN_VERSION))
else
$(warning LLVM CLANG is not installed)
endif

CLANG_MAIN_VERSION_EXPECTED := 22

.PHONY: clang-check
ifndef CLANG_VERSION
clang-check: clang-install
else
ifneq ($(CLANG_MAIN_VERSION),$(CLANG_MAIN_VERSION_EXPECTED))
$(info CLANG_MAIN_VERSION ($(CLANG_MAIN_VERSION)) is not equal to CLANG_MAIN_VERSION_EXPECTED ($(CLANG_MAIN_VERSION_EXPECTED)))
clang-check: clang-install
else
#$(info CLANG_MAIN_VERSION is equal to CLANG_MAIN_VERSION_EXPECTED)
CLANG_INSTALL := 0
clang-check:
	@echo Using LLVM CLANG ${CLANG_VERSION}
endif
endif

ifndef LIBCLANG_PATH
ifdef LLVM_LIB_PATH
LIBCLANG_PATH := $(LLVM_LIB_PATH)
else
LIBCLANG_PATH := /usr/local/opt/llvm/lib
endif
endif

ifndef LIBCLANG_PATH
$(warning LIBCLANG_PATH is not defined)
endif

ifeq ("$(wildcard $(LIBCLANG_PATH))","")
$(info Directory LIBCLANG_PATH=$(LIBCLANG_PATH) does not exist)
endif

# LIBCLANG_BIN_PATH is something like: /usr/local/opt/llvm/bin/
export LIBCLANG_BIN_PATH := $(shell cd $(LIBCLANG_PATH) 2>/dev/null && cd ../bin && pwd)
#$(info LIBCLANG_BIN_PATH=$(LIBCLANG_BIN_PATH))

# LIBCLANG_INCLUDE_PATH is something like: /usr/local/opt/llvm/include
export LIBCLANG_INCLUDE_PATH := $(shell cd $(LIBCLANG_PATH) 2>/dev/null && cd ../include && pwd)
#$(info LIBCLANG_INCLUDE_PATH=$(LIBCLANG_INCLUDE_PATH))

export LDFLAGS="-L$(LIBCLANG_PATH)/c++ -Wl,-rpath,$(LIBCLANG_PATH)/c++"
export CPPFLAGS="-I$(LIBCLANG_INCLUDE_PATH)"

export CC=clang
export CXX=clang

ifeq ($(UNAME_S),Darwin)
export BINDGEN_EXTRA_CLANG_ARGS="-I /Library/Developer/CommandLineTools/usr/include/c++/v1 -I /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include"
endif

LLVM_VERSION := $(shell "$(LIBCLANG_BIN_PATH)/llvm-config" --version 2>/dev/null)

.PHONY: clang-install
ifeq ($(CLANG_INSTALL),0)
clang-install:
else
.INTERMEDIATE: ./clang-install.sh
./clang-install.sh: curl-check
	@echo "Downloading LLVM install script:"
	$(CURL_BIN) -fsSL https://apt.llvm.org/llvm.sh > ./clang-install.sh
	chmod u+x ./clang-install.sh

ifeq ($(UNAME_S),Windows)
clang-install:
else
ifeq ($(UNAME_S),Darwin)
clang-install: brew-check
	@if [ ! -d $(HOMEBREW_CELLAR)/z3/4.12.* ] ; then $(BREW_BIN) install z3 ; else echo "z3 4.12.* is already installed" ; fi
	@if [ ! -d $(HOMEBREW_CELLAR)/llvm/16.* ] ; then $(BREW_BIN) install llvm ; else echo "llvm 16.* is already installed" ; fi
	@if [ ! -d $(HOMEBREW_CELLAR)/protobuf/23.* ] ; then $(BREW_BIN) install protobuf ; else echo "protobuf 23.* is already installed" ; fi
else # anything else: linux
clang-install: ./clang-install.sh
	@echo "Executing LLVM install script"
	sudo ./clang-install.sh $(CLANG_MAIN_VERSION_EXPECTED)
	@echo "LLVM install script finished successfully"
	clang-$(CLANG_MAIN_VERSION_EXPECTED) --version
	@echo "LLVM version $(CLANG_MAIN_VERSION_EXPECTED) has been installed"
endif
endif
endif

.PHONY: llvm-check
llvm-check: clang-check

#$(info <--- .make/clang.mk)

endif # _MK_CLANG_MK_
