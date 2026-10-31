#import "PubgLoad.h"
#import <UIKit/UIKit.h>
#import "ImGuiLoad.h"
#import "ImGuiDrawView.h"
#import "oxsak_badge_data.h"

// =========================================================================
// Floating OXSAK Launcher Button
// 56x56 pt circular badge with glowing orange border and skull logo
// Draggable, screen bounds clamped, position persisted to NSUserDefaults
// =========================================================================
@interface FloatingOXSAKButton : UIView
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, strong) UIImageView *badgeImageView;
@end

@implementation FloatingOXSAKButton {
    CGPoint _viewStart;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0.063f green:0.063f blue:0.078f alpha:0.95f]; // #101014
        self.layer.cornerRadius = frame.size.width / 2.0f;
        self.layer.masksToBounds = NO;
        self.layer.borderColor = [UIColor colorWithRed:1.0f green:0.54f blue:0.0f alpha:1.0f].CGColor; // #FF8A00
        self.layer.borderWidth = 2.0f;
        
        // Glowing orange outer shadow
        self.layer.shadowColor = [UIColor colorWithRed:1.0f green:0.54f blue:0.0f alpha:0.85f].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 0);
        self.layer.shadowRadius = 8.0f;
        self.layer.shadowOpacity = 0.85f;
        
        // Embedded OXSAK logo badge image view
        _badgeImageView = [[UIImageView alloc] initWithFrame:CGRectInset(self.bounds, 4, 4)];
        _badgeImageView.contentMode = UIViewContentModeScaleAspectFit;
        _badgeImageView.layer.cornerRadius = (frame.size.width - 8) / 2.0f;
        _badgeImageView.layer.masksToBounds = YES;
        
        // Decode base64 emblem data
        NSData *imageData = [[NSData alloc] initWithBase64EncodedString:[NSString stringWithUTF8String:g_OXSAKBadgeBase64]
                                                                options:NSDataBase64DecodingIgnoreUnknownCharacters];
        if (imageData) {
            _badgeImageView.image = [UIImage imageWithData:imageData];
        }
        [self addSubview:_badgeImageView];
        
        // Drag (pan) gesture
        UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:pan];
        
        // Tap gesture
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
        [self addGestureRecognizer:tap];
    }
    return self;
}

- (void)handleTap:(UITapGestureRecognizer *)tap {
    // Subtle bounce feedback
    [UIView animateWithDuration:0.1 animations:^{
        self.transform = CGAffineTransformMakeScale(0.92f, 0.92f);
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.1 animations:^{
            self.transform = CGAffineTransformIdentity;
        }];
    }];
    
    if (self.onTap) {
        self.onTap();
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    UIWindow *window = self.window ?: [PubgLoad findKeyWindow];
    if (!window) return;
    
    CGPoint translation = [pan translationInView:window];
    if (pan.state == UIGestureRecognizerStateBegan) {
        _viewStart = self.center;
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        self.center = CGPointMake(_viewStart.x + translation.x, _viewStart.y + translation.y);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGRect screenBounds = window.bounds;
        CGFloat radius = self.frame.size.width / 2.0f;
        CGFloat minX = 12.0f + radius;
        CGFloat maxX = screenBounds.size.width - 12.0f - radius;
        CGFloat minY = 24.0f + radius;
        CGFloat maxY = screenBounds.size.height - 24.0f - radius;
        
        CGPoint finalCenter = self.center;
        finalCenter.x = MAX(minX, MIN(maxX, finalCenter.x));
        finalCenter.y = MAX(minY, MIN(maxY, finalCenter.y));
        
        [UIView animateWithDuration:0.25 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            self.center = finalCenter;
        } completion:^(BOOL finished) {
            [[NSUserDefaults standardUserDefaults] setFloat:finalCenter.x forKey:@"OXSAK_Launcher_X"];
            [[NSUserDefaults standardUserDefaults] setFloat:finalCenter.y forKey:@"OXSAK_Launcher_Y"];
            [[NSUserDefaults standardUserDefaults] synchronize];
        }];
    }
}
@end

@interface PubgLoad ()
@property (nonatomic, strong) ImGuiDrawView *vna;
@property (nonatomic, strong) FloatingOXSAKButton *floatingButton;
@property (nonatomic, assign) BOOL isMenuOpen;
@property (nonatomic, strong) NSTimer *attachTimer;
@end

@implementation PubgLoad

static PubgLoad *g_SharedInstance = nil;

+ (UIWindow *)findKeyWindow
{
    // 1. Try modern UIWindowScene API (iOS 13 - iOS 18)
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if ([scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *w in windowScene.windows) {
                if (w.isKeyWindow) {
                    return w;
                }
            }
        }
    }
    // 2. Try classic keyWindow
    if ([UIApplication sharedApplication].keyWindow) {
        return [UIApplication sharedApplication].keyWindow;
    }
    // 3. Fallback to first available window
    if ([UIApplication sharedApplication].windows.count > 0) {
        return [UIApplication sharedApplication].windows.firstObject;
    }
    return nil;
}

