// Fassade für die UI: alles, was Mesh Security am System ändert, läuft hier durch.
// Die UI kennt weder den Helfer noch pf noch Dateien. Neue Funktionen kommen als Methode hierher.
//
// Alle Aufrufe kehren sofort zurück; die Arbeit läuft auf einer seriellen Queue (der Helfer ist
// ein eigener Prozess), completion kommt auf dem Main-Thread. Danach ist `status` neu gelesen und
// MeshGuardChangedNotification verschickt.
#import <Foundation/Foundation.h>
#import "MeshGuardStatus.h"
#import "MeshException.h"

typedef NS_ENUM(NSInteger, MeshGuardResult) {
    MeshGuardResultOK,
    MeshGuardResultNoHelper,     // Helfer fehlt oder hat keine root-Rechte (Paket neu installieren)
    MeshGuardResultRefused,      // Helfer hat den Aufrufer abgelehnt
    MeshGuardResultForeignRules, // pf hat fremde Regeln, Mesh Security fasst sie nicht an
    MeshGuardResultPassword,     // Passwort ließ sich nicht setzen, alles zurückgenommen
    MeshGuardResultLimit,        // zu viele Ausnahmen
    MeshGuardResultFailed,       // Ursprung wiederhergestellt
};

typedef void (^MeshGuardDone)(MeshGuardResult result);

@interface MeshGuard : NSObject
+ (instancetype)shared;

@property (nonatomic, readonly) MeshGuardStatus *status;   // zuletzt gelesen; anfangs "unbekannt"
- (void)refresh;

// Abschirmen: an = sicheres Passwort statt alpine, eingehend alles zu; aus = alles zurück.
- (void)setShield:(BOOL)on completion:(MeshGuardDone)done;
- (void)loadPassword:(void (^)(NSString *password))done;   // nil, wenn keins erzeugt wurde
// Ausnahmen: Port aus dem eigenen WLAN erreichbar.
- (void)addException:(MeshException *)e completion:(MeshGuardDone)done;
- (void)removeException:(MeshException *)e completion:(MeshGuardDone)done;
// Ziel ausgehend sperren, für alle Apps (pf kann Apps nicht unterscheiden); gilt, solange abgeschirmt.
- (void)setHost:(NSString *)host blocked:(BOOL)blocked completion:(MeshGuardDone)done;
// Darf die App raus? Abgeschirmt dürfen nur erlaubte Apps (Mesh mit Tor immer); der Mitschreiber gibt
// ihre Ziele frei, sobald sie sich verbinden wollen.
- (void)setApp:(NSString *)name allowed:(BOOL)allowed completion:(MeshGuardDone)done;
- (void)loadApps:(void (^)(NSArray *apps))done;   // MeshAppActivity: alle installierten Apps, dann Systemprozesse
// Notschalter: trennt sofort alles in beide Richtungen.
- (void)setCut:(BOOL)cut completion:(MeshGuardDone)done;
// Verbindungen pro App mitschreiben und laden (MeshConnection, neueste zuerst).
- (void)setLogging:(BOOL)on completion:(MeshGuardDone)done;
- (void)loadConnections:(void (^)(NSArray *connections))done;
// Ursprungszustand: alles zurück, Ausnahmen und Protokoll gelöscht.
- (void)resetAll:(MeshGuardDone)done;

+ (NSString *)describe:(MeshGuardResult)result;   // Text für Hinweise
@end
