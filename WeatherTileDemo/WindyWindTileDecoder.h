//
//  WindyWindTileDecoder.h
//  WeatherTileDemo
//
//  解码 Windy wm_grid_257 编码 JPEG（257x265）为 u/v 风场数据
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef struct {
    NSInteger width;
    NSInteger height;
    float *u;  // 东西向分量 (m/s)
    float *v;  // 南北向分量 (m/s)
} WindField;

@interface WindyWindTileDecoder : NSObject

/**
 * 解码 Windy 编码的 JPEG 像素为风场
 * @param pixels ARGB 像素数组（257x265）
 * @param width 图像宽度（应为 257）
 * @param height 图像高度（应为 265）
 * @return 风场结构体（256x256），调用者负责释放 u/v 数组和结构体本身
 */
+ (WindField *)decodePixels:(uint32_t *)pixels width:(NSInteger)width height:(NSInteger)height;

@end

NS_ASSUME_NONNULL_END
