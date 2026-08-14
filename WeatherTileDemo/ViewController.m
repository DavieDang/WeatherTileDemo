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
@property (nonatomic, strong) WindRasterLayerRenderer *activeRenderer;
@property (nonatomic, copy) WeatherLayerType activeType;
@property (nonatomic, strong) UISegmentedControl *typeControl;

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

    // 添加气象类型切换菜单
    [self addTypeControl];
    
    NSLog(@"[WeatherTileDemo] 本地瓦片服务器已启动: %@", tileTemplate);
    NSLog(@"[DEBUG] Map zoom level set to: %.2f", self.mapView.zoomLevel);
}

- (void)mapViewDidFinishLoadingMap:(MLNMapView *)mapView{
    // 添加默认图层（风场）
    if (!self.activeType) {
        [self switchToType:WeatherLayerTypeWind];
    }
}

- (void)mapViewRegionIsChanging:(MLNMapView *)mapView{
    UILabel *zoomLabel = [self.view viewWithTag:10001];
    if (zoomLabel) {
        CGFloat zoomLevel = self.mapView.zoomLevel;
        zoomLabel.text = [NSString stringWithFormat:@"Zoom\n%.2f", zoomLevel];
    }
}

- (void)addLegend {
    [self updateLegendForType:WeatherLayerTypeWind];
}

- (void)addTypeControl {
    UISegmentedControl *control = [[UISegmentedControl alloc] initWithItems:@[@"风速", @"气压"]];
    control.selectedSegmentIndex = 0;
    control.translatesAutoresizingMaskIntoConstraints = NO;
    control.backgroundColor = [UIColor colorWithRed:11/255.0 green:16/255.0 blue:32/255.0 alpha:0.86];
    control.selectedSegmentTintColor = [UIColor colorWithRed:56/255.0 green:120/255.0 blue:220/255.0 alpha:1];
    [control setTitleTextAttributes:@{
        NSForegroundColorAttributeName: [UIColor whiteColor],
        NSFontAttributeName: [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold]
    } forState:UIControlStateNormal];
    [control addTarget:self action:@selector(typeControlChanged:) forControlEvents:UIControlEventValueChanged];
    self.typeControl = control;
    [self.view addSubview:control];
    
    [NSLayoutConstraint activateConstraints:@[
        [control.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:8],
        [control.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [control.widthAnchor constraintEqualToConstant:200],
        [control.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)typeControlChanged:(UISegmentedControl *)sender {
    WeatherLayerType type = (sender.selectedSegmentIndex == 1)
        ? WeatherLayerTypePressure
        : WeatherLayerTypeWind;
    [self switchToType:type];
}

- (void)switchToType:(WeatherLayerType)type {
    if ([self.activeType isEqualToString:type]) {
        return;
    }
    
    // 移除当前图层
    if (self.activeRenderer) {
        [self.activeRenderer removeFromMapView:self.mapView];
        self.activeRenderer = nil;
    }
    
    // 添加新图层
    NSString *template = [self.tileServer tileTemplateForType:type];
    WindRasterLayerRenderer *renderer = [[WindRasterLayerRenderer alloc] initWithTileTemplate:template type:type];
    [renderer addToMapView:self.mapView];
    
    self.activeRenderer = renderer;
    self.activeType = type;
    
    // 更新图例
    [self updateLegendForType:type];
    
    NSLog(@"[WeatherTileDemo] 已切换气象图层: %@", type);
}

- (void)updateLegendForType:(WeatherLayerType)type {
    // 移除旧图例
    UIView *oldLegend = [self.view viewWithTag:20002];
    [oldLegend removeFromSuperview];
    
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 220, 80)];
    container.tag = 20002;
    container.backgroundColor = [UIColor colorWithRed:11/255.0 green:16/255.0 blue:32/255.0 alpha:0.86];
    container.layer.cornerRadius = 8;
    
    // 标题
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(12, 9, 200, 20)];
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:12];
    [container addSubview:title];
    
    // 色带
    UIView *gradient = [[UIView alloc] initWithFrame:CGRectMake(12, 35, 196, 12)];
    CAGradientLayer *gradientLayer = [CAGradientLayer layer];
    gradientLayer.frame = gradient.bounds;
    gradientLayer.startPoint = CGPointMake(0, 0.5);
    gradientLayer.endPoint = CGPointMake(1, 0.5);
    
    NSArray *colors = nil;
    NSArray *labels = nil;
    
    if ([type isEqualToString:WeatherLayerTypePressure]) {
        title.text = @"海平面气压 · ECMWF HRES（hPa）";
        colors = @[
            (id)[UIColor colorWithRed:120/255.0 green:20/255.0 blue:150/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:45/255.0 green:130/255.0 blue:215/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:90/255.0 green:195/255.0 blue:130/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:220/255.0 green:185/255.0 blue:55/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:235/255.0 green:130/255.0 blue:45/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:228/255.0 green:70/255.0 blue:40/255.0 alpha:1].CGColor,
        ];
        labels = @[@"≤940", @"1000", @"≥1050"];
    } else {
        title.text = @"风速 · ECMWF HRES（m/s）";
        colors = @[
            (id)[UIColor colorWithRed:98/255.0 green:113/255.0 blue:183/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:74/255.0 green:148/255.0 blue:169/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:83/255.0 green:165/255.0 blue:83/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:167/255.0 green:157/255.0 blue:81/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:161/255.0 green:108/255.0 blue:92/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:175/255.0 green:80/255.0 blue:136/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:117/255.0 green:74/255.0 blue:147/255.0 alpha:1].CGColor,
            (id)[UIColor colorWithRed:231/255.0 green:215/255.0 blue:215/255.0 alpha:1].CGColor,
        ];
        labels = @[@"0", @"大风 17", @"≥46"];
    }
    gradientLayer.colors = colors;
    gradientLayer.cornerRadius = 3;
    [gradient.layer addSublayer:gradientLayer];
    [container addSubview:gradient];
    
    // 标签
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
