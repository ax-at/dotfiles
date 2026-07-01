# Dotfiles test + lint entrypoints.
#   make test           run the full bats suite (bootstraps bats on first run)
#   make lint           shellcheck + shfmt on the plain shell scripts
#   make update-golden  regenerate the committed TOOLS.md from the registry
#
# CHEZMOI_BIN overrides the chezmoi binary if it isn't on PATH.

CHEZMOI_BIN ?= chezmoi
BATS        := ./test/lib/bats-core/bin/bats

# Plain shell scripts (the .chezmoiscripts/*.tmpl are linted, post-render, by
# test/rendered_shellcheck.bats since raw templates aren't valid shell).
SHELL_FILES := install \
               scripts/gen-tools.sh \
               test/lib/bootstrap.sh \
               test/lib/check-crossrefs.sh
BASH_LIBS   := test/lib/isolate.bash test/lib/helpers.bash

.PHONY: test lint update-golden

test:
	@./test/lib/bootstrap.sh
	@CHEZMOI_BIN=$(CHEZMOI_BIN) $(BATS) test/ </dev/null

lint:
	@shellcheck $(SHELL_FILES)
	@shellcheck --shell=bash $(BASH_LIBS)
	@shfmt -d -i 2 -ci $(SHELL_FILES) $(BASH_LIBS)
	@actionlint

update-golden:
	@./scripts/gen-tools.sh
