# 瓦片缩放级别分析

## Android 配置

### WindRasterLayerRenderer.kt
```kotlin
val tileSet = TileSet("2.2.0", tileTemplate).apply {
    minZoom = 0f
    maxZoom = 4f
    attribution = "Wind data © Windy.com / ECMWF"
}
```

### WindTileServer.kt
```kotlin
const val MAX_DATA_ZOOM = 4

if (z !in 0..MAX_DATA_ZOOM) return transparentTile
```

---

## 结论

Android 获取了 **5 个层级**的瓦片：

- **Zoom 0**: 1 × 1 = 1 个瓦片（全球视图）
- **Zoom 1**: 2 × 2 = 4 个瓦片
- **Zoom 2**: 4 × 4 = 16 个瓦片
- **Zoom 3**: 8 × 8 = 64 个瓦片
- **Zoom 4**: 16 × 16 = 256 个瓦片（最详细）

**总计**: zoom 0-4，共 5 个缩放级别

---

## 为什么最大是 Zoom 4？

### Windy 数据限制

Windy 的 ECMWF HRES 模型数据分辨率有限：
- **时间分辨率**: 3 小时
- **空间分辨率**: 约 9 km（0.1° × 0.1°）

### Zoom 4 对应的实际分辨率

在 Web Mercator 投影中：
- Zoom 4 的一个瓦片覆盖约 **2500 km × 2500 km**
- 256 个像素 → 每像素约 **10 km**

这与 Windy ECMWF 数据的 9 km 分辨率匹配。

### 更高 Zoom 的问题

如果使用 Zoom 5+：
- 每像素分辨率 < 5 km
- 但原始数据只有 9 km 分辨率
- 会导致**过度插值**，没有额外细节

---

## iOS 对比

### WindRasterLayerRenderer.m
```objc
// 当前配置
MLNTileSourceOptionMinimumZoomLevel: @0,
MLNTileSourceOptionMaximumZoomLevel: @4
```

### WindTileServer.m
```objc
// 需要添加验证
if (z < 0 || z > 4) {
    return self.transparentTile;
}
```

---

## 验证 iOS 配置

检查 iOS 代码是否正确限制了缩放级别。
