#import "MLAppDelegate.h"
#import "MLLyricsCore.h"
#import "MLLyricsClient.h"

@interface MLAppDelegate ()
@property(nonatomic, strong) NSStatusItem *statusItem;
@property(nonatomic, strong) NSMenuItem *trackMenuItem;
@property(nonatomic, strong) NSTimer *timer;
@property(nonatomic, copy) NSString *activeTrackKey;
@property(nonatomic, copy) NSArray<MLLyricLine *> *lines;
@property(nonatomic, strong) MLLyricsClient *client;
@property(nonatomic, strong) MLPlaybackSnapshot *snapshot;
@property(nonatomic, strong) NSMenuItem *lookupMenuItem;
@property(nonatomic, copy) NSString *lookupStatus;
@property(nonatomic) NSUInteger retryCount;
@property(nonatomic, strong) NSDate *retryAt;
@property(nonatomic) BOOL isLoadingLyrics;
@property(nonatomic, strong) NSAppleScript *playbackScript;
@end

@implementation MLAppDelegate

- (void)clearPlayback {
    [self.client cancel];
    self.activeTrackKey = nil;
    self.snapshot = nil;
    self.lines = @[];
    self.retryAt = nil;
    self.isLoadingLyrics = NO;
    self.lookupStatus = @"等待播放";
    self.lookupMenuItem.title = self.lookupStatus;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    self.client = [[MLLyricsClient alloc] init];
    self.lookupStatus = @"等待播放";
    self.lines = @[];
    self.playbackScript = [[NSAppleScript alloc] initWithSource:[self musicScript]];
    self.statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:NSVariableStatusItemLength];
    self.statusItem.autosaveName = @"MenuLyricsStatusItem";
    self.statusItem.button.font = [NSFont systemFontOfSize:13];
    self.statusItem.button.alignment = NSTextAlignmentCenter;
    self.statusItem.button.cell.usesSingleLineMode = YES;
    self.statusItem.button.cell.lineBreakMode = NSLineBreakByTruncatingTail;
    [self setStatusText:@"♪ 正在连接…"];

    NSMenu *menu = [[NSMenu alloc] init];
    self.trackMenuItem = [[NSMenuItem alloc] initWithTitle:@"等待 Apple Music"
                                                    action:nil keyEquivalent:@""];
    self.trackMenuItem.enabled = NO;
    [menu addItem:self.trackMenuItem];
    self.lookupMenuItem = [[NSMenuItem alloc] initWithTitle:@"等待播放" action:nil keyEquivalent:@""];
    [menu addItem:self.lookupMenuItem];
    NSMenuItem *retry = [[NSMenuItem alloc] initWithTitle:@"重新匹配歌词" action:@selector(retryLyrics:) keyEquivalent:@""];
    retry.target = self;
    [menu addItem:retry];
    [menu addItem:NSMenuItem.separatorItem];
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"退出歌词"
                                                  action:@selector(quit:) keyEquivalent:@"q"];
    quit.target = self;
    [menu addItem:quit];
    self.statusItem.menu = menu;

    [self pollMusic:nil];
    if (NSApp.isRunning) {
        self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                     target:self
                                                   selector:@selector(pollMusic:)
                                                   userInfo:nil repeats:YES];
        self.timer.tolerance = 0.08;
        [[NSRunLoop mainRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    }
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    [self.timer invalidate];
    [self.client cancel];
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
    NSAppleEventDescriptor *result = [self.playbackScript executeAndReturnError:&error];
    if (!result.stringValue) {
        BOOL denied = [error[NSAppleScriptErrorNumber] integerValue] == -1743;
        [self setStatusText:denied ? @"♪ 需要音乐访问权限" : @"♪ 等待歌曲信息"];
        self.trackMenuItem.title = denied ? @"系统设置 → 隐私与安全性 → 自动化" : @"Apple Music 暂未返回歌曲信息";
        [self clearPlayback];
        return;
    }

    MLPlaybackSnapshot *snapshot = [MLPlaybackSnapshot snapshotFromRecord:result.stringValue];
    if (!snapshot) {
        [self clearPlayback];
        self.trackMenuItem.title = @"等待 Apple Music";
        [self setStatusText:@"♪ Apple Music"];
        return;
    }

    if (snapshot.state == MLPlaybackStateStopped) {
        [self clearPlayback];
        self.trackMenuItem.title = @"Apple Music 已停止播放";
        [self setStatusText:@"■ 已停止"];
        return;
    }

    self.trackMenuItem.title = snapshot.artist.length > 0
        ? [NSString stringWithFormat:@"%@ — %@", snapshot.title, snapshot.artist]
        : snapshot.title;

    self.snapshot = snapshot;
    if (![snapshot.trackKey isEqualToString:self.activeTrackKey]) {
        self.activeTrackKey = snapshot.trackKey;
        self.lines = @[];
        self.retryCount = 0;
        self.retryAt = nil;
        [self fetchLyricsForSnapshot:snapshot];
    } else if (self.retryAt && self.retryAt.timeIntervalSinceNow <= 0 && !self.isLoadingLyrics) {
        self.retryAt = nil;
        [self fetchLyricsForSnapshot:snapshot];
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
        [self setStatusText:[prefix stringByAppendingString:self.lookupStatus ?: @"暂无同步歌词"]];
    }
}

