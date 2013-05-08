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
#import "EGOTextLine.h"

@interface EGOContentView() {
    CTFrameRef _ctFrame;
    CTFramesetterRef _ctFramesetter;
}

@property (nonatomic, strong) NSMutableArray *lines;
@property (nonatomic, assign) dispatch_queue_t drawQueue;

@end

@implementation EGOContentView

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
    if (self) {
        _ctFrame = NULL;
        _ctFramesetter = NULL;
        _lines = [[NSMutableArray alloc] init];
        
        [self setUserInteractionEnabled:NO];
        [self setBackgroundColor:[UIColor whiteColor]];
        [[self layer] setGeometryFlipped:NO];
        [[self layer] setDelegate:self];
    }
	
    return self;
}

- (dispatch_queue_t)drawQueue {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _drawQueue = dispatch_queue_create("com.enormego.EGOContentViewDrawQueue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_queue_set_specific(_drawQueue, self.drawQueueSpecific, (__bridge void *)self, NULL);
    });
    
    return _drawQueue;
}

- (const char *)drawQueueSpecific {
    static const char *kEGODrawQueueSpecific = "EGODrawQueueSpecific";
    return kEGODrawQueueSpecific;
}


+ (Class)layerClass {
    return [CATiledLayer class];
}

- (void)setTextView:(EGOTextView *)textView {
    if (_textView) {
        [_textView removeObserver:self forKeyPath:@"frame"];
    }
    
    if (textView) {
        _textView = textView;
        [_textView addObserver:self forKeyPath:@"frame" options:(NSKeyValueObservingOptionNew | NSKeyValueObservingOptionOld) context:NULL];
    }
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"frame"]) {
        CGRect oldFrame = CGRectNull;
        CGRect newFrame = CGRectNull;
        if([change objectForKey:@"old"] != [NSNull null]) {
            oldFrame = [[change objectForKey:@"old"] CGRectValue];
        }
        if([object valueForKeyPath:keyPath] != [NSNull null]) {
            newFrame = [[object valueForKeyPath:keyPath] CGRectValue];
        }
        if (!CGRectIsNull(oldFrame) && !CGRectIsNull(newFrame) && (fabs(oldFrame.size.width - newFrame.size.width) < 0.001 || fabs(oldFrame.size.height - newFrame.size.height) < 0.001)) {
            NSAttributedString *attributedString = [_textView attributedString];
            dispatch_block_t block = ^{
                [(CATiledLayer *)[self layer] setTileSize:CGSizeMake(newFrame.size.width, _textView.font.lineHeight*8)];
                [self updateFrame];
                [self layoutAttchmentsViews:attributedString];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self setNeedsDisplay];
                });
            };
            if (dispatch_get_specific(self.drawQueueSpecific)) {
                block();
            } else {
                dispatch_barrier_async(self.drawQueue, block);
            }
        }
    }
}

- (void)drawText {
    NSAttributedString *attributedString = [_textView attributedString];
    if (!attributedString) {
        return;
    }
    dispatch_block_t block = ^{
        [self clearPreviousLayoutInformation];
        
        _ctFramesetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)attributedString);
        
        [self updateFrame];
        [self layoutAttchmentsViews:attributedString];
    };
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.drawQueue, block);
    }
}

- (void)updateFrame {
    dispatch_block_t block = ^ {
        if (!_ctFramesetter) {
            return;
        }
        
        if (_ctFrame) {
            CFRelease(_ctFrame);
        }
        
        CGRect theRect = CGRectInset(CGRectMake(0.0f, 0.0f, _textView.frame.size.width, _textView.frame.size.height),
                                     6.0f, 15.0f);
        theRect.size.height = [self boundingHeightForWidth:theRect.size.width] + _textView.font.lineHeight;
        [self setFrame:theRect];
        [_textView setContentSize:CGSizeMake(self.frame.size.width, self.frame.size.height+_textView.font.lineHeight*1)];
                
        CGPathRef path = CGPathCreateWithRect(CGRectMake(0.0f, 0.0f, self.frame.size.width, self.frame.size.height), &CGAffineTransformIdentity);
        _ctFrame = CTFramesetterCreateFrame(_ctFramesetter, CFRangeMake(0, 0), path, NULL);
        CFRelease(path);
        
        CFArrayRef lines = CTFrameGetLines(_ctFrame);
        CFIndex count = CFArrayGetCount(lines);
        
        CGPoint *origins = (CGPoint *)malloc(count * sizeof(CGPoint));
        CTFrameGetLineOrigins(_ctFrame, CFRangeMake(0, count), origins);
        
        [_lines removeAllObjects];
        
        for (int i = 0; i < count; i++) {            
            CTLineRef rawLine = (CTLineRef)CFArrayGetValueAtIndex(lines, i);
            
            EGOTextLine *line = [[EGOTextLine alloc] initWithCTLine:rawLine];
            [line setOrigin:origins[i]];
            [line setIndex:i];
            
            [_lines addObject:line];
        }
        
        free(origins);
    };
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.drawQueue, block);
    }
}

