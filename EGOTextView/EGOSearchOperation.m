//
//  EGOSearchOperation.m
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

#import "EGOSearchOperation.h"
#import "EGOTextView.h"
#import "EGOIndexedRange.h"

@interface EGOSearchOperation ()

@property (nonatomic, weak) id<EGOSearchDelegate> delegate;
@property (nonatomic, strong) NSString *searchWord;
@property (nonatomic, copy)   NSString *searchText;

@end

@implementation EGOSearchOperation

- (id)initWithDelegate:(id<EGOSearchDelegate>)delegate searchWord:(NSString *)word inText:(NSString *)text {
	self = [super init];
	if (self) {
		_delegate = delegate;
		_searchWord = word;
		_searchText = text;
	}
	return self;
}

- (void)main {
	@autoreleasepool {
		NSMutableArray *searchRanges = [[NSMutableArray alloc] initWithCapacity:1];
		
		NSString *pattern = [NSString stringWithFormat:@"(%@)", [_searchWord stringByReplacingOccurrencesOfString:@" " withString:@"\\s"]];
		NSRegularExpression *regularExpression = [NSRegularExpression regularExpressionWithPattern:pattern
																						   options:NSRegularExpressionCaseInsensitive
																							 error:NULL];
		[regularExpression enumerateMatchesInString:_searchText
											options:NSMatchingReportProgress
											  range:NSMakeRange(0, _searchText.length)
										 usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
											 if (result.range.location != NSNotFound && result.range.length > 0) {
												 [searchRanges addObject:[EGOIndexedRange rangeWithNSRange:result.range]];
											 }
											 if (self.isCancelled) {
												 *stop = YES;
											 }
										 }];
		
		if (self.isCancelled) {
			return;
		} else if (_delegate) {
			[_delegate searchDidComplete:[searchRanges copy]];
		}
	}
}

@end
