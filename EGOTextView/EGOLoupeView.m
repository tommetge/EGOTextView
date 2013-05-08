//
//  EGOLoupeView.m
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

#import "EGOLoupeView.h"

@interface EGOLoupeView () {
    @private
    UIImage *_contentImage;
}

@end

@implementation EGOLoupeView

- (id)init {
    if ((self = [super initWithFrame:CGRectMake(0.0f, 0.0f, 126.0f, 126.0f)])) {
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    UIImage *image = [UIImage imageNamed:@"LoupeOverlay.png"];
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    if (_contentImage) {
        CGContextSaveGState(ctx);
        CGContextBeginPath(ctx);
        CGContextAddEllipseInRect(ctx, CGRectInset((CGRect){{0, 0}, [image size]}, 4, 4));
        CGContextClip(ctx);
        [_contentImage drawInRect:rect];
        CGContextRestoreGState(ctx);
    }
    
    [image drawInRect:rect];
}

- (void)setContentImage:(UIImage *)image {    
    _contentImage = image;
    [self setNeedsDisplay];
}

@end
