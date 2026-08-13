# 🎨 像素格式修复可视化指南

## 问题根源：平台差异

```
┌─────────────────────────────────────────────────────────────────┐
│                    Android (Kotlin)                             │
├─────────────────────────────────────────────────────────────────┤
│  Bitmap.Config.ARGB_8888                                        │
│  ┌──────────┬──────────┬──────────┬──────────┐                 │
│  │  Alpha   │   Red    │  Green   │  Blue    │                 │
│  │ (Byte 3) │ (Byte 2) │ (Byte 1) │ (Byte 0) │                 │
│  └──────────┴──────────┴──────────┴──────────┘                 │
│           0xAARRGGBB (ARGB 格式)                                │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      iOS (Objective-C)                          │
├─────────────────────────────────────────────────────────────────┤
│  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big      │
│  ┌──────────┬──────────┬──────────┬──────────┐                 │
│  │   Red    │  Green   │  Blue    │  Alpha   │                 │
│  │ (Byte 3) │ (Byte 2) │ (Byte 1) │ (Byte 0) │                 │
│  └──────────┴──────────┴──────────┴──────────┘                 │
│           0xRRGGBBAA (RGBA 格式)                                │
└─────────────────────────────────────────────────────────────────┘
```

## 具体示例：风速 15 m/s

### 步骤 1: 颜色插值
```
风速 15 m/s 对应色阶：
- RGB(161, 108, 92) → 紫红色
- Alpha = 217 (85% 不透明)
```

### 步骤 2: 对比度增强
```
经过 enhanceContrast 处理后：
- enhanced[0] = 161 (Red)
- enhanced[1] = 108 (Green)  
- enhanced[2] = 92  (Blue)
```

### 步骤 3: 像素打包 (关键步骤！)

#### ❌ 修复前 (错误的 ARGB 格式)
```objc
return (kOverlayAlpha << 24) | (enhanced[0] << 16) | (enhanced[1] << 8) | enhanced[2];
       ─────────────────────   ──────────────────   ──────────────────   ──────────
            217 << 24               161 << 16            108 << 8             92

结果：0xD9A16C5C
      └┬┘└┬┘└┬┘└┬┘
       │  │  │  └─ Blue  = 92  (0x5C)
       │  │  └──── Green = 108 (0x6C)
       │  └─────── Red   = 161 (0xA1)
       └────────── Alpha = 217 (0xD9)

内存布局：[0xD9][0xA1][0x6C][0x5C]
           ^^^^  ^^^^  ^^^^  ^^^^
          Byte3 Byte2 Byte1 Byte0
```

#### iOS CGBitmapContext 的错误解释
```
CGBitmapContext 期望 RGBA 格式，但收到 ARGB：

收到的内存：[0xD9][0xA1][0x6C][0x5C]
             ^^^^  ^^^^  ^^^^  ^^^^
解释为：     Red   Green Blue  Alpha
             217   161   108   92

结果：
- Red = 217 ❌ (应该是 161)
- Green = 161 ❌ (应该是 108)
- Blue = 108 ❌ (应该是 92)
- Alpha = 92 ❌ (应该是 217，半透明变成接近透明)

显示效果：完全错误的颜色！
```

#### ✅ 修复后 (正确的 RGBA 格式)
```objc
return (enhanced[0] << 24) | (enhanced[1] << 16) | (enhanced[2] << 8) | kOverlayAlpha;
       ──────────────────   ──────────────────   ──────────────────   ──────────────
            161 << 24            108 << 16             92 << 8              217

结果：0xA16C5CD9
      └┬┘└┬┘└┬┘└┬┘
       │  │  │  └─ Alpha = 217 (0xD9) ✅
       │  │  └──── Blue  = 92  (0x5C) ✅
       │  └─────── Green = 108 (0x6C) ✅
       └────────── Red   = 161 (0xA1) ✅

内存布局：[0xA1][0x6C][0x5C][0xD9]
           ^^^^  ^^^^  ^^^^  ^^^^
          Byte3 Byte2 Byte1 Byte0
```

