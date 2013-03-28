//
//  EGOIndexedRange.h
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import <UIKit/UIKit.h>

@interface EGOIndexedRange : UITextRange {
    NSRange _range;
}

@property (nonatomic) NSRange range;

+ (EGOIndexedRange *)rangeWithNSRange:(NSRange)range;

@end
