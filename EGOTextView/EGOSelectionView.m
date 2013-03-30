//
//  EGOSelectionView.m
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

#import "EGOSelectionView.h"
#import "EGOTextView.h"
#import <QuartzCore/QuartzCore.h>

@implementation EGOSelectionView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
    if (self) {
        [self setBackgroundColor:[UIColor clearColor]];
        [self setUserInteractionEnabled:NO];
        [self.layer setGeometryFlipped:NO];
    }
	
    return self;
}

- (void)setBeginCaret:(CGRect)begin endCaret:(CGRect)end {
    if (!self.superview) return;
    
    self.frame = CGRectMake(begin.origin.x,
                            begin.origin.y + begin.size.height,
                            end.origin.x - begin.origin.x,
                            (end.origin.y - end.size.height) - begin.origin.y);
    begin = [self.superview convertRect:begin toView:self];
    end = [self.superview convertRect:end toView:self];
    
    
    if (!_leftCaret) {
        UIView *view = [[UIView alloc] initWithFrame:begin];
        view.backgroundColor = [EGOTextView caretColor];
        [self addSubview:view];
        _leftCaret=view;
    }
    
    if (!_leftDot) {
        UIImage *dotImage = [UIImage imageNamed:@"drag-dot.png"];
        UIImageView *view = [[UIImageView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, dotImage.size.width, dotImage.size.height)];
        [view setImage:dotImage];
        [self addSubview:view];
        _leftDot = view;
    }
    
    CGFloat _dotShadowOffset = 5.0f;
    _leftCaret.frame = begin;
    _leftDot.frame = CGRectMake(floorf(_leftCaret.center.x - (_leftDot.bounds.size.width/2)),
                                _leftCaret.frame.origin.y-(_leftDot.bounds.size.height-_dotShadowOffset),
                                _leftDot.bounds.size.width,
                                _leftDot.bounds.size.height);
    
    if (!_rightCaret) {
        UIView *view = [[UIView alloc] initWithFrame:end];
        view.backgroundColor = [EGOTextView caretColor];
        [self addSubview:view];
        _rightCaret = view;
    }
    
    if (!_rightDot) {
        UIImage *dotImage = [UIImage imageNamed:@"drag-dot.png"];
        UIImageView *view = [[UIImageView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, dotImage.size.width, dotImage.size.height)];
        [view setImage:dotImage];
        [self addSubview:view];
        _rightDot = view;
    }
    
    _rightCaret.frame = end;
    _rightDot.frame = CGRectMake(floorf(_rightCaret.center.x - (_rightDot.bounds.size.width/2)),
                                 CGRectGetMaxY(_rightCaret.frame),
                                 _rightDot.bounds.size.width,
                                 _rightDot.bounds.size.height);
}

@end