- (void)layoutAttchmentsViews:(NSAttributedString *)attributedString {
    if (!_ctFramesetter) {
        return;
    }
    
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
}

- (NSArray *)linesInRect:(CGRect)rect {
    return [_lines filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
        EGOTextLine *line = (EGOTextLine *)evaluatedObject;
        CGRect lineRect = CGRectMake(line.origin.x, self.frame.size.height-(line.origin.y+line.ascent),
                                     self.frame.size.width, line.ascent+line.descent+line.leading+1);

        return CGRectIntersectsRect(rect, lineRect);
    }]];
}

#pragma mark - Drawing

- (void)drawPathFromRects:(NSArray *)array cornerRadius:(CGFloat)cornerRadius inContext:(CGContextRef)ctx {
    if (!array || [array count] == 0) return;
    
    CGMutablePathRef path = CGPathCreateMutable();
    
    CGRect firstRect = CGRectFromString([array objectAtIndex:0]);
    CGRect lastRect = CGRectFromString([array lastObject]);
    if ([array count] > 1) {
        firstRect.size.width = self.bounds.size.width-firstRect.origin.x;
    }
    
    if (cornerRadius > 0) {
        CGPathAddPath(path, NULL, [UIBezierPath bezierPathWithRoundedRect:firstRect cornerRadius:cornerRadius].CGPath);
        CGPathAddPath(path, NULL, [UIBezierPath bezierPathWithRoundedRect:lastRect cornerRadius:cornerRadius].CGPath);
    } else {
        CGPathAddRect(path, NULL, firstRect);
        CGPathAddRect(path, NULL, lastRect);
    }
    
    if ([array count] > 1) {
		
        CGRect fillRect = CGRectZero;
        
        CGFloat originX = ([array count] == 2) ? MIN(CGRectGetMinX(firstRect), CGRectGetMinX(lastRect)) : 0.0f;
        CGFloat originY = firstRect.origin.y + firstRect.size.height;
        CGFloat width = ([array count] == 2) ? originX + MIN(CGRectGetMaxX(firstRect), CGRectGetMaxX(lastRect)) : self.bounds.size.width;
        CGFloat height =  MAX(0.0f, lastRect.origin.y - originY);
        
        fillRect = CGRectMake(originX, originY, width, height);
        
        if (cornerRadius > 0) {
            CGPathAddPath(path, NULL, [UIBezierPath bezierPathWithRoundedRect:fillRect cornerRadius:cornerRadius].CGPath);
        } else {
            CGPathAddRect(path, NULL, fillRect);
        }
    }
    
    CGContextAddPath(ctx, path);
    CGContextFillPath(ctx);
    CGPathRelease(path);
}

- (void)drawBoundingRangeAsSelection:(NSRange)selectionRange cornerRadius:(CGFloat)cornerRadius inContext:(CGContextRef)ctx {
    [self drawBoundingRangeAsSelection:selectionRange cornerRadius:cornerRadius inContext:ctx lines:_lines];
}

- (void)drawBoundingRangeAsSelection:(NSRange)selectionRange cornerRadius:(CGFloat)cornerRadius inContext:(CGContextRef)ctx lines:(NSArray *)lines {
    if (selectionRange.length == 0 || selectionRange.location == NSNotFound) {
        return;
    }
    
    NSMutableArray *pathRects = [[NSMutableArray alloc] init];
    
    for (EGOTextLine *line in lines) {
        CFRange lineRange = CTLineGetStringRange(line.rawLine);
        NSRange range = NSMakeRange(lineRange.location==kCFNotFound ? NSNotFound : lineRange.location, lineRange.length);
        NSRange intersection = NSIntersectionRange(range, selectionRange);
        
        if (intersection.location != NSNotFound && intersection.length > 0) {
            CGFloat xStart = CTLineGetOffsetForStringIndex(line.rawLine, intersection.location, NULL);
            CGFloat xEnd = CTLineGetOffsetForStringIndex(line.rawLine, intersection.location + intersection.length, NULL);
            
            CGRect selectionRect = CGRectMake(line.origin.x + xStart, line.origin.y + line.ascent, xEnd - xStart, line.ascent + line.descent);
			selectionRect.origin.y = self.frame.size.height - selectionRect.origin.y;
            
            if (range.length == 1) {
                selectionRect.size.width = self.bounds.size.width;
            }
            
            [pathRects addObject:NSStringFromCGRect(selectionRect)];
        }
    }
    
    [self drawPathFromRects:pathRects cornerRadius:cornerRadius inContext:ctx];
}

