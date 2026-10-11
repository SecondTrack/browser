// BRHTML — zerlegt HTML in einfache, sichere Blöcke. Kein JavaScript, keine Styles, keine Frames.
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, BRBlockKind) {
    BRBlockParagraph, BRBlockHeading, BRBlockListItem, BRBlockPre, BRBlockQuote, BRBlockImage, BRBlockRule
};

// Attribute in BRBlock.text (werden vom Renderer in Schriften/Farben übersetzt)
extern NSString *const BRAttrBold;     // @YES
extern NSString *const BRAttrItalic;   // @YES
extern NSString *const BRAttrCode;     // @YES
extern NSString *const BRAttrLink;     // NSURL

@interface BRBlock : NSObject
@property (nonatomic) BRBlockKind kind;
@property (nonatomic) NSInteger level;               // Überschrift 1–6, Listen-Tiefe
@property (nonatomic, copy) NSString *bullet;        // "•" oder "3."
@property (nonatomic, strong) NSAttributedString *text;
@property (nonatomic, strong) NSURL *imageURL;
@property (nonatomic, strong) NSURL *imageLink;      // Bild steckt in einem Link
@property (nonatomic, copy) NSString *alt;
@end

@interface BRDocument : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray *blocks;       // BRBlock
@end

@interface BRHTML : NSObject
+ (NSString *)decode:(NSData *)data contentType:(NSString *)contentType;
+ (BRDocument *)parse:(NSString *)html baseURL:(NSURL *)base;
+ (BRDocument *)plainText:(NSString *)text;
@end
