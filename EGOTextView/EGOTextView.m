//
//  EGOTextView.m
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

#import "EGOTextView.h"
#import <QuartzCore/QuartzCore.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import "EGOCaretView.h"
#import "EGOTextWindow.h"
#import "EGOSelectionView.h"
#import "EGOMagnifyView.h"
#import "EGOIndexedPosition.h"
#import "EGOIndexedRange.h"

#include <objc/runtime.h>

NSString * const EGOTextSearch = @"com.enormego.EGOTextSearch";

NSString * const EGOTextSpellCheckingColor = @"com.enormego.EGOTextSpellCheckingColor";

NSString * const EGOTextAttachmentAttributeName = @"com.enormego.EGOTextAttachmentAttribute";
NSString * const EGOTextAttachmentPlaceholderString = @"\uFFFC";

NSString * const EGOTextViewLocalizationTable = @"EGOTextView";

#define EGOLocalizedString(_key, _value) [_localizationBundle localizedStringForKey:(_key) value:(_value) table:EGOTextViewLocalizationTable]

#pragma mark - Text attachment helper functions

static void AttachmentRunDelegateDealloc(void *refCon) {
}

static CGSize AttachmentRunDelegateGetSize(void *refCon) {
    id <EGOTextAttachmentCell> cell = (__bridge id<EGOTextAttachmentCell>)(refCon);
    if ([cell respondsToSelector: @selector(attachmentSize)]) {
        return [cell attachmentSize];
    } else {
        return [[cell attachmentView] frame].size;
    }
}

static CGFloat AttachmentRunDelegateGetDescent(void *refCon) {
    return AttachmentRunDelegateGetSize(refCon).height;
}

static CGFloat AttachmentRunDelegateGetWidth(void *refCon) {
    return AttachmentRunDelegateGetSize(refCon).width;
}

#pragma mark - EGOTextView private

@interface EGOTextView (Private)

- (CGRect)caretRectForIndex:(int)inIndex;
- (CGRect)firstRectForNSRange:(NSRange)range;
- (NSInteger)closestIndexToPoint:(CGPoint)point;
- (NSRange)characterRangeAtPoint_:(CGPoint)point;
- (void)checkSpellingForRange:(NSRange)range;
- (void)textChanged;
- (void)removeCorrectionAttributesForRange:(NSRange)range;
- (void)insertCorrectionAttributesForRange:(NSRange)range;
- (void)showCorrectionMenuForRange:(NSRange)range;
- (void)checkLinksForRange:(NSRange)range;
- (void)scanAttachments;
- (void)showMenu;
- (CGRect)menuPresentationRect;

@end

@interface EGOTextView () {
@private
    NSMutableAttributedString          *_mutableAttributedString;
    NSDictionary                       *_markedTextStyle;
    UITextInputStringTokenizer         *_tokenizer;
    UITextChecker                      *_textChecker;
    UILongPressGestureRecognizer       *_longPress;
    
    BOOL _ignoreSelectionMenu;
    
    NSAttributedString  *_attributedString;
    UIFont              *_font;
    BOOL                _editing;
    BOOL                _editable;
	
    NSRange             _markedRange;
    NSRange             _selectedRange;
    NSRange             _correctionRange;
    NSRange             _linkRange;
	
    CTFramesetterRef    _framesetter;
    CTFrameRef          _frame;
    
    EGOContentView      *_textContentView;
    EGOTextWindow       *_textWindow;
    EGOCaretView        *_caretView;
    EGOSelectionView    *_selectionView;
    
    NSMutableArray      *_attachmentViews;
    
	NSBundle			*_localizationBundle;
}

@property (nonatomic, copy) NSAttributedString *attributedString;
@property (nonatomic, copy) NSArray *searchRanges;
@property (nonatomic, strong) NSDictionary *correctionAttributes;
@property (nonatomic, strong) NSMutableDictionary *menuItemActions;
@property (nonatomic, strong) NSOperationQueue *searchQueue;
@property (nonatomic, assign) NSRange correctionRange;
@property (nonatomic, assign) dispatch_semaphore_t drawLock;

@end


@implementation EGOTextView

@dynamic delegate;
@synthesize markedRange=_markedRange;
@synthesize selectedRange=_selectedRange;
@synthesize correctionRange=_correctionRange;
@synthesize defaultAttributes=_defaultAttributes;
@synthesize typingAttributes=_typingAttributes;
@synthesize correctionAttributes=_correctionAttributes;
@synthesize markedTextStyle=_markedTextStyle;
@synthesize inputDelegate=_inputDelegate;
@synthesize menuItemActions;
@synthesize undoManager=_undoManager;

@synthesize dataDetectorTypes;
@synthesize autocapitalizationType;
@synthesize spellCheckingType;
@synthesize autocorrectionType = _autocorrectionType;
@synthesize keyboardType;
@synthesize keyboardAppearance;
@synthesize returnKeyType;
@synthesize enablesReturnKeyAutomatically;

#pragma mark - Common

- (void)commonInit {
    [self setText:@""];
    [self setAlwaysBounceVertical:YES];
    [self setEditable:YES];
	[self setLanguage:nil];
    [self setFont:[UIFont systemFontOfSize:17]];
    [self setBackgroundColor:[UIColor whiteColor]];
    [self setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [self setClipsToBounds:YES];
    [self setAutocorrectionType:UITextAutocorrectionTypeYes];
    [self setSpellCheckingType:UITextSpellCheckingTypeDefault];
    [self setAutocapitalizationType:UITextAutocapitalizationTypeSentences];
    
    _textContentView = [[EGOContentView alloc] initWithFrame:self.bounds];
    [_textContentView setAutoresizingMask:self.autoresizingMask];
    [_textContentView setDelegate:self];
    [self addSubview:_textContentView];
    
    _frame = NULL;
    _framesetter = NULL;
    
	_undoManager = [[NSUndoManager alloc] init];
	
    UILongPressGestureRecognizer *gesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPress:)];
    [gesture setDelegate:(id<UIGestureRecognizerDelegate>)self];
    [self addGestureRecognizer:gesture];
    _longPress = gesture;
    
    UITapGestureRecognizer *doubleTap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)];
    [doubleTap setNumberOfTapsRequired:2];
    [self addGestureRecognizer:doubleTap];
    
    UITapGestureRecognizer *singleTap =  [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tap:)];
    [singleTap setDelegate:(id<UIGestureRecognizerDelegate>)self];
    [self addGestureRecognizer:singleTap];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
}

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
	
    return self;
}

- (id)initWithCoder:(NSCoder *)decoder {
	self = [super initWithCoder:decoder];
    if (self) {
        [self commonInit];
    }
	
    return self;
}

- (void)dealloc {
    [self clearPreviousLayoutInformation];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

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

- (dispatch_semaphore_t)drawLock {
	if (!_drawLock) {
		_drawLock = dispatch_semaphore_create(1);
	}
	
	return _drawLock;
}

- (CGFloat)boundingWidthForHeight:(CGFloat)height {
    CGSize suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(_framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(CGFLOAT_MAX, height), NULL);
    return suggestedSize.width;
}

- (CGFloat)boundingHeightForWidth:(CGFloat)width {
    CGSize suggestedSize = CTFramesetterSuggestFrameSizeWithConstraints(_framesetter, CFRangeMake(0, 0), NULL, CGSizeMake(width, CGFLOAT_MAX), NULL);
    return suggestedSize.height;
}

- (void)textChanged {
    if ([[UIMenuController sharedMenuController] isMenuVisible]) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }
    
    [self drawText];
}

- (void)drawText {
	dispatch_semaphore_wait(self.drawLock, DISPATCH_TIME_FOREVER);
    
    [self clearPreviousLayoutInformation];
	
    _framesetter = CTFramesetterCreateWithAttributedString((__bridge CFAttributedStringRef)self.attributedString);
    
    CGRect theRect = CGRectInset(CGRectMake(0.0f, 0.0f, self.frame.size.width, self.frame.size.height), 6.0f, 15.0f);
    CGFloat height = [self boundingHeightForWidth:theRect.size.width];
    theRect.size.height = height+self.font.lineHeight;
    _textContentView.frame = theRect;
    self.contentSize = CGSizeMake(self.frame.size.width, theRect.size.height+(self.font.lineHeight*2));
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRect:_textContentView.bounds];
    
    _frame =  CTFramesetterCreateFrame(_framesetter, CFRangeMake(0, 0), [path CGPath], NULL);
    
    for (UIView *view in _attachmentViews) {
        [view removeFromSuperview];
    }
    [_attributedString enumerateAttribute:EGOTextAttachmentAttributeName
								  inRange:NSMakeRange(0, [_attributedString length])
								  options:0
							   usingBlock: ^(id value, NSRange range, BOOL *stop) {
								   if ([value respondsToSelector: @selector(attachmentView)]) {
									   UIView *view = [value attachmentView];
									   [_attachmentViews addObject: view];
									   
									   CGRect rect = [self firstRectForNSRange:range];
									   rect.size = [view frame].size;
									   [view setFrame: rect];
									   [self addSubview: view];
								   }
							   }];
    
    [_textContentView setNeedsDisplay];
    
	dispatch_semaphore_signal(self.drawLock);
}

- (NSString *)text {
    return [_attributedString string];
}

- (void)setFont:(UIFont *)font {
    _font = font;
    
    CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef) self.font.fontName, self.font.pointSize, NULL);
    NSDictionary *dictionary = [[NSDictionary alloc] initWithObjectsAndKeys:
                                (__bridge id)ctFont, (NSString *)kCTFontAttributeName,
                                (id)[UIColor blackColor].CGColor, (NSString *)kCTForegroundColorAttributeName, nil];
    self.defaultAttributes = dictionary;
    CFRelease(ctFont);
    
    [self textChanged];
}

