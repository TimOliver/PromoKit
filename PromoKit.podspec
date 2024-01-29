Pod::Spec.new do |s|
  s.name     = 'PromoKit'
  s.version  = '0.0.1'
  s.license  =  { :type => 'MIT', :file => 'LICENSE' }
  s.summary  = 'A flexible framework for dynamically displaying different types of promotional content (app announcements, mobile ads) at runtime.'
  s.homepage = 'https://github.com/TimOliver/PromoKit'
  s.author   = 'Tim Oliver'
  s.source   = { :git => 'https://github.com/TimOliver/PromoKit.git', :tag => s.version }
  s.source_files = 'PromoKit/**/*.{h,m,swift}'
  s.requires_arc = true
  s.ios.deployment_target   = '12.0'
end
