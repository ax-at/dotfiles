# Dotfiles test + lint entrypoints.
#   make test                    run the full bats suite (bootstraps bats on first run)
#   make test FILE=templates     run only test/templates.bats
#   make test FILTER=oxc         run only tests whose name matches the regex
#   make lint                    shellcheck + shfmt (shell), taplo (toml), oxfmt (everything else)
#   make fmt                     auto-format in place with the same three formatters
#   make check-plugins           validate zsh plugin refs against live GitHub (network)
#   make update-golden           regenerate the committed TOOLS.md from the registry
#   make update-skills           regenerate the committed SKILLS.md from skills.toml
#   make update-ghostty-themes   regenerate the committed Ghostty built-in theme snapshot
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
               scripts/gen-skills.sh \
               scripts/gen-ghostty-themes.sh \
               scripts/check-plugins-live.sh \
               test/lib/bootstrap.sh \
               test/lib/check-crossrefs.sh \
               test/lib/check-skills-crossrefs.sh
BASH_LIBS   := test/lib/isolate.bash test/lib/helpers.bash

.PHONY: test lint fmt check-plugins update-golden update-skills update-ghostty-themes

test:
	@./test/lib/bootstrap.sh
	# </dev/null is defense-in-depth: tests never need stdin, so deny it a TTY.
	@CHEZMOI_BIN=$(CHEZMOI_BIN) $(BATS) $(if $(FILTER),-f '$(FILTER)') $(if $(FILE),test/$(FILE).bats,test/) </dev/null

# Formatting is split three ways, no overlap:
#   shfmt -> shell, scoped to the explicit $(SHELL_FILES)/$(BASH_LIBS) lists
#            (the .chezmoiscripts/*.tmpl are linted post-render, see above).
#   taplo -> *.toml, excludes in taplo.toml (skips chezmoi templates).
#   oxfmt -> everything else (JS/JSON/YAML/HTML/CSS/Markdown), whole-tree walk;
#            config + ignores in .oxfmtrc.json.
lint:
	@shellcheck $(SHELL_FILES)
	@shellcheck --shell=bash $(BASH_LIBS)
	@shfmt -d -i 2 -ci $(SHELL_FILES) $(BASH_LIBS)
	@taplo fmt --check --diff
	@oxfmt --check .
	@actionlint

# Auto-format in place — same division of labour as `lint`, but writing.
fmt:
	@shfmt -w -i 2 -ci $(SHELL_FILES) $(BASH_LIBS)
	@taplo fmt
	@oxfmt --write .

check-plugins:
	@./scripts/check-plugins-live.sh

update-golden:
	@./scripts/gen-tools.sh

update-skills:
	@./scripts/gen-skills.sh

update-ghostty-themes:
	@./scripts/gen-ghostty-themes.sh
