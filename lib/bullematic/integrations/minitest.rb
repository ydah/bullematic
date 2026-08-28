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
          @bullematic_request_started = false
          return unless Bullematic.enabled?

          if defined?(Bullet) && Bullet.enable?
            Bullet.start_request
            @bullematic_request_started = true
          end
        end

        #: () -> void
        def teardown
          begin
            if @bullematic_request_started
              begin
                if Bullematic.enabled? && Bullet.enable?
                  Bullematic::Notifier.process_notifications(context_id: object_id)
                end
              ensure
                Bullet.end_request
                @bullematic_request_started = false
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