- (void)setText:(NSString *)text {
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:self.defaultAttributes];
    [self setAttributedText:string];
}

- (void)setAttributedText:(NSAttributedString *)attributedText {
	[self.inputDelegate textWillChange:self];
	
	[_undoManager removeAllActions];
	if (_searchRanges) {
		_searchRanges = nil;
	}
    [self setAttributedString:(attributedText ? attributedText : [[NSAttributedString alloc] init])];
	[self checkSpelling];
    
    [self.inputDelegate textDidChange:self];
}

- (NSAttributedString *)attributedText {
	return [_attributedString copy];
}

- (void)setAttributedString:(NSAttributedString *)string {
	if (_searchRanges && ![string.string isEqualToString:_attributedString.string]) {
		_searchRanges = nil;
	}
	
    _attributedString = [string copy];
    
    NSUInteger length = [_attributedString length];
    NSRange range = NSMakeRange(0, length);
    if (!_editing && !_editable) {
        [self checkLinksForRange:range];
        [self scanAttachments];
    }
    
    if (self.selectedRange.location > length) {
        self.selectedRange = NSMakeRange(length, 0);
    } else {
        self.selectedRange = NSMakeRange(self.selectedRange.location, 0);
    }
    
    [self textChanged];
	
    if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChange:)]) {
        [self.delegate egoTextViewDidChange:self];
    }
}

- (void)setEditable:(BOOL)editable {
    if (editable) {
        
        if (!_caretView) {
            _caretView = [[EGOCaretView alloc] initWithFrame:CGRectZero];
        }
        
        _tokenizer = [[UITextInputStringTokenizer alloc] initWithTextInput:self];
        _textChecker = [[UITextChecker alloc] init];
        _mutableAttributedString = [[NSMutableAttributedString alloc] init];
        
        NSDictionary *dictionary = [[NSDictionary alloc] initWithObjectsAndKeys:[UIColor redColor], EGOTextSpellCheckingColor, nil];
        self.correctionAttributes = dictionary;
        
    } else {
        
        if (_caretView) {
            [_caretView removeFromSuperview];
            _caretView = nil;
        }
        
        self.correctionAttributes = nil;
        if (_textChecker) {
            _textChecker = nil;
        }
        if (_tokenizer) {
            _tokenizer = nil;
        }
        if (_mutableAttributedString) {
            _mutableAttributedString = nil;
        }
        
    }
    _editable = editable;
}

- (void)setAutocorrectionType:(UITextAutocorrectionType)autocorrectionType {
	if (_autocorrectionType == UITextAutocorrectionTypeYes && autocorrectionType == UITextAutocorrectionTypeNo) {
		[self removeCorrectionAttributesForRange:NSMakeRange(0, _attributedString.length)];
	}
	
	UITextAutocorrectionType oldAutocorrectionType = _autocorrectionType;
	_autocorrectionType = autocorrectionType;
	
	if (oldAutocorrectionType == UITextAutocorrectionTypeNo && _autocorrectionType == UITextAutocorrectionTypeYes) {
		[self checkSpelling];
	}
}

