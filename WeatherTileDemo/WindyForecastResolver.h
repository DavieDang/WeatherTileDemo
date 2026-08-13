//
//  WindyForecastResolver.h
//  WeatherTileDemo
//
//  从 Windy manifest 解析最新 ECMWF HRES 预报时次
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface WindyForecastResolver : NSObject

/**
 * 解析最新预报时次的 base URL
 * @return 如 "https://ims.windy.com/im/v3.0/forecast/ecmwf-hres/2026080912/2026080915/wm_grid_257"
 */
- (NSString *)resolveBaseUrl;

@end

NS_ASSUME_NONNULL_END
