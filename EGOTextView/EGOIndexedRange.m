//
//  EGOIndexedRange.m
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import "EGOIndexedRange.h"
#import "EGOIndexedPosition.h"

@implementation EGOIndexedRange

+ (EGOIndexedRange *)rangeWithNSRange:(NSRange)theRange {
    if (theRange.location == NSNotFound) return nil;
    
    EGOIndexedRange *range = [[EGOIndexedRange alloc] init];
    range.range = theRange;
    return range;
}

- (UITextPosition *)start {
    return [EGOIndexedPosition positionWithIndex:self.range.location];
}

- (UITextPosition *)end {
	return [EGOIndexedPosition positionWithIndex:(self.range.location + self.range.length)];
}

-(BOOL)isEmpty {
    return (self.range.length == 0);
}

@end
