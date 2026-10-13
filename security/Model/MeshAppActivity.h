// Ein Programm für die Liste "Apps": installierte App oder Systemprozess aus dem Protokoll, mit
// Aktivität (Ziele, zuletzt gesehen) und ob es abgeschirmt raus darf. Erlaubt wird nach Prozessname.
#import <Foundation/Foundation.h>

@interface MeshAppActivity : NSObject
// installed: Wörterbücher mit name, executable, bundleId, iconPath (optional). Reihenfolge: Mesh (falls
// installiert; mesh-tor gehört dazu und schaltet mit), andere Mesh-Apps (de.mesh.*), übrige Apps nach
// Name, dann Prozesse aus dem Protokoll, die keine App sind (isApp = NO).
+ (NSArray *)activitiesForInstalled:(NSArray *)installed connections:(NSArray *)connections allowedApps:(NSArray *)allowed;

@property (nonatomic, readonly, copy) NSString *process;    // Prozessname laut Kern (Schlüssel fürs Erlauben)
@property (nonatomic, readonly, copy) NSString *name;       // Anzeigename
@property (nonatomic, readonly, copy) NSString *iconPath;   // nil bei Systemprozessen
@property (nonatomic, readonly) BOOL isApp;
@property (nonatomic, readonly) BOOL isMesh;                // de.mesh.*: steht oben
@property (nonatomic, readonly) BOOL isMessenger;           // Mesh selbst (mit Tor): steht ganz oben
@property (nonatomic, readonly) NSUInteger destinations;    // verschiedene Gegenstellen (ausgehend)
@property (nonatomic, readonly) NSDate *lastSeen;           // nil: noch nie online gesehen
@property (nonatomic, readonly) BOOL allowed;
@end
