# frozen_string_literal: true

require_relative "boot"
require "rails/all"

Bundler.require(*Rails.groups)
require "bullet"
require "bullematic"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f
    config.eager_load = false

    config.after_initialize do
      Bullet.enable = true
      Bullet.bullet_logger = true
    end
  end
end
