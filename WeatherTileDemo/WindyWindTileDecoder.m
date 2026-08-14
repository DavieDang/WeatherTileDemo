//
//  WindyWindTileDecoder.m
//  WeatherTileDemo
//

#import "WindyWindTileDecoder.h"
#import <math.h>

static const NSInteger kEncodedWidth = 257;
static const NSInteger kEncodedHeight = 265;
static const NSInteger kTileSize = 256;
static const NSInteger kHeaderRows = 8;
static const NSInteger kMissingBlueThreshold = 192;

typedef struct {
    float rMin;
    float rMax;
    float gMin;
    float gMax;
} Header;

@implementation WindyWindTileDecoder

+ (WindField *)decodePixels:(uint32_t *)pixels width:(NSInteger)width height:(NSInteger)height {
    NSAssert(width == kEncodedWidth && height == kEncodedHeight, 
             @"期望 257x265 wm_grid 瓦片，实际 %ldx%ld", (long)width, (long)height);
    
    // 解码头部
    Header header = [self decodeHeader:pixels width:width];
    
    // 分配风场数组
    WindField *field = (WindField *)malloc(sizeof(WindField));
    field->width = kTileSize;
    field->height = kTileSize;
    field->u = (float *)malloc(kTileSize * kTileSize * sizeof(float));
    field->v = (float *)malloc(kTileSize * kTileSize * sizeof(float));
    
    float rStep = (header.rMax - header.rMin) / 255.0f;
    float gStep = (header.gMax - header.gMin) / 255.0f;
    
    // 统计变量
    NSInteger nanCount = 0;
    NSInteger validCount = 0;
    float minSpeed = INFINITY;
    float maxSpeed = -INFINITY;
    
    // 解码数据区：从 row 8 开始（跳过前 8 行头部），从 col 0 开始读取 256×256
    for (NSInteger y = 0; y < kTileSize; y++) {
        NSInteger sourceOffset = (y + kHeaderRows) * width;
        NSInteger targetOffset = y * kTileSize;
        
        for (NSInteger x = 0; x < kTileSize; x++) {
            // 与 Android 一致：从 col 0 开始读取（读取 col 0..255）
            uint32_t pixel = pixels[sourceOffset + x];
            
            // 提取 RGB (与 Android 完全一致的方式)
            uint8_t red = (pixel >> 16) & 0xFF;
            uint8_t green = (pixel >> 8) & 0xFF;
            uint8_t blue = pixel & 0xFF;
            
            NSInteger index = targetOffset + x;
            
            if (blue >= kMissingBlueThreshold) {
                field->u[index] = NAN;
                field->v[index] = NAN;
                nanCount++;
            } else {
                field->u[index] = red * rStep + header.rMin;
                field->v[index] = green * gStep + header.gMin;
                
                // 统计风速
                float speed = sqrtf(field->u[index] * field->u[index] + field->v[index] * field->v[index]);
                if (speed < minSpeed) minSpeed = speed;
                if (speed > maxSpeed) maxSpeed = speed;
                validCount++;
            }
        }
    }
    
    // 诊断日志
    NSInteger totalPixels = kTileSize * kTileSize;
    float validPercent = (float)validCount / totalPixels * 100.0f;
    NSLog(@"[DECODER] 📊 瓦片统计:");
    NSLog(@"[DECODER]   总像素: %ld", (long)totalPixels);
    NSLog(@"[DECODER]   有效: %ld (%.1f%%)", (long)validCount, validPercent);
    NSLog(@"[DECODER]   缺测: %ld (%.1f%%)", (long)nanCount, (float)nanCount / totalPixels * 100.0f);
    if (validCount > 0) {
        NSLog(@"[DECODER]   风速范围: %.2f ~ %.2f m/s", minSpeed, maxSpeed);
    } else {
        NSLog(@"[DECODER]   ⚠️  全部缺测！");
    }
    
    return field;
}

