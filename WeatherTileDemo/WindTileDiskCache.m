//
//  WindTileDiskCache.m
//  WeatherTileDemo
//

#import "WindTileDiskCache.h"
#import <CommonCrypto/CommonDigest.h>

@interface WindTileDiskCache ()
@property (nonatomic, copy) NSString *versionDirectory;
@property (nonatomic, copy) NSString *activeForecastKey;
@property (nonatomic, strong) NSLock *lock;
@end

@implementation WindTileDiskCache

- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory
                        renderVersion:(NSString *)renderVersion {
    if (self = [super init]) {
        _versionDirectory = [cacheDirectory stringByAppendingPathComponent:renderVersion];
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)activateForecast:(NSString *)forecastKey {
    [self.lock lock];
    
    if ([self.activeForecastKey isEqualToString:forecastKey]) {
        [self.lock unlock];
        return;
    }
    
    // 创建目录
    NSString *activeDirectory = [self.versionDirectory stringByAppendingPathComponent:forecastKey];
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:activeDirectory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    
    if (error) {
        NSLog(@"[WindTileDiskCache] 创建目录失败: %@", error);
        [self.lock unlock];
        return;
    }
    
    // 清理旧预报时次
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:self.versionDirectory error:nil];
    for (NSString *item in contents) {
        if (![item isEqualToString:forecastKey]) {
            NSString *path = [self.versionDirectory stringByAppendingPathComponent:item];
            [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
            NSLog(@"[WindTileDiskCache] 清理旧缓存: %@", item);
        }
    }
    
    self.activeForecastKey = forecastKey;
    [self.lock unlock];
}

- (NSData *)readTileForForecast:(NSString *)forecastKey
                              z:(NSInteger)z
                              x:(NSInteger)x
                              y:(NSInteger)y {
    [self.lock lock];
    NSString *filePath = [self tilePathForForecast:forecastKey z:z x:x y:y];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        [self.lock unlock];
        return nil;
    }
    
    NSData *data = [NSData dataWithContentsOfFile:filePath];
    [self.lock unlock];
    
    return data.length > 0 ? data : nil;
}

- (void)writeTile:(NSData *)pngData
      forForecast:(NSString *)forecastKey
                z:(NSInteger)z
                x:(NSInteger)x
                y:(NSInteger)y {
    [self.lock lock];
    
    NSString *filePath = [self tilePathForForecast:forecastKey z:z x:x y:y];
    NSString *directory = [filePath stringByDeletingLastPathComponent];
    
    NSError *error = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&error];
    
    if (error) {
        NSLog(@"[WindTileDiskCache] 创建瓦片目录失败: %@", error);
        [self.lock unlock];
        return;
    }
    
    // 原子写入
    NSString *tempPath = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@".%@.tmp", [filePath lastPathComponent]]];
    [pngData writeToFile:tempPath atomically:YES];
    
    [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:filePath error:nil];
    
    [self.lock unlock];
}

- (NSString *)tilePathForForecast:(NSString *)forecastKey
                                z:(NSInteger)z
                                x:(NSInteger)x
                                y:(NSInteger)y {
    return [NSString stringWithFormat:@"%@/%@/%ld/%ld/%ld.png",
            self.versionDirectory, forecastKey, (long)z, (long)x, (long)y];
}

+ (NSString *)forecastKeyFromBaseUrl:(NSString *)baseUrl {
    // 匹配 /ecmwf-hres/{reference}/{valid}/wm_grid_257
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"/ecmwf-hres/(\\d{10})/(\\d{10})/wm_grid_257"
                                                                            options:0
                                                                              error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:baseUrl options:0 range:NSMakeRange(0, baseUrl.length)];
    
    if (match) {
        NSString *reference = [baseUrl substringWithRange:[match rangeAtIndex:1]];
        NSString *valid = [baseUrl substringWithRange:[match rangeAtIndex:2]];
        return [NSString stringWithFormat:@"%@_%@", reference, valid];
    }
    
    // 降级：SHA-256 哈希
    const char *str = [baseUrl UTF8String];
    unsigned char hash[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(str, (CC_LONG)strlen(str), hash);
    
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < 16; i++) {
        [hex appendFormat:@"%02x", hash[i]];
    }
    return hex;
}

@end
