#import <UIKit/UIKit.h>
#import "BRNet.h"
#import "BRHTML.h"
#import "BRPageView.h"
#import "MeshL10n.h"

#define MAX_PAGE_BYTES (3 * 1024 * 1024)
static UIColor *RGBc(int r, int g, int b) { return [UIColor colorWithRed:r/255.0 green:g/255.0 blue:b/255.0 alpha:1]; }

@interface BRViewController : UIViewController <UITextFieldDelegate> @end

@implementation BRViewController {
    UITextField *_address;
    UIButton *_back, *_fwd, *_reload;
    UILabel *_status;
    UIActivityIndicatorView *_spin;
    BRPageView *_page;
    NSMutableArray *_history; NSInteger _pos;
    NSUInteger _loadToken;
    BOOL _loading;
}

- (UIButton *)barButton:(NSString *)title action:(SEL)sel {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:RGBc(0,102,214) forState:UIControlStateNormal];
    [b setTitleColor:RGBc(190,190,196) forState:UIControlStateDisabled];
    b.titleLabel.font = [UIFont boldSystemFontOfSize:22];
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    return b;
}

- (void)loadView {
    UIView *v = [[UIView alloc] initWithFrame:[UIScreen mainScreen].applicationFrame];
    v.backgroundColor = RGBc(247,247,250);
    CGFloat W = v.bounds.size.width;

    _back = [self barButton:@"‹" action:@selector(goBack)];  _back.frame = CGRectMake(2, 6, 32, 32);
    _fwd  = [self barButton:@"›" action:@selector(goForward)]; _fwd.frame = CGRectMake(32, 6, 32, 32);
    _reload = [self barButton:@"↻" action:@selector(reloadOrStop)]; _reload.frame = CGRectMake(W - 36, 6, 32, 32);

    _address = [[UITextField alloc] initWithFrame:CGRectMake(66, 7, W - 106, 30)];
    _address.borderStyle = UITextBorderStyleRoundedRect;
    _address.font = [UIFont systemFontOfSize:15];
    _address.placeholder = L(@"Address or search");
    _address.keyboardType = UIKeyboardTypeURL;
    _address.returnKeyType = UIReturnKeyGo;
    _address.autocapitalizationType = UITextAutocapitalizationTypeNone;
    _address.autocorrectionType = UITextAutocorrectionTypeNo;
    _address.clearButtonMode = UITextFieldViewModeWhileEditing;
    _address.delegate = self;

    _status = [[UILabel alloc] initWithFrame:CGRectMake(10, 40, W - 40, 16)];
    _status.font = [UIFont systemFontOfSize:11]; _status.textColor = RGBc(110,110,115); _status.backgroundColor = [UIColor clearColor];
    _spin = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    _spin.frame = CGRectMake(W - 26, 40, 16, 16); _spin.hidesWhenStopped = YES;

    UIView *line = [[UIView alloc] initWithFrame:CGRectMake(0, 59.5, W, 0.5)]; line.backgroundColor = RGBc(200,200,206);
    _page = [[BRPageView alloc] initWithFrame:CGRectMake(0, 60, W, v.bounds.size.height - 60)];
    _page.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    __weak BRViewController *ws = self;
    _page.onLink = ^(NSURL *u) { [ws open:u push:YES]; };

    for (UIView *x in @[_back, _fwd, _address, _reload, _status, _spin, line, _page]) [v addSubview:x];
    self.view = v;

    _history = [NSMutableArray array]; _pos = -1;
    [self showStart];
    [self updateButtons];
}

#pragma mark - Startseite

- (void)showStart {
    NSMutableArray *blocks = [NSMutableArray array];
    BRBlock *h = [BRBlock new]; h.kind = BRBlockHeading; h.level = 1; h.text = [[NSAttributedString alloc] initWithString:L(@"Browser")];
    [blocks addObject:h];
    BRBlock *p = [BRBlock new]; p.kind = BRBlockParagraph;
    p.text = [[NSAttributedString alloc] initWithString:L(@"Secure reading mode: modern encryption with certificate check, no JavaScript, no trackers. Enter an address or a search term above.")];
    [blocks addObject:p];
    NSArray *links = @[@[@"Wikipedia", @"https://de.m.wikipedia.org/"],
                       @[L(@"Search (DuckDuckGo)"), @"https://html.duckduckgo.com/html/"],
                       @[@"Tagesschau", @"https://www.tagesschau.de/"],
                       @[@"Hacker News", @"https://news.ycombinator.com/"]];
    for (NSArray *l in links) {
        BRBlock *b = [BRBlock new]; b.kind = BRBlockListItem; b.level = 1; b.bullet = @"•";
        b.text = [[NSAttributedString alloc] initWithString:l[0] attributes:@{ BRAttrLink: [NSURL URLWithString:l[1]] }];
        [blocks addObject:b];
    }
    BRDocument *d = [BRDocument new]; d.blocks = blocks;
    [_page showDocument:d];
    _status.text = @"";
}

#pragma mark - Navigation

