//
//  EGOTextLine.m
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

#import "EGOTextLine.h"

@interface EGOTextLine  () {
    CFArrayRef _runsArray;
    CGFloat _ascent, _descent, _leading;
    CTLineRef _rawLine;
    
    BOOL _didCalculateMetrics;
}

@property (nonatomic, strong) NSLock *lock;

@end

@implementation EGOTextLine

- (id)initWithCTLine:(CTLineRef)line {
    self = [super init];
    if (self) {
        _lock = [[NSLock alloc] init];
        
        self.rawLine = line;
    }
    
    return self;
}

#pragma mark - Property

- (void)setRawLine:(CTLineRef)rawLine {
    if (_rawLine) {
        CFRelease(_rawLine);
    }
    
    _rawLine = CFRetain(rawLine);
    
    _didCalculateMetrics = NO;
    
    if (_runsArray) {
        CFRelease(_runsArray);
        _runsArray = NULL;
    }
}

- (NSArray *)runsArray {
    if (!_runsArray && _rawLine) {
        if (_runsArray) {
            CFRelease(_runsArray);
        }
        _runsArray = CFRetain(CTLineGetGlyphRuns(_rawLine));
    }
    
    return (__bridge NSArray *)_runsArray;
}

- (CGFloat)ascent {
    if (!_didCalculateMetrics) {
        [self calculateMetrics];
    }
    
    return _ascent;
}

- (CGFloat)descent {
    if (!_didCalculateMetrics) {
        [self calculateMetrics];
    }
    
    return _descent;
}

- (CGFloat)leading {
    if (!_didCalculateMetrics) {
        [self calculateMetrics];
    }
    
    return _leading;
}

#pragma mark - Methods

- (void)calculateMetrics {
    [_lock lock];
    
    if (!_didCalculateMetrics) {
        CTLineGetTypographicBounds(_rawLine, &_ascent, &_descent, &_leading);
        
        _didCalculateMetrics = YES;
    }
    
    [_lock unlock];
}

- (NSString *)description {
    return [NSString stringWithFormat:@"[%i] Origin: %@ Ascent: %f Descent: %f Leading: %f", _index, NSStringFromCGPoint(_origin), _ascent, _descent, _leading];
}

#pragma mark - Dealloc

- (void)dealloc {
    if (_runsArray) {
        CFRelease(_runsArray);
        _runsArray = NULL;
    }
    
    if (_rawLine) {
        CFRelease(_rawLine);
        _rawLine = NULL;
    }
}

@end
