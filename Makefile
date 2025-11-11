RELEASE = -d:debug
HINTS = --hints:off
WARNINGS = -w:off
CMD = nim


.PHONY: exec


compile: main.nim
	printf '\033c'
	$(CMD) c $(RELEASE) $(HINTS) -o:gravity main.nim
	@printf '\033[92mCompilation Completed!\n\033[0m'
