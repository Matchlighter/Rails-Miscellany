# coding: utf-8
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

begin
  require "advanced_ar/version"
  version = AdvancedAR::VERSION
rescue LoadError
  version = "0.0.0.docker"
end

Gem::Specification.new do |spec|
  spec.name          = "advanced_ar"
  spec.version       = version
  spec.authors       = ["Ethan Knapp"]
  spec.email         = ["eknapp@instructure.com"]

  spec.summary       = "Gem for adding advanced features into ActiveRecord"
  spec.homepage      = "https://instructure.com"

  spec.files = Dir["{app,config,db,lib}/**/*", "README.md", "*.gemspec"]
  spec.test_files = Dir["spec/**/*"]
  spec.require_paths = ['lib']

  spec.add_development_dependency "bundler", "~> 1.15"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "rspec-rails"
  spec.add_development_dependency "pg"
  spec.add_development_dependency "factory"
  spec.add_development_dependency "factory_girl_rails"
  spec.add_development_dependency "timecop"
  spec.add_development_dependency "webmock"
  spec.add_development_dependency "sinatra", ">= 0"
  spec.add_development_dependency "shoulda-matchers"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "pry"
  spec.add_development_dependency "pry-nav"
  spec.add_development_dependency "rubocop"

  spec.add_dependency "rails", ">= 5"
  spec.add_dependency "activerecord-import"
end
