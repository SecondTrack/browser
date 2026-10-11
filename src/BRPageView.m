#import "BRPageView.h"
#import "BRNet.h"
#import <CoreText/CoreText.h>
#import <QuartzCore/QuartzCore.h>

#define MARGIN 12.0
#define MAX_IMAGES 30
#define MAX_IMAGE_BYTES (3 * 1024 * 1024)

static UIColor *RGB(int r, int g, int b) { return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }
#define INK   RGB(28,28,30)
#define MUTED RGB(110,110,115)
#define LINK  RGB(0,102,214)
#define CODEBG RGB(242,242,247)

#pragma mark - Schriften / Attribute

static id ctFont(NSString *name, CGFloat size) {
    static NSMutableDictionary *cache; if (!cache) cache = [NSMutableDictionary dictionary];
    NSString *key = [NSString stringWithFormat:@"%@-%.1f", name, size];
    id f = cache[key];
    if (!f) { f = CFBridgingRelease(CTFontCreateWithName((__bridge CFStringRef)name, size, NULL)); cache[key] = f; }
    return f;
}

static CGFloat baseSize(BRBlock *b) {
    if (b.kind == BRBlockHeading) { static const CGFloat s[] = { 0, 24, 21, 19, 17, 16, 15 }; return s[MIN(MAX(b.level, 1), 6)]; }
    if (b.kind == BRBlockPre) return 13;
    return 16;
}

// BRBlock.text -> CoreText-fähiger String
static NSAttributedString *ctString(BRBlock *b) {
    NSMutableAttributedString *out = [NSMutableAttributedString new];
    NSString *prefix = b.kind == BRBlockListItem ? [NSString stringWithFormat:@"%@ ", b.bullet ?: @"•"] : @"";
    NSMutableAttributedString *src = [[NSMutableAttributedString alloc] initWithString:prefix];
    [src appendAttributedString:b.text];
    CGFloat size = baseSize(b);
    BOOL heading = b.kind == BRBlockHeading, quote = b.kind == BRBlockQuote;

    CGFloat indent = b.kind == BRBlockListItem ? 14.0 * b.level : 0;
    CGFloat headIndent = b.kind == BRBlockListItem ? indent + 14.0 : 0;
    CGFloat spacing = b.kind == BRBlockPre ? 1 : 3;
    CTParagraphStyleSetting set[] = {
        { kCTParagraphStyleSpecifierFirstLineHeadIndent, sizeof(CGFloat), &indent },
        { kCTParagraphStyleSpecifierHeadIndent, sizeof(CGFloat), &headIndent },
        { kCTParagraphStyleSpecifierLineSpacing, sizeof(CGFloat), &spacing },
    };
    id para = CFBridgingRelease(CTParagraphStyleCreate(set, 3));

    [src enumerateAttributesInRange:NSMakeRange(0, src.length) options:0 usingBlock:^(NSDictionary *at, NSRange r, BOOL *stop) {
        BOOL bold = heading || [at[BRAttrBold] boolValue], italic = quote || [at[BRAttrItalic] boolValue], code = [at[BRAttrCode] boolValue];
        NSString *fname = code ? (bold ? @"Courier-Bold" : @"Courier")
                        : bold && italic ? @"Helvetica-BoldOblique" : bold ? @"Helvetica-Bold" : italic ? @"Helvetica-Oblique" : @"Helvetica";
        NSURL *link = at[BRAttrLink];
        NSMutableDictionary *ct = [NSMutableDictionary dictionary];
        ct[(__bridge id)kCTFontAttributeName] = ctFont(fname, code && b.kind != BRBlockPre ? size - 2 : size);
        ct[(__bridge id)kCTForegroundColorAttributeName] = (__bridge id)(link ? LINK : (quote ? MUTED : INK)).CGColor;
        ct[(__bridge id)kCTParagraphStyleAttributeName] = para;
        if (link) { ct[(__bridge id)kCTUnderlineStyleAttributeName] = @(kCTUnderlineStyleSingle); ct[BRAttrLink] = link; }
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:[src.string substringWithRange:r] attributes:ct]];
    }];
    return out;
}

#pragma mark - Textblock

@interface BRTextView : UIView
@property (nonatomic, strong) NSAttributedString *text;
@property (nonatomic, copy) void (^onLink)(NSURL *url);
- (CGFloat)heightForWidth:(CGFloat)w;
@end

@implementation BRTextView {
    id _frame;                 // CTFrameRef
    CGFloat _laidOutWidth;
}
- (instancetype)initWithFrame:(CGRect)f { if ((self = [super initWithFrame:f])) { self.backgroundColor = [UIColor clearColor]; self.contentMode = UIViewContentModeRedraw; } return self; }

