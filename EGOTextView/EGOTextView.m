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
#import "EGOTextView+Protected.h"
#import <QuartzCore/QuartzCore.h>
#import <MobileCoreServices/UTCoreTypes.h>
#import "EGOCaretView.h"
#import "EGOTextWindow.h"
#import "EGOSelectionView.h"
#import "EGOMagnifyView.h"
#import "EGOIndexedPosition.h"
#import "EGOIndexedRange.h"
#import "EGOContentView.h"

#include <objc/runtime.h>

NSString * const EGOTextSpellCheckingColor = @"com.enormego.EGOTextSpellCheckingColor";

NSString * const EGOTextAttachmentAttributeName = @"com.enormego.EGOTextAttachmentAttribute";
NSString * const EGOTextAttachmentPlaceholderString = @"\uFFFC";

NSString * const EGOTextViewLocalizationTable = @"EGOTextView";

#define EGOLocalizedString(_key, _value) [_localizationBundle localizedStringForKey:(_key) value:(_value) table:EGOTextViewLocalizationTable]

#pragma mark - Text attachment helper functions

static void AttachmentRunDelegateDealloc(void *refCon) {
	CFBridgingRelease(refCon);
}

static CGSize AttachmentRunDelegateGetSize(void *refCon) {
    id <EGOTextAttachmentCell> cell = (__bridge id<EGOTextAttachmentCell>)(refCon);
    if ([cell respondsToSelector:@selector(egoAttachmentSize)]) {
        return [cell egoAttachmentSize];
    } else {
        return [[cell egoAttachmentView] frame].size;
    }
}

static CGFloat AttachmentRunDelegateGetDescent(void *refCon) {
    return AttachmentRunDelegateGetSize(refCon).height;
}

static CGFloat AttachmentRunDelegateGetWidth(void *refCon) {
    return AttachmentRunDelegateGetSize(refCon).width;
}

#pragma mark - EGOTextView private

@interface EGOTextView () {
@private
    NSMutableAttributedString    *_attributedString;
    NSMutableSet                 *_correctionRanges;
    
    NSDictionary                 *_markedTextStyle;
    UITextInputStringTokenizer   *_tokenizer;
    UITextChecker                *_textChecker;
    UILongPressGestureRecognizer *_longPress;
    
    BOOL _ignoreSelectionMenu;
    
    UIFont              *_font;
    BOOL                _editing;
    BOOL                _editable;
    
    EGOContentView      *_textContentView;
    EGOTextWindow       *_textWindow;
    EGOCaretView        *_caretView;
    EGOSelectionView    *_selectionView;
    
	NSBundle			*_localizationBundle;
}

@property (nonatomic, strong) NSMutableDictionary *menuItemActions;
@property (nonatomic, strong) NSOperationQueue *searchQueue;
@property (nonatomic, assign) dispatch_queue_t correctionQueue;
@property (nonatomic, assign) dispatch_queue_t textQueue;

@end


@implementation EGOTextView

@dynamic delegate;
@synthesize typingAttributes = _typingAttributes;
@synthesize markedTextStyle = _markedTextStyle;
@synthesize inputDelegate = _inputDelegate;
@synthesize undoManager = _undoManager;
@synthesize dataDetectorTypes;
@synthesize autocapitalizationType;
@synthesize spellCheckingType = _spellCheckingType;
@synthesize autocorrectionType = _autocorrectionType;
@synthesize keyboardType;
@synthesize keyboardAppearance;
@synthesize returnKeyType;
@synthesize enablesReturnKeyAutomatically;

#pragma mark - Common

- (void)commonInit {
    _textContentView = [[EGOContentView alloc] initWithFrame:self.bounds];
    [_textContentView setAutoresizingMask:self.autoresizingMask];
    [_textContentView setTextView:self];
    [self addSubview:_textContentView];
    
    _undoManager = [[NSUndoManager alloc] init];
    _correctionRanges = [[NSMutableSet alloc] init];
    _selectedRange = NSMakeRange(NSNotFound, 0);
    
    [self setAlwaysBounceVertical:YES];
    [self setEditable:YES];
	[self setLanguage:nil];
    [self setFont:[UIFont systemFontOfSize:17]];
    [self setBackgroundColor:[UIColor whiteColor]];
    [self setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
    [self setClipsToBounds:YES];
    [self setAutocapitalizationType:UITextAutocapitalizationTypeSentences];
    [self setText:@""];
    	
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
	
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardWillHideNotification object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UIKeyboardDidShowNotification object:nil];
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
	[[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (dispatch_queue_t)textQueue {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _textQueue = dispatch_queue_create("com.enormego.EGOTextViewTextQueue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_queue_set_specific(_textQueue, self.textQueueSpecific, (__bridge void *)self, NULL);
    });
    
    return _textQueue;
}

- (const char *)textQueueSpecific {
    static const char *kEGOTextQueueSpecific = "EGOTextQueueSpecific";
    return kEGOTextQueueSpecific;
}

- (dispatch_queue_t)correctionQueue {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _correctionQueue = dispatch_queue_create("com.enormego.EGOTextViewCorrectionQueue", DISPATCH_QUEUE_CONCURRENT);
        dispatch_queue_set_specific(_correctionQueue, self.correctionQueueSpecific, (__bridge void *)self, NULL);
    });
    
    return _correctionQueue;
}

- (const char *)correctionQueueSpecific {
    static const char *kEGOCorrectionQueueSpecific = "EGOCorrectionQueueSpecific";
    return kEGOCorrectionQueueSpecific;
}

- (NSString *)text {
    __block NSString *text;
    if (dispatch_get_specific(self.textQueueSpecific)) {
        text = [_attributedString string];
    } else {
        dispatch_sync(self.textQueue, ^{
            text = [_attributedString string];
        });
    }
    return text;
}

- (NSUInteger)textLength {
    __block NSUInteger length;
    if (dispatch_get_specific(self.textQueueSpecific)) {
        length = [_attributedString length];
    } else {
        dispatch_sync(self.textQueue, ^{
            length = [_attributedString length];
        });
    }
    return length;
}

