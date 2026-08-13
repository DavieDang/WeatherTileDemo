# Android vs iOS 关键区别分析

## Android 实现

### 图像解码方式
```kotlin
// 1. BitmapFactory 直接解码
val encodedBitmap = BitmapFactory.decodeStream(input)

// 2. getPixels 提取像素数组
val encodedPixels = IntArray(width * height)
encodedBitmap.getPixels(
    encodedPixels,  // 输出数组
    0,              // offset
    width,          // stride (每行像素数)
    0, 0,           // x, y 起始位置
    width, height   // 宽高
)
```

**关键点**：
- `getPixels` 返回的是 **ARGB_8888** 格式
- 像素顺序：从上到下、从左到右
- **没有任何坐标变换**

---

## iOS 当前实现

### 图像解码方式
```objc
// 1. UIImage 解码
UIImage *jpegImage = [UIImage imageWithData:jpegData];
CGImageRef cgImage = jpegImage.CGImage;

// 2. CGBitmapContextCreate + CGContextDrawImage
CGContextRef context = CGBitmapContextCreate(
    pixels, width, height, 8, width * 4,
    colorSpace,
    kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big
);
CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);
```

**潜在问题**：
1. `CGContextDrawImage` 可能会翻转 Y 轴
2. `kCGBitmapByteOrder32Big` 的实际内存布局不确定
3. 像素可能不是从 (0,0) 开始存储

---

## 关键区别

| 方面 | Android | iOS (当前) |
|------|---------|-----------|
| 解码 API | `BitmapFactory.decodeStream()` | `UIImage imageWithData:` |
| 像素提取 | `getPixels()` - 直接数组拷贝 | `CGContextDrawImage()` - 绘制到 context |
| 坐标系 | 原点左上角，不翻转 | **可能翻转 Y 轴** |
| 像素格式 | ARGB_8888 保证 | 依赖 CGBitmapInfo 配置 |
| 内存布局 | 连续数组，顺序存储 | 依赖 context 配置 |

---

## 🚨 可能的根本问题

### CGContextDrawImage 的坐标系问题

```objc
// CoreGraphics 默认坐标系：原点在左下角
// 图像数据：原点在左上角
// 
// 如果不翻转，绘制的图像是上下颠倒的！
```

### 验证方法

在 `fetchAndRender` 中添加验证代码：

```objc
// 打印第一行和最后一行的像素
NSLog(@"[DEBUG] First row first pixel: 0x%08X", pixels[0]);
NSLog(@"[DEBUG] Last row first pixel: 0x%08X", pixels[(height - 1) * width]);

// 如果第一行是头部元数据，应该是特定的模式
// 如果看到的是数据区，说明 Y 轴颠倒了
```

---

## 建议的修复方案

### 方案 A: 恢复 Y 轴翻转（但使用正确的 RGB 顺序）

```objc
CGContextTranslateCTM(context, 0, height);
CGContextScaleCTM(context, 1.0, -1.0);
CGContextDrawImage(context, CGRectMake(0, 0, width, height), cgImage);

// 使用标准 RGB 提取
uint8_t red = (pixel >> 16) & 0xFF;
uint8_t green = (pixel >> 8) & 0xFF;
uint8_t blue = pixel & 0xFF;
```

### 方案 B: 使用 CGImageGetDataProvider（避免坐标系问题）

```objc
CFDataRef data = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
const uint8_t *bytes = CFDataGetBytePtr(data);

// 手动按字节解析
size_t bytesPerPixel = CGImageGetBitsPerPixel(cgImage) / 8;
for (size_t i = 0; i < width * height; i++) {
    size_t offset = i * bytesPerPixel;
    // 根据 CGImageGetBitmapInfo 判断字节顺序
}

CFRelease(data);
```

---

**下一步**：添加验证日志，确认像素是否上下颠倒。
