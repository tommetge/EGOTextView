//
//  EGOCaretView.m
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import "EGOCaretView.h"
#import "EGOTextView.h"
#import <QuartzCore/QuartzCore.h>

@interface EGOCaretView () {
    NSTimer *_blinkTimer;
}

@end

@implementation EGOCaretView

static const NSTimeInterval kInitialBlinkDelay = 0.6f;
static const NSTimeInterval kBlinkRate = 1.0;

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
    if (self) {
        [self setBackgroundColor:[EGOTextView caretColor]];
    }
    return self;
}

- (void)show {
    [self.layer removeAllAnimations];
}

- (void)didMoveToSuperview {
    if (self.superview) {
        [self delayBlink];
    } else {
        [self.layer removeAllAnimations];
    }
}

- (void)delayBlink {
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    [animation setValues:@[[NSNumber numberWithFloat:1.0f],
                           [NSNumber numberWithFloat:1.0f],
                           [NSNumber numberWithFloat:0.0f],
                           [NSNumber numberWithFloat:0.0f]]];
    [animation setCalculationMode:kCAAnimationCubic];
    [animation setDuration:kBlinkRate];
    [animation setBeginTime:CACurrentMediaTime() + kInitialBlinkDelay];
    [animation setRepeatCount:CGFLOAT_MAX];
    [self.layer addAnimation:animation forKey:@"BlinkAnimation"];
}

@end
