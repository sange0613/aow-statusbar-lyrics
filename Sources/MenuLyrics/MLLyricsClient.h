#import <Foundation/Foundation.h>
#import "MLLyricsCore.h"

// One cancellable lookup at a time; completion is always delivered on the main queue.
@interface MLLyricsClient : NSObject
- (instancetype)initWithSession:(NSURLSession *)session;
- (void)cancel;
- (void)invalidateCacheForSnapshot:(MLPlaybackSnapshot *)snapshot;
- (void)findLyrics:(MLPlaybackSnapshot *)snapshot
        completion:(void (^)(NSArray<MLLyricLine *> *, NSString *, BOOL))completion;
@end
