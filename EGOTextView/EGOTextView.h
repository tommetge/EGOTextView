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
#import "EGOSearchOperation.h"

extern NSString * const EGOTextSearch;
extern NSString * const EGOTextSpellCheckingColor;
extern NSString * const EGOTextAttachmentAttributeName;
extern NSString * const EGOTextAttachmentPlaceholderString;
extern NSString * const EGOTextViewLocalizationTable;

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

@interface EGOTextView : UIScrollView <UITextInputTraits, UITextInput, EGOSearchDelegate>

@property (nonatomic, assign) UIDataDetectorTypes dataDetectorTypes; // UIDataDetectorTypeLink supported
@property (nonatomic, assign) UITextAutocapitalizationType autocapitalizationType;
@property (nonatomic, assign) UITextSpellCheckingType spellCheckingType;
@property (nonatomic, assign) UITextAutocorrectionType autocorrectionType;
@property (nonatomic, assign) UIKeyboardType keyboardType;
@property (nonatomic, assign) UIKeyboardAppearance keyboardAppearance;
@property (nonatomic, assign) UIReturnKeyType returnKeyType;
@property (nonatomic, assign) BOOL enablesReturnKeyAutomatically;

@property (nonatomic, strong) NSDictionary *localizedStrings;

@property (nonatomic, strong) NSDictionary *defaultAttributes;
@property (nonatomic, copy)   NSDictionary *typingAttributes;

@property (nonatomic, strong, readonly) NSUndoManager *undoManager;

@property (nonatomic, weak) id <EGOTextViewDelegate> delegate;
@property (nonatomic, weak) id <EGOTextViewDrawDelegate> drawDelegate;
@property (nonatomic, copy) NSAttributedString *attributedText;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) UIFont *font; // ignored when attributedString is not nil
@property (nonatomic, assign, getter = isEditable) BOOL editable; //default YES
@property (nonatomic, assign, readonly) BOOL hasText;
@property (nonatomic, assign, readonly) CGRect contentFrame;
@property (nonatomic, assign) NSRange selectedRange;
@property (nonatomic, assign) NSRange markedRange;

@property (nonatomic, strong) NSString *language;

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

- (CGSize)attachmentSize;
- (void)attachmentDrawInRect:(CGRect)r;

@end