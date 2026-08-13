//
//  PixelFormatTest.m
//  WeatherTileDemo
//

#import "PixelFormatTest.h"

@implementation PixelFormatTest

+ (void)testPixelFormat {
    NSLog(@"==================== 像素格式测试开始 ====================");
    
    // 创建一个 2x2 的测试图像，填充已知颜色
    CGSize size = CGSizeMake(2, 2);
    UIGraphicsBeginImageContextWithOptions(size, YES, 1.0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    
    // 填充4个不同的颜色
    // 像素 [0,0]: 纯红色 RGB(255, 0, 0)
    CGContextSetRGBFillColor(ctx, 1.0, 0.0, 0.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 0, 1, 1));
    
    // 像素 [1,0]: 纯绿色 RGB(0, 255, 0)
    CGContextSetRGBFillColor(ctx, 0.0, 1.0, 0.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(1, 0, 1, 1));
    
    // 像素 [0,1]: 纯蓝色 RGB(0, 0, 255)
    CGContextSetRGBFillColor(ctx, 0.0, 0.0, 1.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(0, 1, 1, 1));
    
    // 像素 [1,1]: 白色 RGB(255, 255, 255)
    CGContextSetRGBFillColor(ctx, 1.0, 1.0, 1.0, 1.0);
    CGContextFillRect(ctx, CGRectMake(1, 1, 1, 1));
    
    UIImage *testImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    // 使用与 WindTileServer 相同的配置读取像素
    CGImageRef cgImage = testImage.CGImage;
    NSUInteger width = CGImageGetWidth(cgImage);
    NSUInteger height = CGImageGetHeight(cgImage);
    
    NSLog(@"测试图像尺寸: %lux%lu", (unsigned long)width, (unsigned long)height);
    
    // 使用相同的 CGBitmapContext 配置
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    uint32_t *pixels = (uint32_t *)malloc(width * height * sizeof(uint32_t));
    
    CGContextRef bitmapContext = CGBitmapContextCreate(
        pixels,
        width,
        height,
        8,
        width * 4,
        colorSpace,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
    );
    
    CGContextDrawImage(bitmapContext, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(bitmapContext);
    CGColorSpaceRelease(colorSpace);
    
    NSLog(@"");
    NSLog(@"=== 像素格式分析 ===");
    NSLog(@"配置: kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big");
    NSLog(@"");
    
    // 分析每个像素
    const char *colors[] = {"红色(255,0,0)", "绿色(0,255,0)", "蓝色(0,0,255)", "白色(255,255,255)"};
    
    for (int i = 0; i < 4; i++) {
        uint32_t pixel = pixels[i];
        
        NSLog(@"像素[%d] = 0x%08X (%s)", i, pixel, colors[i]);
        
        // 尝试所有可能的格式
        NSLog(@"  如果是 ARGB: A=%d R=%d G=%d B=%d", 
              (pixel >> 24) & 0xFF,
              (pixel >> 16) & 0xFF,
              (pixel >> 8) & 0xFF,
              pixel & 0xFF);
        
        NSLog(@"  如果是 RGBA: R=%d G=%d B=%d A=%d",
              (pixel >> 24) & 0xFF,
              (pixel >> 16) & 0xFF,
              (pixel >> 8) & 0xFF,
              pixel & 0xFF);
        
        NSLog(@"  如果是 BGRA: B=%d G=%d R=%d A=%d",
              (pixel >> 24) & 0xFF,
              (pixel >> 16) & 0xFF,
              (pixel >> 8) & 0xFF,
              pixel & 0xFF);
        
        NSLog(@"");
    }
    
    // 判断实际格式
    uint32_t redPixel = pixels[0];  // 应该是红色 RGB(255,0,0)
    
    NSLog(@"=== 格式判断 ===");
    
    // 检查 ARGB 格式
    if (((redPixel >> 16) & 0xFF) == 255 && 
        ((redPixel >> 8) & 0xFF) == 0 && 
        (redPixel & 0xFF) == 0) {
        NSLog(@"✅ 实际格式: ARGB (0xAARRGGBB)");
        NSLog(@"   Red   = (pixel >> 16) & 0xFF");
        NSLog(@"   Green = (pixel >> 8) & 0xFF");
        NSLog(@"   Blue  = pixel & 0xFF");
    }
    // 检查 RGBA 格式
    else if (((redPixel >> 24) & 0xFF) == 255 && 
             ((redPixel >> 16) & 0xFF) == 0 && 
             ((redPixel >> 8) & 0xFF) == 0) {
        NSLog(@"✅ 实际格式: RGBA (0xRRGGBBAA)");
        NSLog(@"   Red   = (pixel >> 24) & 0xFF");
        NSLog(@"   Green = (pixel >> 16) & 0xFF");
        NSLog(@"   Blue  = (pixel >> 8) & 0xFF");
    }
    // 检查 BGRA 格式
    else if ((redPixel & 0xFF) == 255 &&
             ((redPixel >> 8) & 0xFF) == 0 &&
             ((redPixel >> 16) & 0xFF) == 0) {
        NSLog(@"✅ 实际格式: BGRA (0xBBGGRRAA)");
        NSLog(@"   Blue  = (pixel >> 24) & 0xFF");
        NSLog(@"   Green = (pixel >> 16) & 0xFF");
        NSLog(@"   Red   = (pixel >> 8) & 0xFF");
    }
    else {
        NSLog(@"❌ 无法识别的格式！");
    }
    
    free(pixels);
    
    NSLog(@"==================== 像素格式测试结束 ====================");
}

@end
