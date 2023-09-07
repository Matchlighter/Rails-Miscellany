# frozen_string_literal: true

require 'logger'
require 'yaml'
require 'database_cleaner'
require 'with_model'
require 'goldiloader'

require 'miscellany'

FileUtils.makedirs('log')

ActiveRecord::Base.logger = Logger.new('log/test.log')
ActiveRecord::Base.logger.level = Logger::DEBUG
ActiveRecord::Migration.verbose = false

db_adapter = ENV.fetch('ADAPTER', 'sqlite3')
db_config = YAML.safe_load(File.read('spec/db/database.yml'))
ActiveRecord::Base.establish_connection(db_config[db_adapter])

Goldiloader.globally_enabled = false

RSpec.configure do |config|
  config.extend WithModel

  config.order = 'random'

  config.before(:suite) do
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before do
    DatabaseCleaner.strategy = :transaction
  end

  config.before do
    DatabaseCleaner.start
  end

  config.after do
    DatabaseCleaner.clean
  end
end

puts "Testing with ActiveRecord #{ActiveRecord::VERSION::STRING}"
