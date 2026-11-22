Pod::Spec.new do |s|
  s.name             = 'ipareader_ffi'
  s.version          = '1.0.0'
  s.summary          = 'IPAReader speech synthesis (IPA to speech) via dart:ffi.'
  s.description      = 'Compiles GMWester/IPAReader C sources for Flutter.'
  s.homepage         = 'https://github.com/GMWester/IPAReader'
  s.license          = { :type => 'AGPL-3.0', :file => '../LICENSE' }
  s.author           = { 'GMWester' => 'https://github.com/GMWester' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../third_party/ipareader/include" "${PODS_TARGET_SRCROOT}/../third_party/ipareader/src"',
    'GCC_PREPROCESSOR_DEFINITIONS' => 'IPR_BUILD_DLL=1',
    'GCC_C_LANGUAGE_STANDARD' => 'c11',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
  s.swift_version = '5.0'
end
