/* msguard — setuid-root-Helfer von Mesh Security. Einzige Stelle mit root-Rechten.
 *
 * Befehle und Rückgabewerte: security/System/MeshHelperProtocol.h. Grundsätze (docs/SECURITY.md):
 *  - Aufrufer muss die echte App sein: Elternprozess = MG_APP_BINARY, läuft als mobile, wird nicht
 *    debuggt, hat keine DYLD_-Variablen. root darf nur "boot" und "uninstall".
 *  - Nichts vom Aufrufer landet ungeprüft in Regeln oder Dateien; Programme werden mit argv und
 *    fester Umgebung gestartet, nie über eine Shell.
 *  - Vor jeder Änderung wird der Ursprung gemerkt (STATE_DIR, nur root); "shield off" und "reset"
 *    stellen ihn her.
 *  - Nie aussperren: SSH und alles andere von außen lässt sich per Ausnahme öffnen; aus schaltet die App
 *    auf dem Gerät selbst (Nutzerwunsch: einfach an/aus, keine Probezeit).
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <time.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <dirent.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/sysctl.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/proc_info.h>
#include "MeshHelperProtocol.h"

#define MOBILE_UID  501
#define STATE_DIR   "/var/root/.mesh-security"
#define JOURNAL     STATE_DIR "/journal"      /* pf_was=enabled|disabled, beim ersten Eingriff */
#define SHIELD_FILE STATE_DIR "/shield"       /* vorhanden: abgeschirmt */
#define TRIAL_FILE  STATE_DIR "/trial"        /* Altlast der Probezeit (bis 0.3.1): wird nur noch entfernt */
#define CUT_FILE    STATE_DIR "/cut"          /* vorhanden: Notschalter an */
#define PW_FILE     STATE_DIR "/password"     /* erzeugtes Passwort (nur solange abgeschirmt) */
#define HASH_FILE   STATE_DIR "/hashes"       /* <konto> <alter hash> <neuer hash>, je Zeile */
#define EXC_FILE    STATE_DIR "/exceptions"   /* <tcp|udp> <port>, je Zeile; bleibt über an/aus erhalten */
#define BLOCK_FILE  STATE_DIR "/blocked"      /* gesperrte Ziele, eine Adresse je Zeile; bleibt über an/aus erhalten */
#define APPS_FILE   STATE_DIR "/apps"         /* zusätzlich erlaubte Apps (Prozessname), eine je Zeile */
#define AUTO_FILE   STATE_DIR "/auto"         /* gelernte Ziele erlaubter Apps: "<adresse> <app>", vom Mitschreiber gepflegt */
#define LOG_FLAG    STATE_DIR "/log"          /* vorhanden: mitschreiben (auch nach Neustart) */
#define LOG_PID     STATE_DIR "/logger.pid"
#define CONNS_FILE  STATE_DIR "/conns"
#define ERR_FILE    STATE_DIR "/error"        /* letzter Fehler: Schritt, errno (Diagnose, nur root) */
#define PF_CONF     STATE_DIR "/pf.conf"
#define PFCTL       "/sbin/pfctl"
#define MASTER_PW   "/etc/master.passwd"
#define PLAIN_PW    "/etc/passwd"             /* iOS 6 hat den Hash auch hier */
#define CONNS_MAX   (256 * 1024)
#define POLL_SECS   1
#define MAX_AUTO    2048
#define NAME_MAX_LEN 32

int proc_pidpath(int pid, void *buffer, uint32_t buffersize);
int proc_listpids(uint32_t type, uint32_t typeinfo, void *buffer, int buffersize);
int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);
int proc_pidfdinfo(int pid, int fd, int flavor, void *buffer, int buffersize);
int proc_name(int pid, void *buffer, uint32_t buffersize);
#ifndef PROC_ALL_PIDS
#define PROC_ALL_PIDS 1
#endif

static char *cleanEnv[] = { "PATH=/usr/sbin:/usr/bin:/sbin:/bin", "HOME=/var/root", "LANG=C", NULL };

/* ---------- Aufrufer ---------- */

/* Einzige erlaubte DYLD_-Variable: DYLD_INSERT_LIBRARIES, wenn darin nur Cydia Substrate steht (so lädt
 * Substrate sich unter iOS 5/6 in jede App). Jede Bibliothek muss aufgelöst unter
 * /Library/Frameworks/CydiaSubstrate.framework/ oder /Library/MobileSubstrate/ liegen, root gehören und
 * für niemand anderen beschreibbar sein. Alles andere (eigene Bibliotheken, DYLD_LIBRARY_PATH …) bleibt verboten. */
static int hasPrefixStr(const char *s, const char *p) { return strncmp(s, p, strlen(p)) == 0; }
static int trustedDyld(const char *kv) {
    const char *key = "DYLD_INSERT_LIBRARIES=";
    if (!hasPrefixStr(kv, key)) return 0;
    const char *val = kv + strlen(key);
    char list[1024];
    size_t n = strlen(val);
    if (n == 0 || n >= sizeof list) return 0;
    memcpy(list, val, n + 1);
    char *save = NULL;
    for (char *p = strtok_r(list, ":", &save); p; p = strtok_r(NULL, ":", &save)) {
        char real[PATH_MAX]; struct stat st;
        if (!realpath(p, real)) return 0;
        if (!hasPrefixStr(real, "/Library/Frameworks/CydiaSubstrate.framework/") && !hasPrefixStr(real, "/Library/MobileSubstrate/")) return 0;
        if (lstat(real, &st) != 0 || !S_ISREG(st.st_mode) || st.st_uid != 0 || (st.st_mode & 022)) return 0;
    }
    return 1;
}

static int noDyldVars(pid_t pid) {
    int argmax = 0; size_t sz = sizeof argmax;
    int mib[2] = { CTL_KERN, KERN_ARGMAX };
    if (sysctl(mib, 2, &argmax, &sz, NULL, 0) != 0 || argmax <= 0) return 0;
    char *buf = malloc((size_t)argmax);
    if (!buf) return 0;
    int mpa[3] = { CTL_KERN, KERN_PROCARGS2, pid };
    sz = (size_t)argmax;
    int ok = sysctl(mpa, 3, buf, &sz, NULL, 0) == 0;
    for (size_t i = sizeof(int); ok && i < sz; ) {
        size_t n = strnlen(buf + i, sz - i);
        if (n >= 5 && strncmp(buf + i, "DYLD_", 5) == 0 && !trustedDyld(buf + i)) ok = 0;
        i += n + 1;
    }
    free(buf);
    return ok;
}

