# Build the diagrams used by the Org docs.
#
# Every `#+begin_src dot :file NAME.svg' block in docs/**/*.org is the source
# of NAME.svg, written next to the .org file.  The .svg files are not
# committed (see ../.gitignore): CI builds and publishes them to the
# docs-assets branch (.github/workflows/docs-svg.yml).  Run `make docs'
# for a local copy; it needs Graphviz (`dot').

DOT     ?= dot
BUILD   := .build
ORGS    := $(shell find . -name '*.org' -not -path './$(BUILD)/*' -exec grep -l '^\#+begin_src dot .*:file ' {} +)

.PHONY: docs clean
docs:
	@command -v $(DOT) >/dev/null || { echo "Graphviz ($(DOT)) not found" >&2; exit 1; }
	@for org in $(ORGS); do \
	  dir=$$(dirname $$org); \
	  mkdir -p $(BUILD)/$$dir; \
	  awk -v out=$(BUILD)/$$dir '\
	    /^#\+begin_src dot .*:file / { for (i = 1; i <= NF; i++) if ($$i == ":file") f = $$(i+1); sub(/\.svg$$/, "", f); file = out "/" f ".dot"; printf "" > file; next } \
	    /^#\+end_src/ { if (file) close(file); file = ""; next } \
	    file { print > file }' $$org; \
	done
	@find $(BUILD) -name '*.dot' | while read -r src; do \
	  rel=$${src#$(BUILD)/}; svg=$${rel%.dot}.svg; \
	  echo "$$svg"; $(DOT) -Tsvg "$$src" -o "$$svg" || exit 1; \
	done

clean:
	rm -rf $(BUILD)
	find . -name '*.svg' -path './architecture/*' -delete
