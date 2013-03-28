//
//  EGOLoupeView.m
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
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
