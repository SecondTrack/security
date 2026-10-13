// Momentaufnahme des Schutzzustands, wie der Helfer ihn meldet (Befehl "status").
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, MeshLevel) {
    MeshLevelUnknown,   // Helfer nicht erreichbar oder Antwort unvollständig
    MeshLevelOpen,      // nicht abgeschirmt
    MeshLevelShielded,  // abgeschirmt
    MeshLevelCut        // Notschalter: alles getrennt
};

@interface MeshGuardStatus : NSObject
// Aus den key=value-Zeilen des Helfers; fehlende oder fremde Werte bleiben auf "unbekannt".
+ (instancetype)statusFromFields:(NSDictionary *)fields;
+ (instancetype)unknown;

@property (nonatomic, readonly) BOOL helperReachable;
@property (nonatomic, readonly) BOOL shieldOn;            // abgeschirmt und pf tatsächlich aktiv
@property (nonatomic, readonly) BOOL cut;
@property (nonatomic, readonly) BOOL logging;
@property (nonatomic, readonly) BOOL rootHasDefaultPassword;
@property (nonatomic, readonly) BOOL mobileHasDefaultPassword;
@property (nonatomic, readonly) BOOL sshListening;
@property (nonatomic, readonly) BOOL passwordGenerated;   // Mesh Security hat alpine ersetzt
@property (nonatomic, readonly) NSArray *exceptions;      // MeshException
@property (nonatomic, readonly) NSArray *allowedApps;     // NSString, Apps (Prozessname), die abgeschirmt raus dürfen
@property (nonatomic, readonly) NSArray *blockedHosts;    // NSString, gesperrte Ziele (gelten, solange abgeschirmt)

- (MeshLevel)level;
@end
