//
//  ImGuiDrawView.h
//  ImGuiTest
//
//  Created by yiming on 2021/6/2.
//

#import <UIKit/UIKit.h>
NS_ASSUME_NONNULL_BEGIN

@interface ImGuiDrawView : UIViewController

///
+ (void)showChange:(BOOL)open;
+ (BOOL)isMenuOpen;
+ (void)clearData;


@end

NS_ASSUME_NONNULL_END
