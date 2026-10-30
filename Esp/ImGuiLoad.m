#import "ImGuiLoad.h"
#import "ImGuiDrawView.h"

@interface ImGuiLoad()
@property (nonatomic, strong) ImGuiDrawView *vna;
@end

@implementation ImGuiLoad

+ (instancetype)share
{
    static ImGuiLoad *tool;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tool = [[ImGuiLoad alloc] init];
    });
    return tool;
}

- (void)show
{
    if (!_vna) {
        ImGuiDrawView *vc = [[ImGuiDrawView alloc] init];
        _vna = vc;
    }

    [ImGuiDrawView showChange:true];
    
    UIWindow *win = [UIApplication sharedApplication].keyWindow;
    if (!win && [UIApplication sharedApplication].windows.count > 0) {
        win = [UIApplication sharedApplication].windows.firstObject;
    }
    if (win) {
        if (win.rootViewController && win.rootViewController.view) {
            [win.rootViewController.view addSubview:_vna.view];
        } else {
            [win addSubview:_vna.view];
        }
    }
}

- (void)hide
{
    if (!_vna) {
        ImGuiDrawView *vc = [[ImGuiDrawView alloc] init];
        _vna = vc;
    }
    
    [ImGuiDrawView showChange:false];
}

@end
