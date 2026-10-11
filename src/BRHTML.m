#import "BRHTML.h"

NSString *const BRAttrBold   = @"BRBold";
NSString *const BRAttrItalic = @"BRItalic";
NSString *const BRAttrCode   = @"BRCode";
NSString *const BRAttrLink   = @"BRLink";

static NSURL *BRAbsURL(NSString *s, NSURL *base) { return [(NSURL *)[NSURL URLWithString:s relativeToURL:base] absoluteURL]; }

@implementation BRBlock @end
@implementation BRDocument @end

#pragma mark - Zeichensatz

static NSString *charsetFrom(NSString *s) {
    if (!s) return nil;
    NSRange r = [s rangeOfString:@"charset=" options:NSCaseInsensitiveSearch];
    if (r.location == NSNotFound) return nil;
    NSString *v = [s substringFromIndex:NSMaxRange(r)];
    NSCharacterSet *stop = [NSCharacterSet characterSetWithCharactersInString:@"\"'; >/\r\n"];
    v = [v stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\"' "]];
    NSRange e = [v rangeOfCharacterFromSet:stop];
    return (e.location == NSNotFound ? v : [v substringToIndex:e.location]).lowercaseString;
}

static NSStringEncoding encodingNamed(NSString *name) {
    if (!name.length) return 0;
    CFStringEncoding cf = CFStringConvertIANACharSetNameToEncoding((__bridge CFStringRef)name);
    return cf == kCFStringEncodingInvalidId ? 0 : CFStringConvertEncodingToNSStringEncoding(cf);
}

#pragma mark - Entities

static NSDictionary *namedEntities(void) {
    static NSDictionary *d; static dispatch_once_t once;
    dispatch_once(&once, ^{
        d = @{ @"amp": @"&", @"lt": @"<", @"gt": @">", @"quot": @"\"", @"apos": @"'", @"nbsp": @" ",
               @"auml": @"ä", @"ouml": @"ö", @"uuml": @"ü", @"Auml": @"Ä", @"Ouml": @"Ö", @"Uuml": @"Ü", @"szlig": @"ß",
               @"eacute": @"é", @"egrave": @"è", @"aacute": @"á", @"agrave": @"à", @"ccedil": @"ç", @"ntilde": @"ñ",
               @"copy": @"©", @"reg": @"®", @"trade": @"™", @"euro": @"€", @"pound": @"£", @"yen": @"¥", @"cent": @"¢",
               @"mdash": @"—", @"ndash": @"–", @"hellip": @"…", @"laquo": @"«", @"raquo": @"»", @"bull": @"•", @"middot": @"·",
               @"lsquo": @"‘", @"rsquo": @"’", @"ldquo": @"“", @"rdquo": @"”", @"bdquo": @"„", @"sbquo": @"‚",
               @"deg": @"°", @"times": @"×", @"divide": @"÷", @"plusmn": @"±", @"para": @"¶", @"sect": @"§",
               @"larr": @"←", @"rarr": @"→", @"uarr": @"↑", @"darr": @"↓", @"thinsp": @" ", @"ensp": @" ", @"emsp": @" ",
               @"shy": @"", @"zwnj": @"", @"zwj": @"" };
    });
    return d;
}

static NSString *decodeEntities(NSString *s) {
    if ([s rangeOfString:@"&"].location == NSNotFound) return s;
    NSMutableString *out = [NSMutableString stringWithCapacity:s.length];
    NSUInteger i = 0, n = s.length;
    while (i < n) {
        unichar c = [s characterAtIndex:i];
        if (c != '&') { [out appendFormat:@"%C", c]; i++; continue; }
        NSRange semi = [s rangeOfString:@";" options:0 range:NSMakeRange(i, MIN((NSUInteger)12, n - i))];
        if (semi.location == NSNotFound) { [out appendString:@"&"]; i++; continue; }
        NSString *ent = [s substringWithRange:NSMakeRange(i + 1, semi.location - i - 1)];
        NSString *rep = nil;
        if ([ent hasPrefix:@"#"]) {
            unsigned long cp = ([ent hasPrefix:@"#x"] || [ent hasPrefix:@"#X"]) ? strtoul([[ent substringFromIndex:2] UTF8String], NULL, 16)
                                                                              : strtoul([[ent substringFromIndex:1] UTF8String], NULL, 10);
            if (cp > 0 && cp < 0x110000 && !(cp >= 0xD800 && cp <= 0xDFFF)) {
                if (cp < 0x10000) rep = [NSString stringWithFormat:@"%C", (unichar)cp];
                else { cp -= 0x10000; unichar sp[2] = { (unichar)(0xD800 + (cp >> 10)), (unichar)(0xDC00 + (cp & 0x3FF)) };
                       rep = [NSString stringWithCharacters:sp length:2]; }
            }
        } else rep = namedEntities()[ent];
        if (rep) { [out appendString:rep]; i = semi.location + 1; }
        else { [out appendString:@"&"]; i++; }
    }
    return out;
}