- (void)setLanguage:(NSString *)language {
	NSString *path = [[NSBundle mainBundle] pathForResource:language ofType:@"lproj"];
	if (path && language) {
		_localizationBundle = [NSBundle bundleWithPath:path];
		_language = language;
	} else {
		_localizationBundle = [NSBundle mainBundle];
		_language = [[[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"] objectAtIndex:0];
    }
}

- (void)setBackgroundColor:(UIColor *)backgroundColor {
	[super setBackgroundColor:backgroundColor];
	[_textContentView setBackgroundColor:backgroundColor];
}

#pragma mark - Layout methods

- (NSRange)rangeIntersection:(NSRange)first withSecond:(NSRange)second {
    NSRange result = NSMakeRange(NSNotFound, 0);
    
    if (first.location > second.location) {
        NSRange tmp = first;
        first = second;
        second = tmp;
    }
    
    if (second.location < first.location + first.length) {
        result.location = second.location;
        NSUInteger end = MIN(first.location + first.length, second.location + second.length);
        result.length = end - result.location;
    }
    
    return result;
}

- (void)drawPathFromRects:(NSArray *)array cornerRadius:(CGFloat)cornerRadius {
    if (!array || [array count] == 0) return;
    
    CGMutablePathRef _path = CGPathCreateMutable();
    
    CGRect firstRect = CGRectFromString([array objectAtIndex:0]);
    CGRect lastRect = CGRectFromString([array lastObject]);
    if ([array count] > 1) {
        firstRect.size.width = _textContentView.bounds.size.width-firstRect.origin.x;
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
        CGFloat width = ([array count] == 2) ? originX + MIN(CGRectGetMaxX(firstRect), CGRectGetMaxX(lastRect)) : _textContentView.bounds.size.width;
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
        NSRange intersection = [self rangeIntersection:range withSecond:selectionRange];
        
        if (intersection.location != NSNotFound && intersection.length > 0) {
            CGFloat xStart = CTLineGetOffsetForStringIndex(line, intersection.location, NULL);
            CGFloat xEnd = CTLineGetOffsetForStringIndex(line, intersection.location + intersection.length, NULL);
            
            CGPoint origin = origins[i];
            CGFloat ascent, descent;
            CTLineGetTypographicBounds(line, &ascent, &descent, NULL);
            
            CGRect selectionRect = CGRectMake(origin.x + xStart, origin.y + ascent, xEnd - xStart, ascent + descent);
			selectionRect.origin.y = _textContentView.frame.size.height - selectionRect.origin.y;
            
            if (range.length == 1) {
                selectionRect.size.width = _textContentView.bounds.size.width;
            }
            
            [pathRects addObject:NSStringFromCGRect(selectionRect)];
        }
    }
    
    [self drawPathFromRects:pathRects cornerRadius:cornerRadius];
    free(origins);
}

- (void)drawContentInRect:(CGRect)rect {
	if (_searchRanges && [_searchRanges count] > 0) {
		[[UIColor colorWithRed:1.0f green:1.0f blue:0.0f alpha:1.0f] setFill];
		for (int i = 0; i < [_searchRanges count]; i++) {
			[self drawBoundingRangeAsSelection:((EGOIndexedRange *)[_searchRanges objectAtIndex:i]).range cornerRadius:2.0f];
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
    CGContextTranslateCTM(ctx, 0, _textContentView.frame.size.height);
    CGContextScaleCTM(ctx, 1.0, -1.0);
	for (int i = 0; i < count; i++) {
        CTLineRef line = (CTLineRef)CFArrayGetValueAtIndex((CFArrayRef)lines, i);
        CFArrayRef runs = CTLineGetGlyphRuns(line);
        CFIndex runsCount = CFArrayGetCount(runs);
        
        if (self.drawDelegate) {
            for (CFIndex runsIndex = 0; runsIndex < runsCount; runsIndex++) {
                CTRunRef run = CFArrayGetValueAtIndex(runs, runsIndex);
                [self.drawDelegate egoTextView:self drawBeforeGlyphRun:run forLine:line withOrigin:origins[i] inContext:ctx];
            }
        }
        
        CGContextSetTextPosition(ctx, frameRect.origin.x + origins[i].x, frameRect.origin.y + origins[i].y);
        CTLineDraw(line, ctx);
        
        for (CFIndex runsIndex = 0; runsIndex < runsCount; runsIndex++) {
            CTRunRef run = CFArrayGetValueAtIndex(runs, runsIndex);
            
            if (self.drawDelegate) {
                [self.drawDelegate egoTextView:self drawAfterGlyphRun:run forLine:line withOrigin:origins[i] inContext:ctx];
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
    [self drawBoundingRangeAsSelection:_linkRange cornerRadius:2.0f];
    [[EGOTextView selectionColor] setFill];
    [self drawBoundingRangeAsSelection:self.selectedRange cornerRadius:0.0f];
    [[EGOTextView spellingSelectionColor] setFill];
    [self drawBoundingRangeAsSelection:self.correctionRange cornerRadius:2.0f];
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

- (NSInteger)closestWhiteSpaceIndexToPoint:(CGPoint)point {
    point = [self convertPoint:point toView:_textContentView];
	point.y = _textContentView.frame.size.height - point.y;
	
    NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    NSInteger count = [lines count];
    CGPoint *origins = (CGPoint *)malloc(count * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, count), origins);
    
    __block NSRange returnRange = NSMakeRange(_attributedString.length, 0);
    
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
            
            if (theIndex >=_attributedString.length) {
                returnRange = NSMakeRange(_attributedString.length, 0);
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
                if (range.length > 1 && [_attributedString.string characterAtIndex:(range.location+range.length)-1] == '\n') {
                    returnRange = NSMakeRange(theIndex - 1, 0);
                    break;
                } else {
                    returnRange = NSMakeRange(range.location+range.length, 0);
                    break;
                }
            }
            
            [_attributedString.string enumerateSubstringsInRange:range
														 options:NSStringEnumerationByWords
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

- (NSInteger)closestIndexToPoint:(CGPoint)point {
    point = [self convertPoint:point toView:_textContentView];
	point.y = _textContentView.frame.size.height - point.y;
	
    NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    NSInteger count = [lines count];
    CGPoint *origins = (CGPoint *)malloc(count * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, count), origins);
    CFIndex theIndex = kCFNotFound;
    
    for (int i = 0; i < lines.count; i++) {
        if (point.y > origins[i].y) {
            CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:i];
            CGPoint convertedPoint = CGPointMake(point.x - origins[i].x, point.y - origins[i].y);
            theIndex = CTLineGetStringIndexForPosition(line, convertedPoint);
            break;
        }
    }
    
    if (theIndex == kCFNotFound) {
        theIndex = [_attributedString length];
    }
    
    free(origins);
    return theIndex;
}

- (NSRange)characterRangeAtPoint_:(CGPoint)point {
	__block NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    
    CGPoint *origins = (CGPoint *)malloc([lines count] * sizeof(CGPoint));
    CTFrameGetLineOrigins(_frame, CFRangeMake(0, [lines count]), origins);
    __block NSRange returnRange = NSMakeRange(NSNotFound, 0);
	
    for (int i = 0; i < lines.count; i++) {
        
        if (point.y > origins[i].y) {
			
            CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:i];
            CGPoint convertedPoint = CGPointMake(point.x - origins[i].x, point.y - origins[i].y);
            NSInteger theIndex = CTLineGetStringIndexForPosition(line, convertedPoint);
			
            CFRange cfRange = CTLineGetStringRange(line);
            NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length);
            
            [_attributedString.string enumerateSubstringsInRange:range options:NSStringEnumerationByWords usingBlock:^(NSString *subString, NSRange subStringRange, NSRange enclosingRange, BOOL *stop){
                
                returnRange = subStringRange;
                if (theIndex - subStringRange.location <= subStringRange.length) {
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
    
    for (int i=0; i < count; i++) {
        
        __block CTLineRef line = (__bridge CTLineRef)[lines objectAtIndex:i];
        CFRange cfRange = CTLineGetStringRange(line);
        NSRange range = NSMakeRange(cfRange.location == kCFNotFound ? NSNotFound : cfRange.location, cfRange.length == kCFNotFound ? 0 : cfRange.length);
        
        if (inIndex >= range.location && inIndex <= range.location+range.length) {
            
            if (range.length > 1) {
                
                [_attributedString.string enumerateSubstringsInRange:range options:NSStringEnumerationByWords usingBlock:^(NSString *subString, NSRange subStringRange, NSRange enclosingRange, BOOL *stop){
                    
                    if (inIndex - subStringRange.location <= subStringRange.length) {
                        returnRange = subStringRange;
                        *stop = YES;
                    }
                    
                }];
                
            }
			
        }
    }
    return returnRange;
}

- (CGRect)caretRectForIndex:(NSInteger)inIndex {
    CGFloat caretWidth = 3.0f;
    
    NSArray *lines = (__bridge NSArray *)CTFrameGetLines(_frame);
    
    // no text / first index
    if (_attributedString.length == 0 || inIndex == 0) {
        CGPoint origin = CGPointMake(CGRectGetMinX(_textContentView.bounds), CGRectGetMaxY(_textContentView.bounds) - self.font.leading);
        return CGRectMake(origin.x, _textContentView.frame.size.height - origin.y - (self.font.ascender + fabs(self.font.descender)), caretWidth, self.font.ascender + fabs(self.font.descender));
    }
	
    // last index is newline
    if (inIndex == _attributedString.length && [_attributedString.string characterAtIndex:(inIndex - 1)] == '\n' ) {
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
        
        origin.y -= self.font.leading;
		CGRect returnRect = CGRectMake(origin.x + xPos, floorf(origin.y + ascent), caretWidth, ceilf(descent + ascent));
		returnRect.origin.y = _textContentView.frame.size.height - returnRect.origin.y;
        return returnRect;
    }
	
    inIndex = MAX(inIndex, 0);
    inIndex = MIN(_attributedString.string.length, inIndex);
	
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
			
            if (_selectedRange.length > 0 && inIndex != _selectedRange.location && range.length == 1) {
                
                xPos = _textContentView.bounds.size.width - caretWidth; // selection of entire line
                
            } else if ([_attributedString.string characterAtIndex:inIndex-1] == '\n' && range.length == 1) {
				
                xPos = 0.0f; // empty line
				
            }
            
            returnRect = CGRectMake(origin.x + xPos, floorf(origin.y + ascent), caretWidth, ceilf(descent + ascent));
			returnRect.origin.y = _textContentView.frame.size.height - returnRect.origin.y;
        }
        
    }
    
    free(origins);
    return returnRect;
}

- (CGRect)firstRectForNSRange:(NSRange)range{
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
            
            returnRect = CGRectMake(origin.x + xStart, _textContentView.frame.size.height - origin.y - ascent, xEnd - xStart, ascent + descent);
			
            break;
        }
    }
	
    free(origins);
    return CGRectIntegral(returnRect);
}

- (void)scrollToTextRange:(NSRange)range {
    CGRect rect = [self caretRectForIndex:range.location];
    [self scrollRectToVisible:[_textContentView convertRect:rect toView:self] animated:YES];
}

#pragma mark - UIKeyboard notification

- (void)keyboardWillShow:(NSNotification *)notification {
	NSDictionary *userInfo = [notification userInfo];
	CGRect keyboardFrame = [[userInfo objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
	CGRect ownFrame = [[[[UIApplication sharedApplication] delegate] window] convertRect:self.frame fromView:self.superview];    
	CGRect coveredFrame = CGRectIntersection(ownFrame, keyboardFrame);
	coveredFrame = [[[[UIApplication sharedApplication] delegate] window] convertRect:coveredFrame toView:self.superview];
    
	[self setContentInset:UIEdgeInsetsMake(0, 0, coveredFrame.size.height, 0)];
	[self setScrollIndicatorInsets:[self contentInset]];
}

- (void)keyboardDidShow:(NSNotification *)notification {
	CGRect frame = _caretView.frame;
	frame.origin.y += (self.font.lineHeight*2);
	if (!(_selectedRange.location == 0 && _selectedRange.length == 0)) {
		[self scrollRectToVisible:[_textContentView convertRect:frame toView:self] animated:YES];
	}
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [self setContentInset:UIEdgeInsetsZero];
    [self setScrollIndicatorInsets:[self contentInset]];
}

#pragma mark - Text Selection

- (void)selectionChanged {
    if (!_editing) {
        [_caretView removeFromSuperview];
    }
    
    _ignoreSelectionMenu = NO;
    
    if (self.selectedRange.length == 0) {
        if (_selectionView) {
            [_selectionView removeFromSuperview];
            _selectionView = nil;
        }
        
        if (_editing && !_caretView.superview) {
            [_textContentView addSubview:_caretView];
            [_textContentView setNeedsDisplay];
        }
        
        [_caretView setFrame:[self caretRectForIndex:self.selectedRange.location]];
        [_caretView delayBlink];
        
        CGRect frame = _caretView.frame;
        frame.origin.y += (self.font.lineHeight*2);
        if (!(_selectedRange.location == 0 && _selectedRange.length == 0)) {
            [self scrollRectToVisible:[_textContentView convertRect:frame toView:self] animated:YES];
        }
        
        [_textContentView setNeedsDisplay];
        
        _longPress.minimumPressDuration = 0.5f;
    } else {
        _longPress.minimumPressDuration = 0.0f;
        
        if (_caretView && _caretView.superview) {
            [_caretView removeFromSuperview];
        }
        
        if (!_selectionView) {
            EGOSelectionView *view = [[EGOSelectionView alloc] initWithFrame:_textContentView.bounds];
            [_textContentView addSubview:view];
            _selectionView = view;
            
        }
        
        CGRect begin = [self caretRectForIndex:_selectedRange.location];
        CGRect end   = [self caretRectForIndex:_selectedRange.location+_selectedRange.length];
        [_selectionView setBeginCaret:begin endCaret:end];
        [_textContentView setNeedsDisplay];
    }
    
    if (self.markedRange.location != NSNotFound) {
        [_textContentView setNeedsDisplay];
    }
	
	if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChangeSelection:)]) {
		[self.delegate egoTextViewDidChangeSelection:self];
	}
}

- (NSRange)markedRange {
    return _markedRange;
}

- (NSRange)selectedRange {
    return _selectedRange;
}

- (void)setMarkedRange:(NSRange)range {
    _markedRange = range;
    //[self selectionChanged];
}

- (void)setSelectedRange:(NSRange)range {
	_selectedRange = NSMakeRange(range.location == NSNotFound ? NSNotFound : MAX(0, range.location), range.length);
    [self selectionChanged];
}

- (void)setCorrectionRange:(NSRange)range {
    if (NSEqualRanges(range, _correctionRange) && range.location == NSNotFound && range.length == 0) {
        _correctionRange = range;
        return;
    }
    
    _correctionRange = range;
    if (range.location != NSNotFound && range.length > 0) {
        if (_caretView.superview) {
            [_caretView removeFromSuperview];
        }
        
        [self removeCorrectionAttributesForRange:_correctionRange];
        [self showCorrectionMenuForRange:_correctionRange];
    } else if (!_caretView.superview) {
        [_textContentView addSubview:_caretView];
        [_caretView delayBlink];
    }
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[_textContentView setNeedsDisplay];
	});
}

- (void)setSearchRanges:(NSArray *)searchRanges {
	if (_searchRanges && [_searchRanges count] > 0) {
		NSMutableAttributedString *string = [_attributedString mutableCopy];
		for (int i = 0; i < [_searchRanges count]; i++) {
			[string removeAttribute:EGOTextSearch range:((EGOIndexedRange *)[_searchRanges objectAtIndex:i]).range];
		}
		self.attributedString = string;
	}
	_searchRanges = searchRanges;
	
	dispatch_async(dispatch_get_main_queue(), ^{
		[_textContentView setNeedsDisplay];
	});
}

- (void)setLinkRange:(NSRange)range {
    _linkRange = range;
    
    if (_linkRange.length>0) {
        if (_caretView.superview) {
            [_caretView removeFromSuperview];
        }
    } else if (!_caretView.superview) {
		[_textContentView addSubview:_caretView];
		_caretView.frame = [self caretRectForIndex:self.selectedRange.location];
		[_caretView delayBlink];
    }
    
	dispatch_async(dispatch_get_main_queue(), ^{
		[_textContentView setNeedsDisplay];
	});
}

- (void)setLinkRangeFromTextCheckerResults:(NSTextCheckingResult*)results {
    if (_linkRange.length>0) {
        UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:[[results URL] absoluteString]
                                                                 delegate:(id<UIActionSheetDelegate>)self
                                                        cancelButtonTitle:@"Cancel"
                                                   destructiveButtonTitle:nil
                                                        otherButtonTitles:@"Open", nil];
        [actionSheet showInView:self];
    }
}

+ (UIColor *)selectionColor {
    static UIColor *color = nil;
    if (!color) {
        color = [UIColor colorWithRed:0.f green:0.35f blue:0.65f alpha:0.2f];
    }
    return color;
}

+ (UIColor *)caretColor {
    static UIColor *color = nil;
    if (!color) {
        color = [UIColor colorWithRed:0.259f green:0.420f blue:0.949f alpha:1.0f];
    }
    return color;
}

+ (UIColor*)spellingSelectionColor {
    static UIColor *color = nil;
    if (!color) {
        color = [UIColor colorWithRed:1.f green:0.f blue:0.f alpha:0.149f];
    }
    return color;
}

#pragma mark - UITextInput - Replacing and Returning Text

- (NSString *)textInRange:(UITextRange *)range {
    EGOIndexedRange *r = (EGOIndexedRange *)range;
    if (r.range.location + r.range.length > _attributedString.length) {
        r = [EGOIndexedRange rangeWithNSRange:NSMakeRange(r.range.location, _attributedString.length)];
    }
    return ([_attributedString.string substringWithRange:r.range]);
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    EGOIndexedRange *r = (EGOIndexedRange *)range;
	
    NSRange selectedNSRange = self.selectedRange;
    if ((r.range.location + r.range.length) <= selectedNSRange.location) {
        selectedNSRange.location -= (r.range.length - text.length);
    } else {
        selectedNSRange = [self rangeIntersection:r.range withSecond:_selectedRange];
    }
    
    [_mutableAttributedString replaceCharactersInRange:r.range withString:text];
    self.attributedString = _mutableAttributedString;
    self.selectedRange = selectedNSRange;
}

#pragma mark - UITextInput - Working with Marked and Selected Text

- (UITextRange *)selectedTextRange {
    return [EGOIndexedRange rangeWithNSRange:self.selectedRange];
}

- (void)setSelectedTextRange:(UITextRange *)range {
    EGOIndexedRange *r = (EGOIndexedRange *)range;
    self.selectedRange = r.range;
}

- (UITextRange *)markedTextRange {
    return [EGOIndexedRange rangeWithNSRange:self.markedRange];
}

- (void)setMarkedText:(NSString *)markedText selectedRange:(NSRange)selectedRange {
    NSRange selectedNSRange = self.selectedRange;
    NSRange markedTextRange = self.markedRange;
    
    if (markedTextRange.location != NSNotFound) {
        if (!markedText) {
            markedText = @"";
        }
        [_mutableAttributedString replaceCharactersInRange:markedTextRange withString:markedText];
        markedTextRange.length = markedText.length;
        
    } else if (selectedNSRange.length > 0) {
        
        [_mutableAttributedString replaceCharactersInRange:selectedNSRange withString:markedText];
        markedTextRange.location = selectedNSRange.location;
        markedTextRange.length = markedText.length;
        
    } else {
        
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:markedText attributes:self.defaultAttributes];
        [_mutableAttributedString insertAttributedString:string atIndex:selectedNSRange.location];
        
        markedTextRange.location = selectedNSRange.location;
        markedTextRange.length = markedText.length;
    }
    
    selectedNSRange = NSMakeRange(selectedRange.location + markedTextRange.location, selectedRange.length);
    
    self.attributedString = markedText.length == 0 ? _attributedString : _mutableAttributedString;
    self.markedRange = markedTextRange;
    self.selectedRange = selectedNSRange;
}

- (void)unmarkText {
    NSRange markedTextRange = self.markedRange;
    
    if (markedTextRange.location == NSNotFound) return;
    
    markedTextRange.location = NSNotFound;
    self.markedRange = markedTextRange;
}

#pragma mark - UITextInput - Computing Text Ranges and Text Positions

- (UITextPosition *)beginningOfDocument {
    return [EGOIndexedPosition positionWithIndex:0];
}

- (UITextPosition *)endOfDocument {
    return [EGOIndexedPosition positionWithIndex:_attributedString.length];
}

- (UITextRange *)textRangeFromPosition:(UITextPosition *)fromPosition toPosition:(UITextPosition *)toPosition {
    EGOIndexedPosition *from = (EGOIndexedPosition *)fromPosition;
    EGOIndexedPosition *to = (EGOIndexedPosition *)toPosition;
    NSRange range = NSMakeRange(MIN(from.positionIndex, to.positionIndex), ABS(to.positionIndex - from.positionIndex));
    return [EGOIndexedRange rangeWithNSRange:range];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position offset:(NSInteger)offset {
    EGOIndexedPosition *pos = (EGOIndexedPosition *)position;
    NSInteger end = pos.positionIndex + offset;
	
    if (end > _attributedString.length || end < 0) return nil;
    
    return [EGOIndexedPosition positionWithIndex:end];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset {
    EGOIndexedPosition *pos = (EGOIndexedPosition *)position;
    NSInteger newPos = pos.positionIndex;
    
    switch (direction) {
        case UITextLayoutDirectionRight:
            newPos += offset;
            break;
        case UITextLayoutDirectionLeft:
            newPos -= offset;
            break;
        case UITextLayoutDirectionUp: {
            // Iterate through lines to find the one which contains the position given
            CFArrayRef lines = CTFrameGetLines(_frame);
            for (NSInteger i = 0; i < CFArrayGetCount(lines); i++) {
                CTLineRef line = CFArrayGetValueAtIndex(lines, i);
                CFRange lineRange = CTLineGetStringRange(line);
                if (lineRange.location <= newPos && newPos <= (lineRange.location + lineRange.length)) {
                    // Current line was found : calculate the new position
                    if ( line && (i - offset) >= 0) {
                        CGFloat xOffsetToPosition = CTLineGetOffsetForStringIndex(line, newPos, NULL);
                        newPos = CTLineGetStringIndexForPosition(CFArrayGetValueAtIndex(lines, i - offset),
                                                                 CGPointMake(xOffsetToPosition, 0.0f));
                    } else {
                        newPos = 0;
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
                if (lineRange.location <= newPos && newPos <= lineRange.location + lineRange.length) {
                    // Current line was found : calculate the new position
                    if (line && (i + offset) < CFArrayGetCount(lines)) {
                        CGFloat xOffsetToPosition = CTLineGetOffsetForStringIndex(line, newPos, NULL);
                        newPos = CTLineGetStringIndexForPosition(CFArrayGetValueAtIndex(lines, i + offset),
                                                                 CGPointMake(xOffsetToPosition, 0.0f));
                    } else {
                        newPos = _attributedString.length;
                    }
                    break;
                }
            }
        } break;
        default:
            break;
    }
	
    if (newPos < 0)
        newPos = 0;
    
    if (newPos > _attributedString.length)
        newPos = _attributedString.length;
    
    return [EGOIndexedPosition positionWithIndex:newPos];
}

#pragma mark - UITextInput - Evaluating Text Positions

- (NSComparisonResult)comparePosition:(UITextPosition *)position toPosition:(UITextPosition *)other {
    EGOIndexedPosition *pos = (EGOIndexedPosition *)position;
    EGOIndexedPosition *o = (EGOIndexedPosition *)other;
    
    if (pos.positionIndex == o.positionIndex) {
        return NSOrderedSame;
    } if (pos.positionIndex < o.positionIndex) {
        return NSOrderedAscending;
    } else {
        return NSOrderedDescending;
    }
}

- (NSInteger)offsetFromPosition:(UITextPosition *)from toPosition:(UITextPosition *)toPosition {
    EGOIndexedPosition *f = (EGOIndexedPosition *)from;
    EGOIndexedPosition *t = (EGOIndexedPosition *)toPosition;
    return (t.positionIndex - f.positionIndex);
}

#pragma mark - UITextInput - Text Input Delegate and Text Input Tokenizer

- (id <UITextInputTokenizer>)tokenizer {
    return _tokenizer;
}


#pragma mark - UITextInput - Text Layout, writing direction and position

- (UITextPosition *)positionWithinRange:(UITextRange *)range farthestInDirection:(UITextLayoutDirection)direction {
    EGOIndexedRange *r = (EGOIndexedRange *)range;
    NSInteger pos;
    
    switch (direction) {
        case UITextLayoutDirectionUp:
        case UITextLayoutDirectionLeft:
            pos = r.range.location;
            break;
        case UITextLayoutDirectionRight:
        case UITextLayoutDirectionDown:
            pos = r.range.location + r.range.length;
            break;
        default:
            pos = r.range.location;
            break;
    }
    
    return [EGOIndexedPosition positionWithIndex:pos];
}

- (UITextRange *)characterRangeByExtendingPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction {
	
    EGOIndexedPosition *pos = (EGOIndexedPosition *)position;
    NSRange result;
    
    switch (direction) {
        case UITextLayoutDirectionUp:
        case UITextLayoutDirectionLeft:
            result = NSMakeRange(pos.positionIndex - 1, 1);
            break;
        case UITextLayoutDirectionRight:
        case UITextLayoutDirectionDown:
            result = NSMakeRange(pos.positionIndex, 1);
            break;
        default:
            result = NSMakeRange(pos.positionIndex, 1);
            break;
    }
    
    return [EGOIndexedRange rangeWithNSRange:result];
}

- (UITextWritingDirection)baseWritingDirectionForPosition:(UITextPosition *)position inDirection:(UITextStorageDirection)direction {
    return UITextWritingDirectionLeftToRight;
}

- (void)setBaseWritingDirection:(UITextWritingDirection)writingDirection forRange:(UITextRange *)range {
    // only ltr supported for now.
}

#pragma mark - UITextInput - Geometry

- (CGRect)firstRectForRange:(UITextRange *)range {
    if (!range) {
        return CGRectZero;
    }
    EGOIndexedRange *r = (EGOIndexedRange *)range;
    CGRect rect = [self firstRectForNSRange:r.range];
    return rect;
}

- (CGRect)caretRectForPosition:(UITextPosition *)position {
    EGOIndexedPosition *pos = (EGOIndexedPosition *)position;
	CGRect rect = [self caretRectForIndex:pos.positionIndex];
	return rect;
}

- (NSArray *)selectionRectsForRange:(UITextRange *)range {
    return [NSArray array];
}

- (UIView *)textInputView {
    return _textContentView;
}

#pragma mark - UITextInput - Hit testing

- (UITextPosition *)closestPositionToPoint:(CGPoint)point {
    EGOIndexedPosition *position = [EGOIndexedPosition positionWithIndex:[self closestIndexToPoint:point]];
    return position;
}

- (UITextPosition *)closestPositionToPoint:(CGPoint)point withinRange:(UITextRange *)range {
    EGOIndexedPosition *position = [EGOIndexedPosition positionWithIndex:[self closestIndexToPoint:point]];
    return position;
}

- (UITextRange *)characterRangeAtPoint:(CGPoint)point {
    EGOIndexedRange *range = [EGOIndexedRange rangeWithNSRange:[self characterRangeAtPoint_:point]];
    return range;
}

#pragma mark - UITextInput - Styling Information

- (NSDictionary *)textStylingAtPosition:(UITextPosition *)position inDirection:(UITextStorageDirection)direction {
    if (!position) {
        return nil;
    }
    
    EGOIndexedPosition *pos = (EGOIndexedPosition*)position;
    NSDictionary *ctStyles;
    {
        NSUInteger stylePosition = pos.positionIndex;
        if (_selectedRange.location != NSNotFound || (_selectedRange.length == 0 && _selectedRange.location == stylePosition)) {
            ctStyles = [self typingAttributes];
        } else if (direction == UITextStorageDirectionBackward && stylePosition > 0) {
            ctStyles = [_attributedString attributesAtIndex:stylePosition-1 effectiveRange:NULL];
        } else {
            // If the selection encompasses the end of the text with forwards affinity
            if (stylePosition >= [_attributedString length]) {
                stylePosition--;
            }
            ctStyles = [_attributedString attributesAtIndex:stylePosition effectiveRange:NULL];
        }
    }
    
    NSMutableDictionary *uiStyles = [[NSMutableDictionary alloc] initWithDictionary:ctStyles];
    
    CTFontRef ctFont = (__bridge CTFontRef)[ctStyles objectForKey:(id)kCTFontAttributeName];
    if (ctFont) {
        CFStringRef fontName = CTFontCopyPostScriptName(ctFont);
        UIFont *uif = [UIFont fontWithName:(__bridge id)fontName size:CTFontGetSize(ctFont)];
        if (!uif) {
            uif = [UIFont fontWithName:@"Helvetica Neue" size:CTFontGetSize(ctFont)];
        }
        [uiStyles setObject:uif forKey:UITextInputTextFontKey];
        CFRelease(fontName);
    }
    
    CGColorRef cgColor = (__bridge CGColorRef)[ctStyles objectForKey:(id)kCTForegroundColorAttributeName];
    if (cgColor) {
        [uiStyles setObject:[UIColor colorWithCGColor:cgColor] forKey:UITextInputTextColorKey];
    }
    
    if (self.backgroundColor) {
        [uiStyles setObject:self.backgroundColor forKey:UITextInputTextBackgroundColorKey];
    }
    
    return uiStyles;
}

#pragma mark - UIKeyInput methods

- (BOOL)hasText {
    return (_attributedString.length != 0);
}

- (void)insertText:(NSString *)text {
    if (!text) return;
    
    NSRange selectedNSRange = self.selectedRange;
    NSRange markedTextRange = self.markedRange;
    
    [_mutableAttributedString setAttributedString:self.attributedString];
    
    NSMutableDictionary *attributes = nil;
	if (_mutableAttributedString.length > 0) {
		attributes = [[NSMutableDictionary alloc] initWithDictionary:[self typingAttributes]];
		[attributes removeObjectForKey:EGOTextSpellCheckingColor];
	}
    NSAttributedString *newString = [[NSAttributedString alloc] initWithString:text
                                                                    attributes:(attributes ? attributes : self.defaultAttributes)];
    
    if (_correctionRange.location != NSNotFound && _correctionRange.length > 0){
        
		[[_undoManager prepareWithInvocationTarget:self] replaceString:[_mutableAttributedString attributedSubstringFromRange:self.correctionRange]
															   inRange:self.correctionRange];
        [_mutableAttributedString replaceCharactersInRange:self.correctionRange withAttributedString:newString];
        selectedNSRange.length = 0;
        selectedNSRange.location = (self.correctionRange.location+text.length);
        self.correctionRange = NSMakeRange(NSNotFound, 0);
		
    } else if (markedTextRange.location != NSNotFound) {
        
		[[_undoManager prepareWithInvocationTarget:self] replaceString:[_mutableAttributedString attributedSubstringFromRange:markedTextRange]
															   inRange:markedTextRange];
        [_mutableAttributedString replaceCharactersInRange:markedTextRange withAttributedString:newString];
        selectedNSRange.location = markedTextRange.location + text.length;
        selectedNSRange.length = 0;
        markedTextRange = NSMakeRange(NSNotFound, 0);
        
    } else if (selectedNSRange.length > 0) {
        
		[[_undoManager prepareWithInvocationTarget:self] replaceString:[_mutableAttributedString attributedSubstringFromRange:selectedNSRange]
															   inRange:selectedNSRange];
        [_mutableAttributedString replaceCharactersInRange:selectedNSRange withAttributedString:newString];
        selectedNSRange.length = 0;
        selectedNSRange.location = (selectedNSRange.location + text.length);
        
    } else {
        
		[[_undoManager prepareWithInvocationTarget:self] deleteCharactersInRange:NSMakeRange(selectedNSRange.location, newString.length)];
        [_mutableAttributedString insertAttributedString:newString atIndex:selectedNSRange.location];
		selectedNSRange.location += text.length;
        
    }
    
    self.attributedString = _mutableAttributedString;
    self.markedRange = markedTextRange;
    self.selectedRange = selectedNSRange;
	
    if (text.length > 1 || ([text isEqualToString:@" "] || [text isEqualToString:@"\n"])) {
        [self checkSpellingForRange:[self characterRangeAtIndex:self.selectedRange.location]];
        [self checkLinksForRange:NSMakeRange(0, self.attributedString.length)];
    }
}

- (void)deleteBackward {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showCorrectionMenuWithoutSelection) object:nil];
    
    NSRange selectedNSRange = self.selectedRange;
    NSRange markedTextRange = self.markedRange;
    
    if (_correctionRange.location != NSNotFound && _correctionRange.length > 0) {
		[self deleteCharactersInRange:self.correctionRange];
        
		selectedNSRange.location = self.correctionRange.location;
        self.correctionRange = NSMakeRange(NSNotFound, 0);
        selectedNSRange.length = 0;
    } else if (markedTextRange.location != NSNotFound) {
		[self deleteCharactersInRange:selectedNSRange];
        
        selectedNSRange.location = markedTextRange.location;
        selectedNSRange.length = 0;
		markedTextRange = NSMakeRange(NSNotFound, 0);
    } else if (selectedNSRange.length > 0) {
		[self deleteCharactersInRange:selectedNSRange];
        
        selectedNSRange.length = 0;
    } else if (selectedNSRange.location > 0) {
        NSInteger theIndex = MAX(0, selectedNSRange.location-1);
        theIndex = MIN(_attributedString.length-1, theIndex);
        if ([_attributedString.string characterAtIndex:theIndex] == ' ') {
            [self performSelector:@selector(showCorrectionMenuWithoutSelection) withObject:nil afterDelay:0.2f];
        }
        
        selectedNSRange = [[_attributedString string] rangeOfComposedCharacterSequenceAtIndex:selectedNSRange.location - 1];
		
		[self deleteCharactersInRange:selectedNSRange];
        
        selectedNSRange.length = 0;
    } else if (selectedNSRange.location > _mutableAttributedString.length) {
		selectedNSRange.location = _mutableAttributedString.length;
		selectedNSRange.length = 0;
	}
    
    self.markedRange = markedTextRange;
    self.selectedRange = selectedNSRange;
}

- (void)replaceString:(NSAttributedString *)text inRange:(NSRange)range {
	[_mutableAttributedString setAttributedString:self.attributedString];
	
	[[_undoManager prepareWithInvocationTarget:self] replaceString:[_mutableAttributedString attributedSubstringFromRange:range]
														   inRange:range];
	
	[_mutableAttributedString beginEditing];
	[_mutableAttributedString replaceCharactersInRange:range withAttributedString:text];
	[_mutableAttributedString endEditing];
	
	self.attributedString = _mutableAttributedString;
	
	self.selectedRange = NSMakeRange(range.location + range.length, 0);
}

- (void)insertString:(NSAttributedString *)text inRange:(NSRange)range {
	[_mutableAttributedString setAttributedString:self.attributedString];
	
	[_mutableAttributedString beginEditing];
	[_mutableAttributedString insertAttributedString:text atIndex:range.location];
	[_mutableAttributedString endEditing];
	
	self.attributedString = _mutableAttributedString;
	
	[[_undoManager prepareWithInvocationTarget:self] deleteCharactersInRange:range];
	
	self.selectedRange = NSMakeRange(range.location + range.length, 0);
}

- (void)deleteCharactersInRange:(NSRange)range {
	[_mutableAttributedString setAttributedString:self.attributedString];
	
	[[_undoManager prepareWithInvocationTarget:self] insertString:[_mutableAttributedString attributedSubstringFromRange:range]
														  inRange:range];
	
	[_mutableAttributedString beginEditing];
	[_mutableAttributedString deleteCharactersInRange:range];
	[_mutableAttributedString endEditing];
	
	self.attributedString = _mutableAttributedString;
	
	self.selectedRange = NSMakeRange(range.location, 0);
}

- (NSDictionary *)typingAttributes {
    if (_typingAttributes) {
        return _typingAttributes;
    }
    
    NSUInteger contentLength = [self.attributedString length];
    if (contentLength == 0)
        return nil;
    
    NSUInteger insertAt;
    if (_correctionRange.location != NSNotFound) {
        insertAt = _correctionRange.location;
    } else if (self.markedRange.location != NSNotFound) {
        insertAt = self.markedRange.location;
    } else if (self.selectedRange.location != NSNotFound) {
        insertAt = self.selectedRange.location;
    } else {
        insertAt = contentLength;
    }
    
    if (insertAt > contentLength) {
        insertAt = contentLength;
    }
    _typingAttributes = [self.attributedString attributesAtIndex:(insertAt > 0 ? insertAt-1 : 0) effectiveRange:NULL];
    return _typingAttributes;
}

- (void)setTypingAttributes:(NSDictionary *)typingAttributes {
    if ([_typingAttributes isEqualToDictionary:typingAttributes]) return;
    
    _typingAttributes = [typingAttributes copy];
}

#pragma mark - Data Detectors (links)

- (NSTextCheckingResult *)linkAtIndex:(NSInteger)index {
    NSRange range = [self characterRangeAtIndex:index];
    if (range.location==NSNotFound || range.length == 0) {
        return nil;
    }
    
    __block NSTextCheckingResult *link = nil;
    NSError *error = nil;
    NSDataDetector *linkDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
    [linkDetector enumerateMatchesInString:[self.attributedString string] options:0 range:range usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
        
        if ([result resultType] == NSTextCheckingTypeLink) {
            *stop = YES;
            link = result;
        }
        
    }];
	
    return link;
}

- (void)checkLinksForRange:(NSRange)range {
    NSDictionary *linkAttributes = [NSDictionary dictionaryWithObjectsAndKeys:(id)[UIColor blueColor].CGColor, kCTForegroundColorAttributeName, [NSNumber numberWithInt:(int)kCTUnderlineStyleSingle], kCTUnderlineStyleAttributeName, nil];
    
    NSMutableAttributedString *string = (_attributedString ? [_attributedString mutableCopy] : [[NSMutableAttributedString alloc] init]);
    NSError *error = nil;
	NSDataDetector *linkDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
	[linkDetector enumerateMatchesInString:[string string] options:0 range:range usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
		
        if ([result resultType] == NSTextCheckingTypeLink) {
            [string addAttributes:linkAttributes range:[result range]];
        }
		
    }];
	
    if (![self.attributedString isEqualToAttributedString:string]) {
        self.attributedString = string;
    }
}

- (void)scanAttachments {
    __block NSMutableAttributedString *mutableAttributedString = nil;
    
    [_attributedString enumerateAttribute: EGOTextAttachmentAttributeName inRange: NSMakeRange(0, [_attributedString length]) options: 0 usingBlock: ^(id value, NSRange range, BOOL *stop) {
        // we only care when an attachment is set
        if (value != nil) {
            // create the mutable version of the string if it's not already there
            if (mutableAttributedString == nil)
                mutableAttributedString = [_attributedString mutableCopy];
            
            CTRunDelegateCallbacks callbacks = {
                .version = kCTRunDelegateVersion1,
                .dealloc = AttachmentRunDelegateDealloc,
                .getAscent = AttachmentRunDelegateGetDescent,
                //.getDescent = AttachmentRunDelegateGetDescent,
                .getWidth = AttachmentRunDelegateGetWidth
            };
            
            // the retain here is balanced by the release in the Dealloc function
            CTRunDelegateRef runDelegate = CTRunDelegateCreate(&callbacks, (__bridge void *)((__bridge id)CFBridgingRetain(value)));
            [mutableAttributedString addAttribute: (NSString *)kCTRunDelegateAttributeName value: (__bridge id)runDelegate range:range];
            CFRelease(runDelegate);
        }
    }];
    
    if (mutableAttributedString) {
        _attributedString = mutableAttributedString;
    }
}

- (BOOL)selectedLinkAtIndex:(NSInteger)index {
    NSTextCheckingResult *_link = [self linkAtIndex:index];
    if (_link!=nil) {
        [self setLinkRange:[_link range]];
        return YES;
    }
    
    return NO;
}

- (void)openLink:(NSURL*)aURL {
    [[UIApplication sharedApplication] openURL:aURL];
}

#pragma mark - Text Search

- (void)searchSelectedWord {
	if (self.selectedRange.location != NSNotFound) {
		NSString *word = [[_attributedString string] substringWithRange:self.selectedRange];
		[self searchWord:word];
	}
}

- (void)searchWord:(NSString *)word {
	if ([word length] == 0) return;
	
	if (!_searchQueue) {
		_searchQueue = [NSOperationQueue new];
		[_searchQueue setMaxConcurrentOperationCount:1];
	}
	
	NSOperation *searchOperation = [[EGOSearchOperation alloc] initWithDelegate:self searchWord:word inText:[_attributedString string]];
	
	[_searchQueue cancelAllOperations];
	[_searchQueue addOperation:searchOperation];
}

- (void)searchDidComplete:(NSArray *)searchRange {
	[self setSearchRanges:searchRange];
}

- (void)removeSearchAttributesForRange:(NSRange)range {
    NSMutableAttributedString *string = [_attributedString mutableCopy];
    [string removeAttribute:EGOTextSearch range:range];
    self.attributedString = string;
}

#pragma mark - Spell Checking

- (void)insertCorrectionAttributesForRange:(NSRange)range {
    NSMutableAttributedString *string = [_attributedString mutableCopy];
    [string addAttributes:self.correctionAttributes range:range];
    self.attributedString = string;
    
}

- (void)removeCorrectionAttributesForRange:(NSRange)range {
    NSMutableAttributedString *string = [_attributedString mutableCopy];
    [string removeAttribute:EGOTextSpellCheckingColor range:range];
    self.attributedString = string;
}

- (void)checkSpelling {
	if (self.attributedString.length == 0) {
		return;
	}
	[self removeCorrectionAttributesForRange:NSMakeRange(0, self.attributedString.string.length)];
	[self checkSpellingForRange:NSMakeRange(0, self.attributedString.length)];
}

- (void)checkSpellingForRange:(NSRange)range {
    if (self.autocorrectionType == UITextAutocorrectionTypeNo || range.length == 0) {
        return ;
    }
    
    [_mutableAttributedString setAttributedString:self.attributedString];
    
    NSInteger location = range.location-1;
    NSInteger currentOffset = MAX(0, location);
    NSRange currentRange;
    NSString *string = _mutableAttributedString.string;
    NSRange stringRange = NSMakeRange(0, string.length);
    BOOL done = NO;
    
    NSString *language = [[NSLocale currentLocale] localeIdentifier];
    if (![[UITextChecker availableLanguages] containsObject:language]) {
        language = @"en_US";
    }
	
    [_mutableAttributedString removeAttribute:EGOTextSpellCheckingColor range:range];
	
    while (!done) {
        currentRange = [_textChecker rangeOfMisspelledWordInString:string range:stringRange startingAt:currentOffset wrap:NO language:language];
		
        if (currentRange.location == NSNotFound || currentRange.location > range.location + range.length) {
            done = YES;
            continue;
        }
		
		[_mutableAttributedString addAttribute:EGOTextSpellCheckingColor value:[UIColor redColor] range:currentRange];
        
        currentOffset = currentOffset + (currentRange.length-1);
    }
    
    if (![self.attributedString isEqualToAttributedString:_mutableAttributedString]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			self.attributedString = _mutableAttributedString;
		});
    }
}

