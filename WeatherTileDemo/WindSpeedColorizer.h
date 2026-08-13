//
//  WindSpeedColorizer.h
//  WeatherTileDemo
//
//  将 u/v 风场转换为彩色可视化图像
//

#import <Foundation/Foundation.h>
#import "WindyWindTileDecoder.h"

NS_ASSUME_NONNULL_BEGIN

@interface WindSpeedColorizer : NSObject

/**
 * 将风场着色为 ARGB 像素数组
 * @param field 风场数据
 * @return ARGB 像素数组，调用者负责释放
 */
+ (uint32_t *)colorizeField:(WindField *)field;

@end

NS_ASSUME_NONNULL_END
