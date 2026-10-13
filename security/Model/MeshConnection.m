#import "MeshConnection.h"

@implementation MeshConnection

+ (instancetype)connectionFromLine:(NSString *)line {
    NSArray *f = [line componentsSeparatedByString:@"\t"];
    if (f.count != 7) return nil;
    NSString *dir = f[1], *proto = f[2], *verdict = f[6];
    if (!([dir isEqual:@"in"] || [dir isEqual:@"out"])) return nil;
    if (!([proto isEqual:@"tcp"] || [proto isEqual:@"udp"])) return nil;
    if (!([verdict isEqual:@"pass"] || [verdict isEqual:@"block"])) return nil;
    long long t = [f[0] longLongValue];
    if (t <= 0 || [f[3] length] == 0) return nil;

    MeshConnection *c = [[self alloc] init];
    c->_time = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)t];
    c->_incoming = [dir isEqual:@"in"];
    c->_proto = [proto copy];
    c->_process = [f[3] copy];
    c->_local = [f[4] copy];
    c->_remote = [f[5] copy];
    c->_blocked = [verdict isEqual:@"block"];
    return c;
}

- (NSString *)remoteHost {
    NSRange colon = [_remote rangeOfString:@":" options:NSBackwardsSearch];   // IPv6 enthält selbst Doppelpunkte
    return colon.location == NSNotFound ? _remote : [_remote substringToIndex:colon.location];
}

@end