- (void)setFont:(UIFont *)font {
    _font = font;
    
    CTFontRef ctFont = CTFontCreateWithName((__bridge CFStringRef) self.font.fontName, self.font.pointSize, NULL);
    NSDictionary *dictionary = [[NSDictionary alloc] initWithObjectsAndKeys:
                                (__bridge id)ctFont, (NSString *)kCTFontAttributeName,
                                (id)[UIColor blackColor].CGColor, (NSString *)kCTForegroundColorAttributeName, nil];
    self.defaultAttributes = dictionary;
    CFRelease(ctFont);
}

- (void)setText:(NSString *)text {
    NSAttributedString *string = [[NSAttributedString alloc] initWithString:text attributes:self.defaultAttributes];
    [self setAttributedText:string];
}

- (void)setAttributedText:(NSAttributedString *)attributedText {	
	[_undoManager removeAllActions];
    
    BOOL isEditing = (_editing && self.selectedRange.location != NSNotFound);
    
	if (self.searchRanges && [self.searchRanges count] > 0) {
		self.searchRanges = nil;
	}
    dispatch_barrier_sync(self.correctionQueue, ^{
        [_correctionRanges removeAllObjects];
    });
    [self setAttributedString:[[NSMutableAttributedString alloc] initWithAttributedString:attributedText]];
	[self checkSpelling];
    
    if (isEditing) {
        [self selectionChanged];
    }
}

- (NSAttributedString *)attributedText {
    __block NSAttributedString *attributedText;
    if (dispatch_get_specific(self.textQueueSpecific)) {
        attributedText = [_attributedString copy];
    } else {
        dispatch_sync(self.textQueue, ^{
            attributedText = [_attributedString copy];
        });
    }
    
	return attributedText;
}

- (void)setAttributedString:(NSMutableAttributedString *)attributedString {
    [self.inputDelegate textWillChange:self];
    dispatch_block_t block = ^{
        _attributedString = attributedString;
        [self updateText];
        dispatch_async(dispatch_get_main_queue(), ^{
            [_textContentView setNeedsDisplay];
        });
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.textQueue, block);
    }
    [self.inputDelegate textDidChange:self];
    if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChange:)]) {
        [self.delegate egoTextViewDidChange:self];
    }
}

- (NSMutableAttributedString *)attributedString {
    __block NSMutableAttributedString *attributedString;
    if (dispatch_get_specific(self.textQueueSpecific)) {
        attributedString = _attributedString;
    } else {
        dispatch_sync(self.textQueue, ^{
            attributedString = _attributedString;
        });
    }
    
    return attributedString;
}

- (NSMutableSet *)correctionRanges {
    __block NSMutableSet *correctionRanges;
    if (dispatch_get_specific(self.correctionQueueSpecific)) {
        correctionRanges = _correctionRanges;
    } else {
        dispatch_sync(self.correctionQueue, ^{
            correctionRanges = _correctionRanges;
        });
    }
    
    return correctionRanges;
}

- (void)updateText {
    if (self.searchRanges && [self.searchRanges count] > 0) {
        self.searchRanges = nil;
    }
        
    NSUInteger length = [_attributedString length];
    NSRange range = NSMakeRange(0, length);
    if (!_editing && !_editable) {
        if (self.dataDetectorTypes & UIDataDetectorTypeLink) {
            [self checkLinksForRange:range];
        }
        [self scanAttachments];
    }
    
    if (self.selectedRange.location == NSNotFound || self.selectedRange.location > length) {
        self.selectedRange = NSMakeRange(length, 0);
    }
    
    if ([[UIMenuController sharedMenuController] isMenuVisible]) {
        [[UIMenuController sharedMenuController] setMenuVisible:NO animated:NO];
    }
    
    [_textContentView drawText];
}

- (void)setEditable:(BOOL)editable {
    if (editable) {
        if (!_caretView) {
            _caretView = [[EGOCaretView alloc] initWithFrame:CGRectZero];
        }
        
        _tokenizer = [[UITextInputStringTokenizer alloc] initWithTextInput:self];
        _textChecker = [[UITextChecker alloc] init];
        
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
    }
    _editable = editable;
}

- (void)setSpellCheckingType:(UITextSpellCheckingType)spellCheckingType {
    if (_spellCheckingType == UITextSpellCheckingTypeYes && spellCheckingType == UITextSpellCheckingTypeNo) {
        [self removeCorrectionAttributesForRange:NSMakeRange(0, _attributedString.length)];
        dispatch_async(dispatch_get_main_queue(), ^{
            [_textContentView setNeedsDisplay];
        });
	}
	
	UITextSpellCheckingType oldSpellCheckingType = _spellCheckingType;
	_spellCheckingType = spellCheckingType;
	
	if (oldSpellCheckingType == UITextSpellCheckingTypeNo && _spellCheckingType == UITextSpellCheckingTypeYes) {
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

- (void)scrollToTextRange:(NSRange)range {
    CGRect rect = [_textContentView caretRectForIndex:range.location];
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
	frame.size.height += (self.font.lineHeight*2);
	if (!(_selectedRange.location == 0 && _selectedRange.length == 0)) {
		[self scrollRectToVisible:frame animated:YES];
	}
}

- (void)keyboardWillHide:(NSNotification *)notification {
    [self setContentInset:UIEdgeInsetsZero];
    [self setScrollIndicatorInsets:[self contentInset]];
}

#pragma mark - Text Selection

- (void)selectionChanged {
    if (!_editing && _caretView) {
        [_caretView removeFromSuperview];
    }
    
    _ignoreSelectionMenu = NO;
    
    if (self.selectedRange.location == NSNotFound) {
        if (_selectionView) {
            [_selectionView removeFromSuperview];
            _selectionView = nil;
        }
        
        if (_caretView && _caretView.superview) {
            [_caretView removeFromSuperview];
        }
    } else if (self.selectedRange.length == 0) {
        if (_selectionView) {
            [_selectionView removeFromSuperview];
            _selectionView = nil;
        }
        
        if (_editing && !_caretView.superview) {
            [_textContentView addSubview:_caretView];
        }
        
        [_caretView setFrame:[_textContentView caretRectForIndex:self.selectedRange.location]];
        [_caretView delayBlink];
        
        CGRect frame = _caretView.frame;
        frame.size.height += (self.font.lineHeight*2);
        if (!(_selectedRange.location == 0 && _selectedRange.length == 0)) {
            [self scrollRectToVisible:frame animated:YES];
        }
        
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
        
        CGRect begin = [_textContentView caretRectForIndex:_selectedRange.location];
        CGRect end   = [_textContentView caretRectForIndex:_selectedRange.location+_selectedRange.length];
        [_selectionView setBeginCaret:begin endCaret:end];
    }
    
    if (self.markedRange.location != NSNotFound) {
        //[_textContentView setNeedsDisplay];
    }
	
	if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChangeSelection:)]) {
		[self.delegate egoTextViewDidChangeSelection:self];
	}
}

