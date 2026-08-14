//
//  WindRasterLayerRenderer.m
//  WeatherTileDemo
//

#import "WindRasterLayerRenderer.h"

static NSString *const kWaterLayerId = @"water";
static NSString *const kCoastlineLayerId = @"weather-coastline";
static NSString *const kOpenMapTilesSourceId = @"openmaptiles";

@interface WindRasterLayerRenderer ()
@property (nonatomic, copy) NSString *tileTemplate;
@property (nonatomic, copy) NSString *type;
@end

@implementation WindRasterLayerRenderer

- (instancetype)initWithTileTemplate:(NSString *)tileTemplate type:(NSString *)type {
    if (self = [super init]) {
        _tileTemplate = tileTemplate;
        _type = type.length > 0 ? type : @"wind";
    }
    return self;
}

- (void)addToMapView:(MLNMapView *)mapView {
    MLNStyle *style = mapView.style;
    if (!style) {
        NSLog(@"[WindRasterLayerRenderer] MapLibre style 未就绪");
        return;
    }
    
    NSString *sourceId = [NSString stringWithFormat:@"%@-tiles", self.type];
    NSString *layerId = [NSString stringWithFormat:@"%@-layer", self.type];
    
    // 添加栅格源
    if (![style sourceWithIdentifier:sourceId]) {
        MLNRasterTileSource *source = [[MLNRasterTileSource alloc] initWithIdentifier:sourceId
                                                                     tileURLTemplates:@[self.tileTemplate]
                                                                              options:@{
            MLNTileSourceOptionMinimumZoomLevel: @0,
            MLNTileSourceOptionMaximumZoomLevel: @4,
            // ✅ 删除 TileSize 配置 - 让 MapLibre 使用默认的 1:1 映射
            MLNTileSourceOptionAttributionInfos: @[
                [[MLNAttributionInfo alloc] initWithTitle:[[NSAttributedString alloc] initWithString:@"Wind data © Windy.com / ECMWF"]
                                                      URL:nil]
            ]
        }];
        [style addSource:source];
    }
    
    // 添加栅格图层
    if (![style layerWithIdentifier:layerId]) {
        MLNRasterStyleLayer *windLayer = [[MLNRasterStyleLayer alloc] initWithIdentifier:layerId
                                                                                   source:[style sourceWithIdentifier:sourceId]];
        windLayer.rasterOpacity = [NSExpression expressionForConstantValue:@1.0];
        windLayer.rasterResamplingMode = [NSExpression expressionForConstantValue:@"linear"];
        windLayer.rasterFadeDuration = [NSExpression expressionForConstantValue:@0.18];
        
        // 插入到合适的图层顺序
        NSArray<__kindof MLNStyleLayer *> *layers = style.layers;
        
        // 找到 water 层之后的第一个 line/symbol 层
        NSInteger waterIndex = [self indexOfLayerWithIdentifier:kWaterLayerId inLayers:layers];
        NSInteger startIndex = (waterIndex != NSNotFound) ? waterIndex + 1 : 0;
        
        MLNStyleLayer *firstReferenceLayer = nil;
        for (NSInteger i = startIndex; i < layers.count; i++) {
            MLNStyleLayer *layer = layers[i];
            if ([layer isKindOfClass:[MLNLineStyleLayer class]] ||
                [layer isKindOfClass:[MLNSymbolStyleLayer class]]) {
                firstReferenceLayer = layer;
                break;
            }
        }
        
        if (firstReferenceLayer) {
            [style insertLayer:windLayer belowLayer:firstReferenceLayer];
        } else {
            [style addLayer:windLayer];
        }
        
        NSLog(@"[WindRasterLayerRenderer] %@ 图层已添加", self.type);
    }
    
    // 添加海岸线（增强对比）
    if (![style layerWithIdentifier:kCoastlineLayerId] && [style sourceWithIdentifier:kOpenMapTilesSourceId]) {
        MLNLineStyleLayer *coastline = [[MLNLineStyleLayer alloc] initWithIdentifier:kCoastlineLayerId
                                                                               source:[style sourceWithIdentifier:kOpenMapTilesSourceId]];
        coastline.sourceLayerIdentifier = kWaterLayerId;
        coastline.lineColor = [NSExpression expressionForConstantValue:[UIColor colorWithRed:0x26/255.0
                                                                                        green:0x36/255.0
                                                                                         blue:0x4A/255.0
                                                                                        alpha:1.0]];
        coastline.lineOpacity = [NSExpression expressionForConstantValue:@1.0];
        coastline.lineWidth = [NSExpression expressionForConstantValue:@1.0];
        coastline.lineJoin = [NSExpression expressionForConstantValue:@"round"];
        
        MLNStyleLayer *windLayerRef = [style layerWithIdentifier:layerId];
        if (windLayerRef) {
            [style insertLayer:coastline aboveLayer:windLayerRef];
        }
    }
}

- (void)removeFromMapView:(MLNMapView *)mapView {
    MLNStyle *style = mapView.style;
    if (!style) {
        return;
    }
    NSString *layerId = [NSString stringWithFormat:@"%@-layer", self.type];
    NSString *sourceId = [NSString stringWithFormat:@"%@-tiles", self.type];
    
    MLNStyleLayer *layer = [style layerWithIdentifier:layerId];
    if (layer) {
        [style removeLayer:layer];
    }
    id source = [style sourceWithIdentifier:sourceId];
    if (source) {
        [style removeSource:source];
    }
    NSLog(@"[WindRasterLayerRenderer] %@ 图层已移除", self.type);
}

- (NSInteger)indexOfLayerWithIdentifier:(NSString *)identifier inLayers:(NSArray<MLNStyleLayer *> *)layers {
    for (NSInteger i = 0; i < layers.count; i++) {
        if ([layers[i].identifier isEqualToString:identifier]) {
            return i;
        }
    }
    return NSNotFound;
}

@end
