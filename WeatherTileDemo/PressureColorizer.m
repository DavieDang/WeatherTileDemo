//
//  PressureColorizer.m
//  WeatherTileDemo
//

#import "PressureColorizer.h"
#import <math.h>

typedef struct {
    float pressure;  // hPa
    uint8_t red;
    uint8_t green;
    uint8_t blue;
} PressureStop;

static const uint8_t kOverlayAlpha = 217;

// Windy 海平面气压色阶（hPa → RGB），低气压到高气压
static const PressureStop kStops[] = {
    {940.0f, 120,  20, 150},
    {955.0f,  70,  40, 180},
    {970.0f,  40,  80, 205},
    {985.0f,  45, 130, 215},
    {995.0f,  60, 170, 190},
    {1000.0f, 90, 195, 130},
    {1010.0f, 155, 205,  75},
    {1020.0f, 220, 185,  55},
    {1030.0f, 235, 130,  45},
    {1040.0f, 228,  70,  40},
    {1050.0f, 175,  30,  50},
};
static const NSInteger kStopsCount = sizeof(kStops) / sizeof(PressureStop);

@implementation PressureColorizer

+ (uint32_t *)colorizePressure:(float *)pressures size:(NSInteger)size {
    uint32_t *pixels = (uint32_t *)malloc(size * sizeof(uint32_t));
    
    NSInteger nanCount = 0;
    NSInteger coloredCount = 0;
    NSMutableDictionary<NSNumber *, NSNumber *> *colorHistogram = [NSMutableDictionary dictionary];
    
    for (NSInteger i = 0; i < size; i++) {
        float pressure = pressures[i];
        if (isnan(pressure)) {
            pixels[i] = 0x00000000;  // 透明
            nanCount++;
        } else {
            pixels[i] = [self colorForPressure:pressure];
            coloredCount++;
            uint32_t rgb = pixels[i] & 0x00FFFFFF;
            NSNumber *key = @(rgb);
            colorHistogram[key] = @([colorHistogram[key] integerValue] + 1);
        }
    }
    
    NSLog(@"[PRESSURE] 📊 着色统计: 着色=%ld 透明=%ld 唯一颜色=%lu",
          (long)coloredCount, (long)nanCount, (unsigned long)colorHistogram.count);
    
    return pixels;
}

+ (uint32_t)colorForPressure:(float)pressure {
    if (isnan(pressure)) {
        return 0;
    }
    
    PressureStop lower, upper;
    if (pressure <= kStops[0].pressure) {
        lower = upper = kStops[0];
    } else if (pressure >= kStops[kStopsCount - 1].pressure) {
        lower = upper = kStops[kStopsCount - 1];
    } else {
        NSInteger upperIndex = 0;
        for (NSInteger i = 0; i < kStopsCount; i++) {
            if (pressure <= kStops[i].pressure) {
                upperIndex = i;
                break;
            }
        }
        lower = kStops[upperIndex - 1];
        upper = kStops[upperIndex];
    }
    
    float fraction = 0.0f;
    if (upper.pressure > lower.pressure) {
        fraction = (pressure - lower.pressure) / (upper.pressure - lower.pressure);
    }
    
    uint8_t red = [self lerp:lower.red to:upper.red fraction:fraction];
    uint8_t green = [self lerp:lower.green to:upper.green fraction:fraction];
    uint8_t blue = [self lerp:lower.blue to:upper.blue fraction:fraction];
    
    return (kOverlayAlpha << 24) | (red << 16) | (green << 8) | blue;
}

+ (uint8_t)lerp:(uint8_t)from to:(uint8_t)to fraction:(float)fraction {
    float result = from + (to - from) * fraction;
    return (uint8_t)fmaxf(0.0f, fminf(255.0f, result));
}

@end
