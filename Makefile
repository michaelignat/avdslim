PREFIX ?= $(HOME)/.local

.PHONY: install check test lint

install:
	mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/avdslim $(PREFIX)/bin/avdslim

check: lint test

lint:
	shellcheck -s bash avdslim test/test.sh

test:
	test/test.sh
