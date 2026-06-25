# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

begin
  require "miscellany/version"
  version = Miscellany::VERSION
rescue LoadError
  version = "0.0.0.docker"
end

Gem::Specification.new do |spec|
  spec.name          = "miscellany"
  spec.version       = version
  spec.authors       = ["Ethan Knapp"]
  spec.email         = ["eknapp@instructure.com"]

  spec.summary       = "Gem for a bunch of random, re-usable Rails Concerns & Helpers"
  spec.homepage      = "https://instructure.com"

  spec.files = Dir["{app,config,db,lib}/**/*", "README.md", "*.gemspec"]
  spec.test_files = Dir["spec/**/*"]
  spec.require_paths = ['lib']

  spec.add_dependency 'rails', '>= 5', '< 9.0'
  # csv stopped being a default gem in Ruby 3.4; BatchingCsvProcessor requires it.
  spec.add_dependency 'csv'
  # spec.add_dependency 'activerecord', '>= 5', '< 6.3'
  # spec.add_dependency 'activesupport', '>= 5', '< 6.3'

  spec.add_development_dependency 'rake'
  spec.add_development_dependency 'appraisal', '~> 2.4'
  spec.add_development_dependency 'database_cleaner', '>= 1.2'
  spec.add_development_dependency 'rspec', '~> 3'
  # Loosened so Rails 8 (which needs sqlite3 ~> 2.1) can resolve. Each
  # Appraisal pins the exact sqlite3 line its Rails version requires.
  spec.add_development_dependency 'sqlite3', '>= 1.3'
  spec.add_development_dependency 'with_model'
  spec.add_development_dependency 'goldiloader'
end
