//
//  EGOContentView.m
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

#import "EGOContentView.h"
#import "EGOTextView+Protected.h"
#import <QuartzCore/QuartzCore.h>
#import "EGOIndexedRange.h"

@interface EGOContentView() {
    CTFramesetterRef _framesetter;
    CTFrameRef       _frame;
}

@property (nonatomic, assign) dispatch_semaphore_t drawLock;

@end

@implementation EGOContentView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
    if (self) {
        [self setUserInteractionEnabled:NO];
        [self setBackgroundColor:[UIColor whiteColor]];
        [self.layer setGeometryFlipped:NO];
        
        _frame = NULL;
        _framesetter = NULL;
    }
	
    return self;
}

- (dispatch_semaphore_t)drawLock {
	if (!_drawLock) {
		_drawLock = dispatch_semaphore_create(1);
	}
	
	return _drawLock;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    [self drawText];
}

- (void)drawRect:(CGRect)rect {
    [self drawContentInRect:rect];
}

- (void)drawText {
	dispatch_semaphore_wait(self.drawLock, DISPATCH_TIME_FOREVER);
    
    [self clearPreviousLayoutInformation];
	
    NSAttributedString *attributedString = _textView.attributedText;
    
    _framesetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attributedString);
    
    CGRect theRect = CGRectInset(CGRectMake(0.0f, 0.0f, _textView.frame.size.width, _textView.frame.size.height), 6.0f, 15.0f);
    CGFloat height = [self boundingHeightForWidth:theRect.size.width];
    theRect.size.height = height+_textView.font.lineHeight;
    self.frame = theRect;
    _textView.contentSize = CGSizeMake(_textView.frame.size.width, theRect.size.height+(_textView.font.lineHeight*2));
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:self.bounds];
    
    _frame =  CTFramesetterCreateFrame(_framesetter, CFRangeMake(0, 0), [path CGPath], NULL);
    
    for (UIView *view in _textView.attachmentViews) {
        [view removeFromSuperview];
    }
    [attributedString enumerateAttribute:EGOTextAttachmentAttributeName
								  inRange:NSMakeRange(0, [attributedString length])
								  options:0
							   usingBlock: ^(id value, NSRange range, BOOL *stop) {
								   if ([value respondsToSelector:@selector(attachmentView)]) {
									   UIView *view = [value attachmentView];
									   [_textView.attachmentViews addObject:view];
									   
									   CGRect rect = [self firstRectForNSRange:range];
									   rect.size = [view frame].size;
									   [view setFrame:rect];
									   [_textView addSubview:view];
								   }
							   }];
    
    [self setNeedsDisplay];
    
	dispatch_semaphore_signal(self.drawLock);
}

- (CGFloat)boundingWidthForHeight:(CGFloat)height {
    CGSize suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(_framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, height), NULL);
    return suggestedSize.width;
}

- (CGFloat)boundingHeightForWidth:(CGFloat)width {
    CGSize suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(_framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(width, CGFLOAT_MAX), NULL);
    return suggestedSize.height;
}

#pragma mark - Drawing

- (void)drawPathFromRects:(NSArray *)array cornerRadius:(CGFloat)cornerRadius {
    if (!array || [array count] == 0) return;
    
    CGMutablePathRef _path = CGPathCreateMutable();
    
    CGRect firstRect = CGRectFromString([array objectAtIndex:0]);
    CGRect lastRect = CGRectFromString([array lastObject]);
    if ([array count] > 1) {
        firstRect.size.width = self.bounds.size.width-firstRect.origin.x;
    }
    
    if (cornerRadius > 0) {
        CGPathAddPath(_path, NULL, [UIBezierPath bezierPathWithRoundedRect:firstRect cornerRadius:cornerRadius].CGPath);
        CGPathAddPath(_path, NULL, [UIBezierPath bezierPathWithRoundedRect:lastRect cornerRadius:cornerRadius].CGPath);
    } else {
        CGPathAddRect(_path, NULL, firstRect);
        CGPathAddRect(_path, NULL, lastRect);
    }
    
    if ([array count] > 1) {
		
        CGRect fillRect = CGRectZero;
        
        CGFloat originX = ([array count] == 2) ? MIN(CGRectGetMinX(firstRect), CGRectGetMinX(lastRect)) : 0.0f;
        CGFloat originY = firstRect.origin.y + firstRect.size.height;
        CGFloat width = ([array count] == 2) ? originX + MIN(CGRectGetMaxX(firstRect), CGRectGetMaxX(lastRect)) : self.bounds.size.width;
        CGFloat height =  MAX(0.0f, lastRect.origin.y - originY);
        
        fillRect = CGRectMake(originX, originY, width, height);
        
        if (cornerRadius > 0) {
            CGPathAddPath(_path, NULL, [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:cornerRadius].CGPath);
        } else {
            CGPathAddRect(_path, NULL, fillRect);
        }
    }
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextAddPath(ctx, _path);
    CGContextFillPath(ctx);
    CGPathRelease(_path);
}