- (CGFloat)heightForWidth:(CGFloat)w {
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)self.text);
    CGSize s = CTFramesetterSuggestFrameSizeWithConstraints(fs, CFRangeMake(0, 0), NULL, CGSizeMake(w, CGFLOAT_MAX), NULL);
    CFRelease(fs);
    return ceil(s.height) + 2;
}

- (void)buildFrame {
    CTFramesetterRef fs = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)self.text);
    CGPathRef path = CGPathCreateWithRect(self.bounds, NULL);
    _frame = CFBridgingRelease(CTFramesetterCreateFrame(fs, CFRangeMake(0, 0), path, NULL));
    CGPathRelease(path); CFRelease(fs);
    _laidOutWidth = self.bounds.size.width;
}

- (void)drawRect:(CGRect)rect {
    if (!_frame || _laidOutWidth != self.bounds.size.width) [self buildFrame];
    CGContextRef c = UIGraphicsGetCurrentContext();
    CGContextSetTextMatrix(c, CGAffineTransformIdentity);
    CGContextTranslateCTM(c, 0, self.bounds.size.height);
    CGContextScaleCTM(c, 1, -1);
    CTFrameDraw((__bridge CTFrameRef)_frame, c);
}

- (void)setBounds:(CGRect)b { [super setBounds:b]; _frame = nil; [self setNeedsDisplay]; }
- (void)setFrame:(CGRect)f { [super setFrame:f]; _frame = nil; [self setNeedsDisplay]; }

- (NSURL *)linkAt:(CGPoint)p {
    if (!_frame) [self buildFrame];
    CFArrayRef lines = CTFrameGetLines((__bridge CTFrameRef)_frame);
    CFIndex n = CFArrayGetCount(lines); if (!n) return nil;
    CGPoint origins[n]; CTFrameGetLineOrigins((__bridge CTFrameRef)_frame, CFRangeMake(0, 0), origins);
    CGFloat H = self.bounds.size.height;
    for (CFIndex i = 0; i < n; i++) {
        CTLineRef line = CFArrayGetValueAtIndex(lines, i);
        CGFloat asc, desc, lead; double w = CTLineGetTypographicBounds(line, &asc, &desc, &lead);
        CGFloat top = H - origins[i].y - asc - 4, bottom = H - origins[i].y + desc + 4;   // etwas großzügiger für Finger
        if (p.y < top || p.y > bottom) continue;
        if (p.x < origins[i].x - 4 || p.x > origins[i].x + w + 4) return nil;
        CFIndex idx = CTLineGetStringIndexForPosition(line, CGPointMake(p.x - origins[i].x, 0));
        for (CFIndex k = idx; k >= MAX((CFIndex)0, idx - 1); k--) {
            if (k >= (CFIndex)self.text.length) continue;
            NSURL *u = [self.text attribute:BRAttrLink atIndex:(NSUInteger)k effectiveRange:NULL];
            if (u) return u;
        }
        return nil;
    }
    return nil;
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    NSURL *u = [self linkAt:[[touches anyObject] locationInView:self]];
    if (u && self.onLink) self.onLink(u); else [super touchesEnded:touches withEvent:event];
}
@end

#pragma mark - Seite

@implementation BRPageView {
    NSMutableArray *_items;       // @[kind, view, block, (Bildhöhe | Textview im Rahmen)]
    NSUInteger _generation;
    dispatch_queue_t _imgQ;
    CGFloat _lastWidth;
}

- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = [UIColor whiteColor];
        self.alwaysBounceVertical = YES;
        _items = [NSMutableArray array];
        _imgQ = dispatch_queue_create("de.mesh.browser.img", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)clear {
    _generation++;
    for (NSArray *it in _items) [it[1] removeFromSuperview];
    [_items removeAllObjects];
    self.contentOffset = CGPointZero;
}

- (BRTextView *)textViewFor:(NSAttributedString *)s {
    BRTextView *v = [[BRTextView alloc] initWithFrame:CGRectZero];
    v.text = s;
    __weak BRPageView *ws = self;
    v.onLink = ^(NSURL *u) { if (ws.onLink) ws.onLink(u); };
    return v;
}

- (void)showMessage:(NSString *)title detail:(NSString *)detail {
    [self clear];
    BRBlock *h = [BRBlock new]; h.kind = BRBlockHeading; h.level = 2; h.text = [[NSAttributedString alloc] initWithString:title ?: @""];
    BRBlock *p = [BRBlock new]; p.kind = BRBlockParagraph; p.text = [[NSAttributedString alloc] initWithString:detail ?: @""];
    BRDocument *d = [BRDocument new]; d.blocks = @[h, p];
    [self showDocument:d];
}

