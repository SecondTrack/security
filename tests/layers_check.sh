#!/bin/sh
# Prüft die Abhängigkeitstabelle aus docs/ARCHITECTURE.md an den #imports.
cd "$(dirname "$0")/.."
allowed() {   # erlaubte Ziel-Ordner je Schicht (die eigene Schicht ist immer erlaubt)
  case $1 in
    App)     echo "UI Domain Support" ;;
    UI)      echo "Domain Model Compat Support" ;;
    Domain)  echo "System Model Compat Support" ;;
    System)  echo "Model Support" ;;
    Model)   echo "Support" ;;
    Compat)  echo "Support" ;;
    Support) echo "" ;;
  esac
}
T=${TMPDIR:-/tmp}/mesh-security-layers; mkdir -p "$T"
find security -name '*.h' | while read h; do echo "$(basename "$h") $(echo "$h" | cut -d/ -f2)"; done > "$T/map"
bad=0
for f in $(find security -name '*.[hm]'); do
  layer=$(echo "$f" | cut -d/ -f2)
  ok="$layer $(allowed "$layer")"
  for inc in $(grep -hoE '^#import "[^"]+"' "$f" | cut -d'"' -f2); do
    target=$(awk -v h="$inc" '$1 == h { print $2 }' "$T/map")
    [ -z "$target" ] && continue
    case " $ok " in *" $target "*) ;; *) echo "FAIL $f ($layer) importiert $inc ($target)"; bad=1 ;; esac
  done
done
# Den Helfer startet nur MeshGuard; die UI darf nie selbst root-Befehle absetzen.
for f in $(grep -rl '^#import "MeshHelper.h"' security); do
  case $f in security/Domain/MeshGuard.m|security/System/MeshHelper.m) ;; *) echo "FAIL $f importiert MeshHelper.h"; bad=1 ;; esac
done
[ $bad = 0 ] && echo "ok  Schichtgrenzen eingehalten"
exit $bad
