#import "MLLyricsCore.h"

static NSString *MLReplace(NSString *text, NSString *pattern, NSString *replacement) {
    static NSCache<NSString *, NSRegularExpression *> *expressions;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ expressions = [[NSCache alloc] init]; expressions.countLimit = 16; });
    NSRegularExpression *re = [expressions objectForKey:pattern];
    if (!re) {
        re = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
        if (re) [expressions setObject:re forKey:pattern];
    }
    return [re stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length)
        withTemplate:replacement];
}

NSString *MLSearchTitle(NSString *title) {
    // Preserve live/remix/acoustic versions and meaningful parenthesized song titles.
    NSString *value = MLReplace(title, @"[（(\\[]\\s*(?:feat\\.?|ft\\.?|featuring)\\s+[^）)\\]]*[）)\\]]", @"");
    value = MLReplace(value, @"\\s*[-–—]\\s*(?:\\d{4}\\s+)?remaster(?:ed)?(?:\\s+\\d{4})?\\s*$", @"");
    value = MLReplace(value, @"[（(\\[]\\s*(?:\\d{4}\\s+)?remaster(?:ed)?(?:\\s+\\d{4})?\\s*[）)\\]]", @"");
    return [MLReplace(value, @"\\s+", @" ") stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

NSString *MLPrimaryArtist(NSString *artist) {
    return [MLReplace(artist, @"\\s+(?:feat\\.?|ft\\.?|featuring|&|and|×)\\s+.*$", @"")
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

static NSString *MLNormalized(NSString *value) {
    NSString *folded = [value stringByFoldingWithOptions:NSDiacriticInsensitiveSearch | NSWidthInsensitiveSearch
        locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    return MLReplace(folded.lowercaseString, @"[^\\p{L}\\p{N}]", @"");
}

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
    NSTextCheckingResult *offsetTag = [[NSRegularExpression regularExpressionWithPattern:@"\\[offset:([+-]?\\d+)\\]"
        options:NSRegularExpressionCaseInsensitive error:nil] firstMatchInString:source options:0 range:NSMakeRange(0, source.length)];
    double offset = offsetTag ? [[source substringWithRange:[offsetTag rangeAtIndex:1]] doubleValue] / 1000.0 : 0;

    [source enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSArray<NSTextCheckingResult *> *matches = [regex matchesInString:line options:0
                                                                    range:NSMakeRange(0, line.length)];
        if (matches.count == 0) return;
        NSTextCheckingResult *last = matches.lastObject;
        NSString *text = [[line substringFromIndex:NSMaxRange(last.range)]
            stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        text = MLReplace(text, @"<\\d{1,3}:\\d{2}(?:[.:]\\d{1,3})?>", @"");

        for (NSTextCheckingResult *match in matches) {
            double minutes = [[line substringWithRange:[match rangeAtIndex:1]] doubleValue];
            double seconds = [[line substringWithRange:[match rangeAtIndex:2]] doubleValue];
            if (seconds >= 60) continue;
            double fraction = 0;
            NSRange fractionRange = [match rangeAtIndex:3];
            if (fractionRange.location != NSNotFound) {
                NSString *digits = [line substringWithRange:fractionRange];
                fraction = digits.doubleValue / pow(10, digits.length);
            }
            [result addObject:[[MLLyricLine alloc] initWithTime:MAX(0, minutes * 60 + seconds + fraction - offset)
                                                          text:text]];
        }
    }];

    [result sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(MLLyricLine *a, MLLyricLine *b) {
        if (a.time < b.time) return NSOrderedAscending;
        if (a.time > b.time) return NSOrderedDescending;
        return NSOrderedSame;
    }];
    NSMutableArray<MLLyricLine *> *merged = [NSMutableArray array];
    for (MLLyricLine *line in result) {
        MLLyricLine *previous = merged.lastObject;
        if (previous && fabs(previous.time - line.time) < 0.0001) {
            if (line.text.length && ![previous.text isEqualToString:line.text]) {
                NSString *text = previous.text.length ? [previous.text stringByAppendingFormat:@" · %@", line.text] : line.text;
                merged[merged.count - 1] = [[MLLyricLine alloc] initWithTime:line.time text:text];
            }
        } else {
            [merged addObject:line];
        }
    }
    return merged;
}

BOOL MLHasTimedLyrics(NSArray<MLLyricLine *> *lines) {
    for (MLLyricLine *line in lines) if (line.text.length) return YES;
    return NO;
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
        if (![MLNormalized(MLSearchTitle(recordTitle)) isEqualToString:MLNormalized(MLSearchTitle(title))]) continue;
        NSString *candidateArtist = MLNormalized(MLPrimaryArtist(recordArtist));
        NSString *wantedArtist = MLNormalized(MLPrimaryArtist(artist));
        if (wantedArtist.length == 0 || ![candidateArtist isEqualToString:wantedArtist]) continue;
        id length = record[@"duration"];
        if (![length isKindOfClass:NSNumber.class] || duration <= 0 || !isfinite(duration)) continue;
        double score = fabs([length doubleValue] - duration);
        if (!isfinite(score) || score > 5) continue;
        if (score < bestScore) {
            if (!MLHasTimedLyrics(MLParseLRC(synced))) continue;
            best = record;
            bestScore = score;
        }
    }
    return best;
}

NSDictionary *MLUniqueTitleDurationRecord(NSArray *records, NSString *title, NSTimeInterval duration) {
    NSMutableSet *artists = [NSMutableSet set];
    NSDictionary *best = nil;
    double bestDelta = DBL_MAX;
    for (id value in records) {
        if (![value isKindOfClass:NSDictionary.class]) continue;
        NSDictionary *record = value;
        if (![record[@"trackName"] isKindOfClass:NSString.class] ||
            ![record[@"artistName"] isKindOfClass:NSString.class] ||
            ![record[@"duration"] isKindOfClass:NSNumber.class]) continue;
        if (![MLNormalized(MLSearchTitle(record[@"trackName"])) isEqualToString:MLNormalized(MLSearchTitle(title))]) continue;
        double delta = fabs([record[@"duration"] doubleValue] - duration);
        if (!isfinite(delta) || duration <= 0 || delta > 2) continue;
        NSString *artist = MLNormalized(record[@"artistName"]);
        if (!artist.length) continue;
        // Count even unsynchronized candidates so ambiguity is not hidden.
        [artists addObject:artist];
        if (![record[@"syncedLyrics"] isKindOfClass:NSString.class] || !MLHasTimedLyrics(MLParseLRC(record[@"syncedLyrics"]))) continue;
        if (delta < bestDelta) { best = record; bestDelta = delta; }
    }
    return artists.count == 1 ? best : nil;
}

@implementation MLPlaybackSnapshot
+ (instancetype)snapshotFromRecord:(NSString *)record {
    NSArray<NSString *> *parts = [record componentsSeparatedByString:[NSString stringWithFormat:@"%C", (unichar)0x1F]];
    if (parts.count != 6) return nil;
    NSString *state = [parts[0] lowercaseString];
    BOOL stopped = [state isEqualToString:@"stopped"];
    BOOL playing = [@[@"playing", @"fast forwarding", @"rewinding"] containsObject:state];
    if (!stopped && !playing && ![state isEqualToString:@"paused"]) return nil;
    if (!stopped && ![parts[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length) return nil;
    double numbers[2];
    for (NSUInteger index = 0; index < 2; index++) {
        NSScanner *scanner = [NSScanner scannerWithString:parts[4 + index]];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        if (![scanner scanDouble:&numbers[index]] || !scanner.isAtEnd || !isfinite(numbers[index]) || numbers[index] < 0) return nil;
    }
    if (!stopped && numbers[0] <= 0) return nil;

    MLPlaybackSnapshot *snapshot = [[self alloc] init];
    snapshot->_state = playing ? MLPlaybackStatePlaying
                      : [state isEqualToString:@"paused"] ? MLPlaybackStatePaused
                      : MLPlaybackStateStopped;
    snapshot->_title = [parts[1] copy];
    snapshot->_artist = [parts[2] copy];
    snapshot->_album = [parts[3] copy];
    snapshot->_duration = numbers[0];
    snapshot->_position = numbers[1];
    return snapshot;
}

- (NSString *)trackKey {
    return [NSString stringWithFormat:@"%@\n%@\n%@\n%.0f", self.title, self.artist,
            self.album, self.duration];
}
@end