+ (Header)decodeHeader:(uint32_t *)pixels width:(NSInteger)width {
    // 头部的 28 字节分散在第 5 行（index=4），每隔 4 像素一个，从第 3 个像素开始
    // 完全参照 Android 实现
    
    // ⭐ 诊断：检查头部行的前几个像素
    NSLog(@"[DECODER] 📍 头部诊断（row 4, 前10个像素）:");
    for (int i = 0; i < 10; i++) {
        uint32_t p = pixels[width * 4 + i];
        NSLog(@"  [4,%d] = 0x%08X", i, p);
    }
    
    uint8_t bytes[28];
    NSInteger pixelIndex = width * 4 + 2;
    NSLog(@"[DECODER] 📍 pixelIndex = %ld (应该是 %ld * 4 + 2 = %ld)", 
          (long)pixelIndex, (long)width, (long)(width * 4 + 2));
    
    for (NSInteger i = 0; i < 28; i++) {
        uint32_t pixel = pixels[pixelIndex + i * 4];
        uint8_t red = (pixel >> 16) & 0xFF;
        uint8_t green = (pixel >> 8) & 0xFF;
        uint8_t blue = pixel & 0xFF;
        
        // Android 实现的位打包方式：
        // val packed = ((red / 64f).roundToInt() shl 6) or
        //             ((green / 16f).roundToInt() shl 2) or
        //             (blue / 64f).roundToInt()
        int redPacked = (int)roundf(red / 64.0f) & 0x3;    // 2 bits
        int greenPacked = (int)roundf(green / 16.0f) & 0xF; // 4 bits
        int bluePacked = (int)roundf(blue / 64.0f) & 0x3;   // 2 bits
        
        bytes[i] = (uint8_t)((redPacked << 6) | (greenPacked << 2) | bluePacked);
    }
    
    // 解析 7 个 float (Little Endian)
    float values[7];
    
    // DEBUG: 打印前3个头部像素和解析结果
    NSLog(@"[DECODER] 前3个头部像素:");
    for (int i = 0; i < 3; i++) {
        uint32_t p = pixels[pixelIndex + i * 4];
        uint8_t r = (p >> 16) & 0xFF;
        uint8_t g = (p >> 8) & 0xFF;
        uint8_t b = p & 0xFF;
        NSLog(@"  [%d] RGB(%d,%d,%d) -> byte=0x%02X", i, r, g, b, bytes[i]);
    }
    memcpy(values, bytes, 28);
    
    Header header;
    header.rMin = values[0];
    header.rMax = values[1];
    header.gMin = values[2];
    header.gMax = values[3];
    
    
    // 检查头部值是否有效
    BOOL valid = isfinite(header.rMin) && isfinite(header.rMax) && header.rMax > header.rMin &&
                 isfinite(header.gMin) && isfinite(header.gMax) && header.gMax > header.gMin;
    
    if (!valid) {
        NSLog(@"[DECODER] ⚠️  头部解析失败（rMin=%.2f rMax=%.2f gMin=%.2f gMax=%.2f），使用默认范围",
              header.rMin, header.rMax, header.gMin, header.gMax);
        // Windy 典型的风速范围（根据全球风速统计）
        header.rMin = -20.0f;  // U 分量最小值
        header.rMax = 20.0f;   // U 分量最大值
        header.gMin = -20.0f;  // V 分量最小值
        header.gMax = 20.0f;   // V 分量最大值
    }
    
    NSLog(@"[DECODER] Header decoded: rMin=%.2f rMax=%.2f gMin=%.2f gMax=%.2f %@",
          header.rMin, header.rMax, header.gMin, header.gMax,
          valid ? @"✅" : @"⚠️ (using defaults)");
    
    return header;
}

+ (WindFieldHeader)decodeHeaderFromPixels:(uint32_t *)pixels width:(NSInteger)width {
    Header header = [self decodeHeader:pixels width:width];
    WindFieldHeader result;
    result.rMin = header.rMin;
    result.rMax = header.rMax;
    result.gMin = header.gMin;
    result.gMax = header.gMax;
    return result;
}

+ (WindField *)decodeDataPixels:(uint32_t *)pixels
                          width:(NSInteger)width
                         height:(NSInteger)height
                         header:(WindFieldHeader)header {
    // 数据区（已裁剪头部色条），从 row 0 开始读取 256×256
    WindField *field = (WindField *)malloc(sizeof(WindField));
    field->width = kTileSize;
    field->height = kTileSize;
    field->u = (float *)malloc(kTileSize * kTileSize * sizeof(float));
    field->v = (float *)malloc(kTileSize * kTileSize * sizeof(float));
    
    float rStep = (header.rMax - header.rMin) / 255.0f;
    float gStep = (header.gMax - header.gMin) / 255.0f;
    
    NSInteger nanCount = 0;
    NSInteger validCount = 0;
    float minSpeed = INFINITY;
    float maxSpeed = -INFINITY;
    
    for (NSInteger y = 0; y < kTileSize; y++) {
        NSInteger sourceOffset = y * width;
        NSInteger targetOffset = y * kTileSize;
        for (NSInteger x = 0; x < kTileSize; x++) {
            uint32_t pixel = pixels[sourceOffset + x];
            uint8_t red = (pixel >> 16) & 0xFF;
            uint8_t green = (pixel >> 8) & 0xFF;
            uint8_t blue = pixel & 0xFF;
            NSInteger index = targetOffset + x;
            if (blue >= kMissingBlueThreshold) {
                field->u[index] = NAN;
                field->v[index] = NAN;
                nanCount++;
            } else {
                field->u[index] = red * rStep + header.rMin;
                field->v[index] = green * gStep + header.gMin;
                float speed = sqrtf(field->u[index] * field->u[index] +
                                    field->v[index] * field->v[index]);
                if (speed < minSpeed) minSpeed = speed;
                if (speed > maxSpeed) maxSpeed = speed;
                validCount++;
            }
        }
    }
    
    NSLog(@"[DECODER] 📊 数据区解码完成: 有效=%ld 缺测=%ld 风速范围=%.2f~%.2f m/s",
          (long)validCount, (long)nanCount, minSpeed, maxSpeed);
    
    return field;
}

@end
