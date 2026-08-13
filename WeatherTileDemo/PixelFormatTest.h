//
//  PixelFormatTest.h
//  WeatherTileDemo
//
//  用于测试 CGBitmapContext 的实际像素格式
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface PixelFormatTest : NSObject

/**
 * 测试 CGBitmapContext 的像素格式
 * 创建一个已知颜色的图像，读取像素，验证格式
 */
+ (void)testPixelFormat;

@end
