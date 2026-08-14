//
//  WindSpeedColorizer.m
//  WeatherTileDemo
//

#import "WindSpeedColorizer.h"
#import <math.h>

typedef struct {
    float speed;
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} ColorStop;

static const uint8_t kOverlayAlpha = 217;

// Windy 风速色阶表（20 级）
static const ColorStop kStops[] = {
    {0.0f,  98, 113, 183},
    {1.0f,  57,  97, 159},
    {3.0f,  74, 148, 169},
    {5.0f,  77, 141, 123},
    {7.0f,  83, 165,  83},
    {9.0f,  53, 159,  53},
    {11.0f, 167, 157,  81},
    {13.0f, 159, 127,  58},
    {15.0f, 161, 108,  92},
    {17.0f, 129,  58,  78},
    {19.0f, 175,  80, 136},
    {21.0f, 117,  74, 147},
    {24.0f, 109,  97, 163},
    {27.0f,  68, 105, 141},
    {29.0f,  92, 144, 152},
    {36.0f, 125,  68, 165},
    {46.0f, 231, 215, 215},
    {51.0f, 219, 212, 135},
    {77.0f, 205, 202, 112},
    {104.0f, 128, 128, 128},
};
static const NSInteger kStopsCount = sizeof(kStops) / sizeof(ColorStop);

@implementation WindSpeedColorizer

+ (uint32_t *)colorizeField:(WindField *)field {
    NSInteger size = field->width * field->height;
    uint32_t *pixels = (uint32_t *)malloc(size * sizeof(uint32_t));
    
    for (NSInteger i = 0; i < size; i++) {
        float u = field->u[i];
        float v = field->v[i];
        float speed = sqrtf(u * u + v * v);
        pixels[i] = [self colorForSpeed:speed];
    }
    
    return pixels;
}

+ (uint32_t)colorForSpeed:(float)speed {
    if (isnan(speed)) {
        return 0; // 透明
    }
    
    // 查找色阶区间
    ColorStop lower, upper;
    
    if (speed <= kStops[0].speed) {
        lower = upper = kStops[0];
    } else if (speed >= kStops[kStopsCount - 1].speed) {
        lower = upper = kStops[kStopsCount - 1];
    } else {
        NSInteger upperIndex = 0;
        for (NSInteger i = 0; i < kStopsCount; i++) {
            if (speed <= kStops[i].speed) {
                upperIndex = i;
                break;
            }
        }
        lower = kStops[upperIndex - 1];
        upper = kStops[upperIndex];
    }
    
    // 线性插值
    float fraction = 0.0f;
    if (upper.speed > lower.speed) {
        fraction = (speed - lower.speed) / (upper.speed - lower.speed);
    }
    
    uint8_t red = [self lerp:lower.red to:upper.red fraction:fraction];
    uint8_t green = [self lerp:lower.green to:upper.green fraction:fraction];
    uint8_t blue = [self lerp:lower.blue to:upper.blue fraction:fraction];
    
    // 对比度增强
    uint8_t enhanced[3];
    [self enhanceContrast:red green:green blue:blue output:enhanced];
    
    // 打包 ARGB (0xAARRGGBB 格式)
    return (kOverlayAlpha << 24) | (enhanced[0] << 16) | (enhanced[1] << 8) | enhanced[2];
}

+ (uint8_t)lerp:(uint8_t)from to:(uint8_t)to fraction:(float)fraction {
    float result = from + (to - from) * fraction;
    return (uint8_t)fmaxf(0.0f, fminf(255.0f, result));
}

+ (void)enhanceContrast:(uint8_t)r green:(uint8_t)g blue:(uint8_t)b output:(uint8_t *)output {
    // ✅ 完全参照 Android 实现
    // Boost saturation and mid-tone separation while retaining the Windy hue ordering.
    
    float luminance = 0.299f * r + 0.587f * g + 0.114f * b;
    
    for (int i = 0; i < 3; i++) {
        uint8_t channel = (i == 0) ? r : (i == 1) ? g : b;
        
        // Android 的原始算法（1.55x 饱和度 + 1.20x 对比度 + 0.82x 衰减）
        float saturated = luminance + (channel - luminance) * 1.55f;
        float contrasted = (saturated - 128.0f) * 1.20f + 128.0f;
        output[i] = (uint8_t)fmaxf(0.0f, fminf(255.0f, contrasted * 0.82f));
    }
}

@end