#pragma mark - Gestures

- (EGOTextWindow *)egoTextWindow {
    if (!_textWindow) {
        
        EGOTextWindow *window = nil;
        
        for (EGOTextWindow *aWindow in [[UIApplication sharedApplication] windows]){
            if ([aWindow isKindOfClass:[EGOTextWindow class]]) {
                window = aWindow;
                window.frame = [[UIScreen mainScreen] bounds];
                break;
            }
        }
        
        if (!window) {
            window = [[EGOTextWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
        }
        
        window.windowLevel = UIWindowLevelStatusBar;
        window.hidden = NO;
        _textWindow = window;
    }
    
    return _textWindow;
}

- (void)longPress:(UILongPressGestureRecognizer*)gesture {
    if (_typingAttributes) {
        _typingAttributes = nil;
    }
    
    if (gesture.state == UIGestureRecognizerStateBegan || gesture.state == UIGestureRecognizerStateChanged) {
        
        if (_linkRange.length>0 && gesture.state == UIGestureRecognizerStateBegan) {
            NSTextCheckingResult *link = [self linkAtIndex:_linkRange.location];
            [self setLinkRangeFromTextCheckerResults:link];
            gesture.enabled=NO;
            gesture.enabled=YES;
        }
        
		
        UIMenuController *menuController = [UIMenuController sharedMenuController];
        if ([menuController isMenuVisible]) {
            [menuController setMenuVisible:NO animated:NO];
        }
        
        CGPoint point = [gesture locationInView:self];
        BOOL _selection = (_selectionView != nil);
		
        if (!_selection && _caretView != nil) {
            [_caretView show];
        }
        
        _textWindow = [self egoTextWindow];
        [_textWindow updateWindowTransform];
        [_textWindow setType:_selection ? EGOWindowMagnify : EGOWindowLoupe];
		
        point.y -= 20.0f;
        NSInteger index = [self closestIndexToPoint:point];
        /*if (index < self.attributedString.length && [self.attributedString.string characterAtIndex:index] == '\n') {
		 index--;
		 }*/
        
        if (_selection) {
            
            if (gesture.state == UIGestureRecognizerStateBegan) {
                _textWindow.selectionType = (index > (_selectedRange.location+(_selectedRange.length/2))) ? EGOSelectionTypeRight : EGOSelectionTypeLeft;
            }
            
            CGRect rect = CGRectZero;
            if (_textWindow.selectionType == EGOSelectionTypeLeft) {
                NSInteger begin = MAX(0, index);
                begin = MIN(_selectedRange.location+_selectedRange.length-1, begin);
                
                NSInteger end = _selectedRange.location + _selectedRange.length;
                end = MIN(_attributedString.string.length, end-begin);
                
                self.selectedRange = NSMakeRange(begin, end);
                index = _selectedRange.location;
            } else {
                NSInteger length = MIN(index-_selectedRange.location, _attributedString.string.length-_selectedRange.location);
                length = MAX(1, length);
                self.selectedRange = NSMakeRange(self.selectedRange.location, length);
                index = (_selectedRange.location+_selectedRange.length);
            }
            
            rect = [self caretRectForIndex:index];
            if (gesture.state == UIGestureRecognizerStateBegan) {
                [_textWindow showFromView:_textContentView rect:[_textContentView convertRect:rect toView:_textWindow]];
            } else {
                [_textWindow renderWithContentView:_textContentView fromRect:[_textContentView convertRect:rect toView:_textWindow]];
            }
        } else {
            [_textWindow updateWindowTransform];
            CGPoint location = [gesture locationInView:_textWindow];
			CGRect rect = CGRectMake(location.x, location.y, _caretView.bounds.size.width, _caretView.bounds.size.height);
            
            self.selectedRange = NSMakeRange(index, 0);
            if (gesture.state == UIGestureRecognizerStateBegan) {
                [_textWindow showFromView:_textContentView rect:rect];
            } else {
                [_textWindow renderWithContentView:_textContentView fromRect:rect];
            }
        }
    } else {
        if (_caretView) {
            [_caretView delayBlink];
        }
        
        if (_textWindow) {
            [_textWindow hide:YES];
            _textWindow = nil;
        }
        
        if (gesture.state == UIGestureRecognizerStateEnded) {
            if (self.correctionRange.location != NSNotFound && self.correctionRange.length > 0) {
                [self insertCorrectionAttributesForRange:self.correctionRange];
                self.correctionRange = NSMakeRange(NSNotFound, 0);
            }
			
            if (self.selectedRange.location != NSNotFound /*&& self.selectedRange.length>0*/) {
                [self showMenu];
            }
        }
    }
}

- (void)doubleTap:(UITapGestureRecognizer*)gesture {
    if (_typingAttributes) {
        _typingAttributes = nil;
    }
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showMenu) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showCorrectionMenu) object:nil];
	
    NSInteger index = [self closestWhiteSpaceIndexToPoint:[gesture locationInView:self]];
    NSRange range = [self characterRangeAtIndex:index];
    if (range.location != NSNotFound && range.length > 0) {
        
        [self.inputDelegate selectionWillChange:self];
        self.selectedRange = range;
        [self.inputDelegate selectionDidChange:self];
		
        if (![[UIMenuController sharedMenuController] isMenuVisible]) {
            [self performSelector:@selector(showMenu) withObject:nil afterDelay:0.1f];
        }
    }
}

