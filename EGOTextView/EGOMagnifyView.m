//
//  EGOMagnifyView.m
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import "EGOMagnifyView.h"

@interface EGOMagnifyView () {
    @private
    UIImage *_contentImage;
}

@end

@implementation EGOMagnifyView

- (id)init {
	self = [super initWithFrame:CGRectMake(0.0f, 0.0f, 145.0f, 59.0f)];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    [[UIImage imageNamed:@"magnifier-ranged-lo.png"] drawInRect:rect];
    
    if (_contentImage) {
        CGContextSaveGState(ctx);
        CGContextClipToMask(ctx, rect, [UIImage imageNamed:@"magnifier-ranged-mask.png"].CGImage);
        [_contentImage drawInRect:rect];
        CGContextRestoreGState(ctx);
    }
    
    [[UIImage imageNamed:@"magnifier-ranged-hi.png"] drawInRect:rect];
}

- (void)setContentImage:(UIImage *)image {
    _contentImage = image;
    [self setNeedsDisplay];
}

@end
