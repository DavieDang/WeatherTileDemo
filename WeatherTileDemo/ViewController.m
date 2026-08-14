//
//  ViewController.m
//  WeatherTileDemo
//
//  Created by Agent on 2026-08-12.
//

#import "ViewController.h"
#import "WindTileServer.h"
#import "WindRasterLayerRenderer.h"
@import MapLibre;

@interface ViewController ()<MLNMapViewDelegate>

@property (nonatomic, strong) MLNMapView *mapView;
@property (nonatomic, strong) WindTileServer *tileServer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 启动本地瓦片服务器
    NSString *cacheDir = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
    NSLog(@"===本地===：%@",cacheDir);
    NSString *windCacheDir = [cacheDir stringByAppendingPathComponent:@"wind-tiles"];
    self.tileServer = [[WindTileServer alloc] initWithCacheDirectory:windCacheDir];
    NSString *tileTemplate = [self.tileServer start];
    
    // 创建 MapLibre 地图
    NSURL *styleURL = [NSURL URLWithString:@"https://tiles.openfreemap.org/styles/bright"];
    self.mapView = [[MLNMapView alloc] initWithFrame:self.view.bounds styleURL:styleURL];
    self.mapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.mapView.centerCoordinate = CLLocationCoordinate2DMake(30.0, 115.0);
    self.mapView.zoomLevel = self.mapView.minimumZoomLevel;  // ✅ 修复：明确设置缩放级别为 0.7
    self.mapView.rotateEnabled = NO;
    self.mapView.delegate = self;
    
    [self.view addSubview:self.mapView];
    
    // 添加图例
    [self addLegend];
    
    // 添加缩放级别显示
    [self addZoomLevelDisplay];
    
    NSLog(@"[WeatherTileDemo] 本地瓦片服务器已启动: %@", tileTemplate);
    NSLog(@"[DEBUG] Map zoom level set to: %.2f", self.mapView.zoomLevel);
}

- (void)mapViewDidFinishLoadingMap:(MLNMapView *)mapView{
    // 添加风场图层
    WindRasterLayerRenderer *renderer = [[WindRasterLayerRenderer alloc] initWithTileTemplate:self.tileServer.tileTemplate];
    [renderer addToMapView:self.mapView];
    
    NSLog(@"[WeatherTileDemo] 风场图层已添加到地图");
}

- (void)mapViewRegionIsChanging:(MLNMapView *)mapView{
    UILabel *zoomLabel = [self.view viewWithTag:10001];
    if (zoomLabel) {
        CGFloat zoomLevel = self.mapView.zoomLevel;
        zoomLabel.text = [NSString stringWithFormat:@"Zoom\n%.2f", zoomLevel];
    }
}

- (void)addLegend {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 80)];
    container.backgroundColor = [UIColor colorWithRed:11/255.0 green:16/255.0 blue:32/255.0 alpha:0.86];
    container.layer.cornerRadius = 8;
    
    // 标题
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 9, 200, 20)];
    title.text = @"风速 · ECMWF HRES（m/s）";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:12];
    [container addSubview:title];
    
    // 色带
    UIView *gradient = [[UIView alloc] initWithFrame:CGRectMake(12, 35, 196, 12)];
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = gradient.bounds;
    gradientLayer.startPoint = CGPointMake(0, 0.5);
    gradientLayer.endPoint = CGPointMake(1, 0.5);
    gradientLayer.colors = @[
        (id)[UIColor colorWithRed:98/255.0 green:113/255.0 blue:183/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:74/255.0 green:148/255.0 blue:169/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:83/255.0 green:165/255.0 blue:83/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:167/255.0 green:157/255.0 blue:81/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:161/255.0 green:108/255.0 blue:92/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:175/255.0 green:80/255.0 blue:136/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:117/255.0 green:74/255.0 blue:147/255.0 alpha:1].CGColor,
        (id)[UIColor colorWithRed:231/255.0 green:215/255.0 blue:215/255.0 alpha:1].CGColor,
    ];
    gradientLayer.cornerRadius = 3;
    [gradient.layer addSublayer:gradientLayer];
    [container addSubview:gradient];
    
    // 标签
    NSArray *labels = @[@"0", @"大风 17", @"≥46"];
    NSArray *aligns = @[@(NSTextAlignmentLeft), @(NSTextAlignmentCenter), @(NSTextAlignmentRight)];
    for (int i = 0; i < 3; i++) {
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(12 + i * 65, 53, 65, 18)];
        label.text = labels[i];
        label.textColor = [UIColor colorWithRed:210/255.0 green:218/255.0 blue:232/255.0 alpha:1];
        label.font = [UIFont systemFontOfSize:10];
        label.textAlignment = [aligns[i] integerValue];
        [container addSubview:label];
    }
    
    container.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:container];
    
    [NSLayoutConstraint activateConstraints:@[
        [container.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [container.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [container.widthAnchor constraintEqualToConstant:220],
        [container.heightAnchor constraintEqualToConstant:80]
    ]];
}

- (void)dealloc {
    [self.tileServer stop];
}

#pragma mark - 缩放级别显示

- (void)addZoomLevelDisplay {
    UILabel *zoomLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 16, 120, 40)];
    zoomLabel.tag = 10001;  // 用于后续更新
    zoomLabel.backgroundColor = [UIColor colorWithRed:11/255.0 green:16/255.0 blue:32/255.0 alpha:0.86];
    zoomLabel.textColor = [UIColor colorWithRed:210/255.0 green:218/255.0 blue:232/255.0 alpha:1];
    zoomLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    zoomLabel.textAlignment = NSTextAlignmentCenter;
    zoomLabel.layer.cornerRadius = 8;
    zoomLabel.clipsToBounds = YES;
    zoomLabel.numberOfLines = 2;
    
    // 初始显示
    zoomLabel.text = [NSString stringWithFormat:@"Zoom\n%.2f", self.mapView.zoomLevel];
    
    [self.view addSubview:zoomLabel];
 
}



@end