- (void)tap:(UITapGestureRecognizer*)gesture {
    if (_typingAttributes) {
        _typingAttributes = nil;
    }
	
    if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextView:tappedAtIndex:)] && ![self.delegate egoTextView:self tappedAtIndex:[self closestIndexToPoint:[gesture locationInView:self]]]) {
        return;
    }
    
    if (_editable && ![self isFirstResponder]) {
        NSInteger index = [self closestWhiteSpaceIndexToPoint:[gesture locationInView:self]];
        
        [self.inputDelegate selectionWillChange:self];
        
        self.markedRange = NSMakeRange(NSNotFound, 0);
        self.selectedRange = NSMakeRange(index, 0);
        
        [self.inputDelegate selectionDidChange:self];
        
        [self becomeFirstResponder];
        return;
    }
	
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showMenu) object:nil];
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showCorrectionMenu) object:nil];
    
    if (self.correctionRange.location != NSNotFound && self.correctionRange.length > 0) {
        [self insertCorrectionAttributesForRange:self.correctionRange];
        self.correctionRange = NSMakeRange(NSNotFound, 0);
    }
    
    if (self.selectedRange.length > 0) {
        self.selectedRange = NSMakeRange(_selectedRange.location, 0);
    }
    
    NSInteger index = [self closestWhiteSpaceIndexToPoint:[gesture locationInView:self]];
    
    if (!_editing && [self selectedLinkAtIndex:index] && self.delegate && [self.delegate respondsToSelector:@selector(egoTextView:didSelectURL:)]) {
		return;
    }
    
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    if ([menuController isMenuVisible]) {
        [menuController setMenuVisible:NO animated:NO];
    } else if (index == self.selectedRange.location) {
		[self performSelector:@selector(showMenu) withObject:nil afterDelay:0.35f];
	} else if (_editing) {
		[self performSelector:@selector(showCorrectionMenu) withObject:nil afterDelay:0.35f];
    }
    
    [self.inputDelegate selectionWillChange:self];
    
    self.markedRange = NSMakeRange(NSNotFound, 0);
    self.selectedRange = NSMakeRange(index, 0);
    
    [self.inputDelegate selectionDidChange:self];
}

