# Run `bundle exec appraisal install` after editing this file to regenerate
# the gemfiles under ./gemfiles. Each entry pins a Rails line plus the sqlite3
# version that line is compatible with; every other dependency is resolved by
# Bundler from the gemspec.

appraise 'rails-6.1' do
  gem 'rails', '~> 6.1.0'
  gem 'sqlite3', '~> 1.4'
end

appraise 'rails-7.0' do
  gem 'rails', '~> 7.0.0'
  gem 'sqlite3', '~> 1.4'
end

appraise 'rails-7.1' do
  gem 'rails', '~> 7.1.0'
  gem 'sqlite3', '~> 1.4'
end

appraise 'rails-7.2' do
  gem 'rails', '~> 7.2.0'
  # Rails 7.2 supports sqlite3 2.x, which (unlike the 1.x line) builds on Ruby 3.4.
  gem 'sqlite3', '~> 2.1'
end

appraise 'rails-8.0' do
  gem 'rails', '~> 8.0.0'
  gem 'sqlite3', '~> 2.1'
end

appraise 'rails-8.1' do
  gem 'rails', '~> 8.1.0'
  gem 'sqlite3', '~> 2.1'
end
