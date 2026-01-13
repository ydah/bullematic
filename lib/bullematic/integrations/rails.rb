# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  module Integrations
    class Railtie < ::Rails::Railtie
      initializer "bullematic.configure" do |_app|
        Bullematic.setup_bullet_hook if Rails.env.development? || Rails.env.test?
      end

      initializer "bullematic.middleware" do |app|
        app.middleware.use Bullematic::Middleware if Rails.env.development?
      end
    end
  end

  class Middleware
    # @rbs @app: untyped

    # @rbs app: untyped
    # @rbs return: void
    def initialize(app)
      @app = app
    end

    # @rbs env: Hash[String, untyped]
    # @rbs return: untyped
    def call(env)
      return @app.call(env) unless Bullematic.enabled?

      Bullematic::Fixer.clear

      response = @app.call(env)

      Bullematic::Fixer.apply_fixes if Bullematic.configuration&.auto_fix

      response
    end
  end
end
