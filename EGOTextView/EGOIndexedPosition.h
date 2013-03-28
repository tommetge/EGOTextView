//
//  EGOIndexedPosition.h
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 29/11/12.
//
//

#import <UIKit/UIKit.h>

@interface EGOIndexedPosition : UITextPosition {
    NSUInteger               _positionIndex;
    id <UITextInputDelegate> _inputDelegate;
}

@property (nonatomic) NSUInteger positionIndex;

+ (EGOIndexedPosition *)positionWithIndex:(NSUInteger)index;

@end
