//
//  WindTileDiskCache.h
//  WeatherTileDemo
//
//  按预报时次持久化已渲染 PNG 瓦片
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WindTileDiskCache : NSObject

/**
 * 初始化磁盘缓存
 * @param cacheDirectory 缓存根目录
 * @param renderVersion 渲染版本（色阶变化时递增）
 */
- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory
                        renderVersion:(NSString *)renderVersion;

/**
 * 激活指定预报时次（清理其他时次）
 */
- (void)activateForecast:(NSString *)forecastKey;

/**
 * 读取瓦片
 */
- (NSData * _Nullable)readTileForForecast:(NSString *)forecastKey
                                        z:(NSInteger)z
                                        x:(NSInteger)x
                                        y:(NSInteger)y;

/**
 * 写入瓦片
 */
- (void)writeTile:(NSData *)pngData
      forForecast:(NSString *)forecastKey
                z:(NSInteger)z
                x:(NSInteger)x
                y:(NSInteger)y;

/**
 * 从 base URL 提取预报 key
 */
+ (NSString *)forecastKeyFromBaseUrl:(NSString *)baseUrl;

@end

NS_ASSUME_NONNULL_END
