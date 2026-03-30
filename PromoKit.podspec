Pod::Spec.new do |s|
  s.name     = 'PromoKit'
  s.version  = '0.0.2'
  s.license  = { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'A flexible framework for dynamically displaying different types of promotional content at runtime.'
  s.homepage = 'https://github.com/TimOliver/PromoKit'
  s.author   = 'Tim Oliver'
  s.source   = { :git => 'https://github.com/TimOliver/PromoKit.git', :tag => s.version }
  s.requires_arc = true
  s.swift_version = '5.9'
  s.ios.deployment_target = '12.0'
  s.default_subspecs = 'Core'

  s.subspec 'Core' do |core|
    core.source_files = [
      'PromoKit/PromoView.swift',
      'PromoKit/PromoProvider.swift',
      'PromoKit/PromoContentView.swift',
      'PromoKit/ContentViews/PromoContainerContentView.swift',
      'PromoKit/ContentViews/PromoTableListContentView.swift',
      'PromoKit/Providers/PromoAppRaterProvider.swift',
      'PromoKit/Providers/PromoCloudEventProvider.swift',
      'PromoKit/Providers/PromoNetworkTestProvider.swift',
      'PromoKit/Helpers/*.swift',
      'PromoKit/Internal/*.swift',
    ]
    core.frameworks = ['UIKit', 'CloudKit', 'Network']
  end

  s.subspec 'GoogleAds' do |ads|
    ads.source_files = [
      'PromoKit/ContentViews/PromoNativeAdContentView.swift',
      'PromoKit/Providers/PromoBannerAdProvider.swift',
      'PromoKit/Providers/PromoNativeAdProvider.swift',
    ]
    ads.dependency 'PromoKit/Core'
    ads.dependency 'Google-Mobile-Ads-SDK'
    ads.frameworks = ['UIKit']
  end
end