- (void)drawBoundingRangeAsSelection:(NSRange)selectionRange cornerRadius:(CGFloat)cornerRadius {
    if (selectionRange.length == 0 || selectionRange.location == NSNotFound) {
        return;
    }
    
    NSMutableArray *pathRects = [[NSMutableArray alloc] init];
    NSArray *lines = (__bridge NSArray*)CTFrameGetLines(_frame);
    CGPoint *origins = (CGPoint*)malloc([lines count] * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, [lines count]), origins);
    NSInteger count = [lines count];
    
    for (int i = 0; i < count; i++) {
        CTLineRef line = (__bridge CTLineRef) [lines objectAtIndex:i];
        CFRange lineRange = CTLineGetStringRange(line);
        NSRange range = NSMakeRange(lineRange.location==kCFNotFound ? NSNotFound : lineRange.location, lineRange.length);
        NSRange intersection = NSIntersectionRange(range, selectionRange);
        
        if (intersection.location != NSNotFound && intersection.length > 0) {
            CGFloat xStart = CTLineGetOffsetForStringIndex(line, intersection.location, NULL);
            CGFloat xEnd = CTLineGetOffsetForStringIndex(line, intersection.location + intersection.length, NULL);
            
            CGPoint origin = origins[i];
            CGFloat ascent, descent;
            CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
            
            CGRect selectionRect = CGRectMake(origin.x + xStart, origin.y + ascent, xEnd - xStart, ascent + descent);
			selectionRect.origin.y = self.frame.size.height - selectionRect.origin.y;
            
            if (range.length == 1) {
                selectionRect.size.width = self.bounds.size.width;
            }
            
            [pathRects addObject:NSStringFromCGRect(selectionRect)];
        }
    }
    
    [self drawPathFromRects:pathRects cornerRadius:cornerRadius];
    free(origins);
}

