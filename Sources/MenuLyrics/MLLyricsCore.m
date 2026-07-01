#import "MLLyricsCore.h"

@implementation MLLyricLine
- (instancetype)initWithTime:(NSTimeInterval)time text:(NSString *)text {
    if ((self = [super init])) {
        _time = time;
        _text = [text copy];
    }
    return self;
}
@end

NSArray<MLLyricLine *> *MLParseLRC(NSString *source) {
    NSMutableArray<MLLyricLine *> *result = [NSMutableArray array];
    NSRegularExpression *regex = [NSRegularExpression
        regularExpressionWithPattern:@"\\[(\\d{1,3}):(\\d{2})(?:[.:](\\d{1,3}))?\\]"
        options:0 error:nil];

    [source enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:line options:0
                                                                    range:NSMakeRange(0, line.length)];
        if (matches.count == 0) return;
        NSTextCheckingResult *last = matches.lastObject;
        NSString *text = [[line substringFromIndex:NSMaxRange(last.range)]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (text.length == 0) return;

        for (NSTextCheckingResult *match in matches) {
            double minutes = [[line substringWithRange:[match rangeAtIndex:1]] doubleValue];
            double seconds = [[line substringWithRange:[match rangeAtIndex:2]] doubleValue];
            double fraction = 0;
            NSRange fractionRange = [match rangeAtIndex:3];
            if (fractionRange.location != NSNotFound) {
                NSString *digits = [line substringWithRange:fractionRange];
                fraction = digits.doubleValue / pow(10, digits.length);
            }
            [result addObject:[[MLLyricLine alloc] initWithTime:minutes * 60 + seconds + fraction
                                                          text:text]];
        }
    }];

    [result sortUsingComparator:^NSComparisonResult(MLLyricLine *a, MLLyricLine *b) {
        if (a.time < b.time) return NSOrderedAscending;
        if (a.time > b.time) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    return result;
}

MLLyricLine *MLCurrentLine(NSArray<MLLyricLine *> *lines, NSTimeInterval position) {
    MLLyricLine *current = nil;
    for (MLLyricLine *line in lines) {
        if (line.time > position) break;
        current = line;
    }
    return current;
}

NSDictionary *MLBestLyricsRecord(NSArray *records, NSString *title, NSString *artist,
                                  NSTimeInterval duration) {
    NSDictionary *best = nil;
    double bestScore = DBL_MAX;
    for (id value in records) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *record = value;
        NSString *synced = [record[@"syncedLyrics"] isKindOfClass:NSString.class]
            ? record[@"syncedLyrics"] : nil;
        if (synced.length == 0) continue;

        NSString *recordTitle = [record[@"trackName"] isKindOfClass:NSString.class]
            ? record[@"trackName"] : @"";
        NSString *recordArtist = [record[@"artistName"] isKindOfClass:NSString.class]
            ? record[@"artistName"] : @"";
        double score = fabs([record[@"duration"] doubleValue] - duration);
        if ([recordTitle caseInsensitiveCompare:title] != NSOrderedSame) score += 60;
        if ([recordArtist caseInsensitiveCompare:artist] != NSOrderedSame) score += 30;
        if (score < bestScore) {
            best = record;
            bestScore = score;
        }
    }
    return best;
}

@implementation MLPlaybackSnapshot
+ (instancetype)snapshotFromRecord:(NSString *)record {
    NSArray<NSString *> *parts = [record componentsSeparatedByString:[NSString stringWithFormat:@"%C", (unichar)0x1F]];
    if (parts.count != 6 || [parts[1] length] == 0) return nil;

    MLPlaybackSnapshot *snapshot = [[self alloc] init];
    NSString *state = [parts[0] lowercaseString];
    snapshot->_state = [state isEqualToString:@"playing"] ? MLPlaybackStatePlaying
                      : [state isEqualToString:@"paused"] ? MLPlaybackStatePaused
                      : MLPlaybackStateStopped;
    snapshot->_title = [parts[1] copy];
    snapshot->_artist = [parts[2] copy];
    snapshot->_album = [parts[3] copy];
    snapshot->_duration = [parts[4] doubleValue];
    snapshot->_position = [parts[5] doubleValue];
    return snapshot;
}

- (NSString *)trackKey {
    return [NSString stringWithFormat:@"%@\n%@\n%@\n%.0f", self.title, self.artist,
            self.album, self.duration];
}
@end
