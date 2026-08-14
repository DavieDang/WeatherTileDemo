//
//  WindTileServer.m
//  WeatherTileDemo
//

#import "WindTileServer.h"
#import "WindyWindTileDecoder.h"
#import "WindSpeedColorizer.h"
#import "WindyForecastResolver.h"
#import "WindTileDiskCache.h"
#import <GCDWebServer/GCDWebServer.h>
#import <GCDWebServer/GCDWebServerDataResponse.h>
#import <UIKit/UIKit.h>

@interface WindTileServer ()

@property (nonatomic, strong) GCDWebServer *server;
@property (nonatomic, strong) NSCache<NSString *, NSData *> *memoryCache;
@property (nonatomic, strong) WindTileDiskCache *diskCache;
@property (nonatomic, strong) WindyForecastResolver *forecastResolver;
@property (nonatomic, strong) NSData *transparentTile;
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, copy) NSString *currentForecastKey;
@property (nonatomic, copy) NSString *currentBaseUrl;

@end

@implementation WindTileServer

static const NSInteger kMaxDataZoom = 4;
static const NSInteger kMemoryCacheLimit = 64;

- (instancetype)initWithCacheDirectory:(NSString *)cacheDirectory {
    if (self = [super init]) {
        _server = [[GCDWebServer alloc] init];
        _memoryCache = [[NSCache alloc] init];
        _memoryCache.countLimit = kMemoryCacheLimit;
        _diskCache = [[WindTileDiskCache alloc] initWithCacheDirectory:cacheDirectory 
                                                        renderVersion:@"windy-v2-contrast-alpha217"];
        _forecastResolver = [[WindyForecastResolver alloc] init];
        _workQueue = dispatch_queue_create("com.weathertile.server", DISPATCH_QUEUE_CONCURRENT);
        _transparentTile = [self createTransparentTile];
    }
    return self;
}

- (NSString *)start {
    __weak typeof(self) weakSelf = self;
    
    [self.server addDefaultHandlerForMethod:@"GET"
                               requestClass:[GCDWebServerRequest class]
                               processBlock:^GCDWebServerResponse * _Nullable(__kindof GCDWebServerRequest * _Nonnull request) {
        return [weakSelf handleRequest:request];
    }];
    
    NSError *error = nil;
    NSDictionary *options = @{
        GCDWebServerOption_BindToLocalhost: @YES,
        GCDWebServerOption_Port: @0,
        GCDWebServerOption_AutomaticallySuspendInBackground: @NO
    };
    
    if (![self.server startWithOptions:options error:&error]) {
        NSLog(@"[WindTileServer] 启动失败: %@", error);
        return nil;
    }
    
    NSUInteger port = self.server.port;
    _tileTemplate = [NSString stringWithFormat:@"http://127.0.0.1:%lu/wind/{z}/{x}/{y}.png", (unsigned long)port];
    
    // 预热预报时次
    dispatch_async(self.workQueue, ^{
        [weakSelf prepareForecast];
    });
    
    NSLog(@"[WindTileServer] 启动成功，监听端口 %lu", (unsigned long)port);
    return _tileTemplate;
}

- (void)stop {
    [self.server stop];
    [self.memoryCache removeAllObjects];
    NSLog(@"[WindTileServer] 已停止");
}

- (GCDWebServerDataResponse *)handleRequest:(GCDWebServerRequest *)request {
    NSString *path = request.path;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"/wind/(\\d+)/(-?\\d+)/(\\d+)\\.png"
                                                                            options:0
                                                                              error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    
    if (!match) {
        return [GCDWebServerDataResponse responseWithData:self.transparentTile contentType:@"image/png"];
    }
    
    NSInteger z = [[path substringWithRange:[match rangeAtIndex:1]] integerValue];
    NSInteger x = [[path substringWithRange:[match rangeAtIndex:2]] integerValue];
    NSInteger y = [[path substringWithRange:[match rangeAtIndex:3]] integerValue];
    
    NSData *tileData = [self tileForZ:z x:x y:y];
    return [GCDWebServerDataResponse responseWithData:tileData contentType:@"image/png"];
}

