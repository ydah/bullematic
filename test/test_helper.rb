# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["BULLEMATIC"] = "1"

require_relative "dummy/config/environment"
require "rails/test_help"
require "bullematic"
require "bullematic/integrations/minitest"

schema_file = File.expand_path("dummy/db/schema.rb", __dir__)
if File.exist?(schema_file)
  ActiveRecord::Schema.verbose = false
  load schema_file
end

class ActiveSupport::TestCase
  fixture_root = File.expand_path("fixtures", __dir__)
  if respond_to?(:fixture_paths=)
    self.fixture_paths = [fixture_root]
  else
    self.fixture_path = fixture_root
  end
  fixtures :all
end

class ActionDispatch::IntegrationTest
  include ActiveRecord::TestFixtures
  if respond_to?(:fixture_paths=)
    self.fixture_paths = ActiveSupport::TestCase.fixture_paths
  else
    self.fixture_path = ActiveSupport::TestCase.fixture_path
  end
  fixtures :all
end