- (void)drawContentInRect:(CGRect)rect {
	if (_textView.searchRanges && [_textView.searchRanges count] > 0) {
		[[UIColor colorWithRed:1.0f green:1.0f blue:0.0f alpha:1.0f] setFill];
        for (EGOIndexedRange *searchRange in _textView.searchRanges) {
            [self drawBoundingRangeAsSelection:searchRange.range cornerRadius:2.0f];
        }
	}
	
    CGPathRef framePath = CTFrameGetPath(_frame);
    CGRect frameRect = CGPathGetBoundingBox(framePath);
	
	NSArray *lines = (__bridge NSArray*)CTFrameGetLines(_frame);
    NSInteger count = [lines count];
	
    CGPoint *origins = (CGPoint *)malloc(count * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, count), origins);
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSaveGState(ctx);
	CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
    CGContextTranslateCTM(ctx, 0, self.frame.size.height);
    CGContextScaleCTM(ctx, 1.0, -1.0);
	for (int i = 0; i < count; i++) {
        CTLineRef line = (CTLineRef)CFArrayGetValueAtIndex((CFArrayRef)lines, i);
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        CFIndex runsCount = CFArrayGetCount(runs);
        
        if (_textView.drawDelegate) {
            for (CFIndex runsIndex = 0; runsIndex < runsCount; runsIndex++) {
                CTRunRef run = CFArrayGetValueAtIndex(runs, runsIndex);
                [_textView.drawDelegate egoTextView:_textView drawBeforeGlyphRun:run forLine:line withOrigin:origins[i] inContext:ctx];
            }
        }
        
        CGContextSetTextPosition(ctx, frameRect.origin.x + origins[i].x, frameRect.origin.y + origins[i].y);
        CTLineDraw(line, ctx);
        
        for (CFIndex runsIndex = 0; runsIndex < runsCount; runsIndex++) {
            CTRunRef run = CFArrayGetValueAtIndex(runs, runsIndex);
            
            if (_textView.drawDelegate) {
                [_textView.drawDelegate egoTextView:_textView drawAfterGlyphRun:run forLine:line withOrigin:origins[i] inContext:ctx];
            }
            
            CFDictionaryRef attributes = CTRunGetAttributes(run);
            id <EGOTextAttachmentCell> attachmentCell = [(__bridge id)attributes objectForKey:EGOTextAttachmentAttributeName];
            if (attachmentCell && [attachmentCell respondsToSelector: @selector(attachmentSize)] && [attachmentCell respondsToSelector: @selector(attachmentDrawInRect:)]) {
                CGPoint position;
                CTRunGetPositions(run, CFRangeMake(0, 1), &position);
                
                CGSize size = [attachmentCell attachmentSize];
                CGRect theRect = { { origins[i].x + position.x, origins[i].y + position.y }, size };
                
                UIGraphicsPushContext(UIGraphicsGetCurrentContext());
                [attachmentCell attachmentDrawInRect: theRect];
                UIGraphicsPopContext();
            }
            UIColor *spellCheckingColor = [(__bridge id)attributes objectForKey:EGOTextSpellCheckingColor];
            if (spellCheckingColor) {
                [self drawMispelledGlyphRun:run forLine:line withOrigin:origins[i] inContext:ctx color:spellCheckingColor];
            }
        }
	}
    free(origins);
	CGContextRestoreGState(ctx);
    
    [[UIColor colorWithRed:0.8f green:0.8f blue:0.8f alpha:1.0f] setFill];
    [self drawBoundingRangeAsSelection:_textView.linkRange cornerRadius:2.0f];
    [[EGOTextView selectionColor] setFill];
    [self drawBoundingRangeAsSelection:_textView.selectedRange cornerRadius:0.0f];
    [[EGOTextView spellingSelectionColor] setFill];
    [self drawBoundingRangeAsSelection:_textView.correctionRange cornerRadius:2.0f];
}

- (void)drawMispelledGlyphRun:(CTRunRef)glyphRun forLine:(CTLineRef)line withOrigin:(CGPoint)origin inContext:(CGContextRef)context color:(UIColor *)strokeColor {
    CGRect runBounds = CGRectZero;
    CGFloat ascent = 0.0f;
    CGFloat descent = 0.0f;
    
    CGContextSaveGState(context);
    
    runBounds = CTRunGetImageBounds(glyphRun, context, CFRangeMake(0, 0));
    
    runBounds.size.width = CTRunGetTypographicBounds(glyphRun, CFRangeMake(0, 0), &ascent, &descent, NULL);
    CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
    runBounds.size.height = ascent + descent;
    
    CGFloat xOffset = CTLineGetOffsetForStringIndex(line, CTRunGetStringRange(glyphRun).location, NULL);
    runBounds.origin.x = origin.x + xOffset;
    runBounds.origin.y = origin.y - descent/2;
    
    CGMutablePathRef path = CGPathCreateMutable();
    CGPathMoveToPoint(path, NULL, runBounds.origin.x, runBounds.origin.y);
    CGPathAddLineToPoint(path, NULL, runBounds.origin.x + runBounds.size.width, runBounds.origin.y);
    
    CGContextSetShouldAntialias(context, YES);
    
    CGFloat dotRadius = 2.0f;
    CGFloat dashes[] = {0, dotRadius*2};
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineWidth(context, dotRadius);
    CGContextSetLineDash(context, 0.0f, dashes, 2);
	
    CGContextSetStrokeColorWithColor(context, strokeColor.CGColor);
    CGContextAddPath(context, path);
    CGContextStrokePath(context);
    CGPathRelease(path);
    
    CGContextRestoreGState(context);
}

#pragma mark - Layout

