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
    
    CGImageRef fullImage = jpegImage.CGImage;
    size_t fullWidth  = CGImageGetWidth(fullImage);
    size_t fullHeight = CGImageGetHeight(fullImage);
    NSLog(@"[DEBUG] JPEG 原始尺寸: %ldx%ld", (unsigned long)fullWidth, (unsigned long)fullHeight);
    
    // ⭐ 第一步：解码头部（需要完整 257x265，读 row 4 的编码）
    static const NSInteger kHeaderRows = 8;
    CGColorSpaceRef csHeader = CGColorSpaceCreateDeviceRGB();
    uint32_t *fullPixels = (uint32_t *)malloc(fullWidth * fullHeight * sizeof(uint32_t));
    CGContextRef headerCtx = CGBitmapContextCreate(fullPixels, fullWidth, fullHeight, 8,
                                                    fullWidth * 4, csHeader,
                                                    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextTranslateCTM(headerCtx, 0, fullHeight);
    CGContextScaleCTM(headerCtx, 1.0, -1.0);
    CGContextDrawImage(headerCtx, CGRectMake(0, 0, fullWidth, fullHeight), fullImage);
    CGContextRelease(headerCtx);
    CGColorSpaceRelease(csHeader);
    
    // 从完整像素中解码头部参数
    WindFieldHeader header = [WindyWindTileDecoder decodeHeaderFromPixels:fullPixels width:fullWidth];
    free(fullPixels);
    NSLog(@"[DEBUG] 头部解码: rMin=%.2f rMax=%.2f gMin=%.2f gMax=%.2f",
          header.rMin, header.rMax, header.gMin, header.gMax);
    
    // ⭐ 第二步：裁剪掉头部色条
    // 读取时图片存在 Y 轴翻转，色条实际位于裁剪视图的底部。
    // 因此从 y=kHeaderRows 开始取 257 行，裁掉底部 8 行色条。
    NSInteger dataHeight = (NSInteger)fullHeight - kHeaderRows;  // 265-8=257
    CGRect dataRect = CGRectMake(0, kHeaderRows, fullWidth, dataHeight);  // y=8, height=257
    CGImageRef croppedImage = CGImageCreateWithImageInRect(fullImage, dataRect);
    NSLog(@"[DEBUG] 裁剪后尺寸: %ldx%ld（已裁掉底部 %ld 行色条，裁剪矩形 y=%ld h=%ld）",
          (unsigned long)fullWidth, (unsigned long)dataHeight, (long)kHeaderRows,
          (long)kHeaderRows, (long)dataHeight);
    
    // ⭐ 第三步：把裁剪后的数据区（257x257）渲染到像素数组
    CGColorSpaceRef csData = CGColorSpaceCreateDeviceRGB();
    uint32_t *dataPixels = (uint32_t *)malloc(fullWidth * dataHeight * sizeof(uint32_t));
    CGContextRef dataCtx = CGBitmapContextCreate(dataPixels, fullWidth, dataHeight, 8,
                                                  fullWidth * 4, csData,
                                                  kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGContextTranslateCTM(dataCtx, 0, dataHeight);
    CGContextScaleCTM(dataCtx, 1.0, -1.0);
    CGContextDrawImage(dataCtx, CGRectMake(0, 0, fullWidth, dataHeight), croppedImage);
    CGContextRelease(dataCtx);
    CGColorSpaceRelease(csData);
    CGImageRelease(croppedImage);
    
    // ⭐ 第四步：解码风场（裁剪后的像素，从 row 0 开始，无需跳行）
    WindField *field = [WindyWindTileDecoder decodeDataPixels:dataPixels
                                                        width:fullWidth
                                                       height:dataHeight
                                                       header:header];
    free(dataPixels);
    NSLog(@"[DEBUG] 风场解码完成");
    
    // ⭐ 第五步：Windy 色阶着色
    uint32_t *coloredPixels = [WindSpeedColorizer colorizeField:field];
    free(field->u);
    free(field->v);
    free(field);
    
    // ⭐ 第六步：输出 256x256 PNG
    // 注意：这里【不需要】再翻转 Y 轴。
    // 方向链条：UIImage.CGImage 像素存储与视觉方向相反（row 0 = 视觉底部），
    // 读取时 headerCtx/dataCtx 的翻转恰好把裁剪后的数据区纠正为正立，
    // 因此 coloredPixels row 0 = 数据区视觉顶部。若在此再加翻转，瓦片会上下颠倒。
    CGColorSpaceRef csPNG = CGColorSpaceCreateDeviceRGB();
    CGContextRef outputCtx = CGBitmapContextCreate(coloredPixels, 256, 256, 8, 256 * 4,
                                                    csPNG,
                                                    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    if (!outputCtx) {
        free(coloredPixels);
        CGColorSpaceRelease(csPNG);
        @throw [NSException exceptionWithName:@"RenderError" reason:@"无法创建输出上下文" userInfo:nil];
    }
    CGImageRef outputImage = CGBitmapContextCreateImage(outputCtx);
    UIImage *pngImage = [UIImage imageWithCGImage:outputImage];
    NSData *pngData = UIImagePNGRepresentation(pngImage);
    CGImageRelease(outputImage);
    CGContextRelease(outputCtx);
    CGColorSpaceRelease(csPNG);
    free(coloredPixels);
    NSLog(@"[DEBUG] PNG 生成完成: %lu bytes", (unsigned long)pngData.length);
    
#if DEBUG
    // 保存生成的瓦片到缓存文件夹，方便检查是否有色条
    static NSInteger _tileCount = 0;
    if (_tileCount < 10) {
        NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *tileDir = [cacheDir stringByAppendingPathComponent:@"rendered_tiles"];
        [[NSFileManager defaultManager] createDirectoryAtPath:tileDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSString *filename = [NSString stringWithFormat:@"tile_%03ld.png", (long)_tileCount];
        NSString *savePath = [tileDir stringByAppendingPathComponent:filename];
        [pngData writeToFile:savePath atomically:YES];
        NSLog(@"[DEBUG] 💾 瓦片已保存: %@", savePath);
        _tileCount++;
    }
#endif
    
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
