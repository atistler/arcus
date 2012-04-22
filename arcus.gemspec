# -*- encoding: utf-8 -*-
require File.expand_path('../lib/arcus/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["atistler"]
  gem.email         = ["atistler@gmail.com"]
  gem.description   = %q{API and client CLI tool for cloudstack}
  gem.summary       = %q{API and client CLI tool for cloudstack}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.name          = "arcus"
  gem.require_paths = ["lib"]
  gem.version       = Arcus::VERSION

  gem.add_dependency "active_support"
  gem.add_dependency "nori"
  gem.add_dependency "nokogiri"
  gem.add_dependency "cmdparse"
end
