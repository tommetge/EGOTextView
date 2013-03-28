//
//  EGOContentView.m
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import "EGOContentView.h"
#import <QuartzCore/QuartzCore.h>

@implementation EGOContentView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
    if (self) {
        [self setUserInteractionEnabled:NO];
        [self setBackgroundColor:[UIColor whiteColor]];
        [self.layer setGeometryFlipped:NO];
    }
	
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    if (_delegate) {
        [self.delegate drawText]; // reset layout on frame / orientation change
    }
}

- (void)drawRect:(CGRect)rect {
    if (_delegate) {
        [_delegate drawContentInRect:rect];
    }
}

@end
