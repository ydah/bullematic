# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  module Integrations
    module RSpec
      class << self
        #: () -> void
        def setup
          ::RSpec.configure do |config|
            config.before(:suite) do
              Bullematic::Fixer.clear
            end

            config.before(:each) do
              if Bullematic.enabled?
                Bullet.start_request if defined?(Bullet) && Bullet.enable?
              end
            end

            config.after(:each) do |example|
              if Bullematic.enabled? && defined?(Bullet) && Bullet.enable?
                begin
                  Bullematic::Notifier.process_notifications(context_id: example.id)
                ensure
                  Bullet.end_request
                end
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