#### iOS CGBitmapContext 的正确解释
```
CGBitmapContext 期望 RGBA 格式，收到 RGBA：

收到的内存：[0xA1][0x6C][0x5C][0xD9]
             ^^^^  ^^^^  ^^^^  ^^^^
解释为：     Red   Green Blue  Alpha
             161   108   92    217

结果：
- Red = 161 ✅
- Green = 108 ✅
- Blue = 92 ✅
- Alpha = 217 ✅

显示效果：正确的紫红色，85% 不透明！
```

## 颜色对比

### 修复前 (错误)
```
RGB(217, 161, 108) + Alpha(92)
= 浅橙色 + 接近透明
██████ (错误的颜色，几乎看不见)
```

### 修复后 (正确)
```
RGB(161, 108, 92) + Alpha(217)
= 紫红色 + 85% 不透明
██████ (正确的颜色，清晰可见)
```

## 代码对比

### Android 代码 (参考)
```kotlin
// Android 使用 ARGB_8888 格式
val color = (OVERLAY_ALPHA shl 24) or (enhanced[0] shl 16) or (enhanced[1] shl 8) or enhanced[2]
            ─────────────────────────────────────────────────────────────────────────────────
                                        ARGB 格式 ✅

// Android Bitmap 期望 ARGB_8888
val outputBitmap = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
                                                               ──────────────────────
                                                               ARGB 格式 ✅
// 完美匹配！
```

### iOS 代码修复前 (错误)
```objc
// iOS 使用 ARGB 格式（从 Android 直接复制）
return (kOverlayAlpha << 24) | (enhanced[0] << 16) | (enhanced[1] << 8) | enhanced[2];
       ──────────────────────────────────────────────────────────────────────────────
                                   ARGB 格式 ❌

// 但 CGBitmapContext 期望 RGBA 格式
CGBitmapContextCreate(coloredPixels, width, height, 8, width * 4, colorSpace,
                      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
                      ──────────────────────────────────────────────────────
                                    RGBA 格式 ✅
// 格式不匹配！
```

### iOS 代码修复后 (正确)
```objc
// iOS 使用 RGBA 格式（适配 iOS 约定）
return (enhanced[0] << 24) | (enhanced[1] << 16) | (enhanced[2] << 8) | kOverlayAlpha;
       ──────────────────────────────────────────────────────────────────────────────
                                   RGBA 格式 ✅

// CGBitmapContext 期望 RGBA 格式
CGBitmapContextCreate(coloredPixels, width, height, 8, width * 4, colorSpace,
                      kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
                      ──────────────────────────────────────────────────────
                                    RGBA 格式 ✅
// 完美匹配！
```

## 关键要点

### 🔑 为什么 Android 不需要改？
```
Android: 代码输出 ARGB → Bitmap 期望 ARGB → ✅ 匹配
iOS:     代码输出 ARGB → CGContext 期望 RGBA → ❌ 不匹配
         代码输出 RGBA → CGContext 期望 RGBA → ✅ 匹配 (修复后)
```

### 🎯 修复的本质
```
不是修改算法，而是适配平台约定
- 算法：色阶插值、对比度增强 → 完全相同
- 格式：像素打包顺序 → 根据平台调整
```

### 📝 跨平台移植的教训
```
1. 不要盲目复制粘贴代码
2. 理解平台底层的差异
3. 阅读官方文档
4. 测试验证输出格式
```

## 验证清单

运行修复后的 App，检查：

- [ ] 低风速区域显示蓝色 (0-5 m/s)
- [ ] 中风速区域显示绿色/黄色 (5-15 m/s)
- [ ] 高风速区域显示红色/紫色 (15-25 m/s)
- [ ] 透明度正确，可以看到底下的地图
- [ ] 没有明显的颜色断层或错误区域
- [ ] 海陆边界清晰可见

全部通过 = 修复成功！✅

---

**文档创建**: 2026-08-13  
**目的**: 可视化解释像素格式修复的原理
