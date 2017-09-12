# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'concurrent_io/version'

Gem::Specification.new do |spec|
  spec.name          = "concurrent_io"
  spec.version       = ConcurrentIO::VERSION
  spec.authors       = ["Alastair Pharo"]
  spec.email         = ["asppsa@gmail.com"]
  spec.summary       = %q{Concurrency-friendly layer for working with IO.  Based on concurrent-ruby}
  spec.description   = %q{This gem provides an concurrency-friendly setup for working with IO objects (especially sockets).  It is based on concurrent-ruby, and works with a number of select loop implementations}
  spec.homepage      = "https://github.com/asppsa/concurrent_io"
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 1.0"

  spec.add_development_dependency "concurrent-ruby-edge"
  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "nio4r", "~> 2.0"
  spec.add_development_dependency "eventmachine", "~> 1.0"
  spec.add_development_dependency "pry"
end
