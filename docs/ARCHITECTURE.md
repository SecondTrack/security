# Architektur

Mesh Security schützt einen gejailbreakten iPod touch (iOS 5.0 bis 6.1, ARMv7). Aufbau, Stil und
Regeln sind von Mesh (`~/steam-worker/mesh-ios`) übernommen; die UI-Bausteine sind dieselben.

## Zwei Programme

```
MeshSecurity.app/MeshSecurity   App, läuft als mobile. Zeigt an, fragt nach, ändert selbst nichts.
MeshSecurity.app/msguard        setuid-root-Helfer. Einzige Stelle mit root-Rechten.
```

Die App startet `msguard <befehl>` und liest `key=value`-Zeilen zurück. Befehle, Rückgabewerte und
Grenzwerte stehen an einer Stelle: `security/System/MeshHelperProtocol.h` (reines C, beide Seiten
binden es ein). Passwörter gehen über stdin, nie über argv.

## Schichten

```
App          AppDelegate, main
UI/*         Home (eine Seite: MeshShieldButton, Passwort, Ausnahmen, Mehr), Traffic (+ MeshConnectionCell)
UI/Common    aus Mesh: MeshTheme, MeshScreen, MeshTopBar, MeshPageHeader, MeshMenuRow, MeshControls,
             MeshPopup, MeshGlyphs (Schutz-Symbole und Schild-Logo neu)
Domain       MeshGuard (Fassade für die UI)
System       MeshHelper (startet msguard), MeshHelperProtocol.h
Model        MeshGuardStatus, MeshException, MeshConnection
Compat       MeshCompat (iOS-Versionsweichen)
Support      MeshL10n, MeshLog, MeshNotifications
```

| Schicht | darf benutzen |
|---------|---------------|
| App     | UI, Domain, Support |
| UI      | Domain, Model, Compat, Support |
| Domain  | System, Model, Compat, Support |
| System  | Model, Support |
| Model   | Support |
| Compat  | Support |
| Support | — |

`tests/layers_check.sh` prüft die Tabelle an den `#import`-Zeilen und zusätzlich, dass nur
`MeshGuard` den Helfer startet. Die UI kennt weder Helfer noch pf noch Dateien.

## Bedienung

Eine Seite. Der große Schild-Schalter schirmt ab bzw. nimmt alles zurück:

- **an:** Konten mit `alpine` bekommen ein erzeugtes Passwort (angezeigt), eingehend geht alles zu
  (pf), ausgehend nur erlaubte Apps (Mesh mit Tor ist vorab erlaubt). Keine Probezeit, keine Rückfrage.
- **aus:** pf wie vorher, Passwort wieder wie vorher (auch `alpine`, so gewollt).
- **Ausnahmen:** Ports, die aus dem eigenen WLAN erreichbar bleiben (SSH, FileTransfer, eigener Port).
- **Mehr:** Verbindungen pro App mitschreiben, Notschalter (trennt alles), Alles zurücksetzen.

Ein LaunchDaemon (`de.mesh.security.boot`) lädt die Regeln nach einem Neustart neu.

## Konventionen

Wie in Mesh: Klassen der Schichten und Bausteine heißen `Mesh…`, View-Controller nicht. Kommentare
auf Deutsch, Bezeichner auf Englisch. Privater Zustand als Ivars im `@implementation`-Block. Layout
aus UI/Common, Maße und Farben aus `MeshTheme`. Alles Sichtbare über `L()`/`LF()`, Schlüssel ist der
englische Text (`tests/strings_check.sh`).

## Threads

- **Main-Thread:** UI, `MeshGuard`-Zustand, alle Callbacks.
- **Serielle Queue `de.mesh.security.helper`:** jeder Helfer-Aufruf; danach wird der Status neu gelesen
  und `MeshGuardChangedNotification` auf Main verschickt.
