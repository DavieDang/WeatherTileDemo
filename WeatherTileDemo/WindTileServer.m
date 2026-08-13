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
    
    NSLog(@"[DEBUG] JPEG size: %lux%lu", (unsigned long)width, (unsigned long)height);
    
    // ⭐ 创建位图上下文 - 使用默认字节序（小端序，BGRA内存布局）
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    uint32_t *pixels = (uint32_t *)malloc(width * height * sizeof(uint32_t));
    
    CGContextRef bitmapContext = CGBitmapContextCreate(pixels, width, height, 8, width * 4,
                                                       colorSpace,
                                                       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    
    // ⭐ 关键：翻转 Y 轴，因为 CGImage 和 CGContext 的坐标系相反
    CGContextTranslateCTM(bitmapContext, 0, height);
    CGContextScaleCTM(bitmapContext, 1.0, -1.0);
    
    CGContextDrawImage(bitmapContext, CGRectMake(0, 0, width, height), cgImage);
    CGContextRelease(bitmapContext);
    CGColorSpaceRelease(colorSpace);
    
    NSLog(@"[DEBUG] Pixel buffer created (ARGB with little-endian = BGRA in memory)");
    
    // 调试：打印前3个像素
    NSLog(@"[DEBUG] First 3 pixels (ARGB format):");
    for (int i = 0; i < 3; i++) {
        uint32_t p = pixels[i];
        NSLog(@"  [%d] = 0x%08X (A=%d R=%d G=%d B=%d)", 
              i, p,
              (p >> 24) & 0xFF,
              (p >> 16) & 0xFF,
              (p >> 8) & 0xFF,
              p & 0xFF);
    }
    
    // ⭐ 创建256x256的输出（跳过前8行，考虑Y轴翻转）
    NSLog(@"[DEBUG] ========================================");
    NSLog(@"[DEBUG] 🎨 使用原始颜色（跳过头部8行）");
    NSLog(@"[DEBUG] ========================================");
    
    uint32_t *coloredPixels = (uint32_t *)malloc(256 * 256 * sizeof(uint32_t));
    
    for (int y = 0; y < 256; y++) {
        for (int x = 0; x < 256; x++) {
            // 因为 Y 轴翻转，从底部开始读取（跳过顶部8行和底部1行）
            NSInteger srcRow = height - 8 - y - 1;
            uint32_t srcPixel = pixels[srcRow * width + x];
            
            // ⭐ 确保 Alpha 通道为 255（完全不透明）
            coloredPixels[y * 256 + x] = srcPixel | 0xFF000000;
        }
    }
    
    NSLog(@"[DEBUG] ✂️ 裁剪计算：height=%ld, srcRow 范围: %ld ~ %ld",
          (long)height, (long)(height - 8 - 0 - 1), (long)(height - 8 - 255 - 1));
    
    // 验证原始 row 8 的像素
    NSLog(@"[DEBUG] 原始 JPEG Row 8 (数据起点):");
    NSInteger verifyRow = height - 8 - 1;
    for (int i = 0; i < 3; i++) {
        uint32_t p = pixels[verifyRow * width + i];
        NSLog(@"  [8,%d] = 0x%08X (A=%d R=%d G=%d B=%d)", 
              i, p,
              (p >> 24) & 0xFF,
              (p >> 16) & 0xFF,
              (p >> 8) & 0xFF,
              p & 0xFF);
    }
    
    // 验证输出像素
    NSLog(@"[DEBUG] 输出瓦片前3个像素:");
    for (int i = 0; i < 3; i++) {
        uint32_t p = coloredPixels[i];
        NSLog(@"  Output[0,%d] = 0x%08X (A=%d R=%d G=%d B=%d)", 
              i, p,
              (p >> 24) & 0xFF,
              (p >> 16) & 0xFF,
              (p >> 8) & 0xFF,
              p & 0xFF);
    }
    
    // ⭐ 生成 PNG - 使用相同的格式
    CGColorSpaceRef colorSpacePNG = CGColorSpaceCreateDeviceRGB();
    CGContextRef outputContext = CGBitmapContextCreate(coloredPixels, 256, 256, 8,
                                                       256 * 4, colorSpacePNG,
                                                       kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    
    if (!outputContext) {
        NSLog(@"[ERROR] Failed to create output context!");
        free(pixels);
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
    free(pixels);
    free(coloredPixels);
    
    NSLog(@"[DEBUG] PNG generated: %lu bytes", (unsigned long)pngData.length);
    
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
