source "https://rubygems.org"

git_source(:github) {|repo_name| "https://github.com/#{repo_name}" }

gemspec

# The adapter the specs run against. Declared here rather than as a gemspec
# development dependency so it does not collide with the pins in gemfiles/, which
# each hold the sqlite3 version their Rails line supports.
gem "sqlite3"
