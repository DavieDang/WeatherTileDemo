# 瓦片问题分析与修复

## 问题 1: 瓦片颜色呈现灰色

### 原因
iOS CGBitmapContext 使用的像素格式与位移操作不匹配。

**错误代码**（原来的实现）:
```objc
// 错误：按 ARGB 大端序提取（0xAARRGGBB → RRGGBBAA）
uint8_t red = (pixel >> 24) & 0xFF;   // 提取 Alpha
uint8_t green = (pixel >> 16) & 0xFF; // 提取 Red
uint8_t blue = (pixel >> 8) & 0xFF;   // 提取 Green
```

实际上 iOS 在使用 `kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast` 时，
内存布局是：`0xAARRGGBB`（标准 ARGB 格式），正确提取方式：

```objc
// 正确：标准 ARGB 格式
uint8_t blue = pixel & 0xFF;           // 最低字节是 Blue
uint8_t green = (pixel >> 8) & 0xFF;   // 次低字节是 Green  
uint8_t red = (pixel >> 16) & 0xFF;    // 次高字节是 Red
uint8_t alpha = (pixel >> 24) & 0xFF;  // 最高字节是 Alpha
```

### 修复
✅ 已修改 `WindyWindTileDecoder.m` 的像素提取逻辑
✅ 已修改头部解码的 RGB 提取顺序

---

## 问题 2: 瓦片显示不全（Y 轴翻转）

### 原因
**CGBitmapContext 坐标系原点在左下角**，而图像数据原点在左上角。

Android BitmapFactory 不会翻转，iOS CGContext 会自动翻转 Y 轴。

### 解决方案（待实现）
需要在 CGContextDrawImage 前翻转 Y 轴坐标系：

```objc
// 方案 A: 翻转 Context 坐标系
CGContextTranslateCTM(context, 0, height);
CGContextScaleCTM(context, 1.0, -1.0);
CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);

// 或方案 B: 使用 UIImage 直接绘制（推荐）
UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, 1.0);
[jpegImage drawAtPoint:CGPointZero];
// 然后从 context 读取像素
```

---

## 问题 3: 瓦片位置排布

### TMS vs XYZ 坐标系

**标准 Web Mercator (XYZ)**:
- Y=0 在北极（地图顶部）
- Y 递增向南

**TMS (Tile Map Service)**:
- Y=0 在南极（地图底部）
- Y 递增向北

### 当前实现
MapLibre 使用 **XYZ 坐标系**，Windy 也使用 XYZ。

**iOS 代码中的 Y 坐标处理**:
```objc
// WindTileServer.m:111
if (y < 0 || y >= dimension) {
    return self.transparentTile;
}
```

**无需转换** - 直接使用 MapLibre 传入的 Y 坐标即可。

### X 轴循环包裹
```objc
// WindTileServer.m:116
NSInteger wrappedX = ((x % dimension) + dimension) % dimension;
```

✅ 已正确实现 X 轴循环（地球是圆的，X 可以无限循环）

---

## 修复总结

### 已完成 ✅
1. **像素格式修正** - RGB 提取顺序改为标准 ARGB 格式
2. **X 轴循环** - 已正确实现包裹逻辑

### 待处理 ⚠️
1. **Y 轴翻转问题** - 需要在图像解码时翻转坐标系
2. **验证瓦片对齐** - 运行后验证瓦片是否正确拼接

---

## 下一步测试验证

运行 App 后检查：
1. ✅ 颜色是否正常（不再是灰色）
2. ⚠️ 瓦片是否完整显示（Y 轴是否正确）
3. ⚠️ 相邻瓦片是否无缝拼接
