#import "MeshHelper.h"
#import "MeshHelperProtocol.h"
#include <spawn.h>
#include <sys/wait.h>
#include <unistd.h>
#include <fcntl.h>

static const size_t kMaxOutput = 512 * 1024;   // Protokoll kappt der Helfer; mehr wird nicht gelesen

@interface MeshHelperResult ()
- (instancetype)initWithCode:(int)code output:(NSString *)output;
@end

@implementation MeshHelperResult

- (instancetype)initWithCode:(int)code output:(NSString *)output {
    if ((self = [super init])) { _code = code; _output = [output copy] ?: @""; }
    return self;
}

- (NSDictionary *)fields { return [MeshHelper fieldsFromOutput:_output]; }

- (NSArray *)lines {
    NSMutableArray *out = [NSMutableArray array];
    for (NSString *l in [_output componentsSeparatedByString:@"\n"]) if (l.length) [out addObject:l];
    return out;
}

@end

@implementation MeshHelper

+ (NSDictionary *)fieldsFromOutput:(NSString *)output {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        NSRange eq = [line rangeOfString:@"="];
        if (eq.location == NSNotFound || eq.location == 0) continue;
        d[[line substringToIndex:eq.location]] = [line substringFromIndex:eq.location + 1];
    }
    return d;
}

+ (MeshHelperResult *)run:(NSArray *)args input:(NSData *)input {
    NSString *path = [[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@MG_HELPER_NAME];
    int outPipe[2], inPipe[2];
    if (pipe(outPipe) != 0) return [[MeshHelperResult alloc] initWithCode:-1 output:nil];
    if (pipe(inPipe) != 0) { close(outPipe[0]); close(outPipe[1]); return [[MeshHelperResult alloc] initWithCode:-1 output:nil]; }

    char *argv[16] = { (char *)MG_HELPER_NAME };
    NSUInteger n = MIN(args.count, 14u);
    for (NSUInteger i = 0; i < n; i++) argv[i + 1] = (char *)[args[i] UTF8String];
    char *env[] = { "PATH=/usr/bin:/bin:/usr/sbin:/sbin", NULL };

    posix_spawn_file_actions_t fa;
    posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa, inPipe[0], 0);
    posix_spawn_file_actions_adddup2(&fa, outPipe[1], 1);
    posix_spawn_file_actions_addopen(&fa, 2, "/dev/null", O_WRONLY, 0);
    // Alle Original-Enden im Helfer schließen: sonst erbt ein Hintergrundprozess des Helfers (Wächter,
    // Mitschreiber) das Schreib-Ende, und read() unten sähe erst an dessen Ende EOF.
    posix_spawn_file_actions_addclose(&fa, inPipe[0]);
    posix_spawn_file_actions_addclose(&fa, inPipe[1]);
    posix_spawn_file_actions_addclose(&fa, outPipe[0]);
    posix_spawn_file_actions_addclose(&fa, outPipe[1]);
    pid_t pid;
    int rc = posix_spawn(&pid, path.fileSystemRepresentation, &fa, NULL, argv, env);
    posix_spawn_file_actions_destroy(&fa);
    close(inPipe[0]);
    close(outPipe[1]);
    if (rc != 0) { close(inPipe[1]); close(outPipe[0]); return [[MeshHelperResult alloc] initWithCode:-1 output:nil]; }

    if (input.length) (void)write(inPipe[1], input.bytes, input.length);
    close(inPipe[1]);

    NSMutableData *out = [NSMutableData data];
    char buf[4096];
    ssize_t r;
    while ((r = read(outPipe[0], buf, sizeof buf)) > 0) if (out.length < kMaxOutput) [out appendBytes:buf length:(NSUInteger)r];
    close(outPipe[0]);
    int st = 0;
    while (waitpid(pid, &st, 0) < 0) {}
    int code = WIFEXITED(st) ? WEXITSTATUS(st) : -1;
    NSString *text = [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding];
    return [[MeshHelperResult alloc] initWithCode:code output:text];
}

@end
