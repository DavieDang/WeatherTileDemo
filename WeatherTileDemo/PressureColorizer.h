//
//  PressureColorizer.h
//  WeatherTileDemo
//
//  将海平面气压值转换为 Windy 风格彩色可视化图像
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface PressureColorizer : NSObject

/**
 * 将气压数组着色为 ARGB 像素数组
 * @param pressures 气压值数组（hPa，缺测为 NAN）
 * @param size 像素数量
 * @return ARGB 像素数组，调用者负责释放
 */
+ (uint32_t *)colorizePressure:(float *)pressures size:(NSInteger)size;

/**
 * 将单个气压值映射为 ARGB 颜色（0xAARRGGBB）
 * @param pressure 气压值（hPa）
 */
+ (uint32_t)colorForPressure:(float)pressure;

@end

NS_ASSUME_NONNULL_END
