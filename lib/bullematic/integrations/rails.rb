# rbs_inline: enabled
# frozen_string_literal: true

require "rack/body_proxy"

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

      status, headers, body = @app.call(env)
      [status, headers, Rack::BodyProxy.new(body) { capture_notifications(env) }]
    rescue StandardError
      capture_notifications(env)
      raise
    end

    private

    # @rbs env: Hash[String, untyped]
    # @rbs return: void
    def capture_notifications(env)
      if Bullematic.enabled? && defined?(Bullet)
        Bullematic::Notifier.process_notifications(context_id: env.object_id)
      end
    end
  end
end
