//
//  EGOContentView.h
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import <UIKit/UIKit.h>

@protocol EGOContentViewDelegate <NSObject>

- (void)drawText;
- (void)drawContentInRect:(CGRect)frame;

@end

@interface EGOContentView : UIView

@property (weak) id<EGOContentViewDelegate> delegate;

@end
