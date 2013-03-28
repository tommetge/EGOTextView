//
//  EGOSelectionView.h
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import <UIKit/UIKit.h>

typedef enum {
    EGOSelectionTypeLeft = 0,
    EGOSelectionTypeRight,
} EGOSelectionType;

@interface EGOSelectionView : UIView {
    @private
    UIView *_leftDot;
    UIView *_rightDot;
    UIView *_leftCaret;
    UIView *_rightCaret;
}

- (void)setBeginCaret:(CGRect)begin endCaret:(CGRect)rect;

@end
