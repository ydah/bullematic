# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  module Integrations
    module Minitest
      class << self
        #: () -> void
        def setup
          ::Minitest.after_run do
            Bullematic::Fixer.apply_fixes if Bullematic.configuration&.enabled && Bullematic.configuration&.auto_fix
          end
        end
      end

      module TestHelper
        #: () -> void
        def setup
          super
          return unless Bullematic.enabled?

          Bullet.start_request if defined?(Bullet) && Bullet.enable?
          Bullematic::Fixer.clear
        end

        #: () -> void
        def teardown
          if Bullematic.enabled? && defined?(Bullet) && Bullet.enable?
            Bullematic::Notifier.process_notifications if Bullet.notification?
            Bullet.end_request
          end
          super
        end
      end
    end
  end
end
