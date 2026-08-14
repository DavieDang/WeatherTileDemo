//
//  WeatherColorizer.h
//  WeatherTileDemo
//
//  通用气象数据着色器：由配置的色阶点（WeatherColorStop）驱动，
//  支持可选的 Windy 对比度增强，供风速/气压/未来类型共用。
//

#import <Foundation/Foundation.h>
#import "WeatherLayerConfig.h"

NS_ASSUME_NONNULL_BEGIN

@interface WeatherColorizer : NSObject

/**
 * 将数值数组着色为 ARGB 像素数组
 * @param values 数值数组（缺测为 NAN → 透明）
 * @param size 像素数量
 * @param stops 色阶点数组（升序）
 * @param enhance 是否启用 Windy 对比度增强
 * @param alpha 叠加透明度（0-255）
 * @return ARGB 像素数组，调用者负责释放
 */
+ (uint32_t *)colorizeValues:(float *)values
                        size:(NSInteger)size
                      stops:(NSArray<WeatherColorStop *> *)stops
                     enhance:(BOOL)enhance
                       alpha:(uint8_t)alpha;

/**
 * 将单个数值映射为 ARGB 颜色（0xAARRGGBB）
 */
+ (uint32_t)colorForValue:(float)value
                    stops:(NSArray<WeatherColorStop *> *)stops
                  enhance:(BOOL)enhance
                    alpha:(uint8_t)alpha;

@end

NS_ASSUME_NONNULL_END
