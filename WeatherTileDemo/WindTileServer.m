//
//  WindTileServer.m
//  WeatherTileDemo
//

#import "WindTileServer.h"
#import "WindyWindTileDecoder.h"
#import "WindSpeedColorizer.h"
#import "PressureColorizer.h"
#import "WindyForecastResolver.h"
#import "WindTileDiskCache.h"
#import <GCDWebServer/GCDWebServer.h>
#import <GCDWebServer/GCDWebServerDataResponse.h>
#import <UIKit/UIKit.h>

WeatherLayerType const WeatherLayerTypeWind = @"wind";
WeatherLayerType const WeatherLayerTypePressure = @"pressure";

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
    _pressureTileTemplate = [NSString stringWithFormat:@"http://127.0.0.1:%lu/pressure/{z}/{x}/{y}.png", (unsigned long)port];
    
    // 预热预报时次
    dispatch_async(self.workQueue, ^{
        [weakSelf prepareForecast];
    });
    
    NSLog(@"[WindTileServer] 启动成功，监听端口 %lu", (unsigned long)port);
    return _tileTemplate;
}

- (NSString *)tileTemplateForType:(WeatherLayerType)type {
    if ([type isEqualToString:WeatherLayerTypePressure]) {
        return self.pressureTileTemplate;
    }
    return self.tileTemplate;
}

- (void)stop {
    [self.server stop];
    [self.memoryCache removeAllObjects];
    NSLog(@"[WindTileServer] 已停止");
}

- (GCDWebServerDataResponse *)handleRequest:(GCDWebServerRequest *)request {
    NSString *path = request.path;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"/(wind|pressure)/(\\d+)/(-?\\d+)/(\\d+)\\.png"
                                                                            options:0
                                                                              error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:path options:0 range:NSMakeRange(0, path.length)];
    
    if (!match) {
        return [GCDWebServerDataResponse responseWithData:self.transparentTile contentType:@"image/png"];
    }
    
    NSString *type = [path substringWithRange:[match rangeAtIndex:1]];
    NSInteger z = [[path substringWithRange:[match rangeAtIndex:2]] integerValue];
    NSInteger x = [[path substringWithRange:[match rangeAtIndex:3]] integerValue];
    NSInteger y = [[path substringWithRange:[match rangeAtIndex:4]] integerValue];
    
    NSData *tileData = [self tileForType:type z:z x:x y:y];
    return [GCDWebServerDataResponse responseWithData:tileData contentType:@"image/png"];
}

