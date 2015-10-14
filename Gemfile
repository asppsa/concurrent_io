source 'https://rubygems.org'

# Specify your gem's dependencies in io_actors.gemspec
gemspec

# An important bugfix
gem 'concurrent-ruby', :github => 'ruby-concurrency/concurrent-ruby'

# Currently only available from github
gem "ffi-libevent", :github => 'asppsa/ffi-libevent'

# Makes MRI snappier
platform :mri do
  gem "concurrent-ruby-ext"
end
