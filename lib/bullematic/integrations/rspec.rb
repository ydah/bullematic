# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  module Integrations
    module RSpec
      class << self
        #: () -> void
        def setup
          ::RSpec.configure do |config|
            config.before(:each) do
              if Bullematic.enabled?
                Bullet.start_request if defined?(Bullet) && Bullet.enable?
                Bullematic::Fixer.clear
              end
            end

            config.after(:each) do
              if Bullematic.enabled? && defined?(Bullet) && Bullet.enable?
                Bullematic::Notifier.process_notifications if Bullet.notification?
                Bullet.end_request
              end
            end

            config.after(:suite) do
              Bullematic::Fixer.apply_fixes if Bullematic.configuration&.enabled && Bullematic.configuration&.auto_fix
            end
          end
        end
      end
    end
  end
end
