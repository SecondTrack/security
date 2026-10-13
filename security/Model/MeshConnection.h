// Eine beobachtete Verbindung: wer (App), wohin, in welche Richtung, erlaubt oder blockiert.
#import <Foundation/Foundation.h>

@interface MeshConnection : NSObject
// Aus einer Zeile des Helfers (Befehl "conns"): Tab-getrennt
//   <unixzeit> <in|out> <tcp|udp> <prozess> <lokal:port> <fern:port> <pass|block>
// Liefert nil bei falscher Feldzahl oder unbekannten Werten.
+ (instancetype)connectionFromLine:(NSString *)line;

@property (nonatomic, readonly) NSDate *time;
@property (nonatomic, readonly) BOOL incoming;
@property (nonatomic, readonly, copy) NSString *proto;
@property (nonatomic, readonly, copy) NSString *process;   // Programmname laut Kern, z.B. "MobileSafari"
@property (nonatomic, readonly, copy) NSString *local;
@property (nonatomic, readonly, copy) NSString *remote;
@property (nonatomic, readonly) BOOL blocked;
- (NSString *)remoteHost;   // Gegenstelle ohne Port
@end
