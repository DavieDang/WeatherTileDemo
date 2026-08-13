# 地图缩放级别问题分析

## 问题现象

- **设置的缩放级别**: 0.7
- **移动地图后的缩放级别**: 2.0

---

## 可能的原因

### 1. 地图初始化时的缩放设置被覆盖

```objc
// ViewController.m
self.mapView.zoomLevel = 0.7;  // 设置了 0.7

// 但是，如果在 mapView:didFinishLoadingStyle: 中又设置了其他值
- (void)mapView:(MLNMapView *)mapView didFinishLoadingStyle:(MLNStyle *)style {
    // 如果这里又修改了缩放级别...
}
```

### 2. MapLibre 的自动调整行为

MapLibre 可能会根据以下因素自动调整缩放级别：
- **minZoom / maxZoom 限制**
- **centerCoordinate 的有效性**
- **样式加载完成后的默认行为**

### 3. 样式文件的默认缩放

某些 MapLibre 样式文件（如 OpenFreeMap）可能在样式 JSON 中定义了默认缩放级别：

```json
{
  "center": [115.0, 30.0],
  "zoom": 2.0  // ← 样式文件的默认缩放
}
```

---

## 诊断方法

### 添加调试日志

在 `ViewController.m` 中添加：

```objc
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // ... 地图初始化代码 ...
    
    self.mapView.zoomLevel = 0.7;
    NSLog(@"[DEBUG] Initial zoom set to: %.2f", self.mapView.zoomLevel);
}

- (void)mapView:(MLNMapView *)mapView didFinishLoadingStyle:(MLNStyle *)style {
    NSLog(@"[DEBUG] Style loaded, current zoom: %.2f", mapView.zoomLevel);
    
    // 添加风场图层...
    
    NSLog(@"[DEBUG] After adding layers, zoom: %.2f", mapView.zoomLevel);
}

// 监听缩放变化
- (void)mapView:(MLNMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    NSLog(@"[DEBUG] Region changed, zoom: %.2f", mapView.zoomLevel);
}
```

---

## 可能的修复方案

### 方案 A: 在样式加载完成后重新设置缩放

```objc
- (void)mapView:(MLNMapView *)mapView didFinishLoadingStyle:(MLNStyle *)style {
    // 添加风场图层
    [renderer addToMapView:mapView];
    
    // ✅ 样式加载完成后，强制设置缩放
    [mapView setZoomLevel:0.7 animated:NO];
    [mapView setCenterCoordinate:CLLocationCoordinate2DMake(30.0, 115.0) 
                        zoomLevel:0.7 
                         animated:NO];
}
```

### 方案 B: 延迟设置缩放

```objc
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // ... 地图初始化 ...
    
    // 延迟设置缩放，确保样式已加载
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), 
                   dispatch_get_main_queue(), ^{
        [self.mapView setZoomLevel:0.7 animated:NO];
        NSLog(@"[DEBUG] Delayed zoom set to: %.2f", self.mapView.zoomLevel);
    });
}
```

### 方案 C: 使用 setCenterCoordinate:zoomLevel:

```objc
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // ... 地图初始化 ...
    
    // ✅ 同时设置中心点和缩放（更可靠）
    [self.mapView setCenterCoordinate:CLLocationCoordinate2DMake(30.0, 115.0) 
                            zoomLevel:0.7 
                             animated:NO];
}
```

---

## 检查点

### 1. 检查 ViewController.m 中的缩放设置

找到所有设置 `zoomLevel` 的地方：
```bash
grep -n "zoomLevel" WeatherTileDemo/ViewController.m
```

### 2. 检查是否有 minZoom / maxZoom 限制

```objc
// 如果设置了这些，可能会限制缩放范围
self.mapView.minimumZoomLevel = 0;
self.mapView.maximumZoomLevel = 4;
```

### 3. 检查样式 URL

如果使用的样式有内置的默认缩放，需要在加载后覆盖：
```objc
NSURL *styleURL = [NSURL URLWithString:@"https://tiles.openfreemap.org/styles/bright"];
```

---

**下一步**：添加上述调试日志，查看缩放级别在什么时候被改变了。