#pragma mark - Builder

@interface BRBuilder : NSObject
@property (nonatomic, strong) NSMutableArray *blocks;
@property (nonatomic, strong) NSMutableAttributedString *cur;
@property (nonatomic) BRBlockKind kind;
@property (nonatomic) NSInteger level;
@property (nonatomic, copy) NSString *bullet;
@property (nonatomic) int bold, italic, code, pre, quote;
@property (nonatomic, strong) NSMutableArray *links;      // Stapel von NSURL / NSNull
@property (nonatomic, strong) NSMutableArray *lists;      // Stapel: @(-1)=ungeordnet, sonst Zähler
@property (nonatomic, strong) NSURL *base;
@end

@implementation BRBuilder
- (instancetype)init {
    if ((self = [super init])) { _blocks = [NSMutableArray array]; _cur = [NSMutableAttributedString new];
                                 _links = [NSMutableArray array]; _lists = [NSMutableArray array]; }
    return self;
}
- (NSURL *)link { id l = self.links.lastObject; return [l isKindOfClass:[NSURL class]] ? l : nil; }

- (void)flush {
    NSString *t = self.cur.string;
    NSString *trim = [t stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trim.length) {
        // führende/abschließende Leerzeichen entfernen, Attribute behalten
        NSMutableAttributedString *a = [self.cur mutableCopy];
        while (a.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[a.string characterAtIndex:0]] && !self.pre)
            [a deleteCharactersInRange:NSMakeRange(0, 1)];
        while (a.length && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[a.string characterAtIndex:a.length - 1]])
            [a deleteCharactersInRange:NSMakeRange(a.length - 1, 1)];
        BRBlock *b = [BRBlock new];
        b.kind = self.pre ? BRBlockPre : (self.quote && self.kind == BRBlockParagraph ? BRBlockQuote : self.kind);
        b.level = self.level; b.bullet = self.bullet; b.text = a;
        [self.blocks addObject:b];
    }
    self.cur = [NSMutableAttributedString new];
    self.kind = BRBlockParagraph; self.level = 0; self.bullet = nil;
}

- (void)text:(NSString *)s {
    if (!s.length) return;
    if (!self.pre) {
        // Leerraum zusammenfassen wie im Browser
        NSMutableString *m = [NSMutableString stringWithCapacity:s.length]; BOOL ws = NO;
        BOOL lastWS = self.cur.length == 0 || [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[self.cur.string characterAtIndex:self.cur.length - 1]];
        for (NSUInteger i = 0; i < s.length; i++) {
            unichar c = [s characterAtIndex:i];
            if (c == ' ' || c == '\n' || c == '\r' || c == '\t' || c == '\f') { ws = YES; continue; }
            if (ws && !(m.length == 0 && lastWS)) [m appendString:@" "];
            ws = NO; [m appendFormat:@"%C", c];
        }
        if (ws && !(m.length == 0 && lastWS)) [m appendString:@" "];
        s = m;
        if (!s.length) return;
    }
    NSMutableDictionary *at = [NSMutableDictionary dictionary];
    if (self.bold) at[BRAttrBold] = @YES;
    if (self.italic) at[BRAttrItalic] = @YES;
    if (self.code || self.pre) at[BRAttrCode] = @YES;
    if (self.link) at[BRAttrLink] = self.link;
    [self.cur appendAttributedString:[[NSAttributedString alloc] initWithString:decodeEntities(s) attributes:at]];
}

- (void)image:(NSString *)src alt:(NSString *)alt {
    if (!src.length || [src hasPrefix:@"data:"]) return;
    NSURL *u = BRAbsURL([src stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]], self.base);
    if (!u || !([u.scheme isEqualToString:@"https"] || [u.scheme isEqualToString:@"http"])) return;
    [self flush];
    BRBlock *b = [BRBlock new]; b.kind = BRBlockImage; b.imageURL = u; b.imageLink = self.link; b.alt = alt ?: @"";
    [self.blocks addObject:b];
}
@end

#pragma mark - Parser

