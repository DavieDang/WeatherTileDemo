//
//  WindyForecastResolver.m
//  WeatherTileDemo
//

#import "WindyForecastResolver.h"

static NSString *const kMinifestUrl = @"https://node.windy.com/metadata/v1.0/forecast/ecmwf-hres/minifest.json";
static NSString *const kImageServer = @"https://ims.windy.com/im/v3.0/forecast/ecmwf-hres";
static NSString *const kFallbackBaseUrl = @"https://ims.windy.com/im/v3.0/forecast/ecmwf-hres/2026080912/2026080915/wm_grid_257";

@interface WindyForecastResolver ()
@property (nonatomic, copy) NSString *cachedBaseUrl;
@end

@implementation WindyForecastResolver

- (NSString *)resolveBaseUrl {
    if (self.cachedBaseUrl) {
        return self.cachedBaseUrl;
    }
    
    @synchronized (self) {
        if (self.cachedBaseUrl) {
            return self.cachedBaseUrl;
        }
        
        NSString *resolved = [self resolveLatest];
        self.cachedBaseUrl = resolved ?: kFallbackBaseUrl;
        return self.cachedBaseUrl;
    }
}

- (NSString *)resolveLatest {
    @try {
        NSURL *url = [NSURL URLWithString:kMinifestUrl];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                               cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                           timeoutInterval:10.0];
        [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
        [request setValue:@"WeatherTileDemo/1.0" forHTTPHeaderField:@"User-Agent"];
        
        NSError *error = nil;
        NSHTTPURLResponse *response = nil;
        NSData *data = [NSURLConnection sendSynchronousRequest:request
                                             returningResponse:&response
                                                         error:&error];
        
        if (error || response.statusCode != 200) {
            NSLog(@"[WindyForecastResolver] Minifest 请求失败: %@", error ?: @(response.statusCode));
            return nil;
        }
        
        // 解析 JSON
        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        if (error || !json[@"ref"]) {
            NSLog(@"[WindyForecastResolver] JSON 解析失败: %@", error);
            return nil;
        }
        
        NSString *refIso = json[@"ref"]; // "2026-08-09T12:00:00Z"
        
        // 解析 ISO 8601
        NSDateFormatter *isoFormatter = [[NSDateFormatter alloc] init];
        isoFormatter.dateFormat = @"yyyy-MM-dd'T'HH:mm:ss'Z'";
        isoFormatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        isoFormatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        
        NSDate *referenceDate = [isoFormatter dateFromString:refIso];
        if (!referenceDate) {
            NSLog(@"[WindyForecastResolver] 日期解析失败: %@", refIso);
            return nil;
        }
        
        // +3 小时
        NSDate *validDate = [referenceDate dateByAddingTimeInterval:3 * 3600];
        
        // 格式化为 yyyyMMddHH
        NSDateFormatter *pathFormatter = [[NSDateFormatter alloc] init];
        pathFormatter.dateFormat = @"yyyyMMddHH";
        pathFormatter.timeZone = [NSTimeZone timeZoneWithName:@"UTC"];
        
        NSString *reference = [pathFormatter stringFromDate:referenceDate];
        NSString *valid = [pathFormatter stringFromDate:validDate];
        
        NSString *baseUrl = [NSString stringWithFormat:@"%@/%@/%@/wm_grid_257", kImageServer, reference, valid];
        NSLog(@"[WindyForecastResolver] 解析成功: %@", baseUrl);
        
        return baseUrl;
    } @catch (NSException *exception) {
        NSLog(@"[WindyForecastResolver] 异常: %@", exception.reason);
        return nil;
    }
}

@end
