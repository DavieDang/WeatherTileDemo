# Y 轴翻转后的新问题分析

## 问题现象

```
*** Assertion failure: 无效的 R 通道范围
[DEBUG] Header: rMin=0.00 rMax=0.00 gMin=0.00 gMax=0.00
```

头部解码失败，说明头部数据全是 0。

---

## 根本原因

Y 轴翻转后，头部数据读到了错误的位置。

### Windy 格式结构

```
JPEG 从内存读出的顺序（iOS UIImage）: 上下颠倒
原始内存布局:
Row 0-7:   元数据头部
Row 8-264: 风速数据

但 UIImage 翻转后:
Row 0-7:   风速数据（实际是 Row 257-264）
Row 8-16:  风速数据
...
Row 256+:  元数据头部（实际是 Row 0-7）❌
```

---

## 正确的做法

不应该翻转所有像素，而应该只在**解码头部时**调整坐标。

### 方案 A: 恢复不翻转，在头部解码时调整

```objc
// 不翻转 Y 轴
for (NSUInteger y = 0; y < height; y++) {
    size_t byteOffset = y * bytesPerRow + x * bytesPerPixel;
    pixels[y * width + x] = ...;
}

// 但在 WindyWindTileDecoder 中调整头部位置
// 因为头部在第 4 行，但由于 iOS 坐标系，实际是倒数第 5 行
```

### 方案 B: 分区翻转

只翻转数据区，不翻转头部区。

---

## 推荐修复

使用**方案 A**：恢复原始读取，问题其实不在 Y 轴翻转，而在头部解码位置。
