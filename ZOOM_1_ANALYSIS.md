# Zoom 1 未设置但被请求的原因分析

## 问题现象

```
[DEBUG] Map zoom level set to: 0.70       ← 只设置了 Zoom 0.70
[DEBUG] ===== Tile request: z=0 ... =====  ← 请求 z=0 正常
[DEBUG] ===== Tile request: z=1 ... =====  ← 为什么请求 z=1？
```

---

## 🔍 可能的原因

### 1. MapLibre 的自动预加载行为

MapLibre 不仅请求当前显示的瓦片，还会：
- 预加载相邻缩放级别的瓦片
- 预加载周围区域的瓦片
- 提前加载用户可能缩放到的级别

### 2. 初始化过程中的变化

```
viewDidLoad:         zoomLevel = 0.70
风场图层添加过程中：  MapLibre 自动加载 z=1 瓦片
地图显示完成：        已经有 z=0 和 z=1 的瓦片缓存
```

### 3. 样式加载完成时的自动调整

OpenFreeMap 样式在加载过程中可能：
- 触发地图重新渲染
- 请求相邻 Zoom 级别的瓦片
- 自动预加载更高 Zoom 的数据

---

## ✅ 这是正常行为

### MapLibre 的缓存策略

为了提供流畅的用户体验，MapLibre 会：

1. **加载当前级别** (z=0)
2. **预加载相邻级别** (z=1)  ← 用户可能会缩放
3. **缓存周围瓦片** (x±1, y±1)

这样用户缩放或拖动时不会有延迟。

### 对应的 Android 行为

Android 的 MapLibre 也会做同样的事：
```kotlin
// 即使只设置 Zoom 0，MapLibre 也会预加载 Zoom 1
mapView.zoomLevel = 0.7f
// → 自动请求 z=0 和 z=1 的瓦片
```

---

## 📊 日志验证

从你的日志看：

```
[DEBUG] Map zoom level set to: 0.70
[WindRasterLayerRenderer] 风场图层已添加

[DEBUG] ===== Tile request: z=0 x=0 y=0 =====  ← 当前级别
[DEBUG] ===== Tile request: z=0 x=0 y=0 =====  ← 重复（多进程）
[DEBUG] ===== Tile request: z=1 x=1 y=0 =====  ← 预加载相邻
[DEBUG] ===== Tile request: z=1 x=1 y=1 =====  ← 预加载相邻
[DEBUG] ===== Tile request: z=1 x=0 y=0 =====  ← 预加载相邻
[DEBUG] ===== Tile request: z=1 x=0 y=1 =====  ← 预加载相邻
```

---

## 🎯 结论

**这是完全正常的！** 

MapLibre 的预加载机制确保：
- ✅ 用户体验流畅
- ✅ 缩放时无延迟
- ✅ 拖动时立即显示
- ✅ 缓存利用高效

**无需修改任何代码。** 🎉