- (NSInteger)closestWhiteSpaceIndexToPoint:(CGPoint)point fromView:(UIView *)sourceView {
    point = [self convertPoint:point fromView:sourceView];
	point.y = self.frame.size.height - point.y;
	
    NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    NSInteger count = [lines count];
    CGPoint *origins = (CGPoint *)malloc(count * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, count), origins);
    NSString *text = [[_textView attributedText] string];
    
    __block NSRange returnRange = NSMakeRange(text.length, 0);
    
    for (int i = 0; i < lines.count; i++) {
        if (point.y > origins[i].y) {
            CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:i];
            CFRange cfRange = CTLineGetStringRange(line);
            NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length);
            CGPoint convertedPoint = CGPointMake(point.x - origins[i].x, point.y - origins[i].y);
            CFIndex cfIndex = CTLineGetStringIndexForPosition(line, convertedPoint);
            NSInteger theIndex = (cfIndex == kCFNotFound ? NSNotFound : cfIndex);
			
            if(range.location == NSNotFound) {
                break;
			}
            
            if (theIndex >= text.length) {
                returnRange = NSMakeRange(text.length, 0);
                break;
            }
            
            if (range.length <= 1) {
                returnRange = NSMakeRange(range.location, 0);
                break;
            }
            
            if (theIndex == range.location) {
                returnRange = NSMakeRange(range.location, 0);
                break;
            }
			
            if (theIndex >= (range.location+range.length)) {
                if (range.length > 1 && [text characterAtIndex:(range.location+range.length)-1] == '\n') {
                    returnRange = NSMakeRange(theIndex - 1, 0);
                    break;
                } else {
                    returnRange = NSMakeRange(range.location+range.length, 0);
                    break;
                }
            }
            
            [text enumerateSubstringsInRange:range
                                     options:NSStringEnumerationByWords|NSStringEnumerationSubstringNotRequired
                                  usingBlock:^(NSString *subString, NSRange subStringRange, NSRange enclosingRange, BOOL *stop) {
                                      if (NSLocationInRange(theIndex, enclosingRange)) {
                                          if (theIndex > (enclosingRange.location+(enclosingRange.length/2))) {
                                              returnRange = NSMakeRange(subStringRange.location+subStringRange.length, 0);
                                          } else {
                                              returnRange = NSMakeRange(subStringRange.location, 0);
                                          }
                                          *stop = YES;
                                      }
                                  }];
            break;
            
        }
    }
    
    free(origins);
    return returnRange.location;
}

- (NSInteger)closestIndexToPoint:(CGPoint)point fromView:(UIView *)sourceView {
    point = [self convertPoint:point fromView:sourceView];
	point.y = self.frame.size.height - point.y;
	
    NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    NSInteger count = [lines count];
    CGPoint *origins = (CGPoint *)malloc(count * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, count), origins);
    CFIndex index = kCFNotFound;
    
    for (int i = 0; i < lines.count; i++) {
        if (point.y > origins[i].y) {
            CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:i];
            CGPoint convertedPoint = CGPointMake(point.x - origins[i].x, point.y - origins[i].y);
            index = CTLineGetStringIndexForPosition(line, convertedPoint);
			CFRange lineRange = CTLineGetStringRange(line);
			if (index != kCFNotFound && index == lineRange.location + lineRange.length) {
				index = index - 1;
			}
            break;
        }
    }
    
    if (index == kCFNotFound) {
        index = [[_textView attributedText] length];
    }
    
    free(origins);
    return index;
}

- (NSRange)characterRangeAtPoint:(CGPoint)point {
	point.y = self.frame.size.height - point.y;
	
	__block NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    CGPoint *origins = (CGPoint *)malloc([lines count] * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, [lines count]), origins);
    __block NSRange returnRange = NSMakeRange(NSNotFound, 0);
	
    for (int i = 0; i < lines.count; i++) {
        if (point.y > origins[i].y) {
            __block CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:i];
            CGPoint convertedPoint = CGPointMake(point.x - origins[i].x, point.y - origins[i].y);
            NSInteger index = CTLineGetStringIndexForPosition(line, convertedPoint);
            CFRange cfRange = CTLineGetStringRange(line);
            NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length);
            NSString *text = [[_textView attributedText] string];
            [text enumerateSubstringsInRange:range
                                     options:NSStringEnumerationByWords|NSStringEnumerationSubstringNotRequired
                                  usingBlock:^(NSString *subString, NSRange subStringRange, NSRange enclosingRange, BOOL *stop){
                                      if (NSLocationInRange(index, subStringRange)) {
                                          returnRange = subStringRange;
                                          *stop = YES;
                                      } else if (NSLocationInRange(index, enclosingRange)) {
                                          returnRange = enclosingRange;
                                          *stop = YES;
                                      }
                                  }];
            break;
        }
    }
	
    free(origins);
    return returnRange;
}

