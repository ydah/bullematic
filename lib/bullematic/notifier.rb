# rbs_inline: enabled
# frozen_string_literal: true

module Bullematic
  class Notifier
    class << self
      #: () -> void
      def setup
        return if compatible?

        Bullematic.configuration&.logger&.warn(
          "[Bullematic] Disabled: Bullet notification API is unavailable"
        )
      end

      #: () -> bool
      def compatible?
        return false unless defined?(Bullet)

        Bullet.respond_to?(:notification?, true) &&
          Bullet.respond_to?(:notification_collector, true) &&
          !defined?(Bullet::Notification::NPlusOneQuery).nil?
      end

      # @rbs context_id: untyped
      # @rbs return: void
      def process_notifications(context_id: nil)
        return unless compatible? && Bullet.notification?

        context_id ||= Object.new.object_id

        config = Bullematic.configuration
        if config&.logger && config.debug
          config.logger.debug "[Bullematic] Processing notifications..."
        end

        collector = Bullet.send(:notification_collector)
        return unless collector&.respond_to?(:collection)

        notifications = collector.collection

        if config&.logger && config.debug
          config.logger.debug "[Bullematic] Notifications collection type: #{notifications.class}"
          config.logger.debug "[Bullematic] Notifications count: #{notifications.respond_to?(:size) ? notifications.size : 'unknown'}"
        end

        n_plus_one_count = 0
        unused_eager_loading_count = 0

        case notifications
        when Hash
          notifications.each_value do |notification_set|
            notification_set = [notification_set] unless notification_set.respond_to?(:each)
            notification_set.each do |notification|
              type = process_notification(notification, context_id)
              n_plus_one_count += 1 if type == :n_plus_one
              unused_eager_loading_count += 1 if type == :unused_eager_loading
            end
          end
        when Enumerable
          notifications.each do |notification|
            type = process_notification(notification, context_id)
            n_plus_one_count += 1 if type == :n_plus_one
            unused_eager_loading_count += 1 if type == :unused_eager_loading
          end
        end

        if config&.logger && config.debug
          config.logger.debug "[Bullematic] Processed #{n_plus_one_count} N+1 notifications"
          config.logger.debug "[Bullematic] Processed #{unused_eager_loading_count} UnusedEagerLoading notifications"
          config.logger.debug "[Bullematic] Detection queue size: #{Fixer.detection_queue.size}"
        end
      end

      private

      # @rbs notification: untyped
      # @rbs context_id: untyped
      # @rbs return: Symbol?
      def process_notification(notification, context_id)
        if notification.is_a?(Bullet::Notification::NPlusOneQuery)
          process_n_plus_one(notification, context_id)
          :n_plus_one
        elsif defined?(Bullet::Notification::UnusedEagerLoading) &&
              notification.is_a?(Bullet::Notification::UnusedEagerLoading)
          process_unused_eager_loading(notification, context_id)
          :unused_eager_loading
        end
      rescue StandardError => error
        Bullematic.configuration&.logger&.warn(
          "[Bullematic] Skipped invalid Bullet notification: #{error.message}"
        )
        nil
      end

      # @rbs notification: untyped
      # @rbs context_id: untyped
      # @rbs return: void
      def process_n_plus_one(notification, context_id)
        detection = Detection.new(
          type: :n_plus_one,
          base_class: notification.base_class,
          associations: notification.associations,
          call_stack: extract_call_stack(notification),
          context_id: context_id
        )

        config = Bullematic.configuration
        if config&.logger && config.debug
          config.logger.debug "[Bullematic] N+1 Detection created:"
          config.logger.debug "  Base class: #{notification.base_class}"
          config.logger.debug "  Associations: #{notification.associations.inspect}"
          config.logger.debug "  Source file: #{detection.source_file}"
          config.logger.debug "  Line number: #{detection.line_number}"
          config.logger.debug "  Method name: #{detection.method_name}"
          config.logger.debug "  Call stack: #{detection.call_stack.inspect}"
          config.logger.debug "  Fixable: #{detection.fixable?}"
          config.logger.debug "  Queue size before: #{Fixer.detection_queue.size}"
        end

        if detection.fixable?
          Fixer.queue(detection)
          if config&.logger && config.debug
            config.logger.debug "  Queue size after: #{Fixer.detection_queue.size}"
          end
        end
      end

      # @rbs notification: untyped
      # @rbs context_id: untyped
      # @rbs return: void
      def process_unused_eager_loading(notification, context_id)
        config = Bullematic.configuration
        return unless config

        if EvidenceStore.recording?
          detection = Detection.new(
            type: :unused_eager_loading,
            base_class: notification.base_class,
            associations: notification.associations,
            call_stack: extract_call_stack(notification),
            context_id: context_id
          )
          Fixer.queue(detection) if detection.fixable?
        end

        if config.logger && config.debug
          config.logger.debug "[Bullematic] UnusedEagerLoading detected:"
          config.logger.debug "  Base class: #{notification.base_class}"
          config.logger.debug "  Unused associations: #{notification.associations.inspect}"
        end
      end

      # @rbs notification: untyped
      # @rbs return: Array[String]
      def extract_call_stack(notification)
        callers = notification.instance_variable_get(:@callers)
        return callers if callers && !callers.empty?

        config = Bullematic.configuration
        return caller unless config

        call_stacks = Bullet::Detector::Association.send(:call_stacks) if defined?(Bullet::Detector::Association)
        stacks =
          if call_stacks&.respond_to?(:registry)
            call_stacks.registry.values
          else
            []
          end

        matching = stacks.find do |stack|
          frames = Array(stack) #: Array[untyped]
          frames.any? do |frame|
            config.target_paths.any? { |path| frame.is_a?(String) && frame.include?(path) }
          end
        end

        matching || caller
      end
    end

  end
end