- (NSURL *)urlFromInput:(NSString *)s {
    s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!s.length) return nil;
    NSString *low = s.lowercaseString;
    if ([low hasPrefix:@"https://"] || [low hasPrefix:@"http://"]) return [NSURL URLWithString:s];
    if ([s rangeOfString:@" "].location == NSNotFound && [s rangeOfString:@"."].location != NSNotFound) {
        NSURL *u = [NSURL URLWithString:[@"https://" stringByAppendingString:s]];
        if (u.host.length) return u;
    }
    NSString *q = (__bridge_transfer NSString *)CFURLCreateStringByAddingPercentEscapes(NULL, (__bridge CFStringRef)s, NULL,
                                                    CFSTR("!*'();:@&=+$,/?%#[]{}\" "), kCFStringEncodingUTF8);
    return [NSURL URLWithString:[@"https://html.duckduckgo.com/html/?q=" stringByAppendingString:q]];
}

- (BOOL)textFieldShouldReturn:(UITextField *)tf {
    NSURL *u = [self urlFromInput:tf.text];
    if (u) { [tf resignFirstResponder]; [self open:u push:YES]; }
    return NO;
}

- (void)open:(NSURL *)url push:(BOOL)push {
    if (push) {
        while ((NSInteger)_history.count > _pos + 1) [_history removeLastObject];
        [_history addObject:url]; _pos = _history.count - 1;
    }
    _address.text = url.absoluteString;
    [self load:url];
}

- (void)goBack { if (_pos > 0) { _pos--; [self open:_history[_pos] push:NO]; } else if (_pos == 0) { _pos = -1; _address.text = @""; [self showStart]; [self updateButtons]; } }
- (void)goForward { if (_pos + 1 < (NSInteger)_history.count) { _pos++; [self open:_history[_pos] push:NO]; } }
- (void)reloadOrStop {
    if (_loading) { _loadToken++; [self setLoading:NO]; _status.text = L(@"Stopped"); return; }
    if (_pos >= 0) [self load:_history[_pos]];
}

- (void)updateButtons {
    _back.enabled = _pos >= 0; _fwd.enabled = _pos + 1 < (NSInteger)_history.count;
    [_reload setTitle:_loading ? @"✕" : @"↻" forState:UIControlStateNormal];
}
- (void)setLoading:(BOOL)l { _loading = l; l ? [_spin startAnimating] : [_spin stopAnimating]; [self updateButtons]; }

#pragma mark - Laden

- (void)load:(NSURL *)url {
    NSUInteger token = ++_loadToken;
    [self setLoading:YES];
    _status.textColor = RGBc(110,110,115); _status.text = [NSString stringWithFormat:L(@"Loading %@ …"), url.host ?: @""];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        BRResponse *r = [BRNet fetch:url maxBytes:MAX_PAGE_BYTES];
        BRDocument *doc = nil; NSString *errTitle = nil, *errText = nil;
        NSString *ct = r.contentType.lowercaseString ?: @"";
        if (r.error) { errTitle = L(@"Page could not be loaded"); errText = r.error; }
        else if ([ct hasPrefix:@"image/"]) {
            BRBlock *b = [BRBlock new]; b.kind = BRBlockImage; b.imageURL = r.url; b.alt = @"";
            doc = [BRDocument new]; doc.blocks = @[b]; doc.title = r.url.lastPathComponent;
        } else if (!ct.length || [ct hasPrefix:@"text/html"] || [ct hasPrefix:@"application/xhtml"]) {
            doc = [BRHTML parse:[BRHTML decode:r.body contentType:r.contentType] baseURL:r.url];
        } else if ([ct hasPrefix:@"text/"] || [ct hasPrefix:@"application/json"]) {
            doc = [BRHTML plainText:[BRHTML decode:r.body contentType:r.contentType]];
        } else { errTitle = L(@"File type not supported"); errText = r.contentType; }
        if (doc && !doc.blocks.count) { errTitle = L(@"Page is empty"); errText = L(@"This page probably needs JavaScript, which is disabled for your safety."); doc = nil; }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (token != self->_loadToken) return;      // inzwischen andere Seite angefordert
            [self setLoading:NO];
            if (r.url && self->_pos >= 0) { self->_history[self->_pos] = r.url; self->_address.text = r.url.absoluteString; }
            if (!doc) {
                [self->_page showMessage:errTitle detail:errText];
                self->_status.textColor = RGBc(204,40,40); self->_status.text = errTitle;
                return;
            }
            [self->_page showDocument:doc];
            if (r.secure) { self->_status.textColor = RGBc(30,140,60); self->_status.text = [NSString stringWithFormat:@"🔒 %@", doc.title.length ? doc.title : r.url.host]; }
            else { self->_status.textColor = RGBc(204,40,40); self->_status.text = [NSString stringWithFormat:L(@"⚠ Not encrypted – %@"), r.url.host ?: @""]; }
        });
    });
}
@end

#pragma mark - App

@interface BRAppDelegate : UIResponder <UIApplicationDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation BRAppDelegate
- (BOOL)application:(UIApplication *)a didFinishLaunchingWithOptions:(NSDictionary *)o {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [BRViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end
