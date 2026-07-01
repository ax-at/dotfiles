# Dotfiles test + lint entrypoints.
#   make test                    run the full bats suite (bootstraps bats on first run)
#   make test FILE=templates     run only test/templates.bats
#   make test FILTER=oxc         run only tests whose name matches the regex
#   make lint                    shellcheck + shfmt on the plain shell scripts
#   make update-golden           regenerate the committed TOOLS.md from the registry
#
# On a machine provisioned by this repo, chezmoi + bats are already on PATH
# (both are brew formulae in the registry), so these targets need no setup.
# CHEZMOI_BIN overrides the chezmoi binary if it isn't on PATH.

CHEZMOI_BIN ?= chezmoi
BATS        := ./test/lib/bats-core/bin/bats

# Optional focus knobs for `make test` (empty = whole suite):
#   FILE   — a suite basename under test/ (FILE=templates -> test/templates.bats)
#   FILTER — a regex matched against test names (passed to bats -f)
FILE   ?=
FILTER ?=

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
	# </dev/null is defense-in-depth: tests never need stdin, so deny it a TTY.
	@CHEZMOI_BIN=$(CHEZMOI_BIN) $(BATS) $(if $(FILTER),-f '$(FILTER)') $(if $(FILE),test/$(FILE).bats,test/) </dev/null

lint:
	@shellcheck $(SHELL_FILES)
	@shellcheck --shell=bash $(BASH_LIBS)
	@shfmt -d -i 2 -ci $(SHELL_FILES) $(BASH_LIBS)
	@actionlint

update-golden:
	@./scripts/gen-tools.sh
