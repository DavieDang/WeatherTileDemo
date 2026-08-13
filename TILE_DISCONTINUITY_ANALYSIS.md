# 瓦片断层问题分析

## 问题现象

部分瓦片连续正确，部分瓦片出现断层（拼接错位）。

---

## 可能的原因

### 1. 瓦片边界像素处理问题

**Windy wm_grid_257 格式特点**：
```
原始 JPEG: 257x265
- 前 8 行: 元数据头部
- 257x257: 实际数据区
- 第一列（x=0）: 应该被跳过

输出瓦片: 256x256
```

**当前代码问题**：
```objc
// WindyWindTileDecoder.m
for (NSInteger x = 0; x < kTileSize; x++) {
    uint32_t pixel = pixels[sourceOffset + x];  // ❌ 读取 x=0..255
    // 但应该读取 x=1..256（跳过第一列）
}
```

**正确做法**（参考 Android）：
```kotlin
// Android 代码
for (x in 0 until TILE_SIZE) {
    val sourceIndex = sourceOffset + (x + 1)  // ✅ 跳过第一列
    val pixel = encoded.pixels[sourceIndex]
}
```

---

### 2. Y 轴坐标可能仍然颠倒

如果使用 `CGDataProviderCopyData` 读取的像素是上下颠倒的，会导致：
- 头部（前 8 行）读取到错误位置
- 数据区上下翻转

**验证方法**：
```objc
// 检查第一行像素是否是头部元数据模式
// 头部像素通常有特定的规律（每隔 4 个像素）
```

---

### 3. 256 vs 257 宽度不匹配

JPEG 宽度是 **257**，但我们需要的瓦片是 **256**。

如果直接按 256 宽度读取，最后一列会缺失。

**当前代码**：
```objc
for (NSUInteger x = 0; x < width; x++) {  // width = 257
    size_t byteOffset = y * bytesPerRow + x * bytesPerPixel;
    pixels[y * width + x] = ...;  // ❌ 按 257 宽度存储
}
```

**问题**：`WindyWindTileDecoder` 期望 257 宽度，但输出需要 256 宽度。

---

## 🔍 诊断步骤

### Step 1: 检查像素读取宽度

添加日志验证：

```objc
NSLog(@"[DEBUG] Reading pixel at y=%d x=%d, sourceOffset=%zu", 
      0, 0, 0 * bytesPerRow + 0 * bytesPerPixel);
NSLog(@"[DEBUG] Reading pixel at y=%d x=%d, sourceOffset=%zu", 
      4, 2, 4 * bytesPerRow + 2 * bytesPerPixel);  // 头部第一个字节位置
```

### Step 2: 验证头部位置

```objc
// 在 decodeHeader 中添加
NSLog(@"[DEBUG] Header pixel index: %ld", (long)pixelIndex);
NSLog(@"[DEBUG] Header first pixel: 0x%08X", pixels[pixelIndex]);
```

### Step 3: 检查断层瓦片的坐标

```objc
// 在 tileForZ 中记录断层瓦片
NSLog(@"[DEBUG] Tile %ld/%ld/%ld loaded", (long)z, (long)x, (long)y);
```

---

## 🎯 最可能的原因

### 原因 A: 第一列未跳过（最可能）

**表现**：所有瓦片都错位 1 像素

**修复**：
```objc
// WindyWindTileDecoder.m 数据区解码
for (NSInteger x = 0; x < kTileSize; x++) {
    uint32_t pixel = pixels[sourceOffset + x + 1];  // ✅ 跳过第一列
}
```

### 原因 B: Y 轴仍然颠倒

**表现**：瓦片上下颠倒，断层出现在 Y 坐标

**修复**：需要翻转读取的像素数组

```objc
// 读取时翻转 Y 轴
for (NSUInteger y = 0; y < height; y++) {
    NSUInteger flippedY = height - 1 - y;  // 翻转
    for (NSUInteger x = 0; x < width; x++) {
        size_t byteOffset = flippedY * bytesPerRow + x * bytesPerPixel;
        pixels[y * width + x] = ...;
    }
}
```

### 原因 C: 部分瓦片请求失败

**表现**：断层位置固定，缺失瓦片显示为透明

**排查**：查看控制台是否有 HTTP 404 错误

---

## 建议修复顺序

1. ✅ 先修复"跳过第一列"问题（最可能）
2. ⏳ 验证 Y 轴是否正确
3. ⏳ 检查网络请求是否有失败

---

**下一步**：修复 WindyWindTileDecoder.m 的第一列跳过逻辑