#pragma mark - UIGestureRecognizerDelegate

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:NSClassFromString(@"UIScrollViewPanGestureRecognizer")]) {
        UIMenuController *menuController = [UIMenuController sharedMenuController];
        if ([menuController isMenuVisible]) {
            [menuController setMenuVisible:NO animated:NO];
        }
    }
    return NO;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == _longPress) {
        if (_selectedRange.length>0 && _selectionView!=nil) {
            return CGRectContainsPoint(CGRectInset([_textContentView convertRect:_selectionView.frame toView:self], -20.0f, -20.0f) , [gestureRecognizer locationInView:self]);
        }
    }
    
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    if (!_editing && [gestureRecognizer isKindOfClass:[UILongPressGestureRecognizer class]]) {
        return NO;
    } else {
        return (touch.view == self);
    }
}

#pragma mark - UIActionSheetDelegate

- (void)actionSheet:(UIActionSheet *)actionSheet willDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (actionSheet.cancelButtonIndex != buttonIndex) {
        if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChange:)]) {
            [self.delegate egoTextView:self didSelectURL:[NSURL URLWithString:actionSheet.title]];
        } else {
            [self openLink:[NSURL URLWithString:actionSheet.title]];
        }
    } else {
        [self becomeFirstResponder];
    }
    [self setLinkRange:NSMakeRange(NSNotFound, 0)];
}

