//
//  CBCache.h
//  CBCache
//
//  Created by Chris on 4/27/13.
//  Copyright (c) 2013 Chris Beauchamp. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

enum {
    CBCacheStatusInMemoryCache,
    CBCacheStatusInFileCache,
    CBCacheStatusNotCached
};
typedef NSUInteger CBCacheStatus;

typedef void (^CBCacheCompletionBlock)(CBCacheStatus status, NSData *data, NSError *error);

@interface CBCache : NSObject

@property (nonatomic, strong) NSString *cacheName;

+ (CBCache*)cacheWithName:(NSString*)name;

- (void) retrieveFile:(NSURL*)fileURL withCompletion:(CBCacheCompletionBlock)complete;

@end
