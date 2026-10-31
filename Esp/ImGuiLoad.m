#import "ImGuiLoad.h"
#import "ImGuiDrawView.h"

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
    [ImGuiDrawView showChange:YES];
}

- (void)hide
{
    [ImGuiDrawView showChange:NO];
}

@end
