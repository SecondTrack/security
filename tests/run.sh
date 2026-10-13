#!/bin/sh
# Alle Mac-Tests. Jede Suite wird gebaut und ausgeführt; am Ende eine Übersicht.
# Exit-Code 0 nur, wenn jede Suite gebaut wurde und bestanden hat.
if ! xcrun --find clang >/dev/null 2>&1 && [ -d /Library/Developer/CommandLineTools ]; then
  export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
cd "$(dirname "$0")/.."
OUT=$(mktemp -d "${TMPDIR:-/tmp}/mesh-security-tests.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
FAILED=""
BASE="-fobjc-arc -framework Foundation -Wall -Wno-deprecated-declarations -Itests -Isecurity/Support"

suite() {
  name=$1; test=$2; shift 2
  echo "-- $name"
  bin="$OUT/$(basename "$test" .m)"
  if ! clang $BASE "$@" -o "$bin" "$test"; then FAILED="$FAILED\n  $name (Build)"; return; fi
  "$bin" || FAILED="$FAILED\n  $name"
}

suite "Zustand/Protokoll"  tests/model_test.m  -Isecurity/Model -Isecurity/System \
                           security/Model/MeshGuardStatus.m security/Model/MeshConnection.m security/Model/MeshException.m security/Model/MeshAppActivity.m security/System/MeshHelper.m
echo "-- Helfer (Mac-Build, nur Kompilieren)"
clang -Wall -Werror -Isecurity/System -Ihelper/include -o "$OUT/msguard" helper/msguard.c || FAILED="$FAILED\n  Helfer (Build)"

echo "-- Texte"
sh tests/strings_check.sh || FAILED="$FAILED\n  Texte"

echo "-- Schichten"
sh tests/layers_check.sh || FAILED="$FAILED\n  Schichten"

if [ -n "$FAILED" ]; then printf "\nFEHLGESCHLAGEN:$FAILED\n"; exit 1; fi
echo; echo "Alle Suites bestanden."
