//
//  LSSTextView.m
//  EGOTextView_Demo
//
//  Created by Chris Brauchli on 11/13/12.
//
//

#import "LSOTextView.h"

NSString * const kLSOStrikeOutAttributeName = @"LSOStrikeOutAttribute";
NSString * const kLSOBackgroundFillColorAttributeName = @"LSOBackgroundFillColor";
NSString * const kLSOBackgroundStrokeColorAttributeName = @"LSOBackgroundStrokeColor";
NSString * const kLSOBackgroundLineWidthAttributeName = @"LSOBackgroundLineWidth";
NSString * const kLSOBackgroundCornerRadiusAttributeName = @"LSOBackgroundCornerRadius";

NSString * const kLSOTaggedObjectTagAttributeName = @"LSOTaggedObjectTagAttribute";
NSString * const kLSOTaggedObjectNameAttributeName = @"LSOTaggedObjectNameAttribute";

@interface LSOTextView () <EGOTextViewDrawDelegate>

@end

@implementation LSOTextView


#pragma mark - Init

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.drawDelegate = self;
    }
    return self;
}


- (id)init {
    self = [self initWithFrame:CGRectZero];
    return self;
}


- (id)initWithCoder: (NSCoder *)aDecoder {
    if ((self = [super initWithCoder: aDecoder])) {
        self.drawDelegate = self;
    }
    return self;
}


#pragma mark - EGOTextViewDrawDelegate

- (void)egoTextView:(EGOTextView *)textView drawBeforeGlyphRun:(CTRunRef)glyphRun forLine:(CTLineRef)line withOrigin:(CGPoint)origin inContext:(CGContextRef)context
{
//    return;
//    NSDictionary *attributes = (NSDictionary *)CTRunGetAttributes(glyphRun);
    CGRect runBounds = CGRectZero;
    CGFloat ascent = 0.0f;
    CGFloat descent = 0.0f;
    
    runBounds = CTRunGetImageBounds(glyphRun, context, CFRangeMake(0, 0));
  
    runBounds.size.width = CTRunGetTypographicBounds(glyphRun, CFRangeMake(0, 0), &ascent, &descent, NULL);
    CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
    runBounds.size.height = ascent + descent;
  
    CGFloat xOffset = CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(glyphRun).location, NULL);
    runBounds.origin.x = origin.x + textView.bounds.origin.x + xOffset;
    runBounds.origin.y = origin.y + textView.bounds.origin.y;
    runBounds.origin.y -= descent;
  
    runBounds = CGRectInset(CGRectInset(runBounds, -1.0f, -3.0f), 0.f, 0.f);
    
    CGPathRef path = [[UIBezierPath bezierPathWithRoundedRect:runBounds cornerRadius:5.f] CGPath];
    
    CGContextSetLineJoin(context, kCGLineJoinRound);
    
    CGColorRef fillColor = [UIColor redColor].CGColor;
    
    if (fillColor) {
        CGContextSetFillColorWithColor(context, fillColor);
        CGContextAddPath(context, path);
        CGContextFillPath(context);
    }
    
    runBounds.size.width = CTRunGetTypographicBounds(glyphRun, CFRangeMake(0, 0), &ascent, &descent, NULL);
    
    runBounds.size.height = ascent + descent;
    
    
//
//    CGPoint position;
//    CTRunGetPositions(glyphRun, CFRangeMake(0, 1), &position);
//    
//    CGRect theRect = { { origin.x + position.x, origin.y + position.y }, size };
}


- (void)egoTextView:(EGOTextView *)textView drawAfterGlyphRun:(CTRunRef)glyphRun forLine:(CTLineRef)line withOrigin:(CGPoint)origin inContext:(CGContextRef)context
{
    
}

@end