static int appCaller(void) {
    if (getuid() != MOBILE_UID) return 0;
    pid_t pp = getppid();
    // Beide Pfade aufgelöst vergleichen: Cydia verschiebt /Applications nach /var/stash/… (Symlink),
    // und der Kern meldet den echten Pfad. Beide Ziele kann nur root ändern.
    char path[1024] = { 0 }, real[PATH_MAX], expected[PATH_MAX];
    if (proc_pidpath(pp, path, sizeof path) <= 0) return 0;
    if (!realpath(path, real) || !realpath(MG_APP_BINARY, expected) || strcmp(real, expected) != 0) return 0;
    struct kinfo_proc kp; size_t len = sizeof kp;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pp };
    if (sysctl(mib, 4, &kp, &len, NULL, 0) != 0 || len == 0) return 0;
    if (kp.kp_eproc.e_ucred.cr_uid != MOBILE_UID || (kp.kp_proc.p_flag & P_TRACED)) return 0;
    return noDyldVars(pp) && noDyldVars(getpid());
}

/* ---------- Dateien ---------- */

static int exists(const char *path) { struct stat st; return lstat(path, &st) == 0 && S_ISREG(st.st_mode); }

static int readSmall(const char *path, char *buf, size_t len) {
    int fd = open(path, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return -1;
    size_t n = 0; ssize_t r;
    while (n + 1 < len && (r = read(fd, buf + n, len - 1 - n)) > 0) n += (size_t)r;
    close(fd);
    buf[n] = 0;
    return 0;
}

/* Atomar ersetzen: Datei daneben, (fsync,) rename. mode gilt für die neue Datei. fsync nur, wo ein
 * Stromausfall schaden würde (Passwortdateien, Journal); Flash-Schreiben ist auf dem iPod langsam. */
static int writeAtomicSync(const char *path, const char *data, size_t len, mode_t mode, int sync) {
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof tmp, "%s.mesh-tmp", path);
    unlink(tmp);
    int fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode);
    if (fd < 0) return -1;
    if (write(fd, data, len) != (ssize_t)len || fchmod(fd, mode) != 0 || fchown(fd, 0, 0) != 0 || (sync && fsync(fd) != 0)) {
        close(fd); unlink(tmp); return -1;
    }
    close(fd);
    if (rename(tmp, path) != 0) { unlink(tmp); return -1; }
    return 0;
}

static int writeAtomic(const char *path, const char *data, size_t len, mode_t mode) { return writeAtomicSync(path, data, len, mode, 1); }
static int writeText(const char *path, const char *text) { return writeAtomicSync(path, text, strlen(text), 0600, 0); }

static int ensureDir(void) {
    if (mkdir(STATE_DIR, 0700) != 0) {
        struct stat st;
        if (lstat(STATE_DIR, &st) != 0 || !S_ISDIR(st.st_mode)) return -1;   // kein Symlink
    }
    return chmod(STATE_DIR, 0700);
}

/* Fehler festhalten und weiterreichen: "<schritt> rc=<code> errno=<n>". */
static int fail(const char *step, int rc) {
    char line[128];
    snprintf(line, sizeof line, "%s rc=%d errno=%d\n", step, rc, errno);
    writeText(ERR_FILE, line);
    return rc;
}

/* ---------- Programme ---------- */

static int run(const char *prog, char *const argv[], char *out, size_t outlen) {
    int pipefd[2] = { -1, -1 };
    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    if (out && pipe(pipefd) == 0) {
        posix_spawn_file_actions_adddup2(&fa, pipefd[1], 1);
        posix_spawn_file_actions_adddup2(&fa, pipefd[1], 2);
        posix_spawn_file_actions_addclose(&fa, pipefd[0]);
    } else {
        posix_spawn_file_actions_addopen(&fa, 1, "/dev/null", O_WRONLY, 0);
        posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    }
    posix_spawn_file_actions_addopen(&fa, 0, "/dev/null", O_RDONLY, 0);
    pid_t pid;
    int rc = posix_spawn(&pid, prog, &fa, NULL, argv, cleanEnv);
    posix_spawn_file_actions_destroy(&fa);
    if (pipefd[1] >= 0) close(pipefd[1]);
    if (rc != 0) { if (pipefd[0] >= 0) close(pipefd[0]); return -1; }
    if (out) {
        size_t n = 0; ssize_t r;
        while (pipefd[0] >= 0 && (r = read(pipefd[0], out + n, outlen - 1 - n)) > 0) { n += (size_t)r; if (n + 1 >= outlen) break; }
        out[n] = 0;
        if (pipefd[0] >= 0) close(pipefd[0]);
    }
    int st = 0;
    while (waitpid(pid, &st, 0) < 0) {}
    return WIFEXITED(st) ? WEXITSTATUS(st) : -1;
}

/* ---------- pf ---------- */

static int pfEnabled(void) {
    char out[2048]; char *a[] = { "pfctl", "-s", "info", NULL };
    if (run(PFCTL, a, out, sizeof out) < 0) return -1;
    return strstr(out, "Status: Enabled") ? 1 : 0;
}

/* Ursprung merken, bevor pf zum ersten Mal angefasst wird. Fremde aktive Firewall: nicht anfassen. */
static int journalPf(void) {
    if (exists(JOURNAL)) return MG_OK;
    int en = pfEnabled();
    if (en < 0) return MG_ERR_PF;
    if (en == 1) return MG_ERR_FOREIGN;
    return writeAtomic(JOURNAL, "pf_was=disabled\n", 16, 0600) == 0 ? MG_OK : MG_ERR_IO;
}

static void pfRestore(void) {
    char j[256] = { 0 };
    readSmall(JOURNAL, j, sizeof j);
    char *flush[] = { "pfctl", "-F", "all", NULL };
    run(PFCTL, flush, NULL, 0);
    if (!strstr(j, "pf_was=enabled")) { char *d[] = { "pfctl", "-d", NULL }; run(PFCTL, d, NULL, 0); }
    unlink(PF_CONF);
    unlink(JOURNAL);
}

/* Ausnahmen lesen: nur Zeilen der Form "tcp|udp <1..65535>". */
static int readExceptions(char proto[][4], int port[], int max) {
    char buf[1024] = { 0 };
    if (readSmall(EXC_FILE, buf, sizeof buf) != 0) return 0;
    int n = 0;
    for (char *save = NULL, *line = strtok_r(buf, "\n", &save); line && n < max; line = strtok_r(NULL, "\n", &save)) {
        char p[8]; int po;
        if (sscanf(line, "%3s %d", p, &po) != 2 || po < 1 || po > 65535) continue;
        if (strcmp(p, "tcp") && strcmp(p, "udp")) continue;
        strcpy(proto[n], p); port[n] = po; n++;
    }
    return n;
}

