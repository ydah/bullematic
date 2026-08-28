# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  module Integrations
    class Railtie < ::Rails::Railtie
      BULLET_MIDDLEWARE_INITIALIZER = Bullet::BulletRailtie.initializers.find do |initializer|
        initializer.name.start_with?("bullet.")
      end&.name

      initializer "bullematic.configure" do |_app|
        Bullematic.setup_bullet_hook if Rails.env.development? || Rails.env.test?
      end

      initializer "bullematic.middleware", after: BULLET_MIDDLEWARE_INITIALIZER do |app|
        next unless Rails.env.development?

        if defined?(Bullet::Rack)
          app.middleware.insert_after Bullet::Rack, Bullematic::Middleware
        else
          app.middleware.use Bullematic::Middleware
        end
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
      @app.call(env)
    ensure
      capture_notifications(env)
    end

    private

    # @rbs env: Hash[String, untyped]
    # @rbs return: void
    def capture_notifications(env)
      if Bullematic.enabled? && EvidenceStore.recording? && defined?(Bullet)
        Bullematic::Notifier.process_notifications(context_id: env.object_id)
      end
    end
  end
end
