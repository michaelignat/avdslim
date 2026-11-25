PREFIX ?= $(HOME)/.local

.PHONY: install check test lint release

install:
	mkdir -p $(PREFIX)/bin
	ln -sf $(CURDIR)/avdslim $(PREFIX)/bin/avdslim

check: lint test

lint:
	shellcheck -s bash avdslim test/test.sh

test:
	test/test.sh

# Usage: make release VERSION=0.3.0  (GitHub Actions publishes the release)
release: check
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z"; exit 2; }
	@test "$$(git branch --show-current)" = main || { echo "release from main"; exit 2; }
	@test -z "$$(git status --porcelain)" || { echo "working tree not clean"; exit 2; }
	sed -i '' 's/^AVDSLIM_VERSION=".*"/AVDSLIM_VERSION="$(VERSION)"/' avdslim
	git diff --quiet || git commit -qam "Release v$(VERSION)"
	git tag v$(VERSION)
	git push origin main v$(VERSION)