- (NSData *)tileForZ:(NSInteger)z x:(NSInteger)x y:(NSInteger)y {
    NSLog(@"[DEBUG] ===== Tile request: z=%ld x=%ld y=%ld =====", (long)z, (long)x, (long)y);
    
    if (z < 0 || z > kMaxDataZoom) {
        NSLog(@"[DEBUG] Zoom %ld out of range [0-%ld], returning transparent", (long)z, (long)kMaxDataZoom);
        return self.transparentTile;
    }
    
    NSInteger dimension = 1 << z;
    if (y < 0 || y >= dimension) {
        NSLog(@"[DEBUG] Y=%ld out of range [0-%ld], returning transparent", (long)y, (long)dimension - 1);
        return self.transparentTile;
    }
    
    // X 轴循环
    NSInteger wrappedX = ((x % dimension) + dimension) % dimension;
    if (wrappedX != x) {
        NSLog(@"[DEBUG] X wrapped: %ld -> %ld", (long)x, (long)wrappedX);
    }
    
    @try {
        [self prepareForecast];
        return [self tileForForecastZ:z x:wrappedX y:y];
    } @catch (NSException *exception) {
        NSLog(@"[WindTileServer] 瓦片 %ld/%ld/%ld 失败: %@", (long)z, (long)wrappedX, (long)y, exception.reason);
        return self.transparentTile;
    }
}

- (void)prepareForecast {
    if (self.currentBaseUrl && self.currentForecastKey) {
        return;
    }
    
    @synchronized (self) {
        if (self.currentBaseUrl && self.currentForecastKey) {
            return;
        }
        
        NSString *baseUrl = [self.forecastResolver resolveBaseUrl];
        NSString *forecastKey = [WindTileDiskCache forecastKeyFromBaseUrl:baseUrl];
        
        [self.diskCache activateForecast:forecastKey];
        
        self.currentBaseUrl = baseUrl;
        self.currentForecastKey = forecastKey;
        
        NSLog(@"[WindTileServer] 激活预报缓存: %@", forecastKey);
    }
}

- (NSData *)tileForForecastZ:(NSInteger)z x:(NSInteger)x y:(NSInteger)y {
    NSString *coordinateKey = [NSString stringWithFormat:@"%ld/%ld/%ld", (long)z, (long)x, (long)y];
    NSString *memoryKey = [NSString stringWithFormat:@"%@/%@", self.currentForecastKey, coordinateKey];
    
    // 1. 查内存缓存
    NSData *cached = [self.memoryCache objectForKey:memoryKey];
    if (cached) {
        return cached;
    }
    
    // 2. 查磁盘缓存
    NSData *diskData = [self.diskCache readTileForForecast:self.currentForecastKey z:z x:x y:y];
    if (diskData) {
        [self.memoryCache setObject:diskData forKey:memoryKey];
        NSLog(@"[WindTileServer] 磁盘缓存命中 %@ (%lu bytes)", coordinateKey, (unsigned long)diskData.length);
        return diskData;
    }
    
    // 3. 远程下载 + 渲染
    NSString *remoteUrl = [NSString stringWithFormat:@"%@/%@/wind-surface.jpg", self.currentBaseUrl, coordinateKey];
    NSData *pngData = [self fetchAndRender:remoteUrl];
    
    [self.diskCache writeTile:pngData forForecast:self.currentForecastKey z:z x:x y:y];
    [self.memoryCache setObject:pngData forKey:memoryKey];
    
    NSLog(@"[WindTileServer] 下载瓦片 %@ (%lu bytes)", coordinateKey, (unsigned long)pngData.length);
    return pngData;
}

