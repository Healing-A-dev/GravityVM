CMD = nim
RELEASE = -d:release
HINTS = --hints:on
HINTS = --hints:on
WARNINGS = -w:off


INSTALL_DIR= $(HOME)/.local
LIBRARY_DIR= /lib/gvm
BINARY_DIR= /bin

CXX = clang
CFLAGS = -c -static -Wall -Wextra
RUNTIME = lib/gvm_runtime.c
RUNTIME_NAME = gvm.o
CACHE_FILE = $(HOME)/.cache/GravityVM/.config


.PHONY: compile

compile:
	printf '\033c'
	$(CMD) c $(RELEASE) $(HINTS) -o:gvm main.nim
	@printf '\033[92mCompilation Completed!\n\033[0m'

build:
	@if [ ! -d $(HOME)/.cache/GravityVM ]; then \
		mkdir -p $(HOME)/.cache/GravityVM; \
	fi
	@if [ ! -f $(HOME)/.cache/GravityVM/.config ]; then \
		touch $(HOME)/.cache/GravityVM/.config; \
		echo 'MAX_ENTRIES = 9' >> $(HOME)/.cache/GravityVM/.config; \
		echo 'COMPARE_CACHE = 0' >> $(HOME)/.cache/GravityVM/.config; \
	fi
	$(CMD) c $(RELEASE) $(HINTS) -o:gvm main.nim
	mv gvm $(INSTALL_DIR)$(BINARY_DIR)
