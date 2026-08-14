//
//  WeatherLayerConfig.h
//  WeatherTileDemo
//
//  气象图层配置模型：从 WeatherTypes.json 加载，驱动类型切换/解码/着色/图例
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/** 单个色阶点（数值 → 颜色） */
@interface WeatherColorStop : NSObject
@property (nonatomic, assign) float value;
@property (nonatomic, strong) UIColor *color;
@end

/** 图例配置（标题 / 色带 / 标签） */
@interface WeatherLegendConfig : NSObject
@property (nonatomic, copy) NSString *title;
@property (nonatomic, strong) NSArray<UIColor *> *colors;
@property (nonatomic, strong) NSArray<NSString *> *labels;
@end

/** 单个气象图层配置 */
@interface WeatherLayerConfig : NSObject

/** 类型唯一标识，如 "wind" / "pressure" */
@property (nonatomic, copy) NSString *typeId;
/** 显示名称，如 "风速" / "气压" */
@property (nonatomic, copy) NSString *displayName;
/** 本地路由前缀，如 "wind"（URL: /wind/{z}/{x}/{y}.png） */
@property (nonatomic, copy) NSString *pathPrefix;
/** Windy 远程瓦片后缀，如 "wind-surface.jpg" */
@property (nonatomic, copy) NSString *remoteSuffix;
/** 数据类型："vector"（R/G 双通道）或 "scalar"（R 单通道） */
@property (nonatomic, copy) NSString *dataType;
/** 标量归一化系数（气压头部 hPa×100 → 0.01），vector 类型为 1.0 */
@property (nonatomic, assign) float scalarScale;
/** 是否启用 Windy 对比度增强（风场 true，气压 false） */
@property (nonatomic, assign) BOOL enhanceContrast;
/** 图例配置 */
@property (nonatomic, strong) WeatherLegendConfig *legend;
/** 色阶点数组 */
@property (nonatomic, strong) NSArray<WeatherColorStop *> *colorStops;

@end

/** 配置管理器：加载并访问全部气象图层配置 */
@interface WeatherLayerConfigManager : NSObject

+ (instancetype)shared;

/** 全部气象图层配置（按 JSON 顺序） */
@property (nonatomic, readonly) NSArray<WeatherLayerConfig *> *allTypes;

/** 按类型 id 查找配置 */
- (WeatherLayerConfig *)configForType:(NSString *)typeId;

@end

NS_ASSUME_NONNULL_END
