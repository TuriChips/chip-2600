# Bump TOOLCHAIN_REF on purpose, never track main. Bump the @tag in .github/workflows/*.yml with it.
TOOLCHAIN_REF ?= v0.10.2
# Selectable tops (spec §2): m6532 (RIOT, first), tia, a2600.
TOP ?= m6532
TC := .toolchain
ifeq (,$(wildcard $(TC)/chip.mk))
$(shell rm -rf $(TC); gh repo clone TuriChips/toolchain $(TC) -- -q --depth 1 --branch $(TOOLCHAIN_REF))
endif
ifneq (,$(TOOLCHAIN_REF))
ifeq (,$(filter $(TOOLCHAIN_REF),$(shell git -C $(TC) tag --points-at HEAD 2>/dev/null)))
$(error toolchain mismatch: Makefile pins $(TOOLCHAIN_REF) but $(TC) is a different version. Run: rm -rf $(TC))
endif
endif
export TOP
include $(TC)/chip.mk

# Verilator lint of TOP over rtl/files.f (the toolchain has no lint target in $(TOOLCHAIN_REF)).
# Only the tops whose RTL exists can be linted: tia and a2600 fail here until their RTL lands.
.PHONY: lint
lint:
	verilator --lint-only -Wall --top-module $(TOP) -f rtl/files.f