- (void)setMarkedRange:(NSRange)range {
    if (NSEqualRanges(_markedRange, range)) {
        return;
    }
    _markedRange = range;
    //[self selectionChanged];
}

- (void)setSelectedRange:(NSRange)range {
    if (NSEqualRanges(_selectedRange, range)) {
        return;
    }
	_selectedRange = NSMakeRange(range.location == NSNotFound ? NSNotFound : MAX(0, range.location), range.length);
    [self selectionChanged];
}

- (void)setCorrectionRange:(NSRange)range {
    if (NSEqualRanges(_correctionRange, range)) {
        return;
    }
    
    if (_correctionRange.location != NSNotFound) {
        CGRect rangeRect = [_textContentView rectForNSRange:_correctionRange];
        dispatch_async(dispatch_get_main_queue(), ^{
            [_textContentView setNeedsDisplayInRect:rangeRect];
        });
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
	
    CGRect rangeRect = [_textContentView rectForNSRange:range];
	dispatch_async(dispatch_get_main_queue(), ^{
		[_textContentView setNeedsDisplayInRect:rangeRect];
	});
}

- (void)setSearchRanges:(NSArray *)searchRanges {
    if (!searchRanges) {
        searchRanges = [NSArray array];
    }
    
    if (![_searchRanges isEqualToArray:searchRanges]) {
        _searchRanges = [searchRanges copy];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [_textContentView setNeedsDisplay];
        });
    }
}

- (void)setLinkRange:(NSRange)range {
    _linkRange = range;
    
    if (_linkRange.length>0) {
        if (_caretView.superview) {
            [_caretView removeFromSuperview];
        }
    } else if (!_caretView.superview) {
		[_textContentView addSubview:_caretView];
		_caretView.frame = [_textContentView caretRectForIndex:self.selectedRange.location];
		[_caretView delayBlink];
    }
    
    CGRect rangeRect = [_textContentView rectForNSRange:range];
	dispatch_async(dispatch_get_main_queue(), ^{
		[_textContentView setNeedsDisplayInRect:rangeRect];
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
    static UIColor *color;
	static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [UIColor colorWithRed:0.f green:0.35f blue:0.65f alpha:0.2f];
    });
    return color;
}

+ (UIColor *)caretColor {
	static UIColor *color;
	static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [UIColor colorWithRed:0.259f green:0.420f blue:0.949f alpha:1.0f];
    });
    return color;
}

+ (UIColor *)spellingSelectionColor {
	static UIColor *color;
	static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        color = [UIColor colorWithRed:1.f green:0.f blue:0.f alpha:0.149f];
    });
    return color;
}

#pragma mark - UITextInput - Replacing and Returning Text

- (NSString *)textInRange:(UITextRange *)range {
    EGOIndexedRange *r = (EGOIndexedRange *)range;
    __block NSString *text;
    dispatch_block_t block = ^{
        text = [[_attributedString string] substringWithRange:NSMakeRange(r.range.location, MIN(r.range.length, _attributedString.length - r.range.location))];
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.textQueue, block);
    }
    return text;
}

- (void)replaceRange:(UITextRange *)range withText:(NSString *)text {
    EGOIndexedRange *r = (EGOIndexedRange *)range;
    
    [self.inputDelegate textWillChange:self];
    dispatch_block_t block = ^{
        [_attributedString replaceCharactersInRange:r.range withString:text];
        [self updateText];
        dispatch_barrier_sync(self.correctionQueue, ^{
            for (EGOIndexedRange *range in [_correctionRanges allObjects]) {
                if (NSIntersectionRange(range.range, r.range).length != 0) {
                    [_correctionRanges removeObject:range];
                } else if (range.range.location >= r.range.location + r.range.length) {
                    [range setRange:NSMakeRange(range.range.location - r.range.length + text.length, range.range.length)];
                }
            }
        });
        [self checkSpellingForRange:NSMakeRange(r.range.location, text.length)];
        CGRect rangeRect = [_textContentView rectForNSRange:r.range];
        rangeRect.origin.x = 0.0f;
        rangeRect.size.width = _textContentView.frame.size.width;
        rangeRect.size.height = _textContentView.frame.size.height - rangeRect.origin.y;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_textContentView setNeedsDisplayInRect:rangeRect];
        });
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.textQueue, block);
    }
    self.selectedRange = NSMakeRange(r.range.location + text.length, 0);
    [self.inputDelegate textDidChange:self];
    if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChange:)]) {
        [self.delegate egoTextViewDidChange:self];
    }
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
    if (!markedText) {
        markedText = @"";
    }
        
    if (self.markedRange.location != NSNotFound) {
        NSMutableAttributedString *attributedSubstring = [[NSMutableAttributedString alloc] initWithAttributedString:[self.attributedString attributedSubstringFromRange:self.markedRange]];
        [attributedSubstring replaceCharactersInRange:NSMakeRange(0, self.markedRange.length) withString:markedText];
        [self replaceString:[attributedSubstring copy] inRange:self.markedRange];
        
        self.markedRange = NSMakeRange(self.markedRange.location, markedText.length);
    } else if (self.selectedRange.length > 0) {
        NSUInteger markedLocation = self.selectedRange.location;
        NSMutableAttributedString *attributedSubstring = [[NSMutableAttributedString alloc] initWithAttributedString:[self.attributedString attributedSubstringFromRange:self.selectedRange]];
        [attributedSubstring replaceCharactersInRange:NSMakeRange(0, self.selectedRange.length) withString:markedText];
        [self replaceString:[attributedSubstring copy] inRange:self.selectedRange];
        
        self.markedRange = NSMakeRange(markedLocation, markedText.length);
    } else {
        NSUInteger markedLocation = self.selectedRange.location;
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:markedText attributes:self.defaultAttributes];
        [self insertString:string atIndex:self.selectedRange.location];
        
        self.markedRange = NSMakeRange(markedLocation, markedText.length);
    }
}

