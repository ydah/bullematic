# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
ENV["BULLEMATIC"] = "1"

require_relative "dummy/config/environment"
require "rails/test_help"
require "bullematic"
require "bullematic/integrations/minitest"

class ActiveSupport::TestCase
  fixtures :all
end
