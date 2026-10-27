# PDF of the literate docs, typeset with Typst.  Tangled from
# docs/tangles/text/sp-typst.org; edit it there.
#
#   make pdf                          the whole book -> .build/emacs-modular.pdf
#   make file FILE=docs/tangles/ui/sp-writedesk.org     one doc
#   make svgs                         build the figures first (needs Graphviz)
#   make check                        show which tools were found
#   make clean

.RECIPEPREFIX = >
.PHONY: pdf file svgs check clean

EMACS   ?= emacs
TYPST   ?= typst
ROOT    := $(abspath ../..)
BUILD   := $(CURDIR)/.build

# ox-typst and a recent Org from the Elpaca builds of this configuration.
LOAD_PATH ?= $(addprefix -L ,$(wildcard $(ROOT)/var/elpaca/builds/ox-typst $(ROOT)/var/elpaca/builds/org))

BATCH = SP_TYPST_ROOT=$(ROOT) SP_TYPST_EXECUTABLE=$(TYPST) \
        $(EMACS) --batch -Q $(LOAD_PATH) -l $(CURDIR)/export.el

# SVGS=1 builds the figures (docs/Makefile, if it exists) before the book.
pdf: $(if $(SVGS),svgs)
> $(BATCH) -f sp-typst-batch-book

file: $(if $(SVGS),svgs)
> FILE=$(abspath $(FILE)) $(BATCH) -f sp-typst-batch-file

svgs:
> $(if $(wildcard ../Makefile),$(MAKE) -C .. docs,@echo "no docs/Makefile: figures are not built")

check:
> @$(TYPST) --version
> @$(EMACS) --version | head -1
> @echo "load path: $(LOAD_PATH)"

clean:
> rm -rf $(BUILD)
