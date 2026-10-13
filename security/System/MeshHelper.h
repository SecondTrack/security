// Startet den setuid-Helfer msguard im App-Bundle und liest seine Antwort.
// Blockiert; MeshGuard ruft es nur aus einer eigenen seriellen Queue auf.
#import <Foundation/Foundation.h>

@interface MeshHelperResult : NSObject
@property (nonatomic, readonly) int code;            // Exit-Code (MG_*), -1: nicht startbar
@property (nonatomic, readonly, copy) NSString *output;
- (NSDictionary *)fields;                            // key=value-Zeilen
- (NSArray *)lines;                                  // nicht leere Zeilen
@end

@interface MeshHelper : NSObject
+ (MeshHelperResult *)run:(NSArray *)args input:(NSData *)input;
// Zerlegt key=value-Zeilen; Zeilen ohne "=" und leere Schlüssel werden übersprungen.
+ (NSDictionary *)fieldsFromOutput:(NSString *)output;
@end
