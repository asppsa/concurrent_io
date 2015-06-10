# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'io_actors/version'

Gem::Specification.new do |spec|
  spec.name          = "io_actors"
  spec.version       = IOActors::VERSION
  spec.authors       = ["Alastair Pharo"]
  spec.email         = ["asppsa@gmail.com"]
  spec.summary       = %q{Some actor classes for working with IO.  Based on concurrent-ruby and nio4r}
  spec.description   = %q{This gem provides an actor-based framework for working with IO objects such as sockets.  It is based on concurrent-ruby and nio4r, and includes actors for reading, writing and selecting/reacting}
  spec.homepage      = "https://github.com/asppsa/io_actors"
  spec.license       = "Apache 2.0"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency "concurrent-ruby", "~> 0.7"
  spec.add_dependency "nio4r", "~> 1.0"

  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "nio4r", "~> 1.0"
end
