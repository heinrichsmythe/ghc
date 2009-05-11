# -----------------------------------------------------------------------------
#
# (c) 2009 The University of Glasgow
#
# This file is part of the GHC build system.
#
# To understand how the build system works and how to modify it, see
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Architecture
#      http://hackage.haskell.org/trac/ghc/wiki/Building/Modifying
#
# -----------------------------------------------------------------------------


# Build docbook docs

define docbook
# $1 = dir
# $2 = docname

$(call clean-target,$1,docbook,$1/$2 $1/$2.pdf $1/$2.ps)

ifeq "$$(BUILD_DOCBOOK_HTML)" "YES"
$(call all-target,$1,html_$1)

.PHONY: html_$1
html_$1 : $1/$2/index.html

$1/$2/index.html: $$($1_DOCBOOK_SOURCES)
	$$(RM) -r $$(dir $$@)
	$$(XSLTPROC) --stringparam base.dir $$(dir $$@) \
	             --stringparam use.id.as.filename 1 \
	             --stringparam html.stylesheet fptools.css \
	             $$(XSLTPROC_LABEL_OPTS) $$(XSLTPROC_OPTS) \
	             $$(DIR_DOCBOOK_XSL)/html/chunk.xsl $1/$2.xml
	cp mk/fptools.css $$(dir $$@)
endif

ifeq "$$(BUILD_DOCBOOK_PS)" "YES"
$(call all-target,$1,ps_$1)

.PHONY: ps_$1
ps_$1 : $1/$2.ps

$1/$2.ps: $$($1_DOCBOOK_SOURCES)
	$$(DBLATEX) $$(DBLATEX_OPTS) $1/$2.xml --ps -o $$@
endif

ifeq "$$(BUILD_DOCBOOK_PDF)" "YES"
$(call all-target,$1,pdf_$1)

.PHONY: pdf_$1
pdf_$1 : $1/$2.pdf

$1/$2.pdf: $$($1_DOCBOOK_SOURCES)
	$$(DBLATEX) $$(DBLATEX_OPTS) $1/$2.xml --pdf -o $$@
endif

endef

