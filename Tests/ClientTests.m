#import <Foundation/Foundation.h>
#import "MLLyricsClient.h"

static NSInteger mode = 0;
static NSInteger requests = 0;
@interface FakeLyricsProtocol : NSURLProtocol
@end
@implementation FakeLyricsProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)stopLoading {}
- (void)startLoading {
    requests++;
    if (mode == 4) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorNotConnectedToInternet userInfo:nil]];
        return;
    }
    if (mode == 0) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
        return;
    }
    BOOL search = [self.request.URL.path hasSuffix:@"search"];
    id json = search ? @[@{@"trackName":@"Song", @"artistName":@"Artist", @"duration":@141,
        @"syncedLyrics":@"[00:01.00]Test lyric"}] : @{};
    NSInteger status = mode == 2 ? 500 : (search ? 200 : 404);
    if (mode == 3) json = @[@{@"trackName":@"Song", @"artistName":@"Artist", @"duration":@141, @"syncedLyrics":@"[00:01]"}];
    if (mode == 5 && search) json = @[@{@"trackName":@"Song", @"artistName":@"Alternate Name", @"duration":@141, @"syncedLyrics":@"[00:01]Test"}];
    [self.client URLProtocol:self didReceiveResponse:[[NSHTTPURLResponse alloc] initWithURL:self.request.URL
        statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:nil] cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[NSJSONSerialization dataWithJSONObject:json options:0 error:nil]];
    [self.client URLProtocolDidFinishLoading:self];
}
@end

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static void Wait(BOOL *done) {
    NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:5];
    while (!*done && limit.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    Check(*done, @"completion within deadline");
}
int main(void) {
    @autoreleasepool {
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.protocolClasses = @[FakeLyricsProtocol.class];
        NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
        MLLyricsClient *client = [[MLLyricsClient alloc] initWithSession:session];
        MLPlaybackSnapshot *snapshot = [MLPlaybackSnapshot snapshotFromRecord:
            [@[@"playing", @"Song", @"Artist", @"Album", @"141", @"10"] componentsJoinedByString:[NSString stringWithFormat:@"%C", (unichar)31]]];
        __block BOOL done = NO;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) {
            Check(failed && lines.count == 0, @"network error reported"); done = YES;
        }];
        Wait(&done);

        mode = 4; done = NO;
        NSInteger beforeOffline = requests;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) {
            Check(failed && !lines.count, @"offline condition is retryable"); done = YES;
        }];
        Wait(&done);
        Check(requests == beforeOffline + 1, @"offline stops redundant endpoint requests");

        mode = 1; done = NO;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) {
            Check(!failed && lines.count == 1, @"network failure not cached; fallback succeeds"); done = YES;
        }];
        Wait(&done);
        NSInteger beforeCache = requests; done = NO;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) { done = YES; }];
        Wait(&done);
        Check(beforeCache == requests, @"successful lyrics reused");

        [client invalidateCacheForSnapshot:snapshot];
        done = NO;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) { done = YES; }];
        Wait(&done);
        Check(requests > beforeCache, @"manual rematch bypasses cached lyrics");

        mode = 2; done = NO;
        [client invalidateCacheForSnapshot:snapshot];
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) {
            Check(failed && lines.count == 0, @"HTTP error body cannot become lyrics"); done = YES;
        }];
        Wait(&done);

        mode = 3; done = NO;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) {
            Check(!failed && lines.count == 0, @"blank-only LRC is not successful match"); done = YES;
        }];
        Wait(&done);

        mode = 1;
        client = [[MLLyricsClient alloc] initWithSession:session];
        __block NSInteger oldCompletions = 0; done = NO;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) { oldCompletions++; }];
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) { done = YES; }];
        Wait(&done);
        Check(oldCompletions == 0, @"superseded lookup cannot update current song");

        mode = 5; done = NO;
        client = [[MLLyricsClient alloc] initWithSession:session];
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) {
            Check(lines.count == 1 && [status containsString:@"Alternate Name"], @"alias provenance is shown"); done = YES;
        }];
        Wait(&done);
        NSInteger beforeAliasCache = requests; done = NO;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) {
            Check([status containsString:@"Alternate Name"], @"cached alias keeps provenance"); done = YES;
        }];
        Wait(&done);
        Check(requests == beforeAliasCache, @"alias cache avoids repeated network lookup");
        [session invalidateAndCancel];
        NSLog(@"ClientTests: all assertions passed");
    }
}