- (void)unmarkText {
    if (self.markedRange.location == NSNotFound) return;
    
    self.markedRange = NSMakeRange(NSNotFound, 0);
}

#pragma mark - UITextInput - Computing Text Ranges and Text Positions

- (UITextPosition *)beginningOfDocument {
    return [EGOIndexedPosition positionWithIndex:0];
}

- (UITextPosition *)endOfDocument {
    return [EGOIndexedPosition positionWithIndex:self.textLength];
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
	
    if (end < 0 || end > self.textLength) return nil;
    
    return [EGOIndexedPosition positionWithIndex:end];
}

- (UITextPosition *)positionFromPosition:(UITextPosition *)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset {
    EGOIndexedPosition *pos = (EGOIndexedPosition *)position;
    NSInteger newPos = [_textContentView positionFromPosition:pos.positionIndex inDirection:direction offset:offset];
    NSUInteger length = self.textLength;
    newPos = (newPos == NSNotFound ? length : MAX(MIN(newPos, length), 0));
    
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
    CGRect rect = [_textContentView firstRectForNSRange:r.range];
    return rect;
}

- (CGRect)caretRectForPosition:(UITextPosition *)position {
    EGOIndexedPosition *pos = (EGOIndexedPosition *)position;
	CGRect rect = [_textContentView caretRectForIndex:pos.positionIndex];
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
    EGOIndexedPosition *position = [EGOIndexedPosition positionWithIndex:[_textContentView closestIndexToPoint:point fromView:self]];
    return position;
}

- (UITextPosition *)closestPositionToPoint:(CGPoint)point withinRange:(UITextRange *)range {
    EGOIndexedPosition *position = [EGOIndexedPosition positionWithIndex:[_textContentView closestIndexToPoint:point fromView:self]];
    return position;
}

- (UITextRange *)characterRangeAtPoint:(CGPoint)point {
    EGOIndexedRange *range = [EGOIndexedRange rangeWithNSRange:[_textContentView characterRangeAtPoint:point fromView:self]];
    return range;
}

#pragma mark - UITextInput - Styling Information

- (NSDictionary *)textStylingAtPosition:(UITextPosition *)position inDirection:(UITextStorageDirection)direction {
    if (!position) {
        return nil;
    }
    
    EGOIndexedPosition *pos = (EGOIndexedPosition*)position;
    __block NSDictionary *ctStyles;
    dispatch_block_t block = ^{
        NSUInteger stylePosition = pos.positionIndex;
        if (_selectedRange.location != NSNotFound || (_selectedRange.length == 0 && _selectedRange.location == stylePosition)) {
            ctStyles = self.typingAttributes;
        } else if (direction == UITextStorageDirectionBackward && stylePosition > 0) {
            ctStyles = [_attributedString attributesAtIndex:stylePosition-1 effectiveRange:NULL];
        } else {
            // If the selection encompasses the end of the text with forwards affinity
            if (stylePosition >= [_attributedString length]) {
                stylePosition--;
            }
            ctStyles = [_attributedString attributesAtIndex:stylePosition effectiveRange:NULL];
        }
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.textQueue, block);
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
    return (self.textLength != 0);
}

- (void)insertText:(NSString *)text {
    if (!text || [text length] == 0) return;
    
    NSMutableDictionary *attributes = nil;
    if (self.textLength > 0) {
        attributes = [[NSMutableDictionary alloc] initWithDictionary:self.typingAttributes];
    }
    
    NSAttributedString *newString = [[NSAttributedString alloc] initWithString:text
                                                                    attributes:(attributes ? attributes : self.defaultAttributes)];
    
    if (_correctionRange.location != NSNotFound && _correctionRange.length > 0){
        [self replaceString:newString inRange:self.correctionRange];
        
        self.correctionRange = NSMakeRange(NSNotFound, 0);
    } else if (self.markedRange.location != NSNotFound) {
        [self replaceString:newString inRange:self.markedRange];
        
        self.markedRange = NSMakeRange(NSNotFound, 0);
    } else if (self.selectedRange.length > 0) {
        [self replaceString:newString inRange:self.selectedRange];
    } else {
        [self insertString:newString atIndex:self.selectedRange.location];
    }
    	
    if (text.length > 1 || [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[text characterAtIndex:0]]) {
        [self checkLinksForRange:NSMakeRange(0, self.textLength)];
    }
}

