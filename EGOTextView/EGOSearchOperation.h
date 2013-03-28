//
//  EGOSearchOperation.h
//  EGOTextView_Demo
//
//  Created by Tommaso Madonia on 05/02/13.
//
//

#import <Foundation/Foundation.h>

@protocol EGOSearchDelegate <NSObject>

- (void)searchDidComplete:(NSArray *)searchRange;

@end

@interface EGOSearchOperation : NSOperation

- (id)initWithDelegate:(id<EGOSearchDelegate>)delegate searchWord:(NSString *)word inText:(NSString *)text;

@end