- (NSData *)tileForType:(WeatherLayerType)type z:(NSInteger)z x:(NSInteger)x y:(NSInteger)y {
    NSLog(@"[DEBUG] ===== %@ Tile request: z=%ld x=%ld y=%ld =====", type, (long)z, (long)x, (long)y);
    
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
        return [self tileForForecastType:type z:z x:wrappedX y:y];
    } @catch (NSException *exception) {
        NSLog(@"[WindTileServer] %@ 瓦片 %ld/%ld/%ld 失败: %@", type, (long)z, (long)wrappedX, (long)y, exception.reason);
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

- (NSString *)diskForecastKeyForType:(WeatherLayerType)type {
    return [NSString stringWithFormat:@"%@_%@", type, self.currentForecastKey];
}

- (NSString *)remoteSuffixForType:(WeatherLayerType)type {
    if ([type isEqualToString:WeatherLayerTypePressure]) {
        return @"pressure-surface.jpg";
    }
    return @"wind-surface.jpg";
}

- (NSData *)tileForForecastType:(WeatherLayerType)type z:(NSInteger)z x:(NSInteger)x y:(NSInteger)y {
    NSString *diskKey = [self diskForecastKeyForType:type];
    [self.diskCache activateForecast:diskKey];
    
    NSString *coordinateKey = [NSString stringWithFormat:@"%ld/%ld/%ld", (long)z, (long)x, (long)y];
    NSString *memoryKey = [NSString stringWithFormat:@"%@/%@/%@", type, self.currentForecastKey, coordinateKey];
    
    // 1. 查内存缓存
    NSData *cached = [self.memoryCache objectForKey:memoryKey];
    if (cached) {
        return cached;
    }
    
    // 2. 查磁盘缓存
    NSData *diskData = [self.diskCache readTileForForecast:diskKey z:z x:x y:y];
    if (diskData) {
        [self.memoryCache setObject:diskData forKey:memoryKey];
        NSLog(@"[WindTileServer] %@ 磁盘缓存命中 %@ (%lu bytes)", type, coordinateKey, (unsigned long)diskData.length);
        return diskData;
    }
    
    // 3. 远程下载 + 渲染
    NSString *remoteUrl = [NSString stringWithFormat:@"%@/%@/%@", self.currentBaseUrl, coordinateKey, [self remoteSuffixForType:type]];
    NSData *pngData = [self fetchAndRender:remoteUrl type:type];
    
    [self.diskCache writeTile:pngData forForecast:diskKey z:z x:x y:y];
    [self.memoryCache setObject:pngData forKey:memoryKey];
    
    NSLog(@"[WindTileServer] %@ 下载瓦片 %@ (%lu bytes)", type, coordinateKey, (unsigned long)pngData.length);
    return pngData;
}

- (NSData *)fetchAndRender:(NSString *)urlString type:(WeatherLayerType)type {
    NSLog(@"[DEBUG] Fetching from URL: %@", urlString);
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSData *jpegData = [NSData dataWithContentsOfURL:url];
    if (!jpegData) {
        NSLog(@"[DEBUG] Failed to fetch JPEG");
        @throw [NSException exceptionWithName:@"FetchError" reason:@"无法下载图片" userInfo:nil];
    }
    
#if DEBUG
    // 保存原始 JPEG 到缓存文件夹，用于与渲染结果对比
    static NSInteger _rawCount = 0;
    if (_rawCount < 10) {
        NSString *cacheDir = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject;
        NSString *rawDir = [cacheDir stringByAppendingPathComponent:@"raw_jpegs"];
        [[NSFileManager defaultManager] createDirectoryAtPath:rawDir withIntermediateDirectories:YES attributes:nil error:nil];
        
        NSString *filename = [NSString stringWithFormat:@"pair_%03ld_raw.jpg", (long)_rawCount];
        NSString *savePath = [rawDir stringByAppendingPathComponent:filename];
        [jpegData writeToFile:savePath atomically:YES];
        NSLog(@"[DEBUG] 📦 原始 JPEG 已保存: %@", savePath);
        _rawCount++;
    }
#endif
    
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
    // ⚠️ 不能翻转！UIImage.CGImage 的像素存储本身是颠倒的（row 0 = 视觉底部），
    // 若再翻转，fullPixels 的 row 4 会指向数据区而不是头部编码行，导致头部解析出垃圾值。
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
    
    // ⭐ 第四步：解码气象数据（裁剪后的像素，从 row 0 开始，无需跳行）
#if DEBUG
    // 诊断：打印裁剪后数据区的原始像素
    NSLog(@"[DEBUG] 📍 dataPixels 前5个像素值:");
    for (int i = 0; i < 5; i++) {
        NSLog(@"  [%d] = 0x%08X", i, dataPixels[i]);
    }
    // 打印数据区第 50 行的几个像素
    NSLog(@"[DEBUG] 📍 dataPixels row50 col0-4:");
    for (int i = 0; i < 5; i++) {
        NSLog(@"  [50,%d] = 0x%08X", i, dataPixels[50 * fullWidth + i]);
    }
#endif
    uint32_t *coloredPixels = NULL;
    
    if ([type isEqualToString:WeatherLayerTypePressure]) {
        // 气压：R 通道编码 hPa
        float *pressures = [WindyWindTileDecoder decodePressureDataPixels:dataPixels
                                                                    width:fullWidth
                                                                   height:dataHeight
                                                                   header:header];
        coloredPixels = [PressureColorizer colorizePressure:pressures size:256 * 256];
        free(pressures);
        NSLog(@"[DEBUG] 气压着色完成");
    } else {
        // 风场：R/G 通道编码 u/v
        WindField *field = [WindyWindTileDecoder decodeDataPixels:dataPixels
                                                            width:fullWidth
                                                           height:dataHeight
                                                           header:header];
        
#if DEBUG
        // 诊断：打印解码后的 u/v 和风速
        NSLog(@"[DEBUG] 📍 解码后前5个点 u/v/speed:");
        for (int i = 0; i < 5; i++) {
            float u = field->u[i];
            float v = field->v[i];
            if (!isnan(u) && !isnan(v)) {
                NSLog(@"  [%d] u=%.2f v=%.2f speed=%.2f", i, u, v, sqrtf(u*u+v*v));
            } else {
                NSLog(@"  [%d] 缺测 NaN", i);
            }
        }
#endif
        
        coloredPixels = [WindSpeedColorizer colorizeField:field];
        free(field->u);
        free(field->v);
        free(field);
        NSLog(@"[DEBUG] 风场着色完成");
    }
    free(dataPixels);
    NSLog(@"[DEBUG] 气象数据解码完成");
#if DEBUG
    // 诊断：打印着色后的像素值
    NSLog(@"[DEBUG] 📍 着色后前5个像素:");
    for (int i = 0; i < 5; i++) {
        uint32_t p = coloredPixels[i];
        NSLog(@"  [%d] = 0x%08X (A=%d R=%d G=%d B=%d)",
              i, p,
              (p >> 24) & 0xFF,
              (p >> 16) & 0xFF,
              (p >> 8) & 0xFF,
              p & 0xFF);
    }
#endif
    
    // ⭐ 第六步：输出 256x256 PNG
    // 注意：CGBitmapContextCreateImage 不受 CTM 翻转影响（直接包装像素数据），
    // 因此必须在像素层面垂直翻转 coloredPixels，恢复与原始图片一致的方向。
    {
        uint32_t *flipped = (uint32_t *)malloc(256 * 256 * sizeof(uint32_t));
        for (int y = 0; y < 256; y++) {
            memcpy(&flipped[(255 - y) * 256], &coloredPixels[y * 256], 256 * sizeof(uint32_t));
        }
        memcpy(coloredPixels, flipped, 256 * 256 * sizeof(uint32_t));
        free(flipped);
        NSLog(@"[DEBUG] 🔄 像素已垂直翻转（恢复原始方向）");
    }
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
        
        NSString *filename = [NSString stringWithFormat:@"pair_%03ld_rendered.png", (long)_tileCount];
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
