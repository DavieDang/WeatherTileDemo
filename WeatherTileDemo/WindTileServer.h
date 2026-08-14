//
//  WindTileServer.h
//  WeatherTileDemo
//
//  本地 HTTP 瓦片服务器：接收 MapLibre 的瓦片请求，从 Windy 下载编码 JPEG，
//  解码成气象数据（风场/气压），着色后返回 PNG。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** 支持的气象图层类型（可扩展） */
typedef NSString * WeatherLayerType NS_TYPED_ENUM;
FOUNDATION_EXPORT WeatherLayerType const WeatherLayerTypeWind;      // 风场
FOUNDATION_EXPORT WeatherLayerType const WeatherLayerTypePressure;  // 海平面气压

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
 * 获取指定气象类型的瓦片 URL 模板
 * @param type 气象类型（WeatherLayerTypeWind / WeatherLayerTypePressure）
 * @return 如 "http://127.0.0.1:8080/wind/{z}/{x}/{y}.png"
 */
- (NSString *)tileTemplateForType:(WeatherLayerType)type;

/**
 * 停止服务器
 */
- (void)stop;

/**
 * 风场瓦片 URL 模板（兼容旧接口）
 */
@property (nonatomic, readonly) NSString *tileTemplate;

/**
 * 气压瓦片 URL 模板
 */
@property (nonatomic, readonly) NSString *pressureTileTemplate;

@end

NS_ASSUME_NONNULL_END