- (void)deleteBackward {
	static NSCharacterSet *characterSet;
	static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
		NSMutableCharacterSet *mutableCharacterSet = [[NSMutableCharacterSet alloc] init];
        [mutableCharacterSet formUnionWithCharacterSet:[NSCharacterSet punctuationCharacterSet]];
		[mutableCharacterSet formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		characterSet = [mutableCharacterSet copy];
    });
    NSCharacterSet *whitespaceSet = [NSCharacterSet whitespaceCharacterSet];
	
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(showCorrectionMenuWithoutSelection) object:nil];
    
    NSString *text = self.text;
    
    if (self.correctionRange.location != NSNotFound && self.correctionRange.length > 0) {
		if ((_correctionRange.location == 0 || [whitespaceSet characterIsMember:[text characterAtIndex:_correctionRange.location-1]]) && (_correctionRange.location+_correctionRange.length >= text.length || [characterSet characterIsMember:[text characterAtIndex:_correctionRange.location+_correctionRange.length]])) {
			_correctionRange.location = MAX(0, _correctionRange.location-1);
			_correctionRange.length   = MIN(text.length, _correctionRange.length+1);
		}
		
		[self deleteCharactersInRange:self.correctionRange];
        
        self.correctionRange = NSMakeRange(NSNotFound, 0);
    } else if (self.markedRange.location != NSNotFound) {
		[self deleteCharactersInRange:self.markedRange];
        
        self.markedRange = NSMakeRange(NSNotFound, 0);
    } else if (self.selectedRange.length > 0 && self.selectedRange.location != NSNotFound) {
		if ((_selectedRange.location == 0 || [whitespaceSet characterIsMember:[text characterAtIndex:MIN(text.length, _selectedRange.location-1)]]) &&
			(_selectedRange.location+_selectedRange.length == text.length || [characterSet characterIsMember:[text characterAtIndex:_selectedRange.location+_selectedRange.length]])) {
			_selectedRange.location = (_selectedRange.location == 0 ? 0 : _selectedRange.location-1);
			_selectedRange.length   = MIN(text.length, _selectedRange.length+1);
		}
		
		[self deleteCharactersInRange:_selectedRange];
    } else if (self.selectedRange.location > 0) {
        NSInteger index = MAX(0, MIN(text.length, self.selectedRange.location)-1);
        if ([whitespaceSet characterIsMember:[text characterAtIndex:index]]) {
            [self performSelector:@selector(showCorrectionMenuWithoutSelection) withObject:nil afterDelay:0.2f];
        }
        		
		[self deleteCharactersInRange:[text rangeOfComposedCharacterSequenceAtIndex:self.selectedRange.location - 1]];
    }
}

- (void)replaceString:(NSAttributedString *)text inRange:(NSRange)range {
    if (range.location == NSNotFound || range.location+range.length > self.textLength) {
        return;
    }

    [self.inputDelegate textWillChange:self];
    dispatch_block_t block = ^{
        CGRect rangeRect = CGRectNull;
        if (range.length > text.length) {
            rangeRect = [_textContentView rectForNSRange:range];
        }
        [[_undoManager prepareWithInvocationTarget:self] replaceString:[_attributedString attributedSubstringFromRange:range]
                                                               inRange:NSMakeRange(range.location, text.length)];
        [_attributedString replaceCharactersInRange:range withAttributedString:text];
        [self updateText];
        dispatch_barrier_sync(self.correctionQueue, ^{
            for (EGOIndexedRange *r in [_correctionRanges allObjects]) {
                if (NSIntersectionRange(range, r.range).length != 0) {
                    [_correctionRanges removeObject:r];
                } else if (r.range.location >= range.location + range.length) {
                    [r setRange:NSMakeRange(r.range.location - range.length + text.length, r.range.length)];
                }
            }
        });
        [self checkSpellingForRange:NSMakeRange(range.location, text.length)];
        if (CGRectIsNull(rangeRect)) {
            rangeRect = [_textContentView rectForNSRange:NSMakeRange(range.location, text.length)];
        }
        rangeRect.origin.x = 0.0f;
        rangeRect.size.width = _textContentView.frame.size.width;
        rangeRect.size.height = _textContentView.frame.size.height - rangeRect.origin.y;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_textContentView setNeedsDisplayInRect:rangeRect];
        });
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.textQueue, block);
    }
    self.selectedRange = NSMakeRange(range.location + text.length, 0);
    [self.inputDelegate textDidChange:self];
    if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChange:)]) {
        [self.delegate egoTextViewDidChange:self];
    }
}

- (void)insertString:(NSAttributedString *)text atIndex:(NSUInteger)loc {
    if (loc == NSNotFound || loc > self.textLength || text.length == 0) {
        return;
    }
    
    dispatch_block_t block = ^{
        [[_undoManager prepareWithInvocationTarget:self] deleteCharactersInRange:NSMakeRange(loc, text.length)];
        [_attributedString insertAttributedString:text atIndex:loc];
        [self updateText];
        dispatch_barrier_sync(self.correctionQueue, ^{
            for (EGOIndexedRange *r in [_correctionRanges allObjects]) {
                if (r.range.location >= loc) {
                    [r setRange:NSMakeRange(r.range.location + text.length, r.range.length)];
                } else if (r.range.location + r.range.length >= loc) {
                    [_correctionRanges removeObject:r];
                }
            }
        });
        if (text.length > 1 || (text.length == 1 && [[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[text.string characterAtIndex:0]])) {
            if (text.length == 1) {
                [self checkSpellingForRange:[_textContentView characterRangeAtIndex:loc-1]];
            } else {
                [self checkSpellingForRange:NSMakeRange(loc, text.length)];
            }
        }
        CGRect rangeRect = [_textContentView rectForNSRange:NSMakeRange(loc, text.length)];
        rangeRect.origin.x = 0.0f;
        rangeRect.size.width = _textContentView.frame.size.width;
        rangeRect.size.height = _textContentView.frame.size.height - rangeRect.origin.y;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_textContentView setNeedsDisplayInRect:rangeRect];
        });
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.textQueue, block);
    }
    self.selectedRange = NSMakeRange(loc + text.length, 0);
    if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChange:)]) {
        [self.delegate egoTextViewDidChange:self];
    }
}