static NSDictionary *parseAttrs(NSString *s) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSUInteger i = 0, n = s.length;
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    while (i < n) {
        while (i < n && ([ws characterIsMember:[s characterAtIndex:i]] || [s characterAtIndex:i] == '/')) i++;
        NSUInteger ks = i;
        while (i < n && ![ws characterIsMember:[s characterAtIndex:i]] && [s characterAtIndex:i] != '=' && [s characterAtIndex:i] != '/') i++;
        if (i == ks) { i++; continue; }
        NSString *k = [[s substringWithRange:NSMakeRange(ks, i - ks)] lowercaseString];
        while (i < n && [ws characterIsMember:[s characterAtIndex:i]]) i++;
        NSString *v = @"";
        if (i < n && [s characterAtIndex:i] == '=') {
            i++; while (i < n && [ws characterIsMember:[s characterAtIndex:i]]) i++;
            if (i < n && ([s characterAtIndex:i] == '"' || [s characterAtIndex:i] == '\'')) {
                unichar q = [s characterAtIndex:i++]; NSUInteger vs = i;
                while (i < n && [s characterAtIndex:i] != q) i++;
                v = [s substringWithRange:NSMakeRange(vs, i - vs)]; i++;
            } else {
                NSUInteger vs = i; while (i < n && ![ws characterIsMember:[s characterAtIndex:i]]) i++;
                v = [s substringWithRange:NSMakeRange(vs, i - vs)];
            }
        }
        if (!d[k]) d[k] = decodeEntities(v);
    }
    return d;
}

@implementation BRHTML

+ (NSString *)decode:(NSData *)data contentType:(NSString *)contentType {
    NSStringEncoding enc = encodingNamed(charsetFrom(contentType));
    if (!enc) {
        NSString *head = [[NSString alloc] initWithData:[data subdataWithRange:NSMakeRange(0, MIN(data.length, (NSUInteger)4096))] encoding:NSISOLatin1StringEncoding];
        enc = encodingNamed(charsetFrom(head));
    }
    NSString *s = enc ? [[NSString alloc] initWithData:data encoding:enc] : nil;
    if (!s) s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!s) s = [[NSString alloc] initWithData:data encoding:NSWindowsCP1252StringEncoding];
    return s ?: @"";
}

+ (BRDocument *)plainText:(NSString *)text {
    BRDocument *doc = [BRDocument new];
    BRBlock *b = [BRBlock new]; b.kind = BRBlockPre;
    b.text = [[NSAttributedString alloc] initWithString:text attributes:@{ BRAttrCode: @YES }];
    doc.blocks = @[b];
    return doc;
}

