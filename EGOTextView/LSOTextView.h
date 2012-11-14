//
//  LSSTextView.h
//  EGOTextView_Demo
//
//  Created by Chris Brauchli on 11/13/12.
//
//

#import <Foundation/Foundation.h>
#import "EGOTextView.h"


extern NSString * const kLSOStrikeOutAttributeName;
extern NSString * const kLSOBackgroundFillColorAttributeName;
extern NSString * const kLSOBackgroundStrokeColorAttributeName;
extern NSString * const kLSOBackgroundLineWidthAttributeName;
extern NSString * const kLSOBackgroundCornerRadiusAttributeName;

extern NSString* const kLSOTaggedObjectTagAttributeName;
extern NSString* const kLSOTaggedObjectNameAttributeName;

@interface LSOTextView : EGOTextView

@end

// Static methods
static inline NSDictionary* LSPeopleHighlightAttributes()
{
    static NSDictionary *dic = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dic = [NSDictionary dictionaryWithObjectsAndKeys:
               (id)[UIColor colorWithWhite:1.f alpha:1.f].CGColor, (NSString*)kCTForegroundColorAttributeName,
               (id)[UIColor colorWithRed:0.769 green:0.58 blue:0.529 alpha:0.85f].CGColor, kLSOBackgroundFillColorAttributeName,
               (id)[NSNumber numberWithFloat:5.f], kLSOBackgroundCornerRadiusAttributeName,
               nil];
    });
    return dic;
}

static inline NSDictionary* LSVenueHighlightAttributes()
{
    static NSDictionary *dic = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dic = [NSDictionary dictionaryWithObjectsAndKeys:
               (id)[UIColor colorWithWhite:1.f alpha:1.f].CGColor, (NSString*)kCTForegroundColorAttributeName,
               (id)[UIColor colorWithRed:0.435f green:0.655f blue:0.737f alpha:.75f].CGColor, kLSOBackgroundFillColorAttributeName,
               (id)[NSNumber numberWithFloat:5.f], kLSOBackgroundCornerRadiusAttributeName,
               nil];
    });
    return dic;
}
