#import "MeshException.h"

@implementation MeshException

+ (instancetype)exceptionFromToken:(NSString *)token {
    NSArray *p = [token componentsSeparatedByString:@":"];
    if (p.count != 2) return nil;
    NSString *proto = p[0];
    if (!([proto isEqual:@"tcp"] || [proto isEqual:@"udp"])) return nil;
    NSScanner *sc = [NSScanner scannerWithString:p[1]];
    NSInteger port;
    if (![sc scanInteger:&port] || !sc.isAtEnd || port < 1 || port > 65535) return nil;
    return [[self alloc] initWithProto:proto port:port];
}

- (instancetype)initWithProto:(NSString *)proto port:(NSInteger)port {
    if ((self = [super init])) { _proto = [proto copy]; _port = port; }
    return self;
}

- (NSString *)name {
    if ([_proto isEqual:@"tcp"] && _port == 22) return @"SSH";
    if ([_proto isEqual:@"tcp"] && _port == 8080) return @"FileTransfer";
    return nil;
}

@end