- (NSRange)characterRangeAtIndex:(NSInteger)inIndex {
    __block NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    NSInteger count = [lines count];
    __block NSRange returnRange = NSMakeRange(NSNotFound, 0);
    
    for (int i = 0; i < count; i++) {
        __block CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:i];
        CFRange cfRange = CTLineGetStringRange(line);
        NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length == kCFNotFound ? 0 : cfRange.length);
        
        if (inIndex >= range.location && inIndex <= range.location+range.length && range.length > 1) {
            returnRange = range;
            NSString *text = [[_textView attributedText] string];
            [text enumerateSubstringsInRange:range
                                     options:NSStringEnumerationByWords|NSStringEnumerationSubstringNotRequired
                                  usingBlock:^(NSString *subString, NSRange subStringRange, NSRange enclosingRange, BOOL *stop) {
                                      if (NSLocationInRange(inIndex, subStringRange)) {
                                          returnRange = subStringRange;
                                          *stop = YES;
                                      } else if (NSLocationInRange(inIndex, enclosingRange)) {
                                          returnRange = enclosingRange;
                                          *stop = YES;
                                      }
                                  }];
			break;
        }
    }
    return returnRange;
}

- (CGRect)caretRectForIndex:(NSInteger)inIndex {
    CGFloat caretWidth = 3.0f;
    
    NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    NSAttributedString *attributedString = [_textView attributedText];
    
    // no text / first index
    if (attributedString.length == 0 || inIndex == 0) {
        CGPoint origin = CGPointMake(CGRectGetMinX(self.bounds), CGRectGetMaxY(self.bounds) - _textView.font.leading);
        return CGRectMake(origin.x, self.frame.size.height - origin.y - (_textView.font.ascender + fabs(_textView.font.descender)), caretWidth, _textView.font.ascender + fabs(_textView.font.descender));
    }
	
    // last index is newline
    if (inIndex == attributedString.length && [attributedString.string characterAtIndex:(inIndex - 1)] == '\n' ) {
        CTLineRef line = (__bridge CTLineRef)[lines lastObject];
        CFRange range = CTLineGetStringRange(line);
        CGFloat xPos = CTLineGetOffsetForStringIndex(line, range.location, NULL);
        CGFloat ascent, descent;
        CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
		
        CGPoint origin;
        CGPoint *origins = (CGPoint *)malloc(1 * sizeof(CGPoint));
        CTFrameGetLineOrigins(_frame, CFRangeMake([lines count]-1, 0), origins);
        origin = origins[0];
        free(origins);
        
        origin.y -= _textView.font.leading;
		CGRect returnRect = CGRectMake(origin.x + xPos, floorf(origin.y + ascent), caretWidth, ceilf(descent + ascent));
		returnRect.origin.y = self.frame.size.height - returnRect.origin.y;
        return returnRect;
    }
	
    inIndex = MAX(inIndex, 0);
    inIndex = MIN(attributedString.string.length, inIndex);
	
    NSInteger count = [lines count];
    CGPoint *origins = (CGPoint *)malloc(count * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, count), origins);
    CGRect returnRect = CGRectZero;
	
    for (int i = 0; i < count; i++) {
		
        CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:i];
        CFRange cfRange = CTLineGetStringRange(line);
        NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length);
		
        if (inIndex >= range.location && inIndex <= range.location+range.length) {
			
            CGFloat ascent, descent, xPos;
            xPos = CTLineGetOffsetForStringIndex((__bridge CTLineRef)[lines objectAtIndex:i], inIndex, NULL);
            CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
            CGPoint origin = origins[i];
			
            if (_textView.selectedRange.length > 0 && inIndex != _textView.selectedRange.location && range.length == 1) {
                
                xPos = self.bounds.size.width - caretWidth; // selection of entire line
                
            } else if ([attributedString.string characterAtIndex:inIndex-1] == '\n' && range.length == 1) {
				
                xPos = 0.0f; // empty line
				
            }
            
            returnRect = CGRectMake(origin.x + xPos - caretWidth/2, floorf(origin.y + ascent), caretWidth, ceilf(descent + ascent));
			returnRect.origin.y = self.frame.size.height - returnRect.origin.y;
        }
        
    }
    
    free(origins);
    return returnRect;
}

