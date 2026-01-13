# frozen_string_literal: true

require "bundler/setup"

if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    add_filter "/spec/"
    add_filter "/gemfiles/"
  end
end

require "combustion"
Combustion.path = "spec/internal"
Combustion.initialize! :active_record, :action_controller do
  config.after_initialize do
    require "bullet"
    Bullet.enable = true
    Bullet.bullet_logger = true
    Bullet.raise = false
  end
end

require "rspec/rails"
require "database_cleaner/active_record"
require "factory_bot"
require "bullematic"
require "bullematic/integrations/rspec"

Dir[File.join(__dir__, "support", "**", "*.rb")].sort.each { |f| require f }

Bullematic::Integrations::RSpec.setup
Bullematic.setup_bullet_hook

unless defined?(ApplicationController)
  class ApplicationController < ActionController::Base
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/examples.txt"
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.include FactoryBot::Syntax::Methods

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
    FactoryBot.find_definitions

    schema_path = File.expand_path("internal/db/schema.rb", __dir__)
    if File.exist?(schema_path)
      ActiveRecord::Schema.verbose = false
      load schema_path
    end
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end

  config.before(:each) do
    if defined?(Bullet) && !Bullet.enable?
      Bullet.enable = true
    end
    Bullet.start_request if Bullet.enable?
    Bullematic::Fixer.clear if defined?(Bullematic::Fixer)
  end

  config.after(:each) do
    Bullet.end_request if Bullet.enable?
  end
end
