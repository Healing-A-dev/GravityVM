RELEASE = -d:debug
HINTS = --hints:off
WARNINGS = -w:off

DESTDIR = /usr/local/bin
CMD = nim

.PHONY: compile

compile: main.nim
	printf '\033c'
	$(CMD) c $(RELEASE) $(HINTS) -o:gravity main.nim
	@printf '\033[92mCompilation Completed!\n\033[0m'

build:
	$(CMD) c $(RELEASE) $(HINTS) -o:gravity main.nim
	sudo mv gravity $(DESTDIR)
