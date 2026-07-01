#import <Foundation/Foundation.h>
#import "MLLyricsCore.h"

static void Assert(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        NSArray<MLLyricLine *> *lines = MLParseLRC(@"[00:12.50]Second\n[00:01.20]First\n[00:15.00]");
        Assert(lines.count == 2, @"empty lyric lines are ignored");
        Assert(fabs(lines[0].time - 1.2) < 0.001, @"lines are timestamp-sorted");
        Assert([lines[0].text isEqualToString:@"First"], @"line text is parsed");

        NSArray<MLLyricLine *> *echoes = MLParseLRC(@"[00:01.00][00:03.50]Echo");
        Assert(echoes.count == 2, @"multiple timestamps are supported");
        Assert([MLCurrentLine(echoes, 3.6).text isEqualToString:@"Echo"], @"current line follows playback time");
        Assert(MLCurrentLine(echoes, 0.5) == nil, @"no line exists before first timestamp");

        unichar separator = 0x1F;
        NSString *record = [NSString stringWithFormat:@"playing%C Song%CArtist%CAlbum%C245.2%C17.5",
                            separator, separator, separator, separator, separator];
        MLPlaybackSnapshot *snapshot = [MLPlaybackSnapshot snapshotFromRecord:record];
        Assert(snapshot != nil, @"complete Music record parses");
        Assert(snapshot.state == MLPlaybackStatePlaying, @"playing state parses");
        Assert(fabs(snapshot.duration - 245.2) < 0.001, @"duration parses");
        Assert([MLPlaybackSnapshot snapshotFromRecord:@"stopped\x1FSong"] == nil, @"incomplete record is rejected");

        NSArray *records = @[
            @{@"trackName": @"Song", @"artistName": @"Artist", @"duration": @190,
              @"syncedLyrics": @"[00:01.00]Wrong duration"},
            @{@"trackName": @"Song", @"artistName": @"Artist", @"duration": @141.8,
              @"syncedLyrics": @"[00:01.00]Best"},
            @{@"trackName": @"Song", @"artistName": @"Artist", @"duration": @141,
              @"syncedLyrics": [NSNull null]}
        ];
        NSDictionary *best = MLBestLyricsRecord(records, @"Song", @"Artist", 141);
        Assert([best[@"syncedLyrics"] containsString:@"Best"], @"search fallback chooses closest synced record");

        NSLog(@"CoreTests: all assertions passed");
    }
    return 0;
}