- (void)deleteCharactersInRange:(NSRange)range {
    if (range.location == NSNotFound || range.location+range.length > self.textLength) {
        return;
    }
    
    [self.inputDelegate textWillChange:self];
    dispatch_block_t block = ^{
        CGRect rangeRect = [_textContentView rectForNSRange:range];
        [(EGOTextView *)[_undoManager prepareWithInvocationTarget:self] insertString:[_attributedString attributedSubstringFromRange:range]
                                                                             atIndex:range.location];
        [_attributedString deleteCharactersInRange:range];
        [self updateText];
        dispatch_barrier_sync(self.correctionQueue, ^{
            for (EGOIndexedRange *r in [_correctionRanges allObjects]) {
                if (NSIntersectionRange(range, r.range).length != 0) {
                    [_correctionRanges removeObject:r];
                } else if (r.range.location >= range.location + range.length) {
                    [r setRange:NSMakeRange(r.range.location - range.length, r.range.length)];
                }
            }
        });
        rangeRect.origin.x = 0.0f;
        rangeRect.size.width = _textContentView.frame.size.width;
        rangeRect.size.height = _textContentView.frame.size.height - rangeRect.origin.y;
        dispatch_async(dispatch_get_main_queue(), ^{
            [_textContentView setNeedsDisplayInRect:rangeRect];
        });
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.textQueue, block);
    }
    self.selectedRange = NSMakeRange(range.location, 0);
    [self.inputDelegate textDidChange:self];
    if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidChange:)]) {
        [self.delegate egoTextViewDidChange:self];
    }
}

- (NSDictionary *)typingAttributes {
    if (_typingAttributes) {
        return _typingAttributes;
    }
    
    dispatch_block_t block = ^{
        NSUInteger contentLength = [_attributedString length];
        if (contentLength == 0) {
            _typingAttributes = nil;
            return;
        }
        
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
        _typingAttributes = [_attributedString attributesAtIndex:(insertAt > 0 ? insertAt-1 : 0) effectiveRange:NULL];
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.textQueue, block);
    }

    return _typingAttributes;
}

- (void)setTypingAttributes:(NSDictionary *)typingAttributes {
    if ([_typingAttributes isEqualToDictionary:typingAttributes]) return;
    
    _typingAttributes = [typingAttributes copy];
}

#pragma mark - Data Detectors (links)

- (NSTextCheckingResult *)linkAtIndex:(NSInteger)index {
    NSRange range = [_textContentView characterRangeAtIndex:index];
    if (range.location == NSNotFound || range.length == 0) {
        return nil;
    }
    
    __block NSTextCheckingResult *link = nil;
    NSError *error = nil;
    NSDataDetector *linkDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
    dispatch_block_t block =^{
        [linkDetector enumerateMatchesInString:[_attributedString string] options:0 range:range usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            
            if ([result resultType] == NSTextCheckingTypeLink) {
                *stop = YES;
                link = result;
            }
        }];
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.textQueue, block);
    }
	
    return link;
}

- (void)checkLinksForRange:(NSRange)range {
    if (!(self.dataDetectorTypes & UIDataDetectorTypeLink)) {
        return;
    }
    NSDictionary *linkAttributes = [NSDictionary dictionaryWithObjectsAndKeys:(id)[UIColor blueColor].CGColor, kCTForegroundColorAttributeName, [NSNumber numberWithInt:(int)kCTUnderlineStyleSingle], kCTUnderlineStyleAttributeName, nil];
    
    NSError *error = nil;
	NSDataDetector *linkDetector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeLink error:&error];
    dispatch_block_t block = ^{
        [linkDetector enumerateMatchesInString:_attributedString.string
                                       options:0
                                         range:range
                                    usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
                                        if ([result resultType] == NSTextCheckingTypeLink) {
                                            [_attributedString addAttributes:linkAttributes range:[result range]];
                                        }
                                    }];
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.textQueue, block);
    }
}

- (void)scanAttachments {
    dispatch_block_t block = ^{
        [_attributedString enumerateAttribute:EGOTextAttachmentAttributeName inRange:NSMakeRange(0, [_attributedString length]) options:0 usingBlock: ^(id value, NSRange range, BOOL *stop) {
            if (value) {
                CTRunDelegateCallbacks callbacks = {
                    .version = kCTRunDelegateVersion1,
                    .dealloc = AttachmentRunDelegateDealloc,
                    .getAscent = AttachmentRunDelegateGetDescent,
                    //.getDescent = AttachmentRunDelegateGetDescent,
                    .getWidth = AttachmentRunDelegateGetWidth
                };
                
                CTRunDelegateRef runDelegate = CTRunDelegateCreate(&callbacks, (__bridge void *)((__bridge id)CFBridgingRetain(value)));
                [_attributedString addAttribute:(NSString *)kCTRunDelegateAttributeName value: (__bridge id)runDelegate range:range];
                CFRelease(runDelegate);
            }
        }];
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_sync(self.textQueue, block);
    }
}

- (BOOL)selectedLinkAtIndex:(NSInteger)index {
    NSTextCheckingResult *link = [self linkAtIndex:index];
    if (link) {
        [self setLinkRange:[link range]];
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
		[self searchWord:[self.text substringWithRange:self.selectedRange]];
	}
}

- (void)searchWord:(NSString *)word {
	if ([word length] == 0) return;
	
	if (!_searchQueue) {
		_searchQueue = [NSOperationQueue new];
		[_searchQueue setMaxConcurrentOperationCount:1];
	}
	
	NSOperation *searchOperation = [[EGOSearchOperation alloc] initWithDelegate:self
                                                                     searchWord:word
                                                                         inText:self.text];
	
	[_searchQueue cancelAllOperations];
	[_searchQueue addOperation:searchOperation];
}

- (void)searchDidComplete:(NSArray *)searchRange {
	[self setSearchRanges:searchRange];
}

#pragma mark - Spell Checking

- (void)insertCorrectionAttributesForRange:(NSRange)range {
    dispatch_block_t addAttributes = ^ {
        [_correctionRanges addObject:[EGOIndexedRange rangeWithNSRange:range]];
    };
    if (dispatch_get_specific(self.correctionQueueSpecific)) {
        addAttributes();
    } else {
        dispatch_barrier_sync(self.correctionQueue, addAttributes);
    }
}

