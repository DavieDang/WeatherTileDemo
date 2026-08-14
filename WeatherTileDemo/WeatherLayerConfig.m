//
//  WeatherLayerConfig.m
//  WeatherTileDemo
//

#import "WeatherLayerConfig.h"

@implementation WeatherColorStop
@end

@implementation WeatherLegendConfig
@end

@implementation WeatherLayerConfig
@end

@interface WeatherLayerConfigManager ()
@property (nonatomic, strong) NSArray<WeatherLayerConfig *> *types;
@end

@implementation WeatherLayerConfigManager

+ (instancetype)shared {
    static WeatherLayerConfigManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[WeatherLayerConfigManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    if (self = [super init]) {
        [self loadConfig];
    }
    return self;
}

- (NSArray<WeatherLayerConfig *> *)allTypes {
    return self.types ?: @[];
}

- (WeatherLayerConfig *)configForType:(NSString *)typeId {
    for (WeatherLayerConfig *config in self.types) {
        if ([config.typeId isEqualToString:typeId]) {
            return config;
        }
    }
    return nil;
}

- (void)loadConfig {
    NSString *path = [[NSBundle mainBundle] pathForResource:@"WeatherTypes" ofType:@"json"];
    if (!path) {
        NSLog(@"[Config] ❌ 未找到 WeatherTypes.json");
        return;
    }
    
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
    if (error || !json[@"types"]) {
        NSLog(@"[Config] ❌ JSON 解析失败: %@", error);
        return;
    }
    
    NSMutableArray<WeatherLayerConfig *> *configs = [NSMutableArray array];
    for (NSDictionary *dict in json[@"types"]) {
        WeatherLayerConfig *config = [self parseLayerConfig:dict];
        if (config) {
            [configs addObject:config];
        }
    }
    self.types = configs;
    NSLog(@"[Config] ✅ 加载 %lu 个气象图层配置", (unsigned long)configs.count);
}

- (WeatherLayerConfig *)parseLayerConfig:(NSDictionary *)dict {
    if (!dict[@"id"] || !dict[@"pathPrefix"]) {
        return nil;
    }
    WeatherLayerConfig *config = [[WeatherLayerConfig alloc] init];
    config.typeId = dict[@"id"];
    config.displayName = dict[@"displayName"] ?: config.typeId;
    config.pathPrefix = dict[@"pathPrefix"];
    config.remoteSuffix = dict[@"remoteSuffix"] ?: @"";
    config.dataType = dict[@"dataType"] ?: @"scalar";
    config.scalarScale = [dict[@"scalarScale"] floatValue] ?: 1.0f;
    config.enhanceContrast = [dict[@"enhanceContrast"] boolValue];
    
    // 图例
    NSDictionary *legendDict = dict[@"legend"];
    if (legendDict) {
        WeatherLegendConfig *legend = [[WeatherLegendConfig alloc] init];
        legend.title = legendDict[@"title"] ?: @"";
        legend.labels = legendDict[@"labels"] ?: @[];
        NSMutableArray<UIColor *> *colors = [NSMutableArray array];
        for (NSString *hex in legendDict[@"colors"]) {
            UIColor *color = [self colorFromHex:hex];
            if (color) [colors addObject:color];
        }
        legend.colors = colors;
        config.legend = legend;
    }
    
    // 色阶
    NSMutableArray<WeatherColorStop *> *stops = [NSMutableArray array];
    for (NSDictionary *stopDict in dict[@"colorStops"]) {
        WeatherColorStop *stop = [[WeatherColorStop alloc] init];
        stop.value = [stopDict[@"value"] floatValue];
        stop.color = [self colorFromHex:stopDict[@"color"]];
        if (stop.color) {
            [stops addObject:stop];
        }
    }
    config.colorStops = stops;
    
    return config;
}

- (UIColor *)colorFromHex:(NSString *)hex {
    if (!hex || hex.length < 7) {
        return nil;
    }
    NSString *clean = [hex stringByReplacingOccurrencesOfString:@"#" withString:@""];
    NSScanner *scanner = [NSScanner scannerWithString:clean];
    unsigned int value = 0;
    if (![scanner scanHexInt:&value]) {
        return nil;
    }
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0f
                           green:((value >> 8) & 0xFF) / 255.0f
                            blue:(value & 0xFF) / 255.0f
                           alpha:1.0f];
}

@end
