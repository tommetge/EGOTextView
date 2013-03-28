//
//  EGOTextView.h
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

#import <UIKit/UIKit.h>
#import <CoreText/CoreText.h>
#import <UIKit/UITextChecker.h>

#import "EGOCaretView.h"
#import "EGOContentView.h"
#import "EGOTextWindow.h"
#import "EGOSelectionView.h"
#import "EGOMagnifyView.h"
#import "EGOIndexedPosition.h"
#import "EGOIndexedRange.h"
#import "EGOSearchOperation.h"

#include <objc/runtime.h>

extern NSString * const EGOTextSearch;
extern NSString * const EGOTextSpellCheckingColor;
extern NSString * const EGOTextAttachmentAttributeName;
extern NSString * const EGOTextAttachmentPlaceholderString;

@class EGOTextView;

@protocol EGOTextViewDelegate <NSObject, UIScrollViewDelegate>
@optional

- (BOOL)egoTextViewShouldBeginEditing:(EGOTextView *)textView;
- (BOOL)egoTextViewShouldEndEditing:(EGOTextView *)textView;

- (void)egoTextViewDidBeginEditing:(EGOTextView *)textView;
- (void)egoTextViewDidEndEditing:(EGOTextView *)textView;

- (void)egoTextViewDidChange:(EGOTextView *)textView;

- (void)egoTextViewDidChangeSelection:(EGOTextView *)textView;

- (void)egoTextView:(EGOTextView *)textView didSelectURL:(NSURL*)URL;

- (BOOL)egoTextView:(EGOTextView *)textView tappedAtIndex:(NSInteger)index;

@end

@protocol EGOTextViewDrawDelegate;
@protocol EGOTextAttachmentCell;

@interface EGOTextView : UIScrollView <UITextInputTraits, UITextInput, EGOContentViewDelegate, EGOSearchDelegate> {
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
    
}

@property (nonatomic) UIDataDetectorTypes dataDetectorTypes; // UIDataDetectorTypeLink supported
@property (nonatomic) UITextAutocapitalizationType autocapitalizationType;
@property (nonatomic) UITextSpellCheckingType spellCheckingType;
@property (nonatomic) UITextAutocorrectionType autocorrectionType;
@property (nonatomic) UIKeyboardType keyboardType;
@property (nonatomic) UIKeyboardAppearance keyboardAppearance;
@property (nonatomic) UIReturnKeyType returnKeyType;
@property (nonatomic) BOOL enablesReturnKeyAutomatically;

@property (nonatomic, strong) NSDictionary *defaultAttributes;
@property (nonatomic, copy)   NSDictionary *typingAttributes;

@property (nonatomic, readonly) NSUndoManager *undoManager;

@property (nonatomic, weak) id <EGOTextViewDelegate> delegate;
@property (nonatomic, weak) id <EGOTextViewDrawDelegate> drawDelegate;
@property (nonatomic, copy) NSAttributedString *attributedText;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font; // ignored when attributedString is not nil
@property (nonatomic, getter = isEditable) BOOL editable; //default YES
@property (nonatomic, readonly) BOOL hasText;
@property (nonatomic, readonly) CGRect contentFrame;
@property (nonatomic) NSRange selectedRange;
@property (nonatomic) NSRange markedRange;

- (void)checkSpelling;
- (void)scrollToTextRange:(NSRange)range;
- (void)searchWord:(NSString *)word;
+ (UIColor *)selectionColor;
+ (UIColor *)spellingSelectionColor;
+ (UIColor *)caretColor;

@end

@protocol EGOTextViewDrawDelegate

- (void)egoTextView:(EGOTextView *)textView drawBeforeGlyphRun:(CTRunRef)glyphRun forLine:(CTLineRef)line withOrigin:(CGPoint)origin inContext:(CGContextRef)context;
- (void)egoTextView:(EGOTextView *)textView drawAfterGlyphRun:(CTRunRef)glyphRun forLine:(CTLineRef)line withOrigin:(CGPoint)origin inContext:(CGContextRef)context;

@end

@protocol EGOTextAttachmentCell <NSObject>
@optional

// the attachment must either implement -attachmentView or both -attachmentSize and -attachmentDrawInRect:
- (UIView *)attachmentView;

- (CGSize) attachmentSize;
- (void) attachmentDrawInRect: (CGRect)r;

@end