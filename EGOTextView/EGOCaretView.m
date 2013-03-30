//
//  EGOCaretView.m
//
//  Created by Devin Doty on 4/18/11.
//  Copyright (C) 2011 by enormego.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
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