- (void)drawLayer:(CALayer *)layer inContext:(CGContextRef)ctx {
    dispatch_sync(self.drawQueue, ^{
        // Clear background
        CGRect rect = CGContextGetClipBoundingBox(ctx);
        CGContextSetFillColorWithColor(ctx, [self.backgroundColor CGColor]);
        CGContextFillRect(ctx, rect);
        
        if (!_ctFrame) {
            return;
        }
        
        NSArray *lines = [self linesInRect:rect];
        
        if (_textView.searchRanges && [_textView.searchRanges count] > 0) {
            CGContextSetFillColorWithColor(ctx, [[UIColor colorWithRed:1.0f green:1.0f blue:0.0f alpha:1.0f] CGColor]);
            for (EGOIndexedRange *searchRange in _textView.searchRanges) {
                [self drawBoundingRangeAsSelection:searchRange.range cornerRadius:2.0f inContext:ctx lines:lines];
            }
        }
        
        CGContextSaveGState(ctx);
        CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
        CGContextTranslateCTM(ctx, 0, self.frame.size.height);
        CGContextScaleCTM(ctx, 1.0, -1.0);
        CGMutablePathRef path = NULL;
        for (EGOTextLine *line in lines) {
            CGContextSetTextPosition(ctx, line.origin.x, line.origin.y);
            //CTLineDraw(line.rawLine, ctx);
            
            for (CFIndex runsIndex = 0; runsIndex < [line.runsArray count]; runsIndex++) {
                CTRunRef run = (__bridge CTRunRef)[line.runsArray objectAtIndex:runsIndex];
                
                if (_textView.drawDelegate) {
                    [_textView.drawDelegate egoTextView:_textView drawBeforeGlyphRun:run forLine:line.rawLine withOrigin:line.origin inContext:ctx];
                }
                
                CGAffineTransform textMatrix = CTRunGetTextMatrix(run);
                textMatrix.tx = line.origin.x;
                textMatrix.ty = line.origin.y;
                
                CGContextSetTextMatrix(ctx, textMatrix);
                                
                CTRunDraw(run, ctx, CFRangeMake(0, 0));
                
                CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
                
                
                if (_textView.drawDelegate) {
                    [_textView.drawDelegate egoTextView:_textView drawAfterGlyphRun:run forLine:line.rawLine withOrigin:line.origin inContext:ctx];
                }
                
                CFDictionaryRef attributes = CTRunGetAttributes(run);
                id <EGOTextAttachmentCell> attachmentCell = [(__bridge id)attributes objectForKey:EGOTextAttachmentAttributeName];
                if (attachmentCell && [attachmentCell respondsToSelector: @selector(attachmentSize)] && [attachmentCell respondsToSelector: @selector(attachmentDrawInRect:)]) {
                    CGPoint position;
                    CTRunGetPositions(run, CFRangeMake(0, 1), &position);
                    
                    CGSize size = [attachmentCell attachmentSize];
                    CGRect theRect = { { line.origin.x + position.x, line.origin.y + position.y }, size };
                    
                    UIGraphicsPushContext(ctx);
                    [attachmentCell attachmentDrawInRect:theRect];
                    UIGraphicsPopContext();
                }
            }
            
            CFRange lineRange = CTLineGetStringRange(line.rawLine);
            NSPredicate *rangeInLine = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
                return NSIntersectionRange(NSMakeRange(lineRange.location == kCFNotFound ? NSNotFound : lineRange.location, lineRange.length), ((EGOIndexedRange *)evaluatedObject).range).length != 0;
            }];
            
            for (EGOIndexedRange *r in [[_textView correctionRanges] filteredSetUsingPredicate:rangeInLine]) {
                if (!path) {
                    path = CGPathCreateMutable();
                }
                                
                CGFloat xStart = CTLineGetOffsetForStringIndex(line.rawLine, MAX(lineRange.location, r.range.location), NULL);
                CGFloat xEnd = CTLineGetOffsetForStringIndex(line.rawLine, MIN(lineRange.location+lineRange.length, r.range.location+r.range.length), NULL);
                
                CGRect cRect = CGRectZero;
                
                cRect.origin.x = line.origin.x + xStart;
                cRect.origin.y = line.origin.y - line.descent/2;
                
                cRect.size.width = xEnd - xStart;
                cRect.size.height = line.ascent + line.descent;
                
                CGPathMoveToPoint(path, &CGAffineTransformIdentity, cRect.origin.x, cRect.origin.y);
                CGPathAddLineToPoint(path, &CGAffineTransformIdentity, cRect.origin.x + cRect.size.width, cRect.origin.y);
            }
        }
        
        if (path) {
            CGContextSaveGState(ctx);
            
            CGContextSetShouldAntialias(ctx, YES);
            
            CGFloat dotRadius = 2.0f;
            CGFloat dashes[] = {0, dotRadius*2};
            CGContextSetLineCap(ctx, kCGLineCapRound);
            CGContextSetLineWidth(ctx, dotRadius);
            CGContextSetLineDash(ctx, 0.0f, dashes, 2);
            
            UIColor *correctionColor = [_textView.correctionAttributes objectForKey:EGOTextSpellCheckingColor];
            
            CGContextSetStrokeColorWithColor(ctx, [(correctionColor ? correctionColor : [UIColor redColor]) CGColor]);
            CGContextAddPath(ctx, path);
            CGContextStrokePath(ctx);
            CGPathRelease(path);
            
            CGContextRestoreGState(ctx);
        }
        
        CGContextRestoreGState(ctx);
        
        CGContextSetFillColorWithColor(ctx, [[UIColor colorWithRed:0.8f green:0.8f blue:0.8f alpha:1.0f] CGColor]);
        [self drawBoundingRangeAsSelection:_textView.linkRange cornerRadius:2.0f inContext:ctx lines:lines];
        CGContextSetFillColorWithColor(ctx, [[EGOTextView spellingSelectionColor] CGColor]);
        [self drawBoundingRangeAsSelection:_textView.correctionRange cornerRadius:2.0f inContext:ctx lines:lines];
    });
}