static const NSInteger kOXSAKOverlayTag  = 0x5A4;
static const NSInteger kOXSAKLauncherTag = 0x5A5;

+ (void)load
{
    [super load];
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            g_SharedInstance = [[PubgLoad alloc] init];
            [g_SharedInstance startOverlay];
        });
    });
}

- (void)startOverlay
{
    static dispatch_once_t startOverlayOnce;
    dispatch_once(&startOverlayOnce, ^{
        self->_vna = [ImGuiDrawView sharedInstance];
        self->_vna.view.tag = kOXSAKOverlayTag;

        self->_isMenuOpen = NO;
        [ImGuiDrawView showChange:NO];

        [self setupFloatingButton];
        [self tryAttachView];

        // Keep checking until the overlay view is successfully attached to the hierarchy
        self.attachTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                            target:self
                                                          selector:@selector(tryAttachView)
                                                          userInfo:nil
                                                           repeats:YES];

        [self setupGesture];
    });
}

- (void)setupFloatingButton
{
    if (_floatingButton) return;
    
    // Restore cached position from NSUserDefaults or use safe default
    CGFloat x = [[NSUserDefaults standardUserDefaults] floatForKey:@"OXSAK_Launcher_X"];
    CGFloat y = [[NSUserDefaults standardUserDefaults] floatForKey:@"OXSAK_Launcher_Y"];
    if (x <= 10.0f || y <= 10.0f) {
        x = 45.0f;
        y = 120.0f;
    }
    
    _floatingButton = [[FloatingOXSAKButton alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
    _floatingButton.center = CGPointMake(x, y);
    _floatingButton.tag = kOXSAKLauncherTag;
    
    __weak PubgLoad *weakSelf = self;
    _floatingButton.onTap = ^{
        [weakSelf toggleMenu];
    };
}

- (void)tryAttachView
{
    UIWindow *window = [PubgLoad findKeyWindow];
    if (window) {
        UIView *targetContainer = window; // Attach directly to UIWindow for clean presentation above root view and safe modal dialog flow
        
        // Remove any stale duplicate overlays if present
        for (UIView *subview in targetContainer.subviews) {
            if (subview.tag == kOXSAKOverlayTag && subview != _vna.view) {
                [subview removeFromSuperview];
            }
            if (subview.tag == kOXSAKLauncherTag && subview != _floatingButton) {
                [subview removeFromSuperview];
            }
        }

        // Attach ImGui overlay view (Singleton)
        if (_vna && _vna.view.superview != targetContainer) {
            [_vna.view removeFromSuperview];
            _vna.view.tag = kOXSAKOverlayTag;
            [targetContainer addSubview:_vna.view];
        }
        
        // Attach Floating OXSAK Button
        if (_floatingButton && _floatingButton.superview != targetContainer) {
            [_floatingButton removeFromSuperview];
            _floatingButton.tag = kOXSAKLauncherTag;
            [targetContainer addSubview:_floatingButton];
        }
        
        // Ensure overlay and launcher are top-most
        if (_vna && _vna.view.superview == targetContainer) {
            [targetContainer bringSubviewToFront:_vna.view];
        }
        if (_floatingButton && _floatingButton.superview == targetContainer) {
            [targetContainer bringSubviewToFront:_floatingButton];
        }
        
        // Invalidate timer once attached
        if (_vna.view.superview && _vna.view.frame.size.width > 0 && _floatingButton.superview) {
            [self.attachTimer invalidate];
            self.attachTimer = nil;
        }
    }
}

- (void)setupGesture
{
    UIWindow *win = [PubgLoad findKeyWindow];
    if (!win) return;
    
    // Check if double-tap gesture already exists to prevent duplicate handlers
    for (UIGestureRecognizer *g in win.gestureRecognizers) {
        if ([g isKindOfClass:[UITapGestureRecognizer class]]) {
            UITapGestureRecognizer *tg = (UITapGestureRecognizer *)g;
            if (tg.numberOfTapsRequired == 2 && tg.numberOfTouchesRequired == 2) {
                return; // Already attached
            }
        }
    }

    // Double tap with 2 fingers toggles the menu open/closed
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)];
    tap.numberOfTapsRequired = 2;
    tap.numberOfTouchesRequired = 2;
    tap.cancelsTouchesInView = NO;
    [win addGestureRecognizer:tap];
}

- (void)toggleMenu
{
    BOOL open = ![ImGuiDrawView isMenuOpen];
    _isMenuOpen = open;
    [ImGuiDrawView showChange:open];
}

@end
