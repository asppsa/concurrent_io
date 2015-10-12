source 'https://rubygems.org'

# Specify your gem's dependencies in io_actors.gemspec
gemspec

# An important bugfix
gem 'concurrent-ruby', '1.0.0.pre4', :github => 'ruby-concurrency/concurrent-ruby'
#gem 'concurrent-ruby-edge'

# Currently only available from github
gem "ffi-libevent", :github => 'asppsa/ffi-libevent'

# Makes MRI snappier
platform :mri do
  gem "concurrent-ruby-ext"
end