- (CGRect)firstRectForNSRange:(NSRange)range {
    NSInteger theIndex = range.location;
	
    NSArray *lines = (__bridge NSArray *) CTFrameGetLines(_frame);
    NSInteger count = [lines count];
    CGPoint *origins = (CGPoint *)malloc(count * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, count), origins);
    CGRect returnRect = CGRectNull;
    
    for (int i = 0; i < count; i++) {
        
        CTLineRef line = (__bridge CTLineRef) [lines objectAtIndex:i];
        CFRange lineRange = CTLineGetStringRange(line);
        NSInteger localIndex = theIndex - lineRange.location;
		
        if (localIndex >= 0 && localIndex < lineRange.length) {
            
            NSInteger finalIndex = MIN(lineRange.location + lineRange.length, range.location + range.length);
            CGFloat xStart = CTLineGetOffsetForStringIndex(line, theIndex, NULL);
            CGFloat xEnd = CTLineGetOffsetForStringIndex(line, finalIndex, NULL);
            CGPoint origin = origins[i];
            CGFloat ascent, descent;
            CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
            
            returnRect = CGRectMake(origin.x + xStart, self.frame.size.height - origin.y - ascent, xEnd - xStart, ascent + descent);
			
            break;
        }
    }
	
    free(origins);
    return CGRectIntegral(returnRect);
}

- (NSInteger *)positionFromPosition:(NSInteger)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset {
    switch (direction) {
        case UITextLayoutDirectionRight:
            return position + offset;
            break;
        case UITextLayoutDirectionLeft:
            return position - offset;
            break;
        case UITextLayoutDirectionUp: {
            // Iterate through lines to find the one which contains the position given
            CFArrayRef lines = CTFrameGetLines(_frame);
            for (NSInteger i = 0; i < CFArrayGetCount(lines); i++) {
                CTLineRef line = CFArrayGetValueAtIndex(lines, i);
                CFRange lineRange = CTLineGetStringRange(line);
                if (lineRange.location <= position && position <= (lineRange.location + lineRange.length)) {
                    // Current line was found : calculate the new position
                    if (line && (i - offset) >= 0) {
                        CGFloat xOffsetToPosition = CTLineGetOffsetForStringIndex(line, position, NULL);
                        return CTLineGetStringIndexForPosition(CFArrayGetValueAtIndex(lines, i - offset),
                                                               CGPointMake(xOffsetToPosition, 0.0f));
                    } else {
                        return 0;
                    }
                    break;
                }
            }
        } break;
        case UITextLayoutDirectionDown: {
            // Iterate through lines to find the one which contains the position given
            CFArrayRef lines = CTFrameGetLines(_frame);
            for (NSUInteger i = 0; i < CFArrayGetCount(lines); i++) {
                CTLineRef line = CFArrayGetValueAtIndex(lines, i);
                CFRange lineRange = CTLineGetStringRange(line);
                if (lineRange.location <= position && position <= (lineRange.location + lineRange.length)) {
                    // Current line was found : calculate the new position
                    if (line && (i + offset) < CFArrayGetCount(lines)) {
                        CGFloat xOffsetToPosition = CTLineGetOffsetForStringIndex(line, position, NULL);
                        return CTLineGetStringIndexForPosition(CFArrayGetValueAtIndex(lines, i + offset),
                                                               CGPointMake(xOffsetToPosition, 0.0f));
                    }
                    break;
                }
            }
        } break;
    }
    
    return NSNotFound;
}

#pragma mark - Dealloc

- (void)clearPreviousLayoutInformation {
    if (_framesetter != NULL) {
        CFRelease(_framesetter);
        _framesetter = NULL;
    }
    
    if (_frame != NULL) {
        CFRelease(_frame);
        _frame = NULL;
    }
}

- (void)dealloc {
    [self clearPreviousLayoutInformation];
}

@end
