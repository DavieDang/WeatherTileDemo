# 构建说明

## CocoaPods 环境问题

当前系统的 CocoaPods 环境存在 gem 依赖问题，建议采用以下方案之一：

### 方案 A：修复 CocoaPods（推荐）

```bash
# 1. 切换到系统 Ruby
rvm use system

# 2. 重新安装 CocoaPods
sudo gem install cocoapods

# 3. 安装依赖
cd /Users/admin/Desktop/AgentFile/WeatherTileDemo
pod install

# 4. 打开工作空间
open WeatherTileDemo.xcworkspace
```

### 方案 B：手动集成依赖（无需 CocoaPods）

1. **下载 MapLibre iOS SDK**
   - 访问: https://github.com/maplibre/maplibre-native/releases
   - 下载 MapLibre-6.8.0.zip
   - 解压后将 `MapLibre.framework` 拖入项目

2. **下载 GCDWebServer**
   - 访问: https://github.com/swisspol/GCDWebServer/releases
   - 下载 GCDWebServer-3.5.4.zip
   - 解压后将 `GCDWebServer.framework` 拖入项目

3. **配置 Xcode**
   - 打开 `WeatherTileDemo.xcodeproj`
   - Target → General → Frameworks, Libraries, and Embedded Content
   - 添加两个框架，Embed 设置为 "Embed & Sign"

4. **构建运行**
   ```bash
   open WeatherTileDemo.xcodeproj
   # 在 Xcode 中 Cmd+R 运行
   ```

### 方案 C：使用 Swift Package Manager（替代方案）

如果 CocoaPods 无法修复，可以考虑用 SPM 替换：

```bash
# 在 Xcode 中:
# File → Add Package Dependencies
# 添加:
# - https://github.com/maplibre/maplibre-native (MapLibre)
# - https://github.com/swisspol/GCDWebServer (GCDWebServer)
```

## 验证项目结构

当前已创建文件：

✅ Podfile (CocoaPods 配置)  
✅ WeatherTileDemo.xcodeproj (Xcode 项目)  
✅ WeatherTileDemo/ (源代码目录)  
  ├── AppDelegate.h/m  
  ├── ViewController.h/m  
  ├── WindTileServer.h/m  
  ├── WindyWindTileDecoder.h/m  
  ├── WindSpeedColorizer.h/m  
  ├── WindyForecastResolver.h/m  
  ├── WindTileDiskCache.h/m  
  ├── WindRasterLayerRenderer.h/m  
  ├── LaunchScreen.storyboard  
  ├── Info.plist  
  └── main.m  

## 快速开始（无需依赖）

如果暂时无法解决依赖问题，可以先验证代码结构：

```bash
cd /Users/admin/Desktop/AgentFile/WeatherTileDemo

# 查看项目文件
ls -la WeatherTileDemo/

# 验证核心类
grep -l "WindTileServer" WeatherTileDemo/*.m
grep -l "WindyWindTileDecoder" WeatherTileDemo/*.m
```

## 下一步

1. 先修复 CocoaPods 或使用方案 B 手动集成
2. 在 Xcode 中配置签名 Team
3. 选择模拟器运行测试

遇到问题请查看项目目录下的 README.md 获取完整文档。
