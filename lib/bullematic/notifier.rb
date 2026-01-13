# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  class Notifier
    class << self
      #: () -> void
      def setup
        return unless defined?(Bullet)

        setup_notification_hook
      end

      #: () -> void
      def process_notifications
        return unless defined?(Bullet) && Bullet.notification?

        notifications = Bullet.send(:notification_collector)&.collection || {}

        notifications.each_value do |notification_set|
          notification_set.each do |notification|
            next unless notification.is_a?(Bullet::Notification::NPlusOneQuery)

            process_n_plus_one(notification)
          end
        end
      end

      private

      #: () -> void
      def setup_notification_hook
        Bullet::Notification::NPlusOneQuery.prepend(NotificationHook)
      end

      # @rbs notification: untyped
      # @rbs return: void
      def process_n_plus_one(notification)
        detection = Detection.new(
          type: :n_plus_one,
          base_class: notification.base_class,
          associations: notification.associations,
          call_stack: extract_call_stack(notification)
        )

        Fixer.queue(detection) if detection.fixable?
      end

      # @rbs notification: untyped
      # @rbs return: Array[String]
      def extract_call_stack(notification)
        notification.instance_variable_get(:@callers) || caller
      end
    end

    module NotificationHook
      # @rbs base_class: untyped
      # @rbs associations: untyped
      # @rbs path: untyped
      # @rbs return: void
      def initialize(base_class, associations, path = nil)
        super
        return unless Bullematic.enabled?

        detection = Detection.new(
          type: :n_plus_one,
          base_class: base_class,
          associations: associations,
          call_stack: caller
        )

        Fixer.queue(detection) if detection.fixable?
      end
    end
  end
end
