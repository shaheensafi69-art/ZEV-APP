Pod::Spec.new do |s|
  s.name             = 'easy_compressor'
  s.version          = '1.0.0'
  s.summary          = 'Cross-platform video compression using native APIs.'
  s.description      = <<-DESC
A Flutter plugin for high-quality video compression using native platform APIs.
No FFmpeg dependency. Supports quality 0-100 parameter.
                       DESC
  s.homepage         = 'https://github.com/KHKikani/easy_compressor'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'KHKikani' => 'harshitkikani@gmail.com' }
  s.source           = { :http => 'https://github.com/KHKikani/easy_compressor' }
  s.source_files     = 'Classes/**/*'
  s.platform         = :ios, '13.0'
  s.swift_version    = '5.9'
  s.dependency 'Flutter'
  s.frameworks       = 'AVFoundation', 'CoreMedia', 'CoreVideo'
  s.ios.deployment_target = '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