/* Adressen aus einer Datei lesen: erstes Wort je Zeile, nur was inet_pton als IPv4/IPv6 annimmt
 * (in Normalform zurück). */
static int readHosts(const char *path, char out[][INET6_ADDRSTRLEN], int max) {
    static char buf[MAX_AUTO * 96];
    buf[0] = 0;
    if (readSmall(path, buf, sizeof buf) != 0) return 0;
    int n = 0;
    for (char *save = NULL, *line = strtok_r(buf, "\n", &save); line && n < max; line = strtok_r(NULL, "\n", &save)) {
        char *sp = strchr(line, ' ');
        if (sp) *sp = 0;
        struct in6_addr a6; struct in_addr a4;
        if (inet_pton(AF_INET, line, &a4) == 1) inet_ntop(AF_INET, &a4, out[n++], INET6_ADDRSTRLEN);
        else if (inet_pton(AF_INET6, line, &a6) == 1) inet_ntop(AF_INET6, &a6, out[n++], INET6_ADDRSTRLEN);
    }
    return n;
}

static int readBlocked(char out[][INET6_ADDRSTRLEN], int max) { return readHosts(BLOCK_FILE, out, max); }

/* App-Name, wie der Kern ihn meldet: 1–32 Zeichen aus [A-Za-z0-9._+- ] (kein Komma: Statuszeile). */
static int validName(const char *name) {
    size_t n = strlen(name);
    if (n == 0 || n > NAME_MAX_LEN) return 0;
    for (size_t i = 0; i < n; i++) {
        char c = name[i];
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || strchr("._+- ", c))) return 0;
    }
    return 1;
}

/* Ohne eigene Liste (erster Start) sind Mesh und sein Tor erlaubt; danach gilt die Liste. */
static const char *const defaultApps[] = { "Mesh", "mesh-tor" };

static int readApps(char out[][NAME_MAX_LEN + 1], int max) {
    char buf[64 * (NAME_MAX_LEN + 2)] = { 0 };
    if (readSmall(APPS_FILE, buf, sizeof buf) != 0) {
        int n = 0;
        for (size_t i = 0; i < sizeof defaultApps / sizeof *defaultApps && n < max; i++) snprintf(out[n++], NAME_MAX_LEN + 1, "%s", defaultApps[i]);
        return n;
    }
    int n = 0;
    for (char *save = NULL, *line = strtok_r(buf, "\n", &save); line && n < max; line = strtok_r(NULL, "\n", &save))
        if (validName(line)) snprintf(out[n++], NAME_MAX_LEN + 1, "%s", line);
    return n;
}

/* Mesh und sein Tor gehören zusammen: wer das eine erlaubt oder sperrt, meint beide. */
static const char *partnerOf(const char *name) {
    if (!strcmp(name, "Mesh")) return "mesh-tor";
    if (!strcmp(name, "mesh-tor")) return "Mesh";
    return NULL;
}

static int appAllowed(const char *name) {
    char apps[64][NAME_MAX_LEN + 1];
    int n = readApps(apps, 64);
    for (int i = 0; i < n; i++) if (!strcmp(apps[i], name)) return 1;
    return 0;
}

/* Regeln aus fester Vorlage. Abgeschirmt: eingehend alles zu bis auf Netzbetrieb und Ausnahmen aus dem
 * eigenen WLAN; ausgehend nur Netzbetrieb (DNS, DHCP, IPv6-Nachbarn) und die gelernten Ziele erlaubter
 * Apps, gesperrte Ziele nie. Notschalter: alles zu, nur lo0 bleibt. */
static int pfApply(int cut) {
    static char rules[(MG_MAX_BLOCKED + MAX_AUTO) * 72 + 4096];
    static char hosts[MAX_AUTO][INET6_ADDRSTRLEN];
    size_t n = 0;
#define ADD(...) n += (size_t)snprintf(rules + n, n < sizeof rules ? sizeof rules - n : 0, __VA_ARGS__)
    // Lokal immer frei (Tor-SOCKS, Dienste der Apps untereinander). Kein "set skip": Optionen lädt
    // pfctl nur zusammen mit /etc/pf.os, und die gibt es auf iOS nicht (siehe Laden unten).
    ADD("# Mesh Security (feste Vorlage)\npass quick on lo0 all no state\n");
    if (cut) {
        ADD("block drop all\n");
    } else {
        ADD("block drop in all\nblock drop out all\n");
        char blocked[MG_MAX_BLOCKED][INET6_ADDRSTRLEN];
        int nb = readBlocked(blocked, MG_MAX_BLOCKED);
        for (int i = 0; i < nb; i++) ADD("block drop out quick to %s\n", blocked[i]);      // gesperrte Ziele vor allem anderen
        ADD("pass out quick proto { udp, tcp } to any port 53 keep state\n");                  // DNS
        ADD("pass out quick inet proto udp from any port 68 to any port 67 keep state\n");     // DHCP
        ADD("pass out quick inet6 proto ipv6-icmp keep state\n");                              // IPv6-Nachbarn
        int na = readHosts(AUTO_FILE, hosts, MAX_AUTO);                                          // Ziele erlaubter Apps
        for (int i = 0; i < na; i++) ADD("pass out quick to %s keep state\n", hosts[i]);
        ADD("pass in inet proto udp from any port 67 to any port 68\n");                         // WLAN-Adresse (DHCP)
        ADD("pass in inet proto icmp icmp-type unreach\n");                                      // Pfad-MTU
        ADD("pass in inet6 proto ipv6-icmp icmp6-type { 133, 134, 135, 136 }\n");                // IPv6-Nachbarn
        char proto[MG_MAX_EXCEPT][4]; int port[MG_MAX_EXCEPT];
        int k = readExceptions(proto, port, MG_MAX_EXCEPT);
        for (int i = 0; i < k; i++)
            // In Klammern: pf löst das WLAN-Netz dynamisch auf. Ohne Klammern bräche das Laden ab, solange
            // en0 keine Adresse hat (beim Hochfahren), und der iPod bliebe offen.
            ADD("pass in inet proto %s from (en0:network) to any port %d keep state\n", proto[i], port[i]);
    }
#undef ADD
    if (n >= sizeof rules || writeText(PF_CONF, rules) != 0) return fail("pf.conf", MG_ERR_IO);
    // -R: nur Filterregeln (ohne Optionen und OS-Fingerabdrücke, /etc/pf.os fehlt auf iOS);
    // -o none: ohne Optimierer, der sonst Tabellen bräuchte.
    char *load[] = { "pfctl", "-o", "none", "-R", "-f", PF_CONF, NULL };
    int lr = run(PFCTL, load, NULL, 0);
    if (lr != 0) { errno = lr; return fail("pfctl-f", MG_ERR_RULES); }
    char *en[] = { "pfctl", "-e", NULL };
    run(PFCTL, en, NULL, 0);                         // meldet Fehler, wenn schon an
    int st = pfEnabled();
    if (st != 1) { errno = st; return fail("pf-enabled", MG_ERR_RULES); }
    return MG_OK;
}

