//
//  EGOTextWindow.h
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import <UIKit/UIKit.h>
#import "EGOSelectionView.h"

typedef enum {
    EGOWindowLoupe = 0,
    EGOWindowMagnify,
} EGOWindowType;

@interface EGOTextWindow : UIWindow

@property (nonatomic, assign) EGOWindowType type;
@property (nonatomic, assign) EGOSelectionType selectionType;
@property (nonatomic, readonly, getter=isShowing) BOOL showing;

- (void)renderWithContentView:(UIView*)view fromRect:(CGRect)rect;
- (void)showFromView:(UIView*)view rect:(CGRect)rect;
- (void)hide:(BOOL)animated;
- (void)updateWindowTransform;

@end
