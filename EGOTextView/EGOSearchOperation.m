//
//  EGOSearchOperation.m
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 05/02/13.
//
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
