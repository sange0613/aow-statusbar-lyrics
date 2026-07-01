#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MLPlaybackState) {
    MLPlaybackStateStopped,
    MLPlaybackStatePaused,
    MLPlaybackStatePlaying
};

@interface MLLyricLine : NSObject
@property(nonatomic, readonly) NSTimeInterval time;
@property(nonatomic, copy, readonly) NSString *text;
- (instancetype)initWithTime:(NSTimeInterval)time text:(NSString *)text;
@end

FOUNDATION_EXPORT NSArray<MLLyricLine *> *MLParseLRC(NSString *source);
FOUNDATION_EXPORT MLLyricLine * _Nullable MLCurrentLine(NSArray<MLLyricLine *> *lines,
                                                        NSTimeInterval position);
FOUNDATION_EXPORT NSDictionary * _Nullable MLBestLyricsRecord(NSArray *records,
                                                               NSString *title,
                                                               NSString *artist,
                                                               NSTimeInterval duration);

@interface MLPlaybackSnapshot : NSObject
@property(nonatomic, readonly) MLPlaybackState state;
@property(nonatomic, copy, readonly) NSString *title;
@property(nonatomic, copy, readonly) NSString *artist;
@property(nonatomic, copy, readonly) NSString *album;
@property(nonatomic, readonly) NSTimeInterval duration;
@property(nonatomic, readonly) NSTimeInterval position;
@property(nonatomic, copy, readonly) NSString *trackKey;
+ (nullable instancetype)snapshotFromRecord:(NSString *)record;
@end

NS_ASSUME_NONNULL_END