/* ---------- Passwort ---------- */

/* Hash eines Kontos aus einer passwd-Datei; 0 = gefunden. */
static int readHash(const char *file, const char *user, char *hash, size_t len) {
    char buf[16384];
    if (readSmall(file, buf, sizeof buf) != 0) return -1;
    size_t ul = strlen(user);
    for (char *line = buf; line && *line; ) {
        char *next = strchr(line, '\n');
        if (strncmp(line, user, ul) == 0 && line[ul] == ':') {
            char *h = line + ul + 1, *end = strchr(h, ':');
            if (!end || (size_t)(end - h) >= len) return -1;
            memcpy(hash, h, (size_t)(end - h)); hash[end - h] = 0;
            return 0;
        }
        line = next ? next + 1 : NULL;
    }
    return -1;
}

/* In einer passwd-Datei den Hash eines Kontos ersetzen, nur wenn er gerade "from" ist. */
static int replaceHash(const char *file, const char *user, const char *from, const char *to) {
    char buf[16384], out[16640];
    struct stat st;
    if (stat(file, &st) != 0 || readSmall(file, buf, sizeof buf) != 0) return -1;
    size_t ul = strlen(user), o = 0;
    int done = 0;
    for (char *line = buf; *line; ) {
        char *next = strchr(line, '\n');
        size_t ll = next ? (size_t)(next - line) + 1 : strlen(line);
        char *h = line + ul + 1, *end = memchr(h, ':', ll > ul + 1 ? ll - ul - 1 : 0);
        if (!done && strncmp(line, user, ul) == 0 && line[ul] == ':' && end &&
            (size_t)(end - h) == strlen(from) && strncmp(h, from, strlen(from)) == 0) {
            o += (size_t)snprintf(out + o, sizeof out - o, "%s:%s", user, to);
            size_t rest = ll - (size_t)(end - line);
            if (o + rest >= sizeof out) return -1;
            memcpy(out + o, end, rest); o += rest;
            done = 1;
        } else {
            if (o + ll >= sizeof out) return -1;
            memcpy(out + o, line, ll); o += ll;
        }
        line += ll;
    }
    if (!done) return 1;   // nichts zu tun (Hash wurde inzwischen anders geändert)
    return writeAtomic(file, out, o, st.st_mode & 0777);
}

static int isDefault(const char *hash) {
    if (!*hash) return 1;                            // leeres Passwort ist schlimmer als alpine
    const char *c = crypt("alpine", hash);
    return c && strcmp(c, hash) == 0;
}

static int hasDefaultPassword(const char *user) {
    char h[128];
    if (readHash(MASTER_PW, user, h, sizeof h) != 0) return 0;
    return isDefault(h);
}

/* 10 Zeichen ohne Verwechsler; crypt prüft nur die ersten 8, die Anzeige bleibt trotzdem kurz. */
static void generatePassword(char *pw, size_t len) {
    static const char set[] = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    for (size_t i = 0; i + 1 < len; i++) pw[i] = set[arc4random_uniform(sizeof set - 1)];
    pw[len - 1] = 0;
}

