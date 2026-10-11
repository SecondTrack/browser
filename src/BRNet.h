// BRNet — sicheres Laden von Webseiten (eigenes TLS 1.2/1.3 via mbedTLS, Zertifikate werden GEPRÜFT).
#import <Foundation/Foundation.h>

@interface BRResponse : NSObject
@property (nonatomic, strong) NSURL *url;            // endgültige URL nach Weiterleitungen
@property (nonatomic) int status;
@property (nonatomic, copy) NSString *contentType;   // z.B. "text/html; charset=utf-8"
@property (nonatomic, strong) NSData *body;
@property (nonatomic) BOOL secure;                   // HTTPS mit gültigem Zertifikat
@property (nonatomic, copy) NSString *error;         // nil = ok
@end

@interface BRNet : NSObject
// Synchron, NICHT auf dem Main-Thread aufrufen. maxBytes begrenzt die Antwortgröße.
+ (BRResponse *)fetch:(NSURL *)url maxBytes:(NSUInteger)maxBytes;
@end
