#import "PubgLoad.h"
#import <UIKit/UIKit.h>
#import "ImGuiLoad.h"
#import "ImGuiDrawView.h"

@interface PubgLoad ()
@property (nonatomic, strong) ImGuiDrawView *vna;
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
    if (!_vna) {
        _vna = [[ImGuiDrawView alloc] init];
    }

    _isMenuOpen = YES;
    [ImGuiDrawView showChange:YES];

    // Try attaching immediately
    [self tryAttachView];

    // Keep checking every 1 second until the overlay view is successfully added to the screen
    self.attachTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                        target:self
                                                      selector:@selector(tryAttachView)
                                                      userInfo:nil
                                                       repeats:YES];

    // Add gesture recognizer to toggle menu (Double-tap with 2 fingers)
    [self setupGesture];
}

- (void)tryAttachView
{
    UIWindow *window = [PubgLoad findKeyWindow];
    if (window) {
        if (window.rootViewController && window.rootViewController.view) {
            if (_vna.view.superview != window.rootViewController.view) {
                [_vna.view removeFromSuperview];
                [window.rootViewController.view addSubview:_vna.view];
                [window.rootViewController.view bringSubviewToFront:_vna.view];
            }
        } else {
            if (_vna.view.superview != window) {
                [_vna.view removeFromSuperview];
                [window addSubview:_vna.view];
                [window bringSubviewToFront:_vna.view];
            }
        }
        
        // If view is attached and has non-zero size, we can slow down or stop the timer
        if (_vna.view.superview && _vna.view.frame.size.width > 0) {
            [self.attachTimer invalidate];
            self.attachTimer = nil;
        }
    }
}

- (void)setupGesture
{
    // Double tap with 2 fingers toggles the menu open/closed
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleMenu)];
    tap.numberOfTapsRequired = 2;
    tap.numberOfTouchesRequired = 2;
    tap.cancelsTouchesInView = NO;
    
    UIWindow *win = [PubgLoad findKeyWindow];
    if (win) {
        [win addGestureRecognizer:tap];
    }
}

- (void)toggleMenu
{
    _isMenuOpen = !_isMenuOpen;
    [ImGuiDrawView showChange:_isMenuOpen];
}

@end