- (NSData *)fetchAndRender:(NSString *)urlString {
    NSLog(@"[DEBUG] Fetching from URL: %@", urlString);
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSData *jpegData = [NSData dataWithContentsOfURL:url];
    if (!jpegData) {
        NSLog(@"[DEBUG] Failed to fetch JPEG");
        @throw [NSException exceptionWithName:@"FetchError" reason:@"无法下载图片" userInfo:nil];
    }
    
    UIImage *jpegImage = [UIImage imageWithData:jpegData];
    if (!jpegImage) {
        NSLog(@"[DEBUG] Failed to decode JPEG");
        @throw [NSException exceptionWithName:@"DecodeError" reason:@"无法解码图片" userInfo:nil];
    }
    
    CGImageRef cgImage = jpegImage.CGImage;
    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    
    // 诊断：检查 JPEG 尺寸
    if (width != 257 || height != 265) {
        NSLog(@"[WindTileServer] ⚠️  异常 JPEG 尺寸: %ldx%ld (期望 257x265)", (long)width, (long)height);
    }
    
    NSLog(@"[DEBUG] JPEG size: %lux%lu", (unsigned long)width, (unsigned long)height);
    
    // ⭐ 创建位图上下文 - 必须翻转 Y 轴
    // 这样 pixels[0] = JPEG row 0, pixels[4*w] = JPEG row 4（头部）
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    uint32_t *pixels = (uint32_t *)malloc(width * height * sizeof(uint32_t));
    
    CGContextRef bitmapContext = CGBitmapContextCreate(pixels, width, height, 8, width * 4,
                                                       colorSpace,
                                                       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    
    // ✅ 翻转 Y 轴 - 让 pixels 的 row 顺序与 JPEG 一致（row 0 = 顶部）
    CGContextTranslateCTM(bitmapContext, 0, height);
    CGContextScaleCTM(bitmapContext, 1.0, -1.0);
    
    CGContextDrawImage(bitmapContext, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(bitmapContext);
    CGColorSpaceRelease(colorSpace);
    
    NSLog(@"[DEBUG] ⭐⭐⭐ 启用完整渲染管道 ⭐⭐⭐");
    NSLog(@"[DEBUG] 步骤: JPEG → 解码u/v → 计算风速 → Windy色阶 → 对比度增强");
    NSLog(@"[DEBUG] ✅ Y 轴已翻转，pixels[4*w]=头部行，pixels[8*w]=数据第一行");
    
    // ⭐ 步骤1: 解码风场数据（u/v分量）
//    NSLog(@"[WindTileServer] ═══ 瓦片 %ld/%ld/%ld 解码开始 ═══", (long)z, (long)x, (long)y);
    WindField *field = [WindyWindTileDecoder decodePixels:pixels width:width height:height];
    free(pixels);
    
    NSLog(@"[DEBUG] ✓ 风场解码完成: %dx%d",
          field->width, field->height);
    
    // 调试：打印几个风速样本
    NSLog(@"[DEBUG] 风速样本 (前5个点):");
    for (int i = 0; i < 5 && i < field->width * field->height; i++) {
        float u = field->u[i];
        float v = field->v[i];
        if (!isnan(u) && !isnan(v)) {
            float speed = sqrtf(u * u + v * v);
            NSLog(@"  [%d] u=%.2f v=%.2f speed=%.2f m/s", i, u, v, speed);
        } else {
            NSLog(@"  [%d] 缺测 (NaN)", i);
        }
    }
    
    // ⭐ 步骤2: 应用Windy色阶和对比度增强
    uint32_t *coloredPixels = [WindSpeedColorizer colorizeField:field];
    
    // 释放风场数据
    free(field->u);
    free(field->v);
    free(field);
    
    NSLog(@"[DEBUG] ✓ 风速着色完成");
    
    // 调试：打印着色后的样本像素
    NSLog(@"[DEBUG] 着色后像素样本 (ARGB格式，前3个点):");
    for (int i = 0; i < 3; i++) {
        uint32_t p = coloredPixels[i];
        NSLog(@"  [%d] = 0x%08X (A=%d R=%d G=%d B=%d)", 
              i, p,
              (p >> 24) & 0xFF,
              (p >> 16) & 0xFF,
              (p >> 8) & 0xFF,
              p & 0xFF);
    }
    
    // ⭐ 步骤3: 生成 PNG
    CGColorSpaceRef colorSpacePNG = CGColorSpaceCreateDeviceRGB();
    CGContextRef outputContext = CGBitmapContextCreate(coloredPixels, 256, 256, 8,
                                                       256 * 4, colorSpacePNG,
                                                       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    
    if (!outputContext) {
        NSLog(@"[ERROR] Failed to create output context!");
        free(coloredPixels);
        CGColorSpaceRelease(colorSpacePNG);
        @throw [NSException exceptionWithName:@"RenderError" reason:@"无法创建输出上下文" userInfo:nil];
    }
    
    CGImageRef outputImage = CGBitmapContextCreateImage(outputContext);
    UIImage *pngImage = [UIImage imageWithCGImage:outputImage];
    NSData *pngData = UIImagePNGRepresentation(pngImage);
    
    // 清理资源
    CGImageRelease(outputImage);
    CGContextRelease(outputContext);
    CGColorSpaceRelease(colorSpacePNG);
    free(coloredPixels);
    
    NSLog(@"[DEBUG] ✓ PNG生成完成: %lu bytes", (unsigned long)pngData.length);
    NSLog(@"[DEBUG] ==========================================");
    
    return pngData;
}

- (NSData *)createTransparentTile {
    CGSize size = CGSizeMake(256, 256);
    UIGraphicsBeginImageContextWithOptions(size, NO, 1.0);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return UIImagePNGRepresentation(image);
}

@end
