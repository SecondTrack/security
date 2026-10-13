# Erst bei uns testen, dann veröffentlichen

## 1. Am Mac

```sh
sh tests/run.sh                                   # Modell, Passwortregeln, Einrichtung, Texte, Schichten, Helfer-Build
export THEOS=~/theos DEVELOPER_DIR=/Library/Developer/CommandLineTools
make clean package                                # Release (FINALPACKAGE=1); Erfolg nur am Exit-Code ablesen
```

Vor dem Hochladen das fertige .deb entpacken und auf `/Users/`, `/var/folders` und Namen scannen.

## 2. Am Testgerät (iPod .117 oder .28), nie zuerst beim Käufer

Installieren per SSH (`scp -O`, `dpkg -i`) oder per afcclient + Geräte-Terminal (siehe Notizen zu den
iPod-Apps). Danach `ls -l /Applications/MeshSecurity.app/msguard` → `-rwsr-xr-x root wheel`.

Das eigene Testgerät behält normalerweise `alpine` (so gewollt): nach dem Test abschirmen aus.
Der SSH-Schlüssel des Macs bleibt auch mit neuem Passwort gültig.

| Prüfung | erwartet |
|---------|----------|
| `msguard status` aus SSH-Shell als mobile / als root | Exit 2 (abgelehnt) |
| Abschirmen an | Passwort angezeigt; `pfctl -s rules` zeigt Vorlage; SSH von außen zu |
| Probezeit ablaufen lassen | nach 2 min pf aus, `alpine` wieder gültig |
| Behalten, dann Ausnahme SSH | SSH aus dem WLAN geht, mit neuem Passwort |
| Neustart abgeschirmt | Regeln wieder geladen (Boot-Dienst) |
| Neustart in Probezeit | zurückgenommen |
| Abschirmen aus | pf aus, Hash in master.passwd und passwd wieder `alpine` |
| Verbindungen an, Safari öffnen | MobileSafari mit Ziel :443 im Protokoll |
| Notschalter | nichts geht raus oder rein; Wieder verbinden stellt vorherigen Zustand her |
| Paket entfernen | alles zurück, `/var/root/.mesh-security` weg |

Für jede neu gebaute Funktion kommt hier ihr Angriffstest dazu (docs/SECURITY.md).

## 3. Icon wählen

```sh
sh tools/icons/make.sh          # Varianten a, b, c nach tools/icons/out/, Ansicht: tools/icons/preview.html
sh tools/icons/make.sh b        # Variante übernehmen → Resources/Icon.png + Icon@2x.png
```

Icons sind 8 bit RGBA mit gebackenen Ecken (iOS 6 rundet vorgerenderte Icons nicht, Paletten-PNGs
bleiben eckig). Am Gerät nach `uicache` ansehen.

## 4. Veröffentlichen

Erst wenn Abschnitt 2 am Gerät vollständig grün ist: über `~/steam-worker-publish/reboot.py`
(`neu mesh-security security` bzw. `update security`), danach `reboot.py cydia`. Bei neuem Icon den
`?v=`-Wert im Katalog ändern.
