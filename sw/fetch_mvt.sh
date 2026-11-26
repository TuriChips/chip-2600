#!/bin/sh
# Fetch the missingno-vcs-tests acceptance material into build/mvt/ (never committed: rule 9).
#   build/mvt/roms/<sub>/<test>_ntsc.a26   81 prebuilt NTSC ROMs, from ajoneil/missingno (MIT)
#   build/mvt/refs/<sub>/<test>_ntsc.png   27 reference frames, from ajoneil/missingno-vcs-tests (MIT)
# Both come from pinned commits and are checked against sw/mvt-*.sha256. Any mismatch stops the run.
# Usage: sw/fetch_mvt.sh [--build]   --build also rebuilds the ROMs with dasm and compares (needs dasm,
#        and DASM_INC = dasm's machines/atari2600 directory); see docs/mvt-report.md section 2.
set -eu
MVT_URL=https://github.com/ajoneil/missingno-vcs-tests
MVT_COMMIT=891c079976a2f68033ca4af2fe2fd85aaf1906c9
MN_URL=https://github.com/ajoneil/missingno
MN_COMMIT=5e5b8d7dad46355e9bf48b53978d7d91d2ec9e23
here=$(cd "$(dirname "$0")" && pwd)
out=${MVT_DIR:-$here/../build/mvt}
mkdir -p "$out"; out=$(cd "$out" && pwd)

fetch() { # url commit dir
  [ -d "$3/.git" ] || git init -q "$3"
  ( cd "$3"
    git fetch -q --depth 1 "$1" "$2"
    git checkout -q --detach FETCH_HEAD
    [ "$(git rev-parse HEAD)" = "$2" ] || { echo "commit mismatch in $3" >&2; exit 1; } )
}
fetch $MVT_URL $MVT_COMMIT "$out/src-mvt"
fetch $MN_URL $MN_COMMIT "$out/src-missingno"

rm -rf "$out/roms" "$out/refs"; mkdir -p "$out/roms" "$out/refs"
acc="$out/src-missingno/crates/systems/vcs/tests/accuracy/roms"
for s in harness cpu riot tia-render tia-timing collision; do
  mkdir -p "$out/roms/$s" "$out/refs/$s"
  cp "$acc/$s/"*_ntsc.a26 "$out/roms/$s/"
  cp "$out/src-mvt/roms/$s/"*_ntsc.png "$out/refs/$s/" 2>/dev/null || true
done
( cd "$out/roms" && sha256sum -c --quiet "$here/mvt-roms.sha256" )
( cd "$out/refs" && sha256sum -c --quiet "$here/mvt-pngs.sha256" )
echo "MVT ok: $(wc -l < "$here/mvt-roms.sha256") ROMs and $(wc -l < "$here/mvt-pngs.sha256") reference PNGs verified in $out"

if [ "${1:-}" = "--build" ]; then
  : "${DASM_INC:?set DASM_INC to dasm machines/atari2600}"
  n=0
  while read -r _ f; do
    src="$out/src-mvt/roms/${f%_ntsc.a26}.asm"
    dasm "$src" -f3 -I"$out/src-mvt/include" -I"$DASM_INC" -o"$out/rebuilt.a26" >/dev/null
    cmp -s "$out/rebuilt.a26" "$out/roms/$f" || { echo "rebuild differs: $f" >&2; exit 1; }
    n=$((n+1))
  done < "$here/mvt-roms.sha256"
  rm -f "$out/rebuilt.a26"
  echo "dasm rebuild ok: $n ROMs byte-identical"
fi
