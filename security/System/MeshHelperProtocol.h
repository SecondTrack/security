/* Absprache zwischen App und Helfer (helper/msguard.c). Reines C: der Helfer bindet es mit ein.
 *
 * Aufruf:  msguard <befehl> [argumente]     Antwort: key=value-Zeilen bzw. Tab-Zeilen auf stdout
 */
#ifndef MESH_HELPER_PROTOCOL_H
#define MESH_HELPER_PROTOCOL_H

#define MG_HELPER_NAME   "msguard"
#define MG_APP_BINARY    "/Applications/MeshSecurity.app/MeshSecurity"

/* Befehle der App */
#define MG_CMD_STATUS    "status"    /* helper, shield, pf, cut, log, alpine_root, alpine_mobile, ssh, pw, except, blocked, apps (erlaubte) */
#define MG_CMD_SHIELD    "shield"    /* on|off. on: Passwort sichern (falls alpine), eingehend alles zu.
                                        off: alles zurück, auch das Passwort */
#define MG_CMD_PASSWORD  "password"  /* pw=<erzeugtes Passwort>, solange abgeschirmt */
#define MG_CMD_EXCEPT    "except"    /* add|del tcp|udp <port>: eingehend aus dem eigenen WLAN erlauben */
#define MG_CMD_BLOCK     "block"     /* add|del <ipv4|ipv6>: Ziel ausgehend sperren (für alle Apps), solange abgeschirmt */
#define MG_CMD_APP       "app"       /* allow|block <prozessname>: darf die App raus? Abgeschirmt darf nur, wer erlaubt ist */
#define MG_CMD_CUT       "cut"       /* on|off: Notschalter, trennt alles in beide Richtungen */
#define MG_CMD_LOG       "log"       /* on|off: Verbindungen pro Prozess mitschreiben */
#define MG_CMD_CONNS     "conns"     /* Protokoll, eine Verbindung je Zeile (MeshConnection) */
#define MG_CMD_RESET     "reset"     /* alles zurück und alle Einstellungen weg */

/* Befehle nur für root (launchd beim Start, dpkg beim Entfernen) */
#define MG_CMD_BOOT      "boot"      /* Regeln nach Neustart wieder laden, offene Probezeit zurücknehmen */
#define MG_CMD_UNINSTALL "uninstall" /* wie reset */

/* Rückgabewerte (Exit-Code) */
#define MG_OK            0
#define MG_ERR_USAGE     1
#define MG_ERR_CALLER    2           /* Aufrufer ist nicht die echte App */
#define MG_ERR_PRIV      3           /* root-Rechte fehlen (setuid nicht gesetzt) */
#define MG_ERR_PF        4           /* Firewall nicht ansprechbar */
#define MG_ERR_FOREIGN   5           /* pf hat fremde Regeln: nicht anfassen */
#define MG_ERR_IO        6
#define MG_ERR_RULES     7           /* Regeln ließen sich nicht laden; Ursprung wiederhergestellt */
#define MG_ERR_PASSWORD  8           /* Passwort ließ sich nicht setzen; Ursprung wiederhergestellt */
#define MG_ERR_LIMIT     9           /* zu viele Ausnahmen */

#define MG_MAX_EXCEPT    16
#define MG_MAX_BLOCKED   64

#endif
