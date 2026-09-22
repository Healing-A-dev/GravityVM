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


.PHONY: compile

compile:
	printf '\033c'
	$(CMD) c $(RELEASE) $(HINTS) -o:gvm main.nim
	@printf '\033[92mCompilation Completed!\n\033[0m'

build:
	$(CMD) c $(RELEASE) $(HINTS) -o:gvm main.nim
	mv gvm $(INSTALL_DIR)$(BINARY_DIR)
