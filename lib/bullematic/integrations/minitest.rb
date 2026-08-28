# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  module Integrations
    module Minitest
      class << self
        #: () -> void
        def setup
          Bullematic::Fixer.clear

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
        end

        #: () -> void
        def teardown
          begin
            if Bullematic.enabled? && defined?(Bullet) && Bullet.enable?
              begin
                Bullematic::Notifier.process_notifications(context_id: object_id) if Bullet.notification?
              ensure
                Bullet.end_request
              end
            end
          ensure
            super
          end
        end
      end
    end
  end
end
