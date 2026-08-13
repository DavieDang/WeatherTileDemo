platform :ios, '13.0'

target 'WeatherTileDemo' do
  use_frameworks!

  # MapLibre for map rendering
  pod 'MapLibre', '~> 6.8.0'
  
  # GCDWebServer for local tile server
  pod 'GCDWebServer', '~> 3.5.4'
end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
    end
  end
end
