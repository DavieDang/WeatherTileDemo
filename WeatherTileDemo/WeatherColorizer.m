//
//  WeatherColorizer.m
//  WeatherTileDemo
//

#import "WeatherColorizer.h"
#import <math.h>

@implementation WeatherColorizer

+ (uint32_t *)colorizeValues:(float *)values
                        size:(NSInteger)size
                      stops:(NSArray<WeatherColorStop *> *)stops
                     enhance:(BOOL)enhance
                       alpha:(uint8_t)alpha {
    uint32_t *pixels = (uint32_t *)malloc(size * sizeof(uint32_t));
    
    NSInteger nanCount = 0;
    NSMutableSet *colorSet = [NSMutableSet set];
    
    for (NSInteger i = 0; i < size; i++) {
        float value = values[i];
        if (isnan(value)) {
            pixels[i] = 0x00000000;
            nanCount++;
        } else {
            pixels[i] = [self colorForValue:value stops:stops enhance:enhance alpha:alpha];
            [colorSet addObject:@(pixels[i] & 0x00FFFFFF)];
        }
    }
    
    NSLog(@"[COLORIZER] 📊 着色统计: 着色=%ld 透明=%ld 唯一颜色=%lu",
          (long)(size - nanCount), (long)nanCount, (unsigned long)colorSet.count);
    
    return pixels;
}

+ (uint32_t)colorForValue:(float)value
                    stops:(NSArray<WeatherColorStop *> *)stops
                  enhance:(BOOL)enhance
                    alpha:(uint8_t)alpha {
    if (isnan(value) || stops.count == 0) {
        return 0;
    }
    
    WeatherColorStop *lower = nil;
    WeatherColorStop *upper = nil;
    
    if (value <= stops.firstObject.value) {
        lower = upper = stops.firstObject;
    } else if (value >= stops.lastObject.value) {
        lower = upper = stops.lastObject;
    } else {
        for (NSUInteger i = 1; i < stops.count; i++) {
            if (value <= stops[i].value) {
                lower = stops[i - 1];
                upper = stops[i];
                break;
            }
        }
        if (!upper) {
            lower = upper = stops.lastObject;
        }
    }
    
    float fraction = 0.0f;
    if (upper.value > lower.value) {
        fraction = (value - lower.value) / (upper.value - lower.value);
    }
    
    const CGFloat *lowerC = CGColorGetComponents(lower.color.CGColor);
    const CGFloat *upperC = CGColorGetComponents(upper.color.CGColor);
    uint8_t red = [self lerp:lowerC[0] to:upperC[0] fraction:fraction];
    uint8_t green = [self lerp:lowerC[1] to:upperC[1] fraction:fraction];
    uint8_t blue = [self lerp:lowerC[2] to:upperC[2] fraction:fraction];
    
    if (enhance) {
        uint8_t enhanced[3];
        [self enhanceContrast:red green:green blue:blue output:enhanced];
        red = enhanced[0];
        green = enhanced[1];
        blue = enhanced[2];
    }
    
    return ((uint32_t)alpha << 24) | (red << 16) | (green << 8) | blue;
}

+ (uint8_t)lerp:(CGFloat)from to:(CGFloat)to fraction:(float)fraction {
    CGFloat result = (from + (to - from) * fraction) * 255.0f;
    return (uint8_t)fmaxf(0.0f, fminf(255.0f, result));
}

+ (void)enhanceContrast:(uint8_t)r green:(uint8_t)g blue:(uint8_t)b output:(uint8_t *)output {
    // Windy 对比度增强：饱和度 +55%，对比度 +20%，亮度 -18%
    float luminance = 0.299f * r + 0.587f * g + 0.114f * b;
    uint8_t channels[3] = {r, g, b};
    for (int i = 0; i < 3; i++) {
        uint8_t channel = channels[i];
        float saturated = luminance + (channel - luminance) * 1.55f;
        float contrasted = (saturated - 128.0f) * 1.20f + 128.0f;
        output[i] = (uint8_t)fmaxf(0.0f, fminf(255.0f, contrasted * 0.82f));
    }
}

@end