- (NSString *)musicScript {
    return @"if application id \"com.apple.Music\" is not running then return \"\"\n"
            "with timeout of 2 seconds\n"
            "tell application \"Music\"\n"
            "set sep to ASCII character 31\n"
            "set s to (player state as text)\n"
            "if s is \"stopped\" then return s & sep & sep & sep & sep & \"0\" & sep & \"0\"\n"
            "set t to current track\n"
            "set albumName to \"\"\n"
            "try\nset albumName to (album of t as text)\nend try\n"
            "return s & sep & (name of t as text) & sep & (artist of t as text) & sep & albumName & sep & (duration of t as text) & sep & (player position as text)\n"
            "end tell\nend timeout";
}

- (void)retryLyrics:(id)sender {
    if (!self.snapshot || !self.activeTrackKey) return;
    self.retryCount = 0;
    self.retryAt = nil;
    [self.client invalidateCacheForSnapshot:self.snapshot];
    [self fetchLyricsForSnapshot:self.snapshot];
}

- (void)fetchLyricsForSnapshot:(MLPlaybackSnapshot *)snapshot {
    self.retryAt = nil;
    self.isLoadingLyrics = YES;
    self.lookupStatus = @"匹配歌词中…";
    self.lookupMenuItem.title = self.lookupStatus;
    [self.client findLyrics:snapshot completion:^(NSArray *lines, NSString *status, BOOL networkFailure) {
        self.lines = lines;
        self.isLoadingLyrics = NO;
        self.lookupStatus = status;
        self.lookupMenuItem.title = status;
        if (networkFailure && self.retryCount < 2) {
            self.retryCount++;
            self.retryAt = [NSDate dateWithTimeIntervalSinceNow:15 * self.retryCount];
        }
    }];
}

- (void)setStatusText:(NSString *)text {
    // Keep a stable, wider lyric area. Reserve room for other menu bar items on small displays.
    NSScreen *screen = self.statusItem.button.window.screen ?: NSScreen.mainScreen;
    self.statusItem.length = screen ? MIN(520.0, NSWidth(screen.frame) * 0.36) : 520.0;
    // AppKit truncates by rendered width without splitting emoji or composed characters.
    if (![self.statusItem.button.title isEqualToString:text]) {
        self.statusItem.button.title = text;
        self.statusItem.button.toolTip = text;
        self.statusItem.button.accessibilityLabel = [NSString stringWithFormat:@"当前歌词：%@", text];
    }
}

@end
