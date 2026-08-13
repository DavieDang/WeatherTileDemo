# WeatherTileDemo - iOS 气象瓦片显示 Demo

## 项目说明

这是一个基于 MapLibre + Windy 数据的 iOS 气象风场可视化 Demo，完整复刻了 Android 版本的技术方案。

## 技术架构

### 核心流程
```
Windy CDN (编码 JPEG)
      ↓
本地 HTTP 服务器 (GCDWebServer)
      ↓
解码 (WindyWindTileDecoder)
      ↓
着色 (WindSpeedColorizer)
      ↓
PNG 瓦片
      ↓
MapLibre RasterLayer
```

### 关键模块

1. **WindTileServer** - 本地瓦片服务器
   - 绑定 127.0.0.1 随机端口
   - 三级缓存（内存 LRU + 磁盘预报时次 + 远程下载）
   - 处理 MapLibre 的 `{z}/{x}/{y}` 瓦片请求

2. **WindyWindTileDecoder** - Windy JPEG 解码器
   - 解析 257x265 编码 JPEG
   - 提取头部范围参数（u/v min/max）
   - 反量化 RGB 像素为风速分量 (m/s)

3. **WindSpeedColorizer** - 风速着色器
   - 计算风速 `sqrt(u² + v²)`
   - 20 级 Windy 色阶表插值
   - 对比度增强

4. **WindyForecastResolver** - 预报时次解析
   - 查询 Windy manifest API
   - 获取最新 ECMWF HRES 预报时次

5. **WindTileDiskCache** - 磁盘缓存
   - 按预报时次分目录
   - 自动清理旧缓存
   - 原子写入

6. **WindRasterLayerRenderer** - MapLibre 集成
   - 添加 RasterTileSource
   - 插入合适的图层顺序
   - 海岸线增强

## 依赖

- **MapLibre** 6.8.0 - MapLibre 地图渲染
- **GCDWebServer** 3.5.4 - 本地 HTTP 服务器

## 构建步骤

### 1. 安装依赖

由于 CocoaPods 环境问题，建议手动下载框架：

```bash
# 方案 A：如果 pod 可用
pod install

# 方案 B：手动集成（推荐）
# 1. 下载 MapLibre SDK: https://github.com/maplibre/maplibre-native/releases
# 2. 下载 GCDWebServer: https://github.com/swisspol/GCDWebServer/releases
# 3. 拖入 Xcode 项目
```

### 2. 打开项目

```bash
open WeatherTileDemo.xcworkspace  # 如果使用 CocoaPods
# 或
open WeatherTileDemo.xcodeproj     # 如果手动集成
```

### 3. 配置签名

在 Xcode 中：
1. 选择项目 → Target → Signing & Capabilities
2. 设置 Team
3. 修改 Bundle Identifier（如果需要）

### 4. 运行

选择模拟器或真机，按 Cmd+R 运行。

## 项目结构

```
WeatherTileDemo/
├── AppDelegate.h/m          - 应用入口
├── ViewController.h/m       - 主界面（地图 + 图例）
├── WindTileServer.h/m       - 本地瓦片服务器
├── WindyWindTileDecoder.h/m - Windy JPEG 解码器
├── WindSpeedColorizer.h/m   - 风速着色器
├── WindyForecastResolver.h/m- 预报时次解析
├── WindTileDiskCache.h/m    - 磁盘缓存
├── WindRasterLayerRenderer.h/m - MapLibre 渲染器
├── LaunchScreen.storyboard  - 启动屏幕
└── Info.plist               - 应用配置
```

## 功能特性

✅ 实时下载 Windy ECMWF HRES 风场数据  
✅ 本地解码 + 自定义着色（20 级色阶）  
✅ 三级缓存（内存 64 瓦片 + 磁盘按预报时次）  
✅ MapLibre 栅格图层无缝集成  
✅ 支持缩放 0-4 级（全球到区域）  
✅ 海岸线增强显示  

## 技术细节

### Windy 编码格式

```
JPEG 尺寸: 257x265
┌─────────────────────┐
│ 前 8 行: 元数据头部  │ ← 存储 u/v 范围
├─────────────────────┤
│ 后 257x257: 数据区  │
│ R 通道 → u 分量     │
│ G 通道 → v 分量     │
│ B≥192 → 缺测标记    │
└─────────────────────┘
输出: 256x256 PNG
```

### 缓存策略

- **内存缓存**: NSCache，最多 64 个瓦片，LRU 淘汰
- **磁盘缓存**: 按预报时次分目录（如 `2026080912_2026080915/`）
- **版本化**: 色阶调整时递增版本号，避免冲突

### 性能优化

- 并发下载（GCD 并发队列）
- 原子写入（临时文件 + rename）
- 自动清理旧预报时次
- MapLibre 内置瓦片缓存

## 已知限制

- Windy 最大支持 zoom=4（约 50km/像素）
- JPEG 量化精度约 ±0.1 m/s
- 首次加载需要网络连接

## 版权说明

- 风场数据来源: Windy.com / ECMWF
- 仅供学习研究使用
- 商业使用需获取 Windy API 授权

## License

MIT

---

**开发日期**: 2026-08-12  
**iOS 版本要求**: iOS 13.0+  
**语言**: Objective-C  
**参考项目**: simple_app (Android Kotlin)
