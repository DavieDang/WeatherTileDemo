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

typedef struct {
    float rMin;
    float rMax;
    float gMin;
    float gMax;
} WindFieldHeader;

@interface WindyWindTileDecoder : NSObject

/**
 * 解码 Windy 编码的 JPEG 像素为风场
 * @param pixels ARGB 像素数组（257x265）
 * @param width 图像宽度（应为 257）
 * @param height 图像高度（应为 265）
 * @return 风场结构体（256x256），调用者负责释放 u/v 数组和结构体本身
 */
+ (WindField *)decodePixels:(uint32_t *)pixels width:(NSInteger)width height:(NSInteger)height;

/**
 * 从完整 257x265 像素中读取头部通道范围参数（row 4 编码）
 * @param pixels 完整 ARGB 像素数组（257x265，已按 JPEG 顶部为 row 0 排布）
 * @param width 图像宽度（应为 257）
 * @return 头部参数；解析失败时返回默认 ±20 m/s
 */
+ (WindFieldHeader)decodeHeaderFromPixels:(uint32_t *)pixels width:(NSInteger)width;

/**
 * 从已裁剪的数据区像素（257x257，不含头部色条）解码 256x256 风场
 * @param pixels 数据区 ARGB 像素数组（row 0 为原始 JPEG row 8）
 * @param width 数据区宽度（应为 257）
 * @param height 数据区高度（应为 257）
 * @param header 头部通道范围参数
 * @return 风场结构体（256x256），调用者负责释放 u/v 数组和结构体本身
 */
+ (WindField *)decodeDataPixels:(uint32_t *)pixels
                          width:(NSInteger)width
                         height:(NSInteger)height
                         header:(WindFieldHeader)header;

/**
 * 从已裁剪的数据区像素（257x257）解码标量场（256x256）
 * 数值由 R 通道编码，范围由 header 的 rMin/rMax 给出，可附加归一化系数
 * @param pixels 数据区 ARGB 像素数组（row 0 为原始 JPEG row 8）
 * @param width 数据区宽度（应为 257）
 * @param height 数据区高度（应为 257）
 * @param header 头部通道范围参数
 * @param scale 归一化系数（如气压头部 hPa×100 时传 0.01；无缩放传 1.0）
 * @return 标量数组（256x256 个 float，缺测为 NAN），调用者负责 free
 */
+ (float *)decodeScalarDataPixels:(uint32_t *)pixels
                            width:(NSInteger)width
                           height:(NSInteger)height
                           header:(WindFieldHeader)header
                            scale:(float)scale;

@end

NS_ASSUME_NONNULL_END