#pragma mark - Layout

- (CGFloat)boundingWidthForHeight:(CGFloat)height {
    __block CGSize suggestedSize;
    dispatch_block_t block = ^{
        suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(_ctFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, height), NULL);
    };
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }

    return suggestedSize.width;
}

- (CGFloat)boundingHeightForWidth:(CGFloat)width {
    __block CGSize suggestedSize;
    dispatch_block_t block = ^{
        suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(_ctFramesetter, CFRangeMake(0, 0), NULL, CGSizeMake(width, CGFLOAT_MAX), NULL);
    };
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }
    
    return suggestedSize.height;
}

- (NSInteger)closestWhiteSpaceIndexToPoint:(CGPoint)point fromView:(UIView *)sourceView {
    point = [self convertPoint:point fromView:sourceView];
	point.y = self.frame.size.height - point.y;
	
    NSString *text = [_textView text];
    
    __block NSRange returnRange = NSMakeRange(text.length, 0);
    
    dispatch_block_t block = ^{
        for (EGOTextLine *line in _lines) {
            if (point.y > line.origin.y) {
                CFRange cfRange = CTLineGetStringRange(line.rawLine);
                NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length);
                CGPoint convertedPoint = CGPointMake(point.x - line.origin.x, point.y - line.origin.y);
                CFIndex cfIndex = CTLineGetStringIndexForPosition(line.rawLine, convertedPoint);
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
                    if (range.length > 1 && [[NSCharacterSet newlineCharacterSet] characterIsMember:[text characterAtIndex:(range.location+range.length)-1]]) {
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
    };
    
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }
    
    return returnRange.location;
}

- (NSInteger)closestIndexToPoint:(CGPoint)point fromView:(UIView *)sourceView {
    point = [self convertPoint:point fromView:sourceView];
	point.y = self.frame.size.height - point.y;
    
    NSUInteger length = [_textView textLength];
    if (length == 0) {
        return 0;
    }
    BOOL newlineTerminatedText = [[NSCharacterSet newlineCharacterSet] characterIsMember:[[_textView text] characterAtIndex:length-1]];
    __block CFIndex index = kCFNotFound;

    dispatch_block_t block = ^{
        for (EGOTextLine *line in _lines) {
            if (point.y > line.origin.y) {
                CGPoint convertedPoint = CGPointMake(point.x - line.origin.x, point.y - line.origin.y);
                index = CTLineGetStringIndexForPosition(line.rawLine, convertedPoint);
                CFRange lineRange = CTLineGetStringRange(line.rawLine);
                if (index == kCFNotFound) {
                    index = length;
                } else if ((index == length && newlineTerminatedText) || index == lineRange.location + lineRange.length) {
                    index = index - 1;
                }
                break;
            }
        }
    };
    
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }
    
    return index;
}

