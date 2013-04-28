//
//  CBCache.m
//  CBCache
//
//  Created by Chris on 4/27/13.
//  Copyright (c) 2013 Chris Beauchamp. All rights reserved.
//

#import "CBCache.h"

#import "NSString+CBExtensions.h"

@interface CBCache() {
    NSString *_cacheName;
    dispatch_queue_t _cacheQueue;
    NSOperationQueue *_cacheDownloadQueue;
    
    unsigned long long _memoryCacheSize;
    NSMutableDictionary *_memoryCache;
}

@end

@implementation CBCache

@synthesize cacheName = _cacheName;

- (CBCache*)initWithName:(NSString*)name
{
    self = [super init];
    
    if(self) {
        _cacheName = name;
        
        NSString *cacheQueueName = [NSString stringWithFormat:@"com.cbcache.cachequeue.%@", _cacheName];
        _cacheQueue = dispatch_queue_create([cacheQueueName UTF8String], NULL);
        
        _cacheDownloadQueue = [[NSOperationQueue alloc] init];
    }
    
    return self;
}

+ (CBCache*)cacheWithName:(NSString*)name
{
    return [[CBCache alloc] initWithName:name];
}

- (NSString*)getLocalFilePath:(NSURL*)fromURL
{
    NSString *filename = [fromURL.absoluteString md5];
    
    NSArray *myPathList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *myPath = [myPathList objectAtIndex:0];
    myPath = [myPath stringByAppendingPathComponent:_cacheName];
    
    // make this directory if it doesn't exist yet
    [[NSFileManager defaultManager] createDirectoryAtPath:myPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];
    
    myPath = [myPath stringByAppendingPathComponent:filename];
    
    NSLog(@"Created path %@ from url %@", myPath, fromURL.absoluteString);
    
    return myPath;
}

- (UIImage*) getImageFromFileCache:(NSURL*)url
{
    UIImage *image = nil;
    NSString *myPath = [self getLocalFilePath:url];
    
    if([[NSFileManager defaultManager] fileExistsAtPath:myPath]) {
        image = [UIImage imageWithContentsOfFile:myPath];
    }

    return image;
}

- (void) writeImage:(NSData*)imageData toFileCache:(NSURL*)fileURL
{
    NSString *myPath = [self getLocalFilePath:fileURL];
    [imageData writeToFile:myPath atomically:TRUE];
    
    // TODO: clean this up if it's over capacity
}

- (void) retrieveFile:(NSURL*)fileURL withCompletion:(CBCacheCompletionBlock)complete
{
    
    // break out into another thread -- specific to this cache
    dispatch_async(_cacheQueue, ^(void) {
        
        // see if it's in the memory cache
        __block UIImage *memoryImage = [_memoryCache objectForKey:fileURL.absoluteString];
        if(memoryImage != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                complete(CBCacheStatusInMemoryCache, memoryImage, nil);
                
                // TODO: bump this to the top of the memory cache
            });
        } else {
            
            // if not, see if it's in the file cache
            __block UIImage *fileImage = [self getImageFromFileCache:fileURL];
            if(fileImage != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    complete(CBCacheStatusInFileCache, fileImage, nil);
                    
                    // TODO: put this in the top of the memory cache
                    
                });
            } else {

                // if not, download from url
                NSURLRequest *request = [NSURLRequest requestWithURL:fileURL];
                [NSURLConnection sendAsynchronousRequest:request
                                                   queue:_cacheDownloadQueue
                                       completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                           
                                           __block UIImage *img = nil;
                                           
                                           if(error == nil) {
                                               img = [UIImage imageWithData:data];
                                               
                                               // TODO: store this in the memory cache which
                                               // should clean up/update the memory cache
                                               
                                               // save to file cache
                                               [self writeImage:data toFileCache:response.URL];
                                           }
                                           
                                           // make the callback on the main thread
                                           dispatch_async(dispatch_get_main_queue(), ^{
                                               complete(CBCacheStatusNotCached, img, error);
                                           });
                                           
                                       }];

            }

        }
        
        
        
        // TODO: in any case, update the last retrieved time in the data store
        // make sure this is done on main thread
        
    });
    
}

@end
