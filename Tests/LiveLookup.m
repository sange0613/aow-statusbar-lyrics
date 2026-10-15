#import <Foundation/Foundation.h>
#import "MLLyricsClient.h"
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 5) return 2;
        NSArray *fields = @[@"playing", @(argv[1]), @(argv[2]), @(argv[3]), @(argv[4]), @"0"];
        MLPlaybackSnapshot *snapshot = [MLPlaybackSnapshot snapshotFromRecord:[fields componentsJoinedByString:
            [NSString stringWithFormat:@"%C", (unichar)31]]];
        MLLyricsClient *client = [[MLLyricsClient alloc] init];
        __block BOOL done = NO, success = NO;
        [client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL failed) {
            NSLog(@"lines=%lu status=%@ networkFailure=%d", (unsigned long)lines.count, status, failed);
            success = lines.count > 0; done = YES;
        }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:55];
        while (!done && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        [client cancel];
        return success ? 0 : 1;
    }
}