- (NSRange)characterRangeAtPoint:(CGPoint)point fromView:(UIView *)sourceView {
    point = [self convertPoint:point fromView:sourceView];
	point.y = self.frame.size.height - point.y;

    __block NSRange returnRange = NSMakeRange(NSNotFound, 0);
    NSString *text = [_textView text];

    dispatch_block_t block = ^{
        for (EGOTextLine *line in _lines) {
            if (point.y > line.origin.y) {
                CGPoint convertedPoint = CGPointMake(point.x - line.origin.x, point.y - line.origin.y);
                NSInteger index = CTLineGetStringIndexForPosition(line.rawLine, convertedPoint);
                CFRange cfRange = CTLineGetStringRange(line.rawLine);
                NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length);
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
    };
    
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }
    
    return returnRange;
}

- (NSRange)characterRangeAtIndex:(NSInteger)inIndex {
    __block NSRange returnRange = NSMakeRange(NSNotFound, 0);
    NSString *text = [_textView text];
    inIndex = MAX(0, MIN(inIndex, [text length] - 1));
    
    if (inIndex == [text length] || [[NSCharacterSet newlineCharacterSet] characterIsMember:[text characterAtIndex:inIndex]]) {
        return NSMakeRange(inIndex, 0);
    }
    
    dispatch_block_t block = ^{
        for (EGOTextLine *line in _lines) {
            CFRange cfRange = CTLineGetStringRange(line.rawLine);
            NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length == kCFNotFound ? 0 : cfRange.length);
            
            if (inIndex >= range.location && inIndex <= range.location+range.length && range.length > 1) {
                returnRange = range;
                @try {
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
                }
                @catch (NSException *exception) {
                    //NSLog(@"%@ %@", [exception description], NSStringFromRange(range));
                }
                break;
            }
        }
    };
    
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }
    
    return returnRange;
}

- (CGRect)caretRectForIndex:(NSInteger)inIndex {
    NSString *text = [_textView text];
    __block CGRect returnRect = CGRectZero;
    
    dispatch_block_t block = ^{
        CGFloat caretWidth = 3.0f;
        NSInteger index = inIndex;
        
        // no text
        if ([text length] == 0) {
            CGPoint origin = CGPointMake(CGRectGetMinX(self.bounds), CGRectGetMaxY(self.bounds));
            if (_ctFrame) {
                origin.y = CGPathGetPathBoundingBox(CTFrameGetPath(_ctFrame)).origin.y;
            }
            returnRect = CGRectMake(origin.x - caretWidth/2, origin.y, caretWidth, ceilf(_textView.font.ascender + fabs(_textView.font.descender)));
        }
        
        // last index is newline
        else if (index == [text length] && [[NSCharacterSet newlineCharacterSet] characterIsMember:[text characterAtIndex:(index - 1)]]) {
            EGOTextLine *line = [_lines lastObject];
            CFRange range = CTLineGetStringRange(line.rawLine);
            CGFloat xPos = CTLineGetOffsetForStringIndex(line.rawLine, range.location, NULL);
            CGPoint origin = line.origin;
            origin.y -= _textView.font.lineHeight;
            returnRect = CGRectMake(origin.x + xPos, floorf(origin.y + line.ascent), caretWidth, ceilf(line.descent + line.ascent));
            returnRect.origin.y = self.frame.size.height - returnRect.origin.y;
        }
        
        // middle of text
        else {
            index = MIN([text length], MAX(index, 0));
            
            for (EGOTextLine *line in _lines) {
                CFRange cfRange = CTLineGetStringRange(line.rawLine);
                NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length);
                
                if (index >= range.location && index <= range.location+range.length) {
                    CGFloat xPos = CTLineGetOffsetForStringIndex(line.rawLine, index, NULL);
                    CGPoint origin = line.origin;
                    
                    if (_textView.selectedRange.length > 0 && index != _textView.selectedRange.location && range.length == 1) {
                        xPos = self.bounds.size.width - caretWidth; // selection of entire line
                    } else if ([[NSCharacterSet newlineCharacterSet] characterIsMember:[text characterAtIndex:index-1]] && range.length == 1) {
                        xPos = 0.0f; // empty line
                    }
                    
                    returnRect = CGRectMake(origin.x + xPos - caretWidth/2, floorf(origin.y + line.ascent), caretWidth, ceilf(line.descent + line.ascent));
                    returnRect.origin.y = self.frame.size.height - returnRect.origin.y;
                }
            }
        }
    };
    
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }
    
    return returnRect;
}

