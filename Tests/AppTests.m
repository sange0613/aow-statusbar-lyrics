#import <AppKit/AppKit.h>
#import "MLAppDelegate.h"
#import "MLLyricsClient.h"

@interface MLAppDelegate (Testing)
- (void)pollMusic:(NSTimer *)timer;
- (void)retryLyrics:(id)sender;
- (NSString *)musicScript;
@end

@interface PlaybackScript : NSAppleScript
@property(nonatomic, copy) NSString *record;
@end
@implementation PlaybackScript
- (NSAppleEventDescriptor *)executeAndReturnError:(NSDictionary<NSString *, id> **)error {
    if (!self.record) {
        if (error) *error = @{NSAppleScriptErrorNumber:@(-1743)};
        return nil;
    }
    return [NSAppleEventDescriptor descriptorWithString:self.record];
}
@end

@interface LookupClient : MLLyricsClient
@property(nonatomic) NSInteger lookups;
@property(nonatomic) NSInteger invalidations;
@end
@implementation LookupClient
- (void)findLyrics:(MLPlaybackSnapshot *)snapshot completion:(void (^)(NSArray<MLLyricLine *> *, NSString *, BOOL))completion {
    self.lookups++;
    completion(@[], @"暂无同步歌词", NO);
}
- (void)invalidateCacheForSnapshot:(MLPlaybackSnapshot *)snapshot { self.invalidations++; }
@end

@interface AppUnderTest : MLAppDelegate
@property(nonatomic, copy) NSString *displayedText;
@end
@implementation AppUnderTest
- (BOOL)isMusicRunning { return YES; }
- (void)setStatusText:(NSString *)text { self.displayedText = text; }
@end

static void Check(BOOL ok, NSString *message) {
    if (!ok) { NSLog(@"FAIL: %@", message); exit(1); }
}
static NSString *Record(NSString *state, NSString *title, NSString *duration) {
    return [@[state, title, @"Artist", @"Album", duration, @"0"]
        componentsJoinedByString:[NSString stringWithFormat:@"%C", (unichar)31]];
}

int main(void) {
    @autoreleasepool {
        AppUnderTest *app = [[AppUnderTest alloc] init];
        NSDictionary *compileError = nil;
        NSAppleScript *realScript = [[NSAppleScript alloc] initWithSource:[app musicScript]];
        Check([realScript compileAndReturnError:&compileError], [NSString stringWithFormat:@"Music bridge compiles: %@", compileError]);
        LookupClient *client = [[LookupClient alloc] init];
        PlaybackScript *script = [[PlaybackScript alloc] initWithSource:@"return 1"];
        [app setValue:client forKey:@"client"];
        [app setValue:script forKey:@"playbackScript"];
        [app setValue:[[NSMenuItem alloc] initWithTitle:@"Song" action:nil keyEquivalent:@""] forKey:@"trackMenuItem"];
        [app setValue:[[NSMenuItem alloc] initWithTitle:@"Status" action:nil keyEquivalent:@""] forKey:@"lookupMenuItem"];

        script.record = Record(@"stopped", @"", @"0");
        [app pollMusic:nil];
        Check(client.lookups == 0 && [app.displayedText containsString:@"已停止"], @"stopped playback never queries lyrics");

        script.record = Record(@"playing", @"Song", @"141");
        [app pollMusic:nil];
        [app pollMusic:nil];
        Check(client.lookups == 1, @"polling same track avoids repeated queries");
        [app retryLyrics:nil];
        Check(client.lookups == 2 && client.invalidations == 1, @"manual retry invalidates cache");

        script.record = nil;
        [app pollMusic:nil];
        Check([app.displayedText containsString:@"访问权限"] && [app valueForKey:@"snapshot"] == nil, @"permission failure clears old playback");
        [app retryLyrics:nil];
        Check(client.lookups == 2, @"stale track cannot be retried after playback failure");

        script.record = Record(@"playing", @"Song", @"141");
        [app pollMusic:nil];
        Check(client.lookups == 3, @"playback recovers after permission error");
        script.record = Record(@"stopped", @"", @"0");
        [app pollMusic:nil];
        [app retryLyrics:nil];
        Check(client.lookups == 3 && [app valueForKey:@"snapshot"] == nil, @"stop cancels active playback and disables stale retry");
        NSLog(@"AppTests: all assertions passed");
    }
}