+ (BRDocument *)parse:(NSString *)html baseURL:(NSURL *)base {
    BRBuilder *B = [BRBuilder new]; B.base = base;
    NSString *title = nil;
    static NSSet *skip, *blockTags;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // Inhalt komplett verwerfen (ausführbar, unsichtbar oder unbrauchbar ohne JS)
        skip = [NSSet setWithArray:@[@"script", @"style", @"noscript", @"template", @"svg", @"math", @"iframe", @"object",
                                     @"embed", @"canvas", @"video", @"audio", @"select", @"textarea", @"button"]];
        blockTags = [NSSet setWithArray:@[@"p", @"div", @"section", @"article", @"header", @"footer", @"nav", @"main", @"aside",
                                          @"figure", @"figcaption", @"table", @"tr", @"dl", @"dt", @"dd", @"form", @"fieldset",
                                          @"address", @"details", @"summary", @"center", @"caption", @"tbody", @"thead"]];
    });

    NSUInteger i = 0, n = html.length;
    while (i < n) {
        NSRange lt = [html rangeOfString:@"<" options:0 range:NSMakeRange(i, n - i)];
        NSUInteger textEnd = lt.location == NSNotFound ? n : lt.location;
        if (textEnd > i) [B text:[html substringWithRange:NSMakeRange(i, textEnd - i)]];
        if (lt.location == NSNotFound) break;
        i = lt.location;

        if ([html length] >= i + 4 && [[html substringWithRange:NSMakeRange(i, 4)] isEqualToString:@"<!--"]) {
            NSRange e = [html rangeOfString:@"-->" options:0 range:NSMakeRange(i + 4, n - i - 4)];
            i = e.location == NSNotFound ? n : NSMaxRange(e); continue;
        }
        NSRange gt = [html rangeOfString:@">" options:0 range:NSMakeRange(i + 1, n - i - 1)];
        if (gt.location == NSNotFound) { [B text:[html substringFromIndex:i]]; break; }
        NSString *tag = [html substringWithRange:NSMakeRange(i + 1, gt.location - i - 1)];
        i = NSMaxRange(gt);
        if (!tag.length || [tag hasPrefix:@"!"] || [tag hasPrefix:@"?"]) continue;

        BOOL closing = [tag hasPrefix:@"/"];
        if (closing) tag = [tag substringFromIndex:1];
        NSRange sp = [tag rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n/"]];
        NSString *name = [(sp.location == NSNotFound ? tag : [tag substringToIndex:sp.location]) lowercaseString];
        NSString *attrStr = sp.location == NSNotFound ? @"" : [tag substringFromIndex:sp.location];
        if (!name.length) continue;

        // ---- Bereiche, deren Inhalt komplett übersprungen wird ----
        if (!closing && ([skip containsObject:name] || [name isEqualToString:@"title"])) {
            NSRange e = [html rangeOfString:[NSString stringWithFormat:@"</%@", name] options:NSCaseInsensitiveSearch range:NSMakeRange(i, n - i)];
            NSUInteger stop = e.location == NSNotFound ? n : e.location;
            if ([name isEqualToString:@"title"] && !title) title = decodeEntities([[html substringWithRange:NSMakeRange(i, stop - i)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]);
            if (e.location == NSNotFound) { i = n; break; }
            NSRange e2 = [html rangeOfString:@">" options:0 range:NSMakeRange(e.location, n - e.location)];
            i = e2.location == NSNotFound ? n : NSMaxRange(e2);
            continue;
        }
        NSDictionary *at = closing ? nil : parseAttrs(attrStr);

        if ([name isEqualToString:@"base"] && at[@"href"]) { NSURL *b = BRAbsURL(at[@"href"], base); if (b) B.base = b; continue; }

        // Überschriften
        if (name.length == 2 && [name characterAtIndex:0] == 'h' && [name characterAtIndex:1] >= '1' && [name characterAtIndex:1] <= '6') {
            [B flush];
            if (!closing) { B.kind = BRBlockHeading; B.level = [name characterAtIndex:1] - '0'; }
            continue;
        }
        if ([name isEqualToString:@"br"]) { if (B.pre) [B.cur appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]]; else [B flush]; continue; }
        if ([name isEqualToString:@"hr"]) { [B flush]; BRBlock *r = [BRBlock new]; r.kind = BRBlockRule; [B.blocks addObject:r]; continue; }
        if ([name isEqualToString:@"img"]) { [B image:at[@"src"] ?: at[@"data-src"] alt:at[@"alt"]]; continue; }
        if ([name isEqualToString:@"pre"]) { [B flush]; B.pre += closing ? -1 : 1; if (B.pre < 0) B.pre = 0; continue; }
        if ([name isEqualToString:@"blockquote"]) { [B flush]; B.quote += closing ? -1 : 1; if (B.quote < 0) B.quote = 0; continue; }
        if ([name isEqualToString:@"ul"] || [name isEqualToString:@"ol"]) {
            [B flush];
            if (closing) [B.lists removeLastObject];
            else [B.lists addObject:@([name isEqualToString:@"ol"] ? [at[@"start"] integerValue] ?: 1 : -1)];
            continue;
        }
        if ([name isEqualToString:@"li"]) {
            [B flush];
            if (!closing) {
                B.kind = BRBlockListItem; B.level = MAX((NSInteger)1, (NSInteger)B.lists.count);
                NSInteger c = [B.lists.lastObject integerValue];
                if (B.lists.count && c > 0) { B.bullet = [NSString stringWithFormat:@"%ld.", (long)c]; B.lists[B.lists.count - 1] = @(c + 1); }
                else B.bullet = @"•";
            }
            continue;
        }
        if ([name isEqualToString:@"td"] || [name isEqualToString:@"th"]) { if (!closing) [B text:@" "]; else [B text:@"   "]; continue; }
        if ([blockTags containsObject:name]) { [B flush]; continue; }

        // Inline
        if ([name isEqualToString:@"b"] || [name isEqualToString:@"strong"]) { B.bold += closing ? -1 : 1; if (B.bold < 0) B.bold = 0; continue; }
        if ([name isEqualToString:@"i"] || [name isEqualToString:@"em"] || [name isEqualToString:@"cite"]) { B.italic += closing ? -1 : 1; if (B.italic < 0) B.italic = 0; continue; }
        if ([name isEqualToString:@"code"] || [name isEqualToString:@"kbd"] || [name isEqualToString:@"tt"] || [name isEqualToString:@"samp"]) { B.code += closing ? -1 : 1; if (B.code < 0) B.code = 0; continue; }
        if ([name isEqualToString:@"a"]) {
            if (closing) { if (B.links.count) [B.links removeLastObject]; continue; }
            NSString *href = [at[@"href"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            NSURL *u = href.length && ![href.lowercaseString hasPrefix:@"javascript:"] ? BRAbsURL(href, B.base) : nil;
            if (u && !([u.scheme isEqualToString:@"http"] || [u.scheme isEqualToString:@"https"])) u = nil;
            [B.links addObject:u ?: (id)[NSNull null]];
            continue;
        }
        if ([name isEqualToString:@"input"] && [[at[@"type"] lowercaseString] isEqualToString:@"submit"] && [at[@"value"] length]) { [B text:[NSString stringWithFormat:@" [%@] ", at[@"value"]]]; continue; }
        // alles andere (span, font, small, …) einfach ignorieren, Text bleibt erhalten
    }
    [B flush];
    BRDocument *doc = [BRDocument new]; doc.title = title; doc.blocks = B.blocks;
    return doc;
}
@end
