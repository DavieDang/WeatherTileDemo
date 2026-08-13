# 问题根因分析

## 🎯 核心发现

### Android 实现（simple_app）

```kotlin
// 第 207 行：BitmapFactory 直接解码
val encodedBitmap = BitmapFactory.decodeStream(input)

// 第 214-222 行：getPixels 按原始顺序读取
encodedBitmap.getPixels(
    encodedPixels, 0, width, 0, 0, width, height
)
// ↑ 关键：没有 Y 轴翻转，像素顺序就是从上到下、从左到右
```

### iOS 当前实现的错误

❌ **错误 1: 多余的 Y 轴翻转**
```objc
// 当前代码翻转了 Y 轴
CGContextScaleCTM(bitmapContext, 1.0, -1.0);
```

Android 没有翻转，iOS 也不应该翻转！

❌ **错误 2: 像素格式理解错误**

需要验证实际的字节序。

---

## 🔧 修复建议

### 方案 A: 移除 Y 轴翻转（推荐）

完全模仿 Android 的行为，不做任何坐标变换：

```objc
// 简单直接：不翻转
CGContextRef bitmapContext = CGBitmapContextCreate(
    pixels, width, height, 8, width * 4,
    colorSpace,
    kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
);
CGContextDrawImage(bitmapContext, CGRectMake(0, 0, width, height), cgImage);
// 不要 TranslateCTM 和 ScaleCTM
```

### 方案 B: 添加调试日志验证

在修复前，先打印像素值验证字节序：

```objc
// 在 fetchAndRender 中添加
NSLog(@"[DEBUG] JPEG size: %ldx%ld", (long)width, (long)height);
NSLog(@"[DEBUG] First 5 pixels:");
for (int i = 0; i < 5; i++) {
    uint32_t p = pixels[i];
    NSLog(@"  [%d] = 0x%08X (R=%d G=%d B=%d A=%d)", 
          i, p,
          (p >> 16) & 0xFF,  // 假设是标准 ARGB
          (p >> 8) & 0xFF,
          p & 0xFF,
          (p >> 24) & 0xFF);
}

// 在 decodeHeader 后添加
NSLog(@"[DEBUG] Header decoded: rMin=%.2f rMax=%.2f gMin=%.2f gMax=%.2f",
      header.rMin, header.rMax, header.gMin, header.gMax);
```

---

## 📋 修复步骤

1. **立即移除 Y 轴翻转** - 这是最可能的问题
2. **添加调试日志** - 验证像素格式
3. **根据日志调整** RGB 提取顺序

---

准备修复代码...