#pragma mark - UIResponder

- (BOOL)canBecomeFirstResponder {
    if (_editable && self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidBeginEditing:)]) {
        return [self.delegate egoTextViewShouldBeginEditing:self];
    }
    
    return YES;
}

- (BOOL)becomeFirstResponder {
    if (_editable) {
        
        _editing = YES;
		
        if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidBeginEditing:)]) {
            [self.delegate egoTextViewDidBeginEditing:self];
        }
        
        [self selectionChanged];
    }
	
    return [super becomeFirstResponder];
}

- (BOOL)canResignFirstResponder {
    if (_editable && self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewShouldEndEditing:)]) {
        return [self.delegate egoTextViewShouldEndEditing:self];
    }
    
    return YES;
}

- (BOOL)resignFirstResponder {
    if (_editable) {
        
        _editing = NO;
		
        if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewShouldEndEditing:)]) {
            [self.delegate egoTextViewDidEndEditing:self];
        }
        
        self.selectedRange = NSMakeRange(0, 0);
        
    }
    
    if (_typingAttributes) {
        _typingAttributes = nil;
    }
    
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    if ([menuController isMenuVisible]) {
        [menuController setMenuVisible:NO animated:YES];
    }
	
	return [super resignFirstResponder];
}

#pragma mark - UIMenu Presentation

- (CGRect)menuPresentationRect {
    CGRect rect = [_textContentView convertRect:_caretView.frame toView:self];
    if (_selectedRange.location != NSNotFound && _selectedRange.length > 0) {
        if (_selectionView) {
            rect = [_textContentView convertRect:_selectionView.frame toView:self];
        } else {
            rect = [_textContentView convertRect:[self firstRectForNSRange:_selectedRange] toView:self];
        }
    } else if (_editing && _correctionRange.location != NSNotFound && _correctionRange.length > 0) {
        rect = [_textContentView convertRect:[self firstRectForNSRange:_correctionRange] toView:self];
    }
	
    return rect;
}

