# -*- encoding: utf-8 -*-
require File.expand_path('../lib/nimbus/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["atistler"]
  gem.email         = ["atistler@gmail.com"]
  gem.description   = %q{API and client CLI tool for cloudstack}
  gem.summary       = %q{API and client CLI tool for cloudstack}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "nimbus"
  gem.require_paths = ["lib"]
  gem.version       = Nimbus::VERSION
end
