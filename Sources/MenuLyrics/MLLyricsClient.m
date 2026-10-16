#import "MLLyricsClient.h"

@interface MLLyricsClient ()
@property(nonatomic) NSUInteger generation;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableDictionary *cache;
@property(nonatomic, strong) NSURLSession *session;
@end

@implementation MLLyricsClient
- (instancetype)init {
    return [self initWithSession:NSURLSession.sharedSession];
}
- (instancetype)initWithSession:(NSURLSession *)session {
    if ((self = [super init])) { _cache = [NSMutableDictionary dictionary]; _session = session; }
    return self;
}
- (void)cancel {
    self.generation++;
    [self.task cancel];
    self.task = nil;
}
- (void)invalidateCacheForSnapshot:(MLPlaybackSnapshot *)snapshot {
    [self.cache removeObjectForKey:snapshot.trackKey];
}
- (void)findLyrics:(MLPlaybackSnapshot *)snapshot completion:(void (^)(NSArray<MLLyricLine *> *, NSString *, BOOL))completion {
    [self cancel];
    NSDictionary *cached = self.cache[snapshot.trackKey];
    if (cached) { completion(cached[@"lines"], cached[@"status"], NO); return; }
    NSDictionary *signature = @{@"track_name":snapshot.title, @"artist_name":snapshot.artist,
        @"album_name":snapshot.album, @"duration":[NSString stringWithFormat:@"%.2f", snapshot.duration]};
    NSMutableArray *queries = [NSMutableArray arrayWithObject:@[@"get-cached", signature]];
    NSArray *searches = @[
        @{@"track_name":snapshot.title, @"artist_name":snapshot.artist},
        @{@"track_name":MLSearchTitle(snapshot.title), @"artist_name":MLPrimaryArtist(snapshot.artist)},
        @{@"track_name":MLSearchTitle(snapshot.title)}];
    for (NSDictionary *search in searches) {
        NSArray *entry = @[@"search", search];
        if (![queries containsObject:entry]) [queries addObject:entry];
    }
    // External lookup is last so a slow cache miss does not delay available search results.
    [queries addObject:@[@"get", signature]];
    [self runQueries:queries index:0 snapshot:snapshot generation:self.generation networkFailure:NO completion:completion];
}
- (void)runQueries:(NSArray *)queries index:(NSUInteger)index snapshot:(MLPlaybackSnapshot *)snapshot
        generation:(NSUInteger)generation networkFailure:(BOOL)networkFailure
        completion:(void (^)(NSArray<MLLyricLine *> *, NSString *, BOOL))completion {
    if (generation != self.generation) return;
    if (index == queries.count) {
        completion(@[], networkFailure ? @"网络请求失败，点击菜单可重试" : @"暂无匹配的同步歌词", networkFailure);
        return;
    }
    NSArray *entry = queries[index];
    NSURLComponents *url = [NSURLComponents componentsWithString:
        [@"https://lrclib.net/api/" stringByAppendingString:entry[0]]];
    NSMutableArray *items = [NSMutableArray array];
    [entry[1] enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [items addObject:[NSURLQueryItem queryItemWithName:key value:value]];
    }];
    url.queryItems = items;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
    request.timeoutInterval = 8;
    [request setValue:@"AowStatusbarLyrics/1.4.1 (https://github.com/sange0613/aow-statusbar-lyrics)" forHTTPHeaderField:@"User-Agent"];
    self.task = [self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        BOOL failure = error != nil || (status != 200 && status != 404) || (status == 200 && !json);
        if (status == 200 && ![json isKindOfClass:NSArray.class] && ![json isKindOfClass:NSDictionary.class]) failure = YES;
        BOOL offline = [error.domain isEqualToString:NSURLErrorDomain] &&
            (error.code == NSURLErrorNotConnectedToInternet || error.code == NSURLErrorDataNotAllowed || error.code == NSURLErrorNetworkConnectionLost);
        NSArray *records = status == 200 ? ([json isKindOfClass:NSArray.class] ? json :
            ([json isKindOfClass:NSDictionary.class] ? @[json] : @[])) : @[];
        NSDictionary *best = MLBestLyricsRecord(records, snapshot.title, snapshot.artist, snapshot.duration);
        BOOL inferredArtist = NO;
        if (!best && [entry[0] isEqualToString:@"search"] && [entry[1] count] == 1) {
            best = MLUniqueTitleDurationRecord(records, snapshot.title, snapshot.duration);
            inferredArtist = best != nil;
        }
        NSArray *lines = best ? MLParseLRC(best[@"syncedLyrics"]) : @[];
        NSString *matchStatus = inferredArtist ? [NSString stringWithFormat:@"按歌名和时长匹配 · 请核对歌手：%@", best[@"artistName"]] : @"同步歌词已就绪";
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation != self.generation) return;
            self.task = nil;
            if (offline) {
                completion(@[], @"网络未连接，稍后自动重试", YES);
                return;
            }
            if (lines.count) {
                if (self.cache.count >= 100) [self.cache removeAllObjects];
                self.cache[snapshot.trackKey] = @{@"lines":lines, @"status":matchStatus};
                completion(lines, matchStatus, NO);
            } else {
                [self runQueries:queries index:index + 1 snapshot:snapshot generation:generation
                    networkFailure:networkFailure || failure completion:completion];
            }
        });
    }];
    [self.task resume];
}
@end
