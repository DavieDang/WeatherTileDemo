# 瓦片请求问题分析

## 问题 1: 瓦片排列不连续

### 可能的原因

#### A. Y 轴仍然上下颠倒
从 `CGDataProviderCopyData` 读取的像素可能是上下颠倒的。

**验证方法**：
```objc
// 在 fetchAndRender 中添加：
NSLog(@"[DEBUG] Row 0 first pixel: 0x%08X", pixels[0]);
NSLog(@"[DEBUG] Row 4 pixel 2: 0x%08X", pixels[4 * width + 2]);  // 头部位置
NSLog(@"[DEBUG] Last row first pixel: 0x%08X", pixels[(height-1) * width]);
```

如果头部数据在最后一行而不是第 4 行，说明 Y 轴颠倒了。

#### B. 第一列跳过逻辑仍然不对
当前代码：`pixels[sourceOffset + x + 1]`

需要验证 `pixels` 数组的宽度是否确实是 257。

---

## 问题 2: 瓦片层级错误

### 地图缩放级别 vs 瓦片层级

MapLibre 的行为：
- 当地图缩放到最小时（全球视图），应该请求 **Zoom 0** 的瓦片
- 如果请求的是 `/wind/2/3/3`，说明地图缩放级别不是最小

### Zoom 2 对应的地图状态

```
Zoom 2: 4×4 = 16 个瓦片
瓦片 (2, 3, 3) 的含义：
- z=2: 缩放级别 2
- x=3: 横向第 4 个瓦片（0-3）
- y=3: 纵向第 4 个瓦片（0-3）
```

这是正常的，但需要确认：
1. 地图初始缩放级别是多少？
2. MapLibre 是否正确传递了缩放级别？

---

## 诊断步骤

### 1. 验证 Y 轴方向

在 `fetchAndRender` 的像素读取后添加：

```objc
// 打印第 5 行（头部）的前 10 个像素
NSLog(@"[DEBUG] Row 4 pixels (should be header):");
for (int i = 0; i < 10; i++) {
    NSLog(@"  [4,%d] = 0x%08X", i, pixels[4 * width + i]);
}

// 打印第 9 行（数据区第一行）的前 10 个像素
NSLog(@"[DEBUG] Row 8 pixels (should be data):");
for (int i = 0; i < 10; i++) {
    NSLog(@"  [8,%d] = 0x%08X", i, pixels[8 * width + i]);
}
```

### 2. 检查地图初始状态

在 `ViewController.m` 中检查：

```objc
NSLog(@"[DEBUG] Map initial center: lat=%.2f lon=%.2f zoom=%.2f", 
      self.mapView.centerCoordinate.latitude,
      self.mapView.centerCoordinate.longitude,
      self.mapView.zoomLevel);
```

### 3. 验证瓦片请求

在 `tileForZ:x:y:` 中添加：

```objc
NSLog(@"[DEBUG] Tile request: z=%ld x=%ld y=%ld", (long)z, (long)x, (long)y);
```

---

## 可能的修复

### 修复 Y 轴颠倒

如果 Y 轴确实颠倒了，需要在读取像素时翻转：

```objc
for (NSUInteger y = 0; y < height; y++) {
    NSUInteger flippedY = height - 1 - y;  // 翻转 Y 轴
    for (NSUInteger x = 0; x < width; x++) {
        size_t byteOffset = flippedY * bytesPerRow + x * bytesPerPixel;
        // ... 读取像素
        pixels[y * width + x] = ...;  // 存储到正确的位置
    }
}
```
