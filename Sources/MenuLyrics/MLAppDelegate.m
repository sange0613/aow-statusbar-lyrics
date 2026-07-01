#import "MLAppDelegate.h"
#import "MLLyricsCore.h"

@interface MLAppDelegate ()
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *trackMenuItem;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *activeTrackKey;
@property(nonatomic, copy) NSArray<MLLyricLine *> *lines;
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSArray<MLLyricLine *> *> *cache;
@property(nonatomic) BOOL isLoadingLyrics;
@end

@implementation MLAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.cache = [NSMutableDictionary dictionary];
    self.lines = @[];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.autosaveName = @"MenuLyricsStatusItem";
    self.statusItem.button.title = @"♪ 正在连接…";
    self.statusItem.button.toolTip = @"Apple Music 歌词";

    NSMenu *menu = [[NSMenu alloc] init];
    self.trackMenuItem = [[NSMenuItem alloc] initWithTitle:@"等待 Apple Music"
                                                    action:nil keyEquivalent:@""];
    self.trackMenuItem.enabled = NO;
    [menu addItem:self.trackMenuItem];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出歌词"
                                                  action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
    self.statusItem.menu = menu;

    [self pollMusic:nil];
    if (NSApp.isRunning) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.35
                                                     target:self
                                                   selector:@selector(pollMusic:)
                                                   userInfo:nil repeats:YES];
        self.timer.tolerance = 0.08;
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
    [[NSStatusBar systemStatusBar] removeStatusItem:self.statusItem];
}

- (void)quit:(id)sender {
    [NSApp terminate:nil];
}

- (BOOL)isMusicRunning {
    return [NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.apple.Music"].count > 0;
}

- (void)pollMusic:(NSTimer *)timer {
    if (![self isMusicRunning]) {
        [NSApp terminate:nil];
        return;
    }

    NSDictionary *error = nil;
    NSAppleEventDescriptor *result = [[[NSAppleScript alloc] initWithSource:[self musicScript]]
                                      executeAndReturnError:&error];
    if (!result.stringValue) {
        [self setStatusText:@"♪ 需要音乐访问权限"];
        self.trackMenuItem.title = @"请在“系统设置 → 隐私与安全性 → 自动化”中允许访问音乐";
        return;
    }

    MLPlaybackSnapshot *snapshot = [MLPlaybackSnapshot snapshotFromRecord:result.stringValue];
    if (!snapshot) {
        [self setStatusText:@"♪ Apple Music"];
        return;
    }

    self.trackMenuItem.title = snapshot.artist.length > 0
        ? [NSString stringWithFormat:@"%@ — %@", snapshot.title, snapshot.artist]
        : snapshot.title;

    if (![snapshot.trackKey isEqualToString:self.activeTrackKey]) {
        self.activeTrackKey = snapshot.trackKey;
        self.lines = self.cache[snapshot.trackKey] ?: @[];
        if (!self.cache[snapshot.trackKey]) [self fetchLyricsForSnapshot:snapshot];
    }

    if (snapshot.state == MLPlaybackStateStopped) {
        [self setStatusText:@"■ 已停止"];
        return;
    }

    MLLyricLine *line = MLCurrentLine(self.lines, snapshot.position);
    NSString *prefix = snapshot.state == MLPlaybackStatePaused ? @"Ⅱ " : @"";
    if (line.text.length > 0) {
        [self setStatusText:[prefix stringByAppendingString:line.text]];
    } else if (self.isLoadingLyrics) {
        [self setStatusText:[prefix stringByAppendingString:@"♪ 匹配歌词中…"]];
    } else if (self.lines.count > 0) {
        [self setStatusText:[prefix stringByAppendingString:@"♪ …"]];
    } else {
        [self setStatusText:[prefix stringByAppendingFormat:@"♪ %@", snapshot.title]];
    }
}

- (NSString *)musicScript {
    return @"tell application \"Music\"\n"
            "set sep to ASCII character 31\n"
            "set s to (player state as text)\n"
            "set t to current track\n"
            "set albumName to \"\"\n"
            "try\nset albumName to (album of t as text)\nend try\n"
            "return s & sep & (name of t as text) & sep & (artist of t as text) & sep & albumName & sep & (duration of t as text) & sep & (player position as text)\n"
            "end tell";
}

- (void)fetchLyricsForSnapshot:(MLPlaybackSnapshot *)snapshot {
    self.isLoadingLyrics = YES;
    NSString *requestedKey = snapshot.trackKey;
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://lrclib.net/api/get"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"track_name" value:snapshot.title],
        [NSURLQueryItem queryItemWithName:@"artist_name" value:snapshot.artist],
        [NSURLQueryItem queryItemWithName:@"album_name" value:snapshot.album],
        [NSURLQueryItem queryItemWithName:@"duration" value:[NSString stringWithFormat:@"%.0f", snapshot.duration]]
    ];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:@"MenuLyrics/1.0 (macOS status bar lyrics)" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 12;

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSArray<MLLyricLine *> *lines = @[];
        if (data.length > 0 && !error) {
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:NSDictionary.class]) {
                NSString *synced = [json[@"syncedLyrics"] isKindOfClass:NSString.class]
                    ? json[@"syncedLyrics"] : nil;
                if (synced.length > 0) lines = MLParseLRC(synced);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            if (lines.count == 0) {
                [self fetchSearchLyricsForSnapshot:snapshot requestedKey:requestedKey];
                return;
            }
            self.cache[requestedKey] = lines;
            if ([self.activeTrackKey isEqualToString:requestedKey]) self.lines = lines;
            if ([self.activeTrackKey isEqualToString:requestedKey]) self.isLoadingLyrics = NO;
        });
    }] resume];
}

- (void)fetchSearchLyricsForSnapshot:(MLPlaybackSnapshot *)snapshot requestedKey:(NSString *)requestedKey {
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://lrclib.net/api/search"];
    components.queryItems = @[
        [NSURLQueryItem queryItemWithName:@"track_name" value:snapshot.title],
        [NSURLQueryItem queryItemWithName:@"artist_name" value:snapshot.artist]
    ];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:@"MenuLyrics/1.0 (macOS status bar lyrics)" forHTTPHeaderField:@"User-Agent"];
    request.timeoutInterval = 12;

    [[[NSURLSession sharedSession] dataTaskWithRequest:request
                                     completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSArray<MLLyricLine *> *lines = @[];
        if (data.length > 0 && !error) {
            id json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if ([json isKindOfClass:NSArray.class]) {
                NSDictionary *best = MLBestLyricsRecord(json, snapshot.title, snapshot.artist, snapshot.duration);
                NSString *synced = [best[@"syncedLyrics"] isKindOfClass:NSString.class]
                    ? best[@"syncedLyrics"] : nil;
                if (synced.length > 0) lines = MLParseLRC(synced);
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.cache[requestedKey] = lines;
            if ([self.activeTrackKey isEqualToString:requestedKey]) {
                self.lines = lines;
                self.isLoadingLyrics = NO;
            }
        });
    }] resume];
}

- (void)setStatusText:(NSString *)text {
    static const NSUInteger maximumCharacters = 36;
    NSString *display = text;
    if (display.length > maximumCharacters) {
        display = [[display substringToIndex:maximumCharacters - 1] stringByAppendingString:@"…"];
    }
    self.statusItem.button.title = display;
    self.statusItem.button.accessibilityLabel = [NSString stringWithFormat:@"当前歌词：%@", text];
}

@end
