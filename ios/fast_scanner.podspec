#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint fast_scanner.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'fast_scanner'
  s.version          = '5.1.1'
  s.summary          = 'An universal scanner for Flutter based on MLKit.'
  s.description      = <<-DESC
An universal scanner for Flutter based on MLKit.
                       DESC
  s.homepage         = 'https://github.com/juliansteenbakker/fast_scanner'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Julian Steenbakker' => 'juliansteenbakker@outlook.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.static_framework = true
  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
  s.resource_bundles = { 'fast_scanner_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
end