/* Passwort für alle Konten mit alpine setzen; HASH_FILE merkt alt/neu für die Rücknahme. */
static int securePasswords(void) {
    const char *users[] = { "root", "mobile" };
    char pw[9], salt[3], journal[512] = { 0 };
    static const char saltset[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789./";
    int changed = 0;
    generatePassword(pw, sizeof pw);
    salt[0] = saltset[arc4random_uniform(64)]; salt[1] = saltset[arc4random_uniform(64)]; salt[2] = 0;
    const char *c = crypt(pw, salt);
    if (!c) return MG_ERR_PASSWORD;
    char newHash[64];
    snprintf(newHash, sizeof newHash, "%s", c);
    for (int i = 0; i < 2; i++) {
        char old[128];
        if (readHash(MASTER_PW, users[i], old, sizeof old) != 0 || !isDefault(old)) continue;
        size_t jl = strlen(journal);
        snprintf(journal + jl, sizeof journal - jl, "%s %s %s\n", users[i], old, newHash);
        changed = 1;
    }
    if (!changed) return MG_OK;
    // Erst merken, dann ändern: bricht etwas ab, weiß die Rücknahme, was zu tun ist.
    if (writeAtomic(HASH_FILE, journal, strlen(journal), 0600) != 0 || writeText(PW_FILE, pw) != 0) return fail("pw-journal", MG_ERR_IO);
    for (int i = 0; i < 2; i++) {
        char old[128];
        if (readHash(MASTER_PW, users[i], old, sizeof old) != 0 || !isDefault(old)) continue;
        if (replaceHash(MASTER_PW, users[i], old, newHash) != 0) return fail("master.passwd", MG_ERR_PASSWORD);
        if (readHash(PLAIN_PW, users[i], old, sizeof old) == 0 && isDefault(old))
            if (replaceHash(PLAIN_PW, users[i], old, newHash) < 0) return fail("passwd", MG_ERR_PASSWORD);
    }
    memset(pw, 0, sizeof pw);
    return MG_OK;
}

static void restorePasswords(void) {
    char buf[512] = { 0 };
    if (readSmall(HASH_FILE, buf, sizeof buf) == 0) {
        for (char *save = NULL, *line = strtok_r(buf, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
            char user[16], old[64], cur[64];
            if (sscanf(line, "%15s %63s %63s", user, old, cur) != 3) continue;
            replaceHash(MASTER_PW, user, cur, old);
            replaceHash(PLAIN_PW, user, cur, old);
        }
    }
    unlink(HASH_FILE);
    unlink(PW_FILE);
}

/* ---------- Zustand zurück ---------- */

static void stopLogger(void);

/* Abschirmung und Notschalter zurücknehmen; Ausnahmen und Mitschreiben bleiben. */
static void undoShield(void) {
    pfRestore();
    restorePasswords();
    unlink(TRIAL_FILE);
    unlink(SHIELD_FILE);
    unlink(CUT_FILE);
}

static void undoAll(void) {
    undoShield();
    stopLogger();
    DIR *d = opendir(STATE_DIR);
    if (d) {
        struct dirent *e; char path[PATH_MAX];
        while ((e = readdir(d))) {
            if (e->d_name[0] == '.') continue;
            snprintf(path, sizeof path, "%s/%s", STATE_DIR, e->d_name);
            unlink(path);
        }
        closedir(d);
    }
    rmdir(STATE_DIR);
}

/* Bestehende Verbindungen zu einem Ziel kappen (pf ließe sie über ihren Zustand sonst weiterlaufen). */
static void killStates(const char *host) {
    char *kill[] = { "pfctl", "-k", strchr(host, ':') ? "::/0" : "0.0.0.0/0", "-k", (char *)host, NULL };
    run(PFCTL, kill, NULL, 0);
}

/* Ziel einer erlaubten App freigeben; 1 = neu dazugekommen. Ist die Liste voll, fällt das älteste
 * Viertel weg (Tor wechselt seine Relays; was noch gebraucht wird, lernt der Mitschreiber neu). */
static int addAuto(const char *host, const char *app) {
    static char hosts[MAX_AUTO][INET6_ADDRSTRLEN];
    int n = readHosts(AUTO_FILE, hosts, MAX_AUTO);
    for (int i = 0; i < n; i++) if (!strcmp(hosts[i], host)) return 0;
    if (n >= MAX_AUTO) {
        static char buf[MAX_AUTO * 96];
        buf[0] = 0;
        readSmall(AUTO_FILE, buf, sizeof buf);
        char *keep = buf;
        for (int i = 0; i < MAX_AUTO / 4 && keep; i++) { keep = strchr(keep, '\n'); if (keep) keep++; }
        if (keep) writeAtomicSync(AUTO_FILE, keep, strlen(keep), 0600, 0);
    }
    int fd = open(AUTO_FILE, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600);
    if (fd < 0) return 0;
    char line[INET6_ADDRSTRLEN + NAME_MAX_LEN + 4];
    int len = snprintf(line, sizeof line, "%s %s\n", host, app);
    write(fd, line, (size_t)len);
    close(fd);
    return 1;
}

/* Abgeschirmt und kein Notschalter: Regeln gelten, also neu laden. */
static int shieldActive(void) { return exists(SHIELD_FILE) && !exists(CUT_FILE); }

/* ---------- Hintergrundprozesse ---------- */

/* Doppelt forken: der Enkel gehört launchd, überlebt Helfer und App. 1 = im Enkel. */
static int detach(void) {
    pid_t p = fork();
    if (p < 0) return 0;
    if (p > 0) { waitpid(p, NULL, 0); return 0; }
    if (fork() != 0) _exit(0);
    setsid();
    signal(SIGHUP, SIG_IGN); signal(SIGPIPE, SIG_IGN);
    // Alles Geerbte schließen (vor allem die Pipe zur App, die sonst bis zu unserem Ende offen bliebe).
    for (int fd = 3, max = getdtablesize(); fd < max; fd++) close(fd);
    int fd = open("/dev/null", O_RDWR);
    if (fd >= 0) { dup2(fd, 0); dup2(fd, 1); dup2(fd, 2); if (fd > 2) close(fd); }
    return 1;
}

/* ---------- Verbindungen ---------- */

static int ourLoggerPid(void) {
    char b[32];
    if (readSmall(LOG_PID, b, sizeof b) != 0) return 0;
    int pid = atoi(b);
    if (pid <= 1) return 0;
    char path[1024] = { 0 }, self[1024] = { 0 };
    if (proc_pidpath(pid, path, sizeof path) <= 0 || proc_pidpath(getpid(), self, sizeof self) <= 0) return 0;
    return strcmp(path, self) == 0 ? pid : 0;          // PID wiederverwendet: nicht unser Prozess
}

static void stopLogger(void) {
    int pid = ourLoggerPid();
    if (pid) kill(pid, SIGTERM);
    unlink(LOG_PID);
}

static void addr(char *out, size_t len, const struct in_sockinfo *in, int local) {
    char a[INET6_ADDRSTRLEN] = "?";
    int port = ntohs(local ? (uint16_t)in->insi_lport : (uint16_t)in->insi_fport);
    if (in->insi_vflag & INI_IPV4) {
        inet_ntop(AF_INET, local ? &in->insi_laddr.ina_46.i46a_addr4 : &in->insi_faddr.ina_46.i46a_addr4, a, sizeof a);
    } else {
        const struct in6_addr *a6 = local ? &in->insi_laddr.ina_6 : &in->insi_faddr.ina_6;
        // IPv6-Socket mit IPv4 dahinter (::a.b.c.d oder ::ffff:a.b.c.d): als IPv4 schreiben, sonst
        // träfe eine pf-Sperre die echte Verbindung nicht.
        if (IN6_IS_ADDR_V4MAPPED(a6) || IN6_IS_ADDR_V4COMPAT(a6)) inet_ntop(AF_INET, &a6->s6_addr[12], a, sizeof a);
        else inet_ntop(AF_INET6, a6, a, sizeof a);
    }
    snprintf(out, len, "%s:%d", a, port);
}

/* Zuletzt gesehene Verbindungen (Schlüssel als Text), damit jede nur einmal im Protokoll steht. */
#define SEEN_MAX 512
static char seen[SEEN_MAX][96];
static int seenNext;

static int seenBefore(const char *key) {
    for (int i = 0; i < SEEN_MAX; i++) if (seen[i][0] && strcmp(seen[i], key) == 0) return 1;
    snprintf(seen[seenNext], sizeof seen[0], "%s", key);
    seenNext = (seenNext + 1) % SEEN_MAX;
    return 0;
}

static void appendConn(const char *line) {
    struct stat st;
    if (stat(CONNS_FILE, &st) == 0 && st.st_size > CONNS_MAX) {   // ältere Hälfte verwerfen
        int fd = open(CONNS_FILE, O_RDONLY | O_NOFOLLOW);
        if (fd >= 0) {
            char *buf = malloc((size_t)st.st_size + 1);
            ssize_t n = buf ? read(fd, buf, (size_t)st.st_size) : -1;
            close(fd);
            if (n > 0) {
                buf[n] = 0;
                char *half = strchr(buf + n / 2, '\n');
                if (half) writeAtomic(CONNS_FILE, half + 1, strlen(half + 1), 0600);
            }
            free(buf);
        }
    }
    int fd = open(CONNS_FILE, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW, 0600);
    if (fd < 0) return;
    write(fd, line, strlen(line));
    close(fd);
}

/* Ein Durchgang über alle Sockets aller Prozesse. Eingehend = lokaler Port, auf dem dieser Prozess lauscht. */
static void pollSockets(void) {
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0) return;
    pid_t *pids = malloc((size_t)bytes * 2);
    if (!pids) return;
    int np = proc_listpids(PROC_ALL_PIDS, 0, pids, bytes * 2) / (int)sizeof(pid_t);
    for (int i = 0; i < np; i++) {
        if (pids[i] <= 0) continue;
        int fb = proc_pidinfo(pids[i], PROC_PIDLISTFDS, 0, NULL, 0);
        if (fb <= 0) continue;
        struct proc_fdinfo *fds = malloc((size_t)fb);
        if (!fds) continue;
        fb = proc_pidinfo(pids[i], PROC_PIDLISTFDS, 0, fds, fb);
        int nf = fb / (int)sizeof(struct proc_fdinfo);
        int listen[32], nl = 0;
        struct socket_fdinfo si[64]; int ns = 0;
        for (int f = 0; f < nf && ns < 64; f++) {
            if (fds[f].proc_fdtype != PROX_FDTYPE_SOCKET) continue;
            struct socket_fdinfo s;
            if (proc_pidfdinfo(pids[i], fds[f].proc_fd, PROC_PIDFDSOCKETINFO, &s, sizeof s) < (int)sizeof s) continue;
            int kind = s.psi.soi_kind;
            if (kind != SOCKINFO_TCP && kind != SOCKINFO_IN) continue;
            if (kind == SOCKINFO_TCP && s.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN) {
                if (nl < 32) listen[nl++] = s.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport;
                continue;
            }
            si[ns++] = s;
        }
        char name[64] = { 0 };
        proc_name(pids[i], name, sizeof name);
        for (int k = 0; k < ns; k++) {
            int tcp = si[k].psi.soi_kind == SOCKINFO_TCP;
            const struct in_sockinfo *in = tcp ? &si[k].psi.soi_proto.pri_tcp.tcpsi_ini : &si[k].psi.soi_proto.pri_in;
            if (in->insi_fport == 0) continue;                     // nicht verbunden
            char l[64], r[64];
            addr(l, sizeof l, in, 1); addr(r, sizeof r, in, 0);
            if (!strncmp(r, "127.", 4) || !strncmp(r, "::1:", 4)) continue;   // lokal (z.B. Tor-SOCKS)
            // Eingehend: der Prozess lauscht selbst auf dem Port, oder lokal ein Dienstport und fern nicht
            // (SSH: launchd lauscht und reicht die Verbindung an sshd weiter).
            int incoming = ntohs((uint16_t)in->insi_lport) < 1024 && ntohs((uint16_t)in->insi_fport) >= 1024;
            for (int x = 0; x < nl; x++) if (listen[x] == in->insi_lport) incoming = 1;
            char key[96];
            snprintf(key, sizeof key, "%d %s %s %s", pids[i], tcp ? "t" : "u", l, r);
            if (seenBefore(key)) continue;
            // Erlaubte App mit neuem Ziel: freigeben (TCP wiederholt den Aufbau nach ~1 s, dann geht er
            // durch). Alle anderen bleiben am "block drop out all" hängen.
            char host[INET6_ADDRSTRLEN];
            snprintf(host, sizeof host, "%s", r);
            char *colon = strrchr(host, ':');
            if (colon) *colon = 0;
            int allowed = incoming || (validName(name) && appAllowed(name));
            if (!incoming && allowed && addAuto(host, name) && shieldActive()) pfApply(0);
            int blocked = !allowed && shieldActive();
            char line[256];
            snprintf(line, sizeof line, "%ld\t%s\t%s\t%s\t%s\t%s\t%s\n", (long)time(NULL), incoming ? "in" : "out",
                     tcp ? "tcp" : "udp", name[0] ? name : "?", l, r, blocked ? "block" : "pass");
            appendConn(line);
        }
        free(fds);
    }
    free(pids);
}

static void startLogger(void) {
    if (ourLoggerPid()) return;
    if (!detach()) return;
    char b[32];
    snprintf(b, sizeof b, "%d\n", getpid());
    writeText(LOG_PID, b);
    for (;;) {
        if (!exists(LOG_FLAG) && !exists(SHIELD_FILE)) { unlink(LOG_PID); _exit(0); }   // abgeschirmt läuft er immer (App-Sperren)
        pollSockets();
        sleep(POLL_SECS);
    }
}

/* ---------- Befehle ---------- */

static int sshListening(void) {
    int s = socket(AF_INET, SOCK_STREAM, 0);
    if (s < 0) return 0;
    struct sockaddr_in a = { 0 };
    a.sin_len = sizeof a; a.sin_family = AF_INET; a.sin_port = htons(22); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int ok = connect(s, (struct sockaddr *)&a, sizeof a) == 0;
    close(s);
    return ok;
}

static int cmdStatus(void) {
    int pf = pfEnabled();
    printf("helper=1\nshield=%d\npf=%d\ncut=%d\nlog=%d\n",
           exists(SHIELD_FILE), pf == 1, exists(CUT_FILE), (exists(LOG_FLAG) || exists(SHIELD_FILE)) && ourLoggerPid() != 0);
    printf("alpine_root=%d\nalpine_mobile=%d\nssh=%d\npw=%d\n",
           hasDefaultPassword("root"), hasDefaultPassword("mobile"), sshListening(), exists(PW_FILE));
    char proto[MG_MAX_EXCEPT][4]; int port[MG_MAX_EXCEPT];
    int n = readExceptions(proto, port, MG_MAX_EXCEPT);
    printf("except=");
    for (int i = 0; i < n; i++) printf("%s%s:%d", i ? "," : "", proto[i], port[i]);
    printf("\nblocked=");
    char blocked[MG_MAX_BLOCKED][INET6_ADDRSTRLEN];
    int nb = readBlocked(blocked, MG_MAX_BLOCKED);
    for (int i = 0; i < nb; i++) printf("%s%s", i ? "," : "", blocked[i]);
    printf("\napps=");                                 // erlaubte Apps
    char apps[64][NAME_MAX_LEN + 1];
    int napps = readApps(apps, 64);
    for (int i = 0; i < napps; i++) printf("%s%s", i ? "," : "", apps[i]);
    printf("\n");
    return MG_OK;
}

static int shieldOn(void) {
    if (exists(SHIELD_FILE)) return MG_OK;
    if (ensureDir() != 0) return MG_ERR_IO;
    unlink(ERR_FILE);
    int rc = journalPf();
    if (rc != MG_OK) return fail("journal", rc);
    if ((rc = securePasswords()) != MG_OK) { fail("password", rc); undoShield(); return rc; }
    if (!exists(CUT_FILE) && (rc = pfApply(0)) != MG_OK) { undoShield(); return rc; }
    if (writeText(SHIELD_FILE, "1\n") != 0) { fail("state", MG_ERR_IO); undoShield(); return MG_ERR_IO; }
    startLogger();
    return MG_OK;
}

static int cmdShield(const char *arg) {
    if (!strcmp(arg, "on")) return shieldOn();
    if (!strcmp(arg, "off")) { undoShield(); return MG_OK; }
    return MG_ERR_USAGE;
}

static int cmdPassword(void) {
    char pw[32] = { 0 };
    if (readSmall(PW_FILE, pw, sizeof pw) != 0) return MG_ERR_USAGE;
    printf("pw=%s\n", pw);
    return MG_OK;
}

static int cmdExcept(const char *op, const char *proto, const char *portText) {
    char *end;
    long port = strtol(portText, &end, 10);
    if (*end || port < 1 || port > 65535 || (strcmp(proto, "tcp") && strcmp(proto, "udp"))) return MG_ERR_USAGE;
    int add = !strcmp(op, "add");
    if (!add && strcmp(op, "del")) return MG_ERR_USAGE;
    if (ensureDir() != 0) return MG_ERR_IO;
    char p[MG_MAX_EXCEPT][4]; int po[MG_MAX_EXCEPT];
    int n = readExceptions(p, po, MG_MAX_EXCEPT), found = -1;
    for (int i = 0; i < n; i++) if (po[i] == port && !strcmp(p[i], proto)) found = i;
    if (add && found >= 0) return MG_OK;
    if (add && n >= MG_MAX_EXCEPT) return MG_ERR_LIMIT;
    char out[1024]; size_t o = 0;
    for (int i = 0; i < n; i++) if (i != found) o += (size_t)snprintf(out + o, sizeof out - o, "%s %d\n", p[i], po[i]);
    if (add) o += (size_t)snprintf(out + o, sizeof out - o, "%s %ld\n", proto, port);
    if (writeAtomic(EXC_FILE, out, o, 0600) != 0) return MG_ERR_IO;
    if (exists(SHIELD_FILE) && !exists(CUT_FILE)) return pfApply(0);
    return MG_OK;
}

static int cmdBlock(const char *op, const char *host) {
    char norm[INET6_ADDRSTRLEN];
    struct in6_addr a6; struct in_addr a4;
    if (inet_pton(AF_INET, host, &a4) == 1) inet_ntop(AF_INET, &a4, norm, sizeof norm);
    else if (inet_pton(AF_INET6, host, &a6) == 1) inet_ntop(AF_INET6, &a6, norm, sizeof norm);
    else return MG_ERR_USAGE;
    int add = !strcmp(op, "add");
    if (!add && strcmp(op, "del")) return MG_ERR_USAGE;
    if (ensureDir() != 0) return MG_ERR_IO;
    char list[MG_MAX_BLOCKED][INET6_ADDRSTRLEN];
    int n = readBlocked(list, MG_MAX_BLOCKED), found = -1;
    for (int i = 0; i < n; i++) if (!strcmp(list[i], norm)) found = i;
    if (add && found >= 0) return MG_OK;
    if (add && n >= MG_MAX_BLOCKED) return MG_ERR_LIMIT;
    char out[MG_MAX_BLOCKED * (INET6_ADDRSTRLEN + 1) + 64]; size_t o = 0;
    for (int i = 0; i < n; i++) if (i != found) o += (size_t)snprintf(out + o, sizeof out - o, "%s\n", list[i]);
    if (add) o += (size_t)snprintf(out + o, sizeof out - o, "%s\n", norm);
    if (writeAtomic(BLOCK_FILE, out, o, 0600) != 0) return MG_ERR_IO;
    if (exists(SHIELD_FILE) && !exists(CUT_FILE)) {
        int rc = pfApply(0);
        if (rc != MG_OK || !add) return rc;
        killStates(norm);   // bestehende Verbindungen sofort kappen, nicht erst die nächste
    }
    return MG_OK;
}

/* App erlauben: auf die Liste, und ihre Ziele aus dem Protokoll gleich freigeben (sonst wartet sie beim
 * ersten Versuch je Ziel auf die TCP-Wiederholung). Sperren: von der Liste, ihre Ziele weg, laufende
 * Verbindungen kappen. Mesh und mesh-tor schalten zusammen (partnerOf). */
static int cmdAppOne(const char *op, const char *name);

static int cmdApp(const char *op, const char *name) {
    if (!validName(name)) return MG_ERR_USAGE;
    int rc = cmdAppOne(op, name);
    const char *partner = partnerOf(name);
    if (rc == MG_OK && partner) rc = cmdAppOne(op, partner);
    return rc;
}

static int cmdAppOne(const char *op, const char *name) {
    int allow = !strcmp(op, "allow");
    if (!allow && strcmp(op, "block")) return MG_ERR_USAGE;
    if (ensureDir() != 0) return MG_ERR_IO;
    char apps[64][NAME_MAX_LEN + 1];
    int n = readApps(apps, 64), found = -1;
    for (int i = 0; i < n; i++) if (!strcmp(apps[i], name)) found = i;
    if (allow && found < 0 && n >= 64) return MG_ERR_LIMIT;
    char out[64 * (NAME_MAX_LEN + 2)]; size_t o = 0;
    for (int i = 0; i < n; i++) if (i != found) o += (size_t)snprintf(out + o, sizeof out - o, "%s\n", apps[i]);
    if (allow) o += (size_t)snprintf(out + o, sizeof out - o, "%s\n", name);
    if (writeAtomicSync(APPS_FILE, out, o, 0600, 0) != 0) return MG_ERR_IO;

    static char gone[MAX_AUTO][INET6_ADDRSTRLEN];
    int ngone = 0;
    if (allow) {
        // Bisherige Ziele aus dem Protokoll: Feld 4 = Prozess, Feld 2 = Richtung, Feld 6 = Gegenstelle.
        int fd = open(CONNS_FILE, O_RDONLY | O_NOFOLLOW);
        if (fd >= 0) {
            struct stat st;
            char *buf = fstat(fd, &st) == 0 ? malloc((size_t)st.st_size + 1) : NULL;
            ssize_t len = buf ? read(fd, buf, (size_t)st.st_size) : -1;
            close(fd);
            if (len > 0) {
                buf[len] = 0;
                for (char *save = NULL, *line = strtok_r(buf, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
                    char *f[7]; int k = 0;
                    for (char *s2 = NULL, *t = strtok_r(line, "\t", &s2); t && k < 7; t = strtok_r(NULL, "\t", &s2)) f[k++] = t;
                    if (k != 7 || strcmp(f[1], "out") || strcmp(f[3], name)) continue;
                    char *colon = strrchr(f[5], ':');
                    if (colon) *colon = 0;
                    struct in6_addr a6; struct in_addr a4;
                    if (inet_pton(AF_INET, f[5], &a4) == 1 || inet_pton(AF_INET6, f[5], &a6) == 1) addAuto(f[5], name);
                }
            }
            free(buf);
        }
    } else {
        // Freigegebene Ziele dieser App entfernen: Zeilen "<adresse> <name>".
        static char buf[MAX_AUTO * 96], keep[MAX_AUTO * 96];
        size_t kl = 0;
        buf[0] = 0;
        if (readSmall(AUTO_FILE, buf, sizeof buf) == 0) {
            for (char *save = NULL, *line = strtok_r(buf, "\n", &save); line; line = strtok_r(NULL, "\n", &save)) {
                char *sp = strchr(line, ' ');
                if (sp && !strcmp(sp + 1, name)) {
                    *sp = 0;
                    if (ngone < MAX_AUTO) snprintf(gone[ngone++], INET6_ADDRSTRLEN, "%s", line);
                    continue;
                }
                kl += (size_t)snprintf(keep + kl, sizeof keep - kl, "%s\n", line);
            }
            writeAtomicSync(AUTO_FILE, keep, kl, 0600, 0);
        }
    }
    if (!shieldActive()) return MG_OK;
    int rc = pfApply(0);
    for (int i = 0; rc == MG_OK && i < ngone; i++) killStates(gone[i]);
    return rc;
}

static int cmdCut(const char *arg) {
    if (!strcmp(arg, "on")) {
        if (ensureDir() != 0) return MG_ERR_IO;
        int rc = journalPf();
        if (rc != MG_OK) return rc;
        if ((rc = pfApply(1)) != MG_OK) { if (!exists(SHIELD_FILE)) pfRestore(); return rc; }
        return writeText(CUT_FILE, "1\n") == 0 ? MG_OK : MG_ERR_IO;
    }
    if (!strcmp(arg, "off")) {
        unlink(CUT_FILE);
        if (exists(SHIELD_FILE)) return pfApply(0);
        pfRestore();
        return MG_OK;
    }
    return MG_ERR_USAGE;
}

static int cmdLog(const char *arg) {
    if (!strcmp(arg, "on")) {
        if (ensureDir() != 0 || writeText(LOG_FLAG, "1\n") != 0) return MG_ERR_IO;
        startLogger();
        return MG_OK;
    }
    if (!strcmp(arg, "off")) { unlink(LOG_FLAG); stopLogger(); unlink(CONNS_FILE); return MG_OK; }
    return MG_ERR_USAGE;
}

static int cmdConns(void) {
    int fd = open(CONNS_FILE, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) return MG_OK;
    char buf[8192]; ssize_t r;
    while ((r = read(fd, buf, sizeof buf)) > 0) fwrite(buf, 1, (size_t)r, stdout);
    close(fd);
    return MG_OK;
}

/* Nach Neustart: pf ist leer. Offene Probezeit gilt als nicht bestätigt. */
static int cmdBoot(void) {
    if (exists(TRIAL_FILE)) undoShield();   // unbestätigte Probezeit aus Version ≤ 0.3.1
    else if (exists(CUT_FILE)) pfApply(1);
    else if (exists(SHIELD_FILE) && pfApply(0) != MG_OK) {
        // Abschirmung ließ sich nicht laden: lieber alles zu als alles offen (fail-closed). Ausschalten
        // oder "Wieder verbinden" in der App hebt das auf.
        fail("boot", MG_ERR_RULES);
        if (pfApply(1) == MG_OK) writeText(CUT_FILE, "1\n");
    }
    if (exists(LOG_FLAG) || exists(SHIELD_FILE)) startLogger();
    return MG_OK;
}

int main(int argc, char **argv) {
    if (argc < 2) return MG_ERR_USAGE;
    const char *cmd = argv[1];
    int rootOnly = !strcmp(cmd, MG_CMD_BOOT) || !strcmp(cmd, MG_CMD_UNINSTALL);
    if (rootOnly ? getuid() != 0 : !appCaller()) return MG_ERR_CALLER;
    if (geteuid() != 0 || setgid(0) != 0 || setuid(0) != 0) return MG_ERR_PRIV;
    umask(077);
    if (!strcmp(cmd, MG_CMD_BOOT))      return cmdBoot();
    if (!strcmp(cmd, MG_CMD_UNINSTALL)) { undoAll(); return MG_OK; }
    if (!strcmp(cmd, MG_CMD_STATUS))    return cmdStatus();
    if (!strcmp(cmd, MG_CMD_PASSWORD))  return cmdPassword();
    if (!strcmp(cmd, MG_CMD_CONNS))     return cmdConns();
    if (!strcmp(cmd, MG_CMD_RESET))     { undoAll(); return MG_OK; }
    if (argc >= 3 && !strcmp(cmd, MG_CMD_SHIELD)) return cmdShield(argv[2]);
    if (argc >= 3 && !strcmp(cmd, MG_CMD_CUT))    return cmdCut(argv[2]);
    if (argc >= 3 && !strcmp(cmd, MG_CMD_LOG))    return cmdLog(argv[2]);
    if (argc >= 4 && !strcmp(cmd, MG_CMD_APP))    return cmdApp(argv[2], argv[3]);
    if (argc >= 4 && !strcmp(cmd, MG_CMD_BLOCK))  return cmdBlock(argv[2], argv[3]);
    if (argc >= 5 && !strcmp(cmd, MG_CMD_EXCEPT)) return cmdExcept(argv[2], argv[3], argv[4]);
    return MG_ERR_USAGE;
}
