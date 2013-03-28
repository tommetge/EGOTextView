//
//  EGOIndexedPosition.m
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import "EGOIndexedPosition.h"

@implementation EGOIndexedPosition

+ (EGOIndexedPosition *)positionWithIndex:(NSUInteger)inIndex {
    EGOIndexedPosition *pos = [[EGOIndexedPosition alloc] init];
    pos.positionIndex = inIndex;
    return pos;
}

@end
