// Ausnahme der Abschirmung: ein Port, der aus dem eigenen WLAN erreichbar bleibt.
#import <Foundation/Foundation.h>

@interface MeshException : NSObject
// "tcp:22" → Ausnahme; nil bei falschem Protokoll oder Port außerhalb 1…65535.
+ (instancetype)exceptionFromToken:(NSString *)token;
- (instancetype)initWithProto:(NSString *)proto port:(NSInteger)port;
@property (nonatomic, readonly, copy) NSString *proto;   // "tcp" | "udp"
@property (nonatomic, readonly) NSInteger port;
- (NSString *)name;                                      // bekannter Dienst ("SSH") oder nil
@end