- (void)removeCorrectionAttributesForRange:(NSRange)range {
    dispatch_block_t removeAttributes = ^ {
        for (EGOIndexedRange *r in [_correctionRanges allObjects]) {
            if (NSIntersectionRange(r.range, range).length != 0) {
                [_correctionRanges removeObject:r];
            }
        }
    };
    if (dispatch_get_specific(self.correctionQueueSpecific)) {
        removeAttributes();
    } else {
        dispatch_barrier_sync(self.correctionQueue, removeAttributes);
    }
}

- (void)checkSpelling {
    if (self.textLength == 0) {
        return;
    }
    [self removeCorrectionAttributesForRange:NSMakeRange(0, _attributedString.length)];
	[self checkSpellingForRange:NSMakeRange(0, self.textLength)];
}

- (void)checkSpellingForRange:(NSRange)range {
    if (self.spellCheckingType == UITextSpellCheckingTypeNo || range.location == NSNotFound || range.length == 0 || range.length == NSNotFound) {
        return ;
    }

    __block BOOL  needsDisplay = NO;
    NSString *string = self.text;
    NSCharacterSet *characterSet = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSRange startRange = [_textContentView characterRangeAtIndex:range.location +
                          ([characterSet characterIsMember:[string characterAtIndex:range.location]] ? 1 : 0)];
    NSRange endRange = [_textContentView characterRangeAtIndex:range.location + range.length - 1];
    range = NSUnionRange(startRange, endRange);
    dispatch_block_t block = ^{
        NSInteger location = range.location-1;
        NSInteger currentOffset = MAX(0, location);
        NSRange currentRange;
        BOOL done = NO;
        
        NSString *language = [[NSLocale currentLocale] localeIdentifier];
        if (![[UITextChecker availableLanguages] containsObject:language]) {
            language = @"en_US";
        }
                
        NSMutableSet *corrections = [[NSMutableSet alloc] init];
        [_correctionRanges enumerateObjectsUsingBlock:^(id obj, BOOL *stop) {
            if (NSIntersectionRange(range, ((EGOIndexedRange *)obj).range).length != 0) {
                [corrections addObject:obj];
            }
        }];
        [_correctionRanges minusSet:corrections];
        
        while (!done) {
            currentRange = [_textChecker rangeOfMisspelledWordInString:string range:range startingAt:currentOffset wrap:NO language:language];
            
            if (currentRange.location == NSNotFound || currentRange.location > range.location + range.length) {
                done = YES;
                continue;
            }
            
            if (!needsDisplay) {
                if ([corrections containsObject:[EGOIndexedRange rangeWithNSRange:currentRange]]) {
                    [corrections removeObject:[EGOIndexedRange rangeWithNSRange:currentRange]];
                } else {
                    needsDisplay = YES;
                }
            }
            [_correctionRanges addObject:[EGOIndexedRange rangeWithNSRange:currentRange]];
            
            currentOffset = currentOffset + (currentRange.length-1);
        }
        
        if (!needsDisplay && [corrections count] > 0) {
            needsDisplay = YES;
        }
        
        if (needsDisplay) {
            dispatch_async(dispatch_get_main_queue(), ^{
                CGRect updateFrame = [_textContentView rectForNSRange:range];
                [_textContentView setNeedsDisplayInRect:updateFrame];
            });
        }
    };
    if (dispatch_get_specific(self.correctionQueueSpecific)) {
        block();
    } else {
        dispatch_barrier_async(self.correctionQueue, block);
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
		
        if (!_selection && _caretView) {
            [_caretView show];
        }
        
        _textWindow = [self egoTextWindow];
        [_textWindow updateWindowTransform];
        [_textWindow setType:_selection ? EGOWindowMagnify : EGOWindowLoupe];
		
        point.y -= 20.0f;
        NSInteger index = [_textContentView closestIndexToPoint:point fromView:self];
        
        if (_selection) {
            if (gesture.state == UIGestureRecognizerStateBegan) {
                _textWindow.selectionType = (index > (_selectedRange.location+(_selectedRange.length/2))) ? EGOSelectionTypeRight : EGOSelectionTypeLeft;
            }
            
            CGRect rect = CGRectZero;
            if (_textWindow.selectionType == EGOSelectionTypeLeft) {
                NSInteger begin = MAX(0, index);
                begin = MIN(_selectedRange.location+_selectedRange.length-1, begin);
                
                NSInteger end = _selectedRange.location + _selectedRange.length;
                end = MIN(self.textLength, end-begin);
                
                self.selectedRange = NSMakeRange(begin, end);
                index = _selectedRange.location;
            } else {
                NSInteger length = MAX(1, MIN(index-_selectedRange.location, self.textLength-_selectedRange.location));
                if (length > 1 && [[NSCharacterSet newlineCharacterSet] characterIsMember:[self.text characterAtIndex:_selectedRange.location + length - 1]]) {
                    length -= 1;
                }
                self.selectedRange = NSMakeRange(self.selectedRange.location, length);
                index = (_selectedRange.location+_selectedRange.length);
            }
            
            rect = [_textContentView caretRectForIndex:index];
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
	
    NSInteger index = [_textContentView closestWhiteSpaceIndexToPoint:[gesture locationInView:self] fromView:self];
    NSRange range = [_textContentView characterRangeAtIndex:index];
    if (range.location != NSNotFound && range.length > 0) {
        [self.inputDelegate selectionWillChange:self];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:[self.text characterAtIndex:range.location + range.length - 1]]) {
            range.length -= 1;
        }
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
	
    if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextView:tappedAtIndex:)] && ![self.delegate egoTextView:self tappedAtIndex:[_textContentView closestIndexToPoint:[gesture locationInView:self] fromView:self]]) {
        return;
    }
    
    if (_editable && ![self isFirstResponder]) {
        NSInteger index = [_textContentView closestWhiteSpaceIndexToPoint:[gesture locationInView:self] fromView:self];
        
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
    } else if (self.selectedRange.location != NSNotFound) {
		[self checkSpellingForRange:[_textContentView characterRangeAtIndex:self.selectedRange.location]];
	}
    
    NSInteger index = [_textContentView closestWhiteSpaceIndexToPoint:[gesture locationInView:self] fromView:self];
    
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
    if (_editable && self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewShouldBeginEditing:)]) {
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
        
		if (self.correctionRange.location != NSNotFound && self.correctionRange.length > 0) {
            [self insertCorrectionAttributesForRange:self.correctionRange];
			self.correctionRange = NSMakeRange(NSNotFound, 0);
		}
        
        self.selectedRange = NSMakeRange(NSNotFound, 0);
        
        if (self.delegate && [self.delegate respondsToSelector:@selector(egoTextViewDidEndEditing:)]) {
            [self.delegate egoTextViewDidEndEditing:self];
        }
    }
    
    if (_typingAttributes) {
        _typingAttributes = nil;
    }
    
    if (_caretView) {
        [_caretView removeFromSuperview];
    }
    
    if (_selectionView) {
        [_selectionView removeFromSuperview];
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
            rect = [_textContentView convertRect:[_textContentView firstRectForNSRange:_selectedRange] toView:self];
        }
    } else if (_editing && _correctionRange.location != NSNotFound && _correctionRange.length > 0) {
        rect = [_textContentView convertRect:[_textContentView firstRectForNSRange:_correctionRange] toView:self];
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
    if (_editing && self.spellCheckingType != UITextSpellCheckingTypeNo) {
        NSRange range = [_textContentView characterRangeAtIndex:self.selectedRange.location];
        if (range.location != NSNotFound && range.length > 1) {
			NSString *language = [[NSLocale currentLocale] localeIdentifier];
			if (![[UITextChecker availableLanguages] containsObject:language]) {
				language = @"en_US";
			}
            self.correctionRange = [_textChecker rangeOfMisspelledWordInString:self.text
                                                                         range:range
                                                                    startingAt:0
                                                                          wrap:YES
                                                                      language:language];
        }
    }
}

