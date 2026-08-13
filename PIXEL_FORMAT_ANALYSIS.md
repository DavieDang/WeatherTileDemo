# 像素格式深度分析

## Android 实现（参考）

### BitmapFactory 像素格式

```kotlin
// Android: BitmapFactory.decodeStream()
val encoded = BitmapFactory.decodeStream(input, null, options)
val pixels = IntArray(width * height)
encoded.getPixels(pixels, 0, width, 0, 0, width, height)

// Android ARGB_8888 格式
// pixels[i] = 0xAARRGGBB (Int32)
// 位移提取：
val red = (argb ushr 16) and 0xFF    // 次高字节
val green = (argb ushr 8) and 0xFF   // 次低字节
val blue = argb and 0xFF             // 最低字节
```

**关键点**：Android `IntArray` 是 **有符号 32 位整数**，但位运算结果一致。

---

## iOS 实现对比

### CGBitmapContext 像素格式

```objc
// iOS: CGBitmapContextCreate
CGContextRef context = CGBitmapContextCreate(
    pixels,                          // 输出缓冲区
    width, height,                   // 尺寸
    8,                              // bits per component
    width * 4,                      // bytes per row
    colorSpace,
    kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
);
```

**问题关键**：`kCGBitmapByteOrder32Big` 的含义！

---

## 字节序深度分析

### kCGBitmapByteOrder32Big 的实际布局

根据 Apple 文档，`kCGBitmapByteOrder32Big` 表示：
- **大端序**（Big Endian）
- **内存字节顺序**：从高地址到低地址依次存储 A、R、G、B

#### 内存布局示例

假设像素值 `0xFFAABBCC`（A=FF, R=AA, G=BB, B=CC）：

```
Big Endian (kCGBitmapByteOrder32Big):
内存地址:  [0]   [1]   [2]   [3]
内存内容:  0xFF  0xAA  0xBB  0xCC
          ↑     ↑     ↑     ↑
        Alpha  Red  Green  Blue
```

#### 按 uint32_t 读取时

```c
uint32_t pixel = *(uint32_t*)&memory[0];

// Big Endian 系统（ARM64）:
pixel = 0xFFAABBCC  // 直接匹配内存顺序

// 位移提取：
Alpha = (pixel >> 24) & 0xFF  // 0xFF
Red   = (pixel >> 16) & 0xFF  // 0xAA
Green = (pixel >> 8) & 0xFF   // 0xBB
Blue  = pixel & 0xFF          // 0xCC
```

---

## ❌ 当前 iOS 代码的问题

### 当前提取方式

```objc
uint8_t blue = pixel & 0xFF;          // ❌ 提取最低字节
uint8_t green = (pixel >> 8) & 0xFF;  // ❌ 提取次低字节
uint8_t red = (pixel >> 16) & 0xFF;   // ❌ 提取次高字节
```

### 为什么错误？

如果 `kCGBitmapByteOrder32Big` 按字面意思理解：

**大端序 + PremultipliedLast**：
```
pixel = 0xAARRGGBB (内存顺序)
按 uint32_t 读取时：
- Big Endian 系统: pixel = 0xAARRGGBB
  → Alpha 在最高字节 (pixel >> 24)
  → Red 在次高字节 (pixel >> 16)
  → Green 在次低字节 (pixel >> 8)
  → Blue 在最低字节 (pixel & 0xFF)
```

但实际上，**iOS 可能使用了小端序**（Little Endian）！

---

## 🔍 真正的问题：字节序判断错误

### 验证方法

需要打印实际像素值来判断：

```objc
// 解码后打印第一个像素
uint32_t firstPixel = pixels[0];
NSLog(@"First pixel: 0x%08X", firstPixel);

// 从 CGImage 获取颜色验证
// 如果原图某像素是红色 (R=255, G=0, B=0, A=255)
// 那么：
// - 大端 ARGB: 0xFF_FF_00_00
// - 小端 ARGB: 0x00_00_FF_FF
```

---

## 🚨 可能的根本原因

### 原因 1: 字节序理解错误

**iOS CGBitmapContext 实际使用小端序**：

```objc
// 小端序（实际情况）
pixel = 0xBBGGRRAA (uint32_t 表示)

// 正确提取：
uint8_t alpha = pixel & 0xFF;          // A
uint8_t red = (pixel >> 8) & 0xFF;     // R
uint8_t green = (pixel >> 16) & 0xFF;  // G
uint8_t blue = (pixel >> 24) & 0xFF;   // B
```

### 原因 2: Y 轴翻转导致像素错位

Y 轴翻转可能导致：
- 头部的 8 行元数据被读取到了错误位置
- 数据区的像素被错误解析

---

## 🎯 诊断步骤

### Step 1: 打印第一个瓦片的原始数据

```objc
// 在 fetchAndRender 中添加日志
NSLog(@"[DEBUG] JPEG size: %ldx%ld", width, height);
NSLog(@"[DEBUG] First 10 pixels:");
for (int i = 0; i < 10; i++) {
    NSLog(@"  pixels[%d] = 0x%08X", i, pixels[i]);
}
```

### Step 2: 验证头部解码

```objc
// 在 decodeHeader 中添加日志
NSLog(@"[DEBUG] Header: rMin=%.2f rMax=%.2f gMin=%.2f gMax=%.2f",
      header.rMin, header.rMax, header.gMin, header.gMax);
```

### Step 3: 验证风速计算

```objc
// 在 colorizeField 中添加日志
float sampleSpeed = sqrtf(field->u[1000] * field->u[1000] + 
                          field->v[1000] * field->v[1000]);
NSLog(@"[DEBUG] Sample wind speed at index 1000: %.2f m/s", sampleSpeed);
```

---

## 🔧 建议修复方案

### 方案 A: 使用 UIImage 的标准方法

```objc
// 避免直接操作 CGBitmapContext
UIImage *jpegImage = [UIImage imageWithData:jpegData];
CGImageRef cgImage = jpegImage.CGImage;

// 使用 CGDataProvider 获取原始字节
CFDataRef rawData = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
const uint8_t *bytes = CFDataGetBytePtr(rawData);

// 手动解析每个像素（根据 CGImageGetBitsPerPixel 判断格式）
size_t bytesPerPixel = CGImageGetBitsPerPixel(cgImage) / 8;
for (size_t i = 0; i < width * height; i++) {
    size_t offset = i * bytesPerPixel;
    uint8_t red = bytes[offset];
    uint8_t green = bytes[offset + 1];
    uint8_t blue = bytes[offset + 2];
    uint8_t alpha = bytes[offset + 3];
    pixels[i] = (alpha << 24) | (red << 16) | (green << 8) | blue;
}

CFRelease(rawData);
```

### 方案 B: 使用 Android 一致的像素格式

```objc
// 强制使用 RGBA8888 格式（与 Android ARGB_8888 对应）
CGContextRef context = CGBitmapContextCreate(
    pixels, width, height, 8, width * 4,
    colorSpace,
    kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
    // ↑ 改为 Little Endian
);
```

---

## 📋 待确认的关键问题

1. ❓ iOS 实际使用的字节序是什么？（需要打印验证）
2. ❓ Y 轴翻转是否正确？（是否应该翻转？）
3. ❓ 头部解码的像素是否来自正确的行？
4. ❓ 颜色全灰是否因为风速计算结果全为 0 或 NaN？

---

**下一步**：添加调试日志，打印实际像素值，确认字节序和数据正确性。
