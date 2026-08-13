//
//  WindRasterLayerRenderer.h
//  WeatherTileDemo
//
//  将风场瓦片添加为 MapLibre RasterLayer
//

#import <Foundation/Foundation.h>
@import MapLibre;

NS_ASSUME_NONNULL_BEGIN

@interface WindRasterLayerRenderer : NSObject

/**
 * 初始化渲染器
 * @param tileTemplate 瓦片 URL 模板，如 "http://127.0.0.1:8080/wind/{z}/{x}/{y}.png"
 */
- (instancetype)initWithTileTemplate:(NSString *)tileTemplate;

/**
 * 添加图层到地图
 */
- (void)addToMapView:(MLNMapView *)mapView;

@end

NS_ASSUME_NONNULL_END
