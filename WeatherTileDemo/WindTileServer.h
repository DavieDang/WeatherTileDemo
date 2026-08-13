//
//  WindTileServer.h
//  WeatherTileDemo
//
//  本地 HTTP 瓦片服务器：接收 MapLibre 的瓦片请求，从 Windy 下载编码 JPEG，
//  解码成 u/v 风场，着色后返回 PNG。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WindTileServer : NSObject

/**
 * 初始化瓦片服务器
 * @param cacheDirectory 磁盘缓存目录
 */
- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory;

/**
 * 启动服务器（绑定 127.0.0.1 随机端口）
 * @return 瓦片 URL 模板，如 "http://127.0.0.1:8080/wind/{z}/{x}/{y}.png"
 */
- (NSString *)start;

/**
 * 停止服务器
 */
- (void)stop;

/**
 * 瓦片 URL 模板
 */
@property (nonatomic, readonly) NSString *tileTemplate;

@end

NS_ASSUME_NONNULL_END
