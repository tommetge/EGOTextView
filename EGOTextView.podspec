Pod::Spec.new do |s|

  s.name         = "EGOTextView"
  s.version      = "1.0.0"
  s.summary      = "A drop in replacement for UITextView with support for attributed strings"

  s.description  = <<-DESC
                   EGOTextView is a complete drop in replacement for UITextView created by
                   enormego, that adds support for Rich Text Editing.

                   EGOTextView is tested to work with with iPhone OS 5.0 and newer.
                   DESC

  s.homepage     = "https://github.com/enormego/EGOTextView"
  s.license      = 'MIT'
  s.author       = { "tom metge" => "tom@accident-prone.com" }
  s.platform     = :ios, '5.0'
  s.source       = { :git => "https://github.com/tommetge/EGOTextView.git", :tag => "1.0.0" }
  s.source_files  = 'EGOTextView', 'EGOTextView/**/*.{h,m}'
  s.public_header_files = 'EGOTextView/**/*.h'
  s.resources = "EGOTextView/Resources/*.png"
  s.requires_arc = true
  s.frameworks = 'CoreText', 'CoreGraphics', 'QuartzCore', 'MobileCoreServices'

end
