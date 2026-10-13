// Diagnose-Log nur in Debug-Paketen (FINALPACKAGE=0); im fertigen Paket ein leeres Makro.
#import <Foundation/Foundation.h>

#if MESH_DEBUG_LOG
void MeshLogf(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);
#define slog(...) MeshLogf(__VA_ARGS__)
#else
#define slog(...) do { } while (0)
#endif
