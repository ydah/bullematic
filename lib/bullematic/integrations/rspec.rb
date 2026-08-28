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

            config.before(:each) do |example|
              example.metadata[:bullematic_request_started] = false
              if Bullematic.enabled?
                if defined?(Bullet) && Bullet.enable?
                  Bullet.start_request
                  example.metadata[:bullematic_request_started] = true
                end
              end
            end

            config.after(:each) do |example|
              if example.metadata.delete(:bullematic_request_started)
                begin
                  if Bullematic.enabled? && Bullet.enable?
                    Bullematic::Notifier.process_notifications(context_id: example.id)
                  end
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
