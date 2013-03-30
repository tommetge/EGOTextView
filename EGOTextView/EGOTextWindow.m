//
//  EGOTextWindow.m
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

#import "EGOTextWindow.h"
#import "EGOLoupeView.h"
#import "EGOMagnifyView.h"
#import <QuartzCore/QuartzCore.h>

@interface EGOTextWindow () {
    @private
    UIView          *_view;
    EGOWindowType    _type;
    EGOSelectionType _selectionType;
    BOOL             _showing;
}

@end

@implementation EGOTextWindow

static const CGFloat kLoupeScale = 1.2f;
static const CGFloat kMagnifyScale = 1.0f;
static const NSTimeInterval kDefaultAnimationDuration = 0.15f;

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self setBackgroundColor:[UIColor clearColor]];
        [self updateWindowTransform];
        _type = EGOWindowLoupe;
    }
    return self;
}

- (NSInteger)selectionForRange:(NSRange)range {
    return range.location;
}

- (void)showFromView:(UIView *)view rect:(CGRect)rect {
    CGPoint pos = CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect));
    if (!_showing) {
        
        if (!_view) {
            UIView *view;
            if (_type == EGOWindowLoupe) {
                view = [[EGOLoupeView alloc] init];
            } else {
                view = [[EGOMagnifyView alloc] init];
            }
            [self addSubview:view];
            _view = view;
        }
        
        CGRect frame = _view.frame;
        frame.origin.x = floorf(pos.x - (_view.bounds.size.width/2) + (rect.size.width/2));
        frame.origin.y = floorf(pos.y - _view.bounds.size.height);
        
        if (_type == EGOWindowMagnify) {
            
            frame.origin.y = MAX(frame.origin.y+8.0f, 0.0f);
            frame.origin.x += 2.0f;
            
        } else {
            
            frame.origin.y = MAX(frame.origin.y-10.0f, -40.0f);
            
        }
        
        CGRect originFrame = frame;
        frame.origin.y += frame.size.height/2;
        _view.frame = frame;
        _view.transform = CGAffineTransformMakeScale(0.01f, 0.01f);
        _view.alpha = 0.01f;
        [UIView animateWithDuration:kDefaultAnimationDuration
                         animations:^{
                             _view.alpha = 1.0f;
                             _view.transform = CGAffineTransformMakeScale(1.0f, 1.0f);
                             _view.frame = originFrame;
                         }
                         completion:^(BOOL finished) {
                             _showing=YES;
                             dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (0.01f*NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                 [self renderWithContentView:view fromRect:rect];
                             });
                         }];
        
    }
}

- (void)hide:(BOOL)animated {
    
    if (_view) {
        
        [UIView animateWithDuration:kDefaultAnimationDuration animations:^{
            
            CGRect frame = _view.frame;
            CGPoint center = _view.center;
            frame.origin.x = floorf(center.x-(frame.size.width/2));
            frame.origin.y = center.y;
            _view.frame = frame;
            _view.transform = CGAffineTransformMakeScale(0.01f, 0.01f);
            
        } completion:^(BOOL finished) {
            
            _showing=NO;
            [_view removeFromSuperview];
            _view=nil;
            self.windowLevel = UIWindowLevelNormal;
            self.hidden = YES;
            
        }];
        
    }
    
}

- (UIImage *)screenshotFromCaretFrame:(CGRect)rect inView:(UIView *)view scale:(BOOL)scale {
	
    CGRect offsetRect = [self convertRect:rect toView:view];
    offsetRect.origin.y -= (_view.bounds.size.height/2 + (_type == EGOWindowMagnify ? -17.0f : 20.0f));
    offsetRect.origin.x -= (_view.bounds.size.width/2);

    UIGraphicsBeginImageContextWithOptions(_view.bounds.size, YES, [[UIScreen mainScreen] scale]);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:1.0f green:1.0f blue:1.0f alpha:1.0f].CGColor);
    UIRectFill(CGContextGetClipBoundingBox(ctx));
    
    CGContextSaveGState(ctx);
	CGContextTranslateCTM(ctx, -offsetRect.origin.x, -offsetRect.origin.y);
    
    [view.layer renderInContext:ctx];
    
    CGContextRestoreGState(ctx);
    UIImage *aImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return aImage;
    
}

- (void)renderWithContentView:(UIView *)view fromRect:(CGRect)rect {
    CGPoint pos = CGPointMake(CGRectGetMinX(rect), CGRectGetMinY(rect));
	
    if (_showing && _view) {
        CGRect frame = _view.frame;
        frame.origin.x = floorf((pos.x - (_view.bounds.size.width/2)) + (rect.size.width/2));
        frame.origin.y = floorf(pos.y - _view.bounds.size.height);
        
        if (_type == EGOWindowMagnify) {
            frame.origin.y = MAX(0.0f, frame.origin.y);
        } else {
            frame.origin.y = MAX(frame.origin.y-10.0f, -40.0f);
        }
        _view.frame = frame;
        
        UIImage *image = [self screenshotFromCaretFrame:rect inView:view scale:(_type == EGOWindowMagnify)];
        [(EGOLoupeView *)_view setContentImage:image];
    }
}

- (void)updateWindowTransform {
    self.frame = [[UIScreen mainScreen] bounds];
    switch ([[UIApplication sharedApplication] statusBarOrientation]) {
        case UIInterfaceOrientationPortrait:
            self.layer.transform = CATransform3DIdentity;
            break;
        case UIInterfaceOrientationLandscapeRight:
            self.layer.transform = CATransform3DMakeRotation((M_PI/180)*90, 0, 0, 1);
            break;
        case UIInterfaceOrientationLandscapeLeft:
            self.layer.transform = CATransform3DMakeRotation((M_PI/180)*-90, 0, 0, 1);
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            self.layer.transform = CATransform3DMakeRotation((M_PI/180)*180, 0, 0, 1);
            break;
        default:
            break;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateWindowTransform];
}

@end
