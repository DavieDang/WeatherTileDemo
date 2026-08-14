//
//  WindRasterLayerRenderer.h
//  WeatherTileDemo
//
//  将气象瓦片添加为 MapLibre RasterLayer
//

#import <Foundation/Foundation.h>
@import MapLibre;

NS_ASSUME_NONNULL_BEGIN

@interface WindRasterLayerRenderer : NSObject

/**
 * 初始化渲染器
 * @param tileTemplate 瓦片 URL 模板，如 "http://127.0.0.1:8080/wind/{z}/{x}/{y}.png"
 * @param type 气象类型标识（用于图层/源 ID，如 "wind" / "pressure"）
 */
- (instancetype)initWithTileTemplate:(NSString *)tileTemplate type:(NSString *)type;

/**
 * 添加图层到地图
 */
- (void)addToMapView:(MLNMapView *)mapView;

/**
 * 从地图移除图层和源
 */
- (void)removeFromMapView:(MLNMapView *)mapView;

@end

NS_ASSUME_NONNULL_END