- (void)showCorrectionMenuWithoutSelection {
    if (_editing) {
        NSRange range = [_textContentView characterRangeAtIndex:self.selectedRange.location];
        [self showCorrectionMenuForRange:range];
    } else {
        [self showMenu];
    }
}

- (void)showCorrectionMenuForRange:(NSRange)range {
    if (range.location == NSNotFound || range.length == 0 || self.spellCheckingType == UITextSpellCheckingTypeNo) return;
    
    range.location = MAX(0, range.location);
    range.length = MIN(self.text.length, range.length);
    
    [self removeCorrectionAttributesForRange:range];
    
    UIMenuController *menuController = [UIMenuController sharedMenuController];
    
    if ([menuController isMenuVisible]) return;
    _ignoreSelectionMenu = YES;
    
	NSString *language = [[NSLocale currentLocale] localeIdentifier];
    if (![[UITextChecker availableLanguages] containsObject:language]) {
        language = @"en_US";
    }
    
    NSArray *guesses = [_textChecker guessesForWordRange:range inString:self.text language:language];
    
    [menuController setTargetRect:[self menuPresentationRect] inView:self];
    
    if (guesses && [guesses count]>0) {
        NSMutableArray *items = [[NSMutableArray alloc] init];
        
        if (!self.menuItemActions) {
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
        replacementRange = [_textContentView characterRangeAtIndex:self.selectedRange.location];
    }
    if (replacementRange.location != NSNotFound && replacementRange.length != 0) {
        NSString *text = [self.menuItemActions objectForKey:NSStringFromSelector(_cmd)];
        [self replaceRange:[EGOIndexedRange rangeWithNSRange:replacementRange] withText:text];
    }
    
    self.correctionRange = NSMakeRange(NSNotFound, 0);
    self.menuItemActions = nil;
    [sender setMenuItems:nil];
}

- (void)spellCheckMenuEmpty:(id)sender {
    if (self.correctionRange.location != NSNotFound) {
        [self insertCorrectionAttributesForRange:self.correctionRange];
    }
    self.correctionRange = NSMakeRange(NSNotFound, 0);
}

- (void)menuDidHide:(NSNotification *)notification {
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
    __block NSRange trimRange;
    dispatch_block_t block = ^{
        NSString *trimmedString = [_attributedString.string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        trimRange = [_attributedString.string rangeOfString:trimmedString];
    };
    if (dispatch_get_specific(self.textQueueSpecific)) {
        block();
    } else {
        dispatch_sync(self.textQueue, block);
    }
    self.selectedRange = trimRange;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuDidHide:) name:UIMenuControllerDidHideMenuNotification object:nil];
}

- (void)_select:(id)sender {
    NSRange range = [_textContentView characterRangeAtPoint:_caretView.center fromView:_caretView.superview];
    self.selectedRange = range;
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(menuDidHide:) name:UIMenuControllerDidHideMenuNotification object:nil];
}

- (void)_cut:(id)sender {
    [self _copy:sender];
    [self _delete:sender];
}

- (void)_copy:(id)sender {
    [[UIPasteboard generalPasteboard] setValue:[self.text substringWithRange:_selectedRange] forPasteboardType:(NSString *)kUTTypeUTF8PlainText];
}

- (void)_delete:(id)sender {
    if (_selectedRange.location != NSNotFound && _selectedRange.length > 0) {
        [self deleteCharactersInRange:_selectedRange];
    }
}

- (void)replace:(id)sender {
    //NSLog(@"%s", __PRETTY_FUNCTION__);
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
    //NSLog(@"%@", arg);
}
- (void)toggleItalics:(id)arg {
    //NSLog(@"%@", arg);
}
- (void)toggleBoldface:(id)arg {
    //NSLog(@"%@", arg);
}

@end
