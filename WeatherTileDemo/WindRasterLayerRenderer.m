//
//  WindRasterLayerRenderer.m
//  WeatherTileDemo
//

#import "WindRasterLayerRenderer.h"

static NSString *const kSourceId = @"wind-speed-tiles";
static NSString *const kLayerId = @"wind-speed-layer";
static NSString *const kWaterLayerId = @"water";
static NSString *const kCoastlineLayerId = @"weather-coastline";
static NSString *const kOpenMapTilesSourceId = @"openmaptiles";

@interface WindRasterLayerRenderer ()
@property (nonatomic, copy) NSString *tileTemplate;
@end

@implementation WindRasterLayerRenderer

- (instancetype)initWithTileTemplate:(NSString *)tileTemplate {
    if (self = [super init]) {
        _tileTemplate = tileTemplate;
    }
    return self;
}

- (void)addToMapView:(MLNMapView *)mapView {
    MLNStyle *style = mapView.style;
    if (!style) {
        NSLog(@"[WindRasterLayerRenderer] MapLibre style 未就绪");
        return;
    }
    
    // 添加栅格源
    if (![style sourceWithIdentifier:kSourceId]) {
        MLNRasterTileSource *source = [[MLNRasterTileSource alloc] initWithIdentifier:kSourceId
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
    if (![style layerWithIdentifier:kLayerId]) {
        MLNRasterStyleLayer *windLayer = [[MLNRasterStyleLayer alloc] initWithIdentifier:kLayerId
                                                                                   source:[style sourceWithIdentifier:kSourceId]];
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
        
        NSLog(@"[WindRasterLayerRenderer] 风场图层已添加");
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
        
        MLNStyleLayer *windLayerRef = [style layerWithIdentifier:kLayerId];
        if (windLayerRef) {
            [style insertLayer:coastline aboveLayer:windLayerRef];
        }
    }
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
