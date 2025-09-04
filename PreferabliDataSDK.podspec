Pod::Spec.new do |spec|
  spec.name = "PreferabliDataSDK"
  spec.version = "1.0.0"
  spec.summary = "Use this framework to integrate Preferabli's powerful preference technology into your applications."
  spec.homepage = "https://github.com/winering/Preferabli-for-iOS.git"
  spec.license = { :type => 'Preferabli, Inc.', :text => <<-LICENSE
      Copyright 2025
      Permission is granted to use this SDK to customers of Preferabli, Inc.
    LICENSE
  }
  spec.author = { "Preferabli, Inc." => "info@preferabli.com" }
  spec.platform = :ios, "18.0"
  spec.ios.deployment_target = '18.0'
  spec.resources = 'PreferabliDataSDK/PreferabliDataSDK/assets/*.*'
  spec.source = { :git => "https://github.com/winering/Preferabli-for-iOS.git"}
  spec.source_files = 'PreferabliDataSDK/PreferabliDataSDK/**/*.{h,m,swift,md}'
  spec.dependency 'Alamofire'
  spec.dependency 'Mixpanel-swift'
  spec.exclude_files = "PreferabliDataSDK/Pods/**/*.{h,m,swift},PreferabliDataSDKDemo/**/*.{h,m,swift}"
  spec.swift_version = "5.0"
end
