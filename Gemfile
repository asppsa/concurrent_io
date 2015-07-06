source 'https://rubygems.org'

# Specify your gem's dependencies in io_actors.gemspec
gemspec

# An important bugfix
gem 'concurrent-ruby', '0.8.0', :github => 'ruby-concurrency/concurrent-ruby', :tag => '0c0177bb430af26f085038299169fd1762270eec'

# Currently only available from github
gem "ffi-libevent", :github => 'asppsa/ffi-libevent'

# Makes MRI snappier
platform :mri do
  gem "concurrent-ruby-ext", "0.8.0"
end
