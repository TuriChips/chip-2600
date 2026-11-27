# RTL file list for TOP, paths relative to the repo root. Used by `make lint`.
# Tops (spec §2): m6532 (RIOT), tia, a2600 (whole machine). Select with: make lint TOP=<name>
# Only files that exist and belong to TOP are listed; add the others as their PRs land.
# The 6507 core (rtl/cpu/, chip-2600#2) joins when it is merged, for TOP=a2600.
rtl/datapath/m6532.v
rtl/datapath/tia_pgfx.v
rtl/datapath/tia_mbgfx.v
rtl/control/tia_prio.v