- (CGRect)firstRectForNSRange:(NSRange)range {
    __block CGRect returnRect = CGRectNull;
    
    dispatch_block_t block = ^{
        NSInteger rangeLocation = MAX(0, range.location);
                
        for (EGOTextLine *line in _lines) {
            CFRange lineRange = CTLineGetStringRange(line.rawLine);
            
            if (rangeLocation < lineRange.location + lineRange.length) {
                NSInteger rangeEnd = MIN(lineRange.location + lineRange.length, range.location + range.length);
                CGFloat xStart = CTLineGetOffsetForStringIndex(line.rawLine, rangeLocation, NULL);
                CGFloat xEnd = CTLineGetOffsetForStringIndex(line.rawLine, rangeEnd, NULL);
                
                returnRect = CGRectMake(line.origin.x + xStart, self.frame.size.height - line.origin.y - line.ascent, xEnd - xStart, line.ascent + line.descent);
                
                break;
            }
        }
    };
    
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }
	
    return CGRectIntegral(returnRect);
}

- (CGRect)lastRectForNSRange:(NSRange)range {	
    __block CGRect returnRect = CGRectNull;
    
    dispatch_block_t block = ^{
        NSInteger rangeLocation = MAX(0, range.location + range.length);
                
        for (EGOTextLine *line in _lines) {
            CFRange lineRange = CTLineGetStringRange(line.rawLine);
            
            if (rangeLocation < lineRange.location + lineRange.length) {
                NSInteger rangeStart = MAX(lineRange.location, range.location);
                CGFloat xStart = CTLineGetOffsetForStringIndex(line.rawLine, rangeStart, NULL);
                CGFloat xEnd = CTLineGetOffsetForStringIndex(line.rawLine, rangeLocation, NULL);
                
                returnRect = CGRectMake(line.origin.x + xStart, self.frame.size.height - line.origin.y - line.ascent, xEnd - xStart, line.ascent + line.descent);
                
                break;
            }
        }
    };
    
    if (dispatch_get_specific(self.drawQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.drawQueue, block);
    }
	
    return CGRectIntegral(returnRect);
}

- (CGRect)rectForNSRange:(NSRange)range {
    CGRect firstRect = [self firstRectForNSRange:range];
    CGRect lastRect  = [self lastRectForNSRange:range];
    return CGRectUnion(firstRect, lastRect);
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
            for (EGOTextLine *line in _lines) {
                CFRange lineRange = CTLineGetStringRange(line.rawLine);
                if (lineRange.location <= position && position <= (lineRange.location + lineRange.length)) {
                    // Current line was found : calculate the new position
                    if (line && (line.index - offset) >= 0) {
                        CGFloat xOffsetToPosition = CTLineGetOffsetForStringIndex(line.rawLine, position, NULL);
                        return CTLineGetStringIndexForPosition([[_lines objectAtIndex:line.index - offset] rawLine],
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
            for (EGOTextLine *line in _lines) {
                CFRange lineRange = CTLineGetStringRange(line.rawLine);
                if (lineRange.location <= position && position <= (lineRange.location + lineRange.length)) {
                    // Current line was found : calculate the new position
                    if (line && (line.index + offset) < [_lines count]) {
                        CGFloat xOffsetToPosition = CTLineGetOffsetForStringIndex(line.rawLine, position, NULL);
                        return CTLineGetStringIndexForPosition([[_lines objectAtIndex:line.index + offset] rawLine],
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
    if (_lines) {
        [_lines removeAllObjects];
    }
    
    if (_ctFrame) {
        CFRelease(_ctFrame);
        _ctFrame = NULL;
    }
    
    if (_ctFramesetter) {
        CFRelease(_ctFramesetter);
        _ctFramesetter = NULL;
    }
}

- (void)dealloc {
    [self clearPreviousLayoutInformation];
    if (_textView) {
        [_textView removeObserver:self forKeyPath:@"frame"];
    }
}

@end