- (void)showMenu {
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    
    if ([menuController isMenuVisible]) {
        [menuController setMenuVisible:NO animated:NO];
    }
    
	UIMenuItem *searchItem = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"SEARCH", @"Search") action:@selector(searchSelectedWord)];
	UIMenuItem *undoItem = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"UNDO", @"Undo") action:@selector(undo)];
	UIMenuItem *redoItem = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"REDO", @"Redo") action:@selector(redo)];
	UIMenuItem *copyItem = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"COPY", @"Copy") action:@selector(_copy:)];
	UIMenuItem *cutItem  = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"CUT", @"Cut") action:@selector(_cut:)];
	UIMenuItem *pasteItem = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"PASTE", @"Paste") action:@selector(_paste:)];
	UIMenuItem *deleteItem = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"DELETE", @"Delete") action:@selector(_delete:)];
	UIMenuItem *selectItem = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"SELECT", @"Select") action:@selector(_select:)];
	UIMenuItem *selectAllItem = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"SELECT_ALL", @"Select all") action:@selector(_selectAll:)];
	
    dispatch_async(dispatch_get_main_queue(), ^{
        [menuController setMenuItems:@[selectItem, selectAllItem, copyItem, cutItem, pasteItem, deleteItem, searchItem, undoItem, redoItem]];
        [menuController setTargetRect:[self menuPresentationRect] inView:self];
        [menuController update];
        [menuController setMenuVisible:YES animated:YES];
    });
}

- (void)showCorrectionMenu {
    if (_editing) {
        NSRange range = [self characterRangeAtIndex:self.selectedRange.location];
        if (range.location!=NSNotFound && range.length>1) {
            
			NSString *language = [[NSLocale currentLocale] localeIdentifier];
			if (![[UITextChecker availableLanguages] containsObject:language]) {
				language = @"en_US";
			}
            self.correctionRange = [_textChecker rangeOfMisspelledWordInString:_attributedString.string
                                                                         range:range
                                                                    startingAt:0
                                                                          wrap:YES
                                                                      language:language];
        }
    }
}

- (void)showCorrectionMenuWithoutSelection {
    if (_editing) {
        NSRange range = [self characterRangeAtIndex:self.selectedRange.location];
        [self showCorrectionMenuForRange:range];
    } else {
        [self showMenu];
    }
}

- (void)showCorrectionMenuForRange:(NSRange)range {
    if (range.location == NSNotFound || range.length == 0) return;
    
    range.location = MAX(0, range.location);
    range.length = MIN(_attributedString.string.length, range.length);
    
    [self removeCorrectionAttributesForRange:range];
    
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    
    if ([menuController isMenuVisible]) return;
    _ignoreSelectionMenu = YES;
    
	NSString *language = [[NSLocale currentLocale] localeIdentifier];
    if (![[UITextChecker availableLanguages] containsObject:language]) {
        language = @"en_US";
    }
    
    NSArray *guesses = [_textChecker guessesForWordRange:range inString:_attributedString.string language:language];
    
    [menuController setTargetRect:[self menuPresentationRect] inView:self];
    
    if (guesses!=nil && [guesses count]>0) {
        
        NSMutableArray *items = [[NSMutableArray alloc] init];
        
        if (self.menuItemActions==nil) {
            self.menuItemActions = [NSMutableDictionary dictionary];
        }
        
        for (NSString *word in guesses){
            
            NSString *selString = [NSString stringWithFormat:@"spellCheckMenu_%i:", [word hash]];
            SEL sel = sel_registerName([selString UTF8String]);
            
            [self.menuItemActions setObject:word forKey:NSStringFromSelector(sel)];
            class_addMethod([self class], sel, [[self class] instanceMethodForSelector:@selector(spellingCorrection:)], "v@:@");
            
            UIMenuItem *item = [[UIMenuItem alloc] initWithTitle:word action:sel];
            [items addObject:item];
            if ([items count]>=4) {
                break;
            }
        }
        [menuController setMenuItems:items];
    } else {
        UIMenuItem *item = [[UIMenuItem alloc] initWithTitle:EGOLocalizedString(@"NO_REPLACE", @"No replacements found") action:@selector(spellCheckMenuEmpty:)];
        [menuController setMenuItems:[NSArray arrayWithObject:item]];
    }
    [menuController setMenuVisible:YES animated:YES];
}

- (void)showTextStyleMenu {
    UIMenuItem *boldItem = [[UIMenuItem alloc] initWithTitle:@"Bold" action:@selector(toggleBoldface:)];
    UIMenuItem *italicsItem = [[UIMenuItem alloc] initWithTitle:@"Italics" action:@selector(toggleItalics:)];
    UIMenuItem *underlineItem = [[UIMenuItem alloc] initWithTitle:@"Underline" action:@selector(toggleUnderline:)];
    
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    [menuController setMenuItems:@[boldItem, italicsItem, underlineItem]];
    [menuController setTargetRect:[self menuPresentationRect] inView:self];
    [menuController setMenuVisible:YES animated:YES];
}

#pragma mark - UIMenu Actions

- (BOOL)canPerformAction:(SEL)action withSender:(id)sender {
    if (self.correctionRange.length>0 || _ignoreSelectionMenu) {
        if ([NSStringFromSelector(action) hasPrefix:@"spellCheckMenu"]) {
            return YES;
        }
        return NO;
    }
    if (action == @selector(_cut:)) {
        return (_selectedRange.length > 0 && _editing);
    } else if (action == @selector(_copy:)) {
        return (_selectedRange.length > 0);
    } else if ((action == @selector(_select:) || action == @selector(_selectAll:))) {
        return (_selectedRange.length == 0 && [self hasText]);
    } else if (action == @selector(_paste:)) {
        return (_editing && [[UIPasteboard generalPasteboard] containsPasteboardTypes:[NSArray arrayWithObject:(id)kUTTypeText]]);
    } else if (action == @selector(_delete:)) {
        return (_selectedRange.location != NSNotFound && _selectedRange.length > 0);
    } else if (action == @selector(_showTextStyleOptions:)) {
        return NO;//YES;
    } else if (action == @selector(searchSelectedWord)) {
		return (_selectedRange.length > 0);
	} else if (action == @selector(redo)) {
		return (_undoManager && [_undoManager canRedo]);
	} else if (action == @selector(undo)) {
		return (_undoManager && [_undoManager canUndo]);
	}
	
    return [super canPerformAction:action withSender:sender];
}

- (void)spellingCorrection:(UIMenuController *)sender {
    NSRange replacementRange = _correctionRange;
    
    if (replacementRange.location == NSNotFound || replacementRange.length == 0) {
        replacementRange = [self characterRangeAtIndex:self.selectedRange.location];
    }
    if (replacementRange.location != NSNotFound && replacementRange.length != 0) {
        NSString *text = [self.menuItemActions objectForKey:NSStringFromSelector(_cmd)];
        [self.inputDelegate textWillChange:self];
        [self replaceRange:[EGOIndexedRange rangeWithNSRange:replacementRange] withText:text];
        [self.inputDelegate textDidChange:self];
        replacementRange.length = text.length;
        [self removeCorrectionAttributesForRange:replacementRange];
    }
    
    self.correctionRange = NSMakeRange(NSNotFound, 0);
    self.menuItemActions = nil;
    [sender setMenuItems:nil];
}

- (void)spellCheckMenuEmpty:(id)sender {
    self.correctionRange = NSMakeRange(NSNotFound, 0);
}

- (void)menuDidHide:(NSNotification*)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIMenuControllerDidHideMenuNotification object:nil];
    
    if (_selectionView) {
        [self showMenu];
    }
}

- (void)_paste:(id)sender {
    NSString *pasteText = [[UIPasteboard generalPasteboard] valueForPasteboardType:(id)kUTTypeText];
    
    if (pasteText) {
        [self insertText:pasteText];
    }
}

- (void)_selectAll:(id)sender {
    NSString *string = [_attributedString string];
    NSString *trimmedString = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    self.selectedRange = [_attributedString.string rangeOfString:trimmedString];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuDidHide:) name:UIMenuControllerDidHideMenuNotification object:nil];
}

- (void)_select:(id)sender {
    NSRange range = [self characterRangeAtPoint_:_caretView.center];
    self.selectedRange = range;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuDidHide:) name:UIMenuControllerDidHideMenuNotification object:nil];
}

- (void)_cut:(id)sender {
    [self copy:sender];
    [self delete:sender];
}

- (void)_copy:(id)sender {
    NSString *string = [self.attributedString.string substringWithRange:_selectedRange];
    [[UIPasteboard generalPasteboard] setValue:string forPasteboardType:(NSString*)kUTTypeUTF8PlainText];
}

- (void)_delete:(id)sender {
    if (_selectedRange.location != NSNotFound && _selectedRange.length > 0) {
        [_mutableAttributedString setAttributedString:self.attributedString];
        [_mutableAttributedString deleteCharactersInRange:_selectedRange];
        [self.inputDelegate textWillChange:self];
        [self setAttributedString:_mutableAttributedString];
        [self.inputDelegate textDidChange:self];
		
        self.selectedRange = NSMakeRange(_selectedRange.location, 0);
    }
}

- (void)replace:(id)sender {
    NSLog(@"%s", __PRETTY_FUNCTION__);
}

- (void)redo {
	[_undoManager redo];
}

- (void)undo {
	[_undoManager undo];
}

- (void)_showTextStyleOptions:(id)arg {
    [self showTextStyleMenu];
}

- (void)toggleUnderline:(id)arg {
    NSLog(@"%@", arg);
}
- (void)toggleItalics:(id)arg {
    NSLog(@"%@", arg);
}
- (void)toggleBoldface:(id)arg {
    NSLog(@"%@", arg);
}

@end
