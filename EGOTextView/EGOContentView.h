//
//  EGOContentView.h
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

#import <UIKit/UIKit.h>
#import "EGOTextView.h"

@interface EGOContentView : UIView

@property (nonatomic, weak) EGOTextView *textView;

- (void)drawText;

- (NSRange)characterRangeAtIndex:(NSInteger)inIndex;
- (NSRange)characterRangeAtPoint:(CGPoint)point fromView:(UIView *)sourceView;
- (NSInteger)closestIndexToPoint:(CGPoint)point fromView:(UIView *)sourceView;
- (NSInteger)closestWhiteSpaceIndexToPoint:(CGPoint)point fromView:(UIView *)sourceView;
- (CGRect)caretRectForIndex:(NSInteger)inIndex;
- (CGRect)firstRectForNSRange:(NSRange)range;
- (CGRect)lastRectForNSRange:(NSRange)range;
- (CGRect)rectForNSRange:(NSRange)range;
- (NSInteger *)positionFromPosition:(NSInteger)position inDirection:(UITextLayoutDirection)direction offset:(NSInteger)offset;

@end