- (void)showDocument:(BRDocument *)doc {
    [self clear];
    NSUInteger gen = _generation, images = 0;
    for (BRBlock *b in doc.blocks) {
        if (b.kind == BRBlockImage) {
            if (images++ >= MAX_IMAGES) continue;
            UIImageView *iv = [[UIImageView alloc] initWithFrame:CGRectZero];
            iv.backgroundColor = CODEBG; iv.contentMode = UIViewContentModeScaleAspectFit; iv.clipsToBounds = YES;
            if (b.imageLink) {
                iv.userInteractionEnabled = YES;
                [iv addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapImage:)]];
                iv.accessibilityValue = b.imageLink.absoluteString;
            }
            [self addSubview:iv];
            NSMutableArray *item = [@[@(BRBlockImage), iv, b, @(60.0)] mutableCopy];
            [_items addObject:item];
            dispatch_async(_imgQ, ^{
                if (gen != self->_generation) return;
                BRResponse *r = [BRNet fetch:b.imageURL maxBytes:MAX_IMAGE_BYTES];
                UIImage *img = r.body.length ? [UIImage imageWithData:r.body] : nil;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (gen != self->_generation) return;
                    if (img && img.size.width >= 2 && img.size.height >= 2) {
                        iv.image = img; iv.backgroundColor = [UIColor clearColor];
                        CGFloat w = MIN(img.size.width, self.bounds.size.width - 2 * MARGIN);
                        item[3] = @(MIN(w * img.size.height / img.size.width, 600.0));
                    } else item[3] = @0.0;            // nicht ladbar -> ausblenden
                    [self relayout];
                });
            });
        } else if (b.kind == BRBlockRule) {
            UIView *line = [[UIView alloc] initWithFrame:CGRectZero]; line.backgroundColor = RGB(220,220,224);
            [self addSubview:line]; [_items addObject:@[@(BRBlockRule), line, b]];
        } else if (b.kind == BRBlockPre || b.kind == BRBlockQuote) {
            // Rahmen: Code grau hinterlegt, Zitat mit Balken links
            UIView *box = [[UIView alloc] initWithFrame:CGRectZero];
            BRTextView *tv = [self textViewFor:ctString(b)];
            if (b.kind == BRBlockPre) { box.backgroundColor = CODEBG; box.layer.cornerRadius = 6; }
            else { UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 3, 0)]; bar.backgroundColor = RGB(200,200,206);
                   bar.autoresizingMask = UIViewAutoresizingFlexibleHeight; [box addSubview:bar]; }
            [box addSubview:tv];
            [self addSubview:box]; [_items addObject:@[@(b.kind), box, b, tv]];
        } else {
            BRTextView *tv = [self textViewFor:ctString(b)];
            [self addSubview:tv]; [_items addObject:@[@(b.kind), tv, b]];
        }
    }
    [self relayout];
}

- (void)tapImage:(UITapGestureRecognizer *)g {
    NSURL *u = [NSURL URLWithString:g.view.accessibilityValue];
    if (u && self.onLink) self.onLink(u);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    if (self.bounds.size.width != _lastWidth) { _lastWidth = self.bounds.size.width; [self relayout]; }
}

- (void)relayout {
    CGFloat W = self.bounds.size.width - 2 * MARGIN, y = MARGIN;
    BRBlockKind prev = BRBlockParagraph;
    for (NSArray *it in _items) {
        BRBlockKind k = [it[0] integerValue]; UIView *v = it[1];
        CGFloat gap = (k == BRBlockListItem && prev == BRBlockListItem) ? 2 : (k == BRBlockHeading ? 14 : 8);
        if (v != [_items.firstObject objectAtIndex:1]) y += gap;
        if (k == BRBlockImage) {
            CGFloat h = [it[3] floatValue];
            v.hidden = h <= 0; if (h <= 0) { y -= gap; continue; }
            v.frame = CGRectMake(MARGIN, y, W, h); y += h;
        } else if (k == BRBlockRule) {
            v.frame = CGRectMake(MARGIN, y + 4, W, 1); y += 9;
        } else if (k == BRBlockPre || k == BRBlockQuote) {
            BRTextView *tv = it[3];
            CGFloat padX = k == BRBlockPre ? 8 : 12, padY = k == BRBlockPre ? 6 : 0;
            CGFloat h = [tv heightForWidth:W - padX - (k == BRBlockPre ? padX : 0)];
            v.frame = CGRectMake(MARGIN, y, W, h + 2 * padY);
            tv.frame = CGRectMake(padX, padY, W - padX - (k == BRBlockPre ? padX : 0), h);
            y += h + 2 * padY;
        } else {
            BRTextView *tv = (BRTextView *)v;
            CGFloat h = [tv heightForWidth:W];
            tv.frame = CGRectMake(MARGIN, y, W, h);
            y += h;
        }
        prev = k;
    }
    self.contentSize = CGSizeMake(self.bounds.size.width, y + MARGIN * 2);
}
@end
