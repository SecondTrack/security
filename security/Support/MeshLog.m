#import "MeshLog.h"

#if MESH_DEBUG_LOG
void MeshLogf(NSString *format, ...) {
    va_list ap;
    va_start(ap, format);
    NSLogv(format, ap);
    va_end(ap);
}
#endif
