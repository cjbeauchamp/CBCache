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

- (unsigned long long) cacheDirectorySpaceUsed
{
    unsigned long long totalSpace = 0;
    
    __autoreleasing NSError *error = nil;
    NSString *myPath = [self getCacheFilePath];
    
    // get the contents of our directory
    for(NSString *filename in [[NSFileManager defaultManager] contentsOfDirectoryAtPath:myPath error:&error]) {
        
        if([filename length] > 0) {
            if([[filename substringToIndex:1] isEqualToString:@"."]) continue;

            NSString *path = [myPath stringByAppendingPathComponent:filename];
            
            NSDictionary *dict = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:&error];
            
            if(dict != nil) {
                NSNumber *fileSize = [dict objectForKey:NSFileSize];
                totalSpace += fileSize.longLongValue;
            }

        }
        
    }
    
    return totalSpace;
}

- (unsigned long long) freeDiskSpace
{
    unsigned long long totalSpace = 0;
    unsigned long long totalFreeSpace = 0;
    
    __autoreleasing NSError *error = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSDictionary *dictionary = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[paths lastObject] error: &error];
    
    if (dictionary) {
        NSNumber *fileSystemSizeInBytes = [dictionary objectForKey: NSFileSystemSize];
        NSNumber *freeFileSystemSizeInBytes = [dictionary objectForKey:NSFileSystemFreeSize];
        totalSpace = [fileSystemSizeInBytes unsignedLongLongValue];
        totalFreeSpace = [freeFileSystemSizeInBytes unsignedLongLongValue];
        NSLog(@"Memory Capacity of %llu MiB with %llu MiB Free memory available.", ((totalSpace/1024ll)/1024ll), ((totalFreeSpace/1024ll)/1024ll));
    } else {
        NSLog(@"Error Obtaining System Memory Info: Domain = %@, Code = %d", [error domain], [error code]);
    }

    long long totalUsed = [self cacheDirectorySpaceUsed];
    NSLog(@"TOTALUSED: %lld", totalUsed);
    
    return totalFreeSpace;
}

- (CBCache*)initWithName:(NSString*)name
{
    self = [super init];
    
    if(self) {
        _cacheName = name;
        
        NSString *cacheQueueName = [NSString stringWithFormat:@"com.cbcache.cachequeue.%@", _cacheName];
        _cacheQueue = dispatch_queue_create([cacheQueueName UTF8String], NULL);
        
        _cacheDownloadQueue = [[NSOperationQueue alloc] init];
//        _cacheDownloadQueue.maxConcurrentOperationCount = 10;
        
        [self freeDiskSpace];
    }
    
    return self;
}

+ (CBCache*)cacheWithName:(NSString*)name
{
    return [[CBCache alloc] initWithName:name];
}

- (NSString*) getCacheFilePath
{
    NSArray *myPathList = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *myPath = [myPathList objectAtIndex:0];
    myPath = [myPath stringByAppendingPathComponent:_cacheName];
    
    // make this directory if it doesn't exist yet
    [[NSFileManager defaultManager] createDirectoryAtPath:myPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:nil];

    return myPath;
}

- (NSString*)getLocalFilePath:(NSURL*)fromURL
{
    NSString *filename = [fromURL.absoluteString md5];
    
    NSString *myPath = [self getCacheFilePath];
    myPath = [myPath stringByAppendingPathComponent:filename];
    
    return myPath;
}

- (NSData*) getDataFromFileCache:(NSURL*)url
{
    NSData *data = nil;
    NSString *myPath = [self getLocalFilePath:url];
    
    NSLog(@"Data from file: %@", myPath);
    
    if([[NSFileManager defaultManager] fileExistsAtPath:myPath]) {
        data = [NSData dataWithContentsOfFile:myPath];
    }

    return data;
}

- (void) writeDataToFileCache:(NSData*)data usingURL:(NSURL*)fileURL
{
    NSString *myPath = [self getLocalFilePath:fileURL];
    [data writeToFile:myPath atomically:TRUE];
    
    // TODO: clean this up if it's over capacity
}

- (BOOL) writeData:(NSData*)data
           toFile:(NSString*)filename {
    NSString *myPath = [self getLocalFilePath:[NSURL URLWithString:filename]];
    return [data writeToFile:myPath atomically:TRUE];
}

- (NSData*) dataFromFile:(NSString*)filename {
    return [self getDataFromFileCache:[NSURL URLWithString:filename]];
}

- (void) retrieveFile:(NSURL*)fileURL withCompletion:(CBCacheCompletionBlock)complete
{
    
    NSLog(@"Retrieved file: %@", fileURL);
    
    // break out into another thread -- specific to this cache
    // TODO: Allow separate threads for each url... how many is max efficiency?
    dispatch_async(_cacheQueue, ^(void) {
        
        // see if it's in the memory cache
        __block NSData *memoryData = [_memoryCache objectForKey:fileURL.absoluteString];
        if(memoryData != nil) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if(complete) {
                    complete(CBCacheStatusInMemoryCache, memoryData, nil);   
                }
                // TODO: bump this to the top of the memory cache
            });
        } else {
            
            // if not, see if it's in the file cache
            __block NSData *fileImage = [self getDataFromFileCache:fileURL];
            if(fileImage != nil) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if(complete) {
                        complete(CBCacheStatusInFileCache, fileImage, nil);
                    }
                    
                    // TODO: put this in the top of the memory cache
                    
                });
            } else {

                // if not, download from url
                NSURLRequest *request = [NSURLRequest requestWithURL:fileURL];
                [NSURLConnection sendAsynchronousRequest:request
                                                   queue:_cacheDownloadQueue
                                       completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
                                                                                      
                                           if(error == nil) {
                                               
                                               // TODO: store this in the memory cache which
                                               // should clean up/update the memory cache
                                               
                                               // save to file cache
                                               [self writeDataToFileCache:data usingURL:response.URL];
                                           }
                                           
                                           // make the callback on the main thread
                                           dispatch_async(dispatch_get_main_queue(), ^{
                                               if(complete) {
                                                   complete(CBCacheStatusNotCached, data, error);                                                   
                                               }
                                           });
                                           
                                       }];

            }

        }
        
        
        
        // TODO: in any case, update the last retrieved time in the data store
        // make sure this is done on main thread
        
    });
    
}

@end
