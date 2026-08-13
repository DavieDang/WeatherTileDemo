# ✅ 正确的修复方案

## 问题分析

从日志确认：
```
[0] = 0xFFC16180
[DEBUG] Header: rMin=0.00 rMax=0.00 gMin=0.00 gMax=0.00
```

头部全是 0，说明 RGB 提取错误。

## 像素格式验证

iOS `kCGBitmapByteOrder32Big` 的实际格式：

```
pixel = 0xFFC16180

正确提取（与 Android 一致）：
Alpha = (pixel >> 24) & 0xFF = 0xFF  // 255
Red   = (pixel >> 16) & 0xFF = 0xC1  // 193  ← 用于 u 分量
Green = (pixel >> 8) & 0xFF  = 0x61  // 97   ← 用于 v 分量
Blue  = pixel & 0xFF         = 0x80  // 128  ← 用于缺测判断
```

## 最终正确代码

### 数据区解码
```objc
uint8_t red = (pixel >> 16) & 0xFF;
uint8_t green = (pixel >> 8) & 0xFF;
uint8_t blue = pixel & 0xFF;
```

### 头部解码
```objc
uint8_t red = (pixel >> 16) & 0xFF;
uint8_t green = (pixel >> 8) & 0xFF;
uint8_t blue = pixel & 0xFF;
```

## 结论

iOS CGBitmapContext 使用 `kCGBitmapByteOrder32Big | kCGImageAlphaPremultipliedLast` 时，
像素格式与 Android ARGB_8888 **完全一致**，应该使用相同的位移操作。

---

**修复时间**: 2026-08-12
**最终方案**: 与 Android 完全一致的 RGB 提取
