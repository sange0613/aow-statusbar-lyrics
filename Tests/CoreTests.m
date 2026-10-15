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
        Assert(lines.count == 3, @"timed empty lines preserve instrumental breaks");
        Assert(fabs(lines[0].time - 1.2) < 0.001, @"lines are timestamp-sorted");
        Assert([lines[0].text isEqualToString:@"First"], @"line text is parsed");
        Assert(MLCurrentLine(lines, 16).text.length == 0, @"instrumental break clears previous lyric");
        NSArray<MLLyricLine *> *translated = MLParseLRC(@"[00:01.00]Original\n[00:01.00]翻译\n[00:05.00]");
        Assert(translated.count == 2 && [translated[0].text isEqualToString:@"Original · 翻译"], @"merge translations at identical timestamps");
        NSArray *offset = MLParseLRC(@"[offset:500]\n[00:01.00]<00:01.00>Hello");
        Assert(fabs([offset[0] time] - 0.5) < 0.001, @"LRC positive offset advances lyrics");
        Assert([[offset[0] text] isEqualToString:@"Hello"], @"strip enhanced LRC word timing tags");
        Assert(!MLHasTimedLyrics(MLParseLRC(@"[00:01]\n[00:05]")), @"blank timing markers do not count as lyrics");
        Assert(MLParseLRC(@"[00:99]Invalid").count == 0, @"invalid timestamp rejected");

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
        NSString *separatorString = [NSString stringWithFormat:@"%C", separator];
        for (NSString *badNumber in @[@"garbage", @"NaN", @"inf", @"-1", @"17oops"]) {
            NSString *invalid = [@[@"playing", @"Song", @"Artist", @"Album", @"141", badNumber] componentsJoinedByString:separatorString];
            Assert([MLPlaybackSnapshot snapshotFromRecord:invalid] == nil, @"invalid progress is rejected instead of appearing frozen");
        }
        NSString *stopped = [@[@"stopped", @"", @"", @"", @"0", @"0"] componentsJoinedByString:separatorString];
        MLPlaybackSnapshot *stoppedSnapshot = [MLPlaybackSnapshot snapshotFromRecord:stopped];
        Assert(stoppedSnapshot != nil && stoppedSnapshot.state == MLPlaybackStateStopped, @"stopped Music needs no current track");

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
        Assert(MLBestLyricsRecord(records, @"Other Song", @"Artist", 141) == nil, @"reject unrelated titles");
        Assert(MLBestLyricsRecord(records, @"Song", @"Other Artist", 141) == nil, @"reject covers by different artist");
        Assert(MLBestLyricsRecord(records, @"Song", @"Artist", 240) == nil, @"reject different duration versions");
        Assert([MLSearchTitle(@"Song (feat. Guest) - 2024 Remastered") isEqualToString:@"Song"], @"clean collaboration and remaster suffixes");
        Assert([MLSearchTitle(@"Song (Live)") isEqualToString:@"Song (Live)"], @"preserve live version");
        Assert([MLSearchTitle(@"Song (A Memory)") isEqualToString:@"Song (A Memory)"], @"preserve meaningful parentheses");
        Assert(MLBestLyricsRecord(records, @"Song (feat. Guest)", @"Artist & Guest", 141) != nil, @"match collaboration metadata differences");
        Assert(MLBestLyricsRecord(records, @"Song (Live)", @"Artist", 141) == nil, @"do not match live to studio");
        NSArray *chinese = @[@{@"trackName":@"烟花", @"artistName":@"窦靖童", @"duration":@313.2,
            @"syncedLyrics":@"[00:02.20]测试"}];
        Assert(MLBestLyricsRecord(chinese, @"烟花", @"窦靖童", 313.219) != nil, @"Chinese metadata supported");
        NSArray *malformed = @[@{@"trackName":@"Song", @"artistName":@"Artist", @"duration":NSNull.null,
            @"syncedLyrics":@"[00:01]Test"}];
        Assert(MLBestLyricsRecord(malformed, @"Song", @"Artist", 141) == nil, @"null duration is safe");
        NSArray *alias = @[@{@"trackName":@"烟花", @"artistName":@"Leah Dou", @"duration":@313,
            @"syncedLyrics":@"[00:02]Test"}, @{@"trackName":@"烟花", @"artistName":@"南西肯恩", @"duration":@273,
            @"syncedLyrics":@"[00:02]Other"}];
        Assert([MLUniqueTitleDurationRecord(alias, @"烟花", 313.219)[@"artistName"] isEqualToString:@"Leah Dou"], @"unique artist alias by title and close duration");
        NSArray *ambiguous = [alias arrayByAddingObject:@{@"trackName":@"烟花", @"artistName":@"Another", @"duration":@313,
            @"syncedLyrics":@"[00:02]Cover"}];
        Assert(MLUniqueTitleDurationRecord(ambiguous, @"烟花", 313.219) == nil, @"ambiguous artists rejected");

        NSLog(@"CoreTests: all assertions passed");
    }
    return 0;
}
