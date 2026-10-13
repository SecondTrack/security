# Sicherheit

## Bedrohungsmodell

| Angreifer | Weg | Was Mesh Security dagegen tut |
|-----------|-----|-------------------------------|
| Wurm im WLAN (ikee-Typ) | SSH-Login mit `alpine` | neues Passwort für root und mobile (2), Port 22 von außen zu (3) |
| Fremder im selben WLAN | offene Dienste (SSH, AFC2, Dateien-App) | eingehend alles zu (3) |
| App, die nach Hause telefoniert | ausgehende Verbindung | ausgehend nur Mesh über Tor und Freigaben (3), sichtbar im Protokoll (4) |
| Akuter Verdacht | — | Notschalter trennt alles sofort (5) |
| Kompromittierte App Mesh Security | ruft msguard mit eigenen Argumenten | msguard prüft jedes Argument, Regeln nur aus fester Vorlage |
| Fremder Prozess als mobile | ruft msguard direkt | msguard nimmt nur die echte App als Elternprozess an |

**Was wenn root schon kompromittiert ist?** Dann hilft keine App auf demselben Gerät; ein Angreifer
mit root kann pf, msguard und das Protokoll ändern. Mesh Security senkt die Wahrscheinlichkeit, dass
es so weit kommt. Es ist kein Schutz danach. So steht es auch in der App, nicht „komplett sicher“.

## msguard (setuid root)

- **Aufrufer:** reale UID mobile, Elternprozess ist die App (`realpath`-Vergleich, weil Cydia
  `/Applications` nach `/var/stash` verschiebt), Eltern nicht `P_TRACED`, keine `DYLD_*`-Variablen.
  root darf nur `boot` (launchd) und `uninstall` (dpkg); root kann ohnehin alles.
- **Eingaben:** feste Befehlsliste; Ausnahmen nur `tcp|udp` und Port 1–65535 (strtol, ganze Zeichenkette),
  höchstens 16. Regeln aus fester Vorlage, Ausnahmen nur aus dem eigenen WLAN (`en0:network`).
- **Programme:** `pfctl` per `posix_spawn` mit argv und fester Umgebung, nie über eine Shell.
- **Zustand:** `/var/root/.mesh-security/` (0700 root, kein Symlink). Dateien atomar (tmp, fsync, rename).
- **Nie aussperren:** Abschirmen gilt erst nach „Behalten“; sonst nimmt ein abgekoppelter Wächter es nach
  `MG_TRIAL_SECS` zurück. Eine nach einem Neustart noch offene Probezeit gilt als nicht bestätigt.
- **Fremde Firewall:** ist pf schon aktiv, fasst msguard nichts an (`MG_ERR_FOREIGN`).

## Passwort

iOS 6 speichert den Hash in `/etc/master.passwd` **und** `/etc/passwd`; beide werden geändert. DES-`crypt`:
nur 8 Zeichen zählen. Beim Abschirmen bekommen nur Konten mit `alpine` (oder leerem Passwort) ein
erzeugtes Passwort (8 Zeichen aus 55, ohne Verwechsler, `arc4random_uniform`), dasselbe für root und
mobile. Vorher wird `<konto> <alter hash> <neuer hash>` gemerkt; die Rücknahme setzt den alten Hash nur
dort zurück, wo noch der neue steht (hat jemand das Passwort inzwischen selbst geändert, bleibt es).
Das Klartext-Passwort liegt nur solange abgeschirmt in der root-Datei, damit die App es zeigen kann.

**Bewusste Entscheidung des Nutzers:** Ausschalten stellt auch `alpine` wieder her.

## Verbindungen

Ein abgekoppelter Prozess (root) fragt alle 2 s die Sockets **aller** Prozesse ab (`proc_pidinfo`/
`proc_pidfdinfo`, Header aus dem macOS-SDK in helper/include) und schreibt neue Verbindungen ins
Protokoll (256 KB, dann ältere Hälfte weg). Eingehend = lokaler Port, auf dem derselbe Prozess lauscht.
Sehr kurze Verbindungen zwischen zwei Abfragen können fehlen. Das Protokoll verlässt den iPod nie.

## Grenzen

- Eingehend wird alles gesperrt. Ausgehend lässt sich nach Ziel (Adresse/Port) sperren, nicht nach App:
  alle Apps und Mesh-Tor laufen als mobile. pf versteht `user` in Regeln (am Gerät geprüft); für „nur
  Mesh über Tor“ bräuchte Tor einen eigenen Nutzer. Sperren je App ginge nur mit Substrate.
- Wer schon root hat, kann alles davon ändern.

## Angriffstests

Siehe docs/TESTING.md; jede Maßnahme wird am Gerät tatsächlich angegriffen.
